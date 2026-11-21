# TTD lab

An offline lab that compares time-to-die estimators on the observation the client gives us, and the winning
estimator as a pure module (`estimator.lua`) a TTD library can lift as is. Stock Lua 5.1, no dependencies, run
from the repo root.

```sh
lua5.1 tools/ttd_lab/estimator_test.lua            # the estimator's own checks (also: run.lua test)
lua5.1 tools/ttd_lab/run.lua main                  # baselines, winner, ablations, candidates on seed set A (~30 s)
lua5.1 tools/ttd_lab/run.lua sweep --round 5       # one-at-a-time parameter sweep around round 5's base (~70 s)
lua5.1 tools/ttd_lab/run.lua holdout [--set C]    # the same lineup on held-out seed set B, or C (~30 s)
lua5.1 tools/ttd_lab/run.lua all > out.md          # all of it (~7 min); --scale 0.2 for a quick look
lua5.1 tools/ttd_lab/run.lua run2 [--set B]        # run 2: the lust and execute classes, per-class tables (~2 min)
lua5.1 tools/ttd_lab/run.lua tune [--list grid3]   # run 2 lineup (or a grid) on old and new classes, one row each (~4 min)
lua5.1 tools/ttd_lab/run.lua run3 [--set B]        # run 3: partial-group execute, strategies a-d (~4 min)
lua5.1 tools/ttd_lab/run.lua run3 --list learn     # run 3: execute learning weight grid (~3.5 min)
lua5.1 tools/ttd_lab/run.lua run3old [--set B]     # run 3 strategies on the run 1 and run 2 classes (~2 min)
lua5.1 tools/ttd_lab/run.lua idle [--set B]        # idle targets: stale anchors, clamped ranges (~7 min)
```

`results/` holds the committed tables (`main.md`, `sweep-round1.md` ... `sweep-round5.md`, `holdout.md` (set B,
used to confirm near-ties while choosing), `holdout-c.md` (set C, run once on the final lineup); run 2: `run2.md`
(set A), `run2-b.md` and `run2-c.md` (sets B and C), `run2-tune-a.md` and `run2-tune-b.md` (both class sets),
`run2-grid*.md` (detector and learning grids); run 3: `run3.md` / `run3-b.md` (sets A / B), `run3-learn.md` /
`run3-learn-b.md`, `run3-old.md` / `run3-old-b.md`). Every table is deterministic (own Park-Miller generator, fixed seeds).
"Run 1 winner (pinned)" is the estimator as Run 1 left it (`PREV` in `run.lua`); its rows match Run 1's tables.

## Observation model (`observe.lua`)

- Frames every 16-33 ms. Health is never read; the target's 1% band is: `lo..lo+1`, the top cell 99-100 holding
  full health (the LibHiddenValues `health` step-1 contract).
- On a target change the stream restarts and is unknown for 8-12 frames (the prime), then the first band arrives.
- A band change is reported in the frame it is first seen or the next one (1-2 frames late), one report per frame
  with the net band, so a burst skips percents. Heals raise the band.
- Polls every 0.1-0.25 s while the target lives. Each carries the truth and the player's own damage per second over
  the last 3 s (the plain meter; no estimator uses it in the end, see the report).

## Fights (`scenarios.lua`, `real.lua`)

