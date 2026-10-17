-- Virtual/State/Families/Auras.lua
-- The auras family (spec §6.3): per unit and tracked aura, the believed expiry, stacks, applied time and an invented
-- stable instance ID; plain walk reads (observed), our casts' handler writes (modelled, Adapter.lua), expiry by time;
-- per-target memory by GUID slot (TARGET_CAP); the index order for AuraAt; AuraGen; Count.WithAura; a player aura's
-- stacks spent by hits on the player (its `consumedBy`, tank design §3).
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Auras.lua and Belief/Targets.lua (Applier TargetSwap
-- :147); the aura conf of src/TacoDogForever/Model/Belief.lua:709.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, ReadOf = VS.Obs, I.ReadOf
local HUGE = math.huge

--- An aura Read's `a` packs the unit index and the aura index; its `c` packs ReadOf.Aura and the stacks.
I.AURA_UNIT = 4096 -- a = (unit - 1) * AURA_UNIT + aura (Hekili registers hundreds of auras)
I.AURA_STACK = 16 -- c = ReadOf.Aura + stacks * AURA_STACK

local U = {
    n = 0,
    nAura = 0,
    token = {},
    index = {},
    id = {},
    obj = {},
    bySpell = {},
    exp0 = {},
    applied = {},
    stacks = {},
    inst = {},
    harm = {},
    seq = {},
    rec = {},
    ord = {},
    ordN = {},
    gen = {},
    mem = {},
}
I.auras = U
I.nextInst = 0

-- Per-target memory (spec §6.3): TARGET_CAP slots, each a copy of the target's arrays; slot 0 is "no target".
local memExp, memApplied, memStacks, memInst = {}, {}, {}, {}
I.curSlot = 0

-- The player auras with a `consumedBy` (a set of I.HitKind names): their indices, and each one's kinds by I.HitKind.
local CONS, consKinds = { n = 0 }, {}

I.OnBuild(function(def, now)
    for k in pairs(U.bySpell) do
        U.bySpell[k] = nil
    end
    for k in pairs(U.index) do
        U.index[k] = nil
    end
    local auras, units = def.auras, def.units
    U.nAura, U.n = #auras, #units
    for j = 1, U.nAura do
        local ids = def.auraIds[j]
        U.id[j], U.obj[j] = ids[1], auras[j]
        for k = 1, #ids do
            U.bySpell[ids[k]] = j
        end
    end
    for u = 1, U.n do
        U.token[u], U.index[units[u]] = units[u], u
        local e, ap, st, ins, hm, sq, rc = {}, {}, {}, {}, {}, {}, {}
        local ord = {}
        for j = 1, U.nAura do
            e[j], ap[j], st[j], ins[j], hm[j], sq[j] = 0, 0, 0, 0, u ~= 1, 0
            rc[j] = I.NewBelief("aura " .. units[u] .. " " .. tostring(auras[j].key or U.id[j]))
            ord[j] = 0
        end
        U.exp0[u], U.applied[u], U.stacks[u], U.inst[u], U.harm[u], U.seq[u], U.rec[u] = e, ap, st, ins, hm, sq, rc
        U.ord[u], U.ordN[u], U.gen[u] = ord, 0, 0
    end
    for s = 1, I.TARGET_CAP do
        local e, ap, st, ins = {}, {}, {}, {}
        for j = 1, U.nAura do
            e[j], ap[j], st[j], ins[j] = 0, 0, 0, 0
        end
        memExp[s], memApplied[s], memStacks[s], memInst[s] = e, ap, st, ins
    end
    I.curSlot = 0
    CONS.n = 0
    for j = 1, U.nAura do
        local by = rawget(auras[j], "consumedBy")
        if type(by) == "table" then
            CONS.n = CONS.n + 1
            CONS[CONS.n] = j
            local kinds = {}
            for name in pairs(by) do
                local kind = I.HitKind[name]
                if kind then
                    kinds[kind] = true
                end
            end
            consKinds[CONS.n] = kinds
        end
    end
    I.TRACKED.aura = U.id
    I.TRACKED.unit = U.token
end)

