# Modern display: the client routes for each overlay (desk research)

Date 2026-10-29. Branch `forever-modern-research` from `forever` 21ad62d12. Docs only; no addon code changes; no
in-game probe (launch is 2026-11-04). Question (owner, "do a modern display research track"): for each of the six
overlays of the Modern proposal (`modern-display-brief.html`, 2026-10-25), which client call gives the hidden value,
how secret it is, which frame property accepts it, how Blizzard's own UI does it, and how sure we are. The design that
builds on this is `docs/superpowers/specs/2026-10-29-modern-display-design.md`.

Sources: the Forever generated docs `Blizzard_APIDocumentationGenerated/` read through the `wow` MCP server (flavor
`forever`): `UnitDocumentation.lua` [UN:line], `SpellDocumentation.lua` [SP:line], `SimpleStatusBarAPIDocumentation.lua`
[SB:line], `SimpleRegionAPIDocumentation.lua` [RG:line], `SimpleFrameAPIDocumentation.lua` [FR:line],
`FrameAPICooldownDocumentation.lua` [CD:line], `LuaDurationObjectAPIDocumentation.lua` [DO:line],
`LuaCurveObjectAPIDocumentation.lua` [CO:line], `CurveUtilDocumentation.lua` [CU:line], `SecretPredicatesDocumentation.lua`
[PR:line]; the Forever UI source: `Blizzard_ActionBar/Shared/ActionButton.lua` [AB:line],
`Blizzard_AuraContainer/Blizzard_CustomAuraButton.lua` [CAB:line], `Blizzard_EncounterTimeline/EncounterTimelineTimerEvent.lua`
[ET:line], `Blizzard_SharedXMLBase/CurveConstants.lua` [CC:line], `Blizzard_UnitFrame/Shared/CompactUnitFrame.lua`
[CUF:line], `Blizzard_UnitFrame/Mainline/UnitFrame.lua` [UF:line]. Measurements: the gate spike
(`TacoDogForever/docs/spikes/2026-10-gate-spike-findings.md`) [GS], probe session W
(`docs/research/tdf/2026-10-13-probe-session-W-results.md`, PR rows) [W PRn], the Cooldown Manager research
(`docs/research/2026-10-23-cooldown-manager-api.md`) [CV §n]. Hekili code at 21ad62d12.

Confidence labels: **CONFIRMED** (the raw doc allows it and Blizzard code or our own measurement does it),
**LIKELY** (the raw doc allows it and the same mechanism is measured on a neighbouring value), **PROBE** (needs the
launch-day client).

## 0. Verdict

| # | Overlay | Route | Label |
|---|---|---|---|
| 1 | True-cost dimming | `C_Spell.IsSpellUsable` second return (plain, never secret) → our own vertex colour or alpha; no curve | **CONFIRMED**, and already shipped in Classic and Timeline |
| 2 | Execute window from real health | `UnitHealthPercent("target", true, stepCurve)` → `Region:SetAlpha` on a border | **LIKELY** (GC-T health run settles it) |
| 3 | True cooldown swipes | `C_Spell.GetSpellCooldownDuration` → `Cooldown:SetCooldownFromDurationObject` | **CONFIRMED** |
| 4 | Truth strip | `UnitPower("player", type)` → `StatusBar:SetValue`; ticks and the estimate marker are plain | **CONFIRMED** (docs and Blizzard code); our tainted call measured only by GC-T's bar row |
| 5 | Timeline riding real cooldowns | duration object `EvaluateRemainingDuration(clampCurve)` → `StatusBar:SetValue`, lane icon anchored to the fill's right edge | **PROBE** (GC-T plus MD-TL) |
| 6 | Proc confirmation | Cooldown Manager presence bit (plain) or `IsSpellUsable` (plain) → our own glow | **CONFIRMED** (route measured; coverage per aura unknown) |

Three findings change the proposal:

