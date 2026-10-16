-- Virtual/State/Families/Resources.lua
-- The resources family (spec §6.1): the cost ladder (a usability report pins or bounds a resource at the ability's
-- cost), exact reads, regen calibration between pins (an EMA), swing steps for a swing-paid resource (rage), our own
-- casts' changes (Adapter.lua, spec §5.3), periodic regen (Hekili's regen-model entries with `interval` and `value`:
-- with an `aura`, Bloodrage's rage over time; without one, in combat: Anger Management), and the Power/Regen accessors.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Resources.lua (calibrate :117-136, pin :218-263,
-- ladder :275-315, Applier Usable :327, Reader Resource :365-372) and the resource conf of
-- src/TacoDogForever/Model/Belief.lua:695-699. The power-tick phase (TDF's Applier PowerTick :378) is not modelled in
-- Phase 1.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, ReadOf = VS.Obs, I.ReadOf
local abs, floor = math.abs, math.floor

--- A flip pin measures regen only when the last short report was at most this long before it (TDF Belief.PIN_EXACT).
I.PIN_EXACT = 0.15

-- Usability as observed: unknown, not usable, usable, not usable for lack of its resource.
local UNKNOWN, NOT, YES, SHORT = -1, 0, 1, 2

-- By resource slot r. `swing[r]` is the hand that pays it (1 main, 2 off; 0: continuous regen) and `swingOff[r]` the
-- off hand's own value when both hands pay it (0: none); `swingAura[r]` the player aura index its swings need (0: none;
-- -1: named but not tracked, so no swing pays). Continuous regen is per second (regE/regL/regH); a swing-paid
-- resource's step is the spec's model value of that hand x scale (spread around it). `restMax[r]`: a regenerating
-- resource rests at its maximum (energy, mana), the others at 0 (rage).
local R = {
    n = 0,
    type = {},
    token = {},
    max = {},
    rest = {},
    restMax = {},
    swing = {},
    swingAura = {},
    swingValue = {},
    swingOff = {},
    est0 = {},
    lo0 = {},
    hi0 = {},
    regE = {},
    regL = {},
    regH = {},
    decl = {},
    dev = {},
    scale = {},
    spread = {},
    pinT = {},
    pinV = {},
    pinDelta = {},
    pinValid = {},
    snapT = {},
    readT = {},
    readable = {},
    power = {},
    regen = {},
    decayDef = {},
    decay = {},
    maxDef = {},
    maxMods = {},
    maxRead = {},
}
I.res = R
R.slotOf, R.slotOfToken = {}, {}

