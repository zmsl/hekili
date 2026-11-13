-- Game/State/Families/Now.lua
-- `now` handlers (event-facade spec §12a): what our cast did to the now-state, written into the belief at the cast.
-- On each own CastSuccess (a channel's included) the family writes the automatic effects from the ability's declared
-- fields (its cost, its cooldown or charge, the GCD), then runs the ability's `now` function, if the class file
-- declared one beside `handler`, in one shared context whose names are Hekili's verbs (`gain`, `spend`, `applyBuff`,
-- `applyDebuff`, `removeBuff`, `removeDebuff`, `addStack`, `removeStack`, `setCooldown`, `reduceCooldown`, `summonTotem`,
-- `summonPet`, `dismissPet`, `openWindow`, `closeWindow`) and reads (`talent`, `buff`, `debuff`, the resources by key,
-- `knownRank`, `stat`, `swingBase`, `mainhand_speed`, `offhand_speed`, `weapon`, `equipped`, `set_bonus`, `healthMax`,
-- `now`, `combat`, `level`, `lastSwing`, `nextSwing`, `usable`, `window`, and the `now`-only `instant`, `cast_start`,
-- `target.health`: aura audit C8) with belief meanings. A window's evaluator
-- (Families/Windows.lua) runs in the same context, reads only. Every write is a `modelled` sample at the cast's time, so any later observation overrides it (I.Basis). Hekili's sim `handler` is never read for truth.
-- An `applyBuff`/`applyDebuff` with no duration writes the aura's registered one: its number, or its function evaluated
-- in this context (gear-aware spec §5), so a pack writes a duration once.
-- An avoid of the latest cast (Obs.Avoided) undoes its target debuffs and refunds the ability's `refundOnAvoid` share.
-- A channel that ran to its believed end runs the ability's `now_finish` (the sim's `finish`'s twin; aura audit C11).
-- A reaction (RegisterReaction) runs in the same context at a settled outcome's row time, never through the cast fold.
-- Allocates nothing per cast: the context, its proxies and every per-ability array are built at SpecChanged.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs = VS.Obs
local CAST = Obs.CastSuccess

local A = I.ab
A.now = {} -- by ability index: the `now` function, bound to the context, or false
A.onCrit = {} -- by ability index: the `onCrit` function (run at the cast's own crit, Obs.Crit), bound, or false
A.onLand = {} -- by ability index: the `onLand` function (run once its cast landed, Obs.Landed), bound, or false
A.finish = {} -- by ability index: the `now_finish` function (run at a channel's stop at its end), bound, or false
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
    level = 0, -- the player's (Sources/Player.lua; 0 before the first read), set with `now`
    haste = 1, -- the sim's spell-haste multiplier (I.Haste), set with `now`
    mainhand_speed = 0, -- the believed swing speeds (VS.SwingSpeed), set with `now`
    offhand_speed = 0,
    weapon = { size = 0 }, -- the gear (Sources/Player.lua): the main hand's size, 2 a two-hander, as the sim's `weapon`
    equipped = { shield = false }, -- and its `equipped.shield`
    set_bonus = I.setBonus, -- the declared gear's values (Families/Gear.lua), the core's state.set_bonus semantics
    -- the cast's start (aura audit C8; `now`-only names, the sim's `state` has neither): `cast_start` its start time, 0
    -- for an instant (no start seen), and `instant`, true only inside an instant cast's `now` (false elsewhere)
    -- shortcut: a hard cast whose UnitCastingInfo times were secret stages no start, so it reads instant; upgrade with
    -- a start flag staged at UNIT_SPELLCAST_START itself if a pack's instant-only spend shows it live
    cast_start = 0,
    instant = false,
}
I.weapon, I.equipped = NAMES.weapon, NAMES.equipped
-- equipped.<key>: the core's mt_equipped (Engine/Sim/State.lua:4848), set_bonus.<key> > 0; the raw `shield` stays
-- Sources/Player.lua's
setmetatable(NAMES.equipped, {
    __index = function(_, k)
        return I.setBonus[k] > 0
    end,
})
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
-- True while a reaction runs: it is folded after its outcome's time T (a swing's row comes ~0.47 s after the swing, an
-- avoid at its window's close), so its aura reads answer as of T (I.AuraAsOf), not the belief's latest.
local asOf = false

