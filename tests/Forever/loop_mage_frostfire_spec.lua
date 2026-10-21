-- tests/Forever/loop_mage_frostfire_spec.lua: the Frostfire 20-fight gate (#mage), one pack a file so each runs in its own
-- process; loop_mage_spec.lua keeps the boot checks and the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.mage_world")

describe("the headless Mage gates, 20 fights a pack #mage", function()
    it("Frostfire solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Frostfire", w.Frostfire, 20)
        print("Frostfire focus ticks: " .. r.focus)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
