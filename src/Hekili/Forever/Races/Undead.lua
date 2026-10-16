-- Forever/Races/Undead.lua
-- The Undead's Forever racials (DB2 1.60.1.70338), for every class; race token "Scourge" (UnitRace's second return):
-- Will of the Forsaken (7744: removes charm, fear and sleep, immune for 0.1 s; 120 s, on the GCD), whose cast leaves
-- nothing to model beyond its cooldown and GCD (no `handler` or `now`), and Cannibalize (20577: triggers 20578, a 10 s
-- self-channel, SPELL_ATTR1_IS_SELF_CHANNELLED, healing 7% of maximum health and mana every 2 s, near a corpse; 120 s,
-- on the GCD), registered as a 10 s channel so the simulation does not recommend breaking it; whether a corpse is near
-- is not known, a priority gates it. Touch of the Grave (1260189 Warrior/Paladin/Rogue, 1260201 Priest/Mage/Warlock: a
-- proc that drains health) and Underwater Breathing are passives with no rotation effect. No resource or cost modifier.
-- No pack names either. Inert for any other race (Engine/Races.lua).

local addon, ns = ...
local Hekili = _G[ addon ]

local race = Hekili:NewRace( "Scourge" )

race:RegisterAbility( "will_of_the_forsaken", {
    id = 7744,
    cast = 0,
    cooldown = 120,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",
} )

race:RegisterAbility( "cannibalize", {
    id = 20577,
    cast = 10,
    channeled = true,
    fixedCast = true, -- 20578's duration, not hasted
    cooldown = 120,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",

    start = function () -- a channel: Hekili's simulation runs `start`, not `handler` (State.lua runHandler)
        applyBuff( "cannibalize" )
    end,
    -- VirtualState's now-state of the cast (event-facade spec §12a)
    now = function ()
        applyBuff( "cannibalize" )
    end,
} )

race:RegisterAura( "cannibalize", {
    id = 20578,
    duration = 10,
    max_stack = 1,
} )