-- The latest cast's undo (Obs.Avoided): its ability, time and target (the swap serial), the cost it paid, and the target
-- auras its `now` wrote, each as it was before (expiry 0: down), at most UNDO of them. Preallocated.
local UNDO = 4
local undoA, undoT, undoSwap, paid, undoN = 0, -1, 0, 0, 0
local journal = true -- false while an `onCrit` runs: a landed crit's writes are no avoid's to undo
local undoJ, undoE, undoAp, undoSt = {}, {}, {}, {}
for k = 1, UNDO do
    undoJ[k], undoE[k], undoAp[k], undoSt[k] = 0, 0, 0, 0
end
local refund = {} -- by resource slot: the class's default share (the resource meta's `refundOnAvoid`), 0 none
A.refund = {} -- by ability index: the share of its cost an avoid gives back (the ability's `refundOnAvoid`), 0 none
I.avoidsRun = 0

--- The context's reads answer at `t` from now on (a resource's `taken`, run at a hit: Families/Resources.lua); its
--- verbs stay inert outside a cast. Allocates nothing.
function I.NowAt(t)
    T = t
    rawset(NAMES, "now", t)
    rawset(NAMES, "combat", I.combatT) -- as `run` does
    rawset(NAMES, "level", I.level or 0)
    rawset(NAMES, "haste", I.Haste(t))
    rawset(NAMES, "mainhand_speed", VS.SwingSpeed(1, t).est)
    rawset(NAMES, "offhand_speed", VS.SwingSpeed(2, t).est)
end

--- The sim's `haste` (State.lua: 1 / (1 + spell haste), a slow above 1, unclamped as there) from the belief's spell
--- haste (Families/Player.lua, a percent).
function I.Haste(t)
    local h = VS.SpellHaste and VS.SpellHaste(t).est or 0
    return 1 / (1 + h / 100)
end
local abByKey, auraByKey, auraSpell, auraDur, auraFn, auraMax, resByKey = {}, {}, {}, {}, {}, {}, {}

----------------------------------------------------------------------------------------------------------------------
-- Reads: proxies built at SpecChanged, answered from the belief at the cast's time.

-- An aura at T: its expiry (nil: down), stacks and applied time.
local function readAura(unit, spell)
    if asOf then
        return I.AuraAsOf(unit, spell, T)
    end
    local rec, stacks, applied = I.CastAura(unit, spell, T)
    return rec and rec.est, stacks, applied
end

local function auraField(r, f)
    local e, stacks, applied = readAura(rawget(r, "unit"), rawget(r, "spell"))
    if f == "up" then
        return e ~= nil
    elseif f == "down" then
        return e == nil
    elseif f == "remains" then
        return e and e - T or 0
    elseif f == "stack" or f == "count" then
        return e and stacks or 0
    elseif f == "expires" then
        return e or 0
    elseif f == "applied" then
        return e and applied or 0
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

-- totem.<element>: the belief's totem slot (Families/Totems.lua; the sim's state.totem shape, State.lua).
local TOTEM_SLOT = { fire = 1, earth = 2, water = 3, air = 4 }
local totemMeta = {
    __index = function(r, f)
        local rec = VS.Totem(rawget(r, "slot"), T)
        if f == "up" or f == "active" then
            return rec ~= nil
        elseif f == "down" then
            return rec == nil
        elseif f == "remains" then
            return rec and rec.est - T or 0
        elseif f == "expires" then
            return rec and rec.est or 0
        end
        return nil
    end,
}
local NO_TOTEM = setmetatable({ slot = 0 }, totemMeta)
NAMES.totem = setmetatable({}, {
    __index = function()
        return NO_TOTEM
    end,
})
for elem, slot in pairs(TOTEM_SLOT) do
    rawset(NAMES.totem, elem, setmetatable({ slot = slot }, totemMeta))
end

-- action.<key>.in_range: the range poll's last plain answer for the ability (Sources/Target.lua; the sim's
-- state.action.x.in_range is the client's IsSpellInRange): true unless the client answered false. Entries per tracked
-- ability at the build; an untracked key answers an empty record.
local actionMeta = {
    __index = function(r, f)
        if f == "in_range" then
            local ans = I.rangeAnswer
            return not (ans and ans[rawget(r, "a")] == false)
        end
        return nil
    end,
}
local NO_ACTION = setmetatable({ a = 0 }, actionMeta)
NAMES.action = setmetatable({}, {
    __index = function()
        return NO_ACTION
    end,
})
local NO_SETTINGS = {}

