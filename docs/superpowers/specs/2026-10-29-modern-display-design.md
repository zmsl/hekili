# Modern display: the game's truth painted over Hekili's picks (design, 2026-10-29)

Status: DRAFT, awaiting owner review. Architectural (a new style, a new facade class): the owner approves it before any
plan. Branch `forever-modern-research` from `forever` 21ad62d12. Paths are under `src/Hekili/` unless they start with
`tests/`, `tools/` or `docs/`; line numbers as of 21ad62d12.

Research this rests on: "API", `docs/research/2026-10-29-modern-display-api.md` (the client route, secrecy and
confidence per overlay, and the launch-day probes GC-T and MD-*). The proposal it answers: `modern-display-brief.html`
(2026-10-25, owner-facing). "[GS Qn]" cites the gate spike (`TacoDogForever/docs/spikes/2026-10-gate-spike-findings.md`).

## 0. The owner's requirements

From the proposal the owner asked for a research track on (2026-10-29: "do a modern display research track"):

1. Modern is a new, opt-in renderer per display: Classic's layout plus overlays painted from the game's hidden truth.
2. Hekili still decides. Overlays dim, glow or redraw what Hekili suggested; they never swap in another ability.
3. Dim, never promote. When the truth and the estimate disagree, an overlay may say "not yet", never "press
   something else".
4. No jitter. The flicker rule (no-jittery-recommendations, 2026-10-20) applies to overlays too.
5. Classic stays untouched. Switching back is one click.
6. Display only. Nothing presses a button, and no secret enters Hekili's logic (architecture §1: secrets travel from
   one client call into one frame property).
7. Core generic: nothing named after a class or spell in core; pack facts (execute threshold, proc aura) come from packs.

## 1. What the research changed

API §0 in three lines:

- **True-cost dimming already ships.** `UI/Resolve.lua:94-96` reads `C_Spell.IsSpellUsable`'s plain
  `insufficientPower` per record, and Classic (`Classic.lua:1069`) and Timeline (`Timeline.lua:860`) grey an
  unaffordable icon. Modern can only make it faster (the usability edge rather than the 0.2 s pulse) and clearer.
- **The execute border mostly repeats the usability answer.** For the abilities that declare `healthGate` today
  (Warrior Execute, Paladin Hammer of Wrath) the client's usability already flips at the threshold and Hekili
  recommends from it. The border adds the window while the ability is short of resource.
- **Secrets need their own facade class.** The facade answers `UnitPower` with the belief and `UnitHealth` with the
  model, and `tools/check_api_reads.sh` forbids any read around it.

## 2. What ships first

Ranked by player value times confidence (API §0). The owner may reorder; launch data (the probe kit's snapshots of
estimate drift per class) can move the middle rows.

| Phase | Overlay | Confidence | Player value | Why here |
|---|---|---|---|---|
| 1 | True cooldown swipes (3) | CONFIRMED | high: every icon with a cooldown; the swipe players already trust from their bars | measured route, cheaper than today's swipe read (56 B per cooldown event against 520 B per `GetSpellCooldown` call on every drawing frame [GS Q5]) |
| 1 | Usability edge (1) | CONFIRMED | low to medium: the grey arrives within a frame instead of up to 0.2 s | plain signal, no secret at all |
| 1 | Proc confirmation from usability and overlay glow (6, routes 2-3) | CONFIRMED | medium: proc windows are where players doubt the addon | plain, already resolved per record (`r.usable`, `r.glow`) |
| 2 | Truth strip (4) | CONFIRMED by docs; tainted call on GC-T | high for testers (live estimate drift), medium for players | needs GC-T's bar row before it is on by default |
| 2 | Execute border (2) | LIKELY | low to medium (§1) | needs GC-T's health row |
| 3 | Proc confirmation from the Cooldown Manager (6, route 1) | CONFIRMED route, coverage unknown | medium, for buff procs that gate nothing | needs a record field (§5.3) and CDM-T's taint verdict |
| 3 | Timeline riding real cooldowns (5) | PROBE | medium: the near end of the lane becomes exact | needs GC-T and MD-TL, and a Timeline hook (§5.4) |

