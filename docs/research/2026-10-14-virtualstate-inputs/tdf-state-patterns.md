<!-- Research output saved verbatim from the 2026-10-14 planning session (sonnet Explore agent, read-only survey of ~/src/TacoDogForever): the TDF state-tracking patterns inventory the VirtualState spec cites. -->

I couldn't write `/home/zack/.claude/jobs/5926f0e9/tmp/reports/tdf-state-patterns.md`. This session is read-only and has no file-write tool. The full report is below so you can save it. The 10-line summary comes first.

## 10-line summary

1. **Log:** a preallocated 256-slot ring (`ObsLog`) of `{kind,t,a,b,c}` records. Sources write them, the belief drains it, oldest first, at the start of each recalculation, and `Clear` empties it. Overflow drops the oldest and counts it.
2. **Staging:** aura reads go straight to the log. Every other event is staged (cap 128) and flushed next frame, so a frame's aura reads always precede its casts. Every record is stamped with that frame's `GetTime()`.
3. **State:** a belief layer keeps `{input,id,est,lo,hi,anchorT,anchorKind,conf}` per hidden value. Each recalculation `Belief.Write` copies it into a flat preallocated array state (`s.res[slot]`, `s.auraExp[id]`, `s.cdReady[a]`).
4. **No metatable API:** there is no `buff.x.remains` object. The APL compiler turns it into generated Lua over those arrays (`rem(s.auraExp[m], t)`). Only the ID tables use metatables (`NewSpec.lua:16`).
5. **Secrets:** every client value goes through `Sources.Plain(api, v)`, which returns nil for a secret. A secret means no observation is logged. Reads are `pcall`'d, and per-read status strings ("secret"/"readable"/"nil") feed `/tdf selftest`.
6. **Secret pass-through:** the only place a secret is passed to the game is `Render.lua` (the `TickGate` curve alpha and `SetSpellCooldown`), and it is never read. `C_Secrets` is not used in code, only mentioned in a `Target.lua:29` comment and in the feasibility doc.
7. **Unknown has no tri-state.** It is a wide interval plus low `conf`, or a per-field sentinel such as -1, 0 or `NEVER`/`HUGE`. `Model.Simulate` runs the whole APL three times (Est/Lo/Hi). If the picks disagree, the slot is `Fuzzy` with `tLo..tHi` and lower `conf`.
8. **Nowcast:** the belief runs the engine itself on observations. Time passing applies regen and scheduled events; a cast runs the ability's handler. Cooldowns, auras and swings are absolute-time entries anchored by observations, with `conf` decaying (swing over 10 s, target aura halving every 10 s).
9. **Docs:** design spec v2 §3, §5.1/5.3, §6, §7.3, §8.1, §17.1/17.2, §18.3 and §20.3 define state semantics. The gap IDs about state are G003, G015, G016, G020–G023, G027–G031, G033, G035, G037, G045, G046, G048 and G057 (full list in the report).
10. **Lessons:** the best sources are the "As built" notes in spec §6 and the feasibility doc §C.4 ("Hekili has no notion of confidence"). Hekili's `reset()` model (re-read everything each recalculation) tolerates belief jumps, but its across-reset caches do not.

Report path (not written, no write tool): `/home/zack/.claude/jobs/5926f0e9/tmp/reports/tdf-state-patterns.md`

---

# TDF state patterns inventory

All paths are under `/home/zack/src/TacoDogForever`. `src/TDF/` means `src/TacoDogForever/`. Spec means `docs/superpowers/specs/2026-10-12-taco-dog-forever-design-v2.md`.

## 1. Observation log and event sources