-- target.health (aura audit C8; `now`-only): the belief's target health interval (Families/TargetHealth.lua) as
-- percent bounds `lo` and `hi` (0 and 100 while unknown), and `known`, true once something bounded it (a gate's
-- answer, a pin, learned damage, a death). No `pct`: secret health is unknown, never read as 100 or 0, so a `now`
-- tests a bound (`target.health.hi < 35`: proven below 35%) and a bare `pct` read raises (a counted error).
NAMES.target = {
    health = setmetatable({}, {
        __index = function(_, f)
            local h = VS.Health("target", T)
            if f == "known" then
                return h.lo > 0 or h.hi < 1
            elseif f == "lo" then
                return h.lo * 100
            elseif f == "hi" then
                return h.hi * 100
            end
            return nil
        end,
    }),
}

local resourceMeta = {
    __index = function(r, f)
        local pt = rawget(r, "type")
        if f == "current" then
            return VS.Power(pt, T).est
        elseif f == "lo" then
            return VS.Power(pt, T).lo
        elseif f == "hi" then
            return VS.Power(pt, T).hi
        elseif f == "max" then
            return I.res.max[I.res.slotOf[pt]] or 0
        end
        return nil
    end,
}

--- The highest known rank of a tracked ability's rank list (1-based), 0 when none is known or the list is untracked.
--- Reads the belief's spellbook, never the game: a pack function's bare `knownRank` here. Allocates nothing.
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

-- The swing reads a window's evaluator needs (re-pin design §3a): lastSwing(hand), the time of the last observed swing
-- (0 none); nextSwing(hand), the next projected one at the context's time (0 unknown). Hands 1 main, 2 off, 3 ranged.
NAMES.lastSwing = VS.LastSwing
function NAMES.nextSwing(hand)
    return VS.Swing(hand, T).est
end

-- usable.<key>: the last plain IsSpellUsable answer for a tracked ability (Sources/Power.lua's poll: spenders only; a
-- secret answer is no observation there, so the last plain one stays); false before one and for an untracked key.
local usableAns = {} -- by ability index
NAMES.usable = setmetatable({}, {
    __index = function(_, key)
        local a = abByKey[key]
        return a ~= nil and usableAns[a] == true
    end,
})
I.On(Obs.Usable, function(o)
    usableAns[o.a] = o.b == 1
end)

--- The known rank's spell ID for any rank ID of a tracked ability with a known rank, else `spellID` unchanged (nil,
--- untracked or unknown). The client answers range only for a known rank: the facade's C_Spell.IsSpellInRange asks
--- by it (Game/API/Facade.lua). Allocates nothing.
function VS.KnownID(spellID)
    local a = spellID and A.bySpell[spellID]
    if a and A.known[a] then
        return A.qid[a]
    end
    return spellID
end

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
        I.Log.Energize(A.qid[curA] or 0, n, I.res.type[r], I.res.max[r], T) -- a reaction's: no ability (curA 0)
    end
end
function NAMES.gain(amount, resource)
    shift(amount, resource)
end
function NAMES.spend(amount, resource)
    shift(type(amount) == "number" and -amount or amount, resource)
end
-- The belief's own verb (Hekili's handlers spend and gain): the cast set `resource` to `amount`, or up to `upto` more by
-- a roll the belief does not see (the estimate at the floor, the top `upto` above it).
function NAMES.resetResource(resource, amount, upto)
    if not live then
        return
    end
    local r = resByKey[resource]
    if not r then
        error("now: no tracked resource " .. tostring(resource), 2) -- counted as the `now`'s error; no write
    end
    if type(amount) ~= "number" then
        return
    end
    I.ResourceSet(r, amount, type(upto) == "number" and upto > 0 and upto or 0, T, CAST)
end

