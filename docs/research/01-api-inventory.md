# R1 — Hekili game-API inventory vs. WoW Forever (1.60.1.70338)

Scope: every WoW API function and event called from the core `.lua` files (`Classes Constants Core Events Formatting Hekili MultilineEditor Scripts State Targets UI Utils`), `Options/*.lua`, `UI/PopupSlider.lua`, and one spec file, `TheWarWithin/DruidFeral.lua`. `Libs/` is not covered. Branch `research/forever-revival`, HEAD `36daec38`.

## Summary

- **Inventory size:** 84 distinct `C_*.*` functions, 78 documented global functions, 22 C-side globals with no documentation, about 70 FrameXML/Lua-defined globals, and 99 event names (around 85 real `RegisterEvent` targets, plus CLEU subevent strings and a few events that are listed but commented out).
- **Missing:** only **3 functions are confirmed missing** on Forever.
  - `CombatLogGetCurrentEventInfo`. The deprecation shim points at `C_CombatLog.GetCurrentEventInfo`, which does not exist in mainline or Forever docs. Only classic has it.
  - `C_Spell.GetSpellLossOfControlCooldown`. It was renamed to `...CooldownInfo` / `...CooldownDuration`.
  - `InterfaceOptions_AddCategory`. It is only called from dead code.

  Almost every other call **exists**. The API surface is close to retail Midnight, so the problem is not missing functions.
- **Secret values, not missing APIs, block the engine.** 51 of the used functions carry a return-secrecy flag (`SecretReturns` or `SecretWhen*Restricted`): 44 globals and 7 `C_*`. 14 used events carry payload secrecy. The flagged set covers every input the APL engine reads during `state.reset()`: power, auras, cooldown start/duration, charges, cast timing, haste/stats, health, and GUIDs of non-player units.
- **CLEU is effectively gone.**
  - `COMBAT_LOG_EVENT_UNFILTERED` still exists but is flagged `HasRestrictions` and `CallbackEvent`.
  - The payload getter is missing, so `Events.lua:2016` would throw on any delivery.
  - Damage-based target counting, death cleanup, minion tracking and Feral snapshot/Bloodtalons tracking (`DruidFeral.lua:1182`) all depend on CLEU.
- **The worktree cannot load as-is.** `Libs/` holds only SpellFlashCore. The `.pkgmeta` externals (LibStub, Ace3, LibRangeCheck-3.0, LibSpellRange-1.0, …) are not checked out, so `Hekili.lua:5` `LibStub(...)` fails before any API question matters.
- **Usable building blocks exist on Forever.** The docs have no secret flag on these, or flag them `NeverSecret`:
  - `C_Secrets.*` predicates, so the addon can ask at runtime whether a value will be secret.
  - `C_RestrictedActions.IsAddOnRestrictionActive` and the `ADDON_RESTRICTION_STATE_CHANGED` event.
  - `SpellCooldownInfo.isActive` / `isOnGCD` / `isEnabled` (`NeverSecret`).
  - `SpellChargeInfo.maxCharges` / `isActive` (`NeverSecret`).
  - `C_Spell.GetSpellPowerCost` and `C_Spell.IsSpellUsable` (no secret flag).
  - The `PLAYER_SWING` event and the `C_AssistedCombat.*` functions.
  - `C_Spell.IsSpellInRange`, `C_NamePlate.GetNamePlates` and `UnitCanAttack` (no return-secret flag).

## Method / data sources

1. **C_ calls:** regex `\bC_[A-Za-z]+\.[A-Za-z0-9_]+` over non-comment code in the in-scope files (script `/tmp/r1scripts/extract.py`).
2. **Global reads:** compiled every in-scope file with `luajit -bl` and collected `GGET "name"` operands, which gives exact global reads with no regex noise (`/tmp/r1scripts/globals.sh`). Classified with `/tmp/r1scripts/classify.py`.
3. **Events:** every `[A-Z_]+` token that is a known event literal in any flavor, cross-checked against registration sites (`/tmp/r1scripts/events.py`). This also covers loop-registered tables such as `talentEvents` (Events.lua:1015), `specializationEvents` (Events.lua:355) and UI `alphaUpdateEvents`, `kbEvents` and `flashEvents` (UI.lua:894-950).
4. **Ground truth:** sparse clone of `Gethe/wow-ui-source@forever`, commit `943764493e6b`, "1.60.1 (70338)". This build matches the installed client.
   - I parsed all of `Blizzard_APIDocumentationGenerated/*.lua` with LuaJIT (`/tmp/r1scripts/dump.lua` → `/tmp/r1scripts/forever.tsv`) to keep the **full** secret metadata: `SecretWhenUnitPowerRestricted`, `SecretWhenUnitAuraRestricted`, `SecretWhenCooldownsRestricted`, `RequiresNonSecretAura`, and field-level `NeverSecret`/`ConditionalSecret`.
   - The `wow` MCP index (`hated-wow-mcp@0.6.1`, `api-forever.json`) keeps only `secretArguments` and `secretReturns=true`. It **drops the conditional `SecretWhen*` flags**, so it under-reports secrecy. For example, MCP shows `UnitPower` with no secret marker, while the raw doc at UnitDocumentation.lua:2734 has `SecretWhenUnitPowerRestricted = true`.
