-- tests/Forever/loop_shaman_enhancement_spec.lua: the Shaman Enhancement 20-fight gate (#shaman), one pack a
-- file so each runs in its own process; split out of loop_shaman_spec.lua, which keeps the boot checks and the
-- 3-fight #slow gates.
local pack_gate = require("Forever.helpers.pack_gate")
local sw = require("Forever.helpers.shaman_world")

describe("the headless Shaman gates, 20 fights a pack #shaman", function()
    local name = "Enhancement"
    it(name .. " solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo(name, sw[name], 20)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)
