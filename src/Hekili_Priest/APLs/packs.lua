-- src/Hekili_Priest/APLs/packs.lua: the Forever Priest's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua priest): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Priest.lua's generated
-- blocks, and `make packs` sets it to today only when a pack changed.
-- Each pack is generated from wowsims/forever's Priest builds (ui/specs/priest/dps/builds/*.build.json; MIT) by
-- `make wowsims-packs` from its recipe in tools/wowsims/specs/.

return {
    class = "PRIEST",
    packs = { "Shadow (wowsims.com)", "Smite (wowsims.com)" },
    specs = {
        ["Shadow (wowsims.com)"] = "shadow",
        -- the Smite build (525235031030001001-30515100002-3) is 31 Discipline points: our active spec is the tree with
        -- the most points (owner ruling P4: Holy stays unsupported)
        ["Smite (wowsims.com)"] = "discipline",
    },
}
