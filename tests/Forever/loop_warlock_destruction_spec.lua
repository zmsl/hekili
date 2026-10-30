-- tests/Forever/loop_warlock_destruction_spec.lua: the Destruction gates, 3 fights (#slow, `make check`) and 20 (#warlock),
-- one pack a file so each runs in its own process; loop_warlock_spec.lua keeps the boot and world checks.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.warlock_world")

describe("the headless Warlock gates, 20 fights a pack #warlock", function()
    it("Destruction solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Destruction", w.Destruction, 20)
        print("Destruction focus ticks: " .. r.focus)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)

describe("the headless Warlock gates, 3 fights a pack #slow", function()
    it(
        "Destruction solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
        function()
            local r, line = pack_gate.solo("Destruction", w.Destruction, 3, nil, "seeds 1-3")
            print("Destruction focus ticks: " .. r.focus)
            assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
        end
    )
end)
