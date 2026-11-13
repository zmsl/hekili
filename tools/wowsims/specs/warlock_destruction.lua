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
-- Omitted 2 -> 2 (dry.lua 3 before option D): petAttack, the pre-pull doAtValue (C), listed. Bane of Havoc (1225228, a
-- cast on wowsims's second target, never in this single-target log) is `other_target=1` (rule 21, option D). Aura lane 2026-11-11: the kit now registers Shadow and Flame's buff (1293816)
-- so Conflagrate's condition reads it (no "dropped the unresolved aura" note for 1293816). Option D registers Bane of
-- Havoc and its debuff (1225228): the multi-target lines' "not on the Havoc target" reads resolve.
-- Leveling note: without Incinerate (a talent from 40) the list fills with its `searing_pain,if=!action.incinerate.
-- known|...` line, and below Searing Pain (18) with the Shadow Bolt below (the Immolate refresh guards below keep
-- Immolate out of it).
-- Deviations: Berserking (Troll) and
-- Eureka! and Blood Fury are other races' racials, never known to the Human. The Weakness Analyzer trinket (272438) is `use_items` (rule
-- 13).
-- Filler (owner 2026-11-12, a player's report: "after putting my dots, Hekili wants me to spam Life Tap, even with full
-- mana"; owner: "Life tap is not a good filler"): wowsims's list ends `incinerate` then an unconditional Life Tap. An
-- `extra` Shadow Bolt (known at 1) goes before that last Life Tap, and `guard` "default #18" shows the Life Tap only
-- under Shadow Bolt's cost. In wowsims's build Incinerate (325 mana less Cataclysm) is cheaper than Shadow Bolt and
-- always castable above its cost, so neither line moves the replay or the loops (docs/dev/wowsims-packs.md, Deviations
-- by ruling).
-- Immolate refresh (reviews I1 and N1, the same ruling): wowsims's two refresh lines, `immolate,if=!action.incinerate.
-- known|debuff.immolate.remains<action.incinerate.cast` (default #16) and the cooldowns list's (cooldowns #6, Bane of
-- Doom up under 15 s, one enemy), are always true without Incinerate (a talent): below 18 (no Searing Pain either)
-- default #16 showed Immolate every GCD with Immolate up, and a level-60 build without Incinerate saw the cooldowns
-- line do so for up to 15 s a Bane of Doom. `guard` "default #16" and "cooldowns #6" add `action.incinerate.known|
-- (action.shadow_bolt.known&debuff.immolate.remains<action.shadow_bolt.cast)` (rule 6's `(K&t)` guard form): without
-- Incinerate Immolate shows only inside the filler's cast of falling off, as wowsims's line refreshes inside
-- Incinerate's (controller ruling, "follow wowsims"); with Incinerate the term is true, so the lines are wowsims's.
-- Leveling (owner ruling 2026-10-21: no low-level filler): each list ends in Shadow Bolt then Life Tap under its cost,
-- so no bracket idles (worst 0.2 s at 10, 40 and 60; LIVE60 0.2).
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
            activeAll = "warlockAssignedCurseIsActiveOnAllTargets", -- rule 20: its swap is the curse lines' cycle_targets=1
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
    -- the low-level behaviour, in the pack's description
    notes = {
        "Without Incinerate (a talent from level 40) this priority fills with Searing Pain, or with Shadow Bolt before Searing Pain is learned, and refreshes Immolate only when it would wear off within a Shadow Bolt cast.",
    },
    extra = { { before = "life_tap", last = true, line = "shadow_bolt" } }, -- the filler (header)
    guard = {
        -- the Immolate refreshes without Incinerate (header)
        ["default #16"] = {
            expect = "immolate",
            cond = "action.incinerate.known|(action.shadow_bolt.known&debuff.immolate.remains<action.shadow_bolt.cast)",
        },
        ["cooldowns #6"] = {
            expect = "immolate",
            cond = "action.incinerate.known|(action.shadow_bolt.known&debuff.immolate.remains<action.shadow_bolt.cast)",
        },
        ["default #18"] = { expect = "life_tap", cond = "!action.shadow_bolt.known|mana.lo<action.shadow_bolt.cost" },
    }, -- the final Life Tap (header)
    leveling = {},
}
