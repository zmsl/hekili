-- tests/Forever/editor_labels_spec.lua: the action editor's label, label_if, icon and icon_if fields set, read back
-- and clear the line's modifiers, and the saved line's compiled script carries or drops them.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("action editor label and icon fields", function()
    local H, entry, scriptID
    local function info(opt)
        return { "packs", ww.PACK, "lists", "entry", opt }
    end
    local function mods()
        return H.Hekili.Scripts.DB[scriptID].Modifiers or {}
    end

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        entry = H.Hekili.DB.profile.packs[ww.PACK].lists.default[1]
        scriptID = ww.PACK .. ":default:1"
    end)

    for opt, val in pairs({ label = "R6", label_if = "time>=0", icon = "136006", icon_if = "time>=0" }) do
        it("sets, reads back and clears " .. opt, function()
            H.Hekili:SetActionOption(info(opt), val)
            assert.are.equal(val, H.Hekili:GetActionOption(info(opt)))
            assert.is_function(mods()[opt])
            for _, blank in ipairs({ "", "  " }) do
                H.Hekili:SetActionOption(info(opt), val)
                H.Hekili:SetActionOption(info(opt), blank)
                assert.is_nil(entry[opt])
                assert.is_nil(mods()[opt])
            end
            assert.are.same({}, H.errors)
        end)
    end

    it("exports the four fields with the pack", function()
        for opt, val in pairs({ label = "R6", label_if = "time>=0", icon = "136006", icon_if = "time>=0" }) do
            H.Hekili:SetActionOption(info(opt), val)
        end
        local serial = H.Hekili.DeserializeActionPack(H.Hekili.SerializeActionPack(ww.PACK))
        local e = serial.payload.lists.default[1]
        assert.are.same({ "R6", "time>=0", "136006", "time>=0" }, { e.label, e.label_if, e.icon, e.icon_if })
    end)

    it("warns once for an icon path the client lacks, and gives no override", function()
        H.Hekili:SetActionOption(info("icon"), "Interface\\Icons\\Spell_Nature_StarFall")
        assert.is_function(mods().icon) -- the fake client resolves any path
        H.ctl.fileIDs = { ["Interface\\Nope\\Missing"] = false }
        H.Hekili:SetActionOption(info("icon"), "Interface\\Nope\\Missing")
        assert.is_nil(mods().icon)
        assert.are.equal(1, #H.errors)
        assert.is_truthy(tostring(H.errors[1]):find("is not a texture file", 1, true))
    end)
end)