1. **Overlay 1 is not new.** `UI/Resolve.lua:94-96` already asks `C_Spell.IsSpellUsable` per record and keeps
   `insufficientPower` as `r.usable`; Classic greys an unaffordable icon (`UI/Styles/Classic.lua:1069`) and so does
   Timeline (`UI/Styles/Timeline.lua:860`). That answer is the game's own, plain in combat [GS; W PR14]. The proposal's
   "Classic shows Mortal Strike ready at 24 rage" does not happen today, except for up to one 0.2 s range pulse
   (`Classic.lua:50`, `TOOLTIP_UPDATE_TIME`). What Modern can add is speed (the `SPELL_UPDATE_USABLE` edge rather than
   the pulse) and a clearer look, not truth.
2. **The curve input is a 0-1 fraction**, not 0-100: [W PR20] (only the 0-1 pair lit) and Blizzard's own constants
   ("re-scales any percentage value from [0, 1] to [0, 100]" [CC:8-12]). The gate spike's "likely 0-100" is superseded.
   GC-T still runs both scales.
3. **Every secret read needs a new facade class.** `tools/check_api_reads.sh` forbids any game read outside
   `ns.Facade`, and the facade answers `UnitPower` with the belief (`hybrid`, `Game/API/Facade.lua:233-264`) and
   `UnitHealth` with the model (`virtual`, :291). Modern needs the raw client answer, secret, routed into a widget and
   nowhere else (design spec §4).

## 1. The building blocks

| Call | Secrecy (raw doc) | Notes |
|---|---|---|
| `C_CurveUtil.CreateCurve()`, `CreateColorCurve()` | none [CU:11-31] | load time; allocate once |
| `curve:SetType(Enum.LuaCurveType.Step)`, `AddPoint(x, y)` | `AddPoint`: `SecretArguments = "AllowedWhenUntainted"` [CO:11-19] (our points are plain) | `Step` snaps, `Linear` interpolates (`LuaCurveType`); an empty curve answers 0 [CO:25] |
| `C_CurveUtil.EvaluateColorValueFromBoolean(bool, ifTrue, ifFalse)` | `SecretArguments = "AllowedWhenTainted"` [CU:49-65] | a secret boolean to an alpha |
| `Region:SetAlpha(a)`, `Frame:SetAlpha(a)` | `AllowedWhenTainted`, adds the Alpha aspect [RG:123-134; FR:1134-1145] | measured: a secret curve result is accepted, in and out of combat [GS Q1; W PR20, PR21] |
| `Region:SetAlphaFromBoolean`, `SetVertexColorFromBoolean` | `AllowedWhenTainted` [RG:134-205] | GC-T's `b<t>` row |
| `Region:SetVertexColor(r, g, b, a)` | `AllowedWhenTainted`, adds VertexColor and Alpha [RG:191] | a colour curve's result can go here |
| `Frame:SetShown(bool)` | `IsProtectedFunction`, `AllowedWhenUntainted` [FR:1484] | **not** a route for a secret from addon code |
| `StatusBar:SetMinMaxValues(lo, hi, interp)`, `SetValue(v, interp)` | `AllowedWhenTainted`, adds the BarValue aspect; `interpolation` `NeverSecret` [SB:229-240, SB:355-365] | `ExponentialEaseOut` eases the bar toward the target (`StatusBarInterpolation`) |
| `StatusBar:SetTimerDuration(duration, interp, direction)` | `AllowedWhenUntainted` [SB:334-344] | the argument is a duration object, not a secret value; `RemainingTime` or `ElapsedTime` |
| `StatusBar:GetValue()`, `GetMinMaxValues()`, `GetInterpolatedValue()` | `SecretReturnsForAspect` BarValue [SB:22-51, SB:162-174] | never read back what we wrote |
| `Cooldown:SetCooldown(start, dur)` | `AllowedWhenUntainted`, protected [CD:281-295] | measured: rejects secret numbers from addon code [W PR11]; plain numbers fine [W PR22] |
| `Cooldown:SetCooldownFromDurationObject(d, clearIfZero)` | `AllowedWhenUntainted`, protected [CD:308-320] | measured: works in combat [W PR28] |
| `C_Spell.GetSpellCooldownDuration(spell, ignoreGCD)` | `MayReturnNothing`, no `SecretWhen*`; a userdata [SP:327-343] | its getters are secret in combat (125/125); allocates 56 B per call [W PR11, PR28] |
| `C_Spell.GetSpellChargeDuration(spell)` | as above [SP:274-289] | the recharge, for charge spells; unprobed |
| `duration:EvaluateRemainingDuration(curve, modifier)`, `EvaluateRemainingPercent` | `SecretWhenCurveSecret`, `AllowedWhenUntainted` [DO:73-105] | the remaining seconds (or fraction) through a curve; secret result in combat |
| `duration:HasSecretValues()` | `ReturnsNeverSecret` [DO:351-362] | plain: "is this one secret" |

