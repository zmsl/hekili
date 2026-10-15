-- VirtualState/Facade.lua
-- ns.Facade (spec §7): the game API names that are secret in combat, partly secret, or absent on WoW Forever. Each is
-- `virtual` (a policy answering from VirtualState, §7.4) or `stub` (a fixed, API-shaped result, §7.3); every other
-- game read in Hekili is a direct call. Namespaces mirror the game (Facade.UnitPower, Facade.C_Spell.GetSpellCooldown,
-- Facade.AuraUtil.ForEachAura). Query with Facade.Status(name), Facade.Why(name), Facade.Stubs(), Facade.Inventory().
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

local function kept(name, kind, fn, reason)
    local nsName, key = split(name)
    local t = Facade
    if nsName then
        Facade[nsName] = Facade[nsName] or {}
        t = Facade[nsName]
    end
    t[key] = fn
    inventory[#inventory + 1] = name
    status[name], why[name] = kind, reason
end

local GetTime = resolve("GetTime")
local issecretvalue = resolve("issecretvalue") or function()
    return false
end
local realUnitPowerType = resolve("UnitPowerType")
local realUnitIsDead = resolve("UnitIsDead")
local realGetSpellCooldown = resolve("C_Spell.GetSpellCooldown")
local realIsSpellUsable = resolve("C_Spell.IsSpellUsable")
local realGetSpellInfo = resolve("C_Spell.GetSpellInfo")
local realUnitCastingInfo = resolve("UnitCastingInfo")
local realUnitChannelInfo = resolve("UnitChannelInfo")

-- The facade's clock: the pinned cast time during a drain, else GetTime().
local function now()
    return I.pinned or GetTime()
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
        powerType = realUnitPowerType and realUnitPowerType("player") or 0
    end
    return floor(VS.Power(powerType, now()).lo) -- lo never over-promises a spender (feasibility §D.3)
end, "secret always [W PR16]; Power().lo")

kept("GetPowerRegenForPowerType", "virtual", function(powerType)
    local r = I.res.slotOf[powerType]
    if r and I.res.swing[r] > 0 and VS.InCombat() then
        return 0, 0 -- Hekili's swing regen model adds that resource (no double count, G3)
    end
    local est = VS.Regen(powerType, now()).est
    return est, est
end, "secret in combat [W PR16]; Regen()")

kept("GetManaRegen", "virtual", function()
    local t = now()
    local inactive = VS.Regen(0, t).est
    return inactive, VS.Regen(0, t, true).est
end, "secret in combat [W PR16]; Regen(0)")

kept("UnitPartialPower", "stub", zero, "secret always [W PR16]; no Forever user")

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

kept("UnitHealthMax", "virtual", function(unit)
    return VS.HealthMax(unit)
end, "target secret always [W PR14]; HealthMax()")

kept("UnitGetTotalAbsorbs", "stub", zero, "target secret always [W PR14]")

----------------------------------------------------------------------------------------------------------------------
-- Stats: the out-of-combat cache [W PR2, PR4]

local STAT = "secret in combat [W PR2, PR4]; Stat()"
kept("GetCombatRating", "virtual", function(cr)
    return VS.Stat("GetCombatRating", cr)
end, STAT)
kept("GetCombatRatingBonus", "virtual", function(cr)
    return VS.Stat("GetCombatRatingBonus", cr)
end, STAT)
kept("GetCritChance", "virtual", function()
    return VS.Stat("GetCritChance")
end, STAT)
kept("GetMasteryEffect", "virtual", function()
    return VS.Stat("GetMasteryEffect")
end, STAT)
kept("GetRangedCritChance", "virtual", function()
    return VS.Stat("GetRangedCritChance")
end, STAT)
kept("GetSpellBonusDamage", "virtual", function(school)
    return VS.Stat("GetSpellBonusDamage", school)
end, STAT)
kept("GetSpellCritChance", "virtual", function()
    return VS.Stat("GetSpellCritChance")
end, STAT)
kept("UnitArmor", "virtual", function()
    return VS.Stat("UnitArmor")
end, STAT)
kept("UnitAttackPower", "virtual", function()
    return VS.Stat("UnitAttackPower")
end, STAT)
kept("UnitDamage", "virtual", function()
    return VS.Stat("UnitDamage")
end, STAT)
kept("UnitStat", "virtual", function(unit, index)
    return VS.Stat("UnitStat", index)
end, STAT)
kept("UnitWeaponAttackPower", "virtual", function()
    return VS.Stat("UnitWeaponAttackPower")
end, STAT)

----------------------------------------------------------------------------------------------------------------------
-- Haste and speed [W PR2, PR7, PR14; SU PR2]

local function meleeHaste()
    return (VS.Haste(now()).est - 1) * 100
