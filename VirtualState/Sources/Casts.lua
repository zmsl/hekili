-- VirtualState/Sources/Casts.lua
-- Own-cast sources (spec §4.2; event-facade spec §2.4): our UNIT_SPELLCAST_* events become staged observations
-- (urgent lane) and the combat log's own-cast rows (SPELL_CAST_START, _SUCCESS, _FAILED, a channel's
-- SPELL_AURA_REMOVED), which Hekili's CLEU handler turns into its cast history and real queue as on retail. Poll 3:
-- the on-next-swing queue.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Casts.lua (castGUID matching: castStopped, isChannel).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Direct, Urgent = S.Plain, S.Stage, S.Direct, S.Urgent

I.sentGUID = nil

local function readPlayer(api)
    I.Log.player = Plain(api, api.UnitGUID("player")) or ""
end
S.OnStart(readPlayer)
S.On("PLAYER_ENTERING_WORLD", nil, readPlayer)

-- The castGUIDs of our cast and channel in progress (plain strings; nil none or secret). Only these stop, delay or
-- update them: a second press that fails ("another action is in progress") has another castGUID.
local castGUID, chanGUID = nil, nil

local function ability(spellID)
    return spellID and I.ab.bySpell[spellID]
end

S.On("UNIT_SPELLCAST_SENT", "player", function(api, t, unit)
    if unit == "player" then
        I.sentGUID = Plain(api, api.UnitGUID("target"))
    end
end)

S.On("UNIT_SPELLCAST_START", "player", function(api, t, unit, guid, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    castGUID = Plain(api, guid)
    local _, _, _, rawStart, rawEnd = api.UnitCastingInfo("player") -- secret: both through Plain next
    local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
    if type(start) == "number" and type(finish) == "number" then
        Stage(Obs.CastStart, t, a, finish / 1000)
        I.Log.Cast("SPELL_CAST_START", t, spellID, I.sentGUID) -- "" when unknown: CLEU falls back to the target
    end
    Urgent("UNIT_SPELLCAST_START")
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    Stage(Obs.CastSuccess, t, a)
    I.Log.Cast("SPELL_CAST_SUCCESS", t, spellID, I.sentGUID or Plain(api, api.UnitGUID("target")))
    I.sentGUID = nil
    Urgent("UNIT_SPELLCAST_SUCCEEDED")
end)

local function stopped(api, t, unit, guid, spellID)
    local a = unit == "player" and ability(spellID)
    local g = Plain(api, guid)
    if not a or g == nil or g ~= castGUID then
        return
    end
    castGUID = nil
    Stage(Obs.CastStop, t, a)
    I.Log.Cast("SPELL_CAST_FAILED", t, spellID, nil)
    Urgent("UNIT_SPELLCAST_FAILED")
end
S.On("UNIT_SPELLCAST_FAILED", "player", stopped)
S.On("UNIT_SPELLCAST_INTERRUPTED", "player", stopped)

S.On("UNIT_SPELLCAST_DELAYED", "player", function(api, t, unit, guid, spellID)
    local a = unit == "player" and ability(spellID)
    local g = Plain(api, guid)
    if not a or g == nil or g ~= castGUID then
        return
    end
    local _, _, _, _, rawEnd = api.UnitCastingInfo("player") -- secret: Plain next
    local finish = Plain(api, rawEnd)
    if type(finish) == "number" then
        Stage(Obs.CastDelay, t, a, finish / 1000)
    end
end)

S.On("UNIT_SPELLCAST_CHANNEL_START", "player", function(api, t, unit, guid, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    chanGUID = Plain(api, guid)
    local _, _, _, rawStart, rawEnd = api.UnitChannelInfo("player") -- secret: both through Plain next
    local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
    if type(start) == "number" and type(finish) == "number" then
        Stage(Obs.ChannelStart, t, a, finish / 1000) -- its SPELL_CAST_SUCCESS row comes from UNIT_SPELLCAST_SUCCEEDED
    end
    Urgent("UNIT_SPELLCAST_CHANNEL_START")
end)

-- Whether an update or stop is our channel's: its castGUID, or any when CHANNEL_START's was secret (TDF isChannel; the
-- family then matches by ability). A late stop of a channel already replaced by a chained one matches nothing.
local function ownChannel(api, guid)
    if chanGUID == nil then
        return true
    end
    local g = Plain(api, guid)
    return g ~= nil and g == chanGUID
end

S.On("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", function(api, t, unit, guid, spellID)
    local a = unit == "player" and ability(spellID)
    if not a or not ownChannel(api, guid) then
        return
    end
    local _, _, _, _, rawEnd = api.UnitChannelInfo("player") -- secret: Plain next
    local finish = Plain(api, rawEnd)
    if type(finish) == "number" then
        Stage(Obs.ChannelUpdate, t, a, finish / 1000)
    end
end)

S.On("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(api, t, unit, guid, spellID)
    local a = unit == "player" and ability(spellID)
    if not a or not ownChannel(api, guid) then
        return
    end
    Stage(Obs.ChannelStop, t, a)
    I.Log.Cast("SPELL_AURA_REMOVED", t, spellID, I.Log.player)
    Urgent("UNIT_SPELLCAST_CHANNEL_STOP")
end)

-- By ability index: the last queued answer (-1 none).
local queued = {}
I.OnBuild(function(def)
    for a = 1, #def.abilities do
        queued[a] = -1
    end
end)

-- Poll 3: the swing queue (C_Spell.IsCurrentSpell per on-next-swing ability), on change.
S.Poll(3, function(api, t)
    local A = I.ab
    for a = 1, A.n do
        if A.obj[a].onNextSwing then
            local q = Plain(api, api.C_Spell.IsCurrentSpell(A.qid[a]))
            if q ~= nil then
                local v = q and 1 or 0
                if v ~= queued[a] then
                    queued[a] = v
                    Direct(Obs.Queued, t, a, v)
                end
            end
        end
    end
end)
