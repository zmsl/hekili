-- Kinds/Percent.lua: health and power, in percent 0-100 (the client's reads give 0-1 through the curve; the scale is
-- fixed and checked by the self-test, never read). Proven (BandProbe run 2026-11-20): health on player and target,
-- power mana and energy on the player, by the type the spec names (required); rage on the player (BandProbe2 warm-up
-- 2026-11-20, bear form in combat under the lockdown; the library's own run is owed). Anything else is a handle that
-- reports "unavailable", "unproven".
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local GUARD = 0.05 -- percent: the curve's guard distance; an edge needs room for its guard point above 0
local PROVEN_POWER = { [0] = true, [1] = true, [3] = true } -- Enum.PowerType Mana, Rage and Energy

-- Reads and checks the spec into the handle; returns an error code (lib.ERR) when the spec is refused.
local function validate(spec, h)
    local E = lib.ERR
    local unit, edges, step = spec.unit, spec.edges, spec.step
    if type(unit) ~= "string" or not unit:match("^%a%w*$") then
        return E.UNIT_INVALID
    end
    if edges ~= nil and type(edges) ~= "table" then
        return E.EDGES_INVALID
    end
    if step ~= nil and (type(step) ~= "number" or not (step > 0)) then
        return E.STEP_INVALID
    end
    if (edges == nil or #edges == 0) and step == nil then
        return E.EDGES_REQUIRED
    end
    if spec.power ~= nil and type(spec.power) ~= "number" then
        return E.POWER_INVALID
    end
    if h.kind == "power" and spec.power == nil then
        -- required: a default (the displayed power) would let a form change swap what the handle measures
        return E.POWER_REQUIRED
    end
    local list = {}
    for i = 1, edges and #edges or 0 do
        local e = edges[i]
        if type(e) ~= "number" then
            return E.EDGES_INVALID
        end
        if not (e > GUARD and e <= 100) then
            return E.EDGES_OUT_OF_RANGE
        end
        list[i] = e
    end
    table.sort(list)
    local out = {}
    for i = 1, #list do -- duplicates and edges closer than the guard distance merge into the lower one
        if #out == 0 or list[i] - out[#out] >= GUARD then
            out[#out + 1] = list[i]
        end
    end
    h.unit, h.edges, h.power, h.predicted = unit, out, spec.power, spec.predicted ~= false
    if
        not lib.kinds[h.kind].units[unit]
        or #out == 0 -- a step alone: position is a later stage
        or spec.points
        or (h.kind == "power" and not PROVEN_POWER[spec.power])
    then
        h.unproven = "unproven"
    end
end

lib.kinds.health = {
    api = "UnitHealthPercent",
    units = { player = true, target = true },
    validate = validate,
    read = function(s, curve)
        return UnitHealthPercent(s.unit, s.predicted, curve)
    end,
}

lib.kinds.power = {
    api = "UnitPowerPercent",
    units = { player = true },
    validate = validate,
    read = function(s, curve)
        return UnitPowerPercent(s.unit, s.power, false, curve)
    end,
}
