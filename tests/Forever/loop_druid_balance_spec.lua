-- tests/Forever/loop_druid_balance_spec.lua: the Balance 20-fight gate (#druid),
-- one spec a file so each runs in its own process; split out of loop_druid_spec.lua, which keeps the boot checks and
-- the 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.druid_loop_world")

describe("the headless Druid gates, 20 fights a pack #druid", function()
    it("Balance solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Balance", w.Balance, 20)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
