-- tests/Game/harness/fsr_forecast_spec.lua (central fix 12 item 1): the sim's forecast of a resource under the
-- five-second rule: the casting rate inside the window our last spend opened, the not-casting rate outside it.
local headless = require("Game.harness.headless")

describe("the sim's five-second-rule forecast", function()
    local H, S, r
    setup(function()
        H = headless.new()
        S = H.Hekili.State
        rawset(S, "gcd", { remains = 0 }) -- no character booted: no GCD ability to read
    end)

    before_each(function()
        local spec = H.Hekili.Class.specs[0]
        spec:RegisterResource(H.env.Enum.PowerType.Mana)
        r = spec.resources.mana.state
        rawset(S, "mana", r)
        S.now, S.offset, S.delay = 100, 0, 0
        r.actual, r.max, r.regen = 0, 10000, nil
        r.active_regen, r.inactive_regen, r.fsr_until = 0, 22, 100 -- the last spend 5 s ago: the window ends now
    end)

    -- The forecast mana at `t` seconds from now.
    local function at(t)
        S.offset = t
        local v = r.current
        S.offset = 0
        return v
    end

    it("gains nothing inside the window and the not-casting rate after it", function()
        r.fsr_until = 105 -- a spend at 0 (now 100): the window ends at 5
        S.forecastResources("mana")
        assert.are.equal(0, at(5) - at(0))
        assert.are.equal(110, at(10) - at(5))
        assert.are.equal(0, r.regen)
        assert.are.equal(5 + 1, S:TimeToResource(r, 22)) -- 5 s of nothing, then 22 at 22/s
    end)

    it("restarts the window at a spend the sim itself queues", function()
        r.actual, r.fsr_until = 1000, 105
        S.forecastResources("mana")
        S.offset = 3
        S.spend(100, "mana") -- the queued cast's spend at 3: the window now ends at 8
        assert.are.equal(103 + 5, r.fsr_until)
        local base = r.current
        assert.are.equal(0, at(8) - base)
        assert.are.equal(110, at(13) - at(8))
    end)

    it("keeps the old single rate for a resource without a window", function()
        r.fsr_until = false
        r.active_regen, r.inactive_regen = 10, 10
        S.forecastResources("mana")
        assert.are.equal(50, at(5) - at(0))
    end)
end)
