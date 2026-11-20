-- tests/Forever/swing_pending_spec.lua (central fix 15, GAP AK): the rage forecast of a swing the game paid but the
-- belief's floor does not hold yet (VS.SwingPending): its gain one poll after the usability answers can show it
-- (2 x ORACLE_MIN after the swing), the swings after it on their own times; none once it is no longer pending.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the rage forecast of a pending swing (GAP AK)", function()
    local H, st

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        st = H.Hekili.State
        st.reset("Primary", true)
    end)

    -- The main-hand swing entries of the rage forecast after a swing at p, the model's last swing, 0.05 s ago.
    local function swings(pending)
        local p, speed = st.now - 0.05, 2.6
        st.swings.mh_actual, st.swings.mh_speed, st.mainhand_speed = p, speed, speed
        st.swings.mh_pending = pending and p or 0 -- the reset's read of it (UnitAttackSpeed's third, border batch 2)
        st.rage.actual = 0
        st:ForecastSwingbasedResources()
        local out = {}
        for i = 1, st.rage.fcount do
            local f = st.rage.forecast[i]
            if f.e == "mainhand" then
                out[#out + 1] = f.t - p
            end
        end
        return out
    end

    it("forecasts the pending swing 0.2 s after it, the next one on its own time", function()
        local t = swings(true)
        assert.is_true(math.abs(t[1] - 2 * H.ns.VirtualStateInternal.Log.ORACLE_MIN) < 1e-6, tostring(t[1]))
        assert.is_true(math.abs(t[2] - 2.6) < 1e-3, tostring(t[2]))
        -- review I2: the entry records the pending swing time it accepted, so a pack reads it, not the core's test
        assert.are.equal(st.swings.mh_pending, st.rage.regenModel.mainhand.pending)
        local ready = st.rage.time_to_10 -- a 10-rage line: ready with the pending swing's rage, 0.15 s from now
        assert.is_true(math.abs(ready - 0.15) < 0.01, tostring(ready))
    end)

    it("forecasts nothing at the swing once it is not pending (an answer heard, its credit, a spend)", function()
        local t = swings(false)
        assert.is_true(math.abs(t[1] - 2.6) < 1e-3, tostring(t[1]))
        assert.are.equal(0, st.rage.regenModel.mainhand.pending)
    end)

    -- L872 (2): in the opener the model's anchor is the combat start (no swing landed yet: the pseudo swing), and the
    -- fight's first swing lands after it; that pending swing is newer than the anchor, so its gain is forecast and the
    -- swings after it run off it, not off the combat start, however soon after the pull it lands (review I1: a gap
    -- under half a swing too).
    for _, gap in ipairs({ 1.21, 0.5 }) do
        it(
            "forecasts a pending swing " .. gap .. " s newer than the model's anchor, the next one a swing after it",
            function()
                local speed, p = 2.1, st.now - 0.09
                st.swings.mh_actual, st.swings.mh_pseudo = 0, p - gap -- the combat start, gap s before the swing
                st.swings.mh_speed, st.mainhand_speed, st.swings.mh_pending = speed, speed, p
                st.rage.actual = 0
                st:ForecastSwingbasedResources()
                local t = {}
                for i = 1, st.rage.fcount do
                    local f = st.rage.forecast[i]
                    if f.e == "mainhand" then
                        t[#t + 1] = f.t - p
                    end
                end
                assert.is_true(math.abs(t[1] - 2 * H.ns.VirtualStateInternal.Log.ORACLE_MIN) < 1e-6, tostring(t[1]))
                assert.is_true(math.abs(t[2] - speed) < 1e-3, tostring(t[2]))
            end
        )
    end

    -- review R1: mid-fight, a pending swing newer than the last swing row (an early swing before its row lands, the
    -- model's anchor `gap` s before it): the swings after it run off it, a swing apart, whatever the gap.
    for _, gap in ipairs({ 0.6, 1.5, 2.1, 3.0 }) do
        it(
            "mid-fight, forecasts a pending swing " .. gap .. " s after the last swing row, the next a swing after it",
            function()
                local speed, p = 2.1, st.now - 0.09
                st.swings.mh_pseudo, st.swings.mh_actual = nil, p - gap
                st.swings.mh_speed, st.mainhand_speed, st.swings.mh_pending = speed, speed, p
                st.rage.actual = 0
                st:ForecastSwingbasedResources()
                local t = {}
                for i = 1, st.rage.fcount do
                    local f = st.rage.forecast[i]
                    if f.e == "mainhand" then
                        t[#t + 1] = f.t - p
                    end
                end
                assert.is_true(math.abs(t[1] - 2 * H.ns.VirtualStateInternal.Log.ORACLE_MIN) < 1e-6, tostring(t[1]))
                assert.is_true(math.abs(t[2] - speed) < 1e-3, tostring(t[2]))
            end
        )
    end

    -- review R1: the pending swing is the last swing row's own, pulled back 0.6 s by parry haste: the next one keeps the pull.
    it("mid-fight, a pending swing that is the last swing row's own keeps the anchor's parry pull", function()
        local speed, p = 2.1, st.now - 0.09
        st.swings.mh_actual, st.swings.mh_pseudo = p, p - 0.6
        st.swings.mh_speed, st.mainhand_speed, st.swings.mh_pending = speed, speed, p
        st.rage.actual = 0
        st:ForecastSwingbasedResources()
        local t = {}
        for i = 1, st.rage.fcount do
            local f = st.rage.forecast[i]
            if f.e == "mainhand" then
                t[#t + 1] = f.t - p
            end
        end
        assert.is_true(math.abs(t[2] - (speed - 0.6)) < 1e-3, tostring(t[2]))
    end)

    -- L872 (3): Reckless Swings' charges (wowsims talents_fury.go:360-391) pay 5 rage at each landed white swing of
    -- either hand; the belief pays them by its reaction at the swing's row, so the pending swing still holds its charge
    -- and is the first to pay it in the forecast, then the swings after it until the charges are gone.
    -- The forecast rage at `p + dt` for each dt (the last slice at or before it), from 0 at a swing at p.
    local function rageAt(hand, charges, dts)
        local p, speed = st.now - 0.05, 2.6
        local main = hand == "main"
        st.swings.mh_actual, st.swings.mh_speed, st.mainhand_speed =
            main and p or 0, main and speed or 0, main and speed or 0
        st.swings.oh_actual, st.swings.oh_speed, st.offhand_speed =
            main and 0 or p, main and 0 or speed, main and 0 or speed
        st.swings.mh_pending, st.swings.oh_pending = main and p or 0, main and 0 or p
        if charges > 0 then
            st.applyBuff("reckless_swings", 8, charges)
        else
            st.removeBuff("reckless_swings")
        end
        st.rage.actual = 0
        st:ForecastSwingbasedResources()
        local out = {}
        for k, dt in ipairs(dts) do
            out[k] = 0
            for i = 1, st.rage.fcount do
                local f = st.rage.forecast[i]
                if f.t <= p + dt + 1e-9 then
                    out[k] = f.v
                end
            end
        end
        return out
    end

    for _, hand in ipairs({ "main", "off" }) do
        it(
            "forecasts Reckless Swings' 5 rage on the pending " .. hand .. "-hand swing, then per charge (L872 (3))",
            function()
                local dts = { 0.25, 2.65, 5.25 } -- the pending swing, the next, the one after
                local base = rageAt(hand, 0, dts)
                assert.is_true(base[1] > 0, "the pending swing's own rage") -- the swing entries themselves
                local two = rageAt(hand, 2, dts)
                for k, extra in ipairs({ 5, 10, 10 }) do -- two charges: the pending swing's and the next one's
                    assert.is_true(
                        math.abs(two[k] - base[k] - extra) < 1e-6,
                        ("%s dt %.2f: %.3f vs %.3f + %d"):format(hand, dts[k], two[k], base[k], extra)
                    )
                end
            end
        )
    end

    -- L872 (2) with (3): a pending swing newer than the anchor (the opener's combat-start pseudo swing, the first swing
    -- landing over half a swing later) is forecast too, so it still holds the first charge: with one charge, the
    -- pending main-hand swing (0.09 s ago) pays the 5, not the off hand's next swing 0.05 s from now.
    it("gives a pending swing newer than the anchor the first Reckless charge (L872 (2) + (3))", function()
        local speed, p = 2.1, st.now - 0.09
        st.swings.mh_actual, st.swings.mh_pseudo = 0, st.now - 1.3
        st.swings.mh_speed, st.mainhand_speed, st.swings.mh_pending = speed, speed, p
        st.swings.oh_actual, st.swings.oh_speed, st.offhand_speed, st.swings.oh_pending = st.now - 2.05, speed, speed, 0
        st.applyBuff("reckless_swings", 8, 1)
        local model = st.rage.regenModel
        local orc = 2 * H.ns.VirtualStateInternal.Log.ORACLE_MIN
        assert.are.equal(5, model.reckless_mainhand.value(p + orc), "the pending main-hand swing")
        assert.are.equal(0, model.reckless_offhand.value(st.now + 0.05), "the off hand's next swing")
        assert.are.equal(0, model.reckless_mainhand.value(p + speed), "the main hand's next swing")
    end)

    -- flicker-085 review I1 (5922dc27d): a pending swing that is the last swing row's own (mh_actual, within 1 ms) is
    -- the anchor's swing: a parry-haste pull moved the anchor (mh_pseudo), and the swings after it keep the pulled phase.
    it("keeps a parry-pulled anchor's phase after the anchor's own pending swing (flicker-085 I1)", function()
        local speed = 2.6
        local actual = st.now - 0.05
        local pseudo = actual - 0.4 -- a parry-haste pull of 0.4 s
        st.swings.mh_actual, st.swings.mh_pseudo, st.swings.mh_pending = actual, pseudo, actual
        st.swings.mh_speed, st.mainhand_speed = speed, speed
        st.swings.oh_actual, st.swings.oh_speed, st.offhand_speed, st.swings.oh_pending = 0, 0, 0, 0
        st.applyBuff("reckless_swings", 8, 2)
        local model = st.rage.regenModel
        local orc = 2 * H.ns.VirtualStateInternal.Log.ORACLE_MIN
        assert.are.equal(5, model.reckless_mainhand.value(actual + orc), "the pending swing: the first charge")
        assert.are.equal(5, model.reckless_mainhand.value(pseudo + speed), "the pulled grid's next swing: the second")
        assert.are.equal(0, model.reckless_mainhand.value(pseudo + 2 * speed), "the one after: no charge left")
    end)
end)

-- review R3: in the opener (no main-hand swing row yet) the off hand's combat-start pseudo swing anchors it only until
-- its own first swing row lands; after that the off hand runs off the row, so a pending off-hand swing whose row has
-- landed resumes a swing after it, not off the pseudo grid.
describe("the off hand's opener anchor once its first swing row lands (review R3)", function()
    local H, st, VS, pending0, pull0

    before_each(function()
        H = headless.new({ character = ww.Fury.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        st, VS = H.Hekili.State, H.ns.VirtualState
        pending0, pull0 = VS.SwingPending, VS.SwingPull
        VS.SwingPull = function()
            return 0, 0
        end
    end)

    after_each(function()
        VS.SwingPending, VS.SwingPull = pending0, pull0
    end)

    it("forecasts the swing after a landed first off-hand swing a swing after it, not off the pseudo grid", function()
        local s = H.ctl.now - 0.05 -- the off hand's first swing, its row landed, the game's pending swing
        VS.SwingPending = function(hand)
            return hand == 2 and s or 0
        end
        -- the pull 1.6 s ago: the pseudo off-hand swing at combat + speed / 2 sits 0.65 s before now, off s's grid
        st.combat, st.swings.mh_actual, st.swings.oh_actual = H.ctl.now - 1.6, 0, s
        st.reset("Primary", true)
        local speed, t = st.offhand_speed, {}
        assert.is_true(speed > 1, tostring(speed))
        for i = 1, st.rage.fcount do
            local f = st.rage.forecast[i]
            if f.e == "offhand" then
                t[#t + 1] = f.t
            end
        end
        assert.is_true(#t >= 2, tostring(#t))
        assert.is_true(math.abs(t[1] - (s + 2 * H.ns.VirtualStateInternal.Log.ORACLE_MIN)) < 1e-6, tostring(t[1] - s))
        assert.is_true(math.abs(t[2] - (s + speed)) < 1e-3, ("%.3f vs %.3f"):format(t[2] - s, speed))
    end)

    -- L1456 (i), fix round 1: a swing entry's `width` (a proc the belief cannot see) keeps the forecast's floor stream
    -- off it as the belief's own floor is: each forecast swing, the pending one included, adds value - width to the
    -- floor, value + width to the top and the value to the estimate.
    it("steps a forecast swing's floor by value - width and its top by value + width", function()
        local model = st.rage.regenModel.mainhand
        model.width = 0.5
        local p, speed = st.now - 0.05, 2.6
        st.swings.mh_actual, st.swings.mh_speed, st.mainhand_speed = p, speed, speed
        st.swings.mh_pending = p
        st.rage.actual, st.rage.actual_lo, st.rage.actual_hi = 0, 0, 0
        st:ForecastSwingbasedResources()
        model.width = nil
        local seen = 0
        for i = 2, st.rage.fcount do
            local f, prev = st.rage.forecast[i], st.rage.forecast[i - 1]
            if f.e == "mainhand" and f.v < 100 then
                local value = f.v - prev.v
                assert.is_true(value > 1, tostring(value))
                assert.is_true(math.abs(f.l - prev.l - (value - 0.5)) < 1e-9, ("lo step %.3f"):format(f.l - prev.l))
                assert.is_true(math.abs(f.h - prev.h - (value + 0.5)) < 1e-9, ("hi step %.3f"):format(f.h - prev.h))
                seen = seen + 1
            end
        end
        assert.is_true(seen >= 2, tostring(seen)) -- the pending swing and the one after it
    end)

    -- review M2: a negative gain (a decay) with a width keeps falling: the floor takes gain - width, the top gain + width
    it("steps a decay with a width by gain - width on its floor, never stopping it", function()
        local model = st.rage.regenModel.mainhand
        local value = model.value
        model.width, model.value = 0.5, -3
        local p, speed = st.now - 0.05, 2.6
        st.swings.mh_actual, st.swings.mh_speed, st.mainhand_speed = p, speed, speed
        st.swings.mh_pending = p
        st.rage.actual, st.rage.actual_lo, st.rage.actual_hi = 50, 50, 50
        st:ForecastSwingbasedResources()
        model.width, model.value = nil, value
        local seen = 0
        for i = 2, st.rage.fcount do
            local f, prev = st.rage.forecast[i], st.rage.forecast[i - 1]
            if f.e == "mainhand" and f.l > 0 then
                assert.is_true(math.abs(f.l - prev.l + 3.5) < 1e-9, ("lo step %.3f"):format(f.l - prev.l))
                assert.is_true(math.abs(f.h - prev.h + 2.5) < 1e-9, ("hi step %.3f"):format(f.h - prev.h))
                assert.is_true(f.l <= f.v, ("lo %.3f over est %.3f"):format(f.l, f.v))
                seen = seen + 1
            end
        end
        assert.is_true(seen >= 2, tostring(seen))
    end)
end)
