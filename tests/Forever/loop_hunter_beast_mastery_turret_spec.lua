-- tests/Forever/loop_hunter_beast_mastery_turret_spec.lua: the Beast Mastery Turret 20-fight gate (#hunter), one spec a
-- file so each runs in its own process (loop_hunter_spec.lua keeps the boot checks and the 3-fight #slow gates).
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.hunter_world")

describe("the headless Hunter gates, 20 fights a pack #hunter", function()
    it("Beast Mastery Turret solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Beast Mastery Turret", w.BeastMasteryTurret, 20)
        print("Beast Mastery Turret focus ticks: " .. r.focus)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
