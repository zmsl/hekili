-- tools/wowsims/specs/hunter_beast_mastery.lua (wowsims packs plan, Task 11): Beast Mastery (wowsims.com)'s wowsims/forever request and translation.
-- Values from wowsims/forever (MIT) ui/specs/hunter/dps/presets.ts:68-89,128-134 at the pin (the BM Weave talents,
-- DefaultOptions = NoPetOptions, OtherDefaults; the default rotation Melee Weave, apls/default.apl.json; gear p1).
-- Disagreements worked (P7), decisions on-GCD 0.741 (27) top [wing_clip -> false 3; multi_shot -> arcane_shot 2;
-- multi_shot -> serpent_sting 1]:
--   wing_clip -> false: replay limit (mana is secret in combat): the belief's mana is its lower bound, a few points under
--   Wing Clip's price while wowsims, at its true mana, pays it.
--   multi_shot -> arcane_shot, multi_shot -> serpent_sting: replay limit, the same bound. The belief knows only that the
--   dearest spell the client answers usable is affordable (Multi-Shot's price); the queued Raptor Strike ahead of it is
--   paid in the simulation, so Multi-Shot is then believed short and Hekili waits on the next shot.
-- n is 27 (under 40) because wowsims spends its 2790 mana by 25 s (no pet, no Aspect of the Viper) and then casts
-- little but Wing Clip; every on-GCD cast ID of the log maps to a key.
-- Ranges: the weave's melee-range lines read `target.within5` (rule 11) and the shots the bracket from the kit's
-- range checks; wowsims's Movement steps place us in the replay.
-- autocastOtherCooldowns (rule 13, from the log's "Major cooldown used"): Blood Fury (20572, the Orc's) and Rapid Fire
-- (3045), each `if=time>=5`, at the top of the list.
-- Lacerating Strikes (1310536) and the trap's burn (14301) are procs no key maps.
-- Multi-Shot (2643): its cast is the DB2's 500 ms; wowsims has no cast time for it (instant there). Kept: the client
-- charges the DB2's, and the `action.multi_shot.cast+...<=mainhand_remains` line reads it (in-game checkpoint).
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
