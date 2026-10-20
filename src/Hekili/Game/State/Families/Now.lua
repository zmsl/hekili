-- Game/State/Families/Now.lua
-- `now` handlers (event-facade spec §12a): what our cast did to the now-state, written into the belief at the cast.
-- On each own CastSuccess (a channel's included) the family writes the automatic effects from the ability's declared
-- fields (its cost, its cooldown or charge, the GCD), then runs the ability's `now` function, if the class file
-- declared one beside `handler`, in one shared context whose names are Hekili's verbs (`gain`, `spend`, `applyBuff`,
-- `applyDebuff`, `removeBuff`, `removeDebuff`, `addStack`, `setCooldown`, `summonTotem`, `summonPet`) and reads
-- (`talent`, `buff`, `debuff`, the resources by key, `knownRank`, `stat`, `swingBase`, `healthMax`, `now`, `combat`)
-- with belief meanings. Every write is a `modelled` sample at the cast's time, so any later observation overrides it (I.Basis). Hekili's sim `handler` is never read for truth.
-- An avoid of the latest cast (Obs.Avoided) undoes its target debuffs and refunds its resource's `refundOnAvoid` share.
-- Allocates nothing per cast: the context, its proxies and every per-ability array are built at SpecChanged.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local CAST = Obs.CastSuccess

local A = I.ab
A.now = {} -- by ability index: the `now` function, bound to the context, or false
A.extra = {} -- by ability index: a `track_<id>` extra (VS.Track): no ability, no effects
A.known = A.known or {} -- by ability index: any rank in the spellbook (Sources/Spellbook.lua)

-- The names of every `now` function's environment: the verbs and reads below, and Lua's own pure helpers (no game
-- API, no Hekili state, nothing that allocates by itself).
local NAMES = {
    math = math,
    min = math.min,
    max = math.max,
    floor = math.floor,
    ceil = math.ceil,
    abs = math.abs,
    type = type,
    select = select,
    tonumber = tonumber,
    error = error,
    now = 0, -- set per cast and per I.NowAt; seeded so the first set adds no key on a per-event path
    combat = 0,
}
-- The environment itself stays empty, so every assignment from a `now` raises (a counted error) instead of
-- shadowing a verb for every later cast.
local ctx = setmetatable({}, {
    __index = NAMES,
    __newindex = function(_, k)
        error("now: assigns the global " .. tostring(k), 2)
    end,
})
I.nowCtx = ctx
I.nowErrors, I.nowError, I.nowRuns, I.castsRun = 0, nil, 0, 0

-- The cast's belief time and ability while its effects run; `live` only then: a `now` called from anywhere else (Hekili
-- keeps it in `ability.funcs`, where RunStressTest or an APL reading `action.x.now` can call it) writes nothing.
local T, curA, live = 0, 0, false

-- The latest cast's undo (Obs.Avoided): its ability and time, the cost it paid, and the target auras its `now` wrote,
-- each as it was before (expiry 0: down), at most UNDO of them. Preallocated.
local UNDO = 4
local undoA, undoT, paid, undoN = 0, -1, 0, 0
local undoJ, undoE, undoAp, undoSt = {}, {}, {}, {}
for k = 1, UNDO do
    undoJ[k], undoE[k], undoAp[k], undoSt[k] = 0, 0, 0, 0
end
local refund = {} -- by resource slot: the fraction of an avoided cast's cost returned (its `refundOnAvoid`), 0 none
I.avoidsRun = 0

--- The context's reads answer at `t` from now on (a resource's `taken`, run at a hit: Families/Resources.lua); its
--- verbs stay inert outside a cast. Allocates nothing.
function I.NowAt(t)
    T = t
    rawset(NAMES, "now", t)
    rawset(NAMES, "combat", I.combatT) -- as `run` does
end
local abByKey, auraByKey, auraSpell, auraDur, auraMax, resByKey = {}, {}, {}, {}, {}, {}

----------------------------------------------------------------------------------------------------------------------
-- Reads: proxies built at SpecChanged, answered from the belief at the cast's time.

local function auraField(r, f)
    local rec, stacks, applied = VS.Aura(rawget(r, "unit"), rawget(r, "spell"), T)
    if f == "up" then
        return rec ~= nil
    elseif f == "down" then
        return rec == nil
    elseif f == "remains" then
        return rec and rec.est - T or 0
    elseif f == "stack" or f == "count" then
        return rec and stacks or 0
    elseif f == "expires" then
        return rec and rec.est or 0
    elseif f == "applied" then
        return rec and applied or 0
    end
    return nil
