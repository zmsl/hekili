# LibTimeToDie-1.0

Time to die for World of Warcraft Forever (Interface 16001): seconds until a unit's health reaches 0, with a range,
from the 1% health bands of LibHiddenValues-1.0 (the client hides health from addons; that library reads its bands
back as plain numbers). You name the units; the library opens and keeps the health watches, estimates, and tells you
when its answer changes. It never touches a hidden value and never guesses without saying how sure it is: every
answer comes with `lo` and `hi`, and "unknown" is an answer.

MIT licence (see `LICENSE`). LibStub keeps one running copy (the newest minor).

## Install

LibTimeToDie calls LibHiddenValues through LibStub; you call only LibTimeToDie.

- Embedded: copy both folders into your addon and include `LibHiddenValues.xml`, then `LibTimeToDie.xml`, from your
  `embeds.xml`.
- Standalone: install both; list `## OptionalDeps: LibTimeToDie` in your TOC (LibTimeToDie's own TOC loads
  LibHiddenValues first).

Without LibHiddenValues every handle reads `unavailable, lhv-missing` and comes alive when it is there.

## Quick start

```lua
local TTD = LibStub and LibStub("LibTimeToDie-1.0", true)
if not TTD then return end -- keep your own fallback

-- An execute warning: shown while the target dies within 10 s, as far as the estimate can tell.
local h = TTD:Track("MyAddon", "target", function(h, est, lo, hi, state)
    warning:SetShown(state == "live" and hi <= 10)
end)

-- Or read it when you need it (no sink):
local est, lo, hi, state, reason = h:Get()

-- Done with it (your frame closed, your module off):
h:Release()                 -- or TTD:ReleaseAll("MyAddon"): every track and hint of yours
```

- `est`, `lo`, `hi` are seconds from now (nil unless `state` is `"live"`); `lo <= est <= hi`. The death time
  `GetTime() + est` stays put between the sink's calls; the seconds count down by themselves.
