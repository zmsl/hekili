# LibHiddenValues-1.0: developer notes

The library lives in `src/LibHiddenValues` (its own TOC, `LICENSE`, `README.md` for consumers and
`Testing/FakeClient.lua`), its suite in `tests/LibHiddenValues`, its tools in `tools/libhiddenvalues`, these notes in
`docs/libhiddenvalues`. It is built to leave this repository later by a pure move, so nothing in those code folders
names the addon it sits beside, and nothing there names it: `tools/libhiddenvalues/check_standalone.sh` (run by
`make api-check` and by `tests/LibHiddenValues/standalone_spec.lua`) fails otherwise. The package of the other addons
ignores the folder (`.pkgmeta`).

The design it follows is the standalone band library design of 2026-11-20 (working name Tidemark, renamed
LibHiddenValues), sections 1 to 7. Built: stages 0 and 1 (the skeleton and named health and power edges pushed every
frame, the measured mechanism) and stage 3 (error codes, position, exact points, point precision). Its in-game check:
[in-game-test-plan.md](in-game-test-plan.md).

## Built in stage 3

- Error codes: `LHV.ERR`, `LHV:GetMessage(code, locale)` (enUS only), every refusal `nil, code` (owner L1616).
- Position (`step`): per source a mode, chosen by its watches: edges only; `gray` (any step: the Gray code of the 1%
  cell on 7 bars plus a parity bar, design 3.3; edges on the 1% grid need no bar); `ring` (any point precision at a
  max over 100). A position decode checks the code, the parity and every edge and point bar against the cell.
- Points (owner L1613): cut at `(points - 0.5) / max` with a guard a quarter point below (BandProbe2 0.3.0's
  construction), the plain player max read under `C_Secrets.ShouldUnitPowerMaxBeSecret`, re-read on
  `UNIT_MAXPOWER`. Admission (`lib.need`, `lib.admit`) counts the bars a source's watches would need.
- Point precision (owner L1614): BandProbe2 0.3.0's C50 ring (`Bars.lua`, `lib.ringFor`): 50 fine bars, a Gray cell
  code, a parity bar; a fine bar steps every 25 quanta, so the point step grows past a max of 3175 (127 steps per
  curve). Every other watch on that source is answered from the exact value.
- `GetStats` zeroes its times and rates when the driver stops (nothing fed) and returns `splits` 8th; `GetPool`
  returns the point caps; `GetSources` rows carry `mode` and `max`.

## Built in stages 0 and 1

- LibStub major `LibHiddenValues-1.0`, minor 2 (stage 3). Five files after LibStub; the first calls `NewLibrary`
  and sets `lib.loading`, the others return unless it is set, the last (`SelfTest.lua`) clears it. All state on `lib`;
  scripts are one-line dispatchers through `lib`. Nothing but the event frame is built before `PLAYER_LOGIN`; a copy
  loaded after login (load on demand, or a newer minor) realises at once, keeps the frames and re-primes every source.
- `Watch`, the handle (`Get`, `State`, `Domain`, `Exact`, `Latency`, `SetPaused`, `SetSink`, `SetPoints`, `Release`),
  `IsAvailable`, `OnCapability`, `SelfTest`, `GetSelfTest`, `GetStats`, `GetPool`, `GetSources`, `GetKinds`,
  `SetEnabled`, `GetMessage`, `ERR`,
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

## Choices taken where the design left one open

| Question | Taken | Why |
|---|---|---|
| Power type field | `power` (the design's name), required: omitted is `power-required` | a default (the displayed power) would let a form change turn an energy handle into a mana one with nothing in the API saying so (review I1, owner question 1); adding a default later stays compatible, removing one would not |
| `unit` | required for both kinds | the design gives no default |
| Edges | numbers in (0.05, 100]; duplicates and edges closer than 0.05 merge into the lower | an edge needs room for its guard point above 0 |
| `step` (stage 3) | any step is granted as 1 (the Gray 7 + parity set); `Domain()` says 1 | finer needs more curve points than proven; coarser saves at most 2 bars |
| Error codes (stage 3, L1616) | the brief's list plus `owner-invalid`, `spec-invalid`, `sink-invalid`, `kind-invalid` for the other refusals | every refusal gets a code; the API doc was not reachable from the lane |
| Points units (stage 3) | a handle with `points` (or point precision) answers in points, every other in percent; `SetPoints` on a percent handle is `points-invalid` | a handle never changes units; Hekili's APL thresholds are points |
| Point caps (stage 3, L1613) | 8 / 64 bar-needing points, checked at the request; a later mode change (a step or point listener leaving, a new max) allocates without re-checking (the pool can still refuse: `suspended`) | admission control, never revocation |
| `pool-limit` | for points and point-precision requests only; plain percent edges over the pool stay `suspended` (stage 1 rule) | the brief scopes it to those requests |
| Curve size (stage 3) | at most 256 points per curve (BandProbe2 D1: 256 accepted, 512 refused), so 127 guarded steps; the ring's point step grows past a max of 3175 | the brief's "256 steps" would build 513-point curves |
| Mode changes (stage 3) | a step or point listener joining or leaving frees and allocates at once: the source's other handles go unknown for one prime (about 10 frames) when their bars move | shortcut: keep the old bars until the new set is live if this blinds consumers in practice |
| Position split/desync (stage 3) | design 3.3: one bad decode holds the last band (`splits`), two in a row re-prime (`desyncs`) | as designed; the COARSE fallback is not built |
| `points` or `precision` on health, power types other than mana, rage and energy, other tokens | handle `unavailable, unproven` | unproven in the run |
| Rage (controller for the owner, 2026-11-20) | `ready` on `player` like mana and energy, the same `UnitPowerPercent` read | proven by the BandProbe2 warm-up (bear form, in combat under the lockdown: Gray 7 bits + parity and the 20-bar bank, 0 disagreements, desync 0); the library's own in-game run is owed. Rage sits at 0 out of combat: below the lowest edge it primes to the known lowest band |
| Aura | a known kind, permanently `unavailable, unproven` | the aura container closed the route (design addendum) |
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
event-driven, throttled and near-threshold feeding and the governor (stage 4; `GetStats` returns level 0);
booleans, groups, other tokens (6); timers (7); threat, absorbs, meter (9); the `restricted` reason for PvP
matches (an error there turns the kind off as `error` instead); the cached self-test verdict; the 5 s release grace.

## Checks

`make check` runs the suite (`tests/LibHiddenValues`, in `.busted` ROOT for `make test-serial`), luacheck (the
library's client globals are declared in `.luacheckrc`), StyLua (the vendored LibStub is excluded) and the standalone
grep.
