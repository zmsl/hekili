-- tools/wowsims/specs/warlock_sm_ruin.lua (wowsims packs plan, Task 13): SM Ruin (wowsims.com)'s wowsims/forever
-- request and translation; wowsims's preset build "SM/Ruin" (presets.ts Builds).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warlock/dps/builds/sm_ruin.build.json
-- (the build: race Human, talents 2550002013520105--0550205003, Succubus out, Demon Armor, curse Elements, 32 Soul
-- Shards, Engineering/Tailoring, 20 yd; its rotation) and presets.ts:12,21,30,92 (SM_RUIN_APL, SmRuinTalents, the
-- Builds list) at the pin. The build carries no gear: gear_sets/preraid.gear.json (central fix 27).
-- Spec binding: 30 Affliction points to 21 Destruction (0 Demonology), so the pack is Affliction's second (the
-- Fire/Frostfire shape: mage_frostfire.lua); Affliction's default stays "Affliction (wowsims.com)" (aff_wrack). The
-- name is wowsims's "SM/Ruin" without the slash (a pack name is a file name: src/Hekili_Warlock/APLs/<pack>.simc).
-- Re-pin e2842f0a78 (Task 16): the build is now Human (Sesam's lists: Life Tap below 30% mana, Major Mana Potion and
-- Demonic Rune lines); the replay answers `fight_remains` from the log's length (R42, a replay-world assumption; in
-- game it reads 3600, gap AN, so the last-minute lines take the long-fight branch).
-- Disagreements (P7; floor 0.78, was 0.70), decisions on-GCD 0.787 (94) top [shadow_bolt -> life_tap 9;
-- shadow_bolt -> siphon_life 5; shadow_bolt -> corruption 3] (log times):
--   class B (R49, owner): wowsims gates Amplify Curse, Bane of Agony (#6/#7, "Agony time" / "DPET Non DoT") and
--   Corruption, Siphon Life, Immolate (#8-#10) on spellExpectedDpet, which the translator omits (rule 18; L84, after
--   0.6.0): without the recipe's stand-in DoT lines (`extra`) the pack had no DoTs (0.606). The stand-ins cast each
--   DoT when it is down or within its cast time of falling (the entries' own maxOverlap); the siphon_life /
--   corruption misses are all in the fight's last ~20 s, where wowsims's DPET stops refreshing the DoTs and ours recasts them. Amplify Curse and Bane of Agony (the
--   last-minute Doom-to-Agony swap, not a DoT-down need) stay omitted.
--   class A (shadow_bolt -> life_tap; R50, accepted limit): the refill-blind mana belief's Life Tap
--   (warlock_demonology.lua).
-- Omitted 2 -> 6 (dry.lua 6): the hidden #3 and five spellExpectedDpet (#6-#10).
-- Worked: as warlock_affliction.lua.
-- Deviations: Berserking (Troll) and
-- Eureka! and Blood Fury are other races' racials, never known to the Human. The Weakness Analyzer trinket (272438) is `use_items` (rule
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
    -- R49 (owner): wowsims gates Corruption, Siphon Life and Immolate (#8-#10) on spellExpectedDpet, omitted (rule 18),
    -- so these stand-ins cast each DoT when it is down or about to expire (the entries' own strictMultidot overlap,
    -- `maxOverlap = spellCastTime`): not wowsims; need-based (R41), before the APL's #11 Life Tap as #8-#10 sit
    extra = {
        { before = "life_tap", line = "corruption,focus=2,if=debuff.corruption.remains<=action.corruption.cast" },
        { before = "life_tap", line = "siphon_life,focus=2,if=debuff.siphon_life.remains<=action.siphon_life.cast" },
        { before = "life_tap", line = "immolate,focus=2,if=debuff.immolate.remains<=action.immolate.cast" },
    },
    leveling = {},
}
