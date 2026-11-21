# LibTimeToDie: in-game test plan (version 1, minor 2)

For the owner, one session on the live client, about 20 minutes. The library prints nothing and has no command of its
own: every step runs through a probe (a small TTDProbe, or LHVProbe extended; the commands below say `/ttdp`) that
calls the public API and prints what it gets. Everything the probe prints also goes into its copy box: paste that back
at the end.

The expectations are facts (a state, a reason, a count, a range); the probe's wording is its own.

## Setup

1. `scripts/Link-Addons.ps1` once more (it links `src/LibTimeToDie`, which has a TOC), then restart the client fully
   (a reload does not pick up a new folder).
2. At the character screen, AddOns: tick **LibHiddenValues**, **LibTimeToDie** and the probe.
3. Before the first step, out of combat, force the dungeon conditions; undo it at the end (out of combat):
   `/run C_CVar.SetCVar("addonMapRestrictionsForced", "1")` (end: the same with `"0"`).

## What the probe must call

All through `local TTD = LibStub("LibTimeToDie-1.0", true)`; the owner string is the probe's name (`"TTDProbe"`).

| Command | Calls | Prints |
|---|---|---|
| `/ttdp` | `TTD:GetVersion()`; `TTD:IsAvailable(token)` for `target`, `player`, `focus`; `TTD.LHV_MIN` and `select(2, LibStub("LibHiddenValues-1.0", true))` | major, minor; `ok, state, reason` per token; the minor needed and the one running |
| `/ttdp hostile` | `local v = UnitCanAttack("player", "target")` and `local x = UnitExists("target")`; `issecretvalue` of each; a value only when not secret | for each read: `secret` or `plain` and the value; `InCombatLockdown()`; the CVar `addonMapRestrictionsForced` |
| `/ttdp track2` | `TTD:Track("TTDProbe2", "target", sink2)`: a second owner that never hints (sink2 logs like the sink, tagged `2`) | the same sink lines, tagged |
| `/ttdp track <token>` | `TTD:Track("TTDProbe", token, sink)` (keep the handle per token; on `nil, code` print `TTD:GetMessage(code)`) | one line per sink call: `GetTime()`, token, `est`, `lo`, `hi`, `state`, and `h:State()`'s reason |
| (inside the sink) | append `{ t = GetTime(), est, lo, hi, state, reason }` to a log per token; on a change to `gone` take `t` as the death time | at `gone`: the summary below |
| `/ttdp get` | `h:Get()` for every handle | `est, lo, hi, state, reason` each, `TTD:GetMessage(state)` and `TTD:GetMessage(reason)` |
| `/ttdp poll` | toggles a 0.5 s ticker calling `h:Get()` on the target handle | one line per poll (for the countdown between sink calls) |
| `/ttdp streams` | `TTD:GetStreams()` | one line per row: every field |
| `/ttdp lust` | `TTD:HintRate("TTDProbe", 1.3, now, now + 40)` (`now = GetTime()`, kept as the start) | `true` or the code's message |
| `/ttdp lustend` | `TTD:HintRate("TTDProbe", 1.3, start, GetTime())` (the same start, the real end) | as above |
| `/ttdp hintclear` | `TTD:HintRate("TTDProbe", nil)` and `TTD:HintBelow("TTDProbe", nil)` | as above |
| `/ttdp below <pct> [factor]` | `TTD:HintBelow("TTDProbe", pct, factor)` (factor nil when not given) | as above |
| `/ttdp pause` / `/ttdp resume` | `h:SetPaused(true)` / `h:SetPaused(false)` on the target handle | the new `h:State()` |
| `/ttdp release` | `TTD:ReleaseAll("TTDProbe")` | then `TTD:GetStreams()` (empty) and LibHiddenValues' `GetSources()` health rows |
| `/ttdp stats` | `LibStub("LibHiddenValues-1.0"):GetStats()`; the library's own cost: at load, wrap the driver once, `local d = TTD.drive; TTD.drive = function() local t0 = debugprofilestop(); d(); acc = acc + debugprofilestop() - t0; n = n + 1 end` (the frame calls `TTD.drive` through a dispatcher, so the wrap takes) | LibHiddenValues' bars, µs per frame (average, peak); the driver's µs per frame (`acc / n`, then reset) |
| `/ttdp copy` | the copy box | |

The summary at `gone` (per kill), over the logged sink calls and polls while the mob lived: count of `live` lines;
the time from the first band to the first `live`; for every `live` line the truth `death - t`, its relative error
`|est - truth| / truth` (median and 90th percentile), the share with `lo <= truth <= hi`, and the share on the wrong
side of 5 s (est above 5 and truth below, or the other way); sink calls per minute. A death the client keeps secret
(the forced lockdown may) never reads `gone`: the stream stays `live` with `est` near 0. Then the probe takes the time
of the first `est` under 1 s, or else the time the target was lost, as the death time, and flags the summary as such.

