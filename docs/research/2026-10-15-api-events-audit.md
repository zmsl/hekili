# API and events audit (hekili, branch forever, HEAD 3e906ad0). Read-only.
Paths: F = src/Hekili/Virtual/API/Facade.lua, EF = Virtual/Events/EventFacade.lua, N = docs/forever-facade-notes.md,
SPEC = docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md. Hekili files are under src/Hekili/.
"verified" = a [W PRn]/[SU]/gate-spike tag in F or N. Tags say "plain" but rarely say "in combat" (only where written).

## 1. API table (tools/api_inventory.txt: 176 names = 26 hybrid + 123 passthrough + 27 virtual; N:3 still says 175, 124/51, stale)
Every one of the 176 names has a row in F (checked: each name appears quoted in F). No name is NOT IN FACADE.
Rows are built at F:230-715 (kept/hybrid) and the PASSTHROUGH list F:721-843 (122 entries; IsUsableSpell is a kept alias, F:670).
Kind column = inventory class; F's own comment F:2-6 defines them.

### virtual / hybrid rows (53 names), with tag and combat status
| Names | Kind | Tag in F | Combat status |
|---|---|---|---|
| UnitPower | virtual | secret always [W PR16]; Power().est rage / .lo others (F:230) | verified secret; modelled |
| UnitPartialPower | virtual -> 0 | secret always [W PR16]; "no Forever user" (F:259) | verified secret; stubbed 0 |
| GetPowerRegenForPowerType, GetManaRegen | hybrid | secret in combat [W PR16] (F:244,253) | verified |
| UnitHealth, UnitHealthMax, UnitGetTotalAbsorbs | virtual | target secret always [W PR14] (F:264-281) | verified secret; see gap G1 (target/other units are constants) |
| GetCombatRating, GetCombatRatingBonus, GetCritChance, GetMasteryEffect, GetRangedCritChance, GetSpellBonusDamage, GetSpellCritChance, UnitArmor, UnitAttackPower, UnitDamage, UnitStat, UnitWeaponAttackPower | hybrid | secret in combat [W PR2, PR4]; Stat() out-of-combat cache (F:284-321) | verified |
| GetHaste, GetMeleeHaste, UnitSpellHaste | hybrid | [W PR2, PR4] (F:330-333) | verified |
| UnitAttackSpeed | hybrid | secret in combat [SU PR2] (F:340) | verified |
| GetUnitSpeed | hybrid | secret in combat [W PR14] (F:353) | verified |
| UnitInRange | virtual -> false,true | secret always [W PR7]; "no signal" (F:362) | verified secret; no model (G2) |
| GetTotemInfo | hybrid | [W PR12] (F:367) | verified (pick tests only first 4 returns, F:~180) |
| C_UnitAuras.GetBuffDataByIndex, GetDebuffDataByIndex, GetPlayerAuraBySpellID, GetAuraDataByAuraInstanceID; AuraUtil.ForEachAura, FindAura | virtual | secret in combat, errors when tainted [W §4] (F:443-496) | verified |
| C_UnitAuras.GetAuraSlots | virtual -> nil | secret in combat [W §4]; "no retained consumer" (F:510) | verified; unmodelled by design |
| UnitAura, UnitAuraBySlot, C_Spell.GetSpellLossOfControlCooldown, GetSpellBaseCooldown, GetSpellLink, IsHarmfulSpell, IsHelpfulSpell, IsPassiveSpell, GetItemGem, GetItemInfo | virtual stubs | "absent on Forever" (F:511-512, 609, 676-682) | verified absent (N) |
| C_Spell.GetSpellCooldown | kept hybrid | times secret, flags plain [W PR4, PR11] (F:573) | verified |
| C_Spell.GetSpellCharges | kept hybrid | times secret in combat [W §4] (F:596) | verified |
| C_Spell.GetSpellCastCount | virtual -> 0 | "flagged SecretWhenCooldownsRestricted; unprobed, unused" (F:608) | UNKNOWN (unused) |
| UnitCastingInfo, UnitChannelInfo | kept hybrid | player plain [W PR9]; target secret [W PR8] (F:616,634) | verified |
| CombatLogGetCurrentEventInfo | virtual | absent; the row being delivered (F:655) | verified absent |
| GetTalentInfoByID | virtual | dead on Forever [W PR5]; C_Traits walk (F:659) | verified |
| IsUsableSpell | kept passthrough alias | absent on Forever; alias of C_Spell.IsSpellUsable (F:670) | verified via IsSpellUsable [W PR14; SU] |
| GetTime | kept hybrid | plain [W]; back-dated while a CLEU row is delivered (F:687) | verified |
| C_SpecializationInfo.GetSpecializationInfo | kept hybrid | plain [W PR15]; id 0 -> nil (F:708) | verified |
| CreateFrame | virtual | event facade entry (F:715) | n/a |
| AuraUtil.UnpackAuraData | passthrough | pure Lua unpack (F:722) | n/a |

