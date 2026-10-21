-- tests/Forever/wowsims_apl_spec.lua (wowsims packs plan, Task 4): the APL translator's rules on a small APL in
-- wowsims/forever's JSON shape (MIT) with a stand-in class context.
local apl = require("tools.wowsims.apl")

local function ctx(r, player)
    local kit = {
        abilities = {
            strike = { key = "strike", id = 100, copy = { 101 }, gcd = "spell" },
            big_hit = { key = "big_hit", id = 200, gcd = "spell" },
            roar = { key = "roar", id = 300, gcd = "off" },
            dot = { key = "dot", id = 400, gcd = "spell" },
            trinket = { key = "trinket", id = -1, item = 555, gcd = "off" },
            stone = { key = "stone", id = -2, items = { 556, 557 }, gcd = "off" },
        },
        auras = {
            dot = { id = 400 },
            fury = { id = 900 },
            stance = { id = 910 },
            proc = { id = 960, icd = 10, icdSpell = 950 },
            sunder = { id = 970, max_stack = 5 },
        },
        talents = { furious = { 2, 900, 1 }, cuts = { 1, 950, 1 } },
    }
    return apl.context(kit, r or { executePhase = "execute_phase", focus = { strike = 1 } }, nil, player)
end
local function cast(id, cond)
    return { action = { castSpell = { spellId = { spellId = id } }, condition = cond } }
end
local function cmp(op, lhs, rhs)
    return { cmp = { op = op, lhs = lhs, rhs = rhs } }
end
local function const(v)
    return { const = { val = v } }
end
local function AND(...)
    return { ["and"] = { vals = { ... } } }
end
local function OR(...)
    return { ["or"] = { vals = { ... } } }
end
local function NOT(x)
    return { ["not"] = { val = x } }
end
-- The truth table's reads: A (big_hit) ready, B (dot) up, the execute phase.
local ready = { spellIsReady = { spellId = { spellId = 200 } } }
local up = { auraIsActive = { auraId = { spellId = 400 } } }
local E = { isExecutePhase = { threshold = "E20" } }
-- The truth table's trees.
local trees = {
    ready,
    NOT(ready),
    AND(ready, E),
    OR(ready, E),
    AND(NOT(ready), E),
    OR(NOT(ready), E),
    NOT(AND(ready, E)),
    NOT(OR(ready, up)),
    AND(OR(ready, up), E),
    OR(AND(ready, up), E),
    AND(OR(ready, up), OR(ready, E)),
    OR(NOT(AND(ready, E)), up),
    NOT(AND(OR(ready, up), NOT(E))),
    -- one key read by several terms of a group: its guard tests the key once
    AND(OR(ready, ready), E),
    OR(AND(OR(ready, ready), NOT(ready)), E),
    NOT(AND(OR(ready, NOT(ready)), OR(up, up))),
}

