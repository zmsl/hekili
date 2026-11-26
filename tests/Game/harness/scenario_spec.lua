-- tests/Game/harness/scenario_spec.lua (refactor plan lane 2): the scenario builder's verbs fire what the hand-built
-- specs fire, at their own times. The ones a ported spec already proves (swings, casts, rows, power, ticks and drains:
-- finisher_world, now_spec's fix A sequences, the pairing matrix) are checked here only for order and facts; the rest
-- (a failed cast, a taken row, a usable answer, a band) each once.
local fake = require("Game.State.helpers.fake_api")
local load = require("Game.State.helpers.load")
local scenario = require("Game.harness.scenario")

describe("the scenario builder #self", function()
    local api, ctl, heard, B

    before_each(function()
        api, ctl = fake.new()
        ctl.now = 1
        heard = {}
        local f = api.CreateFrame("Frame") -- the client's first frame: ctl.Fire's target
        for _, e in ipairs({
            "UNIT_COMBAT",
            "PLAYER_SWING",
            "UNIT_SPELLCAST_SENT",
            "UNIT_SPELLCAST_SUCCEEDED",
            "UNIT_SPELLCAST_FAILED",
            "UNIT_POWER_FREQUENT",
        }) do
            f:RegisterEvent(e)
        end
        f:SetScript("OnEvent", function(_, e, ...)
            heard[#heard + 1] = { ctl.now, e, ... }
        end)
        B = scenario.new({ ctl = ctl, ns = {} }, { plain = true, dt = false })
    end)

    it("fires in time order, ties in the order given; background events are no facts", function()
        B:row(5, "PARRY", { name = "late" }):swing(3, { act = "DODGE", lag = 0.5 }):row(3.5, "MISS"):run()
        assert.are.same({
            { 3, "PLAYER_SWING", 1.0, 0 },
            { 3.5, "UNIT_COMBAT", "target", "DODGE", "", 0, 1 },
            { 3.5, "UNIT_COMBAT", "target", "MISS", "", 0, 1 },
            { 5, "UNIT_COMBAT", "target", "PARRY", "", 0, 1 },
        }, heard)
        assert.are.same({ "swing", "swing row DODGE", "row MISS", "late" }, {
            B.facts[1].what,
            B.facts[2].what,
            B.facts[3].what,
            B.facts[4].what,
        })
        B:swing(6):run() -- a white wound: background
        assert.are.equal(4, #B.facts)
    end)

    it("a failed cast: SENT before it, UNIT_SPELLCAST_FAILED at its time, no row", function()
        B:cast(5, 1001, { fail = true, name = "jab" }):run()
        assert.are.same({
            { 4.92, "UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-jab-5", 1001 },
            { 5, "UNIT_SPELLCAST_FAILED", "player", "Cast-jab-5", 1001 },
        }, heard)
    end)

    it("a taken row is the player's; amounts are secret unless plain", function()
        B:taken(2, "WOUND", { amount = 300 }):run()
        scenario.new({ ctl = ctl, ns = {} }, { dt = false }):taken(3, "WOUND", { amount = 300 }):run()
        assert.are.same({ 2, "UNIT_COMBAT", "player", "WOUND", "", 300, 1 }, heard[1])
        assert.are.equal(fake.SECRET, heard[2][6])
    end)

    it("a usable answer holds from its time; the power read fires its event with the value", function()
        B:usable(5, 1001, true):power(5, 4, 3)
        B:run(4)
        assert.are.same({ false, false }, { api.C_Spell.IsSpellUsable(1001) })
        B:run(6)
        assert.are.same({ true, false }, { api.C_Spell.IsSpellUsable(1001) })
        assert.are.same({ { 5, "UNIT_POWER_FREQUENT", "player", "COMBO_POINTS" } }, heard)
        assert.are.equal(3, ctl.power[4])
    end)

    it("with a frame loop, steps a frame at a time and calls the frame step after each frame's events", function()
        local steps = {}
        local L = scenario.new({ ctl = ctl, ns = {} }, {
            dt = 0.25,
            frame = function(_, t)
                steps[#steps + 1] = { t, #heard }
            end,
        })
        L:row(1.3, "MISS"):run(1.75)
        assert.are.same({ { 1.25, 0 }, { 1.5, 1 }, { 1.75, 1 } }, steps)
        assert.are.equal(1.3, heard[1][1]) -- at its own time, not the frame's
    end)

    it("a band poll reaches the belief as resources_spec's band() does: the band's columns", function()
        local ns = load.module()
        local VS, I = ns.VirtualState, ns.VirtualStateInternal
        I.Build({
            school = load.school(),
            fsr = load.constant("FSR"),
            gcdSpell = load.constant("GCD_SPELL"),
            oracleMin = load.constant("ORACLE_MIN"),
            abilities = {},
            abilityIds = {},
            abilitySlot = {},
            resources = { { key = "mana", type = 0, token = "MANA", max = 1000, rest = true, regen = 10 } },
            reactions = {},
            auras = {},
            auraIds = {},
            talents = {},
            units = { "player", "target" },
        }, 1)
        I.api = api
        I.Fold(10)
        I.Settle(10)
        scenario.new({ ctl = ctl, ns = ns }, { dt = false }):band(10, 1, 450, 460):run()
        I.Fold(10)
        assert.are.equal(1, I.bandUsed[1])
        assert.are.same({ 450, 460 }, { I.bandUsedLo[1], I.bandUsedHi[1] })
        assert.are.equal(450, VS.Power(0, 10).lo)
    end)
end)
