# LibHiddenValues: in-game test plan (stages 0-1, CDM-1, 3, lane C1, the fix lane)

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
| 1 | Log in, type `/lhvp` right away (again after a second if health says `pending`) | version `LibHiddenValues-1.0` minor 7 or later, 32 bars made (when LHVProbe shows `GetPool`), health `ready` and power `ready`, the other kinds `unavailable (unproven)`. Report the verdict the login self-test gave: `ready` or `unavailable (selftest)`. If unavailable: run `/lhvp selftest` and report its lines; a PASS there (the kinds `ready` after it) means the login run was upset by the loading screen, not a broken mechanism |
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
| A2 | `/lhvp watch aura target <Lacerate> stacks max 5`, `/lhvp watch aura target <Lacerate> left 3 6`, `/lhvp watch aura target <Lacerate> up`; fight a mob, stack it to 5, let it fall off | up 0 then 1; stacks 0-2 at 1 (no count shown: 0 or 1), then 2-3 .. 5-5 one line per cast (dir 1); left 6-inf, then 3-6 and 0-3 (dir -1) near 6 s and 3 s left, back up on each refresh; at the expiry stacks 0-1 and left 0-3 (dir -1), up 0 |
| A3 | Swap targets mid-fight (a mob without the debuff, then back) | minor 7 or later: unknown (`gone`) right after each swap; on the other mob stacks and left the lowest band and up 0 once its auras arrive; on swap-back the old values once the bar lights, with no `priming` line and no 0 or lowest band before them (minor 6 and before: the lowest band at once) |
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
| S1 | `/lhvp` | minor 3 or later; health and power `ready` |
| S2 | `/lhvp watch power player 30` (no type word), `/lhvp watch power player precision exact mana` and `/lhvp watch aura target <any spell ID> left` (no edges) | each refused with the library's English message (`A power watch needs its power type ...`, `The precision must be "point" or nil.`, `The spec needs edges ... (aura stacks: edges or max; aura seconds: edges).`), not a code |
| S3 | `/lhvp watch health player step 1`, `/lhvp watch power player step 1 mana` | each a 1% band (e.g. `61-62`), dir 0 first; `/lhvp stats`: one source line per watch, `mode gray`, 8 bars each |
| S4 | Spend mana in steps (casts), take a hit, heal, out of combat and then in a fight | the mana and health bands follow every 1% change, a big spend is one line; `/lhvp stats`: desyncs 0 (splits may be above 0: a held frame, never a wrong band) |
| S5 | `/lhvp watch power player points 300 500 mana` (pick points under your mana max) | the band in mana points (`300-500`, `500-<max>`, `0-300`); spend across 500 and 300 and regen back: a line at each crossing, at the point (check against the mana shown on your frame) |
| S6 | Still with the step 1 mana watch of S3 live: `/lhvp stats`; then bring mana to exactly a point of S5 (e.g. 500) and to one point below it (499), and the same for a point that is a whole percent of your max | `point bars` counts only points off the 1% grid of your max (a point that is a whole percent of the max costs none); at the point the band starts at it (`500-...`), one below it ends at it (`...-500`), for both kinds of point |
| S7 | `/lhvp watch power player precision point mana` | the panel shows `exact <mana>/1` (step 2 or 3 above 3175 mana) matching your mana frame to the point; `/lhvp stats`: the mana source `mode ring`, 57 bars at most, the S3 and S5 watches still right (answered from the exact value). At a max over 3175 only: also `/lhvp watch power player points <a point that is not a multiple of the step> mana`, sit on it and one point below: the band flips exactly at the point and `/lhvp stats` shows 1 point bar on the ring source. Not reachable at 2239 mana: skip, the offline tests cover it. |
| S8 | With S7 live: spend, regenerate (one-point ticks), in combat for a minute | exact follows every point; desyncs 0; report the µs per frame (`/lhvp stats`); note `splits` from `/lhvp stats` before and after and report it (0 expected). Also report, with both lines copied, any spend or gain that shows as two exact lines one frame apart where one of the two changes is an exact multiple of 50 x step and the other a small move (often against the direction of the spend): the accepted split case, it decides whether a wider hold is needed. |
| S9 | Change your max mana (a buff, a talent, or gear with intellect), or shapeshift and back | after `UNIT_MAXPOWER` the points and precision watches go unknown briefly, then right for the new max |
| S10 | `/lhvp watch off`; bear form: `/lhvp watch power player precision point rage`; cat form: `... precision point energy`; for each, also `... points 40 rage` (or `energy`) and sit exactly at 40, then at 39 | rage and energy (max 100): `mode gray`, 8 bars, exact to the point, also exactly at 40 and at 39 (the exact value matches your frame; the points band flips between 39 and 40) |
| S11 | `/lhvp watch off`, `/lhvp stats` | 0 bars, 0 pushes/s and 0.0 µs per frame (the averages fall to 0 when nothing is fed) |
| S12 | `/lhvp watch off`, then A1 to A3 of the aura section again on this minor | as there (the aura kind runs on the stage 3 core now) |
| S13 | `/lhvp copy`, paste back | |

