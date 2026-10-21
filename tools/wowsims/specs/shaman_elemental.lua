-- tools/wowsims/specs/shaman_elemental.lua (wowsims packs plan, Task 14): Elemental (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/shaman/elemental/builds/testing.build.json
-- at the pin: the player (Troll, talents 5500331023001351-053002001-053, gear, options) and the rotation, wowsims's Auto
-- list for the build.
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
-- Deviation: multidot (Flame Shock) keeps the DoT on the current target only (the header's `# Deviation:` line).
-- Worked: the shaman world's Elemental distance 20 yd (the build's), its mana (5590) and regen (29.75 a second
-- casting, 42.5 more outside the five-second rule: the log's), the Troll's Berserking in the world's MAP. Known
-- deviations: wowsims's autocast trinket (item 272438) stays unmapped (no trinket registered), as in Enhancement.
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
    map = { OtherActionResourcePotion = "major_mana_potion" }, -- the build's resourcePotId 13444, Major Mana Potion
    -- by role (docs/dev/wowsims-packs.md): Flame Shock upkeep, Earth Shock on Revelation; Lava Burst (on cooldown while
    -- Flame Shock is up), Lightning Bolt and the AoE lines rotational; the totems none (the user, 2026-10-21)
    focus = { flame_shock = 2, earth_shock = 1 },
}