-- Periodic regen entries g of every slot (built from each resource's `auraRegen`): `value` every `interval` seconds
-- from the aura's application while the player's aura j is believed up, or (no aura: j = 0) from the combat start
-- while in combat (Anger Management); an entry with a `talent` only while that talent has a rank. Credited only as
-- the clock moves on: an aura first seen after its application loses the ticks before that, and a removal seen late
-- keeps the ticks already credited; both are bounded by the aura's duration and the next pin or rung corrects them.
local G = { n = 0, slot = {}, aura = {}, value = {}, interval = {}, talent = {} }
-- In combat (fold order, for the entries without an aura: aura index 0) and since when.
local fighting, fightT = false, 0
R.auraRegen = G

-- Slot r's out-of-combat loss per second from its `decay` (a number or a state-bound function; absent: none),
-- evaluated at the build and at each combat end (talent ranks change out of combat only). Allocates nothing.
local function decayOf(r)
    local d = R.decayDef[r]
    if type(d) == "function" then
        d = d()
    end
    return type(d) == "number" and d > 0 and d or 0
end

local function eval(v)
    if type(v) == "function" then
        v = v()
    end
    return v
end

-- Slot r's declared maximum from its `max` (a number or a state-bound function; default 100) x the product of
-- (1 + pct) over its `maxMods` whose `when` holds (Families/Modifiers.lua), used until a plain read arrives.
-- Allocates nothing.
local function maxOf(r)
    local m = eval(R.maxDef[r])
    m = type(m) == "number" and m > 0 and m or 100
    local mods = R.maxMods[r]
    if mods then
        for k = 1, #mods do
            local mod = mods[k]
            if mod.when == nil or eval(mod.when) == true then
                m = m * (1 + (type(mod.pct) == "number" and mod.pct or 0))
            end
        end
    end
    return m
end

-- By ability index a: the last usability answer and the last short report (cost, time).
local usable, shortCost, shortT = {}, {}, {}

local function clamp(v, max)
    if v < 0 then
        return 0
    elseif v > max then
        return max
    end
    return v
end

-- Slot r's maximum becomes m. A slot resting at its maximum rests at the new one, and its estimate and upper bound rise
-- by an increase (seeded at 100, a plain read of 1200 believes 1200), kept out of the regen measurement; a decrease
-- caps every slot's interval at the new maximum. Allocates nothing.
local function setMax(r, m)
    local up = m - R.max[r]
    R.max[r] = m
    if up < 0 then
        local before = R.est0[r]
        R.est0[r], R.lo0[r], R.hi0[r] = clamp(before, m), clamp(R.lo0[r], m), clamp(R.hi0[r], m)
        R.pinDelta[r] = R.pinDelta[r] + R.est0[r] - before -- the capped-away amount stays out of the regen measurement
    end
    if R.restMax[r] then
        R.rest[r] = m
        if up > 0 then
            R.est0[r] = clamp(R.est0[r] + up, m)
            R.hi0[r] = clamp(R.hi0[r] + up, m)
            R.pinDelta[r] = R.pinDelta[r] + up
        end
    end
end

I.OnBuild(function(def, now)
    for k in pairs(R.slotOf) do
        R.slotOf[k] = nil
    end
    for k in pairs(R.slotOfToken) do
        R.slotOfToken[k] = nil
    end
    local list = def.resources
    R.n = #list
    for r = 1, R.n do
        local d = list[r]
        R.type[r], R.token[r] = d.type, d.token
        R.slotOf[d.type], R.slotOfToken[d.token] = r, r
        R.maxDef[r], R.maxMods[r], R.maxRead[r] = d.max, d.maxMods, false
        R.max[r] = maxOf(r)
        R.restMax[r] = d.rest == true
        R.rest[r] = R.restMax[r] and R.max[r] or 0
        R.swing[r] = d.swing or 0
        R.swingValue[r] = d.swingValue or 0
        R.swingOff[r] = d.swingOff or 0
        R.est0[r], R.lo0[r], R.hi0[r] = R.rest[r], 0, R.max[r]
        local rate = d.regen or 0
        R.decl[r] = rate
        R.regE[r], R.regL[r], R.regH[r] = rate, rate * (1 - I.REGEN_SPREAD), rate * (1 + I.REGEN_SPREAD)
        R.dev[r], R.scale[r], R.spread[r] = 0, 1, I.REGEN_SPREAD
        R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r] = 0, 0, 0, false
        R.snapT[r], R.readT[r], R.readable[r] = -1e9, -1e9, false
        R.decayDef[r] = d.decay
        R.decay[r] = decayOf(r)
        R.power[r] = I.NewBelief("power " .. tostring(d.key))
        R.regen[r] = I.NewBelief("regen " .. tostring(d.key))
        I.Sample(R.power[r], "default", R.rest[r], now, 0)
        I.Sample(R.regen[r], "default", rate, now, 0)
    end
    I.TRACKED.resource = R.type
    for r = 1, R.n do
        local name = list[r].swingAura
        local j = name == nil and 0 or -1
        for i = 1, #def.auras do
            if def.auras[i].key == name then
                j = i
            end
        end
        R.swingAura[r] = j
    end
    G.n = 0
    -- shortcut: a build in combat (a /reload, a spec change) times the combat entries from the build, not the pull;
    -- the next pull's CombatStart sets the real start.
    fighting, fightT = I.inCombat == true, now
    for r = 1, R.n do
        local entries = list[r].auraRegen
        for k = 1, entries and #entries or 0 do
            local e = entries[k]
            local j, tid = e.aura == nil and 0 or -1, e.talent == nil and 0 or -1 -- -1: named but not tracked
            for i = 1, #def.auras do
                if def.auras[i].key == e.aura then
                    j = i
                end
            end
            for i = 1, #def.talents do
                if def.talents[i].key == e.talent then
                    tid = def.talents[i].spell
                end
            end
            local ok = type(e.value) == "number" and type(e.interval) == "number" and e.interval > 0
            if ok and j >= 0 and tid >= 0 then
                G.n = G.n + 1
                G.slot[G.n], G.aura[G.n], G.value[G.n], G.interval[G.n] = r, j, e.value, e.interval
                G.talent[G.n] = tid
            end
        end
    end
    for a = 1, #def.abilities do
        usable[a], shortCost[a], shortT[a] = UNKNOWN, 0, 0
    end
end)

