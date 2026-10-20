-- tools/wowsims/specs/hunter_beast_mastery.lua (wowsims packs plan, Task 11): Beast Mastery (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/hunter/dps/presets.ts:68-89,128-134 at the pin (the BM Weave talents,
-- DefaultOptions = NoPetOptions, OtherDefaults; the default rotation Melee Weave, apls/default.apl.json; gear p1).
-- Disagreements worked (P7), decisions on-GCD
-- 0.259 (27) top [wing_clip -> false 8; wing_clip -> arcane_shot 3; multi_shot -> arcane_shot 2]:
-- No positions (translation gap, rule 2): the Melee Weave walks in for each main-hand swing and out for the shots;
-- its four melee-range lines (Mongoose Bite, Strider Kick, Immolation Trap, Wing Clip) read `unitDistance` and its
-- Weave group is `move`/`wait`, so all are omitted and Raptor Strike (no range test) leads the list.
--   wing_clip -> false, wing_clip -> arcane_shot: translation gap, no positions (above).
--   multi_shot -> arcane_shot: replay limit (mana is secret in combat): the belief holds mana at its in-combat lower
--   bound (a third of the log's at 6 s) and prices Multi-Shot's percent-of-base cost as a fraction of the maximum
--   (the API gives no base mana), so after Raptor Strike's swing spend Multi-Shot is believed unaffordable.
-- n is 27 (under 40) because wowsims spends its 2790 mana by 25 s (no pet, no Aspect of the Viper) and then casts
-- little but Wing Clip; every on-GCD cast ID of the log maps to a key.
-- Also: the prepull is scheduled (doAtValue -22 s, -20 s), and the precombat list carries no conditions, so Hunter's
-- Mark leads it until the pull (translation gap, rule 1). Lacerating Strikes (1310536) and the trap's burn (14301)
-- are procs no key maps.
return {
    class = "HUNTER",
    pack = "Beast Mastery (wowsims.com)",
    spec = "beast_mastery",
    name = "Beast Mastery",
    talentTree = "hunter",
    apl = "ui/specs/hunter/dps/apls/default.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassHunter",
        gear = "ui/specs/hunter/dps/gear_sets/p1.gear.json",
        talentsString = "5320001505101251-0053250001-4",
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
    focus = { hunters_mark = 2, serpent_sting = 2 }, -- the retired BeastMastery list's tiers (P9.3)
    leveling = {},
}
