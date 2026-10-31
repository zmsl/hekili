-- tests/Forever/loop_warrior_protection_spec.lua: the Protection (wowsims.com) 20-fight gate at level 60 (#loop; gap
-- CI; helpers/protection_gate.lua), its own file so it runs in its own process beside the Arms and Fury gates. Its
-- M.FLICKER label is "Warrior Protection" (the Paladin's is "Protection").
local pack_gate = require("Forever.helpers.pack_gate")
local pg = require("Forever.helpers.protection_gate")

describe("the headless Protection gates, 20 fights #loop", function()
    it(
        "Protection solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's",
        function()
            local r, line = pack_gate.solo("Warrior Protection", pg.content(), 20)
            assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
        end
    )
end)
