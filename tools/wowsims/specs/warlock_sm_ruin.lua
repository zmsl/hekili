-- tools/wowsims/specs/warlock_sm_ruin.lua (wowsims packs plan, Task 13): SM Ruin (wowsims.com)'s wowsims/forever
-- request and translation; wowsims's preset build "SM/Ruin" (presets.ts Builds).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warlock/dps/builds/sm_ruin.build.json
-- (the build: race Orc, talents 2540002013520105--0550305003, Succubus out, Demon Armor, curse Elements, 32 Soul
-- Shards, Engineering/Tailoring, 20 yd; its rotation) and presets.ts:12,21,30,92 (SM_RUIN_APL, SmRuinTalents, the
-- Builds list) at the pin. The build carries no gear: gear_sets/preraid.gear.json (central fix 27).
-- Spec binding: 30 Affliction points to 21 Destruction (0 Demonology), so the pack is Affliction's second (the
-- Fire/Frostfire shape: mage_frostfire.lua); Affliction's default stays "Affliction (wowsims.com)" (aff_wrack). The
-- name is wowsims's "SM/Ruin" without the slash (a pack name is a file name: src/Hekili_Warlock/APLs/<pack>.simc).
-- Disagreements (P7; floor 0.70 on fix 31, was 0.60), decisions on-GCD 0.702 (94) top [shadow_bolt -> bane_of_doom
-- 13; bane_of_agony -> bane_of_doom 3; corruption -> bane_of_doom 3] (log times):
--   * -> bane_of_doom (120-180 s, 27 of 28): API-forced: remainingTime is `fight_remains` (rule 10: 3600 s on
--   Forever), so the variable "Agony time" (no Doom, no Agony, under 60 s left) never holds: ours keeps Bane of Doom
--   whenever it is down where wowsims switches to Amplify Curse and Bane of Agony for the fight's last minute.
--   siphon_life -> shadow_bolt (36.00): central (G6, fix 32): Siphon Life's miss at 34.50 shares its frame with a
--   Shadow Bolt's success, two of our casts pending, so the miss is nobody's and the belief keeps Siphon Life up.
-- Fix 31 (G4) took the dynamite's miss off Corruption: 0.606 -> 0.702.
-- Worked: as warlock_affliction.lua.
-- Deviations: the Boosts group's Major Spellblasting Potion (item 250937) has no key (no shared content): omitted
-- (rule 2); the Ez-Thro Dynamite II (18588, rule 13) is unmapped (no shared key), listed; Berserking (Troll) and
-- Eureka! are other races' racials, never known to the Orc. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13).
-- Leveling (owner ruling 2026-10-21: no low-level filler): each list ends in an unconditional Life Tap, so no bracket
-- idles (worst 0.2 s at 10, 40 and 60; LIVE60 0.2).
return {
    class = "WARLOCK",
    pack = "SM Ruin (wowsims.com)",
    spec = "affliction",
    name = "SM Ruin",
    talentTree = "warlock",
    build = "ui/specs/warlock/dps/builds/sm_ruin.build.json",
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
        shadow_bolt = { 1, false },
        bane_of_doom = 2,
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
