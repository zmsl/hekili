# EllesmereUI: kick tracking and combat-state techniques under secret values

Date: 2026-10-23. Source: `github.com/EllesmereGaming/EllesmereUI` at `28bd3f64` (v9.6.6), read as untrusted data,
nothing executed. Citations are `file:line` in that checkout. Secrecy annotations are from the Forever generated docs
(`Blizzard_APIDocumentationGenerated`, flavor `forever`, via the `wow` MCP).

## 1. What it is

A full UI suite (unit/raid frames, nameplates, action bars, Cooldown Manager reskin, damage meters, Mythic+ tools, ...)
built for retail Midnight 12.1 **and** WoW Forever. Every TOC lists `## Interface: 120000, ..., 120105, 16001`.
`EllesmereUI_ClientGate.lua:30-33` flags Forever (`iface >= 16000 and < 20000` -> `EUI_CLIENT_FOREVER`); 242 files
branch on `EllesmereUI.IS_FOREVER`. A Forever-only addon exists (`EllesmereUIForeverEssentials`, `AllowLoadGameType:
camelot`: threat meter, uprank, classic spellbook/talents). Four addons are retail-only (`AllowLoadGameType: standard`),
**including `EllesmereUIMythicTimer`, which holds the Kick Tracker**. So the kick-rotation feature does not load on
Forever today; the mechanism underneath it would, with the caveats in section 2.4.

The house rules (`AGENTS.md`) match ours: never compare/index/do arithmetic on secrets, "pass them straight to the
widget API that accepts them"; hook Blizzard frames with `hooksecurefunc` only, cosmetic only.

## 2. The kick tracker ("kick rotations")

There is no assigned kick-order scheduler. "Kick rotation" is three displays over one engine
(`EllesmereUIMythicTimer/EUI_MythicTimer_KickEngine.lua`, 1677 lines, header 1-55): who kicked what, each member's
interrupt cooldown (bars, `EUI_MythicTimer_KickBars.lua`), an icon on the kicked mob's nameplate
(`EUI_MythicTimer_KickPlates.lua`), and "marker defaults": each member's assigned focus-kick raid marker, shown on the
mob carrying that marker until they kick. Active only in Mythic+ and arena (`KickEngine.lua:1600-1603`).

### 2.1 Inputs

| Input | Where | What it yields | Forever secrecy (raw docs) |
|---|---|---|---|
| `UNIT_SPELLCAST_INTERRUPTED` / `_CHANNEL_STOP` / `_EMPOWER_STOP` on nameplate tokens | `KickEngine.lua:1450,1463-1466`, `OnStop` 1377-1408 | a plate's cast stopped; `interruptedBy` non-nil (secret or a non-empty GUID) = a kick, nil/"" = CC or natural end; `spellID` of the enemy cast when plain | Event exists with `interruptedBy: WOWGUID` (UnitDocumentation.lua:4636, 4751); `SecretWhenUnitSpellCastRestricted = true` |
| `DAMAGE_METER_COMBAT_SESSION_UPDATED` with type `Interrupts` (5) | `KickEngine.lua:1459-1460` -> `Attribute` 1249 | "some group member's interrupt landed", same frame as the plate stop (`PAIR_WINDOW = 0.25` s, observed same frame, line 92) | Event payload plain (our damagemeter note) |
| `C_DamageMeter.GetCombatSessionFromType(Current, Interrupts)` rows | `ReadRows` 612-676 | per row: `classFilename`, `specIconID`, `isLocalPlayer` (NeverSecret) -> a row key; row **order** (sorted by count) and row appearance; `totalAmount` (secret, only handed on) | `SecretWhenInCombat`, `SecretArguments = AllowedWhenUntainted`; the three fields are `NeverSecret` |
| `C_DamageMeter.GetCombatSessionSourceFromType(Current, Interrupts, memberGUID)` | `ReadSource` 585-592 | `#combatSpells` (plain): how many distinct enemy spells this member has kicked; `totalAmount` (secret) | same; list length plain (measured in our note, section 3) |
| own `UNIT_SPELLCAST_SUCCEEDED` (player, pet) | `OnOwnCast` 1429-1446 | your own kick, at cast time; your icon goes on your target's plate (`UnitIsUnit("target", plate)` guarded by `pcall` + secret test, 1413-1424) | `SecretWhenUnitSpellCastRestricted`; player casts plain in our captures |
| party talents via `NotifyInspect` + `C_Traits` inspect config | `ReadTree` 398-430, out of combat / before a key | cooldown modifiers (Quick Witted, Honed Reflexes, ...) | plain out of combat; locked inside a key (`C_RestrictedActions.IsAddOnRestrictionActive(ChallengeMode)`, 348-357) |
| static interrupt table | `EllesmereUI_KickData.lua:38-60` | spell -> class, base cd, specs, talent, demon | data |
| `C_ChatInfo.SendAddonMessage("EUIKT", "F|R\t<marker>\t<guid>", "PARTY")` | `KickPlates.lua:2340, 2466-2498`, `CHAT_MSG_ADDON` 3104 | each member's announced focus marker (1-8), sent before the key (inside a key the lockdown drops it) | addon comms; not usable as combat state |

