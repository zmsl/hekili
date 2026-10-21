-- tests/Forever/loop_warrior_fury_spec.lua: the Fury (wowsims.com) 20-fight gate at level 60 (#loop;
-- helpers/fury_gate.lua), one level a file so each runs in its own process.
local gate = require("Forever.helpers.fury_gate")

describe("the headless Fury gates, 20 fights #loop", function()
    it("Fury solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
        -- this branch's run (central fix 21): agreement 0.934, react p90 1, unmatched cost 1.6 per 100, flicker 1.71/min
        -- (oracle 0.56); before the fix 0.932, 1, 1.6, 2.09
        gate.solo(60, { agreement = 0.92, reactP90 = 1, unmatched = 2, flicker = 2 })
    end)
end)
