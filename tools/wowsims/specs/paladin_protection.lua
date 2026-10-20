-- tools/wowsims/specs/paladin_protection.lua (wowsims packs plan, Task 9): Protection (wowsims.com)'s wowsims/forever
-- request and translation.
-- Values from wowsims/forever (MIT, https://github.com/wowsims/forever) ui/specs/paladin/protection/presets.ts:23
-- (DefaultTalents), :25-27 (DefaultOptions), :86-98 (OtherDefaults) at the pin; the APL and gear spec.ts's default.
-- Disagreements worked (P7, resume 3: after central fixes 6/8/C and 9/9b): replay 0.750 (28; wowsims's own Protection
-- is out of mana from 24 s, so few decisions). 0.679 on the rebase alone (fix 6/8/C report: the replay's client now
-- reads the log's 2597 maximum); back to 0.750 once wowsims's character is booted with that maximum too, so the class
-- file prices Righteous Fury's 30% on it (on 6000, its short answers capped the belief at 779 under a true 1568).
-- holy_strike -> false 4 and seal_of_fury -> holy_strike 3: core gap (shared, reported to the controller;
-- src/Hekili/Engine/Sim/State.lua): in combat the engine forecasts mana at GetManaRegen's in-five-second-rule rate
-- (this build's mp5 is 0) and never the spirit part after the window, so a spell short by a few mana is never shown
-- with a wait (measured with the window-aware rate: 0.964). The floor stays 0.75. Holy Shock is unconditional: the
-- APL's Consecrated Ground (1310905) is never on the target (wowsims logs Consecration's 1280353), as in wowsims; the
-- build takes no Holy Shock. Lost to autocastOtherCooldowns (not translated): nothing cast.
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