end
local auraMeta = { __index = auraField }
local NO_AURA = setmetatable({ unit = "player", spell = 0 }, auraMeta)
local function noAura()
    return NO_AURA
end
NAMES.buff = setmetatable({}, { __index = noAura })
NAMES.debuff = setmetatable({}, { __index = noAura })

local talentMeta = {
    __index = function(r, f)
        local rank = VS.Talent(rawget(r, "spell"))
        if f == "rank" then
            return rank
        elseif f == "enabled" then
            return rank > 0
        end
        return nil
    end,
}
local NO_TALENT = setmetatable({ spell = 0 }, talentMeta)
NAMES.talent = setmetatable({}, {
    __index = function()
        return NO_TALENT
    end,
})

local resourceMeta = {
    __index = function(r, f)
        local pt = rawget(r, "type")
        if f == "current" then
            return VS.Power(pt, T).est
        elseif f == "max" then
            return I.res.max[I.res.slotOf[pt]] or 0
        end
        return nil
    end,
}

--- The highest known rank of a tracked ability's rank list (1-based), 0 when none is known or the list is untracked.
--- Reads the belief's spellbook, never the game: the class file's own `knownRank` may call it in both its sim and its
--- `now` environments. Allocates nothing.
function VS.KnownRank(ids)
    local a = ids and A.bySpell[ids[1]]
    if not a or not A.known[a] then
        return 0
    end
    local q = A.qid[a]
    for k = #ids, 1, -1 do
        if ids[k] == q then
            return k
        end
    end
    return 0
end
NAMES.knownRank = VS.KnownRank
-- The belief's other plain reads content uses (Families/Player.lua, Swing.lua), as in the sim's `state` (State.lua).
-- Here `stat` is a plain function, stat(name, arg); in the sim it is also the stat table (`stat.crit`), which a `now`
-- handler cannot read.
NAMES.stat, NAMES.swingBase, NAMES.healthMax = VS.Stat, VS.SwingBase, VS.HealthMax

--- The known rank's spell ID for any rank ID of a tracked ability with a known rank, else `spellID` unchanged (nil,
--- untracked or unknown). The client answers range only for a known rank (core edit E5). Allocates nothing.
function VS.KnownID(spellID)
    local a = spellID and A.bySpell[spellID]
    if a and A.known[a] then
        return A.qid[a]
    end
    return spellID
end
ns.KnownSpellID = VS.KnownID -- State.lua's range reads (E5) reach it through `ns`, not Hekili.Virtual

----------------------------------------------------------------------------------------------------------------------
-- Writes: Hekili's verbs, as `modelled` belief samples at T (and the combat log's aura and energize rows).

local function shift(n, resource)
    if not live then
        return
    end
    local r = resByKey[resource]
    if not r then
        error("now: no tracked resource " .. tostring(resource), 3) -- counted as the `now`'s error; no write
    end
    if type(n) ~= "number" or n == 0 then
        return
    end
    I.ResourceShift(r, n, T, CAST)
    if n > 0 then
        I.Log.Energize(A.qid[curA], n, I.res.type[r], I.res.max[r], T)
    end
end
function NAMES.gain(amount, resource)
    shift(amount, resource)
end
function NAMES.spend(amount, resource)
    shift(type(amount) == "number" and -amount or amount, resource)
end

local function aura(u, key, duration, stacks)
    local j = auraByKey[key]
    if not live or not j or (u == 2 and I.auras.n < 2) then
        return
    end
    local rec, have, applied = VS.Aura(u == 1 and "player" or "target", auraSpell[j], T)
    local before = rec and rec.est or 0
    if u == 2 and undoN < UNDO then
        local first = true
        for k = 1, undoN do
            first = first and undoJ[k] ~= j
        end
        if first then -- as it was before the cast: a second write of the same aura keeps the first's
            undoN = undoN + 1
            undoJ[undoN], undoE[undoN], undoAp[undoN], undoSt[undoN] = j, before, applied or 0, have or 0
        end
    end
    local after = 0
    if duration ~= 0 then
        local d = duration or auraDur[j]
        if type(d) ~= "number" then
            return -- the aura's registered duration is a function (Hekili's state): the `now` must pass one
        end
        after = T + d
    end
    I.AuraModel(u, j, T, after, stacks or 1, T, CAST, u == 2)
    I.Log.Aura(u, j, auraSpell[j], before, after, T)
