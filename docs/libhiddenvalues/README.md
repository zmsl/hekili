# LibHiddenValues-1.0: developer notes

The library lives in `src/LibHiddenValues` (its own TOC, `LICENSE`, `README.md` for consumers and
`Testing/FakeClient.lua`), its suite in `tests/LibHiddenValues`, its tools in `tools/libhiddenvalues`, these notes in
`docs/libhiddenvalues`. It is built to leave this repository later by a pure move, so nothing in those code folders
names the addon it sits beside, and nothing there names it: `tools/libhiddenvalues/check_standalone.sh` (run by
`make api-check` and by `tests/LibHiddenValues/standalone_spec.lua`) fails otherwise. The package of the other addons
ignores the folder (`.pkgmeta`).

The design it follows is the standalone band library design of 2026-11-20 (working name Tidemark, renamed
LibHiddenValues), sections 1 to 7. Built: stages 0 and 1 (the skeleton and named health and power edges pushed every
frame, the measured mechanism), stage CDM-1 (the aura kind read from the Cooldown Manager, below), stage 3 (error
codes, position, exact points, point precision), lane C1 (the Cooldown Manager gaps before a consumer's switch,
below), the read-only cut (minor 6) and the fix lane (minor 7, below). Its in-game check:
[in-game-test-plan.md](in-game-test-plan.md).

## Built in the fix lane: the owner's in-game findings of 2026-11-21, minor 7

**Unproven in the library**: no in-game run yet ([in-game-test-plan.md](in-game-test-plan.md), "Fix lane").

- L1650 `Kinds/Aura.lua`: the C1 swap doubt covers every target watch, not only an Essential or Utility item's. The
  owner's run read a Tracked Buffs icon watch as a false 0 for 0.4-0.6 s after a swap onto a mob with the aura (the
  client shows a new target's auras once their update arrives). `up`, `stacks` and `left` target watches read unknown
  after PLAYER_TARGET_CHANGED until the source sees its item lit or a target UNIT_AURA comes. A cleared target stays
  unknown until a target UNIT_AURA. FakeClient: `W.cdm.lateSwap`.
- L1645 ring desyncs (`Bars.lua` `lib.decodeSource`): two invalid decodes in a row counted as a lost firing, but two
  changes on adjacent frames, each split over two frames, are invalid two frames in a row while firings still land
  (every desync of a fake run with each firing 1-2 frames late had its last two changes 2 and 3 frames back). A desync
  is now a bad decode after a bad one with no counted firing in between (`s.firedAt`, stamped in `lib.fire`), or
  `SETTLE` bad decodes in a row. Why the client splits one push's firings over frames is not known (a secret push's
  firing trailing a frame, as LHVProbe saw for a prime's live push, is the hypothesis). FakeClient: `jitter`, `seed`.
- L1645 ring aliases: with regen at 2-3 points per change, the ring's bars of a change across a cell boundary could
  land apart from the cell's: a valid state 50 off outside the I3 set (a fake run read 401 for 451). `suspect()` holds
  any ring decode whose cell moved other than the ring's own move says, so every real jump of 25 quanta or more pays
  one frame (fix round 1 widened it from 42-58 quanta: a spend whose Gray cell bits land in part reads another cell,
  516 for 116 and 1417 for 1467 in fake runs); the first valid ring decode after bad frames is held too (`s.qv` is
  stale then: 1246 +1 +1 +2 read 1200; review I1).
- L1645 energy 35, 36, 35, 36 (exact, max 100, position): no decode path. A one-point change toggles a Gray bit and
  the parity bar, and either alone fails the parity check (a hold); four alternating reads need Gray bit 2 to toggle
  three times, which a spend and up to 7 points of regen cannot give (both checked exhaustively in `position_spec`).
  The client's value went back over 36 (or a bar fired with no fill change); which is unproven in game.
- L1627 (2) `Bars.lua` `lib.sync`, `served`: a refused ring curve no longer suspends the whole source. The source falls
  back to the position set when a step watch is there, else to edges only (also when the percent Gray set itself is
  refused); only the handles that need the refused curves are `suspended` (precision; step without a position set).