Phase 1 can be built before launch and stays opt-in; phases 2 and 3 are built only after their probe passes. An overlay
whose probe fails stays off in code (a constant per overlay, §6), not hidden behind an option.

## 3. The conflict rules, made precise

### 3.1 Hekili decides; dim, never promote

- **R1. Same picks.** Modern draws exactly the records the base style draws, in the same slots, with the same texture,
  caption, keybind, focus ring and indicators. It never writes a record field, never reorders, never hides a record and
  never shows an ability Hekili did not publish. A headless test compares Modern's slot assignment with the base
  style's for the same published sets (§7).
- **R2. Pressable only when both agree.** An icon looks pressable (full colour, no swipe, no dim) only when Hekili's own
  time has come (`exact_time` within 0.05 s, as `Output.lua:12` `READY`) and every truth overlay agrees. Each overlay may
  only take "pressable" away:
  - dim: alpha or vertex colour at or below the base style's;
  - swipe: the real cooldown is shown while it runs (plain `isActive and not isOnGCD`, API §2.3); once it has ended, a
    record Hekili still holds back keeps the base style's delay look (Classic's `delays.fade` / `desaturate` from
    `r.desaturate`, Timeline's countdown), so a real cooldown that ends early never makes the icon look ready before
    Hekili says so;
  - ride: a lane icon's position is `max(Hekili's x, the real cooldown's x)` (§5.4), so it can arrive later than
    predicted, never sooner.
- **R3. Confirm marks are additive and subordinate.** The execute border and the proc glow appear only on a record
  Hekili published, and never on an icon that is dimmed by a plain overlay (the dim is plain, so the border's texture is
  hidden by our own `Hide()` while dimmed; the secret alpha is only ever set on a shown texture). A mark never reaches a
  record that is not first in its display unless the option says so (`confirmQueue`, default off), so the eye stays on
  the press.

### 3.2 No jitter

Two kinds of input, two treatments.

- **Plain inputs** (usability, `isActive`, `isOnGCD`, the presence bit, `IsSpellOverlayed`): debounced in Lua. A
  change toward "less ready" (dim on, mark off) shows at once, because hiding readiness late is the costly error; a
  change back (dim off, mark on) shows only after the new state has held for `Output.hold` publishes (the steady slider,
  1-3, default 1) or `0.1 s`, whichever is shorter, unless `Output.Acted` bumped since (our own cast: show at once, as
  steady icons do). One preallocated `since[i]` timestamp and `state[i]` per button; no tables.
- **Secret inputs** (power, target health, remaining cooldown): Lua cannot see them, so it cannot debounce them. The
  rule is to only feed a secret where a flip cannot be seen as flicker:
  - continuous visuals only (the strip's fill, the swipe, the ride's motion): a value that moves back and forth moves a
    bar, it does not blink an icon;
  - a secret threshold gate (the execute border) only on a value that crosses its threshold about once a fight (target
    health); never a secret gate on power against a cost (that is what the plain usability answer is for);
  - where a gate must sit on a value that can hover, route it through a StatusBar with `ExponentialEaseOut`
    (`SetValue(v, interp)`, API §1) and draw the gate as the clipped child of the fill, so the client eases the edge.
    Only if MD-EASE passes; otherwise no such gate ships.
- **Lua-side inputs to a curve never jitter:** a button's curve and spell change only when its record's ability changes,
  which steady icons already hold (`Output.lua:120-145`).

### 3.3 Secret safety

