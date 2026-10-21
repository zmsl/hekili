-- tests/Forever/loop_paladin_protection_spec.lua: the Protection 20-fight gate (#paladin),
-- one spec a file so each runs in its own process; split out of loop_paladin_spec.lua, which keeps the boot checks and
-- the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.paladin_world")

describe("the headless Paladin gates, 20 fights a pack #paladin", function()
    -- central fix 22 round 2 (presses resolve from the current state, not Update's leftover prediction): agreement
    -- 0.972 -> 0.994, flicker 0.65 -> 0.31/min (oracle 0.02 -> 0.09), dps A/B 1.015 -> 0.989
    it("Protection solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Protection", w.Protection, 20)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