### passthrough rows (123): verified (51)
Item reads C_Item.* x9 [PR13]; GetInventoryItemID [PR13]; C_LossOfControl.* x2 [PR18]; C_SpecializationInfo.GetSpecialization [PR15];
C_Spell.GetSpellPowerCost [§4]; C_Spell.IsCurrentSpell [PR1]; C_Spell.IsSpellUsable [PR14; SU]; IsSpellOverlayed [PR11];
C_Traits.* x8 [PR5, walk identical in combat]; GetActionInfo, GetBindingKey, GetShapeshiftFormInfo [PR10]; GetShapeshiftForm [§4];
InCombatLockdown [§3, lags at PLAYER_REGEN_DISABLED, F:~798]; IsActionInRange [PR7]; UnitPowerMax, UnitPowerType [PR16];
"plain in combat [PR14; gate spike]": UnitAffectingCombat, UnitCanAttack, UnitClass, UnitClassBase, UnitClassification,
UnitCreatureType, UnitExists, UnitGUID, UnitIsDead, UnitIsFriend, UnitIsPlayer, UnitIsUnit, UnitLevel, UnitName, UnitThreatSituation.
Caveat: the PR13/PR18/PR10 tags say "plain" without "in combat"; whether the probe ran in combat is not stated in F or N.

### passthrough rows (122 in the list): "unprobed" = status unknown (72, F:722-843 "unprobed")
C_AddOns.GetAddOnMetadata/IsAddOnLoaded/LoadAddOn, C_ClassColor.GetClassColor, C_ClassTalents.GetActiveConfigID/GetHeroTalentSpecsForClassSpec,
C_PetBattles.IsInBattle, C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier, C_PvP.IsWarModeDesired, C_SpecializationInfo.GetTalentInfo,
C_Spell.GetSpellDescription/GetSpellInfo/GetSpellTexture/IsSpellDataCached/IsSpellHarmful/IsSpellHelpful/IsSpellPassive/RequestLoadSpellData,
C_SpellBook.FindSpellBookSlotForSpell/GetNumSpellBookSkillLines/GetSpellBookItemInfo/GetSpellBookSkillLineInfo/IsSpellInSpellBook/IsSpellKnown,
C_Texture.GetAtlasInfo, C_TooltipInfo.GetInventoryItem/GetItemByID/GetSpellByID, C_VideoOptions.GetCurrentGameWindowSize, GetBuildInfo, GetCVar,
GetClassInfo, GetCursorInfo, GetFrameCPUUsage, GetFramerate, GetInstanceInfo, GetNetStats, GetNumClasses, GetNumGroupMembers,
GetNumSubgroupMembers, GetRealmName, GetSpecializationInfoByID, GetStablePetInfo, HasOverrideActionBar, HasVehicleActionBar, IsInGroup,
IsInInstance, IsInJailersTower, IsInRaid, IsMounted, IsPlayerSpell, IsResting, IsSpellKnown, IsSpellKnownOrOverridesKnown,
SecureCmdOptionParse, SpellIsSelfBuff, UnitCanAssist, UnitEffectiveLevel, UnitFactionGroup, UnitHasVehicleUI, UnitInParty, UnitInRaid,
UnitInVehicle, UnitIsConnected, UnitIsDeadOrGhost, UnitIsPVP, UnitIsTrivial, UnitOnTaxi, UnitPhaseReason, UnitRace, UnitSex, UnitTokenFromGUID.
Safety net, not verification: while tracing, Facade.secrets counts any secret answer from a passthrough (F:~111-114, snapshot line F:~862).

