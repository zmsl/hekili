-- tests/Forever/loop_warlock_shadow_brand_spec.lua: the Shadow Brand gates, 3 fights (#slow, `make check`) and 20 (#warlock),
-- one pack a file so each runs in its own process; loop_warlock_spec.lua keeps the boot and world checks.
local pack_gate = require("Forever.helpers.pack_gate")
local w = require("Forever.helpers.warlock_world")

describe("the headless Warlock gates, 20 fights a pack #warlock", function()
    it("Shadow Brand solo, level 60, one mob, 20 fights of up to 3 minutes", function()
        local r, line = pack_gate.solo("Shadow Brand", w.ShadowBrand, 20)
        print("Shadow Brand focus ticks: " .. r.focus)
        assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
    end)
end)

describe("the headless Warlock gates, 3 fights a pack #slow", function()
    it(
        "Shadow Brand solo, level 60, one mob, 3 fights of up to 3 minutes: the first icon against the oracle's",
        function()
            local r, line = pack_gate.solo("Shadow Brand", w.ShadowBrand, 3, nil, "seeds 1-3")
            print("Shadow Brand focus ticks: " .. r.focus)
            assert.is_true(r.focus > 0, "no flagged line ran: " .. line)
        end
    )
end)
