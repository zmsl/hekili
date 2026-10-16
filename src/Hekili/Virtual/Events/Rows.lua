-- Virtual/Events/Rows.lua
-- The combat-log rows of our swings and of our abilities on the target (event-facade spec §2.4, §3): PLAYER_SWING
-- (time and hand, plain) and our UNIT_SPELLCAST_SUCCEEDED of an ability that starts combat or strikes on the next
-- swing are held, and the target's UNIT_COMBAT (the outcome, plain, victim-side) that FOLLOWS one within its window
-- pairs with it: SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED, inferred, at the action's time
-- (back-dated). A wound picks its swing by amount against each hand's weapon damage (the out-of-combat UnitDamage
-- cache); an avoid has no amount and takes our pending cast, else the oldest pending swing of either hand (ambiguous
-- when both hands are pending: accepted). A swing still unpaired when its window closes is emitted as SWING_DAMAGE
-- with amount 0 at its own time; an outcome nothing pairs is dropped (someone else's, a tick, a proc). A wound paired
-- with a swing stages `Swing` c = 1 (landed, at the swing's time) and, when CRITICAL, c = 3 (that hand's crit) for
-- VirtualState's resources (Families/Resources.lua: swing rage and a white crit's extra).
-- Measured: docs/research/2026-10-16-swing-outcome-pairing.md.
-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
-- (docs/research/2026-10-14-virtual-combat-log-events.md, C1, C3, C9, D7).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local VS = ns.VirtualState
local Obs = VS.Obs
local Plain = S.Plain
local L = I.Log

-- Per hand (1 main, 2 off), how long a swing waits for its outcome (ms), capped at the hand's swing period. Measured
-- lag after PLAYER_SWING (research doc above): main median 474 ms (435-552 in 31 of 34, the rest up to 1287), off
-- median 953 ms (694-1070 in 22 of 31, up to 1686).
L.PAIR_WINDOW_MS = { 1500, 2000 }
-- Seconds a cast waits for its outcome, and within which an on-next-swing strike's success and its swing are one
-- event pair (the same frame, log 1).
local CAST_WINDOW, STRIKE_WINDOW = 0.2, 0.2

local N = 8
-- Pending own actions: kind 1 swing (hand in `x`), 2 cast (spell ID in `x`); `w` its window (s); `t` 0 is free.
local actT, actKind, actX, actDst, actW = {}, {}, {}, {}, {}
for i = 1, N do
    actT[i], actKind[i], actX[i], actDst[i], actW[i] = 0, 0, 0, "", 0
end

local strikeWait = 0 -- an on-next-swing strike's success still waiting for its main-hand swing

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

-- The pending action of `kind` still in its window at `t` that `score(x, amount, flag)` rates highest (0: not
-- this one; nil: every one rates 1), the oldest among equals.
local function pick(kind, t, score, amount, flag)
    local best, bestS = nil, 0
    for i = 1, N do
        local at = actT[i]
        if at > 0 and actKind[i] == kind and t - at <= actW[i] then
            local sc = score and score(actX[i], amount, flag) or 1
            if sc > bestS or (sc == bestS and sc > 0 and at < actT[best]) then
                best, bestS = i, sc
            end
        end
    end
    return best
end

-- How well a wound of `amount` fits hand h's weapon damage (UnitDamage: min and max main, then min and max off), on
-- half the amount for a crit: 2 inside [min, max], 1 inside [0.6 x min, 1.1 x max] (from 0 for a glancing or partly
-- blocked hit), else 0. The exact range decides between hands whose loose ranges overlap (log 2's crit 52: 26 is the
-- off hand's, though inside the main hand's loose range).
local function fits(h, amount, flag)
    local minMain, maxMain, minOff, maxOff = VS.Stat("UnitDamage")
    local lo, hi = minMain, maxMain
    if h == 2 then
        lo, hi = minOff, maxOff
    end
    if flag == "CRITICAL" then
        amount = amount / 2
    elseif flag == "GLANCING" or flag == "BLOCK_REDUCED" then
        lo = 0
    end
    if hi <= 0 or amount < 0.6 * lo or amount > 1.1 * hi then
        return 0
    end
    return (amount >= lo and amount <= hi) and 2 or 1
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

local function hold(kind, x, dst, w, t)
    local i = free()
    actT[i], actKind[i], actX[i], actDst[i], actW[i] = t, kind, x, dst, w
end

S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
    if type(swingType) ~= "number" or swingType > 1 then
        return
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

-- The target's outcome at `t` pairs with the action it follows. A wound: the pending swing whose hand's damage it
-- fits best, the older on a tie (the oldest of any hand before the first UnitDamage read), else our pending cast; a
-- WOUND 0 is the white swing an on-next-swing strike replaced (its frame also carries the strike's own wound) and
-- pairs with nothing. An avoid: our pending cast (its outcome comes in the same frame), else the oldest pending swing
-- of either hand.
-- shortcut: in group play another attacker's outcome inside a window can be credited to our action (and a crit lift
-- rage's lo above the real rage until the next pin); upgrade when a per-attacker attribution exists.
S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount)
    if unit ~= "target" or type(act) ~= "string" or (act ~= "WOUND" and not MISSES[act]) then
        return
    end
    amount = type(amount) == "number" and amount or 0
    flag = type(flag) == "string" and flag or ""
    local p
    if act ~= "WOUND" then
        p = pick(2, t) or pick(1, t)
    elseif amount > 0 then
        local _, maxMain = VS.Stat("UnitDamage")
        p = pick(1, t, maxMain > 0 and fits or nil, amount, flag) or pick(2, t)
    end
    if not p then
        return
    end
    local kind, x, at = actKind[p], actX[p], actT[p]
    actT[p] = 0
    emit(kind, x, actDst[p], act, flag, amount, at)
    if kind == 1 and act == "WOUND" and flag == "CRITICAL" then
        S.Stage(Obs.Swing, t, x, 0, 3)
    end
end)

-- Closes the windows at `now`: an unpaired swing becomes SWING_DAMAGE with amount 0 at its own time (and stages
-- nothing: no rage); an unpaired cast is dropped. Every OnUpdate (the deferred lane, CombatLog.lua). Allocates nothing.
L.OnTick(function(now)
    for i = 1, N do
        local t = actT[i]
        if t > 0 and now - t > actW[i] then
            actT[i] = 0
            if actKind[i] == 1 then
                emit(1, actX[i], actDst[i], "WOUND", "", 0, t)
            end
        end
    end
end)

-- Combat end: nothing pending survives into the next pull.
S.On("PLAYER_REGEN_ENABLED", nil, function()
    for i = 1, N do
        actT[i] = 0
    end
    strikeWait = 0
end)
