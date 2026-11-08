-- Game/State/Sources/Presence/CooldownViewer.lua
-- The Cooldown Manager leaf (cdm-default spec §3; providers spec §2.4 as amended). The map (§3.1): every cooldownID
-- of categories 0-8, unlearned included, to one pack aura j, or ambiguous (-a, amb[a] its tracked js), built out of
-- combat. The collect (§3.2): every child of the four viewers kept once as a slot, item or not, in arrays preallocated
-- to MAX_SLOTS; past that a child is ignored and counted (overflow). A new frame is a new slot; a slot is never reused.
-- The sweep (§3.2): at poll 15, per viewer IsVisible and GetNumChildren once, per slot four rawgets; a reading change
-- moves its thing's counters (aura j, unit u: nUp, nNone, nStale) in O(1); the moved things' tUp/tNone are recomputed
-- over the live slots (O(slots)); a reduced UP or DOWN change goes to onEdge. The seen rule (§2.2a, decision 115): a
-- silent slot answers NONE only for an application it was seen holding (its record up, sSeen >= applied, its last held
-- unit). A target change makes target and NONE slots settle for SETTLE: their target answers are stale (§3.4). A raise
-- in the sweep turns the leaf off for the session (§3.5). Read, never write: rawget on items, on Blizzard frames only
-- GetChildren, GetNumChildren and IsVisible; no hooks of any kind (§3.3, §3.5).
-- The idea of reading the viewer's items for presence, the all-viewers presence bit, the hidden-viewer rule and the
-- spell mapping are TellMeWhen's (Cybeloras), GPL-3.0; ideas only, no code copied.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

