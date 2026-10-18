# Codebase audit: performance, structure, repo health (2026-10-17)

Status (2026-10-18): items 1-9, 11, 17, 18, 20 landed in the first wave (plan docs/superpowers/plans/2026-10-17-audit-first-wave.md); counts below are the pre-wave snapshot.

Three read-only investigations on `forever` 0489efb7, the first commit after the restructure and the engine seams.
Each item has the value it buys, what it costs, and a recommendation. The three source reports follow as appendices
with their evidence and measurements; the scratch specs that produced the performance numbers are under
`~/.claude/jobs/080a308e/tmp/audit-perf/`.

## Headline numbers

| Measure | Value |
|---|---|
| One `Hekili.Update()` headless (Arms, one display) | 2.6 ms mean, 4.4 ms p95, 13 ms max |
| Allocation per Update, as the Driver runs it | 9.4 KB (0.7 KB when run directly: the coroutine costs the rest) |
| Allocation per incoming hit (UNIT_COMBAT) | 411 B, all from three closures and three timers in upstream's damage store |
| Time share per Update | upstream Sim + Schema 81%, the belief 13%, content 2% |
| Frame hitch | the budget is 11.7 ms at 60 fps, Update never yields, so one frame in twelve carries the whole 2.6-4.4 ms |
| `make check` wall time | 196 s, of which 160 s is six simulated-fight gate files run serially on a 16-core machine |
| Repo | no CI; 44 worktrees and 43 merged branches unpruned; packaging still describes upstream's single addon |

## Ranked opportunities

Value is what a player or a developer gets. Cost is wall-clock for one implementer plus review. "Upstream" marks an
edit inside upstream Hekili files, which costs merge friction later.