5. **Undocumented globals:** Forever has no published global list (MCP: "globals: 0, no upstream source yet"). Each one was checked against Forever FrameXML. It is "defined in Lua" if FrameXML defines it, and "referenced" if Blizzard's own Forever code calls it. Anything with neither is marked **unknown**, not missing.

Legend: **OK** = exists, no return-secrecy flag · **SECRET** = exists, returns secret in combat or under restriction (unusable for logic) · **COND** = exists, secrecy depends on unit or restriction predicate (often fine for `"player"`, check at runtime) · **MISSING** = confirmed absent · **UNK** = not documented, existence unverified.

## Findings

### A. Engine-critical secret/restricted APIs (what `state.reset`, events, target counting use)

| API | Forever doc flags | Hekili call sites | Class | Impact |
|---|---|---|---|---|
| `UnitPower` | `SecretWhenUnitPowerRestricted` (UnitDocumentation.lua:2734) | State.lua:6899 (reset), Events.lua:1450 (UNIT_POWER_FREQUENT) | SECRET (combat) | Energy/CP resource model, regen forecasting |
| `UnitPowerMax`, `UnitPartialPower` | `SecretWhenUnitPowerMaxRestricted` / `...PowerRestricted` | State.lua | SECRET | `energy.max`, deficit, time_to_max |
| `GetPowerRegenForPowerType` | `SecretWhenUnitStatsRestricted` | State.lua | SECRET | energy regen rate |
| `C_UnitAuras.GetBuffDataByIndex` / `GetDebuffDataByIndex` | `RequiresUnitAuraAccess`, `SecretWhenUnitAuraRestricted` (UnitAuraDocumentation.lua:324) | State.lua:5995 `ScrapeUnitAuras`, Hekili.lua:12, Utils.lua:24 | SECRET | All buff/debuff state; `UnitIsUnit(caster,…)` filter too |
| `C_UnitAuras.GetPlayerAuraBySpellID` | `RequiresNonSecretAura`, `SecretWhenUnitAuraRestricted` (:395) | Events.lua:21, State.lua:17 | SECRET (most auras) | Player aura lookups |
| `C_UnitAuras.GetAuraDataByAuraInstanceID`, `GetAuraSlots` | `RequiresUnitAuraAccess` (+SecretWhen… on first) | Events.lua:1503, State.lua:765 | SECRET | Incremental UNIT_AURA handling |
| `AuraUtil.FindAura` / `UnpackAuraData` | FrameXML (AuraUtil.lua:40,76) | Utils.lua:15-41 | OK fn / SECRET data | Wraps secret AuraData |
| `C_Spell.GetSpellCooldown` | `SecretWhenCooldownsRestricted`; struct fields `isEnabled/isActive/isOnGCD` = `NeverSecret` (SpellSharedDocumentation.lua:19-31) | Events.lua:28, State.lua:29 wrapper, Events.lua:1924 (GCD via 61304) | SECRET start/duration; **booleans OK** | cooldown.x.remains, GCD timing |
| `C_Spell.GetSpellCharges` | `SecretWhenCooldownsRestricted`; `maxCharges/isActive` `NeverSecret` | State.lua:22, :3380 | SECRET currentCharges/start | charges, charges_fractional |
| `C_Spell.GetSpellCastCount` | `SecretWhenCooldownsRestricted` | State.lua:750 | SECRET | |
| `UnitCastingInfo` / `UnitChannelInfo` | `SecretWhenUnitSpellCastRestricted`; `castBarID/isTradeskill/delayTimeMs` NeverSecret | Events.lua:1329, :1820; State.lua; UI.lua | COND | Player cast/channel timing in reset |
| `GetHaste`, `UnitSpellHaste`, `GetMeleeHaste`, `UnitAttackSpeed`, `GetCritChance`, `GetMasteryEffect`, `UnitStat`, `UnitAttackPower`, `GetCombatRating(Bonus)`, … (13) | `SecretWhenUnitStatsRestricted` | State.lua (stat table), State.lua:2680 (swing), Targets.lua, Classes.lua | COND→likely SECRET | haste-scaled GCD/regen, swing timers |
| `UnitHealth` | `SecretReturns` (always) (UnitDocumentation.lua:1526) | State.lua:2926, :3230, :6960; Targets.lua (TTD); Utils.lua | SECRET | health.pct, TTD, execute |
| `UnitHealthMax` | `SecretWhenUnitHealthMaxRestricted` | State.lua, Targets.lua | COND | |
| `UnitGetTotalAbsorbs`, `UnitInRange` | `SecretReturns` | State.lua, Targets.lua, Classes.lua | SECRET | minor |
| `UnitGUID` | `SecretWhenUnitIdentityRestricted` (:1241) | Targets.lua:51,241,255,267,496,626,1283; Events.lua; State.lua | COND (enemy units in combat likely secret) | **Target table keys**; secret values can't be compared/keyed |
| `UnitIsUnit` | `RequiresComparableUnitTokens`, `SecretWhenUnitComparisonRestricted` (:2410) | Targets.lua, Utils.lua:20-38, State.lua aura caster check | COND | "is my aura" filter |
| `UnitName`, `UnitClass(Base)`, `UnitRace`, `UnitSex`, `UnitCreatureType`, `UnitInRaid`, `UnitIsPVP`, `UnitPhaseReason`, `UnitTokenFromGUID` | `SecretWhenUnitIdentityRestricted` / `...NameIdentity...` | many | COND (player OK out of combat) | debug strings, target filtering |
| `UnitThreatSituation` | `SecretWhenUnitThreatStateRestricted` | State.lua:2196 | COND | `aggro` |
| `GetTotemInfo` | `SecretWhenTotemSlotSecret` | State.lua:4630, :6870 | COND | totem/pet timers (n/a Feral) |
| `GetUnitEmpowerStageDuration/HoldAtMaxTime` | `SecretWhenUnitSpellCastRestricted` | Events.lua | COND | Evoker only |

