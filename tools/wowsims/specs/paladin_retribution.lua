-- tools/wowsims/specs/paladin_retribution.lua (wowsims packs plan, Task 9): Retribution (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/retribution/presets.ts:32-34
-- (DefaultOptions), :37 (TwistOfLightTalents), :144-151 (OtherDefaults) at the pin; the APL and gear spec.ts's default
-- (Twist of Light).
-- Disagreements worked (P7): replay 0.456 (57); top three, all one tracked central core gap (domain "power belief:
-- secret mana lower bound does not climb with regen"): the bound sits near 140 against wowsims's 3000+ and never climbs,
-- though VS.Power should integrate regen into it (docs/dev/layout.md). Only its being a lower bound is API-forced (mana
-- is secret in combat). seal_of_righteousness -> seal_of_command 8 (Seal of Righteousness's 144 above the bound, so the
-- twist's other seal shows first), seal_of_command -> false 6 and seal_of_righteousness -> false 6 (each seal at its
-- cost). The floor is re-measured, and only ever raised, once the central fix lands.
-- Lost to wowsims's autocastOtherCooldowns (not translated): the Everlook Pathcarver (item 274759) at the pull.
-- Leveling: the Seal of Righteousness refresh fills Holy Strike's cooldown before Seal of Command (L10 8.6 -> 4.4 s).
return {
    class = "PALADIN",
    pack = "Retribution (wowsims.com)",
    spec = "retribution",
    name = "Retribution",
    talentTree = "paladin",
    apl = "ui/specs/paladin/retribution/apls/twist_of_light.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/retribution/gear_sets/twist_of_light.gear.json",
        talentsString = "55003003--05225331101330321",
        specKey = "retributionPaladin",
        -- PaladinOptions is an empty message: an object, not dkjson's default empty array
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100,
        distanceFromTarget = 5,
    },
    map = {},
    focus = { hammer_of_wrath = 1, seal_of_command = 1, seal_of_righteousness = 1, consecration = 2, exorcism = 2 },
    -- The Twist of Light lines need the talent (wowsims's Auto rotation picks this APL by it): without it they swap the
    -- seals every GCD.
    requires = { seal_of_command = "twist_of_light", seal_of_righteousness = "twist_of_light" },
    leveling = {
        "seal_of_command,if=!talent.twist_of_light.enabled&!buff.seal_of_command.up",
        "seal_of_righteousness,if=!action.seal_of_command.known&buff.seal_of_righteousness.remains<24",
    },
}