No combat log, no LibOpenRaid, no group cooldown sharing, no `C_CooldownViewer` for party kicks. Party cooldowns are
**modelled**: kick seen -> start `KD.Cooldown(kick, spec, talents)` (`StartCd` 197-200).

### 2.2 Attribution (who kicked)

`Decide`/`Bound`/`Pick` (1136-1330) reason only over plain evidence, best first: the one member whose `#combatSpells`
grew (first kick of that enemy spell; paired with the plate's plain `spellID` it learns that entry), a row that
appeared or moved past another (counts are secret but **sorted**, so order leaks "count rose past X"), your own cast
within `OWN_WINDOW` (1 s), the member whose learned list holds the kicked spell, then elimination by modelled
cooldown (`ELIM_SLACK` 1.5 s). Demon kicks count under the demon's own source (`DemonGUID` 598-610). It never guesses.

### 2.3 The secret-comparison gate (the clever part)

When attribution is ambiguous, the engine still shows exactly the right member without Lua ever learning who:
`BuildGate` (1065-1087) hands each candidate's interrupt count **before** and **after** the update (both secret) to
the display. `KickBars.lua:400-435`: a hidden `StatusBar` gets `SetMinMaxValues(0, after)` and `SetValue(before)`;
its fill is whole iff the count did not move. A `SetClipsChildren(true)` frame is anchored to the fill texture's
right edge, so the member's layer is visible only while the fill is short, i.e. only for the member whose count rose.
The same idiom hides an icon once a member's count has risen past the baseline it was placed at (count gates,
`KickPlates.lua:28-44`), and places marker lanes: the mob's raid-marker index is secret in dungeons, so it goes into a
status bar's value and the kicker's cell hangs from the fill edge inside a one-icon-wide clip at the kicker's own
marker index (`KickPlates.lua:2316-2338`, `BuildLane` 2536-2560, `GetRaidTargetIndex` 2973). `StatusBar:SetMinMaxValues`
/`SetValue` take `SecretArguments = "AllowedWhenTainted"` on Forever, so the trick is available to us.

In short: **a StatusBar plus a clip frame is a secret comparator (`a < b`, `a == k`) whose result only reaches pixels.**

### 2.4 Would it work on Forever?

Mostly yes, if the retail-only addon loaded: the damage meter, its `Interrupts` type, NeverSecret row fields, plain
list lengths and the interrupt event all exist on Forever. Differences: no specs (row `specIconID` is meaningless;
the engine keys rows by class+icon, so two same-class kickers become ambiguous more often), no talent inspect
modifiers, ranked spells (`EllesmereUI_Kick.lua:28-41` already has the Forever per-rank table: Shield Bash/Pummel by
stance, Kick, Counterspell, Earth Shock, Silence, Spell Lock, Feral Charge by form), no `ChallengeMode` restriction.
Unknown: whether Forever's open world/dungeons set `SecretWhenUnitSpellCastRestricted` for nameplate casts (if not,
`interruptedBy` is a plain GUID and attribution is trivial).

## 3. Other combat-state techniques

