-- Game/State/Families/Swing.lua
-- The swing family (spec §6.4) and melee haste (§6.5): per hand an anchor and a speed; the next swing is
-- anchorT + k x speed. Anchors carry weights: PLAYER_SWING 1.0, a paired rage step 0.5, combat start 0.3; conf is the
-- anchor's weight falling linearly to 0 over SWING_DECAY. The observed swing duration is the hasted speed; melee
-- haste is observed out of combat and modelled in combat as the base speed / the observed duration.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Swing.lua (weights :54, confAt :181-188, after
-- :196-205, Applier Swing :602, Listener PowerTick :656, CombatStart :710, CombatEnd :723) and Belief/Player.lua
-- (Applier Haste :130).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local floor = math.floor

local W_SWING, W_PAIR, W_COMBAT = 1, 0.5, 0.3

local anchorT, speed, base, last, w0, confAt = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }
local prevTick = { 0, 0 }
local swingRec, speedRec, haste = {}, {}, nil
I.haste0 = 1

I.OnBuild(function(def, now)
    for h = 1, 2 do
        anchorT[h], w0[h], prevTick[h], last[h] = 0, 0, 0, 0 -- the old set's clock; Sources/Swing.lua re-reads speeds
        swingRec[h] = I.NewBelief(h == 1 and "swing main" or "swing off")
        speedRec[h] = I.NewBelief(h == 1 and "swing speed main" or "swing speed off")
        I.Sample(speedRec[h], "default", h == 1 and 2 or 0, now, 0)
        if speed[h] == 0 and h == 1 then
            speed[h] = 2
        end
    end
    haste = I.NewBelief("haste melee")
    I.Sample(haste, "default", 1, now, 0)
end)

--- The believed speed of hand h (seconds; 0: no weapon). Allocates nothing.
function I.SwingSpeedEst(h)
    return speed[h]
end

local function anchor(h, t, w)
    anchorT[h], w0[h], confAt[h] = t, w, t
end

