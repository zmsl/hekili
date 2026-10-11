# Taco Dog Forever: design spec

Date: 2026-10-11 · Status: draft for review · Research basis: [`docs/research/00-summary.md`](../../research/00-summary.md)

## 1. Summary

**Taco Dog Forever** ("…because we miss Hekili.", `/tdf`) is a new rotation-helper addon for **WoW Forever**
(client 1.60.1, Interface 16001, Midnight 12.1.5 API). It recommends what to press next, as a multi-step queue
modelled from an APL, like Hekili. Unlike Hekili, it works even though energy, per-target combo points, auras,
cooldown times and target health are **secret values** in combat.

The central idea is **secret-gated combination layers**. For each secret input, Lua defines a few ranges
whose edges come from the APL's own comparisons. Lua runs the full forward simulation once per combination
of ranges, using made-up values, and draws each result as its own layer. All layers are stacked in the
same spot. Each layer sits inside nested frames whose alpha the game sets from the real secret values,
through curves and duration objects. Exactly one layer is visible, and Lua never reads a secret.

First target: **Feral cat Druid**. Then other Forever classes, as their input coverage allows.

## 2. Decisions so far

| Decision | Choice |
|---|---|
| Product | A **new addon** built from Hekili's bones, not Hekili cleaned up in place |
| Name | **Taco Dog Forever**. Code prefix `TacoDog`, slash `/tdf`. No CurseForge collision found (TacoTip is the nearest). |
| Recommendation goal | A best-effort "press this next" queue. Occasional ordering errors in later slots are acceptable. |
| Default display | **Rhythm lane** |
| APL | Port Hekili's **SimC APL compiler** from the start, restricted by a **Forever validator** (§5.3) |
| Plugin API | **Internal-only in v1** (used by the built-in views and class packs). Frozen as public at 1.0. |
| Performance | **Zero new tables in steady-state recalculation; precompile everything possible** (§8) |
| Catnip reuse | Authorized by its author (Durts). Credit in file headers and the README. |
| Hekili code reuse | **Pending permission from Hekili's maintainers** (the upstream repo has no license). Build privately until then. |

## 3. Constraints

- **Secret values** (from research 01/02): in combat, energy, `GetComboPoints`, all Druid auras, DoT,
  buff and cooldown times, `UnitHealth`, haste, and enemy GUIDs are secret. The combat-log reader is gone.
- **Readable in combat:** cooldown `isActive`/`isOnGCD`, `IsSpellUsable` (to be confirmed), `GetSpellPowerCost`
  (Clearcasting trick), `UnitPower(player, ComboPoints)` (to be confirmed), `UnitPowerType`, own
  `UNIT_SPELLCAST_*` events, `PLAYER_SWING`, nameplates and `UnitCanAttack`, and `C_AssistedCombat` (exists).
- **Can be gated:** `UnitPowerPercent(unit, type, false, curve)` and `UnitHealthPercent(unit, pred, curve)`
  take a curve, and `LuaDurationObject:EvaluateRemainingDuration(curve)` does the same for time left.
  The results can feed frame alpha. AuraContainer buttons exist only while the aura is up.
- **AuraContainers can't be created in combat.** Their buttons can't be touched after setup.
- **Policy:** display only. No automation, no secure-action tricks, and readable, non-obfuscated code. Blizzard's
  stated intent is to remove combat advantage from addons, so a patch could break the gating. §9 defines how
  the addon degrades when that happens.

## 4. Architecture

### 4.1 Layers (dependencies go one way, downward only)

```
WoW API → Sources → Model → Engine (Sim + APL) → Planner → Render → Views
```

| Layer | Responsibility | WoW access |
|---|---|---|
| **Sources** | Read the game. Classify each input as **R**eadable, **T**racked or **G**ated. R and T produce numbers; G produces *gate descriptors*. | **The only game-state reader** |
| **Model** | The snapshot: readable values, tracked timers, and the range set for each gated input | None |
| **Engine** | `Sim` (time, resources, auras, cooldowns, handlers) and `APL` (parse → validate → compile) | **None** |
| **Planner** | Extract edges, choose combinations, run simulations, cache, produce per-layer queues | None |
| **Render** | Gate frames (secret alpha), the layer pool, and copying queues into layers | **The only frame code** |
| **Views** | The rhythm lane (default); queue, HUD and action-bar glow later | Via the Render API |

**Enforcement:** luacheck per-directory standards. `Engine/`, `Model/` and `Planner/` may reference no WoW
globals, and CI fails if they do.

