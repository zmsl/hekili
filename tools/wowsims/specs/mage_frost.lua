-- tools/wowsims/specs/mage_frost.lua (new packs, owner-approved 2026-11-12): Frost (wowsims.com)'s wowsims/forever
-- request and translation.
return {
    class = "MAGE",
    pack = "Frost (wowsims.com)",
    spec = "frost",
    name = "Frost",
    talentTree = "mage",
    apl = "ui/specs/mage/dps/apls/frost.apl.json",
    player = {
        race = "RaceHuman",
        class = "ClassMage",
        gear = "ui/specs/mage/dps/gear_sets/p1Arcane.gear.json",
        talentsString = "203205-5-053500011121331251",
        specKey = "mage",
        options = { classOptions = { defaultMageArmor = "MageArmorMageArmor" } },
        profession1 = "Engineering",
        profession2 = "Tailoring",
        reactionTimeMs = 100,
        distanceFromTarget = 28,
    },
    -- the Talisman of Ephemeral Power (ItemSparse 18820: a trinket, InventoryType 12)
    map = { ["item:18820"] = "use_items" },
    -- by role (docs/dev/wowsims-packs.md): Cone of Cold on five Winter's Chill stacks and Ice Lance on a Fingers of
    -- Frost charge are windows to catch (1); Ice Barrier, kept up for Frigid Power, is upkeep (2)
    focus = { cone_of_cold = 1, ice_lance = 1, ice_barrier = 2 },
}
