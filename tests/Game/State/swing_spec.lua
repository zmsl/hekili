-- tests/Game/State/swing_spec.lua: swings and melee haste (spec §6.4, §6.5). Golden scenario 1 (TDF
-- tests/model/swing_replay_spec.lua:96): swing anchors within tolerance from rage steps every 2.6 s with casts
-- interleaved, without a PLAYER_SWING after the pull. The ranged hand (hand 3, class-completion C7): anchored on the
-- ranged auto attack's own cast success (an ability declaring `rangedSwing`) at the out-of-combat UnitRangedDamage
-- speed, or on a PLAYER_SWING of swingType 2 (unmeasured on Forever) at its duration.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

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
                assert.is_true(
                    math.abs(got.est - want) <= I.SWING_TOL,
                    ("at %.2f: %.3f vs %.3f"):format(now, got.est, want)
                )
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
        S.Direct(Obs.Swing, 100, 1, 3.0, 4)
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
        S.Direct(Obs.Swing, 100, 1, 2.6, 4)
        S.Direct(Obs.CombatEnd, 101)
        I.Fold(101, false)
        assert.are.same({ 0, 0 }, { VS.Swing(1, 102).est, VS.Swing(1, 102).conf })
        assert.are.equal(2.6, VS.SwingSpeed(1, 102).est)
    end)

    describe("parry haste (parry-haste spec decisions 57-59, the owner's ruling 2026-10-23)", function()
        -- in combat: the main hand (2.0 s) swung at 100, next at 102; the off hand (2.0 s) at 100.1
        local function swung()
            I.inCombat = true
            S.Direct(Obs.Swing, 100, 1, 2.0, 4)
            S.Direct(Obs.Swing, 100.1, 2, 2.0, 4)
            I.Fold(100.1, false)
        end
        local function parry(t)
            S.Direct(Obs.PlayerHit, t, I.HitKind.PARRY, 0, 60)
            I.Fold(t, false)
        end
        local function near(want, got)
            assert.is_true(math.abs(want - got) < 1e-9, ("%.6f vs %.6f"):format(got, want))
        end

        it("L.ParryPull: the replay's pulls; nothing at or under 20% of the swing left", function()
            local P = I.Log.ParryPull
            near(0.2264, P(0.697, 2.353)) -- the 20% branch: 0.697 - 0.4706
            near(0.9412, P(2.0, 2.353)) -- the 40% branch
            near(0.6, P(1.2, 1.5))
            near(0.2, P(0.5, 1.5))
            near(0.068, P(0.368, 1.5))
            assert.are.same({ 0, 0, 0 }, { P(0.3, 1.5), P(0.2, 1.5), P(1, 0) })
        end)

        it("pulls the next main-hand swing by 40% of its duration when more than 60% is left", function()
            swung()
            parry(100.5) -- r = 1.5 > 1.2: 0.8
            near(101.2, VS.Swing(1, 100.5).est)
            local x, from = VS.SwingPull(1)
            near(0.8, x)
            assert.are.equal(100, from)
            near(103.2, VS.Swing(1, 101.3).est) -- the swings after it move with it until the next PLAYER_SWING
        end)

        it("pulls it down to 20% of its duration when 20-60% is left", function()
            swung()
            parry(101.3) -- r = 0.7: 0.7 - 0.4
            near(101.7, VS.Swing(1, 101.3).est)
            near(0.3, (VS.SwingPull(1)))
        end)

        it("pulls nothing at or under 20% left", function()
            swung()
            parry(101.7) -- r = 0.3 <= 0.4
            near(102, VS.Swing(1, 101.7).est)
            assert.are.same({ 0, 0 }, { VS.SwingPull(1) })
        end)

        it("never pulls the off hand; a second parry pulls again from the pulled time", function()
            swung()
            parry(100.2) -- r = 1.8: 0.8, next 101.2
            parry(100.3) -- r = 0.9: min(0.8, 0.5), next 100.7
            near(100.7, VS.Swing(1, 100.3).est)
            near(1.3, (VS.SwingPull(1)))
            near(102.1, VS.Swing(2, 100.3).est)
            assert.are.same({ 0, 0 }, { VS.SwingPull(2) })
        end)

        it("keys the pull to its swing: a later swing is never pulled by it; combat end clears it", function()
            swung()
            parry(100.5) -- 0.8, taken from the swing at 100
            S.Direct(Obs.Swing, 101.2, 1, 2.0, 4) -- the hastened swing
            I.Fold(101.2, false)
            near(103.2, VS.Swing(1, 101.2).est) -- the real swing's anchor: the pull is not applied again
            local x, from = VS.SwingPull(1)
            near(0.8, x)
            assert.are.equal(100, from) -- still the swing at 100: a reader whose last swing is 101.2 ignores it
            parry(101.5) -- r = 1.7: 0.8 from the swing at 101.2, a new pull, not added to the old one
            x, from = VS.SwingPull(1)
            near(0.8, x)
            assert.are.equal(101.2, from)
            S.Direct(Obs.CombatEnd, 102)
            I.Fold(102, false)
            assert.are.same({ 0, 0 }, { VS.SwingPull(1) })
        end)

        it("allocates nothing per parry", function()
            swung()
            local n = 0
            local bytes = alloc.bytes(function()
                n = n + 1
                local t = 100 + 2 * n
                S.Direct(Obs.Swing, t, 1, 2.0, 4)
                S.Direct(Obs.PlayerHit, t + 0.5, I.HitKind.PARRY, 0, 60)
                I.Fold(t + 0.5, false)
                VS.SwingPull(1)
            end, 2000)
            assert.are.equal(0, bytes)
        end)
    end)

    describe("the ranged hand (C7)", function()
        local api, ctl, ns, saved, rows
        local R = fs.SPENDER_R

        before_each(function()
            api, ctl = fake.new()
            saved = {}
            for k, v in pairs({
                CreateFrame = api.CreateFrame,
                issecretvalue = api.issecretvalue,
                GetTime = api.GetTime,
            }) do
                saved[k] = rawget(_G, k) or false
                _G[k] = v
            end
            ns = load.module()
            VS, I = ns.VirtualState, ns.VirtualStateInternal
            S, Obs = I.Sources, VS.Obs
            I.Build(fs.def(fs.new(9, nil, true)), 1)
            ctl.now = 2
            rows = {}
            local GetInfo = ns.Facade.CombatLogGetCurrentEventInfo
            local sink = I.Events.CreateFrame("Frame")
            sink:SetScript("OnEvent", function()
                local _, ev = GetInfo()
                if ev:find("^SWING") then -- a melee swing's row
                    rows[#rows + 1] = ev
                end
            end)
            sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        end)

        after_each(function()
            for k, v in pairs(saved) do
                _G[k] = v or nil
            end
        end)

        local function at(t, event, ...)
            ctl.Tick(t)
            ctl.Fire(event, ...)
            ctl.Tick(t)
            fs.fold(ns, t)
            ctl.Tick(t)
        end

        it(
            "anchors on the auto attack's cast success at the out-of-combat ranged speed; the melee hands stay",
            function()
                VS.Start(api) -- reads UnitRangedDamage's speed, 3.1 (fake_api)
                ctl.Tick(2) -- the staged flush
                fs.fold(ns, 2)
                assert.are.equal(3.1, VS.SwingSpeed(3, 2).est)
                assert.are.equal(0, VS.Swing(3, 2).est) -- no shot yet
                at(9.9, "PLAYER_REGEN_DISABLED")
                at(10, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", R)
                local s = VS.Swing(3, 10)
                assert.are.same({ 13.1, 1, "modelled" }, { s.est, s.conf, s.basis })
                assert.is_true(math.abs(VS.Swing(3, 14).est - 16.2) < 1e-9) -- one period on, uncast
                assert.are.equal(10, VS.LastSwing(3))
                assert.are.equal(3.1, (ns.Facade.UnitRangedDamage("player")))
                assert.are.equal(0, VS.LastSwing(1))
                assert.are.equal(2.6, VS.SwingSpeed(1, 10.5).est)
                assert.are.same({}, rows) -- a shot is no melee swing
            end
        )

        it("anchors at a PLAYER_SWING of swingType 2 with weight 1 and takes its duration as the speed", function()
            VS.Start(api)
            at(9.9, "PLAYER_REGEN_DISABLED")
            local haste = VS.Haste(10).est
            at(10, "PLAYER_SWING", 2.8, 2)
            local s = VS.Swing(3, 10)
            assert.are.same({ 12.8, 1, "observed" }, { s.est, s.conf, s.basis })
            assert.are.equal(2.8, VS.SwingSpeed(3, 10).est)
            assert.are.equal(2.8, (ns.Facade.UnitRangedDamage("player")))
            assert.are.equal(haste, VS.Haste(10).est) -- melee haste learns from the main hand only
            assert.are.equal(0, VS.LastSwing(1))
            assert.is_true(VS.Swing(1, 10).conf <= 0.3) -- the main hand keeps its combat-start guess
            at(12, "UNIT_COMBAT", "target", "WOUND", "", 45, 1)
            assert.are.same({}, rows) -- not a melee swing: no SWING_DAMAGE
            at(12.8, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", R) -- the same shot's success re-anchors
            assert.is_true(math.abs(VS.Swing(3, 13).est - 15.6) < 1e-9)
        end)

        it("has no speed and no clock when UnitRangedDamage is secret, and gives content none of it", function()
            ctl.ranged[1] = fake.SECRET
            VS.Start(api)
            at(10, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", R)
            assert.are.same({ 0, 0, 0 }, { VS.SwingSpeed(3, 10).est, VS.Swing(3, 10.5).est, VS.Swing(3, 10.5).conf })
            assert.is_false(api.issecretvalue((ns.Facade.UnitRangedDamage("player"))))
        end)

        it("clears the ranged anchor at combat end and keeps its speed", function()
            VS.Start(api)
            at(9.9, "PLAYER_REGEN_DISABLED")
            at(10, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", R)
            at(11, "PLAYER_REGEN_ENABLED")
            assert.are.same({ 0, 0 }, { VS.Swing(3, 12).est, VS.Swing(3, 12).conf })
            assert.are.equal(3.1, VS.SwingSpeed(3, 12).est)
        end)
    end)
end)