--- The spec's per-swing value of a swing-paid slot for `hand` (2: the off hand's `swingOff`; else the paying hand's): a
--- number, or the model's state-bound function; 0 while the slot's swing aura is not believed up at the clock (its
--- application after it, or its expiry at or before it). Allocates nothing.
function I.SwingValue(r, hand)
    local j = R.swingAura[r]
    if j < 0 or j > 0 and (I.auras.exp0[1][j] <= I.clock or I.auras.applied[1][j] > I.clock) then
        return 0 -- unit 1 is always "player" (Adapter.lua's def.units)
    end
    local v = R.swingValue[r]
    if hand == 2 and R.swing[r] == 1 then
        v = R.swingOff[r]
    end
    if type(v) == "function" then
        v = v(I.clock)
    end
    return type(v) == "number" and v or 0
end

-- What entry g brings in (from, to]: `value` at each `interval` after the player's aura was applied, up to its
-- believed expiry. Allocates nothing.
local function auraGain(g, from, to)
    local j, tid = G.aura[g], G.talent[g]
    if tid > 0 and VS.Talent(tid) == 0 then
        return 0
    end
    local e, ap
    if j == 0 then
        if not fighting then
            return 0
        end
        e, ap = to, fightT
    else
        e, ap = I.auras.exp0[1][j], I.auras.applied[1][j] -- unit 1 is always "player" (Adapter.lua's def.units)
    end
    if e <= from then
        return 0
    end
    local iv = G.interval[g]
    if to > e then
        to = e
    end
    if from < ap then
        from = ap
    end
    if to <= from then
        return 0
    end
    return (floor((to - ap) / iv) - floor((from - ap) / iv)) * G.value[g] -- nonzero: interval > 0 (checked at build)
end

-- Continuous regen between pins (swing-paid slots move only at swings), then aura-gated regen, kept out of the
-- regen measurement like our own casts' changes (pinDelta).
I.OnAdvance(function(from, to)
    local dt = to - from
    for r = 1, R.n do
        if R.swing[r] == 0 and R.regH[r] ~= 0 then
            local max = R.max[r]
            R.est0[r] = clamp(R.est0[r] + R.regE[r] * dt, max)
            R.lo0[r] = clamp(R.lo0[r] + R.regL[r] * dt, max)
            R.hi0[r] = clamp(R.hi0[r] + R.regH[r] * dt, max)
        end
    end
    for g = 1, G.n do
        local v = auraGain(g, from, to)
        if v ~= 0 then
            local r = G.slot[g]
            local max = R.max[r]
            R.est0[r] = clamp(R.est0[r] + v, max)
            R.lo0[r] = clamp(R.lo0[r] + v, max)
            R.hi0[r] = clamp(R.hi0[r] + v, max)
            R.pinDelta[r] = R.pinDelta[r] + v
        end
    end
    if fighting then
        return
    end
    -- Out of combat a decaying slot falls toward rest at its decay rate (never below it), kept out of the regen
    -- measurement like the aura-gated ticks.
    for r = 1, R.n do
        local d = R.decay[r]
        -- No decay while a tick-paying player aura is up (Bloodrage: +1/s and no decay for 10 s, in game); it
        -- resumes from the aura's expiry.
        local start = from
        for g = 1, G.n do
            local j = G.aura[g]
            if d > 0 and G.slot[g] == r and j > 0 and I.auras.applied[1][j] <= to then
                local e = I.auras.exp0[1][j]
                if e > to then
                    d = 0
                elseif e > start then
                    start = e
                end
            end
        end
        if d > 0 then
            local rest, drop, before = R.rest[r], d * (to - start), R.est0[r]
            if before > rest then
                R.est0[r] = before - drop > rest and before - drop or rest
            end
            if R.lo0[r] > rest then
                R.lo0[r] = R.lo0[r] - drop > rest and R.lo0[r] - drop or rest
            end
            if R.hi0[r] > rest then
                R.hi0[r] = R.hi0[r] - drop > rest and R.hi0[r] - drop or rest
            end
            if R.est0[r] ~= before then
                R.pinDelta[r] = R.pinDelta[r] + R.est0[r] - before
                I.Sample(R.power[r], "modelled", R.est0[r], to, Obs.CombatEnd)
            end
        end
    end
end)

--- A swing-paid slot's model value per second of swinging: each paying hand's value / its believed speed (a hand
--- with no speed adds nothing). Allocates nothing.
function I.SwingPerSecond(r)
    local per, speed = 0, I.SwingSpeedEst(R.swing[r])
    if speed > 0 then
        per = I.SwingValue(r) / speed -- nonzero: speed > 0 checked
    end
    local off = R.swing[r] == 1 and R.swingOff[r] ~= 0 and I.SwingSpeedEst(2) or 0
    if off > 0 then
        per = per + I.SwingValue(r, 2) / off -- nonzero: off > 0 checked
    end
    return per
end

-- One regen measurement m (per second, between two pins ending at t) into the slot's regen (the EMA, TDF
-- calibrate). A swing-paid slot calibrates its step scale against the spec's value per second of swinging.
local function calibrate(r, m, t)
    local ref
    if R.swing[r] > 0 then
        ref = I.SwingPerSecond(r)
    else
        ref = R.decl[r]
    end
    if ref == 0 then
        return
    end
    local ratio = m / ref -- nonzero: ref ~= 0 checked
    if ratio < 1 / I.REGEN_RATIO or ratio > I.REGEN_RATIO then
        return -- noise: a missed spend, a cap
    end
    if R.swing[r] > 0 then
        local scale = R.scale[r] + I.ALPHA * (ratio - R.scale[r])
        local dev = R.dev[r] + I.ALPHA * (abs(ratio - scale) - R.dev[r])
        R.scale[r], R.dev[r] = scale, dev
        R.spread[r] = dev > I.REGEN_SPREAD_MIN and dev or I.REGEN_SPREAD_MIN
        I.Sample(R.regen[r], "modelled", scale * ref, t, Obs.Usable)
    else
        local est = R.regE[r] + I.ALPHA * (m - R.regE[r])
        local dev = R.dev[r] + I.ALPHA * (abs(m - est) - R.dev[r])
        local floor = abs(ref) * I.REGEN_SPREAD_MIN
        local spread = dev > floor and dev or floor
        R.dev[r] = dev
        R.regE[r], R.regL[r], R.regH[r] = est, est - spread, est + spread
        I.Sample(R.regen[r], "modelled", est, t, Obs.Usable)
    end
end

-- Pins slot r at t to [v, v + width]; when this pin and the previous one both measure (exact, or `mid`), the regen
-- between them is a measurement. `origin` is "pinned" (a usability flip) or "observed" (an exact read).
local function pin(r, v, width, t, origin, event, mid)
    local exact = width <= 0
    local measures = exact or mid == true
    local vm = mid and v + width / 2 or v
    local dt = t - R.pinT[r]
    if measures and R.pinValid[r] and dt >= I.PIN_GAP then
        calibrate(r, (vm - R.pinV[r] - R.pinDelta[r]) / dt, t) -- nonzero: dt >= PIN_GAP (1 s)
    end
    local max = R.max[r]
    R.est0[r], R.lo0[r], R.hi0[r] = clamp(v + width / 2, max), clamp(v, max), clamp(v + width, max)
    R.snapT[r] = -1e9 -- an anchor, not a snap
    R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r] = t, vm, 0, measures
    I.Sample(R.power[r], origin, R.est0[r], t, event)
