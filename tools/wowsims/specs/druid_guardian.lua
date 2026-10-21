-- tools/wowsims/specs/druid_guardian.lua (wowsims packs plan, Task 7): Guardian (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralbear/presets.ts:16-19
-- (BearTalents), :116-119 (DefaultOptions), :130-135 (OtherDefaults) at the pin.
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
-- Sim-setup difference (ruling L16): wowsims's sim starts in Dire Bear Form and its list never shifts, so out of form
-- the list showed nothing; the `bear_form` line (the Feral APL's own cat_form pattern) never fires in the replay.
return {
    class = "DRUID",
    pack = "Guardian (wowsims.com)",
    spec = "guardian",
    name = "Guardian",
    talentTree = "druid",
    apl = "ui/specs/druid/feralbear/apls/default.apl.json",
    player = {
        race = "RaceNightElf",
        class = "ClassDruid",
        gear = "ui/specs/druid/feralbear/gear_sets/default.gear.json",
        talentsString = "0500220000000000-55200322120132012551-0000000000000000",
        specKey = "feralBearDruid",
        options = { startingRage = 0, assumeBleedActive = true },
        profession1 = "Engineering",
        profession2 = "Enchanting",
        reactionTimeMs = 250,
        distanceFromTarget = 0,
    },
    executePhase = "execute_phase",
    map = {},
    focus = { lacerate = 2 }, -- the retired Guardian list's tier (P9.3)
    -- Before Primal Bite (25) Maul is the only rage sink: queued whenever affordable instead of at wowsims's 20, which
    -- pools for the on-GCD strikes a level 10 bear lacks (ruling L18; silent at 60). Before Lacerate (42), wowsims's
    -- 13-rage filler between Primal Bites, the bear waits for Primal Bite (L40 9.6 s, L10 7.2 s on central fix 22):
    -- Demoralizing Roar fills the GCD with 10 rage, Faerie Fire (Feral, free; learned at 30) below it, after a run of
    -- avoided swings (both silent at 60: Lacerate is known).
    leveling = {
        "maul,use_off_gcd=1,if=!action.primal_bite.known",
        "demoralizing_roar,if=!action.lacerate.known&(!action.primal_bite.known|cooldown.primal_bite.remains>gcd.max|rage.current<action.primal_bite.cost)",
        "faerie_fire,if=!action.lacerate.known&(!action.primal_bite.known|cooldown.primal_bite.remains>gcd.max|rage.current<action.primal_bite.cost)",
        "bear_form,if=!buff.bear_form.up",
    },
}
