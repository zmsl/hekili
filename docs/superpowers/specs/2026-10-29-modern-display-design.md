# Modern display: the game's truth painted over Hekili's picks (design, 2026-10-29)

Status: APPROVED by the owner 2026-10-29 ("3=a, the rest go with your rec"), with the answers in §9. Revised the same
day to the owner's layer design (§5.1, M2): Modern is a per-display toggle over Classic or Timeline, not a style.
Architectural (a core display layer, an optional button contract, a new facade class): the phase 1 build plan comes
next and is reviewed before any code. Branch `forever-modern-research` from `forever` 21ad62d12. Paths are under `src/Hekili/` unless they start with
`tests/`, `tools/` or `docs/`; line numbers as of 21ad62d12.

Research this rests on: "API", `docs/research/2026-10-29-modern-display-api.md` (the client route, secrecy and
confidence per overlay, and the launch-day probes GC-T and MD-*). The proposal it answers: `modern-display-brief.html`
(2026-10-25, owner-facing). "[GS Qn]" cites the gate spike (`TacoDogForever/docs/spikes/2026-10-gate-spike-findings.md`).

## 0. The owner's requirements

From the proposal the owner asked for a research track on (2026-10-29: "do a modern display research track"):

1. Modern is a new, opt-in renderer per display: Classic's layout plus overlays painted from the game's hidden truth.
   (Revised 2026-10-29, owner: an option on both Classic and Timeline, "A/B switching which display handler is used",
   so a layer over whichever style the display uses, §5.1.)
2. Hekili still decides. Overlays dim, glow or redraw what Hekili suggested; they never swap in another ability.
3. Dim, never promote. When the truth and the estimate disagree, an overlay may say "not yet", never "press
   something else".
4. No jitter. The flicker rule (no-jittery-recommendations, 2026-10-20) applies to overlays too.
5. Classic stays untouched. Switching back is one click. Restated for the layer (2026-10-29): Classic and Timeline
   gain only the optional button contract fields (§5.1, a few lines each, no behaviour change); with the toggle off
   their drawing is unchanged and nothing of Modern runs, which a headless parity test checks (R1, §8).
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
| 2 | Truth bars (4), dev build only (§7.1) | CONFIRMED by docs; tainted call on GC-T | high for testers (live estimate drift); none shown to players (owner, 2026-10-29) | needs GC-T's bar row; never on by default |
| 2 | Execute border (2) | LIKELY | low to medium (§1) | needs GC-T's health row |
| 3 | Proc confirmation from the Cooldown Manager (6, route 1) | CONFIRMED route, coverage unknown | medium, for buff procs that gate nothing | needs a record field (§5.3) and CDM-T's taint verdict |
| 3 | Timeline riding real cooldowns (5) | PROBE | medium: the near end of the lane becomes exact | needs GC-T and MD-TL, and a Timeline hook (§5.4) |

Phase 1 can be built before launch and stays opt-in; phases 2 and 3 are built only after their probe passes. An overlay
whose probe fails stays off in code (a constant per overlay, §6), not hidden behind an option.

## 3. The conflict rules, made precise

### 3.1 Hekili decides; dim, never promote

- **R1. Same picks.** With Modern on, the bound style draws exactly the records it draws with Modern off, in the same
  slots, with the same texture, caption, keybind, focus ring and indicators. Modern never writes a record field, never
  reorders, never hides a record and never shows an ability Hekili did not publish. A headless test compares the bound
  style's slot assignment with the toggle on and off for the same published sets (§8).
- **R2. Pressable only when both agree.** An icon looks pressable (full colour, no swipe, no dim) only when Hekili's own
  time has come (`exact_time` within 0.05 s, as `Output.lua:12` `READY`) and every truth overlay agrees. Each overlay may
  only take "pressable" away:
  - dim: alpha or vertex colour at or below the bound style's;
  - swipe: the real cooldown is shown while it runs (plain `isActive and not isOnGCD`, API §2.3); once it has ended, a
    record Hekili still holds back keeps the bound style's delay look (Classic's `delays.fade` / `desaturate` from
    `r.desaturate`, Timeline's countdown), so a real cooldown that ends early never makes the icon look ready before
    Hekili says so;
  - ride: a lane icon's position is `max(Hekili's x, the real cooldown's x)` (§5.4), so it can arrive later than
    predicted, never sooner.
