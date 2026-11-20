-- tests/Forever/entry_editor_layout_spec.lua: the Action Lists entry editor puts Condition (Description, Conditions)
-- before Display (Caption, Label, Icon), and the Summary tab's copy button shows the note's WhiteCopy texture.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

-- the args of the first table under `t` whose args hold every key in `keys`
local function findArgs(t, keys, seen)
    seen = seen or {}
    if type(t) ~= "table" or seen[t] then
        return nil
    end
    seen[t] = true
    if t.args then
        local ok = true
        for _, k in ipairs(keys) do
            ok = ok and t.args[k] ~= nil
        end
        if ok then
            return t.args
        end
    end
    for _, v in pairs(t) do
        local f = findArgs(v, keys, seen)
        if f then
            return f
        end
    end
end

describe("the priority editor layout", function()
    local packs
    setup(function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        H.Hekili:EmbedPackOptions()
        packs = H.Hekili.Options.args.packs.plugins.packages[ww.PACK]
    end)

    it("orders the entry editor Condition, then Display", function()
        local a = assert(findArgs(packs, { "criteria", "caption", "condHeader", "displayHeader" }))
        local function o(k)
            return a[k].order
        end
        assert.are.equal("header", a.condHeader.type)
        assert.are.equal("header", a.displayHeader.type)
        assert.is_true(o("action") < o("condHeader"))
        local prev = o("condHeader")
        for _, k in ipairs({ "description", "var_name", "op", "modPooling", "criteria", "value", "value_else" }) do
            assert.is_true(o(k) > prev, k)
            prev = o(k)
        end
        assert.is_true(o("displayHeader") > prev)
        prev = o("displayHeader")
        for _, k in ipairs({ "caption", "label", "label_if", "icon", "iconPreview", "icon_if" }) do
            assert.is_true(o(k) > prev, k)
            prev = o(k)
        end
        assert.is_true(o("showModifiers") > prev)
    end)

    it("shows the note's copy texture on the Copy Priority button", function()
        local a = assert(findArgs(packs, { "copyPack" }))
        assert.are.equal("Interface\\Addons\\Hekili\\Textures\\WhiteCopy", a.copyPack.image)
        assert.is_nil(a.copyPack.imageCoords)
    end)
end)