### API gaps (no row = none; "unknown" = unprobed AND plausibly read in combat or per-reset)
| # | Name(s) | Where read | Why it matters |
|---|---|---|---|
| A1 | IsSpellKnown, IsPlayerSpell, IsSpellKnownOrOverridesKnown, C_SpellBook.IsSpellKnown/IsSpellInSpellBook (F:763-807) | State.lua:69 area, Classes | known-checks per reset; secrecy in combat unknown |
| A2 | C_Spell.GetSpellInfo (F:747) | Utils.lua, Classes.lua (ns.GetUnpackedSpellInfo, State.lua:442) | castTime/range per ability; a secret field would reach APL maths |
| A3 | UnitCanAssist, UnitIsDeadOrGhost, UnitInParty/InRaid, UnitInVehicle, UnitHasVehicleUI, UnitTokenFromGUID, UnitEffectiveLevel, UnitIsTrivial, UnitIsPVP (F:812-830) | State.lua:15,1855; Targets.lua enemy scan | siblings (UnitCanAttack, UnitIsDead, UnitIsFriend) are plain, so likely plain; not probed |
| A4 | GetNetStats (F:787) | State.lua:1799 (latency, `select(4,...)/1000`) | in-combat secrecy unknown; a secret would hit arithmetic |
| A5 | GetNumGroupMembers, IsInGroup, IsInRaid, GetInstanceInfo, IsResting, IsMounted (F:~770-806) | State.lua, Utils.lua, Targets.lua:1761 | unknown, low risk |
| A6 | C_Spell.GetSpellCastCount (F:608) | State.lua, DevTools | flagged SecretWhenCooldownsRestricted, unprobed, stubbed 0 |
| A7 | Game range APIs reached through LibSpellRange (Libs/LibSpellRange-1.0.lua:32 uses C_Spell.IsSpellInRange) | State.lua:59,5071,6985 (`LSR.IsSpellInRange(...) == 0`) | NOT in api_inventory.txt, so check_api_reads.sh cannot see it, and no probe tag exists; a secret result would be compared |
| A8 | Other non-inventory globals loaded files use (luacheck sweep): C_Timer, SetCVar, debugprofilestop, UIParent, GameTooltip, hooksecurefunc etc. | UI/Options/Core | not state reads; outside the facade's remit |

## 2. Events table (registrations: src/Hekili/Engine/Sim/Events.lua unless noted)
Delivery path: every Hekili frame is Facade.CreateFrame (EF:174); EF registers the union of subscribers with the client (EF:56-95) and delivers
anything the client fires (EF:183-216) with each payload slot through Plain (secret -> nil, EF:221-230). So "delivered" = the client fires it.
Never registered with the client (NEVER, EF:24): COMBAT_LOG_EVENT_UNFILTERED (synthesized, CombatLog.lua/Rows.lua/Attackers.lua), FRAME_UPDATE.
A refused registration lands in E.STUB (EF:93-95) and is silently never delivered: nothing lists the stubs at load (see E4).
Forever column = wow_api_event_search flavor forever (result "exists"); "not checked" = I did not query it.

