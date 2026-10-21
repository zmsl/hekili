-- tools/wowsims/specs/warlock_demonology.lua (wowsims packs plan, Task 13): Demonology (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/warlock/dps/builds/demo_fire_brand.build.json (the build: race Orc, talents
-- 011-0305003201220301351-0050055003, the Imp out and the Succubus sacrificed (Touch of Fire), Demon Armor, curse
-- Elements, 32 Soul Shards, Engineering/Tailoring, 20 yd; its rotation, which is also wowsims's Auto rotation:
-- spec.ts:125 autoRotation) and presets.ts:9,18,27,89 (DEMO_FIRE_BRAND_APL, DemoFireBrandTalents, the Builds list's
-- first) at the pin. The build carries no gear: gear_sets/preraid.gear.json (central fix 27).
-- Spec binding: 31 Demonology points to 18 Destruction and 2 Affliction: Demonology's default.
-- Disagreements (P7; floor 0.76), decisions on-GCD 0.767 (116) top [searing_pain -> bane_of_doom 8; soul_fire ->
-- bane_of_doom 6; corruption -> bane_of_doom 3] (log times):
--   * -> bane_of_doom (120-180 s, 23 of 27): API-forced: `fight_remains` 3600 s (rule 10): Bane of Doom whenever it is
--   down; wowsims casts Bane of Agony in the last minute (and splits its Boosts on "Time to execute").
--   corruption / immolate -> searing_pain (46.70, 72.40, 85.90): replay limit: the DoT's fade and wowsims's recast
--   share a log timestamp; the decision sits just before the cast, where the modelled debuff still runs.
--   life_tap -> searing_pain (52.80): central (shared gap): `life_tap,if=pet.mana<115` (the Imp at 56 mana in the log);
--   the replay does not read the pet's mana from the log (replay.lua's shortcut), so ours reads it full.
-- Known API deviations: remainingTime (above); the demon's attacks spend Demonic Brand's charges, unseen (the kit keeps
-- the brand its full 10 s); before the Demonic Brand talent the brand is never up, so `searing_pain,if=!debuff.
-- demonic_brand.up` leads the list (as wowsims's own list at that level would).
-- "Execute at" (35%) reads 0.35 (rule 8); wowsims's pet-spell cost 115 ("Firebolt cost") is kept verbatim (ruling W7).
-- Deviations: the Boosts group's Major Spellblasting Potion (item 250937) has no key (no shared content): omitted
-- (rule 2); the Ez-Thro Dynamite II (18588, rule 13) is unmapped (no shared key), listed; Berserking (Troll) and
-- Eureka! are other races' racials, never known to the Orc. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13). Leveling (P8): every bracket live without a recipe line (worst idle 0.2 s at 10, 40 and 60; LIVE60 0.2).
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
    leveling = {},
}
