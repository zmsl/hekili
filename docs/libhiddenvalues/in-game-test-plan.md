# LibHiddenValues stages 0-1: in-game test plan

For the owner, one session on the live client. About 15 minutes. Everything the library prints also goes into
`/lhv copy`: paste that box back at the end.

## Setup

1. Make sure the client sees the folder: `scripts/Link-Addons.ps1` links every `src/<Addon>` that has `<Addon>.toc`,
   so run it once more, then restart the client fully (a reload does not pick up a new folder).
2. At the character screen, AddOns: tick **LibHiddenValues**. Leave everything else as usual. It runs on its own: no
   other addon needs it.
3. Before the first test, out of combat, force the dungeon conditions, and undo it at the end (also out of combat):
   `/run C_CVar.SetCVar("addonMapRestrictionsForced", "1")` (end: the same with `"0"`).

## Steps and what to report

| # | Do | Expect |
|---|---|---|
| 1 | Log in, type `/lhv` right away (again after a second if it says `pending`) | three lines: version and bars (32 made), the unproven kinds, `health ready; power ready`. Report the verdict the login self-test gave: `ready` or `unavailable (selftest)`. If unavailable: run `/lhv selftest` and report its lines; a PASS there (the kinds are `ready` after it) means the login run was upset by the loading screen, not a broken mechanism |
| 2 | `/lhv selftest` | three `selftest edge` lines with changes = firings and `ok`, then `selftest PASS: curves ok, max lag 0 frames` |
| 3 | Target a mob at full health, `/lhv watch health target 20 50 80` | `watching health target: priming`, then within a few frames `health target 80-100 dir 0 q 2` |
| 4 | `/lhv watch health player 50` and `/lhv watch power player 30 60 mana` (or `energy`: your class's type; the word is required) | a first band for each, `dir 0`. Without the type word the watch prints `bad-spec: power required ...`. A Druid: shift forms; each watch keeps its own type (report what an energy watch says in caster form). `rage` prints `unavailable` and stays silent: not proven yet |
| 5 | Fight the mob to death | a `health target` line each time it falls past 80, 50 and 20 (`dir -1`; a big hit over two lines is one line), in order; at its death `health target unknown (gone)` if the client tells the death plainly; if not, the band just stays at 0-20 (report which) |
| 6 | Change target to another mob mid-fight, then clear the target | `unknown (priming)` then the new mob's band with `dir 0`; with no target `unknown (gone)` |
| 7 | Spend and regain power, take a hit and heal | power and player health lines both ways (`dir 1` on regen or a heal) |
| 8 | `/lhv stats` | `bars N, X us per frame (peak Y), ... firings/s, desyncs 0, level 0`, one line per watch. Report X and Y |
| 9 | Press Alt+Z (hide the UI), take a hit or spend power, Alt+Z again, then cross a threshold (a hit past 50% or a spend past 30/60) | report whether lines kept coming while the UI was hidden (the root sits under the UI; unprobed), and whether the crossing after showing the UI again has the right `dir` (wrong `dir`: inverted; no line: stale) |
| 9b | With `/lhv watch health player 50` live: change the UI scale (Options, UI Scale), then resize the game window (or switch windowed/fullscreen); after each, in a fight, take a hit past 50% and heal back over it | after each change `health player unknown (priming)` then a band with `dir 0` (the library re-primes on a re-layout); the crossings after it `dir -1` down and `dir 1` up. Report any line with the wrong `dir` and whether the priming lines came |
| 9c | `/run LibStub("LibHiddenValues-1.0").root:SetParent(nil)`, `/lhv watch off`, the watches of steps 3 and 4 again (the re-parent may re-lay out the bars), then step 9 once more | the same report for a root with no parent. Then `/reload`: the root goes back under the UI |
| 10 | `/reload` in combat, then `/lhv watch health target 20 50 80` again | `pending` or `priming` for a moment, then live bands; no Lua error |
| 11 | `/lhv off`, then `/lhv`, then `/lhv on` | `unavailable (off)` for health and power, every watch `unknown (unavailable)`; `/lhv on` prints `on: self-test running ...`, the `selftest` lines, and the watches come back (`/lhv` says `ready`) |
| 12 | `/lhv watch off`, `/lhv stats` | `bars 0` |
| 13 | A dungeon, if one is at hand: steps 3 to 5 on a pack and a boss | as in the open world; after the loading screen a live player watch re-primes (`unknown (priming)`, then a band) |
| 14 | `/lhv copy`, Ctrl+A, Ctrl+C, paste back | |

Also report any Lua error that names LibHiddenValues, and set the CVar back to "0".
