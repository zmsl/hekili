# TTD lab

An offline lab that compares time-to-die estimators on the observation the client gives us, and the winning
estimator as a pure module (`estimator.lua`) a TTD library can lift as is. Stock Lua 5.1, no dependencies, run
from the repo root.

```sh
lua5.1 tools/ttd_lab/estimator_test.lua            # the estimator's own checks (also: run.lua test)
lua5.1 tools/ttd_lab/run.lua main                  # baselines, winner, ablations, candidates on seed set A (~30 s)
lua5.1 tools/ttd_lab/run.lua sweep --round 5       # one-at-a-time parameter sweep around round 5's base (~70 s)
lua5.1 tools/ttd_lab/run.lua holdout               # the same lineup on held-out seed set B (~30 s)
lua5.1 tools/ttd_lab/run.lua all > out.md          # all of it (~7 min); --scale 0.2 for a quick look
```

`results/` holds the committed tables (`main.md`, `sweep-round1.md` ... `sweep-round5.md`, `holdout.md`).
Every table is deterministic (own Park-Miller generator, fixed seeds).

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
stream beyond the truth's own); first-answer delay per stream. Overall = mean over classes.

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

No allocation after `New`, no game API, every divisor guarded. If the target is acquired before combat, call
`Restart` at combat start so the full-health anchor is not stale.

## Not covered

The headless loop's class worlds (`tests/Forever/helpers/*_world.lua`, `tests/Game/harness/world.lua`) record the
true target health per wound. Feeding them here would need a busted run that dumps `(t, health)` per wound for each
world's fights to a file this lab reads (a small spec per world, ~1 day); the wowsims logs give real damage shapes
without it.
