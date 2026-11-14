-- Game/State/Families/Player.lua
-- The player family (spec §6.5): combat and movement facts, health, spell haste, the out-of-combat stat cache and the
-- default time to die. Melee haste lives with the swing family (Families/Swing.lua), which measures it.
-- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Player.lua (Applier Haste :130, Moving :194).

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local Obs, ReadOf = VS.Obs, I.ReadOf

I.inCombat, I.moving = false, false
I.combatT = 0

--- (spec §3.1) In combat, from PLAYER_REGEN_DISABLED/ENABLED (not InCombatLockdown, which lags).
function VS.InCombat()
    return I.inCombat
end

--- (spec §3.1) Moving, from PLAYER_STARTED_MOVING/PLAYER_STOPPED_MOVING.
function VS.Moving()
    return I.moving
end

I.On(Obs.Moving, function(o)
    I.moving = o.b == 1
end)

-- Health (player: plain reads; target: Families/TargetHealth.lua; others: the default 1.0), spell haste, time to die.
local health, otherHealth, spellHaste, ttd
I.healthMax = 0

-- The player's health unknown from t: full (a defensive "health.pct<50" never fires, a "health.pct>50" gate always
-- passes), the last plain read forgotten so the basis is "default" and the confidence 0. A secret read and the pull
-- (a read from before it may be stale until the next poll) both make it unknown.
local function healthUnknown(t, event)
    health.est, health.lo, health.hi = 1, 0, 1
    health.last.observed.t = 0
    I.Sample(health, "default", 1, t, event)
end

-- The stat split (owner rule L971; accuracy-085 item 4): a pack's player aura declares what it does to the spell haste
-- (`spellHaste`, a multiplier) or to UnitStat (`stats`, flat points by index: a number or a function of the talent ranks,
-- run in the `now` context at the pull; `statsPct`, a multiplier by index, after the flat parts as the client applies
-- them). At the pull the belief splits each out-of-combat read into a base and the parts of the declared auras up at
-- the READ's time (stat reads land directly, aura reads fold later: judging at the read's time neither divides out a
-- buff the read never held nor misses one it did); in the fight the value is composed from its own aura records, so a
-- fall removes exactly its part and a gain adds it. Out of combat, and after any newer plain read, the read stands.
-- Quantity 0 is the spell haste (a multiplier, 1 + percent / 100), 1-5 UnitStat's indices (I.STATS slots 1-5).
local P = { n = 0, j = {}, q = {}, def = {}, add = {}, mul = {} }
local split = {} -- [q] = a part is declared for it
local base, baseAt = {}, {} -- [q] = the fight's base, and when it was derived (0: none)
local hasteRead, hasteReadT = 0, 0 -- the last plain spell haste read (percent) and its time
for q = 0, 5 do
    split[q], base[q], baseAt[q] = false, 0, 0
end

local function part(j, q, def, mul)
    local k = P.n + 1
    P.n, P.j[k], P.q[k], P.def[k], P.mul[k] = k, j, q, def, mul
    P.add[k] = type(def) == "number" and def or 0
    split[q] = true
end

