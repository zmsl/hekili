-- Virtual/State/Families/Resources.lua
-- The resources family (spec §6.1): the cost ladder (a usability report pins or bounds a resource at the ability's
-- cost), exact reads, regen calibration between pins (an EMA), swing steps for a swing-paid resource (rage), our own
-- casts' changes (Adapter.lua, spec §5.3), periodic regen (Hekili's regen-model entries with `interval` and `value`:
-- with an `aura`, Bloodrage's rage over time; without one, in combat: Anger Management), the gain from a hit on the
-- player (the paying entry's `taken`, tank design §1.2) and its learned rate, and the Power/Regen accessors.
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
-- -1: named but not tracked, so no swing pays); `swingCrit[r]` / `swingOffCrit[r]` the extra a critical white hit of
-- that hand adds (0: none). Continuous regen is per second (regE/regL/regH); a swing-paid
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
    swingCrit = {},
    swingOffCrit = {},
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
    decayIv = {},
    decayNext = {},
    maxDef = {},
    maxMods = {},
    maxRead = {},
    gain = {},
    taken = {},
    takenBin = {},
    takenSec = {},
}
I.res = R
R.slotOf, R.slotOfToken = {}, {}

-- Periodic regen entries g of every slot (built from each resource's `auraRegen`): `value` every `interval` seconds
-- from the aura's application while the player's aura j is believed up, or (no aura: j = 0) from the combat start
-- while in combat (Anger Management); an entry with a `talent` only while that talent has a rank. Credited only as
-- the clock moves on: an aura first seen after its application loses the ticks before that, and a removal seen late
-- keeps the ticks already credited; both are bounded by the aura's duration and the next pin or rung corrects them.
-- Whether each hand's last landed swing paid (no on-next-swing strike took it): its crit pays only then.
-- The share of each hand's swings that land: an EMA over swings (a swing, c = 4, decays it; a landed one, c = 1, adds
-- HIT_ALPHA). It scales the model's swing rate, so the step scale calibrates the value of a landed swing.
local hitRate, HIT_ALPHA = { 1, 1 }, 0.1
local G = { n = 0, slot = {}, aura = {}, value = {}, interval = {}, talent = {}, pause = {} }
-- `taken[r]`: the paying entry's `taken(kind, amount, level)` bound to the `now` context (Families/Now.lua), or false.
-- Its gains in one-second bins: `takenBin[r][i]` the gain of the second `takenSec[r][i]` (-1: empty), i = sec % 10 + 1.
I.TAKEN_WINDOW = 10
-- In combat (fold order, for the entries without an aura: aura index 0) and since when.
local fighting, fightT = false, 0
R.auraRegen = G

-- Slot r's out-of-combat loss per second from its `decay` (a number or a state-bound function; absent: none),
-- evaluated at the build and at each combat end (talent ranks change out of combat only). With a `decayInterval`
-- (seconds, `decayIv[r]`; 0: continuous) it is lost in quanta of decay x interval, the first at once when the decay
-- starts and one at the start of each interval after it (`decayNext[r]`: the next one's time, 0 while inactive;
-- stepped-decay design §3.2). Allocates nothing.
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

-- By ability index a: the last usability answer and the last short report (cost, time, the slot's own gains so far
-- and its estimate then).
local usable, shortCost, shortT, shortGain, shortEst = {}, {}, {}, {}, {}

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
    hitRate[1], hitRate[2] = 1, 1
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
        R.swingCrit[r], R.swingOffCrit[r] = d.swingCrit or 0, d.swingOffCrit or 0
        R.est0[r], R.lo0[r], R.hi0[r] = R.rest[r], 0, R.max[r]
        local rate = d.regen or 0
        R.decl[r] = rate
        R.regE[r], R.regL[r], R.regH[r] = rate, rate * (1 - I.REGEN_SPREAD), rate * (1 + I.REGEN_SPREAD)
        R.dev[r], R.scale[r], R.spread[r] = 0, 1, I.REGEN_SPREAD
        R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r], R.gain[r] = 0, 0, 0, false, 0
        R.snapT[r], R.readT[r], R.readable[r] = -1e9, -1e9, false
        R.decayDef[r] = d.decay
        R.decay[r] = decayOf(r)
        local iv = eval(d.decayInterval)
        R.decayIv[r], R.decayNext[r] = type(iv) == "number" and iv > 0 and iv or 0, 0
        R.taken[r] = type(d.taken) == "function" and setfenv(d.taken, I.nowCtx) or false
        R.takenBin[r], R.takenSec[r] = {}, {}
        for i = 1, I.TAKEN_WINDOW do
            R.takenBin[r][i], R.takenSec[r][i] = 0, -1
        end
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
                G.talent[G.n], G.pause[G.n] = tid, e.pausesDecay == true
            end
        end
    end
    for a = 1, #def.abilities do
        usable[a], shortCost[a], shortT[a], shortGain[a], shortEst[a] = UNKNOWN, 0, 0, 0, 0
    end