| Item | Evidence |
|---|---|
| Record | `{kind,t,a,b,c}`: `kind` is `Enum.Obs`, `t` is the time, `a` is an ability, aura or resource slot ID, `b` is the value, `c` is extra. `src/TDF/Model/ObsLog.lua:10-15` |
| Ring | Preallocated at `ObsLog.New(cap)`. `Add` allocates nothing, a full ring drops the oldest and counts `dropped`, and `At`/`Shift`/`Clear` read it. Records are reused, so read them, don't keep them. `ObsLog.lua:26-91` |
| Size and drain | `App.LOG_CAP=256`, `DRAIN=0.75` at `Game/App.lua:26`. An early `Belief.Update` runs at 75% fill (`App.lua:962`). The belief clears the log after reading it. |
| Time stamp | Every observation carries the frame's `GetTime()` (`Sources.lua:19`, staged at `:540`). `Belief.Update` clamps a late `o.t` to `s.now` and passes `lag` (`Belief.lua:720+`). The belief clock starts at the first heard observation. |
| Order | Aura reads go direct to the log. All other event observations go through `Sources.Stage` (cap `Sources.STAGE=128`, excess dropped and counted) and `Flush` at the next OnUpdate (`Sources.lua:531-570`). |
| Polls | `Sources.Poll(order, fn)` runs once per recalculation: resources (1), usability ladder (2), Queued (3), target death (4), nameplates (5), talents (6), pets (7), items (8), range (9). `Sources.lua:565-590` |
| Kinds | `Enum.Obs` has 34 kinds (`Engine/Enum.lua:69-109`). Main ones: Usable, CastStart/Success/Stop, Read (with `c`=`ReadOf`), Cooldown, PowerTick, TargetSwap, Combat*, Swing, Haste, Talent, Enemies, ChannelStart/Stop/Update, CastDelay, PackEvent, Pet, Totem, Gear, ItemCooldown, Range, TargetCast. |
| Event modules | `src/TDF/Sources/`: Sources (dispatch, `EVENTS` table at `:50`), Power, Auras, Casts, Target, Spellbook, Swing, Talents, Nameplates, Player, Group, Pets, Gear, Items. |
| Retention | The log is short-lived (drained every recalculation). Long-lived memory lives in the belief: `lastCast`, `prevGcd`/`prevOffGcd`/`prevAll` rings (`Model/Belief/History.lua`) and a per-target-slot aura memory (`TARGET_CAP=16`, `Belief.lua:81`). A reload record persists the belief (`Model/Belief/Persist.lua:1-25`: layout hash, max age, restore only while fighting). |
| `Game/*` | `Game/App.lua` owns the log, the belief and the frame loop. `Toggles`, `Options`, `Talents` and `Priority` are settings sources that reach the belief only at the idle point (`B.optToggle`, `talentDeclared`). |

## 2. State containers

