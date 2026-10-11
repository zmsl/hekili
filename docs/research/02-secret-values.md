# R2: Secret values and the Feral input matrix (go/no-go gate)

Date: 2026-10-11 · Target: WoW Forever "Camelot" 1.60.1.70338 (TOC 16001), Midnight 12.x API.
Sources:
- `wow` MCP API index (flavor `forever`).
- Blizzard's generated API docs and UI source for **1.60.1.70338**, at
  `~/.cache/hated-wow-mcp/uisource/forever/Interface/AddOns/` (cited below as `forever:`).
- Catnip (local install, and `docs/api-research.md` on GitHub). Catnip code reuse is authorised by
  its author. Credit: Durts, https://github.com/DurtsGaming/Catnip.

Confidence tags used below:
- **[V]** verified in game by Catnip.
- **[D]** documented by the API annotations.
- **[H]** hypothesis, to be settled by the ForeverProbe run (`~/src/ForeverProbe`).

---

## Summary

- **Conditional GO.** A predictor *can* make branch decisions in combat, but not from the numbers
  Hekili is built on. Energy, combo points via `GetComboPoints`, every aura, every DoT and cooldown
  remaining time, and target health are secret in combat. They can be shown, but they can't be
  compared or used in maths.
- **These signals stay readable in combat:**
  - per-spell `C_Spell.IsSpellUsable` (*isUsable* and *insufficientPower*) **[D, partly V]**;
  - `GetSpellCooldown().isActive` and `.isOnGCD` (fields documented `NeverSecret`) **[V][D]**;
  - `C_Spell.GetSpellPowerCost` (which also exposes Clearcasting, because Shred's cost becomes 0) **[V]**;
  - the player's own `UNIT_SPELLCAST_SENT` and `_SUCCEEDED` with spell ID **[V]**;
  - `PLAYER_SWING` **[V]**;
  - `UnitPowerType` (Cat Form ⇔ Energy) **[V]**;
  - by Catnip's account, `UnitPower("player", Enum.PowerType.ComboPoints)` **[V, to re-check]**.
- **What must be rebuilt.** The resource and aura parts of the state model become
  *self-tracked* from cast events plus known durations: Rip, Rake and Faerie Fire on the target,
  the Tiger's Fury buff, and the Omen internal cooldown. Energy becomes a *band* (which abilities
  are affordable), not a number. Hekili's `energy.current`, `debuff.rip.remains` and similar values
  turn into estimates with error bars.
- **Unavailable to addons:**
  - `COMBAT_LOG_EVENT_UNFILTERED`: the event `HasRestrictions`, and the legacy reader
    `CombatLogGetCurrentEventInfo` exists only as a deprecation shim. The real reader moved to the
    secure environment.
  - A readable talent API.
- **`C_AssistedCombat.GetNextCastSpell` has no secrecy annotation.** If Forever populates it, it's
  a free readable "what would Blizzard press" signal. Whether it's available on Forever is unknown
  **[H]**.
- **What decides GO vs NO-GO is one probe run.** It has to confirm that `IsSpellUsable`,
  `UnitPower(ComboPoints)` and `GetNextCastSpell` return plain values in combat. If
  `IsSpellUsable` turns out secret, the predictor loses energy entirely, and the answer becomes
  NO-GO for anything beyond a cast-sequence timer.

## Findings

### How secrecy is declared

The generated API docs carry per-function and per-field secrecy flags. The `wow_api_search` output
only shows `secretArguments` and `secretReturns`, so read the raw docs for the rest:

| Annotation | Meaning | Count in docs |
|---|---|---|
| `SecretReturns = true` | always secret for addon code | 18 |
| `SecretWhen<X>Restricted = true` | secret while restriction X is active (combat, encounters, PvP). X is one of `CooldownsRestricted`, `UnitPowerRestricted`, `UnitAuraRestricted`, `UnitSpellCastRestricted`, `UnitHealthMaxRestricted`, ... | 7–21 each |
| `NeverSecret = true` (on a struct field) | that field stays plain even when the rest of the struct is secret | — |
| `HasRestrictions = true` (on an event) | addon access is restricted | — |
| no flag | not documented as ever secret | — |

`SecretArguments` (`AllowedWhenTainted`, `AllowedWhenUntainted`, `NotAllowed`) says whether a
function **accepts** secret arguments. It says nothing about whether it returns them.

