-- tests/Forever/loop_druid_guardian_spec.lua: the Guardian 20-fight gate (#druid),
-- one spec a file so each runs in its own process; split out of loop_druid_spec.lua, which keeps the boot checks and
-- the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.druid_loop_world")

describe("the headless Druid gates, 20 fights a pack #druid", function()
    it("Guardian solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        -- reported, not gated: loop_druid_spec.lua's REPORTED
        local r, line = pack_gate.solo("Guardian", w.Guardian, 20, nil, nil, true)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