Report the µs per frame of S3, S7 and S8, every desync, and any wrong band (with the mana or health your frame showed).

Stage CDM-2 (the managed layout, Mode B) is gone: it moved to Hekili's integration lane C5.

## Lane C1: up from all four viewers, watch by entry, truths, the position set beside the ring (minor 5 or later)

Map lockdown on as in Setup. LHVProbe needs these before the run (each calls
the public API only; the existing aura commands stay as they are):

- `/lhvp watch aura <unit> cooldown <cooldownID> <up|stacks|left> [edges...] [max N]`: `LHV:Watch(OWNER, { kind =
  "aura", unit = <unit>, cooldown = <cooldownID>, what = <what>, edges = <edges or nil>, max = <N or nil> }, sink)`,
  the same sink and panel line as `watch aura`, its tag `cd=<cooldownID>` instead of `spell=`.
- `/lhvp aura <unit> cooldown <cooldownID> <what> [edges...] [max N]`: `LHV:IsAvailable("aura", <that spec>)`.
- `/lhvp entries <spellID>`: `LHV:GetAuraEntries(spellID)`, one line per row (`cooldownID`, `spellID`,
  `overrideSpellID`, `overrideTooltipSpellID`, the `linkedSpellIDs` joined, `hasAura`, `selfAura`, `category`,
  `placement` or `none`), then `read`.
- `/lhvp cdm`: also print each row's `cooldown` (nil for a spell watch); `placement` may now read `essential` or
  `utility`.

