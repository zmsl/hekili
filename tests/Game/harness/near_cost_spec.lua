-- tests/Game/harness/near_cost_spec.lua (mana-regen plan, Task 4a): the sim marks an ability "near its cost" when
-- its resource alone holds it, the belief's estimate (the `current` stream) reaches the cost within
-- EARLY_EXIT (at the estimate the pick would end the list scan) and the floor reaches it within one more update
-- (the usability poll that settles it). Core keeps such a pick over a later entry that is merely ready sooner
-- (Engine/Sim/Core.lua); its wait stays the floor's, so it shows as a countdown and never ready early.
local headless = require("Game.harness.headless")

describe("the sim's near-cost mark (TimeToReady)", function()
    local H, S, r
    setup(function()
        H = headless.new()
        S = H.Hekili.State
        local class = H.Hekili.Class
        local spec = class.specs[0]
        spec:RegisterResource(H.env.Enum.PowerType.Mana)
        r = spec.resources.mana.state
        rawset(S, "mana", r)
        rawset(S, "gcd", { remains = 0 }) -- no character booted: no GCD ability to read
        rawset(S.cooldown, "global_cooldown", { remains = 0 }) -- nor its cooldown row (a booted class registers it)
        local defs = {
            surge = { id = -9201, spend = 370, spendType = "mana" },
            focus = { id = -9202, spend = 121, spendType = "mana" },
            veil = { id = -9203, spend = 370, spendType = "mana", nobuff = "veil_up" },
        }
        for k, d in pairs(defs) do
            spec:RegisterAbility(k, d)
            class.abilities[k] = spec.abilities[k]
        end
    end)

    before_each(function()
        S.now, S.offset, S.delay = 100, 0, 0
        r.actual, r.max, r.regen, r.tick_rate, r.last_tick = 366, 10000, nil, 0, nil -- the estimate 366: 0.11 s from 370
        r.actual_lo, r.actual_hi = 360, 366 -- the floor 360, 0.26 s; continuous 38/s
        r.active_regen, r.inactive_regen, r.fsr_until = 38, 38, false
        S.forecastResources("mana")
    end)

    it(
        "marks an ability the resource alone holds whose estimate reaches the cost within EARLY_EXIT; the wait stays the floor's",
        function()
            local w = S:TimeToReady("surge")
            assert.is_true(S.nearCost)
            assert.is_true(w >= 0.26 and w <= 0.27, w) -- (370 - 360) / 38 from the floor, not 4 / 38 from the estimate
            S:TimeToReady("focus") -- affordable now: no resource wait, not near
            assert.is_false(S.nearCost)
        end
    )

    it(
        "does not mark it when the estimate's reach exceeds EARLY_EXIT, nor when the floor's exceeds it by over an update",
        function()
            r.actual = 360 -- the estimate is the floor: 0.26 s > EARLY_EXIT
            S.forecastResources("mana")
            S:TimeToReady("surge")
            assert.is_false(S.nearCost)
            r.actual, r.actual_lo = 368, 340 -- the estimate 368 (0.05 s), the floor 0.79 s away: past one update
            S.forecastResources("mana")
            S:TimeToReady("surge")
            assert.is_false(S.nearCost)
        end
    )

    -- CN8 C1 (dim never promote): a resource wait inside Output's READY (0.05 s) would show ready while the floor is
    -- still under the cost; the press then meets the client's no (the forecast's regen not yet landed)
    it("reads a floor wait inside READY (0.05 s) as 0.06: never ready while the floor is under the cost", function()
        r.actual, r.actual_lo = 369.5, 369 -- the floor 1 under: 0.026 s at 38/s
        S.forecastResources("mana")
        assert.are.equal(0.06, S:TimeToReady("surge"))
        r.actual, r.actual_lo = 369.5, 367 -- 3 under: 0.079 s, past READY, unchanged
        S.forecastResources("mana")
        assert.are.equal(0.08, S:TimeToReady("surge"))
    end)

    it("does not mark it when a cooldown, or a check after the resource, holds it", function()
        rawset(S.cooldown, "surge", { remains = 2 })
        local w = S:TimeToReady("surge")
        assert.are.equal(2, w)
        assert.is_false(S.nearCost)
        rawset(S.cooldown, "surge", nil)
        rawset(S.buff, "veil_up", { remains = 12 }) -- the nobuff check, applied after the resource wait
        w = S:TimeToReady("veil")
        assert.are.equal(12, w)
        assert.is_false(S.nearCost)
        rawset(S.buff, "veil_up", nil)
    end)

    it("does not mark a swing-paid resource: it moves only at swings, so no regen is answered late", function()
        r.swingGen = true -- Spec.lua's flag for a resource a swing entry pays
        local w = S:TimeToReady("surge")
        r.swingGen = false
        assert.is_true(w >= 0.26 and w <= 0.27, w)
        assert.is_false(S.nearCost)
    end)

    -- Press decisions read the floor (`lo`), never the estimate: an estimate over the truth must not light an ability.
    it(
        "holds a press the estimate affords but the floor does not: hasRequiredResources, the wait, pct_lo, timeToLo",
        function()
            r.actual, r.actual_lo, r.actual_hi = 380, 360, 400
            S.forecastResources("mana")
            assert.is_false(H.ns.hasRequiredResources("surge"), "hasRequiredResources promoted on the estimate")
            local w = S:TimeToReady("surge")
            assert.is_true(w >= 0.26 and w <= 0.27, w)
            assert.is_true(r.pct_lo < r.pct)
            assert.are.equal(0, r.timeTo(370))
            assert.is_true(r.timeToLo(370) > 0.2, r.timeToLo(370))
        end
    )

    it("compiles a `.lo` or `.pct_lo` line's recheck to timeToLo", function()
        local Sc = H.Hekili.Scripts
        assert.is_truthy((Sc:BuildRecheck("mana.lo>=370") or ""):find("timeToLo", 1, true))
        assert.is_truthy((Sc:BuildRecheck("mana.pct_lo>=50") or ""):find("timeToLo", 1, true))
    end)
end)
