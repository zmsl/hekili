-- Game/Events/Rows.lua
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
-- still unpaired when its window closes is emitted as SWING_DAMAGE with amount 0 at its own time. A DODGE / PARRY / MISS
-- while exactly one cast of ours is pending (its landing window, CAST_WINDOW once others avoid: GAP AX) also stages
-- `Avoided` for the belief (Families/Now.lua).
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
local T, M, X = I.Tickets, I.Melee, I.Expect
local SAME_FRAME, CAST_WINDOW, STRIKE_WINDOW = M.SAME_FRAME, M.CAST_WINDOW, M.STRIKE_WINDOW
local AVOIDS, MELEE, FRAME = M.AVOIDS, X.MELEE, X.FRAME
local lastW0, lastMain = -1, 0

-- Fix 31 G4: a target's outcome names no source, so after a cast of ours the kit does not map (an item's use: a thrown
-- explosive whose outcome comes a travel later) an avoid or crit in this many seconds, past our cast's own frame, is
-- nobody's, as with two casts of ours pending. UNMEASURED: a chosen bound over the wowsims log's thrown explosive (its
-- miss 1.43 s after its success, 0.13 s after our Corruption's).
L.UNMAPPED_WINDOW = 2
local unmappedT = -1e9 -- the latest success of an unmapped spell of ours

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

local strikeWait = 0 -- an on-next-swing strike's success still waiting for its main-hand swing

-- The avoids a cast can have (a swing's: M.AVOIDS).
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

-- Our open cast still in its window at `t` (or within `age` s of it), the oldest first.
local function cast(t, age)
    local best
    for i = 1, T.CAP do
        local a = T.at[i]
        if T.state[i] ~= 0 and T.kind[i] == FRAME and t - a <= (age or T.w[i]) and (not best or a < T.at[best]) then
            best = i
        end
    end
    return best
end

-- Our cast's own avoid for the belief (Obs.Avoided, Families/Now.lua): an action that refuses the whole ability, while
-- exactly one cast of ours is pending (its landing window; the caller has already given a swing of ours what one
-- explains). Anything else is not attributable and stages nothing (the belief keeps the cast's optimistic effects).
-- Obs.Avoided carries the cast's time: the refund belongs there. Allocates nothing.
-- shortcut: a projectile's later outcome is not attributed (no Forever ability declares a `velocity`), upgrade with a
-- travel time when a kit declares one.
local REFUSED = { DODGE = true, PARRY = true, MISS = true }
-- Whether a cast of ours other than p is pending at t, or an unmapped one of ours is in its window (L.UNMAPPED_WINDOW)
-- and the outcome is past p's own frame (a thrown item's outcome travels; p's own in its frame stays p's): an avoid
-- then is nobody's (no row, no Obs.Avoided).
local function another(p, t)
    if t - unmappedT <= L.UNMAPPED_WINDOW and t - T.at[p] > SAME_FRAME then
        return true
    end
    for i = 1, T.CAP do
        if i ~= p and T.state[i] ~= 0 and T.kind[i] == FRAME and t - T.at[i] <= T.w[i] then
            return true
        end
    end
    return false
end

local function avoided(p, t, act)
    if not REFUSED[act] or t - T.at[p] > T.w[p] then
        return
    end
    local a = I.ab.bySpell[T.x[p]]
    if a then
        S.Stage(Obs.Avoided, t, a, T.at[p], I.HitKind[act])
        S.Urgent("VS_CAST_AVOIDED")
    end
end

-- One row from an own action and its outcome, at the earlier time. None without a destination: Hekili's handler would
-- count a "" GUID as an enemy (`ns.updateTarget`, Events.lua:1693-1701).
local function emit(kind, x, dst, action, flag, amount, t)
    if dst == "" then
        return
    end
    local me, mf, hf = L.player, L.PLAYER_FLAGS, L.HOSTILE_FLAGS
    if kind == 1 then
        if action == "WOUND" then
            L.Swing(t, "swing", me, mf, dst, hf, amount, flag, x == 2)
        else
            L.Miss(t, "missed", me, mf, dst, hf, nil, 1, action, x == 2)
        end
    elseif action == "WOUND" then
        L.SpellHit("SPELL_DAMAGE", t, "damage", me, mf, dst, hf, x, 1, amount, flag) -- school 1 until Task 6
    else
        L.Miss(t, "missed", me, mf, dst, hf, x, 1, action)
    end
end

-- Holds an own action in a ticket (the oldest gives way) and returns it.
local function hold(kind, xx, dst, win, t)
    return T.Hold(kind == 1 and MELEE or FRAME, xx, dst, win, t, kind == 1 and xx == 2 and lastMain or 0)
end

-- swingType 2, the ranged hand (C7), is no melee swing: its clock is Sources/Swing.lua's, and the shot's outcome pairs
-- through its ability's cast success, if that starts combat (a SWING row would move Hekili's main-hand clock).
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
    if swingType == 0 and strikeWait > 0 and t - strikeWait <= STRIKE_WINDOW then
        strikeWait = 0 -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
        return
    end
    local hand = swingType + 1
    local w = L.PAIR_WINDOW_MS[hand] / 1000
    if type(duration) == "number" and duration > 0 and duration < w then
        w = duration -- the hand's next swing comes first
    end
    hold(1, hand, I.Units.Pin(api, t) or "", w, t)
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and spellID and I.ab.bySpell[spellID]
    local obj = a and I.ab.obj[a]
    if unit == "player" and type(spellID) == "number" and not a then -- an unmapped cast of ours (another())
        unmappedT = t
    end
    if not obj or not (obj.startsCombat or obj.onNextSwing) then
        return
    end
    M.advance(t)
    if obj.onNextSwing then -- the strike replaces its swing, in the same frame before or after this success
        local found = false
        for i = 1, T.CAP do
            if T.state[i] ~= 0 and T.kind[i] == MELEE and T.x[i] == 1 and t - T.at[i] <= STRIKE_WINDOW then
                T.Close(i)
                found = true
            end
        end
        if not found then
            strikeWait = t
        end
    end
    hold(2, spellID, I.Units.Sent(castGUID) or I.Units.Pin(api, t) or "", L.LandWindow(1), t)
end)

