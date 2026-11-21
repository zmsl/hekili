# LibHiddenValues: in-game test plan (stages 0-1, stage 3)

For the owner, one session on the live client. About 15 minutes. The library prints nothing and has no command of its
own: every test runs through LHVProbe, its reference consumer, which calls the public API and prints what it gets.
Everything LHVProbe prints also goes into `/lhvp copy`: paste that box back at the end.

The expectations below are facts (a band, a direction, a state, a count); LHVProbe's exact wording is its own.

## Setup

1. Make sure the client sees the library folder: `scripts/Link-Addons.ps1` links every `src/<Addon>` that has
   `<Addon>.toc`, so run it once more. LHVProbe sits in the AddOns folder itself. Then restart the client fully (a
   reload does not pick up a new folder).
2. At the character screen, AddOns: tick **LibHiddenValues** and **LHVProbe**. Leave everything else as usual. The
   library needs no other addon.
3. Before the first test, out of combat, force the dungeon conditions, and undo it at the end (also out of combat):
   `/run C_CVar.SetCVar("addonMapRestrictionsForced", "1")` (end: the same with `"0"`).

## Steps and what to report

| # | Do | Expect |
|---|---|---|
| 1 | Log in, type `/lhvp` right away (again after a second if health says `pending`) | version `LibHiddenValues-1.0` minor 3, 32 bars made (when LHVProbe shows `GetPool`), health `ready` and power `ready`, the other kinds `unavailable (unproven)`. Report the verdict the login self-test gave: `ready` or `unavailable (selftest)`. If unavailable: run `/lhvp selftest` and report its lines; a PASS there (the kinds `ready` after it) means the login run was upset by the loading screen, not a broken mechanism |
| 2 | `/lhvp selftest` | three edge lines (25, 50, 75%) with changes = firings and `ok`, `selftest prime: firings in the settle window 1, after it 0: ok`, then `selftest PASS: curves ok, max lag 0 frames` (these lines are the library's own, passed through unchanged) |
| 3 | Target a mob at full health, `/lhvp watch health target 20 50 80` | the watch is `priming`, then within a few frames band 80-100, dir 0, q 2, as its first band (no 0-20 line before it) |
| 4 | `/lhvp watch health player 50` and `/lhvp watch power player 30 mana` (or `energy`: your class's type; the word is required) | a first band for each, dir 0. Without the type word the watch is refused with `A power watch needs its power type (an Enum.PowerType number).`. A Druid: shift forms; each watch keeps its own type (report what an energy watch says in caster form). A rage watch (`/lhvp watch power player 30 rage`, bear form): out of combat at 0 its first band is 0-30, dir 0 (known, not unknown), then crossings as rage builds and decays: the library's first rage run |
| 5 | Fight the mob to death | a health target line each time it falls past 80, 50 and 20 (dir -1; a big hit over two edges is one line), in order; at its death unknown (`gone`) if the client tells the death plainly; if not, the band just stays at 0-20 (report which) |
| 6 | Change target to another mob mid-fight, then clear the target | unknown (`priming`) then the new mob's band with dir 0 as the first band (no 0-20 line before it); with no target unknown (`gone`) |
| 7 | Spend and regain power, take a hit and heal | power and player health lines both ways (dir 1 on regen or a heal) |
| 8 | `/lhvp stats` | bars in use, µs per frame (average and peak), pushes and firings per second, desyncs 0, level 0, and one line per watched source (handles, bars, fed). Report the two µs numbers |
| 9 | Press Alt+Z (hide the UI), take a hit or spend power, Alt+Z again, then cross a threshold (a hit past 50% or a spend past 30%) | report whether lines kept coming while the UI was hidden (the library's root sits under the UI; unprobed), and whether the crossing after showing the UI again has the right dir (wrong dir: inverted; no line: stale) |
| 9b | With `/lhvp watch health player 50` live: change the UI scale (Options, UI Scale), then resize the game window (or switch windowed/fullscreen); after each, in a fight, take a hit past 50% and heal back over it | after each change the player watch goes unknown (`priming`) then a band with dir 0 (the library re-primes on a re-layout); the crossings after it dir -1 down and dir 1 up. Report any line with the wrong dir and whether the priming lines came |
| 9c | `/run LibStub("LibHiddenValues-1.0").root:SetParent(nil)`, `/lhvp watch off`, the watches of steps 3 and 4 again (the re-parent may re-lay out the bars), then step 9 once more | the same report for a root with no parent. Then `/reload`: the root goes back under the UI |
| 10 | `/reload` in combat, then `/lhvp watch health target 20 50 80` again | `pending` or `priming` for a moment, then live bands; no Lua error |
| 11 | `/lhvp off`, then `/lhvp`, then `/lhvp on` | after `off`: health and power `unavailable (off)`, every watch unknown (`unavailable`); after `on`: the self-test lines (it runs again, also after a failed one) and the watches come back (`/lhvp` says `ready`) |
| 12 | `/lhvp watch off`, `/lhvp stats` | 0 bars in use, no source lines |
| 13 | A dungeon, if one is at hand: steps 3 to 5 on a pack and a boss | as in the open world; after the loading screen a live player watch re-primes (unknown `priming`, then a band) |
| 14 | `/lhvp copy`, Ctrl+A, Ctrl+C, paste back | |

Also report any Lua error that names LibHiddenValues or LHVProbe, and set the CVar back to "0".

## Stage CDM-1: auras from the Cooldown Manager

LHVProbe 0.2.0 or later has the aura commands: `/lhvp watch aura <player|target> <spellID> <up|stacks|left>
[edges...] [max N]` calling `Watch` with `{ kind = "aura", ... }`, a line per sink call (band, dir, q) and per
`OnCapability` call (with the handle's spell when the 4th argument is set), `/lhvp aura <unit> <spellID> <what>` printing
`IsAvailable("aura", spec)`, and `/lhvp cdm` printing `GetAuraSources()` (each row, then off, read, texts, values,
refused, reads). A class with a stacking aura and a timed debuff helps (a Druid: Lacerate stacks and Rake or Moonfire).

| # | Do | Expect |
|---|---|---|
| A1 | Cooldown Settings: put a stacking aura (Lacerate) in Tracked Bars, a buff in Tracked Buffs (icons), leave a third aura out. `/lhvp aura` for each with `up`, `stacks`, `left` | bar: all `ready`; icon: `up` and `stacks` `ready`, `left` `unavailable (cdm-icon-only)`; the third `cdm-not-tracked` (or `not-in-cdm` if no entry names it) |
| A2 | `/lhvp watch aura target <Lacerate> stacks max 5`, `/lhvp watch aura target <Lacerate> left 3 6`, `/lhvp watch aura target <Lacerate> up`; fight a mob, stack it to 5, let it fall off | up 0 then 1; stacks 1-2 .. 5-5 one line per cast (dir 1); left 6-inf, then 3-6 and 0-3 (dir -1) near 6 s and 3 s left, back up on each refresh; at the expiry stacks 0-1 and left 0-3 (dir -1), up 0 |
| A3 | Swap targets mid-fight (a mob without the debuff, then back) | stacks and left the lowest band and up 0 on the other mob; the old values again within a frame or two on swap-back, with no `priming` line |
| A4 | `/lhvp cdm` in and after combat | texts and values rising, refused 0; report `read` and the placement of each row |
| A5 | Cooldown Settings: move the aura from Tracked Bars to Tracked Buffs, then remove it, then put it back (out of combat) | `OnCapability` lines per handle: `left` to `cdm-icon-only`, all to `cdm-not-tracked`, then `ready` again |
| A6 | Options: switch the Cooldown Manager off, then on | `aura unavailable (cdm-off)` (kind and each handle), every aura watch unknown; on again: `ready`, bands back after the next application |
| A7 | Edit Mode open with a watch live; then Alt+Z | unknown while open / hidden (state `gone`), values back after |
| A8 | A fight with several auras up at once (a full aura refresh in combat: a resurrect, an aura-heavy pull), then `/lhvp cdm` | the watches keep following; report any watch stuck `gone` in combat and whether it recovered after combat |
| A9 | `/reload` in combat, then the watches again | `pending` until combat ends, then `ready` |

Report the ms between a cast and its stack line (the probes saw 15-50 ms), and any Lua error naming LibHiddenValues.

## Stage 3: error codes, position, points, point precision

About 15 minutes, a Druid (or any mana user; the energy and rage steps need a Druid). Setup as above (LHVProbe 0.3.0;
a `/reload` is enough when only files changed, a full restart if a folder is new), the map lockdown CVar forced first
and reset at the end. Start in caster form, out of combat; `/lhvp watch off` between the groups.

| # | Do | Expect (PASS) |
|---|---|---|
| S1 | `/lhvp` | minor 3; health and power `ready` |
| S2 | `/lhvp watch power player 30` (no type word), `/lhvp watch power player precision exact mana` and `/lhvp watch aura target <any spell ID> left` (no edges) | each refused with the library's English message (`A power watch needs its power type ...`, `The precision must be "point" or nil.`, `The spec needs edges ... (aura stacks: edges or max; aura seconds: edges).`), not a code |
| S3 | `/lhvp watch health player step 1`, `/lhvp watch power player step 1 mana` | each a 1% band (e.g. `61-62`), dir 0 first; `/lhvp stats`: one source line per watch, `mode gray`, 8 bars each |
| S4 | Spend mana in steps (casts), take a hit, heal, out of combat and then in a fight | the mana and health bands follow every 1% change, a big spend is one line; `/lhvp stats`: desyncs 0 (splits may be above 0: a held frame, never a wrong band) |
| S5 | `/lhvp watch power player points 300 500 mana` (pick points under your mana max) | the band in mana points (`300-500`, `500-<max>`, `0-300`); spend across 500 and 300 and regen back: a line at each crossing, at the point (check against the mana shown on your frame) |
| S6 | Still with the step 1 mana watch of S3 live: `/lhvp stats`; then bring mana to exactly a point of S5 (e.g. 500) and to one point below it (499), and the same for a point that is a whole percent of your max | `point bars` counts only points off the 1% grid of your max (a point that is a whole percent of the max costs none); at the point the band starts at it (`500-...`), one below it ends at it (`...-500`), for both kinds of point |
| S7 | `/lhvp watch power player precision point mana` | the panel shows `exact <mana>/1` (step 2 or 3 above 3175 mana) matching your mana frame to the point; `/lhvp stats`: the mana source `mode ring`, 57 bars at most, the S3 and S5 watches still right (answered from the exact value). At a max over 3175 only: also `/lhvp watch power player points <a point that is not a multiple of the step> mana`, sit on it and one point below: the band flips exactly at the point and `/lhvp stats` shows 1 point bar on the ring source. Not reachable at 2239 mana: skip, the offline tests cover it. |
| S8 | With S7 live: spend, regenerate (one-point ticks), in combat for a minute | exact follows every point; desyncs 0; report the µs per frame (`/lhvp stats`) |
| S9 | Change your max mana (a buff, a talent, or gear with intellect), or shapeshift and back | after `UNIT_MAXPOWER` the points and precision watches go unknown briefly, then right for the new max |
| S10 | `/lhvp watch off`; bear form: `/lhvp watch power player precision point rage`; cat form: `... precision point energy`; for each, also `... points 40 rage` (or `energy`) and sit exactly at 40, then at 39 | rage and energy (max 100): `mode gray`, 8 bars, exact to the point, also exactly at 40 and at 39 (the exact value matches your frame; the points band flips between 39 and 40) |
| S11 | `/lhvp watch off`, `/lhvp stats` | 0 bars, 0 pushes/s and 0.0 µs per frame (the averages fall to 0 when nothing is fed) |
| S12 | `/lhvp watch off`, then A1 to A3 of the aura section again on this minor | as there (the aura kind runs on the stage 3 core now) |
| S13 | `/lhvp copy`, paste back | |

Report the µs per frame of S3, S7 and S8, every desync, and any wrong band (with the mana or health your frame showed).
