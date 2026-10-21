-- tools/wowsims/specs/warlock_shadow_brand.lua (wowsims packs plan, Task 13): Shadow Brand (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/warlock/dps/builds/demo_shadow_brand.build.json (the build: race Orc, talents
-- 011-0005003231220301351-0550005003, the Succubus out and the Imp sacrificed (Burning Shadow), Demon Armor, curse
-- Elements, 32 Soul Shards, Engineering/Tailoring, 20 yd; its rotation) and presets.ts:10,19,28,90
-- (DEMO_SHADOW_BRAND_APL, DemoShadowBrandTalents, the Builds list) at the pin. The build carries no gear:
-- gear_sets/preraid.gear.json (central fix 27).
-- Spec binding: 31 Demonology points to 18 Destruction and 2 Affliction, so the pack is Demonology's second (the
-- Fire/Frostfire shape: mage_frostfire.lua); Demonology's default stays "Demonology (wowsims.com)" (demo_fire_brand,
-- wowsims's Auto rotation). The name is wowsims's "Demo (Shadow Brand)" without the spec.
-- Disagreements (P7; floor 0.73), decisions on-GCD 0.735 (98) top [searing_pain -> bane_of_doom 5; shadow_bolt ->
-- bane_of_doom 5; soul_fire -> bane_of_doom 5] (log times):
--   * -> bane_of_doom (120-180 s): API-forced: `fight_remains` 3600 s (warlock_demonology.lua).
--   searing_pain -> immolate / life_tap (38.30, 48.80): API-forced: the Succubus's attacks spend Demonic Brand's
--   charges and the brand falls early in wowsims; ours (the target's charges unreadable, the demon's hits unseen) keeps
--   it the full 10 s (the kit's shortcut).
-- Known deviations: warlock_demonology.lua's (the same list but Shadow Bolt the filler and the Life Tap line's constant
-- "Lash of Pain cost" 160, the Succubus's, kept verbatim: ruling W7).
-- Deviations: the Boosts group's Major Spellblasting Potion (item 250937) has no key (no shared content): omitted
-- (rule 2); the Ez-Thro Dynamite II (18588, rule 13) is unmapped (no shared key), listed; Berserking (Troll) and
-- Eureka! are other races' racials, never known to the Orc. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13). Leveling (P8): every bracket live without a recipe line (worst idle 0.2 s at 10, 40 and 60; LIVE60 0.2).
return {
    class = "WARLOCK",
    pack = "Shadow Brand (wowsims.com)",
    spec = "demonology",
    name = "Shadow Brand",
    talentTree = "warlock",
    build = "ui/specs/warlock/dps/builds/demo_shadow_brand.build.json",
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
        searing_pain = 2,
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
