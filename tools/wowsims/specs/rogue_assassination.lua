-- tools/wowsims/specs/rogue_assassination.lua (wowsims packs plan, Task 8): Assassination (wowsims.com)'s
-- wowsims/forever request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/rogue/dps/presets.ts:18-23
-- (TALENTS_MUTILATE_ASN, "Asn Muti"), :163-165 (DefaultOptions), :241-243 (OtherDefaults) and
-- ui/features/settings/model/apply_defaults.ts:68,87-95 (the race, the professions and the reaction time the UI
-- defaults to: the class's first race, Engineering, 100 ms) at the pin. One APL for the three builds
-- (ui/specs/rogue/dps/apls/default.apl.json, "Direct APL"), played as the build plays it: the build is TypeSimple
-- (spec.ts:82) with presets.ts:57 DEFAULT_SIMPLE_ROTATION (:58 SIMPLE_ROTATION; useBackstab and useExposeArmor false), whose simpleRotation writes
-- those two variables over the raw APL (spec.ts:186-204); the recipe's `vars` does the same (ruling R29: the raw APL
-- has Use Backstab true since upstream 0dbe35317d, a Backstab rotation unlike the build). The talents and the build's `vars` pick the lines.
-- Translation: the APL's "Use X" variables are constants (inlined and folded, rule 1); omitted (rule 2): Maintain
-- Expose (its call folds to never: "Use Expose Armor" false; its strictSequence, RL3, never reached), autocastOtherCooldowns
-- (#7: rule 13, no "Major cooldown used" in the log), the potion; the pin's APL no longer reads Thousand Cuts's buff (1310723), and the pack has neither it nor the talent. The Orc's Blood Fury -> Adrenaline Rush strictSequence (#10) is rule 14's
-- two lines since central fix 13 (Adrenaline Rush unlearned here: the Blood Fury line alone). Known deviations (Forever API): remainingTime reads 3600 (time to die unknown),
-- so the "Fight About to End" terms never fire; energy is secret in combat, so an unannounced energize (Rogue Armor
-- Energize 27788, +20) is invisible to the belief until the next read.
-- At the old pin d33930d0, disagreements worked (P7; decisions on-GCD 0.982, n 57): mutilate -> venom 1 (wowsims quirk: Venom fades on the
-- Mutilate's own timestamp and wowsims's 100 ms reaction time, includeReactionTime, which rule 5 ignores, still sees it
-- up). Nothing else disagrees.
-- Re-pin e2842f0a78 (Task 13): omitted 7 -> 9 (dry: 9 of 27 lines, waitUntil 0 outside the group): + the "Energy
-- Pooling Checks" group's strictSequence of one waitUntil (`currentEnergy >= 90`) and the then-empty group. Its gate,
-- "Gnome Eureka - Should Cast", needs the Gnome racial Eureka (spellIsKnown 1259812), so it holds nothing in this Human
-- fight. Not carried onto the lines it holds (spec section 3; ruling R37): the translator has no carry, and the gate
-- is Gnome-only (no scored decision can fall in a hold: the replay scores only wowsims's casts). A Gnome A/B of this request (same CLI, scratch) pools before Eureka (no casts 120-128.28, Eureka at 90 energy)
-- and replays 0.982 (56) [eviscerate -> venom 1, the fight's end] on this pack; Combat's Gnome A/B 1.000 (68). A
-- carried `energy.lo>=90` would be forecast (Engine/Sim/Scripts.lua `.lo` recheck, timeToLo; near_cost_spec).
-- Affords: the builders' "SnD + builder" term is `energy.lo>(action.slice_and_dice.cost+action.<builder>.cost)`.
-- Rogue Armor Energize 27788 in the log 10 times (darkmantle-set-512.patch; 4 Darkmantle pieces). Mutilate's hand
-- hits stay procs; no other untagged GCD-0 cast in the log is a kit ability (Brain Damage 1290950 is the
-- Lobotomizer's proc, unmapped).
-- Disagreements (P7; floor 0.98 -> 0.93, decisions on-GCD 0.932, n 59): slice_and_dice shown, wowsims eviscerate
-- 174.06 / 179.66 and mutilate 178.66: the fight's last 6 s ("Fight About to End": SnD and its clip skipped,
-- Eviscerate at 3 points; remainingTime reads 3600, gap AN, API); venom -> slice_and_dice 80.69: wowsims casts Venom at
-- exactly 25 energy after the unseen 27788 at 79.25 (belief lo 13.1, truth 25). Without the three fight-end misses 0.949.
-- Regen/pool: the log's 10 a tick and 100 max; kit and world unchanged (not refreshed, lanes 10-12 precedent).
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
        talentsString = "00530311231251031-32030302020103-001",
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
