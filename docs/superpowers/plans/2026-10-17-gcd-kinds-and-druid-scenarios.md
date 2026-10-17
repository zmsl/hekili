# GCD Kinds and Druid Scenarios Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VirtualState's belief prices each GCD by the kind of the ability that opened it (Hekili's `gcdTime`, `"totem"` 1.0 s, `"spell"` 1.5 s / haste), learns one length per kind and keeps `GcdInfo`'s numbers fixed once read; the Druid's bear swing is priced at the form's fixed 2.5 s (D4); Hekili's simulation stops forcing 1.0 s on a spell-kind press made in energy (core edit E10, its own revertable commit); the combat harness gains class-neutral resources, regen, decay, GCD flag edges, form shifts and crit rage, and the Druid is scored in it: solo bear, solo cat, the shift fight, the Furor variants and Enrage's decay pause.

**Base (read first).** These patches are built on `forever` at `a7b0bab5` (the headless recommendation loop merged: `W.press`, the headless shell, the oracle, `warrior_world.lua`). If `forever` has moved in these files, run Step 2 of Task 1 first: a context mismatch shows there.

**Architecture:**
- **Task 1 (core, the GCD rule):** `Virtual/State/Families/Casts.lua`: `A.gcdKind[a]` at build (0 off, 1 spell, 2 totem; a `track_` extra 0), `I.GcdLen(a, t)` (one function for both files), `I.gcdLearned = { spell, totem }`, the opener (`I.gcdOwner`: the cast in progress or an own on-GCD success within `I.GCD_EDGE` = 0.1 s before the rising edge, else a later success or start within it claims the edge), the read guard (`I.gcdRead`, set by `VS.GcdInfo`), learning per kind (spell [1.0, 2.0), totem [0.9, 1.2), none from an ownerless edge or a declared `gcdTime`), the Snapshot line. `Families/Now.lua`'s automatic GCD by `I.GcdLen`.
- **Task 2 (the Druid side, then E10):** `Forever/Classes/Druid.lua`: `BEAR_SWING = 2.5` prices every bear swing (D4). Then, in its own commit, `State.lua`'s `mt_gcd.execute` loses the Druid-in-energy clause (E10; `max`/`duration` stock) with its engine test and the facade notes' row.
- **Task 3 (the harness core, class-neutral):** several resources (`e.res`, `e.pt`), `W.res`, regen (`W.startRegen`, `regenAfter`) and stepped out-of-combat decay (`W.startDecay`, `pausedBy`), the GCD's latency and edge order (`e.gcdLatency`, `e.gcdOrder`, `W.grng`), press effects (`gain`, `points`, `drain`, `aura` with `tick`, `shift`), `W.shift` with per-resource entry rules, white rage by form (`payIn`) and crit (`critRage`); the observer's power reads by type, regen reads, GCD flag order, attack speed reads, the forms list, usability per type; the drive's content boot (`o.boot`), tracked types, GCD and crit and timing-alone captures; the metrics (`metrics.power`, `gcd`, `unknown`, `crits`, `score`'s section filter); `tests/boundary_spec.lua` scans the harness core (D7).
- **Task 4 (the Druid content and its gates):** `tests/Forever/helpers/druid_vs.lua` (the Druid's VirtualState boot, moved out of `druid_spec.lua`), `tests/Forever/helpers/druid_world.lua` (the mapping read from the class file, the scripted lists, the scenarios), `tests/Forever/druid_harness_spec.lua` (the gates at a tenth of the design's fights in `make check`, the design's counts behind `make test-druid`).
- **Task 5:** the spec's "As built" section, and the in-game CHECKPOINT G1-G8 (the user's; not a blocker).

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, StyLua, `make check` (Makefile: lint, fmt-check, typecheck, test, syntax, api-check).

**Spec:** `docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md` (binding; its "Decisions (accepted as recommended 2026-10-16)" section rules: D1-D9 as recommended, this plan after the headless loop plan). Inputs read for this plan: `docs/research/2026-10-16-core-leakage-audit.md` S3; `src/Hekili/Virtual/State/Families/{Casts,Now,Resources}.lua`, `Sources/{Forms,Swing,Power,Spellbook}.lua`, `Adapter.lua`, `Virtual/Events/Rows.lua`; `src/Hekili/State.lua:3180-3212`; `src/Hekili/Forever/Classes/Druid.lua`; `tests/Virtual/harness/*.lua`; `tests/Forever/helpers/{warrior_world,load_druid}.lua`; `tests/Forever/druid_spec.lua`; `docs/research/2026-10-15-forever-druid/research.md`.

### Decisions as built

| Decision | As built | Where |
|---|---|---|
| D1 opener window and read guard | `I.GCD_EDGE = 0.1` s either side of the rising edge, measured from the edge's own time (Deviation 2); a claim re-fixes the duration only before `GcdInfo`'s first non-zero answer; an ownerless GCD teaches nothing and takes the last opener's kind (spell by default) | Task 1 |
| D2 totem learns | yes, from a falling edge in [0.9, 1.2) | Task 1 |
| D3 E10 | the clause removed from `execute` only, `-- Forever E10:` at the line, a row in `docs/forever-facade-notes.md`; its own commit | Task 2 |
| D4 bear swing | `BEAR_SWING = 2.5` beside `BEAR_RAGE_RATE`; `bearSwing()` and its `VS.SwingBase` read are gone. The harness measured the finding first: before D4 every bear swing of the shift fight was priced 3.46 | Task 2, Task 4 |
| D5 Enrage `pausesDecay` | stays absent; the decay gate shows a wrong declaration overshooting by up to 7.5 rage and its absence undershooting | Task 4 |
| D6 Furor | unmodelled (Bear zero, Cat keep); the variants are report-only shift fights | Task 4 |
| D7 boundary of the harness core | `tests/Virtual/harness` in `CORE`, its captured logs skipped (times and amounts), four WoW global names allow-listed, two test IDs changed | Task 3 |
| D8 harness verbs | the loop plan's `W.press`, `W.gain`, `W.applyAura`, `e.gcdUntil` and `k.usable` are used and extended, not replaced | Task 3 |
| D9 gate bounds | as proposed where the first measurement met them; four bounds set as built after a diagnosis (Deviations 11-13, 16) | Task 4 |

### Deviations from the spec (each measured or read)

