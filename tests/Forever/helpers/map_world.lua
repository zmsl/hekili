-- tests/Forever/helpers/map_world.lua (T1, plate count plan v2 §3 task 2): a headless instance with enemy nameplates
-- in three worlds. "A" the open world: plain GUIDs, each plate stored by its GUID. "B" a dungeon under the Map
-- restriction: every unit identity (GUID, name) secret, plates by their ADDED events only. "C": B in combat, the target's
-- aura walk raising and its health secret. The plate enemy count reads, measured or assumed:
-- tests/Forever/fixtures/dungeon_map_reads.lua.
local fake = require("Game.State.helpers.fake_api")
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

local SECRET = fake.SECRET
local M = { SECRET = SECRET }

-- The client's two plate CVars (Targets.lua's showNPs).
local function platesShown(ctl, on)
    ctl.cvars.nameplateShowEnemies = on and "1" or nil
    ctl.cvars.nameplateShowAll = on and "1" or nil
end
M.platesShown = platesShown

local function ident(H, unit, guid)
    local ctl = H.ctl
    if H.world == "A" then
        ctl.guid[unit], ctl.names[unit] = guid, nil
    else
        ctl.guid[unit], ctl.names[unit] = SECRET, SECRET
    end
end

--- A booted instance in world `w` ("A", "B" or "C"); `o.character`, `o.pack` (default: the Arms world's). No target,
--- no plates; the plate CVars on.
function M.new(w, o)
    o = o or {}
    local H = headless.new({ character = o.character or ww.character(), pack = o.pack or ww.PACK })
    assert(#H.loadErrors == 0, tostring(H.loadErrors[1]))
    H.world = w
    local ctl = H.ctl
    platesShown(ctl, true)
    ctl.level.target = 60
    ident(H, "target", "Creature-1")
    ctl.exists.target = false
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, ctl.now + 0.2))
    if w == "C" then
        ctl.combat = true
        ctl.auraError.target = true
        ctl.unitHealth.target = SECRET
        H.Fire("PLAYER_REGEN_DISABLED")
    end
    return H
end

--- Plate k up (a hostile mob, 60, in reach): its ADDED event.
function M.plate(H, k)
    local unit = "nameplate" .. k
    ident(H, unit, "Creature-p" .. k)
    H.ctl.exists[unit], H.ctl.level[unit] = true, 60
    if H.world == "C" then
        H.ctl.unitHealth[unit] = SECRET
    end
    H.Fire("NAME_PLATE_UNIT_ADDED", unit)
end

--- Plate k gone: its REMOVED event (UnitExists still true during it, as in game), then the token empty.
function M.unplate(H, k)
    local unit = "nameplate" .. k
    H.Fire("NAME_PLATE_UNIT_REMOVED", unit)
    H.ctl.exists[unit], H.ctl.guid[unit], H.ctl.names[unit] = nil, nil, nil
end

--- Target plate k's mob (0: a mob with no plate; nil: no target). Both orders of the target compare answer it (the
--- client's UnitIsUnit is symmetric; the fake keys it by the first token).
function M.target(H, k)
    local ctl = H.ctl
    for i = 1, 40 do
        local u = "nameplate" .. i
        if ctl.unitIs[u] == "target" then
            ctl.unitIs[u] = nil
        end
    end
    ctl.unitIs.target = nil
    ctl.exists.target = k ~= nil
    ctl.inRange.target = k ~= nil or nil
    if k == nil then
        ctl.guid.target, ctl.names.target = nil, nil
    elseif k == 0 then
        ident(H, "target", "Creature-t0")
    else
        local u = "nameplate" .. k
        ident(H, "target", "Creature-p" .. k)
        ctl.unitIs.target, ctl.unitIs[u] = u, "target"
    end
    H.Fire("PLAYER_TARGET_CHANGED")
end

--- The count as published after the plate count's one-update hold has settled (two forced counts).
function M.count(H)
    H.ns.getNumberTargets(true)
    return H.ns.getNumberTargets(true)
end

return M
