-- VirtualState/Adapter.lua
-- VirtualState's glue to Hekili (spec §3.6, §4.6, §5): VirtualState.Start at PLAYER_LOGIN, the tracked set from the
-- active spec's registrations (SpecChanged), and Drain: the fold plus "apply through the spec", which runs each of
-- our real casts through Hekili's own registered functions on `state` and records what changed as `modelled` samples.
-- Hekili's across-reset caches (cast history, the real queue, the swing fields) come from the combat-log rows.
-- Loads after Core.lua. The apply follows Hekili's own simulation (Core.lua:1984-2045) and keeps Hekili's credits.

local addon, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local CAST_SUCCESS, CHANNEL_START = Obs.CastSuccess, Obs.ChannelStart

local Hekili = _G[addon]
local state, class = Hekili.State, Hekili.Class
local spendResources = ns.spendResources
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

local resourceKey, auraKey, auraId = {}, {}, {}

local function buildDef()
    for _, list in pairs(def) do
        wipe(list)
    end
    wipe(resourceKey)
    wipe(auraKey)
    wipe(auraId)
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
                auraKey[#def.auras], auraId[#def.auras] = k, ids[1]
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

-- Read-before arrays for the apply (spec §5.3), sized at SpecChanged.
local resBefore, cdBefore, buffExp, buffApp, buffCnt, debuffExp, debuffApp, debuffCnt = {}, {}, {}, {}, {}, {}, {}, {}
local gcdBefore = 0

--- Rebuilds the tracked set from the active spec (decision 8). Called at the end of Hekili:SpecializationChanged,
--- after every registration. Allocates; SpecChanged only.
function VS.SpecChanged()
    buildDef()
    I.Build(def, GetTime())
    for i = 1, #def.resources do
        resBefore[i] = 0
    end
    for a = 1, #def.abilities do
        cdBefore[a] = 0
    end
    for j = 1, #def.auras do
        buffExp[j], buffApp[j], buffCnt[j], debuffExp[j], debuffApp[j], debuffCnt[j] = 0, 0, 0, 0, 0, 0
    end
end

----------------------------------------------------------------------------------------------------------------------
-- Apply through the spec (spec §5.2, §5.3).

local finishEvent = { type = "CAST_FINISH", action = "", time = 0, start = 0 }

local function field(t, k)
    return t and rawget(t, k) or 0
end

-- Step 3.5: the tracked fields before the apply. Each tracked resource's `actual` is set to the belief at the cast
-- first, so a spend is never clipped at 0 by a stale `actual` (the cast succeeded: the game had the cost).
local function readBefore(t)
    local R = I.res
    for r = 1, R.n do
        local res = rawget(state, resourceKey[r])
        if res then
            local v = VS.Power(R.type[r], t).est
            res.actual, res.fcount = v, 0
            resBefore[r] = v
        end
    end
    local A, cooldown = I.ab, state.cooldown
    for a = 1, A.n do
        cdBefore[a] = field(rawget(cooldown, A.key[a]), "expires")
    end
    gcdBefore = field(rawget(cooldown, "global_cooldown"), "expires")
    local buff, debuff = state.buff, state.debuff
    for j = 1, I.auras.nAura do
        local k = auraKey[j]
        local b, d = k and rawget(buff, k), k and rawget(debuff, k)
        buffExp[j], buffApp[j], buffCnt[j] = field(b, "expires"), field(b, "applied"), field(b, "count")
        debuffExp[j], debuffApp[j], debuffCnt[j] = field(d, "expires"), field(d, "applied"), field(d, "count")
    end
end

-- Step 3.7: what changed, as `modelled` samples at t.
local function readAfter(t, kind, a)
    local R, spellID = I.res, I.ab.qid[a]
    for r = 1, R.n do
        local res = rawget(state, resourceKey[r])
        if res then
            local delta = res.actual - resBefore[r]
            if delta > 1e-6 or delta < -1e-6 then
                I.ResourceShift(r, delta, t, kind)
            end
            if delta > 1e-6 then
                I.Log.Energize(spellID, delta, R.type[r], R.max[r], t) -- the cast gave us resource
            end
        end
    end
    local A, cooldown = I.ab, state.cooldown
    for a = 1, A.n do
        local cd = rawget(cooldown, A.key[a])
        local e = field(cd, "expires")
        if e ~= cdBefore[a] then
            if A.ch[a] then
                I.ChargesModel(a, field(cd, "charge"), e, t, kind)
            else
                I.CooldownModel(a, e, field(cd, "duration"), t, kind)
            end
        end
    end
    local g = field(rawget(cooldown, "global_cooldown"), "expires")
    if g ~= gcdBefore then
        I.GcdModel(g, t, kind)
    end
    local buff, debuff = state.buff, state.debuff
    for j = 1, I.auras.nAura do
        local k = auraKey[j]
        if k then
            local b, d = rawget(buff, k), rawget(debuff, k)
            local be, de = field(b, "expires"), field(d, "expires")
            if be ~= buffExp[j] or field(b, "count") ~= buffCnt[j] then
                I.AuraModel(1, j, field(b, "applied"), be, field(b, "count"), t, kind, false)
                I.Log.Aura(1, j, auraId[j], buffExp[j], be, t)
            end
            if (de ~= debuffExp[j] or field(d, "count") ~= debuffCnt[j]) and I.auras.n >= 2 then
                I.AuraModel(2, j, field(d, "applied"), de, field(d, "count"), t, kind, true)
                I.Log.Aura(2, j, auraId[j], debuffExp[j], de, t)
            end
        end
    end
end

local function gcdStep(ability)
    if ability.gcd ~= "off" and state.cooldown.global_cooldown.remains == 0 then
        state.setCooldown("global_cooldown", state.gcd.execute)
    end
end

local function cooldownStep(key, ability)
    if ability.charges and ability.charges > 1 and ability.recharge > 0 then
        state.spendCharges(key, 1)
    elseif ability.cooldown > 0 then
        state.setCooldown(key, ability.cooldown)
    end
end

-- Steps 3.3-3.7 for one own cast of ability index `a` at t.
local function apply(kind, a, t)
    local key = I.ab.key[a]
    local ability = key and class.abilities[key]
    if not ability or not ability.id or ability.id <= 0 then
        return false
    end
    -- 3.3: combat start (R2), the value PLAYER_REGEN_DISABLED writes (Events.lua:856-863)
    if ability.startsCombat and state.combat == 0 then
        state.combat = t - 0.01
    end
    readBefore(t)
    local now = state.now
    if kind == CHANNEL_START then
        state.offset, state.delay = t - now, 0
        gcdStep(ability)
        cooldownStep(key, ability)
        state:RunHandler(key) -- takes the channel path (State.lua:6135-6137)
        spendResources(key)
    elseif (ability.cast or 0) > 0 and not ability.channeled then
        -- a hard cast, at its finish: the GCD at its start, then the CAST_FINISH event at the finish
        local started = I.ab.castStartT[a]
        if started > 0 and started < t then
            state.offset, state.delay = started - now, 0
            gcdStep(ability)
        end
        state.offset, state.delay = t - now, 0
        finishEvent.action, finishEvent.time, finishEvent.start = key, t, started
        state:HandleEvent(finishEvent) -- charges/cooldown, spend, handler (State.lua:5921-5953)
    else
        state.offset, state.delay = t - now, 0
        gcdStep(ability)
        cooldownStep(key, ability)
        spendResources(key)
        state:RunHandler(key)
    end
    readAfter(t, kind, a)
    return true
end
I.Apply = apply

-- Applies (or the drain's first reset) whose spec code raised, and the last error (Snapshot's log line); the drain
-- carries on so its restore always runs.
I.applyErrors, I.applyError = 0, nil

--- The fold plus apply through the spec (spec §5.2), called only from Hekili.Update after its guards. Allocates
--- nothing beyond what Hekili's own reset and handlers allocate.
---@param cutoff number GetTime() at the drain's entry
function VS.Drain(cutoff)
    if not I.built then
        return
    end
    local t0 = debugprofilestop()
    local genP, genT = VS.AuraGen("player"), VS.AuraGen("target")
    S.Flush() -- this frame's staged observations first, whichever OnUpdate runs first (poll 3's Queued(0) follows them)
    S.RunPolls(cutoff) -- step 1
    local applied, reset, resetOk = 0, false, false
    while true do
        local kind, a, t = I.Fold(cutoff, true) -- steps 2 and 3.8
        if not kind then
            break
        end
        local key = I.ab.key[a]
        if key and class.abilities[key] then -- a track_<id> extra has no ability to apply
            I.pinned = t -- 3.1: the facade answers at the cast's time (R1)
            if not reset then
                reset = true
                local err
                resetOk, err = pcall(state.reset) -- 3.2: once, full ("Primary", State.lua:6181-6184)
                if not resetOk then
                    I.applyErrors, I.applyError = I.applyErrors + 1, err
                end
            end
            if resetOk then
                local ok, done = pcall(apply, kind, a, t)
                if not ok then
                    I.applyErrors, I.applyError = I.applyErrors + 1, done
                elseif done then
                    applied = applied + 1
                end
            end
        end
    end
    -- 4: restore, unpin, settle, and one more full reset when anything was applied (R2, R3)
    state.offset, state.delay = 0, 0
    I.pinned = nil
    I.Settle(cutoff)
    if reset then
        -- the trailing reset rescans both units' auras, so an apply-time write outside the tracked set never survives
        state.player.updated, state.target.updated = true, true
        state.reset()
    else
        -- 5: Hekili rescans a unit's auras when its believed set moved (G1)
        if VS.AuraGen("player") ~= genP then
            state.player.updated = true
        end
        if VS.AuraGen("target") ~= genT then
            state.target.updated = true
        end
    end
    I.drainMs, I.drainCasts = debugprofilestop() - t0, applied
end
