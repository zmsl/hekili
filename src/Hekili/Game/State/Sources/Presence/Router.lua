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
local leaf, api0, def0, pending = nil, nil, nil, false
local edges = { up = 0, down = 0 } -- the edges passed on this fight (Snapshot)
I.presenceEdges = edges

-- The leaf's onEdge: a tracked aura's edge only, counted. Allocates nothing.
local function forward(j, u, up, t)
    if tracked[j] then
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

-- Clears the map (preallocated to the def's auras), then, out of combat, marks it and activates the leaf; in combat
-- it waits for PLAYER_REGEN_ENABLED.
local function activate(t)
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
    if I.inCombat then
        pending = true
        return
    end
    mark(api0, def0)
    leaf.onEdge = forward
    leaf.Activate(api0, t, def0, nil)
    R.covered, R.scope = leaf.covered, leaf.scope
end

--- Takes the leaf when cfg.viewer; builds the map and activates the leaf out of combat (else at combat end).
function R.Activate(api, t, def, cfg)
    api0, def0 = api, def
    leaf = nil
    if cfg and cfg.viewer then
        leaf = I.PRESENCE.viewer
    end
    activate(t)
end

--- Answers I.UNDECIDED from now on.
function R.Deactivate(t)
    if leaf then
        leaf.Deactivate(t)
    end
    leaf, pending, R.covered, R.scope = nil, false, 0, nil
end

--- The leaf's answer for a tracked aura, else I.UNDECIDED. Allocates nothing.
function R.Presence(j, u)
    if leaf and tracked[j] then
        return leaf.Presence(j, u)
    end
    return I.UNDECIDED
end

-- The viewer's sets changed (CV §3): rebuild out of combat, else at combat end (decision 89: no change mid-fight).
local function changed(_, t)
    if not leaf or I.presence ~= R then
        return
    end
    if I.inCombat then
        pending = true
    else
        activate(t)
    end
end
S.On("COOLDOWN_VIEWER_DATA_LOADED", nil, changed)
S.On("COOLDOWN_VIEWER_TABLE_HOTFIXED", nil, changed)
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
