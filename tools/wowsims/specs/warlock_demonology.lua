-- tools/wowsims/specs/warlock_demonology.lua (wowsims packs plan, Task 13): Demonology (wowsims.com)'s wowsims/forever
-- request and translation; wowsims's preset build "Demo (Fire Brand)" (presets.ts Builds).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/warlock/dps/builds/demo_fire_brand.build.json (the build: race Human, talents
-- 011-0305003201220301351-0050055003, the Imp out and the Succubus sacrificed (Touch of Fire), Demon Armor, curse
-- Elements, 32 Soul Shards, Engineering/Tailoring, 20 yd; its rotation, which is also wowsims's Auto rotation:
-- spec.ts:125 autoRotation) and presets.ts:9,18,27,89 (DEMO_FIRE_BRAND_APL, DemoFireBrandTalents, the Builds list's
-- first) at the pin. The build carries no gear: gear_sets/preraid.gear.json (central fix 27).
-- Spec binding: 31 Demonology points to 18 Destruction and 2 Affliction: Demonology's default.
-- Re-pin e2842f0a78 (Task 16): the build is now Human (Sesam's lists: Life Tap below 30% mana, Major Mana Potion and
-- Demonic Rune lines); the replay answers `fight_remains` from the log's length (R42, a replay-world assumption; in
-- game it reads 3600, gap AN, so the last-minute lines take the long-fight branch).
-- Disagreements (P7; floor 0.89, was 0.77), decisions on-GCD 0.897 (117) top [searing_pain -> life_tap 5; corruption
-- -> searing_pain 2; bane_of_agony -> searing_pain 1] (log times), 12 misses:
--   class A (6, t=32-45; R50, accepted limit): the Demonic Rune and Major Mana Potion refills are invisible to the
--   mana belief (gaps "Potion mana refill"; mana is secret in combat), so lo sits ~2800 under the truth for 20-40 s and
--   `life_tap,if=mana.pct_lo<30` fires.
--   class C (1, the first decision; R50, accepted limit): the pre-pull Soul Fire's doAtValue `-(castTime +
--   travelTime) x 0.9` does not fold (spellTravelTime), so the precombat hard cast is omitted.
--   the rest (5: 10.9 searing_pain -> corruption, 81.8 / 92.3 / 93.9 / 125.6): Searing Pain / Life Tap near-ties with
--   lo 32 under the truth, not traced one by one.
--   The measured top also has corruption -> searing_pain (2) and bane_of_agony -> searing_pain (1), the other way: untraced.
-- Omitted 2 -> 10 (dry.lua 10): petAttack, the pre-pull doAtValue (C), the move (R8: it reaches Hellfire; the
-- spec opts into Movement), five changeTarget, the APL's trinket 18820 (not worn) and the Major Spellblasting Potion
-- 250937; unitIsMoving dropped (Task 5), listed.
-- Known API deviations: the demon's attacks spend Demonic Brand's charges, unseen (the kit keeps
-- the brand its full 10 s); before the Demonic Brand talent the brand is never up, so `searing_pain,if=!debuff.
-- demonic_brand.up` leads the list (as wowsims's own list at that level would).
-- "Execute at" (35%) reads 0.35 (rule 8); wowsims's pet-spell cost 115 ("Firebolt cost") is kept verbatim (ruling W7).
-- Deviations: Berserking (Troll) and
-- Eureka! and Blood Fury are other races' racials, never known to the Human. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13).
-- Leveling (owner ruling 2026-10-21: no low-level filler): each list ends in an unconditional Life Tap, so no bracket
-- idles (worst 0.2 s at 10, 40 and 60; LIVE60 0.2). Below Searing Pain (18) it fills with Life Tap between its DoTs.
return {
    class = "WARLOCK",
    pack = "Demonology (wowsims.com)",
    spec = "demonology",
    name = "Demonology",
    talentTree = "warlock",
    build = "ui/specs/warlock/dps/builds/demo_fire_brand.build.json",
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
        soul_fire = 1,
        searing_pain = { 2, false },
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
        "Below level 18 (before Searing Pain) this priority has no filler and shows Life Tap between its DoTs, as wowsims's own list would at that level.",
        "Before the Demonic Brand talent, Searing Pain leads the list (its brand is never up), as wowsims's own list would.",
    },
    leveling = {},
}
