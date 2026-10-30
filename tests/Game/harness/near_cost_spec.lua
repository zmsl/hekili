-- tests/Game/harness/near_cost_spec.lua (mana-regen plan, Task 4a): the sim marks an ability "near its cost" when
-- its resource alone holds it, the belief's estimate (the floor the sim reads plus estGap) reaches the cost within
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
        H.Hekili.combatRate = 0.2
    end)

    before_each(function()
        S.now, S.offset, S.delay = 100, 0, 0
        r.actual, r.max, r.regen, r.tick_rate, r.last_tick = 360, 10000, nil, 0, nil -- floor 360, continuous 38/s
        r.active_regen, r.inactive_regen, r.fsr_until = 38, 38, false
        r.estGap = 6 -- the estimate 366: 0.11 s from 370; the floor 0.26 s
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
            r.estGap = 0 -- the estimate is the floor: 0.26 s > EARLY_EXIT
            S.forecastResources("mana")
            S:TimeToReady("surge")
            assert.is_false(S.nearCost)
            r.actual, r.estGap = 340, 28 -- the estimate 368 (0.05 s), the floor 0.79 s away: past one update
            S.forecastResources("mana")
            S:TimeToReady("surge")
            assert.is_false(S.nearCost)
        end
    )

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
end)
