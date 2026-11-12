-- Game/State/Families/Auras.lua
-- The auras family (spec §6.3): per unit and tracked aura, the believed expiry, stacks, applied time and an invented
-- stable instance ID; plain walk reads (observed), our casts' handler writes (modelled, Families/Now.lua), expiry by time;
-- per-target memory by slot (TARGET_CAP; Sources/Target.lua keys a slot by GUID, under Map by plate index); the
-- pending-swap serial I.curSwapN; the index order for AuraAt; AuraGen; Count.WithAura; a player aura's
-- stacks spent by hits on the player (its `consumedBy`, tank design §3).
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Auras.lua and Belief/Targets.lua (Applier TargetSwap
-- :147); the aura conf of src/TacoDogForever/Model/Belief.lua:709.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, ReadOf = VS.Obs, I.ReadOf
local HUGE = math.huge
local CDM_OPEN = -ReadOf.AuraOpen -- the sample event of a Cooldown Manager open (no Obs kind is negative)

--- An aura Read's `a` packs the unit index and the aura index; its `c` packs ReadOf.Aura and the stacks.
I.AURA_UNIT = 4096 -- a = (unit - 1) * AURA_UNIT + aura (Hekili registers hundreds of auras)
I.AURA_STACK = 16 -- c = ReadOf.Aura + stacks * AURA_STACK
I.AURA_REFRESH = 0.5 -- a plain read of an `icd` aura expiring this much past the believed one is a re-application