-- The target's outcome at `t`. Our pending cast claims first: an avoid within its window, a wound within its frame.
-- A WOUND 0 is the white swing an on-next-swing strike replaced and pairs with nothing; a wound right after one that
-- no cast of ours claimed is another player's strike frame (background). A white outcome (school 1) is then scored
-- against our pending swings; a wound no swing takes goes to our pending cast, else to the background.
-- A white avoid that one of our pending swings explains (any candidate past the cast's frame; inside it, a swing due
-- in that frame) is not the cast's: it would claim it as SPELL_MISSED, and an ability's `missable` would drop its
-- debuff. An avoid takes the cast in its frame before an older one still in its window.
-- shortcut: a startsCombat cast with no outcome of its own (a DoT, a debuff) takes an avoid inside its landing window
-- (CAST_WINDOW once others avoid: GAP AX) that no pending swing of ours explains as SPELL_MISSED; rare, upgrade to the
-- cast's frame if Phase D's compensating aura removal relies on it.
-- shortcut: in group play another attacker's white wound inside our pending cast's 0.2 s that no swing of ours takes
-- is credited to that cast as SPELL_DAMAGE; upgrade when a per-attacker attribution exists.
I.Units.OnRow(function(t, g, uid, act, flag, amount, school)
    -- the registry's equivalent of today's `unit == "target"`: the current target's unit, or the cleared one's while
    -- it still resolves (Task 6 replaces this with the tickets' own GUID match)
    if not I.Units.IsTarget(uid, t) or (act ~= "WOUND" and not MISSES[act]) then
        return
    end
    local api = I.api
    M.advance(t)
    -- EventFacade's Plain made a secret slot nil: no candidate (not a WOUND 0), only counted (never seen in game)
    if type(amount) ~= "number" or type(flag) ~= "string" or type(school) ~= "number" then
        M.background(act, 0, "", false, act ~= "WOUND", false)
        return
    end
    local white, avoid = school == 1, act ~= "WOUND"
    if act == "WOUND" and amount <= 0 then
        lastW0 = t
        return
    end
    local p = cast(t, SAME_FRAME) -- the fresh one in its frame first, else (an avoid) the oldest still pending
    if avoid and not p then
        p = cast(t, not (REFUSED[act] and L.bg[7] < L.FOREIGN_AVOIDS) and CAST_WINDOW or nil) -- GAP AX
    end
    -- a crit is the cast's only by the avoid's rules (GAP T); a wound row keeps its pairing either way
    local crit = not avoid and flag == "CRITICAL"
    if p and white and (avoid or crit) then
        -- a white avoid a pending swing of ours explains is the swing's (the cast keeps its effects: no SPELL_MISSED
        -- row, no Obs.Avoided), and so is a white crit's Obs.Crit: a swing due now, its landing lag within twice the
        -- hand's learned spread of the median, or one in that swing's own event frame (P log 2: an unexplained avoid
        -- in our swing's ms, 3 of 87 swings; never a cast's report)
        local sw, _, ref, lag = M.score(t, nil, amount, flag, avoid, crit) -- a crit by its timing alone, as an avoid
        local h = ref == 3 and 2 or ref
        if sw and (lag <= SAME_FRAME or math.abs(lag - L.med[h]) <= 2 * L.spr[h]) then
            if avoid then
                p = nil
            else
                crit = false
            end
        end
    end
    local credited, lr, ref, lag, second, k = nil, 0, 0, 0, 0, 1
    local unknown = false
    if not p and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
        if not avoid then
            local _, maxMain = VS.Stat("UnitDamage")
            local form = Plain(api, api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade.lua's stance row)
            unknown = maxMain <= 0 or form ~= I.damageForm
        end
        credited, lr, ref, lag, second, k = M.score(t, nil, amount, flag, avoid, unknown)
        if credited and lr < (avoid and L.THETA or L.theta[k]) then
            credited = nil
        elseif credited and not avoid and I.Missed and I.Missed(T.x[credited], T.at[credited]) then
            -- the veto, on a credit the bar passed: that swing gave no rage (its usability answers since it showed),
            -- so this wound is another source's; a wound row that swing cannot have (rage is gained at the swing, R1)
            L.oracle.vetoed, L.vetoX, L.vetoAt = L.oracle.vetoed + 1, T.x[credited], T.at[credited]
            credited = nil
        end
    end
    if not p and not credited and not avoid and white then
        p = cast(t, CAST_WINDOW)
    end
    if p and avoid and another(p, t) then
        M.background(act, amount, flag, white, avoid, unknown) -- two casts pending: whose avoid is unknown
        return
    elseif p then
        if avoid then
            avoided(p, t, act)
        elseif crit and t - T.at[p] <= T.w[p] and not another(p, t) then
            local a = I.ab.bySpell[T.x[p]] -- our cast's own crit (the target's row carries the flag plain): GAP T
            if a then
                S.Stage(Obs.Crit, t, a, T.at[p], 0)
            end
        end
        local x, at = T.x[p], T.at[p]
        T.Close(p)
        L.credited[3] = L.credited[3] + 1
        emit(2, x, T.guid[p], act, flag, amount, at)
        return
    elseif not credited then
        M.background(act, amount, flag, white, avoid, unknown)
        return
    end
    local x, at = T.x[credited], T.at[credited]
    if avoid then
        T.lr[credited], T.avoid[credited] = lr, act -- provisional: emitted when the window closes
        L.avoids, L.avoidX, L.avoidT = L.avoids + 1, x, at
        return
    end
    if T.avoid[credited] ~= "" then
        L.avoidsBack = L.avoidsBack + 1 -- the avoid it held was someone else's after all
    end
    if not unknown and M.classOf(x, amount, flag) == 1 and second < L.THETA then
        local d = ref == 3 and t - T.ref[credited] or lag
        if math.abs(d - L.med[ref]) < 3 * L.spr[ref] then
            M.learn(ref, d)
        end
    end
    recNext = recNext % RECORDS + 1
    local id = recNext
    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = t, amount, flag, at, x
    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] =
        T.guid[credited], T.w[credited], T.ref[credited], k, lr, true
    T.Close(credited)
    L.credited[x] = L.credited[x] + 1
    emit(1, x, T.guid[credited], act, flag, amount, at)
    S.Stage(Obs.Swing, at, x, id, 1) -- landed, at the swing's time: the resources family pays its rage (record id)
    if flag == "CRITICAL" then
        S.Stage(Obs.Swing, t, x, id, 3) -- the same record: a retraction takes the crit back too
    end
    S.Urgent("VS_SWING_LANDED")