- Residual rates (fake, 6 seeds x 150 s, max 2479, regen +2/+3 every 5-7 frames, a spend every 1-4 s, lag 1 plus
  jitter: each firing 1-2 frames late, harsher than the run's ~1 change in 4 split; Park-Miller seeds). Desyncs /
  sink calls outside the client's values of the last 9 frames / of those, 40 or more off that range:
  | regime | late | c01cbbdc4 | fix round 1 |
  |---|---|---|---|
  | drained (spend 100-399 from 1200) | 1-2 | 0 / 1 / 1 | 0 / 0 / 0 |
  | balanced (spend 30-94) | 1-2 | 0 / 1 / 0 | 0 / 1 / 0 |
  | sweep (spend 60-259 from the max, refilled each minute) | 1-2 | 0 / 4 / 1 | 0 / 1 / 0 |
  | drained | 1-3 | 1003 / 9 / 6 | 1038 / 2 / 1 |
  | balanced | 1-3 | 1017 / 13 / 13 | 1081 / 3 / 3 |
  | sweep | 1-3 | 939 / 5 / 5 | 984 / 2 / 2 |
  The 1-2 rows' remaining reads outside the range decode as a spend whose cell bars all landed a frame after its ring
  bars, the ring moved fewer than 25 quanta: a valid small change from the old value (272 for 122 after 269, 150
  off; the "40 or more off the range" column measures from the nearest recent value, so it misses it). The cost:
  about 8000 splits per 15 min (as before), the longest a reading stayed behind the client's value 11-14 frames at
  1-2 late (9-10 before) and 30-44 at 1-3 late (11 before; holds now count toward `SETTLE`); desyncs at 1-3 late rose
  3-6%.
- Read-only leftovers (L1649): `.luacheckrc` drops the unused `C_EncodingUtil`, `UnitClass`, `GetSpecialization`,
  `C_SpecializationInfo`; the in-game plan's minor statements read "or later".
- Fix round 1 (review of the fix lane): I2 `Kinds/Aura.lua` stamps `s.litAt` only when the item lit for the watch's
  own unit: an item lit on the player or on a secret unit no longer ends a target source's swap doubt (it read a false
  0 once the player's aura fell). I3 `h:Latency()` of a position or precision handle is `SETTLE + 2` frames (was 3),
  counted from the frame a change's first firing arrives: a bad frame after a hold counts the hold in `s.bad`, so at
  most `SETTLE` decodes go without a call, then the value or (a desync) unknown; measured 6 by two chains in
  `precision_spec`. M1: the minute-of-regen spec sweeps from the max to 36 (it sat below 100 for 3124 of its 3600
  frames). M2: FakeClient's `jitter` draws from Park-Miller (`seed` 1 to 2^31 - 2; the old LCG lost bits past 2^53).
- Known, not changed here: in edges mode `lib.decode` still counts a contradiction between edge bars as a desync at
  once (a jump over two edges whose firings split the wrong way re-primes, no hold). With the doubt on every target
  watch, a mob without the aura reads unknown until a target UNIT_AURA (about 2 s in the Essential run). Owner calls:
  every jump of 25 quanta or more and every first valid decode after bad frames pays a frame; the residual above (a
  jump's cell bars all late, its ring moved under 25) is not caught; `h:Latency()` is 6 frames for position and
  precision handles.

## Built in lane C1: Cooldown Manager gaps G1-G4, truths, the position set beside the ring, minor 5

**Unproven in the library**: no in-game run yet ([in-game-test-plan.md](in-game-test-plan.md), "Lane C1").

- G1 `Cdm.lua`: four viewers, index 1 bar, 2 icon, 3 Essential, 4 Utility (lower outranks). Essential and Utility
  items bind their linked aura as the aura viewers' do (`auraInstanceID`, `auraDataUnit`): `up` only. Their viewers
  get the same post-hooks (`OnAcquireItemFrame`, `RefreshData`); their items' widgets are never hooked. `stacks` and
  `left` there: `unavailable, cdm-cooldown-only`. Placement names `essential`, `utility`.
- G2 `Kinds/Aura.lua`: `cooldown = <cooldownID>` instead of `spell` (`spell-or-cooldown`, `cooldown-invalid`); its
  own source key; `cdm.statusOf(spell, what, cdw)` follows that entry only.
- G3 and the owner's rule (2026-11-21: the library outputs truths, consumers make assumptions): a held item on a
  secret, absent or other unit, and a secret `isEditing` or `IsVisible`, read unknown. An aura up with no count text
  reads [0, lowest stacks bar edge), never 1. `LHV:GetAuraEntries(spell)`: every entry naming a spell with the
  client's plain facts (the catalogue keeps them: `cdm.facts`), so a consumer chooses the entry itself.
- G4 `LibHiddenValues.lua`: `lib.capOf(kind, barless)`; an aura `up` handle (`h.barless`) skips the self-test's
  verdict, pending or failed; the kind's `barless(spec)` answers `IsAvailable` with a spec.
- Owner decision L1624 (2): `Bars.lua` keeps the position set (7 Gray bits + parity) beside a ring of point step
  above 1 while a step is asked, after the ring's bars in `s.core`. Its curves are cut on whole points per max
  (`lib.grayFor(M)`, cached and trimmed as the rings): the percent-scale set misreads 3967 of 6400 as 62% when the
  client snaps right or to the nearest point. The ring decode cross-checks the cell against the quantum's points
  ("cross": a bad frame, as a split; a desync by the rule of `lib.decodeSource`). A step joining or leaving re-allocates the whole core.
  `lib.need` counts the 8 bars whenever a step and precision share a source (at step 1 too: the step can grow with
  the max); a `step` watch is now admitted (pool-limit) like points and precision.
- Fix round 1 (review of 2026-11-21, owner rule "truths, not assumptions"): `Kinds/Aura.lua` counts target swaps
  (`cdm.swapNo`) and holds `cdm.doubt` from PLAYER_TARGET_CHANGED to the next target UNIT_AURA (registered for the
  target only, `Cdm.lua`); meanwhile a target watch's silent Essential or Utility item (since minor 7 every
  target watch's item) reads unknown unless that source saw it lit on the target since the swap (`s.litAt`, stamped only for the watch's
  own unit since minor 7's fix round; a source made after the swap is in doubt too). The viewers'
  RefreshData hook does not clear it: it may run at the swap itself. The client refreshes such an item on a target
  change only while it holds a target aura (no range check), so after A, B, A it can stay silent on A. `cdm.facts`
  keeps the client's `hasAura` and `selfAura` as given (rows of `GetAuraEntries`; nothing filters on them).
- `Testing/FakeClient.lua`: Essential and Utility viewers with item pools (`W.cdm.essential`, `W.cdm.utility`),
  `W.cdm.secretUnit`, `W.cdm.noUnit`, `W.cdm.quietSwap`, `Fake.secret`.
- Probe facts owed: is `auraDataUnit` ever secret in combat (aura viewers, Essential, Utility)? Is an item's
  `cooldownID` ever secret in combat (its watches then read unknown)? Does an Essential item show its
  aura in combat as it does out of combat?

## The managed layout (Mode B) is not in the library

Minor 6 removed it: the library only reads and writes no game state (no layout store, no viewer alpha, no reload).
The reviewed code is in git history (forever 9d03be787, d8118f21b) and moves into Hekili's integration lane C5.

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
- With the aura kind (merged at minor 3): its refusals are `LHV.ERR` codes too (`spell-invalid`, `what-invalid`,
  `max-invalid` added; the edges codes cover stacks and seconds); `IsAvailable("aura", spec)` keeps the reason
  `bad-spec`; `h:Latency()` of an aura handle is its measured worst case (up 2 frames, stacks `SETTLE + 1`, left
  `HOLD + SETTLE + 3`); the secret-max check runs under `pcall` (a raise counts as secret).

## Built in stages 0 and 1

- LibStub major `LibHiddenValues-1.0`, minor 7 (2: the aura kind; 3: stage 3; 4: CDM-2; 5: C1; 6: Mode B removed;
  7: the fix lane). Seven files after LibStub (`LibHiddenValues.lua`, `Bars.lua`, `Feed.lua`, `Kinds/Percent.lua`,
  `Cdm.lua`, `Kinds/Aura.lua`, `SelfTest.lua`); the first calls `NewLibrary` and sets `lib.loading`, the others return unless it is set, the last
  (`SelfTest.lua`) clears it. All state on `lib`; scripts are one-line dispatchers through `lib`. Nothing but the
  event frame is built before `PLAYER_LOGIN`; a copy loaded after login (load on demand, or a newer minor) realises
  at once, keeps the frames and re-primes every source.
- `Watch`, the handle (`Get`, `State`, `Domain`, `Exact`, `Latency`, `SetPaused`, `SetSink`, `SetPoints`, `Release`),
  `IsAvailable`, `OnCapability`, `SelfTest`, `GetSelfTest`, `GetStats`, `GetPool`, `GetSources`, `GetAuraSources`,
  `GetKinds`, `SetEnabled`, `GetMessage`, `ERR`,
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

## Built in stage CDM-1: the aura kind from the Cooldown Manager (read-only)

**Unproven in the library.** The probes (AuraBandProbe 0.2.0 and 0.2.1, CDMConfigProbe 0.2.0) proved the mechanisms;
this code has not run in game. Until an in-game run passes, treat every aura answer as unverified.

- `Cdm.lua` reads the client's Cooldown Manager: the catalogue (`C_CooldownViewer.GetCooldownViewerCategorySet(0-8)` and
  `GetCooldownViewerCooldownInfo`, out of combat only: spell, override, tooltip override and linked spells of each
  cooldownID), the active item frames of `BuffBarCooldownViewer` and `BuffIconCooldownViewer`
  (`itemFramePool:EnumerateActive()`, `rawget` of `cooldownID`, `auraInstanceID`, `auraDataUnit`) and
  four post-hooks (`hooksecurefunc`, each once): the viewers' `OnAcquireItemFrame` and `RefreshData` (a data change
  that keeps the item count acquires no frame and sends no event), an item's count FontString
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
  (`cooldownViewerEnabled`), the viewers' `RefreshData`. Separately, a watched item that no longer shows its
  cooldownID is searched again (at most every 30 frames) and, when it is gone, asks for a read.
