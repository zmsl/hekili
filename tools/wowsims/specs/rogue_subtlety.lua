-- tools/wowsims/specs/rogue_subtlety.lua (wowsims packs plan, Task 8): Subtlety (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/rogue/dps/presets.ts:42-47
-- (TALENTS_SUB_HEMO, "Subtlety Hemo"), :163-165 (DefaultOptions), :241-243 (OtherDefaults) and
-- ui/features/settings/model/apply_defaults.ts:68,87-95 (the race, the professions and the reaction time the UI
-- defaults to: the class's first race, Engineering, 100 ms) at the pin. One APL for the three builds
-- (ui/specs/rogue/dps/apls/default.apl.json, "Direct APL"), played as the build plays it: the build is TypeSimple
-- (spec.ts:82) with presets.ts:57 DEFAULT_SIMPLE_ROTATION (:58 SIMPLE_ROTATION; useBackstab and useExposeArmor false), whose simpleRotation writes
-- those two variables over the raw APL (spec.ts:186-204); the recipe's `vars` does the same (ruling R29: the raw APL
-- has Use Backstab true since upstream 0dbe35317d, a Backstab rotation unlike the build). The talents and the build's `vars` pick the lines.
-- Translation: the APL's "Use X" variables are constants (inlined and folded, rule 1); omitted (rule 2): Maintain
-- Expose (its call folds to never: "Use Expose Armor" false; its strictSequence, RL3, never reached), autocastOtherCooldowns
-- (#7: rule 13, no "Major cooldown used" in the log), the potion; Thousand Cuts's buff (1310723) resolves from the kit's aura, so
-- `auraIsKnown` of it is the talent. The Orc's Blood Fury -> Adrenaline Rush strictSequence (#10) is rule 14's
-- two lines since central fix 13 (Adrenaline Rush unlearned here: the Blood Fury line alone). Known deviations (Forever API): remainingTime reads 3600 (time to die unknown),
-- so the "Fight About to End" terms never fire; energy is secret in combat, so an unannounced energize (Rogue Armor
-- Energize 27788, +20) is invisible to the belief until the next read.
-- At the old pin d33930d0, disagreements worked (P7; decisions on-GCD 0.939, n 82): hemorrhage -> rupture 4 (Thousand Cuts's stacks and
-- Hemorrhage's cost: the belief's energy without the unannounced energize above); eviscerate -> rupture 1 (the same
-- energize: wowsims at 75.6 energy, our belief 60). The pre-rebase hemorrhage -> garrote 7 (the opener's Garrote) went
-- away with the central fixes (fix 6's energy belief).
-- Kit fixes from this replay (P6): Dirty Deeds (Garrote 30 at 2/2), Thousand Cuts's -3 a stack on Hemorrhage and
-- Backstab, Improved Sinister Strike's -5 as the whole talent's (Combat's Sinister Strike 40).
-- Re-pin e2842f0a78 (Task 13): omitted 7 -> 9 (the Energy Pooling Checks waitUntil and its group, Gnome-gated: see
-- rogue_assassination.lua). Rogue Armor Energize 27788 in the log 6 times (old 5). Brain Damage 1290950 (the
-- Lobotomizer's proc) is the only untagged GCD-0 cast besides melee, unmapped.
-- Disagreements (P7; floor 0.96 -> 0.96, decisions on-GCD 0.964, n 83): hemorrhage -> rupture 156.49 (wowsims casts on
-- the unseen 27788's instant: lo 12.8, truth 33); eviscerate -> rupture 174.25 and hemorrhage -> slice_and_dice 178.15
-- (the fight's last 6 s: Rupture and SnD skipped, gap AN). Regen/pool not refreshed (as Assassination).
return {
    class = "ROGUE",
    pack = "Subtlety (wowsims.com)",
    spec = "subtlety",
    name = "Subtlety",
    talentTree = "rogue",
    apl = "ui/specs/rogue/dps/apls/default.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassRogue",
        gear = "ui/specs/rogue/dps/gear_sets/p1_bssub.gear.json",
        talentsString = "00530301-320003-305230031321001151",
        specKey = "rogue",
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) }, -- an empty message (dkjson: {} is [])
        profession1 = "Engineering",
        reactionTimeMs = 100,
        distanceFromTarget = 5,
    },
    -- the build's simple rotation (presets.ts:57 DEFAULT_SIMPLE_ROTATION (:58 SIMPLE_ROTATION)) writes these over the raw APL (spec.ts:195-196;
    -- ruling R29): Use Backstab is `true` raw, Use Expose Armor already `false`
    vars = { ["Use Backstab"] = "false", ["Use Expose Armor"] = "false" },
    map = {},
    -- by role (docs/dev/wowsims-packs.md): Garrote a stealth-window cast; Slice and Dice and Rupture both at 1, so they
    -- sort by soonest; Venom none (the user, 2026-10-21)
    focus = { garrote = 1, slice_and_dice = 1, rupture = 1 },
    leveling = {},
}