| Event (registration site) | Delivery | Forever | Payload secrecy |
|---|---|---|---|
| UNIT_AURA player,target (1268; DevTools:1154 other units) | client event + virtual info `{isFullUpdate=true}` (EF:26-28,232) | exists | updateInfo table is secret-bearing; replaced by layer's table, so Hekili's handler (1270-1325) always takes the full-update branch; the incremental branches (1288-1320) are dead code |
| COMBAT_LOG_EVENT_UNFILTERED (1771; Druid.lua:605; Warrior.lua:579; DevTools:1156) | synthesized rows, no payload; CombatLogGetCurrentEventInfo returns row (EF:198-200) | n/a (never registered) | rows built from plain signals; see subevent gap E1 |
| UNIT_POWER_FREQUENT player (1215) | client | exists | plain [V] N11 (SPEC:251); handler reads UnitPower = belief (F:230) |
| UNIT_COMBAT player (1781) | client | exists | plain in combat [V] N27, 779 firings 0 secret (SPEC:252); handler does raw `amount > 0` (1774), which throws if a secret ever becomes nil via Plain (pcall-caught, EF:206-211) |
| UNIT_SPELLCAST_SUCCEEDED/START/CHANNEL_START/STOP/UPDATE/STOP/DELAYED (1017-1079), SENT (1124) | client | exist | player plain [W PR9]; target spellID/castGUID secret -> nil, Hekili's target arm reads neither (SPEC:250) |
| PLAYER_TOTEM_UPDATE (1154) | client | exists | slot plain |
| CURRENT_SPELL_CAST_CHANGED (1148 is inside a `--[[ ... ]]` comment: too spammy; UI.lua:1915 registers it) | client | exists | plain |
| PLAYER_REGEN_DISABLED/ENABLED (859,878), PLAYER_TARGET_CHANGED (1330), PLAYER_STARTED/STOPPED_MOVING (1352,1362), PLAYER_EQUIPMENT_CHANGED (823) | client | exist | plain |
| NAME_PLATE_UNIT_ADDED/REMOVED (Targets.lua:250,263), UNIT_FLAGS (273) | client | exist | plain |
| PLAYER_ENTERING_WORLD, ZONE_CHANGED (400), VARIABLES_LOADED (958), PLAYER_LOGIN (State/Adapter.lua:50) | client | not checked | plain |
| ENCOUNTER_START/END (456,463), BARBER_SHOP_OPEN/CLOSE (405,409), PLAYER_CONTROL_LOST/GAINED (415,419), DISPLAY_SIZE_CHANGED (330), CVAR_UPDATE (957), UPDATE_BINDINGS (2318), ACTIONBAR_SHOWGRID/HIDEGRID (2320), SPELLS_CHANGED (2319; UI.lua:1914), UI_ERROR_MESSAGE (Druid.lua:613), UI_INFO_MESSAGE (Targets.lua:303), SPELL_DATA_LOAD_RESULT (309) | client | exist | plain (low risk; not combat-state) |
| Talent/spec: ACTIVE_PLAYER_SPECIALIZATION_CHANGED, ACTIVE_TALENT_GROUP_CHANGED, PLAYER_TALENT_UPDATE, SPEC_INVOLUNTARILY_CHANGED, TALENTS_INVOLUNTARILY_RESET, CONFIRM_TALENT_WIPE (365-386), TRAIT_CONFIG_CREATED/DELETED/UPDATED, ACTIVE_COMBAT_CONFIG_CHANGED, STARTER_BUILD_ACTIVATION_FAILED, CONFIG_COMMIT_FAILED (839-851, 2329) | client | all exist | plain. PLAYER_ALIVE, PLAYER_UNGHOST (851): not checked |
| Branch guard: `Hekili.IsWrath()` (361, 2324) picks which talent events register | n/a | n/a | not verified here what IsWrath() returns on build 16001 (N says version gates false); if true, the specialization/TRAIT events above are NOT registered |
| UI.lua 1905-1923: SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE | client | exist | plain |
| UI.lua alphaUpdateEvents/kbEvents/flashEvents (UI.lua:901-960): PET_BATTLE_OPENING_START, BARBER_SHOP_*, VEHICLE_ANGLE_SHOW, UPDATE_OVERRIDE_ACTIONBAR, CLIENT_SCENE_OPENED, UPDATE_ALL_UI_WIDGETS, PLAYER_MOUNT_DISPLAY_CHANGED, ACTIONBAR_PAGE_CHANGED, ACTIONBAR_UPDATE_STATE, UPDATE_SHAPESHIFT_FORM, LEARNED_SPELL_IN_SKILL_LINE, CHARACTER_POINTS_CHANGED, UPDATE_MACROS, ACTIVE_TALENT_GROUP_CHANGED | client | exist (all queried) | plain. VEHICLE_UPDATE, UNIT_ENTERING/ENTERED/EXITED/EXITING_VEHICLE, PLAYER_GAINS/LOSES_VEHICLE_DATA, ZONE_CHANGED_INDOORS/NEW_AREA, PET_BATTLE_CLOSE, CLIENT_SCENE_CLOSED, PLAYER_CONTROL_*: not checked |
| Engine/Schema/Spec.lua:2209-2229 SpellDisableEvents: CHALLENGE_MODE_START/RESET/COMPLETED, ZONE_CHANGED_NEW_AREA, QUEST_SESSION_*, PLAYER_ALIVE | client | CHALLENGE_MODE_START and QUEST_SESSION_CREATED exist; the rest not checked | plain |
| Engine/Schema/Spec.lua:1080-1090 class RegisterEvent/RegisterUnitEvent wrappers; Druid.lua/Warrior.lua spec-level handlers | pass-through of the above | n/a | n/a |

