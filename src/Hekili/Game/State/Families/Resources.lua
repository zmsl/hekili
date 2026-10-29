-- Game/State/Families/Resources.lua
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
local Stats = I.Stats

--- A flip pin measures regen only when the last short report was at most this long before it (TDF Belief.PIN_EXACT).
I.PIN_EXACT = 0.15
--- Seconds a cast's declared gain (its `now`'s `gain`) takes to reach the client's usability answers (the harness's
--- usableDelay, UNMEASURED until G7): a short answer read sooner that the gain lifts past the cost predates it (a
--- same-frame press after Bloodrage), so it is no rung. A refund and a hit's `taken` rage are estimates the answer may
--- correct, so they do not count (both raised the loops' flicker: Guardian 3.35 -> 3.52, Fury 1.77 -> 1.96).
I.GAIN_SHOWS = 0.1
--- A swing-paid slot's scale is measured over at least this many model steps of its paying hand (GAP AC).
I.SWING_STEPS = 5

-- Usability as observed: unknown, not usable, usable, not usable for lack of its resource.
local UNKNOWN, NOT, YES, SHORT = -1, 0, 1, 2

-- By resource slot r. `swing[r]` is the hand that pays it (1 main, 2 off; 0: continuous regen) and `swingOff[r]` the
-- off hand's own value when both hands pay it (0: none); `swingAura[r]` the player aura index its swings need (0: none;
-- -1: named but not tracked, so no swing pays); `swingCrit[r]` / `swingOffCrit[r]` the extra a critical white hit of
-- that hand adds (0: none). Continuous regen is per second (regE/regL/regH); a swing-paid
-- resource's step is the spec's model value of that hand x scale (spread around it). `restMax[r]`: a regenerating
-- resource rests at its maximum (energy, mana), the others at 0 (rage).
-- The five-second rule (C3): a slot with an `fsr` meta splits its continuous regen in two parts, each with its own
-- calibrated state: the `mp5` part (regE/regL/regH, decl, dev) always, the `spirit` part (spE/spL/spH, spDecl, spDev;
-- 0 for every other slot) only outside the window our own spend opens (`fsrUntil[r]`: its end, I.FSR after the
-- spend); `share[r]` (c, 0-1): the static casting share the learned split already holds (the `fsr` meta's `share`), so
-- the mp5 part is wowsims's casting rate M + cS and the spirit part (1 - c)S. `shaped[r]`: the slot has an `fsr` or a
-- regen entry (else its regen is the plain rate x dt). `pinA[r]` / `pinB[r]`: the integrals of each part's weight
-- (coefAt's fa and fb) since the last pin (the calibration's weights).
-- `liftE/L/H[r]` and `liftT[r]`: how far a rung lifted a swing-paid slot's est, lo and hi (our cast's success, a usable
-- answer, a flip's pin: the game held more than we believed) and the latest lifting rung's time; a landed swing at or
-- before it pays that much less (owe, I.On(Obs.Swing)). `liftRec[r]`: the credit record that paid from it (its crit
-- may pay the rest).
-- `sinceShort[r]`: the lowest top a short answer set since our last spend from slot r (math.huge: none), and the
-- estimate just after it (`sinceShortEst[r]`: what the slot gained since moves that top with it); `sinceYes[r]` /
-- `sinceSnap[r]`: whether a usable answer raised its floor / its estimate since then. An avoided cast's refund
-- (I.Refund) is dated at that cast: the answers heard since already saw it.
-- `over[r]`: how far the modelled floor sits above the measured one (lo0): a regenerating slot that rests at its
-- maximum is built at rest (est, and this floor: lo0 + over), and the floor then moves with everything that moves lo0;
-- a measurement the floor contradicts (a short answer below it, a pin's top under it, an exact read) drops it to lo0
-- for good (`assume[r]` false: the rest assumption is over; a usable answer above it only raises lo0).
-- Without it a slot never read plainly (mana, secret even out of combat) holds the dearest usable cost as its floor.
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
    fsr = {},
    fsrUntil = {},
    share = {},
    shareDef = {}, -- the fsr share as declared (a number or a function)
    spE = {},
    spL = {},
    spH = {},
    spDecl = {},
    spDev = {},
    shaped = {},
    pinA = {},
    pinB = {},
    scale = {},
    spread = {},
    pinT = {},
    pinV = {},
    pinDelta = {},
    pinValid = {},
    pinOwn = {},
    ownT = {}, -- our latest cast gain's time (ownGain), and what we gained within I.GAIN_SHOWS of it
    ownV = {},
    swFrom = {},
    skipFrom = {},
    skipTo = {},
    pinSkip = {},
    swAccG = {},
    swAccT = {},
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
    castGain = {}, -- the part of `gain` that is our casts' declared gains (trusted, unlike a refund or a hit's estimate)
    crossT = {}, -- the instant of the latest crossed() and lo before its first flip there (estimated gain given up once)
    crossLo = {},
    taken = {},
    takenBin = {},
    takenSec = {},
    spends = {},
    liftE = {},
    liftL = {},
    liftH = {},
    liftT = {},
    liftRec = {},
    sinceShort = {},
    sinceShortEst = {},
    sinceYes = {},
    sinceSnap = {},
    over = {},
    assume = {},
    pinN = {}, -- the fight's flips at an unchanged cost (the providers audit, I.PinError)
    pinErr = {}, -- and the sum of |estimate before the flip - cost| over them
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
local G = { n = 0, slot = {}, aura = {}, value = {}, interval = {}, talent = {}, pause = {}, def = {} }
-- `taken[r]`: the paying entry's `taken(kind, amount, level)` bound to the `now` context (Families/Now.lua), or false.
-- Its gains in one-second bins: `takenBin[r][i]` the gain of the second `takenSec[r][i]` (-1: empty), i = sec % 10 + 1.
I.TAKEN_WINDOW = 10
-- In combat (fold order, for the entries without an aura: aura index 0) and since when.
local fighting, fightT = false, 0
R.auraRegen = G
-- Regen entries (C3b, built from each resource's `mult` list), wowsims's mana PseudoStats while the player's aura j is
-- believed up: `mult` the whole rate x n (default 1), `spirit` the spirit regen x m (default 1), `share` + s of the
-- spirit regen while casting (default 0; capped with the slot's static share at all of it), `mp5` + x a second in and
-- out of the window (default 0). See coefAt.
local M = { n = 0, slot = {}, aura = {}, mult = {}, spirit = {}, share = {}, mp5 = {}, spiritDef = {}, mp5Def = {} }
R.regenMult = M
--- The five-second rule's window after our own spend of an `fsr` slot, in seconds.
I.FSR = 5

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

-- By ability index a: the last usability answer and its time (`ansT`), and the last short report (cost, time, the slot's
-- own gains so far, the cast-declared part of them, and its estimate then).
local usable, ansT, shortCost, shortT, shortGain, shortCast, shortEst = {}, {}, {}, {}, {}, {}, {}
-- Per hand (1 main, 2 off): the swing-paid slot's estimate and floor at its latest PLAYER_SWING, that swing's time,
-- the lowest top a short answer set from ORACLE_MIN after it (math.huge: none) and the slot's spend count then (I.Missed).
local swE, swL, swT, swTop, swSp = { 0, 0 }, { 0, 0 }, { -1, -1 }, { math.huge, math.huge }, { 0, 0 }
local heardT = 0 -- the latest usability answer's time that set a rung above its slot's floor
-- By ability index: its ladder precondition (C9): false for `ladder = false` (its answers are no rungs), its `usable`
-- function (a short answer while it fails names another requirement, such as a finisher's combo points), or true.
local pre = {}

-- The usability oracle (harness design §2): per credit record k (Events/Rows.lua's record id, a landed swing's `b`),
-- the slot it paid (0: none), the hand, est, lo and hi before it and the deltas it added (its crit included), its
-- hit-rate step, the ability whose next answer judges it (0: not judged: it crossed no rung), whether the prediction
-- is firm (the post-credit floor reaches the cost) and the slot's spend count at the credit. Rows registers
-- I.CreditVerdict.
local RECORDS = 8
local recR, recHand, recEst, recLo, recHi, recHit, recA, recFirm, recSpends = {}, {}, {}, {}, {}, {}, {}, {}, {}
local recE0, recLo0, recHi0 = {}, {}, {}
-- Per record also: the estimate its crossing is judged from (`recX0`: the slot's at the swing, before any rung lifted it
-- for that swing's rage; else recE0), the swing's time (`recSw`) and whether it still awaits the look-back at the
-- answers heard since its swing (`recLook`, done at the fold's end, after its crit).
local recX0, recSw, recLook = {}, {}, {}
-- Per record: the share of a step its assumption added (attribution-recovery decision 52; Obs.Swing c = 5), so its
-- confirmation (c = 7) adds the rest.
local recAsm = {}
for k = 1, RECORDS do
    recX0[k], recSw[k], recLook[k], recAsm[k] = 0, 0, false, 1
    recR[k], recHand[k], recEst[k], recLo[k], recHi[k], recHit[k], recA[k] = 0, 0, 0, 0, 0, 0, 0
    recFirm[k], recSpends[k], recE0[k], recLo0[k], recHi0[k] = false, 0, 0, 0, 0
end
-- Per slot: est still owed back by a retraction (attribution-recovery spec §2.4, the hold): applied at the slot's next
-- usability answer or spend (I.SettleDebt), dropped at combat end. Filled at build.
local estDebt = {}
-- Per record: its credit is measured (a verdict consumed it, or a spend of ours from its slot voided it): no
-- retraction can take it back, so its provisional swing is final (I.CreditFixed).
local recGone = {}
for k = 1, RECORDS do
    recGone[k] = false
end

--- Whether credit record k can no longer be taken back (attribution-recovery spec §2.3: a verdict or a spend of ours
--- from its slot measured the pool). Allocates nothing.
function I.CreditFixed(k)
    local s = recR[k]
    return recGone[k] or (s ~= nil and s > 0 and R.spends[s] ~= recSpends[k])
end

local function clamp(v, max)
    if v < 0 then
        return 0
    elseif v > max then
        return max
    end
    return v
end

-- Slot r's modelled floor (lo0 + over) kept at or under the maximum. Allocates nothing.
local function norm(r)
    local room = R.max[r] - R.lo0[r]
    if R.over[r] > room then
        R.over[r] = room > 0 and room or 0
    end
end

-- A cast's declared gain into slot r at t (I.GAIN_SHOWS). Allocates nothing.
local function ownGain(r, delta, t)
    R.ownV[r] = t - R.ownT[r] < I.GAIN_SHOWS and R.ownV[r] + delta or delta
    R.ownT[r] = t
end

local keepFloor = false -- the Usable apply's: this short answer leaves the modelled floor (I.GAIN_SHOWS)
-- After a measurement moved lo0, slot r's modelled floor (`was`, lo0 + over before it), if any, stays where it was
-- unless the measurement's top `top` falls under it (then it is lo0). Allocates nothing.
local function remeasure(r, was, top)
    if not R.assume[r] then
        return -- no modelled floor: a measurement moves lo0 alone, as before
    end
    if top < was - I.EPS and not keepFloor then
        R.assume[r], R.over[r] = false, 0
        return
    end
    local o = was - R.lo0[r]
    R.over[r] = o > 0 and o or 0
    norm(r)
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
        -- the capped-away amount stays out of the regen measurement
        R.pinDelta[r], R.pinOwn[r] = R.pinDelta[r] + R.est0[r] - before, true
        norm(r)
    end
    if R.restMax[r] then
        R.rest[r] = m
        if up > 0 then
            if R.assume[r] and R.lo0[r] + R.over[r] >= m - up - I.EPS then
                R.over[r] = m - R.lo0[r] -- the modelled floor was at rest: it rests at the new maximum
                norm(r)
            end
            R.est0[r] = clamp(R.est0[r] + up, m)
            R.hi0[r] = clamp(R.hi0[r] + up, m)
            R.pinDelta[r], R.pinOwn[r] = R.pinDelta[r] + up, true
        end
    end
end

-- Re-reads every function-valued regen field (a number is read as it stands) into the number arrays; a result that is
-- not a valid number makes the field inert. Called at the build and at each combat start only: the functions read
-- state (a pack's Spirit, max mana), which does not move mid-fight.
local function finite(v)
    if type(v) == "function" then
        local ok, r = pcall(v) -- a pack function may error before the first stat read: inert
        v = ok and r or nil
    end
    return type(v) == "number" and v == v and v > -math.huge and v < math.huge and v or nil
end

local function refresh()
    for r = 1, R.n do
        local c = finite(R.shareDef[r]) or 0
        R.share[r] = c < 0 and 0 or c > 1 and 1 or c
    end
    for i = 1, M.n do
        local m, x = finite(M.spiritDef[i]), finite(M.mp5Def[i])
        M.spirit[i] = m and m > 0 and m or 1
        M.mp5[i] = x and x > 0 and x or 0
    end
    for g = 1, G.n do
        local v = finite(G.def[g])
        G.value[g] = v and v >= 0 and v or 0
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
        estDebt[r] = 0
        R.assume[r] = R.restMax[r] and R.swing[r] == 0
        R.over[r] = R.assume[r] and R.rest[r] or 0 -- the floor at rest too (over)
        local fsr = type(d.fsr) == "table" and d.fsr or false
        local rate, spirit = d.regen or 0, 0
        if fsr then
            rate, spirit = eval(fsr.mp5), eval(fsr.spirit)
            rate, spirit = type(rate) == "number" and rate or 0, type(spirit) == "number" and spirit or 0
        end
        R.fsr[r], R.fsrUntil[r], R.shaped[r], R.pinA[r], R.pinB[r] = fsr ~= false, 0, fsr ~= false, 0, 0
        R.shareDef[r] = fsr and fsr.share
        R.decl[r] = rate
        R.regE[r], R.regL[r], R.regH[r] = rate, rate * (1 - I.REGEN_SPREAD), rate * (1 + I.REGEN_SPREAD)
        R.spDecl[r], R.spDev[r] = spirit, 0
        R.spE[r], R.spL[r], R.spH[r] = spirit, spirit * (1 - I.REGEN_SPREAD), spirit * (1 + I.REGEN_SPREAD)
        R.dev[r], R.scale[r], R.spread[r] = 0, 1, I.REGEN_SPREAD
        R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r], R.gain[r], R.spends[r] = 0, 0, 0, false, 0, 0
        R.pinOwn[r], R.pinSkip[r], R.swFrom[r], R.skipFrom[r], R.skipTo[r] = false, false, 0, 0, 0
        R.swAccG[r], R.swAccT[r] = 0, 0
        R.ownT[r], R.ownV[r], R.castGain[r] = -1e9, 0, 0
        R.crossT[r], R.crossLo[r] = -1e9, 0
        R.pinN[r], R.pinErr[r] = 0, 0
        R.liftE[r], R.liftL[r], R.liftH[r], R.liftT[r], R.liftRec[r] = 0, 0, 0, -1e9, 0
        R.sinceShort[r], R.sinceShortEst[r], R.sinceYes[r], R.sinceSnap[r] = math.huge, 0, false, false
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
        I.Sample(R.regen[r], "default", rate + spirit, now, 0)
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
    G.n, M.n = 0, 0
    for r = 1, R.n do
        local entries = list[r].mult
        for k = 1, entries and #entries or 0 do
            local e = entries[k]
            -- each field valid or its default (a mult or spirit of 0 or less: the out-of-combat read divides by it); a
            -- function spirit or mp5 is read here once
            local f, sh, m, x = e.mult, e.share, e.spirit, e.mp5
            f = type(f) == "number" and f > 0 and f or nil
            sh = type(sh) == "number" and sh > 0 and sh <= 1 and sh or nil
            local live = f
                or sh
                or type(m) == "function"
                or type(m) == "number" and m > 0
                or type(x) == "function"
                or type(x) == "number" and x > 0 -- a function may become valid at a pull
            for i = 1, live and #def.auras or 0 do
                if def.auras[i].key == e.aura then
                    M.n = M.n + 1
                    M.slot[M.n], M.aura[M.n] = r, i
                    M.mult[M.n], M.share[M.n], M.spiritDef[M.n], M.mp5Def[M.n] = f or 1, sh or 0, m, x
                    R.shaped[r] = true
                end
            end
        end
    end
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
            local ok = (type(e.value) == "number" or type(e.value) == "function")
                and type(e.interval) == "number"
                and e.interval > 0
            if ok and j >= 0 and tid >= 0 then
                G.n = G.n + 1
                G.slot[G.n], G.aura[G.n], G.def[G.n], G.interval[G.n] = r, j, e.value, e.interval
                G.talent[G.n], G.pause[G.n] = tid, e.pausesDecay == true
            end
        end
    end
    refresh()
    for a = 1, #def.abilities do
        usable[a], ansT[a], shortCost[a], shortT[a], shortGain[a], shortCast[a], shortEst[a] =
            UNKNOWN, -1, 0, 0, 0, 0, 0
        local obj = def.abilities[a]
        local funcs = rawget(obj, "funcs") -- Hekili keeps an ability's functions there
        local f = type(funcs) == "table" and rawget(funcs, "usable") or rawget(obj, "usable")
        pre[a] = rawget(obj, "ladder") ~= false and (type(f) ~= "function" or f)
    end
    for k = 1, RECORDS do
        recA[k], recR[k], recGone[k] = 0, 0, false
    end
end)

-- Slot r's `main` or (the off hand of a main-hand slot) `off` field for `hand`: a number, or the model's state-bound
-- function; 0 while the slot's swing aura is not believed up at `at` (default the clock; a swing's own time: rage is
-- gained at the swing) (its application after it, or its expiry at or before it). Allocates nothing.
local function perSwing(r, hand, main, off, at)
    local j, t = R.swingAura[r], at or I.clock
    if j < 0 or j > 0 and (I.auras.exp0[1][j] <= t or I.auras.applied[1][j] > t) then
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
function I.SwingValue(r, hand, at)
    return perSwing(r, hand, R.swingValue, R.swingOff, at)
end

--- The spec's white-crit extra of a swing-paid slot for `hand` (its swing entry's `crit`), as I.SwingValue.
function I.SwingCrit(r, hand, at)
    return perSwing(r, hand, R.swingCrit, R.swingOffCrit, at)
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

-- Slot r's rate at t as multiples of its two learned parts plus a known rate (fa x regE + fb x spE + k): wowsims's
-- (MP5/5 + S x m x min(c + s, 1)) x f inside the window and (MP5/5 + S x m) x f outside (sim/core/mana.go:186-206),
-- from the entries up at t: f and m multiply, s and mp5 add. The spirit regen S is spE / (1 - c), or the mp5 part
-- when the static share c is all of it (shortcut: exact while the slot has no mp5; upgrade if a full-share spec has
-- mp5). A plain slot's fb is 0. Allocates nothing.
local function coefAt(r, t, inside)
    local f, m, s, k = 1, 1, 0, 0
    for i = 1, M.n do
        if M.slot[i] == r then
            local j = M.aura[i]
            if I.auras.applied[1][j] <= t and I.auras.exp0[1][j] > t then -- unit 1 is always "player"
                f, m, s, k = f * M.mult[i], m * M.spirit[i], s + M.share[i], k + M.mp5[i]
            end
        end
    end
    if not R.fsr[r] then
        return f, 0, f * k
    end
    local c = R.share[r]
    local fa, fb, e = 1, 1, m - 1
    if inside then
        fb, e = 0, m * (c + s < 1 and c + s or 1) - c
    end
    if c < 1 then
        fb = fb + e / (1 - c) -- nonzero: c < 1
    else
        fa = fa + e
    end
    return f * fa, f * fb, f * k
end

-- The entries of slot r up at t as the out-of-combat read sees them: their whole-rate multiple f, their summed mp5, and
-- whether a `spirit` or `share` one is up (the game's pair then mixes the parts: no news). Allocates nothing.
local function readAt(r, t)
    local f, k, mixed = 1, 0, false
    for i = 1, M.n do
        if M.slot[i] == r then
            local j = M.aura[i]
            if I.auras.applied[1][j] <= t and I.auras.exp0[1][j] > t then
                f, k = f * M.mult[i], k + M.mp5[i]
                mixed = mixed or M.spirit[i] ~= 1 or M.share[i] > 0
            end
        end
    end
    return f, k, mixed
end

-- Slot r's regen weights over (from, from + dt]: the integrals of coefAt's fa, fb and k, split at the window's end and
-- at every entry's aura edge inside it (each piece read at its start: no edge lies inside it, and a midpoint of a
-- sub-ulp piece rounds onto its end); dt, 0 and 0 for a plain slot. The window is the latest one: a bound over a past
-- interval that held an earlier window is approximate. Allocates nothing.
local function spans(r, from, dt)
    if not R.shaped[r] then
        return dt, 0, 0
    end
    local to, a, b, k, t = from + dt, 0, 0, 0, from
    local u = R.fsr[r] and R.fsrUntil[r] or -1
    while t < to do
        local nxt = u > t and u < to and u or to
        for i = 1, M.n do
            if M.slot[i] == r then
                local j = M.aura[i]
                local ap, e = I.auras.applied[1][j], I.auras.exp0[1][j]
                if ap > t and ap < nxt then
                    nxt = ap
                end
                if e > t and e < nxt then
                    nxt = e
                end
            end
        end
        local fa, fb, kk = coefAt(r, t, t < u)
        local w = nxt - t
        a, b, k, t = a + fa * w, b + fb * w, k + kk * w, nxt
    end
    return a, b, k
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
        R.pinDelta[r], R.pinOwn[r] = R.pinDelta[r] + R.est0[r] - before, true
        I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.CombatEnd)
    end
    R.decayNext[r] = R.est0[r] > rest and t + R.decayIv[r] or 0
end

-- Continuous regen between pins (swing-paid slots move only at swings), then aura-gated regen, kept out of the
-- regen measurement like our own casts' changes (pinDelta), then the decay: ticks before quanta at the same instant.
I.OnAdvance(function(from, to)
    local dt = to - from
    for r = 1, R.n do
        local learned = R.regH[r] ~= 0 or R.spH[r] ~= 0
        if R.swing[r] == 0 and (learned or R.shaped[r]) then
            local max, a, b, k = R.max[r], spans(r, from, dt)
            if learned or k ~= 0 then -- a slot with no learned regen still gains an `mp5` entry's k (as VS.Power does)
                R.est0[r] = clamp(R.est0[r] + R.regE[r] * a + R.spE[r] * b + k, max)
                R.lo0[r] = clamp(R.lo0[r] + R.regL[r] * a + R.spL[r] * b + k, max)
                R.hi0[r] = clamp(R.hi0[r] + R.regH[r] * a + R.spH[r] * b + k, max)
                R.pinA[r], R.pinB[r] = R.pinA[r] + a, R.pinB[r] + b
                R.pinDelta[r] = R.pinDelta[r] + k -- an `mp5` entry's known gain, kept out of the measurement
                norm(r)
            end
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
            R.pinDelta[r], R.pinOwn[r] = R.pinDelta[r] + v, true
            norm(r)
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
                R.pinDelta[r], R.pinOwn[r] = R.pinDelta[r] + R.est0[r] - before, true
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

-- One measurement m of a continuous part of slot r (its declared rate ref, its EMA E/L/H and deviation D) into that
-- part's EMA (TDF calibrate). False when m is noise (a missed spend, a cap) or the part has no declared rate. A part
-- declared 0 with a `bound` (an `fsr` slot's mp5 part: the slot's declared total) learns any m in [0, bound x
-- REGEN_RATIO] instead of the ratio test.
local function ema(r, m, ref, E, L, H, D, bound)
    local scale = ref
    if ref == 0 then
        scale = bound or 0
        if scale <= 0 or m < 0 or m > scale * I.REGEN_RATIO then
            return false
        end
    else
        local ratio = m / ref -- nonzero: ref ~= 0 checked
        if ratio < 1 / I.REGEN_RATIO or ratio > I.REGEN_RATIO then
            return false
        end
    end
    -- the spread floor is REGEN_SPREAD_MIN times the reference m is measured against (calibrate's ratio: x 1)
    local est, dev, spread = Stats.Ema(E[r], D[r], m, I.ALPHA, abs(scale) * I.REGEN_SPREAD_MIN)
    D[r] = dev
    E[r], L[r], H[r] = est, est - spread, est + spread
    return true
end

-- One regen measurement m (per second, between two pins ending at t) into the slot's regen (the EMA, TDF
-- calibrate). A swing-paid slot calibrates its step scale against the spec's value per second of swinging. A shaped
-- slot's m is the gain over the pins' interval, split by its weights (pinA, pinB; spans): with no time outside the
-- window it measures the mp5 part (or the whole unscaled rate) as gain / pinA; with at least I.PIN_GAP outside, the
-- spirit part as (gain - mp5 x pinA) / pinB; a shorter time outside is no measurement.
local function calibrate(r, m, t)
    if R.shaped[r] then
        local a, b = R.pinA[r], R.pinB[r]
        local ok
        if b <= 0 and a > 0 then
            local bound = R.fsr[r] and R.decl[r] + R.spDecl[r] or nil
            ok = ema(r, m / a, R.decl[r], R.regE, R.regL, R.regH, R.dev, bound) -- nonzero: a > 0 checked
        elseif b >= I.PIN_GAP then
            ok = ema(r, (m - R.regE[r] * a) / b, R.spDecl[r], R.spE, R.spL, R.spH, R.spDev) -- nonzero: b >= 1
        end
        if ok then
            I.Sample(R.regen[r], "modelled", R.regE[r] + R.spE[r], t, Obs.Usable)
        end
        return
    end
    if R.swing[r] == 0 then
        if ema(r, m, R.decl[r], R.regE, R.regL, R.regH, R.dev) then
            I.Sample(R.regen[r], "modelled", R.regE[r], t, Obs.Usable)
        end
        return
    end
    local ref = I.SwingPerSecond(r)
    if ref == 0 then
        return
    end
    local ratio = m / ref -- nonzero: ref ~= 0 checked
    if ratio < 1 / I.REGEN_RATIO or ratio > I.REGEN_RATIO then
        return -- noise: a missed spend, a cap
    end
    local scale, dev, spread = Stats.Ema(R.scale[r], R.dev[r], ratio, I.ALPHA, I.REGEN_SPREAD_MIN) -- floor x 1: a ratio
    R.scale[r], R.dev[r], R.spread[r] = scale, dev, spread
    I.Sample(R.regen[r], "modelled", scale * ref, t, Obs.Usable)
end

-- Pins slot r at t to [v, v + width]; when this pin and the previous one both measure (exact, or `mid`), the regen
-- between them is a measurement. `origin` is "pinned" (a usability flip) or "observed" (an exact read). A wide flip
-- is a bound: it clamps the estimate into the range, never moves one already inside it; a read takes the midpoint.
local function pin(r, v, width, t, origin, event, mid)
    local exact = width <= 0
    local measures = exact or mid == true
    local vm = mid and v + width / 2 or v
    local dt = t - R.pinT[r]
    if R.swing[r] > 0 then
        -- a swing-paid slot's gain comes in steps: between two pins a second or two apart it is 0, 1 or 2 of them, and
        -- that lumpiness alone (the low ratios refused as noise, the high ones kept) pulled the scale to 1.3 within 15 s,
        -- its floor step above the true one (GAP AC); chained measuring pins add up until SWING_STEPS steps are due
        -- (bounded in time too: a hand idle past its swing plus I.LIFT_WINDOW, or with no step, starts it over)
        local h, step = R.swing[r], I.SwingValue(r, R.swing[r])
        if measures and R.pinValid[r] and step > 0 and t - swT[h] <= I.SwingSpeedEst(h) + I.LIFT_WINDOW then
            -- pins at one instant (several cost thresholds flipping at once) re-estimate one value: the window's ends
            -- are each instant's latest (it closes at the next instant's first pin, before that pin adds its interval)
            if dt > 1e-6 then
                if R.swAccT[r] * I.SwingPerSecond(r) >= I.SWING_STEPS * step then
                    calibrate(r, R.swAccG[r] / R.swAccT[r], t) -- nonzero: step > 0, so the window's time is too
                    R.swAccG[r], R.swAccT[r] = 0, 0
                end
                -- an interval holding a gain the belief knows besides the swings (our cast's, a refund, a periodic or
                -- decay step, a hit taken, a crit's extra) adds nothing: the scale measures swings only (the old
                -- per-interval filter refused such intervals); the instant keeps that verdict for its re-estimates
                R.pinSkip[r] = R.pinOwn[r]
                if R.pinOwn[r] then
                    R.skipFrom[r], R.skipTo[r] = R.pinT[r], t
                else
                    if R.swAccT[r] == 0 then
                        R.swFrom[r] = R.pinT[r]
                    end
                    R.swAccG[r], R.swAccT[r] = R.swAccG[r] + vm - R.pinV[r] - R.pinDelta[r], R.swAccT[r] + dt
                end
            elseif R.pinOwn[r] then
                R.pinSkip[r] = true -- a known gain between pins of one instant: its re-estimate is none of the window's
            elseif R.swAccT[r] > 0 and not R.pinSkip[r] then
                R.swAccG[r] = R.swAccG[r] + vm - R.pinV[r] - R.pinDelta[r]
            end
        else
            R.swAccG[r], R.swAccT[r], R.pinSkip[r] = 0, 0, false
        end
    elseif measures and R.pinValid[r] and dt >= I.PIN_GAP then
        local gain = vm - R.pinV[r] - R.pinDelta[r]
        calibrate(r, R.shaped[r] and gain or gain / dt, t) -- nonzero: dt >= PIN_GAP (1 s)
    end
    local max = R.max[r]
    local was = R.lo0[r] + R.over[r]
    local est = v + width / 2
    if origin == "pinned" then
        est = R.est0[r] < v and v or (R.est0[r] > v + width and v + width or R.est0[r])
    end
    R.est0[r], R.lo0[r], R.hi0[r] = clamp(est, max), clamp(v, max), clamp(v + width, max)
    R.snapT[r] = -1e9 -- an anchor, not a snap
    R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r], R.pinOwn[r] = t, vm, 0, measures, false
    R.pinA[r], R.pinB[r] = 0, 0
    remeasure(r, was, origin == "pinned" and v + width or -1) -- an exact read leaves no model above it
    I.Sample(R.power[r], origin, R.est0[r], t, event)
end

-- One rung of the cost ladder: the resource was at least `c` (affordable) or below it, `lag` before t. A late bound
-- is moved by the most regen could have changed it; a late short one is dropped if it then conflicts with the floor,
-- and an affordable one above the believed top opens the top to the maximum, as a timely one does. True when it moved the estimate
-- (a snap: the estimate now stands on this rung, so the caller writes a `pinned` sample).
local function ladder(r, c, affordable, t, lag)
    if lag > 0 and R.swing[r] == 0 then
        local a, b, k = spans(r, t - lag, lag)
        if affordable then
            c = c + R.regL[r] * a + R.spL[r] * b + k
            c = c < R.max[r] and c or R.max[r] -- the pool caps the regen since the answer
        else
            c = c + R.regH[r] * a + R.spH[r] * b + k
            if c - I.EPS < R.lo0[r] then
                return false
            end
        end
    end
    local snapped = false
    local was = R.lo0[r] + R.over[r]
    if affordable then
        if R.lo0[r] < c then
            R.lo0[r] = c
        end
        if R.est0[r] < c then
            R.est0[r], R.snapT[r], snapped = c, t, true
        end
        if R.hi0[r] < c then
            -- above the believed top: a gain the belief did not see (a refill: a potion, a pause, a mana return) put
            -- the slot anywhere from c to its maximum; a bound, never the pin [c, c] (GAP V)
            R.hi0[r] = R.max[r]
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
    remeasure(r, was, affordable and R.max[r] or c - I.EPS)
    return snapped
end

-- The lift a swing whose wound is still in flight can owe: its wound comes within the longest landing lag (Rows.lua's
-- pair window, 2 s off hand), so an older lift is nobody's.
I.LIFT_WINDOW = 2

-- Swing-paid slot r was at e, lo, hi before a rung at t moved it: what it lifted is owed by a swing at or before t
-- whose wound has not landed yet (I.On(Obs.Swing)). A lift older than the window is dropped first; a rung that lifts
-- nothing leaves liftT. Two lifts in one window pool, so a swing between them may pay the first's share too: est then
-- runs low and lo stays a floor (the safe side; keeping them apart per swing would let an off hand's late wound pay
-- the first lift twice). A short answer in the window (a cut) is not netted: the wound's step lands on the clamped
-- est and hi, which overshoot until the next answer, while lo (the simulation's reading) only takes its low edge.
-- Allocates nothing.
-- The rage is in at PLAYER_SWING, its wound about 0.47 s later: checkpoint R1, measured by the user 2026-10-20 ("Rage is
-- gained on swing, not on combat log entry").
local function owe(r, e, lo, hi, t)
    if R.swing[r] == 0 then
        return
    end
    local de, dl, dh = R.est0[r] - e, R.lo0[r] - lo, R.hi0[r] - hi
    if de <= 0 and dl <= 0 and dh <= 0 then
        return
    end
    if t - R.liftT[r] > I.LIFT_WINDOW then
        R.liftE[r], R.liftL[r], R.liftH[r] = 0, 0, 0
    end
    R.liftE[r] = R.liftE[r] + (de > 0 and de or 0)
    R.liftL[r] = R.liftL[r] + (dl > 0 and dl or 0)
    R.liftH[r] = R.liftH[r] + (dh > 0 and dh or 0)
    R.liftT[r] = t
end

--- Whether the swing of `hand` at `at` gave no rage, by the usability answers heard once it showed: a short answer
--- below the floor its landed step would have set (the floor at the swing plus the hand's low step), with no spend of
--- ours from the slot since the swing. Events/Rows.lua then credits no wound to it (it was avoided: a wound now is
--- another source's). Allocates nothing.
function I.Missed(hand, at)
    if swT[hand] ~= at or swTop[hand] == math.huge then
        return false
    end
    for r = 1, R.n do
        if
            (R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0))
            and R.spends[r] == swSp[hand]
        then
            local step = I.SwingValue(r, hand, at) * (R.scale[r] - R.spread[r]) -- its form or aura at the swing
            return swTop[hand] < swL[hand] + step
        end
    end
    return false
end

-- Step d less what of `lift` it covers, and the lift left.
local function net(d, lift)
    local u = lift < d and lift or d
    return d - u, lift - u
end

-- One swing step of slot r for `hand` at t: c = 1 a landed swing (the hand's value x scale, spread around it), c = 3
-- its crit (the hand's `crit`, unscaled); none for a crit of a slot without one. `owed`: the step first covers the
-- slot's rung lift (R.liftE/L/H). Allocates nothing.
local function swingStep(r, hand, c, t, owed, at)
    local max, v, s, sp = R.max[r], 0, 1, 0
    if c == 1 then
        v, s, sp = I.SwingValue(r, hand, at), R.scale[r], R.spread[r]
    else
        v = I.SwingCrit(r, hand, at)
    end
    if c == 1 or v ~= 0 then -- a slot with no `crit` takes no sample for a crit
        local de, dl, dh = v * s, v * (s - sp), v * (s + sp)
        if owed then
            de, R.liftE[r] = net(de, R.liftE[r])
            dl, R.liftL[r] = net(dl, R.liftL[r])
            dh, R.liftH[r] = net(dh, R.liftH[r])
        end
        if c ~= 1 then
            -- a crit's extra (exact and unscaled, a talent's rage with it) is no step the scale measures: its interval
            -- adds nothing to the window, or, already in it (after the window's start, outside an excluded interval),
            -- comes back out
            if at > R.pinT[r] then
                R.pinOwn[r] = true
            elseif R.swAccT[r] > 0 and at > R.swFrom[r] and not (at > R.skipFrom[r] and at <= R.skipTo[r]) then
                R.swAccG[r] = R.swAccG[r] - v
            end
        end
        R.est0[r] = clamp(R.est0[r] + de, max)
        R.lo0[r] = clamp(R.lo0[r] + dl, max)
        R.hi0[r] = clamp(R.hi0[r] + dh, max)
        I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
    end
end

-- Credit record k paid slot r for `hand` (from e, lo and hi before it): its deltas, and which answer will judge it.
-- The cheapest tracked spender of the slot whose cost the swing's rage crosses (x < c <= the estimate now, x the
-- estimate at the swing: a usable answer between the swing and its wound may already have lifted e), firm when the
-- new floor reaches it; a credit crossing no rung is not judged. Its crit calls it again with the same pre-credit
-- values: the deltas and the crossing then cover both steps. Allocates nothing.
local function predict(k, r, hand, e, lo, hi, hit, x, above)
    recR[k], recHand[k], recHit[k], recSpends[k] = r, hand, hit, R.spends[r]
    recE0[k], recLo0[k], recHi0[k], recX0[k] = e, lo, hi, x
    recEst[k], recLo[k], recHi[k] = R.est0[r] - e, R.lo0[r] - lo, R.hi0[r] - hi
    local best, cost, low, lowCost = 0, 0, 0, 0
    if not R.readable[r] then
        for a = 1, I.ab.n do
            if I.ab.slot[a] == r and not I.ab.multiCost[a] then
                local c = I.CostOf(a)
                if c > x and c <= R.est0[r] then
                    if best == 0 or c < cost then
                        best, cost = a, c
                    end
                    if c > above and (low == 0 or c < lowCost) then
                        low, lowCost = a, c
                    end
                end
            end
        end
    end
    if low > 0 then -- a crit: the cheapest cost its extra alone crosses judges the crit as well as the hit
        best, cost = low, lowCost
    end
    recA[k], recFirm[k] = best, best > 0 and R.lo0[r] >= cost
end

-- The oracle's verdict on the records ability a judges, from its answer `now` at t (harness design §2.2), before the
-- ladder reads it (§2.6): Rows decides whether the answer falls in the record's window and labels it; a firm credit
-- answered short is retracted here (est, lo, hi and the hit rate lose what it added, but never below their pre-credit
-- values: a short answer before the verdict may already have clamped the step away). One of our spends from the slot
-- since the credit voids it, and so does a NOT answer in its window. Returns whether a credit of slot r explains a
-- crossing of cost c: confirmed by this answer, or still awaiting its verdict with its step across c.
-- Allocates nothing.
local function back(cur, d, pre, max)
    local v = cur - d
    if v < pre then
        v = cur < pre and cur or pre
    end
    return clamp(v, max)
end

-- Record k's verdict from answer `now` (YES, SHORT, NOT) at t: nil before its window opens (it stays open), else
-- true or false; a firm credit answered short is retracted here.
local function verdict(k, now, t)
    if R.spends[recR[k]] ~= recSpends[k] then
        recA[k], recR[k], recGone[k] = 0, 0, true
        return false
    end
    local ok = nil -- a NOT answer is no rung: it leaves the record open (CreditVerdict)
    if now == YES or now == SHORT then
        ok = now == YES
    end
    local v = I.CreditVerdict(k, ok, t, recFirm[k])
    if v == nil then
        return nil
    end
    local s = recR[k]
    if v and now ~= YES and recFirm[k] then
        local max = R.max[s]
        R.est0[s] = back(R.est0[s], recEst[k], recE0[k], max)
        R.lo0[s] = back(R.lo0[s], recLo[k], recLo0[k], max)
        R.hi0[s] = back(R.hi0[s], recHi[k], recHi0[k], max)
        local h = hitRate[recHand[k]] - recHit[k]
        hitRate[recHand[k]] = h > 0 and h or 0
        I.Sample(R.power[s], "modelled", R.est0[s], t, Obs.Usable)
    end
    recA[k], recR[k], recGone[k] = 0, 0, true -- consumed: a reused id is not this slot's credit
    return v
end

-- Record k's credit taken back at t (a replacement, a refund): lo at once (it must never stand above the truth), hi
-- down to est at most, est into the slot's debt; the hit rate loses its step. Nothing once a spend of ours from the
-- slot measured the pool. The verdict's own retraction (verdict) is unchanged: an answer is a measurement. Allocates
-- nothing.
local function retract(k, t)
    local s = recR[k]
    if s == 0 or R.spends[s] ~= recSpends[k] then
        recA[k], recR[k] = 0, 0
        return
    end
    local max = R.max[s]
    R.lo0[s] = back(R.lo0[s], recLo[k], recLo0[k], max)
    local h = back(R.hi0[s], recHi[k], recHi0[k], max)
    R.hi0[s] = h > R.est0[s] and h or R.est0[s]
    estDebt[s] = estDebt[s] + recEst[k]
    local hr = hitRate[recHand[k]] - recHit[k]
    hitRate[recHand[k]] = hr > 0 and hr or 0
    recA[k], recR[k] = 0, 0
    I.Sample(R.power[s], "modelled", R.est0[s], t, Obs.Swing)
end

--- Slot r's held est debt applied (its next usability answer or spend): est loses it, never below lo. Allocates nothing.
function I.SettleDebt(r)
    local d = estDebt[r]
    if r > 0 and d and d > 0 then
        estDebt[r] = 0
        local e = R.est0[r] - d
        R.est0[r] = e > R.lo0[r] and e or R.lo0[r]
    end
end

-- `was` / `wasT`: a's answer before this one and its time: a new credit is judged by it first when it was heard since
-- the credit's swing (the look-back), then by this answer if that left it open.
local function judge(a, now, t, r, c, was, wasT)
    local explained = false
    for k = 1, RECORDS do
        if recA[k] == a then
            local s, x, d = recR[k], recX0[k], recEst[k] + recE0[k] - recX0[k]
            local v = nil
            if recLook[k] then
                recLook[k] = false
                if wasT >= recSw[k] then
                    v = verdict(k, was, wasT)
                end
            end
            if v == nil and recA[k] == a then
                v = verdict(k, now, t)
            end
            if s == r and (v and now == YES or v == nil) then
                explained = explained or (x < c and c <= x + d)
            end
        elseif recA[k] > 0 and recR[k] == r and R.spends[r] == recSpends[k] then
            -- awaiting another spender's verdict: its step across c explains this one's flip as well
            local x = recX0[k]
            explained = explained or (x < c and c <= recE0[k] + recEst[k])
        end
    end
    return explained
end

-- At the fold's end, each new credit is judged by its spender's latest answer heard since its swing, if any (rage is
-- gained at the swing: an answer between the swing and its wound already shows it). Allocates nothing.
I.OnSettle(function()
    for k = 1, RECORDS do
        if recLook[k] then
            recLook[k] = false
            local a = recA[k]
            if a > 0 and ansT[a] >= recSw[k] and I.CreditVerdict then
                verdict(k, usable[a], ansT[a])
            end
        end
    end
end)

-- Whether ability a's `usable` holds at t, read in the `now` context (the belief's names). Its function is Hekili's
-- sim one, so it runs there for this call only; one that raises (a name the context lacks) holds from then on.
-- Allocates nothing once it has raised.
local function holds(a, t)
    local f = pre[a]
    if f == true then
        return true
    end
    local env = getfenv(f)
    setfenv(f, I.nowCtx)
    I.NowAt(t)
    local ok, v = pcall(f)
    setfenv(f, env)
    if not ok then
        pre[a] = true
        return true
    end
    return v ~= false and v ~= nil
end

-- A flip to usable that a gain we modelled explains (our own): it proves only "at least c" now,
-- so slot r is bound to [c, the believed top] around the estimate, not pinned exactly at it (a mis-sized gain would
-- put lo above the truth: rage the game lacks); no regen measurement. `est` (gain - cast gain since the short answer)
-- is the estimated part of that gain (a refund, a hit's `taken`): lo gives up only that much, once an instant (from lo
-- before the instant's first flip), never below c; a cast's declared gain stays in it (gap BD round 2: each flip after
-- a mana gain dropped lo to its cost, ~200 under the truth). Allocates nothing.
local function crossed(r, c, t, est)
    local e, hi = R.est0[r], R.hi0[r]
    local top = e > hi and e or hi
    if top < c then
        top = c
    end
    if R.crossT[r] ~= t then
        R.crossT[r], R.crossLo[r] = t, R.lo0[r]
    end
    -- shortcut: a swing-paid floor holds estimated swing steps `est` does not count, so lo is the cost there (gaps.md
    -- row BR); count those steps as estimated gain to keep the floor.
    local v = R.swing[r] > 0 and c or R.crossLo[r] - (est > 0 and est or 0)
    if v < c then
        v = c
    elseif v > top then
        v = top
    end
    R.pinValid[r] = false
    pin(r, v, top - v, t, "pinned", Obs.Usable)
    R.pinValid[r] = false
end

I.On(Obs.Usable, function(o, t, lag)
    local a = o.a
    local now = o.b == 1 and YES or (o.c == 1 and SHORT or NOT)
    local r = I.ab.slot[a]
    I.SettleDebt(r)
    if now == SHORT and r ~= 0 and not R.readable[r] and pre[a] and not holds(a, t) then
        now = NOT -- short for another requirement: no rung, and no flip from it later
    elseif now == SHORT and r ~= 0 and o.t >= R.ownT[r] and o.t - R.ownT[r] < I.GAIN_SHOWS then
        local c = I.CostOf(a)
        if R.est0[r] >= c and R.est0[r] - R.ownV[r] < c then
            now = NOT -- read before our gain showed (I.GAIN_SHOWS): no rung; a later answer still counts
        end
    end
    -- a short answer read before the regen's crossing of the cost could show (I.GAIN_SHOWS) still caps, but leaves the
    -- modelled floor: a pin a tick of regen contradicts is no proof the rest assumption was wrong (remeasure)
    keepFloor = false
    if now == SHORT and r ~= 0 and R.swing[r] == 0 and lag <= 0 then
        local c = I.CostOf(a)
        local ga, gb, gk = spans(r, o.t - I.GAIN_SHOWS, I.GAIN_SHOWS)
        keepFloor = c - I.EPS >= R.est0[r] - R.regE[r] * ga - R.spE[r] * gb - gk and R.lo0[r] + R.over[r] >= c - I.EPS
    end
    local was, wasT = usable[a], ansT[a]
    usable[a], ansT[a] = now, o.t
    local c = r ~= 0 and I.CostOf(a) or 0
    local rung = r ~= 0 and now ~= NOT and not R.readable[r] and not I.ab.multiCost[a] and pre[a]
    if rung and c > 0 and c > R.lo0[r] then
        heardT = o.t -- only a rung above the floor can show a pending swing's gain (an answer below it proves nothing)
    end
    local explained = I.CreditVerdict and judge(a, now, t, r, c, was, wasT)
    keepFloor = keepFloor and rung and c > 0 -- no rung, no kept floor: a later read must not inherit it
    if not rung then
        return -- a second power cost (Overpower's combo points) makes a short answer ambiguous: no rung
    end
    if c <= 0 then
        return
    end
    local lo1, e1 = R.lo0[r], R.est0[r]
    if was == SHORT and now == YES and lag <= 0 and abs(c - shortCost[a]) <= I.EPS then
        -- It just became affordable at an unchanged cost: it crossed the cost since the last short report.
        R.pinN[r], R.pinErr[r] = R.pinN[r] + 1, R.pinErr[r] + abs(e1 - c)
        if R.gain[r] - shortGain[a] >= c - shortEst[a] then
            -- our own gain since then explains the crossing: a bound (crossed)
            crossed(r, c, t, R.gain[r] - shortGain[a] - (R.castGain[r] - shortCast[a]))
        elseif R.swing[r] > 0 then
            -- below the cost by every gain we modelled: a swing crossed it (rage is gained at the swing, so its wound,
            -- if ours, is still to come: the lift owe() records is its, netted when that wound is credited; a wound
            -- that never comes loses only its row, the rage stays right); a credit of ours across c (confirmed now, or
            -- awaiting its verdict) already explains it.
            if explained then
                -- a credited swing crossed it (its crit included): the flip proves only "at least c", a rung
                local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
                if ladder(r, c, true, t, lag) then
                    I.Sample(R.power[r], "pinned", R.est0[r], t, Obs.Usable)
                end
                owe(r, e, lo, hi, o.t)
            else
                -- a swing-paid resource crosses at a swing: [c, c + one step of the larger hand), measured at its
                -- midpoint
                local v, off = I.SwingValue(r), R.swingOff[r] ~= 0 and I.SwingValue(r, 2) or 0
                local step = (v > off and v or off) * (R.scale[r] + R.spread[r])
                local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
                pin(r, c, step, t, "pinned", Obs.Usable, true)
                owe(r, e, lo, hi, o.t) -- that swing's wound, if still in flight, must not pay it again
            end
        else
            local wa, wb, wk = spans(r, shortT[a], t - shortT[a])
            local width = R.regH[r] * wa + R.spH[r] * wb + wk
            pin(r, c, t - shortT[a] <= I.PIN_EXACT and 0 or width, t, "pinned", Obs.Usable)
        end
    else
        local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
        if ladder(r, c, now == YES, t, lag) then
            I.Sample(R.power[r], "pinned", R.est0[r], t, Obs.Usable)
        end
        owe(r, e, lo, hi, o.t)
    end
    if now == SHORT then
        shortCost[a], shortT[a], shortGain[a], shortCast[a], shortEst[a] =
            c, t - lag, R.gain[r], R.castGain[r], R.est0[r]
        local top = c - I.EPS
        if top < R.sinceShort[r] then
            R.sinceShort[r], R.sinceShortEst[r] = top, R.est0[r]
        end
        for h = 1, 2 do -- heard once a swing's rage shows: evidence on that swing (I.Missed)
            if R.swing[r] > 0 and o.t - swT[h] > I.Log.ORACLE_MIN - 1e-6 and top < swTop[h] then
                swTop[h] = top
            end
        end
    else
        R.sinceYes[r] = R.sinceYes[r] or R.lo0[r] > lo1
        R.sinceSnap[r] = R.sinceSnap[r] or R.est0[r] > e1
    end
    keepFloor = false -- this apply's only (remeasure)
end)

I.On(Obs.Read, function(o, t, lag)
    local r, c = o.a, o.c
    if c == ReadOf.Resource then
        if I.inCombat then
            R.readable[r] = true -- plain in combat: its exact reads keep it, its spenders' answers are no rungs
        end
        if lag > 0 and R.swing[r] == 0 then
            local a, b, k = spans(r, t - lag, lag)
            local width = (R.regH[r] - R.regL[r]) * a + (R.spH[r] - R.spL[r]) * b
            pin(r, o.b + R.regL[r] * a + R.spL[r] * b + k, width, t, "observed", Obs.Read)
        else
            pin(r, o.b, 0, t, "observed", Obs.Read)
        end
    elseif c == ReadOf.Max then
        if o.b > 0 then
            setMax(r, o.b)
            R.maxRead[r] = true -- a plain read wins over the declared maximum from now on
        end
    elseif c == ReadOf.Regen or c == ReadOf.RegenSpirit then
        -- the game's rate includes the entries up now: store it unscaled and net of their mp5 (none of a mixed pair)
        local f, k, mixed = readAt(r, t)
        if c == ReadOf.Regen and R.swing[r] == 0 and not (R.fsr[r] and mixed) then
            local v = o.b / f - k -- nonzero: every entry's mult > 0 (the build)
            v = v > 0 and v or 0 -- an `mp5` aura believed up that the game dropped: never a draining rate
            R.decl[r], R.readT[r] = v, t
            R.regE[r], R.regL[r], R.regH[r] = v, v, v
            I.Sample(R.regen[r], "observed", v + R.spE[r], t, Obs.Read)
        elseif c == ReadOf.RegenSpirit and R.fsr[r] and not mixed then -- after its slot's Regen read (Power.lua)
            local v = o.b / f -- nonzero: every entry's mult > 0 (the build)
            R.spDecl[r], R.readT[r] = v, t
            R.spE[r], R.spL[r], R.spH[r] = v, v, v
            I.Sample(R.regen[r], "observed", R.regE[r] + v, t, Obs.Read)
        end
    end
end)

-- A landed swing (c = 1: Events/Rows.lua credited the target's wound to our white swing, so never an avoid and never
-- a swing an on-next-swing strike took) pays each slot of its hand one step (the off hand its own value). It is
-- staged when the wound arrives, one swing's lag after PLAYER_SWING (about 0.45 s main, about 1 s off, research
-- 2026-10-16-swing-outcome-pairing): believed rage trails the game's by that step, and lo stays a floor. Its crit
-- (c = 3, the same credit with a CRITICAL wound, right after its c = 1) adds the hand's `crit` once more, unscaled (an
-- exact, documented amount; the scale absorbs the model's error). A swing (c = 4) pays nothing; it and c = 1
-- keep the hand's hit rate. A credit's `b` names its record (the oracle): the first slot it pays keeps its deltas, and
-- its crit (the same `b`) adds to them. A landed swing at or before a rung that lifted the slot (our cast's success, a
-- usable answer or a flip's pin while its wound was in flight) was in the game's pool then: its step covers that lift
-- first (as if credited before the rung: lo stays a floor; owe). A swing after the rung owes nothing and leaves the lift
-- to an earlier one still in flight (the other hand's).
I.On(Obs.Swing, function(o, t)
    local hand, c = o.a, o.c
    local hit = 0
    if hand ~= 1 and hand ~= 2 then
        return
    elseif c == 4 then
        hitRate[hand] = (Stats.Ema(hitRate[hand], 0, 0, HIT_ALPHA, 0)) -- a swing: the share decays toward 0
        for r = 1, R.n do -- the estimate a credit of this swing is judged from (predict)
            if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
                swE[hand], swL[hand], swT[hand], swTop[hand], swSp[hand] =
                    R.est0[r], R.lo0[r], o.t, math.huge, R.spends[r]
                break
            end
        end
        return
    elseif c == 1 then
        local h = hitRate[hand] + HIT_ALPHA
        h = h < 1 and h or 1
        hit, hitRate[hand] = h - hitRate[hand], h
    elseif c == 6 then -- a credit taken back (attribution-recovery spec §2.3): its record's deltas, with the hold
        local k = o.b >= 1 and o.b <= RECORDS and o.b or 0
        if k > 0 then
            retract(k, t)
        end
        return
    elseif c == 5 or c == 7 then -- assumed (5) or its confirmation (7), attribution-recovery spec §3.2
        local k = o.b >= 1 and o.b <= RECORDS and o.b or 0
        if k > 0 and c == 5 then
            recA[k], recR[k], recGone[k], recSw[k], recLook[k] = 0, 0, false, o.t, false -- a fresh record
        elseif c == 5 then
            -- a lost close (no record, so no c = 7 follows): the hit rate takes the expected share it credits, else
            -- every lost row counts as an avoid, the scale inflates to make up the rate and each landed step (lo
            -- with it) overpays
            local h = hitRate[hand] + HIT_ALPHA * hitRate[hand]
            hitRate[hand] = h < 1 and h or 1
        end
        for r = 1, R.n do
            if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
                local v, sc, sp, max = I.SwingValue(r, hand, o.t), R.scale[r], R.spread[r], R.max[r]
                local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
                -- a rung that lifted the slot while this swing was out already holds its rage (owe): net it first
                local owes = o.t <= R.liftT[r] and t - R.liftT[r] <= I.LIFT_WINDOW
                if c == 5 then -- est and hi only: affordability never rests on an assumption
                    -- EV (decision 52 as ruled): the expected share of a step, read after the update above (a lost
                    -- close's: h0 x (1 - alpha^2), the swing's decay and the share's credit)
                    local f = hitRate[hand]
                    local de = v * sc * f
                    local dh = de
                    if owes then
                        de, R.liftE[r] = net(de, R.liftE[r])
                        dh, R.liftH[r] = net(dh, R.liftH[r])
                    end
                    R.est0[r], R.hi0[r] = clamp(e + de, max), clamp(hi + dh, max)
                    if k > 0 then
                        recAsm[k] = f
                        predict(k, r, hand, e, lo, hi, 0, e, math.huge)
                        -- judged by no answer: its answer would come before its row, a verdict would consume the record
                        -- and the row's confirmation (c = 7: the floor, the rest of the step, the hit rate) would be
                        -- dropped, starving SwingPerSecond and inflating the scale. Only a provider's HIT has a record
                        -- here (T.onAssume); the expectation at a lost close stages record 0.
                        recA[k] = 0
                    end
                elseif k > 0 and recR[k] == r then -- confirmed: the rest of a landed step, and its floor
                    R.liftRec[r] = owes and o.b or 0 -- as a landed swing's (c = 1): its crit pays the rest it owed
                    local de, dh, dl = v * sc * (1 - recAsm[k]), v * (sc + sp) - v * sc * recAsm[k], v * (sc - sp)
                    if owes then
                        de, R.liftE[r] = net(de, R.liftE[r])
                        dh, R.liftH[r] = net(dh > 0 and dh or 0, R.liftH[r])
                        dl, R.liftL[r] = net(dl, R.liftL[r])
                    end
                    R.est0[r] = clamp(e + de, max)
                    R.hi0[r] = clamp(hi + (dh > 0 and dh or 0), max)
                    R.lo0[r] = clamp(lo + dl, max)
                    local h = hitRate[hand] + HIT_ALPHA
                    h = h < 1 and h or 1
                    predict(k, r, hand, recE0[k], recLo0[k], recHi0[k], h - hitRate[hand], recX0[k], math.huge)
                    hitRate[hand] = h
                end
                norm(r)
                I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
                break
            end
        end
        return
    elseif c ~= 3 then
        return
    end
    local k = o.b >= 1 and o.b <= RECORDS and o.b or 0
    if k > 0 and c == 1 then
        recA[k], recR[k], recGone[k] = 0, 0, false -- a fresh record: no stale prediction when its hand pays no slot
    end
    -- the swing's own time (rage is gained at the swing: its form or aura then decides): c = 1 is stamped at it, its
    -- crit (stamped at the wound) takes its record's
    local at = c == 3 and k > 0 and recSw[k] > 0 and recSw[k] or o.t
    for r = 1, R.n do
        if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
            local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
            local owes = false
            if c == 1 then -- the swing's own time (o.t), not the fold's
                owes = o.t <= R.liftT[r] and t - R.liftT[r] <= I.LIFT_WINDOW
                R.liftRec[r] = owes and o.b or 0
            else
                owes = R.liftRec[r] == o.b -- its crit pays the rest of what its landed step owed
            end
            swingStep(r, hand, c, t, owes, at)
            if k > 0 and c == 1 then
                local x = abs(o.t - swT[hand]) < 1e-6 and swE[hand] < e and swE[hand] or e
                predict(k, r, hand, e, lo, hi, hit, x, math.huge)
                recSw[k], recLook[k] = o.t, true
                k = 0
            elseif k > 0 and recR[k] == r and recHand[k] == hand then
                local white = recE0[k] + recEst[k] -- the estimate after the hit's own step
                predict(k, r, hand, recE0[k], recLo0[k], recHi0[k], recHit[k], recX0[k], white) -- its crit: both steps
                k = 0
            end
        end
    end
end)

-- Our own cast succeeded: the game had its cost (a rung); Families/Now.lua then pays it. An on-next-swing strike's
-- success arrives with its swing, where Now.lua pays it, so its press says nothing here.
I.On(Obs.CastSuccess, function(o, t, lag)
    local a = o.a
    local r = I.ab.slot[a]
    I.SettleDebt(r)
    if r == 0 or I.ab.obj[a].onNextSwing then
        return
    end
    local c = I.CastCost(o, a)
    local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
    if c > 0 and ladder(r, c, true, t, lag) then
        I.Sample(R.power[r], "pinned", R.est0[r], t, Obs.CastSuccess)
    end
    owe(r, e, lo, hi, o.t)
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
                norm(r)
                -- the full gain even when capped, as I.ResourceShift does (review minor 3: skipped for both)
                R.pinDelta[r], R.gain[r], R.pinOwn[r] = R.pinDelta[r] + gain, R.gain[r] + gain, true
                I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.PlayerHit)
                local sec = floor(t) -- out of combat too: the pull's own hits count once combat starts
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

--- The time of `hand`'s latest swing (1 main, 2 off) whose gain the believed floor does not hold yet, else 0 (GAP AK).
--- The game pays it at the swing (checkpoint R1); the floor takes it at the first usability answer that can show it
--- (about ORACLE_MIN later: a rung, so a cost above the floor) or at its wound row's credit (a landing lag later).
--- Hekili's swing forecast counts that swing as past meanwhile, so for a poll every rage-gated line ranked as
--- unaffordable (Arms flicker 4.1/min); Engine/Sim/State.lua forecasts its gain instead, one poll after the answers can
--- show it (no press before). Not pending once an answer above the floor since that point was heard (it showed the
--- gain, or the swing gave none; one under it proves nothing), once its swing ticket closes (credited, or no credit
--- within its pending window: Events/Tickets.lua's T.SwingPending), after a spend from the slot (its cast's rung holds
--- what the game had), or for a slot read plain. Allocates nothing.
function VS.SwingPending(hand)
    local p = I.Tickets.SwingPending(hand, I.clock) -- the swing ticket owns it (open, uncredited, in its window)
    if p == 0 or heardT > p + I.Log.ORACLE_MIN - 1e-6 then
        return 0 -- shown, credited, or no credit one landing lag on: avoided
    end
    local paid = false
    for r = 1, R.n do
        if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
            if R.readable[r] or R.spends[r] ~= swSp[hand] then
                return 0
            end
            paid = true
        end
    end
    return paid and p or 0 -- no swing-paid slot on that hand: nothing pends
end

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
    refresh()
    for r = 1, R.n do
        R.decayNext[r] = 0
        R.pinN[r], R.pinErr[r] = 0, 0
    end
end)

--- (providers spec §4.3) The fight's usability flips at an unchanged cost and the summed |estimate - cost| at them,
--- over every slot: the rage error an Outcomes provider should move. Allocates nothing.
function I.PinError()
    local n, e = 0, 0
    for r = 1, R.n do
        n, e = n + R.pinN[r], e + R.pinErr[r]
    end
    return n, e
end

-- Out of combat a resource falls toward its rest value: the interval opens down to it (lo never over-promises), and
-- a decaying slot's rate is re-read; a stepped one loses its first quantum at once (front-loaded).
I.On(Obs.CombatEnd, function(o, t)
    fighting = false
    for r = 1, R.n do
        estDebt[r] = 0
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
    local lo = R.lo0[r]
    R.lo0[r] = clamp(lo + delta, max)
    if delta < 0 and R.over[r] > 0 then -- the part the measured floor could not lose (at 0) comes off the model's
        local o = R.over[r] + delta - (R.lo0[r] - lo)
        R.over[r] = o > 0 and o or 0
    end
    norm(r)
    R.hi0[r] = clamp(R.hi0[r] + delta, max)
    R.pinDelta[r] = R.pinDelta[r] + delta
    if delta > 0 then
        R.gain[r] = R.gain[r] + delta -- explains a flip (the Usable apply)
        R.pinOwn[r] = true
        if event == Obs.CastSuccess then -- a cast's declared gain, not a refund (I.GAIN_SHOWS)
            ownGain(r, delta, t)
            R.castGain[r] = R.castGain[r] + delta
        end
    elseif delta < 0 then
        R.spends[r] = R.spends[r] + 1 -- a spend between a credit and its verdict voids the verdict (the oracle)
        R.sinceShort[r], R.sinceYes[r], R.sinceSnap[r] = math.huge, false, false
        if R.fsr[r] then
            local late = I.clock - t -- a success folded late (GAP W): the spirit part was credited since t
            local _, b0 = spans(r, t, late > 0 and late or 0)
            R.fsrUntil[r] = t + I.FSR -- our own spend: the spirit part pauses (the five-second rule, C3)
            local _, b1 = spans(r, t, late > 0 and late or 0)
            local d = b0 - b1 -- what the window opened at t takes back of it
            if d > 0 then
                R.est0[r] = clamp(R.est0[r] - R.spE[r] * d, max)
                R.lo0[r] = clamp(R.lo0[r] - R.spL[r] * d, max)
                R.hi0[r] = clamp(R.hi0[r] - R.spH[r] * d, max)
                R.pinB[r] = R.pinB[r] - d
                norm(r)
            end
        end
    end
    I.Sample(R.power[r], "modelled", R.est0[r], t, event)
end

--- An avoided cast's refund `d` (> 0) to slot r, dated at that cast's success (the server refunds there, the user
--- 2026-10-20; the target's avoid only reports it later): est and hi take it, clamped by the lowest top a short answer
--- set since the cast plus what the slot gained since that answer (the answer already saw the refunded pool; regen or
--- a credit after it adds to the truth); lo takes it only when no usable answer raised lo since the cast, est only
--- when none raised est (else that answer's bound already holds the refund). Allocates nothing.
function I.Refund(r, d, t)
    local lo, e, top = R.lo0[r], R.est0[r], R.sinceShort[r]
    if top < math.huge then
        local moved = e - R.sinceShortEst[r]
        top = top + (moved > 0 and moved or 0)
    end
    I.ResourceShift(r, d, t, Obs.Avoided)
    if R.sinceYes[r] then
        R.lo0[r] = lo
    end
    if R.sinceSnap[r] then
        R.est0[r] = e
    end
    if R.hi0[r] > top then
        R.hi0[r] = top
    end
    if R.est0[r] > top then
        R.est0[r] = top
    end
    if R.lo0[r] > top then
        R.lo0[r] = top
    end
    if R.est0[r] < R.lo0[r] then
        R.est0[r] = R.lo0[r]
    end
    if R.hi0[r] < R.est0[r] then
        R.hi0[r] = R.est0[r]
    end
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
    local a, b, k = spans(r, I.clock, dt)
    gain = gain + k
    local est = clamp(R.est0[r] + R.regE[r] * a + R.spE[r] * b + gain, max)
    local lo = clamp(R.lo0[r] + R.over[r] + R.regL[r] * a + R.spL[r] * b + gain, max)
    local hi = clamp(R.hi0[r] + R.regH[r] * a + R.spH[r] * b + gain, max)
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

-- VS.Regen's modes: the client's pair, GetPowerRegenForPowerType's (not casting, casting), each without the window.
VS.CASTING, VS.NOT_CASTING = true, "not casting"

--- (spec §3.2) The believed regen per second of a power type. A swing-paid resource's is its calibrated step per
--- second of swinging. A continuous one's is the rate its regen entries up at `now` give (coefAt); with an `fsr`, the
--- casting rate while `mode` is VS.CASTING (the in-cast rate), the not-casting rate while it is VS.NOT_CASTING (the
--- client's first return), and with it nil the rate at `now`: the casting rate inside the five-second window.
--- Allocates nothing.
function VS.Regen(powerType, now, mode)
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
        local fa, fb, k = coefAt(r, now, R.fsr[r] and (mode == VS.CASTING or mode == nil and now < R.fsrUntil[r]))
        local est = R.regE[r] * fa + R.spE[r] * fb + k
        rec.est, rec.lo, rec.hi = est, R.regL[r] * fa + R.spL[r] * fb + k, R.regH[r] * fa + R.spH[r] * fb + k
        local conf = est ~= 0 and 1 - (rec.hi - est) / abs(est) or 0 -- nonzero: est ~= 0 checked
        rec.conf = conf < 0 and 0 or conf
    end
    return rec
end

--- The end of the five-second window our own last spend of a power type opened (its spirit part pauses until then;
--- 0 before any spend), or nil for a type without an `fsr`. The sim's forecast applies the window itself (Engine/Sim
--- State.lua): the casting rate before this, the not-casting rate after. Allocates nothing.
function VS.FsrUntil(powerType)
    local r = R.slotOf[powerType]
    if r and R.fsr[r] then
        return R.fsrUntil[r]
    end
end
VS.FSR = I.FSR -- the window's length, for the sim's own queued spends

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
