-- Game/State/Sources/Presence/Router.lua
-- The Presence router (providers spec §2.5, decisions 88-90): only a map and delegation. At activation, out of combat,
-- it reads the Cooldown Manager's category sets itself and marks each tracked aura; a tracked aura is answered by the
-- viewer leaf (a fact), an untracked one I.UNDECIDED (the belief's modelled timer). The experimental switch
-- (cfg.viewer) decides whether it has the leaf: without it every answer is I.UNDECIDED. The tracked set and the leaf's
-- build change only out of combat (the leaf does not check combat itself). Knows the leaf only through the contract
-- (I.PRESENCE.viewer).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local R = { name = "router", scope = nil, covered = 0, onEdge = nil, tracked = {} }
local tracked = R.tracked
local leaf, want, api0, def0, pending = nil, nil, nil, nil, false
local edges = { up = 0, down = 0 } -- the edges passed on this fight (Snapshot)
I.presenceEdges = edges

-- A "self" provider's DOWN on the target says only that our debuff is gone; another caster's may be up (the target
-- walk reads anyone's), so it is no answer.
local function selfDownOnTarget(u, up)
    return u == 2 and not up and R.scope == "self"
end

-- The leaf's onEdge: a tracked aura's edge only, counted. Allocates nothing. An item released to its pool keeps its
-- hook harmlessly: the pool hides it before ResetCooldownData clears its aura fields (CooldownViewer.lua:1646-1650,
-- CooldownViewerItemData.lua:383-391), so the hide reads its true presence and the reacquired item's show re-reads.
local function forward(j, u, up, t)
    if tracked[j] and not selfDownOnTarget(u, up) then
        if up then
            edges.up = edges.up + 1
        else
            edges.down = edges.down + 1
        end
        if R.onEdge then
            R.onEdge(j, u, up, t)
        end
    end
end

-- Marks tracked[j] from the client's sets (allocates: the getters' tables). Out of combat only.
local function mark(api, def)
    local CV = api and api.C_CooldownViewer
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
                    if j then
                        tracked[j] = true
                    end
                end
            end
        end
    end
end

-- Out of combat: takes the wanted leaf, clears the map (preallocated to the def's auras), marks it and activates the
-- leaf. In combat it changes nothing and waits for PLAYER_REGEN_ENABLED (decision 89: no path change mid-fight).
local function activate(t)
    if I.inCombat then
        pending = true
        return
    end
    leaf = want
    for j = 1, #tracked do
        tracked[j] = false
    end
    for j = 1, def0 and #def0.auraIds or 0 do
        tracked[j] = false
    end
    R.covered, R.scope, pending = 0, nil, false
    if not leaf then
        return
    end
    mark(api0, def0)
    leaf.onEdge = forward
    leaf.Activate(api0, t, def0, nil)
    R.covered, R.scope = leaf.covered, leaf.scope
end

-- The viewer's events reach the client only while the router has the leaf: switch off is the Default to the digit
-- (decision 88), so it registers nothing new.
local VIEWER_EVENTS = { "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED" }
local function listen(on)
    for n = 1, #VIEWER_EVENTS do
        S.Dormant(VIEWER_EVENTS[n], not on)
        I.Events.Sync(VIEWER_EVENTS[n])
    end
end

--- Takes the leaf when cfg.viewer; builds the map and activates the leaf out of combat (else at combat end).
function R.Activate(api, t, def, cfg)
    listen(cfg and cfg.viewer)
    api0, def0, want = api, def, nil
    if cfg and cfg.viewer then
        want = I.PRESENCE.viewer
    end
    activate(t)
end

--- Answers I.UNDECIDED from now on.
function R.Deactivate(t)
    listen(false)
    if leaf then
        leaf.Deactivate(t)
    end
    leaf, want, pending, R.covered, R.scope = nil, nil, false, 0, nil
end

--- The leaf's answer for a tracked aura, else I.UNDECIDED. Allocates nothing.
function R.Presence(j, u)
    if leaf and tracked[j] then
        local a = leaf.Presence(j, u)
        if not selfDownOnTarget(u, a ~= I.DOWN) then
            return a
        end
    end
    return I.UNDECIDED
end

-- The viewer's sets changed (CV §3): rebuild out of combat, else at combat end (decision 89: no change mid-fight).
local function changed(_, t)
    if want and I.presence == R then
        activate(t)
    end
end
for n = 1, #VIEWER_EVENTS do
    S.On(VIEWER_EVENTS[n], nil, changed)
    S.Dormant(VIEWER_EVENTS[n], true)
end
-- Player.lua's handler runs first (TOC order) and clears I.inCombat.
S.On("PLAYER_REGEN_ENABLED", nil, function(_, t)
    if pending and I.presence == R then
        activate(t)
    end
end)
S.On("PLAYER_REGEN_DISABLED", nil, function()
    edges.up, edges.down = 0, 0
end)

I.PRESENCE.router = R
