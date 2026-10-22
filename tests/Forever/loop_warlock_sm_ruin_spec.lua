-- tests/Forever/loop_warlock_sm_ruin_spec.lua: the SM Ruin 20-fight gate (#warlock), one pack a file so each runs in its
-- own process; loop_warlock_spec.lua keeps the boot checks and the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.warlock_world")

describe("the headless Warlock gates, 20 fights a pack #warlock", function()
    it("SM Ruin solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("SM Ruin", w.SMRuin, 20)
        print("SM Ruin focus ticks: " .. r.focus)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
