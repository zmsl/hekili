-- tests/Forever/loop_priest_smite_spec.lua: the Smite 20-fight gate (#priest), one pack a file so each runs in its own
-- process; loop_priest_spec.lua keeps the boot checks and the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.priest_world")

describe("the headless Priest gates, 20 fights a pack #priest", function()
    it("Smite solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Smite", w.Smite, 20)
        print("Smite focus ticks: " .. r.focus)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