The secrecy predicates [PR:90-150]: cooldowns are secret "when combat, encounter, challenge mode, or PvP match addon
restrictions are in effect" (`SecretWhenCooldownsRestricted`); power is secret "for power types not explicitly flagged as
being never secret" (`SecretWhenUnitPowerRestricted`; energy and rage measured secret even out of combat [GS]); the
maximum is secret only when "the unit isn't player-controlled" (`SecretWhenUnitPowerMaxRestricted`), so the player's
`UnitPowerMax` is plain (100 for rage [W PR16]).

`Enum.SecretAspect` has no layout aspect (Shown, Alpha, VertexColor, BarValue, Cooldown, ... but nothing for points or
rects), so what `GetRight()` of a child anchored to a secret-filled bar returns is not documented. GC-T reads it
(`clipW`, `clipR`); Modern must never read it either way (design spec §3.3).

## 2. Per overlay

### 2.1 True-cost dimming — CONFIRMED (shipped)

- **Hidden value:** whether the player can pay the cost now. Not hidden: `C_Spell.IsSpellUsable(spell)` returns
  `isUsable, insufficientPower` and carries no `SecretWhen*` flag at all [SP:980-990]. Measured plain in combat for
  every sample, `insufficientPower` flipping exactly when the resource runs short, on Warrior and Rogue [GS], and it is a
  facade passthrough (`Facade.lua:908`, "plain [W PR14; SU]").
- **Frame property:** none secret. Our own `Texture:SetVertexColor` or `SetAlpha` with plain numbers.
- **Hekili today:** `ns.UI.Resolve` (`UI/Resolve.lua:94-96`) on every drawing frame; Classic dims in its range pass
  (`Classic.lua:1058-1073`, every 0.2 s), Timeline on its draw (`Timeline.lua:860`). The belief already consumes the same
  answer as its resource ladder (`Game/State/Sources/Power.lua:20-50`, `SPELL_UPDATE_USABLE` at :63).
- **Blizzard:** the action bars colour a button from `C_ActionBar.IsUsableAction`'s `isUsable, notEnoughMana` [AB:726, AB:1477], the same pair.
- **Curve fallback (not needed):** `UnitPowerPercent("player", type, false, stepCurve)` with the step at
  `cost / UnitPowerMax` (both plain) into `SetAlpha` is measured [W PR20]. It would only matter for a spell whose
  usability answer ignores the cost, and none is known.
- **What Modern adds:** the edge, not the truth: redraw on `SPELL_UPDATE_USABLE` (the display does not register it today:
  `UI/UI.lua:1267-1270` are commented out) instead of waiting for the pulse; and one "not yet" look on the press icon.

### 2.2 Execute window from real health — LIKELY

- **Hidden value:** target health. `UnitHealth` is `SecretReturns` always [UN:1526-1530]; measured secret in and out
  of combat [GS; W PR14]. `UnitHealthPercent(unit, usePredicted = true, curve)` is `SecretReturns`,
  `SecretWhenCurveSecret`, `AllowedWhenUntainted` for its arguments, returns `LuaCurveEvaluatedResult`, documented
  "can be scaled via a curve for display purposes" [UN:1506-1523]. Its unit type is
  `UnitTokenPvPRestrictedForAddOns`: fine on mobs, check in PvP.
