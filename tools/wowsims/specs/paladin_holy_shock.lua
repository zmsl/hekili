-- tools/wowsims/specs/paladin_holy_shock.lua (new packs, owner-approved 2026-11-12): Holy Shock (wowsims.com)'s
-- wowsims/forever request and translation.
return {
    class = "PALADIN",
    pack = "Holy Shock (wowsims.com)",
    spec = "retribution",
    name = "Holy Shock",
    talentTree = "paladin",
    apl = "ui/specs/paladin/retribution/apls/holy_shock.apl.siml",
    player = {
        race = "RaceHuman",
        class = "ClassPaladin",
        gear = "ui/specs/paladin/retribution/gear_sets/holy_shock.gear.siml",
        talentsString = "05025210221021--0523330110130033",
        specKey = "retributionPaladin",
        options = { classOptions = setmetatable({}, { __jsontype = "object" }) },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100,
        distanceFromTarget = 25,
    },
    -- 25902: Holy Shock rank 3's damage row (DB2: 20930 is a dummy the server turns into 25902 or the heal 25903), the
    -- ID wowsims casts and logs; the kit's holy_shock (its ranks 1311606, 20473, 20929, 20930)
    map = { [25902] = "holy_shock" },
    -- by role (docs/dev/wowsims-packs.md): Hammer of Wrath's execute window 1, the seal and Consecration kept up 2
    focus = { hammer_of_wrath = 1, seal_of_righteousness = 2, consecration = 2 },
}
