-- Game/Events/Tickets.lua
-- The ticket pool (unit-registry spec §3): one record per commit of ours, preallocated (TICKETS = 32). A ticket opens
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
T.CAP = 32 -- multi-dotting: 3 targets x 4 dots = 12 TICKS, plus swings, a bolt in flight, the next commit
T.FREE, T.COMMITTED, T.OPEN, T.PROV, T.TENT, T.ASSUMED = 0, 1, 2, 3, 4, 5
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
-- Per ticket: when it closed paid (0: open, or closed for another reason); its other fields stay until the slot is
-- reused, so DueElsewhere still sees a frame ticket our target's row paid first (K18).
T.paidAt = {}
local paidAt = T.paidAt
for i = 1, CAP do
    paidAt[i] = 0
end
-- Per ticket (attribution-recovery decision 48): a payment outside the narrow band, before it passed, is provisional:
-- the ticket stays TENT (owed 0, its unit held) until `fin`; the row that paid it (time, action, flag, amount, school,
-- clean) to teach from at `fin` or to re-label foreign; a held observation (1 Obs.Crit, 2 Obs.Avoided); the swing's
-- credit record (0 none).
T.fin, T.rowT, T.rowAct, T.rowFlag, T.rowAmt, T.rowSch, T.rowClean, T.held, T.rec = {}, {}, {}, {}, {}, {}, {}, {}, {}
for i = 1, CAP do
    T.fin[i], T.rowT[i], T.rowAct[i], T.rowFlag[i], T.rowAmt[i], T.rowSch[i] = 0, 0, "", "", 0, 0
    T.rowClean[i], T.held[i], T.rec[i] = false, 0, 0
end
-- The EARLY variant (measured, Task 2; off): a learned flight also takes a row before its narrow band, anywhere in its
-- hard window, at pass 5 (after pass (d)), always provisional (TENT). A load-time constant; the test loaders set it from
-- TA_EARLY=1.
T.EARLY = false
-- Per ticket (attribution-recovery decision 51, owner ruling 2026-10-23: the expectation at expiry): a firm
-- retraction's re-open (no expectation at its lost close) and whether it was assumed (T.Assume: a provider's HIT).
-- Also: a white avoid nobody took (foreign or absorbed) fell in its window, maybe its own: no expectation at its lost
-- close (fix round 2: the bear and decay gates; their lost swings were avoided in truth).
T.retry, T.assumed, T.avoidSeen = {}, {}, {}
for i = 1, CAP do
    T.retry[i], T.assumed[i], T.avoidSeen[i] = false, false, false
end
T.onAssume, T.onLost = nil, nil
T.replaced = 0 -- every replacement of a provisional payment by a narrow-band row, re-offered or not (not a close)
T.onFinal, T.onReplace = nil, nil -- Rows' hooks: a TENT ticket final, a TENT ticket's row replaced

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
    confirmed = 0,
    refunded = 0,
    assumed = 0,
}
T.paid, T.lost = {}, {} -- by kind: tickets paid out, rows lost
for k = 0, 7 do
    T.paid[k], T.lost[k] = 0, 0
