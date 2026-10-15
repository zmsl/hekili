-- VirtualState/Adapter.lua
-- VirtualState's glue to Hekili (spec §3.6, §4.6, §5): VirtualState.Start at PLAYER_LOGIN, the tracked set from the
-- active spec's registrations (SpecChanged), and Drain: the fold, whose own casts write their effects through the
-- class files' `now` handlers (Families/Now.lua), never through Hekili's `state`.
-- Hekili's across-reset caches (cast history, the real queue, the swing fields) come from the combat-log rows.
-- Loads after Core.lua.

local addon, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources

local Hekili = _G[addon]
local state, class = Hekili.State, Hekili.Class
local GetTime, CreateFrame = ns.Facade.GetTime, ns.Facade.CreateFrame
local debugprofilestop = debugprofilestop
local insert, sort = table.insert, table.sort

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- The debug handle: /run print(Hekili.VirtualState.Snapshot())
Hekili.VirtualState = VS

-- The trace (event-facade spec §5): facade reads and events write into Hekili's snapshot while it debugs, and each
-- display's snapshot log opens with VirtualState's own Snapshot().
ns.Facade.Attach(Hekili)
do
    local setupDebug = Hekili.SetupDebug
    function Hekili:SetupDebug(display)
        setupDebug(self, display)
        if self.ActiveDebug and display then
            self:Debug("%s", VS.Snapshot())
        end
    end
end

-- The urgent lane (spec §4.4): shortens Hekili's wait before its next cycle; never interrupts one.
I.urgent = function(event)
    Hekili:ForceUpdate(event)
end

-- Start once, at PLAYER_LOGIN, on a frame of its own (a subscriber of the event facade like Hekili's frames).
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

local function buildDef()
    for _, list in pairs(def) do
        wipe(list)
    end
    local slotByKey = {}
    for _, k in ipairs(sortedKeys(class.resources)) do
        local r = class.resources[k]
        local swing, value, offValue, auraRegen = 0, nil, nil, nil
        local model = r.state and r.state.regenModel
        if model then
            for _, m in pairs(model) do
                if m.swing == "offhand" then
                    offValue = m.value
                elseif m.swing and HANDS[m.swing] and swing == 0 then
                    swing, value = HANDS[m.swing], m.value
                elseif not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting) then
                    auraRegen = auraRegen or {}
                    -- a player aura's regen { aura, interval, value }, or without `aura` a periodic one credited in
                    -- combat; either may name a `talent` (Resources.lua). Hekili's other gates are unseen here, so an
                    -- entry with one is not forwarded.
                    auraRegen[#auraRegen + 1] = m
                end
            end
        end
        if swing == 0 and offValue ~= nil then
            swing, value, offValue = 2, offValue, nil -- the off hand alone pays it
        end
        local d = {
            key = k,
            type = r.type,
            token = k:upper(),
            max = r.state and r.state.meta and r.state.meta.max or 100, -- a number or a state-bound function
            rest = ns.ResourceRegenerates(k) and 100 or 0,
            swing = swing,
            swingValue = value,
            swingOff = offValue,
            auraRegen = auraRegen,
            decay = r.state and r.state.meta and r.state.meta.decay, -- out-of-combat loss per second (Resources.lua)
        }
        insert(def.resources, d)
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

--- Rebuilds the tracked set from the active spec (decision 8). Called at the end of Hekili:SpecializationChanged,
--- after every registration. Allocates; SpecChanged only.
function VS.SpecChanged()
    buildDef()
    I.Build(def, GetTime())
end

----------------------------------------------------------------------------------------------------------------------
-- The drain (event-facade spec §12a): our casts' effects are written by the `now` handlers as the fold reaches them
-- (Families/Now.lua); Hekili's state is never reset or replayed here.

--- The fold, called only from Hekili.Update after its guards: this frame's staged observations, the polls, the fold
--- to the cut-off, the settle, and Hekili's rescan flags. Allocates nothing.
---@param cutoff number GetTime() at the drain's entry
function VS.Drain(cutoff)
    if not I.built then
        return
    end
    local t0 = debugprofilestop()
    local genP, genT = VS.AuraGen("player"), VS.AuraGen("target")
    local casts = I.castsRun
    S.Flush() -- this frame's staged observations first, whichever OnUpdate runs first (poll 3's Queued(0) follows them)
    S.RunPolls(cutoff)
    I.Fold(cutoff)
    I.Settle(cutoff)
    -- Hekili rescans a unit's auras when its believed set moved (G1)
    if VS.AuraGen("player") ~= genP then
        state.player.updated = true
    end
    if VS.AuraGen("target") ~= genT then
        state.target.updated = true
    end
    I.drainMs, I.drainCasts = debugprofilestop() - t0, I.castsRun - casts
end
