-- tools/wowsims/specs/warrior_arms.lua (wowsims packs plan, Task 5): Arms (wowsims.com)'s wowsims/forever request and
-- translation. Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/warrior/dps/presets.ts
-- (ArmsTalents :102, DefaultOptions :143-152, OtherDefaults :169-175) at the pin; gear p1_arms (the spike's, a level
-- 60 set; the presets' default is the Fury build).
-- Since the user's Berserker Rage ruling (2026-10-21; recipe `requires`): floor 0.89, on-GCD 0.896 (67): the build has no
-- Improved Berserker Rage, so the pre-pull Berserker Rage wowsims casts at -4.5 is gated off (berserker_rage ->
-- battle_shout at -4.50, a ruled deviation). Before it:
-- Disagreements (P7; floor 0.91, final): decisions on-GCD 0.910 (67) top [execute -> overpower 1; execute ->
-- sunder_armor 1; mortal_strike -> slam 1] after central fixes 7 (outcome belief), 13 and 16 (0.866 before them,
-- 0.836 before fix 6), with Improved Slam (12862) and Anger Management's 1.5 rage per 5 s (12296, DB2 aura 85)
-- modelled in the kit and the replay character at the build's 3.8 s Arcanite Reaper. Each disagreement once, wowsims
-- -> ours, at the log's time:
-- 1. execute -> overpower (165.08) and slam -> mortal_strike (64.08): wowsims casts 0.08 s after a tick crosses the
--    15 the cast costs (Anger Management 13.5 -> 15.0 at 165.00; Bloodrage 13.8 -> 15.3 at 64.00); the client answers
--    usability 0.1 s after a gain, so at the cast its last answer is still "short" (believed hi 14.99, the sim's
--    floor(lo) 14): replay limit (the usability answer's delay). At 64.08 the belief is also 1.3 short because
--    Improved Bloodrage 2/2's +50% on the periodic ticks (wowsims logs 1.5 a second) cannot be modelled: the belief's
--    aura regen entries take a fixed number, not a talent-rank-scaled one (shared gap, lane report); with 1.5 forced in
--    a scratch run the belief reads 14.99 there and agreement stays 0.910.
-- 2. execute -> sunder_armor (171.08), mortal_strike -> slam (110.28), spearing_strike -> sunder_armor (34.28): wowsims
--    casts on a white swing's rage logged at the same instant; the replay lands the swing one landing lag later (fix
--    6's M.LAND, as the client hears it): replay limit (landing lag).
-- 3. overpower -> sunder_armor (79.98): Bloodthrill's proc (1289682) opens the hidden window 0.09 s before the cast,
--    seen only by usability: replay limit (the 0.2 s tick).
-- Fixed since the provisional floor: sunder_armor -> rend (7.58, a dodged Sunder counted as a stack) and rend -> slam
-- (78.08, a missed Rend kept up) by fix 7's undo of an avoided cast's target auras; sunder_armor -> overpower (177.88)
-- no longer disagrees. Fix 6 cleared 45.68, 60.88 and 102.68 (the belief's rage at a same-instant swing, gap B).
-- Pre-pull: Berserker Rage at -4.5 and Battle Shout at -3 are on-GCD decisions and agree; Battle Stance,
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
    -- the user's tiers (2026-10-21): Rend's uptime and Overpower are focus; Mortal Strike, Slam and Execute rotational
    -- (untiered); Arms casts no Revenge. Heroic Strike and Cleave always 2, Victory Rush 1 on its extra line (the owner's
    -- ruling, 2026-10-22)
    focus = { overpower = 1, heroic_strike = 2, cleave = 2, rend = 2 },
    -- Rule 15: Thunder Clap, a setting off in game and on in the harness (the user's ruling, 2026-10-21); its only
    -- line is the leveling filler below. Fury casts no Thunder Clap, so its recipe names none (rule 15 errors on a key
    -- with no cast line) and the setting is registered for Arms only.
    maintenance = { thunder_clap = "maintain_thunder_clap" },
    -- leveling: before Mortal Strike's talent (the brackets' L40 has 31 points, short of it) Arms has only cooldown
    -- strikes (Slam 18 s, Spearing Strike 20 s), Rend, Thunder Clap and five Sunders; the rest went to the off-GCD Heroic
    -- Strike and the GCD idled up to 11.2 s at L40 (9.0 at L10). Hamstring (10 rage, no cooldown) is the last-resort GCD
    -- press: L10 and L40 5.6 s; silent at 60 (wowsims's list has no Hamstring).
    -- Thunder Clap drops its 40-rage hold: Hamstring would spend the rage it pools for, and the harness (rule 15's
    -- setting on) never cast it (tests/Forever/maintenance_spec.lua); in game the setting is off and the line silent.
    leveling = {
        "heroic_strike,use_off_gcd=1,focus=2,if=!action.mortal_strike.known&rage.current>=30",
        "thunder_clap,if=!action.mortal_strike.known&!debuff.thunder_clap.up",
        "sunder_armor,if=!action.mortal_strike.known&debuff.sunder_armor.stack<5",
        "hamstring,if=!action.mortal_strike.known",
    },
    -- extra (content outside wowsims's model): Victory Rush; wowsims never goes mob to mob, so its kill window never
    -- opens there. The user's ruling (2026-10-21): "just above bloodthirst (since it's a mini bloodthirst)". The bare
    -- line: the kit's usable already refuses it outside Victorious.
    -- Arms has no Bloodthirst: above its main strike, Mortal Strike (the owner's placement; the user may move it).
    extra = { { before = "mortal_strike", line = "victory_rush,focus=1" } },
}
