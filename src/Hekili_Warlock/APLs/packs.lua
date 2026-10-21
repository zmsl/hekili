-- src/Hekili_Warlock/APLs/packs.lua: the Forever Warlock's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua warlock): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Warlock.lua's generated
-- blocks, and `make packs` sets it to today only when a pack changed.
-- Each pack is generated from wowsims/forever's builds (ui/specs/warlock/dps/builds/*.build.json; MIT) by
-- `make wowsims-packs` from its recipe in tools/wowsims/specs/.

return {
    class = "WARLOCK",
    packs = {
        "Affliction (wowsims.com)",
        "Demonology (wowsims.com)",
        "Destruction (wowsims.com)",
        "SM Ruin (wowsims.com)",
        "Shadow Brand (wowsims.com)",
    },
    specs = {
        ["Affliction (wowsims.com)"] = "affliction",
        ["Demonology (wowsims.com)"] = "demonology",
        ["Destruction (wowsims.com)"] = "destruction",
        -- the sm_ruin build is 30 Affliction points to 21 Destruction: our active spec is the tree with the most points
        ["SM Ruin (wowsims.com)"] = "affliction",
        -- the demo_shadow_brand build is 31 Demonology points to 18 Destruction and 2 Affliction
        ["Shadow Brand (wowsims.com)"] = "demonology",
    },
}
