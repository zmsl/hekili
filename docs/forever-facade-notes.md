# Forever facade notes

Working notes for Phase 2 (the VirtualGameAPI-1.0 skeleton) and the hand-off to Phases 1 and 3b.

## Inventory

Every game API name a loaded Hekili file reads, with its Forever status. `tools/api_inventory.txt` is
the machine-readable copy; `tools/list_api_reads.sh` regenerates the candidate list.

Sources: Forever presence from `wow_api_search` (flavor `forever`), with Forever FrameXML for names the API docs do
not list (undocumented C globals, FrameXML Lua, deprecation shims). Secrecy tags: [W PRn] probe session W,
[W §4] its secrecy model, [SU] the swing/usable probe, "gate spike" the 2026-10 gate spike. "unprobed" means present
on Forever with no measured secrecy; such reads pass through (a secret result would reach Hekili only in combat, Phase 1
work). Deprecation shims exist only when the CVar `loadDeprecationFallbacks` is on; the library's `missing` fallback
covers them being nil, and Phase 3b ports them to `C_SpellBook.IsSpellKnown` and `C_ActionBar.*`.

| Name | Forever | Secrecy | Status | Stub returns | Hekili call sites |
|---|---|---|---|---|---|
| `AuraUtil.FindAura` | present (FrameXML Lua) | wraps secret aura data [W §4] | stub | `nil` | Utils.lua |
| `AuraUtil.ForEachAura` | present (FrameXML Lua) | wraps secret aura data [W §4] | stub | no-op, returns nothing | Hekili.lua, Events.lua |
| `AuraUtil.UnpackAuraData` | present (FrameXML Lua) | pure Lua unpack of a table | passthrough | — | Hekili.lua, Utils.lua, State.lua |
| `C_AddOns.GetAddOnMetadata` | present | unprobed | passthrough | — | Hekili.lua |
| `C_AddOns.IsAddOnLoaded` | present | unprobed | passthrough | — | Utils.lua, Events.lua, Targets.lua |
| `C_AddOns.LoadAddOn` | present | unprobed | passthrough | — | Targets.lua |
| `C_AzeriteEmpoweredItem.GetAllTierInfo` | present | unprobed | passthrough | — | Events.lua |
| `C_AzeriteEmpoweredItem.GetPowerInfo` | present | unprobed | passthrough | — | Events.lua |
| `C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItemByID` | present | unprobed | passthrough | — | Events.lua |
| `C_AzeriteEmpoweredItem.IsPowerSelected` | present | unprobed | passthrough | — | Events.lua |
| `C_AzeriteEssence.GetEssenceInfo` | present | unprobed | passthrough | — | Events.lua |
| `C_AzeriteEssence.GetMilestoneEssence` | present | unprobed | passthrough | — | Events.lua |
| `C_AzeriteItem.FindActiveAzeriteItem` | present | unprobed | passthrough | — | State.lua |
| `C_AzeriteItem.IsAzeriteItemEnabled` | present | unprobed | passthrough | — | State.lua |
| `C_ClassColor.GetClassColor` | present | unprobed | passthrough | — | Options/Options.lua |
| `C_ClassTalents.GetActiveConfigID` | present | unprobed | passthrough | — | Utils.lua, Options/DevTools.lua |
| `C_ClassTalents.GetActiveHeroTalentSpec` | present | unprobed | passthrough | — | Constants.lua |
| `C_ClassTalents.GetHeroTalentSpecsForClassSpec` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_Item.GetDetailedItemLevelInfo` | present | plain [W PR13] | passthrough | — | Events.lua |
| `C_Item.GetItemCooldown` | present | plain [W PR13] | passthrough | — | State.lua, Classes.lua, UI.lua |
| `C_Item.GetItemCount` | present | plain [W PR13] | passthrough | — | State.lua, Classes.lua |
| `C_Item.GetItemGem` | present | plain [W PR13] | passthrough | — | Events.lua |
| `C_Item.GetItemInfo` | present | plain [W PR13] | passthrough | — | Utils.lua, Events.lua, Classes.lua |
| `C_Item.GetItemInfoInstant` | present | plain [W PR13] | passthrough | — | UI.lua |
| `C_Item.GetItemSpell` | present | plain [W PR13] | passthrough | — | State.lua, Events.lua, Classes.lua |
| `C_Item.IsCurrentItem` | present | plain [W PR13] | passthrough | — | UI.lua |
| `C_Item.IsEquippedItem` | present | plain [W PR13] | passthrough | — | Events.lua |
| `C_Item.IsUsableItem` | present | plain [W PR13] | passthrough | — | State.lua, Events.lua, Classes.lua, UI.lua |
| `C_LossOfControl.GetActiveLossOfControlData` | present | plain [W PR18] | passthrough | — | State.lua, Classes.lua |
| `C_LossOfControl.GetActiveLossOfControlDataCount` | present | plain [W PR18] | passthrough | — | State.lua, Classes.lua |
| `C_PetBattles.IsInBattle` | undocumented C global | unprobed | passthrough | — | UI.lua |
| `C_PlayerInfo.IsPlayerInChromieTime` | present | unprobed | passthrough | — | Targets.lua |
| `C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier` | present | unprobed | passthrough | — | Targets.lua |
| `C_PvP.IsWarModeDesired` | present | unprobed | passthrough | — | Targets.lua |
| `C_Soulbinds.GetActiveSoulbindID` | present | unprobed | passthrough | — | Options/Options.lua |
| `C_Soulbinds.GetSoulbindData` | present | unprobed | passthrough | — | Options/Options.lua |
| `C_SpecializationInfo.GetPvpTalentSlotInfo` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_SpecializationInfo.GetSpecialization` | present | plain [W PR15] | passthrough | — | Constants.lua, State.lua, Events.lua, Classes.lua, Options/DevTools.lua, Options/Options.lua, UI.lua |
| `C_SpecializationInfo.GetSpecializationInfo` | present | plain [W PR15] | passthrough | — | Constants.lua, Events.lua, Classes.lua, Options/DevTools.lua, Options/Options.lua, UI.lua |
| `C_SpecializationInfo.GetTalentInfo` | present | unprobed | passthrough | — | Events.lua |
| `C_Spell.GetSpellCastCount` | present | flagged `SecretWhenCooldownsRestricted`; unprobed | stub | `0` | State.lua, Options/DevTools.lua |
| `C_Spell.GetSpellCharges` | present | times secret in combat [W §4 cooldowns] | stub | shared table `{ currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }` | State.lua, Options/DevTools.lua |
| `C_Spell.GetSpellCooldown` | present | times secret in combat, flags plain [W PR4, PR11] | stub | shared table `{ startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }` | State.lua, Events.lua, Options/DevTools.lua, UI.lua |
| `C_Spell.GetSpellDescription` | present | unprobed | passthrough | — | Classes.lua, Options/DevTools.lua, Options/Options.lua |
| `C_Spell.GetSpellInfo` | present | unprobed | passthrough | — | Utils.lua, Classes.lua, Options/DevTools.lua |
| `C_Spell.GetSpellLink` | present | unprobed | passthrough | — | Classes.lua |
| `C_Spell.GetSpellLossOfControlCooldown` | absent (fallback shim only) | n/a | stub | `nil, nil` | State.lua |
| `C_Spell.GetSpellPowerCost` | present | plain [W §4] | passthrough | — | Options/DevTools.lua |
| `C_Spell.GetSpellTexture` | present | unprobed | passthrough | — | State.lua, Classes.lua, UI.lua |
| `C_Spell.IsCurrentSpell` | present | plain [W PR1] | passthrough | — | UI.lua |
| `C_Spell.IsPressHoldReleaseSpell` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_Spell.IsSpellDataCached` | present | unprobed | passthrough | — | Events.lua |
| `C_Spell.IsSpellHarmful` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_Spell.IsSpellHelpful` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_Spell.IsSpellPassive` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_Spell.IsSpellUsable` | present | plain [W PR14; SU] | passthrough | — | State.lua, UI.lua |
| `C_Spell.RequestLoadSpellData` | present | unprobed | passthrough | — | Events.lua |
| `C_SpellActivationOverlay.IsSpellOverlayed` | present | plain [W PR11] | passthrough | — | Options/DevTools.lua, UI.lua |
| `C_SpellBook.FindSpellBookSlotForSpell` | present | unprobed | passthrough | — | Utils.lua |
| `C_SpellBook.GetNumSpellBookSkillLines` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_SpellBook.GetSpellBookItemInfo` | present | unprobed | passthrough | — | Utils.lua, Options/DevTools.lua |
| `C_SpellBook.GetSpellBookSkillLineInfo` | present | unprobed | passthrough | — | Options/DevTools.lua |
| `C_SpellBook.IsSpellInSpellBook` | present | unprobed | passthrough | — | State.lua, Options/DevTools.lua |
| `C_SpellBook.IsSpellKnown` | present | unprobed | passthrough | — | State.lua |
| `C_Texture.GetAtlasInfo` | present | unprobed | passthrough | — | Utils.lua |
| `C_TooltipInfo.GetConduit` | present | unprobed | passthrough | — | Utils.lua |
| `C_TooltipInfo.GetInventoryItem` | present | unprobed | passthrough | — | Utils.lua |
| `C_TooltipInfo.GetItemByID` | present | unprobed | passthrough | — | Utils.lua |
| `C_TooltipInfo.GetSpellByID` | present | unprobed | passthrough | — | Utils.lua |
| `C_Traits.GetConfigInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Utils.lua, Options/DevTools.lua |
| `C_Traits.GetDefinitionInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetEntryInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetLoadoutSerializationVersion` | present | plain, walk identical in combat [W PR5] | passthrough | — | Utils.lua |
| `C_Traits.GetNodeCost` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetNodeInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Utils.lua, Options/DevTools.lua |
| `C_Traits.GetSubTreeInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetTreeCurrencyInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetTreeHash` | present | plain, walk identical in combat [W PR5] | passthrough | — | Utils.lua |
| `C_Traits.GetTreeNodes` | present | plain, walk identical in combat [W PR5] | passthrough | — | Utils.lua, Options/DevTools.lua |
| `C_UnitAuras.GetAuraDataByAuraInstanceID` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Events.lua |
| `C_UnitAuras.GetAuraSlots` | present | secret in combat [W §4] | stub | `nil` (no continuation token, no slots) | State.lua |
| `C_UnitAuras.GetBuffDataByIndex` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Hekili.lua, Utils.lua, State.lua |
| `C_UnitAuras.GetDebuffDataByIndex` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Hekili.lua, Utils.lua, State.lua |
| `C_UnitAuras.GetPlayerAuraBySpellID` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Utils.lua, State.lua, Events.lua, Options/DevTools.lua |
| `C_VideoOptions.GetCurrentGameWindowSize` | present | unprobed | passthrough | — | UI.lua |
| `CombatLogGetCurrentEventInfo` | absent (shim targets `C_CombatLog.GetCurrentEventInfo`, absent) | n/a; registering CLEU is forbidden | stub | `nil` | Events.lua, Options/DevTools.lua |
| `GetActionInfo` | undocumented C global | plain [W PR10] | passthrough | — | Events.lua, Targets.lua |
| `GetBindingKey` | undocumented C global | plain [W PR10] | passthrough | — | Events.lua, Options/Options.lua |
| `GetBuildInfo` | present | unprobed | passthrough | — | Hekili.lua, Options/DevTools.lua |
| `GetCVar` | present (FrameXML Lua) | unprobed | passthrough | — | Targets.lua, Options/Options.lua |
| `GetClassInfo` | undocumented C global | unprobed | passthrough | — | Constants.lua |
| `GetCombatRating` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetCombatRatingBonus` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetCritChance` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetCursorInfo` | present | unprobed | passthrough | — | MultilineEditor.lua |
| `GetFrameCPUUsage` | present | unprobed | passthrough | — | Core.lua |
| `GetFramerate` | present | unprobed | passthrough | — | Hekili.lua, Options/Options.lua, UI.lua |
| `GetHaste` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | Targets.lua |
| `GetInstanceInfo` | present | unprobed | passthrough | — | State.lua, Events.lua |
| `GetInventoryItemID` | undocumented C global | plain [W PR13] | passthrough | — | State.lua, Events.lua |
| `GetItemGem` | absent | n/a | stub | `nil` | State.lua |
| `GetItemInfo` | absent | n/a | stub | `nil` | State.lua |
| `GetManaRegen` | present | secret in combat [W PR16] | stub | `0, 0` | State.lua |
| `GetMasteryEffect` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetMeleeHaste` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetNetStats` | present | unprobed | passthrough | — | State.lua |
| `GetNumClasses` | undocumented C global | unprobed | passthrough | — | Constants.lua |
| `GetNumGroupMembers` | undocumented C global | unprobed | passthrough | — | Utils.lua, State.lua, Targets.lua |
| `GetNumSubgroupMembers` | undocumented C global | unprobed | passthrough | — | Utils.lua |
| `GetPowerRegenForPowerType` | present | secret in combat [W PR16] | stub | `0, 0` | State.lua |
| `GetPvpTalentInfoByID` | undocumented C global | dead on Forever [W PR5] | stub | `nil` | Events.lua, Options/DevTools.lua |
| `GetRangedCritChance` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetRealmName` | present | unprobed | passthrough | — | Options/Options.lua |
| `GetShapeshiftForm` | undocumented C global | plain [W §4 (stance)] | passthrough | — | State.lua |
| `GetShapeshiftFormInfo` | undocumented C global | plain [W PR10] | passthrough | — | State.lua |
| `GetSpecializationInfoByID` | undocumented C global | unprobed | passthrough | — | Classes.lua, Options/Options.lua |
| `GetSpellBaseCooldown` | absent | n/a | stub | `nil` | Options/DevTools.lua |
| `GetSpellBonusDamage` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetSpellCritChance` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `GetSpellLink` | absent | n/a | stub | `nil` | State.lua |
| `GetStablePetInfo` | undocumented C global | unprobed | passthrough | — | State.lua |
| `GetTalentInfoByID` | absent | dead on Forever [W PR5] | stub | `nil` | Events.lua |
| `GetTime` | present | plain [W] | passthrough | — | Hekili.lua, Utils.lua, State.lua, Events.lua, Classes.lua, Targets.lua, Options/DevTools.lua, UI.lua, Core.lua |
| `GetTotemInfo` | present | secret in combat [W PR12] | stub | `false, "", 0, 0, 0` | State.lua |
| `GetUnitEmpowerHoldAtMaxTime` | present | flagged secret with casts; unprobed | stub | `0` | Events.lua |
| `GetUnitEmpowerStageDuration` | present | flagged secret with casts; unprobed | stub | `0` | Events.lua |
| `GetUnitSpeed` | present | secret in combat [W PR14] | stub | `0, 0, 0, 0` | State.lua, Targets.lua |
| `HasOverrideActionBar` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | UI.lua |
| `HasVehicleActionBar` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | UI.lua |
| `InCombatLockdown` | present (documented global) | plain [W §3; lags at PLAYER_REGEN_DISABLED] | passthrough | — | State.lua, Events.lua, Classes.lua, Targets.lua, Options/DevTools.lua, Options/ChatCommands.lua, Options/Options.lua, UI.lua, Core.lua |
| `IsActionInRange` | deprecation shim (`loadDeprecationFallbacks`) | plain [W PR7] | passthrough | — | Targets.lua |
| `IsHarmfulSpell` | absent | n/a | stub | `false` | Options/DevTools.lua |
| `IsHelpfulSpell` | absent | n/a | stub | `false` | Options/DevTools.lua |
| `IsInGroup` | undocumented C global | unprobed | passthrough | — | Utils.lua, Events.lua |
| `IsInInstance` | present | unprobed | passthrough | — | Targets.lua, UI.lua |
| `IsInJailersTower` | present | unprobed | passthrough | — | State.lua, Events.lua |
| `IsInRaid` | undocumented C global | unprobed | passthrough | — | Utils.lua, State.lua, Targets.lua |
| `IsMounted` | present | unprobed | passthrough | — | State.lua, UI.lua |
| `IsPassiveSpell` | absent | n/a | stub | `false` | Options/DevTools.lua |
| `IsPlayerSpell` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | State.lua, Events.lua, Options/DevTools.lua |
| `IsPressHoldReleaseSpell` | absent | n/a | stub | `false` | Options/DevTools.lua |
| `IsResting` | present | unprobed | passthrough | — | Events.lua |
| `IsSpellKnown` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | State.lua |
| `IsSpellKnownOrOverridesKnown` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | State.lua |
| `IsUsableSpell` | absent | n/a | stub | `false` | State.lua |
| `SecureCmdOptionParse` | undocumented C global | unprobed | passthrough | — | Events.lua |
| `SpellIsSelfBuff` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | Events.lua |
| `UnitAffectingCombat` | present | plain in combat [W PR14; gate spike] | passthrough | — | Targets.lua |
| `UnitArmor` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `UnitAttackPower` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `UnitAttackSpeed` | present | secret in combat [SU PR2] | stub | `2, nil` (keeps `UnitAttackSpeed("player") > 0` at load true) | State.lua, Events.lua, Classes.lua |
| `UnitAura` | absent | n/a | stub | `nil` | State.lua |
| `UnitAuraBySlot` | absent | n/a | stub | `nil` | State.lua |
| `UnitCanAssist` | present | unprobed | passthrough | — | State.lua |
| `UnitCanAttack` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Classes.lua, Targets.lua, Options/DevTools.lua, UI.lua |
| `UnitCastingInfo` | present | player plain [W PR9]; target flagged secret [W PR8] | stub | the real call when `unit == "player"`, else `nil` | State.lua, Events.lua, Classes.lua, UI.lua |
| `UnitChannelInfo` | present | player plain [W PR9]; target flagged secret [W PR8] | stub | the real call when `unit == "player"`, else `nil` | State.lua, Events.lua, Classes.lua, UI.lua |
| `UnitClass` | present | plain in combat [W PR14; gate spike] | passthrough | — | Events.lua, Options/DevTools.lua, Options/Options.lua, UI.lua |
| `UnitClassBase` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Classes.lua, Targets.lua, Options/DevTools.lua |
| `UnitClassification` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua |
| `UnitCreatureType` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua |
| `UnitDamage` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `UnitEffectiveLevel` | present | unprobed | passthrough | — | State.lua, Options/Options.lua |
| `UnitExists` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Events.lua, Targets.lua, UI.lua |
| `UnitFactionGroup` | present | unprobed | passthrough | — | State.lua |
| `UnitGUID` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Events.lua, Classes.lua, Targets.lua |
| `UnitGetTotalAbsorbs` | present | target secret always [W PR14]; player unprobed | stub | `0` | State.lua, Classes.lua, Targets.lua |
| `UnitHasVehicleUI` | present | unprobed | passthrough | — | UI.lua |
| `UnitHealth` | present | target secret always [W PR14]; player unprobed | stub | `0` | Utils.lua, State.lua, Targets.lua |
| `UnitHealthMax` | present | target secret always [W PR14]; player unprobed | stub | `0` | Utils.lua, State.lua, Targets.lua |
| `UnitInParty` | present | unprobed | passthrough | — | State.lua, Events.lua, Targets.lua |
| `UnitInRaid` | present | unprobed | passthrough | — | State.lua, Events.lua, Targets.lua |
| `UnitInRange` | present | secret always [W PR7] | stub | `false, true` | State.lua |
| `UnitInVehicle` | present | unprobed | passthrough | — | State.lua |
| `UnitIsConnected` | present | unprobed | passthrough | — | State.lua |
| `UnitIsDead` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Targets.lua, UI.lua |
| `UnitIsDeadOrGhost` | present | unprobed | passthrough | — | State.lua |
| `UnitIsFriend` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Targets.lua |
| `UnitIsPVP` | present | unprobed | passthrough | — | Targets.lua |
| `UnitIsPlayer` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Events.lua, Targets.lua |
| `UnitIsTrivial` | present | unprobed | passthrough | — | Targets.lua |
| `UnitIsUnit` | present | plain in combat [W PR14; gate spike] | passthrough | — | Utils.lua, State.lua, Targets.lua, Options/DevTools.lua |
| `UnitLevel` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua, Events.lua, Targets.lua, Options/Options.lua |
| `UnitName` | present | plain in combat [W PR14; gate spike] | passthrough | — | Utils.lua, State.lua, Events.lua, Targets.lua, Options/Options.lua |
| `UnitOnTaxi` | present | unprobed | passthrough | — | UI.lua |
| `UnitPartialPower` | present | secret always [W PR16] | stub | `0` | State.lua |
| `UnitPhaseReason` | present | unprobed | passthrough | — | Targets.lua |
| `UnitPower` | present | secret always [W PR16] | stub | `0` | State.lua, Events.lua |
| `UnitPowerMax` | present | plain (100 for rage) [W PR16] | passthrough | — | State.lua, Options/DevTools.lua |
| `UnitPowerType` | present | plain (100 for rage) [W PR16] | passthrough | — | State.lua |
| `UnitRace` | present | unprobed | passthrough | — | State.lua |
| `UnitSex` | present | unprobed | passthrough | — | Constants.lua |
| `UnitSpellHaste` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua, Options/DevTools.lua |
| `UnitStat` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `UnitThreatSituation` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua |
| `UnitTokenFromGUID` | present | unprobed | passthrough | — | Targets.lua |
| `UnitWeaponAttackPower` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
