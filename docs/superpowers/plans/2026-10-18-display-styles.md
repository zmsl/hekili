# Display Styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split Hekili's display rendering into a core (frame, visibility, subscription, config mode) plus N swappable per-display styles, with the existing look extracted as `classic` unchanged, then add a Timeline style.

**Architecture:** Each display frame binds one style table from a registry (`ns.UI.Styles`) by the profile field `displays[id].style`; core drives it through a small interface (Build, Draw, Tick, OnGameEvent, Clear, Perimeter, UpdateKeybindings, Options). A style reads only `Hekili.Engine.Output[id]`, `Output.status`, and its own config subtable. Styles never read `state.*`, `class.*` or the engine.

**Tech Stack:** Lua 5.1 (WoW), AceConfig tab groups with `hidden` functions, AceDB `['**']` templates, busted headless harness (`tests/Game/harness/headless.lua`).

**Spec:** the Design section below, approved by the user on 2026-10-18 (there is no separate spec document).

## Global Constraints

- No new tables, closures, varargs, string building or `C_Timer.After` in recurring paths (OnUpdate, Draw, Tick, publish). Preallocate at Build.
- UI code never reads `state.*`, `class.*`, `Hekili.State`, `Hekili.Class`, `HekiliEngine`; `tools/check_engine_reads.sh` enforces it in `UI/**` and `Options/**`.
- `make check` green before every commit (luacheck, stylua, busted, apiref, boundary, engine-reads, packs-check).
- Recommendations byte-identical: `make test-loop` `Arms solo:` line unchanged; `tests/Forever/arms_recs_spec.lua` fixture unchanged.
- Credit Hekili and Catnip (Durts) in file headers wherever their code is used; new files start `local _, ns = ...`.
- TOC: new UI files load after `UI\UI.lua` and before `Engine\Sim\Core.lua`; a TOC change needs a full client restart in game.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Styles are isolated: no style reads another style's subtable; core never reads a style's subtable.

## Review Focus

1. Switching a live display's style must hide every widget of the old style (Clear) before Build of the new one; nothing of the old look may stay visible. Test in Task 2's switch spec: after the switch, every frame the old style created reports `IsShown() == false`.
2. Consumers that reach into buttons (Masque, ElvUI, SpellFlash, the tooltip's `b.Recommendation`, config movers' `b.display`, `Options.lua:9436,9452`, `ChatCommands.lua:540`) must tolerate a style that returns no buttons. Test in Task 2: the stub style returns an empty list and `Hekili:BuildUI()`, config mode start/stop and the removed-display path run without error.
3. Zero allocation per frame in Draw/Tick after warm-up. Test in Task 1 (classic) and Task 4 (timeline): 1,000 frames with GC stopped allocate 0 B after the first publish.
4. A profile saved by an older build has no `style` field; it must draw as classic. Test in Task 2: a display table with `style = nil` binds classic without a Notify; an unknown name binds classic with one Notify.
5. Custom (user-created) displays go through `CreateCustomDisplay`, which copies methods from Primary; they must bind their own style. Test in Task 2: a custom display with `style = "stub"` calls the stub's Build.

---

## Context

The user wants to add a new *visual style* for Hekili's displays, chosen per display (Primary, AOE,
Cooldowns, Defensives, Interrupts), without touching the engine's "display mode" toggle (automatic /
single / aoe / dual / reactive is a target-count and visibility policy, 13 scattered sites, out of scope).

Today one renderer is welded into `src/Hekili/UI/UI.lua` (3,027 lines): `Hekili:CreateDisplay` (1106-2164)
builds the frame and defines `OnUpdate` (1169-1725, 557 lines mixing "what to show" with "how to show"),
`RefreshCooldowns`, `OnEvent` (glow, highlight), `UpdateKeybindings`, `GetPerimeterButtons`;
`Hekili:CreateButton` (2350-2717) reads every style field of `profile.displays[id]` and does all layout
by name-chained anchors (`Hekili_<disp>_B<i>`). `Options/Options.lua` `newDisplayOption` (1183-~2860)
hard-codes one tab per style field group. The only generic seams already in place: `Engine/Output.lua`
(per-display `recs`/`count`/`version`, Subscribe/Wanted/Annotate; Core caps records at `numIcons`,
Core.lua:1500) and `Engine.Output.status`.

