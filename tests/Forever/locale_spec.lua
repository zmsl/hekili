-- tests/Forever/locale_spec.lua (localization plan, Tasks 2-3; spec §1-§3): the string tables on AceLocale-3.0, on an
-- enUS client (fake_api's GetLocale): each key its own English, a key no table holds answering itself (silent).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("the string tables (headless Arms, an enUS client)", function()
    local H, AceLocale
    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        AceLocale = H.env.LibStub("AceLocale-3.0")
    end)

    it("make ns.L the core's AceLocale app, each key its own English, silent on any other", function()
        assert.are.equal(AceLocale:GetLocale("Hekili"), H.ns.L)
        assert.are.equal("Forecast window (s)", rawget(H.ns.L, "Forecast window (s)")) -- written by Locales/enUS.lua
        assert.are.equal("a key nobody wrote", H.ns.L["a key nobody wrote"])
        assert.is_nil(H.ns.Locale)
        assert.are.same({}, headless.unexpected(H, "load")) -- GAME_LOCALE, AceLocale's probe, is a known nil
    end)

    it("give each pack its own app, read through Hekili:GetLocale, holding none of the core's keys", function()
        local pack = AceLocale:GetLocale("Hekili_Warrior")
        assert.are.equal(pack, H.Hekili:GetLocale("Hekili_Warrior"))
        assert.are.equal("Arms", rawget(pack, "Arms"))
        assert.is_nil(rawget(H.ns.L, "Arms")) -- the core holds no pack string
        assert.is_nil(rawget(pack, "Forecast window (s)"))
        assert.is_nil(H.Hekili.L)
    end)
end)
