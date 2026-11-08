-- Hekili_Shared/Races/Dwarf.lua
-- `all` (Engine/Schema/Spec/All.lua) no longer registers this racial: the stock entry named below is what it used to register.
-- The Dwarf's Forever racial (DB2 build 70707), for every class: Stoneform (20594: -10% physical damage taken,
-- removes poison, disease and bleed effects and grants immunity to them for 8 s; 180 s, on the GCD), which replaces
-- `all`'s stock entry (120 s, off the GCD, its buff 65116 absent on Forever: the buff is 20594 itself). Kept from
-- `all`: usable only while a dispellable effect it removes is up. The gate covers poison and disease: a bleed carries no
-- dispel type, so no `dispellable_bleed` aura can exist. Find Treasure, Mace Specialization and Big Game Hunter have no
-- rotation effect. No resource or cost modifier. Protection (wowsims.com) names it (its low-health line). Unknown for
-- any other race (Engine/Schema/Races.lua).

local race = Hekili:NewRace("Dwarf")

local CLEARS = { "dispellable_poison", "dispellable_disease" } -- Stoneform's dispels on Forever

race:RegisterAbility("stoneform", {
    id = 20594,
    cast = 0,
    cooldown = 180,
    gcd = "spell",
    startsCombat = false,
    toggle = "defensives",

    -- the effect with the longest remaining time (Hekili's ability `buff`: usable only while it is up)
    buff = function()
        local aura, remains = CLEARS[1], buff[CLEARS[1]].remains
        for i = 2, #CLEARS do
            local rem = buff[CLEARS[i]].remains
            if rem > remains then
                aura = CLEARS[i]
                remains = rem
            end
        end
        return aura
    end,

    handler = function()
        removeBuff("dispellable_poison")
        removeBuff("dispellable_disease")
        applyBuff("stoneform")
    end,
    -- The belief's now-state of the cast (event-facade spec §12a)
    now = function()
        removeBuff("dispellable_poison")
        removeBuff("dispellable_disease")
        applyBuff("stoneform")
    end,
})

race:RegisterAura("stoneform", {
    id = 20594,
    duration = 8,
    max_stack = 1,
})
