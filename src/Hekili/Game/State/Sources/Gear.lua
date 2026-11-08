-- Game/State/Sources/Gear.lua
-- Gear sources (gear-aware spec §7): the declared gear's values (Families/Gear.lua), read as the core's ns.updateGear
-- reads them (Engine/Sim/Events.lua:541-574): an item or set key counts its equipped pieces (C_Item.IsEquippedItem,
-- plain [W PR13], no item cache needed), a bonus key is 1 while the belief holds its aura on the player (the core's
-- read is the same record, through the facade's virtual GetPlayerAuraBySpellID). At each build the items at once and
-- everything 1 s later (the core's re-read, Q2); 1 s after PLAYER_EQUIPMENT_CHANGED, PLAYER_ALIVE and
-- ZONE_CHANGED_NEW_AREA (the core's QueueUpdate and CheckSpellsAndGear), restarted by each event. In or out of combat:
-- the reads are plain, no deferral. Each changed value is logged as `Gear`. Allocates nothing per read.
-- Credits: secret-value handling after Catnip's (Durts) research.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local S = I.Sources
local Obs = VS.Obs
local Plain, Direct, Note = S.Plain, S.Direct, S.Note
local G = I.gear

I.GEAR_DELAY = 1 -- the core's 1 s (Events.lua QueueUpdate, Spec/Activation.lua CheckSpellsAndGear)
local dueAt = 0 -- the pending read's time; 0 none

-- 1 equipped, 0 not, nil a secret answer (the key keeps its value). Allocates nothing.
local function equipped(api, id)
    local v = Plain(api, api.C_Item.IsEquippedItem(id))
    if v == nil then
        return nil -- a secret answer (the client answers a boolean)
    end
    return v == true and 1 or 0
end

local function read(api, t, itemsOnly)
    local changed, secret = false, false
    for k = 1, G.n do
        local v
        if G.aura[k] > 0 then
            if not itemsOnly then
                v = VS.Aura("player", G.aura[k], t) and 1 or 0
            end
        else
            v = 0
            local ids = G.items[k]
            for i = 1, #ids do
                local e = equipped(api, ids[i])
                if e == nil then
                    v, secret = nil, true
                    break
                end
                v = v + e
            end
        end
        if v and I.SetGear(k, v) then
            Direct(Obs.Gear, t, k, v)
            changed = true
        end
    end
    if changed then
        I.GearPublish()
    end
    Note("gear set reads", secret and "secret" or "readable")
end

-- Unprobed in game, and it runs inside Build: a raise costs the gear values, never a build.
local function safeRead(api, t, itemsOnly)
    if not pcall(read, api, t, itemsOnly) then
        Note("gear set reads", "error")
        I.GearPublish()
    end
end

local function request(_, t)
    if I.built then
        dueAt = t + I.GEAR_DELAY
    end
end

I.OnBuild(function(_, now)
    dueAt = 0
    if I.api and G.n > 0 then
        safeRead(I.api, now, true)
        dueAt = now + I.GEAR_DELAY -- Q2's re-read (without Q2: no dueAt here)
    end
end)

-- A build before Start had no api for its read: read once Start gives one (as Sources/Talents.lua's S.OnStart(request)).
S.OnStart(function(_, t)
    if I.built and G.n > 0 then
        dueAt = t
    end
end)

S.On("PLAYER_EQUIPMENT_CHANGED", nil, request)
S.On("PLAYER_ALIVE", nil, request)
S.On("ZONE_CHANGED_NEW_AREA", nil, request)

-- Poll 8: the pending read, once due.
S.Poll(8, function(api, t)
    if dueAt > 0 and t >= dueAt then
        dueAt = 0
        safeRead(api, t, false)
    end
end)
