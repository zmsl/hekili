-- Game/State/Families/Gear.lua
-- The gear family (gear-aware spec §4): the pack's declared gear (def.gear: spec:RegisterGear's items and sets,
-- spec:RegisterSetBonus's bonus auras) and its values with the core's `state.set_bonus` semantics
-- (Engine/Sim/Events.lua ns.updateGear, Engine/Sim/State.lua mt_set_bonuses): a gear key its equipped piece count, a
-- bonus key 1 while its aura is believed up, `<key>_<n>pc` 1 when a bonus of that name is up or the set's count
-- reaches n, any other key 0. Sources/Gear.lua reads the values; Families/Now.lua's `set_bonus` and `equipped` answer
-- from I.setBonus. A rebuild keeps each key's value until the next read (the core's set_bonus survives
-- SpecializationChanged). Allocates at Build only.

local _, ns = ...
local I = ns.VirtualStateInternal

-- The `_<n>pc` forms the core derives (State.lua's suffix): every n (owner Q1). Without Q1: only 2 and 4.
local ANY_PC = true

local G =
    { n = 0, key = {}, items = {}, aura = {}, value = {}, nPc = 0, pcKey = {}, pcOf = {}, pcNeed = {}, pcBonus = {} }
I.gear = G
I.gearGen = 0
-- the raw keys: the declared ones and their `_<n>pc` forms; any other key answers 0, as the core's
local SB = setmetatable({}, {
    __index = function()
        return 0
    end,
})
I.setBonus = SB
local NO_GEAR, NO_ITEMS = {}, {}

--- Writes each value to its raw key, then each `_<n>pc` (the bonus of that name, or the set's count). Allocates nothing.
function I.GearPublish()
    for k = 1, G.n do
        SB[G.key[k]] = G.value[k]
    end
    for p = 1, G.nPc do
        local b = G.pcBonus[p]
        SB[G.pcKey[p]] = ((b > 0 and G.value[b] > 0) or G.value[G.pcOf[p]] >= G.pcNeed[p]) and 1 or 0
    end
end

--- Sets gear k's value (Sources/Gear.lua, which publishes); bumps I.gearGen. True when it changed.
function I.SetGear(k, v)
    if G.value[k] ~= v then
        G.value[k] = v
        I.gearGen = I.gearGen + 1
        return true
    end
    return false
end

I.OnBuild(function(def)
    local old = {} -- Build allocates: the carried values by key (the values, not a derived `_<n>pc`'s OR)
    for k = 1, G.n do
        old[G.key[k]] = G.value[k]
    end
    for k in pairs(SB) do
        SB[k] = nil
    end
    local list = def.gear or NO_GEAR
    local byKey = {}
    G.n, G.nPc = #list, 0
    for k = 1, G.n do
        local d = list[k]
        G.key[k], G.items[k], G.aura[k] = d.key, d.items or NO_ITEMS, d.aura or 0
        G.value[k] = old[d.key] or 0
        byKey[d.key] = k
    end
    for k = 1, G.n do
        for n = 1, #G.items[k] do
            if ANY_PC or n == 2 or n == 4 then
                local p = G.nPc + 1
                G.nPc = p
                G.pcKey[p], G.pcOf[p], G.pcNeed[p] = G.key[k] .. "_" .. n .. "pc", k, n
                local b = byKey[G.pcKey[p]]
                G.pcBonus[p] = (b and G.aura[b] > 0) and b or 0
            end
        end
    end
    I.GearPublish()
end)

I.OnSnapshot(function(out)
    for k = 1, G.n do
        out[#out + 1] = string.format("gear %s = %d", tostring(G.key[k]), G.value[k])
    end
end)
