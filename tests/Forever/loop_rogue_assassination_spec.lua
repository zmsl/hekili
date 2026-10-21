-- tests/Forever/loop_rogue_assassination_spec.lua: the Assassination 20-fight gate (#rogue),
-- one spec a file so each runs in its own process; split out of loop_rogue_spec.lua, which keeps the boot checks and
-- the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.rogue_world")

describe("the headless Rogue gates, 20 fights a pack #rogue", function()
    it("Assassination solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Assassination", w.Assassination, 20)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
