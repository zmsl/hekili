--[[
VirtualGameAPI-1.0
A facade over the World of Warcraft game API for addons running on clients that return secret values
(WoW Forever, Midnight). Each game API an addon reads is registered here with a status:

  passthrough  the real function, called through one seam (`invoke`) so caching can be added later;
  stub         a fixed, non-secret, API-shaped result, used until a virtual game state answers the read;
  missing      a passthrough whose real function does not exist on this client (returns nil).

Namespaces mirror the game: VGA.UnitPower, VGA.C_Spell.GetSpellCooldown, VGA.AuraUtil.ForEachAura.
Query the table with VGA.Status(name), VGA.Why(name), VGA.Stubs() and VGA.Inventory().

Copyright (c) 2026 Zack Samsel. MIT licence, see LICENSE.
]]

local MAJOR, MINOR = "VirtualGameAPI-1.0", 1
local lib = LibStub:NewLibrary( MAJOR, MINOR )
if not lib then return end

local _G = _G
local status, why, inventory = {}, {}, {}

-- The single seam every passthrough goes through. A per-frame cache or a secrecy check lands here.
local function invoke( real, ... )
    return real( ... )
end

local function split( name )
    local nsName, key = name:match( "^([%w_]+)%.([%w_]+)$" )
    if nsName then return nsName, key end
    return nil, name
end

local function resolve( name )
    local nsName, key = split( name )
    if nsName then
        local t = _G[ nsName ]
        return t and t[ key ]
    end
    return _G[ key ]
end

local function slot( name )
    local nsName, key = split( name )
    if nsName then
        lib[ nsName ] = lib[ nsName ] or {}
        return lib[ nsName ], key
    end
    return lib, key
end

local function nothing() return nil end

