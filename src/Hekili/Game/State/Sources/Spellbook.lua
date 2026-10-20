-- Game/State/Sources/Spellbook.lua
-- Spellbook sources (spec §4.2, §4.5): each tracked ability's query ID (its highest known rank), its range (the range
-- poll's bounds) and plain cost (out of combat: shown by Snapshot(), and a percent-of-base cost teaches its pool's base),
-- and the cooldown flag edges: SPELL_UPDATE_COOLDOWN/SPELL_UPDATE_CHARGES read C_Spell.GetSpellCooldown
-- per tracked spell and log a `Cooldown` per changed plain `isActive` flag (b: 1 ready / 0 not), and the GCD's edge
-- from the GCD spell's flag (a = 0, c = 1). Only the plain flags are used; the times are secret in combat.
-- Credits: the field-by-field secrecy test after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Spellbook.lua (ResolveRanks).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Note = S.Plain, S.Stage, S.Note

--- Forever's GCD spell (cleanup Q6): the one constant core and the facade ask the GCD by (shared-content spec §5).
I.GCD_SPELL = 29515

-- By ability index: the last ready flag reported (-1 none, 0 not ready, 1 ready); the GCD's (-1, 0 idle, 1 active).
local last, gcdLast = {}, -1

-- The highest known rank of each ability (rank order: its `id`, then its `copy` IDs) and, out of combat, its plain
-- cost and whether it costs a second power type. Out of the hot path: build, SPELLS_CHANGED.
local function resolve(api)
    local A = I.ab
    if not I.inCombat then -- each pool's base is learned again from this pass's reads (I.LearnBase)
        for r = 1, #I.baseDefault do
            I.basePow[r] = I.baseDefault[r]
        end
    end
    for a = 1, A.n do
        local ids, q, known = A.ids[a], A.ids[a][1], false
        for k = 1, #ids do
            if Plain(api, api.C_SpellBook.IsSpellKnown(ids[k])) == true then
                q, known = ids[k], true
            end
        end
        A.qid[a] = q
        if A.known then
            A.known[a] = known -- VS.KnownRank (Families/Now.lua)
        end
        -- the range poll's bounds (Sources/Target.lua): static spell data, plain; an on-next-swing strike is never
        -- asked (the client answers it in range at any distance, probe W PR7)
        local info = Plain(api, api.C_Spell.GetSpellInfo(q)) -- secret: Plain next, then each field
        local lo = type(info) == "table" and Plain(api, info.minRange)
        local hi = type(info) == "table" and Plain(api, info.maxRange)
        A.rMin[a] = type(lo) == "number" and lo or 0
        A.rMax[a] = (type(hi) == "number" and not A.obj[a].onNextSwing) and hi or 0
        if not I.inCombat and A.slot[a] > 0 then
            local raw = api.C_Spell.GetSpellPowerCost(q) -- secret: Plain next, then each field
            local costs = Plain(api, raw)
            local first = type(costs) == "table" and Plain(api, costs[1])
            local cost = type(first) == "table" and Plain(api, first.cost)
            A.readCost[a] = type(cost) == "number" and cost or 0
            I.LearnBase(a, A.readCost[a]) -- a percent-of-base cost teaches its pool's base (Families/Casts.lua)
            A.multiCost[a] = type(costs) == "table" and Plain(api, costs[2]) ~= nil -- a second power type (A5)
        end
    end
end

I.OnBuild(function(def)
    for a = 1, #def.abilities do
        last[a] = -1
    end
    gcdLast = -1
    if I.api then
        resolve(I.api)
    end
end)

S.OnStart(function(api)
    if I.built then
        resolve(api)
    end
end)

S.On("SPELLS_CHANGED", nil, function(api)
    if I.built then
        resolve(api)
    end
end)

-- A level-up changes every percent-of-base cost (the pool's base power): read them again.
S.On("PLAYER_LEVEL_UP", nil, function(api)
    if I.built then
        resolve(api)
    end
end)

-- A build or spell change in combat (a /reload mid-fight) skipped the costs; read them at combat end. Player.lua's
-- handler runs first (TOC order) and clears I.inCombat.
S.On("PLAYER_REGEN_ENABLED", nil, function(api)
    if I.built then
        resolve(api)
    end
end)

-- The plain ready flag of one spell: true ready, false on cooldown, nil when unreadable. A spell on the GCD only
-- reads ready. Allocates nothing (the client allocates the info table).
local function ready(api, spellID)
    local raw = api.C_Spell.GetSpellCooldown(spellID) -- secret: Plain next, then each field
    local info = Plain(api, raw)
    if type(info) ~= "table" then
        Note("GetSpellCooldown flags", "nil")
        return nil
    end
    local active, onGcd = Plain(api, info.isActive), Plain(api, info.isOnGCD)
    if active == nil then
        Note("GetSpellCooldown flags", "secret")
        return nil
    end
    Note("GetSpellCooldown flags", "readable")
    return not active or onGcd == true, active
end

local function onCooldown(api, t)
    if not I.built then
        return
    end
    local A, edge = I.ab, false
    for a = 1, A.n do
        local r = ready(api, A.qid[a])
        if r ~= nil then
            local v = r and 1 or 0
            if v ~= last[a] then
                last[a] = v
                edge = Stage(Obs.Cooldown, t, a, v, 0) or edge
            end
        end
    end
    local _, active = ready(api, I.GCD_SPELL)
    if active ~= nil then
        local v = active and 1 or 0
        if v ~= gcdLast then
            gcdLast = v
            edge = Stage(Obs.Cooldown, t, 0, v, 1) or edge
        end
    end
    if edge then
        S.Urgent("VS_COOLDOWN")
    end
end
S.On("SPELL_UPDATE_COOLDOWN", nil, onCooldown)
S.On("SPELL_UPDATE_CHARGES", nil, onCooldown)
