-- tools/wowsims/specs/paladin_protection.lua (wowsims packs plan, Task 9): Protection (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/protection/presets.ts:23
-- (DefaultTalents), :25-27 (DefaultOptions), :86-98 (OtherDefaults) at the pin; the APL and gear spec.ts's default.
-- Disagreements worked (P7): pending (the replay gate waits on a shared change: the APL casts Retribution Aura at
-- -10 s, before tests/Game/harness/replay.lua's 5 s prepull).
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
