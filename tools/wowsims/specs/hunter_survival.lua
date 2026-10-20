-- tools/wowsims/specs/hunter_survival.lua (wowsims packs plan, Task 11): Survival (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/hunter/dps/presets.ts:68-89,128-134 at the pin (the SV Weave talents,
-- DefaultOptions = NoPetOptions, OtherDefaults; the default rotation Melee Weave, apls/default.apl.json; gear p1).
-- Disagreements worked (P7, after central fixes 6 and 11), decisions on-GCD 0.878 (41) top [strider_kick -> wing_clip
-- 3; immolation_trap -> wing_clip 1; multi_shot -> arcane_shot 1]:
--   strider_kick -> wing_clip: shared gap (percent-of-base costs priced on the maximum; see hunter_marksmanship.lua).
--   multi_shot -> arcane_shot (22.73 s): the same shared gap under Multi-Shot's 13.9% (387.8 vs wowsims's 239).
--   immolation_trap -> wing_clip (37.09 s): API-forced (mana secret in combat): the belief sits at its last usable
--   rung, Strider Kick's price (64.8; 39.95 priced on base mana), while the truth is 112 and the trap costs 98.
-- Content gaps fixed (P6): Resourcefulness (440529, 2/2) cuts Raptor Strike, Mongoose Bite, Wing Clip, Immolation Trap
-- and Strider Kick 60% (wowsims's 40, 26, 32, 98 and 39.6; 30% at rank 1): before it the bite was believed short of
-- mana at every window (0.415 -> 0.659), and with Raptor Strike priced too and the world's truth under the build's
-- talents 0.659 -> 0.780. Strider Kick's DB2 mask is outside 440529's, but wowsims's log charges it 39.6: the kit
-- follows the log.
-- Ranges: the weave's melee-range lines read `target.within5` (rule 11) and the shots the bracket from the kit's
-- range checks; wowsims's Movement steps place us in the replay.
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): Blood Fury (20572, the Orc's) and Rapid Fire
-- (3045), each `if=time>=5`, at the top of the list.
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
-- Multi-Shot (2643): its cast is the DB2's 500 ms; wowsims has no cast time for it (instant there). Kept: the client
-- charges the DB2's, and the `action.multi_shot.cast+...<=mainhand_remains` line reads it (in-game checkpoint).
-- Unmodelled: Resourcefulness's second effect (1242688, from 1.38 s in the log: 30 s of 50% mana regen while casting
-- after a critical strike; the kit's mana belief has no hook for it).
return {
    class = "HUNTER",
    pack = "Survival (wowsims.com)",
    spec = "survival",
    name = "Survival",
    talentTree = "hunter",
    apl = "ui/specs/hunter/dps/apls/default.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassHunter",
        gear = "ui/specs/hunter/dps/gear_sets/p1.gear.json",
        talentsString = "-00530501114-550200030050220151",
        specKey = "hunter",
        options = {
            classOptions = {
                ammo = "ThoriumHeadedArrow",
                quiverBonus = "AncientSinewWrappedLamina",
                petUptime = 1,
                petAttackSpeed = "FasterAttackII",
                cobraReflexes = true,
                petAggression = 5,
                petType = "PetNone",
            },
        },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        distanceFromTarget = 11,
    },
    map = {},
    focus = { raptor_strike = 1, hunters_mark = 2, mongoose_bite = 1 }, -- the retired Survival list's tiers (P9.3)
    leveling = {},
}
