-- Game/Events/Rows.lua
-- Our own commits and their outcomes as combat-log rows (event-facade spec §2.4, §3; unit-registry spec §3).
-- Before (to 2026-10-22): an 8-slot pending ring, its own target-only UNIT_COMBAT handler, its own GUID reads, and
-- every scoring rule inline. Now: it opens a ticket (Events/Tickets.lua) for each commit (PLAYER_SWING, a hard cast's
-- START, each success), feeds each row the unit registry resolved and deduplicated (State/Sources/Units.lua's OnRow)
-- through the consumption order (spec §3.4: spell kinds by pass, Events/Kinds.lua; the swing LR, Events/Melee.lua),
-- and turns each payment into SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED / SPELL_PERIODIC_DAMAGE at
-- the commit's time (back-dated; ticks at their own) and the staged observations: `Swing` c = 1 (landed) and c = 3
-- (that hand's crit), `Crit` and `Avoided` for a spell when no second candidate matched. It keeps the credit records,
-- I.CreditVerdict, the provisional avoid, WOUND 0's foreign strike frame and the on-next-swing replacement.
-- Measured: docs/research/2026-10-16-swing-outcome-pairing.md (P), docs/research/2026-10-16-group-pairing-captures.md
-- (G, G5); the 2026-10-22 captures (unit-registry spec §1).
-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
-- (docs/research/2026-10-14-virtual-combat-log-events.md, C1, C3, C9, D7).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local VS = ns.VirtualState
local Obs = VS.Obs
local Plain = S.Plain
local L = I.Log
local T, M, X, U = I.Tickets, I.Melee, I.Expect, I.Units
local A = I.ab
local SAME_FRAME, STRIKE_WINDOW = M.SAME_FRAME, M.STRIKE_WINDOW
local AVOIDS, MELEE, TICKS, CHANNEL = M.AVOIDS, X.MELEE, X.TICKS, X.CHANNEL

-- Credit records (ids 1-8, a ring; `Swing` c = 1's b): the outcome's time, amount and flag, the swing's time, hand,
-- destination, window and main reference, the class index, LR, and whether a verdict is still open.
local RECORDS = 8
local recT, recAmount, recFlag, recAt, recHand, recDst, recW, recRef, recK, recLR, recOpen =
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
for k = 1, RECORDS do
    recT[k], recAmount[k], recFlag[k], recAt[k], recHand[k], recDst[k], recW[k], recRef[k] = 0, 0, "", 0, 0, "", 0, 0
    recK[k], recLR[k], recOpen[k] = 1, 0, false
end
local recNext = 0

local lastMain, lastW0, fresh = 0, -1, false

-- Gap AS (owner ruling 2026-11-02): per swing ticket, the spell ticket whose own frame an avoid the swing took by the
-- MELEE tie arrived in (0 none), that ticket's and the swing's anchors (the slots' identities) and the avoid's time.
-- The swing's own wound in its core band later gives the avoid back to that cast.
local tieP, tieAt, tieSw, tieT = {}, {}, {}, {}
-- The reversed order: per swing ticket, the white wound in its core band the LR refused (time, amount, flag, amount
-- class then; wAt the swing's anchor, 0 none). An avoid in a cast's own frame then finds the swing landed: the avoid
-- is the cast's.
local wT, wAmt, wFlag, wAt, wCls = {}, {}, {}, {}, {}
for k = 1, T.CAP do
    tieP[k], tieAt[k], tieSw[k], tieT[k] = 0, 0, 0, 0
    wT[k], wAmt[k], wFlag[k], wAt[k], wCls[k] = 0, 0, "", 0, 0
end

-- The PROV swing on `g` holding a tied avoid whose core band holds a white wound at t (its own: it landed), or nil.
-- Allocates nothing.
local function tieHolder(t, g, amount, flag)
    for i = 1, T.CAP do
        local h = T.x[i]
        if
            tieP[i] > 0
            and T.state[i] == T.PROV
            and T.kind[i] == MELEE
            and T.at[i] == tieSw[i]
            and T.guid[i] == g
            and math.abs(t - T.at[i] - L.med[h]) <= 2 * L.spr[h]
            and M.classOf(h, amount, flag) > 0
        then
            return i
        end
    end
    return nil
end

local MISSES = {
    DODGE = true,
    PARRY = true,
    MISS = true,
    BLOCK = true,
    DEFLECT = true,
    EVADE = true,
    IMMUNE = true,
    RESIST = true,
    ABSORB = true,
}
local REFUSED = { DODGE = true, PARRY = true, MISS = true } -- the avoids that refuse the whole ability (Obs.Avoided)
local REACTED = { DEFLECT = true, EVADE = true } -- staged as Obs.Avoided for reactions only (Families/Now.lua: no undo)

-- One row from an own action of kind `k` and its outcome at `t` (school mask `sch` for a spell), through CombatLog's
-- builders (Task 5b). None without a destination: Hekili's handler would count a "" GUID as an enemy
-- (`ns.updateTarget`, Events.lua:1693-1701).
local lastRowT = { 0, 0 } -- per hand: the latest stamp of a swing row emitted
local function emit(k, xx, dst, action, flag, amount, t, sch)
    if dst == "" then
        return
    end
    local me, mf, hf = L.player, L.PLAYER_FLAGS, L.HOSTILE_FLAGS
    if k == MELEE then
        -- a hand's rows stay in time order: a swing's row emitted after a newer one of its hand (its window closing
        -- after a parry-hastened next swing's row) takes that row's stamp
        if t < lastRowT[xx] then
            t = lastRowT[xx]
        end
        lastRowT[xx] = t
        if action == "WOUND" then
            L.Swing(t, "swing", me, mf, dst, hf, amount, flag, xx == 2)
        else
            L.Miss(t, "missed", me, mf, dst, hf, nil, 1, action, xx == 2)
        end
    elseif action == "WOUND" then
        local sub = (k == TICKS or k == CHANNEL) and "SPELL_PERIODIC_DAMAGE" or "SPELL_DAMAGE"
        L.SpellHit(sub, t, "damage", me, mf, dst, hf, xx, sch, amount, flag) -- the ticket's school, spec §3.5
    else
        L.Miss(t, "missed", me, mf, dst, hf, xx, sch, action)
    end
end

-- (one-event-feed plan Step 1) Per hand, the anchor of its latest settled swing: a swing's row and its
-- Obs.SwingSettled (and a white crit's Obs.Crit) go out once. A verdict's re-open paid again (I.CreditVerdict) or
-- closing unpaid settles nothing twice; the belief's rage (Obs.Swing) still follows it. Per hand, so twin hands swung
-- in one ms each settle (K14). shortcut: only the latest anchor, so a hand's older swing settling after a newer one
-- lets the newer one's re-open settle again; keep more anchors if the row feed counts one.
local settledAt = { 0, 0 }
local function settle(hand, at)
    if settledAt[hand] == at then
        return false
    end
    settledAt[hand] = at
    return true
end

-- Our cast's own avoid for the belief (Families/Now.lua): an action that refuses the whole ability, staged at the
-- ticket's anchor (the refund belongs there).
local function avoided(i, t, act)
    local a = T.ab[i]
    if (REFUSED[act] or REACTED[act]) and a > 0 then
        S.Stage(Obs.Avoided, t, a, T.at[i], I.HitKind[act])
    end
end

-- Our cast's own landed hit for the belief (aura audit C10: Families/Now.lua's `onLand`): a direct hit's ticket (no
-- tick's, no swing's; each owes one row) settled as landed, once: paid by a wound or crit (at its row) or final
-- (T.onFinal). A ticket closing with no row is not presumed landed: live, every target row is background (amount, flag
-- and school secret; deferrals L317), so an avoid never pays either and a presumed land would follow every avoid,
-- promoting the gain. A cast whose ability opens no ticket (expects NONE) never lands here.
local function landed(i, t)
    local a, k = T.ab[i], T.kind[i]
    if a > 0 and k ~= TICKS and k ~= CHANNEL and k ~= MELEE then
        S.Stage(Obs.Landed, t, a, T.at[i])
    end
end

-- A swing closing unpaid: SWING_MISSED for a provisional avoid, else SWING_DAMAGE 0 (the swing timer reads it). The
-- avoid it still holds is settled now (no wound can take it back): staged at its row's time (Families/Now.lua's
-- reactions). A swing closing with no row stages SwingSettled with c = -1 at its own time: no outcome was observed, so
-- only a "land" reaction runs (live, a non-crit hit's row is secret and only avoids are plain: aura audit C3). A
-- retraction's re-open (T.retry)
-- closing on a real avoid it still holds is a new settled fact (R23): its row and settle go out, the guard aside.
T.onExpire = function(i)
    if T.kind[i] ~= MELEE then
        return
    end
    local reAvoid = T.retry[i] and T.avoid[i] ~= "" and T.state[i] == T.PROV
    if settle(T.x[i], T.at[i]) or reAvoid then
        local held = T.avoid[i] ~= ""
        emit(MELEE, T.x[i], T.guid[i], held and T.avoid[i] or "WOUND", "", 0, T.at[i], 1)
        if held and T.state[i] == T.PROV then -- only a ticket still provisional (T.Provisional) settles its avoid here
            S.Stage(Obs.SwingSettled, T.avoidT[i], T.x[i], T.at[i], I.HitKind[T.avoid[i]] or 0)
        elseif not held then
            S.Stage(Obs.SwingSettled, T.at[i], T.x[i], T.at[i], -1) -- no row: presumed landed
        end
    end
end

-- swingType 2, the ranged hand (C7), is no melee swing: its clock is Sources/Swing.lua's, and the shot's outcome pays
-- its ability's ticket.
S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
    if type(swingType) ~= "number" or swingType > 2 then
        return
    end
    M.advance(t)
    if swingType == 2 then
        return
    end
    if swingType == 0 then
        lastMain = t
    end
    if swingType == 0 and T.Swallows(t) then
        return -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
    end
    local hand = swingType + 1
    local win = L.PAIR_WINDOW_MS[hand] / 1000
    if type(duration) == "number" and duration > 0 and duration < win then
        win = duration -- the hand's next swing comes first
    end
    T.OpenSwing(t, hand, U.Pin(api, t) or "", win, hand == 2 and lastMain or 0, fresh)
    fresh = false
end)

-- U10 (owner ruling): auto-attack turns on at once, and the first PLAYER_SWING after entering combat is that first
-- swing; its row's lag is one sample (989 ms in the second Rogue capture), so it teaches nothing and its Due band is
-- its whole window. The client may send that swing first in the same ms (second Rogue capture: both at 628).
S.On("PLAYER_ENTER_COMBAT", nil, function(api, t)
    local marked = false
    for i = 1, T.CAP do -- every hand: dual wield can open both swings in that ms
        if T.state[i] ~= 0 and T.kind[i] == MELEE and t - T.at[i] <= 0.01 then
            T.first[i], marked = true, true
        end
    end
    fresh = not marked
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    if unit ~= "player" or type(spellID) ~= "number" then
        return
    end
    local a = A.bySpell[spellID] or 0
    if a > 0 and A.expKind[a] ~= X.NONE then
        M.advance(t)
    end
    local strike, found = a > 0 and A.expKind[a] == X.STRIKE, false
    if strike then -- the strike replaces its swing, in the same frame before or after this success
        for i = 1, T.CAP do
            if
                T.state[i] ~= 0
                and T.state[i] ~= T.TENT -- its white row came (a provisional credit): not the strike's swing
                and T.kind[i] == MELEE
                and T.x[i] == 1
                and t - T.at[i] <= STRIKE_WINDOW
            then
                T.Close(i, t, "replaced")
                found = true
            end
        end
    end
    local i = T.Arm(castGUID, t)
    if i == 0 then
        i = T.OpenCast(t, a, spellID, U.Sent(castGUID) or U.Pin(api, t) or "")
    end
    if strike and not found and i > 0 then
        T.OpenStrikeWait(i) -- its swing comes after: the strike ticket swallows it (T.Swallows)
    end
end)

-- A cast commits at its SENT, pinned there (spec §3.2, decision 10; capture c: the cast keeps its SENT target).
S.On("UNIT_SPELLCAST_SENT", "player", function(api, t, unit, _, castGUID, spellID)
    local a = unit == "player" and type(spellID) == "number" and A.bySpell[spellID]
    if a then
        T.Commit(t, a, spellID, U.Sent(castGUID) or U.Pin(api, t) or "", castGUID)
    end
end)

local function stopped(api, t, unit, castGUID)
    if unit == "player" then
        T.Stop(castGUID, t)
    end
end
S.On("UNIT_SPELLCAST_FAILED", "player", stopped)
S.On("UNIT_SPELLCAST_FAILED_QUIET", "player", stopped) -- a refused press (no cast): its SENT commit ends
S.On("UNIT_SPELLCAST_INTERRUPTED", "player", stopped)
S.On("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(api, t, unit, castGUID, spellID)
    if unit == "player" and type(spellID) == "number" then
        T.ChannelStop(spellID, t)
    end
end)

-- A spell row paid to ticket p at pass `pass` with n candidates at that pass: staged unless another candidate implies
-- a different state (divergent, T.Divergent: it stages nothing, spec §4.2), then emitted. A divergent avoid emits no
-- SPELL_MISSED (Hekili's `missable` would drop the other cast's debuff on it). A provisional payment (TENT,
-- attribution-recovery decision 48) holds its Crit or Avoided and its row until it is final (T.onFinal) or replaced.
local rerouting = false -- a displaced row re-offered (decision 48 as amended): it never teaches
local quiet = {} -- per ticket: its held payment is a divergent avoid (no row at T.onFinal either)
for k = 1, T.CAP do
    quiet[k] = false
end
local function paySpell(p, n, pass, t, act, flag, amount, school, avoid, crit)
    local divergent = (avoid or crit) and n > 1 and T.Divergent(p, t, pass, act, flag, amount, school, avoid)
    local kk, xx, dst, at0, sch = T.kind[p], T.x[p], T.guid[p], T.at[p], T.school[p]
    local held = T.PayTentative(p, t, avoid, amount, flag, n == 1 and not rerouting, pass, act, school)
    if held then
        quiet[p] = divergent and avoid
    end
    if divergent then
        T.divergent = T.divergent + 1
    elseif held then
        T.held[p] = avoid and 2 or (crit and T.ab[p] > 0 and 1 or 0)
    elseif avoid then
        avoided(p, t, act)
    elseif crit and T.ab[p] > 0 then
        S.Stage(Obs.Crit, t, T.ab[p], at0, 0) -- our cast's own crit (the target's row carries the flag plain): GAP T
    end
    if not held and not avoid and not divergent then
        landed(p, t)
    end
    L.credited[3] = L.credited[3] + 1
    if amount then -- nil: a secret crit's (route), never guessed
        L.fight.paid = L.fight.paid + amount
    end
    if not held and not (divergent and avoid) then
        local at = (kk == TICKS or kk == CHANNEL) and t or at0
        emit(kk, xx, dst, act, flag, amount or 0, at, sch > 0 and sch or school) -- 0: unknown, as Attackers' rows
    end
end

-- Swing ticket `credited` takes the row at t (LR lr, scoring reference ref, lag, runner-up `second`, theta index k): an
-- avoid held provisionally; a wound credited through a record (rage at the swing's time), provisional outside the core
-- band or when re-offered (decision 48: neither teaches the median). Allocates nothing.
local function creditSwing(credited, t, act, flag, amount, avoid, unknown, lr, ref, lag, second, k)
    local xx, at0 = T.x[credited], T.at[credited]
    local f = L.fight
    if T.told[credited] == 0 then
        f.swingsRow = f.swingsRow + 1 -- decided by its row, not by the Outcomes provider
    end
    if avoid then
        if T.told[credited] == 1 then
            f.collide = f.collide + 1 -- an avoid row credited to a told-HIT swing: a true collision or a foreign avoid
        end
        if T.state[credited] == T.ASSUMED and T.rec[credited] > 0 then -- refunded: the assumed rage comes back out
            recOpen[T.rec[credited]] = false
            S.Stage(Obs.Swing, t, xx, T.rec[credited], 6)
        end
        T.Provisional(credited, lr, act, t) -- emitted when the window closes
        L.avoids, L.avoidX, L.avoidT, L.avoidRowT = L.avoids + 1, xx, at0, t
        L.avoidRowG = act == "PARRY" and T.guid[credited] or ""
        return
    end
    if T.avoid[credited] ~= "" then
        L.avoidsBack = L.avoidsBack + 1 -- the avoid it held was someone else's after all
        local q = tieP[credited]
        if q > 0 and T.at[credited] == tieSw[credited] and T.state[q] == T.OPEN and T.at[q] == tieAt[credited] then
            paySpell(q, 1, 1, tieT[credited], T.avoid[credited], "", 0, 1, true, false) -- the cast's, by the tie (AS)
        end
    end
    tieP[credited] = 0
    -- a credit outside the hand's core band is provisional and never teaches the median (decision 48)
    local dc = ref == 3 and t - T.ref[credited] or lag -- the scoring reference's lag (an off hand's main reference)
    local core = T.first[credited] or lag <= SAME_FRAME or math.abs(dc - L.med[ref]) <= 2 * L.spr[ref]
    if
        core
        and not rerouting
        and not unknown
        and M.classOf(xx, amount, flag) == 1
        and second < L.THETA
        and not T.first[credited]
    then
        local d = ref == 3 and t - T.ref[credited] or lag
        if math.abs(d - L.med[ref]) < 3 * L.spr[ref] then
            M.learn(ref, d)
        end
    end
    local confirm = T.state[credited] == T.ASSUMED and T.rec[credited] > 0 -- the assumption's record becomes the credit
    local id = T.rec[credited]
    if not confirm then
        recNext = recNext % RECORDS + 1
        id = recNext
    end
    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = t, amount, flag, at0, xx
    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] =
        T.guid[credited], T.w[credited], T.ref[credited], k, lr, true
    local dst = T.guid[credited]
    T.rec[credited] = id
    local tent =
        T.PayTentative(credited, t, false, amount, flag, second < L.THETA, (core and not rerouting) and 1 or 2, act, 1)
    L.credited[xx] = L.credited[xx] + 1
    if amount then -- nil: a secret crit's (route), never guessed
        f.paid = f.paid + amount
    end
    S.Stage(Obs.Swing, at0, xx, id, confirm and 7 or 1) -- landed (or confirmed), at the swing's time: its rage
    if flag == "CRITICAL" then
        S.Stage(Obs.Swing, t, xx, id, 3) -- the same record: a retraction takes the crit back too
    end
    -- final (pass 1: T.PayTentative): no row can displace it, so the swing is settled: its row, its crit and
    -- SwingSettled (reactions), once per swing; a TENT one at T.onFinal
    if not tent and settle(xx, at0) then
        emit(MELEE, xx, dst, act, flag, amount or 0, at0, 1)
        if flag == "CRITICAL" then
            S.Stage(Obs.Crit, t, 0, at0, 0)
        end
        S.Stage(Obs.SwingSettled, t, xx, at0, I.HitKind.WOUND)
    end
end

-- The row TENT ticket i was paid by, displaced at `now` by a narrow-band row (attribution-recovery decision 48 as
-- amended: our own row, so swaps between our tickets net to nothing), re-offered to our other open tickets on its GUID
-- through the normal passes: a spell's bands (1, then 2 and 3, the swing scoring, then 4), the swing LR, and for a wound
-- an overdue swing on timing alone (its amount class may reject it). Provisional and untaught. True when one took it.
local function reroute(i, now)
    local g, t, act, flag, amount, sch = T.guid[i], T.rowT[i], T.rowAct[i], T.rowFlag[i], T.rowAmt[i], T.rowSch[i]
    local avoid, white = act ~= "WOUND", sch == 1
    rerouting = true
    local p, n, pass = T.Pick(t, g, 1, act, flag, amount, sch, avoid)
    pass = 1
    for q = 2, 3 do
        if p == 0 and avoid then
            p, n = T.Pick(t, g, q, act, flag, amount, sch, true)
            pass = q
        end
    end
    local credited, lr, ref, lag, second, k = nil, 0, 0, 0, 0, 1
    local unknown = false
    if p == 0 and white and (AVOIDS[act] or not avoid) then
        -- a secret crit's (route: amount nil) classes 0 here, so only the timing-alone pass below can take it
        credited, lr, ref, lag, second, k = M.score(t, g, amount, flag, avoid, false)
        if credited and lr < (avoid and L.THETA or L.theta[k]) then
            credited = nil
        end
        if not credited and not avoid then -- timing alone, for a swing already past its core band
            unknown = true
            credited, lr, ref, lag, second, k = M.score(t, g, amount, flag, false, true)
            if credited and (lr < L.theta[k] or now <= T.NarrowEnd(credited)) then
                credited = nil
            end
        end
        if credited and not avoid and I.Missed and I.Missed(T.x[credited], T.at[credited]) then
            credited = nil
        end
    end
    for q = 2, 4 do
        if p == 0 and not credited and (q == 4 or not avoid) then
            p, n = T.Pick(t, g, q, act, flag, amount, sch, avoid)
            pass = q
        end
    end
    if p > 0 then
        paySpell(p, n, pass, t, act, flag, amount, sch, avoid, not avoid and flag == "CRITICAL")
    elseif credited then
        creditSwing(credited, t, act, flag, amount, avoid, unknown, lr, ref, lag, second, k)
    end
    rerouting = false
    return p > 0 or credited ~= nil
end

-- A swing assumed a hit (T.Assume, attribution-recovery decision 51: a provider's HIT): staged at once as a credit
-- record the oracle can judge and a late avoid can take back (Obs.Swing c = 5).
T.onAssume = function(i, now)
    if T.kind[i] ~= MELEE then
        return -- a spell: nothing to believe; the ticket only waits as a shadow
    end
    recNext = recNext % RECORDS + 1
    local id = recNext
    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = now, 0, "", T.at[i], T.x[i]
    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] = T.guid[i], T.w[i], T.ref[i], 1, 0, true
    T.rec[i] = id
    S.Stage(Obs.Swing, T.at[i], T.x[i], id, 5)
end

-- The expectation at a swing's lost close (decision 51 as ruled 2026-10-23: expiry EV, the parked 9b; a retry none; a
-- swing the Outcomes provider called AVOID none, providers decision 70).
T.onLost = function(i)
    if T.kind[i] == MELEE and not T.retry[i] and not T.avoidSeen[i] and T.told[i] ~= 2 then
        S.Stage(Obs.Swing, T.at[i], T.x[i], 0, 5)
    end
end

-- A TENT ticket final: what it held is staged now (attribution-recovery decision 48), at its row's time (the outcome's:
-- a reaction's window counts from it), and its row emitted (one-event-feed plan Step 1: at the ticket's anchor, a tick
-- at its own time). A swing's credit (and crit) is settled here too (its Obs.Swing came at the row).
T.onFinal = function(i)
    local t, k = T.rowT[i], T.kind[i]
    if k == MELEE then -- a landed swing (an avoid is PROV, never TENT): settled now
        if settle(T.x[i], T.at[i]) then
            emit(MELEE, T.x[i], T.guid[i], T.rowAct[i], T.rowFlag[i], T.rowAmt[i] or 0, T.at[i], 1) -- nil: secret
            if T.rowFlag[i] == "CRITICAL" then
                S.Stage(Obs.Crit, t, 0, T.at[i], 0)
            end
            S.Stage(Obs.SwingSettled, t, T.x[i], T.at[i], I.HitKind.WOUND)
        end
        return
    end
    if T.held[i] == 2 then
        avoided(i, t, T.rowAct[i])
    elseif T.held[i] == 1 then
        S.Stage(Obs.Crit, t, T.ab[i], T.at[i], 0)
    end
    if T.held[i] ~= 2 and not quiet[i] then
        landed(i, t)
    end
    if not quiet[i] then
        local sch = T.school[i]
        emit(
            k,
            T.x[i],
            T.guid[i],
            T.rowAct[i],
            T.rowFlag[i],
            T.rowAmt[i] or 0, -- nil: a secret crit's (route)
            (k == TICKS or k == CHANNEL) and t or T.at[i],
            sch > 0 and sch or T.rowSch[i]
        )
    end
