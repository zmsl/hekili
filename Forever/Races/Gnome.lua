-- Forever/Races/Gnome.lua
-- The Gnome's Forever racials (DB2 1.60.1.70338), for every class: Eureka! (15 s: the next 3 abilities in its scope
-- cost 10% less, +10% damage not modelled; 120 s, off the GCD) and Expansive Mind (+5% maximum resources: 20591
-- Priest/Mage/Warlock, 1259802 Warrior, 1259803 Rogue). Inert for any other race (Races.lua).

local addon, ns = ...
local Hekili = _G[ addon ]

local race = Hekili:NewRace( "Gnome" )

local EUREKA = { 1259812, 1259817, 1259821, 1259823 } -- the other classes' Eureka!

race:RegisterAbility( "eureka", {
    id = 1259813,
    copy = EUREKA,
    cast = 0,
    cooldown = 120,
    gcd = "off",
    startsCombat = false,
    toggle = "cooldowns",

    handler = function ()
        applyBuff( "eureka", 15, 3 )
    end,
    -- VirtualState's now-state of the cast (event-facade spec §12a)
    now = function ()
        applyBuff( "eureka", 15, 3 )
    end,
} )

race:RegisterAura( "eureka", {
    id = 1259813,
    copy = EUREKA,
    duration = 15,
    max_stack = 3,
} )

race:RegisterResourceMod( { max = 0.05 } ) -- Expansive Mind: +5% maximum resources

race:RegisterCostMod( {
    aura = "eureka",
    pct = -0.10,
    charges = 3,
    -- Eureka! 1259813 effect 0: aura 108 (ADD_PCT_MODIFIER) misc 14 (cost) -10, class masks
    -- 1784679630 / 5 / 1 / 0 against SpellClassSet 4 (Warrior). Other classes: append their IDs from
    -- select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
    --   join SpellPower p on p.SpellID=o.SpellID where o.SpellClassSet=<set> and p.ManaCost>0 and not
    --   ((o.SpellClassMask_0 & 1784679630)=0 and (o.SpellClassMask_1 & 5)=0 and (o.SpellClassMask_2 & 1)=0)
    -- Warrior: heroic_strike, cleave, slam, execute, overpower, mortal_strike, bloodthirst, whirlwind, shield_slam,
    -- revenge, thunder_clap, hamstring, intercept, mocking_blow, pummel, shield_bash, spearing_strike (rank 1 IDs;
    -- higher ranks resolve through the class's `copy` lists). Not: rend, sunder_armor, the shouts, concussion_blow,
    -- death_wish, disarm, retaliation, shield_block, sweeping_strikes.
    spells = { 78, 845, 1240193, 5308, 7384, 12294, 23881, 1680, 23922, 6572, 6343, 1715, 20252, 694, 6552, 72, 1310222 },
} )