The `SecrecyLevel` enum is `NeverSecret` (0), `AlwaysSecret` (1) and `ContextuallySecret` (2).
`C_Secrets.Get{PowerType,SpellAura,SpellCast,SpellCooldown}Secrecy` return it, and
`C_Secrets.Should*BeSecret` answers "right now". Catnip found every Druid spell at level 2 for aura
and cast, and found `ShouldCooldownsBeSecret()` already true inside `PLAYER_IN_COMBAT_CHANGED`
while `InCombatLockdown()` still read false. So a predictor should gate on `C_Secrets` or on
`issecretvalue()`, never on `InCombatLockdown()`.

### Feral input matrix

Column key: **IC** = readable in combat; **OOC** = readable out of combat (open world; in
battlegrounds auras are secret even out of combat, per Catnip).

| Input | IC | OOC | Derivable in combat? (how) | Verdict | Conf. |
|---|---|---|---|---|---|
| Energy (`UnitPower(p,3)`) | **No** (`SecretWhenUnitPowerRestricted`) | Yes | **Band only.** With per-ability `IsSpellUsable` and `insufficientPower`, plus real costs from `GetSpellPowerCost` (readable, includes talent cost reductions), you know energy ≥ cost for each ability. Spend order gives cost thresholds of roughly 30/35/40/45/60. Refine it by anchoring when a flag flips from false to true and adding a 20-per-2s tick model. The tick phase isn't observable; `UNIT_POWER_FREQUENT` fires but carries no readable amount. | Derivable (coarse) | D + H |
| Energy ≥ X for an ability | **Yes**, via `C_Spell.IsSpellUsable(id)`: no secrecy flag. Catnip saw it follow Clearcasting (Shred usable at cost 0). | Yes | Directly. `insufficientPower` separates "not enough energy" from "wrong form or no target". | Readable | D; V (in part) |
| Combo points, `GetComboPoints(p,"target")` | **No** (`SecretWhenUnitPowerRestricted`; BitW and Catnip saw it secret) | Yes | Display only | Display only | V |
| Combo points, `UnitPower(p, Enum.PowerType.ComboPoints)` | **Yes**, according to Catnip's api-research. Caveat: Forever CP don't reset on target death or target switch. | Yes | Readable value. Reset it yourself on `PLAYER_TARGET_CHANGED`, and confirm with cast events: a builder adds 1 (or 2 on a Primal Fury crit), a finisher sets it to 0. If it's secret after all: count it yourself from `UNIT_SPELLCAST_SUCCEEDED` (no hit/miss information without the combat log, so it will drift). | Readable (probably) | V (Catnip doc) + H |
| Cat Form | **Yes**: `UnitPowerType("player")` is Energy (no flag; Catnip "Readable"). `GetShapeshiftFormID()` is undocumented but Blizzard's own UI uses it. | Yes | `UPDATE_SHAPESHIFT_FORM`, plus a power-type check | Readable | V (power type); H (form ID) |
| Clearcasting (Omen of Clarity) | Aura: **No**. `GetSpellPowerCost("Shred")[1].cost == 0`: **Yes** | Yes | Cost 0 means the proc is up. `IsSpellUsable(Shred)` becomes true at any energy. A refresh while it's up is invisible. | Derivable (exact for up/down) | V |
| Tiger's Fury buff | **No** (all Druid auras secret; `ShouldSpellAuraBeSecret` true) | Yes | Self-timer: the TF `UNIT_SPELLCAST_SUCCEEDED` time plus the buff duration (6s in 1.6; learn it from an out-of-combat cast, when the aura is readable). The Cooldown Manager item's `IsShown()` gives a readable up/down if the user tracks it. | Derivable | V (secret) + H (timer) |
| Tiger's Fury cooldown | `isActive`/`isOnGCD`: **Yes** (`NeverSecret`). `startTime`/`duration`: **No** | Yes | `isActive and isOnGCD ~= true` means a real cooldown. Get the remaining time from a self-timer or from a length learned out of combat. | Readable (ready or not) | V + D |
| Rip / Rake / Faerie Fire on target | **No** (target auras secret; `UNIT_AURA` `updateInfo` fields secret) | Yes, for a target out of combat (rarely useful) | Self-timer from the cast's `UNIT_SPELLCAST_SUCCEEDED` plus the duration (Rip 12s, Rake 9s, FF 40s in 1.6; verify with `wowdb`), keyed by target GUID. **Confirming a hit:** for Rip, CP dropping to 0 shows it landed. For Rake, CP +1. Faerie Fire can't be confirmed. Lost by: dodge or parry (unseen without the combat log), target swap, dispel. | Derivable (approximate) | V (secret) + H |
| Rip / Rake remaining (exact) | **No** | Yes | Display only, through `CustomAuraContainerTemplate` / `SetDurationCooldown` | Display only | V |
| Ability cooldowns (generic) | Flags yes, times no (`SecretWhenCooldownsRestricted`) | Yes | Flags and learned lengths. `GetSpellCooldownDuration` returns a duration object, which is display-only. | Readable (flags) | V + D |
| GCD | `C_Spell.GetSpellCooldown(29515).isActive`: **Yes**. Length: no | Yes | Length learned out of combat (Cat GCD about 1.0s), then paired with the GCD start | Readable (flag) | V |
| Target health % | **No**: `UnitHealth` and `UnitHealthPercent` are `SecretReturns` (always secret). `UnitHealthMax` is `SecretWhenUnitHealthMaxRestricted` | Partly: `UnitHealth` is secret even out of combat, per docs | Curve to alpha for display. No execute logic. | Display only (or unavailable) | D |
| Enemy count (nameplates) | `C_NamePlate.GetNamePlates()`: no flag. `UnitCanAttack`: no flag. | Yes | Count plates whose unit `UnitCanAttack`. `NAME_PLATE_UNIT_ADDED`/`REMOVED` also work. Feral cat in 1.6 has no cat AoE, so low priority. | Readable (probably) | D + H |
| Swing timer | `PLAYER_SWING` duration: **Yes** (plain number) | Yes | Directly | Readable | V |
| Own cast events | `UNIT_SPELLCAST_SUCCEEDED`/`SENT` (player) with spellID: **Yes**. The event is annotated `SecretWhenUnitSpellCastRestricted`, which in practice applies to other units. Check with `issecretvalue` anyway. | Yes | — | Readable | V + D |
| `C_AssistedCombat.GetNextCastSpell(false)` | No secrecy flag; returns `spellID?` | Same | Directly, if available. Forever ships `Blizzard_ActionBar/Mainline/AssistedCombatManager.lua` gated `[AllowLoadGameType mainline]`. Forever's `[Family]` resolves to `Mainline`, so it probably loads, but whether Assisted Combat has Forever rotation data is unknown. | Unknown | D + H |
| `COMBAT_LOG_EVENT_UNFILTERED` | **No** | **No** | The event is `HasRestrictions`. The reader moved to `C_CombatLogSecure.GetCurrentEventInfo` (secure only). `CombatLogGetCurrentEventInfo` exists only as a deprecation shim to `C_CombatLog.GetCurrentEventInfo`, behind the `loadDeprecationFallbacks` CVar. Catnip: "removed from the addon API". | Unavailable | D + V (Catnip doc, source-based) |
| `UNIT_COMBO_POINTS` | Not in the Forever event index | — | Use `UNIT_POWER_FREQUENT` (`powerType` "COMBO_POINTS") or poll | Probably unavailable | D (absent) + H |
| Talents | No readable talent API (`GetTalentInfo` absent; `C_SpecializationInfo.GetTalentInfo` returns nil) | No | Indirectly: real costs from `GetSpellPowerCost`, real GCD and cooldown lengths learned out of combat. User toggles for the rest. | Unavailable (proxy) | V (Catnip/SpellTuner) |

