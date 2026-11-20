# LibHiddenValues stages 0-1: in-game test plan

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
| 1 | Log in, type `/lhvp` right away (again after a second if health says `pending`) | version `LibHiddenValues-1.0` minor 1, 32 bars made, health `ready` and power `ready`, the other kinds `unavailable (unproven)`. Report the verdict the login self-test gave: `ready` or `unavailable (selftest)`. If unavailable: run `/lhvp selftest` and report its lines; a PASS there (the kinds `ready` after it) means the login run was upset by the loading screen, not a broken mechanism |
| 2 | `/lhvp selftest` | three edge lines (25, 50, 75%) with changes = firings and `ok`, then `selftest PASS: curves ok, max lag 0 frames` (these lines are the library's own, passed through unchanged) |
| 3 | Target a mob at full health, `/lhvp watch health target 20 50 80` | the watch is `priming`, then within a few frames band 80-100, dir 0, q 2 |
| 4 | `/lhvp watch health player 50` and `/lhvp watch power player 30 mana` (or `energy`: your class's type; the word is required) | a first band for each, dir 0. Without the type word the watch is refused with `bad-spec: power required ...`. A Druid: shift forms; each watch keeps its own type (report what an energy watch says in caster form). `rage` is `unavailable` and stays silent: not proven yet |
| 5 | Fight the mob to death | a health target line each time it falls past 80, 50 and 20 (dir -1; a big hit over two edges is one line), in order; at its death unknown (`gone`) if the client tells the death plainly; if not, the band just stays at 0-20 (report which) |
| 6 | Change target to another mob mid-fight, then clear the target | unknown (`priming`) then the new mob's band with dir 0; with no target unknown (`gone`) |
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
