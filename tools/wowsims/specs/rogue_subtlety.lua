-- tools/wowsims/specs/rogue_subtlety.lua (wowsims packs plan, Task 8): Subtlety (wowsims.com)'s wowsims/forever request
-- and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/rogue/dps/presets.ts:42-47
-- (TALENTS_SUB_HEMO, "Subtlety Hemo"), :163-165 (DefaultOptions), :241-243 (OtherDefaults) and
-- ui/features/settings/model/apply_defaults.ts:68,87-95 (the race, the professions and the reaction time the UI
-- defaults to: the class's first race, Engineering, 100 ms) at the pin. One APL for the three builds
-- (ui/specs/rogue/dps/apls/default.apl.json, "Direct APL"); the talents pick the lines.
-- Translation: the APL's "Use X" variables are constants (inlined and folded, rule 1); omitted (rule 2): Maintain
-- Expose (its call folds to never: "Use Expose Armor" false; its strictSequence, RL3, never reached), autocastOtherCooldowns
-- (#7: rule 13, no "Major cooldown used" in the log), the potion; Thousand Cuts's buff (1310723) resolves from the kit's aura, so
-- `auraIsKnown` of it is the talent. The Orc's Blood Fury -> Adrenaline Rush strictSequence (#10) is rule 14's
-- two lines since central fix 13 (Adrenaline Rush unlearned here: the Blood Fury line alone). Known deviations (Forever API): remainingTime reads 3600 (time to die unknown),
-- so the "Fight About to End" terms never fire; energy is secret in combat, so an unannounced energize (Rogue Armor
-- Energize 27788, +20) is invisible to the belief until the next read.
-- Disagreements worked (P7; decisions on-GCD 0.939, n 82): hemorrhage -> rupture 4 (Thousand Cuts's stacks and
-- Hemorrhage's cost: the belief's energy without the unannounced energize above); eviscerate -> rupture 1 (the same
-- energize: wowsims at 75.6 energy, our belief 60). The pre-rebase hemorrhage -> garrote 7 (the opener's Garrote) went
-- away with the central fixes (fix 6's energy belief).
-- Kit fixes from this replay (P6): Dirty Deeds (Garrote 30 at 2/2), Thousand Cuts's -3 a stack on Hemorrhage and
-- Backstab, Improved Sinister Strike's -5 as the whole talent's (Combat's Sinister Strike 40).
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
        talentsString = "005323101014--4323200300013211501",
        specKey = "rogue",
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) }, -- an empty message (dkjson: {} is [])
        profession1 = "Engineering",
        reactionTimeMs = 100,
        distanceFromTarget = 5,
    },
    map = {},
    -- the retired list's tiers (P9.3)
    focus = { kick = 1, expose_armor = 2, slice_and_dice = 1, ambush = 1, rupture = 2 },
    leveling = {},
}