-- In category order 0-3 (CV §2): every viewer's items are evidence (F6), their role plays no part.
local VIEWERS =
    { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local MAX_SLOTS = 128
local SETTLE = 0.05 -- shortcut: a guess until the CDM-O probe measures the target switch (spec D5)
local STOPPED = "Forever: Cooldown Manager reading stopped for this session after an error: %s"

local cdvToJ = {} -- cooldownID -> j, or -a (ambiguous: amb[a] lists its tracked js); built out of combat
local amb = {} -- a -> { j, ... }
local mappable = {} -- j -> true when some cooldownID's candidates name it (alone or ambiguously)
local slotOf = setmetatable({}, { __mode = "k" }) -- child frame -> slot: the only in-combat insert (a new child)
local known = { 0, 0, 0, 0 } -- children collected per viewer (GetNumChildren at the last collect)

-- The slots, preallocated: the frame, its viewer, the aura it is counted for (sJ; sAmb unused), what it is counted as
-- (sAns, sUnit: sUnit is also the last plain held unit, kept through silence) since sT, the seen rule's last held time
-- and last plain cooldownID (sSeen, sCd, §2.2a), the end of a target settle (sSettle, §3.4). sAns 0 not counted, else
-- UP, NONE or STALE (a hidden viewer's or a settling slot: what it would answer, not live).
local sFrame, sV, sJ, sAmb, sAns, sUnit, sT, sSeen, sCd, sSettle = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
for s = 1, MAX_SLOTS do
    sFrame[s], sV[s], sJ[s], sAmb[s], sAns[s], sUnit[s], sT[s] = false, 0, 0, 0, 0, 0, 0
    sSeen[s], sCd[s], sSettle[s] = 0, 0, 0
end

local NOT, UP, NONE, STALE = 0, 1, 2, 3
local UNIT = { player = 1, target = 2 }

-- The things' counters, by k = (u - 1) * AURA_UNIT + j, zeroed for both units at activation (preallocated: the
-- target's keys are in the hash part); the last reduced state (onEdge on a change); live slots per aura (covered).
local cUp, cNone, cStale, tUp, tNone, last, live = {}, {}, {}, {}, {}, {}, {}
local touched, mark, nTouched = {}, {}, 0 -- the things a sweep moved, each once
local vis = { false, false, false, false } -- each viewer's IsVisible at this sweep

local Q = {
    name = "viewer", -- l10n: verbatim
    scope = "self",
    covered = 0,
    onEdge = nil,
    MAX_SLOTS = MAX_SLOTS,
    nSlots = 0,
    overflow = 0, -- children past MAX_SLOTS, ignored
    errors = 0, -- sweeps that raised (the first turns the leaf off for the session)
    map = cdvToJ, -- read-only views for the tests and the snapshot
    amb = amb,
    slotOf = slotOf,
    seen = sSeen,
}
local active, api0, broken = false, nil, false

-- One candidate spell into the item's set of js (0: untracked or secret; either makes the item ambiguous).
local function note(api, byId, js, x)
    if api.issecretvalue(x) then
        js[0] = true
    elseif x ~= nil then
        js[byId[x] or 0] = true
    end
end

-- A candidate and GetOverrideSpell's answer for it (a plain spell ID read from the info, never a secret).
local function noteOver(api, byId, js, x, over)
    note(api, byId, js, x)
    x = Plain(api, x)
    if x ~= nil and over then
        local ok, o = pcall(over, x)
        if ok then
            note(api, byId, js, o)
        end
    end
end

-- An item's aura candidates (§2.2): its linkedSpellIDs when it has any (F4: the base spell stays dark), else spellID,
-- overrideSpellID and overrideTooltipSpellID, each also through GetOverrideSpell. Never the singular linkedSpellID
-- (the viewer fills it with the secret aura id: TMW Auras.lua:960-1010).
local function candidates(api, byId, info, js)
    local links = Plain(api, info.linkedSpellIDs)
    if type(links) == "table" and #links > 0 then -- the length only: an element is read through note (issecretvalue)
        for n = 1, #links do
            note(api, byId, js, links[n])
        end
        return
    end
    local C = api.C_Spell
    local over = C and C.GetOverrideSpell
    noteOver(api, byId, js, info.spellID, over)
    noteOver(api, byId, js, info.overrideSpellID, over)
    noteOver(api, byId, js, info.overrideTooltipSpellID, over)
end

-- The map (§3.1), out of combat (allocates: the getters' tables, the candidate sets).
local function build(api, def)
    for k in pairs(cdvToJ) do
        cdvToJ[k] = nil
    end
    for k in pairs(amb) do
        amb[k] = nil
    end
    for k in pairs(mappable) do
        mappable[k] = nil
    end
    local CV = api.C_CooldownViewer
    if not CV or not def then
        return false
    end
    local ok, avail = pcall(CV.IsCooldownViewerAvailable) -- secret: Plain next
    if not ok or Plain(api, avail) ~= true then
        return false
    end
    local byId = {}
    for j = 1, #def.auraIds do
        for _, sid in ipairs(def.auraIds[j]) do
            byId[sid] = j
        end
    end
    for c = 0, 8 do
        local okS, set = pcall(CV.GetCooldownViewerCategorySet, c, true) -- secret: Plain next
        set = Plain(api, set)
        if okS and type(set) == "table" then
            for n = 1, #set do
                local id = Plain(api, set[n])
                local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, id) -- secret: Plain next
                info = Plain(api, info)
                if id and okI and type(info) == "table" and cdvToJ[id] == nil then
                    local js = {}
                    candidates(api, byId, info, js)
                    local one, many = nil, false
                    for j in pairs(js) do
                        if j > 0 then
                            mappable[j] = true
                            many = many or (one ~= nil)
                            one = one or j
                        end
                    end
                    if one and (many or js[0]) then
                        local list = {}
                        for j in pairs(js) do
                            if j > 0 then
                                list[#list + 1] = j
                            end
                        end
                        amb[#amb + 1] = list
                        cdvToJ[id] = -#amb
                    elseif one then
                        cdvToJ[id] = one
                    end
                end
            end
        end
    end
    return true
end

-- One child: kept as a slot once; past MAX_SLOTS ignored and counted. Allocates only slotOf's entry.
local function take(c, v)
    if slotOf[c] then
        return
    end
    local s = Q.nSlots + 1
    if s > MAX_SLOTS then
        Q.overflow = Q.overflow + 1
        return
    end
    Q.nSlots, sFrame[s], sV[s] = s, c, v
    slotOf[c] = s
end

-- The collect (§3.2): `full` walks every child (activation, rebuild, combat end); otherwise only the indices past the
-- last count when GetNumChildren grew (in combat: varargs through select, no table).
local function collect(api, full)
    if full then
        Q.overflow = 0 -- recounted: each ignored child once
    end
    for v = 1, #VIEWERS do
        local f = Plain(api, api[VIEWERS[v]])
        local n = f and f.GetNumChildren and Plain(api, f:GetNumChildren())
        if type(n) == "number" then
            local from = full and 1 or known[v] + 1
            for i = from, n do
                local c = Plain(api, (select(i, f:GetChildren())))
                if type(c) == "table" then
                    take(c, v)
                end
            end
            known[v] = n -- a removal lowers it, so the next growth reads the new indices
        end
    end
end

-- Un-counts slot s (what sAns/sUnit/sJ say it is counted as) and marks it not counted. Allocates nothing.
local function uncount(s)
    local a = sAns[s]
    if a == NOT then
        return
    end
    local j = sJ[s]
    local k = (sUnit[s] - 1) * I.AURA_UNIT + j
    sAns[s] = NOT
    if a == UP then
        cUp[k] = cUp[k] - 1
    elseif a == NONE then
        cNone[k] = cNone[k] - 1
    else
        cStale[k] = cStale[k] - 1
    end
    if a ~= STALE then
        live[j] = live[j] - 1
        if live[j] == 0 then
            Q.covered = Q.covered - 1
        end
    end
    if not mark[k] then
        mark[k], nTouched = true, nTouched + 1
        touched[nTouched] = k
    end
end

-- Counts slot s as answer `a` for aura j on unit u, beginning at t. Allocates nothing.
local function count(s, j, u, a, t)
    sJ[s], sUnit[s], sAns[s], sT[s] = j, u, a, t
    if a == NOT then
        return
    end
    local k = (u - 1) * I.AURA_UNIT + j
    if a == UP then
        cUp[k] = cUp[k] + 1
    elseif a == NONE then
        cNone[k] = cNone[k] + 1
    else
        cStale[k] = cStale[k] + 1
    end
    if a ~= STALE then
        live[j] = live[j] + 1
        if live[j] == 1 then
            Q.covered = Q.covered + 1
        end
    end
    if not mark[k] then
        mark[k], nTouched = true, nTouched + 1
        touched[nTouched] = k
    end
end

-- The seen rule starts over for slot s (§2.2a): un-counted first, so no count is left with no live slot behind it.
local function reset(s)
    uncount(s)
    sSeen[s], sUnit[s] = 0, 0
end

-- One sweep (§3.2), under one pcall: each viewer's visibility and growth, then every slot's reading against what it is
-- counted as. Un-count before count, so a raise between the two leaves the slot not counted, never counted twice.
local function sweep(t)
    local api = api0
    local issecret = api.issecretvalue
    local U = I.auras
    for v = 1, #VIEWERS do
        local f = Plain(api, api[VIEWERS[v]])
        local n = f and f.GetNumChildren and Plain(api, f:GetNumChildren())
        if type(n) == "number" and n ~= known[v] then
            for i = known[v] + 1, n do -- growth: the new indices only (varargs, no table)
                local c = Plain(api, (select(i, f:GetChildren())))
                if type(c) == "table" then
                    take(c, v)
                end
            end
            known[v] = n
        end
        vis[v] = f ~= nil and f.IsVisible ~= nil and Plain(api, f:IsVisible()) == true
    end
    for s = 1, Q.nSlots do
        local item = sFrame[s]
        local j, u, a = 0, 0, NOT
        local id = Plain(api, rawget(item, "cooldownID"))
        if (id or 0) ~= sCd[s] then -- (re)assigned, released or secret: a new mapping (same-aura re-points too)
            reset(s)
            sCd[s] = id or 0
        end
        local m = id ~= nil and Plain(api, rawget(item, "layoutIndex")) ~= nil and cdvToJ[id]
        if m and m > 0 then -- configured and mapped to one aura (an ambiguous item counts for none)
            local aid = rawget(item, "auraInstanceID")
            if issecret(aid) or aid ~= nil then -- secret: only tested, never compared
                local unit = Plain(api, rawget(item, "auraDataUnit"))
                u = unit ~= nil and UNIT[unit] or 0 -- a secret, nil or other unit: not live for either
                if u > 0 then
                    j, a = m, UP
                else
                    reset(s) -- held for no unit we track: what it was seen holding says nothing now
                end
            else -- silent: NONE only for the application this slot was seen holding (§2.2a)
                j, u = m, sUnit[s]
                if u > 0 and u <= U.n and sSeen[s] > 0 and U.exp0[u][m] > t and sSeen[s] >= U.applied[u][m] then
                    a = NONE
                end
            end
            if a ~= NOT and (not vis[sV[s]] or u == 2 and sSettle[s] > t) then -- settling: target answers only (§2.2)
                a = STALE
            end
        end
        if a ~= sAns[s] or j ~= sJ[s] or u ~= sUnit[s] then
            uncount(s)
            count(s, j, u, a, t)
        end
        if a == UP then -- every held sweep, not only a change: our refresh moves applied while the item stays held
            sSeen[s] = t
        end
    end
end

-- The things a sweep moved: tUp/tNone recomputed as the latest begin (sT) of a live slot (§2.3: a slot that left takes
-- its time with it), O(slots); then each reduced; an UP or DOWN change goes to onEdge (UNKNOWN fires none). Allocates
-- nothing.
local function reduce(t)
    if nTouched == 0 then
        return
    end
    for i = 1, nTouched do
        local k = touched[i]
        tUp[k], tNone[k] = 0, 0
    end
    for s = 1, Q.nSlots do
        local a = sAns[s]
        if a == UP or a == NONE then
            local k = (sUnit[s] - 1) * I.AURA_UNIT + sJ[s]
            if mark[k] then
                if a == UP and sT[s] > tUp[k] then
                    tUp[k] = sT[s]
                elseif a == NONE and sT[s] > tNone[k] then
                    tNone[k] = sT[s]
                end
            end
        end
    end
    for i = 1, nTouched do
        local k = touched[i]
        mark[k] = false
        local st = I.ReduceFact(cUp[k] + cNone[k], cUp[k], cNone[k], cStale[k], tUp[k], tNone[k])
        if st ~= last[k] then
            last[k] = st
            if st ~= I.UNDECIDED and Q.onEdge then
                local u = k > I.AURA_UNIT and 2 or 1
                Q.onEdge(k - (u - 1) * I.AURA_UNIT, u, st == I.UP, t)
            end
        end
    end
    nTouched = 0
end

--- The sweep at poll 15: reads every slot, moves the counters, then reduces what moved. A raise inside the sweep turns
--- the leaf off for the session (§3.5): it answers nothing from then on, so no frozen answer is applied again; one
--- def.error line. Allocates nothing (a new child's slotOf entry aside; the error path formats once).
function Q.Sweep(t)
    if not active then
        return
    end
    local ok, err = pcall(sweep, t)
    if not ok then
        broken, active, Q.covered = true, false, 0
        Q.errors = Q.errors + 1
        for i = 1, nTouched do
            mark[touched[i]] = false
        end
        nTouched = 0
        local def = I.def
        if def and def.error then
            def.error(STOPPED, tostring(err))
        end
        return
    end
    reduce(t)
end

--- nLive, nUp, nNone, nStale, tUp, tNone for aura `j` on unit `u`. Allocates nothing.
function Q.Counts(j, u)
    local k = (u - 1) * I.AURA_UNIT + j
    if not active or not cUp[k] then
        return 0, 0, 0, 0, 0, 0
    end
    return cUp[k] + cNone[k], cUp[k], cNone[k], cStale[k], tUp[k], tNone[k]
end

--- Builds the map and collects every viewer's children (out of combat), then sweeps once: the state now.
function Q.Activate(api, t, def)
    api0, active = api, api ~= nil and not broken -- off after an error until /reload
    Q.covered, nTouched = 0, 0
    for k in pairs(cUp) do
        cUp[k], cNone[k], cStale[k], tUp[k], tNone[k], last[k], mark[k] = 0, 0, 0, 0, 0, I.UNDECIDED, false
    end
    for j in pairs(live) do
        live[j] = 0
    end
    for s = 1, Q.nSlots do -- a new map: every slot counted afresh, its seen rule started over (§2.2a)
        sJ[s], sAmb[s], sAns[s], sUnit[s], sT[s] = 0, 0, NOT, 0, 0
        sSeen[s], sCd[s], sSettle[s] = 0, 0, 0
    end
    local nAura = def and #def.auraIds or 0
    for j = 1, nAura do
        live[j] = 0
        for u = 1, 2 do
            local k = (u - 1) * I.AURA_UNIT + j
            cUp[k], cNone[k], cStale[k], tUp[k], tNone[k], last[k], mark[k] = 0, 0, 0, 0, 0, I.UNDECIDED, false
            touched[(u - 1) * nAura + j] = touched[(u - 1) * nAura + j] or 0
        end
    end
    if active then
        if build(api, def) then
            collect(api, true)
            Q.Sweep(t)
        end
    end
end

--- Stops answering; the slots stay (a frame is never given another slot).
function Q.Deactivate()
    active, Q.covered = false, 0
end

--- Whether some cooldownID's candidates name aura j (alone or ambiguously): the router's tracked set.
function Q.Mappable(j)
    return active and mappable[j] == true
end

--- The in-combat collect: a viewer whose GetNumChildren grew gives its new indices a slot each. Allocates only a new
--- child's slotOf entry.
function Q.Collect()
    if active then
        collect(api0, false)
    end
end

--- I.UP, I.DOWN or I.UNDECIDED for aura `j` on unit `u` (1 player, 2 target): the reduced counts at the last
--- sweep. Allocates nothing.
function Q.Presence(j, u)
    local v = active and last[(u - 1) * I.AURA_UNIT + j]
    if v == I.UP or v == I.DOWN then
        return v
    end
    return I.UNDECIDED
end

-- A target change (§3.4): the slots last answering for the target, and every NONE slot, settle until t + SETTLE (stale);
-- the target slots' seen rule starts over (mob A's light says nothing of mob B). Idempotent (it fires twice a swap).
-- Allocates nothing.
S.On("PLAYER_TARGET_CHANGED", nil, function(_, t)
    if not active then
        return
    end
    for s = 1, Q.nSlots do
        if sUnit[s] == 2 or sAns[s] == NONE then
            sSettle[s] = t + SETTLE
        end
        if sUnit[s] == 2 then
            reset(s)
        end
    end
end)

-- Combat end: every child, so a pool grown in combat is complete (decision 101).
S.On("PLAYER_REGEN_ENABLED", nil, function()
    if active then
        collect(api0, true)
    end
end)

I.PRESENCE.viewer = Q