end
-- Hekili's own signatures (State.lua), so a Classic handler's lines port by copying.
function NAMES.applyBuff(aura_, duration, stacks)
    aura(1, aura_, duration, stacks)
end
function NAMES.applyDebuff(unit, aura_, duration, stacks)
    aura(unit == "player" and 1 or 2, aura_, duration, stacks)
end
function NAMES.removeBuff(aura_)
    aura(1, aura_, 0)
end
function NAMES.removeDebuff(unit, aura_)
    aura(unit == "player" and 1 or 2, aura_, 0)
end
function NAMES.addStack(aura_, duration, stacks)
    local j = auraByKey[aura_]
    if not live or not j then
        return
    end
    local _, have = VS.Aura("player", auraSpell[j], T)
    local n = (have or 0) + (stacks or 1)
    aura(1, aura_, duration, n < auraMax[j] and n or auraMax[j]) -- Hekili's max_stack clamp (State.lua:837-852)
end
function NAMES.setCooldown(action, duration)
    local a = abByKey[action]
    if live and a and type(duration) == "number" then
        I.CooldownModel(a, T + duration, duration, T, CAST)
    end
end

-- The totem slots by element, as Hekili's `state.totem` numbers them (State.lua's mt_totem; the client's slot order).
local TOTEM_SLOT = { fire = 1, earth = 2, water = 3, air = 4 }
--- summonTotem(name, element, duration): Hekili's signature (State.lua); the element's slot expires `duration` s after
--- the cast (an unknown element or a non-number duration writes nothing).
function NAMES.summonTotem(name, elem, duration)
    local slot = TOTEM_SLOT[elem]
    if live and slot and type(duration) == "number" then
        I.TotemModel(slot, T + duration, A.qid[curA], type(name) == "string" and name or "", T, CAST)
    end
end

--- summonPet(key, duration): Hekili's name (its third argument, `spec`, is not read). A guardian (a pet registered with
--- a `cap`) gains one expiring `duration` s after the cast (no number: its registered duration); any other key models
--- the pet unit up until the first observation (Families/Pets.lua).
function NAMES.summonPet(key, duration)
    if live and type(key) == "string" then
        I.PetModel(key, duration, T, CAST)
    end
end

----------------------------------------------------------------------------------------------------------------------
-- The tracked set: keys to indices, proxies, and each ability's `now` bound to the context.

I.OnBuild(function(def)
    for k in pairs(abByKey) do
        abByKey[k] = nil
    end
    for k in pairs(auraByKey) do
        auraByKey[k] = nil
    end
    for k in pairs(resByKey) do
        rawset(NAMES, k, nil)
        resByKey[k] = nil
    end
    for k in pairs(NAMES.buff) do
        NAMES.buff[k], NAMES.debuff[k] = nil, nil
    end
    for k in pairs(NAMES.talent) do
        NAMES.talent[k] = nil
    end
    for a = 1, A.n do
        abByKey[A.key[a]] = a
        A.known[a] = A.known[a] or false
        A.extra[a] = type(A.key[a]) == "string" and A.key[a]:sub(1, 6) == "track_"
        local obj = def.abilities[a]
        local funcs = type(obj) == "table" and rawget(obj, "funcs")
        local f = type(funcs) == "table" and rawget(funcs, "now") -- Hekili keeps unknown functions in `funcs`
        if type(f) == "function" and (f == rawget(funcs, "handler") or f == rawget(obj, "handler")) then
            -- rebinding it would move the sim handler into the `now` context
            I.nowErrors, I.nowError = I.nowErrors + 1, "now: " .. tostring(A.key[a]) .. "'s now is its handler"
            f = false
        end
        A.now[a] = type(f) == "function" and setfenv(f, ctx) or false
    end
    for j = 1, #def.auras do
        local key = def.auras[j].key
        auraSpell[j] = def.auraIds[j][1]
        local d = rawget(def.auras[j], "duration")
        auraDur[j] = type(d) == "number" and d or false
        local m = rawget(def.auras[j], "max_stack")
        auraMax[j] = type(m) == "number" and m or 1
        if key then
            auraByKey[key] = j
            NAMES.buff[key] = setmetatable({ unit = "player", spell = auraSpell[j] }, auraMeta)
            NAMES.debuff[key] = setmetatable({ unit = "target", spell = auraSpell[j] }, auraMeta)
        end
    end
    for r = 1, #def.resources do
        local d = def.resources[r]
        local f = d.refundOnAvoid
        refund[r] = type(f) == "number" and f > 0 and f <= 1 and f or 0
        if d.key then
            resByKey[d.key] = r
            rawset(NAMES, d.key, setmetatable({ type = d.type }, resourceMeta))
        end
    end
    for k = 1, #def.talents do
        local d = def.talents[k]
        NAMES.talent[d.key] = setmetatable({ spell = d.spell }, talentMeta)
    end
end)

