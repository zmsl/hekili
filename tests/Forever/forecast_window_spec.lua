-- tests/Forever/forecast_window_spec.lua (dry-forecast, engine pass E-D6): the resource forecast reaches as far as the
-- longest window a display in use walks. Primary and AOE walk the global forecast window, Cooldowns, Interrupts and
-- Defensives their own Forecast Period; a non-main display reuses the forecast of the last full reset, so a period above
-- the global window walked past the forecast's end, where a cost answers 3600 (not ready). Through real updates of a
-- headless Arcane Mage (mana regen > 0), mana half full out of combat.
local headless = require("Game.harness.headless")
local mw = require("Forever.helpers.mage_world")

describe("the resource forecast's horizon", function()
    local H, S, t

    local function cycle()
        t = t + 0.2
        assert.is_true(headless.cycle(H, t))
        assert.are.same({}, H.errors)
    end

    before_each(function()
        local C = mw.Arcane
        H = headless.new({ character = C.character(), pack = C.PACK })
        assert.are.same({}, H.loadErrors)
        S = H.Hekili.State
        H.ctl.power[0] = math.floor(S.mana.max / 2)
        t = H.ctl.now
        cycle()
        local settings = H.Hekili.Engine.settings
        assert.are.equal(15, settings.performance.forecastWindow)
        settings.displays.Cooldowns.forecastPeriod = 30
        assert.is_true(H.Hekili.Engine.Subscribe("Cooldowns", function() end))
    end)

    -- The mana the forecast's floor reaches `dt` seconds on, and the reach time the state answers for it.
    local function reachAt(dt)
        S.reset("Primary")
        local r = S.mana
        assert.is_true(r.regen > 0 and r.actual_lo < r.max)
        local amount = r.actual_lo + r.regen * dt
        assert.is_true(amount < r.max)
        return S:TimeToResource(r, amount, true), r.forecast[r.fcount].t - S.query_time
    end

    it("reaches a separate Cooldowns display's longer Forecast Period", function()
        local cds = H.Hekili.Engine.settings.toggles.cooldowns
        cds.separate, cds.value = true, true
        cycle()
        local reach, horizon = reachAt(20)
        assert.is_true(horizon >= 30 - 1e-6, "horizon " .. horizon)
        assert.is_true(reach > 19 and reach < 21, "reach " .. reach)
    end)

    it("stays at the global window while that display is not in use", function()
        local cds = H.Hekili.Engine.settings.toggles.cooldowns
        cds.separate, cds.value = false, true
        cycle()
        local reach, horizon = reachAt(20)
        assert.is_true(horizon >= 15 - 1e-6 and horizon < 16, "horizon " .. horizon)
        assert.is_true(reach > 3599, "reach " .. reach) -- past the forecast's end: not reached
    end)
end)