end

-- A TENT ticket's first row displaced: its swing credit taken back (the record's verdict closed, Resources retracts
-- with its hold), a spell's held observation dropped (Tickets clears T.held); it emitted no row (held to T.onFinal).
-- The row is then re-offered (reroute); true when one of our tickets took it (else Tickets labels it foreign).
T.onReplace = function(i, t)
    if T.kind[i] == MELEE then
        if T.rec[i] > 0 then
            recOpen[T.rec[i]] = false
            S.Stage(Obs.Swing, t, T.x[i], T.rec[i], 6)
        end
        L.credited[T.x[i]] = L.credited[T.x[i]] - 1
    else
        L.credited[3] = L.credited[3] - 1
    end
    L.fight.paid = L.fight.paid - (T.rowAmt[i] or 0) -- re-paid if reroute places it (nil: a secret crit's, unpaid)
    L.background = L.background + 1
    return reroute(i, t)
end

-- A white avoid nobody took at t on `g`: each open swing whose window holds it may have been avoided (T.onLost then
-- expects nothing). Allocates nothing.
local function avoidSeen(g, t)
    for i = 1, T.CAP do
        if
            T.state[i] == T.OPEN
            and T.kind[i] == MELEE
            and T.guid[i] == g
            and t >= T.at[i]
            and t - T.at[i] <= T.w[i]
        then
            T.avoidSeen[i] = true
        end
    end
end

-- A row of ours no ticket took (spec §3.4 step 5): an avoid or crit inside an UNMAPPED window is nobody's; else
-- foreign, teaching the background only when it is about the target (as the target-only reading did).
local function foreign(uid, t, act, flag, amount, white, avoid, unknown, school)
    if white and AVOIDS[act] then
        avoidSeen(U.GUID(uid), t)
    end
    if (avoid or flag == "CRITICAL") and T.Unmapped(t) then
        T.absorbed = T.absorbed + 1
        return
    end
    T.foreign = T.foreign + 1
    T.Foreign(uid, school, t) -- the crowd gate (Kinds.Flight)
    if act == "WOUND" and T.DueElsewhere(t, U.GUID(uid), school) then
        T.aoeOther = T.aoeOther + 1 -- a diagnostic only: routed as foreign, never a ticket, never lost
    end
    if U.IsTarget(uid, t) then
        M.background(act, amount, flag, white, avoid, unknown)
    end
end

-- The row at `t` on unit `g`, in the consumption order (spec §3.4): (1) a spell ticket's narrow band, then for an
-- avoid its widened and hard bands; a white avoid or crit a swing of ours explains is the swing's (MELEE wins a tie,
-- today's Rows.lua:458-478 order); (2) the swing LR among the swing tickets on `g`; (3) a wound's widened then hard
-- band; else nobody's. A WOUND 0 is the white
-- swing an on-next-swing strike replaced and pays nothing; a wound right after one that no ticket took is another
-- player's strike frame.
local function route(t, g, uid, act, flag, amount, school)
    if act ~= "WOUND" and not MISSES[act] then
        return
    end
    M.advance(t)
    local white, avoid = school == 1, act ~= "WOUND"
    -- Live (owner's /vslog dump 2026-11-08, D1): the amount alone is secret (the facade passes it as nil), the action,
    -- flag and school plain. An avoid routes by its kind: its amount is 0 on a plain client and no avoid path reads it.
    -- A crit routes by kind, flag and school with its amount unknown (`secret`, never guessed): no band tests or learns
    -- it, the swing LR scores it on timing alone, the rows it emits carry 0. A plain wound with a secret amount may be
    -- WOUND 0 (the white swing an on-next-swing strike replaced; captures G 177249, DM research :72: never CRITICAL),
    -- and a secret flag or school (unseen live) hides the row's kind: both only counted, as before.
    local secret = type(amount) ~= "number"
    if type(flag) ~= "string" or type(school) ~= "number" or (secret and not avoid and flag ~= "CRITICAL") then
        if U.IsTarget(uid, t) then
            M.background(act, 0, "", false, avoid, false)
        end
        return
    end
    local kindOnly = secret and avoid -- an avoid with a secret amount: its own frame only on an instant (below)
    if kindOnly then
        amount, secret = 0, false
    end
    if not secret and act == "WOUND" and amount <= 0 then
        lastW0 = t
        return
    end
    local crit = not avoid and flag == "CRITICAL"
    local tied = false -- the MELEE tie took the row from a spell: pass (d) never hands it back
    local tiedP, tiedN = 0, 0 -- the spell ticket the tie took it from in its own frame (re-offered if the swing refuses)
    local frameSw, frameP = 0, 0 -- the swing the tie gave an avoid in a cast's own frame, and that cast's ticket (AS)
    local p, n = T.Pick(t, g, 1, act, flag, amount, school, avoid)
    local pass = 1
    local replacing = 0
    if p == 0 then -- a narrow-band row for a provisionally paid ticket (attribution-recovery decision 48)
        replacing = T.Replaceable(t, g, act, flag, amount, school, avoid)
        p, n = replacing, 1
    end
    if p == 0 and avoid then
        p, n = T.Pick(t, g, 2, act, flag, amount, school, true)
        pass = 2
        if p == 0 then
            p, n = T.Pick(t, g, 3, act, flag, amount, school, true)
            pass = 3
        end
        -- live, a landed instant's own wound is unseen (its amount is secret, so it stays background above) and its
        -- ticket stays open through its landing window: a secret avoid past its own frame is then most likely another's
        -- (secret arm, 20 fights of one melee spec: 15 of 16 false refunds were past the frame, 3 of 143 right ones)
        if kindOnly and p > 0 and (T.kind[p] == X.FRAME or T.kind[p] == X.STRIKE) then
            p = 0
        end
    end
    if p > 0 and white and (avoid or crit) then
        local sw, _, ref, lag = M.score(t, g, amount, flag, avoid, crit) -- a crit by its timing alone, as an avoid
        local d, h = lag, ref == 3 and 2 or ref
        -- pass order (spec §3.4 step 4): against a ticket matched only past pass 1, an off hand landing at the main
        -- swing's lag (reference 3) runs from the main swing against L.med[3]. At pass 1 the tie keeps its old test:
        -- probe U15: at pass 1 an off-hand row scored at reference 3 is still tested against its own lag and
        -- L.med[2]; the spec's pass (a) core band is reference 3's; the full fix broke the Fury L24 loop gate (refused
        -- 3.0 -> 5.1)
        if sw and ref == 3 and pass > 1 then
            d, h = t - T.ref[sw], 3
        end
        if sw and (T.first[sw] or lag <= SAME_FRAME or math.abs(d - L.med[h]) <= 2 * L.spr[h]) then
            if avoid then
                -- a row in the spell's own frame (pass 1) tied only by the swing's frame (not its first swing's window,
                -- not its core band): the spell's again if the swing refuses it
                if pass == 1 and not T.first[sw] and lag <= SAME_FRAME then
                    tiedP, tiedN = p, n
                end
                local own = pass == 1 and t - T.at[p] <= SAME_FRAME
                -- the swing's own wound came first: it landed, the avoid is the cast's (its class as remembered: UnitDamage
                -- may have been read since)
                if own and wAt[sw] > 0 and wAt[sw] == T.at[sw] and wCls[sw] > 0 then -- 0: none remembered
                    local h, wl = T.x[sw], wT[sw] - T.at[sw]
                    local wk = M.thetaIndex(h, wCls[sw], h, wl)
                    creditSwing(sw, wT[sw], "WOUND", wFlag[sw], wAmt[sw], false, false, math.huge, h, wl, 0, wk)
                    wAt[sw] = 0
                else
                    if own then -- the cast's own frame: its again if the swing lands
                        frameSw, frameP = sw, p
                    end
                    p, tied = 0, true -- the swing's (MELEE wins the tie): the LR below takes it, the spell keeps its effects
                end
            else
                crit = false
            end
        end
    end
    local credited, lr, ref, lag, second, k = nil, 0, 0, 0, 0, 1
    local unknown = false
    local refused = 0 -- the swing the LR refused this wound for (AS's reversed order)
    if p == 0 and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
        if not avoid then
            local _, maxMain = VS.Stat("UnitDamage")
            local form = Plain(I.api, I.api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade's stance row)
            unknown = secret or maxMain <= 0 or form ~= I.damageForm -- a secret crit: its timing alone
        end
        credited, lr, ref, lag, second, k = M.score(t, g, amount, flag, avoid, unknown)
        if credited and lr < (avoid and L.THETA or L.theta[k]) then
            refused = (not avoid and lr >= 1) and credited or 0 -- still more likely ours than the background's
            credited = nil
        elseif credited and not avoid and I.Missed and I.Missed(T.x[credited], T.at[credited]) then
            -- the veto: that swing gave no rage (its usability answers since it showed), so this wound is another's
            L.oracle.vetoed, L.vetoX, L.vetoAt = L.oracle.vetoed + 1, T.x[credited], T.at[credited]
            credited = nil
        end
    end
    if p == 0 and not credited and white and (AVOIDS[act] or not avoid) then
        local r = M.Replaceable(t, g, amount, flag, avoid, unknown)
        if r and T.rec[r] > 0 and I.CreditFixed and I.CreditFixed(T.rec[r]) then
            T.Final(r, t) -- a verdict or a spend measured its rage: no longer replaceable (spec §2.3)
            r = nil
        end
        if r then -- the swing's own row in its core band replaces a provisional credit (decision 48)
            T.Replace(r, t)
            local h, rf = T.x[r], T.ref[r]
            lag = t - T.at[r]
            -- the band that matched: the hand's own, else an off hand's main reference (creditSwing's core: final)
            local rr = (rf > 0 and math.abs(lag - L.med[h]) > 2 * L.spr[h]) and 3 or h
            credited, lr, ref, second = r, math.huge, rr, 0
            k = M.thetaIndex(h, (avoid or unknown) and 4 or M.classOf(h, amount, flag), rr, rr == 3 and t - rf or lag)
        end
    end
    if p == 0 and not credited and white and not avoid and not secret then -- its own wound: by its amount class
        local i = tieHolder(t, g, amount, flag)
        if i then -- its own wound: the avoid it held by the tie was the cast's
            local h = T.x[i]
            lag = t - T.at[i]
            credited, lr, ref, second = i, math.huge, h, 0
            k = M.thetaIndex(h, M.classOf(h, amount, flag), h, lag)
        end
    end
    if p == 0 and not credited and not avoid then
        p, n = T.Pick(t, g, 2, act, flag, amount, school, false)
        pass = 2
        if p == 0 then
            p, n = T.Pick(t, g, 3, act, flag, amount, school, false)
            pass = 3
        end
    end
    -- the swing had first claim and refused a same-frame tie: the row is the spell's again, at once (its refund and
    -- undo fire through Obs.Avoided); pass (d) below still never hands a tied avoid back (owner ruling 2026-10-24)
    if tied and not credited and tiedP > 0 then
        p, n, pass = tiedP, tiedN, 1
    end
    -- pass (d), Overdue (attribution-recovery decision 46 as amended): after every band and the melee scoring, the
    -- oldest spell ticket of the queue past its expected tolerance whose hard window holds the row (late, never early).
    -- No swing is Overdue: only a provider's HIT is ASSUMED, from its swing on, so it would take every other player's
    -- white row in its window (providers fix round 1); its own row reaches it through the LR.
    if p == 0 and not credited and not tied then
        p, n = T.Pick(t, g, 4, act, flag, amount, school, avoid)
        pass = 4
    end
    if p > 0 then
        -- past p's own frame, inside an unmapped success's window: nobody's, and p's expiry is not a lost row (it
        -- may have been this one). A FLIGHT's widened and hard bands are its own landing, not past it (spec §3.4 5).
        if (avoid or crit) and pass > 1 and T.kind[p] ~= X.FLIGHT and T.Unmapped(t) then
            T.absorbed, T.excused[p] = T.absorbed + 1, true
            if white and AVOIDS[act] then
                avoidSeen(g, t)
            end
            return
        end
        if replacing > 0 and p == replacing then
            T.Replace(p, t)
        end
        paySpell(p, n, pass, t, act, flag, amount, school, avoid, crit)
        return
    elseif not credited then
        -- in its core band and amount classes, the swing's own if a cast's own avoid follows; never an unknown-class
        -- wound (form mismatch): the credit would teach from it
        if refused > 0 and not unknown then
            local h = T.x[refused]
            local cls = M.classOf(h, amount, flag)
            if math.abs(t - T.at[refused] - L.med[h]) <= 2 * L.spr[h] and cls > 0 then
                wT[refused], wAmt[refused], wFlag[refused], wAt[refused], wCls[refused] =
                    t, amount, flag, T.at[refused], cls
            end
        end
        foreign(uid, t, act, flag, amount, white, avoid, unknown, school)
        return
    end
    if avoid and credited == frameSw then
        tieP[credited], tieAt[credited], tieSw[credited], tieT[credited] = frameP, T.at[frameP], T.at[credited], t
    end
    creditSwing(credited, t, act, flag, amount, avoid, unknown, lr, ref, lag, second, k)
end

-- (providers decision 73, count-only per the owner 2026-10-23) A row is routed at once; RowOwner is asked ROW_DELAY
-- later for the audit only: FOREIGN counts `foreignByMeter` (and `disagree` when a ticket took the row), OURS on a row
-- no ticket took counts `ownUnclaimed`. With ROW_DELAY 0 (Default) nothing is queued or asked. Preallocated.
-- shortcut: "a ticket took the row" is read as T.foreign and T.absorbed unchanged by its routing (a reroute can bump
-- T.foreign from another path), so `disagree` and `ownUnclaimed` are approximate; exact needs route() to return it.
local ASK = 32
local aT, aU, aS, aM, aA, aOurs = {}, {}, {}, {}, {}, {}
for k = 1, ASK do
    aT[k], aU[k], aS[k], aM[k], aA[k], aOurs[k] = 0, 0, 0, 0, "", false
end
local aHead, aN = 0, 0
-- The fight's providers audit (Snapshot's `providers` lines): the swings the provider told (HIT/AVOID/unanswered) or a
-- row decided, avoid rows credited to a told-HIT swing (`collide`: the meter's collisions plus other players' avoids
-- the scoring gave to our swing), the amounts our tickets were paid.
L.fight = {
    ownUnclaimed = 0,
    foreignByMeter = 0,
    disagree = 0,
    overflow = 0,
    swingsTick = 0,
    swingsAvoid = 0,
    swingsRow = 0,
    swingsUnknown = 0,
    collide = 0,
    paid = 0,
}

local function ask(now)
    local P, f = I.outcomes, L.fight
    while aN > 0 do
        local k = (aHead - aN) % ASK + 1
        if now < aT[k] + P.ROW_DELAY then
            return
        end
        aN = aN - 1
        local owner = P.RowOwner(aT[k], aU[k], aS[k], aM[k], aA[k], now)
        if owner == I.FOREIGN then
            f.foreignByMeter = f.foreignByMeter + 1
            if aOurs[k] then
                f.disagree = f.disagree + 1
            end
        elseif owner == I.OURS and not aOurs[k] then
            f.ownUnclaimed = f.ownUnclaimed + 1
        end
    end
end

U.OnRow(function(t, g, uid, act, flag, amount, school)
    local f0, a0 = T.foreign, T.absorbed
    route(t, g, uid, act, flag, amount, school)
    -- a secret amount (live) is never asked about: RowOwner matches the meter by amount
    if I.outcomes.ROW_DELAY > 0 and (act == "WOUND" or MISSES[act]) and type(amount) == "number" then
        if type(school) == "number" and (amount > 0 or act ~= "WOUND") then
            if aN >= ASK then -- full: the oldest goes unasked (counted)
                aN, L.fight.overflow = aN - 1, L.fight.overflow + 1
            end
            aHead, aN = aHead % ASK + 1, aN + 1
            aT[aHead], aU[aHead], aS[aHead], aM[aHead], aA[aHead] = t, uid, school, amount, act
            aOurs[aHead] = T.foreign == f0 and T.absorbed == a0
        end
    end
end)

--- (harness design §2.2) The verdict on credit record `id` from a usability answer at t (`ok`: usable, false: short,
--- nil: not usable for another reason; `firm`: the credit's floor reached the cost), asked by Families/Resources.lua:
--- nil before ORACLE_MIN after the swing or on a nil `ok` (no verdict yet), false once one landing lag (the hand's
--- learned median) has passed since the wound or when the record is closed, true when judged. Usable confirms it (theta
--- of its class / 1.1). Short and firm retracts it (theta x 1.5): its swing is pending again inside its window on a
--- unit still held (the belief's rage model only: the re-open settles nothing twice, `settle`), and its wound counts
--- as background. No row: the core keeps the landed SWING_DAMAGE (one-event-feed plan §2.4, owner 2026-11-04; was a
--- second SWING_MISSED, decision D9). Short and soft labels it at half weight (x 1.22). Allocates nothing.
function I.CreditVerdict(id, ok, t, firm)
    if not recOpen[id] then
        return false
    end
    if t - recAt[id] < L.ORACLE_MIN - 1e-6 then -- (a float sum of the two may fall a ulp short)
        return nil
    end
    if t - recT[id] > L.med[recHand[id] == 2 and 2 or 1] then
        recOpen[id] = false
        return false -- past its window: no verdict
    elseif ok == nil then
        return nil -- a NOT answer (no rung): no verdict yet, the record stays open
    end
    recOpen[id] = false
    local o, th, k = L.oracle, L.theta, recK[id]
    o.judged = o.judged + 1
    if ok then
        o.confirmed = o.confirmed + 1
        th[k] = th[k] / 1.1 > L.THETA_MIN and th[k] / 1.1 or L.THETA_MIN
    elseif firm then
        o.retracted = o.retracted + 1
        th[k] = th[k] * 1.5 < L.THETA_MAX and th[k] * 1.5 or L.THETA_MAX
        local hand, at = recHand[id], recAt[id]
        if t - at <= recW[id] and U.Find(recDst[id]) > 0 then
            T.OpenSwing(at, hand, recDst[id], recW[id], recRef[id], false, true)
        end
        L.background = L.background + 1
    else
        o.soft = o.soft + 1
        th[k] = th[k] * 1.22 < L.THETA_MAX and th[k] * 1.22 or L.THETA_MAX
    end
    return true
end

-- Closes the windows at `now` (each swing's row at its own time). Every OnUpdate. Allocates nothing.
L.OnTick(function(now)
    M.advance(now)
    T.Decide(now) -- the Outcomes provider's swing answers (providers decision 70)
    T.Expire(now)
    if aN > 0 then
        ask(now)
    end
end)

-- Combat end: nothing open survives into the next pull; the background and the lags are kept (decision D6). A
-- provider swap asked for in combat applies now (I.SetProviders).
S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    M.advance(t)
    if aN > 0 then
        ask(math.huge)
    end
    T.EndCombat(t)
    fresh = false
    I.ApplyProviders(t)
end)

-- A pull: the providers audit's counters start again.
S.On("PLAYER_REGEN_DISABLED", nil, function()
    local f = L.fight
    f.ownUnclaimed, f.foreignByMeter, f.disagree, f.overflow, aN = 0, 0, 0, 0, 0
    f.swingsTick, f.swingsAvoid, f.swingsRow, f.swingsUnknown, f.collide, f.paid = 0, 0, 0, 0, 0, 0
end)

--- Snapshot's lines (allocates; debugging only): the credits and the background, the learned lags (ms) and the
--- background rates (per second); the oracle's counts.
I.OnSnapshot(function(out)
    local c, med, spr, o = L.credited, L.med, L.spr, L.oracle
    out[#out + 1] = string.format(
        "rows credited main=%d off=%d cast=%d background=%d avoidsBack=%d lag main=%.0f/%.0f off=%.0f/%.0f ref=%.0f/%.0f lambda exact=%.2f/%.2f avoid=%.2f",
        c[1],
        c[2],
        c[3],
        L.background,
        L.avoidsBack,
        med[1] * 1000,
        spr[1] * 1000,
        med[2] * 1000,
        spr[2] * 1000,
        med[3] * 1000,
        spr[3] * 1000,
        M.lambda(1),
        M.lambda(4),
        M.lambda(7)
    )
    out[#out + 1] = string.format(
        "rows oracle judged=%d confirmed=%d retracted=%d soft=%d vetoed=%d",
        o.judged,
        o.confirmed,
        o.retracted,
        o.soft,
        o.vetoed
    )
    -- the providers audit (providers spec §4.3), two lines so each stays under 255 characters for VSCopy
    local f, a = L.fight, I.outcomes.Audit()
    local pn, pe = I.PinError()
    local e = I.presenceEdges
    out[#out + 1] = string.format(
        "providers outcomes=%s presence=%s swings tick=%d/%d row=%d unknown=%d muted=%d ownUnclaimed=%d foreignByMeter=%d",
        I.outcomes.name,
        I.presence and I.presence.name or "-",
        f.swingsTick,
        f.swingsAvoid,
        f.swingsRow,
        f.swingsUnknown,
        I.outcomes.muted or 0,
        f.ownUnclaimed,
        f.foreignByMeter
    )
    out[#out + 1] = string.format(
        "providers paid=%d meter=%s pins=%d pinErr=%.1f edges up=%d down=%d collide=%d disagree=%d",
        f.paid,
        a and tostring(a.done) or "-",
        pn,
        pn > 0 and pe / pn or 0,
        e and e.up or 0,
        e and e.down or 0,
        f.collide,
        f.disagree
    )
end)