local function aura(u, key, duration, stacks)
    local j = auraByKey[key]
    if not live or not j or (u == 2 and I.auras.n < 2) then
        return
    end
    local rec, have, applied = VS.Aura(u == 1 and "player" or "target", auraSpell[j], T)
    local before = rec and rec.est or 0
    local after = 0
    if duration ~= 0 then
        local d = duration
        if d == nil then
            d = auraDur[j]
            if not d and auraFn[j] then
                d = I.Eval(auraFn[j], T) -- the aura's registered duration in this context (gear-aware spec §5)
            end
        end
        if type(d) ~= "number" then
            return -- no number: a raising duration (counted by I.Eval) writes nothing
        end
        after = T + d
    end
    if u == 2 and journal and undoN < UNDO then
        local first = true
        for k = 1, undoN do
            first = first and undoJ[k] ~= j
        end
        if first then -- as it was before the cast: a second write of the same aura keeps the first's
            undoN = undoN + 1
            undoJ[undoN], undoE[undoN], undoAp[undoN], undoSt[undoN] = j, before, applied or 0, have or 0
        end
    end
    I.AuraModel(u, j, T, after, stacks or 1, T, CAST, u == 2)
    -- cdm-default rule 2.5.1: this application is ours (Sources/Auras.lua); a projectile's travel widens the
    -- verdict's window (cdm-verdict §2.3; velocity > 0 only: the client raises on x/0)
    local v = A.velocity[curA] or 0
    I.AuraOurs(u, j, v > 0 and (A.rMax[curA] or 0) / v or 0)
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
    local e, have = readAura("player", auraSpell[j])
    local n = (e and have or 0) + (stacks or 1)
    aura(1, aura_, duration, n < auraMax[j] and n or auraMax[j]) -- Hekili's max_stack clamp (State.lua:837-852)
end
--- removeStack(aura, stacks): Hekili's verb (State.lua): `stacks` (1) fewer of our aura, its expiry and applied time
--- kept; down when none is left. A down aura is left down (aura audit C4).
function NAMES.removeStack(aura_, stacks)
    local j = auraByKey[aura_]
    if not live or not j then
        return
    end
    local rec, have, applied = VS.Aura("player", auraSpell[j], T)
    if not rec then
        return
    end
    local n = (have or 1) - (stacks or 1)
    if n <= 0 then
        aura(1, aura_, 0)
        return
    end
    I.AuraModel(1, j, applied, rec.est, n, T, CAST, false) -- no log row: the expiry stands (a dose, not a refresh)
end
function NAMES.setCooldown(action, duration)
    local a = abByKey[action]
    if live and a and type(duration) == "number" then
        I.CooldownModel(a, T + duration, duration, T, CAST)
    end
end
--- reduceCooldown(action, time): Hekili's verb (State.lua): a running cooldown `time` s shorter (ready at the cast at
--- the earliest); a charged ability's next charge `time` s sooner (VS.Charges counts the recharges it then passes).
function NAMES.reduceCooldown(action, time)
    local a = abByKey[action]
    if not live or not a or type(time) ~= "number" then
        return
    end
    if A.ch[a] then
        if A.next0[a] > 0 then
            A.next0[a] = A.next0[a] - time
            I.Sample(A.chNext[a], "modelled", A.next0[a], T, CAST)
        end
    elseif A.ready0[a] > T then
        local e = A.ready0[a] - time
        A.ready0[a] = e > T and e or T
        I.Sample(A.cd[a], "modelled", A.ready0[a], T, CAST)
    end
end

--- summonTotem(name, element, duration): Hekili's signature (State.lua); the element's slot expires `duration` s after
--- the cast (an unknown element or a non-number duration writes nothing).
function NAMES.summonTotem(name, elem, duration)
    local slot = TOTEM_SLOT[elem]
    if live and slot and type(duration) == "number" then
        I.TotemModel(slot, T + duration, A.qid[curA] or 0, type(name) == "string" and name or "", T, CAST)
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

--- dismissPet(key): Hekili's name. A guardian's summons end; any other key models the pet unit down until the first
--- observation (Families/Pets.lua).
function NAMES.dismissPet(key)
    if live and type(key) == "string" then
        I.PetDismiss(key, T, CAST)
    end
end

--- openWindow(name) / closeWindow(name): a rotation window's verbs (Families/Windows.lua), at the cast's time; the
--- evaluator's edge rules (a close acts only on an open window). An unregistered name writes nothing.
function NAMES.openWindow(name)
    if live then
        I.WindowOpen(name, T)
    end
