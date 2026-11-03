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