end)

--- (harness design §2.2) The verdict on credit record `id` from a usability answer at t (`ok`: usable, false: short,
--- nil: not usable for another reason; `firm`: the credit's floor reached the cost), asked by Families/Resources.lua:
--- nil before ORACLE_MIN after the swing or on a nil `ok` (no verdict yet), false once one landing lag (the hand's
--- learned median) has passed since the wound or when the record is closed, true when judged. Usable confirms it (theta of its class / 1.1). Short and firm retracts it
--- (theta x 1.5): its swing is pending again inside its window, else closed as SWING_MISSED (the SWING_DAMAGE row
--- already went out: two rows for that swing, decision D9), and its wound counts as background. Short
--- and soft labels it at half weight (x 1.22). Allocates nothing.
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
        if t - at <= recW[id] then
            local i = hold(1, hand, recDst[id], recW[id], at)
            T.ref[i] = recRef[id]
        else
            emit(1, hand, recDst[id], "MISS", "", 0, at)
        end
        L.background = L.background + 1
    else
        o.soft = o.soft + 1
        th[k] = th[k] * 1.22 < L.THETA_MAX and th[k] * 1.22 or L.THETA_MAX
    end
    return true
end

-- Closes the windows at `now`: a swing holding a provisional avoid becomes SWING_MISSED, an unpaired one SWING_DAMAGE
-- with amount 0, each at its own time (and stages nothing: no rage); an unpaired cast is dropped. Every OnUpdate (the
-- deferred lane, CombatLog.lua). Allocates nothing.
L.OnTick(function(now)
    M.advance(now)
    for i = 1, T.CAP do
        local t = T.at[i]
        if T.state[i] ~= 0 and now - t > T.w[i] then
            if T.kind[i] == MELEE then
                emit(1, T.x[i], T.guid[i], T.avoid[i] ~= "" and T.avoid[i] or "WOUND", "", 0, t)
            end
            T.Close(i)
        end
    end
end)

-- Combat end: nothing pending survives into the next pull; the background and the lags are kept (decision D6).
S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    M.advance(t)
    for i = 1, T.CAP do
        T.Close(i)
    end
    strikeWait, unmappedT = 0, -1e9
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
