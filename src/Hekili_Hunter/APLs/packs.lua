-- src/Hekili_Hunter/APLs/packs.lua: the Forever Hunter's pack manifest for tools/make_pack.lua (lua5.1
-- tools/make_pack.lua hunter): the pseudo-spec (Hekili_Hunter/Hunter.lua's HUNTER_SPEC: 1484, Forever's alphabetical
-- pattern, to be confirmed at the Hunter checkpoint; run `make packs` when it changes) and the packs in RegisterPack
-- order, each one's text in <Pack>.simc beside this file. Dev-only (no TOC lists it); the pack date lives in
-- Hunter.lua's generated blocks, and `make packs` sets it to today only when a pack changed.
-- After wowsims/forever's Hunter APLs (ui/specs/hunter/dps/apls/turret_hawk.apl.json, turret.apl.json and
-- melee.apl.json; MIT, reference only), D3. Left out on purpose: the melee weave (D3), the auto-shot weave (D5: shots
-- without weaving), pet-bar abilities and Bestial Wrath (D6), traps (a placement decision, research §6), Aspect of the
-- Viper (a rune, research Q9/Q10), racials, potions and trinkets.

return { spec = 1484, packs = { "BeastMastery", "Marksmanship", "Survival" } }
