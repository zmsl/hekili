-- tests/Forever/focus_tier_options_spec.lua (Fury plan, Task 3b): the in-game importer and the priority editor read,
-- keep and edit focus=N tiers (1 highest; 0 or blank is off).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    assert(headless.cycle(H, H.ctl.now + 0.2))
    return H
end

describe("focus tiers in the options", function()
    it("the importer keeps any positive integer tier, drops 0, and warns on a value that is not a tier", function()
        local H = boot()
        local list, warnings = H.Hekili:ParseActionList(
            "actions+=/slam,focus=1\nactions+=/rend,focus=3\nactions+=/whirlwind,focus=0\n"
                .. "actions+=/overpower,focus=yes\nactions+=/cleave,focus=1.5\n"
        )
        assert.are.same({ 1, 3 }, { list[1].focus, list[2].focus })
        assert.is_nil(list[3].focus)
        assert.is_nil(list[4].focus)
        assert.is_nil(list[5].focus)
        local text = table.concat(warnings or {}, "\n")
        assert.truthy(text:find("Line 4: focus=yes is not a tier", 1, true))
        assert.truthy(text:find("Line 5: focus=1.5 is not a tier", 1, true))
        assert.is_nil(text:find("Line 3: focus", 1, true))
    end)

    it("the editor shows the entry's tier (0 when off) and stores 1.. as the tier, 0 as off", function()
        local H = boot()
        local pack = ww.PACK
        local entry = H.Hekili.DB.profile.packs[pack].lists.default[1]
        local info = { "packs", pack, "lists", "entry", "modAsyncUsage", "focus" }
        entry.focus = nil
        assert.are.equal(0, H.Hekili:GetActionOption(info))
        H.Hekili:SetActionOption(info, 2)
        assert.are.equal(2, entry.focus)
        assert.are.equal(2, H.Hekili:GetActionOption(info))
        H.Hekili:SetActionOption(info, 0)
        assert.is_nil(entry.focus)
        assert.are.same({}, H.errors)
    end)
end)
