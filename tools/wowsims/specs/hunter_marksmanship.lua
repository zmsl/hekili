-- tools/wowsims/specs/hunter_marksmanship.lua (wowsims packs plan, Task 11): Marksmanship (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/hunter/dps/presets.ts:68-89,128-134 at the pin (the MM Weave talents,
-- DefaultOptions = NoPetOptions, OtherDefaults; the default rotation Melee Weave, apls/default.apl.json; gear p1).
-- Disagreements worked (P7), decisions on-GCD
-- 0.238 (42) top [mongoose_bite -> false 10; strider_kick -> false 5; wing_clip -> arcane_shot 4]:
-- No positions (translation gap, rule 2): the Melee Weave walks in for each main-hand swing and out for the shots;
-- its four melee-range lines (Mongoose Bite, Strider Kick, Immolation Trap, Wing Clip) read `unitDistance` and its
-- Weave group is `move`/`wait`, so all are omitted and Raptor Strike (no range test) leads the list.
--   all three: translation gap, no positions (above). Next: multi_shot -> arcane_shot, the secret-mana replay limit
--   (see hunter_beast_mastery.lua).
-- Also: the prepull is scheduled (doAtValue -22 s, -20 s), and the precombat list carries no conditions, so Hunter's
-- Mark leads it until the pull (translation gap, rule 1). Lacerating Strikes (1310536) and the trap's burn (14301)
-- are procs no key maps.
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