- A secret comes from one `Facade.Display` call (§4) and goes straight into one widget method in the same expression:
  `bar:SetValue(Display.UnitPower("player", t))`, `border:SetAlpha(Display.UnitHealthPercent("target", false, curve))`,
  `cd:SetCooldownFromDurationObject(dur)`. No local holds a secret number; a duration object (userdata, not a secret
  value) may be held per button.
- Never read back an aspect we fed: `GetValue`, `GetMinMaxValues`, `GetAlpha`, `IsShown`/`IsVisible` of a gated widget,
  `GetCooldownTimes`, and no geometry (`GetRight`, `GetWidth`, `GetRect`) of a fill texture or of anything anchored to
  it, even if the client answers plain (API §1: no layout aspect is documented).
- Branches use plain values only: `isActive`, `isOnGCD`, `HasSecretValues()`, usability, presence.
- Nothing from `Facade.Display` reaches `d.resolved`, the engine, Snapshot, WeakAuras or the options.

### 3.4 The GCD on the swipe

`GetSpellCooldownDuration(id, ignoreGCD)` (API §2.3): the press icon (record 1) shows the GCD as the action bars do
(`ignoreGCD = false`); queued icons ignore it (`true`), so a queue does not sweep in unison after every press. Charge
spells use `GetSpellChargeDuration` for the recharge (MD-CH), and their swipe stays modelled until it passes.

## 4. `Facade.Display`: the secret-out class

A fourth facade class beside passthrough, hybrid and virtual (`Game/API/Facade.lua:1-10`): **display**, the raw call,
whose answer may be secret and is meant for a widget only.

- Rows (`tools/api_inventory.txt`, class `display`): `UnitPower` (player only; the hybrid row stays for the engine),
  `UnitHealthPercent`, `UnitPowerPercent`, `C_Spell.GetSpellCooldownDuration`, `C_Spell.GetSpellChargeDuration`,
  `C_CurveUtil.CreateCurve`. Exposed as `Facade.Display.UnitPower` etc., a separate table, so `Facade.UnitPower` keeps
  answering the belief and nothing else changes for its callers.
- Each row's `Why` text names the raw doc flag (API §1), as the other rows do.
- Check: `tools/check_api_reads.sh` gains one grep: `Facade.Display` (or `.Display.`) appears only in `UI/Truth.lua`.
  `tests/boundary_spec.lua` is unchanged (no content names).
- Trace: a display read writes no Snapshot line (it runs per frame and its answer is secret anyway); `Facade.QUIET`
  gains the rows.

## 5. Where it plugs in

### 5.1 A style that wraps the base style

`UI/Styles/Modern.lua`, registered as `modern` through `ns.UI.RegisterStyle` (`UI/Styles.lua:48`), `api = 1`. Its
`displays[id].modern.base` names the layout, `classic` or `timeline` (default `classic`). Every member delegates to the
base style's table (`ns.UI.Styles[base]`) with the same `d` and `conf`, then calls the truth layer:

| Member | Modern does |
|---|---|
| `Build(d, conf)` | `base.Build`, then `Truth.Build(d, conf, buttons)`: one overlay set per button, out of combat |
| `Tick(d, conf, out, now, elapsed)` | `base.Tick`, then `Truth.Tick` (strip value, ride values, debounce timers) |
| `Draw(d, conf, out, status)` | `base.Draw`, then `Truth.Draw` (per record: spell, swipe source, dim, marks) |
| `OnGameEvent(d, conf, event, ...)` | `base.OnGameEvent`, then `Truth.OnGameEvent` (`SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`, `SPELL_UPDATE_USABLE`, `UNIT_MAXPOWER`, `PLAYER_TARGET_CHANGED`) |
| `Clear`, `Perimeter`, `UpdateKeybindings` | base, plus `Truth.Clear` |
| `Options(id, conf)` | the base's tabs plus one "Modern" tab |
| `needs` / `NeedsFor` | the base's |