Nothing in the profile names a style. `displayTemplate.queue.style` and `queue.alignment` exist but are
never read; `visibility.mode.*` likewise. There is no renderer registry.

Outcome: UI.lua keeps the display frame, visibility, subscription, config mode, menus and launchers
("core"); each style is one file under `src/Hekili/UI/Styles/` implementing a small interface; the
existing look becomes `classic`, byte-for-byte in behaviour; a second style can be added as one file plus
its options table. Per-display selection via `profile.displays[id].style`.

## Design

### Style interface (`ns.UI.Styles[name]`, one table per style)

| Member | Called from | Inputs | Replaces today |
|---|---|---|---|
| `Build(d, conf)` | `CreateDisplay`, `BuildUI` | display frame, display config | `CreateButton` ×10 + layout 2553-2682; returns the button list core stores in `ns.UI.Buttons[id]` |
| `Draw(d, conf, out, status)` | display `OnUpdate` when `NewRecommendations` or pulse | `Engine.Output[id]` (`recs`, `count`, `version`), `status` | 1215-1343 (texture, caption, keybind, indicator, glow start/stop) + `RefreshCooldowns` |
| `Tick(d, conf, out, now, elapsed)` | display `OnUpdate` every frame | same + time | 1350-1693 (glow re-check, flash, target count, delay, range/usable/desaturate) |
| `OnGameEvent(d, conf, event, ...)` | display `OnEvent` | event args | 1811-1868, 1892-1912 (overlay glow, cast highlight) |
| `Clear(d)` | `unsubscribe`, `Deactivate`, style switch | | hide loops 941-945, 1216-1220 |
| `Perimeter(d)` | config mode | buttons | `GetPerimeterButtons` 2004-2045 |
| `UpdateKeybindings(d)` | core keybinding event | | 1144-1167 |
| `Options(id, conf)` | `newDisplayOption` | display id, config | the style tabs: keybindings, border, range, glow, flash, captions, targets, delays, indicators, and the `queue`/size part of `main` |

Plus two data members: `label` (dropdown text) and `defaults` (the style's config subtable template; classic's is nil because its fields are the legacy flat ones).

Core keeps: frame creation and position (1106-1142), the timer/alpha/pause head of `OnUpdate`
(1169-1205), `UpdateAlpha`, `CalculateAlpha`, `Activate`/`Deactivate`, alpha and keybinding event
dispatch in `OnEvent`, `CreateCustomDisplay`, `UpdateDisplayVisibility`, `BuildUI`, config mode and
movers, menus/launchers, the diagnostic tooltip, Masque group setup. Per-display style state
(`flashTimer`, `rangeTimer`, `delayIconShown`, ...) moves onto `d.styleState` (a table the style owns).

### Profile: settings are split into core and per-style, nothing shared by accident

```lua
displays.Primary = {
  -- core (read by UI.lua and the engine, every style)
  enabled, builtIn, name, relativeTo, displayPoint, anchorPoint, x, y, frameStrata, frameLevel,
  numIcons,              -- how many records the engine publishes (Core.lua:1500); each style says how it uses them
  visibility = { ... },  -- advanced/pve/pvp alpha rules
  style = "classic",     -- NEW: which renderer draws this display
  -- classic's fields stay exactly where they are (primaryWidth/Height, zoom, queue, border, range,
  -- glow, flash, captions, indicators, targets, delays, keybindings): no migration, old profiles load
  -- a new style owns ONE subtable named after itself; nothing of classic's applies to it
  timeline = { nowSize = 48, nextSize = 40, laneLength = 300, laneHeight = 28, pxPerSec = 24, ... },
}
```

