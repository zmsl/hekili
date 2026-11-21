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
```

`results/` holds the committed tables (`main.md`, `sweep-round1.md` ... `sweep-round5.md`, `holdout.md` (set B,
used to confirm near-ties while choosing), `holdout-c.md` (set C, run once on the final lineup); run 2: `run2.md`
(set A), `run2-b.md` and `run2-c.md` (sets B and C), `run2-tune-a.md` and `run2-tune-b.md` (both class sets),
`run2-grid*.md` (detector and learning grids)). Every table is deterministic (own Park-Miller generator, fixed seeds).
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
older than the next stream's first band, so a new pull does not inherit the last pull's slope.

Rate changes (run 2). On by default, with no caller input: a change detector (a two-sided CUSUM of each crossing's
lateness against the fit, standardised by the stream's own running variance; `detect = 6`, `detectK = 0.25`). When
it fires, the fit restarts at the crossing where the change began. Optional hints (they survive `Restart`; slopes
are kept in base-rate units, so a carried slope outlives a hint's end):

```lua
e:Hint("rate", 1.3, startT, endT)      -- a known damage multiplier over a time window (lust); endT nil: open ended
e:Hint("rate", nil)                    -- clear it
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

## Not covered

The headless loop's class worlds (`tests/Forever/helpers/*_world.lua`, `tests/Game/harness/world.lua`) record the
true target health per wound. Feeding them here would need a busted run that dumps `(t, health)` per wound for each
world's fights to a file this lab reads (a small spec per world, ~1 day); the wowsims logs give real damage shapes
without it.
