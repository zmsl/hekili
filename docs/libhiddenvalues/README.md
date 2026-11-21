# LibHiddenValues-1.0: developer notes

The library lives in `src/LibHiddenValues` (its own TOC, `LICENSE`, `README.md` for consumers and
`Testing/FakeClient.lua`), its suite in `tests/LibHiddenValues`, its tools in `tools/libhiddenvalues`, these notes in
`docs/libhiddenvalues`. It is built to leave this repository later by a pure move, so nothing in those code folders
names the addon it sits beside, and nothing there names it: `tools/libhiddenvalues/check_standalone.sh` (run by
`make api-check` and by `tests/LibHiddenValues/standalone_spec.lua`) fails otherwise. The package of the other addons
ignores the folder (`.pkgmeta`).

The design it follows is the standalone band library design of 2026-11-20 (working name Tidemark, renamed
LibHiddenValues), sections 1 to 7. This is stages 0 and 1: the skeleton and named health and power edges pushed every
frame, the measured mechanism; and stage CDM-1: the aura kind read from the Cooldown Manager (below). Its in-game
check: [in-game-test-plan.md](in-game-test-plan.md).

## Built in stages 0 and 1

- LibStub major `LibHiddenValues-1.0`, minor 1. Seven files after LibStub; the first calls `NewLibrary` and sets
  `lib.loading`, the others return unless it is set, the last (`SelfTest.lua`) clears it. All state on `lib`; scripts
  are one-line dispatchers through `lib`. Nothing but the event frame is built before `PLAYER_LOGIN`; a copy loaded
  after login (load on demand, or a newer minor) realises at once, keeps the frames and re-primes every source.
- `Watch`, the handle (`Get`, `State`, `Domain`, `Exact`, `Latency`, `SetPaused`, `SetSink`, `Release`), `IsAvailable`,
  `OnCapability`, `SelfTest`, `GetSelfTest`, `GetStats`, `GetPool`, `GetSources`, `GetKinds`, `SetEnabled`,
  `ReleaseAll`, `GetVersion`, the quality codes.
- Sources by canonical key (kind, unit, power type, predicted); one bar per edge per source, reference counted; each
  handle a view cut by its own edges; a new edge primes only its own bar.
- The pool (32 made at login, cap 256, growth in combat under pcall), one Step curve per edge (guard point 0.0005
  below the step on the fixed 0-1 x scale), bars ranged 0-2 under one root at alpha 0, priming held 4 frames, then
  settled 4 (fed live, firings counted, the handle still unknown: its first band is the real one, dir 0, once).
- The plain self-test at login (three bars, ten values, about 45 frames): firings must equal changes, within 3
  frames, and every curve output must follow the convention; a fourth bar, primed as a source's bar is (held low,
  then a read through a curve that is 2 everywhere), must fire once inside the settle window and never after (the
  `selftest prime:` line; a plain login read proves the plain prime timing, and the owner's run of 2026-11-20 passed
  it in game). Kinds are `pending` until it passes.
- Capability reasons `api`, `selftest`, `error`, `off`, `unproven`, `unknown-kind`.
- A pure API: no slash command, no chat output, no frame of its own that shows. Every diagnostic fact is a getter
  (the consumer README's Diagnostics table); LHVProbe, outside this repository, is the reference consumer (`/lhvp`).

## Built in stage CDM-1: the aura kind from the Cooldown Manager (Mode A, read-only)

**Unproven in the library.** The probes (AuraBandProbe 0.2.0 and 0.2.1, CDMConfigProbe 0.2.0) proved the mechanisms;
this code has not run in game. Until an in-game run passes, treat every aura answer as unverified.

- `Cdm.lua` reads the client's Cooldown Manager: the catalogue (`C_CooldownViewer.GetCooldownViewerCategorySet(0-8)` and
  `GetCooldownViewerCooldownInfo`, out of combat only: spell, override, tooltip override and linked spells of each
  cooldownID), the active item frames of `BuffBarCooldownViewer` and `BuffIconCooldownViewer`
  (`itemFramePool:EnumerateActive()`, `rawget` of `cooldownID`, `layoutIndex`, `auraInstanceID`, `auraDataUnit`) and
  three post-hooks (`hooksecurefunc`, each once): the viewers' `OnAcquireItemFrame`, an item's count FontString
  `SetText` (stacks) and a tracked bar's StatusBar `SetValue` (seconds left). It never shows, hides, fades, moves,
  re-lays out or refreshes anything, and calls no provider method.
- `Kinds/Aura.lua` is the kind: spec `{ kind = "aura", unit = "player" | "target", spell, what = "up" | "stacks" |
  "left", edges, max }`; reasons `cdm-off`, `not-in-cdm`, `cdm-not-tracked`, `cdm-icon-only`; `IsAvailable(kind,
  spec)`, per-handle `OnCapability` calls, `GetAuraSources()`.
