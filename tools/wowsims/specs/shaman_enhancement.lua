-- tools/wowsims/specs/shaman_enhancement.lua (wowsims packs plan, Task 10): Enhancement (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/shaman/enhancement/presets.ts:14-23 (DefaultGear: the Testing build's
-- gear; StandardTalents 053503102-053030031005112251, the build's own talentsString) and builds/testing.build.json at
-- d33930d040, where the rotation was apls/default.apl.json (the presets' default), replacing the build's. The re-pin
-- (e2842f0a78) deletes apls/: the rotation is the build's own (builds/testing.build.json's player.rotation).
-- At d33930d040, disagreements worked (P7, decisions on-GCD 0.807 of 88; first clean run 0.557):
-- 1. "* -> flame_shock" (was 19 of 35): content gap, fixed in the kit. Call of Flame: wowsims spell data, absent from
--    DB2 (wowdb effects 16038 has none): +3 s a rank on Flame Shock (21 s at 3/3, the log's). IN-GAME CHECK: Flame
--    Shock duration with Call of Flame: 21 s?
-- 2. "fire_nova -> earth_shock" (4; was 13): replay limit, fixed centrally (fix 9: the replay sends the shocks' shared
--    category and the talent-modified cooldowns, C.SHARED); 4 left. Core gap behind them too (GAP V): after a refill
--    it cannot see (here the potions and runes), the secret-mana belief pins at the dearest usable cost (lo = hi), so
--    from the first potion it sits about 2000 under the truth.
-- 3. "stormstrike -> earth_shock" (3) and "stormstrike -> lightning_bolt" (3): replay limit (wowsims casts on the
--    instant a cooldown ends; the decision sits a hair before it, our cooldown not yet over; mana is no factor).
-- Kit fixes (P6): Reverberation (shocks 5 s), Improved Fire Nova (6 s), Shamanistic Focus (-45% on the shocks and
-- Lightning Shield), from wowdb; Call of Flame (+3 s a rank on Flame Shock) and Stormstrike's cost (8% of base mana,
-- 121 at 60; the DB2's 125), wowsims spell data absent from DB2 (in-game checks). Each matches the log.
-- Known deviations: the Water Shield line's condition is ours (R55, below). Of wowsims's autocast cooldowns (rule 13)
-- Rage of the Farseer 425336 (the kit's, by its ID) and the Weakness Analyzer (use_items) translate; mana is secret in
-- combat, so the potion (mana.pct<80) and Demonic Rune (<70) read the belief's estimate. Fire Nova now costs wowsims's
-- 65..375 in the kit (R57a, the owner's in-game read; the DB2's 520 was wrong).
-- Re-pin e2842f0a78 (Task 15; floor 0.98 kept, R56 as amended by R57a): decisions on-GCD 0.988 (85) top
-- [magma_totem -> stormstrike 1] (base 1.000; 0.965 with Fire Nova at the DB2's 520). The build is now Windshaper
-- Skyborne (was Orc; no Blood Fury), talents 053303102-053030031005102251-03 (was 053503102-053030031005112251),
-- Greater Blessings of Wisdom and Might at 2, the top rank (R25; the log applies 25918 and 25916); its own list: Magma
-- Totem (40 s with Trial by Fire 2/2, fixed in the kit and the worlds), Windfury Totem, Water Shield, Flame Shock by
-- multidot, Fire Nova the unconditional single-target filler (so untiered; the old `mana.pct>10` filler line is gone),
-- an AoE list. Omissions 3 -> 5: the Water Shield line's empty aura (its branch only; R55 gives the line its
-- condition), the Manual Crowd Pummeler 9449 (the item swap's) and the trinket 249469 unmapped, itemSwap,
-- autoTimeToNext; the Weakness Analyzer 272438 maps to use_items (as Elemental's).
-- The miss (log clock): 121.47 magma_totem -> stormstrike: the Major Mana Potion's +2008 is a refill the belief
-- cannot see (R50 class A, GAP V).
-- Re-pin 0.7 (4b0030a44b, lane shaman): the pack's lines are unchanged (the talent string re-encoded, Improved Ghost Wolf
-- moved); Stormstrike's cooldown is 6 s (was 8; the kit's). aoe_rotation #1's autoTimeToNext stays omitted (translator-5,
-- held: nothing in this lane adds it).
return {
    class = "SHAMAN",
    pack = "Enhancement (wowsims.com)",
    spec = "enhancement",
    name = "Enhancement",
    talentTree = "shaman",
    build = "ui/specs/shaman/enhancement/builds/testing.build.json",
    -- the build's resourcePotId 13444, Major Mana Potion; the Weakness Analyzer (ItemSparse 272438: a trinket) as
    -- Elemental maps it
    map = { OtherActionResourcePotion = "major_mana_potion", ["item:272438"] = "use_items" },
    focus = { -- by role (docs/dev/wowsims-packs.md); the totems none (the user, 2026-10-21); Fire Nova is the filler
        -- at the re-pin (no Clearcasting line), so none
        water_shield = 2,
        lightning_bolt = 1,
        flame_shock = 2,
    },
    -- before Stormstrike (learned at 40): Lightning Bolt fills while the shocks wait; silent from 40, and so at 60,
    -- where wowsims casts it only at five Maelstrom Weapon stacks
    leveling = { "lightning_bolt,if=!action.stormstrike.known" },
    -- Deviation by ruling (R55, 2026-11-06): the build's Water Shield line tests an empty aura ID (no condition in
    -- wowsims, which never knows the shield); from 20 it would lead every GCD. Its own buff, as the precombat line.
    condition = { water_shield = "!buff.water_shield.up" },
    -- not wowsims (its imbue never expires, sim/shaman/weapon_imbues.go); need-based (R41): the main hand's imbue when
    -- none is up (weapon buffs lane, owner 2026-11-05: Flametongue, Rockbiter before it is learned at 10), first so it
    -- works in combat (a trailing line is never reached; a player's custom one only showed out of combat)
    levelingFirst = {
        "flametongue_weapon,if=!buff.main_hand_enchant.up",
        "rockbiter_weapon,if=!buff.main_hand_enchant.up&!action.flametongue_weapon.known",
    },
}