- A style registers `defaults` with its implementation. `Hekili:GetDefaults()` (Options.lua:367) sets
  `displayTemplate[name] = style.defaults` for every registered style before returning, so AceDB's
  `['**'] = displayTemplate` (596) supplies them per display. Styles load after Options.lua in the TOC
  (UI.lua is line 71, Options 67) and before `OnInitialize` creates the DB (Profile.lua:19), so the
  registry is complete when defaults are read.
- A style never reads another style's fields; core passes it `conf` (the whole display table); the style
  reads core fields it needs (`numIcons`) and `conf[name]` (its own subtable). Classic is the exception:
  its subtable is the display table itself (legacy flat fields).

### Options panel: reactive to the style, one tab set per style

- `newDisplayOption` (Options.lua:1183) builds the display's `childGroups = "tab"` group and already
  hides tabs with `hidden = function () ... end` (the "Multi" pattern at 1233-1285). AceConfigDialog
  re-evaluates `hidden` on every refresh, and every `set` refreshes, so choosing a style in the dropdown
  swaps the visible tabs immediately. No new mechanism.
- The `main` tab ("Icons" today) becomes core-only: enabled, name, position/anchor, strata, numIcons,
  and the new `style` dropdown (values = registered style names, labelled by `style.label`). Classic's
  size/zoom/queue fields stay in `main` (their profile path is unchanged) but gain
  `hidden = function() return conf.style ~= "classic" end`.
- Each style's `Options(id, conf)` returns its tab groups. Classic returns today's tabs (keybindings,
  border, range, glow, flash, captions, targets, delays, indicators) unchanged, each with the hidden
  function added. A new style returns one tab whose key IS its subtable name (`timeline`), with
  `inline = true` section groups inside (Now, Next, Lane). `GetDisplayOption`/`SetDisplayOption`
  (689-748) resolve `displays[info[2]][info[3]][info[#info]]`, i.e. display → tab key → option, and
  ignore the middle segments, so inline sections are presentational and every option lands in
  `displays.Primary.timeline.<option>`. Consequence: option keys must be unique within one style's
  subtable (flat). A style that needs more than one tab prefixes the extra tab keys with its name and
  gets a matching subtable each (`timeline_colors`); avoid unless needed.
- The "Multi" pseudo-display (edit several at once) shows a style's tabs only when every selected
  display uses that style; the style dropdown on Multi applies to all selected (existing `multiSet`
  path).
- `QueueRebuildUI` already rebuilds on any set, which re-runs `Build` for the new style.

### How a style plugs into a display at runtime

1. **Registration, at file load.** `src/Hekili/UI/Styles/Timeline.lua` ends with
   `ns.UI.RegisterStyle("timeline", { label = "Timeline", defaults = {...}, Build = ..., Draw = ...,
   Tick = ..., OnGameEvent = ..., Clear = ..., Perimeter = ..., UpdateKeybindings = ..., Options = ... })`.
   `RegisterStyle` validates the members and stores the table in `ns.UI.Styles[name]`. Nothing else
   knows the style exists; the dropdown and `GetDefaults` enumerate the registry.
2. **Binding, in `Hekili:CreateDisplay(id)`** (UI.lua:1106), after the frame and position are set:
   `d.style = ns.UI.Styles[conf.style] or ns.UI.Styles.classic` (unknown name: one `Notify`, fall back;
   nil name: classic silently); `d.styleState = d.styleState or {}` (per-display scratch the style owns);
   `d.widgets = d.style.Build(d, conf)` creates the style's child frames parented to `d`, sizes `d`, and
   returns the list that core stores as `ns.UI.Buttons[id]` (may be empty for a style without buttons).
   WoW cannot free frames, so `Build` keeps what it made on `d.styleFrames[name]` and reuses it when the
   same style is bound again; switching styles calls the old style's `Clear(d)` first (everything hidden).