- **R3. Confirm marks are additive and subordinate.** The execute border and the proc glow appear only on a record
  Hekili published, and never on an icon that is dimmed by a plain overlay (the dim is plain, so the border's texture is
  hidden by our own `Hide()` while dimmed; the secret alpha is only ever set on a shown texture). A mark appears only on
  the next icon (record 1 of its display) and the focus icon, never on any other queued icon, with no option to
  change it (owner ruling 2026-10-29: "The execute/proc border should be turned off for all non-next/focus icons"), so
  the eye stays on the press.

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

### 5.1 A layer core attaches to the bound style (owner, 2026-10-29)

Owner: "Could we have the 'modern' display be an option on both timeline and classic such that we're effectively A/B
switching which display handler is used so that we don't need to worry about shadowing or copying at all?" Modern is
a per-display toggle, owned by core and shown whichever style the display is bound to (classic, timeline, or a
third-party style). When it is on, core attaches the truth layer (`UI/Truth.lua`, §5.2) to the bound style's buttons;
when it is off, nothing of it runs. The display keeps its style and every setting at its own path: there is no
`modern` style, no `base` field, no layout accessor, no style reading another style's subtable and no setting copied.

**The toggle.** A core display field, `displays[id].truth`, in `displayTemplate` beside `visibility`:
`truth.enabled` (default `false`, marked experimental) plus the per-overlay options of §7 (and, in a dev build, the
truth bars of §7.1), all stored at `displays[id].truth.*`. Core shows them as one display tab, "Modern", beside
"Icons" and "Visibility" (`Options/Options.lua`, a core tab: `optionConf` already resolves a core tab's options to
`displays[id].<tab>.*`), on every style, never from Classic's or Timeline's code. `truth` is a core display key, so
`ns.UI.StyleNameTaken("truth")` refuses a style of that name (it is in `displayTemplate`).

