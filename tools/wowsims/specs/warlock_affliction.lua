-- tools/wowsims/specs/warlock_affliction.lua (wowsims packs plan, Task 13): Affliction (wowsims.com)'s wowsims/forever
-- request and translation; wowsims's preset build "Aff (Wrack)" (presets.ts Builds).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/warlock/dps/builds/aff_wrack.build.json (the build: race Orc, talents 25300020135201351--0550005003,
-- Succubus out, Demon Armor, curse Elements, 32 Soul Shards, Engineering/Tailoring, 20 yd; its rotation) and
-- presets.ts:8,22,31,93 (AFF_WRACK_APL, AffWrackTalents, the Builds list) at the pin. The build carries no gear:
-- gear_sets/preraid.gear.json (central fix 27). Spec binding: 33 Affliction points to 18 Destruction (0 Demonology):
-- Affliction's default.
-- Disagreements (P7; floor 0.87 on fix 31, was 0.72), decisions on-GCD 0.877 (81) top [shadow_bolt -> corruption 2;
-- shadow_bolt -> wrack 2; immolate -> corruption 1] (log times):
--   shadow_bolt / immolate / siphon_life / wrack -> corruption (87.5-101 s): central (G6, deferred to central fix 32):
--   the Shadow Bolt completed at 84.50 misses at 85.50 (its travel), inside our Corruption's landing window, and
--   Events/Rows.lua credits the MISS to Corruption, undoing its debuff.
--   shadow_bolt -> wrack (12.50, 15.00): central (G6): the Agony tick's crit at 10.00 shares a frame with a Shadow
--   Bolt's success, so the bolt's `onCrit` puts Shadow Vulnerability up in the belief (the bolt's own outcome lands
--   1 s later): Shadow Bolt's `onCrit` is a recorded known deviation until fix 32's travel time.
--   wrack -> shadow_bolt / immolate (106.5, 112.5): the same (Shadow Vulnerability believed or not, API-forced: the
--   target's aura is unreadable).
-- Re-pin e2842f0a78 (Task 11; floor 0.87 -> 0.98): decisions on-GCD 0.988 (84) top [wrack -> shadow_bolt 1 (log
-- 142.5)]: the wrack -> shadow_bolt pair of the Shadow Vulnerability class above, not traced at this time (was
-- 0.989, 87: within tolerance). The build is still Orc and still carries
-- `curseOptions: Elements`, so `select` stays (no Bane rule); the request drops executeProportion25/45/90 and sends
-- Greater Blessing of Wisdom at 2, the top rank (R25; the build's rank 1 measured 0.977). Omitted 2 -> 2.
-- Follow-up: the world and kit regen were not refreshed from the new log (pool 5053, was 5353; casting tick 1.12, was
-- 1.04; warlock_world.lua and Warlock.lua keep the old values): within tolerance, lane 10's precedent.
-- Fix 31 (G4: an outcome past an unmapped cast's frame is nobody's) took the dynamite's two misses off Corruption:
-- 0.728 -> 0.877.
-- Worked (P6): Corruption's `now` passes its rank's duration (the belief wrote nothing for a function duration);
-- Shadow Bolt's `onCrit` Shadow Vulnerability (kit and world).
-- Deviations: the Boosts group's Major Spellblasting Potion (item 250937) has no key (no shared content): omitted
-- (rule 2); the Ez-Thro Dynamite II (18588, rule 13) is unmapped (no shared key), listed; Berserking (Troll) and
-- Eureka! are other races' racials, never known to the Orc. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13).
-- Filler (owner 2026-11-12, a player's report: "after putting my dots, Hekili wants me to spam Life Tap, even with full
-- mana"; owner: "Life tap is not a good filler"): wowsims's list ends `wrack` then an unconditional Life Tap, so a
-- Warlock without Wrack (the talent) was shown Life Tap at full mana. An `extra` Shadow Bolt (known at 1) goes before
-- that last Life Tap, and `guard` "default #12" shows the Life Tap only under Shadow Bolt's cost. In wowsims's build
-- Wrack (200 mana) is cheaper than Shadow Bolt and always castable above its cost, so neither line moves the replay or
-- the loops (docs/dev/wowsims-packs.md, Deviations by ruling).
-- Leveling (owner ruling 2026-10-21: no low-level filler): each list ends in Shadow Bolt then Life Tap under its cost,
-- so no bracket idles (worst 0.2 s at 10, 40 and 60; LIVE60 0.2).
return {
    class = "WARLOCK",
    pack = "Affliction (wowsims.com)",
    spec = "affliction",
    name = "Affliction",
    talentTree = "warlock",
    build = "ui/specs/warlock/dps/builds/aff_wrack.build.json",
    gear = "ui/specs/warlock/dps/gear_sets/preraid.gear.json",
    map = { ["item:272438"] = "use_items" }, -- the Weakness Analyzer (ItemSparse 272438: a trinket, InventoryType 12)
    -- the build's "Improved Shadow Bolt Known" variable is auraIsKnown(Shadow Vulnerability 17794): the talent that makes it
    knownAs = { [17794] = "improved_shadow_bolt" },
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
            activeAll = "warlockAssignedCurseIsActiveOnAllTargets", -- rule 20: its swap is the curse lines' cycle_targets=1
            is = "warlockIsAssignedCurse",
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
    extra = { { before = "life_tap", last = true, line = "shadow_bolt" } }, -- the filler (header)
    guard = {
        ["default #12"] = { expect = "life_tap", cond = "!action.shadow_bolt.known|mana.lo<action.shadow_bolt.cost" },
    }, -- the final Life Tap (header)
    leveling = {},
}
