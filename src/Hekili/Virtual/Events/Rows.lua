-- Virtual/Events/Rows.lua
-- The combat-log rows of our swings and of our abilities on the target (event-facade spec §2.4, §3): PLAYER_SWING
-- (time and hand, plain) and our UNIT_SPELLCAST_SUCCEEDED of an ability that starts combat or strikes on the next
-- swing are paired with the target's UNIT_COMBAT (the outcome, plain, victim-side) when the two arrive within
-- PAIR_WINDOW of each other, in either order: SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED, inferred, at
-- the earlier event's time (back-dated). A swing still unpaired when its window closes is emitted as SWING_DAMAGE with
-- amount 0 (its time is still the swing's); an outcome or a cast unpaired then is dropped (someone else's, or no
-- outcome). A swing paired with a CRITICAL wound also stages `Swing` c = 3 (that hand's crit) for VirtualState's
-- resources (Families/Resources.lua: a white crit's extra rage).
-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
-- (docs/research/2026-10-14-virtual-combat-log-events.md, C1, C3, C9, D7).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Obs = ns.VirtualState.Obs
local Plain = S.Plain
local L = I.Log

-- Seconds within which a swing or cast and the target's outcome pair (PAIR_WINDOW_MS / 1000; event-facade spec §3:
-- [V] D10a's 0.2 s until the phase B checkpoint measures the gap).
L.PAIR_WINDOW = 0.2

local N = 8
-- Pending own actions: kind 1 swing (hand in `x`), 2 cast (spell ID in `x`); `t` 0 is a free entry.
local actT, actKind, actX, actDst = {}, {}, {}, {}
-- Pending target outcomes: action ("WOUND", "DODGE" ...), flag text, amount.
local outT, outAction, outFlag, outAmount = {}, {}, {}, {}
for i = 1, N do
    actT[i], actKind[i], actX[i], actDst[i] = 0, 0, 0, ""
    outT[i], outAction[i], outFlag[i], outAmount[i] = 0, "", "", 0
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

local function free(ts)
    local oldest = 1
    for i = 1, N do
        if ts[i] == 0 then
            return i
        elseif ts[i] < ts[oldest] then
            oldest = i
        end
    end
    return oldest -- full: the oldest gives way, unemitted (8 pending within PAIR_WINDOW cannot happen)
end

local function oldest(ts, now)
    local best
    for i = 1, N do
        local t = ts[i]
        if t > 0 and now - t <= L.PAIR_WINDOW and (not best or t < ts[best]) then
            best = i
        end
    end
    return best
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

-- A paired swing's crit, at the pairing's time `t`: staged for the resources family.
local function crit(kind, x, act, flag, t)
    if kind == 1 and act == "WOUND" and flag == "CRITICAL" then
        S.Stage(Obs.Swing, t, x, 0, 3)
    end
end

-- An own action at `t`: paired with a pending outcome, else held.
local function action(kind, x, dst, t)
    local o = oldest(outT, t)
    if o then
        local ot = outT[o]
        outT[o] = 0
        emit(kind, x, dst, outAction[o], outFlag[o], outAmount[o], ot < t and ot or t)
        crit(kind, x, outAction[o], outFlag[o], t)
        return
    end
    local i = free(actT)
    actT[i], actKind[i], actX[i], actDst[i] = t, kind, x, dst
end

S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
    if type(swingType) ~= "number" or swingType > 1 then
        return
    end
    if swingType == 0 and strikeWait > 0 and t - strikeWait <= L.PAIR_WINDOW then
        strikeWait = 0 -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
        return
    end
    action(1, swingType + 1, Plain(api, api.UnitGUID("target")) or "", t)
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and spellID and I.ab.bySpell[spellID]
    local obj = a and I.ab.obj[a]
    if not obj or not (obj.startsCombat or obj.onNextSwing) then
        return
    end
    if obj.onNextSwing then -- the strike replaces its swing, which came before or comes after this success
        local found = false
        for i = 1, N do
            if actT[i] > 0 and actKind[i] == 1 and actX[i] == 1 and t - actT[i] <= L.PAIR_WINDOW then
                actT[i], found = 0, true
            end
        end
        if not found then
            strikeWait = t
        end
    end
    action(2, spellID, Plain(api, api.UnitGUID("target")) or "", t)
end)

S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount)
    if unit ~= "target" or type(act) ~= "string" or (act ~= "WOUND" and not MISSES[act]) then
        return
    end
    amount = type(amount) == "number" and amount or 0
    flag = type(flag) == "string" and flag or ""
    local p = oldest(actT, t)
    if p then
        local at = actT[p]
        actT[p] = 0
        emit(actKind[p], actX[p], actDst[p], act, flag, amount, at)
        crit(actKind[p], actX[p], act, flag, t)
        return
    end
    local i = free(outT)
    outT[i], outAction[i], outFlag[i], outAmount[i] = t, act, flag, amount
end)

-- Closes the windows at `now`: an unpaired swing becomes SWING_DAMAGE with amount 0 at its own time; an unpaired
-- cast or outcome is dropped. Every OnUpdate (the deferred lane, CombatLog.lua). Allocates nothing.
L.OnTick(function(now)
    for i = 1, N do
        local t = actT[i]
        if t > 0 and now - t > L.PAIR_WINDOW then
            actT[i] = 0
            if actKind[i] == 1 then
                emit(1, actX[i], actDst[i], "WOUND", "", 0, t)
            end
        end
        if outT[i] > 0 and now - outT[i] > L.PAIR_WINDOW then
            outT[i] = 0
        end
    end
end)

-- Combat end: nothing pending survives into the next pull.
S.On("PLAYER_REGEN_ENABLED", nil, function()
    for i = 1, N do
        actT[i], outT[i] = 0, 0
    end
    strikeWait = 0
end)
