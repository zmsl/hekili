-- tests/Game/State/meter_spec.lua (providers spec §2.2): the damage-meter Outcomes provider. The event's (type,
-- sessionID) as group times; the 15 ms rule, the mute, "no group behind the row", taken groups, the out-of-combat audit.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the damage-meter Outcomes provider", function()
    local api, ctl, ns, VS, I, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        local d = fs.def(fs.new(9))
        d.providers = { outcomes = "meter" }
        I.Build(d, 1)
        VS.Start(api)
        ctl.combat = true
        ctl.Fire("PLAYER_REGEN_DISABLED")
    end)
    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    local function group(t)
        ctl.now = t
        ctl.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 200)
        ctl.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 0) -- the duplicate set: ignored
    end

    it("is UNDECIDED before the first group of the fight (not live)", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Tick(10.02)
        assert.are.equal(3, I.Tickets.told[I.Tickets.lastSwing[1]])
    end)

    it("HIT for a group within 15 ms of the swing, AVOID without", function()
        group(5)
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        group(10.008)
        ctl.Tick(10.02)
        assert.are.equal(1, I.Tickets.told[I.Tickets.lastSwing[1]])
        ctl.now = 12.6
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Tick(12.62)
        assert.are.equal(2, I.Tickets.told[I.Tickets.lastSwing[1]])
        local f = I.Log.fight
        assert.are.same({ 1, 1, 0 }, { f.swingsTick, f.swingsAvoid, f.swingsUnknown })
    end)

    it("mutes after three more told avoids than avoid rows", function()
        group(5)
        for n = 0, 3 do
            ctl.now = 10 + 2.6 * n
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(ctl.now + 0.02)
        end
        ctl.now = 21
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Tick(21.02)
        assert.are.equal(3, I.Tickets.told[I.Tickets.lastSwing[1]])
        assert.are.equal(1, I.outcomes.muted)
    end)

    it("RowOwner: a spell row with no group in its frame is FOREIGN; with one, UNDECIDED in a group", function()
        local P = I.outcomes
        group(5)
        assert.are.equal(I.FOREIGN, P.RowOwner(6, 1, 32, 50, "WOUND", 6.02))
        assert.are.equal(I.OURS, P.RowOwner(5.002, 1, 32, 50, "WOUND", 5.02))
        ctl.inGroup = true -- IsInGroup, read at PLAYER_REGEN_DISABLED
        ctl.Fire("PLAYER_REGEN_DISABLED")
        group(7.004)
        assert.are.equal(I.UNDECIDED, P.RowOwner(7, 1, 32, 50, "WOUND", 7.02))
        assert.are.equal(I.UNDECIDED, P.RowOwner(7, 1, 1, 0, "DODGE", 7.02))
        assert.are.equal(I.FOREIGN, P.RowOwner(7.1, 1, 32, 50, "WOUND", 7.12))
    end)

    it("RowOwner: a white row with a group in the 2 s before it is not FOREIGN", function()
        group(5)
        assert.are.equal(I.OURS, I.outcomes.RowOwner(6.2, 1, 1, 40, "WOUND", 6.22))
        assert.are.equal(I.FOREIGN, I.outcomes.RowOwner(7.2, 1, 1, 40, "WOUND", 7.22))
    end)

    it("EnemyHitAt: a taken group 0.3-0.6 s before a white row on us, once", function()
        group(5)
        ctl.now = 9.6
        ctl.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, 200)
        assert.are.equal(9.6, I.outcomes.EnemyHitAt(10))
        assert.is_nil(I.outcomes.EnemyHitAt(10.01))
    end)

    it("Audit: out of combat, plain, the local player's totals; nil while secret", function()
        ctl.meter.done[1], ctl.meter.taken[1] = 923, 51
        fs.fold(ns, 29) -- in combat: no read (the getters are secret and allocate)
        assert.is_nil(I.outcomes.Audit())
        ctl.now = 30
        ctl.combat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        fs.fold(ns, 30.1)
        local a = I.outcomes.Audit()
        assert.are.same({ true, 923, 51 }, { a.valid, a.done, a.taken })
    end)

    it("Audit: a secret field drops the read", function()
        ctl.meter.done[1] = 923
        ctl.now = 30
        ctl.Fire("PLAYER_REGEN_ENABLED") -- the client still answers secret (ctl.combat stays true)
        I.inCombat = false
        fs.fold(ns, 30.1)
        assert.is_nil(I.outcomes.Audit())
    end)

    it("re-activation is idempotent (VS.Start after a build)", function()
        group(5)
        VS.Start(api)
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        group(10.008)
        ctl.Tick(10.02)
        assert.are.equal(1, I.Tickets.told[I.Tickets.lastSwing[1]])
        assert.is_truthy(api.frame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED)
    end)

    it("dormant while the default provider is active", function()
        assert.is_truthy(api.frame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED)
        local d = fs.def(fs.new(9))
        I.Build(d, 1)
        assert.is_falsy(api.frame.events.DAMAGE_METER_COMBAT_SESSION_UPDATED)
    end)

    it("the audit line: two Snapshot lines, each under 255 characters", function()
        local text = VS.Snapshot()
        local a = text:match("(providers outcomes=meter[^\n]*)")
        local b = text:match("(providers paid=[^\n]*)")
        assert.is_truthy(a, text)
        assert.is_truthy(b, text)
        assert.is_true(#a < 255 and #b < 255)
    end)
end)
