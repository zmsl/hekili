-- tools/wowsims/specs/hunter_marksmanship.lua (wowsims packs plan, Task 11): Marksmanship (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/hunter/dps/presets.ts:68-89,128-134 at the pin (the MM Weave talents,
-- DefaultOptions = NoPetOptions, OtherDefaults; the default rotation Melee Weave, apls/default.apl.json; gear p1).
-- Disagreements worked (P7, after central fix 6: the log's pools, casts priced when heard), decisions on-GCD 0.833 (42)
-- top [strider_kick -> wing_clip 5; multi_shot -> arcane_shot 2]:
--   strider_kick -> wing_clip: shared gap (percent-of-base costs priced on the maximum): Strider Kick's 5.81% of base
--   mana is priced on the log's maximum 2790 (64.8 after Resourcefulness) vs wowsims's 39.6, with the true mana 40-52.
--   Priced on base mana (a local run): 0.905, and the two left (149 s, 168 s) are API-forced: mana is secret in combat
--   and the belief's bound [32, 37] sits under a 39.96 the truth (40.0, 40.4) clears by under 1.
--   multi_shot -> arcane_shot: shared gap (`%` division read as Lua's modulo; see
--   hunter_beast_mastery.lua).
-- Prices (P6): Resourcefulness 2/2 (440529) cuts Raptor Strike, Mongoose Bite, Wing Clip, Immolation Trap and Strider
-- Kick 60% (wowsims's 40, 26, 32, 98, 39.6).
-- Ranges: the weave's melee-range lines read `target.within5` (rule 11) and the shots the bracket from the kit's
-- range checks; wowsims's Movement steps place us in the replay.
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): Blood Fury (20572, the Orc's) and Rapid Fire
-- (3045), each `if=time>=5`, at the top of the list.
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
-- Multi-Shot (2643): its cast is the DB2's 500 ms; wowsims has no cast time for it (instant there). Kept: the client
-- charges the DB2's, and the `action.multi_shot.cast+...<=mainhand_remains` line reads it (in-game checkpoint).
return {
    class = "HUNTER",
    pack = "Marksmanship (wowsims.com)",
    spec = "marksmanship",
    name = "Marksmanship",
    talentTree = "hunter",
    apl = "ui/specs/hunter/dps/apls/default.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassHunter",
        gear = "ui/specs/hunter/dps/gear_sets/p1.gear.json",
        talentsString = "-205305031150001-5502000300502201",
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
    -- the retired Marksmanship list's tiers (P9.3); its Sniper Shot tier 1 is dropped: the Melee Weave never casts it
    focus = { hunters_mark = 2, serpent_sting = 2 },
    leveling = {},
}
