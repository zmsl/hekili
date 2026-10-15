-- VirtualState/Sources/Casts.lua
-- Own-cast sources (spec §4.2, §4.6): our UNIT_SPELLCAST_* events become staged observations (urgent lane) and,
-- synchronously in the handler, feed Hekili's across-reset caches through the hooks Adapter.lua sets in `I.feed`
-- (cast history, the real queue's CAST_FINISH and channel events, their removal). Poll 3: the on-next-swing queue.
-- Credits: secret-value handling after Catnip's (Durts) research.
-- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Casts.lua.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Stage, Direct, Urgent = S.Plain, S.Stage, S.Direct, S.Urgent

I.sentGUID = nil

local function ability(spellID)
    return spellID and I.ab.bySpell[spellID]
end

S.On("UNIT_SPELLCAST_SENT", "player", function(api, t, unit)
    if unit == "player" then
        I.sentGUID = Plain(api, api.UnitGUID("target"))
    end
end)

S.On("UNIT_SPELLCAST_START", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, rawStart, rawEnd = api.UnitCastingInfo("player") -- secret: both through Plain next
    local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
    if type(start) == "number" and type(finish) == "number" then
        Stage(Obs.CastStart, t, a, finish / 1000)
        local f = I.feed.CastStart
        if f then
            f(a, start / 1000, finish / 1000, I.sentGUID)
        end
    end
    Urgent("UNIT_SPELLCAST_START")
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    Stage(Obs.CastSuccess, t, a)
    local f = I.feed.CastSucceeded
    if f then
        f(a, spellID, I.sentGUID or Plain(api, api.UnitGUID("target")))
    end
    I.sentGUID = nil
    Urgent("UNIT_SPELLCAST_SUCCEEDED")
end)

local function stopped(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    Stage(Obs.CastStop, t, a)
    local f = I.feed.CastFailed
    if f then
        f(a)
    end
    Urgent("UNIT_SPELLCAST_FAILED")
end
S.On("UNIT_SPELLCAST_FAILED", "player", stopped)
S.On("UNIT_SPELLCAST_INTERRUPTED", "player", stopped)

S.On("UNIT_SPELLCAST_DELAYED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, _, rawEnd = api.UnitCastingInfo("player") -- secret: Plain next
    local finish = Plain(api, rawEnd)
    if type(finish) == "number" then
        Stage(Obs.CastDelay, t, a, finish / 1000)
    end
end)

S.On("UNIT_SPELLCAST_CHANNEL_START", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, rawStart, rawEnd = api.UnitChannelInfo("player") -- secret: both through Plain next
    local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
    if type(start) == "number" and type(finish) == "number" then
        Stage(Obs.ChannelStart, t, a, finish / 1000)
        local f = I.feed.ChannelStart
        if f then
            f(a, start / 1000, finish / 1000, I.sentGUID or Plain(api, api.UnitGUID("target")))
        end
    end
    Urgent("UNIT_SPELLCAST_CHANNEL_START")
end)

S.On("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    local _, _, _, _, rawEnd = api.UnitChannelInfo("player") -- secret: Plain next
    local finish = Plain(api, rawEnd)
    if type(finish) == "number" then
        Stage(Obs.ChannelUpdate, t, a, finish / 1000)
    end
end)

S.On("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and ability(spellID)
    if not a then
        return
    end
    Stage(Obs.ChannelStop, t, a)
    local f = I.feed.ChannelStop
    if f then
        f(a)
    end
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
