-- Game/State/Adapter.lua
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
local floor = math.floor

local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

-- The bridge, and the debug handle (/run print(Hekili.Virtual.State.Snapshot()); ForeverProbe's Calib.lua). Not for
-- content: the content addons read the client through Hekili.Client and the belief through their environment names.
Hekili.Virtual = { State = VS, Events = I.Events }

-- The trace (event-facade spec §5): facade reads and events write into Hekili's snapshot while it debugs, and each
-- display's snapshot log opens with VirtualState's own Snapshot().
ns.Facade.Attach(Hekili)
do
    local setupDebug = Hekili.SetupDebug
    function Hekili:SetupDebug(display)
        setupDebug(self, display)
        if self.ActiveDebug and display then
            local ok, s = pcall(VS.Snapshot) -- a raising Snapshot must not abort Hekili's snapshot
            self:Debug(ok and "%s" or "[vs] snapshot failed: %s", s)
        end
    end
end

-- The urgent lane (spec §4.4): shortens Hekili's wait before its next cycle; never interrupts one.
I.urgent = function(event)
    Hekili:ForceUpdate(event)
end

-- Our own actions reach the displays' steady icons (Engine/Output.lua; absent where a test loads the state alone).
I.acted = ns.Output and ns.Output.Acted

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
    pets = {}, -- the guardians: { key, cap, duration } of each pet registered with a `cap` (Families/Pets.lua)
}

local HANDS = { mainhand = 1, offhand = 2 }
local NO_PETS = {} -- a test's stand-in class may have no `pets`
local DECAY = "__decay" -- the generated entry's reserved name in a regen model
local TAKEN = "__taken" -- the generated incoming-rage entry's (tank design §1.2.5)

local function eval(v)
    if type(v) == "function" then
        return v()
    end
    return v
end

-- The sim's stepped decay (stepped-decay design §3.3): a regen-model entry Hekili's forecast steps like a class's,
-- `value` (negative, talent-scaled) every `interval`, never in combat. Its beats are the belief's (from its last
-- quantum), or start at a pausing aura's expiry (an entry flagged `pausesDecay`) while one is up in the sim: Hekili's
-- forecast removes an entry whose `stop` holds, so the pause is in `last`, not `stop`. Built once per regen model, at a
-- build.
local function decayEntry(key, model, meta, powerType)
    local e = { resource = key, interval = meta.decayInterval }
    function e.value()
        return -eval(meta.decay) * eval(meta.decayInterval)
    end
    function e.last()
        -- Hekili's forecast starts at now + offset and steps every beat after `last`; after an advance `actual` holds
        -- every beat to there already, so the anchor rolls forward to the last beat at or before it (as Warrior.lua's
        -- swing entries do).
        local iv, t, a = eval(meta.decayInterval), state.now + state.offset, 0
        for _, m in pairs(model) do
            -- a pausing aura present at the reset (up, or expired in the sim since): the beats start at its expiry
            local b = m.pausesDecay and m.aura and not (m.swing or m.debuff) and state.buff[m.aura]
            if b and b.expires > a then
                a = b.expires
            end
        end
        if a == 0 then
            a = VS.DecayAnchor(powerType)
            if a == 0 then
                return t - iv -- the belief inactive: a quantum at the forecast's start
            end
        end
        if a > t then
            -- a beat at the expiry, with its last tick: State.lua keeps one point per instant, 10 - 1.25 in either
            -- order (not at a cap: above 99 or below 1.25 rage the order changes what the clamp keeps)
            return a - iv
        end
        return a + floor((t - a) / iv) * iv
    end
    function e.stop()
        return state.time > 0
    end
    return e
end

-- The sim's rage from hits on the player (tank design §1.2.5): a regen-model entry Hekili's forecast steps every
-- second from the reset, the belief's learned rate (VS.TakenRate) a step, removed out of combat (`stop`). The belief
-- never reads it: real hits are observed. Built once per regen model, at a build. Its anchor rolls like `__decay`'s:
-- a re-forecast keeps the reset's grid (the last whole beat at or before the forecast's start is already in `actual`).
local function takenEntry(key, powerType)
    local e = { resource = key, interval = 1 }
    function e.value()
        return VS.TakenRate(powerType, state.now)
    end
    function e.last()
        return state.now + floor(state.offset)
    end
    function e.stop()
        return state.time == 0
    end
    return e
