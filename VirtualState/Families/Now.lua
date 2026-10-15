-- VirtualState/Families/Now.lua
-- `now` handlers (event-facade spec §12a): what our cast did to the now-state, written into the belief at the cast.
-- On each own CastSuccess (a channel's included) the family writes the automatic effects from the ability's declared
-- fields (its cost, its cooldown or charge, the GCD), then runs the ability's `now` function, if the class file
-- declared one beside `handler`, in one shared context whose names are Hekili's verbs (`gain`, `spend`, `applyBuff`,
-- `applyDebuff`, `removeBuff`, `removeDebuff`, `addStack`, `setCooldown`) and reads (`talent`, `buff`, `debuff`, the
-- resources by key, `knownRank`, `now`, `combat`) with belief meanings. Every write is a `modelled` sample at the
-- cast's time, so any later observation overrides it (I.Basis). Hekili's sim `handler` is never read for truth.
-- Allocates nothing per cast: the context, its proxies and every per-ability array are built at SpecChanged.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local CAST = Obs.CastSuccess

local A = I.ab
A.now = {} -- by ability index: the `now` function, bound to the context, or false
A.extra = {} -- by ability index: a `track_<id>` extra (VS.Track): no ability, no effects
A.known = A.known or {} -- by ability index: any rank in the spellbook (Sources/Spellbook.lua)

-- The one environment of every `now` function: the verbs and reads below, and Lua's own pure helpers (no game API,
-- no Hekili state, nothing that allocates by itself).
local SAFE = {
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
}
local ctx = setmetatable({}, { __index = SAFE })
I.nowCtx = ctx
I.nowErrors, I.nowError, I.nowRuns, I.castsRun = 0, nil, 0, 0

-- The cast's belief time and ability while its effects run; `live` only then: a `now` called from anywhere else (Hekili
-- keeps it in `ability.funcs`, where RunStressTest or an APL reading `action.x.now` can call it) writes nothing.
local T, curA, live = 0, 0, false
local abByKey, auraByKey, auraSpell, auraDur, resByKey = {}, {}, {}, {}, {}

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
ctx.buff = setmetatable({}, { __index = noAura })
ctx.debuff = setmetatable({}, { __index = noAura })

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
ctx.talent = setmetatable({}, {
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
ctx.knownRank = VS.KnownRank

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
function ctx.gain(amount, resource)
    shift(amount, resource)
end
function ctx.spend(amount, resource)
    shift(type(amount) == "number" and -amount or amount, resource)
end

local function aura(u, key, duration, stacks)
    local j = auraByKey[key]
    if not live or not j or (u == 2 and I.auras.n < 2) then
        return
    end
    local rec = VS.Aura(u == 1 and "player" or "target", auraSpell[j], T)
    local before = rec and rec.est or 0
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
function ctx.applyBuff(aura_, duration, stacks)
    aura(1, aura_, duration, stacks)
end
function ctx.applyDebuff(unit, aura_, duration, stacks)
    aura(unit == "player" and 1 or 2, aura_, duration, stacks)
end
function ctx.removeBuff(aura_)
    aura(1, aura_, 0)
end
function ctx.removeDebuff(unit, aura_)
    aura(unit == "player" and 1 or 2, aura_, 0)
end
function ctx.addStack(aura_, duration, stacks)
    local j = auraByKey[aura_]
    if not live or not j then
        return
    end
    local _, have = VS.Aura("player", auraSpell[j], T)
    aura(1, aura_, duration, (have or 0) + (stacks or 1))
end
function ctx.setCooldown(action, duration)
    local a = abByKey[action]
    if live and a and type(duration) == "number" then
        I.CooldownModel(a, T + duration, duration, T, CAST)
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
        ctx[k], resByKey[k] = nil, nil
    end
    for k in pairs(ctx.buff) do
        ctx.buff[k], ctx.debuff[k] = nil, nil
    end
    for k in pairs(ctx.talent) do
        ctx.talent[k] = nil
    end
    for a = 1, A.n do
        abByKey[A.key[a]] = a
        A.known[a] = A.known[a] or false
        A.extra[a] = type(A.key[a]) == "string" and A.key[a]:sub(1, 6) == "track_"
        local obj = def.abilities[a]
        local funcs = type(obj) == "table" and rawget(obj, "funcs")
        local f = type(funcs) == "table" and rawget(funcs, "now") -- Hekili keeps unknown functions in `funcs`
        A.now[a] = type(f) == "function" and setfenv(f, ctx) or false
    end
    for j = 1, #def.auras do
        local key = def.auras[j].key
        auraSpell[j] = def.auraIds[j][1]
        local d = rawget(def.auras[j], "duration")
        auraDur[j] = type(d) == "number" and d or false
        if key then
            auraByKey[key] = j
            ctx.buff[key] = setmetatable({ unit = "player", spell = auraSpell[j] }, auraMeta)
            ctx.debuff[key] = setmetatable({ unit = "target", spell = auraSpell[j] }, auraMeta)
        end
    end
    for r = 1, #def.resources do
        local d = def.resources[r]
        if d.key then
            resByKey[d.key] = r
            ctx[d.key] = setmetatable({ type = d.type }, resourceMeta)
        end
    end
    for k = 1, #def.talents do
        local d = def.talents[k]
        ctx.talent[d.key] = setmetatable({ spell = d.spell }, talentMeta)
    end
end)

----------------------------------------------------------------------------------------------------------------------
-- The trigger: our cast's automatic effects, then its `now`.

local function automatic(a, t, kind)
    local obj = A.obj[a]
    local r = A.slot[a]
    if r > 0 then -- an on-next-swing strike's success arrives with its swing, which is when it pays
        local c = I.CostOf(a)
        if c > 0 then
            I.ResourceShift(r, -c, t, kind)
        end
    end
    if A.ch[a] then
        local recharge = type(obj.recharge) == "number" and obj.recharge or 0
        local charges = A.charges0[a] - 1
        local nextAt = A.next0[a] > t and A.next0[a] or t + recharge
        I.ChargesModel(a, charges > 0 and charges or 0, nextAt, t, kind)
    else
        local cd = obj.cooldown
        if type(cd) == "number" and cd > 0 then
            I.CooldownModel(a, t + cd, cd, t, kind)
        end
    end
    if obj.gcd ~= "off" then
        local start = t
        if kind == CAST and A.castStartT[a] > 0 and A.castStartT[a] < t then
            start = A.castStartT[a] -- a hard cast's GCD began at its start
        end
        local h = VS.Haste(t).est
        local len = I.gcdLearned > 0 and I.gcdLearned or 1.5 / (h > 0 and h or 1) -- nonzero: h > 0 checked
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
    automatic(a, t, o.kind)
    I.castsRun = I.castsRun + 1
    local f = A.now[a]
    if f then
        T, curA = t, a
        ctx.now = t
        ctx.combat = I.combatT
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