| # | Opportunity | Value | Cost | Recommendation |
|---|---|---|---|---|
| 1 | **Parallel test gates** (busted one file per process; `make -j check`; split the 6-fight gate in two) | `make check` from 3 min to about 1 min, same coverage; every task and review round gets faster | 1 h, tests only | Do now |
| 2 | **Reuse one engine coroutine** instead of `coroutine.create` per refresh (`Engine/Driver.lua`) | removes 8.7 KB per Update, about 43 KB/s in combat, the addon's largest allocation and a GC-pause source | 1-2 h + a spec, fork file | Do now |
| 3 | **Minimal CI** (GitHub workflow: bootstrap cached, `make check` minus typecheck) | nothing merges off a red base; catches a push that skipped the check | 45 min + 6-8 min per run | Do now |
| 4 | **Prune merged branches and worktrees** (commands in appendix C of the health report, dry-run first) | 44 worktrees and 106 refs down to a handful; faster git and IDE pickers | 10 min | Do now |
| 5 | **Memoize `IsKnown`/`IsDisabled` per prediction** and answer `query_time` first in `mt_state` | measured -12% per Update (2.6 to 2.28 ms), first icons identical over 4,614 Updates | 1-2 h, ~11 upstream lines | Do, with the test-druid gate |
| 6 | **Ring buffer for incoming damage/healing** (`Targets.lua` storeDamage/storeHealing) | removes 410 B and three timers per hit taken; matters most for Protection | 1-2 h + a spec, upstream | Do |
| 7 | **Pool the popped APL stack entries** (`Core.lua` PopStack, one line) | removes 667 B per Update, 98% of the direct allocation | 10 min, upstream one line | Do now |
| 8 | **Gate the per-entry yield/status strings on debug**; drop the `eventsTriggered` write; cache a false tooltip answer | 1% per Update, 124 fewer transient strings, a slow leak closed | 30 min total | Do now |
| 9 | **Fix the upstream `alphaCheck` global read** (`UI.lua:1183`: `if alphaCheck then` tests a global that never exists, so the per-frame alpha check has never run; the status subscriber covers combat visibility today) | correctness; removes a lint exemption | 15 min, upstream one line | Do, verify combat-only displays in game |
| 10 | **Fix packaging for CurseForge "Hekili Forever"** (`.pkgmeta` move-folders for the four addons under `src/`, ignore list, `@project-version@`, project ID, tag-triggered packager) | the project becomes shippable; today the packager would ship nothing | 2-3 h | Soon, after CI |
| 11 | **Fork identity** (add an `upstream` remote, default branch `forever`, replace FUNDING.yml and the issue-template links that point at upstream) | issues and funding stop routing to the wrong project | 15 min | Do now |
| 12 | **README and LICENSE** (the README is upstream's retail README under a "Goodbye" banner; no root LICENSE) | first impression and legal clarity before publishing; check upstream's licence first | 30-45 min | Soon |
| 13 | **One class-file loader** for tests (`load_warrior.lua` + `load_druid.lua` share 130 of 195 lines; `rank`/`idsOf`/`near` repeated in four specs) | about 150 lines gone; the third class pack gets its loader for free | 1-2 h, tests only | Do before the next class |
| 14 | **Shared class-file helpers** (`rest`/`knows`/`knownRank`, the swing-rage entry, the decay line duplicated in Warrior.lua and Druid.lua) into `Hekili_Shared/Shared/Ranks.lua` | about 45 lines; a third pack copies nothing | 1 h, content | Do before the next class |
| 15 | **Split `Families/Resources.lua`** (954 lines, seven responsibilities) into resources, regen/decay and the usability oracle; split its 1,304-line spec along its describes | the belief's most-edited file becomes three readable ones | 3-4 h, semi-mechanical | When next touched |
| 16 | **Lifecycle out of `Core.lua`** (OnInitialize/OnEnable composition into a fork `Boot.lua`; launchers into `UI/Launchers.lua`) | the engine stops composing the app; UI.lua's upstream diff shrinks by 85 lines | 1 h | At the next upstream merge |
| 17 | **Threat table out of `Spec.lua`** into `Engine/Schema/Threat.lua` | the largest fork block leaves an upstream-derived file | 30 min | Do |
| 18 | **`packs-check` target** (run `make packs`, fail on diff) and a documented one-spec command and `.lua/` sharing note | an edited `.simc` that was not regenerated cannot slip through; new worktrees stop re-bootstrapping | 30 min | Soon |
| 19 | **Docs index** (15 plans, 11 specs, 17 research docs with no status column) | a returning reader finds what is done | 40 min | Soon |
| 20 | **Dead code** (eleven fork names written and never read; `IsDragonflight`/`IsTWW`/`IsMidnight` in Hekili.lua) | small; keeps the grep-based checks honest | 30 min | Do with item 8 |
| 21 | **Tighten LuaLS** (`undefined-global` and nine other diagnostics are disabled; busted globals unknown) | typecheck becomes a real net instead of decoration | 1 h + triage | Later |
| 22 | **Nameplate range poll** (one `IsSpellInRange` per startsCombat ability per plate, linear in plates: ~10% of Update at ten plates) | matters in AoE pulls only | measure in game first | Defer |
| 23 | **Frame budget default** (0.7 × frame time) | the hitch a player sees is one frame carrying the whole Update | measure in game after 2, 5, 7 | Defer |

Not recommended: deduplicating the 53 `now` handlers that repeat their sim `handler` (Lua 5.1 cannot share a closure
across two environments; the only fix is a declarative shorthand that makes content less Hekili-shaped); pre-checking
the ability-metatable misses (a wrapper made Update slower; only caller-side `rawget` across most of upstream helps);
merging the five headless boot paths (they are deliberate fidelity levels; only the two class loaders should merge).

## Suggested order

Items 1, 2, 3, 4, 7, 8, 11 are a day's work and pay back on every later task: faster gates, a green base enforced,
the two biggest allocations gone. Then 5 and 6 as one measured performance task with the gate line byte-identical,
then 9, 10, 12 for publishing, then the structure items (13-17) as their files come up.

## Things examined and found fine

Output publish/subscribe allocates nothing inside real Updates; the belief's Drain and flush are 0 B in steady state;
the UI's idle frame, pulse and redraw allocate nothing; the Rows pairing is O(8) per outcome with no O(n²) over
attackers; the facade wrapper costs 0.6% of Update; the embedded libraries are pinned and credited; history has no
large blobs; 693 tests pass with no pending or skipped; the credit headers are present on the ported files; the
current layout and architecture docs match the tree.


---

# Appendix A: per-frame performance report


All numbers are headless PUC Lua 5.1 on WSL. Level 60 Arms Warrior from `warrior_world.lua`, driving alone (no
oracle), pressing its own first icon at 5 Hz, only Primary subscribed (one display per Update; each extra visible
display adds one `state.reset` and one APL pass). Scratch specs in `~/.claude/jobs/080a308e/tmp/audit-perf/`, run from
the worktree root with `.lua/bin/busted <spec>`.

## A. Measured baseline

| Quantity | Value | How measured |
|---|---|---|
| ms per Update | mean 2.84, p50 2.63, p95 4.43, p99 4.71, max 13.27 (n = 15,558, 20 fights) | perf_spec MODE=time, os.clock around Hekili.Update |
| ms per Update, quieter rerun | mean 2.59, p95 3.21 (n = 4,614, 6 fights) | patch_spec PATCH=none, twice (2.597 / 2.594) |
| APL entries per Update | mean 62.4, p50 63, p95 72, max 72 | count of IsActionActive calls |
| Lists entered per Update | mean 9.2, p95 12 | count of GetPredictionFromAPL |
| CheckScript calls per Update | mean 63.9, p95 78 | wrapper count |
| state.reset / state.advance per Update | 1.00 / 1.92 | wrapper count |
| Function calls per Update | 24,545, of which 1,590 in Game/ | calls_spec call hook |
| Bytes per Update, run directly | mean 642, p95 1,188, max 34 KB | perf_spec MODE=alloc, GC stopped |
| Bytes per Update, run as the Driver runs it | 9,377 (direct: 679) | coup_spec: alternate Updates in a fresh coroutine |
| Where the direct 679 B come from | 667 B in Hekili:AddToStack (3.3 calls of 202 B) | incl_spec |
| VS.Drain | 170 µs mean (6%), p95 271, 0 B steady | alloc_spec MODE=events |
| state.reset | 173 µs (6%), 2.4 B | same |
| GetNumTargets(true) | 11.8 µs, 0.2 B | same |
| VirtualState per-frame flush | 9.7 µs, 23 B mean | same |
| Time share | Engine/Sim + Schema 81%; Game/ 12.6% (Drain 6%, belief reads 6.6%); fake client 1.4%; content 1.9% | tprof_spec count hook, hook time excluded |
| Driver idle frame | 7.6 µs, 0 B | idle_spec |
| Display idle frame / pulse (0.25 s) / redraw | 8.7 µs / 107 µs / 127 µs, 0 B | idle_spec (stub widgets inflate these; compare only with each other) |

Belief cost per event (GC stopped; the harness's own dispatch costs 40.5 µs per event, subtracted in "net"):

| Event | n | µs mean / p95 / max | B per event | net µs |
|---|---|---|---|---|
| UNIT_COMBAT | 5,606 | 83.6 / 155 / 305 | 410.6 | 43 |
| SPELL_UPDATE_COOLDOWN | 3,688 | 80.5 / 137 / 274 | 0.2 | 40 |
| SPELL_UPDATE_USABLE | 1,325 | 76.5 / 125 / 269 | 1.3 | 36 |
| UNIT_SPELLCAST_SUCCEEDED | 1,184 | 84.6 / 173 / 305 | 27.2 | 44 |
| PLAYER_SWING | 851 | 96.3 / 146 / 415 | 1.8 | 56 |
| UNIT_AURA | 314 | 92.0 / 158 / 201 | 13.8 | 52 |
| UPDATE_SHAPESHIFT_FORM | 40 | 120.6 / 194 / 287 | 37.5 | 80 |
| PLAYER_REGEN_ENABLED | 5 | 286 / 392 / 392 | 908 | 246 |

Idle-frame census: in combat two frames besides the VirtualState flush have a per-frame OnUpdate, HekiliEngine and one
HekiliDisplay per visible display. Driver per idle frame: adds elapsed to the refresh timer, reads settings.enabled
and Pause, one coroutine.status. Display per idle frame: one Published lookup, one debugprofilestop, two timer
decrements, the alphaCheck global read and the pause test. No table created or wiped on either path. eventsTriggered
is never wiped (the wipe is in commented-out code at UI.lua 2046-2129).

## B. Opportunities, ranked

1. **Reuse one coroutine (do).** Driver.lua OnUpdate calls coroutine.create(Hekili.Update) on every refresh: 9,377 B
   per Update vs 679 B direct, about 43 KB/s at 5 Hz, the largest allocation in the addon (make test-loop cannot see
   it because headless.cycle calls Update directly). Fix: one thread `while true do Hekili.Update(); yield(DONE) end`,
   treat DONE where the code tests "dead", recreate after an error or when Snapshot.lua:32 drops it. Gain: 8.7 KB per
   Update. 1-2 h plus a spec driving Updates through the frame asserting 0 B. No recommendation risk; fork file.
2. **Memoize IsKnown / IsDisabled per prediction (do).** State.lua 6730 and 6827; the cooldown metatable (2928,
   3043-3083) calls both on every remains/charges read (189 per Update): 150 IsKnown + 141 IsDisabled calls, about
   1,500 of the 3,525 ability-metatable misses (State.lua:3071-3072), 438 knownRank belief reads (3.2%). Measured as a
   wrapper cache wiped at ResetSpellCaches: 2.595 → 2.36 ms (-9%), first icons identical over 4,614 Updates. Fix:
   revive Core.lua's knownCache/disabledCache and route the cooldown reads through them. 1-2 h. Risk: an ability
   whose known reads time-varying sim state stays frozen for one prediction (upstream's own cache lifetime); run
   test-druid. Medium friction (about 10 upstream lines).
3. **Ring buffer for incoming damage and healing (do).** Targets.lua storeDamage (966) and storeHealing (1019): each
   hit creates 3 closures and 3 C_Timer.After timers, the whole of UNIT_COMBAT's 410.6 B. Fix: a fixed ring summed on
   read in damageInLast. 1-2 h plus a spec pinning the 1/5/10 s sums. Risk: Protection and defensive lists read the
   sums. Medium friction. Follow-up: switch to fixed 100 ms time buckets when the first tank pack reads incoming_*; the
   hit ring undercounts above 12.8 hits/s per kind.
4. **Return popped stack entries to the pool (do).** Core.lua PopStack drops non-run entries so AddToStack's pool
   stays empty: 667 B per Update, 98% of direct allocation. One line (tinsert(StackPool, x) on the non-run branch).
5. **Answer query_time first in mt_state (do, with 2).** State.lua mt_state.__index (1795): 1,362 misses per Update,
   902 of them query_time about 20 branches down; the metamethod is 14.6% of time. Measured -2.5% alone, stacked
   on 2: 2.36 → 2.28 ms. One moved line.
6. **Gate the yield and status strings on debug (do).** The per-entry Yield("GetPrediction... " .. dispName ..),
   the per-display "Recommendations finished" string and ThreadStatus are ungated: 30 µs per Update (1%) and about
   124 transient strings. Build only under ActiveDebug; keep scriptID (a cache key). 15 min.
7. **Range poll across nameplates (defer).** Sources/Nameplates.lua poll 8 in every Drain: IsSpellInRange per
   startsCombat ability per active plate; 1% with one plate, linear in plates (about 10% at 10). Measure an in-game
   pull with 8+ plates, then poll one spell per range.
8. **Drop the eventsTriggered write (do).** ForceUpdate writes it, nothing reads it; UI.lua:1746 builds a
   "DISPLAY_ALPHA_CHANGED:...:" .. GetTime() key on every fade-in (a slow leak). 10 min.
9. **Cache a nil tooltip answer (hygiene, with 2).** Utils.lua IsSpellDisabled caches nil so a nil tooltip answer is
   asked again every call (141 per Update headless; free in game since Forever answers tooltips). Store false. 5 min.
10. **Frame budget (defer, a setting).** Budget is 0.7 × frame time (11.7 ms at 60 fps); Update is 2.6-4.4 ms so it
    never yields and one frame in 12 carries the whole Update, which is the hitch a player sees. Measure in game after
    1-5 before choosing a default.
11. **Remaining ability-metatable misses (don't, for now).** Spec.lua:722: 15% of time, 3,525 calls per Update (item
    alone 976); the cost is dispatch, not the body (a pre-check wrapper made Update slower, 2.59 → 3.90 ms). Only
    caller-side rawget fixes it and that diff crosses most of upstream Core/State. After 2, rerun keys2_spec and take
    only callers still above 200 per Update.

Together 1-6 cut Update by about 12% (2.6 → 2.28 ms measured as wrappers; inline does better), per-Update allocation
from 9.4 KB to 0, per incoming hit from 410 B to 0.

## C. Looked at and fine

Engine: Output.Begin/Publish 0 B inside real Updates; the status record is 5 comparisons per Update;
UpdatePerformance once per finished thread; ns.callHook returns at once when nothing is registered, else reuses vars
(226 calls per Update); GetNumTargets 11.8 µs; StoreValues/GetConditionsAndValues/ImplantDebugData snapshot-only;
Timer:Reset/Track 457 no-op calls under 1%; ns.Mark 374 per Update allocates only on first use; the facade wrapper
0.6%; APL work stable (62 entries, 1 reset, 2 advances); the 13 ms max is a single Update.
Belief and events: Rows scoring O(8) per outcome, 0 B; Attackers on UNIT_COMBAT at most 861 comparisons, no O(n²);
UNIT_AURA walk and SPELL_UPDATE_COOLDOWN linear, 0-14 B; EventFacade.onEvent 8 Plain calls and one pcall per
subscriber, 0 B; Drain and flush 0 B steady (the 131 KB maxima are first-observation table growth).
UI: display OnUpdate 0 B in idle, pulse and redraw; RefreshCooldowns only on redraw; the pulse under 0.5 ms/s per
display. `alphaCheck` at UI.lua:1183 reads an unset global, so UpdateAlpha never runs from OnUpdate: a behaviour slip,
not a cost (see the combined report).

Not checked: in-game timings, more than one visible display, Druid content, GC pauses under the client's collector.
The 2 and 5 gains are from runtime wrappers, not edits in the tree. These are headless costs; check the ms figures in
game before relying on them.


---

# Appendix B: single responsibility and duplication report


## A. The ten largest files

| # | Path | Lines | Owner | Responsibilities |
|---|------|------:|-------|------------------|
| 1 | src/Hekili/Options/Options.lua | 9602 | upstream (154 fork lines) | 8+ |
| 2 | src/Hekili/Engine/Sim/State.lua | 7329 | upstream | 6+ |
| 3 | src/Hekili/UI/UI.lua | 3026 | upstream (235 fork lines) | 6 (displays, buttons, menu, launchers, config mode, tooltips) |
| 4 | src/Hekili/Engine/Sim/Events.lua | 2525 | upstream | 4 |
| 5 | src/Hekili/Engine/Schema/Spec.lua | 2246 | from upstream Classes.lua (85 fork lines) | 4 (Register API, `all` keys, SpecializationChanged, threat table) |
| 6 | src/Hekili/Engine/Sim/Scripts.lua | 2186 | upstream | 2 |
| 7 | src/Hekili/Engine/Sim/Core.lua | 2098 | upstream (69 fork lines) | 4 (lifecycle, APL runner, recommendation loop, debug dumps) |
| 8 | src/Hekili_Warrior/Warrior.lua | 1930 | fork | 6 |
| 9 | src/Hekili_Druid/Druid.lua | 1900 | fork | 6 |
| 10 | src/Hekili/Engine/Sim/Targets.lua | 1582 | upstream | 4 |

Largest fork-only files after these: resources_spec.lua 1304, harness/headless.lua 1012, druid_spec.lua 985,
Families/Resources.lua 954, Game/API/Facade.lua 883, warrior_spec.lua 839.

Largest functions in fork code: headless.lua:255 `M.new` 727 lines; fake_api.lua:30 `M.new` 534; observer.lua:111
`M.new` 406; Snapshot.lua:38 `SaveDebugSnapshot` 402 (moved upstream code); world.lua:20 `M.new` 380; engine.lua:132
`M.load` 212; loop.lua:85 `M.run` 202; Adapter.lua:172 `buildDef` 115. No other function in src/Hekili/Game exceeds 41
lines.

## B. Ranked opportunities

1. **Parallel test runs.** Do; mechanical, 1 h, no upstream code. Seconds per file: loop_warrior_spec 46.8 (the 6-fight
   Arms gate alone 45.1), group_spec 29.2, solo_spec 26.0, sweep_spec 21.2, druid_harness_spec 20.2, onus_spec 9.6; the
   other 680 tests take about 9 s together. A headless boot costs 0.1 s; the time is simulated fights (two engines at
   5 Hz for up to 3 minutes). Run `busted <file>` per spec through `xargs -P` or a make pattern rule and `make -j check`;
   optionally split the 6-fight gate into two 3-fight files (wall time about 25 s); split `test-druid` per scenario the
   same way. Risk: interleaved output; run twice to confirm no ordering dependence.
2. **One class-file loader.** Do; tests only. load_warrior.lua and load_druid.lua are 195 lines each with about 130
   shared; they differ only in the file path (load_druid:82, load_warrior:100) and the `game`/`w.state` defaults
   (load_warrior:26-37). Repeated fixtures: `rank`/`idsOf` (warrior_spec:117-131, druid_spec:222-236); `near`
   (druid_spec:238, warrior_spec:373, casts_spec:189, fixtures_spec:65). Proposal: `load_class.lua` with
   `M.load(path, gameDefaults, stateDefaults, vs)` exporting the fixtures. Saves about 150 lines.
3. **Split Families/Resources.lua** (954 lines, 7 responsibilities: slots and maxima :23-161; swing pay :268-296,
   :541-557, :715-756; aura regen and decay :297-367, :832-856; calibration, pins and the cost ladder :442-540; the
   oracle's predict/judge :558-714; rage taken :771-831; accessors :874-954) into Resources.lua, ResourceRegen.lua and
   ResourceOracle.lua with the per-slot arrays on a shared `I.Res` table; resources_spec (1304) splits along its
   existing describes (:31, :132, :353, :501, :629, :746, :920, :1097). Semi-mechanical, 3-4 h; do it when the file is
   next touched. Risk: an upvalue becoming a table field on a hot path; the alloc specs guard it.
4. **Shared class-file helpers.** Do before a third pack; 1 h. Duplicates: `rest`/`knownRank`/`knows` (Warrior.lua:68-94,
   Druid.lua:118-134); the swing rage entry `last`/`interval`/`stop` (Warrior.lua:183-198, off-hand twin :245-252,
   Druid.lua:158-170); the decay line `app + floor(...)` (Warrior.lua:294, Druid.lua:188). Proposal:
   Hekili_Shared/Shared/Ranks.lua with `Hekili.Ranks.*` and a `SwingEntry` builder. Saves about 45 lines. Risk: the
   helpers run in the file's environment, not `state` (Warrior.lua:76-79); the shared version must read `Hekili.State`
   the same way.
5. **Lifecycle out of Core.lua.** Defer to the next upstream merge. Core.lua:64-116 is app composition (content, profile,
   launchers, chat commands). Proposal: a fork `Boot.lua` loaded last plus `UI/Launchers.lua` for UI.lua:831-916. 1 h;
   costs one delete/modify conflict in an upstream file; UI.lua's diff against upstream shrinks by 85 lines.
6. **Split the giant test constructors.** Defer to the next client-stub addition. headless.lua `M.new` mixes Lua shims,
   frame stubs, C_Timer, constants, the miss counter and the TOC/XML loader; proposal headless/{env, frames, timers,
   globals, loader}.lua each with `install(env, H)`; fake_api, observer and world have the same shape. 2-3 h per file.
7. **Facade.lua.** Optional, at the next probe sweep. Trace (:50-163), policies (:229-724), PASSTHROUGH table (:730-874)
   → Facade/Trace.lua and Facade/Passthrough.lua. 1 h.
8. **Rows.lua.** Defer to the G7 oracle tuning; 3-4 h, medium risk. It does pairing and scoring, the background-rate
   model and the record half of the usability oracle (:58-88, :345-360, :479-555); the judging half is in
   Resources.lua:558-714. One Oracle.lua should hold both halves.
9. **Threat table out of Spec.lua.** Do; 30 min. The largest fork block in this upstream-derived file (about 25 lines) →
   Engine/Schema/Threat.lua registered on `all`.
10. **`now` handlers that repeat their `handler`.** Don't. 53 of 76 are identical (Warrior 21/30, Druid 20/34, races
    12/12, about 170 lines, 47 one-liners). Now.lua:251-256 deliberately rejects sharing the function (setfenv would
    move the sim handler into the belief context) and Lua 5.1 cannot clone a closure; the only fix is a declarative
    Schema shorthand, which makes content less Hekili-shaped.
11. **One mechanism for the boundary checks.** Defer. check_engine_reads.sh could become a boundary_spec case on
    boundary_lib; list_api_reads.sh repeats check_api_reads.sh's listing and luacheck call (:9-14) and could be
    `--list`. Saves about 20 lines.
12. **Repeated VirtualState spec setup.** Defer. About 20 specs repeat the same 4-6 setup lines (`load.module()`,
    `I.Build(fs.def(fs.new(n)), t)`, `I.api = fake.new()`; e.g. swing_spec:11-17, target_health_spec:35-43). A
    `load.boot()` helper saves about 80 lines.

**Boot paths.** Five ways to boot headless: (1) State/helpers/load.lua `module()`; (2) the same plus `load.adapter`;
(3) Forever/helpers/engine.lua, the real Schema and content against strict stubs; (4) load_warrior/load_druid, a class
file against a recording spec; (5) harness/headless.lua, the full TOCs in two isolated instances. druid_vs.lua combines
4 and 1. These are deliberate fidelity levels (engine.lua's raise-on-unknown-name check would be lost under headless's
real State.lua), so no single loader can serve all; only the two copies in path 4 should merge. The two class worlds
use different harness paths: Warrior through loop.lua and headless, Druid through drive.lua and VirtualState only.

## C. Dead code

Method: every function defined in src (Libs excluded) whose name appears only at its definition across src, tests and
tools, strings counted (dead.sh); fields.sh does the same for non-function fields.

Fork code, safe to delete: Registry.lua:25 `Registry.SetBonus`; VirtualState.lua:84-85 `I.FALSE_START`, `I.READ_HOLD`
(written, never read); Rows.lua:47 `L.MED0`, `L.SPR0` (never read; the literals repeat at :48); exports never read
outside their file: Belief.lua:47 `I.Advance`, Resources.lua:539 `I.Ladder`, Spellbook.lua:46 `I.ResolveSpells`,
Casts.lua:49 `I.GCD_EDGE`; Options/Profile.lua:45 calls `ns.checkImports()`, which is empty (Core.lua:37);
list_api_reads.sh:15 filters expansion folders that no longer exist.

Upstream file, delete anyway (the fork already rewrote these lines): Hekili.lua:41-51 `IsDragonflight`, `IsTWW`,
`IsMidnight` (return true, nothing calls them).

Upstream, unreachable on Forever but leave (merge friction): the `IsWrath()` branches (Events.lua:362, :523, :2327;
Flavor defaults to "Retail", no TOC sets X-Flavor); UI.lua:812 `IsClassic()`; Core.lua:42 `EmbedBlizOptions` (call
commented at :68); two Empower references in State.lua; pet-based target detection (23 references, a user option);
about 80 upstream debug/API helpers (State.lua:5595-5615, Targets.lua:696-921 and :1241-1503, Utils.lua:130-163,
Options.lua:3569-3838, Spec.lua:1750-1854), some of which are `/run` entry points so a count of 1 does not prove death.

## D. Examined and found fine

VirtualState.lua (244 lines) and the Families other than Resources (none over 460 lines, functions at most 41 lines);
the Events files other than Rows; the Engine fork files (Snapshot.lua's 402-line function and Driver.lua's 81-line
`UpdatePerformance` are re-homed upstream code); make_pack.lua (276 lines, functions at most 42); the race packs; the
harness has no class, spell or form names (it defaults its swing resource to rage: drive.lua:24, observer.lua:32,
behaviours.lua:48, acceptable); belief logic in content is only Warrior.lua:157-161 (an EMA of unblocked hits for
Shield Block, Warrior-specific); `ns.StartConfiguration` (UI.lua:153, 200 lines) and the `ns.UI.Menu` dropdown are
options code in UI but upstream's placement; Spec.lua's 85 fork lines (passive abilities, the cost-mod wrap,
`Engine.settings` reads, the pseudo-spec identity, the threat table, the SpecializationChanged hooks): only the threat
table is worth moving.

Not checked: why one simulated Arms fight takes about 7.5 s (most likely upstream's per-tick State reset);
`make test-druid` was not run (about 200 s per layout.md); Options.lua's 154 fork lines were only skimmed.


---

# Appendix C: repository health report


Read-only. Logs in this directory (lint.log, test.log, times.txt). Worktree: /home/zack/src/hekili/.claude/worktrees/forever-audit.

## (A) Scorecard

| Area | Status | Reason |
|---|---|---|
| make check | green | All six targets pass; 196 s wall (181 s is `test`); no check passes on an empty list |
| typecheck (LuaLS) | yellow | Passes in 4 s but `undefined-global` and 9 other diagnostics are disabled; weak safety net |
| Toolchain reproducibility | yellow | Versions pinned (mise.toml, bootstrap.sh); copying `.lua/` between worktrees is undocumented |
| CI | red | `.github/` has only FUNDING.yml and ISSUE_TEMPLATE; no workflows, nothing runs `make check` off this machine |
| Branch and worktree hygiene | red | 106 refs (46 local, 60 origin), 44 worktrees, 43 merged local branches never pruned |
| Fork identity (remote/default) | yellow | No `upstream` remote; origin default is `classic`, not `forever`; FUNDING/issue links still point at upstream Hekili |
| Large files in history | green | Largest blob 589 KB (old Options.lua); no binaries or dumps |
| Tree hygiene | yellow | `archive/` (5.1 MB) still present by design; `.pkgmeta` is stale; no root LICENSE or CHANGELOG |
| Libs | green | 27 libs vendored, all pinned and documented in `Libs/CREDITS.md`, all referenced |
| Release / packaging | red | `.pkgmeta` says `package-as: Hekili`, ignores a nonexistent `VirtualState/spec`, ships no sibling addons, no release script, no tags, all TOCs `forever-dev` |
| Docs | yellow | Current layout/architecture docs are accurate; no index for 15 plans / 11 specs / ~17 research docs; README is the upstream retail README under a "Goodbye" banner |
| Credits / headers | green | Catnip/TDF/Hekili credit headers present in the ported Game/ files spot-checked |
| Tests | green | 693 pass, 0 pending, 0 skipped; 5 tags used consistently |
| Tooling gaps | yellow | No `make bench`, no `test-warrior`, no single-spec command or wow/wowdb note in the docs |

## (B) Ranked recommendations

1. **Add a minimal CI workflow.**
   - Evidence: `ls .github` gives FUNDING.yml and ISSUE_TEMPLATE only. The whole gate is `make check`, which already runs headless (bootstrap.sh comments mention "CI images").
   - Value: high. Catches a push that skips `make check`, and every merge lands on a green base.
   - Cost: 30-45 min, plus about 6-8 min per run (3 min of tests, 2-4 min bootstrap compiling Lua and luarocks, cacheable on the `.lua/` directory).
   - Shape: `ubuntu-latest`; `actions/cache` on `.lua/` keyed by `hashFiles('scripts/bootstrap.sh')`; `jdx/mise-action` (installs stylua 2.5.2 and lua-language-server 3.19.1 from mise.toml); `make bootstrap`; `make check`. LuaLS needs the WoW API annotations that `.luarc.json` points at (`/home/zack/.local/share/vscode-wow-api/Annotations/Core`, an absolute local path), so CI needs that repo cloned and `workspace.library` made relative or overridden. Without that, run lint, fmt-check, test, syntax and api-check only and leave typecheck local.
   - Recommendation: do now (without typecheck if the annotations are a hurdle).

2. **Prune merged branches and worktrees (section C).**
   - Evidence: `git branch --merged forever` lists 43 branches besides `forever`, nearly all with a worktree under `.claude/worktrees`; `git branch -r --merged forever` lists 45 remote refs. `git worktree list` has 44 entries.
   - Value: medium. Removes noise from `git branch`, IDE branch pickers and the codebase-memory index.
   - Cost: 10 min.
   - Recommendation: do now. Keep `forever-boundary` and `research/forever-revival` (not merged).

3. **Fix packaging to ship the four addons (CurseForge "Hekili Forever").**
   - Evidence: `.pkgmeta` is `package-as: Hekili`, `enable-nolib-creation: no`, and ignores `VirtualState/spec` (a path that no longer exists), `tools`, `docs`. It does not ignore `tests`, `archive`, `scripts`, `Makefile`, `mise.toml`, `.busted`, `.stylua.toml`, `.styluaignore`, `.editorconfig`. The addons live under `src/`, so the packager sees none of them at the top level. No `.release` script, no tags (the zmsl remote has none of its own; `git ls-remote --tags` returns 1932, all inherited from upstream).
   - What it needs:
     - Move the packager root to `src/` (a release step that copies `src/*` to a staging dir and runs the BigWigs packager there), or give `.pkgmeta` a `move-folders:` map (`Hekili/src/Hekili: Hekili`, plus the three siblings). One zip with four top-level folders is the normal CurseForge multi-addon layout.
     - Ignore list for `tests tools docs archive scripts Makefile mise.toml .busted .luacheckrc .luarc.json .stylua.toml .styluaignore .editorconfig .lua`.
     - Real `## Version:` via `@project-version@` in the four TOCs; the packager substitutes it, so `forever-dev` still works locally.
     - `## X-Curse-Project-ID:` in each TOC; a `CF_API_KEY` secret; a tag-triggered workflow (`BigWigsMods/packager@v2`).
     - Project name "Hekili Forever", a LICENSE (item 5), and a decision on which version scheme the content addons use (docs/dev/layout.md already says a class release bumps the pack's `## Version`).
   - Value: medium (only if the user wants to publish). Cost: 2-3 h, mostly first-run packager debugging.
   - Recommendation: soon, not before CI.

4. **Fork identity.**
   - Evidence: `git remote -v` gives only `origin https://github.com/zmsl/hekili.git`; `origin/HEAD -> origin/classic` (GitHub's default branch for the fork is `classic`, ls-remote HEAD agrees). `forever` vs `origin/classic`: 5462 ahead, 485 behind. `forever` vs `origin/master`: 2948 ahead, 0 behind. `.github/FUNDING.yml` has `patreon: Hekili`; `ISSUE_TEMPLATE/config.yml` links `github.com/Hekili/hekili/issues/2624`. `.pkgmeta` and the README still claim upstream's identity.
   - Value: medium. Issues filed on the fork would be mis-routed, and the Patreon link shows upstream's funding page on someone else's project.
   - Cost: 15 min. Add `upstream` = https://github.com/Hekili/hekili.git (fetch only; set the push URL to `no_push`), set the fork's default branch to `forever` in the GitHub settings, remove or replace FUNDING.yml and the issue-template links.
   - Recommendation: do now (the funding and issue links); the default branch change is yours.

5. **Add a root LICENSE and replace the README.**
   - Evidence: no LICENSE at root (only `Libs/VirtualGameAPI-1.0/LICENSE`). README is upstream's retail README ("Goodbye ... Old Readme below"), with install links to Hekili/hekili releases, none describing this fork, `make bootstrap`/`make check` or the four addons.
   - Value: medium (legal clarity before any publishing; first impression).
   - Cost: 30 min for the README (what it is, the four addons, install via symlink, dev quickstart, credit to Hekili and Catnip); the LICENSE text depends on upstream's license, which this audit did not verify, so check upstream before choosing.
   - Recommendation: soon.

6. **Tighten LuaLS.**
   - Evidence: `.luarc.json` disables `undefined-global` plus 9 other diagnostics, `diagnostics.globals` is `LibStub, Hekili, ns` only, and `typecheck` runs `--check .` on 155 files (src, tests and tools are all inside the root; only Libs, archive, .claude, .git and .lua are ignored). The library path is an absolute `/home/zack/.local/share/vscode-wow-api/...` path. With `undefined-global` off the IDE does not show `describe` as undefined, but it also does not flag real typos; luacheck (`.luacheckrc`, 7.7 KB) is what actually enforces globals. Result: typecheck is nearly decorative for correctness, and the busted globals (`describe`, `it`, `assert`, `spy`, `stub`, `before_each`, `finally`) are known to nothing.
   - Value: low-medium. Cost: 30-60 min to enable `undefined-global` with `diagnostics.globals` extended by the busted names, then triage the fallout.
   - Recommendation: later; do not let it block anything.

7. **Document `.lua/` sharing between worktrees and a one-spec command.**
   - Evidence: grep of README, docs/dev for `worktree`, `cp -a`, `--filter`, `make test` single-file usage finds only `docs/dev/layout.md:53` for `make bootstrap`. Worktrees get no `.lua/` (it is git-ignored; `!! .lua/`), so each new one either runs a 2-4 min bootstrap or copies the directory (paths inside hererocks are absolute, so copying is not guaranteed to work).
   - Add two lines to docs/dev/layout.md: `.lua/bin/busted tests/Game/State/resources_spec.lua` (or `--filter`), and either "symlink or copy `.lua`" or "run `make bootstrap`".
   - Value: low-medium. Cost: 10 min. Recommendation: do now.

8. **Tooling gaps.**
   - No `make bench` (the rule in CLAUDE.md refers to a TDF target; nothing here), no `make test-warrior`: `test-loop` is the Arms warrior loop and `test-druid` the Druid harness, so Warrior Fury/Protection scenario gates, if any, run only in `make test`.
   - `make packs` rewrites class files and is intentionally outside `check`. If someone edits `tools/packs/*.lua` without running it, nothing in `check` notices (only `git diff` after `make packs` would). A `packs-check` (run `make packs` then `git diff --exit-code src`) would close that; 1-2 min runtime.
   - `wow` MCP and `wowdb` are not mentioned in docs/dev or README; they are in CLAUDE.md of the sibling TacoDogForever project only. Content files cite "wowdb" in comments.
   - Value: low. Cost: 20 min for the packs-check. Recommendation: soon for packs-check; later for the rest.

9. **Docs index and superseded markers.**
   - Evidence: docs/superpowers has 15 plans and 11 specs, docs/research has 17 top-level entries (7 per-class directories, tdf/, inputs, 9 dated files), `docs/forever-cleanup.md` (a branch report from 2026-10-14), `docs/forever-facade-notes.md`, `docs/virtualstate-kickoff-prompt.md` (a session prompt, one-shot). No `docs/README.md`, no status column for which plans are done, no SUPERSEDED headers (not exhaustively checked). The 7 plans with matching branches (`forever-*`) are merged; 4 plan files (`headless-recommendation-loop`, `combat-harness...`, `gcd-kinds...`, `restructure...`) have branches or content in `forever` too, so likely all done.
   - Value: medium for a returning reader. Cost: 30-40 min for a table of title, date, status, branch/merge SHA. Recommendation: soon; move `virtualstate-kickoff-prompt.md` and `forever-cleanup.md` under docs/research or mark them historical.

10. **`archive/` removal.**
    - Evidence: archive/README.md says "kept temporarily ... removed once those files exist". Referenced only in `.luacheckrc`, `.styluaignore`, `.luarc.json` (ignore lists), `tools/list_api_reads.sh` (a comment) and `tools/packs/warrior.lua:4` (a comment pointing at `archive/TheWarWithin/Priorities/WarriorProtection.simc`). 5.1 MB, history keeps it anyway. Warrior and Druid files exist now.
    - Value: low (declutter). Cost: 15 min plus checking the remaining comment. Recommendation: later, when the Mage/Priest/Rogue/Warlock/Hunter packs no longer need the retail reference.

11. **Stale `.pkgmeta` entry and stray documentation.**
    - `VirtualState/spec` in `.pkgmeta` (item 3). Absent from the grep: `Virtual/`, `Forever/Classes`, `Hekili_Forever`, `ns.queue` appear nowhere in README or docs/dev except `architecture.md:152`, where `ns.queue` is the real name the engine check bans (correct, not stale). Commit messages mention `Hekili_Forever` historically (fine).
    - Value: low. Cost: part of item 3. Recommendation: with item 3.

## (C) Safe cleanup (NOT run)

Merged = reachable from `forever`. Not merged (keep): `forever-boundary` (worktree), `research/forever-revival` (worktree `forever-research`, also `origin/research/forever-revival`). The main checkout `/home/zack/src/hekili` and `forever-audit` are detached; leave them.

Review the list, then run from the main repo (`cd /home/zack/src/hekili`). `git worktree remove` without `--force` refuses a dirty worktree, and `git branch -d` refuses an unmerged branch, so both are self-guarding.

```bash
cd /home/zack/src/hekili
git fetch origin --prune

# 1. Worktrees whose branch is merged into forever (forever-boundary and the research worktree are skipped by the merged test)
for b in $(git branch --merged forever --format='%(refname:short)' | grep -vx 'forever'); do
  wt=$(git worktree list --porcelain | awk -v b="refs/heads/$b" '/^worktree /{p=$2} $0=="branch " b {print p}')
  [ -n "$wt" ] && [ "$wt" != "$(git rev-parse --show-toplevel)" ] && git worktree remove "$wt"
done
git worktree prune

# 2. Local branches merged into forever (everything except forever itself)
git branch --merged forever --format='%(refname:short)' | grep -vx 'forever' | xargs -r git branch -d

# 3. Remote branches: only your own forever-*, virtualstate-* and restructure ones that are merged.
#    Leaves origin/forever, origin/classic, origin/master, origin/tbc, origin/wrath*, etc. (upstream's) untouched.
git branch -r --merged forever --format='%(refname:short)' \
  | grep -E '^origin/(forever-|virtualstate-|restructure$)' \
  | sed 's#^origin/##' | xargs -r git push origin --delete
```

Notes: step 1 first dry-run by replacing `git worktree remove` with `echo`. The remote-merged set is 45 refs, of which about 42 match the pattern in step 3. A worktree with uncommitted work (check `git -C <wt> status -s`) will stop step 1 for that one only (the loop continues; the later `branch -d` still succeeds because the branch is merged, leaving the worktree on a deleted branch, so read step 1 output before step 2).

## (D) Checked and found fine

**make check, with times** (run serially in the worktree, `PATH` including `.lua/bin`):

```
lint      rc=0   3s   (luacheck -q .)
fmt-check rc=0   5s   (stylua --check .)
typecheck rc=0   4s   (lua-language-server --check . ... "Diagnosis completed, no problems found", 155 files)
test      rc=0 181s   (busted --exclude-tags=party,loop,druid: 693 successes / 0 failures / 0 errors / 0 pending)
syntax    rc=0   0s   (luac -p over git ls-files '*.lua')
api-check rc=0   3s   (check_api_reads.sh, check_engine_reads.sh, git diff --exit-code tools/api_inventory.txt)
total ~196 s
```

- No silent-pass: `check_api_reads.sh` exits 1 if the TOC-derived file list is empty; `check_engine_reads.sh` exits 1 if an engine file is missing; `syntax` uses `git ls-files` (untracked new files are not checked until added).
- Not in `check` by design: `test-loop`, `test-party`, `test-druid` (about 190 s), `packs` (rewrites files). `.busted` ROOT lists tests/Game/{Events,API,State,harness}, tests/Forever and tests/boundary_spec.lua; every `_spec.lua` under `tests/` is inside one of them (a new top-level test dir would be skipped silently).
- `mise.toml` pins python 3.13, stylua 2.5.2, lua-language-server 3.19.1; `bootstrap.sh` pins hererocks 0.25.1, Lua 5.1, luarocks 3.8.0, busted 2.3.0-1, luacheck 1.2.0-1, luacov 0.17.0-1. Reproducible.
- `tools/api_inventory.txt` (5.4 KB): generated and committed; `api-check` fails on drift. Fine.
- Largest history blobs: ten successive Options.lua revisions, 579-589 KB each. No binary dumps.
- `git status --ignored` shows only `.lua/`. `.gitignore` is the stock Windows/OS list plus `.lua/`; no noise.
- Libs: 27 folders in `src/Hekili/Libs`, `CREDITS.md` documents upstream, pin (Ace3 Release-r1403, d295b12), licence and Forever load gates for each. Every lib name appears in `embeds.xml` or sources, except `VirtualGameAPI-1.0`, which is not in `embeds.xml` (the facade, `Game/API/Facade.lua` and `tests/Game/API/facade_spec.lua` reference it; not checked how it loads, via the TOC or by `require`). Textures 1.0 MB. src/Hekili total 4.5 MB.
- Credits: Catnip/Durts mentioned in 10+ Game/ files (Sources/Nameplates, Spellbook, Swing, Power, Target, Talents, Auras; Events/Attackers, Rows; API/Facade). Spot-checked ported files (Sources/Swing.lua, Families/Player.lua, ObsLog.lua, Belief.lua, Resources.lua) carry "Ported from Taco Dog Forever, src/TacoDogForever/..." headers with line references. Core files inherited from upstream (e.g. Engine/Sim/Core.lua) keep upstream's `-- Hekili.lua / April 2014` header, with no license text of their own.
- Tests by directory (specs / `it` count): tests/ 1 / 5; tests/Forever 13 / 169; tests/Game/harness 11 / 71; tests/Game/API 2 / 22; tests/Game/Events 3 / 70; tests/Game/State 19 / 248 (+1 helper file). Total 49 specs, about 585 `it(` blocks (693 assertions-counted successes). Tags: `#slow` (6 files, 8 uses), `#loop` (1 file, 2), `#party` (1, 1), `#druid` (1, 2). No `pending`/`xit`/`skip` anywhere. A crude grep for `it` bodies with no `assert`/`expect` found 9 hits (druid_harness_spec 327/335, loop_warrior_spec 236, headless_spec 170, group_spec 15/28, resources_spec 166/189/896); the ones I opened (group_spec:15, resources_spec:166) assert through local helpers (`check`, `within`), so these are false positives; the rest not opened.
- Per-tag runtime was not measured (would add about 5 more minutes); docs/dev/layout.md gives `make test-druid` about 190 s and gates making busted about 160 s, matching the 181 s seen.
- Fixtures: `tests/Game/harness/fixtures/log{1,2,3,5}.lua`, 60 KB total. Provenance is noted in each header (e.g. log1.lua: "log 1 of docs/research/2026-10-16-swing-outcome-pairing.md ... as /vslog recorded it"), produced by `tools/vslog_fixture.lua`.
- docs/dev/layout.md and architecture.md match the tree (Engine/Sim, Engine/Schema, Game/{API,Events,State}, UI, Integrations, Options exist). They document the four addons, `## Group: Hekili`, ContentAPI versioning and the test gates.
- Root files: `.busted .editorconfig .gitattributes .gitignore .luacheckrc .luarc.json .pkgmeta .stylua.toml .styluaignore Makefile README.md mise.toml` and dirs `archive docs scripts src tests tools`. Nothing stray. `scripts/` is just bootstrap.sh; `tools/` has 8 files plus `packs/`; no `spikes/` dir.
- TOC `## Version: forever-dev` in all four TOCs, `## Interface: 16001`.

Not checked: CurseForge account/project state; upstream's licence; whether `.lua/` copying works (hererocks uses absolute paths); LuaLS in CI; per-spec runtimes.
