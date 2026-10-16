
# Forever Target Health Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VirtualState believes the current target's health instead of a constant 1.0. An ability that declares `healthGate = g` (the Warrior's Execute, 0.2) turns the client's plain usability answer into a bound:
- usable means health ≤ g;
- a NOT under every guard of design §5 means health > g;
- a flip from such a NOT to usable pins the health at g, and on a target never held before it teaches M, the damage per full health.

Between answers, the target's plain UNIT_COMBAT WOUND amounts move the health down by amount / M. `VS.Health("target")`, `VS.TTD("target")` and a new `VS.TimeToPct` answer from this. `UnitHealth("target")` (est x 100, through the facade's existing row) moves, so `target.health.pct` moves. Hekili's `GetTTD`/`GetTimeToPct` return VirtualState's answer for the target once it has one (named core edit E4).

**Architecture:**
- **Task 1:** adds `Obs.TargetDamage = 35`, the TargetSwap `b` (a slot newly taken) and `c` (plain `UnitCanAttack`) flags in Sources/Target.lua, and the new family Families/TargetHealth.lua. At build the family indexes each ability's `healthGate` and its `buff`/`nobuff` guard aura. It handles usability answers (flip pin, bounds above and below, the §5 guards, M learned on a fresh target) and counts WOUND damage. Player.lua's `VS.Health` sends "target" to the family.
- **Task 2:** stages UNIT_COMBAT WOUND on the target as `TargetDamage`. The family then moves the health by damage / M (floor 0.02 while alive) and keeps M per memory slot across swaps. Resets: a death reads 0 (observed); combat end returns to the default. `VS.TTD("target")` and `VS.TimeToPct` come from the damage per second since the first WOUND.
- **Task 3:** named core edit E4 in Targets.lua, `GetTTD` and `GetTimeToPct`.
- **Task 4:** Execute's `healthGate = 0.2`, the allocation test's coverage of the new paths, and the docs.
- **Task 5:** the in-game CHECKPOINT.

Conservative branches only, per the controller's ruling:
- A short-of-power answer (c = 1) is no health signal.
- No plain `UnitHealthMax("target")` read (design §2.3b). M is learned only from the fresh-anchor pin, or stays unknown.

Each deferral is marked in TargetHealth.lua: a `shortcut:` comment in the c = 1 branch, and a "Hook (design §2.3b)" comment where M is learned.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, StyLua, `make check` (Makefile: lint, fmt-check, typecheck, test, syntax, api-check).

