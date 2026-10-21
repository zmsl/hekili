-- tools/wowsims/specs/rogue_combat.lua (wowsims packs plan, Task 8): Combat (wowsims.com)'s wowsims/forever request and
-- translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/rogue/dps/presets.ts:30-35
-- (TALENTS_COMBAT_SS, "Combat SS", the default), :163-165 (DefaultOptions), :241-243 (OtherDefaults) and
-- ui/features/settings/model/apply_defaults.ts:68,87-95 (the race, the professions and the reaction time the UI
-- defaults to: the class's first race, Engineering, 100 ms) at the pin. One APL for the three builds
-- (ui/specs/rogue/dps/apls/default.apl.json, "Direct APL"); the talents pick the lines.
-- Translation: the APL's "Use X" variables are constants (inlined and folded, rule 1); omitted (rule 2): Maintain
-- Expose (its call folds to never: "Use Expose Armor" false; its strictSequence, RL3, never reached), autocastOtherCooldowns (#7: rule
-- 13 finds no "Major cooldown used" in the log, so no line), the potion; Thousand Cuts's buff (1310723) resolves from
-- the kit's aura, so `auraIsKnown` of it is the talent. Known deviations (Forever API): remainingTime reads 3600 (time
-- to die unknown), so the "Fight About to End" terms never fire; energy is secret in combat, so an unannounced energize
-- (Rogue Armor Energize 27788, +20) is invisible to the belief until the next read.
-- Disagreements worked (P7; decisions on-GCD 0.944, n 71): sinister_strike -> slice_and_dice 2 (replay limit: Slice and
-- Dice's last 0.4 s at the 75-energy cap threshold, the energize above lowering our forecast; one at the fight's last
-- second); adrenaline_rush -> sinister_strike 1 (the #10 Blood Fury -> Adrenaline Rush strictSequence: wowsims's
-- opener Adrenaline Rush at 64 energy, which the APL's own Adrenaline Rush line (energy <= 50) never allows; gone since
-- central fix 13 translates it (rule 14), 0.958: Adrenaline Rush follows `prev.1.blood_fury` and keeps the sequence's
-- Slice and Dice and readiness terms, not Blood Fury's own readiness, false once it is cast); garrote -> sinister_strike 1 (replay limit: the harness's IsStealthed always answers false, so
-- the Vanish wowsims pressed is invisible; checkpoint).
return {
    class = "ROGUE",
    pack = "Combat (wowsims.com)",
    spec = "combat",
    name = "Combat",
    talentTree = "rogue",
    apl = "ui/specs/rogue/dps/apls/default.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassRogue",
        gear = "ui/specs/rogue/dps/gear_sets/p1_slowmh.gear.json",
        talentsString = "005323101012-32030320201515231",
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
