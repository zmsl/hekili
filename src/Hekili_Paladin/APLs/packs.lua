-- src/Hekili_Paladin/APLs/packs.lua: the Forever Paladin's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua paladin): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Paladin.lua's generated
-- blocks, and `make packs` sets it to today only when a pack changed.
-- Both packs are translated from wowsims/forever (MIT, https://github.com/wowsims/forever) by tools/wowsims (recipes in
-- tools/wowsims/specs/paladin_*.lua): ui/specs/paladin/retribution/apls/twist_of_light.apl.json and
-- ui/specs/paladin/protection/apls/default.apl.json.

return {
    class = "PALADIN",
    packs = { "Retribution (wowsims.com)", "Protection (wowsims.com)" },
    specs = {
        ["Retribution (wowsims.com)"] = "retribution",
        ["Protection (wowsims.com)"] = "protection",
    },
}
