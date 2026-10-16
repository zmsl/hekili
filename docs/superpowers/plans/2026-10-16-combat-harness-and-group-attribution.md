# Combat Harness and Group Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Our white outcomes on the target are attributed by evidence, not by window and order. A seeded headless model of the Forever client (the combat harness: entities, behaviours, a world, an observer that encodes only what the client shows, scripted scenarios) drives VirtualState through the existing fakes and holds the truth, with the pasted logs as fixtures it is fitted to. Rows.lua scores every white outcome against our pending swings (amount class x landing-lag density / the learned background rate of that class), so other players' outcomes on our target stop paying us rage; an avoid is provisional; our credits that cross a spender's cost are judged by the client's next usability answer (retracted when it says short) and a flip nothing explains rescues a dropped wound; hits on us gain per-attacker amount bands. Every rule is gated on the harness.

**Architecture:**
- **Task 1 (the client model):** `tests/Virtual/harness/`: rng, entities, behaviours, world, observer, scenarios, drive; the four logs as fixtures (every token row kept); `fixtures_spec` fits the observer's and behaviours' defaults to log 2 and G5; `observer_spec` checks each observer rule on a one-event world; `alloc_spec` replays a generated party fight at 0 bytes. `fake_api` answers UnitDamage from `ctl.damage`; `pairing_replay_spec` reads log 2 from its fixture.
- **Task 2 (attribution):** Events/Rows.lua: the score (spec §1.2-§1.4), the amount classes with "above" (the N = 3 fallback dropped), the off hand's two references, the background rates from quiet windows, the foreign strike frame, school 1 only, provisional avoids, the learned lags; `metrics.lua` and the solo, group and sweep gates; the log 1, 3 and 5 replays.
- **Task 3 (the usability oracle):** Families/Resources.lua keeps each credit's deltas and prediction, takes the verdict before the ladder, retracts a firm credit answered short and pays a rescue; Events/Rows.lua registers `I.CreditVerdict` and `I.Rescue`, keeps the credit records, the dropped ring and the sixteen class bars.
- **Task 4 (hits on us):** Events/Attackers.lua: per-attacker amount bands (min and max of the clean credits), the band rule beside the clocks, elimination for a joining attacker; `onus_spec`.
- **Task 5 (lines and docs):** the `rows credited`, `rows oracle` and `rows onus` snapshot lines; `tools/vslog_fixture.lua` (a /vslog dump to a fixture); docs/dev/layout.md and the two research docs.
- **Task 6:** the in-game CHECKPOINT (spec §5), deferred to the user; not a blocker.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, StyLua, `lua5.1` (tools/vslog_fixture.lua), `make check` (Makefile: lint, fmt-check, typecheck, test, syntax, api-check).

**Spec:** `docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md` (binding). Decisions D1-D9 are accepted as recommended (user, 2026-10-16: "count all break points as approved"); D4 (the off hand's two references, §1.1 "RULED") is a fact. Every deviation below is measured on the harness or read in the code.

### Decisions as built

| Decision | As built | Where |
|---|---|---|
| D1 thresholds | q 0.90/0.08/0.02, LAMBDA0 0.01/s, T0 5 s, TAU 10 s as proposed; THETA retuned to 5 by the harness (D1 allows it; Deviation 1) | Task 2 |
| D2 per-hand windows | kept as the lag density's support `W_h` (1.5 / 2.0 s, capped at the period) | Task 2 |
| D3 avoid rows | provisional, emitted at the window's close, back-dated | Task 2 |
| D4 fight counts | solo 200, party 100, raid 30, sweep 20 a cell (18 cells): `busted` about 70 s (it was 6 s) | Tasks 2-4 |
| D5 gates | the §3.4 numbers, raid reported; two gates replaced (Deviations 10, 11) | Tasks 2-4 |
| D6 background memory | counts and quiet time persist across pulls, decay with combat time only | Task 2 |
| D7 G1 truth | the partner records too (checkpoint G1) | Task 6 |
| D8 oracle bounds | THETA_MIN 2, THETA_MAX 16, /1.1 and x1.5, soft x1.22 (soft labels), ORACLE_MIN/MAX 0.1/0.6 s until G7 | Task 3 |
| D9 the retracted swing's row | SWING_MISSED (MISS, back-dated) past its window: two rows for that swing | Task 3 |

### Deviations from the spec (each measured or read)

1. **THETA is 5, not 4.** At 4 the off hand's tail alone (0.9 x 0.10 / 2.0 s / 0.01 per s = 4.5) credits any exact off-range wound inside a window: the party-with-pet gate failed (6.05 false credits per 100 swings, gate 6, 100 fights). At 5: 5.69; party 1.35; solo unchanged; log 2 off 31/33 (floor 31). The class bars of §2.5 start at THETA.
2. **A glancing or partly blocked wound opens only the loose band down to 0** (§1.3 says "open the range from 0", which in today's `fits` made the exact band start at 0). With the exact band open, G's glancing 4 at 7 ms scores 0.9 x 0.08 / 0.01 = 7.2 and takes our main swing (the log 3 gate fails); loose, it scores 0.64: background. Log 2's BLOCK_REDUCED 48 is exact either way.
3. **The background counts only in combat**, as its quiet time accrues (§1.4): an outcome on the target before our pull would otherwise raise the rate over no time.
4. **Log 2's crits: 8 found, 7 on the amount's hand** (§3.4 "8/8 crits"). The last one (52 at 116581) lands 369 ms after the main swing and 103 ms after the off swing: it scores as the main hand's (LR 11.8 against the off hand's tail, 4.5) while its amount is the off hand's. The floors hold: main 36/36, off 31/33.
5. **The verdict's window is checked in Rows**, which holds the outcome's time: Resources asks `I.CreditVerdict(id, ok, t, firm)` (the spec's `(id, ok, t)` plus the prediction's firmness, which Resources knows) with each answer for the judged ability; Rows returns nil before ORACLE_MIN, false past ORACLE_MAX or for a NOT answer (`ok` nil: no verdict), true when judged. A NOT before ORACLE_MIN (a spender that has not answered yet) waits.
6. **Swing credits are not in `R.gain`** (§2.1 and §2.3 assume they are): `R.gain` carries casts' and hits-taken gains only, and the swing calibration depends on that. So a retraction leaves `R.gain` alone, and the rescue's condition is the estimate below the flipped cost (`need = c - est > 0`) rather than `R.gain - shortGain < c - shortEst`.
7. **A rescue is paid by Resources at once**: `I.Rescue` returns the hand, the crit and the swing's time and stages nothing; Resources pays the step (and the crit), then the crossing is explained and pins exactly. A staged `Swing` c = 1 would land after the flip's pin and pay the step twice.
8. **Rescue candidates are the dropped wounds that arrived ORACLE_MIN to ORACLE_MAX before the flip** (§2.3: "since the short report"): the flip trails the wound that caused it, and the polls (0.1-0.2 s) put the last short report after that wound. Measured in the party: the "since" rule rescued 3 times in 30 fights (2 ours); the window rule 172 times in 100 fights (161 ours, 0.94).
9. **The party oracle gate "overshoot windows at most half the no-oracle run's" is replaced by "no poll ever reads a floor at a cost the true power is below, with or without the oracle"** (a guard, not a ratio). The ladder clamps a false credit's floor at the same poll the oracle reads (§2.6), so the windows' overshoot belongs to the ladder and the swing calibration (above the top cost), not to the attribution: measured over 100 party fights, est a step over truth 126 vs 131 windows, lo a step over truth 8 vs 5 of 1200, a dangerous floor 0 vs 0.
10. **The solo rescue gate is "at most one wrong rescue, or 5%"** (§3.4: precision >= 0.95): solo leaves the oracle almost nothing to rescue (2 rescues in 200 fights, 1 ours).
11. **Hits on us: a band credit needs every candidate's band, and a joining attacker is found by elimination** (§4.2 rule 2, "exactly one that fits"). An attacker with no band yet may hold the amount too, so a band credit needs every candidate's band usable; and a wound every known band excludes goes to the one candidate with no band, which is how an attacker that joins later starts its clock and band. Measured (100 fights, 2x strength, the second joining at 15 s): precision 0.967, coverage 0.893; today's clocks alone (50 fights) 0.879 and 0.673. Two of the same strength are gated on us from the pull (§4.3: nothing attributed, precision vacuous); when the second joins later, the first's clock takes some of its hits (precision 0.88, reported).
12. **The generator is Park-Miller (multiplier 48271), not xorshift32**: Lua 5.1 has no bit operators; it is exact in doubles and the same on every machine (§3.1's reason).
13. **What the logs fixed in the observer**: the duplicate tokens fire nameplateN, then target, then softenemy/softinteract (P logs 1-2, G, G5; §3.1's table lists target first); player before targettarget; partyN before nameplateN. The main lag's core share is asserted within 0.10 of the default's 0.85 (tail 0.15), not ">= 0.85": G5 has 17 of 22 in 436-556 ms (0.77). A single off-hand share sits within 0.15 of both logs' only at their midpoint (own 0.452, main 0.49; log 2: 10 and 21 of 33, G5: 12 and 7 of 20). Usability: a gain flips the client's answer `usableDelay` (0.1 s, UNMEASURED until G7) later, our spend at its cast (UNMEASURED).
14. **Log 5's off minimum is 26**: its crit 53 halves to 26.5, under the session's 27.
15. **The `rows credited` line carries both off-hand references** (`off=` own, `ref=` the main reference): §1.5's line predates the ruling that made two.

### The current code, where it differs from the spec's description

The spec (written against 6dd6d6c2/08def3ae) matches today's Rows.lua, Attackers.lua and Resources.lua with three refinements read for this plan (081b30fa):
- Resources pays the white crit's extra on `Swing` c = 3 and keeps the per-hand hit rate (c = 4 decays it, c = 1 adds HIT_ALPHA); `R.gain` is our casts' and hits-taken gains (Deviation 6).
- Sources/Player.lua stages `Obs.PlayerHit` for every hit on us before and independent of Attackers.lua (§4.4 holds unchanged).
- fake_api already answers `UnitGUID`/`UnitIsUnit` for any token from `ctl.guid`/`ctl.unitIs`: the only fake_api addition is UnitDamage from `ctl.damage` (§3.1).

## How this plan was checked

Replayed, not hand-derived. A throwaway clone of `~/src/hekili` at `081b30fa` (in `/tmp`, tools from the main checkout's `.lua/`):
- Each task was written there and gated on the harness; then the tasks were rebuilt as a test commit and an implementation commit each, from `081b30fa`.
- The patches below are `git diff` between those states; they were extracted from this file and re-applied with `git apply` to a fresh clone at `081b30fa`, in this plan's order, with busted after every test patch and `make check` after every task. The final tree equals the hand-built one. Nothing was committed to `~/src/hekili`.

Measured counts (full suite, `busted`):

| State | Result |
|---|---|
| base `081b30fa` | 483 successes / 0 / 0 / 0 |
| T1 tests only | 473 successes / 0 failures / 4 errors / 0 pending |
| T1 green | 496 successes / 0 failures / 0 errors / 0 pending |
| T2 tests only | 505 successes / 23 failures / 2 errors / 0 pending |
| T2 green | 530 successes / 0 failures / 0 errors / 0 pending |
| T3 tests only | 530 successes / 2 failures / 7 errors / 0 pending |
| T3 green | 539 successes / 0 failures / 0 errors / 0 pending |
| T4 tests only | 541 successes / 3 failures / 2 errors / 0 pending |
| T4 green | 546 successes / 0 failures / 0 errors / 0 pending |
| T5 tests only | 546 successes / 2 failures / 0 errors / 0 pending |
| T5 green | 548 successes / 0 failures / 0 errors / 0 pending |

`make check` exited 0 after every task: luacheck 0 / 0 (119, 123, 123, 124, 125 files after the tasks in order), lua-language-server no problems, api-check ok in 65 loaded files with an empty inventory diff, `stylua --check .` silent.

Harness measurements on the final tree (the gates' own runs):

| Scenario (fights) | Measured | Gate |
|---|---|---|
| Fixture log 2, replay (1) | main 36/36, off 31/33, 0 late; crits 8 found, 7 on the amount's hand (Deviation 4) | main >= 34/36, off >= 31/33, 0 late |
| Fixture log 1 (1) | strike frames: SPELL_DAMAGE 77/84, no swing credit; the DoT tick 13 background; the crit 90 credited to the main swing 353 ms before | as the spec |
| Fixture log 3 (1) | our 50 credited to the main swing; the glancing 4 (7 ms) and MISS (53 ms) background; school 8 and segment C: no credit | as the spec |
| Fixture log 5, G5 (1) | main 22/22, off >= 18/20, the school-32 proc never credited | (added: G5 says "add log 5 as a fixture") |
| Solo, log-2 profile (200) | main 99.2%, off 98.9% right; wrong 0.3% / 0.1%; overshoot 0/2400 windows; false 0 | >= 94% each; wrong <= 2%; overshoot 0 |
| Solo, +20% damage buff at 30 s (100) | main 89.6% after the buff; false 0 | >= 85%; false 0 |
| Solo, form change at 30 s (100) | main 96.6%, off 96.7% after it; false 0 | >= 85%; false 0 |
| Party of 5, melee + caster on target (100) | main 80.9%, off 96.2%; 1.35 false / 100 swings; overshoot 16/1200 | main >= 75%, off >= 85%; <= 4; <= 5% |
| Party of 5 + pet + ranged (100) | main 72.9%, off 90.4%; 5.69 false / 100 swings; overshoot 40/1200 | >= 70% each; <= 6; <= 10% |
| Raid, 12 on target (30) | main 34.8%, off 84.3%; 8.88 false / 100 swings | reported (D5) |
| Sweep, levels 10-60 x DR 0/0.15/0.30 (20 a cell) | DR 0: every cell >= 98.7% right; DR 0.30: wrong <= 2.9%; DR 0.15: wrong <= 1.6% | DR 0 solo gates; DR 0.30 wrong <= 5% |
| Oracle, solo (200) | 27.7 verdicts a fight; 1 of 15847 own credits retracted; 2 rescues, 1 ours | <= 0.5%; precision >= 0.95 (Deviation 10) |
| Oracle, party of 5 (100, and the same with the hooks off) | 25.8 verdicts a fight; 47 of 64 judged false credits caught (73%); 8 of 7119 own retracted (0.11%); 172 rescues, 161 ours (0.94); a dangerous floor 0 and 0 | caught >= 60%; <= 1%; >= 0.90; overshoot (Deviation 9) |
| Hits on us, 2x strength, the second joining at 15 s (100) | precision 0.967, coverage 0.893; PlayerHit staged 10054 of 10054 | >= 0.95, >= 0.80 |
| Hits on us, same strength (100 from the pull; 30 joining) | from the pull: nothing attributed (precision vacuous); joining: precision 0.88, coverage 0.68 | precision >= 0.90, coverage reported |

## Global Constraints

From the spec, verbatim:

> **Boundary, binding for every section.** Everything here is core: `Virtual/**` and `tests/Virtual/**`. No class,
> spell, aura, form or rotation name; the harness names source profiles by shape (`melee`, `caster`, `ranged`, `pet`),
> never by class. The one class-shaped fact the model uses is the declared `onNextSwing` field.

> - **Zero allocation:** two more per-slot arrays (`actLR`, `actAvoid`: the avoid's LR and its event string, an interned
>   constant), `med[2]`, `spr[2]`, `bg[8]`, `quiet`, `lastW0`; scoring is a scalar loop over 8 slots with `math.exp`.
>   `alloc_spec` and the harness assert 0 bytes.

> Layers 1-3 and 5 allocate (test code); the world runs ahead into flat arrays, and the drive loop reads preallocated arrays and calls `ctl.Fire` with fixed
> arguments; `harness/alloc_spec` wraps one generated party fight in `alloc.bytes` (warm-up, then 5 replays) and asserts
> 0 bytes for VirtualState, as `alloc_spec` and the replay spec do.

> - Every task ends with busted, luacheck, StyLua, LuaLS and the boundary check (no class word in `Virtual/**` or the
>   harness).

The house rules for this plan:
- **Worktree.** Repository `~/src/hekili`. The orchestrator creates the worktree after the plan is committed: `git -C ~/src/hekili worktree add .claude/worktrees/combat-harness -b combat-harness forever`. Git from WSL only. After each task's green verification and clean review the orchestrator pushes `combat-harness`; never push to `forever` or any other branch; never force-push. No task merges.
- **Commits.** Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. An implementer on another model uses its own model's name.
- **The boundary** (above; `docs/research/2026-10-16-core-leakage-audit.md`). No class, race or ability name in any core or harness change, comments included: `git diff forever -- src/Hekili/Virtual tests/Virtual tools docs/dev | grep '^+' | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|undead|maul|heroic|overpower|shred|bloodrage|charge|grave|bear'` prints nothing after every task. The fixtures name our spells `STRIKE`, `DOT`, `OTHER` (the fake spec's `REND`, `SHOUT` and `STRIKE` keys predate this plan).
- **Zero allocation on every per-event path.** Rows' scoring, provisional avoids, records, dropped ring, verdict and rescue; Resources' records, verdict, retraction and rescue payment; Attackers' bands: no table, closure or string is built per event. Tests: State `alloc_spec` (adds a provisional avoid), `pairing_replay_spec` and `cleu_rows_spec` (0 bytes), the harness `alloc_spec` (a generated party fight with presses, usability, two attackers: a retraction, a rescue and band credits among its paths), each 0 bytes.
- **Secret safety.** No new client read: Rows and Attackers read the event facade's arguments (already through `Plain`: a secret slot arrives nil) and the out-of-combat stat cache; Resources reads nothing from the client. No `a and b or c` on a possibly-secret value. `tools/api_inventory.txt` stays unchanged.
- **Style.** StyLua formats our files (the fixtures carry `-- stylua: ignore`). Each patch is StyLua-clean.
- **Tools.** Run everything from the worktree root. The worktree has no `.lua/`: `make check LUA_ENV=$HOME/src/hekili/.lua`; busted alone: `$HOME/src/hekili/.lua/bin/busted`. `make check` now takes about 90 s (busted about 70 s: the harness gates).
- **Patches** are applied with `git apply` from the worktree root, in the order given. Each block is a heredoc, so copy it whole.
- **Every task ends green on `make check`** (the verification block in each task).
- **The user runs the game.** Task 6 is the in-game checkpoint; it is deferred to the user and blocks nothing: the branch can merge with it open. Every line is under 255 characters and copies its answer through `VSCopy(` (ForeverProbe). No new TOC file: `/reload` suffices.

## Review Focus

1. **The score and its bar** (Deviations 1-3): LR = q x f / lambda, THETA 5, a glancing hit loose only, the background in combat only, school 1 only, the foreign strike frame. Tests: pairing_replay_spec "makes a glancing 4 at 7 ms and a MISS at 53 ms background...", "credits an above-range wound in the core band solo...", "drops another player's strike frame..."; solo_spec and group_spec gates; fixtures_spec "log 3: our 50 credited...".
2. **Provisional avoids and the rows' timing** (D3, D9): an avoid emitted at its window's close, a wound that beats it takes the swing, a retracted swing re-held or closed as SWING_MISSED. Tests: pairing_replay_spec "credits an avoid provisionally..." and "keeps an avoid nothing beats..."; cleu_rows_spec "credits a swing the target's dodge at its lag..."; resources_spec "closes a retracted swing past its window as SWING_MISSED".
3. **The oracle against the ladder** (Deviations 5-9): the verdict before the ladder, firm vs soft, a spend voids, a NOT waits; the rescue paid in Resources and pinned exactly; lo never above its pre-credit value. Tests: resources_spec "the usability oracle" (7 cases); group_spec "oracle, party of 5..."; solo_spec "oracle: retracts <= 0.5%...".
4. **Zero allocation** on the new per-event paths (the Global Constraints' list). Tests: alloc_spec (State), pairing_replay_spec "allocates nothing replaying the log", cleu_rows_spec "allocates nothing per hit on us" and "per paired swing", harness alloc_spec (asserts the retraction, rescue and band paths ran).
5. **The harness's fidelity**: every observer rule cites its log or is UNMEASURED with a knob; the fits (Deviations 13-14); the client's usability from a power timeline (gains delayed, spends at once); the truth the metrics read. Tests: fixtures_spec (fits, token order, replays), observer_spec (9 rules).

## File structure

```
tests/Virtual/harness/rng.lua              T1  seeded Park-Miller generator
tests/Virtual/harness/entities.lua         T1  actors: weapons, armour DR, avoid table, power, target
tests/Virtual/harness/behaviours.lua       T1  melee (swings per hand, presses, strikes, proc, DoT), caster, mob
tests/Virtual/harness/world.lua            T1  one clock, the truth stream, our rage, set-piece snapshots
tests/Virtual/harness/observer.lua         T1  the client: tokens, lags, procs, strike frames, secrets, usability, cache
tests/Virtual/harness/scenarios.lua        T1  rosters, archetypes, set pieces, the oracle preset
tests/Virtual/harness/drive.lua            T1  boots VirtualState, fires a stream, captures credits, rows, verdicts, hits
tests/Virtual/harness/fixtures/log1.lua    T1  log 1, every token row
tests/Virtual/harness/fixtures/log2.lua    T1  log 2, every token row (pairing_replay_spec reads it)
tests/Virtual/harness/fixtures/log3.lua    T1  log 3 (party), every token row
tests/Virtual/harness/fixtures/log5.lua    T1  G5, every token row
tests/Virtual/harness/fixtures_spec.lua    T1  fits, token order; T2 the replays; T5 the fixture tool
tests/Virtual/harness/observer_spec.lua    T1  the observer's rules
tests/Virtual/harness/alloc_spec.lua       T1  a party fight at 0 bytes; T3 with the oracle; T4 with two attackers
tests/Virtual/harness/metrics.lua          T2  own/wrong/missed/false per hand, rage windows, oracle and onus tallies
tests/Virtual/harness/solo_spec.lua        T2  solo, buff, form gates; T3 the solo oracle gate
tests/Virtual/harness/group_spec.lua       T2  party gates, raid report; T3 the party oracle gate
tests/Virtual/harness/sweep_spec.lua       T2  levels 10-60 x DR 0/0.15/0.30 (#slow)
tests/Virtual/harness/onus_spec.lua        T4  hits-on-us gates
tests/Virtual/State/helpers/fake_api.lua   T1  UnitDamage from ctl.damage
tests/Virtual/Events/pairing_replay_spec.lua  T1 log 2 from the fixture; T2 the frame cases and floors
tests/Virtual/Events/cleu_rows_spec.lua    T2  the dodge at its lag; T4 bands (4 cases); T5 the snapshot lines
tests/Virtual/State/alloc_spec.lua         T2  a provisional avoid in the mix
tests/Virtual/State/resources_spec.lua     T3  "the usability oracle" (7 cases)
src/Hekili/Virtual/Events/Rows.lua         T2  the score; T3 records, verdict, rescue, class bars; T5 snapshot lines
src/Hekili/Virtual/State/Families/Resources.lua  T3  records' deltas, the verdict, retraction, rescue payment
src/Hekili/Virtual/Events/Attackers.lua    T4  amount bands, the band rule, elimination; T5 the onus line
tools/vslog_fixture.lua                    T5  a /vslog dump to a fixture
docs/dev/layout.md                         T5  the harness and how a capture becomes a fixture
docs/research/2026-10-16-swing-outcome-pairing.md, 2026-10-16-group-pairing-captures.md  T5  fixture pointers
.busted, .luacheckrc                       T1  the harness specs run and are linted
```

Deliberately not built (a review should not flag these):
- "press what the display recommends" (§3.1, a later extension);
- party members not on our target (their rows go to tokens nothing reads), heals on party members, parry haste on our swing timer (shortcuts in scenarios.lua);
- a raid gate (D5: reported only);
- G6 as a fixture (its capture cast the buff between fights; §5's G6 asks for one in combat);
- caching or exposing the background rates beyond the snapshot line.

---
### Task 1: The harness's client model, with the logs as fitted fixtures

Spec §3.1 (the five layers, the observer's table, the files beside the layers), §3.5 (fixtures and the fit), §3.6 (allocation); §6's harness specs `fixtures_spec`, `observer_spec`, `alloc_spec`.

**Files:**
- Create: `tests/Virtual/harness/rng.lua`, `entities.lua`, `behaviours.lua`, `world.lua`, `observer.lua`, `scenarios.lua`, `drive.lua`; `tests/Virtual/harness/fixtures/log1.lua`, `log2.lua`, `log3.lua`, `log5.lua`
- Modify: `tests/Virtual/State/helpers/fake_api.lua` (`ctl.damage`, UnitDamage answers it), `.busted` (ROOT adds `tests/Virtual/harness`), `.luacheckrc` (`files["tests/Virtual/harness/"] = { std = "+busted" }`)
- Test: `tests/Virtual/harness/fixtures_spec.lua` (new: "fits the observer's and behaviours' defaults to log2", "... to log5", "fires the tokens of one outcome in the observer's order, in every log"), `tests/Virtual/harness/observer_spec.lua` (new, 9 cases: "fires our swing, then its outcome on the target's plate and the target in the same ms", "fires a hit on us for player, then targettarget while our target targets us; another's on partyN", "fires another source's outcome on our target's tokens; its casts with secret IDs, ours plain", "fires a queued strike's frame: ...", "fires another player's strike frame as a WOUND 0 and its damage 1 ms later, with no cast", "fires the on-swing proc as a school-32 wound on the target and a heal on us, same ms", "adds an unexplained avoid in the swing event's ms at its share, and lands our hands at their lags", "answers usability from our true power: a gain flips it a knob's delay later, our spend at once", "reads the weapon damage cache out of combat only: ..."), `tests/Virtual/harness/alloc_spec.lua` (new: "allocates nothing in VirtualState replaying a generated party fight"), `tests/Virtual/Events/pairing_replay_spec.lua` (log 2 from the fixture, deduplicated to one row per outcome as before; its cases unchanged)

**Interfaces:**
- Consumes: `fake_api` (`ctl.Fire`, `ctl.Tick`, the `ctl` answers), `fake_spec` (`fs.def`, `fs.fold`, the spenders SHOUT 10, STRIKE 15, REND 10), `load.module`; the event facade's `COMBAT_LOG_EVENT_UNFILTERED` rows; `S.Stage`; `I.On(Obs.PlayerHit)`.
- Produces (test code, all under `tests/Virtual/harness/`):
  - `rng.new(seed)`: `next()` in [0, 1), `int(a, b)`, `chance(p)`, `normal(mu, sd)`, `pick(list)`;
  - `entities.new(o)` (guid, kind, level, weapons `{ { min, max, speed }, ... }`, dr, avoid, health, powerMax), `entities.weapons(level)` (log 2's 36-50 / 24-32 x level / 22);
  - `behaviours.melee(p)`, `behaviours.caster(p)`, `behaviours.mob(p)`, `behaviours.RATES` (miss 0.14, dodge 0.04, parry 0.04, crit 0.12);
  - `world.new(seed)`: `at(t, fn)`, `emit(ev)`, `add(e, behaviour)`, `run(tEnd)`, `truth` (events `{ t, kind, src, dst, hand, act, flag, amount, school, spell, power, ... }`);
  - `observer.observe(W, k)` -> the stream `{ n, t[], ev[], a1..a5[], src[], hand[], swingT[], actor[] }` (`@`-ops change client answers; `@truth` carries our true power), `observer.lag(k)`, `observer.DEFAULTS`, `observer.SPELLS`, `observer.COSTS`, `observer.rank(token)`;
  - `scenarios.build(o, seed)`, `scenarios.stream(o, seed)`, `scenarios.oracle(o)`, `scenarios.ARCHETYPES` (`melee`, `caster`, `pet`, `ranged`);
  - `drive.boot(o)`, `drive.run(c, s, offset)`, `drive.restore(c)`, `drive.fixtureStream(fix, base, dedupe)`; captures by stream index `crHand`, `crAt`, `crTok`, `verdict`, `onus`, and `crits`, `landed`, `rows`, `win`/`winT`, `loOver`, `estOver`, `danger`, `lateHand`/`lateAt`, `hits` (the drive wraps `I.CreditVerdict`/`I.Rescue` only once Rows registers them, Task 3; `o.oracle == false` unregisters them for the no-oracle run; the verdict, rescue and onus captures stay empty until Tasks 3 and 4);
  - fixtures `{ damage = { min, max, min, max }, rows = { ... } }`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/.busted b/.busted
index 3850cfc7..2d4dc4fc 100644
--- a/.busted
+++ b/.busted
@@ -1,6 +1,6 @@
 return {
     default = {
-        ROOT = { "tests/Virtual/Events", "tests/Virtual/API", "tests/Virtual/State", "tests/Forever" },
+        ROOT = { "tests/Virtual/Events", "tests/Virtual/API", "tests/Virtual/State", "tests/Virtual/harness", "tests/Forever" },
         pattern = "_spec",
         lpath = "./src/Hekili/?.lua;./tests/?.lua;./?.lua",
         verbose = true,
diff --git a/.luacheckrc b/.luacheckrc
index a519d8e0..273f9eae 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -100,6 +100,7 @@ local nowEnv = {
 files["tests/Virtual/State/"] = { std = "+busted", read_globals = nowEnv }
 files["tests/Virtual/Events/"] = { std = "+busted", read_globals = nowEnv }
 files["tests/Virtual/API/"] = { std = "+busted", read_globals = nowEnv }
+files["tests/Virtual/harness/"] = { std = "+busted" }
 files["tests/Forever/"] = { std = "+busted" }
 -- The Warrior's handlers, state expressions and state functions run with setfenv( f, state ) as well; these are the
 -- further `state` names they use.
diff --git a/tests/Virtual/Events/pairing_replay_spec.lua b/tests/Virtual/Events/pairing_replay_spec.lua
index ff542079..02c3f506 100644
--- a/tests/Virtual/Events/pairing_replay_spec.lua
+++ b/tests/Virtual/Events/pairing_replay_spec.lua
@@ -1,72 +1,16 @@
 -- tests/Virtual/Events/pairing_replay_spec.lua (event-facade spec §3, pairing): log 2 of
--- docs/research/2026-10-16-swing-outcome-pairing.md replayed through the real Rows.lua, with the weapon damage the
--- character had (main 36-50, off 24-32). Every UNIT_COMBAT row is fed as the token "target": the log is already
--- deduplicated (one row per outcome, a few kept under softinteract or nameplate1), and in game Rows.lua reads only
--- "target", which dedupes the tokens.
+-- docs/research/2026-10-16-swing-outcome-pairing.md (the harness fixture tests/Virtual/harness/fixtures/log2.lua)
+-- replayed through the real Rows.lua, with the weapon damage the character had (main 36-50, off 24-32). Every
+-- outcome on the target is fed once as the token "target" (a few were recorded only under softinteract or nameplate1),
+-- as in game Rows.lua reads only "target", which dedupes the tokens.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local alloc = require("Virtual.State.helpers.alloc")
 local fs = require("Virtual.State.helpers.fake_spec")
+local drive = require("Virtual.harness.drive")
 
--- ms since the first event, then: "S" PLAYER_SWING duration swingType; "U" UNIT_COMBAT action flag amount;
--- "C" our UNIT_SPELLCAST_SUCCEEDED spellID (Charge: not an ability of the fake spec, so it pairs with nothing).
--- stylua: ignore
-local LOG = {
-    { 0, "C", 100 }, { 998, "S", 2.2, 0 }, { 1296, "S", 2.5, 1 }, { 1472, "U", "WOUND", "", 40 },
-    { 2695, "U", "WOUND", "", 31 }, { 3158, "S", 2.2, 0 }, { 3612, "U", "WOUND", "", 41 }, { 3775, "S", 2.5, 1 },
-    { 4844, "U", "WOUND", "", 30 }, { 5404, "S", 2.2, 0 }, { 5841, "U", "WOUND", "", 43 }, { 6289, "S", 2.5, 1 },
-    { 7091, "U", "WOUND", "", 31 }, { 7556, "S", 2.2, 0 }, { 7992, "U", "WOUND", "", 49 }, { 8788, "S", 2.5, 1 },
-    { 9491, "U", "DODGE", "", 0 }, { 9788, "S", 2.2, 0 }, { 10308, "U", "WOUND", "", 49 }, { 11221, "S", 2.5, 1 },
-    { 11924, "U", "WOUND", "", 28 }, { 11988, "S", 2.2, 0 }, { 12122, "U", "WOUND", "CRITICAL", 91 },
-    { 17786, "C", 100 }, { 18518, "S", 2.5, 1 }, { 18785, "S", 2.2, 0 }, { 19221, "U", "WOUND", "", 30 },
-    { 19221, "U", "MISS", "", 0 }, { 21085, "S", 2.2, 0 }, { 21085, "S", 2.5, 1 }, { 21521, "U", "WOUND", "", 45 },
-    { 22771, "U", "WOUND", "", 25 }, { 23251, "S", 2.2, 0 }, { 23635, "S", 2.5, 1 },
-    { 23788, "U", "WOUND", "BLOCK_REDUCED", 48 }, { 24938, "U", "WOUND", "", 26 }, { 25401, "S", 2.2, 0 },
-    { 25938, "U", "WOUND", "", 42 }, { 26118, "S", 2.5, 1 }, { 27088, "U", "WOUND", "CRITICAL", 56 },
-    { 27685, "S", 2.2, 0 }, { 28138, "U", "WOUND", "", 39 }, { 28635, "S", 2.5, 1 },
-    { 29371, "U", "WOUND", "", 25 }, { 29835, "S", 2.2, 0 }, { 30271, "U", "WOUND", "", 48 },
-    { 31051, "S", 2.5, 1 }, { 31755, "U", "WOUND", "", 31 }, { 32069, "S", 2.2, 0 },
-    { 32505, "U", "WOUND", "", 43 }, { 33651, "S", 2.5, 1 }, { 38086, "C", 100 }, { 38935, "S", 2.5, 1 },
-    { 39086, "S", 2.2, 0 }, { 39638, "U", "WOUND", "", 29 }, { 39638, "U", "WOUND", "", 49 },
-    { 41368, "S", 2.2, 0 }, { 41369, "S", 2.5, 1 }, { 41905, "U", "WOUND", "", 48 },
-    { 43055, "U", "WOUND", "", 28 }, { 43585, "S", 2.2, 0 }, { 43935, "S", 2.5, 1 },
-    { 44122, "U", "WOUND", "", 50 }, { 45272, "U", "WOUND", "", 30 }, { 45785, "S", 2.2, 0 },
-    { 46323, "U", "WOUND", "", 45 }, { 46452, "S", 2.5, 1 }, { 47472, "U", "WOUND", "", 27 },
-    { 48002, "S", 2.2, 0 }, { 48522, "U", "WOUND", "CRITICAL", 97 }, { 48885, "S", 2.5, 1 },
-    { 49689, "U", "WOUND", "", 30 }, { 50202, "S", 2.2, 0 }, { 50638, "U", "WOUND", "", 45 },
-    { 51452, "S", 2.5, 1 }, { 52146, "U", "WOUND", "CRITICAL", 48 }, { 58607, "C", 100 }, { 59592, "S", 2.5, 1 },
-    { 59891, "S", 2.2, 0 }, { 59891, "U", "MISS", "", 0 }, { 60294, "U", "WOUND", "", 28 },
-    { 61095, "U", "WOUND", "", 48 }, { 62091, "S", 2.2, 0 }, { 62091, "S", 2.5, 1 },
-    { 62628, "U", "WOUND", "", 49 }, { 63777, "U", "WOUND", "", 26 }, { 64291, "S", 2.2, 0 },
-    { 64641, "S", 2.5, 1 }, { 64728, "U", "WOUND", "CRITICAL", 100 }, { 65978, "U", "WOUND", "", 28 },
-    { 66508, "S", 2.2, 0 }, { 66944, "U", "WOUND", "", 38 }, { 67141, "S", 2.5, 1 },
-    { 68194, "U", "WOUND", "", 26 }, { 68708, "S", 2.2, 0 }, { 69178, "U", "WOUND", "", 50 },
-    { 69641, "S", 2.5, 1 }, { 70395, "U", "WOUND", "", 31 }, { 70909, "S", 2.2, 0 },
-    { 71433, "U", "WOUND", "", 41 }, { 74361, "C", 100 }, { 75361, "S", 2.2, 0 }, { 75611, "S", 2.5, 1 },
-    { 75897, "U", "WOUND", "", 42 }, { 76694, "S", 2.2, 0 }, { 77048, "U", "WOUND", "", 29 },
-    { 77781, "U", "MISS", "", 0 }, { 78061, "S", 2.5, 1 }, { 78862, "S", 2.2, 0 }, { 79014, "U", "WOUND", "", 27 },
-    { 79731, "U", "WOUND", "CRITICAL", 89 }, { 80628, "S", 2.5, 1 }, { 81111, "S", 2.2, 0 },
-    { 81331, "U", "WOUND", "", 30 }, { 82048, "U", "MISS", "", 0 }, { 83128, "S", 2.5, 1 }, { 83311, "S", 2.2, 0 },
-    { 83831, "U", "WOUND", "", 27 }, { 84548, "U", "WOUND", "", 49 }, { 85511, "S", 2.2, 0 },
-    { 85611, "S", 2.5, 1 }, { 85611, "U", "MISS", "", 0 }, { 85948, "U", "PARRY", "", 0 },
-    { 87198, "U", "WOUND", "", 27 }, { 87728, "S", 2.2, 0 }, { 88128, "S", 2.5, 1 }, { 88247, "U", "PARRY", "", 0 },
-    { 89415, "U", "WOUND", "", 31 }, { 89928, "S", 2.2, 0 }, { 90381, "U", "WOUND", "", 45 },
-    { 90611, "S", 2.5, 1 }, { 91614, "U", "WOUND", "", 28 }, { 92128, "S", 2.2, 0 },
-    { 92582, "U", "WOUND", "", 47 }, { 95362, "C", 100 }, { 96178, "S", 2.2, 0 }, { 96495, "S", 2.5, 1 },
-    { 96715, "U", "WOUND", "", 41 }, { 97864, "U", "DODGE", "", 0 }, { 98462, "S", 2.2, 0 },
-    { 98915, "U", "WOUND", "", 39 }, { 98995, "S", 2.5, 1 }, { 99778, "S", 2.2, 0 },
-    { 100148, "U", "PARRY", "", 0 }, { 100882, "U", "MISS", "", 0 }, { 101512, "S", 2.5, 1 },
-    { 101928, "S", 2.2, 0 }, { 102215, "U", "DODGE", "", 0 }, { 102934, "U", "MISS", "", 0 },
-    { 103962, "S", 2.5, 1 }, { 104128, "S", 2.2, 0 }, { 104665, "U", "WOUND", "CRITICAL", 55 },
-    { 105415, "U", "WOUND", "", 39 }, { 106379, "S", 2.2, 0 }, { 106512, "S", 2.5, 1 },
-    { 106833, "U", "WOUND", "", 47 }, { 108065, "U", "MISS", "", 0 }, { 108595, "S", 2.2, 0 },
-    { 109012, "S", 2.5, 1 }, { 109132, "U", "WOUND", "", 41 }, { 110282, "U", "WOUND", "", 31 },
-    { 110795, "S", 2.2, 0 }, { 110796, "U", "MISS", "", 0 }, { 111232, "U", "WOUND", "", 50 },
-    { 111512, "S", 2.5, 1 }, { 112482, "U", "WOUND", "", 30 }, { 113012, "S", 2.2, 0 },
-    { 113447, "U", "WOUND", "", 42 }, { 114012, "S", 2.5, 1 }, { 114714, "U", "WOUND", "", 29 },
-    { 116212, "S", 2.2, 0 }, { 116478, "S", 2.5, 1 }, { 116581, "U", "WOUND", "CRITICAL", 52 },
-    { 116734, "U", "MISS", "", 0 },
-}
+-- One row per outcome on the target, fed as "target" (harness/drive.lua's dedupe of the fixture's token rows).
+local LOG = drive.fixtureStream(require("Virtual.harness.fixtures.log2"), 0, true)
 
 describe("swing/outcome pairing", function()
     local api, ctl, VS, I, L, saved, got, record
@@ -126,17 +70,16 @@ describe("swing/outcome pairing", function()
         for key in pairs(stats) do
             stats[key] = 0
         end
-        for k = 1, #LOG do
-            local r = LOG[k]
-            local now = base + r[1] / 1000
+        for k = 1, LOG.n do
+            local now = base + LOG.t[k]
+            local kind = LOG.ev[k]
             ctl.Tick(now)
-            local kind = r[2]
-            if kind == "S" then
-                ctl.Fire("PLAYER_SWING", r[3], r[4])
-            elseif kind == "C" then
-                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", r[3])
-            else
-                local act, flag, amount = r[3], r[4], r[5]
+            if kind == "PLAYER_SWING" then
+                ctl.Fire("PLAYER_SWING", LOG.a1[k], LOG.a2[k])
+            elseif kind == "UNIT_SPELLCAST_SUCCEEDED" then
+                ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", LOG.a3[k])
+            elseif kind == "UNIT_COMBAT" then
+                local act, flag, amount = LOG.a2[k], LOG.a3[k], LOG.a4[k]
                 lastAmount = 0
                 local c1, c2 = crits[1], crits[2]
                 ctl.Fire("UNIT_COMBAT", "target", act, flag, amount, 1)
diff --git a/tests/Virtual/harness/alloc_spec.lua b/tests/Virtual/harness/alloc_spec.lua
new file mode 100644
index 00000000..283e264a
--- /dev/null
+++ b/tests/Virtual/harness/alloc_spec.lua
@@ -0,0 +1,18 @@
+-- tests/Virtual/harness/alloc_spec.lua (harness design §3.6): one generated party fight (two other sources on our
+-- target, a mob on us, our presses) replayed through VirtualState: after a warm-up, the replays allocate nothing.
+local scenarios = require("Virtual.harness.scenarios")
+local drive = require("Virtual.harness.drive")
+local alloc = require("Virtual.State.helpers.alloc")
+
+describe("the harness drive", function()
+    it("allocates nothing in VirtualState replaying a generated party fight", function()
+        local s = scenarios.stream(scenarios.oracle({ duration = 30, others = { "melee", "caster" } }), 2)
+        local c = drive.boot({ max = 100 })
+        local ok, bytes = pcall(alloc.bytes, function(i)
+            drive.run(c, s, i * 100)
+        end, 5)
+        drive.restore(c)
+        assert.is_true(ok, tostring(bytes))
+        assert.are.equal(0, bytes)
+    end)
+end)
diff --git a/tests/Virtual/harness/fixtures/log1.lua b/tests/Virtual/harness/fixtures/log1.lua
new file mode 100644
index 00000000..1cda0940
--- /dev/null
+++ b/tests/Virtual/harness/fixtures/log1.lua
@@ -0,0 +1,38 @@
+-- tests/Virtual/harness/fixtures/log1.lua: log 1 of docs/research/2026-10-16-swing-outcome-pairing.md (2026-10-16),
+-- every token row as /vslog recorded it (ms since the first event). Solo, level 22, dual wield (main 2.2 s, off 2.5 s),
+-- one mob: two on-next-swing strike frames (4330, 6532), a DoT cast at 2844 (its tick, WOUND 13, at 5847), the
+-- unexplained WOUND 30 + CRITICAL 90 frame at 2463, hits on us (player, then targettarget). `damage`: UnitDamage's min
+-- and max per hand (the research doc).
+-- Rows: { ms, "S", duration, swingType } PLAYER_SWING; { ms, "U", unit, action, flag, amount, school } UNIT_COMBAT;
+-- { ms, "C", unit, spell } UNIT_SPELLCAST_SUCCEEDED (spell: "STRIKE" on-next-swing, "DOT", "OTHER", "SECRET").
+-- stylua: ignore
+return {
+    damage = { 36, 50, 24, 32 },
+    rows = {
+        { 0, "C", "player", "OTHER" }, { 771, "S", 2.2, 0 }, { 1006, "C", "player", "OTHER" }, { 1008, "S", 2.5, 1 },
+        { 1297, "U", "player", "PARRY", "", 0, 1 }, { 1297, "U", "targettarget", "PARRY", "", 0, 1 },
+        { 1345, "C", "player", "OTHER" }, { 1345, "C", "targettarget", "OTHER" },
+        { 1762, "U", "nameplate1", "WOUND", "", 49, 1 }, { 1762, "U", "target", "WOUND", "", 49, 1 },
+        { 2110, "S", 2.2, 0 }, { 2111, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 2111, "U", "target", "MISS", "", 0, 1 }, { 2463, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 2463, "U", "target", "WOUND", "", 30, 1 }, { 2463, "U", "nameplate1", "WOUND", "CRITICAL", 90, 1 },
+        { 2463, "U", "target", "WOUND", "CRITICAL", 90, 1 }, { 2663, "U", "player", "WOUND", "", 12, 1 },
+        { 2663, "U", "targettarget", "WOUND", "", 12, 1 }, { 2844, "C", "player", "DOT" },
+        { 2844, "C", "targettarget", "DOT" }, { 3593, "S", 2.5, 1 }, { 3897, "U", "player", "WOUND", "", 13, 1 },
+        { 3897, "U", "targettarget", "WOUND", "", 13, 1 }, { 4297, "U", "nameplate1", "WOUND", "", 29, 1 },
+        { 4297, "U", "target", "WOUND", "", 29, 1 }, { 4328, "C", "player", "OTHER" },
+        { 4329, "C", "targettarget", "OTHER" }, { 4330, "C", "player", "STRIKE" },
+        { 4330, "C", "targettarget", "STRIKE" }, { 4330, "U", "nameplate1", "WOUND", "", 0, 1 },
+        { 4330, "U", "target", "WOUND", "", 0, 1 }, { 4330, "S", 2.2, 0 },
+        { 4331, "U", "nameplate1", "WOUND", "", 77, 1 }, { 4331, "U", "target", "WOUND", "", 77, 1 },
+        { 5318, "U", "player", "WOUND", "", 13, 1 }, { 5318, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 5847, "U", "nameplate1", "WOUND", "", 13, 1 }, { 5847, "U", "target", "WOUND", "", 13, 1 },
+        { 6015, "S", 2.5, 1 }, { 6531, "C", "player", "STRIKE" }, { 6532, "C", "targettarget", "STRIKE" },
+        { 6532, "U", "nameplate1", "WOUND", "", 0, 1 }, { 6532, "U", "target", "WOUND", "", 0, 1 },
+        { 6532, "S", 2.2, 0 }, { 6532, "U", "nameplate1", "WOUND", "", 84, 1 },
+        { 6532, "U", "target", "WOUND", "", 84, 1 }, { 6619, "U", "player", "WOUND", "", 13, 1 },
+        { 6619, "U", "targettarget", "WOUND", "", 13, 1 }, { 7017, "U", "nameplate1", "WOUND", "", 33, 1 },
+        { 7017, "U", "target", "WOUND", "", 33, 1 }, { 8614, "S", 2.5, 1 },
+        { 9305, "U", "target", "WOUND", "", 30, 1 }, { 9305, "U", "softinteract", "WOUND", "", 30, 1 },
+    },
+}
diff --git a/tests/Virtual/harness/fixtures/log2.lua b/tests/Virtual/harness/fixtures/log2.lua
new file mode 100644
index 00000000..c9484d6e
--- /dev/null
+++ b/tests/Virtual/harness/fixtures/log2.lua
@@ -0,0 +1,185 @@
+-- tests/Virtual/harness/fixtures/log2.lua: log 2 of docs/research/2026-10-16-swing-outcome-pairing.md (2026-10-16),
+-- every token row as /vslog recorded it (368 events). Solo, level 22, dual wield (main 2.2 s, off 2.5 s), auto-attack
+-- only, six mobs. The research doc's table is this log deduplicated to one row per outcome on the target.
+-- Rows: { ms, "S", duration, swingType } PLAYER_SWING; { ms, "U", unit, action, flag, amount, school } UNIT_COMBAT;
+-- { ms, "C", unit, spell } UNIT_SPELLCAST_SUCCEEDED (spell: "STRIKE" on-next-swing, "DOT", "OTHER", "SECRET").
+-- stylua: ignore
+return {
+    damage = { 36, 50, 24, 32 },
+    rows = {
+        { 0, "C", "player", "OTHER" }, { 998, "S", 2.2, 0 }, { 1296, "S", 2.5, 1 },
+        { 1400, "U", "player", "WOUND", "", 11, 1 }, { 1400, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 1472, "U", "nameplate1", "WOUND", "", 40, 1 }, { 1472, "U", "target", "WOUND", "", 40, 1 },
+        { 2628, "U", "player", "WOUND", "", 12, 1 }, { 2628, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 2695, "U", "nameplate1", "WOUND", "", 31, 1 }, { 2695, "U", "target", "WOUND", "", 31, 1 },
+        { 3158, "S", 2.2, 0 }, { 3612, "U", "nameplate1", "WOUND", "", 41, 1 },
+        { 3612, "U", "target", "WOUND", "", 41, 1 }, { 3775, "S", 2.5, 1 }, { 3954, "U", "player", "MISS", "", 0, 1 },
+        { 3954, "U", "targettarget", "MISS", "", 0, 1 }, { 4844, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 4844, "U", "target", "WOUND", "", 30, 1 }, { 5308, "U", "player", "WOUND", "", 12, 1 },
+        { 5308, "U", "targettarget", "WOUND", "", 12, 1 }, { 5404, "S", 2.2, 0 },
+        { 5841, "U", "nameplate1", "WOUND", "", 43, 1 }, { 5841, "U", "target", "WOUND", "", 43, 1 },
+        { 6289, "S", 2.5, 1 }, { 6591, "U", "player", "WOUND", "", 12, 1 },
+        { 6591, "U", "targettarget", "WOUND", "", 12, 1 }, { 7091, "U", "nameplate1", "WOUND", "", 31, 1 },
+        { 7091, "U", "target", "WOUND", "", 31, 1 }, { 7556, "S", 2.2, 0 },
+        { 7958, "U", "player", "WOUND", "", 11, 1 }, { 7958, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 7992, "U", "nameplate1", "WOUND", "", 49, 1 }, { 7992, "U", "target", "WOUND", "", 49, 1 },
+        { 8788, "S", 2.5, 1 }, { 9091, "U", "player", "WOUND", "", 11, 1 },
+        { 9091, "U", "targettarget", "WOUND", "", 11, 1 }, { 9491, "U", "nameplate1", "DODGE", "", 0, 1 },
+        { 9491, "U", "target", "DODGE", "", 0, 1 }, { 9788, "S", 2.2, 0 },
+        { 10308, "U", "nameplate1", "WOUND", "", 49, 1 }, { 10308, "U", "target", "WOUND", "", 49, 1 },
+        { 10458, "U", "player", "WOUND", "", 14, 1 }, { 10458, "U", "targettarget", "WOUND", "", 14, 1 },
+        { 11221, "S", 2.5, 1 }, { 11758, "U", "player", "WOUND", "", 13, 1 },
+        { 11758, "U", "targettarget", "WOUND", "", 13, 1 }, { 11924, "U", "nameplate1", "WOUND", "", 28, 1 },
+        { 11924, "U", "target", "WOUND", "", 28, 1 }, { 11988, "S", 2.2, 0 },
+        { 12122, "U", "nameplate1", "WOUND", "CRITICAL", 91, 1 },
+        { 12122, "U", "softinteract", "WOUND", "CRITICAL", 91, 1 }, { 17786, "C", "player", "OTHER" },
+        { 18518, "S", 2.5, 1 }, { 18785, "S", 2.2, 0 }, { 19221, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 19221, "U", "target", "WOUND", "", 30, 1 }, { 19221, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 19221, "U", "target", "MISS", "", 0, 1 }, { 20339, "U", "player", "WOUND", "", 21, 1 },
+        { 20339, "U", "targettarget", "WOUND", "", 21, 1 }, { 21085, "S", 2.2, 0 }, { 21085, "S", 2.5, 1 },
+        { 21521, "U", "nameplate1", "WOUND", "", 45, 1 }, { 21521, "U", "target", "WOUND", "", 45, 1 },
+        { 22338, "U", "player", "DODGE", "", 0, 1 }, { 22338, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 22771, "U", "nameplate1", "WOUND", "", 25, 1 }, { 22771, "U", "target", "WOUND", "", 25, 1 },
+        { 23251, "S", 2.2, 0 }, { 23635, "S", 2.5, 1 }, { 23788, "U", "nameplate1", "WOUND", "BLOCK_REDUCED", 48, 1 },
+        { 23788, "U", "target", "WOUND", "BLOCK_REDUCED", 48, 1 }, { 24720, "U", "player", "WOUND", "", 17, 1 },
+        { 24720, "U", "targettarget", "WOUND", "", 17, 1 }, { 24938, "U", "nameplate1", "WOUND", "", 26, 1 },
+        { 24938, "U", "target", "WOUND", "", 26, 1 }, { 25401, "S", 2.2, 0 },
+        { 25938, "U", "nameplate1", "WOUND", "", 42, 1 }, { 25938, "U", "target", "WOUND", "", 42, 1 },
+        { 26118, "S", 2.5, 1 }, { 27088, "U", "nameplate1", "WOUND", "CRITICAL", 56, 1 },
+        { 27088, "U", "target", "WOUND", "CRITICAL", 56, 1 }, { 27237, "U", "player", "DODGE", "", 0, 1 },
+        { 27237, "U", "targettarget", "DODGE", "", 0, 1 }, { 27685, "S", 2.2, 0 },
+        { 28138, "U", "nameplate1", "WOUND", "", 39, 1 }, { 28138, "U", "target", "WOUND", "", 39, 1 },
+        { 28635, "S", 2.5, 1 }, { 29204, "U", "player", "WOUND", "", 23, 1 },
+        { 29204, "U", "targettarget", "WOUND", "", 23, 1 }, { 29371, "U", "nameplate1", "WOUND", "", 25, 1 },
+        { 29371, "U", "target", "WOUND", "", 25, 1 }, { 29835, "S", 2.2, 0 },
+        { 30271, "U", "nameplate1", "WOUND", "", 48, 1 }, { 30271, "U", "target", "WOUND", "", 48, 1 },
+        { 31051, "S", 2.5, 1 }, { 31237, "U", "player", "MISS", "", 0, 1 },
+        { 31237, "U", "targettarget", "MISS", "", 0, 1 }, { 31755, "U", "nameplate1", "WOUND", "", 31, 1 },
+        { 31755, "U", "target", "WOUND", "", 31, 1 }, { 32069, "S", 2.2, 0 },
+        { 32505, "U", "nameplate1", "WOUND", "", 43, 1 }, { 32505, "U", "target", "WOUND", "", 43, 1 },
+        { 33237, "U", "player", "DODGE", "", 0, 1 }, { 33237, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 33651, "S", 2.5, 1 }, { 38086, "C", "player", "OTHER" }, { 38935, "S", 2.5, 1 }, { 39086, "S", 2.2, 0 },
+        { 39638, "U", "nameplate1", "WOUND", "", 29, 1 }, { 39638, "U", "target", "WOUND", "", 29, 1 },
+        { 39638, "U", "nameplate1", "WOUND", "", 49, 1 }, { 39638, "U", "target", "WOUND", "", 49, 1 },
+        { 39689, "U", "player", "WOUND", "", 21, 1 }, { 39689, "U", "targettarget", "WOUND", "", 21, 1 },
+        { 41368, "S", 2.2, 0 }, { 41369, "S", 2.5, 1 }, { 41789, "U", "player", "WOUND", "", 19, 1 },
+        { 41789, "U", "targettarget", "WOUND", "", 19, 1 }, { 41905, "U", "nameplate1", "WOUND", "", 48, 1 },
+        { 41905, "U", "target", "WOUND", "", 48, 1 }, { 43055, "U", "nameplate1", "WOUND", "", 28, 1 },
+        { 43055, "U", "target", "WOUND", "", 28, 1 }, { 43585, "S", 2.2, 0 }, { 43935, "S", 2.5, 1 },
+        { 44122, "U", "nameplate1", "WOUND", "", 50, 1 }, { 44122, "U", "target", "WOUND", "", 50, 1 },
+        { 44687, "U", "player", "WOUND", "", 21, 1 }, { 44687, "U", "targettarget", "WOUND", "", 21, 1 },
+        { 45272, "U", "nameplate1", "WOUND", "", 30, 1 }, { 45272, "U", "target", "WOUND", "", 30, 1 },
+        { 45785, "S", 2.2, 0 }, { 46323, "U", "nameplate1", "WOUND", "", 45, 1 },
+        { 46323, "U", "target", "WOUND", "", 45, 1 }, { 46452, "S", 2.5, 1 },
+        { 46621, "U", "player", "WOUND", "", 19, 1 }, { 46621, "U", "targettarget", "WOUND", "", 19, 1 },
+        { 47472, "U", "nameplate1", "WOUND", "", 27, 1 }, { 47472, "U", "target", "WOUND", "", 27, 1 },
+        { 48002, "S", 2.2, 0 }, { 48272, "U", "player", "WOUND", "", 21, 1 },
+        { 48272, "U", "targettarget", "WOUND", "", 21, 1 }, { 48522, "U", "nameplate1", "WOUND", "CRITICAL", 97, 1 },
+        { 48522, "U", "target", "WOUND", "CRITICAL", 97, 1 }, { 48885, "S", 2.5, 1 },
+        { 49689, "U", "nameplate1", "WOUND", "", 30, 1 }, { 49689, "U", "target", "WOUND", "", 30, 1 },
+        { 50202, "S", 2.2, 0 }, { 50638, "U", "nameplate1", "WOUND", "", 45, 1 },
+        { 50638, "U", "target", "WOUND", "", 45, 1 }, { 50671, "U", "player", "WOUND", "", 23, 1 },
+        { 50671, "U", "targettarget", "WOUND", "", 23, 1 }, { 51452, "S", 2.5, 1 },
+        { 52146, "U", "softinteract", "WOUND", "CRITICAL", 48, 1 }, { 58607, "C", "player", "OTHER" },
+        { 59592, "S", 2.5, 1 }, { 59891, "S", 2.2, 0 }, { 59891, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 59891, "U", "target", "MISS", "", 0, 1 }, { 59901, "U", "player", "DODGE", "", 0, 1 },
+        { 59901, "U", "targettarget", "DODGE", "", 0, 1 }, { 60294, "U", "nameplate1", "WOUND", "", 28, 1 },
+        { 60294, "U", "target", "WOUND", "", 28, 1 }, { 61095, "U", "nameplate1", "WOUND", "", 48, 1 },
+        { 61095, "U", "target", "WOUND", "", 48, 1 }, { 61378, "U", "player", "WOUND", "", 12, 1 },
+        { 61378, "U", "targettarget", "WOUND", "", 12, 1 }, { 62091, "S", 2.2, 0 }, { 62091, "S", 2.5, 1 },
+        { 62627, "U", "nameplate1", "WOUND", "", 49, 1 }, { 62628, "U", "target", "WOUND", "", 49, 1 },
+        { 62644, "U", "player", "WOUND", "", 14, 1 }, { 62644, "U", "targettarget", "WOUND", "", 14, 1 },
+        { 63777, "U", "nameplate1", "WOUND", "", 26, 1 }, { 63777, "U", "target", "WOUND", "", 26, 1 },
+        { 63878, "U", "player", "WOUND", "", 13, 1 }, { 63878, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 64291, "S", 2.2, 0 }, { 64641, "S", 2.5, 1 }, { 64728, "U", "nameplate1", "WOUND", "CRITICAL", 100, 1 },
+        { 64728, "U", "target", "WOUND", "CRITICAL", 100, 1 }, { 65278, "U", "player", "WOUND", "", 12, 1 },
+        { 65278, "U", "targettarget", "WOUND", "", 12, 1 }, { 65978, "U", "nameplate1", "WOUND", "", 28, 1 },
+        { 65978, "U", "target", "WOUND", "", 28, 1 }, { 66508, "S", 2.2, 0 },
+        { 66578, "U", "player", "WOUND", "", 12, 1 }, { 66578, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 66944, "U", "nameplate1", "WOUND", "", 38, 1 }, { 66944, "U", "target", "WOUND", "", 38, 1 },
+        { 67141, "S", 2.5, 1 }, { 67794, "U", "player", "WOUND", "", 11, 1 },
+        { 67794, "U", "targettarget", "WOUND", "", 11, 1 }, { 68194, "U", "nameplate1", "WOUND", "", 26, 1 },
+        { 68194, "U", "target", "WOUND", "", 26, 1 }, { 68708, "S", 2.2, 0 },
+        { 69012, "U", "player", "WOUND", "", 12, 1 }, { 69012, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 69178, "U", "nameplate1", "WOUND", "", 50, 1 }, { 69178, "U", "target", "WOUND", "", 50, 1 },
+        { 69641, "S", 2.5, 1 }, { 70394, "U", "nameplate1", "WOUND", "", 31, 1 },
+        { 70395, "U", "target", "WOUND", "", 31, 1 }, { 70909, "S", 2.2, 0 },
+        { 71433, "U", "softinteract", "WOUND", "", 41, 1 }, { 74361, "C", "player", "OTHER" }, { 75361, "S", 2.2, 0 },
+        { 75611, "S", 2.5, 1 }, { 75897, "U", "nameplate1", "WOUND", "", 42, 1 },
+        { 75897, "U", "target", "WOUND", "", 42, 1 }, { 75915, "U", "player", "PARRY", "", 0, 1 },
+        { 76694, "S", 2.2, 0 }, { 77048, "U", "nameplate1", "WOUND", "", 29, 1 },
+        { 77048, "U", "target", "WOUND", "", 29, 1 }, { 77148, "U", "player", "WOUND", "", 11, 1 },
+        { 77148, "U", "targettarget", "WOUND", "", 11, 1 }, { 77781, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 77781, "U", "target", "MISS", "", 0, 1 }, { 78061, "S", 2.5, 1 },
+        { 78531, "U", "player", "WOUND", "", 13, 1 }, { 78531, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 78862, "S", 2.2, 0 }, { 79014, "U", "nameplate1", "WOUND", "", 27, 1 },
+        { 79014, "U", "target", "WOUND", "", 27, 1 }, { 79731, "U", "nameplate1", "WOUND", "CRITICAL", 89, 1 },
+        { 79731, "U", "target", "WOUND", "CRITICAL", 89, 1 }, { 79833, "U", "player", "DODGE", "", 0, 1 },
+        { 79833, "U", "targettarget", "DODGE", "", 0, 1 }, { 80628, "S", 2.5, 1 }, { 81111, "S", 2.2, 0 },
+        { 81148, "U", "player", "WOUND", "", 13, 1 }, { 81148, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 81331, "U", "nameplate1", "WOUND", "", 30, 1 }, { 81331, "U", "target", "WOUND", "", 30, 1 },
+        { 82048, "U", "nameplate1", "MISS", "", 0, 1 }, { 82048, "U", "target", "MISS", "", 0, 1 },
+        { 82398, "U", "player", "DODGE", "", 0, 1 }, { 82398, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 83128, "S", 2.5, 1 }, { 83311, "S", 2.2, 0 }, { 83748, "U", "player", "MISS", "", 0, 1 },
+        { 83748, "U", "targettarget", "MISS", "", 0, 1 }, { 83831, "U", "nameplate1", "WOUND", "", 27, 1 },
+        { 83831, "U", "target", "WOUND", "", 27, 1 }, { 84548, "U", "nameplate1", "WOUND", "", 49, 1 },
+        { 84548, "U", "target", "WOUND", "", 49, 1 }, { 85147, "U", "player", "WOUND", "", 13, 1 },
+        { 85147, "U", "targettarget", "WOUND", "", 13, 1 }, { 85511, "S", 2.2, 0 }, { 85611, "S", 2.5, 1 },
+        { 85611, "U", "nameplate1", "MISS", "", 0, 1 }, { 85611, "U", "target", "MISS", "", 0, 1 },
+        { 85948, "U", "nameplate1", "PARRY", "", 0, 1 }, { 85948, "U", "target", "PARRY", "", 0, 1 },
+        { 86048, "U", "player", "WOUND", "", 11, 1 }, { 86048, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 87198, "U", "nameplate1", "WOUND", "", 27, 1 }, { 87198, "U", "target", "WOUND", "", 27, 1 },
+        { 87498, "U", "player", "WOUND", "", 13, 1 }, { 87498, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 87728, "S", 2.2, 0 }, { 88128, "S", 2.5, 1 }, { 88247, "U", "nameplate1", "PARRY", "", 0, 1 },
+        { 88247, "U", "target", "PARRY", "", 0, 1 }, { 88481, "U", "player", "DODGE", "", 0, 1 },
+        { 88481, "U", "targettarget", "DODGE", "", 0, 1 }, { 89415, "U", "nameplate1", "WOUND", "", 31, 1 },
+        { 89415, "U", "target", "WOUND", "", 31, 1 }, { 89698, "U", "player", "WOUND", "", 12, 1 },
+        { 89698, "U", "targettarget", "WOUND", "", 12, 1 }, { 89928, "S", 2.2, 0 },
+        { 90381, "U", "nameplate1", "WOUND", "", 45, 1 }, { 90381, "U", "target", "WOUND", "", 45, 1 },
+        { 90611, "S", 2.5, 1 }, { 91015, "U", "player", "WOUND", "", 13, 1 },
+        { 91015, "U", "targettarget", "WOUND", "", 13, 1 }, { 91614, "U", "nameplate1", "WOUND", "", 28, 1 },
+        { 91614, "U", "target", "WOUND", "", 28, 1 }, { 92128, "S", 2.2, 0 },
+        { 92582, "U", "softinteract", "WOUND", "", 47, 1 }, { 95362, "C", "player", "OTHER" }, { 96178, "S", 2.2, 0 },
+        { 96495, "S", 2.5, 1 }, { 96715, "U", "nameplate1", "WOUND", "", 41, 1 },
+        { 96715, "U", "target", "WOUND", "", 41, 1 }, { 96899, "U", "player", "WOUND", "", 14, 1 },
+        { 96899, "U", "targettarget", "WOUND", "", 14, 1 }, { 97864, "U", "nameplate1", "DODGE", "", 0, 1 },
+        { 97864, "U", "target", "DODGE", "", 0, 1 }, { 98132, "U", "player", "WOUND", "", 15, 1 },
+        { 98132, "U", "targettarget", "WOUND", "", 15, 1 }, { 98462, "S", 2.2, 0 },
+        { 98915, "U", "nameplate1", "WOUND", "", 39, 1 }, { 98915, "U", "target", "WOUND", "", 39, 1 },
+        { 98995, "S", 2.5, 1 }, { 99502, "U", "player", "PARRY", "", 0, 1 },
+        { 99502, "U", "targettarget", "PARRY", "", 0, 1 }, { 99778, "S", 2.2, 0 },
+        { 100148, "U", "nameplate1", "PARRY", "", 0, 1 }, { 100148, "U", "target", "PARRY", "", 0, 1 },
+        { 100732, "U", "player", "WOUND", "", 11, 1 }, { 100732, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 100882, "U", "nameplate1", "MISS", "", 0, 1 }, { 100882, "U", "target", "MISS", "", 0, 1 },
+        { 101512, "S", 2.5, 1 }, { 101928, "S", 2.2, 0 }, { 102048, "U", "player", "WOUND", "", 13, 1 },
+        { 102049, "U", "targettarget", "WOUND", "", 13, 1 }, { 102215, "U", "nameplate1", "DODGE", "", 0, 1 },
+        { 102215, "U", "target", "DODGE", "", 0, 1 }, { 102934, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 102934, "U", "target", "MISS", "", 0, 1 }, { 103348, "U", "player", "WOUND", "", 12, 1 },
+        { 103348, "U", "targettarget", "WOUND", "", 12, 1 }, { 103962, "S", 2.5, 1 }, { 104128, "S", 2.2, 0 },
+        { 104665, "U", "nameplate1", "WOUND", "CRITICAL", 55, 1 },
+        { 104665, "U", "target", "WOUND", "CRITICAL", 55, 1 }, { 104749, "U", "player", "WOUND", "", 12, 1 },
+        { 104749, "U", "targettarget", "WOUND", "", 12, 1 }, { 105415, "U", "nameplate1", "WOUND", "", 39, 1 },
+        { 105415, "U", "target", "WOUND", "", 39, 1 }, { 105882, "U", "player", "WOUND", "", 15, 1 },
+        { 105882, "U", "targettarget", "WOUND", "", 15, 1 }, { 106379, "S", 2.2, 0 }, { 106512, "S", 2.5, 1 },
+        { 106833, "U", "nameplate1", "WOUND", "", 47, 1 }, { 106833, "U", "target", "WOUND", "", 47, 1 },
+        { 107365, "U", "player", "WOUND", "", 12, 1 }, { 107365, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 108065, "U", "nameplate1", "MISS", "", 0, 1 }, { 108065, "U", "target", "MISS", "", 0, 1 },
+        { 108565, "U", "player", "WOUND", "", 11, 1 }, { 108565, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 108595, "S", 2.2, 0 }, { 109012, "S", 2.5, 1 }, { 109132, "U", "nameplate1", "WOUND", "", 41, 1 },
+        { 109132, "U", "target", "WOUND", "", 41, 1 }, { 109965, "U", "player", "WOUND", "", 13, 1 },
+        { 109965, "U", "targettarget", "WOUND", "", 13, 1 }, { 110282, "U", "nameplate1", "WOUND", "", 31, 1 },
+        { 110282, "U", "target", "WOUND", "", 31, 1 }, { 110795, "S", 2.2, 0 },
+        { 110795, "U", "nameplate1", "MISS", "", 0, 1 }, { 110796, "U", "target", "MISS", "", 0, 1 },
+        { 111099, "U", "player", "WOUND", "", 13, 1 }, { 111099, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 111232, "U", "nameplate1", "WOUND", "", 50, 1 }, { 111232, "U", "target", "WOUND", "", 50, 1 },
+        { 111512, "S", 2.5, 1 }, { 112482, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 112482, "U", "target", "WOUND", "", 30, 1 }, { 112565, "U", "player", "WOUND", "", 13, 1 },
+        { 112565, "U", "targettarget", "WOUND", "", 13, 1 }, { 113012, "S", 2.2, 0 },
+        { 113447, "U", "nameplate1", "WOUND", "", 42, 1 }, { 113447, "U", "target", "WOUND", "", 42, 1 },
+        { 113881, "U", "player", "WOUND", "", 12, 1 }, { 113881, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 114012, "S", 2.5, 1 }, { 114714, "U", "nameplate1", "WOUND", "", 29, 1 },
+        { 114714, "U", "target", "WOUND", "", 29, 1 }, { 116212, "S", 2.2, 0 }, { 116478, "S", 2.5, 1 },
+        { 116581, "U", "nameplate1", "WOUND", "CRITICAL", 52, 1 }, { 116734, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 116734, "U", "softinteract", "MISS", "", 0, 1 },
+    },
+}
diff --git a/tests/Virtual/harness/fixtures/log3.lua b/tests/Virtual/harness/fixtures/log3.lua
new file mode 100644
index 00000000..d3b132a6
--- /dev/null
+++ b/tests/Virtual/harness/fixtures/log3.lua
@@ -0,0 +1,138 @@
+-- tests/Virtual/harness/fixtures/log3.lua: log 3 of docs/research/2026-10-16-group-pairing-captures.md (2026-10-16),
+-- every token row as /vslog recorded it (252 events). A party of two, the same character as log 2 and a partner
+-- (party1). Segment A (0-12272) solo; B (160779-171699) both on the mob (target, nameplate2, softenemy); C
+-- (174816-205518) only the partner, we idle; we rejoin at 205767. The partner's casts arrive with secret IDs, his
+-- spells on our target as school 8 wounds, his on-next-swing strike frames (WOUND 0 + damage, no cast of ours) at
+-- 177249, 184533 and 186966.
+-- Rows: { ms, "S", duration, swingType } PLAYER_SWING; { ms, "U", unit, action, flag, amount, school } UNIT_COMBAT;
+-- { ms, "C", unit, spell } UNIT_SPELLCAST_SUCCEEDED (spell: "STRIKE" on-next-swing, "DOT", "OTHER", "SECRET").
+-- stylua: ignore
+return {
+    damage = { 36, 50, 24, 32 },
+    rows = {
+        { 0, "C", "player", "OTHER" }, { 1003, "S", 2.2, 0 }, { 1286, "S", 2.5, 1 },
+        { 1307, "U", "player", "WOUND", "", 11, 1 }, { 1307, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 1539, "U", "nameplate1", "WOUND", "", 46, 1 }, { 1539, "U", "target", "WOUND", "", 46, 1 },
+        { 2689, "U", "nameplate1", "WOUND", "CRITICAL", 55, 1 }, { 2689, "U", "target", "WOUND", "CRITICAL", 55, 1 },
+        { 2706, "U", "player", "MISS", "", 0, 1 }, { 2706, "U", "targettarget", "MISS", "", 0, 1 },
+        { 3303, "S", 2.2, 0 }, { 3772, "U", "nameplate1", "WOUND", "", 46, 1 },
+        { 3772, "U", "target", "WOUND", "", 46, 1 }, { 3836, "S", 2.5, 1 },
+        { 3837, "U", "nameplate1", "MISS", "", 0, 1 }, { 3837, "U", "target", "MISS", "", 0, 1 },
+        { 4106, "U", "player", "WOUND", "", 14, 1 }, { 4106, "U", "targettarget", "WOUND", "", 14, 1 },
+        { 4993, "U", "nameplate1", "WOUND", "", 26, 1 }, { 4993, "U", "target", "WOUND", "", 26, 1 },
+        { 5240, "U", "player", "WOUND", "", 13, 1 }, { 5240, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 5519, "S", 2.2, 0 }, { 6039, "U", "nameplate1", "WOUND", "", 37, 1 },
+        { 6039, "U", "target", "WOUND", "", 37, 1 }, { 6321, "S", 2.5, 1 },
+        { 6623, "U", "player", "WOUND", "", 12, 1 }, { 6623, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 7205, "U", "nameplate1", "WOUND", "", 28, 1 }, { 7206, "U", "target", "WOUND", "", 28, 1 },
+        { 7719, "S", 2.2, 0 }, { 7823, "U", "player", "MISS", "", 0, 1 },
+        { 7823, "U", "targettarget", "MISS", "", 0, 1 }, { 8239, "U", "nameplate1", "WOUND", "", 43, 1 },
+        { 8239, "U", "target", "WOUND", "", 43, 1 }, { 8769, "S", 2.5, 1 },
+        { 9173, "U", "player", "WOUND", "", 11, 1 }, { 9173, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 9473, "U", "nameplate1", "WOUND", "CRITICAL", 59, 1 }, { 9473, "U", "target", "WOUND", "CRITICAL", 59, 1 },
+        { 9919, "S", 2.2, 0 }, { 10373, "U", "nameplate1", "WOUND", "", 39, 1 },
+        { 10373, "U", "target", "WOUND", "", 39, 1 }, { 10472, "U", "player", "WOUND", "", 12, 1 },
+        { 10472, "U", "targettarget", "WOUND", "", 12, 1 }, { 11286, "S", 2.5, 1 },
+        { 11989, "U", "nameplate1", "WOUND", "", 29, 1 }, { 11989, "U", "target", "WOUND", "", 29, 1 },
+        { 12119, "S", 2.2, 0 }, { 12272, "U", "nameplate1", "WOUND", "", 44, 1 },
+        { 12272, "U", "softinteract", "WOUND", "", 44, 1 }, { 26446, "C", "player", "OTHER" },
+        { 30196, "C", "player", "OTHER" }, { 33996, "C", "player", "OTHER" }, { 37898, "C", "player", "OTHER" },
+        { 49873, "C", "party1", "SECRET" }, { 52806, "C", "party1", "SECRET" }, { 54190, "C", "party1", "SECRET" },
+        { 55742, "C", "party1", "SECRET" }, { 57176, "C", "party1", "SECRET" },
+        { 57177, "U", "party1", "WOUND", "", 20, 1 }, { 58609, "C", "party1", "SECRET" },
+        { 59192, "U", "party1", "WOUND", "", 22, 1 }, { 60675, "C", "party1", "SECRET" },
+        { 61192, "U", "party1", "WOUND", "", 17, 1 }, { 62692, "C", "party1", "SECRET" },
+        { 63209, "U", "party1", "WOUND", "", 20, 1 }, { 64692, "C", "party1", "SECRET" },
+        { 65063, "C", "player", "OTHER" }, { 67541, "C", "party1", "SECRET" }, { 73145, "C", "player", "OTHER" },
+        { 76002, "C", "party1", "SECRET" }, { 78902, "C", "party1", "SECRET" },
+        { 79118, "U", "party1", "WOUND", "", 17, 1 }, { 80602, "C", "party1", "SECRET" },
+        { 81035, "U", "party1", "MISS", "", 0, 1 }, { 82018, "C", "party1", "SECRET" },
+        { 83052, "U", "party1", "WOUND", "", 16, 1 }, { 84535, "C", "party1", "SECRET" },
+        { 85142, "U", "party1", "WOUND", "", 20, 1 }, { 86609, "C", "party1", "SECRET" },
+        { 89710, "C", "party1", "SECRET" }, { 94034, "U", "party1", "HEAL", "", 19, 1 },
+        { 97036, "U", "party1", "HEAL", "", 18, 1 }, { 100036, "U", "party1", "HEAL", "", 19, 1 },
+        { 103036, "U", "party1", "HEAL", "", 18, 1 }, { 160779, "C", "party1", "SECRET" },
+        { 160779, "C", "nameplate1", "SECRET" }, { 162196, "U", "nameplate2", "WOUND", "", 37, 8 },
+        { 162196, "U", "target", "WOUND", "", 37, 8 }, { 162196, "U", "softenemy", "WOUND", "", 37, 8 },
+        { 162197, "C", "party1", "SECRET" }, { 162197, "C", "nameplate1", "SECRET" },
+        { 162197, "C", "targettarget", "SECRET" }, { 163596, "U", "nameplate2", "WOUND", "", 38, 8 },
+        { 163596, "U", "target", "WOUND", "", 38, 8 }, { 163596, "U", "softenemy", "WOUND", "", 38, 8 },
+        { 164665, "U", "party1", "WOUND", "", 13, 1 }, { 164665, "U", "nameplate1", "WOUND", "", 13, 1 },
+        { 164665, "U", "targettarget", "WOUND", "", 13, 1 }, { 165116, "S", 2.2, 0 },
+        { 165123, "U", "nameplate2", "WOUND", "GLANCING", 4, 1 },
+        { 165124, "U", "target", "WOUND", "GLANCING", 4, 1 }, { 165169, "U", "nameplate2", "MISS", "", 0, 1 },
+        { 165169, "U", "target", "MISS", "", 0, 1 }, { 165382, "S", 2.5, 1 },
+        { 165485, "U", "nameplate2", "WOUND", "", 50, 1 }, { 165485, "U", "target", "WOUND", "", 50, 1 },
+        { 166752, "U", "nameplate2", "WOUND", "", 26, 1 }, { 166752, "U", "target", "WOUND", "", 26, 1 },
+        { 166835, "U", "party1", "MISS", "", 0, 1 }, { 166835, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 166835, "U", "targettarget", "MISS", "", 0, 1 }, { 167366, "S", 2.2, 0 },
+        { 167552, "U", "nameplate2", "WOUND", "GLANCING", 3, 1 },
+        { 167552, "U", "target", "WOUND", "GLANCING", 3, 1 }, { 167835, "U", "nameplate2", "WOUND", "", 49, 1 },
+        { 167835, "U", "target", "WOUND", "", 49, 1 }, { 167899, "S", 2.5, 1 },
+        { 168719, "U", "player", "DODGE", "", 0, 1 }, { 168719, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 169052, "U", "nameplate2", "WOUND", "", 30, 1 }, { 169052, "U", "target", "WOUND", "", 30, 1 },
+        { 169466, "S", 2.2, 0 }, { 169901, "U", "nameplate2", "WOUND", "", 43, 1 },
+        { 169902, "U", "target", "WOUND", "", 43, 1 }, { 170102, "U", "nameplate2", "WOUND", "GLANCING", 1, 1 },
+        { 170102, "U", "target", "WOUND", "GLANCING", 1, 1 }, { 170416, "S", 2.5, 1 },
+        { 170819, "U", "player", "WOUND", "", 12, 1 }, { 170819, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 171152, "U", "nameplate2", "WOUND", "", 25, 1 }, { 171152, "U", "target", "WOUND", "", 25, 1 },
+        { 171699, "S", 2.2, 0 }, { 174816, "C", "party1", "SECRET" }, { 174816, "C", "nameplate1", "SECRET" },
+        { 175219, "U", "party1", "WOUND", "", 18, 1 }, { 175219, "U", "nameplate1", "WOUND", "", 18, 1 },
+        { 177249, "U", "nameplate2", "WOUND", "", 0, 1 }, { 177250, "U", "nameplate2", "WOUND", "", 36, 1 },
+        { 177352, "U", "party1", "WOUND", "", 14, 1 }, { 177352, "U", "nameplate1", "WOUND", "", 14, 1 },
+        { 179319, "U", "party1", "WOUND", "", 16, 1 }, { 179319, "U", "nameplate1", "WOUND", "", 16, 1 },
+        { 180185, "U", "nameplate2", "WOUND", "GLANCING", 5, 1 }, { 181453, "U", "party1", "DODGE", "", 0, 1 },
+        { 181453, "U", "nameplate1", "DODGE", "", 0, 1 }, { 182099, "U", "nameplate2", "DODGE", "", 0, 1 },
+        { 183452, "U", "party1", "WOUND", "", 19, 1 }, { 183452, "U", "nameplate1", "WOUND", "", 19, 1 },
+        { 184533, "U", "nameplate2", "WOUND", "", 0, 1 }, { 184533, "U", "nameplate2", "WOUND", "", 38, 1 },
+        { 185335, "U", "party1", "WOUND", "", 16, 1 }, { 185335, "U", "nameplate1", "WOUND", "", 16, 1 },
+        { 186966, "U", "nameplate2", "WOUND", "", 0, 1 }, { 186966, "U", "nameplate2", "WOUND", "", 40, 1 },
+        { 187352, "U", "party1", "WOUND", "", 16, 1 }, { 187352, "U", "nameplate1", "WOUND", "", 16, 1 },
+        { 189319, "U", "party1", "WOUND", "", 14, 1 }, { 189319, "U", "nameplate1", "WOUND", "", 14, 1 },
+        { 189902, "U", "nameplate2", "MISS", "", 0, 1 }, { 191352, "U", "party1", "WOUND", "", 15, 1 },
+        { 191352, "U", "nameplate1", "WOUND", "", 15, 1 }, { 192470, "U", "nameplate2", "DODGE", "", 0, 1 },
+        { 193486, "U", "party1", "WOUND", "", 15, 1 }, { 193486, "U", "nameplate1", "WOUND", "", 15, 1 },
+        { 194769, "U", "nameplate2", "WOUND", "GLANCING", 3, 1 }, { 195486, "U", "party1", "WOUND", "", 14, 1 },
+        { 195486, "U", "nameplate1", "WOUND", "", 14, 1 }, { 196683, "U", "nameplate2", "PARRY", "", 0, 1 },
+        { 197502, "U", "party1", "WOUND", "", 19, 1 }, { 197502, "U", "nameplate1", "WOUND", "", 19, 1 },
+        { 199101, "U", "nameplate2", "PARRY", "", 0, 1 }, { 199372, "U", "party1", "WOUND", "", 15, 1 },
+        { 199373, "U", "nameplate1", "WOUND", "", 15, 1 }, { 200572, "U", "party1", "WOUND", "", 17, 1 },
+        { 200572, "U", "nameplate1", "WOUND", "", 17, 1 }, { 201568, "U", "nameplate2", "PARRY", "", 0, 1 },
+        { 202338, "U", "party1", "WOUND", "", 18, 1 }, { 202338, "U", "nameplate1", "WOUND", "", 18, 1 },
+        { 204388, "U", "party1", "WOUND", "", 16, 1 }, { 204388, "U", "nameplate1", "WOUND", "", 16, 1 },
+        { 205518, "U", "nameplate2", "PARRY", "", 0, 1 }, { 205767, "S", 2.2, 0 },
+        { 206188, "U", "party1", "WOUND", "", 17, 1 }, { 206188, "U", "nameplate1", "WOUND", "", 17, 1 },
+        { 206188, "U", "targettarget", "WOUND", "", 17, 1 }, { 206289, "U", "nameplate2", "WOUND", "", 43, 1 },
+        { 206289, "U", "target", "WOUND", "", 43, 1 }, { 206934, "S", 2.5, 1 }, { 207169, "C", "player", "OTHER" },
+        { 207169, "U", "nameplate2", "WOUND", "", 4, 1 }, { 207169, "U", "target", "WOUND", "", 4, 1 },
+        { 207884, "U", "nameplate2", "DODGE", "", 0, 1 }, { 207885, "U", "target", "DODGE", "", 0, 1 },
+        { 207885, "S", 2.2, 0 }, { 207920, "U", "nameplate2", "WOUND", "", 27, 1 },
+        { 207920, "U", "target", "WOUND", "", 27, 1 }, { 207985, "C", "player", "OTHER" },
+        { 208272, "U", "party1", "WOUND", "", 17, 1 }, { 208272, "U", "nameplate1", "WOUND", "", 17, 1 },
+        { 208272, "U", "targettarget", "WOUND", "", 17, 1 }, { 208904, "U", "nameplate2", "WOUND", "", 39, 1 },
+        { 208905, "U", "target", "WOUND", "", 39, 1 }, { 209502, "S", 2.5, 1 }, { 210152, "S", 2.2, 0 },
+        { 210206, "U", "nameplate2", "WOUND", "", 30, 1 }, { 210206, "U", "target", "WOUND", "", 30, 1 },
+        { 210206, "U", "nameplate2", "WOUND", "", 36, 1 }, { 210206, "U", "target", "WOUND", "", 36, 1 },
+        { 210323, "U", "party1", "WOUND", "", 18, 1 }, { 210323, "U", "nameplate1", "WOUND", "", 18, 1 },
+        { 210323, "U", "targettarget", "WOUND", "", 18, 1 }, { 210386, "U", "nameplate2", "DODGE", "", 0, 1 },
+        { 210386, "U", "target", "DODGE", "", 0, 1 }, { 211936, "S", 2.5, 1 },
+        { 212339, "U", "party1", "WOUND", "", 15, 1 }, { 212339, "U", "nameplate1", "WOUND", "", 15, 1 },
+        { 212339, "U", "targettarget", "WOUND", "", 15, 1 }, { 212369, "S", 2.2, 0 },
+        { 212503, "U", "nameplate2", "WOUND", "", 47, 1 }, { 212624, "U", "nameplate2", "MISS", "", 0, 1 },
+        { 216141, "C", "player", "OTHER" }, { 216360, "U", "party1", "HEAL", "", 19, 1 },
+        { 216360, "U", "nameplate1", "HEAL", "", 19, 1 }, { 216761, "U", "party1", "HEAL", "", 102, 1 },
+        { 216761, "U", "nameplate1", "HEAL", "", 102, 1 }, { 216761, "C", "party1", "SECRET" },
+        { 216761, "C", "nameplate1", "SECRET" }, { 219327, "C", "party1", "SECRET" },
+        { 219327, "C", "nameplate1", "SECRET" }, { 219328, "U", "party1", "HEAL", "", 19, 1 },
+        { 219328, "U", "nameplate1", "HEAL", "", 19, 1 }, { 219760, "U", "party1", "HEAL", "", 15, 1 },
+        { 219760, "U", "nameplate1", "HEAL", "", 15, 1 }, { 222277, "U", "party1", "HEAL", "", 19, 1 },
+        { 222277, "U", "nameplate1", "HEAL", "", 19, 1 }, { 222678, "U", "party1", "HEAL", "", 15, 1 },
+        { 222678, "U", "nameplate1", "HEAL", "", 15, 1 }, { 225347, "U", "party1", "HEAL", "CRITICAL", 28, 1 },
+        { 225347, "U", "nameplate1", "HEAL", "CRITICAL", 28, 1 }, { 225731, "U", "party1", "HEAL", "", 16, 1 },
+        { 225731, "U", "nameplate1", "HEAL", "", 16, 1 }, { 228748, "U", "party1", "HEAL", "", 15, 1 },
+        { 228748, "U", "nameplate1", "HEAL", "", 15, 1 }, { 231764, "U", "party1", "HEAL", "", 15, 1 },
+        { 231764, "U", "nameplate1", "HEAL", "", 15, 1 }, { 234764, "U", "party1", "HEAL", "", 16, 1 },
+        { 234764, "U", "nameplate1", "HEAL", "", 16, 1 }, { 237668, "U", "party1", "HEAL", "", 15, 1 },
+        { 237668, "U", "nameplate1", "HEAL", "", 15, 1 },
+    },
+}
diff --git a/tests/Virtual/harness/fixtures/log5.lua b/tests/Virtual/harness/fixtures/log5.lua
new file mode 100644
index 00000000..c403174b
--- /dev/null
+++ b/tests/Virtual/harness/fixtures/log5.lua
@@ -0,0 +1,135 @@
+-- tests/Virtual/harness/fixtures/log5.lua: G5 of docs/research/2026-10-16-group-pairing-captures.md (2026-10-16), every
+-- token row as /vslog recorded it (245 events). Solo, dual wield (main 2.2 s, off 2.5 s), auto-attack only, about 88 s:
+-- the off hand's two landing references; the on-swing proc (a school-32 WOUND on the target and a HEAL on us in the
+-- same ms, 1-2 ms after a PLAYER_SWING) at 37174 and 68467. `damage`: the session's plain amount bands (main 40-56, off
+-- 27-36), the off minimum at 26 for its crit 53 (26.5 halved).
+-- Rows: { ms, "S", duration, swingType } PLAYER_SWING; { ms, "U", unit, action, flag, amount, school } UNIT_COMBAT;
+-- { ms, "C", unit, spell } UNIT_SPELLCAST_SUCCEEDED (spell: "STRIKE" on-next-swing, "DOT", "OTHER", "SECRET").
+-- stylua: ignore
+return {
+    damage = { 40, 56, 26, 36 },
+    rows = {
+        { 0, "S", 2.5, 1 }, { 328, "S", 2.2, 0 }, { 699, "U", "nameplate1", "WOUND", "", 28, 1 },
+        { 699, "U", "target", "WOUND", "", 28, 1 }, { 699, "U", "nameplate1", "WOUND", "", 56, 1 },
+        { 699, "U", "target", "WOUND", "", 56, 1 }, { 915, "U", "player", "MISS", "", 0, 1 },
+        { 915, "U", "targettarget", "MISS", "", 0, 1 }, { 2528, "S", 2.2, 0 }, { 2529, "S", 2.5, 1 },
+        { 2932, "U", "player", "WOUND", "", 19, 1 }, { 2932, "U", "targettarget", "WOUND", "", 19, 1 },
+        { 2981, "U", "nameplate1", "WOUND", "", 46, 1 }, { 2981, "U", "target", "WOUND", "", 46, 1 },
+        { 4215, "U", "nameplate1", "MISS", "", 0, 1 }, { 4215, "U", "target", "MISS", "", 0, 1 },
+        { 4728, "S", 2.2, 0 }, { 4865, "U", "player", "WOUND", "", 23, 1 },
+        { 4865, "U", "targettarget", "WOUND", "", 23, 1 }, { 5095, "S", 2.5, 1 },
+        { 5164, "U", "nameplate1", "MISS", "", 0, 1 }, { 5165, "U", "target", "MISS", "", 0, 1 },
+        { 6414, "U", "nameplate1", "WOUND", "", 32, 1 }, { 6414, "U", "target", "WOUND", "", 32, 1 },
+        { 6798, "U", "player", "PARRY", "", 0, 1 }, { 6799, "U", "targettarget", "PARRY", "", 0, 1 },
+        { 6895, "S", 2.2, 0 }, { 7331, "U", "nameplate1", "WOUND", "", 44, 1 },
+        { 7331, "U", "target", "WOUND", "", 44, 1 }, { 7595, "S", 2.5, 1 },
+        { 8581, "U", "nameplate1", "WOUND", "", 29, 1 }, { 8581, "U", "target", "WOUND", "", 29, 1 },
+        { 8911, "S", 2.2, 0 }, { 8932, "U", "player", "PARRY", "", 0, 1 },
+        { 8932, "U", "targettarget", "PARRY", "", 0, 1 }, { 9432, "U", "nameplate1", "WOUND", "", 50, 1 },
+        { 9432, "U", "target", "WOUND", "", 50, 1 }, { 10095, "S", 2.5, 1 },
+        { 10131, "U", "player", "WOUND", "", 19, 1 }, { 10131, "U", "targettarget", "WOUND", "", 19, 1 },
+        { 10798, "U", "nameplate1", "PARRY", "", 0, 1 }, { 10798, "U", "target", "PARRY", "", 0, 1 },
+        { 11148, "U", "player", "WOUND", "", 20, 1 }, { 11148, "U", "targettarget", "WOUND", "", 20, 1 },
+        { 11178, "S", 2.2, 0 }, { 11631, "U", "nameplate1", "WOUND", "", 56, 1 },
+        { 11631, "U", "target", "WOUND", "", 56, 1 }, { 12165, "U", "player", "WOUND", "", 20, 1 },
+        { 12165, "U", "targettarget", "WOUND", "", 20, 1 }, { 12512, "S", 2.5, 1 },
+        { 13181, "U", "player", "WOUND", "", 19, 1 }, { 13181, "U", "targettarget", "WOUND", "", 19, 1 },
+        { 13215, "U", "nameplate1", "WOUND", "", 35, 1 }, { 13215, "U", "target", "WOUND", "", 35, 1 },
+        { 13378, "S", 2.2, 0 }, { 13934, "U", "nameplate1", "WOUND", "", 47, 1 },
+        { 13934, "U", "target", "WOUND", "", 47, 1 }, { 14915, "U", "player", "WOUND", "", 20, 1 },
+        { 14915, "U", "targettarget", "WOUND", "", 20, 1 }, { 15011, "S", 2.5, 1 }, { 15595, "S", 2.2, 0 },
+        { 15705, "U", "nameplate1", "WOUND", "", 33, 1 }, { 15705, "U", "softinteract", "WOUND", "", 33, 1 },
+        { 15752, "U", "nameplate1", "WOUND", "", 48, 1 }, { 15752, "U", "softinteract", "WOUND", "", 48, 1 },
+        { 24323, "S", 2.2, 0 }, { 24656, "S", 2.5, 1 }, { 24859, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 24859, "U", "target", "MISS", "", 0, 1 }, { 25527, "U", "player", "WOUND", "", 11, 1 },
+        { 25527, "U", "targettarget", "WOUND", "", 11, 1 }, { 26009, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 26009, "U", "target", "MISS", "", 0, 1 }, { 26623, "S", 2.2, 0 },
+        { 26743, "U", "player", "DODGE", "", 0, 1 }, { 26743, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 27059, "U", "nameplate1", "MISS", "", 0, 1 }, { 27060, "U", "target", "MISS", "", 0, 1 },
+        { 27156, "S", 2.5, 1 }, { 28160, "U", "player", "WOUND", "", 14, 1 },
+        { 28160, "U", "targettarget", "WOUND", "", 14, 1 }, { 28310, "U", "nameplate1", "WOUND", "", 33, 1 },
+        { 28311, "U", "target", "WOUND", "", 33, 1 }, { 28756, "S", 2.2, 0 },
+        { 29293, "U", "nameplate1", "MISS", "", 0, 1 }, { 29293, "U", "target", "MISS", "", 0, 1 },
+        { 29393, "U", "player", "WOUND", "", 11, 1 }, { 29393, "U", "targettarget", "WOUND", "", 11, 1 },
+        { 29656, "S", 2.5, 1 }, { 30442, "U", "nameplate1", "WOUND", "CRITICAL", 66, 1 },
+        { 30443, "U", "target", "WOUND", "CRITICAL", 66, 1 }, { 30760, "U", "player", "WOUND", "", 11, 1 },
+        { 30760, "U", "targettarget", "WOUND", "", 11, 1 }, { 31040, "S", 2.2, 0 },
+        { 31476, "U", "nameplate1", "WOUND", "", 51, 1 }, { 31476, "U", "target", "WOUND", "", 51, 1 },
+        { 31894, "U", "player", "DODGE", "", 0, 1 }, { 31894, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 32173, "S", 2.5, 1 }, { 32876, "U", "nameplate1", "DODGE", "", 0, 1 },
+        { 32876, "U", "target", "DODGE", "", 0, 1 }, { 33206, "S", 2.2, 0 },
+        { 33360, "U", "player", "WOUND", "", 13, 1 }, { 33360, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 33644, "U", "nameplate1", "WOUND", "", 45, 1 }, { 33644, "U", "target", "WOUND", "", 45, 1 },
+        { 34576, "U", "player", "WOUND", "", 13, 1 }, { 34576, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 34673, "S", 2.5, 1 }, { 35376, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 35376, "U", "target", "WOUND", "", 30, 1 }, { 35456, "S", 2.2, 0 },
+        { 35876, "U", "player", "DODGE", "", 0, 1 }, { 35876, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 36192, "U", "nameplate1", "WOUND", "", 45, 1 }, { 36193, "U", "target", "WOUND", "", 45, 1 },
+        { 37173, "S", 2.5, 1 }, { 37174, "U", "nameplate1", "WOUND", "", 36, 32 },
+        { 37174, "U", "target", "WOUND", "", 36, 32 }, { 37174, "U", "player", "HEAL", "", 36, 1 },
+        { 37174, "U", "targettarget", "HEAL", "", 36, 1 }, { 37661, "S", 2.2, 0 },
+        { 37863, "U", "player", "DODGE", "", 0, 1 }, { 37863, "U", "targettarget", "DODGE", "", 0, 1 },
+        { 37864, "U", "nameplate1", "WOUND", "", 34, 1 }, { 37864, "U", "target", "WOUND", "", 34, 1 },
+        { 38398, "U", "player", "WOUND", "", 12, 1 }, { 38398, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 38664, "U", "nameplate1", "MISS", "", 0, 1 }, { 38664, "U", "target", "MISS", "", 0, 1 },
+        { 39694, "S", 2.5, 1 }, { 39731, "U", "player", "PARRY", "", 0, 1 }, { 39861, "S", 2.2, 0 },
+        { 40028, "U", "nameplate1", "WOUND", "CRITICAL", 105, 1 },
+        { 40028, "U", "softinteract", "WOUND", "CRITICAL", 105, 1 },
+        { 40398, "U", "softinteract", "WOUND", "", 33, 1 }, { 49833, "S", 2.2, 0 }, { 50083, "S", 2.5, 1 },
+        { 50269, "U", "nameplate1", "WOUND", "BLOCK_REDUCED", 45, 1 },
+        { 50269, "U", "target", "WOUND", "BLOCK_REDUCED", 45, 1 }, { 50269, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 50270, "U", "target", "WOUND", "", 30, 1 }, { 50500, "U", "player", "WOUND", "", 20, 1 },
+        { 50500, "U", "targettarget", "WOUND", "", 20, 1 }, { 52028, "S", 2.2, 0 },
+        { 52465, "U", "nameplate1", "WOUND", "", 51, 1 }, { 52465, "U", "target", "WOUND", "", 51, 1 },
+        { 52532, "U", "player", "WOUND", "", 22, 1 }, { 52532, "U", "targettarget", "WOUND", "", 22, 1 },
+        { 52595, "S", 2.5, 1 }, { 53681, "U", "nameplate1", "DODGE", "", 0, 1 },
+        { 53681, "U", "target", "DODGE", "", 0, 1 }, { 54228, "S", 2.2, 0 },
+        { 54229, "U", "player", "WOUND", "", 22, 1 }, { 54229, "U", "targettarget", "WOUND", "", 22, 1 },
+        { 54681, "U", "nameplate1", "WOUND", "", 47, 1 }, { 54681, "U", "target", "WOUND", "", 47, 1 },
+        { 54847, "U", "player", "WOUND", "", 17, 1 }, { 54847, "U", "targettarget", "WOUND", "", 17, 1 },
+        { 55078, "S", 2.5, 1 }, { 55914, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 55914, "U", "target", "WOUND", "", 30, 1 }, { 56445, "S", 2.2, 0 },
+        { 56515, "U", "player", "WOUND", "", 21, 1 }, { 56515, "U", "targettarget", "WOUND", "", 21, 1 },
+        { 56981, "U", "nameplate1", "WOUND", "", 41, 1 }, { 56981, "U", "target", "WOUND", "", 41, 1 },
+        { 57495, "S", 2.5, 1 }, { 58200, "U", "nameplate1", "WOUND", "", 27, 1 },
+        { 58201, "U", "target", "WOUND", "", 27, 1 }, { 58515, "U", "player", "MISS", "", 0, 1 },
+        { 58515, "U", "targettarget", "MISS", "", 0, 1 }, { 58595, "S", 2.2, 0 },
+        { 59066, "U", "nameplate1", "WOUND", "CRITICAL", 99, 1 },
+        { 59066, "U", "target", "WOUND", "CRITICAL", 99, 1 }, { 60595, "S", 2.5, 1 }, { 60761, "S", 2.2, 0 },
+        { 61298, "U", "nameplate1", "WOUND", "", 29, 1 }, { 61298, "U", "target", "WOUND", "", 29, 1 },
+        { 61298, "U", "nameplate1", "MISS", "", 0, 1 }, { 61298, "U", "target", "MISS", "", 0, 1 },
+        { 63061, "S", 2.2, 0 }, { 63584, "U", "target", "WOUND", "", 40, 1 },
+        { 63584, "U", "softinteract", "WOUND", "", 40, 1 }, { 68465, "S", 2.2, 0 },
+        { 68467, "U", "nameplate1", "WOUND", "", 36, 32 }, { 68467, "U", "target", "WOUND", "", 36, 32 },
+        { 68467, "U", "player", "HEAL", "", 36, 1 }, { 68467, "U", "targettarget", "HEAL", "", 36, 1 },
+        { 68698, "S", 2.5, 1 }, { 68901, "U", "nameplate1", "WOUND", "", 40, 1 },
+        { 68901, "U", "target", "WOUND", "", 40, 1 }, { 69585, "U", "player", "WOUND", "", 13, 1 },
+        { 69585, "U", "targettarget", "WOUND", "", 13, 1 }, { 70151, "U", "nameplate1", "WOUND", "", 30, 1 },
+        { 70151, "U", "target", "WOUND", "", 30, 1 }, { 70715, "S", 2.2, 0 },
+        { 70918, "U", "player", "MISS", "", 0, 1 }, { 70918, "U", "targettarget", "MISS", "", 0, 1 },
+        { 71169, "U", "nameplate1", "WOUND", "", 45, 1 }, { 71169, "U", "target", "WOUND", "", 45, 1 },
+        { 71281, "S", 2.5, 1 }, { 72302, "U", "player", "WOUND", "", 15, 1 },
+        { 72302, "U", "targettarget", "WOUND", "", 15, 1 }, { 72402, "U", "nameplate1", "MISS", "", 0, 1 },
+        { 72402, "U", "target", "MISS", "", 0, 1 }, { 72914, "S", 2.2, 0 },
+        { 73435, "U", "nameplate1", "DODGE", "", 0, 1 }, { 73435, "U", "target", "DODGE", "", 0, 1 },
+        { 73601, "U", "player", "MISS", "", 0, 1 }, { 73601, "U", "targettarget", "MISS", "", 0, 1 },
+        { 73714, "S", 2.5, 1 }, { 74601, "U", "nameplate1", "WOUND", "CRITICAL", 53, 1 },
+        { 74601, "U", "target", "WOUND", "CRITICAL", 53, 1 }, { 74885, "U", "player", "WOUND", "", 12, 1 },
+        { 74885, "U", "targettarget", "WOUND", "", 12, 1 }, { 75114, "S", 2.2, 0 },
+        { 75568, "U", "nameplate1", "WOUND", "", 45, 1 }, { 75568, "U", "target", "WOUND", "", 45, 1 },
+        { 76153, "U", "player", "WOUND", "", 13, 1 }, { 76153, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 76298, "S", 2.5, 1 }, { 77001, "U", "nameplate1", "WOUND", "", 27, 1 },
+        { 77001, "U", "target", "WOUND", "", 27, 1 }, { 77314, "S", 2.2, 0 },
+        { 77501, "U", "player", "WOUND", "", 13, 1 }, { 77501, "U", "targettarget", "WOUND", "", 13, 1 },
+        { 77768, "U", "nameplate1", "WOUND", "", 51, 1 }, { 77768, "U", "target", "WOUND", "", 51, 1 },
+        { 78718, "U", "player", "WOUND", "", 12, 1 }, { 78718, "U", "targettarget", "WOUND", "", 12, 1 },
+        { 78798, "S", 2.5, 1 }, { 79501, "U", "nameplate1", "WOUND", "", 32, 1 },
+        { 79501, "U", "target", "WOUND", "", 32, 1 }, { 79514, "S", 2.2, 0 },
+        { 80118, "U", "player", "WOUND", "", 15, 1 }, { 80118, "U", "targettarget", "WOUND", "", 15, 1 },
+        { 80319, "U", "nameplate1", "WOUND", "", 45, 1 }, { 80319, "U", "target", "WOUND", "", 45, 1 },
+        { 81214, "S", 2.5, 1 }, { 81921, "U", "nameplate1", "WOUND", "", 32, 1 },
+        { 81921, "U", "target", "WOUND", "", 32, 1 }, { 87348, "S", 2.5, 1 },
+        { 88039, "U", "target", "WOUND", "CRITICAL", 58, 1 },
+        { 88039, "U", "softinteract", "WOUND", "CRITICAL", 58, 1 },
+    },
+}
diff --git a/tests/Virtual/harness/fixtures_spec.lua b/tests/Virtual/harness/fixtures_spec.lua
new file mode 100644
index 00000000..aa53059f
--- /dev/null
+++ b/tests/Virtual/harness/fixtures_spec.lua
@@ -0,0 +1,114 @@
+-- tests/Virtual/harness/fixtures_spec.lua (harness design §3.5): every pasted log is a fixture, and the model's
+-- defaults are fitted on the solo dual-wield logs (log 2, G5): the landing lags, the off hand's two references, the
+-- avoid and crit rates, the amount envelope; and on every log, the order the client fires the tokens of one outcome. A
+-- fit outside tolerance fails, and the defaults are retuned in the same change.
+local drive = require("Virtual.harness.drive")
+local observer = require("Virtual.harness.observer")
+local behaviours = require("Virtual.harness.behaviours")
+
+local K, RATES = observer.DEFAULTS, behaviours.RATES
+local CORE = { 0.43, 0.56 } -- the main hand's measured band (log 2's 435-552, G5's 436-556)
+
+-- The log's own statistics: one row per outcome on the target; a white wound's hand by amount (a crit halved), the
+-- lags of each hand, the off hand's reference (own swing within 30 ms of 0.703 s, the latest main swing at or before it
+-- within 30 ms of 1.686 s, the main hit's frame, else the tail).
+local function fit(fix)
+    local s = drive.fixtureStream(fix, 10, true)
+    local d = fix.damage
+    local split = (d[4] + d[1]) / 2
+    local f =
+        { main = {}, own = {}, mref = {}, off = 0, frame = 0, swings = 0, avoids = 0, wounds = 0, crits = 0, out = 0 }
+    local last, mainBefore, lastMainWound = { 0, 0 }, 0, -1
+    for i = 1, s.n do
+        local ev, t = s.ev[i], s.t[i]
+        if ev == "PLAYER_SWING" then
+            local h = s.a2[i] + 1
+            last[h], f.swings = t, f.swings + 1
+            if h == 2 then
+                mainBefore = last[1]
+            end
+        elseif ev == "UNIT_COMBAT" and s.a5[i] == 1 then
+            local act, flag, amount = s.a2[i], s.a3[i], s.a4[i]
+            local a = flag == "CRITICAL" and amount / 2 or amount
+            if act == "WOUND" and a >= 0.6 * d[3] then
+                f.wounds, f.crits = f.wounds + 1, f.crits + (flag == "CRITICAL" and 1 or 0)
+                local h = a > split and 1 or 2
+                local lo, hi = d[2 * h - 1], d[2 * h]
+                if a < (flag == "BLOCK_REDUCED" and 0 or lo) or a > hi then
+                    f.out = f.out + 1
+                end
+                if h == 1 then
+                    f.main[#f.main + 1], lastMainWound = t - last[1], t
+                else
+                    f.off = f.off + 1
+                    if math.abs(t - last[2] - K.off.own) <= 0.03 then
+                        f.own[#f.own + 1] = t - last[2]
+                    elseif math.abs(t - mainBefore - K.off.main) <= 0.03 then
+                        f.mref[#f.mref + 1] = t - mainBefore
+                    elseif math.abs(t - lastMainWound) <= 0.0015 then
+                        f.frame = f.frame + 1
+                    end
+                end
+            elseif act == "MISS" or act == "DODGE" or act == "PARRY" then
+                f.avoids = f.avoids + 1
+            end
+        end
+    end
+    return f
+end
+
+local function median(list)
+    table.sort(list)
+    return list[math.floor((#list + 1) / 2)]
+end
+
+local function near(want, got, tol, what)
+    assert.is_true(math.abs(want - got) <= tol, ("%s: want %.3f +- %.3f, got %.3f"):format(what, want, tol, got))
+end
+
+describe("the fixtures and the model's fit", function()
+    for _, name in ipairs({ "log2", "log5" }) do
+        it("fits the observer's and behaviours' defaults to " .. name, function()
+            local f = fit(require("Virtual.harness.fixtures." .. name))
+            near(K.main.med, median(f.main), 0.025, "main median")
+            local core = 0
+            for _, lag in ipairs(f.main) do
+                core = core + ((lag >= CORE[1] and lag <= CORE[2]) and 1 or 0)
+            end
+            near(1 - K.main.tail, core / #f.main, 0.10, "main core share")
+            near(K.off.own, median(f.own), 0.015, "off own-reference median")
+            near(K.off.main, median(f.mref), 0.015, "off main-reference median")
+            near(K.off.pOwn, #f.own / f.off, 0.15, "off own-reference share")
+            near(K.off.pMain, #f.mref / f.off, 0.15, "off main-reference share")
+            assert.is_true((f.off - #f.own - #f.mref - f.frame) / f.off <= 0.15, "off tail share")
+            near(RATES.miss + RATES.dodge + RATES.parry, f.avoids / f.swings, 0.06, "avoid rate")
+            near(RATES.crit, f.crits / f.wounds, 0.05, "crit share")
+            assert.are.equal(0, f.out) -- every white wound inside the configured ranges
+        end)
+    end
+
+    it("fires the tokens of one outcome in the observer's order, in every log", function()
+        for _, name in ipairs({ "log1", "log2", "log3", "log5" }) do
+            local rows, groups = require("Virtual.harness.fixtures." .. name).rows, 0
+            local prev
+            for _, r in ipairs(rows) do
+                if r[2] == "U" then
+                    local same = prev
+                        and r[1] - prev[1] <= 1
+                        and r[4] == prev[4]
+                        and r[5] == prev[5]
+                        and r[6] == prev[6]
+                    if same and r[3] ~= prev[3] then
+                        assert.is_true(
+                            observer.rank(prev[3]) <= observer.rank(r[3]),
+                            ("%s at %d: %s before %s"):format(name, r[1], prev[3], r[3])
+                        )
+                        groups = groups + 1
+                    end
+                    prev = r
+                end
+            end
+            assert.is_true(groups > 10, name)
+        end
+    end)
+end)
diff --git a/tests/Virtual/harness/observer_spec.lua b/tests/Virtual/harness/observer_spec.lua
new file mode 100644
index 00000000..f793f9e6
--- /dev/null
+++ b/tests/Virtual/harness/observer_spec.lua
@@ -0,0 +1,274 @@
+-- tests/Virtual/harness/observer_spec.lua (harness design §3.1 layer 4): each observer rule on a one-event true stream.
+local world = require("Virtual.harness.world")
+local entities = require("Virtual.harness.entities")
+local observer = require("Virtual.harness.observer")
+local fake = require("Virtual.State.helpers.fake_api")
+
+describe("the observer", function()
+    local W, us, mob
+
+    -- A world with us (two weapons) attacking a mob that attacks us, and `n` party members.
+    local function setup(n)
+        W = world.new(7)
+        us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
+        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } } }))
+        us.target, mob.target = mob, us
+        for i = 1, n or 0 do
+            W.add(entities.new({ guid = "Other-" .. i })).target = mob
+        end
+    end
+
+    -- The stream's events from `from` on, as { t, ev, a1, a2, a3, a4, a5, src } (ops included).
+    local function events(s, from)
+        local out = {}
+        for i = 1, s.n do
+            if s.t[i] >= (from or 0) and not (s.ev[i] == "@usable" and s.t[i] == 0) then
+                out[#out + 1] = { s.t[i], s.ev[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i], s.src[i] }
+            end
+        end
+        return out
+    end
+
+    it("fires our swing, then its outcome on the target's plate and the target in the same ms", function()
+        setup()
+        local sw = W.emit({
+            t = 5,
+            kind = "swing",
+            src = us,
+            dst = mob,
+            hand = 2,
+            act = "WOUND",
+            flag = "",
+            amount = 30,
+            speed = 2.5,
+        })
+        W.emit({
+            t = 5.7,
+            kind = "land",
+            src = us,
+            dst = mob,
+            hand = 2,
+            act = "WOUND",
+            flag = "",
+            amount = 30,
+            school = 1,
+            swing = sw,
+        })
+        local s = observer.observe(W, setmetatable({ sameMs = 0 }, { __index = observer.DEFAULTS }))
+        assert.are.same({
+            { 5, "PLAYER_SWING", 2.5, 1, nil, nil, nil, 0 },
+            { 5.7, "UNIT_COMBAT", "nameplate1", "WOUND", "", 30, 1, 1 },
+            { 5.7, "UNIT_COMBAT", "target", "WOUND", "", 30, 1, 1 },
+        }, events(s))
+        local i = s.n -- the target's row, last
+        assert.are.same({ "target", 2, 5 }, { s.a1[i], s.hand[i], s.swingT[i] })
+    end)
+
+    it("fires a hit on us for player, then targettarget while our target targets us; another's on partyN", function()
+        setup(1)
+        local other = W.ents[3]
+        W.emit({
+            t = 3,
+            kind = "swing",
+            src = mob,
+            dst = us,
+            hand = 1,
+            act = "PARRY",
+            flag = "",
+            amount = 0,
+            school = 1,
+        })
+        mob.target = other
+        W.emit({
+            t = 4,
+            kind = "swing",
+            src = mob,
+            dst = us,
+            hand = 1,
+            act = "WOUND",
+            flag = "",
+            amount = 12,
+            school = 1,
+        })
+        W.emit({
+            t = 5,
+            kind = "swing",
+            src = mob,
+            dst = other,
+            hand = 1,
+            act = "WOUND",
+            flag = "",
+            amount = 13,
+            school = 1,
+        })
+        local got = events(observer.observe(W))
+        assert.are.same({
+            { 3, "UNIT_COMBAT", "player", "PARRY", "", 0, 1, 2 },
+            { 3, "UNIT_COMBAT", "targettarget", "PARRY", "", 0, 1, 2 },
+            { 4, "UNIT_COMBAT", "player", "WOUND", "", 12, 1, 2 },
+            { 5, "UNIT_COMBAT", "party1", "WOUND", "", 13, 1, 2 },
+        }, got)
+    end)
+
+    it("fires another source's outcome on our target's tokens; its casts with secret IDs, ours plain", function()
+        setup(1)
+        local other = W.ents[3]
+        W.emit({ t = 2, kind = "cast", src = other, dst = mob, spell = "SECRET" })
+        W.emit({ t = 2, kind = "spell", src = other, dst = mob, act = "WOUND", flag = "", amount = 37, school = 8 })
+        W.emit({ t = 3, kind = "cast", src = us, dst = mob, spell = "DOT", cost = 10 })
+        local got = events(observer.observe(W))
+        assert.are.same({ 2, "UNIT_SPELLCAST_SUCCEEDED", "party1", fake.SECRET, fake.SECRET }, { unpack(got[1], 1, 5) })
+        assert.are.same({ "nameplate1", 37, 8, 2 }, { got[2][3], got[2][6], got[2][7], got[2][8] })
+        assert.are.same({ "target", 37, 8, 2 }, { got[3][3], got[3][6], got[3][7], got[3][8] })
+        assert.are.same({ 3, "UNIT_SPELLCAST_SUCCEEDED", "player" }, { got[4][1], got[4][2], got[4][3] })
+        assert.is_number(got[4][5])
+    end)
+
+    it(
+        "fires a queued strike's frame: our swing, a WOUND 0 and our success in either order, its wound 1 ms later",
+        function()
+            local orders = {}
+            for seed = 1, 8 do
+                setup()
+                W.rng = require("Virtual.harness.rng").new(seed)
+                W.emit({
+                    t = 6,
+                    kind = "strike",
+                    src = us,
+                    dst = mob,
+                    hand = 1,
+                    act = "WOUND",
+                    flag = "",
+                    amount = 80,
+                    school = 1,
+                    spell = "STRIKE",
+                    speed = 2.2,
+                })
+                local got = events(observer.observe(W))
+                local o = {}
+                for _, e in ipairs(got) do
+                    o[#o + 1] = e[2] == "UNIT_COMBAT" and (e[3] .. e[6]) or e[2]
+                end
+                orders[table.concat(o, " ")] = true
+                assert.are.same({ 6.001, "target", 80, 1 }, { got[#got][1], got[#got][3], got[#got][6], got[#got][8] })
+            end
+            assert.are.same({
+                ["PLAYER_SWING nameplate10 target0 UNIT_SPELLCAST_SUCCEEDED nameplate180 target80"] = true,
+                ["UNIT_SPELLCAST_SUCCEEDED nameplate10 target0 PLAYER_SWING nameplate180 target80"] = true,
+            }, orders)
+        end
+    )
+
+    it("fires another player's strike frame as a WOUND 0 and its damage 1 ms later, with no cast", function()
+        setup(1)
+        W.emit({
+            t = 6,
+            kind = "strike",
+            src = W.ents[3],
+            dst = mob,
+            hand = 1,
+            act = "WOUND",
+            flag = "",
+            amount = 36,
+            school = 1,
+        })
+        local got = events(observer.observe(W))
+        assert.are.same({ 6, 6, 6.001, 6.001 }, { got[1][1], got[2][1], got[3][1], got[4][1] })
+        assert.are.same({ 0, 0, 36, 36 }, { got[1][6], got[2][6], got[3][6], got[4][6] })
+        assert.are.equal(4, #got)
+    end)
+
+    it("fires the on-swing proc as a school-32 wound on the target and a heal on us, same ms", function()
+        setup()
+        W.emit({ t = 7.002, kind = "proc", src = us, dst = mob, act = "WOUND", amount = 36, school = 32 })
+        local got = events(observer.observe(W))
+        assert.are.same({ "nameplate1", "WOUND", 36, 32 }, { got[1][3], got[1][4], got[1][6], got[1][7] })
+        assert.are.same({ "target", "WOUND", 36, 32 }, { got[2][3], got[2][4], got[2][6], got[2][7] })
+        assert.are.same({ "player", "HEAL", 36, 1 }, { got[3][3], got[3][4], got[3][6], got[3][7] })
+        assert.are.same({ "targettarget", "HEAL" }, { got[4][3], got[4][4] })
+        assert.are.equal(7.002, got[4][1])
+    end)
+
+    it("adds an unexplained avoid in the swing event's ms at its share, and lands our hands at their lags", function()
+        setup()
+        local lag, sameMs, swings = observer.lag(), 0, 3000
+        local main, own, mref = {}, 0, 0
+        us.lastSwing, us.landAt = { 0, 0 }, { 0, 0 }
+        for k = 1, swings / 2 do -- a main swing, then an off swing 0.3 s later
+            local t = k * 2.5
+            local d = lag(W, us, 1, t)
+            us.lastSwing[1], us.landAt[1], main[#main + 1] = t, t + d, d
+            d = lag(W, us, 2, t + 0.3)
+            if math.abs(d - 0.703) < 0.03 then
+                own = own + 1
+            elseif math.abs(0.3 + d - 1.686) < 0.03 then
+                mref = mref + 1
+            end
+            for h = 1, 2 do
+                W.emit({
+                    t = t + 0.3 * (h - 1),
+                    kind = "swing",
+                    src = us,
+                    dst = mob,
+                    hand = h,
+                    act = "MISS",
+                    speed = 2.5,
+                })
+            end
+        end
+        local s = observer.observe(W)
+        for i = 1, s.n do
+            sameMs = sameMs + (s.src[i] == 3 and s.a1[i] == "target" and 1 or 0)
+        end
+        assert.is_true(math.abs(sameMs / swings - 3 / 87) < 0.01, "same-ms share " .. sameMs / swings)
+        table.sort(main)
+        assert.is_true(math.abs(main[#main / 2] - 0.474) < 0.01, "main median " .. main[#main / 2])
+        assert.is_true(math.abs(own / (swings / 2) - observer.DEFAULTS.off.pOwn) < 0.05, "off own share")
+        assert.is_true(math.abs(mref / (swings / 2) - observer.DEFAULTS.off.pMain) < 0.05, "off main-reference share")
+    end)
+
+    it("answers usability from our true power: a gain flips it a knob's delay later, our spend at once", function()
+        setup()
+        local land = { t = 4, kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", flag = "", amount = 40 }
+        land.school, land.swing, land.rage = 1, { t = 3.5 }, 12
+        W.emit(land)
+        W.emit({ t = 5, kind = "cast", src = us, dst = mob, spell = "CAST", cost = 10 })
+        local got = events(observer.observe(W, setmetatable({ usable = true }, { __index = observer.DEFAULTS })), 1)
+        local shout, rend = observer.COSTS[1][1], observer.COSTS[3][1]
+        assert.are.same({
+            { 4, "UNIT_COMBAT", "nameplate1", "WOUND", "", 40, 1, 1 },
+            { 4, "UNIT_COMBAT", "target", "WOUND", "", 40, 1, 1 },
+            { 4, "@truth", 12, nil, nil, nil, nil, 0 },
+            { 4.1, "@usable", shout, 1, nil, nil, nil, 0 },
+            { 4.1, "@usable", rend, 1, nil, nil, nil, 0 },
+            { 4.1, "SPELL_UPDATE_USABLE", nil, nil, nil, nil, nil, 0 },
+            { 5, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", observer.SPELLS.CAST, nil, nil, 0 },
+            { 5, "@truth", 2, nil, nil, nil, nil, 0 },
+            { 5, "@usable", shout, 2, nil, nil, nil, 0 },
+            { 5, "@usable", rend, 2, nil, nil, nil, 0 },
+            { 5, "SPELL_UPDATE_USABLE", nil, nil, nil, nil, nil, 0 },
+        }, got)
+    end)
+
+    it(
+        "reads the weapon damage cache out of combat only: before the pull and at the stop, not at a form change",
+        function()
+            setup()
+            W.emit({ t = 2, kind = "pull" })
+            us.dmgMult = 1.2 -- a damage buff in combat: no read until the stop
+            W.emit({ t = 3, kind = "form", form = 1 })
+            W.emit({ t = 9, kind = "stop" })
+            local damage, form = {}, nil
+            local s = observer.observe(W)
+            for i = 1, s.n do
+                if s.ev[i] == "@damage" then
+                    damage[#damage + 1] = { s.t[i], s.a2[i] }
+                elseif s.ev[i] == "UPDATE_SHAPESHIFT_FORM" then
+                    form = s.t[i]
+                end
+            end
+            assert.are.same({ { 1.5, 50 }, { 9, 60 } }, damage)
+            assert.are.equal(3, form)
+        end
+    )
+end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `473 successes / 0 failures / 4 errors / 0 pending`.
- `pairing_replay_spec`, `fixtures_spec`, `observer_spec` and `alloc_spec` (harness) error at load: `module 'Virtual.harness.drive' not found` (and `...observer`, `...scenarios`): the harness does not exist yet.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/helpers/fake_api.lua b/tests/Virtual/State/helpers/fake_api.lua
index 2efa578f..a656991b 100644
--- a/tests/Virtual/State/helpers/fake_api.lua
+++ b/tests/Virtual/State/helpers/fake_api.lua
@@ -62,6 +62,7 @@ function M.new()
         unknownEvents = {}, -- [event] = true: RegisterEvent raises, as the client does for an event it does not know
         form = 0, -- GetShapeshiftForm (0: none)
         forms = {}, -- [form index] = its spell ID (GetShapeshiftFormInfo's 4th return)
+        damage = { 0, 0, 0, 0 }, -- UnitDamage's min and max main, min and max off (the harness's out-of-combat cache)
     }
     local api = { ctl = ctl }
 
@@ -177,7 +178,11 @@ function M.new()
         return stats[1], stats[2], stats[3], stats[4], stats[5], stats[6], stats[7]
     end
     api.UnitStat, api.GetSpellBonusDamage, api.UnitAttackPower, api.UnitWeaponAttackPower = zeros, zeros, zeros, zeros
-    api.UnitDamage, api.UnitArmor, api.GetMasteryEffect, api.GetCritChance = zeros, zeros, zeros, zeros
+    api.UnitArmor, api.GetMasteryEffect, api.GetCritChance = zeros, zeros, zeros
+    function api.UnitDamage()
+        local d = ctl.damage
+        return d[1], d[2], d[3], d[4], 0, 0, 1
+    end
     api.GetShieldBlock = zeros
     api.GetSpellCritChance, api.GetRangedCritChance, api.GetCombatRating, api.GetCombatRatingBonus =
         zeros, zeros, zeros, zeros
diff --git a/tests/Virtual/harness/behaviours.lua b/tests/Virtual/harness/behaviours.lua
new file mode 100644
index 00000000..8c785a65
--- /dev/null
+++ b/tests/Virtual/harness/behaviours.lua
@@ -0,0 +1,227 @@
+-- tests/Virtual/harness/behaviours.lua (harness design §3.1, layer 2): seeded behaviours that drive entities over time,
+-- few and parametric: `melee` (white swings per hand, presses, a queued strike, an on-swing proc, a DoT), `caster`
+-- (cast bars, spell schools, an optional pet: a `melee` of its own), `mob` (swings at its target, a spell). The matrix
+-- comes from parameters and seeds. Named by shape only (boundary rule).
+local M = {}
+
+-- Our white swings' outcome rates (P log 2: 10 MISS, 3 DODGE, 3 PARRY in 71 swings; 8 crits in 69 wounds).
+M.RATES = { miss = 0.14, dodge = 0.04, parry = 0.04, glancing = 0, crit = 0.12 }
+-- A mob's swings at a player: the player's avoid table is the victim's (`entity.avoid`); this is the mob's crit.
+M.MOB_CRIT = 0.05
+
+-- One outcome from `rates` (miss, dodge, parry, block, glancing, crit): the action and its flag.
+local function roll(r, rates)
+    local x = r.next()
+    for _, k in ipairs({ "miss", "dodge", "parry", "block" }) do
+        local p = rates[k] or 0
+        if x < p then
+            return k:upper(), ""
+        end
+        x = x - p
+    end
+    if x < (rates.glancing or 0) then
+        return "WOUND", "GLANCING"
+    end
+    x = x - (rates.glancing or 0)
+    if x < (rates.crit or 0) then
+        return "WOUND", "CRITICAL"
+    end
+    return "WOUND", ""
+end
+M.roll = roll
+
+-- A white hit's amount: the weapon's roll x the attacker's damage multiplier, less the victim's armour, doubled for a
+-- crit; a glancing blow is `glance` ({ lo, hi } absolute) or three quarters.
+local function amount(r, w, e, victim, flag, glance)
+    local a = r.int(w[1], w[2]) * e.dmgMult * (1 - (victim and victim.dr or 0))
+    if flag == "CRITICAL" then
+        a = a * 2
+    elseif flag == "GLANCING" then
+        a = glance and r.int(glance[1], glance[2]) or a * 0.75
+    end
+    return math.max(1, math.floor(a + 0.5))
+end
+
+--- A melee player: per weapon hand, a swing every speed / haste from a random phase, its outcome rolled from `p.rates`
+--- (default RATES). `p.land(W, e, hand, t)`: ours only, the lag before the outcome lands (observer.lua); without it the
+--- outcome is at the swing (another player's). `p.rage` { main, off }: what a landed swing of ours pays.
+--- `p.presses` { { t, spell, cost, kind } }: kind "queue" (the next main-hand swing is a strike of `p.strike`
+--- { lo, hi }), "dot" (`p.dot` { every, n, amount } ticks, school 1), "cast" (no outcome); each only if our power
+--- covers its cost.
+--- `p.strikes`: another player's chance per main-hand swing to make it a strike frame (G: WOUND 0 + damage).
+--- `p.proc` { chance, amount }: a school-32 wound on the swing event (1-2 ms after it). `p.glance` { lo, hi }.
+function M.melee(p)
+    p = p or {}
+    return function(W, e)
+        local rates = p.rates or M.RATES
+        e.lastSwing, e.landAt = { 0, 0 }, { 0, 0 }
+        for h = 1, #e.weapons do
+            local function swing()
+                local tgt = e.target
+                if e.stopped or not tgt or tgt.health <= 0 then
+                    return
+                end
+                local w = e.weapons[h]
+                local foreign = h == 1 and p.strikes and W.rng.chance(p.strikes)
+                if h == 1 and (e.queued or foreign) then
+                    local q = e.queued or {}
+                    e.queued = nil
+                    W.emit({
+                        kind = "strike",
+                        src = e,
+                        dst = tgt,
+                        hand = 1,
+                        act = "WOUND",
+                        flag = "",
+                        amount = W.rng.int(p.strike[1], p.strike[2]),
+                        school = 1,
+                        spell = q.spell,
+                        cost = q.cost,
+                        speed = w[3],
+                    })
+                else
+                    local act, flag = roll(W.rng, rates)
+                    local amt = act == "WOUND" and amount(W.rng, w, e, tgt, flag, p.glance) or 0
+                    local sw = W.emit({
+                        kind = "swing",
+                        src = e,
+                        dst = tgt,
+                        hand = h,
+                        act = act,
+                        flag = flag,
+                        amount = amt,
+                        school = 1,
+                        speed = w[3],
+                        ours = p.land ~= nil,
+                    })
+                    if p.land then
+                        local lag = p.land(W, e, h, W.t)
+                        e.landAt[h] = W.t + lag
+                        W.at(W.t + lag, function()
+                            W.emit({
+                                kind = "land",
+                                src = e,
+                                dst = tgt,
+                                hand = h,
+                                act = act,
+                                flag = flag,
+                                amount = amt,
+                                school = 1,
+                                swing = sw,
+                                rage = act == "WOUND" and p.rage and p.rage[h] or nil,
+                            })
+                        end)
+                    end
+                    if p.proc and W.rng.chance(p.proc[1]) then
+                        W.at(W.t + W.rng.int(1, 2) / 1000, function()
+                            local proc =
+                                { kind = "proc", src = e, dst = tgt, act = "WOUND", amount = p.proc[2], school = 32 }
+                            W.emit(proc)
+                        end)
+                    end
+                end
+                e.lastSwing[h] = W.t
+                W.at(W.t + w[3] / (p.haste or 1), swing)
+            end
+            W.at(W.t + (p.phase and p.phase[h] or W.rng.next() * e.weapons[h][3]), swing)
+        end
+        for _, press in ipairs(p.presses or {}) do
+            W.at(press[1], function()
+                if e.stopped or e.power < press[3] then
+                    return
+                end
+                if press[4] == "queue" then
+                    e.queued = { spell = press[2], cost = press[3] }
+                    return
+                end
+                W.emit({ kind = "cast", src = e, dst = e.target, spell = press[2], cost = press[3] })
+                if press[4] == "dot" then
+                    for k = 1, p.dot[2] do
+                        W.at(W.t + k * p.dot[1], function()
+                            W.emit({
+                                kind = "tick",
+                                src = e,
+                                dst = e.target,
+                                act = "WOUND",
+                                amount = p.dot[3],
+                                school = 1,
+                            })
+                        end)
+                    end
+                end
+            end)
+        end
+    end
+end
+
+--- A caster: a spell every `p.every` s (a `p.cast` s bar first), school `p.school` (2, 4, 8 or 32), amount `p.amount`
+--- { lo, hi }, resisted (MISS) at `p.resist`; its casts are another player's (secret IDs). `p.pet`: a melee behaviour
+--- for a pet entity `p.petEntity` on the caster's target.
+function M.caster(p)
+    return function(W, e)
+        local function cast()
+            if e.stopped or not e.target or e.target.health <= 0 then
+                return
+            end
+            W.emit({ kind = "cast", src = e, dst = e.target, spell = "SECRET" })
+            local resisted = W.rng.chance(p.resist or 0)
+            W.emit({
+                kind = "spell",
+                src = e,
+                dst = e.target,
+                act = resisted and "MISS" or "WOUND",
+                flag = "",
+                amount = resisted and 0 or W.rng.int(p.amount[1], p.amount[2]),
+                school = p.school or 8,
+            })
+            W.at(W.t + p.every * (0.8 + 0.4 * W.rng.next()), cast)
+        end
+        W.at(W.t + (p.cast or 1.5) + W.rng.next(), cast)
+    end
+end
+
+--- A mob: a swing at its target every weapon speed, rolled against the target's `avoid` table and `p.crit`; `p.spell`
+--- { every, lo, hi, school }: a spell at its target.
+function M.mob(p)
+    p = p or {}
+    return function(W, e)
+        local function swing()
+            local v = e.target
+            if e.stopped or e.health <= 0 then
+                return
+            elseif not v then -- not attacking anyone yet (a later `targetSwitch`): look again a swing later
+                W.at(W.t + e.weapons[1][3], swing)
+                return
+            end
+            local rates = { miss = v.avoid.miss, dodge = v.avoid.dodge, parry = v.avoid.parry, block = v.avoid.block }
+            rates.crit = p.crit or M.MOB_CRIT
+            local act, flag = roll(W.rng, rates)
+            local amt = act == "WOUND" and amount(W.rng, e.weapons[1], e, v, flag) or 0
+            W.emit({ kind = "swing", src = e, dst = v, hand = 1, act = act, flag = flag, amount = amt, school = 1 })
+            W.at(W.t + e.weapons[1][3], swing)
+        end
+        W.at(W.t + (p.phase or W.rng.next() * e.weapons[1][3]), swing)
+        if p.spell then
+            local s = p.spell
+            local function spell()
+                if e.stopped or e.health <= 0 or not e.target then
+                    return
+                end
+                local amt = W.rng.int(s[2], s[3])
+                W.emit({
+                    kind = "spell",
+                    src = e,
+                    dst = e.target,
+                    act = "WOUND",
+                    flag = "",
+                    amount = amt,
+                    school = s[4],
+                })
+                W.at(W.t + s[1], spell)
+            end
+            W.at(W.t + s[1] * W.rng.next() + 1, spell)
+        end
+    end
+end
+
+return M
diff --git a/tests/Virtual/harness/drive.lua b/tests/Virtual/harness/drive.lua
new file mode 100644
index 00000000..9acf6425
--- /dev/null
+++ b/tests/Virtual/harness/drive.lua
@@ -0,0 +1,267 @@
+-- tests/Virtual/harness/drive.lua (harness design §3.1): boots VirtualState on fake_api and the fake spec as
+-- pairing_replay_spec does, fires an observed stream through `ctl`, ticks and folds every TICK seconds, and captures
+-- what the addon concluded: each `Swing` c = 1 / c = 3 staged (through an S.Stage wrapper, tagged with the stream event
+-- being fired), the combat-log rows (a COMBAT_LOG_EVENT_UNFILTERED sink) and the believed rage at each 10 s window.
+-- The run loop allocates nothing: the stream and every capture array are built before it.
+local load = require("Virtual.State.helpers.load")
+local fake = require("Virtual.State.helpers.fake_api")
+local fs = require("Virtual.State.helpers.fake_spec")
+
+local M = {}
+
+M.TICK = 0.1 -- seconds between OnUpdate + drain (in game every frame; poll 2 at 0.2 s in combat)
+M.WINDOW = 10 -- seconds per rage window (harness design §3.3)
+M.STEP = 9 -- one main-hand step: the overshoot bar
+local CAP = 4096
+
+local USABLE, SHORT = { true, false }, { false, true }
+
+--- A booted VirtualState: { api, ctl, ns, VS, I, L, captures }. `o.rage` { main, off } per landed swing [9, 5],
+--- `o.max` the rage cap [1e6]; `o.damage` the UnitDamage cache's first values (default zeros: read at the pull);
+--- `o.oracle == false` unregisters Rows' oracle hooks (the no-oracle run).
+function M.boot(o)
+    o = o or {}
+    local api, ctl = fake.new()
+    ctl.now = 0.1
+    local c = { api = api, ctl = ctl, saved = {}, cur = 0 }
+    for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
+        c.saved[k] = rawget(_G, k) or false
+        _G[k] = v
+    end
+    ctl.powerMax[fs.RAGE] = o.max or 1e6
+    if o.damage then
+        for i = 1, 4 do
+            ctl.damage[i] = o.damage[i]
+        end
+    end
+    local ns = load.module()
+    c.ns, c.VS, c.I = ns, ns.VirtualState, ns.VirtualStateInternal
+    c.L = c.I.Log
+    local def = fs.def(fs.new((o.rage or { 9, 5 })[1]))
+    def.resources[1].swingOff = (o.rage or { 9, 5 })[2]
+    def.resources[1].max = o.max or 1e6
+    c.I.Build(def, 0.1)
+    c.VS.Start(api)
+    -- captures, by stream index: the hand credited and the swing time it was credited at (0: none)
+    c.crHand, c.crAt, c.crTok, c.verdict, c.recIdx, c.onus = {}, {}, {}, {}, {}, {}
+    c.lateHand, c.lateAt = {}, {} -- credits staged outside an event (the oracle's rescue)
+    c.win, c.winT, c.loOver, c.estOver, c.danger = {}, {}, {}, {}, {}
+    for i = 1, CAP do
+        c.crHand[i], c.crAt[i], c.crTok[i], c.lateHand[i], c.lateAt[i], c.win[i], c.winT[i] = 0, 0, false, 0, 0, 0, 0
+        c.loOver[i], c.estOver[i], c.danger[i] = 0, 0, 0
+        c.verdict[i], c.onus[i] = 0, ""
+    end
+    for k = 1, 8 do
+        c.recIdx[k] = 0
+    end
+    c.crits, c.landed = { 0, 0 }, { 0, 0 }
+    c.rows = { swing = 0, missed = 0, spell = 0, noDst = 0, order = 0 }
+    c.lastRow = { 0, 0 }
+    local S, Swing = c.I.Sources, c.VS.Obs.Swing
+    local stage = S.Stage
+    c.stream = nil
+    c.I.On(c.VS.Obs.PlayerHit, function() -- every hit on us reaches the belief, attributed or not
+        c.hits = c.hits + 1
+    end)
+    S.Stage = function(kind, t, a, b, cc)
+        if kind == Swing and (cc == 1 or cc == 3) then
+            local i = c.cur
+            if cc == 3 then
+                c.crits[a] = c.crits[a] + 1
+            elseif i > 0 then
+                c.landed[a] = c.landed[a] + 1
+                c.crHand[i], c.crAt[i], c.crTok[i] = a, t, c.stream.a1[i] == "target"
+                if b >= 1 and b <= 8 then
+                    c.recIdx[b] = i
+                end
+            end
+        end
+        return stage(kind, t, a, b, cc)
+    end
+    -- the oracle's verdicts by stream index (1 confirmed, 2 retracted, 3 soft) and its rescues (hand, swing time)
+    local verdict, rescue = c.I.CreditVerdict, c.I.Rescue
+    if o.oracle == false then
+        c.I.CreditVerdict, c.I.Rescue = nil, nil
+    elseif verdict then
+        c.I.CreditVerdict = function(id, ok, t, firm)
+            local v = verdict(id, ok, t, firm)
+            local i = c.recIdx[id]
+            if v and i > 0 then
+                c.verdict[i] = ok and 1 or (firm and 2 or 3)
+            end
+            return v
+        end
+        c.I.Rescue = function(r, need, since, t)
+            local h, crit, at = rescue(r, need, since, t)
+            if h then
+                c.landed[h] = c.landed[h] + 1
+                c.nLate = c.nLate + 1
+                c.lateHand[c.nLate], c.lateAt[c.nLate] = h, at
+            end
+            return h, crit, at
+        end
+    end
+    local GetInfo = ns.Facade.CombatLogGetCurrentEventInfo
+    local sink = c.I.Events.CreateFrame("Frame")
+    local rows, last = c.rows, c.lastRow
+    sink:SetScript("OnEvent", function()
+        local t, ev, _, src, _, _, _, dst, _, _, _, a12, a13, _, _, _, _, _, _, _, a21 = GetInfo()
+        if src ~= "Player-1" then
+            if dst == "Player-1" and c.cur > 0 then
+                c.onus[c.cur] = src -- a hit on us credited to an attacker
+            end
+            return
+        end
+        if dst == "" then
+            rows.noDst = rows.noDst + 1
+        end
+        local hand = 0
+        if ev == "SWING_DAMAGE" then
+            rows.swing, hand = rows.swing + 1, a21 and 2 or 1
+        elseif ev == "SWING_MISSED" then
+            rows.missed, hand = rows.missed + 1, a13 and 2 or 1
+        elseif ev == "SPELL_DAMAGE" or ev == "SPELL_MISSED" then
+            rows.spell = rows.spell + 1
+        end
+        if hand > 0 then
+            if t < last[hand] then
+                rows.order = rows.order + 1
+            end
+            last[hand] = t
+        end
+    end)
+    sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+    c.nLate, c.nWin, c.truth, c.hits = 0, 0, 0, 0
+    return c
+end
+
+--- Puts back the globals the boot replaced.
+function M.restore(c)
+    for k, v in pairs(c.saved) do
+        _G[k] = v or nil
+    end
+end
+
+-- One client-answer change (or the truth's power for the metrics). Allocates nothing.
+local function op(c, ctl, ev, a1, a2, a3, a4)
+    if ev == "@truth" then
+        c.truth = a1
+    elseif ev == "@damage" then
+        ctl.damage[1], ctl.damage[2], ctl.damage[3], ctl.damage[4] = a1, a2, a3, a4
+    elseif ev == "@usable" then
+        ctl.usable[a1] = a2 == 1 and USABLE or SHORT
+    elseif ev == "@form" then
+        ctl.form = a1
+    elseif ev == "@guid" then
+        ctl.guid[a1] = a2
+    elseif ev == "@unitIs" then
+        ctl.unitIs[a1] = a2
+    elseif ev == "@speed" then
+        ctl.unitSpeed[a1] = a2
+    elseif ev == "@combat" then
+        ctl.combat = a1
+    end
+end
+
+local function tick(c, t)
+    c.ctl.Tick(t)
+    fs.fold(c.ns, t)
+    local p = c.VS.Power(fs.RAGE, t)
+    if t >= c.nextWin then
+        c.nWin = c.nWin + 1
+        c.win[c.nWin], c.winT[c.nWin], c.loOver[c.nWin] = p.est, t, 0
+        c.estOver[c.nWin], c.danger[c.nWin] = 0, 0
+        c.nextWin = c.nextWin + M.WINDOW
+    end
+    if c.nWin > 0 and p.lo - c.truth >= M.STEP then
+        c.loOver[c.nWin] = 1 -- the dangerous sign: the floor a step above the true power
+    end
+    if c.nWin > 0 and p.est - c.truth >= M.STEP then
+        c.estOver[c.nWin] = 1
+    end
+    if c.nWin > 0 and ((p.lo >= 10 and c.truth < 10) or (p.lo >= 15 and c.truth < 15)) then
+        c.danger[c.nWin] = 1
+    end
+end
+
+--- Fires stream `s` (observer.lua) through the booted VirtualState, `offset` seconds later than its times (a replay
+--- on the same boot), ticking every TICK seconds, then 3 s past its end. The captures (crHand/crAt by stream index,
+--- crits, landed, rows, win) are reset first. Allocates nothing.
+function M.run(c, s, offset)
+    offset = offset or 0
+    local ctl = c.ctl
+    c.stream = s
+    for i = 1, s.n do
+        c.crHand[i], c.crAt[i], c.verdict[i], c.onus[i] = 0, 0, 0, ""
+    end
+    c.hits = 0
+    c.crits[1], c.crits[2], c.landed[1], c.landed[2], c.nLate, c.nWin, c.truth = 0, 0, 0, 0, 0, 0, 0
+    local rows = c.rows
+    rows.swing, rows.missed, rows.spell, rows.noDst, rows.order = 0, 0, 0, 0, 0
+    c.lastRow[1], c.lastRow[2] = 0, 0
+    local nextTick = M.TICK * math.floor((s.t[1] + offset) / M.TICK) + M.TICK
+    c.nextWin = nextTick
+    for i = 1, s.n do
+        local t = s.t[i] + offset
+        while nextTick < t do
+            tick(c, nextTick)
+            nextTick = nextTick + M.TICK
+        end
+        ctl.now = t
+        local ev = s.ev[i]
+        if ev:byte(1) == 64 then -- "@"
+            op(c, ctl, ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i])
+        else
+            c.cur = i
+            ctl.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
+            c.cur = 0
+        end
+    end
+    local stop = s.t[s.n] + offset + 3
+    while nextTick <= stop do
+        tick(c, nextTick)
+        nextTick = nextTick + M.TICK
+    end
+end
+
+--- A fixture (fixtures/logN.lua) as a stream: its rows from `base` seconds, the cache read out of combat first.
+--- `dedupe`: one row per outcome on the target, fed as "target" (the research doc's table: the target-side tokens of
+--- one outcome within 1 ms collapse; an outcome only seen on a nameplate or soft token counts). Our casts as the fake
+--- spec's (STRIKE, DOT), other spell IDs as 1; a secret ID as fake_api's SECRET.
+function M.fixtureStream(fix, base, dedupe)
+    local s = { n = 0, t = {}, ev = {}, a1 = {}, a2 = {}, a3 = {}, a4 = {}, a5 = {}, src = {}, hand = {}, swingT = {} }
+    local function push(t, ev, a1, a2, a3, a4, a5)
+        local n = s.n + 1
+        s.n = n
+        s.t[n], s.ev[n], s.a1[n], s.a2[n], s.a3[n], s.a4[n], s.a5[n] = t, ev, a1, a2, a3, a4, a5
+        s.src[n], s.hand[n], s.swingT[n] = 0, 0, 0
+    end
+    local d = fix.damage
+    push(base - 1, "@damage", d[1], d[2], d[3], d[4])
+    push(base - 1, "PLAYER_EQUIPMENT_CHANGED")
+    local IDS = { STRIKE = fs.STRIKE, DOT = fs.REND, OTHER = 1, SECRET = fake.SECRET }
+    local TARGET_SIDE = { target = true, softenemy = true, softinteract = true }
+    local last = {}
+    for _, r in ipairs(fix.rows) do
+        local t = base + r[1] / 1000
+        if r[2] == "S" then
+            push(t, "PLAYER_SWING", r[3], r[4])
+        elseif r[2] == "C" then
+            push(t, "UNIT_SPELLCAST_SUCCEEDED", r[3], r[4] == "SECRET" and fake.SECRET or "Cast", IDS[r[4]])
+        else
+            local unit = r[3]
+            if dedupe and (TARGET_SIDE[unit] or unit:match("^nameplate")) then
+                local key = r[4] .. r[5] .. r[6] .. "/" .. r[7]
+                if not (last.key == key and r[1] - last.ms <= 1) then
+                    push(t, "UNIT_COMBAT", "target", r[4], r[5], r[6], r[7])
+                end
+                last.key, last.ms = key, r[1]
+            elseif not dedupe then
+                push(t, "UNIT_COMBAT", unit, r[4], r[5], r[6], r[7])
+            end
+        end
+    end
+    return s
+end
+
+return M
diff --git a/tests/Virtual/harness/entities.lua b/tests/Virtual/harness/entities.lua
new file mode 100644
index 00000000..8da65e7c
--- /dev/null
+++ b/tests/Virtual/harness/entities.lua
@@ -0,0 +1,40 @@
+-- tests/Virtual/harness/entities.lua (harness design §3.1, layer 1): the true state of each actor of a fight (our
+-- character, party members, enemies, pets). Plain test tables; nothing here is named after a class.
+local M = {}
+
+-- Log 2's weapon damage at level 22 (UnitDamage, before armour), each hand { min, max, speed }.
+M.LOG2_WEAPONS = { { 36, 50, 2.2 }, { 24, 32, 2.5 } }
+
+--- Weapons for `level`: log 2's ranges scaled by level / 22 (UNMEASURED scaling), the same speeds.
+function M.weapons(level, speeds)
+    local k, out = (level or 22) / 22, {}
+    for h, w in ipairs(M.LOG2_WEAPONS) do
+        local s = speeds and speeds[h] or w[3]
+        out[h] = { math.floor(w[1] * k + 0.5), math.floor(w[2] * k + 0.5), s }
+    end
+    return out
+end
+
+--- A new actor. `o`: guid, kind ("player", "mob", "pet"), level, weapons ({ { min, max, speed }, ... }), dr (the
+--- damage its armour takes away, 0-1), avoid ({ miss, dodge, parry, block } on swings at it), health, powerMax.
+function M.new(o)
+    local e = {
+        guid = o.guid,
+        kind = o.kind or "player",
+        level = o.level or 22,
+        weapons = o.weapons or {},
+        dr = o.dr or 0,
+        avoid = o.avoid or { miss = 0.05, dodge = 0.05, parry = 0.05, block = 0 },
+        health = o.health or 1000,
+        healthMax = o.health or 1000,
+        power = 0,
+        powerMax = o.powerMax or 100,
+        auras = {},
+        target = o.target,
+        form = 0,
+        dmgMult = 1,
+    }
+    return e
+end
+
+return M
diff --git a/tests/Virtual/harness/observer.lua b/tests/Virtual/harness/observer.lua
new file mode 100644
index 00000000..2406a62b
--- /dev/null
+++ b/tests/Virtual/harness/observer.lua
@@ -0,0 +1,262 @@
+-- tests/Virtual/harness/observer.lua (harness design §3.1, layer 4): turns the world's true stream into what the client
+-- shows OUR character, as flat arrays the drive loop fires through fake_api. The only place that encodes the client;
+-- every rule names its log (P = docs/research/2026-10-16-swing-outcome-pairing.md, G = the group captures doc, U = the
+-- UNIT_COMBAT research), and a rule without one is UNMEASURED with a knob in DEFAULTS.
+local fs = require("Virtual.State.helpers.fake_spec")
+local fake = require("Virtual.State.helpers.fake_api")
+
+local M = {}
+
+M.DEFAULTS = {
+    -- Our landing lag after PLAYER_SWING (P log 2, G5): main N(474 ms, 40 ms), a share in a uniform tail over 0.1-1.3 s
+    -- (log 2: 5 of 36 outside 435-552 ms; G5: 5 of 22 outside 436-556 ms).
+    main = { med = 0.474, sd = 0.04, tail = 0.15 },
+    -- Off hand (G5 ruling): 0.703 s after its own swing, or 1.686 s after the latest main swing at or before it, or in
+    -- the main hit's frame, else the tail. The shares sit within 0.15 of both logs' (log 2: 10 and 21 of 33; G5: 12 and
+    -- 7 of 20, one in the main frame), which only their midpoint does.
+    off = { own = 0.703, ownSd = 0.006, main = 1.686, mainSd = 0.004, pOwn = 0.452, pMain = 0.49, pFrame = 0.03 },
+    tail = { 0.1, 1.3 },
+    sameMs = 3 / 87, -- an avoid on the target in the same ms as our swing event, per swing (P log 2: 3 of 87)
+    usable = false, -- answer usability from our true power (the oracle's scenarios; off: no pins, the scale stays 1)
+    usableDelay = 0.1, -- SPELL_UPDATE_USABLE after a true gain that flips an answer (UNMEASURED until G7); a spend at once
+    targetTokens = { "plate", "target" }, -- "plate": the target's nameplateN (P logs 1-2: nameplate1 then target)
+    plainSpeed = false, -- UnitAttackSpeed of a hostile plain (Attackers.lua notes: secret on Forever)
+}
+
+-- Our spells as the fake spec's (its costs: the usability answers).
+M.SPELLS = { STRIKE = fs.STRIKE, DOT = fs.REND, CAST = fs.SHOUT, OTHER = 1 }
+M.COSTS = { { fs.SHOUT, 10 }, { fs.STRIKE, 15 }, { fs.REND, 10 } }
+
+--- Our landing lag (the `land` of behaviours.melee) under knobs `k`: the time from a swing of `hand` at `t` to its
+--- outcome.
+function M.lag(k)
+    k = k or M.DEFAULTS
+    return function(W, e, hand, t)
+        local r = W.rng
+        local function tail()
+            return k.tail[1] + r.next() * (k.tail[2] - k.tail[1])
+        end
+        local o = k.off
+        if hand == 1 then
+            if r.chance(k.main.tail) then
+                return tail()
+            end
+            return math.max(0.05, r.normal(k.main.med, k.main.sd))
+        end
+        local own = math.max(0.05, r.normal(o.own, o.ownSd))
+        local x = r.next()
+        if x < o.pOwn then
+            return own
+        elseif x < o.pOwn + o.pMain then
+            local d = e.lastSwing[1] + r.normal(o.main, o.mainSd) - t
+            return (e.lastSwing[1] > 0 and d > 0.05) and d or own
+        elseif x < o.pOwn + o.pMain + o.pFrame then
+            local d = e.landAt[1] - t
+            return d > 0 and d or own
+        end
+        return tail()
+    end
+end
+
+-- The token rank of a duplicate group (P logs 1-2, G, G5: nameplateN before target before softenemy/softinteract;
+-- player before targettarget; partyN before nameplateN): the observer fires in this order, fixtures_spec checks it.
+function M.rank(token)
+    if token == "player" then
+        return 1
+    elseif token:match("^party") or token:match("^raid") then
+        return 2
+    elseif token:match("^nameplate") then
+        return 3
+    elseif token == "target" then
+        return 4
+    elseif token:match("^soft") then
+        return 5
+    end
+    return 6 -- targettarget
+end
+
+--- The client stream of world `W` for our character (W.ents[1]) under knobs `k`: { n, t[], ev[], a1..a5[], src[]
+--- (1 ours, 2 another source, 3 unexplained, 0 not an outcome), hand[] (our swing's hand; 0 a cast's), swingT[] (our
+--- swing's true time), actor[] (the entity index of a hit on us) }. An `ev` starting with "@" is a client-answer change
+--- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`), or `@truth` our
+--- true power after an event (for the metrics).
+function M.observe(W, k)
+    k = k or M.DEFAULTS
+    local us = W.ents[1]
+    local idx, plate, party, mobs = {}, {}, {}, {}
+    local nMob, nParty = 0, 0
+    for i, e in ipairs(W.ents) do
+        idx[e] = i
+        if e.kind == "mob" then
+            nMob = nMob + 1
+            plate[e], mobs[nMob] = "nameplate" .. nMob, e
+        elseif e.kind == "player" and i > 1 then
+            nParty = nParty + 1
+            party[e] = "party" .. nParty
+        elseif e.kind == "pet" then
+            party[e] = "partypet1"
+        end
+    end
+    local list, seq = {}, 0
+    local function push(t, ev, a1, a2, a3, a4, a5, src, hand, swingT, actor)
+        seq = seq + 1
+        list[#list + 1] = { t, seq, ev, a1, a2, a3, a4, a5, src or 0, hand or 0, swingT or 0, actor or 0 }
+    end
+    local function tokensOf(v, ev)
+        local out = {}
+        if v == us then
+            out[1] = "player"
+            if ev.onUs then
+                out[2] = "targettarget"
+            end
+        elseif v == ev.ourTarget then
+            for _, tok in ipairs(k.targetTokens) do
+                out[#out + 1] = tok == "plate" and plate[v] or tok
+            end
+        elseif plate[v] then
+            out[1] = plate[v]
+        elseif party[v] then
+            out[1] = party[v]
+        end
+        return out
+    end
+    local function outcome(t, ev, src, hand, swingT)
+        for _, tok in ipairs(tokensOf(ev.dst, ev)) do
+            push(
+                t,
+                "UNIT_COMBAT",
+                tok,
+                ev.act,
+                ev.flag or "",
+                ev.amount or 0,
+                ev.school or 1,
+                src,
+                hand,
+                swingT,
+                idx[ev.src]
+            )
+        end
+    end
+    -- The client's power for usability: our gains after the knob's delay, our spends at their casts (UNMEASURED);
+    -- the answers flip as it crosses the fake spec's costs (built after the walk, in time order).
+    local deltas = {}
+    local function targets(t, ev)
+        local tt = ev.targets
+        for _, e in ipairs(mobs) do
+            local tok = plate[e]
+            push(t, "@guid", tok, e.guid)
+            push(t, "@unitIs", tok .. "target", tt[e] == us and "player" or nil)
+            if k.plainSpeed then
+                push(t, "@speed", tok, e.weapons[1][3])
+            end
+        end
+        for _, e in ipairs(mobs) do
+            push(t, "NAME_PLATE_UNIT_ADDED", plate[e])
+        end
+        local tgt = tt[us] or nil
+        push(t, "@guid", "target", tgt and tgt.guid)
+        push(t, "@unitIs", "targettarget", tgt and tt[tgt] == us and "player" or nil)
+        if k.plainSpeed and tgt then
+            push(t, "@speed", "target", tgt.weapons[1][3])
+        end
+        push(t, "PLAYER_TARGET_CHANGED")
+    end
+    local function cache(t, d)
+        push(t, "@damage", d[1], d[2], d[3], d[4])
+        push(t, "PLAYER_EQUIPMENT_CHANGED")
+    end
+    local castN = 0
+    for _, ev in ipairs(W.truth) do
+        local t, kind = ev.t, ev.kind
+        if kind == "pull" then
+            cache(t - 0.5, ev.damage)
+            targets(t - 0.4, ev)
+            push(t, "@combat", true)
+            push(t, "PLAYER_REGEN_DISABLED")
+        elseif kind == "stop" then
+            push(t, "@combat", false)
+            cache(t, ev.damage)
+            push(t, "PLAYER_REGEN_ENABLED")
+        elseif kind == "form" then
+            push(t, "@form", ev.form)
+            push(t, "UPDATE_SHAPESHIFT_FORM")
+        elseif kind == "target" then
+            targets(t, ev)
+        elseif kind == "swing" and ev.src == us then
+            push(t, "PLAYER_SWING", ev.speed, ev.hand - 1)
+            if k.sameMs > 0 and W.rng.chance(k.sameMs) then
+                local avoid = W.rng.pick({ "MISS", "DODGE", "PARRY" })
+                outcome(t, { dst = ev.ourTarget, ourTarget = ev.ourTarget, act = avoid, amount = 0 }, 3)
+            end
+        elseif kind == "land" then
+            outcome(t, ev, 1, ev.hand, ev.swing.t)
+        elseif kind == "strike" and ev.src ~= us then -- G 177249/177250: WOUND 0, then the damage 1 ms later
+            outcome(t, { dst = ev.dst, ourTarget = ev.ourTarget, act = "WOUND", amount = 0, school = 1 }, 2)
+            outcome(t + 0.001, ev, 2)
+        elseif kind == "strike" then
+            castN = castN + 1
+            local frame = { dst = ev.dst, ourTarget = ev.ourTarget, act = "WOUND", amount = 0, school = 1 }
+            if W.rng.chance(0.5) then -- P log 1's order, then the brief's: swing and success either way round
+                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, M.SPELLS[ev.spell])
+                outcome(t, frame, 1)
+                push(t, "PLAYER_SWING", ev.speed, 0)
+            else
+                push(t, "PLAYER_SWING", ev.speed, 0)
+                outcome(t, frame, 1)
+                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, M.SPELLS[ev.spell])
+            end
+            outcome(t + 0.001, ev, 1)
+        elseif kind == "cast" and ev.src == us then
+            castN = castN + 1
+            push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, M.SPELLS[ev.spell])
+        elseif kind == "cast" and party[ev.src] then
+            push(t, "UNIT_SPELLCAST_SUCCEEDED", party[ev.src], fake.SECRET, fake.SECRET)
+        elseif kind == "proc" then -- G5: the wound on the target, then a heal of the same amount on us, same ms
+            outcome(t, ev, 1)
+            outcome(t, { dst = us, onUs = ev.onUs, act = "HEAL", amount = ev.amount, school = 1 }, 0)
+        elseif ev.act and ev.dst then -- another source's outcome, our DoT's tick, a hit on us or on someone else
+            outcome(t, ev, (ev.src == us) and 1 or 2)
+        end
+        if ev.power then
+            deltas[#deltas + 1] = { t + (ev.cost and 0 or k.usableDelay), (ev.rage or 0) - (ev.cost or 0) }
+            push(t, "@truth", ev.power) -- the metrics' truth (harness design §3.3), no client answer
+        end
+    end
+    if k.usable then
+        table.sort(deltas, function(a, b)
+            return a[1] < b[1]
+        end)
+        local usable, p = {}, 0
+        for _, c in ipairs(M.COSTS) do
+            usable[c[1]] = 2
+            push(0, "@usable", c[1], 2)
+        end
+        for _, d in ipairs(deltas) do
+            p = math.min(us.powerMax, p + d[2]) -- unclamped below: a spend can land before a delayed gain
+            local flipped = false
+            for _, c in ipairs(M.COSTS) do
+                local st = p >= c[2] and 1 or 2
+                if usable[c[1]] ~= st then
+                    usable[c[1]] = st
+                    push(d[1], "@usable", c[1], st)
+                    flipped = true
+                end
+            end
+            if flipped then
+                push(d[1], "SPELL_UPDATE_USABLE")
+            end
+        end
+    end
+    table.sort(list, function(a, b)
+        return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
+    end)
+    local s = { n = #list, t = {}, ev = {}, a1 = {}, a2 = {}, a3 = {}, a4 = {}, a5 = {} }
+    s.src, s.hand, s.swingT, s.actor = {}, {}, {}, {}
+    for i, e in ipairs(list) do
+        s.t[i], s.ev[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i] = e[1], e[3], e[4], e[5], e[6], e[7], e[8]
+        s.src[i], s.hand[i], s.swingT[i], s.actor[i] = e[9], e[10], e[11], e[12]
+    end
+    return s
+end
+
+return M
diff --git a/tests/Virtual/harness/rng.lua b/tests/Virtual/harness/rng.lua
new file mode 100644
index 00000000..f84d93a9
--- /dev/null
+++ b/tests/Virtual/harness/rng.lua
@@ -0,0 +1,34 @@
+-- tests/Virtual/harness/rng.lua (harness design §3.1): a seeded generator that gives the same stream on every machine.
+-- Lua 5.1's math.random is the C library's (it differs between machines), and Lua 5.1 has no bit operators for a
+-- xorshift: this is the Park-Miller minimal standard generator (multiplier 48271, modulus 2^31 - 1), exact in doubles.
+local M = {}
+
+--- A generator seeded with `seed` (any integer). `next()` in [0, 1), `int(a, b)` in [a, b], `chance(p)`,
+--- `normal(mu, sd)` (Box-Muller), `pick(list)`.
+function M.new(seed)
+    local s = (math.floor(seed or 1) % 2147483646) + 1
+    local r = {}
+    function r.next()
+        s = s * 48271 % 2147483647
+        return (s - 1) / 2147483646
+    end
+    function r.int(a, b)
+        return a + math.floor(r.next() * (b - a + 1))
+    end
+    function r.chance(p)
+        return r.next() < p
+    end
+    function r.normal(mu, sd)
+        local u = 1 - r.next()
+        return mu + sd * math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * r.next())
+    end
+    function r.pick(list)
+        return list[r.int(1, #list)]
+    end
+    for _ = 1, 10 do -- the first draws of nearby seeds are close: discard them
+        r.next()
+    end
+    return r
+end
+
+return M
diff --git a/tests/Virtual/harness/scenarios.lua b/tests/Virtual/harness/scenarios.lua
new file mode 100644
index 00000000..49098208
--- /dev/null
+++ b/tests/Virtual/harness/scenarios.lua
@@ -0,0 +1,151 @@
+-- tests/Virtual/harness/scenarios.lua (harness design §3.1 layer 5, §3.2): a scenario is a roster, a behaviour per
+-- entity and a timeline of set pieces (pull, stop, formChange, damageBuff, targetSwitch); between them the fight is
+-- emergent. Our character auto-attacks and presses a scripted list. Archetypes by shape only (boundary rule).
+local world = require("Virtual.harness.world")
+local entities = require("Virtual.harness.entities")
+local behaviours = require("Virtual.harness.behaviours")
+local observer = require("Virtual.harness.observer")
+
+local M = {}
+
+-- Another source on our target, by shape: `melee` (white hits inside our main-hand range, glancing 1-5 and strike
+-- frames as G's partner), `caster` (school-8 spells as G's partner's), `pet` (one quick weapon), `ranged` (a physical
+-- stand-in: a 2-3 s period, no dodge or parry by the target's facing).
+local ARCHETYPES = {
+    melee = function(W, lvl)
+        local w = entities.weapons(lvl)[1]
+        local e = entities.new({ weapons = { { w[1], w[2], 2.0 + W.rng.next() } }, level = lvl })
+        local rates = { miss = 0.08, dodge = 0.05, parry = 0.02, glancing = 0.1, crit = 0.1 }
+        return e, behaviours.melee({ rates = rates, glance = { 1, 5 }, strikes = 0.4, strike = { w[1], w[2] } })
+    end,
+    caster = function(W, lvl)
+        local k = lvl / 22
+        local e = entities.new({ level = lvl })
+        return e, behaviours.caster({ every = 2.5, amount = { math.floor(30 * k), math.floor(45 * k) }, school = 8 })
+    end,
+    pet = function(W, lvl)
+        local w = entities.weapons(lvl)[2]
+        local e = entities.new({ kind = "pet", weapons = { { w[1], w[2], 1.6 + 0.4 * W.rng.next() } }, level = lvl })
+        return e, behaviours.melee({ rates = { miss = 0.08, dodge = 0.05, parry = 0.02, crit = 0.1 } })
+    end,
+    ranged = function(W, lvl)
+        local w = entities.weapons(lvl)[1]
+        local e = entities.new({ weapons = { { w[1], w[2], 2.0 + W.rng.next() } }, level = lvl })
+        return e, behaviours.melee({ rates = { miss = 0.05, crit = 0.1 } })
+    end,
+}
+M.ARCHETYPES = ARCHETYPES
+
+-- shortcut: only the other sources on our target are simulated (the rest fire rows on tokens nothing reads), with no
+-- heals on party members and no parry haste on our swing timer; add them when a customer reads them.
+
+--- The world of one fight. Knobs `o` (defaults in brackets): duration [120], level [22], dr [0], rates (ours),
+--- lag (observer knobs), others { archetype, ... } on our target [none], attackers [1] (mobs on us; the first is our
+--- target), mobPeriod [2.0], mobDamage { lo, hi } [10-14], plainSpeed, damageBuff (t: +20% in combat), formAt (t),
+--- presses ({ t, spell, cost, kind }), rage ({ main, off } [9, 5]), max (our power cap [1e6]), proc, mobs (per
+--- attacker { damage = { lo, hi }, period }) and joinAt ({ [attacker] = t: on us from t }) for hits on us, switches.
+function M.build(o, seed)
+    local W = world.new(seed)
+    local lvl = o.level or 22
+    local us = W.add(
+        entities.new({ guid = "Player-1", level = lvl, weapons = entities.weapons(lvl), powerMax = o.max or 1e6 })
+    )
+    local mobs = {}
+    for i = 1, math.max(1, o.attackers or 1) do
+        local m = o.mobs and o.mobs[i] or {}
+        local dmg = m.damage or o.mobDamage or { 10, 14 }
+        local mob = W.add(entities.new({
+            guid = "Creature-" .. i,
+            kind = "mob",
+            level = lvl,
+            dr = i == 1 and (o.dr or 0) or 0,
+            weapons = { { dmg[1], dmg[2], m.period or o.mobPeriod or 2.0 } },
+            health = 1e9,
+        }))
+        mob.target = (i <= (o.attackers or 1) and not (o.joinAt and o.joinAt[i])) and us or nil
+        mobs[i] = mob
+    end
+    us.target = mobs[1]
+    local others = {}
+    for i, kind in ipairs(o.others or {}) do
+        local e, b = ARCHETYPES[kind](W, lvl)
+        e.guid = "Other-" .. i
+        e.target = mobs[1]
+        others[i] = { e = W.add(e), b = b }
+    end
+    local pull, stop = 1, (o.duration or 120) + 1
+    W.at(pull, function()
+        W.emit({ kind = "pull" })
+        behaviours.melee({
+            rates = o.rates,
+            land = observer.lag(o.lag),
+            rage = o.rage or { 9, 5 },
+            presses = o.presses,
+            strike = { 70, 90 },
+            dot = { 3, 5, 13 },
+            proc = o.proc,
+        })(W, us)
+        for i = 1, #mobs do
+            if i <= (o.attackers or 1) then
+                behaviours.mob({ phase = 0.3 + W.rng.next() * 2 })(W, mobs[i])
+            end
+        end
+        for _, x in ipairs(others) do
+            x.b(W, x.e)
+        end
+    end)
+    if o.damageBuff then
+        W.at(o.damageBuff, function()
+            us.dmgMult = 1.2
+            W.emit({ kind = "buff" })
+        end)
+    end
+    if o.formAt then
+        W.at(o.formAt, function()
+            us.form = 1
+            for _, w in ipairs(us.weapons) do -- the form's own weapon damage: the cache holds the old one
+                w[1], w[2] = math.floor(w[1] * 1.6), math.floor(w[2] * 1.6)
+            end
+            W.emit({ kind = "form", form = 1 })
+        end)
+    end
+    for i, t in pairs(o.joinAt or {}) do -- attacker i turns to us at t
+        W.at(t, function()
+            mobs[i].target = us
+            W.emit({ kind = "target" })
+        end)
+    end
+    for _, sw in ipairs(o.switches or {}) do -- { t, attacker index, true: on us / false: off us }
+        W.at(sw[1], function()
+            mobs[sw[2]].target = sw[3] and us or nil
+            W.emit({ kind = "target" })
+        end)
+    end
+    W.at(stop, function()
+        for _, e in ipairs(W.ents) do
+            e.stopped = true
+        end
+        W.emit({ kind = "stop" })
+    end)
+    W.run(stop + 3)
+    return W
+end
+
+--- The observed stream of a built world (knobs `o.lag` for the observer; `o.plainSpeed`, `o.usable` over them).
+function M.stream(o, seed)
+    local W = M.build(o, seed)
+    local k = setmetatable({ plainSpeed = o.plainSpeed, usable = o.usable }, { __index = o.lag or observer.DEFAULTS })
+    return observer.observe(W, k), W
+end
+
+--- The oracle's scenario knobs over `o`: usability answered from our true power (rage capped at 100) and a 10-rage
+--- spender pressed every 2 s when the true rage covers it, so rage crosses the spenders' costs (10, 15) all fight.
+function M.oracle(o)
+    local presses = {}
+    for t = 3, (o.duration or 120), (o.pressEvery or 2) do
+        presses[#presses + 1] = { t, "CAST", 10, "cast" }
+    end
+    return setmetatable({ usable = true, max = 100, presses = presses }, { __index = o })
+end
+
+return M
diff --git a/tests/Virtual/harness/world.lua b/tests/Virtual/harness/world.lua
new file mode 100644
index 00000000..515a9d9a
--- /dev/null
+++ b/tests/Virtual/harness/world.lua
@@ -0,0 +1,86 @@
+-- tests/Virtual/harness/world.lua (harness design §3.1, layer 3): runs every behaviour on one clock (a queue by time)
+-- and records the TRUE event stream, with the effects the world applies itself (health, our rage). Test code: it
+-- allocates freely; the drive loop (drive.lua) reads the observer's flat arrays, never this.
+local rng = require("Virtual.harness.rng")
+
+local M = {}
+
+--- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
+--- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
+--- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "pull", "stop", "form", "buff",
+--- "target".
+function M.new(seed)
+    local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), ents = {} }
+
+    --- Runs `fn(W)` at time `t` (after everything already queued for `t`).
+    function W.at(t, fn)
+        W.seq = W.seq + 1
+        local item, q = { t = t, seq = W.seq, fn = fn }, W.q
+        local lo, hi = 1, #q + 1
+        while lo < hi do
+            local mid = math.floor((lo + hi) / 2)
+            local m = q[mid]
+            if m.t < t or (m.t == t and m.seq < item.seq) then
+                lo = mid + 1
+            else
+                hi = mid
+            end
+        end
+        table.insert(q, lo, item)
+    end
+
+    --- Records a truth event at the clock (or at `ev.t`) and applies its effects: a wound takes health, our landed
+    --- wound pays our rage (`ev.rage`), a cast spends it (`ev.cost`); a pull or stop keeps our weapon damage then.
+    function W.emit(ev)
+        ev.t = ev.t or W.t
+        W.truth[#W.truth + 1] = ev
+        local me = W.ents[1]
+        if me then -- who our target is, and whether it targets us, at this event (the tokens that fire for it)
+            ev.ourTarget, ev.onUs = me.target, me.target ~= nil and me.target.target == me
+        end
+        if ev.kind == "pull" or ev.kind == "target" then -- whom each entity targets now (its tokens' answers)
+            ev.targets = {}
+            for _, e in ipairs(W.ents) do
+                ev.targets[e] = e.target or false
+            end
+        end
+        if (ev.kind == "pull" or ev.kind == "stop") and me then -- the weapon damage UnitDamage would read now
+            local w, m = me.weapons, me.dmgMult
+            local o = w[2] or { 0, 0 }
+            ev.damage = { w[1][1] * m, w[1][2] * m, o[1] * m, o[2] * m }
+        end
+        if ev.act == "WOUND" and ev.dst and ev.kind ~= "swing" then
+            ev.dst.health = math.max(0, ev.dst.health - (ev.amount or 0))
+        end
+        local us = W.ents[1]
+        if ev.src == us and (ev.rage or ev.cost) then
+            us.power = math.min(us.powerMax, math.max(0, us.power + (ev.rage or 0) - (ev.cost or 0)))
+            ev.power = us.power
+        end
+        return ev
+    end
+
+    --- Adds an entity (the first is our character) and its behaviour `fn(W, e)`, started at once.
+    function W.add(e, behaviour)
+        W.ents[#W.ents + 1] = e
+        if behaviour then
+            behaviour(W, e)
+        end
+        return e
+    end
+
+    --- Runs the queue up to `tEnd`.
+    function W.run(tEnd)
+        local q = W.q
+        while q[1] and q[1].t <= tEnd do
+            local item = table.remove(q, 1)
+            W.t = item.t
+            item.fn(W)
+        end
+        W.t = tEnd
+    end
+
+    return W
+end
+
+return M
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `496 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 119 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      496 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual tests/Virtual tools docs/dev | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|undead|maul|heroic|overpower|shred|bloodrage|charge|grave|bear'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add .busted .luacheckrc tests/Virtual/Events/pairing_replay_spec.lua tests/Virtual/State/helpers/fake_api.lua \
  tests/Virtual/harness/alloc_spec.lua tests/Virtual/harness/behaviours.lua tests/Virtual/harness/drive.lua \
  tests/Virtual/harness/entities.lua tests/Virtual/harness/fixtures/log1.lua tests/Virtual/harness/fixtures/log2.lua \
  tests/Virtual/harness/fixtures/log3.lua tests/Virtual/harness/fixtures/log5.lua \
  tests/Virtual/harness/fixtures_spec.lua tests/Virtual/harness/observer.lua tests/Virtual/harness/observer_spec.lua \
  tests/Virtual/harness/rng.lua tests/Virtual/harness/scenarios.lua tests/Virtual/harness/world.lua
git commit -m "test(harness): a headless model of the Forever client (entities, behaviours, world, observer, scenarios) with the logs as fitted fixtures (combat harness design §3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin combat-harness`

---
### Task 2: Attribution by score: Rows.lua's model, and the harness gates

Spec §1.1-§1.5 (the model), §3.3 (metrics), §3.4 (the solo, buff, form, party, pet, raid and sweep rows, the fixture rows), §6 §1's frame cases (as amended by Deviations 1-4).

**Files:**
- Modify: `src/Hekili/Virtual/Events/Rows.lua`
- Test: `tests/Virtual/harness/metrics.lua` (new: the tallies), `tests/Virtual/harness/solo_spec.lua` (new: 3 gates), `tests/Virtual/harness/group_spec.lua` (new: 2 gates, the raid reported), `tests/Virtual/harness/sweep_spec.lua` (new, `#slow`: 18 cells), `tests/Virtual/harness/fixtures_spec.lua` (new describe "the fixtures replayed through Rows.lua": log 1, log 3, log 5), `tests/Virtual/Events/pairing_replay_spec.lua` (floors 34/36 and 31/33, crits 8 and 7 on their hand; the frame cases: G's frame, another player's strike frame, school 8, provisional avoid taken and kept, an avoid at neither lag, the lag learned and not on tail credits, "above" in place of the N = 3 case, the off hand's two references, form mismatch by timing, timing before the first read), `tests/Virtual/Events/cleu_rows_spec.lua` (the dodge at its lag, emitted at the window's close), `tests/Virtual/State/alloc_spec.lua` (a provisional avoid in the mix)

**Interfaces:**
- Consumes: `VS.Stat("UnitDamage")` and `I.damageForm` (the out-of-combat cache), `I.inCombat`, `I.ab` (`onNextSwing`, `startsCombat`), the target's `UNIT_COMBAT` (school in its fifth argument), `PLAYER_SWING`, our `UNIT_SPELLCAST_SUCCEEDED`.
- Produces (`I.Log`, shared with the tests):
  - `L.THETA = 5`, `L.Q = { 0.90, 0.08, 0.02 }`, `L.Q_AVOID = 0.22`, `L.EPS = { 0.12, 0.10 }`, `L.LAMBDA0, L.T0, L.TAU = 0.01, 5, 10`, `L.PAIR_WINDOW_MS` (the support);
  - learned `L.med`, `L.spr` (references 1 main, 2 off own, 3 off from the main swing; seeds `L.MED0`, `L.SPR0`), `L.bg[1..8]`, `L.quiet`;
  - counters `L.credited = { main, off, cast }`, `L.background`, `L.avoidsBack`;
  - the rows as before (SWING_DAMAGE / SWING_MISSED / SPELL_*), a provisional avoid's SWING_MISSED at the window's close; `Swing` c = 1 (b = 0 until Task 3) and c = 3 as before.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/Events/cleu_rows_spec.lua b/tests/Virtual/Events/cleu_rows_spec.lua
index 415b3234..97f0b0ac 100644
--- a/tests/Virtual/Events/cleu_rows_spec.lua
+++ b/tests/Virtual/Events/cleu_rows_spec.lua
@@ -230,33 +230,38 @@ describe("the synthesized combat log", function()
             return got[i] and got[i].row
         end
 
-        it("pairs a swing with the target's dodge that follows it: SWING_MISSED at the swing's time", function()
-            ctl.now = 10
-            ctl.Fire("PLAYER_SWING", 2.6, 0)
-            assert.are.equal(0, #got)
-            ctl.now = 10.05
-            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
-            assert.are.equal(1, #got)
-            assert.are.same({
-                10,
-                "SWING_MISSED",
-                false,
-                "Player-1",
-                "",
-                L.PLAYER_FLAGS,
-                0,
-                "Creature-1",
-                "",
-                L.HOSTILE_FLAGS,
-                0,
-                "DODGE",
-                false,
-                0,
-                false,
-            }, row(1))
-            assert.are.equal(15, got[1].n)
-            assert.are.equal(10, got[1].now) -- back-dated to the swing
-        end)
+        it(
+            "credits a swing the target's dodge at its lag: SWING_MISSED at the swing's time when its window closes",
+            function()
+                ctl.now = 10
+                ctl.Fire("PLAYER_SWING", 2.6, 0)
+                assert.are.equal(0, #got)
+                ctl.now = 10.47 -- the main hand's lag (harness design §1.1: median 474 ms)
+                ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
+                assert.are.equal(0, #got) -- provisional: a wound of that swing could still take it
+                ctl.Tick(11.55)
+                assert.are.equal(1, #got)
+                assert.are.same({
+                    10,
+                    "SWING_MISSED",
+                    false,
+                    "Player-1",
+                    "",
+                    L.PLAYER_FLAGS,
+                    0,
+                    "Creature-1",
+                    "",
+                    L.HOSTILE_FLAGS,
+                    0,
+                    "DODGE",
+                    false,
+                    0,
+                    false,
+                }, row(1))
+                assert.are.equal(15, got[1].n)
+                assert.are.equal(10, got[1].now) -- back-dated to the swing
+            end
+        )
 
         it("pairs a swing only with a wound that follows it: SWING_DAMAGE at the swing's time", function()
             ctl.now = 20
diff --git a/tests/Virtual/Events/pairing_replay_spec.lua b/tests/Virtual/Events/pairing_replay_spec.lua
index 02c3f506..10fd4dc7 100644
--- a/tests/Virtual/Events/pairing_replay_spec.lua
+++ b/tests/Virtual/Events/pairing_replay_spec.lua
@@ -51,7 +51,7 @@ describe("swing/outcome pairing", function()
                 lastHand, lastAmount, lastLag = a21 and 2 or 1, a12, ctl.now - t
             end
             if record then
-                got[#got + 1] = { ev, a12, a13, a15, a21 }
+                got[#got + 1] = { ev, a12, a13, a15, a21, t }
             end
         end)
         sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
@@ -106,13 +106,15 @@ describe("swing/outcome pairing", function()
         ctl.Tick(base + 130)
     end
 
-    it("pairs log 2's wounds with their own hand's swing, within the hand's window", function()
+    it("credits log 2's wounds to their own hand's swing, within the hand's window (harness design §3.4)", function()
         start(36, 50, 24, 32)
         replay(10)
         assert.are.same({ 36, 33 }, { stats.main, stats.off }) -- the 34 and 31 hits plus the 4 orphans of the doc
-        assert.is_true(stats.mainOk >= 30, "main hand paired: " .. stats.mainOk)
-        assert.is_true(stats.offOk >= 28, "off hand paired: " .. stats.offOk)
-        assert.are.same({ 8, 8 }, { stats.crits, stats.critOk })
+        assert.is_true(stats.mainOk >= 34, "main hand paired: " .. stats.mainOk)
+        assert.is_true(stats.offOk >= 31, "off hand paired: " .. stats.offOk)
+        -- the last crit (52 at 116581: 369 ms after the main swing, 103 ms after the off swing) scores as the main
+        -- hand's by its lag, though its amount is the off hand's
+        assert.are.same({ 8, 7 }, { stats.crits, stats.critOk })
         assert.are.equal(0, stats.late)
     end)
 
@@ -171,28 +173,30 @@ describe("swing/outcome pairing", function()
             assert.are.equal(1, landed[1])
         end)
 
-        it("pays a swing whose wound is outside the cached ranges when the form changed since the read", function()
-            ctl.form = 1 -- Bear Form: the cache holds the caster's weapon damage
+        it("credits a wound outside the cached ranges by timing alone when the form changed since the read", function()
+            ctl.form = 1 -- a form whose weapon damage the cache never read
             fire(10, "PLAYER_SWING", 2.5, 0)
             fire(10.45, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
             assert.are.same({ "SWING_DAMAGE", 120, 1 }, { got[1][1], got[1][2], landed[1] })
         end)
 
-        it("treats the cache as stale after 3 white wounds in a row fit no range (a damage buff)", function()
-            fire(10, "PLAYER_SWING", 2.2, 0)
-            fire(10.2, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
-            fire(10.3, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
-            assert.are.same({ 0, 0 }, { #got, landed[1] })
-            fire(10.4, "UNIT_COMBAT", "target", "WOUND", "", 120, 1)
-            fire(12.2, "PLAYER_SWING", 2.2, 0)
-            fire(12.6, "UNIT_COMBAT", "target", "WOUND", "", 121, 1)
-            assert.are.same(
-                { "SWING_DAMAGE", 120, "SWING_DAMAGE", 121, 2 },
-                { got[1][1], got[1][2], got[2][1], got[2][2], landed[1] }
-            )
-        end)
+        it(
+            "credits an above-range wound in the core band solo, and rejects it once that class's background is up",
+            function()
+                fire(10, "PLAYER_SWING", 2.2, 0)
+                fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 70, 1) -- above the main hand's 50 (a buff since the read)
+                assert.are.same({ "SWING_DAMAGE", 70, 1 }, { got[1][1], got[1][2], landed[1] })
+                fire(12, "PLAYER_REGEN_DISABLED")
+                for k = 1, 10 do -- in combat with nothing of ours pending: background
+                    fire(12 + k, "UNIT_COMBAT", "target", "WOUND", "", 70, 1)
+                end
+                fire(23, "PLAYER_SWING", 2.2, 0)
+                fire(23.47, "UNIT_COMBAT", "target", "WOUND", "", 70, 1)
+                assert.are.same({ 1, 11 }, { landed[1], L.background })
+            end
+        )
 
-        it("drops a wound that fits neither hand (a Rend tick), and the swing takes the next that fits", function()
+        it("drops a wound that fits neither hand (a DoT tick), and the swing takes the next that fits", function()
             fire(10, "PLAYER_SWING", 2.2, 0)
             fire(10.3, "UNIT_COMBAT", "target", "WOUND", "", 13, 1)
             assert.are.equal(0, #got)
@@ -200,42 +204,107 @@ describe("swing/outcome pairing", function()
             assert.are.same({ "SWING_DAMAGE", 45, false }, { got[1][1], got[1][2], got[1][5] })
         end)
 
-        it("gives a wound to the hand whose exact range holds it, else the older pending swing", function()
+        it(
+            "gives a wound to the hand whose exact range holds it when both lags fit, else to the better-timed swing",
+            function()
+                fire(9.77, "PLAYER_SWING", 2.5, 1)
+                fire(10, "PLAYER_SWING", 2.2, 0)
+                fire(10.473, "UNIT_COMBAT", "target", "WOUND", "", 30, 1) -- loosely both hands', exactly the off hand's
+                fire(20, "PLAYER_SWING", 2.5, 1)
+                fire(20.2, "PLAYER_SWING", 2.2, 0)
+                fire(20.703, "UNIT_COMBAT", "target", "WOUND", "", 34, 1) -- loosely both, exactly neither: the off hand's lag
+                assert.are.same(
+                    { "SWING_DAMAGE", 30, true, "SWING_DAMAGE", 34, true },
+                    { got[1][1], got[1][2], got[1][5], got[3][1], got[3][2], got[3][5] }
+                )
+            end
+        )
+
+        it("credits the off hand 0.703 s after its own swing or 1.686 s after the main swing before it", function()
             fire(10, "PLAYER_SWING", 2.2, 0)
-            fire(10.2, "PLAYER_SWING", 2.5, 1)
-            fire(10.6, "UNIT_COMBAT", "target", "WOUND", "", 30, 1) -- loosely both hands', exactly the off hand's
+            fire(10.3, "PLAYER_SWING", 2.5, 1)
+            fire(11.686, "UNIT_COMBAT", "target", "WOUND", "", 28, 1) -- 1.386 s after its own: the main reference
             fire(20, "PLAYER_SWING", 2.5, 1)
-            fire(20.2, "PLAYER_SWING", 2.2, 0)
-            fire(20.6, "UNIT_COMBAT", "target", "WOUND", "", 34, 1) -- loosely both (21.6-55, 14.4-35.2), exactly neither
-            assert.are.same(
-                { "SWING_DAMAGE", 30, true, "SWING_DAMAGE", 34, true },
-                { got[1][1], got[1][2], got[1][5], got[3][1], got[3][2], got[3][5] }
-            )
+            fire(20.703, "UNIT_COMBAT", "target", "WOUND", "", 29, 1)
+            assert.are.same({ 28, true, 29, true }, { got[2][2], got[2][5], got[3][2], got[3][5] }) -- got[1]: main's 0
+            assert.are.same({ 0, 2 }, landed)
         end)
 
-        it("pairs an avoid with the older of two pending swings", function()
+        it(
+            "makes a glancing 4 at 7 ms and a MISS at 53 ms background, and credits our 50 at 369 ms (G's frame)",
+            function()
+                fire(10, "PLAYER_SWING", 2.2, 0)
+                fire(10.007, "UNIT_COMBAT", "target", "WOUND", "GLANCING", 4, 1)
+                fire(10.053, "UNIT_COMBAT", "target", "MISS", "", 0, 1)
+                fire(10.369, "UNIT_COMBAT", "target", "WOUND", "", 50, 1)
+                ctl.Tick(12)
+                assert.are.same({ { "SWING_DAMAGE", 50, 0, 0, false, 10 } }, got)
+            end
+        )
+
+        it("drops another player's strike frame (a WOUND 0, its damage 1 ms later, no success of ours)", function()
+            fire(10, "PLAYER_SWING", 2.2, 0)
+            fire(10.2, "UNIT_COMBAT", "target", "WOUND", "", 0, 1)
+            fire(10.201, "UNIT_COMBAT", "target", "WOUND", "", 40, 1)
+            assert.are.same({ 0, 0 }, { #got, landed[1] }) -- the swing is still pending
+            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 44, 1)
+            assert.are.same({ "SWING_DAMAGE", 44, 1 }, { got[1][1], got[1][2], landed[1] })
+        end)
+
+        it("gives no swing a wound of another school inside its range (a party caster's spell)", function()
+            fire(10, "PLAYER_SWING", 2.2, 0)
+            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 40, 8)
+            ctl.Tick(12)
+            assert.are.same({ "SWING_DAMAGE", 0, 0 }, { got[1][1], got[1][2], landed[1] }) -- the window closed unpaired
+        end)
+
+        it("credits an avoid provisionally, and the swing goes to the hand's wound that scores higher", function()
             fire(10, "PLAYER_SWING", 2.2, 0)
-            fire(10.1, "PLAYER_SWING", 2.5, 1)
             fire(10.4, "UNIT_COMBAT", "target", "DODGE", "", 0, 1)
-            fire(30, "PLAYER_SWING", 2.5, 1)
-            fire(30.1, "PLAYER_SWING", 2.2, 0)
-            fire(30.4, "UNIT_COMBAT", "target", "PARRY", "", 0, 1)
-            assert.are.same(
-                { "SWING_MISSED", "DODGE", false, "SWING_MISSED", "PARRY", true },
-                { got[1][1], got[1][2], got[1][3], got[3][1], got[3][2], got[3][3] }
-            )
+            fire(10.47, "UNIT_COMBAT", "target", "WOUND", "", 44, 1)
+            ctl.Tick(12)
+            assert.are.same({ { "SWING_DAMAGE", 44, 0, 0, false, 10 } }, got) -- no SWING_MISSED
+            assert.are.same({ 1, 1 }, { landed[1], L.avoidsBack })
+        end)
+
+        it("keeps an avoid nothing beats: SWING_MISSED when the window closes, back-dated to the swing", function()
+            fire(10, "PLAYER_SWING", 2.2, 0)
+            fire(10.47, "UNIT_COMBAT", "target", "PARRY", "", 0, 1)
+            ctl.Tick(11.45)
+            assert.are.equal(0, #got)
+            ctl.Tick(11.55)
+            assert.are.same({ { "SWING_MISSED", "PARRY", false, false, nil, 10 } }, got)
+        end)
+
+        it("makes an avoid at neither hand's lag background", function()
+            fire(10, "PLAYER_SWING", 2.2, 0)
+            fire(10.05, "UNIT_COMBAT", "target", "DODGE", "", 0, 1) -- the same-ms avoids of log 2
+            ctl.Tick(12)
+            assert.are.same({ "SWING_DAMAGE", 0 }, { got[1][1], got[1][2] })
+        end)
+
+        it("moves the main lag's median and spread toward a stream of 520 ms lags, not on tail credits", function()
+            for k = 0, 39 do
+                fire(10 + 2.2 * k, "PLAYER_SWING", 2.2, 0)
+                fire(10.52 + 2.2 * k, "UNIT_COMBAT", "target", "WOUND", "", 44, 1)
+            end
+            assert.is_true(math.abs(L.med[1] - 0.52) <= 0.006 and L.spr[1] < 0.03, L.med[1] .. " " .. L.spr[1])
+            local med, spr = L.med[1], L.spr[1]
+            fire(200, "PLAYER_SWING", 2.2, 0)
+            fire(201.2, "UNIT_COMBAT", "target", "WOUND", "", 44, 1) -- in the tail: credited, not learned
+            assert.are.same({ 41, med, spr }, { landed[1], L.med[1], L.spr[1] })
         end)
     end)
 
-    it("pairs a wound with the oldest pending swing of either hand before the first UnitDamage read", function()
+    it("credits a wound by timing alone before the first UnitDamage read", function()
         start(0, 0, 0, 0)
         record = true
         ctl.Tick(10)
         ctl.Fire("PLAYER_SWING", 2.5, 1)
         ctl.Tick(10.2)
         ctl.Fire("PLAYER_SWING", 2.2, 0)
-        ctl.Tick(10.6)
-        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 45, 1) -- a main-hand amount, but no range to tell
-        assert.are.same({ "SWING_DAMAGE", 45, true }, { got[1][1], got[1][2], got[1][5] })
+        ctl.Tick(10.62)
+        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 45, 1) -- no range to tell: the main hand's lag
+        assert.are.same({ "SWING_DAMAGE", 45, false }, { got[1][1], got[1][2], got[1][5] })
     end)
 end)
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
index 7924e2ff..eefb0391 100644
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -1,8 +1,8 @@
 -- tests/Virtual/State/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
--- usability flipping on a health-gated spender, own casts, UNIT_AURA after a form swap, the target's UNIT_COMBAT, hits
--- on the player paying rage through a `taken`, combat ending and starting under a stepped rage decay) with a drain every
--- tick against the fake spec, every accessor and every facade policy and passthrough called, every combat-log row
--- delivered to a subscriber: VirtualState allocates nothing.
+-- usability flipping on a health-gated spender, own casts, UNIT_AURA after a form swap, the target's UNIT_COMBAT (wounds
+-- and provisional avoids), hits on the player paying rage through a `taken`, combat ending and starting under a stepped
+-- rage decay) with a drain every tick against the fake spec, every accessor and every facade policy and passthrough
+-- called, every combat-log row delivered to a subscriber: VirtualState allocates nothing.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local fs = require("Virtual.State.helpers.fake_spec")
@@ -100,7 +100,8 @@ describe("zero allocation", function()
                 ctl.Fire("UPDATE_SHAPESHIFT_FORM")
                 ctl.Fire("UNIT_AURA", "player")
             else
-                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 1)
+                local dodge = i % 12 == 5 -- an avoid at the swing's lag: provisional, SWING_MISSED at the window's close
+                ctl.Fire("UNIT_COMBAT", "target", dodge and "DODGE" or "WOUND", "", dodge and 0 or 10, 1)
                 ctl.Fire("UNIT_COMBAT", "player", "WOUND", i % 12 == 5 and "BLOCK" or "", 12, 1)
             end
             if i % 100 == 50 then
diff --git a/tests/Virtual/harness/fixtures_spec.lua b/tests/Virtual/harness/fixtures_spec.lua
index aa53059f..1ec105d7 100644
--- a/tests/Virtual/harness/fixtures_spec.lua
+++ b/tests/Virtual/harness/fixtures_spec.lua
@@ -112,3 +112,69 @@ describe("the fixtures and the model's fit", function()
         end
     end)
 end)
+
+describe("the fixtures replayed through Rows.lua", function()
+    -- Replays fixture `name` (its token rows as recorded, or one row per outcome as "target" when `dedupe`).
+    local function replay(name, dedupe)
+        local fix = require("Virtual.harness.fixtures." .. name)
+        local s = drive.fixtureStream(fix, 10, dedupe)
+        local c = drive.boot()
+        drive.run(c, s)
+        drive.restore(c)
+        return c, s
+    end
+
+    -- The stream index of the target's `act` of `amount` at `ms`.
+    local function at(s, ms, act, amount)
+        for i = 1, s.n do
+            local hit = s.ev[i] == "UNIT_COMBAT" and s.a1[i] == "target" and s.a2[i] == act and s.a4[i] == amount
+            if hit and math.abs(s.t[i] - 10 - ms / 1000) < 1e-6 then
+                return i
+            end
+        end
+        error(("no target %s %d at %d"):format(act, amount, ms))
+    end
+
+    it(
+        "log 1: the strike frames' wounds are the casts', the DoT tick background, the crit 90 the main hand's",
+        function()
+            local c, s = replay("log1")
+            assert.are.same({ 0, 0 }, { c.crHand[at(s, 4331, "WOUND", 77)], c.crHand[at(s, 6532, "WOUND", 84)] })
+            assert.are.equal(2, c.rows.spell) -- SPELL_DAMAGE 77 and 84
+            assert.are.equal(0, c.crHand[at(s, 5847, "WOUND", 13)])
+            local crit = at(s, 2463, "WOUND", 90)
+            assert.are.same({ 1, 12.110 }, { c.crHand[crit], c.crAt[crit] }) -- 353 ms after the main swing (P's reading)
+            assert.is_true(c.crHand[at(s, 2463, "WOUND", 30)] ~= 1) -- background, or the off hand's (1.692 s after main)
+        end
+    )
+
+    it("log 3: our 50 credited to the main hand; the partner's glancing, miss and strike frames background", function()
+        local c, s = replay("log3")
+        local ours = at(s, 165485, "WOUND", 50)
+        assert.are.same({ 1, 175.116 }, { c.crHand[ours], c.crAt[ours] })
+        assert.are.same({ 0, 0 }, { c.crHand[at(s, 165124, "WOUND", 4)], c.crHand[at(s, 165169, "MISS", 0)] })
+        for i = 1, s.n do
+            if s.t[i] >= 10 + 160.779 and s.ev[i] == "UNIT_COMBAT" and s.a5[i] ~= 1 then
+                assert.are.equal(0, c.crHand[i]) -- the partner's school-8 spells
+            elseif s.t[i] >= 10 + 174.816 and s.t[i] <= 10 + 205.518 then
+                assert.are.equal(0, c.crHand[i]) -- segment C: we idle, his strike frames on nameplate2 included
+            end
+        end
+    end)
+
+    it("log 5 (G5): the main hand's 22 wounds, >= 18 of the off hand's 20, never the on-swing proc", function()
+        local c, s = replay("log5", true)
+        local main, off = 0, 0
+        for i = 1, s.n do
+            if s.ev[i] == "UNIT_COMBAT" and s.a2[i] == "WOUND" and s.a4[i] > 0 and c.crHand[i] > 0 then
+                local a = s.a3[i] == "CRITICAL" and s.a4[i] / 2 or s.a4[i]
+                assert.are.equal(1, s.a5[i]) -- the school-32 proc is no swing's
+                local hand = a > 38 and 1 or 2
+                main, off =
+                    main + (hand == 1 and c.crHand[i] == 1 and 1 or 0),
+                    off + (hand == 2 and c.crHand[i] == 2 and 1 or 0)
+            end
+        end
+        assert.is_true(main == 22 and off >= 18, ("main %d/22 off %d/20"):format(main, off))
+    end)
+end)
diff --git a/tests/Virtual/harness/group_spec.lua b/tests/Virtual/harness/group_spec.lua
new file mode 100644
index 00000000..ab9fb01c
--- /dev/null
+++ b/tests/Virtual/harness/group_spec.lua
@@ -0,0 +1,32 @@
+-- tests/Virtual/harness/group_spec.lua (harness design §3.4, decisions D4-D5): other sources on our target (G fact 1:
+-- their outcomes arrive on our target's tokens with plain amounts), through the real Rows.lua; the gates of §3.4. The
+-- raid is reported, not gated (D5).
+local metrics = require("Virtual.harness.metrics")
+
+local function check(ok, m)
+    assert.is_true(ok, metrics.line(m))
+end
+
+describe("group attribution (harness gates)", function()
+    it("party of 5, a melee in our main range and a caster on our target (100 fights)", function()
+        local m = metrics.fights({ others = { "melee", "caster" } }, 100)
+        check(metrics.rate(m, 1) >= 0.75 and metrics.rate(m, 2) >= 0.85, m)
+        check(metrics.falsePer100(m) <= 4 and m.over <= 0.05 * m.windows, m)
+    end)
+
+    it("party of 5 with a pet and a ranged stand-in on our target as well (100 fights)", function()
+        local m = metrics.fights({ others = { "melee", "caster", "pet", "ranged" } }, 100)
+        check(metrics.rate(m, 1) >= 0.70 and metrics.rate(m, 2) >= 0.70, m)
+        check(metrics.falsePer100(m) <= 6 and m.over <= 0.10 * m.windows, m)
+    end)
+
+    it("raid, 12 on our target: reported (30 fights)", function()
+        local others = {}
+        for i = 1, 12 do
+            others[i] = ({ "melee", "melee", "caster", "pet", "ranged", "melee" })[i % 6 + 1]
+        end
+        local m = metrics.fights({ others = others }, 30)
+        print("\nraid, 12 on target: " .. metrics.line(m))
+        assert.is_true(m.fights == 30)
+    end)
+end)
diff --git a/tests/Virtual/harness/metrics.lua b/tests/Virtual/harness/metrics.lua
new file mode 100644
index 00000000..d0719104
--- /dev/null
+++ b/tests/Virtual/harness/metrics.lua
@@ -0,0 +1,224 @@
+-- tests/Virtual/harness/metrics.lua (harness design §3.3): scores a run against the world's truth. Own hits per hand
+-- (credited to the right swing, to the wrong one, missed), false credits (another source's outcome, our tick or proc,
+-- or an unexplained avoid credited to a swing of ours), the rage error per 10 s window (believed est minus truth, each
+-- window as if pinned at its start) and the row checks.
+local M = {}
+
+--- A fresh tally (summed over fights by `score`).
+function M.new()
+    return {
+        fights = 0,
+        swings = 0,
+        own = { 0, 0 },
+        right = { 0, 0 },
+        wrong = { 0, 0 },
+        missed = { 0, 0 },
+        falses = { 0, 0 },
+        late = 0,
+        windows = 0,
+        over = 0,
+        loOver = 0,
+        estOver = 0,
+        danger = 0,
+        errSum = 0,
+        errMax = 0,
+        noDst = 0,
+        order = 0,
+        nonTarget = 0,
+        judged = 0,
+        falseJudged = 0,
+        caught = 0,
+        falseRetracted = 0,
+        rescued = 0,
+        rescuedOurs = 0,
+        onusAll = 0,
+        onusCredited = 0,
+        onusRight = 0,
+        hitsFed = 0,
+        hitsStaged = 0,
+    }
+end
+
+-- Our true power at `t`: the last truth event with a power at or before it (0 before any).
+local function truthAt(W, t)
+    local p = 0
+    for _, ev in ipairs(W.truth) do
+        if ev.t > t then
+            break
+        end
+        if ev.power then
+            p = ev.power
+        end
+    end
+    return p
+end
+M.truthAt = truthAt
+
+--- Adds one fight (drive captures `c`, stream `s`, world `W`) to tally `m`: the outcomes from `after` seconds on (default
+--- all). `step`: one main-hand step (the overshoot bar, default 9). Returns `m`.
+function M.score(m, c, s, W, step, after)
+    step, after = step or 9, after or 0
+    m.fights = m.fights + 1
+    for i = 1, s.n do
+        local ev = s.ev[i]
+        if ev == "PLAYER_SWING" then
+            m.swings = m.swings + 1
+        elseif ev == "UNIT_COMBAT" and s.a1[i] == "target" and s.t[i] >= after then
+            local h, cr = s.hand[i], c.crHand[i]
+            if s.src[i] == 1 and h > 0 and s.a2[i] == "WOUND" and s.a4[i] > 0 then
+                m.own[h] = m.own[h] + 1
+                if cr == h and c.crAt[i] == s.swingT[i] then
+                    m.right[h] = m.right[h] + 1
+                elseif cr > 0 then
+                    m.wrong[h] = m.wrong[h] + 1
+                else
+                    m.missed[h] = m.missed[h] + 1
+                end
+            elseif cr > 0 then
+                m.falses[cr] = m.falses[cr] + 1
+            end
+            local v = c.verdict[i]
+            if v > 0 then -- judged: another source's outcome (a false credit) or our own swing's (credited right)
+                local ours = s.src[i] == 1 and h > 0
+                m.judged = m.judged + 1
+                if not ours then
+                    m.falseJudged, m.caught = m.falseJudged + 1, m.caught + (v == 2 and 1 or 0)
+                elseif v == 2 and cr == h and c.crAt[i] == s.swingT[i] then
+                    m.falseRetracted = m.falseRetracted + 1
+                end
+            end
+        end
+        if c.crHand[i] > 0 and not c.crTok[i] then
+            m.nonTarget = m.nonTarget + 1
+        end
+    end
+    local HIT = { WOUND = true, BLOCK = true, DODGE = true, PARRY = true, MISS = true, HEAL = true }
+    for i = 1, s.n do -- hits on us (harness design §4.3): credited to the right attacker, and every one staged
+        if s.ev[i] == "UNIT_COMBAT" and s.a1[i] == "player" then
+            m.hitsFed = m.hitsFed + (HIT[s.a2[i]] and 1 or 0)
+            if s.src[i] == 2 and s.a2[i] ~= "HEAL" then
+                m.onusAll = m.onusAll + 1
+                if c.onus[i] ~= "" then
+                    m.onusCredited = m.onusCredited + 1
+                    if W and c.onus[i] == W.ents[s.actor[i]].guid then
+                        m.onusRight = m.onusRight + 1
+                    end
+                end
+            end
+        end
+    end
+    m.hitsStaged = m.hitsStaged + c.hits
+    m.late = m.late + c.nLate
+    for k = 1, c.nLate do -- a rescue was ours when it paid our swing whose wound landed and went uncredited
+        m.rescued = m.rescued + 1
+        for i = 1, s.n do
+            if s.src[i] == 1 and s.hand[i] == c.lateHand[k] and s.swingT[i] == c.lateAt[k] and s.a1[i] == "target" then
+                if s.a2[i] == "WOUND" and s.a4[i] > 0 and c.crHand[i] == 0 then
+                    m.rescuedOurs = m.rescuedOurs + 1
+                end
+                break
+            end
+        end
+    end
+    if W then
+        for w = 1, c.nWin - 1 do
+            local a, b = c.winT[w], c.winT[w + 1]
+            local err = (c.win[w + 1] - c.win[w]) - (truthAt(W, b) - truthAt(W, a))
+            m.windows = m.windows + 1
+            m.errSum = m.errSum + err
+            if math.abs(err) > m.errMax then
+                m.errMax = math.abs(err)
+            end
+            if err >= step then
+                m.over = m.over + 1
+            end
+            m.loOver = m.loOver + c.loOver[w]
+            m.estOver, m.danger = m.estOver + c.estOver[w], m.danger + c.danger[w]
+        end
+    end
+    m.noDst, m.order = m.noDst + c.rows.noDst, m.order + c.rows.order
+    return m
+end
+
+--- The share of hand h's own hits credited to the right swing.
+function M.rate(m, h)
+    return m.own[h] > 0 and m.right[h] / m.own[h] or 1
+end
+
+--- False credits per 100 of our swings.
+function M.falsePer100(m)
+    return m.swings > 0 and 100 * (m.falses[1] + m.falses[2]) / m.swings or 0
+end
+
+--- Runs `n` fights of scenario `o` (seeds 1..n), each on a fresh VirtualState, and returns their tally (outcomes
+--- from `after` seconds on).
+function M.fights(o, n, after)
+    local scenarios = require("Virtual.harness.scenarios")
+    local drive = require("Virtual.harness.drive")
+    local m = M.new()
+    for seed = 1, n do
+        local s, W = scenarios.stream(o, seed)
+        local c = drive.boot({ max = o.max, oracle = o.oracle })
+        drive.run(c, s)
+        M.score(m, c, s, W, 9, after)
+        drive.restore(c)
+    end
+    return m
+end
+
+--- The oracle's line: judged, false credits judged and caught, own credits retracted, rescues and how many were ours.
+function M.oracleLine(m)
+    return string.format(
+        "judged %d (%.1f a fight), false judged %d caught %d, own retracted %d of %d, rescued %d ours %d, lo over %d/%d",
+        m.judged,
+        m.judged / math.max(1, m.fights),
+        m.falseJudged,
+        m.caught,
+        m.falseRetracted,
+        m.right[1] + m.right[2],
+        m.rescued,
+        m.rescuedOurs,
+        m.loOver,
+        m.windows
+    ) .. string.format(", est over %d, danger %d", m.estOver, m.danger)
+end
+
+--- Hits on us: precision (credited to the right attacker / credited), coverage (credited / all), staged and fed.
+function M.onusLine(m)
+    return string.format(
+        "hits on us %d: credited %d, right %d (precision %.3f, coverage %.3f); PlayerHit staged %d of %d fed",
+        m.onusAll,
+        m.onusCredited,
+        m.onusRight,
+        m.onusCredited > 0 and m.onusRight / m.onusCredited or 1,
+        m.onusAll > 0 and m.onusCredited / m.onusAll or 1,
+        m.hitsStaged,
+        m.hitsFed
+    )
+end
+
+--- One line for a report (`busted` prints it in a failing assertion's message).
+function M.line(m)
+    return string.format(
+        "fights=%d main %d/%d (wrong %d, missed %d) off %d/%d (wrong %d, missed %d) false %d/%d (%.2f per 100 swings) "
+            .. "over %d/%d windows, err mean %.2f max %.1f",
+        m.fights,
+        m.right[1],
+        m.own[1],
+        m.wrong[1],
+        m.missed[1],
+        m.right[2],
+        m.own[2],
+        m.wrong[2],
+        m.missed[2],
+        m.falses[1],
+        m.falses[2],
+        M.falsePer100(m),
+        m.over,
+        m.windows,
+        m.windows > 0 and m.errSum / m.windows or 0,
+        m.errMax
+    )
+end
+
+return M
diff --git a/tests/Virtual/harness/solo_spec.lua b/tests/Virtual/harness/solo_spec.lua
new file mode 100644
index 00000000..33456b99
--- /dev/null
+++ b/tests/Virtual/harness/solo_spec.lua
@@ -0,0 +1,37 @@
+-- tests/Virtual/harness/solo_spec.lua (harness design §3.4, decisions D4-D5): solo fights of the log-2 profile, a
+-- damage buff in combat and a form change, through the real Rows.lua; the gates of §3.4.
+local metrics = require("Virtual.harness.metrics")
+
+local function check(ok, m)
+    assert.is_true(ok, metrics.line(m))
+end
+
+describe("solo attribution (harness gates)", function()
+    it(
+        "credits >= 94% of each hand's hits to the right swing, <= 2% to the wrong one, no overshoot (200 fights)",
+        function()
+            local m = metrics.fights({}, 200)
+            check(metrics.rate(m, 1) >= 0.94 and metrics.rate(m, 2) >= 0.94, m)
+            check(m.wrong[1] <= 0.02 * m.own[1] and m.wrong[2] <= 0.02 * m.own[2], m)
+            check(m.over == 0 and m.falses[1] + m.falses[2] == 0, m)
+            check(m.noDst == 0 and m.order == 0 and m.nonTarget == 0, m)
+        end
+    )
+
+    it(
+        "credits >= 85% of the main hand's hits after a +20% damage buff in combat, falsely none (100 fights)",
+        function()
+            local m = metrics.fights({ damageBuff = 30 }, 100, 31)
+            check(metrics.rate(m, 1) >= 0.85 and m.falses[1] + m.falses[2] == 0, m)
+        end
+    )
+
+    it(
+        "credits >= 85% of the hits after a form change (amount unknown: timing alone), falsely none (100 fights)",
+        function()
+            local m = metrics.fights({ formAt = 30 }, 100, 31)
+            check(metrics.rate(m, 1) >= 0.85 and metrics.rate(m, 2) >= 0.85, m)
+            check(m.falses[1] + m.falses[2] == 0, m)
+        end
+    )
+end)
diff --git a/tests/Virtual/harness/sweep_spec.lua b/tests/Virtual/harness/sweep_spec.lua
new file mode 100644
index 00000000..5943764a
--- /dev/null
+++ b/tests/Virtual/harness/sweep_spec.lua
@@ -0,0 +1,23 @@
+-- tests/Virtual/harness/sweep_spec.lua (harness design §3.4, D4): solo, levels 10-60 x armour DR 0 / 0.15 / 0.30, 20
+-- fights a cell. DR 0 holds the solo gates; DR 0.30 (main-hand hits pushed into the off hand's range) keeps the wrong
+-- hand at <= 5%; DR 0.15 is reported. Slow: run by `make check` (split it out if it passes 20 s).
+local metrics = require("Virtual.harness.metrics")
+
+describe("the level and armour sweep #slow", function()
+    for _, level in ipairs({ 10, 20, 30, 40, 50, 60 }) do
+        for _, dr in ipairs({ 0, 0.15, 0.30 }) do
+            it(("level %d, DR %.2f"):format(level, dr), function()
+                local m = metrics.fights({ level = level, dr = dr }, 20)
+                if dr == 0 then
+                    assert.is_true(metrics.rate(m, 1) >= 0.94 and metrics.rate(m, 2) >= 0.94, metrics.line(m))
+                    assert.is_true(m.wrong[1] + m.wrong[2] <= 0.02 * (m.own[1] + m.own[2]), metrics.line(m))
+                    assert.is_true(m.over == 0, metrics.line(m))
+                elseif dr == 0.30 then
+                    assert.is_true(m.wrong[1] + m.wrong[2] <= 0.05 * (m.own[1] + m.own[2]), metrics.line(m))
+                else
+                    print(("\nlevel %d DR 0.15: %s"):format(level, metrics.line(m)))
+                end
+            end)
+        end
+    end
+end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `505 successes / 23 failures / 2 errors / 0 pending`.
- Today's window-and-order pairing against the new expectations: `pairing_replay_spec` (9 failures, 2 errors): the log 2 floors (34/36 and 31/33; today's pairing misses them), G's frame (the glancing 4 takes the swing), another player's strike frame, school 8, the provisional avoid taken and kept (today's avoid is final at once), an avoid at neither lag, timing before the first read (today the oldest swing), and errors in "credits an above-range wound..." and "moves the main lag's median..." (`L.background`, `L.med` are nil); `cleu_rows_spec` "credits a swing the target's dodge at its lag..." (today's row comes at once, not at the window's close);
- the harness: `fixtures_spec`'s three replays (log 1, log 3, log 5), `solo_spec`'s three gates, `group_spec`'s two party gates (today about 12 false credits per 100 swings), and `sweep_spec`'s six DR 0.30 cells (today's amount-first rule takes a main-hand hit pushed into the off hand's range for the off hand). The DR 0 cells and the raid report pass on today's code.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/Events/Rows.lua b/src/Hekili/Virtual/Events/Rows.lua
index f5a42ffd..a48f5f34 100644
--- a/src/Hekili/Virtual/Events/Rows.lua
+++ b/src/Hekili/Virtual/Events/Rows.lua
@@ -1,15 +1,17 @@
 -- Virtual/Events/Rows.lua
 -- The combat-log rows of our swings and of our abilities on the target (event-facade spec §2.4, §3): PLAYER_SWING
 -- (time and hand, plain) and our UNIT_SPELLCAST_SUCCEEDED of an ability that starts combat or strikes on the next
--- swing are held, and the target's UNIT_COMBAT (the outcome, plain, victim-side) that FOLLOWS one within its window
--- pairs with it: SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED, inferred, at the action's time
--- (back-dated). A wound picks its swing by amount against each hand's weapon damage (the out-of-combat UnitDamage
--- cache); an avoid has no amount and takes our pending cast, else the oldest pending swing of either hand (ambiguous
--- when both hands are pending: accepted). A swing still unpaired when its window closes is emitted as SWING_DAMAGE
--- with amount 0 at its own time; an outcome nothing pairs is dropped (someone else's, a tick, a proc). A wound paired
--- with a swing stages `Swing` c = 1 (landed, at the swing's time) and, when CRITICAL, c = 3 (that hand's crit) for
--- VirtualState's resources (Families/Resources.lua: swing rage and a white crit's extra).
--- Measured: docs/research/2026-10-16-swing-outcome-pairing.md.
+-- swing are held, and the target's UNIT_COMBAT (the outcome, plain, victim-side, from ANY source: G fact 1) that
+-- FOLLOWS one is attributed to it by score (combat harness design §1): our cast claims the outcomes of its frame first;
+-- a white (school 1) outcome is then scored against every pending swing, LR = q(amount class) x f(landing lag) /
+-- lambda(the learned background rate of that class), and credited to the best swing when LR >= THETA, else it is
+-- background (no row). SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED are inferred, at the action's time
+-- (back-dated). A credited wound stages `Swing` c = 1 (landed, at the swing's time) and, when CRITICAL, c = 3 (that
+-- hand's crit) for VirtualState's resources (Families/Resources.lua). An avoid credited to a swing is provisional: a
+-- later wound that scores that swing higher takes it; otherwise the swing's window closes as SWING_MISSED. A swing
+-- still unpaired when its window closes is emitted as SWING_DAMAGE with amount 0 at its own time.
+-- Measured: docs/research/2026-10-16-swing-outcome-pairing.md (P), docs/research/2026-10-16-group-pairing-captures.md
+-- (G, G5).
 -- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
 -- (docs/research/2026-10-14-virtual-combat-log-events.md, C1, C3, C9, D7).
 
@@ -21,30 +23,49 @@ local Obs = VS.Obs
 local Plain = S.Plain
 local L = I.Log
 
--- Per hand (1 main, 2 off), how long a swing waits for its outcome (ms), capped at the hand's swing period. Measured
--- lag after PLAYER_SWING (research doc above): main median 474 ms (435-552 in 31 of 34, the rest up to 1287), off
--- median 953 ms (694-1070 in 22 of 31, up to 1686).
+-- Per hand (1 main, 2 off), the support of a swing's landing lag (ms), capped at the hand's swing period: measured
+-- maximum lags 1287 / 1686 ms plus a margin (P log 2).
 L.PAIR_WINDOW_MS = { 1500, 2000 }
 -- Seconds a cast waits for its outcome, and within which an on-next-swing strike's success and its swing are one
 -- event pair (the same frame, log 1).
 local CAST_WINDOW, STRIKE_WINDOW = 0.2, 0.2
--- Seconds within which a cast's own wound comes (its frame): a yellow strike's damage can fit a weapon range
--- (Overpower, Shred), so a cast this fresh takes a wound before any pending swing.
+-- Seconds within which a cast's own wound comes (its frame): a yellow strike's damage can fit a weapon range, so a
+-- cast this fresh takes a wound before any pending swing. Also the foreign strike frame: a wound this soon after a
+-- WOUND 0 that no cast of ours claimed is someone else's on-next-swing strike (G 177249/177250).
 local SAME_FRAME = 0.05
--- White wounds in a row (with a swing pending) that fit no hand's range before the cache counts as stale (a damage
--- buff, a form whose damage it never read): from then on a wound that fits nothing takes the oldest pending swing.
-local STALE_AFTER = 3
-local misses = 0
+
+-- The score (harness design §1.2-§1.4, decision D1; PROTOTYPE values, the harness's gates hold them): THETA the
+-- credit bar; q per amount class (exact, loose, above) and for an avoid; the lag density's tail weight per hand; the
+-- background prior LAMBDA0 (outcomes per second) worth T0 seconds; TAU the decay of the background counts (s).
+L.THETA = 5
+L.Q = { 0.90, 0.08, 0.02 }
+L.Q_AVOID = 0.22
+L.EPS = { 0.12, 0.10 }
+L.LAMBDA0, L.T0, L.TAU = 0.01, 5, 10
+-- The landing lag per reference (1 main from its swing; 2 off from its own swing; 3 off from the latest main swing at
+-- or before it: G5's two sharp references), seeds (MEASURED: P log 2, G5) learned online from clean credits.
+L.MED0, L.SPR0 = { 0.474, 0.703, 1.686 }, { 0.060, 0.020, 0.020 }
+L.med, L.spr = { 0.474, 0.703, 1.686 }, { 0.060, 0.020, 0.020 }
+-- The background: per class, the outcomes that arrived while nothing of ours was pending (1-3 main exact, loose,
+-- above; 4-6 off; 7 avoid; 8 white with no usable cache), and the quiet time they came in; both decay with combat
+-- time (decision D6: they persist across pulls).
+L.bg, L.quiet = { 0, 0, 0, 0, 0, 0, 0, 0 }, 0
+local lastT, lastW0, lastMain = 0, -1, 0
+L.credited, L.background, L.avoidsBack = { 0, 0, 0 }, 0, 0
 
 local N = 8
 -- Pending own actions: kind 1 swing (hand in `x`), 2 cast (spell ID in `x`); `w` its window (s); `t` 0 is free.
-local actT, actKind, actX, actDst, actW = {}, {}, {}, {}, {}
+-- `ref` an off-hand swing's main reference (the latest main swing at or before it; 0 none); `lr` and `avoid` the LR
+-- and action of an avoid credited to it provisionally ("" none).
+local actT, actKind, actX, actDst, actW, actRef, actLR, actAvoid = {}, {}, {}, {}, {}, {}, {}, {}
 for i = 1, N do
-    actT[i], actKind[i], actX[i], actDst[i], actW[i] = 0, 0, 0, "", 0
+    actT[i], actKind[i], actX[i], actDst[i], actW[i], actRef[i], actLR[i], actAvoid[i] = 0, 0, 0, "", 0, 0, 0, ""
 end
 
 local strikeWait = 0 -- an on-next-swing strike's success still waiting for its main-hand swing
 
+-- The avoids a swing can have (school 1) and the further ones a cast can (MISSES).
+local AVOIDS = { DODGE = true, PARRY = true, MISS = true, BLOCK = true, DEFLECT = true, EVADE = true }
 local MISSES = {
     DODGE = true,
     PARRY = true,
@@ -69,28 +90,54 @@ local function free()
     return oldest -- full: the oldest gives way, unemitted (8 pending within 2 s cannot happen)
 end
 
--- The pending action of `kind` still in its window at `t` (or within `age` s of it) that `score(x, amount, flag)`
--- rates highest (0: not this one; nil: every one rates 1), the oldest among equals.
-local function pick(kind, t, score, amount, flag, age)
-    local best, bestS = nil, 0
+-- Our pending cast still in its window at `t` (or within `age` s of it), the oldest first.
+local function cast(t, age)
+    local best
     for i = 1, N do
         local at = actT[i]
-        if at > 0 and actKind[i] == kind and t - at <= (age or actW[i]) then
-            local sc = score and score(actX[i], amount, flag) or 1
-            if sc > bestS or (sc == bestS and sc > 0 and at < actT[best]) then
-                best, bestS = i, sc
-            end
+        if at > 0 and actKind[i] == 2 and t - at <= (age or actW[i]) and (not best or at < actT[best]) then
+            best = i
         end
     end
     return best
 end
 
--- How well a wound of `amount` fits hand h's weapon damage (UnitDamage: min and max main, then min and max off), on
--- half the amount for a crit: 2 inside [min, max], 1 inside [0.6 x min, 1.1 x max] (from 0 for a glancing or partly
--- blocked hit), else 0. The exact range decides between hands whose loose ranges overlap (log 2's crit 52: 26 is the
--- off hand's, though inside the main hand's loose range). The ranges are before armour: a heavily armoured target can
--- push a main-hand hit into the off hand's exact range (per-hand values swap; the count of steps holds).
-local function fits(h, amount, flag)
+local function pending()
+    for i = 1, N do
+        if actT[i] > 0 then
+            return true
+        end
+    end
+    return false
+end
+
+-- The clock of the background: in combat, the counts and the quiet time decay by exp(-dt / TAU), and the quiet time
+-- grows while nothing of ours is pending. Allocates nothing.
+local function advance(t)
+    if t <= lastT then
+        return
+    end
+    if I.inCombat then
+        local dt = t - lastT
+        local k = math.exp(-dt / L.TAU)
+        local bg = L.bg
+        for c = 1, 8 do
+            bg[c] = bg[c] * k
+        end
+        L.quiet = L.quiet * k + (pending() and 0 or dt)
+    end
+    lastT = t
+end
+
+local function lambda(c)
+    return (L.bg[c] + L.LAMBDA0 * L.T0) / (L.quiet + L.T0) -- nonzero: T0 > 0
+end
+
+-- The amount class of a wound for hand h against the weapon damage (UnitDamage: min and max main, then min and max
+-- off), on half the amount for a crit: 1 exact [min, max], 2 loose [0.6 x min, 1.1 x max], 3 above (1.1 x max,
+-- 2 x max] (a damage buff since the read), else 0. A glancing or partly blocked hit opens the loose band down to 0
+-- (G's glancing 1-5 are another player's; log 2's BLOCK_REDUCED 48 is exact). The ranges are before armour.
+local function classOf(h, amount, flag)
     local minMain, maxMain, minOff, maxOff = VS.Stat("UnitDamage")
     local lo, hi = minMain, maxMain
     if h == 2 then
@@ -98,13 +145,54 @@ local function fits(h, amount, flag)
     end
     if flag == "CRITICAL" then
         amount = amount / 2
-    elseif flag == "GLANCING" or flag == "BLOCK_REDUCED" then
-        lo = 0
     end
-    if hi <= 0 or amount < 0.6 * lo or amount > 1.1 * hi then
+    local looseLo = 0.6 * lo
+    if flag == "GLANCING" or flag == "BLOCK_REDUCED" then
+        looseLo = 0
+    end
+    if hi <= 0 or amount < looseLo or amount > 2 * hi then
         return 0
+    elseif amount >= lo and amount <= hi then
+        return 1
     end
-    return (amount >= lo and amount <= hi) and 2 or 1
+    return amount <= 1.1 * hi and 2 or 3
+end
+
+local function normal(d, m, s)
+    local z = (d - m) / s -- nonzero: spr clamped at 0.02 s
+    return math.exp(-0.5 * z * z) / (s * 2.5066283)
+end
+
+-- The landing-lag density of pending swing i for an outcome at t (0 outside its window), and the reference that
+-- scored: the main hand from its swing; the off hand the better of its own swing and its main reference, plus the
+-- hand's tail over the window.
+local function density(i, t)
+    local d, w = t - actT[i], actW[i]
+    if d < 0 or d > w then
+        return 0, 0
+    end
+    local med, spr = L.med, L.spr
+    if actX[i] == 1 then
+        return (1 - L.EPS[1]) * normal(d, med[1], spr[1]) + L.EPS[1] / w, 1 -- nonzero: w > 0 (a window)
+    end
+    local f, ref = normal(d, med[2], spr[2]), 2
+    if actRef[i] > 0 then
+        local m = normal(t - actRef[i], med[3], spr[3])
+        if m > f then
+            f, ref = m, 3
+        end
+    end
+    return (1 - L.EPS[2]) * f + L.EPS[2] / w, ref -- nonzero: w > 0 (a window)
+end
+
+-- A clean credit moves its reference's median and spread (a running median; mean absolute deviation to SD).
+local function learn(ref, d)
+    local med, spr = L.med, L.spr
+    med[ref] = med[ref] + 0.005 * (d > med[ref] and 1 or -1)
+    local s = spr[ref] + 0.05 * (1.2533 * math.abs(d - med[ref]) - spr[ref])
+    spr[ref] = s < 0.02 and 0.02 or (s > 0.4 and 0.4 or s)
+    local w = L.PAIR_WINDOW_MS[ref == 1 and 1 or 2] / 1000
+    med[ref] = med[ref] < 0 and 0 or (med[ref] > w and w or med[ref])
 end
 
 -- One row from an own action and its outcome, at the earlier time. None without a destination: Hekili's handler would
@@ -134,15 +222,22 @@ local function emit(kind, x, dst, action, flag, amount, t)
     end
 end
 
+-- Holds an own action in a free slot (the oldest gives way) and returns the slot.
 local function hold(kind, x, dst, w, t)
     local i = free()
     actT[i], actKind[i], actX[i], actDst[i], actW[i] = t, kind, x, dst, w
+    actRef[i], actLR[i], actAvoid[i] = kind == 1 and x == 2 and lastMain or 0, 0, ""
+    return i
 end
 
 S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
     if type(swingType) ~= "number" or swingType > 1 then
         return
     end
+    advance(t)
+    if swingType == 0 then
+        lastMain = t
+    end
     if swingType == 0 and strikeWait > 0 and t - strikeWait <= STRIKE_WINDOW then
         strikeWait = 0 -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
         return
@@ -161,6 +256,7 @@ S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spel
     if not obj or not (obj.startsCombat or obj.onNextSwing) then
         return
     end
+    advance(t)
     if obj.onNextSwing then -- the strike replaces its swing, in the same frame before or after this success
         local found = false
         for i = 1, N do
@@ -175,78 +271,150 @@ S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spel
     hold(2, spellID, Plain(api, api.UnitGUID("target")) or "", CAST_WINDOW, t)
 end)
 
--- The target's outcome at `t` pairs with the action it follows. A wound: our cast of this frame, else the pending
--- swing whose hand's damage it fits best, the older on a tie (the oldest of any hand when the cache cannot tell: no
--- UnitDamage read yet, read in another form, or stale), else our pending cast; a WOUND 0 is the white swing an
--- on-next-swing strike replaced (its frame also carries the strike's own wound) and pairs with nothing. An avoid: our
--- pending cast (its outcome comes in the same frame), else the oldest pending swing of either hand.
--- shortcut: a startsCombat cast with no outcome of its own (Rend, Sunder) takes a white avoid inside its 0.2 s as
+-- The best pending swing for an outcome at t (amount class per hand from `classOf`, or q = 1 for every hand when
+-- `unknown`; an avoid when `avoid`): its slot, LR, reference and lag, and the runner-up's LR. Allocates nothing.
+local function score(t, amount, flag, avoid, unknown)
+    local best, bestLR, ref, lag, second = nil, 0, 0, 0, 0
+    for i = 1, N do
+        if actT[i] > 0 and actKind[i] == 1 and not (avoid and actAvoid[i] ~= "") then
+            local f, r = density(i, t)
+            local q, c = L.Q_AVOID, 7
+            if not avoid then
+                local cls = 0
+                if unknown then
+                    q, c = 1, 8
+                else
+                    cls = classOf(actX[i], amount, flag)
+                    q, c = cls > 0 and L.Q[cls] or 0, (actX[i] - 1) * 3 + cls
+                end
+            end
+            local lr = f > 0 and q > 0 and q * f / lambda(c) or 0
+            if lr > actLR[i] or actAvoid[i] == "" then -- a wound takes a provisionally avoided swing only by beating it
+                if lr > bestLR then
+                    best, bestLR, ref, lag, second = i, lr, r, t - actT[i], bestLR
+                elseif lr > second then
+                    second = lr
+                end
+            end
+        end
+    end
+    return best, bestLR, ref, lag, second
+end
+
+-- An outcome nobody of ours claimed: counted, and while in combat with nothing of ours pending (the quiet time it is a
+-- rate over), it teaches the background rate of each class it qualifies for (a white wound in every hand's class it
+-- fits).
+local function background(amount, flag, avoid, unknown)
+    L.background = L.background + 1
+    if pending() or not I.inCombat then
+        return
+    end
+    local bg = L.bg
+    if avoid then
+        bg[7] = bg[7] + 1
+    elseif unknown then
+        bg[8] = bg[8] + 1
+    else
+        for h = 1, 2 do
+            local cls = classOf(h, amount, flag)
+            if cls > 0 then
+                bg[(h - 1) * 3 + cls] = bg[(h - 1) * 3 + cls] + 1
+            end
+        end
+    end
+end
+
+-- The target's outcome at `t`. Our pending cast claims first: an avoid within its window, a wound within its frame.
+-- A WOUND 0 is the white swing an on-next-swing strike replaced and pairs with nothing; a wound right after one that
+-- no cast of ours claimed is another player's strike frame (background). A white outcome (school 1) is then scored
+-- against our pending swings; a wound no swing takes goes to our pending cast, else to the background.
+-- shortcut: a startsCombat cast with no outcome of its own (a DoT, a debuff) takes an avoid inside its 0.2 s as
 -- SPELL_MISSED; rare, upgrade to the cast's frame if Phase D's compensating aura removal relies on it.
--- shortcut: in group play another attacker's outcome inside a window can be credited to our action (and its wound's
--- rage lift rage's lo above the real rage until the next pin); upgrade when a per-attacker attribution exists.
-S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount)
+S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
     if unit ~= "target" or type(act) ~= "string" or (act ~= "WOUND" and not MISSES[act]) then
         return
     end
+    advance(t)
     amount = type(amount) == "number" and amount or 0
     flag = type(flag) == "string" and flag or ""
-    local p
-    if act ~= "WOUND" then
-        p = pick(2, t) or pick(1, t)
-    elseif amount > 0 then
-        p = pick(2, t, nil, nil, nil, SAME_FRAME)
-        if not p then
-            local _, maxMain = VS.Stat("UnitDamage")
-            local form = Plain(api, api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade.lua's stance row)
-            if maxMain <= 0 or form ~= I.damageForm then
-                p = pick(1, t)
-            else
-                p = pick(1, t, fits, amount, flag)
-                if p then
-                    misses = 0
-                elseif pick(1, t) then
-                    misses = misses + 1
-                    if misses >= STALE_AFTER then
-                        p = pick(1, t)
-                    end
-                end
-            end
-            p = p or pick(2, t)
-        end
-    end
-    if not p then
+    local white, avoid = school == 1, act ~= "WOUND"
+    if act == "WOUND" and amount <= 0 then
+        lastW0 = t
         return
     end
-    local kind, x, at = actKind[p], actX[p], actT[p]
-    actT[p] = 0
-    emit(kind, x, actDst[p], act, flag, amount, at)
-    if kind == 1 and act == "WOUND" then
-        S.Stage(Obs.Swing, at, x, 0, 1) -- landed, at the swing's time: the resources family pays its rage
-        if flag == "CRITICAL" then
-            S.Stage(Obs.Swing, t, x, 0, 3)
+    local p = cast(t, not avoid and SAME_FRAME or nil)
+    local credited, lr, ref, lag, second = nil, 0, 0, 0, 0
+    local unknown = false
+    if not p and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
+        if not avoid then
+            local _, maxMain = VS.Stat("UnitDamage")
+            local form = Plain(api, api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade.lua's stance row)
+            unknown = maxMain <= 0 or form ~= I.damageForm
+        end
+        credited, lr, ref, lag, second = score(t, amount, flag, avoid, unknown)
+        if credited and lr < L.THETA then
+            credited = nil
         end
-        S.Urgent("VS_SWING_LANDED")
     end
+    if not p and not credited and not avoid then
+        p = cast(t)
+    end
+    if p then
+        local x, at = actX[p], actT[p]
+        actT[p] = 0
+        L.credited[3] = L.credited[3] + 1
+        emit(2, x, actDst[p], act, flag, amount, at)
+        return
+    elseif not credited then
+        background(amount, flag, avoid, unknown)
+        return
+    end
+    local x, at = actX[credited], actT[credited]
+    if avoid then
+        actLR[credited], actAvoid[credited] = lr, act -- provisional: emitted when the window closes
+        return
+    end
+    if actAvoid[credited] ~= "" then
+        L.avoidsBack = L.avoidsBack + 1 -- the avoid it held was someone else's after all
+    end
+    actT[credited], actAvoid[credited], actLR[credited] = 0, "", 0
+    L.credited[x] = L.credited[x] + 1
+    if not unknown and classOf(x, amount, flag) == 1 and second < L.THETA then
+        local d = ref == 3 and t - actRef[credited] or lag
+        if math.abs(d - L.med[ref]) < 3 * L.spr[ref] then
+            learn(ref, d)
+        end
+    end
+    emit(1, x, actDst[credited], act, flag, amount, at)
+    S.Stage(Obs.Swing, at, x, 0, 1) -- landed, at the swing's time: the resources family pays its rage
+    if flag == "CRITICAL" then
+        S.Stage(Obs.Swing, t, x, 0, 3)
+    end
+    S.Urgent("VS_SWING_LANDED")
 end)
 
--- Closes the windows at `now`: an unpaired swing becomes SWING_DAMAGE with amount 0 at its own time (and stages
--- nothing: no rage); an unpaired cast is dropped. Every OnUpdate (the deferred lane, CombatLog.lua). Allocates nothing.
+-- Closes the windows at `now`: a swing holding a provisional avoid becomes SWING_MISSED, an unpaired one SWING_DAMAGE
+-- with amount 0, each at its own time (and stages nothing: no rage); an unpaired cast is dropped. Every OnUpdate (the
+-- deferred lane, CombatLog.lua). Allocates nothing.
 L.OnTick(function(now)
+    advance(now)
     for i = 1, N do
         local t = actT[i]
         if t > 0 and now - t > actW[i] then
             actT[i] = 0
             if actKind[i] == 1 then
-                emit(1, actX[i], actDst[i], "WOUND", "", 0, t)
+                emit(1, actX[i], actDst[i], actAvoid[i] ~= "" and actAvoid[i] or "WOUND", "", 0, t)
             end
+            actAvoid[i], actLR[i] = "", 0
         end
     end
 end)
 
--- Combat end: nothing pending survives into the next pull.
-S.On("PLAYER_REGEN_ENABLED", nil, function()
+-- Combat end: nothing pending survives into the next pull; the background and the lags are kept (decision D6).
+S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
+    advance(t)
     for i = 1, N do
-        actT[i] = 0
+        actT[i], actAvoid[i], actLR[i] = 0, "", 0
     end
-    strikeWait, misses = 0, 0
+    strikeWait = 0
 end)
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `530 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 123 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      530 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual tests/Virtual tools docs/dev | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|undead|maul|heroic|overpower|shred|bloodrage|charge|grave|bear'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/Events/Rows.lua tests/Virtual/Events/cleu_rows_spec.lua \
  tests/Virtual/Events/pairing_replay_spec.lua tests/Virtual/State/alloc_spec.lua \
  tests/Virtual/harness/fixtures_spec.lua tests/Virtual/harness/group_spec.lua tests/Virtual/harness/metrics.lua \
  tests/Virtual/harness/solo_spec.lua tests/Virtual/harness/sweep_spec.lua
git commit -m "feat(vs): score white outcomes on the target against our pending swings: amount class, the landing lag's density per hand (the off hand's two references), the learned background; provisional avoids, the foreign strike frame, school 1 only (combat harness design §1)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin combat-harness`

---
### Task 3: The usability oracle: verdicts, retraction and rescue

Spec §2.1-§2.6 (as amended by Deviations 5-10); §3.4's oracle rows; §6 §2's cases.

**Files:**
- Modify: `src/Hekili/Virtual/State/Families/Resources.lua`, `src/Hekili/Virtual/Events/Rows.lua`
- Test: `tests/Virtual/State/resources_spec.lua` (new describe "the usability oracle (harness design §2: ...)", 7 cases: "confirms a firm credit across a cost when the answer flips usable, and lowers its class's bar", "retracts a firm credit answered short: est, lo and hi back, the swing pending again", "closes a retracted swing past its window as SWING_MISSED (two rows for that swing, decision D9)", "labels a soft credit (only its estimate crossed) at half weight and retracts nothing", "gives no verdict when one of our casts spent from the slot between the outcome and the answer", "rescues a dropped wound for a flip nothing explains: its swing paid, its row out; without one, today's pin", "caps a class's bar at THETA_MAX after ten negatives and floors it at THETA_MIN after positives"), `tests/Virtual/harness/solo_spec.lua` (the solo oracle gate), `tests/Virtual/harness/group_spec.lua` (the party oracle gate, both runs reported), `tests/Virtual/harness/alloc_spec.lua` (the oracle fight: a retraction and a rescue among its paths)

**Interfaces:**
- Consumes: `Swing` c = 1's `b` (the record id), `Obs.Usable` answers, `I.CostOf`, `I.ab.slot`/`multiCost`, `I.SwingValue`/`I.SwingCrit`, `I.res.scale`.
- Produces:
  - Rows: `I.CreditVerdict(id, ok, t, firm)` -> nil (before ORACLE_MIN) / false (past ORACLE_MAX, closed, or `ok` nil) / true (judged); `I.Rescue(r, need, since, t)` -> hand, crit, swing time (or nil); `L.ORACLE_MIN, L.ORACLE_MAX = 0.1, 0.6`, `L.THETA_MIN, L.THETA_MAX = 2, 16`, `L.theta[1..16]` (k = (hand - 1) x 8 + (class - 1) x 2 + band), `L.oracle = { judged, confirmed, retracted, soft, rescued, rescuedLate }`; a credit stages `Swing` c = 1 with `b` = its record id (1-8);
  - Resources: per record its slot, hand, the deltas to est/lo/hi, the hit-rate step, the judged ability (the cheapest spender of the slot the step crosses), firm; `R.spends[r]` (our spends, counted in `I.ResourceShift`); the verdict before the ladder; the rescue's step paid and pinned exactly.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/resources_spec.lua b/tests/Virtual/State/resources_spec.lua
index 4f86bd27..850539b1 100644
--- a/tests/Virtual/State/resources_spec.lua
+++ b/tests/Virtual/State/resources_spec.lua
@@ -1087,3 +1087,148 @@ describe("resources", function()
         end)
     end)
 end)
+
+describe("the usability oracle (harness design §2: Rows' credits judged by the next usability answer)", function()
+    local api, ctl, ns, VS, I, L, R, saved, rows
+    local SHOUT, STRIKE = fs.SHOUT, fs.STRIKE -- the fake spec's spenders at 10 and 15
+    local USABLE, SHORT = { true, false }, { false, true }
+
+    before_each(function()
+        api, ctl = fake.new()
+        saved = {}
+        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
+            saved[k] = rawget(_G, k) or false
+            _G[k] = v
+        end
+        ns = load.module()
+        VS, I = ns.VirtualState, ns.VirtualStateInternal
+        L, R = I.Log, I.res
+        I.Build(fs.def(fs.new(9)), 1)
+        ctl.damage[1], ctl.damage[2], ctl.damage[3], ctl.damage[4] = 36, 50, 24, 32
+        ctl.now = 2
+        VS.Start(api)
+        rows = {}
+        local GetInfo = ns.Facade.CombatLogGetCurrentEventInfo
+        local sink = I.Events.CreateFrame("Frame")
+        sink:SetScript("OnEvent", function()
+            local t, ev, _, _, _, _, _, _, _, _, _, a12 = GetInfo()
+            if ev == "SWING_DAMAGE" or ev == "SWING_MISSED" then
+                rows[#rows + 1] = { ev, a12, t }
+            end
+        end)
+        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+    end)
+
+    after_each(function()
+        for k, v in pairs(saved) do
+            _G[k] = v or nil
+        end
+    end)
+
+    -- The client event at t, then a drain, then the rows it queued.
+    local function at(t, event, ...)
+        ctl.Tick(t)
+        ctl.Fire(event, ...)
+        ctl.Tick(t)
+        fs.fold(ns, t)
+        ctl.Tick(t)
+    end
+    local function answer(t, spell, ok)
+        ctl.usable[spell] = ok and USABLE or SHORT
+        at(t, "SPELL_UPDATE_USABLE")
+    end
+    -- In combat from 9.9 s at `est` (lo `lo`, hi `hi`); no spender has answered yet (no rung).
+    local function setup(est, lo, hi)
+        at(9.9, "PLAYER_REGEN_DISABLED")
+        R.est0[1], R.lo0[1], R.hi0[1] = est, lo or est, hi or est
+    end
+    local function credit(t, amount, lag)
+        at(t, "PLAYER_SWING", 2.2, 0)
+        at(t + (lag or 0.47), "UNIT_COMBAT", "target", "WOUND", "", amount or 45, 1)
+    end
+    local function power(t)
+        local p = VS.Power(fs.RAGE, t)
+        return { p.lo, p.est, p.hi }
+    end
+
+    it("confirms a firm credit across a cost when the answer flips usable, and lowers its class's bar", function()
+        setup(8)
+        credit(10)
+        assert.are.same({ 8 + 9 * 0.9, 17, 8 + 9 * 1.1 }, power(10.5))
+        answer(10.52, SHOUT, true) -- before ORACLE_MIN after the outcome: no verdict yet
+        assert.are.equal(0, L.oracle.judged)
+        answer(10.6, SHOUT, true)
+        assert.are.same({ 1, 1 }, { L.oracle.judged, L.oracle.confirmed })
+        assert.are.equal(L.THETA / 1.1, L.theta[1]) -- main, exact, core band
+    end)
+
+    it("retracts a firm credit answered short: est, lo and hi back, the swing pending again", function()
+        setup(8)
+        credit(10)
+        answer(10.6, SHOUT, false)
+        assert.are.same({ 1, 1 }, { L.oracle.judged, L.oracle.retracted })
+        assert.are.same({ 8, 8, 8 }, power(10.6)) -- lo never above its pre-credit value
+        assert.are.equal(L.THETA * 1.5, L.theta[1])
+        at(10.9, "UNIT_COMBAT", "target", "WOUND", "", 44, 1) -- in the tail: the re-held swing takes it
+        assert.are.same({ { "SWING_DAMAGE", 45, 10 }, { "SWING_DAMAGE", 44, 10 } }, rows)
+    end)
+
+    it("closes a retracted swing past its window as SWING_MISSED (two rows for that swing, decision D9)", function()
+        setup(8)
+        credit(10, 45, 1.2)
+        answer(11.6, SHOUT, false) -- 0.4 s after the outcome, 1.6 s after the swing
+        assert.are.same({ { "SWING_DAMAGE", 45, 10 }, { "SWING_MISSED", "MISS", 10 } }, rows)
+    end)
+
+    it("labels a soft credit (only its estimate crossed) at half weight and retracts nothing", function()
+        setup(8, 0, 8)
+        credit(10)
+        answer(10.6, SHOUT, false)
+        assert.are.same({ 1, 0 }, { L.oracle.soft, L.oracle.retracted })
+        assert.are.equal(L.THETA * 1.22, L.theta[1])
+        assert.are.equal(8.1, power(10.6)[1]) -- the credit's floor stays; the ladder clamped est and hi under 10
+    end)
+
+    it("gives no verdict when one of our casts spent from the slot between the outcome and the answer", function()
+        setup(8)
+        credit(10)
+        at(10.55, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", SHOUT)
+        answer(10.6, SHOUT, false)
+        assert.are.equal(0, L.oracle.judged)
+    end)
+
+    it(
+        "rescues a dropped wound for a flip nothing explains: its swing paid, its row out; without one, today's pin",
+        function()
+            setup(5)
+            answer(9.95, SHOUT, false)
+            L.theta[2] = 8 -- main, exact, tail: the 45 at 1.3 s (LR 7.2) is dropped
+            credit(10, 45, 1.3)
+            assert.are.same({ 0, 0 }, { #rows, L.oracle.rescued })
+            answer(11.45, SHOUT, true)
+            assert.are.same({ 1, 0 }, { L.oracle.rescued, L.oracle.rescuedLate })
+            assert.are.same({ { "SWING_DAMAGE", 45, 10 } }, rows)
+            assert.are.same({ 14, 14, 14 }, power(11.45)) -- 5 + 9, then the explained flip pins exactly
+            answer(12, SHOUT, false)
+            R.est0[1], R.lo0[1], R.hi0[1] = 5, 5, 5
+            answer(12.5, SHOUT, true) -- nothing dropped: the swing-paid pin [10, 10 + a step)
+            assert.are.same({ 10, 10, 10 + 9 * 1.1 }, power(12.5))
+        end
+    )
+
+    it("caps a class's bar at THETA_MAX after ten negatives and floors it at THETA_MIN after positives", function()
+        setup(8)
+        for k = 0, 9 do
+            credit(10 + 3 * k)
+            answer(10.6 + 3 * k, SHOUT, false)
+        end
+        assert.are.equal(L.THETA_MAX, L.theta[1])
+        for k = 10, 39 do
+            R.est0[1], R.lo0[1], R.hi0[1] = 8, 8, 8
+            credit(10 + 3 * k)
+            answer(10.6 + 3 * k, SHOUT, true)
+            answer(11 + 3 * k, SHOUT, false)
+        end
+        assert.are.equal(L.THETA_MIN, L.theta[1])
+    end)
+end)
diff --git a/tests/Virtual/harness/alloc_spec.lua b/tests/Virtual/harness/alloc_spec.lua
index 283e264a..a80ce96e 100644
--- a/tests/Virtual/harness/alloc_spec.lua
+++ b/tests/Virtual/harness/alloc_spec.lua
@@ -1,5 +1,6 @@
 -- tests/Virtual/harness/alloc_spec.lua (harness design §3.6): one generated party fight (two other sources on our
--- target, a mob on us, our presses) replayed through VirtualState: after a warm-up, the replays allocate nothing.
+-- target, a mob on us, our presses, usability answered from our true power: the oracle's verdicts, a retraction and a
+-- rescue among them) replayed through VirtualState: after a warm-up, the replays allocate nothing.
 local scenarios = require("Virtual.harness.scenarios")
 local drive = require("Virtual.harness.drive")
 local alloc = require("Virtual.State.helpers.alloc")
@@ -14,5 +15,7 @@ describe("the harness drive", function()
         drive.restore(c)
         assert.is_true(ok, tostring(bytes))
         assert.are.equal(0, bytes)
+        local o = c.I.Log.oracle
+        assert.is_true(o.retracted > 0 and o.rescued > 0, "the fight exercises a retraction and a rescue")
     end)
 end)
diff --git a/tests/Virtual/harness/group_spec.lua b/tests/Virtual/harness/group_spec.lua
index ab9fb01c..4879883a 100644
--- a/tests/Virtual/harness/group_spec.lua
+++ b/tests/Virtual/harness/group_spec.lua
@@ -2,6 +2,7 @@
 -- their outcomes arrive on our target's tokens with plain amounts), through the real Rows.lua; the gates of §3.4. The
 -- raid is reported, not gated (D5).
 local metrics = require("Virtual.harness.metrics")
+local scenarios = require("Virtual.harness.scenarios")
 
 local function check(ok, m)
     assert.is_true(ok, metrics.line(m))
@@ -29,4 +30,17 @@ describe("group attribution (harness gates)", function()
         print("\nraid, 12 on target: " .. metrics.line(m))
         assert.is_true(m.fights == 30)
     end)
+
+    it("oracle, party of 5 (in-range melee): catches >= 60% of the false credits it judges (100 fights)", function()
+        local o = scenarios.oracle({ others = { "melee", "caster" } })
+        local m = metrics.fights(o, 100)
+        local off = metrics.fights(setmetatable({ oracle = false }, { __index = o }), 100)
+        print("\noracle: " .. metrics.oracleLine(m) .. "\nno oracle: " .. metrics.oracleLine(off))
+        assert.is_true(m.caught >= 0.60 * m.falseJudged, metrics.oracleLine(m))
+        assert.is_true(m.falseRetracted <= 0.01 * (m.right[1] + m.right[2]), metrics.oracleLine(m))
+        assert.is_true(m.rescuedOurs >= 0.90 * m.rescued, metrics.oracleLine(m))
+        -- the ladder clamps a false credit's floor at the same poll, with or without the oracle: no poll ever reads
+        -- a floor at a cost the true power is below
+        assert.is_true(m.danger == 0 and off.danger == 0, metrics.oracleLine(m))
+    end)
 end)
diff --git a/tests/Virtual/harness/solo_spec.lua b/tests/Virtual/harness/solo_spec.lua
index 33456b99..d7602d08 100644
--- a/tests/Virtual/harness/solo_spec.lua
+++ b/tests/Virtual/harness/solo_spec.lua
@@ -1,6 +1,7 @@
 -- tests/Virtual/harness/solo_spec.lua (harness design §3.4, decisions D4-D5): solo fights of the log-2 profile, a
 -- damage buff in combat and a form change, through the real Rows.lua; the gates of §3.4.
 local metrics = require("Virtual.harness.metrics")
+local scenarios = require("Virtual.harness.scenarios")
 
 local function check(ok, m)
     assert.is_true(ok, metrics.line(m))
@@ -34,4 +35,15 @@ describe("solo attribution (harness gates)", function()
             check(m.falses[1] + m.falses[2] == 0, m)
         end
     )
+
+    it(
+        "oracle: retracts <= 0.5% of our own credits; its rescues are ours (>= 95%, or one miss) (200 fights)",
+        function()
+            local m = metrics.fights(scenarios.oracle({}), 200)
+            assert.is_true(m.falseRetracted <= 0.005 * (m.right[1] + m.right[2]), metrics.oracleLine(m))
+            -- solo leaves the oracle little to rescue (2 in 200 fights): one wrong rescue is within the gate
+            assert.is_true(m.rescued - m.rescuedOurs <= math.max(1, 0.05 * m.rescued), metrics.oracleLine(m))
+            assert.is_true(m.judged > 0 and m.danger == 0, metrics.oracleLine(m))
+        end
+    )
 end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `530 successes / 2 failures / 7 errors / 0 pending`.
- `resources_spec` "the usability oracle": six error (`L.oracle`/`L.theta` are nil: Rows has no oracle yet) and "closes a retracted swing past its window as SWING_MISSED" fails (nothing retracts);
- `solo_spec` "oracle: ..." fails (`judged` 0: nothing is judged) and the harness `alloc_spec` errors on `c.I.Log.oracle` (nil).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/Events/Rows.lua b/src/Hekili/Virtual/Events/Rows.lua
index a48f5f34..9f7afcad 100644
--- a/src/Hekili/Virtual/Events/Rows.lua
+++ b/src/Hekili/Virtual/Events/Rows.lua
@@ -53,6 +53,36 @@ L.bg, L.quiet = { 0, 0, 0, 0, 0, 0, 0, 0 }, 0
 local lastT, lastW0, lastMain = 0, -1, 0
 L.credited, L.background, L.avoidsBack = { 0, 0, 0 }, 0, 0
 
+-- The usability oracle (harness design §2, decision D8): a credit's record is judged by the first usability answer
+-- ORACLE_MIN to ORACLE_MAX s after its outcome (UNMEASURED until G7); labels move the credit bar of the record's class,
+-- theta[k] for k = hand x amount class (exact, loose, above, unknown) x lag band (core: within 2 spr; tail), between
+-- THETA_MIN and THETA_MAX (start THETA; kept across pulls, reset at load).
+L.ORACLE_MIN, L.ORACLE_MAX = 0.1, 0.6
+L.THETA_MIN, L.THETA_MAX = 2, 16
+L.theta = {}
+for k = 1, 16 do
+    L.theta[k] = L.THETA
+end
+L.oracle = { judged = 0, confirmed = 0, retracted = 0, soft = 0, rescued = 0, rescuedLate = 0 }
+-- Credit records (ids 1-8, a ring; `Swing` c = 1's b): the outcome's time, amount and flag, the swing's time, hand,
+-- destination, window and main reference, the class index, LR, and whether a verdict is still open.
+local RECORDS = 8
+local recT, recAmount, recFlag, recAt, recHand, recDst, recW, recRef, recK, recLR, recOpen =
+    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
+for k = 1, RECORDS do
+    recT[k], recAmount[k], recFlag[k], recAt[k], recHand[k], recDst[k], recW[k], recRef[k] = 0, 0, "", 0, 0, "", 0, 0
+    recK[k], recLR[k], recOpen[k] = 1, 0, false
+end
+local recNext = 0
+-- The wounds dropped as background (DROP, a ring), each for one off-hand window: time, amount, flag, its best
+-- candidate swing's hand and time, the class index, LR, and whether that swing was claimed since (credited, rescued).
+local DROP = 8
+local dT, dAmount, dFlag, dHand, dAt, dK, dLR, dUsed = {}, {}, {}, {}, {}, {}, {}, {}
+for i = 1, DROP do
+    dT[i], dAmount[i], dFlag[i], dHand[i], dAt[i], dK[i], dLR[i], dUsed[i] = 0, 0, "", 0, 0, 1, 0, true
+end
+local dNext = 0
+
 local N = 8
 -- Pending own actions: kind 1 swing (hand in `x`), 2 cast (spell ID in `x`); `w` its window (s); `t` 0 is free.
 -- `ref` an off-hand swing's main reference (the latest main swing at or before it; 0 none); `lr` and `avoid` the LR
@@ -271,16 +301,23 @@ S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spel
     hold(2, spellID, Plain(api, api.UnitGUID("target")) or "", CAST_WINDOW, t)
 end)
 
+-- The theta index of hand h's amount class `cls` (1-3, 4 unknown) at lag d from reference `ref`: core band (within 2
+-- spr of the median) or tail.
+local function thetaIndex(h, cls, ref, d)
+    local band = math.abs(d - L.med[ref]) <= 2 * L.spr[ref] and 1 or 2
+    return (h - 1) * 8 + (cls - 1) * 2 + band
+end
+
 -- The best pending swing for an outcome at t (amount class per hand from `classOf`, or q = 1 for every hand when
--- `unknown`; an avoid when `avoid`): its slot, LR, reference and lag, and the runner-up's LR. Allocates nothing.
+-- `unknown`; an avoid when `avoid`): its slot, LR, reference, lag, the runner-up's LR and its theta index (wounds).
+-- Allocates nothing.
 local function score(t, amount, flag, avoid, unknown)
-    local best, bestLR, ref, lag, second = nil, 0, 0, 0, 0
+    local best, bestLR, ref, lag, second, idx = nil, 0, 0, 0, 0, 1
     for i = 1, N do
         if actT[i] > 0 and actKind[i] == 1 and not (avoid and actAvoid[i] ~= "") then
             local f, r = density(i, t)
-            local q, c = L.Q_AVOID, 7
+            local q, c, cls = L.Q_AVOID, 7, 4
             if not avoid then
-                local cls = 0
                 if unknown then
                     q, c = 1, 8
                 else
@@ -291,14 +328,32 @@ local function score(t, amount, flag, avoid, unknown)
             local lr = f > 0 and q > 0 and q * f / lambda(c) or 0
             if lr > actLR[i] or actAvoid[i] == "" then -- a wound takes a provisionally avoided swing only by beating it
                 if lr > bestLR then
+                    local d = r == 3 and t - actRef[i] or t - actT[i]
                     best, bestLR, ref, lag, second = i, lr, r, t - actT[i], bestLR
+                    idx = thetaIndex(actX[i], cls, r, d)
                 elseif lr > second then
                     second = lr
                 end
             end
         end
     end
-    return best, bestLR, ref, lag, second
+    return best, bestLR, ref, lag, second, idx
+end
+
+-- A wound nobody took into the dropped ring, with its best candidate swing (none: not kept).
+local function drop(t, amount, flag, hand, at, k, lr)
+    dNext = dNext % DROP + 1
+    dT[dNext], dAmount[dNext], dFlag[dNext], dHand[dNext], dAt[dNext] = t, amount, flag, hand, at
+    dK[dNext], dLR[dNext], dUsed[dNext] = k, lr, false
+end
+
+-- The swing of `hand` at `at` was claimed: its dropped wounds are no rescue's.
+local function claimed(hand, at)
+    for i = 1, DROP do
+        if dHand[i] == hand and dAt[i] == at then
+            dUsed[i] = true
+        end
+    end
 end
 
 -- An outcome nobody of ours claimed: counted, and while in combat with nothing of ours pending (the quiet time it is a
@@ -343,7 +398,7 @@ S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
         return
     end
     local p = cast(t, not avoid and SAME_FRAME or nil)
-    local credited, lr, ref, lag, second = nil, 0, 0, 0, 0
+    local credited, lr, ref, lag, second, k, short = nil, 0, 0, 0, 0, 1, nil
     local unknown = false
     if not p and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
         if not avoid then
@@ -351,9 +406,9 @@ S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
             local form = Plain(api, api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade.lua's stance row)
             unknown = maxMain <= 0 or form ~= I.damageForm
         end
-        credited, lr, ref, lag, second = score(t, amount, flag, avoid, unknown)
-        if credited and lr < L.THETA then
-            credited = nil
+        credited, lr, ref, lag, second, k = score(t, amount, flag, avoid, unknown)
+        if credited and lr < (avoid and L.THETA or L.theta[k]) then
+            short, credited = not avoid and credited or nil, nil
         end
     end
     if not p and not credited and not avoid then
@@ -366,6 +421,9 @@ S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
         emit(2, x, actDst[p], act, flag, amount, at)
         return
     elseif not credited then
+        if short then -- a wound that fell short of its best swing's bar: kept for a rescue
+            drop(t, amount, flag, actX[short], actT[short], k, lr)
+        end
         background(amount, flag, avoid, unknown)
         return
     end
@@ -377,7 +435,13 @@ S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
     if actAvoid[credited] ~= "" then
         L.avoidsBack = L.avoidsBack + 1 -- the avoid it held was someone else's after all
     end
+    recNext = recNext % RECORDS + 1
+    local id = recNext
+    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = t, amount, flag, at, x
+    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] =
+        actDst[credited], actW[credited], actRef[credited], k, lr, true
     actT[credited], actAvoid[credited], actLR[credited] = 0, "", 0
+    claimed(x, at)
     L.credited[x] = L.credited[x] + 1
     if not unknown and classOf(x, amount, flag) == 1 and second < L.THETA then
         local d = ref == 3 and t - actRef[credited] or lag
@@ -386,13 +450,97 @@ S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
         end
     end
     emit(1, x, actDst[credited], act, flag, amount, at)
-    S.Stage(Obs.Swing, at, x, 0, 1) -- landed, at the swing's time: the resources family pays its rage
+    S.Stage(Obs.Swing, at, x, id, 1) -- landed, at the swing's time: the resources family pays its rage (record id)
     if flag == "CRITICAL" then
         S.Stage(Obs.Swing, t, x, 0, 3)
     end
     S.Urgent("VS_SWING_LANDED")
 end)
 
+--- (harness design §2.2) The verdict on credit record `id` from a usability answer at t (`ok`: usable, false: short,
+--- nil: not usable for another reason; `firm`: the credit's floor reached the cost), asked by Families/Resources.lua:
+--- nil before ORACLE_MIN after the outcome (no verdict yet), false once ORACLE_MAX has passed, on a nil `ok` or when the
+--- record is closed, true when judged. Usable confirms it (theta of its class / 1.1). Short and firm retracts it
+--- (theta x 1.5): its swing is pending again inside its window, else closed as SWING_MISSED (the SWING_DAMAGE row
+--- already went out: two rows for that swing, decision D9), and its wound joins the dropped ring as background. Short
+--- and soft labels it at half weight (x 1.22). Allocates nothing.
+function I.CreditVerdict(id, ok, t, firm)
+    if not recOpen[id] then
+        return false
+    end
+    local d = t - recT[id]
+    if d < L.ORACLE_MIN then
+        return nil
+    end
+    recOpen[id] = false
+    if d > L.ORACLE_MAX or ok == nil then
+        return false -- past its window, or a NOT answer (no rung): no verdict
+    end
+    local o, th, k = L.oracle, L.theta, recK[id]
+    o.judged = o.judged + 1
+    if ok then
+        o.confirmed = o.confirmed + 1
+        th[k] = th[k] / 1.1 > L.THETA_MIN and th[k] / 1.1 or L.THETA_MIN
+    elseif firm then
+        o.retracted = o.retracted + 1
+        th[k] = th[k] * 1.5 < L.THETA_MAX and th[k] * 1.5 or L.THETA_MAX
+        local hand, at = recHand[id], recAt[id]
+        if t - at <= recW[id] then
+            actRef[hold(1, hand, recDst[id], recW[id], at)] = recRef[id]
+        else
+            emit(1, hand, recDst[id], "MISS", "", 0, at)
+        end
+        L.background = L.background + 1
+        drop(recT[id], recAmount[id], recFlag[id], hand, at, k, recLR[id])
+    else
+        o.soft = o.soft + 1
+        th[k] = th[k] * 1.22 < L.THETA_MAX and th[k] * 1.22 or L.THETA_MAX
+    end
+    return true
+end
+
+--- (harness design §2.3) A flip of slot r to usable that leaves `need` unexplained (Families/Resources.lua): the dropped
+--- wound that arrived ORACLE_MIN to ORACLE_MAX before it (the flip trails the wound that caused it, as a verdict does;
+--- and not before `since`, the short report, less that window), whose swing nothing claimed and whose step covers
+--- `need`, the best by LR. Its swing's row goes out if it is still pending (else rage only: rescuedLate); a
+--- positive label. Returns its hand, whether it was a crit (Resources pays it) and its swing's time, or nil. Allocates
+--- nothing.
+function I.Rescue(r, need, since, t)
+    local best
+    for i = 1, DROP do
+        local h = dHand[i]
+        local age = t - dT[i]
+        if not dUsed[i] and dT[i] >= since - L.ORACLE_MAX and age >= L.ORACLE_MIN and age <= L.ORACLE_MAX then
+            local step = I.SwingValue(r, h) * I.res.scale[r]
+            if dFlag[i] == "CRITICAL" then
+                step = step + I.SwingCrit(r, h)
+            end
+            if step >= need - I.EPS and (not best or dLR[i] > dLR[best]) then
+                best = i
+            end
+        end
+    end
+    if not best then
+        return nil
+    end
+    local h, at, o = dHand[best], dAt[best], L.oracle
+    claimed(h, at)
+    o.rescued = o.rescued + 1
+    local late = true
+    for i = 1, N do
+        if actT[i] == at and actKind[i] == 1 and actX[i] == h then
+            actT[i], actAvoid[i], actLR[i], late = 0, "", 0, false
+            emit(1, h, actDst[i], "WOUND", dFlag[best], dAmount[best], at)
+        end
+    end
+    if late then
+        o.rescuedLate = o.rescuedLate + 1
+    end
+    local k = dK[best]
+    L.theta[k] = L.theta[k] / 1.1 > L.THETA_MIN and L.theta[k] / 1.1 or L.THETA_MIN
+    return h, dFlag[best] == "CRITICAL", at
+end
+
 -- Closes the windows at `now`: a swing holding a provisional avoid becomes SWING_MISSED, an unpaired one SWING_DAMAGE
 -- with amount 0, each at its own time (and stages nothing: no rage); an unpaired cast is dropped. Every OnUpdate (the
 -- deferred lane, CombatLog.lua). Allocates nothing.
diff --git a/src/Hekili/Virtual/State/Families/Resources.lua b/src/Hekili/Virtual/State/Families/Resources.lua
index 91c9f079..db66f56c 100644
--- a/src/Hekili/Virtual/State/Families/Resources.lua
+++ b/src/Hekili/Virtual/State/Families/Resources.lua
@@ -69,6 +69,7 @@ local R = {
     taken = {},
     takenBin = {},
     takenSec = {},
+    spends = {},
 }
 I.res = R
 R.slotOf, R.slotOfToken = {}, {}
@@ -132,6 +133,17 @@ end
 -- and its estimate then).
 local usable, shortCost, shortT, shortGain, shortEst = {}, {}, {}, {}, {}
 
+-- The usability oracle (harness design §2): per credit record k (Events/Rows.lua's record id, a landed swing's `b`),
+-- the slot it paid (0: none), the hand, the deltas it added to est, lo and hi, its hit-rate step, the ability whose
+-- next answer judges it (0: not judged: it crossed no rung), whether the prediction is firm (the post-credit floor
+-- reaches the cost) and the slot's spend count at the credit. Rows registers I.CreditVerdict and I.Rescue.
+local RECORDS = 8
+local recR, recHand, recEst, recLo, recHi, recHit, recA, recFirm, recSpends = {}, {}, {}, {}, {}, {}, {}, {}, {}
+for k = 1, RECORDS do
+    recR[k], recHand[k], recEst[k], recLo[k], recHi[k], recHit[k], recA[k] = 0, 0, 0, 0, 0, 0, 0
+    recFirm[k], recSpends[k] = false, 0
+end
+
 local function clamp(v, max)
     if v < 0 then
         return 0
@@ -189,7 +201,7 @@ I.OnBuild(function(def, now)
         R.decl[r] = rate
         R.regE[r], R.regL[r], R.regH[r] = rate, rate * (1 - I.REGEN_SPREAD), rate * (1 + I.REGEN_SPREAD)
         R.dev[r], R.scale[r], R.spread[r] = 0, 1, I.REGEN_SPREAD
-        R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r], R.gain[r] = 0, 0, 0, false, 0
+        R.pinT[r], R.pinV[r], R.pinDelta[r], R.pinValid[r], R.gain[r], R.spends[r] = 0, 0, 0, false, 0, 0
         R.snapT[r], R.readT[r], R.readable[r] = -1e9, -1e9, false
         R.decayDef[r] = d.decay
         R.decay[r] = decayOf(r)
@@ -246,6 +258,9 @@ I.OnBuild(function(def, now)
     for a = 1, #def.abilities do
         usable[a], shortCost[a], shortT[a], shortGain[a], shortEst[a] = UNKNOWN, 0, 0, 0, 0
     end
+    for k = 1, RECORDS do
+        recA[k], recR[k] = 0, 0
+    end
 end)
 
 -- Slot r's `main` or (the off hand of a main-hand slot) `off` field for `hand`: a number, or the model's state-bound
@@ -521,11 +536,83 @@ local function ladder(r, c, affordable, t, lag)
 end
 I.Ladder = ladder
 
+-- One swing step of slot r for `hand` at t: c = 1 a landed swing (the hand's value x scale, spread around it), c = 3
+-- its crit (the hand's `crit`, unscaled); none for a crit of a slot without one. Allocates nothing.
+local function swingStep(r, hand, c, t)
+    local max, v, s, sp = R.max[r], 0, 1, 0
+    if c == 1 then
+        v, s, sp = I.SwingValue(r, hand), R.scale[r], R.spread[r]
+    else
+        v = I.SwingCrit(r, hand)
+    end
+    if c == 1 or v ~= 0 then -- a slot with no `crit` takes no sample for a crit
+        R.est0[r] = clamp(R.est0[r] + v * s, max)
+        R.lo0[r] = clamp(R.lo0[r] + v * (s - sp), max)
+        R.hi0[r] = clamp(R.hi0[r] + v * (s + sp), max)
+        I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
+    end
+end
+
+-- Credit record k paid slot r for `hand` (from e, lo and hi before it): its deltas, and which answer will judge it.
+-- The cheapest tracked spender of the slot whose cost the credit's estimate step crosses (e < c <= e + step), firm
+-- when the new floor reaches it; a credit crossing no rung is not judged. Allocates nothing.
+local function predict(k, r, hand, e, lo, hi, hit)
+    recR[k], recHand[k], recHit[k], recSpends[k] = r, hand, hit, R.spends[r]
+    recEst[k], recLo[k], recHi[k] = R.est0[r] - e, R.lo0[r] - lo, R.hi0[r] - hi
+    local best, cost = 0, 0
+    if not R.readable[r] then
+        for a = 1, I.ab.n do
+            if I.ab.slot[a] == r and not I.ab.multiCost[a] then
+                local c = I.CostOf(a)
+                if c > e and c <= R.est0[r] and (best == 0 or c < cost) then
+                    best, cost = a, c
+                end
+            end
+        end
+    end
+    recA[k], recFirm[k] = best, best > 0 and R.lo0[r] >= cost
+end
+
+-- The oracle's verdict on the records ability a judges, from its answer `now` at t (harness design §2.2), before the
+-- ladder reads it (§2.6): Rows decides whether the answer falls in the record's window and labels it; a firm credit
+-- answered short is retracted here (est, lo, hi and the hit rate lose what it added). One of our spends from the slot
+-- since the credit voids it, and so does a NOT answer in its window. Allocates nothing.
+local function judge(a, now, t)
+    for k = 1, RECORDS do
+        if recA[k] == a then
+            local r = recR[k]
+            if R.spends[r] ~= recSpends[k] then
+                recA[k] = 0
+            else
+                local ok = nil -- a NOT answer is no rung: in the window it closes the record unjudged
+                if now == YES or now == SHORT then
+                    ok = now == YES
+                end
+                local v = I.CreditVerdict(k, ok, t, recFirm[k])
+                if v ~= nil then
+                    recA[k] = 0
+                end
+                if v and now ~= YES and recFirm[k] then
+                    local max = R.max[r]
+                    R.est0[r] = clamp(R.est0[r] - recEst[k], max)
+                    R.lo0[r] = clamp(R.lo0[r] - recLo[k], max)
+                    R.hi0[r] = clamp(R.hi0[r] - recHi[k], max)
+                    hitRate[recHand[k]] = hitRate[recHand[k]] - recHit[k]
+                    I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Usable)
+                end
+            end
+        end
+    end
+end
+
 I.On(Obs.Usable, function(o, t, lag)
     local a = o.a
     local now = o.b == 1 and YES or (o.c == 1 and SHORT or NOT)
     local was = usable[a]
     usable[a] = now
+    if I.CreditVerdict then
+        judge(a, now, t)
+    end
     local r = I.ab.slot[a]
     if r == 0 or now == NOT or R.readable[r] or I.ab.multiCost[a] then
         return -- a second power cost (Overpower's combo points) makes a short answer ambiguous: no rung
@@ -543,10 +630,30 @@ I.On(Obs.Usable, function(o, t, lag)
             pin(r, e > c and e or c, 0, t, "pinned", Obs.Usable)
             R.pinValid[r] = false
         elseif R.swing[r] > 0 then
-            -- a swing-paid resource crosses at a swing: [c, c + one step of the larger hand), measured at its midpoint
-            local v, off = I.SwingValue(r), R.swingOff[r] ~= 0 and I.SwingValue(r, 2) or 0
-            local step = (v > off and v or off) * (R.scale[r] + R.spread[r])
-            pin(r, c, step, t, "pinned", Obs.Usable, true)
+            -- below the cost by every gain we modelled: a wound Rows dropped just before this flip may be the swing
+            -- that crossed it (the oracle's rescue): paid now, the crossing is explained and pins exactly
+            local hand, crit = nil, false
+            if I.Rescue and R.est0[r] < c then
+                hand, crit = I.Rescue(r, c - R.est0[r], shortT[a], t)
+            end
+            if hand then
+                local h = hitRate[hand] + HIT_ALPHA
+                hitRate[hand] = h < 1 and h or 1
+                swingStep(r, hand, 1, t)
+                if crit then
+                    swingStep(r, hand, 3, t)
+                end
+                local e = R.est0[r]
+                R.pinValid[r] = false
+                pin(r, e > c and e or c, 0, t, "pinned", Obs.Usable)
+                R.pinValid[r] = false
+            else
+                -- a swing-paid resource crosses at a swing: [c, c + one step of the larger hand), measured at its
+                -- midpoint
+                local v, off = I.SwingValue(r), R.swingOff[r] ~= 0 and I.SwingValue(r, 2) or 0
+                local step = (v > off and v or off) * (R.scale[r] + R.spread[r])
+                pin(r, c, step, t, "pinned", Obs.Usable, true)
+            end
         else
             local width = R.regH[r] * (t - shortT[a])
             pin(r, c, t - shortT[a] <= I.PIN_EXACT and 0 or width, t, "pinned", Obs.Usable)
@@ -582,15 +689,16 @@ I.On(Obs.Read, function(o, t, lag)
     end
 end)
 
--- A landed swing (c = 1: Events/Rows.lua paired the target's wound with our white swing, so never an avoid and never
+-- A landed swing (c = 1: Events/Rows.lua credited the target's wound to our white swing, so never an avoid and never
 -- a swing an on-next-swing strike took) pays each slot of its hand one step (the off hand its own value). It is
 -- staged when the wound arrives, one swing's lag after PLAYER_SWING (about 0.45 s main, about 1 s off, research
 -- 2026-10-16-swing-outcome-pairing): believed rage trails the game's by that step, and lo stays a floor. Its crit
--- (c = 3, the same pairing with a CRITICAL wound, right after its c = 1) adds the hand's `crit` once more, unscaled (an
+-- (c = 3, the same credit with a CRITICAL wound, right after its c = 1) adds the hand's `crit` once more, unscaled (an
 -- exact, documented amount; the scale absorbs the model's error). A swing (c = 4) pays nothing; it and c = 1
--- keep the hand's hit rate.
+-- keep the hand's hit rate. A credit's `b` names its record (the oracle): the first slot it pays keeps its deltas.
 I.On(Obs.Swing, function(o, t)
     local hand, c = o.a, o.c
+    local hit = 0
     if hand ~= 1 and hand ~= 2 then
         return
     elseif c == 4 then
@@ -598,23 +706,19 @@ I.On(Obs.Swing, function(o, t)
         return
     elseif c == 1 then
         local h = hitRate[hand] + HIT_ALPHA
-        hitRate[hand] = h < 1 and h or 1
+        h = h < 1 and h or 1
+        hit, hitRate[hand] = h - hitRate[hand], h
     elseif c ~= 3 then
         return
     end
+    local k = c == 1 and o.b >= 1 and o.b <= RECORDS and o.b or 0
     for r = 1, R.n do
         if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
-            local max, v, s, sp = R.max[r], 0, 1, 0
-            if c == 1 then
-                v, s, sp = I.SwingValue(r, hand), R.scale[r], R.spread[r]
-            else
-                v = I.SwingCrit(r, hand)
-            end
-            if c == 1 or v ~= 0 then -- a slot with no `crit` takes no sample for a crit
-                R.est0[r] = clamp(R.est0[r] + v * s, max)
-                R.lo0[r] = clamp(R.lo0[r] + v * (s - sp), max)
-                R.hi0[r] = clamp(R.hi0[r] + v * (s + sp), max)
-                I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
+            local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
+            swingStep(r, hand, c, t)
+            if k > 0 then
+                predict(k, r, hand, e, lo, hi, hit)
+                k = 0
             end
         end
     end
@@ -728,6 +832,8 @@ function I.ResourceShift(r, delta, t, event)
     R.pinDelta[r] = R.pinDelta[r] + delta
     if delta > 0 then
         R.gain[r] = R.gain[r] + delta -- explains a flip (the Usable apply)
+    elseif delta < 0 then
+        R.spends[r] = R.spends[r] + 1 -- a spend between a credit and its verdict voids the verdict (the oracle)
     end
     I.Sample(R.power[r], "modelled", R.est0[r], t, event)
 end
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `539 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 123 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      539 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual tests/Virtual tools docs/dev | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|undead|maul|heroic|overpower|shred|bloodrage|charge|grave|bear'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/Events/Rows.lua src/Hekili/Virtual/State/Families/Resources.lua \
  tests/Virtual/State/resources_spec.lua tests/Virtual/harness/alloc_spec.lua tests/Virtual/harness/group_spec.lua \
  tests/Virtual/harness/solo_spec.lua
git commit -m "feat(vs): the usability oracle: a credit that crosses a spender's cost is judged by the next answer and retracted when short; an unexplained flip rescues a dropped wound (combat harness design §2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin combat-harness`

---
### Task 4: Hits on us: per-attacker amount bands

Spec §4.1-§4.4 (as amended by Deviation 11); §6 §4's cases; §3.4's hits-on-us row.

**Files:**
- Modify: `src/Hekili/Virtual/Events/Attackers.lua`
- Test: `tests/Virtual/Events/cleu_rows_spec.lua` (new describe "per-attacker amount bands (combat harness design §4)", 4 cases: "learns each attacker's band from three clean credits; a wound off both clocks goes to the band that holds it", "gives a wound inside two clocks' tolerance to the one whose band holds it", "leaves a wound unattributed while a hostile on us has no band and no clock names it", "never widens a band from its own credits, nor from a partly blocked wound"), `tests/Virtual/harness/onus_spec.lua` (new: the 2x gate, the same-strength gate from the pull, the same strength joining reported; PlayerHit staged = fed in each), `tests/Virtual/harness/alloc_spec.lua` (two attackers, the second joining: band credits among the paths)

**Interfaces:**
- Consumes: the player's `UNIT_COMBAT` (school in its fifth argument), the attacker clocks and tokens as today.
- Produces: per clock slot `atkLo`, `atkHi`, `atkN` (cleared when the slot is reassigned); `L.BAND_LO, L.BAND_HI, L.BAND_N = 0.8, 1.2, 3`; `L.onus = { credited, byBand }` beside `L.unattributed`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/Events/cleu_rows_spec.lua b/tests/Virtual/Events/cleu_rows_spec.lua
index 97f0b0ac..b3aaaaed 100644
--- a/tests/Virtual/Events/cleu_rows_spec.lua
+++ b/tests/Virtual/Events/cleu_rows_spec.lua
@@ -537,6 +537,69 @@ describe("the synthesized combat log", function()
             assert.are.equal("Creature-1", got[6].row[4])
         end)
 
+        describe("per-attacker amount bands (combat harness design §4)", function()
+            local function hit(t, amount, flag)
+                ctl.now = t
+                ctl.Fire("UNIT_COMBAT", "player", "WOUND", flag or "", amount, 1)
+            end
+            local function source(i)
+                return got[i] and got[i].row[4]
+            end
+            -- A (the target) alone hits 20, 22, 24; then B (nameplate1) alone hits 60, 61, 62; then both are on us.
+            local function twoBands()
+                onUs("target", "Creature-A", nil)
+                ctl.Fire("PLAYER_TARGET_CHANGED")
+                hit(20, 20)
+                hit(22, 22)
+                hit(24, 24)
+                ctl.unitIs.targettarget = nil
+                ctl.Fire("UNIT_TARGET", "target")
+                onUs("nameplate1", "Creature-B", nil)
+                ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
+                hit(25.9, 60)
+                hit(27.9, 61)
+                hit(29.9, 62)
+                ctl.unitIs.targettarget = "player"
+                ctl.Fire("UNIT_TARGET", "target")
+            end
+
+            it(
+                "learns each attacker's band from three clean credits; a wound off both clocks goes to the band that holds it",
+                function()
+                    twoBands()
+                    hit(31, 21) -- A's clock: 30, 32; B's: 31.9
+                    hit(34.6, 63)
+                    assert.are.same({ "Creature-A", "Creature-B" }, { source(7), source(8) })
+                    assert.are.equal(2, L.onus.byBand)
+                end
+            )
+
+            it("gives a wound inside two clocks' tolerance to the one whose band holds it", function()
+                twoBands()
+                hit(31.95, 59) -- A's clock (32) and B's (31.9): only B's band holds 59
+                assert.are.same({ "Creature-B", 1 }, { source(7), L.onus.byBand })
+            end)
+
+            it("leaves a wound unattributed while a hostile on us has no band and no clock names it", function()
+                onUs("target", "Creature-A", nil)
+                onUs("nameplate1", "Creature-B", nil)
+                ctl.Fire("PLAYER_TARGET_CHANGED")
+                ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
+                hit(20, 20)
+                hit(21, 60)
+                assert.are.same({ 0, 2 }, { #got, L.unattributed })
+            end)
+
+            it("never widens a band from its own credits, nor from a partly blocked wound", function()
+                twoBands()
+                hit(33, 5, "BLOCK_REDUCED") -- A's clock (32), off by more than the tolerance: alone? no: unattributed
+                hit(35.1, 28) -- off both clocks, inside A's band (up to 1.2 x 24 = 28.8): A's by band, not learned
+                hit(37.6, 29.5) -- off both clocks (A re-anchored at 35.1), outside the band: it was not widened to 28
+                assert.are.same({ "Creature-A" }, { source(7) })
+                assert.are.equal(2, L.unattributed)
+            end)
+        end)
+
         it("allocates nothing per hit on us", function()
             local sink = I.Events.CreateFrame("Frame")
             local GetInfo = Facade.CombatLogGetCurrentEventInfo
diff --git a/tests/Virtual/harness/alloc_spec.lua b/tests/Virtual/harness/alloc_spec.lua
index a80ce96e..2cd917c5 100644
--- a/tests/Virtual/harness/alloc_spec.lua
+++ b/tests/Virtual/harness/alloc_spec.lua
@@ -1,13 +1,21 @@
 -- tests/Virtual/harness/alloc_spec.lua (harness design §3.6): one generated party fight (two other sources on our
--- target, a mob on us, our presses, usability answered from our true power: the oracle's verdicts, a retraction and a
--- rescue among them) replayed through VirtualState: after a warm-up, the replays allocate nothing.
+-- target, two mobs on us of different strength, the second joining: amount bands; our presses and usability answered
+-- from our true power: the oracle's verdicts, a retraction and a rescue among them) replayed through VirtualState:
+-- after a warm-up, the replays allocate nothing.
 local scenarios = require("Virtual.harness.scenarios")
 local drive = require("Virtual.harness.drive")
 local alloc = require("Virtual.State.helpers.alloc")
 
 describe("the harness drive", function()
     it("allocates nothing in VirtualState replaying a generated party fight", function()
-        local s = scenarios.stream(scenarios.oracle({ duration = 30, others = { "melee", "caster" } }), 2)
+        local o = scenarios.oracle({
+            duration = 60,
+            others = { "melee", "caster" },
+            attackers = 2,
+            joinAt = { [2] = 10 },
+            mobs = { { damage = { 10, 14 }, period = 2.0 }, { damage = { 20, 28 }, period = 2.6 } },
+        })
+        local s = scenarios.stream(o, 4)
         local c = drive.boot({ max = 100 })
         local ok, bytes = pcall(alloc.bytes, function(i)
             drive.run(c, s, i * 100)
@@ -15,7 +23,7 @@ describe("the harness drive", function()
         drive.restore(c)
         assert.is_true(ok, tostring(bytes))
         assert.are.equal(0, bytes)
-        local o = c.I.Log.oracle
-        assert.is_true(o.retracted > 0 and o.rescued > 0, "the fight exercises a retraction and a rescue")
+        local L = c.I.Log
+        assert.is_true(L.oracle.retracted > 0 and L.oracle.rescued > 0 and L.onus.byBand > 0, "every path exercised")
     end)
 end)
diff --git a/tests/Virtual/harness/onus_spec.lua b/tests/Virtual/harness/onus_spec.lua
new file mode 100644
index 00000000..298b9635
--- /dev/null
+++ b/tests/Virtual/harness/onus_spec.lua
@@ -0,0 +1,36 @@
+-- tests/Virtual/harness/onus_spec.lua (harness design §4.3): hits on us from two attackers through the real
+-- Attackers.lua (their speeds secret: clocks from the gaps), and every hit reaching the belief as a PlayerHit,
+-- attributed or not (§4.4).
+local metrics = require("Virtual.harness.metrics")
+
+local function mobs(a, b)
+    return { { damage = a, period = 2.0 }, { damage = b, period = 2.6 } }
+end
+
+describe("hits on us (harness gates)", function()
+    it(
+        "two attackers of 2x different strength, the second joining at 15 s: precision >= 0.95, coverage >= 0.80",
+        function()
+            local m = metrics.fights({ attackers = 2, joinAt = { [2] = 15 }, mobs = mobs({ 10, 14 }, { 20, 28 }) }, 100)
+            local line = metrics.onusLine(m)
+            assert.is_true(m.onusRight >= 0.95 * m.onusCredited and m.onusCredited >= 0.80 * m.onusAll, line)
+            assert.are.equal(m.hitsFed, m.hitsStaged)
+        end
+    )
+
+    it("two attackers of the same strength on us from the pull: precision >= 0.90, coverage reported", function()
+        local m = metrics.fights({ attackers = 2, mobs = mobs({ 10, 14 }, { 10, 14 }) }, 100)
+        print("\nsame strength, from the pull: " .. metrics.onusLine(m))
+        assert.is_true(m.onusRight >= 0.90 * m.onusCredited, metrics.onusLine(m))
+        assert.are.equal(m.hitsFed, m.hitsStaged)
+    end)
+
+    it(
+        "two of the same strength, the second joining at 15 s: reported (the first one's clock takes some of its hits)",
+        function()
+            local m = metrics.fights({ attackers = 2, joinAt = { [2] = 15 }, mobs = mobs({ 10, 14 }, { 10, 14 }) }, 30)
+            print("\nsame strength, the second joining: " .. metrics.onusLine(m))
+            assert.are.equal(m.hitsFed, m.hitsStaged)
+        end
+    )
+end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `541 successes / 3 failures / 2 errors / 0 pending`.
- `cleu_rows_spec` "per-attacker amount bands": three fail and one errors (today a wound off every clock with two hostiles on us is unattributed, and `L.onus` is nil);
- `onus_spec` "two attackers of 2x different strength...": today's clocks reach precision 0.88 and coverage 0.67 (gates 0.95, 0.80); the same-strength cases pass on today's code (nothing attributed from the pull);
- the harness `alloc_spec` errors on `L.onus` (nil).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/Events/Attackers.lua b/src/Hekili/Virtual/Events/Attackers.lua
index d6a1ff63..2bc6e1e5 100644
--- a/src/Hekili/Virtual/Events/Attackers.lua
+++ b/src/Hekili/Virtual/Events/Attackers.lua
@@ -6,8 +6,10 @@
 -- UnitAttackSpeed(unit) when plain, else learned from the gaps between hits on us. A hit is credited to the attacker
 -- whose clock predicts a swing nearest it within ATTACK_TOLERANCE; while a single hostile targets us and its clock is
 -- not set yet, to that one (which starts its clock); otherwise it stays unattributed and makes no row (no phantom
--- enemy for the tank branch, Events.lua's `ns.updateTarget( sourceGUID, ... )`). The same per-token reads count the
--- hostiles attacking someone else (VirtualState.LooseEnemies, tank design §2).
+-- enemy for the tank branch, Events.lua's `ns.updateTarget( sourceGUID, ... )`). A physical wound also has each
+-- attacker's amount band to go by (combat harness design §4): learned from the wounds its clock or the lone-hostile
+-- rule credited, it separates two attackers of different strength. The same per-token reads count the hostiles
+-- attacking someone else (VirtualState.LooseEnemies, tank design §2).
 -- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
 -- (docs/research/2026-10-14-virtual-combat-log-events.md, C2, C4, M1-M4, D13).
 
@@ -20,6 +22,9 @@ local floor = math.floor
 
 L.ATTACK_TOLERANCE = 0.2 -- seconds between a clock's predicted swing and a hit credited to it
 L.unattributed = 0
+-- A band fits a wound within [BAND_LO x its min, BAND_HI x its max] once BAND_N wounds taught it (UNMEASURED margins).
+L.BAND_LO, L.BAND_HI, L.BAND_N = 0.8, 1.2, 3
+L.onus = { credited = 0, byBand = 0 }
 
 -- The tokens whose target is checked: target, focus, nameplate1-40; each with "<token>target" built once.
 local TOKENS, TT, INDEX = { "target", "focus" }, {}, {}
@@ -34,11 +39,12 @@ for i = 1, #TOKENS do
     tokGUID[i], tokOnMe[i], tokSpeed[i], tokLoose[i] = "", false, 0, false
 end
 
--- Attacker clocks by GUID (8, the oldest anchor gives way).
+-- Attacker clocks by GUID (8, the oldest anchor gives way), each with its amount band (min and max over the slot's
+-- life, of `atkN` wounds).
 local N = 8
-local atkGUID, atkAnchor, atkPeriod = {}, {}, {}
+local atkGUID, atkAnchor, atkPeriod, atkLo, atkHi, atkN = {}, {}, {}, {}, {}, {}
 for k = 1, N do
-    atkGUID[k], atkAnchor[k], atkPeriod[k] = "", 0, 0
+    atkGUID[k], atkAnchor[k], atkPeriod[k], atkLo[k], atkHi[k], atkN[k] = "", 0, 0, 0, 0, 0
 end
 
 -- The clock of `guid`, or nil. Allocates nothing.
@@ -65,7 +71,7 @@ local function clockOf(guid)
             slot = j
         end
     end
-    atkGUID[slot], atkAnchor[slot], atkPeriod[slot] = guid, 0, 0
+    atkGUID[slot], atkAnchor[slot], atkPeriod[slot], atkLo[slot], atkHi[slot], atkN[slot] = guid, 0, 0, 0, 0, 0
     return slot
 end
 
@@ -166,13 +172,34 @@ end
 
 local MISSES = { DODGE = true, PARRY = true, BLOCK = true, MISS = true }
 
+-- A wound's amount as its attacker's unmodified hit: a crit halved, a crushing blow / 1.5; nil for a partly blocked one
+-- (the blocked part is not given).
+local function base(amount, flag)
+    if type(amount) ~= "number" or flag == "BLOCK_REDUCED" then
+        return nil
+    elseif flag == "CRITICAL" then
+        return amount / 2
+    elseif flag == "CRUSHING" then
+        return amount / 1.5
+    end
+    return amount
+end
+
+-- Whether clock k's band is usable and holds `a`.
+local function fits(k, a)
+    return k ~= nil and a ~= nil and atkN[k] >= L.BAND_N and a >= L.BAND_LO * atkLo[k] and a <= L.BAND_HI * atkHi[k]
+end
+
 S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
     if unit ~= "player" or (act ~= "WOUND" and not MISSES[act]) then
         return
     end
     local melee = act ~= "WOUND" or school == 1
+    local wound = act == "WOUND" and school == 1
+    local a = wound and base(amount, flag) or nil
     -- the candidates: each hostile targeting us once (a GUID can be the target and a plate); no clock is made here
-    local best, bestErr, single, n = nil, L.ATTACK_TOLERANCE, nil, 0
+    local best, bestErr, single, n, nTol, tolI, nFit, fitI = nil, L.ATTACK_TOLERANCE, nil, 0, 0, nil, 0, nil
+    local nNew, newI = 0, nil -- candidates whose band is not usable yet
     for i = 1, #TOKENS do
         if tokOnMe[i] then
             local guid, seen = tokGUID[i], false
@@ -187,12 +214,35 @@ S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
                     period = atkPeriod[k]
                 end
                 local err = clockError(k, period, t)
-                if melee and err <= bestErr then
-                    best, bestErr = i, err
+                if melee and err <= L.ATTACK_TOLERANCE then
+                    nTol, tolI = nTol + 1, i
+                    if err <= bestErr then
+                        best, bestErr = i, err
+                    end
+                end
+                if not (k and atkN[k] >= L.BAND_N) then
+                    nNew, newI = nNew + 1, i
+                elseif fits(k, a) then
+                    nFit, fitI = nFit + 1, i
                 end
             end
         end
     end
+    local byBand = false
+    if wound and a then -- harness design §4.2: the clock, unless the bands say another; else the bands; else the lone one
+        best = nil
+        if nTol == 1 then
+            best = tolI
+            local k = find(tokGUID[tolI])
+            if k and atkN[k] >= L.BAND_N and not fits(k, a) and nFit == 1 and nNew == 0 then
+                best, byBand = fitI, true
+            end
+        elseif nFit == 1 and nNew == 0 then -- every band known, one holds it
+            best, byBand = fitI, true
+        elseif nFit == 0 and nNew == 1 and n > 1 then -- every known band excludes it: the one without a band
+            best = newI
+        end
+    end
     if not best and n == 1 then
         -- one hostile on us: it is that one (a spell, no clock yet, or a swing off its clock: a new phase, which
         -- learn re-anchors without refining the period, since the gap is off by more than the tolerance)
@@ -202,9 +252,18 @@ S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
         L.unattributed = L.unattributed + 1
         return
     end
+    L.onus.credited = L.onus.credited + 1
     local src, dst = tokGUID[best], L.player
     if melee then -- a spell does not follow the swing clock: no clock made or moved for it
-        learn(clockOf(src), t, tokSpeed[best])
+        local k = clockOf(src)
+        learn(k, t, tokSpeed[best])
+        if byBand then
+            L.onus.byBand = L.onus.byBand + 1
+        elseif a then -- a band learns from the clock's, the lone hostile's and the elimination's credits, never its own
+            atkLo[k] = (atkN[k] == 0 or a < atkLo[k]) and a or atkLo[k]
+            atkHi[k] = a > atkHi[k] and a or atkHi[k]
+            atkN[k] = atkN[k] + 1
+        end
     end
     if act == "WOUND" and melee then
         local r = L.Emit("SWING_DAMAGE", 21, t, true, "onus", "inferred", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS)
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `546 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 124 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      546 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual tests/Virtual tools docs/dev | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|undead|maul|heroic|overpower|shred|bloodrage|charge|grave|bear'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/Events/Attackers.lua tests/Virtual/Events/cleu_rows_spec.lua \
  tests/Virtual/harness/alloc_spec.lua tests/Virtual/harness/onus_spec.lua
git commit -m "feat(vs): per-attacker amount bands for hits on us; a joining attacker found by elimination (combat harness design §4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin combat-harness`

---
### Task 5: Snapshot lines, the fixture tool, docs

Spec §1.5 and §2's snapshot lines, §4's line (as amended by Deviation 15); §3.5 (a new capture becomes a fixture).

**Files:**
- Modify: `src/Hekili/Virtual/Events/Rows.lua` (two lines), `src/Hekili/Virtual/Events/Attackers.lua` (the `rows onus` line replaces `rows unattributed hits on us`), `docs/dev/layout.md`, `docs/research/2026-10-16-swing-outcome-pairing.md`, `docs/research/2026-10-16-group-pairing-captures.md`
- Create: `tools/vslog_fixture.lua`
- Test: `tests/Virtual/Events/cleu_rows_spec.lua` ("writes the rows credited, oracle and onus lines in Snapshot() ..."), `tests/Virtual/harness/fixtures_spec.lua` (new describe "tools/vslog_fixture.lua": "turns a /vslog dump into the fixture's rows, our spells and secrets named as the fixtures do")

**Interfaces:**
- Produces: Snapshot lines `rows credited main=%d off=%d cast=%d background=%d avoidsBack=%d lag main=%.0f/%.0f off=%.0f/%.0f ref=%.0f/%.0f lambda exact=%.2f/%.2f avoid=%.2f`, `rows oracle judged=%d confirmed=%d retracted=%d soft=%d rescued=%d rescuedLate=%d`, `rows onus credited=%d unattributed=%d byBand=%d`; `lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" STRIKE=<id> DOT=<id>` (stdout: the fixture), `loadfile("tools/vslog_fixture.lua")("rows", text, ids)` (the rows).

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/Events/cleu_rows_spec.lua b/tests/Virtual/Events/cleu_rows_spec.lua
index b3aaaaed..a507bb93 100644
--- a/tests/Virtual/Events/cleu_rows_spec.lua
+++ b/tests/Virtual/Events/cleu_rows_spec.lua
@@ -225,6 +225,29 @@ describe("the synthesized combat log", function()
         assert.are.equal(0, bytes)
     end)
 
+    it(
+        "writes the rows credited, oracle and onus lines in Snapshot() (combat harness design §1.5, §2, §4)",
+        function()
+            ctl.guid.target = "Creature-1"
+            ctl.unitIs.targettarget = "player"
+            ctl.Fire("PLAYER_TARGET_CHANGED")
+            ctl.now = 10
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            ctl.now = 10.47
+            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 40, 1)
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 12, 1)
+            local snap = VS.Snapshot()
+            for _, line in ipairs({
+                "rows credited main=1 off=0 cast=0 background=0 avoidsBack=0 lag main=474/60 off=703/20 ref=1686/20 "
+                    .. "lambda exact=0.01/0.01 avoid=0.01\n",
+                "rows oracle judged=0 confirmed=0 retracted=0 soft=0 rescued=0 rescuedLate=0\n",
+                "rows onus credited=1 unattributed=0 byBand=0\n",
+            }) do
+                assert.is_truthy(snap:find(line, 1, true), line)
+            end
+        end
+    )
+
     describe("our swings and abilities on the target", function()
         local function row(i)
             return got[i] and got[i].row
diff --git a/tests/Virtual/harness/fixtures_spec.lua b/tests/Virtual/harness/fixtures_spec.lua
index 1ec105d7..d50e32cc 100644
--- a/tests/Virtual/harness/fixtures_spec.lua
+++ b/tests/Virtual/harness/fixtures_spec.lua
@@ -178,3 +178,29 @@ describe("the fixtures replayed through Rows.lua", function()
         assert.is_true(main == 22 and off >= 18, ("main %d/22 off %d/20"):format(main, off))
     end)
 end)
+
+describe("tools/vslog_fixture.lua", function()
+    it("turns a /vslog dump into the fixture's rows, our spells and secrets named as the fixtures do", function()
+        local dump = table.concat({
+            "<pasted_content>",
+            "     0 UNIT_SPELLCA player Cast-3-4615-1-2-100-7FFD244B25 100 nil nil",
+            "   771 PLAYER_SWING 2.2000000476837 0 nil nil nil",
+            "  1297 UNIT_COMBAT player PARRY  0 1",
+            "  2463 UNIT_COMBAT target WOUND CRITICAL 90 1",
+            "  4330 UNIT_SPELLCA player Cast-3-4615-1-2-285-4C4F5AEFDD 285 nil nil",
+            " 49873 UNIT_SPELLCA party1 S S CastBar-9296D9AA6601D8FE nil",
+            "vslog n=6 dropped=0",
+        }, "\n")
+        local rows = assert(loadfile("tools/vslog_fixture.lua"))("rows", dump, { ["285"] = "STRIKE" })
+        assert.are.same({
+            { 0, "C", "player", "OTHER" },
+            { 771, "S", 2.2, 0 },
+            { 1297, "U", "player", "PARRY", "", 0, 1 },
+            { 2463, "U", "target", "WOUND", "CRITICAL", 90, 1 },
+            { 4330, "C", "player", "STRIKE" },
+            { 49873, "C", "party1", "SECRET" },
+        }, rows)
+        local log1 = require("Virtual.harness.fixtures.log1").rows
+        assert.are.same({ log1[1], log1[2], log1[5] }, { rows[1], rows[2], rows[3] })
+    end)
+end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `546 successes / 2 failures / 0 errors / 0 pending`.
- `cleu_rows_spec` "writes the rows credited, oracle and onus lines in Snapshot()": today's Snapshot has `rows unattributed hits on us=0` and no `rows credited`/`rows oracle` lines;
- `fixtures_spec` "tools/vslog_fixture.lua ...": `loadfile` finds no tool.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/docs/dev/layout.md b/docs/dev/layout.md
index 60a1f735..e0f68f6a 100644
--- a/docs/dev/layout.md
+++ b/docs/dev/layout.md
@@ -6,6 +6,13 @@
 - `tests/` holds the busted specs and their helpers, mirroring the source tree: the specs for
   `src/Hekili/Virtual/State/` are in `tests/Virtual/State/`, their helpers in `tests/Virtual/State/helpers/`, and so
   on. `tests/Virtual/State/helpers/load.lua` names the addon root once (`ROOT = "src/Hekili/"`).
+- `tests/Virtual/harness/` is the combat harness (combat harness design §3): a seeded model of the Forever client
+  (entities, behaviours, the world, the observer, scenarios) that drives VirtualState through the fakes, with the
+  attribution gates (`solo_spec`, `group_spec`, `onus_spec`, `sweep_spec`). Its `fixtures/` are in-game /vslog dumps,
+  every token row kept; `fixtures_spec` replays them and fits the observer's defaults to them. A new capture becomes a
+  fixture with `lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" STRIKE=<id> DOT=<id>` (the weapon damage
+  UnitDamage read, our strike's and DoT's spell IDs) plus a header comment; a fit outside tolerance is retuned in the
+  same change. The gates make `busted` take about a minute.
 - `tools/`, `docs/` and `archive/` stay at the repository root, with the lint, test and type-check configs
   (`.busted`, `.luacheckrc`, `.luarc.json`). Run every tool and `busted` from the root.
 
diff --git a/docs/research/2026-10-16-group-pairing-captures.md b/docs/research/2026-10-16-group-pairing-captures.md
index 44bce316..bed8001e 100644
--- a/docs/research/2026-10-16-group-pairing-captures.md
+++ b/docs/research/2026-10-16-group-pairing-captures.md
@@ -181,3 +181,5 @@ Raw dump: in the job transcript (vslog n=451, second fight rows 171089-229713).
 
 ## Token semantics (confirmed with the user 2026-10-16)
 One event fires once per unit token resolving to the same unit (target/nameplateN/softinteract; player/targettarget): dedupe by reading one token. `player PARRY/DODGE/BLOCK/WOUND` = an attack ON the player (victim-side), not our attack; the same event drives Revenge and damage-taken rage.
+
+Fixtures: log 3 and G5 are harness fixtures, every token row kept (`tests/Virtual/harness/fixtures/log3.lua`, `log5.lua`).
diff --git a/docs/research/2026-10-16-swing-outcome-pairing.md b/docs/research/2026-10-16-swing-outcome-pairing.md
index 081bb555..b8cb0b89 100644
--- a/docs/research/2026-10-16-swing-outcome-pairing.md
+++ b/docs/research/2026-10-16-swing-outcome-pairing.md
@@ -205,3 +205,6 @@ Facts for the design:
 116581 UNIT_COMBAT nameplate1 WOUND CRITICAL 52 1
 116734 UNIT_COMBAT nameplate1 MISS  0 1
 ```
+
+Fixtures: logs 1 and 2 are harness fixtures, every token row kept (`tests/Virtual/harness/fixtures/log1.lua`,
+`log2.lua`); the pairing they measured is now a score (combat harness design, §1).
diff --git a/src/Hekili/Virtual/Events/Attackers.lua b/src/Hekili/Virtual/Events/Attackers.lua
index 2bc6e1e5..5d61add6 100644
--- a/src/Hekili/Virtual/Events/Attackers.lua
+++ b/src/Hekili/Virtual/Events/Attackers.lua
@@ -289,5 +289,6 @@ S.On("PLAYER_REGEN_ENABLED", nil, function()
 end)
 
 I.OnSnapshot(function(out)
-    out[#out + 1] = string.format("rows unattributed hits on us=%d", L.unattributed)
+    out[#out + 1] =
+        string.format("rows onus credited=%d unattributed=%d byBand=%d", L.onus.credited, L.unattributed, L.onus.byBand)
 end)
diff --git a/src/Hekili/Virtual/Events/Rows.lua b/src/Hekili/Virtual/Events/Rows.lua
index 9f7afcad..81843b43 100644
--- a/src/Hekili/Virtual/Events/Rows.lua
+++ b/src/Hekili/Virtual/Events/Rows.lua
@@ -566,3 +566,36 @@ S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
     end
     strikeWait = 0
 end)
+
+--- Snapshot's lines (allocates; debugging only): the credits and the background, the learned lags (ms: median/spread
+--- of the main hand, the off hand's own reference and its main reference) and background rates (per second: main and
+--- off exact, avoid); the oracle's counts.
+I.OnSnapshot(function(out)
+    local c, med, spr, o = L.credited, L.med, L.spr, L.oracle
+    out[#out + 1] = string.format(
+        "rows credited main=%d off=%d cast=%d background=%d avoidsBack=%d lag main=%.0f/%.0f off=%.0f/%.0f ref=%.0f/%.0f lambda exact=%.2f/%.2f avoid=%.2f",
+        c[1],
+        c[2],
+        c[3],
+        L.background,
+        L.avoidsBack,
+        med[1] * 1000,
+        spr[1] * 1000,
+        med[2] * 1000,
+        spr[2] * 1000,
+        med[3] * 1000,
+        spr[3] * 1000,
+        lambda(1),
+        lambda(4),
+        lambda(7)
+    )
+    out[#out + 1] = string.format(
+        "rows oracle judged=%d confirmed=%d retracted=%d soft=%d rescued=%d rescuedLate=%d",
+        o.judged,
+        o.confirmed,
+        o.retracted,
+        o.soft,
+        o.rescued,
+        o.rescuedLate
+    )
+end)
diff --git a/tools/vslog_fixture.lua b/tools/vslog_fixture.lua
new file mode 100644
index 00000000..83715ed8
--- /dev/null
+++ b/tools/vslog_fixture.lua
@@ -0,0 +1,72 @@
+-- tools/vslog_fixture.lua: turns a ForeverProbe /vslog dump (the in-game checkpoint's captures, combat harness design
+-- §5) into a harness fixture (tests/Virtual/harness/fixtures/): every token row kept, in ms since the first event; our
+-- spells as the fake spec's (`STRIKE` the on-next-swing strike, `DOT`, else `OTHER`, by the IDs given), another
+-- player's (secret) as `SECRET`. Run from the repository root:
+--   lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" STRIKE=<id> DOT=<id> > tests/Virtual/harness/fixtures/x.lua
+-- then write the fixture's header comment (what was captured, where it is described). Loaded with the argument "rows"
+-- (loadfile(...)("rows", text, ids)) it returns the parsed rows instead, for the specs.
+
+local mode, a2, a3 = ...
+
+-- The dump's rows: { ms, "S", duration, swingType }, { ms, "U", unit, action, flag, amount, school }, { ms, "C", unit,
+-- spell }; `ids` maps a spell ID (string) to STRIKE or DOT.
+local function parse(text, ids)
+    local rows = {}
+    for line in text:gmatch("[^\n]+") do
+        local p = {}
+        for w in line:gmatch("%S+") do
+            p[#p + 1] = w
+        end
+        local ms = tonumber(p[1])
+        if ms and p[2] == "PLAYER_SWING" then
+            rows[#rows + 1] = { ms, "S", math.floor(tonumber(p[3]) * 10 + 0.5) / 10, tonumber(p[4]) }
+        elseif ms and p[2] == "UNIT_COMBAT" then
+            local flag, amount, school = "", p[5], p[6]
+            if #p >= 7 then
+                flag, amount, school = p[5], p[6], p[7]
+            end
+            rows[#rows + 1] = { ms, "U", p[3], p[4], flag, tonumber(amount), tonumber(school) }
+        elseif ms and p[2] == "UNIT_SPELLCA" then
+            rows[#rows + 1] = { ms, "C", p[3], p[4] == "S" and "SECRET" or (ids[p[5]] or "OTHER") }
+        end
+    end
+    return rows
+end
+
+if mode == "rows" then
+    return parse(a2, a3 or {})
+end
+
+local ids = {}
+for i = 3, select("#", ...) do
+    local name, id = select(i, ...):match("^(%u+)=(%d+)$")
+    if name then
+        ids[id] = name
+    end
+end
+local f = assert(io.open(mode, "r"))
+local rows = parse(f:read("*a"), ids)
+f:close()
+local function cell(r)
+    local out = {}
+    for i, v in ipairs(r) do
+        out[i] = type(v) == "string" and string.format("%q", v) or tostring(v)
+    end
+    return "{ " .. table.concat(out, ", ") .. " }"
+end
+print("-- stylua: ignore")
+print("return {")
+print("    damage = { " .. a2:gsub(",", ", ") .. " },")
+print("    rows = {")
+local line = "       "
+for _, r in ipairs(rows) do
+    local c = cell(r)
+    if #line + #c + 2 > 118 then
+        print(line)
+        line = "       "
+    end
+    line = line .. " " .. c .. ","
+end
+print(line)
+print("    },")
+print("}")
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `548 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 125 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      548 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual tests/Virtual tools docs/dev | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|undead|maul|heroic|overpower|shred|bloodrage|charge|grave|bear'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add docs/dev/layout.md docs/research/2026-10-16-group-pairing-captures.md \
  docs/research/2026-10-16-swing-outcome-pairing.md src/Hekili/Virtual/Events/Attackers.lua \
  src/Hekili/Virtual/Events/Rows.lua tests/Virtual/Events/cleu_rows_spec.lua tests/Virtual/harness/fixtures_spec.lua \
  tools/vslog_fixture.lua
git commit -m "feat(vs): rows credited/oracle/onus snapshot lines; tools/vslog_fixture.lua turns a /vslog dump into a harness fixture; harness docs (combat harness design §1.5, §3.5)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin combat-harness`

---
### Task 6: CHECKPOINT: group attribution in game (spec §5), deferred to the user

Not a blocker: the branch can be reviewed and merged with this task open. No code unless a capture calls for it; each capture becomes a fixture (`tools/vslog_fixture.lua`, a header comment naming the capture) with its replay as a `fixtures_spec` case and, when its fit falls outside tolerance, the defaults retuned in the same commit (spec §3.5), each its own commit with the verification block.

- [ ] **Step 1: Point the client at the branch** (when the user is ready to play)

```bash
git push origin combat-harness
git -C ~/src/hekili checkout --detach combat-harness
```

Then `/reload` in game (no new file).

- [ ] **Step 2: CHECKPOINT: ask the user to run the following in game and paste each capture**

ForeverProbe loaded (`/vslog`, `VSCopy`; restart the client once if `Log.lua` is new), open-world mobs (no dummies). Each capture: `/vslog clear`, `/vslog on`, the fight, `/vslog off`, `/vslog dump`, then the snapshot line R, then paste. Each dump becomes a fixture (§3.5) and is replayed; the pass criteria are checked on the replay. Every line is under 255 characters.

R = `/run for l in Hekili.VirtualState.Snapshot():gmatch("rows [^\n]*") do VSCopy(l) end`

| # | Capture | Line(s) | Pass |
|---|---|---|---|
| G0 | build loads, new lines exist | R out of combat | `rows credited`, `rows oracle` and `rows onus` lines present |
| G1 | 2-player fight, dual wield, one partner in melee on the same mob: 20 s alone, 40 s both, 20 s partner alone | the /vslog sequence, then R | replay: segment A right-hand credits >= 94%; segment C 0 credits; segment B: no credit with school != 1 or in a foreign strike frame, credits per own swing within 10 points of segment A's. With the partner also recording (D7), aligned on the shared target rows: false credits <= 4 per 100 own swings |
| G2 | 5-player fight (dungeon pack or elite), >= 2 melee on our target, 60 s+ | as G1 | replay: the fitted background rates and lags inside the party scenario's ranges; the party gates (§3.4) hold on the model refitted to this capture |
| G3 | as G2 with a pet (`partypet1`) on our target | as G1 | as G2; no outcome counted twice across `target`/plate/soft tokens |
| G4 | B15: UNIT_AURA full-update cost after 60 s of a 5-player fight | `/run local u=Hekili.Engine.threadUpdates VSCopy(format("work %.2f ms frames %.1f",u.meanWorkTime,u.meanFrames))` | work <= 5.5 ms (solo 4.38 ms + 25%, proposed) |
| G5 | DONE 2026-10-16 (`tmp/pairing/log5.txt`): solo, dual wield, auto-attack only, 88 s | - | ruled the off-hand's two references (§1.1); added as a fixture (Task 1: `fixtures/log5.lua`) |
| G6 | solo, one hostile, our damage buff cast in combat (a self buff that adds attack power) | the /vslog sequence, then R | replay: main credits after the buff >= 85%, `background` does not grow faster than before it |
| G7 | party fight, we auto-attack and press nothing (the partner tanks: no damage taken), 60 s; record `SPELL_UPDATE_USABLE` too (`/vslog add SPELL_UPDATE_USABLE` before `/vslog on`) | the /vslog sequence, then R, then at combat end `/run local r=Hekili.VirtualState.Power(1,GetTime()) VSCopy(format("%.1f %.1f %.1f",r.lo,r.est,r.hi),UnitPower("player",1))` | `rows oracle` judged > 0; retracted <= 1 per 30 s; rescued counted; est within one white step of `UnitPower`; the log gives the WOUND -> `SPELL_UPDATE_USABLE` delay that sets `ORACLE_MIN/MAX` |

Turning a pasted dump into a fixture (from the worktree root; the weapon damage is UnitDamage's, read out of combat: `/run VSCopy(UnitDamage("player"))`; STRIKE and DOT are our on-next-swing strike's and DoT's spell IDs, kept out of the repository):

```bash
lua5.1 tools/vslog_fixture.lua dump.txt "36,50,24,32" STRIKE=<id> DOT=<id> > tests/Virtual/harness/fixtures/g1.lua
```

Then add the header comment (capture, date, segments) above `-- stylua: ignore`, and the replay case.

Known limits (say them with the results):
- The usability delay after a gain (`observer.DEFAULTS.usableDelay`, 0.1 s) and the oracle's window (0.1-0.6 s) are UNMEASURED until G7; a longer delay pushes verdicts out of the window (no verdict, nothing retracted).
- A false credit inside our core lag band with an in-range amount is indistinguishable from ours without a source (§1.6): the party gates measure its rate (1.35 per 100 swings; 5.69 with a pet in our off range).
- Two attackers of the same strength separate only by their clocks; when one joins later, the first one's clock takes some of its hits (precision 0.88 in the harness).
- Above the top spender's cost the oracle has nothing to judge (§2.4): the estimate there is the ladder's and the swing calibration's.

Fix what a capture shows, then repeat the capture. When the session ends: `git -C ~/src/hekili checkout --detach forever`.

---

## Self-Review

**1. Coverage of the spec**

| Spec | Task |
|---|---|
| §0 the pending-swing buffer kept, windows as lag densities, the hit-rate EMA and back-dated rows unchanged | 2 |
| §1.1 facts (lags, off hand's two references, avoid rate, crit share, others' outcomes, foreign strike frame, school on avoids, the on-swing proc) | 1 (observer rules and fits), 2 (seeds) |
| §1.2 actions and predictions: the lag density per hand, `W_h` capped at the period, the off hand's two references (`actRef`), our cast claims first | 2 |
| §1.3 classes: exact/loose/above, avoid, not a candidate (school, WOUND 0, foreign frame), amount unknown (form, no read) | 2 (Deviation 2) |
| §1.4 score, background from quiet windows, THETA, provisional avoids, same-ms avoids | 2 (Deviations 1, 3) |
| §1.5 learned vs constant, the N = 3 fallback dropped, zero allocation, the snapshot line | 2, 5 (Deviation 15) |
| §1.6 the prototype check replaced by the harness | 2 (the gates) |
| §2.1 prediction (cheapest crossed rung, firm) | 3 |
| §2.2 the verdict, retraction, the swing re-held or SWING_MISSED | 3 (Deviations 5, 6) |
| §2.3 recovery (the dropped ring, the rescue) | 3 (Deviations 7, 8) |
| §2.4 only threshold-crossing credits judged | 3 |
| §2.5 labels and bounded thresholds | 3 |
| §2.6 the retraction before the ladder | 3 |
| §3.1 the five layers, the observer's rules, rng, drive, metrics, fixtures, fake_api's UnitDamage | 1, 2 (metrics; Deviations 12-14) |
| §3.2 scenario knobs | 1 (scenarios), 2-4 (used) |
| §3.3 metrics | 2, 3, 4 |
| §3.4 scenarios and gates | 2 (solo, buff, form, party, pet, raid, sweep, fixtures), 3 (oracle; Deviations 9, 10), 4 (hits on us; Deviation 11) |
| §3.5 fixtures and the fit | 1, 5 (the tool; Deviation 13) |
| §3.6 allocation | 1-4 (harness alloc_spec grows with each task) |
| §4.1-§4.4 hits on us, bands, the rule, PlayerHit unchanged | 4 (Deviation 11) |
| §5 checkpoint | 6 |
| §6 tests | 2-5 (each task's Files line names its cases) |
| §7 decisions D1-D9 | "Decisions as built" |
| §8 out of scope | "Deliberately not built" |

**2. Placeholder scan:**
- No "TBD", "TODO", "implement later" or "similar to Task N"; the checkpoint's `<id>` placeholders are spell IDs the user supplies at capture time (kept out of the repository by the boundary rule).
- Every code step is a `git apply` patch from the replay, and every test step states its measured busted counts.

**3. Names across tasks:** spelled the same in every task and in the checkpoint:
- Rows: `L.THETA`, `L.Q`, `L.Q_AVOID`, `L.EPS`, `L.LAMBDA0`, `L.T0`, `L.TAU`, `L.med`, `L.spr`, `L.bg`, `L.quiet`, `L.credited`, `L.background`, `L.avoidsBack`, `L.ORACLE_MIN`, `L.ORACLE_MAX`, `L.THETA_MIN`, `L.THETA_MAX`, `L.theta`, `L.oracle`, `I.CreditVerdict`, `I.Rescue`
- Resources: `R.spends`, the records (`recR`, `recHand`, `recEst`, `recLo`, `recHi`, `recHit`, `recA`, `recFirm`, `recSpends`), `swingStep`, `predict`, `judge`
- Attackers: `atkLo`, `atkHi`, `atkN`, `L.BAND_LO`, `L.BAND_HI`, `L.BAND_N`, `L.onus`
- Harness: `observer.DEFAULTS`, `observer.lag`, `scenarios.oracle`, `drive.fixtureStream`, `metrics.fights`, `metrics.line`, `metrics.oracleLine`, `metrics.onusLine`

**4. Review Focus:** each line has its pinned tests (named in Review Focus 1-5).

**Concerns for the orchestrator:**
- (a) `busted` grows from 6 s to about 70 s (the gates: about 1,300 generated fights). `sweep_spec` alone takes about 12 s, under the spec's 20 s split line; it carries `#slow` for `busted --exclude-tags=slow` when iterating.
- (b) THETA 5 (Deviation 1) puts log 2's off hand exactly on its floor (31/33): a later change that loses one off-hand credit there fails the replay; the floor is the spec's.
- (c) The oracle's window and the usability delay are unmeasured (G7); the harness's oracle gates hold for a 0.1 s delay inside a 0.1-0.6 s window.
- (d) Deviation 11's elimination rule credits a joining attacker from the first wound every known band excludes; a known attacker's outlier (a crushing blow beyond its band's 1.2 x max) can seed the newcomer's band.
