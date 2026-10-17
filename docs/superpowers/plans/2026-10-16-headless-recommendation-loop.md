# Headless Recommendation Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stock Hekili runs headless under busted against the combat harness's world and presses its own first icon. Two Hekili instances live side by side in one busted process, each in its own Lua environment: ours reads the Forever client fake_api encodes (rage secret in combat, the target's auras raising), the oracle reads a secret-free client. The loop scores ours against the oracle (first-icon agreement, reaction, refused presses, flicker) and against the oracle playing the same seed (DPS, GCD idle, full-power time, debuff uptime), and gates engine health (errors, raises, nil reads, the facade's secret passthroughs, CPU per Update).

**Base (read first).** These patches are built on `forever-boundary` at `5ddc5fcf` (the core/content boundary cleanup: `tests/boundary_spec.lua`, the fake race test split, `ns.ResourceIsPoints`, the neutral fixtures `spender_a/b/c` and `CLASS_A` in `fake_spec`/`fake_api`), which is about to merge into `forever`. Execute this plan only after that merge: the worktree below branches from `forever` and the first patch's context needs `5ddc5fcf`'s `fake_api.lua` (`class = "CLASS_A"`). If `forever` has moved past the merge in these files, re-run Step 2 of Task 1 first: a context mismatch shows there.

