-- tests/Forever/loop_paladin_protection_spec.lua: the Protection 20-fight gate (#paladin),
-- one spec a file so each runs in its own process; split out of loop_paladin_spec.lua, which keeps the boot checks and
-- the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.paladin_world")

describe("the headless Paladin gates, 20 fights a pack #paladin", function()
    it("Protection solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Protection", w.Protection, 20)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
