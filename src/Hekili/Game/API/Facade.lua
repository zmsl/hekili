-- Game/API/Facade.lua
-- ns.Facade (spec §7; event-facade spec §1.1): every game function Hekili core and the class files read, in one of
-- three classes (event-facade decision 8): `passthrough` (the raw call: plain by probe, or a value Hekili never uses
-- in a way a secret breaks), `hybrid` (the raw call; a secret answer is replaced by the policy's, for names secret
-- only sometimes) and `virtual` (the policy only, never the game's answer: secret always, absent on Forever, or
-- answered from VirtualState for a reason beyond secrecy). Namespaces mirror the game (Facade.UnitPower,
-- Facade.C_Spell.GetSpellCooldown, Facade.AuraUtil.ForEachAura). Query with Facade.Status(name) (the class),
-- Facade.Why(name), Facade.Inventory(); tools/api_inventory.txt lists every name with its class.
-- Every policy uses now = GetTime(), or the clock Drain pins while it applies a cast (spec §5.5 R1), and returns
-- shared preallocated result tables that callers read at once and never keep or mutate.
-- Origin: Libs/VirtualGameAPI-1.0, folded into Hekili. Copyright (c) 2026 Zack Samsel. MIT licence, see
-- Libs/VirtualGameAPI-1.0/LICENSE.
-- Credits: the issecretvalue tests on the real cooldown flags follow Catnip's (Durts) secret-value research.

local _, ns = ...
local VS, I = ns.VirtualState, ns.VirtualStateInternal
local floor, find, HUGE = math.floor, string.find, math.huge
local _G = _G

local Facade = {}
ns.Facade = Facade

local status, why, inventory = {}, {}, {}

local function split(name)
    local nsName, key = name:match("^([%w_]+)%.([%w_]+)$")
    if nsName then
        return nsName, key
    end
    return nil, name
end

-- The real function `name` names, or nil (absent on this client). Load time only.
local function resolve(name)
    local nsName, key = split(name)
    if nsName then
        local t = _G[nsName]
        return t and t[key]
    end
    return _G[key]
end

local GetTime = resolve("GetTime")
local issecretvalue = resolve("issecretvalue") or function()
    return false
end
Facade.issecretvalue = issecretvalue -- the secrecy test a passthrough row's reader needs (Engine/Schema/Spec.lua's `threat`)

----------------------------------------------------------------------------------------------------------------------
-- The trace (event-facade spec §5, decision 3): while Hekili makes a snapshot (`Hekili.ActiveDebug`), every facade
-- read writes one line through Hekili:Debug into the snapshot: the class that answered (a hybrid says whether the
-- raw value or the model did), the name, two arguments and four results, a secret shown as S. Off, a read costs one
-- field test. Facade.Attach(Hekili) (Adapter.lua) names the addon table; until then nothing is traced.

local hk = { ActiveDebug = false }
function Facade.Attach(hekili)
    hk, I.hekili = hekili, hekili
end

local busy, modelled = false, false
Facade.secrets = {} -- by name: secret answers from a passthrough, or a hybrid's raw answer, while tracing (E11)
Facade.QUIET = { GetTime = true } -- read so often it would bury the snapshot: counted, not written
Facade.counts = {} -- by name: reads while tracing

-- A value as trace text: S for a secret, scalars of a table copied now (never the shared table, whose values change
-- later), each field tested with issecretvalue before it is compared or converted.
local function field(v)
    if issecretvalue(v) then
        return "S"
    end
    return tostring(v)
end

local function show(v)
    if issecretvalue(v) then
        return "S"
    elseif type(v) ~= "table" then
        return tostring(v)
    end
    local id, start = v.spellId, v.startTime
    if issecretvalue(id) or id ~= nil then
        return "aura:" .. field(id) .. "/" .. field(v.expirationTime) .. "/" .. field(v.applications)
    elseif issecretvalue(start) or start ~= nil then
        return "cd:" .. field(start) .. "/" .. field(v.duration)
    end
    return "table"
end

-- One trace line (run through pcall: a raising Debug or a strange value never reaches the read).
local function write(name, kind, a1, a2, n, r1, r2, r3, r4)
    Facade.counts[name] = (Facade.counts[name] or 0) + 1
    -- a hybrid's raw answer counts too: UnitExists and UnitIsDead pass every unit but the pet through raw
    if kind == "passthrough" or (kind == "hybrid" and not modelled) then
        if issecretvalue(r1) or issecretvalue(r2) or issecretvalue(r3) or issecretvalue(r4) then
            Facade.secrets[name] = (Facade.secrets[name] or 0) + 1
        end
    end
    if kind == "hybrid" then
        kind = modelled and "hybrid:model" or "hybrid:raw"
    end
    if not Facade.QUIET[name] then
        hk:Debug(
            "[vs] %s %s(%s, %s) -> %s, %s, %s, %s #%d",
            kind,
            name,
            show(a1),
            show(a2),
            show(r1),
            show(r2),
            show(r3),
            show(r4),
            n
        )
    end
end

local function traced(name, kind, a1, a2, ...)
    if not busy then
        busy = true
        local r1, r2, r3, r4 = ...
        pcall(write, name, kind, a1, a2, select("#", ...), r1, r2, r3, r4)
        busy = false -- every path: pcall returns whatever write did
    end
    return ...
end