end
function NAMES.closeWindow(name)
    if live then
        I.WindowClose(name)
    end
end

-- window.<name>: the window's state (Families/Windows.lua) at the context's time, the sim's state.window answers
-- (Engine/Sim/State.lua mtWindow): up, down, remains, elapsed, step, next.<ability key> (the due step; casts already
-- folded). Read-only (the verbs above are the writers); an unregistered name reads down (the sim's would raise). One
-- reader per registered window, built at the build; the index is resolved per read (Windows.lua builds after this file).
local function readOnly()
    error("now: window readers are read-only", 2)
end
local function upAt(r) -- the window's index when up at T, else nil (expired but not yet closed reads down)
    local W = I.win
    local w = W.byKey[rawget(r, "key")]
    if w and W.up[w] and W.openedAt[w] <= T and T < W.expiresAt[w] then
        return w
    end
    return nil
end
local windowMeta = {
    __index = function(r, f)
        local w = upAt(r)
        if f == "up" then
            return w ~= nil
        elseif f == "down" then
            return w == nil
        elseif f == "remains" then
            return w and I.win.expiresAt[w] - T or 0
        elseif f == "elapsed" then
            return w and T - I.win.openedAt[w] or 0
        elseif f == "step" then
            return w and I.win.step[w] or 0
        end
        return nil
    end,
    __newindex = readOnly,
}
local nextMeta = {
    __index = function(r, key)
        local w = upAt(r)
        local steps = w and I.win.steps[w]
        local a = abByKey[key]
        return steps and a ~= nil and steps[I.win.step[w]] == a or false
    end,
    __newindex = readOnly,
}
local function reader(key)
    return setmetatable({ key = key, next = setmetatable({ key = key }, nextMeta) }, windowMeta)
end
local NO_WINDOW = reader(false)
NAMES.window = setmetatable({}, {
    __index = function()
        return NO_WINDOW
    end,
    __newindex = readOnly,
})

----------------------------------------------------------------------------------------------------------------------
-- Reactions (RegisterReaction, re-pin design §3a): `now` functions run by a settled outcome, never by a cast. By `who`
-- (1 player, 2 target) x outcome (OUTCOME): the bound functions, a list each, and each one's hand (0 any, 1 main,
-- 2 off: a "swing" reaction's filter), preallocated at load, refilled at the build.

local WHO, HAND = { player = 1, target = 2 }, { main = 1, off = 2 }
local OUTCOME = { dodge = 1, parry = 2, block = 3, miss = 4, deflect = 5, evade = 6, crit = 7, swing = 8, land = 9 }
local CRIT, SWING, LAND = OUTCOME.crit, OUTCOME.swing, OUTCOME.land
local OUTCOME_OF = {} -- by I.HitKind: the outcome slot (0: no reaction outcome)
for name, kind in pairs(I.HitKind) do
    local o = OUTCOME[name:lower()]
    OUTCOME_OF[kind] = o or 0
end
OUTCOME_OF[I.HitKind.BLOCKED] = OUTCOME.block -- `block` covers BLOCK and BLOCKED
local NO_REACTIONS = {}
local react = { {}, {} } -- react[who][outcome] = { n = count, bound functions... }
for w = 1, 2 do
    for o = 1, LAND do
        react[w][o] = { n = 0, hand = {} }
    end
end
I.reactionsRun = 0

local function bindReactions(list)
    for w = 1, 2 do
        for o = 1, LAND do
            local l = react[w][o]
            for k = 1, l.n do
                l[k], l.hand[k] = nil, nil
            end
            l.n = 0
        end
    end
    for k = 1, #list do
        local d = list[k]
        local w, o, f = WHO[d.who], OUTCOME[d.outcome], d.now
        if w and o and type(f) == "function" then
            local l = react[w][o]
            l.n = l.n + 1
            l[l.n], l.hand[l.n] = setfenv(f, ctx), HAND[d.hand] or 0
        end
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
    for k in pairs(NAMES.action) do
        NAMES.action[k] = nil
    end
    for k in pairs(NAMES.window) do
        rawset(NAMES.window, k, nil)
    end
    local wins = def.windows or NO_SETTINGS -- a hand-built def may carry no `windows`
    for k = 1, #wins do
        rawset(NAMES.window, wins[k].key, reader(wins[k].key))
    end
    for a = 1, A.n do
        abByKey[A.key[a]] = a
        usableAns[a] = false
        A.known[a] = A.known[a] or false
        A.extra[a] = type(A.key[a]) == "string" and A.key[a]:sub(1, 6) == "track_"
        local obj = def.abilities[a]
        local f = obj.now -- the plain record's field (Engine/Schema/Tracked.lua)
        if type(f) == "function" and f == obj.handler then
            -- rebinding it would move the sim handler into the `now` context
            I.nowErrors, I.nowError = I.nowErrors + 1, "now: " .. tostring(A.key[a]) .. "'s now is its handler"
            f = false
        end
        A.now[a] = type(f) == "function" and setfenv(f, ctx) or false
        local c = obj.onCrit
        A.onCrit[a] = type(c) == "function" and setfenv(c, ctx) or false
        local l = obj.onLand
        A.onLand[a] = type(l) == "function" and setfenv(l, ctx) or false
        local fin = obj.now_finish
        if type(fin) == "function" and fin == obj.finish then -- as `now` and `handler`: one function, one environment
            I.nowErrors, I.nowError = I.nowErrors + 1, "now: " .. tostring(A.key[a]) .. "'s now_finish is its finish"
            fin = false
        end
        A.finish[a] = type(fin) == "function" and setfenv(fin, ctx) or false
        rawset(NAMES.action, A.key[a], setmetatable({ a = a }, actionMeta))
    end
    rawset(NAMES, "settings", def.settings or NO_SETTINGS) -- the spec's settings as plain values, the core's copy
    bindReactions(def.reactions or NO_REACTIONS)
    for r = 1, #def.resources do
        local f = def.resources[r].refundOnAvoid
        refund[r] = type(f) == "number" and f > 0 and f <= 1 and f or 0
    end
    for a = 1, A.n do -- true: the resource's default share; a number: its own
        local obj = def.abilities[a]
        local f = obj.refundOnAvoid
        local r = def.abilitySlot[a] or 0
        if f == true then
            f = r > 0 and refund[r] or 0
        end
        A.refund[a] = type(f) == "number" and f > 0 and f <= 1 and f or 0
    end
    for j = 1, #def.auras do
        local key = def.auras[j].key
        auraSpell[j] = def.auraIds[j][1]
        local d = rawget(def.auras[j], "duration")
        auraDur[j] = type(d) == "number" and d or false
        auraFn[j] = type(d) == "function" and d or false
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
            -- at the cast's own time when its success folds late (staged, after a later direct observation): the
            -- spend's five-second window opens at the cast, not at the fold (GAP W)
            I.ResourceShift(r, -c, o.t < t and o.t or t, kind)
        end
        -- a charged cost modifier in scope loses a stack, even when its discount made the cast free (Modifiers.lua)
        if I.BaseCostOf(a) > 0 then
            I.SpendCostCharges(a, r, o.t < t and o.t or t, kind)
        end
    end
    -- from the cast's own time, as its spend: a success folded late starts its cooldown or recharge no later (GAP W);
    -- the GCD below stays at the fold's time (the safe side: never believed ready early)
    local at = o.t < t and o.t or t
    if A.ch[a] then
        local recharge = type(obj.recharge) == "number" and obj.recharge or 0
        local ch, nx = VS.Charges(A.id[a], at) -- the recharges finished since the last sample, caught up to the cast
        local charges, nextAt = ch.est - 1, nx.est
        if nextAt <= at then
            nextAt = at + recharge -- it was at max: the recharge starts at the cast
        end
        I.ChargesModel(a, charges > 0 and charges or 0, nextAt, t, kind)
    else
        local cd = I.CooldownOf(a, at) -- a function cooldown in the belief's context (Families/Casts.lua)
        if cd > 0 then
            I.CooldownModel(a, at + cd, cd, at, kind)
        end
    end
    if A.gcdKind[a] > 0 then
        local start = t
        if kind == CAST and A.castStartT[a] > 0 and A.castStartT[a] < t then
            start = A.castStartT[a] -- a hard cast's GCD began at its start
        end
        local len = I.GcdLen(a, t, start < t and start or at) -- its kind's, modifiers judged at its opening (Casts.lua)
        if start + len > t then
            I.GcdModel(start + len, t, kind)
        end
    end
end

--- Runs a window's bound evaluator f in the shared context at belief time t, reads only (the verbs stay inert): true
--- only for a plain `true` answer, and whether it ran clean. A raise is counted and reads false; `raised` (it raised
--- before) skips the call. Allocates nothing.
function I.NowEval(f, t, raised)
    if raised then
        return false, false
    end
    I.NowAt(t)
    local ok, v = pcall(f)
    if not ok then
        I.nowErrors, I.nowError = I.nowErrors + 1, v
        return false, false
    end
    local api = I.api
    return not (api and api.issecretvalue(v)) and v == true, true
end

-- Runs ability a's bound function f in the shared context at belief time t; an error is counted, never raised.
local function call(f, a, t)
    curA = a
    I.NowAt(t)
    live = true
    local ok, err = pcall(f)
    live = false
    I.nowRuns = I.nowRuns + 1
    if not ok then
        I.nowErrors, I.nowError = I.nowErrors + 1, err
    end
end

-- Runs who's reactions to outcome slot o at the outcome's time t: no ability (curA 0), its writes no avoid's to undo
-- (journal off, as an `onCrit`). Never through `run`: no cast, step, strict end, cooldown or GCD. `hand` (a swing's,
-- 1 or 2; nil elsewhere) passes a reaction whose hand is 0 or equal. Allocates nothing.
local function fire(w, o, t, hand)
    local l = o > 0 and react[w][o]
    if not l or l.n == 0 then
        return
    end
    journal, asOf = false, true
    for k = 1, l.n do
        local hk = l.hand[k]
        if hk == 0 or hk == hand then
            call(l[k], 0, t)
            I.reactionsRun = I.reactionsRun + 1
        end
    end
    journal, asOf = true, false
end

local function run(o, t)
    local a = o.a
    if not A.obj[a] or not A.key[a] or A.extra[a] then
        return
    end

    undoA, undoT, undoSwap, paid, undoN = a, o.t, I.curSwapN, 0, 0
    local started = o.kind == CAST and A.castStartT[a] or 0 -- read before `automatic` and the line after clear it
    automatic(a, t, o.kind, o)
    A.castStartT[a] = 0 -- consumed: a later instant cast of the same ability starts its own GCD
    I.castsRun = I.castsRun + 1
    I.WindowCast(a, t) -- the stepped and strict windows' one per-cast hook (Families/Windows.lua), before the `now`
    if A.now[a] then
        rawset(NAMES, "cast_start", started)
        rawset(NAMES, "instant", started == 0)
        call(A.now[a], a, t)
        rawset(NAMES, "cast_start", 0)
        rawset(NAMES, "instant", false)
    end
end
-- CastSuccess only: a channel stages ChannelStart and CastSuccess both (Sources/Casts.lua), and must run once.
I.On(Obs.CastSuccess, run)

-- Our cast's own crit (Events/Rows.lua, GAP T): the ability's `onCrit` runs in the same context, its writes `modelled` at
-- the crit's row (what a crit gives, as Primal Fury's rage, is the class file's to declare). Allocates nothing.
I.On(Obs.Crit, function(o)
    fire(2, CRIT, o.t) -- first: the target's crit reactions (a 0: our white swing's, Rows stages it once final)
    local a = o.a
    if A.onCrit[a] and A.key[a] and not A.extra[a] then
        journal = false
        call(A.onCrit[a], a, o.t)
        journal = true
    end
end)

