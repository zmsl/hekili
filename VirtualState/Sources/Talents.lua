-- VirtualState/Sources/Talents.lua
-- Talent sources (spec §6.6): one C_Traits tree walk (plain and identical in combat [W PR5]; every call pcall'd and
-- every answer through Plain) at build, on TRAIT_CONFIG_UPDATED, PLAYER_TALENT_UPDATE and SPELLS_CHANGED; an event in
-- combat defers the walk to poll 6 once combat ends. Each node's rank goes to the tracked talent its entry's
-- definition spell names (directly, or through a pack alias); ranks are written at once (Families/Talents.lua) and
-- each changed rank is logged as `Talent`.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Talents.lua (the walk: eachNode, walkNode, entryTalent).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Direct, Note = S.Plain, S.Direct, S.Note

-- The walk's scratch ranks by talent index.
local walkRank = {}
-- How many entries the last walk matched through a pack alias (a rank spell) rather than the registered spell.
local aliasHits = 0
local pending = false

-- The client calls, where they are read (the secrets check sees them); `call` pcalls them and Plains the answer.
local function activeConfig(api)
    return api.C_ClassTalents.GetActiveConfigID() -- secret: through Plain by `call`
end
local function configInfo(api, cfg)
    return api.C_Traits.GetConfigInfo(cfg) -- secret: through Plain by `call`
end
local function treeNodes(api, tree)
    return api.C_Traits.GetTreeNodes(tree) -- secret: through Plain by `call`
end
local function nodeInfo(api, cfg, node)
    return api.C_Traits.GetNodeInfo(cfg, node) -- secret: through Plain by `call`
end
local function entryInfo(api, cfg, entry)
    return api.C_Traits.GetEntryInfo(cfg, entry) -- secret: through Plain by `call`
end
local function definitionInfo(api, def)
    return api.C_Traits.GetDefinitionInfo(def) -- secret: through Plain by `call`
end

local function call(api, fn, a, b)
    local ok, v = pcall(fn, api, a, b)
    if not ok then
        return nil
    end
    return Plain(api, v)
end

-- One node: its rank (activeRank, else currentRank) to the tracked talent of its active (or only) entry.
local function walkNode(api, cfg, nodeID)
    local T = I.talents
    local info = call(api, nodeInfo, cfg, nodeID)
    if type(info) ~= "table" then
        return
    end
    local entries = Plain(api, info.entryIDs)
    if type(entries) ~= "table" or #entries == 0 then
        return
    end
    local rank = Plain(api, info.activeRank)
    if type(rank) ~= "number" then
        rank = Plain(api, info.currentRank)
    end
    if type(rank) ~= "number" or rank ~= rank or rank < 0 then
        rank = 0
    end
    local active = Plain(api, info.activeEntry)
    local activeId = type(active) == "table" and Plain(api, active.entryID) or nil
    for n = 1, #entries do
        local entry = Plain(api, entries[n])
        if type(entry) == "number" then
            local e = call(api, entryInfo, cfg, entry)
            local def = type(e) == "table" and Plain(api, e.definitionID) or nil
            local d = type(def) == "number" and call(api, definitionInfo, def) or nil
            local spell = type(d) == "table" and Plain(api, d.spellID) or nil
            local k = type(spell) == "number" and T.bySpell[spell]
            if k and T.alias[spell] then
                aliasHits = aliasHits + 1
            end
            local r = (#entries == 1 or entry == activeId) and rank or 0
            -- only entries holding points: spent points bound them, so the cap is not filled by untaken nodes
            if not k and type(spell) == "number" and r > 0 then
                T.nUnmatched = T.nUnmatched + 1
                if T.nUnmatched <= I.TALENT_UNMATCHED then
                    T.unmatched[T.nUnmatched] = spell
                end
            end
            if k then
                if r > T.max[k] then
                    r = T.max[k]
                end
                if r > walkRank[k] then
                    walkRank[k] = r
                end
            end
        end
    end
end

-- The walk: the active config's trees, node by node; then each changed rank written and logged. Out of combat only.
local function walk(api, t)
    local T = I.talents
    T.nUnmatched = 0
    if T.n == 0 then
        return
    end
    for k = 1, T.n do
        walkRank[k] = 0
    end
    aliasHits = 0
    local cfg = call(api, activeConfig)
    local info = type(cfg) == "number" and call(api, configInfo, cfg) or nil
    local trees = type(info) == "table" and Plain(api, info.treeIDs) or nil
    if type(trees) ~= "table" then
        Note("talent walk", "nil")
        return
    end
    Note("talent walk", "readable")
    for n = 1, #trees do
        local tree = Plain(api, trees[n])
        local nodes = type(tree) == "number" and call(api, treeNodes, tree) or nil
        if type(nodes) == "table" then
            for m = 1, #nodes do
                local id = Plain(api, nodes[m])
                if type(id) == "number" then
                    walkNode(api, cfg, id)
                end
            end
        end
    end
    -- whether the pack's aliases (VirtualState.Track{ talents }) were needed: "used" or "unused" (CHECKPOINT 2)
    Note("talent walk aliases", aliasHits > 0 and "used" or "unused")
    for k = 1, T.n do
        if I.SetTalentRank(k, walkRank[k]) then
            Direct(Obs.Talent, t, k, walkRank[k])
        end
    end
end

local function request(api, t)
    if not I.built then
        return
    end
    if I.inCombat then
        pending = true
    else
        walk(api, t)
    end
end

I.OnBuild(function(def, now)
    for k = 1, #def.talents do
        walkRank[k] = 0
    end
    if I.api then
        walk(I.api, now)
    end
end)

S.OnStart(request)
S.On("TRAIT_CONFIG_UPDATED", nil, request)
S.On("PLAYER_TALENT_UPDATE", nil, request)
S.On("SPELLS_CHANGED", nil, request)

-- Poll 6: a walk deferred by combat runs once combat ends.
S.Poll(6, function(api, t)
    if pending and not I.inCombat then
        pending = false
        walk(api, t)
    end
end)
