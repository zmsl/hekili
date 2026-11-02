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

    it("a string without the Hekili: prefix (the removed legacy format): the decode message", function()
        assert.are.same({ nil, "Unable to decode." }, { H.Hekili.DeserializeActionPack(packString:sub(8)) })
        assert.are.same({ nil, "Unable to decode." }, { H.Hekili.DeserializeStyle(styleString:sub(8)) })
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

-- Audit item 4: Apply Changes assigns the imported tables raw, so AceDB's `**` defaults miss them; an older export
-- (no truth/timeline/classic subtables) must still build once applied.
describe("the style import's Apply Changes", function()
    it("fills the defaults an older export lacks, so the display builds", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local p = H.Hekili.DB.profile
        local saved = p.displays.Primary
        p.displays.Primary = { enabled = true, numIcons = 3, x = 0, y = -225 }
        local old = H.Hekili.SerializeStyle("Primary")
        p.displays.Primary = saved

        H.Hekili:EmbedDisplayOptions()
        local import = H.Hekili.Options.args.displays.args.shareDisplays.args.import.args
        import.stage0.args.importString.set(nil, old)
        import.stage0.args.importBtn.func()
        import.stage1.args.apply.func()

        assert.has_no.errors(function()
            H.Hekili:BuildUI()
        end)
        assert.is_table(H.Hekili.DB.profile.displays.Primary.truth)
        assert.is_table(H.Hekili.DB.profile.displays.Primary.classic)
    end)
end)