**Secret safety:** secret values may flow only from Sources to `Render.Gate`. Engine, Planner and Views
never receive a secret.

### 4.2 Packages

- `TacoDogForever` is the core: all layers plus the lane and queue views.
- `TacoDogForever_<Class>` is loaded on demand: spec definitions, default APLs (compiled at build time) and
  generated spell data. v1 ships `TacoDogForever_Druid`.
- `TacoDogForever_Options` is loaded on demand: the options UI and APL editor.
- `tools/` is in the repo but not shipped: `wowdb` → spell-data code generation, APL compile and lint CLI, replay
  harness.
- Libraries are kept minimal and vendored: LibStub, CallbackHandler, AceDB, LibEditMode, and optionally
  Masque. Full AceConfig/AceGUI only in Options.

### 4.3 Data flow per update

1. Events (cast, combo-point change, target change, cooldown flag, `UNIT_POWER_FREQUENT`, aura events)
   mark inputs **dirty**.
2. One central driver runs at most once per frame. Sources refresh the readable and tracked values.
3. The Planner chooses the combinations to run: the ranges adjacent to the tracked estimate, nearest first.
   It runs them within a per-frame millisecond budget and reuses cached results.
4. Render copies the changed queue slots into the matching layer frames, diffing first.
5. Continuously and without Lua, the game sets gate alphas from the real secret values, so one layer shows.

## 5. Engine

### 5.1 Input model (Feral v1)

| Input | Class | Mechanism |
|---|---|---|
| Combo points | R* | `UnitPower(player, ComboPoints)`, reset on target change. Fallback: a cast-event counter. |
| Clearcasting | R | `GetSpellPowerCost(Shred)` cost == 0 |
| Cat Form | R | `UnitPowerType == Energy` |
| Ability affordable | R* | `C_Spell.IsSpellUsable` + `insufficientPower` |
| Cooldown ready, GCD | R | `GetSpellCooldown` flags; GCD from spell 29515 |
| Energy | G | `UnitPowerPercent` curve; T estimate from the tick model to narrow ranges |
| Rip, Rake, FF remaining | G (+T) | Duration curve or AuraContainer presence. T: a cast timer keyed by target GUID, used to narrow ranges. |
| Tiger's Fury buff | T (G if possible) | Cast timer; Cooldown Manager `IsShown()` if the user tracks it |
| Target health % | G | `UnitHealthPercent` curve (execute-style conditions only) |
| Enemy count | R* | Attackable nameplates |
| Time to die, fight remaining | X | Replaced by a user setting (boss/trash) |

`*` = must be confirmed by ForeverProbe.

### 5.2 Simulation

- **Flat state struct** per pool slot (pool size = maximum layers, e.g. 16), allocated at login.
- Auras and cooldowns are **parallel arrays indexed by compile-time integers** (`s.auraExp[RIP]`), and actions
  are integer IDs. There are no string keys in the hot path.
- Per-ability **generated handlers**: `cost(s)`, `readyTime(s)`, `apply(s)`.
- **Generated, unrolled** functions copy and reset state.
- A forward loop modelled on Hekili (pick → wait for resources → apply → advance by GCD), producing K = 3 slots
  per layer.
- Vanilla models adapted from Hekili's `classic` branch: the energy tick (20 per 2s), rank lookup by name, forms,
  and Clearcasting.

### 5.3 APL compiler and Forever validator

- **Parser:** a port of Hekili's `Scripts.lua` SimC grammar (priority list, `if=`, `variable`,
  `call/run_action_list`, `precombat`, `use_off_gcd`, `wait`, `pool_resource`, `use_item`, `potion`).
- **Validator:** each expression root is classified R/G/T/X by a registry, and expressions in category X are rejected
  with a clear message, e.g. "`time_to_die` is unavailable on Forever; use `settings.boss`". Rejected outright:
  `raid_event.*`, `fight_style`, `desired_targets`, `time_to_die`, `fight_remains`, `time_to_pct_*`,
  `pmultiplier`, `incoming_damage_*`, combat-log `.react`, and retail-only systems. `cycle_targets`/`target_if`
  are disabled in v1.
- **Edge extraction:** every comparison of a gated input against a constant contributes a range edge.
- **Output:** one Lua function per action list, a straight-line `if` chain over direct struct field reads, with
  constants folded and settings bound as upvalues, returning an action ID. No `setfenv`, no metatables.
  Default APLs compile at **build time** to committed generated Lua. User edits compile at runtime with
  `loadstring`.

## 6. Planner