So Classic's file is not edited, and the player's existing Classic or Timeline layout carries over: Modern reads the
base's subtable (`conf.classic`, `conf.timeline`) through the base's own code. That is an exception to "no style reads
another style's subtable" (architecture §7), recorded as decision M2; the alternative is open question Q3.

The display must register the three usability and cooldown events (today commented out, `UI/UI.lua:1267-1270`):
registered only while a display is bound to `modern`, from `Truth.Build`.

### 5.2 The truth layer: `UI/Truth.lua`

The only file that calls `Facade.Display`. Per display, preallocated at `Build` for `SLOTS` (12) buttons:

- `ov[i].cd`: a second `Cooldown` frame over the base button's own (`CooldownFrameTemplate`, same draw settings); the
  base's `b.Cooldown` is hidden while `ov[i].cd` shows a real cooldown, and shown again otherwise (R2);
- `ov[i].dur`: the held duration object (nil when none), `ov[i].spell`: the spell it was fetched for;
- `ov[i].border`: the execute border texture; `ov[i].glow`: uses the base's glow helpers (LibCustomGlow, as Classic);
- `ov[i].dim`, `ov[i].since`: the debounce state (§3.2);
- the strip (one StatusBar, its tick textures `ticks[1..SLOTS]`, the estimate marker) per display;
- the ride bars (`ride[i]`, one StatusBar per lane slot) for a `timeline` base.

What it reads: `out.recs[i]` (`actionName`, `actionID`, `exact_time`, `cost`, `resource_type`, `resources`),
`d.resolved[i]` (`usable`, `glow`, `desaturate`), `Hekili.Engine.Registry.Abilities()[name]` for pack facts
(`healthGate`; `item` to skip items), `Output.hold`, `Output.Acted` through a getter. Nothing of `state.*`, `class.*`
or VirtualState (`tools/check_engine_reads.sh` already enforces it for `UI/`).

When it fetches a duration object: when a button's record changes spell, and on `SPELL_UPDATE_COOLDOWN` /
`SPELL_UPDATE_CHARGES` for the shown spells; never in `Tick`. The plain `isActive` / `isOnGCD` come from the facade's
existing `C_Spell.GetSpellCooldown` row, which already reads the plain flags (`Facade.lua:660-669`).

### 5.3 The subscription channel

No engine change for phases 1-2: Modern subscribes through core's display binding as any style does
(`Engine.Subscribe`, `Engine/Output.lua:237`; `bindStyle`, `UI/UI.lua:1081`). Every field it reads is already on the
record (architecture §7 "What a style may read").

Phase 3's Cooldown Manager confirmation needs the presence bit on the record, because a style may not read the belief.
Proposed: a game-side annotator (`Output.Annotate`, `Engine/Output.lua:288`, unused today) writes `rec.confirmed`
(nil: no fact; true: up; false: down) for a record whose ability declares the new optional pack field
`confirmAura = "<aura key>"`, answered by the presence router (`Game/State/Sources/Presence/Router.lua`). A new record
field bumps `Hekili.DisplayStyleAPI` to 2 (architecture §7). Open question Q4.

### 5.4 The Timeline ride (phase 3)

For a lane record whose real cooldown is running (plain `isActive and not isOnGCD`) and whose spell has a duration
object, Truth shows `ride[i]`, a StatusBar laid along the lane from Hekili's own predicted x for that record
(`laneX0 + pred × pxPerSec`, `pred = exact_time - now`) to the lane's end, with `SetMinMaxValues(pred / H, 1)` and, each
`Tick`, `SetValue(dur:EvaluateRemainingDuration(clamp))`, where `clamp` maps `0..H` seconds to `0..1` linearly (API
§2.5 Route A). A value below the minimum leaves the fill empty, so the fill's right edge sits at
`laneX0 + max(pred, real) × pxPerSec`. The lane cell is anchored to `ride[i]:GetStatusBarTexture()`'s `RIGHT`.

