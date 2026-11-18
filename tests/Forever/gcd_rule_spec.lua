-- tests/Forever/gcd_rule_spec.lua: the simulation's one GCD-length rule (dry-gcd): gcd.execute and gcd.max share it,
-- its 1.0 s floor is wowsims's (sim/core/constants.go GCDMin, applied after the GCD multiplier and the haste), the
-- class's own GCD kind is pack data (Hekili:NewClass `gcd`), and it gives what the belief's I.GcdLen gives.
local headless = require("Game.harness.headless")
local dw = require("Forever.helpers.druid_loop_world")
local rw = require("Forever.helpers.rogue_world")

local function near(want, got, what)
    assert(math.abs(want - got) < 1e-9, ("%s: want %.6f, got %.6f"):format(what or "", want, got))
end

-- A level 60 instance of content `C` whose out-of-combat spell haste read is `haste` percent.
local function load(C, haste)
    local H = headless.new({ character = C.character(), pack = C.PACK })
    assert.are.same({}, H.loadErrors)
    H.ctl.spellHaste = haste or 0
    H.Fire("UNIT_SPELL_HASTE", "player")
    assert.is_true(headless.cycle(H, H.ctl.now + 0.1))
    H.Hekili.State.reset("Primary", true)
    return H, H.Hekili.State
end

describe("the simulation's GCD rule (dry-gcd)", function()
    it("floors a spell-kind GCD at 1.0 s, never 0.75 (wowsims GCDMin), on both keys", function()
        local _, S = load(dw.Balance, 100) -- 1.5 / 2 = 0.75 before the floor
        S.this_action = "wrath"
        near(0.5, S.haste, "haste")
        near(1.0, S.gcd.execute, "execute")
        near(1.0, S.gcd.max, "max")
    end)

    it(
        "floors after both Nature's Grace modifiers and the haste (30%: 1.5 / 1.3 / 1.1 x 0.9 = 0.944 -> 1.0)",
        function()
            local _, S = load(dw.Balance, 30)
            S.this_action = "wrath"
            near(1.5 / 1.3, S.gcd.execute, "no modifier")
            S.applyBuff("natures_grace")
            near(1.0, S.gcd.execute, "both modifiers")
            S.this_action = "bear_form" -- off the mask: 1.5 / 1.3 / 1.1 = 1.049, above the floor
            near(1.5 / 1.3 / 1.1, S.gcd.execute, "the cast speed alone")
        end
    )

    it("gives what the belief's I.GcdLen gives, nothing learned, by haste, modifier and kind", function()
        for _, haste in ipairs({ 0, 20, 30, 50, 100 }) do
            local H, S = load(dw.Balance, haste)
            local I = H.ns.VirtualStateInternal
            local A, t = I.ab, H.ctl.now
            local function index(key)
                for a = 1, A.n do
                    if A.key[a] == key then
                        return a
                    end
                end
                error("no belief ability " .. key)
            end
            local j = assert(I.auras.byKey.natures_grace)
            for _, grace in ipairs({ false, true }) do
                if grace then
                    S.applyBuff("natures_grace")
                    I.AuraModel(1, j, t - 1, t + 10, 1, t - 1, 0)
                end
                for _, key in ipairs({ "wrath", "bear_form", "shred" }) do -- mask, off the mask, the totem kind
                    S.this_action = key
                    near(
                        I.GcdLen(index(key), t),
                        S.gcd.execute,
                        ("%s haste %d grace %s"):format(key, haste, tostring(grace))
                    )
                end
            end
        end
    end)

    it("answers gcd.max by the same rule as gcd.execute: the ability's kind, its modifiers, no class clause", function()
        local _, S = load(dw.Balance, 20)
        for _, key in ipairs({ "wrath", "shred", "bear_form" }) do
            S.this_action = key
            near(S.gcd.execute, S.gcd.max, key)
        end
        S.this_action = "wait" -- no ability's kind: the class's (Balance in caster form: the spell kind)
        near(1.5 / 1.2, S.gcd.max, "wait")
        near(1.5 / 1.2, S.gcd.execute, "wait")
        S.applyBuff("cat_form") -- the Druid's own kind in Cat Form (pack data): the totem kind
        near(1, S.gcd.max, "wait in Cat Form")
        near(1, S.gcd.execute, "wait in Cat Form")
        S.this_action = "natures_swiftness" -- gcd.max of an off-GCD ability: the class kind, never 0
        near(0, S.gcd.execute, "off execute")
        near(1, S.gcd.max, "off max in Cat Form")
    end)

    it("prices a Rogue's spell-kind press at 1.5 s x haste and its wait at 1 s, Adrenaline Rush or not", function()
        local _, S = load(rw.Combat, 20)
        S.this_action = "distract" -- the row's 1.5 s GCD (wowsims pin spells_auto_gen.go, 1725)
        near(1.5 / 1.2, S.gcd.execute, "distract")
        S.this_action = "wait"
        near(1, S.gcd.execute, "wait")
        near(1, S.gcd.max, "wait max")
        S.applyBuff("adrenaline_rush") -- energy regen only at the pin (13750: one A_MOD_POWER_REGEN_PERCENT effect)
        near(1, S.gcd.execute, "wait under Adrenaline Rush")
        S.this_action = "sinister_strike"
        near(1, S.gcd.execute, "sinister strike under Adrenaline Rush")
    end)

    it("reads a bare `gcd` as gcd.max in the compiler, as the SimC importer does", function()
        local H = load(dw.Balance, 0)
        assert.are.equal("gcd.max<2", H.Hekili.Scripts.SimToLua("gcd<2"))
        local out = H.Hekili:ParseActionList("actions+=/wrath,if=gcd<2\n")
        assert.are.equal("gcd.max<2", (out[1].criteria:gsub(" ", "")))
    end)

    -- D1's consequence: at 60% spell haste (1.5 / 1.6 = 0.9375 before the floor) the queue placed each instant's
    -- successor 0.0625 s early per GCD; wowsims's GCD there is 1.0 s.
    it("places the queue's later slots one floored GCD apart at 60% spell haste", function()
        local H = headless.new({ character = dw.Balance.character(), pack = dw.Balance.PACK })
        assert.are.same({}, H.loadErrors)
        H.ctl.spellHaste = 60
        H.Fire("UNIT_SPELL_HASTE", "player")
        local out = H.Hekili.Engine.Output.Primary
        assert.is_true(H.Hekili.Engine.Subscribe("Primary", function() end))
        H.ctl.inRange.target, H.ctl.level.target = true, 60
        H.Fire("PLAYER_TARGET_CHANGED")
        H.ctl.now = H.ctl.now + 1
        H.Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(headless.cycle(H, H.ctl.now + 0.1))
        local r = out.recs
        assert.are.same({ "moonfire", "insect_swarm", "wrath" }, { r[1].actionName, r[2].actionName, r[3].actionName })
        near(1.0, r[2].time - r[1].time, "slot 2")
        near(2.0, r[3].time - r[1].time, "slot 3")
        assert.are.same({}, H.errors)
    end)
end)
