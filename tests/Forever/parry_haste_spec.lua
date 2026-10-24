-- tests/Forever/parry_haste_spec.lua (parry-haste spec decision 59, plan amendment 1): Hekili's reset applies the
-- belief's parry-haste pull to the main hand's phase (swings.mainhand, the rage forecast's `last`) and to nextMH,
-- only while mh_actual is the swing the pull was taken from.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("parry haste in Hekili's swing state", function()
    local H, st, VS, pull0, pending0

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        st, VS = H.Hekili.State, H.ns.VirtualState
        pull0, pending0 = VS.SwingPull, VS.SwingPending
        VS.SwingPending = function()
            return 0
        end
    end)

    after_each(function()
        VS.SwingPull, VS.SwingPending = pull0, pending0
    end)

    -- A reset in combat with our last main-hand swing 0.3 s ago and a belief pull of `x` taken from swing `from`
    -- (an offset from that swing). Returns the swing time and the main-hand forecast entries' times.
    local function resetWith(x, fromOffset)
        local s = H.ctl.now - 0.3
        st.combat, st.swings.mh_actual = H.ctl.now - 10, s
        VS.SwingPull = function(hand)
            if hand ~= 1 then
                return 0, 0
            end
            return x, s + fromOffset
        end
        st.reset("Primary", true)
        local out = {}
        for i = 1, st.rage.fcount do
            local f = st.rage.forecast[i]
            if f.e == "mainhand" then
                out[#out + 1] = f.t
            end
        end
        return s, out
    end

    local function near(want, got)
        assert.is_true(math.abs(want - got) < 1e-6, ("%.4f vs %.4f"):format(got, want))
    end

    it("pulls nextMH, the swing phase and the rage forecast by the pull taken from mh_actual's swing", function()
        local s, f = resetWith(0.6, 0)
        local speed = st.mainhand_speed
        assert.is_true(speed > 1)
        near(s, st.swings.mh_actual) -- the real swing stays
        near(s - 0.6, st.swings.mainhand)
        near(s - 0.6 + speed, st.nextMH)
        near(s - 0.6 + speed, f[1])
    end)

    it("ignores a pull taken from another swing (its row not landed yet, or a stale one) and no pull", function()
        for _, case in ipairs({ { 0.6, 2.0 }, { 0.6, -2.0 }, { 0, 0 } }) do
            local s, f = resetWith(case[1], case[2])
            local speed = st.mainhand_speed
            near(s, st.swings.mainhand)
            near(s + speed, st.nextMH)
            near(s + speed, f[1])
        end
    end)
    it(
        "pulls the combat-start anchor by a pull taken before the fight's first swing (from: 0 or an older fight)",
        function()
            local speed
            for _, from in ipairs({ 0, H.ctl.now - 30 }) do
                st.combat, st.swings.mh_actual = H.ctl.now - 0.2, 0
                VS.SwingPull = function(hand)
                    if hand ~= 1 then
                        return 0, 0
                    end
                    return 0.6, from
                end
                st.reset("Primary", true)
                speed = st.mainhand_speed
                local f
                for i = 1, st.rage.fcount do
                    if st.rage.forecast[i].e == "mainhand" then
                        f = f or st.rage.forecast[i].t
                    end
                end
                near(st.combat - 0.6, st.swings.mainhand)
                near(st.combat - 0.6 + speed, f)
                assert.are.equal(0, st.nextMH) -- E8: no nextMH before the first swing row
            end
        end
    )

    it("a pending swing (GAP AK) with a live pull: the pending gain, then the pulled swing; nextMH agrees", function()
        local s = H.ctl.now - 0.05
        VS.SwingPending = function(hand)
            return hand == 1 and s or 0
        end
        st.combat, st.swings.mh_actual = H.ctl.now - 10, s
        VS.SwingPull = function(hand)
            if hand ~= 1 then
                return 0, 0
            end
            return 0.6, s
        end
        st.reset("Primary", true)
        local speed, f = st.mainhand_speed, {}
        for i = 1, st.rage.fcount do
            if st.rage.forecast[i].e == "mainhand" then
                f[#f + 1] = st.rage.forecast[i].t
            end
        end
        near(s + 2 * H.ns.VirtualStateInternal.Log.ORACLE_MIN, f[1])
        near(s - 0.6 + speed, f[2]) -- pulled once, not twice
        near(s - 0.6 + speed, st.nextMH)
        near(s - 0.6, st.swings.mainhand)
    end)
end)
