-- tests/Forever/loop_warrior_fury24_spec.lua: the Fury (wowsims.com) 20-fight gate at level 24 (#loop;
-- helpers/fury_gate.lua), one level a file so each runs in its own process.
local gate = require("Forever.helpers.fury_gate")

describe("the headless Fury gates, 20 fights #loop", function()
    it("Fury solo, level 24, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
        -- this branch's run (central fix 21): agreement 0.908, react p90 0, unmatched cost 1.2 per 100, flicker 3.31/min
        -- (oracle 2.16); before the fix 0.893, 0, 1.8, 4.35
        gate.solo(24, { agreement = 0.9, reactP90 = 0, unmatched = 1.5, flicker = 3.5 })
    end)
end)
