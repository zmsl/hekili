-- tools/wowsims/specs/warrior_fury.lua (wowsims packs plan, Task 6): Fury (wowsims.com)'s wowsims/forever request and
-- translation. Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warrior/dps/presets.ts
-- (FuryTalents :73, DefaultOptions :143-152, OtherDefaults :169-175) at the pin; gear p1_fury (a level 60 dual-wield set).
-- Since the user's Berserker Rage ruling (2026-10-21; recipe `requires`): floor 0.91, on-GCD 0.917 (60): the build has no
-- Improved Berserker Rage, so the pre-pull Berserker Rage wowsims casts at -4.5 is gated off (berserker_rage ->
-- battle_shout at -4.50, a ruled deviation). Before it:
-- Disagreements (P7; floor 0.93, final): decisions on-GCD 0.933 (60) top [sunder_armor -> bloodthirst 2; death_wish ->
-- sunder_armor 1; overpower -> bloodthirst 1] after central fixes 7, 13 and 16 (0.817 before, with GAP AD: precombat's
-- in-combat filter did not reach pre_pull_move, so Intercept showed all fight; fix 16 closed it). Each disagreement
-- once, wowsims -> ours, at the log's time: sunder_armor -> bloodthirst (89.82): our Sunder stacks read 5 where
-- wowsims's are 4: fix 7 undoes the Sunder missed at 81.32, but the one missed at 86.82, 0.04 s after our off-hand
-- swing, is never attributed to our cast, so its stack stays (believed 4 while the client lists 3 from 86.82; the
-- belief re-reads stacks only on an aura change): shared gap (the avoid's attribution, lane report); sunder_armor -> bloodthirst (133.04): a same-instant crit swing's rage (replay
-- limit, landing lag); overpower -> bloodthirst (69.51): believed rage 0.0 under the truth's 10.8: an
-- off-hand crit (67.90, +9.86) and our Whirlwind (67.91, 25) in one frame leave the belief at 0.0 against the truth's
-- 4.88 for 1.6 s (the crit's extra step is not credited after the cast's success lift: shared gap, lane report), then
-- the off-hand swing at 69.42 lands 0.09 s before the cast (replay limit, landing lag). Unbridled Wrath's procs (1 rage
-- a proc) are the kit's measured ~7.5% a rank (Warrior.lua rageOf); wowsims procs 85 of 140 landed white hits (60%,
-- the tooltip): wowsims quirk, kept (Forever measured);
-- death_wish -> sunder_armor (0.00): wowsims is 6 yd away after Intercept's travel and cannot Sunder yet; the engine
-- does not gate Sunder on melee range (replay limit). Fix 16 cleared 57.09, 67.91, 76.16, 117.06 and 138.30; 62.81
-- and 88.32 no longer disagree.
-- Leveling: Sunder Armor below 5 stacks while Bloodthirst is unlearned (levels 10-40 idled 7.4 s and 8.2 s over the
-- 60 bracket's 6.8 s with only Rend's or Whirlwind's wait left); silent at 60. At 5 stacks it stays silent (fix 18).
-- Hamstring out of Battle Stance while Bloodthirst is unlearned: from 30 the list holds Berserker Stance, where Rend,
-- Overpower and Thunder Clap cannot go, so the GCD idled pooling rage for Heroic Strike (L40 8.6 s, L30 over 20 s in
-- scratch runs) -> L40 2.4 s. Below 30 (Battle Stance) it stays silent, so the level 24 loop does not move; at 60 too.
-- The stance test reads Battle Stance in the leveling check's guard form (a known-guard that drops the term).
-- Replay knobs (tests/Forever/wowsims_warrior_spec.lua): Whirlwind's off-hand hit (1680 Tag 2) is a hit, not a cast;
-- the Heroic Strike queue (25286 Tag 1) is an aura the client never shows; the main hand's 2.1 s period (the log's
-- first two main-hand swings are 4.2 s apart: Heroic Strike replaced one).
-- Automatic cooldowns (rule 13): cd_trinkets's castAllStatBuffCooldowns cast nothing in the log: no lines.
return {
    class = "WARRIOR",
    pack = "Fury (wowsims.com)",
    spec = "fury",
    name = "Fury",
    talentTree = "warrior",
    apl = "ui/specs/warrior/dps/apls/fury.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassWarrior",
        gear = "ui/specs/warrior/dps/gear_sets/p1_fury.gear.json",
        talentsString = "30305013002-25053005052010501",
        specKey = "dpsWarrior",
        options = {
            classOptions = {
                queueDelay = 250,
                startingRage = 50,
                useBattleShout = true,
                defaultStance = "WarriorStanceBerserker",
                hasBsT2 = true,
                stanceSnapshot = true,
            },
        },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100,
        distanceFromTarget = 25,
    },
    -- player-facing lines of the in-game description (the user's audit rulings, 2026-10-21)
    notes = {
        "Cooldowns toggle hides: Death Wish, Recklessness (also behind its pack setting, off by default), Sweeping Strikes and the racials (Blood Fury, Berserking, Eureka, Elune's Light).",
        "No line here sits under the Potions or Defensives toggles.",
        "Rend is used on every target, boss or not.",
    },
    executePhase = "execute_phase",
    -- the user's ruling (2026-10-21): Berserker Rage only "if talented for the rage gain", precombat and in combat
    requires = { berserker_rage = "improved_berserker_rage" },
    map = { [12723] = "sweeping_strikes" }, -- Sweeping Strikes's effect id (wowdb); the kit's ability is 12292
    -- the user's tiers (2026-10-21): Bloodthirst and Whirlwind rotational (untiered); Overpower 1; Heroic Strike and
    -- Cleave alike, { 1, 2 } ("those abilities are kind of the same"; Fury has one Cleave line, so it takes 1); Rend 2
    -- (the rend weave); Battle Stance 1 (overpower_weaving's swap, Fury's only Battle Stance line). A tier is static:
    -- the weave's lines carry theirs whether Rend Weave is on or off.
    focus = { overpower = 1, heroic_strike = { 1, 2 }, cleave = { 1, 2 }, rend = 2, battle_stance = 1 },
    -- the user's ruling (2026-10-21): "guard against recommending battle stance if there won't be enough time or rage
    -- to cast overpower". wowsims's swap (overpower_weaving #2: Overpower: Can Cast, i.e. the Delay Check, not the
    -- execute phase, the window up with 5 <= rage <= 100, and gcd 0) checks the rage before the swap only: below
    -- Tactical Mastery (level 14; Overpower is 12) the swap keeps no rage, and it never reads Overpower's 5 s cooldown
    -- against the 5 s window. The guard: the rage a swap keeps (the kit's stance_rage_kept: Tactical Mastery's 10, its
    -- improvement's 15 a rank) pays for Overpower, and Overpower is ready before the window closes. A deviation
    -- (docs/dev/wowsims-packs.md).
    guard = {
        battle_stance = "!action.overpower.known|(stance_rage_kept>=action.overpower.cost"
            .. "&cooldown.overpower.remains<buff.overpower_ready.remains)",
    },
    leveling = {
        "sunder_armor,if=!action.bloodthirst.known&debuff.sunder_armor.stack<5",
        "hamstring,if=!action.bloodthirst.known&(!action.battle_stance.known|!buff.battle_stance.up)",
    },
    -- extra (content outside wowsims's model): Victory Rush; wowsims never goes mob to mob, so its kill window never
    -- opens there. The user's ruling (2026-10-21): "just above bloodthirst (since it's a mini bloodthirst)". The bare
    -- line: the kit's usable already refuses it outside Victorious.
    extra = { { before = "bloodthirst", line = "victory_rush" } },
}
