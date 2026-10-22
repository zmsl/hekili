-- Game/Events/Tickets.lua
-- The ticket pool (unit-registry spec §3): one record per commit of ours, preallocated (TICKETS = 16). A ticket opens
-- for every commit: every PLAYER_SWING (MELEE), every hard cast at its START (committed, pinned at SENT, armed at its
-- success), every other success, mapped (its ability's kind, Families/Expect.lua) or not (UNMAPPED); NONE closes at
-- once. Rows are consumed online (Events/Rows.lua) by the order of spec §3.4: candidates on the row's GUID, by pass
-- (1 narrow, 2 widened, 3 hard), the least expected closure first, so FIFO per queue falls out. Closes are counted
-- once each (spec §3.6). The matching rules live in Events/Kinds.lua and Events/Melee.lua; this file owns records,
-- order and closes. Pure: no client read. Allocates nothing after load.

local _, ns = ...
local I = ns.VirtualStateInternal
local A = I.ab
local X, U = I.Expect, I.Units

local T = {}
I.Tickets = T
T.CAP = 16
T.FREE, T.COMMITTED, T.OPEN, T.PROV = 0, 1, 2, 3
local CAP, COMMITTED, OPEN, PROV = T.CAP, T.COMMITTED, T.OPEN, T.PROV
local NONE, MELEE, UNMAPPED, ANY = X.NONE, X.MELEE, X.UNMAPPED, X.ANY
T.COMMIT_HOLD = 60 -- s: a committed cast with no stop event closes as stopped (a lost STOP must not pin a unit)

-- Per ticket (spec §3.1): state, kind, ability index (0 swing or unmapped), x (hand or spell ID), the pinned GUID and
-- its registry slot, the school mask (ANY -1, 0 none), rows owed, the anchor, the expiry, the window length, a main
-- reference, a provisional avoid's LR and action, the castGUID of a committed cast, rows paid, first swing of combat.
T.state, T.kind, T.ab, T.x, T.guid, T.uid, T.school, T.owed = {}, {}, {}, {}, {}, {}, {}, {}
T.at, T.hi, T.w, T.ref, T.lr, T.avoid, T.cast, T.done, T.first = {}, {}, {}, {}, {}, {}, {}, {}, {}
local state, kind, ab, x, guid, uid, school, owed = T.state, T.kind, T.ab, T.x, T.guid, T.uid, T.school, T.owed
local at, hi, w, ref, lr, avoid, cast, done, first = T.at, T.hi, T.w, T.ref, T.lr, T.avoid, T.cast, T.done, T.first
for i = 1, CAP do
    state[i], kind[i], ab[i], x[i], guid[i], uid[i], school[i], owed[i] = 0, 0, 0, 0, "", 0, ANY, 0
    at[i], hi[i], w[i], ref[i], lr[i], avoid[i], cast[i], done[i], first[i] = 0, 0, 0, 0, 0, "", "", 0, false
end
-- Per ticket: a row it matched past its own frame was absorbed as nobody's (Rows: an UNMAPPED window), so its
-- missing row may have been that one: its expiry counts `expired`, not `lost`.
T.excused = {}
for i = 1, CAP do
    T.excused[i] = false
end

T.opened = 0
T.closed = {
    none = 0,
    paid = 0,
    signal = 0,
    replaced = 0,
    refreshed = 0,
    stopped = 0,
    expired = 0,
    lost = 0,
    dead = 0,
    gone = 0,
    ended = 0,
    overflow = 0,
    unpinned = 0,
    provisional = 0,
}
T.paid, T.lost = {}, {} -- by kind: tickets paid out, rows lost
for k = 0, 7 do
    T.paid[k], T.lost[k] = 0, 0
end
T.ours, T.foreign, T.absorbed, T.divergent, T.bandRejected, T.aoeOther = 0, 0, 0, 0, 0, 0
T.onExpire, T.onPay = nil, nil
-- FLIGHT (spec §3.3.1): per ticket its speed (yd/s) and hard window length H = rMax / speed + TOL.
T.TOL, T.CLOSE, T.LAG_CAP = 0.15, 7, 16
T.speed, T.H = {}, {}
for i = 1, CAP do
    T.speed[i], T.H[i] = 0, 0
end
-- The learned flight lag per (GUID, speed): the last observed lag, its spread, the time and count of observations.
-- Survive combat end (a GUID does not return); reset at load.
T.lagGUID, T.lagSpeed, T.lagE, T.lagSpr, T.lagT, T.lagN = {}, {}, {}, {}, {}, {}
for r = 1, T.LAG_CAP do
    T.lagGUID[r], T.lagSpeed[r], T.lagE[r], T.lagSpr[r], T.lagT[r], T.lagN[r] = "", 0, 0, 0, 0, 0
end

--- The lag record of (g, v), or 0.
function T.LagOf(g, v)
    for r = 1, T.LAG_CAP do
        if T.lagGUID[r] == g and T.lagSpeed[r] == v then
            return r
        end
    end
    return 0
end

--- A clean flight payment's lag teaches (g, v)'s record (a full pool gives the oldest way). A new record's spread
--- starts at TOL / 2, so its first narrow band is TOL each side. Allocates nothing.
function T.Learn(g, v, lag, t)
    local r = T.LagOf(g, v)
    if r == 0 then
        r = 1
        for q = 1, T.LAG_CAP do
            if T.lagGUID[q] == "" then
                r = q
                break
            elseif T.lagT[q] < T.lagT[r] then
                r = q
            end
        end
        T.lagGUID[r], T.lagSpeed[r], T.lagE[r], T.lagSpr[r], T.lagN[r] = g, v, lag, T.TOL / 2, 0
    end
    local Stats = I.Stats -- the one EMA: the spread moves by 0.25 x (1.2533 |lag - last| - spread), [0.02, 0.4]
    local s = Stats.Ema(T.lagSpr[r], 0, 1.2533 * math.abs(lag - T.lagE[r]), 0.25, 0)
    T.lagSpr[r] = Stats.Clamp(s, Stats.SPR_LO, Stats.SPR_HI)
    T.lagE[r], T.lagT[r], T.lagN[r] = lag, t, T.lagN[r] + 1 -- the last lag: a closing mob makes it shrink
end

-- Per ability: the amount band of its own clean wounds (a crit halved), declared abilities only (spec §3.4); reset at
-- each build (ability indices change with the spec).
T.bandLo, T.bandHi, T.bandN = {}, {}, {}
I.OnBuild(function()
    for a = 1, A.n do
        T.bandLo[a], T.bandHi[a], T.bandN[a] = 0, 0, 0
    end
end)

local function teach(a, amount, flag) -- a new low or high takes it, else each end creeps toward it by 0.05
    I.Bands.Learn(T.bandLo, T.bandHi, T.bandN, a, I.Bands.Normalise(amount, flag, "ours"), 0.05)
end
T.latestT = -1 -- the latest success of a mapped ability (Families/Now.lua's latest cast, whose avoid undoes it)
-- The pending swing (owner ruling 2026-10-22: the ticket is its single owner): each hand's latest swing ticket and its
-- time; a swing is pending while that ticket is open and within the hand's pending window. PEND_CAP: Resources'
-- drift guard, moved here unchanged (Melee's learn can widen the landing window to about 2.7 s main, 3.2 s off).
T.PEND_CAP = 1.0
T.lastSwing, T.lastSwingT = { 0, 0 }, { 0, 0 }
-- A strike whose success came before its swing: the open STRIKE ticket that swallows the next main-hand swing.
local strikeWait, strikeWaitT = 0, 0

--- Closes ticket i at t for `why` (a T.closed key) and releases its unit. Allocates nothing.
function T.Close(i, t, why)
    if state[i] == 0 then
        return
    end
    state[i], lr[i], avoid[i] = 0, 0, ""
    T.closed[why] = T.closed[why] + 1
    U.Release(uid[i], t)
end
local close = T.Close

--- A free ticket, else the oldest gives way (spec §3.6: `overflow`, unemitted). Allocates nothing.
function T.Slot(t)
    local oldest = 1
    for i = 1, CAP do
        if state[i] == 0 then
            return i
        elseif at[i] < at[oldest] then
            oldest = i
        end
    end
    close(oldest, t, "overflow")
    return oldest
end

local function fill(i, k, a, xx, g, t)
    state[i], kind[i], ab[i], x[i], guid[i], uid[i] = OPEN, k, a, xx, g, U.Find(g)
    school[i], owed[i], at[i], hi[i], w[i] = ANY, 1, t, t, 0
    ref[i], lr[i], avoid[i], cast[i], done[i], first[i], T.excused[i] = 0, 0, "", "", 0, false, false
    U.Hold(uid[i])
    T.opened = T.opened + 1
end

-- Anchors spell ticket i at its success t and sets its window by its kind (spec §3.3).
local function arm(i, t)
    local k = kind[i]
    state[i], at[i] = OPEN, t
    if k == X.FRAME or k == X.STRIKE then
        local cw = I.Melee.CAST_WINDOW
        w[i] = I.Log.LandWindow(1)
        hi[i] = t + (w[i] > cw and w[i] or cw)
    elseif k == X.FLIGHT then
        local a = ab[i]
        local r = A.rMax[a] > 0 and A.rMax[a] or 40 -- 0: no range read; 40 yd covers every spell range
        T.speed[i] = A.velocity[a]
        T.H[i] = r / T.speed[i] + T.TOL -- Expect requires a positive travel velocity
        hi[i] = t + T.H[i]
    elseif k == UNMAPPED then
        owed[i], hi[i] = 0, t + I.Log.UNMAPPED_WINDOW
    end
end

--- A swing of `hand` at t pinned to `g` with window `win`; an off hand's main reference `mref`; `retry`: a
--- retraction's re-open (I.CreditVerdict), which is not the hand's latest swing. Allocates nothing.
function T.OpenSwing(t, hand, g, win, mref, isFirst, retry)
    local i = T.Slot(t)
    fill(i, MELEE, 0, hand, g, t)
    school[i], w[i], hi[i], ref[i], first[i] = 1, win, t + win, mref or 0, isFirst == true
    if not retry then -- a retraction's re-open is not the hand's latest swing (pendT stayed 0 after a credit)
        T.lastSwing[hand], T.lastSwingT[hand] = i, t
    end
    return i
end

--- Hand's pending window: its landing window, capped at PEND_CAP. Allocates nothing.
function T.PendingWindow(hand)
    local lw = I.Log.LandWindow(hand)
    return lw < T.PEND_CAP and lw or T.PEND_CAP
end

--- The time of hand's latest swing while its ticket is open (not credited, retracted away or expired) and t is within
--- its pending window; else 0 (VS.SwingPending's swing). A strike's own swing (T.Swallows: lastSwing 0) has no ticket
--- and stays pending through its window, as pendT held it (Fury L24 agreement 0.960 with it, 0.953 without). Allocates
--- nothing.
function T.SwingPending(hand, t)
    local i, at0 = T.lastSwing[hand], T.lastSwingT[hand]
    if at0 == 0 or t > at0 + T.PendingWindow(hand) then
        return 0
    elseif i == 0 then
        return at0
    elseif state[i] < OPEN or kind[i] ~= MELEE or at[i] ~= at0 then
        return 0
    end
    return at0
end

--- Strike ticket i's success came before its swing: it swallows the next main-hand swing within STRIKE_WINDOW.
function T.OpenStrikeWait(i)
    strikeWait, strikeWaitT = i, at[i]
end

--- Whether a main-hand swing at t is a waiting strike's own (consumed either way). Its ticket may be paid already (its
--- row can come before its swing in that frame); `at` unchanged says the slot is still that strike's. Allocates nothing.
function T.Swallows(t)
    local i = strikeWait
    strikeWait = 0
    if i > 0 and kind[i] == X.STRIKE and at[i] == strikeWaitT and t - strikeWaitT <= I.Melee.STRIKE_WINDOW then
        T.lastSwing[1], T.lastSwingT[1] = 0, t -- the main hand's latest swing, the strike's own (T.SwingPending)
        return true
    end
    return false
end

--- A success at t of ability `a` (0: unmapped) pinned to `g`: its ticket, armed; 0 for NONE (counted). Allocates
--- nothing.
function T.OpenCast(t, a, spellID, g)
    local k = a > 0 and A.expKind[a] or UNMAPPED
    if a > 0 then
        T.latestT = t
    end
    if k == NONE then
        T.opened = T.opened + 1
        T.closed.none = T.closed.none + 1
        return 0
    end
    local i = T.Slot(t)
    fill(i, k, a, spellID, k == UNMAPPED and "" or g, t)
    if a > 0 then
        school[i] = A.school[a]
    end
    arm(i, t)
    return i
end

--- A cast of `a` SENT at t to `g` (spec decision 10): committed until its success (T.Arm) or its stop (T.Stop). SENT
--- names no cast time, so an instant commits too and its success arms it in the same frame. 0 for NONE. Allocates
--- nothing.
function T.Commit(t, a, spellID, g, castGUID)
    if A.expKind[a] == NONE or castGUID == nil then
        return 0
    end
    local i = T.Slot(t)
    fill(i, A.expKind[a], a, spellID, g, t)
    school[i], cast[i], state[i], hi[i] = A.school[a], castGUID, COMMITTED, t + T.COMMIT_HOLD
    return i
end

--- Arms the committed ticket of `castGUID` at its success t; its index, or 0 when none claims it.
function T.Arm(castGUID, t)
    if castGUID == nil then
        return 0
    end
    for i = 1, CAP do
        if state[i] == COMMITTED and cast[i] == castGUID then
            arm(i, t)
            T.latestT = t
            return i
        end
    end
    return 0
end

--- Closes the committed ticket of `castGUID` uncounted toward lost (its FAILED or INTERRUPTED).
function T.Stop(castGUID, t)
    for i = 1, CAP do
        if state[i] == COMMITTED and castGUID ~= nil and cast[i] == castGUID then
            close(i, t, "stopped")
        end
    end
end

--- (spec §3.4 steps 2-4, owner ruling 2026-10-22) The candidate for a row at t on `g` at pass `p`: among the open
--- tickets on `g` that accept the row and whose band at p holds t, those whose learned amount band accepts it first
--- (K.Accepts' second answer), then those with no band or an unlearned one; within each group the least expected
--- closure. Also how many matched. Allocates nothing.
function T.Pick(t, g, p, act, flag, amount, sch, isAvoid)
    local K = I.Kinds
    local best, bestE, bestBanded, n, refused = 0, math.huge, false, 0, false
    for i = 1, CAP do
        if state[i] >= OPEN and guid[i] == g then
            local ok, banded = K.Accepts(i, act, flag, amount, sch, isAvoid)
            refused = refused or (not ok and banded == true)
            if ok then
                local lo, h, e = K.Band(i, p, t, isAvoid, act, sch)
                if lo and t >= lo - 1e-9 and t <= h + 1e-9 then
                    n, banded = n + 1, banded == true
                    if (banded and not bestBanded) or (banded == bestBanded and e < bestE) then
                        best, bestE, bestBanded = i, e, banded
                    end
                end
            end
        end
    end
    if refused and p == 1 then -- once per row: every row starts at pass 1
        T.bandRejected = T.bandRejected + 1
    end
    return best, n
end

--- (spec §4.2, decision 25) Whether a row Pick gave to p at pass `pass` with a second candidate is divergent: another
--- candidate implies a different state. An avoid: one of the candidates is the latest cast (Now undoes only that one's
--- effects: hit vs miss). A crit: a candidate of another ability, either running an `onCrit`. Allocates nothing.
function T.Divergent(p, t, pass, act, flag, amount, sch, isAvoid)
    local K, oc = I.Kinds, A.onCrit
    for i = 1, CAP do
        if state[i] >= OPEN and guid[i] == guid[p] and K.Accepts(i, act, flag, amount, sch, isAvoid) then
            local lo, h = K.Band(i, pass, t, isAvoid, act, sch)
            if lo and t >= lo - 1e-9 and t <= h + 1e-9 then
                if isAvoid and at[i] >= T.latestT then
                    return true
                elseif not isAvoid and ab[i] ~= ab[p] and oc and (oc[ab[i]] or oc[ab[p]]) then
                    return true
                end
            end
        end
    end
    return false
end

--- Ticket i paid by a row at t (`clean`: the only candidate at its pass): one row fewer owed; closed when none is.
function T.Pay(i, t, isAvoid, amount, flag, clean, pass)
    if T.onPay then
        T.onPay(i, t, pass)
    end
    local k, a = kind[i], ab[i]
    -- Any clean pass teaches the lag, pass 3 included (spec §3.3.1 says a or b only, but with no record a ticket is a
    -- candidate at pass 3 alone, so no record would ever be made: controller ruling, Task 19 amends the spec).
    if clean and k == X.FLIGHT then
        T.Learn(guid[i], T.speed[i], t - at[i], t)
    end
    if clean and not isAvoid and a > 0 and A.expDeclared[a] and (k == X.FRAME or k == X.FLIGHT or k == X.STRIKE) then
        teach(a, amount, flag)
    end
    done[i], owed[i] = done[i] + 1, owed[i] - 1
    if owed[i] <= 0 then
        T.paid[kind[i]] = T.paid[kind[i]] + 1
        close(i, t, "paid")
    end
end

--- A swing ticket holds an avoid provisionally (spec §3.7): it is emitted at its close unless a wound overtakes it.
function T.Provisional(i, lri, act)
    state[i], lr[i], avoid[i] = PROV, lri, act
end

--- Whether an UNMAPPED ticket's window holds t.
function T.Unmapped(t)
    for i = 1, CAP do
        if state[i] >= OPEN and kind[i] == UNMAPPED and t <= hi[i] then
            return true
        end
    end
    return false
end

--- (registry hook, spec §2.3) Whether an open ticket on slot u still owes a row of `act` and school `sch`.
function T.Claims(u, act, sch)
    for i = 1, CAP do
        if state[i] >= OPEN and uid[i] == u and owed[i] > 0 and kind[i] ~= UNMAPPED then
            if act ~= "WOUND" or school[i] == ANY or school[i] == sch then
                return true
            end
        end
    end
    return false
end
U.Claims = T.Claims

-- Why ticket i closes at its window's end (spec §3.6).
local function expiry(i)
    local st, k = state[i], kind[i]
    if st == COMMITTED then
        return "stopped"
    elseif st == PROV then
        return "provisional"
    elseif k == UNMAPPED or owed[i] <= 0 then
        return "expired"
    elseif guid[i] == "" then
        return "unpinned"
    elseif school[i] == ANY or school[i] == 0 then
        return "expired"
    elseif U.IsDead(uid[i]) then
        if U.Ours(uid[i]) then
            T.ours = T.ours + 1
        end
        return "dead"
    elseif T.excused[i] then
        return "expired"
    end
    T.lost[k] = T.lost[k] + owed[i]
    return "lost"
end

--- Closes every ticket whose window ended by `now`, after Rows' T.onExpire (a swing's row). Every OnUpdate.
function T.Expire(now)
    for i = 1, CAP do
        if state[i] ~= 0 and now > hi[i] then
            if state[i] ~= COMMITTED and T.onExpire then
                T.onExpire(i, now)
            end
            close(i, now, expiry(i))
        end
    end
end

--- Combat end (spec §3.6): every ticket closes, emitting nothing, counted `ended`.
function T.EndCombat(t)
    for i = 1, CAP do
        close(i, t, "ended")
    end
    strikeWait = 0
    T.lastSwingT[1], T.lastSwingT[2] = 0, 0
end

-- A unit gone (released and past GRACE, so normally no ticket pins it): any ticket still on it closes as at expiry.
U.OnGone(function(u, g, why, t)
    if why ~= U.GONE then
        return
    end
    for i = 1, CAP do
        if state[i] ~= 0 and uid[i] == u then
            if state[i] ~= COMMITTED and T.onExpire then
                T.onExpire(i, t)
            end
            close(i, t, "gone")
        end
    end
end)

--- Snapshot's line (allocates; debugging only).
I.OnSnapshot(function(out)
    local c, open = T.closed, 0
    for i = 1, CAP do
        open = open + (state[i] ~= 0 and 1 or 0)
    end
    local lost = 0
    for k = 0, 7 do
        lost = lost + T.lost[k]
    end
    out[#out + 1] = string.format(
        "tickets open=%d none=%d paid=%d lost=%d expired=%d refreshed=%d foreign=%d unpinned=%d dead=%d gone=%d bandRejected=%d divergent=%d overflow=%d absorbed=%d ours=%d aoeOther=%d",
        open,
        c.none,
        c.paid,
        lost,
        c.expired,
        c.refreshed,
        T.foreign,
        c.unpinned,
        c.dead,
        c.gone,
        T.bandRejected,
        T.divergent,
        c.overflow,
        T.absorbed,
        T.ours,
        T.aoeOther
    )
end)
