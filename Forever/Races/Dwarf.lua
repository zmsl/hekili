-- Forever/Races/Dwarf.lua
-- The Dwarf's Forever racial (DB2 1.60.1.70338), for every class: Stoneform (20594: -10% physical damage taken,
-- removes poison, disease and bleed effects and grants immunity to them for 8 s; 180 s, on the GCD), which replaces
-- `all`'s stock entry (120 s, off the GCD, its buff 65116 absent on Forever: the buff is 20594 itself). Kept from
-- `all`: usable only while a dispellable effect it removes is up. No `dispellable_bleed` aura exists in `all`: the gate
-- covers poison and disease until one does (the bleed lines stay, as Forever's real dispel). Find Treasure, Mace
-- Specialization and Big Game Hunter have no rotation effect. No resource or cost modifier. No pack names it. Inert for
-- any other race (Races.lua).

local addon, ns = ...
local Hekili = _G[ addon ]

local race = Hekili:NewRace( "Dwarf" )

local CLEARS = { "dispellable_poison", "dispellable_disease", "dispellable_bleed" } -- Stoneform's dispels on Forever

race:RegisterAbility( "stoneform", {
    id = 20594,
    cast = 0,
    cooldown = 180,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",

    -- the effect with the longest remaining time (Hekili's ability `buff`: usable only while it is up)
    buff = function ()
        local aura, remains = CLEARS[ 1 ], buff[ CLEARS[ 1 ] ].remains
        for i = 2, #CLEARS do
            local rem = buff[ CLEARS[ i ] ].remains
            if rem > remains then
                aura = CLEARS[ i ]
                remains = rem
            end
        end
        return aura
    end,

    handler = function ()
        removeBuff( "dispellable_poison" )
        removeBuff( "dispellable_disease" )
        removeBuff( "dispellable_bleed" )
        applyBuff( "stoneform" )
    end,
    -- VirtualState's now-state of the cast (event-facade spec §12a)
    now = function ()
        removeBuff( "dispellable_poison" )
        removeBuff( "dispellable_disease" )
        removeBuff( "dispellable_bleed" )
        applyBuff( "stoneform" )
    end,
} )

race:RegisterAura( "stoneform", {
    id = 20594,
    duration = 8,
    max_stack = 1,
} )