end)

-- Slot r's `main` or (the off hand of a main-hand slot) `off` field for `hand`: a number, or the model's state-bound
-- function; 0 while the slot's swing aura is not believed up at the clock (its application after it, or its expiry at
-- or before it). Allocates nothing.
local function perSwing(r, hand, main, off)
    local j = R.swingAura[r]
    if j < 0 or j > 0 and (I.auras.exp0[1][j] <= I.clock or I.auras.applied[1][j] > I.clock) then
        return 0 -- unit 1 is always "player" (Adapter.lua's def.units)
    end
    local v = main[r]
    if hand == 2 and R.swing[r] == 1 then
        v = off[r]
    end
    if type(v) == "function" then
        v = v(I.clock)
    end
    return type(v) == "number" and v or 0
end

--- The spec's per-swing value of a swing-paid slot for `hand` (2: the off hand's `swingOff`; else the paying hand's),
--- 0 while its swing aura is down. Allocates nothing.
function I.SwingValue(r, hand)
    return perSwing(r, hand, R.swingValue, R.swingOff)
end

--- The spec's white-crit extra of a swing-paid slot for `hand` (its swing entry's `crit`), as I.SwingValue.
function I.SwingCrit(r, hand)
    return perSwing(r, hand, R.swingCrit, R.swingOffCrit)
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

-- No decay while a `pausesDecay` entry's player aura of slot r is up (Bloodrage: +1/s and no decay for 10 s, in game):
-- false while one is up through `to`, else when in (from, to] the decay runs from (the latest expiry in it, or `from`).
local function decayFrom(r, from, to)
    local start = from
    for g = 1, G.n do
        local j, tid = G.aura[g], G.talent[g]
        local learned = tid == 0 or VS.Talent(tid) ~= 0 -- auraGain's talent gate
        if learned and G.pause[g] and G.slot[g] == r and j > 0 and I.auras.applied[1][j] <= to then
            local e = I.auras.exp0[1][j]
            if e > to then
                return false
            elseif e > start then
                start = e
            end
        end
    end
    return start
end

-- One stepped decay quantum of slot r at t: the interval down by decay x interval, never below rest, as a `modelled`
-- sample at t, kept out of the regen measurement; the next one an interval later, none once the estimate rests.
local function beat(r, t)
    local rest, step, before = R.rest[r], R.decay[r] * R.decayIv[r], R.est0[r]
    if before > rest then
        R.est0[r] = before - step > rest and before - step or rest
    end
    if R.lo0[r] > rest then
        R.lo0[r] = R.lo0[r] - step > rest and R.lo0[r] - step or rest
    end
    if R.hi0[r] > rest then
        R.hi0[r] = R.hi0[r] - step > rest and R.hi0[r] - step or rest
    end
    if R.est0[r] ~= before then
        R.pinDelta[r] = R.pinDelta[r] + R.est0[r] - before
        I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.CombatEnd)
    end
    R.decayNext[r] = R.est0[r] > rest and t + R.decayIv[r] or 0
end

-- Continuous regen between pins (swing-paid slots move only at swings), then aura-gated regen, kept out of the
-- regen measurement like our own casts' changes (pinDelta), then the decay: ticks before quanta at the same instant.
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
    -- measurement like the aura-gated ticks; it resumes from a tick aura's expiry.
    for r = 1, R.n do
        local d = R.decay[r]
        local start = d > 0 and decayFrom(r, from, to)
        if R.decayIv[r] > 0 then
            if not start then
                R.decayNext[r] = 0
            elseif start > from or R.decayNext[r] == 0 and R.est0[r] > R.rest[r] then
                R.decayNext[r] = start -- it starts: at a tick aura's expiry, or at a rise above rest
            end
            while R.decayNext[r] > 0 and R.decayNext[r] <= to do
                beat(r, R.decayNext[r])
            end
        elseif start then
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