**Usable with no secret flag:**
- **Time and spell queries:** `GetTime`, `C_Spell.IsSpellUsable`, `C_Spell.GetSpellPowerCost`, `C_Spell.IsCurrentSpell`, `C_SpellActivationOverlay.IsSpellOverlayed`, `C_Spell.GetSpellInfo`/`Texture`/`Description`/`Link`.
- **Item queries:** `C_Item.IsUsableItem`, `C_Item.GetItemCooldown`.
- **Spellbook, specialization and talents:** `C_SpellBook.*`, `C_SpecializationInfo.*`, `C_Traits.*`, `C_ClassTalents.*`.
- **Unit state checks:** `UnitExists`, `UnitCanAttack`, `UnitIsDead`, `UnitAffectingCombat`, `UnitIsFriend`, `UnitLevel`, `UnitPowerType`, `UnitClassification`.
- **Player and world state:** `IsMounted`, `GetInstanceInfo`, `InCombatLockdown`.
- **Timers:** `C_Timer.*`.
- **Not flagged here, but secret in combat on Forever:** the documented "AllowedWhenTainted/Untainted" in `secretArguments` is about passing secrets *in*, not about return values. The shared brief says `GetSpellPowerCost` costs are readable in combat. Catnip confirms this.

### B. Missing / renamed

