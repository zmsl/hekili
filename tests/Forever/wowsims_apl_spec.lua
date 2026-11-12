-- tests/Forever/wowsims_apl_spec.lua (wowsims packs plan, Task 4): the APL translator's rules on a small APL in
-- wowsims/forever's JSON shape (MIT) with a stand-in class context.
local apl = require("tools.wowsims.apl")

local function ctx(r, player, encounter)
    local kit = {
        abilities = {
            strike = { key = "strike", id = 100, copy = { 101 }, gcd = "spell" },
            big_hit = { key = "big_hit", id = 200, gcd = "spell" },
            roar = { key = "roar", id = 300, gcd = "off" },
            dot = { key = "dot", id = 400, gcd = "spell" },
            starfire = { key = "starfire", id = 500, cast = 3, gcd = "spell" },
            pyroblast = {
                key = "pyroblast",
                id = 600,
                gcd = "spell",
                cast = function()
                    return 6
                end,
            },
            drain = { key = "drain", id = 700, cast = 5, channeled = true, gcd = "spell" },
            bolt = { key = "bolt", id = 800, cast = 2.5, velocity = 20, gcd = "spell" },
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
    return apl.context(kit, r or { executePhase = "execute_phase", focus = { strike = 1 } }, nil, player, encounter)
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

    it("puts the recipe's levelingFirst lines before a pre-pull list's own too", function()
        local pre = cast(100)
        pre.doAtValue = const("-1.5s")
        local text = apl.translate(
            { prepullActions = { pre }, priorityList = { cast(200) } },
            ctx({ levelingFirst = { "dot,if=!buff.dot.up" } })
        )
        assert.are.equal(
            table.concat({
                "actions.precombat=dot,if=!buff.dot.up",
                "actions.precombat+=/strike",
                "actions=dot,if=!buff.dot.up",
                "actions+=/big_hit",
            }, "\n"),
            text
        )
    end)

    it(
        "omits the recipe's prepullSkip actions from the precombat list only, listed, and refuses an unused one",
        function()
            local function at(id, v)
                local e = cast(id)
                e.doAtValue = const(v)
                return e
            end
            local text, omitted = apl.translate(
                { prepullActions = { at(200, "-3s"), at(100, "-1.5s") }, priorityList = { cast(200) } },
                ctx({ prepullSkip = { "big_hit" } })
            )
            assert.are.equal(table.concat({ "actions.precombat=strike", "actions=big_hit" }, "\n"), text)
            assert.are.same({ "precombat #1: prepullSkip (recipe)" }, omitted)
            assert.has_error(function()
                apl.translate({ prepullActions = { at(100, "-1s") } }, ctx({ prepullSkip = { "dot" } }))
            end, "prepullSkip: no dot line in precombat")
        end
    )

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

    it("actionGroupUsed of a group with actions is wowsims's constant: a shown reference to it exists", function()
        local function used(name)
            return { actionGroupUsed = { name = name } }
        end
        local text, omitted = apl.translate({
            priorityList = {
                { action = { groupReference = { groupName = "Weave" } } },
                { hide = true, action = { groupReference = { groupName = "Hidden" } } },
                cast(100, used("Weave")),
                cast(200, used("Hidden")),
                cast(300, used("Nested")),
                cast(400, used("Unreferenced")),
            },
            groups = {
                { name = "Weave", actions = { cast(400), { action = { groupReference = { groupName = "Nested" } } } } },
                { name = "Hidden", actions = { cast(400) } },
                { name = "Nested", actions = { cast(400) } },
                { name = "Unreferenced", actions = { cast(400) } },
            },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions=call_action_list,name=weave",
                "actions+=/strike,focus=1",
                "actions+=/roar,use_off_gcd=1",
                "actions.weave=dot",
                "actions.weave+=/call_action_list,name=nested",
                "actions.nested=dot",
            }, "\n"),
            text
        )
        assert.are.same({ "default #2: hidden", "default #4: never", "default #6: never" }, omitted)
        local _, unknown = apl.translate({ priorityList = { cast(100, used("Nowhere")) } }, ctx())
        assert.are.same({ "default #1: actionGroupUsed Nowhere" }, unknown)
    end)

    it(
        "multipleCdUsages without a base spell: wowsims's fight-length test as fight_remains (R42), else true",
        function()
            local function mcu(o)
                o.targetSpellId = { spellId = 400 }
                o.offset = const("0ms")
                return { multipleCdUsages = o }
            end
            local text, omitted = apl.translate({
                priorityList = {
                    cast(400, mcu({ alignCdEnd = true })),
                    cast(100, mcu({})),
                    cast(200, mcu({ alignCdEnd = true, baseSpellId = { spellId = 200 } })),
                },
            }, ctx())
            assert.are.equal(
                table.concat({
                    "actions=dot,if=(fight_remains<=buff.dot.duration|fight_remains>(cooldown.dot.duration+(buff.dot.duration/2)))",
                    "actions+=/strike,focus=1",
                }, "\n"),
                text
            )
            assert.are.same({ "default #3: multipleCdUsages with a base spell" }, omitted)
        end
    )

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

    it("orders the prepull by doAtValue, earliest first, ties in the APL's order, with no prepull_at", function()
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
                "actions.precombat=roar,use_off_gcd=1",
                "actions.precombat+=/strike", -- pre-pull lines carry no tier
                "actions.precombat+=/big_hit,if=(!talent.furious.enabled|!buff.fury.up)",
                "actions.precombat+=/dot",
            }, "\n"),
            text
        )
        assert.are.same({
            "precombat #5: no doAtValue",
            "precombat #6: doAtValue after the pull",
            "precombat #7: doAtValue not a constant",
        }, omitted)
    end)

    describe("the pre-pull guard (rule 1: from what each line's handler does)", function()
        -- A kit whose handlers run in a stub environment, as the engine's (setfenv( f, state )): the translator
        -- records the verbs each handler calls.
        -- luacheck: read globals applyBuff applyDebuff removeBuff summonTotem buff
        local function noop() end
        local leaf = { up = false, down = true, remains = 0 }
        local env = {
            applyBuff = noop,
            applyDebuff = noop,
            removeBuff = noop,
            summonTotem = noop,
            error = error,
            buff = setmetatable({}, {
                __index = function()
                    return leaf
                end,
            }),
        }
        local function h(f)
            return setfenv(f, env)
        end
        local function guardCtx(r)
            local kit = {
                abilities = {
                    shout = {
                        key = "shout",
                        id = 1001,
                        gcd = "spell",
                        cooldown = 0,
                        handler = h(function()
                            applyBuff("shout")
                        end),
                    },
                    mark = {
                        key = "mark",
                        id = 1002,
                        gcd = "spell",
                        cooldown = 0,
                        handler = h(function()
                            applyDebuff("target", "mark")
                        end),
                    },
                    rage = {
                        key = "rage",
                        id = 1003,
                        gcd = "off",
                        cooldown = 60,
                        handler = h(function()
                            applyBuff("rage")
                        end),
                    },
                    move = {
                        key = "move",
                        id = 1004,
                        gcd = "off",
                        cooldown = 15,
                        handler = h(function()
                            applyDebuff("target", "move_stun")
                        end),
                    },
                    totem = {
                        key = "totem",
                        id = 1005,
                        gcd = "spell",
                        cooldown = 0,
                        handler = h(function()
                            summonTotem("totem", "air", 300)
                        end),
                    },
                    seal_a = {
                        key = "seal_a",
                        id = 1006,
                        gcd = "spell",
                        cooldown = 0,
                        handler = h(function()
                            if buff.seal_b.up then
                                removeBuff("seal_b")
                            end
                            applyBuff("seal_a")
                        end),
                    },
                    seal_b = {
                        key = "seal_b",
                        id = 1007,
                        gcd = "spell",
                        cooldown = 0,
                        handler = h(function()
                            if buff.seal_a.up then
                                removeBuff("seal_a")
                            end
                            applyBuff("seal_b")
                        end),
                    },
                    stance = {
                        key = "stance",
                        id = 1008,
                        gcd = "off",
                        cooldown = 1,
                        handler = h(function()
                            removeBuff("other_stance")
                            applyBuff("stance")
                        end),
                    },
                    boom = {
                        key = "boom",
                        id = 1009,
                        gcd = "spell",
                        cooldown = 0,
                        handler = h(function()
                            error("stub lacks x")
                        end),
                    },
                    plain = { key = "plain", id = 1010, gcd = "spell", cooldown = 0 },
                },
                auras = {
                    shout = { id = 2001, duration = 120 },
                    mark = { id = 2002, duration = 60 },
                    rage = { id = 2003, duration = 10 },
                    move_stun = { id = 2004, duration = 1 },
                    seal_a = { id = 2006, duration = 30 },
                    seal_b = { id = 2007, duration = 30 },
                    stance = { id = 2008, duration = 3600 },
                    other_stance = { id = 2018, duration = 3600 },
                    boom = { id = 2009, duration = 30 },
                },
                talents = {},
            }
            return apl.context(kit, r or { executePhase = "execute_phase" })
        end
        local function at(id, v, cond)
            local e = cast(id, cond)
            e.doAtValue = const(v)
            return e
        end

        it("writes each kind: buff, debuff, totem; none when moot, of another key, or no handler", function()
            local text, omitted = apl.translate({
                prepullActions = {
                    at(1001, "-5s"),
                    at(1002, "-5s"),
                    at(1003, "-4s"),
                    at(1004, "-1s"),
                    at(1005, "-4s"),
                    at(1008, "-3s", { isExecutePhase = { threshold = "E20" } }),
                    at(1009, "-2s"),
                    at(1010, "-2s"),
                },
            }, guardCtx())
            assert.are.equal(
                table.concat({
                    "actions.precombat=shout,if=!buff.shout.up",
                    "actions.precombat+=/mark,if=!debuff.mark.up",
                    "actions.precombat+=/rage,use_off_gcd=1",
                    "actions.precombat+=/totem,if=!totem.air.up",
                    "actions.precombat+=/stance,use_off_gcd=1,if=!buff.stance.up&execute_phase",
                    "actions.precombat+=/boom",
                    "actions.precombat+=/plain",
                    "actions.precombat+=/move,use_off_gcd=1",
                }, "\n"),
                text
            )
            assert.are.equal(1, #omitted)
            assert.matches("^precombat #7: no guard: boom's handler raised", omitted[1])
        end)

        it(
            "leaves a recipe's levelingFirst line in a pre-pull list unguarded (it carries its own condition)",
            function()
                local text =
                    apl.translate({ prepullActions = { at(1010, "-2s") } }, guardCtx({ levelingFirst = { "shout" } }))
                assert.are.equal(
                    table.concat({ "actions.precombat=shout", "actions.precombat+=/plain", "actions=shout" }, "\n"),
                    text
                )
            end
        )

        -- L102: a condition that already has the guard's term as an `&` term does not take it twice (Enhancement's
        -- `water_shield,if=!buff.water_shield.up&!buff.water_shield.up`)
        it("adds no guard term the line's condition already has", function()
            local down = NOT({ auraIsActive = { auraId = { spellId = 2001 } } })
            local text = apl.translate({
                prepullActions = {
                    at(1001, "-5s", down),
                    at(1001, "-4s", AND(down, { isExecutePhase = { threshold = "E20" } })),
                    at(1001, "-3s", OR(down, { isExecutePhase = { threshold = "E20" } })),
                },
            }, guardCtx())
            assert.are.equal(
                table.concat({
                    "actions.precombat=shout,if=!buff.shout.up",
                    "actions.precombat+=/shout,if=(!buff.shout.up&execute_phase)",
                    "actions.precombat+=/shout,if=!buff.shout.up&(!buff.shout.up|execute_phase)",
                }, "\n"),
                text
            )
        end)

        it("guards a mutually exclusive group's first line by every member's aura, later ones by their own", function()
            local text = apl.translate({
                prepullActions = { at(1006, "-3s"), at(1007, "-1.5s") },
            }, guardCtx())
            assert.are.equal(
                table.concat({
                    "actions.precombat=seal_a,if=!buff.seal_a.up&(!action.seal_b.known|!buff.seal_b.up)",
                    "actions.precombat+=/seal_b,if=!buff.seal_b.up",
                }, "\n"),
                text
            )
        end)

        it("reaches a group only the prepull calls, never one the priority also calls, nor the priority", function()
            local text = apl.translate({
                prepullActions = {
                    { action = { groupReference = { groupName = "Move" } }, doAtValue = const("-1s") },
                    { action = { groupReference = { groupName = "Both" } }, doAtValue = const("-1s") },
                },
                priorityList = { cast(1001), { action = { groupReference = { groupName = "Both" } } } },
                groups = {
                    { name = "Move", actions = { cast(1001), cast(1004) } },
                    { name = "Both", actions = { cast(1002) } },
                },
            }, guardCtx())
            assert.are.equal(
                table.concat({
                    "actions.precombat=call_action_list,name=move",
                    "actions.precombat+=/call_action_list,name=both",
                    "actions=shout",
                    "actions+=/call_action_list,name=both",
                    "actions.move=shout,if=!buff.shout.up",
                    "actions.move+=/move,use_off_gcd=1",
                    "actions.both=mark",
                }, "\n"),
                text
            )
        end)
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
                "actions+=/roar,use_off_gcd=1,if=rage.lo<30",
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

    it("reads a resource's current value on the Pet as pet.<resource>; any other Pet value is unsupported", function()
        local pet = { sourceUnit = { type = "Pet", index = 0, owner = { type = "Self" } } }
        local text, omitted = apl.translate({
            priorityList = {
                cast(100, cmp("OpLt", { currentMana = pet }, const("115"))),
                cast(200, cmp("OpGt", { currentManaPercent = pet }, const("10%"))),
                cast(300, cmp("OpGt", { currentEnergy = pet }, const("40"))),
            },
        }, ctx())
        assert.are.equal(
            table.concat(
                { "actions=strike,focus=1,if=pet.mana<115", "actions+=/roar,use_off_gcd=1,if=pet.energy>40" },
                "\n"
            ),
            text
        )
        assert.are.same({ "default #2: currentManaPercent of Pet" }, omitted)
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
                -- an unresolved ID folds false inside an emitted line: its header note shows the silent fold
                cast(100, { ["or"] = { vals = { known(999), known(200, "Self") } } }),
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
                "actions+=/strike,if=action.big_hit.known",
            }, "\n"),
            text
        )
        assert.are.same({
            "default #6: never",
            "default #8: never",
            "default #9: never",
            "default #13: auraIsKnown of the unresolved aura 999 folds false",
        }, omitted)
    end)

    it("reads auraIsKnown of an aura the recipe's knownAs names as that talent's enabled", function()
        local text = apl.translate({
            priorityList = { cast(100, { auraIsKnown = { auraId = { spellId = 910 } } }) },
        }, ctx({ knownAs = { [910] = "cuts" } }))
        assert.are.equal("actions=strike,if=talent.cuts.enabled", text)
    end)

    -- batch review M7: a knownAs naming a talent the kit lacks falls through as any other aura, with a header note
    it("notes a knownAs that names a talent the kit lacks, and resolves the aura as any other", function()
        local text, omitted = apl.translate({
            priorityList = { cast(100, { auraIsKnown = { auraId = { spellId = 910 } } }) },
        }, ctx({ knownAs = { [910] = "no_such_talent" } }))
        assert.are.equal("actions=strike", text)
        assert.are.same({
            "default #1: knownAs of the aura 910 names no_such_talent, a talent the kit lacks: read as any other aura",
        }, omitted)
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
                    "actions+=/strike,focus=1,if=ranged_speed>0",
                }, "\n"),
                text
            )
            assert.are.same({ "default #7: auraShouldRefresh 910 (no exclusive effect declared)" }, omitted)
        end
    )

    it("lets a recipe `condition` and `guard` name a cancelAura line as cancel_buff (owner deviation R69)", function()
        local text = apl.translate({
            priorityList = {
                { action = { cancelAura = { auraId = { spellId = 910 } } } },
                cast(100),
            },
        }, ctx({ condition = { cancel_buff = "target.within5" }, guard = { cancel_buff = "time>1" } }))
        assert.are.equal(
            table.concat({
                "actions=cancel_buff,buff_name=stance,if=target.within5&time>1",
                "actions+=/strike",
            }, "\n"),
            text
        )
    end)

    it("omits a cast aimed at another target (castSpell target index 1), never on the current one", function()
        local function at(target)
            return { action = { castSpell = { spellId = { spellId = 100 }, target = target } } }
        end
        local text, omitted = apl.translate({
            priorityList = {
                at({ index = 1, type = "Target" }), -- wowsims's second target (Bane of Havoc): aura audit C7
                at({ type = "Target" }), -- index 0: the encounter's first target, read as the current one
                { action = { changeTarget = { newTarget = { type = "NextTarget" } } } }, -- never a current-target line
            },
        }, ctx())
        assert.are.equal("actions=strike,focus=1", text) -- ctx()'s recipe gives strike focus tier 1
        assert.are.same(
            { "default #1: castSpell on another target (Target index 1)", "default #3: changeTarget" },
            omitted
        )
    end)

    it("omits a line whose recipe `condition` is false (owner deviation R69)", function()
        local text, omitted = apl.translate({
            priorityList = {
                { action = { cancelAura = { auraId = { spellId = 910 } } } },
                cast(100),
            },
        }, ctx({ condition = { cancel_buff = false } }))
        assert.are.equal("actions=strike", text)
        assert.are.same({ "default #1: the recipe's condition is false" }, omitted)
    end)

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
                "actions=strike,if=mana.pct_lo>10",
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
        local text, omitted = apl.translate({
            valueVariables = {
                { name = "Execute at", value = const("35%") },
                { name = "Mana", value = math("OpAdd", { currentManaPercent = {} }, const("1")) },
            },
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
                -- a percent read inside math or min / max: its scale (0-100 here, 0-1 in wowsims) leaks, unsupported
                cast(100, cmp("OpLt", math("OpSub", { currentHealthPercent = {} }, const("10%")), const("20%"))),
                cast(100, cmp("OpLt", math("OpMul", const("2"), at), { variableRef = { name = "Mana" } })),
                cast(100, cmp("OpLt", { min = { vals = { { currentManaPercent = {} }, const("5") } } }, const("20%"))),
            },
        }, ctx({}))
        assert.are.equal(
            table.concat({
                "actions=strike,if=20<=health.pct",
                "actions+=/strike,if=health.pct<35",
                "actions+=/strike,if=(fight_remains-((time+fight_remains)*0.35))<=0",
                "actions+=/strike,if=mana.pct_lo>(0.1+5)",
                "actions+=/strike,if=rage.lo<0.5",
            }, "\n"),
            text
        )
        assert.are.same({
            "default #6: a percent read in math",
            "default #7: a percent read in math",
            "default #8: a percent read in min",
        }, omitted)
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
                    "actions+=/strike,if=max(rage.lo,(action.dot.known&debuff.dot.remains),5)>4",
                    "actions+=/strike,if=rage.lo<5",
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
                    "actions=strike,if=((action.big_hit.known&cooldown.big_hit.ready)|rage.lo>10)",
                    "actions+=/strike,if=((!action.big_hit.known|cooldown.big_hit.ready)&rage.lo>10)",
                    "actions+=/strike,if=((action.big_hit.known&!cooldown.big_hit.ready)|rage.lo>10)",
                    "actions+=/strike,if=!((action.dot.known&buff.dot.up)|rage.lo>10)",
                    "actions+=/strike,if=((!action.big_hit.known|!cooldown.big_hit.ready)&rage.lo>10)",
                    "actions+=/strike,if=((!(action.big_hit.known|action.dot.known)|((action.big_hit.known&cooldown.big_hit.ready)|(action.dot.known&buff.dot.up)))&rage.lo>10)",
                    "actions+=/strike,if=(((action.big_hit.known|action.dot.known)&((!action.big_hit.known|cooldown.big_hit.ready)&(!action.dot.known|buff.dot.up)))|rage.lo>10)",
                    "actions+=/strike,if=((!action.big_hit.known|cooldown.big_hit.ready)&rage.lo>10)", -- `A|A` is A
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
                    "actions.precombat=big_hit,if=talent.cuts.enabled",
                    "actions=strike,if=talent.furious.enabled&((action.big_hit.known&cooldown.big_hit.ready)|rage.lo>10)",
                    "actions+=/big_hit,if=talent.cuts.enabled",
                    "actions+=/strike,if=talent.furious.enabled&((!action.big_hit.known|cooldown.big_hit.ready)&rage.lo>10)",
                    "actions+=/roar,use_off_gcd=1,if=rage.lo>10",
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
                    "strike,if=rage.lo>10&debuff.dot.up",
                    -- under a negation: another line's copied condition (Guardian's Lacerate lines repeat Berserk's)
                    "strike,if=!(cooldown.big_hit.ready&debuff.dot.up)",
                    -- the documented limit: any negated group reads as if the debuff were up (setting off: !(rage>10))
                    "big_hit,if=!(debuff.dot.up&rage.lo>10)",
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
                    "actions+=/big_hit,if=((!action.dot.known|debuff.dot.up|!settings.keep_dot)&rage.lo>10)",
                    "actions+=/big_hit,if=(!action.dot.known|!debuff.dot.up)",
                    "actions+=/strike,if=(!action.dot.known|debuff.dot.remains>2|!settings.keep_dot)",
                    "actions+=/dot,if=settings.keep_dot&!debuff.dot.up",
                    "actions+=/dot,if=settings.keep_dot&(rage.lo>10|debuff.dot.remains>2)",
                    "actions+=/dot,if=settings.keep_dot",
                    "actions+=/dot,if=settings.keep_dot&!action.big_hit.known",
                    "actions+=/strike,if=rage.lo>10&(debuff.dot.up|!settings.keep_dot)",
                    "actions+=/strike,if=!(cooldown.big_hit.ready&(debuff.dot.up|!settings.keep_dot))",
                    "actions+=/big_hit,if=!((debuff.dot.up|!settings.keep_dot)&rage.lo>10)",
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
                    zero = "One",
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
        -- wowsims's IsActive with no spell (the none candidate) is false: no term for it; an unlearned candidate's term
        -- reads false behind its known test (the line's own candidate needs none), which tools/check_pack_levels.lua takes
        local one, two = "(settings.pick='one'&debuff.dot.up)", "(settings.pick='two'&debuff.big_hit.up)"
        local gOne = "(action.dot.known&settings.pick='one'&debuff.dot.up)"
        local gTwo = "(action.big_hit.known&settings.pick='two'&debuff.big_hit.up)"
        local lines = {
            "actions=dot,if=settings.pick='one'&(!(" .. one .. "|" .. gTwo .. "))",
            "actions+=/big_hit,if=settings.pick='two'&(!(" .. gOne .. "|" .. two .. "))",
            "actions+=/strike,if=((" .. gOne .. "|" .. gTwo .. ")&rage.lo>10)",
        }
        local isAbility = function(k)
            return k == "dot" or k == "big_hit" or k == "strike"
        end
        local levels = assert(loadfile("tools/check_pack_levels.lua"))()
        for _, line in ipairs(lines) do
            local self, cond = line:match("^actions[^=]*=/?([%w_]+),if=(.*)$")
            assert.are.same({}, levels.unguarded(cond, self, isAbility), line)
        end
        assert.are.equal(
            table.concat({
                lines[1],
                lines[2],
                lines[3],
                "actions+=/strike,if=settings.pick='off'",
                "actions+=/dot,if=settings.pick='one'",
                "actions+=/big_hit,if=settings.pick='two'",
            }, "\n"),
            text
        )
        assert.are.same({
            "# Setting pick (choice of pickOption: off, one, two), default two in game and in the harness.",
        }, header)
        -- no field is the option's zero value (protojson omits it); an unknown candidate is unsupported (rule 2)
        local zeroText, omitted = apl.translate({
            priorityList = {
                { action = { castAssigned = {} } },
                cast(100, { isAssigned = {} }),
                cast(100, { isAssigned = { pickType = "Three" } }),
            },
        }, ctx(r, player))
        assert.are.equal(
            "actions=dot,if=settings.pick='one'\nactions+=/big_hit,if=settings.pick='two'\nactions+=/strike,if=settings.pick='one'",
            zeroText
        )
        assert.are.same({ "default #3: isAssigned of Three" }, omitted)
        assert.has_error(function()
            apl.translate({ priorityList = { cast(100) } }, ctx(r, player))
        end, "select: castAssigned is not in the APL")
        -- a build without the option holds its zero value (re-pin: 4 of 5 warlock builds omit curseOptions)
        local _, _, _, zeroHeader = apl.translate(
            { priorityList = { { action = { castAssigned = {} } } } },
            ctx(r, {
                warrior = { options = {} },
            })
        )
        assert.are.same({
            "# Setting pick (choice of pickOption: off, one, two), default one in game and in the harness.",
        }, zeroHeader)
        r.select.castAssigned.zero = nil
        assert.has_error(function()
            ctx(r, player)
        end, "select: castAssigned declares no zero candidate")
    end)

    it("rule 17's multidot: the DoT's cast on the current target while its DoT has at most maxOverlap left", function()
        local function multidot(id, overlap, cond)
            local m = { spellId = { spellId = id, rank = 5 }, maxDots = 3, maxOverlap = overlap and const(overlap) }
            return { action = { multidot = m, condition = cond } }
        end
        local text, omitted, _, header = apl.translate({
            priorityList = {
                multidot(400, "0ms"),
                multidot(400, "2s", cmp("OpGt", { currentRage = {} }, const("10"))),
                multidot(400), -- no maxOverlap (protojson's zero value): 0
                multidot(999, "0ms"), -- an unmapped DoT: the whole entry (rule 2)
            },
        }, ctx({}))
        assert.are.equal(
            table.concat({
                "actions=dot,if=debuff.dot.remains<=0",
                "actions+=/dot,if=(rage.lo>10&debuff.dot.remains<=2)",
                "actions+=/dot,if=debuff.dot.remains<=0",
            }, "\n"),
            text
        )
        assert.are.same({ "default #4: spell 999" }, omitted)
        local dev = "multidot keeps the DoT on up to 3 targets in wowsims; this line is for the current target only."
        assert.are.same({
            "# Deviation: default #1: " .. dev,
            "# Deviation: default #2: " .. dev,
            "# Deviation: default #3: " .. dev,
        }, header)
    end)

    it("adds a required talent only once: not when the condition already has it as an & term", function()
        local rage = cmp("OpGt", { currentRage = {} }, const("10"))
        local known = { auraIsKnown = { auraId = { spellId = 900 } } } -- the talent furious's spell
        local text = apl.translate({
            priorityList = { cast(100, AND(rage, OR(known, known))), cast(100, known), cast(100, OR(rage, known)) },
        }, ctx({ requires = { strike = "furious" } }))
        assert.are.equal(
            table.concat({
                "actions=strike,if=(rage.lo>10&talent.furious.enabled)",
                "actions+=/strike,if=talent.furious.enabled",
                "actions+=/strike,if=talent.furious.enabled&(rage.lo>10|talent.furious.enabled)",
            }, "\n"),
            text
        )
    end)

    it("appends a recipe's guard to each line of its action, in every list, after a required talent", function()
        local rage = cmp("OpGt", { currentRage = {} }, const("10"))
        local text = apl.translate({
            prepullActions = { { action = cast(200).action, doAtValue = const("-1s") } },
            priorityList = { cast(200, OR(rage, ready)), cast(100), cast(200, rage) },
        }, ctx({ requires = { big_hit = "cuts" }, guard = { big_hit = "buff.fury.remains>1|rage.lo>50" } }))
        assert.are.equal(
            table.concat({
                "actions.precombat=big_hit,if=talent.cuts.enabled&(buff.fury.remains>1|rage.lo>50)",
                "actions=big_hit,if=(talent.cuts.enabled&(rage.lo>10|cooldown.big_hit.ready))&(buff.fury.remains>1|rage.lo>50)",
                "actions+=/strike",
                "actions+=/big_hit,if=talent.cuts.enabled&rage.lo>10&(buff.fury.remains>1|rage.lo>50)",
            }, "\n"),
            text
        )
    end)

    it(
        "replaces each line's condition of a recipe's condition action, before its guard, and refuses an unused one",
        function()
            local rage = cmp("OpGt", { currentRage = {} }, const("10"))
            local text = apl.translate(
                { priorityList = { cast(200, OR(rage, ready)), cast(100, rage), cast(200) } },
                ctx({ condition = { big_hit = "rage.lo>40" }, guard = { big_hit = "buff.fury.up" } })
            )
            assert.are.equal(
                table.concat({
                    "actions=big_hit,if=rage.lo>40&buff.fury.up",
                    "actions+=/strike,if=rage.lo>10",
                    "actions+=/big_hit,if=rage.lo>40&buff.fury.up",
                }, "\n"),
                text
            )
            assert.has_error(function()
                apl.translate({ priorityList = { cast(100) } }, ctx({ condition = { big_hit = "rage.lo>40" } }))
            end, "condition: no big_hit cast line")
        end
    )

    -- L11: the recipe's condition replaces the APL's even where the APL's folds false (it was "never", then a
    -- spurious "condition: no <key> cast line" error)
    it("replaces an APL condition that folds false with the recipe's condition", function()
        local never = AND(ready, const("false"))
        local text, omitted = apl.translate(
            { priorityList = { cast(200, never), cast(100, never) } },
            ctx({ condition = { big_hit = "rage.lo>40" } })
        )
        assert.are.equal("actions=big_hit,if=rage.lo>40", text)
        assert.are.same({ "default #2: never" }, omitted)
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

    it(
        "reads unitDistance against a whole number as the target's within/outside, OpEq omitted, else dropped",
        function()
            local d = { unitDistance = { sourceUnit = { type = "Self" } } }
            local text, omitted = apl.translate({
                priorityList = {
                    cast(100, cmp("OpLe", d, { variableRef = { name = "Melee range" } })),
                    cast(200, cmp("OpGt", d, const("8"))),
                    cast(300, cmp("OpGe", const("11.00"), d)), -- N >= d: within
                    cast(400, cmp("OpEq", d, const("5"))),
                    cast(400, cmp("OpLe", d, const("5.5"))), -- a non-integer: a movement term (rule 18), dropped
                },
                valueVariables = { { name = "Melee range", value = const("5.00") } },
            }, ctx())
            assert.are.equal(
                table.concat({
                    "actions=strike,focus=1,if=target.within5",
                    "actions+=/big_hit,if=target.outside8",
                    "actions+=/roar,use_off_gcd=1,if=target.within11",
                    "actions+=/dot",
                }, "\n"),
                text
            )
            assert.are.same({ "default #4: unitDistance OpEq 5" }, omitted)
        end
    )

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
                "actions=strike,if=rage.lo>10",
                "actions+=/strike,if=rage.lo>10",
                "actions+=/strike",
                "actions+=/strike,if=(rage.lo>10&execute_phase)",
                "actions+=/strike",
                "actions+=/strike,if=rage.lo>10",
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
            -- no aura registered under big_hit: an ability's key is an aura read only where the kit has that aura
            -- (rule 12's nil, its branch dropped); its auraIsKnown stays the ability's known test (rule 4)
            assert.are.equal(
                "actions=big_hit\nactions+=/strike,focus=1,if=action.big_hit.known",
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
        -- split at the first term's known end (the pin's sequence condition nests `))&` inside bf, re-pin e2842f0a78)
        local at = "((action.blood_fury.known&prev.1.blood_fury)|(!action.blood_fury.known&" .. bf .. "))"
        assert.are.equal(at .. "&", ar:sub(1, #at + 1))
        local rest = ar:sub(#at + 2)
        -- the rest of its sequence's condition: Slice and Dice up and Adrenaline Rush ready, not Blood Fury's readiness
        assert.is_truthy(
            rest:find("buff.slice_and_dice.up", 1, true) and rest:find("cooldown.adrenaline_rush.ready", 1, true)
        )
        assert.is_falsy(rest:find("blood_fury", 1, true))
        -- no longer omitted (the pin's Gnome-gated pooling group omits its own strictSequence of a waitUntil)
        assert.is_falsy(simc:find("# Omitted: default #%d+: strictSequence"))
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

    it("groups an | condition before a guard's & term, on cast and automatic lines alike", function()
        local early = OR(cmp("OpGe", { currentTime = {} }, const("5s")), cmp("OpGt", { currentRage = {} }, const("10")))
        local kit = {
            abilities = {
                big_hit = { key = "big_hit", id = 200, gcd = "spell" },
                roar = { key = "roar", id = 300, gcd = "off" },
            },
            auras = {},
        }
        local guard = { big_hit = "rage.lo>50", roar = "rage.lo>50|time>9" }
        local text = apl.translate({
            priorityList = { cast(200, early), { action = { autocastOtherCooldowns = {}, condition = early } } },
        }, apl.context(kit, { guard = guard }, LOG))
        assert.are.equal(
            table.concat({
                "actions=big_hit,if=(time>=5|rage.lo>10)&rage.lo>50",
                "actions+=/roar,use_off_gcd=1,if=(time>=5|rage.lo>10)&(rage.lo>50|time>9)",
            }, "\n"),
            text
        )
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

    -- Rule 13's racials: wowsims's autocast uses every racial major cooldown the class can have (sim/core/racials.go),
    -- not only the sampled race's; a defensive one only for a tank.
    it("expands every racial the class can have that wowsims's autocast would use, at the racial's place", function()
        local kit = {
            abilities = {
                roar = { key = "roar", id = 300, gcd = "off" },
                trinket = { key = "trinket", id = -1, item = 555, gcd = "off" },
                stoneform = { key = "stoneform", id = 20594, gcd = "spell" },
                eureka = { key = "eureka", id = 1259813, copy = { 1259812, 1259817, 1259821, 1259823 }, gcd = "off" },
                elunes_light = { key = "elunes_light", id = 1259799, gcd = "off" },
                blood_fury = { key = "blood_fury", id = 20572, gcd = "off" },
                shatter_curse = { key = "shatter_curse", id = 1299026, gcd = "spell" },
                berserking = { key = "berserking", id = 20554, gcd = "off" },
            },
            auras = {},
        }
        local function log(...)
            local out = { "# wowsims 0123 test seed 1 10 s target 63" }
            for i, b in ipairs({ ... }) do
                out[#out + 1] = ("[%d.00] [Tester (#1)] Major cooldown used: {%s}"):format(i, b)
            end
            return table.concat(out, "\n")
        end
        local orc = log("ItemID: 555", "SpellID: 20572", "SpellID: 300") -- the sampled Orc's Blood Fury second
        local auto =
            { action = { autocastOtherCooldowns = {}, condition = cmp("OpGe", { currentTime = {} }, const("5s")) } }
        local function lines(class, text, tank, ...)
            local rotation = { priorityList = { ... } }
            rotation.priorityList[#rotation.priorityList + 1] = auto
            return (apl.translate(rotation, apl.context(kit, {}, text, { class = class }, nil, tank)))
        end
        local function want(...)
            local out = {}
            for i, x in ipairs({ ... }) do
                out[i] = (i == 1 and "actions=" or "actions+=/") .. x .. ",if=time>=5"
            end
            return table.concat(out, "\n")
        end
        -- every class racial in racials.go's order, where the sampled one was used; Stoneform and Shatter Curse
        -- (defensive only) are a tank's
        assert.are.equal(
            want(
                "trinket,use_off_gcd=1",
                "eureka,use_off_gcd=1",
                "elunes_light,use_off_gcd=1",
                "blood_fury,use_off_gcd=1",
                "berserking,use_off_gcd=1",
                "roar,use_off_gcd=1"
            ),
            lines("ClassWarrior", orc)
        )
        assert.are.equal(
            want(
                "trinket,use_off_gcd=1",
                "stoneform",
                "eureka,use_off_gcd=1",
                "elunes_light,use_off_gcd=1",
                "blood_fury,use_off_gcd=1",
                "shatter_curse",
                "berserking,use_off_gcd=1",
                "roar,use_off_gcd=1"
            ),
            lines("ClassWarrior", orc, true)
        )
        -- only the class's races (capabilities_auto_gen.ts CLASS_RACES): a Hunter is never a Gnome
        assert.are.equal(
            want(
                "trinket,use_off_gcd=1",
                "elunes_light,use_off_gcd=1",
                "blood_fury,use_off_gcd=1",
                "berserking,use_off_gcd=1",
                "roar,use_off_gcd=1"
            ),
            lines("ClassHunter", orc)
        )
        -- a sample with no racial (a Human's): the racials lead (registered first, all ready at the pull)
        assert.are.equal(
            want(
                "eureka,use_off_gcd=1",
                "blood_fury,use_off_gcd=1",
                "berserking,use_off_gcd=1",
                "trinket,use_off_gcd=1",
                "roar,use_off_gcd=1"
            ),
            lines("ClassMage", log("ItemID: 555", "SpellID: 300"))
        )
        -- a racial the APL casts itself is not wowsims's to autocast: its own line stands, not repeated, no note
        local text, omitted = apl.translate({
            priorityList = { cast(20572), cast(1259813), auto },
        }, apl.context(kit, {}, orc, { class = "ClassWarrior" }))
        assert.are.equal(
            table.concat({
                "actions=blood_fury,use_off_gcd=1",
                "actions+=/eureka,use_off_gcd=1",
                "actions+=/trinket,use_off_gcd=1,if=time>=5",
                "actions+=/elunes_light,use_off_gcd=1,if=time>=5",
                "actions+=/berserking,use_off_gcd=1,if=time>=5",
                "actions+=/roar,use_off_gcd=1,if=time>=5",
            }, "\n"),
            text
        )
        assert.are.same(
            { "default #3: autocastOtherCooldowns: spell 20572 is blood_fury, which the APL casts itself" },
            omitted
        )
        -- a Paladin tank's only racial cooldown is the Dwarf's; no log line at all still gives it
        assert.are.equal(want("stoneform"), lines("ClassPaladin", log(), true))
        assert.are.equal("", lines("ClassPaladin", log()))
        -- a defensive-health threshold or a cooldown timing (the player's `cooldowns`) is not modelled: an error
        local ok, err = pcall(
            apl.translate,
            { priorityList = { auto } },
            apl.context(
                kit,
                {},
                orc,
                { class = "ClassWarrior", cooldowns = { hpPercentForDefensives = 0.4 } },
                nil,
                true
            )
        )
        assert.is_false(ok)
        assert.matches("hpPercentForDefensives", err)
    end)
end)

-- Re-pin Phase 2 (docs/superpowers/plans/2026-11-03-wowsims-repin.md, Task 3): the reads e2842f0a78's APLs add.
describe("the wowsims APL translator's re-pin reads", function()
    local function one(cond, r)
        return apl.translate({ priorityList = { cast(100, cond) } }, ctx(r or {}))
    end
    local function lines(cond, r)
        return (one(cond, r))
    end
    local function spell(k, id)
        return { [k] = { spellId = { spellId = id } } }
    end

    it("talentIsKnown is the talent's enabled test (rank > 1: its rank); an ID no talent has is false", function()
        local function known(id, rank)
            return { talentIsKnown = { talentId = { spellId = id, rank = rank } } }
        end
        assert.are.equal("actions=strike,if=talent.cuts.enabled", lines(known(950, 1)))
        assert.are.equal("actions=strike,if=talent.cuts.enabled", lines(known(950)))
        assert.are.equal("actions=strike,if=talent.cuts.rank>=3", lines(known(950, 3)))
        assert.are.equal("actions=strike,if=talent.cuts.enabled", lines(known(951), { map = { [951] = "cuts" } }))
        local text, omitted = one(known(999, 1)) -- wowsims's constant false: the talent is not held
        assert.are.equal("", text)
        assert.are.same({ "default #1: never" }, omitted)
    end)

    -- R52: wowsims's tree holds a talent the kit has as an ability (Feral's Shifting Power): the ability's known test
    it(
        "talentIsKnown of an ID that resolves to a kit ability is the ability's known test; an aura's is false",
        function()
            local function known(id, rank)
                return { talentIsKnown = { talentId = { spellId = id, rank = rank } } }
            end
            assert.are.equal("actions=strike,if=action.big_hit.known", lines(known(200)))
            assert.are.equal("actions=strike,if=action.big_hit.known", lines(known(200, 2)))
            assert.are.equal("actions=strike,if=action.strike.known", lines(known(101)))
            assert.are.equal(
                "actions=strike,if=action.big_hit.known",
                lines(known(990), { map = { [990] = "big_hit" } })
            )
            local text, omitted = one(known(910)) -- an aura, no ability: still wowsims's constant false
            assert.are.equal("", text)
            assert.are.same({ "default #1: never" }, omitted)
        end
    )

    it("talentRank is the talent's rank; an ID no talent has reads 0", function()
        local function rank(id)
            return cmp("OpGe", { talentRank = { talentId = { spellId = id } } }, const("2"))
        end
        assert.are.equal("actions=strike,if=talent.cuts.rank>=2", lines(rank(950)))
        assert.are.equal("actions=strike,if=0>=2", lines(rank(999)))
    end)

    it("spellFullCooldown is the ability's cooldown duration, guarded while unlearned", function()
        local full = function(id)
            return cmp("OpGt", spell("spellFullCooldown", id), const("10s"))
        end
        assert.are.equal("actions=strike,if=(!action.big_hit.known|cooldown.big_hit.duration>10)", lines(full(200)))
        assert.are.equal("actions=strike,if=cooldown.strike.duration>10", lines(full(100)))
        local text, omitted = one(full(999))
        assert.are.equal("actions=strike", text)
        assert.are.same({ "default #1: dropped the unresolved spell 999 (its branch only)" }, omitted)
    end)

    it("gcdIsReady is gcd.remains<=0", function()
        assert.are.equal("actions=strike,if=gcd.remains<=0", lines({ gcdIsReady = {} }))
    end)

    -- wowsims reads the named spell's GCD (Arms's Slam line: Slam's 1 s cast against Mortal Strike's 1.5 s GCD), not
    -- the evaluated line's own (`gcd.execute` would read Slam's 1 s there)
    it("spellGcdHastedDuration is the named spell's action.<key>.gcd, guarded while it is unlearned", function()
        local g = function(id)
            return cmp("OpLt", spell("spellGcdHastedDuration", id), const("1.5s"))
        end
        assert.are.equal("actions=strike,if=(!action.big_hit.known|action.big_hit.gcd<1.5)", lines(g(200)))
        assert.are.equal("actions=strike,if=action.strike.gcd<1.5", lines(g(100)))
    end)

    it("currentHealth is health.current; another unit's is unsupported", function()
        assert.are.equal(
            "actions=strike,if=health.current>1000",
            lines(cmp("OpGt", { currentHealth = {} }, const("1000")))
        )
        local pet = cmp("OpGt", { currentHealth = { sourceUnit = { type = "Pet" } } }, const("1000"))
        local text, omitted = one(pet)
        assert.are.equal("", text)
        assert.are.same({ "default #1: currentHealth of Pet" }, omitted)
    end)

    it("auraDuration is the aura's duration on its unit, guarded; another player's is dropped", function()
        local function dur(id, u, tag)
            local v = { auraId = { spellId = id, tag = tag }, sourceUnit = u and { type = u } or nil }
            return cmp("OpGt", { auraDuration = v }, const("5s"))
        end
        assert.are.equal("actions=strike,if=(!talent.furious.enabled|buff.fury.duration>5)", lines(dur(900)))
        assert.are.equal(
            "actions=strike,if=(!action.dot.known|debuff.dot.duration>5)",
            lines(dur(400, "CurrentTarget"))
        )
        assert.are.equal("actions=strike", lines(dur(910, nil, -1)))
    end)

    it("dotBaseDuration is the DoT's duration on the target, guarded while unlearned", function()
        local d = cmp("OpGt", spell("dotBaseDuration", 400), const("10s"))
        assert.are.equal("actions=strike,if=(!action.dot.known|debuff.dot.duration>10)", lines(d))
    end)

    it("spellTravelTime is the ability's travel_time, guarded while unlearned", function()
        local t = cmp("OpLt", spell("spellTravelTime", 200), const("1s"))
        assert.are.equal("actions=strike,if=(!action.big_hit.known|action.big_hit.travel_time<1)", lines(t))
    end)

    it("druidBleedIsActive is the kit's druid_bleed_active", function()
        assert.are.equal("actions=strike,if=druid_bleed_active", lines({ druidBleedIsActive = {} }))
        assert.are.equal("actions=strike,if=!druid_bleed_active", lines(NOT({ druidBleedIsActive = {} })))
    end)

    -- CN4: the APL values upstream added after the pin (apl.proto 13813515ea, 39b31a66ee, baf3cc4c10; read at
    -- upstream/master 4b0030a44b, sim/core apl_values_targets.go, apl_values_aura.go, apl_values_dot.go)
    it("reads the on-any/all-target auras and DoTs on the current target, each with its deviation", function()
        local aura = function(k, id)
            return { [k] = { auraId = { spellId = id }, includeReactionTime = true } }
        end
        local text, omitted, _, header = apl.translate({
            priorityList = {
                cast(100, aura("auraIsActiveOnAllTargets", 400)),
                cast(100, aura("auraIsActiveOnAnyTarget", 400)),
                cast(100, NOT(spell("dotIsActiveOnAnyTarget", 400))),
                cast(100, aura("auraIsActiveOnAnyTarget", 999)), -- unresolved: wowsims's nil, dropped
            },
        }, ctx({}))
        assert.are.equal(
            table.concat({
                "actions=strike,if=(!action.dot.known|debuff.dot.up)",
                "actions+=/strike,if=(!action.dot.known|debuff.dot.up)",
                "actions+=/strike,if=(!action.dot.known|!debuff.dot.up)",
                "actions+=/strike",
            }, "\n"),
            text
        )
        assert.are.same({ "default #4: dropped the unresolved aura 999 (its branch only)" }, omitted)
        local all, any =
            'an "on all targets" read is the current target\'s only.',
            'an "on any target" read is the current target\'s only.'
        assert.are.same({
            "# Deviation: default #1: " .. all,
            "# Deviation: default #2: " .. any,
            "# Deviation: default #3: " .. any,
        }, header)
    end)

    it("reads the current target as active now and its death at the fight's end; other units unsupported", function()
        local other = { type = "Target", index = 1 }
        local text, omitted = apl.translate({
            priorityList = {
                cast(100, { targetIsActive = {} }),
                cast(
                    200,
                    cmp("OpLe", { timeUntilTargetActive = { targetUnit = { type = "CurrentTarget" } } }, const("0s"))
                ),
                cast(300, cmp("OpGt", { timeUntilTargetDies = {} }, const("20s"))),
                cast(400, { targetIsActive = { targetUnit = other } }),
                cast(400, cmp("OpGt", { timeUntilTargetDies = { targetUnit = other } }, const("1s"))),
                cast(400, cmp("OpGt", { numActiveAdds = {} }, const("0"))),
                cast(400, cmp("OpGt", { remainingCastTime = {} }, const("0s"))),
                cast(400, AND(E, { isExecutePhase = { threshold = "E20", targetUnit = other } })),
            },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions=strike,focus=1",
                "actions+=/big_hit,if=0<=0",
                "actions+=/roar,use_off_gcd=1,if=fight_remains>20",
            }, "\n"),
            text
        )
        assert.are.same({
            "default #4: targetIsActive of Target",
            "default #5: timeUntilTargetDies of Target",
            "default #6: numActiveAdds",
            "default #7: remainingCastTime",
            "default #8: isExecutePhase of Target",
        }, omitted)
    end)

    it("strictMultidot is rule 17's current-target multidot line, with its deviation", function()
        local m = { spellId = { spellId = 400 }, maxDots = 2, maxOverlap = const("1s") }
        local text, omitted, _, header = apl.translate({
            priorityList = { { action = { strictMultidot = m } } },
        }, ctx({}))
        assert.are.equal("actions=dot,if=debuff.dot.remains<=1", text)
        assert.are.same({}, omitted)
        assert.are.same({
            "# Deviation: default #1: multidot keeps the DoT on up to 2 targets in wowsims;"
                .. " this line is for the current target only.",
        }, header)
    end)
end)

describe("the wowsims APL translator's casting, range, curse and cast-time pre-pull reads", function()
    local function one(cond)
        return apl.translate({ priorityList = { cast(100, cond) } }, ctx({}))
    end
    local function spell(k, id)
        return { [k] = { spellId = { spellId = id } } }
    end
    local function mul(x, k)
        return { math = { op = "OpMul", lhs = x, rhs = const(k) } }
    end

    it("spellIsCasting is the ability's executing with a cast time, false for an instant", function()
        local text = apl.translate({ priorityList = { cast(500, NOT(spell("spellIsCasting", 500))) } }, ctx({}))
        assert.are.equal("actions=starfire,if=!action.starfire.executing", text)
        assert.are.equal("actions=strike", (one(NOT(spell("spellIsCasting", 100))))) -- the not of false folds true
        assert.are.equal(
            "actions=strike,if=(!action.starfire.known|!action.starfire.executing)",
            (one(NOT(spell("spellIsCasting", 500))))
        )
        assert.are.equal( -- a cast-time function, read under the stand-in state
            "actions=strike,if=(!action.pyroblast.known|action.pyroblast.executing)",
            (one(spell("spellIsCasting", 600)))
        )
        local text2, omitted = one(spell("spellIsCasting", 999))
        assert.are.equal("actions=strike", text2)
        assert.are.same({ "default #1: dropped the unresolved spell 999 (its branch only)" }, omitted)
    end)

    it("totemRemainingTime with no totemType (TypeUnknownTotem, protojson's zero) is wowsims's nil node", function()
        assert.are.equal("actions=strike", (one(cmp("OpGt", { totemRemainingTime = {} }, const("1")))))
    end)

    it("spellInRange is the ability's in_range, guarded while unlearned", function()
        assert.are.equal("actions=strike,if=action.strike.in_range", (one(spell("spellInRange", 100))))
        assert.are.equal(
            "actions=strike,if=(!action.big_hit.known|action.big_hit.in_range)",
            (one(spell("spellInRange", 200)))
        )
    end)

    it("a doAtValue that folds from the kit's cast time orders its pre-pull line by that constant", function()
        local function at(id, v)
            local e = cast(id)
            e.doAtValue = type(v) == "table" and v or const(v)
            return e
        end
        local castTime = function(id)
            return spell("spellCastTime", id)
        end
        local text, omitted = apl.translate({
            prepullActions = {
                at(100, "-1.5s"),
                at(600, mul(castTime(600), "-1")), -- Pyroblast: -6
                at(300, "-10s"),
                at(200, mul({ math = { op = "OpAdd", lhs = castTime(500), rhs = castTime(600) } }, "-1")), -- -9
                at(400, mul(castTime(100), "-1")), -- an instant: at the pull
                at(500, mul(spell("spellTravelTime", 600), "-1")), -- no velocity: wowsims's 0 s travel, at the pull
                at(500, mul(castTime(999), "-1")), -- an unresolved spell
            },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions.precombat=roar,use_off_gcd=1",
                "actions.precombat+=/big_hit",
                "actions.precombat+=/pyroblast",
                "actions.precombat+=/strike",
                "actions.precombat+=/dot",
                "actions.precombat+=/starfire",
            }, "\n"),
            text
        )
        assert.are.same({
            "precombat #7: doAtValue not a constant",
        }, omitted)
    end)

    -- CN4: upstream 901c5b8cfd times Arcane's Read Ley Line at -(Arcane Wrath's cast + its own GCD)
    it("a doAtValue that folds a spell's GCD (spellGcdHastedDuration) uses the kit's unhasted GCD, noted", function()
        local function at(id, v)
            local e = cast(id)
            e.doAtValue = v
            return e
        end
        local function neg(x)
            return mul(x, "-1")
        end
        local function add(a, b)
            return { math = { op = "OpAdd", lhs = a, rhs = b } }
        end
        local text, omitted, _, header = apl.translate({
            prepullActions = {
                at(500, neg(spell("spellCastTime", 500))), -- -3
                -- off the GCD: wowsims's floor, max(1 s, hasted 0) (apl_values_spell.go:402-409; 0 only for a spell
                -- that ignores haste, which the kit cannot tell): -1, before the -0.5 line
                at(300, neg(spell("spellGcdHastedDuration", 300))),
                at(200, neg(add(spell("spellCastTime", 500), spell("spellGcdHastedDuration", 200)))), -- -4.5
                at(100, const("-0.5s")),
                at(400, neg(spell("spellGcdHastedDuration", 999))), -- an unresolved spell
            },
        }, ctx({}))
        assert.are.equal(
            table.concat({
                "actions.precombat=big_hit",
                "actions.precombat+=/starfire",
                "actions.precombat+=/roar,use_off_gcd=1",
                "actions.precombat+=/strike",
            }, "\n"),
            text
        )
        assert.are.same({ "precombat #5: doAtValue not a constant" }, omitted)
        local cast, gcd =
            "the pre-pull time uses the kit's base cast time; wowsims uses the hasted cast.",
            "the pre-pull time uses the kit's unhasted GCD (1 s off the GCD, wowsims's floor); wowsims uses the hasted GCD."
        assert.are.same({
            "# Deviation: precombat #3: " .. cast,
            "# Deviation: precombat #3: " .. gcd,
            "# Deviation: precombat #1: " .. cast,
            "# Deviation: precombat #2: " .. gcd,
        }, header)
    end)

    it(
        "a build without curseOptions plays the zero value's curse (Elements); the all-targets reads are this target's",
        function()
            local r = {
                select = {
                    castAssigned = {
                        setting = "pick",
                        option = "pickOption",
                        zero = "Elements",
                        candidates = { Elements = "dot", NoCurse = false },
                        active = "assignedIsActive",
                        activeAll = "assignedIsActiveOnAllTargets",
                        is = "isAssigned",
                    },
                },
            }
            local entries = {
                { action = { castAssigned = {} } },
                cast(100, { isAssigned = { curseType = "NoCurse" } }),
                cast(100, { assignedIsActiveOnAllTargets = {} }),
                cast(100, spell("dotIsActiveOnAllTargets", 400)),
            }
            local text, omitted, _, header =
                apl.translate({ priorityList = entries }, ctx(r, { warlock = { options = { classOptions = {} } } }))
            local dev = 'an "on all targets" read is the current target\'s only.'
            assert.are.equal(
                table.concat({
                    "actions=dot,if=settings.pick='elements'",
                    "actions+=/strike,if=settings.pick='nocurse'",
                    "actions+=/strike,if=((action.dot.known&settings.pick='elements'&debuff.dot.up))", -- rule 16's OR, of one
                    "actions+=/strike,if=(!action.dot.known|debuff.dot.up)",
                }, "\n"),
                text
            )
            assert.are.same({}, omitted)
            assert.are.same({
                "# Setting pick (choice of pickOption: elements, nocurse), default elements in game and in the harness.",
                "# Deviation: default #3: " .. dev,
                "# Deviation: default #4: " .. dev,
            }, header)
            -- a recipe with no select: each select read is unsupported; the Banes have no recipe hook
            local _, none = apl.translate({ priorityList = entries }, ctx({}))
            assert.are.same({
                "default #1: castAssigned",
                "default #2: isAssigned",
                "default #3: assignedIsActiveOnAllTargets",
            }, none)
            local _, bane = one({ warlockBaneIsActiveOnAllTargets = {} })
            assert.are.same({ "default #1: warlockBaneIsActiveOnAllTargets" }, bane)
        end
    )
end)

-- Re-pin plan Task 5 (rule 18, decision 8): movement terms are wowsims's nil; a negated bracket is the opposite one.
describe("the wowsims APL translator's movement terms", function()
    local d = { unitDistance = { sourceUnit = { type = "Self" } } }
    local speed = { unitMovementSpeed = { sourceUnit = { type = "Self" } } }
    local function run(entries, vars)
        return apl.translate({ priorityList = entries, valueVariables = vars }, ctx({}))
    end

    it("drops a walk time (math over yards and run speed) and keeps the timing term", function()
        local walk =
            { math = { op = "OpDiv", lhs = { math = { op = "OpSub", lhs = d, rhs = const("5") } }, rhs = speed } }
        local mh = { autoTimeToNext = { autoType = "MainHandAuto" } }
        local text, omitted, _, header = run({
            cast(
                100,
                AND(
                    cmp("OpLe", { variableRef = { name = "Time to walk in" } }, const("0s")),
                    cmp("OpGt", mh, const("0.5s"))
                )
            ),
        }, { { name = "Time to walk in", value = walk } })
        assert.are.equal("actions=strike,if=mainhand_remains>0.5", text)
        assert.are.same({}, omitted)
        assert.are.same({
            "# Dropped (movement): default #1: unitDistance",
            "# Dropped (movement): default #1: unitMovementSpeed",
            '# Dropped (movement): default #1: variable "Time to walk in"', -- R17: each variable it drops
        }, header)
    end)

    -- R17: yards are a type. A move's rangeFromTarget and a unitDistance comparison make their variables yards (and
    -- what feeds them); math over yards (the old pin's walk time, a yard difference over a run-speed constant) is a
    -- movement term, and so is every variable that depends on it, each listed.
    it("drops math over yards (a yard difference over a speed constant) and every variable that reads it", function()
        local mh = { autoTimeToNext = { autoType = "MainHandAuto" } }
        local rng = { autoTimeToNext = { autoType = "RangedAuto" } }
        local function var(name)
            return { variableRef = { name = name } }
        end
        local yd = { math = { op = "OpSub", lhs = var("Ranged range"), rhs = var("Melee range") } }
        local vars = {
            { name = "Melee range", value = const("5.00") },
            { name = "Ranged range", value = const("11.00") },
            { name = "Start", value = var("Ranged range") },
            {
                name = "Move duration",
                value = {
                    math = {
                        op = "OpMul",
                        lhs = const("1s"),
                        rhs = { math = { op = "OpDiv", lhs = yd, rhs = const("7") } },
                    },
                },
            },
            {
                name = "Auto Shot wait",
                value = { math = { op = "OpAdd", lhs = var("Move duration"), rhs = const("0.2s") } },
            },
        }
        local text, omitted, _, header = run({
            { action = { move = { rangeFromTarget = var("Start") } } },
            cast(100, AND(cmp("OpLe", mh, var("Move duration")), cmp("OpGe", rng, var("Auto Shot wait")))),
            cast(200, cmp("OpLe", d, var("Melee range"))),
            cast(300, cmp("OpGt", mh, const("0.5s"))),
            -- R17 refined: the old pin's Multi-Shot shape keeps its timing addend; a factor still drops the whole term
            cast(
                100,
                cmp("OpLe", {
                    math = {
                        op = "OpAdd",
                        lhs = { spellCastTime = { spellId = { spellId = 100 } } },
                        rhs = var("Move duration"),
                    },
                }, mh)
            ),
            cast(
                200,
                AND(cmp("OpLe", { math = { op = "OpMul", lhs = const("2"), rhs = var("Move duration") } }, mh), up)
            ),
        }, vars)
        assert.are.equal(
            table.concat({
                "actions=strike,if=ranged_remains>=0.2",
                "actions+=/big_hit,if=target.within5",
                "actions+=/roar,use_off_gcd=1,if=mainhand_remains>0.5",
                "actions+=/strike,if=action.strike.cast<=mainhand_remains",
                "actions+=/big_hit,if=(!action.dot.known|buff.dot.up)",
            }, "\n"),
            text
        )
        assert.are.same({ "default #1: move" }, omitted)
        assert.are.same({
            "# Dropped (movement): default #2: yards math",
            '# Dropped (movement): default #2: variable "Move duration"',
            "# Dropped (movement): default #5: yards math",
            '# Dropped (movement): default #5: variable "Move duration"',
            "# Dropped (movement): default #6: yards math",
            '# Dropped (movement): default #6: variable "Move duration"',
        }, header)
    end)

    it("unitIsMoving (any unit) alone is a line with no condition", function()
        local text, omitted, _, header =
            run({ cast(100, { unitIsMoving = { sourceUnit = { type = "CurrentTarget" } } }) })
        assert.are.equal("actions=strike", text)
        assert.are.same({}, omitted)
        assert.are.same({ "# Dropped (movement): default #1: unitIsMoving" }, header)
    end)

    it("a negated bracket is the opposite bracket; yards against a max() drop", function()
        local text, omitted, _, header = run({
            cast(100, NOT(cmp("OpGt", d, const("5")))),
            cast(200, NOT(cmp("OpLt", d, const("8")))),
            cast(300, cmp("OpNe", d, { max = { vals = { const("11"), const("13") } } })),
        })
        assert.are.equal(
            table.concat({
                "actions=strike,if=target.within5",
                "actions+=/big_hit,if=target.outside8",
                "actions+=/roar,use_off_gcd=1",
            }, "\n"),
            text
        )
        assert.are.same({}, omitted)
        assert.are.same({ "# Dropped (movement): default #3: unitDistance" }, header)
    end)

    it("a call of an empty group lists no dropped term", function()
        local text, _, _, header = apl.translate({
            priorityList = {
                { action = { groupReference = { groupName = "Walk" }, condition = { unitIsMoving = {} } } },
                cast(100),
            },
            groups = { { name = "Walk", actions = { { action = { move = {} } } } } },
        }, ctx({}))
        assert.are.equal("actions=strike", text)
        assert.are.same({}, header)
    end)

    it("a pre-pull time folded from the kit's cast time is a deviation (wowsims folds the hasted cast)", function()
        local e = cast(500)
        e.doAtValue =
            { math = { op = "OpMul", lhs = { spellCastTime = { spellId = { spellId = 500 } } }, rhs = const("-1") } }
        local e2 = cast(100)
        e2.doAtValue = const("-1s")
        local _, _, _, header = apl.translate({ prepullActions = { e, e2 } }, ctx({}))
        assert.are.same({
            "# Deviation: precombat #1: the pre-pull time uses the kit's base cast time; wowsims uses the hasted cast.",
        }, header)
    end)
end)

-- Re-pin plan Task 7 (design §2.2, §3a; rulings R4, R7): rule 19, a move's reached entries take
-- `(toggle.movement&<move condition>|<range gate>)`; rule 14b, a wowsims `sequence` is a stepped window.
describe("the wowsims APL translator's move rewrite and sequences as windows", function()
    local d = { unitDistance = {} }
    local mh = { autoTimeToNext = { autoType = "MainHandAuto" } }
    local stance = { auraIsActive = { auraId = { spellId = 910 } } }
    local function move(yd, cond)
        return { action = { move = { rangeFromTarget = const(yd) }, condition = cond } }
    end
    local function waitUntil(gate, cond)
        return { action = { waitUntil = { condition = gate }, condition = cond } }
    end
    local function inRange(id)
        return { spellInRange = { spellId = { spellId = id } } }
    end
    local function lines(t)
        return table.concat(t, "\n")
    end

    it("Feral-shaped: the omitted waitUntil's gate is carried, and the move before it reaches it", function()
        local text, omitted, _, header = apl.translate({
            priorityList = {
                move("5", cmp("OpGt", d, const("5"))),
                waitUntil(NOT(cmp("OpGt", d, const("5"))), cmp("OpGt", d, const("5"))),
                cast(100, stance), -- Review Focus 4: the line's own condition stays outside the gate
            },
        }, ctx({}))
        assert.are.equal("actions=strike,if=buff.stance.up&(toggle.movement&target.outside5|target.within5)", text)
        assert.are.same({ "default #1: move", "default #2: waitUntil" }, omitted)
        assert.are.same({ "# Movement: default #1 reaches default: strike" }, header)
    end)

    it("weave-shaped: a melee move under a timing condition reaches the strike's bracket", function()
        local text, omitted = apl.translate({
            priorityList = {
                move("5", AND(cmp("OpGt", mh, const("0.5s")), cmp("OpGt", d, const("5")))),
                cast(100, cmp("OpLe", d, const("5"))),
            },
        }, ctx({}))
        assert.are.equal(
            "actions=strike,if=(toggle.movement&(mainhand_remains>0.5&target.outside5)|target.within5)",
            text
        )
        assert.are.same({ "default #1: move" }, omitted)
    end)

    it("R4: a group's move reaches the calling list's entries before the call, by bracket or kit range", function()
        local text, omitted, _, header = apl.translate({
            priorityList = {
                cast(100, cmp("OpLe", d, const("5"))),
                cast(200), -- no bracket: the recipe's DB2 range (0-5)
                { action = { groupReference = { groupName = "Weave" }, condition = E } },
            },
            groups = { { name = "Weave", actions = { move("5", cmp("OpGt", mh, const("0.5s"))), cast(400) } } },
        }, ctx({ executePhase = "execute_phase", ranges = { big_hit = { 0, 5 } } }))
        assert.are.equal( -- R51: the in-range arms in place, the move arms (in line order) where the call is
            lines({
                "actions=strike,if=target.within5",
                "actions+=/big_hit,if=target.within5",
                "actions+=/strike,if=toggle.movement&(execute_phase&mainhand_remains>0.5)",
                "actions+=/big_hit,if=toggle.movement&(execute_phase&mainhand_remains>0.5)",
                "actions+=/call_action_list,name=weave,if=execute_phase",
                "actions.weave=dot",
            }),
            text
        )
        assert.are.same({ "weave #1: move" }, omitted)
        assert.are.same({ "# Movement: weave #1 reaches default: strike, big_hit" }, header)
    end)

    it(
        "R51 Hunter-shaped: a shot above the last-called move group keeps its rank over the strike's move arm",
        function()
            local text, _, _, header = apl.translate({
                priorityList = {
                    cast(100, cmp("OpLe", d, const("5"))),
                    cast(500), -- the shot: no range read, no recipe range
                    { action = { groupReference = { groupName = "Weave" }, condition = E } },
                },
                groups = { { name = "Weave", actions = { move("5", cmp("OpGt", mh, const("0.5s"))) } } },
            }, ctx({ executePhase = "execute_phase" }))
            assert.are.equal(
                lines({
                    "actions=strike,if=target.within5",
                    "actions+=/starfire",
                    "actions+=/strike,if=toggle.movement&(execute_phase&mainhand_remains>0.5)",
                }),
                text
            )
            assert.are.same({ "# Movement: weave #1 reaches default: strike" }, header)
        end
    )

    it("R51: two reached lines right after one move: both arms at the move, in line order, then both gates", function()
        local text = apl.translate({
            priorityList = {
                move("5", cmp("OpGt", mh, const("0.5s"))),
                cast(100, cmp("OpLe", d, const("5"))),
                cast(200, cmp("OpLe", d, const("5"))),
            },
        }, ctx({}))
        assert.are.equal(
            lines({
                "actions=strike,if=toggle.movement&mainhand_remains>0.5",
                "actions+=/big_hit,if=toggle.movement&mainhand_remains>0.5",
                "actions+=/strike,if=target.within5",
                "actions+=/big_hit,if=target.within5",
            }),
            text
        )
    end)

    it("R51: a move above a reached line with an unreached line between puts the arm above that line", function()
        local text = apl.translate({
            priorityList = {
                move("5", cmp("OpGt", mh, const("0.5s"))),
                cast(500),
                cast(100, cmp("OpLe", d, const("5"))),
            },
        }, ctx({}))
        assert.are.equal(
            lines({
                "actions=strike,if=toggle.movement&mainhand_remains>0.5",
                "actions+=/starfire",
                "actions+=/strike,if=target.within5",
            }),
            text
        )
    end)

    it("two moves reaching one strike join their conditions with | in one toggle term", function()
        local text, _, _, header = apl.translate({
            priorityList = {
                move("5", cmp("OpGt", mh, const("0.5s"))),
                move("5", E),
                cast(100, cmp("OpLe", d, const("5"))),
            },
        }, ctx({ executePhase = "execute_phase" }))
        assert.are.equal(
            "actions=strike,if=(toggle.movement&(mainhand_remains>0.5|execute_phase)|target.within5)",
            text
        )
        assert.are.same({
            "# Movement: default #1 reaches default: strike",
            "# Movement: default #2 reaches default: strike",
        }, header)
    end)

    it("a move to another range reaches nothing, and a list with no move is unchanged", function()
        local text, _, _, header = apl.translate({
            priorityList = { move("11", cmp("OpGt", mh, const("0.5s"))), cast(100, cmp("OpLe", d, const("5"))) },
        }, ctx({}))
        assert.are.equal("actions=strike,if=target.within5", text)
        assert.are.same({}, header)
        assert.are.equal(
            "actions=strike,if=target.within5",
            (apl.translate({ priorityList = { cast(100, cmp("OpLe", d, const("5"))) } }, ctx({})))
        )
    end)

    it("Retribution-shaped (S3): each sequence is a stepped window, its trailing gate held while it is up", function()
        local text, omitted, _, header = apl.translate({
            priorityList = {
                { action = { groupReference = { groupName = "Move to melee" }, condition = NOT(inRange(100)) } },
                cast(200),
                cast(100),
            },
            groups = {
                {
                    name = "Move to melee",
                    actions = {
                        {
                            action = {
                                condition = AND(
                                    { talentIsKnown = { talentId = { spellId = 900 } } },
                                    NOT({ sequenceIsComplete = { sequenceName = "move1" } })
                                ),
                                sequence = {
                                    name = "move1",
                                    actions = {
                                        { move = { rangeFromTarget = const("5") } },
                                        { waitUntil = { condition = inRange(200) } },
                                        { castSpell = { spellId = { spellId = 200 } } },
                                        { wait = { duration = { inputDelay = {} } } },
                                        { castSpell = { spellId = { spellId = 400 } } },
                                        { waitUntil = { condition = inRange(100) } },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }, ctx({}))
        local held = "(toggle.movement&window.move1.up|(!action.strike.known|action.strike.in_range)|!window.move1.up)"
        assert.are.equal(
            lines({
                "actions=call_action_list,name=move_to_melee,if=(!action.strike.known|!action.strike.in_range)",
                "actions+=/big_hit,if=" .. held,
                "actions+=/strike,if=" .. held,
                "actions.move_to_melee=big_hit,if=window.move1.next.big_hit"
                    .. "&(toggle.movement&window.move1.up|action.big_hit.in_range)",
                "actions.move_to_melee+=/dot,if=window.move1.next.dot",
            }),
            text
        )
        assert.are.same({}, omitted)
        assert.are.same({
            "# Window: move1: steps big_hit, dot; on_deviation stay; evaluator talent.furious.enabled (the class registers it).",
            "# Movement: move_to_melee #1 reaches move_to_melee: big_hit; default: big_hit, strike",
        }, header)
    end)

    it("resetSequence is the window's loop; sequenceIsComplete elsewhere reads the window down", function()
        local seq = {
            action = {
                condition = { talentIsKnown = { talentId = { spellId = 950 } } },
                sequence = {
                    name = "HHA",
                    actions = {
                        { castSpell = { spellId = { spellId = 100 } } },
                        { castSpell = { spellId = { spellId = 100 } } },
                        { castSpell = { spellId = { spellId = 200 } } },
                    },
                },
            },
        }
        local done = { sequenceIsComplete = { sequenceName = "HHA" } }
        local text, omitted, _, header = apl.translate({
            priorityList = {
                { action = { resetSequence = { sequenceName = "HHA" }, condition = done } },
                seq,
                cast(400, done),
            },
        }, ctx({}))
        assert.are.equal(
            lines({
                "actions=strike,if=window.hha.next.strike",
                "actions+=/big_hit,if=window.hha.next.big_hit",
                "actions+=/dot,if=!window.hha.up",
            }),
            text
        )
        assert.are.same({ "default #1: resetSequence" }, omitted)
        assert.are.same({
            "# Window: hha: steps strike, strike, big_hit; loop; on_deviation stay; evaluator talent.cuts.enabled (the class registers it).",
        }, header)
    end)

    it("a sequence whose condition the belief cannot read is omitted, and so are its window's readers", function()
        local seq = {
            action = {
                condition = E,
                sequence = { name = "S", actions = { { castSpell = { spellId = { spellId = 100 } } } } },
            },
        }
        local text, omitted = apl.translate({
            priorityList = { seq, cast(400, { sequenceIsComplete = { sequenceName = "S" } }), cast(200) },
        }, ctx({ executePhase = "execute_phase" }))
        assert.are.equal("actions=big_hit", text)
        assert.are.same({
            "default #1: sequence s: its condition is not readable by the belief (execute_phase)",
            "default #2: reads window s, whose sequence was omitted",
        }, omitted)
    end)

    it("a double not over a bracket is the bracket; a not over and/or with one pushes inside (De Morgan)", function()
        local text = apl.translate({
            priorityList = {
                cast(100, NOT(NOT(cmp("OpGt", d, const("5"))))),
                cast(200, NOT(AND(cmp("OpGt", d, const("5")), stance))),
                cast(300, NOT(OR(cmp("OpLt", d, const("8")), stance))),
            },
        }, ctx({}))
        assert.are.equal(
            lines({
                "actions=strike,if=target.outside5",
                "actions+=/big_hit,if=(target.within5|!buff.stance.up)",
                "actions+=/roar,use_off_gcd=1,if=(target.outside8&!buff.stance.up)",
            }),
            text
        )
    end)

    it("Demonology-shaped: a bracket inside one grouped conjunction is reached; one inside an or is not", function()
        local text, _, _, header = apl.translate({
            priorityList = {
                move("5", AND(E, cmp("OpGt", d, const("5")))),
                cast(200, AND(E, cmp("OpLe", d, const("5")))),
                cast(400, OR(AND(E, cmp("OpLe", d, const("5"))), up)),
            },
        }, ctx({ executePhase = "execute_phase" }))
        assert.are.equal(
            lines({
                "actions=big_hit,if=execute_phase&(toggle.movement&(execute_phase&target.outside5)|target.within5)",
                "actions+=/dot,if=((execute_phase&target.within5)|buff.dot.up)",
            }),
            text
        )
        assert.are.same({ "# Movement: default #1 reaches default: big_hit" }, header)
    end)

    it("weave-shaped: the move back to the shoot spot reaches the shots (outside5 or a DB2 minimum range)", function()
        local spot = { max = { vals = { const("13.19"), const("11.67") } } } -- the hunters' "Shoot spot"
        local text, omitted, _, header = apl.translate({
            priorityList = {
                cast(100, cmp("OpLe", d, const("5"))),
                cast(500, cmp("OpGt", d, const("5"))),
                cast(400), -- no bracket: the recipe's DB2 range (5-35)
                { action = { groupReference = { groupName = "Weave" }, condition = E } },
            },
            groups = {
                {
                    name = "Weave",
                    actions = {
                        move("5", AND(cmp("OpGt", mh, const("0.5s")), cmp("OpGt", d, const("5")))),
                        { action = { move = { rangeFromTarget = spot } } },
                        cast(200),
                    },
                },
            },
        }, ctx({ executePhase = "execute_phase", ranges = { dot = { 5, 35 } } }))
        assert.are.equal( -- R51: weave #1's arm (the strike) before weave #2's (the shots), both where the call is
            lines({
                "actions=strike,if=target.within5",
                "actions+=/starfire,if=target.outside5",
                "actions+=/dot,if=target.outside5",
                "actions+=/strike,if=toggle.movement&(execute_phase&(mainhand_remains>0.5&target.outside5))",
                "actions+=/starfire,if=toggle.movement&execute_phase",
                "actions+=/dot,if=toggle.movement&execute_phase",
                "actions+=/call_action_list,name=weave,if=execute_phase",
                "actions.weave=big_hit",
            }),
            text
        )
        assert.are.same({ "weave #1: move", "weave #2: move" }, omitted)
        assert.are.same({
            "# Movement: weave #1 reaches default: strike",
            "# Movement: weave #2 reaches default: starfire, dot",
        }, header)
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

-- Re-pin plan Task 8b (spec §3, §3a; rulings R6, R14): the ranged auto-shot clock (C7) and the time since the last
-- swing or shot in `remains` form, so the recheck parser's decreasing-clock branches (Engine/Sim/Scripts.lua)
-- forecast it.
describe("the wowsims APL translator's auto-attack clocks", function()
    local rngSince = { autoTimeSinceLast = { autoType = "RangedAuto" } }
    local mhSince = { autoTimeSinceLast = { autoType = "MainHandAuto" } }
    local function run(entries)
        return apl.translate({ priorityList = entries }, ctx({}))
    end

    it("writes a comparison on the time since the last swing or shot in remains form, either side", function()
        local text, omitted = run({
            cast(100, cmp("OpLt", rngSince, const("0.1s"))),
            cast(200, cmp("OpLt", mhSince, const("0.2s"))),
            cast(300, cmp("OpLe", mhSince, { math = { op = "OpAdd", lhs = const("0s"), rhs = const("0.3s") } })),
            cast(400, cmp("OpGt", const("0.2s"), mhSince)),
            cast(500, cmp("OpGe", rngSince, const("1s"))),
        })
        assert.are.equal(
            table.concat({
                "actions=strike,if=ranged_remains>ranged_speed-0.1",
                "actions+=/big_hit,if=mainhand_remains>mainhand_speed-0.2",
                "actions+=/roar,use_off_gcd=1,if=mainhand_remains>=mainhand_speed-(0+0.3)",
                "actions+=/dot,if=mainhand_remains>mainhand_speed-0.2",
                "actions+=/starfire,if=ranged_remains<=ranged_speed-1",
            }, "\n"),
            text
        )
        assert.are.same({}, omitted)
    end)

    it("keeps the time since as a difference inside math", function()
        local text = run({
            cast(100, cmp("OpGt", { math = { op = "OpAdd", lhs = rngSince, rhs = const("1s") } }, const("2s"))),
        })
        assert.are.equal("actions=strike,if=((ranged_speed-ranged_remains)+1)>2", text)
    end)

    local rngNext = { autoTimeToNext = { autoType = "RangedAuto" } }
    it("reads the next Auto Shot as ranged_remains and the ranged swing time as ranged_speed", function()
        local text, omitted = run({
            cast(100, cmp("OpGt", rngNext, const("0.5s"))),
            cast(200, cmp("OpGe", rngNext, { autoSwingTime = { autoType = "Ranged" } })),
        })
        assert.are.equal(
            "actions=strike,if=ranged_remains>0.5\nactions+=/big_hit,if=ranged_remains>=ranged_speed",
            text
        )
        assert.are.same({}, omitted)
    end)

    -- spec §3a: a variable the recipe's `windowVars` names reads its window: the time since is the window's elapsed
    it(
        "reads a recipe windowVars variable's time since from its window, the same comparison elsewhere on the clock",
        function()
            local rotation = {
                valueVariables = { { name = "Just shot", value = cmp("OpLt", rngSince, const("0.1s")) } },
                priorityList = {
                    cast(100, { variableRef = { name = "Just shot" } }),
                    cast(200, cmp("OpLt", rngSince, const("0.1s"))),
                },
            }
            local r = { focus = {}, windowVars = { ["Just shot"] = "weave" } }
            local text, omitted = apl.translate(rotation, ctx(r))
            assert.are.equal(
                "actions=strike,if=(window.weave.up&window.weave.elapsed<0.1)\n"
                    .. "actions+=/big_hit,if=ranged_remains>ranged_speed-0.1",
                text
            )
            assert.are.same({}, omitted)
            -- a threshold of 0 (wowsims's input delay, 0 here) is `elapsed<0`: never true, folded false
            rotation.valueVariables[1].value = cmp("OpLt", rngSince, { inputDelay = {} })
            rotation.priorityList[2] = cast(200, OR({ variableRef = { name = "Just shot" } }, ready))
            text, omitted = apl.translate(rotation, ctx(r))
            assert.are.equal("actions=big_hit,if=cooldown.big_hit.ready", text)
            assert.are.same({ "default #1: never" }, omitted)
        end
    )

    -- The converted weave build (re-pin e2842f0a78's bm_weave.siml, Task 19's request), its timing variables read by
    -- a line each: "Windup close" on the ranged clock (the time since inside math as speed - remains), "Just shot"
    -- from the weave window (the recipe's windowVars; folded false at input delay 0), and "Weave fits" on the clocks:
    -- its "Weave done" keeps its timing addends, the walk times (yards over the run speed) drop alone (R17 refined).
    -- No walk term reaches the text; the build's waits and waitUntils give no line -- (decision 9).
    it("translates bm_weave's timing variables on the clocks and the window, no walk term, no wait line", function()
        local json = require("dkjson")
        local f = assert(io.open("tests/Forever/wowsims/hunter_beast_mastery.build.json", "rb"))
        local player = json.decode(f:read("*a")).player
        f:close()
        local r = dofile("tools/wowsims/specs/hunter_beast_mastery.lua")
        local set = require("Forever.helpers.engine").abilitySet(r.class)
        local rotation = { valueVariables = player.rotation.valueVariables, priorityList = {} }
        for _, name in ipairs({ "Windup close", "Just shot", "Weave fits" }) do
            rotation.priorityList[#rotation.priorityList + 1] = {
                action = {
                    castSpell = { spellId = { spellId = 14287 } },
                    condition = { variableRef = { name = name } },
                },
            }
        end
        -- the recipe's open line wants its raptor_strike; its leveling line (BM's Arcane Shot below Summon Hawk, Task 19)
        -- is not one of the three timing lines under test, nor is its `guard` (a move entry of the full APL; CN12 refuses
        -- a guard key that names nothing)
        local lines = setmetatable({ extra = {}, leveling = {}, guard = {} }, { __index = r })
        local text = apl.translate(rotation, apl.context(set, lines, nil, player))
        assert.are.equal(
            table.concat({
                "actions=arcane_shot,if=(ranged_remains<=0|ranged_remains>=(ranged_speed-(ranged_speed-ranged_remains)))",
                -- 0.7 re-pin (e5a9cd2a2d, acc6bcb5f8's weave): "Weave fits" no longer carries the walk and swing addends; the
                -- variable keeps its ranged clock term alone
                "actions+=/arcane_shot,if=ranged_remains>ranged_speed-0",
            }, "\n"),
            text
        )
        -- "Just shot" at input delay 0 is `elapsed<0`, never true: folded false, so its line is omitted (never)
        local full, omitted = apl.translate(player.rotation, apl.context(set, r, nil, player))
        assert.is_falsy(full:find("wait", 1, true), full)
        local waits = 0
        for _, o in ipairs(omitted) do
            waits = waits + ((o:find(": wait$") or o:find(": waitUntil$")) and 1 or 0)
        end
        assert.is_true(waits > 0)
    end)
end)

-- CN2 (.siml recipes, L141): upstream moved the Paladin APLs to .apl.siml (2fe0846044). export.lua turns a .siml file
-- into protojson with the CLI's `siml parse -json` (its `siml` step; a recipe `apl` path is CN1's); the translator then
-- reads the request's rotation as it reads a JSON APL. The fixtures are upstream/master 4b0030a44b's
-- ui/specs/paladin/{retribution,protection}/apls/default.apl.siml through a CLI built at that commit (the pin's CLI
-- cannot parse them). SIML writes no `rank` fields; the translator ignores ranks (rule 5), so the pack is the same.
describe("the wowsims APL translator on a .siml-parsed APL", function()
    local json = require("dkjson")
    local function slurp(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end
    for _, spec in ipairs({ "paladin_retribution", "paladin_protection" }) do
        it(spec .. "'s upstream .apl.siml translates as the checked-in request's JSON APL", function()
            local r = dofile("tools/wowsims/specs/" .. spec .. ".lua")
            local set = require("Forever.helpers.engine").abilitySet(r.class)
            local log = slurp("tests/Forever/wowsims/" .. spec .. ".log")
            local player = json.decode(slurp("tests/Forever/wowsims/" .. spec .. ".json")).raid.parties[1].players[1]
            local want = { apl.translate(player.rotation, apl.context(set, r, log, player)) }
            local siml = json.decode(slurp("tests/Forever/fixtures/wowsims_siml_" .. spec .. ".apl.json"))
            assert.are.equal("TypeAPL", siml.type)
            local got = { apl.translate(siml, apl.context(set, r, log, player)) }
            assert.are.same(want, got)
        end)
    end
end)

-- CN3 (L124): upstream 60b9eec562 gates the Warlocks' curse group on `warlockIsAssignedCurse` (sim/warlock/apl_values.go:
-- the option equals the value's curseType). That is rule 16's `is` value: a recipe whose `select` names it as `is`
-- translates the group; one that does not (every Warlock recipe at the pin) omits the line, leaving the group empty.
-- The group below is upstream/master 4b0030a44b's demo_fire_brand.build.json "Single/Multi Target Curse Logic" #1.
describe("the wowsims APL translator on the Warlocks' assigned-curse check", function()
    it("translates warlockIsAssignedCurse once the recipe's select names it `is`", function()
        local rotation = {
            priorityList = { { action = { groupReference = { groupName = "Single/Multi Target Curse Logic" } } } },
            groups = {
                {
                    name = "Single/Multi Target Curse Logic",
                    actions = {
                        {
                            action = {
                                castWarlockAssignedCurse = {},
                                condition = {
                                    ["and"] = {
                                        vals = {
                                            { ["not"] = { val = { warlockAssignedCurseIsActive = {} } } },
                                            {
                                                ["not"] = {
                                                    val = { warlockIsAssignedCurse = { curseType = "NoCurse" } },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        }
        local r = dofile("tools/wowsims/specs/warlock_demonology.lua")
        local set = require("Forever.helpers.engine").abilitySet(r.class)
        local player = { warlock = { options = { classOptions = {} } } } -- the zero value, Elements
        r.select.castWarlockAssignedCurse.is = nil -- the shipped recipes name it now (CN3, the 0.7 re-pin): drop it for the "before"
        local before, omitted = apl.translate(rotation, apl.context(set, r, nil, player))
        assert.are.equal("", before)
        assert.are.same({
            "single_multi_target_curse_logic #1: warlockIsAssignedCurse",
            "default: empty group single_multi_target_curse_logic",
        }, omitted)
        r.select.castWarlockAssignedCurse.is = "warlockIsAssignedCurse"
        local text, none = apl.translate(rotation, apl.context(set, r, nil, player))
        assert.are.same({}, none)
        local up = "(settings.assigned_curse='elements'&debuff.curse_of_the_elements.up)"
            .. "|(action.curse_of_recklessness.known&settings.assigned_curse='recklessness'&debuff.curse_of_recklessness.up)"
            .. "|(action.curse_of_weakness.known&settings.assigned_curse='weakness'&debuff.curse_of_weakness.up)"
        assert.are.equal(
            "actions=call_action_list,name=single_multi_target_curse_logic\n"
                .. "actions.single_multi_target_curse_logic=curse_of_the_elements,focus=2,"
                .. "if=settings.assigned_curse='elements'&(!("
                .. up
                .. ")&!(settings.assigned_curse='nocurse'))",
            (text:gsub("\nactions%.single_multi_target_curse_logic%+=/.*", ""))
        )
    end)
end)

-- CN12: a recipe `guard`, `requires` or `windowVars` key that names nothing raises, as `condition` does. Upstream
-- renamed the hunters' weave entries ("weave #6" is gone; "Just shot" became 'shot_since_swing' in
-- weave_common.apl.siml at 4b0030a44b), so a re-export would otherwise drop the guard and the window read silently.
describe("the wowsims APL translator's recipe keys", function()
    local rotation = { priorityList = { cast(100) } }
    it("refuses a guard key no line or move entry has", function()
        assert.has_error(function()
            apl.translate(rotation, ctx({ guard = { ["weave #6"] = "window.weave.up" } }))
        end, "guard: no weave #6 line")
        assert.has_error(function()
            apl.translate(rotation, ctx({ guard = { strike = "buff.fury.up", nope = "x" } }))
        end, "guard: no nope line")
    end)
    it("refuses a requires key no line has", function()
        assert.has_error(function()
            apl.translate(rotation, ctx({ requires = { nope = "furious" } }))
        end, "requires: no nope line")
    end)
    -- fix round 1 (review I2, probes P3-P5): the error means only "the APL has no entry of that name"; an entry that
    -- exists but is omitted (folds false, hidden, an unsupported node) matches its key
    it("matches a guard or requires key whose entry exists but is omitted", function()
        local never = AND(ready, const("false"))
        for _, e in ipairs({
            cast(200, never), -- P3: its condition folds false
            { hide = true, action = { castSpell = { spellId = { spellId = 200 } } } }, -- P4: hidden
            cast(200, { brandNewValue = {} }), -- P5: a node the translator does not know
        }) do
            for _, r in ipairs({ { guard = { big_hit = "buff.fury.up" } }, { requires = { big_hit = "furious" } } }) do
                local text = apl.translate({ priorityList = { cast(100), e } }, ctx(r))
                assert.are.equal("actions=strike", text)
            end
        end
    end)

    -- review I2: rule 16's select lines take a guard on a candidate, as every other cast line does
    it("appends a guard to a select candidate's line", function()
        local r = {
            guard = { dot = "buff.fury.up" },
            select = {
                castAssigned = {
                    setting = "pick",
                    option = "pickOption",
                    zero = "Elements",
                    candidates = { Elements = "dot", NoCurse = false },
                },
            },
        }
        local text = apl.translate(
            { priorityList = { { action = { castAssigned = {} } } } },
            ctx(r, { warlock = { options = { classOptions = {} } } })
        )
        assert.are.equal("actions=dot,if=settings.pick='elements'&buff.fury.up", text)
    end)

    -- review M1 (probe P1): a recipe condition on an action cast only inside a group
    it("finds a condition's cast line inside a group", function()
        local text = apl.translate({
            priorityList = { { action = { groupReference = { groupName = "G" } } } },
            groups = { { name = "G", actions = { cast(200) } } },
        }, ctx({ condition = { big_hit = "rage.lo>40" } }))
        assert.are.equal("actions=call_action_list,name=g\nactions.g=big_hit,if=rage.lo>40", text)
    end)

    it("refuses a windowVars variable nothing reads", function()
        assert.has_error(function()
            apl.translate(rotation, ctx({ windowVars = { ["Just shot"] = "weave" } }))
        end, "windowVars: no Just shot read")
    end)
end)

describe("the wowsims APL translator's second-lane reads (CN14, CN16, the travel-time fold)", function()
    local function spell(k, id)
        return { [k] = { spellId = { spellId = id } } }
    end
    local function one(cond, player, encounter)
        return apl.translate({ priorityList = { cast(100, cond) } }, ctx({}, player, encounter))
    end
    local inRange = spell("spellInRange", 100)
    local FACING = "frontOfTarget is the request's in-front setting (behind the target); the client gives no facing."

    -- CN16 (rogue-1.md): Ghostly Strike's `not frontOfTarget | Dirty Deeds Known`
    it("frontOfTarget folds to the request's inFrontOfTarget (absent: false, behind), noted", function()
        local text, omitted, _, header = one(AND(NOT({ frontOfTarget = {} }), inRange))
        assert.are.equal("actions=strike,if=action.strike.in_range", text)
        assert.are.same({}, omitted)
        assert.are.same({ "# Deviation: default #1: " .. FACING }, header)
        local text2, omitted2 = one(AND(NOT({ frontOfTarget = {} }), inRange), { inFrontOfTarget = true })
        assert.are.equal("", text2)
        assert.are.same({
            "default #1: never: frontOfTarget is the request's in-front setting (in front of the target);"
                .. " the client gives no facing.",
        }, omitted2)
        local _, _, _, header3 = one(AND({ frontOfTarget = {} }, inRange), { inFrontOfTarget = true })
        assert.are.same({
            "# Deviation: default #1: frontOfTarget is the request's in-front setting (in front of the target);"
                .. " the client gives no facing.",
        }, header3)
    end)

    -- CN16 (warrior-2.md): Fury #15's Spearing Strike weave for Dragonkin or Giants
    it("targetIsMobType folds against the request's target mob type, noted; no encounter: unknown", function()
        local enc = { targets = { { mobType = "MobTypeGiant" } } }
        local dragon = { targetIsMobType = { mobType = "MobTypeDragonkin" } }
        local giant = { targetIsMobType = { mobType = "MobTypeGiant" } }
        local text, omitted, _, header = one(AND(OR(dragon, giant), inRange), nil, enc)
        assert.are.equal("actions=strike,if=action.strike.in_range", text)
        assert.are.same({}, omitted)
        assert.are.same({
            "# Deviation: default #1: targetIsMobType is the request's target type (giant); the client's creature"
                .. " type is not read.",
        }, header)
        local text2, omitted2 = one(AND(OR(dragon, giant), inRange), nil, {
            targets = { { mobType = "MobTypeMechanical" } },
        })
        assert.are.equal("", text2)
        assert.are.same({
            "default #1: never: targetIsMobType is the request's target type (mechanical); the client's"
                .. " creature type is not read.",
        }, omitted2)
        local text3, omitted3 = one(AND(dragon, inRange)) -- protojson's zero: MobTypeUnknown
        assert.are.equal("", text3)
        assert.are.same({ "default #1: never" }, omitted3)
    end)

    -- CN14 (lane-warlock-report.md): Affliction's Siphon Life `not spellIsChanneling(Wrack)`
    it("spellIsChanneling is the ability's channeling for a channeled spell, false otherwise, guarded", function()
        assert.are.equal(
            "actions=strike,if=(!action.drain.known|!action.drain.channeling)",
            (one(NOT(spell("spellIsChanneling", 700))))
        )
        local text = apl.translate({ priorityList = { cast(700, spell("spellIsChanneling", 700)) } }, ctx({}))
        assert.are.equal("actions=drain,if=action.drain.channeling", text)
        assert.are.equal("actions=strike", (one(NOT(spell("spellIsChanneling", 500))))) -- a hard cast: never
        assert.are.equal("actions=strike", (one(NOT(spell("spellIsChanneling", 100))))) -- an instant: never
        local text2, omitted = one(spell("spellIsChanneling", 999))
        assert.are.equal("actions=strike", text2)
        assert.are.same({ "default #1: dropped the unresolved spell 999 (its branch only)" }, omitted)
    end)

    -- the travel fold puts Shadow Bolt in Affliction's precombat: its per-occurrence tiers are the role lines'
    it("a recipe's per-occurrence focus tiers count the rotation's lines, not a pre-pull one", function()
        local pre = cast(200)
        pre.doAtValue = const("-1s")
        local text = apl.translate(
            { prepullActions = { pre }, priorityList = { cast(200), cast(100), cast(200) } },
            ctx({ focus = { big_hit = { 1, 2 } } })
        )
        assert.are.equal(
            "actions.precombat=big_hit\nactions=big_hit,focus=1\nactions+=/strike\nactions+=/big_hit,focus=2",
            text
        )
    end)

    -- Enhancement's AoE line reads Stormstrike's debuff (17364), which the Shaman kit does not register: the ID resolves
    -- to the ability's key, and `debuff.stormstrike.up` was an unknown aura (shaman_spec's registered-names check)
    it("reads an aura through an ability's key only where the kit registers that aura; else rule 12's nil", function()
        local function on(id)
            return { auraIsActive = { auraId = { spellId = id }, sourceUnit = { type = "CurrentTarget" } } }
        end
        local text, omitted = one(AND(on(200), inRange))
        assert.are.equal("actions=strike,if=action.strike.in_range", text)
        assert.are.same({ "default #1: dropped the unresolved aura 200 (its branch only)" }, omitted)
        assert.are.equal("actions=strike,if=(!action.dot.known|debuff.dot.up)", (one(on(400)))) -- dot: both
    end)

    -- translator-5.md: Fury #29's Bloodrage (MeleeAuto) and Enhancement's AoE Chain Lightning (AnyAuto)
    it(
        "autoTimeToNext MeleeAuto / AnyAuto is the min of the kit's hand clocks (AnyAuto: and its ranged one)",
        function()
            local function auto(t)
                return cmp("OpGt", { autoTimeToNext = { autoType = t } }, const("0.5s"))
            end
            local c = ctx({})
            c.set.stateExprs = { mainhand_remains = true, offhand_remains = true }
            local function at(t)
                return (apl.translate({ priorityList = { cast(100, auto(t)) } }, c))
            end
            assert.are.equal("actions=strike,if=min(mainhand_remains,offhand_remains)>0.5", at("MeleeAuto"))
            assert.are.equal("actions=strike,if=min(mainhand_remains,offhand_remains)>0.5", at("AnyAuto")) -- no ranged clock
            c.set.stateExprs.ranged_remains = true
            assert.are.equal(
                "actions=strike,if=min(mainhand_remains,offhand_remains,ranged_remains)>0.5",
                at("AnyAuto")
            )
            c.set.stateExprs = { mainhand_remains = true } -- a kit with no off-hand clock: unsupported, as before
            local text, omitted = apl.translate({ priorityList = { cast(100, auto("MeleeAuto")) } }, c)
            assert.are.equal("", text)
            assert.are.same({ "default #1: autoTimeToNext MeleeAuto: the kit has no offhand_remains" }, omitted)
        end
    )

    -- translator-2.md: the Warlocks' `-0.9 * (cast + travel)` pre-pull opener
    it("a doAtValue folds a spell's travel time as the request's distance over the kit's velocity", function()
        local function at(id, v)
            local e = cast(id)
            e.doAtValue = v
            return e
        end
        local opener = {
            math = {
                op = "OpMul",
                lhs = {
                    math = { op = "OpAdd", lhs = spell("spellCastTime", 800), rhs = spell("spellTravelTime", 800) },
                },
                rhs = const("-0.9"),
            },
        }
        local rot = {
            prepullActions = {
                at(200, const("-2.5s")), -- between: -(2.5 + 20/20) * 0.9 = -3.15 at 20 yd, -2.25 at 0 yd
                at(800, opener),
                at(100, { math = { op = "OpMul", lhs = spell("spellTravelTime", 100), rhs = const("-1") } }),
            },
        }
        local text, omitted, _, header = apl.translate(rot, ctx({}, { distanceFromTarget = 20 }))
        assert.are.equal(
            table.concat({
                "actions.precombat=bolt",
                "actions.precombat+=/big_hit",
                "actions.precombat+=/strike", -- no velocity: wowsims's 0 s travel, at the pull
            }, "\n"),
            text
        )
        assert.are.same({}, omitted)
        assert.are.same({
            "# Deviation: precombat #2: the pre-pull time uses the kit's base cast time; wowsims uses the hasted cast.",
        }, header)
        local c = ctx({}, { distanceFromTarget = 20 })
        c.set.abilities.bolt.flightTime = 0.5 -- a kit flight time wins over distance / velocity
        assert.are.equal( -- -(2.5 + 0.5) * 0.9 = -2.7: still before big_hit's -2.5
            "actions.precombat=bolt\nactions.precombat+=/big_hit\nactions.precombat+=/strike",
            (apl.translate(rot, c))
        )
        c.set.abilities.bolt.flightTime = 0 -- -(2.5 + 0) * 0.9 = -2.25: after big_hit (distance / velocity unused)
        assert.are.equal(
            "actions.precombat=big_hit\nactions.precombat+=/bolt\nactions.precombat+=/strike",
            (apl.translate(rot, c))
        )
        c.set.abilities.bolt.flightTime = nil
        assert.are.equal( -- protojson omits a 0 distance: the travel time is 0
            "actions.precombat=big_hit\nactions.precombat+=/bolt\nactions.precombat+=/strike",
            (apl.translate(rot, ctx({})))
        )
    end)
end)
