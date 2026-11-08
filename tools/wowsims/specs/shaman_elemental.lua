-- tools/wowsims/specs/shaman_elemental.lua (wowsims packs plan, Task 14): Elemental (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/shaman/elemental/builds/testing.build.json
-- at the pin: the player (Troll before the re-pin, Windshaper Skyborne at e2842f0a78; talents
-- 5500331023001351-053002001-053, gear, options) and the rotation, wowsims's Auto list for the build.
-- Disagreements (P7; floor 0.93: decisions on-GCD 0.937 of 95 on the first clean run, 0.853 before the translator's
-- multidot, central fix 28):
-- 1. "lightning_bolt -> searing_totem" (3, log 112.68-122.38): central (ranks; deviation until central fix 30): wowsims
--    down-ranks (`castSpell` Lightning Bolt rank 8, 10392, 144 mana, at mana < 20%) and the translator keys every rank
--    as the ability (rule 5), which the kit prices at its top rank (198), so at ~150 mana Searing Totem (170) is the
--    sooner wait. Deviation: the pack shows the top rank.
-- 2. "earth_shock -> lightning_bolt" (2, log 80.18 and 101.18): central (travel time): wowsims spends Revelation when
--    a Lightning Bolt, Lava Burst or Earth Shock lands (1 s after the cast; a miss keeps it), the kit at the cast's end,
--    so at a Lava Burst cast's end our state has it gone while wowsims's Earth Shock still reads it.
-- 3. "searing_totem -> flame_shock" (1, log 124.58): central (the mana belief): the Major Mana Potion at 124.55 is a
--    refill the secret-mana belief does not credit (nor Demonic Rune's), so Searing Totem (170) reads unaffordable and
--    the cheaper Flame Shock (Convection's 153) is the sooner wait; lo sits up to 2286 under the truth after them.
-- Re-pin e2842f0a78 (Task 11; floor 0.93 -> 0.92, ruling R26): decisions on-GCD 0.928 (97) top
-- [earth_shock -> lightning_bolt 3; lightning_bolt -> searing_totem 3; flame_shock -> searing_totem 1] (base 0.957
-- (92): lightning_bolt -> searing_totem 4). The build is now Windshaper Skyborne (was Troll), its list puts Elemental
-- Mastery and the racial lines on Flame Shock's DoT; Greater Blessing of Wisdom at 2, the top rank (R25).
--   earth_shock -> lightning_bolt (log 53.44, 73.07, 80.42): central, gaps.md "Travel time" (core belief): the Lava
--   Burst completing at 53.44 spends Revelation (gained 52.49) at its cast end in our belief; wowsims spends it at the
--   landing, so its Earth Shock at 53.44 still reads it. New at the re-pin (0 at base): the new build's casts.
--   lightning_bolt -> searing_totem (112.83, 117.19, 121.75): class 1 above (gap BL, rank 8 at 144 mana).
--   flame_shock -> searing_totem (109.06): the same low-mana phase: our mana belief sits under the truth (at-cost
--   lo-truth -388.7; the poll's lo was not dumped: plausibly the rank-8 Lightning Bolts, 144 in wowsims, read at the top
--   rank's 198), so Flame Shock (170.8) reads unaffordable. Without the three travel-time misses 93 of 97 (0.959, the base).
-- Deviation: multidot (Flame Shock) keeps the DoT on the current target only (the header's `# Deviation:` line).
-- Worked: the shaman world's Elemental distance 20 yd (the build's), its mana and regen from the re-pin log (5650; 31.13
-- a second casting, 45.25 outside the five-second rule; was 5590 / 29.75 / 42.5 as a Troll; the kit's seeds likewise:
-- no decision moved), the Troll's Berserking in the world's MAP (unused since). Windshaper Skyborne has no race file:
-- its Skysight is movement only (no regen mod, unlike the High Order's Read Ley Line); the shared Wind Blessed is
-- +2% cast speed in wowsims (Lightning Bolt 2.0 s -> 1.961 s in the log). The Blood Fury and Berserking lines stay
-- silent (other races'). The Weakness Analyzer (item 272438) is `use_items` (rule 13; as Shadow and Affliction).
-- Omitted 1 -> 0.
-- Re-pin 0.7 (4b0030a44b, lane shaman): Lava Burst is gone from the game (owner, 2026-11-07; the sim dropped it at
-- 4fe09d45b7 and Call of Thunder 16120 took its talent slot), so the kit, the world and the pack have none, and
-- disagreements 2 (Revelation spent at a Lava Burst's landing) and the Lava Burst clauses of the 4 above are gone.
-- The list: Water Shield and the Weakness Analyzer after Mana Tide Totem, Chain Lightning also on a single target at
-- mana >= 40% without Elemental Mastery up, Fire Nova after it, Earth Shock single-target only; Chain Lightning costs
-- 245/360/425/495 (was 145..315). The disagreements above are re-counted at the floors step.
-- Levels (P8; learn_shaman.lua regenerated with the Elemental kit's ranks): L10 0.0, L40 0.0, L60 5.0 s, no leveling
-- line needed. The spells the DB2 lacks (Lava Burst rank 4, 1326047; Elemental Mastery, 16166) still count as learned
-- at level 1, so the lower brackets can press them early (the check's limit, docs/dev/wowsims-packs.md).
return {
    class = "SHAMAN",
    pack = "Elemental (wowsims.com)",
    spec = "elemental",
    name = "Elemental",
    talentTree = "shaman",
    build = "ui/specs/shaman/elemental/builds/testing.build.json",
    -- the build's resourcePotId 13444, Major Mana Potion; the Weakness Analyzer (ItemSparse 272438: a trinket) as
    -- Shadow and Affliction map it
    map = { OtherActionResourcePotion = "major_mana_potion", ["item:272438"] = "use_items" },
    -- by role (docs/dev/wowsims-packs.md): Flame Shock upkeep, Earth Shock on Revelation; Chain Lightning, Lightning
    -- Bolt and the AoE lines rotational; the totems none (the user, 2026-10-21)
    focus = { flame_shock = 2, earth_shock = 1 },
}