- **Frame property:** `Region:SetAlpha(result)` on a border texture [RG:123-134], with a step curve
  `(0, 1), (g, 1), (g + ε, 0)` where `g` is the pack's `healthGate` (a 0-1 fraction already declared on Warrior Execute,
  `Hekili_Warrior/Warrior.lua:1224`, and Paladin Hammer of Wrath, `Hekili_Paladin/Paladin.lua:447`).
- **Evidence:** the same call shape on power (`UnitPowerPercent` + step curve → `SetAlpha`) is measured in and out of
  combat with no error [W PR20]. Health through a curve is not measured: GC-T's health run is exactly this (`a<t>/1`
  rows).
- **Blizzard:** no Forever (or mainline) Blizzard file calls `UnitHealthPercent` with a curve; health bars feed
  `UnitHealth` into `StatusBar:SetValue` (`UF:837`). So "LIKELY", not "CONFIRMED".
- **Player value, honestly:** for Execute and Hammer of Wrath the client's usability answer already flips at the
  threshold (the target-health design, `docs/superpowers/specs/2026-10-16-target-health-design.md` §1), and Hekili
  recommends from it. The border adds the window while the ability is short of rage (usability says "short", not
  "in range") and for any future pack ability whose bonus below a threshold is not a usability gate. Smaller than the
  proposal claims.

### 2.3 True cooldown swipes — CONFIRMED

- **Hidden value:** the spell's remaining cooldown. `C_Spell.GetSpellCooldown` is `SecretWhenCooldownsRestricted`
  [SP:309-325]; `startTime` and `duration` secret in combat, `isActive` / `isOnGCD` `NeverSecret` [W PR4, PR11; CV §3].
- **Route:** `C_Spell.GetSpellCooldownDuration(spellID, ignoreGCD)` [SP:327-343] → `Cooldown:SetCooldownFromDurationObject(d)`
  [CD:308-320]. Measured: works in combat; `SetCooldown` with the secret numbers is rejected ("bad argument #2") [W PR11,
  PR28]. Charge spells: `GetSpellChargeDuration` [SP:274-289], same shape, unprobed.
- **Blizzard:** aura buttons drive their swipe this way (`cooldown:SetCooldownFromDurationObject(auraDuration,
  clearIfZero)` [CAB:603]); the action bars pass the secret numbers to `SetCooldown` from untainted code, gated by the
  plain `isActive` [AB:867-911].
- **Cost:** 56 B per `GetSpellCooldownDuration` call [W PR28]. Fetch on a change only (the record's spell changes,
  `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`), never per frame; the Cooldown widget animates itself.
