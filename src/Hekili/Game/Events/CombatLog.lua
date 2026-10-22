-- Game/Events/CombatLog.lua
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

-- The target's plain GUID (rows' destination for our debuffs), kept by Game/Events/Attackers.lua.
L.target = ""

-- Our auras' rows (decision 5: APPLIED and REFRESH at the cast's time, back-dated; REMOVED at the modelled expiry,
-- stamped at delivery). Per tracked aura and unit (1 player, 2 target): the believed expiry, its spell, its target.
local auraExp, auraId, auraDst = { {}, {} }, { {}, {} }, { {}, {} }
I.OnBuild(function(def)
    for u = 1, 2 do
        for j = 1, math.max(#def.auras, #auraExp[u]) do
            auraExp[u][j], auraId[u][j], auraDst[u][j] = 0, 0, ""
        end
    end
end)

local function auraRow(sub, u, j, t, backdate, prov)
    local dst = auraDst[u][j]
    local flags = L.HOSTILE_FLAGS
    if u == 1 then
        flags = L.PLAYER_FLAGS
    end
    local r = L.Emit(sub, 16, t, backdate, "aura", prov, L.player, L.PLAYER_FLAGS, dst, flags)
    r[12], r[13], r[14], r[15], r[16] = auraId[u][j], "", 1, u == 1 and "BUFF" or "DEBUFF", 0
end

--- What our cast at `t` did to tracked aura `j` on unit `u` (1 player, 2 target): its expiry before and after the
--- `now` verbs (Families/Now.lua). No row without a destination GUID (Hekili would count "" as an enemy).
--- Allocates nothing.
function L.Aura(u, j, spellID, before, after, t)
    if type(spellID) ~= "number" then
        return
    end
    if after > t then
        local dst = L.player
        if u == 2 then
            dst = L.target
        end
        if dst == "" then
            return
        end
        auraId[u][j], auraExp[u][j], auraDst[u][j] = spellID, after, dst
        if before > t then
            auraRow("SPELL_AURA_REFRESH", u, j, t, true, "inferred")
        else
            auraRow("SPELL_AURA_APPLIED", u, j, t, true, "inferred")
        end
    elseif before > t and auraExp[u][j] > 0 then
        auraExp[u][j] = 0
        auraRow("SPELL_AURA_REMOVED", u, j, t, true, "inferred") -- the cast removed it (a handler's removeBuff)
    end
end

L.OnTick(function(now)
    for u = 1, 2 do
        local exp = auraExp[u]
        for j = 1, #exp do
            if exp[j] > 0 and now >= exp[j] then
                exp[j] = 0
                auraRow("SPELL_AURA_REMOVED", u, j, now, false, "modelled")
            end
        end
    end
end)

--- Resource our cast at `t` gave us (a `now` handler's gain, Families/Now.lua): SPELL_ENERGIZE, back-dated to the cast.
function L.Energize(spellID, amount, powerType, maxPower, t)
    if type(spellID) ~= "number" or L.player == "" then
        return
    end
    local me, flags = L.player, L.PLAYER_FLAGS
    local r = L.Emit("SPELL_ENERGIZE", 18, t, true, "energize", "modelled", me, flags, me, flags)
    r[12], r[13], r[14], r[15], r[16], r[17], r[18] = spellID, "", 1, amount, 0, powerType, maxPower
end

--- (unit-registry spec §3.5) A white hit's row: SWING_DAMAGE at `t` (back-dated), from `src` to `dst`. Allocates
--- nothing.
function L.Swing(t, family, src, srcFlags, dst, dstFlags, amount, flag, offhand)
    local r = L.Emit("SWING_DAMAGE", 21, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
    r[12], r[13], r[14], r[15], r[16], r[17] = amount, 0, 1, 0, 0, 0
    r[18], r[19], r[20], r[21] = flag == "CRITICAL", flag == "GLANCING", flag == "CRUSHING", offhand == true
end

--- A spell's damage row (`sub`: SPELL_DAMAGE or SPELL_PERIODIC_DAMAGE) with `school` in slots 14 and 17.
function L.SpellHit(sub, t, family, src, srcFlags, dst, dstFlags, spellID, school, amount, flag)
    local r = L.Emit(sub, 24, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
    r[12], r[13], r[14], r[15], r[16], r[17], r[18] = spellID, "", school, amount, 0, school, 0
    r[19], r[20], r[21], r[22], r[23], r[24] = 0, 0, flag == "CRITICAL", false, false, false
end

--- An avoid's row: SWING_MISSED for a swing (`spellID` nil), else SPELL_MISSED with `school` in slot 14.
function L.Miss(t, family, src, srcFlags, dst, dstFlags, spellID, school, action, offhand)
    if spellID == nil then
        local r = L.Emit("SWING_MISSED", 15, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
        r[12], r[13], r[14], r[15] = action, offhand == true, 0, false
        return
    end
    local r = L.Emit("SPELL_MISSED", 18, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
    r[12], r[13], r[14], r[15], r[16], r[17], r[18] = spellID, "", school, action, false, 0, false
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