local function passthrough( name, reason )
    local real = resolve( name )
    local t, key = slot( name )
    inventory[ #inventory + 1 ] = name
    why[ name ] = reason
    if real then
        status[ name ] = "passthrough"
        t[ key ] = function( ... ) return invoke( real, ... ) end
    else
        status[ name ] = "missing"
        t[ key ] = nothing
    end
end

local function stub( name, fn, reason )
    local t, key = slot( name )
    inventory[ #inventory + 1 ] = name
    status[ name ] = "stub"
    why[ name ] = reason
    t[ key ] = fn
end

-- Shared stub results. Callers read them and never mutate them.
local function zero() return 0 end
local function zero2() return 0, 0 end
local function zero4() return 0, 0, 0, 0 end
local function isFalse() return false end
local function zeros() return 0, 0, 0, 0, 0, 0, 0 end -- "0 for every return"; UnitDamage has 7
local function noop() end
local function noTotem() return false, "", 0, 0, 0 end
local function inRangeUnknown() return false, true end
local function attackSpeed() return 2, nil end -- keeps `UnitAttackSpeed( "player" ) > 0` true at load

local COOLDOWN = { startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }
local CHARGES = { currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }

-- A stub that still answers for the player's own unit, where the read is plain on Forever.
local function playerOnly( name )
    local real = resolve( name )
    return function( unit, ... )
        if unit == "player" and real then return invoke( real, unit, ... ) end
        return nil
    end
end

local function cooldown() return COOLDOWN end
local function charges() return CHARGES end

----------------------------------------------------------------------------------------------------
-- Resources: values are secret always on Forever [W PR16]; max and type are plain. Stubs return 0 per value.
stub( "UnitPower", zero, "secret always [W PR16]" )
stub( "UnitPartialPower", zero, "secret always [W PR16]" )
passthrough( "UnitPowerMax", "plain (100 for rage) [W PR16]" )
passthrough( "UnitPowerType", "plain [W PR16]" )
stub( "GetPowerRegenForPowerType", zero2, "secret in combat [W PR16]" )
stub( "GetManaRegen", zero2, "secret in combat [W PR16]" )

-- Health and absorbs: secret on the target always [W PR14]; stubs return 0.
stub( "UnitHealth", zero, "target secret always [W PR14]; player unprobed" )
stub( "UnitHealthMax", zero, "target secret always [W PR14]; player unprobed" )
stub( "UnitGetTotalAbsorbs", zero, "target secret always [W PR14]; player unprobed" )

-- Stats and haste: secret in combat [W PR2, PR4]; stubs return 0 for every return value.
stub( "GetCombatRating", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetCombatRatingBonus", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetCritChance", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetHaste", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetMasteryEffect", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetMeleeHaste", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetRangedCritChance", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetSpellBonusDamage", zeros, "secret in combat [W PR2, PR4]" )
stub( "GetSpellCritChance", zeros, "secret in combat [W PR2, PR4]" )
stub( "UnitArmor", zeros, "secret in combat [W PR2, PR4]" )
stub( "UnitAttackPower", zeros, "secret in combat [W PR2, PR4]" )
stub( "UnitAttackSpeed", attackSpeed, "secret in combat [SU PR2]" )
stub( "UnitDamage", zeros, "secret in combat [W PR2, PR4]" )
stub( "UnitSpellHaste", zeros, "secret in combat [W PR2, PR4]" )
stub( "UnitStat", zeros, "secret in combat [W PR2, PR4]" )
stub( "UnitWeaponAttackPower", zeros, "secret in combat [W PR2, PR4]" )

-- Movement and range: secret [W PR7, PR14]; speed returns four zeros, range returns (false, true).
stub( "GetUnitSpeed", zero4, "secret in combat [W PR14]" )
stub( "UnitInRange", inRangeUnknown, "secret always [W PR7]" )
passthrough( "IsActionInRange", "plain [W PR7]" )

-- Totems: secret in combat [W PR12]; stub returns (false, "", 0, 0, 0).
stub( "GetTotemInfo", noTotem, "secret in combat [W PR12]" )

-- Auras: aura data is secret in combat [W §4]; stubs return nil (no aura), ForEachAura iterates nothing.
stub( "AuraUtil.FindAura", nothing, "wraps secret aura data [W §4]" )
stub( "AuraUtil.ForEachAura", noop, "wraps secret aura data [W §4]" )
passthrough( "AuraUtil.UnpackAuraData", "pure Lua unpack of a table" )
stub( "C_UnitAuras.GetAuraDataByAuraInstanceID", nothing, "secret in combat; errors when tainted [W §4]" )
stub( "C_UnitAuras.GetAuraSlots", nothing, "secret in combat [W §4]" )
stub( "C_UnitAuras.GetBuffDataByIndex", nothing, "secret in combat; errors when tainted [W §4]" )
stub( "C_UnitAuras.GetDebuffDataByIndex", nothing, "secret in combat; errors when tainted [W §4]" )
stub( "C_UnitAuras.GetPlayerAuraBySpellID", nothing, "secret in combat; errors when tainted [W §4]" )
stub( "UnitAura", nothing, "absent on Forever" )
stub( "UnitAuraBySlot", nothing, "absent on Forever" )

-- Cooldowns and charges: times secret in combat [W §4]; stubs return shared, read-only tables (ready, one charge).
stub( "C_Spell.GetSpellCooldown", cooldown, "times secret in combat, flags plain [W PR4, PR11]" )
stub( "C_Spell.GetSpellCharges", charges, "times secret in combat [W §4 cooldowns]" )
stub( "C_Spell.GetSpellCastCount", zero, "flagged SecretWhenCooldownsRestricted; unprobed" )
stub( "C_Spell.GetSpellLossOfControlCooldown", nothing, "absent on Forever" )
passthrough( "C_LossOfControl.GetActiveLossOfControlData", "plain [W PR18]" )
passthrough( "C_LossOfControl.GetActiveLossOfControlDataCount", "plain [W PR18]" )

-- Casts: the player's own casts are plain [W PR9], other units' are secret [W PR8]; empower timings return 0.
stub( "UnitCastingInfo", playerOnly( "UnitCastingInfo" ), "player plain [W PR9]; target flagged secret [W PR8]" )
stub( "UnitChannelInfo", playerOnly( "UnitChannelInfo" ), "player plain [W PR9]; target flagged secret [W PR8]" )
stub( "GetUnitEmpowerHoldAtMaxTime", zero, "flagged secret with casts; unprobed" )
stub( "GetUnitEmpowerStageDuration", zero, "flagged secret with casts; unprobed" )
passthrough( "C_Spell.IsCurrentSpell", "plain [W PR1]" )
passthrough( "C_SpellActivationOverlay.IsSpellOverlayed", "plain [W PR11]" )

-- Combat log: CLEU is forbidden on Forever; the stub returns nil.
stub( "CombatLogGetCurrentEventInfo", nothing, "absent on Forever; registering CLEU is forbidden" )

-- Talents, specialization and borrowed powers: plain [W PR5, PR15] or unprobed; the old talent globals are dead (nil).
passthrough( "C_ClassTalents.GetActiveConfigID", "unprobed" )
passthrough( "C_ClassTalents.GetHeroTalentSpecsForClassSpec", "unprobed" )
passthrough( "C_Soulbinds.GetActiveSoulbindID", "unprobed" )
passthrough( "C_Soulbinds.GetSoulbindData", "unprobed" )
passthrough( "C_SpecializationInfo.GetPvpTalentSlotInfo", "unprobed" )
passthrough( "C_SpecializationInfo.GetSpecialization", "plain [W PR15]" )
passthrough( "C_SpecializationInfo.GetSpecializationInfo", "plain [W PR15]" )
passthrough( "C_SpecializationInfo.GetTalentInfo", "unprobed" )
passthrough( "C_Traits.GetConfigInfo", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetDefinitionInfo", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetEntryInfo", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetLoadoutSerializationVersion", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetNodeCost", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetNodeInfo", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetSubTreeInfo", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetTreeCurrencyInfo", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetTreeHash", "plain, walk identical in combat [W PR5]" )
passthrough( "C_Traits.GetTreeNodes", "plain, walk identical in combat [W PR5]" )
passthrough( "GetClassInfo", "unprobed" )
passthrough( "GetNumClasses", "unprobed" )
stub( "GetPvpTalentInfoByID", nothing, "dead on Forever [W PR5]" )
passthrough( "GetSpecializationInfoByID", "unprobed" )
stub( "GetTalentInfoByID", nothing, "dead on Forever [W PR5]" )

-- Spells and spellbook: spell data passes through; globals absent on Forever return nil or false.
passthrough( "C_Spell.GetSpellDescription", "unprobed" )
passthrough( "C_Spell.GetSpellInfo", "unprobed" )
passthrough( "C_Spell.GetSpellPowerCost", "plain [W §4]" )
passthrough( "C_Spell.GetSpellTexture", "unprobed" )
passthrough( "C_Spell.IsPressHoldReleaseSpell", "unprobed" )
passthrough( "C_Spell.IsSpellDataCached", "unprobed" )
passthrough( "C_Spell.IsSpellHarmful", "unprobed" )
passthrough( "C_Spell.IsSpellHelpful", "unprobed" )
passthrough( "C_Spell.IsSpellPassive", "unprobed" )
passthrough( "C_Spell.IsSpellUsable", "plain [W PR14; SU]" )
passthrough( "C_Spell.RequestLoadSpellData", "unprobed" )
passthrough( "C_SpellBook.FindSpellBookSlotForSpell", "unprobed" )
passthrough( "C_SpellBook.GetNumSpellBookSkillLines", "unprobed" )
passthrough( "C_SpellBook.GetSpellBookItemInfo", "unprobed" )
passthrough( "C_SpellBook.GetSpellBookSkillLineInfo", "unprobed" )
passthrough( "C_SpellBook.IsSpellInSpellBook", "unprobed" )
passthrough( "C_SpellBook.IsSpellKnown", "unprobed" )
passthrough( "C_TooltipInfo.GetConduit", "unprobed" )
passthrough( "C_TooltipInfo.GetSpellByID", "unprobed" )
stub( "GetSpellBaseCooldown", nothing, "absent on Forever" )
stub( "GetSpellLink", nothing, "absent on Forever" )
stub( "IsHarmfulSpell", isFalse, "absent on Forever" )
stub( "IsHelpfulSpell", isFalse, "absent on Forever" )
stub( "IsPassiveSpell", isFalse, "absent on Forever" )
passthrough( "IsPlayerSpell", "unprobed" )
stub( "IsPressHoldReleaseSpell", isFalse, "absent on Forever" )
passthrough( "IsSpellKnown", "unprobed" )
passthrough( "IsSpellKnownOrOverridesKnown", "unprobed" )
stub( "IsUsableSpell", isFalse, "absent on Forever" )
passthrough( "SpellIsSelfBuff", "unprobed" )

-- Items: passthroughs, plain [W PR13]; the absent globals return nil.
passthrough( "C_Item.GetDetailedItemLevelInfo", "plain [W PR13]" )
passthrough( "C_Item.GetItemCooldown", "plain [W PR13]" )
passthrough( "C_Item.GetItemCount", "plain [W PR13]" )
passthrough( "C_Item.GetItemGem", "plain [W PR13]" )
passthrough( "C_Item.GetItemInfo", "plain [W PR13]" )
passthrough( "C_Item.GetItemInfoInstant", "plain [W PR13]" )
passthrough( "C_Item.GetItemSpell", "plain [W PR13]" )
passthrough( "C_Item.IsCurrentItem", "plain [W PR13]" )
passthrough( "C_Item.IsEquippedItem", "plain [W PR13]" )
passthrough( "C_Item.IsUsableItem", "plain [W PR13]" )
passthrough( "C_TooltipInfo.GetInventoryItem", "unprobed" )
passthrough( "C_TooltipInfo.GetItemByID", "unprobed" )
passthrough( "GetInventoryItemID", "plain [W PR13]" )
stub( "GetItemGem", nothing, "absent on Forever" )
stub( "GetItemInfo", nothing, "absent on Forever" )

-- Units and identity: passthroughs, plain in combat [W PR14; gate spike] or unprobed.
passthrough( "UnitAffectingCombat", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitCanAssist", "unprobed" )
passthrough( "UnitCanAttack", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitClass", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitClassBase", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitClassification", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitCreatureType", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitEffectiveLevel", "unprobed" )
passthrough( "UnitExists", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitFactionGroup", "unprobed" )
passthrough( "UnitGUID", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitHasVehicleUI", "unprobed" )
passthrough( "UnitInParty", "unprobed" )
passthrough( "UnitInRaid", "unprobed" )
passthrough( "UnitInVehicle", "unprobed" )
passthrough( "UnitIsConnected", "unprobed" )
passthrough( "UnitIsDead", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitIsDeadOrGhost", "unprobed" )
passthrough( "UnitIsFriend", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitIsPVP", "unprobed" )
passthrough( "UnitIsPlayer", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitIsTrivial", "unprobed" )
passthrough( "UnitIsUnit", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitLevel", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitName", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitOnTaxi", "unprobed" )
passthrough( "UnitPhaseReason", "unprobed" )
passthrough( "UnitRace", "unprobed" )
passthrough( "UnitSex", "unprobed" )
passthrough( "UnitThreatSituation", "plain in combat [W PR14; gate spike]" )
passthrough( "UnitTokenFromGUID", "unprobed" )

-- Group, world and combat state: passthroughs, unprobed unless noted.
passthrough( "C_PetBattles.IsInBattle", "unprobed" )
passthrough( "C_PlayerInfo.IsPlayerInChromieTime", "unprobed" )
passthrough( "C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier", "unprobed" )
passthrough( "C_PvP.IsWarModeDesired", "unprobed" )
passthrough( "GetInstanceInfo", "unprobed" )
passthrough( "GetNumGroupMembers", "unprobed" )
passthrough( "GetNumSubgroupMembers", "unprobed" )
passthrough( "GetRealmName", "unprobed" )
passthrough( "GetStablePetInfo", "unprobed" )
passthrough( "InCombatLockdown", "plain [W §3; lags at PLAYER_REGEN_DISABLED]" )
passthrough( "IsInGroup", "unprobed" )
passthrough( "IsInInstance", "unprobed" )
passthrough( "IsInJailersTower", "unprobed" )
passthrough( "IsInRaid", "unprobed" )
passthrough( "IsMounted", "unprobed" )
passthrough( "IsResting", "unprobed" )

-- Bindings, action bars and shapeshift: passthroughs, plain [W PR10] or unprobed.
passthrough( "GetActionInfo", "plain [W PR10]" )
passthrough( "GetBindingKey", "plain [W PR10]" )
passthrough( "GetCursorInfo", "unprobed" )
passthrough( "HasOverrideActionBar", "unprobed" )
passthrough( "HasVehicleActionBar", "unprobed" )
passthrough( "GetShapeshiftForm", "plain [W §4 (stance)]" )
passthrough( "GetShapeshiftFormInfo", "plain [W PR10]" )
passthrough( "SecureCmdOptionParse", "unprobed" )

-- Client and build: passthroughs.
passthrough( "C_AddOns.GetAddOnMetadata", "unprobed" )
passthrough( "C_AddOns.IsAddOnLoaded", "unprobed" )
passthrough( "C_AddOns.LoadAddOn", "unprobed" )
passthrough( "C_ClassColor.GetClassColor", "unprobed" )
passthrough( "C_Texture.GetAtlasInfo", "unprobed" )
passthrough( "C_VideoOptions.GetCurrentGameWindowSize", "unprobed" )
passthrough( "GetBuildInfo", "unprobed" )
passthrough( "GetCVar", "unprobed" )
passthrough( "GetFrameCPUUsage", "unprobed" )
passthrough( "GetFramerate", "unprobed" )
passthrough( "GetNetStats", "unprobed" )
passthrough( "GetTime", "plain [W]" )
----------------------------------------------------------------------------------------------------

table.sort( inventory )
local stubs = {}
for _, name in ipairs( inventory ) do
    if status[ name ] ~= "passthrough" then stubs[ #stubs + 1 ] = name end
end

function lib.Status( name ) return status[ name ] end
function lib.Why( name ) return why[ name ] end
function lib.Stubs() return stubs end
function lib.Inventory() return inventory end

return lib
