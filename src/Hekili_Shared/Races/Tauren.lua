-- Hekili_Shared/Races/Tauren.lua
-- The Tauren's castable racial on Forever (DB2 1.60.1.70338), for every class: War Stomp (20549: stuns up to 5 enemies
-- within 8 yards for 2 s; 0.5 s cast, 120 s, off the GCD), which Hekili's stock racials (`all`) lack. Plainsrunning
-- (1259918, Forever's movement-speed ramp), Endurance and Cultivation have no cast, cost, maximum or rotation effect:
-- nothing to register. No pack names it. Inert for any other race (Engine/Schema/Races.lua).

local race = Hekili:NewRace("Tauren")

race:RegisterAbility("war_stomp", {
    id = 20549,
    cast = 0.5,
    cooldown = 120,
    gcd = "off",
    startsCombat = true,
    toggle = "cooldowns",

    handler = function()
        applyDebuff("target", "war_stomp")
    end,
    -- The belief's now-state of the cast (event-facade spec §12a)
    now = function()
        applyDebuff("target", "war_stomp")
    end,
})

race:RegisterAura("war_stomp", {
    id = 20549,
    duration = 2,
    max_stack = 1,
})