end

-- One rung of the cost ladder: the resource was at least `c` (affordable) or below it, `lag` before t. A late bound
-- is moved by the most regen could have changed it and dropped if it then conflicts. True when it moved the estimate
-- (a snap: the estimate now stands on this rung, so the caller writes a `pinned` sample).
local function ladder(r, c, affordable, t, lag)
    if lag > 0 and R.swing[r] == 0 then
        if affordable then
            c = c + R.regL[r] * lag
            if c > R.hi0[r] then
                return false
            end
        else
            c = c + R.regH[r] * lag
            if c - I.EPS < R.lo0[r] then
                return false
            end
        end
    end
    local snapped = false
    if affordable then
        if R.lo0[r] < c then
            R.lo0[r] = c
        end
        if R.est0[r] < c then
            R.est0[r], R.snapT[r], snapped = c, t, true
        end
        if R.hi0[r] < c then
            R.hi0[r] = c -- the newest bound wins
        end
    else
        local top = c - I.EPS
        if R.hi0[r] > top then
            R.hi0[r] = top
        end
        if R.est0[r] > top then
            R.est0[r], R.snapT[r], snapped = top, t, true
        end
        if R.lo0[r] > top then
            R.lo0[r] = top < 0 and 0 or top -- the newest bound wins
        end
    end
    return snapped