-- Re-sorts unit u's index order (applied ascending, then walk order) and bumps its AuraGen. Allocates nothing.
local function changed(u)
    local ord, e, ap, sq = U.ord[u], U.exp0[u], U.applied[u], U.seq[u]
    local n = 0
    for j = 1, U.nAura do
        if e[j] > 0 then
            n = n + 1
            local k = n
            while k > 1 do
                local p = ord[k - 1]
                if ap[p] < ap[j] or ap[p] == ap[j] and sq[p] <= sq[j] then
                    break
                end
                ord[k] = p
                k = k - 1
            end
            ord[k] = j
        end
    end
    U.ordN[u] = n
    U.gen[u] = U.gen[u] + 1
end

-- Writes one aura state on unit u (expiry 0: down). A newly up aura gets a fresh instance ID and walk order.
local function set(u, j, expires, applied, stacks, t, origin, event, harmful)
    local e = U.exp0[u]
    local was, wasStacks = e[j], U.stacks[u][j]
    if expires > 0 and was == 0 then
        I.nextInst = I.nextInst + 1
        U.inst[u][j] = I.nextInst
        U.seq[u][j] = I.nextInst
    end
    if expires <= 0 then
        U.inst[u][j] = 0
        expires, applied, stacks = 0, 0, 0
    end
    e[j], U.applied[u][j], U.stacks[u][j] = expires, applied, stacks
    if harmful ~= nil then
        U.harm[u][j] = harmful
    end
    local rec = U.rec[u][j]
    rec.est, rec.lo, rec.hi = expires, expires, expires
    I.Sample(rec, origin, expires, t, event)
    if was ~= expires or wasStacks ~= stacks then
        changed(u)
    end
end

I.On(Obs.Read, function(o, t)
    local c = o.c
    if c % I.AURA_STACK ~= ReadOf.Aura then
        return
    end
    local u = (o.a - o.a % I.AURA_UNIT) / I.AURA_UNIT + 1 -- nonzero: AURA_UNIT is a constant
    local j = o.a % I.AURA_UNIT
    local stacks = (c - ReadOf.Aura) / I.AURA_STACK -- nonzero: AURA_STACK is a constant
    if o.b == 0 then
        set(u, j, 0, 0, 0, t, "observed", Obs.Read)
    else
        local expires = o.b < 0 and HUGE or o.t + o.b
        local applied = U.exp0[u][j] > 0 and U.applied[u][j] or o.t
        set(u, j, expires, applied, stacks > 0 and stacks or 1, t, "observed", Obs.Read)
    end
end)

I.auraReadsWon = 0

--- Our own cast changed aura j on unit u (spec §5.3): a `modelled` expiry with its stacks and applied time. A plain
--- read that saw the aura up in the cast's frame or later already includes the cast (its stack, say): the read wins
--- and the modelled change is dropped (counted), so the cast is not applied twice.
function I.AuraModel(u, j, applied, expires, stacks, t, event, harmful)
    local seen = U.rec[u][j].last.observed
    if seen.event == Obs.Read and seen.v > 0 and seen.t >= t - I.SAME_FRAME then
        I.auraReadsWon = I.auraReadsWon + 1
        return
    end
    set(u, j, expires, applied, stacks > 0 and stacks or 1, t, "modelled", event, harmful)
end