end

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
        local swing, value, offValue, auraRegen, swingAura = 0, nil, nil, nil, nil
        local crit, offCrit -- a white crit's extra amount by hand (Resources.lua, I.SwingCrit)
        local taken -- the paying entry's gain from a hit on the player (Resources.lua, tank design §1.2)
        local model = r.state and r.state.regenModel
        if model then
            for name, m in pairs(model) do
                if m.swing == "offhand" then
                    offValue, offCrit = m.value, m.crit
                elseif m.swing and HANDS[m.swing] and swing == 0 then
                    swing, value, swingAura = HANDS[m.swing], m.value, m.aura -- `aura`: swings pay only while it is up
                    crit, taken = m.crit, m.taken
                elseif
                    name ~= DECAY
                    and name ~= TAKEN
                    and not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting)
                then
                    auraRegen = auraRegen or {}
                    -- a player aura's regen { aura, interval, value }, or without `aura` a periodic one credited in
                    -- combat; either may name a `talent` (Resources.lua). Hekili's other gates are unseen here, so an
                    -- entry with one is not forwarded.
                    auraRegen[#auraRegen + 1] = m
                end
            end
        end
        local meta = r.state and r.state.meta
        local iv = meta and meta.decay ~= nil and eval(meta.decayInterval)
        if model and type(iv) == "number" and iv > 0 and model[DECAY] == nil then
            model[DECAY] = decayEntry(k, model, meta, r.type)
        end
        if model and type(taken) ~= "function" then
            model[TAKEN] = nil -- a stale entry out of the forecast's event list
        elseif model and model[TAKEN] == nil then
            model[TAKEN] = takenEntry(k, r.type)
        end
        if swing == 0 and offValue ~= nil then
            swing, value, offValue, crit, offCrit = 2, offValue, nil, offCrit, nil -- the off hand alone pays it
        end
        local d = {
            key = k,
            type = r.type,
            token = k:upper(),
            max = r.state and r.state.meta and r.state.meta.max or 100, -- a number or a state-bound function
            rest = ns.ResourceRegenerates(k) == true, -- a regenerating resource rests at its maximum (Resources.lua)
            swing = swing,
            swingValue = value,
            swingOff = offValue,
            swingCrit = crit,
            swingOffCrit = offCrit,
            swingAura = swingAura,
            taken = taken,
            auraRegen = auraRegen,
            decay = r.state and r.state.meta and r.state.meta.decay, -- out-of-combat loss per second (Resources.lua)
            decayInterval = r.state and r.state.meta and r.state.meta.decayInterval, -- seconds per quantum (stepped)
            fsr = r.state and r.state.meta and r.state.meta.fsr, -- the five-second rule's parts (Resources.lua, C3)
            -- the class's default share of an avoided cast's cost given back, for an ability with `refundOnAvoid = true`
            -- (a number, 0-1; Families/Now.lua's Obs.Avoided); the sim never reads it: it does not roll avoidance
            refundOnAvoid = r.state and r.state.meta and r.state.meta.refundOnAvoid,
            base = r.state and r.state.meta and r.state.meta.base, -- the pool's base power (Families/Casts.lua)
            mult = r.state and r.state.regenMult, -- the rate multipliers, out of the regen model (Spec.lua, C3b)
        }
        insert(def.resources, d)
        slotByKey[k] = #def.resources
        -- the race pack's resource and cost modifiers (Engine/Schema/Races.lua, event-facade spec §12b): every resource of the class,
        -- but a maximum modifier never scales a point resource (ns.ResourceIsPoints, Constants.lua)
        local race = ns.raceMods
        if race then
            d.maxMods, d.costMods = not ns.ResourceIsPoints(k) and race.maxMods or nil, race.costMods
        end
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
            if #ids == 0 and rawget(a, "weaponEnchant") ~= nil and type(a.id) == "number" then
                ids[1] = a.id -- an id-less weapon-enchant pseudo-aura (C4): RegisterAura's negative pseudo-ID
            end
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
    for _, k in ipairs(sortedKeys(class.pets or NO_PETS)) do
        local p = class.pets[k]
        if p.token == k and type(p.cap) == "number" and p.cap >= 1 then -- its token's entry, not an alias's
            insert(def.pets, { key = k, cap = floor(p.cap), duration = p.duration })
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
