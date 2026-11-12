-- tools/wowsims/specs/warlock_destruction.lua (wowsims packs plan, Task 13): Destruction (wowsims.com)'s
-- wowsims/forever request and translation; wowsims's preset build "Destro" (presets.ts Builds).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warlock/dps/builds/destro.build.json
-- (the build: race Human, talents 2550002013--0050355103101351, Succubus out, Demon Armor, curse Elements, 32 Soul
-- Shards, Engineering/Tailoring, 20 yd; its rotation) and presets.ts:11,20,29,91 (DESTRO_APL, DestroTalents, the Builds
-- list) at the pin. The build carries no gear: gear_sets/preraid.gear.json (central fix 27).
-- Spec binding: 33 Destruction points to 14 Affliction and 4 Demonology: Destruction's default.
-- Re-pin e2842f0a78 (Task 16): the build is now Human (Sesam's lists: Life Tap below 30% mana, Major Mana Potion and
-- Demonic Rune lines); the replay answers `fight_remains` from the log's length (R42, a replay-world assumption; in
-- game it reads 3600, gap AN, so the last-minute lines take the long-fight branch).
-- Disagreements (P7; floor 0.90, was 0.74), decisions on-GCD 0.900 (110) top [incinerate -> life_tap 5; incinerate
-- -> immolate 4; conflagrate -> immolate 1] (log times), 11 misses:
--   class A (7, t=19-48; R50, accepted limit): the refill-blind mana belief's Life Tap (warlock_demonology.lua).
--   class C (1; R50): the pre-pull Incinerate is omitted (warlock_demonology.lua).
--   the rest (3: 101.5, 167, 185 immolate): the Immolate refresh at `remains<=cast`, not traced.
-- Omitted 2 -> 3 (dry.lua 3): petAttack, the pre-pull doAtValue (C), spell 1225228 (Bane of Havoc: a NextTarget cast,
-- never in this single-target log), listed. Aura lane 2026-11-11: the kit now registers Shadow and Flame's buff (1293816)
-- so Conflagrate's condition reads it (no "dropped the unresolved aura" note for 1293816). Bane of Havoc's debuff
-- (1225228) is deliberately NOT registered: the translator would read it and cast on the main target; waits for C7.
-- Leveling note: below Incinerate (40) the list has no filler and falls through to its last line, Life Tap (as
-- wowsims's own list would at that level); the gate counts Life Tap as a press, so no bracket is idle.
-- Deviations: Berserking (Troll) and
-- Eureka! and Blood Fury are other races' racials, never known to the Human. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13).
-- Leveling (owner ruling 2026-10-21: no low-level filler): each list ends in an unconditional Life Tap, so no bracket
-- idles (worst 0.2 s at 10, 40 and 60; LIVE60 0.2).
return {
    class = "WARLOCK",
    pack = "Destruction (wowsims.com)",
    spec = "destruction",
    name = "Destruction",
    talentTree = "warlock",
    build = "ui/specs/warlock/dps/builds/destro.build.json",
    gear = "ui/specs/warlock/dps/gear_sets/preraid.gear.json",
    map = { ["item:272438"] = "use_items" }, -- the Weakness Analyzer (ItemSparse 272438: a trinket, InventoryType 12)
    select = {
        castWarlockAssignedCurse = {
            setting = "assigned_curse",
            option = "curseOptions",
            zero = "Elements", -- proto/warlock.proto CurseOptions: Elements = 0 (protojson omits it)
            candidates = {
                Elements = "curse_of_the_elements",
                Recklessness = "curse_of_recklessness",
                Weakness = "curse_of_weakness",
                NoCurse = false,
            },
            active = "warlockAssignedCurseIsActive",
            is = "warlockIsAssignedCurse",
        },
    },
    -- focus by role (docs/dev/wowsims-packs.md): tier 1 the proc lines, tier 2 the upkeep (the DoTs, the Banes, the
    -- curses, a debuff kept up); the cooldowns (Amplify Curse, the racials), the core casts and Life Tap none
    focus = {
        bane_of_doom = 2,
        bane_of_agony = 2,
        immolate = 2,
        corruption = 2,
        curse_of_the_elements = 2,
        curse_of_recklessness = 2,
        curse_of_weakness = 2,
    },
    -- the low-level behaviour (owner ruling 2026-10-21: no low-level filler), in the pack's description
    notes = {
        "Below level 40 (before Incinerate) this priority has no filler and shows Life Tap between its DoTs, as wowsims's own list would at that level.",
    },
    leveling = {},
}