--- A swing-paid slot's model value per second of swinging: each paying hand's value x its hit rate / its believed
--- speed (a hand with no speed adds nothing). Allocates nothing.
function I.SwingPerSecond(r)
    local h = R.swing[r]
    local per, speed = 0, I.SwingSpeedEst(h)
    if speed > 0 then
        per = I.SwingValue(r) * hitRate[h] / speed -- nonzero: speed > 0 checked
    end
    local off = h == 1 and R.swingOff[r] ~= 0 and I.SwingSpeedEst(2) or 0
    if off > 0 then
        per = per + I.SwingValue(r, 2) * hitRate[2] / off -- nonzero: off > 0 checked
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
-- between them is a measurement. `origin` is "pinned" (a usability flip) or "observed" (an exact read). A wide flip
-- is a bound: it clamps the estimate into the range, never moves one already inside it; a read takes the midpoint.
local function pin(r, v, width, t, origin, event, mid)
    local exact = width <= 0
    local measures = exact or mid == true
    local vm = mid and v + width / 2 or v
    local dt = t - R.pinT[r]
    if measures and R.pinValid[r] and dt >= I.PIN_GAP then
        calibrate(r, (vm - R.pinV[r] - R.pinDelta[r]) / dt, t) -- nonzero: dt >= PIN_GAP (1 s)
    end
    local max = R.max[r]
    local est = v + width / 2
    if origin == "pinned" then
        est = R.est0[r] < v and v or (R.est0[r] > v + width and v + width or R.est0[r])
    end
    R.est0[r], R.lo0[r], R.hi0[r] = clamp(est, max), clamp(v, max), clamp(v + width, max)
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
        if R.gain[r] - shortGain[a] >= c - shortEst[a] then
            -- our own gain since then explains the crossing: exact at the estimate (at least c), no regen measurement
            local e = R.est0[r]
            R.pinValid[r] = false
            pin(r, e > c and e or c, 0, t, "pinned", Obs.Usable)
            R.pinValid[r] = false
        elseif R.swing[r] > 0 then
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
        shortCost[a], shortT[a], shortGain[a], shortEst[a] = c, t - lag, R.gain[r], R.est0[r]
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

