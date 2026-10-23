-- Game/State/Sources/Units.lua
-- The unit registry (unit-registry spec §2): the only code that turns a unit token into a GUID for attribution. Token
-- indices are fixed at load (1 target, 2 focus, 3-42 nameplate1-40, 43 softenemy, 44 softinteract: Attackers.lua's
-- order); each binds to a unit slot by plain GUID. A slot lives while a token names it (LIVE), while an open ticket
-- pins it (Events/Tickets.lua: Hold/Release) and GRACE after its release; then GONE. Deaths: UNIT_DIED and
-- PLAYER_TARGET_DIED (plain), a poll's plain UnitIsDead (Dead), or, only when the client refused the death events, a
-- clear to none within KILL_TELL of a player FAILED. PARTY_KILL with our GUID marks our kill. UNIT_COMBAT on a table
-- token is resolved, deduplicated across one outcome's fan-out (plate, target, soft: a token never repeats within one
-- outcome) and dispatched once to each OnRow listener. Also the player's GUID and the SENT pin. Owns no belief.
-- Allocates nothing after load.
-- Credits: secret-value handling after Catnip's (Durts) research.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local U = {}
I.Units = U

U.UNIT_CAP, U.DUP_N, U.DUP_WINDOW, U.GRACE, U.KILL_TELL = 64, 4, 0.005, 0.1, 0.010
U.FREE, U.LIVE, U.GRACE_S, U.GONE, U.DEAD, U.RESET = 0, 1, 2, 3, 4, 0
local FREE, LIVE, GRACE_S, GONE, DEAD, RESET = 0, 1, 2, 3, 4, 0
local CAP, DUP_N, NTOK = U.UNIT_CAP, U.DUP_N, 44

local TOKENS, INDEX = { "target", "focus" }, {}
for k = 1, 40 do
    TOKENS[k + 2] = "nameplate" .. k
end
TOKENS[43], TOKENS[44] = "softenemy", "softinteract"
for i = 1, NTOK do
    INDEX[TOKENS[i]] = i
end
U.TOKENS, U.INDEX, U.NTOK = TOKENS, INDEX, NTOK

-- Per token index: the slot bound now (0 none), the slot bound before the last change, the change's time.
local tokUid, tokPrev, tokAt = {}, {}, {}
for i = 1, NTOK do
    tokUid[i], tokPrev[i], tokAt[i] = 0, 0, 0
end
-- Per unit slot (spec §2.1): GUID ("" free), state, tokens bound, last seen, last token left, tickets held, last ticket
-- released, our kill.
local uGUID, uState, uTokens, uSeen, uLeft, uHeld, uFree, uOurs = {}, {}, {}, {}, {}, {}, {}, {}
for u = 1, CAP do
    uGUID[u], uState[u], uTokens[u], uSeen[u] = "", FREE, 0, 0
    uLeft[u], uHeld[u], uFree[u], uOurs[u] = 0, 0, 0, false
end
U.uState = uState -- read-only: Snapshot and the specs

-- The dedupe ring (spec §2.4): DUP_N groups, each with the 44-token set of the tokens already seen in it.
local dT, dUid, dAct, dFlag, dAmount, dSchool, dTok = {}, {}, {}, {}, {}, {}, {}
for e = 1, DUP_N do
    dT[e], dUid[e], dAct[e], dFlag[e], dAmount[e], dSchool[e] = -1e9, 0, "", false, false, false
end
for k = 1, DUP_N * NTOK do
    dTok[k] = false
end
local dNext = 0

U.unresolved, U.dup, U.evicted, U.sweeps = 0, 0, 0, 0 -- sweeps: Tick scans that ran (spec §10)
U.deaths = { tell = 0, poll = 0, event = 0 }
U.player, U.sentCast, U.sentGUID = "", nil, nil
U.lastGUID = "" -- the GUID of the row being dispatched, "" between rows (read by the invariant sweep only)
U.Claims = nil -- set by Events/Tickets.lua: whether an open ticket on a unit owes a row of this act and school
U.Reused = nil -- set by Events/Tickets.lua: slot u takes another GUID (eviction): forget its per-slot state
local failT = -1e9
local ROW, GONE_FN = {}, {}

local function released(u)
    return uTokens[u] == 0 and uHeld[u] == 0
end

local function releaseT(u)
    return uLeft[u] > uFree[u] and uLeft[u] or uFree[u]
end

-- The earliest time a released GRACE slot can turn GONE (math.huge: none pending); Tick does nothing before it.
local nextDue = math.huge

local function schedule(u)
    if uState[u] == GRACE_S and released(u) then
        local due = releaseT(u) + U.GRACE
        if due < nextDue then
            nextDue = due
        end
    end
end

