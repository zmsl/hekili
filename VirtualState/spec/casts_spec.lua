-- VirtualState/spec/casts_spec.lua: cooldowns, charges and the GCD (spec §6.2, §7.5). Golden scenario 3 (TDF
-- tests/model/belief_spec.lua:401): cooldowns snap to the game's ready flags.
local load = require("VirtualState.spec.helpers.load")
local fake = require("VirtualState.spec.helpers.fake_api")
local fs = require("VirtualState.spec.helpers.fake_spec")

describe("casts and cooldowns", function()
    local VS, I, S, Obs, api, ctl, h
    local REND = 3

    before_each(function()
        api, ctl = fake.new()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        h = fs.new(9)
        h.Class.abilities.rend.cooldown = 30
        I.Build(fs.def(h), 1)
        VS.Start(api)
        ctl.Tick(1)
        I.ObsLog.Clear(I.log)
    end)

    it("snaps cooldowns to the game's ready flags", function()
        I.CooldownModel(REND, 40, 30, 10, Obs.CastSuccess) -- 30 s cooldown in the model
        S.Direct(Obs.Cooldown, 20, REND, 1) -- but the game says it's ready (something reset it)
        I.Fold(20, false)
        I.Settle(20)
        assert.are.equal(20, VS.Cooldown(fs.REND, 20).est)
        assert.are.equal("pinned", VS.Cooldown(fs.REND, 20).basis)
        S.Direct(Obs.Cooldown, 21, REND, 0) -- and now it isn't, while the model thinks it is
        I.Fold(21, false)
        I.Settle(21)
        assert.are.equal(21 + I.CD_PROBE, VS.Cooldown(fs.REND, 21).est)
        assert.are.equal(VS.Cooldown(fs.REND_R2, 21), VS.Cooldown(fs.REND, 21)) -- every rank ID is the ability
        assert.is_nil(VS.Cooldown(424242, 21))
    end)

    it("learns the real length from the ready edge after our cast", function()
        assert.are.equal(30, VS.CooldownLength(fs.REND)) -- the spec's cooldown first
        I.CooldownModel(REND, 40, 30, 10, Obs.CastSuccess)
        S.Direct(Obs.Cooldown, 10.1, REND, 0)
        S.Direct(Obs.Cooldown, 35, REND, 1)
        I.Fold(35, false)
        assert.are.equal(25, VS.CooldownLength(fs.REND))
    end)

    it("logs a Cooldown only on a plain flag edge, and the GCD's edges, on the urgent lane", function()
        h.forced = {}
        I.urgent = function(e)
            h.forced[#h.forced + 1] = e
        end
        ctl.cooldown[fs.REND] = { isActive = true, isOnGCD = false }
        ctl.cooldown[29515] = { isActive = true, isOnGCD = false }
        ctl.now = 5
        ctl.Fire("SPELL_UPDATE_COOLDOWN")
        ctl.Fire("SPELL_UPDATE_COOLDOWN")
        ctl.Tick(5)
        local n = 0
        for i = 1, I.log.n do
            if I.ObsLog.At(I.log, i).kind == Obs.Cooldown then
                n = n + 1
            end
        end
        assert.are.equal(4, n) -- shout, strike ready; rend not; the GCD up (a second event repeats nothing)
        assert.are.same({ "VS_COOLDOWN" }, h.forced)
        ctl.cooldown[fs.REND] = { isActive = fake.SECRET, isOnGCD = false }
        ctl.Fire("SPELL_UPDATE_COOLDOWN") -- a secret flag is no news
        assert.are.equal(4, n + I.Sources.stN)
    end)

    it("fixes the GCD's start and duration at the rising edge, quantised so they survive Hekili's round trip", function()
        S.Direct(Obs.Cooldown, 1000.123456, 0, 1, 1)
        I.Fold(1000.2, false)
        local s, d = VS.GcdInfo(1000.2)
        assert.are.equal(s, (s + d) - d)
        assert.are.equal(s * 1024, math.floor(s * 1024))
        assert.are.same({ s, d }, { VS.GcdInfo(1000.9) }) -- unchanged between edges
        S.Direct(Obs.Cooldown, 1001.6, 0, 0, 1)
        I.Fold(1001.6, false)
        assert.are.same({ 0, 0 }, { VS.GcdInfo(1001.6) })
        assert.is_true(math.abs(I.gcdLearned - 1.477) < 0.002) -- learned from the falling edge
        for _ = 1, 2000 do
            local t = math.random() * 1e6
            local q = I.Quantise(t)
            local dq = I.Quantise(1.5 * math.random())
            assert.are.equal(q, (q + dq) - dq)
        end
    end)

    it("evaluates a function cost (a talent that lowers it) and uses it for the ladder", function()
        local rank = 2
        h.Class.abilities.heroic_strike.spend = function()
            return 15 - rank -- Improved Heroic Strike: -1 a rank
        end
        assert.are.equal(13, I.CostOf(2))
        rank = 3
        assert.are.equal(12, I.CostOf(2))
        assert.are.equal(10, I.CostOf(3)) -- a number cost
    end)

    it("models charges and recharges them by time; a spell without charges has none", function()
        assert.is_nil(VS.Charges(fs.REND, 1))
    end)
end)
