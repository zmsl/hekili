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

-- One row from an own action of kind `k` and its outcome at `t` (school mask `sch` for a spell), through CombatLog's
-- builders (Task 5b). None without a destination: Hekili's handler would count a "" GUID as an enemy
-- (`ns.updateTarget`, Events.lua:1693-1701).
local function emit(k, xx, dst, action, flag, amount, t, sch)
    if dst == "" then
        return
    end
    local me, mf, hf = L.player, L.PLAYER_FLAGS, L.HOSTILE_FLAGS
    if k == MELEE then
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

-- Our cast's own avoid for the belief (Families/Now.lua): an action that refuses the whole ability, staged at the
-- ticket's anchor (the refund belongs there).
local function avoided(i, t, act)
    local a = T.ab[i]
    if REFUSED[act] and a > 0 then
        S.Stage(Obs.Avoided, t, a, T.at[i], I.HitKind[act])
        S.Urgent("VS_CAST_AVOIDED")
    end
end

-- A swing closing unpaid: SWING_MISSED for a provisional avoid, else SWING_DAMAGE 0 (the swing timer reads it).
T.onExpire = function(i)
    if T.kind[i] == MELEE then
        emit(MELEE, T.x[i], T.guid[i], T.avoid[i] ~= "" and T.avoid[i] or "WOUND", "", 0, T.at[i], 1)
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
            if T.state[i] ~= 0 and T.kind[i] == MELEE and T.x[i] == 1 and t - T.at[i] <= STRIKE_WINDOW then
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
S.On("UNIT_SPELLCAST_INTERRUPTED", "player", stopped)

-- A spell row paid to ticket p at pass `pass` with n candidates at that pass: staged unless another candidate implies
-- a different state (divergent, T.Divergent: it stages nothing, spec §4.2), then emitted. A divergent avoid emits no
-- SPELL_MISSED (Hekili's `missable` would drop the other cast's debuff on it).
local function paySpell(p, n, pass, t, act, flag, amount, school, avoid, crit)
    local divergent = (avoid or crit) and n > 1 and T.Divergent(p, t, pass, act, flag, amount, school, avoid)
    if divergent then
        T.divergent = T.divergent + 1
    elseif avoid then
        avoided(p, t, act)
    elseif crit and T.ab[p] > 0 then
        S.Stage(Obs.Crit, t, T.ab[p], T.at[p], 0) -- our cast's own crit (the target's row carries the flag plain): GAP T
    end
    local kk, xx, dst, at0, sch = T.kind[p], T.x[p], T.guid[p], T.at[p], T.school[p]
    T.Pay(p, t, avoid, amount, flag, n == 1, pass)
    L.credited[3] = L.credited[3] + 1
    if not (divergent and avoid) then
        emit(kk, xx, dst, act, flag, amount, (kk == TICKS or kk == CHANNEL) and t or at0, sch > 0 and sch or school)
    end
end

