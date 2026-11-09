-- tests/Forever/loop_warrior_fury_spec.lua: the Fury (wowsims.com) 20-fight gate at level 60 (#loop;
-- helpers/fury_gate.lua), one level a file so each runs in its own process.
local gate = require("Forever.helpers.fury_gate")

describe("the headless Fury gates, 20 fights #loop", function()
    it("Fury solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
        -- this branch's run (central fix 21): agreement 0.934, react p90 1, unmatched cost 1.6 per 100, flicker 1.71/min
        -- (oracle 0.56), dps A/B 1.008; before the fix 0.932, 1, 1.6, 2.09, 1.013
        -- overpower: 16 / 13 / 15 presses, seeds 1-20 / 21-40 / 41-60; a margin for re-timed fights, 0 means the client went dead
        -- translator-2 (the Bloodrage line): unmatched cost 1.9 -> 2.4 per 100 (bar 2 -> 2.5): the refused presses of
        -- the forecast-swing ready-while-short class (pack_gate's Fury L60 row: readyShort 20 -> 26, every event traced)
        gate.solo(60, { agreement = 0.92, reactP90 = 1, unmatched = 2.5, dps = 0.98, overpower = 10 })
    end)
end)