- Bars: each edge is a raw bar ranged just below it (stacks `(e - 1, e)`, seconds `(e - 0.01, e)`) fed the hook's
  value as it is; a firing is a toggle, except that a seconds bar firing on the frame after its last firing primes
  again while its handles keep their band (the run rule: a falling timer may land inside the bar for a frame, which a
  toggle cannot tell from a fall followed at once by a refresh). Presence needs no bar.
- Re-reads: an acquire hook, `COOLDOWN_VIEWER_DATA_LOADED`, `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`,
  `COOLDOWN_VIEWER_TABLE_HOTFIXED`, `PLAYER_REGEN_ENABLED`, `PLAYER_LEVEL_CHANGED`, `CVAR_UPDATE`
  (`cooldownViewerEnabled`), and any frame in which a watched item no longer shows its cooldownID.
- The shared machinery is reached by wrapping `lib.sync`, `lib.feed`, `lib.fire`, `lib.decode`, `lib.reprime`,
  `lib.event` and `lib.drive` for aura sources in `Kinds/Aura.lua` (no edit to `Bars.lua`, `Feed.lua`,
  `SelfTest.lua`); the core (`LibHiddenValues.lua`) gained the source key and fields, the per-source answer in
  `stateOf`, the kind's `why` in `capOf`, a spec argument to `IsAvailable`, and the aura top in `Domain()` and
  `Latency()`.

