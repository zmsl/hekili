-- tools/wowsims/specs/rogue_assassination.lua (wowsims packs plan, Task 8): Assassination (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/rogue/dps/presets.ts:18-23
-- (TALENTS_MUTILATE_ASN, "Asn Muti"), :163-165 (DefaultOptions), :241-243 (OtherDefaults) and
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
-- Disagreements worked (P7; decisions on-GCD 0.982, n 57): mutilate -> venom 1 (wowsims quirk: Venom fades on the
-- Mutilate's own timestamp and wowsims's 100 ms reaction time, includeReactionTime, which rule 5 ignores, still sees it
-- up). Nothing else disagrees.
return {
    class = "ROGUE",
    pack = "Assassination (wowsims.com)",
    spec = "assassination",
    name = "Assassination",
    talentTree = "rogue",
    apl = "ui/specs/rogue/dps/apls/default.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassRogue",
        gear = "ui/specs/rogue/dps/gear_sets/p1_muti.gear.json",
        talentsString = "00532310151501031-302303202014",
        specKey = "rogue",
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) }, -- an empty message (dkjson: {} is [])
        profession1 = "Engineering",
        reactionTimeMs = 100,
        distanceFromTarget = 5,
    },
    map = {},
    -- by role (docs/dev/wowsims-packs.md); Slice and Dice arguable
    focus = { ambush = 1, slice_and_dice = 1, rupture = 2 },
    leveling = {},
}