3. **Driving, from core's three entry points.** Display `OnUpdate` head (timers, alpha, pause) then
   `d.style.Draw(d, conf, out, status)` when `NewRecommendations` or the 0.25 s pulse fires, and
   `d.style.Tick(d, conf, out, now, elapsed)` every frame; display `OnEvent` handles alpha and keybinding
   events itself and forwards the rest to `d.style.OnGameEvent(d, conf, event, ...)`; `unsubscribe` and
   `Deactivate` call `d.style.Clear(d)`; config mode asks `d.style.Perimeter(d)` for the backdrop bounds.
   `out` is `Hekili.Engine.Output[id]` (`recs[1..count]`, `version`), `status` is `Output.status`.
4. **Switching, from the options panel.** The `style` dropdown's set goes through `SetDisplayOption` →
   `QueueRebuildUI` → `Hekili:BuildUI` → `CreateDisplay(id)` for every display, which is step 2 again
   with the new name. Custom displays (`CreateCustomDisplay`) copy the same binding.
5. **Per-display, not global.** Every display has its own `d.style`, so Primary can be `timeline` while
   Cooldowns stays `classic`; the two share nothing but the registry table.

### Consumers of the named buttons (must keep working)

Masque (2148), ElvUI skin, SpellFlash, the tooltip (`b.Recommendation`, 2702), config movers
(`b.display`), `Options.lua:9436,9452`, `ChatCommands.lua:540` (`ns.UI.Buttons`). Ruling: `Build`
returns the frames; each must carry `display`, `Recommendation`, `Ability`, `Action`, `ExactTime` if it
shows a recommendation. Masque registration stays inside classic's `Build`. A style with no icon buttons
returns an empty list and the tooltip/mover code must tolerate that (verify in Task 1, test in Task 2).

### "What to show" shared between styles (Task 3)

Range, usable, desaturation, `earliest_time`/delay, clamped target count and overlay-glow state are
computed inside classic's draw loops from game APIs. Move them into `src/Hekili/UI/Resolve.lua`
(`ns.UI.Resolve(d, conf, out, now)` writing into a preallocated per-record table) so a second style does
not re-query the client. Longer term these belong in an `Output.Annotate` annotator; not in this plan.

### Does the engine output carry what a TDF-style timeline needs? (checked 2026-10-18)

Hekili's `Output[name].recs[i]` (Core.lua writes ~1046-1861): `actionName`, `actionID`, `texture`,
`caption`, `indicator` (`"cycle"`), `offGCD`, `keybind`, `script/list/action/pack` (APL provenance),
`time` (seconds from `state.now`, cumulative), `exact_time` (absolute GetTime), `delay`, `since`
(`time - prev.time`), `wait`/`waitSec`, `resource_type`, `resources[k]` (simulated level at that cast,
before its spend), `belief = {}` (reserved, no annotator exists yet). Records 2..n are true sequence
predictions (Core.lua:1863-1947). Count is `numIcons` (1-10, Core.lua:1500), not a time horizon.

| Timeline need | Source | Status |
|---|---|---|
| icon, x position, ETA text, APL line tooltip | `texture`, `exact_time - GetTime()`, `script/list/action` | present |
| two-row stacking of close picks | `since` | present |
| Now / Committed / Future kind | `i == 1` and `time ≤ 0.1`, else `i == 1`, else future | trivial (UI) |
| combat mode, pinned (out of combat, GCD free) | `status.combat`, `recs[1].time`, GCD via game API | trivial |
| horizon | clip to the lane length on `exact_time - GetTime()`; set the display's `numIcons` to ~8 | config |
| spend gate (resource, **cost**) | `resource_type`, `resources[type]` present; cost MISSING | engine: one Core write `slot.cost` at ~1857 |
| busy / idle (GCD or cast length per pick) | MISSING | engine: one Core write `slot.busy` near 1870 |
| `why` Resource / Cooldown | derivable once `cost` and `busy` exist | trivial after the two writes |
| `conf`, beliefs tooltip, overflow aura tracks | belief layer (`VS.Power`/`VS.Regen`/`VS.Aura`) | annotator via `ns.Output.Annotate` (follow-up spec) |
| Fuzzy kind, `why` Unsure, `why` Window | needs Lo/Hi re-sims and a recheck flag | deferred |