-- Player aura j up at t by its current record, or (`asOfRead`) by its last fall too: one fall deep (I.AuraAsOf's rule);
-- an aura first seen in the first clean walk (a login) counts as up since before it. Allocates nothing.
local function upAt(j, t, asOfRead)
    local A = I.auras
    local ap = A.applied[1][j] -- unit 1 is always "player"
    if A.exp0[1][j] > t and (ap <= t or asOfRead and ap <= A.firstWalk[1]) then
        return true
    end
    return asOfRead and A.fellFrom[1][j] <= t and A.fellAt[1][j] > t or false
end

-- Quantity q's flat sum and multiplier of the parts up at t. Allocates nothing.
local function parts(q, t, asOfRead)
    local add, mul = 0, 1
    for k = 1, P.n do
        if P.q[k] == q and upAt(P.j[k], t, asOfRead) then
            add, mul = add + P.add[k], mul * P.mul[k]
        end
    end
    return add, mul
end

local function derive(q, read, readT, t)
    local add, mul = parts(q, readT, true)
    base[q], baseAt[q] = read / mul - add, t -- nonzero: every declared multiplier is > 0
end

local function splitAtPull(t)
    for k = 1, P.n do
        local d = P.def[k]
        if type(d) == "function" then
            local v, ok = I.Eval(d, t, true)
            P.add[k] = ok and type(v) == "number" and v == v and v or 0 -- v == v: not NaN
        end
    end
    if split[0] then
        derive(0, 1 + hasteRead / 100, hasteReadT, t)
    end
    for q = 1, 5 do
        if split[q] and I.statT[q] > 0 then
            derive(q, I.statVal[q][2], I.statT[q], t)
        end
    end
end

I.On(Obs.CombatStart, function(o, t)
    I.combatT = t
    healthUnknown(t, Obs.CombatStart)
    splitAtPull(t)
end)

local function decay(rec, now)
    local age = now - rec.last.observed.t
    if age < 0 then
        age = 0
    end
    rec.conf = rec.last.observed.t > 0 and 1 / (1 + age / I.AURA_HALF_LIFE) or 0 -- nonzero: 1 + age >= 1
end

I.OnBuild(function(def, now)
    health = I.NewBelief("health player")
    health.est, health.lo, health.hi = 1, 0, 1
    I.Sample(health, "default", 1, now, 0)
    otherHealth = I.NewBelief("health other")
    otherHealth.est, otherHealth.lo, otherHealth.hi = 1, 0, 1
    I.Sample(otherHealth, "default", 1, now, 0)
    spellHaste = I.NewBelief("spell haste")
    P.n = 0
    for q = 0, 5 do
        split[q], baseAt[q] = false, 0
    end
    local auras = def.auras or {}
    for j = 1, #auras do
        local f, st, pct = rawget(auras[j], "spellHaste"), rawget(auras[j], "stats"), rawget(auras[j], "statsPct")
        if type(f) == "number" and f > 0 then
            part(j, 0, 0, f)
        end
        for q = 1, 5 do
            local v = type(st) == "table" and st[q]
            if type(v) == "number" or type(v) == "function" then
                part(j, q, v, 1)
            end
            local m = type(pct) == "table" and pct[q]
            if type(m) == "number" and m > 0 then
                part(j, q, 0, m)
            end
        end
    end
    I.Sample(spellHaste, "default", 0, now, 0)
    ttd = I.NewBelief("ttd")
    ttd.est, ttd.lo, ttd.hi = 30, 0, 3600
    I.Sample(ttd, "default", 30, now, 0)
end)

I.On(Obs.Read, function(o, t)
    if o.c == ReadOf.Health and o.b < 0 then
        healthUnknown(t, Obs.Read)
    elseif o.c == ReadOf.Health then
        health.est, health.lo, health.hi = o.b, o.b, o.b
        I.Sample(health, "observed", o.b, t, Obs.Read)
    end
end)

I.On(Obs.Haste, function(o, t)
    if o.c == 2 then
        spellHaste.est, spellHaste.lo, spellHaste.hi = o.b, o.b, o.b
        I.Sample(spellHaste, "observed", o.b, t, Obs.Haste)
        hasteRead, hasteReadT = o.b, t
        if I.inCombat and baseAt[0] > 0 and split[0] then -- a plain read in a fight: the base follows it
            derive(0, 1 + o.b / 100, t, t)
        end
    end
end)

--- (spec §3.2) Health fraction 0..1: the player's last plain read (conf decaying as an aura), 1 (full) before one and
--- after a secret read; the target's belief
--- (Families/TargetHealth.lua); every other unit the default 1.0.
function VS.Health(unit, now)
    if unit == "player" then
        decay(health, now)
        return health
    elseif unit == "target" then
        return I.TargetHealth(now)
    end
    return otherHealth
end

--- (spec §3.1) The player's last plain maximum health; 100 for any other unit.
function VS.HealthMax(unit)
    if unit == "player" and I.healthMax > 0 then
        return I.healthMax
    end
    return 100
end

--- (spec §3.2) Spell haste percent: the last plain read, default 0; in a fight with a `spellHaste` aura declared, the
--- base split at the pull x the declared multipliers up at `now` (the stat split above). Allocates nothing.
function VS.SpellHaste(now)
    decay(spellHaste, now)
    if split[0] and baseAt[0] > 0 and hasteReadT <= baseAt[0] then
        local _, mul = parts(0, now)
        local h = (base[0] * mul - 1) * 100
        spellHaste.est, spellHaste.lo, spellHaste.hi = h, h, h
    end
    return spellHaste
end

--- (spec §3.2) Time to die: the default 30 s (Hekili's DEFAULT_TTD), conf 0.
function VS.TTD(unit, now)
    return ttd
end

-- The stat cache (spec §6.5): the 12 stat names with the arguments Hekili reads them with (State.lua:2236-2356),
-- and the shield's block value (a class's rage from a blocked hit), read out of combat; up to 7 returns each.
I.STATS = {
    { "UnitStat", 1 },
    { "UnitStat", 2 },
    { "UnitStat", 3 },
    { "UnitStat", 4 },
    { "UnitStat", 5 },
    { "GetSpellBonusDamage", 7 },
    { "UnitAttackPower" },
    { "UnitWeaponAttackPower" },
    { "UnitDamage" },
    { "UnitRangedDamage" },
    { "UnitArmor" },
    { "GetShieldBlock" },
    { "GetMasteryEffect" },
    { "GetCritChance" },
    { "GetSpellCritChance" },
    { "GetRangedCritChance" },
    { "GetCombatRating", "CR_CRIT_MELEE" },
    { "GetCombatRating", "CR_HASTE_MELEE" },
    { "GetCombatRating", "CR_CRIT_TAKEN_SPELL" },
    { "GetCombatRating", "CR_MASTERY" },
    { "GetCombatRating", "CR_VERSATILITY_DAMAGE_DONE" },
    { "GetCombatRating", "CR_VERSATILITY_DAMAGE_TAKEN" },
    { "GetCombatRatingBonus", "CR_VERSATILITY_DAMAGE_DONE" },
    { "GetCombatRatingBonus", "CR_VERSATILITY_DAMAGE_TAKEN" },
}
-- statVal[i][1..7]: the cached returns; statT[i]: the read time; statIndex[name][arg or 0] = i.
I.statVal, I.statT, I.statIndex = {}, {}, {}
for i = 1, #I.STATS do
    I.statVal[i] = { 0, 0, 0, 0, 0, 0, 0 }
    I.statT[i] = 0
end

--- (spec §3.1) The returns of the last plain out-of-combat `apiName(arg)` call, in the real API's order; zeros before
--- the first read or for a call not cached. `arg` is the stat index, rating or school (nil for the unit-only calls).
--- UnitStat's effective value (its second return) is composed at `now` (default the belief's clock) in a fight when an
--- aura declares a part of it (the stat split above). Allocates nothing.
function VS.Stat(apiName, arg, now)
    local byArg = I.statIndex[apiName]
    local i = byArg and byArg[arg or 0]
    local v = i and I.statVal[i]
    if not v then
        return 0, 0, 0, 0, 0, 0, 0
    end
    if apiName == "UnitStat" and i <= 5 and split[i] and baseAt[i] > 0 and I.statT[i] <= baseAt[i] then
        local add, mul = parts(i, now or I.clock)
        return v[1], (base[i] + add) * mul, v[3], v[4], v[5], v[6], v[7]
    end
    return v[1], v[2], v[3], v[4], v[5], v[6], v[7]
end

I.OnSnapshot(function(out, now)
    VS.Health("player", now)
    VS.SpellHaste(now)
end)