- **Hekili today:** Classic and Timeline swipe from the facade's modelled `GetSpellCooldown` (`Classic.lua:27-33,
  501-554`), plain numbers. Classic's "extend" swipe (record 1 stretched to Hekili's `exact_time`) is a prediction, not a
  cooldown; it stays as it is and is drawn only when the real cooldown is not running (design spec §3.4).

### 2.4 Truth strip — CONFIRMED

- **Hidden value:** the player's power. `UnitPower` is `SecretWhenUnitPowerRestricted` [UN:2734-2737]; secret for
  rage and energy even out of combat [GS].
- **Frame property:** `StatusBar:SetMinMaxValues(0, UnitPowerMax("player", type))` (plain) and
  `StatusBar:SetValue(UnitPower("player", type))` (secret, `AllowedWhenTainted` [SB:355-365]). The ticks (each queued
  record's `cost` over the same plain max) and the estimate marker (record 1's `resources[resource_type]`, the belief)
  are plain textures placed by our own arithmetic.
- **Blizzard:** `CompactUnitFrame_UpdatePower` does `powerBar:SetValue(UnitPower(...))` [CUF:758], the unit frames
  `statusbar:SetValue(currValue)` [UF:968]: untainted code. Our tainted call is the GC-T bar row; the doc flag is the
  same `AllowedWhenTainted` as `SetAlpha`, which is measured, so the risk is low.
- **Never:** read `GetValue`, the fill texture's width, or the marker's overlap with the fill.

### 2.5 Timeline riding real cooldowns — PROBE

- **Hidden value:** the remaining cooldown of a lane record's spell, as a position.
- **Route A (proposed):** hold the record's duration object (§2.3); each frame `SetValue(d:EvaluateRemainingDuration(clamp))`
  on a lane-length StatusBar with min/max `0, 1`, where `clamp` is the linear curve `(0, 0), (H, 1)` and `H` the lane's
  horizon in seconds; the bar's fill edge then sits at `remaining × pxPerSec`, whatever the secret total. The lane icon is
  anchored to the fill texture's `RIGHT` (`bar:GetStatusBarTexture()`), so the client moves it.
  **Never earlier than Hekili:** the bar starts at Hekili's own predicted x for that icon and its minimum is that
  prediction's fraction; a StatusBar clamps a value below its minimum to an empty fill, so the edge sits at
  `max(predicted, real)`. The icon can only arrive later than Hekili said, never sooner.
- **Route B:** `SetTimerDuration(d, interp, RemainingTime)` [SB:334-344] needs no per-frame call, but its fill fraction is
  remaining / total, so the bar width would need the total, which is secret in combat. Usable only with Hekili's
  modelled length, which reintroduces the estimate. Rejected for the lane; fine for a fixed-size cooldown bar.
- **Blizzard:** the encounter timeline does Route B's shape: `timerBar:SetTimerDuration(...)` [ET:755] and a spark
  anchored `CENTER` to `GetStatusBarTexture()`'s `RIGHT` [ET:666]. Untainted code, and its durations may be plain.
- **Unknowns, all probe:** a secret `SetValue` from tainted code (GC-T bar row); a child anchored to a secret fill edge
  moves (GC-T `clip<t>` row, the EllesmereUI comparator shape); the clamp below the minimum holds for a secret value;
  `EvaluateRemainingDuration` with a plain curve on a secret duration is allowed and allocates nothing (MD-TL below).
  The PR27 spike (an anchored now-line driving a moving icon, plain values) showed no visible gap [W PR27].

### 2.6 Proc confirmation — CONFIRMED (route), coverage unknown

- **Hidden value:** whether the proc aura is up. Player auras applied in combat are unreadable to addon code [GS Q2;
  CV §2].
- **Route 1, Cooldown Manager:** the viewer item's `auraInstanceID` is secret while the aura is up and nil while down,
  so `issecretvalue(id) or id ~= nil` is a plain presence bit; `HookScript` OnShow/OnHide fire 3-4 ms after the edge
  [CV §2]. Built: `Game/State/Sources/Presence/CooldownViewer.lua` behind the providers switch (off by default). No
  secret reaches a frame: our own glow from a plain bit.
- **Route 2, usability:** a proc that gates a spell's usability (Overpower after a dodge, Victory Rush) flips
  `IsSpellUsable` plainly [GS: `u_op` true after dodges]; Resolve already reads it per record. No Cooldown Manager
  dependency.
- **Route 3, overlay glow:** `C_SpellActivationOverlay.IsSpellOverlayed` is plain [W PR11] and Resolve already turns it
  into `r.glow`; no proc fired in the probe, so whether Forever raises overlays for any proc is unknown.
- **Coverage:** Route 1 needs the user's Cooldown Manager enabled and the aura in the class's default sets (CV §4,
  the coverage tool `tools/check_cooldown_viewer.lua`); probes CDM-T (taint) and CDM-E/CDM-C (edges, coverage) are
  already in the kit.

## 3. Launch-day probes

Ready for the kit (`~/src/ForeverProbe/docs/launch-day.md`, one row each; not added here). GC-T exists
(`ForeverProbe/Gate.lua`, `/vslog gate health|power`); the MD rows are new. "Pass" is what Modern needs; anything else
keeps that overlay off.

| Id | Kind | Class | Where | What to do | Pass | Fail means |
|----|------|-------|-------|------------|------|------------|
| GC-T | auto + manual | any | open-world mob | as in the kit | (a) `GATE_CALL SetAlpha ok` with no `err` in the health run; the `a<t>/1` squares go dark exactly as the target's health bar crosses t (owner's eye); (b) `GATE_CALL SetValue ok` in both runs and the `bar<t>/1` fill follows the health or power bar; (c) `clip<t>/1` moves with the fill | (a) fail: overlay 2 off; (b) fail: overlays 4 and 5 off; (c) fail: overlay 5 off |
| MD-CD | manual | Warrior (Mortal Strike or Bloodthirst; Charge) | open-world mob | `/vslog md cd`: a button-sized Cooldown fed `GetSpellCooldownDuration(id, false)` on `SPELL_UPDATE_COOLDOWN`, next to the Hekili icon; fight, press the spell, let it come back | `MDCD set ok` every call; the swipe ends on the frame the plain `isActive` goes false (`MDCD end dt=` within ±1 frame); 0 B per frame between events | overlay 3 off for that kind (normal or charge) |
| MD-CH | manual | a charge spell (any class that has one) | open-world mob | as MD-CD with `GetSpellChargeDuration` | as MD-CD for the recharge | charge spells keep the modelled swipe |
| MD-TL | manual | Warrior | open-world mob | `/vslog md lane`: a 300 px bar, horizon 10 s, fed `EvaluateRemainingDuration(clamp)` each frame for a cooldown spell, a 16 px child anchored to the fill's RIGHT; a second bar with min = 0.3 (the clamp test) | no `err`; the child glides left and reaches the bar's left end on the frame `isActive` goes false (±1 frame); on the second bar the child stops at 30 % and waits; `collectgarbage("count")` flat over 600 frames | overlay 5 off (the lane stays Hekili's prediction) |
| MD-EASE | manual | any | open-world mob | `/vslog md ease`: GC-T's bar with `SetValue(v, ExponentialEaseOut)` | the fill eases (owner's eye), no `err` | the no-jitter rule falls back to "no secret gate on a flipping value" (design spec §3.2) |
| MD-USE | auto | Warrior and Druid | open-world mobs | none: record `SPELL_UPDATE_USABLE` time against the poll's `insufficientPower` flip for the spenders (Power.lua's ladder) | the event comes no later than the next poll in ≥ 95 % of flips | Modern's dim keeps the 0.2 s pulse (no loss against Classic) |
| MD-TAINT | manual | any | open-world mob, then a dungeon | `/console taintLog 1`, Hekili with one display on Modern, two pulls, `/reload` | `Logs/taint.log` names no Hekili frame; no "blocked" popup; the action bars and Cooldown Manager keep working | Modern stays developer-only until the culprit is found |
| MD-PVP | situation | any | a duel or battleground | GC-T health run on a player target | `UnitHealthPercent` read `ok` (the `UnitTokenPvPRestrictedForAddOns` arg) | overlay 2 off against players |

## 4. Open questions

- Does a Step curve treat a value exactly at a point as the upper or the lower side? It matters only to the 1 %
  boundary (`g` vs `g + ε`); GC-T's 20/40/60/80 rows show it.
- `UnitHealthPercent`'s `usePredicted` (default true) includes incoming heals on our target; for a hostile mob that is
  noise. Use `false`? GC-T uses true.
- Does `GetSpellCooldownDuration(id, false)` include the GCD as the action bars show it (the swipe after every press)?
  Modern wants the GCD on the press icon only (design spec §3.4).
- Encounter and challenge restrictions may make more of this secret, or refuse a call outright; MD-TAINT's dungeon pull
  and the existing CDM-I row cover it.
