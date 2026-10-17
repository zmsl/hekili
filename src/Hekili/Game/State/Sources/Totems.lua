-- Game/State/Sources/Totems.lua
-- Totem sources (spec §4.2, §4.5): out of combat, the four slots of GetTotemInfo (on PLAYER_TOTEM_UPDATE and poll 7),
-- each an observed `Totem` (c = 1) with its facts; in combat (the read is secret) PLAYER_TOTEM_UPDATE logs the slot
-- with no read (c = 0), which the family takes as a destruction unless our cast just summoned it.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, the totem half of src/TacoDogForever/Sources/Pets.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Direct = S.Plain, S.Stage, S.Direct

-- The last plain read of each slot (its expiry; -1 before any), so a poll logs only changes.
local last = { -1, -1, -1, -1 }

local function read(api, slot, t, direct)
    local rawUp, rawName, rawStart, rawDur, rawIcon, _, rawSpell = api.GetTotemInfo(slot) -- secret: Plain next
    local up, name, start = Plain(api, rawUp), Plain(api, rawName), Plain(api, rawStart)
    local dur, icon, spell = Plain(api, rawDur), Plain(api, rawIcon), Plain(api, rawSpell)
    if up == nil then
        return
    end
    local e = 0
    if up and type(start) == "number" and type(dur) == "number" and dur > 0 then
        e = start + dur
        I.totemName[slot] = type(name) == "string" and name or ""
        I.totemIcon[slot] = type(icon) == "number" and icon or 0
        I.totemSpell[slot] = type(spell) == "number" and spell or 0
        I.totemStart[slot] = start
    end
    if e ~= last[slot] then
        last[slot] = e
        if direct then
            Direct(Obs.Totem, t, slot, e, 1)
        else
            Stage(Obs.Totem, t, slot, e, 1)
        end
    end
end

S.On("PLAYER_TOTEM_UPDATE", nil, function(api, t, slot)
    if type(slot) ~= "number" or slot < 1 or slot > 4 then
        return
    end
    if I.inCombat then
        last[slot] = -1
        Stage(Obs.Totem, t, slot, 0, 0)
    else
        read(api, slot, t, false)
    end
end)

-- Poll 7: the four slots, out of combat.
S.Poll(7, function(api, t)
    if not I.inCombat then
        for slot = 1, 4 do
            read(api, slot, t, true)
        end
    end
end)
