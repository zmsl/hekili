-- Forever/Shared/Items.lua
-- The equipped-item actions every class shares (shared-content spec §4.4), through Engine/Shared.lua into `all`:
-- `use_items` (the APL verb Core.lua expands into the equipped trinkets) and the slots Events.lua rebinds on an equipment
-- change (trinket1, trinket2, main_hand; null_cooldown while a slot has no on-use), and class.trinkets, State.lua's
-- per-item buff map (empty: no Forever trinket is modelled). Hekili's unused item-settings helpers and its unlisted
-- unusable-trinket stub were dropped.

local addon, ns = ...
local Hekili = _G[ addon ]

local class = Hekili.Class

local shared = Hekili:NewShared()

-- Should handle trinkets/items internally.
-- 1.  Check APLs and don't try to recommend items that have their own APL entries.
-- 2.  Respect item preferences registered in spec options.

shared:RegisterAbility( "use_items", {
    name = "Use Items",
    listName = "|T136243:0|t |cff00ccff[Use Items]|r",
    cast = 0,
    cooldown = 120,
    gcd = "off",
} )

local items = {
    null_cooldown = {
        name = "|cff00ccff[Null Cooldown]|r",
        listName = "|T136243:0|t |cff00ccff[Null Cooldown]|r",
        cast = 0,
        cooldown = 0.001,
        gcd = "off",

        startsCombat = false,

        unlisted = true
    },

    trinket1 = {
        name = "|cff00ccff[Trinket #1]|r",
        listName = "|T136243:0|t |cff00ccff[Trinket #1]|r",
        cast = 0,
        cooldown = 600,
        gcd = "off",

        usable = false,

        copy = "actual_trinket1",
    },

    trinket2 = {
        name = "|cff00ccff[Trinket #2]|r",
        listName = "|T136243:0|t |cff00ccff[Trinket #2]|r",
        cast = 0,
        cooldown = 600,
        gcd = "off",

        usable = false,

        copy = "actual_trinket2",
    },

    main_hand = {
        name = "|cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
        listName = "|T136243:0|t |cff00ccff[" .. INVTYPE_WEAPONMAINHAND .. "]|r",
        cast = 0,
        cooldown = 600,
        gcd = "off",

        usable = false,

        copy = "actual_main_hand",
    },
}

for key, def in pairs( items ) do
    shared:RegisterAbility( key, def )
end

class.trinkets = {
    [0] = { -- for when nothing is equipped.
    },
}

setmetatable( class.trinkets, {
    __index = function( t, k )
    return t[0]
end
} )
