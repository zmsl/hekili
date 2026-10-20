-- tools/wowsims/specs/paladin_protection.lua (wowsims packs plan, Task 9): Protection (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/protection/presets.ts:23
-- (DefaultTalents), :25-27 (DefaultOptions), :86-98 (OtherDefaults) at the pin; the APL and gear spec.ts's default.
-- Disagreements worked (P7): replay 0.750 (28; wowsims's own Protection is out of mana from 24 s, so few decisions);
-- top two, the tracked central core gap Retribution's header names (domain "power belief: secret mana lower bound
-- does not climb with regen"); only the bound's being a lower bound is API-forced (mana is secret in combat):
-- holy_strike -> false 4 (the bound 2-15 under Holy Strike's 20 when wowsims casts at exactly its cost),
-- seal_of_fury -> holy_strike 3 (the bound 150-180 against Seal of Fury's 200). The floor is re-measured, and only ever
-- raised, once the central fix lands. Holy Shock is unconditional: the APL's
-- Consecrated Ground (1310905) is never on the target (wowsims logs Consecration's 1280353), as in wowsims; the build
-- takes no Holy Shock. Lost to autocastOtherCooldowns (not translated): nothing cast.
return {
    class = "PALADIN",
    pack = "Protection (wowsims.com)",
    spec = "protection",
    name = "Protection",
    talentTree = "paladin",
    apl = "ui/specs/paladin/protection/apls/default.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/protection/gear_sets/default.gear.json",
        talentsString = "50003-0530313321301531-5022",
        specKey = "protectionPaladin",
        -- PaladinOptions is an empty message: an object, not dkjson's default empty array
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Enchanting",
        distanceFromTarget = 5,
    },
    map = { [25903] = "holy_shock" }, -- Holy Shock rank 4's hostile spell (wowdb: 25903, range 40); the kit's 20930
    focus = { seal_of_fury = 2, holy_shield = 2 },
    leveling = {},
}