- **Ranges** from the extracted edges. **Combinations** are the cross product of gated ranges, enumerated
  once at compile time.
- **Pruning:** tracked estimates select the current range ±1. The target is ≤ 12 runs per refresh.
- **Scheduling:** time-sliced jobs under a per-frame ms budget (`debugprofilestop`), nearest combination
  first.
- **Caching:** keyed by (generated readable-snapshot compare, range tuple). If only time passed, shift the
  queue timings instead of re-simulating.
- **Confidence:** a slot is "sure" when the simulations at the range minimum and maximum agree. Unsure slots fade.
- **Out of combat:** inputs are readable, so a single exact simulation runs and the gates are bypassed.

## 7. Render and views

- **Gates:** one gate frame per range of each gated input, with alpha driven by the secret value through curves
  and duration objects. Each combination's layer is nested under its gates, so the visible alpha multiplies
  down the chain. Built out of combat and pooled.
- **Layers:** a fixed pool. Each layer holds K icon slots, keybind text, explain text and a pooling countdown,
  and Render diffs before writing.
- **Rhythm lane (default):** upcoming actions slide toward a "now" line. DoT and cooldown markers come from
  game-driven timer bars (`StatusBar:SetTimerDuration`) and animation groups, so the game animates movement,
  not Lua.
- **Queue view:** a large primary icon plus 2 more, with confidence and explain text.
- **Explain overlay:** the APL line plus its conditions, rendered per layer as precompiled strings plus
  `SetFormattedText`.
- **Edit Mode** positioning via LibEditMode. Scale and theme options.
- HUD and action-bar glow views come after v1.

## 8. Performance requirements

- **Budget:** ≤ 0.3 ms per frame on average and ≤ 1.5 ms worst case in combat. ≤ 3 MB for the core.
- **Zero allocation in steady state:** no new tables, closures, `{...}`, string building or `C_Timer.After`
  in recurring paths. Pools are preallocated, `wipe` is reused, WoW globals are cached as upvalues, and loops use
  numeric `for`.
- **Precompile:** spell data and default APLs at build time. Handlers, copy and reset functions, edges, combinations
  and curves at spec load. Frames out of combat.
- **Verification:** a CI test runs 10,000 planner and simulation iterations and expects zero `collectgarbage("count")`
  growth after warm-up. `/tdf perf` shows ms and KB/s per subsystem and per plugin.
- **Game-side allocation:** curve and duration result objects are created by the game. Call them on events,
  not every frame, and prefer self-updating widgets. The rendering spike measures this.

## 9. Robustness and fallbacks