### Can a predictor make branch decisions in combat? On what signals?

**Yes, from booleans and events, not from numbers.** A Feral predictor in combat can branch on:

1. **Affordability now**: `IsSpellUsable(x)` and `insufficientPower` for each cat ability.
   This replaces `energy.current >= cost`. **[D; needs probe]**
2. **Clearcasting up**: `GetSpellPowerCost(Shred)` cost is 0. **[V]**
3. **Combo points**: `UnitPower(player, ComboPoints)` (plain, per Catnip), reset on target change
   and cross-checked against finisher casts. If the probe shows it secret, use a cast-event counter.
   **[V/H]**
4. **Cooldown ready**: `isActive`/`isOnGCD` (`NeverSecret`) for Tiger's Fury, Faerie Fire (Feral)
   and the GCD. **[V]**
5. **DoT and buff up or refresh window**: self-timers started on `UNIT_SPELLCAST_SUCCEEDED`, with
   durations from game data. Approximate: misses are invisible. **[H]**
6. **Form**: `UnitPowerType == Energy` / `UPDATE_SHAPESHIFT_FORM`. **[V]**
7. **Optional oracle**: `C_AssistedCombat.GetNextCastSpell(false)`, if it's available and plain.
   **[H]**

Not usable for branching: exact energy, time-to-energy (pooling maths), exact DoT remaining, target
health (execute), and any combat-log-driven state (misses, procs on others, damage).