end
T.ours, T.foreign, T.absorbed, T.divergent, T.bandRejected, T.aoeOther = 0, 0, 0, 0, 0, 0
T.overpaid = 0 -- payments past `owed` (never: the invariant sweep asserts 0)
T.onExpire, T.onPay = nil, nil
-- FLIGHT (spec §3.3.1): per ticket its speed (yd/s) and hard window length H = rMax / speed + TOL. CLOSE: 7 yd/s, a
-- mob's run speed (a hard cast cannot move). The lag falls because the mob closes between anchors and again during
-- the flight (it meets the projectile at speed + CLOSE: Kinds.Flight's bound); capture b's (2026-10-22) six closing
-- rows (16017, 38127, 39145, 40413, 69926, 72780) and capture a's 5367 crit land inside that bound.
T.TOL, T.CLOSE, T.LAG_CAP = 0.15, 7, 16
-- The crowd gate (owner ruling 2026-10-22, Task 12): a flight's widened band takes the running-mob bound's early edge
-- only while no foreign row of its school reached its unit in the last CROWD s (named cause: the detection suite's
-- party and busy cells doubled false credit under the bound, K4 party 13.2 -> 28.9 per 100, while capture b's
-- running-mob rows need it in solo). Per unit slot x school (7): the last foreign row's time.
T.CROWD = 5
local NSCH = 7
T.SCHOOL_IX = { [1] = 1, [2] = 2, [4] = 3, [8] = 4, [16] = 5, [32] = 6, [64] = 7 }
local foreignT = {}
for k = 1, U.UNIT_CAP * NSCH do
    foreignT[k] = -1e9
end

--- A row nobody of ours took (Rows' foreign) on slot u with school `sch` at t. Allocates nothing.
function T.Foreign(u, sch, t)
    local x = T.SCHOOL_IX[sch]
    if u > 0 and x then
        foreignT[(u - 1) * NSCH + x] = t
    end
end

--- Whether a foreign row of school mask `s` (ANY: any school; 0: none) reached slot u within CROWD before t.
function T.Crowded(u, s, t)
    if u <= 0 or s == 0 then
        return false
    end
    local base = (u - 1) * NSCH
    for x = 1, NSCH do
        if (s == X.ANY or T.SCHOOL_IX[s] == x) and t - foreignT[base + x] <= T.CROWD then
            return true
        end
    end
    return false
end

local function clearForeign(u)
    for x = 1, NSCH do
        foreignT[(u - 1) * NSCH + x] = -1e9
    end
end
U.Reused = clearForeign -- an evicted slot's next GUID starts with no crowd
T.speed, T.H = {}, {}
for i = 1, CAP do
    T.speed[i], T.H[i] = 0, 0
end
-- TICKS and CHANNEL (spec §3.3): the period, the schedule's anchor (the application), a widening while a velocity
-- TICKS ticket has no learned lag, the link between a direct ticket (j) and its composed TICKS ticket (-1), and the
-- last paid tick's amount (0 before the first: Kinds' soft band).
T.TICK_BAND = 0.1
T.period, T.anchor, T.wide, T.link, T.tickAmt = {}, {}, {}, {}, {}
for i = 1, CAP do
    T.period[i], T.anchor[i], T.wide[i], T.link[i], T.tickAmt[i] = 0, 0, 0, 0, 0
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
-- Per ability: its ticking aura's spell ID (0 none), which CombatLog's removal rows name (T.AuraGone).
T.tickAuraId = {}
I.OnBuild(function()
    for a = 1, A.n do
        T.bandLo[a], T.bandHi[a], T.bandN[a] = 0, 0, 0
        local au = A.tickAura[a]
        T.tickAuraId[a] = au and tonumber(rawget(au, "id")) or 0
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
    paidAt[i] = 0
    if why == "paid" then
        paidAt[i] = t
    end
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
    T.held[i], T.rec[i] = 0, 0
    T.retry[i], T.assumed[i], T.avoidSeen[i] = false, false, false
    T.period[i], T.anchor[i], T.wide[i], T.link[i], T.speed[i], T.H[i], T.tickAmt[i] = 0, t, 0, 0, 0, 0, 0
    U.Hold(uid[i])
    T.opened = T.opened + 1
end

-- TICKS ticket i of ability a: its aura's count of rows owed (read now, Families/Expect.lua's X.Tick), tick k at
-- app + k x period +- (TICK_BAND + wide). The count at any time is done + owed.
local function schedule(i, a, app, wide)
    local period, count = X.Tick(a)
    T.period[i], owed[i], T.anchor[i], T.wide[i] = period, count, app, wide
    hi[i] = app + count * period + T.TICK_BAND + wide
end

-- A new application of a on g, confirmed by a row (the direct hit, or an alone schedule's first tick), closes its older
-- TICKS ticket as refreshed (unpaid rows not lost; decision 37): a recast that is avoided leaves the old one open.
local function refresh(a, g, t, except)
    for j = 1, CAP do
        if j ~= except and state[j] >= OPEN and kind[j] == X.TICKS and ab[j] == a and guid[j] == g then
            close(j, t, "refreshed")
        end
    end
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
    elseif k == X.TICKS then -- alone (a pure DoT): anchored at the success, after the flight with a velocity
        local a = ab[i]
        local v = A.velocity[a]
        if v > 0 then
            local rm = A.rMax[a] > 0 and A.rMax[a] or 40
            T.speed[i], T.H[i] = v, rm / v + T.TOL
            local r = T.LagOf(guid[i], v)
            if r > 0 then
                schedule(i, a, t + T.lagE[r], 0)
            else
                schedule(i, a, t + rm / v / 2, rm / v / 2) -- decision 36: widened until the first tick
            end
        else
            schedule(i, a, t, 0)
        end
    elseif k == X.CHANNEL then -- U9 deferred: owes rows until its stop
        T.period[i], owed[i], hi[i] = (X.Tick(ab[i])), math.huge, math.huge
    elseif k == UNMAPPED then
        owed[i], hi[i] = 0, t + I.Log.UNMAPPED_WINDOW
    end
end

-- A direct ticket whose aura is a debuff dot (A.ticking) opens its TICKS ticket on the same GUID (decision 35),
-- anchored at the success (widened by the flight's hard window for a projectile) until the direct row re-anchors it.
local function compose(i, t)
    local a = ab[i]
    if a == 0 or not A.ticking[a] or (kind[i] ~= X.FRAME and kind[i] ~= X.FLIGHT) then
        return
    end
    local j = T.Slot(t)
    fill(j, X.TICKS, a, x[i], guid[i], t)
    school[j], T.link[j], T.link[i] = school[i], -1, j
    schedule(j, a, t, kind[i] == X.FLIGHT and T.H[i] or 0)
end

--- A swing of `hand` at t pinned to `g` with window `win`; an off hand's main reference `mref`; `retry`: a
--- retraction's re-open (I.CreditVerdict), which is not the hand's latest swing. Allocates nothing.
function T.OpenSwing(t, hand, g, win, mref, isFirst, retry)
    local i = T.Slot(t)
    fill(i, MELEE, 0, hand, g, t)
    school[i], w[i], hi[i], ref[i], first[i] = 1, win, t + win, mref or 0, isFirst == true
    T.retry[i] = retry == true
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
    elseif state[i] < OPEN or state[i] == T.TENT or kind[i] ~= MELEE or at[i] ~= at0 then
        return 0 -- a TENT swing is credited, provisionally (attribution-recovery decision 48)
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
    compose(i, t)
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
            compose(i, t)
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

--- (spec §3.4 steps 2-4, owner ruling 2026-10-22; at most 4 passes (pass 4: Overdue, attribution-recovery decision 46) x CAP 32 tickets per row) The candidate for a row at t on `g` at pass `p`: among the open
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

-- What a clean payment teaches: a flight's lag (any pass, pass 3 included: with no record a ticket is a candidate at
-- pass 3 alone, so no record would ever be made) and a declared direct ability's amount band.
local function teachFrom(i, t, isAvoid, amount, flag, clean)
    local k, a = kind[i], ab[i]
    if clean and k == X.FLIGHT then
        T.Learn(guid[i], T.speed[i], t - at[i], t)
    end
    if clean and not isAvoid and a > 0 and A.expDeclared[a] and (k == X.FRAME or k == X.FLIGHT or k == X.STRIKE) then
        teach(a, amount, flag)
    end
end

-- A paid ticket's close: an assumed one closes confirmed (a hit) or refunded (an avoid), else paid (counted by kind).
local function closePaid(i, t, isAvoid)
    if T.assumed[i] then
        close(i, t, isAvoid and "refunded" or "confirmed")
    else
        T.paid[kind[i]] = T.paid[kind[i]] + 1
        close(i, t, "paid")
    end
end

--- Ticket i paid by a row at t (`clean`: the only candidate at its pass): one row fewer owed; closed when none is.
function T.Pay(i, t, isAvoid, amount, flag, clean, pass)
    if T.onPay then
        T.onPay(i, t, pass)
    end
    local k, a = kind[i], ab[i]
    -- an Overdue payment (pass 4) teaches neither the lag nor the band (attribution-recovery spec §1.1): its row is
    -- past the narrow band, so it is final at once (§2.1) and never teaches
    teachFrom(i, t, isAvoid, amount, flag, clean and pass ~= 4)
    done[i], owed[i] = done[i] + 1, owed[i] - 1
    if owed[i] < 0 then
        T.overpaid = T.overpaid + 1 -- never: a ticket is paid at most `owed` times (the sweep asserts it)
    end
    if k == X.TICKS and not isAvoid then -- the owner's soft band: the last paid tick's amount (a crit halved)
        T.tickAmt[i] = flag == "CRITICAL" and amount / 2 or amount
        if done[i] == 1 then -- the first tick confirms the application
            refresh(a, guid[i], t, i)
        end
    end
    if k == X.TICKS and T.wide[i] > 0 then -- the first tick paid: the schedule snaps to it
        T.anchor[i], T.wide[i] = t - done[i] * T.period[i], 0
        hi[i] = T.anchor[i] + (done[i] + owed[i]) * T.period[i] + T.TICK_BAND
    end
    if isAvoid and k == X.TICKS then
        owed[i] = 0 -- the application avoided: nothing owed, not lost
    end
    local j = T.link[i]
    -- at and ab equal: slot j is still the schedule composed with i (compose fills it at i's success)
    if j > 0 and state[j] >= OPEN and kind[j] == X.TICKS and T.link[j] == -1 and at[j] == at[i] and ab[j] == a then
        if isAvoid then
            close(j, t, "signal") -- the direct hit was avoided: no debuff, no ticks
        else
            refresh(a, guid[i], t, j) -- the direct row confirms the application
            if done[j] == 0 then
                T.anchor[j], T.wide[j] = t, 0 -- the application is the direct row
            end
            hi[j] = T.anchor[j] + (done[j] + owed[j]) * T.period[j] + T.TICK_BAND + T.wide[j]
        end
    end
    if owed[i] <= 0 then
        closePaid(i, t, isAvoid)
    end
end

--- The end of ticket i's narrow band (MELEE: the hand's core band), or nil when it has none (a flight with no lag
--- record). Allocates nothing.
function T.NarrowEnd(i)
    if kind[i] == MELEE then
        local L, h = I.Log, x[i]
        local e = at[i] + L.med[h] + 2 * L.spr[h]
        local e3 = ref[i] > 0 and ref[i] + L.med[3] + 2 * L.spr[3] or 0 -- an off hand's main reference
        return e > e3 and e or e3
    end
    local _, h = I.Kinds.Band(i, 1, at[i], false, "WOUND", school[i])
    return h
end

--- (attribution-recovery decision 48) Ticket i paid at pass `pass` by a row at t: final (T.Pay, false) at pass 1 or
--- 3, once its narrow band passed, for a ticking kind or a direct ticket with a live schedule (its refresh cannot be
--- undone); else TENT until fin = min(narrow band end, hi), its row kept to teach from or re-label (true).
--- Allocates nothing.
function T.PayTentative(i, t, isAvoid, amount, flag, clean, pass, act, sch)
    local k = kind[i]
    local n = (pass == 2 or pass >= 4) and k ~= X.TICKS and k ~= X.CHANNEL and T.link[i] <= 0 and T.NarrowEnd(i)
    if not n or t >= n then
        T.Pay(i, t, isAvoid, amount, flag, clean, pass)
        return false
    end
    if T.onPay then
        T.onPay(i, t, pass)
    end
    state[i], owed[i], done[i] = T.TENT, owed[i] - 1, done[i] + 1
    T.fin[i] = n < hi[i] and n or hi[i]
    T.rowT[i], T.rowAct[i], T.rowFlag[i], T.rowAmt[i], T.rowSch[i] = t, act, flag, amount, sch
    T.rowClean[i] = clean and pass < 4 -- no teaching at pass (d) (decision 46 as amended) or the early pass 5
    return true
end

--- TENT ticket i is final at `now`: Rows stages what it held (T.onFinal), it teaches from its row, and it closes paid.
function T.Final(i, now)
    if T.onFinal then
        T.onFinal(i, now)
    end
    teachFrom(i, T.rowT[i], T.rowAct[i] ~= "WOUND", T.rowAmt[i], T.rowFlag[i], T.rowClean[i])
    T.held[i] = 0
    closePaid(i, now, T.rowAct[i] ~= "WOUND")
end

--- The oldest TENT spell ticket on `g` whose narrow band holds a row at t that it would accept with its row still
--- owed; 0 when none. Allocates nothing.
function T.Replaceable(t, g, act, flag, amount, sch, isAvoid)
    local K, best = I.Kinds, 0
    for i = 1, CAP do
        if state[i] == T.TENT and kind[i] ~= MELEE and guid[i] == g and t <= T.fin[i] then
            owed[i] = 1 -- K.Accepts reads `owed`: asked as if the row were still owed
            local ok = K.Accepts(i, act, flag, amount, sch, isAvoid)
            owed[i] = 0
            local lo, h = K.Band(i, 1, t, isAvoid, act, sch)
            if ok and lo and t >= lo - 1e-9 and t <= h + 1e-9 and (best == 0 or at[i] < at[best]) then
                best = i
            end
        end
    end
    return best
end

--- TENT ticket i's row is replaced at t by a narrow-band row: Rows undoes its effects and re-offers it to our other
--- open tickets (T.onReplace, true when one took it); else it becomes foreign (arming the crowd gate at its own time).
--- The ticket owes its row again. Allocates nothing.
function T.Replace(i, t)
    T.replaced = T.replaced + 1
    if not (T.onReplace and T.onReplace(i, t)) then -- re-offered to our other tickets first (decision 48 as amended)
        T.foreign = T.foreign + 1
        T.Foreign(uid[i], T.rowSch[i], T.rowT[i])
    end
    state[i], owed[i], done[i], T.held[i] = OPEN, owed[i] + 1, done[i] - 1, 0
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

--- (spec §6.2 K18) Whether a spell ticket of school `sch` on a GUID other than `g`, open or paid within SAME_FRAME
--- before t (our target's row pays the frame first), is Due at t (its pass-1 band holds t): a foreign row then is
--- likely our AoE or cleave on a unit we did not pin. A diagnostic only. Allocates nothing.
function T.DueElsewhere(t, g, sch)
    local K, frame = I.Kinds, I.Melee.SAME_FRAME
    for i = 1, CAP do
        local st = state[i]
        if
            (st >= OPEN or (st == 0 and paidAt[i] > 0 and t - paidAt[i] <= frame))
            and guid[i] ~= g
            and kind[i] ~= MELEE
            and kind[i] ~= UNMAPPED
            and school[i] == sch
        then
            local lo, h = K.Band(i, 1, t, false, "WOUND", sch)
            if lo and t >= lo and t <= h then
                return true
            end
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
        return T.assumed[i] and "refunded" or "provisional"
    elseif st == T.ASSUMED and not U.IsDead(uid[i]) then
        return "assumed" -- the assumption stands (a dead unit's closes dead below)
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
    elseif k == X.TICKS then -- a recast whose confirming row has not come yet: its old schedule ends refreshed
        local g = guid[i]
        for j = 1, CAP do
            if
                j ~= i
                and state[j] >= OPEN
                and kind[j] == X.TICKS
                and ab[j] == ab[i]
                and guid[j] == g
                and at[j] > at[i]
            then
                return "refreshed"
            end
        end
    end
    if T.onLost then -- the expectation at the lost close (decision 51 as ruled)
        T.onLost(i)
    end
    T.lost[k] = T.lost[k] + owed[i]
    return "lost"
end

--- (attribution-recovery decision 51) Open ticket i assumed at t: a shadow (ASSUMED) to its hard window's end, Rows
--- stages the assumed outcome (T.onAssume). Also the providers' entry (a meter tick that says HIT). Allocates nothing.
function T.Assume(i, t)
    if state[i] ~= OPEN then
        return
    end
    state[i], T.assumed[i] = T.ASSUMED, true
    if T.onAssume then
        T.onAssume(i, t)
    end
end

--- Closes every ticket whose window ended by `now`, after Rows' T.onExpire (a swing's row). Every OnUpdate.
function T.Expire(now)
    for i = 1, CAP do
        if state[i] == T.TENT and now > T.fin[i] then
            T.Final(i, now)
        end
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
        T.held[i] = 0 -- a provisional payment's held observation is dropped (decision 48)
    end
    strikeWait = 0
    T.lastSwingT[1], T.lastSwingT[2] = 0, 0
    for u = 1, U.UNIT_CAP do
        clearForeign(u)
    end
end

-- A unit gone (released and past GRACE: normally nothing pins it) or dead: a dead unit's schedules end at once
-- (`dead`, ours when we killed it); its other tickets stay open until paid or their own window ends (decision 8).
U.OnGone(function(u, g, why, t)
    if why ~= U.DEAD then -- a slot gone or reset may take another GUID next
        clearForeign(u)
    end
    for i = 1, CAP do
        if state[i] == T.TENT and uid[i] == u and why == U.GONE then
            T.Final(i, t) -- nothing can replace it now: final as paid
        elseif state[i] ~= 0 and uid[i] == u then
            if why == U.GONE then
                if state[i] ~= COMMITTED and T.onExpire then
                    T.onExpire(i, t)
                end
                close(i, t, "gone")
            elseif why == U.DEAD and kind[i] == X.TICKS then
                if U.Ours(u) then
                    T.ours = T.ours + 1
                end
                close(i, t, "dead")
            end
        end
    end
end)

--- Our debuff `spellID` left `g` at t (CombatLog's SPELL_AURA_REMOVED): its schedule closes (`signal`) when that is
--- before its last tick's band. Allocates nothing.
function T.AuraGone(spellID, g, t)
    for i = 1, CAP do
        if state[i] >= OPEN and kind[i] == X.TICKS and T.tickAuraId[ab[i]] == spellID and guid[i] == g then
            local last = T.anchor[i] + (done[i] + owed[i]) * T.period[i]
            if t < last - T.TICK_BAND - T.wide[i] then
                T.paid[X.TICKS] = T.paid[X.TICKS] + 1
                close(i, t, "signal")
            end
        end
    end
end
I.Log.AuraGone = T.AuraGone

--- Our channel `spellID` stopped at t: its CHANNEL ticket closes (`signal`). Allocates nothing.
function T.ChannelStop(spellID, t)
    for i = 1, CAP do
        if state[i] >= OPEN and kind[i] == X.CHANNEL and x[i] == spellID then
            T.paid[X.CHANNEL] = T.paid[X.CHANNEL] + 1
            close(i, t, "signal")
        end
    end
end

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
        "tickets open=%d none=%d paid=%d lost=%d expired=%d refreshed=%d foreign=%d unpinned=%d dead=%d gone=%d bandRejected=%d divergent=%d overflow=%d absorbed=%d ours=%d aoeOther=%d overpaid=%d assumed=%d confirmed=%d refunded=%d",
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
        T.aoeOther,
        T.overpaid,
        c.assumed,
        c.confirmed,
        c.refunded
    )
end)
