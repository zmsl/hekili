-- tools/wowsims/specs/warrior_arms.lua (wowsims packs plan, Task 5): Arms (wowsims.com)'s wowsims/forever request and
-- translation. Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warrior/dps/presets.ts
-- (ArmsTalents :102, DefaultOptions :143-152, OtherDefaults :169-175) at the pin; gear p1_arms (the spike's, a level
-- 60 set; the presets' default is the Fury build).
-- Disagreements worked (P7; floor 0.86, provisional until central fix 7, ruling L10): decisions on-GCD 0.866 (67) top
-- [execute -> overpower 1; execute -> sunder_armor 1; mortal_strike -> slam 1] on the tree after fixes 6/8/C, 9, 9b,
-- 10, 10b and 11 (0.836 before fix 6), with Improved Slam (12862) and Anger Management's 1.5 rage per 5 s (12296, DB2
-- aura 85) modelled in the kit and the replay character at the build's 3.8 s Arcanite Reaper. Each disagreement once,
-- wowsims -> ours, at the log's time:
-- 1. execute -> overpower (165.08): the believed rage under Execute's 15; wowsims refunds 80% of an avoided ability's
--    rage (the log's OtherID 8: Overpower's 4 at 161.18), our belief none yet: shared gap A, central fix 7 (outcome
--    belief, refundOnAvoid). (provisional: fix 7)
-- 2. execute -> sunder_armor (171.08): wowsims casts on the white swing's 17.1 rage logged at the same instant; the
--    replay lands the swing one landing lag later (fix 6's M.LAND, as the client hears it), so at the decision the
--    rage is 8.5 and the forecast reaches Execute's 15 only after Sunder's stacks run out (174.48): replay limit
--    (landing lag). The believed rage there follows the refund wowsims paid at 165.08. (provisional: fix 7)
-- 3. mortal_strike -> slam (110.28): the same landing lag (a 30.2-rage crit swing logged with the Mortal Strike;
--    truth 4.7 at the decision; no avoid since 76.58): replay limit (landing lag).
-- Others: sunder_armor -> rend (7.58) a dodged Sunder (3.08) counted as a stack (shared gap A, fix 7 restores the
-- auras on an avoid; provisional: fix 7); spearing_strike -> sunder_armor (34.28) the landing lag of a same-instant
-- swing (replay limit); rend -> slam (78.08) a missed Rend (76.58) kept up (shared gap A; provisional: fix 7);
-- overpower -> sunder_armor (79.98) Bloodthrill's proc (1289682) opens the hidden window 0.09 s before the cast, seen
-- only by usability (replay limit, the 0.2 s tick); slam -> mortal_strike (64.08) and sunder_armor -> overpower
-- (177.88) not worked. Fix 6 cleared 45.68, 60.88 and 102.68 (the belief's rage at a same-instant swing, gap B).
-- Pre-pull (prepull_at): Berserker Rage at -4.5 and Battle Shout at -3 are on-GCD decisions and agree; Battle Stance,
-- Bloodrage, Charge and Blood Fury are off the GCD (not scored).
-- Automatic cooldowns (rule 13): cd_trinkets's two castAllStatBuffCooldowns entries cast nothing in the log (no
-- stat-buff cooldown in this gear): no lines; GAP 14 (autocastOtherCooldowns) costs Arms nothing (none in its APL).
-- Not a deviation: Blood Fury's cooldown is the DB2's 120 s; wowsims holds it to 180 s (queued at 3m), so from 120 s
-- our off-GCD icon shows it while wowsims waits (off the GCD: not scored).
return {
    class = "WARRIOR",
    pack = "Arms (wowsims.com)",
    spec = "arms",
    name = "Arms",
    talentTree = "warrior",
    apl = "ui/specs/warrior/dps/apls/arms.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassWarrior",
        gear = "ui/specs/warrior/dps/gear_sets/p1_arms.gear.json",
        talentsString = "30325213132515201-0505-2",
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
    focus = { overpower = 1, rend = 2, slam = 2 }, -- the retired Arms list's tiers (P9.3)
    leveling = {
        "heroic_strike,use_off_gcd=1,if=!action.mortal_strike.known&rage.current>=30",
        "thunder_clap,if=!action.mortal_strike.known&!debuff.thunder_clap.up&rage.current>=40",
        "sunder_armor,if=!action.mortal_strike.known",
    },
}
