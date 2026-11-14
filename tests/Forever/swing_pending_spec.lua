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
end)