-- Every row is stored behind one wrapper that traces it while Hekili debugs (decision 4: one branch when off).
local function kept(name, kind, fn, reason)
    local nsName, key = split(name)
    local t = Facade
    if nsName then
        Facade[nsName] = Facade[nsName] or {}
        t = Facade[nsName]
    end
    t[key] = function(...)
        if hk.ActiveDebug then
            local a1, a2 = ...
            modelled = false
            return traced(name, kind, a1, a2, fn(...))
        end
        return fn(...)
    end
    inventory[#inventory + 1] = name
    status[name], why[name] = kind, reason
end
local realUnitPowerType = resolve("UnitPowerType")
local realUnitIsDead = resolve("UnitIsDead")
local realGetSpellCooldown = resolve("C_Spell.GetSpellCooldown")
local realIsSpellUsable = resolve("C_Spell.IsSpellUsable")
local realGetSpellInfo = resolve("C_Spell.GetSpellInfo")
local realUnitCastingInfo = resolve("UnitCastingInfo")
local realUnitChannelInfo = resolve("UnitChannelInfo")
local realGetSpellCharges = resolve("C_Spell.GetSpellCharges")

--- A passthrough: the raw function behind the row's wrapper, so a later finding changes one row, not Hekili. A name the
--- client lacks (the deprecation shims while `loadDeprecationFallbacks` is off) answers nothing and is virtual.
local function passthrough(name, reason)
    local real = resolve(name)
    if not real then
        kept(name, "virtual", function() end, "absent on this client; answers nothing (" .. reason .. ")")
        return
    end
    kept(name, "passthrough", real, reason)
end

-- The raw answer, or the policy's when any of its first four values is secret. Allocates nothing.
-- Tests only those four (the times sit there); later values (GetTotemInfo's icon, modRate, spellID) pass untested.
local function pick(policy, x, y, z, a, b, c, d, ...)
    if issecretvalue(a) or issecretvalue(b) or issecretvalue(c) or issecretvalue(d) then
        modelled = true
        return policy(x, y, z)
    end
    return a, b, c, d, ...
end

--- A hybrid of up to three arguments: the raw call, its secret answer replaced by `policy`'s (absent: the policy).
local function hybrid(name, policy, reason)
    local real = resolve(name)
    if not real then
        kept(name, "virtual", policy, reason .. "; absent on this client")
        return
    end
    kept(name, "hybrid", function(x, y, z)
        return pick(policy, x, y, z, real(x, y, z))
    end, reason)
end

-- The raw answer when every value is plain, else nothing (no cast). Allocates nothing.
local function plainAll(...)
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then
            return nil
        end
    end
    return ...
end

-- Whether a cooldown or charge table's two time fields are plain numbers (the hybrid tables' test).
local function plainTimes(info, startKey, durationKey)
    if issecretvalue(info) or type(info) ~= "table" then
        return false
    end
    local s, d = info[startKey], info[durationKey]
    if issecretvalue(s) or issecretvalue(d) then
        return false
    end
    return type(s) == "number" and type(d) == "number"
end

-- The facade's clock.
local function now()
    return GetTime()
end
Facade.Now = now

-- Shared stub results (the original's, VirtualGameAPI-1.0.lua:77-88).
local function nothing()
    return nil
end
local function zero()
    return 0
end
local function isFalse()
    return false
end
local function inRangeUnknown()
    return false, true
end

----------------------------------------------------------------------------------------------------------------------
-- Resources [W PR16]

kept("UnitPower", "virtual", function(unit, powerType)
    if unit ~= "player" then
        return 0
    end
    if powerType == nil then
        powerType = realUnitPowerType and realUnitPowerType("player")
        if issecretvalue(powerType) or type(powerType) ~= "number" then
            powerType = 0
        end
    end
    local b = VS.Power(powerType, now())
    -- lo for every resource: rage's speed-based model has a zero band and errs upward only, so lo is a true floor (G4)
    return floor(b.lo)
end, "secret always [W PR16]; Power().lo for every resource (G4's rage exception dropped 2026-10-16)")

hybrid("GetPowerRegenForPowerType", function(powerType)
    local r = I.res.slotOf[powerType]
    if r and I.res.swing[r] > 0 then
        return 0, 0 -- Hekili's swing regen model adds that resource in combat; no swings out of combat (G3)
    end
    local est = VS.Regen(powerType, now()).est
    return est, est
end, "secret in combat [W PR16]; Regen(), 0 for a swing-paid resource (G3)")

hybrid("GetManaRegen", function()
    local t = now()
    local inactive = VS.Regen(0, t).est
    return inactive, VS.Regen(0, t, true).est
end, "secret in combat [W PR16]; Regen(0)")

kept("UnitPartialPower", "virtual", zero, "secret always [W PR16]; no Forever user")

----------------------------------------------------------------------------------------------------------------------
-- Health [W PR14]

kept("UnitHealth", "virtual", function(unit)
    if unit == "player" then
        return VS.Health("player", now()).est * VS.HealthMax("player")
    elseif unit == "target" then
        return VS.Health("target", now()).est * 100
    end
    local dead = realUnitIsDead and realUnitIsDead(unit) -- secret: tested next
    if issecretvalue(dead) or dead then
        return 0
    end
    return 100 -- keeps the enemy scan's UnitHealth( unit ) > 1 (Targets.lua:407, 484) meaningful
end, "target secret always [W PR14]; Health()")

-- The player's maximum: the raw read while plain, the belief's when secret; another unit's (secret always) the belief's,
-- without a call. Allocates nothing.
local realUnitHealthMax = resolve("UnitHealthMax")
kept("UnitHealthMax", realUnitHealthMax and "hybrid" or "virtual", function(unit)
    if unit == "player" and realUnitHealthMax then
        local v = realUnitHealthMax(unit)
        if not issecretvalue(v) then
            return v
        end
        modelled = true
    end
    return VS.HealthMax(unit)
end, "player plain in combat [probe 2026-10-16], HealthMax() when secret; target secret always [W PR14]; HealthMax()")

kept("UnitGetTotalAbsorbs", "virtual", zero, "target secret always [W PR14]")

----------------------------------------------------------------------------------------------------------------------
-- Stats: the out-of-combat cache [W PR2, PR4]

local STAT = "secret in combat [W PR2, PR4]; Stat()"
hybrid("GetCombatRating", function(cr)
    return VS.Stat("GetCombatRating", cr)
end, STAT)
hybrid("GetCombatRatingBonus", function(cr)
    return VS.Stat("GetCombatRatingBonus", cr)
end, STAT)
hybrid("GetCritChance", function()
    return VS.Stat("GetCritChance")
end, STAT)
hybrid("GetMasteryEffect", function()
    return VS.Stat("GetMasteryEffect")
end, STAT)
hybrid("GetRangedCritChance", function()
    return VS.Stat("GetRangedCritChance")
end, STAT)
hybrid("GetSpellBonusDamage", function(school)
    return VS.Stat("GetSpellBonusDamage", school)
end, STAT)
hybrid("GetSpellCritChance", function()
    return VS.Stat("GetSpellCritChance")
end, STAT)
hybrid("UnitArmor", function()
    return VS.Stat("UnitArmor")
end, STAT)
hybrid("UnitAttackPower", function()
    return VS.Stat("UnitAttackPower")
end, STAT)
hybrid("UnitDamage", function()
    return VS.Stat("UnitDamage")
end, STAT)
hybrid("UnitStat", function(unit, index)
    return VS.Stat("UnitStat", index)
end, STAT)
hybrid("UnitWeaponAttackPower", function()
    return VS.Stat("UnitWeaponAttackPower")
end, STAT)

----------------------------------------------------------------------------------------------------------------------
-- Haste and speed [W PR2, PR7, PR14; SU PR2]

local function meleeHaste()
    return (VS.Haste(now()).est - 1) * 100
end
hybrid("GetHaste", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")
hybrid("GetMeleeHaste", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")

hybrid("UnitSpellHaste", function(unit)
    if unit ~= "player" then
        return 0
    end
    return VS.SpellHaste(now()).est
end, "secret in combat [W PR2, PR4]; SpellHaste()")

hybrid("UnitAttackSpeed", function(unit)
    if unit ~= "player" then
        return 2, nil
    end
    local t = now()
    local main = VS.SwingSpeed(1, t).est
    local off = VS.SwingSpeed(2, t).est
    if off > 0 then
        return main, off
    end
    return main, nil
end, "secret in combat [SU PR2]; SwingSpeed()")

-- The speed is the ranged hand's (C7: out of combat, or a swingType 2 duration); the rest the out-of-combat cache.
hybrid("UnitRangedDamage", function()
    local speed, lo, hi, pos, neg, pct = VS.Stat("UnitRangedDamage")
    local s = VS.SwingSpeed(3, now()).est
    return s > 0 and s or speed, lo, hi, pos, neg, pct
end, "SecretWhenUnitStatsRestricted (API docs); unprobed (Hunter Q1); SwingSpeed(3), Stat()")

hybrid("GetUnitSpeed", function(unit)
    if unit == "player" and VS.Moving() then
        return 7, 7, 7, 4.72
    elseif unit == "player" then
        return 0, 7, 7, 4.72
    end
    return 0, 0, 0, 0
end, "secret in combat [W PR14]; Moving()")

kept("UnitInRange", "virtual", inRangeUnknown, "secret always [W PR7]; no signal")

----------------------------------------------------------------------------------------------------------------------
-- Totems [W PR12]

hybrid("GetTotemInfo", function(slot)
    local spellID, name, icon, start = VS.TotemFacts(slot)
    local rec = spellID and VS.Totem(slot, now())
    if not rec then
        return false, "", 0, 0, 0
    end
    return true, name, start, rec.est - start, icon, 1, spellID
end, "secret in combat [W PR12]; Totem(), TotemFacts()")

----------------------------------------------------------------------------------------------------------------------
-- Auras [W §4]: one shared AuraData per index slot, one more for the by-ID and by-instance reads.

local AURA_SLOTS = 40
local POINTS = {}
local function newAura()
    return {
        name = "",
        icon = 0,
        applications = 0,
        dispelName = nil,
        duration = 0,
        expirationTime = 0,
        sourceUnit = "player",
        isStealable = false,
        nameplateShowPersonal = false,
        spellId = 0,
        canApplyAura = true,
        isBossAura = false,
        isFromPlayerOrPlayerPet = true,
        nameplateShowAll = false,
        timeMod = 1,
        auraInstanceID = 0,
        isHelpful = true,
        isHarmful = false,
        points = POINTS,
    }
end
local slots = {}
for i = 1, AURA_SLOTS do
    slots[i] = newAura()
end
local single = newAura()

-- Spell names and icons, read once per spell ID (the client allocates its info table once per ID).
local names, icons = {}, {}
local function spellName(id)
    local n = names[id]
    if n == nil then
        local info = id > 0 and realGetSpellInfo and realGetSpellInfo(id) -- a pseudo-aura's negative ID asks nothing
        n = info and info.name or tostring(id)
        names[id], icons[id] = n, info and info.iconID or 0
    end
    return n, icons[id]
end

local function fill(t, spellID, rec, stacks, applied, instance, harmful)
    t.name, t.icon = spellName(spellID)
    t.spellId, t.applications, t.auraInstanceID = spellID, stacks, instance
    if rec.est == HUGE then
        t.expirationTime, t.duration = 0, 0 -- no expiry, as the client says it
    else
        t.expirationTime = rec.lo -- the early bound: refresh sooner rather than late
        t.duration = rec.est - applied
    end
    t.isHarmful, t.isHelpful = harmful, not harmful
    return t
end

local function auraAt(unit, harmful, i)
    local spellID, rec, stacks, applied, instance = VS.AuraAt(unit, harmful and "HARMFUL" or "HELPFUL", i, now())
    if not spellID or i > AURA_SLOTS then
        return nil
    end
    return fill(slots[i], spellID, rec, stacks, applied, instance, harmful)
end

kept("C_UnitAuras.GetBuffDataByIndex", "virtual", function(unit, i)
    return auraAt(unit, false, i)
end, "secret in combat; errors when tainted [W §4]; AuraAt()")

kept("C_UnitAuras.GetDebuffDataByIndex", "virtual", function(unit, i)
    return auraAt(unit, true, i)
end, "secret in combat; errors when tainted [W §4]; AuraAt()")

kept("C_UnitAuras.GetPlayerAuraBySpellID", "virtual", function(spellID)
    local rec, stacks, applied, instance = VS.Aura("player", spellID, now())
    if not rec then
        return nil
    end
    return fill(single, spellID, rec, stacks, applied, instance, false)
end, "secret in combat; errors when tainted [W §4]; Aura()")

kept("C_UnitAuras.GetAuraDataByAuraInstanceID", "virtual", function(unit, instanceID)
    local spellID, rec, stacks, applied = VS.AuraByInstance(unit, instanceID, now())
    if not spellID then
        return nil
    end
    return fill(single, spellID, rec, stacks, applied, instanceID, unit ~= "player")
end, "secret in combat; errors when tainted [W §4]; AuraByInstance()")

kept("AuraUtil.ForEachAura", "virtual", function(unit, filter, maxCount, fn)
    local harmful = filter and find(filter, "HARMFUL", 1, true) ~= nil or false
    for i = 1, maxCount or AURA_SLOTS do
        local t = auraAt(unit, harmful, i)
        if not t or fn(t) then
            return
        end
    end
end, "wraps secret aura data [W §4]; AuraAt(), the shared AuraData")

-- AuraUtil.UnpackAuraData's order (without the points), for FindAura's predicate and result.
local function unpackAura(t)
    return t.name,
        t.icon,
        t.applications,
        t.dispelName,
        t.duration,
        t.expirationTime,
        t.sourceUnit,
        t.isStealable,
        t.nameplateShowPersonal,
        t.spellId,
        t.canApplyAura,
        t.isBossAura,
        t.isFromPlayerOrPlayerPet,
        t.nameplateShowAll,
        t.timeMod
end

kept("AuraUtil.FindAura", "virtual", function(predicate, unit, filter, arg1, arg2, arg3)
    local harmful = filter and find(filter, "HARMFUL", 1, true) ~= nil or false
    for i = 1, AURA_SLOTS do
        local t = auraAt(unit, harmful, i)
        if not t then
            return nil
        end
        if predicate(arg1, arg2, arg3, unpackAura(t)) then
            return unpackAura(t)
        end
    end
    return nil
end, "wraps secret aura data [W §4]; AuraAt()")

kept("C_UnitAuras.GetAuraSlots", "virtual", nothing, "secret in combat [W §4]; no retained consumer")
kept("UnitAura", "virtual", nothing, "absent on Forever")
kept("UnitAuraBySlot", "virtual", nothing, "absent on Forever")

-- Stealth (C5): the believed state of the `isStealthed` auras (Sources/Forms.lua) when the answer is secret.
hybrid("IsStealthed", function()
    local list, t = I.stealthAuras, now()
    for k = 1, list.n do
        if VS.Aura("player", I.auras.id[list[k]], t) then
            return true
        end
    end
    return false
end, "no SecretWhen* flag in the API docs, but unprobed in combat (Rogue Q5); a believed-up `isStealthed` aura")

-- Weapon enchants (C4): the client's list of WeaponEnchantInfo while every field is plain, else the slot's
-- `weaponEnchant` pseudo-aura (Sources/Enchants.lua) in that shape (timeLeft in ms), in shared tables.
local realGetWeaponEnchantInfo = resolve("C_Item.GetWeaponEnchantInfo")
local ENCHANT = { hasEnchant = true, enchantType = 0, timeLeft = 0, charges = 0, enchantID = 0, enchantIconID = 0 }
local ENCHANTS, NO_ENCHANTS = { ENCHANT }, {}
local function plainEnchants(list)
    if issecretvalue(list) or type(list) ~= "table" then
        return false
    end
    for i = 1, #list do
        local e = list[i]
        if issecretvalue(e) or type(e) ~= "table" then
            return false
        end
        if
            issecretvalue(e.hasEnchant)
            or issecretvalue(e.enchantType)
            or issecretvalue(e.timeLeft)
            or issecretvalue(e.charges)
            or issecretvalue(e.enchantID)
            or issecretvalue(e.enchantIconID)
        then
            return false
        end
    end
    return true
end
kept("C_Item.GetWeaponEnchantInfo", realGetWeaponEnchantInfo and "hybrid" or "virtual", function(slot)
    local list = realGetWeaponEnchantInfo and realGetWeaponEnchantInfo(slot) -- secret: tested next
    if plainEnchants(list) then
        return list
    end
    modelled = true
    local j, t = I.enchantSlot[slot], now()
    local rec, stacks
    if j then
        rec, stacks = VS.Aura("player", I.auras.id[j], t)
    end
    if not rec then
        return NO_ENCHANTS
    end
    -- rec.lo, the conservative bound (as the aura facade's expirationTime): a pack reapplies early, never late.
    ENCHANT.timeLeft = rec.lo == HUGE and 0 or floor((rec.lo - t) * 1000)
    ENCHANT.charges = stacks
    return ENCHANTS
end, "unprobed (Rogue Q9); the slot's `weaponEnchant` pseudo-aura when any field is secret")

-- Pets (C1): the pet unit's reads are plain [W PR14; gate spike]; for "pet", our summon's model answers them until the
-- first observation (Families/Pets.lua, VS.Pet), and so does the belief's last observation when one is secret. Every
-- other unit gets the raw answer, as the passthrough did.
hybrid("UnitCreatureFamily", nothing, "SecretWhenUnitIdentityRestricted (API docs); unprobed (C1); nothing")

local realUnitExists = resolve("UnitExists")
kept("UnitExists", "hybrid", function(unit)
    if unit == "pet" then
        local exists, _, model = VS.Pet(now())
        local raw = not model and realUnitExists and realUnitExists(unit) -- secret: tested next
        if model or issecretvalue(raw) then
            modelled = true
            return exists
        end
        return raw
    end
    if realUnitExists then
        return realUnitExists(unit)
    end
end, "plain in combat [W PR14; gate spike]; for the pet, Pet() while our summon is modelled or the read is secret")

kept("UnitIsDead", "hybrid", function(unit)
    if unit == "pet" then
        local _, dead, model = VS.Pet(now())
        local raw = not model and realUnitIsDead and realUnitIsDead(unit) -- secret: tested next
        if model or issecretvalue(raw) then
            modelled = true
            return dead
        end
        return raw
    end
    if realUnitIsDead then
        return realUnitIsDead(unit)
    end
end, "plain in combat [W PR14; gate spike]; for the pet, Pet() while our summon is modelled or the read is secret")

----------------------------------------------------------------------------------------------------------------------
-- Cooldowns [W PR4, PR11]: times secret in combat, flags plain

local CD = { startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }
local CHARGES = { currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }

-- The real call's plain flags: isActive, isOnGCD (each nil when secret or unreadable).
local function flags(spellID)
    local info = realGetSpellCooldown and realGetSpellCooldown(spellID) -- secret: tested next, then each field
    if issecretvalue(info) or type(info) ~= "table" then
        return nil, nil
    end
    local active, onGcd = info.isActive, info.isOnGCD -- secret: each tested next
    if issecretvalue(active) then
        active = nil
    end
    if issecretvalue(onGcd) then
        onGcd = nil
    end
    return active, onGcd
end

local function cooldownPolicy(spellID)
    local t = now()
    if spellID == I.GCD_SPELL then
        local s, d = VS.GcdInfo(t)
        CD.startTime, CD.duration, CD.isActive, CD.isOnGCD = s, d, d > 0, false
        return CD
    end
    local active, onGcd = flags(spellID)
    if onGcd == true then
        -- bit-identical to the GCD's numbers, so Hekili zeroes it (State.lua:2972-2975, spec §7.5)
        local s, d = VS.GcdInfo(t)
        CD.startTime, CD.duration, CD.isActive, CD.isOnGCD = s, d, true, true
        return CD
    end
    local rec = VS.Cooldown(spellID, t)
    CD.isOnGCD = false
    if not rec then
        CD.startTime, CD.duration = 0, 0
        CD.isActive = active == true
        return CD
    end
    if rec.est <= t or active == false then
        -- ready (believed, or the plain flag, which leads the belief by a poll): the client's ready shape, not a
        -- finished cooldown Hekili would read as running
        CD.startTime, CD.duration = 0, 0
        CD.isActive = active == true
        return CD
    end
    local len = VS.CooldownLength(spellID)
    CD.startTime, CD.duration = rec.est - len, len
    if active ~= nil then
        CD.isActive = active
    else
        CD.isActive = rec.est > t
    end
    return CD
end
kept("C_Spell.GetSpellCooldown", "hybrid", function(spellID)
    local info = realGetSpellCooldown and realGetSpellCooldown(spellID)
    if plainTimes(info, "startTime", "duration") then
        return info
    end
    modelled = true
    return cooldownPolicy(spellID)
end, "times secret in combat, flags plain [W PR4, PR11]; Cooldown(), GcdInfo()")

local function chargesPolicy(spellID)
    local cur, nextAt = VS.Charges(spellID, now())
    if not cur then
        return nil
    end
    local a = I.ab.bySpell[spellID]
    local obj = I.ab.obj[a]
    local recharge = type(obj.recharge) == "number" and obj.recharge or 0
    CHARGES.currentCharges = floor(cur.est)
    CHARGES.maxCharges = type(obj.charges) == "number" and obj.charges or 1
    CHARGES.cooldownStartTime = nextAt.est > 0 and nextAt.est - recharge or 0
    CHARGES.cooldownDuration = recharge
    return CHARGES
end
kept("C_Spell.GetSpellCharges", "hybrid", function(spellID)
    local info = realGetSpellCharges and realGetSpellCharges(spellID)
    if not issecretvalue(info) and info == nil then
        return nil -- not a charge spell (plain)
    end
    if plainTimes(info, "cooldownStartTime", "cooldownDuration") then
        return info
    end
    modelled = true
    return chargesPolicy(spellID)
end, "times secret in combat [W §4 cooldowns]; Charges()")

kept("C_Spell.GetSpellCastCount", "virtual", zero, "flagged SecretWhenCooldownsRestricted; unprobed, unused")
kept("C_Spell.GetSpellLossOfControlCooldown", "virtual", nothing, "absent on Forever")

----------------------------------------------------------------------------------------------------------------------
-- Casts: the player's own are plain [W PR9], the target's secret [W PR8]

local CAST_ICON = 136243

kept("UnitCastingInfo", "hybrid", function(unit, ...)
    if unit == "player" then
        if realUnitCastingInfo then
            return plainAll(realUnitCastingInfo(unit, ...))
        end
        return nil
    elseif unit ~= "target" then
        return nil
    end
    modelled = true
    local channel, castBarID, start, interruptible = VS.TargetCastFacts()
    local rec = channel == false and VS.TargetCast(now())
    if not rec then
        return nil
    end
    return "Casting", "", CAST_ICON, start * 1000, rec.est * 1000, false, castBarID, interruptible == 0, 0
end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")

kept("UnitChannelInfo", "hybrid", function(unit, ...)
    if unit == "player" then
        if realUnitChannelInfo then
            return plainAll(realUnitChannelInfo(unit, ...))
        end
        return nil
    elseif unit ~= "target" then
        return nil
    end
    modelled = true
    local channel, _, start, interruptible = VS.TargetCastFacts()
    local rec = channel == true and VS.TargetCast(now())
    if not rec then
        return nil
    end
    return "Channeling", "", CAST_ICON, start * 1000, rec.est * 1000, false, interruptible == 0, 0
end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")

----------------------------------------------------------------------------------------------------------------------
-- Combat log, talents, spells and items: absent on Forever, or replaced

kept("CombatLogGetCurrentEventInfo", "virtual", I.Log.Current, "absent; the row being delivered (event-facade §2.4)")
-- A talent in the GetTalentInfoByID shape upstream Hekili's code expects, from the C_Traits walk (event-facade
-- decision 7): `talent` is a RegisterTalents entry { node, spell, max rank } or a spell ID; always named (the caller's
-- IsPlayerSpell fallback would get a table), selected and known with any rank, the rank as a 12th return (Forever's;
-- not in that shape).
kept("GetTalentInfoByID", "virtual", function(talent)
    local spell = talent
    if type(talent) == "table" then
        spell = talent[2]
    end
    if type(spell) ~= "number" then
        return nil
    end
    local rank = VS.Talent(spell)
    return spell, "", 0, rank > 0, true, spell, nil, 0, 0, rank > 0, false, rank
end, "dead on Forever [W PR5]; VirtualState.Talent (the C_Traits walk)")
kept("IsUsableSpell", "passthrough", function(spellID)
    if realIsSpellUsable then
        return realIsSpellUsable(spellID)
    end
    return false
end, "absent on Forever; alias of C_Spell.IsSpellUsable (plain [W PR14; SU])")
kept("GetSpellBaseCooldown", "virtual", nothing, "absent on Forever")
kept("GetSpellLink", "virtual", nothing, "absent on Forever")
kept("IsHarmfulSpell", "virtual", isFalse, "absent on Forever")
kept("IsHelpfulSpell", "virtual", isFalse, "absent on Forever")
kept("IsPassiveSpell", "virtual", isFalse, "absent on Forever")
kept("GetItemGem", "virtual", nothing, "absent on Forever")
kept("GetItemInfo", "virtual", nothing, "absent on Forever")

----------------------------------------------------------------------------------------------------------------------
-- The clock: the client's, except while a back-dated row is delivered (event-facade spec §3, decision 5)

kept("GetTime", "hybrid", function()
    local b = I.backdate
    if b then
        modelled = true
        return b
    end
    return GetTime()
end, "plain [W]; a back-dated combat-log row's observed time while it is delivered")

----------------------------------------------------------------------------------------------------------------------
-- Forever's answers in the shape upstream Hekili's code expects (event-facade decision 7): an empty specialization slot. Hekili asks the GCD as
-- Forever's own spell, I.GCD_SPELL (shared-content spec §5).

local realGetSpecializationInfo = resolve("C_SpecializationInfo.GetSpecializationInfo")

local function noEmptySlot(id, ...)
    if not issecretvalue(id) and id == 0 then
        return nil -- Forever answers id 0 for an empty slot; upstream's code expects nothing
    end
    return id, ...
end
kept("C_SpecializationInfo.GetSpecializationInfo", "hybrid", function(...)
    return noEmptySlot(realGetSpecializationInfo(...))
end, "plain [W PR15]; Forever's id 0 for an empty slot answered as nil (cleanup Q7)")

----------------------------------------------------------------------------------------------------------------------
-- Frames: the event facade's entry point (event-facade spec §2.1)

kept("CreateFrame", "virtual", I.Events.CreateFrame, "the event facade: a frame whose events subscribe to the layer")

----------------------------------------------------------------------------------------------------------------------
-- Passthroughs: the evidence per name from docs/forever-facade-notes.md ("[W sweep 2026-10-16]": the ForeverProbe sweep
-- read it plain in and out of combat; not combat state, and the trace counts any secret answer, event-facade spec §5)

local PASSTHROUGH = {
    { "AuraUtil.UnpackAuraData", "pure Lua unpack of a table" },
    { "C_AddOns.GetAddOnMetadata", "plain [W sweep 2026-10-16]" },
    { "C_AddOns.IsAddOnLoaded", "plain [W sweep 2026-10-16]" },
    { "C_AddOns.LoadAddOn", "not probed (state-changing); assumed plain" },
    { "C_ClassColor.GetClassColor", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_ClassTalents.GetActiveConfigID", "plain [W sweep 2026-10-16]" },
    { "C_ClassTalents.GetHeroTalentSpecsForClassSpec", "plain [W sweep 2026-10-16]" },
    { "C_Item.GetDetailedItemLevelInfo", "plain [W PR13]" },
    { "C_Item.GetItemCooldown", "plain [W PR13]" },
    { "C_Item.GetItemCount", "plain [W PR13]" },
    { "C_Item.GetItemGem", "plain [W PR13]" },
    { "C_Item.GetItemInfo", "plain [W PR13]" },
    { "C_Item.GetItemInfoInstant", "plain [W PR13]" },
    { "C_Item.GetItemSpell", "plain [W PR13]" },
    { "C_Item.IsCurrentItem", "plain [W PR13]" },
    { "C_Item.IsEquippedItem", "plain [W PR13]" },
    { "C_Item.IsUsableItem", "plain [W PR13]" },
    { "C_LossOfControl.GetActiveLossOfControlData", "plain [W PR18]" },
    { "C_LossOfControl.GetActiveLossOfControlDataCount", "plain [W PR18]" },
    { "C_PetBattles.IsInBattle", "plain [W sweep 2026-10-16]" },
    { "C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier", "plain [W sweep 2026-10-16]" },
    { "C_PvP.IsWarModeDesired", "plain [W sweep 2026-10-16]" },
    { "C_SpecializationInfo.GetSpecialization", "plain [W PR15]" },
    { "C_SpecializationInfo.GetTalentInfo", "plain [W sweep 2026-10-16]" },
    { "C_Spell.GetSpellDescription", "plain [W sweep 2026-10-16]" },
    { "C_Spell.GetSpellInfo", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_Spell.GetSpellPowerCost", "plain [W §4]" },
    { "C_Spell.GetSpellTexture", "plain [W sweep 2026-10-16]" },
    { "C_Spell.IsCurrentSpell", "plain [W PR1]" },
    { "C_Spell.IsSpellDataCached", "plain [W sweep 2026-10-16]" },
    { "C_Spell.IsSpellHarmful", "plain [W sweep 2026-10-16]" },
    { "C_Spell.IsSpellHelpful", "plain [W sweep 2026-10-16]" },
    { "C_Spell.IsSpellPassive", "plain [W sweep 2026-10-16]" },
    { "C_Spell.IsSpellUsable", "plain [W PR14; SU]" },
    { "C_Spell.RequestLoadSpellData", "plain [W sweep 2026-10-16]" },
    { "C_SpellActivationOverlay.IsSpellOverlayed", "plain [W PR11]" },
    { "C_SpellBook.FindSpellBookSlotForSpell", "plain [W sweep 2026-10-16]" },
    { "C_SpellBook.GetNumSpellBookSkillLines", "plain [W sweep 2026-10-16]" },
    { "C_SpellBook.GetSpellBookItemInfo", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_SpellBook.GetSpellBookSkillLineInfo", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_SpellBook.IsSpellInSpellBook", "plain [W sweep 2026-10-16]" },
    { "C_SpellBook.IsSpellKnown", "plain [W sweep 2026-10-16]" },
    { "C_Texture.GetAtlasInfo", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_TooltipInfo.GetInventoryItem", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_TooltipInfo.GetItemByID", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_TooltipInfo.GetSpellByID", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "C_Traits.GetConfigInfo", "plain, walk identical in combat [W PR5]" },
    { "C_Traits.GetDefinitionInfo", "plain, walk identical in combat [W PR5]" },
    { "C_Traits.GetEntryInfo", "plain, walk identical in combat [W PR5]" },
    { "C_Traits.GetNodeCost", "plain, walk identical in combat [W PR5]" },
    { "C_Traits.GetNodeInfo", "plain, walk identical in combat [W PR5]" },
    { "C_Traits.GetSubTreeInfo", "plain, walk identical in combat [W PR5]" },
    { "C_Traits.GetTreeCurrencyInfo", "plain, walk identical in combat [W PR5]" },
    { "C_Traits.GetTreeNodes", "plain, walk identical in combat [W PR5]" },
    { "C_VideoOptions.GetCurrentGameWindowSize", "plain [W sweep 2026-10-16]; table fields unverified" },
    { "GetActionInfo", "plain [W PR10]" },
    { "GetBindingKey", "plain [W PR10]" },
    { "GetBuildInfo", "plain [W sweep 2026-10-16]" },
    { "GetCVar", "plain [W sweep 2026-10-16]" },
    { "GetClassInfo", "plain [W sweep 2026-10-16]" },
    { "GetCursorInfo", "plain [W sweep 2026-10-16]" },
    { "GetFrameCPUUsage", "plain [W sweep 2026-10-16]" },
    { "GetFramerate", "plain [W sweep 2026-10-16]" },
    { "GetInstanceInfo", "plain [W sweep 2026-10-16]" },
    { "GetInventoryItemID", "plain [W PR13]" },
    { "GetNetStats", "plain [W sweep 2026-10-16]" },
    { "GetNumClasses", "plain [W sweep 2026-10-16]" },
    { "GetNumGroupMembers", "plain [W sweep 2026-10-16]" },
    { "GetNumSubgroupMembers", "plain [W sweep 2026-10-16]" },
    { "GetRealmName", "plain [W sweep 2026-10-16]" },
    { "GetShapeshiftForm", "plain [W §4 (stance)]" },
    { "GetShapeshiftFormInfo", "plain [W PR10]" },
    { "GetSpecializationInfoByID", "plain [W sweep 2026-10-16]" },
    { "GetStablePetInfo", "missing on Forever [W sweep 2026-10-16]" },
    { "HasOverrideActionBar", "plain [W sweep 2026-10-16]" },
    { "HasVehicleActionBar", "plain [W sweep 2026-10-16]" },
    { "InCombatLockdown", "plain [W §3; lags at PLAYER_REGEN_DISABLED]" },
    { "IsActionInRange", "plain [W PR7]" },
    { "IsInGroup", "plain [W sweep 2026-10-16]" },
    { "IsInInstance", "plain [W sweep 2026-10-16]" },
    { "IsInRaid", "plain [W sweep 2026-10-16]" },
    { "IsMounted", "plain [W sweep 2026-10-16]" },
    { "IsPlayerSpell", "plain [W sweep 2026-10-16]" },
    { "IsResting", "plain [W sweep 2026-10-16]" },
    { "IsSpellKnown", "plain [W sweep 2026-10-16]" },
    { "IsSpellKnownOrOverridesKnown", "plain [W sweep 2026-10-16]" },
    { "SecureCmdOptionParse", "plain [W sweep 2026-10-16]" },
    { "SpellIsSelfBuff", "plain [W sweep 2026-10-16]" },
    { "UnitAffectingCombat", "plain in combat [W PR14; gate spike]" },
    { "UnitCanAssist", "plain [W sweep 2026-10-16]" },
    { "UnitCanAttack", "plain in combat [W PR14; gate spike]" },
    { "UnitClass", "plain in combat [W PR14; gate spike]" },
    { "UnitClassBase", "plain in combat [W PR14; gate spike]" },
    { "UnitClassification", "plain in combat [W PR14; gate spike]" },
    { "UnitCreatureType", "plain in combat [W PR14; gate spike]" },
    { "UnitEffectiveLevel", "plain [W sweep 2026-10-16]" },
    { "UnitFactionGroup", "plain [W sweep 2026-10-16]" },
    { "UnitGUID", "plain in combat [W PR14; gate spike]" },
    { "UnitHasVehicleUI", "plain [W sweep 2026-10-16]" },
    { "UnitInParty", "plain [W sweep 2026-10-16]" },
    { "UnitInRaid", "plain [W sweep 2026-10-16]" },
    { "UnitInVehicle", "plain [W sweep 2026-10-16]" },
    { "UnitIsConnected", "plain [W sweep 2026-10-16]" },
    { "UnitIsDeadOrGhost", "plain [W sweep 2026-10-16]" },
    { "UnitIsFriend", "plain in combat [W PR14; gate spike]" },
    { "UnitIsPVP", "plain [W sweep 2026-10-16]" },
    { "UnitIsPlayer", "plain in combat [W PR14; gate spike]" },
    { "UnitIsTrivial", "plain [W sweep 2026-10-16]" },
    { "UnitIsUnit", "plain in combat [W PR14; gate spike]" },
    { "UnitLevel", "plain in combat [W PR14; gate spike]" },
    { "UnitName", "plain in combat [W PR14; gate spike]" },
    { "UnitOnTaxi", "plain [W sweep 2026-10-16]" },
    { "UnitPhaseReason", "plain [W sweep 2026-10-16]" },
    { "UnitPowerMax", "plain (100 for rage) [W PR16]" },
    { "UnitPowerType", "plain [W PR16]" },
    { "UnitRace", "plain [W sweep 2026-10-16]" },
    { "UnitSex", "plain [W sweep 2026-10-16]" },
    { "UnitThreatSituation", "plain in combat [W PR14; gate spike]" },
    { "UnitTokenFromGUID", "plain [W sweep 2026-10-16]" },
}
for i = 1, #PASSTHROUGH do
    passthrough(PASSTHROUGH[i][1], PASSTHROUGH[i][2])
end

----------------------------------------------------------------------------------------------------------------------

table.sort(inventory)

function Facade.Status(name)
    return status[name]
end
function Facade.Why(name)
    return why[name]
end
function Facade.Inventory()
    return inventory
end

-- Snapshot's line: what the trace counted (allocates; debugging only).
I.OnSnapshot(function(out)
    local parts = {}
    for name, n in pairs(Facade.secrets) do
        parts[#parts + 1] = name .. "=" .. n
    end
    table.sort(parts)
    out[#out + 1] = "facade secret passthrough answers: " .. (#parts > 0 and table.concat(parts, " ") or "none")
end)
