-- tools/wowsims/specs/druid_guardian.lua (wowsims packs plan, Task 7): Guardian (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralbear/presets.ts:16-19
-- (BearTalents), :116-119 (DefaultOptions), :130-135 (OtherDefaults) at d33930d040; the re-pin (e2842f0a78) moves the
-- APL to apls/adaptive.apl.json (presets.ts:10, :12 ROTATION_ADAPTIVE "Adaptive Bear", spec.ts:90 the default
-- rotation; 998 lines); the gear stays gear_sets/default.gear.json (presets.ts:11, spec.ts:75).
-- Replay (P7): decisions on-GCD 0.782 (n 78; 0.718 held in Task 7b, 0.782 after central fixes 12-15), with the replay
-- knob procs { ["9881:0"] = true } (Maul's untagged Casting lines are wowsims's queue at each swing, not casts).
-- Worked (Task 7g): the bear's 11.25 rage a white swing and a crit's 8.65 more (the log's 11.25 and 19.9); Primal
-- Fury's 5 on our crits (16959 in the log) as the strikes' `onCrit`; Berserk ends Primal Bite's cooldown (central fix
-- 14). Neither Primal Fury nor the rage moved a scored decision.
-- 1. lacerate -> primal_bite 10 (wowsims's cast -> our icon): wowsims decides after a white swing landing at the
--    same instant (50.14, 55.14, 100.14, 112.64, 160.14, 175.14: its 11.25 rage then pays Lacerate); the replay lands
--    the swing's rage a landing lag later, so the belief (0-5 rage) shows Primal Bite, the sooner ready (replay limit,
--    shared: tests/Game/harness/replay.lua). The rest (63.89, 68.39, 108.14, 148.14) sit 1-4 rage under Lacerate's 13
--    with the same pending swing.
-- 2. primal_bite -> lacerate 5: the mirror, a same-instant swing (25.14's white crit, 19.9 rage) or Berserk's first
--    Primal Bite (12.64) paying Primal Bite before the belief sees the rage (the same replay limit).
-- 3. lacerate -> demoralizing_roar 2 (65.39, 96.14): Demoralizing Roar's refresh a fraction before its expiry
--    (casts land at completion: replay limit).
-- Translation: `health.pct<20` (Frenzied Regeneration) reads the player's health, full while the game keeps it
-- secret (central fix 12: API-forced, never fires in combat); autocastOtherCooldowns (GAP 14: no class cooldown lost).
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