| # | Do | Expect (PASS) |
|---|---|---|
| E1 | `/lhvp` | minor 5 or later |
| E2 | Cooldown Settings: an ability whose debuff its Essential icon shows (a Druid: Faerie Fire, Demoralizing Roar); its aura not in Tracked Buffs or Bars. `/lhvp entries <its spellID>` | one row per entry naming the spell, the Essential one with `placement essential` and `category 0` |
| E3 | `/lhvp aura target <spellID> up`, `... stacks max 3`, `... left 3` | `up` `ready`; `stacks` and `left` `unavailable (cdm-cooldown-only)` |
| E4 | `/lhvp watch aura target cooldown <the Essential cooldownID> up`; fight a mob, cast it, let it fall off; also in combat | up 0, then 1 when applied (within a frame or two of the icon showing it), 0 when it ends; report any `gone` in combat |
| E5 | `/lhvp cdm` in and out of combat | the row: `cooldown` = the ID, `cd=` the same, `essential`, `up` true/false following the icon |
| E6 | Out of combat: `/run local L=LibStub("LibHiddenValues-1.0") L.stVerdict=false L.capChanged()` (pretends the bar self-test failed), then `/lhvp`, `/lhvp aura target <spellID> up`, `/lhvp aura target <a Tracked Bar aura> stacks max 5` | the aura kind `unavailable (selftest)`; the `up` spec `ready` and the E4 watch still following; `stacks` `unavailable (selftest)`. Then `/lhvp selftest` (PASS puts everything back) |
| E7 | A stacking aura in Tracked Bars (Lacerate): `/lhvp watch aura target <Lacerate> stacks max 5`; apply 1 stack, then 2 | absent 0-1; at 1 stack 0-2 (never 1-2); at 2 stacks 2-3 |
| E8 | A buff of yours that the same entry can also show on the target (or any entry you saw show the target's aura): `/lhvp watch aura player <spellID> up` while the item shows the target's | `gone` (unknown) while the item shows the target's aura, not 0 |
| E9 | Probe fact (Q3), in combat with an aura shown on Essential, Utility and Tracked Buffs: `/run for _,n in ipairs({"Essential","Utility","BuffIcon","BuffBar"}) do for i in _G[n.."CooldownViewer"].itemFramePool:EnumerateActive() do local u=rawget(i,"auraDataUnit") if issecretvalue(u) then print(n,"SECRET") elseif u then print(n,u) end end end` (252 characters: the secrecy test comes before any comparison) | report each line: `player`/`target`, or `SECRET` (a secret unit makes those watches unknown) |
| E10 | A mana class with a max over 3175 (6400: step 3): `/lhvp watch off`, `/lhvp watch power player precision point mana`, `/lhvp watch power player step 1 mana`, `/lhvp stats`; spend and regen through a few percent | 65 bars on the source (57 + 8); every step line one 1% cell (`lo + 1 == hi`), never two; the precision line to the step (3). `/lhvp watch off` the step one only (or `watch off` and the precision one again): 57 bars. Desyncs 0 |
| E11 | Swap-back (fix round 1, I2): Demoralizing Roar (no range check) on Essential only. `/lhvp watch aura target cooldown <its cooldownID> up`. Roar mob A (debuffed), target mob B (no Roar), then A again within the debuff; wait 5 s without casting; then Roar again | on A 1; on B `gone` or 0 (0 only after B's auras change); back on A `gone` (never 0) until A's auras change or the icon lights, then 1. Report the line at each step and whether the Essential icon showed the debuff on the swap back |
| E12 | Facts (I4): `/lhvp entries <spellID>` for an ability with an Essential entry that shows no aura (`hasAura` false) and one that does (`hasAura` true; Demoralizing Roar). `/lhvp watch aura target cooldown <the hasAura false ID> up`, cast it on a mob | report both rows' `hasAura` and `selfAura`; whether the `hasAura` false item ever reads 1 (its icon ever showing an aura) |
| E13 | Catalogue re-reads (M2): out of combat, one Essential watch on (E4), `/lhvp cdm`, note `reads=`; cast abilities on Essential and Utility for one minute; `/lhvp cdm` again. Repeat on minor 4 (the lane-CDM-2 LHVProbe with its library) | report both `reads=` deltas per minute. Many more on minor 5 than minor 4: the Essential/Utility RefreshData hook re-reads the catalogue per cooldown event (the fix would read it only on catalogue events) |
| E14 | `/lhvp copy`, paste back; set the CVar back to "0" | |

## Fix lane: the owner's findings of 2026-11-21 (minor 7)

About 10 minutes, a Druid. Map lockdown on as in Setup (LHVProbe 0.6.0 or later; a `/reload` is enough: no new
file). `/lhvp watch off` between the groups.

| # | Do | Expect (PASS) |
|---|---|---|
| F1 | `/lhvp` | minor 7 |
| F2 | Faerie Fire (or another debuff of yours) in Tracked Buffs (an icon), a Tracked Bar debuff too if you have one. `/lhvp watch aura target cooldown <the icon's cooldownID> up` (and `... <the bar's> left 3`). Debuff mobs A and C, leave B clean; target A, then C (debuffed to debuffed: the case the owner's run saw read 0), then B, then A, several rounds | after every swap the watch reads unknown (`?`, `gone`) first; on A and C then 1 (the bar: its seconds band), never 0 (or 0-3) between the swap and the 1; on B 0 once its auras arrive (the run saw ~2 s on the Essential watch: every target watch now waits that long on a mob without the aura). Report the line times of each swap |
| F3 | With the F2 watch live, clear the target (Escape), wait 5 s, target A again | unknown while no target (it may stay unknown until a target's auras arrive), then as in F2 |
| F4 | `/lhvp watch off`, `/lhvp watch power player precision point mana`; `/lhvp stats` (note desyncs and splits); one minute regenerating out of combat, then one minute in a fight casting; `/lhvp stats` again | desyncs unchanged (0 new: the run before this lane saw 4 in 2.5 min); splits rising is fine (every mana change is now held one frame until the next frame confirms it; a split is a change that moved during its hold). Report both deltas and the µs per frame. Report, with both lines copied, any exact line showing a value your mana never showed (50 off its neighbours, or a value partway through a regen tick): there should be none |
| F5 | Cat form: `/lhvp watch power player precision point energy`; `/lhvp stats`; spend and regenerate for a minute; `/lhvp stats` again. Then `/lhvp watch off`, `/lhvp watch health target step 1` and kill a mob as fast as you can | energy: every change is held one frame until the next confirms it, as mana's (fix round 3), so each exact line comes a frame later and shows only values your energy frame showed (a spend's split read, 84 for 85, is gone); desyncs 0 new, splits may rise. Value lines now come at least two frames apart, so back and forth over 4 frames (the 35, 36, 35, 36 of the run before) cannot show: an energy flickering 35/36 on every frame reads its held value (35) until it settles, with no desync. Report, with the energy your frame showed, any exact line with a value your energy never showed. Health: cells in order, each a frame later; report any unknown (`?`) mid-fight with the desyncs delta (a cell changing on every frame for six frames is never confirmed: the source primes again) |
| F6 | `/lhvp copy`, paste back; set the CVar back to "0" | |