describe("the wowsims APL translator", function()
    it("keeps the order, maps keys, flags off-GCD and focus, and guards another ability's reads", function()
        local text, omitted = apl.translate({
            prepullActions = { { action = cast(300).action, doAtValue = const("-1s") } },
            priorityList = {
                cast(100, cmp("OpGe", { spellTimeToReady = { spellId = { spellId = 200 } } }, const("1.5s"))),
                cast(200, { ["not"] = { val = { auraIsActive = { auraId = { spellId = 900 } } } } }),
                cast(400, cmp("OpLe", { dotRemainingTime = { spellId = { spellId = 400 } } }, const("300ms"))),
                { action = { castSpell = { spellId = { itemId = 555 } } } },
                cast(101, { isExecutePhase = { threshold = "E20" } }),
            },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions.precombat=roar,use_off_gcd=1,prepull_at=1",
                "actions=strike,focus=1,if=(!action.big_hit.known|cooldown.big_hit.remains>=1.5)",
                "actions+=/big_hit,if=(!talent.furious.enabled|!buff.fury.up)",
                "actions+=/dot,if=debuff.dot.remains<=0.3",
                "actions+=/trinket,use_off_gcd=1",
                "actions+=/strike,focus=1,if=execute_phase",
            }, "\n"),
            text
        )
        assert.are.same({}, omitted)
    end)

    it("puts the recipe's levelingFirst lines before the APL's own and its leveling lines after them", function()
        local text = apl.translate(
            { priorityList = { cast(100) } },
            ctx({ leveling = { "roar,if=!action.big_hit.known" }, levelingFirst = { "dot,if=!buff.dot.up" } })
        )
        assert.are.equal(
            table.concat(
                { "actions=dot,if=!buff.dot.up", "actions+=/strike", "actions+=/roar,if=!action.big_hit.known" },
                "\n"
            ),
            text
        )
    end)

    it("puts each recipe extra line before the first line of its anchor action, the rest in order", function()
        local text = apl.translate(
            { priorityList = { cast(300), cast(100), cast(200), cast(100) } },
            ctx({ extra = { { before = "strike", line = "dot,if=buff.fury.up" } } })
        )
        assert.are.equal(
            table.concat({
                "actions=roar,use_off_gcd=1",
                "actions+=/dot,if=buff.fury.up",
                "actions+=/strike",
                "actions+=/big_hit",
                "actions+=/strike",
            }, "\n"),
            text
        )
        assert.has_error(function()
            apl.translate({ priorityList = { cast(100) } }, ctx({ extra = { { before = "big_hit", line = "dot" } } }))
        end, "extra: no big_hit line in actions")
    end)

    it("lists a recipe setting a line reads after the APL's own toggles, with its description", function()
        local r = {
            leveling = { "roar,if=settings.roar_filler&!action.big_hit.known" },
            settings = {
                roar_filler = { default = true, desc = "Roar fills the GCD" },
                unread = { default = false, desc = "no line reads it" },
            },
        }
        local text, _, toggles = apl.translate({
            priorityList = { cast(100, { actionGroupUsed = { name = "Big ON/OFF" } }) },
            groups = { { name = "Big ON/OFF", actions = { { action = {} } } } },
        }, ctx(r))
        assert.are.equal(
            "actions=strike,if=settings.wowsims_big\nactions+=/roar,if=settings.roar_filler&!action.big_hit.known",
            text
        )
        assert.are.same({
            { "wowsims_big", false, "wowsims ON/OFF group" },
            { "roar_filler", true, "Roar fills the GCD" },
        }, toggles)
    end)

    it(
        "schedules the prepull: prepull_at from doAtValue, earliest first, 0 at the pull, no guard of its own",
        function()
            local function at(id, v, cond)
                local e = cast(id, cond)
                e.doAtValue = type(v) == "table" and v or (v and const(v))
                return e
            end
            local text, omitted = apl.translate({
                prepullActions = {
                    at(100, "-1.5s"),
                    at(300, "-10s"),
                    at(200, "-1.5s", { ["not"] = { val = { auraIsActive = { auraId = { spellId = 900 } } } } }),
                    at(400, "0s"),
                    at(400),
                    at(100, "2s"),
                    at(200, { variableRef = { name = "x" } }),
                },
            }, ctx())
            assert.are.equal(
                table.concat({
                    "actions.precombat=roar,use_off_gcd=1,prepull_at=10",
                    "actions.precombat+=/strike,prepull_at=1.5", -- pre-pull lines carry no tier
                    "actions.precombat+=/big_hit,prepull_at=1.5,if=(!talent.furious.enabled|!buff.fury.up)",
                    "actions.precombat+=/dot,prepull_at=0",
                }, "\n"),
                text
            )
            assert.are.same({
                "precombat #5: no doAtValue",
                "precombat #6: doAtValue after the pull",
                "precombat #7: doAtValue not a constant",
            }, omitted)
        end
    )

    it("gives a group called from the prepull its caller's prepull_at (its own entries' order kept)", function()
        local call = { action = { groupReference = { groupName = "Move" } }, doAtValue = const("-0.9s") }
        local text, omitted = apl.translate({
            prepullActions = { call, { action = cast(300).action, doAtValue = const("-2s") } },
            priorityList = { cast(400) },
            groups = { { name = "Move", actions = { cast(200), cast(100) } } },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions.precombat=roar,use_off_gcd=1,prepull_at=2",
                "actions.precombat+=/call_action_list,name=move",
                "actions=dot",
                "actions.move=big_hit,prepull_at=0.9",
                "actions.move+=/strike,prepull_at=0.9",
            }, "\n"),
            text
        )
        assert.are.same({}, omitted)
    end)

    it("folds constants, omits hidden and unsupported entries, inlines variables, makes toggles settings", function()
        local text, omitted, toggles = apl.translate({
            priorityList = {
                { hide = true, action = { groupReference = { groupName = "Big ON/OFF" } } },
                { action = { groupReference = { groupName = "Weave ON/OFF" } } },
                cast(100, { ["and"] = { vals = { { actionGroupUsed = { name = "Big ON/OFF" } }, const("true") } } }),
                cast(200, {
                    ["or"] = {
                        vals = {
                            const("false"),
                            { auraIsKnown = { sourceUnit = { type = "Pet" }, auraId = { spellId = 900 } } },
                        },
                    },
                }),
                cast(300, { variableRef = { name = "Low" } }),
                { action = { wait = {} } },
                cast(999),
                { action = { groupReference = { groupName = "Opener" } } },
            },
            groups = {
                { name = "Big ON/OFF", actions = { { action = {} } } },
                { name = "Weave ON/OFF", actions = { { action = {} } } },
                { name = "Opener", actions = { cast(400) } },
            },
            valueVariables = { { name = "Low", value = cmp("OpLt", { currentRage = {} }, const("30")) } },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions=strike,focus=1,if=settings.wowsims_big",
                "actions+=/roar,use_off_gcd=1,if=rage.current<30",
                "actions+=/call_action_list,name=opener",
                "actions.opener=dot",
            }, "\n"),
            text
        )
        assert.are.same(
            { "default #1: hidden", "default #4: never", "default #6: wait", "default #7: spell 999" },
            omitted
        )
        -- Weave is a switch no emitted line reads: not listed (ruling L14)
        assert.are.same({ { "wowsims_big", false, "wowsims ON/OFF group" } }, toggles)
    end)

    it("reads auraIsKnown as registered on Self or the target; another unit's or player's is false", function()
        local function known(id, unit)
            return { auraIsKnown = { sourceUnit = unit and { type = unit } or nil, auraId = { spellId = id } } }
        end
        local text, omitted = apl.translate({
            priorityList = {
                cast(100, known(900)), -- the talent's aura
                cast(100, known(950)), -- a talent's spell, no aura
                cast(100, known(200, "Self")), -- an ability's
                cast(100, known(910)), -- an aura no talent or ability owns
                cast(100, known(951)), -- the recipe maps it to a talent's key
                cast(100, known(999)), -- nothing registers it
                cast(100, known(910, "CurrentTarget")), -- the target's: the same path
                cast(100, known(910, "Pet")),
                cast(100, { auraIsKnown = { auraId = { spellId = 200, tag = -1 } } }), -- another player's
                -- another player's aura is nil (never registered): dropped, as wowsims drops it
                cast(100, { auraIsActive = { auraId = { spellId = 910, tag = -1 } } }),
                cast(100, {
                    ["and"] = {
                        vals = {
                            { spellIsKnown = { spellId = { spellId = 200 } } },
                            { auraIsActive = { auraId = { spellId = 910, tag = -1 } } },
                        },
                    },
                }),
                cast(100, cmp("OpGt", { auraRemainingTime = { auraId = { spellId = 910, tag = -1 } } }, const("2s"))),
            },
        }, ctx({ map = { [951] = "cuts" } }))
        assert.are.equal(
            table.concat({
                "actions=strike,if=talent.furious.enabled",
                "actions+=/strike,if=talent.cuts.enabled",
                "actions+=/strike,if=action.big_hit.known",
                "actions+=/strike",
                "actions+=/strike,if=talent.cuts.enabled",
                "actions+=/strike",
                "actions+=/strike",
                "actions+=/strike,if=action.big_hit.known",
                "actions+=/strike",
            }, "\n"),
            text
        )
        assert.are.same({ "default #6: never", "default #8: never", "default #9: never" }, omitted)
    end)

    it(
        "reads auraIcdIsReady as the declaring aura's icd_ready, by its ID or its proc trigger's (a talent's: guarded)",
        function()
            local function icd(id)
                return { auraIcdIsReady = { auraId = { spellId = id }, includeReactionTime = true } }
            end
            local text, omitted = apl.translate({
                priorityList = {
                    cast(100, icd(960)), -- the proc aura's own ID
                    cast(100, { ["and"] = { vals = { icd(950), const("true") } } }), -- its trigger, a talent's spell
                    cast(100, { ["or"] = { vals = { icd(950), { auraIsActive = { auraId = { spellId = 910 } } } } } }),
                    cast(100, icd(910)), -- an aura declaring no icd
                    cast(
                        100,
                        { auraIcdIsReady = { sourceUnit = { type = "CurrentTarget" }, auraId = { spellId = 960 } } }
                    ),
                },
            }, ctx())
            assert.are.equal(
                table.concat({
                    "actions=strike,focus=1,if=buff.proc.icd_ready",
                    "actions+=/strike,focus=1,if=(!talent.cuts.enabled|buff.proc.icd_ready)",
                    "actions+=/strike,focus=1,if=((talent.cuts.enabled&buff.proc.icd_ready)|buff.stance.up)",
                }, "\n"),
                text
            )
            assert.are.same(
                { "default #4: auraIcdIsReady 910", "default #5: auraIcdIsReady of CurrentTarget" },
                omitted
            )
        end
    )

    it(
        "reads auraShouldRefresh as remains within the overlap (or short of max stacks), cancelAura, autoSwingTime",
        function()
            local function refresh(id, unit, overlap)
                return {
                    auraShouldRefresh = {
                        sourceUnit = unit and { type = unit } or nil,
                        auraId = { spellId = id },
                        maxOverlap = overlap and const(overlap) or nil,
                    },
                }
            end
            local text, omitted = apl.translate({
                priorityList = {
                    cast(400, refresh(400, "CurrentTarget", "6s")), -- its own aura: unguarded
                    cast(100, refresh(970)), -- the target's by default; a stacking aura
                    cast(100, refresh(400, "Self")), -- another ability's aura: guarded
                    { action = { cancelAura = { auraId = { spellId = 910 } } } },
                    cast(100, cmp("OpGt", { autoSwingTime = { autoType = "OffHand" } }, const("0s"))),
                    cast(100, cmp("OpGt", { autoSwingTime = { autoType = "Ranged" } }, const("0s"))),
                    cast(100, refresh(910)), -- no exclusive effect declared
                },
            }, ctx({ focus = { strike = 1 }, exclusive = { [400] = true, [970] = true } }))
            assert.are.equal(
                table.concat({
                    "actions=dot,if=debuff.dot.remains<=6",
                    "actions+=/strike,focus=1,if=(debuff.sunder.remains<=0|debuff.sunder.stack<5)",
                    "actions+=/strike,focus=1,if=(!action.dot.known|buff.dot.remains<=0)",
                    "actions+=/cancel_buff,buff_name=stance",
                    "actions+=/strike,focus=1,if=offhand_speed>0",
                }, "\n"),
                text
            )
            assert.are.same(
                { "default #6: autoSwingTime", "default #7: auraShouldRefresh 910 (no exclusive effect declared)" },
                omitted
            )
        end
    )

    it("reads percents 0-100, Go durations in seconds, a Target's aura as a debuff, an item list", function()
        local text = apl.translate({
            priorityList = {
                cast(100, cmp("OpGt", { currentManaPercent = {} }, const("10%"))),
                cast(100, cmp("OpLt", { remainingTime = {} }, const("2m"))),
                cast(100, cmp("OpLt", { gcdTimeToReady = {} }, const("1m30.5s"))),
                cast(100, {
                    auraIsActive = { sourceUnit = { type = "Target" }, auraId = { spellId = 400 } },
                }),
                { action = { castSpell = { spellId = { itemId = 557 } } } },
            },
        }, ctx({}))
        assert.are.equal(
            table.concat({
                "actions=strike,if=mana.pct>10",
                "actions+=/strike,if=fight_remains<120",
                "actions+=/strike,if=gcd.remains<90.5",
                "actions+=/strike,if=(!action.dot.known|debuff.dot.up)",
                "actions+=/stone,use_off_gcd=1",
            }, "\n"),
            text
        )
    end)

    it("reads a percent constant as N only against a percent read, N/100 in math or against anything else", function()
        local at = { variableRef = { name = "Execute at" } }
        local function math(op, lhs, rhs)
            return { math = { op = op, lhs = lhs, rhs = rhs } }
        end
        local text = apl.translate({
            valueVariables = { { name = "Execute at", value = const("35%") } },
            priorityList = {
                cast(100, cmp("OpLe", const("20%"), { currentHealthPercent = {} })), -- either side
                cast(100, cmp("OpLt", { currentHealthPercent = {} }, at)), -- a variable, still the direct operand
                -- wowsims's Demonology "In execute": the fight's elapsed plus remaining time scaled by the fraction
                cast(
                    100,
                    cmp(
                        "OpLe",
                        math(
                            "OpSub",
                            { remainingTime = {} },
                            math("OpMul", math("OpAdd", { currentTime = {} }, { remainingTime = {} }), at)
                        ),
                        const("0")
                    )
                ),
                cast(100, cmp("OpGt", { currentManaPercent = {} }, math("OpAdd", const("10%"), const("5")))),
                cast(100, cmp("OpLt", { currentRage = {} }, const("50%"))), -- not a percent read
            },
        }, ctx({}))
        assert.are.equal(
            table.concat({
                "actions=strike,if=20<=health.pct",
                "actions+=/strike,if=health.pct<35",
                "actions+=/strike,if=(fight_remains-((time+fight_remains)*0.35))<=0",
                "actions+=/strike,if=mana.pct>(0.1+5)",
                "actions+=/strike,if=rage.current<0.5",
            }, "\n"),
            text
        )
    end)

    it(
        "writes min / max over the terms wowsims keeps: an unlearned term dropped at run time, nil when all are",
        function()
            local function MIN(...)
                return { min = { vals = { ... } } }
            end
            local function MAX(...)
                return { max = { vals = { ... } } }
            end
            local dot = { dotRemainingTime = { spellId = { spellId = 400 } } }
            local hit = { spellTimeToReady = { spellId = { spellId = 200 } } }
            local gone = { auraRemainingTime = { auraId = { spellId = 12345 } } } -- nothing maps it: nil (rule 12)
            local text, omitted = apl.translate({
                priorityList = {
                    cast(100, cmp("OpLt", MIN(dot, hit), const("3"))), -- two terms, each may be nil
                    cast(100, cmp("OpGt", MAX({ currentRage = {} }, dot, const("5")), const("4"))), -- three, one never nil
                    cast(100, cmp("OpLt", MIN({ currentRage = {} }, gone), const("5"))), -- a dropped term
                    cast(100, cmp("OpLt", MIN(gone, {}), const("5"))), -- all dropped: nil, so the line is unconditional
                },
            }, ctx({}))
            assert.are.equal(
                table.concat({
                    "actions=strike,if=(!(action.dot.known|action.big_hit.known)|min((action.dot.known&debuff.dot.remains),(action.big_hit.known&cooldown.big_hit.remains))<3)",
                    "actions+=/strike,if=max(rage.current,(action.dot.known&debuff.dot.remains),5)>4",
                    "actions+=/strike,if=rage.current<5",
                    "actions+=/strike",
                }, "\n"),
                text
            )
            assert.are.same({
                "default #3: dropped the unresolved aura 12345 (its branch only)",
                "default #4: dropped the unresolved aura 12345 (its branch only)",
            }, omitted)
        end
    )

    it(
        "guards a read so an unknown ability drops its term: true in an and, false in an or, flipped by a not",
        function()
            local rage = cmp("OpGt", { currentRage = {} }, const("10"))
            local text = apl.translate({
                priorityList = {
                    cast(100, { ["or"] = { vals = { ready, rage } } }),
                    cast(100, { ["and"] = { vals = { ready, rage, {} } } }),
                    cast(100, { ["or"] = { vals = { { ["not"] = { val = ready } }, rage } } }),
                    cast(100, { ["not"] = { val = { ["or"] = { vals = { up, {}, rage } } } } }),
                    cast(100, { ["and"] = { vals = { { ["not"] = { val = ready } }, rage } } }),
                    -- a group whose every term reads an unlearned ability is nil as a whole, and dropped
                    cast(100, { ["and"] = { vals = { { ["or"] = { vals = { ready, up } } }, rage } } }),
                    cast(100, { ["or"] = { vals = { { ["and"] = { vals = { ready, up } } }, rage } } }),
                    -- a group whose terms all read one ability: that ability's guard, its test once
                    cast(100, AND(OR(ready, ready), rage)),
                },
            }, ctx({}))
            assert.are.equal(
                table.concat({
                    "actions=strike,if=((action.big_hit.known&cooldown.big_hit.ready)|rage.current>10)",
                    "actions+=/strike,if=((!action.big_hit.known|cooldown.big_hit.ready)&rage.current>10)",
                    "actions+=/strike,if=((action.big_hit.known&!cooldown.big_hit.ready)|rage.current>10)",
                    "actions+=/strike,if=!((action.dot.known&buff.dot.up)|rage.current>10)",
                    "actions+=/strike,if=((!action.big_hit.known|!cooldown.big_hit.ready)&rage.current>10)",
                    "actions+=/strike,if=((!(action.big_hit.known|action.dot.known)|((action.big_hit.known&cooldown.big_hit.ready)|(action.dot.known&buff.dot.up)))&rage.current>10)",
                    "actions+=/strike,if=(((action.big_hit.known|action.dot.known)&((!action.big_hit.known|cooldown.big_hit.ready)&(!action.dot.known|buff.dot.up)))|rage.current>10)",
                    "actions+=/strike,if=((!action.big_hit.known|((action.big_hit.known&cooldown.big_hit.ready)|(action.big_hit.known&cooldown.big_hit.ready)))&rage.current>10)",
                }, "\n"),
                text
            )
        end
    )

    -- The truth table, every row: each tree under every (A known, B known, ready, up, execute) against wowsims's
    -- evaluation (sim/core/apl_values_operators.go): a read of an unknown ability is nil; and/or drop nil children
    -- and are nil when all are; not of nil is nil; a nil condition is true (apl_action.go).
    it("evaluates as wowsims does for every learned/unlearned combination (the truth table)", function()
        local function wowsims(n, w)
            local k, v = next(n)
            if k == "spellIsReady" then
                if w.kA then
                    return w.ready
                end
                return nil
            elseif k == "auraIsActive" then
                if w.kB then
                    return w.up
                end
                return nil
            elseif k == "isExecutePhase" then
                return w.E
            elseif k == "not" then
                local x = wowsims(v.val, w)
                if x == nil then
                    return nil
                end
                return not x
            end
            local out
            for _, x in ipairs(v.vals) do
                local r = wowsims(x, w)
                if r ~= nil then
                    if out == nil then
                        out = r
                    elseif k == "and" then
                        out = out and r
                    else
                        out = out or r
                    end
                end
            end
            return out
        end
        local function ours(text, w)
            local cond = text:match(",if=(.*)$")
            if not cond then
                return true
            end
            local V = {
                ["action.big_hit.known"] = w.kA,
                ["action.dot.known"] = w.kB,
                ["cooldown.big_hit.ready"] = w.ready,
                ["buff.dot.up"] = w.up,
                execute_phase = w.E,
            }
            local lua = cond:gsub("[%a_][%w_.]*", function(x)
                return ("V[%q]"):format(x)
            end)
                :gsub("&", " and ")
                :gsub("|", " or ")
                :gsub("!", " not ")
            local f = assert(loadstring("local V = ...; return " .. lua))
            return f(V)
        end
        for i, tree in ipairs(trees) do
            local text = apl.translate({ priorityList = { cast(300, tree) } }, ctx({ executePhase = "execute_phase" }))
            for bits = 0, 31 do
                local w = {}
                for j, name in ipairs({ "kA", "kB", "ready", "up", "E" }) do
                    w[name] = math.floor(bits / 2 ^ (j - 1)) % 2 == 1
                end
                local want = wowsims(tree, w)
                if want == nil then
                    want = true
                end
                assert.are.equal(want, ours(text, w), ("tree %d, %s, row %d"):format(i, text, bits))
            end
        end
    end)

    -- The invariant between rule 6 and tools/check_pack_levels.lua: every line the translator writes passes the
    -- leveling check, over nested guards (a guarded term holding another ability's guard), guards under a not,
    -- group guards and groups whose terms read one ability, and the Feral and Rogue shapes from the wowsims lanes.
    it("writes only lines the leveling check accepts", function()
        local levels = assert(loadfile("tools/check_pack_levels.lua"))()
        local function cost(id)
            return { spellCurrentCost = { spellId = { spellId = id } } }
        end
        local function calc(op, l, r)
            return { math = { op = op, lhs = l, rhs = r } }
        end
        local function known(id)
            return { auraIsKnown = { auraId = { spellId = id } } }
        end
        local energy, cp = { currentEnergy = {} }, { currentComboPoints = {} }
        local remains = { dotRemainingTime = { spellId = { spellId = 400 } } }
        -- Feral's pooling test: energy after A's cost, against B's (two abilities' reads in one comparison)
        local pool = cmp("OpLt", calc("OpAdd", calc("OpSub", energy, cost(200)), const("10")), cost(400))
        local refresh = AND(cmp("OpGe", cp, const("5")), up, cmp("OpLe", remains, const("2s")), pool)
        local spend = OR(
            AND(
                cmp("OpLt", cp, const("5")),
                OR(
                    NOT(cmp("OpLe", remains, const("2s"))),
                    AND(cmp("OpGt", energy, calc("OpAdd", cost(400), cost(100))), NOT(up))
                )
            ),
            cmp("OpGe", energy, const("75"))
        )
        local corpus = {
            pool,
            NOT(pool),
            refresh,
            AND(NOT(OR(refresh, AND(ready, pool))), cmp("OpGe", energy, cost(200))),
            AND(
                OR(NOT(AND(NOT(up), ready)), cmp("OpLt", remains, const("1s"))),
                OR(ready, up, ready),
                NOT(OR(up, up, up))
            ),
            NOT(AND(OR(ready, up), OR(ready, pool), NOT(OR(up, NOT(pool))))),
            spend,
            NOT(spend),
            OR(AND(ready, OR(ready, AND(up, ready))), E),
            -- known tests or-ed inside an and (auraIsKnown of two abilities, of two talents): a condition, not a guard
            AND(OR(known(200), known(400)), E),
            AND(OR(known(900), known(950)), E),
            OR(AND(OR(known(200), known(400)), ready), E),
            OR(AND(known(200), up), E),
            AND(OR(known(400), known(400)), ready),
        }
        for _, t in ipairs(trees) do
            corpus[#corpus + 1] = t
        end
        local function isAbility(k)
            return k == "strike" or k == "big_hit" or k == "roar" or k == "dot"
        end
        for i, tree in ipairs(corpus) do
            local text = apl.translate({ priorityList = { cast(300, tree) } }, ctx({ executePhase = "execute_phase" }))
            local cond = text:match(",if=(.*)$")
            assert.are.same(
                {},
                cond and levels.unguarded(cond, "roar", isAbility) or {},
                ("tree %d: %s"):format(i, text)
            )
        end
    end)

    it(
        "puts a recipe's required talent before each entry it names, in every list, and refuses an unknown one",
        function()
            local levels = assert(loadfile("tools/check_pack_levels.lua"))()
            local rage = cmp("OpGt", { currentRage = {} }, const("10"))
            local rotation = {
                prepullActions = { { action = cast(200).action, doAtValue = const("-1s") } },
                priorityList = {
                    cast(100, OR(ready, rage)),
                    cast(200),
                    cast(100, AND(ready, rage)),
                    cast(300, rage),
                    { action = { groupReference = { groupName = "Big" } } },
                },
                groups = { { name = "Big", actions = { cast(200, NOT(up)) } } },
            }
            local text =
                apl.translate(rotation, ctx({ requires = { strike = "furious", big_hit = "cuts", big = "cuts" } }))
            assert.are.equal(
                table.concat({
                    "actions.precombat=big_hit,prepull_at=1,if=talent.cuts.enabled",
                    "actions=strike,if=talent.furious.enabled&((action.big_hit.known&cooldown.big_hit.ready)|rage.current>10)",
                    "actions+=/big_hit,if=talent.cuts.enabled",
                    "actions+=/strike,if=talent.furious.enabled&((!action.big_hit.known|cooldown.big_hit.ready)&rage.current>10)",
                    "actions+=/roar,use_off_gcd=1,if=rage.current>10",
                    "actions+=/call_action_list,name=big,if=talent.cuts.enabled",
                    "actions.big=big_hit,if=talent.cuts.enabled&(!action.dot.known|!buff.dot.up)",
                }, "\n"),
                text
            )
            local function isAbility(k)
                return k == "strike" or k == "big_hit" or k == "roar" or k == "dot"
            end
            for line in text:gmatch("[^\n]+") do
                local self, cond = line:match("=/?([%w_]+).-,if=(.*)$")
                assert.are.same({}, levels.unguarded(cond, self, isAbility), line)
            end
            assert.has_error(function()
                apl.translate({ priorityList = { cast(100) } }, ctx({ requires = { strike = "nope" } }))
            end, "requires: nope is not a talent key")
        end
    )

    it(
        "rule 15's maintenance: the cast lines take the setting, the aura's other required reads read 'up or disabled'",
        function()
            local tgt = { type = "CurrentTarget" }
            local on = { auraIsActive = { sourceUnit = tgt, auraId = { spellId = 400 } } }
            local rem =
                cmp("OpGt", { auraRemainingTime = { sourceUnit = tgt, auraId = { spellId = 400 } } }, const("2s"))
            local rage = cmp("OpGt", { currentRage = {} }, const("10"))
            local r = {
                maintenance = { dot = "keep_dot" },
                leveling = {
                    "dot,if=!action.big_hit.known",
                    "strike,if=rage.current>10&debuff.dot.up",
                    -- under a negation: another line's copied condition (Guardian's Lacerate lines repeat Berserk's)
                    "strike,if=!(cooldown.big_hit.ready&debuff.dot.up)",
                    -- the documented limit: any negated group reads as if the debuff were up (setting off: !(rage>10))
                    "big_hit,if=!(debuff.dot.up&rage.current>10)",
                },
            }
            local text, _, _, header = apl.translate({
                priorityList = {
                    cast(100, on),
                    cast(200, AND(on, rage)),
                    cast(200, NOT(on)), -- the aura's absence on another line: not a requirement, unchanged
                    cast(100, rem),
                    cast(400, NOT(on)), -- the cast line: the setting, not the rewrite
                    cast(400, OR(rage, rem)),
                    cast(400),
                },
            }, ctx(r))
            assert.are.equal(
                table.concat({
                    "actions=strike,if=(!action.dot.known|debuff.dot.up|!settings.keep_dot)",
                    "actions+=/big_hit,if=((!action.dot.known|debuff.dot.up|!settings.keep_dot)&rage.current>10)",
                    "actions+=/big_hit,if=(!action.dot.known|!debuff.dot.up)",
                    "actions+=/strike,if=(!action.dot.known|debuff.dot.remains>2|!settings.keep_dot)",
                    "actions+=/dot,if=settings.keep_dot&!debuff.dot.up",
                    "actions+=/dot,if=settings.keep_dot&(rage.current>10|debuff.dot.remains>2)",
                    "actions+=/dot,if=settings.keep_dot",
                    "actions+=/dot,if=settings.keep_dot&!action.big_hit.known",
                    "actions+=/strike,if=rage.current>10&(debuff.dot.up|!settings.keep_dot)",
                    "actions+=/strike,if=!(cooldown.big_hit.ready&(debuff.dot.up|!settings.keep_dot))",
                    "actions+=/big_hit,if=!((debuff.dot.up|!settings.keep_dot)&rage.current>10)",
                }, "\n"),
                text
            )
            assert.are.same(
                { "# Setting keep_dot (maintenance debuff: dot), default off in game, on in the harness." },
                header
            )
            assert.has_error(function()
                apl.translate({ priorityList = { cast(100) } }, ctx({ maintenance = { big_hit = "x" } }))
            end, "maintenance: big_hit matched no line")
        end
    )

    it("rule 16's select: an option-selected cast is one line a candidate, its values read the setting", function()
        local r = {
            select = {
                castAssigned = {
                    setting = "pick",
                    option = "pickOption",
                    candidates = { One = "dot", Two = "big_hit", Off = false },
                    active = "assignedIsActive",
                    is = "isAssigned",
                },
            },
        }
        local player = { warrior = { options = { classOptions = { pickOption = "Two" } } } }
        local isActive = { assignedIsActive = {} }
        local rage = cmp("OpGt", { currentRage = {} }, const("10"))
        local text, _, _, header = apl.translate({
            priorityList = {
                { action = { castAssigned = {}, condition = NOT(isActive) } },
                cast(100, AND(isActive, rage)),
                cast(100, { isAssigned = { pickType = "Off" } }),
                { action = { castAssigned = {} } },
            },
        }, ctx(r, player))
        -- wowsims's IsActive with no spell (the none candidate) is false: no term for it
        local active = "((settings.pick='one'&debuff.dot.up)|(settings.pick='two'&debuff.big_hit.up))"
        assert.are.equal(
            table.concat({
                "actions=dot,if=settings.pick='one'&(!" .. active .. ")",
                "actions+=/big_hit,if=settings.pick='two'&(!" .. active .. ")",
                "actions+=/strike,if=(" .. active .. "&rage.current>10)",
                "actions+=/strike,if=settings.pick='off'",
                "actions+=/dot,if=settings.pick='one'",
                "actions+=/big_hit,if=settings.pick='two'",
            }, "\n"),
            text
        )
        assert.are.same({
            "# Setting pick (choice of pickOption: off, one, two), default two in game and in the harness.",
        }, header)
        -- the option's zero value (protojson omits it) and an unknown candidate are unsupported (rule 2)
        local _, omitted = apl.translate({
            priorityList = {
                { action = { castAssigned = {} } },
                cast(100, { isAssigned = {} }),
                cast(100, { isAssigned = { pickType = "Three" } }),
            },
        }, ctx(r, player))
        assert.are.same({ "default #2: isAssigned of no candidate", "default #3: isAssigned of Three" }, omitted)
        assert.has_error(function()
            apl.translate({ priorityList = { cast(100) } }, ctx(r, player))
        end, "select: castAssigned is not in the APL")
        assert.has_error(function()
            ctx(r, { warrior = { options = {} } })
        end, "select: the build sets no pickOption")
    end)

    it("takes the character's ability set: a shared racial is mapped and off the GCD", function()
        local set = require("Forever.helpers.engine").abilitySet("WARRIOR")
        local c = apl.context(set, {})
        for id, key in pairs({
            [20572] = "blood_fury",
            [20554] = "berserking",
            [1259813] = "eureka",
            [1259799] = "elunes_light",
        }) do
            local text = apl.translate({ priorityList = { cast(id) } }, c)
            assert.are.equal("actions=" .. key .. ",use_off_gcd=1", text)
        end
        assert.are.equal("demonic_rune", c.itemKey[12662])
    end)

    it("reads unitDistance against a whole number as the target's within/outside, else omits the line", function()
        local d = { unitDistance = { sourceUnit = { type = "Self" } } }
        local text, omitted = apl.translate({
            priorityList = {
                cast(100, cmp("OpLe", d, { variableRef = { name = "Melee range" } })),
                cast(200, cmp("OpGt", d, const("8"))),
                cast(300, cmp("OpGe", const("11.00"), d)), -- N >= d: within
                cast(400, cmp("OpEq", d, const("5"))),
                cast(400, cmp("OpLe", d, const("5.5"))),
            },
            valueVariables = { { name = "Melee range", value = const("5.00") } },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions=strike,focus=1,if=target.within5",
                "actions+=/big_hit,if=target.outside8",
                "actions+=/roar,use_off_gcd=1,if=target.within11",
            }, "\n"),
            text
        )
        assert.are.same({ "default #4: unitDistance OpEq 5", "default #5: unitDistance OpLe 5.5" }, omitted)
    end)

    it("drops a call to a group whose entries were all omitted", function()
        local text, omitted = apl.translate({
            priorityList = { { action = { groupReference = { groupName = "Gone" } } }, cast(100) },
            groups = { { name = "Gone", actions = { cast(999) } } },
        }, ctx())
        assert.are.equal("actions=strike,focus=1", text)
        assert.are.same({ "gone #1: spell 999", "default: empty group gone" }, omitted)
    end)

    it("drops only the branch of a read nothing resolves, as wowsims's nil node, and lists its ID", function()
        local lost = { auraIsActive = { auraId = { spellId = 12345 } } } -- no aura, ability or map owns it
        local rage = cmp("OpGt", { currentRage = {} }, const("10"))
        local text, omitted = apl.translate({
            priorityList = {
                cast(100, AND(lost, rage)),
                cast(100, OR(lost, rage)),
                cast(100, NOT(lost)),
                cast(100, AND(NOT(lost), OR(rage, lost), E)),
                cast(100, cmp("OpLt", { spellTimeToReady = { spellId = { spellId = 999 } } }, const("1s"))),
                cast(100, AND({ spellIsReady = { spellId = { itemId = 777 } } }, rage)),
                cast(100, AND({ spellIsKnown = { spellId = { spellId = 999 } } }, rage)), -- wowsims's constant false
                cast(100, { dotIsActive = { spellId = { spellId = 12346 } } }),
                cast(999, rage), -- the action itself: the whole entry
            },
        }, ctx({ executePhase = "execute_phase" }))
        assert.are.equal(
            table.concat({
                "actions=strike,if=rage.current>10",
                "actions+=/strike,if=rage.current>10",
                "actions+=/strike",
                "actions+=/strike,if=(rage.current>10&execute_phase)",
                "actions+=/strike",
                "actions+=/strike,if=rage.current>10",
                "actions+=/strike",
            }, "\n"),
            text
        )
        assert.are.same({
            "default #1: dropped the unresolved aura 12345 (its branch only)",
            "default #2: dropped the unresolved aura 12345 (its branch only)",
            "default #3: dropped the unresolved aura 12345 (its branch only)",
            "default #4: dropped the unresolved aura 12345 (its branch only)",
            "default #5: dropped the unresolved spell 999 (its branch only)",
            "default #6: dropped the unresolved item 777 (its branch only)",
            "default #7: never",
            "default #8: dropped the unresolved aura 12346 (its branch only)",
            "default #9: spell 999",
        }, omitted)
    end)

    -- A log in the exporter's shape: two autocast cooldowns (one twice), an unmapped one, a pet's, and instant and cast
    -- stat-buff casts.
    local LOG = table.concat({
        "# wowsims 0123 test seed 1 10 s target 63",
        "[-1.00] [Tester (#1)] Casting {ItemID: 555} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)",
        "[-1.00] [Tester (#1)] Completed cast {ItemID: 555}",
        '[-1.00] [Tester (#1)] Gained {"Strength": 50.000,} from {ItemID: 555}.',
        "[0.00] [Tester (#1)] Casting {SpellID: 300} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)",
        "[0.00] [Tester (#1)] Completed cast {SpellID: 300}",
        '[0.00] [Tester (#1)] Gained {"AttackPower": 100.000,} from {SpellID: 300}.',
        "[0.00] [Tester (#1)] Major cooldown used: {SpellID: 300}",
        "[0.00] [Tester (#1)] Major cooldown used: {ItemID: 777}",
        "[1.00] [Tester (#1) - Wolf] Major cooldown used: {SpellID: 200}",
        "[2.00] [Tester (#1)] Major cooldown used: {SpellID: 400}",
        "[3.00] [Tester (#1)] Major cooldown used: {SpellID: 300}",
        "[4.00] [Tester (#1)] Casting {ItemID: 556} (Cost = 0.000, Cast Time = 1.5s, GCD = 1.5s, Effective Time = 1.5s)",
        "[5.50] [Tester (#1)] Completed cast {ItemID: 556}",
        '[5.50] [Tester (#1)] Gained {"AttackPower": 80.000,} from {ItemID: 556}.',
        "[6.00] [Tester (#1)] Casting {SpellID: 100} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[6.00] [Tester (#1)] Completed cast {SpellID: 100}",
        '[6.00] [Tester (#1)] Gained {"AttackPower": 80.000,} from {SpellID: 100}.',
        -- instant but on the GCD (Effective Time 1.5s): wowsims's EffectiveTime() is not 0, no stat-buff cooldown
        "[7.00] [Tester (#1)] Casting {SpellID: 500} (Cost = 0.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)",
        "[7.00] [Tester (#1)] Completed cast {SpellID: 500}",
        '[7.00] [Tester (#1)] Gained {"Strength": 80.000,} from {SpellID: 500}.',
        -- off the GCD, but the APL casts it (castFriendlySpell): out of wowsims's automatic set
        "[8.00] [Tester (#1)] Casting {SpellID: 600} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)",
        "[8.00] [Tester (#1)] Completed cast {SpellID: 600}",
        '[8.00] [Tester (#1)] Gained {"Strength": 80.000,} from {SpellID: 600}.',
        -- another ID of strike, which the APL casts itself under 100
        "[9.00] [Tester (#1)] Major cooldown used: {SpellID: 101}",
    }, "\n")

    it("writes a strictSequence as its members' lines, each after the one before it is cast (rule 14)", function()
        local levels = assert(loadfile("tools/check_pack_levels.lua"))()
        local function member(id, cond)
            return { castSpell = { spellId = { spellId = id } }, condition = cond }
        end
        local text, omitted = apl.translate({
            priorityList = {
                {
                    action = {
                        condition = AND({ spellIsReady = { spellId = { spellId = 300 } } }, ready),
                        strictSequence = { actions = { member(300), member(100, up), member(400) } },
                    },
                },
                { action = { strictSequence = { actions = { member(300), { wait = {} } } } } },
            },
        }, ctx())
        local BIG = "(!action.big_hit.known|cooldown.big_hit.ready)"
        -- the sequence's condition, all reads guarded
        local GO = "(!(action.roar.known|action.big_hit.known)|((!action.roar.known|cooldown.roar.ready)&"
            .. BIG
            .. "))"
        local AT_STRIKE = "((action.roar.known&prev.1.roar)|(!action.roar.known&" .. GO .. "))"
        local lines = {
            "actions=roar,use_off_gcd=1,if=" .. GO,
            -- a later member: the condition without roar's readiness (false once roar is cast), then its own
            "actions+=/strike,focus=1,if=" .. AT_STRIKE .. "&" .. BIG .. "&(!action.dot.known|buff.dot.up)",
            "actions+=/dot,if=((action.strike.known&prev.1.strike)|(!action.strike.known&" .. AT_STRIKE .. "))&" .. BIG,
        }
        assert.are.equal(table.concat(lines, "\n"), text)
        assert.are.same({ "default #2: strictSequence of wait" }, omitted)
        local function isAbility(k)
            return k == "strike" or k == "big_hit" or k == "roar" or k == "dot"
        end
        for _, line in ipairs(lines) do
            local key, cond = line:match("[=/]([%w_]+),.-if=(.*)$")
            assert.are.same({}, levels.unguarded(cond, key, isAbility), line)
        end
    end)

    it("keeps two strictSequences sharing a first member apart: neither's later member opens on the other's", function()
        local function member(id)
            return { castSpell = { spellId = { spellId = id } } }
        end
        local text = apl.translate({
            priorityList = {
                { action = { condition = up, strictSequence = { actions = { member(300), member(100) } } } },
                { action = { condition = NOT(up), strictSequence = { actions = { member(300), member(400) } } } },
            },
        }, ctx())
        local strike = text:match("strike,focus=1,if=([^\n]*)")
        local dot = text:match("/dot,if=([^\n]*)")
        -- after the second sequence's roar (dot not up), the first's strike stays shut: it needs dot up too
        local UP = "(!action.dot.known|buff.dot.up)"
        assert.are.equal("((action.roar.known&prev.1.roar)|(!action.roar.known&" .. UP .. "))&" .. UP, strike)
        local DOWN = dot:match("^%(%(action%.roar%.known&prev%.1%.roar%)|%(!action%.roar%.known&(.*)%)%)&(.*)$")
        assert.is_truthy(DOWN and DOWN:find("!buff.dot.up", 1, true), dot) -- its own sequence's: dot down
    end)

    it(
        "reads an aura keyed by an ability's spell ID through the recipe's aura-only map, casts through `map`",
        function()
            local hit = { auraIsActive = { auraId = { spellId = 200 } } } -- wowsims's window aura under big_hit's own ID
            local rot =
                { priorityList = { cast(200, hit), cast(100, { auraIsKnown = { auraId = { spellId = 200 } } }) } }
            assert.are.equal(
                "actions=big_hit,if=buff.big_hit.up\nactions+=/strike,focus=1,if=action.big_hit.known",
                (apl.translate(rot, ctx({ focus = { strike = 1 } })))
            )
            assert.are.equal( -- the cast is still big_hit; the aura reads stance (registered: known, true)
                "actions=big_hit,if=buff.stance.up\nactions+=/strike,focus=1",
                (apl.translate(rot, ctx({ focus = { strike = 1 }, auras = { [200] = "stance" } })))
            )
        end
    )

    it("opens the Rogue Combat recipe with Blood Fury, then Adrenaline Rush once it is cast (rule 14)", function()
        local f = assert(io.open("src/Hekili_Rogue/APLs/Combat (wowsims.com).simc", "rb"))
        local simc = f:read("*a")
        f:close()
        local bf, ar = simc:match( -- consecutive lines
            "\nactions%+=/blood_fury,use_off_gcd=1,if=([^\n]*)\nactions%+=/adrenaline_rush,if=([^\n]*)\n"
        )
        assert.is_truthy(bf and bf:find("cooldown.adrenaline_rush.ready", 1, true)) -- the sequence's condition
        local at, rest = ar:match("^(.-%)%))&(.*)$")
        assert.are.equal("((action.blood_fury.known&prev.1.blood_fury)|(!action.blood_fury.known&" .. bf .. "))", at)
        -- the rest of its sequence's condition: Slice and Dice up and Adrenaline Rush ready, not Blood Fury's readiness
        assert.is_truthy(
            rest:find("buff.slice_and_dice.up", 1, true) and rest:find("cooldown.adrenaline_rush.ready", 1, true)
        )
        assert.is_falsy(rest:find("blood_fury", 1, true))
        assert.is_falsy(simc:find("strictSequence", 1, true)) -- no longer omitted
    end)

    it("runs prev.1 through the engine: a member is recommended right after its predecessor's prediction", function()
        local headless = require("Game.harness.headless")
        local ww = require("Forever.helpers.warrior_world")
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        local out = H.Hekili.Engine.Output.Primary
        local function recs(after) -- bloodrage, then battle_shout listed first behind `prev.1.<after>`
            H.Hekili.DB.profile.packs[ww.PACK].lists = {
                default = {
                    { enabled = true, action = "battle_shout", criteria = "prev.1." .. after },
                    { enabled = true, action = "bloodrage" },
                },
            }
            H.Hekili:LoadScripts()
            assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
            t = t + 0.2
            assert(headless.cycle(H, t))
            assert.are.same({}, H.errors)
            return { out.recs[1] and out.recs[1].actionName, out.recs[2] and out.recs[2].actionName }
        end
        assert.are.same({ "bloodrage", "battle_shout" }, recs("bloodrage"))
        assert.are.same({ "bloodrage" }, recs("berserker_stance"))
    end)

    it("expands wowsims's automatic cooldowns from the log, in place, under the entry's condition", function()
        local levels = assert(loadfile("tools/check_pack_levels.lua"))()
        local r = { focus = { strike = 1 } }
        local rotation = {
            priorityList = {
                cast(200),
                {
                    action = { autocastOtherCooldowns = {}, condition = cmp("OpGe", { currentTime = {} }, const("5s")) },
                },
                { action = { castAllStatBuffCooldowns = { statType1 = 0, statType2 = 14, statType3 = -1 } } },
                { action = { castAllStatBuffCooldowns = { statType1 = 13, statType2 = -1, statType3 = -1 } } },
                cast(100),
                { action = { castFriendlySpell = { spellId = { spellId = 600 } } } },
            },
        }
        local kit = {
            abilities = {
                strike = { key = "strike", id = 100, copy = { 101 }, gcd = "spell" },
                big_hit = { key = "big_hit", id = 200, gcd = "spell" },
                roar = { key = "roar", id = 300, gcd = "off" },
                shout = { key = "shout", id = 500, gcd = "spell" },
                bless = { key = "bless", id = 600, gcd = "off" },
                dot = { key = "dot", id = 400, gcd = "spell" },
                trinket = { key = "trinket", id = -1, item = 555, gcd = "off" },
                stone = { key = "stone", id = -2, items = { 556, 557 }, gcd = "off" },
            },
            auras = {},
        }
        local text, omitted = apl.translate(rotation, apl.context(kit, r, LOG))
        assert.are.equal(
            table.concat({
                "actions=big_hit",
                "actions+=/roar,use_off_gcd=1,if=time>=5", -- off the GCD: flagged; dot (on it) is not
                "actions+=/dot,if=time>=5",
                "actions+=/trinket,use_off_gcd=1",
                "actions+=/strike,focus=1",
            }, "\n"),
            text
        )
        assert.are.same({
            "default #2: autocastOtherCooldowns: unmapped item 777",
            "default #2: autocastOtherCooldowns: spell 101 is strike, which the APL casts itself",
            "default #4: castAllStatBuffCooldowns: none in the log",
            "default #6: castFriendlySpell",
        }, omitted)
        -- the friendly cast is what keeps bless out: without it, the off-GCD instant buff is wowsims's to cast
        table.remove(rotation.priorityList)
        local without = apl.translate(rotation, apl.context(kit, r, LOG))
        assert.are.equal(
            "actions+=/trinket,use_off_gcd=1\nactions+=/bless,use_off_gcd=1",
            without:match("actions%+=/trinket.-use_off_gcd=1\n[^\n]+")
        )
        table.insert(rotation.priorityList, { action = { castFriendlySpell = { spellId = { spellId = 600 } } } })
        -- deterministic, and every line passes the leveling check
        assert.are.equal(text, (apl.translate(rotation, apl.context(kit, r, LOG))))
        for line in text:gmatch("[^\n]+") do
            local self, cond = line:match("=/?([%w_]+).-,if=(.*)$")
            if cond then
                assert.are.same(
                    {},
                    levels.unguarded(cond, self, function()
                        return true
                    end),
                    line
                )
            end
        end
        -- without a log the automatic actions are unsupported, as before
        local _, none = apl.translate({ priorityList = { { action = { autocastOtherCooldowns = {} } } } }, ctx())
        assert.are.same({ "default #1: autocastOtherCooldowns (no log)" }, none)
    end)
end)

-- Central fix 11: wowsims's OpDiv is division; the engine's script language takes `/` for division and `%` for modulo.
describe("a wowsims division", function()
    local div = cmp("OpGt", { math = { op = "OpDiv", lhs = const("7"), rhs = const("2") } }, const("3"))

    it("is written as /", function()
        local text = apl.translate({ priorityList = { cast(100, div) } }, ctx({}))
        assert.are.equal("actions=strike,if=(7/2)>3", text)
    end)

    it("runs as division through the engine (7 / 2 > 3; modulo would be 1)", function()
        local headless = require("Game.harness.headless")
        local ww = require("Forever.helpers.warrior_world")
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        local t = H.ctl.now + 0.2
        assert(headless.cycle(H, t))
        local cond = apl.translate({ priorityList = { cast(100, div) } }, ctx({})):match(",if=(.*)$")
        H.Hekili.DB.profile.packs[ww.PACK].lists = {
            default = { { enabled = true, action = "berserker_stance", criteria = cond } },
        }
        H.Hekili:LoadScripts()
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        assert(headless.cycle(H, t + 0.2))
        assert.are.same({}, H.errors)
        assert.are.equal("berserker_stance", out.recs[1] and out.recs[1].actionName)
    end)
end)