The player (rate 1) and 0-4 group members (rate 0.6-1.4) hit every 0.3-1.2 s with +-30% noise and 25% crits.
Classes: `trash` 8-20 s; `pack` 3-5 mobs with cleave, swaps on death plus 0-2 deliberate swaps (half swap back);
`mixed` the same with one mob at 3-5x health; `elite` 30-60 s; `boss` 3-6 min with an opener, lust and an execute
speed-up; `burst` a 2-3.5x opener; `dot` damage ramping from 25% over 6-14 s; `execute` 1.6-2.5x below 20-35%;
`stall` 4-10 s immunity at 30-70%; `heal` 2-5 heals of 1-5%; `phase` a reset to 70-100% at 35-55% with 2 s
immunity; `damaged` the player targets the mob only when the group has it at 30-90%; `real` the 30 checked-in wowsims
logs (`tests/Forever/wowsims/*.log`, one player's real damage on Target 1), the mob dying at 20, 60 and 180 s.

Run 2 classes (`S.RUN2`, `run.lua run2`; 50 fights each, 40 for bosses; every multiplier applies to all damage):
`lust pull boss|elite|pack` x1.3 for 40 s from the pull; `lust mid boss|elite` the same when the first mob reaches
30-60%; `lust end` an 80-150 s elite whose lust ends at 40 s with the mob at about 35-65%; `ex20|ex35 x1.3|1.6|2.0|2.5`
an execute at exactly 20% or 35% (the eight classes are the same fights; only threshold and multiplier differ);
`ex+lust elite|boss` an execute at 20-35% x1.6-2.5 with the lust started 0-15% above it; `solo` (no group, about 1.3
hits/s) and `raid` (15-19 members, about 25 hits/s) elites, plain and `ex+lust`.

## Algorithms

Baselines (`baselines.lua`, written from their descriptions in the research note, no third-party code): TimeToDie's
Initial Midpoints, Least Squares and Weighted Least Squares (halving per sample); HeroLib-style OLS of percent on time
over 10.4 s with more than 3 samples; Hekili-retail-style mean of the last 10 instantaneous rates (3 needed);
SimC-style cumulative average; the old plan's 8-point ring (unknown under 3 points, after a swap or any rise). All
answer an absolute death time; unknown covers the constant defaults some of them show instead.

`estimator.lua` is the winner; its parameters let the lab replay the research's recommendation and every sweep.

## Metrics (`metrics.lua`)

Per algorithm and class, every poll while the target lives: unknown share; abs error and relative error
`|est - true| / max(true, 2 s)` (median, p90), early (first 25% of the stream) and late (last 25%), and on the
polls every main-lineup algorithm answered ("common", no selection bias); decisions `ttd < 4, 8, 15` and
`fight_remains < 20` (the true end of the fight is the last mob's death; only the target has an estimate) with
unknown read as very long (the consumer's fallback), wrong-side share and excess flips per minute (flips within a
stream beyond the truth's own); first-answer delay per stream. Overall = mean over classes. Run 2 adds, outside the
score, the relative error and wrong side on "post-change" polls: those within 10 s after a lust start or end, an
opener's end, or the target crossing its execute threshold.

Score (lower is better) = weighted mean of each term over its median in the main lineup: unknown 1, rel median 0.5,
rel p90 0.5, wrong side 1, excess flips 1. Robustness: 2000 draws with each weight times 2^U(-1, 1).

## Lifting the estimator

```lua
local E = require("estimator")          -- one per watched stream (unit token)
local e = E.New()                       -- or E.New({ deathPct = 50 }) for a phase exit
e:Restart()                             -- on a unit change (the carried slope survives)
e:Band(t, lo, hi)                       -- every band callback (lo, hi percent; t = the callback's time)
local est, lo, hi, state = e:Get(now)   -- est nil: unknown; state fit | seed | prior | stalled | unknown
```

No allocation after `New`, no game API, every divisor guarded. `Band` takes a known band only: when the band goes
unknown (lo == nil), call `Restart`. If the target is acquired before combat, call `Restart` at combat start so the
full-health anchor is not stale. A carried slope is dropped when its last answer is more than `priorAge` (10 s)
older than the next stream's first band, so a new pull does not inherit the last pull's slope. A first-band anchor
older than `staleAnchor` (8 s) at the first crossing is dropped (an idle target in combat), and lo/hi cover an
unclamped fit (`clampRange`).

Rate changes (run 2). On by default, with no caller input: a change detector (a two-sided CUSUM of each crossing's
lateness against the fit, standardised by the stream's own running variance; `detect = 6`, `detectK = 0.25`). When
it fires, the fit restarts at the crossing where the change began. Optional hints (they survive `Restart`; slopes
are kept in base-rate units, so a carried slope outlives a hint's end):

```lua
e:Hint("rate", 1.3, startT, endT)      -- a known damage multiplier over a time window (lust); endT nil: open ended
e:Hint("rate", 1.3, startT, tEnd)      -- it ended early: re-issue with the same startT and the real end
e:Hint("rate", nil)                    -- clear: only for a hint that was wrong (it un-warps every crossing it covered)
e:Hint("execute", factor, pct)         -- a pack's execute range: below pct the damage runs factor times faster
e:Hint("execute", 1, 20)               -- the threshold only: the factor is learned (execLearn), starting at 1
local x = e:ExecuteFactor()            -- the factor in use, with the current stream's measurement folded in
```

A rate hint warps time (the fit sees one base rate; the projection runs faster inside the window). An execute
declaration warps percent: by default (`execAhead`) the projection already expects the speed-up below the threshold;
each stream that falls 5% below it measures slope above / slope below and moves the factor halfway there at the next
`Restart` (`execLearn = 0.5`). The detector drops a hint the data contradicts from its start (the change point within
max(2 s, 2 mean gaps) of the hint's start or the threshold crossing). The estimator keeps one rate hint at a time.

## Run 2 results (execute and lust)

Scores on the run 2 classes, sets A / B / C (lower is better; `run2*.md`): Midpoints 0.960 / 0.972 / 0.962, Run 1
winner 0.923 / 0.913 / 0.921, the default (detector) 0.916 / 0.903 / 0.913, plus a lust hint and an execute declared
at 20% on every fight with the factor learned 0.757 / 0.751 / 0.758, every hint perfect (the ceiling) 0.657 / 0.666 /
0.667. On the run 1 classes the default scores 0.843 / 0.835 / 0.838 against Run 1's 0.852 / 0.844 / 0.846, at
+0.1-0.7% flips. An execute declared with a fixed wrong factor is dangerous (20% x2 on every fight: 1.121 on the run 1
classes); learned, it is not (0.824). Details, per-fix value and concerns: the run 2 section of the lab report.

## Run 3 results (partial-group execute)

Fights (`S.RUN3`, `S.group`, `run.lua run3`): a session is one fixed 5-player group (the player, 3 more DPS at
0.7-1.3, a tank at 0.4-0.7 whose damage never speeds up) doing 10 pulls (`S.PULLS`: 6 trash packs of 2-4 mobs with
cleave and swaps, 3 elites, 1 boss). 14 compositions: 0, 1, 2 or 4 executing DPS of 4, the player executing or not,
lines 20%, 35% or a mix, one dominant DPS (2.5-3.5x) or not, and solo. Each executor has its own x1.5-2.5 below its
own line, so the group factor below a line is 1 + sum of executing shares x (mult - 1): 1.07-1.75 with one
executor, 1.1-1.6 with two, 1.25-2 with four. Stats per composition x length (42 buckets), 16 sessions per
composition and set; each session draws its pull seeds from its own generator.

Strategies (`est3` in `run.lua`; every one on the estimator's defaults, the factor carried pull to pull within a
session): a. no hint; b. the threshold only, factor learned from 1: the player's own line, or every line in the group
(classes known, tank excluded; the estimator has one execute slot, so the highest line); c. a composition prior: the
factor starts at 1 + executing DPS x (m - 1) x share (assumed m = 2, share = 1 / DPS count), then learns; wrong
priors (share 1/8 each: too low; m = 3: too high); d. the same priors fixed (`execLearn = 0`), and x2 whatever the
group; a reference (the true group factor below the top line, fixed: a ceiling for single lines, not for mixes).

Scores on sets A / B, the other columns set A (lower is better; `run3.md`, `run3-b.md`):

| strategy | run 3 score | rel med | post-crossing rel med | wrong ttd<8 | flips/min |
|---|---|---|---|---|---|
| a. no hint (default) | 0.834 / 0.829 | 0.18 | 0.27 | 6.1% | 14.04 |
| b. own line, learned | 0.745 / 0.741 | 0.12 | 0.16 | 5.2% | 14.00 |
| b. all lines, learned | 0.724 / 0.715 | 0.11 | 0.15 | 5.0% | 14.05 |
| b. all lines, learned w=0.25 (`execLearn = 0.25`) | 0.712 / 0.702 | 0.11 | 0.14 | 4.9% | 14.06 |
| b. all lines, learned, one factor across groups | 0.717 / 0.711 | 0.11 | 0.15 | 5.0% | 14.01 |
| c. all lines, prior x2 equal share, learned | 0.716 / 0.706 | 0.11 | 0.14 | 4.9% | 14.04 |
| c. prior too low (share 1/8), learned | 0.718 / 0.710 | 0.11 | 0.14 | 5.0% | 14.03 |
| c. prior too high (x3), learned | 0.721 / 0.714 | 0.11 | 0.15 | 5.1% | 14.05 |
| d. prior x2 equal share, fixed | 0.694 / 0.686 | 0.10 | 0.12 | 4.7% | 13.96 |
| d. prior too low (share 1/8), fixed | 0.721 / 0.717 | 0.11 | 0.16 | 4.9% | 13.96 |
| d. prior too high (x3), fixed | 0.796 / 0.783 | 0.16 | 0.24 | 6.2% | 14.33 |
| d. x2 whatever the group, fixed | 0.805 / 0.791 | 0.16 | 0.23 | 6.3% | 14.51 |
| reference: true factor at the top line | 0.683 / 0.676 | 0.09 | 0.12 | 4.5% | 13.95 |

The gain follows the group factor. One executing DPS of four (five compositions, factor about 1.15-1.3): score
0.725 / 0.687 with no hint, 0.701 / 0.660 learned at 0.5, 0.685 / 0.644 at 0.25, 0.663 / 0.638 with the right fixed
composition factor, 0.732 / 0.706 with the x3 one; wrong side ttd<8 5.0% -> 4.9% learned, 4.4% fixed right. Two or
more executors, or solo: ttd<8 5.5-9.3% -> 4.2-7.2% learned. The right prior's fixed row is near the reference only
because its assumptions (m = 2, equal shares) are the lab generator's means. A fixed factor that is too low is cheap
in groups but not solo (solo 35: 1.128 vs 0.965 learned); one that is too high loses to no hint where one DPS
executes (g1 20 me: 0.682 vs 0.657). On the run 1 and run 2 classes (`run3old`: the player believed a 20% executor,
members unknown, each fight a new group, so a prior is never corrected; most of those fights have no execute),
threshold-only learning is harmless (old score 0.845-0.847 vs 0.844) and every prior above 1 costs (too low 0.872,
x2 equal share 0.971-0.974, x3 1.079; set A).

## Idle targets (LibTimeToDie review I-3; `run.lua idle [--set B]`, `results/idle.md`, `idle-b.md`)

`S.IDLE`: the player targets a full mob nobody hits for 5-30 s, then the fight starts (trash, elite, boss, solo
elite; in combat the stream runs through the idle, out of combat (`ooc`) the caller restarts it at the first hit).
Before Run 3 the first band's full anchor made the first crossings read 20-40x long (a 20 s idle, then 0.5 s per
percent: 1979, 1004, 678 s against a truth of 48), and the fit, clamped to 0.2 x that cumulative slope, showed lo = hi
= est at 103, 83, 70 s (truth 47). Two defaults since Run 3:

- `staleAnchor = 8`: a first-band anchor (full or below) older than 8 s at the first crossing is dropped; the stream
  starts at that crossing (unknown until 2% of crossings, then right: 48 [24, 145], 47). 3 s costs on slow-start
  classes (old 0.847, run 2 0.927 vs 0.843 / 0.916); 12 s misses short idles (first 10 s of damage rel p90 0.90).
- `clampRange = true`: when the clamp moved a fit, lo/hi also cover the unclamped fit's estimate.

Set A / B (`idle.md`): idle classes' rel p90 1.71 / 1.62 -> 0.21 / 0.20, rel median in the first 10 s of damage 0.73
/ 0.71 -> 0.10 / 0.10, wrong side 2.9% -> 2.6%, unknown 25.9% -> 26.9% (the idle itself is unknown for everyone),
excess flips 0.85 / 0.90 -> 1.66 / 1.52 per minute (the estimate now reaches the decision range instead of sitting at
thousands of seconds), score 0.693 / 0.691 -> 0.718 / 0.673 (the flip term). Run 1 classes 0.843 -> 0.844 (A), 0.835
both (B); run 2 classes, run 3 tables and flips unchanged. Ranges are uncalibrated in general (truth inside lo/hi on
18% of old-class polls, median hi:lo 1.04); `clampRange` alone lifts idle coverage in the first 10 s of damage from
19% to 26%, `staleAnchor` removes most clamped cases (31%). The Run 1 and run 2 rows of `run.lua` (`est`) pin
`staleAnchor = 0`, so their committed tables still reproduce. Learning weight (`run3 --list learn`): threshold-only best at
`execLearn` 0.15-0.25 (0.25: 0.712 / 0.702 vs 0.724 / 0.715 at the default 0.5; 0.1 is best with one executor but
slow with four); the default stays 0.5 (Run 2's classes gain 0.004-0.008 at 0.25, old-class flips +0.8-1%).

## Not covered

The headless loop's class worlds (`tests/Forever/helpers/*_world.lua`, `tests/Game/harness/world.lua`) record the
true target health per wound. Feeding them here would need a busted run that dumps `(t, health)` per wound for each
world's fights to a file this lab reads (a small spec per world, ~1 day); the wowsims logs give real damage shapes
without it.