-- A row of ours no ticket took (spec §3.4 step 5): an avoid or crit inside an UNMAPPED window is nobody's; else
-- foreign, teaching the background only when it is about the target (as the target-only reading did).
local function foreign(uid, t, act, flag, amount, white, avoid, unknown)
    if (avoid or flag == "CRITICAL") and T.Unmapped(t) then
        T.absorbed = T.absorbed + 1
        return
    end
    T.foreign = T.foreign + 1
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
U.OnRow(function(t, g, uid, act, flag, amount, school)
    if act ~= "WOUND" and not MISSES[act] then
        return
    end
    M.advance(t)
    if type(amount) ~= "number" or type(flag) ~= "string" or type(school) ~= "number" then
        if U.IsTarget(uid, t) then -- a secret slot (never seen in game): only counted
            M.background(act, 0, "", false, act ~= "WOUND", false)
        end
        return
    end
    local white, avoid = school == 1, act ~= "WOUND"
    if act == "WOUND" and amount <= 0 then
        lastW0 = t
        return
    end
    local crit = not avoid and flag == "CRITICAL"
    local p, n = T.Pick(t, g, 1, act, flag, amount, school, avoid)
    local pass = 1
    if p == 0 and avoid then
        p, n = T.Pick(t, g, 2, act, flag, amount, school, true)
        pass = 2
        if p == 0 then
            p, n = T.Pick(t, g, 3, act, flag, amount, school, true)
            pass = 3
        end
    end
    if p > 0 and white and (avoid or crit) then
        local sw, _, ref, lag = M.score(t, g, amount, flag, avoid, crit) -- a crit by its timing alone, as an avoid
        local h = ref == 3 and 2 or ref
        if sw and (lag <= SAME_FRAME or math.abs(lag - L.med[h]) <= 2 * L.spr[h]) then
            if avoid then
                p = 0 -- the swing's (MELEE wins the tie): the LR below takes it, the spell keeps its effects
            else
                crit = false
            end
        end
    end
    local credited, lr, ref, lag, second, k = nil, 0, 0, 0, 0, 1
    local unknown = false
    if p == 0 and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
        if not avoid then
            local _, maxMain = VS.Stat("UnitDamage")
            local form = Plain(I.api, I.api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade's stance row)
            unknown = maxMain <= 0 or form ~= I.damageForm
        end
        credited, lr, ref, lag, second, k = M.score(t, g, amount, flag, avoid, unknown)
        if credited and lr < (avoid and L.THETA or L.theta[k]) then
            credited = nil
        elseif credited and not avoid and I.Missed and I.Missed(T.x[credited], T.at[credited]) then
            -- the veto: that swing gave no rage (its usability answers since it showed), so this wound is another's
            L.oracle.vetoed, L.vetoX, L.vetoAt = L.oracle.vetoed + 1, T.x[credited], T.at[credited]
            credited = nil
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
    if p > 0 then
        if (avoid or crit) and pass > 1 and T.Unmapped(t) then
            T.absorbed = T.absorbed + 1 -- past p's own frame, inside an unmapped success's window: nobody's
            return
        end
        paySpell(p, n, pass, t, act, flag, amount, school, avoid, crit)
        return
    elseif not credited then
        foreign(uid, t, act, flag, amount, white, avoid, unknown)
        return
    end
    local xx, at0 = T.x[credited], T.at[credited]
    if avoid then
        T.Provisional(credited, lr, act) -- emitted when the window closes
        L.avoids, L.avoidX, L.avoidT = L.avoids + 1, xx, at0
        return
    end
    if T.avoid[credited] ~= "" then
        L.avoidsBack = L.avoidsBack + 1 -- the avoid it held was someone else's after all
    end
    if not unknown and M.classOf(xx, amount, flag) == 1 and second < L.THETA and not T.first[credited] then
        local d = ref == 3 and t - T.ref[credited] or lag
        if math.abs(d - L.med[ref]) < 3 * L.spr[ref] then
            M.learn(ref, d)
        end
    end
    recNext = recNext % RECORDS + 1
    local id = recNext
    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = t, amount, flag, at0, xx
    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] =
        T.guid[credited], T.w[credited], T.ref[credited], k, lr, true
    local dst = T.guid[credited]
    T.Pay(credited, t, false, amount, flag, second < L.THETA, 2)
    L.credited[xx] = L.credited[xx] + 1
    emit(MELEE, xx, dst, act, flag, amount, at0, 1)
    S.Stage(Obs.Swing, at0, xx, id, 1) -- landed, at the swing's time: the resources family pays its rage (record id)
    if flag == "CRITICAL" then
        S.Stage(Obs.Swing, t, xx, id, 3) -- the same record: a retraction takes the crit back too
    end
    S.Urgent("VS_SWING_LANDED")
end)

--- (harness design §2.2) The verdict on credit record `id` from a usability answer at t (`ok`: usable, false: short,
--- nil: not usable for another reason; `firm`: the credit's floor reached the cost), asked by Families/Resources.lua:
--- nil before ORACLE_MIN after the swing or on a nil `ok` (no verdict yet), false once one landing lag (the hand's
--- learned median) has passed since the wound or when the record is closed, true when judged. Usable confirms it (theta of its class / 1.1). Short and firm retracts it
--- (theta x 1.5): its swing is pending again inside its window on a unit still held, else closed as SWING_MISSED
--- (the SWING_DAMAGE row already went out: two rows for that swing, decision D9), and its wound counts as
--- background. Short and soft labels it at half weight (x 1.22). Allocates nothing.
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
        else
            emit(MELEE, hand, recDst[id], "MISS", "", 0, at, 1)
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
    T.Expire(now)
end)

-- Combat end: nothing open survives into the next pull; the background and the lags are kept (decision D6).
S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    M.advance(t)
    T.EndCombat(t)
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
end)