Timeline today places lane cells itself every frame (`moveLane`, `Timeline.lua:469-493`, `place` at :134). The ride
needs one hook in Timeline: skip `place` for a cell whose `b.rideAnchored` is set (one line in `moveLane`, plus the flag
cleared in `assign`). That touches Timeline, not Classic; requirement 5 holds. When the real cooldown ends (plain
event), the cell goes back to `place` at Hekili's x, which by R2 is at or after the ride's last x, so no backward jump
beyond the glide.

## 6. The curve set, built at spec load

Built in `Truth.Build` and on `PLAYER_SPECIALIZATION_CHANGED` / pack load (out of combat; `C_CurveUtil.CreateCurve`
allocates), kept in a file-scope table keyed by the plain parameter, and reused by every display:

| Curve | Points | Built for | Count |
|---|---|---|---|
| `gate[g]` | Step: `(0, 1), (g, 1), (g + 0.001, 0)`; input is a 0-1 fraction (API §0) | each distinct `healthGate` among the active pack's abilities | 1 today (0.2) |
| `clamp[H]` | Linear: `(0, 0), (H, 1)` | each Timeline display's horizon `H` (s) | one per display with ride on; `ClearPoints` + `AddPoint` on an option change |
| `ease` | none: easing is the StatusBar's | | 0 |

No curve for cost (the usability answer is plain), none for the strip (the raw value goes into the bar), none per
frame. Every `Tick` and `Draw` allocates nothing: no table, closure, string or curve; the only client allocation is
`GetSpellCooldownDuration`'s 56 B per cooldown event per shown spell (API §2.3), which Q7 asks the owner to accept.

Overlay switches that depend on a probe are constants in `Truth.lua`, set from the probe verdicts:
`VERIFIED = { strip = false, execute = false, ride = false, cdm = false }`, flipped by a commit that cites the
probe's result, not by a player option.

## 7. Options per display (`displays[id].modern`)

One "Modern" tab, built through `Hekili.StyleOptions` helpers where they exist. Defaults:

| Option | Default | Notes |
|---|---|---|
| `base` | `classic` | `classic` or `timeline` |
| `swipes` | on | real cooldown swipes |
| `edge` | on | redraw on the usability edge |
| `confirm` | on | proc glow from usability and overlay; `confirmQueue` off |
| `execute` | on, shown only while `VERIFIED.execute` | the border colour (gold) and width |
| `strip` | off, shown only while `VERIFIED.strip` | position (below / above), height; `stripEstimate` (the blue marker) on |
| `ride` | off, shown only while `VERIFIED.ride` and `base == timeline` | |

The style dropdown's label is "Modern (game truth)"; switching back to Classic is the existing dropdown (requirement 5).

## 8. What is testable where

