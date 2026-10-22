-- tests/Game/State/stats_spec.lua (owner ruling 2026-10-22): the running statistics, written once.
local load = require("Game.State.helpers.load")

describe("the running statistics", function()
    local Stats = load.module().VirtualStateInternal.Stats

    it("moves an EMA and its deviation, the spread never below the floor", function()
        local e, d, s = Stats.Ema(10, 1, 20, 0.1, 0.5)
        assert.are.equal(11, e)
        assert.is_true(math.abs(d - (1 + 0.1 * (9 - 1))) < 1e-12)
        assert.are.equal(d, s)
        assert.are.same({ 10, 0, 0.5 }, { Stats.Ema(10, 0, 10, 0.1, 0.5) })
    end)

    it("keeps the swing lag's sign-step median exactly as Rows learned it", function()
        local function old(med, spr, d, w) -- Rows.lua:272-279 before Task 5, verbatim
            med = med + 0.005 * (d > med and 1 or -1)
            local s = spr + 0.05 * (1.2533 * math.abs(d - med) - spr)
            spr = s < 0.02 and 0.02 or (s > 0.4 and 0.4 or s)
            med = med < 0 and 0 or (med > w and w or med)
            return med, spr
        end
        local m1, s1, m2, s2, x = 0.474, 0.06, 0.474, 0.06, 1
        for _ = 1, 500 do
            x = (x * 16807) % 2147483647
            local d = 0.2 + (x % 1000) / 1000
            m1, s1 = old(m1, s1, d, 1.5)
            m2, s2 = Stats.Median(m2, s2, d, 0.005, 0, 1.5)
            assert.are.same({ m1, s1 }, { m2, s2 })
        end
    end)

    it("clamps", function()
        assert.are.same(
            { 0.02, 0.4, 0.3 },
            { Stats.Clamp(0.01, 0.02, 0.4), Stats.Clamp(9, 0.02, 0.4), Stats.Clamp(0.3, 0.02, 0.4) }
        )
    end)
end)
