-- tools/wowsims/specs/hunter_survival.lua (wowsims packs plan, Task 11): Survival (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/hunter/dps/presets.ts:68-89,128-134 at the pin (the SV Weave talents,
-- DefaultOptions = NoPetOptions, OtherDefaults; the default rotation Melee Weave, apls/default.apl.json; gear p1).
-- Disagreements worked (P7), decisions on-GCD 0.659 (41) top [wing_clip -> false 4; multi_shot -> arcane_shot 3;
-- strider_kick -> false 3]:
--   wing_clip -> false: replay limit, the in-combat mana lower bound (secret mana) under Wing Clip's price.
--   multi_shot -> arcane_shot: replay limit, the same bound (see hunter_beast_mastery.lua).
--   strider_kick -> false: API-forced price (no base mana read): its percent-of-base cost priced on the maximum.
-- Content gap fixed (P6): Resourcefulness (440529) cuts Mongoose Bite, Wing Clip, Immolation Trap and Strider Kick 60%
-- (wowsims's 26, 32, 98 and 39.6); before it, the bite was believed short of mana at every window (0.415 -> 0.659).
-- Ranges: the weave's melee-range lines read `target.within5` (rule 11) and the shots the bracket from the kit's
-- range checks; wowsims's Movement steps place us in the replay.
-- Lost to GAP 14 (autocastOtherCooldowns, not translated): Rapid Fire (3045) and the Orc's Blood Fury (20572), the
-- cooldowns wowsims casts from 5 s on.
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
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
