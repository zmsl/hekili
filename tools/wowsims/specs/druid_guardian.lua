-- tools/wowsims/specs/druid_guardian.lua: Guardian (wowsims.com)'s wowsims/forever request and translation, at 4b0030a44b.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/druid/feralbear/presets.ts: BearTalents
-- (:16, '050022-2322030212310212501-055', the same string as at e2842f0a78), DefaultOptions (:44-47), OtherDefaults
-- (:78-93: Tauren, Engineering/Enchanting, 25 yd, 250 ms reaction, the healing model below); the APL is
-- apls/adaptive.apl.json (:10, :12 ROTATION_ADAPTIVE "Adaptive Bear"), the gear gear_sets/default.gear.json (:11). The
-- re-pin from e2842f0a78 changed only the APL: b19089ff45 dropped its autocastOtherCooldowns entry (6 lines), so the
-- pack's lines are the old pin's (the translator already omitted that entry).
-- Re-pin e5a9cd2a2d -> e4ef929e54: BearTalents '050022-5023030212310112501-055' (presets.ts:14); the adaptive list
-- rewritten (cbd46412fd, a94dc3c549): 2- and 3-target groups (Swipe, Primal Bite) and single_target_and_larger_packs
-- behind the movement gate, a pre-pull Maul at 3 targets (CN21: its computed aura duration keeps the `!buff.maul.up`
-- guard); the gear file unchanged. Owner deviation L1169 (decision C) is Feral's only: Guardian's groups have no
-- other-target read (CN24) and ship whole.
-- Replay (e4ef929e54, `procs { ["9881:0"] = true }`: Maul's untagged Casting lines are wowsims's queue at each swing):
-- the kit has no rage-from-damage-taken rule (`taken`: CN7's hook, a named gap), so the belief sees only the bear's own
-- rage (white swings, Primal Fury, Enrage): decisions on-GCD 0.574 (115). NAMED GAP (owner ruling 2026-11-07, extended
-- to this pin by the controller, L1319): the shipped kit has no rage from hits taken (CN7; the belief cannot read hit
-- amounts in game, L67); the floor is measured without it. The log's rage by source over 180 s: hits taken 1779.7 of
-- ~2150 (~83%), white swings 101.2 (Maul replaces 64 of 72 swings), Primal Fury 105.0, Enrage 62.0. The re-pinned list
-- spends 15 rage every GCD (Lacerate to 5 stacks, then Lacerate as the filler under Primal Bite), so all 49 misses are
-- one class: the belief's rage 0-12 against a truth of 25-90 (Lacerate / Primal Bite cost 15); with rage believed ~0 the
-- queue waits Primal Bite 3-5 s and a Faerie Fire / Demoralizing Roar refresh due at its believed expiry comes first.
-- By pair (theirs -> ours): lacerate -> primal_bite 30, lacerate -> demoralizing_roar 9, lacerate -> faerie_fire 6,
-- primal_bite -> faerie_fire 2, primal_bite -> demoralizing_roar 1, lacerate -> bear_form 1. Two carry a second cause:
--   121.90 primal_bite -> faerie_fire: Faerie Fire fades 0.05 s after wowsims's Primal Bite (same-instant order:
--   replay limit);
--   178.90 lacerate -> bear_form: the believed Bear Form expiry at the log's end (180.00).
-- With the archived kit rule (lane-feralguardian-taken-wip.patch, scratch, NOT shipped: do not land it blind) the old
-- pin's replay was 0.923 (117) with 14.65/min flicker (off-GCD Maul alternation; oracle 0.00).
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
        talentsString = "050022-5023030212310112501-055",
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
    -- by role (docs/dev/wowsims-packs.md): Maul a rage dump as Heroic Strike, always tier 2, every line (owner ruling
    -- 2026-10-22 extended to Guardian, Fable for the owner 2026-11-17); Lacerate (every line) and Demoralizing Roar at 2
    focus = { maul = 2, lacerate = 2, demoralizing_roar = 2 },
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