end
I.Ladder = ladder

I.On(Obs.Usable, function(o, t, lag)
    local a = o.a
    local now = o.b == 1 and YES or (o.c == 1 and SHORT or NOT)
    local was = usable[a]
    usable[a] = now
    local r = I.ab.slot[a]
    if r == 0 or now == NOT or R.readable[r] or I.ab.multiCost[a] then
        return -- a second power cost (Overpower's combo points) makes a short answer ambiguous: no rung
    end
    local c = I.CostOf(a)
    if c <= 0 then
        return
    end
    if was == SHORT and now == YES and lag <= 0 and abs(c - shortCost[a]) <= I.EPS then
        -- It just became affordable at an unchanged cost: it crossed the cost since the last short report.
        if R.swing[r] > 0 then
            -- a swing-paid resource crosses at a swing: [c, c + one step of the larger hand), measured at its midpoint
            local v, off = I.SwingValue(r), R.swingOff[r] ~= 0 and I.SwingValue(r, 2) or 0
            local step = (v > off and v or off) * (R.scale[r] + R.spread[r])
            pin(r, c, step, t, "pinned", Obs.Usable, true)
        else
            local width = R.regH[r] * (t - shortT[a])
            pin(r, c, t - shortT[a] <= I.PIN_EXACT and 0 or width, t, "pinned", Obs.Usable)
        end
    elseif ladder(r, c, now == YES, t, lag) then
        I.Sample(R.power[r], "pinned", R.est0[r], t, Obs.Usable)
    end
    if now == SHORT then
        shortCost[a], shortT[a] = c, t - lag
    end
end)

I.On(Obs.Read, function(o, t, lag)
    local r, c = o.a, o.c
    if c == ReadOf.Resource then
        if I.inCombat then
            R.readable[r] = true -- plain in combat: its exact reads keep it, its spenders' answers are no rungs
        end
        if lag > 0 and R.swing[r] == 0 then
            pin(r, o.b + R.regL[r] * lag, (R.regH[r] - R.regL[r]) * lag, t, "observed", Obs.Read)
        else
            pin(r, o.b, 0, t, "observed", Obs.Read)
        end
    elseif c == ReadOf.Max then
        if o.b > 0 then
            setMax(r, o.b)
            R.maxRead[r] = true -- a plain read wins over the declared maximum from now on
        end
    elseif c == ReadOf.Regen and R.swing[r] == 0 then
        R.decl[r], R.readT[r] = o.b, t
        R.regE[r], R.regL[r], R.regH[r] = o.b, o.b, o.b
        I.Sample(R.regen[r], "observed", o.b, t, Obs.Read)
    end
end)

-- A landed swing pays each slot of its hand one step (the off hand its own value), unless an on-next-swing strike
-- took that swing (spec §6.4).
I.On(Obs.Swing, function(o, t)
    if o.c ~= 1 then
        return
    end
    local hand = o.a
    for r = 1, R.n do
        local pays = R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0)
        if pays and not (hand == 1 and I.queuedStrike) then
            local v, max = I.SwingValue(r, hand), R.max[r]
            local s, sp = R.scale[r], R.spread[r]
            R.est0[r] = clamp(R.est0[r] + v * s, max)
            R.lo0[r] = clamp(R.lo0[r] + v * (s - sp), max)
            R.hi0[r] = clamp(R.hi0[r] + v * (s + sp), max)
            I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
        end
    end
end)

-- Our own cast succeeded: the game had its cost (a rung); Families/Now.lua then pays it. An on-next-swing strike's
-- success arrives with its swing, where Now.lua pays it, so its press says nothing here.
I.On(Obs.CastSuccess, function(o, t, lag)
    local a = o.a
    local r = I.ab.slot[a]
    if r == 0 or I.ab.obj[a].onNextSwing then
        return
    end
    local c = I.CostOf(a)
    if c > 0 and ladder(r, c, true, t, lag) then
        I.Sample(R.power[r], "pinned", R.est0[r], t, Obs.CastSuccess)
    end
end)