What this means for Hekili's engine: `state.energy` and `state.combo_points` are numeric and run
through `regen` simulation (`State.lua`). They would need a "band" representation, or a
feasibility-oracle mode in which `ready_time`/`time_to` for energy come from the usable flags at
t=0 and from the tick model for t>0. Auras need a self-tracked aura store fed by cast events, not
by `UNIT_AURA` scanning.

## Evidence

**API annotations.** These come from Forever's generated docs:
`forever:Blizzard_APIDocumentationGenerated/…` at 1.60.1.70338.

- `SpellDocumentation.lua:980`: `IsSpellUsable`, only `SecretArguments = "AllowedWhenTainted"`.
  No return secrecy.
- `SpellDocumentation.lua:309-313`: `GetSpellCooldown`, `SecretWhenCooldownsRestricted = true`.
- `SpellSharedDocumentation.lua:26,30`: `SpellCooldownInfo.isActive` and `.isOnGCD` are
  `NeverSecret = true`. `startTime`/`duration` aren't.
- `SpellDocumentation.lua:535-538`: `GetSpellPowerCost`, no return secrecy.
- `UnitDocumentation.lua:91-94`: `GetComboPoints`, `SecretWhenUnitPowerRestricted = true`.
- `UnitDocumentation.lua:2732-2735`: `UnitPower`, `SecretWhenUnitPowerRestricted = true`.
  Secrecy is per power type: `C_Secrets.ShouldUnitPowerBeSecret(unit, powerType?)`,
  `GetPowerTypeSecrecy(powerType)`.
- `UnitDocumentation.lua:2859-2862`: `UnitPowerType`, no return secrecy.
- `UnitDocumentation.lua:1526-1529`: `UnitHealth`, `SecretReturns = true`.
  `:1506-1510`: `UnitHealthPercent`, `SecretReturns = true`.
  `:1472-1475`: `UnitHealthMax`, `SecretWhenUnitHealthMaxRestricted`.
- `AssistedCombatDocumentation.lua:20-22`: `GetNextCastSpell`, `SecretArguments` only.
  `:44`: `IsAvailable` has no flags.
- `NamePlateDocumentation.lua:37`: `GetNamePlates`, no flags.
  `UnitDocumentation.lua:763-765`: `UnitCanAttack`, no return flag.
- `ActionBarFrameDocumentation.lua:904-907`: `C_ActionBar.IsUsableAction`, no return secrecy.
  It's an alternative to `IsSpellUsable` when the button is on a bar.
- `CombatLogDocumentation.lua:132-135`: `COMBAT_LOG_EVENT_UNFILTERED`, `HasRestrictions = true`,
  `CallbackEvent = true`.
- `UnitDocumentation.lua:4846-4847`: `UNIT_SPELLCAST_SUCCEEDED`,
  `SecretWhenUnitSpellCastRestricted`.
- `SecretWrapperConstantsDocumentation.lua:6-16`: the `SecrecyLevel` enum.

**Blizzard UI source.**

- `forever:Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua:4-18`: `CombatLogGetCurrentEventInfo`
  is only aliased when the `loadDeprecationFallbacks` CVar is set. The comment reads "Some functions
  have been relocated to the secure environment, for which no deprecation is (intentionally)
  provided."
- `forever:Blizzard_CombatLogProcessor/Blizzard_CombatLogProcessor.lua:105`: Blizzard reads the log
  through `C_CombatLogSecure.GetCurrentEventInfo()`.
- `forever:Blizzard_ActionBar/Blizzard_ActionBar.toc:21`:
  `[Family]\AssistedCombatManager.lua [AllowLoadGameType mainline]`. The file is present at
  `Blizzard_ActionBar/Mainline/AssistedCombatManager.lua:333`, where it polls
  `GetNextCastSpell(true)` on a timer and compares to the last ID. That's secure code, so it isn't
  proof of addon readability.
- `forever:Blizzard_ActionBar/Shared/ActionButton.lua:684` and `Blizzard_CooldownViewer/CooldownViewer.lua`
  (mainline copy at `:1225`) branch on `IsUsableAction`/`IsSpellUsable` for icon tinting, which is
  also secure code.