- The shared machinery is reached by wrapping `lib.sync`, `lib.feed`, `lib.fire`, `lib.decode`, `lib.reprime`,
  `lib.event` and `lib.drive` for aura sources in `Kinds/Aura.lua` (no edit to `Bars.lua`, `Feed.lua`,
  `SelfTest.lua`); the core (`LibHiddenValues.lua`) gained the source key and fields, the per-source answer in
  `stateOf`, the kind's `why` in `capOf`, a spec argument to `IsAvailable`, and the aura top in `Domain()` and
  `Latency()`.

| Question | Taken | Why |
|---|---|---|
| A curve for hook values | none: raw narrow-range bars | a secret from a hook cannot go through a curve from addon code; the probes' per-stack and 2.9-3.0 s bars are what was proven |
| Seconds bar width | 0.01 s | the narrower, the rarer a landing inside; the run rule covers the landings that happen |
| Two firings of a seconds bar on consecutive frames | that bar primes again (HOLD + SETTLE + 2 frames, the seconds come every frame; one more when a secret firing trails its push: `h:Latency()`); its handles keep their band meanwhile | forcing "below" would stick wrong after a fall followed at once by a refresh (review); a flip is wrong for a landing inside |
| The first capability answer of a new watch | noted, not called | it is given inside `Watch`; the consumer reads `h:State()` after it |
| `up` | the item's `auraInstanceID` secret or not nil, polled every frame, no bar | the proven presence read; it is plain to test |
| Stacks and seconds while absent | the lowest band (0 stacks, 0 seconds), live | controller decision (review I1): the item holding no aura of yours is a known reading (not proof of absence: F10 only the player's own auras, helpful ones on the player; F12 an item silent a whole fight with its aura up); `"live"` never comes without a band |
| An aura up with no count | [0, lowest stacks bar edge): `[0, 2)` with `max`, `[0, 3)` with edges `{ 3 }` (lane C1; was 1 stack) | the client hides the count at 0 and 1 stack; the library reports what it sees (owner rule 2026-11-21) |
| Linked, override and tooltip spells | they answer for the entry: whatever aura of it the client shows | the catalogue maps them to the cooldownID; the shown aura's spell is not read (review M2) |
| `left` on an aura with no duration | the lowest band while up | the client pushes 0 seconds for it (review M3) |
| `stacks` edge 1 | no bar: told only by the aura being absent | the count text is `""` for one stack or none |
| A count of `""` or plain digits | `tonumber(text) or 0` | out of combat the client passes a string |
| Identity | the item's `cooldownID` read at each use; secret: the item is unknown (its watches `gone`) and its pushes are dropped (lane C1 fix round 1; was the item's `layoutIndex` in the order last read plain) | frames reshuffle and the layout can be edited in combat (F13), so an index read before could name another entry; Hekili's leaf also requires a plain ID; the in-combat secrecy of the ID is unprobed |
| A shown aura on the other unit | unknown (`gone`) for this watch (lane C1; was not up): a watch on each unit of one entry reads unknown on one while the aura is up on the other; a secret or absent unit is unknown too | the item scans player then target; whether a target aura can outrank a player one is unsettled, so 0 would be a guess |
| Priming | a new bar holds low 4 frames, then counts; it is read `SETTLE` (4) frames after the client's first push (and again after each absence); after a prime the handle is unknown until then, after an absence or a run the band stands | a secret is never kept, so nothing can be re-fed; stacks come only when the count is rewritten; a firing can trail its push (review I2, as the percent prime settle) |
| `IsAvailable(kind, spec)` | answers from the last read and asks for a new one next frame | it must not call capability callbacks (review M5) |
| Errors | an errored aura kind's hooks return at once | a body raising every frame would re-sync every kind per call (review M1) |
| Target swap | no priming for aura bars | the bars follow the client's pushes; priming would drop the swap's own push |
| Re-layout | aura bars prime | a stray firing would invert a toggle |
| A paused aura handle | reports unknown, its bars stay fed | the pushes are the client's; pausing saves nothing |
| A hidden viewer, Edit Mode | the handle is `gone` | a hidden viewer stops its events; Edit Mode shows placeholder data (`isEditing`, read from the client's code, unprobed) |
| Edit Mode "Hidden" or "In Combat" visibility | no reason of its own (`gone` while hidden) | the brief's reason list; `cdm-hidden` is left for a later stage |
| Catalogue in combat | not read: `pending` until combat ends | in-combat secrecy of the catalogue reads is unprobed |
| `SetMinMaxValues` hook | not built | seconds edges need only `SetValue`; the percent route through a secret max is closed (AuraBandProbe 0.2.1) |
| Essential and Utility items | `up` read (lane C1 G1); `stacks` and `left` `unavailable, cdm-cooldown-only` | they give presence of a linked aura only (clean-room doc P2.3); the two aura viewers serve more |
| Errors | an error in a hook, an event or a read turns the aura kind off (`error`); the other kinds carry on | the design's per-kind rule |

## Choices taken where the design left one open

| Question | Taken | Why |
|---|---|---|
| Power type field | `power` (the design's name), required: omitted is `power-required` | a default (the displayed power) would let a form change turn an energy handle into a mana one with nothing in the API saying so (review I1, owner question 1); adding a default later stays compatible, removing one would not |
| `unit` | required for both kinds | the design gives no default |
| Edges | numbers in (0.05, 100]; duplicates and edges closer than 0.05 merge into the lower | an edge needs room for its guard point above 0 |
| `step` (stage 3) | any step is granted as 1 (the Gray 7 + parity set); `Domain()` says 1 | finer needs more curve points than proven; coarser saves at most 2 bars |
| Error codes (stage 3, L1616) | the brief's list plus `owner-invalid`, `spec-invalid`, `sink-invalid`, `kind-invalid` for the other refusals | every refusal gets a code; the API doc was not reachable from the lane |
| Points units (stage 3) | a handle with `points` (or point precision) answers in points, every other in percent; `SetPoints` on a percent handle is `points-invalid` | a handle never changes units; Hekili's APL thresholds are points |
| Point caps (stage 3, L1613) | 8 / 64 distinct points, each counted as edges mode would place it (with a bar), checked at the request; so a mode ending (a step or precision listener leaving) stays within them; a new max allocates without re-checking (the pool can still refuse: `suspended`) | admission control, never revocation; review I5 |
| `pool-limit` | for points, point-precision and (since lane C1) step requests; plain percent edges over the pool stay `suspended` (stage 1 rule) | the brief scopes it to those requests; a step joining a full precision source suspended the whole source |
| Curve size (stage 3) | at most 256 points per curve (BandProbe2 D1: 256 accepted, 512 refused), so 127 guarded steps; the ring's point step grows past a max of 3175 | the brief's "256 steps" would build 513-point curves |
| Mode changes (stage 3) | a step or point listener joining or leaving frees and allocates at once: the source's other handles go unknown for one prime (about 10 frames) when their bars move | shortcut: keep the old bars until the new set is live if this blinds consumers in practice |
| Position split/desync (stage 3; fix lane) | design 3.3: one bad decode holds the last band (`splits`); a bad decode after a bad one with no firing between, or `SETTLE` in a row, re-primes (`desyncs`) | design 3.3 had two in a row; a change still landing is not a lost firing (owner run 2026-11-21); the COARSE fallback is not built |
| `points` or `precision` on health, power types other than mana, rage and energy, other tokens | handle `unavailable, unproven` | unproven in the run |
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
event-driven, throttled and near-threshold feeding and the governor (stage 4; `GetStats` returns level 0);
aura sound and private-copy tiers, upgrade hints,
`cdm-hidden` and `cdm-combat-only`, icon timers; booleans, groups, other tokens (6); timers (7); threat, absorbs,
meter (9); the `restricted` reason for PvP matches (an error there turns the kind off as `error` instead); the cached self-test verdict; the 5 s release grace.

## Checks

`make check` runs the suite (`tests/LibHiddenValues`, in `.busted` ROOT for `make test-serial`), luacheck (the
library's client globals are declared in `.luacheckrc`), StyLua (the vendored LibStub is excluded) and the standalone
grep.