## Steps and what to report

| # | Do | Expect |
|---|---|---|
| 1 | Log in, `/ttdp` (again after a second if target says `pending`) | `LibTimeToDie-1.0` minor 2; `target` and `player` `ready`; `focus` `unavailable (unproven)`; the LibHiddenValues minor running is at least the one needed |
| 1a | With the CVar forced (setup 3): target a hostile mob, `/ttdp hostile` out of combat, then again in combat with it; target a friendly player or NPC, `/ttdp hostile` in combat | report `secret` or `plain` for both reads each time (the library treats a secret UnitCanAttack as hostile and a secret UnitExists as present; plain is expected); plain values: UnitCanAttack `true` for the mob, `false` for the friendly unit; UnitExists `true`. Also `/ttdp hostile` with no target, in combat: UnitExists `false` (or secret) |
| 2 | Target a mob at full health, `/ttdp track target` | sink lines: `priming`, then `unknown` (at full, nothing to estimate yet) within a few frames |
| 3 | Fight it to death with `/ttdp poll` on | `live` from the first crossings (reason `seed` while the anchor holds, then `fit` after about 3%; a first hit in the frame of combat start gives `unknown` until 2% has fallen, never a 0.16 s estimate), `lo`/`hi` wide early (up to 3x either way of `est`) and narrowing as the fight goes, est falling smoothly with the clock between sink calls (the poll lines), few sink calls; at the death `gone`. Report the summary, including the share with `lo <= truth <= hi` (about 85% expected) |
| 4 | Three more kills of mobs of different sizes (one elite if at hand) | report each summary |
| 5 | Mid-fight, target another mob that is already damaged; then clear the target | `priming` for a few frames, then `live` with reason `prior` (the last rate carried) before it loses a percent; with no target `gone` |
| 6 | Target a mob at full, wait 20 s, then pull | the first `live` estimate is in the range of the fight's length, not minutes (combat start re-anchors), its range wide; no first estimate under about 1 s on a mob with many seconds to live |
| 7 | With the target stream `live`: change the UI scale (Options) | the TTD state stays `live` (no `priming` line), crossings continue (LibHiddenValues re-primes its bars underneath) |
| 8 | Stop attacking a damaged mob for 6 s or more (or let it heal: a mob that regenerates, a healer in the pack) | stall: reason `stalled`, est roughly holds (it may step by a second or two); heal of 3% or more: reason `prior`, then `fit` again |
| 9 | `/ttdp track player`, take damage and heal (or fall damage) | the player stream answers as the target's does; `/ttdp streams` shows two rows |
| 10 | When a Bloodlust/Heroism is cast in a group (or as a test with none): `/ttdp track2`, then `/ttdp lust` at the cast, `/ttdp lustend` when it ends early | the target's est drops at once on `lust` for `TTDProbe` only: the `TTDProbe2` lines do not move; `/ttdp streams` shows `rateFactor 1.3`, `rateStart`, `rateEnd` on the `TTDProbe` target row, `rateFactor 1` on the `TTDProbe2` row and on the player row; after `lustend`, `rateEnd` is the end. With no real lust the estimator may drop it (`drops 1`, `rateFactor 1`): report it |
| 10a | With the hints of step 10 or 11 set, target a friendly unit (a party member, a friendly NPC), `/ttdp streams`; then a hostile mob again | friendly: the `TTDProbe` target row has `rateFactor 1` and no `executePct`; back on a mob: the hints are back (`executeFactor` as learned before) |
| 11 | `/ttdp below 20` and fight two or three mobs to death | `executePct 20` on the `TTDProbe` target row only; after a mob falls 5% below 20, `executeFactor` moves away from 1 (learned) |
| 12 | `/ttdp pause`, wait, `/ttdp resume` | `paused`; LibHiddenValues' target health source not fed (`/ttdp stats` or LHVProbe's sources line); after resume `priming` for LibHiddenValues and the TTD state back to `live` or `unknown` |
| 13 | `/ttdp stats` during a fight | report LibHiddenValues' µs (8 bars for a 1% watch) and the driver's µs per frame |
| 14 | `/ttdp release` | no rows; LibHiddenValues' health sources for player and target gone (0 handles) |
| 15 | A dungeon if at hand: steps 3 and 5 on a pack and a boss | as in the open world; report whether the death shows as `gone` |
| 15a | Optional, the release form: build `tools/libtimetodie/package.sh`, put its `LibTimeToDie` folder in place of the link, untick **LibHiddenValues**, restart the client, `/ttdp`, then steps 2-3 | as with both addons: LibHiddenValues runs from the bundled copy (its minor shows), no Lua error |
| 16 | `/ttdp copy`, paste back | |

Also report any Lua error that names LibTimeToDie, LibHiddenValues or the probe, and set the CVar back to "0".
