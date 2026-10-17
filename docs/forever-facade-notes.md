# Forever facade notes

Status (2026-10-15, after the shared-content pass): 176 names in `tools/api_inventory.txt`: 123 passthrough, 26 hybrid, 27 virtual (counts from the facade's own summary).

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
| `C_AddOns.IsAddOnLoaded` | present | unprobed | passthrough | — | Events.lua, Targets.lua |
| `C_AddOns.LoadAddOn` | present | unprobed | passthrough | — | Targets.lua |
| `C_ClassColor.GetClassColor` | present | unprobed | passthrough | — | Options/Options.lua |
| `C_ClassTalents.GetActiveConfigID` | present | unprobed | passthrough | — | Options/DevTools.lua |
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
| `C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier` | present | unprobed | passthrough | — | Targets.lua |
| `C_PvP.IsWarModeDesired` | present | unprobed | passthrough | — | Targets.lua |
| `C_SpecializationInfo.GetSpecialization` | present | plain [W PR15] | passthrough | — | Constants.lua, State.lua, Events.lua, Classes.lua, Options/DevTools.lua, Options/Options.lua, UI.lua |
| `C_SpecializationInfo.GetSpecializationInfo` | present | plain [W PR15] | passthrough | — | Constants.lua, Events.lua, Classes.lua, Options/DevTools.lua, Options/Options.lua, UI.lua |
| `C_SpecializationInfo.GetTalentInfo` | present | unprobed | passthrough | — | Events.lua |
| `C_Spell.GetSpellCastCount` | present | flagged `SecretWhenCooldownsRestricted`; unprobed | stub | `0` | State.lua, Options/DevTools.lua |
| `C_Spell.GetSpellCharges` | present | times secret in combat [W §4 cooldowns] | stub | shared table `{ currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }` | State.lua, Options/DevTools.lua |
| `C_Spell.GetSpellCooldown` | present | times secret in combat, flags plain [W PR4, PR11] | stub | shared table `{ startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }` | State.lua, Events.lua, Options/DevTools.lua, UI.lua |
| `C_Spell.GetSpellDescription` | present | unprobed | passthrough | — | Classes.lua, Options/DevTools.lua, Options/Options.lua |
| `C_Spell.GetSpellInfo` | present | unprobed | passthrough | — | Utils.lua, Classes.lua, Options/DevTools.lua |
| `C_Spell.GetSpellLossOfControlCooldown` | absent (fallback shim only) | n/a | stub | `nil` | State.lua |
| `C_Spell.GetSpellPowerCost` | present | plain [W §4] | passthrough | — | Options/DevTools.lua |
| `C_Spell.GetSpellTexture` | present | unprobed | passthrough | — | State.lua, Classes.lua, UI.lua |
| `C_Spell.IsCurrentSpell` | present | plain [W PR1] | passthrough | — | UI.lua |
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
| `C_TooltipInfo.GetInventoryItem` | present | unprobed | passthrough | — | Utils.lua |
| `C_TooltipInfo.GetItemByID` | present | unprobed | passthrough | — | Utils.lua |
| `C_TooltipInfo.GetSpellByID` | present | unprobed | passthrough | — | Utils.lua |
| `C_Traits.GetConfigInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetDefinitionInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetEntryInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetNodeCost` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetNodeInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetSubTreeInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetTreeCurrencyInfo` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_Traits.GetTreeNodes` | present | plain, walk identical in combat [W PR5] | passthrough | — | Options/DevTools.lua |
| `C_UnitAuras.GetAuraDataByAuraInstanceID` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Events.lua |
| `C_UnitAuras.GetAuraSlots` | present | secret in combat [W §4] | stub | `nil` (no continuation token, no slots) | State.lua |
| `C_UnitAuras.GetBuffDataByIndex` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Hekili.lua, Utils.lua, State.lua |
| `C_UnitAuras.GetDebuffDataByIndex` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Hekili.lua, Utils.lua, State.lua |
| `C_UnitAuras.GetPlayerAuraBySpellID` | present | secret in combat; errors when tainted [W §4] | stub | `nil` | Utils.lua, State.lua, Events.lua, Options/DevTools.lua |
| `C_VideoOptions.GetCurrentGameWindowSize` | present | unprobed | passthrough | — | Options/Options.lua, UI.lua |
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
| `GetUnitSpeed` | present | secret in combat [W PR14] | stub | `0, 0, 0, 0` | State.lua, Targets.lua |
| `HasOverrideActionBar` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | UI.lua |
| `HasVehicleActionBar` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | UI.lua |
| `InCombatLockdown` | present (documented global) | plain [W §3; lags at PLAYER_REGEN_DISABLED] | passthrough | — | State.lua, Events.lua, Classes.lua, Targets.lua, Options/DevTools.lua, Options/ChatCommands.lua, Options/Options.lua, UI.lua, Core.lua |
| `IsActionInRange` | deprecation shim (`loadDeprecationFallbacks`) | plain [W PR7] | passthrough | — | Targets.lua |
| `IsHarmfulSpell` | absent | n/a | stub | `false` | Options/DevTools.lua |
| `IsHelpfulSpell` | absent | n/a | stub | `false` | Options/DevTools.lua |
| `IsInGroup` | undocumented C global | unprobed | passthrough | — | Utils.lua, Events.lua |
| `IsInInstance` | present | unprobed | passthrough | — | Targets.lua, UI.lua |
| `IsInJailersTower` | present | unprobed | passthrough | — | State.lua |
| `IsInRaid` | undocumented C global | unprobed | passthrough | — | Utils.lua, State.lua, Targets.lua |
| `IsMounted` | present | unprobed | passthrough | — | State.lua, UI.lua |
| `IsPassiveSpell` | absent | n/a | stub | `false` | Options/DevTools.lua |
| `IsPlayerSpell` | deprecation shim (`loadDeprecationFallbacks`) | unprobed | passthrough | — | State.lua, Events.lua, Options/DevTools.lua |
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
| `UnitPowerType` | present | plain [W PR16] | passthrough | — | State.lua |
| `UnitRace` | present | unprobed | passthrough | — | State.lua |
| `UnitSex` | present | unprobed | passthrough | — | Constants.lua |
| `UnitSpellHaste` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua, Options/DevTools.lua |
| `UnitStat` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |
| `UnitThreatSituation` | present | plain in combat [W PR14; gate spike] | passthrough | — | State.lua |
| `UnitTokenFromGUID` | present | unprobed | passthrough | — | Targets.lua |
| `UnitWeaponAttackPower` | present | secret in combat [W PR2, PR4] | stub | `0` (every return) | State.lua |

## Sweep 2026-10-16

Supersedes the "unprobed" tags in the inventory above for the 72 passthrough reads (the facade's PASSTHROUGH table now
carries the sweep tags).

- Method: the ForeverProbe `/vsprobe sweep` command called every read tagged "unprobed" once out of combat and once in
  combat at a dummy (Undead Warrior, Forever 1.60.1), recording per return value secret / plain type / nil.
- Verdict: 71 called (`C_AddOns.LoadAddOn` skipped as state-changing, assumed plain), none returned a secret in either
  run, and oc = ic apart from argument-dependent answers (`UnitFactionGroup`, `UnitSex`, `UnitTokenFromGUID` on a
  creature target). `GetStablePetInfo` is missing on Forever.
- Caveat: table returns (`GetClassColor`, `C_Spell.GetSpellInfo`, `GetSpellBookItemInfo`, `GetSpellBookSkillLineInfo`,
  `GetAtlasInfo`, the three `C_TooltipInfo` reads, `GetCurrentGameWindowSize`) were checked as tables only; their
  fields are unverified.
- `UnitHealthMax("target")` is secret out of combat and in combat (`C_Secrets.ShouldUnitHealthMaxBeSecret("target")`
  = true): the max is secret always on other units, so the target-health design's plain-max branch (§2.3b) is closed.

## Secrecy zone (bodies unchanged in Phase 2; Phase 3b revisits them)

Line ranges are as of the post-cleanup sweep (Task 20).

| Code | Where | What it reads through the facade |
|---|---|---|
| cooldown metatable | `State.lua` 2905-3119 (`GetUnpackedSpellCooldown`, `mt_default_cooldown`) | `C_Spell.GetSpellCooldown`, `GetSpellCharges`, `GetSpellLossOfControlCooldown` |
| `ScrapeUnitAuras` | `State.lua` 5353-5567 (`function state.ScrapeUnitAuras`); slot reader `StoreMatchingAuras` 5281-5350 | `C_UnitAuras.Get{Buff,Debuff}DataByIndex`, `UnitAuraBySlot`, `UnitIsUnit` |
| `state.reset` | `State.lua` 6178-6476 (`function state.reset`) | `UnitPower`, `UnitPowerMax`, `GetManaRegen`, `GetPowerRegenForPowerType`, `UnitHealth`, `UnitHealthMax`, `UnitAttackSpeed`, `GetTotemInfo`, `UnitCastingInfo` |
| `UNIT_POWER_FREQUENT` handler | `Events.lua` 1174-1211 | `UnitPower` |
| `UNIT_AURA` handler | `Events.lua` 1254-1324 | `AuraUtil.ForEachAura`, `C_UnitAuras.GetAuraDataByAuraInstanceID` |
| combat-log handler | `Events.lua` 1460-1767 (`CLEU_HANDLER` and its registration on 1767) | `CombatLogGetCurrentEventInfo`, `UnitAttackSpeed` |
| target counting | `Targets.lua` 395-667 (`ns.getNumberTargets`) | `UnitHealth`, `UnitGUID`, `GetUnitSpeed`, `GetHaste` |
| time to die | `Targets.lua` 1164-1605 (`EliminateEnemy`, `UpdateEnemy`, `GetTTD`, `GetTimeToPct`, `UpdateTTDs`) | `UnitHealth`, `UnitHealthMax`, `UnitGetTotalAbsorbs` |
| UI cooldown arithmetic | `UI.lua` 1107-1663 (`d:OnUpdate`) and 1693-1740 (`d:RefreshCooldowns`) | `C_Spell.GetSpellCooldown`, `UnitCastingInfo`, `UnitChannelInfo` |
| spec detection | `Classes.lua` 3077-3362 (`Hekili:SpecializationChanged`) | `C_SpecializationInfo.*` |

## Stub call sites that would throw or misbehave (for Phase 3b; not patched here)

Every stub site in the retained files that throws or yields a wrong value. Sites that read a stub and stay correct
(nil-guarded, `or` defaults) are left out.

| Stub | Call site | Effect |
|---|---|---|
| `CombatLogGetCurrentEventInfo` -> nil | `Events.lua` 1767 `CLEU_HANDLER( event, CombatLogGetCurrentEventInfo() )` | **throws** in combat if the event ever fires: every argument is nil, the out-of-combat early return (1494) is skipped, and `bit.band( destFlags, ... )` (1510) gets nil. Registering CLEU itself is forbidden on Forever; removing or diverting the registration is the real fix |
| `CombatLogGetCurrentEventInfo` -> nil | `Options/DevTools.lua` 458 `SkeletonCLEU( CombatLogGetCurrentEventInfo() )` | safe: `sourceName` nil returns at 339 |
| `GetTalentInfoByID` -> nil | `Events.lua` 431-435, `ns.updateTalents`: `name` nil falls back to `IsPlayerSpell( v )` where `v` is a `RegisterTalents` entry (a table) | probably **throws** (`IsPlayerSpell` given a table); unverified on the client. Either way talents come out wrong until the `C_Traits` walk replaces this loop |
| `UnitAttackSpeed` -> `2, nil` | `State.lua` 192 and 6356, `Events.lua` 816 and 1695, `Classes.lua` 3357 | wrong value: main-hand speed is a constant 2.0, so swing projections (`swings.mh_*`) are fiction. `oh_speed` nil is guarded at State.lua 195/5132/6358 and Events.lua 1688/1690 |
| `UnitAttackSpeed` -> `2, nil` | `State.lua` 2310 `stat.weapon_speed` | wrong value: 2.0 / 0 |
| `GetPowerRegenForPowerType` -> `0, 0` | `State.lua` 6310 in `state.reset`, feeding `forecastResources` | wrong value: `active or 0.001` keeps the 0 (0 is truthy), so regen is 0, every resource forecast is flat, and `time_to_x` returns 3600 or the next modeled slice (`State.lua` 3391 divides by 0 to `inf` but the comparison that follows still picks `after.t`). Assassination's timeout `energy.max / max( 0.001, regen )` (1192) becomes 100000 s, bounded by the 30-iteration cap |
| `GetManaRegen` -> `0, 0` | `State.lua` 6303 | wrong value: mana never regenerates in the forecast |
| `UnitPower` -> 0 | `State.lua` 6290 `res.actual`; `Events.lua` 1174-1208 | wrong value: every resource reads 0, so nothing with a cost is ever recommended. The single largest behavioural gap |
| `C_UnitAuras.GetAuraSlots` -> nil | `State.lua` 456 `state.UnitAuraSlots` | no retained consumer; spec code calling `UnitAuraSlots` would get no slots |
| `GetTotemInfo` -> `false, "", 0, 0, 0` | `State.lua` 2389 (totem pets), 4093 (`mt_default_totem.expires`), 4128-4149 (`mt_totem` fire/earth/water/air), 6261 (`summonPet` from totems) | wrong value: `spellID` and `modRate` are nil (`class.abilities[ nil ]` reads nil, no throw), every totem and totem-backed pet is down |
| `UnitCastingInfo` / `UnitChannelInfo` ("target") -> nil | `Classes.lua` 1646 and 1677, the `casting` aura generator for `unit == "target"` | wrong value: `debuff.casting` is never up on the target, so interrupt recommendations never fire. Player casts pass through |
| `UnitHealth` / `UnitHealthMax` -> 0 | `Targets.lua` 434 and 511 enemy scan `UnitHealth( unit ) > 1` | wrong value: every nameplate is filtered out unless it is a training dummy, so `active_enemies` stays at 1 |
| `UnitHealth` / `UnitHealthMax` -> 0 | `Targets.lua` 1600 `UpdateEnemy( guid, health / healthMax, ... )` (1583-1587 clamps `healthMax` to 1, 1600 does not) | wrong value: `0 / 0` is NaN, NaN comparisons are false, `rate` stays 0, and TTD stays at its default |
| `UnitHealth` / `UnitHealthMax` -> 0 | `Targets.lua` 1304-1312 (`GetTTD`) and 1328-1340 (`GetTimeToPct`) | wrong value: NaN `healthPct`; the `enemy.n < 3` early return hides it, so callers get the default |
| `UnitHealth` / `UnitHealthMax` -> 0 | `State.lua` 2860-2866 `mt_target_health` | wrong value: `target.health.pct` is 100 (the `t.max ~= 0` guard), so execute-phase conditions never pass |
| `UnitHealth( "target" )` -> the TargetHealth belief x 100 | `State.lua` 2860-2866 `mt_target_health` | follows VirtualState's target health (Families/TargetHealth.lua: a pin at a health gate, then a plain WOUND slope); 100 until a pin |
| `UnitHealth` / `UnitHealthMax` -> 0 | `State.lua` 1866-1893 `group_health`, `at_risk`; 2562 pet `health_pct`; `Utils.lua` 416-462 | wrong value: `0 / 0` NaN percentages, every `<` test false |
| `UnitHealth` -> 0 | `State.lua` 2424, 2556 pet alive checks `UnitHealth( "pet" ) > 0` | wrong value: the pet always reads dead |
| `UnitHealth` -> 0 | `State.lua` 6351-6352 `state.health` | wrong value: player health 0 of max 1 |
| `IsUsableSpell` -> false | `State.lua` 6966 `usable` check for a numeric `usable` | wrong value: such abilities are never usable (port to `C_Spell.IsSpellUsable`) |
| `GetUnitSpeed` -> 0 | `State.lua` 1861, 2793; `Targets.lua` 492, 558, 622, 642 | wrong value: nothing is ever moving |
| `UnitInRange` -> `false, true` | `State.lua` 1850 | wrong value: no group member is in range |
| `C_Spell.GetSpellCooldown`, `GetSpellCharges`, `GetSpellLossOfControlCooldown` | `State.lua` 2905-3011 | wrong value only: every spell is off cooldown with 1/1 charges; the loss-of-control nil is guarded |
| stat stubs (`UnitStat`, `GetCombatRating*`, `GetMasteryEffect`, crit, haste, `UnitDamage`, `UnitArmor`, attack power) | `State.lua` 2236-2356, `Targets.lua` 816 | wrong value: 0 everywhere; haste 0 gives a factor of 1, so no division by zero |

## Edits no facade absorbs (feasibility doc C.5)

- GCD spell 61304 -> 29515: `Classes.lua` 2469 (`id = 61304`), `UI.lua` 1493 and 1694, `Events.lua` 1675.
- The GCD by kind (core edit E10, `State.lua` `mt_gcd`, `execute`): stock gives every spell-kind press made with
  energy as the power type 1.0 s; E10 drops that clause from `execute` only, so such a press (a form or a spell cast
  from an energy form) keeps 1.5 s x haste as the DB2 says (checkpoint G1), and a 1 s ability declares
  `gcd = "totem"` as before. `max`/`duration` (no ability context: `gcd.max` in cycle and time-to expressions) keep
  the stock clause, the typical 1 s GCD in energy. VirtualState's belief prices each GCD by the same kinds
  (`Families/Casts.lua`, `I.GcdLen`; GCD kinds design §1.2). Revert: restore the one `if` line.
- The enemy-scan health comparison: `Targets.lua` 434 and 511.
- TTD: `Targets.lua` 1164-1605 needs another source of health deltas.
- Spec identity (pseudo-spec 1491): `Classes.lua` 3077-3362 `SpecializationChanged`. `NewSpecialization` now takes
  identity from the `ns.Specializations[ 1491 ].forever` row (Task 11b); what remains:
  - `Classes.lua` 3135-3138: Forever returns id `0` (truthy) for spec slots 2 and 3, so the loop does not break and
    `specs` holds `0` several times; `all` is merged repeatedly and its hooks (`reset_precast`, 3242) run 2-3 times per
    reset. Wrong cost, no error (the hook is idempotent). Fix: `if not id or id == 0 then break end`.
  - `Classes.lua` 3148-3164: `role` and `primaryStat` from `GetSpecializationInfo( 1 )` are unprobed on Forever; if nil,
    `state.role.healer` and `state.spec.primaryStat = "intellect"` are set for a Warrior. Wrong data, no error.
- Talents: replace `ns.updateTalents` (`Events.lua` 423) with a `C_Traits` walk (`Options/DevTools.lua` already walks the tree).
- CLEU: `ns.RegisterEvent` now skips the frame registration for `COMBAT_LOG_EVENT_UNFILTERED` (the handler stays
  registered at `Events.lua` 1767); Phase 3b supplies the virtual combat log to it. `Options/DevTools.lua` 1156 still
  registers it on its own listener frame.
- Version gates: `Hekili.lua` 18-56 (`IsDragonflight`, `IsTWW`, `IsMidnight` and `ns.PTR` are false on build 16001;
  `BuiltFor = 110200`) and `Core.lua` 205 (`BuiltFor > CurrentBuild` reports Hekili as built for a newer client).
- Division-by-zero audit: the NaN and `inf` sites in the table above.
- Load-time nils: the stubs above cover reads; globals the facade does not list stay a Phase 3b audit.

## Periodic auras

- A periodic aura's ticks land in full, the one at its expiry too (Bloodrage: 10 ticks of 1 rage over 10 s). VirtualState's `auraGain` counts through the expiry; Hekili's forecast keeps its own `expires < e.next` (the 2026-10-16 core edit E6 is reverted).
- Out-of-combat decay is stepped and front-loaded (`docs/superpowers/specs/2026-10-16-stepped-decay-design.md`): a class's meta table declares `decay` (per second) and `decayInterval` (seconds, a function: Engine/Schema/Spec.lua setfenv's every meta field). The quantum `decay x decayInterval` is lost at once when the decay starts (combat end, the last tick aura's expiry, a rise above rest) and at the start of each interval after it; a tick and a quantum at the same instant resolve tick first (Bloodrage, then Battle Shout, out of combat: the bar ends the buff at 10 - 1.25 = 8.75, shown 9). Without `decayInterval` a decay stays continuous.
- The sim: the Adapter generates a regen-model entry `__decay` (`value` -quantum every `decayInterval`) whose beats are the belief's (`VS.DecayAnchor`), or start at a tick aura's expiry while one is up in the sim; `stop` in combat only, because Hekili's forecast removes a stopped entry for the rest of the forecast.
- Hekili's forecast counted aura-gated regen entries twice (2026-10-16, Warrior out of combat with Bloodrage up: rage forecast climbed ~2/s): once as tick events and again inside `regen_combined`, its continuous rate. Core edit E7 (`forecastResources`) uses plain `r.regen`, so those entries count through their events only; `regen_combined` itself is unchanged.
- The forecast window (core edit E9, Core.lua `defaultMax` and State.lua's forecast `timeout`) is one global option, `Hekili.DB.profile.performance.forecastWindow` (default 15 s), under Options > Performance > Forecast; not a per-spec setting.

## Known reads outside the inventory

- `Libs/LibSpellRange-1.0` calls `C_Spell.IsSpellInRange` directly (Libs are excluded from tools/check_api_reads.sh); probed plain OUT of combat (2026-10-15, Charge 100 → true/false); in combat unprobed. `action.<key>.in_range` (State.lua ~5070) reads it through `ability.rangeSpell or ability.id`: for a RANKED spell `ability.id` is rank 1, the client answers nil for an unknown rank, and Hekili treats nil as "in range". Only single-rank abilities (Charge) or ones with `rangeSpell` set to the known rank get a real answer.
- `LibRangeCheck-3.0:GetRange("target")` answers `100, nil` on Forever (2026-10-15, one sample contradicted by CheckInteractDistance): `target.minR/maxR/distance` and the `within`/`outside` conditions are unusable; no pack reads them.
