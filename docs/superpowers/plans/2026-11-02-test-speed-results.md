# Test speed: results

Plan: `2026-11-02-test-speed.md`. Base commit f89a84642 (`git rev-parse --short HEAD`), nproc 16, MemTotal 24608392 kB
(WSL2). Raw logs: `~/src/hekili-speed-runs/<task>/`.

## How measured

`/usr/bin/time -o <run>.time -f "wall %e user %U sys %S"` (user+sys counts waited-for children), `XDG_CACHE_HOME`
pinned to `~/src/hekili-speed-runs/base/cache` for every base run (one cache for the state, so the warm-up primes the
longest-first order), one warm-up run discarded, the whole check batch in one hold of `/tmp/hekili-gate.lock`.

## The extractor (`scripts/results.sh LOG...`)

Sorted lines of the logs, without: make's lines (`^make`, `make\[`), the runner's `== <file>` headers, progress lines
(only `+ - * .` or `●◼✱⊝`), busted's per-file summaries (` : <s> seconds`), `/usr/bin/time`'s `wall` line, and
Python's `ResourceWarning: unclosed database ... at 0x<addr>` warnings with the source line after each and the
tracemalloc hint (address and the place the collector fires vary run to run). Kept lines lose: a progress-mark prefix
before a letter (`+solo bear: ...`), `; cpu mean ... per Update` (the rig's strip), and the tool counts that change
with the plan's own files: luacheck `in N files`, the LuaLS progress bar (only `Diagnosis completed ...` kept),
unittest `Ran N tests`. The runner's `all files:` totals stay.

Noise check: `diff` of `results.sh` over check0/1/2/3, pairwise (1-2, 1-3, 0-1, 2-3): empty.
`base-check.results` = `results.sh check1.log` (622 lines); `base.results` = `results.sh gate0.log` (705 lines; see
the gate note below).

## Baseline

| measure | run 1 | run 2 | run 3 | spread |
|---|---|---|---|---|
| check wall s (warm-up 354.8, discarded) | 277.3 | 261.7 | 263.5 | 15.6 (6 %) |
| check user+sys s | 3135.4 | 3034.9 | 3072.9 | 100.5 (3 %) |
| check per-file sum s (172 files) | 3868 | 3625 | 3752 | 243 |
| check sum / 16 jobs s | 242 | 227 | 235 | |
| check slowest file s (`detect_more_spec.lua`) | 262 | 246 | 248 | |
| gate | deferred | deferred | deferred | |

Check results: 2788 successes / 0 failures / 0 errors / 1 pending, every run. Check load at each start (1-minute
average) was 6.6 / 16.1 / 13.0, mostly the previous run's own 16 jobs; no other busted ran.

Top 10 check files (check1, s): detect_more 262.4, loop_druid 209.9, alts_seed3 188.7, wowsims_druid 174.0, group
151.0, solo 139.5, detect 129.9, alts 127.3, sweep 126.9, detect_sweep 125.6. The check is bound by
`detect_more_spec.lua` (262 s vs 3868 s / 16 = 242 s; 2026-11-01: 265 s vs 3931 s / 16 = 246 s).

Gate: **deferred, rerun on a quiet machine after the audit lanes merge.** Only the warm-up gate0 ran (13:09-13:23,
green: check 2788/0/0/1, gate tier 42 successes / 0 failures); four audit fix lanes started during it, so its numbers
are not a baseline: wall 834.2 s (check part included), user 8596.3 s, sys 103.1 s, gate-tier per-file sum 5903 s
(29 files), sum / 14 jobs = 422 s, slowest file `druid_harness_spec.lua` 506 s; then loop_shaman 386, loop_druid_feral
349, loop_warrior 261, loop_warlock_demonology 246, loop_warrior_protection 232, loop_warlock_destruction 228,
loop_warlock_shadow_brand 227, loop_warlock_affliction 226, loop_warlock_sm_ruin 221. The plan's note: the gate is
CPU-bound (2026-11-01: sum 8962 s / 14 = 640 s, above its slowest file, 479 s), so for the gate only CPU cuts (Tasks
5-8) can pay. gate0 does not agree (422 s < 506 s, the slowest file bounds it); the rerun decides. `base.results` from
gate0 is not yet shown noise-free (no second gate to diff against).

Not run yet (deferred with the gate): the rig on the base tree (`base/rig.txt`) and the per-`it` timings (`its.tsv`;
the batch script is `~/src/hekili-speed-runs/base/its-batch.sh`, filters per ruling S10).

## Per-`it` seconds of the split candidates (`its.tsv`)

Deferred.

## Per task

| task | metric | before | after | results identical | rig identical | kept |
|---|---|---|---|---|---|---|
