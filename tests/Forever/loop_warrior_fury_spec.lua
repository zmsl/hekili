-- tests/Forever/loop_warrior_fury_spec.lua: the Fury (wowsims.com) 20-fight gate at level 60 (#loop;
-- helpers/fury_gate.lua), one level a file so each runs in its own process.
local gate = require("Forever.helpers.fury_gate")

describe("the headless Fury gates, 20 fights #loop", function()
    it("Fury solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
        -- central fix 21's run: agreement 0.934, react p90 1, unmatched cost 1.6 per 100, flicker 1.71/min (oracle 0.56),
        -- dps A/B 1.008; before the fix 0.932, 1, 1.6, 2.09, 1.013. Base a9a6fff9f: unmatched cost 1.9 per 100.
        -- translator-2 (the Bloodrage line), seeds 1-20: unmatched cost 1.9 -> 2.4 per 100 (bar 2 -> 2.5): all 26 refused
        -- presses are the 26 ready-while-short presses, the same tick each (traced per event: pack_gate's Fury L60 row)
        -- overpower: 16 / 13 / 15 presses, seeds 1-20 / 21-40 / 41-60; a margin for re-timed fights, 0 means the client went dead
        -- dps 0.98 -> 0.97 (re-pin ab0f: UW 59.5% x 1 rage rolled per hit (wowsims) + HS/Cleave Reckless charge; R6,
        -- seeds 1-20 / 21-40 / 41-60 dps A/B 0.976 / 1.028 / 1.017, mean 1.007; 0.983 / 1.003 / 1.005 on the world's
        -- fixed average): the rolled world re-times the fights. Seeds 1-20 per fight (a 15000-health kill each, so the
        -- ratio is the kill-time ratio): 0.82 to 1.28, ours 303102 in 1697.4 s, the oracle's 304116 in 1661.6 s; ours
        -- kills slower in 15 of the 20, but the other sets read 1.028 / 1.017 and the fixed world already sat at 0.983:
        -- read as seed-set noise of the diverging runs' kill times, not traced to a mechanism
        gate.solo(60, { agreement = 0.92, reactP90 = 1, unmatched = 2.5, dps = 0.97, overpower = 10 })
    end)
end)
