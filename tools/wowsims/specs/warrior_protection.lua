-- tools/wowsims/specs/warrior_protection.lua (wowsims packs plan, Task 6): Protection (wowsims.com)'s wowsims/forever
-- request and translation. Values from wowsims/forever (MIT, https://github.com/wowsims/forever)
-- ui/specs/warrior/protection/presets.ts (ProtectionTalents :32, DefaultOptions :93-102, OtherDefaults :127-142) and spec.ts
-- (default gear: Pre-BiS (Defense Cap), prebis.gear.json) at the pin.
-- Disagreements (P7; floor 0.90): decisions on-GCD 0.904 (94) top [shield_slam -> demoralizing_shout 3; shield_slam ->
-- sunder_armor 3; rend -> shield_slam 1], on the tanked export (central fix 13: the target swings at us, 76 swings;
-- the incoming healing model; Revenge's window read through the aura-only map). Each disagreement once, wowsims ->
-- ours, at the log's time:
-- 1. shield_slam -> sunder_armor / demoralizing_shout / battle_shout (13.53, 19.53, 81.15, 123.15, 165.17, 171.17):
--    wowsims casts Shield Slam the instant its cooldown ends; the decision runs just before, while the client still
--    answers "on cooldown", so the belief pushes the ready time a probe (0.5 s, VirtualState CD_PROBE) out and a filler
--    ready now wins: replay limit (the decision instant at a cooldown's end).
-- 2. shatter_curse -> shield_slam (30.38): the Orc racial at 50% health; the replay does not replay our health, so
--    health.pct reads full: replay limit.
-- 3. rend -> shield_slam (85.65): Rend's condition needs cooldown.shield_slam.remains>=1.5; Shield Slam was cast at
--    81.15 on a 6 s cooldown, so wowsims reads exactly 1.5 and ours reads an ulp under it (the engine's clock sums):
--    replay limit (an exact tie at the GCD's length).
-- Worked: shield_slam -> thunder_clap (18 at 0.585): the state read a `shared = "target"` aura from the player's
-- debuffs, so Thunder Clap's debuff always read down (central GAP AJ fixed the read; the kit shares it on the target); the kit's talent costs (Focused Rage 1 a rank, on the shouts too) priced as wowsims logs them.
-- The replay does not replay the target's swings (replay limit: rage from damage taken reaches the belief only
-- through the truth's after-values); Revenge's window (25288) is a hidden aura in the replay knobs.
-- Precombat calls no list (fix 16 does not reach this pack). Automatic cooldowns (rule 13): none in the log.
return {
    class = "WARRIOR",
    pack = "Protection (wowsims.com)",
    spec = "protection",
    name = "Protection",
    talentTree = "warrior",
    apl = "ui/specs/warrior/protection/apls/default.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassWarrior",
        gear = "ui/specs/warrior/protection/gear_sets/prebis.gear.json",
        talentsString = "35300003-05-050531120300021351",
        specKey = "protectionWarrior",
        options = {
            classOptions = {
                queueDelay = 250,
                startingRage = 0,
                useBattleShout = true,
                defaultStance = "WarriorStanceDefensive",
                hasBsT2 = true,
                stanceSnapshot = true,
            },
        },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100, -- apply_defaults.ts: `other.reactionTime || 100` (OtherDefaults sets none)
        distanceFromTarget = 0,
    },
    -- a tank: the raid's tank (the target swings at it) and presets.ts:127-142's healing model (apply_defaults.ts:108-122)
    tank = true,
    healingModel = {
        hps = 815,
        cadenceSeconds = 0.3,
        cadenceVariation = 0.64,
        absorbFrac = 0.015,
        burstWindow = 6,
        inspirationUptime = 0.25,
    },
    -- wowsims names the Revenge window (DB2 5302 Defensive State, 5 s) by Revenge's own ID; the kit's is revenge_usable
    auras = { [25288] = "revenge_usable" },
    exclusive = { [11556] = true }, -- Demoralizing Shout bids in wowsims's "Demoralizing" category (an exclusive effect)
    map = { [12723] = "sweeping_strikes" }, -- Sweeping Strikes's effect id (wowdb); the kit's ability is 12292
    -- no focus: the retired Protection list's tiers (Shield Bash, Mocking Blow, Taunt) are on none of wowsims's lines
    -- Rule 15: the raid debuff, a setting off in game and on in the harness (the user's ruling, 2026-10-21); Thunder
    -- Clap stays always on here, as wowsims has it (the user's ruling: not a Protection option)
    maintenance = { demoralizing_shout = "maintain_demoralizing_shout" },
    leveling = {},
    -- extra (content outside wowsims's model): Victory Rush; wowsims never goes mob to mob, so its kill window never
    -- opens there. The user's ruling (2026-10-21): "just above bloodthirst (since it's a mini bloodthirst)". The bare
    -- line: the kit's usable already refuses it outside Victorious.
    extra = { { before = "bloodthirst", line = "victory_rush" } },
}