**Spec:** `docs/superpowers/specs/2026-10-16-target-health-design.md`. It is binding with the controller's rulings above:
- §1 facts
- §2 design (2.3a's short branch and 2.3b deferred)
- §3 reads, including E4
- §4 allocation
- §5 guards
- §6 tests
- §7 checkpoint
- §9 placement

## How this plan was checked

Written in a read-only session; the patches were NOT replayed. Every patch below is hand-written against the text at `e8f53b6c` (exact lines read with `sed -n`/`cat -A`; the files are LF). Hunk line counts were checked by hand, and later hunks against the same file assume the earlier task's patch exactly.

Base counts measured at `e8f53b6c`:
- `.lua/bin/busted`: 387 successes (the brief's 384 predates the E5 commit)
- `luacheck -q .`: 0 warnings / 0 errors in 99 files
- `tools/check_api_reads.sh`: ok in 63 loaded files

Each task's expected counts are derived from these. The implementer runs the red step and the verification block, and records the real output in the review.

## Global Constraints

- **Worktree.** Repository `~/src/hekili`. Work only in a new worktree `~/src/hekili/.claude/worktrees/forever-target-health`, on branch `forever-target-health` from `e8f53b6c`:
  - Create it with `git -C ~/src/hekili worktree add .claude/worktrees/forever-target-health -b forever-target-health e8f53b6c`.
  - Git from WSL only.
  - After each task's green verification and clean review, the orchestrator pushes the branch (`git push origin forever-target-health`). Never push to `forever` or any other branch; never force-push. No task merges.
- **Commits.** Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. An implementer on another model uses its own model's name.
- **No allocation in recurring paths.** Records, per-ability arrays (`ab`, `gate`, `aura`, `up`, `prev`, `notDmg`) and `maxBy[1..TARGET_CAP]` are allocated at build or load. Appliers and accessors do scalar arithmetic only. UNIT_COMBAT stages numbers (`S.Stage`). Task 4's `alloc_spec` measures 0 bytes.
- **No class names in the engine.** `Virtual/` reads the declarative `healthGate`, `buff` and `nobuff` fields only. No "Warrior", "Execute" or 5308 appears in a VirtualState file.
- **Every game read goes through the facade or the injected `api`.** Hekili files read through `ns.Facade` (`tools/check_api_reads.sh`). VirtualState sources read only through `api` and `Plain` (`tests/Virtual/State/secrets_spec.lua`). The one new read, `api.UnitCanAttack("player", "target")`, is plain in combat [W PR14] and goes through `Plain`. It is not an inventory name (VirtualState reads the injected `api`), so `tools/api_inventory.txt` is unchanged and api-check's `git diff --exit-code tools/api_inventory.txt` stays empty.
- **Upstream files** are edited only as named core edits: Targets.lua, E4 (Task 3), marked `-- Forever E4:`.
- **Style.** StyLua formats only our files (`.styluaignore` lists Targets.lua). Targets.lua keeps Hekili's style (spaces inside parentheses). Every patch below is written in StyLua's output style. Each task still runs `stylua` on its own files before verification. If StyLua changes a line a later hunk uses as context, apply that small hunk by hand (each one names its function in its context).
- **Tools.** Run everything from the worktree root. The worktree has no `.lua/`, so pass the main checkout's: `make check LUA_ENV=$HOME/src/hekili/.lua`. Busted alone: `$HOME/src/hekili/.lua/bin/busted`.
- **Verification block** at the end of every code task:

  ```bash
  stylua <the task's Lua files under src/Hekili/Virtual, src/Hekili/Forever, tests/>   # [no output; git diff unchanged]
  make check LUA_ENV=$HOME/src/hekili/.lua
  #   lint:      Total: 0 warnings / 0 errors in F files
  #   fmt-check: (silent)
  #   typecheck: Diagnosis completed, no problems found
  #   test:      N successes / 0 failures / 0 errors / 0 pending
  #   syntax:    (silent)
  #   api-check: ok: no direct game API read in L loaded files; inventory diff empty
  ```
- **Patches** are applied with `git apply` from the worktree root, in the order given.
- **The user runs the game.** A **CHECKPOINT** task stops execution:
  - The orchestrator, not a subagent, pushes the branch and runs `git -C ~/src/hekili checkout --detach forever-target-health`.
  - It asks the user to run the exact lines given, and waits.
  - Lines copy their answers through `VSCopy(` (ForeverProbe). A new TOC file needs a full client restart, not a `/reload`.
  - When the session ends: `git -C ~/src/hekili checkout forever`.

## Review Focus

1. **UNIT_COMBAT is registered for every unit, not "target"** (Task 2). `S.On("UNIT_COMBAT", nil, ...)` with `unit == "target"` checked in the handler. A `"target"` registration would put the event in `S.UNITS` and narrow the client registration to `RegisterUnitEvent(e, "target")` (Virtual/Events/EventFacade.lua `sync`). That would starve Attackers.lua of the player's hits. The fake client does not filter units, so only review catches this.
2. **Conservative branches** (Task 1):
   - A short answer (c = 1) only clears `prev` (the `shortcut:` comment); it never bounds health.
   - M is set only at a flip on a fresh target (`H.fresh`, TargetSwap b = 1) with damage taken and M unknown. The "Hook (design §2.3b)" comment marks where a plain max would plug in.
   - Pinned by test 2 (a short answer, then usable, is a bound, not a flip; M stays 0).
3. **A NOT bounds health only under every §5 guard:**
   - known
   - cost ≤ believed rage `lo`
   - guard aura as needed (-1 means never)
   - live attackable target
   - lag ≤ `PIN_EXACT`

   Tests 2 and 3. A flip needs a guarded NOT immediately before it, so a power or stance flip is never read as health.
4. **Zero allocation** (Task 4 `alloc_spec`): 10,000 steps with gated flips, target WOUNDs, `VS.Health/TTD("target")`, `VS.TimeToPct` and `Facade.UnitHealth("target")`, measured at 0 bytes.
5. **E4 falls through to Hekili's tracker until the belief has an answer** (test 7: 300 and 210 before, the belief's ceil'd answer with n = 3 after).
6. **No class name in the engine; the inventory is unchanged** (the api-check diff stays empty).

## File structure

```
src/Hekili/Virtual/State/VirtualState.lua           T1  Obs.TargetDamage = 35; TargetSwap's b/c documented
src/Hekili/Hekili.toc                               T1  Virtual\State\Families\TargetHealth.lua after TargetCast.lua
src/Hekili/Virtual/State/Families/TargetHealth.lua  T1  new: gate index, usability bounds/pin/guards, damage count, I.TargetHealth
                                                    T2  slope, floor, maxBy, TargetGone, CombatEnd, I.TargetTTD, VS.TimeToPct
src/Hekili/Virtual/State/Families/Player.lua        T1  VS.Health("target") dispatch; T2 VS.TTD("target") dispatch
src/Hekili/Virtual/State/Sources/Target.lua         T1  TargetSwap b (slot newly taken), c (plain UnitCanAttack)
                                                    T2  UNIT_COMBAT WOUND -> Stage(TargetDamage)
src/Hekili/Targets.lua                              T3  E4: GetTTD, GetTimeToPct
src/Hekili/Forever/Classes/Warrior.lua              T4  execute: healthGate = 0.2
tests/Virtual/State/target_health_spec.lua          T1  tests 1-3; T2 tests 4-6; T3 test 7
tests/Virtual/State/alloc_spec.lua                  T4  test 8
tests/Forever/warrior_spec.lua                      T4  execute.healthGate
docs/superpowers/specs/2026-10-16-target-health-design.md   T4  status line
docs/forever-facade-notes.md                        T4  the TTD line
```

Deliberately not built (a review should not flag these):
- the short-answer signal (§2.3a, §7 line 4);
- the plain max read (§2.3b, §7 line 2);
- a per-npcid M;
- `fight_remains`/`GetGreatestTTD` (keep Hekili's tracker);
- Hammer of Wrath (no Paladin file);
- a `buff` guard for a future Execute proc.

---
### Task 1: The target health family: gate index, usability bounds and the flip pin

Design §2.1, §2.2, §2.3a (usable/NOT branches), §2.3d (swap start), §3 (`VS.Health("target")`), §5, §6 tests 1-3.

**Files:**
- Create: `src/Hekili/Virtual/State/Families/TargetHealth.lua`, `tests/Virtual/State/target_health_spec.lua`
- Modify: `src/Hekili/Virtual/State/VirtualState.lua`, `src/Hekili/Hekili.toc`, `src/Hekili/Virtual/State/Families/Player.lua`, `src/Hekili/Virtual/State/Sources/Target.lua`

**Interfaces:**
- Consumes: `I.ab` (`known`, `slot`, `obj`), `I.CostOf`, `I.res.lo0`, `I.auras.exp0[1]`, `I.PIN_EXACT`, `I.EPS`, `I.NewBelief`, `I.Sample`, `Obs.Usable`, `Obs.TargetSwap` (a slot, b 1 newly taken, c 1 attackable).
- Produces:
  - `Obs.TargetDamage = 35` (b: amount)
  - `I.th` (the family's scalars and arrays: `n`, `ab`, `gate`, `aura`, `up`, `prev`, `notDmg`, `slot`, `dead`, `attackable`, `fresh`, `est0`, `lo0`, `hi0`, `dmg`, `dmgT0`, `M`)
  - `I.TargetHealth(now)` → the "health target" record
  - `VS.Health("target", now)` → that record

- [ ] **Step 1: Write the failing spec**

```diff
diff --git a/tests/Virtual/State/target_health_spec.lua b/tests/Virtual/State/target_health_spec.lua
new file mode 100644
--- /dev/null
+++ b/tests/Virtual/State/target_health_spec.lua
@@ -0,0 +1,90 @@
+-- tests/Virtual/State/target_health_spec.lua: the target health family (target-health design, 2026-10-16, §6). A
+-- health-gated spender's flip pins the target's health at its gate and teaches M (the damage per full health) on a
+-- target never held before; the guards keep a NOT from bounding it; WOUND damage moves it between answers; the time to
+-- die and to a percentage follow; the facade and Targets.lua's GetTTD/GetTimeToPct (named core edit E4) answer it.
+local load = require("Virtual.State.helpers.load")
+local fake = require("Virtual.State.helpers.fake_api")
+
+local function within(want, got, tol)
+    assert.is_true(math.abs(want - got) <= (tol or 1e-9), ("want %s, got %s"):format(want, got))
+end
+
+-- A gated spender (Smite: 15 rage, usable at or below 20%, not while Stance is up) and an ungated one; rage, no regen.
+local SMITE, SLAM, STANCE = 2001, 2002, 3001
+local GATED = 1 -- Smite's ability index
+
+local function def()
+    return {
+        abilities = {
+            { key = "smite", spend = 15, healthGate = 0.2, nobuff = "stance" },
+            { key = "slam", spend = 10 },
+        },
+        abilityIds = { { SMITE }, { SLAM } },
+        abilitySlot = { 1, 1 },
+        resources = { { key = "rage", type = 1, token = "RAGE", max = 100, rest = false } },
+        auras = { { key = "stance", id = STANCE } },
+        auraIds = { { STANCE } },
+        talents = {},
+        units = { "player", "target" },
+    }
+end
+
+describe("target health", function()
+    local ns, VS, I, S, Obs, ReadOf, api, ctl
+
+    before_each(function()
+        api, ctl = fake.new()
+        ns = load.module()
+        VS, I = ns.VirtualState, ns.VirtualStateInternal
+        S, Obs, ReadOf = I.Sources, VS.Obs, I.ReadOf
+        ctl.known[SMITE], ctl.known[SLAM] = true, true
+        I.api = api
+        I.Build(def(), 1) -- the build's swap: Creature-1 takes slot 1, never held before, attackable
+    end)
+
+    local function obs(kind, t, a, b, c)
+        S.Direct(kind, t, a, b, c)
+    end
+
+    -- 50 rage, 800 damage taken at 3, a guarded NOT at 9, then the flip at 10: health 0.2, M = 800 / (1 - 0.2).
+    local function anchor()
+        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
+        obs(Obs.TargetDamage, 3, 0, 800)
+        obs(Obs.Usable, 9, GATED, 0, 0)
+        obs(Obs.Usable, 10, GATED, 1, 0)
+        I.Fold(10)
+    end
+
+    it("pins the health at the gate on a flip and learns M on a target never held before", function()
+        anchor()
+        local h = VS.Health("target", 10)
+        assert.are.same({ 0.2, 0.2, 0.2, "pinned" }, { h.est, h.lo, h.hi, h.basis })
+        within(1000, I.th.M, 1e-6)
+    end)
+
+    it("takes no bound from a NOT while the cost is believed unaffordable, nor from a short answer", function()
+        obs(Obs.Read, 2, 1, 5, ReadOf.Resource) -- 5 rage: Smite's 15 believed unaffordable
+        obs(Obs.Usable, 9, GATED, 0, 0)
+        obs(Obs.Usable, 9.5, GATED, 0, 1) -- short (c = 1): no health signal until design §7 line 4 says so
+        I.Fold(9.5)
+        local h = VS.Health("target", 9.5)
+        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
+        obs(Obs.Usable, 10, GATED, 1, 0) -- usable after the short: a bound at the gate, not a flip
+        I.Fold(10)
+        h = VS.Health("target", 10)
+        assert.are.same({ 0.2, 0, 0.2, "pinned", 0 }, { h.est, h.lo, h.hi, h.basis, I.th.M })
+    end)
+
+    it("takes no bound from a NOT while the guard aura is believed up", function()
+        obs(Obs.Read, 2, 1, 50, ReadOf.Resource)
+        obs(Obs.Read, 2, 1, 3600, ReadOf.Aura + I.AURA_STACK) -- Stance up on the player (unit 1, aura 1), 1 stack
+        obs(Obs.Usable, 9, GATED, 0, 0)
+        I.Fold(9)
+        local h = VS.Health("target", 9)
+        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
+        obs(Obs.Usable, 10, GATED, 1, 0) -- no guarded NOT before it: a bound at the gate, not a flip
+        I.Fold(10)
+        h = VS.Health("target", 10)
+        assert.are.same({ 0.2, 0, 0.2, 0 }, { h.est, h.lo, h.hi, I.th.M })
+    end)
+end)
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `$HOME/src/hekili/.lua/bin/busted tests/Virtual/State/target_health_spec.lua`
Expected: `0 successes / 2 failures / 1 error`:
- tests 1 and 2 fail on the constant `health other` record;
- test 3 errors on `I.th` being nil.

- [ ] **Step 3: Write the implementation**

```diff
diff --git a/src/Hekili/Virtual/State/VirtualState.lua b/src/Hekili/Virtual/State/VirtualState.lua
--- a/src/Hekili/Virtual/State/VirtualState.lua
+++ b/src/Hekili/Virtual/State/VirtualState.lua
@@ -23,7 +23,7 @@ VS.Obs = {
     Read = 5, -- a: resource slot or aura index (c: ReadOf); b: the exact value (amount; aura time remaining)
     Cooldown = 6, -- a: ability index; b: 1 ready / 0 not (the plain isActive flag); c: 1 the GCD flag edge
     PowerTick = 7, -- a: resource slot
-    TargetSwap = 8,
+    TargetSwap = 8, -- a: memory slot (0 none); b: 1 a slot newly taken; c: 1 attackable (plain UnitCanAttack)
     CombatStart = 9,
     CombatEnd = 10,
     Group = 11, -- reserved
@@ -50,4 +50,5 @@ VS.Obs = {
     ItemCooldown = 32, -- reserved
     Range = 33, -- a: plate index; b: count in range of the range spell
     TargetCast = 34, -- a: TargetCastOf; b: castBarID; c: interruptible 1 / 0 / -1 unknown
+    TargetDamage = 35, -- b: a WOUND amount the target took (UNIT_COMBAT, plain); VirtualState's own, past TDF's range
 }
diff --git a/src/Hekili/Hekili.toc b/src/Hekili/Hekili.toc
--- a/src/Hekili/Hekili.toc
+++ b/src/Hekili/Hekili.toc
@@ -18,6 +18,7 @@ Virtual\State\Families\Resources.lua
 Virtual\State\Families\Swing.lua
 Virtual\State\Families\Auras.lua
 Virtual\State\Families\TargetCast.lua
+Virtual\State\Families\TargetHealth.lua
 Virtual\State\Families\Talents.lua
 Virtual\State\Families\Totems.lua
 Virtual\State\Families\Enemies.lua
diff --git a/src/Hekili/Virtual/State/Families/TargetHealth.lua b/src/Hekili/Virtual/State/Families/TargetHealth.lua
new file mode 100644
--- /dev/null
+++ b/src/Hekili/Virtual/State/Families/TargetHealth.lua
@@ -0,0 +1,209 @@
+-- Virtual/State/Families/TargetHealth.lua
+-- Target health (docs/superpowers/specs/2026-10-16-target-health-design.md): the current target's health as a
+-- fraction 0..1, from the client's usability answer for an ability declaring `healthGate = g` (usable only at or
+-- below g of the target's health). Usable bounds the health at or below g; a NOT under every guard of design §5
+-- bounds it above g; a flip from such a NOT to usable pins it at g. M, the damage per full health, is learned at that
+-- flip on a target never held before (full at the swap): M = the WOUND damage since the swap / (1 - g).
+-- Not built until the in-game checkpoint (design §7) answers: a short answer (c = 1) as a health signal (line 4), and
+-- a plain UnitHealthMax("target") read as M (line 2; its hook is marked below).
+
+local _, ns = ...
+local VS, I = ns.VirtualState, ns.VirtualStateInternal
+local Obs = VS.Obs
+
+-- What a gated ability's last answer said: nothing about health, above its gate (a guarded NOT), at or below it.
+local UNKNOWN, ABOVE, BELOW = -1, 0, 1
+
+-- By gated ability k (n of them): its ability index, gate, guard aura (the player aura index of its `buff` or `nobuff`:
+-- 0 none, -1 named but untracked, which allows no NOT bound), whether that aura must be up (`buff`), its last answer,
+-- and the damage taken at its last guarded NOT. The current target: its memory slot (0 none), dead, attackable
+-- (TargetSwap c), fresh (TargetSwap b: never held before, so full at the swap), the health interval, the WOUND damage
+-- since the swap and the first WOUND's time, M (the damage per full health; 0 unknown).
+local H = {
+    n = 0,
+    ab = {},
+    gate = {},
+    aura = {},
+    up = {},
+    prev = {},
+    notDmg = {},
+    slot = 0,
+    dead = false,
+    attackable = false,
+    fresh = false,
+    est0 = 1,
+    lo0 = 0,
+    hi0 = 1,
+    dmg = 0,
+    dmgT0 = 0,
+    M = 0,
+}
+I.th = H
+local rec
+
+-- The player aura index of an ability's `buff`/`nobuff` key (Resources.lua's swingAura): 0 none, -1 untracked.
+local function auraIndex(def, key)
+    if key == nil then
+        return 0
+    end
+    for i = 1, #def.auras do
+        if def.auras[i].key == key then
+            return i
+        end
+    end
+    return -1
+end
+
+-- Back to the default: 1.0 in [0, 1], no damage seen, no answer standing; only the default sample counts (basis
+-- "default"). Allocates nothing.
+local function restart(t)
+    H.est0, H.lo0, H.hi0, H.dmg, H.dmgT0 = 1, 0, 1, 0, 0
+    for k = 1, H.n do
+        H.prev[k] = UNKNOWN
+    end
+    local last = rec.last
+    last.observed.t, last.pinned.t, last.modelled.t = 0, 0, 0
+    I.Sample(rec, "default", 1, t, 0)
+end
+
+I.OnBuild(function(def, now)
+    rec = I.NewBelief("health target")
+    H.n = 0
+    for a = 1, #def.abilities do
+        local obj = def.abilities[a]
+        local g = rawget(obj, "healthGate")
+        if type(g) == "number" and g > 0 and g < 1 then
+            local buff, nobuff = rawget(obj, "buff"), rawget(obj, "nobuff")
+            local k = H.n + 1
+            H.n, H.ab[k], H.gate[k], H.up[k], H.notDmg[k] = k, a, g, buff ~= nil, 0
+            if buff ~= nil and nobuff ~= nil then
+                H.aura[k] = -1 -- shortcut: both named allows no NOT bound; resolve both when an ability needs it
+            else
+                H.aura[k] = auraIndex(def, buff ~= nil and buff or nobuff)
+            end
+        end
+    end
+    H.slot, H.dead, H.attackable, H.fresh, H.M = 0, false, false, false, 0
+    restart(now)
+end)
+
+-- Every guard of design §5 on reading a NOT as "above the gate" (the caller has checked a live target): the ability
+-- known, its cost believed affordable, its guard aura as it needs, the target attackable. Range is not part of
+-- IsSpellUsable; a gated ability has no cooldown. Allocates nothing.
+local function guarded(k, a, t)
+    if I.ab.known[a] == false or not H.attackable then
+        return false
+    end
+    local r = I.ab.slot[a]
+    if r > 0 and I.res.lo0[r] < I.CostOf(a) then
+        return false
+    end
+    local j = H.aura[k]
+    if j < 0 then
+        return false
+    elseif j == 0 then
+        return true
+    end
+    local up = I.auras.exp0[1][j] > t -- unit 1 is always "player" (Adapter.lua's def.units)
+    return up == H.up[k]
+end
+
+I.On(Obs.Usable, function(o, t, lag)
+    local a, k = o.a, 0
+    for i = 1, H.n do
+        if H.ab[i] == a then
+            k = i
+        end
+    end
+    if k == 0 or H.slot == 0 or H.dead then
+        return
+    end
+    local g = H.gate[k]
+    if o.b == 1 then
+        local was = H.prev[k]
+        H.prev[k] = BELOW
+        if was == ABOVE and lag <= I.PIN_EXACT then
+            -- A flip: the health crossed g since the last guarded NOT, by at most the damage taken since then.
+            local slack = H.M > 0 and (H.dmg - H.notDmg[k]) / H.M or 0 -- nonzero: M > 0 checked
+            H.lo0, H.hi0 = g - slack > 0 and g - slack or 0, g
+            H.est0 = (H.lo0 + H.hi0) / 2
+            -- Hook (design §2.3b, deferred to §7 line 2): a plain UnitHealthMax("target") read would set M here,
+            -- observed, winning over a learned one (as Resources.lua's maxRead). Until then M is learned or unknown.
+            if H.fresh and H.dmg > 0 and H.M == 0 then
+                H.M = H.dmg / (1 - g) -- nonzero: g < 1 (checked at the build)
+            end
+            I.Sample(rec, "pinned", H.est0, t, Obs.Usable)
+        else
+            if H.hi0 > g then
+                H.hi0 = g
+            end
+            if H.lo0 > g then
+                H.lo0 = g -- the newest bound wins
+            end
+            if H.est0 > g then
+                H.est0 = g
+                I.Sample(rec, "pinned", g, t, Obs.Usable)
+            end
+        end
+    elseif o.c == 1 then
+        -- shortcut: a short answer says nothing about health until design §7 line 4 shows short means at or below
+        -- the gate; then it joins the usable branch above.
+        H.prev[k] = UNKNOWN
+    elseif lag <= I.PIN_EXACT and guarded(k, a, t) then
+        local top = g + I.EPS
+        H.prev[k], H.notDmg[k] = ABOVE, H.dmg
+        if H.lo0 < top then
+            H.lo0 = top
+        end
+        if H.hi0 < top then
+            H.hi0 = 1 -- the newest bound wins: it healed (an evade) since the bound below
+        end
+        if H.est0 < top then
+            H.est0 = top
+            I.Sample(rec, "pinned", top, t, Obs.Usable)
+        end
+    else
+        H.prev[k] = UNKNOWN
+    end
+end)
+
+-- A swap (a: the new slot, 0 none; b: 1 never held before; c: 1 attackable) starts the new target over at the
+-- default. Families/Auras.lua has already moved I.curSlot; H.slot is still the old slot here.
+I.On(Obs.TargetSwap, function(o, t)
+    H.slot, H.dead, H.M = o.a, false, 0
+    H.fresh, H.attackable = o.b == 1, o.c == 1
+    restart(t)
+end)
+
+-- WOUND damage the target took (UNIT_COMBAT, plain; everyone's hits): counted from the swap, M's numerator.
+I.On(Obs.TargetDamage, function(o, t)
+    if H.slot == 0 or H.dead then
+        return
+    end
+    if H.dmgT0 == 0 then
+        H.dmgT0 = o.t
+    end
+    H.dmg = H.dmg + o.b
+end)
+
+--- (design §3) The current target's health fraction: the interval as folded, conf 1 - its width (0 at the default).
+--- VS.Health("target") answers it (Families/Player.lua). Allocates nothing.
+function I.TargetHealth(now)
+    rec.est, rec.lo, rec.hi = H.est0, H.lo0, H.hi0
+    rec.conf = 1 - (H.hi0 - H.lo0)
+    return rec
+end
+
+I.OnSnapshot(function(out, now)
+    I.TargetHealth(now)
+    out[#out + 1] = string.format(
+        "target health slot=%d gates=%d M=%.0f dmg=%.0f fresh=%s attackable=%s dead=%s",
+        H.slot,
+        H.n,
+        H.M,
+        H.dmg,
+        tostring(H.fresh),
+        tostring(H.attackable),
+        tostring(H.dead)
+    )
+end)
diff --git a/src/Hekili/Virtual/State/Families/Player.lua b/src/Hekili/Virtual/State/Families/Player.lua
--- a/src/Hekili/Virtual/State/Families/Player.lua
+++ b/src/Hekili/Virtual/State/Families/Player.lua
@@ -28,7 +28,7 @@ I.On(Obs.CombatStart, function(o, t)
     I.combatT = t
 end)
 
--- Health (player: plain reads; every other unit: the default 1.0), spell haste, time to die.
+-- Health (player: plain reads; target: Families/TargetHealth.lua; others: the default 1.0), spell haste, time to die.
 local health, otherHealth, spellHaste, ttd
 I.healthMax = 0
 
@@ -68,14 +68,17 @@ I.On(Obs.Haste, function(o, t)
     end
 end)
 
---- (spec §3.2) Health fraction 0..1: the player's last plain read (conf decaying as an aura), else default 1.0.
+--- (spec §3.2) Health fraction 0..1: the player's last plain read (conf decaying as an aura); the target's belief
+--- (Families/TargetHealth.lua); every other unit the default 1.0.
 function VS.Health(unit, now)
     if unit == "player" then
         decay(health, now)
         return health
+    elseif unit == "target" then
+        return I.TargetHealth(now)
     end
     return otherHealth
 end
 
 --- (spec §3.1) The player's last plain maximum health; 100 for any other unit.
 function VS.HealthMax(unit)
diff --git a/src/Hekili/Virtual/State/Sources/Target.lua b/src/Hekili/Virtual/State/Sources/Target.lua
--- a/src/Hekili/Virtual/State/Sources/Target.lua
+++ b/src/Hekili/Virtual/State/Sources/Target.lua
@@ -1,7 +1,8 @@
 -- Virtual/State/Sources/Target.lua
 -- Target sources (spec §4.2): PLAYER_TARGET_CHANGED keeps a GUID -> memory slot map (TARGET_CAP slots, the least
--- recently used reused) and logs `TargetSwap` (a: the slot, 0 no target) straight to the log, then walks the new
--- target's auras; poll 4 logs `TargetGone` for a dead target; the target's UNIT_SPELLCAST_* events become
--- `TargetCast` observations by castBarID (plain; the spellID and castGUID are secret on the target).
+-- recently used reused) and logs `TargetSwap` (a: the slot, 0 no target; b: 1 a slot newly taken; c: 1 plain
+-- UnitCanAttack) straight to the log, then walks the new target's auras; poll 4 logs `TargetGone` for a dead target;
+-- the target's UNIT_SPELLCAST_* events become `TargetCast` observations by castBarID (plain; the spellID and castGUID
+-- are secret on the target).
 -- Credits: secret-value handling after Catnip's (Durts) research.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Target.lua.
 
@@ -24,7 +25,7 @@ local function slotFor(g, t)
     for s = 1, I.TARGET_CAP do
         if guid[s] == g then
             used[s] = t
-            return s
+            return s, false
         elseif guid[s] == "" and free == 0 then
             free = s
         elseif used[s] < used[oldest] then
@@ -36,17 +37,21 @@ local function slotFor(g, t)
         Direct(Obs.TargetGone, t, s)
     end
     guid[s], used[s] = g, t
-    return s
+    return s, true -- newly taken: a GUID not held before (or forgotten)
 end
 
 -- A target swap: the new target's memory slot, then a walk of its auras. Also at Start and at each rebuild, so a
 -- target already held at a /reload gets its slot (poll 4 then sees its death, a swap away keeps what was believed).
 -- No "built" guard: in game Start (PLAYER_LOGIN) comes before the first build (PLAYER_ENTERING_WORLD), and I.Build
 -- runs its hooks before it marks the set built; the slot map lives here, and a swap logged before a build is cleared
 -- by that build, which logs its own.
 local function swap(api, t)
     local g = Plain(api, api.UnitGUID("target"))
-    local s = type(g) == "string" and slotFor(g, t) or 0
+    local s, fresh = 0, false
+    if type(g) == "string" then
+        s, fresh = slotFor(g, t)
+    end
+    local attackable = s > 0 and Plain(api, api.UnitCanAttack("player", "target")) == true
     dead = false
-    Direct(Obs.TargetSwap, t, s)
+    Direct(Obs.TargetSwap, t, s, fresh and 1 or 0, attackable and 1 or 0)
     if s > 0 and I.auras.n >= 2 then
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`
Expected: `390 successes / 0 failures / 0 errors / 0 pending`. These existing specs keep passing:
- `facts_spec` (`VS.Health("target")` est 1, `VS.TTD` 30);
- `facade_spec` (`UnitHealth("target")` 100);
- `secrets_spec` (the new `UnitCanAttack` read goes through `Plain`).

- [ ] **Step 5: Verify**

```bash
stylua src/Hekili/Virtual/State/VirtualState.lua src/Hekili/Virtual/State/Families/TargetHealth.lua \
  src/Hekili/Virtual/State/Families/Player.lua src/Hekili/Virtual/State/Sources/Target.lua \
  tests/Virtual/State/target_health_spec.lua                 # [no change]
make check LUA_ENV=$HOME/src/hekili/.lua
# lint: Total: 0 warnings / 0 errors in 101 files; fmt-check silent; typecheck: no problems;
# test: 390 successes / 0 failures / 0 errors / 0 pending; syntax silent;
# api-check: ok: no direct game API read in 64 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/VirtualState.lua src/Hekili/Hekili.toc src/Hekili/Virtual/State/Families/TargetHealth.lua \
  src/Hekili/Virtual/State/Families/Player.lua src/Hekili/Virtual/State/Sources/Target.lua tests/Virtual/State/target_health_spec.lua
git commit -m "feat(vs): target health family: a health-gated spender's usability bounds and pins the target's health, M learned on a fresh target (target-health design §2.1-2.3a, §5)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-target-health`

---
### Task 2: The damage slope, the resets, the time to die and to a percentage

Design §2.3c, §2.3d (maxBy, TargetGone, CombatEnd), §3 (`VS.TTD("target")`, `VS.TimeToPct`), §6 tests 4-6.

**Files:**
- Modify: `src/Hekili/Virtual/State/Families/TargetHealth.lua`, `src/Hekili/Virtual/State/Families/Player.lua`, `src/Hekili/Virtual/State/Sources/Target.lua`
- Test: `tests/Virtual/State/target_health_spec.lua`

**Interfaces:**
- Consumes: Task 1's `I.th`, `Obs.TargetDamage`, `Obs.TargetGone` (a slot), `Obs.CombatEnd`, `I.PIN_GAP`, `I.TARGET_CAP`.
- Produces:
  - `I.TARGET_HEALTH_FLOOR = 0.02`
  - `I.th.maxBy[s]`
  - `I.TargetTTD(now)` → the "ttd target" record or nil
  - `VS.TTD("target", now)` → that record, else the default `ttd`
  - `VS.TimeToPct(p, now)` → the "time to pct target" record (p a fraction) or nil
  - the UNIT_COMBAT source

- [ ] **Step 1: Write the failing specs**

```diff
diff --git a/tests/Virtual/State/target_health_spec.lua b/tests/Virtual/State/target_health_spec.lua
--- a/tests/Virtual/State/target_health_spec.lua
+++ b/tests/Virtual/State/target_health_spec.lua
@@ -87,4 +87,57 @@ describe("target health", function()
         h = VS.Health("target", 10)
         assert.are.same({ 0.2, 0, 0.2, 0 }, { h.est, h.lo, h.hi, I.th.M })
     end)
+
+    it("moves the health by WOUND damage over M and answers the time to die from the damage per second", function()
+        anchor()
+        obs(Obs.TargetDamage, 11, 0, 50)
+        obs(Obs.TargetDamage, 12, 0, 50)
+        I.Fold(12)
+        local h = VS.Health("target", 12)
+        within(0.1, h.est, 1e-6)
+        within(0.1, h.lo, 1e-6)
+        within(0.1, h.hi, 1e-6)
+        assert.are.equal("modelled", h.basis)
+        local dps = 900 / (12 - 3) -- every WOUND since the first, at 3
+        local ttd = VS.TTD("target", 12)
+        assert.are.equal("modelled", ttd.basis)
+        within(h.est * I.th.M / dps, ttd.est, 1e-6)
+        within((h.est - 0.05) * I.th.M / dps, VS.TimeToPct(0.05, 12).est, 1e-6)
+    end)
+
+    it("keeps a live target at the floor and reads a dead one as 0, observed", function()
+        anchor()
+        obs(Obs.TargetDamage, 11, 0, 500)
+        I.Fold(11)
+        local h = VS.Health("target", 11)
+        assert.are.same({ 0.02, 0.02, 0.02, "modelled" }, { h.est, h.lo, h.hi, h.basis })
+        obs(Obs.TargetGone, 12, 1)
+        I.Fold(12)
+        h = VS.Health("target", 12)
+        assert.are.same({ 0, 0, 0, "observed" }, { h.est, h.lo, h.hi, h.basis })
+        assert.are.equal(30, VS.TTD("target", 12).est) -- dead: the default
+    end)
+
+    it("starts a new target over at the default and keeps M for a target swapped back to", function()
+        anchor()
+        VS.Start(api) -- the start's swap at 100: Creature-1 keeps slot 1 (held before)
+        ctl.guid.target = "Creature-2"
+        api.UnitCanAttack = function()
+            return false
+        end
+        ctl.Fire("PLAYER_TARGET_CHANGED")
+        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 70, 1)
+        ctl.Tick() -- the staged WOUND into the log
+        I.Fold(100)
+        -- M unknown on the new target: its WOUND moves nothing
+        local h = VS.Health("target", 100)
+        assert.are.same({ 1, 0, 1, "default" }, { h.est, h.lo, h.hi, h.basis })
+        assert.are.same({ 2, true, false, 70, 0 }, { I.th.slot, I.th.fresh, I.th.attackable, I.th.dmg, I.th.M })
+        ctl.now = 101
+        ctl.guid.target = "Creature-1"
+        ctl.Fire("PLAYER_TARGET_CHANGED")
+        I.Fold(101)
+        assert.are.same({ 1, false, 0, "default" }, { I.th.slot, I.th.fresh, I.th.dmg, VS.Health("target", 101).basis })
+        within(1000, I.th.M, 1e-6)
+    end)
 end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted tests/Virtual/State/target_health_spec.lua`
Expected: `3 successes / 3 failures / 0 errors`:
- test 4: the health stays 0.2 (no slope);
- test 5: 0.2, not 0.02;
- test 6: dmg is 0 (no UNIT_COMBAT source).

- [ ] **Step 3: Write the implementation**

```diff
diff --git a/src/Hekili/Virtual/State/Families/TargetHealth.lua b/src/Hekili/Virtual/State/Families/TargetHealth.lua
--- a/src/Hekili/Virtual/State/Families/TargetHealth.lua
+++ b/src/Hekili/Virtual/State/Families/TargetHealth.lua
@@ -4,12 +4,17 @@
 -- below g of the target's health). Usable bounds the health at or below g; a NOT under every guard of design §5
 -- bounds it above g; a flip from such a NOT to usable pins it at g. M, the damage per full health, is learned at that
 -- flip on a target never held before (full at the swap): M = the WOUND damage since the swap / (1 - g).
+-- Between answers each WOUND moves the health down by amount / M (floor 0.02 while alive); the time to die and to a
+-- percentage are the health left x M / the damage per second since the first WOUND.
 -- Not built until the in-game checkpoint (design §7) answers: a short answer (c = 1) as a health signal (line 4), and
 -- a plain UnitHealthMax("target") read as M (line 2; its hook is marked below).
 
 local _, ns = ...
 local VS, I = ns.VirtualState, ns.VirtualStateInternal
 local Obs = VS.Obs
 
+--- A live target's health never reads below this fraction (Targets.lua's UpdateTTDs drops an enemy at or below 1%).
+I.TARGET_HEALTH_FLOOR = 0.02
+
 -- What a gated ability's last answer said: nothing about health, above its gate (a guarded NOT), at or below it.
 local UNKNOWN, ABOVE, BELOW = -1, 0, 1
 
@@ -27,6 +32,7 @@ local H = {
     up = {},
     prev = {},
     notDmg = {},
+    maxBy = {}, -- M by target memory slot: a swap back keeps it
     slot = 0,
     dead = false,
     attackable = false,
@@ -40,4 +46,4 @@ local H = {
 }
 I.th = H
-local rec
+local rec, ttdRec, pctRec
 
@@ -68,6 +74,8 @@ local function restart(t)
 
 I.OnBuild(function(def, now)
     rec = I.NewBelief("health target")
+    ttdRec = I.NewBelief("ttd target")
+    pctRec = I.NewBelief("time to pct target")
     H.n = 0
     for a = 1, #def.abilities do
         local obj = def.abilities[a]
@@ -83,6 +91,9 @@ I.OnBuild(function(def, now)
             end
         end
     end
+    for s = 1, I.TARGET_CAP do
+        H.maxBy[s] = 0
+    end
     H.slot, H.dead, H.attackable, H.fresh, H.M = 0, false, false, false, 0
     restart(now)
 end)
@@ -167,10 +178,14 @@ I.On(Obs.Usable, function(o, t, lag)
     end
 end)
 
--- A swap (a: the new slot, 0 none; b: 1 never held before; c: 1 attackable) starts the new target over at the
--- default. Families/Auras.lua has already moved I.curSlot; H.slot is still the old slot here.
+-- A swap (a: the new slot, 0 none; b: 1 never held before; c: 1 attackable) keeps the old slot's M and starts the new
+-- target over at the default with its own. Families/Auras.lua has already moved I.curSlot; H.slot is the old one here.
 I.On(Obs.TargetSwap, function(o, t)
-    H.slot, H.dead, H.M = o.a, false, 0
+    if H.slot > 0 then
+        H.maxBy[H.slot] = H.M
+    end
+    H.slot, H.dead = o.a, false
+    H.M = o.a > 0 and H.maxBy[o.a] or 0
     H.fresh, H.attackable = o.b == 1, o.c == 1
     restart(t)
 end)
@@ -177,13 +192,45 @@ I.On(Obs.TargetSwap, function(o, t)
 
--- WOUND damage the target took (UNIT_COMBAT, plain; everyone's hits): counted from the swap, M's numerator.
+-- WOUND damage the target took (UNIT_COMBAT, plain; everyone's hits): counted from the swap (M's numerator, the time
+-- to die's damage per second); with M known, the health moves down by amount / M, a live target never below the floor.
 I.On(Obs.TargetDamage, function(o, t)
     if H.slot == 0 or H.dead then
         return
     end
     if H.dmgT0 == 0 then
         H.dmgT0 = o.t
     end
     H.dmg = H.dmg + o.b
+    if H.M > 0 then
+        local d, floor = o.b / H.M, I.TARGET_HEALTH_FLOOR -- nonzero: M > 0 checked
+        H.est0 = H.est0 - d > floor and H.est0 - d or floor
+        H.lo0 = H.lo0 - d > floor and H.lo0 - d or floor
+        H.hi0 = H.hi0 - d > floor and H.hi0 - d or floor
+        I.Sample(rec, "modelled", H.est0, t, Obs.TargetDamage)
+    end
 end)
 
+-- A death (poll 4) or a slot taken for another GUID: the slot forgets M; the current target reads 0, observed, until
+-- the next swap.
+I.On(Obs.TargetGone, function(o, t)
+    local s = o.a
+    if s <= 0 then
+        return
+    end
+    H.maxBy[s] = 0
+    if s == H.slot then
+        H.dead, H.M = true, 0
+        H.est0, H.lo0, H.hi0 = 0, 0, 0
+        I.Sample(rec, "observed", 0, t, Obs.TargetGone)
+    end
+end)
+
+-- Combat end: an evade heals, so a live target starts over at the default, no longer known to be full.
+I.On(Obs.CombatEnd, function(o, t)
+    if not H.dead then
+        H.fresh = false
+        restart(t)
+    end
+end)
+
 --- (design §3) The current target's health fraction: the interval as folded, conf 1 - its width (0 at the default).
@@ -192,6 +239,43 @@ function I.TargetHealth(now)
     rec.est, rec.lo, rec.hi = H.est0, H.lo0, H.hi0
     rec.conf = 1 - (H.hi0 - H.lo0)
     return rec
 end
 
+-- The damage per second the current target has taken since its first WOUND: 0 without a live target, M, or a second
+-- of damage. Allocates nothing.
+local function dps(now)
+    local dt = now - H.dmgT0
+    if H.slot == 0 or H.dead or H.M <= 0 or H.dmgT0 == 0 or dt < I.PIN_GAP then
+        return 0
+    end
+    return H.dmg / dt -- nonzero: dt >= PIN_GAP (1 s)
+end
+
+--- (design §3) The current target's time to die: the health left x M / dps (lo and hi from the interval), basis
+--- `modelled`; nil while dps is 0 (VS.TTD("target") then answers its default, Families/Player.lua). Allocates nothing.
+function I.TargetTTD(now)
+    local rate = dps(now)
+    if rate <= 0 then
+        return nil
+    end
+    local k = H.M / rate -- nonzero: rate > 0 checked
+    ttdRec.est, ttdRec.lo, ttdRec.hi = H.est0 * k, H.lo0 * k, H.hi0 * k
+    ttdRec.conf, ttdRec.basis = 1 - (H.hi0 - H.lo0), "modelled" -- derived on read from the health: no sample of its own
+    return ttdRec
+end
+
+--- (design §3) Seconds until the current target's health is at fraction `p` (0..1): (est - p) x M / dps, 0 at or
+--- below it; nil while dps is 0. Allocates nothing.
+function VS.TimeToPct(p, now)
+    local rate = dps(now)
+    if rate <= 0 then
+        return nil
+    end
+    local k = H.M / rate -- nonzero: rate > 0 checked
+    local e, l, h = H.est0 - p, H.lo0 - p, H.hi0 - p
+    pctRec.est, pctRec.lo, pctRec.hi = e > 0 and e * k or 0, l > 0 and l * k or 0, h > 0 and h * k or 0
+    pctRec.conf, pctRec.basis = 1 - (H.hi0 - H.lo0), "modelled"
+    return pctRec
+end
+
 I.OnSnapshot(function(out, now)
diff --git a/src/Hekili/Virtual/State/Families/Player.lua b/src/Hekili/Virtual/State/Families/Player.lua
--- a/src/Hekili/Virtual/State/Families/Player.lua
+++ b/src/Hekili/Virtual/State/Families/Player.lua
@@ -94,7 +94,14 @@ function VS.SpellHaste(now)
     return spellHaste
 end
 
---- (spec §3.2) Time to die: the default 30 s (Hekili's DEFAULT_TTD), conf 0.
+--- (spec §3.2) Time to die: the target's from its damage taken once known (Families/TargetHealth.lua), else the
+--- default 30 s (Hekili's DEFAULT_TTD), conf 0.
 function VS.TTD(unit, now)
+    if unit == "target" then
+        local r = I.TargetTTD(now)
+        if r then
+            return r
+        end
+    end
     return ttd
 end
diff --git a/src/Hekili/Virtual/State/Sources/Target.lua b/src/Hekili/Virtual/State/Sources/Target.lua
--- a/src/Hekili/Virtual/State/Sources/Target.lua
+++ b/src/Hekili/Virtual/State/Sources/Target.lua
@@ -4,6 +4,7 @@
 -- UnitCanAttack) straight to the log, then walks the new target's auras; poll 4 logs `TargetGone` for a dead target;
 -- the target's UNIT_SPELLCAST_* events become `TargetCast` observations by castBarID (plain; the spellID and castGUID
 -- are secret on the target).
+-- The target's UNIT_COMBAT WOUND amounts become `TargetDamage` (b: the amount; target-health design §2.3c).
 -- Credits: secret-value handling after Catnip's (Durts) research.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Target.lua.
 
@@ -81,6 +82,15 @@ S.Poll(4, function(api, t)
     end
     dead = d
 end)
 
+-- The target's damage taken (target-health design §2.3c): UNIT_COMBAT's WOUND amount, plain and victim-side (every
+-- attacker's hits count, as a time to die needs). Registered for every unit, as Events/Rows.lua and Attackers.lua
+-- register it: a "target" registration would narrow the client's to the target and starve Attackers.lua of the player's.
+S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount)
+    if unit == "target" and act == "WOUND" and type(amount) == "number" and amount > 0 then
+        Stage(Obs.TargetDamage, t, 0, amount)
+    end
+end)
+
 -- `fifth`: the event carries interruptedBy before its castBarID (INTERRUPTED, CHANNEL_STOP).
 local function cast(of, fifth)
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`
Expected: `393 successes / 0 failures / 0 errors / 0 pending`. `cleu_rows_spec` keeps passing: the new UNIT_COMBAT handler only stages and adds no unit registration.

- [ ] **Step 5: Verify**

```bash
stylua src/Hekili/Virtual/State/Families/TargetHealth.lua src/Hekili/Virtual/State/Families/Player.lua \
  src/Hekili/Virtual/State/Sources/Target.lua tests/Virtual/State/target_health_spec.lua   # [no change]
make check LUA_ENV=$HOME/src/hekili/.lua
# lint: 0 warnings / 0 errors in 101 files; fmt-check silent; typecheck: no problems;
# test: 393 successes / 0 failures / 0 errors / 0 pending; syntax silent; api-check ok in 64 loaded files, inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/Families/TargetHealth.lua src/Hekili/Virtual/State/Families/Player.lua \
  src/Hekili/Virtual/State/Sources/Target.lua tests/Virtual/State/target_health_spec.lua
git commit -m "feat(vs): target health follows the target's WOUND damage; M per memory slot, death and combat-end resets; VS.TTD/VS.TimeToPct for the target (target-health design §2.3c-d, §3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-target-health`

---
### Task 3: Named core edit E4: Hekili's GetTTD and GetTimeToPct for the target

Design §3 (facade unchanged; E4), §6 test 7. Targets.lua cannot load headless. The spec compiles the two edited functions out of the file text and runs them, with Targets.lua's upvalues and the facade reads supplied as stub functions in an environment table.

**Files:**
- Modify: `src/Hekili/Targets.lua` (named core edit E4)
- Test: `tests/Virtual/State/target_health_spec.lua`

**Interfaces:**
- Consumes: `ns.VirtualState.TTD("target", now)` (a record; basis "default" means none), `ns.VirtualState.TimeToPct(fraction, now)` (record or nil), the facade's `UnitHealth`/`UnitHealthMax` rows (unchanged).
- Produces: `Hekili:GetTTD("target")` and `Hekili:GetTimeToPct("target", pct)` → `ceil(est), 3` once the belief has one; otherwise Hekili's tracker, unchanged.

- [ ] **Step 1: Write the failing spec**

```diff
diff --git a/tests/Virtual/State/target_health_spec.lua b/tests/Virtual/State/target_health_spec.lua
--- a/tests/Virtual/State/target_health_spec.lua
+++ b/tests/Virtual/State/target_health_spec.lua
@@ -29,17 +29,36 @@ local function def()
     }
 end
 
+-- Hekili's GetTTD or GetTimeToPct (Targets.lua, named core edit E4) compiled alone, its upvalues and the facade reads
+-- it makes from `env`.
+local function targetsFn(name, env)
+    local f = assert(io.open("src/Hekili/Targets.lua"))
+    local src = f:read("*a")
+    f:close()
+    local body = assert(src:match("\n    (function Hekili:" .. name .. "%(.-\n    end)\n"), name)
+    local chunk = assert(loadstring(body, name))
+    setfenv(chunk, env)
+    chunk()
+    return env.Hekili[name]
+end
+
 describe("target health", function()
-    local ns, VS, I, S, Obs, ReadOf, api, ctl
+    local ns, VS, I, S, Obs, ReadOf, api, ctl, saved
 
     before_each(function()
         api, ctl = fake.new()
+        saved = rawget(_G, "GetTime") or false
+        rawset(_G, "GetTime", api.GetTime) -- the facade's clock (Facade.lua resolves it at load)
         ns = load.module()
         VS, I = ns.VirtualState, ns.VirtualStateInternal
         S, Obs, ReadOf = I.Sources, VS.Obs, I.ReadOf
         ctl.known[SMITE], ctl.known[SLAM] = true, true
         I.api = api
         I.Build(def(), 1) -- the build's swap: Creature-1 takes slot 1, never held before, attackable
     end)
 
+    after_each(function()
+        rawset(_G, "GetTime", saved or nil)
+    end)
+
     local function obs(kind, t, a, b, c)
         S.Direct(kind, t, a, b, c)
     end
@@ -140,4 +159,44 @@ describe("target health", function()
         assert.are.same({ 1, false, 0, "default" }, { I.th.slot, I.th.fresh, I.th.dmg, VS.Health("target", 101).basis })
         within(1000, I.th.M, 1e-6)
     end)
+
+    it("answers the facade's target health and Hekili's GetTTD/GetTimeToPct from the belief", function()
+        local env = {
+            Hekili = {},
+            state = { target = { is_dummy = false } },
+            db = {},
+            VirtualState = VS,
+            GetTime = api.GetTime,
+            UnitIsTrivial = function()
+                return false
+            end,
+            UnitLevel = function()
+                return 60
+            end,
+            UnitExists = function()
+                return true
+            end,
+            UnitCanAttack = function()
+                return true
+            end,
+            UnitGUID = function()
+                return "Creature-1"
+            end,
+            ceil = math.ceil,
+            TRIVIAL = 5,
+            FOREVER = 300,
+        }
+        local GetTTD, GetTimeToPct = targetsFn("GetTTD", env), targetsFn("GetTimeToPct", env)
+        -- no damage per second yet: Hekili's own tracker, which knows no enemy here (its defaults)
+        assert.are.equal(300, GetTTD(env.Hekili, "target"))
+        within(210, GetTimeToPct(env.Hekili, "target", 10), 1e-9)
+        anchor()
+        obs(Obs.TargetDamage, 11, 0, 50) -- health 0.15; 850 damage over the 8 s since the first WOUND
+        I.Fold(11)
+        ctl.now = 11
+        within(15, ns.Facade.UnitHealth("target"), 1e-6)
+        assert.are.equal(100, ns.Facade.UnitHealthMax("target"))
+        assert.are.same({ 2, 3 }, { GetTTD(env.Hekili, "target") }) -- ceil(0.15 x 1000 / 106.25 = 1.41)
+        assert.are.same({ 1, 3 }, { GetTimeToPct(env.Hekili, "target", 10) }) -- ceil(0.05 x 1000 / 106.25 = 0.47)
+    end)
 end)
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `$HOME/src/hekili/.lua/bin/busted tests/Virtual/State/target_health_spec.lua`
Expected: `6 successes / 1 failure / 0 errors`. Test 7 fails at `GetTTD`: the unedited function returns its 300 default after the slope.

- [ ] **Step 3: Write the implementation**

```diff
diff --git a/src/Hekili/Targets.lua b/src/Hekili/Targets.lua
--- a/src/Hekili/Targets.lua
+++ b/src/Hekili/Targets.lua
@@ -13,6 +13,7 @@
 local UnitIsTrivial, UnitIsUnit, UnitLevel, UnitName = Facade.UnitIsTrivial, Facade.UnitIsUnit, Facade.UnitLevel, Facade.UnitName
 local UnitPhaseReason, UnitTokenFromGUID = Facade.UnitPhaseReason, Facade.UnitTokenFromGUID
 local Hekili = _G[addon]
+local VirtualState = ns.VirtualState -- Forever E4: the target's time to die (GetTTD, GetTimeToPct)
 
 local class = Hekili.Class
 local state = Hekili.State
@@ -1257,6 +1258,12 @@
     function Hekili:GetTTD( unit, isGUID )
         if state.target.is_dummy then return 180 end
 
+        -- Forever E4: the target's health is secret; VirtualState's time to die from its damage taken, once it has one.
+        if unit == "target" and not isGUID then
+            local vs = VirtualState.TTD( "target", GetTime() )
+            if vs and vs.basis ~= "default" then return ceil( vs.est ), 3 end
+        end
+
         local default = ( isGUID or UnitIsTrivial(unit) and UnitLevel(unit) > -1 ) and TRIVIAL or FOREVER
         local guid = isGUID and unit or UnitExists(unit) and UnitCanAttack("player", unit) and UnitGUID(unit)
 
@@ -1292,6 +1299,12 @@
         if percent >= 1 then
             percent = percent / 100
         end
 
+        -- Forever E4: as in GetTTD, the target's from VirtualState once it has one.
+        if unit == "target" then
+            local vs = VirtualState.TimeToPct( percent, GetTime() )
+            if vs then return ceil( vs.est ), 3 end
+        end
+
         if not guid then return default end
 
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`
Expected: `394 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify**

```bash
stylua tests/Virtual/State/target_health_spec.lua           # [no change] (Targets.lua is in .styluaignore)
make check LUA_ENV=$HOME/src/hekili/.lua
# lint: 0 warnings / 0 errors in 101 files; fmt-check silent; typecheck: no problems;
# test: 394 successes / 0 failures / 0 errors / 0 pending; syntax silent; api-check ok in 64 loaded files, inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Targets.lua tests/Virtual/State/target_health_spec.lua
git commit -m "fix(core): GetTTD/GetTimeToPct answer VirtualState's target time to die once it has one (E4; target-health design §3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-target-health`

---
### Task 4: Execute's `healthGate`, the zero-allocation coverage, the docs

Design §2.1 (the field), §4 and §6 test 8 (allocation), and the status line.

**Files:**
- Modify: `src/Hekili/Forever/Classes/Warrior.lua`, `docs/superpowers/specs/2026-10-16-target-health-design.md`, `docs/forever-facade-notes.md`
- Test: `tests/Forever/warrior_spec.lua`, `tests/Virtual/State/alloc_spec.lua`

**Interfaces:**
- Consumes: Tasks 1-3.
- Produces: `class.abilities.execute.healthGate == 0.2` (raw; RegisterAbility stores non-function fields raw, Engine/Spec.lua:780-788).

- [ ] **Step 1: Write the failing specs**

```diff
diff --git a/tests/Forever/warrior_spec.lua b/tests/Forever/warrior_spec.lua
--- a/tests/Forever/warrior_spec.lua
+++ b/tests/Forever/warrior_spec.lua
@@ -323,5 +323,6 @@
         local a = w.abilities
         assert.are.same({ nil, "berserker_stance" }, { a.thunder_clap.buff, a.thunder_clap.nobuff })
         assert.are.same({ nil, "defensive_stance" }, { a.execute.buff, a.execute.nobuff })
+        assert.are.equal(0.2, a.execute.healthGate) -- VirtualState's target health (Families/TargetHealth.lua)
         assert.are.same({ "battle_stance", nil }, { a.spearing_strike.buff, a.spearing_strike.nobuff })
     end)
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -1,6 +1,7 @@
 -- tests/Virtual/State/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
--- usability, own casts, UNIT_AURA) with a drain every tick against the fake spec, every accessor and every facade
--- policy and passthrough called, every combat-log row delivered to a subscriber: VirtualState allocates nothing.
+-- usability flipping on a health-gated spender, own casts, UNIT_AURA, the target's UNIT_COMBAT) with a drain every
+-- tick against the fake spec, every accessor and every facade policy and passthrough called, every combat-log row
+-- delivered to a subscriber: VirtualState allocates nothing.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local fs = require("Virtual.State.helpers.fake_spec")
@@ -54,24 +55,32 @@
             GetInfo()
         end)
         sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+        h.Class.abilities.rend.healthGate = 0.2 -- a health-gated spender (Families/TargetHealth.lua)
+        ctl.known[fs.REND] = true -- known: its NOT answers can bound the target's health
         VS.Start(api)
         VS.SpecChanged()
+        ctl.guid.target = "Creature-2" -- a target never held before: its first flip learns M, then WOUNDs move it
+        ctl.Fire("PLAYER_TARGET_CHANGED")
         ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 1e9, applications = 0 }
-        ctl.usable[fs.REND] = { true, false }
+        local USABLE, NOT_USABLE = { true, false }, { false, false }
+        ctl.usable[fs.REND] = USABLE
         ctl.cooldown[fs.REND] = { isActive = false, isOnGCD = true }
         ctl.Fire("PLAYER_REGEN_DISABLED")
         local POWER = "RAGE"
         local function step(i)
             ctl.now = ctl.now + 0.1
-            local k = i % 5
+            local k = i % 6
             if k == 0 then
                 ctl.Fire("PLAYER_SWING", 2.6, 0)
             elseif k == 1 then
                 ctl.Fire("UNIT_POWER_FREQUENT", "player", POWER)
             elseif k == 2 then
+                ctl.usable[fs.REND] = i % 4 == 2 and NOT_USABLE or USABLE -- every other usability event flips
                 ctl.Fire("SPELL_UPDATE_USABLE")
             elseif k == 3 then
                 ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast", fs.REND)
-            else
+            elseif k == 4 then
                 ctl.Fire("UNIT_AURA", "player")
+            else
+                ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 1)
             end
@@ -95,6 +104,8 @@
             VS.SpellHaste(t)
             VS.Health("player", t)
             VS.HealthMax("player")
+            VS.Health("target", t)
+            VS.TimeToPct(0.2, t)
             VS.TTD("target", t)
             VS.Totem(1, t)
             VS.TotemFacts(1)
@@ -114,6 +125,7 @@
             Facade.GetManaRegen()
             Facade.UnitHealth("player")
             Facade.UnitHealth("nameplate1")
+            Facade.UnitHealth("target")
             Facade.UnitHealthMax("target")
             Facade.UnitStat("player", 1)
             Facade.GetCombatRating(10)
```

- [ ] **Step 2: Run the specs**

Run: `$HOME/src/hekili/.lua/bin/busted tests/Forever/warrior_spec.lua tests/Virtual/State/alloc_spec.lua`
Expected:
- `warrior_spec`'s stance case fails (`healthGate` is nil).
- `alloc_spec` already passes at 0 bytes: its new paths are Tasks 1-3's code, so it is coverage, not a red.

Two notes on the allocation run:
- Every sixth step is a WOUND, and every other usability event flips Rend. A NOT is guarded once a swing lifts the believed rage `lo` to Rend's 10, so flips occur. The first one on the fresh `Creature-2` learns M; the WOUNDs then exercise the slope, the floor and the TTD.
- If `alloc_spec` reports bytes: the rows pair the target's WOUND with Rend's cast within `PAIR_WINDOW`. Bisect by dropping the UNIT_COMBAT branch. A row emit that allocates is a pre-existing bug, so report it rather than widening this task.

- [ ] **Step 3: Write the implementation**

```diff
diff --git a/src/Hekili/Forever/Classes/Warrior.lua b/src/Hekili/Forever/Classes/Warrior.lua
--- a/src/Hekili/Forever/Classes/Warrior.lua
+++ b/src/Hekili/Forever/Classes/Warrior.lua
@@ -991,7 +991,8 @@
         spendType = "rage",
 
         startsCombat = true,
         known = knows(EXECUTE),
         nobuff = "defensive_stance",
+        healthGate = 0.2, -- usable at or below 20% of the target's health: VirtualState's target health reads it
 
         usable = function()
             return reactive(EXECUTE), "requires target health under 20 percent"
diff --git a/docs/superpowers/specs/2026-10-16-target-health-design.md b/docs/superpowers/specs/2026-10-16-target-health-design.md
--- a/docs/superpowers/specs/2026-10-16-target-health-design.md
+++ b/docs/superpowers/specs/2026-10-16-target-health-design.md
@@ -1,4 +1,5 @@
 # Target health from health-gated usability (design note, 2026-10-16)
 
-Status: DRAFT, awaiting the user's checkpoint results (§7, lines 2 and 4 decide §2.3b and §2.3a). Base: 605b6dcb.
+Status: IMPLEMENTED, the conservative branches: a short answer (c = 1) is no health signal (§2.3a) and no plain max is
+read (§2.3b); §7 lines 2 and 4 decide those two follow-ups. Base: 605b6dcb.
 Paths are under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`.
diff --git a/docs/forever-facade-notes.md b/docs/forever-facade-notes.md
--- a/docs/forever-facade-notes.md
+++ b/docs/forever-facade-notes.md
@@ -247,5 +247,8 @@
 - GCD spell 61304 -> 29515: `Classes.lua` 2469 (`id = 61304`), `UI.lua` 1493 and 1694, `Events.lua` 1675.
 - The enemy-scan health comparison: `Targets.lua` 434 and 511.
 - TTD: `Targets.lua` 1164-1605 needs another source of health deltas.
+  - The target's (named core edit E4, 2026-10-16): `GetTTD` and `GetTimeToPct` answer VirtualState's belief once it has
+    one (`VS.TTD`/`VS.TimeToPct`: M learned at a health-gated flip, WOUND damage per second;
+    Families/TargetHealth.lua); `UnitHealth("target")` answers that health x 100 through its existing row.
 - Spec identity (pseudo-spec 1491): `Classes.lua` 3077-3362 `SpecializationChanged`. `NewSpecialization` now takes
   identity from the `ns.Specializations[ 1491 ].forever` row (Task 11b); what remains:
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`
Expected: `394 successes / 0 failures / 0 errors / 0 pending`. `engine_load_spec` keeps passing: `healthGate` is a number, not a function.

- [ ] **Step 5: Verify**

```bash
stylua src/Hekili/Forever/Classes/Warrior.lua tests/Forever/warrior_spec.lua tests/Virtual/State/alloc_spec.lua   # [no change]
make check LUA_ENV=$HOME/src/hekili/.lua
# lint: 0 warnings / 0 errors in 101 files; fmt-check silent; typecheck: no problems;
# test: 394 successes / 0 failures / 0 errors / 0 pending; syntax silent; api-check ok in 64 loaded files, inventory diff empty
grep -nE "Warrior|Execute|5308" src/Hekili/Virtual/State/Families/TargetHealth.lua   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Forever/Classes/Warrior.lua tests/Forever/warrior_spec.lua tests/Virtual/State/alloc_spec.lua \
  docs/superpowers/specs/2026-10-16-target-health-design.md docs/forever-facade-notes.md
git commit -m "feat(warrior): Execute declares healthGate = 0.2; alloc spec covers the target health paths; target-health design marked implemented

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                          # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-target-health`

---
### Task 5: CHECKPOINT: target health in game (design §7), deferred to the user

No code unless an answer calls for it. An answer that changes code is its own commit with the verification block. Use an open-world mob: training dummies answer a fixed 180 and may never drop below 20%. A new TOC file requires a full client restart.

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin forever-target-health
git -C ~/src/hekili checkout --detach forever-target-health
```

Then fully restart the client.

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, and report each answer**

The design's §7 lines, verbatim:

1. Execute flips vs health (in combat, watch the bar; the frame prints each change):
`/run local f=CreateFrame("Frame")f:SetScript("OnUpdate",function()local u,n=C_Spell.IsSpellUsable(5308)if u~=f.u or n~=f.n then f.u,f.n=u,n VSCopy(format("%.2f",GetTime()),u,n)end end)`
2. Max readability, out of combat then in combat:
`/run local m=UnitHealthMax("target")VSCopy(InCombatLockdown(),issecretvalue(m),not issecretvalue(m) and m,C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret and C_Secrets.ShouldUnitHealthMaxBeSecret("target"))`
3. Damage amounts summed to the kill (compare with the mob's max):
`/run local s=0 local f=CreateFrame("Frame")f:RegisterUnitEvent("UNIT_COMBAT","target")f:RegisterEvent("PLAYER_TARGET_CHANGED")f:SetScript("OnEvent",function(_,e,u,a,_,n)if e=="UNIT_COMBAT"then if a=="WOUND"then s=s+n end else VSCopy("sum",s)s=0 end end)`
4. Short vs health: with under 15 rage, line 1 on a mob above 20% and below 20%; repeat in Defensive Stance (does short mean at or below the gate; does a wrong stance give false,false).

Plus one line of ours to read the belief (fresh mob, after Execute lights up, then a few hits):
`/run local V=Hekili.Virtual.State local h,d=V.Health("target",GetTime()),V.TTD("target",GetTime()) VSCopy(h.est,h.lo,h.hi,h.basis,d.est,d.basis)`

| Line | Decides | Answer → action |
|---|---|---|
| 1 | the flip exists and is prompt | flips at about 20% → none; no flip or a late one → report (the pin's premise) |
| 2 | §2.3b | `UnitHealthMax("target")` plain in combat → follow-up: a read at the swap and in poll 1 sets M observed at the "Hook (design §2.3b)" comment; secret → none |
| 3 | M's scale | the sum ≈ the mob's max → none; far off → report (amounts not full damage: M and the TTD scale wrong) |
| 4 | §2.3a | short only at or below 20% → follow-up: the c = 1 `shortcut:` branch joins the usable branch; a wrong stance gives `false,false` → the guard-3 premise holds; else report |
| ours | the belief moves | `0.2 0.2 0.2 pinned` after the flip, then modelled values falling; `d.basis` `modelled` once M is known → none |

Known limits (say them with the results):
- Health above 20% stays at the default until a flip on a fresh target teaches M.
- A pre-damaged target overestimates M (design §8).
- `fight_remains` keeps Hekili's tracker.
- A NOT is a bound only while the believed rage `lo` covers Execute's cost, so rage beliefs with a wide interval make flips rare.

Fix what the user reports, then repeat the affected lines. Continue only when the user confirms. When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

**1. Coverage of the design**

| Design | Task |
|---|---|
| §1 facts (facade rows unchanged, ability table raw, TargetSwap slots, UNIT_COMBAT plain) | 1, 2 (no Adapter change) |
| §2.1 `healthGate` field, `buff`/`nobuff` guard aura index (0 / -1) | 1 (index); 4 (Execute's field) |
| §2.2 family, scalars, `maxBy`, records "health target"/"ttd target" | 1, 2 |
| §2.3a usable / flip pin / rung / NOT bound, M learned on a fresh target | 1 (short branch: conservative `shortcut:`) |
| §2.3b plain max | deferred: hook comment in Task 1; §7 line 2 in Task 5 |
| §2.3c `Obs.TargetDamage = 35`, UNIT_COMBAT WOUND, slope, floor 0.02 | 1 (enum, count), 2 (source, slope) |
| §2.3d resets: swap (fresh flag, `maxBy`), TargetGone 0 observed, CombatEnd default | 1 (swap), 2 (rest) |
| §3 `VS.Health("target")`, facade unchanged, `VS.TTD`, `VS.TimeToPct`, E4 | 1, 2, 3 |
| §4 allocation | 1-2 (code), 4 (alloc_spec) |
| §5 guards 1-5 | 1 (tests 2, 3; guard 5 via TargetSwap c, test 6 reads it) |
| §6 tests 1-8 | 1: 1-3; 2: 4-6; 3: 7; 4: 8 |
| §7 checkpoint | 5 |
| §9 placement (TOC after TargetCast.lua) | 1 |

**2. Placeholder scan:** no "TBD", "TODO", "implement later" or "similar to Task N". Every code step is a `git apply` patch, and every test step states its busted counts. The counts are derived, not replayed (see "How this plan was checked").

**3. Names across tasks:** these are spelled the same in every task and in the checkpoint:
- `healthGate`, `I.th` and its fields, `I.TargetHealth`, `I.TargetTTD`, `VS.TimeToPct`
- `I.TARGET_HEALTH_FLOOR`, `Obs.TargetDamage`
- the records "health target", "ttd target", "time to pct target"
- `-- Forever E4:`, `targetsFn`, `anchor`, `GATED`

**4. Review Focus:** each line has its pinned test or check:
- 1: review only (the fake does not filter units)
- 2: test 2
- 3: tests 2 and 3
- 4: alloc_spec
- 5: test 7
- 6: Task 4's grep and api-check

**Concerns for the orchestrator:**
- (a) The patches were not replayed. The base busted count is 387 (measured), not 384.
- (b) The UNIT_COMBAT registration must stay `nil`-unit (Review Focus 1).
- (c) Guard 2 uses the believed rage `lo`. If rage's interval runs wide in combat, guarded NOTs and therefore flips may be rare, so M is rarely learned. The checkpoint line "ours" shows it. The follow-ups are §7 line 4 (short as a signal) and line 2 (plain max).
- (d) At login with a target already held, Start's swap takes the slot and the first build's swap reads it as not fresh, so no M until a retarget.
- (e) `alloc_spec` now fires the target's WOUND 0.2 s after Rend's cast, which may pair a SPELL_DAMAGE row. Rows are designed allocation-free, but this is the first time the alloc test exercises a paired target outcome.

### Critical Files for Implementation
- src/Hekili/Virtual/State/Families/TargetHealth.lua (new)
- src/Hekili/Virtual/State/Sources/Target.lua
- src/Hekili/Virtual/State/Families/Player.lua
- src/Hekili/Targets.lua
- tests/Virtual/State/target_health_spec.lua (new)

