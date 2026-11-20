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
| 1 | Log in, type `/lhv` | three lines: version and bars (32 made), the unproven kinds, `health ready; power ready` |
| 2 | `/lhv selftest` | three `selftest edge` lines with changes = firings and `ok`, then `selftest PASS: curves ok, max lag 0 frames` |
| 3 | Target a mob at full health, `/lhv watch health target 20 50 80` | `watching health target: priming`, then within a few frames `health target 80-100 dir 0 q 2` |
| 4 | `/lhv watch health player 50` and `/lhv watch power player 30 60` (your displayed power) | a first band for each, `dir 0`. As a Druid in bear form the power watch prints `watching power player: unavailable` and stays silent until cat or caster form: rage is not proven yet |
| 5 | Fight the mob to death | a `health target` line each time it falls past 80, 50 and 20 (`dir -1`; a big hit over two lines is one line), in order; at its death `health target unknown (gone)` if the client tells the death plainly; if not, the band just stays at 0-20 (report which) |
| 6 | Change target to another mob mid-fight, then clear the target | `unknown (priming)` then the new mob's band with `dir 0`; with no target `unknown (gone)` |
| 7 | Spend and regain power, take a hit and heal | power and player health lines both ways (`dir 1` on regen or a heal) |
| 8 | `/lhv stats` | `bars N, X us per frame (peak Y), ... firings/s, desyncs 0, level 0`, one line per watch. Report X and Y |
| 9 | Press Alt+Z (hide the UI), take a hit or spend power, Alt+Z again | report whether lines kept coming while the UI was hidden (the root sits under the UI; unprobed) |
| 10 | `/reload` in combat, then `/lhv watch health target 20 50 80` again | `pending` or `priming` for a moment, then live bands; no Lua error |
| 11 | `/lhv off`, then `/lhv` | `unavailable (off)` for health and power, every watch `unknown (unavailable)`; `/lhv on` brings them back after the self-test |
| 12 | `/lhv watch off`, `/lhv stats` | `bars 0` |
| 13 | A dungeon, if one is at hand: steps 3 to 5 on a pack and a boss | as in the open world |
| 14 | `/lhv copy`, Ctrl+A, Ctrl+C, paste back | |

Also report any Lua error that names LibHiddenValues, and set the CVar back to "0".
