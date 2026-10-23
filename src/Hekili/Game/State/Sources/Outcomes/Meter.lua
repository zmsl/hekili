-- Game/State/Sources/Outcomes/Meter.lua
-- The damage-meter Outcomes provider (providers spec §2.2): DAMAGE_METER_COMBAT_SESSION_UPDATED's plain (type,
-- sessionID) as a ring of group times; a swing hit iff a damage group lies within 15 ms after it; a row is foreign iff
-- no group stands behind it; a taken group dates a hit on us; the getters only out of combat, for the audit.
-- Measured: docs/research/2026-10-23-damagemeter-api.md (DM §2-§4, §7). Shares no code with any other provider.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local EVENT = "DAMAGE_METER_COMBAT_SESSION_UPDATED"
local RING, MERGE, SWING_WIN, WHITE_BACK = 64, 0.003, 0.015, 2.0
local TAKEN_FAR, TAKEN_NEAR, SPELL_TAKEN, MUTE_AT, AUDIT_FOR = 0.6, 0.3, 0.005, 3, 3

local P = { name = "meter", SWING_DELAY = SWING_WIN, ROW_DELAY = SWING_WIN, muted = 0 }
local gT, gKind, gUsed = {}, {}, {}
for k = 1, RING do
    gT[k], gKind[k], gUsed[k] = -1e9, -1, false
end
local head = 0
local active, available, seen, grouped = false, false, false, false
local toldAvoid, avoidRows = 0, 0
local audit = { valid = false, done = 0, taken = 0, at = 0 }
local auditFrom = nil -- the time of the combat end the audit waits for (nil: none pending)

