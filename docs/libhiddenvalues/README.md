# LibHiddenValues-1.0: developer notes

The library lives in `src/LibHiddenValues` (its own TOC, `LICENSE`, `README.md` for consumers and
`Testing/FakeClient.lua`), its suite in `tests/LibHiddenValues`, its tools in `tools/libhiddenvalues`, these notes in
`docs/libhiddenvalues`. It is built to leave this repository later by a pure move, so nothing in those code folders
names the addon it sits beside, and nothing there names it: `tools/libhiddenvalues/check_standalone.sh` (run by
`make api-check` and by `tests/LibHiddenValues/standalone_spec.lua`) fails otherwise. The package of the other addons
ignores the folder (`.pkgmeta`).

The design it follows is the standalone band library design of 2026-11-20 (working name Tidemark, renamed
LibHiddenValues), sections 1 to 7. This is stages 0 and 1: the skeleton and named health and power edges pushed every
frame, the measured mechanism. Its in-game check: [in-game-test-plan.md](in-game-test-plan.md).

## Built in stages 0 and 1

- LibStub major `LibHiddenValues-1.0`, minor 1. Six files after LibStub; the first calls `NewLibrary` and sets
  `lib.loading`, the others return unless it is set, the last clears it. All state on `lib`; scripts are one-line
  dispatchers through `lib`. Nothing but the event frame is built before `PLAYER_LOGIN`; a copy loaded after login
  (load on demand, or a newer minor) realises at once, keeps the frames and re-primes every source.
- `Watch`, the handle (`Get`, `State`, `Domain`, `Exact`, `Latency`, `SetPaused`, `SetSink`, `Release`), `IsAvailable`,
  `OnCapability`, `SelfTest`, `GetStats`, `SetEnabled`, `ReleaseAll`, `GetVersion`, the quality codes.
- Sources by canonical key (kind, unit, power type, predicted); one bar per edge per source, reference counted; each
  handle a view cut by its own edges; a new edge primes only its own bar.
- The pool (32 made at login, cap 256, growth in combat under pcall), one Step curve per edge (guard point 0.0005
  below the step on the fixed 0-1 x scale), bars ranged 0-2 under one root at alpha 0, priming held 4 frames.
- The plain self-test at login (three bars, ten values, about 45 frames): firings must equal changes, within 3
  frames, and every curve output must follow the convention. Kinds are `pending` until it passes.
- Capability reasons `api`, `selftest`, `error`, `off`, `unproven`, `unknown-kind`.
- `/lhv` with `selftest`/`test`, `stats`, `watch`, `watch off`, `copy`, `off`, `on` (`on` runs the self-test and
  prints its lines, so it also recovers from a failed verdict).

## Choices taken where the design left one open

| Question | Taken | Why |
|---|---|---|
| Power type field | `power` (the design's name), required: omitted is `bad-spec` | a default (the displayed power) would let a form change turn an energy handle into a mana one with nothing in the API saying so (review I1, owner question 1); adding a default later stays compatible, removing one would not |
| `unit` | required for both kinds | the design gives no default |
| Edges | numbers in (0.05, 100]; duplicates and edges closer than 0.05 merge into the lower | an edge needs room for its guard point above 0 |
| `step` | with edges: the edges are granted and `Domain()` returns `nil, 0, 100`; alone: `unavailable, unproven` | position is stage 3 (the design's own coarsening rule: report the granted domain) |
| `points = true`, rage, other tokens | handle `unavailable, unproven` | unproven in the run |
| Aura | a known kind, permanently `unavailable, unproven` | the aura container closed the route (design addendum) |
| Sink timing (owner question 9) | mixed, as recommended: one-edge handles from the firing, several edges one frame later | the design's recommendation; `h:Latency()` says which |
| Views (owner question 5) | per-handle views only | the design's recommendation |
| Death | plain `UnitIsDead` true: health handles go `gone`; a secret answer keeps the bands | the `dead` boolean bar is stage 6 |
| Inconsistent edges (above a higher edge, below a lower one) | counted as a desync; the source re-primes | the shadow check that would correct it is stage 2 |
| Re-layouts | every fed source re-primes on `UI_SCALE_CHANGED`, `DISPLAY_SIZE_CHANGED`, `LOADING_SCREEN_DISABLED` (each registered under `pcall`: the client raises on an unknown event) | a re-layout may fire a clip whose fill did not change, which inverts a one-edge handle (review I3); this corrects a stray firing before the event or within the 4 hold frames after it, not a later one |
| Sink `t` | `GetTime()` of the frame the change was seen: the firing, or the live push that ends priming, when that was this frame or the last; else the call's frame | design 2.3 (review M3) |
| Bar cap | a handle missing a bar is `suspended` and does not keep its source fed; its partial bars stay allocated | the governor (stage 4) owns the cap (review M1) |
| Self-test with a full pool | reports `selftest not run: no free bar`, the earlier verdict stands | a full pool says nothing about the mechanism (review M2) |
| Root frame | parented and anchored to `UIParent` (bottom left), alpha 0 | the run's measured shape; a parentless root is unprobed (owner question 11) |
| `OnSizeChanged` | `SetScript` on our own child frame | the design forbids `HookScript` (a hook cannot be removed); the probe used `HookScript`, so the self-test proves `SetScript` in game |
| SavedVariables | none | nothing needs to persist yet: no cached verdict, `/lhv off` is per session |

## Not built (later stages)

Shadow verification and the `silent` detector, plain-read calibration and `q = EXACT` (stage 2; the BandProbe2
warm-up found health and power secret even out of combat, so there may be no plain truth to calibrate against);
position (Gray code and parity, stage 3: the encoding is internal to `Bars.lua`'s decode, so it joins without an API
change); event-driven, throttled and near-threshold feeding and the governor (stage 4; `GetStats` returns level 0);
rage (5); booleans, groups, other tokens (6); timers (7); threat, absorbs, meter (9); the `restricted` reason for PvP
matches (an error there turns the kind off as `error` instead); the cached self-test verdict; the 5 s release grace.

## Checks

`make check` runs the suite (`tests/LibHiddenValues`, in `.busted` ROOT for `make test-serial`), luacheck (the
library's client globals are declared in `.luacheckrc`), StyLua (the vendored LibStub is excluded) and the standalone
grep.