**The lifecycle** (`UI/UI.lua`, the display's own code, beside each call it already makes to the style):

| Core call | With `d.truthOn` |
|---|---|
| `bindStyle` (`UI/UI.lua:1081`) | `Truth.Clear(d)` before the style's `Build` when it was on; after `d.Buttons = style.Build(d, conf)`, `d.truthOn = conf.truth.enabled == true` and, when on, `Truth.Build(d, conf, d.Buttons)`: one overlay set per button, out of combat |
| `OnUpdate` (`:1157`, `:1161`) | `Truth.Tick(d, conf, out, now)` right after `style.Tick`; `Truth.Draw(d, conf, out)` right after `style.Draw` |
| `OnEvent` (`:1224`) | `Truth.OnGameEvent(d, conf, event, ...)` right after `style.OnGameEvent` (`SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`, `SPELL_UPDATE_USABLE`; phase 2 adds `UNIT_MAXPOWER`, `PLAYER_TARGET_CHANGED`) |
| every `style.Clear(d)` (`unsubscribe` :934, a style switch :1090, `Deactivate` :1307) | `Truth.Clear(d)` right after |

Switching the style or flipping the toggle goes through `SetDisplayOption` → `QueueRebuildUI` → `bindStyle`, as any
style change does; nothing else rebuilds. The display registers the three usability and cooldown events (today
commented out, `UI/UI.lua:1267-1270`) only while the layer is on, from `Truth.Build`, and unregisters them in
`Truth.Clear`.

**The button contract** (`UI/Styles.lua`, documented beside `MEMBERS`; every field optional). A style's `Build`
returns its buttons; for Truth to paint one, the button exposes:

| Field | Meaning | Classic | Timeline |
|---|---|---|---|
| `b.recIndex` | the record the button draws now (`out.recs[b.recIndex]`), 0 for none; set on every publish | `i` for `i <= numIcons`, else 0; 0 when blank and in `Clear` | `T.rec[c]` in `assign`; 0 when blank and in `Clear` |
| `b.isFocus` | the button draws the display's focus record (M11's "focus icon") | never set | `c == 1 and T.focused` in `assign`; false when blank and in `Clear` |
| `b.Cooldown` | the button's own `Cooldown` frame, which Truth hides while it shows the real one (R2) | already there (every button) | already there (cells 1-2) |
| `b.round` | the icon is round (Truth's swipe and veil use the circle) | never set | `true` on cell 1, at creation |

The "next" icon is the button whose `recIndex` is 1. Truth copies the count-number look from the style's frame
(`b.Cooldown:GetHideCountdownNumbers()`, a plain read of our own widget, never of a fed one). A button without
`recIndex` gets no overlays, and one without `Cooldown` gets no real swipe (Timeline's lane cells), so a third-party
style that sets none of these draws exactly as before with the toggle on. `Hekili.DisplayStyleAPI` stays 1: the fields
are optional, no member or record field changes, and a style written for 1 still registers and draws (ruling M12).

So Classic and Timeline gain only the contract assignments (requirement 5), and the player's layout carries over
because it is never moved: Truth reads no style's subtable, only the buttons the style returned and the contract.

### 5.2 The truth layer: `UI/Truth.lua`

The only file that calls `Facade.Display`. Per display (`d.truthState`), preallocated at `Truth.Build` for each
button the bound style returned (one set per button list, so a style switch back reuses it):

- `ov[i].cd`: a second `Cooldown` frame over the button's own `b.Cooldown` (contract, §5.1; `CooldownFrameTemplate`,
  same draw settings); the style's `b.Cooldown` is hidden while `ov[i].cd` shows a real cooldown, and shown again
  otherwise (R2);
- `ov[i].dur`: the held duration object (nil when none), `ov[i].spell`: the spell it was fetched for;
- `ov[i].border`: the execute border texture; `ov[i].glow`: LibCustomGlow under its own key (as Classic uses it);
- `ov[i].dim`, `ov[i].since`: the debounce state (§3.2);
- the truth bars (§7.1, developer mode only): per enabled type, one real StatusBar (fed from `Facade.Display`) and one
  belief StatusBar (fed the plain published estimate), with the cost tick textures `ticks[1..SLOTS]` on the real bar;
  built only in a dev build (`Hekili.IsDev`), so a player's display allocates and draws none of it;
- the ride bars (`ride[i]`, one StatusBar per lane slot) on a Timeline display (phase 3, §5.4).

What it reads: the buttons and their contract fields (§5.1), `out.recs[i]` (`actionName`, `actionID`, `exact_time`, `cost`, `resource_type`, `resources`),
`d.resolved[i]` (`usable`, `glow`, `desaturate`), `Hekili.Engine.Registry.Abilities()[name]` for pack facts
(`healthGate`; `item` to skip items), `Output.hold`, `Output.Acted` through a getter, its own `conf.truth`; no style's subtable. Nothing of `state.*`, `class.*`
or VirtualState (`tools/check_engine_reads.sh` already enforces it for `UI/`).

When it fetches a duration object: when a button's record changes spell, and on `SPELL_UPDATE_COOLDOWN` /
`SPELL_UPDATE_CHARGES` for the shown spells; never in `Tick`. The plain `isActive` / `isOnGCD` come from the facade's
existing `C_Spell.GetSpellCooldown` row, which already reads the plain flags (`Facade.lua:660-669`).

### 5.3 The subscription channel

No engine change for phases 1-2: Truth rides the bound style's subscription (`Engine.Subscribe`,
`Engine/Output.lua:237`; `bindStyle`, `UI/UI.lua:1081`) and draws from the same `out` core hands the style. Every field it reads is already on the
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
beyond the glide. Under the layer design (§5.1) Truth reads no style's subtable, so the lane's geometry (`laneX0`,
`pxPerSec`, `H`) and the `rideAnchored` hook become optional contract fields that Timeline sets; their names are
designed with phase 3, and they stay optional (no `DisplayStyleAPI` bump for them).

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

