-- Virtual/State/spec/swing_spec.lua: swings and melee haste (spec §6.4, §6.5). Golden scenario 1 (TDF
-- tests/model/swing_replay_spec.lua:96): swing anchors within tolerance from rage steps every 2.6 s with casts
-- interleaved, without a PLAYER_SWING after the pull.
local load = require("Virtual.State.spec.helpers.load")
local fake = require("Virtual.State.spec.helpers.fake_api")
local fs = require("Virtual.State.spec.helpers.fake_spec")

describe("swings", function()
    local VS, I, S, Obs

    before_each(function()
        local ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        S, Obs = I.Sources, VS.Obs
        I.Build(fs.def(fs.new(9)), 90)
        I.api = fake.new()
    end)

    it("gives swing anchors within tolerance from rage steps every 2.6 s with casts interleaved", function()
        S.Direct(Obs.Swing, 90, 1, 2.6, 0) -- the out-of-combat speed read
        S.Direct(Obs.CombatStart, 100) -- a guess at weight 0.3
        local swings = {}
        for k = 0, 7 do
            swings[#swings + 1] = 100.4 + 2.6 * k -- the true swings: one rage step each
        end
        local casts = { 103.9, 109.1, 114.7 } -- our casts: their own power ticks don't pair
        local events = {}
        for _, t in ipairs(swings) do
            events[#events + 1] = { t, Obs.PowerTick }
        end
        for _, t in ipairs(casts) do
            events[#events + 1] = { t, Obs.CastSuccess }
            events[#events + 1] = { t + 0.01, Obs.PowerTick }
        end
        table.sort(events, function(a, b)
            return a[1] < b[1]
        end)
        local checked = 0
        for _, e in ipairs(events) do
            if e[2] == Obs.PowerTick then
                S.Direct(Obs.PowerTick, e[1], 1)
            else
                S.Direct(Obs.CastSuccess, e[1], 3)
            end
            I.Fold(e[1], false)
            if e[1] >= 104 then
                local now = e[1] + 0.05
                local want
                for _, s in ipairs(swings) do
                    if s > now then
                        want = want or s
                    end
                end
                want = want or swings[#swings] + 2.6
                local got = VS.Swing(1, now)
                assert.is_true(math.abs(got.est - want) <= I.SWING_TOL, ("at %.2f: %.3f vs %.3f"):format(now, got.est, want))
                checked = checked + 1
            end
        end
        assert.is_true(checked >= 10)
        local mh = VS.Swing(1, 119)
        assert.are.equal("modelled", mh.basis)
        assert.is_true(mh.conf > 0.4, tostring(mh.conf))
    end)

    it("anchors at PLAYER_SWING with weight 1 and takes its duration as the hasted speed", function()
        I.inCombat = true -- (the Player source sets it at PLAYER_REGEN_DISABLED)
        S.Direct(Obs.Swing, 90, 1, 3.6, 2) -- base (unhasted) speed
        S.Direct(Obs.CombatStart, 99)
        S.Direct(Obs.Swing, 100, 1, 3.0, 1)
        I.Fold(100, false)
        local s = VS.Swing(1, 100)
        assert.are.same({ 103, 1, "observed" }, { s.est, s.conf, s.basis })
        assert.are.equal(3.0, VS.SwingSpeed(1, 101).est)
        assert.are.equal(100, VS.LastSwing(1))
        assert.are.same({ 3.6, 0 }, { VS.SwingBase(1), VS.SwingBase(2) }) -- the base, not the hasted 3.0
        assert.is_true(math.abs(VS.Haste(101).est - 1.2) < 1e-9)
        assert.are.equal("modelled", VS.Haste(101).basis)
        assert.is_true(math.abs(VS.Swing(1, 106).conf - 0.4) < 1e-9) -- falls linearly over SWING_DECAY
    end)

    it("clears anchors at combat end and keeps speeds", function()
        S.Direct(Obs.Swing, 100, 1, 2.6, 1)
        S.Direct(Obs.CombatEnd, 101)
        I.Fold(101, false)
        assert.are.same({ 0, 0 }, { VS.Swing(1, 102).est, VS.Swing(1, 102).conf })
        assert.are.equal(2.6, VS.SwingSpeed(1, 102).est)
    end)
end)
