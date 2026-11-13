-- tests/Forever/caption_clear_spec.lua: clearing an action's Caption in the editor removes it without an error.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("action caption option", function()
    local function setup()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        local entry = H.Hekili.DB.profile.packs[ww.PACK].lists.default[1]
        return H, entry, { "packs", ww.PACK, "lists", "entry", "caption" }
    end

    it("removes the caption on an empty or whitespace value", function()
        local H, entry, info = setup()
        for _, blank in ipairs({ "", "   " }) do
            entry.caption = "x"
            H.Hekili:SetActionOption(info, blank)
            assert.is_nil(entry.caption)
        end
        assert.are.same({}, H.errors)
    end)

    it("still turns a doubled pipe into one", function()
        local H, entry, info = setup()
        H.Hekili:SetActionOption(info, "a||b")
        assert.are.equal("a|b", entry.caption)
    end)
end)
