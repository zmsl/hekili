-- tools/wowsims/specs/warrior_arms.lua (wowsims packs plan, Task 5): Arms (wowsims.com)'s wowsims/forever request and
-- translation. Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warrior/dps/presets.ts
-- (ArmsTalents :102, DefaultOptions :143-152, OtherDefaults :169-175) at the pin; gear p1_arms (the spike's, a level
-- 60 set; the presets' default is the Fury build).
-- Disagreements worked (P7; floor 0.83, re-floored after the shared fixes): decisions on-GCD 0.836 (67) top
-- [sunder_armor -> rend 2; execute -> overpower 1; execute -> sunder_armor 1] with Improved Slam (12862) and Anger
-- Management's 1.5 rage per 5 s (12296, DB2 aura 85) modelled in the kit and the replay character at the build's 3.8 s
-- Arcanite Reaper.
-- 1. sunder_armor -> rend: a dodged Sunder (3.08) counted as a stack by the belief (Sunder's `now` runs at the cast;
--    the target's auras are unreadable in combat): shared gap pending (fix 6/7), A: the belief has no own-ability
--    avoid outcome. The others are B (3.).
-- 2. execute -> overpower (165.08): the believed rage 13.5 against wowsims's 15: wowsims refunds 80% of an avoided
--    ability's rage (the log's OtherID 8: Overpower's 4 at 161.18): shared gap pending (fix 6/7), A.
-- 3. execute -> sunder_armor (171.08), and 34.28, 45.68, 60.88, 64.08, 102.68, 110.28: wowsims casts on the rage of
--    the white swing logged at the same instant; our belief is pinned under the next ability's cost at that decision
--    (45.68: est 9.99, truth 21.996): shared gap pending (fix 6/7), B: the belief's usability pin or the harness's
--    usability rows at the decision.
-- Others: rend -> slam (78.08) a missed Rend kept up (shared gap pending (fix 6/7), A); overpower -> sunder_armor
-- (79.98) Bloodthrill's proc (1289682) opens the hidden window 0.09 s before the cast, seen only by usability (replay
-- limit, the 0.2 s tick).
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