| Used name | Where | Status | Replacement on Forever |
|---|---|---|---|
| `CombatLogGetCurrentEventInfo` | Events.lua:2016, Options/DevTools.lua:453 | **MISSING (effective)**. Shim `Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua:17` = `C_CombatLog.GetCurrentEventInfo`, which is absent from Forever and mainline docs (present only in classic). Only `C_CombatLogSecure.*` (SecureOnly) / `C_CombatLogInternal.*` remain. | None for addons. Use `UNIT_SPELLCAST_*`, `UNIT_AURA` (+predicates), `NAME_PLATE_*`, `PLAYER_SWING`. |
| `C_Spell.GetSpellLossOfControlCooldown` | State.lua:22 (localized; nil until called) | **MISSING** (also absent on mainline per `wow_api_diff`) | `C_Spell.GetSpellLossOfControlCooldownInfo` (returns `SpellLossOfControlInfo`; `isActive` NeverSecret) / `...CooldownDuration` |
| `InterfaceOptions_AddCategory` | Core.lua:52 | MISSING (no FrameXML def) but only in `EmbedBlizOptions`, whose call is commented out (Core.lua:76) | `Settings.RegisterCanvasLayoutCategory` |
| `UnitAuraBySlot` | State.lua:5882 `StoreMatchingAuras` (exported, no internal caller) | UNK/likely missing (no FrameXML ref) | `C_UnitAuras.GetAuraDataBySlot` (also SecretWhenUnitAuraRestricted) |
| `UnitAura` | State.lua:764 `state.UnitAura = UnitAura` (alias only) | UNK (only classic deprecated file references it) | `C_UnitAuras.GetAuraDataByIndex` |
| `GetTalentInfoByID`, `GetPvpTalentInfoByID` | Events.lua:424, :445 (`ns.updateTalents`, called from Classes.lua:4368, Events.lua:982/1008) | UNK: undocumented; Forever FrameXML calls `GetPvpTalentInfoByID` (4×) but never `GetTalentInfoByID` | Forever FrameXML uses `C_SpecializationInfo.GetTalentInfo` / `GetTalentInfo` (10× each). Talent model needs R-x follow-up. |
| `GetSpellBaseCooldown` | Options/DevTools.lua:867 | UNK (no FrameXML ref) | dev-only |
| `GetItemInfo`, `GetItemGem`, `GetSpellLink`, `IsUsableSpell` (bare globals) | State.lua:745-746 (`state.*` aliases), UI.lua:27 shadows with `C_Spell.IsSpellUsable` | UNK (0 bare calls in FrameXML) | `C_Item.*`, `C_Spell.*` (already used elsewhere) |
| `ITEM_SPELL_TRIGGER_ONEQUIP`, `PET_TYPE_DEMON`, `BATTLE_PET_NAME_4` | Events.lua:804/860/911, State.lua | UNK (GlobalStrings not in ui-source) | |

**Not missing:** `C_PetBattles.IsInBattle` (UI.lua:43, indexed at file load). `wow_api_diff` reports it "NOT AVAILABLE" on Forever, but that is only because Forever has no global list. Forever's own `Blizzard_ActionBar/Shared/ActionButton.lua` calls it, and the `C_PetBattles` docs (5 functions) exist. It is **OK**.

### C. Undocumented C-side globals that Forever FrameXML calls (treat as OK, unverified)

Bare-call counts in Forever FrameXML:

| Global | FrameXML calls | Global | FrameXML calls |
|---|---|---|---|
| `CreateFrame` | 370 | `GetSpecializationInfoByID` | 22 |
| `IsInGroup` | 128 | `GetNumSubgroupMembers` | 19 |
| `IsInRaid` | 71 | `GetInventoryItemID` | 18 |
| `SecureCmdOptionParse` | 69 | `GetClassInfo` | 10 |
| `GetBindingKey` | 51 | `GetShapeshiftFormInfo` | 8 |
| `GetNumGroupMembers` | 50 | `GetStablePetInfo` | 6 |
| `GetActionInfo` | 45 | `GetPvpTalentInfoByID` | 4 |
| | | `debugstack` | 3 |
| | | `GetShapeshiftForm` | 1 |
| | | `GetNumClasses` | 1 |

