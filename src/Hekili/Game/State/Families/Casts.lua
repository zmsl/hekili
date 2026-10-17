-- Game/State/Families/Casts.lua
-- The casts family (spec §6.2): the tracked abilities, our casts and channels in progress, cooldown ready times
-- snapped to the game's plain ready flags (the constrain step), charges, the GCD from its flag edges with
-- bit-identical start and duration (spec §7.5), its length by GCD kind and the ability that opened it, the
-- on-next-swing queue, and the Cooldown/Charges/Gcd accessors.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Casts.lua (step :34-78, Applier Cooldown :385,
-- Queued :391) and src/TacoDogForever/Model/Belief.lua (constrain :652-684).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local floor, abs, max = math.floor, math.abs, math.max

-- By ability index a. `obj` is the spec's ability table (Hekili's `class.abilities[key]`): VirtualState reads its
-- `spend`, `spendType`, `cooldown`, `charges`, `recharge`, `gcd`, `gcdTime`, `cast` and `onNextSwing` fields.
local A = {
    n = 0,
    key = {},
    id = {},
    ids = {},
    obj = {},
    slot = {},
    qid = {},
    readCost = {},
    multiCost = {},
    ready0 = {},
    cdLen = {},
    castT = {},
    flag = {},
    charges0 = {},
    next0 = {},
    queued = {},
    castStartT = {},
    cd = {},
    ch = {},
    chNext = {},
    gcdKind = {}, -- 0 off the GCD, 1 spell (1.5 s / haste), 2 totem (Hekili's fixed 1.0 s)
}
I.ab = A
A.bySpell = {}

-- Unknown, not ready, ready (the plain isActive flag as last reported).
local UNKNOWN, NOT, YES = -1, 0, 1
-- The plausible lengths a falling edge may teach, by kind: spell [1.0, 2.0), totem [0.9, 1.2) (two chained GCDs merge
-- into one long edge: 2.0 and more is never one).
local GCD_MIN, GCD_MAX = { 1.0, 0.9 }, { 2.0, 1.2 }
-- An own cast within this of the GCD's rising edge, before or after it, opened it (UNMEASURED until checkpoint G3).
local GCD_EDGE = 0.1
I.GCD_EDGE = GCD_EDGE

-- The cast or channel in progress (0: none), and the GCD fixed at its rising edge: its opener (ability index, 0
-- none), the opener kind a GCD without one takes (the last opener's), whether GcdInfo has answered it, and the
-- learned length by kind ({ spell, totem }, 0 unlearned).
I.castAb, I.castEnd, I.channel = 0, 0, false
I.gcdStart, I.gcdDur, I.gcdLearned = 0, 0, { 0, 0 }
I.gcdOwner, I.gcdKindLast, I.gcdRead = 0, 1, false
local lastGcdA, lastGcdT = 0, 0 -- the last own on-GCD CastSuccess no GCD has taken yet
local gcdEdge = 0 -- the rising edge's own time (gcdStart is it quantised, up to 2^-11 s later)
I.queuedStrike = false
I.lastCastT = 0
local gcd

-- 2^-10 s: a start and a duration on this grid survive (start + duration) - duration exactly (spec §7.5).
local Q = 1024
local function quantise(x)
    return floor(x * Q + 0.5) / Q
end
I.Quantise = quantise

--- The length of a GCD that ability a (0: none known, the last opener's kind) opens at t: its declared `gcdTime`,
--- else its kind's learned length, else 1.0 for the totem kind and 1.5 / haste for the spell kind. Allocates nothing.
function I.GcdLen(a, t)
    local kind = I.gcdKindLast
    if a > 0 then
        local g = A.obj[a].gcdTime
        if type(g) == "number" and g > 0 then
            return g
        end
        kind = A.gcdKind[a]
    end
    if kind == 0 then
        return 0
    elseif I.gcdLearned[kind] > 0 then
        return I.gcdLearned[kind]
    elseif kind == 2 then
        return 1.0
    end
    local h = VS.Haste and VS.Haste(t).est or 1 -- Families/Swing.lua measures it
    return 1.5 / (h > 0 and h or 1) -- nonzero: h > 0 checked
end

local function maxCharges(a)
    local c = A.obj[a].charges
    return type(c) == "number" and c or 1
end

I.OnBuild(function(def, now)
    for k in pairs(A.bySpell) do
        A.bySpell[k] = nil
    end
    local list = def.abilities
    A.n = #list
    for a = 1, A.n do
        local obj = list[a]
        A.key[a], A.obj[a] = obj.key, obj
        local ids = def.abilityIds[a]
        A.ids[a], A.id[a] = ids, ids[1]
        for k = 1, #ids do
            A.bySpell[ids[k]] = a
        end
        A.slot[a] = def.abilitySlot[a]
        A.qid[a], A.readCost[a], A.multiCost[a] = ids[1], 0, false
        A.ready0[a], A.cdLen[a], A.castT[a], A.flag[a] = 0, 0, 0, UNKNOWN
        A.charges0[a], A.next0[a] = maxCharges(a), 0
        A.queued[a], A.castStartT[a] = false, 0
        local g, extra = obj.gcd, type(obj.key) == "string" and obj.key:sub(1, 6) == "track_" -- VS.Track: no GCD
        A.gcdKind[a] = (g == "off" or extra) and 0 or (g == "totem" and 2 or 1) -- anything else: State.lua's "spell"
        A.cd[a] = I.NewBelief("cooldown " .. tostring(obj.key))
        I.Sample(A.cd[a], "default", 0, now, 0)
        if maxCharges(a) > 1 then
            A.ch[a] = I.NewBelief("charges " .. tostring(obj.key))
            A.chNext[a] = I.NewBelief("charge next " .. tostring(obj.key))
            I.Sample(A.ch[a], "default", maxCharges(a), now, 0)
        else
            A.ch[a], A.chNext[a] = false, false
        end
    end
    I.TRACKED.ability = A.id
    gcd = I.NewBelief("gcd")
    I.castAb, I.castEnd, I.channel, I.gcdStart, I.gcdDur, I.queuedStrike = 0, 0, false, 0, 0, false
    I.gcdOwner, I.gcdKindLast, I.gcdRead, lastGcdA, lastGcdT = 0, 1, false, 0, 0
end)

-- The GCD's current sample at its fixed end.
local function pinGcd(t)
    local e = I.gcdStart + I.gcdDur
    gcd.est, gcd.lo, gcd.hi = e, e, e
    I.Sample(gcd, "pinned", e, t, Obs.Cooldown)
end

-- An own cast of on-GCD ability a at time `at`: it claims an ownerless GCD that rose within GCD_EDGE before it (the
-- edge came first), re-fixing the duration only while GcdInfo has not answered this GCD (spec §7.5); else it is kept
-- for the next rising edge.
local function opener(a, at, t)
    if A.gcdKind[a] == 0 then
        return -- off the GCD (an on-next-swing strike's success at its swing): never an opener
    end
    if I.gcdStart > 0 and I.gcdOwner == 0 and at >= gcdEdge and at - gcdEdge <= GCD_EDGE then
        I.gcdOwner, I.gcdKindLast = a, A.gcdKind[a]
        if not I.gcdRead then
            I.gcdDur = quantise(I.GcdLen(a, t))
            pinGcd(t)
        end
        lastGcdA = 0
    else
        lastGcdA, lastGcdT = a, at
    end
end

I.On(Obs.CastStart, function(o, t)
    I.castAb, I.castEnd, I.channel = o.a, o.b, false
    A.castStartT[o.a] = o.t
    opener(o.a, o.t, t)
end)

I.On(Obs.CastDelay, function(o)
    if I.castAb == o.a then
        I.castEnd = o.b
    end
end)

I.On(Obs.CastSuccess, function(o, t)
    I.lastCastT = o.t
    if I.castAb == o.a and not I.channel then
        I.castAb = 0
    elseif A.castStartT[o.a] == 0 then -- a hard cast's GCD opened at its start
        opener(o.a, o.t, t)
    end
    if A.obj[o.a].onNextSwing then
        A.queued[o.a] = false
    end
end)

I.On(Obs.CastStop, function(o)
    if I.castAb == o.a then
        I.castAb = 0
    end
    A.castStartT[o.a] = 0 -- an interrupted cast's start is no GCD anchor for the next one (Families/Now.lua)
end)

I.On(Obs.ChannelStart, function(o, t)
    I.castAb, I.castEnd, I.channel = o.a, o.b, true
    A.castStartT[o.a] = o.t
    opener(o.a, o.t, t)
end)

I.On(Obs.ChannelUpdate, function(o)
    if I.castAb == o.a then
        I.castEnd = o.b
    end
end)

I.On(Obs.ChannelStop, function(o)
    if I.castAb == o.a then
        I.castAb, I.channel = 0, false
    end
end)

I.On(Obs.Queued, function(o)
    A.queued[o.a] = o.b == 1
    local any = false
    for a = 1, A.n do
        if A.queued[a] then
            any = true
        end
    end
    I.queuedStrike = any
end)

-- The plain flags (spec §6.2): an ability's ready edge, or (a = 0, c = 1) the GCD's edge.
I.On(Obs.Cooldown, function(o, t)
    if o.c == 1 then
        if o.b == 1 then
            -- the GCD began: its opener is the cast in progress or an own cast just before the edge; start and
            -- duration fixed until the falling edge (spec §7.5), but a later opener's claim before GcdInfo's first read
            local owner = 0
            if I.castAb > 0 and A.gcdKind[I.castAb] > 0 then
                owner = I.castAb
            elseif lastGcdA > 0 and abs(o.t - lastGcdT) <= GCD_EDGE then
                owner = lastGcdA
            end
            lastGcdA = 0
            I.gcdOwner, I.gcdRead = owner, false
            if owner > 0 then
                I.gcdKindLast = A.gcdKind[owner]
            end
            I.gcdStart, I.gcdDur, gcdEdge = quantise(o.t), quantise(I.GcdLen(owner, t)), o.t
            pinGcd(t)
        else
            local len, owner = o.t - I.gcdStart, I.gcdOwner
            local kind = owner > 0 and A.gcdKind[owner] or 0
            local g = owner > 0 and A.obj[owner].gcdTime
            -- an ownerless GCD, or one of a declared length, teaches nothing
            if I.gcdStart > 0 and kind > 0 and not (type(g) == "number" and g > 0) then
                if len >= GCD_MIN[kind] and len < GCD_MAX[kind] then
                    I.gcdLearned[kind] = quantise(len)
                end
            end
            I.gcdStart, I.gcdDur, I.gcdOwner, I.gcdRead = 0, 0, 0, false
            gcd.est, gcd.lo, gcd.hi = o.t, o.t, o.t
            I.Sample(gcd, "pinned", o.t, t, Obs.Cooldown)
        end
        return
    end
    local a = o.a
    local was = A.flag[a]
    A.flag[a] = o.b == 1 and YES or NOT
    if o.b == 1 and was == NOT and A.castT[a] > 0 and o.t > A.castT[a] then
        -- a ready edge after our cast teaches the real length (talents included), but only near the registered one:
        -- a flag that also tracks something else (a kill window's usability) would teach minutes
        local len, reg = o.t - A.castT[a], A.obj[a].cooldown
        if type(reg) ~= "number" or reg <= 0 or abs(len - reg) <= max(1, reg * 0.1) then
            A.cdLen[a] = len
        end
    end
end)

-- The standing flags at `now` (TDF constrain): ready pulls a later ready time back to now (and restores a charge);
-- not ready pushes an earlier one to at least now + CD_PROBE.
I.OnSettle(function(now)
    for a = 1, A.n do
        local flag = A.flag[a]
        if flag == YES then
            if A.ready0[a] > now then
                A.ready0[a] = now
                I.Sample(A.cd[a], "pinned", now, now, Obs.Cooldown)
            end
            if A.ch[a] and A.charges0[a] < 1 then
                A.charges0[a] = 1
            end
        elseif flag == NOT then
            local probe = now + I.CD_PROBE
            if A.ch[a] then
                A.charges0[a] = 0
                if A.next0[a] < probe then
                    A.next0[a] = probe
                end
            elseif A.ready0[a] < probe then
                A.ready0[a] = probe
                I.Sample(A.cd[a], "pinned", probe, now, Obs.Cooldown)
            end
        end
    end
end)

--- Our own cast set ability a's cooldown (spec §5.3): ready time `expires`, length `duration`. Allocates nothing.
function I.CooldownModel(a, expires, duration, t, event)
    A.ready0[a], A.castT[a] = expires, t
    if A.cdLen[a] == 0 and duration > 0 then
        A.cdLen[a] = duration
    end
    I.Sample(A.cd[a], "modelled", expires, t, event)
end

--- Our own cast spent a charge (spec §5.3). Allocates nothing.
function I.ChargesModel(a, charges, nextAt, t, event)
    if A.ch[a] then
        A.charges0[a], A.next0[a], A.castT[a] = charges, nextAt, t
        I.Sample(A.ch[a], "modelled", charges, t, event)
        I.Sample(A.chNext[a], "modelled", nextAt, t, event)
    end
end

--- Our own cast started the GCD (spec §5.3): its end as a `modelled` sample. Allocates nothing.
function I.GcdModel(expires, t, event)
    gcd.est, gcd.lo, gcd.hi = expires, expires, expires
    I.Sample(gcd, "modelled", expires, t, event)
end

--- The cost the ladder uses for ability a: the spec's `spend` (decision 2), a number or a function bound to `state`
--- (Hekili's ability table already evaluates a function `spend` on access; a raw one is called here). The plain
--- out-of-combat read (`readCost`, Sources/Spellbook.lua) only confirms it, in Snapshot(): its units are the client's.
function I.CostOf(a)
    local c = I.BaseCostOf(a)
    if I.CostMod then
        c = I.CostMod(a, A.slot[a], c, I.clock) -- the resource's cost modifiers in scope (Families/Modifiers.lua)
    end
    return c
end

--- Ability a's declared cost, before any cost modifier (0 when it has none); a cost between 0 and 1 is that fraction
--- of its resource's believed maximum, as Hekili's simulation prices it (State.lua's spend). Allocates nothing.
function I.BaseCostOf(a)
    local obj = I.ab.obj[a]
    local c = obj.baseSpend -- the declared cost before the simulation's modifiers (Engine/Schema/Races.lua)
    if c == nil then
        c = obj.spend
    end
    if type(c) == "function" then
        c = c()
    end
    if type(c) ~= "number" then
        return 0
    end
    if c > 0 and c < 1 and A.slot[a] > 0 then
        c = c * I.res.max[A.slot[a]]
    end
    return c
end

local function ageConf(rec, now)
    local last = rec.last
    local t = last.observed.t
    if last.pinned.t > t then
        t = last.pinned.t
    end
    if last.modelled.t > t then
        t = last.modelled.t
    end
    local age = now - t
    if age < 0 then
        age = 0
    end
    rec.conf = 1 / (1 + age / I.AURA_HALF_LIFE) -- nonzero: 1 + age >= 1
end
I.AgeConf = ageConf

--- (spec §3.2) The believed ready time of a tracked spell (absolute), or nil for an untracked one.
function VS.Cooldown(spellID, now)
    local a = A.bySpell[spellID]
    if not a then
        return nil
    end
    local rec, ready = A.cd[a], A.ready0[a]
    rec.est, rec.lo, rec.hi = ready, ready, ready
    ageConf(rec, now)
    return rec
end

--- (spec §3.1) Seconds: the length learned from the last observed cooldown, else the spec's `cooldown`.
function VS.CooldownLength(spellID)
    local a = A.bySpell[spellID]
    if not a then
        return 0
    end
    if A.cdLen[a] > 0 then
        return A.cdLen[a]
    end
    local c = A.obj[a].cooldown
    return type(c) == "number" and c or 0
end

--- (spec §3.2) Two Beliefs, current charges and the next charge's time; nil for a spell without charges.
function VS.Charges(spellID, now)
    local a = A.bySpell[spellID]
    if not a or not A.ch[a] then
        return nil
    end
    local ch, nx = A.ch[a], A.chNext[a]
    local c, nextAt = A.charges0[a], A.next0[a]
    local max = maxCharges(a)
    local recharge = A.obj[a].recharge
    recharge = type(recharge) == "number" and recharge or 0
    -- recharges the model expects by now
    while c < max and nextAt > 0 and nextAt <= now do
        c = c + 1
        nextAt = c < max and nextAt + recharge or 0
    end
    ch.est, ch.lo, ch.hi = c, c, c
    nx.est, nx.lo, nx.hi = nextAt, nextAt, nextAt
    ageConf(ch, now)
    ageConf(nx, now)
    return ch, nx
end

--- (spec §3.2) The believed end of the GCD.
function VS.Gcd(now)
    ageConf(gcd, now)
    return gcd
end

--- (spec §3.1, §7.5) start, duration of the current GCD as plain numbers fixed between its edges; 0, 0 when none.
function VS.GcdInfo(now)
    if I.gcdStart > 0 and I.gcdStart + I.gcdDur > now then
        I.gcdRead = true -- answered: a later opener's claim no longer changes the duration
        return I.gcdStart, I.gcdDur
    end
    return 0, 0
end

I.OnSnapshot(function(out, now)
    out[#out + 1] = string.format(
        "cast ab=%s end=%.2f channel=%s gcd=%.4f+%.4f learned=%.4f/%.4f owner=%s queued=%s",
        I.castAb > 0 and tostring(A.key[I.castAb]) or "none",
        I.castEnd,
        tostring(I.channel),
        I.gcdStart,
        I.gcdDur,
        I.gcdLearned[1],
        I.gcdLearned[2],
        I.gcdOwner > 0 and tostring(A.key[I.gcdOwner]) or "none",
        tostring(I.queuedStrike)
    )
    for a = 1, A.n do
        VS.Cooldown(A.id[a], now)
        VS.Charges(A.id[a], now)
        out[#out + 1] = string.format(
            "ability %s qid=%d cost=%s read=%s len=%.2f flag=%d multi=%s",
            tostring(A.key[a]),
            A.qid[a],
            tostring(I.CostOf(a)),
            tostring(A.readCost[a]),
            VS.CooldownLength(A.id[a]),
            A.flag[a],
            tostring(A.multiCost[a])
        )
    end
    VS.Gcd(now)
end)
