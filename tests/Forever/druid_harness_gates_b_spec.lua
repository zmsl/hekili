-- tests/Forever/druid_harness_gates_b_spec.lua: the Druid harness gates at the design's fight counts (#druid),
-- cat, regenAfter, shift, furor: half of them, so the halves run in their own processes (summed seconds near equal); split out
-- of druid_harness_spec.lua (test-speed plan, Task 4), which keeps the usability check and the #slow tenth.
local GATES = require("Forever.helpers.druid_harness_gates").GATES

describe("Druid harness scenarios at the design's fight counts (GCD kinds design §4.6) #druid", function()
    for _, name in ipairs({ "cat", "regenAfter", "shift", "furor" }) do
        it(name, function()
            GATES[name](1)
        end)
    end
end)