Events used only by VirtualState sources (Virtual/State/Sources/*, Virtual/Events/*.lua; delivered through EF onEvent -> S.Run, EF:221-228):
PLAYER_SWING (Swing.lua:16, Rows.lua:109; exists, swingDuration/swingType plain in combat per Swing.lua:2), UNIT_MAXPOWER, UNIT_DISPLAYPOWER,
UNIT_DAMAGE, UNIT_ATTACK_POWER, UNIT_ATTACK_SPEED, SPELL_UPDATE_USABLE/COOLDOWN/CHARGES, ACTION_USABLE_CHANGED, PLAYER_LEVEL_UP, TRAIT_CONFIG_UPDATED,
PLAYER_TALENT_UPDATE, SPELLS_CHANGED, UNIT_SPELLCAST_FAILED/INTERRUPTED/INTERRUPTIBLE/NOT_INTERRUPTIBLE/STOP (target), UNIT_TARGET: all exist
on Forever (queried); PLAYER_FOCUS_CHANGED (Attackers.lua:111): not checked.

### Event gaps
- E1. Combat-log subevents Hekili consumes but no source synthesizes (CLEU_HANDLER Events.lua:1464-1771). Emitted set (Virtual/Events/*.lua):
  SPELL_AURA_APPLIED/REFRESH/REMOVED, SPELL_CAST_START/SUCCESS/FAILED, SPELL_DAMAGE, SPELL_MISSED, SPELL_ENERGIZE, SWING_DAMAGE/MISSED.
  Read but never delivered at HEAD: UNIT_DIED/UNIT_DESTROYED/UNIT_DISSIPATES/PARTY_KILL/SPELL_INSTAKILL (death_events, Events.lua:1423-1429, handler 1468;
  SPEC:287,666 schedule it as "phase C", not built; consequence: ns.eliminateUnit never runs), SPELL_SUMMON (1500), SPELL_AURA_APPLIED_DOSE,
  SPELL_AURA_BROKEN/_SPELL (1723-1749), SPELL_PERIODIC_DAMAGE/HEAL/MISSED (1731,1746; SPEC:360 lists periodic missed as omitted), SPELL_EMPOWER_END (1668),
  ENVIRONMENTAL_* (1519), SPELL_AURA_REMOVED_CHANNEL. Class hooks (Druid.lua:605, Warrior.lua:579) see only the emitted set.
- E2. UNIT_AURA incremental lists dead (above): by design (SPEC:249 phase C will replace it).
- E3. UNIT_COMBAT handler Events.lua:1774 has no nil guard (sources guard at Rows.lua:140). Safe only while N27 holds.
- E4. E.STUB (EF:93-95) is a silent drop. No load-time check lists which registered events the client refused; "Forever fires it" is only as good as the 40 queries above.
- E5. Not checked on Forever: PLAYER_ENTERING_WORLD, VARIABLES_LOADED, PLAYER_LOGIN, ZONE_CHANGED*, PLAYER_ALIVE, PLAYER_UNGHOST, PLAYER_FOCUS_CHANGED, vehicle/pet-battle/scene variants listed above.

## 3. Modeled vs read
Answered by VirtualState belief (Virtual/State/Families/*, via facade rows):
- Resources: UnitPower, GetPowerRegenForPowerType, GetManaRegen (Resources.lua; F:230-259). UnitPowerMax/UnitPowerType stay raw but plain [PR16].
- Auras (player, target): all C_UnitAuras/AuraUtil reads (Auras.lua; F:443-512). Other units get nothing.
- Cooldowns, charges, GCD, usability flags: C_Spell.GetSpellCooldown/GetSpellCharges (Casts.lua; F:573-609); IsSpellUsable is raw (plain).
- Casts: player raw hybrid; target via TargetCast.lua (F:616-653); UnitCastingInfo on target is secret, model answers by castBarID.
- Swing/melee haste: UnitAttackSpeed, GetHaste/GetMeleeHaste (Swing.lua; F:330-340). Spell haste, stats, speed: Player.lua (F:284-353).
- Health: UnitHealth/UnitHealthMax for "player" only (Player.lua:81, F:264-281).
- Talents: GetTalentInfoByID via C_Traits walk (Talents.lua; F:659); C_Traits.* raw but verified identical in combat [PR5].
- Totems: GetTotemInfo (Totems.lua; F:367). Enemies: Enemies.lua counts plates but no Hekili code reads VS.Count (header lines 1-4; confirmed, grep of Count.Enemies/InRange outside Families is empty), so active_enemies still comes from Targets.lua's UnitHealth>1 scan.
Combat-critical reads still raw passthrough: none tagged secret. Tagged-plain raw reads that combat depends on: IsSpellUsable, UnitGUID/Exists/IsDead/CanAttack, UnitPowerMax, UnitPowerType, InCombatLockdown, IsActionInRange, C_Item.*, GetShapeshiftForm, C_Traits.*. Unknown raw reads in combat: A1-A5, A7.
Stubbed (modelled as constants, behaviour wrong not secret) :
- G1. Target health: otherHealth belief fixed at 1 (Player.lua:47-49,77) and nothing writes it, so UnitHealth("target") = 100 always (F:264-272): target.health.pct stays 100, execute-phase conditions never pass, TTD stays default (ttd belief est 30, Player.lua:52-54). Pets/group: UnitHealth returns 100 or 0 (dead), HealthMax 100 (F:268-275, Player.lua:85).
- G2. UnitInRange -> false,true (F:362): group members never "in range" (State.lua:1855).
- G3. UnitPartialPower 0, UnitGetTotalAbsorbs 0, GetSpellCastCount 0, GetAuraSlots nil: unused or no consumer per F tags.

## 4. Verdict
Modeled with gaps. All 176 inventory reads have a facade row, and every read tagged secret in F/N (power, health, stats, haste, swing speed, cooldown times,
auras, target cast, totems, talents, combat log) goes through a virtual or hybrid row. What is not fully modeled:
1. 72 of 122 passthrough rows are "unprobed" (F:722-843), the candidates that State/Targets read per reset or per scan: A1 spell-known family (F:763-807), A2 C_Spell.GetSpellInfo (F:747), A3 UnitCanAssist/IsDeadOrGhost/InVehicle/TokenFromGUID (F:812-830), A4 GetNetStats (F:787; State.lua:1799). Disposition: one probe session in combat, then retag; add a hybrid only if secret.
2. A7 LibSpellRange's C_Spell.IsSpellInRange is outside api_inventory.txt and the facade (State.lua:5071, 6985). Disposition: add inventory entry plus facade row (route LSR through it) after a combat probe.
3. G1 target and other-unit health are constants (Player.lua:47-49, F:264-281): execute and TTD logic never works. Disposition: add a belief family (target health from UNIT_COMBAT/range or accept) or document as dropped.
4. E1 combat-log subevents Hekili reads but nothing delivers (deaths, summon, dose, broken, periodic, empower, environmental; Events.lua:1423-1771). Disposition: build phase C death rows; drop or ignore the rest explicitly in SPEC.
5. E3 UNIT_COMBAT handler lacks a nil guard (Events.lua:1774). Disposition: add `amount and`, one line (not done; read-only audit).
6. E4/E5 no load-time report of events the client refused (EF:93-95); ~12 events unchecked on Forever. Disposition: probe or surface E.STUB in the snapshot.
7. G2 UnitInRange has no model (F:362). Disposition: drop (group content) or add family.
8. A6 GetSpellCastCount unprobed but stubbed 0 (F:608): drop.
9. Housekeeping: N:3 counts (175; 124/51) and the N "Secrecy zone"/"Stub call sites" tables are stale vs the current 26/123/27 rows; the Events.lua IsWrath() branch (361, 2324) was not verified.
Not checked: runtime behaviour on the client, tests, unchecked events above, and whether PASSTHROUGH "plain" tags were taken in combat.