-- Whether rows may resolve to slot u at t (spec §2.1's table).
local function resolvable(u, t)
    local st = uState[u]
    if st == LIVE then
        return true
    elseif st == GRACE_S or st == DEAD then
        return not released(u) or t - releaseT(u) < U.GRACE
    end
    return false
end

local function notify(u, why, t)
    for k = 1, #GONE_FN do
        GONE_FN[k](u, uGUID[u], why, t)
    end
end

--- The slot holding `guid`, or 0. Allocates nothing.
function U.Find(guid)
    if guid == nil or guid == "" then
        return 0
    end
    for u = 1, CAP do
        if uGUID[u] == guid then
            return u
        end
    end
    return 0
end

-- A slot for guid (spec §2.6): its own, else a FREE one, else the released GONE or DEAD one seen longest ago, else a
-- released GRACE one seen longest ago. A LIVE or held slot is never taken. 0 only if all 64 are LIVE or held; the worst
-- case (44 tokens + 32 tickets) can reach it, and then the row counts unresolved, Pin still returns the GUID, no hold.
local function take(guid, t)
    local u = U.Find(guid)
    if u > 0 then
        return u
    end
    local best, bestRank = 0, 9
    for v = 1, CAP do
        local st, rank = uState[v], 9
        if st == FREE then
            rank = 1
        elseif released(v) and (st == GONE or st == DEAD) then
            rank = 2
        elseif released(v) and st == GRACE_S then
            rank = 3
        end
        if rank < bestRank or (rank < 9 and rank == bestRank and uSeen[v] < uSeen[best]) then
            best, bestRank = v, rank
        end
    end
    if best == 0 then
        return 0
    end
    if bestRank > 1 then
        U.evicted = U.evicted + 1
        if U.Reused then -- a DEAD or GRACE slot evicted without OnGone: its per-slot state must not carry over
            U.Reused(best)
        end
        for i = 1, NTOK do -- a token's previous unit is gone: never resolve its rows to the slot's next occupant
            if tokPrev[i] == best then
                tokPrev[i] = 0
            end
        end
    end
    uGUID[best], uState[best], uTokens[best], uSeen[best] = guid, GRACE_S, 0, t
    uLeft[best], uHeld[best], uFree[best], uOurs[best] = t, 0, 0, false
    return best
end

local function unbind(i, t)
    local u = tokUid[i]
    if u == 0 then
        return
    end
    tokPrev[i], tokUid[i], tokAt[i] = u, 0, t
    uTokens[u] = uTokens[u] - 1
    if uTokens[u] == 0 then
        uLeft[u] = t
        if uState[u] == LIVE then
            uState[u] = GRACE_S
        end
        schedule(u)
    end
end

local function bind(i, guid, t)
    local u = take(guid, t)
    if u == 0 then
        return 0
    end
    uSeen[u] = t
    if tokUid[i] == u then
        return u
    end
    unbind(i, t)
    tokUid[i], tokAt[i] = u, t
    uTokens[u] = uTokens[u] + 1
    if uState[u] ~= DEAD then
        uState[u] = LIVE
    end
    return u
end

-- Token i's live GUID (plain, non-empty), or nil.
local function read(api, i)
    local g = Plain(api, api.UnitGUID(TOKENS[i]))
    if type(g) == "string" and g ~= "" then
        return g
    end
end

local function rebind(api, i, t)
    local g = read(api, i)
    if g then
        bind(i, g, t)
    else
        unbind(i, t)
    end
end

local function kill(u, t, how)
    if u == 0 or uState[u] == DEAD or uState[u] == FREE then
        return
    end
    uState[u] = DEAD
    U.deaths[how] = U.deaths[how] + 1
    notify(u, DEAD, t)
end

--- (spec §2.3) The GUID a row on token index i at t is about, its slot, and whether token i was swapped away from a
--- still-resolvable unit. 1: the live read (rebinding a stale token first), except that a row the old unit's open
--- ticket owes (U.Claims) stays on the old unit; 2: while the live read is nil, the bound or previous slot while it
--- resolves; 3: nil (counted). Allocates nothing.
function U.Resolve(api, i, t, act, school)
    local g = read(api, i)
    if g then
        local u = tokUid[i]
        if u == 0 or uGUID[u] ~= g then
            u = bind(i, g, t)
            if u == 0 then -- every slot is bound or held: no slot for this GUID
                U.unresolved = U.unresolved + 1
                return nil, 0, false
            end
        end
        local p = tokPrev[i]
        local swapped = p > 0 and p ~= u and resolvable(p, t)
        if swapped and U.Claims and U.Claims(p, act, school) then
            return uGUID[p], p, true
        end
        return g, u, swapped
    end
    local u = tokUid[i] > 0 and tokUid[i] or tokPrev[i]
    if u > 0 and resolvable(u, t) then
        return uGUID[u], u, false
    end
    U.unresolved = U.unresolved + 1
    return nil, 0, false
end

-- Whether a resolved row is a duplicate of a group in the ring (spec §2.4): same slot (any slot when `swapped`), same
-- payload within DUP_WINDOW, and its token not yet in that group; a duplicate joins the group.
local function dupOf(i, t, u, act, fk, ak, sk, swapped)
    for e = 1, DUP_N do
        if
            t - dT[e] <= U.DUP_WINDOW
            and (dUid[e] == u or swapped)
            and dAct[e] == act
            and dFlag[e] == fk
            and dAmount[e] == ak
            and dSchool[e] == sk
        then
            local k = (e - 1) * NTOK + i
            if not dTok[k] then
                dTok[k] = true
                return true
            end
        end
    end
    return false
end

--- The registry's UNIT_COMBAT handler (by reference, for in-game CPU profiling). Allocates nothing.
function U.OnCombat(api, t, unit, act, flag, amount, school)
    local i = unit and INDEX[unit]
    if not i or type(act) ~= "string" then
        return -- player rows stay with Attackers and Player; targettarget, partyN, raidN, mouseover are echoes
    end
    local g, u, swapped = U.Resolve(api, i, t, act, school)
    if not g then
        return
    end
    local fk, ak, sk = flag or false, amount or false, school or false -- a secret slot (nil) never equals a plain one
    if dupOf(i, t, u, act, fk, ak, sk, swapped) then
        U.dup = U.dup + 1
        return
    end
    dNext = dNext % DUP_N + 1
    local e, base = dNext, (dNext - 1) * NTOK
    dT[e], dUid[e], dAct[e], dFlag[e], dAmount[e], dSchool[e] = t, u, act, fk, ak, sk
    for k = base + 1, base + NTOK do
        dTok[k] = false
    end
    dTok[base + i] = true
    uSeen[u] = t
    U.lastGUID = g
    for k = 1, #ROW do
        ROW[k](t, g, u, act, flag, amount, school)
    end
    U.lastGUID = ""
end
S.On("UNIT_COMBAT", nil, U.OnCombat)

S.On("PLAYER_TARGET_CHANGED", nil, function(api, t)
    local before = tokUid[1]
    rebind(api, 1, t)
    local stub = I.Events.STUB
    if tokUid[1] == 0 and before > 0 and t - failT <= U.KILL_TELL and stub.UNIT_DIED and stub.PLAYER_TARGET_DIED then
        kill(before, t, "tell") -- spec §2.5's fallback: the death events are refused
    end
end)
S.On("PLAYER_FOCUS_CHANGED", nil, function(api, t)
    rebind(api, 2, t)
end)
S.On("PLAYER_SOFT_ENEMY_CHANGED", nil, function(api, t)
    rebind(api, 43, t)
end)
S.On("PLAYER_SOFT_INTERACT_CHANGED", nil, function(api, t)
    rebind(api, 44, t)
end)
S.On("NAME_PLATE_UNIT_ADDED", nil, function(api, t, unit)
    local i = unit and INDEX[unit]
    if i then
        rebind(api, i, t)
    end
end)
S.On("NAME_PLATE_UNIT_REMOVED", nil, function(api, t, unit)
    local i = unit and INDEX[unit]
    if not i then
        return
    end
    local g = read(api, i) -- the removal still answers the plate's GUID (soft-targeting log)
    if g and (tokUid[i] == 0 or uGUID[tokUid[i]] ~= g) then
        bind(i, g, t)
    end
    unbind(i, t)
end)

S.On("UNIT_DIED", nil, function(api, t, guid)
    kill(U.Find(guid), t, "event")
end)
S.On("PLAYER_TARGET_DIED", nil, function(api, t)
    kill(tokUid[1], t, "event")
end)
S.On("PARTY_KILL", nil, function(api, t, killer, victim)
    if killer ~= nil and killer == U.player then
        local u = U.Find(victim)
        if u > 0 then
            uOurs[u] = true
        end
    end
end)
S.On("UNIT_SPELLCAST_FAILED", "player", function(api, t, unit)
    if unit == "player" then
        failT = t -- any castGUID, key spam included: read only by the fallback tell
    end
end)

--- (spec §2.7) Pins a commit: the target's live GUID, else the soft enemy's, else nil. Allocates nothing.
function U.Pin(api, t)
    local g = read(api, 1)
    if g then
        bind(1, g, t)
        return g
    end
    g = read(api, 43)
    if g then
        bind(43, g, t)
    end
    return g
end

S.On("UNIT_SPELLCAST_SENT", "player", function(api, t, unit, _, castGUID)
    if unit == "player" then
        U.sentCast, U.sentGUID = castGUID, U.Pin(api, t)
    end
end)

--- The GUID our cast `castGUID` was SENT to (spec §1 row 3: a cast keeps its SENT target), or nil.
function U.Sent(castGUID)
    if castGUID ~= nil and castGUID == U.sentCast then
        return U.sentGUID
    end
end

--- Moves each released GRACE slot past GRACE to GONE (OnGone GONE). Every OnUpdate; returns at once until the
--- earliest pending expiry (spec §10). Allocates nothing.
function U.Tick(now)
    if now < nextDue then
        return
    end
    U.sweeps = U.sweeps + 1
    nextDue = math.huge
    for u = 1, CAP do
        if uState[u] == GRACE_S and released(u) then
            if now - releaseT(u) >= U.GRACE then
                uState[u] = GONE
                notify(u, GONE, now)
            else
                schedule(u)
            end
        end
    end
end

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    for u = 1, CAP do
        if uState[u] ~= FREE and uTokens[u] == 0 then
            notify(u, RESET, t)
            uGUID[u], uState[u], uHeld[u], uOurs[u] = "", FREE, 0, false
        end
    end
    for i = 1, NTOK do
        if tokPrev[i] > 0 and uState[tokPrev[i]] == FREE then
            tokPrev[i] = 0
        end
    end
    for e = 1, DUP_N do
        dT[e] = -1e9
    end
    failT = -1e9
end)

