-- Hekili_Shared/Races/Troll.lua
-- `all` (Engine/Schema/Spec.lua) no longer registers this racial: the stock entry named below is what it used to register.
-- The Troll's Forever racials (DB2 1.60.1.70338), for every class: Berserking (20554: +10% attack and casting speed
-- for 10 s, one flat value, no health scaling; 180 s, off the GCD), which replaces `all`'s stock entry and aura
-- (26297, absent on Forever), and Rapid Regeneration (1260270: heals 50% of maximum health over 6 s; a self-channel,
-- SPELL_ATTR1_IS_SELF_CHANNELLED, broken by movement, action or damage; 180 s, off the GCD), registered as a 6 s
-- channel so the simulation does not recommend breaking it. The haste itself is the game's (Hekili reads haste); a
-- priority reads `buff.berserking.up`. Regeneration and Beast Slaying are passives. No resource or cost modifier. No
-- pack names either. Unknown for any other race (Engine/Schema/Races.lua).

local race = Hekili:NewRace("Troll")

race:RegisterAbility("berserking", {
    id = 20554,
    cast = 0,
    cooldown = 180,
    gcd = "off",
    startsCombat = false,
    toggle = "cooldowns",

    handler = function()
        applyBuff("berserking")
    end,
    -- The belief's now-state of the cast (event-facade spec §12a)
    now = function()
        applyBuff("berserking")
    end,
})

race:RegisterAura("berserking", {
    id = 20554,
    duration = 10,
    max_stack = 1,
})

race:RegisterAbility("rapid_regeneration", {
    id = 1260270,
    cast = 6,
    channeled = true,
    fixedCast = true, -- the DB2's duration, not hasted
    cooldown = 180,
    gcd = "off",
    startsCombat = false,
    toggle = "defensives",

    start = function() -- a channel: Hekili's simulation runs `start`, not `handler` (State.lua runHandler)
        applyBuff("rapid_regeneration")
    end,
    now = function()
        applyBuff("rapid_regeneration")
    end,
})

race:RegisterAura("rapid_regeneration", {
    id = 1260270,
    duration = 6,
    max_stack = 1,
})