-- A channel's `now_finish` (aura audit C11): the channel in progress (ability index, 0 none) and its believed end, from
-- its start (Sources/Casts.lua stages it only with plain times) and pushbacks; a stop within FINISH_TOL of that end
-- ran it full (wowsims: the last tick lands at the end), so its `now_finish` runs at the stop, its writes no avoid's
-- to undo. A stop earlier (a break, a clip), later than FINISH_LATE past the end, or a channel with no plain start runs
-- nothing (dim: never a full channel assumed). Allocates nothing.
local FINISH_TOL = 0.05 -- UNMEASURED: CHANNEL_STOP at a full channel's end is read at or just after it
local FINISH_LATE = 0.5 -- a stop later than this past the end is another channel's (one whose start was secret)
local chanA, chanEnd = 0, 0
I.On(Obs.ChannelStart, function(o)
    chanA, chanEnd = o.a, o.b
end)
I.On(Obs.ChannelUpdate, function(o)
    if o.a == chanA then
        chanEnd = o.b
    end
end)
I.On(Obs.ChannelStop, function(o)
    local a = chanA
    if o.a ~= a then
        return
    end
    chanA = 0
    if A.finish[a] and A.key[a] and not A.extra[a] and o.t >= chanEnd - FINISH_TOL and o.t <= chanEnd + FINISH_LATE then
        journal = false
        call(A.finish[a], a, o.t)
        journal = true
    end
end)

