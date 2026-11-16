-- tools/wowsims/specs/warlock_affliction.lua (wowsims packs plan, Task 13): Affliction (wowsims.com)'s wowsims/forever
-- request and translation; wowsims's preset build "Aff (Wrack)" (presets.ts Builds).
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/warlock/dps/builds/aff_wrack.build.json (the build: race Orc, talents 25500020135201351-0050203001-05,
-- the Imp sacrificed (no demon out), Demon Armor, curse Elements, 32 Soul Shards, Engineering/Tailoring, 20 yd; its
-- rotation) and presets.ts (AFF_WRACK_APL, the Builds list) at the pin. The build carries no gear:
-- gear_sets/preraid.gear.json (central fix 27). Spec binding: 35 Affliction points to 11 Demonology and 5 Destruction:
-- Affliction's default.
-- Re-pin e5a9cd2a2d -> e4ef929e54 (0.9; owner ruling L1154 (2): follow wowsims): the new Wrack APL (202831a0a0).
-- Bane of Doom only on 2+ targets (one target never casts it); the Cooldowns call always on one target; Amplify Curse
-- and Bane of Agony no longer wait on Doom; Eureka! and Blood Fury wait on the Amp Agony variables (Agony up with
-- Amplify Curse used within its duration + 1.5 s, or waiting would cost a use over the fight left); the Cooldowns
-- Wrack line is gone (Life Tap moves up). In game `fight_remains` reads 3600 (API-forced), so every "Waiting Costs"
-- term is false there and the racials fire on Amp Agony Up (or 2+ targets); the replay answers it from the log.
-- The Major Mana Potion line goes (rule 13: wowsims's autocast no longer uses the potion in the 180 s fight): the new
-- APL drinks Major Spellblasting Potion 250937 (cooldowns #2, at 4.41 and 124.41) on the shared potion cooldown, and
-- 250937 has no key in our data (the pack omits its line); the
-- Weakness Analyzer's cooldown is 6 min (was 90 s: one use, was two). Wrack (6de4dee7b9 and on) no longer raises the
-- damage the other DoTs deal: while it channels, Corruption, Siphon Life and Bane of Agony tick on their half
-- points too (the loop world models it; the kit reads no tick). wowsims's expected tick now counts its crits
-- (2e9186a04a): no Affliction line reads it (log only).
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
-- Follow-up: the world and kit regen were not refreshed from the new log (the world's pool 5353, the log's 6277 at
-- e5a9cd2a2d; casting tick 1.12, was 1.04): within tolerance, lane 10's precedent. The 0.9 re-pin's fix round moved
-- the loop world to the build (35/11/5, instant Corruption, the Imp sacrificed, pool 6277, Spirit 235, regen 35.625 /
-- 15.2: warlock_world.lua); the kit's fsr seed stays the Human logs' { 38.13, 15.2 }.
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
