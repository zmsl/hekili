-- Hekili_Shared/Races/Human.lua
-- `all` (Engine/Schema/Spec.lua) no longer registers this racial: the stock entry named below is what it used to register.
-- The Human's Forever racials (DB2 1.60.1.70338), for every class: Will to Survive (1259718: removes stun effects;
-- 180 s, on the GCD), which replaces `all`'s stock entry (59752, absent on Forever), and Perception (20600: stealth
-- detection for 20 s; 180 s, on the GCD). Will to Survive leaves no aura and no resource: no `handler` or `now`, its
-- cooldown and GCD are the declared fields'. The Human Spirit (+5% Spirit) and Sword Specialization (+2% crit with a
-- sword) are passives on stats the game reports. No resource or cost modifier. No pack names either. Inert for any
-- other race (Engine/Schema/Races.lua).

local race = Hekili:NewRace("Human")

race:RegisterAbility("will_to_survive", {
    id = 1259718,
    cast = 0,
    cooldown = 180,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",
})

race:RegisterAbility("perception", {
    id = 20600,
    cast = 0,
    cooldown = 180,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",

    handler = function()
        applyBuff("perception")
    end,
    -- The belief's now-state of the cast (event-facade spec §12a)
    now = function()
        applyBuff("perception")
    end,
})

race:RegisterAura("perception", {
    id = 20600,
    duration = 20,
    max_stack = 1,
})