-- Our cast's own landed hit (Events/Rows.lua, aura audit C10): the ability's `onLand` runs at it, its writes `modelled`
-- there and no avoid's to undo (a gain only a landed hit gives, as a mana return). Allocates nothing.
I.On(Obs.Landed, function(o)
    local a = o.a
    if A.onLand[a] and A.key[a] and not A.extra[a] then
        journal = false
        call(A.onLand[a], a, o.t)
        journal = true
    end
end)

-- Our cast's own avoid (Events/Rows.lua): the latest cast, when it is the one avoided, loses the target auras its `now`
-- wrote (each back as it was, when the target is still the cast's) and gets back the ability's `refundOnAvoid` share of
-- the cost it paid; both `modelled` at the outcome. Any other cast's avoid changes nothing (its effects are no longer
-- the latest's to undo). The cooldown,
-- the GCD and the player auras stay (an avoided ability still triggers them). Allocates nothing.
local DEFLECT, EVADE = I.HitKind.DEFLECT, I.HitKind.EVADE
I.On(Obs.Avoided, function(o, t)
    fire(2, OUTCOME_OF[o.c] or 0, o.t) -- first: the target's reactions, at the outcome's row
    if o.c == DEFLECT or o.c == EVADE then -- staged for reactions only (Events/Rows.lua REACTED): no undo, no refund
        return
    elseif o.a ~= undoA or o.b ~= undoT then
        return
    end
    undoA = 0
    for k = 1, I.curSwapN == undoSwap and undoN or 0 do -- another target since the cast: its auras are not these
        local j = undoJ[k]
        local rec = VS.Aura("target", auraSpell[j], t)
        local was, back = rec and rec.est or 0, undoE[k] > t and undoE[k] or 0
        I.AuraModel(2, j, undoAp[k], back, back > 0 and undoSt[k] or 0, t, Obs.Avoided, true)
        I.Log.Aura(2, j, auraSpell[j], was, back, t)
    end
    local r = A.slot[o.a]
    if r > 0 and paid > 0 and A.refund[o.a] > 0 then
        I.Refund(r, paid * A.refund[o.a], t) -- at the fold; the answers since the cast's spend already saw it
    end
    I.avoidsRun = I.avoidsRun + 1
end)

-- The other settled outcomes reactions run on (re-pin design §3a): our white swing's (Obs.SwingSettled, Events/Rows.lua:
-- its avoid's own outcome, then every "swing" reaction of its hand), a hit on us (Obs.PlayerHit, Obs.PlayerCrit:
-- victim-side UNIT_COMBAT, Sources/Player.lua), each at its row's time. Allocates nothing.
-- "land" (aura audit C3): a settled wound, or a swing that closed with no row (c = -1: live, a non-crit hit's row is
-- secret and only avoids are plain), which runs nothing else, at the swing's own time (o.b): what a landed hit does
-- follows the auras up when it swung, not at its row ~0.47 s later (an aura may change in between).
local WOUND = I.HitKind.WOUND
I.On(Obs.SwingSettled, function(o)
    fire(2, OUTCOME_OF[o.c] or 0, o.t)
    if o.c ~= -1 then
        fire(2, SWING, o.t, o.a)
    end
    if o.c == WOUND or o.c == -1 then
        fire(2, LAND, o.b, o.a)
    end
end)
I.On(Obs.PlayerHit, function(o)
    fire(1, OUTCOME_OF[o.a] or 0, o.t)
end)
I.On(Obs.PlayerCrit, function(o)
    fire(1, CRIT, o.t)
end)
