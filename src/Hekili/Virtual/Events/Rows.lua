-- Virtual/Events/Rows.lua
-- The combat-log rows of our swings and of our abilities on the target (event-facade spec §2.4, §3): PLAYER_SWING
-- (time and hand, plain) and our UNIT_SPELLCAST_SUCCEEDED of an ability that starts combat or strikes on the next
-- swing are held, and the target's UNIT_COMBAT (the outcome, plain, victim-side, from ANY source: G fact 1) that
-- FOLLOWS one is attributed to it by score (combat harness design §1): our cast claims the outcomes of its frame first;
-- a white (school 1) outcome is then scored against every pending swing, LR = q(amount class) x f(landing lag) /
-- lambda(the learned background rate of that class), and credited to the best swing when LR >= THETA, else it is
-- background (no row). SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED are inferred, at the action's time
-- (back-dated). A credited wound stages `Swing` c = 1 (landed, at the swing's time) and, when CRITICAL, c = 3 (that
-- hand's crit) for VirtualState's resources (Families/Resources.lua). An avoid credited to a swing is provisional: a
-- later wound that scores that swing higher takes it; otherwise the swing's window closes as SWING_MISSED. A swing
-- still unpaired when its window closes is emitted as SWING_DAMAGE with amount 0 at its own time.
-- Measured: docs/research/2026-10-16-swing-outcome-pairing.md (P), docs/research/2026-10-16-group-pairing-captures.md
-- (G, G5).
-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
-- (docs/research/2026-10-14-virtual-combat-log-events.md, C1, C3, C9, D7).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local VS = ns.VirtualState
local Obs = VS.Obs
local Plain = S.Plain
local L = I.Log

-- Per hand (1 main, 2 off), the support of a swing's landing lag (ms), capped at the hand's swing period: measured
-- maximum lags 1287 / 1686 ms plus a margin (P log 2).
L.PAIR_WINDOW_MS = { 1500, 2000 }
-- Seconds a cast waits for its outcome, and within which an on-next-swing strike's success and its swing are one
-- event pair (the same frame, log 1).
local CAST_WINDOW, STRIKE_WINDOW = 0.2, 0.2
-- Seconds within which a cast's own wound comes (its frame): a yellow strike's damage can fit a weapon range, so a
-- cast this fresh takes a wound before any pending swing. Also the foreign strike frame: a wound this soon after a
-- WOUND 0 that no cast of ours claimed is someone else's on-next-swing strike (G 177249/177250).
local SAME_FRAME = 0.05

-- The score (harness design §1.2-§1.4, decision D1; PROTOTYPE values, the harness's gates hold them): THETA the
-- credit bar; q per amount class (exact, loose, above) and for an avoid; the lag density's tail weight per hand; the
-- background prior LAMBDA0 (outcomes per second) worth T0 seconds; TAU the decay of the background counts (s).
L.THETA = 5
L.Q = { 0.90, 0.08, 0.02 }
L.Q_AVOID = 0.22
L.EPS = { 0.12, 0.10 }
L.LAMBDA0, L.T0, L.TAU = 0.01, 5, 10
-- The landing lag per reference (1 main from its swing; 2 off from its own swing; 3 off from the latest main swing at
-- or before it: G5's two sharp references), seeds (MEASURED: P log 2, G5) learned online from clean credits.
L.MED0, L.SPR0 = { 0.474, 0.703, 1.686 }, { 0.060, 0.020, 0.020 }
L.med, L.spr = { 0.474, 0.703, 1.686 }, { 0.060, 0.020, 0.020 }
-- The background: per class, the white outcomes that arrived while nothing of ours was pending (1-3 main exact, loose,
-- above; 4-6 off; 7 avoid; 8 white, any amount), and the quiet time they came in; both decay with combat
-- time (decision D6: they persist across pulls).
L.bg, L.quiet = { 0, 0, 0, 0, 0, 0, 0, 0 }, 0
local lastT, lastW0, lastMain = 0, -1, 0
L.credited, L.background, L.avoidsBack = { 0, 0, 0 }, 0, 0
-- the provisional avoids taken, and the latest one's swing (hand, time): what the harness scores avoid credits by
L.avoids, L.avoidX, L.avoidT = 0, 0, 0

-- The usability oracle (harness design §2, decision D8): a credit's record is judged by the first usability answer
-- ORACLE_MIN to ORACLE_MAX s after its outcome (UNMEASURED until G7); labels move the credit bar of the record's class,
-- theta[k] for k = hand x amount class (exact, loose, above, unknown) x lag band (core: within 2 spr; tail), between
-- THETA_MIN and THETA_MAX (start THETA; kept across pulls, reset at load).
L.ORACLE_MIN, L.ORACLE_MAX = 0.1, 0.6
L.THETA_MIN, L.THETA_MAX = 2, 16
L.theta = {}
for k = 1, 16 do
    L.theta[k] = L.THETA
end
L.oracle = { judged = 0, confirmed = 0, retracted = 0, soft = 0, rescued = 0, rescuedLate = 0 }
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
-- The wounds dropped as background (DROP, a ring), each for one off-hand window: time, amount, flag, its best
-- candidate swing's hand and time, the class index, LR, and whether that swing was claimed since (credited, rescued).
local DROP = 8
local dT, dAmount, dFlag, dHand, dAt, dK, dLR, dUsed = {}, {}, {}, {}, {}, {}, {}, {}
for i = 1, DROP do
    dT[i], dAmount[i], dFlag[i], dHand[i], dAt[i], dK[i], dLR[i], dUsed[i] = 0, 0, "", 0, 0, 1, 0, true
end
local dNext = 0

local N = 8
-- Pending own actions: kind 1 swing (hand in `x`), 2 cast (spell ID in `x`); `w` its window (s); `t` 0 is free.
-- `ref` an off-hand swing's main reference (the latest main swing at or before it; 0 none); `lr` and `avoid` the LR
-- and action of an avoid credited to it provisionally ("" none).
local actT, actKind, actX, actDst, actW, actRef, actLR, actAvoid = {}, {}, {}, {}, {}, {}, {}, {}
for i = 1, N do
    actT[i], actKind[i], actX[i], actDst[i], actW[i], actRef[i], actLR[i], actAvoid[i] = 0, 0, 0, "", 0, 0, 0, ""
end

local strikeWait = 0 -- an on-next-swing strike's success still waiting for its main-hand swing

-- The avoids a swing can have (school 1) and the further ones a cast can (MISSES).
local AVOIDS = { DODGE = true, PARRY = true, MISS = true, BLOCK = true, DEFLECT = true, EVADE = true }
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

local function free()
    local oldest = 1
    for i = 1, N do
        if actT[i] == 0 then
            return i
        elseif actT[i] < actT[oldest] then
            oldest = i
        end
    end
    return oldest -- full: the oldest gives way, unemitted (8 pending within 2 s cannot happen)
end

-- Our pending cast still in its window at `t` (or within `age` s of it), the oldest first.
local function cast(t, age)
    local best
    for i = 1, N do
        local at = actT[i]
        if at > 0 and actKind[i] == 2 and t - at <= (age or actW[i]) and (not best or at < actT[best]) then
            best = i
        end
    end
    return best
end

local function pending()
    for i = 1, N do
        if actT[i] > 0 then
            return true
        end
    end
    return false
end

-- The clock of the background: in combat, the counts and the quiet time decay by exp(-dt / TAU), and the quiet time
-- grows while nothing of ours is pending. Allocates nothing.
local function advance(t)
    if t <= lastT then
        return
    end
    if I.inCombat then
        local dt = t - lastT
        local k = math.exp(-dt / L.TAU)
        local bg = L.bg
        for c = 1, 8 do
            bg[c] = bg[c] * k
        end
        L.quiet = L.quiet * k + (pending() and 0 or dt)
    end
    lastT = t
end

local function lambda(c)
    return (L.bg[c] + L.LAMBDA0 * L.T0) / (L.quiet + L.T0) -- nonzero: T0 > 0
end

-- The amount class of a wound for hand h against the weapon damage (UnitDamage: min and max main, then min and max
-- off), on half the amount for a crit: 1 exact [min, max], 2 loose [0.6 x min, 1.1 x max], 3 above (1.1 x max,
-- 2 x max] (a damage buff since the read), else 0. A glancing or partly blocked hit opens the loose band down to 0
-- (G's glancing 1-5 are another player's; log 2's BLOCK_REDUCED 48 is exact). The ranges are before armour.
local function classOf(h, amount, flag)
    local minMain, maxMain, minOff, maxOff = VS.Stat("UnitDamage")
    local lo, hi = minMain, maxMain
    if h == 2 then
        lo, hi = minOff, maxOff
    end
    if flag == "CRITICAL" then
        amount = amount / 2
    end
    local looseLo = 0.6 * lo
    if flag == "GLANCING" or flag == "BLOCK_REDUCED" then
        looseLo = 0
    end
    if hi <= 0 or amount < looseLo or amount > 2 * hi then
        return 0
    elseif amount >= lo and amount <= hi then
        return 1
    end
    return amount <= 1.1 * hi and 2 or 3
end

local function normal(d, m, s)
    local z = (d - m) / s -- nonzero: spr clamped at 0.02 s
    return math.exp(-0.5 * z * z) / (s * 2.5066283)
end

-- The landing-lag density of pending swing i for an outcome at t (0 outside its window), and the reference that
-- scored: the main hand from its swing; the off hand the better of its own swing and its main reference, plus the
-- hand's tail over the window.
local function density(i, t)
    local d, w = t - actT[i], actW[i]
    if d < 0 or d > w then
        return 0, 0
    end
    local med, spr = L.med, L.spr
    if actX[i] == 1 then
        return (1 - L.EPS[1]) * normal(d, med[1], spr[1]) + L.EPS[1] / w, 1 -- nonzero: w > 0 (a window)
    end
    local f, ref = normal(d, med[2], spr[2]), 2
    if actRef[i] > 0 then
        local m = normal(t - actRef[i], med[3], spr[3])
        if m > f then
            f, ref = m, 3
        end
    end
    return (1 - L.EPS[2]) * f + L.EPS[2] / w, ref -- nonzero: w > 0 (a window)
end

-- A clean credit moves its reference's median and spread (a running median; mean absolute deviation to SD).
local function learn(ref, d)
    local med, spr = L.med, L.spr
    med[ref] = med[ref] + 0.005 * (d > med[ref] and 1 or -1)
    local s = spr[ref] + 0.05 * (1.2533 * math.abs(d - med[ref]) - spr[ref])
    spr[ref] = s < 0.02 and 0.02 or (s > 0.4 and 0.4 or s)
    local w = L.PAIR_WINDOW_MS[ref == 1 and 1 or 2] / 1000
    med[ref] = med[ref] < 0 and 0 or (med[ref] > w and w or med[ref])
end

-- One row from an own action and its outcome, at the earlier time. None without a destination: Hekili's handler would
-- count a "" GUID as an enemy (`ns.updateTarget`, Events.lua:1693-1701).
local function emit(kind, x, dst, action, flag, amount, t)
    if dst == "" then
        return
    end
    local flags = L.HOSTILE_FLAGS
    if kind == 1 then
        local offhand = x == 2
        if action == "WOUND" then
            local r = L.Emit("SWING_DAMAGE", 21, t, true, "swing", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
            r[12], r[13], r[14], r[15], r[16], r[17] = amount, 0, 1, 0, 0, 0
            r[18], r[19], r[20], r[21] = flag == "CRITICAL", flag == "GLANCING", flag == "CRUSHING", offhand
        else
            local r = L.Emit("SWING_MISSED", 15, t, true, "missed", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
            r[12], r[13], r[14], r[15] = action, offhand, 0, false
        end
    elseif action == "WOUND" then
        local r = L.Emit("SPELL_DAMAGE", 24, t, true, "damage", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
        r[12], r[13], r[14], r[15], r[16], r[17], r[18] = x, "", 1, amount, 0, 1, 0
        r[19], r[20], r[21], r[22], r[23], r[24] = 0, 0, flag == "CRITICAL", false, false, false
    else
        local r = L.Emit("SPELL_MISSED", 18, t, true, "missed", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
        r[12], r[13], r[14], r[15], r[16], r[17], r[18] = x, "", 1, action, false, 0, false
    end
end

-- Holds an own action in a free slot (the oldest gives way) and returns the slot.
local function hold(kind, x, dst, w, t)
    local i = free()
    actT[i], actKind[i], actX[i], actDst[i], actW[i] = t, kind, x, dst, w
    actRef[i], actLR[i], actAvoid[i] = kind == 1 and x == 2 and lastMain or 0, 0, ""
    return i
end

S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
    if type(swingType) ~= "number" or swingType > 1 then
        return
    end
    advance(t)
    if swingType == 0 then
        lastMain = t
    end
    if swingType == 0 and strikeWait > 0 and t - strikeWait <= STRIKE_WINDOW then
        strikeWait = 0 -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
        return
    end
    local hand = swingType + 1
    local w = L.PAIR_WINDOW_MS[hand] / 1000
    if type(duration) == "number" and duration > 0 and duration < w then
        w = duration -- the hand's next swing comes first
    end
    hold(1, hand, Plain(api, api.UnitGUID("target")) or "", w, t)
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and spellID and I.ab.bySpell[spellID]
    local obj = a and I.ab.obj[a]
    if not obj or not (obj.startsCombat or obj.onNextSwing) then
        return
    end
    advance(t)
    if obj.onNextSwing then -- the strike replaces its swing, in the same frame before or after this success
        local found = false
        for i = 1, N do
            if actT[i] > 0 and actKind[i] == 1 and actX[i] == 1 and t - actT[i] <= STRIKE_WINDOW then
                actT[i], found = 0, true
            end
        end
        if not found then
            strikeWait = t
        end
    end
    hold(2, spellID, Plain(api, api.UnitGUID("target")) or "", CAST_WINDOW, t)
end)

-- The theta index of hand h's amount class `cls` (1-3, 4 unknown) at lag d from reference `ref`: core band (within 2
-- spr of the median) or tail.
local function thetaIndex(h, cls, ref, d)
    local band = math.abs(d - L.med[ref]) <= 2 * L.spr[ref] and 1 or 2
    return (h - 1) * 8 + (cls - 1) * 2 + band
end

-- The best pending swing for an outcome at t (amount class per hand from `classOf`, or q = 1 for every hand when
-- `unknown`; an avoid when `avoid`): its slot, LR, reference, lag, the runner-up's LR and its theta index (wounds).
-- Allocates nothing.
local function score(t, amount, flag, avoid, unknown)
    local best, bestLR, ref, lag, second, idx = nil, 0, 0, 0, 0, 1
    for i = 1, N do
        if actT[i] > 0 and actKind[i] == 1 and not (avoid and actAvoid[i] ~= "") then
            local f, r = density(i, t)
            local q, c, cls = L.Q_AVOID, 7, 4
            if not avoid then
                if unknown then
                    q, c = 1, 8
                else
                    cls = classOf(actX[i], amount, flag)
                    q, c = cls > 0 and L.Q[cls] or 0, (actX[i] - 1) * 3 + cls
                end
            end
            local lr = f > 0 and q > 0 and q * f / lambda(c) or 0
            if lr > actLR[i] or actAvoid[i] == "" then -- a wound takes a provisionally avoided swing only by beating it
                if lr > bestLR then
                    local d = r == 3 and t - actRef[i] or t - actT[i]
                    best, bestLR, ref, lag, second = i, lr, r, t - actT[i], bestLR
                    idx = thetaIndex(actX[i], cls, r, d)
                elseif lr > second then
                    second = lr
                end
            end
        end
    end
    return best, bestLR, ref, lag, second, idx
end

-- A wound nobody took into the dropped ring, with its best candidate swing (none: not kept).
local function drop(t, amount, flag, hand, at, k, lr)
    dNext = dNext % DROP + 1
    dT[dNext], dAmount[dNext], dFlag[dNext], dHand[dNext], dAt[dNext] = t, amount, flag, hand, at
    dK[dNext], dLR[dNext], dUsed[dNext] = k, lr, false
end

-- The swing of `hand` at `at` was claimed: its dropped wounds are no rescue's.
local function claimed(hand, at)
    for i = 1, DROP do
        if dHand[i] == hand and dAt[i] == at then
            dUsed[i] = true
        end
    end
end

-- An outcome nobody of ours claimed: counted, and while in combat with nothing of ours pending (the quiet time it is a
-- rate over), it teaches the background rate of each white class it qualifies for: a white avoid the avoid class, a
-- white wound the any-amount class always (its rate is over the same quiet time) and every hand's class it fits while
-- the cache is usable. A non-physical outcome, or a RESIST / IMMUNE / ABSORB, counts in no class (§1.3, §1.4).
local function background(act, amount, flag, white, avoid, unknown)
    L.background = L.background + 1
    if pending() or not I.inCombat or not white then
        return
    end
    local bg = L.bg
    if avoid then
        if AVOIDS[act] then
            bg[7] = bg[7] + 1
        end
        return
    end
    bg[8] = bg[8] + 1
    if not unknown then
        for h = 1, 2 do
            local cls = classOf(h, amount, flag)
            if cls > 0 then
                bg[(h - 1) * 3 + cls] = bg[(h - 1) * 3 + cls] + 1
            end
        end
    end
end

-- The target's outcome at `t`. Our pending cast claims first: an avoid within its window, a wound within its frame.
-- A WOUND 0 is the white swing an on-next-swing strike replaced and pairs with nothing; a wound right after one that
-- no cast of ours claimed is another player's strike frame (background). A white outcome (school 1) is then scored
-- against our pending swings; a wound no swing takes goes to our pending cast, else to the background.
-- shortcut: a startsCombat cast with no outcome of its own (a DoT, a debuff) takes an avoid inside its 0.2 s as
-- SPELL_MISSED; rare, upgrade to the cast's frame if Phase D's compensating aura removal relies on it.
-- shortcut: in group play another attacker's white wound inside our pending cast's 0.2 s that no swing of ours takes
-- is credited to that cast as SPELL_DAMAGE; upgrade when a per-attacker attribution exists.
S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
    if unit ~= "target" or type(act) ~= "string" or (act ~= "WOUND" and not MISSES[act]) then
        return
    end
    advance(t)
    amount = type(amount) == "number" and amount or 0
    flag = type(flag) == "string" and flag or ""
    local white, avoid = school == 1, act ~= "WOUND"
    if act == "WOUND" and amount <= 0 then
        lastW0 = t
        return
    end
    local p = cast(t, not avoid and SAME_FRAME or nil)
    local credited, lr, ref, lag, second, k, short = nil, 0, 0, 0, 0, 1, nil
    local unknown = false
    if not p and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
        if not avoid then
            local _, maxMain = VS.Stat("UnitDamage")
            local form = Plain(api, api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade.lua's stance row)
            unknown = maxMain <= 0 or form ~= I.damageForm
        end
        credited, lr, ref, lag, second, k = score(t, amount, flag, avoid, unknown)
        if credited and lr < (avoid and L.THETA or L.theta[k]) then
            short, credited = not avoid and credited or nil, nil
        end
    end
    if not p and not credited and not avoid and white then
        p = cast(t)
    end
    if p then
        local x, at = actX[p], actT[p]
        actT[p] = 0
        L.credited[3] = L.credited[3] + 1
        emit(2, x, actDst[p], act, flag, amount, at)
        return
    elseif not credited then
        if short then -- a wound that fell short of its best swing's bar: kept for a rescue
            drop(t, amount, flag, actX[short], actT[short], k, lr)
        end
        background(act, amount, flag, white, avoid, unknown)
        return
    end
    local x, at = actX[credited], actT[credited]
    if avoid then
        actLR[credited], actAvoid[credited] = lr, act -- provisional: emitted when the window closes
        L.avoids, L.avoidX, L.avoidT = L.avoids + 1, x, at
        return
    end
    if actAvoid[credited] ~= "" then
        L.avoidsBack = L.avoidsBack + 1 -- the avoid it held was someone else's after all
    end
    recNext = recNext % RECORDS + 1
    local id = recNext
    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = t, amount, flag, at, x
    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] =
        actDst[credited], actW[credited], actRef[credited], k, lr, true
    actT[credited], actAvoid[credited], actLR[credited] = 0, "", 0
    claimed(x, at)
    L.credited[x] = L.credited[x] + 1
    if not unknown and classOf(x, amount, flag) == 1 and second < L.THETA then
        local d = ref == 3 and t - actRef[credited] or lag
        if math.abs(d - L.med[ref]) < 3 * L.spr[ref] then
            learn(ref, d)
        end
    end
    emit(1, x, actDst[credited], act, flag, amount, at)
    S.Stage(Obs.Swing, at, x, id, 1) -- landed, at the swing's time: the resources family pays its rage (record id)
    if flag == "CRITICAL" then
        S.Stage(Obs.Swing, t, x, id, 3) -- the same record: a retraction takes the crit back too
    end
    S.Urgent("VS_SWING_LANDED")
end)

--- (harness design §2.2) The verdict on credit record `id` from a usability answer at t (`ok`: usable, false: short,
--- nil: not usable for another reason; `firm`: the credit's floor reached the cost), asked by Families/Resources.lua:
--- nil before ORACLE_MIN after the outcome (no verdict yet), false once ORACLE_MAX has passed, on a nil `ok` or when the
--- record is closed, true when judged. Usable confirms it (theta of its class / 1.1). Short and firm retracts it
--- (theta x 1.5): its swing is pending again inside its window, else closed as SWING_MISSED (the SWING_DAMAGE row
--- already went out: two rows for that swing, decision D9), and its wound joins the dropped ring as background. Short
--- and soft labels it at half weight (x 1.22). Allocates nothing.
function I.CreditVerdict(id, ok, t, firm)
    if not recOpen[id] then
        return false
    end
    local d = t - recT[id]
    if d < L.ORACLE_MIN then
        return nil
    end
    recOpen[id] = false
    if d > L.ORACLE_MAX or ok == nil then
        return false -- past its window, or a NOT answer (no rung): no verdict
    end
    local o, th, k = L.oracle, L.theta, recK[id]
    o.judged = o.judged + 1
    if ok then
        o.confirmed = o.confirmed + 1
        th[k] = th[k] / 1.1 > L.THETA_MIN and th[k] / 1.1 or L.THETA_MIN
    elseif firm then
        o.retracted = o.retracted + 1
        th[k] = th[k] * 1.5 < L.THETA_MAX and th[k] * 1.5 or L.THETA_MAX
        local hand, at = recHand[id], recAt[id]
        if t - at <= recW[id] then
            actRef[hold(1, hand, recDst[id], recW[id], at)] = recRef[id]
        else
            emit(1, hand, recDst[id], "MISS", "", 0, at)
        end
        L.background = L.background + 1
        drop(recT[id], recAmount[id], recFlag[id], hand, at, k, recLR[id])
    else
        o.soft = o.soft + 1
        th[k] = th[k] * 1.22 < L.THETA_MAX and th[k] * 1.22 or L.THETA_MAX
    end
    return true
end

--- (harness design §2.3) A flip of slot r to usable that leaves `need` unexplained (Families/Resources.lua): the dropped
--- wound that arrived ORACLE_MIN to ORACLE_MAX before it (the flip trails the wound that caused it, as a verdict does;
--- and not before `since`, the short report, less that window), whose swing nothing claimed and whose step covers
--- `need`, the best by LR. Its swing's row goes out if it is still pending (else rage only: rescuedLate); a
--- positive label. Returns its hand, whether it was a crit (Resources pays it) and its swing's time, or nil. Allocates
--- nothing.
function I.Rescue(r, need, since, t)
    local best
    for i = 1, DROP do
        local h = dHand[i]
        local age = t - dT[i]
        if not dUsed[i] and dT[i] >= since - L.ORACLE_MAX and age >= L.ORACLE_MIN and age <= L.ORACLE_MAX then
            local step = I.SwingValue(r, h) * I.res.scale[r]
            if dFlag[i] == "CRITICAL" then
                step = step + I.SwingCrit(r, h)
            end
            if step >= need - I.EPS and (not best or dLR[i] > dLR[best]) then
                best = i
            end
        end
    end
    if not best then
        return nil
    end
    local h, at, o = dHand[best], dAt[best], L.oracle
    claimed(h, at)
    o.rescued = o.rescued + 1
    local late = true
    for i = 1, N do
        if actT[i] == at and actKind[i] == 1 and actX[i] == h then
            actT[i], actAvoid[i], actLR[i], late = 0, "", 0, false
            emit(1, h, actDst[i], "WOUND", dFlag[best], dAmount[best], at)
        end
    end
    if late then
        o.rescuedLate = o.rescuedLate + 1
    end
    local k = dK[best]
    L.theta[k] = L.theta[k] / 1.1 > L.THETA_MIN and L.theta[k] / 1.1 or L.THETA_MIN
    return h, dFlag[best] == "CRITICAL", at
end

-- Closes the windows at `now`: a swing holding a provisional avoid becomes SWING_MISSED, an unpaired one SWING_DAMAGE
-- with amount 0, each at its own time (and stages nothing: no rage); an unpaired cast is dropped. Every OnUpdate (the
-- deferred lane, CombatLog.lua). Allocates nothing.
L.OnTick(function(now)
    advance(now)
    for i = 1, N do
        local t = actT[i]
        if t > 0 and now - t > actW[i] then
            actT[i] = 0
            if actKind[i] == 1 then
                emit(1, actX[i], actDst[i], actAvoid[i] ~= "" and actAvoid[i] or "WOUND", "", 0, t)
            end
            actAvoid[i], actLR[i] = "", 0
        end
    end
end)

-- Combat end: nothing pending survives into the next pull; the background and the lags are kept (decision D6).
S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    advance(t)
    for i = 1, N do
        actT[i], actAvoid[i], actLR[i] = 0, "", 0
    end
    strikeWait = 0
end)

--- Snapshot's lines (allocates; debugging only): the credits and the background, the learned lags (ms: median/spread
--- of the main hand, the off hand's own reference and its main reference) and background rates (per second: main and
--- off exact, avoid); the oracle's counts.
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
        lambda(1),
        lambda(4),
        lambda(7)
    )
    out[#out + 1] = string.format(
        "rows oracle judged=%d confirmed=%d retracted=%d soft=%d rescued=%d rescuedLate=%d",
        o.judged,
        o.confirmed,
        o.retracted,
        o.soft,
        o.rescued,
        o.rescuedLate
    )
end)