local function readPlayer(api)
    U.player = Plain(api, api.UnitGUID("player")) or ""
    I.Log.player = U.player
end
S.On("PLAYER_ENTERING_WORLD", nil, readPlayer)
S.OnStart(function(api, t)
    readPlayer(api)
    rebind(api, 1, t)
    rebind(api, 2, t)
    rebind(api, 43, t)
    rebind(api, 44, t)
    I.Log.OnTick(U.Tick) -- CombatLog.lua loads after the Sources: its lane exists from Start
end)

--- The GUID bound to token index i, "" none.
function U.Bound(i)
    local u = tokUid[i]
    return u > 0 and uGUID[u] or ""
end
--- The slot bound to token index i, 0 none.
function U.Uid(i)
    return tokUid[i]
end
--- Slot u's GUID, "" none.
function U.GUID(u)
    return u > 0 and uGUID[u] or ""
end
--- Whether slot u is LIVE or GRACE.
function U.Alive(u)
    return u > 0 and (uState[u] == LIVE or uState[u] == GRACE_S)
end
--- Whether slot u is DEAD.
function U.IsDead(u)
    return u > 0 and uState[u] == DEAD
end
--- Whether slot u died to our kill (PARTY_KILL with our GUID).
function U.Ours(u)
    return u > 0 and uOurs[u]
