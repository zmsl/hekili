-- tests/Forever/options_import_spec.lua (audit items 5, 19, 4): the priority and style import boxes, driven through the
-- options tree. A broken or wrong-kind string shows its message in the box and stays on stage 0 (Options.lua).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local PREFIX = "The Import String provided could not be decompressed.\n"

local function boot()
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    assert.are.same({}, H.loadErrors)
    H.Hekili:EmbedDisplayOptions()
    H.Hekili:EmbedPackOptions()
    return H
end

-- the import groups (stage0, stage1, ...) of the priority and the style share panels
local function boxes(H)
    local O = H.Hekili.Options.args
    return O.packs.args.sharePacks.args.import.args, O.displays.args.shareDisplays.args.import.args
end

-- the style export string for display `name`, as the Export tab makes it
local function exportStyle(H, name)
    H.Hekili:SetDisplayShareOption({ name }, true)
    local ex = H.Hekili.Options.args.displays.args.shareDisplays.args.export.args
    ex.stage0.args.exportBtn.func()
    return ex.stage1.args.exportString.get()
end

-- paste `s`, click Import; returns what the box shows
local function import(box, s)
    box.stage0.args.importString.set(nil, s)
    box.stage0.args.importBtn.func()
    return box.stage0.args.importString.get()
end

local function refused(box, s, msg)
    local shown = import(box, s)
    assert.are.equal(PREFIX, shown:sub(1, #PREFIX))
    if msg then
        assert.are.equal(PREFIX .. msg, shown)
    else
        assert.is_true(#shown > #PREFIX)
    end
    assert.is_false(box.stage0.hidden())
    assert.is_true(box.stage1.hidden())
end

describe("the import boxes", function()
    local H, packBox, styleBox, packString, styleString

    setup(function()
        H = boot()
        packBox, styleBox = boxes(H)
        packString = H.Hekili.SerializeActionPack(next(H.Hekili.DB.profile.packs))
        styleString = exportStyle(H, "Primary")
        assert.are.equal("Hekili:", packString:sub(1, 7))
        assert.are.equal("Hekili:", styleString:sub(1, 7))
    end)

    it("take their own kind to stage 1", function()
        import(packBox, packString)
        assert.is_true(packBox.stage0.hidden())
        assert.is_false(packBox.stage1.hidden())
        packBox.stage1.args.reset.func()
        import(styleBox, styleString)
        assert.is_true(styleBox.stage0.hidden())
        assert.is_false(styleBox.stage1.hidden())
        styleBox.stage1.args.reset.func()
    end)

    it("garbage in either box: the message, stage 0 stays", function()
        for _, s in ipairs({ "garbage", "Hekili:garbage" }) do
            refused(packBox, s)
            refused(styleBox, s)
        end
    end)

    it("a string without the Hekili: prefix (the removed legacy format): the decode message", function()
        refused(packBox, packString:sub(8), "Unable to decode.")
        refused(styleBox, styleString:sub(8), "Unable to decode.")
    end)

    it("a style string in the priority box: the priority message", function()
        refused(packBox, styleString, "Unable to restore Priority from the provided string.")
    end)

    it("a priority string in the style box: the style message", function()
        refused(styleBox, packString, "Unable to restore Style from the provided string.")
    end)
end)

-- Audit item 4: Apply Changes assigns the imported tables raw, so AceDB's `**` defaults miss them; an older export
-- (no truth/timeline/classic subtables) must still build once applied.
describe("the style import's Apply Changes", function()
    it("fills the defaults an older export lacks, so the display builds", function()
        local H = boot()
        local p = H.Hekili.DB.profile
        local saved = p.displays.Primary
        p.displays.Primary = { enabled = true, numIcons = 3, x = 0, y = -225 }
        local old = exportStyle(H, "Primary")
        p.displays.Primary = saved

        local _, styleBox = boxes(H)
        import(styleBox, old)
        styleBox.stage1.args.apply.func()

        assert.has_no.errors(function()
            H.Hekili:BuildUI()
        end)
        assert.is_table(H.Hekili.DB.profile.displays.Primary.truth)
        assert.is_table(H.Hekili.DB.profile.displays.Primary.classic)
    end)
end)