**Catnip (local install).**

- `SpellTiming.lua:5-6, 11-13`: in combat only `isActive`/`isOnGCD` are readable. GCD spell 29515.
- `OmenRing.lua:5-9, 57-68`: Clearcasting through Shred's cost going to 0, verified 2026-10-09.
- `ComboPoints.lua:56-57, 127`: `GetComboPoints` secret in combat (BitW). `UNIT_COMBO_POINTS`
  registration is wrapped and unverified.
- `Cooldowns.lua:291-303`, `Proc.lua:27-32`: auras can be secret out of combat (battlegrounds).
  Gate on `C_Secrets.ShouldAurasBeSecret()` and wrap reads in pcall.
- `CHANGELOG.md:15`, `:109`: Omen probe; "all Druid auras are secret in combat".
- `ShiftOrbs.lua:18-21, 253-319`: thresholds on secret power through `UnitPowerPercent` and a step
  curve to `SetAlpha` (display only; `curve:Evaluate(secret)` from Lua errors).

**Catnip api-research** (https://github.com/DurtsGaming/Catnip/blob/main/docs/api-research.md):
- "What's readable in combat → Combo points": `UnitPower("player", Enum.PowerType.ComboPoints)`
  is readable in combat, but Forever combo points are per-target.
- "Spell costs": `C_Spell.IsSpellUsable` follows it too (Shred usable at 0 cost).
- `UnitPowerType`: Readable.
- `COMBAT_LOG_EVENT_UNFILTERED`: "Removed from the addon API (source)".
- `ShouldCooldownsBeSecret` flips before `InCombatLockdown()` (2026-10-10).
- No readable talent API.

**Probe addon.** `~/src/ForeverProbe/` (`ForeverProbe.toc`, `ForeverProbe.lua`, `README.md`).
`/fprobe` logs every value above as plain, `"S"` (secret) or `"E:…"` (error) at 4 Hz and on events,
into `ForeverProbeDB`. It passed `wow_toc_validate` cleanly. `wow_lua_lint` (forever) reported
0 errors. Its 3 warnings are the intentional CLEU registration test, and `luac -p` passes.

## Open questions (settled by the probe run)

1. Are `C_Spell.IsSpellUsable` *isUsable* and *insufficientPower* plain booleans in combat, and do
   they track energy at the documented costs? **This is the gate.**
2. Is `UnitPower("player", ComboPoints)` plain in combat? Compare `upc` against `cp`, and
   `ShouldUnitPowerBeSecret(player, 4)` (`sCP`).
3. Is `C_AssistedCombat` available on Forever (`IsAvailable`, `failureReason`)? Does
   `GetNextCastSpell` return plain spell IDs, and are they sensible for 1.6 Feral?
4. Does `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` error or silently never fire? Does
   `UNIT_COMBO_POINTS` exist?
5. Are nameplate unit tokens and `UnitCanAttack` plain in combat?
6. Is `UnitHealth("target")` secret out of combat too (`SecretReturns` implies yes)?
7. Is `GetShapeshiftFormID()` present and plain?
8. What are the exact Rip, Rake, FF and TF durations and talent-modified costs on Forever? (Use
   R5's `wowdb`, plus out-of-combat aura reads.)
9. Does `UNIT_SPELLCAST_SUCCEEDED` fire for dodged or parried cat abilities? That decides whether
   self-timers need the combo-point confirmation.

## Confidence

- **High:** energy, `GetComboPoints`, auras and DoT timing are secret in combat (Catnip verified plus
  doc flags). Cooldown flags, `GetSpellPowerCost`, the swing timer and own cast events are readable
  (verified). The combat log is not addon-accessible (doc flags plus deprecation shim).
- **Medium-high:** `IsSpellUsable` is readable in combat. There's no return flag, and Catnip lists
  it under "readable in combat", but no logged in-combat boolean exists yet.
- **Medium:** `UnitPower(ComboPoints)` is readable (Catnip doc claim; the doc flag says
  "when restricted", and restriction is per power type).
- **Low:** `C_AssistedCombat` is usable on Forever. Nameplate counts are readable.
- **Overall go/no-go: conditional GO**, pending probe questions 1 and 2. If both come back plain,
  a feasibility-based Feral predictor is viable. If question 1 fails, NO-GO for a Hekili-style
  predictor.