-- A hit of a listed kind spends one stack of each `consumedBy` player aura believed up (a modelled sample at the hit),
-- and takes it down at 0. Allocates nothing.
I.On(Obs.PlayerHit, function(o, t)
    for k = 1, CONS.n do
        local j = CONS[k]
        if consKinds[k][o.a] and U.exp0[1][j] > t then -- unit 1 is always "player" (Adapter.lua's def.units)
            local n = U.stacks[1][j] - 1
            if n > 0 then
                set(1, j, U.exp0[1][j], U.applied[1][j], n, t, "modelled", Obs.PlayerHit)
            else
                set(1, j, 0, 0, 0, t, "modelled", Obs.PlayerHit)
            end
        end
    end
end)

-- Per-target memory: the target's arrays into slot s, and back.
local function save(s)
    if s == 0 or U.n < 2 then
        return
    end
    local e, ap, st, ins = U.exp0[2], U.applied[2], U.stacks[2], U.inst[2]
    for j = 1, U.nAura do
        memExp[s][j], memApplied[s][j], memStacks[s][j], memInst[s][j] = e[j], ap[j], st[j], ins[j]
    end
end

local function load(s)
    if U.n < 2 then
        return
    end
    local e, ap, st, ins = U.exp0[2], U.applied[2], U.stacks[2], U.inst[2]
    for j = 1, U.nAura do
        if s == 0 then
            e[j], ap[j], st[j], ins[j] = 0, 0, 0, 0
        else
            e[j], ap[j], st[j], ins[j] = memExp[s][j], memApplied[s][j], memStacks[s][j], memInst[s][j]
        end
        local rec = U.rec[2][j]
        rec.est, rec.lo, rec.hi = e[j], e[j], e[j]
        local seen = rec.last.observed -- the old target's read: it must not stop or outrank a cast on this one
        seen.t, seen.event = 0, 0
    end
    changed(2)
end

-- TargetSwap: a is the new target's memory slot (0: none). TargetGone: forget slot a.
I.On(Obs.TargetSwap, function(o)
    save(I.curSlot)
    I.curSlot = o.a
    load(o.a)
end)

I.On(Obs.TargetGone, function(o)
    local s = o.a
    if s > 0 then
        for j = 1, U.nAura do
            memExp[s][j] = 0
        end
        if s == I.curSlot then
            load(0)
        end
    end
end)

-- Expiry by time: an aura whose expiry passed is down (an AuraGen bump lets Hekili rescan).
I.OnSettle(function(now)
    for u = 1, U.n do
        local e = U.exp0[u]
        for j = 1, U.nAura do
            if e[j] > 0 and e[j] <= now then
                set(u, j, 0, 0, 0, now, "modelled", 0)
            end
        end
    end
end)

local function proj(u, j, now)
    local rec = U.rec[u][j]
    local e = U.exp0[u][j]
    rec.est, rec.lo, rec.hi = e, e, e
    I.AgeConf(rec, now)
    return rec
end

--- (spec §3.2) Belief expiry, then stacks, applied, instanceID; nil when not believed up.
function VS.Aura(unit, spellID, now)
    local u, j = U.index[unit], U.bySpell[spellID]
    if not u or not j or U.exp0[u][j] <= now then
        return nil
    end
    return proj(u, j, now), U.stacks[u][j], U.applied[u][j], U.inst[u][j]
end

--- (spec §3.2) The i-th believed aura on `unit` matching "HELPFUL"/"HARMFUL" (applied time ascending, then walk
--- order; only auras with est > now): spellID, Belief expiry, stacks, applied, instanceID; nil past the last.
function VS.AuraAt(unit, filter, i, now)
    local u = U.index[unit]
    if not u then
        return nil
    end
    local harmful = filter == "HARMFUL"
    local ord, e, hm = U.ord[u], U.exp0[u], U.harm[u]
    local k = 0
    for n = 1, U.ordN[u] do
        local j = ord[n]
        if e[j] > now and hm[j] == harmful then
            k = k + 1
            if k == i then
                return U.id[j], proj(u, j, now), U.stacks[u][j], U.applied[u][j], U.inst[u][j]
            end
        end
    end
    return nil
end

--- (spec §3.2) spellID, Belief expiry, stacks, applied for a believed aura by its instance ID; nil when gone.
function VS.AuraByInstance(unit, instanceID, now)
    local u = U.index[unit]
    if not u or not instanceID or instanceID <= 0 then
        return nil
    end
    local ins, e = U.inst[u], U.exp0[u]
    for j = 1, U.nAura do
        if ins[j] == instanceID and e[j] > now then
            return U.id[j], proj(u, j, now), U.stacks[u][j], U.applied[u][j]
        end
    end
    return nil
end

--- (spec §3.1) Bumped whenever the unit's believed aura set changes.
function VS.AuraGen(unit)
    local u = U.index[unit]
    return u and U.gen[u] or 0
end

--- (spec §3.3) Tracked units (the target and remembered target slots) on which the aura is believed up.
function VS.Count.WithAura(spellID, now)
    local j = U.bySpell[spellID]
    if not j or U.n < 2 then
        return 0
    end
    local n = U.exp0[2][j] > now and 1 or 0
    for s = 1, I.TARGET_CAP do
        if s ~= I.curSlot and memExp[s][j] > now then
            n = n + 1
        end
    end
    return n
end

I.OnSnapshot(function(out, now)
    out[#out + 1] = string.format("aura reads won=%d", I.auraReadsWon)
    for u = 1, U.n do
        out[#out + 1] = string.format("auras %s gen=%d up=%d", U.token[u], U.gen[u], U.ordN[u])
        for j = 1, U.nAura do
            proj(u, j, now)
        end
    end
end)