- The sink is called only when the published estimate (the estimator's deadband decides) or the state changes, at
  most once per frame, never from inside a call of yours. A new sink hears the current answer on the next frame.
- `h:State()` returns `state, reason`; `h:SetSink(fn)` swaps the sink (`true`, or `nil, code`); `h:SetPaused(true)`
  stops answering for this track (`paused`); `h:Release()` drops it.

## States

| State | `est` | Meaning |
|---|---|---|
| `live` | number | an estimate; `reason` says from what: `fit` (the recent fall), `seed` (the fall since the unit was first seen: little data), `prior` (the rate carried over from before a change of unit, a heal or a stall), `stalled` (the health stopped falling: the death time moves later with the clock) |
| `priming` | nil | the health is not read yet (a new watch, a new target; `reason` `pending` while LibHiddenValues' self-test runs) |
| `unknown` | nil | the health is read but has not fallen enough to estimate (a mob at full, a pull with no carried rate) |
| `gone` | nil | no unit, or it is plainly dead. A death the client keeps secret (under the dungeon restrictions it may) is not `gone`: the band reaches 0-1% and `est` stays near 0 until the target changes or clears |
| `unavailable` | nil | `reason`: `lhv-missing`, or LibHiddenValues' reason passed through (`unproven` for a token it does not read yet, `selftest`, `api`, `off`, `error`, `suspended`) |
| `paused` | nil | your `SetPaused(true)`, or every track of the token paused |
| `released` | nil | after `Release` |

`TTD:GetMessage(code)` gives the words for every code, state and reason (enUS for now; LibHiddenValues' reasons in its
own words; `nil` for a locale without text).

## What it tracks

Tokens are what LibHiddenValues reads health for: `player` and `target` now. Any other token returns a handle that
reads `unavailable, unproven` until LibHiddenValues proves it; write against it now. `TTD:IsAvailable(token)` returns
`ok, state, reason` (LibHiddenValues' answer for health on that token).

- One health watch per token (1% bands), shared by every track of it (and by any other addon's LibHiddenValues watch
  of the same unit), opened by the first track and freed with the last. Paused while every track of it is.
- A target change starts a fresh stream: the last mob's rate carries over for a few seconds (the estimator's rule), so
  the new target usually answers from its first band (`prior`).
- A re-prime of the same unit (a UI scale change, a loading screen) keeps the history and keeps answering.
- `gone` clears the stream and keeps your handle: the next unit starts fresh.
- Combat start re-anchors a stream with no 1% crossing yet (a mob targeted at full long before the pull).
- Every stream is read every 0.1 s while it exists (the estimator's deadband and its carried rate come from these
  reads), and in the frame after a new band.

## Hints

Numbers only: the library knows no spell, aura or class. Hints apply to every stream (`player` included), are kept per
owner (a new call replaces your last one of that kind; `ReleaseAll` clears yours), and several owners' hints multiply.
The estimator drops a hint the data clearly contradicts. Times are `GetTime()` seconds.

```lua
-- Bloodlust/Heroism: the group's damage runs 1.3 times faster for 40 s.
local now = GetTime()
TTD:HintRate("MyAddon", 1.3, now, now + 40)
-- It ended early (the buff was removed at 25 s): the same start, the real end. Do not clear it: clearing un-warps
-- every crossing it covered. Clear (factor nil or 1) only a hint that was wrong.
TTD:HintRate("MyAddon", 1.3, now, now + 25)

-- An execute phase: damage speeds up below 20%. Without a factor the library learns it from the units that cross the
-- threshold (recommended: your own damage is only part of the group's).
TTD:HintBelow("MyAddon", 20)
TTD:HintBelow("MyAddon", 35, 1.5) -- or a factor you know (still refined by what the units show)
TTD:HintBelow("MyAddon", nil)     -- clears yours
```

| Call | Returns |
|---|---|
| `TTD:HintRate(owner, factor, startTime, endTime?)` | `true`, or `nil, code`. `factor` > 0; `endTime` nil: open-ended |
| `TTD:HintBelow(owner, pct, factor?)` | `true`, or `nil, code`. `pct` in (0, 100]; `factor` nil: learned |

Several owners: the rate hints in force at the latest start multiply, up to the first of their ends; thresholds act as
one at the highest percent with the product of the factors given. A part a stream learned (a threshold's factor) or
dropped (a contradicted rate hint) is pushed again only when the combined hint changes. What a stream learned lives
with it: when the last track of a token is released, the next track of it starts from the hints as given.

## Error codes

Calls that refuse input return `nil, code`; codes are plain strings in `TTD.ERR`.

| Constant | Code | When |
|---|---|---|
| `OWNER_INVALID` | `owner-invalid` | owner not a string |
| `UNIT_INVALID` | `unit-invalid` | token not a unit token (letters, then letters or digits) |
| `SINK_INVALID` | `sink-invalid` | sink neither a function nor nil |
| `FACTOR_INVALID` | `factor-invalid` | a hint's factor not a number above 0 |
| `TIME_INVALID` | `time-invalid` | a rate hint's start not a number, or its end not a later one |
| `PCT_INVALID` | `pct-invalid` | a threshold not a number in (0, 100] |

A code LibHiddenValues refused the watch with (`pool-limit`: no bars left) is returned by `Track` as is.

## Diagnostics

The library prints nothing, registers no slash command and shows no frame. Its one frame (never shown) listens to
`PLAYER_TARGET_CHANGED` and `PLAYER_REGEN_DISABLED` and runs the driver.

| Call | Returns |
|---|---|
| `TTD:GetVersion()` | `"LibTimeToDie-1.0", 1` |
| `TTD:IsAvailable(token)` | `ok, state, reason` |
| `TTD:GetStreams()` | a fresh array (call it from a command, not every frame), one row per tracked token: `token`, `tracks`, `sinks`, `state`, `reason`, `est`, `lo`, `hi`, `crossings` (kept for the fit, at most 32), `drops` (hints the data contradicted), `rateFactor` (1: none), `rateStart`, `rateEnd` (nil: open), `executePct` (nil: none), `executeFactor` (with the stream's own measurement folded in) |

## Testing your addon

`Testing/FakeClient.lua` runs both libraries on LibHiddenValues' fake client (stock Lua 5.1, not in the TOC):

```lua
local Fake = dofile("libs/LibTimeToDie/Testing/FakeClient.lua") -- finds libs/LibHiddenValues beside it
Fake.world.unit.target = { health = 1.0 }
dofile("MyAddon.lua")
Fake.login()
Fake.tick(12)                                   -- priming
Fake.world.unit.target.health = 0.985           -- the 98-99% band
Fake.advance(0.5)
Fake.world.unit.target = { health = 0.5 }       -- a new target
Fake.event("PLAYER_TARGET_CHANGED")
Fake.restore()
```

## The estimator

`Estimator.lua` is the winner of an offline lab (synthetic fights and recorded solo fights, scored against the true
time to die, flicker counted): an exponentially time-weighted least-squares fit of time on percent over the recent 1%
crossings (half-life 6 s, 30 s window), the cumulative slope while there is too little spread, a carried slope over a
swap, heal or stall, a stall that holds the countdown, a change detector that restarts the fit when the rate steps,
and a deadband on the published death time so the countdown is smooth. `lo` and `hi` come from a fast and a slow
half-life (3 s and 12 s), or 0.5x to 3x of `est` while the answer rests on little data. The range was not calibrated
against the truth in the lab.

## Later (version 2)

- Nameplate and boss tokens, once LibHiddenValues marks them proven.
- Lazy coarse tracking of past targets through their nameplates (a background estimate per recent target).
- The target adopting a watched nameplate's stream when you target that mob (no restart).
- Hints per unit (today they apply to every stream).
