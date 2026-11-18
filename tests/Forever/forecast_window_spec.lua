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

-- E-D7 (engine pass E6): state:CombinedResourceRegen (the `regen_combined` key) reads each aura-gated regen entry as the
-- forecast does: the forecast's gates, an interval that may be a state field's name or a function, a guarded divisor.
-- Guardian's swing rage in Bear Form is aura-gated with the interval "mainhand_speed": it raised (arithmetic on a string).
describe("the combined regen rate", function()
    it("reads Guardian's Bear Form swing rage as the forecast does, never raising", function()
        local C = require("Forever.helpers.druid_loop_world").Guardian
        local H = headless.new({ character = C.character(), pack = C.PACK })
        assert.are.same({}, H.loadErrors)
        local S = H.Hekili.State
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.is_true(S.buff.bear_form.up)
        local ok, rate = pcall(function()
            return S.rage.regen_combined
        end)
        assert.is_true(ok, tostring(rate))
        local e = S.rage.regenModel.mainhand
        assert.is_true(S.mainhand_speed > 0)
        local base = S.rage.regen > 0.001 and S.rage.regen or 0
        local enrage = S.buff.enrage.up and S.rage.regenModel.enrage.value or 0 -- 2 a second
        assert.is_true(
            math.abs(rate - (base + e.value() / S.mainhand_speed + enrage)) < 1e-9,
            "rate " .. tostring(rate)
        )
    end)

    -- review M4: an entry a gate excludes adds nothing. With Bear Form gone the swing entry's aura gate fails.
    it("leaves out an entry its aura gate excludes", function()
        local C = require("Forever.helpers.druid_loop_world").Guardian
        local H = headless.new({ character = C.character(), pack = C.PACK })
        assert.are.same({}, H.loadErrors)
        local S = H.Hekili.State
        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
        assert.is_true(S.rage.regenModel.mainhand.value() / S.mainhand_speed > 0)
        S.removeBuff("bear_form")
        assert.is_false(S.buff.bear_form.up)
        local base = S.rage.regen > 0.001 and S.rage.regen or 0
        local enrage = S.buff.enrage.up and S.rage.regenModel.enrage.value or 0
        assert.is_true(math.abs(S.rage.regen_combined - (base + enrage)) < 1e-9, "rate " .. S.rage.regen_combined)
    end)
end)
