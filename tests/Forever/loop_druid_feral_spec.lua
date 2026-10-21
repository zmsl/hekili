-- tests/Forever/loop_druid_feral_spec.lua: the Feral 20-fight gate (#druid),
-- one spec a file so each runs in its own process; split out of loop_druid_spec.lua, which keeps the boot checks and
-- the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.druid_loop_world")

describe("the headless Druid gates, 20 fights a pack #druid", function()
    -- central fix 22 round 2 (presses resolve from the current state, not Update's leftover prediction): agreement
    -- 0.942 -> 0.941, flicker 1.70 -> 2.12/min (oracle 1.52 -> 1.72), dps A/B 0.998 -> 1.024
    it("Feral solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Feral", w.Feral, 20)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
