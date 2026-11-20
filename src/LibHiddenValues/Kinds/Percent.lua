-- Kinds/Percent.lua: health and power, in percent 0-100 (the client's reads give 0-1 through the curve; the scale is
-- fixed and checked by the self-test, never read). Proven (BandProbe run 2026-11-20): health on player and target,
-- power mana and energy on the player. Anything else is a handle that reports "unavailable", "unproven".
local lib = LibStub and LibStub("LibHiddenValues-1.0", true)
if not (lib and lib.loading) then
    return
end

local GUARD = 0.05 -- percent: the curve's guard distance; an edge needs room for its guard point above 0
local PROVEN_POWER = { [0] = true, [3] = true } -- Enum.PowerType Mana and Energy (rage: a later stage)

-- Reads and checks the spec into the handle; returns an error text for bad-spec.
local function validate(spec, h)
    local unit, edges, step = spec.unit, spec.edges, spec.step
    if type(unit) ~= "string" or not unit:match("^%a%w*$") then
        return "unit must be a unit token"
    end
    if edges ~= nil and type(edges) ~= "table" then
        return "edges must be a list of percents"
    end
    if step ~= nil and (type(step) ~= "number" or not (step > 0)) then
        return "step must be a positive number"
    end
    if (edges == nil or #edges == 0) and step == nil then
        return "edges or step required"
    end
    if spec.power ~= nil and type(spec.power) ~= "number" then
        return "power must be an Enum.PowerType number"
    end
    local list = {}
    for i = 1, edges and #edges or 0 do
        local e = edges[i]
        if type(e) ~= "number" or not (e > GUARD and e <= 100) then
            return "edges must be numbers in (0.05, 100]"
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
        or (h.kind == "power" and spec.power ~= nil and not PROVEN_POWER[spec.power])
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
        return UnitPowerPercent(s.unit, s.pt, false, curve)
    end,
    -- The power type fed: the named one, or the unit's displayed one (followed through UNIT_DISPLAYPOWER) while it is
    -- proven. Returns true when it changed (the source primes).
    resolve = function(s)
        local old = s.pt
        if s.power ~= nil then
            s.pt = s.power
        else
            local pt = UnitPowerType(s.unit)
            local ok = not issecretvalue(pt) and PROVEN_POWER[pt]
            s.pt = ok and pt or nil
            s.unproven = not ok and "unproven" or nil
        end
        return s.pt ~= old
    end,
}
