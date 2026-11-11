-- tools/wowsims/specs/rogue_combat.lua (wowsims packs plan, Task 8): Combat (wowsims.com)'s wowsims/forever request and
-- translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/rogue/dps/presets.ts:30-35
-- (TALENTS_COMBAT_SS, "Combat SS", the default), :163-165 (DefaultOptions), :241-243 (OtherDefaults) and
-- ui/features/settings/model/apply_defaults.ts:68,87-95 (the race, the professions and the reaction time the UI
-- defaults to: the class's first race, Engineering, 100 ms) at the pin. One APL for the three builds
-- (ui/specs/rogue/dps/apls/default.apl.json, "Direct APL"), played as the build plays it: the build is TypeSimple
-- (spec.ts:82) with presets.ts:57 DEFAULT_SIMPLE_ROTATION (:58 SIMPLE_ROTATION; useBackstab and useExposeArmor false), whose simpleRotation writes
-- those two variables over the raw APL (spec.ts:186-204); the recipe's `vars` does the same (ruling R29: the raw APL
-- has Use Backstab true since upstream 0dbe35317d, a Backstab rotation unlike the build). The talents and the build's `vars` pick the lines.
-- Translation: the APL's "Use X" variables are constants (inlined and folded, rule 1); omitted (rule 2): Maintain
-- Expose (its call folds to never: "Use Expose Armor" false; its strictSequence, RL3, never reached), autocastOtherCooldowns (#7: rule
-- 13 finds no "Major cooldown used" in the log, so no line), the potion; the pin's APL no longer reads Thousand Cuts's buff (1310723), and the pack has neither it nor the talent. Known deviations (Forever API): remainingTime reads 3600 (time
-- to die unknown), so the "Fight About to End" terms never fire; energy is secret in combat, so an unannounced energize
-- (Rogue Armor Energize 27788, +20) is invisible to the belief until the next read.
-- At the old pin d33930d0, disagreements worked (P7; decisions on-GCD 0.944, n 71): sinister_strike -> slice_and_dice 2 (replay limit: Slice and
-- Dice's last 0.4 s at the 75-energy cap threshold, the energize above lowering our forecast; one at the fight's last
-- second); adrenaline_rush -> sinister_strike 1 (the #10 Blood Fury -> Adrenaline Rush strictSequence: wowsims's
-- opener Adrenaline Rush at 64 energy, which the APL's own Adrenaline Rush line (energy <= 50) never allows; gone since
-- central fix 13 translates it (rule 14), 0.958: Adrenaline Rush follows `prev.1.blood_fury` and keeps the sequence's
-- Slice and Dice and readiness terms, not Blood Fury's own readiness, false once it is cast); garrote -> sinister_strike 1 (replay limit: the harness's IsStealthed always answers false, so
-- the Vanish wowsims pressed is invisible; checkpoint).
-- Re-pin e2842f0a78 (Task 13): omitted 7 -> 9 (the Energy Pooling Checks waitUntil and its group, Gnome-gated: see
-- rogue_assassination.lua; Gnome A/B 1.000 (68)). Rogue Armor Energize 27788 in the log 6 times (old 2). No untagged
-- GCD-0 kit cast in the log (Hack and Slash's extra swings are OtherID 3 melee).
-- Disagreements (P7; floor 0.95 -> 0.97, decisions on-GCD 0.973, n 73): sinister_strike -> slice_and_dice 13.86
-- (Slice and Dice 0.19 s from its end, the old header's class); eviscerate -> sinister_strike 176.62 (the fight's last
-- 6 s, gap AN). Regen/pool not refreshed (as Assassination).
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
        talentsString = "00530320201-3200132202012321551",
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
    -- Riposte (owner ruling R70, 2026-11-06: "add it to the apl and make it focus=1"): not from wowsims, which never plays it
    -- (its fight has no parry on us; at 4b0030a44b the Combat SS build does not even take the talent). Off the global
    -- cooldown, so it leads the list (anchored on Garrote, the first line left once upstream dropped its Ambush opener:
    -- L143); it is a reaction to a parry, a real need (R41), and shows only in the 5 s `window.riposte` (Rogue.lua: the
    -- client's usability answer, L138), which the ability's own `usable` reads, so the line carries the energy term only;
    -- skipped for a Rogue without the talent. Tier 1 in the line itself, as Victory Rush.
    extra = {
        {
            before = "garrote",
            line = "riposte,use_off_gcd=1,focus=1,if=energy.lo>=action.riposte.cost",
        },
    },
}