Defined in Forever FrameXML (Lua), so OK:
- **Frames, tooltips and utility objects:** `AuraUtil`, `BackdropTemplateMixin`, `GameTooltip`, `GameTooltip_SetTitle/AddNormalLine`, `GetAppropriateTooltip`, `UIParent`, `UIDropDownMenu_*`, `ToggleDropDownMenu`, `UIFrameFadeOut`, `PixelUtil`, `PlayerUtil`, `ExportUtil`, `ClassTalentImportExportMixin`, `Item`, `ItemLocation`, `CreateAtlasMarkup`.
- **Constants and globals:** `RAID_CLASS_COLORS`, `TOOLTIP_UPDATE_TIME`, `LOCALIZED_CLASS_NAMES_*`, `INVSLOT_*`, `CR_*` constants, `DEFAULT_CHAT_FRAME`, `MAX_PLAYER_LEVEL`.
- **CVars and bindings:** `GetCVar`/`SetCVar` (CvarUtil), `ClearOverrideBindings`/`SetOverrideBindingClick`.
- **Not undocumented:** `InCombatLockdown` has a doc entry (RestrictedActionsDocumentation.lua:45, `Namespace=""`, so it is a global).
- **Deprecation shims** (`Blizzard_Deprecated*`) exist **only if CVar `loadDeprecationFallbacks` is on**:
  - `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown` (Deprecated_SpellBook → `C_SpellBook.IsSpellKnown`)
  - `SpellIsSelfBuff`
  - `IsActionInRange`, `HasVehicleActionBar`, `HasOverrideActionBar` (→ `C_ActionBar.*`)
  - `COMBATLOG_OBJECT_*`

  Hekili uses these at Events.lua:428/448/784, Targets.lua:145/172 and UI.lua:43. They should be **ported to the `C_` forms** rather than relying on the CVar.

### D. Events (99 tokens; all in Forever event docs)

