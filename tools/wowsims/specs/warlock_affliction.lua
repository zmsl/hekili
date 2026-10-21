-- tools/wowsims/specs/warlock_affliction.lua (wowsims packs plan, Task 13): Affliction (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/warlock/dps/builds/aff_wrack.build.json (the build: race Orc, talents 25300020135201351--0550005003,
-- Succubus out, Demon Armor, curse Elements, 32 Soul Shards, Engineering/Tailoring, 20 yd; its rotation) and
-- presets.ts:8,22,31,93 (AFF_WRACK_APL, AffWrackTalents, the Builds list) at the pin. The build carries no gear:
-- gear_sets/preraid.gear.json (central fix 27). Spec binding: 33 Affliction points to 18 Destruction (0 Demonology):
-- Affliction's default. Disagreements (P7; floor 0.72), decisions on-GCD 0.728 (81) top [shadow_bolt -> corruption 10;
-- immolate -> corruption 3; siphon_life -> corruption 3] (log times):
--   all three (1.5-20 s and 65-85 s): central (shared gap, reported): wowsims's Ez-Thro Dynamite II misses at 2.43 and
--   65.43 while our Corruption (0.8 s cast) is in its landing window; the replay emits the unmapped item's outcome with
--   no cast, and Events/Rows.lua credits the MISS to the one pending cast of ours (Obs.Avoided), which undoes
--   Corruption's debuff until wowsims recasts it 18 s later. Without the item's outcome: 0.901 (measured, not kept).
--   wrack -> shadow_bolt / life_tap: API-forced: the target's Shadow Vulnerability (17794) is unreadable in combat, so
--   `shadow_bolt,if=!debuff.shadow_vulnerability.up` passes; the kit's Shadow Bolt `onCrit` would model it, but the
--   bolt's crit lands about 1 s after its success (travel), past Rows's cast window (central: no `velocity`).
-- Worked (P6): Corruption's `now` passes its rank's duration (the belief wrote nothing for a function duration);
-- Shadow Bolt's `onCrit` Shadow Vulnerability (kit and world).
-- Deviations: the Boosts group's Major Spellblasting Potion (item 250937) has no key (no shared content): omitted
-- (rule 2); the Ez-Thro Dynamite II (18588, rule 13) is unmapped (no shared key), listed; Berserking (Troll) and
-- Eureka! are other races' racials, never known to the Orc. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13). Leveling (P8): every bracket live without a recipe line (worst idle 0.2 s at 10, 40 and 60; LIVE60 0.2).
return {
    class = "WARLOCK",
    pack = "Affliction (wowsims.com)",
    spec = "affliction",
    name = "Affliction",
    talentTree = "warlock",
    build = "ui/specs/warlock/dps/builds/aff_wrack.build.json",
    gear = "ui/specs/warlock/dps/gear_sets/preraid.gear.json",
    map = { ["item:272438"] = "use_items" }, -- the Weakness Analyzer (ItemSparse 272438: a trinket, InventoryType 12)
    select = {
        castWarlockAssignedCurse = {
            setting = "assigned_curse",
            option = "curseOptions",
            candidates = {
                Elements = "curse_of_the_elements",
                Recklessness = "curse_of_recklessness",
                Weakness = "curse_of_weakness",
                NoCurse = false,
            },
            active = "warlockAssignedCurseIsActive",
        },
    },
    -- focus by role (docs/dev/wowsims-packs.md): tier 1 the proc lines, tier 2 the upkeep (the DoTs, the Banes, the
    -- curses, a debuff kept up); the cooldowns (Amplify Curse, the racials), the core casts and Life Tap none
    focus = {
        shadow_bolt = { 2, 1, false },
        bane_of_agony = 2,
        corruption = 2,
        siphon_life = 2,
        immolate = 2,
        curse_of_the_elements = 2,
        curse_of_recklessness = 2,
        curse_of_weakness = 2,
    },
    leveling = {},
}
