-- Forever/Races/NightElf.lua
-- The Night Elf's Forever racial (DB2 1.60.1.70338), for every class: Elune's Light (1259799: +10% critical strike
-- chance with spells and attacks, aura 290 base 10, for 15 s; 180 s, off the GCD). Shadowmeld stays Hekili's stock
-- racial (`all`); Quickness and Wisp Spirit are passives. No resource or cost modifier. No pack names it: a race
-- ability is absent for other races; a player adds it to a priority if wanted. Inert for any other race (Races.lua).

local addon, ns = ...
local Hekili = _G[ addon ]

local race = Hekili:NewRace( "NightElf" )

race:RegisterAbility( "elunes_light", {
    id = 1259799,
    cast = 0,
    cooldown = 180,
    gcd = "off",
    startsCombat = false,
    toggle = "cooldowns",

    handler = function ()
        applyBuff( "elunes_light" )
    end,
    -- VirtualState's now-state of the cast (event-facade spec §12a)
    now = function ()
        applyBuff( "elunes_light" )
    end,
} )

race:RegisterAura( "elunes_light", {
    id = 1259799,
    duration = 15,
    max_stack = 1,
} )
