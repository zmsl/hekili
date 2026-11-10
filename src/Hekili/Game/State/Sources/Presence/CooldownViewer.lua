-- Game/State/Sources/Presence/CooldownViewer.lua
-- The Cooldown Manager leaf (cdm-default spec §3; providers spec §2.4 as amended). The map (§3.1): every cooldownID
-- of categories 0-8, unlearned included, to one pack aura j, or ambiguous (-a, amb[a] its tracked js), built out of
-- combat. The collect (§3.2): every child of the four viewers kept once as a slot, item or not, in arrays preallocated
-- to MAX_SLOTS; past that a child is ignored and counted (overflow). A new frame is a new slot; a slot is never reused.
-- The sweep (§3.2): at poll 15, per viewer IsVisible and GetNumChildren once, per slot four rawgets; a reading change
-- moves its thing's counters (aura j, unit u: nUp, nNone, nStale) in O(1); the moved things' tUp/tNone are recomputed
-- over the live slots (O(slots)); each moved thing goes to Q.onThing (the router reduces it, §2.4). The seen rule
-- (§2.2a, decision 115): a silent slot answers NONE only for an application it was seen holding (its record up, sSeen >= applied, its last held
-- unit). A target change makes target and NONE slots settle for its frame: target answers stale (§3.4). A raise
-- in the sweep, or in the router's reduction it calls, turns the leaf off for the session (§3.5). Read, never write: rawget on items, on Blizzard frames only
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
local STOPPED = "Forever: Cooldown Manager reading stopped for this session after an error: %s"

local cdvToJ = {} -- cooldownID -> j, or -a (ambiguous: amb[a] lists its tracked js); built out of combat
local amb = {} -- a -> { j, ... }
local mappable = {} -- j -> true when some cooldownID's candidates name it (alone or ambiguously)
local slotOf = setmetatable({}, { __mode = "k" }) -- child frame -> slot: the only in-combat insert (a new child)
local known = { 0, 0, 0, 0 } -- children collected per viewer (GetNumChildren at the last collect)

