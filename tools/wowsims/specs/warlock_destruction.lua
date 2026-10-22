-- tools/wowsims/specs/warlock_destruction.lua (wowsims packs plan, Task 13): Destruction (wowsims.com)'s
-- wowsims/forever request and translation; wowsims's preset build "Destro" (presets.ts Builds).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warlock/dps/builds/destro.build.json
-- (the build: race Orc, talents 2530000013-0004-0050355103101351, Succubus out, Demon Armor, curse Elements, 32 Soul
-- Shards, Engineering/Tailoring, 20 yd; its rotation) and presets.ts:11,20,29,91 (DESTRO_APL, DestroTalents, the Builds
-- list) at the pin. The build carries no gear: gear_sets/preraid.gear.json (central fix 27).
-- Spec binding: 33 Destruction points to 14 Affliction and 4 Demonology: Destruction's default.
-- Disagreements (P7; floor 0.74), decisions on-GCD 0.743 (109) top [incinerate -> bane_of_doom 10; conflagrate ->
-- bane_of_doom 5; shadowburn -> bane_of_doom 4] (log times): every one is in the fight's last minute (120-180 s):
-- API-forced: `fight_remains` 3600 s (rule 10), so Bane of Doom whenever it is down; wowsims switches to Bane of Agony.
-- Leveling note: below Incinerate (40) the list has no filler and falls through to its last line, Life Tap (as
-- wowsims's own list would at that level); the gate counts Life Tap as a press, so no bracket is idle.
-- Deviations: the Boosts group's Major Spellblasting Potion (item 250937) has no key (no shared content): omitted
-- (rule 2); the Ez-Thro Dynamite II (18588, rule 13) is unmapped (no shared key), listed; Berserking (Troll) and
-- Eureka! are other races' racials, never known to the Orc. The Weakness Analyzer trinket (272438) is `use_items` (rule
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
