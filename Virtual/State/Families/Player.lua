-- Virtual/State/Families/Player.lua
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

I.On(Obs.CombatStart, function(o, t)
    I.combatT = t
end)

-- Health (player: plain reads; every other unit: the default 1.0), spell haste, time to die.
local health, otherHealth, spellHaste, ttd
I.healthMax = 0

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
    I.Sample(spellHaste, "default", 0, now, 0)
    ttd = I.NewBelief("ttd")
    ttd.est, ttd.lo, ttd.hi = 30, 0, 3600
    I.Sample(ttd, "default", 30, now, 0)
end)

I.On(Obs.Read, function(o, t)
    if o.c == ReadOf.Health then
        health.est, health.lo, health.hi = o.b, o.b, o.b
        I.Sample(health, "observed", o.b, t, Obs.Read)
    end
end)

I.On(Obs.Haste, function(o, t)
    if o.c == 2 then
        spellHaste.est, spellHaste.lo, spellHaste.hi = o.b, o.b, o.b
        I.Sample(spellHaste, "observed", o.b, t, Obs.Haste)
    end
end)

--- (spec §3.2) Health fraction 0..1: the player's last plain read (conf decaying as an aura), else default 1.0.
function VS.Health(unit, now)
    if unit == "player" then
        decay(health, now)
        return health
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

--- (spec §3.2) Spell haste percent: the last plain read, default 0.
function VS.SpellHaste(now)
    decay(spellHaste, now)
    return spellHaste
end

--- (spec §3.2) Time to die: the default 30 s (Hekili's DEFAULT_TTD), conf 0.
function VS.TTD(unit, now)
    return ttd
end

-- The stat cache (spec §6.5): the 12 stat names with the arguments Hekili reads them with (State.lua:2236-2356),
-- read out of combat; up to 7 returns each.
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
    { "UnitArmor" },
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
--- Allocates nothing.
function VS.Stat(apiName, arg)
    local byArg = I.statIndex[apiName]
    local i = byArg and byArg[arg or 0]
    local v = i and I.statVal[i]
    if not v then
        return 0, 0, 0, 0, 0, 0, 0
    end
    return v[1], v[2], v[3], v[4], v[5], v[6], v[7]
end

I.OnSnapshot(function(out, now)
    VS.Health("player", now)
    VS.SpellHaste(now)
end)
