-- src/Hekili_Hunter/APLs/packs.lua: the Forever Hunter's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua hunter): the class token, the packs in RegisterPack order (each one's text in <Pack>.simc beside
-- this file) and each pack's spec key. Dev-only (no TOC lists it); the pack date lives in Hunter.lua's generated
-- blocks, and `make packs` sets it to today only when a pack changed.
-- After wowsims/forever's Hunter APLs (ui/specs/hunter/dps/apls/turret_hawk.apl.json, turret.apl.json and
-- melee.apl.json; MIT, reference only), D3. Left out on purpose: the melee weave (D3), the auto-shot weave (D5: shots
-- without weaving), pet-bar abilities and Bestial Wrath (D6), traps (a placement decision, research §6), Aspect of the
-- Viper (a rune, research Q9/Q10), racials, potions and trinkets.

return {
    class = "HUNTER",
    packs = {
        "Beast Mastery (wowsims.com)",
        "Marksmanship (wowsims.com)",
        "Survival (wowsims.com)",
        "BeastMastery",
        "Marksmanship",
        "Survival",
    },
    specs = {
        ["Beast Mastery (wowsims.com)"] = "beast_mastery",
        ["Marksmanship (wowsims.com)"] = "marksmanship",
        ["Survival (wowsims.com)"] = "survival",
        BeastMastery = "beast_mastery",
        Marksmanship = "marksmanship",
        Survival = "survival",
    },
}
