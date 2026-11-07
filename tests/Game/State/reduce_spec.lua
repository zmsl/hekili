-- tests/Game/State/reduce_spec.lua (cdm-default spec §2.3, decision 94): I.ReduceFact, one row per case of the table,
-- totality included, and no allocation.
local load = require("Game.State.helpers.load")
local alloc = require("Game.State.helpers.alloc")

describe("I.ReduceFact (cdm-default spec §2.3)", function()
    local I
    before_each(function()
        I = load.module().VirtualStateInternal
    end)
    -- nLive, nUp, nNone, nStale, tUp, tNone -> state, agree
    local ROWS = {
        { "no item anywhere", 0, 0, 0, 0, 0, 0, "UNDECIDED", true },
        { "no item, only stale", 0, 0, 0, 2, 0, 0, "UNDECIDED", true },
        { "no live, stray counts (nLive == 0 wins)", 0, 1, 1, 0, 5, 5, "UNDECIDED", true },
        { "live but no answer (totality)", 1, 0, 0, 0, 0, 0, "UNDECIDED", true },
        { "one item up", 1, 1, 0, 0, 5, 0, "UP", true },
        { "two items up", 2, 2, 0, 0, 5, 0, "UP", true },
        { "one item none", 1, 0, 1, 0, 0, 5, "DOWN", true },
        { "all none, one stale", 2, 0, 1, 1, 0, 5, "UNDECIDED", true },
        { "up and none, up fresher", 2, 1, 1, 0, 6, 5, "UP", false },
        { "up and none, same time", 2, 1, 1, 0, 5, 5, "UP", false },
        { "up and none, none fresher", 2, 1, 1, 0, 5, 6, "UNDECIDED", false },
        { "up with a stale peer", 2, 1, 0, 1, 5, 0, "UP", true },
    }
    for _, r in ipairs(ROWS) do
        it(r[1], function()
            local s, a = I.ReduceFact(r[2], r[3], r[4], r[5], r[6], r[7])
            assert.are.equal(I[r[8]], s)
            assert.are.equal(r[9], a)
        end)
    end
    it("allocates nothing", function()
        local Reduce = I.ReduceFact
        local bytes = alloc.bytes(function(i)
            local m = i % 4 -- every branch: none, up, down, mixed
            Reduce(m, m % 2, m > 1 and 1 or 0, 0, i, 5)
        end, 1e4)
        assert.are.equal(0, bytes)
    end)
end)
