-- src/Hekili_Paladin/APLs/packs.lua: the Forever Paladin's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua paladin): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Paladin.lua's generated
-- blocks, and `make packs` sets it to today only when a pack changed.
-- After wowsims/forever's Paladin APLs (ui/specs/paladin/retribution/apls/twist_of_light.apl.json and
-- holy_shock.apl.json, ui/specs/paladin/protection/apls/default.apl.json; MIT, reference only). Left out on purpose:
-- the item swap (D6), racials, potions and trinkets, a taunt (Hand of Reckoning is no player spell on Forever) and
-- Hammer of Wrath's swing sync (the 0.2 s after a main-hand swing).

return {
    class = "PALADIN",
    packs = { "Protection (wowsims.com)", "Retribution", "Protection" },
    specs = {
        ["Protection (wowsims.com)"] = "protection",
        Retribution = "retribution",
        Protection = "protection",
    },
}