| Technique | Where | What it gives | Forever |
|---|---|---|---|
| Kick-ready tick on enemy cast bars: positioner bar `SetValue(castDuration:GetElapsedDuration())` + marker bar anchored to its fill edge `SetValue(kickCD:GetRemainingDuration())`, tick at the second fill's edge = "your kick is ready here" | `EllesmereUINameplates/EUI_Nameplates_Cast.lua:404-500` | secret **addition** by anchoring; geometry, no Lua maths | `UnitCastingDuration`, `C_Spell.GetSpellCooldownDuration` (`SecretArguments = AllowedWhenTainted`) present |
| Cast bar tint from your kick's readiness: `C_CurveUtil.EvaluateColorValueFromBoolean(cdDuration:IsZero(), a, b)` | `EllesmereUI_Kick.lua:108-127` | secret boolean -> colour component | present (`AllowedWhenTainted`) |
| Non-interruptible / important cast overlays: `SetAlphaFromBoolean(notInterruptible)` from `UnitCastingInfo` | `EUI_Nameplates_Cast.lua:77-107, 382` | secret bool -> visibility | `UnitCastingInfo` `SecretWhenUnitSpellCastRestricted` |
| Per-spell secrecy predicates: `C_Secrets.ShouldSpellAuraBeSecret(id)` per rank, re-asked each frame; read the aura only if every rank is non-secret | `EllesmereUIRaidFrames/EUI_RaidFrames_ForeverMissingBuffs.lua:205-225`; `EUI_AuraBuffReminders_Auras.lua:30`; `EUI_CDM_HookIconWatch.lua:845` | knowing **in advance** whether a read will be plain, instead of read-then-`issecretvalue` | 21 predicates on Forever incl. `ShouldSpellCooldownBeSecret`, `ShouldUnitAuraInstanceBeSecret`, `ShouldUnitSpellCastBeSecret`, `ShouldUnitPowerBeSecret(unit, powerType)` |
| Global predicates `ShouldCooldownsBeSecret()` / `ShouldAurasBeSecret()` | `EUI_ActionBars_Disposal.lua:191`, `EllesmereUI_AuraKit.lua:2338` | mode switch per restriction state | present |
| Threat values read plain on Forever ("`ShouldUnitThreatValuesBeSecret` is false there"); `UnitDetailedThreatSituation(unit, mob)` per group token | `EllesmereUIForeverEssentials_ThreatData.lua:1-10, 102` | scaled %, raw %, raw threat per member | `SecretWhenUnitThreatValuesRestricted`; their field claim: not restricted on Forever |
| Damage meter as an event source (`DAMAGE_METER_*`), NeverSecret row fields, sorted order | `KickEngine.lua` above; `EllesmereUIDamageMeters/` | landed-event timing and attribution | present (our note) |
| Blizzard Cooldown Viewer frames hooked: `TriggerAvailableAlert` (exact ready edge; "the client sends NO event when a cooldown runs out"), icon `SetDesaturated` (on-cooldown visual), `SetCooldownFromDurationObject`, `OnCooldownIDSet` | `EUI_CDM_HookIconWatch.lua:225-260`; `EUI_CDM_HookDecorate.lua:1024-1041, 1207`; `EUI_CDM_HookViewers.lua:162` | cooldown-ready edges without reading a duration | CDM addon loads on Forever; whether the Forever viewer has these mixins/methods is untested (our cooldownviewer note: items present) |
| Clean booleans at event time: `GetSpellCooldown().isActive` and `isOnGCD`, `GetSpellCharges().isActive` | `EUI_CDM_HookIconWatch.lua:9-22` | ready/not ready without duration maths | plain status bools per their notes; durations secret in instances |
| `C_AssistedCombat.GetNextCastSpell()` (Blizzard rotation helper) to glow action buttons / a rotation icon | `EUI_CDM_Rotation.lua:275`; `EllesmereUICdmRotationIcon.lua:144`; `EUI_ActionBars_Events.lua:169` | Blizzard's own next-spell suggestion | documented on Forever (`AssistedCombatDocumentation.lua:20`) but our gate spike found it unavailable |
| Engine-animated timers: `StatusBar:SetTimerDuration(durationObject)`; `Cooldown:SetCooldownFromDurationObject` | `KickBars.lua:12-14`; `EllesmereUI_ManaRegenSpark.lua` | animation with no Lua per frame and no secret read | present |
| Mana cost overlay: max mana and cost only into `SetMinMaxValues`/`SetValue` | `EllesmereUI_SpellCostPrediction.lua:1-30` | display of secret mana | Forever only |
| Five-second-rule spark from cast events + spell cost type, `UNIT_POWER_UPDATE` only as a keep-alive ("Mana is SECRET") | `EllesmereUI_ManaRegenSpark.lua:1-30` | regen windows without reading mana | Forever only |
| `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)` into `SetFormattedText` | `EllesmereUINameplatesFriendly.lua:1428` | secret % to text | present |
| Range: `C_Spell.IsSpellInRange` ladders, Forever rank/form aware | `EllesmereUI_Range.lua:104-248` | in range | present |
| Restriction edges: `ADDON_RESTRICTION_STATE_CHANGED` + `C_RestrictedActions.IsAddOnRestrictionActive(type)` | `KickEngine.lua:348-357, 1509` | when reads turn plain again | present |
| Secure proxies (menus, targeting) via `SecureActionButtonTemplate` + `/click` macro transport | `EllesmereUI_Kick.lua:136-300` | UI plumbing, not state | n/a |