| Question | Taken | Why |
|---|---|---|
| A curve for hook values | none: raw narrow-range bars | a secret from a hook cannot go through a curve from addon code; the probes' per-stack and 2.9-3.0 s bars are what was proven |
| Seconds bar width | 0.01 s | the narrower, the rarer a landing inside; the run rule covers the landings that happen |
| Two firings of a seconds bar on consecutive frames | that bar primes again (HOLD + 2 frames, the seconds come every frame); its handles keep their band meanwhile | forcing "below" would stick wrong after a fall followed at once by a refresh (review); a flip is wrong for a landing inside |
| The first capability answer of a new watch | noted, not called | it is given inside `Watch`; the consumer reads `h:State()` after it |
| `up` | the item's `auraInstanceID` secret or not nil, polled every frame, no bar | the proven presence read; it is plain to test |
| Stacks and seconds while absent | unknown | the brief's contract; `up` carries absence |
| `stacks` edge 1 | presence, no bar | the count text is `""` for one stack or none |
| A count of `""` or plain digits | `tonumber(text) or 0` | out of combat the client passes a string |
| Identity | the item's `cooldownID` read at each use; secret: its `layoutIndex` in the order last read plain; both secret: the item is `gone` | frames reshuffle in combat; the in-combat secrecy of these fields is unprobed |
| A shown aura on the other unit | not up for this watch | the item scans player then target; `auraDataUnit` says which (a secret one counts as this unit) |
| Priming | a new bar holds low 4 frames, then counts; its band waits for the client's next push (and again after each absence) | a secret is never kept, so nothing can be re-fed; stacks come only when the count is rewritten |
| Target swap | no priming for aura bars | the bars follow the client's pushes; priming would drop the swap's own push |
| Re-layout | aura bars prime | a stray firing would invert a toggle |
| A paused aura handle | reports unknown, its bars stay fed | the pushes are the client's; pausing saves nothing |
| A hidden viewer, Edit Mode | the handle is `gone` | a hidden viewer stops its events; Edit Mode shows placeholder data (`isEditing`, read from the client's code, unprobed) |
| Edit Mode "Hidden" or "In Combat" visibility | no reason of its own (`gone` while hidden) | the brief's reason list; `cdm-hidden` is left for a later stage |
| Catalogue in combat | not read: `pending` until combat ends | in-combat secrecy of the catalogue reads is unprobed |
| `SetMinMaxValues` hook | not built | seconds edges need only `SetValue`; the percent route through a secret max is closed (AuraBandProbe 0.2.1) |
| Essential and Utility items | `cdm-not-tracked` | they give presence of a linked aura only (clean-room doc P2.3); Mode A serves the two aura viewers |
| Errors | an error in a hook, an event or a read turns the aura kind off (`error`); the other kinds carry on | the design's per-kind rule |

## Choices taken where the design left one open

| Question | Taken | Why |
|---|---|---|
| Power type field | `power` (the design's name), required: omitted is `bad-spec` | a default (the displayed power) would let a form change turn an energy handle into a mana one with nothing in the API saying so (review I1, owner question 1); adding a default later stays compatible, removing one would not |
| `unit` | required for both kinds | the design gives no default |
| Edges | numbers in (0.05, 100]; duplicates and edges closer than 0.05 merge into the lower | an edge needs room for its guard point above 0 |
| `step` | with edges: the edges are granted and `Domain()` returns `nil, 0, 100`; alone: `unavailable, unproven` | position is stage 3 (the design's own coarsening rule: report the granted domain) |
| `points = true`, power types other than mana, rage and energy, other tokens | handle `unavailable, unproven` | unproven in the run |
| Rage (controller for the owner, 2026-11-20) | `ready` on `player` like mana and energy, the same `UnitPowerPercent` read | proven by the BandProbe2 warm-up (bear form, in combat under the lockdown: Gray 7 bits + parity and the 20-bar bank, 0 disagreements, desync 0); the library's own in-game run is owed. Rage sits at 0 out of combat: below the lowest edge it primes to the known lowest band |
| Aura | read from the Cooldown Manager (stage CDM-1, above); the aura container route stays closed | design addenda L1576, L1577, L1582 |
| Sink timing (owner question 9) | mixed, as recommended: one-edge handles from the firing, several edges one frame later | the design's recommendation; `h:Latency()` says which |
| Views (owner question 5) | per-handle views only | the design's recommendation |
| Death | plain `UnitIsDead` true: health handles go `gone`; a secret answer keeps the bands | the `dead` boolean bar is stage 6 |
| Inconsistent edges (above a higher edge, below a lower one) | counted as a desync; the source re-primes | the shadow check that would correct it is stage 2 |
| Re-layouts | every fed source re-primes on `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED`, `LOADING_SCREEN_DISABLED` (each registered under `pcall`: the client raises on an unknown event) | a re-layout may fire a clip whose fill did not change, which inverts a one-edge handle (review I3); this corrects a stray firing before the event or within the 4 hold frames after it, not a later one |
| Priming settle (LHVProbe 2026-11-20) | after the 4 hold frames the live push is followed by 4 settle frames: firings toggle the bars, the handle stays unknown, the next frame decodes once | the in-game log showed every prime's live-push firing arriving one frame after the decode that followed it: the lowest band with dir 0, then the real band with dir 1 a frame later. 4 = the self-test's plain lag limit (3) plus the frame a secret push added; BandProbe v1 counted 4 frames after the push (`IN window 4`). Owner call: a shorter window primes faster but must stay at or above the self-test's lag limit |
| Sink `t` | `GetTime()` of the frame the change was seen: the firing, or the last settle frame that ends priming, when that was this frame or the last; else the call's frame | design 2.3 (review M3) |
| Bar cap | a handle missing a bar is `suspended` and does not keep its source fed; its partial bars stay allocated | the governor (stage 4) owns the cap (review M1) |
| Self-test with a full pool | reports `selftest not run: no free bar`, the earlier verdict stands | a full pool says nothing about the mechanism (review M2) |
| Root frame | parented and anchored to `UIParent` (bottom left), alpha 0 | the run's measured shape; a parentless root is unprobed (owner question 11) |
| `OnSizeChanged` | `SetScript` on our own child frame | the design forbids `HookScript` (a hook cannot be removed); the probe used `HookScript`, so the self-test proves `SetScript` in game |
| SavedVariables | none | nothing needs to persist yet: no cached verdict, `SetEnabled(false)` is per session |
| Diagnostics (owner 2026-11-20) | no `/lhv` command, no print, no copy box: getters only (`GetKinds`, `GetSources`, `GetSelfTest`, `GetPool`; `GetStats` unchanged); the consumer (LHVProbe `/lhvp`) prints | a library is a pure API surface; output, commands and UI belong to the addon that wants them. Recovery after a failed self-test is `SelfTest(fn)` (`SetEnabled(true)` alone changes nothing when already on) |

## Not built (later stages)

Shadow verification and the `silent` detector, plain-read calibration and `q = EXACT` (stage 2; the BandProbe2
warm-up found health and power secret even out of combat, so there may be no plain truth to calibrate against);
position (Gray code and parity, stage 3: the encoding is internal to `Bars.lua`'s decode, so it joins without an API
change); the Cooldown Manager's Mode B (managed layout, CDM-2), aura sound and private-copy tiers, upgrade hints,
`cdm-hidden` and `cdm-combat-only`, icon timers; event-driven, throttled and near-threshold feeding and the governor
(stage 4; `GetStats` returns level 0); booleans, groups, other tokens (6); timers (7); threat, absorbs, meter (9); the
`restricted` reason for PvP
matches (an error there turns the kind off as `error` instead); the cached self-test verdict; the 5 s release grace.

## Checks

`make check` runs the suite (`tests/LibHiddenValues`, in `.busted` ROOT for `make test-serial`), luacheck (the
library's client globals are declared in `.luacheckrc`), StyLua (the vendored LibStub is excluded) and the standalone
grep.
