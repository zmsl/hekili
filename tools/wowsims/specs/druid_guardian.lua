-- tools/wowsims/specs/druid_guardian.lua: Guardian (wowsims.com)'s wowsims/forever request and translation, at 4b0030a44b.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralbear/presets.ts: BearTalents
-- (:16, '050022-2322030212310212501-055', the same string as at e2842f0a78), DefaultOptions (:44-47), OtherDefaults
-- (:78-93: Tauren, Engineering/Enchanting, 25 yd, 250 ms reaction, the healing model below); the APL is
-- apls/adaptive.apl.json (:10, :12 ROTATION_ADAPTIVE "Adaptive Bear"), the gear gear_sets/default.gear.json (:11). The
-- re-pin from e2842f0a78 changed only the APL: b19089ff45 dropped its autocastOtherCooldowns entry (6 lines), so the
-- pack's lines are the old pin's (the translator already omitted that entry).
-- Replay (4b0030a44b, `procs { ["9881:0"] = true }`: Maul's untagged Casting lines are wowsims's queue at each swing):
-- the kit has no rage-from-damage-taken rule (`taken`: CN7's hook, a named gap), so the belief sees only the bear's own
-- rage (white swings, Primal Fury, Enrage): decisions on-GCD 0.632 (117). NAMED GAP (owner ruling 2026-11-07): the
-- shipped kit has no rage from hits taken (CN7; the belief cannot read hit amounts in game, L67); the floor is measured
-- without it (fresh-floor rule waived for this one cause). With the archived kit rule (lane-feralguardian-taken-wip.patch,
-- scratch, NOT shipped: do not land it blind) the replay is 0.923 (117) once CN7 and CN9 (the Druid world's rage knob)
-- land, but its replay flicker is 14.65/min (off-GCD Maul alternation; oracle 0.00). 9 misses with it, none a pack
-- line, by log time:
--   8.95 lacerate -> primal_bite, 10.45 primal_bite -> lacerate, 18.20 primal_bite -> lacerate, 23.95 lacerate ->
--   primal_bite, 38.20 primal_bite -> lacerate, 151.20 primal_bite -> lacerate: the belief's rage lo sits under the
--   true rage at Lacerate's 15 / Primal Bite's 18 (truth 15-34, lo 1.6-17.8: the hits' rage is an estimate band);
--   120.70 barkskin: `health.pct<=60` reads the player's health, secret in game (API-forced, as Frenzied Regeneration);
--   122.20 lacerate -> faerie_fire: Faerie Fire fades at 122.20, the instant wowsims casts Lacerate and recasts Faerie
--   Fire at 123.70 (same-instant order: replay limit);
--   179.70 lacerate -> bear_form: the fight's last decision, UNTRACED (the log ends at 180.00).
-- Worked (Task 7g): the bear's 11.25 rage a white swing and a crit's 8.65 more; Primal Fury's 5 on our crits (16959) as
-- the strikes' `onCrit`.
-- Translation: `health.pct<25` (Frenzied Regeneration) and `<=60` (Barkskin) read the player's health, full while the
-- game keeps it secret (API-forced, never fire in combat).
-- Sim-setup difference (ruling L16): wowsims's sim starts in Dire Bear Form (its pre-pull) and its list never shifts, so out of form
-- the list showed nothing; the `bear_form` line (the Feral APL's own cat_form pattern) never fires in the replay.
return {
    class = "DRUID",
    pack = "Guardian (wowsims.com)",
    spec = "guardian",
    name = "Guardian",
    talentTree = "druid",
    apl = "ui/specs/druid/feralbear/apls/adaptive.apl.json",
    player = {
        race = "RaceTauren",
        class = "ClassDruid",
        gear = "ui/specs/druid/feralbear/gear_sets/default.gear.json",
        talentsString = "050022-2322030212310212501-055",
        specKey = "feralBearDruid",
        options = { startingRage = 0, assumeBleedActive = true },
        profession1 = "Engineering",
        profession2 = "Enchanting",
        reactionTimeMs = 250,
        distanceFromTarget = 25,
    },
    -- a tank: the raid's tank (the target swings at it) and presets.ts:55-69's healing model (apply_defaults.ts:108-125)
    tank = true,
    healingModel = {
        hps = 2200,
        cadenceSeconds = 0.4,
        cadenceVariation = 1.2,
        absorbFrac = 0.02,
        burstWindow = 6,
        inspirationUptime = 0.25,
    },
    executePhase = "execute_phase",
    map = {},
    -- Faerie Fire's armor and Demoralizing Roar's attack power are exclusive effects (wowsims
    -- sim/core/debuffs_generated_test.go:326 with Curse of Recklessness, :446 with Demoralizing Shout): rule 10
    exclusive = { [9907] = true, [9898] = true },
    -- by role (docs/dev/wowsims-packs.md): Maul a rage dump as Heroic Strike ({ 1, 2 } by line; the leveling Maul,
    -- a literal, the second at 2); Lacerate (both lines) and Demoralizing Roar at 2
    focus = { maul = { 1, 2 }, lacerate = 2, demoralizing_roar = 2 },
    -- Before Primal Bite Maul is the only rage sink: queued whenever affordable instead of at
    -- wowsims's 20, which pools for the on-GCD strikes a low-level bear lacks (ruling L18; silent once Primal Bite is
    -- known). The re-pin's adaptive list maintains Faerie Fire (#14) and Demoralizing Roar (#16, "Attack-power reduction
    -- is covered") itself, whenever the debuff is down and at every level, above every strike: the leveling Roar and
    -- Faerie Fire lines R45 guarded were dead behind them and are gone (L47).
    -- Rule 15: the raid debuff, a setting off in game and on in the harness (the user's ruling, 2026-10-21)
    maintenance = { demoralizing_roar = "maintain_demoralizing_roar" },
    leveling = { "maul,use_off_gcd=1,focus=2,if=!action.primal_bite.known" },
    -- wowsims's sim starts in Dire Bear Form (its pre-pull shift only with Furor under 10 rage): the form first, as
    -- Balance's Moonkin Form (ruling L16); the re-pin's Faerie Fire line has no form gate, so a trailing line came after
    -- it. Silent in the replay (the log is in Bear Form from the pre-pull on).
    levelingFirst = { "bear_form,if=!buff.bear_form.up" },
}