end
kept("GetHaste", "virtual", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")
kept("GetMeleeHaste", "virtual", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")

kept("UnitSpellHaste", "virtual", function(unit)
    if unit ~= "player" then
        return 0
    end
    return VS.SpellHaste(now()).est
end, "secret in combat [W PR2, PR4]; SpellHaste()")

kept("UnitAttackSpeed", "virtual", function(unit)
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

kept("GetUnitSpeed", "virtual", function(unit)
    if unit == "player" and VS.Moving() then
        return 7, 7, 7, 4.72
    elseif unit == "player" then
        return 0, 7, 7, 4.72
    end
    return 0, 0, 0, 0
end, "secret in combat [W PR14]; Moving()")

kept("UnitInRange", "stub", inRangeUnknown, "secret always [W PR7]; no signal")

----------------------------------------------------------------------------------------------------------------------
-- Totems [W PR12]

kept("GetTotemInfo", "virtual", function(slot)
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
        local info = realGetSpellInfo and realGetSpellInfo(id)
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

kept("C_UnitAuras.GetAuraSlots", "stub", nothing, "secret in combat [W §4]; no retained consumer")
kept("UnitAura", "stub", nothing, "absent on Forever")
kept("UnitAuraBySlot", "stub", nothing, "absent on Forever")

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

kept("C_Spell.GetSpellCooldown", "virtual", function(spellID)
    local t = now()
    if spellID == 61304 or spellID == I.GCD_SPELL then
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
    local len = VS.CooldownLength(spellID)
    CD.startTime, CD.duration = rec.est - len, len
    if active ~= nil then
        CD.isActive = active
    else
        CD.isActive = rec.est > t
    end
    return CD
end, "times secret in combat, flags plain [W PR4, PR11]; Cooldown(), GcdInfo()")

kept("C_Spell.GetSpellCharges", "virtual", function(spellID)
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
end, "times secret in combat [W §4 cooldowns]; Charges()")

kept("C_Spell.GetSpellCastCount", "stub", zero, "flagged SecretWhenCooldownsRestricted; unprobed, unused")
kept("C_Spell.GetSpellLossOfControlCooldown", "stub", nothing, "absent on Forever")

----------------------------------------------------------------------------------------------------------------------
-- Casts: the player's own are plain [W PR9], the target's secret [W PR8]

local CAST_ICON = 136243

kept("UnitCastingInfo", "virtual", function(unit, ...)
    if unit == "player" then
        if realUnitCastingInfo then
            return realUnitCastingInfo(unit, ...)
        end
        return nil
    elseif unit ~= "target" then
        return nil
    end
    local channel, castBarID, start, kick = VS.TargetCastFacts()
    local rec = channel == false and VS.TargetCast(now())
    if not rec then
        return nil
    end
    return "Casting", "", CAST_ICON, start * 1000, rec.est * 1000, false, castBarID, kick == 0, 0
end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")

kept("UnitChannelInfo", "virtual", function(unit, ...)
    if unit == "player" then
        if realUnitChannelInfo then
            return realUnitChannelInfo(unit, ...)
        end
        return nil
    elseif unit ~= "target" then
        return nil
    end
    local channel, _, start, kick = VS.TargetCastFacts()
    local rec = channel == true and VS.TargetCast(now())
    if not rec then
        return nil
    end
    return "Channeling", "", CAST_ICON, start * 1000, rec.est * 1000, false, kick == 0, 0
end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")

----------------------------------------------------------------------------------------------------------------------
-- Combat log, talents, spells and items: absent on Forever, or replaced

kept("CombatLogGetCurrentEventInfo", "stub", nothing, "absent; registering CLEU is forbidden (Phases 2 and 3)")
kept("GetTalentInfoByID", "stub", nothing, "dead on Forever [W PR5]; ranks come from VirtualState.Talent")
kept("IsUsableSpell", "virtual", function(spellID)
    if realIsSpellUsable then
        return realIsSpellUsable(spellID)
    end
    return false
end, "absent on Forever; alias of C_Spell.IsSpellUsable (plain [W PR14; SU])")
kept("GetSpellBaseCooldown", "stub", nothing, "absent on Forever")
kept("GetSpellLink", "stub", nothing, "absent on Forever")
kept("IsHarmfulSpell", "stub", isFalse, "absent on Forever")
kept("IsHelpfulSpell", "stub", isFalse, "absent on Forever")
kept("IsPassiveSpell", "stub", isFalse, "absent on Forever")
kept("GetItemGem", "stub", nothing, "absent on Forever")
kept("GetItemInfo", "stub", nothing, "absent on Forever")

----------------------------------------------------------------------------------------------------------------------

table.sort(inventory)
local stubs = {}
for _, name in ipairs(inventory) do
    if status[name] == "stub" then
        stubs[#stubs + 1] = name
    end
end

function Facade.Status(name)
    return status[name]
end
function Facade.Why(name)
    return why[name]
end
function Facade.Stubs()
    return stubs
end
function Facade.Inventory()
    return inventory
end
