-- Forever/Races/NightElf.lua
-- `all` (Engine/Spec.lua) no longer registers this racial: the stock entry named below is what it used to register.
-- The Night Elf's Forever racials (DB2 1.60.1.70338), for every class: Elune's Light (1259799: +10% critical strike
-- chance with spells and attacks, aura 290 base 10, for 15 s; 180 s, off the GCD) and Shadowmeld, which replaces
-- `all`'s stock entry (58984, absent on Forever): 20580, no cooldown of its own but a 10 s category recovery (871),
-- off the GCD, the stealth aura 20580 until cancelled. Quickness and Wisp Spirit are passives. No resource or cost
-- modifier. No pack names either: a race ability is absent for other races; a player adds it to a priority if wanted.
-- Inert for any other race (Engine/Races.lua).

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

race:RegisterAbility( "shadowmeld", {
    id = 20580,
    cast = 0,
    cooldown = 10,
    gcd = "off",
    startsCombat = false,

    -- `all`'s gate, kept
    usable = function ()
        if not boss or solo then return false, "requires boss fight or group (to avoid resetting)" end
        if moving then return false, "can't shadowmeld while moving" end
        return true
    end,

    handler = function ()
        applyBuff( "shadowmeld" )
    end,
    now = function ()
        applyBuff( "shadowmeld" )
    end,
} )

race:RegisterAura( "shadowmeld", {
    id = 20580,
    duration = 3600, -- until cancelled (DB2 -1), as `all`'s
    max_stack = 1,
} )
