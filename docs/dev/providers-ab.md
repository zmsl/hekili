# Providers A/B: the damage meter and the Cooldown Manager, measured (2026-10-24)

Measured, not gated (providers spec decision 86). The owner decides whether a provider becomes default.

The design is `docs/superpowers/specs/2026-10-23-providers-design.md` (BUILT; its "Amended 2026-10-24 (Task 8)" notes
record what differs from the design). Every number here comes from the harness on branch `forever-providers`
(`make gate-ab` at 8599f0437, plus `make gate AB_ARM=lagged`), not from the game: the in-game checks are the
launch-day probes in `docs/dev/ingame-ledger.md` (DM-P, DM-M, CDM-T, CDM-E, CDM-R, CDM-O, CDM-P and the spec's §6 rows).

## The arms

| Arm (`HEKILI_AB`) | Providers | Observer shapes | Run by |
| --- | --- | --- | --- |
| `default` | Outcomes "default", presence "router" without the viewer leaf | today's stream | `make gate`, `make gate-ab` |
| `meter` | Outcomes "meter" | the meter's events (a group 0-11 ms after each hitting swing of the group, 3-14 ms after a spell, 1-2 ms after a tick, type 7 at a hit on a group member) and the hit row on us 0.48 ±0.09 s after its taken group | `make gate-ab` |
| `viewer` | presence "router" with the viewer leaf | `@viewer` events 3-5 ms after each aura edge of ours | `make gate-ab` |
| `lagged` | the Default providers | the meter arm's 0.48 s taken lead only | by hand |

The meter arm changes two things at once: the provider, and the rows on us arriving 0.48 s late (DM §3's measured lead,
which `EnemyHitAt` needs). So the meter's baseline is `lagged`, not `default`: the two differ only by the leaf and its
assumptions. Every detection cell and every solo and group fights gate is byte-identical between `default` and `lagged`;
the lead moves only the onus lines and the loops. The plan's "second meter arm with `HEKILI_TAKENLAG=1`" became this
`lagged` arm.

**Seed noise.** A 20-fight loop line moves with the seeds about as much as the meter moves it: Fury L60 flicker reads
1.74, 2.03, 1.97, 1.34 and 1.80/min on five 20-fight seed sets of the `lagged` arm. The loop table uses the gate's
seeds 1-20; its reading gives the Fury probe's 60- and 100-fight figures where the probe ran them.

## Meter arm: the detection cells (kinds x bands)

Band means over the gated cells of `.ab/meter.tsv` against `.ab/lagged.tsv` (byte-identical to the default arm's
cells). `rageErr` is the mean size of the signed error; lower is better for rageErr, false100, leak100, lostDiff and
wash. `lostDiff` uses the redefinition (below).

**solo (22 cells)**

| Metric | default (= lagged) | meter | Difference | cells better / worse |
| --- | --- | --- | --- | --- |
| recall | 0.970 | 0.970 | +0.000 | 0/0 |
| melee | 0.976 | 0.977 | +0.001 | 1/0 |
| melee2 | 0.975 | 0.975 | +0.000 | 0/0 |
| rageErr | 8.523 | 8.577 | +0.055 | 3/3 |
| false100 | 2.332 | 2.332 | +0.000 | 0/0 |
| leak100 | 2.264 | 2.264 | +0.000 | 0/0 |
| staged | 0.954 | 0.954 | +0.000 | 0/0 |
| lostDiff | 0.455 | 0.455 | +0.000 | 0/0 |
| postClear | 1.000 | 1.000 | +0.000 | 0/0 |
| recovered | 0.840 | 0.840 | +0.000 | 0/0 |
| wash | 2.073 | 1.214 | -0.859 | 2/0 |

**party (24 cells)**

| Metric | default (= lagged) | meter | Difference | cells better / worse |
| --- | --- | --- | --- | --- |
| recall | 0.955 | 0.955 | -0.000 | 0/1 |
| melee | 0.905 | 0.905 | +0.000 | 1/1 |
| melee2 | 0.970 | 0.969 | -0.001 | 0/1 |
| rageErr | 9.042 | 9.083 | +0.042 | 3/4 |
| false100 | 4.108 | 4.117 | +0.008 | 0/1 |
| leak100 | 1.271 | 1.275 | +0.004 | 0/1 |
| staged | 0.945 | 0.945 | +0.000 | 0/0 |
| lostDiff | 0.208 | 0.208 | +0.000 | 0/0 |
| postClear | 0.996 | 0.996 | +0.000 | 0/0 |
| recovered | 0.464 | 0.471 | +0.007 | 4/1 |
| wash | 1.767 | 1.429 | -0.338 | 2/0 |

**busy (24 cells)**

| Metric | default (= lagged) | meter | Difference | cells better / worse |
| --- | --- | --- | --- | --- |
| recall | 0.841 | 0.842 | +0.002 | 1/0 |
| melee | 0.861 | 0.860 | -0.001 | 1/3 |
| melee2 | 0.936 | 0.936 | +0.000 | 0/0 |
| rageErr | 9.638 | 9.438 | -0.200 | 8/1 |
| false100 | 16.596 | 16.421 | -0.175 | 1/0 |
| leak100 | 1.571 | 1.558 | -0.013 | 1/0 |
| staged | 0.847 | 0.849 | +0.002 | 1/0 |
| lostDiff | 1.125 | 1.167 | +0.042 | 0/1 |
| postClear | 0.987 | 0.987 | +0.000 | 0/0 |
| recovered | 0.430 | 0.432 | +0.003 | 4/0 |
| wash | 2.329 | 1.692 | -0.637 | 1/1 |

Notable cells: busy rage error and false credit improve in 8 and 1 cells (1 and 0 worse); K10 busy melee recall
0.18 -> 0.17, K10 party recall 0.92 -> 0.91 and rage error -24.7 -> -25.7, K14f rage error -32.5 / -41.3 / -50.1 ->
-33.9 / -42.8 / -51.6 (solo / party / busy), each one floor step. `.ab/meter.tsv` records 19 detection MISS lines
(each about one floor step; with K10 busy lostDiff 7 against 6, K10 busy wash and K14f party recovered) and 7 others
(the fixture pins, the party5 oracle catch bar and three loop floors, below); the default arm's floors are unchanged
and pass.

**lostDiff, redefined** (`tests/Game/harness/metrics.lua` `M.lostDiff`):
`lostDiff = |lostEngine + assumed closes of FRAME and FLIGHT - lostTruth|`. Recovery Task 5 had defined it with every
assumed close. Under the meter every assumed close is a swing told HIT whose row the engine never paid (2221 of them:
melee-recall misses the LR judged foreign, rows after the close, avoid rows nobody paid); the default arm closes the
same swings `lost` MELEE, which `lostEngine` leaves out. Counting them charged 29 meter cells (lostDiff up to 237 in
K10 party) against floors set with nothing assumed. With the redefinition the meter arm's lostDiff equals the
default's in every cell but K10 busy (7 against 6). The default arm's values cannot move (nothing is assumed under the
Default providers): its detection suite passes unchanged (102 of 102) and no floor file changed. The drive tallies the
assumed closes by kind in its `T.Expire` wrapper.

## Meter arm: the fights gates (`solo_spec`, `group_spec`, `onus_spec`; the same cases and seeds)

`lagged` equals `default` on every line but the onus line (there the taken lead alone costs precision and
coverage, so both baselines are given). Unchanged by the Fury fix (5d78e255) and by the lostDiff
redefinition (byte-identical records).

| Case | default (= lagged) | meter | Difference |
| --- | --- | --- | --- |
| solo200 main hand right / wrong / missed | 8438 / 26 / 52 | 8444 / 22 / 50 | +6 / -4 / -2 |
| solo200 off hand right / wrong / missed | 7396 / 8 / 82 | 7395 / 5 / 86 | -1 / -3 / +4 |
| solo200 own retractions (bar 0.5 %) | 12 of 15834 | 8 of 15839 | -4 |
| solo200 lo over / est over | 0 / 91 | 0 / 86 | 0 / -5 |
| solo200 over, usability answers on (not gated) | 14 of 2400 | 25 of 2400 | +11 |
| solo200 drift over, answers off (bar 2) | 1 | 0 | -1 |
| solo damage buff: main right / over | 2871 / 15 | 2880 / 18 | +9 / +3 |
| solo form change: main right / over | 3096 / 9 | 3121 / 14 | +25 / +5 |
| party5 main / off right | 3515 / 3665 | 3512 / 3662 | -3 / -3 |
| party5 false credit net per 100 (bar 4) | 1.45 | 1.36 | -0.09 |
| party5 over / drift over | 28 / 18 | 28 / 0 | 0 / -18 |
| party5 oracle: false judged / caught (bar 60 %) | 24 / 19 | 1 / 0 (MISS, see below) | |
| party5 oracle: own retractions / lo over | 44 / 8 | 40 / 6 | -4 / -2 |
| party5 + pet main / off right | 3320 / 3385 | 3304 / 3394 | -16 / +9 |
| party5 + pet false credit net per 100 (bar 6) | 5.64 | 4.67 | -0.97 |
| party5 + pet over / drift over | 43 / 48 | 35 / 3 | -8 / -45 |
| raid, 12 on target: false wounds per 100 swings / over of 360 windows | 9.56 / 9 | 7.61 / 0 | -1.95 / -9 |
| K14p pet rows paid by our tickets per 100 (solo / party / busy) | 7.31 / 5.98 / 1.97 | 7.01 / 5.83 / 1.97 | down |
| onus "second joining" precision / coverage | 0.758 / 0.407 (lagged); 0.879 / 0.677 (default) | 0.872 / 0.578 | +0.114 / +0.171 against lagged |
| onus 2x precision / coverage (bars 0.95 / 0.80) | 0.913 / 0.690 (lagged); 0.967 / 0.893 (default, no lead) | 0.958 / 0.841 | +0.045 / +0.151 against lagged |

The party5 oracle catch bar (caught >= 60 % of the false credits the oracle judges) misses at 0 of 1: the meter
leaves about one rage-false credit for the oracle to judge (the default has 24), so the bar has nothing to measure.
The only other line that is worse is solo over with usability answers on (25 against 14 windows of 2400, not gated;
the gated drift over is 0 against 1).

## Meter arm: the leaf against the truth

Each swing's truth outcome from the stream's own rows, matched by hand and swing time (Task 3, e50ff96c; the later
fixes changed the consumer, not the leaf's 15 ms rule).

| Cell | told HIT: hit / avoided | told AVOID: avoided / hit |
| --- | --- | --- |
| K1 solo | 815 / 0 | 198 / 0 |
| K1 party | 804 / 2 | 212 / 0 |
| K1 busy | 829 / 0 | 195 / 0 |
| K10 party | 770 / 4 | 242 / 1 |
| K14p busy (our pet) | 939 / 200 | 58 / 0 |
| solo200 (oracle) | 15949 / 13 | 4427 / 3 |

**The party collision rate** (wrong HITs per 100 avoided swings, party band): K1 party 2 of 214 avoided swings
(0.9 per 100), K10 party 4 of 246 (1.6 per 100). Spec §2.2's bound, `1 - exp(-0.015 λ)`, is 0.7 % at λ = 0.5/s and
4.4 % at λ = 3/s (two partners): the harness party band is under the two-partner bound. The game's rate is DM-P.
Our own pet is the exception: in K14p busy the pet's hits made 200 of 1139 told HITs wrong (78 per 100 avoided
swings), the spec's known collision (DM-PET) at a larger rate than its λ estimate for a fast pet.

**Audit counters**, summed over each band's detection cells (the `audit` lines of `.ab/meter.tsv`):

| Band | tick HIT / AVOID | row | unknown | muted | collide | foreignByMeter | disagree | ownUnclaimed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| solo | 7528 / 1627 | 46 | 34 | 0 | 450 | 3 | 3 | 916 |
| party | 7645 / 1583 | 46 | 30 | 0 | 522 | 10 | 7 | 0 |
| busy | 7575 / 1540 | 39 | 25 | 0 | 642 | 24015 | 1415 | 52294 |

`foreignByMeter` (RowOwner's FOREIGN, count-only) was not scored row by row against the truth. In the busy band every
other source is a stranger (strangers never group), so its 24015 FOREIGN answers are rows of non-members; the proxy for
wrong ones is `disagree`, a FOREIGN row a ticket took anyway: 1415 of 24015 (5.9 %), an upper bound on its error, since
a ticket taking a row does not make the row ours. `ownUnclaimed` in busy is the 2 s white-row window's noise (it cannot
tell strangers' white rows from ours while we swing). `pins` is 0 in every detection cell: those kinds have no usability
flips at an unchanged cost. `EnemyHitAt`'s precision is the onus line above (0.958 against 0.913 lagged).

## Meter arm: the loops

20 fights, seeds 1-20: agreement with the oracle, flicker per minute, ready retracted per minute, refused for cost per
100.

D = default, L = lagged (the meter's baseline), M = meter. The viewer arm equals D on every line. The other 43 loop
lines (every caster, hunter and paladin, and the other rogue specs) are identical in all four arms.

| Line | agreement D / L / M | flicker D / L / M (floor) | retracted D / L / M | refused cost D / L / M |
| --- | --- | --- | --- | --- |
| Fury L60 (`loop_warrior_fury`) | 0.935 / 0.930 / 0.927 | 1.63 / 1.74 / 1.84 (1.8: MISS) | 0.09 / 0.19 / 0.16 (0.1: MISS in L and M) | 12.7 / 13.4 / 13.4 |
| Fury L60 steady (`loop_steady`) | 0.928 / 0.923 / 0.921 | 0.79 / 1.14 / 1.22 | 0.09 / 0.19 / 0.16 | 12.7 / 13.4 / 13.4 |
| Fury L24 (`loop_warrior_fury24`) | 0.959 / 0.962 / 0.959 | 2.95 / 2.99 / 2.85 (3.4) | 0.09 / 0.06 / 0.03 | 2.8 / 3.9 / 3.9 |
| Arms (`loop_warrior`) | 0.959 / 0.959 / 0.958 | 1.55 / 1.55 / 1.63 (1.6: MISS) | 0.02 / 0.02 / 0.02 | 16.4 / 16.4 / 16.5 |
| Arms party (10 fights) | 0.959 / 0.959 / 0.962 | 1.32 / 1.32 / 1.46 | 0 / 0 / 0 | 8.2 / 8.2 / 8.1 (unmatched 3.7 in all) |
| Guardian (`loop_druid_guardian`) | 0.864 / 0.864 / 0.871 | 3.26 / 3.26 / 3.27 | 0.55 / 0.55 / 0.52 | 25.3 / 25.3 / 22.1 |
| Enhancement | 1.000 / 1.000 / 1.000 | 1.13 / 1.03 / 1.03 | 0 / 0 / 0 | 1.1 / 0.9 / 0.9 |
| Subtlety | 0.972 / 0.972 / 0.975 | 0.16 / 0.16 / 0.16 | 0 / 0 / 0 | - |

Also moved: the one-fight wowsims replays (Fury agreement 0.554 -> 0.552, flicker 3.99 -> 4.66; Guardian 0.741 ->
0.744), the 3-fight Guardian line (0.899 -> 0.889) and the recorded fixture pins (the Arms recommendation fixture's
626 changes: 618 lagged, 615 meter; the timing fixtures: Fury 23 of 89 decisions off it, Arms 8 of 74, none in
lagged). Enhancement's gain comes from the taken lead (L = M), not from the meter.

Reading, with the seed noise in mind:

- **Fury L60 flicker** is the one loop cost. Over 100 fights (five seed sets, the Fury probe) lagged reads 1.78, the
  meter before the c = 7 fix 2.18 (worse in 5 of 5 sets), the meter with the fix 1.83: the fix recovered 85-90 % of the
  gap and the rest (+0.06, standard error about 0.09) is within noise. On the gate's seeds alone it reads 1.84 against
  1.74 (and 1.63 in the default, whose 1.8 floor the lagged arm itself misses on two of the five sets).
- **Agreement** is within noise: Fury L60 0.921 / 0.922 / 0.918 (lagged / meter / meter with the fix) over 100 fights.
- **Fury L24 and Arms flicker** are noise: over 60 fights Fury L24 averages 2.80 / 2.88 / 2.81 and Arms 1.42 / 1.46 /
  1.47 (Arms' 1.63 on seeds 1-20 against its 1.6 floor is 1.7 flips in 56 minutes).
- **Guardian** improves: agreement +0.007, refused for cost 25.3 -> 22.1 per 100 (26.5 -> 22.2 on seeds 21-40).
- Fury L60's ready-retracted MISS (0.16 against 0.1) comes from the taken lead (lagged 0.19), not the meter.
- The oracle shadow follows the arm's profile toggles too; the Fury probe showed that the oracle's own flicker moving
  (0.47 -> 0.59) is run A's shadowing of a world our presses drive, not a change of reference.

## Viewer arm

The viewer arm is identical to the default on every gate line (407 of 407 normalised gate lines): every detection cell,
fights gate, loop and replay line, and 0 MISS in `.ab/viewer.tsv`. That is not a measured "no effect": the harness loops
(Druid and Warrior included) build no Cooldown Manager items. The fake's category sets start empty (`fake_api.lua`
`ctl.viewer`), so the router tracks nothing, `covered` is 0, the `@viewer` events find no item, and the per-aura `facts`
and `disagree` counts are 0 for every aura in every loop. Per-aura facts and disagreements are measured only by the unit
specs (`viewer_spec`, `router_spec`, `auras_spec`) on fixture items. Feeding the loops' fake viewer from
`tools/data/cooldownviewer/WARRIOR.lua` is the next harness step if the owner wants a loop number before launch; the
real answer is the launch-day checkpoint CDM-T with the Warrior re-capture CDM-R.

Coverage (`make cdv-coverage`): Warrior 4 of 42 pack auras answered by the viewer (demoralizing_shout, sunder_armor,
sweeping_strikes, victorious), a lower bound; every other class has no fixture.

## For the owner's decision

- **Meter**: better on the belief gates (solo and group false credit, drift over, retractions, busy rage error,
  attacker clocks), equal on detection recall, and one loop cost within noise after the fix (Fury L60 flicker 1.84
  against 1.74 on seeds 1-20; 1.83 against 1.78 over 100 fights). Its in-game behaviour is unmeasured until DM-M and
  DM-P (launch day). Our pet's hits are its known weakness (K14p, DM-PET).
- **Viewer**: unmeasured in the loops (no fake items); taint (CDM-T) and coverage (CDM-R) decide it in game. Warrior
  coverage is 4 of 42 auras today.
- Both stay off by default until the owner rules.

## Using the providers (developer guide)

### The two experimental options

Options > Performance > Experimental, both off by default, profile-wide (`profile.performance.damageMeter`,
`profile.performance.cooldownViewer`; defaults in `src/Hekili/Options/Options.lua`).

- **"use the damage meter for swing outcomes"** injects `def.providers.outcomes = "meter"`
  (`Game/State/Sources/Outcomes/Meter.lua`). It reads only `DAMAGE_METER_COMBAT_SESSION_UPDATED (type, sessionID)` in
  combat (plain) and the meter's totals out of combat (the audit). It works with the Damage Meter window hidden or
  disabled.
- **"use the Cooldown Manager for aura presence"** gives the presence router (`Sources/Presence/Router.lua`, always
  injected) the viewer leaf (`Sources/Presence/CooldownViewer.lua`). It needs the Cooldown Manager enabled in the
  game options (`C_CooldownViewer.IsCooldownViewerAvailable()`); without it the router covers nothing.

Each setter calls `Hekili:ProvidersChanged()` (`Game/State/Adapter.lua`), which calls
`VS.SetProviders(outcomes, presence, viewer)`: at once out of combat; in combat the names are stored and applied at
`PLAYER_REGEN_ENABLED`. A provider never changes mid-fight. `VS.SetProviders` swaps the active tables (`I.outcomes`,
`I.presence`); `I.def.providers` keeps the build's names until the next build. A profile switch rebuilds through
`buildDef`, which reads both options. The engine never reads the profile.

### The audit lines

`/run VSCopy(Hekili.Virtual.State.Snapshot())` after a pull (the counters reset at `PLAYER_REGEN_DISABLED`; the last
fight's stay until the next pull). Two `providers` lines (`Game/Events/Rows.lua`):

```
providers outcomes=meter presence=router swings tick=HIT/AVOID row=N unknown=N muted=0|1 ownUnclaimed=N foreignByMeter=N
providers paid=N meter=N|- pins=N pinErr=X edges up=N down=N collide=N disagree=N
```

- `tick=HIT/AVOID`: swings the provider decided 15 ms after the swing; `row`: swings a row decided (the provider gave
  no answer); `unknown`: asked and unanswered (before the fight's first group, or muted); `muted`: 1 when the mute
  tripped (the provider told more avoids than the avoid rows it saw on our swing's unit, by 3).
- `foreignByMeter`: rows RowOwner called FOREIGN (count-only: nothing routes on it); `disagree`: of those, rows a
  ticket took anyway; `ownUnclaimed`: rows RowOwner called OURS that no ticket took (noise in a busy crowd, where the
  2 s white-row window cannot tell strangers' white rows from ours).
- `paid`: the amounts our tickets were paid; `meter`: the meter's own total for the fight (out of combat, `-` until
  read). Solo they should match (DM §3); in a party the meter counts our pet too.
- `pins`, `pinErr`: usability flips at an unchanged cost and the mean rage error at them.
- `edges`: presence edges the router passed on; `collide`: avoid rows credited to a swing the meter told HIT.

With the Cooldown Manager option on, one line per tracked aura and unit (`Game/State/Sources/Auras.lua`):
`presence <key> unit=player|target|- path=viewer|model facts=N disagree=N`. `facts` counts viewer answers that the
belief acted on (an edge, or a poll that contradicted the belief); `disagree` the ones that contradicted the belief's
own state: how wrong the modelled timer was.

### `make gate-ab`

```bash
make gate-ab                          # make gate three times: HEKILI_AB unset (default), meter, viewer
make gate AB_ARM=lagged               # the meter arm's baseline, by hand
```

`tests/Game/harness/ab.lua` chooses the arm. The default arm asserts every floor as `make gate` does. A provider arm
records each floor check as `label TAB ok|MISS TAB line` in `.ab/<arm>.tsv` and never fails (decision 86); health
checks (errors, secrets, allocation, CPU) assert in every arm. Detection cells write `cell ...` and `audit ...` lines.
`make gate-ab` starts with `rm -rf .ab`: copy `.ab/lagged.tsv` aside first. The meter arm also turns on a 0.48 s taken
lead (rows on us arrive late, as measured), so compare it with `lagged`, not with `default`. One arm's spec file:
`HEKILI_AB=meter .lua/bin/busted --tags=loop tests/Forever/loop_warrior_fury_spec.lua`. A loop verdict needs several
seed sets (the seed-noise rule, `docs/dev/gaps.md` "A/B seed noise").

### `make cdv-coverage`

`tools/check_cooldown_viewer.lua` compares each class pack's auras with `tools/data/cooldownviewer/<CLASS>.lua` (the
cooldown infos from ForeverProbe's `/vslog cdv ids`) and prints, per class, each aura's path (`viewer` or `model`) and
categories, the auras per category, and `coverage N/M`: auras with a BuffIcon or BuffBar item (categories 2 and 3), the
only ones the viewer answers. It always exits 0 and is not part of `make check`. A class with no fixture prints "no
fixture". Warrior today: `coverage 4/42` (a lower bound; ledger CDM-R).