----------------------------------------------------------------------------------------------------------------------
-- The trigger: our cast's automatic effects, then its `now`.

local function automatic(a, t, kind, o)
    local obj = A.obj[a]
    local r = A.slot[a]
    if r > 0 then -- an on-next-swing strike's success arrives with its swing, which is when it pays
        local c = I.CastCost(o, a)
        paid = c
        if c > 0 then
            I.ResourceShift(r, -c, t, kind)
        end
        -- a charged cost modifier in scope loses a stack, even when its discount made the cast free (Modifiers.lua)
        if I.BaseCostOf(a) > 0 then
            I.SpendCostCharges(a, r, t, kind)
        end
    end
    if A.ch[a] then
        local recharge = type(obj.recharge) == "number" and obj.recharge or 0
        local ch, nx = VS.Charges(A.id[a], t) -- the recharges finished since the last sample, caught up to t
        local charges, nextAt = ch.est - 1, nx.est
        if nextAt <= t then
            nextAt = t + recharge -- it was at max: the recharge starts now
        end
        I.ChargesModel(a, charges > 0 and charges or 0, nextAt, t, kind)
    else
        local cd = obj.cooldown
        if type(cd) == "number" and cd > 0 then
            I.CooldownModel(a, t + cd, cd, t, kind)
        end
    end
    if A.gcdKind[a] > 0 then
        local start = t
        if kind == CAST and A.castStartT[a] > 0 and A.castStartT[a] < t then
            start = A.castStartT[a] -- a hard cast's GCD began at its start
        end
        local len = I.GcdLen(a, t) -- its kind's (Families/Casts.lua)
        if start + len > t then
            I.GcdModel(start + len, t, kind)
        end
    end
end

local function run(o, t)
    local a = o.a
    if not A.obj[a] or not A.key[a] or A.extra[a] then
        return
    end
    undoA, undoT, paid, undoN = a, o.t, 0, 0
    automatic(a, t, o.kind, o)
    A.castStartT[a] = 0 -- consumed: a later instant cast of the same ability starts its own GCD
    I.castsRun = I.castsRun + 1
    local f = A.now[a]
    if f then
        T, curA = t, a
        rawset(NAMES, "now", t)
        rawset(NAMES, "combat", I.combatT)
        live = true
        local ok, err = pcall(f)
        live = false
        I.nowRuns = I.nowRuns + 1
        if not ok then
            I.nowErrors, I.nowError = I.nowErrors + 1, err
        end
    end
end
-- CastSuccess only: a channel stages ChannelStart and CastSuccess both (Sources/Casts.lua), and must run once.
I.On(Obs.CastSuccess, run)

-- Our cast's own avoid (Events/Rows.lua): the latest cast, when it is the one avoided, loses the target auras its `now`
-- wrote (each back as it was) and gets back its resource's `refundOnAvoid` share of the cost it paid; both `modelled` at
-- the outcome. Any other cast's avoid changes nothing (its effects are no longer the latest's to undo). The cooldown,
-- the GCD and the player auras stay (an avoided ability still triggers them). Allocates nothing.
I.On(Obs.Avoided, function(o, t)
    if o.a ~= undoA or o.b ~= undoT then
        return
    end
    undoA = 0
    for k = 1, undoN do
        local j = undoJ[k]
        local rec = VS.Aura("target", auraSpell[j], t)
        local was, back = rec and rec.est or 0, undoE[k] > t and undoE[k] or 0
        I.AuraModel(2, j, undoAp[k], back, back > 0 and undoSt[k] or 0, t, Obs.Avoided, true)
        I.Log.Aura(2, j, auraSpell[j], was, back, t)
    end
    local r = A.slot[o.a]
    if r > 0 and paid > 0 and refund[r] > 0 then
        I.ResourceShift(r, paid * refund[r], t, Obs.Avoided)
    end
    I.avoidsRun = I.avoidsRun + 1
end)