end
--- Whether slot u is the current target, or (no target) the cleared target's slot while it still resolves at t.
function U.IsTarget(u, t)
    if u == 0 then
        return false
    elseif tokUid[1] > 0 then
        return u == tokUid[1]
    end
    return u == tokPrev[1] and resolvable(u, t)
end
--- Marks slot u DEAD from a poll's plain UnitIsDead (Target poll 4, Nameplates poll 5).
function U.Dead(u, t)
    kill(u, t, "poll")
end
--- An open ticket pins slot u (Events/Tickets.lua).
function U.Hold(u)
    if u > 0 then
        uHeld[u] = uHeld[u] + 1
    end
end
--- A ticket pinned to slot u closed at t.
function U.Release(u, t)
    if u > 0 and uHeld[u] > 0 then
        uHeld[u] = uHeld[u] - 1
        if uHeld[u] == 0 then
            uFree[u] = t
            schedule(u)
        end
    end
end
--- Load-time: `fn(t, guid, uid, act, flag, amount, school)` for every resolved, deduplicated row, in registration order.
function U.OnRow(fn)
    ROW[#ROW + 1] = fn
end
--- Load-time: `fn(uid, guid, why, t)`, why GONE 3, DEAD 4 or RESET 0.
function U.OnGone(fn)
    GONE_FN[#GONE_FN + 1] = fn
end

--- Snapshot's line (allocates; debugging only).
I.OnSnapshot(function(out)
    local n = { [LIVE] = 0, [GRACE_S] = 0, [GONE] = 0, [DEAD] = 0 }
    for u = 1, CAP do
        local st = uState[u]
        if st ~= FREE then
            n[st] = n[st] + 1
        end
    end
    local d = U.deaths
    out[#out + 1] = string.format(
        "units live=%d grace=%d gone=%d dead=%d unresolved=%d dup=%d evicted=%d deaths tell=%d poll=%d event=%d",
        n[LIVE],
        n[GRACE_S],
        n[GONE],
        n[DEAD],
        U.unresolved,
        U.dup,
        U.evicted,
        d.tell,
        d.poll,
        d.event
    )
end)
