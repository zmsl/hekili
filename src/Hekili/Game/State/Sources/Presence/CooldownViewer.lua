-- Game/State/Sources/Presence/CooldownViewer.lua
-- The Cooldown Manager leaf (cdm-default spec §3; providers spec §2.4 as amended). The map (§3.1): every cooldownID
-- of categories 0-8, unlearned included, to one pack aura j, or ambiguous (-a, amb[a] its tracked js), built out of
-- combat. The collect (§3.2): every child of the four viewers kept once as a slot, item or not, in arrays preallocated
-- to MAX_SLOTS; past that a child is ignored and counted (overflow). A new frame is a new slot; a slot is never reused.
-- Read, never write: rawget on items, on Blizzard frames only GetChildren and GetNumChildren (§3.5). The map and the
-- collect install no hook (§3.3); the providers-spec hook block at the end stays until Task 3b's sweep replaces it.
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

local cdvToJ = {} -- cooldownID -> j, or -a (ambiguous: amb[a] lists its tracked js); built out of combat
local amb = {} -- a -> { j, ... }
local mappable = {} -- j -> true when some cooldownID's candidates name it (alone or ambiguously)
local slotOf = setmetatable({}, { __mode = "k" }) -- child frame -> slot: the only in-combat insert (a new child)
local known = { 0, 0, 0, 0 } -- children collected per viewer (GetNumChildren at the last collect)

-- The slots, preallocated: the frame, its viewer, the aura it maps to (sJ, or sAmb the ambiguous a), what it is
-- counted as (sAns, sUnit) since sT, the seen rule's last held time and last plain cooldownID (sSeen, sCd: Task 3c).
local sFrame, sV, sJ, sAmb, sAns, sUnit, sT, sSeen, sCd = {}, {}, {}, {}, {}, {}, {}, {}, {}
for s = 1, MAX_SLOTS do
    sFrame[s], sV[s], sJ[s], sAmb[s], sAns[s], sUnit[s], sT[s], sSeen[s], sCd[s] = false, 0, 0, 0, 0, 0, 0, 0, 0
end

local Q = {
    name = "viewer", -- l10n: verbatim
    scope = "self",
    covered = 0,
    onEdge = nil,
    MAX_SLOTS = MAX_SLOTS,
    nSlots = 0,
    overflow = 0, -- children past MAX_SLOTS, ignored
    map = cdvToJ, -- read-only views for the tests and the snapshot
    amb = amb,
    slotOf = slotOf,
}
local active, api0 = false, nil

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
    if type(links) == "table" and links[1] ~= nil then
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

-- Until Task 3b's sweep reads every slot: the providers-spec hooks on the aura viewers' items (OnShow/OnHide), so the
-- router's Presence keeps its in-combat edges. Task 3b deletes this block, the hooks and Q.Presence's table.
local UNIT = { player = 1, target = 2 }
local unitOf = {} -- cooldownID -> its last known unit (0: none yet); a down item reads no unit (CDV_FRAME 5609)
local st = {} -- (u - 1) * AURA_UNIT + j -> 0 undecided, 1 up, 2 down
local hooked = setmetatable({}, { __mode = "k" })

-- The hook (one function for every item): presence at fire time, a change only. Allocates nothing.
local function hook(self)
    if not active then
        return
    end
    local api = api0
    local id = Plain(api, rawget(self, "cooldownID"))
    local j = id and cdvToJ[id]
    if not j or j < 0 then
        return -- an unmapped or ambiguous item
    end
    local aid = rawget(self, "auraInstanceID")
    local up = api.issecretvalue(aid) or aid ~= nil -- secret: only tested, never compared
    local u = UNIT[Plain(api, rawget(self, "auraDataUnit")) or ""] or unitOf[id]
    if not u or u == 0 then
        return -- no unit ever seen: nothing to move (every pair is down from the build)
    end
    local v = I.DOWN
    if up then
        v = I.UP
        unitOf[id] = u
    end
    local k = (u - 1) * I.AURA_UNIT + j
    if st[k] ~= v then
        st[k] = v
        if Q.onEdge then
            Q.onEdge(j, u, up, api.GetTime())
        end
    end
end

-- Hooks the aura viewers' configured items (out of combat) and marks what they cover.
local function hookAll(api)
    for _, j in pairs(cdvToJ) do
        if j > 0 then
            st[j], st[I.AURA_UNIT + j] = 0, 0 -- preallocated: the hook inserts nothing
        end
    end
    for id, j in pairs(cdvToJ) do
        if j > 0 then
            unitOf[id] = 0
        end
    end
    local seen = {}
    for s = 1, Q.nSlots do
        local item = sFrame[s]
        if sV[s] >= 3 and rawget(item, "layoutIndex") ~= nil then -- BuffIcon and BuffBar only
            if not hooked[item] then
                item:HookScript("OnShow", hook)
                item:HookScript("OnHide", hook)
                hooked[item] = true
            end
            local id = Plain(api, rawget(item, "cooldownID"))
            local j = id and cdvToJ[id]
            if j and j > 0 then
                local u = UNIT[Plain(api, rawget(item, "auraDataUnit")) or ""]
                if u then
                    unitOf[id] = u
                end
                if not seen[j] then -- covered: down on both units until a read says up
                    seen[j] = true
                    st[j], st[I.AURA_UNIT + j] = I.DOWN, I.DOWN
                    Q.covered = Q.covered + 1
                end
            end
        end
    end
end

--- Builds the map and collects every viewer's children (out of combat), then reads the hooked items' presence now.
function Q.Activate(api, t, def)
    api0, active = api, api ~= nil
    Q.covered = 0
    for k in pairs(unitOf) do
        unitOf[k] = nil
    end
    for k in pairs(st) do
        st[k] = 0
    end
    if api then
        if build(api, def) then
            collect(api, true)
            hookAll(api)
            for s = 1, Q.nSlots do
                if hooked[sFrame[s]] then
                    hook(sFrame[s]) -- the state now
                end
            end
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

--- I.UP, I.DOWN or I.UNDECIDED for aura `j` on unit `u` (1 player, 2 target). Allocates nothing.
function Q.Presence(j, u)
    local v = active and st[(u - 1) * I.AURA_UNIT + j] or 0
    if v == I.UP or v == I.DOWN then
        return v
    end
    return I.UNDECIDED
end

-- Combat end: every child, so a pool grown in combat is complete (decision 101).
S.On("PLAYER_REGEN_ENABLED", nil, function()
    if active then
        collect(api0, true)
    end
end)

-- The target's items may change without a show edge ("hide when inactive" off, CV §7): re-read them.
S.On("PLAYER_TARGET_CHANGED", nil, function()
    if active then
        for s = 1, Q.nSlots do
            if hooked[sFrame[s]] then
                hook(sFrame[s])
            end
        end
    end
end)

I.PRESENCE.viewer = Q
