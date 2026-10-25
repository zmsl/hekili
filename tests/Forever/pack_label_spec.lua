-- tests/Forever/pack_label_spec.lua (localization plan, Task 6; spec §5b): a built-in priority keeps its name as the
-- key everywhere it is stored or typed and shows a label from its pack's string table; any other priority shows its
-- name. The label below stands in for a translation (a language file sets it the same way).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

-- The option node at `path` (AceConfig merges a group's plugins into its args).
local function node(t, ...)
    for _, k in ipairs({ ... }) do
        local n = t.args and t.args[k]
        for _, group in pairs(n == nil and t.plugins or {}) do
            n = n or group[k]
        end
        t = assert(n, k)
    end
    return t
end

describe("priority labels (headless Arms)", function()
    local H, hk, Registry, labels
    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        hk = H.Hekili
        Registry = hk.Engine.Registry
        labels = H.env.LibStub("AceLocale-3.0"):GetLocale("Hekili_Warrior")
    end)

    it("shows a built-in priority's label from its pack's table, the name itself otherwise", function()
        assert.are.equal(ww.PACK, Registry.PackLabel(ww.PACK)) -- enUS: no entry, the key
        rawset(labels, ww.PACK, "Waffen (wowsims.com)") -- as a language file sets it
        assert.are.equal("Waffen (wowsims.com)", Registry.PackLabel(ww.PACK))
        assert.are.equal("Mine", Registry.PackLabel("Mine")) -- a player's own
        assert.are.equal("Arms", Registry.PackLabel("Arms")) -- retired (spec:RetirePacks): not registered
    end)

    it("labels the priority in the spec page's dropdown, the pack tree and the share list; keys stay names", function()
        rawset(labels, ww.PACK, "Waffen (wowsims.com)")
        hk:RefreshOptions()
        local values = node(hk.Options, "packs", "arms", "core", "package").values()
        assert.is_truthy(values[ww.PACK]:find("Waffen (wowsims.com)", 1, true))
        assert.is_truthy(node(hk.Options, "packs", "arms", ww.PACK).name():find("Waffen (wowsims.com)", 1, true))
        assert.are.equal(
            "Waffen (wowsims.com)",
            node(hk.Options, "packs", "sharePacks", "export", "actionPack").values()[ww.PACK]
        )
        assert.are.equal(ww.PACK, hk.DB.profile.specs[100011].package)
    end)

    it("names the updated priority by its label in RestoreDefaults' notice", function()
        rawset(labels, ww.PACK, "Waffen (wowsims.com)")
        local said = {}
        hk.Print = function(_, s)
            said[#said + 1] = s
        end
        hk.Notify = hk.Print
        rawget(hk.DB.profile.packs, ww.PACK).version = 0 -- older than the shipped one: decoded again, "updated"
        hk:RestoreDefaults()
        H.ctl.now = H.ctl.now + 10
        H.RunTimers(H.ctl.now)
        assert.are.equal("The |cFFFFD100Waffen (wowsims.com)|r priority was updated.", said[#said])
    end)
end)
