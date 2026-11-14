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
end)
