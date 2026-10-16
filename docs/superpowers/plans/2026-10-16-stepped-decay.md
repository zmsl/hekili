# Forever Stepped Decay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Out of combat a resource with a `decayInterval` loses `decay x decayInterval` in quanta (front-loaded): the first quantum at once when the decay starts, then one at the start of each interval. The decay starts at a combat end, at the last tick-paying aura's expiry, or when the estimate rises above rest. A periodic aura's tick at its expiry lands again, and it is credited before a quantum at the same instant. So Bloodrage, then Battle Shout, ends the buff at 10 - 1.25 = 8.75, never 10. Hekili's sim gets the same decay as a generated regen-model entry `__decay` whose beats are the belief's. Both halves of the 2026-10-16 tick-at-expiry hack (2dd4902a: `I.TICK_EPS`, core edit E6) are reverted.

**Architecture:**
- **Task 1 (belief):** Families/Resources.lua:
  - adds `R.decayIv[r]` (seconds per quantum, 0 = continuous) and `R.decayNext[r]` (the next quantum's time, 0 = inactive);
  - adds `decayFrom(r, from, to)` (the R5 pause scan, factored out of OnAdvance) and `beat(r, t)` (one quantum);
  - OnAdvance runs beats after the aura ticks; CombatStart zeroes `decayNext`; CombatEnd beats at once;
  - adds `VS.DecayAnchor(pt)`.

  The Adapter forwards `meta.decayInterval`. `auraGain` loses the TICK_EPS clamp and VirtualState.lua loses `I.TICK_EPS`.
- **Task 2 (sim):** Adapter.lua generates `model.__decay` once per regen model at a build. The walk skips that name. State.lua's E6 line goes back to `expires < e.next`.
- **Task 3 (class data and docs):** `decayInterval` on the Warrior's and the Druid's rage, the Bloodrage comments back to ten ticks, forever-facade-notes "Periodic auras" rewritten, the design's status set to implemented.
- **Task 4:** the in-game CHECKPOINT (design §5), deferred to the user.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, StyLua, `make check` (Makefile: lint, fmt-check, typecheck, test, syntax, api-check).

**Spec:** `docs/superpowers/specs/2026-10-16-stepped-decay-design.md` (binding). Every deviation is below with its evidence. Task 3 copies them into the design's status line.

### Deviations from the design (each measured or read, not guessed)

1. **`decayInterval` is a function in the class files**, `decayInterval = function() return 1 end`, not `= 1`.
   - Engine/Spec.lua:181-183 runs `setfenv( func, state )` on every meta field. For a number that is `setfenv(1, state)`, which re-envs RegisterResource itself.
   - Measured in the replay worktree: a numeric `decayInterval = 1` in Warrior.lua makes `tests/Forever/engine_load_spec.lua` fail for every Warrior race with `Engine/Spec.lua:182: stub state lacks "setfenv"`.
   - Resources.lua and the Adapter evaluate either form.
2. **The `__decay` entry is generated in Virtual/State/Adapter.lua, not Engine/Spec.lua.**
   - Spec.lua is upstream (`.styluaignore`), so an edit there would be a new named core edit. The constraints allow only the E6 revert.
   - The Adapter is ours. Its `buildDef` already walks `regenModel` and `meta` at every build, with Hekili's `state` and `VS` in scope.
   - `class.resources[k].state` is the same table as `state[k]` (Spec.lua:2039-2041), so the forecast (State.lua:1215 `r.regenModel`) sees the entry.
3. **The sim pauses in `last()`, not `stop()`.**
   - State.lua:1258-1263 evaluates `e.stop(...)` and on true does `table.remove( events, 1 )`: the entry is gone for the rest of the forecast. `state.buff.x.up` also reads the sim's query time, not the event's time.
   - Design §3.3's "`stop()` true while a tick aura is up" would therefore delete the decay for the whole forecast during Bloodrage. The forecast would show 10 flat after the buff: the Rend countdown the checkpoint must not show.
   - So `stop()` is `state.time > 0` only. `last()` returns, in order:
     - the latest expiry of a tick-paying player aura up in the sim, minus the interval (the first quantum at that expiry);
     - else the belief's `VS.DecayAnchor`;
     - else `state.query_time - iv`, a quantum at the forecast's start. This is harmless at rest, which is the only out-of-combat case where the belief is inactive with no aura.
   - The entry also carries `resource = <key>`: State.lua:1307 writes `remains[ e.resource ]`, and a nil key raises.
4. **Test 7 lives in `tests/Virtual/State/adapter_spec.lua`.**
   - `tests/Forever/warrior_spec.lua` loads the class through a recording stand-in (helpers/load_warrior.lua) that never runs the Adapter, so it cannot see a generated entry.
   - warrior_spec keeps the class-data assertion (Task 3) and loses the E6 source-text assertion (Task 2).
5. **No `R.decayStep` array:** `beat` computes `R.decay[r] * R.decayIv[r]`, because the decay is re-read at each combat end anyway.
6. **No default `decayInterval = 1` when `decay` is set.** Design §3.1 says both "default 1" and "nil keeps today's behaviour". The second wins, because test 4 requires the existing continuous cases (`decay = 2`, no interval) to keep their numbers. Warrior and Druid declare it explicitly.
7. **"A build out of combat"** needs no build-time code: a build seeds the estimate at rest (Resources.lua OnBuild). The first rise above rest out of combat anchors the decay at the next advance's `from`, the rise's clock (Task 1, test "starts from a rise above rest").

## How this plan was checked

Replayed, not hand-derived. A throwaway worktree at `71514780` was bootstrapped with `make bootstrap` (20 s) and used as follows:
- The patches below were produced there with `git diff` between the task states.
- They were then re-applied with `git apply` from a clean `71514780`, in this plan's order.
- The full suite ran after every test step and every implementation step. `make check` ran after every task.
- The final tree equals the one built by hand (`2b418fbb`).
- The throwaway was removed afterwards. Nothing was committed anywhere.

Measured counts (full suite, `busted`):

| State | Result |
|---|---|
| base `71514780` | 420 successes / 0 / 0 / 0 |
| T1 tests only | 416 successes / 5 failures / 4 errors |
| T1 green | 425 / 0 / 0 / 0 |
| T2 tests only | 423 successes / 1 failure / 1 error |
| T2 green | 425 / 0 / 0 / 0 |
| T3 tests only | 423 successes / 0 failures / 2 errors |
| T3 green | 425 / 0 / 0 / 0 |

`make check` passed (exit 0) at T1, T2 and T3:
- luacheck: 0 / 0 in 104 files
- lua-language-server: no problems
- api-check: ok in 65 loaded files; inventory diff empty

The patches are LF and StyLua-clean (`stylua --check` on every touched file of ours).

## Global Constraints

- **Worktree.** Repository `~/src/hekili`, existing worktree `~/src/hekili/.claude/worktrees/forever-stepped-decay` on branch `forever-stepped-decay` at `71514780`. That commit is forever `2dd4902a` plus the design commit.
  - Git from WSL only.
  - After each task's green verification and clean review, the orchestrator pushes the branch (`git push origin forever-stepped-decay`). Never push to `forever` or any other branch; never force-push. No task merges.
- **Commits.** Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. An implementer on another model uses its own model's name.
- **Zero allocation per frame.** `R.decayIv`/`R.decayNext` are preallocated arrays, and `decayFrom`/`beat`/`VS.DecayAnchor` do scalar arithmetic only. The `__decay` entry and its closures are built once per regen model at a build; its functions iterate with `pairs` and allocate nothing. Tests: `alloc_spec` (combat cycles, `VS.DecayAnchor`, the entry's `last`/`stop`/`value`) and resources_spec's own 2000-step cycle, both 0 bytes.
- **No class names in the engine.** Resources.lua and Adapter.lua read the declarative `decay`, `decayInterval`, `aura`, `swing` and `debuff` fields only. "Bloodrage" appears only in Resources.lua's existing explanatory comment, moved unchanged into `decayFrom`.
- **Every game read through the facade.** No new game API read. The entry reads Hekili's `state` (sim state), not the game. `tools/api_inventory.txt` stays unchanged, and api-check's `git diff --exit-code tools/api_inventory.txt` stays empty.
- **Upstream files** are edited only as named core edits. The one here is the E6 revert in State.lua (Task 2), which removes the `-- Forever E6:` line; afterwards State.lua is byte-identical to `340eff96`. Engine/Spec.lua is not touched (Deviation 2).
- **Style.** StyLua formats only our files (`.styluaignore` lists State.lua and Engine/Spec.lua). State.lua keeps Hekili's style. Each task runs `stylua` on its own files before verification.
- **Tools.** Run everything from the worktree root. The worktree has no `.lua/`, so pass the main checkout's: `make check LUA_ENV=$HOME/src/hekili/.lua`. Busted alone: `$HOME/src/hekili/.lua/bin/busted`.
- **Patches** are applied with `git apply` from the worktree root, in the order given. Each block is a heredoc, so copy it whole.
- **Verification block** at the end of every code task:

  ```bash
  make check LUA_ENV=$HOME/src/hekili/.lua
  #   lint:      Total: 0 warnings / 0 errors in 104 files
  #   fmt-check: (silent)
  #   typecheck: Diagnosis completed, no problems found
  #   test:      425 successes / 0 failures / 0 errors / 0 pending
  #   syntax:    (silent)
  #   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
  ```
- **The user runs the game.** The CHECKPOINT task stops execution:
  - The orchestrator, not a subagent, pushes the branch and runs `git -C ~/src/hekili checkout --detach forever-stepped-decay`.
  - It asks the user to run the exact lines given, and waits.
  - Lines copy their answers through `VSCopy(` (ForeverProbe). No new TOC file, so a `/reload` suffices.
  - When the session ends: `git -C ~/src/hekili checkout forever`.

## Review Focus

1. **Same-instant ordering: the tick, then the quantum.**
   - Belief: OnAdvance credits `auraGain` before its decay loop. `decayFrom` returns the in-window expiry as `start`, which re-anchors `decayNext` there, so the expiry's tick lands before the quantum at that instant (test 2: 8.75 at 20, `decayNext` 21).
   - Sim: Hekili's forecast keeps one point per instant (State.lua `forecast[ fcount ].t == now` reuses the slot), so the tick and the quantum at the expiry give 10 - 1.25 in either sort order.
   - Exception: a clamp. At 100, tick first gives 98.75; quantum first gives 99.75. A float drift of `applied + 10` past `expires` would drop the tick in the sim (`expires < now`), as before E6.
2. **Re-anchoring after a pause.**
   - A tick aura applied at a beat's instant pauses that beat (`applied <= to` and `expires > to`). Test 3: no beat at 13, `decayNext` 0.
   - Its expiry re-anchors regardless of the old phase (`start > from`).
   - An aura believed removed early (`exp0 = 0`) is no longer a pause, and the next advance anchors at its `from` through the rise rule.
   - Check that `decayFrom(r, t, t)` in CombatEnd sees an aura applied exactly at `t` as up.
3. **A build out of combat with the estimate above rest.**
   - The build seeds est at rest, so nothing beats at the build. Only CombatEnd beats synchronously.
   - Any later rise (a pin, a read, a shift, a swing) anchors at the next advance's `from`. Test 5 ("starts from a rise"): 18.75 at 6.5, `decayNext` 7.
   - `VS.Power` at the rise instant itself does not show that first quantum until the clock moves, and `VS.Power(now)` does not project beats between the clock and `now` (neither did the continuous mode).
4. **The sim's anchor when the belief has decay inactive.**
   - The anchor is `state.query_time - iv`: one quantum at the forecast's start, on a resource the belief holds at rest.
   - With a tick aura up in the sim (its own Bloodrage handler's `applyBuff`), the anchor is that expiry.
   - `stop()` is combat only (Deviation 3). A reviewer who "fixes" `stop()` to include the aura brings back the Rend countdown.
   - `resource = key` must stay (State.lua:1307).
5. **Continuous-mode regressions.**
   - `R.decayIv[r] == 0` takes the old code. The only change is that the pause scan moved into `decayFrom`, which returns `false` where the old loop set `d = 0`.
   - The existing continuous cases keep their numbers, apart from the TICK_EPS reverts (26 at 22, 10 at 25/30).
   - A meta with `decayInterval` but no `decay` generates no entry, and the belief's `decay` is 0.
   - A numeric `decayInterval` in a class meta table breaks Engine/Spec.lua (Deviation 1). Task 3's comment says so.

## File structure

```
src/Hekili/Virtual/State/Families/Resources.lua   T1  decayIv/decayNext, decayFrom, beat, OnAdvance beats, CombatStart/End,
                                                      VS.DecayAnchor; auraGain's TICK_EPS clamp reverted
src/Hekili/Virtual/State/VirtualState.lua         T1  I.TICK_EPS removed
src/Hekili/Virtual/State/Adapter.lua              T1  forwards meta.decayInterval
                                                  T2  DECAY, eval, decayEntry, the walk skips __decay, generation
src/Hekili/State.lua                              T2  E6 reverted (core edit removed)
src/Hekili/Forever/Classes/Warrior.lua            T3  decayInterval; Bloodrage comments back to ten ticks
src/Hekili/Forever/Classes/Druid.lua              T3  decayInterval
tests/Virtual/State/resources_spec.lua            T1  the 9-tick cases back to 10; "stepped decay" describe (tests 1-3, 5, 6)
tests/Virtual/State/alloc_spec.lua                T1  combat cycles + VS.DecayAnchor; T2 the entry's functions
tests/Virtual/State/adapter_spec.lua              T2  test 7 (the generated entry)
tests/Forever/warrior_spec.lua                    T2  E6 source-text case removed; T3 decayInterval()
tests/Forever/druid_spec.lua                      T3  decayInterval()
docs/forever-facade-notes.md                      T3  "Periodic auras" rewritten
docs/superpowers/specs/2026-10-16-stepped-decay-design.md   T3  status line
```

Deliberately not built (a review should not flag these):
- projecting beats between the clock and `now` in `VS.Power`;
- a default `decayInterval`;
- a snapshot field for `decayNext` (`VS.DecayAnchor` reads it);
- talent gates on the sim entry's aura scan (no tick aura of rage has one);
- moving `hi` to rest once the estimate rests (beats stop with the estimate, as the design's "est above rest" says).

---
### Task 1: The belief: stepped, front-loaded decay; the tick at the expiry lands again

Design §3.2, §3.4 (the Resources.lua/VirtualState.lua half), §4 tests 1-6 and 8.

**Files:**
- Modify: `src/Hekili/Virtual/State/Families/Resources.lua`, `src/Hekili/Virtual/State/VirtualState.lua`, `src/Hekili/Virtual/State/Adapter.lua`
- Test: `tests/Virtual/State/resources_spec.lua`, `tests/Virtual/State/alloc_spec.lua`

**Interfaces:**
- Consumes:
  - `def.resources[r].decay` (number or function, unchanged) and a new `def.resources[r].decayInterval` (number or function; nil/0 = continuous);
  - `G` (the aura-regen entries), `I.auras.applied/exp0[1]`, `I.Sample`, `Obs.CombatStart/CombatEnd`.
- Produces:
  - `I.res.decayIv[r]`, `I.res.decayNext[r]`;
  - `VS.DecayAnchor(powerType)` → the last quantum's time, 0 while inactive, continuous or untracked;
  - Adapter: `d.decayInterval = meta.decayInterval`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
index 2a40760f..7ae2d4ae 100644
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -1,7 +1,8 @@
 -- tests/Virtual/State/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
--- usability flipping on a health-gated spender, own casts, UNIT_AURA after a form swap, the target's UNIT_COMBAT) with
--- a drain every tick against the fake spec, every accessor and every facade policy and passthrough called, every
--- combat-log row delivered to a subscriber: VirtualState allocates nothing.
+-- usability flipping on a health-gated spender, own casts, UNIT_AURA after a form swap, the target's UNIT_COMBAT, combat
+-- ending and starting under a stepped rage decay) with a drain every tick against the fake spec, every accessor and
+-- every facade policy and passthrough called, every combat-log row delivered to a subscriber: VirtualState allocates
+-- nothing.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local fs = require("Virtual.State.helpers.fake_spec")
@@ -57,6 +58,14 @@ describe("zero allocation", function()
         sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
         h.Class.abilities.rend.healthGate = 0.2 -- a health-gated spender (Families/TargetHealth.lua)
         ctl.known[fs.REND] = true -- known: its NOT answers can bound the target's health
+        h.Class.resources.rage.state.meta = { -- a stepped decay (Families/Resources.lua): 1.25 at each 1 s beat
+            decay = function()
+                return 1.25
+            end,
+            decayInterval = function()
+                return 1
+            end,
+        }
         VS.Start(api)
         VS.SpecChanged()
         ctl.guid.target = "Creature-2" -- a target never held before: its first flip learns M, then WOUNDs move it
@@ -87,10 +96,16 @@ describe("zero allocation", function()
             else
                 ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 1)
             end
+            if i % 100 == 50 then
+                ctl.Fire("PLAYER_REGEN_ENABLED") -- out of combat: the rage decays on its beats
+            elseif i % 100 == 0 then
+                ctl.Fire("PLAYER_REGEN_DISABLED")
+            end
             ctl.Tick()
             VS.Drain(ctl.now)
             local t = ctl.now
             VS.Power(fs.RAGE, t)
+            VS.DecayAnchor(fs.RAGE)
             VS.Regen(fs.RAGE, t)
             VS.Cooldown(fs.REND, t)
             VS.Charges(fs.REND, t)
diff --git a/tests/Virtual/State/resources_spec.lua b/tests/Virtual/State/resources_spec.lua
index b150833b..10cc6bf2 100644
--- a/tests/Virtual/State/resources_spec.lua
+++ b/tests/Virtual/State/resources_spec.lua
@@ -320,11 +320,11 @@ describe("resources", function()
             I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
             I.Settle(15.5)
             assert.are.equal(5, VS.Power(fs.RAGE, 15.5).est) -- ticks at 11, 12, 13, 14, 15
-            assert.are.equal(9, VS.Power(fs.RAGE, 25).est) -- projected: 16 to 19; the tick at the expiry does not land
+            assert.are.equal(10, VS.Power(fs.RAGE, 25).est) -- projected: 16 to 20, none after the expiry
             I.Settle(25)
             local r = VS.Power(fs.RAGE, 30)
-            assert.are.same({ 9, 9 }, { r.est, r.lo })
-            assert.are.equal(9, I.res.pinDelta[1]) -- kept out of the next regen measurement
+            assert.are.same({ 10, 10 }, { r.est, r.lo })
+            assert.are.equal(10, I.res.pinDelta[1]) -- kept out of the next regen measurement
             assert.are.equal(1, I.res.auraRegen.n)
         end)
 
@@ -354,14 +354,14 @@ describe("resources", function()
             I.Settle(15)
             assert.are.equal(25, VS.Power(fs.RAGE, 15).est) -- 5 ticks, no decay
             I.Settle(22)
-            assert.are.equal(25, VS.Power(fs.RAGE, 22).est) -- 4 more ticks (none at the expiry), then 2 s x 2/s
+            assert.are.equal(26, VS.Power(fs.RAGE, 22).est) -- 5 more ticks, then 2 s x 2/s after the expiry
         end)
 
-        it("drops the tick at the expiry: a 10 s aura ticking 1 a second lands 9 (in game, 2026-10-16)", function()
+        it("lands the tick at the expiry: a 10 s aura ticking 1 a second lands 10", function()
             I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
-            assert.are.equal(5, VS.Power(fs.RAGE, 15).est) -- (10, 15]: before the expiry, unchanged
-            assert.are.equal(9, VS.Power(fs.RAGE, 20).est) -- (10, 20]: 11 to 19, not 20
-            assert.are.equal(9, VS.Power(fs.RAGE, 30).est) -- (10, 30]: nothing after it either
+            assert.are.equal(5, VS.Power(fs.RAGE, 15).est) -- (10, 15]: 11 to 15
+            assert.are.equal(10, VS.Power(fs.RAGE, 20).est) -- (10, 20]: 11 to 20, the expiry's tick too
+            assert.are.equal(10, VS.Power(fs.RAGE, 30).est) -- (10, 30]: nothing after it
         end)
 
         it("leaves decay at the full rate when the tick aura is down or already expired", function()
@@ -434,6 +434,112 @@ describe("resources", function()
             assert.are.equal(0, bytes)
         end)
     end)
+
+    describe("stepped decay (rage: 1.25 lost at the start of each 1 s window out of combat)", function()
+        local BLOODRAGE = 3 -- the aura index
+
+        before_each(function()
+            local def = fs.def(fs.new(9))
+            def.auras[BLOODRAGE] = { key = "bloodrage", id = 29131 }
+            def.auraIds[BLOODRAGE] = { 29131 }
+            def.resources[1].decay = 1.25
+            def.resources[1].decayInterval = function() -- a function, as a class file's meta table declares it
+                return 1
+            end
+            def.resources[1].auraRegen = { { aura = "bloodrage", interval = 1, value = 1 } }
+            boot(def)
+            S.Direct(Obs.CombatStart, 2)
+            I.Fold(2, false)
+        end)
+
+        -- 50 rage in combat from 2; the combat ends at 10.
+        local function combatEnd()
+            I.ResourceShift(1, 50, 2, Obs.CastSuccess)
+            I.Settle(10)
+            S.Direct(Obs.CombatEnd, 10)
+            I.Fold(10, false)
+        end
+
+        it("takes the first quantum at the combat end, then one at each window's start, down to rest", function()
+            combatEnd()
+            assert.are.equal(48.75, VS.Power(fs.RAGE, 10).est) -- at once
+            I.Settle(10.5)
+            assert.are.equal(48.75, VS.Power(fs.RAGE, 10.5).est)
+            I.Settle(11)
+            assert.are.equal(47.5, VS.Power(fs.RAGE, 11).est)
+            I.Settle(12.9)
+            local r = VS.Power(fs.RAGE, 12.9)
+            assert.are.same({ 46.25, 0, 96.25, "modelled" }, { r.est, r.lo, r.hi, r.basis }) -- beats at 10, 11, 12
+            assert.are.same({ 13, 12 }, { I.res.decayNext[1], VS.DecayAnchor(fs.RAGE) })
+            I.Settle(60)
+            assert.are.same({ 0, 0, 0 }, { VS.Power(fs.RAGE, 60).est, I.res.decayNext[1], VS.DecayAnchor(fs.RAGE) })
+        end)
+
+        it("lands Bloodrage's tenth tick at its expiry, then the first quantum at once: 10 - 1.25", function()
+            S.Direct(Obs.CombatEnd, 5)
+            I.Fold(5, false) -- at rest (0): no quantum
+            I.Settle(10)
+            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
+            I.Settle(15)
+            assert.are.same({ 5, 0 }, { VS.Power(fs.RAGE, 15).est, I.res.decayNext[1] }) -- paused while it is up
+            I.Settle(20)
+            assert.are.same({ 8.75, 21 }, { VS.Power(fs.RAGE, 20).est, I.res.decayNext[1] }) -- the tick, then the step
+            I.Settle(21)
+            assert.are.equal(7.5, VS.Power(fs.RAGE, 21).est)
+        end)
+
+        it("pauses for a tick aura applied while decaying and re-anchors at its expiry", function()
+            combatEnd()
+            I.Settle(12.5) -- 46.25: beats at 10, 11, 12
+            I.AuraModel(1, BLOODRAGE, 13, 23, 1, 12.5, 0) -- applied at 13, expires at 23
+            I.Settle(13)
+            assert.are.same({ 46.25, 0 }, { VS.Power(fs.RAGE, 13).est, I.res.decayNext[1] }) -- no beat at 13
+            I.Settle(18)
+            assert.are.equal(51.25, VS.Power(fs.RAGE, 18).est) -- ticks at 14 to 18
+            I.Settle(23)
+            assert.are.same({ 55, 24 }, { VS.Power(fs.RAGE, 23).est, I.res.decayNext[1] }) -- 19 to 23, then a step
+            I.Settle(24)
+            assert.are.equal(53.75, VS.Power(fs.RAGE, 24).est)
+        end)
+
+        it("stops at a combat start and front-loads again at the next combat end", function()
+            combatEnd()
+            I.Settle(11.5) -- 47.5
+            S.Direct(Obs.CombatStart, 11.5)
+            I.Fold(11.5, false)
+            assert.are.equal(0, I.res.decayNext[1])
+            I.Settle(20)
+            assert.are.equal(47.5, VS.Power(fs.RAGE, 20).est) -- no quantum in combat
+            S.Direct(Obs.CombatEnd, 20.5)
+            I.Fold(20.5, false)
+            assert.are.same({ 46.25, 21.5 }, { VS.Power(fs.RAGE, 20.5).est, I.res.decayNext[1] })
+        end)
+
+        it("starts from a rise above rest out of combat, and allocates nothing over combat cycles", function()
+            S.Direct(Obs.CombatEnd, 5)
+            I.Fold(5, false)
+            I.Settle(6)
+            I.ResourceShift(1, 20, 6, Obs.CastSuccess) -- out of combat, at the clock
+            I.Settle(6.5)
+            assert.are.same({ 18.75, 7 }, { VS.Power(fs.RAGE, 6.5).est, I.res.decayNext[1] }) -- the first beat at 6
+            local t = 10
+            assert.are.equal(
+                0,
+                alloc.bytes(function(i)
+                    t = t + 0.1
+                    if i % 50 == 0 then
+                        S.Direct(i % 100 == 0 and Obs.CombatEnd or Obs.CombatStart, t)
+                        I.Fold(t, false)
+                        I.ResourceShift(1, 30, t, Obs.CastSuccess)
+                    end
+                    I.Settle(t)
+                    VS.Power(fs.RAGE, t)
+                    VS.DecayAnchor(fs.RAGE)
+                end, 2000)
+            )
+        end)
+    end)
+
     describe("a resource resting at its maximum, and a fractional cost (mana, 0.55 of the maximum)", function()
         local MANA, FORM, BIG = 0, 1, 2
         local def
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `416 successes / 5 failures / 4 errors / 0 pending`.
- resources_spec (`37 / 4 / 4`) fails:
  - the three reverted aura-gated cases (TICK_EPS still drops the expiry's tick);
  - test 1 (48.75 expected, 50 at the combat end).
- resources_spec errors on tests 2, 3, 5 and the rise/alloc case (`decayNext` nil).
- alloc_spec fails: `attempt to call field 'DecayAnchor' (a nil value)`.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/State/Adapter.lua b/src/Hekili/Virtual/State/Adapter.lua
index b2a7f165..66299d16 100644
--- a/src/Hekili/Virtual/State/Adapter.lua
+++ b/src/Hekili/Virtual/State/Adapter.lua
@@ -149,6 +149,7 @@ local function buildDef()
             swingAura = swingAura,
             auraRegen = auraRegen,
             decay = r.state and r.state.meta and r.state.meta.decay, -- out-of-combat loss per second (Resources.lua)
+            decayInterval = r.state and r.state.meta and r.state.meta.decayInterval, -- seconds per quantum (stepped)
         }
         insert(def.resources, d)
         slotByKey[k] = #def.resources
diff --git a/src/Hekili/Virtual/State/Families/Resources.lua b/src/Hekili/Virtual/State/Families/Resources.lua
index 5b6b34fc..605618a4 100644
--- a/src/Hekili/Virtual/State/Families/Resources.lua
+++ b/src/Hekili/Virtual/State/Families/Resources.lua
@@ -56,6 +56,8 @@ local R = {
     regen = {},
     decayDef = {},
     decay = {},
+    decayIv = {},
+    decayNext = {},
     maxDef = {},
     maxMods = {},
     maxRead = {},
@@ -74,7 +76,10 @@ local fighting, fightT = false, 0
 R.auraRegen = G
 
 -- Slot r's out-of-combat loss per second from its `decay` (a number or a state-bound function; absent: none),
--- evaluated at the build and at each combat end (talent ranks change out of combat only). Allocates nothing.
+-- evaluated at the build and at each combat end (talent ranks change out of combat only). With a `decayInterval`
+-- (seconds, `decayIv[r]`; 0: continuous) it is lost in quanta of decay x interval, the first at once when the decay
+-- starts and one at the start of each interval after it (`decayNext[r]`: the next one's time, 0 while inactive;
+-- stepped-decay design §3.2). Allocates nothing.
 local function decayOf(r)
     local d = R.decayDef[r]
     if type(d) == "function" then
@@ -170,6 +175,8 @@ I.OnBuild(function(def, now)
         R.snapT[r], R.readT[r], R.readable[r] = -1e9, -1e9, false
         R.decayDef[r] = d.decay
         R.decay[r] = decayOf(r)
+        local iv = eval(d.decayInterval)
+        R.decayIv[r], R.decayNext[r] = type(iv) == "number" and iv > 0 and iv or 0, 0
         R.power[r] = I.NewBelief("power " .. tostring(d.key))
         R.regen[r] = I.NewBelief("regen " .. tostring(d.key))
         I.Sample(R.power[r], "default", R.rest[r], now, 0)
@@ -237,8 +244,7 @@ function I.SwingValue(r, hand)
 end
 
 -- What entry g brings in (from, to]: `value` at each `interval` after the player's aura was applied, up to its
--- believed expiry. A tick due at the expiry itself does not land (the removal wins; in game 2026-10-16, Bloodrage's ten
--- ticks give 9), so an aura-gated window stops TICK_EPS short of it. Allocates nothing.
+-- believed expiry. Allocates nothing.
 local function auraGain(g, from, to)
     local j, tid = G.aura[g], G.talent[g]
     if tid > 0 and VS.Talent(tid) == 0 then
@@ -257,8 +263,8 @@ local function auraGain(g, from, to)
         return 0
     end
     local iv = G.interval[g]
-    if j ~= 0 and to > e - I.TICK_EPS then
-        to = e - I.TICK_EPS
+    if to > e then
+        to = e
     end
     if from < ap then
         from = ap
@@ -269,8 +275,47 @@ local function auraGain(g, from, to)
     return (floor((to - ap) / iv) - floor((from - ap) / iv)) * G.value[g] -- nonzero: interval > 0 (checked at build)
 end
 
+-- No decay while a tick-paying player aura of slot r is up (Bloodrage: +1/s and no decay for 10 s, in game): false
+-- while one is up through `to`, else when in (from, to] the decay runs from (the latest expiry in it, or `from`).
+local function decayFrom(r, from, to)
+    local start = from
+    for g = 1, G.n do
+        local j, tid = G.aura[g], G.talent[g]
+        local learned = tid == 0 or VS.Talent(tid) ~= 0 -- auraGain's talent gate
+        if learned and G.slot[g] == r and j > 0 and I.auras.applied[1][j] <= to then
+            local e = I.auras.exp0[1][j]
+            if e > to then
+                return false
+            elseif e > start then
+                start = e
+            end
+        end
+    end
+    return start
+end
+
+-- One stepped decay quantum of slot r at t: the interval down by decay x interval, never below rest, as a `modelled`
+-- sample at t, kept out of the regen measurement; the next one an interval later, none once the estimate rests.
+local function beat(r, t)
+    local rest, step, before = R.rest[r], R.decay[r] * R.decayIv[r], R.est0[r]
+    if before > rest then
+        R.est0[r] = before - step > rest and before - step or rest
+    end
+    if R.lo0[r] > rest then
+        R.lo0[r] = R.lo0[r] - step > rest and R.lo0[r] - step or rest
+    end
+    if R.hi0[r] > rest then
+        R.hi0[r] = R.hi0[r] - step > rest and R.hi0[r] - step or rest
+    end
+    if R.est0[r] ~= before then
+        R.pinDelta[r] = R.pinDelta[r] + R.est0[r] - before
+        I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.CombatEnd)
+    end
+    R.decayNext[r] = R.est0[r] > rest and t + R.decayIv[r] or 0
+end
+
 -- Continuous regen between pins (swing-paid slots move only at swings), then aura-gated regen, kept out of the
--- regen measurement like our own casts' changes (pinDelta).
+-- regen measurement like our own casts' changes (pinDelta), then the decay: ticks before quanta at the same instant.
 I.OnAdvance(function(from, to)
     local dt = to - from
     for r = 1, R.n do
@@ -296,25 +341,20 @@ I.OnAdvance(function(from, to)
         return
     end
     -- Out of combat a decaying slot falls toward rest at its decay rate (never below it), kept out of the regen
-    -- measurement like the aura-gated ticks.
+    -- measurement like the aura-gated ticks; it resumes from a tick aura's expiry.
     for r = 1, R.n do
         local d = R.decay[r]
-        -- No decay while a tick-paying player aura is up (Bloodrage: +1/s and no decay for 10 s, in game); it
-        -- resumes from the aura's expiry.
-        local start = from
-        for g = 1, G.n do
-            local j, tid = G.aura[g], G.talent[g]
-            local learned = tid == 0 or VS.Talent(tid) ~= 0 -- auraGain's talent gate
-            if d > 0 and learned and G.slot[g] == r and j > 0 and I.auras.applied[1][j] <= to then
-                local e = I.auras.exp0[1][j]
-                if e > to then
-                    d = 0
-                elseif e > start then
-                    start = e
-                end
+        local start = d > 0 and decayFrom(r, from, to)
+        if R.decayIv[r] > 0 then
+            if not start then
+                R.decayNext[r] = 0
+            elseif start > from or R.decayNext[r] == 0 and R.est0[r] > R.rest[r] then
+                R.decayNext[r] = start -- it starts: at a tick aura's expiry, or at a rise above rest
             end
-        end
-        if d > 0 then
+            while R.decayNext[r] > 0 and R.decayNext[r] <= to do
+                beat(r, R.decayNext[r])
+            end
+        elseif start then
             local rest, drop, before = R.rest[r], d * (to - start), R.est0[r]
             if before > rest then
                 R.est0[r] = before - drop > rest and before - drop or rest
@@ -532,11 +572,14 @@ end)
 
 I.On(Obs.CombatStart, function(o, t)
     fighting, fightT = true, t
+    for r = 1, R.n do
+        R.decayNext[r] = 0
+    end
 end)
 
 -- Out of combat a resource falls toward its rest value: the interval opens down to it (lo never over-promises), and
--- a decaying slot's rate is re-read.
-I.On(Obs.CombatEnd, function()
+-- a decaying slot's rate is re-read; a stepped one loses its first quantum at once (front-loaded).
+I.On(Obs.CombatEnd, function(o, t)
     fighting = false
     for r = 1, R.n do
         R.decay[r] = decayOf(r)
@@ -547,6 +590,10 @@ I.On(Obs.CombatEnd, function()
             R.lo0[r] = R.rest[r]
         end
         R.pinValid[r] = false
+        local stepped = R.decayIv[r] > 0 and R.decayNext[r] == 0 and R.decay[r] > 0
+        if stepped and R.est0[r] > R.rest[r] and decayFrom(r, t, t) then
+            beat(r, t)
+        end
     end
 end)
 
@@ -599,6 +646,14 @@ function VS.Power(powerType, now)
     return rec
 end
 
+--- (stepped-decay design §3.3) The time of a power type's last stepped decay quantum, the anchor of the sim's
+--- `__decay` entry (Adapter.lua): 0 while its decay is inactive or continuous, or the type untracked. Allocates nothing.
+function VS.DecayAnchor(powerType)
+    local r = R.slotOf[powerType]
+    local n = r and R.decayNext[r] or 0
+    return n > 0 and n - R.decayIv[r] or 0
+end
+
 --- (spec §3.2) The believed regen per second of a power type. A swing-paid resource's is its calibrated step per
 --- second of swinging. `casting` selects the in-cast rate (Phase 1 has one rate). Allocates nothing.
 function VS.Regen(powerType, now, casting)
diff --git a/src/Hekili/Virtual/State/VirtualState.lua b/src/Hekili/Virtual/State/VirtualState.lua
index 31096250..8f44e135 100644
--- a/src/Hekili/Virtual/State/VirtualState.lua
+++ b/src/Hekili/Virtual/State/VirtualState.lua
@@ -68,7 +68,6 @@ I.REGEN_SPREAD = 0.1
 I.REGEN_SPREAD_MIN = 0.02
 I.REGEN_RATIO = 2
 I.EPS = 0.01
-I.TICK_EPS = 0.001 -- a periodic tick due at its aura's expiry does not land (Resources.lua auraGain)
 I.CD_PROBE = 0.5
 I.SNAP_HOLD = 1
 I.AURA_HALF_LIFE = 10
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `425 successes / 0 failures / 0 errors / 0 pending`. The existing continuous cases (`decay = 2`, no interval: design test 4) pass unchanged, apart from the reverted numbers.

- [ ] **Step 5: Verify**

```bash
stylua src/Hekili/Virtual/State/Families/Resources.lua src/Hekili/Virtual/State/VirtualState.lua \
  src/Hekili/Virtual/State/Adapter.lua tests/Virtual/State/resources_spec.lua tests/Virtual/State/alloc_spec.lua   # [no change]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 104 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      425 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
grep -rn TICK_EPS src tests                                   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/Families/Resources.lua src/Hekili/Virtual/State/VirtualState.lua \
  src/Hekili/Virtual/State/Adapter.lua tests/Virtual/State/resources_spec.lua tests/Virtual/State/alloc_spec.lua
git commit -m "feat(vs): stepped, front-loaded out-of-combat decay in the belief; a periodic aura's tick at its expiry lands again (stepped-decay design §3.2, §3.4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-stepped-decay`

---
### Task 2: The sim: the generated `__decay` regen entry; core edit E6 reverted

Design §3.3, §3.4 (the State.lua half), §4 test 7, as amended by Deviations 2-4.

**Files:**
- Modify: `src/Hekili/Virtual/State/Adapter.lua`, `src/Hekili/State.lua` (upstream: the E6 revert only)
- Test: `tests/Virtual/State/adapter_spec.lua`, `tests/Virtual/State/alloc_spec.lua`, `tests/Forever/warrior_spec.lua`

**Interfaces:**
- Consumes: `VS.DecayAnchor` (Task 1); Hekili's `state.time`, `state.query_time`, `state.buff[aura].up/expires`; the class's `meta.decay` and `meta.decayInterval`.
- Produces: `class.resources[k].state.regenModel.__decay`, a table with these fields:
  - `resource` = `k`;
  - `interval` = `meta.decayInterval` (as given; Hekili accepts a number or a function);
  - `value()` = `-decay x interval`;
  - `last()` (Deviation 3);
  - `stop()` = `state.time > 0`.

  Built only when `meta.decay` is set and `decayInterval` evaluates above 0, and only once per model. The walk forwards it to the belief as no regen entry.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/warrior_spec.lua b/tests/Forever/warrior_spec.lua
index 99582cf4..fa35626f 100644
--- a/tests/Forever/warrior_spec.lua
+++ b/tests/Forever/warrior_spec.lua
@@ -613,9 +613,4 @@ describe("Forever Warrior", function()
         assert.are.equal(2, n)
         assert.is_nil(src:find("IsSpellInRange( ability.rangeSpell or ability.id", 1, true))
     end)
-    it("the forecast drops an aura's periodic event at its expiry (core edit E6)", function()
-        local src = assert(io.open("src/Hekili/State.lua")):read("*a")
-        assert.is_truthy(src:find('state[ e.debuff and "debuff" or "buff" ][ e.aura ].expires <= e.next )', 1, true))
-        assert.is_truthy(src:find("-- Forever E6:", 1, true))
-    end)
 end)
diff --git a/tests/Virtual/State/adapter_spec.lua b/tests/Virtual/State/adapter_spec.lua
index c1969872..7e7fbfe9 100644
--- a/tests/Virtual/State/adapter_spec.lua
+++ b/tests/Virtual/State/adapter_spec.lua
@@ -127,6 +127,40 @@ describe("Adapter", function()
         assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
     end)
 
+    it("generates the sim's stepped decay entry, on the belief's beats and from a tick aura's expiry", function()
+        local model, rank = h.Class.resources.rage.state.regenModel, 0
+        model.bloodrage = { aura = "bloodrage", interval = 1, value = 1 }
+        h.Class.auras.bloodrage = { key = "bloodrage", id = 29131, duration = 10 }
+        h.Class.resources.rage.state.meta = {
+            decay = function()
+                return 1.25 * (1 - 0.3 * rank)
+            end,
+            decayInterval = function()
+                return 1
+            end,
+        }
+        VS.SpecChanged()
+        local e = model.__decay
+        assert.are.same({ "rage", 1, -1.25 }, { e.resource, e.interval(), e.value() })
+        rank = 1
+        assert.is_true(math.abs(-0.875 - e.value()) < 1e-9) -- Anger Management's 30% less
+        VS.SpecChanged()
+        assert.are.same({ e, 1 }, { model.__decay, I.res.auraRegen.n }) -- built once; not a regen entry of the belief
+        state.time, state.query_time, state.buff.bloodrage = 0, 4.5, { up = false, expires = 0 }
+        assert.are.same({ false, 3.5 }, { e.stop(), e.last() }) -- the belief at rest: a quantum at the forecast's start
+        state.time = 5
+        assert.is_true(e.stop()) -- in combat
+        I.Sources.Direct(VS.Obs.CombatStart, 1.5)
+        I.Fold(1.5)
+        I.ResourceShift(1, 50, 1.5, VS.Obs.CastSuccess)
+        I.Sources.Direct(VS.Obs.CombatEnd, 2)
+        I.Fold(2)
+        I.Settle(3.5) -- the belief's quanta at 2 and 3, the next at 4
+        assert.are.same({ 3, 3 }, { VS.DecayAnchor(fs.RAGE), e.last() }) -- the sim's next beat: 4, the belief's
+        state.buff.bloodrage = { up = true, expires = 20 }
+        assert.are.equal(19, e.last()) -- a tick aura up in the sim: the first quantum at its expiry, after its tick
+    end)
+
     it("forwards a regenerating resource's rest as a flag and a swing entry's `aura` as its gate", function()
         local got
         local build = I.Build
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
index 7ae2d4ae..5959cfd4 100644
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -68,6 +68,8 @@ describe("zero allocation", function()
         }
         VS.Start(api)
         VS.SpecChanged()
+        local decay = h.Class.resources.rage.state.regenModel.__decay -- the sim's (Adapter.lua), called as a forecast
+        state.time, state.query_time = 0, 1
         ctl.guid.target = "Creature-2" -- a target never held before: its first flip learns M, then WOUNDs move it
         ctl.Fire("PLAYER_TARGET_CHANGED")
         ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 1e9, applications = 0 }
@@ -106,6 +108,9 @@ describe("zero allocation", function()
             local t = ctl.now
             VS.Power(fs.RAGE, t)
             VS.DecayAnchor(fs.RAGE)
+            decay.last()
+            decay.stop()
+            decay.value()
             VS.Regen(fs.RAGE, t)
             VS.Cooldown(fs.REND, t)
             VS.Charges(fs.REND, t)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `423 successes / 1 failure / 1 error / 0 pending`. The suite holds 425 tests: warrior_spec loses its E6 case, and adapter_spec gains test 7.
- adapter_spec test 7 errors: `model.__decay` is nil.
- alloc_spec fails: `decay` is nil inside the measured step.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/State.lua b/src/Hekili/State.lua
index d62172f8..db0b4e85 100644
--- a/src/Hekili/State.lua
+++ b/src/Hekili/State.lua
@@ -1307,9 +1307,8 @@ do
                     remains[ e.resource ] = finish - e.next
                     e.next = e.next + step
 
-                    -- Forever E6: a tick due at the aura's expiry does not land (Bloodrage gives 9, not 10).
                     if e.next > finish or step < 0 or
-                       ( e.aura and state[ e.debuff and "debuff" or "buff" ][ e.aura ].expires <= e.next ) or
+                       ( e.aura and state[ e.debuff and "debuff" or "buff" ][ e.aura ].expires < e.next ) or
                        ( e.channel and state.buff.casting.expires < e.next ) then
                         table.remove( events, 1 )
                     end
diff --git a/src/Hekili/Virtual/State/Adapter.lua b/src/Hekili/Virtual/State/Adapter.lua
index 66299d16..c95ee886 100644
--- a/src/Hekili/Virtual/State/Adapter.lua
+++ b/src/Hekili/Virtual/State/Adapter.lua
@@ -69,6 +69,44 @@ local def = {
 }
 
 local HANDS = { mainhand = 1, offhand = 2 }
+local DECAY = "__decay" -- the generated entry's reserved name in a regen model
+
+local function eval(v)
+    if type(v) == "function" then
+        return v()
+    end
+    return v
+end
+
+-- The sim's stepped decay (stepped-decay design §3.3): a regen-model entry Hekili's forecast steps like a class's,
+-- `value` (negative, talent-scaled) every `interval`, never in combat. Its beats are the belief's (from its last
+-- quantum), or start at a tick aura's expiry while one is up in the sim: Hekili's forecast removes an entry whose
+-- `stop` holds, so the pause is in `last`, not `stop`. Built once per regen model, at a build.
+local function decayEntry(key, model, meta, powerType)
+    local e = { resource = key, interval = meta.decayInterval }
+    function e.value()
+        return -eval(meta.decay) * eval(meta.decayInterval)
+    end
+    function e.last()
+        local iv, up = eval(meta.decayInterval), 0
+        for _, m in pairs(model) do
+            local b = m.aura and not (m.swing or m.debuff) and state.buff[m.aura]
+            if b and b.up and b.expires > up then
+                up = b.expires
+            end
+        end
+        if up > 0 then
+            return up - iv -- with its last tick: State.lua keeps one point per instant, 10 - 1.25 in either order
+        end
+        local a = VS.DecayAnchor(powerType)
+        return a > 0 and a or state.query_time - iv -- the belief inactive: a quantum at the forecast's start
+    end
+    function e.stop()
+        return state.time > 0
+    end
+    return e
+end
+
 -- Point resources (a count, not a pool): a percentage maximum modifier does not apply to them.
 local POINTS = {
     combo_points = true,
@@ -120,12 +158,15 @@ local function buildDef()
         local swing, value, offValue, auraRegen, swingAura = 0, nil, nil, nil, nil
         local model = r.state and r.state.regenModel
         if model then
-            for _, m in pairs(model) do
+            for name, m in pairs(model) do
                 if m.swing == "offhand" then
                     offValue = m.value
                 elseif m.swing and HANDS[m.swing] and swing == 0 then
                     swing, value, swingAura = HANDS[m.swing], m.value, m.aura -- `aura`: swings pay only while it is up
-                elseif not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting) then
+                elseif
+                    name ~= DECAY
+                    and not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting)
+                then
                     auraRegen = auraRegen or {}
                     -- a player aura's regen { aura, interval, value }, or without `aura` a periodic one credited in
                     -- combat; either may name a `talent` (Resources.lua). Hekili's other gates are unseen here, so an
@@ -134,6 +175,11 @@ local function buildDef()
                 end
             end
         end
+        local meta = r.state and r.state.meta
+        local iv = meta and meta.decay ~= nil and eval(meta.decayInterval)
+        if model and type(iv) == "number" and iv > 0 and model[DECAY] == nil then
+            model[DECAY] = decayEntry(k, model, meta, r.type)
+        end
         if swing == 0 and offValue ~= nil then
             swing, value, offValue = 2, offValue, nil -- the off hand alone pays it
         end
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `425 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify**

```bash
stylua src/Hekili/Virtual/State/Adapter.lua tests/Virtual/State/adapter_spec.lua tests/Virtual/State/alloc_spec.lua \
  tests/Forever/warrior_spec.lua                              # [no change]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 104 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      425 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
git diff --exit-code 340eff96 -- src/Hekili/State.lua         # [no output: State.lua is as before E6]
grep -n "Forever E6" src/Hekili/State.lua                     # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/Adapter.lua src/Hekili/State.lua tests/Virtual/State/adapter_spec.lua \
  tests/Virtual/State/alloc_spec.lua tests/Forever/warrior_spec.lua
git commit -m "feat(sim): a generated __decay regen entry steps the forecast's out-of-combat decay on the belief's beats; core edit E6 reverted (stepped-decay design §3.3, §3.4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-stepped-decay`

---
### Task 3: Class data and docs: `decayInterval` on the Warrior's and the Druid's rage

Design §3.1, §3.4 (the Warrior.lua comments), §6 (the notes), and the status line.

**Files:**
- Modify: `src/Hekili/Forever/Classes/Warrior.lua`, `src/Hekili/Forever/Classes/Druid.lua`, `docs/forever-facade-notes.md`, `docs/superpowers/specs/2026-10-16-stepped-decay-design.md`
- Test: `tests/Forever/warrior_spec.lua`, `tests/Forever/druid_spec.lua`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: the rage meta `decayInterval = function() return 1 end` in both classes. Through Task 2 it yields a `__decay` entry for each.
- `tests/Forever/engine_load_spec.lua` keeps passing: it runs every meta function under the real Spec.lua's `state` and is the guard for Deviation 1.
- druid_spec's adapter-backed sequence runs with the generated entry present.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/druid_spec.lua b/tests/Forever/druid_spec.lua
index 8732b8b9..bd19bf39 100644
--- a/tests/Forever/druid_spec.lua
+++ b/tests/Forever/druid_spec.lua
@@ -607,6 +607,7 @@ describe("Forever Druid", function()
         w.state.buff.enrage, w.state.query_time = { applied = 10 }, 13.4
         assert.are.equal(13, models.enrage.last())
         assert.are.equal(1.25, w.resources[1].meta.decay())
+        assert.are.equal(1, w.resources[1].meta.decayInterval()) -- stepped, as the Warrior's
     end)
 
     it("declares energy with no regen model, combo points and mana with no maximum, in Classic's order", function()
diff --git a/tests/Forever/warrior_spec.lua b/tests/Forever/warrior_spec.lua
index fa35626f..48b17f6b 100644
--- a/tests/Forever/warrior_spec.lua
+++ b/tests/Forever/warrior_spec.lua
@@ -399,6 +399,7 @@ describe("Forever Warrior", function()
         assert.are.equal(1.25, decay())
         w.state.talent.anger_management.rank = 1
         assert.is_true(math.abs(0.875 - decay()) < 1e-9) -- 1.25 x (1 - 0.3 x 1) = 1.25 x 0.7 = 0.875
+        assert.are.equal(1, w.resource[4].decayInterval()) -- stepped: lost at the start of each 1 s window
     end)
 
     it("declares no rage maximum of its own: a Gnome's 105 is the race pack's Expansive Mind", function()
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `423 successes / 0 failures / 2 errors / 0 pending`: the Warrior's and the Druid's decay cases each call a nil `decayInterval`.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/docs/forever-facade-notes.md b/docs/forever-facade-notes.md
index 393706cb..85d60859 100644
--- a/docs/forever-facade-notes.md
+++ b/docs/forever-facade-notes.md
@@ -282,7 +282,9 @@ Every stub site in the retained files that throws or yields a wrong value. Sites
 
 ## Periodic auras
 
-- A periodic tick due at its aura's expiry does not land (2026-10-16, Warrior out of combat: Bloodrage's 10 s aura ticking 1 rage a second ends at 9, never 10). VirtualState's `auraGain` stops TICK_EPS short of the expiry; the sim's forecast drops an event at `expires <= e.next` (core edit E6, `State.lua`).
+- A periodic aura's ticks land in full, the one at its expiry too (Bloodrage: 10 ticks of 1 rage over 10 s). VirtualState's `auraGain` counts through the expiry; Hekili's forecast keeps its own `expires < e.next` (the 2026-10-16 core edit E6 is reverted).
+- Out-of-combat decay is stepped and front-loaded (`docs/superpowers/specs/2026-10-16-stepped-decay-design.md`): a class's meta table declares `decay` (per second) and `decayInterval` (seconds, a function: Engine/Spec.lua setfenv's every meta field). The quantum `decay x decayInterval` is lost at once when the decay starts (combat end, the last tick aura's expiry, a rise above rest) and at the start of each interval after it; a tick and a quantum at the same instant resolve tick first (Bloodrage, then Battle Shout, out of combat: the bar ends the buff at 10 - 1.25 = 8.75, shown 9). Without `decayInterval` a decay stays continuous.
+- The sim: the Adapter generates a regen-model entry `__decay` (`value` -quantum every `decayInterval`) whose beats are the belief's (`VS.DecayAnchor`), or start at a tick aura's expiry while one is up in the sim; `stop` in combat only, because Hekili's forecast removes a stopped entry for the rest of the forecast.
 
 ## Known reads outside the inventory
 
diff --git a/docs/superpowers/specs/2026-10-16-stepped-decay-design.md b/docs/superpowers/specs/2026-10-16-stepped-decay-design.md
index 9098615e..02a4ff06 100644
--- a/docs/superpowers/specs/2026-10-16-stepped-decay-design.md
+++ b/docs/superpowers/specs/2026-10-16-stepped-decay-design.md
@@ -1,6 +1,10 @@
 # Stepped, front-loaded resource decay (design, 2026-10-16)
 
-Status: approved direction (user, 2026-10-16: "assume my theory and build it into the model instead of hacking it").
+Status: IMPLEMENTED (belief, sim entry, class data); the in-game checkpoint (§5) is the user's. Deviations:
+`decayInterval` is a function in the class files (Engine/Spec.lua setfenv's every meta field); the sim entry is
+generated in Adapter.lua (Spec.lua is upstream) and pauses through `last()`, not `stop()` (Hekili's forecast removes a
+stopped entry for the rest of the forecast); its test is in adapter_spec, not warrior_spec.
+Direction: user, 2026-10-16: "assume my theory and build it into the model instead of hacking it".
 Base: forever 2dd4902a. Paths under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`.
 
 ## 1. The observation and the theory
diff --git a/src/Hekili/Forever/Classes/Druid.lua b/src/Hekili/Forever/Classes/Druid.lua
index 5a00e936..f2b1d992 100644
--- a/src/Hekili/Forever/Classes/Druid.lua
+++ b/src/Hekili/Forever/Classes/Druid.lua
@@ -204,6 +204,10 @@ spec:RegisterResource(
         decay = function()
             return 1.25
         end,
+        -- Stepped and front-loaded, as the Warrior's (a function: Engine/Spec.lua setfenv's every meta field).
+        decayInterval = function()
+            return 1
+        end,
     }
 )
 
diff --git a/src/Hekili/Forever/Classes/Warrior.lua b/src/Hekili/Forever/Classes/Warrior.lua
index 645cdb3e..99f8da47 100644
--- a/src/Hekili/Forever/Classes/Warrior.lua
+++ b/src/Hekili/Forever/Classes/Warrior.lua
@@ -205,8 +205,7 @@ spec:RegisterResource(
         },
 
         -- Bloodrage's aura (29131): 1 rage every second for 10 s (DB2 effect: periodic energize 10 every 1000 ms).
-        -- Its ten ticks land nine times: the tick at the expiry does not (in game 2026-10-16, 10 instant + 9 = 19); both
-        -- models drop it (VirtualState's auraGain, core edit E6).
+        -- Its ten ticks all land; the tenth, at the expiry, meets the decay's first quantum (the meta table below).
         bloodrage = {
             aura = "bloodrage",
 
@@ -231,6 +230,12 @@ spec:RegisterResource(
         decay = function()
             return 1.25 * (1 - 0.3 * state.talent.anger_management.rank)
         end,
+        -- Stepped and front-loaded (stepped-decay design): 1.25 lost at once at the start of each 1 s window, the first
+        -- when the decay starts (combat end, a tick aura's expiry), so Bloodrage's last tick ends at 10 - 1.25.
+        -- A function, not a number: Engine/Spec.lua setfenv's every meta field, and setfenv(1) re-envs its caller.
+        decayInterval = function()
+            return 1
+        end,
     }
 )
 
@@ -750,8 +755,7 @@ spec:RegisterAbilities({
         end,
 
         handler = function()
-            -- 12301 (in-game tooltip): +25% of the rage Bloodrage generates a rank. The aura's ten ticks then land nine
-            -- times, the one at the expiry does not (in game 2026-10-16; the regen entry above).
+            -- 12301 (in-game tooltip): +25% of the rage Bloodrage generates a rank.
             gain(10 * (1 + 0.25 * talent.improved_bloodrage.rank), "rage")
             applyBuff("bloodrage")
         end,
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `425 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify**

```bash
stylua src/Hekili/Forever/Classes/Warrior.lua src/Hekili/Forever/Classes/Druid.lua tests/Forever/warrior_spec.lua \
  tests/Forever/druid_spec.lua                                # [no change]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 104 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      425 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
grep -n "nine times\|does not land" src/Hekili/Forever/Classes/Warrior.lua   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Forever/Classes/Warrior.lua src/Hekili/Forever/Classes/Druid.lua tests/Forever/warrior_spec.lua \
  tests/Forever/druid_spec.lua docs/forever-facade-notes.md docs/superpowers/specs/2026-10-16-stepped-decay-design.md
git commit -m "feat(classes): Warrior and Druid rage decay stepped every 1 s; facade notes and the stepped-decay design marked implemented

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-stepped-decay`

---
### Task 4: CHECKPOINT: stepped decay in game (design §5), deferred to the user

No code unless an answer calls for it. An answer that changes code is its own commit with the verification block. The change is data only, in both class files: `decayInterval` and `decay`.

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin forever-stepped-decay
git -C ~/src/hekili checkout --detach forever-stepped-decay
```

Then `/reload` in game (no new file).

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, as a Warrior out of combat, and report each answer**

Arm the two watchers first. Then press Bloodrage, cast Battle Shout at once, and wait until the bar is back at 0.

1. The bar's own steps (one line per change, with its time):
`/run local f=CreateFrame("Frame")f:SetScript("OnUpdate",function()local u=UnitPower("player",1)if u~=f.u then f.u=u VSCopy(format("%.2f",GetTime()),"bar",u)end end)`
2. The belief at the same moments, once per 0.25 s (est, lo, hi, basis, the last quantum's time):
`/run local V,n=Hekili.Virtual.State,0 local f=CreateFrame("Frame")f:SetScript("OnUpdate",function(_,e)n=n+e if n>=0.25 then n=0 local t=GetTime()local p=V.Power(1,t)VSCopy(format("%.2f",t),"vs",format("%.2f",p.est),format("%.2f",p.lo),format("%.2f",p.hi),p.basis,format("%.2f",V.DecayAnchor(1)))end end)`
3. Hekili's display through the buff: no Rend countdown (a cooldown sweep or a timer on Rend's icon) at any point.

| Line | Decides | Answer → action |
|---|---|---|
| 1 | the beat | Steps 1 s apart, the first at the buff's end (9 shown → 8 within a frame, i.e. 8.75 shows as 9 then 8 at the next beat): none. Steps 0.8 s apart: `decayInterval` → `function() return 0.8 end`, `decay` stays 1.25 (quantum 1), in both class files. |
| 2 | belief vs bar | `est` 8.75 at the buff's end, then down 1.25 at each `DecayAnchor` change, which matches line 1's steps within a frame: none. Off by a constant phase: report the two times (the anchor is the expiry; the game's may differ). |
| 3 | the sim | No countdown: none. A countdown: report Hekili's snapshot (`/hekili` snapshot of the Primary display); check the forecast's `__decay` events. |

Known limits (say them with the results):
- `VS.Power(now)` does not project beats between the belief's clock and `now`, so the belief can lag the bar by up to one frame.
- The display rounds 8.75 to 9.
- A tick aura applied exactly at a beat skips that beat (Review Focus 2).

Fix what the user reports, then repeat the affected lines. Continue only when the user confirms. When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

**1. Coverage of the design**

| Design | Task |
|---|---|
| §1 theory: the tick lands at the expiry, decay resumes front-loaded at that instant | 1 (belief), 2 (sim) |
| §1/§3.4 the 2dd4902a hack replaced: `I.TICK_EPS` and the auraGain clamp | 1 |
| §3.4 State.lua E6 back to `expires < e.next` | 2 |
| §3.4 the resources_spec expectations back to 10 ticks | 1 |
| §3.4 Warrior.lua Bloodrage comments back to ten ticks | 3 |
| §2 facts (decayOf, auraGain, the R5 pause, combat end, forecastResources, RegisterResource meta) | read; 1, 2 |
| §3.1 `decayInterval` in the meta table; quantum = decay x interval; continuous when nil/0 | 1 (belief), 3 (class data); Deviations 1, 6 |
| §3.2 per-slot arrays, active rule, transitions (combat end, the last tick aura's expiry, a rise out of combat), beats in OnAdvance, ticks before quanta, `decayNext = 0` on combat start or a tick aura | 1; Deviations 5, 7 |
| §3.2 continuous mode preserved | 1 (Review Focus 5) |
| §3.2/§3.3 zero allocation | 1, 2 (alloc_spec, the resources_spec cycle) |
| §3.3 generated `__decay` entry: interval, negative talent-scaled value, `last` from the belief's anchor, `stop`, reserved name skipped | 2; Deviations 2, 3 |
| §4 test 1 front-loaded (48.75 / 48.75 / 47.5 / 46.25, rest) | 1 |
| §4 test 2 Bloodrage end (8.75, 7.5) | 1 |
| §4 test 3 pause and re-anchor | 1 |
| §4 test 4 continuous unchanged | 1 (the existing cases) |
| §4 test 5 combat start zeroes `decayNext` | 1 |
| §4 test 6 allocation | 1, 2 |
| §4 test 7 sim entry | 2 (adapter_spec; Deviation 4), 3 (warrior/druid class data) |
| §4 test 8 the 9-tick case becomes 10 | 1 |
| §5 checkpoint | 4 |
| §6 placement (Resources.lua, Adapter.lua, State.lua, Warrior/Druid, specs, notes) | 1-3 |

**2. Placeholder scan:**
- No "TBD", "TODO", "implement later" or "similar to Task N".
- Every code step is a `git apply` patch, and every test step states its measured busted counts.

**3. Names across tasks:** these are spelled the same in every task and in the checkpoint:
- `decayInterval`, `R.decayIv`, `R.decayNext`, `decayFrom`, `beat`, `VS.DecayAnchor`
- `__decay` (`DECAY` in the Adapter), `decayEntry`

**4. Review Focus:** each line has its pinned test or check:
- 1: test 2 and the adapter_spec `19` (expiry - 1) case
- 2: test 3
- 3: the "rise above rest" case
- 4: adapter_spec test 7 (3.5 at rest, 3 = the belief's anchor, 19 with the aura)
- 5: the unchanged continuous cases plus engine_load_spec

**Concerns for the orchestrator:**
- (a) The design's `stop()` rule was not followed (Deviation 3). The evidence is State.lua:1258-1263. If the user prefers the literal design, the forecast loses all decay while Bloodrage is up.
- (b) Once the estimate reaches rest, beats stop and `hi` stops with them. After a combat end with `hi` at 100 and est at 0, `hi` stays above rest until a read or rung.
- (c) The sim entry's fallback `query_time - iv` takes a quantum at every forecast's start while the belief is inactive. It is harmless at rest, but a sim-only gain without a tick aura would lose up to one quantum early.
- (d) Bloodrage's sim tick at the expiry relies on `applied + 10 <= expires` in floats, as it did before E6.
- (e) Hekili's forecast caps itself at 30 events. About 11 decay events in a 10 s window leave room for the Bloodrage ticks, but a long GCD-extended window with swings could reach the cap. That only happens out of combat with a tick aura, so it is unlikely.

### Critical Files for Implementation
- src/Hekili/Virtual/State/Families/Resources.lua
- src/Hekili/Virtual/State/Adapter.lua
- src/Hekili/State.lua
- tests/Virtual/State/resources_spec.lua
- tests/Virtual/State/adapter_spec.lua