1. **The fake spec's two kinds fixtures are opt-in** (`fs.new(swingValue, true)` adds `spender_t`, gcd `"totem"`, 1005, and `spender_u`, `gcdTime = 0.8`, 1006): in every fake spec they moved `adapter_spec`'s tracked counts (3 to 5) and `casts_spec`'s flag count (4 to 6), and adapter_spec already uses 1005/1006 as ad-hoc IDs.
2. **The opener compares against the edge's own time**, not the quantised `gcdStart`: quantising rounds 18.65 up to 18.650390625, so an edge-first claim at the same time read as "before the GCD" and failed; the harness found it (every edge-first GCD at an off-grid time ownerless). casts_spec pins it at 30.65.
3. **The old worlds do not move** (§2.5 expected the new draws to move fights): the GCD order rolls from a third generator `W.grng` (seed + 15485863), and every new behaviour is knob-gated, the player's attack speed read too (`k.playerSpeed`). Nine streams (oracle solo, form, party; seeds 1-3) dumped before and after Task 3 are byte-identical, so the harness design's §9 tables stand without re-measurement; the loop's `W.press` callers see the same stream.
4. **`power` stays the swing-paid type's value** (`e.pt`, default 1), not an alias kept in `res`; `res` holds the other types, `W.res(e, pt)` reads either.
5. **Press field shapes**: `points = { pt, 1 | "all" }` (the type is needed), `aura.tick = { pt, every, amount }` with named fields, `gcd = 0` is off the GCD (as `offGcd`).
6. **Regen is discrete**: a "regen" gain every `regenTick` (0.1 s), capped, no event at the maximum, so usability and the truth use the existing delta path. It runs in every form (UNMEASURED), so Furor's Cat restore (the energy left plus 10 a second out of Cat) equals keep; the Furor rank 5 variant differs from the pack's model by its Bear chance only.
7. **`shift` is a press field and `W.shift`, no set piece**: the shift fight's shifts respect the GCD as presses.
8. **The Druid's presses run half a tick off the drive's 0.1 s grid**: the drive's accumulated tick time (9.4999...) lands a tick between two events of one frame at 9.5, so an edge-first GCD was read before its success arrived; in game Hekili reads between frames, not inside one. Content-side (`druid_world.script`).
9. **`druid_vs.lua` forwards `startsCombat`** (Hekili's ability field): Rows.lua credits a strike's hit to its cast only for a `startsCombat` ability; without it Rake's 40 was credited to a white swing (4 false wounds in one cat fight).
10. **The gates in `make check` run a tenth of the design's fights** (`#slow`, about 19 s, under the harness design's 20 s per spec rule, §4.7's "split the sweep out"); the design's counts run behind `make test-druid` (`#druid`, about 192 s), excluded from `make test` and `make test-fast`.
11. **Bear drift as built**: a window counts when the belief ends it above the truth. All windows a step over: 4 of 2400, each one that starts with the belief 17 below the truth (no answers) and a Maul's 15 paid from 4 believed, clamped at 0; none ends above the truth.
12. **"Believed rage 0 after each Bear entry" as built**: believed minus true at the first tick after the entry <= 1.3 (0.15 of a swing); a swing landing after the entry pays both, at the calibrated scale: measured 0.84 over, 7.31 under.
13. **Decay, matched**: the change since 1.5 s after the stop (our last swings landed) is compared, and one fight in 20 may lose one Enrage tick: seed 15 loses the expiry tick (2) in both matched pairs, below the truth. A VirtualState finding (the expiry's tick and the decay's first quantum), not fixed here (its own change).
14. **The druid_spec GCD case passes at its red step**: it pins Task 1's rule against the class file's declarations; only D4's case fails there.
15. **E10's test boots the whole addon headless** as a level 60 Druid in energy (`tests/Virtual/harness/headless.lua`): `tests/Forever/helpers/engine.lua` stubs `state` and loads no `State.lua`. It lives in `engine_load_spec.lua` as §1.6 says.
16. **Reported, not gated** (the mismatched Furor variants): Cat entry zero leaves the energy belief 99 above the truth at each Cat entry, within 5 only after 35.7 s on average (the fight's end if never): the energy belief's upper side corrects slowly (a VirtualState finding); Furor rank 5's Bear rage lo is at most 4.99 over the truth (below one swing), never a window over.

### The current code, where it differs from the spec's description

- `Families/Casts.lua:42-46` hold `GCD_MIN, GCD_MAX` and `I.gcdLearned` as numbers; `Now.lua:309-319` is the automatic GCD the spec quotes; `VS.GcdInfo` is at `Casts.lua:342`.
- The harness's `W.press` already refuses during `e.gcdUntil` and emits `gcd` on the cast event; the observer fires the GCD flag after the success, always (no order).
- `druid_spec.lua`'s VirtualState setup is at `:859-920`; it copies no `startsCombat` (Deviation 9).
- `Druid.lua:144-150` is `bearSwing()` (`VS.SwingBase(1)`, else `state.mainhand_speed`).

## How this plan was checked

Replayed, not hand-derived. A throwaway clone of `forever` at `a7b0bab5` (tools from the main checkout's `.lua/`):
- Each task was written and measured there (the gates' numbers below are its own runs); then the tasks were rebuilt as a test commit and an implementation commit each.
- The patches below are `git diff` between those states; they were extracted from this file and re-applied with `git apply` to a fresh clone at `a7b0bab5`, in this plan's order, with busted after every patch and `make check` after every task. The final tree equals the hand-built one. Nothing was committed to `~/src/hekili`.

Measured counts (`busted --exclude-tags=party,loop,druid`, the set `make test` runs from Task 4 on):

| State | Result |
|---|---|
| base `a7b0bab5` | 595 successes / 0 / 0 / 0 |
| T1 tests only | 593 successes / 11 failures / 4 errors / 0 pending |
| T1 green | 608 successes / 0 failures / 0 errors / 0 pending |
| T2 D4 tests only | 608 successes / 1 failure / 0 errors / 0 pending |
| T2 D4 green | 609 successes / 0 failures / 0 errors / 0 pending |
| T2 E10 tests only | 609 successes / 1 failure / 0 errors / 0 pending |
| T2 E10 green | 610 successes / 0 failures / 0 errors / 0 pending |
| T3 tests only | 610 successes / 5 failures / 10 errors / 0 pending |
| T3 green | 625 successes / 0 failures / 0 errors / 0 pending |
| T4 tests only | 620 successes / 0 failures / 2 errors / 0 pending |
| T4 green | 632 successes / 0 failures / 0 errors / 0 pending |
| T5 (docs) | 632 successes / 0 failures / 0 errors / 0 pending |

`make check` exited 0 after every task: luacheck 0 / 0 (133, 133, 133, 135, 138, 138 files after the commits in order), lua-language-server no problems, api-check ok in 65 loaded files with an empty inventory diff, `stylua --check .` silent; `make check` took 152, 152, 152, 155, 174 and 173 seconds. The boundary grep printed nothing after every task, and `tests/boundary_spec.lua` scans the harness core from Task 3 on. `make test-druid` on the final tree: 7 successes / 0 failures / 0 errors / 0 pending in 189 s.

The gates' measurements on the final tree are in Task 4's table and the spec's §9 (Task 5).

## Global Constraints

From the spec, verbatim:

> **The boundary, binding for every section.** Core (`Virtual/**`, `Engine/**`, the fork's edits to stock files) and
> the harness core (`tests/Virtual/harness/**`) get generic rules read from declared fields or scenario knobs, with no
> class, form, spell, aura or talent name and no spell ID beyond the GCD spell 29515. Everything Druid is in
> `Forever/Classes/Druid.lua` or in `tests/Forever/**`. Each section ends with "Owns" and "Tests".

> `GcdInfo`'s numbers must not change between edges once read (§7.5).

> `make check`'s runtime rises; split the sweep out if it passes the harness design's 20 s per
> spec rule.

> Every task ends with busted, luacheck, StyLua, LuaLS and the API-read check.

> Every line is under 255 characters.

The house rules for this plan:
- **Worktree.** Repository `~/src/hekili`. The orchestrator creates the worktree after the plan is committed: `git -C ~/src/hekili worktree add .claude/worktrees/gcd-kinds -b gcd-kinds forever`. Git from WSL only. After each task's green verification and clean review the orchestrator pushes `gcd-kinds`; never push to `forever` or any other branch; never force-push. No task merges.
- **Commits.** Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. An implementer on another model uses its own model's name. Task 2 makes two commits; the second (E10) must stay revertable on its own (`git revert` of it leaves every test green but its own engine case).
- **The boundary.** `tests/boundary_spec.lua` scans `src/Hekili/Virtual`, `src/Hekili/Engine` and, from Task 3, `tests/Virtual/harness`. Every task's verification also greps the added lines of `src/Hekili/Virtual`, `src/Hekili/Engine`, `src/Hekili/State.lua` and `tests/Virtual` for class, form and Druid ability words (comments included). Everything Druid is in `src/Hekili/Forever/Classes/Druid.lua` or `tests/Forever/`; the harness never names a spell ID (the GCD spell reaches the observer as `k.gcdSpell` from `c.I.GCD_SPELL`).
- **Secret safety.** No new client read in `src/`. fake_api answers what the facade resolves; a secret stays fake_api's `SECRET` proxy; the harness compares a possibly-secret value only with `rawequal`. `tools/api_inventory.txt` stays unchanged.
- **Allocation.** `Families/Casts.lua` and `Now.lua` allocate nothing per cast or edge (`alloc_spec`'s new 1000-cast case); every VirtualState and harness 0-byte gate stays green and unchanged. The drive's new captures are preallocated; its `@regen` op allocates (no 0-byte drive fires one). Test code allocates otherwise.
- **Style.** StyLua formats every file; each patch is StyLua-clean.
- **Tools.** Run everything from the worktree root. The worktree has no `.lua/`: `make check LUA_ENV=$HOME/src/hekili/.lua`; busted alone: `$HOME/src/hekili/.lua/bin/busted`. `make check` takes about 2 minutes 30 seconds before Task 4 and about 3 minutes from Task 4 on (busted about 160 s); `make test-fast` about 17 s; `make test-druid` about 190 s.
- **Patches** are applied with `git apply` from the worktree root, in the order given. Each block is a heredoc, so copy it whole.
- **Every task ends green on `make check`** (the verification block in each task).
- **The user runs the game.** Task 5's checkpoint is deferred to the user and blocks nothing; E10 is its own commit so the user can revert it if G1 reads 1.0 s. Every line is under 255 characters and copies its answer through `VSCopy(` (ForeverProbe). No new TOC file: `/reload` suffices.

## Review Focus

1. **One frame's edge and success, either order, at any time** (D1, Deviation 2): the claim must hold when the rising edge comes first and the quantised start is later than the edge. Tests: casts_spec "opens a totem-kind GCD of 1.0 s with the success after the edge and before it (same t)" (the 30.65 case), the Druid gates' `ownerless=0` with both `order1` and `order2` counted.
2. **A `GcdInfo` read before the opener arrives** (§7.5): the duration stays, the kind still learns. Tests: casts_spec "keeps the duration after GcdInfo's first answer when the opener's success comes later, and still learns its kind".
3. **A spell-kind press made in energy, in Hekili's simulation** (E10): 1.5 x haste, a totem one 1.0, `gcd.max` 1. Tests: engine_load_spec "prices a spell-kind press at 1.5 x haste and a totem-kind one at 1.0; gcd.max stays the typical 1.0"; G1 in game.
4. **A stale out-of-combat swing base after an in-combat shift** (D4): every bear swing at 8.65. Tests: druid_spec "gains rage per white swing in Bear Form only, at the form's fixed 2.5 s x 3.46; Enrage 2/s; decay 1.25" (a 1.0 s base), the shift gate's `swingMin=swingMax=8.65`.
5. **A wrong resource or decay rule in the class file** (D5, D6): the belief's error must stay on the safe side or be reported. Tests: druid_harness_spec "furor" (Bear never over) and "decay" (the signs asserted, the matched pairs within a quantum).

## File structure

```
src/Hekili/Virtual/State/Families/Casts.lua     T1  gcdKind, I.GcdLen, I.GCD_EDGE, the opener and claim, gcdRead, learning per kind, Snapshot
src/Hekili/Virtual/State/Families/Now.lua       T1  the automatic GCD by I.GcdLen
tests/Virtual/State/helpers/fake_spec.lua       T1  fs.new(swingValue, kinds): spender_t (totem), spender_u (gcdTime 0.8)
tests/Virtual/State/{casts,now,alloc,adapter}_spec.lua  T1
src/Hekili/Forever/Classes/Druid.lua            T2  BEAR_SWING (D4)
tests/Forever/druid_spec.lua                    T2  D4's case, the GCD across shifts; T4 its setup moved to druid_vs.lua
src/Hekili/State.lua                            T2  E10 (its own commit)
tests/Forever/engine_load_spec.lua              T2  E10's case (headless Druid)
docs/forever-facade-notes.md                    T2  E10's row
tests/Virtual/harness/{entities,world,behaviours,observer,drive,scenarios,metrics}.lua  T3
tests/Virtual/harness/{world,metrics}_spec.lua  T3  new
tests/Virtual/harness/{observer,fixtures}_spec.lua, tests/boundary_spec.lua  T3
tests/Forever/helpers/druid_vs.lua              T4  new: the Druid's VirtualState boot
tests/Forever/helpers/druid_world.lua           T4  new: the mapping, the lists, the scenarios, M.fight
tests/Forever/druid_harness_spec.lua            T4  new: the gates (#slow a tenth, #druid the design's counts)
Makefile                                        T4  test and test-fast exclude druid; test-druid
docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md  T5  §9 As built
```

Deliberately not built (a review should not flag these):
- spell haste for the spell kind, a per-form damage cache, Feral Dedication as a declared regen entry, Balance and Restoration scenarios, multi-target bear and threat, the headless "press what is recommended" loop for the Druid, misses on yellow strikes and their points, Blood Frenzy, Natural Reaction and rage from damage taken (spec §8);
- a fix for the two VirtualState findings (Deviations 13, 16): each is its own change;
- mana in the world (never read; a mana cost is not modelled), positions and range, a `shift` set piece (Deviation 7), the swing timer's reset at a shift (the swing already scheduled keeps its time, a comment in `W.shift`).

---
### Task 1: The GCD by kind in the belief: per-kind length, gcdTime, the opener and its claim, the read guard

Spec §1.1-§1.3, §1.5-§1.6 (the core rows), D1, D2; Deviations 1-2.

**Files:**
- Modify: `src/Hekili/Virtual/State/Families/Casts.lua` (`A.gcdKind`; `I.GcdLen(a, t)`; `I.GCD_EDGE`; `I.gcdLearned` a two-slot array; `I.gcdOwner`, `I.gcdKindLast`, `I.gcdRead`; the opener on `CastStart`, `ChannelStart` and an instant `CastSuccess`; the rising edge's owner, the falling edge's learning per kind; `VS.GcdInfo` sets `I.gcdRead`; the Snapshot's `learned=%.4f/%.4f owner=%s`), `src/Hekili/Virtual/State/Families/Now.lua` (the automatic GCD: `A.gcdKind[a] > 0`, `I.GcdLen(a, t)`)
- Test: `tests/Virtual/State/helpers/fake_spec.lua` (`fs.new(swingValue, kinds)`, `fs.SPENDER_T`, `fs.SPENDER_U`, `fs.def` appends them), `tests/Virtual/State/casts_spec.lua` (the two learning cases cast a spell-kind ability first and read `I.gcdLearned[1]`; new describe "the GCD by kind": 9 cases), `tests/Virtual/State/now_spec.lua` (2 cases), `tests/Virtual/State/alloc_spec.lua` (1000 casts mixing kinds, edges in both orders, 0 bytes), `tests/Virtual/State/adapter_spec.lua` (the kinds and `gcdTime` readable from `I.ab.obj` after SpecChanged)

**Interfaces:**
- Consumes: `A.obj[a]` (Hekili's ability table: `gcd`, `gcdTime`, `key`), `VS.Haste(t).est`, `Obs.Cooldown` (a = 0, c = 1: the GCD's edges), `Obs.CastStart`, `Obs.ChannelStart`, `Obs.CastSuccess`.
- Produces: `I.ab.gcdKind[a]` (0 off, 1 spell, 2 totem); `I.GcdLen(a, t)` -> seconds (a = 0: the last opener's kind); `I.GCD_EDGE` (0.1); `I.gcdLearned` `{ [1] = spell, [2] = totem }` (0 unlearned); `I.gcdOwner` (ability index, 0 none); `I.gcdKindLast` (1 or 2); `I.gcdRead` (bool); Snapshot `cast ab=... gcd=%.4f+%.4f learned=%.4f/%.4f owner=<key|none> queued=...`; `fs.new(swingValue, kinds)`, `fs.SPENDER_T` (1005), `fs.SPENDER_U` (1006).

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/adapter_spec.lua b/tests/Virtual/State/adapter_spec.lua
index 8300cdd7..ef037a42 100644
--- a/tests/Virtual/State/adapter_spec.lua
+++ b/tests/Virtual/State/adapter_spec.lua
@@ -100,6 +100,18 @@ describe("Adapter", function()
         assert.are.equal(1011, got.talents[1].spell)
     end)
 
+    it("reads each ability's GCD kind and a declared gcdTime from Hekili's ability table as it is", function()
+        h.Class.abilities.spender_t = { key = "spender_t", id = fs.SPENDER_T, gcd = "totem", funcs = {} }
+        h.Class.abilities.spender_u = { key = "spender_u", id = fs.SPENDER_U, gcdTime = 0.8, funcs = {} }
+        VS.SpecChanged()
+        local A, kinds = I.ab, {}
+        for a = 1, A.n do
+            kinds[A.key[a]] = A.gcdKind[a]
+        end
+        assert.are.same({ spender_a = 1, spender_b = 0, spender_c = 1, spender_t = 2, spender_u = 1 }, kinds)
+        assert.are.equal(0.8, A.obj[A.bySpell[fs.SPENDER_U]].gcdTime)
+    end)
+
     it("forwards a resource's player-aura regen entries to the resources family", function()
         h.Class.resources.rage.state.regenModel.regen_aura_a = { aura = "regen_aura_a", interval = 1, value = 1 }
         h.Class.resources.rage.state.regenModel.debuff_test =
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
index a36a0dff..a3c8aa55 100644
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -190,4 +190,56 @@ describe("zero allocation", function()
         assert.is_true(ok, tostring(bytes))
         assert.are.equal(0, bytes)
     end)
+
+    it(
+        "allocates nothing over 1000 casts mixing GCD kinds, the GCD's rising edge before and after each success",
+        function()
+            local api, ctl = fake.new()
+            local saved = {}
+            for k, v in pairs({
+                CreateFrame = api.CreateFrame,
+                issecretvalue = api.issecretvalue,
+                GetTime = api.GetTime,
+            }) do
+                saved[k] = rawget(_G, k) or false
+                _G[k] = v
+            end
+            ctl.now = 1
+            local ns = load.module()
+            local VS, I = ns.VirtualState, ns.VirtualStateInternal
+            I.Build(fs.def(fs.new(9, true)), 1)
+            VS.Start(api)
+            local IDS = { fs.SPENDER_C, fs.SPENDER_T, fs.SPENDER_U } -- spell, totem, a declared gcdTime
+            local UP, DOWN = { isActive = true, isOnGCD = false }, { isActive = false, isOnGCD = false }
+            local function tick()
+                ctl.Tick(ctl.now)
+                fs.fold(ns, ctl.now)
+                VS.GcdInfo(ctl.now)
+            end
+            local function step(i)
+                ctl.now = ctl.now + 0.5
+                local id = IDS[i % 3 + 1]
+                if i % 2 == 0 then
+                    ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", id)
+                end
+                ctl.cooldown[I.GCD_SPELL] = UP
+                ctl.Fire("SPELL_UPDATE_COOLDOWN")
+                if i % 2 == 1 then
+                    ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", id)
+                end
+                tick()
+                ctl.now = ctl.now + 1.0
+                ctl.cooldown[I.GCD_SPELL] = DOWN
+                ctl.Fire("SPELL_UPDATE_COOLDOWN")
+                tick()
+            end
+            local ok, bytes = pcall(alloc.bytes, step, 1000)
+            for k, v in pairs(saved) do
+                _G[k] = v or nil
+            end
+            assert.is_true(ok, tostring(bytes))
+            assert.are.equal(0, bytes)
+            assert.is_true(I.gcdLearned[1] > 0 and I.gcdLearned[2] > 0, "both kinds learned")
+        end
+    )
 end)
diff --git a/tests/Virtual/State/casts_spec.lua b/tests/Virtual/State/casts_spec.lua
index 1e489d74..3c9ad617 100644
--- a/tests/Virtual/State/casts_spec.lua
+++ b/tests/Virtual/State/casts_spec.lua
@@ -54,6 +54,9 @@ describe("casts and cooldowns", function()
     end)
 
     it("learns a GCD only from a falling edge within [1.0, 2.0) s", function()
+        for _, t in ipairs({ 100, 110, 120 }) do
+            S.Direct(Obs.CastSuccess, t, REND) -- a spell-kind cast opens each one (an ownerless GCD teaches nothing)
+        end
         S.Direct(Obs.Cooldown, 100, 0, 1, 1)
         S.Direct(Obs.Cooldown, 101.4, 0, 0, 1)
         S.Direct(Obs.Cooldown, 110, 0, 1, 1)
@@ -61,7 +64,7 @@ describe("casts and cooldowns", function()
         S.Direct(Obs.Cooldown, 120, 0, 1, 1)
         S.Direct(Obs.Cooldown, 122, 0, 0, 1) -- exactly 2.0 s: two chained 1.0 s GCDs, not one
         I.Fold(122.1, false)
-        assert.is_true(math.abs(I.gcdLearned - 1.4) < 0.002) -- the earlier, plausible one stands
+        assert.is_true(math.abs(I.gcdLearned[1] - 1.4) < 0.002) -- the earlier, plausible one stands
     end)
 
     it("names an ability with a second power cost in Snapshot", function()
@@ -97,6 +100,7 @@ describe("casts and cooldowns", function()
     it(
         "fixes the GCD's start and duration at the rising edge, quantised so they survive Hekili's round trip",
         function()
+            S.Direct(Obs.CastSuccess, 1000.1, REND)
             S.Direct(Obs.Cooldown, 1000.123456, 0, 1, 1)
             I.Fold(1000.2, false)
             local s, d = VS.GcdInfo(1000.2)
@@ -106,7 +110,7 @@ describe("casts and cooldowns", function()
             S.Direct(Obs.Cooldown, 1001.6, 0, 0, 1)
             I.Fold(1001.6, false)
             assert.are.same({ 0, 0 }, { VS.GcdInfo(1001.6) })
-            assert.is_true(math.abs(I.gcdLearned - 1.477) < 0.002) -- learned from the falling edge
+            assert.is_true(math.abs(I.gcdLearned[1] - 1.477) < 0.002) -- learned from the falling edge
             for _ = 1, 2000 do
                 local t = math.random() * 1e6
                 local q = I.Quantise(t)
@@ -155,3 +159,141 @@ describe("casts and cooldowns", function()
         assert.is_nil(VS.Charges(fs.SPENDER_C, 1))
     end)
 end)
+
+-- The GCD by kind (GCD kinds design §1.2): its length from the ability that opened it, an opener on either side of the
+-- rising edge, learning per kind, and the read guard that keeps GcdInfo's numbers fixed between edges (spec §7.5).
+describe("the GCD by kind", function()
+    local VS, I, S, Obs, api, ctl
+    local SPELL, OFF, TOTEM, FIXED = 3, 2, 4, 5 -- spender_c, spender_b (off the GCD), spender_t, spender_u (0.8 s)
+
+    before_each(function()
+        api, ctl = fake.new()
+        local ns = load.module()
+        VS, I = ns.VirtualState, ns.VirtualStateInternal
+        S, Obs = I.Sources, VS.Obs
+        I.Build(fs.def(fs.new(9, true)), 1)
+        VS.Start(api)
+        ctl.Tick(1)
+        I.ObsLog.Clear(I.log)
+    end)
+
+    local function success(a, t)
+        S.Direct(Obs.CastSuccess, t, a)
+    end
+    local function edge(t, up)
+        S.Direct(Obs.Cooldown, t, 0, up and 1 or 0, 1)
+    end
+    local function info(t)
+        I.Fold(t, false)
+        return { VS.GcdInfo(t) }
+    end
+    local function near(want, got)
+        assert.is_true(math.abs(want - got) < 0.002, tostring(got))
+    end
+
+    it("opens a totem-kind GCD of 1.0 s with the success after the edge and before it (same t)", function()
+        edge(10, true)
+        success(TOTEM, 10) -- the edge first: the success claims it (provisional: the spell kind's 1.5)
+        assert.are.same({ 10, 1 }, info(10.05))
+        assert.are.equal(TOTEM, I.gcdOwner)
+        edge(11, false)
+        success(TOTEM, 20) -- the success first
+        edge(20, true)
+        assert.are.same({ 20, 1 }, info(20.05))
+        assert.are.equal(TOTEM, I.gcdOwner)
+        edge(21, false)
+        edge(30.65, true) -- off the 2^-10 grid: the quantised start (30.650390625) is later than the edge
+        success(TOTEM, 30.65)
+        assert.are.same({ I.Quantise(30.65), 1 }, info(30.7))
+        assert.are.equal(TOTEM, I.gcdOwner)
+    end)
+
+    it("opens a spell-kind GCD of 1.5 / haste (haste 1.25: 1.2)", function()
+        S.Direct(Obs.Haste, 9, 0, 1.25, 1)
+        success(SPELL, 10)
+        edge(10.03, true)
+        near(1.2, info(10.1)[2])
+        assert.are.equal(SPELL, I.gcdOwner)
+    end)
+
+    it("lets a hard cast in progress own the edge at its start, after a totem-kind GCD", function()
+        success(TOTEM, 5)
+        edge(5, true)
+        edge(6, false)
+        S.Direct(Obs.CastStart, 10, SPELL, 11.5)
+        edge(10.02, true)
+        near(1.5, info(10.1)[2])
+        assert.are.equal(SPELL, I.gcdOwner)
+    end)
+
+    it("lets a declared gcdTime (0.8) win, and never learns from it", function()
+        success(FIXED, 10)
+        edge(10, true)
+        near(0.8, info(10.1)[2])
+        edge(10.85, false)
+        I.Fold(11, false)
+        assert.are.same({ 0, 0 }, I.gcdLearned)
+    end)
+
+    it("learns per kind: a totem GCD falling at +1.02 and a spell GCD at +1.43 set the next of each kind", function()
+        success(TOTEM, 10)
+        edge(10, true)
+        edge(11.02, false)
+        success(SPELL, 20)
+        edge(20, true)
+        edge(21.43, false)
+        success(TOTEM, 30)
+        edge(30, true)
+        near(1.02, info(30.1)[2])
+        edge(31.02, false)
+        success(SPELL, 40)
+        edge(40, true)
+        near(1.43, info(40.1)[2])
+        assert.is_truthy(VS.Snapshot():find("learned=1.4297/1.0195 owner=spender_c", 1, true))
+    end)
+
+    it("takes the last opener's kind for an ownerless edge, and learns nothing from it", function()
+        success(TOTEM, 10)
+        edge(10, true)
+        edge(11, false)
+        edge(20, true) -- no cast near it
+        assert.are.same({ 20, 1 }, info(20.1))
+        assert.are.equal(0, I.gcdOwner)
+        edge(21.4, false)
+        I.Fold(21.5, false)
+        assert.are.same({ 0, 1 }, I.gcdLearned)
+    end)
+
+    it(
+        "keeps the duration after GcdInfo's first answer when the opener's success comes later, and still learns its kind",
+        function()
+            edge(10, true)
+            assert.are.same({ 10, 1.5 }, info(10.01)) -- read: the provisional spell kind's
+            success(TOTEM, 10.05)
+            assert.are.same({ 10, 1.5 }, info(10.1)) -- unchanged between edges
+            assert.are.equal(TOTEM, I.gcdOwner)
+            edge(11.03, false)
+            I.Fold(11.1, false)
+            near(1.03, I.gcdLearned[2])
+        end
+    )
+
+    it("never lets an off-GCD success inside the window open the GCD", function()
+        success(OFF, 10)
+        edge(10.02, true)
+        success(OFF, 10.05)
+        info(10.1)
+        assert.are.equal(0, I.gcdOwner)
+    end)
+
+    it("rejects a totem-kind fall of 2.0 s (two chained GCDs) and of 0.85 s", function()
+        success(TOTEM, 10)
+        edge(10, true)
+        edge(12, false)
+        success(TOTEM, 20)
+        edge(20, true)
+        edge(20.85, false)
+        I.Fold(21, false)
+        assert.are.same({ 0, 0 }, I.gcdLearned)
+    end)
+end)
diff --git a/tests/Virtual/State/helpers/fake_spec.lua b/tests/Virtual/State/helpers/fake_spec.lua
index 512625cb..c8534963 100644
--- a/tests/Virtual/State/helpers/fake_spec.lua
+++ b/tests/Virtual/State/helpers/fake_spec.lua
@@ -8,10 +8,14 @@ local M = {}
 M.RAGE = 1 -- Enum.PowerType.Rage
 -- Neutral fixtures, no class's facts: spender_a puts a 120 s buff on us, spender_b waits for the next swing (off the
 -- GCD), spender_c puts a 15 s debuff on the target and has a rank 2. The keys sort in that order, as the slots do.
+-- With `kinds` (M.new's second argument) two free casts on Hekili's other GCD kinds follow: spender_t on the fixed
+-- 1.0 s one ("totem"), spender_u on a declared `gcdTime` of 0.8 s.
 M.SPENDER_A, M.SPENDER_B, M.SPENDER_C, M.SPENDER_C_R2 = 1001, 1002, 1003, 1004
+M.SPENDER_T, M.SPENDER_U = 1005, 1006
 
---- A fake Hekili: { State, Class, ForceUpdate, forced }, and `spendResources` for ns. `swingValue` is rage per swing.
-function M.new(swingValue)
+--- A fake Hekili: { State, Class, ForceUpdate, forced }, and `spendResources` for ns. `swingValue` is rage per swing;
+--- `kinds` adds spender_t and spender_u.
+function M.new(swingValue, kinds)
     local state = {
         offset = 0,
         delay = 0,
@@ -103,6 +107,10 @@ function M.new(swingValue)
             applyBuff("spender_a")
         end,
     })
+    if kinds then
+        ability("spender_t", { id = M.SPENDER_T, gcd = "totem" })
+        ability("spender_u", { id = M.SPENDER_U, gcdTime = 0.8 })
+    end
     class.auras.spender_c = { key = "spender_c", id = M.SPENDER_C, copy = { M.SPENDER_C_R2 }, duration = 15 }
     class.auras.spender_a = { key = "spender_a", id = M.SPENDER_A, duration = 120 }
     function state:RunHandler(key)
@@ -149,7 +157,7 @@ function M.def(hekili)
     local class = hekili.Class
     local rage = class.resources.rage
     local mh = rage.state.regenModel.mainhand
-    return {
+    local def = {
         abilities = { class.abilities.spender_a, class.abilities.spender_b, class.abilities.spender_c },
         abilityIds = { { M.SPENDER_A }, { M.SPENDER_B }, { M.SPENDER_C, M.SPENDER_C_R2 } },
         abilitySlot = { 1, 1, 1 },
@@ -161,6 +169,14 @@ function M.def(hekili)
         talents = { { key = "talent_a", spell = 1011, max = 3 } },
         units = { "player", "target" },
     }
+    for _, k in ipairs({ "spender_t", "spender_u" }) do
+        local a = class.abilities[k]
+        if a then
+            def.abilities[#def.abilities + 1], def.abilityIds[#def.abilityIds + 1] = a, { a.id }
+            def.abilitySlot[#def.abilitySlot + 1] = 0
+        end
+    end
+    return def
 end
 
 --- One drain without Hekili: the polls, the fold, the settle (Adapter's Drain minus the apply).
diff --git a/tests/Virtual/State/now_spec.lua b/tests/Virtual/State/now_spec.lua
index 9c352341..03aa0740 100644
--- a/tests/Virtual/State/now_spec.lua
+++ b/tests/Virtual/State/now_spec.lua
@@ -367,6 +367,45 @@ describe("now handlers", function()
         assert.is_true(gcd.est > 20)
     end)
 
+    it(
+        "models the automatic GCD by kind: totem t + 1.0, spell t + 1.5 / haste, a declared gcdTime, the learned slot",
+        function()
+            register("totem_test", { id = 4501, gcd = "totem" })
+            register("fixed_test", { id = 4502, gcdTime = 0.8 })
+            start()
+            cast(4501, 10)
+            assert.are.equal(11, VS.Gcd(10.1).est)
+            cast(fs.SPENDER_C, 20)
+            assert.are.equal(21.5, VS.Gcd(20.1).est) -- haste 1
+            cast(4502, 30)
+            assert.are.equal(30.8, VS.Gcd(30.1).est)
+            I.gcdLearned[1] = 1.4 -- the spell kind's learned length (Families/Casts.lua's falling edge)
+            cast(fs.SPENDER_C, 40)
+            assert.are.equal(41.4, VS.Gcd(40.1).est)
+            cast(4501, 50)
+            assert.are.equal(51, VS.Gcd(50.1).est) -- the totem kind keeps its own
+        end
+    )
+
+    it(
+        "models a spell-kind cast at t + 1.5 after three totem ones learned 1.0, and the next totem one at t + 1.0",
+        function()
+            register("totem_test", { id = 4501, gcd = "totem" })
+            start()
+            for _, t in ipairs({ 10, 12, 14 }) do
+                cast(4501, t)
+                I.Sources.Direct(VS.Obs.Cooldown, t, 0, 1, 1) -- the GCD's edges, 1.0 s apart
+                I.Sources.Direct(VS.Obs.Cooldown, t + 1, 0, 0, 1)
+                VS.Drain(t + 1.01)
+            end
+            assert.are.same({ 0, 1 }, I.gcdLearned)
+            cast(fs.SPENDER_C, 16)
+            assert.are.equal(17.5, VS.Gcd(16.1).est)
+            cast(4501, 18)
+            assert.are.equal(19, VS.Gcd(18.1).est)
+        end
+    )
+
     it("clears a stopped cast's start", function()
         register("slam_test", { id = 1464, cast = 1.5 })
         start()
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `593 successes / 11 failures / 4 errors / 0 pending`.
- casts_spec "the GCD by kind" (9 cases) and now_spec's 2 new cases fail: the GCD is 1.5 s for every kind and `I.gcdLearned` is a number;
- adapter_spec "reads each ability's GCD kind ..." and alloc_spec's new case error (`I.ab.gcdKind` is nil); the two edited learning cases error indexing `I.gcdLearned[1]`.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/State/Families/Casts.lua b/src/Hekili/Virtual/State/Families/Casts.lua
index cb9038fa..a0527fe6 100644
--- a/src/Hekili/Virtual/State/Families/Casts.lua
+++ b/src/Hekili/Virtual/State/Families/Casts.lua
@@ -1,7 +1,8 @@
 -- Virtual/State/Families/Casts.lua
 -- The casts family (spec §6.2): the tracked abilities, our casts and channels in progress, cooldown ready times
 -- snapped to the game's plain ready flags (the constrain step), charges, the GCD from its flag edges with
--- bit-identical start and duration (spec §7.5), the on-next-swing queue, and the Cooldown/Charges/Gcd accessors.
+-- bit-identical start and duration (spec §7.5), its length by GCD kind and the ability that opened it, the
+-- on-next-swing queue, and the Cooldown/Charges/Gcd accessors.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Casts.lua (step :34-78, Applier Cooldown :385,
 -- Queued :391) and src/TacoDogForever/Model/Belief.lua (constrain :652-684).
 
@@ -11,7 +12,7 @@ local Obs = VS.Obs
 local floor, abs, max = math.floor, math.abs, math.max
 
 -- By ability index a. `obj` is the spec's ability table (Hekili's `class.abilities[key]`): VirtualState reads its
--- `spend`, `spendType`, `cooldown`, `charges`, `recharge`, `gcd`, `cast` and `onNextSwing` fields.
+-- `spend`, `spendType`, `cooldown`, `charges`, `recharge`, `gcd`, `gcdTime`, `cast` and `onNextSwing` fields.
 local A = {
     n = 0,
     key = {},
@@ -33,17 +34,28 @@ local A = {
     cd = {},
     ch = {},
     chNext = {},
+    gcdKind = {}, -- 0 off the GCD, 1 spell (1.5 s / haste), 2 totem (Hekili's fixed 1.0 s)
 }
 I.ab = A
 A.bySpell = {}
 
 -- Unknown, not ready, ready (the plain isActive flag as last reported).
 local UNKNOWN, NOT, YES = -1, 0, 1
-local GCD_MIN, GCD_MAX = 1.0, 2.0 -- the plausible GCD lengths a falling edge may teach: [1.0, 2.0)
+-- The plausible lengths a falling edge may teach, by kind: spell [1.0, 2.0), totem [0.9, 1.2) (two chained GCDs merge
+-- into one long edge: 2.0 and more is never one).
+local GCD_MIN, GCD_MAX = { 1.0, 0.9 }, { 2.0, 1.2 }
+-- An own cast within this of the GCD's rising edge, before or after it, opened it (UNMEASURED until checkpoint G3).
+local GCD_EDGE = 0.1
+I.GCD_EDGE = GCD_EDGE
 
--- The cast or channel in progress (0: none), and the GCD fixed at its rising edge.
+-- The cast or channel in progress (0: none), and the GCD fixed at its rising edge: its opener (ability index, 0
+-- none), the opener kind a GCD without one takes (the last opener's), whether GcdInfo has answered it, and the
+-- learned length by kind ({ spell, totem }, 0 unlearned).
 I.castAb, I.castEnd, I.channel = 0, 0, false
-I.gcdStart, I.gcdDur, I.gcdLearned = 0, 0, 0
+I.gcdStart, I.gcdDur, I.gcdLearned = 0, 0, { 0, 0 }
+I.gcdOwner, I.gcdKindLast, I.gcdRead = 0, 1, false
+local lastGcdA, lastGcdT = 0, 0 -- the last own on-GCD CastSuccess no GCD has taken yet
+local gcdEdge = 0 -- the rising edge's own time (gcdStart is it quantised, up to 2^-11 s later)
 I.queuedStrike = false
 I.lastCastT = 0
 local gcd
@@ -55,6 +67,28 @@ local function quantise(x)
 end
 I.Quantise = quantise
 
+--- The length of a GCD that ability a (0: none known, the last opener's kind) opens at t: its declared `gcdTime`,
+--- else its kind's learned length, else 1.0 for the totem kind and 1.5 / haste for the spell kind. Allocates nothing.
+function I.GcdLen(a, t)
+    local kind = I.gcdKindLast
+    if a > 0 then
+        local g = A.obj[a].gcdTime
+        if type(g) == "number" and g > 0 then
+            return g
+        end
+        kind = A.gcdKind[a]
+    end
+    if kind == 0 then
+        return 0
+    elseif I.gcdLearned[kind] > 0 then
+        return I.gcdLearned[kind]
+    elseif kind == 2 then
+        return 1.0
+    end
+    local h = VS.Haste and VS.Haste(t).est or 1 -- Families/Swing.lua measures it
+    return 1.5 / (h > 0 and h or 1) -- nonzero: h > 0 checked
+end
+
 local function maxCharges(a)
     local c = A.obj[a].charges
     return type(c) == "number" and c or 1
@@ -79,6 +113,8 @@ I.OnBuild(function(def, now)
         A.ready0[a], A.cdLen[a], A.castT[a], A.flag[a] = 0, 0, 0, UNKNOWN
         A.charges0[a], A.next0[a] = maxCharges(a), 0
         A.queued[a], A.castStartT[a] = false, 0
+        local g, extra = obj.gcd, type(obj.key) == "string" and obj.key:sub(1, 6) == "track_" -- VS.Track: no GCD
+        A.gcdKind[a] = (g == "off" or extra) and 0 or (g == "totem" and 2 or 1) -- anything else: State.lua's "spell"
         A.cd[a] = I.NewBelief("cooldown " .. tostring(obj.key))
         I.Sample(A.cd[a], "default", 0, now, 0)
         if maxCharges(a) > 1 then
@@ -92,11 +128,39 @@ I.OnBuild(function(def, now)
     I.TRACKED.ability = A.id
     gcd = I.NewBelief("gcd")
     I.castAb, I.castEnd, I.channel, I.gcdStart, I.gcdDur, I.queuedStrike = 0, 0, false, 0, 0, false
+    I.gcdOwner, I.gcdKindLast, I.gcdRead, lastGcdA, lastGcdT = 0, 1, false, 0, 0
 end)
 
+-- The GCD's current sample at its fixed end.
+local function pinGcd(t)
+    local e = I.gcdStart + I.gcdDur
+    gcd.est, gcd.lo, gcd.hi = e, e, e
+    I.Sample(gcd, "pinned", e, t, Obs.Cooldown)
+end
+
+-- An own cast of on-GCD ability a at time `at`: it claims an ownerless GCD that rose within GCD_EDGE before it (the
+-- edge came first), re-fixing the duration only while GcdInfo has not answered this GCD (spec §7.5); else it is kept
+-- for the next rising edge.
+local function opener(a, at, t)
+    if A.gcdKind[a] == 0 then
+        return -- off the GCD (an on-next-swing strike's success at its swing): never an opener
+    end
+    if I.gcdStart > 0 and I.gcdOwner == 0 and at >= gcdEdge and at - gcdEdge <= GCD_EDGE then
+        I.gcdOwner, I.gcdKindLast = a, A.gcdKind[a]
+        if not I.gcdRead then
+            I.gcdDur = quantise(I.GcdLen(a, t))
+            pinGcd(t)
+        end
+        lastGcdA = 0
+    else
+        lastGcdA, lastGcdT = a, at
+    end
+end
+
 I.On(Obs.CastStart, function(o, t)
     I.castAb, I.castEnd, I.channel = o.a, o.b, false
     A.castStartT[o.a] = o.t
+    opener(o.a, o.t, t)
 end)
 
 I.On(Obs.CastDelay, function(o)
@@ -105,10 +169,12 @@ I.On(Obs.CastDelay, function(o)
     end
 end)
 
-I.On(Obs.CastSuccess, function(o)
+I.On(Obs.CastSuccess, function(o, t)
     I.lastCastT = o.t
     if I.castAb == o.a and not I.channel then
         I.castAb = 0
+    elseif A.castStartT[o.a] == 0 then -- a hard cast's GCD opened at its start
+        opener(o.a, o.t, t)
     end
     if A.obj[o.a].onNextSwing then
         A.queued[o.a] = false
@@ -122,9 +188,10 @@ I.On(Obs.CastStop, function(o)
     A.castStartT[o.a] = 0 -- an interrupted cast's start is no GCD anchor for the next one (Families/Now.lua)
 end)
 
-I.On(Obs.ChannelStart, function(o)
+I.On(Obs.ChannelStart, function(o, t)
     I.castAb, I.castEnd, I.channel = o.a, o.b, true
     A.castStartT[o.a] = o.t
+    opener(o.a, o.t, t)
 end)
 
 I.On(Obs.ChannelUpdate, function(o)
@@ -154,18 +221,32 @@ end)
 I.On(Obs.Cooldown, function(o, t)
     if o.c == 1 then
         if o.b == 1 then
-            -- the GCD began: start and duration fixed until the falling edge (spec §7.5)
-            local h = VS.Haste and VS.Haste(t).est or 1 -- Families/Swing.lua measures it
-            local dur = I.gcdLearned > 0 and I.gcdLearned or 1.5 / (h > 0 and h or 1) -- nonzero: h > 0 checked
-            I.gcdStart, I.gcdDur = quantise(o.t), quantise(dur)
-            gcd.est, gcd.lo, gcd.hi = I.gcdStart + I.gcdDur, I.gcdStart + I.gcdDur, I.gcdStart + I.gcdDur
-            I.Sample(gcd, "pinned", gcd.est, t, Obs.Cooldown)
-        else
-            local len = o.t - I.gcdStart
-            if I.gcdStart > 0 and len >= GCD_MIN and len < GCD_MAX then -- chained GCDs merge into one long edge
-                I.gcdLearned = quantise(len)
+            -- the GCD began: its opener is the cast in progress or an own cast just before the edge; start and
+            -- duration fixed until the falling edge (spec §7.5), but a later opener's claim before GcdInfo's first read
+            local owner = 0
+            if I.castAb > 0 and A.gcdKind[I.castAb] > 0 then
+                owner = I.castAb
+            elseif lastGcdA > 0 and o.t - lastGcdT <= GCD_EDGE then
+                owner = lastGcdA
             end
-            I.gcdStart, I.gcdDur = 0, 0
+            lastGcdA = 0
+            I.gcdOwner, I.gcdRead = owner, false
+            if owner > 0 then
+                I.gcdKindLast = A.gcdKind[owner]
+            end
+            I.gcdStart, I.gcdDur, gcdEdge = quantise(o.t), quantise(I.GcdLen(owner, t)), o.t
+            pinGcd(t)
+        else
+            local len, owner = o.t - I.gcdStart, I.gcdOwner
+            local kind = owner > 0 and A.gcdKind[owner] or 0
+            local g = owner > 0 and A.obj[owner].gcdTime
+            -- an ownerless GCD, or one of a declared length, teaches nothing
+            if I.gcdStart > 0 and kind > 0 and not (type(g) == "number" and g > 0) then
+                if len >= GCD_MIN[kind] and len < GCD_MAX[kind] then
+                    I.gcdLearned[kind] = quantise(len)
+                end
+            end
+            I.gcdStart, I.gcdDur, I.gcdOwner, I.gcdRead = 0, 0, 0, false
             gcd.est, gcd.lo, gcd.hi = o.t, o.t, o.t
             I.Sample(gcd, "pinned", o.t, t, Obs.Cooldown)
         end
@@ -341,6 +422,7 @@ end
 --- (spec §3.1, §7.5) start, duration of the current GCD as plain numbers fixed between its edges; 0, 0 when none.
 function VS.GcdInfo(now)
     if I.gcdStart > 0 and I.gcdStart + I.gcdDur > now then
+        I.gcdRead = true -- answered: a later opener's claim no longer changes the duration
         return I.gcdStart, I.gcdDur
     end
     return 0, 0
@@ -348,13 +430,15 @@ end
 
 I.OnSnapshot(function(out, now)
     out[#out + 1] = string.format(
-        "cast ab=%s end=%.2f channel=%s gcd=%.4f+%.4f learned=%.4f queued=%s",
+        "cast ab=%s end=%.2f channel=%s gcd=%.4f+%.4f learned=%.4f/%.4f owner=%s queued=%s",
         I.castAb > 0 and tostring(A.key[I.castAb]) or "none",
         I.castEnd,
         tostring(I.channel),
         I.gcdStart,
         I.gcdDur,
-        I.gcdLearned,
+        I.gcdLearned[1],
+        I.gcdLearned[2],
+        I.gcdOwner > 0 and tostring(A.key[I.gcdOwner]) or "none",
         tostring(I.queuedStrike)
     )
     for a = 1, A.n do
diff --git a/src/Hekili/Virtual/State/Families/Now.lua b/src/Hekili/Virtual/State/Families/Now.lua
index 9586d8f0..6c8b545c 100644
--- a/src/Hekili/Virtual/State/Families/Now.lua
+++ b/src/Hekili/Virtual/State/Families/Now.lua
@@ -306,13 +306,12 @@ local function automatic(a, t, kind)
             I.CooldownModel(a, t + cd, cd, t, kind)
         end
     end
-    if obj.gcd ~= "off" then
+    if A.gcdKind[a] > 0 then
         local start = t
         if kind == CAST and A.castStartT[a] > 0 and A.castStartT[a] < t then
             start = A.castStartT[a] -- a hard cast's GCD began at its start
         end
-        local h = VS.Haste(t).est
-        local len = I.gcdLearned > 0 and I.gcdLearned or 1.5 / (h > 0 and h or 1) -- nonzero: h > 0 checked
+        local len = I.GcdLen(a, t) -- its kind's (Families/Casts.lua)
         if start + len > t then
             I.GcdModel(start + len, t, kind)
         end
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `608 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 133 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      608 successes / 0 failures / 0 errors / 0 pending (about 139 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual src/Hekili/Engine src/Hekili/State.lua tests/Virtual | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|bear|cat|feral|maul|enrage|furor|shred|rake|rip|swipe|lacerate|bite|cat_form|bear_form|shifting_power|stance'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/Families/Casts.lua src/Hekili/Virtual/State/Families/Now.lua \
  tests/Virtual/State/helpers/fake_spec.lua tests/Virtual/State/casts_spec.lua tests/Virtual/State/now_spec.lua \
  tests/Virtual/State/alloc_spec.lua tests/Virtual/State/adapter_spec.lua
git commit -m "feat(vs): the GCD by kind: gcdTime, a totem kind of 1.0 s and a spell kind of 1.5 s / haste, each learned apart; the opener on either side of the rising edge, its claim fixed once GcdInfo has answered (GCD kinds design §1, D1, D2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin gcd-kinds`

---
### Task 2: The Druid side (D4), then core edit E10 in its own commit

Spec §1.4, §1.6 (the Druid and engine rows), §4.3's finding, D3, D4; Deviations 14-15. Two commits: D4 (Steps 1-6), then E10 (Steps 7-12), which the user reverts on its own if checkpoint G1 reads 1.0 s.

**Files:**
- Modify: `src/Hekili/Forever/Classes/Druid.lua` (`BEAR_SWING = 2.5`; `bearSwing()` removed; `mainhand.value` and `crit` are `BEAR_RAGE_RATE * BEAR_SWING`); then `src/Hekili/State.lua` (`mt_gcd.execute`: `if one_sec_gcd[ class.file ] then`, a `-- Forever E10:` line above it), `docs/forever-facade-notes.md` (E10's bullet under "Edits no facade absorbs")
- Test: `tests/Forever/druid_spec.lua` ("gains rage per white swing in Bear Form only, at the form's fixed 2.5 s x 3.46; Enrage 2/s; decay 1.25": a stale 1.0 s base; new "opens each GCD at its kind's length across shifts, and a hard cast's at its start (GCD kinds §1.6)"), then `tests/Forever/engine_load_spec.lua` (new describe "the simulation's GCD by kind in energy (core edit E10)")

**Interfaces:**
- Consumes: Task 1's `I.gcdLearned`, `VS.GcdInfo`, the Snapshot's `learned=`; `tests/Virtual/harness/headless.lua`'s `headless.new({ character })`.
- Produces: the class file's bear swing at 8.65 whatever `VS.SwingBase` holds (Task 4's shift gate reads it); `state.gcd.execute` 1.5 x haste for a spell-kind press in energy.

- [ ] **Step 1: Write the failing spec (D4)**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/druid_spec.lua b/tests/Forever/druid_spec.lua
index 76d76360..ce65d6f7 100644
--- a/tests/Forever/druid_spec.lua
+++ b/tests/Forever/druid_spec.lua
@@ -589,29 +589,32 @@ describe("Forever Druid", function()
         assert.are.same({}, e.removed)
     end)
 
-    it("gains rage per white swing in Bear Form only, at the form's 2.5 s x 3.46; Enrage 2/s; decay 1.25", function()
-        local models = w.resources[1].models
-        w.state.buff.bear_form = { up = false }
-        w.state.swings.mainhand, w.state.mainhand_speed = 5, 2.5
-        assert.are.same(
-            { "mainhand", "bear_form", "mainhand_speed" },
-            { models.mainhand.swing, models.mainhand.aura, models.mainhand.interval }
-        )
-        assert.is_true(models.mainhand.stop()) -- out of Bear Form
-        w.state.buff.bear_form.up = true
-        assert.is_false(models.mainhand.stop())
-        near(2.5 * 3.46, models.mainhand.value()) -- the believed swing speed before a plain base read
-        w.game.base = { 2.5, 0 }
-        w.state.mainhand_speed = 2.0 -- hasted: the rage follows the unhasted speed
-        near(8.65, models.mainhand.value())
-        near(8.65, models.mainhand.crit()) -- a white crit: one more base swing
-        assert.are.same({ "enrage", 1, 2 }, { models.enrage.aura, models.enrage.interval, models.enrage.value })
-        assert.is_nil(models.enrage.pausesDecay) -- unverified (checkpoint Q9)
-        w.state.buff.enrage, w.state.query_time = { applied = 10 }, 13.4
-        assert.are.equal(13, models.enrage.last())
-        assert.are.equal(1.25, w.resources[1].meta.decay())
-        assert.are.equal(1, w.resources[1].meta.decayInterval()) -- stepped, as the Warrior's
-    end)
+    it(
+        "gains rage per white swing in Bear Form only, at the form's fixed 2.5 s x 3.46; Enrage 2/s; decay 1.25",
+        function()
+            local models = w.resources[1].models
+            w.state.buff.bear_form = { up = false }
+            w.state.swings.mainhand, w.state.mainhand_speed = 5, 2.5
+            assert.are.same(
+                { "mainhand", "bear_form", "mainhand_speed" },
+                { models.mainhand.swing, models.mainhand.aura, models.mainhand.interval }
+            )
+            assert.is_true(models.mainhand.stop()) -- out of Bear Form
+            w.state.buff.bear_form.up = true
+            assert.is_false(models.mainhand.stop())
+            near(2.5 * 3.46, models.mainhand.value()) -- before a plain base read
+            w.game.base = { 1.0, 0 } -- a Cat pull's base, stale after the shift (D4: the form's period, not the read)
+            w.state.mainhand_speed = 2.0 -- hasted: the rage follows the unhasted speed
+            near(8.65, models.mainhand.value())
+            near(8.65, models.mainhand.crit()) -- a white crit: one more base swing
+            assert.are.same({ "enrage", 1, 2 }, { models.enrage.aura, models.enrage.interval, models.enrage.value })
+            assert.is_nil(models.enrage.pausesDecay) -- unverified (checkpoint Q9)
+            w.state.buff.enrage, w.state.query_time = { applied = 10 }, 13.4
+            assert.are.equal(13, models.enrage.last())
+            assert.are.equal(1.25, w.resources[1].meta.decay())
+            assert.are.equal(1, w.resources[1].meta.decayInterval()) -- stepped, as the Warrior's
+        end
+    )
 
     it("declares energy with no regen model, combo points and mana with no maximum, in Classic's order", function()
         assert.are.same({ 3, 4, 1, 0 }, w.order)
@@ -958,6 +961,37 @@ describe("Forever Druid in VirtualState's now context", function()
         assert.are.same({ 0, 9 }, { I.nowErrors, I.nowRuns })
     end)
 
+    it("opens each GCD at its kind's length across shifts, and a hard cast's at its start (GCD kinds §1.6)", function()
+        local Direct, Obs = I.Sources.Direct, VS.Obs
+        local function gcd(t, len) -- the GCD spell's edges around our cast at t: its duration as GcdInfo answers it
+            Direct(Obs.Cooldown, t, 0, 1, 1)
+            VS.Drain(t + 0.03)
+            local _, d = VS.GcdInfo(t + 0.03)
+            Direct(Obs.Cooldown, t + len, 0, 0, 1)
+            VS.Drain(t + len + 0.01)
+            return d
+        end
+        cast(5221, 2) -- Shred x2: the totem kind learns 1.0
+        gcd(2, 1)
+        cast(5221, 4)
+        gcd(4, 1)
+        assert.are.same({ 0, 1 }, I.gcdLearned)
+        cast(5487, 6) -- Bear Form: the spell kind, not the last learned length
+        assert.are.equal(1.5, gcd(6, 1.5))
+        cast(768, 8) -- Cat Form
+        gcd(8, 1.5)
+        cast(5221, 10)
+        assert.are.equal(1, gcd(10, 1))
+        ctl.form = 0 -- a manual unshift (no cast), then Healing Touch's hard cast
+        ctl.Fire("UPDATE_SHAPESHIFT_FORM")
+        ctl.now, ctl.casting = 12, { 12000, 15500 }
+        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-2", 5185)
+        ctl.Tick(12.01)
+        ctl.casting = nil
+        assert.are.equal(1.5, gcd(12.02, 1.5))
+        assert.is_truthy(VS.Snapshot():find("learned=1.5000/1.0000", 1, true))
+    end)
+
     it("runs every declared `now` in the context without an error", function()
         local runs = 0
         local t = 2
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `608 successes / 1 failure / 0 errors / 0 pending`.
- druid_spec "gains rage per white swing in Bear Form only, at the form's fixed 2.5 s x 3.46 ..." fails: the stale 1.0 s base prices the swing at 3.46. The GCD case passes already (Deviation 14).

- [ ] **Step 3: Write the implementation (D4)**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Forever/Classes/Druid.lua b/src/Hekili/Forever/Classes/Druid.lua
index a846d6d9..6714759e 100644
--- a/src/Hekili/Forever/Classes/Druid.lua
+++ b/src/Hekili/Forever/Classes/Druid.lua
@@ -109,8 +109,11 @@ local FORMS = { "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic
 
 -- Shifting Power's energy (DB2 1322605 effect 30, base 40) and bear rage per white swing (spec §2.3, D4): the
 -- Warrior's measured one-hand main-hand rate x the form's unhasted 2.5 s swing, 8.65 a swing, until checkpoint Q8.
+-- The swing is the form's fixed period, not VirtualState's out-of-combat base read, which holds the pull's form (1.0 s
+-- after a Cat pull) through an in-combat shift (GCD kinds design D4; checkpoint G6 reads both forms' speeds).
 local SHIFTING_POWER_ENERGY = 40
 local BEAR_RAGE_RATE = 3.46
+local BEAR_SWING = 2.5
 -- Rip's and Rake's energy (Rake's before Ferocity's -1 a rank), shared by their `spend` and `excess_e`'s reservations.
 local RIP_COST = 30
 local RAKE_COST = 40
@@ -140,15 +143,6 @@ local function byRank(values, ids)
     return values[knownRank(ids)] or values[1]
 end
 
--- The form's unhasted swing (2.5 s in Bear Form): VirtualState's plain base read, else the believed swing speed.
-local function bearSwing()
-    local speed = VS.SwingBase(1)
-    if speed <= 0 then
-        speed = state.mainhand_speed
-    end -- no plain base read yet
-    return speed
-end
-
 -- shortcut: after a /reload in combat energy's regen rate stays 0 for the rest of the fight (VirtualState's calibrate
 -- returns early at ref == 0); upgrade with a `regen` meta field forwarded by the adapter after checkpoint Q3.
 spec:RegisterResource(Enum.PowerType.Energy)
@@ -182,10 +176,10 @@ spec:RegisterResource(
                 return state.swings.mainhand == 0 or not state.buff.bear_form.up
             end,
             value = function()
-                return BEAR_RAGE_RATE * bearSwing()
+                return BEAR_RAGE_RATE * BEAR_SWING
             end,
             crit = function()
-                return BEAR_RAGE_RATE * bearSwing()
+                return BEAR_RAGE_RATE * BEAR_SWING
             end,
         },
 
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `609 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 133 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      609 successes / 0 failures / 0 errors / 0 pending (about 139 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual src/Hekili/Engine src/Hekili/State.lua tests/Virtual | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|bear|cat|feral|maul|enrage|furor|shred|rake|rip|swipe|lacerate|bite|cat_form|bear_form|shifting_power|stance'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit (D4)**

```bash
git add src/Hekili/Forever/Classes/Druid.lua tests/Forever/druid_spec.lua
git commit -m "fix(druid): price every bear swing at the form's fixed 2.5 s, not the out-of-combat base read a Cat pull leaves at 1.0 s (GCD kinds design §4.3, D4); the GCD by kind across shifts pinned against the class file

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Write the failing spec (E10)**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/engine_load_spec.lua b/tests/Forever/engine_load_spec.lua
index 13f30788..08208b81 100644
--- a/tests/Forever/engine_load_spec.lua
+++ b/tests/Forever/engine_load_spec.lua
@@ -174,3 +174,29 @@ describe("the engine's threat table (tank design §2)", function()
         assert.is_true(threat.lost)
     end)
 end)
+
+-- Hekili's own GCD in the simulation (GCD kinds design §1.4, core edit E10), from the whole addon headless
+-- (tests/Virtual/harness/headless.lua) as a level 60 Druid in Cat Form, its power energy.
+describe("the simulation's GCD by kind in energy (core edit E10)", function()
+    local headless = require("Virtual.harness.headless")
+
+    it("prices a spell-kind press at 1.5 x haste and a totem-kind one at 1.0; gcd.max stays the typical 1.0", function()
+        local H = headless.new({
+            character = {
+                class = "DRUID",
+                classID = 11,
+                specID = 1499,
+                level = 60,
+                known = { 768, 5487, 5221 },
+                power = { type = 3, token = "ENERGY", max = 100 },
+            },
+        })
+        assert.are.same({}, H.loadErrors)
+        local S = H.Hekili.State
+        S.this_action = "bear_form"
+        assert.are.equal(1.5 * S.haste, S.gcd.execute)
+        S.this_action = "shred"
+        assert.are.equal(1, S.gcd.execute)
+        assert.are.equal(1, S.gcd.max) -- no ability context: the clause E10 keeps
+    end)
+end)
PATCH
```

- [ ] **Step 8: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `609 successes / 1 failure / 0 errors / 0 pending`.
- engine_load_spec "prices a spell-kind press at 1.5 x haste ..." fails: `state.gcd.execute` for `bear_form` in energy is 1 (Expected 1.5).

- [ ] **Step 9: Write the implementation (E10)**

```bash
git apply <<'PATCH'
diff --git a/docs/forever-facade-notes.md b/docs/forever-facade-notes.md
index 4cb8aa33..29dbc27d 100644
--- a/docs/forever-facade-notes.md
+++ b/docs/forever-facade-notes.md
@@ -262,6 +262,12 @@ Every stub site in the retained files that throws or yields a wrong value. Sites
 ## Edits no facade absorbs (feasibility doc C.5)
 
 - GCD spell 61304 -> 29515: `Classes.lua` 2469 (`id = 61304`), `UI.lua` 1493 and 1694, `Events.lua` 1675.
+- The GCD by kind (core edit E10, `State.lua` `mt_gcd`, `execute`): stock gives every spell-kind press made with
+  energy as the power type 1.0 s; E10 drops that clause from `execute` only, so such a press (a form or a spell cast
+  from an energy form) keeps 1.5 s x haste as the DB2 says (checkpoint G1), and a 1 s ability declares
+  `gcd = "totem"` as before. `max`/`duration` (no ability context: `gcd.max` in cycle and time-to expressions) keep
+  the stock clause, the typical 1 s GCD in energy. VirtualState's belief prices each GCD by the same kinds
+  (`Families/Casts.lua`, `I.GcdLen`; GCD kinds design §1.2). Revert: restore the one `if` line.
 - The enemy-scan health comparison: `Targets.lua` 434 and 511.
 - TTD: `Targets.lua` 1164-1605 needs another source of health deltas.
 - Spec identity (pseudo-spec 1491): `Classes.lua` 3077-3362 `SpecializationChanged`. `NewSpecialization` now takes
diff --git a/src/Hekili/State.lua b/src/Hekili/State.lua
index 97b5e3d4..83e95712 100644
--- a/src/Hekili/State.lua
+++ b/src/Hekili/State.lua
@@ -3194,7 +3194,8 @@ local mt_gcd = {
             if gcd == "off" then return 0 end
             if gcd == "totem" then return 1 end
 
-            if one_sec_gcd[ class.file ] or class.file == "DRUID" and UnitPowerType( "player" ) == Enum.PowerType.Energy then
+            -- Forever E10: a spell-kind press keeps 1.5 s x haste in every power type; a 1 s ability declares gcd = "totem" (checkpoint G1).
+            if one_sec_gcd[ class.file ] then
                 return state.buff.adrenaline_rush.up and max( 0.75, state.haste ) or 1
             end
 
PATCH
```

- [ ] **Step 10: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `610 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 11: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 133 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      610 successes / 0 failures / 0 errors / 0 pending (about 139 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual src/Hekili/Engine src/Hekili/State.lua tests/Virtual | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|bear|cat|feral|maul|enrage|furor|shred|rake|rip|swipe|lacerate|bite|cat_form|bear_form|shifting_power|stance'
#                                                               # [empty: the boundary]
```

- [ ] **Step 12: Commit (E10, revertable on its own)**

```bash
git add src/Hekili/State.lua tests/Forever/engine_load_spec.lua docs/forever-facade-notes.md
git commit -m "feat(state): core edit E10: a spell-kind press keeps 1.5 s x haste in every power type; gcd.max and gcd.duration stay stock (GCD kinds design §1.4, D3; checkpoint G1 confirms)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 13: Push** (orchestrator, after this task's review is clean): `git push origin gcd-kinds`

---
### Task 3: The harness core: several resources, regen and decay, the GCD's edges, shifts, crit rage, their observer and metrics

Spec §2 (§2.1-§2.5), D7, D8; Deviations 3-6.

**Files:**
- Modify: `tests/Virtual/harness/entities.lua` (`pt`, `res`, `res0`, `formSpeed`, `formSince`), `world.lua` (`W.grng`, `W.combat`, `W.rates`; `ev.pt`/`ev.resCur`; the out-of-combat reads on prepull, stop and an out-of-combat form; `W.res`, `W.effects`, `W.shift`, `W.regenRate`, `W.startRegen`, `W.startDecay`; `W.press`: the cost by type, `gcd = 0`, `e.gcdLatency`, `e.gcdOrder`; `W.hit` returns its event, `e.lastHit`), `behaviours.lua` (`p.critRage`, `p.payIn`), `observer.lua` (`k.plainPower`, `k.powerTokens`, `k.regenRead`, `k.playerSpeed`, `k.forms`; the GCD flag before the success at `ev.order == 2`; `@regen`, `@attackSpeed`, `@forms`, `@power` by type; usability `fn(W, us, power, view)`), `drive.lua` (`o.boot(c)`, `o.track`, `c.trk`, `c.gcdN/gcdS/gcdE/gcdOwned`, `c.crit3`, `c.unk`; ops `@forms`, `@regen`, `@attackSpeed`), `scenarios.lua` (the knobs `pt`, `res`, `formSpeed`, `regen`, `regenTick`, `regenAfter`, `decay`, `payIn`, `critRage`, `gcdOrder`, `gcdLatency`, `script`, `after`, `observe`), `metrics.lua` (`score`'s `keep`; `truthOf`, `power`, `gcd`, `unknown`, `crits`)
- Test: `tests/Virtual/harness/world_spec.lua` (new, 7 cases), `tests/Virtual/harness/metrics_spec.lua` (new, 3 cases), `tests/Virtual/harness/observer_spec.lua` (new describe "the observer's resources, GCD and forms", 5 cases; the cooldown case's test IDs 77/78 become 9077/9078), `tests/Virtual/harness/fixtures_spec.lua` (the vslog dump's spell ID 285 becomes 4242), `tests/boundary_spec.lua` (`CORE` gains `tests/Virtual/harness`, `SKIP` its `fixtures/`, four `ALLOW_NAMES`)

**Interfaces:**
- Consumes: the loop plan's `W.press`, `W.gain`, `W.applyAura`, `W.setForm`, `W.hit`, `e.gcdUntil`, `observer.new(W, k)`, `k.usable`, `k.gcdSpell`, `drive.boot/run/op`, `metrics.score`, `scenarios.world/stream`.
- Produces (test code, class-neutral):
  - entities: `e.pt` [1], `e.res` `{ [pt] = { cur, max } }`, `e.res0`, `e.formSpeed`, `e.formSince`, `e.gcdLatency`, `e.gcdOrder` (1, 2 or `"mixed"`), `e.lastHit`;
  - world: `W.res(e, pt)`, `W.effects(e, p)`, `W.shift(e, sh)` (`sh = { form, speed, dmgMult, onEnter = { [pt] = "zero" | "keep" | fn(W, e, pt, cur) } }`), `W.regenRate(e, pt)`, `W.startRegen(e, rates, every, after)`, `W.startDecay(e, { pt, rate, interval, pausedBy })`, `W.grng`, `W.rates`, `W.combat`, `W.after`; press fields `pt`, `gain = { pt, amount }`, `points = { pt, 1 | "all" }`, `drain = pt`, `aura = { id, duration, tick = { pt, every, amount } }`, `shift`; truth kinds "regen" and "decay", fields `ev.pt`, `ev.resCur`, `ev.order`, `ev.speed`, `ev.regen`;
  - behaviours.melee: `p.critRage = { main, off }`, `p.payIn` (a form);
  - observer knobs: `plainPower = { [pt] = "always" | "ooc" | "never" }`, `powerTokens = { [pt] = token }`, `regenRead` [true], `playerSpeed` [false], `forms` (index to spell ID); ops `@regen pt rate|nil`, `@attackSpeed main off`, `@forms list`;
  - drive: `drive.boot({ boot = fn(c), track = { pt... } })`, `c.trk[pt] = { n, t[], est[], lo[] }`, `c.gcdN`, `c.gcdS[]`, `c.gcdE[]`, `c.gcdOwned[]`, `c.crit3[]`, `c.unk[]`;
  - scenarios.world knobs as listed; `scenarios.stream(o)` applies `o.observe` over the observer's knobs;
  - metrics: `metrics.score(m, c, s, W, step, after, keep)`, `metrics.truthOf(W, pt)` -> `fn(t) -> value, lastChange`, `metrics.power(c, W, pt, overBar, { after, keep, settle })` -> `{ n, meanAbs, maxAbs, windows, over, overMax, exact, settled }`, `metrics.gcd(c, W)` -> `{ n, seen, owned, ownerless, errMax, extra }`, `metrics.unknown(c, s, keep)` -> `n, unknown`, `metrics.crits(c, s)` -> `crits, staged, false`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/harness/fixtures_spec.lua b/tests/Virtual/harness/fixtures_spec.lua
index efeda112..ec13339c 100644
--- a/tests/Virtual/harness/fixtures_spec.lua
+++ b/tests/Virtual/harness/fixtures_spec.lua
@@ -192,11 +192,11 @@ describe("tools/vslog_fixture.lua", function()
             "   771 PLAYER_SWING 2.2000000476837 0 nil nil nil",
             "  1297 UNIT_COMBAT player PARRY  0 1",
             "  2463 UNIT_COMBAT target WOUND CRITICAL 90 1",
-            "  4330 UNIT_SPELLCA player Cast-3-4615-1-2-285-4C4F5AEFDD 285 nil nil",
+            "  4330 UNIT_SPELLCA player Cast-3-4615-1-2-4242-4C4F5AEFDD 4242 nil nil",
             " 49873 UNIT_SPELLCA party1 S S CastBar-9296D9AA6601D8FE nil",
             "vslog n=6 dropped=0",
         }, "\n")
-        local rows = assert(loadfile("tools/vslog_fixture.lua"))("rows", dump, { ["285"] = "STRIKE" })
+        local rows = assert(loadfile("tools/vslog_fixture.lua"))("rows", dump, { ["4242"] = "STRIKE" })
         assert.are.same({
             { 0, "C", "player", "OTHER" },
             { 771, "S", 2.2, 0 },
diff --git a/tests/Virtual/harness/metrics_spec.lua b/tests/Virtual/harness/metrics_spec.lua
new file mode 100644
index 00000000..5afc17c9
--- /dev/null
+++ b/tests/Virtual/harness/metrics_spec.lua
@@ -0,0 +1,72 @@
+-- tests/Virtual/harness/metrics_spec.lua (GCD kinds design §2.4): the per-type power error, the GCD match, the
+-- timing-alone share and the crit staging, on hand-made captures and truth (class-neutral: bare power types).
+local world = require("Virtual.harness.world")
+local entities = require("Virtual.harness.entities")
+local metrics = require("Virtual.harness.metrics")
+
+describe("the harness metrics", function()
+    local W, us
+    local POOL = 3
+
+    before_each(function()
+        W = world.new(1)
+        us = W.add(entities.new({ guid = "Player-1", res = { [POOL] = { cur = 50, max = 100 } } }))
+    end)
+
+    local function ticks(list) -- { { t, est, lo } }
+        local r = { n = #list, t = {}, est = {}, lo = {} }
+        for k, x in ipairs(list) do
+            r.t[k], r.est[k], r.lo[k] = x[1], x[2], x[3]
+        end
+        return r
+    end
+
+    it(
+        "scores a tracked type's belief against its truth: mean and max error, overshoot windows, settled exactness",
+        function()
+            W.t = 1
+            W.emit({ kind = "gain", src = us, pt = POOL, cost = 20 }) -- 30 from 1 s
+            W.t = 12
+            W.emit({ kind = "gain", src = us, pt = POOL, rage = 10 }) -- 40 from 12 s
+            W.t = 20 -- the world's end: a tick after it is not scored
+            local c = {
+                trk = {
+                    [POOL] = ticks({ { 0.5, 50, 50 }, { 1.1, 50, 30 }, { 2, 30, 30 }, { 12.1, 40, 46 }, { 25, 0, 0 } }),
+                },
+            }
+            local p = metrics.power(c, W, POOL, 5)
+            assert.are.same({ 4, 20, 2, 1 }, { p.n, p.maxAbs, p.windows, p.over }) -- 46 over 40 by 6: the second window
+            assert.are.equal(5, p.meanAbs)
+            assert.are.equal(1, p.exact) -- 1.1 and 12.1 are inside the settle time: 0.5 and 2 count, both exact
+            assert.are.equal(2, p.settled)
+        end
+    )
+
+    it("matches each believed GCD to the press that opened it, its end error and its opener", function()
+        W.t = 5
+        W.emit({ kind = "cast", src = us, spell = 1, gcd = 1.0 })
+        W.t = 7
+        W.emit({ kind = "cast", src = us, spell = 2, gcd = 1.5 })
+        local c = { gcdN = 3, gcdS = { 5.0005, 7, 20 }, gcdE = { 6.0005, 8.5, 21 }, gcdOwned = { 1, 0, 0 } }
+        local g = metrics.gcd(c, W)
+        assert.are.same({ 2, 2, 1, 1, 1 }, { g.n, g.seen, g.owned, g.ownerless, g.extra })
+        assert.is_true(math.abs(g.errMax - 0.0005) < 1e-9)
+    end)
+
+    it("counts our white wounds scored on timing alone, and the crits staged among the credited", function()
+        local s =
+            { n = 3, ev = {}, src = { 1, 1, 2 }, hand = { 1, 1, 0 }, a1 = {}, a3 = { "", "CRITICAL", "" }, a4 = {} }
+        s.t = { 1, 2, 3 }
+        for i = 1, 3 do
+            s.ev[i], s.a1[i], s.a4[i] = "UNIT_COMBAT", "target", 30
+        end
+        local c = { unk = { 0, 1, 1 }, crHand = { 1, 1, 0 }, crit3 = { 0, 1, 0 } }
+        assert.are.same({ 2, 1 }, { metrics.unknown(c, s) })
+        assert.are.same({ 1, 0 }, {
+            metrics.unknown(c, s, function(t)
+                return t < 1.5
+            end),
+        })
+        assert.are.same({ 1, 1, 0 }, { metrics.crits(c, s) })
+    end)
+end)
diff --git a/tests/Virtual/harness/observer_spec.lua b/tests/Virtual/harness/observer_spec.lua
index 52be92f8..a756b3e1 100644
--- a/tests/Virtual/harness/observer_spec.lua
+++ b/tests/Virtual/harness/observer_spec.lua
@@ -375,8 +375,8 @@ describe("the observer", function()
                 kind = "cast",
                 src = us,
                 dst = mob,
-                spell = 77,
-                ids = { 77, 78 },
+                spell = 9077,
+                ids = { 9077, 9078 },
                 cost = 10,
                 cd = 6,
                 gcd = 1.5,
@@ -395,18 +395,153 @@ describe("the observer", function()
                 { 1.6, "@health", "target", 1000, 1000 },
                 { 4, "@health", "target", 960, 1000 },
                 { 4, "@power", 1, 12 },
-                { 5, "@cooldown", 77, 5, 6 },
-                { 5, "@cooldown", 78, 5, 6 },
+                { 5, "@cooldown", 9077, 5, 6 },
+                { 5, "@cooldown", 9078, 5, 6 },
                 { 5, "@cooldown", 900, 5, 1.5 },
                 { 5, "@power", 1, 2 },
                 { 6.5, "@cooldown", 900, 0, 0 },
-                { 11, "@cooldown", 77, 0, 0 },
-                { 11, "@cooldown", 78, 0, 0 },
+                { 11, "@cooldown", 9077, 0, 0 },
+                { 11, "@cooldown", 9078, 0, 0 },
             }, got)
         end
     )
 end)
 
+-- The client facts several resources, the GCD and form shifts add (GCD kinds design §2.3), one rule per case.
+describe("the observer's resources, GCD and forms", function()
+    local W, us, mob
+    local POOL, POINTS, GCD = 3, 4, 900 -- power types and the GCD spell, as bare numbers
+
+    local function setup()
+        W = world.new(7)
+        us = W.add(entities.new({
+            guid = "Player-1",
+            weapons = { { 10, 10, 2.0 } },
+            res = { [POOL] = { cur = 100, max = 100 }, [POINTS] = { cur = 0, max = 5 } },
+            formSpeed = { [1] = 2.5 },
+        }))
+        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } }, health = 1e6 }))
+        us.target = mob -- not on us: no targettarget rows
+    end
+
+    local function knobs(o)
+        return setmetatable(o, { __index = observer.DEFAULTS })
+    end
+
+    -- The stream as "t ev a1 a2" lines (ops included, the time-0 answers left out), only the events `keep` names.
+    local function lines(s, keep)
+        local out = {}
+        for i = 1, s.n do
+            if s.t[i] > 0 and (not keep or keep[s.ev[i]]) then
+                local a2 = rawequal(s.a2[i], fake.SECRET) and "SECRET" or tostring(s.a2[i])
+                out[#out + 1] = table.concat({ s.t[i], s.ev[i], tostring(s.a1[i]), a2 }, " ")
+            end
+        end
+        return out
+    end
+
+    it("fires the GCD flag's edges after the success or before it, by the press's order", function()
+        setup()
+        us.gcdOrder = 2
+        W.t = 2
+        W.press(us, "a", { spell = 11, gcd = 1.0 })
+        us.gcdOrder = 1
+        W.t = 4
+        W.press(us, "a", { spell = 11, gcd = 1.0 })
+        local keep = { UNIT_SPELLCAST_SUCCEEDED = true, ["@cooldown"] = true, SPELL_UPDATE_COOLDOWN = true }
+        assert.are.same({
+            "2 @cooldown 900 SECRET",
+            "2 SPELL_UPDATE_COOLDOWN nil nil",
+            "2 UNIT_SPELLCAST_SUCCEEDED player Cast-1",
+            "3 @cooldown 900 nil",
+            "3 SPELL_UPDATE_COOLDOWN nil nil",
+            "4 UNIT_SPELLCAST_SUCCEEDED player Cast-2",
+            "4 @cooldown 900 SECRET",
+            "4 SPELL_UPDATE_COOLDOWN nil nil",
+            "5 @cooldown 900 nil",
+            "5 SPELL_UPDATE_COOLDOWN nil nil",
+        }, lines(observer.observe(W, knobs({ gcdSpell = GCD })), keep))
+    end)
+
+    it("answers each power type by its mode: always, out of combat only, never", function()
+        setup()
+        local modes = { [POOL] = "ooc", [POINTS] = "always", [1] = "never" }
+        local tokens = { [POOL] = "POOL", [POINTS] = "POINTS" }
+        W.t = 1
+        W.emit({ kind = "gain", src = us, pt = POOL, cost = 10 })
+        W.emit({ kind = "pull" })
+        W.t = 2
+        W.emit({ kind = "gain", src = us, pt = POOL, cost = 20 })
+        W.emit({ kind = "gain", src = us, pt = POINTS, rage = 1 })
+        W.emit({ kind = "gain", src = us, rage = 5 })
+        W.t = 3
+        W.emit({ kind = "stop" })
+        local s = observer.observe(W, knobs({ plainPower = modes, powerTokens = tokens }))
+        assert.are.same({
+            "1 @power 3 90",
+            "1 UNIT_POWER_FREQUENT player POOL",
+            "1 @power 3 nil", -- in combat: secret
+            "2 @power 4 1",
+            "2 UNIT_POWER_FREQUENT player POINTS",
+            "3 @power 3 70", -- out of combat again
+            "3 UNIT_POWER_FREQUENT player POOL",
+        }, lines(s, { ["@power"] = true, UNIT_POWER_FREQUENT = true }))
+    end)
+
+    it("reads the regen rate out of combat with the caches, secret in combat; none without the read", function()
+        setup()
+        W.startRegen(us, { [POOL] = 10 })
+        W.at(1, function()
+            W.emit({ kind = "prepull" })
+        end)
+        W.at(2, function()
+            W.emit({ kind = "pull" })
+        end)
+        W.at(5, function()
+            W.emit({ kind = "stop" })
+        end)
+        W.run(5.5)
+        assert.are.same(
+            { "1 @regen 3 10", "2 @regen 3 nil", "5 @regen 3 10" },
+            lines(observer.observe(W, knobs({})), { ["@regen"] = true })
+        )
+        assert.are.same({}, lines(observer.observe(W, knobs({ regenRead = false })), { ["@regen"] = true }))
+    end)
+
+    it("fires a shift's success, then the form; the player's attack speed out of combat only", function()
+        setup()
+        W.t = 1
+        W.press(us, "shift", { spell = 12, gcd = 1.5, shift = { form = 1 } })
+        W.emit({ kind = "pull" })
+        W.t = 3
+        W.press(us, "shift", { spell = 13, gcd = 1.5, shift = { form = 0, speed = 1.0 } })
+        local keep = { UNIT_SPELLCAST_SUCCEEDED = true, ["@form"] = true, UPDATE_SHAPESHIFT_FORM = true }
+        keep["@attackSpeed"] = true
+        assert.are.same({
+            "1 UNIT_SPELLCAST_SUCCEEDED player Cast-1",
+            "1 @form 1 nil",
+            "1 UPDATE_SHAPESHIFT_FORM nil nil",
+            "1 @attackSpeed 2.5 nil", -- out of combat: the form's period, with the damage cache
+            "3 UNIT_SPELLCAST_SUCCEEDED player Cast-2",
+            "3 @form 0 nil",
+            "3 UPDATE_SHAPESHIFT_FORM nil nil", -- in combat: no read
+        }, lines(observer.observe(W, knobs({ playerSpeed = true })), keep))
+    end)
+
+    it("answers usability against each rung's own type, the client's view a gain late", function()
+        setup()
+        local function pool(_, _, _, view)
+            return view[POOL] >= 60, view[POOL] < 60
+        end
+        W.t = 1
+        W.emit({ kind = "gain", src = us, pt = POOL, cost = 50 })
+        W.t = 2
+        W.emit({ kind = "gain", src = us, pt = POOL, rage = 20 })
+        local s = observer.observe(W, knobs({ usable = { { 21, pool } }, usableDelay = 0.1 }))
+        assert.are.same({ "1 @usable 21 2", "2.1 @usable 21 1" }, lines(s, { ["@usable"] = true }))
+    end)
+end)
+
 describe("the world", function()
     it("takes health for every wound but our white swing's (ours at its land), and gives it for heals", function()
         local W = world.new(7)
diff --git a/tests/Virtual/harness/world_spec.lua b/tests/Virtual/harness/world_spec.lua
new file mode 100644
index 00000000..933669f4
--- /dev/null
+++ b/tests/Virtual/harness/world_spec.lua
@@ -0,0 +1,179 @@
+-- tests/Virtual/harness/world_spec.lua (GCD kinds design §2.1-§2.2): the world's truth for several resources, regen
+-- and out-of-combat decay, the GCD's refusal, form shifts with their resource rules, and white rage by form and crit.
+-- Class-neutral: power types and aura IDs are bare numbers.
+local world = require("Virtual.harness.world")
+local entities = require("Virtual.harness.entities")
+local behaviours = require("Virtual.harness.behaviours")
+
+describe("the world's resources", function()
+    local W, us, mob
+    local SWUNG, POOL, POINTS = 1, 3, 4 -- the swing-paid type, a regenerating pool, a points resource
+
+    local function setup(o)
+        W = world.new(3)
+        us = W.add(entities.new({
+            guid = "Player-1",
+            weapons = { { 10, 10, 2.0 } },
+            res = { [POOL] = { cur = 50, max = 100 }, [POINTS] = { cur = 0, max = 5 } },
+            formSpeed = { [1] = 2.5, [2] = 1.0 },
+        }))
+        mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", weapons = { { 10, 14, 2 } }, health = 1e6 }))
+        mob.avoid = { miss = 0, dodge = 0, parry = 0 }
+        us.target, mob.target = mob, us
+        for key, v in pairs(o or {}) do
+            us[key] = v
+        end
+    end
+
+    it("refuses a press until the GCD and its latency are over, and keeps each type's cost apart", function()
+        setup({ gcdLatency = 0.05 })
+        W.t = 10
+        assert.is_true(W.press(us, "a", { spell = 1, gcd = 1.0, cost = 20, pt = POOL }))
+        assert.are.same({ 30, 0, 11.05 }, { W.res(us, POOL), us.power, us.gcdUntil })
+        W.t = 11.04
+        assert.are.same({ false, "gcd" }, { W.press(us, "b", { spell = 2, gcd = 1.0 }) })
+        assert.are.same({ false, "cost" }, { W.press(us, "c", { spell = 3, gcd = 0, cost = 40, pt = POOL }) })
+        W.t = 11.05
+        assert.is_true(W.press(us, "b", { spell = 2, gcd = 1.0 }))
+        local casts = {}
+        for _, ev in ipairs(W.truth) do
+            if ev.kind == "cast" then
+                casts[#casts + 1] = { ev.t, ev.gcd, ev.order }
+            end
+        end
+        assert.are.same({ { 10, 1.05, 1 }, { 11.05, 1.05, 1 } }, casts)
+    end)
+
+    it("rolls the GCD flag's order from its own generator when mixed, leaving the world's two alone", function()
+        setup({ gcdOrder = "mixed" })
+        local before = { W.rng.next(), W.crng.next() }
+        setup({ gcdOrder = "mixed" })
+        local seen = {}
+        for k = 1, 40 do
+            W.t = 2 * k
+            W.press(us, "a", { spell = 1, gcd = 1.0 })
+            seen[W.truth[#W.truth].order] = true
+        end
+        assert.are.same({ true, true }, seen)
+        assert.are.same(before, { W.rng.next(), W.crng.next() })
+    end)
+
+    it(
+        "runs a builder's point on a landed hit, a finisher's spend of all, a drain, a gain and a ticking aura",
+        function()
+            setup()
+            W.t = 1
+            local hit = function(w, e)
+                w.hit(e, e.target, 30)
+            end
+            W.press(us, "build", { spell = 1, gcd = 0, effect = hit, points = { POINTS, 1 } })
+            W.press(us, "build", { spell = 1, gcd = 0, effect = hit, points = { POINTS, 1 } })
+            assert.are.equal(2, W.res(us, POINTS))
+            W.press(
+                us,
+                "finish",
+                { spell = 2, gcd = 0, cost = 10, pt = POOL, points = { POINTS, "all" }, drain = POOL }
+            )
+            assert.are.same({ 0, 0 }, { W.res(us, POINTS), W.res(us, POOL) })
+            W.press(us, "gain", { spell = 3, gcd = 0, gain = { POOL, 40 } })
+            assert.are.equal(40, W.res(us, POOL))
+            W.press(us, "tick", {
+                spell = 4,
+                gcd = 0,
+                gain = { SWUNG, 10 },
+                aura = { id = 77, duration = 10, tick = { pt = SWUNG, every = 1, amount = 2 } },
+            })
+            W.run(30)
+            assert.are.equal(10 + 2 * 10, us.power) -- every tick lands, the one at its expiry too
+            assert.is_nil(us.auras[77])
+        end
+    )
+
+    it("regenerates at its rate every tick, capped, and by the ramp after its seconds in one form", function()
+        setup()
+        W.startRegen(us, { [POOL] = 10 }, 0.1, { s = 5, k = 1.25 })
+        W.run(4.05)
+        assert.is_true(math.abs(W.res(us, POOL) - 90) < 1e-6, tostring(W.res(us, POOL)))
+        W.run(6)
+        assert.are.equal(100, W.res(us, POOL)) -- capped: no event at the maximum
+        W.press(us, "spend", { spell = 1, gcd = 0, cost = 100, pt = POOL })
+        W.run(7.05) -- 6 s and more in form 0: the ramp's rate
+        assert.is_true(math.abs(W.res(us, POOL) - 12.5) < 1e-6, tostring(W.res(us, POOL)))
+        local last = W.truth[#W.truth]
+        assert.are.same({ "regen", POOL }, { last.kind, last.pt })
+    end)
+
+    it(
+        "decays out of combat stepped and front-loaded; an aura that pauses it moves the next quantum to its expiry",
+        function()
+            for _, paused in ipairs({ false, true }) do
+                setup()
+                us.power = 40
+                W.t = 57
+                W.applyAura(us, 88, 10)
+                W.t = 60
+                W.startDecay(us, { pt = SWUNG, rate = 1.25, interval = 1, pausedBy = paused and 88 })
+                W.run(60.5)
+                assert.are.equal(paused and 40 or 38.75, us.power)
+                W.run(66.5)
+                assert.are.equal(paused and 40 or 40 - 1.25 * 7, us.power)
+                W.run(67.5)
+                assert.are.equal(paused and 38.75 or 40 - 1.25 * 8, us.power, tostring(paused))
+            end
+        end
+    )
+
+    it(
+        "shifts after its cast: the form, the main hand's period, the weapon factor and each type's entry rule",
+        function()
+            setup()
+            us.power = 30
+            W.t = 5
+            local sh = {
+                form = 1,
+                dmgMult = 1.6,
+                onEnter = {
+                    [SWUNG] = "zero",
+                    [POOL] = "keep",
+                    [POINTS] = function(_, _, _, cur)
+                        return cur + 2
+                    end,
+                },
+            }
+            assert.is_true(W.press(us, "shift", { spell = 9, gcd = 1.5, shift = sh }))
+            assert.are.same(
+                { 1, 2.5, 1.6, 0, 50, 2 },
+                { us.form, us.weapons[1][3], us.dmgMult, us.power, W.res(us, POOL), W.res(us, POINTS) }
+            )
+            local kinds = {}
+            for _, ev in ipairs(W.truth) do
+                kinds[#kinds + 1] = ev.kind
+            end
+            assert.are.same({ "cast", "form", "gain", "gain" }, { kinds[1], kinds[2], kinds[3], kinds[4] })
+            assert.is_table(W.truth[2].damage) -- out of combat: the caches read the form's own
+            W.emit({ kind = "pull" })
+            W.shift(us, { form = 2 })
+            assert.are.same({ 1.0, nil }, { us.weapons[1][3], W.truth[#W.truth].damage }) -- in combat: no read
+        end
+    )
+
+    it("pays white rage only in the paying form, and a crit's extra on top", function()
+        setup()
+        local rates = { miss = 0, dodge = 0, parry = 0, crit = 1 }
+        behaviours.melee({
+            rates = rates,
+            land = function()
+                return 0.1
+            end,
+            phase = { 1 },
+            rage = { 5 },
+            critRage = { 3 },
+            payIn = 1,
+        })(W, us)
+        W.run(1.5) -- the swing at 1 lands at 1.1, in form 0: nothing
+        assert.are.equal(0, us.power)
+        W.setForm(us, 1)
+        W.run(3.5) -- the swing at 3: 5 and the crit's 3
+        assert.are.equal(8, us.power)
+    end)
+end)
diff --git a/tests/boundary_spec.lua b/tests/boundary_spec.lua
index d53d2e01..8c07118e 100644
--- a/tests/boundary_spec.lua
+++ b/tests/boundary_spec.lua
@@ -1,9 +1,10 @@
 -- tests/boundary_spec.lua
 -- The core/content boundary (core leakage audit, docs/research/2026-10-16-core-leakage-audit.md): the core engine
--- (src/Hekili/Virtual/**, src/Hekili/Engine/**) names no ability, aura or talent key and no spell ID that the Forever
--- content (src/Hekili/Forever/**: Classes, Races, Shared) registers, and no class or form/stance name. Ported from Taco
--- Dog Forever's tests/boundary_spec.lua, which scans for a fixed word list; here the keys and IDs are
--- extracted from the content at test time, so a new ability is checked without being listed.
+-- (src/Hekili/Virtual/**, src/Hekili/Engine/**) and the harness core (tests/Virtual/harness/**, GCD kinds design D7)
+-- name no ability, aura or talent key and no spell ID that the Forever content (src/Hekili/Forever/**: Classes, Races,
+-- Shared) registers, and no class or form/stance name. Ported from Taco Dog Forever's tests/boundary_spec.lua, which
+-- scans for a fixed word list; here the keys and IDs are extracted from the content at test time, so a new ability is
+-- checked without being listed.
 -- Code only: comments are skipped, and so is a string with whitespace (a message or a description); each word of any
 -- other string (`buff["rend"]`, `"buff.rend.up"`, `"772"`) is checked like an identifier or a number. A multi-part key
 -- (`heroic_strike`) also matches as parts of an identifier (`HEROIC_STRIKE_COST`); a one-word key matches whole only.
@@ -12,7 +13,10 @@ local loaders = {
     Druid = require("Forever.helpers.load_druid"),
 }
 
-local CORE = { "src/Hekili/Virtual", "src/Hekili/Engine" }
+-- The harness core too (GCD kinds design D7), but its captured logs (tests/Virtual/harness/fixtures/): their numbers
+-- are times in ms and amounts, never IDs.
+local CORE = { "src/Hekili/Virtual", "src/Hekili/Engine", "tests/Virtual/harness" }
+local SKIP = { "^tests/Virtual/harness/fixtures/" }
 
 -- Content names core may use, each with its reason.
 local ALLOW_KEYS = {
@@ -37,6 +41,11 @@ local ALLOW_NAMES = {
     GetActiveLossOfControlDataCount = "a WoW API name",
     GetSpellLossOfControlCooldown = "a WoW API name",
     IsInBattle = "a WoW API name",
+    -- WoW globals the headless shell stubs (tests/Virtual/harness/headless.lua), matched by their parts
+    C_BattleNet = "a WoW API name",
+    SPELL_FAILED_NOT_IN_MAGE_TOWER = "a WoW GlobalStrings name",
+    TOOLTIP_NOT_IN_MAGE_TOWER = "a WoW GlobalStrings name",
+    BATTLE_PET_NAME_4 = "a WoW GlobalStrings name",
 }
 local ALLOW_IDS = {
     [29515] = "the client's GCD spell (Constants), not content",
@@ -234,7 +243,13 @@ local function coreFiles()
     local p = assert(io.popen("find " .. table.concat(CORE, " ") .. " -type f -name '*.lua' | sort"))
     local list = {}
     for path in p:lines() do
-        list[#list + 1] = path
+        local skip = false
+        for _, pat in ipairs(SKIP) do
+            skip = skip or path:match(pat) ~= nil
+        end
+        if not skip then
+            list[#list + 1] = path
+        end
     end
     p:close()
     return list
@@ -354,15 +369,18 @@ describe("core/content boundary", function()
         assert.are.same({ 1, 2, 3, 4, 5, 6, 7, 7, 8, 9 }, lines)
     end)
 
-    it("keeps content keys, spell IDs, class and form names out of Virtual/** and Engine/**", function()
-        local found = {}
-        local files = coreFiles()
-        assert.is_true(#files > 30)
-        for _, path in ipairs(files) do
-            for _, hit in ipairs(leaks(path, read(path), c, words)) do
-                found[#found + 1] = hit
+    it(
+        "keeps content keys, spell IDs, class and form names out of Virtual/**, Engine/** and the harness core",
+        function()
+            local found = {}
+            local files = coreFiles()
+            assert.is_true(#files > 30)
+            for _, path in ipairs(files) do
+                for _, hit in ipairs(leaks(path, read(path), c, words)) do
+                    found[#found + 1] = hit
+                end
             end
+            assert.are.same({}, found)
         end
-        assert.are.same({}, found)
-    end)
+    )
 end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `610 successes / 5 failures / 10 errors / 0 pending`.
- metrics_spec's 3 cases error (`metrics.power`, `gcd`, `unknown` are nil); world_spec's 7 and observer_spec's 5 new cases fail or error (no `W.res`, `W.startRegen`, `W.startDecay`, `W.shift`, press effects, power modes, regen reads, edge order).
- boundary_spec, fixtures_spec and the old observer cases pass: the allow-list, the skip and the changed IDs land with the scan.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/harness/behaviours.lua b/tests/Virtual/harness/behaviours.lua
index 6d89c050..71f56edb 100644
--- a/tests/Virtual/harness/behaviours.lua
+++ b/tests/Virtual/harness/behaviours.lua
@@ -46,7 +46,8 @@ end
 --- A melee player: per weapon hand, a swing every speed / haste from a random phase, its outcome rolled from `p.rates`
 --- (default RATES). `p.land(W, e, hand, t)`: ours only, the lag before the outcome lands (observer.lua); without it the
 --- outcome is at the swing (another player's). `p.rage` { main, off } or fn(hand, amount, flag): what a landed wound
---- of ours pays. A queued strike (W.queueStrike) our power no longer covers at the swing is dropped (a white swing).
+--- of ours pays; `p.critRage` { main, off }: the extra a CRITICAL one pays; `p.payIn`: the form whose landed wounds pay
+--- (nil: every form). A queued strike (W.queueStrike) our power no longer covers at the swing is dropped (a white swing).
 --- `p.presses` { { t, spell, cost, kind } }: kind "queue" (the next main-hand swing is a strike of `p.strike`
 --- { lo, hi }), "dot" (`p.dot` { every, n, amount } ticks, school 1), "cast" (no outcome); each only if our power
 --- covers its cost.
@@ -124,6 +125,12 @@ function M.melee(p)
                             else
                                 rage = act == "WOUND" and rage and rage[h] or nil
                             end
+                            if act == "WOUND" and flag == "CRITICAL" and p.critRage then
+                                rage = (rage or 0) + (p.critRage[h] or 0)
+                            end
+                            if p.payIn and e.form ~= p.payIn then
+                                rage = nil
+                            end
                             W.emit({
                                 kind = "land",
                                 src = e,
diff --git a/tests/Virtual/harness/drive.lua b/tests/Virtual/harness/drive.lua
index aefe2bec..dc7ad9b9 100644
--- a/tests/Virtual/harness/drive.lua
+++ b/tests/Virtual/harness/drive.lua
@@ -1,8 +1,10 @@
 -- tests/Virtual/harness/drive.lua (harness design §3.1): boots VirtualState on fake_api and the fake spec as
 -- pairing_replay_spec does, fires an observed stream through `ctl`, ticks and folds every TICK seconds, and captures
 -- what the addon concluded: each `Swing` c = 1 / c = 3 staged (through an S.Stage wrapper, tagged with the stream event
--- being fired), the combat-log rows (a COMBAT_LOG_EVENT_UNFILTERED sink) and the believed rage at each 10 s window.
--- The run loop allocates nothing: the stream and every capture array are built before it.
+-- being fired), the combat-log rows (a COMBAT_LOG_EVENT_UNFILTERED sink), the believed rage at each 10 s window, each
+-- tracked power type's believed value at every tick, each GCD as GcdInfo first answered it, and per stream index the
+-- crits staged and the white wounds Rows.lua scored on timing alone (a stale form cache). The run loop allocates
+-- nothing: the stream and every capture array are built before it.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local fs = require("Virtual.State.helpers.fake_spec")
@@ -19,7 +21,9 @@ local PLAIN_READY = { isActive = false, isOnGCD = false, startTime = 0, duration
 
 --- A booted VirtualState: { api, ctl, ns, VS, I, L, captures }. `o.rage` { main, off } per landed swing [9, 5],
 --- `o.max` the rage cap [1e6]; `o.damage` the UnitDamage cache's first values (default zeros: read at the pull);
---- `o.oracle == false` unregisters Rows' oracle hooks (the no-oracle run).
+--- `o.oracle == false` unregisters Rows' oracle hooks (the no-oracle run). `o.boot(c)`: the content builds the
+--- definition and starts VirtualState itself (`c.ns`, `c.api`, `c.ctl`; default: the fake spec's, as today).
+--- `o.track` { powerType... }: the types whose believed est and lo are captured at every tick (`c.trk[pt]`).
 function M.boot(o)
     o = o or {}
     local api, ctl = fake.new()
@@ -38,11 +42,15 @@ function M.boot(o)
     local ns = load.module()
     c.ns, c.VS, c.I = ns, ns.VirtualState, ns.VirtualStateInternal
     c.L = c.I.Log
-    local def = fs.def(fs.new((o.rage or { 9, 5 })[1]))
-    def.resources[1].swingOff = (o.rage or { 9, 5 })[2]
-    def.resources[1].max = o.max or 1e6
-    c.I.Build(def, 0.1)
-    c.VS.Start(api)
+    if o.boot then
+        o.boot(c)
+    else
+        local def = fs.def(fs.new((o.rage or { 9, 5 })[1]))
+        def.resources[1].swingOff = (o.rage or { 9, 5 })[2]
+        def.resources[1].max = o.max or 1e6
+        c.I.Build(def, 0.1)
+        c.VS.Start(api)
+    end
     -- captures, by stream index: the hand credited and the swing time it was credited at (0: none)
     c.crHand, c.crAt, c.crTok, c.verdict, c.recIdx, c.onus = {}, {}, {}, {}, {}, {}
     c.lateHand, c.lateAt = {}, {} -- credits staged outside an event (the oracle's rescue)
@@ -58,6 +66,23 @@ function M.boot(o)
     for k = 1, 8 do
         c.recIdx[k] = 0
     end
+    c.crit3, c.unk = {}, {} -- by stream index: a c = 3 staged at it; a white wound of ours scored on timing alone
+    for i = 1, CAP do
+        c.crit3[i], c.unk[i] = 0, 0
+    end
+    c.trk = {} -- [pt] = { n, t[], est[], lo[] } per tick
+    for _, pt in ipairs(o.track or {}) do
+        local r = { n = 0, t = {}, est = {}, lo = {} }
+        for i = 1, CAP do
+            r.t[i], r.est[i], r.lo[i] = 0, 0, 0
+        end
+        c.trk[pt] = r
+    end
+    -- each GCD GcdInfo answered: its start and end, and whether an opener owned it at that tick
+    c.gcdN, c.gcdS, c.gcdE, c.gcdOwned = 0, {}, {}, {}
+    for i = 1, CAP do
+        c.gcdS[i], c.gcdE[i], c.gcdOwned[i] = 0, 0, 0
+    end
     c.crits, c.landed = { 0, 0 }, { 0, 0 }
     c.rows = { swing = 0, missed = 0, spell = 0, noDst = 0, order = 0 }
     c.lastRow = { 0, 0 }
@@ -72,6 +97,9 @@ function M.boot(o)
             local i = c.cur
             if cc == 3 then
                 c.crits[a] = c.crits[a] + 1
+                if i > 0 then
+                    c.crit3[i] = c.crit3[i] + 1
+                end
             elseif i > 0 then
                 c.landed[a] = c.landed[a] + 1
                 c.crHand[i], c.crAt[i], c.crTok[i] = a, t, c.stream.a1[i] == "target"
@@ -216,6 +244,12 @@ local function op(c, ctl, ev, a1, a2, a3, a4, a5)
         else
             ctl.cooldown[a1] = { isActive = true, isOnGCD = false, startTime = a2, duration = a3 }
         end
+    elseif ev == "@forms" then -- the client's forms, index to spell ID (the content's list)
+        ctl.forms = a1
+    elseif ev == "@regen" then -- powerType, the rate (nil: secret); allocates (no 0-byte drive fires one)
+        ctl.regen[a1] = a2 and { a2, a2 } or nil
+    elseif ev == "@attackSpeed" then -- the player's main and off hand
+        ctl.speed[1], ctl.speed[2] = a1, a2
     end
 end
 
@@ -240,6 +274,18 @@ local function tick(c, t)
     if c.nWin > 0 and ((p.lo >= 10 and c.truth < 10) or (p.lo >= 15 and c.truth < 15)) then
         c.danger[c.nWin] = 1
     end
+    for pt, r in pairs(c.trk) do
+        if r.n < CAP then
+            local b = c.VS.Power(pt, t)
+            local n = r.n + 1
+            r.n, r.t[n], r.est[n], r.lo[n] = n, t, b.est, b.lo
+        end
+    end
+    local gs, gd = c.VS.GcdInfo(t)
+    if gs > 0 and gs ~= c.gcdS[c.gcdN] and c.gcdN < CAP then
+        local n = c.gcdN + 1
+        c.gcdN, c.gcdS[n], c.gcdE[n], c.gcdOwned[n] = n, gs, gs + gd, c.I.gcdOwner > 0 and 1 or 0
+    end
 end
 
 --- Fires stream `s` (observer.lua) through the booted VirtualState, `offset` seconds later than its times (a replay
@@ -251,8 +297,12 @@ function M.run(c, s, offset)
     local ctl = c.ctl
     c.stream = s
     for i = 1, s.n do
-        c.crHand[i], c.crAt[i], c.verdict[i], c.onus[i] = 0, 0, 0, ""
+        c.crHand[i], c.crAt[i], c.verdict[i], c.onus[i], c.crit3[i], c.unk[i] = 0, 0, 0, "", 0, 0
     end
+    for _, r in pairs(c.trk) do
+        r.n = 0
+    end
+    c.gcdN = 0
     c.hits = 0
     c.crits[1], c.crits[2], c.landed[1], c.landed[2], c.nLate, c.nWin, c.truth, c.nAv = 0, 0, 0, 0, 0, 0, 0, 0
     local rows = c.rows
@@ -272,6 +322,10 @@ function M.run(c, s, offset)
             op(c, ctl, ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
         else
             c.cur = i
+            if ev == "UNIT_COMBAT" and s.src[i] == 1 and s.hand[i] > 0 and s.a1[i] == "target" and s.a4[i] > 0 then
+                local _, maxMain = c.VS.Stat("UnitDamage") -- Rows.lua's stale-form test, as it reads it now
+                c.unk[i] = (maxMain <= 0 or ctl.form ~= c.I.damageForm) and 1 or 0
+            end
             local avoids = c.L.avoids
             ctl.Fire(ev, s.a1[i], s.a2[i], s.a3[i], s.a4[i], s.a5[i])
             if c.L.avoids > avoids and c.nAv < CAP then
diff --git a/tests/Virtual/harness/entities.lua b/tests/Virtual/harness/entities.lua
index abc232e4..0711d810 100644
--- a/tests/Virtual/harness/entities.lua
+++ b/tests/Virtual/harness/entities.lua
@@ -16,7 +16,9 @@ function M.weapons(level, speeds)
 end
 
 --- A new actor. `o`: guid, kind ("player", "mob", "pet"), level, weapons ({ { min, max, speed }, ... }), dr (the
---- damage its armour takes away, 0-1), avoid ({ miss, dodge, parry, block } on swings at it), health, powerMax.
+--- damage its armour takes away, 0-1), avoid ({ miss, dodge, parry, block } on swings at it), health, powerMax, pt (the
+--- power type of `power`, the swing-paid resource [1]), res ({ [powerType] = { cur, max } }: the other resources),
+--- formSpeed ({ [form] = the main hand's period in that form }).
 function M.new(o)
     local e = {
         guid = o.guid,
@@ -29,6 +31,10 @@ function M.new(o)
         healthMax = o.health or 1000,
         power = 0,
         powerMax = o.powerMax or 100,
+        pt = o.pt or 1,
+        res = o.res or {},
+        formSpeed = o.formSpeed or {},
+        formSince = 0, -- when the current form began (W.shift; a regen ramp's clock)
         auras = {},
         target = o.target,
         form = 0,
@@ -37,6 +43,10 @@ function M.new(o)
         cdUntil = {}, -- [key] = the true cooldown's end
         avoidAt = {}, -- [act] = the last time an outcome of ours on a target was that avoid (MISS, DODGE, PARRY)
     }
+    e.res0 = {} -- each other resource's value at the start (the observer's first view; the world changes `res`)
+    for pt, r in pairs(e.res) do
+        e.res0[pt] = r.cur
+    end
     return e
 end
 
diff --git a/tests/Virtual/harness/metrics.lua b/tests/Virtual/harness/metrics.lua
index d513f0f3..2fcd6480 100644
--- a/tests/Virtual/harness/metrics.lua
+++ b/tests/Virtual/harness/metrics.lua
@@ -61,15 +61,19 @@ end
 M.truthAt = truthAt
 
 --- Adds one fight (drive captures `c`, stream `s`, world `W`) to tally `m`: the outcomes from `after` seconds on (default
---- all). `step`: one main-hand step (the overshoot bar, default 9). Returns `m`.
-function M.score(m, c, s, W, step, after)
+--- all), and only at times `keep(t)` accepts when given (a section of the fight). `step`: one main-hand step (the
+--- overshoot bar, default 9). Returns `m`.
+function M.score(m, c, s, W, step, after, keep)
     step, after = step or 9, after or 0
+    local function inside(t)
+        return t >= after and (keep == nil or keep(t))
+    end
     m.fights = m.fights + 1
     for i = 1, s.n do
         local ev = s.ev[i]
-        if ev == "PLAYER_SWING" and s.t[i] >= after then -- the same window as the false credits
+        if ev == "PLAYER_SWING" and inside(s.t[i]) then -- the same window as the false credits
             m.swings = m.swings + 1
-        elseif ev == "UNIT_COMBAT" and s.a1[i] == "target" and s.t[i] >= after then
+        elseif ev == "UNIT_COMBAT" and s.a1[i] == "target" and inside(s.t[i]) then
             local h, cr = s.hand[i], c.crHand[i]
             if s.src[i] == 1 and h > 0 and s.a2[i] == "WOUND" and s.a4[i] > 0 then
                 m.own[h] = m.own[h] + 1
@@ -105,7 +109,7 @@ function M.score(m, c, s, W, step, after)
     -- avoid (right), another swing's of ours (wrong), or another source's or an unexplained one (a false credit)
     for k = 1, math.min(c.rows.missed, #c.missHand) do
         local h, at = c.missHand[k], c.missAt[k]
-        if at >= after then
+        if inside(at) then
             local i = 0
             for a = c.nAv, 1, -1 do
                 if c.avHand[a] == h and c.avAt[a] == at then
@@ -172,6 +176,142 @@ function M.score(m, c, s, W, step, after)
     return m
 end
 
+-- Our true value of power type `pt` as a function of time, for times asked in increasing order: the swing-paid type's
+-- from `ev.power`, another's from `ev.resCur` (its start value before any event); and the time of its last change.
+local function truthOf(W, pt)
+    local us, truth, i = W.ents[1], W.truth, 0
+    local v, changed = (pt == us.pt) and 0 or (us.res0[pt] or 0), -math.huge
+    return function(t)
+        while truth[i + 1] and truth[i + 1].t <= t do
+            i = i + 1
+            local ev = truth[i]
+            local x = (pt == us.pt and ev.power) or (ev.pt == pt and ev.resCur) or nil
+            if x and x ~= v then
+                v, changed = x, ev.t
+            end
+        end
+        return v, changed
+    end
+end
+M.truthOf = truthOf
+
+--- One tracked power type's belief against the truth (drive's `c.trk[pt]`, GCD kinds design §2.4), from `o.after`
+--- seconds on, up to the world's end (W.t: the drive ticks on past it) and at times `o.keep(t)` accepts: { n, meanAbs, maxAbs, windows (10 s), over (windows with a tick whose
+--- lo is above the truth by more than `overBar`), overMax (the largest lo above the truth), exact (the share of ticks,
+--- `o.settle` (0.25) s or more after the truth's last change and our last cast, whose est equals the truth) }.
+function M.power(c, W, pt, overBar, o)
+    o = o or {}
+    local r, at = c.trk[pt], truthOf(W, pt)
+    local after, settle = o.after or 0, o.settle or 0.25
+    local casts, ci = {}, 1
+    for _, ev in ipairs(W.truth) do
+        if ev.kind == "cast" and ev.src == W.ents[1] then
+            casts[#casts + 1] = ev.t
+        end
+    end
+    local out = { n = 0, meanAbs = 0, maxAbs = 0, windows = 0, over = 0, overMax = 0, exact = 1, settled = 0 }
+    local sum, hits, win, winOver = 0, 0, nil, false
+    local function close()
+        if win then
+            out.windows = out.windows + 1
+            out.over = out.over + (winOver and 1 or 0)
+        end
+    end
+    for k = 1, r.n do
+        local t = r.t[k]
+        local v, changed = at(t)
+        while casts[ci + 1] and casts[ci + 1] <= t do
+            ci = ci + 1
+        end
+        if t >= after and t <= W.t and (o.keep == nil or o.keep(t)) then
+            local err = r.est[k] - v
+            out.n, sum = out.n + 1, sum + math.abs(err)
+            out.maxAbs = math.max(out.maxAbs, math.abs(err))
+            local w = math.floor(t / 10)
+            if w ~= win then
+                close()
+                win, winOver = w, false
+            end
+            local over = r.lo[k] - v
+            out.overMax = math.max(out.overMax, over)
+            winOver = winOver or over > overBar
+            local lastCast = casts[ci] and casts[ci] <= t and casts[ci] or -math.huge
+            if t - changed >= settle and t - lastCast >= settle then
+                out.settled = out.settled + 1
+                hits = hits + (r.est[k] == v and 1 or 0)
+            end
+        end
+    end
+    close()
+    out.meanAbs = out.n > 0 and sum / out.n or 0
+    out.exact = out.settled > 0 and hits / out.settled or 1
+    return out
+end
+
+--- Each GCD of ours (W's casts with `gcd`) against the belief's (drive's `c.gcdS`/`c.gcdE`): { n (true), seen (a
+--- believed one at its start, within 0.01 s), owned, ownerless (of those seen, by the opener at the first tick),
+--- errMax (|believed end - true end|), extra (believed GCDs no press opened) }.
+function M.gcd(c, W)
+    local out = { n = 0, seen = 0, owned = 0, ownerless = 0, errMax = 0, extra = 0 }
+    local starts, ends = {}, {}
+    for _, ev in ipairs(W.truth) do
+        if ev.kind == "cast" and ev.src == W.ents[1] and ev.gcd then
+            out.n = out.n + 1
+            starts[out.n], ends[out.n] = ev.t, ev.t + ev.gcd
+        end
+    end
+    local j = 1
+    for k = 1, c.gcdN do
+        local gs = c.gcdS[k]
+        while starts[j] and starts[j] < gs - 0.01 do
+            j = j + 1
+        end
+        if starts[j] and math.abs(starts[j] - gs) <= 0.01 then
+            out.seen = out.seen + 1
+            out.errMax = math.max(out.errMax, math.abs(c.gcdE[k] - ends[j]))
+            if c.gcdOwned[k] == 1 then
+                out.owned = out.owned + 1
+            else
+                out.ownerless = out.ownerless + 1
+            end
+            j = j + 1
+        else
+            out.extra = out.extra + 1
+        end
+    end
+    return out
+end
+
+--- Our white wounds on the target at times `keep(t)` accepts, and how many Rows.lua scored on timing alone (drive's
+--- `c.unk`: the form differs from the damage cache's): n, unknown.
+function M.unknown(c, s, keep)
+    local n, u = 0, 0
+    for i = 1, s.n do
+        if s.ev[i] == "UNIT_COMBAT" and s.src[i] == 1 and s.hand[i] > 0 and s.a1[i] == "target" and s.a4[i] > 0 then
+            if keep == nil or keep(s.t[i]) then
+                n, u = n + 1, u + c.unk[i]
+            end
+        end
+    end
+    return n, u
+end
+
+--- The crits staged (c = 3, drive's `c.crit3`) among our credited white wounds: crits (credited and CRITICAL), staged
+--- (of those, with a c = 3), false (a c = 3 on a credited non-crit).
+function M.crits(c, s)
+    local crits, staged, false3 = 0, 0, 0
+    for i = 1, s.n do
+        if s.ev[i] == "UNIT_COMBAT" and c.crHand[i] > 0 then
+            if s.a3[i] == "CRITICAL" then
+                crits, staged = crits + 1, staged + (c.crit3[i] > 0 and 1 or 0)
+            elseif c.crit3[i] > 0 then
+                false3 = false3 + 1
+            end
+        end
+    end
+    return crits, staged, false3
+end
+
 --- The share of hand h's own hits credited to the right swing.
 function M.rate(m, h)
     return m.own[h] > 0 and m.right[h] / m.own[h] or 1
diff --git a/tests/Virtual/harness/observer.lua b/tests/Virtual/harness/observer.lua
index 18ced175..81104ef0 100644
--- a/tests/Virtual/harness/observer.lua
+++ b/tests/Virtual/harness/observer.lua
@@ -30,6 +30,14 @@ M.DEFAULTS = {
     gcdSpell = nil, -- the spell whose cooldown is the GCD (the addon's constant; nil: no GCD answers)
     powerType = 1,
     powerToken = "RAGE",
+    -- Power reads by type: { [powerType] = "always" | "ooc" | "never" } (UnitPower plain always, out of combat only, or
+    -- never: the swing-paid type's default, as measured in combat); "always" and "ooc" answer each change with
+    -- UNIT_POWER_FREQUENT and the type's token in `powerTokens` ({ [powerType] = token }; default `powerToken`).
+    plainPower = false,
+    powerTokens = false,
+    regenRead = true, -- GetPowerRegenForPowerType answers the true rate out of combat (probe W), secret in combat
+    playerSpeed = false, -- UnitAttackSpeed("player") answers our weapons' periods with the damage cache (out of combat)
+    forms = false, -- the client's forms (index to spell ID: the content's), answered once
 }
 
 -- Our spells as the fake spec's (its costs: the usability answers).
@@ -91,12 +99,14 @@ end
 --- (1 ours, 2 another source, 3 unexplained, 0 not an outcome), hand[] (our swing's hand; 0 a cast's), swingT[] (our
 --- swing's true time), actor[] (the entity index of a hit on us) }. An `ev` starting with "@" is a client-answer change
 --- for the drive (`@damage` UnitDamage, `@usable`, `@form`, `@guid`, `@unitIs`, `@speed`, `@combat`, `@auraError`,
---- `@current` IsCurrentSpell, `@aura` an aura list entry, `@dead`), or `@truth` our true power after an event. It draws nothing from `W.rng` (the behaviours roll every
+--- `@current` IsCurrentSpell, `@aura` an aura list entry, `@dead`, `@cooldown`, `@power`, `@regen`, `@attackSpeed`,
+--- `@forms`), or `@truth` our true power after an event. It draws nothing from `W.rng` (the behaviours roll every
 --- random choice and record it on the truth event), so batch and incremental streams of one world are equal.
---- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power) -> ok, short } }
---- (the content's): IsSpellUsable's two answers (usable; unusable for lack of power), `@usable` 1, 2 or 3 (unusable
---- for another reason); `power` is the client's view of ours (a gain `usableDelay` late, a spend at once). Each answer
---- is evaluated at every power change and, stepping, at each step's end (an aura or a target's health may flip it).
+--- `k.usable`: true (the fake spec's COSTS against our power) or a list { { spellID, fn(W, us, power, view) -> ok,
+--- short } } (the content's): IsSpellUsable's two answers (usable; unusable for lack of power), `@usable` 1, 2 or 3
+--- (unusable for another reason); `power` is the client's view of our swing-paid power and `view[pt]` of each other
+--- type's (a gain `usableDelay` late, a spend at once). Each answer is evaluated at every power change and, stepping,
+--- at each step's end (an aura or a target's health may flip it).
 function M.new(W, k)
     k = k or M.DEFAULTS
     local us = W.ents[1]
@@ -186,11 +196,47 @@ function M.new(W, k)
         end
         push(t, "PLAYER_TARGET_CHANGED")
     end
-    -- UnitDamage read out of combat only (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1).
-    local function cache(t, d)
+    -- UnitDamage read out of combat only (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1); the
+    -- attack speeds (Sources/Swing.lua, probe W PR2) and the regen rates (probe W: 10.001 a second out of combat) too.
+    local function cache(t, ev)
+        local d = ev.damage
         push(t, "@damage", d[1], d[2], d[3], d[4])
+        if k.playerSpeed and ev.speed then
+            push(t, "@attackSpeed", ev.speed[1], ev.speed[2])
+        end
+        if k.regenRead and ev.regen then
+            for pt, r in pairs(ev.regen) do
+                push(t, "@regen", pt, r)
+            end
+        end
         push(t, "PLAYER_EQUIPMENT_CHANGED")
     end
+    local modes, tokens = k.plainPower or {}, k.powerTokens or {}
+    local cur, inCombat = {}, false -- our true power by type as the stream has told it; the client's combat flag
+    local function plainPower(t, pt) -- a plain read of `pt` now, if its mode answers it
+        local m = modes[pt]
+        if m == "always" or (m == "ooc" and not inCombat) then
+            push(t, "@power", pt, cur[pt])
+            push(t, "UNIT_POWER_FREQUENT", "player", tokens[pt] or k.powerToken)
+        end
+    end
+    local function combat(t, on) -- the plain-out-of-combat reads turn secret in combat and plain again after it
+        inCombat = on
+        for pt, m in pairs(modes) do
+            if m == "ooc" then
+                if on then
+                    push(t, "@power", pt, nil)
+                else
+                    plainPower(t, pt)
+                end
+            end
+        end
+        if on and k.regenRead then
+            for pt in pairs(W.rates or {}) do
+                push(t, "@regen", pt, nil)
+            end
+        end
+    end
     local function spellID(name)
         return M.SPELLS[name] or name -- a real ID (the content's) passes as is
     end
@@ -203,13 +249,14 @@ function M.new(W, k)
                 push(t, "@form", ev.form)
                 push(t, "UPDATE_SHAPESHIFT_FORM")
             end
-            cache(t, ev.damage)
+            cache(t, ev)
             targets(t + 0.1, ev)
             local v = ev.targets[us]
             if k.plain and v then
                 push(t + 0.1, "@health", "target", v.health, v.healthMax)
             end
         elseif kind == "pull" then
+            combat(t, true)
             push(t, "@combat", true)
             if not k.plain then
                 push(t, "@auraError", "target", true) -- spec §3.1: the target's auras raise in combat
@@ -217,14 +264,18 @@ function M.new(W, k)
             push(t, "PLAYER_REGEN_DISABLED")
         elseif kind == "stop" then
             push(t, "@combat", false)
+            combat(t, false)
             if not k.plain then
                 push(t, "@auraError", "target", false)
             end
-            cache(t, ev.damage)
+            cache(t, ev)
             push(t, "PLAYER_REGEN_ENABLED")
-        elseif kind == "form" then
+        elseif kind == "form" then -- after its cast's success (Forms.lua, Q2)
             push(t, "@form", ev.form)
             push(t, "UPDATE_SHAPESHIFT_FORM")
+            if ev.damage then -- out of combat: the caches read the form's own
+                cache(t, ev)
+            end
         elseif kind == "target" then
             targets(t, ev)
         elseif kind == "swing" and ev.src == us then
@@ -274,6 +325,7 @@ function M.new(W, k)
             end
             if not left then
                 push(t, "@combat", false)
+                combat(t, false)
                 if not k.plain then
                     push(t, "@auraError", "target", false)
                 end
@@ -282,9 +334,9 @@ function M.new(W, k)
         -- our cast IDs plain (docs/superpowers/specs/2026-10-16-forever-protection-design.md §1.1)
         elseif kind == "cast" and ev.src == us then -- others' secret (G 49873)
             castN = castN + 1
-            push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
-            -- on cooldown and the GCD (the client's GCD spell, `k.gcdSpell`): the flags plain, the times secret but
-            -- to a secret-free client
+            -- on cooldown and the GCD (the client's GCD spell, `k.gcdSpell`): the flags plain (probe W PR4), the times
+            -- secret but to a secret-free client; the GCD's rising edge after the success or before it (`ev.order`,
+            -- the world's roll: UNMEASURED until checkpoint G3)
             local function cooldown(id, d)
                 if k.plain then
                     push(t, "@cooldown", id, t, d)
@@ -296,12 +348,17 @@ function M.new(W, k)
                 push(t, "SPELL_UPDATE_COOLDOWN")
                 push(t + d, "SPELL_UPDATE_COOLDOWN")
             end
+            local gcdFirst = ev.gcd and k.gcdSpell and ev.order == 2
+            if gcdFirst then
+                cooldown(k.gcdSpell, ev.gcd)
+            end
+            push(t, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. castN, spellID(ev.spell))
             if (ev.cd or 0) > 0 then -- every rank answers the spell's cooldown (`ev.ids`, the content's)
                 for _, id in ipairs(ev.ids or { spellID(ev.spell) }) do
                     cooldown(id, ev.cd)
                 end
             end
-            if ev.gcd and k.gcdSpell then
+            if ev.gcd and k.gcdSpell and not gcdFirst then
                 cooldown(k.gcdSpell, ev.gcd)
             end
             if ev.onUs then -- P log 1 1345, 4329-4330, 6532: also on targettarget while our target targets us
@@ -318,14 +375,20 @@ function M.new(W, k)
         if k.plain and ev.health and ev.dst == ev.ourTarget then -- a secret-free client's target health
             push(t, "@health", "target", ev.health, ev.dst.healthMax)
         end
-        if ev.power then
-            if k.plain then -- a secret-free client's power, and its event
+        if ev.power or ev.resCur then
+            local pt = ev.resCur and ev.pt or us.pt
+            cur[pt] = ev.resCur or ev.power
+            if k.plain and ev.power then -- a secret-free client's power, and its event
                 push(t, "@power", k.powerType, ev.power)
                 push(t, "UNIT_POWER_FREQUENT", "player", k.powerToken)
             end
+            plainPower(t, pt)
             dseq = dseq + 1
-            deltas[#deltas + 1] = { t + (ev.cost and 0 or k.usableDelay), (ev.rage or 0) - (ev.cost or 0), dseq }
-            push(t, "@truth", ev.power) -- the metrics' truth (harness design §3.3), no client answer
+            local d = (ev.rage or 0) - (ev.cost or 0)
+            deltas[#deltas + 1] = { t + (ev.cost and 0 or k.usableDelay), d, pt, dseq }
+            if ev.power then
+                push(t, "@truth", ev.power) -- the metrics' truth (harness design §3.3), no client answer
+            end
         end
     end
     -- usability: the content's answers, or the fake spec's costs against our power (as the client answers them)
@@ -342,11 +405,14 @@ function M.new(W, k)
             }
         end
     end
-    local usable, power = {}, 0
+    local usable, power, view = {}, 0, {}
+    for pt, v in pairs(us.res0 or {}) do
+        view[pt], cur[pt] = v, v
+    end
     local function answer(t)
         local flipped = false
         for _, u in ipairs(answers) do
-            local ok, short = u[2](W, us, power)
+            local ok, short = u[2](W, us, power, view)
             local st = ok and 1 or (short and 2 or 3)
             if usable[u[1]] ~= st then
                 usable[u[1]] = st
@@ -360,7 +426,7 @@ function M.new(W, k)
     end
     if answers then -- the answers before anything happens (no event: the client's state at login)
         for _, u in ipairs(answers) do
-            local ok, short = u[2](W, us, 0)
+            local ok, short = u[2](W, us, 0, view)
             usable[u[1]] = ok and 1 or (short and 2 or 3)
             push(0, "@usable", u[1], usable[u[1]])
         end
@@ -368,6 +434,15 @@ function M.new(W, k)
     if k.plain then
         push(0, "@power", k.powerType, us.power)
     end
+    if k.forms then
+        push(0, "@forms", k.forms)
+    end
+    for pt in pairs(modes) do -- the client's state at login (no event)
+        cur[pt] = cur[pt] or 0
+        if modes[pt] ~= "never" then
+            push(0, "@power", pt, cur[pt])
+        end
+    end
     local function byTime(a, b)
         return a[1] < b[1] or (a[1] == b[1] and a[#a] < b[#b])
     end
@@ -386,7 +461,12 @@ function M.new(W, k)
             local keep = {}
             for _, d in ipairs(deltas) do
                 if d[1] <= tEnd then
-                    power = math.min(us.powerMax, power + d[2]) -- unclamped below: a spend can land before a delayed gain
+                    -- unclamped below: a spend can land before a delayed gain
+                    if d[3] == us.pt or not us.res[d[3]] then
+                        power = math.min(us.powerMax, power + d[2])
+                    else
+                        view[d[3]] = math.min(us.res[d[3]].max, view[d[3]] + d[2])
+                    end
                     answer(d[1])
                 else
                     keep[#keep + 1] = d
diff --git a/tests/Virtual/harness/scenarios.lua b/tests/Virtual/harness/scenarios.lua
index ddbc4ed5..6da9bc46 100644
--- a/tests/Virtual/harness/scenarios.lua
+++ b/tests/Virtual/harness/scenarios.lua
@@ -47,6 +47,11 @@ M.ARCHETYPES = ARCHETYPES
 --- The headless loop's knobs: weapons (ours [entities.weapons(level)]), mobHealth (our target's [1e9]: a kill ends
 --- the fight), pull (its time [1]), prepull (the cache and target reads [pull - 0.5]), form (ours at the start [0]),
 --- tag (appended to the mobs' GUIDs: a fresh target per fight on one boot).
+--- Several resources (GCD kinds design §2): pt (the swing-paid power type [1]), res ({ [pt] = { cur, max } }: the
+--- others), regen ({ [pt] = per second }, from the prepull), regenTick [0.1], regenAfter ({ s, k }), decay ({ pt, rate,
+--- interval, pausedBy }: from the stop), formSpeed ({ [form] = period }), payIn (the form whose swings pay), critRage
+--- ({ main, off }), gcdOrder (1, 2 or "mixed") and gcdLatency [0] (W.press), script (fn(W, us): our presses, started
+--- at the pull), after (seconds the world runs past the stop [3]).
 --- Returns the world with every behaviour scheduled, not run (`M.build` runs it).
 function M.world(o, seed)
     local W = world.new(seed)
@@ -56,8 +61,12 @@ function M.world(o, seed)
         level = lvl,
         weapons = o.weapons or entities.weapons(lvl),
         powerMax = o.max or 1e6,
+        pt = o.pt,
+        res = o.res,
+        formSpeed = o.formSpeed,
     }))
     us.form = o.form or 0
+    us.gcdOrder, us.gcdLatency = o.gcdOrder, o.gcdLatency
     local mobs = {}
     for i = 1, math.max(1, o.attackers or 1) do
         local m = o.mobs and o.mobs[i] or {}
@@ -83,6 +92,11 @@ function M.world(o, seed)
     end
     local pull = o.pull or 1
     local stop = (o.duration or 120) + pull
+    if o.regen then -- before the prepull: its reads answer the rates
+        W.at(0, function()
+            W.startRegen(us, o.regen, o.regenTick, o.regenAfter)
+        end)
+    end
     W.at(o.prepull or pull - 0.5, function() -- out of combat: the weapon damage cache and the target (observer.lua)
         W.emit({ kind = "prepull" })
     end)
@@ -93,6 +107,8 @@ function M.world(o, seed)
             land = observer.lag(o.lag),
             sameMs = (o.lag or observer.DEFAULTS).sameMs,
             rage = o.rage or { 9, 5 },
+            critRage = o.critRage,
+            payIn = o.payIn,
             presses = o.presses,
             strike = { 70, 90 },
             dot = { 3, 5, 13 },
@@ -106,6 +122,9 @@ function M.world(o, seed)
         for _, x in ipairs(others) do
             x.b(W, x.e)
         end
+        if o.script then
+            o.script(W, us)
+        end
     end)
     if o.damageBuff then
         W.at(o.damageBuff, function()
@@ -139,22 +158,30 @@ function M.world(o, seed)
             e.stopped = true
         end
         W.emit({ kind = "stop" })
+        if o.decay then
+            W.startDecay(us, o.decay)
+        end
     end)
-    W.stopAt = stop
+    W.stopAt, W.after = stop, o.after or 3
     return W
 end
 
---- The world of one fight (M.world's knobs), run to 3 s past its end.
+--- The world of one fight (M.world's knobs), run to `o.after` (3) s past its end.
 function M.build(o, seed)
     local W = M.world(o, seed)
-    W.run(W.stopAt + 3)
+    W.run(W.stopAt + W.after)
     return W
 end
 
---- The observed stream of a built world (knobs `o.lag` for the observer; `o.plainSpeed`, `o.usable` over them).
+--- The observed stream of a built world (knobs `o.lag` for the observer; `o.plainSpeed`, `o.usable` and the table
+--- `o.observe` over them).
 function M.stream(o, seed)
     local W = M.build(o, seed)
-    local k = setmetatable({ plainSpeed = o.plainSpeed, usable = o.usable }, { __index = o.lag or observer.DEFAULTS })
+    local k = { plainSpeed = o.plainSpeed, usable = o.usable }
+    for key, v in pairs(o.observe or {}) do
+        k[key] = v
+    end
+    setmetatable(k, { __index = o.lag or observer.DEFAULTS })
     return observer.observe(W, k), W
 end
 
diff --git a/tests/Virtual/harness/world.lua b/tests/Virtual/harness/world.lua
index 6d7757f8..b4a52627 100644
--- a/tests/Virtual/harness/world.lua
+++ b/tests/Virtual/harness/world.lua
@@ -13,10 +13,16 @@ M.CRIT = behaviours.RATES.crit
 --- A new world. `seed` seeds its generator. Truth events: { t, kind, src, dst, hand, act, flag, amount, school, spell }
 --- with kind "swing" (a white swing, its outcome rolled; ours land later as "land"), "land", "strike" (an
 --- on-next-swing strike frame), "spell" (a spell's outcome), "tick", "proc", "cast", "prepull" (the cache and
---- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target", "aura", "queue", "unqueue", "gain", "kill".
+--- target reads 0.5 s before the pull), "pull", "stop", "form", "buff", "target", "aura", "queue", "unqueue", "gain", "kill",
+--- "regen" and "decay" (a resource's continuous regen and out-of-combat decay, W.startRegen / W.startDecay). A gain
+--- (`rage`) or spend (`cost`) of ours is of power type `pt` (default our `pt`, the swing-paid `power`; another type's
+--- value after it: `ev.resCur`).
 function M.new(seed)
     -- crng: the client-detail draws (the same-ms avoid, a strike frame's order) apart from the fight's own
     local W = { t = 0, q = {}, seq = 0, truth = {}, rng = rng.new(seed), crng = rng.new(seed + 7919), ents = {} }
+    W.grng = rng.new(seed + 15485863) -- the GCD flag's order against its cast (W.press), apart from both
+    W.combat = false
+    W.rates = {} -- [powerType] = regen per second (W.startRegen)
 
     --- Runs `fn(W)` at time `t` (after everything already queued for `t`).
     function W.at(t, fn)
@@ -53,10 +59,19 @@ function M.new(seed)
         if ev.kind == "prepull" and me then -- our form at the start (the client's first form answer)
             ev.form = me.form
         end
-        if (ev.kind == "prepull" or ev.kind == "stop") and me then -- the weapon damage UnitDamage would read now
+        if ev.kind == "pull" or ev.kind == "stop" then
+            W.combat = ev.kind == "pull"
+        end
+        -- out of combat: the weapon damage UnitDamage reads now, the attack speeds and the regen rates
+        if me and (ev.kind == "prepull" or ev.kind == "stop" or (ev.kind == "form" and not W.combat)) then
             local w, m = me.weapons, me.dmgMult
             local o = w[2] or { 0, 0 }
             ev.damage = { w[1][1] * m, w[1][2] * m, o[1] * m, o[2] * m }
+            ev.speed = { w[1][3], w[2] and w[2][3] or nil }
+            ev.regen = {}
+            for pt in pairs(W.rates) do
+                ev.regen[pt] = W.regenRate(me, pt)
+            end
         end
         if ev.act == "WOUND" and ev.dst and (ev.kind ~= "swing" or not ev.ours) then -- ours take it at `land`
             local v = ev.dst
@@ -71,12 +86,26 @@ function M.new(seed)
         end
         local us = W.ents[1]
         if ev.src == us and (ev.rage or ev.cost) then
-            us.power = math.min(us.powerMax, math.max(0, us.power + (ev.rage or 0) - (ev.cost or 0)))
-            ev.power = us.power
+            local r = ev.pt and ev.pt ~= us.pt and us.res[ev.pt]
+            if r then
+                r.cur = math.min(r.max, math.max(0, r.cur + (ev.rage or 0) - (ev.cost or 0)))
+                ev.resCur = r.cur
+            else
+                us.power = math.min(us.powerMax, math.max(0, us.power + (ev.rage or 0) - (ev.cost or 0)))
+                ev.power = us.power
+            end
         end
         return ev
     end
 
+    --- `e`'s true value of power type `pt` (nil: its swing-paid `power`).
+    function W.res(e, pt)
+        if pt == nil or pt == e.pt or not e.res[pt] then
+            return e.power
+        end
+        return e.res[pt].cur
+    end
+
     --- Adds an entity (the first is our character) and its behaviour `fn(W, e)`, started at once.
     function W.add(e, behaviour)
         W.ents[#W.ents + 1] = e
@@ -90,22 +119,28 @@ function M.new(seed)
     -- the generic ones below.
 
     --- The player `e` pressed `key` now. `p` is the content's resolved press { spell, ids (every rank's: the client
-    --- answers their cooldown and IsCurrentSpell together; default { spell }), cost, cooldown, gcd (seconds),
-    --- offGcd, onNextSwing, amount ({ lo, hi } of a queued strike), cast (a cast time in seconds), requires = fn(W, e)
-    --- -> ok, why, effect = fn(W, e, p) }. Checked against the true state in order: a cast in progress, the GCD, the
-    --- cooldown, the cost, a strike already queued, `requires`; a refusal returns false and its reason ("casting",
-    --- "gcd", "cooldown", "cost", "queued", "requires:<why>") and changes nothing. An accept starts the GCD and the
-    --- cooldown, then spends, emits the cast and runs `effect` (a cast time: all three when the cast completes; a queued
-    --- strike: queues it, paid at its swing); it returns true.
+    --- answers their cooldown and IsCurrentSpell together; default { spell }), cost, pt (the cost's power type; default
+    --- the swing-paid one), cooldown, gcd (seconds; 0 or offGcd: off the GCD), offGcd, onNextSwing, amount ({ lo, hi } of
+    --- a queued strike), cast (a cast time in seconds), requires = fn(W, e) -> ok, why, effect = fn(W, e, p), and the
+    --- generic effects run after `effect`: gain { pt, amount }, points { pt, 1 | "all" } (1: one more on a landed hit
+    --- of `effect`'s; "all": spend them all), drain (a power type: spend what is left of it), aura { id, duration,
+    --- tick = { pt, every, amount } } (named fields; on us), shift (W.shift's `sh`) }. Checked against the true state in order: a
+    --- cast in progress, the GCD, the cooldown, the cost, a strike already queued, `requires`; a refusal returns false
+    --- and its reason ("casting", "gcd", "cooldown", "cost", "queued", "requires:<why>") and changes nothing. An accept
+    --- starts the GCD (its length plus `e.gcdLatency`, the client's flag) and the cooldown, then spends, emits the cast
+    --- (with `order`, the GCD flag's: 1 after the success, 2 before; `e.gcdOrder` 1, 2 or "mixed", rolled from W.grng)
+    --- and runs the effects (a cast time: all three when the cast completes; a queued strike: queues it, paid at its
+    --- swing); it returns true.
     function W.press(e, key, p)
         local t = W.t
+        local offGcd = p.offGcd or p.gcd == 0
         if not p.onNextSwing and t < (e.castUntil or 0) then
             return false, "casting"
-        elseif not p.offGcd and t < e.gcdUntil then
+        elseif not offGcd and t < e.gcdUntil then
             return false, "gcd"
         elseif t < (e.cdUntil[key] or 0) then
             return false, "cooldown"
-        elseif (p.cost or 0) > e.power then
+        elseif (p.cost or 0) > W.res(e, p.pt) then
             return false, "cost"
         elseif p.onNextSwing and e.queued then
             return false, "queued"
@@ -116,8 +151,9 @@ function M.new(seed)
                 return false, "requires:" .. tostring(why)
             end
         end
-        if not p.offGcd then
-            e.gcdUntil = t + (p.gcd or 1.5)
+        local gcdLen = not offGcd and (p.gcd or 1.5) + (e.gcdLatency or 0) or nil
+        if gcdLen then
+            e.gcdUntil = t + gcdLen
         end
         if (p.cooldown or 0) > 0 then
             e.cdUntil[key] = t + p.cooldown
@@ -125,7 +161,11 @@ function M.new(seed)
         local function land()
             -- shortcut: a cast time's GCD is over at its success, so the client sees no GCD flag for it; upgrade
             -- with UNIT_SPELLCAST_START.
-            local gcd = not p.offGcd and (p.cast or 0) == 0 and (p.gcd or 1.5) or nil
+            local gcd = (p.cast or 0) == 0 and gcdLen or nil
+            local order = e.gcdOrder or 1
+            if gcd and order == "mixed" then
+                order = W.grng.chance(0.5) and 2 or 1
+            end
             W.emit({
                 kind = "cast",
                 src = e,
@@ -133,12 +173,16 @@ function M.new(seed)
                 spell = p.spell,
                 ids = p.ids,
                 cost = p.cost,
+                pt = p.pt,
                 cd = p.cooldown,
                 gcd = gcd,
+                order = gcd and order or nil,
             })
+            e.lastHit = nil
             if p.effect then
                 p.effect(W, e, p)
             end
+            W.effects(e, p)
         end
         if p.onNextSwing then
             W.queueStrike(e, p)
@@ -156,6 +200,124 @@ function M.new(seed)
         return true
     end
 
+    --- The generic effects of press `p` by `e` (W.press's gain, points, drain, aura, shift), after its `effect`.
+    function W.effects(e, p)
+        if p.gain then
+            W.emit({ kind = "gain", src = e, pt = p.gain[1], rage = p.gain[2] })
+        end
+        if p.points then
+            local pt, n = p.points[1], p.points[2]
+            if n == "all" then
+                W.emit({ kind = "gain", src = e, pt = pt, cost = W.res(e, pt) })
+            elseif e.lastHit and e.lastHit.act == "WOUND" then
+                W.emit({ kind = "gain", src = e, pt = pt, rage = n })
+            end
+        end
+        if p.drain then
+            W.emit({ kind = "gain", src = e, pt = p.drain, cost = W.res(e, p.drain) })
+        end
+        local a = p.aura
+        if a then
+            W.applyAura(e, a.id, a.duration)
+            local tk = a.tick
+            -- shortcut: a refresh keeps the first application's ticks running beside its own (no content refreshes a
+            -- ticking aura yet); upgrade with an application count when one does.
+            if tk then -- every tick lands, the one at the expiry too
+                local applied = e.auras[a.id]
+                for k = 1, math.floor(a.duration / tk.every + 1e-9) do
+                    W.at(W.t + k * tk.every, function()
+                        if applied.expires >= W.t then
+                            W.emit({ kind = "gain", src = e, pt = tk.pt, rage = tk.amount })
+                        end
+                    end)
+                end
+            end
+        end
+        if p.shift then
+            W.shift(e, p.shift)
+        end
+    end
+
+    --- `e` changes form (after the shift's own cast): `sh` { form, speed (the main hand's new period; default
+    --- e.formSpeed[form], else unchanged), dmgMult (the form's weapon damage factor), onEnter = { [pt] = "zero" |
+    --- "keep" | fn(W, e, pt, cur) -> the new value } }. The form event comes first, then the resources; out of combat
+    --- the form event carries the new damage and speeds (the caches' read). The swing already scheduled keeps its time.
+    function W.shift(e, sh)
+        e.form, e.formSince = sh.form, W.t
+        local speed = sh.speed or e.formSpeed[sh.form]
+        if speed and e.weapons[1] then
+            e.weapons[1][3] = speed
+        end
+        if sh.dmgMult then
+            e.dmgMult = sh.dmgMult
+        end
+        W.emit({ kind = "form", form = sh.form })
+        for pt, rule in pairs(sh.onEnter or {}) do
+            local cur = W.res(e, pt)
+            local new = cur
+            if rule == "zero" then
+                new = 0
+            elseif type(rule) == "function" then
+                new = rule(W, e, pt, cur)
+            end
+            if new > cur then
+                W.emit({ kind = "gain", src = e, pt = pt, rage = new - cur })
+            elseif new < cur then
+                W.emit({ kind = "gain", src = e, pt = pt, cost = cur - new })
+            end
+        end
+    end
+
+    --- `e`'s regen per second of `pt` now: the rate, times `W.regenAfter.k` after `W.regenAfter.s` seconds in one form.
+    function W.regenRate(e, pt)
+        local r, ra = W.rates[pt] or 0, W.regenAfter
+        if ra and W.t - e.formSince >= ra.s then
+            r = r * ra.k
+        end
+        return r
+    end
+
+    --- Continuous regen of `e`'s resources at `rates` ({ [pt] = per second }) from now, applied every `every` s (0.1)
+    --- as a "regen" gain, capped at the maximum (no event at it); `after` { s, k }: the rate x k after s seconds in one
+    --- form (an unmeasured in-form ramp's knob).
+    function W.startRegen(e, rates, every, after)
+        every, W.regenAfter = every or 0.1, after
+        for pt, r in pairs(rates) do
+            W.rates[pt] = r
+        end
+        local function step()
+            for pt in pairs(W.rates) do
+                local r = e.res[pt] or { cur = e.power, max = e.powerMax }
+                local add = math.min(W.regenRate(e, pt) * every, r.max - r.cur)
+                if add > 0 then
+                    W.emit({ kind = "regen", src = e, pt = pt, rage = add })
+                end
+            end
+            W.at(W.t + every, step)
+        end
+        W.at(W.t + every, step)
+    end
+
+    --- `e`'s out-of-combat decay of power type `d.pt` from now (call it at the combat's end): `d.rate` a second, stepped
+    --- and front-loaded: rate x interval at once and at the start of each interval while above 0. `d.pausedBy`: an aura
+    --- ID on `e` that pauses it (the quantum then falls at the aura's expiry, and every interval after).
+    function W.startDecay(e, d)
+        local q = d.rate * d.interval
+        local function beat()
+            local a = d.pausedBy and e.auras[d.pausedBy]
+            if a then
+                W.at(a.expires, beat)
+                return
+            end
+            local cur = W.res(e, d.pt)
+            if cur > 0 then
+                W.emit({ kind = "decay", src = e, pt = d.pt, cost = math.min(cur, q) })
+            end
+            W.at(W.t + d.interval, beat)
+        end
+        beat()
+    end
+
     --- Queues `p` as `e`'s next main-hand swing (the melee behaviour turns it into a strike frame, paid then).
     function W.queueStrike(e, p)
         e.queued = { spell = p.spell, ids = p.ids, cost = p.cost, amount = p.amount }
@@ -199,7 +361,9 @@ function M.new(seed)
             e.avoidAt[act] = W.t
         end
         local amt = act == "WOUND" and math.floor(amount * (flag == "CRITICAL" and 2 or 1) + 0.5) or 0
-        W.emit({ kind = "spell", src = e, dst = dst, act = act, flag = flag, amount = amt, school = school or 1 })
+        e.lastHit =
+            W.emit({ kind = "spell", src = e, dst = dst, act = act, flag = flag, amount = amt, school = school or 1 })
+        return e.lastHit
     end
 
     --- `e` gains `amount` power now (a negative amount spends it).
@@ -213,7 +377,7 @@ function M.new(seed)
 
     --- Puts `e` in form `form` (an index into the client's forms; 0 none).
     function W.setForm(e, form)
-        e.form = form
+        e.form, e.formSince = form, W.t
         W.emit({ kind = "form", form = form })
     end
 
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `625 successes / 0 failures / 0 errors / 0 pending`.

The harness's old worlds are unchanged (Deviation 3): the `#slow` gate specs (`solo_spec`, `sweep_spec`, `group_spec`, `onus_spec`) pass at their bounds with the same numbers.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 135 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      625 successes / 0 failures / 0 errors / 0 pending (about 141 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual src/Hekili/Engine src/Hekili/State.lua tests/Virtual | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|bear|cat|feral|maul|enrage|furor|shred|rake|rip|swipe|lacerate|bite|cat_form|bear_form|shifting_power|stance'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add tests/Virtual/harness/entities.lua tests/Virtual/harness/world.lua tests/Virtual/harness/behaviours.lua \
  tests/Virtual/harness/observer.lua tests/Virtual/harness/drive.lua tests/Virtual/harness/scenarios.lua \
  tests/Virtual/harness/metrics.lua tests/Virtual/harness/world_spec.lua tests/Virtual/harness/metrics_spec.lua \
  tests/Virtual/harness/observer_spec.lua tests/Virtual/harness/fixtures_spec.lua tests/boundary_spec.lua
git commit -m "test(harness): several resources with regen and stepped decay, the GCD's latency and edge order, shifts with entry rules, white rage by form and crit; the observer's power reads by type, regen and speed reads, the forms; the drive's content boot and captures; the metrics by type, GCD and section; the boundary scan covers the harness core (GCD kinds design §2, D7, D8)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin gcd-kinds`

---
### Task 4: The Druid in the harness: its content, the scenarios and their gates

Spec §3, §4 (§4.1-§4.7), D4-D6, D9; Deviations 6-13, 16.

**Files:**
- Create: `tests/Forever/helpers/druid_vs.lua` (`M.boot(ns, api, edit)` -> `w, h`), `tests/Forever/helpers/druid_world.lua` (the content), `tests/Forever/druid_harness_spec.lua` (the gates)
- Modify: `tests/Forever/druid_spec.lua` ("Forever Druid in VirtualState's now context" boots through `druid_vs.boot`), `Makefile` (`test` and `test-fast` exclude `druid`; `test-druid`)

**Interfaces:**
- Consumes: Task 3's harness (every name in its Produces), `load_druid.lua` (`load`, `env`, `run`), Task 2's class file, `c.I.GCD_SPELL`.
- Produces (test code, Druid content):
  - `druid_vs.boot(ns, api, edit)` -> `w, h` (the class with `startsCombat` forwarded; `edit(class, w)` before the build);
  - `druid_world`: `MANA, RAGE, ENERGY, POINTS`, `TOKENS`, `FORMS` (Bear, Aquatic, Cat, Travel), `FORM`, `BEAR`, `CAT`, `SPEED`, `DMG`, `GCD`, `KEYS`, `MAP`; `rules()` -> `{ swing, crit, payIn, tick, decay, enterBear, enterCat, shiftingPower, enrage }` read from the class file; `press(key, R, o)`; `usable(keys, R)`; `script(list, every, extra, R, o, presses)`; `bearList()`, `bearExtra(R, enrageAt)`, `catList()`, `onTarget(us, key)`; `knobs(o, R, gcdSpell)`; `formIds()`; `fight(o, seed)` -> `{ c, s, W, R, rows, swingValues }`; `done(f)`; `SCENARIOS` (`bear`, `cat`, `shift`, `decay`); `fights(name, n, v, each)`; `formAt(W, form0)`;
  - `make test-druid` (busted `--tags=druid`).

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/druid_harness_spec.lua b/tests/Forever/druid_harness_spec.lua
new file mode 100644
index 00000000..82e797f6
--- /dev/null
+++ b/tests/Forever/druid_harness_spec.lua
@@ -0,0 +1,311 @@
+-- tests/Forever/druid_harness_spec.lua (GCD kinds design §4, D9): the Druid in the combat harness, through the real
+-- VirtualState and Rows.lua, its content from tests/Forever/helpers/druid_world.lua: solo bear (the rage model), solo
+-- cat (energy secret, combo points plain), the shift fight (the stale caches, GCD kinds across shifts, resources on
+-- entry), the Furor variants and Enrage's decay pause. The gates in make check (#slow) run a tenth of the design's
+-- fights; the design's counts run behind make test-druid (#druid). Each gate prints its tally line, which is also its
+-- failure message.
+local dw = require("Forever.helpers.druid_world")
+local metrics = require("Virtual.harness.metrics")
+
+local function count(t, key, v)
+    t[key] = (t[key] or 0) + (v or 1)
+end
+local function most(t, key, v)
+    t[key] = math.max(t[key] or -math.huge, v)
+end
+local function least(t, key, v)
+    t[key] = math.min(t[key] or math.huge, v)
+end
+
+-- One line of a tally's numbers, sorted by name (rounded to 3 places).
+local function line(name, t, m)
+    local keys, out = {}, {}
+    for k, v in pairs(t) do
+        if type(v) == "number" then
+            keys[#keys + 1] = k
+        end
+    end
+    table.sort(keys)
+    for _, k in ipairs(keys) do
+        out[#out + 1] = k .. "=" .. math.floor(t[k] * 1000 + 0.5) / 1000
+    end
+    return name .. ": " .. table.concat(out, " ") .. (m and ("; " .. metrics.line(m)) or "")
+end
+
+-- The GCD tally of a fight: every press's GCD seen at its start, owned, its end's error; both edge orders counted.
+local function gcd(t, f)
+    local g = metrics.gcd(f.c, f.W)
+    count(t, "gcds", g.n)
+    count(t, "gcdSeen", g.seen)
+    count(t, "ownerless", g.ownerless)
+    count(t, "gcdExtra", g.extra)
+    most(t, "gcdErr", g.errMax)
+    for _, ev in ipairs(f.W.truth) do
+        if ev.kind == "cast" and ev.order then
+            count(t, "order" .. ev.order)
+        end
+    end
+end
+
+-- The first tick of capture `rk` after time `t`: its index.
+local function after(rk, t)
+    for k = 1, rk.n do
+        if rk.t[k] > t then
+            return k
+        end
+    end
+end
+
+--- §4.1 solo bear over `n` fights: the credits (metrics.score at the bear step), crits staged, Mauls, the GCDs; and
+--- the overshoot windows of the same fights without answers (the model's drift alone: `driftRaw` every window a step
+--- over, `driftOver` those that end with the belief above the truth).
+local function bear(n)
+    local t, m, drift = {}, metrics.new(), metrics.new()
+    dw.fights("bear", n, {}, function(f)
+        local c, s, W = f.c, f.s, f.W
+        metrics.score(m, c, s, W, f.R.swing)
+        local crits, staged, false3 = metrics.crits(c, s)
+        count(t, "crits", crits)
+        count(t, "staged", staged)
+        count(t, "false3", false3)
+        local maul = dw.press("maul", f.R).spell
+        for _, ev in ipairs(W.truth) do
+            if ev.kind == "strike" and ev.src == W.ents[1] then
+                count(t, "strikes")
+            end
+        end
+        count(t, "maulRows", ((f.rows.SPELL_DAMAGE or {})[maul] or 0) + ((f.rows.SPELL_MISSED or {})[maul] or 0))
+        count(t, "maulPaid", (f.rows.SPELL_CAST_SUCCESS or {})[maul] or 0)
+        gcd(t, f)
+    end)
+    dw.fights("bear", n, { usable = false }, function(f)
+        local c, W = f.c, f.W
+        metrics.score(drift, c, f.s, W, f.R.swing)
+        -- a window the belief ends above the truth in: a window that starts with the belief far below it can rise a
+        -- step past the truth's change only by the floor at 0 (a Maul's 15 paid from 4 believed), never above it
+        for w = 1, c.nWin - 1 do
+            local a, b = c.winT[w], c.winT[w + 1]
+            local err = (c.win[w + 1] - c.win[w]) - (metrics.truthAt(W, b) - metrics.truthAt(W, a))
+            if err >= f.R.swing and c.win[w + 1] > metrics.truthAt(W, b) then
+                count(t, "driftOver")
+            end
+        end
+    end)
+    t.danger, t.driftRaw, t.driftWindows, t.driftOver = m.danger, drift.over, drift.windows, t.driftOver or 0
+    return t, m
+end
+
+--- §4.2 solo cat over `n` fights (variant `v`: regenAfter, regenRead): energy from `from` seconds on, rage, points,
+--- the GCDs; the main hand's credits as the pairing report.
+local function cat(n, v, from)
+    local t, m = {}, metrics.new()
+    dw.fights("cat", n, v, function(f)
+        local c, s, W = f.c, f.s, f.W
+        metrics.score(m, c, s, W, f.R.swing)
+        local e = metrics.power(c, W, dw.ENERGY, 5, { after = from })
+        count(t, "energyMean", e.meanAbs / n)
+        most(t, "energyMax", e.maxAbs)
+        count(t, "energyOver", e.over)
+        count(t, "windows", e.windows)
+        most(t, "rageErr", metrics.power(c, W, dw.RAGE, 0).maxAbs)
+        local p = metrics.power(c, W, dw.POINTS, 0.5)
+        count(t, "pointsTicks", p.settled)
+        count(t, "pointsExact", p.exact * p.settled)
+        gcd(t, f)
+    end)
+    t.pairing = metrics.rate(m, 1)
+    return t, m
+end
+
+--- §4.3-§4.4 the shift fight over `n` fights (variant `v`: onEnter): by form section, the credits, the share scored on
+--- timing alone, the rage belief's overshoot in Bear; the believed minus the true rage right after each Bear entry
+--- (`bearEntryOver`, `bearEntryUnder`: the rage zeroed in both, or a swing landing after it paid both), the energy error at each
+--- Cat entry and the time until it is within 5; the swing value; the GCDs.
+local function shift(n, v)
+    local t, mBear, mCat = {}, metrics.new(), metrics.new()
+    dw.fights("shift", n, v, function(f)
+        local c, s, W = f.c, f.s, f.W
+        local formAt = dw.formAt(W, dw.CAT)
+        local function inBear(x)
+            return formAt(x) == dw.BEAR
+        end
+        local function inCat(x)
+            return formAt(x) == dw.CAT
+        end
+        metrics.score(mBear, c, s, W, f.R.swing, 0, inBear)
+        metrics.score(mCat, c, s, W, f.R.swing, 0, inCat)
+        local nb, ub = metrics.unknown(c, s, inBear)
+        local nc, uc = metrics.unknown(c, s, inCat)
+        count(t, "bearWounds", nb)
+        count(t, "bearUnknown", ub)
+        count(t, "catWounds", nc)
+        count(t, "catUnknown", uc)
+        local r = metrics.power(c, W, dw.RAGE, f.R.swing, { keep = inBear })
+        count(t, "rageOver", r.over)
+        count(t, "rageMean", r.meanAbs / n)
+        most(t, "rageOverMax", r.overMax)
+        local e = metrics.power(c, W, dw.ENERGY, 5)
+        count(t, "energyOver", e.over)
+        count(t, "energyMean", e.meanAbs / n)
+        most(t, "swingMax", f.swingValues.max) -- D4: every swing the rage belief pays at the form's fixed 2.5 s
+        least(t, "swingMin", f.swingValues.min)
+        local rk, ek = c.trk[dw.RAGE], c.trk[dw.ENERGY]
+        local rageAt, energyAt = metrics.truthOf(W, dw.RAGE), metrics.truthOf(W, dw.ENERGY)
+        for _, ev in ipairs(W.truth) do
+            if ev.kind == "form" and ev.form == dw.BEAR then -- a swing landing just after the entry pays both
+                local k = after(rk, ev.t)
+                most(t, "bearEntryOver", rk.est[k] - rageAt(rk.t[k]))
+                least(t, "bearEntryUnder", rk.est[k] - rageAt(rk.t[k]))
+            elseif ev.kind == "form" and ev.form == dw.CAT then
+                local k = after(ek, ev.t)
+                local err = math.abs(ek.est[k] - energyAt(ek.t[k]))
+                count(t, "catEntries")
+                count(t, "entryErr", err)
+                while k < ek.n and math.abs(ek.est[k] - energyAt(ek.t[k])) > 5 do
+                    k = k + 1
+                end
+                count(t, "fixSeconds", ek.t[k] - ev.t)
+            end
+        end
+        gcd(t, f)
+    end)
+    t.entryErr, t.fixSeconds = t.entryErr / t.catEntries, t.fixSeconds / t.catEntries
+    return t, mBear, mCat
+end
+
+--- §4.5 the decay after a fight ending in Bear with Enrage up, over `n` fights (variant `v`: pausedBy, declared): the
+--- believed change of rage since 1.5 s after the stop (our last swings landed) minus the true change, at every second.
+local function decay(n, v)
+    local t = {}
+    dw.fights("decay", n, v, function(f)
+        local c, W = f.c, f.W
+        local rk, at = c.trk[dw.RAGE], metrics.truthOf(W, dw.RAGE)
+        least(t, "rageAtStop", at(W.stopAt))
+        local base = after(rk, W.stopAt + 1.5)
+        local e0, v0 = rk.est[base], at(rk.t[base])
+        local low = 0
+        for k = base, rk.n do
+            local x = rk.t[k] - W.stopAt
+            if rk.t[k] <= W.t and math.abs(x - math.floor(x + 0.5)) < 0.05 then
+                local err = (rk.est[k] - e0) - (at(rk.t[k]) - v0)
+                most(t, "errMax", err)
+                least(t, "errMin", err)
+                low = math.min(low, err)
+            end
+        end
+        count(t, "lowFights", low < -1.25 and 1 or 0)
+    end)
+    return t
+end
+
+local function gcdGate(t, msg)
+    assert.is_true(t.gcdSeen == t.gcds and t.gcdExtra == 0 and t.gcdErr <= 0.01, msg)
+    assert.is_true(t.ownerless == 0 and t.order1 > 0 and t.order2 > 0, msg)
+end
+
+-- The gates (§4.6), each at `k` x the design's fights.
+local GATES = {
+    bear = function(k)
+        local t, m = bear(200 * k)
+        local msg = line("solo bear", t, m)
+        print(msg)
+        assert.is_true(metrics.rate(m, 1) >= 0.94 and m.wrong[1] == 0 and metrics.falsePer100(m) == 0, msg)
+        assert.is_true(t.driftOver == 0 and t.danger == 0, msg)
+        assert.is_true(t.strikes > 0 and t.maulRows == t.strikes and t.maulPaid == t.strikes, msg)
+        assert.is_true(t.staged >= 0.94 * t.crits and t.false3 == 0, msg)
+        gcdGate(t, msg)
+    end,
+    cat = function(k)
+        local t, m = cat(200 * k, {}, 0)
+        local msg = line("solo cat", t, m)
+        print(msg) -- the white pairing at a 1.0 s period: reported
+        assert.is_true(t.rageErr == 0, msg)
+        assert.is_true(t.energyMean <= 10 and t.energyOver <= 0.02 * t.windows, msg)
+        assert.is_true(t.pointsExact == t.pointsTicks, msg)
+        gcdGate(t, msg)
+    end,
+    regenAfter = function(k)
+        local t, m = cat(100 * k, { regenAfter = { s = 5, k = 1.25 } }, 21)
+        local msg = line("solo cat, regenAfter 5 s x 1.25", t, m)
+        print(msg)
+        assert.is_true(t.energyMean <= 15 and t.energyOver <= 0.05 * t.windows, msg)
+    end,
+    reload = function(k)
+        local t, m = cat(50 * k, { regenRead = false }, 0)
+        print(line("solo cat, a /reload in combat (no regen read)", t, m)) -- report only: sizes the shortcut
+    end,
+    shift = function(k)
+        local t, mBear, mCat = shift(100 * k, {})
+        local msg = line("shift fight", t, mBear) .. " | Cat sections: " .. metrics.line(mCat)
+        print(msg)
+        assert.is_true(metrics.rate(mBear, 1) >= 0.85, msg)
+        assert.is_true(metrics.falsePer100(mBear) == 0 and metrics.falsePer100(mCat) == 0, msg)
+        assert.is_true(t.catUnknown == 0 and t.bearUnknown == t.bearWounds and t.bearWounds > 0, msg)
+        assert.is_true(
+            t.rageOver == 0 and math.abs(t.swingMin - 8.65) < 1e-9 and math.abs(t.swingMax - 8.65) < 1e-9,
+            msg
+        )
+        assert.is_true(t.bearEntryOver <= 1.3, msg) -- no rage carried into Bear: a swing at the calibrated scale at most
+        gcdGate(t, msg)
+    end,
+    furor = function(k)
+        local variants = {
+            { "Cat entry zero", { cat = { [dw.ENERGY] = "zero" } } },
+            {
+                -- Furor's Cat restore (the energy left plus 10 a second out of Cat) is what the world's regen in every
+                -- form already gives: the Cat entry keeps
+                "Furor rank 5",
+                {
+                    bear = {
+                        [dw.RAGE] = function()
+                            return 10 -- 20% a rank of 10 rage: rank 5 always
+                        end,
+                    },
+                },
+            },
+        }
+        for _, x in ipairs(variants) do
+            local t, mBear = shift(50 * k, { onEnter = x[2] })
+            local msg = line("shift fight, " .. x[1], t, mBear)
+            print(msg) -- report: the error at each Cat entry and the time a usability pin takes to correct it
+            assert.is_true(t.rageOver == 0 and t.bearEntryOver <= 1.3, msg) -- Bear's rage never an overshoot
+        end
+    end,
+    decay = function(k)
+        for _, v in ipairs({
+            { pausedBy = true, declared = true },
+            { pausedBy = false, declared = false },
+        }) do
+            local t = decay(20 * k, v)
+            local msg = line(("decay, paused %s, declared %s"):format(tostring(v.pausedBy), tostring(v.declared)), t)
+            print(msg)
+            -- as built: one fight in 20 (seed 15) loses Enrage's expiry tick (2) in both pairs, below the truth (a
+            -- VirtualState finding: the tick and the decay's first quantum at the aura's expiry; its own change)
+            assert.is_true(t.errMax <= 1.25 and t.errMin >= -2 and t.lowFights <= math.max(1, 0.05 * 20 * k), msg)
+        end
+        local over = decay(20 * k, { pausedBy = false, declared = true })
+        local overMsg = line("decay, a declared pause over a decaying truth", over)
+        print(overMsg) -- the dangerous sign: up to 1.25 x 7 rage above the truth
+        assert.is_true(over.errMax > 1.25 and over.errMin >= -1.25, overMsg)
+        local under = decay(20 * k, { pausedBy = true, declared = false })
+        local underMsg = line("decay, no declaration over a pausing truth", under)
+        print(underMsg) -- the safe sign: below the truth
+        assert.is_true(under.errMin < -1.25 and under.errMax <= 1.25, underMsg)
+    end,
+}
+
+describe("Druid harness scenarios, a tenth of the fights (GCD kinds design §4.6) #slow", function()
+    for _, name in ipairs({ "bear", "cat", "regenAfter", "reload", "shift", "furor", "decay" }) do
+        it(name, function()
+            GATES[name](0.1)
+        end)
+    end
+end)
+
+describe("Druid harness scenarios at the design's fight counts (GCD kinds design §4.6) #druid", function()
+    for _, name in ipairs({ "bear", "cat", "regenAfter", "reload", "shift", "furor", "decay" }) do
+        it(name, function()
+            GATES[name](1)
+        end)
+    end
+end)
diff --git a/tests/Forever/druid_spec.lua b/tests/Forever/druid_spec.lua
index ce65d6f7..e8245368 100644
--- a/tests/Forever/druid_spec.lua
+++ b/tests/Forever/druid_spec.lua
@@ -847,6 +847,7 @@ describe("Forever Druid in VirtualState's now context", function()
     local load = require("Virtual.State.helpers.load")
     local fake = require("Virtual.State.helpers.fake_api")
     local fs = require("Virtual.State.helpers.fake_spec")
+    local dvs = require("Forever.helpers.druid_vs")
     local ns, VS, I, api, ctl, w, h, saved
 
     local function cast(id, t)
@@ -874,50 +875,7 @@ describe("Forever Druid in VirtualState's now context", function()
         end
         ns = load.module()
         VS, I = ns.VirtualState, ns.VirtualStateInternal
-        w = ld.load(VS) -- the class file's knownRank and swing base read this VirtualState
-        w.state.mainhand_speed = 2.5
-        -- Hekili's class from the file's registrations: values evaluated at talent rank 0, functions kept in `funcs`
-        local e = ld.env(w)
-        local class = { primaryResource = "energy", abilities = {}, auras = {}, talents = w.talents }
-        class.resources = {
-            energy = { type = 3, state = {} },
-            combo_points = { type = 4, state = {} },
-            rage = { type = 1, state = { regenModel = w.resources[1].models, meta = w.resources[1].meta } },
-            mana = { type = 0, state = {} },
-        }
-        for key, a in pairs(w.abilities) do
-            class.abilities[key] = {
-                key = key,
-                id = a.id,
-                copy = a.copy,
-                spend = a.spend ~= nil and ld.run(a.spend, e) or nil,
-                spendType = a.spendType,
-                cooldown = ld.run(a.cooldown, e),
-                gcd = a.gcd,
-                onNextSwing = a.onNextSwing,
-                cast = 0,
-                charges = 1,
-                recharge = 0,
-                funcs = { now = a.now, handler = a.handler },
-            }
-        end
-        for key, a in pairs(w.auras) do
-            class.auras[key] = { key = key, id = a.id, copy = a.copy, duration = a.duration, max_stack = a.max_stack }
-        end
-        h = fs.new(9)
-        h.Class = class
-        fs.clock = api.GetTime
-        ns.spendResources = fs.spend
-        ns.ResourceRegenerates = function(k)
-            return k == "energy" or k == "mana"
-        end
-        ns.ResourceIsPoints = function(k) -- Constants.lua's, for the one point resource here
-            return k == "combo_points"
-        end
-        ns.raceMods = { maxMods = {}, costMods = w.costMods } -- Clearcasting, as spec:RegisterCostMod appends it
-        load.adapter(ns, h)
-        VS.Start(api)
-        VS.SpecChanged()
+        w, h = dvs.boot(ns, api)
         ctl.Tick(1)
         I.ObsLog.Clear(I.log)
     end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `620 successes / 0 failures / 2 errors / 0 pending`.
- druid_harness_spec errors at load (`module 'Forever.helpers.druid_world' not found`); druid_spec's "Forever Druid in VirtualState's now context" errors (`module 'Forever.helpers.druid_vs' not found`: its 5 cases do not run).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/Makefile b/Makefile
index 217e41b1..3de92cf5 100644
--- a/Makefile
+++ b/Makefile
@@ -5,7 +5,7 @@ BUSTED := $(LUA_ENV)/bin/busted
 LUACHECK := $(LUA_ENV)/bin/luacheck
 LUAC := $(LUA_ENV)/bin/luac
 
-.PHONY: bootstrap lint fmt fmt-check typecheck test test-fast test-loop test-party syntax api-check check
+.PHONY: bootstrap lint fmt fmt-check typecheck test test-fast test-loop test-party test-druid syntax api-check check
 
 bootstrap:
 	scripts/bootstrap.sh
@@ -22,13 +22,14 @@ fmt-check:
 typecheck:
 	lua-language-server --check . --checklevel=Error --logpath $(LUA_ENV)/lsp-log
 
-# The headless loop's 20-fight Arms gate (#loop) and party report (#party) run only behind their own targets.
+# The headless loop's 20-fight Arms gate (#loop) and party report (#party), and the Druid harness gates at the GCD
+# kinds design's fight counts (#druid), run only behind their own targets.
 test:
-	$(BUSTED) --exclude-tags=party,loop
+	$(BUSTED) --exclude-tags=party,loop,druid
 
 # The edit loop: skips the harness gate specs tagged #slow (hundreds of simulated fights); `make check` runs them.
 test-fast:
-	$(BUSTED) --exclude-tags=slow,party,loop
+	$(BUSTED) --exclude-tags=slow,party,loop,druid
 
 test-loop:
 	$(BUSTED) --tags=loop
@@ -36,6 +37,9 @@ test-loop:
 test-party:
 	$(BUSTED) --tags=party
 
+test-druid:
+	$(BUSTED) --tags=druid
+
 syntax:
 	git ls-files -z '*.lua' | xargs -0 -n 200 $(LUAC) -p
 
diff --git a/tests/Forever/helpers/druid_vs.lua b/tests/Forever/helpers/druid_vs.lua
new file mode 100644
index 00000000..248a9f64
--- /dev/null
+++ b/tests/Forever/helpers/druid_vs.lua
@@ -0,0 +1,68 @@
+-- tests/Forever/helpers/druid_vs.lua: the Forever Druid in a real VirtualState (tests/Forever/druid_spec.lua's "in
+-- VirtualState's now context" and the Druid harness scenarios, tests/Forever/helpers/druid_world.lua): Hekili's class
+-- built from the class file's registrations (load_druid.lua's recording load; values evaluated at talent rank 0,
+-- functions kept in `funcs`) and handed to the Adapter through the fake spec provider.
+local ld = require("Forever.helpers.load_druid")
+local load = require("Virtual.State.helpers.load")
+local fs = require("Virtual.State.helpers.fake_spec")
+
+local M = {}
+
+--- Builds the Druid's class into the VirtualState `ns` loaded (Virtual.State.helpers.load) on fake_api `api` and
+--- starts it at SpecChanged. `edit(class, w)` (optional) changes the class before the build (a scenario's declaration
+--- variant). Returns `w` (the recording load, bound to this VirtualState) and `h` (the fake Hekili). The caller sets
+--- the globals the build reads (GetTime, UnitGUID, CreateFrame, issecretvalue, debugprofilestop) and clears
+--- `fs.clock` afterwards.
+function M.boot(ns, api, edit)
+    local VS = ns.VirtualState
+    local w = ld.load(VS) -- the class file's knownRank reads this VirtualState
+    w.state.mainhand_speed = 2.5
+    local e = ld.env(w)
+    local class = { primaryResource = "energy", abilities = {}, auras = {}, talents = w.talents }
+    class.resources = {
+        energy = { type = 3, state = {} },
+        combo_points = { type = 4, state = {} },
+        rage = { type = 1, state = { regenModel = w.resources[1].models, meta = w.resources[1].meta } },
+        mana = { type = 0, state = {} },
+    }
+    for key, a in pairs(w.abilities) do
+        class.abilities[key] = {
+            key = key,
+            id = a.id,
+            copy = a.copy,
+            spend = a.spend ~= nil and ld.run(a.spend, e) or nil,
+            spendType = a.spendType,
+            cooldown = ld.run(a.cooldown, e),
+            gcd = a.gcd,
+            onNextSwing = a.onNextSwing,
+            startsCombat = ld.run(a.startsCombat, e), -- Rows.lua credits a strike's hit to its cast
+            cast = 0,
+            charges = 1,
+            recharge = 0,
+            funcs = { now = a.now, handler = a.handler },
+        }
+    end
+    for key, a in pairs(w.auras) do
+        class.auras[key] = { key = key, id = a.id, copy = a.copy, duration = a.duration, max_stack = a.max_stack }
+    end
+    if edit then
+        edit(class, w)
+    end
+    local h = fs.new(9)
+    h.Class = class
+    fs.clock = api.GetTime
+    ns.spendResources = fs.spend
+    ns.ResourceRegenerates = function(k)
+        return k == "energy" or k == "mana"
+    end
+    ns.ResourceIsPoints = function(k) -- Constants.lua's, for the one point resource here
+        return k == "combo_points"
+    end
+    ns.raceMods = { maxMods = {}, costMods = w.costMods } -- Clearcasting, as spec:RegisterCostMod appends it
+    load.adapter(ns, h)
+    VS.Start(api)
+    VS.SpecChanged()
+    return w, h
+end
+
+return M
diff --git a/tests/Forever/helpers/druid_world.lua b/tests/Forever/helpers/druid_world.lua
new file mode 100644
index 00000000..24927df8
--- /dev/null
+++ b/tests/Forever/helpers/druid_world.lua
@@ -0,0 +1,570 @@
+-- tests/Forever/helpers/druid_world.lua (GCD kinds design §3-§4): the Druid content of the class-neutral combat
+-- harness: the character's resources, forms and rates, each ability's press in the world's generic verbs, the client's
+-- usability answers and the fights the gates run (tests/Forever/druid_harness_spec.lua). Spell and aura IDs, costs,
+-- GCD kinds, cooldowns, durations, form requirements, the rage per swing, Enrage's ticks, the decay, the entry rules
+-- of a shift and Shifting Power's energy come from the class file (load_druid.lua's recording load, its `now` and
+-- `swap_form` run in the stand-in state), never copied here. Damage amounts and the weapon are UNMEASURED: the
+-- scenarios score the belief, not the damage.
+local ld = require("Forever.helpers.load_druid")
+local dvs = require("Forever.helpers.druid_vs")
+local drive = require("Virtual.harness.drive")
+local scenarios = require("Virtual.harness.scenarios")
+local fs = require("Virtual.State.helpers.fake_spec")
+
+local M = {}
+
+M.MANA, M.RAGE, M.ENERGY, M.POINTS = 0, 1, 3, 4 -- Enum.PowerType
+local PT = { mana = M.MANA, rage = M.RAGE, energy = M.ENERGY, combo_points = M.POINTS }
+M.TOKENS = { [M.MANA] = "MANA", [M.RAGE] = "RAGE", [M.ENERGY] = "ENERGY", [M.POINTS] = "COMBO_POINTS" }
+
+-- The client's forms in Classic's index order (Forms.lua maps them by spell ID, so the real order (Q2) changes nothing).
+M.FORMS = { "bear_form", "aquatic_form", "cat_form", "travel_form" }
+M.FORM = {}
+for i, key in ipairs(M.FORMS) do
+    M.FORM[key] = i
+end
+M.BEAR, M.CAT = M.FORM.bear_form, M.FORM.cat_form
+-- The main hand's period in each form (Classic's; checkpoint G6 reads them) and its damage against Cat's (UNMEASURED).
+M.SPEED = { [M.BEAR] = 2.5, [M.CAT] = 1.0 }
+M.DMG = { [M.BEAR] = 1.6, [M.CAT] = 1.0 }
+M.WEAPON = { 55, 75 } -- the paws' white damage in Cat (UNMEASURED)
+M.ENERGY_REGEN = 10 -- energy a second (probe W's out-of-combat read: 10.001)
+-- GCD seconds by kind, at haste 1 (Hekili's kinds; the DB2's StartRecoveryTime; checkpoints G1-G3).
+M.GCD = { totem = 1.0, spell = 1.5, off = 0 }
+-- UNMEASURED amounts of the instant strikes (a hit on the target: Rows.lua credits it to the cast).
+local AMOUNT = {
+    claw = 90,
+    shred = 160,
+    rake = 40,
+    ferocious_bite = 300,
+    primal_bite = 120,
+    lacerate = 30,
+    swipe_bear = 80,
+}
+
+-- The recording load and its stand-in state (talents at rank 0), once.
+local W0, E0
+local function class()
+    if not W0 then
+        W0 = ld.load()
+        E0 = ld.env(W0)
+    end
+    return W0, E0
+end
+
+-- What a `now` gains, by resource key (the class file's own amounts: Shifting Power's energy, Enrage's rage).
+local function nowGains(key)
+    local w, e = class()
+    e.gained = {}
+    ld.run(w.abilities[key].now, e)
+    local out = {}
+    for _, g in ipairs(e.gained) do
+        out[#out + 1] = { PT[g[2]], g[1] }
+    end
+    return out
+end
+
+-- A shift's entry rule per resource, from the class file's swap_form at 50 rage: "zero" when it spends it all.
+local function entryRules(form)
+    local w, e = class()
+    e.spent, e.rage.current, e.energy.current = {}, 50, 50
+    e.swap_form(form)
+    local rules = { [M.RAGE] = "keep", [M.ENERGY] = "keep" }
+    for _, s in ipairs(e.spent) do
+        if s[1] == 50 then
+            rules[PT[s[2]]] = "zero"
+        end
+    end
+    return rules
+end
+
+-- The rage entries of the class file's model: per white swing in Bear (`value`, `crit`), Enrage's ticks, the decay.
+local function rageModel()
+    local w = class()
+    local r = w.resources[M.RAGE]
+    return r.models, r.meta
+end
+
+--- The world's rates and rules read from the class file: { swing, crit, payIn, tick = { every, amount }, decay = {
+--- rate, interval }, enterBear, enterCat, shiftingPower (energy), enrage (rage at once) }.
+function M.rules()
+    local models, meta = rageModel()
+    local mh, en = models.mainhand, models.enrage
+    return {
+        swing = mh.value(),
+        crit = mh.crit(),
+        payIn = M.FORM[mh.aura],
+        tick = { every = en.interval, amount = en.value },
+        decay = { rate = meta.decay(), interval = meta.decayInterval() },
+        enterBear = entryRules("bear_form"),
+        enterCat = entryRules("cat_form"),
+        shiftingPower = nowGains("shifting_power")[1][2],
+        enrage = nowGains("enrage")[1][2],
+    }
+end
+
+-- Each pressed ability's effect beyond its cost (the world's generic verbs); `R` the rules above.
+local function hit(key)
+    return function(W, e)
+        W.hit(e, e.target, AMOUNT[key])
+    end
+end
+local function debuff(key, alsoHit)
+    return function(W, e)
+        local w = class()
+        local a = w.auras[key]
+        W.applyAura(e.target, a.id, a.duration, 1, a.max_stack)
+        if alsoHit then
+            W.hit(e, e.target, AMOUNT[key])
+        end
+    end
+end
+local MAP = {
+    claw = { effect = hit("claw"), points = 1 },
+    shred = { effect = hit("shred"), points = 1 },
+    rake = { effect = debuff("rake", true), points = 1 },
+    rip = { effect = debuff("rip"), points = "all" },
+    ferocious_bite = { effect = hit("ferocious_bite"), points = "all", drain = M.ENERGY },
+    shifting_power = {
+        extra = function(p, R)
+            p.gain = { M.ENERGY, R.shiftingPower }
+        end,
+    },
+    faerie_fire = { effect = debuff("faerie_fire") },
+    primal_bite = { effect = hit("primal_bite") },
+    lacerate = { effect = debuff("lacerate", true) },
+    swipe_bear = { effect = hit("swipe_bear") },
+    demoralizing_roar = { effect = debuff("demoralizing_roar") },
+    maul = { amount = { 110, 140 } },
+    enrage = {
+        extra = function(p, R)
+            local w = class()
+            p.gain = { M.RAGE, R.enrage }
+            local a = w.auras.enrage
+            p.aura = {
+                id = a.id,
+                duration = a.duration,
+                tick = { pt = M.RAGE, every = R.tick.every, amount = R.tick.amount },
+            }
+        end,
+    },
+    bear_form = {
+        extra = function(p, R, o)
+            local mult = M.DMG[M.BEAR] / M.DMG[o.form or M.CAT] -- the pull's form's weapon is the base
+            p.shift = { form = M.BEAR, dmgMult = mult, onEnter = (o.onEnter or {}).bear or R.enterBear }
+        end,
+    },
+    cat_form = {
+        extra = function(p, R, o)
+            local mult = M.DMG[M.CAT] / M.DMG[o.form or M.CAT]
+            p.shift = { form = M.CAT, dmgMult = mult, onEnter = (o.onEnter or {}).cat or R.enterCat }
+        end,
+    },
+}
+M.MAP = MAP
+
+--- The resolved press of `key` from the class file: its rank 1 ID, its cost (rank 0 talents) and power type (a mana
+--- cost is not modelled: mana is never read), its cooldown, its GCD by kind, on-next-swing, its form requirement (the
+--- ability's `buff` / `nobuff` form fields) and the mapping's effects. `o.onEnter` { bear, cat }: a variant's entry
+--- rules over the class file's.
+function M.press(key, R, o)
+    local m = assert(MAP[key], "unmapped key " .. tostring(key))
+    local w, e = class()
+    local a = w.abilities[key]
+    local cost, pt = ld.run(a.spend, e) or 0, PT[a.spendType]
+    if pt == M.MANA or cost < 1 then
+        cost, pt = 0, nil
+    end
+    local p = {
+        spell = a.id,
+        cost = cost,
+        pt = pt,
+        cooldown = ld.run(a.cooldown, e) or 0,
+        gcd = M.GCD[a.gcd or "spell"],
+        onNextSwing = a.onNextSwing,
+        amount = m.amount,
+        effect = m.effect,
+        drain = m.drain,
+    }
+    if m.points then
+        p.points = { M.POINTS, m.points }
+    end
+    if m.extra then
+        m.extra(p, R, o or {})
+    end
+    local need, avoid = M.FORM[a.buff], M.FORM[a.nobuff]
+    p.requires = function(_, us)
+        if need and us.form ~= need then
+            return false, a.buff
+        elseif avoid and us.form == avoid then
+            return false, "not " .. a.nobuff
+        end
+        return true
+    end
+    return p
+end
+
+--- The client's usability answers (observer `k.usable`) for `keys`' rank 1 IDs: unusable (not for power) out of the
+--- required form, else usable when the client's view of the cost's own type covers it, short when not.
+function M.usable(keys, R)
+    local out = {}
+    for _, key in ipairs(keys) do
+        local p = M.press(key, R)
+        out[#out + 1] = {
+            p.spell,
+            function(W, us, power, view)
+                if not p.requires(W, us) then
+                    return false, false
+                end
+                local have = (p.pt == nil and math.huge) or (p.pt == us.pt and power) or view[p.pt]
+                return have >= p.cost, have < p.cost
+            end,
+        }
+    end
+    return out
+end
+
+--- Our presses as a script (scenarios.world's `script`): every `every` s, once the true GCD is over, the first entry
+--- of `list` ({ key, when = fn(W, us, t) }) whose `when` holds and that W.press accepts; `extra` entries (off the
+--- GCD) are tried every 0.1 s. `presses` (optional) collects each accepted press as { t, key }.
+function M.script(list, every, extra, R, o, presses)
+    local P = {}
+    for _, x in ipairs(list) do
+        P[x[1]] = M.press(x[1], R, o)
+    end
+    for _, x in ipairs(extra or {}) do
+        P[x[1]] = M.press(x[1], R, o)
+    end
+    return function(W, us)
+        local nextT = W.t
+        local function tick()
+            if us.stopped then
+                return
+            end
+            for _, x in ipairs(extra or {}) do
+                if (not x.when or x.when(W, us, W.t)) and W.press(us, x[1], P[x[1]]) and presses then
+                    presses[#presses + 1] = { W.t, x[1] }
+                end
+            end
+            if W.t >= nextT - 1e-9 and W.t >= us.gcdUntil then
+                for _, x in ipairs(list) do
+                    if (not x.when or x.when(W, us, W.t)) and W.press(us, x[1], P[x[1]]) then
+                        nextT = W.t + every
+                        if presses then
+                            presses[#presses + 1] = { W.t, x[1] }
+                        end
+                        break
+                    end
+                end
+            end
+            W.at(W.t + 0.1, tick)
+        end
+        -- half a tick off the drive's 0.1 s grid: a press and its GCD edges never share a time with a drive tick, so
+        -- one frame's events (the edge and the success, either order) reach the belief before a GcdInfo read
+        W.at(W.t + 0.05, tick)
+    end
+end
+
+-- Whether the target has aura `key` (the class file's ID) in the world now.
+local function onTarget(us, key)
+    local w = class()
+    return us.target and us.target.auras[w.auras[key].id] ~= nil
+end
+M.onTarget = onTarget
+
+-- The scripted lists (§4.1, §4.2). Bear, every 1.5 s down the list when the true rage covers each: Demoralizing Roar
+-- while its debuff is down, Primal Bite and Lacerate above 40 rage, Swipe above 60 (the rage left over pays Maul);
+-- Maul queued whenever the rage covers Maul and Primal Bite; Enrage once, at `enrageAt`. Cat: Faerie Fire every 40 s,
+-- Shifting Power off cooldown, Rip at 5 points, Rake while its debuff is down, Shred otherwise, each only when the
+-- true energy covers it.
+local function rageAbove(n)
+    return function(_, us)
+        return us.power >= n
+    end
+end
+function M.bearList()
+    return {
+        {
+            "demoralizing_roar",
+            when = function(_, us)
+                return not onTarget(us, "demoralizing_roar")
+            end,
+        },
+        { "primal_bite", when = rageAbove(40) },
+        { "lacerate", when = rageAbove(40) },
+        { "swipe_bear", when = rageAbove(60) },
+    }
+end
+function M.bearExtra(R, enrageAt)
+    local maul, bite = M.press("maul", R), M.press("primal_bite", R)
+    local enraged = false
+    return {
+        {
+            "maul",
+            when = function(_, us)
+                return us.form == M.BEAR and not us.queued and us.power >= maul.cost + bite.cost
+            end,
+        },
+        {
+            "enrage",
+            when = function(_, us, t)
+                if enraged or us.form ~= M.BEAR or t < enrageAt then
+                    return false
+                end
+                enraged = true
+                return true
+            end,
+        },
+    }
+end
+function M.catList()
+    local fire = -math.huge
+    return {
+        {
+            "faerie_fire",
+            when = function(W, us)
+                if W.t - fire >= 40 and us.form == M.CAT then
+                    fire = W.t
+                    return true
+                end
+                return false
+            end,
+        },
+        { "shifting_power" },
+        {
+            "rip",
+            when = function(W, us)
+                return W.res(us, M.POINTS) >= 5
+            end,
+        },
+        {
+            "rake",
+            when = function(_, us)
+                return not onTarget(us, "rake")
+            end,
+        },
+        { "shred" },
+    }
+end
+
+M.KEYS = {
+    "claw",
+    "shred",
+    "rake",
+    "rip",
+    "ferocious_bite",
+    "shifting_power",
+    "primal_bite",
+    "lacerate",
+    "swipe_bear",
+    "demoralizing_roar",
+    "maul",
+}
+
+--- The knobs of a Druid fight over scenario `o` (scenarios.world's): level 60, the paws, our resources (rage the
+--- swing-paid `power`; energy 100 of 100 regenerating, combo points, mana unmodelled), the form's period and damage at
+--- the pull, the rage per Bear swing and crit from the class file, its out-of-combat decay, the GCD flag's order mixed,
+--- and the observer: the GCD spell, combo points plain, rage and energy never, the forms, usability from `KEYS`.
+--- `o.form` the pull's form; `o.script` our presses; `o.pausedBy` the decay's truth variant; `o.regenAfter`,
+--- `o.regenRead` (false: no regen read, a /reload in combat), `o.usable` (false: no answers).
+function M.knobs(o, R, gcdSpell)
+    local form = o.form or M.CAT
+    local k = {
+        level = 60,
+        weapons = { { M.WEAPON[1] * M.DMG[form], M.WEAPON[2] * M.DMG[form], M.SPEED[form] } },
+        max = 100,
+        mobHealth = 1e9,
+        duration = o.duration,
+        pt = M.RAGE,
+        res = { [M.ENERGY] = { cur = 100, max = 100 }, [M.POINTS] = { cur = 0, max = 5 } },
+        regen = { [M.ENERGY] = M.ENERGY_REGEN },
+        regenAfter = o.regenAfter,
+        decay = { pt = M.RAGE, rate = R.decay.rate, interval = R.decay.interval, pausedBy = o.pausedBy or false },
+        formSpeed = M.SPEED,
+        payIn = R.payIn,
+        rage = { R.swing, 0 },
+        critRage = { R.crit, 0 },
+        gcdOrder = "mixed",
+        form = form,
+        script = o.script,
+        after = o.after,
+        rates = o.rates,
+        usable = o.usable ~= false and M.usable(M.KEYS, R) or false,
+        observe = {
+            gcdSpell = gcdSpell,
+            plainPower = { [M.RAGE] = "never", [M.ENERGY] = "never", [M.POINTS] = "always" },
+            powerTokens = M.TOKENS,
+            forms = M.formIds(),
+            playerSpeed = true,
+            regenRead = o.regenRead ~= false,
+        },
+    }
+    return k
+end
+
+--- The client's forms list (index to the class file's spell ID).
+function M.formIds()
+    local w = class()
+    local ids = {}
+    for i, key in ipairs(M.FORMS) do
+        ids[i] = w.abilities[key].id
+    end
+    return ids
+end
+
+--- One Druid fight of scenario `o` at `seed`: VirtualState booted with the Druid's class (`o.edit(class, w)` a
+--- declaration variant), the world built and observed, the stream run. Returns { c, s, W, R, rows, swingValues }
+--- (`rows` the combat-log rows of ours by event: { [subevent] = { [spellID] = n } }; `swingValues` { min, max } of the
+--- rage belief's swing values); the caller restores with M.done.
+function M.fight(o, seed)
+    local R = M.rules()
+    local saved = {}
+    local c = drive.boot({
+        max = 100,
+        oracle = o.oracle,
+        track = { M.RAGE, M.ENERGY, M.POINTS },
+        boot = function(c)
+            for _, key in ipairs({ "UnitGUID", "debugprofilestop" }) do
+                saved[key] = rawget(_G, key) or false
+            end
+            _G.UnitGUID = c.api.UnitGUID
+            _G.debugprofilestop = function()
+                return 0
+            end
+            local ctl = c.ctl
+            ctl.powerMax[M.ENERGY], ctl.powerMax[M.POINTS], ctl.powerMax[M.MANA] = 100, 5, 1e6
+            ctl.powerMax[M.RAGE] = 100
+            local w = class()
+            for _, key in ipairs(M.KEYS) do
+                ctl.known[w.abilities[key].id] = true
+            end
+            for _, key in ipairs({ "bear_form", "cat_form", "enrage", "faerie_fire" }) do
+                ctl.known[w.abilities[key].id] = true
+            end
+            dvs.boot(c.ns, c.api, o.edit)
+        end,
+    })
+    c.druidSaved = saved
+    -- every swing value the rage belief steps by (Resources.lua asks I.SwingValue at each landed swing it pays)
+    local sv, I, rage = c.I.SwingValue, c.I, 0
+    for r = 1, I.res.n do
+        rage = I.res.type[r] == M.RAGE and r or rage
+    end
+    local values = { min = math.huge, max = -math.huge }
+    I.SwingValue = function(r, hand)
+        local v = sv(r, hand)
+        if r == rage and hand ~= 2 and v > 0 then -- the main hand's while Bear's aura is believed up
+            values.min, values.max = math.min(values.min, v), math.max(values.max, v)
+        end
+        return v
+    end
+    local rows = {}
+    local GetInfo = c.ns.Facade.CombatLogGetCurrentEventInfo
+    local sink = c.I.Events.CreateFrame("Frame")
+    sink:SetScript("OnEvent", function()
+        local _, ev, _, src, _, _, _, _, _, _, _, spell = GetInfo()
+        if src == "Player-1" then
+            rows[ev] = rows[ev] or {}
+            rows[ev][spell or 0] = (rows[ev][spell or 0] or 0) + 1
+        end
+    end)
+    sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+    local k = M.knobs(o, R, c.I.GCD_SPELL)
+    for key, v in pairs(o.world or {}) do
+        k[key] = v
+    end
+    local s, W = scenarios.stream(k, seed)
+    drive.run(c, s)
+    return { c = c, s = s, W = W, R = R, rows = rows, swingValues = values }
+end
+
+--- Puts back what M.fight replaced.
+function M.done(f)
+    drive.restore(f.c)
+    for key, v in pairs(f.c.druidSaved) do
+        _G[key] = v or nil
+    end
+    fs.clock = nil
+end
+
+-- The scenarios (§4.1-§4.5): each builds the fight's knobs `o` for M.fight from the rules `R`.
+local PULL = 1 -- scenarios.world's default pull
+M.SCENARIOS = {
+    -- §4.1: pull in Bear, the bear list, Maul, Enrage once at 20 s
+    bear = function(R, v)
+        local o = { form = M.BEAR, usable = v.usable, oracle = v.oracle }
+        o.script = M.script(M.bearList(), 1.5, M.bearExtra(R, PULL + 20), R, o)
+        return o
+    end,
+    -- §4.2: pull in Cat, the cat list; `v.regenAfter`, `v.regenRead`
+    cat = function(R, v)
+        local o = { form = M.CAT, regenAfter = v.regenAfter, regenRead = v.regenRead }
+        o.script = M.script(M.catList(), 1.0, {}, R, o)
+        return o
+    end,
+    -- §4.3-§4.4: Cat at the pull, Bear at 30 s, Cat at 60, Bear at 90, stop at 120; `v.onEnter` a Furor variant
+    shift = function(R, v)
+        local o = { form = M.CAT, onEnter = v.onEnter }
+        local function at(form, from, to)
+            return function(_, us, t)
+                return us.form ~= form and t >= PULL + from and t < PULL + to
+            end
+        end
+        local list = { { "bear_form", when = at(M.BEAR, 30, 60) }, { "cat_form", when = at(M.CAT, 60, 90) } }
+        list[3] = { "bear_form", when = at(M.BEAR, 90, 1e9) }
+        for _, x in ipairs(M.catList()) do
+            list[#list + 1] = x
+        end
+        for _, x in ipairs(M.bearList()) do
+            list[#list + 1] = x
+        end
+        o.script = M.script(list, 1.0, M.bearExtra(R, math.huge), R, o)
+        return o
+    end,
+    -- §4.5: Bear, the fight ends at 60 s with Enrage pressed at 57 (its last 7 s out of combat), 20 s observed after;
+    -- `v.pausedBy` the truth's pause, `v.declared` the class's `pausesDecay` on its Enrage entry; no answers (the
+    -- model alone)
+    decay = function(R, v)
+        local o = { form = M.BEAR, duration = 59, after = 20, usable = false }
+        o.pausedBy = v.pausedBy and class().auras.enrage.id
+        if v.declared then
+            o.edit = function(class)
+                class.resources.rage.state.regenModel.enrage.pausesDecay = true
+            end
+        end
+        o.script = M.script(M.bearList(), 1.5, M.bearExtra(R, PULL + 56), R, o)
+        return o
+    end,
+}
+
+--- Fight `n` seeds of scenario `name` (variant `v`), calling `each(f)` on every fight before it is restored.
+function M.fights(name, n, v, each)
+    local R = M.rules()
+    for seed = 1, n do
+        local f = M.fight(M.SCENARIOS[name](R, v or {}), seed)
+        each(f)
+        M.done(f)
+    end
+end
+
+--- The true form at time `t` of world `W` (our form changes, in order), from the pull's `form0`.
+function M.formAt(W, form0)
+    local changes = {}
+    for _, ev in ipairs(W.truth) do
+        if ev.kind == "form" then
+            changes[#changes + 1] = { ev.t, ev.form }
+        end
+    end
+    return function(t)
+        local f = form0
+        for _, x in ipairs(changes) do
+            if x[1] > t then
+                break
+            end
+            f = x[2]
+        end
+        return f
+    end
+end
+
+return M
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted --exclude-tags=party,loop,druid`

Expected: `632 successes / 0 failures / 0 errors / 0 pending`. The seven `#slow` Druid gates take about 19 s and print their lines.

Then the design's counts: `make test-druid LUA_ENV=$HOME/src/hekili/.lua` -> `7 successes / 0 failures / 0 errors / 0 pending` (about 192 s).

Measured (the design's counts; the `#slow` run's tenth agrees within the bounds):

| Scenario (fights) | Measured | Gate (as built) |
|---|---|---|
| Solo bear (200) | main 6000/6047 (.992), wrong 0, false wounds 0; drift windows ending over 0 (all a step over: 4/2400, Deviation 11); danger 0; Mauls 1936: 1936 rows, 1936 paid; crits 920, staged 920, on a non-crit 0; GCDs 2067 seen, end error 0.0004 s, ownerless 0 (orders 1043 / 1024) | main >= .94, wrong 0, false 0; drift 0, danger 0; every Maul one `SPELL_DAMAGE`/`SPELL_MISSED` row and paid once; staged >= 94% of crits, 0 on a non-crit; GCD |
| Solo cat (200) | rage error 0; energy mean abs 1.78, over windows 0/2600; points exact on 226603 of 226603 settled ticks; GCDs 8407, end error 0.0004 s, ownerless 0 (orders 4193 / 4214); pairing: main .912 | rage exact; energy mean <= 10, over <= 2%; points 100%; GCD (every press's GCD seen at its start, end within 0.01 s, ownerless 0, both orders) |
| Solo cat, `regenAfter` (100) | energy mean abs 2.41 after 20 s, over 0/1100 | mean <= 15, over <= 5% |
| Solo cat, /reload in combat (50) | energy mean abs 11.4, over 0/650 | report |
| Shift fight (100) | Bear sections main 1680/1719 (.977), false 0 in both; timing alone 1719/1719 Bear, 0/4670 Cat; Bear rage over windows 0, mean abs 2.92; every swing 8.65 (before D4 every one 3.46, mean abs 3.94, entry under by up to 5.08); entry over 0.84 (Deviation 12); energy mean abs 0.28; GCDs 3036, ownerless 0 | Bear main >= .85; false 0; unknown 0 / 1; rage over 0, every swing 8.65; entry over <= 1.3; GCD |
| Furor variants (50 each) | Cat entry zero: entry error 99, within 5 after 35.7 s on average, energy over 200 windows, Bear entry over 1.18; Furor rank 5: Bear entry under 10, Bear lo over at most 4.99 (Deviation 16) | report; Bear rage never over (over windows 0, entry over <= 1.3) |
| Enrage decay (4 x 20) | matched pairs 0, but seed 15 at -2 in both (Deviation 13); declared over decaying: up to +7.5; none over pausing: down to -9.5 | matched within 1.25 (one fight in 20 may lose one tick, >= -2); signs asserted |

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 138 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      632 successes / 0 failures / 0 errors / 0 pending (about 160 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual src/Hekili/Engine src/Hekili/State.lua tests/Virtual | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|bear|cat|feral|maul|enrage|furor|shred|rake|rip|swipe|lacerate|bite|cat_form|bear_form|shifting_power|stance'
#                                                               # [empty: the boundary]
```

- [ ] **Step 6: Commit**

```bash
git add Makefile tests/Forever/helpers/druid_vs.lua tests/Forever/helpers/druid_world.lua \
  tests/Forever/druid_harness_spec.lua tests/Forever/druid_spec.lua
git commit -m "test(druid): the Druid in the combat harness: the mapping read from the class file, solo bear, solo cat, the shift fight, the Furor variants and Enrage's decay pause; a tenth of the fights in make check, the design's counts behind make test-druid (GCD kinds design §3-§4, D4-D6, D9)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin gcd-kinds`

---
### Task 5: The spec's "As built" section; CHECKPOINT G1-G8 in game, deferred to the user

Spec §6, D9. The documentation step is the commit; the checkpoint is not a blocker: the branch can be reviewed and merged with it open.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md` (§9 As built: the deviations that change the spec's text and the measured table)

**Interfaces:**
- Consumes: Tasks 1-4 (their measured numbers).
- Produces: the spec's §9.

- [ ] **Step 1: Write the section**

```bash
git apply <<'PATCH'
diff --git a/docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md b/docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md
index 19e40a82..1695655f 100644
--- a/docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md
+++ b/docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md
@@ -302,3 +302,39 @@ Bear (the calibration absorbs them, as the class file's shortcut says).
 ## Decisions (accepted as recommended 2026-10-16, controller under the user's standing approval)
 D1-D9 as recommended. Sequencing: this spec's plan runs AFTER the headless recommendation loop plan (it reuses that
 plan's press and usability pieces, D8); the in-game checkpoint G1-G8 needs a Druid character and is the user's.
+
+## 9. As built (2026-10-17)
+Where §1-§7 and the code differ, this table rules ("Deviation n" is the plan's,
+`docs/superpowers/plans/2026-10-17-gcd-kinds-and-druid-scenarios.md`).
+
+| Topic | Spec text | As built | Source |
+|---|---|---|---|
+| The opener's window (§1.2 item 3) | within `GCD_EDGE` of the edge | measured from the edge's own time; the quantised `gcdStart` is up to 2^-11 s later, and an edge-first claim at an off-grid time failed against it | Deviation 2 |
+| The fake spec's kinds (§1.6) | two abilities in `fake_spec` | opt-in, `fs.new(swingValue, true)`: in every fake spec they moved the adapter's tracked counts and the flag count | Deviation 1 |
+| E10 (§1.4) | in energy, `execute` only | as proposed; the clause's line comments `-- Forever E10:` without a class name; `docs/forever-facade-notes.md` has the row | Task 2 |
+| Resources (§2.1) | `res = { [pt] = { cur, max } }`, `power` an alias | `power` stays the swing-paid type's value (`e.pt`); `res` holds the others | Deviation 4 |
+| Press fields (§2.1) | `points = 1 \| "all"` | `points = { pt, 1 \| "all" }`; `aura.tick` has named fields `{ pt, every, amount }`; `gcd = 0` is off the GCD | Deviation 5 |
+| Regen (§2.2) | continuous | a "regen" gain every `regenTick` (0.1 s), capped; it runs in every form (UNMEASURED), so Furor's Cat restore equals keep | Deviation 6 |
+| Shift (§2.2) | set piece / press | a press field and `W.shift` only: the shifts respect the GCD | Deviation 7 |
+| The old worlds (§2.5) | the new draws move fights, re-measure | nothing moves: the GCD order has its own generator (`W.grng`), every new behaviour is knob-gated and the attack speed read is behind `k.playerSpeed`; nine streams byte-identical before and after, so the harness design's §9 tables stand | Deviation 3 |
+| Boundary (D7) | `tests/Virtual/harness` in `CORE` | with its captured logs (`fixtures/`) skipped (their numbers are times and amounts), four WoW global names allow-listed, two test IDs that collided with content IDs changed | Task 3 |
+| Fight counts (§4.6, §4.7) | in `make check` | a tenth of each in `make check` (`#slow`, about 19 s); the design's counts behind `make test-druid` (`#druid`, about 192 s) | Deviation 10 |
+| Bear drift (§4.6) | overshoot windows 0 | windows a step over that end with the belief above the truth: 0; all windows a step over: 4 of 2400, each a window that starts with the belief 17 below the truth and a Maul's 15 clamped at 0 | Deviation 11 |
+| Rage after a Bear entry (§4.6) | 0 | believed minus true at the first tick after the entry <= 1.3 (a swing landing after the entry pays both, at the calibrated scale): measured 0.84 | Deviation 12 |
+| Decay, matched (§4.5) | within 1.25 every second | the change since 1.5 s after the stop (our last swings landed) within 1.25, but one fight in 20 (seed 15) that loses Enrage's expiry tick (2) in both pairs, below the truth: a VirtualState finding, its own change | Deviation 13 |
+
+Measured (the design's fight counts, `make test-druid`):
+
+| Scenario (fights) | Measured | Gate |
+|---|---|---|
+| Solo bear (200) | main 6000/6047 (.992), wrong 0, false wounds 0; drift windows ending over 0 (raw 4/2400); danger 0; Mauls 1936: 1936 `SPELL_DAMAGE`/`SPELL_MISSED` rows, 1936 paid; crits 920, staged 920, on a non-crit 0; GCDs 2067 seen at their start, end error 0.0004 s, ownerless 0 (orders 1043 / 1024) | main >= .94, wrong 0, false 0, drift 0, danger 0, every Maul one row and paid once, staged >= 94% and 0 false, GCD |
+| Solo cat (200) | rage error 0; energy mean abs 1.78, max 40.0 (the pull), over windows 0/2600; points exact 226603 of 226603 settled ticks; GCDs 8407, end error 0.0004 s, ownerless 0 (orders 4193 / 4214); white pairing at 1.0 s: main .912 | rage 0; energy mean <= 10, over <= 2%; points 100%; GCD (within 0.01 s, ownerless 0, both orders) |
+| Solo cat, `regenAfter` 5 s x 1.25 (100) | energy mean abs 2.41 after 20 s, over 0/1100 | mean <= 15, over <= 5% |
+| Solo cat, a /reload in combat (50) | energy mean abs 11.4, over 0/650 | report |
+| Shift fight (100) | Bear sections main 1680/1719 (.977), false wounds 0 in both; timing alone: 1719/1719 in Bear, 0/4670 in Cat; Bear rage over windows 0 (lo over the truth at most 1.26), mean abs 2.92; every swing the belief paid 8.65 (before D4: every one 3.46, mean abs 3.94, entry under by up to 5.08); entry over 0.84, under -7.31; energy mean abs 0.28; GCDs 3036, ownerless 0 | Bear main >= .85; false 0; unknown 0 / 1; rage over 0 and every swing 8.65; entry over <= 1.3; GCD |
+| Furor: Cat entry zero (50) | energy error at each Cat entry 99, within 5 after 35.7 s on average (the fight's end if never); energy over windows 200; Bear rage over 0, entry over 1.18 | report; Bear never over |
+| Furor rank 5 (50) | Bear entry under by 10 (the truth's chance, the belief's 0), lo over the truth at most 4.99 (below a swing), over windows 0 | report; Bear never over |
+| Enrage decay (4 x 20) | matched: errors 0 but seed 15 at -2 in both pairs; declared over a decaying truth: up to +7.5 (6 quanta: the dangerous sign); none over a pausing truth: down to -9.5 (the safe sign) | matched within 1.25 (one lost tick allowed); signs asserted |
+
+D4 confirmed by the harness (the stale 1.0 s base priced every Bear swing at 3.46 through the shift fight); D5 stands:
+a wrong `pausesDecay` overshoots, its absence undershoots.
PATCH
```

- [ ] **Step 2: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 138 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      632 successes / 0 failures / 0 errors / 0 pending (about 160 s)
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff forever -- src/Hekili/Virtual src/Hekili/Engine src/Hekili/State.lua tests/Virtual | grep '^+' \
  | grep -iwE 'warrior|druid|rogue|hunter|paladin|shaman|mage|warlock|priest|bear|cat|feral|maul|enrage|furor|shred|rake|rip|swipe|lacerate|bite|cat_form|bear_form|shifting_power|stance'
#                                                               # [empty: the boundary]
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-10-16-gcd-kinds-and-druid-scenarios.md
git commit -m "docs(spec): GCD kinds and Druid scenarios: as built (the deviations and the gates' measurements)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 4: Point the client at the branch** (when the user is ready to play)

```bash
git push origin gcd-kinds
git -C ~/src/hekili checkout --detach gcd-kinds
```

Then `/reload` in game (no new file).

- [ ] **Step 5: CHECKPOINT: ask the user to run the following in game and paste each answer**

A Druid of level 20 or more with Cat Form, ForeverProbe loaded (`VSCopy`, `/vscopy` reopens it; S = secret), open-world mobs (no dummies). A two-line entry is a macro (the `/cast` line, then the `/run` line). Every line is under 255 characters (G3's `/run` is 253).

| # | Question | Line | Answer -> action |
|---|---|---|---|
| G1 | a spell-kind GCD from Cat (E10) | out of combat in Cat: `/cast Bear Form`, then `/run C_Timer.After(.1,function() local c=C_Spell.GetSpellCooldown(29515) VSCopy(c.startTime,c.duration) end)` | 1.5 -> E10 lands; 1.0 -> keep the stock line, reopen §1.2 |
| G2 | the totem and caster lengths out of combat | the G1 macro with `/cast Shifting Power` in Cat, then with `/cast [@player] Mark of the Wild` in caster form | 1.0 and 1.5 -> none; otherwise the kind's default changes |
| G3 | edge order and in-combat lengths | `/run local f=CreateFrame("Frame")f:RegisterEvent("SPELL_UPDATE_COOLDOWN")f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player")f:SetScript("OnEvent",function(_,e,a,_,c)VSCopy(format("%.3f",GetTime()),e,a,c,C_Spell.GetSpellCooldown(29515).isActive)end)`, then Shred x3, Bear Form, Maul, Swipe on a mob | success and rising edge within 0.1 s either way -> `GCD_EDGE` stands; wider -> the measured max + 50 ms; edge spacing 1.0 / 1.5 -> the kind windows stand |
| G4 | the belief after the build | in combat after Shreds: `/cast Bear Form`, then `/run C_Timer.After(.1,function() local s,d=Hekili.VirtualState.GcdInfo(GetTime()) VSCopy(format("%.3f %.3f",s,d)) end)`; again with `/cast Shred` after Cat Form | 1.500 and 1.000 -> none; the old learned length -> report |
| G5 | learned per kind | after G4: `/run VSCopy(Hekili.VirtualState.Snapshot():match("cast ab=[^\n]*"))` | `learned=` near 1.5/1.0 -> none |
| G6 | form speeds and the stale base (D4) | out of combat in each form: `/run VSCopy(GetShapeshiftForm(),UnitAttackSpeed("player"),GetMeleeHaste())`; after a Cat pull, in Bear in combat: `/run local V=Hekili.VirtualState VSCopy(V.SwingBase(1),issecretvalue(UnitAttackSpeed("player")),GetShapeshiftForm())` | Cat 1.0, Bear 2.5, base 1.0 in combat -> D4 confirmed; base 2.5 -> the speed read is live in combat, D4 unneeded |
| G7 | Enrage and the decay (refines Q9) | out of combat in Bear at 0 rage: `/cast Enrage`, then `/run C_Timer.After(10.5,function() VSCopy(C_Spell.IsSpellUsable("Swipe"),C_Spell.IsSpellUsable("Maul")) end)`, and watch the bar | Swipe usable (about 30) -> paused: `pausesDecay = true` on `enrage`; Maul only (about 17) -> stays absent; Enrage refused out of combat -> press it 2 s before the last mob dies and read the bar |
| G8 | resources after shifts (with Q3, Q10) | in combat after Cat -> Bear -> Cat: `/run local V,t=Hekili.VirtualState,GetTime() VSCopy(V.Power(1,t).est,V.Power(3,t).est,V.Power(4,t).est,GetComboPoints("player","target"))` against the bars | rage 0 on Bear entry, energy as the bar, points equal -> none; otherwise the Furor variant the bars show -> the matching `onEnter` becomes the class's model |

When the session ends: `git -C ~/src/hekili checkout --detach forever`.

---

## Self-Review

**1. Coverage of the spec**

| Spec | Task |
|---|---|
| §1.1 facts | "The current code" |
| §1.2 items 1-5 (kinds, `I.GcdLen`, the opener and claim, learning per kind, Snapshot) | 1 (Deviation 2) |
| §1.3 adapter forwarding (none new; pinned) | 1 (adapter_spec) |
| §1.4 E10 | 2 (Steps 7-12), D3 |
| §1.5-§1.6 owns and tests (fake_spec, casts, now, druid_spec, engine_load_spec, alloc) | 1, 2 (Deviations 1, 14, 15) |
| §2.1 entities and behaviours (`res`, `formSpeed`, `gcdUntil`, `payIn`, `critRage`, the press fields, the GCD refusal) | 3 (Deviations 4-5) |
| §2.2 the world (regen, `regenAfter`, decay with `pausedBy`, the GCD's events and order, `shift`) | 3 (Deviations 3, 6-7) |
| §2.3 the observer's rows | 3 (observer_spec, one case per row) |
| §2.4 drive and metrics | 3 (metrics_spec), 4 (the gates read them) |
| §2.5 the old gates at their bounds, alloc unchanged | 3 (Deviation 3) |
| §3 the Druid content, `druid_vs.lua`, D7 | 4 (Deviations 8-9), 3 (D7) |
| §4.1-§4.5 scenarios | 4 |
| §4.6 gates, D9 | 4 (Deviations 11-13, 16) |
| §4.7 owns and tests, the runtime split | 4 (Deviation 10) |
| §5 order (G1 before E10) | 2's separate commit, 5's G1 |
| §6 checkpoint | 5 |
| §7 decisions, "Decisions (accepted)" | "Decisions as built" |
| §8 out of scope | "Deliberately not built" |

**2. Placeholder scan:** no "TBD", "TODO", "implement later" or "similar to Task N"; every code step is a `git apply` patch from the replay, and every test step states its measured busted counts.

**3. Names across tasks:** spelled the same in every task and in the checkpoint:
- Core: `I.ab.gcdKind`, `I.GcdLen`, `I.GCD_EDGE`, `I.gcdLearned`, `I.gcdOwner`, `I.gcdKindLast`, `I.gcdRead`, `VS.GcdInfo`, Snapshot `learned=`/`owner=`; `fs.SPENDER_T`, `fs.SPENDER_U`, `fs.new(swingValue, kinds)`
- Druid: `BEAR_SWING`, `BEAR_RAGE_RATE`; E10's `-- Forever E10:`
- Harness: `W.res`, `W.effects`, `W.shift`, `W.regenRate`, `W.startRegen`, `W.startDecay`, `W.grng`, `W.rates`, `e.pt`, `e.res`, `e.res0`, `e.gcdOrder`, `e.gcdLatency`, `p.payIn`, `p.critRage`, `k.plainPower`, `k.powerTokens`, `k.regenRead`, `k.playerSpeed`, `k.forms`, `@regen`, `@attackSpeed`, `@forms`, `c.trk`, `c.gcdS`, `c.crit3`, `c.unk`, `metrics.power`, `metrics.gcd`, `metrics.unknown`, `metrics.crits`, `metrics.truthOf`
- Content: `druid_vs.boot`, `druid_world.fight`, `fights`, `SCENARIOS`, `rules`, `press`, `script`, `make test-druid`

**4. Review Focus:** each line has its pinned tests (named in Review Focus 1-5).

**Concerns for the orchestrator:**
- (a) `make check` grows to about 3 minutes (busted about 161 s, from about 140 s): the Druid gates' tenth is about 19 s; the design's counts are behind `make test-druid` (about 192 s), not in `make check` (Deviation 10).
- (b) Four bounds are set as built after a diagnosis (Deviations 11-13, 16): the reviewer should check each diagnosis (the floor at 0 in the drift windows, the swing landing after a Bear entry, seed 15's lost expiry tick, the Furor report) rather than accept the numbers.
- (c) Two VirtualState findings come out of the scenarios and are not fixed here (Deviations 13, 16): Enrage's expiry tick lost against the decay's first quantum in one fight in 20, and a slow correction of an energy belief that sits above the truth after a mismatched entry rule.
- (d) E10 changes a stock file; G1 decides it. The commit is separate so `git revert` of it alone restores the stock line (only its own engine case then fails, by design).
- (e) The harness's truths for the Druid are Classic's or UNMEASURED where the spec says so (form periods, the paws' damage, energy regen in every form, the GCD flag's order, the strikes' amounts); the gates score the belief against them, not the game.