local U = {
    n = 0,
    nAura = 0,
    token = {},
    index = {},
    id = {},
    obj = {},
    bySpell = {},
    byKey = {}, -- aura key -> index (VS.PresenceScope)
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
    icd = {}, -- by aura: its RegisterAura `icd` (seconds), 0 none
    haste = {}, -- by aura: its RegisterAura `swingHaste` (the swing speed's multiplier while up), 0 none
    hasteOn = {}, -- by aura: its `swingHaste` gain was applied and its fall not yet (pairs every gain with one fall)
    firstWalk = {}, -- by unit: the time of its first clean walk (Sources/Auras.lua), 0 none yet
    openFold = {}, -- by unit and aura: the I.folds of its last Cooldown Manager open (I.CastAura), 0 none
    -- by unit and aura: its last fall (I.AuraAsOf): when, and the fallen application's applied time, expiry and stacks
    fellAt = {},
    fellFrom = {},
    fellExp = {},
    fellStacks = {},
}
I.auras = U
-- The believed delta since the drain last delivered it (see `set` below); I.auraDelta for Game/API/Facade.lua.
local D = { add = {}, upd = {}, rem = {}, nAdd = {}, nUpd = {}, nRem = {}, full = {} }
I.auraDelta = D
I.nextInst = 0

-- Per-target memory (spec §6.3): TARGET_CAP slots, each a copy of the target's arrays; slot 0 is "no target".
local memExp, memApplied, memStacks, memInst = {}, {}, {}, {}
I.curSlot = 0
-- The serial of the swap folded last (Sources/Target.lua's I.targetSwapN, copied, never incremented: a swap the log
-- dropped before its fold must not leave the target waiting for ever). Unequal: a swap waits to fold.
I.curSwapN = 0

-- The player auras with a `consumedBy` (a set of I.HitKind names): their indices, and each one's kinds by I.HitKind;
-- each one's `consumeIcd` (seconds, 0 none) and its last spend's time.
local CONS, consKinds, consIcd, consLast = { n = 0 }, {}, {}, {}

I.OnBuild(function(def, now)
    for k in pairs(U.bySpell) do
        U.bySpell[k] = nil
    end
    for k in pairs(U.index) do
        U.index[k] = nil
    end
    for k in pairs(U.byKey) do
        U.byKey[k] = nil
    end
    local auras, units = def.auras, def.units
    U.nAura, U.n = #auras, #units
    for j = 1, U.nAura do
        local ids = def.auraIds[j]
        U.id[j], U.obj[j] = ids[1], auras[j]
        local icd = rawget(auras[j], "icd")
        U.icd[j] = type(icd) == "number" and icd > 0 and icd or 0
        local haste = rawget(auras[j], "swingHaste")
        U.haste[j] = type(haste) == "number" and haste > 0 and haste or 0
        U.hasteOn[j] = false
        if auras[j].key ~= nil then
            U.byKey[auras[j].key] = j
        end
        for k = 1, #ids do
            U.bySpell[ids[k]] = j
        end
    end
    for u = 1, U.n do
        U.token[u], U.index[units[u]] = units[u], u
        local e, ap, st, ins, hm, sq, rc = {}, {}, {}, {}, {}, {}, {}
        local ord, fa, ff, fe, fs = {}, {}, {}, {}, {}
        for j = 1, U.nAura do
            e[j], ap[j], st[j], ins[j], hm[j], sq[j] = 0, 0, 0, 0, u ~= 1, 0
            rc[j] = I.NewBelief("aura " .. units[u] .. " " .. tostring(auras[j].key or U.id[j]))
            ord[j], fa[j], ff[j], fe[j], fs[j] = 0, 0, 0, 0, 0
        end
        U.fellAt[u], U.fellFrom[u], U.fellExp[u], U.fellStacks[u] = fa, ff, fe, fs
        U.exp0[u], U.applied[u], U.stacks[u], U.inst[u], U.harm[u], U.seq[u], U.rec[u] = e, ap, st, ins, hm, sq, rc
        U.ord[u], U.ordN[u], U.gen[u] = ord, 0, 0
        U.firstWalk[u] = 0
        local of = {}
        for j = 1, U.nAura do
            of[j] = 0
        end
        U.openFold[u] = of
        local add, upd, rem = {}, {}, {}
        for j = 1, U.nAura do
            add[j], upd[j], rem[j] = 0, 0, 0
        end
        D.add[u], D.upd[u], D.rem[u] = add, upd, rem
        D.nAdd[u], D.nUpd[u], D.nRem[u], D.full[u] = 0, 0, 0, false
    end
    for s = 1, I.TARGET_CAP do
        local e, ap, st, ins = {}, {}, {}, {}
        for j = 1, U.nAura do
            e[j], ap[j], st[j], ins[j] = 0, 0, 0, 0
        end
        memExp[s], memApplied[s], memStacks[s], memInst[s] = e, ap, st, ins
    end
    I.curSlot = 0 -- the build cleared the log (Sources/Target.lua's hook resets I.curSwapN and logs its own swap)
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
            local icd = rawget(auras[j], "consumeIcd")
            consIcd[CONS.n], consLast[CONS.n] = type(icd) == "number" and icd > 0 and icd or 0, -HUGE
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

-- The believed delta of each unit's set since the drain last delivered it (event-facade spec §2.2, decision 2 phase
-- C; Game/API/Facade.lua delivers it as UNIT_AURA's addedAuras / updatedAuraInstanceIDs / removedAuraInstanceIDs):
-- per unit, the added auras' indices, the updated and removed instance IDs, each list nAura long, and `full` when a
-- whole-set change (a target swap) or an overflow makes a full update the right shape. Preallocated at OnBuild (D).
local function push(list, n, u, v)
    local k = n[u] + 1
    if k > U.nAura then
        D.full[u] = true
    else
        list[u][k], n[u] = v, k
    end
end

-- Writes one aura state on unit u (expiry 0: down). A newly up aura gets a fresh instance ID and walk order.
local function set(u, j, expires, applied, stacks, t, origin, event, harmful)
    local e = U.exp0[u]
    local was, wasStacks = e[j], U.stacks[u][j]
    local inst0 = U.inst[u][j]
    if expires > 0 and was == 0 then
        I.nextInst = I.nextInst + 1
        U.inst[u][j] = I.nextInst
        U.seq[u][j] = I.nextInst
        push(D.add, D.nAdd, u, j)
    end
    if expires <= 0 then
        if was > 0 then
            push(D.rem, D.nRem, u, inst0)
            U.fellAt[u][j], U.fellFrom[u][j] = was < t and was or t, U.applied[u][j] -- a fall by time: when it ran out
            U.fellExp[u][j], U.fellStacks[u][j] = was, wasStacks
        end
        U.inst[u][j] = 0
        expires, applied, stacks = 0, 0, 0
    elseif was > 0 and (was ~= expires or wasStacks ~= stacks) then
        push(D.upd, D.nUpd, u, inst0)
    end
    e[j], U.applied[u][j], U.stacks[u][j] = expires, applied, stacks
    local f = u == 1 and U.haste[j] or 0
    if f > 0 and (expires > 0) ~= U.hasteOn[j] then -- a `swingHaste` aura's gain or fall (aura audit C5)
        U.hasteOn[j] = expires > 0 -- an expired record recast before the sweep stays one application
        local at = (expires <= 0 and was < t) and was or t -- a fall by time: when it ran out
        if I.inCombat and at >= I.combatT then -- out of combat the client's plain speed reads say it
            I.SwingHaste(expires > 0 and f or 1 / f, at) -- nonzero: f > 0
        end
    end
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
    local kind = c % I.AURA_STACK
    if kind ~= ReadOf.Aura and kind ~= ReadOf.AuraOpen and kind ~= ReadOf.AuraHeld and kind ~= ReadOf.AuraVerdict then
        return
    end
    local u = (o.a - o.a % I.AURA_UNIT) / I.AURA_UNIT + 1 -- nonzero: AURA_UNIT is a constant
    local j = o.a % I.AURA_UNIT
    if kind == ReadOf.AuraVerdict then
        -- the verdict's close names the application it judged (o.b: its applied time). Our recast's write, folded
        -- first in this drain (the polls stage after the cast's event was logged), is another application and stands
        -- (Fable 5.2 review M1; F3's pattern). Only a close that happened is counted (Sources/Auras.lua).
        if U.exp0[u][j] > 0 and U.applied[u][j] == o.b then
            set(u, j, 0, 0, 0, t, "observed", Obs.Read)
            I.AuraVerdictClosed(o.a, o.t)
        end
        return
    end
    local stacks = (c - kind) / I.AURA_STACK -- nonzero: AURA_STACK is a constant
    -- a Cooldown Manager write is sampled with no read event (I.AuraModel's "the read wins" is for a client expiry
    -- only); an open with its own mark, for I.CastAura
    local event = kind == ReadOf.Aura and Obs.Read or kind == ReadOf.AuraOpen and CDM_OPEN or 0
    if o.b == 0 then
        set(u, j, 0, 0, 0, t, "observed", event)
    elseif kind == ReadOf.AuraOpen and U.exp0[u][j] > o.t then
        return -- a CDM UP staged while the record was down; our cast's write, folded first in this drain, stands (F3)
    else
        local expires = o.b < 0 and HUGE or o.t + o.b
        local was, icd = U.exp0[u][j], U.icd[j]
        local applied
        if was > 0 and not (icd > 0 and expires > was + I.AURA_REFRESH) then
            -- up: the same application. Only a proc aura with an ICD takes a later expiry as a re-application (its ICD
            -- restarts, State.lua icd_remains); any other keeps its applied time, which times its tick phase (Resources.lua's
            -- periodic gains and mult overlap, State.lua's ticks), and a refresh keeps the phase.
            applied = U.applied[u][j]
        elseif was == 0 and icd > 0 and not (U.firstWalk[u] > 0 and U.firstWalk[u] < o.t) then
            -- first seen up in the unit's first clean walk (a reload, a login): the gain is unknown, so its ICD reads
            -- ready (an unknown ICD never blocks): applied is put one ICD back, a sentinel only `icd` auras get
            applied = o.t - icd
        else
            applied = o.t
        end
        set(u, j, expires, applied, stacks > 0 and stacks or 1, t, "observed", event)
        if kind == ReadOf.AuraOpen then
            U.openFold[u][j] = I.folds
        end
    end
end)

I.auraReadsWon = 0

--- VS.Aura for our cast's own handler at t (Families/Now.lua's reads): a record a Cooldown Manager light opened in this
--- drain's fold or the one just before, with no model since, is the cast's own application seen early (the light polled
--- a drain before the cast's event was logged), so it reads down: a handler's `stack + 1` or addStack does not count
--- it twice. Drains, not seconds (review S3). Allocates nothing.
function I.CastAura(unit, spellID, t)
    local u, j = U.index[unit], U.bySpell[spellID]
    if u and j then
        local last = U.rec[u][j].last
        local o = last.observed
        if o.event == CDM_OPEN and U.openFold[u][j] >= I.folds - 1 and o.t >= last.modelled.t and U.exp0[u][j] > t then
            return nil
        end
    end
    return VS.Aura(unit, spellID, t)
end

--- I.CastAura as of a past t (a reaction folded after its outcome: Families/Now.lua): an application later than t
--- reads down, and the last one fallen after t reads up as it was. Expiry (nil: down), stacks, applied. Allocates
--- nothing.
--- shortcut: one fall deep, and a refresh after t (a later applied time) reads down; upgrade with a per-aura history
--- if a reaction shows either.
function I.AuraAsOf(unit, spellID, t)
    local rec, stacks, applied = I.CastAura(unit, spellID, t)
    if rec and applied <= t then
        return rec.est, stacks, applied
    end
    local u, j = U.index[unit], U.bySpell[spellID]
    if u and j and U.fellFrom[u][j] <= t and U.fellAt[u][j] > t then
        return U.fellExp[u][j], U.fellStacks[u][j], U.fellFrom[u][j]
    end
    return nil
end

--- Our own cast changed aura j on unit u (spec §5.3): a `modelled` expiry with its stacks and applied time. A plain
--- read that saw the aura up in the cast's frame or later already includes the cast (its stack, say): the read wins
--- and the modelled change is dropped (counted), so the cast is not applied twice. `closes` (a charge spend taking the
--- last stack, Families/Modifiers.lua): an up-read before the cast, even in its frame, cannot include a close, so only
--- a read at the cast's time or later wins (one at its time: a proc the cast itself raised) (L576).
function I.AuraModel(u, j, applied, expires, stacks, t, event, harmful, closes)
    local seen = U.rec[u][j].last.observed
    local from = closes and t or t - I.SAME_FRAME
    if seen.event == Obs.Read and seen.v > 0 and seen.t >= from then
        I.auraReadsWon = I.auraReadsWon + 1
        return
    end
    set(u, j, expires, applied, stacks > 0 and stacks or 1, t, "modelled", event, harmful)
end

-- A hit of a listed kind spends one stack of each `consumedBy` player aura believed up (a modelled sample at the hit),
-- and takes it down at 0; an aura with `consumeIcd` spends at most one a window from its last spend (wowsims's ICD
-- timer: a recast keeps it running). The floor (decision 114): a generic input by aura, default 0; while floor[j] is 1 the last
-- stack is kept (its writer says the aura is seen up: the hit count is not what closes it). Allocates nothing.
local floor = I.auraFloor or {}
I.auraFloor = floor
I.On(Obs.PlayerHit, function(o, t)
    for k = 1, CONS.n do
        local j = CONS[k]
        if consKinds[k][o.a] and U.exp0[1][j] > t and t - consLast[k] >= consIcd[k] then -- unit 1: "player"
            consLast[k] = t
            local n = U.stacks[1][j] - 1
            if n > 0 then
                set(1, j, U.exp0[1][j], U.applied[1][j], n, t, "modelled", Obs.PlayerHit)
            elseif floor[j] ~= 1 then
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
    D.full[2] = true -- the whole set changed: a full update, not a delta
    changed(2)
end

-- TargetSwap: a is the new target's memory slot (0: none). TargetGone: forget slot a.
I.On(Obs.TargetSwap, function(o)
    save(I.curSlot)
    I.curSlot, I.curSwapN = o.a, I.targetSwapN
    load(o.a)
end)

I.On(Obs.TargetGone, function(o)
    local s = o.a
    if s > 0 then
        for j = 1, U.nAura do -- all four (review m2): a reused slot's load must bring no old mob's stacks
            memExp[s][j], memApplied[s][j], memStacks[s][j], memInst[s][j] = 0, 0, 0, 0
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