**Headless (busted, beside `tests/Forever/display_style_spec.lua` and `display_resolve_spec.lua`, with the fake API's widgets recording calls):**

- R1: for recorded published sets (the harness fights), Modern's per-slot action and texture equal the base style's.
- R2: given fake plain flags, the swipe source per button (real when `isActive and not isOnGCD`, base otherwise), the
  dim state, and that no "pressable" look appears before `exact_time - READY`.
- Debounce: a usability flip back within the hold window does not undim; a flip after `Output.Acted` does at once.
- Requests: which spell each button fetches a duration for, with which `ignoreGCD`; that fetches happen only on the
  listed events and spell changes (counted), never in `Tick`.
- Secret flow: the fake `Facade.Display` returns a sentinel whose metatable raises on compare, arithmetic, concat and
  `tostring`; the test asserts it reaches only the allowed widget methods (`SetValue`, `SetAlpha`,
  `SetCooldownFromDurationObject`) and nothing else (the shape of `tests/Game/State/secrets_spec.lua`).
- Curves: built once per distinct parameter (count `CreateCurve` calls), reused across displays and redraws.
- Allocation: 0 B per `Tick` and `Draw` after the first publish (the bench's `collectgarbage("count")` pattern).
- Geometry (plain): tick x for each queued cost over the max; the estimate marker x; the ride bar's left and minimum.
- The `check_api_reads.sh` rule: a fixture file reading `Facade.Display` outside `UI/Truth.lua` fails it.

**In game only (launch day and after):** that the client paints each route (API §3: GC-T, MD-CD, MD-CH, MD-TL,
MD-EASE), taint (MD-TAINT), the usability edge timing (MD-USE), PvP (MD-PVP), and a checklist per overlay for the
owner: swipe ends with the action bar's, the strip matches the player frame's power bar, the border lights at the
target frame's 20 %, a lane icon arrives with the action bar's swipe end.

## 9. Open questions for the owner

1. **Overlay 1 already ships.** Keep "true-cost dimming" in the pitch as "faster and clearer", or drop it?
2. **Execute border.** Its value over the usability answer is small (§1). Build it in phase 2, or drop it?
3. **How Modern holds the layout.** (a) one `modern` style wrapping the base and borrowing its subtable (proposed,
   decision M2); (b) a "truth overlays" option group inside Classic and Timeline (no new style, but edits Classic);
   (c) Modern copies Classic's layout options (no exception, duplicated settings).
4. **Cooldown Manager confirmation.** Worth a record field (`DisplayStyleAPI` 1 → 2) and a pack field
   (`confirmAura`)? Without it, proc confirmation covers usability-gated procs and overlay glows only.
5. **The strip's estimate marker.** Player-facing, or a developer option for play tests?
6. **The ride's max rule.** A lane icon may arrive later than Hekili predicted but never sooner. Acceptable, or
   should the lane show the real time only when it is later, and nothing otherwise (the same thing, said as a rule)?
7. **Allocation.** Accept 56 B per cooldown event per shown spell (client userdata), against Classic's 520 B per
   swipe read on every drawing frame?
8. **When to build.** Phase 1 before launch (all CONFIRMED, opt-in), or wait for the launch data as the proposal said?
9. **PvP.** Overlays 2 and 4 off against player targets unless MD-PVP passes?

## Out of scope

Engine changes for phases 1-2; any change to Classic; reading a secret back from a widget; secret-driven gates on
power against a cost; WeakAuras export of truth values; localisation of the new option strings beyond wrapping them
in `L[...]` (the lint requires it).

## Decisions made in this spec

| # | Decision | Why |
|---|---|---|
| M1 | Overlays ship in three phases ranked by value × confidence; a probe-dependent overlay is a code constant, flipped by a commit citing the probe | no option for something the client may refuse |
| M2 | One `modern` style wraps `classic` or `timeline` by delegation and reads the base's subtable through the base's code | Classic untouched; the player's layout carries over |
| M3 | A fourth facade class, `display`, as `Facade.Display.*`, readable only from `UI/Truth.lua` | the check stays total; the engine's rows keep answering the belief |
| M4 | A secret goes from one call into one widget method in one expression; nothing reads a fed aspect or the geometry of a secret-filled bar | secret safety without trusting undocumented read-backs |
| M5 | Pressable only when Hekili's time has come and every truth overlay agrees; swipes switch source on the plain `isActive`; the ride shows `max(pred, real)` by the StatusBar's minimum clamp | dim, never promote, with plain branches only |
| M6 | Plain inputs debounce in Lua (less-ready at once, back after the hold); secret inputs only drive continuous visuals or once-a-fight gates, eased by the StatusBar when a gate must sit on a hovering value | no jitter without reading a secret |
| M7 | Curves are built per distinct pack parameter out of combat and shared; nothing per frame; the curve input is a 0-1 fraction | performance rule; API §0 |
| M8 | Execute and proc facts come from pack fields (`healthGate`, existing; `confirmAura`, proposed) | core generic rule |
| M9 | The press icon's swipe includes the GCD; queued icons ignore it | matches the action bars without the queue sweeping in unison |