- `/tdf selftest` checks secrecy assumptions, API presence and gate behaviour at runtime, and reports clearly.
- **Fallback modes:**
  - If gating stops working: a **C_AssistedCombat lane** (Blizzard's suggestion in our display).
  - If affordability isn't readable: a reduced APL on R and T inputs only, with a visible notice.
- **Plugin isolation:** every callback is wrapped in `pcall` with a circuit breaker (error count and time or memory budget).
  The plugin is disabled and reported; the core keeps running.
- Versioned SavedVariables with migrations. No Lua error escapes in combat.

### 9.1 Drift and self-correction

**Gated inputs can't drift.** The game sets gate alpha from the true secret value, so only a layer matching
reality can be visible. **Tracked estimates can drift.** They are used to narrow which combinations to run,
and to feed any input that is only tracked.

Rules:
- Every secret input that drives an APL decision is **gated**. Tracking is only a narrowing hint, never the
  source of truth, unless an input can't be gated, in which case the validator flags it as T-only.
- The planner **sweeps every combination in the background**, with the near-estimate ones first. A mis-narrowed true
  layer is at most a few hundred ms stale, never empty.
- **Confidence decays** with time since the last confirming signal.

Correction signals (the timing of an event counts as information):

| Signal | Corrects |
|---|---|
| Own `UNIT_SPELLCAST_SUCCEEDED` | Start time of every self-timer |
| Combo points +1 after a builder (unchanged means a miss) | Rake applied or missed; Shred hits for any extension mechanic |
| Combo points → 0 after Rip | Rip new or refreshed (the timer restarts) |
| Combo points kept after a missed finisher (to verify) | Detects Rip misses |
| `UNIT_POWER_FREQUENT` firing (amount secret) | Exact energy tick phase |
| `IsSpellUsable` false → true | The exact moment energy crossed that ability's cost |
| Cooldown `isActive` flip | Cooldown end; start of the TF buff |
| `PLAYER_TARGET_CHANGED` | Swap or reset per-target timers and combo points |
| Leaving combat | Full exact re-sync plus calibration |
| Our child frame's `OnShow`/`OnHide` on an AuraContainer button (if allowed) | Exact "applied" and "fell off" events for Rip and Rake |

Remaining blind spots: refresh or extension without a combo-point signal, dispels and early removal (unless the
AuraContainer hook works), and per-GUID keying while enemy GUIDs are secret (timers are kept per target switch;
a returning target waits for its gate).

## 10. Plugin API (internal in v1)

```lua
TDF:RegisterPlugin({ kind = "view"|"spec"|"input"|"apl"|"integration",
  id = "lane", version = "1.0.0", api = 1, requires = {...}, provides = {...}, ... })
```

- **view:** receives `(layerFrame, queue)` with read-only integer arrays. It must not allocate or keep references.
- **spec:** fields and handlers declared *as data*. The core generates the fast code.
- **input:** declares R/G/T and edges. The gated kind may only pass values to `Render.Gate`.
- Planned plugins after v1: Catnip bridge, C_AssistedCombat oracle, community APL packs, Masque.

## 11. Quality

- LuaLS annotations on all public interfaces. `lua-language-server --check` (strict) is a CI gate.
- luacheck with per-directory standards. StyLua formatting.
- busted tests (TDD for all pure code):
  - APL golden tests (source → AST → compiled output)
  - validator table tests
  - simulation property tests (bounds, determinism)
  - planner tests (edges; exactly one combination matches any true state)
  - **replay tests** from probe and dummy logs
  - the zero-allocation test
  - luacov thresholds on Engine, Planner and APL
- CI (GitHub Actions): lint, format, LuaLS, tests, coverage, generated-data freshness, TOC validation, and the
  BigWigs packager with releases to CurseForge and Wago.
- ADRs in `docs/adr/`. Superpowers spec → plan → subagent-driven implementation, `/ponytail-review` before merges.

## 12. v1 scope (Feral)

**In v1:**
- the rhythm lane (default) and queue view, with confidence
- out-of-combat exact mode
- self-calibration (GCD, durations, costs, tick phase learned out of combat)
- generated spell data
- the explain overlay
- Edit Mode positioning
- `/tdf selftest` and `/tdf perf`
- the C_AssistedCombat fallback
- tests and CI

**After v1:**
- the HUD and action-bar views
- the in-game APL editor UI (the compiler and validator ship in v1)
- import/export
- `C_Traits` talent detection
- other classes
- the public plugin API
- a post-combat review

## 13. Prerequisites (before implementation)

1. **ForeverProbe run** (`~/src/ForeverProbe`): is `IsSpellUsable` readable in combat? Is
   `UnitPower(ComboPoints)`? Does `C_AssistedCombat` return anything? Does the combat-log event fire?
   Which `C_Secrets` checks report active?
2. **Rendering spike** (a throwaway addon):
   1. Do frames accept curve-result alpha from `UnitPowerPercent` and `EvaluateRemainingDuration`, and does
      nested alpha combine as an AND?
   2. Can we get Rip's duration object (`GetAuraDuration` needs an `auraInstanceID`)? If not, can our frames be
      children of AuraContainer buttons?
   3. Can a curve be 1 inside a range and 0 outside it?
   4. Does `StatusBar:SetTimerDuration` accept a secret aura or cooldown duration from addon code?
   5. How much do curve evaluations allocate per call?
   6. How long does one simulation run take for Feral?
   7. Does our child frame on an AuraContainer button receive `OnShow`/`OnHide`, or are those blocked?
   8. Does `UNIT_POWER_FREQUENT` fire on energy ticks in combat, with usable timing?
   9. Do combo points survive a missed or dodged finisher on Forever?
   10. Can unit tokens be compared (`C_Secrets.CanCompareUnitTokens`, `UnitIsUnit`) to recognise a returning target?
3. **Permission:** ask Hekili's maintainers about reusing the code with credit. Ask Catnip's author to add the
   MIT LICENSE file that CurseForge already shows.

If question 2.1 fails, the design falls back to §9: the C_AssistedCombat lane plus a reduced APL.

## 14. Open questions

- The spec ID Forever reports (Hekili keyed specs on retail IDs).
- Forever's real Feral durations and costs, and its new spells (Primal Bite, Shifting Power, the 21s Rip variant
  1289141). Resolve with `wowdb` and in-game calibration.
- The repository: a new GitHub repo `zmsl/TacoDogForever` (to be created with the user's OK).
