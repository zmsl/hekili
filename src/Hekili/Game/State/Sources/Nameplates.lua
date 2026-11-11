-- Game/State/Sources/Nameplates.lua
-- Nameplate sources (spec §4.5, §6.9): the plate tokens from NAME_PLATE_UNIT_ADDED/REMOVED; poll 5 reports a plate
-- whose plain UnitIsDead answers true to the unit registry (one death).
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Nameplates.lua.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local PLATES = 40
local token, index, active = {}, {}, {}
for k = 1, PLATES do
    token[k] = "nameplate" .. k
    index[token[k]] = k
    active[k] = false
end
I.Plates = { active = active, token = token } -- Sources/Target.lua finds the target's plate at a target change

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

-- Poll 5: a plate whose plain UnitIsDead answers true is reported to the registry (one death).
S.Poll(5, function(api, t)
    for k = 1, PLATES do
        if active[k] and Plain(api, api.UnitIsDead(token[k])) == true then
            I.Units.Dead(I.Units.Uid(k + 2), t) -- nameplateK is the registry's token K + 2
        end
    end
end)
