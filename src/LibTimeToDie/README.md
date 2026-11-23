# LibTimeToDie-1.0

Time to die for World of Warcraft Forever (Interface 16001): seconds until a unit's health reaches 0, with a range,
from the 1% health bands of LibHiddenValues-1.0 (the client hides health from addons; that library reads its bands
back as plain numbers). You name the units; the library opens and keeps the health watches, estimates, and tells you
when its answer changes. It never touches a hidden value and never guesses without saying how sure it is: every
answer comes with `lo` and `hi`, and "unknown" is an answer.

MIT licence (see `LICENSE`). LibStub keeps one running copy (the newest minor).

## Install

LibTimeToDie calls LibHiddenValues through LibStub; you call only LibTimeToDie. The package carries
LibHiddenValues inside it (`Libs/LibHiddenValues`, loaded by `LibTimeToDie.xml` and the TOC before the library's own
files), so you depend on LibTimeToDie alone:

- Embedded: copy the `LibTimeToDie` folder into your addon and include `LibTimeToDie.xml` from your `embeds.xml`.

LibStub runs the newest copy of each library on the client, wherever it was loaded from, so another addon's
LibHiddenValues and the bundled one never both run. LibTimeToDie needs LibHiddenValues minor 10 or newer
(`TTD.LHV_MIN`): nameplates and their 5% step came with it, and the whole library asks for it (the package bundles
minor 10, so LibStub always has it when this package loads), so with an older one every token reads `unavailable,
lhv-old`, the target too. Without LibHiddenValues every handle reads `unavailable, lhv-missing`. Both come alive once a
suitable one is loaded.

The package is built with `tools/package.sh [--tag v<major>.<minor>.<patch>]` (the folder and `LibTimeToDie-<version>.zip` in
`.release/`, without `Testing/`; the repository vendors one LibHiddenValues source in `src/LibHiddenValues`). Two copies
of one LibHiddenValues minor must be identical (LibStub keeps whichever loads first): the script packages HEAD
(`git archive`; `--worktree` is its test mode, never a release), a release needs the vendored copy at a release tag, and
LibHiddenValues' own repository keeps a minor unchanged after its release.

## Quick start

```lua
local TTD = LibStub and LibStub("LibTimeToDie-1.0", true)
if not TTD then return end -- keep your own fallback

-- An execute warning: shown while the target dies within 10 s, as far as the estimate can tell.
local h = TTD:Track("MyAddon", "target", function(h, est, lo, hi, state)
    warning:SetShown(state == "live" and hi <= 10)
end)

-- Or read it when you need it (no sink); id: which mob's estimate this is (below, "Past targets"):
local est, lo, hi, state, reason, id = h:Get()

-- Done with it (your frame closed, your module off):
h:Release()                 -- or TTD:ReleaseAll("MyAddon"): every track and hint of yours
```

- `est`, `lo`, `hi` are seconds from now (nil unless `state` is `"live"`); `lo <= est <= hi`. The death time
  `GetTime() + est` stays put between the sink's calls while it is ahead; `est` never goes below a quarter of the
  seconds one percent takes at the current rate, so near the end a read stops short of 0 without a sink call.