Caveat: `recs[1].time` can be above 0 because of the queued-event pre-advance, so x must come from
`exact_time - GetTime()`.

---

## Tasks

Each task is one reviewed commit set on `forever-styles`; `make check` green; `display_alpha_spec` and the
`Arms solo:` gate line unchanged.

### Task 1: extract classic verbatim (mechanical)

**Files:**
- Create: `src/Hekili/UI/Styles/Classic.lua`, `src/Hekili/UI/Styles.lua` (the registry: `ns.UI.Styles`, `ns.UI.RegisterStyle`)
- Modify: `src/Hekili/UI/UI.lua` (CreateDisplay, OnUpdate, OnEvent, unsubscribe, Deactivate, CreateCustomDisplay, BuildUI, config mode's perimeter call), `src/Hekili/Hekili.toc`, `.luacheckrc`, `.styluaignore` if the moved code is upstream-formatted
- Test: `tests/Forever/display_style_spec.lua`, fixture `tests/Forever/fixtures/classic_draw.lua`

**Interfaces:**
- Produces: `ns.UI.RegisterStyle(name, impl)` validating `label`, `Build`, `Draw`, `Tick`, `OnGameEvent`, `Clear`, `Perimeter`, `UpdateKeybindings`, `Options` (`defaults` optional); `ns.UI.Styles.classic`; `d.style`, `d.styleState`, `d.styleFrames`.

- [ ] Record the fixture at base BEFORE moving code: boot headless Arms (`tests/Game/harness/headless.lua`, see `tests/Forever/display_alpha_spec.lua` for the display boot), publish a fixed 4-record set into `Hekili.Engine.Output.Primary` through `ns.Output.Begin/Publish`, run the display's `OnUpdate` for 3 frames, then dump per button: texture, caption text, keybind text, `IsShown()`, `GetPoint()` tuple, cooldown start/duration, desaturated flag. Write it with `CLASSIC_DRAW=record .lua/bin/busted tests/Forever/display_style_spec.lua` (same shape as `tests/Forever/arms_recs_spec.lua`). Commit the fixture alone first.
- [ ] Move the code into `Styles/Classic.lua` behind the interface; UI.lua's `OnUpdate` becomes head + `d.style.Draw` + `d.style.Tick`; `OnEvent` forwards non-core events; `unsubscribe`/`Deactivate` call `Clear`; config mode calls `Perimeter`. `d.style = ns.UI.Styles[conf.style] or ns.UI.Styles.classic` in `CreateDisplay`; `CreateCustomDisplay` copies the binding. `ns.UI.Buttons[id]` is what `Build` returns. Delete the 85 commented lines (UI.lua 2047-2131).
- [ ] The spec passes in compare mode against the base fixture (byte-identical); add the 0 B over 1,000 frames allocation case (GC stopped, after the first publish).
- [ ] `make check`, `make test-loop` (`Arms solo:` unchanged), commit.

### Task 2: per-display selection, defaults and the options dropdown

**Files:**
- Modify: `src/Hekili/Options/Options.lua` (`displayTemplate.style = "classic"`, `GetDefaults` merges `style.defaults` into `displayTemplate[name]`, `newDisplayOption` dropdown + per-style tabs + `hidden`, Multi handling), `src/Hekili/UI/UI.lua` (unknown style Notify, switch calls old `Clear`)
- Test: `tests/Forever/display_style_spec.lua` (new describes)

- [ ] Spec cases (write first, see them fail): a stub style registered in the test with `defaults = { foo = 1 }` and `Build` returning `{}` → a fresh DB has `displays.Primary.stub.foo == 1`; `Hekili:GetDisplayOption({ "displays", "Primary", "stub", "section", "foo" })` returns 1; `style = nil` binds classic with no Notify; `style = "nope"` binds classic with exactly one Notify; switching Primary from classic to stub via `Hekili:SetDisplayOption` + `BuildUI` hides every classic button (`IsShown() == false`) and the stub's `Draw` receives `out.count` records on the next publish; `BuildUI`, `ns.StartConfiguration()`/`ns.StopConfiguration()` and the removed-display path run without error while Primary has no buttons; a custom display with `style = "stub"` calls the stub's `Build`.
- [ ] Implement; the dropdown's `values` enumerate `ns.UI.Styles` with `label`; classic's size/zoom/queue fields in `main` and classic's tabs get `hidden = function() return conf.style ~= "classic" end`; each style's `Options(id, conf)` tabs appended with the matching hidden function; Multi shows a style's tabs only when all selected displays share it.
- [ ] `make check`, commit.

### Task 3: shared resolve

**Files:**
- Create: `src/Hekili/UI/Resolve.lua` (TOC after `UI\UI.lua`, before `UI\Styles.lua`)
- Modify: `src/Hekili/UI/Styles/Classic.lua` (read resolved fields instead of calling game APIs in Draw/Tick), `src/Hekili/UI/UI.lua` (core calls `ns.UI.Resolve(d, conf, out, now)` before `Draw`/`Tick`)
- Test: `tests/Forever/display_resolve_spec.lua`

- [ ] `ns.UI.Resolve(d, conf, out, now)` fills a preallocated per-record table `d.resolved[i]` with: `inRange`, `usable`, `desaturate`, `delay` (`earliest_time` logic from UI.lua 1546-1570), `targets` (clamped count, 1503-1521), `glow` (overlay state, 1301/1359). Zero allocation after warm-up.
- [ ] Classic reads `d.resolved[i]`; the Task 1 fixture still passes byte-identical; alloc spec 0 B.
- [ ] `make check`, commit.

### Task 3b: the two slot writes the timeline needs (engine, additive)

**Files:**
- Modify: `src/Hekili/Engine/Sim/Core.lua` (near 1857-1870), `src/Hekili/Engine/Output.lua` (record template)
- Test: `tests/Forever/output_spec.lua`

- [ ] `slot.cost` = the ability's spend of `resource_type` at query time (0 when none); `slot.busy` = GCD length, or cast/channel length if longer, for that pick. Preallocated in the record template.
- [ ] `output_spec`: both are numbers on every published record, `busy >= 0`; `make test-loop` `Arms solo:` line and `arms_recs_spec` fixture unchanged (additive fields only).
- [ ] `make check`, commit.

### Task 3c: alternatives under resource uncertainty, gated by subscriber needs (engine, additive)

Why: the Timeline stacks several picks at one moment when the belief knows a resource is in a range but
not its exact value, ordered by APL priority. Hekili runs one deterministic sim at the estimate, so the
engine must evaluate the bounds too. Only displays whose bound style asked pay for it.

**Files:**
- Modify: `src/Hekili/Engine/Output.lua` (`Subscribe(name, fn, passive, needs)`; per-display
  `needs.alts` count maintained like the non-passive count; record template gains `alts = {}` with
  preallocated entries `{ actionName, actionID, texture, action, list, bound }`), `src/Hekili/UI/UI.lua`
  (subscribe with `d.style.needs`), `src/Hekili/UI/Styles.lua` (`needs` optional member),
  `src/Hekili/Engine/Sim/Core.lua` (the bounded passes), `src/Hekili/Engine/Sim/State.lua` only if a
  resource pin needs a hook (prefer none: set `state[res].actual`/`current` through the existing reset path)
- Test: `tests/Forever/output_spec.lua`, `tests/Forever/alts_spec.lua`

- [ ] Invariant first, as a spec: with a second subscriber on Primary declaring `needs = { alts = true }`,
  every field of `recs[1..count]` other than `alts` is identical to a run without that subscriber, over the
  every-slot fixture (`tests/Forever/arms_recs_spec.lua` run twice in-process, needs off then on, deep
  compare). The main records never depend on whether alternatives were computed.
- [ ] Order inside `Update` for a display with `needs.alts > 0`: the normal slot loop finishes and the
  records are final; THEN for slots 1 and 2 only: `state.reset`, pin the gating resource
  (`recs[i].resource_type`) at the belief's low bound (`VS.Power(type).lo`), advance to `recs[i].time`,
  evaluate one pick; same at the high bound; a pick that differs from `recs[i].actionName` goes into
  `recs[i].alts` with `bound = "lo"|"hi"`; sorted by `action` (APL entry index). Skip both passes when the
  band does not straddle any registered cost (`lo >= cost of the estimate pick`, or `hi < cost`). Then
  publish. No pass when the count is 0.
- [ ] `output_spec`: `alts` is empty on every record when no subscriber declares the need; the need count
  rises and falls with Subscribe/Unsubscribe; `Wanted` unchanged by needs.
- [ ] `alts_spec`: a scripted belief band straddling a spender's cost produces exactly the spender and the
  filler on `recs[1].alts`, in APL order; a band that does not straddle produces none; `make bench`
  reports the per-Update cost with the need on (expect under 0.5 ms extra), recorded in the report.
- [ ] `make check`, gate lines unchanged, commit.

### Task 4: the Timeline style

**Files:**
- Create: `src/Hekili/UI/Styles/Timeline.lua` (TOC after `UI\Styles\Classic.lua`), fixture `tests/Forever/fixtures/timeline_draw.lua`
- Test: `tests/Forever/display_style_spec.lua` (timeline describe)

- [ ] Design brief with the user before dispatch: final field list for `defaults` (`nowSize`, `nextSize`, `laneLength`, `laneHeight`, `pxPerSec`, `stackSize`, `rows`), colours, fonts, what the "now" circle shows (icon, sweep, ETA), what the "next" box shows, lane stacking rule.
- [ ] Build: "now" circle (record 1), "next" box (record 2), lane (records 3..count at `(exact_time - GetTime()) * pxPerSec`, second row when `since * pxPerSec < stackSize`), ETA text, resource-gate marker when `resources[resource_type] < cost`, cooldown marker from `busy`, clip beyond `laneLength`. Primitives ported from TDF `src/TacoDogForever/Render/Render.lua` (credit header). Options: one `timeline` tab, inline sections Now / Next / Lane.
- [ ] Fixture spec over a fixed published set (record once, compare); alloc spec 0 B over 1,000 frames.
- [ ] `make check`, commit.

### Task 5: docs

- [ ] `docs/dev/architecture.md`: the style interface, the registry, the per-style config rule, the "styles never read `state.*`/`class.*`; they draw `Engine.Output[id]`" rule; `docs/dev/layout.md` file list (`UI/Styles.lua`, `UI/Resolve.lua`, `UI/Styles/*.lua`); the fixture re-record commands.

## Bugs found while mapping (not fixed in this plan; separate one-line commits if wanted)
- `UI.lua:1188` `not self.id == "Primary"` is always false (precedence), so the guard never runs.
- `UI.lua:1607` writes `b.delayIconShown` where `self.delayIconShown` is meant.
- `UI.lua:129-133, 390, 2784` iterate `ns.UI.Buttons` with `#`/`ipairs` on a string-keyed table: the right-click mouse reset, Masque-disabled path and removed-display hide never run.
- `Options.lua:393-402` stores `"false"` (a string) for reactive/dual/aoe in the mode cycle defaults, so every mode is in the keybind cycle on a fresh profile.
- `queue.style`, `queue.alignment`, `visibility.mode.*` in `displayTemplate` are dead fields.

## Verification
- `make check`; `tests/Forever/display_alpha_spec.lua` and `display_style_spec.lua` fixtures byte-identical to the base recording; `make test-loop` `Arms solo:` line unchanged.
- In game (`/reload`, full restart after the TOC change): all five displays draw as before; config mode drag/anchors work; Masque skin applies; tooltip on a button; options panel shows the style dropdown and the classic tabs; switching a display to the timeline rebuilds it without a Lua error.
