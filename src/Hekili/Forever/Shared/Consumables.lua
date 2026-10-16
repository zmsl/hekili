-- Forever/Shared/Consumables.lua
-- The consumables every class shares on Forever (shared-content spec §4.3), through Engine/Shared.lua into `all`: the
-- `potion` action and auras core reads by name, and the Healthstone from Forever's items (DB2 1.60.1.70338: the five
-- ranks and their Improved Healthstone variants). No Forever potion, flask or food is registered: the default
-- priorities leave consumables out, and retail's (Tempered Potion, Pact of Gluttony's Healthstone) do not exist here.
-- Neither action has a `now`: VirtualState sees only spell casts (an item action has no spell ID), and a Healthstone's
-- heal is health, which the belief does not track (spec §4.3).

local addon, ns = ...
local Hekili = _G[ addon ]

local C_Item = ns.Facade.C_Item
local GetItemCount, IsUsableItem = C_Item.GetItemCount, C_Item.IsUsableItem

local class = Hekili.Class

local shared = Hekili:NewShared()

-- State.lua's applyBuff mirrors a potion's aura to `potion`; with no Forever potion registered, `fake_potion` is the
-- alias's only member.
shared:RegisterAura( "fake_potion", {
    duration = 30,
    max_stack = 1,
} )

shared:RegisterAura( "potion", {
    alias = { "fake_potion" },
    aliasMode = "first",
    aliasType = "buff",
    duration = 30
} )

-- The APL verb `potion` (Core.lua resolves it to the chosen potion's action): an item only once a potion is chosen.
shared:RegisterAbility( "potion", {
    name = "Potion",
    listName = '|T136243:0|t |cff00ccff[Potion]|r',
    cast = 0,
    cooldown = 300,
    gcd = "off",

    startsCombat = false,
    toggle = "potions",

    consumable = function() return state.args.potion or settings.potion end,
    item = function()
        if state.args.potion and class.abilities[ state.args.potion ] then return class.abilities[ state.args.potion ].item end
        if spec.potion and class.abilities[ spec.potion ] then return class.abilities[ spec.potion ].item end
    end,
    bagItem = true,

    handler = function ()
        local use = class.specs[ 0 ].abilities.potion
        use = use and use.consumable

        if use and use ~= "global_cooldown" then
            class.abilities[ use ].handler()
            setCooldown( use, action[ use ].cooldown )
        end
    end,

    usable = function ()
        return false, "no Forever potion is registered"
    end,

    copy = "potion_default"
} )

-- Highest heal first: Major, Greater, Healthstone, Lesser, Minor; each as Improved Healthstone 2/2, 1/2, then plain.
local HEALTHSTONES = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 }

-- The best Healthstone in the bags and true (Minor and false when none: the keybind and icon lookups need an item). A
-- field read (`ability.item`) keeps only the first value.
local function healthstone()
    for i = 1, #HEALTHSTONES do
        if GetItemCount( HEALTHSTONES[ i ] ) > 0 then return HEALTHSTONES[ i ], true end
    end
    return HEALTHSTONES[ #HEALTHSTONES ], false
end

shared:RegisterAbility( "healthstone", {
    name = "Healthstone",
    listName = "|T538745:0|t |cff00ccff[Healthstone]|r",
    cast = 0,
    cooldown = 120, -- Classic's shared Healthstone cooldown; the item's own is read in game (spec §7 Q5)
    gcd = "off",

    item = healthstone,
    items = HEALTHSTONES,
    bagItem = true,

    startsCombat = false,

    usable = function ()
        local item, inBags = healthstone()
        if not inBags then return false, "requires healthstone in bags"
        elseif not IsUsableItem( item ) then return false, "healthstone on CD"
        elseif health.current >= health.max then return false, "must be damaged" end
        return true
    end,

    handler = function ()
        gain( 0.25 * health.max, "health" )
    end,
} )
