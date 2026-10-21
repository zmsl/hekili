-- src/Hekili_Mage/APLs/packs.lua: the Forever Mage's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua mage): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Mage.lua's generated
-- blocks, and `make packs` sets it to today only when a pack changed.
-- Each pack is generated from wowsims/forever's APL (ui/specs/mage/dps/apls/*.apl.json; MIT) by `make wowsims-packs`
-- from its recipe in tools/wowsims/specs/.

return {
    class = "MAGE",
    packs = { "Arcane (wowsims.com)", "Fire (wowsims.com)" },
    specs = {
        ["Arcane (wowsims.com)"] = "arcane",
        ["Fire (wowsims.com)"] = "fire",
    },
}
