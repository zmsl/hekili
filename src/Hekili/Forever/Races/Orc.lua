-- Forever/Races/Orc.lua
-- `all` (Engine/Schema/Spec.lua) no longer registers this racial: the stock entry named below is what it used to register.
-- The Orc's Forever racials (DB2 1.60.1.70338), for every class: Blood Fury (20572: +10% attack power and spell power
-- for 15 s; 120 s, off the GCD), one ID for every class, which replaces `all`'s stock entry (its per-class IDs 33702
-- and 33697 are absent on Forever; its aura, 20572 for 15 s, is right but registered here too, so the race owns it),
-- and Shatter Curse (1299026: removes curses, -15% magic damage taken and immunity to curses for 8 s; 180 s, on the
-- GCD). Hardiness (-20% stun duration) and Axe Specialization (+1% crit with an axe) are passives. No resource or cost
-- modifier. No pack names either. Inert for any other race (Engine/Schema/Races.lua).

local addon, ns = ...
local Hekili = _G[addon]

local race = Hekili:NewRace("Orc")

race:RegisterAbility("blood_fury", {
    id = 20572,
    cast = 0,
    cooldown = 120,
    gcd = "off",
    startsCombat = false,
    toggle = "cooldowns",

    handler = function()
        applyBuff("blood_fury", 15)
    end,
    -- VirtualState's now-state of the cast (event-facade spec §12a)
    now = function()
        applyBuff("blood_fury", 15)
    end,
})

race:RegisterAura("blood_fury", {
    id = 20572,
    duration = 15,
    max_stack = 1,
})

race:RegisterAbility("shatter_curse", {
    id = 1299026,
    cast = 0,
    cooldown = 180,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",

    handler = function()
        removeBuff("dispellable_curse")
        applyBuff("shatter_curse")
    end,
    now = function()
        removeBuff("dispellable_curse")
        applyBuff("shatter_curse")
    end,
})

race:RegisterAura("shatter_curse", {
    id = 1299026,
    duration = 8,
    max_stack = 1,
})
