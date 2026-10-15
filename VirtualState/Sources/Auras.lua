-- VirtualState/Sources/Auras.lua
-- Aura sources (spec §4.5): one C_UnitAuras.GetAuraDataByIndex walk per tracked unit per UNIT_AURA, helpful then
-- harmful, each call pcall'd; the walk stops at the first error, secret or nil (in combat that is one call per
-- filter). Entries whose spellId is tracked become `Read` observations straight to the log (remaining time, stacks).
-- After a complete walk, a believed-up aura it did not find is logged down, but in combat only once that aura was
-- seen readable in combat (before that, a miss may be the client hiding it).
-- Credits: the pcall-then-issecretvalue handling and the "seen readable in combat" rule follow Catnip's (Durts)
-- secret-value research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Auras.lua (:42, :58-61, :74, :148).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs, ReadOf = VS.Obs, I.ReadOf
local Plain, Direct, Note = S.Plain, S.Direct, S.Note

local SCAN = 40
local FILTERS = { "HELPFUL", "HARMFUL" }
-- The walk status per unit index ("aura walk <unit>", built at OnBuild for every tracked unit), so Snapshot tells
-- them apart.
local WALK = {}

-- By unit index and aura index: the walk serial that last found it, and whether it was seen plain in combat.
local found, seen = {}, {}
local serial = 0

I.OnBuild(function(def)
    local U = I.auras
    for u = 1, U.n do
        WALK[u] = "aura walk " .. tostring(def.units[u])
        local f, s = {}, {}
        for j = 1, U.nAura do
            f[j], s[j] = 0, false
        end
        found[u], seen[u] = f, s
    end
end)

-- One unit's walk at t. Allocates nothing (the client allocates its aura tables).
local function walk(api, u, unit, t)
    local U = I.auras
    serial = serial + 1
    local complete = true
    for f = 1, #FILTERS do
        local filter = FILTERS[f]
        for i = 1, SCAN do
            local ok, raw = pcall(api.C_UnitAuras.GetAuraDataByIndex, unit, i, filter) -- secret: tested next
            if not ok then
                Note(WALK[u], "error")
                complete = false
                break
            elseif api.issecretvalue(raw) then
                Note(WALK[u], "secret")
                complete = false
                break
            end
            local data = Plain(api, raw)
            if not data then
                break
            end
            local id = Plain(api, data.spellId)
            if id == nil then
                complete = false
                Note(WALK[u], "secret")
                break
            end
            local j = U.bySpell[id]
            if j then
                local exp, apps = Plain(api, data.expirationTime), Plain(api, data.applications)
                if type(exp) ~= "number" then
                    complete = false
                    Note(WALK[u], "secret")
                    break
                end
                Note(WALK[u], "readable")
                found[u][j] = serial
                if I.inCombat then
                    seen[u][j] = true
                end
                local stacks = type(apps) == "number" and apps or 0
                local remaining = exp > 0 and exp - t or -1
                if remaining > 0 or exp == 0 then
                    Direct(Obs.Read, t, (u - 1) * I.AURA_UNIT + j, remaining, ReadOf.Aura + stacks * I.AURA_STACK)
                    U.harm[u][j] = filter == "HARMFUL"
                end
            end
        end
        if not complete then
            break
        end
    end
    if complete then
        Note(WALK[u], "readable") -- a clean walk, even with no tracked aura up
        local e = U.exp0[u]
        for j = 1, U.nAura do
            if e[j] > 0 and found[u][j] ~= serial and (not I.inCombat or seen[u][j]) then
                Direct(Obs.Read, t, (u - 1) * I.AURA_UNIT + j, 0, ReadOf.Aura)
            end
        end
    end
end
I.WalkAuras = walk

S.On("UNIT_AURA", nil, function(api, t, unit)
    local u = unit and I.built and I.auras.index[unit]
    if u then
        if u ~= 1 and Plain(api, api.UnitExists(unit)) ~= true then
            return
        end
        walk(api, u, unit, t)
    end
end)

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    if not I.built then
        return
    end
    local U = I.auras
    for u = 1, U.n do
        for j = 1, U.nAura do
            seen[u][j] = false
        end
    end
end)
