-- tests/Forever/loop_truth_spec.lua (central fix 22, round 1): a press resolves from the instance whose state is true
-- for the run: the oracle when it is driven (loop.fight), else the driving instance (ws.live drives ours alone and
-- never steps the oracle, whose state then stays at its boot).
local loop = require("Game.harness.loop")
local ww = require("Forever.helpers.warrior_world")

describe("the loop's truth instance", function()
    local seen
    local C = setmetatable({
        resolve = function(key, H)
            seen.resolve[H] = true
            return ww.resolve(key, H)
        end,
    }, { __index = ww })
    local L

    setup(function()
        seen = { resolve = {} }
        L = loop.new(C)
    end)

    it("resolves from the driver when the oracle is not driven", function()
        seen = { resolve = {} }
        local run = loop.run(L, 1, { duration = 15 }, { { H = L.us } })
        assert.is_true(run.presses > 0)
        assert.are.same({ [L.us] = true }, seen.resolve)
    end)

    it("resolves from the oracle when it is driven", function()
        seen = { resolve = {} }
        local run = loop.run(L, 1, { duration = 15 }, { { H = L.us }, { H = L.oracle, plain = true } })
        assert.is_true(run.presses > 0)
        assert.are.same({ [L.oracle] = true }, seen.resolve)
    end)
end)
