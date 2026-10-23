-- Game/State/Sources/Presence/CooldownViewer.lua
-- The Cooldown Manager AuraPresence leaf (providers spec §2.4): the viewer's item frames carry a plain presence bit in
-- combat (auraInstanceID secret while up, nil while down); HookScript OnShow/OnHide read it 3-5 ms after the edge.
-- Scope "self": the viewer tracks player-cast auras only (probe CDM-S); presence only, never stacks or durations.
-- Read, never call: rawget on items, GetChildren out of combat, HookScript once per item; nothing written to the
-- viewer. Measured: docs/research/2026-10-23-cooldown-manager-api.md (CV §2, §5, §6). Shares no code with any other
-- provider.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

-- Only the aura viewers: Essential and Utility items are always shown (CV §2), so their auras get no edges and answer
-- I.UNDECIDED (the router falls through to the default source).
local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local UNIT = { player = 1, target = 2 }

local Q = { name = "viewer", scope = "self", covered = 0, onEdge = nil }
local active, api0 = false, nil
local cdvToJ = {} -- cooldownID -> aura index (built out of combat)
local unitOf = {} -- cooldownID -> its last known unit (0: none yet); a down item reads no unit (CDV_FRAME 5609)
local st = {} -- (u - 1) * AURA_UNIT + j -> 0 undecided, 1 up, 2 down
local items = {} -- the hooked item frames, for the target re-read (built out of combat)
local hooked = setmetatable({}, { __mode = "k" })

-- The hook (one function for every item): presence at fire time, a change only. Allocates nothing.
local function hook(self)
    if not active then
        return
    end
    local api = api0
    local id = Plain(api, rawget(self, "cooldownID"))
    local j = id and cdvToJ[id]
    if not j then
        return -- an unmapped aura
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

-- The map and the hooks, out of combat (allocates: the getters' tables, GetChildren's list).
local function build(api, def)
    for k in pairs(cdvToJ) do
        cdvToJ[k], unitOf[k] = nil, nil
    end
    for k in pairs(st) do
        st[k] = 0
    end
    for n = 1, #items do
        items[n] = nil
    end
    Q.covered = 0
    local CV = api.C_CooldownViewer
    if not CV or not def then
        return
    end
    local ok, avail = pcall(CV.IsCooldownViewerAvailable) -- secret: Plain next
    if not ok or Plain(api, avail) ~= true then
        return
    end
    local byId = {}
    for j = 1, #def.auraIds do
        for _, sid in ipairs(def.auraIds[j]) do
            byId[sid] = j
        end
    end
    for c = 0, 8 do
        local okS, set = pcall(CV.GetCooldownViewerCategorySet, c) -- secret: Plain next
        set = Plain(api, set)
        if okS and type(set) == "table" then
            for _, id in ipairs(set) do
                local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, id) -- secret: Plain next
                info = Plain(api, info)
                if okI and type(info) == "table" then
                    local j = byId[Plain(api, info.spellID) or 0] or byId[Plain(api, info.overrideSpellID) or 0]
                    local links = Plain(api, info.linkedSpellIDs)
                    if type(links) == "table" then
                        for _, l in ipairs(links) do
                            j = j or byId[Plain(api, l) or 0]
                        end
                    end
                    if j and not cdvToJ[id] then
                        cdvToJ[id], unitOf[id] = j, 0
                        st[j], st[I.AURA_UNIT + j] = 0, 0 -- preallocated: the hook inserts nothing
                    end
                end
            end
        end
    end
    local seen = {}
    for _, name in ipairs(VIEWERS) do
        local v = api[name]
        if v and v.GetChildren then
            for _, item in ipairs({ v:GetChildren() }) do
                if rawget(item, "layoutIndex") ~= nil then
                    if not hooked[item] then
                        item:HookScript("OnShow", hook)
                        item:HookScript("OnHide", hook)
                        hooked[item] = true
                    end
                    items[#items + 1] = item
                    local id = Plain(api, rawget(item, "cooldownID"))
                    local j = id and cdvToJ[id]
                    local u = UNIT[Plain(api, rawget(item, "auraDataUnit")) or ""]
                    if j and u then
                        unitOf[id] = u
                    end
                    if j and not seen[j] then -- covered: down on both units until a read says up
                        seen[j] = true
                        st[j], st[I.AURA_UNIT + j] = I.DOWN, I.DOWN
                        Q.covered = Q.covered + 1
                    end
                end
            end
        end
    end
end

--- Builds the map and hooks the items (out of combat), then reads every item's presence now.
function Q.Activate(api, t, def)
    api0, active = api, api ~= nil
    if api then
        build(api, def)
        for n = 1, #items do
            hook(items[n]) -- the state now
        end
    end
end

--- Stops answering; the hooks stay installed and return at once.
function Q.Deactivate()
    active, Q.covered = false, 0
end

--- I.UP, I.DOWN or I.UNDECIDED for aura `j` on unit `u` (1 player, 2 target). Allocates nothing.
function Q.Presence(j, u)
    local v = active and st[(u - 1) * I.AURA_UNIT + j] or 0
    if v == I.UP or v == I.DOWN then
        return v
    end
    return I.UNDECIDED
end

-- The target's items may change without a show edge ("hide when inactive" off, CV §7): re-read them.
S.On("PLAYER_TARGET_CHANGED", nil, function()
    if active then
        for n = 1, #items do
            hook(items[n])
        end
    end
end)

I.PRESENCE.viewer = Q
