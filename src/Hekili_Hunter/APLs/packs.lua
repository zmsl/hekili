-- src/Hekili_Hunter/APLs/packs.lua: the Forever Hunter's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua hunter): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Hunter.lua's generated
-- blocks, and `make packs` sets it to today only when a pack changed.
-- Each pack is generated from wowsims/forever's Melee Weave APL (ui/specs/hunter/dps/apls/default.apl.json; MIT) by
-- `make wowsims-packs` from its recipe in tools/wowsims/specs/.

return {
    class = "HUNTER",
    packs = { "Beast Mastery (wowsims.com)", "Marksmanship (wowsims.com)", "Survival (wowsims.com)" },
    specs = {
        ["Beast Mastery (wowsims.com)"] = "beast_mastery",
        ["Marksmanship (wowsims.com)"] = "marksmanship",
        ["Survival (wowsims.com)"] = "survival",
    },
}
