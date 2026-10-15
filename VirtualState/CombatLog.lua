-- VirtualState/CombatLog.lua
-- The synthesized combat log (event-facade spec §2.4, §3, §4): rows in the client's positional shape, emitted by the
-- sources from plain signals into a 64-row pool, delivered as COMBAT_LOG_EVENT_UNFILTERED (no payload) to the event
-- facade's subscribers after the client event that completed them, or at the next OnUpdate; the facade's
-- CombatLogGetCurrentEventInfo returns the row being delivered. A row with an observed basis carries the observed
-- time in slot 1 and is back-dated: Facade.GetTime answers that time while the row is delivered (decision 5).
-- Credits: the slot layout is the client's combat log (warcraft.wiki.gg COMBAT_LOG_EVENT); the plain signals behind
-- each row follow Taco Dog Forever's research (docs/research/2026-10-14-virtual-combat-log-events.md).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local unpack = unpack

local L = {}
I.Log = L

L.POOL = 64
L.PLAYER_FLAGS = 0x511 -- mine, friendly, player
L.HOSTILE_FLAGS = 0xA48 -- outsider, hostile, NPC

local rows = {}
for i = 1, L.POOL do
    local r = { n = 0, t = 0, backdate = false, family = "", prov = "" }
    for k = 1, 24 do
        r[k] = false
    end
    rows[i] = r
end
local head, count = 1, 0
-- the row a dropped emission fills in (its caller still writes slots 12 on): never queued
local spare = { n = 0, t = 0, backdate = false, family = "", prov = "" }
for k = 1, 24 do
    spare[k] = false
end
local delivering, current = false, nil

L.emitted, L.dropped, L.requeued, L.delivered = 0, 0, 0, 0
L.counts = { cast = 0, swing = 0, missed = 0, damage = 0, onus = 0, aura = 0, energize = 0 }

-- The player's plain GUID (rows' source), read by Sources/Casts.lua at Start and on PLAYER_ENTERING_WORLD.
L.player = ""

--- Queues one row and returns it for its slots 12 on; `last` is its last slot (no nil up to it: ns.callHook rebuilds
--- the tuple with unpack). A full pool drops the oldest undelivered row (counted); during a delivery, when only the
--- delivered row's slot is left, the new row is dropped instead. Allocates nothing.
function L.Emit(sub, last, t, backdate, family, prov, srcGUID, srcFlags, dstGUID, dstFlags)
    local r
    if delivering and count >= L.POOL - 1 then
        -- the row being delivered still holds the slot after the queue: the new row gives way, never that one
        L.dropped = L.dropped + 1
        r = spare
    else
        if count == L.POOL then
            head = head % L.POOL + 1
            count = count - 1
            L.dropped = L.dropped + 1
        end
        r = rows[(head + count - 1) % L.POOL + 1]
        count = count + 1
        if delivering then
            L.requeued = L.requeued + 1 -- delivered after the current row, never nested (ns.callHook drops nested ones)
        end
        L.emitted = L.emitted + 1 -- queued rows only: one given way to `spare` counts in `dropped` alone
        L.counts[family] = L.counts[family] + 1
    end
    r[1], r[2], r[3], r[4], r[5], r[6], r[7] = t, sub, false, srcGUID, "", srcFlags, 0
    r[8], r[9], r[10], r[11] = dstGUID, "", dstFlags, 0
    r.n, r.t, r.backdate, r.family, r.prov = last, t, backdate, family, prov
    return r
end

-- The last slot of each own-cast row (event-facade spec §2.4's table).
local CAST_LAST = { SPELL_CAST_START = 14, SPELL_CAST_SUCCESS = 14, SPELL_CAST_FAILED = 15, SPELL_AURA_REMOVED = 16 }

--- An own-cast row (observed): our spell `spellID` at `t` on `dstGUID` ("" none). A channel's end is its
--- SPELL_AURA_REMOVED on us.
function L.Cast(sub, t, spellID, dstGUID)
    if type(spellID) ~= "number" then
        return -- no nil hole in slot 12
    end
    local dst = dstGUID or ""
    local flags = L.HOSTILE_FLAGS
    if dst == "" or dst == L.player then
        flags = L.PLAYER_FLAGS
    end
    local r = L.Emit(sub, CAST_LAST[sub], t, true, "cast", "observed", L.player, L.PLAYER_FLAGS, dst, flags)
    r[12], r[13], r[14] = spellID, "", 1
    if sub == "SPELL_CAST_FAILED" then
        r[15] = "" -- failedType
    elseif sub == "SPELL_AURA_REMOVED" then
        r[15], r[16] = "BUFF", 0
    end
end

--- Delivers every queued row, oldest first, to the combat log's subscribers; a row emitted meanwhile follows the
--- current one. Runs at the end of each client event and at each OnUpdate, never inside a coroutine (Hekili.Update's:
--- a client event fired synchronously there waits for the OnUpdate, spec §3). Allocates nothing.
function L.Deliver()
    if delivering or count == 0 or coroutine.running() then
        return
    end
    delivering = true
    local h = I.hekili
    while count > 0 do
        local r = rows[head]
        head = head % L.POOL + 1
        count = count - 1
        current = r
        if r.backdate then
            I.backdate = r.t
        end
        if h and h.ActiveDebug then
            pcall(h.Debug, h, "[vs] row %s %s %s t=%.3f", r[2], r.family, r.prov, r.t)
        end
        I.Events.Deliver("COMBAT_LOG_EVENT_UNFILTERED")
        I.backdate = nil
        L.delivered = L.delivered + 1
    end
    current = nil
    delivering = false
end

--- The row being delivered, as the client's CombatLogGetCurrentEventInfo returns it; nothing outside a delivery.
function L.Current()
    local r = current
    if r then
        return unpack(r, 1, r.n)
    end
end

-- The deferred lane: functions run at every OnUpdate with the clock (pairing windows, modelled expiries).
local TICKS = {}
function L.OnTick(fn)
    TICKS[#TICKS + 1] = fn
end

--- Runs the deferred lane at `now` (the event facade's OnUpdate, before it delivers). Allocates nothing.
function L.Tick(now)
    for k = 1, #TICKS do
        TICKS[k](now)
    end
end

--- Snapshot's line: the rows (allocates; debugging only).
I.OnSnapshot(function(out)
    local c = L.counts
    out[#out + 1] = string.format(
        "rows emitted=%d delivered=%d requeued=%d dropped=%d cast=%d swing=%d missed=%d damage=%d onus=%d aura=%d energize=%d",
        L.emitted,
        L.delivered,
        L.requeued,
        L.dropped,
        c.cast,
        c.swing,
        c.missed,
        c.damage,
        c.onus,
        c.aura,
        c.energize
    )
end)
