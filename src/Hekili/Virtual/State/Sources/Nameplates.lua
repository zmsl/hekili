-- Virtual/State/Sources/Nameplates.lua
-- Nameplate sources (spec §4.5, §6.9): the plate tokens from NAME_PLATE_UNIT_ADDED/REMOVED; poll 5 counts the live,
-- attackable plates (plain UnitExists, UnitIsDead, UnitCanAttack) into `Enemies`; poll 8 counts, per tracked attack
-- (an ability that starts combat), the plates in range of its spell (plain C_Spell.IsSpellInRange) into `Range`.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Nameplates.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Direct = S.Plain, S.Direct

local PLATES = 40
local token, index, active = {}, {}, {}
for k = 1, PLATES do
    token[k] = "nameplate" .. k
    index[token[k]] = k
    active[k] = false
end

S.On("NAME_PLATE_UNIT_ADDED", nil, function(api, t, unit)
    local k = unit and index[unit]
    if k then
        active[k] = true
    end
end)

S.On("NAME_PLATE_UNIT_REMOVED", nil, function(api, t, unit)
    local k = unit and index[unit]
    if k then
        active[k] = false
    end
end)

local function live(api, unit)
    return Plain(api, api.UnitExists(unit)) == true
        and Plain(api, api.UnitIsDead(unit)) == false
        and Plain(api, api.UnitCanAttack("player", unit)) == true
end

-- Poll 5: the enemy count.
S.Poll(5, function(api, t)
    local n = 0
    for k = 1, PLATES do
        if active[k] and live(api, token[k]) then
            n = n + 1
        end
    end
    Direct(Obs.Enemies, t, 0, n)
end)

-- Poll 8: per tracked attack, the plates in range of its spell.
S.Poll(8, function(api, t)
    local A = I.ab
    for a = 1, A.n do
        if A.obj[a].startsCombat then
            local n = 0
            for k = 1, PLATES do
                if active[k] and Plain(api, api.C_Spell.IsSpellInRange(A.qid[a], token[k])) == true then
                    n = n + 1
                end
            end
            if n ~= I.inRange[a] then
                Direct(Obs.Range, t, a, n)
            end
        end
    end
end)