I.On(Obs.Swing, function(o, t)
    local h, c = o.a, o.c
    if h ~= 1 and h ~= 2 then
        return
    end
    if c == 4 then -- PLAYER_SWING, landed or not (c = 1, landed, is the resources family's)
        anchor(h, o.t, W_SWING)
        last[h] = o.t
        if o.b > 0 then
            speed[h] = o.b
            I.Sample(speedRec[h], "observed", o.b, t, Obs.Swing)
            if h == 1 and base[1] > 0 and I.inCombat then
                I.haste0 = base[1] / o.b -- nonzero: o.b > 0 checked
                I.Sample(haste, "modelled", I.haste0, t, Obs.Swing)
            end
        end
        I.Sample(swingRec[h], "observed", o.t + speed[h], t, Obs.Swing)
    elseif c == 0 then
        speed[h] = o.b
        I.Sample(speedRec[h], "observed", o.b, t, Obs.Swing)
    elseif c == 2 then
        base[h] = o.b
    end
end)

I.On(Obs.Haste, function(o, t)
    if o.c == 1 and o.b > 0 then
        I.haste0 = o.b
        I.Sample(haste, "observed", o.b, t, Obs.Haste)
    end
end)

-- The first predicted swing strictly after t (TDF after()). The caller checks speed > 0.
local function after(h, t)
    local sp, at = speed[h], anchorT[h]
    local p = at + (floor((t - at) / sp) + 1) * sp -- nonzero: callers check speed > 0
    if p <= t then
        p = p + sp
    elseif p - sp > t then
        p = p - sp
    end
    return p
end

-- A paired rage step (spec §6.4): a PowerTick of a swing-paid resource that no PLAYER_SWING and no own cast
-- explains is a landed swing when it falls one swing after the previous such tick (a pair: anchor at weight 0.5 when
-- the clock is weaker) or on a predicted swing (a confirmation: the clock re-anchors there).
local OWN_TICK = 0.1 -- TDF Belief.OWN_TICK: a tick this close to our cast is the cast's own change

I.On(Obs.PowerTick, function(o, t)
    local h = I.res.swing[o.a]
    if not h or h == 0 or speed[h] <= 0 then
        return
    end
    local x = o.t
    if x - last[h] <= I.SWING_TOL or x - I.lastCastT <= OWN_TICK then
        return
    end
    local sp = speed[h]
    if anchorT[h] > 0 then
        local p = after(h, x - I.SWING_TOL)
        if p - x <= I.SWING_TOL and x - p <= I.SWING_TOL then
            anchorT[h], confAt[h] = x, x
            if w0[h] < W_PAIR then
                w0[h] = W_PAIR
            end
            I.Sample(swingRec[h], "modelled", x + sp, t, Obs.PowerTick)
            prevTick[h] = x
            return
        end
    end
    local gap = x - prevTick[h] - sp
    if prevTick[h] > 0 and gap <= I.SWING_TOL and gap >= -I.SWING_TOL then
        local age = x - confAt[h]
        local c = w0[h] * (1 - age / I.SWING_DECAY) -- nonzero: SWING_DECAY is a constant
        if anchorT[h] == 0 or c < W_PAIR then
            anchor(h, x, W_PAIR)
            I.Sample(swingRec[h], "modelled", x + sp, t, Obs.PowerTick)
        end
    end
    prevTick[h] = x
end)

I.On(Obs.CombatStart, function(o, t)
    for h = 1, 2 do
        if speed[h] > 0 and w0[h] < W_COMBAT then
            anchor(h, o.t, W_COMBAT)
            I.Sample(swingRec[h], "modelled", o.t + speed[h], t, Obs.CombatStart)
        end
    end
end)

I.On(Obs.CombatEnd, function()
    for h = 1, 2 do
        anchorT[h], w0[h], prevTick[h] = 0, 0, 0
    end
end)

--- (spec §3.2) The next swing of hand 1 (main) or 2 (off) after now.
function VS.Swing(hand, now)
    local rec = swingRec[hand]
    if not rec then
        return I.UNKNOWN
    end
    if speed[hand] > 0 and anchorT[hand] > 0 then
        local p = after(hand, now)
        rec.est, rec.lo, rec.hi = p, p, p
        local age = now - confAt[hand]
        local f = age <= 0 and 1 or 1 - age / I.SWING_DECAY -- nonzero: SWING_DECAY is a constant
        rec.conf = f > 0 and w0[hand] * f or 0
    else
        rec.est, rec.lo, rec.hi, rec.conf = 0, 0, 0, 0
    end
    return rec
end

--- (spec §3.2) The believed swing speed of a hand (seconds): PLAYER_SWING durations and out-of-combat reads.
function VS.SwingSpeed(hand, now)
    local rec = speedRec[hand]
    if not rec then
        return I.UNKNOWN
    end
    local s = speed[hand]
    rec.est, rec.lo, rec.hi = s, s, s
    I.AgeConf(rec, now)
    return rec
end

--- (spec §3.1) The absolute time of the last observed swing of a hand, 0 when none.
function VS.LastSwing(hand)
    return last[hand] or 0
end

--- (spec §3.1) The unhasted base speed of a hand (seconds) from the last plain out-of-combat read, 0 before one.
--- Allocates nothing.
function VS.SwingBase(hand)
    return base[hand] or 0
end

--- (spec §3.2) The melee haste multiplier.
function VS.Haste(now)
    if not haste then
        return I.UNKNOWN
    end
    haste.est, haste.lo, haste.hi = I.haste0, I.haste0, I.haste0
    I.AgeConf(haste, now)
    return haste
end

I.OnSnapshot(function(out, now)
    for h = 1, 2 do
        VS.Swing(h, now)
        VS.SwingSpeed(h, now)
        out[#out + 1] = string.format(
            "hand %d anchor=%.2f speed=%.3f base=%.3f last=%.2f weight=%.1f",
            h,
            anchorT[h],
            speed[h],
            base[h],
            last[h],
            w0[h]
        )
    end
    VS.Haste(now)
end)
