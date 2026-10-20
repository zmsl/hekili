-- tools/wowsims/specs/hunter_marksmanship.lua (wowsims packs plan, Task 11): Marksmanship (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/hunter/dps/presets.ts:68-89,128-134 at the pin (the MM Weave talents,
-- DefaultOptions = NoPetOptions, OtherDefaults; the default rotation Melee Weave, apls/default.apl.json; gear p1).
-- Disagreements worked (P7), decisions on-GCD 0.738 (42) top [strider_kick -> wing_clip 5; mongoose_bite -> false 2;
-- multi_shot -> arcane_shot 2]:
--   strider_kick -> wing_clip: API-forced price (no base mana read): Strider Kick costs 5.81% of base mana, priced as a
--   fraction of the maximum (overstated), so at low mana the belief takes it as short and shows Wing Clip.
--   mongoose_bite -> false: replay limit, the in-combat mana lower bound (secret mana) under the bite's price.
--   multi_shot -> arcane_shot: replay limit, the same bound (see hunter_beast_mastery.lua).
-- Ranges: the weave's melee-range lines read `target.within5` (rule 11) and the shots the bracket from the kit's
-- range checks; wowsims's Movement steps place us in the replay.
-- Lost to GAP 14 (autocastOtherCooldowns, not translated): Rapid Fire (3045) and the Orc's Blood Fury (20572), the
-- cooldowns wowsims casts from 5 s on.
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
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
    focus = { hunters_mark = 2, serpent_sting = 2, sniper_shot = 1 }, -- the retired Marksmanship list's tiers (P9.3)
    leveling = {},
}