- The sink is called only when the published estimate (the estimator's deadband decides) or the state changes, at
  most once per frame, never from inside a call of yours. A new sink hears the current answer on the next frame.
- `h:State()` returns `state, reason`; `h:SetSink(fn)` swaps the sink (`true`, or `nil, code`); `h:SetPaused(true)`
  stops answering for this track (`paused`); `h:Release()` drops it.

## States

| State | `est` | Meaning |
|---|---|---|
| `live` | number | an estimate; `reason` says from what: `fit` (the recent fall), `seed` (the fall since the unit's first 1% crossing, over at least 1.5 s: little data; the last target's slower rate may lengthen it), `prior` (the rate from before a heal or a stall: the unit's own, or the last target's slower one lengthening it), `stalled` (the health stopped falling: the death time moves later with the clock) |
| `priming` | nil | the health is not read yet (a new watch, a new target; `reason` `pending` while LibHiddenValues' self-test runs) |
| `unknown` | nil | the health is read but has not fallen enough to estimate (a new pull or a new target before 2% of crossings over 1.5 s, or 3% for a fit) |
| `gone` | nil | no unit, or it is plainly dead. A death the client keeps secret (under the dungeon restrictions it may) is not `gone`: the band reaches 0-1% and `est` stays near 0 until the target changes or clears |
| `unavailable` | nil | `reason`: `lhv-missing`, `lhv-old`, a code LibHiddenValues refused the watch with, or LibHiddenValues' reason passed through (`unproven` for a token it does not read yet, `selftest`, `api`, `off`, `error`, `suspended`) |
| `paused` | nil | your `SetPaused(true)`, or every track of the token paused |
| `released` | nil | after `Release` |
| `untracked` | nil | `TTD:Get(owner, token)` only: you have no estimate on that token now (a past target's life released, a plate token that names another unit now, a token nobody tracks) |

`TTD:GetMessage(code)` gives the words for every code, state and reason (enUS for now; LibHiddenValues' reasons in its
own words; `nil` for a locale without text).

## What it tracks

Tokens are what LibHiddenValues reads health for: `player`, `target` and `nameplate1` to `nameplate40` (5% bands, below)
now. Any other token returns a handle that reads `unavailable, unproven` until LibHiddenValues proves it; write against
it now. `TTD:IsAvailable(token)` returns
`ok, state, reason` (LibHiddenValues' answer for health on that token).

- One health watch per token (1% bands), shared by every track of it (and by any other addon's LibHiddenValues watch
  of the same unit), opened by the first track and freed with the last. Paused while every track of it is.
- One estimate per owner and token: every owner's estimator gets the same crossings; your tracks of a token share
  yours. An owner that starts tracking a unit already watched starts from its current band (the earlier crossings
  are not replayed).
- A target change starts a fresh stream unless the new target's plate holds its estimate (below, "Past targets"): the
  new target reads `unknown` until it
  has lost health over 1.5 s after its first 1% crossing (2% of crossings, or 3% for a fit): a big first hit is not
  a rate, whether combat started before it or you took the target in combat. From then the last target's rate can
  make the first answers longer for a few seconds (the estimator's rule), never shorter. That rate is kept for 10 s
  after the last answer, so a corpse or a stalled target still targeted keeps it for as long as it answers. The
  exception is your hints' state, by design: a threshold factor learned by `HintBelow` (or a rate hint the last target's
  data dropped) carries to the next unit and can shorten its answers.
- The same unit also reads `unknown` until its next percent when it heals 3% or more and combat then starts before it
  loses health, and after a plain death or loss of the unit that was none (a feign death). Cleared and targeted again,
  it gets its history back when its plate kept it (below), else it starts fresh.
- A re-prime of the same unit (a UI scale change, a loading screen) keeps the history and keeps answering.
- `gone` clears the stream and keeps your handle: the next unit starts fresh.
- Combat start restarts a stream with no 1% crossing yet (a mob targeted at full long before the pull): the time it
  sat idle never counts.
- Every stream is read every 0.1 s while it exists (the estimator's deadband and its carried rate come from these
  reads), and in the frame after a new band. A stream LibHiddenValues reports unavailable is read again only on a
  band, your read, a hint or a LibHiddenValues capability change; one with no watch (`lhv-missing`, `lhv-old`, a
  refusal) tries to open it at most once a second, on your read or the driver's.

## Past targets (lives)

Each mob's estimate is a life, with an `id` (a plain whole number, new per life, per session). When you switch away
from a target, its life moves to that mob's nameplate, which feeds it at 5%; when you switch back, the target takes it
again and answers at once (the same `id`, the 1% watch again) instead of reading `unknown` for a few seconds. A boss
with adds: switch to an add and back, and the boss resumes its fit. A boss you never leave costs nothing: no plate
watch, no extra reads, no allocation.

```lua
TTD:SetRecent("MyAddon", true)  -- on by default; false: your records stop following new targets (it restarts, as before); records already on plates stay until they go
local est, lo, hi, state, reason, id = TTD:Get("MyAddon", "nameplate3") -- whatever that plate holds for you now
for i = 1, 4 do                 -- your past targets still on their plates, newest first
    local token, id = TTD:Recent("MyAddon", i)
    if not token then break end
end
```

| Call | Returns |
|---|---|
| `TTD:Get(owner, token)` | `est, lo, hi, state, reason, id` for whatever life `token` holds now, no handle, no allocation; no record of yours there: `nil, nil, nil, "untracked"` |
| `TTD:Recent(owner, i)` | `token, id` of the i-th newest past target whose plate still holds its life with a record of yours; `nil` past the end |
| `TTD:SetRecent(owner, on)` | `true`, or `nil, code` |
| `TTD:Track(owner, "nameplateN", sink)` | a handle on that plate at 5%: a fresh life when it opens and after each `NAME_PLATE_UNIT_REMOVED`; it shares the target's life while it is the target's plate |

- A life moves only on a plain `UnitIsUnit` true between the target and a shown plate, checked at a target change (and
  for a plate that appears for the target, one read later unless a target change came first). A secret answer links
  nothing. A plate token names a new unit after `NAME_PLATE_UNIT_REMOVED`: the plate's hold ends there (a returning
  token never inherits). Which plate is which mob: the token is the reference now; `id` over time (the same `id` is the
  same mob; a new `id` does not prove another mob).
- Handed on only with a 1% crossing, a band and the mob not plainly dead, and if some owner has not opted out (an
  opted-out owner's record stays behind). Kept until the plate's REMOVED, combat end, or more than four past targets
  (`TTD.RECENT`; the oldest goes first; your own plate tracks do not count). Then `Get` reads `untracked` there.
- While a plate feeds a life its range is 1.1x wider at both ends (`TTD.WIDEN`: 5% bands cover less often, the plates
  lab). The hand-over band (the first band of the new watch) is never a crossing; a band whose bottom is 3% or more
  above the last band's top is not that mob now: a new life and `id`. Every rise on a plate is fed (a 5% cell up is a
  heal to the estimator). A plate that starts without a past target's life is a cold start: 10-25 s before its first
  answer at 5%.
- Costs: 6 LibHiddenValues bars per plate fed in the background (24 at most), none while the mob is the target; about
  15 us a frame per plate fed. A plate watch is made when you switch away; a watch refused with `pool-limit` drops the life (a restart, as before); a bar refused later reads `suspended`.
- Your hints stay yours across moves; a learned `HintBelow` factor carries as it does to a new target.

## Hints

Numbers only: the library knows no spell, aura or class. Your hints are yours alone: they bend only your own
estimates, and another addon's hints never reach yours (each owner's estimate depends on the shared health crossings
and its own hints only). A new call replaces your last one of that kind; `ReleaseAll` clears yours. Hints describe
damage dealt, so they apply to hostile units only: never to `player`, never to a friendly target. The target's
hostility is read with `UnitCanAttack` at each target change (an answer the client keeps secret counts as hostile; a
moment with no target changes nothing); other tokens are read once, when the stream opens. The estimator drops a hint
the data clearly contradicts. Times are `GetTime()` seconds.

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

One rate hint and one threshold per owner: a second rate call before the first window ends replaces it (also for the
crossings it covered), so combine overlapping windows yourself (one window at the product). A call that repeats your
hint changes nothing, so what your estimate learned (a threshold's factor) or dropped (a contradicted rate hint) is
kept; a new hint is pushed afresh. A friendly target in between keeps a learned threshold factor; going back to a
hostile one pushes your rate hint again (even one the estimator had dropped). What your estimate learned lives with
it: when your last track of a token is released, your next track of it starts from the hints as given.

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
`PLAYER_TARGET_CHANGED`, `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `NAME_PLATE_UNIT_ADDED` and
`NAME_PLATE_UNIT_REMOVED` and runs the driver.

| Call | Returns |
|---|---|
| `TTD:GetVersion()` | `"LibTimeToDie-1.0", 5` |
| `TTD:IsAvailable(token)` | `ok, state, reason` |
| `TTD:GetStreams()` | a fresh array (call it from a command, not every frame), one row per tracked token and owner: `token`, `owner`, `tracks` and `sinks` (that owner's), `state`, `reason`, `est`, `lo`, `hi`, `crossings` (kept for the fit, at most 32), `drops` (hints the data contradicted), `rateFactor` (1: none), `rateStart`, `rateEnd` (nil: open), `executePct` (nil: none), `executeFactor` (with the stream's own measurement folded in) |

## Testing your addon

`Testing/FakeClient.lua` (in this repository's source tree: the package zip does not carry it) runs both libraries on
LibHiddenValues' fake client (stock Lua 5.1, not in the TOC), with a
`UnitCanAttack` (`unit.friendly = true` for a friendly unit; `Fake.world.secretAttack = true` for a secret answer):

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
heal or stall (over a swap only to lengthen), a stall that holds the countdown, a change detector that restarts the fit
when the rate steps, and a deadband on the published death time so the countdown is smooth. `lo` and `hi` come from a
fast and a slow half-life (3 s and 12 s), or 0.5x to 3x of `est` while the answer rests on little data; when the fit
hits its clamp (0.2x to 5x the cumulative slope) the range also covers the unclamped fit, so a clamped answer does
not look certain. The range also covers the stream's own crossing noise (`rangeZ` 1.15): this term is capped at 3x
either way of `est`, but the fit spreads and the clamp widening can reach further, so an early fit range can be much
wider than 3x. The seed and prior ranges are 0.5x to 3x. Calibrated in the lab, `[lo, hi]` held the truth on about
79% of the polls of the five real solo fights pooled (in-sample; single fights 60-89%), 70-75% on lumpy and recorded
synthetic fights, less where the rate steps (a Bloodlust, an execute phase). Short fights get wide ranges: that is
the honest answer, not a defect; about one poll in ten sits at the cap.

Another unit's slope only lengthens (`priorEmpty` false here, true in the lab, and the lines marked minor 3): the lab's
rule read a tough mob pulled or targeted within 10 s of the last answer about a short kill as that kill's time for
several seconds (a corpse or a stalled target still targeted keeps answering, so those 10 s never ran out). Now a unit
answers from its own crossings, and a slower slope of the last unit can only lengthen that (a learned `HintBelow`
factor aside, above). It still steadies packs whose mobs are all hit at once (cleave: the lab's packs flicker no more
than before), at about 0.3 s more `unknown` per new target; single swaps and pulls between similar mobs flicker more
(about 1.3x to 1.4x the lab rule's flips). A weak mob after a tough one still reads too long at first.

The first estimate (minor 4; `anchorFull` and `anchorBelow` false here, true in the lab, and `seedTime` 1.5 s, the
lines marked minor 4): the lab started a stream at the unit's first band (full: 100% at the targeting or combat start;
damaged: the band's middle), so one big first hit a moment later read as a rate. A recorded pull read 3.6 s (range
1.8-10.9) on a mob with about 52 s to live. Now a stream starts at its first 1% crossing and its first answer (`seed`)
waits until its own crossings span 1.5 s; a fit (3% over 1.5 s) may come first. In the lab this kept
the protection of reading `seed` as unknown, with a little less silence: first answer about 4.1 s
after the target or combat start against 4.5 s, 12.1% of reads `unknown` against 12.5%. Against minor 3 the first
answer comes about 2 s later (chain pulls 1.0 -> 3.0 s) and up to about 5.5 s later on long boss fights (a lust mid-fight
2.9 -> 8.3 s; a lust at the pull 2.2 -> 6.4 s; an idle boss pulled from out of combat 4.2 -> 9.8 s, the largest). Accepted limits:
- Minor 3's lengthening has nothing to lengthen in the first 1.5 s: a new target reads `unknown` there, not the last
  target's slower rate.
- After a sudden speed-up mid-fight the estimate can blank (`unknown`) for up to about 1.5 s, mostly on fast trash.
- A burst opener and lumpy damage still read short sometimes: one more stream in 180 than reading `seed` as unknown in each of three
  such lab classes (none a boss, elite, lust or execute fight).
- Ranges: on a solo fight with an execute and a lust the later range held the truth on 34.9% of reads against 38.2%;
  on one recorded session the median range is wider (hi/lo 4.37 against 2.95; another session went 2.55 to 2.84).
- One recorded fight flips its 5 s and 8 s lines 16 times a minute against 5: a quiet band then a big
  chunk late in the fight, read without the anchor.
- `staleAnchor` and `newAnchor` act only with an anchor, so not by default.

## Later (version 2)

- Boss tokens, once LibHiddenValues marks them proven.
- A plate's death read before its removal (today it shows at the REMOVED, about 0.25 s late).
- Hints per unit (today an owner's hints apply to all its hostile units).