## 7. Options per display (`displays[id].truth`)

One core "Modern" tab on every display, whatever its style (§5.1), its options stored at `displays[id].truth.*`. The
overlay toggles are disabled while `enabled` is off. Defaults:

| Option | Default | Notes |
|---|---|---|
| `enabled` | off | "Modern (game truth)", marked experimental: attach the truth layer to this display's style |
| `swipes` | on | real cooldown swipes |
| `edge` | on | redraw on the usability edge |
| `confirm` | on | proc glow from usability and overlay; next and focus icons only (R3, no queue option) |
| `execute` | on, shown only while `VERIFIED.execute` | the border colour (gold) and width |
| `ride` | off, shown only while `VERIFIED.ride` and the display's style is `timeline` | |

Switching back is one click: the `enabled` toggle (requirement 5). The style dropdown is unchanged.

### 7.1 Truth bars: dev build only (owner ruling, 2026-10-29)

Owner: "The truth strip is a really interesting idea but should be designed carefully so that the UI isn't messy. It
should be off by default ... both the real bar(s) and belief bars should be dev-mode only so that the addon isn't
trying to show too much to the player."

- **Developer mode is the dev build** (owner, 2026-10-29: "the title itself changes on the addon when it's a dev
  build"): `Hekili.IsDev` (`Hekili.lua:35-38`), true when the packager left `@project-version@` unreplaced (a git
  checkout; the version reads `Dev-<build> (<date>)`), never in a released zip. No new flag. In a release build the
  truth-bar options do not exist, nothing is built, and Truth's `Tick` skips the bars (one plain boolean check). In a
  dev build the options appear under a "Developer" header on the Modern tab, every toggle still off by default.
- **Two families of bars, each off by default, each switchable by type** (`displays[id].truth.bars`):
  - **Real bars** (`real[type]`): the game's value through `Facade.Display` (secret, §3.3), one bar per type: the
    player's power types the active pack declares (rage, mana, energy, focus) and target health. Each needs
    `VERIFIED.strip` (GC-T) before its toggle appears.
  - **Belief bars** (`belief[type]`): Hekili's own estimate for the same types, from the published plain record
    (`out.recs[1].resources`, the belief's est; no `state.*` read), drawn in a distinct colour, optionally with its
    lo-hi band as a lighter span. Plain values only, so they need no probe.
  - A type shows a real bar and a belief bar stacked as a pair when both are on, so drift reads at a glance; either
    alone is allowed.
- **Layout restraint.** Bars sit in one compact block below (or above) the icons, `height` 4-10 px each (default 6),
  at most one row per enabled type, width = the display's icon row; no text by default (`showValues` off; when on, the
  belief bar may print its number, the real bar never can: a secret cannot be formatted). Cost ticks (the queue's
  costs) only on a real bar of the matching type.
- **Never player-facing:** no bar appears outside a dev build; a released zip has no path to them. The
  options, the snapshot and WeakAuras do not expose real values (§3.3).

## 8. What is testable where

