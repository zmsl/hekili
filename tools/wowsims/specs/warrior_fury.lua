-- tools/wowsims/specs/warrior_fury.lua (wowsims packs plan, Task 6): Fury (wowsims.com)'s wowsims/forever request and
-- translation. Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warrior/dps/presets.ts
-- (FuryTalents :73, DefaultOptions :143-152, OtherDefaults :169-175) at the pin; gear p1_fury (a level 60 dual-wield set).
-- Disagreements (P7; floor 0.81, provisional until central fixes 16 and 7): decisions on-GCD 0.817 (60) top
-- [sunder_armor -> bloodthirst 3; whirlwind -> bloodthirst 3; bloodthirst -> sunder_armor 1]. GAP AD (central fix 16):
-- precombat's in-combat filter does not reach pre_pull_move, so Intercept (off-GCD, usable in combat in Berserker
-- Stance) shows all fight and the forecast pays its 10 rage first; 0.883 (60) measured without it. Each disagreement
-- once, wowsims -> ours, at the log's time: whirlwind -> bloodthirst (57.09, 67.91, 138.30), bloodthirst ->
-- sunder_armor (76.16), whirlwind -> sunder_armor (117.06): GAP AD, on top of a gain just before the cast (Bloodrage's
-- +10, a same-instant or 0.02 s earlier swing) that reaches the client one usability delay or landing lag later
-- (replay limit); sunder_armor -> bloodthirst (88.32, 89.82): Sunders missed at 81.32 and 86.82 counted as stacks
-- (shared gap A; provisional: fix 7); sunder_armor -> bloodthirst (133.04): a same-instant crit swing's rage (replay
-- limit, landing lag); overpower -> bloodthirst (69.51): the believed rage still under 67.91's misread (provisional:
-- fix 7); rend -> bloodthirst (62.81): not worked; death_wish -> sunder_armor (0.00): wowsims is 6 yd away after
-- Intercept's travel and cannot Sunder yet; the engine does not gate Sunder on melee range (replay limit).
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
    executePhase = "execute_phase",
    map = { [12723] = "sweeping_strikes" }, -- Sweeping Strikes's effect id (wowdb); the kit's ability is 12292
    -- the retired Fury list's tiers in order (P9.3)
    focus = { victory_rush = 1, overpower = 1, revenge = 1, heroic_strike = { 1, 2 }, cleave = { 1, 2 } },
    leveling = {},
}
