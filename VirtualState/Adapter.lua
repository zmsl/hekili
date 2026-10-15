-- VirtualState/Adapter.lua
-- VirtualState's glue to Hekili (spec §3.6, §5): VirtualState.Start at PLAYER_LOGIN, the Hekili.VirtualState debug
-- handle, the urgent lane, the tracked set from the active spec's registrations (SpecChanged) and Drain. This first
-- version drains by folding only; the apply through the spec and the across-reset feeds arrive with Task 9.
-- Loads after Core.lua.

local addon, ns = ...
local GetTime = GetTime
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources

local Hekili = _G[addon]
local class = Hekili.Class
local CreateFrame, debugprofilestop = CreateFrame, debugprofilestop
local insert, sort = table.insert, table.sort

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- The debug handle: /run print(Hekili.VirtualState.Snapshot())
Hekili.VirtualState = VS

-- The urgent lane (spec §4.4): shortens Hekili's wait before its next cycle; never interrupts one.
I.urgent = function(event)
    Hekili:ForceUpdate(event)
end

-- Start once, at PLAYER_LOGIN, on a frame of its own.
do
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        VS.Start(_G)
    end)
end

----------------------------------------------------------------------------------------------------------------------
-- The tracked set (spec §3.6, decision 8): what `state` reads, from the active spec's registrations.

local def = {
    abilities = {},
    abilityIds = {},
    abilitySlot = {},
    resources = {},
    auras = {},
    auraIds = {},
    talents = {},
    units = {},
}

local HANDS = { mainhand = 1, offhand = 2 }

-- The spell IDs of a registration: its `id`, then its `copy` IDs (rank order), positive numbers only.
local function idsOf(obj)
    local ids = {}
    if type(obj.id) == "number" and obj.id > 0 then
        ids[1] = obj.id
    end
    local copy = obj.copy
    if type(copy) == "number" and copy > 0 then
        ids[#ids + 1] = copy
    elseif type(copy) == "table" then
        for _, v in ipairs(copy) do
            if type(v) == "number" and v > 0 then
                ids[#ids + 1] = v
            end
        end
    end
    return ids
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then
            keys[#keys + 1] = k
        end
    end
    sort(keys)
    return keys
end

local resourceKey, auraKey = {}, {}

local function buildDef()
    for _, list in pairs(def) do
        wipe(list)
    end
    wipe(resourceKey)
    wipe(auraKey)
    local slotByKey = {}
    for _, k in ipairs(sortedKeys(class.resources)) do
        local r = class.resources[k]
        local swing, value = 0, nil
        local model = r.state and r.state.regenModel
        if model then
            for _, m in pairs(model) do
                if m.swing and HANDS[m.swing] and swing == 0 then
                    swing, value = HANDS[m.swing], m.value
                end
            end
        end
        local d = {
            key = k,
            type = r.type,
            token = k:upper(),
            max = 100,
            rest = ns.ResourceRegenerates(k) and 100 or 0,
            swing = swing,
            swingValue = value,
        }
        insert(def.resources, d)
        resourceKey[#def.resources] = k
        slotByKey[k] = #def.resources
    end
    for _, k in ipairs(sortedKeys(class.abilities)) do
        local a = class.abilities[k]
        if a.key == k and k ~= "global_cooldown" then
            local ids = idsOf(a)
            if #ids > 0 then
                insert(def.abilities, a)
                def.abilityIds[#def.abilities] = ids
                local spends = rawget(a, "spend") ~= nil or a.funcs and a.funcs.spend ~= nil
                local slot = spends and slotByKey[a.spendType or class.primaryResource] or 0
                def.abilitySlot[#def.abilities] = slot
            end
        end
    end
    for _, id in ipairs(I.extra.abilities) do
        insert(def.abilities, { key = "track_" .. id, id = id, cooldown = 0 })
        def.abilityIds[#def.abilities] = { id }
        def.abilitySlot[#def.abilities] = 0
    end
    for _, k in ipairs(sortedKeys(class.auras)) do
        local a = class.auras[k]
        if a.key == k then
            local ids = idsOf(a)
            if #ids > 0 then
                insert(def.auras, a)
                def.auraIds[#def.auras] = ids
                auraKey[#def.auras] = k
            end
        end
    end
    for _, id in ipairs(I.extra.auras) do
        insert(def.auras, { key = "track_" .. id, id = id })
        def.auraIds[#def.auras] = { id }
    end
    local seen = {}
    for _, k in ipairs(sortedKeys(class.talents)) do
        local v = class.talents[k]
        if type(v) == "table" and type(v[2]) == "number" and not seen[v[2]] then
            seen[v[2]] = true
            insert(def.talents, { key = k, spell = v[2], max = v[3] or 1 })
        end
    end
    def.units[1], def.units[2] = "player", "target"
    for _, u in ipairs(I.extra.units) do
        insert(def.units, u)
    end
end

--- Rebuilds the tracked set from the active spec (decision 8). Called from Hekili:SpecializationChanged, after every
--- registration. Allocates; SpecChanged only.
function VS.SpecChanged()
    buildDef()
    I.Build(def, GetTime())
end

--- The fold (spec §5.2 steps 1, 2 and 4 without casts), called only from Hekili.Update after its guards.
---@param cutoff number GetTime() at the drain's entry
function VS.Drain(cutoff)
    if not I.built then
        return
    end
    local t0 = debugprofilestop()
    S.RunPolls(cutoff)
    I.Fold(cutoff, false)
    I.Settle(cutoff)
    I.drainMs, I.drainCasts = debugprofilestop() - t0, 0
end
