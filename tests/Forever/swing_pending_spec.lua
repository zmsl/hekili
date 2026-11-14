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
        local ready = st.rage.time_to_10 -- a 10-rage line: ready with the pending swing's rage, 0.15 s from now
        assert.is_true(math.abs(ready - 0.15) < 0.01, tostring(ready))
    end)

    it("forecasts nothing at the swing once it is not pending (an answer heard, its credit, a spend)", function()
        local t = swings(false)
        assert.is_true(math.abs(t[1] - 2.6) < 1e-3, tostring(t[1]))
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
end)