-- A landed swing (c = 1: Events/Rows.lua paired the target's wound with our white swing, so never an avoid and never
-- a swing an on-next-swing strike took) pays each slot of its hand one step (the off hand its own value). It is
-- staged when the wound arrives, one swing's lag after PLAYER_SWING (about 0.45 s main, about 1 s off, research
-- 2026-10-16-swing-outcome-pairing): believed rage trails the game's by that step, and lo stays a floor. Its crit
-- (c = 3, the same pairing with a CRITICAL wound, right after its c = 1) adds the hand's `crit` once more, unscaled (an
-- exact, documented amount; the scale absorbs the model's error). A swing (c = 4) pays nothing; it and c = 1
-- keep the hand's hit rate.
I.On(Obs.Swing, function(o, t)
    local hand, c = o.a, o.c
    if hand ~= 1 and hand ~= 2 then
        return
    elseif c == 4 then
        hitRate[hand] = hitRate[hand] * (1 - HIT_ALPHA)
        return
    elseif c == 1 then
        local h = hitRate[hand] + HIT_ALPHA
        hitRate[hand] = h < 1 and h or 1
    elseif c ~= 3 then
        return
    end
    for r = 1, R.n do
        if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
            local max, v, s, sp = R.max[r], 0, 1, 0
            if c == 1 then
                v, s, sp = I.SwingValue(r, hand), R.scale[r], R.spread[r]
            else
                v = I.SwingCrit(r, hand)
            end
            if c == 1 or v ~= 0 then -- a slot with no `crit` takes no sample for a crit
                R.est0[r] = clamp(R.est0[r] + v * s, max)
                R.lo0[r] = clamp(R.lo0[r] + v * (s - sp), max)
                R.hi0[r] = clamp(R.hi0[r] + v * (s + sp), max)
                I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
            end
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

-- A hit on the player (kinds 1-6; a heal brings no rage): each slot with a `taken` gains what it returns, the interval
-- by its half-width (lo never below the estimate's gain minus it), clamped to [0, max]; kept out of the regen
-- measurement and counted as our own gain (a flip it explains pins exactly, as I.ResourceShift's); one `modelled`
-- sample at the hit, and the gain into its second's bin. A `taken` that raises is counted as a `now`'s error.
I.On(Obs.PlayerHit, function(o, t)
    local kind = o.a
    if kind < I.HitKind.WOUND or kind > I.HitKind.MISS then
        return
    end
    for r = 1, R.n do
        local f = R.taken[r]
        if f then
            I.NowAt(t)
            local ok, gain, width = pcall(f, I.HitName[kind], o.b, o.c)
            if not ok then
                I.nowErrors, I.nowError = I.nowErrors + 1, gain
            elseif type(gain) == "number" and gain > 0 then
                width = type(width) == "number" and width > 0 and width or 0
                local max = R.max[r]
                R.est0[r] = clamp(R.est0[r] + gain, max)
                R.lo0[r] = clamp(R.lo0[r] + (gain > width and gain - width or 0), max)
                R.hi0[r] = clamp(R.hi0[r] + gain + width, max)
                R.pinDelta[r], R.gain[r] = R.pinDelta[r] + gain, R.gain[r] + gain
                I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.PlayerHit)
                local sec = floor(t)
                local i = sec % I.TAKEN_WINDOW + 1
                local bin, stamp = R.takenBin[r], R.takenSec[r]
                if stamp[i] ~= sec then
                    bin[i], stamp[i] = 0, sec
                end
                bin[i] = bin[i] + gain
            end
        end
    end
end)

--- (tank design §1.2.4) A power type's learned gain per second from hits on the player: its `taken` gains of
--- the last TAKEN_WINDOW whole seconds to `now` / TAKEN_WINDOW, in combat only (0 out of combat, or with no `taken`).
--- Allocates nothing.
function VS.TakenRate(powerType, now)
    local r = R.slotOf[powerType]
    if not r or not R.taken[r] or not fighting then
        return 0
    end
    local sec, sum, bin, stamp = floor(now), 0, R.takenBin[r], R.takenSec[r]
    for i = 1, I.TAKEN_WINDOW do
        if stamp[i] > sec - I.TAKEN_WINDOW and stamp[i] <= sec then
            sum = sum + bin[i]
        end
    end
    return sum / I.TAKEN_WINDOW -- nonzero: a constant
end

I.On(Obs.CombatStart, function(o, t)
    fighting, fightT = true, t
    for r = 1, R.n do
        R.decayNext[r] = 0
    end
end)

-- Out of combat a resource falls toward its rest value: the interval opens down to it (lo never over-promises), and
-- a decaying slot's rate is re-read; a stepped one loses its first quantum at once (front-loaded).
I.On(Obs.CombatEnd, function(o, t)
    fighting = false
    for r = 1, R.n do
        for i = 1, I.TAKEN_WINDOW do
            R.takenSec[r][i] = -1
        end
        R.decay[r] = decayOf(r)
        if not R.maxRead[r] then
            setMax(r, maxOf(r))
        end
        if R.rest[r] < R.lo0[r] then
            R.lo0[r] = R.rest[r]
        end
        R.pinValid[r] = false
        local stepped = R.decayIv[r] > 0 and R.decayNext[r] == 0 and R.decay[r] > 0
        if stepped and R.est0[r] > R.rest[r] and decayFrom(r, t, t) then
            beat(r, t)
        end
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
    if delta > 0 then
        R.gain[r] = R.gain[r] + delta -- explains a flip (the Usable apply)
    end
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

--- (stepped-decay design §3.3) The time of a power type's last stepped decay quantum, the anchor of the sim's
--- `__decay` entry (Adapter.lua): 0 while its decay is inactive or continuous, or the type untracked. Allocates nothing.
function VS.DecayAnchor(powerType)
    local r = R.slotOf[powerType]
    local n = r and R.decayNext[r] or 0
    return n > 0 and n - R.decayIv[r] or 0
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
