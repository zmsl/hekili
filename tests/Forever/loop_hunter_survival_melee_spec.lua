-- tests/Forever/loop_hunter_survival_melee_spec.lua: the Survival Melee 20-fight gate (#hunter), one spec a file so
-- each runs in its own process (loop_hunter_spec.lua keeps the boot checks and the 3-fight #slow gates).
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.hunter_world")

describe("the headless Hunter gates, 20 fights a pack #hunter", function()
    it("Survival Melee solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Survival Melee", w.SurvivalMelee, 20)
        print("Survival Melee focus ticks: " .. r.focus)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