**Architecture:**
- **Task 1 (the shell):** `tests/Virtual/harness/headless.lua`: SPIKE's scratch shell as a helper. `headless.new(o)` loads Hekili.toc into its own environment (`setfenv` on every chunk, `loadstring` and `getfenv(0)` bound to it), the client fake_api copied per instance, the stubs (aliases, frames, C_Timer on the fake clock, constants) in one file, the miss counter by phase against `KNOWN_LOAD_NILS`/`KNOWN_RUN_NILS`, login and a 5 s settle. fake_api gains every client function a facade row resolves and `UnitIsUnit(a, a)`; State.lua's dead `state.abs = safeAbs` goes. The Warrior character (`tests/Forever/helpers/warrior_world.lua`) boots in `loop_warrior_spec`.
- **Task 2 (the incremental observer):** `observer.new(W, k)` / `obs.step(tEnd)`; `observe` is one step to the end. The same-ms avoid and the strike frame's order are rolled by `behaviours.melee` from the world's second generator `W.crng`; the pull's reads become a `prepull` truth event; `k.usable` takes the content's answers. The harness gates re-measured at their bounds (H §9's table updated).
- **Task 3 (presses and the Warrior world):** `W.press(e, key, p)` and the generic verbs (`queueStrike`, `applyAura`, `dot`, `hit`, `gain`, `setForm`), kills, the observer's aura, queued-strike and kill answers; `warrior_world.lua`'s mapping, `resolve` and usability answers.
- **Task 4 (the loop and the oracle):** `tests/Virtual/harness/loop.lua`: two instances in lockstep on one world at 5 Hz, the first-icon press policy, run A and run B, the oracle's secret-free client (`k.plain`, `o.raw`) and its self-check; the client's cooldown and GCD flags, three-state usability, the highest known rank.
- **Task 5 (metrics and gates):** the loop's tallies and line; the Arms solo gate (20 fights, `#slow`) and the party report (`#party`, `make test-party`, not in `make check`).
- **Task 6:** the in-game CHECKPOINT C1 (the precombat queue), deferred to the user; not a blocker.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, StyLua, `make check` (Makefile: lint, fmt-check, typecheck, test, syntax, api-check).

**Spec:** `docs/superpowers/specs/2026-10-16-headless-recommendation-loop.md` (binding; its "Decisions (accepted 2026-10-16)" section rules). Inputs read for this plan: the SPIKE findings `docs/research/2026-10-16-headless-hekili-spike.md` and its scratch `shell.lua`, `run.lua`, `loop.lua`; `tests/Virtual/harness/*.lua`; `tests/Virtual/State/helpers/fake_api.lua`; `tests/Forever/helpers/{engine,load_warrior}.lua`; `src/Hekili/Core.lua` (`Hekili.Update`, :1547); `src/Hekili/State.lua:416`.

### Decisions as built

| Decision | As built | Where |
|---|---|---|
| D1 update rate | 5 Hz (`loop.TICK`, `o.hz = 10` the option) | Task 4 |
| D2 fights | Arms solo 20 fights of up to 3 minutes, `#slow` (busted grows from about 95 s to about 232 s; the gate alone about 137 s); the party report 10 fights behind `make test-party` (about 40 s), excluded from `make test` and `make check` | Task 5 |
| D3 agreement | first-icon agreement >= 0.85 and DPS A/B >= 0.97 as proposed; two other proposals missed on the first measurement and were diagnosed before their as-built bounds (Deviations 14, 15) | Task 5 |
| D4 the oracle | a secret-free client: our power, the target's health, our cooldown times plain, the target's auras listed (no aura error), usability without delay; the same events | Task 4 |
| D5 CPU | mean <= 10 ms per Update gated, p99 reported (measured 2.67 / 8.58 ms) | Task 5 |
| Boundary grep | dropped from `headless_spec` (the decision: `tests/boundary_spec.lua` instead); that spec scans `src/` only, so every task's verification greps the harness core for class and ability words | every task |

### Deviations from the spec (each measured or read)

1. **The stubs are built per instance** (§1.1 says "the shared read-only stubs table"): most close over the instance (its frames, timers, `ctl`, `IsLoggedIn`), and fake_api's namespaces are copied per instance (`setmetatable({}, { __index = api.C_Spell })`) so one instance's writes (Hekili adds `C_Spell` fields) stay its own. The environment holds the standard library by name, its own `table` (WoW's `table.wipe`), `loadstring` binding its result to the instance, `getfenv(0)` answering the instance (LibSharedMedia reads `_G.bit` through it) and WoW's `xpcall`. Boot 0.10 s each.
2. **Login settles 5 s** (`headless.SETTLE`): the display visibility (UI.lua:2102, a 3 s timer) and the spec's pack review (Engine/Spec.lua:1301, 5 s) run on the fake clock; without them no list is active (`ListActive: N`) and the queue stays empty.
3. **The miss lists, measured** (§1.4): `KNOWN_LOAD_NILS` holds the 51 names the load and login read (other addons, flavour probes, legacy spellbook globals, chat UI, GlobalStrings no queue path reads; `io` is LibDeflate.lua:3453's probe; `HekiliDB` a fresh profile; `id` and `squawk` read at login), `KNOWN_RUN_NILS` SPIKE's five plus `WeakAuras`. Measured: the run misses are empty in every fight.
4. **"The five rows absent on Forever"** (§6.2) are the passthrough rows no client here answers: `C_SpellBook.GetSpellBookItemInfo`, `C_SpellBook.GetSpellBookSkillLineInfo`, `C_Traits.GetNodeCost`, `C_Traits.GetSubTreeInfo`, `C_Traits.GetTreeCurrencyInfo`. The coverage test reads the passthrough and hybrid rows only: a virtual row resolves nothing (176 rows: 123 passthrough, 27 hybrid, 26 virtual).
5. **The observation draws use the world's second generator `W.crng`** (seed + 7919), rolled by `behaviours.melee` as §2.1.2 says. Drawn from `W.rng` they shifted every later world draw, and the solo gate "at most one wrong rescue" failed (seeds 1-200: 8 rescues, 2 ours). Diagnosed as seed noise around a gate of a handful of events: the base already fails it on seeds 401-600 (5 rescues, 2 ours). With `W.crng` every world (swings, lags, outcomes) is the base's per seed and H's table moves by at most 0.02 in a share (Task 2 Step 5).
6. **The pull's reads are a `prepull` truth event** (pull - 0.5 s; the target 0.1 s later), not pushed back from the pull: an incremental observer cannot fire an event earlier than the truth event it reads. The streams' times are unchanged.
7. **Usability has three states** (§2.1.3, §7): usable; short (`noMana` true); unusable for another reason (both false). The class file reads Victory Rush, Execute and Revenge as `usable or noMana` (Warrior.lua's `reactive`): the two-state fake made a short answer open Victory Rush every tick. Every rank's ID is answered: the class reads the highest known rank's usability.
8. **Cooldowns and the GCD are answered as the client's flags** (not in §2): a cast with a cooldown sets `isActive` on every rank of the spell (`p.ids`, the content's) with secret times (plain to the oracle), a GCD press sets the client's GCD spell's (the instance's `GCD_SPELL`, passed as `k.gcdSpell`: no ID in the harness), each with `SPELL_UPDATE_COOLDOWN`. Without them fake_api's ready shape (`isActive` false, plain) read every cooldown ready: Bloodrage stayed the first icon after its press and Whirlwind showed during the GCD (7 `gcd` refusals in 30 s).
9. **A press casts the highest known rank** (`VS.KnownID`): the rank-1 ID's success did not start the belief's cooldown (Mortal Strike believed ready at its cast).
10. **The oracle reads three facade rows raw** (`loop.RAW`, the `o.raw` override §4 prescribes): `UnitHealth` and `UnitHealthMax` (the target's health, virtual for ours) and `C_UnitAuras.GetDebuffDataByIndex`. The self-check failed on Sunder Armor through the belief: VirtualState counts the modelled stack on top of a plain read that arrives before the cast's drain (2 believed, 1 up; a VirtualState finding for its own change). The buff row stays the belief's: read raw, the stances (forms, which the belief turns into buffs) vanished and the oracle recommended Berserker Stance every tick (agreement 0.19). fake_api gains the two absent aura rows for it.
11. **The target's level is plain in the loop** (UnitLevel is plain in combat on Forever, the facade's passthrough row; fake_api answers an unset unit secret): with it secret, the traced fight's condition debug `tostring`ed it (780 Update raises) and `Facade.secrets` held `UnitLevel`.
12. **The client's answers are reset per fight** on one boot (dead, current, cooldowns, usability, unit health, the aura lists, the form) and each run's mob has its own GUID (`scenarios.world`'s `o.tag`): the second fight otherwise kept the first one's target debuffs (the same GUID) and its stance (567 refusals in one fight).
13. **Damage is compared per second** (§5.1 "our true damage dealt, A / B"): a fight ends at the kill (15000 health, about 2.5-3 minutes), so both runs deal the mob's health.
14. **"Never" is gated at <= 0.08** (§5.2 proposed 5%; measured 0.063). Diagnosed: the misses are the oracle's short Whirlwind windows at a rage threshold (the top confusion `whirlwind -> mortal_strike`, 322 ticks); ours reads 7.0 rage low there (mean believed minus true at disagreement ticks; 3.3 absolute over all ticks), the threshold flip §5.2 anticipates; DPS A/B 0.985 says they cost 1.5%.
15. **`cost` refusals are gated against the oracle's own** (ours <= the oracle's + 3 per 100 attempts; §5.2 proposed <= 3; measured 17.3, the oracle 15.9). Diagnosed: Hekili shows a spender ready at the predicted swing, and the swing's rage lands at the outcome lag (0.47 s) later; the oracle, reading the true rage, is refused as often. `gcd` and `cooldown` refusals are 0 as proposed.
16. **The self-check reads what Hekili reads, before the tick's press**: `VS.Power` for the power (its hybrid row returns the plain read), the facade's debuff row for the debuffs; the client sees a press the next tick, so the check runs before it; expiries are compared on each side's clock (a tick and an expiry meet within a ulp).
17. **World times are put on the instance's clock** in the loop's feed (a cooldown's start, an aura's expiry: `base + t`); each instance's clock continues across fights with a 30 s gap.
18. **The per-tick tallies append, the queue slots are reused** (§3: "preallocated arrays"): `run.ours`/`run.theirs`/`run.cpu` grow by one number or string per tick, no table per tick; the CPU figure times `headless.cycle` alone (the VirtualState flush, the timers and `Hekili.Update`), not the harness.
19. **Not built** (spec options nobody reads yet): `o.fresh` (a reboot per fight), `Hekili.Debug` lines kept while tracing (counted and dropped; `SaveDebugSnapshot` stubbed while tracing: Options.lua:8220 formats the version as a number).

### The current code, where it differs from the spec's description

- fake_api's `UnitHealth`/`UnitHealthMax` answer one value for every unit; the loop needs the target's (`ctl.unitHealth`, `ctl.unitHealthMax` by unit, the old fields the default).
- Hekili's gear scan reads the two-hander from `GetInventoryItemID("player", 16)` and `C_Item.GetItemInfo`'s ninth return (Events.lua:688-760); fake_api answered neither (`ctl.inventory`, `ctl.items`).
- VirtualState learns the GCD from the plain `isActive` edges of the GCD spell's cooldown, polled on `SPELL_UPDATE_COOLDOWN` (Sources/Spellbook.lua:101-123), and a cooldown's end from the flag; no harness event fired either (Deviation 8).
- `State.lua:416` is `state.abs = safeAbs` as the spec says; `:482` sets `math.abs`.

## How this plan was checked

Replayed, not hand-derived. A throwaway clone of `forever-boundary` at `5ddc5fcf` (tools from the main checkout's `.lua/`):
- Each task was written and measured there (the loop's numbers below are its own runs); then the tasks were rebuilt as a test commit and an implementation commit each, from `5ddc5fcf`.
- The patches below are `git diff` between those states; they were extracted from this file and re-applied with `git apply` to a fresh clone at `5ddc5fcf`, in this plan's order, with busted after every patch and `make check` after every task. The final tree equals the hand-built one. Nothing was committed to `~/src/hekili`.

Measured counts (full suite, `busted`, all tags; `make test` excludes `#party` from Task 5 on):

| State | Result |
|---|---|
| base `5ddc5fcf` | 565 successes / 0 / 0 / 0 |
| T1 tests only | 565 successes / 0 failures / 2 errors / 0 pending |
| T1 green | 572 successes / 0 failures / 0 errors / 0 pending |
| T2 tests only | 570 successes / 2 failures / 2 errors / 0 pending |
| T2 green | 574 successes / 0 failures / 0 errors / 0 pending |
| T3 tests only | 573 successes / 1 failure / 8 errors / 0 pending |
| T3 green | 582 successes / 0 failures / 0 errors / 0 pending |
| T4 tests only | 577 successes / 3 failures / 1 error / 0 pending |
| T4 green | 586 successes / 0 failures / 0 errors / 0 pending |
| T5 tests only | 586 successes / 0 failures / 2 errors / 0 pending |
| T5 green | 588 successes / 0 failures / 0 errors / 0 pending |

Task 5's green `busted` runs every tag (the party report included: 588, about 274 s); `make test` from Task 5 on excludes `#party` (587).

`make check` exited 0 after every task: luacheck 0 / 0 (131, 131, 132, 133, 133 files after the tasks in order), lua-language-server no problems, api-check ok in 65 loaded files with an empty inventory diff, `stylua --check .` silent; `make check` took about 2 minutes through Task 4 and 4 minutes 5 seconds after Task 5. The boundary grep printed nothing after every task, and the final tree equals the hand-built one (`diff -r`).

The loop's measurements on the final tree (the gates' own runs):

| Scenario (fights) | Measured | Gate (as built) |
|---|---|---|
| Arms solo, level 60, one mob of 15000 health (20) | agreement 0.965 over 16240 ticks; react median 0, p90 0 ticks, never 0.063; refused per 100 attempts: cost 17.3 (the oracle 15.9), gcd 0, cooldown 0; episodes 2.47/min; DPS A/B 0.985; full power 0.000 / 0.000; GCD idle 0.745 / 0.740; Sunder Armor up 0.94 / 0.95, Demoralizing Shout 0 / 0; flicker 0.68/min (the oracle 0.30); errors 0, raises 0, self-check 0, run misses none, `Facade.secrets` none; CPU per Update mean 2.67 ms, p99 8.58 ms; top confusions (oracle -> ours) whirlwind -> mortal_strike 322, whirlwind -> sunder_armor 81, mortal_strike -> sunder_armor 50; believed minus true rage at disagreements -7.0 | agreement >= 0.85; react median <= 1, p90 <= 3, never <= 0.08 (Deviation 14); gcd and cooldown 0, cost <= the oracle's + 3 (Deviation 15); DPS A/B >= 0.97; full and idle <= B + 0.03; each uptime >= B - 0.03; flicker <= 2/min; errors, raises, self-check 0; misses and secrets empty; CPU mean <= 10 ms |
| Arms party of 5, a melee and a caster on our target (10, `make test-party`) | agreement 0.954; never 0.067; cost 3.9 per 100 (the oracle 4.2); DPS A/B 1.106; GCD idle 0.721 / 0.729; Sunder Armor 0.95 / 0.95; flicker 0.80/min; errors 0, raises 0, self-check 0; CPU mean 2.78 ms | reported; errors, raises, self-check 0, misses empty |
| Smoke: one 30 s fight (fast) | presses accepted in both runs; errors, raises, misses, self-check 0 | as measured |
| C1's precombat queue (fast) | at 0.2 s, out of combat, a hostile target, no rage: bloodrage, battle_shout, berserker_stance | pinned; Task 6 compares it in game |
| Harness gates after Task 2 (H §9's table) | solo .991 / .989, false avoids 0.08; buff .897 / .944; form .965 / .966; party .831 / .979; party+pet .774 / .898; oracle and hits on us as in Task 2 Step 5 | H's bounds, unchanged |

## Global Constraints

From the spec, verbatim:

> **The boundary, binding for every section.** The shell, the loop, the observer and the world stay class-neutral: no
> class, spell, aura, talent, stance or rotation name, no spell ID (the house rule H applies to `Virtual/**` and the harness; this repo has no scan for it,
> so `headless_spec` greps the new harness files for the class tokens and the Warrior ability keys). Everything Warrior-specific (the ability-to-world mapping, the talents, the pack name, the
> uptime list, the gates' Arms scenario) lives in `tests/Forever/`. Each section ends with "Owns".

> The harness is test code and allocates (H §3.6). The loop's per-tick reads (queue slots, metric counters) use
> preallocated arrays so the CPU measurement (§5) measures Hekili, not the harness. The existing 0-byte gate for
> VirtualState (H `alloc_spec`) is unchanged and stays on the fake spec; Hekili's own per-cycle allocation is not gated
> (stock Hekili allocates; out of scope).

> Every task ends with busted, luacheck, StyLua, LuaLS and the API-read check.

> The class-name grep in headless_spec is unnecessary once tests/boundary_spec.lua
> (forever-boundary branch) is merged; use that.

The house rules for this plan:
- **Worktree.** Repository `~/src/hekili`, after `forever-boundary` (5ddc5fcf) is merged into `forever`. The orchestrator creates the worktree after the plan is committed: `git -C ~/src/hekili worktree add .claude/worktrees/headless-loop -b headless-loop forever`. Git from WSL only. After each task's green verification and clean review the orchestrator pushes `headless-loop`; never push to `forever` or any other branch; never force-push. No task merges.
- **Commits.** Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. An implementer on another model uses its own model's name.
- **The boundary, in the harness core.** `tests/boundary_spec.lua` scans `src/Hekili/Virtual` and `src/Hekili/Engine` only, not `tests/`, so the rule is checked by a grep in every task's verification: no class, race, stance or ability word, and no Warrior ability key, in any added line of `tests/Virtual/**`, `src/Hekili/**`, `tools/` or `docs/dev` (comments included). The one allowed hit is `Fury = 17` in headless.lua's `Enum.PowerType` stub (WoW's power-type name, a resource like `rage`; boundary_spec's ALLOW_KEYS reasoning). Everything Warrior-specific is in `tests/Forever/` (`warrior_world.lua`, `loop_warrior_spec.lua`). The harness core never names a spell ID either: the client's GCD spell reaches the observer from the instance (`ns.VirtualStateInternal.GCD_SPELL`).
- **Secret safety.** No new client read in `src/` (the only src change deletes a line). fake_api answers what the facade resolves; a secret stays fake_api's `SECRET` proxy; the harness compares a possibly-secret value only with `rawequal` (press_spec's lines). `tools/api_inventory.txt` stays unchanged.
- **Allocation.** Test code allocates (Global Constraints, §3). The VirtualState 0-byte gates (`tests/Virtual/State/alloc_spec.lua`, `tests/Virtual/harness/alloc_spec.lua`, the replay specs) stay green and unchanged; drive.lua's `op` gains branches that allocate only for `@aura` (no 0-byte drive fires one).
- **Style.** StyLua formats every file; each patch is StyLua-clean.
- **Tools.** Run everything from the worktree root. The worktree has no `.lua/`: `make check LUA_ENV=$HOME/src/hekili/.lua`; busted alone: `$HOME/src/hekili/.lua/bin/busted`. `make check` takes about 2 minutes before Task 5 and about 4 minutes from Task 5 on (busted about 232 s: the Arms gate about 137 s); `make test-fast` about 15 s.
- **Patches** are applied with `git apply` from the worktree root, in the order given. Each block is a heredoc, so copy it whole.
- **Every task ends green on `make check`** (the verification block in each task).
- **The user runs the game.** Task 6 is the in-game checkpoint; it is deferred to the user and blocks nothing: the branch can merge with it open. Every line is under 255 characters and copies its answer through `VSCopy(` (ForeverProbe). No new TOC file: `/reload` suffices.

## Review Focus

1. **The environment boundary** (§1.1, Deviation 1): every chunk `setfenv`ed, `loadstring` and `getfenv(0)` bound, the real `_G` untouched, two instances apart. Tests: headless_spec "keeps two instances apart and adds no global to the real _G", "loads every TOC file but the listed XML and logs in ...".
2. **The client model's fidelity in fake_api and the observer** (§6.2, Deviations 7-8, 10-11): which answers are secret, which plain, which flags fire which events; the oracle's raw rows. Tests: headless_spec "answers every facade row the client resolves from fake_api ...", observer_spec "answers a secret-free client under k.plain ...", "answers the content's usability ...", press_spec "accepts a press ..." (the cooldown flag), the loop smoke and the gate's `self-check 0` and `Facade.secrets` empty.
3. **Batch equals incremental, and the old gates keep their worlds** (§2.1.1-§2.1.2, Deviations 5-6). Tests: observer_spec "steps to the batch's stream in 0.2 s steps, and draws nothing from the world's generator"; every H gate spec at its bounds (Task 2 Step 5's table).
4. **The press and the mapping** (§2.1.4, §7, Deviation 9): the refusal order, an on-next-swing strike, the highest rank, costs and cooldowns read from the class (never copied), the stance requirements from the ability's fields. Tests: press_spec (5 cases), loop_warrior_spec "maps every ability ...", "resolves a press from the class file ...", "answers usability from the true world ...".
5. **The gates' bounds and their diagnoses** (§5.2, D3, Deviations 13-15): agreement and DPS as proposed; never and cost as built. Tests: loop_warrior_spec "Arms solo ... 20 fights" (its line in the failure message), the party report.

## File structure

```
tests/Virtual/harness/headless.lua            T1  headless.new: the environment, stubs, loader, login, miss counter, cycle; T3 items; T4 o.raw
tests/Virtual/harness/headless_spec.lua       T1  boot, misses, ticker, two instances, facade coverage, UnitIsUnit; T4 o.raw
tests/Virtual/State/helpers/fake_api.lua      T1  the facade's client rows, UnitIsUnit(a, a); T3 inventory/items; T4 unit health; T5 the aura rows
src/Hekili/State.lua                          T1  line 416 deleted
tests/Forever/helpers/warrior_world.lua       T1  the character; T3 the mapping, resolve, usability, rage, uptime, WORLD; T4 ranks, three states
tests/Forever/loop_warrior_spec.lua           T1  boot; T3 the mapping cases; T4 C1's precombat queue, the smoke; T5 the gate, the party report
tests/Virtual/harness/observer.lua            T2  observer.new / step, content usability, prepull; T3 auras, queue, kill; T4 k.plain, cooldown and GCD flags
tests/Virtual/harness/observer_spec.lua       T2  the moved draws, batch = incremental, content usability; T3 @current; T4 k.plain
tests/Virtual/harness/behaviours.lua          T2  same-ms avoid and strike order rolled (W.crng); T3 rage fn, avoidAt, a short queued strike; T4 ranks
tests/Virtual/harness/world.lua               T2  W.crng, prepull; T3 W.press and the verbs, kills; T4 the cast's GCD and ranks
tests/Virtual/harness/scenarios.lua           T2  prepull, sameMs; T4 scenarios.world (weapons, mobHealth, pull, prepull, form, tag)
tests/Virtual/harness/drive.lua               T2  drive.op exported; T3 @current, @dead, @aura; T4 @power, @health, @cooldown, three-state @usable
tests/Virtual/harness/entities.lua            T3  gcdUntil, cdUntil, avoidAt
tests/Virtual/harness/press_spec.lua          T3  W.press and the verbs (5 cases); T4 the cooldown flag
tests/Virtual/harness/loop.lua                T4  loop.new / run / fight; T5 tally, summary, line, the trace, the oracle's raw debuff row
docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md  T2  §9's gate tables re-measured
Makefile                                      T5  test excludes #party; test-fast excludes slow,party; test-party
```

Deliberately not built (a review should not flag these):
- positions, movement and range: every target is in melee range (`ctl.inRange.target`), Charge pays its rage only (a shortcut comment in warrior_world.lua);
- out-of-combat rage decay and rage from hits on us in the world's truth (VirtualState models both; the precombat window is 3 s and the harness mob hits for 10-14: about 0.1 rage a hit), Slam's cast time;
- `o.fresh` (a reboot per fight), the renderer, Druid content (§8.1, §11);
- a raw buff row for the oracle (Deviation 10), a fix for VirtualState's stacked-debuff count (a finding, its own change).

---
### Task 1: The shell: stock Hekili headless in its own environment, the fake client completed

Spec §1 (the shell: §1.1 one instance one environment, §1.2 every stub in one file, §1.3 loader, clock, timers, login, §1.4 the miss counter), §6 (fake_api and src fixes), §7's character, §9's headless_spec; Deviations 1-4.

**Files:**
- Create: `tests/Virtual/harness/headless.lua`, `tests/Forever/helpers/warrior_world.lua` (the character only)
- Modify: `tests/Virtual/State/helpers/fake_api.lua` (`UnitIsUnit(a, a)` true first; `ctl.classID`, `ctl.specID`, `ctl.powerType`, `ctl.role`; every passthrough and hybrid facade row's client function: plain constants or `ctl` answers, `C_AddOns.GetAddOnMetadata` from Hekili.toc's `## Key: value` lines, `C_SpecializationInfo` from `ctl.specID`, `C_Spell.GetSpellInfo` a table built once per ID), `src/Hekili/State.lua` (line 416 `state.abs = safeAbs` deleted)
- Test: `tests/Virtual/harness/headless_spec.lua` (new, fast, class-neutral boot: "loads every TOC file but the listed XML and logs in (OnInitialize, OnEnable, VirtualState started)", "reads no unset global at load or login beyond the known lists; safeAbs is not one", "runs a ticker on the fake clock and nothing before its time", "keeps two instances apart and adds no global to the real _G", "answers every facade row the client resolves from fake_api, but the five absent on Forever", "answers UnitIsUnit true for a unit and itself; a secret answer for two tokens stays secret"), `tests/Forever/loop_warrior_spec.lua` (new: "boots the Arms character: three entries out of combat with a target, no error, no unlisted nil read")

**Interfaces:**
- Consumes: `fake_api.new()` (`api`, `ctl`), Hekili.toc and every file it lists, `Forever.helpers.load_warrior` (the recording load: each ability's `id` and `copy`).
- Produces (test code):
  - `headless.new(o)` -> `H = { env, api, ctl, ns, Hekili, frames, timers, misses, errors, loadErrors, prints, phase, Fire, RunTimers, CreateFrame, stub }`; `o.character` { class, classID, specID, level, known = { spellID... }, talents = { [spellID] = rank }, power = { type, token, max, value [0] (Task 3: nil, secret as on Forever) }, speed, forms, form }, `o.pack`, `o.now` [1000];
  - `headless.unexpected(H, phase)` (sorted names outside the phase's list), `headless.cycle(H, t)` (clock, the VirtualState frame's OnUpdate, the due timers, `xpcall(Hekili.Update)`), `headless.ROOT`, `headless.SETTLE` (5), `headless.SKIPPED`, `headless.KNOWN_LOAD_NILS`, `headless.KNOWN_RUN_NILS`;
  - `warrior_world.character()`, `warrior_world.SPEC` (1491), `CLASS_ID`, `PACK` ("Arms"), `KIT`, `TALENTS`.
  - Process-wide: `string.trim`, `string.split` (the helper's header says so).

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/loop_warrior_spec.lua b/tests/Forever/loop_warrior_spec.lua
new file mode 100644
index 00000000..1e5f7626
--- /dev/null
+++ b/tests/Forever/loop_warrior_spec.lua
@@ -0,0 +1,21 @@
+-- tests/Forever/loop_warrior_spec.lua (headless loop design §5, §7, §9): stock Hekili headless as a level 60 Arms
+-- Warrior (tests/Forever/helpers/warrior_world.lua) against the harness's world.
+local headless = require("Virtual.harness.headless")
+local ww = require("Forever.helpers.warrior_world")
+
+describe("headless Arms", function()
+    it("boots the Arms character: three entries out of combat with a target, no error, no unlisted nil read", function()
+        local H = headless.new({ character = ww.character(), pack = ww.PACK })
+        assert.are.same({}, H.loadErrors)
+        assert.are.equal(ww.SPEC, H.Hekili.State.spec.id)
+        H.ctl.inRange.target, H.ctl.level.target = true, 60
+        H.Fire("PLAYER_TARGET_CHANGED")
+        assert.is_true(headless.cycle(H, H.ctl.now + 0.2))
+        local q = H.ns.UI.Displays.Primary.Recommendations
+        for i = 1, 3 do
+            assert.is_table(H.Hekili.Class.abilities[q[i].actionName], tostring(q[i].actionName))
+        end
+        assert.are.same({}, H.errors)
+        assert.are.same({}, headless.unexpected(H, "run"))
+    end)
+end)
diff --git a/tests/Virtual/harness/headless_spec.lua b/tests/Virtual/harness/headless_spec.lua
new file mode 100644
index 00000000..c695b5f8
--- /dev/null
+++ b/tests/Virtual/harness/headless_spec.lua
@@ -0,0 +1,96 @@
+-- tests/Virtual/harness/headless_spec.lua (headless loop design §1, §6, §9): stock Hekili boots headless in its own
+-- environment on fake_api, with no character (class-neutral: the content's characters are booted in tests/Forever).
+local headless = require("Virtual.harness.headless")
+local fake = require("Virtual.State.helpers.fake_api")
+
+-- The facade's passthrough rows no client in this repository answers (absent on Forever by the facade's own sweep;
+-- nothing on the recommendation path reads them), each a row fake_api leaves out on purpose.
+local ABSENT = {
+    ["C_SpellBook.GetSpellBookItemInfo"] = "retail spellbook item API",
+    ["C_SpellBook.GetSpellBookSkillLineInfo"] = "retail spellbook tabs API",
+    ["C_Traits.GetNodeCost"] = "retail talent currency",
+    ["C_Traits.GetSubTreeInfo"] = "retail hero talents",
+    ["C_Traits.GetTreeCurrencyInfo"] = "retail talent currency",
+}
+
+describe("headless Hekili", function()
+    local H
+    setup(function()
+        H = headless.new()
+    end)
+
+    it("loads every TOC file but the listed XML and logs in (OnInitialize, OnEnable, VirtualState started)", function()
+        assert.are.same({}, H.loadErrors)
+        assert.is_table(H.Hekili.DB.profile) -- AceDB's profile: OnInitialize ran
+        assert.are.equal(H.env, H.ns.VirtualStateInternal.api) -- VS.Start(_G) at PLAYER_LOGIN (OnEnable)
+        assert.is_true(H.env.IsLoggedIn())
+    end)
+
+    it("reads no unset global at load or login beyond the known lists; safeAbs is not one", function()
+        assert.are.same({}, headless.unexpected(H, "load"))
+        assert.are.same({}, headless.unexpected(H, "login"))
+        assert.is_nil(H.misses.load.safeAbs)
+        assert.is_nil(headless.KNOWN_LOAD_NILS.safeAbs)
+        assert.are.equal(math.abs, H.Hekili.State.abs)
+    end)
+
+    it("runs a ticker on the fake clock and nothing before its time", function()
+        local n = 0
+        local t = H.env.C_Timer.NewTicker(1, function()
+            n = n + 1
+        end)
+        local now = H.ctl.now
+        H.RunTimers(now + 0.5)
+        assert.are.equal(0, n)
+        H.RunTimers(now + 2)
+        assert.are.equal(2, n)
+        t:Cancel()
+        H.RunTimers(now + 5)
+        assert.are.equal(2, n)
+    end)
+
+    it("keeps two instances apart and adds no global to the real _G", function()
+        local before = {}
+        for k in pairs(_G) do
+            before[k] = true
+        end
+        local other = headless.new({ now = 50 })
+        assert.are_not.equal(H.Hekili, other.Hekili)
+        assert.are_not.equal(H.env.LibStub, other.env.LibStub)
+        other.ctl.now = 60
+        assert.are.equal(60, other.env.GetTime())
+        assert.are_not.equal(60, H.env.GetTime())
+        local added = {}
+        for k in pairs(_G) do
+            if not before[k] then
+                added[#added + 1] = tostring(k)
+            end
+        end
+        assert.are.same({}, added)
+        assert.is_nil(rawget(_G, "Hekili"))
+        assert.is_nil(rawget(_G, "LibStub"))
+    end)
+
+    it("answers every facade row the client resolves from fake_api, but the five absent on Forever", function()
+        local api = fake.new()
+        local missing = {}
+        for _, name in ipairs(H.ns.Facade.Inventory()) do
+            if H.ns.Facade.Status(name) ~= "virtual" and not ABSENT[name] then
+                local space, key = name:match("^([%w_]+)%.([%w_]+)$")
+                local fn = space and api[space] and api[space][key] or (not space and api[name])
+                if type(fn) ~= "function" then
+                    missing[#missing + 1] = name
+                end
+            end
+        end
+        assert.are.same({}, missing)
+    end)
+
+    it("answers UnitIsUnit true for a unit and itself; a secret answer for two tokens stays secret", function()
+        local api, ctl = fake.new()
+        assert.is_true(api.UnitIsUnit("player", "player"))
+        assert.is_true(api.UnitIsUnit("target", "target"))
+        ctl.unitIs.targettarget = fake.SECRET
+        assert.is_true(api.issecretvalue(api.UnitIsUnit("targettarget", "player")))
+    end)
+end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `565 successes / 0 failures / 2 errors / 0 pending`.
- `headless_spec` and `loop_warrior_spec` error at load: `module 'Virtual.harness.headless' not found`.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/State.lua b/src/Hekili/State.lua
index d2f3a476..97b5e3d4 100644
--- a/src/Hekili/State.lua
+++ b/src/Hekili/State.lua
@@ -413,7 +413,6 @@ setmetatable( state.trinket.main_hand.is, mt_trinket_is )
 
 state.max = safeMax
 state.min = safeMin
-state.abs = safeAbs
 
 if Hekili.Version:match( "^Dev" ) then
     state.print = print
diff --git a/tests/Forever/helpers/warrior_world.lua b/tests/Forever/helpers/warrior_world.lua
new file mode 100644
index 00000000..790e6527
--- /dev/null
+++ b/tests/Forever/helpers/warrior_world.lua
@@ -0,0 +1,68 @@
+-- tests/Forever/helpers/warrior_world.lua (headless loop design §7): the Warrior content of the class-neutral headless
+-- loop: the character the instance logs in as. Spell IDs come from the class file itself (load_warrior's recording
+-- load: each ability's `id` and `copy` ranks), never copied here.
+local loadWarrior = require("Forever.helpers.load_warrior")
+
+local M = {}
+
+M.SPEC, M.CLASS_ID, M.PACK = 1491, 1, "Arms"
+
+-- The Arms kit a level 60 Warrior has trained (every rank: Classic trains them all by 60) and the talent-granted
+-- Mortal Strike of the build below.
+M.KIT = {
+    "battle_shout",
+    "battle_stance",
+    "berserker_stance",
+    "bloodrage",
+    "charge",
+    "cleave",
+    "defensive_stance",
+    "demoralizing_shout",
+    "execute",
+    "hamstring",
+    "heroic_strike",
+    "intercept",
+    "mortal_strike",
+    "overpower",
+    "pummel",
+    "rend",
+    "sunder_armor",
+    "thunder_clap",
+    "victory_rush",
+    "whirlwind",
+}
+-- An Arms build by definition spell (the SPIKE's): Mortal Strike, Anger Management, Deep Wounds 3, Tactical Mastery 5,
+-- Impale 2, Improved Rend 3.
+M.TALENTS = { [12294] = 1, [12296] = 1, [12834] = 3, [12295] = 5, [16493] = 2, [12163] = 3 }
+
+--- The character for headless.new (§1.3): level 60, the kit known, the Arms talents, rage 0 of 100, a two-hand weapon
+--- (speed 3.6), the three stances as forms, Battle Stance up.
+function M.character()
+    local w = loadWarrior.load()
+    local known = {}
+    for _, key in ipairs(M.KIT) do
+        local a = assert(w.abilities[key], key)
+        known[#known + 1] = a.id
+        for _, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
+            known[#known + 1] = id
+        end
+    end
+    local forms = {}
+    for i, key in ipairs({ "battle_stance", "defensive_stance", "berserker_stance" }) do
+        forms[i] = w.abilities[key].id
+    end
+    return {
+        class = "WARRIOR",
+        classID = M.CLASS_ID,
+        specID = M.SPEC,
+        level = 60,
+        known = known,
+        talents = M.TALENTS,
+        power = { type = 1, token = "RAGE", max = 100, value = 0 },
+        speed = { 3.6 },
+        forms = forms,
+        form = 1,
+    }
+end
+
+return M
diff --git a/tests/Virtual/State/helpers/fake_api.lua b/tests/Virtual/State/helpers/fake_api.lua
index e6d5b15f..274e40ba 100644
--- a/tests/Virtual/State/helpers/fake_api.lua
+++ b/tests/Virtual/State/helpers/fake_api.lua
@@ -63,6 +63,10 @@ function M.new()
         form = 0, -- GetShapeshiftForm (0: none)
         forms = {}, -- [form index] = its spell ID (GetShapeshiftFormInfo's 4th return)
         damage = { 0, 0, 0, 0 }, -- UnitDamage's min and max main, min and max off (the harness's out-of-combat cache)
+        classID = 0, -- UnitClass's third return
+        specID = nil, -- C_SpecializationInfo.GetSpecializationInfo(1)'s ID (nil: no specialization)
+        powerType = { 0, "MANA" }, -- UnitPowerType("player")
+        role = "DAMAGER",
     }
     local api = { ctl = ctl }
 
@@ -137,6 +141,9 @@ function M.new()
         return v
     end
     function api.UnitIsUnit(a, b)
+        if a == b then -- the client: a unit is itself, never a secret (headless loop design §6.1)
+            return true
+        end
         local v = ctl.unitIs[a]
         if v == SECRET then
             return SECRET
@@ -249,6 +256,236 @@ function M.new()
         end,
     }
 
+    -- The rest of the client the facade resolves (headless loop design §6.2): every passthrough and hybrid row of
+    -- ns.Facade.Inventory() but the five absent on Forever, so the client model is this one file. Each answers a plain
+    -- constant or a `ctl` field: none is secret on Forever by the facade's probes.
+    local function none() end
+    local function no()
+        return false
+    end
+    local function zero()
+        return 0
+    end
+    function api.GetBuildInfo()
+        return "1.60.1", "70338", "Oct 1 2026", 16001
+    end
+    function api.GetLocale()
+        return "enUS"
+    end
+    api.GetCVar, api.GetCursorInfo, api.GetActionInfo, api.GetBindingKey = none, none, none, none
+    api.GetInventoryItemID, api.GetSpecializationInfoByID, api.GetStablePetInfo = none, none, none
+    api.UnitPhaseReason, api.UnitThreatSituation, api.UnitTokenFromGUID, api.IsActionInRange = none, none, none, none
+    api.HasOverrideActionBar, api.HasVehicleActionBar, api.IsInJailersTower, api.SpellIsSelfBuff = no, no, no, no
+    api.IsMounted, api.IsResting, api.IsInGroup, api.IsInRaid, api.UnitCanAssist = no, no, no, no, no
+    api.UnitIsTrivial, api.UnitIsPVP, api.UnitInVehicle, api.UnitHasVehicleUI, api.UnitOnTaxi = no, no, no, no, no
+    api.UnitInParty, api.UnitInRaid = no, none
+    api.GetHaste, api.GetFrameCPUUsage, api.GetNumGroupMembers, api.GetNumSubgroupMembers = zero, zero, zero, zero
+    function api.GetFramerate()
+        return 60
+    end
+    function api.GetNetStats()
+        return 0, 0, 50, 50
+    end
+    function api.GetRealmName()
+        return "Realm"
+    end
+    function api.GetNumClasses()
+        return 11
+    end
+    function api.GetClassInfo()
+        return ctl.class, ctl.class, ctl.classID
+    end
+    function api.UnitClass()
+        return ctl.class, ctl.class, ctl.classID
+    end
+    function api.UnitRace()
+        return "Race", "Race", 1
+    end
+    function api.UnitName(u)
+        return u == "player" and "Player" or "Unit"
+    end
+    function api.UnitSex()
+        return 2
+    end
+    function api.UnitFactionGroup()
+        return "Horde", "Horde"
+    end
+    function api.UnitEffectiveLevel(u)
+        return api.UnitLevel(u)
+    end
+    function api.UnitPowerType()
+        return ctl.powerType[1], ctl.powerType[2]
+    end
+    function api.UnitAffectingCombat()
+        return ctl.combat
+    end
+    function api.UnitIsPlayer(u)
+        return u == "player"
+    end
+    function api.UnitIsFriend(_, u)
+        return u == "player"
+    end
+    function api.UnitIsDeadOrGhost(u)
+        return ctl.dead[u] == true
+    end
+    function api.UnitClassification()
+        return "normal"
+    end
+    function api.UnitCreatureType()
+        return "Beast"
+    end
+    function api.UnitIsConnected()
+        return true
+    end
+    function api.GetUnitSpeed()
+        return 0, 7, 7, 4.72
+    end
+    function api.IsInInstance()
+        return false, "none"
+    end
+    function api.GetInstanceInfo()
+        return "World", "none", 0, "", 5, 0, false, 1
+    end
+    function api.IsPlayerSpell(id)
+        return ctl.known[id] == true
+    end
+    api.IsSpellKnown, api.IsSpellKnownOrOverridesKnown = api.IsPlayerSpell, api.IsPlayerSpell
+    function api.GetManaRegen()
+        return 0, 0
+    end
+    function api.SecureCmdOptionParse(s)
+        return s
+    end
+    api.AuraUtil = {
+        UnpackAuraData = function(a)
+            if not a then
+                return nil
+            end
+            local p = a.points or {}
+            return a.name,
+                a.icon,
+                a.applications,
+                a.dispelName,
+                a.duration,
+                a.expirationTime,
+                a.sourceUnit,
+                a.isStealable,
+                a.nameplateShowPersonal,
+                a.spellId,
+                a.canApplyAura,
+                a.isBossAura,
+                a.isFromPlayerOrPlayerPet,
+                a.nameplateShowAll,
+                a.timeMod,
+                p[1],
+                p[2],
+                p[3]
+        end,
+    }
+    local toc = {} -- C_AddOns.GetAddOnMetadata answers the TOC's `## Key: value` lines (State.lua reads Version)
+    local fh = io.open("src/Hekili/Hekili.toc")
+    if fh then
+        for line in fh:lines() do
+            local k, v = line:match("^## ([%w%-]+): (.-)%s*$")
+            if k then
+                toc[k] = v
+            end
+        end
+        fh:close()
+    end
+    api.C_AddOns = {
+        GetAddOnMetadata = function(_, k)
+            return toc[k]
+        end,
+        IsAddOnLoaded = no,
+        LoadAddOn = no,
+    }
+    local white = { r = 1, g = 1, b = 1 }
+    function white.GenerateHexColor()
+        return "ffffffff"
+    end
+    api.C_ClassColor = {
+        GetClassColor = function()
+            return white
+        end,
+    }
+    api.C_ClassTalents.GetHeroTalentSpecsForClassSpec = none
+    api.C_Item = {
+        GetItemCount = zero,
+        GetItemSpell = none,
+        IsUsableItem = no,
+        GetItemInfo = none,
+        GetItemInfoInstant = none,
+        GetItemCooldown = function()
+            return 0, 0, 1
+        end,
+        IsEquippedItem = no,
+        IsCurrentItem = no,
+        GetDetailedItemLevelInfo = none,
+        GetItemGem = none,
+    }
+    api.C_LossOfControl = { GetActiveLossOfControlData = none, GetActiveLossOfControlDataCount = zero }
+    api.C_PetBattles = { IsInBattle = no }
+    api.C_PvP = { IsWarModeDesired = no }
+    api.C_PlayerInfo = { IsPlayerInTimerunningHeroicWorldTier = no }
+    api.C_SpecializationInfo = {
+        GetSpecialization = function()
+            return ctl.specID and 1 or nil
+        end,
+        GetSpecializationInfo = function(i) -- Forever: one pseudo-spec per class (Constants.lua), at index 1
+            if i == 1 and ctl.specID then
+                return ctl.specID, ctl.class, "", 0, ctl.role, 1
+            end
+        end,
+        GetTalentInfo = none,
+    }
+    api.C_SpellActivationOverlay = { IsSpellOverlayed = no }
+    api.C_Texture = { GetAtlasInfo = none }
+    api.C_TooltipInfo = { GetInventoryItem = none, GetItemByID = none, GetSpellByID = none }
+    local window = { x = 1920, y = 1080 }
+    api.C_VideoOptions = {
+        GetCurrentGameWindowSize = function()
+            return window
+        end,
+    }
+    local C = api.C_Spell
+    local info = {} -- [spellID] = GetSpellInfo's table, built once
+    function C.GetSpellInfo(id)
+        local i = info[id]
+        if not i then
+            i = {
+                name = "Spell " .. tostring(id),
+                iconID = 136000,
+                spellID = id,
+                castTime = 0,
+                minRange = 0,
+                maxRange = 5,
+            }
+            info[id] = i
+        end
+        return i
+    end
+    function C.GetSpellTexture()
+        return 136000
+    end
+    function C.GetSpellDescription()
+        return ""
+    end
+    C.GetSpellCharges, C.RequestLoadSpellData, C.IsSpellPassive, C.IsSpellHelpful = none, none, no, no
+    function C.IsSpellHarmful()
+        return true
+    end
+    function C.IsSpellDataCached()
+        return true
+    end
+    function api.IsUsableSpell(id)
+        return C.IsSpellUsable(id)
+    end
+    local B = api.C_SpellBook
+    B.IsSpellInSpellBook = B.IsSpellKnown
+    B.FindSpellBookSlotForSpell = none
+    B.GetNumSpellBookSkillLines = zero
+
     -- Frames: each records its registrations; the first one made is the client's view of VirtualState's frame
     -- (`api.frame`): Fire delivers an event to its OnEvent when registered, ctl.Tick runs its OnUpdate.
     function api.CreateFrame()
diff --git a/tests/Virtual/harness/headless.lua b/tests/Virtual/harness/headless.lua
new file mode 100644
index 00000000..472f2e25
--- /dev/null
+++ b/tests/Virtual/harness/headless.lua
@@ -0,0 +1,939 @@
+-- tests/Virtual/harness/headless.lua (headless loop design §1): stock Hekili loaded headless under busted, one
+-- instance per Lua environment. Every chunk of Hekili.toc runs with setfenv( chunk, H.env ), so two instances (ours and
+-- the oracle, §4) keep their own `Hekili`, `LibStub`, frames and saved variables, and the real _G gains nothing. The
+-- client is fake_api (copied per instance, each with its own `ctl`); this file holds only load and UI scaffolding
+-- (WoW's Lua aliases, frames, C_Timer, constants), never a client answer a secret could touch (§1.2).
+-- Process-wide effect, the only one: `string.trim` and `string.split` (WoW adds them; Hekili calls `s:trim()`, which
+-- reads the one string metatable), idempotent additions to the real `string` table.
+-- Class-neutral (the boundary rule): the character (class, spec, spells, talents) comes from the content.
+local fake = require("Virtual.State.helpers.fake_api")
+
+local M = {}
+
+M.ROOT = "src/Hekili/"
+M.SETTLE = 5 -- seconds the clock runs after login before the instance is handed over
+-- The one file the loader skips, and why.
+M.SKIPPED = { ["src/Hekili/UI/PopupSlider.xml"] = "XML frames (no XML frame loader headless; not on the queue path)" }
+
+-- Reads of unset globals while the TOC loads and at login: feature probes the client also answers nil (other
+-- addons, retail- or classic-only names). A name not listed fails `H.unexpected` (§1.4): a person decides.
+M.KNOWN_LOAD_NILS = {
+    ElvUI = "another addon (Hekili skins for it when present)",
+    WeakAuras = "another addon",
+    io = "LibDeflate.lua:3453 probes the standalone Lua io library (absent in WoW)",
+    SpellFlashCore = "an optional library's host addon",
+    ChatThrottleLib = "AceComm's optional global (it embeds its own)",
+    ["LibDualSpec-1.0-35 test"] = "LibStub probes a minor version",
+    LibStub = "LibStub.lua's own `_G.LibStub` probe before it defines it",
+    HekiliDB = "no saved variables (a fresh profile)",
+    HekiliCustomEditorInsertLink = "Hekili's own probe of an optional hook",
+    AceGUIEditBoxInsertLink = "AceGUI's own probe",
+    AceGUIMultiLineEditBoxInsertLink = "AceGUI's own probe",
+    ChatEdit_InsertLink = "chat UI (not on Forever's headless client)",
+    ChatEdit_SendText = "chat UI",
+    ChatFrameUtil = "chat UI (retail)",
+    C_EventUtils = "retail-only namespace",
+    C_BattleNet = "retail-only namespace",
+    C_PaperDollInfo = "retail-only namespace",
+    BNSendGameData = "Battle.net messaging",
+    Ambiguate = "chat name helper",
+    AnimateTexCoords = "UI animation helper",
+    TextureUtil = "retail UI helper",
+    ClearCursor = "cursor UI",
+    CheckInteractDistance = "a range library's fallback probe",
+    IsSpellInRange = "a range library's legacy probe (C_Spell.IsSpellInRange answers)",
+    UnitIsVisible = "a range library's probe",
+    GetPlayerMapPosition = "a range library's legacy probe",
+    GetInventoryItemLink = "a range library's item probe",
+    GetSpellInfo = "the legacy global (C_Spell.GetSpellInfo answers)",
+    GetNumSpellTabs = "legacy spellbook API (absent on the modern client)",
+    GetSpellTabInfo = "legacy spellbook API",
+    GetSpellBookItemInfo = "legacy spellbook API",
+    GetSpellBookItemName = "legacy spellbook API",
+    BOOKTYPE_SPELL = "legacy spellbook constant",
+    LEVEL_LINKED_NOT_USABLE = "a GlobalString nothing on the queue path reads",
+    SPELL_FAILED_INCORRECT_AREA = "a GlobalString nothing on the queue path reads",
+    SPELL_FAILED_NOT_HERE = "a GlobalString nothing on the queue path reads",
+    SPELL_FAILED_NOT_IN_MAGE_TOWER = "a GlobalString nothing on the queue path reads",
+    TOOLTIP_NOT_IN_MAGE_TOWER = "a GlobalString nothing on the queue path reads",
+    TALENT_SPEC_PRIMARY = "a GlobalString nothing on the queue path reads",
+    TALENT_SPEC_SECONDARY = "a GlobalString nothing on the queue path reads",
+    LE_EXPANSION_CATACLYSM = "a classic flavour constant",
+    LE_EXPANSION_MISTS_OF_PANDARIA = "a classic flavour constant",
+    WOW_PROJECT_ID = "the flavour probes: none matches, as on Forever",
+    WOW_PROJECT_MAINLINE = "the flavour probes",
+    WOW_PROJECT_CLASSIC = "the flavour probes",
+    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = "the flavour probes",
+    WOW_PROJECT_WRATH_CLASSIC = "the flavour probes",
+    WOW_PROJECT_CATACLYSM_CLASSIC = "the flavour probes",
+    WOW_PROJECT_MISTS_CLASSIC = "the flavour probes",
+    id = "Hekili reads an unset global `id` (an upstream slip, nil in game too)",
+    squawk = "Scripts.lua:1032 reads an unset global (upstream, nil in game too)",
+}
+-- Reads of unset globals at recommendation time (upstream slips, nil in game too: SPIKE risk 10).
+M.KNOWN_RUN_NILS = {
+    overcap = "State.lua:1386",
+    id = "State.lua:3766",
+    listName = "Core.lua:1992",
+    alphaCheck = "UI.lua:1121",
+    squawk = "Scripts.lua:1032",
+    WeakAuras = "another addon's probe on the display path",
+}
+
+-- WoW's string additions, process-wide (the header's one shared effect).
+function string.trim(s) -- luacheck: ignore 122 142
+    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
+end
+local function strsplit(sep, s)
+    local out = {}
+    for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
+        out[#out + 1] = piece
+    end
+    return unpack(out)
+end
+function string.split(s, sep) -- luacheck: ignore 122 142
+    return strsplit(sep, s)
+end
+
+-- The Lua standard library the client offers, copied into each environment.
+local STD = {
+    "assert",
+    "error",
+    "ipairs",
+    "pairs",
+    "next",
+    "select",
+    "type",
+    "tostring",
+    "tonumber",
+    "rawget",
+    "rawset",
+    "rawequal",
+    "setmetatable",
+    "getmetatable",
+    "pcall",
+    "unpack",
+    "setfenv",
+    "newproxy",
+    "collectgarbage",
+    "gcinfo",
+    "string",
+    "math",
+    "os",
+    "coroutine",
+    "debug",
+    "load",
+}
+
+-- A Lua 5.1 bit library (WoW's `bit`), for the libraries that read it at load.
+local function bitop(a, b, f)
+    local r, m = 0, 1
+    while a > 0 or b > 0 do
+        if f(a % 2, b % 2) then
+            r = r + m
+        end
+        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
+    end
+    return r
+end
+local BIT = {
+    band = function(a, b)
+        return bitop(a, b, function(x, y)
+            return x == 1 and y == 1
+        end)
+    end,
+    bor = function(a, b)
+        return bitop(a, b, function(x, y)
+            return x == 1 or y == 1
+        end)
+    end,
+    lshift = function(a, n)
+        return a * 2 ^ n
+    end,
+    rshift = function(a, n)
+        return math.floor(a / 2 ^ n)
+    end,
+    bnot = function(a)
+        return -1 - a
+    end,
+}
+
+-- Stub widgets: a frame whose unknown WoW-style methods are no-ops; `Get*` answers a stub, `Is*`/`Has*` false, a short
+-- list of getters numbers; any other missing key reads nil, so Hekili's own fields on a frame behave.
+local VERBS = {
+    "Set",
+    "Get",
+    "Is",
+    "Has",
+    "Create",
+    "Register",
+    "Unregister",
+    "Enable",
+    "Disable",
+    "Show",
+    "Hide",
+    "Clear",
+    "Hook",
+    "Raise",
+    "Lower",
+    "Start",
+    "Stop",
+    "Play",
+    "Add",
+    "Lock",
+    "Unlock",
+    "Release",
+    "Adjust",
+    "Insert",
+    "Remove",
+    "Scroll",
+    "Update",
+    "Click",
+    "Refresh",
+    "Fade",
+    "Desaturate",
+    "Toggle",
+    "Restart",
+    "Finish",
+    "Pause",
+    "Can",
+    "Apply",
+    "Reset",
+    "Clip",
+    "Disconnect",
+    "Scale",
+}
+local NUM = {
+    GetWidth = 100,
+    GetHeight = 100,
+    GetScale = 1,
+    GetEffectiveScale = 1,
+    GetAlpha = 1,
+    GetLeft = 0,
+    GetRight = 0,
+    GetTop = 0,
+    GetBottom = 0,
+    GetNumPoints = 0,
+    GetFrameLevel = 1,
+    GetID = 0,
+    GetValue = 0,
+    GetNumRegions = 0,
+    GetNumChildren = 0,
+    GetStringWidth = 10,
+    GetStringHeight = 10,
+    GetCenter = 0,
+    GetEffectiveAlpha = 1,
+    GetFrameStrata = "MEDIUM",
+    GetObjectType = "Frame",
+    GetText = "",
+    GetFont = "Fonts\\FRIZQT__.TTF",
+    GetTexture = 0,
+    HasScript = true,
+}
+local function isVerb(k)
+    for _, v in ipairs(VERBS) do
+        if k:sub(1, #v) == v and (k == v or k:sub(#v + 1, #v + 1):match("%u")) then
+            return true
+        end
+    end
+end
+
+--- A new instance: Hekili loaded and logged in. `o.character` (the content's, set before login: §1.3) {
+--- class, classID, specID, level, known = { spellID... }, talents = { [spellID] = rank }, power = { type, token, max,
+--- value }, speed = { main, off }, forms = { spellID... }, form }; `o.pack` the priority to select; `o.now` the clock [1000].
+--- Returns `H = { env, api, ctl, ns, Hekili, frames, timers, misses, errors, loadErrors, prints }`.
+function M.new(o)
+    o = o or {}
+    local api, ctl = fake.new()
+    ctl.now = o.now or 1000
+    local H = { api = api, ctl = ctl, frames = {}, timers = {}, errors = {}, loadErrors = {}, prints = {} }
+    H.phase, H.misses = "load", { load = {}, login = {}, run = {} }
+    local env = {}
+    H.env = env
+    env._G = env
+    for _, k in ipairs(STD) do
+        env[k] = _G[k]
+    end
+    env.table = setmetatable({}, { __index = table })
+    -- loadstring binds the real globals in 5.1: Scripts.lua compiles the APL with it, so bind them to the instance
+    function env.loadstring(s, name)
+        local f, err = loadstring(s, name)
+        if f then
+            setfenv(f, env)
+        end
+        return f, err
+    end
+    function env.getfenv(f) -- getfenv(0) is the thread's globals: LibSharedMedia reads them
+        if f == 0 then
+            return env
+        end
+        return getfenv(type(f) == "number" and f + 1 or f or 2)
+    end
+    -- WoW's xpcall passes extra arguments to the function (AceAddon's safecall relies on it)
+    function env.xpcall(f, h, ...)
+        local n = select("#", ...)
+        if n == 0 then
+            return xpcall(f, h)
+        end
+        local args = { ... }
+        return xpcall(function()
+            return f(unpack(args, 1, n))
+        end, h)
+    end
+    -- the client: fake_api's functions, namespaces copied so an instance's writes stay its own
+    for k, v in pairs(api) do
+        if k ~= "ctl" then
+            env[k] = type(v) == "table" and setmetatable({}, { __index = v }) or v
+        end
+    end
+
+    -- WoW's Lua aliases
+    env.floor, env.ceil, env.max, env.min, env.abs = math.floor, math.ceil, math.max, math.min, math.abs
+    env.format, env.strlower, env.strupper, env.gmatch = string.format, string.lower, string.upper, string.gmatch
+    env.strsub, env.strfind, env.strmatch, env.gsub = string.sub, string.find, string.match, string.gsub
+    env.strlen, env.strrep, env.strbyte, env.strchar = string.len, string.rep, string.byte, string.char
+    env.tinsert, env.tremove, env.sort, env.tconcat = table.insert, table.remove, table.sort, table.concat
+    function env.wipe(t)
+        for k in pairs(t) do
+            t[k] = nil
+        end
+        return t
+    end
+    env.table.wipe = env.wipe
+    env.strtrim, env.strsplit = string.trim, strsplit
+    function env.strjoin(sep, ...)
+        return table.concat({ ... }, sep)
+    end
+    function env.tostringall(...)
+        local n, t = select("#", ...), { ... }
+        for i = 1, n do
+            t[i] = tostring(t[i])
+        end
+        return unpack(t, 1, n)
+    end
+    function env.tContains(t, v)
+        for _, x in pairs(t) do
+            if x == v then
+                return true
+            end
+        end
+        return false
+    end
+    env.date, env.time, env.bit = os.date, os.time, BIT
+    -- wall clock for Hekili's frame budget only; the loop calls Update directly and never reaches it (§1.3)
+    function env.debugprofilestop()
+        return os.clock() * 1000
+    end
+    function env.debugstack()
+        return debug.traceback("", 2)
+    end
+    function env.geterrorhandler()
+        return function(e)
+            H.errors[#H.errors + 1] = tostring(e)
+        end
+    end
+    env.seterrorhandler = function() end
+    function env.securecall(f, ...)
+        return pcall(f, ...)
+    end
+    function env.securecallfunction(f, ...)
+        return f(...)
+    end
+    function env.hooksecurefunc(a, b, c)
+        local t, name, hook = a, b, c
+        if type(a) == "string" then
+            t, name, hook = env, a, b
+        end
+        local orig = t[name]
+        t[name] = function(...)
+            local r = { orig(...) }
+            hook(...)
+            return unpack(r)
+        end
+    end
+    function env.print(...)
+        H.prints[#H.prints + 1] = table.concat({ env.tostringall(...) }, " ")
+    end
+    function env.issecurevariable()
+        return true
+    end
+    function env.Mixin(t, ...)
+        for i = 1, select("#", ...) do
+            for k, v in pairs((select(i, ...))) do
+                t[k] = v
+            end
+        end
+        return t
+    end
+    function env.CreateFromMixins(...)
+        return env.Mixin({}, ...)
+    end
+
+    -- stub widgets and frames (real event registration and scripts)
+    local stubMT, methods = {}, {}
+    local function stub(name)
+        return setmetatable({ __stub = name or "?" }, stubMT)
+    end
+    local function frame(kind, name, parent)
+        local f = stub(kind)
+        rawset(f, "__name", name)
+        rawset(f, "__parent", parent)
+        rawset(f, "__events", {})
+        rawset(f, "__scripts", {})
+        if name then
+            env[name] = f
+        end
+        H.frames[#H.frames + 1] = f
+        return f
+    end
+    H.stub, H.CreateFrame = stub, frame
+    stubMT.__index = function(_, k)
+        if type(k) ~= "string" then
+            return nil
+        end
+        local m = methods[k]
+        if m then
+            return m
+        end
+        if NUM[k] ~= nil then
+            local v = NUM[k]
+            m = function()
+                return v
+            end
+        elseif k:match("^Is") or k:match("^Has") then
+            m = function()
+                return false
+            end
+        elseif k:match("^Get") then
+            m = function()
+                return stub(k)
+            end
+        elseif k:match("^Create") then
+            m = function(self, name)
+                return frame("Region", type(name) == "string" and name or nil, self)
+            end
+        elseif isVerb(k) then
+            m = function(self)
+                return self
+            end
+        else
+            return nil
+        end
+        methods[k] = m
+        return m
+    end
+    function methods.GetSize()
+        return 100, 100
+    end
+    function methods.GetPoint()
+        return "CENTER", nil, "CENTER", 0, 0
+    end
+    function methods.GetTextColor()
+        return 1, 1, 1, 1
+    end
+    methods.GetVertexColor = methods.GetTextColor
+    function methods.GetTexCoord()
+        return 0, 1, 0, 1
+    end
+    function methods.GetName(self)
+        return rawget(self, "__name")
+    end
+    function methods.GetParent(self)
+        return rawget(self, "__parent")
+    end
+    methods.GetChildren, methods.GetRegions, methods.GetAttribute, methods.GetScript = nil, nil, nil, nil
+    function methods.RegisterEvent(self, e)
+        self.__events[e] = true
+        return true
+    end
+    methods.RegisterUnitEvent = methods.RegisterEvent
+    function methods.UnregisterEvent(self, e)
+        self.__events[e] = nil
+    end
+    function methods.UnregisterAllEvents(self)
+        env.wipe(self.__events)
+    end
+    function methods.IsEventRegistered(self, e)
+        return self.__events[e] == true
+    end
+    function methods.SetScript(self, s, fn)
+        self.__scripts[s] = fn
+    end
+    function methods.HookScript(self, s, fn)
+        local old = self.__scripts[s]
+        self.__scripts[s] = old and function(...)
+            old(...)
+            fn(...)
+        end or fn
+    end
+    function methods.GetScript(self, s)
+        return self.__scripts[s]
+    end
+    env.CreateFrame = frame
+
+    --- Delivers `event` to every frame that registered it (the client's dispatch); ctl.Fire is this.
+    function H.Fire(event, ...)
+        for _, f in ipairs(H.frames) do
+            local fn = rawget(f, "__events") and f.__events[event] and f.__scripts.OnEvent
+            if fn then
+                fn(f, event, ...)
+            end
+        end
+    end
+    ctl.Fire = H.Fire
+
+    -- C_Timer on the fake clock: callbacks by due time, run by H.RunTimers(now)
+    local seq = 0
+    local function addTimer(d, fn, iter)
+        seq = seq + 1
+        local t = { at = ctl.now + d, fn = fn, d = d, iter = iter, seq = seq }
+        function t.Cancel(self)
+            self.cancelled = true
+        end
+        function t.IsCancelled(self)
+            return self.cancelled
+        end
+        H.timers[#H.timers + 1] = t
+        return t
+    end
+    env.C_Timer = {
+        After = function(d, fn)
+            addTimer(d, fn, 1)
+        end,
+        NewTimer = function(d, fn)
+            return addTimer(d, fn, 1)
+        end,
+        NewTicker = function(d, fn, n)
+            return addTimer(d, fn, n or math.huge)
+        end,
+    }
+    --- Runs every timer due at or before `now`, in due order (a raise is recorded in H.errors).
+    function H.RunTimers(now)
+        local ran = true
+        while ran do
+            ran = false
+            for i, t in ipairs(H.timers) do
+                if t.cancelled then
+                    table.remove(H.timers, i)
+                    ran = true
+                    break
+                elseif t.at <= now then
+                    t.iter = t.iter - 1
+                    if t.iter <= 0 then
+                        table.remove(H.timers, i)
+                    else
+                        t.at = t.at + t.d
+                    end
+                    local ok, err = pcall(t.fn, t)
+                    if not ok then
+                        H.errors[#H.errors + 1] = "timer: " .. tostring(err)
+                    end
+                    ran = true
+                    break
+                end
+            end
+        end
+    end
+
+    -- Hekili's and the libraries' load reads: constants, UI globals, item and spell loaders
+    env.Item = {
+        CreateFromItemID = function(_, id)
+            return {
+                IsItemEmpty = function()
+                    return false
+                end,
+                ContinueOnItemLoad = function(_, fn)
+                    fn(true)
+                end,
+                GetItemName = function()
+                    return "Item " .. id
+                end,
+                GetItemLink = function()
+                    return "[Item " .. id .. "]"
+                end,
+                GetItemIcon = function()
+                    return 0
+                end,
+                GetItemID = function()
+                    return id
+                end,
+            }
+        end,
+    }
+    env.Spell = {
+        CreateFromSpellID = function()
+            return {
+                IsSpellEmpty = function()
+                    return false
+                end,
+                ContinueOnSpellLoad = function(_, fn)
+                    fn(true)
+                end,
+            }
+        end,
+    }
+    -- Enum: the power types; any other Enum table answers a fresh number per key (enough at load)
+    local function anyNumber()
+        local n = 100
+        return setmetatable({}, {
+            __index = function(t, k)
+                n = n + 1
+                rawset(t, k, n)
+                return n
+            end,
+        })
+    end
+    env.Enum = setmetatable({
+        PowerType = {
+            HealthCost = -2,
+            None = -1,
+            Mana = 0,
+            Rage = 1,
+            Focus = 2,
+            Energy = 3,
+            ComboPoints = 4,
+            Runes = 5,
+            RunicPower = 6,
+            SoulShards = 7,
+            LunarPower = 8,
+            HolyPower = 9,
+            Alternate = 10,
+            Maelstrom = 11,
+            Chi = 12,
+            Insanity = 13,
+            Obsolete = 14,
+            Obsolete2 = 15,
+            ArcaneCharges = 16,
+            Fury = 17,
+            Pain = 18,
+            Essence = 19,
+        },
+    }, {
+        __index = function(t, k)
+            local v = anyNumber()
+            rawset(t, k, v)
+            return v
+        end,
+    })
+    for _, s in ipairs({
+        "ACCEPT",
+        "CANCEL",
+        "OKAY",
+        "NONE",
+        "YES",
+        "NO",
+        "CLOSE",
+        "DEFAULT",
+        "INVTYPE_WEAPONMAINHAND",
+        "BATTLE_PET_NAME_4",
+        "PET_TYPE_DEMON",
+        "ITEM_SPELL_TRIGGER_ONEQUIP",
+        "KEY_BUTTON1",
+        "KEY_BUTTON2",
+        "NOT_BOUND",
+        "RESET",
+        "SAVE",
+    }) do
+        env[s] = s
+    end
+    local function self(_, k)
+        return k
+    end
+    env.LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = self })
+    env.LOCALIZED_CLASS_NAMES_FEMALE = env.LOCALIZED_CLASS_NAMES_MALE
+    env.RAID_CLASS_COLORS = setmetatable({}, {
+        __index = function()
+            return { r = 1, g = 1, b = 1, colorStr = "ffffffff" }
+        end,
+    })
+    env.MAX_PLAYER_LEVEL, env.INVSLOT_LAST_EQUIPPED, env.TOOLTIP_UPDATE_TIME = 60, 19, 0.2
+    env.COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x10
+    env.NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
+    env.BackdropTemplateMixin = {}
+    env.UIParent = frame("Frame", "UIParent")
+    env.GameTooltip = frame("GameTooltip", "GameTooltip")
+    env.DEFAULT_CHAT_FRAME = frame("Frame", "DEFAULT_CHAT_FRAME")
+    env.Minimap = frame("Minimap", "Minimap")
+    env.ChatFontNormal = stub("Font")
+    for _, f in ipairs({
+        "GameFontNormal",
+        "GameFontHighlight",
+        "GameFontHighlightSmall",
+        "GameFontNormalSmall",
+        "GameFontNormalLarge",
+        "GameFontHighlightLarge",
+        "GameFontDisable",
+        "GameFontDisableSmall",
+        "ChatFontSmall",
+        "GameFontHighlightMedium",
+        "GameFontNormalHuge",
+        "NumberFontNormal",
+        "SystemFont_Shadow_Med1",
+    }) do
+        env[f] = stub(f)
+    end
+    env.PixelUtil = setmetatable({ -- numbers, not stubs (UI.lua:121)
+        GetNearestPixelSize = function(x)
+            return x
+        end,
+        GetPixelToUIUnitFactor = function()
+            return 1
+        end,
+    }, {
+        __index = function()
+            return function() end
+        end,
+    })
+    env.AddonCompartmentFrame = stub("AddonCompartmentFrame")
+    env.Settings = stub("Settings")
+    env.SlashCmdList, env.hash_SlashCmdList, env.UISpecialFrames, env.StaticPopupDialogs = {}, {}, {}, {}
+    local noop = function() end
+    for _, k in ipairs({
+        "InterfaceOptions_AddCategory",
+        "UIDropDownMenu_AddButton",
+        "UIDropDownMenu_AddSeparator",
+        "UIDropDownMenu_SetDisplayMode",
+        "ToggleDropDownMenu",
+        "UIFrameFadeOut",
+        "GameTooltip_SetTitle",
+        "GameTooltip_AddNormalLine",
+        "ChatFrame_AddMessageEventFilter",
+        "PlaySound",
+        "GetMouseFocus",
+        "RegisterAddonMessagePrefix",
+        "SendChatMessage",
+        "SetCVar",
+        "ClearOverrideBindings",
+        "SetOverrideBindingClick",
+    }) do
+        env[k] = noop
+    end
+    function env.CreateAtlasMarkup()
+        return ""
+    end
+    function env.GetAppropriateTooltip()
+        return env.GameTooltip
+    end
+    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
+    function env.GetScreenWidth()
+        return 1920
+    end
+    function env.GetScreenHeight()
+        return 1080
+    end
+    local function no()
+        return false
+    end
+    env.IsShiftKeyDown, env.IsControlKeyDown, env.IsAltKeyDown = no, no, no
+    function env.CreateColor(r, g, b, a)
+        return {
+            r = r,
+            g = g,
+            b = b,
+            a = a,
+            GetRGBA = function(c)
+                return c.r, c.g, c.b, c.a
+            end,
+        }
+    end
+    env.SOUNDKIT = setmetatable({}, {
+        __index = function()
+            return 0
+        end,
+    })
+    env.C_ChatInfo = { RegisterAddonMessagePrefix = noop, SendAddonMessage = noop }
+    function env.GetChannelName()
+        return 0
+    end
+    env.FONT_COLOR_CODE_CLOSE, env.HIGHLIGHT_FONT_COLOR_CODE, env.NORMAL_FONT_COLOR_CODE =
+        "|r", "|cffffffff", "|cffffd100"
+    -- library reads at load
+    function env.GetCurrentRegion()
+        return 1
+    end
+    env.C_UIFileAsset = {
+        IsKnownFile = function()
+            return true
+        end,
+    }
+    function env.GetInventorySlotInfo()
+        return 1
+    end
+    function env.GetMinimapShape()
+        return "ROUND"
+    end
+    function env.ClassicExpansionAtLeast()
+        return false
+    end
+    env.ClassicExpansionAtMost = env.ClassicExpansionAtLeast
+    env.LE_EXPANSION_SHADOWLANDS, env.LE_EXPANSION_CLASSIC, env.LE_EXPANSION_LEVEL_CURRENT = 8, 0, 0
+    function env.GetNumSpecGroups()
+        return 1
+    end
+    env.GetActiveSpecGroup = env.GetNumSpecGroups
+    local function pool()
+        return {
+            Acquire = function()
+                return frame("Region")
+            end,
+            Release = noop,
+            ReleaseAll = noop,
+            EnumerateActive = function()
+                return noop
+            end,
+        }
+    end
+    env.CreateTexturePool, env.CreateFramePool, env.CreateObjectPool, env.CreateFontStringPool = pool, pool, pool, pool
+    local loggedIn = false
+    function env.IsLoggedIn()
+        return loggedIn
+    end
+
+    -- the miss counter: every read of a name nobody defined, by phase (§1.4)
+    setmetatable(env, {
+        __index = function(_, k)
+            local t = H.misses[H.phase]
+            t[k] = (t[k] or 0) + 1
+            return nil
+        end,
+    })
+
+    -- the loader: Hekili.toc in order, an .xml line's Script/Include tags; a raising file is recorded, the load goes on
+    local ns = {}
+    H.ns = ns
+    local function loadLua(path)
+        local f, err = loadfile(path)
+        if not f then
+            H.loadErrors[#H.loadErrors + 1] = path .. ": " .. tostring(err)
+            return
+        end
+        setfenv(f, env)
+        local ok, e = xpcall(function()
+            return f("Hekili", ns)
+        end, debug.traceback)
+        if not ok then
+            H.loadErrors[#H.loadErrors + 1] = path .. ": " .. tostring(e)
+        end
+    end
+    local function loadXml(path)
+        local fh = io.open(path)
+        if not fh then
+            H.loadErrors[#H.loadErrors + 1] = path .. ": missing"
+            return
+        end
+        local body = fh:read("*a"):gsub("<!%-%-.-%-%->", "")
+        fh:close()
+        local dir = path:match("^(.*/)") or ""
+        for tag, file in body:gmatch('<(%a+)%s+file%s*=%s*"([^"]+)"') do
+            local p = dir .. file:gsub("\\", "/")
+            if tag == "Script" then
+                loadLua(p)
+            elseif tag == "Include" then
+                loadXml(p)
+            end
+        end
+        if not M.SKIPPED[path] and (body:match("<Frame") or body:match("<Button") or body:match("<Slider")) then
+            H.loadErrors[#H.loadErrors + 1] = path .. ": XML frames not loaded"
+        end
+    end
+
+    local c = o.character
+    if c then -- the character, before login: VirtualState builds its spellbook at SpecializationChanged
+        ctl.class, ctl.classID, ctl.specID = c.class, c.classID or 0, c.specID
+        ctl.level.player = c.level
+        for _, id in ipairs(c.known or {}) do
+            ctl.known[id] = true
+        end
+        if c.talents then
+            local tr = { config = 1, trees = { 1 }, nodeIDs = {}, nodes = {}, defs = {} }
+            for spell, rank in pairs(c.talents) do
+                local n = #tr.nodeIDs + 1
+                tr.nodeIDs[n], tr.nodes[n], tr.defs[n] = n, { entryIDs = { n }, activeRank = rank }, spell
+            end
+            ctl.traits = tr
+        end
+        local p = c.power
+        if p then
+            ctl.powerType[1], ctl.powerType[2] = p.type, p.token
+            ctl.powerMax[p.type], ctl.power[p.type] = p.max, p.value or 0
+        end
+        if c.speed then
+            ctl.speed = c.speed
+        end
+        for i, id in ipairs(c.forms or {}) do
+            ctl.forms[i] = id
+        end
+        ctl.form = c.form or 0
+    end
+    for line in io.lines(M.ROOT .. "Hekili.toc") do
+        line = line:gsub("\r", ""):gsub("%s+$", "")
+        if line ~= "" and not line:match("^##") then
+            local p = M.ROOT .. line:gsub("\\", "/")
+            if p:match("%.xml$") then
+                loadXml(p)
+            else
+                loadLua(p)
+            end
+        end
+    end
+
+    -- login: ADDON_LOADED (OnInitialize, the AceDB profile), PLAYER_LOGIN (OnEnable, VS.Start), PLAYER_ENTERING_WORLD
+    H.phase = "login"
+    local ok, err = xpcall(function()
+        H.Fire("ADDON_LOADED", "Hekili")
+        loggedIn = true
+        H.Fire("PLAYER_LOGIN")
+        H.Fire("PLAYER_ENTERING_WORLD", true, false)
+    end, debug.traceback)
+    if not ok then
+        H.loadErrors[#H.loadErrors + 1] = "login: " .. tostring(err)
+    end
+    -- the seconds after login: the display visibility (UI.lua:2102, +3 s) and the spec's pack review (+5 s) run
+    ctl.now = ctl.now + M.SETTLE
+    H.RunTimers(ctl.now)
+    H.Hekili = rawget(env, "Hekili")
+    local hk = H.Hekili
+    if hk then
+        local onError = hk.Error -- Hekili:Error, counted (the engine-health metric)
+        function hk.Error(s, ...)
+            H.errors[#H.errors + 1] = tostring((...))
+            return onError(s, ...)
+        end
+        if o.pack and ctl.specID then
+            rawget(hk.DB.profile.specs, ctl.specID).package = o.pack
+        end
+    end
+    H.phase = "run"
+    return H
+end
+
+--- The names `H` read in `phase` that the phase's list does not hold (load and login: KNOWN_LOAD_NILS; run:
+--- KNOWN_RUN_NILS), sorted.
+function M.unexpected(H, phase)
+    local known = phase == "run" and M.KNOWN_RUN_NILS or M.KNOWN_LOAD_NILS
+    local out = {}
+    for k in pairs(H.misses[phase]) do
+        if not known[k] then
+            out[#out + 1] = tostring(k)
+        end
+    end
+    table.sort(out)
+    return out
+end
+
+--- One display cycle at `t`: the clock, the VirtualState frame's OnUpdate (the staged flush), the due timers, then
+--- Hekili.Update() called directly (never the wall-clock budgeted frame update: §2.2). Returns false and the error
+--- when Update raised.
+function M.cycle(H, t)
+    local ctl = H.ctl
+    ctl.now = t
+    local f = H.ns.VirtualStateInternal.Events.frame
+    local u = f and f.__scripts.OnUpdate
+    if u then
+        u(f, 0.1)
+    end
+    H.RunTimers(t)
+    return xpcall(H.Hekili.Update, debug.traceback)
+end
+
+return M
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `572 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 131 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      572 successes / 0 failures / 0 errors / 0 pending (about 91 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili tests/Virtual tools docs/dev | grep '^+' | grep -v 'Fury = 17' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|arms|fury|protection|stance|stances|sunder|sunder_armor|overpower|execute|heroic|heroic_strike|bloodrage|charge|whirlwind|rend|cleave|hamstring|slam|recklessness|intercept|pummel|mortal_strike|battle_shout|demoralizing_shout|victory_rush|thunder_clap|battle_stance|berserker_stance|defensive_stance|undead'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/State.lua tests/Forever/helpers/warrior_world.lua tests/Forever/loop_warrior_spec.lua \
  tests/Virtual/State/helpers/fake_api.lua tests/Virtual/harness/headless.lua tests/Virtual/harness/headless_spec.lua
git commit -m "test(headless): stock Hekili headless under busted, one instance per environment (headless loop design §1); fake_api answers the facade's client rows and UnitIsUnit(a, a); the dead safeAbs read removed (§6)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin headless-loop`

---
### Task 2: The incremental observer; the observation draws in the behaviour; the harness gates re-measured

Spec §2.1.1 (incremental observer), §2.1.2 (no RNG in observation), §2.1.3 (usability from the content), §9's observer_spec cases and "H's gate specs re-run at their bounds"; Deviations 5-6.

**Files:**
- Modify: `tests/Virtual/harness/observer.lua` (`observer.new(W, k)` with `obs.step(tEnd)` and `obs.s`; `observe` = new + `step(math.huge)`; `k.usable` true or the content's `{ { spellID, fn(W, us, power) } }`, evaluated at each power change and at each step's end; a stable sort on (time, sequence); `prepull` reads; `ev.sameMs` and `ev.order` read, never rolled), `behaviours.lua` (the same-ms avoid and our strike frame's order rolled from `W.crng` and recorded on the truth event), `world.lua` (`W.crng`; `prepull` carries the targets and the cache), `scenarios.lua` (a `prepull` event at pull - 0.5; `sameMs` passed to our melee), `drive.lua` (`drive.op` exported), `docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md` (§9: a row for the observation draws; the gate tables re-measured)
- Test: `tests/Virtual/harness/observer_spec.lua` (the strike case reads the rolled order: "fires a queued strike's frame: our swing, a WOUND 0 and our success in its rolled order, its wound 1 ms later"; the same-ms case runs the melee behaviour: "fires the avoid our swing rolled in its ms (at its share), and lands our hands at their lags"; the cache and aura cases emit `prepull`; new: "steps to the batch's stream in 0.2 s steps, and draws nothing from the world's generator", "answers the content's usability: a power answer a delay after the gain, a world answer at the step's end")

**Interfaces:**
- Consumes: Task 1's tree (no Task 1 symbol: this task is the harness core alone).
- Produces: `observer.new(W, k)` -> `obs` { `s` (the stream, growing), `step(tEnd)` -> first, last }; `observer.observe(W, k)` unchanged in shape; truth event kind `prepull` (with `targets`, `damage`); truth fields `ev.sameMs`, `ev.order`; `W.crng`; `behaviours.melee`'s `p.sameMs`; `drive.op(c, ctl, ev, a1, a2, a3, a4)`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/harness/observer_spec.lua b/tests/Virtual/harness/observer_spec.lua
index 58862201..64dda065 100644
--- a/tests/Virtual/harness/observer_spec.lua
+++ b/tests/Virtual/harness/observer_spec.lua
@@ -2,6 +2,8 @@
 local world = require("Virtual.harness.world")
 local entities = require("Virtual.harness.entities")
 local observer = require("Virtual.harness.observer")
+local behaviours = require("Virtual.harness.behaviours")
+local scenarios = require("Virtual.harness.scenarios")
 local fake = require("Virtual.State.helpers.fake_api")
 
 describe("the observer", function()
@@ -54,7 +56,7 @@ describe("the observer", function()
             school = 1,
             swing = sw,
         })
-        local s = observer.observe(W, setmetatable({ sameMs = 0 }, { __index = observer.DEFAULTS }))
+        local s = observer.observe(W)
         assert.are.same({
             { 5, "PLAYER_SWING", 2.5, 1, nil, nil, nil, 0 },
             { 5.7, "UNIT_COMBAT", "nameplate1", "WOUND", "", 30, 1, 1 },
@@ -125,12 +127,11 @@ describe("the observer", function()
     end)
 
     it(
-        "fires a queued strike's frame: our swing, a WOUND 0 and our success in either order, its wound 1 ms later",
+        "fires a queued strike's frame: our swing, a WOUND 0 and our success in its rolled order, its wound 1 ms later",
         function()
             local orders = {}
-            for seed = 1, 8 do
+            for order = 1, 2 do
                 setup()
-                W.rng = require("Virtual.harness.rng").new(seed)
                 W.emit({
                     t = 6,
                     kind = "strike",
@@ -143,18 +144,19 @@ describe("the observer", function()
                     school = 1,
                     spell = "STRIKE",
                     speed = 2.2,
+                    order = order, -- the behaviour's roll
                 })
                 local got = events(observer.observe(W))
                 local o = {}
                 for _, e in ipairs(got) do
                     o[#o + 1] = e[2] == "UNIT_COMBAT" and (e[3] .. e[6]) or e[2]
                 end
-                orders[table.concat(o, " ")] = true
+                orders[order] = table.concat(o, " ")
                 assert.are.same({ 6.001, "target", 80, 1 }, { got[#got][1], got[#got][3], got[#got][6], got[#got][8] })
             end
             assert.are.same({
-                ["PLAYER_SWING nameplate10 target0 UNIT_SPELLCAST_SUCCEEDED nameplate180 target80"] = true,
-                ["UNIT_SPELLCAST_SUCCEEDED nameplate10 target0 PLAYER_SWING nameplate180 target80"] = true,
+                "UNIT_SPELLCAST_SUCCEEDED nameplate10 target0 PLAYER_SWING nameplate180 target80",
+                "PLAYER_SWING nameplate10 target0 UNIT_SPELLCAST_SUCCEEDED nameplate180 target80",
             }, orders)
         end
     )
@@ -189,13 +191,27 @@ describe("the observer", function()
         assert.are.equal(7.002, got[4][1])
     end)
 
-    it("adds an unexplained avoid in the swing event's ms at its share, and lands our hands at their lags", function()
+    it("fires the avoid our swing rolled in its ms (at its share), and lands our hands at their lags", function()
         setup()
-        local lag, sameMs, swings = observer.lag(), 0, 3000
-        local main, own, mref = {}, 0, 0
-        us.lastSwing, us.landAt = { 0, 0 }, { 0, 0 }
-        for k = 1, swings / 2 do -- a main swing, then an off swing 0.3 s later
-            local t = k * 2.5
+        mob.health = 1e9
+        behaviours.melee({ land = observer.lag(), sameMs = observer.DEFAULTS.sameMs })(W, us)
+        W.run(3600)
+        local rolled, swings, sameMs = 0, 0, 0
+        for _, ev in ipairs(W.truth) do
+            if ev.kind == "swing" then
+                swings, rolled = swings + 1, rolled + (ev.sameMs and 1 or 0)
+            end
+        end
+        local s = observer.observe(W)
+        for i = 1, s.n do
+            sameMs = sameMs + (s.src[i] == 3 and s.a1[i] == "target" and 1 or 0)
+        end
+        assert.are.equal(rolled, sameMs)
+        assert.is_true(math.abs(sameMs / swings - 3 / 87) < 0.01, "same-ms share " .. sameMs / swings)
+        local lag, main, own, mref = observer.lag(), {}, 0, 0
+        local n = 1500
+        for k = 1, n do -- a main swing, then an off swing 0.3 s later
+            local t = 4000 + k * 2.5
             local d = lag(W, us, 1, t)
             us.lastSwing[1], us.landAt[1], main[#main + 1] = t, t + d, d
             d = lag(W, us, 2, t + 0.3)
@@ -204,27 +220,11 @@ describe("the observer", function()
             elseif math.abs(0.3 + d - 1.686) < 0.03 then
                 mref = mref + 1
             end
-            for h = 1, 2 do
-                W.emit({
-                    t = t + 0.3 * (h - 1),
-                    kind = "swing",
-                    src = us,
-                    dst = mob,
-                    hand = h,
-                    act = "MISS",
-                    speed = 2.5,
-                })
-            end
         end
-        local s = observer.observe(W)
-        for i = 1, s.n do
-            sameMs = sameMs + (s.src[i] == 3 and s.a1[i] == "target" and 1 or 0)
-        end
-        assert.is_true(math.abs(sameMs / swings - 3 / 87) < 0.01, "same-ms share " .. sameMs / swings)
         table.sort(main)
-        assert.is_true(math.abs(main[#main / 2] - 0.474) < 0.01, "main median " .. main[#main / 2])
-        assert.is_true(math.abs(own / (swings / 2) - observer.DEFAULTS.off.pOwn) < 0.05, "off own share")
-        assert.is_true(math.abs(mref / (swings / 2) - observer.DEFAULTS.off.pMain) < 0.05, "off main-reference share")
+        assert.is_true(math.abs(main[n / 2] - 0.474) < 0.01, "main median " .. main[n / 2])
+        assert.is_true(math.abs(own / n - observer.DEFAULTS.off.pOwn) < 0.05, "off own share")
+        assert.is_true(math.abs(mref / n - observer.DEFAULTS.off.pMain) < 0.05, "off main-reference share")
     end)
 
     it("answers usability from our true power: a gain flips it a knob's delay later, our spend at once", function()
@@ -255,6 +255,7 @@ describe("the observer", function()
         "reads the weapon damage cache out of combat only: before the pull and at the stop, not at a form change",
         function()
             setup()
+            W.emit({ t = 1.5, kind = "prepull" })
             W.emit({ t = 2, kind = "pull" })
             us.dmgMult = 1.2 -- a damage buff in combat: no read until the stop
             W.emit({ t = 3, kind = "form", form = 1 })
@@ -275,6 +276,7 @@ describe("the observer", function()
 
     it("makes the target's auras raise in combat, and answers UnitIsUnit secret under its knob", function()
         setup()
+        W.emit({ t = 1.5, kind = "prepull" })
         W.emit({ t = 2, kind = "pull" })
         W.emit({ t = 9, kind = "stop" })
         local k = setmetatable({ secretUnitIs = true }, { __index = observer.DEFAULTS })
@@ -290,6 +292,71 @@ describe("the observer", function()
         assert.are.same({ { 2, "target", true }, { 9, "target", false } }, aura)
         assert.is_true(rawequal(fake.SECRET, unitIs))
     end)
+
+    it("steps to the batch's stream in 0.2 s steps, and draws nothing from the world's generator", function()
+        local o = scenarios.oracle({ duration = 40, others = { "melee", "caster" } })
+        local k = setmetatable({ usable = true }, { __index = observer.DEFAULTS })
+        local batch = observer.observe(scenarios.build(o, 3), k)
+        local W2 = scenarios.build(o, 3)
+        local obs = observer.new(W2, k)
+        local steps = 0
+        for t = 0, 50, 0.2 do
+            local first, last = obs.step(t)
+            assert.is_true(last >= first - 1)
+            steps = steps + 1
+        end
+        obs.step(math.huge)
+        for _, f in ipairs({ "t", "ev", "a1", "a2", "a3", "a4", "a5", "src", "hand", "swingT", "actor" }) do
+            for i = 1, batch.n do
+                assert.is_true(rawequal(batch[f][i], obs.s[f][i]), f .. " " .. i)
+            end
+        end
+        assert.are.equal(batch.n, obs.s.n)
+        local W3 = scenarios.build(o, 3) -- the same world, never observed
+        assert.are.equal(W3.rng.next(), W2.rng.next())
+    end)
+
+    it(
+        "answers the content's usability: a power answer a delay after the gain, a world answer at the step's end",
+        function()
+            setup()
+            mob.health = 1000
+            local k = setmetatable({
+                usable = {
+                    {
+                        101,
+                        function(_, _, p)
+                            return p >= 10
+                        end,
+                    },
+                    {
+                        102,
+                        function(_, e)
+                            return e.target.health < 200
+                        end,
+                    },
+                },
+            }, { __index = observer.DEFAULTS })
+            local obs = observer.new(W, k)
+            local land = { t = 4, kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", flag = "", amount = 40 }
+            land.school, land.swing, land.rage = 1, { t = 3.5 }, 12
+            W.emit(land)
+            local got = {}
+            local function step(t)
+                local first, last = obs.step(t)
+                for i = first, last do
+                    if obs.s.ev[i] == "@usable" and obs.s.t[i] > 0 then
+                        got[#got + 1] = { t, obs.s.t[i], obs.s.a1[i], obs.s.a2[i] }
+                    end
+                end
+            end
+            step(4.0)
+            step(4.2)
+            W.emit({ t = 6, kind = "spell", src = W.ents[2], dst = mob, act = "WOUND", flag = "", amount = 900 })
+            step(6.2)
+            assert.are.same({ { 4.2, 4.1, 101, 1 }, { 6.2, 6.2, 102, 1 } }, got)
+        end
+    )
 end)
 
 describe("the world", function()
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `570 successes / 2 failures / 2 errors / 0 pending`.
- observer_spec's two new cases error (`attempt to call field 'new' (a nil value)`); the strike-order and same-ms cases fail (the old observer rolls both itself and ignores `ev.order` and `ev.sameMs`). The cache and aura cases pass either way (the old `pull` read the same times).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md b/docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md
index 6331182a..5caf4e6a 100644
--- a/docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md
+++ b/docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md
@@ -455,29 +455,31 @@ task's review round.
 | Solo rescue gate (§3.4) | precision | "one miss" (<= 1 wrong rescue) | Deviation 10 |
 | Fixtures (§3.1) | logs 1-3 | logs 1, 2, 3 and 5 (G5); `tools/vslog_fixture.lua` turns a dump into one | Task 5 |
 | RNG (§3.2) | seeded | Park-Miller minimal standard (48271, 2^31 - 1), not xorshift | Task 1 |
+| Observation draws (§3.1) | the observer rolls the same-ms avoid and the strike frame's order | the melee behaviour rolls both from the world's second generator `W.crng` (seed + 7919) and records them on the truth event (`sameMs`, `order`); the observer draws nothing, so its incremental and batch streams are equal | headless loop plan, Task 2 |
 | Attackers, rule 2 (§4.2) | the band that holds it | only when every candidate's band is known, one holds it and more than one hostile is on us; with one, the lone rule credits it and its band learns | T4, Task 5 |
 | Attackers, joiner (§4.1) | - | a joining attacker without a band is found by elimination (every known band excludes the wound) | Task 4 |
 | Same strength (§4.3, §3.4) | precision >= 0.90 | from the pull: `credited == 0` (equal bands never separate); different strength from the pull is never attributed either (T4 #5, open) | T4 |
 | Runtime (D4) | about 1 min | `make check` about 108 s (busted about 95 s); `make test-fast` about 11 s skips the `#slow` gates | final review |
 
-Final gates (deterministic seeds; Task 3 round 2 and Task 4, unchanged at 915b2ca3). Hit rates main / off; false
+Final gates (deterministic seeds; re-measured at the same bounds after the observation draws moved into the
+behaviour, headless loop plan Task 2). Hit rates main / off; false
 wounds and avoids per 100 swings; overshoot from the run without answers.
 
 | Gate | Hit rates | Wrong | False wounds, gross | False wounds, net | False avoids | Overshoot |
 |---|---|---|---|---|---|---|
-| solo, 200 fights | .992 / .989 | 26 / 8 | 0 | 0 | 0.10 | 0 |
-| buff, 100 fights | .897 / .944 | 38 / 80 | 0 | 0 | 0.16 | not gated |
-| form, 100 fights | .966 / .967 | 81 / 61 (2.5% / 2.1%) | 0 | 0 | 0.10 | not gated |
-| party, 100 fights | .831 / .979 | 0 / 7 | 1.76 (<= 2.76) | 1.16 (<= 4) | 0.33 | 22/1200 |
-| party+pet, 100 fights | .774 / .899 | 0 / 1 | 6.35 (<= 7.33) | 5.12 (<= 6) | 0.82 | 47/1200 |
+| solo, 200 fights | .991 / .989 | 26 / 8 | 0 | 0 | 0.08 | 0 |
+| buff, 100 fights | .897 / .944 | 38 / 79 | 0 | 0 | 0.18 | not gated |
+| form, 100 fights | .965 / .966 | 82 / 61 (2.6% / 2.1%) | 0 | 0 | 0.09 | not gated |
+| party, 100 fights | .831 / .979 | 0 / 7 | 1.76 (<= 2.76) | 1.16 (<= 4) | 0.36 | 22/1200 |
+| party+pet, 100 fights | .774 / .898 | 0 / 1 | 6.35 (<= 7.33) | 5.12 (<= 6) | 0.81 | 47/1200 |
 
 | Oracle | Judged | False credits caught | False retractions | Rescues that were ours | Danger |
 |---|---|---|---|---|---|
-| solo | 5548 | none judged | 1 of 15847 | 1 of 2 | 0 |
-| buff | 1890 | none judged | 0 | 44 of 51 | 0 |
+| solo | 5554 | none judged | 1 of 15844 | 1 of 2 | 0 |
+| buff | 1888 | none judged | 0 | 43 of 50 | 0 |
 | form | 1953 | none judged | 0 | 1 of 1 | 0 |
-| party | 2614 | 61 of 82, 74% | 8 of 7225 | 138 of 148, 93.2% (gate 90%) | 0 |
-| party+pet | 2551 | 126 of 238, 53% | 20 of 6703 | 260 of 285, 91.2% (not gated) | 0 |
+| party | 2616 | 61 of 82, 74% | 8 of 7226 | 138 of 148, 93.2% (gate 90%) | 0 |
+| party+pet | 2548 | 126 of 238, 53% | 20 of 6705 | 260 of 285, 91.2% (not gated) | 0 |
 
 Hits on us (`onus_spec`): 2x strength, the second joining at 15 s: precision 0.967 (>= 0.95), coverage 0.893
 (>= 0.80); same strength from the pull: 0 of 10592 credited; same strength joining (reported): precision 0.879.
diff --git a/tests/Virtual/harness/behaviours.lua b/tests/Virtual/harness/behaviours.lua
index 8c69f93e..c35f6cf5 100644
--- a/tests/Virtual/harness/behaviours.lua
+++ b/tests/Virtual/harness/behaviours.lua
@@ -8,6 +8,7 @@ local M = {}
 M.RATES = { miss = 0.14, dodge = 0.04, parry = 0.04, glancing = 0, crit = 0.12 }
 -- A mob's swings at a player: the player's avoid table is the victim's (`entity.avoid`); this is the mob's crit.
 M.MOB_CRIT = 0.05
+local SAME_MS = { "MISS", "DODGE", "PARRY" }
 
 -- One outcome from `rates` (miss, dodge, parry, block, glancing, crit): the action and its flag.
 local function roll(r, rates)
@@ -50,6 +51,8 @@ end
 --- covers its cost.
 --- `p.strikes`: another player's chance per main-hand swing to make it a strike frame (G: WOUND 0 + damage).
 --- `p.proc` { chance, amount }: a school-32 wound on the swing event (1-2 ms after it). `p.glance` { lo, hi }.
+--- `p.sameMs`: the chance per swing of ours of an unexplained avoid in its ms (`ev.sameMs`, the observer's knob);
+--- our strike frames carry their order (`ev.order`). Both come from `W.crng`; every draw is the behaviour's.
 function M.melee(p)
     p = p or {}
     return function(W, e)
@@ -66,6 +69,8 @@ function M.melee(p)
                 if h == 1 and (e.queued or foreign) then
                     local q = e.queued or {}
                     e.queued = nil
+                    -- our strike frame's order (P log 1's, then the brief's): 1 the success first, 2 the swing first
+                    local order = p.land and (W.crng.chance(0.5) and 1 or 2) or nil
                     W.emit({
                         kind = "strike",
                         src = e,
@@ -78,10 +83,15 @@ function M.melee(p)
                         spell = q.spell,
                         cost = q.cost,
                         speed = w[3],
+                        order = order,
                     })
                 else
                     local act, flag = roll(W.rng, rates)
                     local amt = act == "WOUND" and amount(W.rng, w, e, tgt, flag, p.glance) or 0
+                    -- an unexplained avoid on the target in our swing event's ms (P log 2), rolled here from the
+                    -- client-detail generator so the observer draws nothing (a press changes the fight's future,
+                    -- never how its past is observed) and W.rng's draws per seed stay as they were
+                    local same = p.sameMs and W.crng.chance(p.sameMs) and W.crng.pick(SAME_MS) or nil
                     local sw = W.emit({
                         kind = "swing",
                         src = e,
@@ -93,6 +103,7 @@ function M.melee(p)
                         school = 1,
                         speed = w[3],
                         ours = p.land ~= nil,
+                        sameMs = same,
                     })
                     if p.land then
                         local lag = p.land(W, e, h, W.t)
diff --git a/tests/Virtual/harness/drive.lua b/tests/Virtual/harness/drive.lua
index 3329f993..0149e883 100644
--- a/tests/Virtual/harness/drive.lua
+++ b/tests/Virtual/harness/drive.lua
@@ -148,7 +148,8 @@ function M.restore(c)
     end
 end
 
--- One client-answer change (or the truth's power for the metrics). Allocates nothing.
+--- One client-answer change (or the truth's power for the metrics) on `ctl`; `c.truth` takes `@truth`. Allocates
+--- nothing. The headless loop applies its streams' ops through this too.
 local function op(c, ctl, ev, a1, a2, a3, a4)
     if ev == "@truth" then
         c.truth = a1
@@ -171,6 +172,8 @@ local function op(c, ctl, ev, a1, a2, a3, a4)
     end
 end
 
+M.op = op
+
 local function tick(c, t)
     c.ctl.Tick(t)
     fs.fold(c.ns, t)
diff --git a/tests/Virtual/harness/observer.lua b/tests/Virtual/harness/observer.lua
index e1cf389d..90f95093 100644
--- a/tests/Virtual/harness/observer.lua
+++ b/tests/Virtual/harness/observer.lua
@@ -16,8 +16,9 @@ M.DEFAULTS = {
     -- 7 of 20, one in the main frame), which only their midpoint does.
     off = { own = 0.703, ownSd = 0.006, main = 1.686, mainSd = 0.004, pOwn = 0.452, pMain = 0.49, pFrame = 0.03 },
     tail = { 0.1, 1.3 },
-    sameMs = 3 / 87, -- an avoid on the target in the same ms as our swing event, per swing (P log 2: 3 of 87)
-    usable = false, -- answer usability from our true power (the oracle's scenarios; off: no pins, the scale stays 1)
+    sameMs = 3 / 87, -- an avoid on the target in the same ms as our swing event, per swing (P log 2: 3 of 87); the
+    -- behaviour rolls it (scenarios.lua passes this knob), the observer fires what it rolled
+    usable = false, -- answer usability (true: the fake spec's COSTS against our power; a list: the content's); off: no pins
     usableDelay = 0.1, -- SPELL_UPDATE_USABLE after a true gain that flips an answer (UNMEASURED until G7); a spend at once
     targetTokens = { "plate", "target" }, -- "plate": the target's nameplateN (P logs 1-2: nameplate1 then target)
     plainSpeed = false, -- UnitAttackSpeed of a hostile plain (Attackers.lua notes: secret on Forever)
@@ -76,12 +77,19 @@ function M.rank(token)
     return 6 -- targettarget
 end
 
---- The client stream of world `W` for our character (W.ents[1]) under knobs `k`: { n, t[], ev[], a1..a5[], src[]
+--- An incremental observer of world `W` for our character (W.ents[1]) under knobs `k`. `obs.step(tEnd)` reads the truth
+--- events at or before `tEnd` the world appended since the last step and appends to `obs.s` the client events at or
+--- before `tEnd`, in time then sequence order (later ones, the usability delay or a strike's wound 1 ms on, wait for
+--- a later step); it returns the first and last index it appended. The stream `obs.s`: { n, t[], ev[], a1..a5[], src[]
 --- (1 ours, 2 another source, 3 unexplained, 0 not an outcome), hand[] (our swing's hand; 0 a cast's), swingT[] (our
 --- swing's true time), actor[] (the entity index of a hit on us) }. An `ev` starting with "@" is a client-answer change
---- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`, `@auraError`), or `@truth` our
---- true power after an event (for the metrics).
-function M.observe(W, k)
+--- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`, `@auraError`), or
+--- `@truth` our true power after an event (for the metrics). It draws nothing from `W.rng` (the behaviours roll every
+--- random choice and record it on the truth event), so batch and incremental streams of one world are equal.
+--- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power) -> bool } }
+--- (the content's); `power` is the client's view of ours (a gain `usableDelay` late, a spend at once). Each answer is
+--- evaluated at every power change and, stepping, at each step's end (an aura or a target's health may flip it).
+function M.new(W, k)
     k = k or M.DEFAULTS
     local us = W.ents[1]
     local idx, plate, party, mobs = {}, {}, {}, {}
@@ -98,6 +106,9 @@ function M.observe(W, k)
             party[e] = "partypet1"
         end
     end
+    local s = { n = 0, t = {}, ev = {}, a1 = {}, a2 = {}, a3 = {}, a4 = {}, a5 = {} }
+    s.src, s.hand, s.swingT, s.actor = {}, {}, {}, {}
+    local obs = { s = s }
     local list, seq = {}, 0
     local function push(t, ev, a1, a2, a3, a4, a5, src, hand, swingT, actor)
         seq = seq + 1
@@ -142,9 +153,6 @@ function M.observe(W, k)
             )
         end
     end
-    -- The client's power for usability: our gains after the knob's delay, our spends at their casts (UNMEASURED);
-    -- the answers flip as it crosses the fake spec's costs (built after the walk, in time order).
-    local deltas = {}
     local function targets(t, ev)
         local tt = ev.targets
         for _, e in ipairs(mobs) do
@@ -175,12 +183,17 @@ function M.observe(W, k)
         push(t, "@damage", d[1], d[2], d[3], d[4])
         push(t, "PLAYER_EQUIPMENT_CHANGED")
     end
+    local function spellID(name)
+        return M.SPELLS[name] or name -- a real ID (the content's) passes as is
+    end
     local castN = 0
-    for _, ev in ipairs(W.truth) do
+    local deltas, dseq = {}, 0 -- our power's changes as the client's usability sees them: { t, delta, seq }
+    local function read(ev)
         local t, kind = ev.t, ev.kind
-        if kind == "pull" then
-            cache(t - 0.5, ev.damage)
-            targets(t - 0.4, ev)
+        if kind == "prepull" then -- 0.5 s before the pull: the cache, then the target 0.1 s later
+            cache(t, ev.damage)
+            targets(t + 0.1, ev)
+        elseif kind == "pull" then
             push(t, "@combat", true)
             push(t, "@auraError", "target", true) -- spec §3.1: the target's auras raise in combat
             push(t, "PLAYER_REGEN_DISABLED")
@@ -196,9 +209,8 @@ function M.observe(W, k)
             targets(t, ev)
         elseif kind == "swing" and ev.src == us then
             push(t, "PLAYER_SWING", ev.speed, ev.hand - 1)
-            if k.sameMs > 0 and W.rng.chance(k.sameMs) then
-                local avoid = W.rng.pick({ "MISS", "DODGE", "PARRY" })
-                outcome(t, { dst = ev.ourTarget, ourTarget = ev.ourTarget, act = avoid, amount = 0 }, 3)
+            if ev.sameMs then -- the behaviour's roll (P log 2: 3 of 87)
+                outcome(t, { dst = ev.ourTarget, ourTarget = ev.ourTarget, act = ev.sameMs, amount = 0 }, 3)
             end
         elseif kind == "land" then
             outcome(t, ev, 1, ev.hand, ev.swing.t)
@@ -208,22 +220,22 @@ function M.observe(W, k)
         elseif kind == "strike" then
             castN = castN + 1
             local frame = { dst = ev.dst, ourTarget = ev.ourTarget, act = "WOUND", amount = 0, school = 1 }
-            if W.rng.chance(0.5) then -- P log 1's order, then the brief's: swing and success either way round
-                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, M.SPELLS[ev.spell])
+            if ev.order == 1 then -- P log 1's order, then the brief's: swing and success either way round
+                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
                 outcome(t, frame, 1)
                 push(t, "PLAYER_SWING", ev.speed, 0)
             else
                 push(t, "PLAYER_SWING", ev.speed, 0)
                 outcome(t, frame, 1)
-                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, M.SPELLS[ev.spell])
+                push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
             end
             outcome(t + 0.001, ev, 1)
         -- our cast IDs plain (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1)
         elseif kind == "cast" and ev.src == us then -- others' secret (G 49873)
             castN = castN + 1
-            push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, M.SPELLS[ev.spell])
+            push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
             if ev.onUs then -- P log 1 1345, 4329-4330, 6532: also on targettarget while our target targets us
-                push(t, "UNIT_SPELLCAST_SUCCEEDED", "targettarget", "Cast-" .. castN, M.SPELLS[ev.spell])
+                push(t, "UNIT_SPELLCAST_SUCCEEDED", "targettarget", "Cast-" .. castN, spellID(ev.spell))
             end
         elseif kind == "cast" and party[ev.src] then
             push(t, "UNIT_SPELLCAST_SUCCEEDED", party[ev.src], fake.SECRET, fake.SECRET)
@@ -234,45 +246,98 @@ function M.observe(W, k)
             outcome(t, ev, (ev.src == us) and 1 or 2)
         end
         if ev.power then
-            deltas[#deltas + 1] = { t + (ev.cost and 0 or k.usableDelay), (ev.rage or 0) - (ev.cost or 0) }
+            dseq = dseq + 1
+            deltas[#deltas + 1] = { t + (ev.cost and 0 or k.usableDelay), (ev.rage or 0) - (ev.cost or 0), dseq }
             push(t, "@truth", ev.power) -- the metrics' truth (harness design §3.3), no client answer
         end
     end
-    if k.usable then
-        table.sort(deltas, function(a, b)
-            return a[1] < b[1]
-        end)
-        local usable, p = {}, 0
-        for _, c in ipairs(M.COSTS) do
-            usable[c[1]] = 2
-            push(0, "@usable", c[1], 2)
+    -- usability: the content's answers, or the fake spec's costs against our power (as the client answers them)
+    local answers = k.usable
+    if answers == true then
+        answers = {}
+        for i, c in ipairs(M.COSTS) do
+            local cost = c[2]
+            answers[i] = {
+                c[1],
+                function(_, _, p)
+                    return p >= cost
+                end,
+            }
         end
-        for _, d in ipairs(deltas) do
-            p = math.min(us.powerMax, p + d[2]) -- unclamped below: a spend can land before a delayed gain
-            local flipped = false
-            for _, c in ipairs(M.COSTS) do
-                local st = p >= c[2] and 1 or 2
-                if usable[c[1]] ~= st then
-                    usable[c[1]] = st
-                    push(d[1], "@usable", c[1], st)
-                    flipped = true
+    end
+    local usable, power = {}, 0
+    local function answer(t)
+        local flipped = false
+        for _, u in ipairs(answers) do
+            local st = u[2](W, us, power) and 1 or 2
+            if usable[u[1]] ~= st then
+                usable[u[1]] = st
+                push(t, "@usable", u[1], st)
+                flipped = true
+            end
+        end
+        if flipped then
+            push(t, "SPELL_UPDATE_USABLE")
+        end
+    end
+    if answers then
+        for _, u in ipairs(answers) do
+            usable[u[1]] = 2
+            push(0, "@usable", u[1], 2)
+        end
+    end
+    local function byTime(a, b)
+        return a[1] < b[1] or (a[1] == b[1] and a[#a] < b[#b])
+    end
+    local function bySeq(a, b)
+        return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
+    end
+    local cursor = 0
+    function obs.step(tEnd)
+        local truth = W.truth
+        while truth[cursor + 1] and truth[cursor + 1].t <= tEnd do
+            cursor = cursor + 1
+            read(truth[cursor])
+        end
+        if answers then
+            table.sort(deltas, byTime)
+            local keep = {}
+            for _, d in ipairs(deltas) do
+                if d[1] <= tEnd then
+                    power = math.min(us.powerMax, power + d[2]) -- unclamped below: a spend can land before a delayed gain
+                    answer(d[1])
+                else
+                    keep[#keep + 1] = d
                 end
             end
-            if flipped then
-                push(d[1], "SPELL_UPDATE_USABLE")
+            deltas = keep
+            if tEnd < math.huge then
+                answer(tEnd)
             end
         end
+        table.sort(list, bySeq)
+        local first, keep = s.n + 1, {}
+        for _, e in ipairs(list) do
+            if e[1] <= tEnd then
+                local i = s.n + 1
+                s.n = i
+                s.t[i], s.ev[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i] = e[1], e[3], e[4], e[5], e[6], e[7], e[8]
+                s.src[i], s.hand[i], s.swingT[i], s.actor[i] = e[9], e[10], e[11], e[12]
+            else
+                keep[#keep + 1] = e
+            end
+        end
+        list = keep
+        return first, s.n
     end
-    table.sort(list, function(a, b)
-        return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
-    end)
-    local s = { n = #list, t = {}, ev = {}, a1 = {}, a2 = {}, a3 = {}, a4 = {}, a5 = {} }
-    s.src, s.hand, s.swingT, s.actor = {}, {}, {}, {}
-    for i, e in ipairs(list) do
-        s.t[i], s.ev[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i] = e[1], e[3], e[4], e[5], e[6], e[7], e[8]
-        s.src[i], s.hand[i], s.swingT[i], s.actor[i] = e[9], e[10], e[11], e[12]
-    end
-    return s
+    return obs
+end
+
+--- The whole client stream of a finished world `W` under knobs `k` (one step to the end of time).
+function M.observe(W, k)
+    local obs = M.new(W, k)
+    obs.step(math.huge)
+    return obs.s
 end
 
 return M
diff --git a/tests/Virtual/harness/scenarios.lua b/tests/Virtual/harness/scenarios.lua
index 49098208..4efde05f 100644
--- a/tests/Virtual/harness/scenarios.lua
+++ b/tests/Virtual/harness/scenarios.lua
@@ -74,11 +74,15 @@ function M.build(o, seed)
         others[i] = { e = W.add(e), b = b }
     end
     local pull, stop = 1, (o.duration or 120) + 1
+    W.at(pull - 0.5, function() -- out of combat: the weapon damage cache and the target (observer.lua)
+        W.emit({ kind = "prepull" })
+    end)
     W.at(pull, function()
         W.emit({ kind = "pull" })
         behaviours.melee({
             rates = o.rates,
             land = observer.lag(o.lag),
+            sameMs = (o.lag or observer.DEFAULTS).sameMs,
             rage = o.rage or { 9, 5 },
             presses = o.presses,
             strike = { 70, 90 },
diff --git a/tests/Virtual/harness/world.lua b/tests/Virtual/harness/world.lua
index 68baa0c9..f64e60c7 100644
--- a/tests/Virtual/harness/world.lua
+++ b/tests/Virtual/harness/world.lua
@@ -7,10 +7,11 @@ local M = {}
 
 --- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
 --- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
---- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "pull", "stop", "form", "buff",
---- "target".
+--- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "prepull" (the cache and
+--- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target".
 function M.new(seed)
-    local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), ents = {} }
+    -- crng: the client-detail draws (the same-ms avoid, a strike frame's order) apart from the fight's own
+    local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), crng = rng.new(seed + 7919), ents = {} }
 
     --- Runs `fn(W)` at time `t` (after everything already queued for `t`).
     function W.at(t, fn)
@@ -38,13 +39,13 @@ function M.new(seed)
         if me then -- who our target is, and whether it targets us, at this event (the tokens that fire for it)
             ev.ourTarget, ev.onUs = me.target, me.target ~= nil and me.target.target == me
         end
-        if ev.kind == "pull" or ev.kind == "target" then -- whom each entity targets now (its tokens' answers)
+        if ev.kind == "prepull" or ev.kind == "target" then -- whom each entity targets now (its tokens' answers)
             ev.targets = {}
             for _, e in ipairs(W.ents) do
                 ev.targets[e] = e.target or false
             end
         end
-        if (ev.kind == "pull" or ev.kind == "stop") and me then -- the weapon damage UnitDamage would read now
+        if (ev.kind == "prepull" or ev.kind == "stop") and me then -- the weapon damage UnitDamage would read now
             local w, m = me.weapons, me.dmgMult
             local o = w[2] or { 0, 0 }
             ev.damage = { w[1][1] * m, w[1][2] * m, o[1] * m, o[2] * m }
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `574 successes / 0 failures / 0 errors / 0 pending`.

H's gates after this task, at their bounds (the replay's own run; Task 2 Step 3 updates §9's tables to these):

| Gate | Hit rates | Wrong | False wounds, gross / net | False avoids | Overshoot | Oracle (judged; rescues ours) |
|---|---|---|---|---|---|---|
| solo, 200 fights | .991 / .989 | 26 / 8 | 0 / 0 | 0.08 | 0/2400 | 5554; 1 of 2 |
| buff, 100 | .897 / .944 | 38 / 79 | 0 / 0 | 0.18 | - | 1888; 43 of 50 |
| form, 100 | .965 / .966 | 82 / 61 | 0 / 0 | 0.09 | - | 1953; 1 of 1 |
| party, 100 | .831 / .979 | 0 / 7 | 1.76 / 1.16 | 0.36 | 22/1200 | 2616; 138 of 148 |
| party+pet, 100 | .774 / .898 | 0 / 1 | 6.35 / 5.12 | 0.81 | 47/1200 | 2548; 260 of 285 |

Hits on us unchanged: 2x strength joining precision 0.967, coverage 0.893; same strength from the pull 0 credited; joining 0.879.


- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 131 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      574 successes / 0 failures / 0 errors / 0 pending (about 91 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili tests/Virtual tools docs/dev | grep '^+' | grep -v 'Fury = 17' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|arms|fury|protection|stance|stances|sunder|sunder_armor|overpower|execute|heroic|heroic_strike|bloodrage|charge|whirlwind|rend|cleave|hamstring|slam|recklessness|intercept|pummel|mortal_strike|battle_shout|demoralizing_shout|victory_rush|thunder_clap|battle_stance|berserker_stance|defensive_stance|undead'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-16-combat-harness-and-group-attribution.md tests/Virtual/harness/behaviours.lua \
  tests/Virtual/harness/drive.lua tests/Virtual/harness/observer.lua tests/Virtual/harness/observer_spec.lua \
  tests/Virtual/harness/scenarios.lua tests/Virtual/harness/world.lua
git commit -m "test(harness): an incremental observer that draws nothing (the behaviour rolls the same-ms avoid and the strike order from W.crng); content usability answers; drive.op exported; H's gates re-measured (headless loop design §2.1.1-§2.1.3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin headless-loop`

---
### Task 3: Runtime presses and kills in the world; the Warrior world mapping

Spec §2.1.4 (W.press and the generic verbs), §2.1.5 (kills), §7 (the Warrior content: mapping, resolve, usability answers, true rage per hit, uptime list), §9's press cases and loop_warrior_spec's "an unmapped key fails".

**Files:**
- Modify: `tests/Virtual/harness/world.lua` (`W.press`, `W.queueStrike`, `W.applyAura`, `W.dot`, `W.hit`, `W.gain`, `W.setForm`; a wound to 0 health emits `kill` and sets `W.killAt`; `world.CRIT`), `entities.lua` (`gcdUntil`, `cdUntil`, `avoidAt`), `behaviours.lua` (`p.rage` a function too; our avoids recorded in `avoidAt`; a queued strike the power no longer covers is dropped at the swing; a strike's amount from the queued press), `observer.lua` (`aura`, `queue`/`unqueue`, `kill` answers; the strike clears IsCurrentSpell), `drive.lua` (`@current`, `@dead`, `@aura`; `op` takes `a5`), `headless.lua` (`o.character.items`, the gear scan's reads; the character's power secret unless given), `fake_api.lua` (`ctl.inventory`, `ctl.items`: `GetInventoryItemID`, `C_Item.GetItemInfo`'s name and equip location), `tests/Forever/helpers/warrior_world.lua` (the kit's Recklessness and Slam; the forms; the two-hander; `MAP`, `resolve`, `usable`, `rage`, `uptime`, `WORLD`)
- Test: `tests/Virtual/harness/press_spec.lua` (new, fast, fake spec: "refuses a press for the GCD, the cooldown, the cost and a requirement, changing nothing", "accepts a press: spends, starts the GCD and cooldown, emits the cast with its spell ID as is", "queues an on-next-swing press (IsCurrentSpell) and pays it at the swing; one queued at a time", "puts an aura on the clock: ours on the player plain until its expiry; a refresh keeps it up", "ends the fight at a kill: the target dead, out of combat when no attacker is left"), `observer_spec.lua` (the strike case: "... then no longer current ..."), `tests/Forever/loop_warrior_spec.lua` ("maps every ability the Arms pack can recommend that the character knows; an unmapped key fails", "resolves a press from the class file: cost, cooldown and GCD as the state has them; a strike on the next swing", "answers usability from the true world: Execute under 20% health, Overpower after a dodge, a stance's own")

**Interfaces:**
- Consumes: Task 2's observer and world; Task 1's `headless.new`, `warrior_world.character`.
- Produces: `W.press(e, key, p)` -> true | false, reason ("gcd", "cooldown", "cost", "queued", "requires:<why>"), `p` = { spell, cost, cooldown, gcd, offGcd, onNextSwing, amount, requires(W, e), effect(W, e) }; `W.queueStrike(e, p)`, `W.applyAura(dst, id, duration, stacks, maxStacks)`, `W.dot(e, dst, every, n, amount)`, `W.hit(e, dst, amount, school)`, `W.gain(e, amount)`, `W.setForm(e, form)`, `W.killAt`; truth kinds `aura`, `queue`, `unqueue`, `gain`, `kill`; ops `@current`, `@dead`, `@aura`; `warrior_world.MAP`, `resolve(key, H)`, `usable(H)`, `rage(hand, amount, flag)`, `uptime(H)`, `WORLD`, `FORMS`, `FORM`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/loop_warrior_spec.lua b/tests/Forever/loop_warrior_spec.lua
index 1e5f7626..c327d6f0 100644
--- a/tests/Forever/loop_warrior_spec.lua
+++ b/tests/Forever/loop_warrior_spec.lua
@@ -19,3 +19,65 @@ describe("headless Arms", function()
         assert.are.same({}, headless.unexpected(H, "run"))
     end)
 end)
+
+describe("the Warrior world mapping", function()
+    local H
+    setup(function()
+        H = headless.new({ character = ww.character(), pack = ww.PACK })
+    end)
+
+    it("maps every ability the Arms pack can recommend that the character knows; an unmapped key fails", function()
+        local unmapped = {}
+        for _, list in pairs(H.Hekili.DB.profile.packs[ww.PACK].lists) do
+            for _, entry in ipairs(list) do
+                local a = entry.action and H.Hekili.Class.abilities[entry.action]
+                if a and a.id and H.ctl.known[a.id] and not ww.MAP[entry.action] then
+                    unmapped[#unmapped + 1] = entry.action
+                end
+            end
+        end
+        assert.are.same({}, unmapped)
+        local ok, err = pcall(ww.resolve, "not_an_ability", H)
+        assert.is_false(ok)
+        assert.is_truthy(tostring(err):find("unmapped key not_an_ability", 1, true))
+    end)
+
+    it(
+        "resolves a press from the class file: cost, cooldown and GCD as the state has them; a strike on the next swing",
+        function()
+            local ms, hs = ww.resolve("mortal_strike", H), ww.resolve("heroic_strike", H)
+            local a = H.Hekili.Class.abilities
+            assert.are.same(
+                { a.mortal_strike.id, H.Hekili.State.action.mortal_strike.cost, a.mortal_strike.cooldown, false },
+                { ms.spell, ms.cost, ms.cooldown, ms.offGcd }
+            )
+            assert.are.same(
+                { true, true, H.Hekili.State.action.heroic_strike.cost },
+                { hs.onNextSwing, hs.offGcd, hs.cost }
+            )
+        end
+    )
+
+    it(
+        "answers usability from the true world: Execute under 20% health, Overpower after a dodge, a stance's own",
+        function()
+            local answers, by = ww.usable(H), {}
+            for _, u in ipairs(answers) do
+                by[u[1]] = u[2]
+            end
+            local a = H.Hekili.Class.abilities
+            local mob = { health = 100, healthMax = 100 }
+            local W, e = { t = 10 }, { form = ww.FORM.battle_stance, target = mob, avoidAt = {} }
+            assert.is_false(by[a.execute.id](W, e, 100))
+            mob.health = 19
+            assert.is_true(by[a.execute.id](W, e, 100))
+            assert.is_false(by[a.execute.id](W, e, 5)) -- short of its cost
+            assert.is_false(by[a.overpower.id](W, e, 100))
+            e.avoidAt.DODGE = 8
+            assert.is_true(by[a.overpower.id](W, e, 100))
+            assert.is_false(by[a.whirlwind.id](W, e, 100)) -- Berserker Stance's
+            e.form = ww.FORM.berserker_stance
+            assert.is_true(by[a.whirlwind.id](W, e, 100))
+        end
+    )
+end)
diff --git a/tests/Virtual/harness/observer_spec.lua b/tests/Virtual/harness/observer_spec.lua
index 64dda065..e3fb356c 100644
--- a/tests/Virtual/harness/observer_spec.lua
+++ b/tests/Virtual/harness/observer_spec.lua
@@ -127,7 +127,7 @@ describe("the observer", function()
     end)
 
     it(
-        "fires a queued strike's frame: our swing, a WOUND 0 and our success in its rolled order, its wound 1 ms later",
+        "fires a queued strike's frame: our swing, a WOUND 0 and our success in its rolled order, then no longer current, its wound 1 ms later",
         function()
             local orders = {}
             for order = 1, 2 do
@@ -155,8 +155,8 @@ describe("the observer", function()
                 assert.are.same({ 6.001, "target", 80, 1 }, { got[#got][1], got[#got][3], got[#got][6], got[#got][8] })
             end
             assert.are.same({
-                "UNIT_SPELLCAST_SUCCEEDED nameplate10 target0 PLAYER_SWING nameplate180 target80",
-                "PLAYER_SWING nameplate10 target0 UNIT_SPELLCAST_SUCCEEDED nameplate180 target80",
+                "UNIT_SPELLCAST_SUCCEEDED nameplate10 target0 PLAYER_SWING @current nameplate180 target80",
+                "PLAYER_SWING nameplate10 target0 UNIT_SPELLCAST_SUCCEEDED @current nameplate180 target80",
             }, orders)
         end
     )
diff --git a/tests/Virtual/harness/press_spec.lua b/tests/Virtual/harness/press_spec.lua
new file mode 100644
index 00000000..614793e9
--- /dev/null
+++ b/tests/Virtual/harness/press_spec.lua
@@ -0,0 +1,153 @@
+-- tests/Virtual/harness/press_spec.lua (headless loop design §2.1.4-§2.1.5, §9): the world's runtime press and its
+-- generic verbs, on the fake spec's spells (class-neutral).
+local world = require("Virtual.harness.world")
+local entities = require("Virtual.harness.entities")
+local behaviours = require("Virtual.harness.behaviours")
+local observer = require("Virtual.harness.observer")
+local fs = require("Virtual.State.helpers.fake_spec")
+
+describe("the world's press", function()
+    local W, us, mob
+
+    local function setup()
+        W = world.new(5)
+        us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
+        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } }, health = 1e6 }))
+        us.target, mob.target = mob, us
+        us.power = 20
+    end
+
+    -- The client events of the world so far, as "ev a1 a2" strings (ops included, the initial answers left out).
+    local function seen()
+        local s, out = observer.observe(W), {}
+        for i = 1, s.n do
+            out[#out + 1] = table.concat({ s.ev[i], tostring(s.a1[i]), tostring(s.a2[i]) }, " ")
+        end
+        return out
+    end
+
+    it("refuses a press for the GCD, the cooldown, the cost and a requirement, changing nothing", function()
+        setup()
+        local p = { spell = fs.SPENDER_A, cost = 10, cooldown = 6, gcd = 1.5 }
+        W.t = 10
+        assert.is_true(W.press(us, "spender_a", p))
+        W.t = 11 -- the GCD runs to 11.5
+        assert.are.same({ false, "gcd" }, { W.press(us, "spender_b", { spell = fs.SPENDER_B, cost = 5 }) })
+        W.t = 12 -- off the GCD, on the cooldown until 16
+        assert.are.same({ false, "cooldown" }, { W.press(us, "spender_a", p) })
+        assert.are.same({ false, "cost" }, { W.press(us, "spender_b", { spell = fs.SPENDER_B, cost = 15 }) })
+        local why = function()
+            return false, "phase"
+        end
+        assert.are.same(
+            { false, "requires:phase" },
+            { W.press(us, "spender_b", { spell = fs.SPENDER_B, cost = 5, requires = why }) }
+        )
+        assert.are.same({ 10, 11.5, 16 }, { us.power, us.gcdUntil, us.cdUntil.spender_a })
+        assert.is_nil(us.cdUntil.spender_b)
+        local casts = 0
+        for _, ev in ipairs(W.truth) do
+            casts = casts + (ev.kind == "cast" and 1 or 0)
+        end
+        assert.are.equal(1, casts)
+    end)
+
+    it("accepts a press: spends, starts the GCD and cooldown, emits the cast with its spell ID as is", function()
+        setup()
+        W.t = 3
+        local hit = 0
+        local p = {
+            spell = fs.SPENDER_C,
+            cost = 10,
+            cooldown = 6,
+            effect = function(w, e)
+                hit = hit + 1
+                w.gain(e, 5)
+            end,
+        }
+        assert.is_true(W.press(us, "spender_c", p))
+        assert.are.same({ 15, 4.5, 9, 1 }, { us.power, us.gcdUntil, us.cdUntil.spender_c, hit })
+        local got = seen() -- our target targets us: the success fires on targettarget too
+        assert.are.same({
+            "UNIT_SPELLCAST_SUCCEEDED player Cast-1",
+            "UNIT_SPELLCAST_SUCCEEDED targettarget Cast-1",
+            "@truth 10 nil",
+            "@truth 15 nil",
+        }, { got[1], got[2], got[3], got[4] })
+        local s = observer.observe(W)
+        assert.are.equal(fs.SPENDER_C, s.a3[1])
+    end)
+
+    it("queues an on-next-swing press (IsCurrentSpell) and pays it at the swing; one queued at a time", function()
+        setup()
+        behaviours.melee({ land = observer.lag(), phase = { 2, 9 } })(W, us)
+        W.run(1)
+        local p = { spell = fs.SPENDER_B, cost = 15, offGcd = true, onNextSwing = true, amount = { 70, 70 } }
+        assert.is_true(W.press(us, "spender_b", p))
+        assert.are.same({ false, "queued" }, { W.press(us, "spender_b", p) })
+        assert.are.equal(20, us.power) -- paid at the swing, not the press
+        W.run(2.5)
+        assert.are.equal(5, us.power)
+        local got = seen()
+        assert.are.equal("@current " .. fs.SPENDER_B .. " true", got[1])
+        local last
+        for _, line in ipairs(got) do
+            if line:match("^@current") then
+                last = line
+            end
+        end
+        assert.are.equal("@current " .. fs.SPENDER_B .. " false", last)
+    end)
+
+    it("puts an aura on the clock: ours on the player plain until its expiry; a refresh keeps it up", function()
+        setup()
+        W.t = 1
+        W.applyAura(us, 501, 10)
+        W.at(6, function()
+            W.applyAura(us, 501, 10)
+        end)
+        W.applyAura(mob, 502, 30, 1, 5)
+        W.applyAura(mob, 502, 30, 1, 5)
+        W.run(15)
+        assert.are.equal(2, mob.auras[502].stacks)
+        assert.is_table(us.auras[501]) -- the refresh at 6 runs to 16
+        W.run(17)
+        assert.is_nil(us.auras[501])
+        local s, lines = observer.observe(W), {}
+        for i = 1, s.n do
+            if s.ev[i] == "@aura" then
+                lines[#lines + 1] = { s.t[i], s.a1[i], s.a2[i], s.a3[i], s.a4[i] }
+            end
+        end
+        assert.are.same({
+            { 1, "player", 501, 1, 11 },
+            { 1, "target", 502, 1, 31 },
+            { 1, "target", 502, 2, 31 },
+            { 6, "player", 501, 1, 16 },
+            { 16, "player", 501, 0, 0 },
+        }, lines)
+    end)
+
+    it("ends the fight at a kill: the target dead, out of combat when no attacker is left", function()
+        setup()
+        mob.health = 30
+        W.t = 2
+        W.emit({ kind = "pull" })
+        W.hit(us, mob, 50)
+        if not mob.dead then -- an avoid: hit again (seed 5's roll)
+            W.hit(us, mob, 50)
+        end
+        assert.is_true(mob.dead)
+        assert.are.equal(2, W.killAt)
+        local got, at = seen(), nil
+        for i, line in ipairs(got) do
+            at = line == "@dead target true" and i or at
+        end
+        assert.are.same({
+            "UNIT_HEALTH target nil",
+            "@combat false nil",
+            "@auraError target false",
+            "PLAYER_REGEN_ENABLED nil nil",
+        }, { got[at + 1], got[at + 2], got[at + 3], got[at + 4] })
+    end)
+end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `573 successes / 1 failure / 8 errors / 0 pending`.
- `press_spec` errors in every case (`attempt to call field 'press'` / `'applyAura'` / `'hit'` (a nil value)); observer_spec's strike case fails (no `@current`); the three new loop_warrior_spec cases error (`attempt to index field 'MAP' (a nil value)`, `attempt to call field 'resolve'`, `'usable'`).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/helpers/warrior_world.lua b/tests/Forever/helpers/warrior_world.lua
index 790e6527..1973141c 100644
--- a/tests/Forever/helpers/warrior_world.lua
+++ b/tests/Forever/helpers/warrior_world.lua
@@ -1,6 +1,9 @@
 -- tests/Forever/helpers/warrior_world.lua (headless loop design §7): the Warrior content of the class-neutral headless
--- loop: the character the instance logs in as. Spell IDs come from the class file itself (load_warrior's recording
--- load: each ability's `id` and `copy` ranks), never copied here.
+-- loop: the character the instance logs in as, each ability's press in the world's generic verbs (W.press's
+-- `requires` and `effect`), the client's usability answers and the true rage per landed hit. Spell and aura IDs,
+-- costs, cooldowns, durations and stance requirements come from the class file (load_warrior's recording load for the
+-- character; the booted instance's Hekili.Class and Hekili.State for the rest), never copied here. Damage amounts are
+-- Classic's rank-60 values: the loop compares two runs of one model (A/B), so they set only what a choice is worth.
 local loadWarrior = require("Forever.helpers.load_warrior")
 
 local M = {}
@@ -35,8 +38,15 @@ M.KIT = {
 -- Impale 2, Improved Rend 3.
 M.TALENTS = { [12294] = 1, [12296] = 1, [12834] = 3, [12295] = 5, [16493] = 2, [12163] = 3 }
 
---- The character for headless.new (§1.3): level 60, the kit known, the Arms talents, rage 0 of 100, a two-hand weapon
---- (speed 3.6), the three stances as forms, Battle Stance up.
+-- The stances as the client's forms, in order (GetShapeshiftForm's index).
+M.FORMS = { "battle_stance", "defensive_stance", "berserker_stance" }
+M.FORM = {}
+for i, key in ipairs(M.FORMS) do
+    M.FORM[key] = i
+end
+
+--- The character for headless.new (§1.3): level 60, the kit known, the Arms talents, rage of 100 (secret, as on
+--- Forever), a two-hand weapon (speed 3.6; the gear scan reads it as one), the three stances as forms, Battle Stance up.
 function M.character()
     local w = loadWarrior.load()
     local known = {}
@@ -48,7 +58,7 @@ function M.character()
         end
     end
     local forms = {}
-    for i, key in ipairs({ "battle_stance", "defensive_stance", "berserker_stance" }) do
+    for i, key in ipairs(M.FORMS) do
         forms[i] = w.abilities[key].id
     end
     return {
@@ -58,11 +68,252 @@ function M.character()
         level = 60,
         known = known,
         talents = M.TALENTS,
-        power = { type = 1, token = "RAGE", max = 100, value = 0 },
+        power = { type = 1, token = "RAGE", max = 100 },
         speed = { 3.6 },
+        items = { [16] = { 1, "Two-Hander", "INVTYPE_2HWEAPON" } },
         forms = forms,
         form = 1,
     }
 end
 
+-- The world the loop fights in (scenarios.world's knobs): level 60 against a level 60 mob in melee range, the
+-- two-hander's damage (Arcanite Reaper's range, rounded), rage capped at 100.
+M.WORLD = { level = 60, weapons = { { 150, 230, 3.6 } }, max = 100 }
+
+-- True rage per landed white wound: the class file's own model restated (Forever/Classes/Warrior.lua, "Rage per white
+-- swing": 4.5 x the unhasted speed with a two-hander; a crit one more base swing, 3.46 x speed). Circular on purpose:
+-- the loop measures recommendations, not the rage model (its own specs measure that).
+function M.rage(hand, _, flag)
+    if hand ~= 1 then
+        return 0
+    end
+    return 4.5 * 3.6 + (flag == "CRITICAL" and 3.46 * 3.6 or 0)
+end
+
+-- A weapon hit's amount: the main hand's roll plus `bonus`.
+local function weapon(W, e, bonus)
+    local w = e.weapons[1]
+    return W.rng.int(w[1], w[2]) + bonus
+end
+
+-- Each recommendable ability's press: `requires(W, e, X)` (beyond the stance, which the ability's buff/nobuff fields
+-- give) and `effect(W, e, p, X)` in the world's verbs; `X` holds the class data (X.aura[key] = { id, duration,
+-- max_stack }). An ability missing here fails the loop ("unmapped key").
+local function aura(W, X, dst, key, stacks)
+    local a = X.aura[key]
+    W.applyAura(dst, a.id, a.duration, stacks or 1, a.max_stack)
+end
+local function stance(key)
+    return {
+        effect = function(W, e)
+            W.setForm(e, M.FORM[key])
+            if e.power > 25 then -- Tactical Mastery 5/5 keeps 25 rage through a stance change
+                W.gain(e, 25 - e.power)
+            end
+        end,
+    }
+end
+M.MAP = {
+    battle_stance = stance("battle_stance"),
+    berserker_stance = stance("berserker_stance"),
+    defensive_stance = stance("defensive_stance"),
+    battle_shout = {
+        effect = function(W, e, _, X)
+            aura(W, X, e, "battle_shout")
+        end,
+    },
+    bloodrage = { -- 10 at once, then 1 a second for 10 s (the class file's tick aura)
+        effect = function(W, e, _, X)
+            aura(W, X, e, "bloodrage")
+            W.gain(e, 10)
+            for k = 1, 10 do
+                W.at(W.t + k, function()
+                    W.gain(e, 1)
+                end)
+            end
+        end,
+    },
+    -- shortcut: no positions, so Charge only pays its rage (rank 3: 15); the pull starts combat. Upgrade with positions.
+    charge = {
+        effect = function(W, e)
+            W.gain(e, 15)
+        end,
+    },
+    cleave = { amount = 50, onNextSwing = true },
+    heroic_strike = { amount = 157, onNextSwing = true },
+    demoralizing_shout = {
+        effect = function(W, e, _, X)
+            aura(W, X, e.target, "demoralizing_shout")
+        end,
+    },
+    sunder_armor = {
+        effect = function(W, e, _, X)
+            aura(W, X, e.target, "sunder_armor")
+        end,
+    },
+    hamstring = {
+        effect = function(W, e, _, X)
+            aura(W, X, e.target, "hamstring")
+            W.hit(e, e.target, 45)
+        end,
+    },
+    rend = { -- rank 7: 147 over the aura's duration, a tick every 3 s
+        effect = function(W, e, _, X)
+            local d = X.aura.rend.duration
+            aura(W, X, e.target, "rend")
+            W.dot(e, e.target, 3, math.floor(d / 3), math.floor(147 * 3 / d))
+        end,
+    },
+    recklessness = {
+        effect = function(W, e, _, X)
+            aura(W, X, e, "recklessness")
+        end,
+    },
+    mortal_strike = {
+        effect = function(W, e)
+            W.hit(e, e.target, weapon(W, e, 160))
+        end,
+    },
+    whirlwind = {
+        effect = function(W, e)
+            W.hit(e, e.target, weapon(W, e, 0))
+        end,
+    },
+    slam = {
+        effect = function(W, e)
+            W.hit(e, e.target, weapon(W, e, 87))
+        end,
+    },
+    intercept = {
+        effect = function(W, e)
+            W.hit(e, e.target, 65)
+        end,
+    },
+    overpower = { -- a dodge of ours on the target within 5 s opens it; the press uses it up
+        requires = function(W, e)
+            return W.t - (e.avoidAt.DODGE or -1e9) <= 5, "no dodge"
+        end,
+        effect = function(W, e)
+            e.avoidAt.DODGE = nil
+            W.hit(e, e.target, weapon(W, e, 35))
+        end,
+    },
+    execute = { -- the target's true health under 20%; rank 5: 600, and 15 a point of the rage it spends past its cost
+        requires = function(_, e)
+            local v = e.target
+            return v ~= nil and v.health < 0.2 * v.healthMax, "not in execute range"
+        end,
+        effect = function(W, e)
+            local extra = e.power
+            W.gain(e, -extra)
+            W.hit(e, e.target, 600 + 15 * extra)
+        end,
+    },
+    victory_rush = { -- a kill of ours within 20 s
+        requires = function(W)
+            return W.killAt ~= nil and W.t - W.killAt <= 20, "no kill"
+        end,
+        effect = function(W, e)
+            W.hit(e, e.target, 200)
+        end,
+    },
+}
+
+-- The class data the mapping reads, from a booted instance `H` (once per instance).
+local cache = setmetatable({}, { __mode = "k" })
+local function classData(H)
+    if cache[H] then
+        return cache[H]
+    end
+    local X = { aura = {} }
+    cache[H] = X
+    for key, a in pairs(H.Hekili.Class.auras) do
+        if type(key) == "string" and type(a) == "table" and a.id then
+            X.aura[key] = { id = a.id, duration = a.duration, max_stack = a.max_stack }
+        end
+    end
+    return X
+end
+
+-- Whether `e`'s true stance meets ability `a`'s buff / nobuff stance fields.
+local function stanceOk(a, e)
+    if a.buff and M.FORM[a.buff] and e.form ~= M.FORM[a.buff] then
+        return false, a.buff
+    elseif a.nobuff and M.FORM[a.nobuff] and e.form == M.FORM[a.nobuff] then
+        return false, "not " .. a.nobuff
+    end
+    return true
+end
+
+--- The resolved press of `key` (headless loop design §7), read from instance `H` (the loop passes the oracle's: its
+--- state is true): the ability's ID, its cost as the state resolves it, its cooldown and GCD, on-next-swing; the
+--- mapping's requirement (after the stance's) and effect. Raises "unmapped key" for a key the mapping lacks.
+function M.resolve(key, H)
+    local m = M.MAP[key]
+    if not m then
+        error("unmapped key " .. tostring(key), 2)
+    end
+    local a = H.Hekili.Class.abilities[key]
+    local X = classData(H)
+    local p = {
+        spell = a.id,
+        cost = H.Hekili.State.action[key].cost or 0,
+        cooldown = tonumber(a.cooldown) or 0,
+        gcd = 1.5,
+        offGcd = a.gcd == "off",
+        onNextSwing = m.onNextSwing or a.onNextSwing or a.nextSwing,
+    }
+    if m.amount then
+        local w = M.WORLD.weapons[1]
+        p.amount = { w[1] + m.amount, w[2] + m.amount }
+    end
+    p.requires = function(W, e)
+        local ok, why = stanceOk(a, e)
+        if ok and m.requires then
+            ok, why = m.requires(W, e, X)
+        end
+        return ok, why
+    end
+    if m.effect then
+        p.effect = function(W, e)
+            m.effect(W, e, p, X)
+        end
+    end
+    return p
+end
+
+--- The client's usability answers (observer `k.usable`) for every mapped ability the character knows, from instance
+--- `H`: the power (the client's view) covers the cost, the stance fits and the mapping's requirement holds in the true
+--- world (Execute's phase and Overpower's opening read these, as in game).
+function M.usable(H)
+    local out = {}
+    for key, m in pairs(M.MAP) do
+        local a = H.Hekili.Class.abilities[key]
+        if a and H.ctl.known[a.id] then
+            local cost = H.Hekili.State.action[key].cost or 0
+            local X = classData(H)
+            out[#out + 1] = {
+                a.id,
+                function(W, e, power)
+                    return power >= cost and stanceOk(a, e) and (not m.requires or m.requires(W, e, X)) or false
+                end,
+            }
+        end
+    end
+    table.sort(out, function(x, y)
+        return x[1] < y[1]
+    end)
+    return out
+end
+
+--- The debuffs whose uptime the loop reports (§5.1): the Arms list keeps Sunder Armor and Demoralizing Shout up (Rend
+--- only without Mortal Strike). Returns { { key, auraID } } from instance `H`.
+function M.uptime(H)
+    local out = {}
+    for _, key in ipairs({ "sunder_armor", "demoralizing_shout" }) do
+        out[#out + 1] = { key, H.Hekili.Class.auras[key].id }
+    end
+    return out
+end
+
 return M
diff --git a/tests/Virtual/State/helpers/fake_api.lua b/tests/Virtual/State/helpers/fake_api.lua
index 274e40ba..3c352b69 100644
--- a/tests/Virtual/State/helpers/fake_api.lua
+++ b/tests/Virtual/State/helpers/fake_api.lua
@@ -67,6 +67,8 @@ function M.new()
         specID = nil, -- C_SpecializationInfo.GetSpecializationInfo(1)'s ID (nil: no specialization)
         powerType = { 0, "MANA" }, -- UnitPowerType("player")
         role = "DAMAGER",
+        inventory = {}, -- [slot] = itemID (GetInventoryItemID("player", slot))
+        items = {}, -- [itemID] = { name, equipLoc } (C_Item.GetItemInfo's first and ninth returns)
     }
     local api = { ctl = ctl }
 
@@ -273,7 +275,10 @@ function M.new()
         return "enUS"
     end
     api.GetCVar, api.GetCursorInfo, api.GetActionInfo, api.GetBindingKey = none, none, none, none
-    api.GetInventoryItemID, api.GetSpecializationInfoByID, api.GetStablePetInfo = none, none, none
+    api.GetSpecializationInfoByID, api.GetStablePetInfo = none, none
+    function api.GetInventoryItemID(_, slot)
+        return ctl.inventory[slot]
+    end
     api.UnitPhaseReason, api.UnitThreatSituation, api.UnitTokenFromGUID, api.IsActionInRange = none, none, none, none
     api.HasOverrideActionBar, api.HasVehicleActionBar, api.IsInJailersTower, api.SpellIsSelfBuff = no, no, no, no
     api.IsMounted, api.IsResting, api.IsInGroup, api.IsInRaid, api.UnitCanAssist = no, no, no, no, no
@@ -414,7 +419,12 @@ function M.new()
         GetItemCount = zero,
         GetItemSpell = none,
         IsUsableItem = no,
-        GetItemInfo = none,
+        GetItemInfo = function(id)
+            local i = ctl.items[id]
+            if i then
+                return i[1], nil, nil, nil, nil, nil, nil, nil, i[2]
+            end
+        end,
         GetItemInfoInstant = none,
         GetItemCooldown = function()
             return 0, 0, 1
diff --git a/tests/Virtual/harness/behaviours.lua b/tests/Virtual/harness/behaviours.lua
index c35f6cf5..1a5024b0 100644
--- a/tests/Virtual/harness/behaviours.lua
+++ b/tests/Virtual/harness/behaviours.lua
@@ -45,7 +45,8 @@ end
 
 --- A melee player: per weapon hand, a swing every speed / haste from a random phase, its outcome rolled from `p.rates`
 --- (default RATES). `p.land(W, e, hand, t)`: ours only, the lag before the outcome lands (observer.lua); without it the
---- outcome is at the swing (another player's). `p.rage` { main, off }: what a landed swing of ours pays.
+--- outcome is at the swing (another player's). `p.rage` { main, off } or fn(hand, amount, flag): what a landed wound
+--- of ours pays. A queued strike (W.queueStrike) our power no longer covers at the swing is dropped (a white swing).
 --- `p.presses` { { t, spell, cost, kind } }: kind "queue" (the next main-hand swing is a strike of `p.strike`
 --- { lo, hi }), "dot" (`p.dot` { every, n, amount } ticks, school 1), "cast" (no outcome); each only if our power
 --- covers its cost.
@@ -66,6 +67,10 @@ function M.melee(p)
                 end
                 local w = e.weapons[h]
                 local foreign = h == 1 and p.strikes and W.rng.chance(p.strikes)
+                if h == 1 and e.queued and e.power < (e.queued.cost or 0) then -- short at the swing: a white one
+                    W.emit({ kind = "unqueue", src = e, spell = e.queued.spell })
+                    e.queued = nil
+                end
                 if h == 1 and (e.queued or foreign) then
                     local q = e.queued or {}
                     e.queued = nil
@@ -78,7 +83,7 @@ function M.melee(p)
                         hand = 1,
                         act = "WOUND",
                         flag = "",
-                        amount = W.rng.int((p.strike or w)[1], (p.strike or w)[2]),
+                        amount = W.rng.int((q.amount or p.strike or w)[1], (q.amount or p.strike or w)[2]),
                         school = 1,
                         spell = q.spell,
                         cost = q.cost,
@@ -109,6 +114,15 @@ function M.melee(p)
                         local lag = p.land(W, e, h, W.t)
                         e.landAt[h] = W.t + lag
                         W.at(W.t + lag, function()
+                            if act ~= "WOUND" then
+                                e.avoidAt[act] = W.t -- the world's truth a content requirement reads (an opening)
+                            end
+                            local rage = p.rage
+                            if type(rage) == "function" then
+                                rage = act == "WOUND" and rage(h, amt, flag) or nil
+                            else
+                                rage = act == "WOUND" and rage and rage[h] or nil
+                            end
                             W.emit({
                                 kind = "land",
                                 src = e,
@@ -119,7 +133,7 @@ function M.melee(p)
                                 amount = amt,
                                 school = 1,
                                 swing = sw,
-                                rage = act == "WOUND" and p.rage and p.rage[h] or nil,
+                                rage = rage,
                             })
                         end)
                     end
diff --git a/tests/Virtual/harness/drive.lua b/tests/Virtual/harness/drive.lua
index 0149e883..cb092d3c 100644
--- a/tests/Virtual/harness/drive.lua
+++ b/tests/Virtual/harness/drive.lua
@@ -148,9 +148,37 @@ function M.restore(c)
     end
 end
 
+-- An aura list entry of `unit` (the player's helpful, the target's harmful), from the player. Allocates (headless
+-- loop only: the 0-byte drives fire no aura).
+local function aura(ctl, unit, id, stacks, expires, duration)
+    local list = ctl.auras[unit][unit == "player" and "HELPFUL" or "HARMFUL"]
+    for i, a in ipairs(list) do
+        if a.spellId == id then
+            if stacks == 0 then
+                table.remove(list, i)
+            else
+                a.applications, a.expirationTime, a.duration = stacks, expires, duration
+            end
+            return
+        end
+    end
+    if stacks > 0 then
+        list[#list + 1] = {
+            name = "Aura " .. id,
+            icon = 0,
+            spellId = id,
+            applications = stacks,
+            duration = duration,
+            expirationTime = expires,
+            sourceUnit = "player",
+            isFromPlayerOrPlayerPet = true,
+        }
+    end
+end
+
 --- One client-answer change (or the truth's power for the metrics) on `ctl`; `c.truth` takes `@truth`. Allocates
 --- nothing. The headless loop applies its streams' ops through this too.
-local function op(c, ctl, ev, a1, a2, a3, a4)
+local function op(c, ctl, ev, a1, a2, a3, a4, a5)
     if ev == "@truth" then
         c.truth = a1
     elseif ev == "@damage" then
@@ -169,6 +197,12 @@ local function op(c, ctl, ev, a1, a2, a3, a4)
         ctl.combat = a1
     elseif ev == "@auraError" then
         ctl.auraError[a1] = a2 or nil
+    elseif ev == "@current" then
+        ctl.current[a1] = a2 or nil
+    elseif ev == "@dead" then
+        ctl.dead[a1] = a2 or nil
+    elseif ev == "@aura" then -- unit, spellID, stacks (0: gone), expires, duration: ours, from the player
+        aura(ctl, a1, a2, a3, a4, a5)
     end
 end
 
@@ -222,7 +256,7 @@ function M.run(c, s, offset)
         ctl.now = t
         local ev = s.ev[i]
         if ev:byte(1) == 64 then -- "@"
-            op(c, ctl, ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i])
+            op(c, ctl, ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
         else
             c.cur = i
             local avoids = c.L.avoids
diff --git a/tests/Virtual/harness/entities.lua b/tests/Virtual/harness/entities.lua
index 8da65e7c..abc232e4 100644
--- a/tests/Virtual/harness/entities.lua
+++ b/tests/Virtual/harness/entities.lua
@@ -33,6 +33,9 @@ function M.new(o)
         target = o.target,
         form = 0,
         dmgMult = 1,
+        gcdUntil = 0, -- the true GCD's end (W.press)
+        cdUntil = {}, -- [key] = the true cooldown's end
+        avoidAt = {}, -- [act] = the last time an outcome of ours on a target was that avoid (MISS, DODGE, PARRY)
     }
     return e
 end
diff --git a/tests/Virtual/harness/headless.lua b/tests/Virtual/harness/headless.lua
index 472f2e25..f8d66db1 100644
--- a/tests/Virtual/harness/headless.lua
+++ b/tests/Virtual/harness/headless.lua
@@ -240,7 +240,8 @@ end
 
 --- A new instance: Hekili loaded and logged in. `o.character` (the content's, set before login: §1.3) {
 --- class, classID, specID, level, known = { spellID... }, talents = { [spellID] = rank }, power = { type, token, max,
---- value }, speed = { main, off }, forms = { spellID... }, form }; `o.pack` the priority to select; `o.now` the clock [1000].
+--- value (nil: secret, as on Forever) }, speed = { main, off }, items = { [slot] = { itemID, name, equipLoc } },
+--- forms = { spellID... }, form }; `o.pack` the priority to select; `o.now` the clock [1000].
 --- Returns `H = { env, api, ctl, ns, Hekili, frames, timers, misses, errors, loadErrors, prints }`.
 function M.new(o)
     o = o or {}
@@ -855,11 +856,14 @@ function M.new(o)
         local p = c.power
         if p then
             ctl.powerType[1], ctl.powerType[2] = p.type, p.token
-            ctl.powerMax[p.type], ctl.power[p.type] = p.max, p.value or 0
+            ctl.powerMax[p.type], ctl.power[p.type] = p.max, p.value
         end
         if c.speed then
             ctl.speed = c.speed
         end
+        for slot, item in pairs(c.items or {}) do -- { [slot] = { itemID, name, equipLoc } }: the gear scan's reads
+            ctl.inventory[slot], ctl.items[item[1]] = item[1], { item[2], item[3] }
+        end
         for i, id in ipairs(c.forms or {}) do
             ctl.forms[i] = id
         end
diff --git a/tests/Virtual/harness/observer.lua b/tests/Virtual/harness/observer.lua
index 90f95093..ab261b69 100644
--- a/tests/Virtual/harness/observer.lua
+++ b/tests/Virtual/harness/observer.lua
@@ -83,8 +83,8 @@ end
 --- a later step); it returns the first and last index it appended. The stream `obs.s`: { n, t[], ev[], a1..a5[], src[]
 --- (1 ours, 2 another source, 3 unexplained, 0 not an outcome), hand[] (our swing's hand; 0 a cast's), swingT[] (our
 --- swing's true time), actor[] (the entity index of a hit on us) }. An `ev` starting with "@" is a client-answer change
---- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`, `@auraError`), or
---- `@truth` our true power after an event (for the metrics). It draws nothing from `W.rng` (the behaviours roll every
+--- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`, `@auraError`,
+--- `@current` IsCurrentSpell, `@aura` an aura list entry, `@dead`), or `@truth` our true power after an event. It draws nothing from `W.rng` (the behaviours roll every
 --- random choice and record it on the truth event), so batch and incremental streams of one world are equal.
 --- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power) -> bool } }
 --- (the content's); `power` is the client's view of ours (a gain `usableDelay` late, a spend at once). Each answer is
@@ -230,6 +230,29 @@ function M.new(W, k)
                 push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
             end
             outcome(t + 0.001, ev, 1)
+            push(t, "@current", spellID(ev.spell), false) -- IsCurrentSpell: no longer queued
+        elseif kind == "queue" or kind == "unqueue" then -- our on-next-swing press (IsCurrentSpell, plain)
+            push(t, "@current", spellID(ev.spell), kind == "queue")
+        elseif kind == "aura" then -- ours on the player (plain), ours on the target (raising in combat)
+            local unit = ev.dst == us and "player" or (ev.dst == ev.ourTarget and "target" or nil)
+            if unit then
+                push(t, "@aura", unit, ev.aura, ev.stacks, ev.expires, ev.duration)
+                push(t, "UNIT_AURA", unit)
+            end
+        elseif kind == "kill" then -- our target gone; out of combat when no living attacker is left
+            if ev.dst == ev.ourTarget then
+                push(t, "@dead", "target", true)
+                push(t, "UNIT_HEALTH", "target")
+            end
+            local left = false
+            for _, e in ipairs(mobs) do
+                left = left or (not e.dead and e.target == us)
+            end
+            if not left then
+                push(t, "@combat", false)
+                push(t, "@auraError", "target", false)
+                push(t, "PLAYER_REGEN_ENABLED")
+            end
         -- our cast IDs plain (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1)
         elseif kind == "cast" and ev.src == us then -- others' secret (G 49873)
             castN = castN + 1
diff --git a/tests/Virtual/harness/world.lua b/tests/Virtual/harness/world.lua
index f64e60c7..5968f710 100644
--- a/tests/Virtual/harness/world.lua
+++ b/tests/Virtual/harness/world.lua
@@ -2,13 +2,14 @@
 -- and records the TRUE event stream, with the effects the world applies itself (health, our rage). Test code: it
 -- allocates freely; the drive loop (drive.lua) reads the observer's flat arrays, never this.
 local rng = require("Virtual.harness.rng")
+local roll = require("Virtual.harness.behaviours").roll
 
 local M = {}
 
 --- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
 --- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
 --- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "prepull" (the cache and
---- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target".
+--- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target", "aura", "queue", "unqueue", "gain", "kill".
 function M.new(seed)
     -- crng: the client-detail draws (the same-ms avoid, a strike frame's order) apart from the fight's own
     local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), crng = rng.new(seed + 7919), ents = {} }
@@ -51,7 +52,12 @@ function M.new(seed)
             ev.damage = { w[1][1] * m, w[1][2] * m, o[1] * m, o[2] * m }
         end
         if ev.act == "WOUND" and ev.dst and (ev.kind ~= "swing" or not ev.ours) then -- ours take it at `land`
-            ev.dst.health = math.max(0, ev.dst.health - (ev.amount or 0))
+            local v = ev.dst
+            v.health = math.max(0, v.health - (ev.amount or 0))
+            if v.health <= 0 and not v.dead then -- a kill (headless loop design §2.1.5): the fight's end
+                v.dead, W.killAt = true, W.t
+                W.emit({ kind = "kill", dst = v })
+            end
         elseif ev.act == "HEAL" and ev.dst then
             ev.dst.health = math.min(ev.dst.healthMax, ev.dst.health + (ev.amount or 0))
         end
@@ -72,6 +78,110 @@ function M.new(seed)
         return e
     end
 
+    -- Runtime presses (headless loop design §2.1.4): the world's verbs, class-neutral; the content's `effect` uses only
+    -- the generic ones below.
+
+    --- The player `e` pressed `key` now. `p` is the content's resolved press { spell, cost, cooldown, gcd (seconds),
+    --- offGcd, onNextSwing, amount ({ lo, hi } of a queued strike), requires = fn(W, e) -> ok, why, effect =
+    --- fn(W, e, p) }. Checked against the true state in order: the GCD, the cooldown, the cost, a strike already queued,
+    --- `requires`; a refusal returns false and its reason ("gcd", "cooldown", "cost", "queued", "requires:<why>") and
+    --- changes nothing. An accept spends (a queued strike at its swing), starts the GCD and the cooldown, emits the
+    --- cast (or queues the strike) and runs `effect`; it returns true.
+    function W.press(e, key, p)
+        local t = W.t
+        if not p.offGcd and t < e.gcdUntil then
+            return false, "gcd"
+        elseif t < (e.cdUntil[key] or 0) then
+            return false, "cooldown"
+        elseif (p.cost or 0) > e.power then
+            return false, "cost"
+        elseif p.onNextSwing and e.queued then
+            return false, "queued"
+        end
+        if p.requires then
+            local ok, why = p.requires(W, e)
+            if not ok then
+                return false, "requires:" .. tostring(why)
+            end
+        end
+        if not p.offGcd then
+            e.gcdUntil = t + (p.gcd or 1.5)
+        end
+        if (p.cooldown or 0) > 0 then
+            e.cdUntil[key] = t + p.cooldown
+        end
+        if p.onNextSwing then
+            W.queueStrike(e, p)
+        else
+            W.emit({ kind = "cast", src = e, dst = e.target, spell = p.spell, cost = p.cost })
+        end
+        if p.effect then
+            p.effect(W, e, p)
+        end
+        return true
+    end
+
+    --- Queues `p` as `e`'s next main-hand swing (the melee behaviour turns it into a strike frame, paid then).
+    function W.queueStrike(e, p)
+        e.queued = { spell = p.spell, cost = p.cost, amount = p.amount }
+        W.emit({ kind = "queue", src = e, spell = p.spell })
+    end
+
+    --- Puts aura `id` on `dst` (ours, from the player) for `duration` s, adding `stacks` [1] up to `maxStacks` [1];
+    --- it expires on the world clock unless refreshed. Truth events "aura" { dst, aura, stacks (0: gone), expires }.
+    function W.applyAura(dst, id, duration, stacks, maxStacks)
+        local a = dst.auras[id] or { stacks = 0 }
+        a.stacks = math.min(maxStacks or 1, a.stacks + (stacks or 1))
+        a.expires, a.duration = W.t + duration, duration
+        dst.auras[id] = a
+        W.emit({ kind = "aura", dst = dst, aura = id, stacks = a.stacks, expires = a.expires, duration = duration })
+        local due = a.expires
+        W.at(due, function()
+            if dst.auras[id] == a and a.expires == due then
+                dst.auras[id] = nil
+                W.emit({ kind = "aura", dst = dst, aura = id, stacks = 0, expires = 0, duration = 0 })
+            end
+        end)
+    end
+
+    --- `n` ticks of `amount` (school 1) from `e` on `dst`, every `every` s from now.
+    function W.dot(e, dst, every, n, amount)
+        for k = 1, n do
+            W.at(W.t + k * every, function()
+                if not dst.dead then
+                    W.emit({ kind = "tick", src = e, dst = dst, act = "WOUND", flag = "", amount = amount, school = 1 })
+                end
+            end)
+        end
+    end
+
+    --- An instant outcome of `amount` (school [1]) from `e` on `dst`, rolled against the victim's avoid table and our
+    --- crit rate (a crit doubles it; an avoid is recorded in `e.avoidAt[act]`).
+    function W.hit(e, dst, amount, school)
+        local av = dst.avoid
+        local act, flag = roll(W.rng, { miss = av.miss, dodge = av.dodge, parry = av.parry, crit = M.CRIT })
+        if act ~= "WOUND" then
+            e.avoidAt[act] = W.t
+        end
+        local amt = act == "WOUND" and math.floor(amount * (flag == "CRITICAL" and 2 or 1) + 0.5) or 0
+        W.emit({ kind = "spell", src = e, dst = dst, act = act, flag = flag, amount = amt, school = school or 1 })
+    end
+
+    --- `e` gains `amount` power now (a negative amount spends it).
+    function W.gain(e, amount)
+        if amount >= 0 then
+            W.emit({ kind = "gain", src = e, rage = amount })
+        else
+            W.emit({ kind = "gain", src = e, cost = -amount })
+        end
+    end
+
+    --- Puts `e` in form `form` (an index into the client's forms; 0 none).
+    function W.setForm(e, form)
+        e.form = form
+        W.emit({ kind = "form", form = form })
+    end
+
     --- Runs the queue up to `tEnd`.
     function W.run(tEnd)
         local q = W.q
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `582 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 132 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      582 successes / 0 failures / 0 errors / 0 pending (about 92 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili tests/Virtual tools docs/dev | grep '^+' | grep -v 'Fury = 17' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|arms|fury|protection|stance|stances|sunder|sunder_armor|overpower|execute|heroic|heroic_strike|bloodrage|charge|whirlwind|rend|cleave|hamstring|slam|recklessness|intercept|pummel|mortal_strike|battle_shout|demoralizing_shout|victory_rush|thunder_clap|battle_stance|berserker_stance|defensive_stance|undead'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add tests/Forever/helpers/warrior_world.lua tests/Forever/loop_warrior_spec.lua tests/Virtual/State/helpers/fake_api.lua \
  tests/Virtual/harness/behaviours.lua tests/Virtual/harness/drive.lua tests/Virtual/harness/entities.lua \
  tests/Virtual/harness/headless.lua tests/Virtual/harness/observer.lua tests/Virtual/harness/observer_spec.lua \
  tests/Virtual/harness/press_spec.lua tests/Virtual/harness/world.lua
git commit -m "test(harness): runtime presses (W.press and the world's generic verbs), kills, the client's aura and queued-strike answers; the Warrior world mapping in tests/Forever (headless loop design §2.1.4-§2.1.5, §7)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin headless-loop`

---
### Task 4: The loop and the oracle: two instances in lockstep, the secret-free client, the self-check

Spec §2.2 (one tick: 5 Hz, Update called directly, the press policy, precombat), §2.3 (run A and run B), §4 (the oracle, `k.plain`, `o.raw`, the self-check), §8.2's C1 precombat queue, §9's smoke; Deviations 7-9, 12, 16-17.

**Files:**
- Create: `tests/Virtual/harness/loop.lua` (`loop.new`, `loop.run`, `loop.fight`; `TICK`, `REACT`, `PULL`, `GAP`, `RAW`)
- Modify: `observer.lua` (`k.plain`: `@power` with `UNIT_POWER_FREQUENT`, the target's `@health`, no `@auraError`, plain cooldown times; every cast's cooldown and the GCD as `@cooldown` flags with `SPELL_UPDATE_COOLDOWN`, on every rank `ev.ids`; usability in three states; the initial answers evaluated; the starting form at `prepull`), `drive.lua` (`@power`, `@health`, `@cooldown`; `@usable` 3 = unusable), `world.lua` (a cast carries `ids`, `cd`, `gcd`; a wound the target's health after it; `prepull` our form), `behaviours.lua` (a queued strike's `ids`), `scenarios.lua` (`scenarios.world(o, seed)`, not run; `build` = world + run; `weapons`, `mobHealth`, `pull`, `prepull`, `form`, `tag`), `headless.lua` (`o.raw`: facade rows answered by the raw client, replaced as Facade.lua loads), `fake_api.lua` (`ctl.unitHealth`, `ctl.unitHealthMax` by unit), `tests/Forever/helpers/warrior_world.lua` (`IDS` per kit ability; presses cast `VS.KnownID`; usability answers every rank in three states; `WORLD.mobHealth` 15000)
- Test: `observer_spec.lua` (new: "answers a secret-free client under k.plain: power, target health, cooldown times plain, no aura error"), `headless_spec.lua` (new: "answers the facade rows `o.raw` names with the client's raw function (the oracle's secret-free reads)"), `press_spec.lua` ("accepts a press ..." reads the cooldown flag), `tests/Forever/loop_warrior_spec.lua` (the resolve case reads the highest known rank and `ids`; new: "shows the precombat queue checkpoint C1 compares: no Battle Shout, a hostile target, no rage", "smoke: one 30 s fight, ours driving, the oracle shadowing and then driving (fast)")

**Interfaces:**
- Consumes: Tasks 1-3 (`headless.new`, `headless.cycle`, `observer.new`, `scenarios`, `drive.op`, `W.press`, the content's `character`, `PACK`, `resolve`, `usable`, `rage`, `WORLD`, `uptime`).
- Produces: `loop.new(content)` -> `L` { content, us, oracle, form, answers, uptime }; `loop.run(L, seed, o, drivers)` (drivers { { H, plain } }; `o.duration`, `o.mobHealth`, `o.hz`, `o.react`, `o.on`) -> run { W, us, ticks, presses, refused, errors, raises, misses, selfCheck, t }; `loop.fight(L, seed, o)` -> run A, run B; observer knobs `plain`, `gcdSpell`, `powerType`, `powerToken`; ops `@power`, `@health`, `@cooldown`; `scenarios.world(o, seed)`, `W.stopAt`; headless `o.raw`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/loop_warrior_spec.lua b/tests/Forever/loop_warrior_spec.lua
index c327d6f0..452547b0 100644
--- a/tests/Forever/loop_warrior_spec.lua
+++ b/tests/Forever/loop_warrior_spec.lua
@@ -1,6 +1,7 @@
 -- tests/Forever/loop_warrior_spec.lua (headless loop design §5, §7, §9): stock Hekili headless as a level 60 Arms
 -- Warrior (tests/Forever/helpers/warrior_world.lua) against the harness's world.
 local headless = require("Virtual.harness.headless")
+local loop = require("Virtual.harness.loop")
 local ww = require("Forever.helpers.warrior_world")
 
 describe("headless Arms", function()
@@ -47,10 +48,14 @@ describe("the Warrior world mapping", function()
         function()
             local ms, hs = ww.resolve("mortal_strike", H), ww.resolve("heroic_strike", H)
             local a = H.Hekili.Class.abilities
-            assert.are.same(
-                { a.mortal_strike.id, H.Hekili.State.action.mortal_strike.cost, a.mortal_strike.cooldown, false },
-                { ms.spell, ms.cost, ms.cooldown, ms.offGcd }
-            )
+            assert.are.same({ -- the rank the client casts, the highest known; every rank answers its cooldown
+                H.ns.VirtualState.KnownID(a.mortal_strike.id),
+                H.Hekili.State.action.mortal_strike.cost,
+                a.mortal_strike.cooldown,
+                false,
+            }, { ms.spell, ms.cost, ms.cooldown, ms.offGcd })
+            assert.are.equal(a.mortal_strike.id, ms.ids[1])
+            assert.are.equal(ms.spell, ms.ids[#ms.ids])
             assert.are.same(
                 { true, true, H.Hekili.State.action.heroic_strike.cost },
                 { hs.onNextSwing, hs.offGcd, hs.cost }
@@ -81,3 +86,37 @@ describe("the Warrior world mapping", function()
         end
     )
 end)
+
+describe("the headless Arms loop", function()
+    local L
+    setup(function()
+        L = loop.new(ww)
+    end)
+
+    it("shows the precombat queue checkpoint C1 compares: no Battle Shout, a hostile target, no rage", function()
+        local first
+        loop.run(L, 1, {
+            duration = 0,
+            react = -1, -- watch, press nothing
+            on = function(_, steps, t)
+                if not first and steps[1].q.name[1] then
+                    local q = steps[1].q
+                    first = { t, q.name[1], q.name[2], q.name[3] }
+                end
+            end,
+        }, { { H = L.us } })
+        print(("\nC1 headless precombat queue at %.1f s: %s %s %s"):format(unpack(first)))
+        assert.are.same({ "bloodrage", "battle_shout", "berserker_stance" }, { first[2], first[3], first[4] })
+    end)
+
+    it("smoke: one 30 s fight, ours driving, the oracle shadowing and then driving (fast)", function()
+        local a, b = loop.fight(L, 1, { duration = 30 })
+        for _, r in ipairs({ a, b }) do
+            assert.are.same({ 0, 0 }, { r.errors, r.raises })
+            assert.are.same({}, r.misses)
+            assert.is_true(r.presses > 0)
+            assert.are.same({}, r.selfCheck) -- the oracle's belief is the truth at every tick
+        end
+        assert.are.same({}, L.us.loadErrors)
+    end)
+end)
diff --git a/tests/Virtual/harness/headless_spec.lua b/tests/Virtual/harness/headless_spec.lua
index c695b5f8..fea25cca 100644
--- a/tests/Virtual/harness/headless_spec.lua
+++ b/tests/Virtual/harness/headless_spec.lua
@@ -86,6 +86,16 @@ describe("headless Hekili", function()
         assert.are.same({}, missing)
     end)
 
+    it(
+        "answers the facade rows `o.raw` names with the client's raw function (the oracle's secret-free reads)",
+        function()
+            local raw = headless.new({ raw = { "UnitHealth", "C_Spell.GetSpellCooldown" } })
+            assert.are.equal(raw.env.UnitHealth, raw.ns.Facade.UnitHealth)
+            assert.are.equal(raw.env.C_Spell.GetSpellCooldown, raw.ns.Facade.C_Spell.GetSpellCooldown)
+            assert.are_not.equal(H.env.UnitHealth, H.ns.Facade.UnitHealth)
+        end
+    )
+
     it("answers UnitIsUnit true for a unit and itself; a secret answer for two tokens stays secret", function()
         local api, ctl = fake.new()
         assert.is_true(api.UnitIsUnit("player", "player"))
diff --git a/tests/Virtual/harness/observer_spec.lua b/tests/Virtual/harness/observer_spec.lua
index e3fb356c..52be92f8 100644
--- a/tests/Virtual/harness/observer_spec.lua
+++ b/tests/Virtual/harness/observer_spec.lua
@@ -357,6 +357,54 @@ describe("the observer", function()
             assert.are.same({ { 4.2, 4.1, 101, 1 }, { 6.2, 6.2, 102, 1 } }, got)
         end
     )
+
+    it(
+        "answers a secret-free client under k.plain: power, target health, cooldown times plain, no aura error",
+        function()
+            setup()
+            local k = setmetatable({ plain = true, usableDelay = 0, gcdSpell = 900 }, { __index = observer.DEFAULTS })
+            local obs = observer.new(W, k) -- stepped as the world runs: each answer is the world's at its time
+            W.emit({ t = 1.5, kind = "prepull" })
+            obs.step(1.6)
+            W.emit({ t = 2, kind = "pull" })
+            local land = { t = 4, kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", flag = "", amount = 40 }
+            land.school, land.swing, land.rage = 1, { t = 3.5 }, 12
+            W.emit(land)
+            W.emit({
+                t = 5,
+                kind = "cast",
+                src = us,
+                dst = mob,
+                spell = 77,
+                ids = { 77, 78 },
+                cost = 10,
+                cd = 6,
+                gcd = 1.5,
+            })
+            local got = {}
+            obs.step(math.huge)
+            local s = obs.s
+            for i = 1, s.n do
+                local ev = s.ev[i]
+                if ev == "@power" or ev == "@health" or ev == "@cooldown" or ev == "@auraError" then
+                    got[#got + 1] = { s.t[i], ev, s.a1[i], s.a2[i], s.a3[i] }
+                end
+            end
+            assert.are.same({
+                { 0, "@power", 1, 0 },
+                { 1.6, "@health", "target", 1000, 1000 },
+                { 4, "@health", "target", 960, 1000 },
+                { 4, "@power", 1, 12 },
+                { 5, "@cooldown", 77, 5, 6 },
+                { 5, "@cooldown", 78, 5, 6 },
+                { 5, "@cooldown", 900, 5, 1.5 },
+                { 5, "@power", 1, 2 },
+                { 6.5, "@cooldown", 900, 0, 0 },
+                { 11, "@cooldown", 77, 0, 0 },
+                { 11, "@cooldown", 78, 0, 0 },
+            }, got)
+        end
+    )
 end)
 
 describe("the world", function()
diff --git a/tests/Virtual/harness/press_spec.lua b/tests/Virtual/harness/press_spec.lua
index 614793e9..f944af58 100644
--- a/tests/Virtual/harness/press_spec.lua
+++ b/tests/Virtual/harness/press_spec.lua
@@ -5,6 +5,7 @@ local entities = require("Virtual.harness.entities")
 local behaviours = require("Virtual.harness.behaviours")
 local observer = require("Virtual.harness.observer")
 local fs = require("Virtual.State.helpers.fake_spec")
+local fake = require("Virtual.State.helpers.fake_api")
 
 describe("the world's press", function()
     local W, us, mob
@@ -21,7 +22,8 @@ describe("the world's press", function()
     local function seen()
         local s, out = observer.observe(W), {}
         for i = 1, s.n do
-            out[#out + 1] = table.concat({ s.ev[i], tostring(s.a1[i]), tostring(s.a2[i]) }, " ")
+            local a2 = rawequal(s.a2[i], fake.SECRET) and "SECRET" or tostring(s.a2[i])
+            out[#out + 1] = table.concat({ s.ev[i], tostring(s.a1[i]), a2 }, " ")
         end
         return out
     end
@@ -67,13 +69,15 @@ describe("the world's press", function()
         }
         assert.is_true(W.press(us, "spender_c", p))
         assert.are.same({ 15, 4.5, 9, 1 }, { us.power, us.gcdUntil, us.cdUntil.spender_c, hit })
-        local got = seen() -- our target targets us: the success fires on targettarget too
+        local got = seen() -- the cooldown's flag (its times secret); our target targets us: targettarget too
         assert.are.same({
             "UNIT_SPELLCAST_SUCCEEDED player Cast-1",
+            "@cooldown " .. fs.SPENDER_C .. " SECRET",
+            "SPELL_UPDATE_COOLDOWN nil nil",
             "UNIT_SPELLCAST_SUCCEEDED targettarget Cast-1",
             "@truth 10 nil",
             "@truth 15 nil",
-        }, { got[1], got[2], got[3], got[4] })
+        }, { got[1], got[2], got[3], got[4], got[5], got[6] })
         local s = observer.observe(W)
         assert.are.equal(fs.SPENDER_C, s.a3[1])
     end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `577 successes / 3 failures / 1 error / 0 pending`.
- `loop_warrior_spec` errors at load as one suite (`module 'Virtual.harness.loop' not found`: its earlier cases do not run either); observer_spec's plain case fails (no `@power` or `@health`, an `@auraError`); headless_spec's `o.raw` case fails (the facade's own row); press_spec's "accepts" case fails (no `@cooldown`).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/helpers/warrior_world.lua b/tests/Forever/helpers/warrior_world.lua
index 1973141c..78eac195 100644
--- a/tests/Forever/helpers/warrior_world.lua
+++ b/tests/Forever/helpers/warrior_world.lua
@@ -38,6 +38,9 @@ M.KIT = {
 -- Impale 2, Improved Rend 3.
 M.TALENTS = { [12294] = 1, [12296] = 1, [12834] = 3, [12295] = 5, [16493] = 2, [12163] = 3 }
 
+-- Every rank's spell ID of each kit ability (the class file reads the usability of the highest rank known).
+M.IDS = {}
+
 -- The stances as the client's forms, in order (GetShapeshiftForm's index).
 M.FORMS = { "battle_stance", "defensive_stance", "berserker_stance" }
 M.FORM = {}
@@ -52,8 +55,12 @@ function M.character()
     local known = {}
     for _, key in ipairs(M.KIT) do
         local a = assert(w.abilities[key], key)
-        known[#known + 1] = a.id
+        local ids = { a.id }
         for _, id in ipairs(type(a.copy) == "table" and a.copy or {}) do
+            ids[#ids + 1] = id
+        end
+        M.IDS[key] = ids
+        for _, id in ipairs(ids) do
             known[#known + 1] = id
         end
     end
@@ -77,8 +84,9 @@ function M.character()
 end
 
 -- The world the loop fights in (scenarios.world's knobs): level 60 against a level 60 mob in melee range, the
--- two-hander's damage (Arcanite Reaper's range, rounded), rage capped at 100.
-M.WORLD = { level = 60, weapons = { { 150, 230, 3.6 } }, max = 100 }
+-- two-hander's damage (Arcanite Reaper's range, rounded), rage capped at 100, a mob of 15000 health (killed in about
+-- 3 minutes by this build: measured 13700-17700 damage in 3 minutes over seeds 1-3).
+M.WORLD = { level = 60, weapons = { { 150, 230, 3.6 } }, max = 100, mobHealth = 15000 }
 
 -- True rage per landed white wound: the class file's own model restated (Forever/Classes/Warrior.lua, "Rage per white
 -- swing": 4.5 x the unhasted speed with a two-hander; a crit one more base swing, 3.46 x speed). Circular on purpose:
@@ -246,7 +254,7 @@ local function stanceOk(a, e)
 end
 
 --- The resolved press of `key` (headless loop design §7), read from instance `H` (the loop passes the oracle's: its
---- state is true): the ability's ID, its cost as the state resolves it, its cooldown and GCD, on-next-swing; the
+--- state is true): the ability's known rank's ID, its cost as the state resolves it, its cooldown and GCD, on-next-swing; the
 --- mapping's requirement (after the stance's) and effect. Raises "unmapped key" for a key the mapping lacks.
 function M.resolve(key, H)
     local m = M.MAP[key]
@@ -256,7 +264,8 @@ function M.resolve(key, H)
     local a = H.Hekili.Class.abilities[key]
     local X = classData(H)
     local p = {
-        spell = a.id,
+        spell = H.ns.VirtualState.KnownID(a.id), -- the rank the client casts: the highest known
+        ids = M.IDS[key],
         cost = H.Hekili.State.action[key].cost or 0,
         cooldown = tonumber(a.cooldown) or 0,
         gcd = 1.5,
@@ -282,22 +291,26 @@ function M.resolve(key, H)
     return p
 end
 
---- The client's usability answers (observer `k.usable`) for every mapped ability the character knows, from instance
---- `H`: the power (the client's view) covers the cost, the stance fits and the mapping's requirement holds in the true
---- world (Execute's phase and Overpower's opening read these, as in game).
+--- The client's usability answers (observer `k.usable`) for every rank of every mapped ability the character knows,
+--- from instance `H`: unusable (not for power) when the stance or the mapping's requirement fails in the true world
+--- (Execute's phase, Overpower's opening, Victory Rush's kill: the class file reads these, as in game), else usable
+--- when the power (the client's view) covers the cost, short when it does not.
 function M.usable(H)
     local out = {}
+    local X = classData(H)
     for key, m in pairs(M.MAP) do
         local a = H.Hekili.Class.abilities[key]
-        if a and H.ctl.known[a.id] then
+        if a and M.IDS[key] then
             local cost = H.Hekili.State.action[key].cost or 0
-            local X = classData(H)
-            out[#out + 1] = {
-                a.id,
-                function(W, e, power)
-                    return power >= cost and stanceOk(a, e) and (not m.requires or m.requires(W, e, X)) or false
-                end,
-            }
+            local function answer(W, e, power)
+                if not stanceOk(a, e) or (m.requires and not m.requires(W, e, X)) then
+                    return false, false
+                end
+                return power >= cost, power < cost
+            end
+            for _, id in ipairs(M.IDS[key]) do
+                out[#out + 1] = { id, answer }
+            end
         end
     end
     table.sort(out, function(x, y)
diff --git a/tests/Virtual/State/helpers/fake_api.lua b/tests/Virtual/State/helpers/fake_api.lua
index 3c352b69..e657a158 100644
--- a/tests/Virtual/State/helpers/fake_api.lua
+++ b/tests/Virtual/State/helpers/fake_api.lua
@@ -52,6 +52,8 @@ function M.new()
         spellHaste = 0,
         health = 1000,
         healthMax = 1000,
+        unitHealth = {}, -- [unit] = UnitHealth (default: health)
+        unitHealthMax = {}, -- [unit] = UnitHealthMax (default: healthMax)
         totems = {},
         traits = nil, -- { config = id, trees = { tree }, nodes = { [node] = info }, entries = {}, defs = {} }
         inRange = {},
@@ -113,11 +115,11 @@ function M.new()
         end
         return r[1], r[2]
     end
-    function api.UnitHealth()
-        return ctl.health
+    function api.UnitHealth(unit)
+        return ctl.unitHealth[unit] or ctl.health
     end
-    function api.UnitHealthMax()
-        return ctl.healthMax
+    function api.UnitHealthMax(unit)
+        return ctl.unitHealthMax[unit] or ctl.healthMax
     end
     function api.UnitSpellHaste()
         return ctl.spellHaste
diff --git a/tests/Virtual/harness/behaviours.lua b/tests/Virtual/harness/behaviours.lua
index 1a5024b0..6d89c050 100644
--- a/tests/Virtual/harness/behaviours.lua
+++ b/tests/Virtual/harness/behaviours.lua
@@ -68,7 +68,7 @@ function M.melee(p)
                 local w = e.weapons[h]
                 local foreign = h == 1 and p.strikes and W.rng.chance(p.strikes)
                 if h == 1 and e.queued and e.power < (e.queued.cost or 0) then -- short at the swing: a white one
-                    W.emit({ kind = "unqueue", src = e, spell = e.queued.spell })
+                    W.emit({ kind = "unqueue", src = e, spell = e.queued.spell, ids = e.queued.ids })
                     e.queued = nil
                 end
                 if h == 1 and (e.queued or foreign) then
@@ -86,6 +86,7 @@ function M.melee(p)
                         amount = W.rng.int((q.amount or p.strike or w)[1], (q.amount or p.strike or w)[2]),
                         school = 1,
                         spell = q.spell,
+                        ids = q.ids,
                         cost = q.cost,
                         speed = w[3],
                         order = order,
diff --git a/tests/Virtual/harness/drive.lua b/tests/Virtual/harness/drive.lua
index cb092d3c..aefe2bec 100644
--- a/tests/Virtual/harness/drive.lua
+++ b/tests/Virtual/harness/drive.lua
@@ -14,7 +14,8 @@ M.WINDOW = 10 -- seconds per rage window (harness design §3.3)
 M.STEP = 9 -- one main-hand step: the overshoot bar
 local CAP = 4096
 
-local USABLE, SHORT = { true, false }, { false, true }
+local USABLE, SHORT, UNUSABLE = { true, false }, { false, true }, { false, false }
+local PLAIN_READY = { isActive = false, isOnGCD = false, startTime = 0, duration = 0 } -- a secret-free client's
 
 --- A booted VirtualState: { api, ctl, ns, VS, I, L, captures }. `o.rage` { main, off } per landed swing [9, 5],
 --- `o.max` the rage cap [1e6]; `o.damage` the UnitDamage cache's first values (default zeros: read at the pull);
@@ -184,7 +185,7 @@ local function op(c, ctl, ev, a1, a2, a3, a4, a5)
     elseif ev == "@damage" then
         ctl.damage[1], ctl.damage[2], ctl.damage[3], ctl.damage[4] = a1, a2, a3, a4
     elseif ev == "@usable" then
-        ctl.usable[a1] = a2 == 1 and USABLE or SHORT
+        ctl.usable[a1] = a2 == 1 and USABLE or (a2 == 2 and SHORT or UNUSABLE)
     elseif ev == "@form" then
         ctl.form = a1
     elseif ev == "@guid" then
@@ -203,6 +204,18 @@ local function op(c, ctl, ev, a1, a2, a3, a4, a5)
         ctl.dead[a1] = a2 or nil
     elseif ev == "@aura" then -- unit, spellID, stacks (0: gone), expires, duration: ours, from the player
         aura(ctl, a1, a2, a3, a4, a5)
+    elseif ev == "@power" then
+        ctl.power[a1] = a2
+    elseif ev == "@health" then
+        ctl.unitHealth[a1], ctl.unitHealthMax[a1] = a2, a3
+    elseif ev == "@cooldown" then -- spellID, start, duration: on cooldown; start 0: ready (plain); nil: ready (secret)
+        if a2 == nil then
+            ctl.cooldown[a1] = nil
+        elseif a2 == 0 then
+            ctl.cooldown[a1] = PLAIN_READY
+        else
+            ctl.cooldown[a1] = { isActive = true, isOnGCD = false, startTime = a2, duration = a3 }
+        end
     end
 end
 
diff --git a/tests/Virtual/harness/headless.lua b/tests/Virtual/harness/headless.lua
index f8d66db1..7eb13397 100644
--- a/tests/Virtual/harness/headless.lua
+++ b/tests/Virtual/harness/headless.lua
@@ -241,7 +241,8 @@ end
 --- A new instance: Hekili loaded and logged in. `o.character` (the content's, set before login: §1.3) {
 --- class, classID, specID, level, known = { spellID... }, talents = { [spellID] = rank }, power = { type, token, max,
 --- value (nil: secret, as on Forever) }, speed = { main, off }, items = { [slot] = { itemID, name, equipLoc } },
---- forms = { spellID... }, form }; `o.pack` the priority to select; `o.now` the clock [1000].
+--- forms = { spellID... }, form }; `o.pack` the priority to select; `o.now` the clock [1000]; `o.raw` facade rows
+--- answered by the raw client (names: the oracle's secret-free client, §4), replaced as Facade.lua loads.
 --- Returns `H = { env, api, ctl, ns, Hekili, frames, timers, misses, errors, loadErrors, prints }`.
 function M.new(o)
     o = o or {}
@@ -815,6 +816,16 @@ function M.new(o)
         if not ok then
             H.loadErrors[#H.loadErrors + 1] = path .. ": " .. tostring(e)
         end
+        if path:match("Virtual/API/Facade%.lua$") then -- o.raw: the client's raw answer for these rows (§4)
+            for _, name in ipairs(o.raw or {}) do
+                local space, key = name:match("^([%w_]+)%.([%w_]+)$")
+                if space then
+                    ns.Facade[space][key] = env[space][key]
+                else
+                    ns.Facade[name] = env[name]
+                end
+            end
+        end
     end
     local function loadXml(path)
         local fh = io.open(path)
diff --git a/tests/Virtual/harness/loop.lua b/tests/Virtual/harness/loop.lua
new file mode 100644
index 00000000..c20e69a7
--- /dev/null
+++ b/tests/Virtual/harness/loop.lua
@@ -0,0 +1,198 @@
+-- tests/Virtual/harness/loop.lua (headless loop design §2, §4): stock Hekili pressing its own first icon against the
+-- harness's world. Two instances in lockstep on one world (§2.2): ours, reading the Forever client the observer
+-- encodes, and the oracle, reading a secret-free client (k.plain, design §4/D4) with the target's health rows raw.
+-- Run A: ours drives, the oracle shadows; run B: the same seed, a fresh world, the oracle drives (§2.3).
+-- Class-neutral (the boundary rule): the content passes the character, the pack, the press resolution, the usability
+-- answers, the true rage per hit, the world's knobs and the debuff list.
+local headless = require("Virtual.harness.headless")
+local observer = require("Virtual.harness.observer")
+local scenarios = require("Virtual.harness.scenarios")
+local drive = require("Virtual.harness.drive")
+
+local M = {}
+
+M.TICK = 0.2 -- 5 Hz, the in-game combat rate (D1); o.hz = 10 the option
+M.REACT = 0.05 -- a first icon whose wait is at most this is shown as ready: pressed
+M.PULL = 3 -- the world starts this long before the pull, the target selected (precombat presses)
+M.GAP = 30 -- out of combat between two fights on one boot (consecutive pulls)
+M.RAW = { "UnitHealth", "UnitHealthMax" } -- the oracle's facade rows answered by the client (target health plain)
+
+--- Boots the two instances for `content` (one boot per busted block, §1.3): { content, us, oracle }. `content`:
+--- character(), PACK, resolve(key, H), usable(H), rage(hand, amount, flag), WORLD (scenario knobs), uptime(H).
+function M.new(content)
+    local L = { content = content }
+    local character = content.character()
+    L.form = character.form
+    L.us = headless.new({ character = character, pack = content.PACK })
+    L.oracle = headless.new({ character = character, pack = content.PACK, raw = M.RAW })
+    for _, H in ipairs({ L.us, L.oracle }) do
+        H.ctl.inRange.target = true -- shortcut: no positions, every target in melee range
+    end
+    L.answers = content.usable(L.oracle)
+    L.uptime = content.uptime(L.oracle)
+    return L
+end
+
+-- Fires the client events `obs` releases up to world time `t` into instance `H`, each at its own time (base + t).
+local function feed(H, obs, t, base, sink)
+    local s = obs.s
+    local first, last = obs.step(t)
+    local ctl = H.ctl
+    for i = first, last do
+        ctl.now = base + s.t[i]
+        local ev = s.ev[i]
+        if ev:byte(1) == 64 then -- "@"; a cooldown's start and an aura's expiry on the instance's clock
+            local a2, a4 = s.a2[i], s.a4[i]
+            if ev == "@cooldown" and type(a2) == "number" and a2 > 0 then
+                a2 = base + a2
+            elseif ev == "@aura" and a4 > 0 then
+                a4 = base + a4
+            end
+            drive.op(sink, ctl, ev, s.a1[i], a2, s.a3[i], a4, s.a5[i])
+        else
+            H.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
+        end
+    end
+end
+
+-- The first `n` entries of an instance's Primary queue into `q` (names, waits); returns how many.
+local function queue(H, q, n)
+    local recs = H.ns.UI.Displays.Primary.Recommendations
+    local k = 0
+    for i = 1, n do
+        local r = recs[i]
+        if r and r.actionName then
+            k = k + 1
+            q.name[k], q.time[k] = r.actionName, r.time or 0
+        end
+    end
+    for i = k + 1, n do
+        q.name[i], q.time[i] = false, 0
+    end
+    return k
+end
+
+--- One run of fight `seed`: the instances in `runners` (each { H, obs knobs }) stepped on one world in lockstep, the
+--- first one's first icon pressed. `o`: duration (combat seconds [180]), mobHealth, hz [5], react [REACT], on(tick)
+--- (a per-tick hook for the metrics). Returns the run { W, us, ticks, presses, refused (by reason), errors, raises,
+--- misses (unexpected run names), selfCheck (ticks where the oracle's belief missed the truth, by field) }.
+function M.run(L, seed, o, drivers)
+    o = o or {}
+    local content = L.content
+    local tick = 1 / (o.hz or 5)
+    local wo = setmetatable({
+        pull = M.PULL,
+        prepull = 0.1,
+        duration = o.duration or 180,
+        mobHealth = o.mobHealth or content.WORLD.mobHealth,
+        rage = content.rage,
+        form = L.form,
+        tag = "-" .. seed .. "-" .. #drivers, -- a fresh mob per run
+    }, { __index = content.WORLD })
+    local W = scenarios.world(wo, seed)
+    local us = W.ents[1]
+    local run = { W = W, us = us, ticks = 0, presses = 0, refused = {}, raises = 0, selfCheck = {} }
+    local sink = {}
+    local steps = {}
+    for i, d in ipairs(drivers) do
+        local ctl = d.H.ctl -- a fresh world: the client's answers about it start fresh too
+        ctl.combat, ctl.form = false, L.form
+        for _, t in ipairs({ ctl.dead, ctl.current, ctl.cooldown, ctl.usable, ctl.unitHealth, ctl.unitHealthMax }) do
+            for key in pairs(t) do
+                t[key] = nil
+            end
+        end
+        for _, list in pairs(ctl.auras) do
+            list.HELPFUL, list.HARMFUL = {}, {}
+        end
+        ctl.auraError.target = nil
+        local k = setmetatable({ usable = L.answers, gcdSpell = d.H.ns.VirtualStateInternal.GCD_SPELL }, {
+            __index = observer.DEFAULTS,
+        })
+        if d.plain then
+            k.plain, k.usableDelay = true, 0
+        end
+        local base = d.H.ctl.now + M.GAP -- this instance's clock continues from its last fight
+        steps[i] = { H = d.H, obs = observer.new(W, k), base = base, q = { name = {}, time = {} }, plain = d.plain }
+    end
+    local errors0 = {}
+    for i, st in ipairs(steps) do
+        errors0[i] = #st.H.errors
+    end
+    local stopAt = W.stopAt
+    local t = 0
+    local lastAttempt = -1
+    while t < stopAt and not W.killAt do
+        t = t + tick
+        W.run(t)
+        for _, st in ipairs(steps) do
+            feed(st.H, st.obs, t, st.base, sink)
+            local ok = headless.cycle(st.H, st.base + t)
+            if not ok then
+                run.raises = run.raises + 1
+            end
+            queue(st.H, st.q, 3)
+        end
+        run.ticks = run.ticks + 1
+        -- the oracle's self-check (§4), before this tick's press: its believed power is the true power, its target
+        -- debuffs the world's
+        for _, st in ipairs(steps) do
+            if st.plain then
+                local VS = st.H.ns.VirtualState
+                local now = st.base + t
+                local p = VS.Power(observer.DEFAULTS.powerType, now)
+                if math.abs(p.est - us.power) > 1e-6 then
+                    run.selfCheck.power = (run.selfCheck.power or 0) + 1
+                end
+                local tgt = us.target
+                for _, u in ipairs(L.uptime) do
+                    local a = tgt and tgt.auras[u[2]]
+                    local exp, stacks = VS.Aura("target", u[2], now)
+                    if (a ~= nil) ~= (exp ~= nil) or (a and a.stacks ~= stacks) then
+                        run.selfCheck[u[1]] = (run.selfCheck[u[1]] or 0) + 1
+                    end
+                end
+            end
+        end
+        -- the press policy (behaviours.recommended, §2.2 step 6): the driver's first icon, when shown as ready
+        local q = steps[1].q
+        local key = q.name[1]
+        if key and q.time[1] <= (o.react or M.REACT) and lastAttempt < t then
+            lastAttempt = t
+            local oracleH = L.oracle
+            local p = content.resolve(key, oracleH)
+            local ok, why = W.press(us, key, p)
+            if ok then
+                run.presses = run.presses + 1
+            else
+                run.refused[why] = (run.refused[why] or 0) + 1
+            end
+        end
+        if o.on then
+            o.on(run, steps, t)
+        end
+    end
+    -- the out-of-combat gap: each instance's clock moves past the fight
+    for _, st in ipairs(steps) do
+        st.H.ctl.now = st.base + t
+        headless.cycle(st.H, st.H.ctl.now)
+    end
+    run.errors, run.misses = 0, {}
+    for i, st in ipairs(steps) do
+        run.errors = run.errors + #st.H.errors - errors0[i]
+        for _, name in ipairs(headless.unexpected(st.H, "run")) do
+            run.misses[#run.misses + 1] = name
+        end
+    end
+    run.t = t
+    return run
+end
+
+--- Fight `seed`: run A (ours drives, the oracle shadows) and run B (the oracle drives a fresh world of the same seed).
+function M.fight(L, seed, o)
+    local a = M.run(L, seed, o, { { H = L.us }, { H = L.oracle, plain = true } })
+    local b = M.run(L, seed, o, { { H = L.oracle, plain = true } })
+    return a, b
+end
+
+return M
diff --git a/tests/Virtual/harness/observer.lua b/tests/Virtual/harness/observer.lua
index ab261b69..18ced175 100644
--- a/tests/Virtual/harness/observer.lua
+++ b/tests/Virtual/harness/observer.lua
@@ -23,6 +23,13 @@ M.DEFAULTS = {
     targetTokens = { "plate", "target" }, -- "plate": the target's nameplateN (P logs 1-2: nameplate1 then target)
     plainSpeed = false, -- UnitAttackSpeed of a hostile plain (Attackers.lua notes: secret on Forever)
     secretUnitIs = false, -- UnitIsUnit("<plate>target", "player") answers secret (spec §3.1: plain or secret, UNMEASURED)
+    -- A secret-free client (the headless loop's oracle, design §4/D4): our power (`powerType`, its event token
+    -- `powerToken`), the target's health and our cooldown times plain, the target's auras listed (no auraError). The
+    -- events are the same; usability without delay is the caller's `usableDelay = 0`.
+    plain = false,
+    gcdSpell = nil, -- the spell whose cooldown is the GCD (the addon's constant; nil: no GCD answers)
+    powerType = 1,
+    powerToken = "RAGE",
 }
 
 -- Our spells as the fake spec's (its costs: the usability answers).
@@ -86,9 +93,10 @@ end
 --- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`, `@auraError`,
 --- `@current` IsCurrentSpell, `@aura` an aura list entry, `@dead`), or `@truth` our true power after an event. It draws nothing from `W.rng` (the behaviours roll every
 --- random choice and record it on the truth event), so batch and incremental streams of one world are equal.
---- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power) -> bool } }
---- (the content's); `power` is the client's view of ours (a gain `usableDelay` late, a spend at once). Each answer is
---- evaluated at every power change and, stepping, at each step's end (an aura or a target's health may flip it).
+--- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power) -> ok, short } }
+--- (the content's): IsSpellUsable's two answers (usable; unusable for lack of power), `@usable` 1, 2 or 3 (unusable
+--- for another reason); `power` is the client's view of ours (a gain `usableDelay` late, a spend at once). Each answer
+--- is evaluated at every power change and, stepping, at each step's end (an aura or a target's health may flip it).
 function M.new(W, k)
     k = k or M.DEFAULTS
     local us = W.ents[1]
@@ -191,15 +199,27 @@ function M.new(W, k)
     local function read(ev)
         local t, kind = ev.t, ev.kind
         if kind == "prepull" then -- 0.5 s before the pull: the cache, then the target 0.1 s later
+            if ev.form ~= 0 then -- a fight that starts in a form (the loop's consecutive fights)
+                push(t, "@form", ev.form)
+                push(t, "UPDATE_SHAPESHIFT_FORM")
+            end
             cache(t, ev.damage)
             targets(t + 0.1, ev)
+            local v = ev.targets[us]
+            if k.plain and v then
+                push(t + 0.1, "@health", "target", v.health, v.healthMax)
+            end
         elseif kind == "pull" then
             push(t, "@combat", true)
-            push(t, "@auraError", "target", true) -- spec §3.1: the target's auras raise in combat
+            if not k.plain then
+                push(t, "@auraError", "target", true) -- spec §3.1: the target's auras raise in combat
+            end
             push(t, "PLAYER_REGEN_DISABLED")
         elseif kind == "stop" then
             push(t, "@combat", false)
-            push(t, "@auraError", "target", false)
+            if not k.plain then
+                push(t, "@auraError", "target", false)
+            end
             cache(t, ev.damage)
             push(t, "PLAYER_REGEN_ENABLED")
         elseif kind == "form" then
@@ -230,9 +250,13 @@ function M.new(W, k)
                 push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
             end
             outcome(t + 0.001, ev, 1)
-            push(t, "@current", spellID(ev.spell), false) -- IsCurrentSpell: no longer queued
+            for _, id in ipairs(ev.ids or { spellID(ev.spell) }) do
+                push(t, "@current", id, false) -- IsCurrentSpell: no longer queued
+            end
         elseif kind == "queue" or kind == "unqueue" then -- our on-next-swing press (IsCurrentSpell, plain)
-            push(t, "@current", spellID(ev.spell), kind == "queue")
+            for _, id in ipairs(ev.ids or { spellID(ev.spell) }) do
+                push(t, "@current", id, kind == "queue")
+            end
         elseif kind == "aura" then -- ours on the player (plain), ours on the target (raising in combat)
             local unit = ev.dst == us and "player" or (ev.dst == ev.ourTarget and "target" or nil)
             if unit then
@@ -250,13 +274,36 @@ function M.new(W, k)
             end
             if not left then
                 push(t, "@combat", false)
-                push(t, "@auraError", "target", false)
+                if not k.plain then
+                    push(t, "@auraError", "target", false)
+                end
                 push(t, "PLAYER_REGEN_ENABLED")
             end
         -- our cast IDs plain (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1)
         elseif kind == "cast" and ev.src == us then -- others' secret (G 49873)
             castN = castN + 1
             push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
+            -- on cooldown and the GCD (the client's GCD spell, `k.gcdSpell`): the flags plain, the times secret but
+            -- to a secret-free client
+            local function cooldown(id, d)
+                if k.plain then
+                    push(t, "@cooldown", id, t, d)
+                    push(t + d, "@cooldown", id, 0, 0)
+                else
+                    push(t, "@cooldown", id, fake.SECRET, fake.SECRET)
+                    push(t + d, "@cooldown", id)
+                end
+                push(t, "SPELL_UPDATE_COOLDOWN")
+                push(t + d, "SPELL_UPDATE_COOLDOWN")
+            end
+            if (ev.cd or 0) > 0 then -- every rank answers the spell's cooldown (`ev.ids`, the content's)
+                for _, id in ipairs(ev.ids or { spellID(ev.spell) }) do
+                    cooldown(id, ev.cd)
+                end
+            end
+            if ev.gcd and k.gcdSpell then
+                cooldown(k.gcdSpell, ev.gcd)
+            end
             if ev.onUs then -- P log 1 1345, 4329-4330, 6532: also on targettarget while our target targets us
                 push(t, "UNIT_SPELLCAST_SUCCEEDED", "targettarget", "Cast-" .. castN, spellID(ev.spell))
             end
@@ -268,7 +315,14 @@ function M.new(W, k)
         elseif ev.act and ev.dst then -- another source's outcome, our DoT's tick, a hit on us or on someone else
             outcome(t, ev, (ev.src == us) and 1 or 2)
         end
+        if k.plain and ev.health and ev.dst == ev.ourTarget then -- a secret-free client's target health
+            push(t, "@health", "target", ev.health, ev.dst.healthMax)
+        end
         if ev.power then
+            if k.plain then -- a secret-free client's power, and its event
+                push(t, "@power", k.powerType, ev.power)
+                push(t, "UNIT_POWER_FREQUENT", "player", k.powerToken)
+            end
             dseq = dseq + 1
             deltas[#deltas + 1] = { t + (ev.cost and 0 or k.usableDelay), (ev.rage or 0) - (ev.cost or 0), dseq }
             push(t, "@truth", ev.power) -- the metrics' truth (harness design §3.3), no client answer
@@ -283,7 +337,7 @@ function M.new(W, k)
             answers[i] = {
                 c[1],
                 function(_, _, p)
-                    return p >= cost
+                    return p >= cost, p < cost
                 end,
             }
         end
@@ -292,7 +346,8 @@ function M.new(W, k)
     local function answer(t)
         local flipped = false
         for _, u in ipairs(answers) do
-            local st = u[2](W, us, power) and 1 or 2
+            local ok, short = u[2](W, us, power)
+            local st = ok and 1 or (short and 2 or 3)
             if usable[u[1]] ~= st then
                 usable[u[1]] = st
                 push(t, "@usable", u[1], st)
@@ -303,12 +358,16 @@ function M.new(W, k)
             push(t, "SPELL_UPDATE_USABLE")
         end
     end
-    if answers then
+    if answers then -- the answers before anything happens (no event: the client's state at login)
         for _, u in ipairs(answers) do
-            usable[u[1]] = 2
-            push(0, "@usable", u[1], 2)
+            local ok, short = u[2](W, us, 0)
+            usable[u[1]] = ok and 1 or (short and 2 or 3)
+            push(0, "@usable", u[1], usable[u[1]])
         end
     end
+    if k.plain then
+        push(0, "@power", k.powerType, us.power)
+    end
     local function byTime(a, b)
         return a[1] < b[1] or (a[1] == b[1] and a[#a] < b[#b])
     end
diff --git a/tests/Virtual/harness/scenarios.lua b/tests/Virtual/harness/scenarios.lua
index 4efde05f..ddbc4ed5 100644
--- a/tests/Virtual/harness/scenarios.lua
+++ b/tests/Virtual/harness/scenarios.lua
@@ -44,23 +44,31 @@ M.ARCHETYPES = ARCHETYPES
 --- target), mobPeriod [2.0], mobDamage { lo, hi } [10-14], plainSpeed, damageBuff (t: +20% in combat), formAt (t),
 --- presses ({ t, spell, cost, kind }), rage ({ main, off } [9, 5]), max (our power cap [1e6]), proc, mobs (per
 --- attacker { damage = { lo, hi }, period }) and joinAt ({ [attacker] = t: on us from t }) for hits on us, switches.
-function M.build(o, seed)
+--- The headless loop's knobs: weapons (ours [entities.weapons(level)]), mobHealth (our target's [1e9]: a kill ends
+--- the fight), pull (its time [1]), prepull (the cache and target reads [pull - 0.5]), form (ours at the start [0]),
+--- tag (appended to the mobs' GUIDs: a fresh target per fight on one boot).
+--- Returns the world with every behaviour scheduled, not run (`M.build` runs it).
+function M.world(o, seed)
     local W = world.new(seed)
     local lvl = o.level or 22
-    local us = W.add(
-        entities.new({ guid = "Player-1", level = lvl, weapons = entities.weapons(lvl), powerMax = o.max or 1e6 })
-    )
+    local us = W.add(entities.new({
+        guid = "Player-1",
+        level = lvl,
+        weapons = o.weapons or entities.weapons(lvl),
+        powerMax = o.max or 1e6,
+    }))
+    us.form = o.form or 0
     local mobs = {}
     for i = 1, math.max(1, o.attackers or 1) do
         local m = o.mobs and o.mobs[i] or {}
         local dmg = m.damage or o.mobDamage or { 10, 14 }
         local mob = W.add(entities.new({
-            guid = "Creature-" .. i,
+            guid = "Creature-" .. i .. (o.tag or ""),
             kind = "mob",
             level = lvl,
             dr = i == 1 and (o.dr or 0) or 0,
             weapons = { { dmg[1], dmg[2], m.period or o.mobPeriod or 2.0 } },
-            health = 1e9,
+            health = i == 1 and o.mobHealth or 1e9,
         }))
         mob.target = (i <= (o.attackers or 1) and not (o.joinAt and o.joinAt[i])) and us or nil
         mobs[i] = mob
@@ -73,8 +81,9 @@ function M.build(o, seed)
         e.target = mobs[1]
         others[i] = { e = W.add(e), b = b }
     end
-    local pull, stop = 1, (o.duration or 120) + 1
-    W.at(pull - 0.5, function() -- out of combat: the weapon damage cache and the target (observer.lua)
+    local pull = o.pull or 1
+    local stop = (o.duration or 120) + pull
+    W.at(o.prepull or pull - 0.5, function() -- out of combat: the weapon damage cache and the target (observer.lua)
         W.emit({ kind = "prepull" })
     end)
     W.at(pull, function()
@@ -131,7 +140,14 @@ function M.build(o, seed)
         end
         W.emit({ kind = "stop" })
     end)
-    W.run(stop + 3)
+    W.stopAt = stop
+    return W
+end
+
+--- The world of one fight (M.world's knobs), run to 3 s past its end.
+function M.build(o, seed)
+    local W = M.world(o, seed)
+    W.run(W.stopAt + 3)
     return W
 end
 
diff --git a/tests/Virtual/harness/world.lua b/tests/Virtual/harness/world.lua
index 5968f710..9d1cbe8e 100644
--- a/tests/Virtual/harness/world.lua
+++ b/tests/Virtual/harness/world.lua
@@ -46,6 +46,9 @@ function M.new(seed)
                 ev.targets[e] = e.target or false
             end
         end
+        if ev.kind == "prepull" and me then -- our form at the start (the client's first form answer)
+            ev.form = me.form
+        end
         if (ev.kind == "prepull" or ev.kind == "stop") and me then -- the weapon damage UnitDamage would read now
             local w, m = me.weapons, me.dmgMult
             local o = w[2] or { 0, 0 }
@@ -54,6 +57,7 @@ function M.new(seed)
         if ev.act == "WOUND" and ev.dst and (ev.kind ~= "swing" or not ev.ours) then -- ours take it at `land`
             local v = ev.dst
             v.health = math.max(0, v.health - (ev.amount or 0))
+            ev.health = v.health -- after the wound (a secret-free client's UnitHealth)
             if v.health <= 0 and not v.dead then -- a kill (headless loop design §2.1.5): the fight's end
                 v.dead, W.killAt = true, W.t
                 W.emit({ kind = "kill", dst = v })
@@ -81,7 +85,8 @@ function M.new(seed)
     -- Runtime presses (headless loop design §2.1.4): the world's verbs, class-neutral; the content's `effect` uses only
     -- the generic ones below.
 
-    --- The player `e` pressed `key` now. `p` is the content's resolved press { spell, cost, cooldown, gcd (seconds),
+    --- The player `e` pressed `key` now. `p` is the content's resolved press { spell, ids (every rank's: the client
+    --- answers their cooldown and IsCurrentSpell together; default { spell }), cost, cooldown, gcd (seconds),
     --- offGcd, onNextSwing, amount ({ lo, hi } of a queued strike), requires = fn(W, e) -> ok, why, effect =
     --- fn(W, e, p) }. Checked against the true state in order: the GCD, the cooldown, the cost, a strike already queued,
     --- `requires`; a refusal returns false and its reason ("gcd", "cooldown", "cost", "queued", "requires:<why>") and
@@ -113,7 +118,17 @@ function M.new(seed)
         if p.onNextSwing then
             W.queueStrike(e, p)
         else
-            W.emit({ kind = "cast", src = e, dst = e.target, spell = p.spell, cost = p.cost })
+            local gcd = not p.offGcd and (p.gcd or 1.5) or nil
+            W.emit({
+                kind = "cast",
+                src = e,
+                dst = e.target,
+                spell = p.spell,
+                ids = p.ids,
+                cost = p.cost,
+                cd = p.cooldown,
+                gcd = gcd,
+            })
         end
         if p.effect then
             p.effect(W, e, p)
@@ -123,8 +138,8 @@ function M.new(seed)
 
     --- Queues `p` as `e`'s next main-hand swing (the melee behaviour turns it into a strike frame, paid then).
     function W.queueStrike(e, p)
-        e.queued = { spell = p.spell, cost = p.cost, amount = p.amount }
-        W.emit({ kind = "queue", src = e, spell = p.spell })
+        e.queued = { spell = p.spell, ids = p.ids, cost = p.cost, amount = p.amount }
+        W.emit({ kind = "queue", src = e, spell = p.spell, ids = p.ids })
     end
 
     --- Puts aura `id` on `dst` (ours, from the player) for `duration` s, adding `stacks` [1] up to `maxStacks` [1];
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `586 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 133 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      586 successes / 0 failures / 0 errors / 0 pending (about 94 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili tests/Virtual tools docs/dev | grep '^+' | grep -v 'Fury = 17' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|arms|fury|protection|stance|stances|sunder|sunder_armor|overpower|execute|heroic|heroic_strike|bloodrage|charge|whirlwind|rend|cleave|hamstring|slam|recklessness|intercept|pummel|mortal_strike|battle_shout|demoralizing_shout|victory_rush|thunder_clap|battle_stance|berserker_stance|defensive_stance|undead'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add tests/Forever/helpers/warrior_world.lua tests/Forever/loop_warrior_spec.lua tests/Virtual/State/helpers/fake_api.lua \
  tests/Virtual/harness/behaviours.lua tests/Virtual/harness/drive.lua tests/Virtual/harness/headless.lua \
  tests/Virtual/harness/headless_spec.lua tests/Virtual/harness/loop.lua tests/Virtual/harness/observer.lua \
  tests/Virtual/harness/observer_spec.lua tests/Virtual/harness/press_spec.lua tests/Virtual/harness/scenarios.lua \
  tests/Virtual/harness/world.lua
git commit -m "test(headless): the loop and the oracle: two instances in lockstep at 5 Hz, a secret-free client, the self-check; the client's cooldown and GCD flags, three-state usability, the highest known rank (headless loop design §2.2-§2.3, §4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin headless-loop`

---
### Task 5: The metrics and the Arms gates; the party report behind make test-party

Spec §5.1 (the metrics), §5.2 (the gates), Decisions D1-D5; Deviations 10-11, 13-15, 18.

**Files:**
- Modify: `tests/Virtual/harness/loop.lua` (the per-tick record: agreement, both first icons, refusals and episodes, full power, GCD idle, uptimes, the belief's power gap, CPU per Update; `o.reaction`, `o.others`, `o.trace` (the facade's trace, `Hekili.Debug` and `SaveDebugSnapshot` stubbed meanwhile; `Facade.secrets` collected); the target's level plain; `RAW` adds the debuff row; the self-check reads the facade's debuff row; `loop.tally`, `loop.summary`, `loop.line`), `tests/Virtual/State/helpers/fake_api.lua` (`C_UnitAuras.GetBuffDataByIndex`, `GetDebuffDataByIndex`: absent on Forever, the oracle's raw rows), `Makefile` (`test` excludes `#party`, `test-fast` excludes `slow,party`, `test-party`)
- Test: `tests/Forever/loop_warrior_spec.lua` (new: "Arms solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's" `#slow`; "Arms in a party of 5, a melee and a caster on our target, 10 fights: reported" `#party`)

**Interfaces:**
- Consumes: Task 4's loop.
- Produces: `loop.tally(L, n, o)` -> m { fights, both, agree, conf, react, refused, attempts, refusedB, attemptsB, episodes, A, B { combat, full, idle, up, damage, time, flicker }, oracleFlicker, errors, raises, misses, secrets, selfCheck, cpu, gap }; `loop.summary(m)` -> { agreement, reactMedian, reactP90, never, per100, per100B, episodes, dps, fullA/B, idleA/B, upA/B, flicker, oracleFlicker, cpuMean, cpuP99 }; `loop.line(m)`; `make test-party`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/loop_warrior_spec.lua b/tests/Forever/loop_warrior_spec.lua
index 452547b0..18442b54 100644
--- a/tests/Forever/loop_warrior_spec.lua
+++ b/tests/Forever/loop_warrior_spec.lua
@@ -120,3 +120,38 @@ describe("the headless Arms loop", function()
         assert.are.same({}, L.us.loadErrors)
     end)
 end)
+
+-- The gates (headless loop design §5.2; as built: the plan's Deviations 7-8). Measured on the plan's replay: 20 fights,
+-- agreement 0.965, react median 0 / p90 0 / never 0.063, cost refusals 17.3 per 100 attempts (the oracle's own 15.9),
+-- DPS A/B 0.985, GCD idle 0.745 / 0.740, Sunder Armor up 0.94 / 0.95, flicker 0.68/min, CPU mean 2.60 ms.
+describe("the headless Arms gates #slow", function()
+    it("Arms solo, level 60, one mob, 20 fights of up to 3 minutes: the first icon against the oracle's", function()
+        local m = loop.tally(loop.new(ww), 20)
+        local r, line = loop.summary(m), loop.line(m)
+        print("\nArms solo: " .. line)
+        assert.is_true(r.agreement >= 0.85, line)
+        assert.is_true(r.reactMedian <= 1 and r.reactP90 <= 3 and r.never <= 0.08, line)
+        assert.is_true((r.per100.gcd or 0) == 0 and (r.per100.cooldown or 0) == 0, line)
+        assert.is_true((r.per100.cost or 0) <= (r.per100B.cost or 0) + 3, line)
+        assert.is_true(r.dps >= 0.97, line)
+        assert.is_true(r.fullA <= r.fullB + 0.03 and r.idleA <= r.idleB + 0.03, line)
+        for key, up in pairs(r.upB) do
+            assert.is_true((r.upA[key] or 0) >= up - 0.03, key .. ": " .. line)
+        end
+        assert.is_true(r.flicker <= 2, line)
+        assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
+        assert.are.same({}, m.misses)
+        assert.are.same({}, m.secrets) -- no facade passthrough answered a secret (the traced first fight)
+        assert.is_true(r.cpuMean <= 10, line) -- D5: about 4x the measured mean; p99 reported
+    end)
+end)
+
+-- The party report (§5.2): reported, engine health gated; `make test-party`, not `make check` (D2).
+describe("the headless Arms party report #party", function()
+    it("Arms in a party of 5, a melee and a caster on our target, 10 fights: reported", function()
+        local m = loop.tally(loop.new(ww), 10, { others = { "melee", "caster" } })
+        print("\nArms party: " .. loop.line(m))
+        assert.are.same({ 0, 0, 0 }, { m.errors, m.raises, m.selfCheck })
+        assert.are.same({}, m.misses)
+    end)
+end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `586 successes / 0 failures / 2 errors / 0 pending`.
- The gate and the party report error (`attempt to call field 'tally' (a nil value)`): plain `busted` runs every tag, `#party` included.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/Makefile b/Makefile
index baf5ba9c..133cef8e 100644
--- a/Makefile
+++ b/Makefile
@@ -5,7 +5,7 @@ BUSTED := $(LUA_ENV)/bin/busted
 LUACHECK := $(LUA_ENV)/bin/luacheck
 LUAC := $(LUA_ENV)/bin/luac
 
-.PHONY: bootstrap lint fmt fmt-check typecheck test test-fast syntax api-check check
+.PHONY: bootstrap lint fmt fmt-check typecheck test test-fast test-party syntax api-check check
 
 bootstrap:
 	scripts/bootstrap.sh
@@ -22,12 +22,16 @@ fmt-check:
 typecheck:
 	lua-language-server --check . --checklevel=Error --logpath $(LUA_ENV)/lsp-log
 
+# The headless loop's party report (#party) runs only behind `make test-party` (about 1 minute).
 test:
-	$(BUSTED)
+	$(BUSTED) --exclude-tags=party
 
 # The edit loop: skips the harness gate specs tagged #slow (hundreds of simulated fights); `make check` runs them.
 test-fast:
-	$(BUSTED) --exclude-tags=slow
+	$(BUSTED) --exclude-tags=slow,party
+
+test-party:
+	$(BUSTED) --tags=party
 
 syntax:
 	git ls-files -z '*.lua' | xargs -0 -n 200 $(LUAC) -p
diff --git a/tests/Virtual/State/helpers/fake_api.lua b/tests/Virtual/State/helpers/fake_api.lua
index e657a158..a2b52b8c 100644
--- a/tests/Virtual/State/helpers/fake_api.lua
+++ b/tests/Virtual/State/helpers/fake_api.lua
@@ -237,6 +237,13 @@ function M.new()
             return list and list[i]
         end,
     }
+    -- absent on Forever (the facade's virtual rows); a secret-free client's, for the headless loop's oracle (o.raw)
+    function api.C_UnitAuras.GetBuffDataByIndex(unit, i)
+        return api.C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
+    end
+    function api.C_UnitAuras.GetDebuffDataByIndex(unit, i)
+        return api.C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
+    end
     api.C_ClassTalents = {
         GetActiveConfigID = function()
             return ctl.traits and ctl.traits.config
diff --git a/tests/Virtual/harness/loop.lua b/tests/Virtual/harness/loop.lua
index c20e69a7..9f61d5f9 100644
--- a/tests/Virtual/harness/loop.lua
+++ b/tests/Virtual/harness/loop.lua
@@ -15,7 +15,11 @@ M.TICK = 0.2 -- 5 Hz, the in-game combat rate (D1); o.hz = 10 the option
 M.REACT = 0.05 -- a first icon whose wait is at most this is shown as ready: pressed
 M.PULL = 3 -- the world starts this long before the pull, the target selected (precombat presses)
 M.GAP = 30 -- out of combat between two fights on one boot (consecutive pulls)
-M.RAW = { "UnitHealth", "UnitHealthMax" } -- the oracle's facade rows answered by the client (target health plain)
+-- The oracle's facade rows answered by the client (§4's override): the target's health, and the debuff row Hekili's
+-- aura scan reads (VirtualState counts a modelled stack on top of a plain read that arrives before the cast's drain:
+-- the self-check measured a stacking debuff at 2 believed stacks with 1 up). The buff row stays VirtualState's: our
+-- forms become buffs in the belief, and the client's list does not hold them.
+M.RAW = { "UnitHealth", "UnitHealthMax", "C_UnitAuras.GetDebuffDataByIndex" }
 
 --- Boots the two instances for `content` (one boot per busted block, §1.3): { content, us, oracle }. `content`:
 --- character(), PACK, resolve(key, H), usable(H), rage(hand, amount, flag), WORLD (scenario knobs), uptime(H).
@@ -72,10 +76,14 @@ local function queue(H, q, n)
     return k
 end
 
---- One run of fight `seed`: the instances in `runners` (each { H, obs knobs }) stepped on one world in lockstep, the
---- first one's first icon pressed. `o`: duration (combat seconds [180]), mobHealth, hz [5], react [REACT], on(tick)
---- (a per-tick hook for the metrics). Returns the run { W, us, ticks, presses, refused (by reason), errors, raises,
---- misses (unexpected run names), selfCheck (ticks where the oracle's belief missed the truth, by field) }.
+--- One run of fight `seed`: the instances in `drivers` (each { H, plain }) stepped on one world in lockstep, the
+--- first one's first icon pressed. `o`: duration (combat seconds [180]), mobHealth, hz [5], react [REACT], reaction
+--- (seconds an icon shows ready before the press [0]), others (archetypes on our target), trace (the facade's trace
+--- each tick), on(run, steps, t) (a per-tick hook). Returns the run { W, us, ticks, presses, refused (by reason),
+--- attempts, episodes, errors, raises, misses (unexpected run names), secrets (Facade.secrets), selfCheck (ticks where
+--- the oracle's belief missed the truth, by field), combat, full, idle, up (by debuff key: in-combat ticks), ours and
+--- theirs (first icons by in-combat tick), gap (believed minus true power where they differ), cpu (ms per Update of
+--- the first instance), damage, t }.
 function M.run(L, seed, o, drivers)
     o = o or {}
     local content = L.content
@@ -88,10 +96,14 @@ function M.run(L, seed, o, drivers)
         rage = content.rage,
         form = L.form,
         tag = "-" .. seed .. "-" .. #drivers, -- a fresh mob per run
+        others = o.others, -- other sources on our target (scenarios.ARCHETYPES: the party report)
     }, { __index = content.WORLD })
     local W = scenarios.world(wo, seed)
     local us = W.ents[1]
     local run = { W = W, us = us, ticks = 0, presses = 0, refused = {}, raises = 0, selfCheck = {} }
+    -- the metrics' per-tick record (§5.1): in-combat ticks only, both queues' first icons, the truth
+    run.combat, run.full, run.idle, run.attempts, run.episodes, run.up = 0, 0, 0, 0, 0, {}
+    run.ours, run.theirs, run.gap, run.cpu, run.secrets = {}, {}, {}, {}, {}
     local sink = {}
     local steps = {}
     for i, d in ipairs(drivers) do
@@ -106,6 +118,8 @@ function M.run(L, seed, o, drivers)
             list.HELPFUL, list.HARMFUL = {}, {}
         end
         ctl.auraError.target = nil
+        -- UnitLevel is plain in combat on Forever (the facade's passthrough row); fake_api answers an unset unit secret
+        ctl.level.target, ctl.level.nameplate1 = wo.level, wo.level
         local k = setmetatable({ usable = L.answers, gcdSpell = d.H.ns.VirtualStateInternal.GCD_SPELL }, {
             __index = observer.DEFAULTS,
         })
@@ -121,19 +135,38 @@ function M.run(L, seed, o, drivers)
     end
     local stopAt = W.stopAt
     local t = 0
-    local lastAttempt = -1
+    local lastAttempt, lastRefused, readySince = -1, false, {}
+    local traced = {}
+    if o.trace then -- the facade's trace (§5.1): Hekili's own debug pass, its lines counted and dropped
+        for i, st in ipairs(steps) do
+            local hk = st.H.Hekili
+            traced[i] = { hk.Debug, hk.SaveDebugSnapshot }
+            hk.Debug = function() end
+            hk.SaveDebugSnapshot = function()
+                return false
+            end
+        end
+    end
     while t < stopAt and not W.killAt do
         t = t + tick
         W.run(t)
-        for _, st in ipairs(steps) do
+        for i, st in ipairs(steps) do
             feed(st.H, st.obs, t, st.base, sink)
+            st.H.Hekili.ActiveDebug = o.trace or false
+            local c0 = os.clock()
             local ok = headless.cycle(st.H, st.base + t)
+            if i == 1 then
+                run.cpu[#run.cpu + 1] = (os.clock() - c0) * 1000
+            end
+            st.H.Hekili.ActiveDebug = false
             if not ok then
                 run.raises = run.raises + 1
             end
             queue(st.H, st.q, 3)
         end
         run.ticks = run.ticks + 1
+        local inCombat = t >= wo.pull
+        local gcdFree = us.gcdUntil <= t
         -- the oracle's self-check (§4), before this tick's press: its believed power is the true power, its target
         -- debuffs the world's
         for _, st in ipairs(steps) do
@@ -145,27 +178,73 @@ function M.run(L, seed, o, drivers)
                     run.selfCheck.power = (run.selfCheck.power or 0) + 1
                 end
                 local tgt = us.target
+                local debuff = st.H.ns.Facade.C_UnitAuras.GetDebuffDataByIndex -- what Hekili's aura scan reads
                 for _, u in ipairs(L.uptime) do
                     local a = tgt and tgt.auras[u[2]]
-                    local exp, stacks = VS.Aura("target", u[2], now)
-                    if (a ~= nil) ~= (exp ~= nil) or (a and a.stacks ~= stacks) then
+                    local seen
+                    for i = 1, 40 do
+                        local d = debuff("target", i)
+                        if not d then
+                            break
+                        elseif d.spellId == u[2] then
+                            seen = d
+                        end
+                    end
+                    -- up: expiring after this tick, on each side's clock (a tick and an expiry can meet within a ulp)
+                    local up = a ~= nil and a.expires > t + 1e-6
+                    local upSeen = seen ~= nil and seen.expirationTime > now + 1e-6
+                    if up ~= upSeen or (up and a.stacks ~= seen.applications) then
                         run.selfCheck[u[1]] = (run.selfCheck[u[1]] or 0) + 1
                     end
                 end
             end
         end
-        -- the press policy (behaviours.recommended, §2.2 step 6): the driver's first icon, when shown as ready
+        -- the press policy (§2.2 step 6): the driver's first icon, once it has shown as ready for `o.reaction` s
         local q = steps[1].q
         local key = q.name[1]
-        if key and q.time[1] <= (o.react or M.REACT) and lastAttempt < t then
+        local gcdPress, refusedKey = false, false
+        local shown = key and q.time[1] <= (o.react or M.REACT)
+        if shown then
+            readySince[key] = readySince[key] or t
+        end
+        for k in pairs(readySince) do
+            if k ~= key or not shown then
+                readySince[k] = nil
+            end
+        end
+        if shown and t - readySince[key] >= (o.reaction or 0) - 1e-9 and lastAttempt < t then
             lastAttempt = t
-            local oracleH = L.oracle
-            local p = content.resolve(key, oracleH)
+            local p = content.resolve(key, L.oracle)
             local ok, why = W.press(us, key, p)
+            if inCombat then
+                run.attempts = run.attempts + 1
+            end
             if ok then
                 run.presses = run.presses + 1
+                gcdPress = not p.offGcd
             else
                 run.refused[why] = (run.refused[why] or 0) + 1
+                refusedKey = key
+                if inCombat and lastRefused ~= key then
+                    run.episodes = run.episodes + 1 -- a refusal episode: consecutive refused ticks of one key
+                end
+            end
+        end
+        lastRefused = refusedKey
+        if inCombat then
+            local n = run.combat + 1
+            run.combat = n
+            run.full = run.full + (us.power >= us.powerMax and 1 or 0)
+            run.idle = run.idle + ((gcdFree and not gcdPress) and 1 or 0)
+            local tgt = us.target
+            for _, u in ipairs(L.uptime) do
+                run.up[u[1]] = (run.up[u[1]] or 0) + ((tgt and tgt.auras[u[2]]) and 1 or 0)
+            end
+            run.ours[n] = steps[1].q.name[1]
+            run.theirs[n] = steps[2] and steps[2].q.name[1] or false
+            if steps[2] and run.ours[n] ~= run.theirs[n] then -- the belief's power error where they disagree
+                local VS = steps[1].H.ns.VirtualState
+                run.gap[#run.gap + 1] = VS.Power(observer.DEFAULTS.powerType, steps[1].base + t).est - us.power
             end
         end
         if o.on then
@@ -173,9 +252,21 @@ function M.run(L, seed, o, drivers)
         end
     end
     -- the out-of-combat gap: each instance's clock moves past the fight
-    for _, st in ipairs(steps) do
+    for i, st in ipairs(steps) do
         st.H.ctl.now = st.base + t
         headless.cycle(st.H, st.H.ctl.now)
+        if traced[i] then
+            st.H.Hekili.Debug, st.H.Hekili.SaveDebugSnapshot = traced[i][1], traced[i][2]
+        end
+        for name, n in pairs(st.H.ns.Facade.secrets) do
+            run.secrets[name] = (run.secrets[name] or 0) + n
+        end
+    end
+    run.damage = 0 -- our true damage dealt (white wounds count at their land)
+    for _, ev in ipairs(W.truth) do
+        if ev.src == us and ev.act == "WOUND" and ev.kind ~= "swing" then
+            run.damage = run.damage + (ev.amount or 0)
+        end
     end
     run.errors, run.misses = 0, {}
     for i, st in ipairs(steps) do
@@ -195,4 +286,212 @@ function M.fight(L, seed, o)
     return a, b
 end
 
+-- A -> B -> A within 3 ticks in a first-icon sequence.
+local function flicker(seq, n)
+    local f = 0
+    for i = 1, n - 2 do
+        if seq[i] ~= seq[i + 1] and seq[i + 2] == seq[i] then
+            f = f + 1
+        end
+    end
+    return f
+end
+
+-- Cycles to react (§5.1): for each change of the oracle's first icon to X lasting >= 2 ticks, the ticks until ours
+-- shows X, censored at the oracle's next change (-1: never). Appends to `out`.
+local function reactions(ours, theirs, n, out)
+    for i = 2, n - 1 do
+        local x = theirs[i]
+        if x and x ~= theirs[i - 1] and theirs[i + 1] == x then
+            local d = -1
+            for j = i, n do
+                if theirs[j] ~= x then
+                    break
+                elseif ours[j] == x then
+                    d = j - i
+                    break
+                end
+            end
+            out[#out + 1] = d
+        end
+    end
+end
+
+--- `n` fights (seeds 1..n, from `o.seed0` + 1) on `L`'s boot: run A and run B each, tallied (§5.1). The first fight
+--- runs traced when `o.trace` is unset (one per scenario: the facade's secret passthroughs). Returns the tally.
+function M.tally(L, n, o)
+    o = o or {}
+    local m = { fights = 0, both = 0, agree = 0, conf = {}, react = {}, refused = {}, attempts = 0, episodes = 0 }
+    m.refusedB, m.attemptsB = {}, 0 -- the oracle's own, driving run B (the projection's share: §5.2 as built)
+    m.A = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
+    m.B = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
+    m.oracleFlicker, m.errors, m.raises, m.misses, m.secrets, m.selfCheck = 0, 0, 0, {}, {}, 0
+    m.cpu, m.gap = {}, {}
+    for f = 1, n do
+        local seed = (o.seed0 or 0) + f
+        local po = setmetatable({ trace = o.trace == nil and f == 1 or o.trace }, { __index = o })
+        local a, b = M.fight(L, seed, po)
+        m.fights = m.fights + 1
+        for i = 1, a.combat do
+            local x, y = a.ours[i], a.theirs[i]
+            if x and y then
+                m.both = m.both + 1
+                if x == y then
+                    m.agree = m.agree + 1
+                else
+                    local key = y .. " -> " .. x
+                    m.conf[key] = (m.conf[key] or 0) + 1
+                end
+            end
+        end
+        reactions(a.ours, a.theirs, a.combat, m.react)
+        for why, k in pairs(a.refused) do
+            m.refused[why] = (m.refused[why] or 0) + k
+        end
+        m.attempts, m.episodes = m.attempts + a.attempts, m.episodes + a.episodes
+        for why, k in pairs(b.refused) do
+            m.refusedB[why] = (m.refusedB[why] or 0) + k
+        end
+        m.attemptsB = m.attemptsB + b.attempts
+        m.oracleFlicker = m.oracleFlicker + flicker(a.theirs, a.combat)
+        for side, r in pairs({ A = a, B = b }) do
+            local s = m[side]
+            s.combat, s.full, s.idle = s.combat + r.combat, s.full + r.full, s.idle + r.idle
+            s.damage, s.time = s.damage + r.damage, s.time + r.combat / (o.hz or 5)
+            s.flicker = s.flicker + flicker(r.ours, r.combat)
+            for key, k in pairs(r.up) do
+                s.up[key] = (s.up[key] or 0) + k
+            end
+        end
+        for _, r in ipairs({ a, b }) do
+            m.errors, m.raises = m.errors + r.errors, m.raises + r.raises
+            for _, name in ipairs(r.misses) do
+                m.misses[name] = true
+            end
+            for name in pairs(r.secrets) do
+                m.secrets[name] = true
+            end
+            for _, k in pairs(r.selfCheck) do
+                m.selfCheck = m.selfCheck + k
+            end
+        end
+        for _, ms in ipairs(a.cpu) do
+            m.cpu[#m.cpu + 1] = ms
+        end
+        for _, g in ipairs(a.gap) do
+            m.gap[#m.gap + 1] = g
+        end
+    end
+    return m
+end
+
+-- The `p` quantile of a list (sorted in place).
+local function quantile(list, p)
+    table.sort(list)
+    return list[math.max(1, math.ceil(p * #list))] or 0
+end
+
+--- The tally's derived metrics: agreement, react (median, p90, share never; in ticks), refusals per 100 attempts by
+--- reason, episodes per minute, damage per second A / B, full-power and GCD-idle shares and debuff uptimes (A, B),
+--- flicker per minute (ours, the oracle's), CPU per Update (mean, p99 ms).
+function M.summary(m)
+    local r = {}
+    r.agreement = m.agree / math.max(1, m.both)
+    local reacted, never = {}, 0
+    for _, d in ipairs(m.react) do
+        if d < 0 then
+            never = never + 1
+        else
+            reacted[#reacted + 1] = d
+        end
+    end
+    r.reactMedian, r.reactP90 = quantile(reacted, 0.5), quantile(reacted, 0.9)
+    r.never = never / math.max(1, #m.react)
+    r.per100, r.per100B = {}, {}
+    for why, k in pairs(m.refused) do
+        r.per100[why] = 100 * k / math.max(1, m.attempts)
+    end
+    for why, k in pairs(m.refusedB) do
+        r.per100B[why] = 100 * k / math.max(1, m.attemptsB)
+    end
+    local minutes = m.A.time / 60
+    r.episodes = m.episodes / math.max(1e-9, minutes)
+    r.dps = (m.A.damage / math.max(1e-9, m.A.time)) / math.max(1e-9, m.B.damage / math.max(1e-9, m.B.time))
+    for _, side in ipairs({ "A", "B" }) do
+        local s = m[side]
+        r["full" .. side], r["idle" .. side] = s.full / math.max(1, s.combat), s.idle / math.max(1, s.combat)
+        r["up" .. side] = {}
+        for key, k in pairs(s.up) do
+            r["up" .. side][key] = k / math.max(1, s.combat)
+        end
+    end
+    r.flicker, r.oracleFlicker = m.A.flicker / math.max(1e-9, minutes), m.oracleFlicker / math.max(1e-9, minutes)
+    local sum = 0
+    for _, ms in ipairs(m.cpu) do
+        sum = sum + ms
+    end
+    r.cpuMean, r.cpuP99 = sum / math.max(1, #m.cpu), quantile(m.cpu, 0.99)
+    return r
+end
+
+--- One line for a failure message: the summary, the confusion table's top three disagreements (oracle -> ours) and
+--- the believed power minus the truth where they disagree (mean), reported, never gated.
+function M.line(m)
+    local r = M.summary(m)
+    local conf = {}
+    for key, k in pairs(m.conf) do
+        conf[#conf + 1] = { key, k }
+    end
+    table.sort(conf, function(x, y)
+        return x[2] > y[2] or (x[2] == y[2] and x[1] < y[1])
+    end)
+    local top = {}
+    for i = 1, math.min(3, #conf) do
+        top[i] = conf[i][1] .. " " .. conf[i][2]
+    end
+    local refused = {}
+    for why, v in pairs(r.per100) do
+        refused[#refused + 1] = ("%s %.1f (oracle %.1f)"):format(why, v, r.per100B[why] or 0)
+    end
+    table.sort(refused)
+    local up = {}
+    for key, v in pairs(r.upA) do
+        up[#up + 1] = ("%s %.2f/%.2f"):format(key, v, r.upB[key] or 0)
+    end
+    table.sort(up)
+    local gap = 0
+    for _, g in ipairs(m.gap) do
+        gap = gap + g
+    end
+    return (
+        "fights=%d agreement %.3f (%d ticks); react median %d p90 %d never %.3f; refused per 100 [%s], episodes %.2f/min; "
+        .. "dps A/B %.3f; full %.3f/%.3f idle %.3f/%.3f; uptime [%s]; flicker %.2f/min (oracle %.2f); "
+        .. "errors %d raises %d self-check %d; cpu mean %.2f p99 %.2f ms; top [%s]; power est-truth at disagreements %.1f"
+    ):format(
+        m.fights,
+        r.agreement,
+        m.both,
+        r.reactMedian,
+        r.reactP90,
+        r.never,
+        table.concat(refused, ", "),
+        r.episodes,
+        r.dps,
+        r.fullA,
+        r.fullB,
+        r.idleA,
+        r.idleB,
+        table.concat(up, ", "),
+        r.flicker,
+        r.oracleFlicker,
+        m.errors,
+        m.raises,
+        m.selfCheck,
+        r.cpuMean,
+        r.cpuP99,
+        table.concat(top, "; "),
+        gap / math.max(1, #m.gap)
+    )
+end
+
 return M
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `588 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 133 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      587 successes / 0 failures / 0 errors / 0 pending (about 232 s; make test excludes the #party report)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili tests/Virtual tools docs/dev | grep '^+' | grep -v 'Fury = 17' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|arms|fury|protection|stance|stances|sunder|sunder_armor|overpower|execute|heroic|heroic_strike|bloodrage|charge|whirlwind|rend|cleave|hamstring|slam|recklessness|intercept|pummel|mortal_strike|battle_shout|demoralizing_shout|victory_rush|thunder_clap|battle_stance|berserker_stance|defensive_stance|undead'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add Makefile tests/Forever/loop_warrior_spec.lua tests/Virtual/State/helpers/fake_api.lua tests/Virtual/harness/loop.lua
git commit -m "test(headless): the loop's metrics and the Arms solo gate (#slow); the party report behind make test-party, not make check (headless loop design §5, D1-D5)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin headless-loop`

---
### Task 6: CHECKPOINT: the precombat queue in game (spec §8.2 C1), deferred to the user

Not a blocker: the branch can be reviewed and merged with this task open. No code unless the comparison calls for it (then the character or the pack loading in `warrior_world.lua` is fixed in its own commit with the verification block, before the gates are trusted).

- [ ] **Step 1: Point the client at the branch** (when the user is ready to play)

```bash
git push origin headless-loop
git -C ~/src/hekili checkout --detach headless-loop
```

Then `/reload` in game (no new file).

- [ ] **Step 2: CHECKPOINT: ask the user to run the following in game and paste each answer**

ForeverProbe loaded (`VSCopy`). Arms (the Arms priority selected), level 60, Battle Stance, no Battle Shout up, no rage, out of combat, a hostile open-world mob targeted in melee range (no dummies). Every line is under 255 characters.

| # | Question | Line(s) | Answer -> action |
|---|---|---|---|
| C1 | headless and in-game precombat queues agree | `/run local t={}for i=1,3 do t[i]=tostring(Hekili_GetRecommendedAbility("Primary",i))end VSCopy(GetTime(),UnitAffectingCombat("player"),unpack(t))` and the talent export the Protection checkpoint uses | the headless queue for the same talents and buffs is `bloodrage, battle_shout, berserker_stance` (loop_warrior_spec "shows the precombat queue checkpoint C1 compares ..."; `Hekili_GetRecommendedAbility` answers ability keys or IDs as the in-game build does: compare by ability). Equal -> none. Different -> the character (kit, talents: `warrior_world.TALENTS` holds the SPIKE's build, not the user's export) or the pack loading differs: fix the content to the export, re-run the case and the gate, before trusting the gates |

Known limits (say them with the result):
- The headless character's talents are the SPIKE's Arms build (Mortal Strike, Anger Management, Deep Wounds 3, Tactical Mastery 5, Impale 2, Improved Rend 3); a different in-game build can change the precombat queue without any fault.
- No in-combat checkpoint: the loop exists because the in-game truth (true rage, true auras) is unreadable there (§8.2).

When the session ends: `git -C ~/src/hekili checkout --detach forever`.

---

## Self-Review

**1. Coverage of the spec**

| Spec | Task |
|---|---|
| §1.1 one instance one environment, `loadstring` bound, the real `_G` untouched, `string.trim`/`split` process-wide | 1 (Deviation 1) |
| §1.2 every stub in one file, client answers in fake_api only | 1 |
| §1.3 loader (the TOC, XML Script/Include, PopupSlider skipped), clock, C_Timer, the character before login, login, the boot cost | 1 (Deviation 2) |
| §1.4 the miss counter by phase, `KNOWN_LOAD_NILS`, `KNOWN_RUN_NILS` | 1 (Deviation 3), 4-5 (run misses asserted per fight) |
| §2.1.1 the incremental observer, `observe` = new + one step | 2 |
| §2.1.2 no RNG in observation, batch = incremental, the gates re-measured | 2 (Deviations 5-6) |
| §2.1.3 usability from the content | 2 (the knob), 3 (the Warrior answers), 4 (three states: Deviation 7) |
| §2.1.4 `W.press`, the refusal order and reasons, the generic verbs, auras on the clock | 3, 4 (cooldown and GCD flags, ranks: Deviations 8-9) |
| §2.1.5 kills | 3 |
| §2.2 one tick at 5 Hz, `o.hz`, Update called directly, the queue read, the first-icon policy, `o.react`, `o.reaction`, precombat | 4, 5 (`o.reaction`) |
| §2.3 run A, run B | 4 |
| §3 allocation and performance | 4-5 (Deviation 18) |
| §4 the oracle: `k.plain`, the self-check, `o.raw` | 4, 5 (the debuff row: Deviation 10) |
| §5.1 metrics | 5 (Deviation 13) |
| §5.2 gates, the smoke, the party report | 4 (smoke), 5 (Deviations 14-15) |
| §6.1 `UnitIsUnit(a, a)` | 1 |
| §6.2 facade-name coverage | 1 (Deviation 4) |
| §6.3 State.lua:416 | 1 |
| §7 the Warrior content | 1 (character), 3 (mapping, resolve, usability, rage, uptime), 4 (ranks) |
| §8.1 not tested | "Deliberately not built" |
| §8.2 checkpoint C1 | 4 (the headless queue), 6 |
| §9 tests | 1-5 (each task's Files line names its cases) |
| §10 decisions, "Decisions (accepted)" | "Decisions as built" |
| §11 out of scope | "Deliberately not built" |

**2. Placeholder scan:**
- No "TBD", "TODO", "implement later" or "similar to Task N"; every code step is a `git apply` patch from the replay, and every test step states its measured busted counts.

**3. Names across tasks:** spelled the same in every task and in the checkpoint:
- Shell: `headless.new`, `headless.cycle`, `headless.unexpected`, `headless.SETTLE`, `headless.SKIPPED`, `headless.KNOWN_LOAD_NILS`, `headless.KNOWN_RUN_NILS`, `H.env`, `H.ctl`, `H.Fire`, `H.RunTimers`, `o.character`, `o.pack`, `o.raw`
- Harness: `observer.new`, `obs.step`, `obs.s`, `k.usable`, `k.plain`, `k.gcdSpell`, `k.powerType`, `k.powerToken`, `W.crng`, `W.press`, `W.queueStrike`, `W.applyAura`, `W.dot`, `W.hit`, `W.gain`, `W.setForm`, `W.killAt`, `W.stopAt`, `scenarios.world`, `drive.op`, ops `@current`, `@dead`, `@aura`, `@power`, `@health`, `@cooldown`
- Loop: `loop.new`, `loop.run`, `loop.fight`, `loop.tally`, `loop.summary`, `loop.line`, `loop.TICK`, `loop.REACT`, `loop.PULL`, `loop.GAP`, `loop.RAW`
- Content: `warrior_world.character`, `SPEC`, `CLASS_ID`, `PACK`, `KIT`, `TALENTS`, `IDS`, `FORMS`, `FORM`, `MAP`, `resolve`, `usable`, `rage`, `uptime`, `WORLD`

**4. Review Focus:** each line has its pinned tests (named in Review Focus 1-5).

**Concerns for the orchestrator:**
- (a) `make check` grows to about 4 minutes (busted about 232 s; it was about 95 s): the Arms gate is about 137 s of it, close to D2's estimate of two minutes; the party report adds about 40 s behind `make test-party` only.
- (b) Two proposed bounds missed the first measurement and are set as built after diagnosis (Deviations 14-15). D3 allows that only after the diagnosis; the reviewer should check that the diagnosis holds (the oracle's own `cost` refusals at 15.9 per 100; the disagreement ticks' -7.0 rage) rather than accept the numbers.
- (c) A VirtualState finding comes out of the oracle's self-check (Deviation 10): a stacking debuff believed at one stack too many when a plain aura read lands before the cast's drain. In game the target's auras raise in combat, so ours never meets it there; out of combat (and for player buffs) it can. It is not fixed here (its own change).
- (d) The CPU gate is machine-dependent (D5): the mean measured 2.67 ms against a 10 ms bound.
- (e) The world's truth leaves out what VirtualState models but the world does not (out-of-combat rage decay, rage from hits taken, Slam's cast time), and the damage numbers are Classic's rank-60 values: both runs share them, so A/B compares Hekili's choices, not the numbers.