I.On(Obs.CombatStart, function(o, t)
    fighting, fightT = true, t
end)

-- Out of combat a resource falls toward its rest value: the interval opens down to it (lo never over-promises), and
-- a decaying slot's rate is re-read.
I.On(Obs.CombatEnd, function()
    fighting = false
    for r = 1, R.n do
        R.decay[r] = decayOf(r)
        if not R.maxRead[r] then
            setMax(r, maxOf(r))
        end
        if R.rest[r] < R.lo0[r] then
            R.lo0[r] = R.rest[r]
        end
        R.pinValid[r] = false
    end
end)

--- Our own cast changed slot r by `delta` at t (spec §5.3): the interval moves by the same amount, written as a
--- `modelled` sample. Allocates nothing.
function I.ResourceShift(r, delta, t, event)
    local max = R.max[r]
    R.est0[r] = clamp(R.est0[r] + delta, max)
    R.lo0[r] = clamp(R.lo0[r] + delta, max)
    R.hi0[r] = clamp(R.hi0[r] + delta, max)
    R.pinDelta[r] = R.pinDelta[r] + delta
    I.Sample(R.power[r], "modelled", R.est0[r], t, event)
end

--- (spec §3.2) The believed amount of a power type at `now`: the clock values plus continuous regen x dt and the
--- aura-gated ticks to `now`, each clamped to [0, max]; conf 1 - (hi - lo) / max, halved within SNAP_HOLD of a snap.
--- Allocates nothing.
function VS.Power(powerType, now)
    local r = R.slotOf[powerType]
    if not r then
        return I.UNKNOWN
    end
    local rec, max, dt = R.power[r], R.max[r], I.Dt(now)
    if R.swing[r] > 0 then
        dt = 0 -- a swing-paid resource moves only at swings
    end
    local gain = 0
    if now > I.clock then
        for g = 1, G.n do
            if G.slot[g] == r then
                gain = gain + auraGain(g, I.clock, now)
            end
        end
    end
    local est = clamp(R.est0[r] + R.regE[r] * dt + gain, max)
    local lo = clamp(R.lo0[r] + R.regL[r] * dt + gain, max)
    local hi = clamp(R.hi0[r] + R.regH[r] * dt + gain, max)
    if lo > est then
        lo = est
    end
    if hi < est then
        hi = est
    end
    rec.est, rec.lo, rec.hi = est, lo, hi
    local conf = 1 - (hi - lo) / max -- nonzero: max > 0 (the default 100, or a plain read above 0)
    if now - R.snapT[r] < I.SNAP_HOLD then
        conf = conf * 0.5
    end
    rec.conf = conf
    return rec
end

--- (spec §3.2) The believed regen per second of a power type. A swing-paid resource's is its calibrated step per
--- second of swinging. `casting` selects the in-cast rate (Phase 1 has one rate). Allocates nothing.
function VS.Regen(powerType, now, casting)
    local r = R.slotOf[powerType]
    if not r then
        return I.UNKNOWN
    end
    local rec = R.regen[r]
    if R.swing[r] > 0 then
        local per = I.SwingPerSecond(r)
        local s, sp = R.scale[r], R.spread[r]
        rec.est, rec.lo, rec.hi = per * s, per * (s - sp), per * (s + sp)
        rec.conf = s > 0 and 1 - sp / s or 0 -- nonzero: s > 0 checked
    else
        local est = R.regE[r]
        rec.est, rec.lo, rec.hi = est, R.regL[r], R.regH[r]
        local conf = est ~= 0 and 1 - (R.regH[r] - est) / abs(est) or 0 -- nonzero: est ~= 0 checked
        rec.conf = conf < 0 and 0 or conf
    end
    return rec
end

I.OnSnapshot(function(out, now)
    for r = 1, R.n do
        VS.Power(R.type[r], now)
        VS.Regen(R.type[r], now)
        out[#out + 1] = string.format(
            "resource %s type=%d max=%d swing=%d scale=%.2f auraRegen=%d decay=%g",
            tostring(R.token[r]),
            R.type[r],
            R.max[r],
            R.swing[r],
            R.scale[r],
            G.n,
            R.decay[r]
        )
    end
end)