-- The slots, preallocated: the frame, its viewer, the aura it is counted for (sJ; sAmb 1 while an ambiguous item is
-- held: its lights are counted, never evidence), what it is counted as
-- (sAns, sUnit: sUnit is also the last plain held unit, kept through silence) since sT, the seen rule's last held time
-- and last plain cooldownID (sSeen, sCd, §2.2a), the last target change's t (sSettle, §3.4). sAns 0 not counted, else
-- UP, NONE or STALE (a hidden viewer's or a settling slot: what it would answer, not live).
-- The edge (owner rulings L348-L351; the conservative rule, L351: no positive dark for a never-lit slot, F12): sLit 1
-- while the slot's last monitored sweep (viewer visible, not settling) saw it held for sUnit; sDark the t of the first
-- monitored dark sweep after that, kept while it stays dark and monitored. A light for the same unit with sDark > 0 is
-- an EDGE; every reset, a hidden or settling sweep, a held sweep for no unit and a rebuild zero both, so a first light
-- after any of them is a SEED.
local sFrame, sV, sJ, sAmb, sAns, sUnit, sT, sSeen, sCd, sSettle = {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
local sLit, sDark = {}, {}
-- The verdict's dark (cdm-verdict §2.2, decision 118 as amended): sDk the k a proven item's slot is counted dark for
-- (0 none), sDarkT the t of its first monitored dark sweep (0 none): the two move together (darkTo), so every point
-- where the monitoring restarts restarts the start. Never live: nLive, covered and the reducer do not see it.
local sDarkT, sDk = {}, {}
for s = 1, MAX_SLOTS do
    sFrame[s], sV[s], sJ[s], sAmb[s], sAns[s], sUnit[s], sT[s] = false, 0, 0, 0, 0, 0, 0
    sSeen[s], sCd[s], sSettle[s], sLit[s], sDark[s], sDarkT[s], sDk[s] = 0, 0, -1, 0, 0, 0, 0
end

local NOT, UP, NONE, STALE = 0, 1, 2, 3
-- shortcut: STRIKES_MAX 2 is the spec's guess (§6); Task 10 tunes it.
local STRIKES_MAX = 2
local UNIT = { player = 1, target = 2 }

-- The things' counters, by k = (u - 1) * AURA_UNIT + j, zeroed for both units at activation (preallocated: the
-- target's keys are in the hash part); live slots per aura (covered).
local cUp, cNone, cStale, tUp, tNone, live = {}, {}, {}, {}, {}, {}
-- By the same k: the t of the last sweep where one of the thing's slots had an edge (eT) and where one went dark after a
-- monitored light (dT); 0 none. Read by the router (fact.edge, fact.dark).
local eT, dT = {}, {}
-- By k (cdm-verdict §2.2), preallocated beside cUp: cDark the slots counted dark for the thing, tDark the LATEST start
-- (sDarkT) among them, 0 none: the thing has been watched dark continuously since then (Fable 5.2 review M2).
local cDark, tDark = {}, {}
-- Per cooldownID (cdm-verdict §2.1, §2.4; decisions 117, 121), preallocated at build() to the map's keys, out of combat:
-- proven (lit once this build), the unit it last lit for (1 player, 2 target), strikes, and silentCd: the verdict
-- closes of things it was dark for since its last visible light (Fable 5.2 review M3: at STRIKES_MAX its proof is
-- suspended until it lights again). The item is the cooldownID, never the frame. The seen rule's memory stays per
-- slot: a re-pointed frame starts with none (review S1).
local provenCd, provenU, strikesCd, silentCd = {}, {}, {}, {}
local ambC = {} -- by k: the per-fight lights of ambiguous items naming aura j on unit u (§2.2; the snapshot's)
local VBIT = { 1, 2, 4, 8 } -- a viewer's bit in Q.Via (§2.4)
local touched, mark, nTouched = {}, {}, 0 -- the things a sweep moved, each once
local vis = { false, false, false, false } -- each viewer's IsVisible at this sweep

local Q = {
    name = "viewer", -- l10n: verbatim
    scope = "self",
    covered = 0,
    onThing = nil, -- (k, t): a thing this sweep moved, its counts final (the router reduces it, §2.4)
    MAX_SLOTS = MAX_SLOTS,
    nSlots = 0,
    overflow = 0, -- children past MAX_SLOTS, ignored
    errors = 0, -- sweeps that raised (the first turns the leaf off for the session)
    ambiguous = 0, -- ambiguous items' lights this fight (§2.2)
    map = cdvToJ, -- read-only views for the tests and the snapshot
    amb = amb,
    slotOf = slotOf,
    seen = sSeen,
    edgeT = eT, -- by k: the last sweep's t with an edge of the thing (the router's fact.edge)
    darkT = dT, -- by k: the last sweep's t one of its slots went dark after a monitored light
    proven = provenCd, -- by cooldownID (cdm-verdict §2.1): read-only views for the tests and the snapshot
    provenU = provenU,
    strikes = strikesCd,
    silent = silentCd,
    repoints = 0, -- per fight: plain cooldownID changes of a slot that held another one (§2.4)
    struck = 0, -- per build: cooldownIDs whose proof the strikes dropped (§2.5)
    suspended = 0, -- per build: the times silent verdicts suspended a cooldownID's proof (§2.5, review M3)
    builds = 0, -- per session, never reset: the map's builds; each one zeroes every proof (review S2)
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
    Q.builds = Q.builds + 1
    for k in pairs(cdvToJ) do
        cdvToJ[k] = nil
    end
    for k in pairs(amb) do
        amb[k] = nil
    end
    for k in pairs(mappable) do
        mappable[k] = nil
    end
    for id in pairs(provenCd) do -- zeroed at every build: a new rank's map starts unproven (decision 124)
        provenCd[id], provenU[id], strikesCd[id], silentCd[id] = nil, nil, nil, nil
    end
    Q.struck, Q.suspended = 0, 0
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
        -- (cdm-panel) a switched-off aura (def.auras[j].cdm == false, Tracked.lua) is no candidate: its items stay
        -- unmapped, the aura pure belief
        if not (def.auras[j] and def.auras[j].cdm == false) then
            for _, sid in ipairs(def.auraIds[j]) do
                byId[sid] = j
            end
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
                    if cdvToJ[id] then -- every mapped key preallocated: the sweep writes existing keys only
                        provenCd[id], provenU[id], strikesCd[id], silentCd[id] = false, 0, 0, 0
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

-- Moves slot s's dark count to thing k (0: none) at t, its start, marking both things for the router (cdm-verdict
-- §2.2): the sweep's reduction recomputes their tDark. Allocates nothing.
local function darkTo(s, k, t)
    local o = sDk[s]
    if o == k then
        return
    end
    sDk[s], sDarkT[s] = k, k > 0 and t or 0
    for i = 1, 2 do
        local x = i == 1 and o or k
        if x > 0 then
            cDark[x] = cDark[x] + (i == 1 and -1 or 1)
            if not mark[x] then
                mark[x], nTouched = true, nTouched + 1
                touched[nTouched] = x
            end
        end
    end
end

-- The seen rule starts over for slot s (§2.2a): un-counted first, so no count is left with no live slot behind it. Its
-- dark restarts too (cdm-verdict §2.4c).
local function reset(s)
    uncount(s)
    darkTo(s, 0)
    sSeen[s], sUnit[s], sLit[s], sDark[s] = 0, 0, 0, 0
end

-- The things a sweep moved: tUp/tNone recomputed as the latest begin (sT) of a live slot (§2.3: a slot that left takes
-- its time with it), tDark as the latest start of a dark slot, O(slots); then each goes to Q.onThing. Allocates nothing.
local function reduce(t)
    if nTouched == 0 then
        return
    end
    for i = 1, nTouched do
        local k = touched[i]
        tUp[k], tNone[k], tDark[k] = 0, 0, 0
    end
    for s = 1, Q.nSlots do
        local dk = sDk[s]
        if dk > 0 and mark[dk] and sDarkT[s] > tDark[dk] then
            tDark[dk] = sDarkT[s]
        end
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
    local on = Q.onThing
    for i = 1, nTouched do
        local k = touched[i]
        mark[k] = false
        if on then
            on(k, t)
        end
    end
    nTouched = 0
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
        local seenAs = 0 -- the edge's reading (sLit, sDark): 1 held for a unit we track, 2 silent, 0 neither
        local wasAmb = sAmb[s]
        sAmb[s] = 0
        local id = Plain(api, rawget(item, "cooldownID"))
        if (id or 0) ~= sCd[s] then -- (re)assigned, released or secret: a new mapping (same-aura re-points too)
            if id ~= nil and sCd[s] ~= 0 then
                Q.repoints = Q.repoints + 1
            end
            reset(s) -- with its seen memory: what the item was seen holding on another frame says nothing here (S1)
            sCd[s] = id or 0
        end
        local m = id ~= nil and Plain(api, rawget(item, "layoutIndex")) ~= nil and cdvToJ[id]
        if m and m > 0 then -- configured and mapped to one aura (an ambiguous item counts for none)
            local aid = rawget(item, "auraInstanceID")
            if issecret(aid) or aid ~= nil then -- secret: only tested, never compared
                local unit = Plain(api, rawget(item, "auraDataUnit"))
                u = unit ~= nil and UNIT[unit] or 0 -- a secret, nil or other unit: not live for either
                if u > 0 then
                    if u ~= sUnit[s] then -- sSeen pairs with sUnit: a stale light for another unit must not inherit it
                        sSeen[s] = 0
                    end
                    j, a, seenAs = m, UP, 1
                    -- proof (cdm-verdict §2.1): a visible light for the item's one aura; none after STRIKES_MAX
                    -- strikes. Any such light ends a suspension: the silent verdicts are counted since it (M3)
                    if vis[sV[s]] then
                        provenU[id], silentCd[id] = u, 0
                        if strikesCd[id] < STRIKES_MAX then
                            provenCd[id] = true
                        end
                    end
                else
                    reset(s) -- held for no unit we track: what it was seen holding says nothing now
                end
            else -- silent: NONE only for the application this slot was seen holding (§2.2a)
                j, u, seenAs = m, sUnit[s], 2
                -- (4a review m5) m <= U.nAura: an in-combat rebuild may shrink the set under this map
                if
                    u > 0
                    and u <= U.n
                    and m <= U.nAura
                    and sSeen[s] > 0
                    and U.exp0[u][m] > t
                    and sSeen[s] >= U.applied[u][m]
                then
                    a = NONE
                end
            end
            if a ~= NOT and (not vis[sV[s]] or u == 2 and sSettle[s] >= t) then -- settling: target answers only (§2.2)
                a = STALE
            end
        elseif m and m < 0 and vis[sV[s]] then -- ambiguous: its lights counted (each once), never evidence (§2.2)
            local aid = rawget(item, "auraInstanceID")
            if issecret(aid) or aid ~= nil then -- secret: only tested, never compared
                sAmb[s] = 1
                if wasAmb == 0 then
                    Q.ambiguous = Q.ambiguous + 1
                    local unit = Plain(api, rawget(item, "auraDataUnit"))
                    local au = unit ~= nil and UNIT[unit] or 0
                    local list = amb[-m]
                    for n = 1, au > 0 and #list or 0 do
                        local k = (au - 1) * I.AURA_UNIT + list[n]
                        ambC[k] = ambC[k] + 1
                    end
                end
            end
        end
        if seenAs == 0 or not vis[sV[s]] or u == 2 and sSettle[s] >= t then -- not monitored: the edge starts over
            sLit[s], sDark[s] = 0, 0
        elseif seenAs == 1 then
            if sDark[s] > 0 and u == sUnit[s] then -- lit -> dark -> lit on one unit, each seen: an edge
                eT[(u - 1) * I.AURA_UNIT + j] = t
            end
            sLit[s], sDark[s] = 1, 0
        elseif sLit[s] == 1 and u > 0 then -- silent after a monitored light: the dark baseline
            sLit[s], sDark[s] = 0, t
            dT[(u - 1) * I.AURA_UNIT + j] = t
        end
        -- the dark (cdm-verdict §2.2): a proven item silent on a monitored sweep, counted for the unit it last lit for
        -- from its first such sweep (darkTo keeps that t while it stays so); anything else restarts it
        local dk = 0
        if seenAs == 2 and provenCd[id] and vis[sV[s]] and not (provenU[id] == 2 and sSettle[s] >= t) then
            dk = (provenU[id] - 1) * I.AURA_UNIT + m
        end
        darkTo(s, dk, t)
        if a ~= sAns[s] or j ~= sJ[s] or u ~= sUnit[s] then
            uncount(s)
            count(s, j, u, a, t)
        end
        if a == UP then -- every held sweep, not only a change: our refresh moves applied while the item stays held
            sSeen[s] = t
        end
    end
    reduce(t) -- inside the pcall: a raise in the router's reduction or onEdge is a self-off too (§3.5)
end

--- The sweep at poll 15: reads every slot, moves the counters, then hands each moved thing to Q.onThing, all under one
--- pcall. A raise anywhere in it turns the leaf off for the session (§3.5): it answers nothing from then on, so no
--- frozen answer is applied again; one def.error line; Q.errors counts it (the router drops the leaf on a change).
--- Allocates nothing (a new child's slotOf entry aside; the error path formats once).
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
    end
end

--- nLive, nUp, nNone, nStale, tUp, tNone, nDark, tDark (cdm-verdict §2.2: the proven slots dark on a monitored sweep,
--- never live, and the latest of their first such sweeps) for aura `j` on unit `u`. Allocates nothing.
function Q.Counts(j, u)
    local k = (u - 1) * I.AURA_UNIT + j
    if not active or not cUp[k] then
        return 0, 0, 0, 0, 0, 0, 0, 0
    end
    return cUp[k] + cNone[k], cUp[k], cNone[k], cStale[k], tUp[k], tNone[k], cDark[k], tDark[k]
end

--- A wrong verdict for (j, u) (cdm-verdict §2.5): every slot counted UP for it now has its cooldownID struck; at
--- STRIKES_MAX its proof is dropped for the build. Called from poll 15 after the sweep (the verdict's strike check, a
--- poll after the light): it touches no counter and marks no thing (the next sweep un-counts the dark of an unproven
--- item). Allocates nothing.
function Q.Strike(j, u)
    for s = 1, active and Q.nSlots or 0 do
        local id = sCd[s]
        if sAns[s] == UP and sJ[s] == j and sUnit[s] == u and strikesCd[id] then
            strikesCd[id] = strikesCd[id] + 1
            if strikesCd[id] >= STRIKES_MAX and provenCd[id] then
                provenCd[id], Q.struck = false, Q.struck + 1
            end
        end
    end
end

--- A verdict closed the record of (j, u) (cdm-verdict §2.5, Fable 5.2 review M3): every slot counted dark for it has
--- its cooldownID's silent count raised; at STRIKES_MAX the item's proof is suspended: no verdict from it until any
--- visible light of it (the sweep's proof) re-proves it and zeroes the count. A strike needs a light, so an item
--- silent for some applications (a rank or variant it does not follow) would otherwise close every one of them.
--- Called from the fold, after the sweep, like Q.Strike: it touches no counter and marks no thing. Allocates nothing.
function Q.Silent(j, u)
    local k = (u - 1) * I.AURA_UNIT + j
    for s = 1, active and Q.nSlots or 0 do
        local id = sCd[s]
        if sDk[s] == k and silentCd[id] then
            silentCd[id] = silentCd[id] + 1
            if silentCd[id] >= STRIKES_MAX and provenCd[id] then
                provenCd[id], Q.suspended = false, Q.suspended + 1
            end
        end
    end
end

--- Whether aura j is mapped (alone) by some cooldownID and none of them lit this build (the snapshot's
--- mappedNeverLit; an item struck or suspended did light: provenU). Loops the map: debug only.
function Q.NeverLit(j)
    local mapped = false
    for id, m in pairs(cdvToJ) do
        if m == j then
            if provenCd[id] or provenU[id] ~= 0 then
                return false
            end
            mapped = true
        end
    end
    return mapped
end

--- Builds the map and collects every viewer's children (out of combat), then sweeps once: the state now.
function Q.Activate(api, t, def)
    api0, active = api, api ~= nil and not broken -- off after an error until /reload
    Q.covered, nTouched = 0, 0
    for k in pairs(cUp) do
        cUp[k], cNone[k], cStale[k], tUp[k], tNone[k], mark[k], ambC[k], eT[k], dT[k] = 0, 0, 0, 0, 0, false, 0, 0, 0
        cDark[k], tDark[k] = 0, 0
    end
    Q.ambiguous = 0
    for j in pairs(live) do
        live[j] = 0
    end
    for s = 1, Q.nSlots do -- a new map: every slot counted afresh, its seen rule started over (§2.2a)
        sJ[s], sAmb[s], sAns[s], sUnit[s], sT[s] = 0, 0, NOT, 0, 0
        sSeen[s], sCd[s], sSettle[s], sLit[s], sDark[s], sDarkT[s], sDk[s] = 0, 0, -1, 0, 0, 0, 0
    end
    Q.repoints = 0
    local nAura = def and #def.auraIds or 0
    for j = 1, nAura do
        live[j] = 0
        for u = 1, 2 do
            local k = (u - 1) * I.AURA_UNIT + j
            cUp[k], cNone[k], cStale[k], tUp[k], tNone[k], mark[k], ambC[k], eT[k], dT[k] =
                0, 0, 0, 0, 0, false, 0, 0, 0
            cDark[k], tDark[k] = 0, 0
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

--- Every slot's edge state starts over (the viewer's data reloaded; the router calls it even while its rebuild waits
--- for combat end): the next light of each is a SEED, and its dark restarts. Called from an event, never
--- inside the sweep's reduction (it marks things). Allocates nothing.
function Q.ForgetEdges()
    for s = 1, Q.nSlots do
        sLit[s], sDark[s] = 0, 0
        darkTo(s, 0) -- (review m5) the dark starts over too
    end
end

--- Stops answering; the slots stay (a frame is never given another slot).
function Q.Deactivate()
    active, Q.covered = false, 0
end

--- The viewers with a live slot (UP or NONE) for aura `j` on unit `u`: a bitmask, 1 Essential, 2 Utility, 4 Buff icon,
--- 8 Buff bar (§2.4, the snapshot's fact.via). Loops the slots; allocates nothing.
function Q.Via(j, u)
    local via = 0
    for s = 1, active and Q.nSlots or 0 do
        local a, b = sAns[s], VBIT[sV[s]]
        if (a == UP or a == NONE) and sJ[s] == j and sUnit[s] == u and via % (2 * b) < b then
            via = via + b
        end
    end
    return via
end

--- This fight's lights of ambiguous items naming aura `j` on unit `u` (§2.2). Allocates nothing.
function Q.Ambiguous(j, u)
    return ambC[(u - 1) * I.AURA_UNIT + j] or 0
end

--- Configured slots whose cooldownID maps to no pack aura (the snapshot's summary). Allocates nothing.
function Q.Unmapped()
    local api, n = api0, 0
    for s = 1, active and Q.nSlots or 0 do
        local item = sFrame[s]
        local id = Plain(api, rawget(item, "cooldownID"))
        if id ~= nil and Plain(api, rawget(item, "layoutIndex")) ~= nil and cdvToJ[id] == nil then
            n = n + 1
        end
    end
    return n
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

-- A target change (§3.4): the slots last answering for the target, and every NONE slot, settle for this frame: a sweep
-- at t <= the switch's t is stale (t is GetTime(), one value per frame; CDM-O, owner 2026-11-08: the viewer is stale
-- only in the event's frame, right from the next); the target slots' seen rule starts over (mob A's light says nothing
-- of mob B). Idempotent (it fires twice a swap). The verdict (cdm-verdict §2.4): every item proven for the target
-- settles with its dark restarted. Allocates nothing.
S.On("PLAYER_TARGET_CHANGED", nil, function(_, t)
    if not active then
        return
    end
    for s = 1, Q.nSlots do
        if sUnit[s] == 2 or sAns[s] == NONE or provenU[sCd[s]] == 2 then
            sSettle[s] = t
        end
        if sUnit[s] == 2 then
            reset(s)
        elseif provenU[sCd[s]] == 2 then
            darkTo(s, 0)
        end
    end
end)

-- A fight's start: the ambiguous lights are counted per fight.
S.On("PLAYER_REGEN_DISABLED", nil, function()
    Q.ambiguous, Q.repoints = 0, 0
    for k in pairs(ambC) do
        ambC[k] = 0
    end
end)

-- Combat end: every child, so a pool grown in combat is complete (decision 101).
S.On("PLAYER_REGEN_ENABLED", nil, function()
    if active then
        collect(api0, true)
    end
end)

I.PRESENCE.viewer = Q
