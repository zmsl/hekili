# Test speed: results

Plan: `2026-11-02-test-speed.md`. Base: forever ba149d6f7, branch base commit 471502040 (`git rev-parse --short HEAD`),
nproc 16, MemTotal 24608404 kB (WSL2). Raw logs: `~/src/hekili-speed-runs/<task>/`; the base is
`~/src/hekili-speed-runs/base2/` (2026-11-03, quiet machine). The first, partial baseline (f89a84642, 2026-11-02, a
busy machine, gate deferred) stays in `base/` for comparison only; every later task diffs against `base2/`.

## How measured

`/usr/bin/time -o <run>.time -f "wall %e user %U sys %S"` (user+sys counts waited-for children), `XDG_CACHE_HOME`
pinned to `base2/cache` for every base run (one cache for the state, so the warm-up primes the longest-first order),
one warm-up run discarded per batch. The check batch holds `/tmp/hekili-gate.lock` for the whole batch; the gates and
the rig take it themselves (`pgrep -c busted` was 0 before each). Load (1/5/15) is recorded at each start; after the
first run it is the previous run's own jobs (ps showed nothing foreign above 8 % CPU).

## The extractor (`scripts/results.sh LOG...`)

Sorted lines of the logs, without: make's lines (`^make`, `make\[`), the runner's `== <file>` headers, progress lines
(only `+ - * .` or `●◼✱⊝`), busted's per-file summaries (` : <s> seconds`), `/usr/bin/time`'s `wall` line, and
Python's `ResourceWarning: unclosed database ... at 0x<addr>` warnings with the source line after each and the
tracemalloc hint (address and the place the collector fires vary run to run). Kept lines lose: a progress-mark prefix
before a letter (`+solo bear: ...`), `; cpu mean ... per Update` (the rig's strip), and the tool counts that change
with the plan's own files: luacheck `in N files`, the LuaLS progress bar (only `Diagnosis completed ...` kept),
unittest `Ran N tests`. The runner's `all files:` totals stay.

Noise check: `diff` of `results.sh` pairwise (1-2, 1-3, 2-3, 0-1) over check0-3 and over gate0-3: all empty, no
new strip needed. `base-check.results` = `results.sh check1.log` (619 lines); `base.results` = `results.sh gate1.log`
(702 lines).

## Baseline

| measure | run 1 | run 2 | run 3 | spread |
|---|---|---|---|---|
| check wall s (warm-up 251.0, discarded) | 195.3 | 195.6 | 200.8 | 5.4 (2.8 %) |
| check user+sys s | 2677.3 | 2686.7 | 2775.9 | 98.6 (3.7 %) |
| check per-file sum s (176 files) | 2692 | 2711 | 2792 | 100 |
| check sum / 16 jobs s | 168 | 169 | 175 | |
| check slowest file s (`detect_more_spec.lua`) | 182.3 | 182.0 | 187.9 | |
| gate wall s (warm-up 662.7, discarded; check part included) | 598.9 | 598.9 | 601.2 | 2.3 (0.4 %) |
| gate user+sys s | 7573.3 | 7561.0 | 7556.9 | 16.4 (0.2 %) |
| gate-tier per-file sum s (29 files) | 4881 | 4873 | 4877 | 8 |
| gate-tier sum / 14 jobs s | 349 | 348 | 348 | |
| gate-tier slowest file s (`druid_harness_spec.lua`) | 401.7 | 401.8 | 404.5 | |

Results, every run: check 2817 successes / 0 failures / 0 errors / 0 pending; gate tier 42 successes / 0 failures.
Start loads: check 4.2 / 10.2 / 11.2, gate 3.5 / 6.7 / 6.6 (1-minute average).

Top 10 check files (check1, s): detect_more 182.3, loop_druid 146.1, alts_seed3 131.2, wowsims_druid 121.7, group
116.3, solo 105.7, detect 100.9, alts 96.2, detect_sweep 95.1, loop_rogue 94.1. The check is bound by
`detect_more_spec.lua` (182 s vs 2692 s / 16 = 168 s).

Top 10 gate-tier files (gate1, s): druid_harness 401.7, loop_shaman 358.5, loop_druid_feral 287.7, loop_warrior
284.9, loop_warrior_protection 248.4, loop_warlock_demonology 203.5, loop_warlock_sm_ruin 189.4,
loop_warlock_shadow_brand 188.5, loop_warlock_destruction 184.1, loop_priest_shadow 182.5. The gate's wall is about
the check part (~200 s) plus `druid_harness_spec.lua` (~400 s).

**The gate tier is not CPU-bound on this tree** (4877 s / 14 = 348 s, below its slowest file, 402 s), against the
plan's note (2026-11-01: sum 8962 s / 14 = 640 s, above its slowest file, 479 s). So splitting `druid_harness_spec.lua`
(Task 4) can pay on the gate, down to about the next file, loop_shaman (358 s); below that CPU cuts are needed.
Per-file seconds are wall under 14-16-way contention: the same file alone is faster (druid_harness's seven `it`s sum to
286 s single, against 402 s in the gate; detect_more's rows to 112 s, against 182 s in the check).

Rig (`~/src/hekili-rig/run.sh /home/zack/src/hekili-wt-speed speed-base2`, 07:03-07:20, load 3.8 at start): rc 0,
real 995 s, user 12745 s; 81 `RESULT` lines, each `errors 0 raises 0 self-check 0`; saved as `base2/rig.txt`.

## Per-`it` seconds of the split candidates (`its.tsv`)

One busted per row, alone under the lock (07:20-07:33, load 4.3 at start), wall s (user+sys); filters per ruling S10.

| file | tag | it (filter) | s | user+sys | ok |
|---|---|---|---|---|---|
| druid_harness_spec.lua | druid | bear | 105.13 | 105.09 | 1 |
| druid_harness_spec.lua | druid | cat | 59.84 | 59.82 | 1 |
| druid_harness_spec.lua | druid | regenAfter | 30.26 | 30.26 | 1 |
| druid_harness_spec.lua | druid | reload | 14.98 | 14.96 | 1 |
| druid_harness_spec.lua | druid | shift | 28.28 | 28.26 | 1 |
| druid_harness_spec.lua | druid | furor | 28.40 | 28.39 | 1 |
| druid_harness_spec.lua | druid | decay | 19.24 | 19.24 | 1 |
| loop_shaman_spec.lua | shaman | Enhancement | 111.43 | 111.35 | 1 |
| loop_shaman_spec.lua | shaman | Elemental | 120.43 | 120.39 | 1 |
| loop_warrior_spec.lua | loop | Arms 20 fights | 140.28 | 140.23 | 1 |
| loop_warrior_spec.lua | party | Arms party | 38.07 | 38.03 | 1 |
| detect_more_spec.lua | slow | K10 in | 5.35 | 5.33 | 3 |
| detect_more_spec.lua | slow | K11 in | 2.79 | 2.78 | 3 |
| detect_more_spec.lua | slow | K11m in | 2.91 | 2.90 | 3 |
| detect_more_spec.lua | slow | K12 in | 5.01 | 5.01 | 3 |
| detect_more_spec.lua | slow | K13 in | 5.09 | 5.08 | 3 |
| detect_more_spec.lua | slow | K13p1 in | 5.11 | 5.10 | 3 |
| detect_more_spec.lua | slow | K13p5 in | 5.06 | 5.05 | 3 |
| detect_more_spec.lua | slow | K14 in | 5.18 | 5.17 | 3 |
| detect_more_spec.lua | slow | K14p in | 5.12 | 5.11 | 3 |
| detect_more_spec.lua | slow | K14f in | 5.16 | 5.15 | 3 |
| detect_more_spec.lua | slow | K15 in | 5.00 | 4.98 | 3 |
| detect_more_spec.lua | slow | K17 in | 4.22 | 4.21 | 3 |
| detect_more_spec.lua | slow | K18 in | 5.12 | 5.12 | 3 |
| detect_more_spec.lua | slow | K19 in | 5.25 | 5.24 | 3 |
| detect_more_spec.lua | slow | K16: | 45.08 | 45.06 | 1 |
| detect_more_spec.lua | slow | K17: | 0.16 | 0.16 | 1 |

Per file, single: druid_harness 286.1 (bear 105, cat 60), loop_shaman 231.9 (Enhancement 111, Elemental 120),
loop_warrior 178.4 (#loop Arms 140, #party Arms 38), detect_more 111.6 (K16 45; each `K* in` row 3-5 s for 3 bands).

## Per task

| task | metric | before | after | results identical | rig identical | kept |
|---|---|---|---|---|---|---|
| 2 stamped check | `make check` wall s, inputs unchanged | 195.3-200.8 (full) | 0.19 / 0.20 (skip) | yes (both FULL=1 logs) | n/a (no rig input) | yes |
| 3 docs-only skip | `make check` wall s, only an unread doc changed | 195.3-200.8 (full) | 0.24 (skip) | yes (FULL=1 log) | n/a (no rig input) | yes |
| 4 split files | `make check FULL=1` wall s, base/split interleaved x3 | 240.9 / 230.3 / 266.3 | 217.9 / 217.3 / 258.1 | yes (result lines; new files add empty lines) | not run | yes |
| 4 split files | `make gate` wall s, interleaved x3 (loaded machine) | 801.8 / 898.1 / 867.4 | 1013.5 / 816.1 / 710.8 | yes (result lines) | not run | yes (by the bound file, see below) |

### Task 2: the stamped check

Raw logs `~/src/hekili-speed-runs/task2/` (`step6.out`, `full1.log`, `full2.log`, `skip1.log`, `skip2.log`,
`detect.log`), one `/tmp/hekili-gate.lock` hold, `XDG_CACHE_HOME=task2/cache`, 2026-11-03 11:58-12:07; start loads
7.55 and 5.04 (not a quiet machine: the full-run walls 285.7 s and 234.5 s are not timings, only proof).
- `make check FULL=1`: rc 0, wrote the stamp (`<worktree git dir>/hekili-check-stamp`).
- `make check`: the skip line, wall 0.19 s (user 0.06, sys 0.06) and 0.20 s, against Task 1's full check 195.3-200.8 s.
- `make check FULL=1` again: rc 0, no skip line, the stages ran (159 busted summary lines), stamp rewritten.
- `DETECT_WRITE=0 make check`: started check-full (`DETECT_WRITE` is in the key), killed by process group once
  `luacheck -q` ran; rc 143, `pgrep -c busted` 0 after, stamp unchanged (same md5), its start file left in /tmp.
- `make check` again: the skip line (the stamp is the last green one).
- `results.sh` of `full1.log` and `full2.log` diffed against `base2/base-check.results`: no output (619 lines each).
- `make gate` (12:08, load 8.55 at start, `pgrep -c busted` 0): rc 0, no skip line (check-full ran: 2817 / 0 / 0 / 0,
  gate tier 42 / 0), wall 824.1 s on the loaded machine (not a timing); `results.sh gate.log` diffed against
  `base2/base.results`: no output. The gate's check-full stamped, so a plain `make check` after it skips.

### Task 3: the docs-only skip

Raw logs `~/src/hekili-speed-runs/task3/` (`full1.log`, `docs.log`, `readme.log`), one `/tmp/hekili-gate.lock` hold,
2026-11-03 12:31-12:40; start load 4.88 (not a quiet machine: the full run is proof, not a timing).
- `make check FULL=1`: rc 0, wrote the stamp; `results.sh full1.log` diffed against `base2/base-check.results`: no
  output (619 lines).
- A line appended to `docs/dev/gaps.md`, `make check`: `check: skipped, only docs no test reads changed since the last
  green check: docs/dev/gaps.md; FULL=1 runs it`, wall 0.24 s; then `git checkout docs/dev/gaps.md`.
- A line appended to `README.md`, `make check`: no skip line, check-full ran (lint, fmt-check, typecheck, then
  `busted_parallel.sh` started), killed by process group (rc 143); then `git checkout README.md`.

### Task 4: the split files

Raw logs `~/src/hekili-speed-runs/split/` (`check-batch.out`, `gate-batch.out`, `check-{base,split}{0..3}.log`,
`gate-{base,split}{0..3}.log`, `.time` beside each, `names-*.{before,after}`, `top.sh` for per-file seconds). The base
arm is the same worktree with the split stashed (`git stash -u`), interleaved base, split; warm-ups 0 discarded;
`XDG_CACHE_HOME` per arm. 2026-11-03: check batch 14:17-14:49 under one lock hold (load 3.76 at start); gate batch
14:50-16:37, `pgrep -c busted` 0 before each.

Splits (single-process seconds from `its.tsv`): `druid_harness_gates_a_spec.lua` bear, reload, decay (139.4) /
`_b_spec.lua` cat, regenAfter, shift, furor (146.8), the gates in `helpers/druid_harness_gates.lua`;
`loop_shaman_enhancement_spec.lua` / `loop_shaman_elemental_spec.lua`; `loop_warrior_party_spec.lua`; detect_more:
K10-K18 stay (61.1), `detect_more_b_spec.lua` K19, K21, K16, K17 (56.1; K21 is not in `its.tsv`, measured alone at
5.56 s), each cell in `detect_more_cells.lua`. Names before/after: identical (both tiers).

- Check: every pair lower (-23.0 / -13.1 / -8.2 s), mean 245.8 -> 231.1 s, above Task 1's 5.4 s spread: kept. Top 5
  (split1): loop_druid 167.2, alts_seed3 151.3, wowsims_druid 141.0, group 131.3, solo 121.5 (detect_more gone from
  the top; base1 had it at 220.1).
- Gate: the machine was loaded (gate walls 711-1062 s against Task 1's 599; the check part's per-file sum 3195-7188 s
  against Task 1's ~2700), so the walls do not decide: the pairs went +212 / -82 / -157 s. The bound file did move:
  the gate tier's slowest file was druid_harness 522 / 471 / 442 s (then loop_shaman 483 / 427 / 411) on base, and
  loop_druid_feral 344 / 392 / 342 s on split (druid_harness_gates_a/b 242-316, Shaman packs <= 216). Kept, with a
  quiet-machine gate re-time owed. Top 5 gate tier (split3): loop_druid_feral 342.1, loop_warrior_protection 296.2,
  loop_warrior 266.4, druid_harness_gates_b 260.2, loop_warlock_demonology 247.0.
- Left whole (one gate-tier `it` each; the Warlock files also hold one #slow `it`; base2 gate1 s): loop_druid_feral 287.7, loop_warrior_protection 248.4,
  loop_warlock_demonology 203.5, loop_warlock_sm_ruin 189.4, loop_warlock_shadow_brand 188.5,
  loop_warlock_destruction 184.1, loop_priest_shadow 182.5, loop_warlock_affliction 182.1, loop_warrior_fury 151.0;
  alts_seed3 (check tier) 131.2.
- Results: `results.sh` of every split log against `base2`: the result lines are identical (`all files:` 2817 / 0 / 0 / 0
  and 42 / 0 / 0 / 0); the only difference is empty lines (check 1, gate 3): a new file whose first output is
  `print("\n...")` starts its log section with an empty line. A strip of empty lines in `results.sh` would close it.
- The split warm-up gate (split0, discarded) failed in its check part: `loop_warlock_destruction_spec.lua` (unchanged)
  ended with no output and a non-zero rc (2816 successes); no OOM line found. The three timed split gates passed.