| Event(s) | Flags on Forever | Hekili site | Class |
|---|---|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | `HasRestrictions`, `CallbackEvent` (CombatLogDocumentation.lua:132) | Events.lua:2016, Classes.lua:1087, DruidFeral.lua:1182 | **RESTRICTED + payload getter missing** |
| `UNIT_DIED`, `PARTY_KILL` | `SecretWhenUnitIdentityRestricted` | Events.lua:1669-1672 (used as **CLEU subevent strings**, not registered) | dead with CLEU |
| `UNIT_AURA` | `SecretWhenAurasRestricted` (UnitAuraDocumentation.lua:643) | Events.lua:1513 | SECRET payload (updateInfo) in combat |
| `UNIT_SPELLCAST_{START,STOP,SUCCEEDED,SENT,DELAYED,CHANNEL_*,EMPOWER_*}` | `SecretWhenUnitSpellCastRestricted`; `castBarID` NeverSecret; SENT `target` ConditionalSecret | Events.lua:1220-1369 | COND. For `"player"` the spellID is readable per Catnip; for `"target"` it is likely secret |
| `UNIT_POWER_FREQUENT` | none on payload (unit, powerType) | Events.lua:1423 | OK event; handler's `UnitPower` read is SECRET |
| `NAME_PLATE_UNIT_ADDED/REMOVED` | none | Targets.lua:240/253 | OK; the handler's `UnitGUID` is COND |
| `PLAYER_TARGET_CHANGED`, `PLAYER_REGEN_*`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`, `SPELL_ACTIVATION_OVERLAY_GLOW_*`, `UPDATE_SHAPESHIFT_FORM`, `CURRENT_SPELL_CAST_CHANGED`, `SPELL_DATA_LOAD_RESULT`, `PLAYER_STARTED/STOPPED_MOVING`, `ENCOUNTER_*`, `UNIT_FLAGS`, `UNIT_COMBAT`, `PLAYER_EQUIPMENT_CHANGED`, `UPDATE_BINDINGS`, `ACTIONBAR_*`, `ZONE_CHANGED*`, `CVAR_UPDATE`, `DISPLAY_SIZE_CHANGED`, vehicle/pet-battle/barber/client-scene events | none | Events.lua, UI.lua, Targets.lua | OK |
| `ACTIVE_PLAYER_SPECIALIZATION_CHANGED`, `PLAYER_SPECIALIZATION_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED`, `TRAIT_CONFIG_*`, `ACTIVE_COMBAT_CONFIG_CHANGED`, `CONFIG_COMMIT_FAILED`, `STARTER_BUILD_ACTIVATION_FAILED`, `PLAYER_TALENT_UPDATE`, `CONFIRM_TALENT_WIPE`, `SPEC_INVOLUNTARILY_CHANGED`, `TALENTS_INVOLUNTARILY_RESET`, `CHALLENGE_MODE_*`, `QUEST_SESSION_*`, `AZERITE_ESSENCE_*` (commented out), `ARENA_PREP_OPPONENT_SPECIALIZATIONS` | none | Events.lua:351-392, 1015-1024; Classes.lua:4392-4401 | OK (exist, may never fire on Forever) |

Some events are not used by Hekili but exist on Forever and look useful:
- `PLAYER_SWING(swingDuration, swingType)`
- `PLAYER_SWING_RANGE_UPDATE`
- `SPELL_UPDATE_COOLDOWN(spellID, …)`, `SPELL_UPDATE_CHARGES`, `SPELL_UPDATE_USABLE`
- `UNIT_SPELLCAST_FAILED(_QUIET)`
- `ADDON_RESTRICTION_STATE_CHANGED(type, state)`
- `ASSISTED_COMBAT_ACTION_SPELL_CAST`
- `COOLDOWN_VIEWER_DATA_LOADED`
- `PLAYER_SOFT_ENEMY_CHANGED`

### E. Counts

| Bucket | Count |
|---|---|
| Distinct `C_*` functions used | 84 → OK 75, SECRET/COND 7, MISSING 1 (`GetSpellLossOfControlCooldown`), false-missing 1 (`C_PetBattles.IsInBattle`, OK) |
| Documented global functions used | 78 → no return-secret 34 (13 no flags + 21 `SecretArguments` only), return-secret/COND 44 |
| Undocumented C-side globals | 22 → referenced by Forever FrameXML 15 (assume OK); UNK 5 (`GetTalentInfoByID`, `GetSpellBaseCooldown`, `UnitAura`, `UnitAuraBySlot`, `IsUsableSpell` bare); MISSING 2 (`CombatLogGetCurrentEventInfo`, `InterfaceOptions_AddCategory`) |
| FrameXML/Lua-defined globals (UI utils, mixins, constants) | ~70 → OK. Deprecation-CVar dependent: 9 |
| Event names | 99 → all exist; restricted 1 (CLEU); secret-payload 13 (UNIT_AURA, 10× UNIT_SPELLCAST_*, plus UNIT_DIED/PARTY_KILL, which are really CLEU subevents) |

### F. Top-20 blockers (ranked by engine criticality)

| # | Blocker | Breaks | Severity |
|---|---|---|---|
| 0 | `Libs/` externals absent (only SpellFlashCore present; `embeds.xml` needs LibStub/Ace3/LibRangeCheck/LibSpellRange) | Addon load (`Hekili.lua:5`) | **Hard, pre-API** |
| 1 | CLEU restricted + `CombatLogGetCurrentEventInfo` missing | Events.lua:2016 handler errors; damage/dot target counting (Events.lua:1930-2010), unit death cleanup, minion tracking, Feral Bloodtalons/snapshot hook (DruidFeral.lua:1182) | Hard |
| 2 | `UnitPower`/`UnitPowerMax`/`UnitPartialPower` secret | `state.reset` resources (State.lua:6899), UNIT_POWER_FREQUENT forecasting (Events.lua:1450). Energy & combo points drive every Feral condition | Hard |
| 3 | `C_UnitAuras.Get{Buff,Debuff}DataByIndex` secret | `ScrapeUnitAuras` (State.lua:5956-6100), called by `state.reset` State.lua:6809/6814. All `buff.*`/`debuff.*`/`dot.*` | Hard |
| 4 | `UNIT_AURA` updateInfo secret + `GetAuraDataByAuraInstanceID` secret | Incremental aura tracking Events.lua:1503-1513 | Hard |
| 5 | `C_Spell.GetSpellCooldown` start/duration secret | `cooldown.*.remains`, GCD (Events.lua:1924, spell 61304). Only `isActive/isOnGCD/isEnabled` usable | Hard |
| 6 | `C_Spell.GetSpellCharges` currentCharges/start secret | `charges`, `charges_fractional`, `recharge` (State.lua:3380) | Hard |
| 7 | `UnitGUID` secret for enemy units under identity restriction | Target registry keyed by GUID (Targets.lua:241-267, 496, 1283); TTD DB | High |
| 8 | `UnitHealth` always secret, `UnitHealthMax` cond. | TTD/`fight_remains`, `target.health.pct`, execute logic (Targets.lua, State.lua:3230/6960) | High |
| 9 | Haste/stat APIs (`GetHaste`, `UnitSpellHaste`, `GetMeleeHaste`, `UnitAttackSpeed`, crit/mastery) `SecretWhenUnitStatsRestricted` | GCD length, energy regen, swing timer (State.lua:2680) | High |
| 10 | `UnitCastingInfo`/`UnitChannelInfo` cond. secret | Cast/channel state in reset, Events.lua:1329/1820 | Med-High (Feral: low) |
| 11 | `UNIT_SPELLCAST_*` payload cond. secret | Action history / `prev_gcd` / queued-cast detection (Events.lua:1220-1369). Player-unit probably fine (Catnip) | Medium |
| 12 | `UnitIsUnit` comparison restricted | "my aura" caster filter (State.lua aura scrape, Utils.lua:20-38), unit matching in Targets | Medium |
| 13 | `C_UnitAuras.GetPlayerAuraBySpellID` (`RequiresNonSecretAura`) | Fast player-aura checks (Events.lua:21, State.lua:17) | Medium (works only for whitelisted non-secret auras) |
| 14 | `C_Spell.GetSpellLossOfControlCooldown` missing | State.lua:22 local is nil, so any LoC-cooldown path errors | Medium |
| 15 | Talent model: `GetTalentInfoByID`/`GetPvpTalentInfoByID` unknown; `C_Traits`/`C_ClassTalents` exist but Forever trees are 1.6-era | `ns.updateTalents` (Events.lua:416), all `talent.*` conditions | Medium (need R-x) |
| 16 | Deprecated shims rely on `loadDeprecationFallbacks` CVar (`IsPlayerSpell`, `SpellIsSelfBuff`, `IsActionInRange`, `HasVehicleActionBar`) | Talent fallback (Events.lua:428), trinket proc detection (Events.lua:784), pet range (Targets.lua:145), UI hide rules (UI.lua:43) | Medium |
| 17 | `UnitThreatSituation`, `UnitGetTotalAbsorbs`, `UnitInRange`, `GetTotemInfo` secret/cond. | `aggro`, absorbs, totems (State.lua:2196/4630/6870) | Low (Feral) |
| 18 | Identity APIs (`UnitName`, `UnitClass`, `UnitCreatureType`, `UnitIsPVP`, `UnitPhaseReason`) cond. secret | Target filtering (Targets.lua), debug snapshot strings (secret string concat errors) | Low-Med |
| 19 | `InterfaceOptions_AddCategory` missing | Dead code (Core.lua:52, call commented at :76) | Low |
| 20 | `UnitAura`/`UnitAuraBySlot`/bare `GetItemInfo`/`GetItemGem` | Nil aliases (State.lua:745-764, 5882). Error only if an APL or script calls them | Low |

## Evidence

- Forever docs: `github.com/Gethe/wow-ui-source` branch `forever` @ `943764493e6b` ("1.60.1 (70338)").
  - `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:2732-2735`: `UnitPower`, `SecretWhenUnitPowerRestricted = true`.
  - `UnitAuraDocumentation.lua:324,395,643`: buff-by-index, player-aura, `UNIT_AURA` (`SecretWhenAurasRestricted`).
  - `SpellDocumentation.lua:257,291,309`: cast count, charges, cooldown, all with `SecretWhenCooldownsRestricted`.
  - `SpellSharedDocumentation.lua:19-31`: `SpellCooldownInfo`, with `NeverSecret` on `isEnabled`, `isActive` and `isOnGCD`.
  - `CombatLogDocumentation.lua:132`: CLEU `HasRestrictions`, `CallbackEvent`. `C_CombatLog` lists 11 functions and no `GetCurrentEventInfo`. `CombatLogSecureDocumentation.lua` has `Environment = "SecureOnly"`.
  - `SecretPredicateAPIDocumentation.lua` (`C_Secrets`): `ShouldUnitPowerBeSecret(unit, powerType)`, `GetPowerTypeSecrecy`, `ShouldAurasBeSecret`, `ShouldSpellAuraBeSecret`, `ShouldCooldownsBeSecret`, `ShouldSpellCooldownBeSecret`, `ShouldUnitStatsBeSecret`, `ShouldUnitIdentityBeSecret`, `ShouldUnitSpellCastBeSecret`, … `SecrecyLevel` = `NeverSecret` 0 / `AlwaysSecret` 1 / `ContextuallySecret` 2 (`SecretWrapperConstantsDocumentation.lua:6-14`).
  - `RestrictedActionsConstantsDocumentation.lua:19-31`: `AddOnRestrictionType` = Combat / Encounter / ChallengeMode / PvPMatch / Map / Chat. `RestrictedActionsDocumentation.lua:29,45,55`: `GetAddOnRestrictionState`, `InCombatLockdown` (global), `IsAddOnRestrictionActive`.
  - `Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua:4,17`: gated on `loadDeprecationFallbacks`, and `CombatLogGetCurrentEventInfo = C_CombatLog.GetCurrentEventInfo` (that target does not exist).
  - `Blizzard_ActionBar/Shared/ActionButton.lua` calls `C_PetBattles.IsInBattle`.
- MCP `wow_api_diff`:
  - `C_PetBattles.IsInBattle`: Forever "NOT AVAILABLE". This is a false negative because Forever has no globals list.
  - `C_Spell.GetSpellLossOfControlCooldown`: NOT AVAILABLE on any flavor.
  - `COMBAT_LOG_EVENT_UNFILTERED`: valid event on all flavors.
- MCP `wow_api_search` (forever) `GetSpellLossOfControl` returns `C_Spell.GetSpellLossOfControlCooldownInfo` / `...Duration`.
- MCP `wow_api_stats`: Forever has 6577 functions, 1802 events, **0 globals** ("no upstream source yet: globals, eventNames, cvars").
- MCP index JSON (`hated-wow-mcp/data/api-*.json`): `C_CombatLog.GetCurrentEventInfo` appears in classic only. Mainline and Forever have only `C_CombatLogInternal`/`C_CombatLogSecure`.
- Hekili sites: cited inline. Raw extraction outputs: `/tmp/r1scripts/{uses,gget,glob_class,events,cf,forever}.tsv`. These are scratch files that are not in the repo, and they can be regenerated from the scripts in the same directory.

## Open questions

1. **Which restrictions are active on Forever, and for which units?** The flags are conditional (`SecretWhenUnitPowerRestricted` etc.). One `/run` in combat would answer it from the predicates. Test: `C_Secrets.ShouldUnitPowerBeSecret("player", Enum.PowerType.Energy)`, `GetPowerTypeSecrecy(ComboPoints)`, `ShouldUnitStatsBeSecret()`, `ShouldAurasBeSecret()`, `ShouldCooldownsBeSecret()`, `ShouldUnitIdentityBeSecret("target")`, and `C_RestrictedActions.IsAddOnRestrictionActive(0)`, each in and out of combat. The brief says power and combo points are secret in combat, which is consistent with these flags.
2. **Does registering CLEU on a frame raise `ADDON_ACTION_FORBIDDEN`, or deliver nothing?** The Forever addon Attune still registers it (`Attune.lua:591`), but it is multi-flavor code. Needs an in-game test.
3. **Is `C_CombatLogInternal.GetCurrentEventInfo` (Environment "All") callable by addons?** It is probably not exposed in shipping builds. Untested.
4. **Is `loadDeprecationFallbacks` on by default on Forever?** That decides whether `IsPlayerSpell`, `SpellIsSelfBuff` and `IsActionInRange` exist.
5. **How do talents work on Forever (1.6 trees)?** It is unclear whether `C_Traits`/`C_ClassTalents` return a tree, or whether classic `GetTalentInfo(tab, i)` applies. This needs a separate investigation.
6. **Are secret values usable as table keys or in `==`?** The brief says no comparisons are allowed. If GUIDs from nameplate units are secret, the whole Targets.lua design (GUID-keyed tables) is invalid in combat.
7. **Will LibRangeCheck-3.0 and LibSpellRange-1.0 work on Forever?** They are not in the worktree, so I could not inspect them. Their underlying APIs (`C_Spell.IsSpellInRange`, `C_Item.IsItemInRange`, `CheckInteractDistance`, `UnitDistanceSquared`) carry no return-secret flag on Forever, but restrictions on `C_Item.IsItemInRange` in combat are known from retail.

## Confidence

- **High:**
  - Existence and missing status for documented APIs and events. This comes from build-matched raw docs plus LuaJIT bytecode extraction of global reads.
  - The CLEU getter being missing.
  - The secret flags as written in the docs.
- **Medium:**
  - Real in-combat behaviour of the conditional `SecretWhen*` flags for `"player"`. The docs say *can* be secret, and predicates decide. The Catnip evidence in the brief agrees for power, auras and cooldown times.
  - Undocumented C globals inferred from FrameXML usage.
- **Low:** Whether the deprecation shims and talent APIs actually behave on the live client.
- **Coverage caveats:**
  - `GGET` catches direct global reads only. `_G.X` / `_G["X"]` reads (about 20, mostly ElvUI/Bartender frame names and `_G.IsPassiveSpell` etc. in DevTools) were reviewed by grep.
  - Dynamic `RegisterEvent(k)` loops were resolved by token scan.