## 4. What we could adopt

Constraint: secrets flow only from Sources to the gate; Engine/Model never see one. Each idea below keeps that.

1. **`C_Secrets` predicates as a Source-side pre-check.** Ask `ShouldSpellAuraBeSecret(id)`,
   `ShouldSpellCooldownBeSecret(id)`, `ShouldUnitPowerBeSecret("player", type)` (all plain bools) before reading, and
   record per spell whether the read can be trusted this frame. Cheaper and more honest than read-then-test, and it
   tells us which player auras/cooldowns stay plain on Forever in combat. First step: a probe dumping these for our
   tracked spells in and out of combat.
2. **The StatusBar comparator for display-only conditions.** Where the APL only needs "show/hide this icon if secret
   `x` >= `k`" (target health execute window, a resource threshold), the gate can draw it: bar
   `SetMinMaxValues(0, x)`, `SetValue(k)`, clip anchored to the fill edge. Lua never learns the answer, so it cannot
   feed the simulation, but it can veto or glow a recommendation at render time without flicker from a model guess.
   Complements, does not replace, the curve-gated alpha we already proved.
3. **Threat values on Forever.** If `UnitDetailedThreatSituation` really returns plain values there (their Forever
   addon depends on it), tank and threat-capped DPS logic can read scaled threat percent instead of the 0-3 situation
   we use (`Engine/Schema/Threat.lua`). Needs one in-combat probe with `C_Secrets.ShouldUnitThreatValuesBeSecret`.
4. **Ready edges from the Cooldown Viewer** (`TriggerAvailableAlert` hook) if the Forever viewer has it: an exact
   "cooldown just ended" event, which our model now infers.
5. **Interrupt as a recommendation input** (if we ever recommend kicks): our own `interrupt` ability only needs the
   enemy cast state; `UNIT_SPELLCAST_INTERRUPTED` with `interruptedBy` on target/nameplates tells us a cast was kicked
   by someone (secret GUID compared to nil only, as they do) so we can stop recommending our kick.

## 5. What we already do better (for a rotation helper)

- We need our own state, not the group's: player casts and power are plain or modelled, so the damage-meter
  attribution machinery (row order, list lengths) is overkill for us; our damagemeter note already uses the update
  event as a landed-hit clock, which is the part that matters for a predictor.
- Our engine is headless and tested (busted, Facade); theirs is display logic that cannot be tested off-client.
- We read `C_Spell.IsSpellUsable` (plain on Forever) for resource gating; they avoid power entirely.

## 6. Open questions

1. Is `SecretWhenUnitSpellCastRestricted` active for enemy nameplate casts in Forever open world and dungeons? If not,
   `interruptedBy` and `UnitCastingInfo` are plain and the whole gate machinery is unnecessary on Forever.
2. Which of our tracked spells answer `ShouldSpellAuraBeSecret`/`ShouldSpellCooldownBeSecret` = false in combat?
3. Is threat really plain on Forever in combat (`ShouldUnitThreatValuesBeSecret("player", "target")`)?
4. Does the Forever Cooldown Viewer have `TriggerAvailableAlert` and `OnCooldownIDSet`?
5. `C_AssistedCombat` is documented on Forever; is `IsAvailable()` still false at 1.60.1.70338?