| Module | Role | Exposure | Value shape |
|---|---|---|---|
| `Model/Belief.lua` (+ `Model/Belief/*.lua` families) | The hidden-input model. `B.beliefs[]`, `B.res[slot]`, `B.regen[slot]`, `B.aura[id]`, `B.swing[hand]`, `B.haste`, `B.health`. | Plain table fields. Families register appliers, readers, writers and listeners through `ns.BeliefShared` (`Belief.lua:98-160`). | `TacoDogBelief {input,id,est,lo,hi,anchorT,anchorKind,conf, speed?, anchorW?}` (`Belief.lua:190-209`). `Enum.Input` is Resource, AuraRemains, Haste, TargetHealth, Regen, Swing, CastRegen. |
| `B.s` (belief's own virtual state) | The believed state in absolute time. The engine moves it (regen, events). | Plain arrays. | `Enum.Bound` is Est/Lo/Hi (`Enum.lua:242`). |
| `TacoDogState` (`Engine/SpecBuilder.lua:32-145`) | The snapshot the APL sees. Clock 0 = now. | Flat arrays by ID. No methods, no metatables. | See field list below. |
| `Model/ViewModel.lua` | The display output: `TacoDogSlot{ability,kind,t,tLo,tHi,conf,why,idle,gates}` and `TacoDogTrack{est,lo,hi}`. | Plain tables, versioned. | `Enum.SlotKind` is Now/Committed/Fuzzy/Future (`Enum.lua:259`). `Enum.Wait` is Unsure/Resource/Window/Cooldown/None. |

State fields that matter, with the value convention each uses:

| Field | Convention |
|---|---|
| `s.res[slot]`, `resMax`, `resRegen`, `resLastTick` | Current value, max, per-second rate, relative last-tick time (`NEVER` if unknown). |
| `s.auraExp[id]`, `auraApplied`, `auraStacks` | Expiry as relative time; "down at t" means `auraExp &lt;= t`. |
| `s.cdReady[a]`, `charges`, `chargeNext`, `lastCast` | Relative ready time; `lastCast = NEVER` if never used. |
| `s.swingNext[hand]`, `swingSpeed` | Next swing; `math.huge` if the hand never swings. |
| `s.gcdEnd`, `castEnd`, `castAbility`, `haste`, `targetHealthPct`, `combatStart` | `combatStart = math.huge` while not fighting. |
| `s.usable[a]` | 0 means the game says no for a reason the model can't explain (the "unmodelled-block" flag). |
| `s.targetCastKick` | 1 yes, 0 no, -1 unknown. |
| `s.targetLevel`, `s.level` | 0 means unknown. |
| `s.targetCastEnd` | `math.huge` means a cast whose end is unknown. |
| `s.inRange[a]` | 1 for in range, unknown, or no check. |

Sentinels: `NEVER = -1e9` (`Engine/Helpers.lua:687`) and `math.huge` mean "never" or "no timer". `rel(x, now)` leaves both unchanged when converting belief-clock to snapshot time (`Belief.lua:~790`).

Standard shapes:
- **Interval:** `est, lo, hi`.
- **Confidence:** `conf` in 0..1.
- **Last anchor:** `anchorT`, `anchorKind` (an `Enum.Obs`).
- **Usability:** `UNKNOWN=-1, NOT=0, YES=1, SHORT=2` (`Belief.lua:~100`).
- **Source status strings:** "unread" / "readable" / "secret" / "none" / "no API", e.g. `maxStatus`, `regenStatus`, `sourceStatus`.

Confidence formulas:
- Resource: `1 - (hi-lo)/max`, halved while recently snapped (`Belief.lua:695-699`).
- Tracked target aura: `1/(1+age/AURA_HALF_LIFE)` with half-life 10 s (`:709`).
- Swing: linear to 0 over 10 s (`SWING_DECAY`).
- Constants: `PIN_GAP`, `ALPHA` 0.3, `REGEN_SPREAD` 0.1, `CD_PROBE` 0.5, `SNAP_HOLD` 1, `CAST_GRACE` 0.5, `FALSE_START` 1, `READ_HOLD` 2 (`Belief.lua:33-80`, `Model/Belief/Resources.lua:26`).

## 3. Secret handling

| Mechanism | Evidence |
|---|---|
| Gate | `Sources.Plain(api, v)` asks `api.issecretvalue(v)` first and returns nil if secret (`Sources/Sources.lua:42`). The api table is injected (`_G` in game, a fake in tests), so no Sources file names a WoW global. `tests/game/secrets_spec.lua` enforces the Plain rule statically. |
| Multi-return | Tests each return with `issecretvalue`, then reads through `Plain`. A secret in either return of `IsSpellUsable` means no news, because a secret `insufficientPower` read as plain "no" would be wrong (`Sources/Power.lua:62-95`). |
| Tables and errors | `pcall` wraps aura reads (`C_UnitAuras.*` raises when secret) and `issecretvalue(raw)` is tested before the table is touched (`Sources/Auras.lua:43,79`). Each field is then read via `Plain`. |
| Plain read vs secret read | A plain read logs a `Read` observation (`ReadOf` Resource/Aura/Max/Base/Regen/CastRegen/Rest/ItemCount) with the exact value in `b`. A secret read logs nothing, and the belief coasts on its model and the usability ladder. |
| Absent vs hidden | In combat a missing aura counts as "down" only after that aura has been seen readable in combat (`Sources/Auras.lua` doc comment, ~line 60). |
| Display-only pass-through | `Render.lua:1-15,336-345`. `TickGate` calls `UnitPowerPercent(unit, type, false, curve)` and feeds the secret result straight to `frame:SetAlpha(alpha)`. The curve is a step: 1 below the cost %, 0 at or above it. The call is `pcall`'d and falls back to alpha 1. `Render.SetSpellCooldown` hands the game's duration object to a Cooldown frame. Views never read these values. |
| Plain predicates | `C_Secrets.Should*BeSecret` is referenced only in the feasibility doc (§C.3) and a `Target.lua:29` comment. TDF decides per call with `issecretvalue`. |
| Status reporting | `/tdf selftest` (`Sources.SelftestLines`, `Sources.lua:~490`) prints each family's seen / plain / secret counts. |

## 4. Prediction and nowcast

**Flow.** `Belief.Update(B, log, now)` (`Belief.lua:720`) shifts each observation and calls `advance(B,t)`, which moves the belief's virtual state forward (regen, queued events, forecast ticks). It then calls the registered applier for that kind, pack `tracker.observe`, and finally `constrain` and `sync`. `Belief.Write(B, s, bound)` (`:830`) then writes the snapshot through ordered writer parts. After that come pack trackers' `write`, `generate` auras, and the final usability gate (`spec.requires`).

**Projection.**

| Quantity | How it is projected |
|---|---|
| Resource | Interval `[lo,hi]` moved by regen. Usability flips pin it to an ability's cost. A cost ladder (usable vs unusable abilities) bounds it. Regen is calibrated by an EMA between pins. |
| Aura expiry | Absolute expiry from our cast, with durations rank-corrected. A plain `Read` replaces it with `t + remaining`. |
| Cooldown | `cdReady` is set by the use step. A `Cooldown` observation snaps it (ready = now; not ready = no sooner than `CD_PROBE`). |
| GCD | `gcdEnd`, plus a `GcdFinish` event; haste comes from reads or GCD durations. |
| Swing | `anchorT + k*speed`, anchored by `PLAYER_SWING` with weights (1.0 / 0.9 / 0.8 / 0.5 / 0.3, spec §6). |
| Event queue | A time-sorted array in the state (`Timeline.CAP=8`, `Engine/Timeline.lua`): CastFinish, Impact, Callback, SwingSpend, ChannelTick/Finish, GcdFinish. |

**Query API: compiled code over the state arrays.**
- The APL compiler emits Lua for each root. For example `buff.x.remains` becomes `rem(s.auraExp[m], t)` with `flip = {kind="countdown", at=...}` (`Engine/APL/Roots/Auras.lua`).
- Each root declares a flip time (step, countdown, sawtooth, steps). `Runtime.Pick` retries a failed condition at those times (`Engine/APL/Runtime.lua:1-8`).
- `Engine/Helpers.lua` and `APLRuntime` export `stacks`, `refreshable`, `resAt`, `timeTo`, `chargesAt`, `nextSwing`, `find`, `petUp`, `procChance` and others (`Runtime.lua:13-80`). They are pure functions of `(s, id, t)`.

**Unknown into conditions.**
- There is no unknown value inside a condition. Uncertainty is handled around the engine: `Model.Simulate` writes the beliefs at `Bound.Est`, `Lo` and `Hi` and runs the whole APL from each (`Model/Run.lua:57-72`, spec §7.3 step 2).
- Agreeing picks give a certain action with a timing range. Disagreeing picks give `SlotKind.Fuzzy`, the highest-priority pick, lower `conf`, and "pooling target + hint".
- Unreadable but modelled values still use the same arrays. Target health is a declared default.
- `Model.BLIND_AFTER=1.5` switches to `ReducedApl` (slot 1 only) when usability answers stop reaching the belief (`ViewModel.lua:32,437`).
- Tracked values carry `class="T"` in the compiler; readable ones carry `class="R"`. Gates (`TacoDogGate`: input, id, op, value) record the hidden inputs a decision read.

## 5. Spec and research docs

Spec v2 sections (6,775 lines; the file has two `## 16` blocks, the change log at the end):

| § | Title | Defines |
|---|---|---|
| 3 | Constraints | Readable vs secret vs gateable lists (line 69) |
| 5.1 | State | Preallocated state, resources, forecast models (323) |
| 5.2 / 5.3 | Using an ability / Fields | Handler order, `known`, `rank`, `usable` (611, 770) |
| 6 | Belief and observations | Intervals, anchors, conf, drift, swing, haste, talents, enemies, casts and channels, regen window (1173) |
| 6.1 | Proc models | Proc state (2118) |
| 7.2.3 / 7.2.6 | Root list / Phase 2 roots | Query vocabulary and flip kinds (2540, 2712) |
| 7.3 | Evaluation per refresh | Est/Lo/Hi sensitivity (2785) |
| 8.1 | View model | Slot kind, `why`, gates (2810) |
| 10 / 10.1 | Robustness / snapshots | Fallbacks and trace (3171, 3183) |
| 17 / 17.1 / 17.2 | Contracts | Observation table; belief to state writer (3949, 4312, 4461) |
| 17.6, 17.7, 17.8 | Phase 3, 4, 5 contracts | Casts and channels; pets, gear, items; range and target casts (4644, 4668, 4695) |
| 18.3 | Sources (event map) | Which event feeds which kind, `/tdf selftest` lines (4777) |
| 18.8 | Display fallbacks | Gate and ReducedApl degradation (5139) |
| 20.3 | Per-target memory | Target slots (5280) |
| 15 | Open questions | Resolved and open state questions (3868) |

State gap IDs (ledger in `docs/research/2026-10-12-hekili-reconciliation/00-reconciliation.md`):

| IDs | Topic |
|---|---|
| G003 | Resource rest |
| G006 | Queued swing |
| G007 | Rank-correct durations |
| G008 | Combat time and false start |
| G009 | Cast history |
| G015, G016 | Aura, cooldown and charge fields |
| G020–G023 | Resource roots, max/base costs, regen window, model extensions |
| G025, G026 | Recheck candidates, timeline operations |
| G027, G028 | Swing timer, swing rage |
| G029 | Haste and GCD |
| G030, G031 | Movement, talents |
| G033–G035 | Enemy count, `spell_targets`, usability gate |
| G037 | Readiness waits |
| G038–G040 | Boss, player and target facts |
| G041 | Pack events |
| G042 | UI errors (open) |
| G045–G048 | Channels, pushback |
| G050–G053 | Pets, totems, gear, items |
| G055–G057 | Aliases, sim helper semantics, pack state tables and `generate` auras |
| G059 | Range (delta) |

Research docs in `docs/research/`:

| Doc | What it covers |
|---|---|
| `2026-10-14-hekili-virtual-state-feasibility.md` | §C.3 secret rules per call, §C.4 Hekili cache invariants, §C.6 belief-to-read mapping, §D calibration |
| `2026-10-14-virtual-combat-log-events.md` | Derived events with observed / inferred / modelled provenance (the closest analogue to a reusable event bus) |
| `2026-10-14-probe-session-O-results.md` | `UNIT_COMBAT` plain in combat; §21 consequences for the library design |
| `2026-10-13-probe-session-W-results.md` | PR1–PR19 measured readability |
| `2026-10-12-hekili-state-engine-matrix.md` | Engine feature matrix |
| `2026-10-12-parity-2-resources-auras.md`, `parity-3-prediction.md` | Hekili parity audits |
| `2026-10-13-probe-results-swing-usable.md` | Swing and usability probe results |

## 6. Lessons, as-built notes and pain points

- **Found in game (spec §6, line 1182):** a rage belief starting at max at login put Heroic Strike before Bloodrage. This led to the `rest`/`restRate` model and `CombatStart` staged on entering the world mid-fight. The related as-built note is at spec line 1184.
- **Found in game (spec line 5831):** an unlearned Mortal Strike was recommended, which led to the `Known` gate (G001).
- **As-built notes in spec §6:** lane 2A1 swing clocks (~1292), 2B talents (1508), 2C1 nameplates (1590), 2C2a haste and movement (1454), 2D usability (1549), 2C2b target facts (1889). Known limits sit at lines 1386 and 2076.
- **Open (spec §15):**
  - Frame order of aura reads vs casts (line 3905).
  - G042: the "must be behind" error ID is unknown, so `NOT_BEHIND_ERRORS` is empty (lines 3892-3894).
  - The opening swing at combat start is not pre-paid (3945).
  - The in-combat recalculation cost sits at ~1.0–1.2 ms against a 1.5 ms worst case (3941).
- **Feasibility doc §C.3:** `issecretvalue` cannot detect these cases:
  - Calls that error (use `pcall`).
  - Calls that return nil for "hidden".
  - Plain-but-wrong values: `GetSpecialization` returns 1491, `InCombatLockdown` is false inside `PLAYER_REGEN_DISABLED`, and a `UnitIsDead` poll misses the death edge.
  - A mixed plain/secret table (the `GetSpellCooldown` flags).
- **Feasibility doc §C.4:**
  - Hekili has no confidence concept, so unknown health becomes "full" (100000) and unknown TTD becomes 30 s.
  - Its GCD equality trick needs bit-identical numbers.
  - A correction to a past fact must reach Hekili's across-reset caches as a compensating event.
- **Design rules visible in code:**
  - Zero allocation in `Update`, `Write`, `Flush` and `Poll`.
  - One-way flow: Sources → log → belief → state → APL → view model.
  - Class specifics live in pack trackers, not core.

## Not checked

- I did not run the tests or the game.
- I did not read the `Roots/*` files other than `Auras`.
- The G-ID list is taken from the reconciliation ledger tables (some are marked "done" there), not verified against code.
- I did not verify that spec line numbers are still current after v2.33.

The full report content is written for the caller to save, since I could not.
