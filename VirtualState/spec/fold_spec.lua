-- VirtualState/spec/fold_spec.lua: the fold, the clock and the sources' plumbing (spec §4.3, §4.4, §8).
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("the fold", function()
    local ns, VS, I, S, api, ctl

    before_each(function()
        api, ctl = fake.new()
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S = I.Sources
        I.Build(fs.def(fs.new()), 100)
        VS.Start(api)
        ctl.Tick(100) -- the start's reads into the log, then an empty log
        I.ObsLog.Clear(I.log)
    end)

    it("starts the clock at the first observation and never moves it backward", function()
        I.started = false
        S.Direct(VS.Obs.Moving, 105, 0, 1)
        I.Fold(110)
        assert.are.equal(105, I.clock)
        I.Settle(110)
        assert.are.equal(110, I.clock)
        assert.is_true(VS.Moving())
        S.Direct(VS.Obs.Moving, 104, 0, 0) -- late: applied at the clock, with its lag
        local lagSeen
        I.On(VS.Obs.Moving, function(o, t, lag)
            lagSeen = { t, lag }
        end)
        I.Fold(111)
        assert.are.same({ 110, 6 }, lagSeen)
        assert.are.equal(0, I.Dt(109))
    end)

    it("stages event observations until the next frame and puts aura reads first", function()
        ctl.Fire("PLAYER_STARTED_MOVING")
        assert.are.equal(0, I.log.n)
        S.Direct(VS.Obs.Read, 100, 1, 0, I.ReadOf.Aura)
        ctl.Tick(100.1)
        assert.are.equal(2, I.log.n)
        assert.are.equal(VS.Obs.Read, I.ObsLog.At(I.log, 1).kind)
        assert.are.equal(VS.Obs.Moving, I.ObsLog.At(I.log, 2).kind)
    end)

    it("drops staged observations past the stage cap and counts them", function()
        for _ = 1, S.STAGE + 3 - S.stN do
            S.Stage(VS.Obs.Moving, 100, 0, 1)
        end
        assert.are.equal(3, S.dropped)
    end)

    it("runs the polls in order and refuses a duplicate order", function()
        local seen = {}
        S.Poll(9.5, function()
            seen[#seen + 1] = 9.5
        end)
        S.Poll(0.5, function()
            seen[#seen + 1] = 0.5
        end)
        S.RunPolls(100)
        assert.are.same({ 0.5, 9.5 }, seen)
        assert.has_error(function()
            S.Poll(1.5, function() end) -- the player's health poll
        end)
    end)

    it("passes every event argument through Plain: a secret argument arrives as nil", function()
        local got = "unset"
        S.On("UNIT_SPELL_HASTE", "player", function(_, _, a1)
            got = a1
        end)
        ctl.Fire("UNIT_SPELL_HASTE", fake.SECRET)
        assert.is_nil(got)
    end)

    it("drops every held and staged observation when the tracked set is rebuilt (their indices are the old set's)", function()
        S.Direct(VS.Obs.Moving, 101, 0, 1)
        S.Stage(VS.Obs.Moving, 101, 0, 1)
        I.Build(fs.def(fs.new()), 102)
        ctl.Tick(102)
        for i = 1, I.log.n do -- (a rebuild may log a target swap of its own, Sources/Target.lua)
            assert.are_not.equal(VS.Obs.Moving, I.ObsLog.At(I.log, i).kind)
        end
    end)

    it("starts in combat after a /reload in combat (no PLAYER_REGEN_DISABLED comes)", function()
        local api2, ctl2 = fake.new()
        ctl2.combat = true
        local ns2 = load.module()
        ns2.VirtualStateInternal.Build(fs.def(fs.new()), 1)
        ns2.VirtualState.Start(api2)
        assert.is_true(ns2.VirtualState.InCombat())
    end)

    it("knows combat from the regen events, not InCombatLockdown", function()
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.is_true(VS.InCombat())
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.is_false(VS.InCombat())
    end)
end)