**Headless (busted, beside `tests/Forever/display_style_spec.lua` and `display_resolve_spec.lua`, with the fake API's widgets recording calls):**

- R1 (parity): for recorded published sets (the harness fights), Classic's and Timeline's per-slot shown state, action
  and texture are the same with the toggle on and off; a style without the contract fields draws and errors nothing
  with the toggle on.
- R2: given fake plain flags, the swipe source per button (real when `isActive and not isOnGCD`, the style's own otherwise), the
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

## 9. Owner answers (2026-10-29)

All answered: question 3 "a", the rest "go with your rec", plus two earlier rulings (5, and R3's marks).

1. **Overlay 1 already ships:** keep it in the pitch, worded "faster and clearer" (the usability edge, not the 0.2 s pulse).
2. **Execute border:** deferred to phase 2, low priority (it mostly repeats the usability answer, §1).
3. **Layout:** (a), one `modern` style wrapping `classic` or `timeline` through a read-only layout accessor.
   **Superseded** by the owner's layer design (2026-10-29, §5.1, M2): Modern is a per-display toggle on whichever style
   is bound, with no `modern` style, `base` field or accessor. **Open for the owner:** Timeline's "Timers Out of
   Combat" (`oocTimers`) off hides its sweeps out of combat, while Truth's real swipe would still show a running
   cooldown there. Recommended: the real swipe follows the bound style's setting (it would need one more optional
   contract field, since Truth reads no style's subtable); phase 1 ships without it and the question stays open.
4. **Cooldown Manager confirmation:** yes, in phase 3, after launch shows the Cooldown Manager's proc coverage
   (`DisplayStyleAPI` 1 -> 2, pack field `confirmAura`).
5. **Truth bars:** real and belief bars both dev-build only (`Hekili.IsDev`), off by default, per type (§7.1, M10).
6. **The ride's max rule:** accepted: a lane icon may arrive later than Hekili predicted, never sooner (M5).
7. **Allocation:** accepted: 56 B per cooldown event per shown spell, fetched on events only.
8. **When to build:** phase 1 now (true swipes, the usability edge, proc glow from usability and overlay), opt-in and
   marked experimental; the probe-gated parts after their 2026-11-04 probes pass (M1).
9. **PvP:** the execute border and the truth bars off against player targets unless MD-PVP passes.
10. **Confirm marks** (owner ruling): next and focus icons only, no queue option (R3, M11).

## Out of scope

Engine changes for phases 1-2; any change to how Classic or Timeline draw (they gain only the contract fields); reading a secret back from a widget; secret-driven gates on
power against a cost; WeakAuras export of truth values; localisation of the new option strings beyond wrapping them
in `L[...]` (the lint requires it).

## Decisions made in this spec

| # | Decision | Why |
|---|---|---|
| M1 | Overlays ship in three phases ranked by value × confidence; a probe-dependent overlay is a code constant, flipped by a commit citing the probe | no option for something the client may refuse |
| M2 | Modern is a core per-display layer (`displays[id].truth.enabled`, a core "Modern" tab), attached to the bound style's buttons after its `Build` and called right after each of its members, only while on; styles expose an optional button contract (`recIndex`, `isFocus`, `Cooldown`, `round`). Supersedes the wrapping `modern` style (owner, 2026-10-29) | owner: "A/B switching which display handler is used" with no shadowing or copying: no style reads another's subtable, the layout never moves, and the toggle off runs nothing |
| M3 | A fourth facade class, `display`, as `Facade.Display.*`, readable only from `UI/Truth.lua` | the check stays total; the engine's rows keep answering the belief |
| M4 | A secret goes from one call into one widget method in one expression; nothing reads a fed aspect or the geometry of a secret-filled bar | secret safety without trusting undocumented read-backs |
| M5 | Pressable only when Hekili's time has come and every truth overlay agrees; swipes switch source on the plain `isActive`; the ride shows `max(pred, real)` by the StatusBar's minimum clamp | dim, never promote, with plain branches only |
| M6 | Plain inputs debounce in Lua (less-ready at once, back after the hold); secret inputs only drive continuous visuals or once-a-fight gates, eased by the StatusBar when a gate must sit on a hovering value | no jitter without reading a secret |
| M7 | Curves are built per distinct pack parameter out of combat and shared; nothing per frame; the curve input is a 0-1 fraction | performance rule; API §0 |
| M8 | Execute and proc facts come from pack fields (`healthGate`, existing; `confirmAura`, proposed) | core generic rule |
| M9 | The press icon's swipe includes the GCD; queued icons ignore it | matches the action bars without the queue sweeping in unison |
| M10 | Truth bars (real and belief, per type) exist only in a dev build (`Hekili.IsDev`), each off by default, built only there | owner ruling 2026-10-29: no cluttered player UI; the bars are a testing tool |
| M11 | Execute border and proc glow on the next icon and the focus icon only, no option for the rest of the queue | owner ruling 2026-10-29: marks stay on what to press |
| M12 | The button contract's fields are optional, so `Hekili.DisplayStyleAPI` stays 1; a style without them gets no overlays | no member or record field changes; a third-party style written for 1 keeps registering and drawing unchanged |
