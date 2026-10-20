-- tests/Forever/wowsims_apl_spec.lua (wowsims packs plan, Task 4): the APL translator's rules on a small APL in
-- wowsims/forever's JSON shape (MIT) with a stand-in class context.
local apl = require("tools.wowsims.apl")

local function ctx(r)
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
    return apl.context(kit, r or { executePhase = "execute_phase", focus = { strike = 1 } })
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

describe("the wowsims APL translator", function()
    it("keeps the order, maps keys, flags off-GCD and focus, and guards another ability's reads", function()
        local text, omitted = apl.translate({
            prepullActions = { cast(300) },
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
                "actions.precombat=roar,use_off_gcd=1",
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

    it("schedules the prepull: prepull_at from doAtValue, earliest first, no guard of its own", function()
        local function at(id, v, cond)
            local e = cast(id, cond)
            e.doAtValue = v and const(v)
            return e
        end
        local text, omitted = apl.translate({
            prepullActions = {
                at(100, "-1.5s"),
                at(300, "-10s"),
                at(200, "-1.5s", { ["not"] = { val = { auraIsActive = { auraId = { spellId = 900 } } } } }),
                at(400),
            },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions.precombat=roar,use_off_gcd=1,prepull_at=10",
                "actions.precombat+=/strike,focus=1,prepull_at=1.5",
                "actions.precombat+=/big_hit,prepull_at=1.5,if=(!talent.furious.enabled|!buff.fury.up)",
                "actions.precombat+=/dot",
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
        assert.are.same({ { "wowsims_big", false }, { "wowsims_weave", true } }, toggles)
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

    it(
        "guards a read so an unknown ability drops its term: true in an and, false in an or, flipped by a not",
        function()
            local ready = { spellIsReady = { spellId = { spellId = 200 } } }
            local up = { auraIsActive = { auraId = { spellId = 400 } } }
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
                }, "\n"),
                text
            )
        end
    )

    -- The truth table, every row: each tree under every (A known, B known, ready, up, execute) against wowsims's
    -- evaluation (sim/core/apl_values_operators.go): a read of an unknown ability is nil; and/or drop nil children
    -- and are nil when all are; not of nil is nil; a nil condition is true (apl_action.go).
    it("evaluates as wowsims does for every learned/unlearned combination (the truth table)", function()
        local ready = { spellIsReady = { spellId = { spellId = 200 } } } -- A: big_hit
        local up = { auraIsActive = { auraId = { spellId = 400 } } } -- B: dot
        local E = { isExecutePhase = { threshold = "E20" } }
        local function AND(...)
            return { ["and"] = { vals = { ... } } }
        end
        local function OR(...)
            return { ["or"] = { vals = { ... } } }
        end
        local function NOT(x)
            return { ["not"] = { val = x } }
        end
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
        }
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

    it("drops a call to a group whose entries were all omitted", function()
        local text, omitted = apl.translate({
            priorityList = { { action = { groupReference = { groupName = "Gone" } } }, cast(100) },
            groups = { { name = "Gone", actions = { cast(999) } } },
        }, ctx())
        assert.are.equal("actions=strike,focus=1", text)
        assert.are.same({ "gone #1: spell 999", "default: empty group gone" }, omitted)
    end)
end)