-- Types 0, 1, 10 (damage done, DPS, the group's) are one damage group; 7 (damage taken) its own; sessionID 0 is the
-- duplicate set (DM §1). Allocates nothing.
S.On(EVENT, nil, function(api, t, ty, sid)
    if not active or sid == 0 or type(ty) ~= "number" then
        return
    end
    local kind = (ty == 0 or ty == 1 or ty == 10) and 0 or (ty == 7 and 7 or -1)
    if kind < 0 then
        return
    end
    if head > 0 and gKind[head] == kind and t - gT[head] <= MERGE then
        return -- the same server batch (DM §2: 29244/29245)
    end
    head = head % RING + 1
    gT[head], gKind[head], gUsed[head] = t, kind, false
    if kind == 0 then
        seen = true
    end
end)
S.Dormant(EVENT, true)

-- Any damage group in [lo, hi]. Allocates nothing.
local function any(lo, hi)
    for k = 1, RING do
        if gKind[k] == 0 and gT[k] >= lo and gT[k] <= hi then
            return true
        end
    end
    return false
end

local function live()
    return active and available and seen and P.muted == 0
end

--- Wakes the event; reads availability (plain, DM §4). Idempotent: VS.Start re-activates a provider a build activated.
function P.Activate(api, t)
    active = true
    if api then
        local DM = api.C_DamageMeter
        local ok, a = false, nil
        if type(DM) == "table" then
            ok, a = pcall(DM.IsDamageMeterAvailable) -- secret: Plain next (measured plain, DM §4)
        end
        available = ok and Plain(api, a) == true
        S.Dormant(EVENT, false)
        I.Events.Sync(EVENT)
    end
end

function P.Deactivate()
    active = false
    S.Dormant(EVENT, true)
    I.Events.Sync(EVENT)
end

--- (decision 70, the 15 ms rule) HIT when a damage group lies in [swing, swing + 15 ms], else AVOID; UNDECIDED until
--- live, and for the rest of the fight once told avoids outrun the avoid rows by MUTE_AT (counted `muted`).
function P.SwingOutcome(i, now)
    if not live() then
        return I.UNDECIDED
    end
    local at = I.Tickets.at[i]
    if any(at, at + SWING_WIN) then
        return I.HIT
    end
    toldAvoid = toldAvoid + 1
    if toldAvoid > avoidRows + MUTE_AT then
        P.muted = 1
        return I.UNDECIDED
    end
    return I.AVOID
end

--- (decision 73) FOREIGN when no damage group stands behind a wound (a white row's swing group precedes it by up to 2 s,
--- DM §2); OURS solo when one does; UNDECIDED in a group, for an avoid and while not live.
function P.RowOwner(t, uid, school, amount, act, now)
    if not live() or act ~= "WOUND" then
        return I.UNDECIDED
    end
    local lo = school == 1 and t - WHITE_BACK or t - MERGE
    if not any(lo, t + SWING_WIN) then
        return I.FOREIGN
    end
    if grouped then
        return I.UNDECIDED
    end
    return I.OURS
end

--- (decision 75) The latest unused taken group 0.3-0.6 s before a white hit row on us at t (DM §3: 389-565 ms), or
--- within 5 ms of a spell row (`school` not 1); marked used. nil in a group (partners' hits taken fire type 7 too) or
--- while not live. Allocates nothing.
function P.EnemyHitAt(t, school)
    if not live() or grouped then
        return nil
    end
    local lo, hi = t - TAKEN_FAR, t - TAKEN_NEAR
    if school ~= 1 then
        lo, hi = t - SPELL_TAKEN, t + SPELL_TAKEN
    end
    local best = 0
    for k = 1, RING do
        if gKind[k] == 7 and not gUsed[k] and gT[k] >= lo and gT[k] <= hi and (best == 0 or gT[k] > gT[best]) then
            best = k
        end
    end
    if best == 0 then
        return nil
    end
    gUsed[best] = true
    return gT[best]
end

--- The last fight's totals, read out of combat: { valid, done, taken, at }, or nil until read.
function P.Audit()
    return audit.valid and audit or nil
end

-- the white avoid rows the mute compares against (any unit: an avoid of ours is on the unit we swung at)
I.Units.OnRow(function(t, g, uid, act, flag, amount, school)
    if active and school == 1 and (act == "MISS" or act == "DODGE" or act == "PARRY") then
        avoidRows = avoidRows + 1
    end
end)

S.On("PLAYER_REGEN_DISABLED", nil, function(api, t)
    if not active then
        return
    end
    seen, P.muted, toldAvoid, avoidRows = false, 0, 0, 0
    grouped = Plain(api, api.IsInGroup()) == true -- secret: Plain (IsInGroup is plain)
    audit.valid, auditFrom = false, nil
end)

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    if active then
        auditFrom = t
    end
end)

-- One getter read of `ty` (0 done, 7 taken): the local player's total, or nil when anything read is secret or
-- missing. Out of combat only: the getters allocate (DM §7).
local function total(api, ty)
    local DM = api.C_DamageMeter
    if type(DM) ~= "table" then
        return nil
    end
    local ok, s = pcall(DM.GetCombatSessionFromType, 1, ty) -- secret: tested next
    if not ok or api.issecretvalue(s) or type(s) ~= "table" then
        return nil
    end
    local list = s.combatSources
    if api.issecretvalue(list) or type(list) ~= "table" then
        return nil
    end
    for k = 1, #list do
        local src = list[k]
        if api.issecretvalue(src) or type(src) ~= "table" then
            return nil
        end
        local mine = Plain(api, src.isLocalPlayer) -- NeverSecret (DM §4)
        if mine == nil then
            return nil
        elseif mine == true then
            local v = Plain(api, src.totalAmount)
            return type(v) == "number" and v or nil
        end
    end
    return 0 -- no row of ours this session
end

-- Poll 16 (after the presence poll 15): the audit, out of combat, retried for AUDIT_FOR s after combat end.
S.Poll(16, function(api, t)
    if not auditFrom or I.inCombat then
        return
    end
    if t - auditFrom > AUDIT_FOR then
        auditFrom = nil
        return
    end
    local d, k = total(api, 0), total(api, 7)
    if d and k then
        audit.valid, audit.done, audit.taken, audit.at, auditFrom = true, d, k, t, nil
    end
end)

I.OUTCOMES.meter = P
