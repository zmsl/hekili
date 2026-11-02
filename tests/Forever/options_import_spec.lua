-- tests/Forever/options_import_spec.lua (audit item 5): the priority and style import boxes refuse a broken or
-- wrong-kind string with `nil, message`; the Import button shows the message and stops (Options.lua).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the import boxes", function()
    local H, packString, styleString

    setup(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local name = next(H.Hekili.DB.profile.packs)
        packString = H.Hekili.SerializeActionPack(name)
        styleString = H.Hekili.SerializeStyle("Primary")
        assert.is_string(packString)
        assert.is_string(styleString)
    end)

    it("reads back their own kind", function()
        assert.are.equal("package", H.Hekili.DeserializeActionPack(packString).type)
        assert.is_table(H.Hekili.DeserializeStyle(styleString).Primary)
    end)

    it("garbage in either box: nil plus a message", function()
        for _, s in ipairs({ "garbage", "Hekili:garbage" }) do
            local a, b = H.Hekili.DeserializeActionPack(s)
            assert.is_nil(a)
            assert.is_string(b)
            a, b = H.Hekili.DeserializeStyle(s)
            assert.is_nil(a)
            assert.is_string(b)
        end
    end)

    it("a style string in the priority box: nil plus a message", function()
        local a, b = H.Hekili.DeserializeActionPack(styleString)
        assert.is_nil(a)
        assert.is_string(b)
    end)

    it("a priority string in the style box: nil plus a message", function()
        local a, b = H.Hekili.DeserializeStyle(packString)
        assert.is_nil(a)
        assert.is_string(b)
    end)
end)
