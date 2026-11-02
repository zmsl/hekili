-- tests/Forever/loop_warrior_fury24_spec.lua: the Fury (wowsims.com) 20-fight gate at level 24 (#loop;
-- helpers/fury_gate.lua), one level a file so each runs in its own process.
local gate = require("Forever.helpers.fury_gate")

describe("the headless Fury gates, 20 fights #loop", function()
    it("Fury solo, level 24, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
        -- this branch's run (central fix 21): agreement 0.908, react p90 0, unmatched cost 1.2 per 100, flicker 3.31/min
        -- (oracle 2.16), dps A/B 0.972; before the fix 0.893, 0, 1.8, 4.35, 1.006
        -- unmatched 1.5 -> 0.9, flicker 3.5 -> 1.1 (the world's off hand by rank, pack_gate.lua's Fury L24 row; seeds 1-20 /
        -- 21-40 / 41-60: agreement .930 / .944 / .918, react p90 0 / 1 / 1, unmatched 0.7 / 0.4 / 0.8, flicker 0.86 / 1.08
        -- / 0.98, dps A/B 0.985 / 1.000 / 1.004)
        -- overpower: 76-104 presses over 12 seed sets; a margin for re-timed fights, 0 means the client went dead
        gate.solo(24, { agreement = 0.9, reactP90 = 0, unmatched = 0.9, flicker = 1.1, dps = 0.95, overpower = 60 })
    end)
end)
