-- tests/Forever/loop_warrior_late_spec.lua: fights 4-6 of `make check`'s 6-fight Arms gate (fights 1-3 and the rest of
-- the headless Arms loop: loop_warrior_spec.lua), its own file so the two halves run in parallel.
local gate = require("Forever.helpers.arms_gate")

describe("the headless Arms gates, fights 4-6 #slow", function()
    it("Arms solo, level 60, one mob, fights 4-6 of up to 3 minutes: the first icon against the oracle's", function()
        local r, line = gate.solo(3, 3, "seeds 4-6")
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line) -- review focus 5
    end)
end)
