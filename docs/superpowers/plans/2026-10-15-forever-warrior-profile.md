# Forever Warrior Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `Forever/Warrior.lua` (pseudo-spec 1491) up to the full Classic Warrior kit with Forever's own spell data: every Classic ability, aura and talent with Forever IDs, ranks, costs, cooldowns and durations, Forever's Victory Rush and Spearing Strike, Bloodrage's rage over time, stances, and Arms, Fury and Protection priorities.

**Architecture:** One class file registers everything once; Hekili's simulation and VirtualState both consume it (spec §1 decision 2). The only VirtualState change is aura-gated regen in the resources family (Hekili's regen-model entries `{ aura, interval, value }`, forwarded by the adapter), which Bloodrage needs. Stances come from the plain `GetShapeshiftForm`/`GetShapeshiftFormInfo` reads in `reset_precast`; reactive windows (Execute, Revenge, Victory Rush) from the plain `C_Spell.IsSpellUsable`; Overpower's from Forever's 5 s player aura 1282733. The priorities are SimC-style text in `tools/make_pack.lua`, which prints the three share strings; a headless spec loads the class file against a recording stand-in for Hekili and checks the registrations against the DB2 and the strings against the generator.

**Replay base:** `virtualstate-phase1` at `0403af6bfa98bfae203308565f56efa6f758f6cd` (see "How this plan was checked").

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, `lua5.1`/`luac5.1`, the vendored LibStub, LibDeflate and AceSerializer (for `tools/make_pack.lua`), the `wowdb` CLI (Forever DB2 build 1.60.1.70338; every value below was looked up with it).

**Spec:** `docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md` (binding: §1 decision 2, §3.6 `Track{}`, §6.1 resources, §6.3 auras, §6.6 talents, §10, §13 credits). Read with it: `docs/superpowers/plans/2026-10-14-hekili-virtualstate-phase1.md` (house style; Task 4 the regen model, Task 6 talents and `Track`, Task 7 the first Warrior file and `tools/make_pack.lua`, Task 8 the facade and `tools/api_inventory.txt`, Tasks 9 and 9b the apply through the spec and the APL warnings), `docs/forever-facade-notes.md` (which game names are secret or absent on Forever). Hekili's Classic Warrior profile is `git show origin/classic:Classic/Warrior.lua` (1781 lines) with `Classic/APLs/WarriorArms.simc` and `Classic/APLs/WarriorFury.simc`.

## How this plan was checked

Every file and patch in this plan was written and run before the plan was saved: the four code tasks were replayed in order on a clone of the `forever-warrior-profile` worktree at `0403af6b` (`virtualstate-phase1` after Task 9b and the final review wave; earlier replays at `799e74b3` were re-run on it, and fix round 1 re-ran all four tasks from this plan's own text), each patch applied with `git apply`, and after each task the verification block passed with the counts this plan states. The red steps were run too; their failure counts are the replay's. The in-game checkpoint (Task 5) cannot be replayed headless; it is the user's.

Counts are at base `0403af6b` (91 busted successes, luacheck 63 files, 43 loaded files). On a later base, add the same deltas to that base's counts: Task 1 +5 successes; Task 2 +8 successes and +2 luacheck files; Task 3 +1; Task 4 +3.

## Global Constraints

- Repository `~/src/hekili`; work only in the worktree `~/src/hekili/.claude/worktrees/forever-warrior-profile`, branch `forever-warrior-profile`, created from `virtualstate-phase1` at 0403af6b (both already exist; no creation step). Git from WSL only. Push `forever-warrior-profile` to `origin` after each task's green verification and clean review (`git push origin forever-warrior-profile`); never push to `forever`, `classic` or `virtualstate-phase1`; never merge; never force-push.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, naming the model that wrote the commit; the commit commands below are written for Claude Opus 5.5. An implementer running on another model replaces `Claude Opus 5.5` in each commit command with its own model's name before running it.
- No LICENSE or README changes, in any repository. No changes to `archive/`.
- Taco Dog Forever is read only. Clean-room direction: TDF mechanics may be ported into Hekili with credit in the file header (spec §13); Hekili code never flows into TDF. The Classic profile is Hekili's own code: port it with Hekili's header conventions (a `Credits:` line naming the source path), no extra licence text.
- Secret safety (spec §4.5): no VirtualState code compares or does arithmetic on a client value without `issecretvalue()` first, none uses `a and b or c` on a possibly-secret value, and no secret value leaves the sources or the facade. A class file reads directly only names outside `tools/api_inventory.txt` (the plain set; `tools/check_api_reads.sh` enforces it); anything in the inventory goes through `ns.Facade`. This plan's class file reads `C_SpellBook.IsSpellKnown`, `C_Spell.IsCurrentSpell`, `C_Spell.IsSpellUsable`, `GetShapeshiftForm`, `GetShapeshiftFormInfo` and `UnitClassBase`, all plain (`docs/forever-facade-notes.md`).
- Performance (spec §2): VirtualState accessors, the fold, Flush, the polls and the facade policies allocate nothing; every record and array is allocated when the tracked set is built (`VirtualState.SpecChanged`). `VirtualState/spec/alloc_spec.lua` and this plan's resources case assert 0 bytes.
- TOC order (spec §9) is unchanged: `Forever\Warrior.lua` is already listed (`Hekili.toc:48`), after Hekili's files. No new TOC entries.
- Scope: nothing from the Phase 2 investigation or the Phase 3 event bus, nothing listed in spec §14, no new VirtualState source. No SoD rune spells ("Engrave …", Raging Blow, Quick Strike, Devastate, Shockwave, Meathook, Commanding Shout, Rallying Cry, Enraged Regeneration).
- Tools: `BUSTED=~/src/TacoDogForever/.lua/bin/busted`, `LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`, `lua-language-server` from `~/.local/share/mise/installs/lua-language-server/latest/bin/`, `lua5.1` and `luac5.1` from the system. All commands run from the worktree root.
- Every task ends with the verification block (busted, luacheck, `tools/check_api_reads.sh`, the api-inventory diff, LuaLS `--checklevel=Error`, `luac5.1 -p` on the touched Lua files), then a commit. The block is written out in each task with that task's expected results.
- The user runs the game. The step marked **CHECKPOINT** stops execution: the orchestrator (not a subagent) points the client's checkout at the branch with `git -C ~/src/hekili checkout --detach forever-warrior-profile` (the client reads the local checkout; no push is needed for it), asks the user to run the exact lines given, and waits for the results. When the session ends, `git -C ~/src/hekili checkout forever` restores the main checkout.
- Style: VirtualState files and specs use the TDF layout (4 spaces, no spaces inside parentheses, 120 columns); `Forever/Warrior.lua` and `tools/make_pack.lua` keep Hekili's style (spaces inside parentheses in the class file), as Phase 1 Task 7 wrote them.

## Review Focus

1. **Bloodrage's aura gone early or never seen** (the walk drops it, a target swap, a `/reload`): believed rage must stop gaining at the believed expiry or removal, never keep ticking. Test: Task 1, `resources_spec` "stops when the aura is believed gone early" and "adds nothing while the aura is down".
2. **The resources family's advance and `VS.Power` projection with an aura-gated entry** run on every fold and every facade read: they must allocate nothing. Test: Task 1, `resources_spec` "allocates nothing advancing or projecting through an entry".
3. **A character below the level that teaches a spell** (Forever's beta cap is 30; Mortal Strike, Bloodthirst, Shield Slam, Whirlwind are 36 to 60): an unknown spell or rank must never be recommended, and a known lower rank must be the one queried. Test: Task 2, `warrior_spec` "registers the Classic kit …" (every ability carries `known`) and "recommends Execute only inside the client's usability window, at the known rank".
4. **A priority condition that reads a secret value or names nothing registered** (target health, time to die, a misspelt aura, a setting that was left out): it is silently dead on Forever. Test: Task 4, `warrior_spec` "writes priorities that name only registered abilities, auras, talents, settings and lists" (uses Task 9b's `VS.AplSecretToken`).
5. **A pack string edited by hand or a generator change not pasted back**: the shipped priority silently differs from its readable source. Test: Task 4, `warrior_spec` "registers the Arms, Fury and Protection priorities exactly as tools/make_pack.lua prints them".

Named, not test-pinned (no modelling change, ruling W9): **Heroic Strike or Cleave queued in Hekili's own simulation.** `onNextSwing` is read only by VirtualState; Hekili's `state` spends the cost at the press and still adds the replaced swing's rage, so its forward projection is one swing of rage optimistic per queued strike (and a dual wielder's off-hand swings are missing from both models) until VirtualState's next drain corrects the belief. Checkpoint Q9 compares Hekili's `state.rage.current` after a press with the rage bar.

## File structure

```
VirtualState/Families/Resources.lua   Task 1  aura-gated regen entries (built from each resource's `auraRegen`)
VirtualState/Adapter.lua               Task 1  buildDef forwards a resource's player-aura regen entries
VirtualState/spec/resources_spec.lua   Task 1  the aura-gated regen cases
VirtualState/spec/adapter_spec.lua     Task 1  the forwarding case
Forever/Warrior.lua                    Tasks 2-4  the class file (kit, talents, priorities)
Forever/spec/helpers/load_warrior.lua  Task 2  loads the class file headless against a recording stand-in
Forever/spec/warrior_spec.lua          Tasks 2-4  the class file's registrations against the DB2
tools/make_pack.lua                    Task 4  the three priorities' SimC-style text and the share-string printer
.busted, .luacheckrc                   Task 2  Forever/spec in busted's roots; the Warrior's state names for luacheck
```

## Order and checkpoint

Tasks 1 to 4 in order (Task 2's resource entry needs Task 1's forwarding to reach VirtualState; Tasks 3 and 4 extend Task 2's files), then Task 5, the one in-game CHECKPOINT. Deliberately not built (do not add them; a review should not flag them):
- Classic's `auto_attack` (6603): not a Warrior spell; Classic's version is a recommendation trick with a fake 9 s cooldown, and no priority uses it.
- Classic's combat-log tracking of dodges and blocks (Classic/Warrior.lua:441-455): `CombatLogGetCurrentEventInfo` is absent on Forever; Overpower uses Forever's aura and Revenge its usability instead.
- `my_battle_shout` and the `shout`/`stance` alias auras: `my_battle_shout` reads aura data through `FindUnitBuffByID` (secret in combat); the aliases served only it and `swap_stance`'s fallback.
- Classic's adaptive Whirlwind (`ww_breakpoint`) and Bloodthirst-in-execute (`bt_over_exec`) with their settings: they compute from attack power and weapon damage, secret on Forever, and the Fury execute entry also read `target.time_to_die`.
- Stance rage modifiers (Classic's Defensive Stance factor 0.95, Classic/Warrior.lua:14-24, and any Berserker Stance effect): VirtualState's calibration absorbs them; Hekili's own forecast does not, a few percent of white-swing rage.
- An off-hand swing source for a dual-wielding Fury warrior: VirtualState models one swing-paid hand per resource (`VirtualState/Adapter.lua` buildDef takes the first `swing` entry); calibration absorbs the off hand. A `shortcut:` comment in the class file names it.
- Talent cooldown and duration modifiers whose higher ranks the DB2 lacks (Improved Intercept, Improved Slam, Improved Disarm, Improved Shield Wall, Booming Voice): only rank 1 of each talent is in the Forever DB2, and a linear extrapolation gives impossible values (Improved Shield Wall rank 1 is -660 s on a 900 s cooldown). Cost modifiers are modelled (rank 1 x rank, floored at 0) because the checkpoint can compare them with the client's plain cost.

---

### Task 1: Aura-gated regen in the resources family

Bloodrage (2687) gives 10 rage at once (DB2 effect 0: energize 100, rage) and applies aura 29131, which gives 1 rage every second for 10 s (DB2 29131 effect 0: periodic energize, base 10, period 1000 ms). Hekili models the second part as a regen-model entry `{ aura = "bloodrage", interval = 1, value = 1, last = fn }` (State.lua:1210-1235 forecasts it; Classic/Warrior.lua:28-40 registers it); VirtualState's resources family applies only continuous regen and swing steps today, so believed rage would miss it. This task adds the Hekili regen-model shape to the family: `value` every `interval` seconds from the aura's application while the player's aura is believed up (the aura family's `exp0`/`applied`), in the advance hook (so the fold order is unchanged: an observation at t is applied after the clock reaches t) and in `VS.Power`'s projection, with the gain added to `pinDelta` like our own casts' changes so it is kept out of the next regen measurement. Entries are flat preallocated arrays rebuilt at `SpecChanged`; nothing allocates per fold.

**Files:**
- Modify: `VirtualState/Families/Resources.lua` (header :2-5, `local abs` :13, before :54, after `I.TRACKED.resource = R.type` :95, the advance hook :110-121, `VS.Power` :322-335, the snapshot line :378-385)
- Modify: `VirtualState/Adapter.lua` (buildDef's resource loop, :102-119)
- Test: `VirtualState/spec/resources_spec.lua` (a new `describe` at the end), `VirtualState/spec/adapter_spec.lua` (a new `it` before "feeds the cast history…", :77)

**Interfaces:**
- Consumes: `I.auras.exp0[1][j]`, `I.auras.applied[1][j]` (Phase 1 Task 5; unit 1 is always `"player"`, `VirtualState/Adapter.lua` buildDef), `I.OnBuild`, `I.OnAdvance`, `I.clock`, `I.Dt` (Phase 1 Task 1), the `def.resources[r]` record (Phase 1 Task 4).
- Produces: `def.resources[r].auraRegen` — a list of `{ aura = <aura key>, interval = <number > 0>, value = <number> }` (the adapter passes Hekili's regen-model entries that have `aura` and no `debuff`; entries whose `interval`/`value` are functions are ignored); `I.res.auraRegen` (`G`): `G.n`, `G.slot[g]` (resource slot), `G.aura[g]` (aura index), `G.value[g]`, `G.interval[g]`; Snapshot's resource line gains `auraRegen=<G.n>`.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/adapter_spec.lua b/VirtualState/spec/adapter_spec.lua
index bd687964..131a1ee0 100644
--- a/VirtualState/spec/adapter_spec.lua
+++ b/VirtualState/spec/adapter_spec.lua
@@ -74,6 +74,18 @@ describe("Adapter", function()
         assert.are.equal(12286, got.talents[1].spell)
     end)
 
+    it("forwards a resource's player-aura regen entries to the resources family", function()
+        h.Class.resources.rage.state.regenModel.bloodrage = { aura = "bloodrage", interval = 1, value = 1 }
+        h.Class.resources.rage.state.regenModel.debuff_test = { aura = "rend", debuff = true, interval = 3, value = 2 }
+        h.Class.auras.bloodrage = { key = "bloodrage", id = 29131, duration = 10 }
+        VS.SpecChanged()
+        local G = I.res.auraRegen
+        assert.are.equal(1, G.n) -- the debuff entry is not a player aura
+        assert.are.same({ 1, 1, 1 }, { G.slot[1], G.value[1], G.interval[1] })
+        assert.are.equal(29131, I.auras.id[G.aura[1]])
+        assert.are.equal(1, I.res.swing[1]) -- the swing source is still found
+    end)
+
     it("feeds the cast history and the real queue from our own cast events, and asks for a cycle", function()
         ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
         assert.are.same({ "rend" }, state.history)
diff --git a/VirtualState/spec/resources_spec.lua b/VirtualState/spec/resources_spec.lua
index d5610919..2829ffd3 100644
--- a/VirtualState/spec/resources_spec.lua
+++ b/VirtualState/spec/resources_spec.lua
@@ -4,6 +4,7 @@
 local load = require("VirtualState.spec.helpers.load")
 local fake = require("VirtualState.spec.helpers.fake_api")
 local fs = require("VirtualState.spec.helpers.fake_spec")
+local alloc = require("VirtualState.spec.helpers.alloc")
 
 local ENERGY = 3
 
@@ -146,4 +147,56 @@ describe("resources", function()
             assert.are.same({ 0, "unknown" }, { u.conf, u.basis })
         end)
     end)
+
+    describe("aura-gated regen (rage, Bloodrage: 1 a second while its aura is up)", function()
+        local BLOODRAGE = 3 -- the aura index
+
+        before_each(function()
+            local def = fs.def(fs.new(9))
+            def.auras[BLOODRAGE] = { key = "bloodrage", id = 29131 }
+            def.auraIds[BLOODRAGE] = { 29131 }
+            def.resources[1].auraRegen = {
+                { aura = "bloodrage", interval = 1, value = 1 },
+                { aura = "not_tracked", interval = 1, value = 5 }, -- no such aura: ignored
+            }
+            boot(def)
+            I.Fold(10, false) -- the clock starts at 10
+        end)
+
+        it("adds value at each interval after the aura's application while it is believed up", function()
+            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0) -- applied at 10, expires at 20
+            I.Settle(15.5)
+            assert.are.equal(5, VS.Power(fs.RAGE, 15.5).est) -- ticks at 11, 12, 13, 14, 15
+            assert.are.equal(10, VS.Power(fs.RAGE, 25).est) -- projected: 16 to 20, none after the expiry
+            I.Settle(25)
+            local r = VS.Power(fs.RAGE, 30)
+            assert.are.same({ 10, 10 }, { r.est, r.lo })
+            assert.are.equal(10, I.res.pinDelta[1]) -- kept out of the next regen measurement
+            assert.are.equal(1, I.res.auraRegen.n)
+        end)
+
+        it("adds nothing while the aura is down", function()
+            I.Settle(20)
+            assert.are.equal(0, VS.Power(fs.RAGE, 25).est)
+        end)
+
+        it("stops when the aura is believed gone early", function()
+            I.AuraModel(1, BLOODRAGE, 10, 20, 1, 10, 0)
+            I.Settle(12.5)
+            I.AuraModel(1, BLOODRAGE, 0, 0, 0, 12.5, 0) -- gone at 12.5 (expiry 0: down)
+            I.Settle(20)
+            assert.are.equal(2, VS.Power(fs.RAGE, 20).est)
+        end)
+
+        it("allocates nothing advancing or projecting through an entry", function()
+            I.AuraModel(1, BLOODRAGE, 10, 1e9, 1, 10, 0)
+            local t = 10
+            local bytes = alloc.bytes(function()
+                t = t + 0.1
+                I.Settle(t)
+                VS.Power(fs.RAGE, t + 0.5)
+            end, 10000)
+            assert.are.equal(0, bytes)
+        end)
+    end)
 end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `93 successes / 2 failures / 1 error` — `resources_spec.lua:169` and `:188` (expected 5 and 2, got 0: no aura-gated regen), `adapter_spec.lua:83: attempt to index local 'G' (a nil value)`.

- [ ] **Step 3: Implement the entries in the family and the forwarding in the adapter**

Apply with `git apply`:

```diff
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index c1478d7e..15532a24 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -99,12 +99,15 @@ local function buildDef()
     local slotByKey = {}
     for _, k in ipairs(sortedKeys(class.resources)) do
         local r = class.resources[k]
-        local swing, value = 0, nil
+        local swing, value, auraRegen = 0, nil, nil
         local model = r.state and r.state.regenModel
         if model then
             for _, m in pairs(model) do
                 if m.swing and HANDS[m.swing] and swing == 0 then
                     swing, value = HANDS[m.swing], m.value
+                elseif m.aura and not m.debuff then
+                    auraRegen = auraRegen or {}
+                    auraRegen[#auraRegen + 1] = m -- a player aura's regen: { aura, interval, value } (Resources.lua)
                 end
             end
         end
@@ -116,6 +119,7 @@ local function buildDef()
             rest = ns.ResourceRegenerates(k) and 100 or 0,
             swing = swing,
             swingValue = value,
+            auraRegen = auraRegen,
         }
         insert(def.resources, d)
         resourceKey[#def.resources] = k
diff --git a/VirtualState/Families/Resources.lua b/VirtualState/Families/Resources.lua
index edb7dae1..bf1b3826 100644
--- a/VirtualState/Families/Resources.lua
+++ b/VirtualState/Families/Resources.lua
@@ -1,7 +1,8 @@
 -- VirtualState/Families/Resources.lua
 -- The resources family (spec §6.1): the cost ladder (a usability report pins or bounds a resource at the ability's
 -- cost), exact reads, regen calibration between pins (an EMA), swing steps for a swing-paid resource (rage), our own
--- casts' changes (Adapter.lua, spec §5.3), and the Power/Regen accessors.
+-- casts' changes (Adapter.lua, spec §5.3), aura-gated regen (Hekili's regen-model entries with `aura`, `interval`,
+-- `value`: Bloodrage's rage over time), and the Power/Regen accessors.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Resources.lua (calibrate :117-136, pin :218-263,
 -- ladder :275-315, Applier Usable :327, Reader Resource :365-372) and the resource conf of
 -- src/TacoDogForever/Model/Belief.lua:695-699. The power-tick phase (TDF's Applier PowerTick :378) is not modelled in
@@ -10,7 +11,7 @@
 local _, ns = ...
 local VS, I = ns.VirtualState, ns.VirtualStateInternal
 local Obs, ReadOf = VS.Obs, I.ReadOf
-local abs = math.abs
+local abs, floor = math.abs, math.floor
 
 --- A flip pin measures regen only when the last short report was at most this long before it (TDF Belief.PIN_EXACT).
 I.PIN_EXACT = 0.15
@@ -51,6 +52,13 @@ local R = {
 I.res = R
 R.slotOf, R.slotOfToken = {}, {}
 
+-- Aura-gated regen entries g of every slot (built from each resource's `auraRegen`): `value` every `interval`
+-- seconds from the aura's application while the player's aura j is believed up. Credited only as the clock moves on:
+-- an aura first seen after its application loses the ticks before that, and a removal seen late keeps the ticks
+-- already credited; both are bounded by the aura's duration and the next pin or rung corrects them.
+local G = { n = 0, slot = {}, aura = {}, value = {}, interval = {} }
+R.auraRegen = G
+
 -- By ability index a: the last usability answer and the last short report (cost, time).
 local usable, shortCost, shortT = {}, {}, {}
 
@@ -93,6 +101,20 @@ I.OnBuild(function(def, now)
         I.Sample(R.regen[r], "default", rate, now, 0)
     end
     I.TRACKED.resource = R.type
+    G.n = 0
+    for r = 1, R.n do
+        local entries = list[r].auraRegen
+        for k = 1, entries and #entries or 0 do
+            local e = entries[k]
+            local ok = type(e.value) == "number" and type(e.interval) == "number" and e.interval > 0
+            for j = 1, #def.auras do
+                if ok and def.auras[j].key == e.aura then
+                    G.n = G.n + 1
+                    G.slot[G.n], G.aura[G.n], G.value[G.n], G.interval[G.n] = r, j, e.value, e.interval
+                end
+            end
+        end
+    end
     for a = 1, #def.abilities do
         usable[a], shortCost[a], shortT[a] = UNKNOWN, 0, 0
     end
@@ -107,7 +129,29 @@ function I.SwingValue(r)
     return type(v) == "number" and v or 0
 end
 
--- Continuous regen between pins (swing-paid slots move only at swings).
+-- What entry g brings in (from, to]: `value` at each `interval` after the player's aura was applied, up to its
+-- believed expiry. Allocates nothing.
+local function auraGain(g, from, to)
+    local j = G.aura[g]
+    local e = I.auras.exp0[1][j] -- unit 1 is always "player" (Adapter.lua's def.units)
+    if e <= from then
+        return 0
+    end
+    local ap, iv = I.auras.applied[1][j], G.interval[g]
+    if to > e then
+        to = e
+    end
+    if from < ap then
+        from = ap
+    end
+    if to <= from then
+        return 0
+    end
+    return (floor((to - ap) / iv) - floor((from - ap) / iv)) * G.value[g] -- nonzero: interval > 0 (checked at build)
+end
+
+-- Continuous regen between pins (swing-paid slots move only at swings), then aura-gated regen, kept out of the
+-- regen measurement like our own casts' changes (pinDelta).
 I.OnAdvance(function(from, to)
     local dt = to - from
     for r = 1, R.n do
@@ -118,6 +162,17 @@ I.OnAdvance(function(from, to)
             R.hi0[r] = clamp(R.hi0[r] + R.regH[r] * dt, max)
         end
     end
+    for g = 1, G.n do
+        local v = auraGain(g, from, to)
+        if v ~= 0 then
+            local r = G.slot[g]
+            local max = R.max[r]
+            R.est0[r] = clamp(R.est0[r] + v, max)
+            R.lo0[r] = clamp(R.lo0[r] + v, max)
+            R.hi0[r] = clamp(R.hi0[r] + v, max)
+            R.pinDelta[r] = R.pinDelta[r] + v
+        end
+    end
 end)
 
 -- One regen measurement m (per second, between two pins ending at t) into the slot's regen (the EMA, TDF
@@ -319,8 +374,9 @@ function I.ResourceShift(r, delta, t, event)
     I.Sample(R.power[r], "modelled", R.est0[r], t, event)
 end
 
---- (spec §3.2) The believed amount of a power type at `now`: the clock values plus continuous regen x dt, each clamped
---- to [0, max]; conf 1 - (hi - lo) / max, halved within SNAP_HOLD of a snap. Allocates nothing.
+--- (spec §3.2) The believed amount of a power type at `now`: the clock values plus continuous regen x dt and the
+--- aura-gated ticks to `now`, each clamped to [0, max]; conf 1 - (hi - lo) / max, halved within SNAP_HOLD of a snap.
+--- Allocates nothing.
 function VS.Power(powerType, now)
     local r = R.slotOf[powerType]
     if not r then
@@ -330,9 +386,17 @@ function VS.Power(powerType, now)
     if R.swing[r] > 0 then
         dt = 0 -- a swing-paid resource moves only at swings
     end
-    local est = clamp(R.est0[r] + R.regE[r] * dt, max)
-    local lo = clamp(R.lo0[r] + R.regL[r] * dt, max)
-    local hi = clamp(R.hi0[r] + R.regH[r] * dt, max)
+    local gain = 0
+    if now > I.clock then
+        for g = 1, G.n do
+            if G.slot[g] == r then
+                gain = gain + auraGain(g, I.clock, now)
+            end
+        end
+    end
+    local est = clamp(R.est0[r] + R.regE[r] * dt + gain, max)
+    local lo = clamp(R.lo0[r] + R.regL[r] * dt + gain, max)
+    local hi = clamp(R.hi0[r] + R.regH[r] * dt + gain, max)
     if lo > est then
         lo = est
     end
@@ -376,12 +440,13 @@ I.OnSnapshot(function(out, now)
         VS.Power(R.type[r], now)
         VS.Regen(R.type[r], now)
         out[#out + 1] = string.format(
-            "resource %s type=%d max=%d swing=%d scale=%.2f",
+            "resource %s type=%d max=%d swing=%d scale=%.2f auraRegen=%d",
             tostring(R.token[r]),
             R.type[r],
             R.max[r],
             R.swing[r],
-            R.scale[r]
+            R.scale[r],
+            G.n
         )
     end
 end)
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `96 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [96 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 63 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output] (modified and new files, new directories included)
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Families/Resources.lua VirtualState/Adapter.lua VirtualState/spec/resources_spec.lua VirtualState/spec/adapter_spec.lua
git commit -m "feat(virtualstate): aura-gated regen in the resources family; the adapter forwards a resource's player-aura regen entries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-warrior-profile`

### Task 2: The Classic kit with Forever's spell data: abilities, auras, Bloodrage, stances, reactive windows

This task rewrites `Forever/Warrior.lua` with every Classic ability and aura (Classic/Warrior.lua:140-1572), corrected to the Forever DB2, plus Victory Rush and Spearing Strike, and adds the headless spec that checks it. The talent block and the default "Warrior" pack stay as Phase 1 left them (Tasks 3 and 4 replace them).

Data (DB2 build 1.60.1.70338; `wowdb "SELECT c.SpellID, i.name, c.RecoveryTime, c.CategoryRecoveryTime, c.StartRecoveryTime, i.cost FROM SpellCooldowns c JOIN spell_info i ON i.id=c.SpellID WHERE …"`: the `spell_info.cooldown_ms` column alone misses category cooldowns): the costs, cooldowns and GCDs are the `KIT` table in the spec below. Differences from Classic that the file takes from the DB2: Thunder Clap cooldown 6 (Classic 4) and duration 10/14/18/22/26/30 s by rank; Disarm cooldown 60 (10); Last Stand 180 (600); Retaliation and Shield Wall 900 (1800); Taunt 8 (10); Concussion Blow cost 10 (15); Sweeping Strikes aura 20 s (30); Demoralizing Shout 45 s; Battle Shout 180 s; Shield Block 7 s; Shield Wall 12 s; Slam a new rank 1 (1240193, level 20), an 18 s category cooldown and Improved Slam's replacement spells 1310196-1310200 (talent 12862's override effects); Charge's rage 9/12/15 by rank (energize 90/120/150); Pummel, Shield Bash and Shield Wall on the GCD (start recovery 1500 ms; Classic had them off: a checkpoint question). The Classic file's swapped IDs are corrected: Death Wish 12328 and Sweeping Strikes 12292 (ability and aura). Classic's unregistered auras the handlers named (`demoralizing_shout`, `sunder_armor`, `expose_armor`, `improved_shield_bash`) are registered or renamed (`shield_bash_silenced`, 18498); Improved Hamstring's proc is 23694 (the DB2's 5 s spell; Classic used the talent's rank 2 ID); Classic's `not combat` (always false: `state.combat` is a number) is `combat == 0`.

Forever changes beyond the data: the execute window is Execute's plain usability (`C_Spell.IsSpellUsable`: the target's health is secret on Forever, `docs/forever-facade-notes.md`), as are Revenge's (a 5 s window from that read, not from the proc) and Victory Rush's; Overpower's window is Forever's 5 s player aura 1282733 ("Overpower", DB2 effect 1 applies aura 560 on the caster), tracked by VirtualState like any aura (ruling W6); its effect 0 grants a combo point, so it may be a hidden aura the walk never sees: checkpoint Q6 asks, and the fallback (ruling W6a) is Overpower on rage alone behind its Battle Stance gate, no usability read, with the swap to Battle Stance after a dodge then unpredictable from another stance (no combat log); the stance is read in `reset_precast` from `GetShapeshiftForm`/`GetShapeshiftFormInfo` (plain, `docs/forever-facade-notes.md:115-116`), mapping the form's spell ID (the fourth return) to the stance aura, so the stance bar's order does not matter (ruling W5; Hekili's own `stance` table, `State.lua:2617-2631`, reads a fifth return that does not exist and never re-reads, so it is not used); a queued Heroic Strike or Cleave is read from `C_Spell.IsCurrentSpell` into a synthetic aura so it is not recommended twice (Classic's `QueueAuraExpiration` model is replaced by Phase 1's `onNextSwing`, which only VirtualState reads: Hekili's own simulation spends the cost at the press and still adds the replaced swing's rage, one swing of rage optimism per queued strike in its forward projection until VirtualState's next drain corrects the belief; no modelling change (ruling W9), named in a code comment and checked by checkpoint Q9); a stance swap keeps 10 rage with Forever's Tactical Mastery passive (1310185, DB2 effect: dummy 10) plus 15 a rank of Improved Tactical Mastery (12295's base points, DB2); Bloodrage's rage over time is the resource's `bloodrage` entry (Task 1). Talent cost modifiers are rank 1's DB2 value x the rank, floored at 0 (only rank 1 of each talent is in the DB2): Improved Heroic Strike -1, Improved Cleave -3, Improved Execute -5, Improved Sunder Armor -3, Improved Thunder Clap -6 rage a rank; Improved Taunt -1 s a rank and Improved Shield Block +0.5/1/2 s are exact (every rank is in the DB2). Rage per swing uses Hekili's `main_hand.size` (Events.lua:741-745): 3.46 a second of weapon speed for a one-hander, 4.5 for a two-hander (TDF `src/TacoDogForever_Warrior/Warrior.lua:21-24`).

**Files:**
- Create: `Forever/spec/helpers/load_warrior.lua`, `Forever/spec/warrior_spec.lua`
- Modify (whole file): `Forever/Warrior.lua`, `.busted`
- Modify: `.luacheckrc` (:110-111)

**Interfaces:**
- Consumes: Task 1's `auraRegen` forwarding (the `bloodrage` regen entry reaches VirtualState through it); Hekili's `NewSpecialization`, `RegisterResource`, `RegisterTalents`, `RegisterAuras`, `RegisterAbilities`, `RegisterStateFunction` (`Classes.lua:421`), `RegisterHook` (`Classes.lua:704`), `RegisterOptions`, `RegisterPack`; `ns.VirtualState.Track` (Phase 1 Task 1); `state.main_hand.size`, `state.timeToInterrupt` (`State.lua:995-1001`), `state.mainhand_speed`, `state.swings`.
- Produces (Tasks 3 and 4 rely on these names): in `Forever/Warrior.lua` the locals `rest(ids)`, `knownRank(ids) -> rank`, `knows(ids) -> function`, `reactive(ids) -> boolean`, the rank tables (`EXECUTE`, `MORTAL_STRIKE`, `HEROIC_STRIKE`, `CLEAVE`, …), the state function `swap_stance(stance)`, the hook `reset_precast`, 41 abilities and 41 auras (Classic's 40 less `my_battle_shout`, `stance` and `shout`, plus `battle_shout`, `demoralizing_shout`, `expose_armor` and `sunder_armor`, which Classic named but never registered); in `Forever/spec/helpers/load_warrior.lua`: `load() -> w` (`w.abilities`, `w.auras`, `w.talents`, `w.track`, `w.resource`, `w.hooks`, `w.funcs`, `w.exprs`, `w.settings[key] = { default, option }`, `w.packs` (`{ name, version, string }` in order), `w.options`, `w.specID`, `w.state`, `w.game` with `known`, `current`, `usable`, `noMana`, `form`, `formSpell`), `env(w) -> e` (records `applied`, `removed`, `spent`, `gained`; binds `w.funcs`), `run(f, e, ...)`.

- [ ] **Step 1: Write the loader and the failing spec; point busted and luacheck at them**

`Forever/spec/helpers/load_warrior.lua`:

```lua
-- Forever/spec/helpers/load_warrior.lua
-- Loads Forever/Warrior.lua headless against a recording stand-in for Hekili: every spec:RegisterX call is kept by
-- method name, ns.VirtualState.Track's tables are merged, and the plain game reads the file captures at load answer
-- from `game` (known spells, queued spells, usability, the shapeshift form). `env()` is a stand-in `state` for running
-- the file's handlers, state functions and hooks (Hekili runs them with setfenv( f, state )).
local M = {}

--- Loads the class file. Returns `w`: `w.abilities`, `w.auras` (merged by key), `w.talents`, `w.track`, `w.resource`
--- ({ powerType, models }), `w.hooks[name]`, `w.funcs[name]`, `w.exprs[name]`, `w.settings[key]` ({ default,
--- option }), `w.packs` (in order: { name, version, string }), `w.options`, `w.specID`, `w.state` (Hekili.State's
--- stand-in) and `w.game`.
function M.load()
    local reg = {}
    local spec = setmetatable({}, {
        __index = function(_, method)
            return function(_, ...)
                reg[method] = reg[method] or {}
                table.insert(reg[method], { ... })
            end
        end,
    })
    local game = { known = {}, current = {}, usable = {}, noMana = {}, form = 0, formSpell = {} }
    local w = { game = game, abilities = {}, auras = {}, track = {}, hooks = {}, funcs = {}, exprs = {} }
    w.state = { main_hand = { size = 2 }, timeToInterrupt = function() end }
    local hekili = { State = w.state }
    function hekili:NewSpecialization(id)
        w.specID = id
        return spec
    end
    local fakes = {
        Hekili = hekili,
        UnitClassBase = function()
            return "WARRIOR"
        end,
        C_SpellBook = {
            IsSpellKnown = function(id)
                return game.known[id] == true
            end,
        },
        C_Spell = {
            IsCurrentSpell = function(id)
                return game.current[id] == true
            end,
            IsSpellUsable = function(id)
                return game.usable[id] == true, game.noMana[id] == true
            end,
        },
        GetShapeshiftForm = function()
            return game.form
        end,
        GetShapeshiftFormInfo = function(i)
            return 0, true, true, game.formSpell[i]
        end,
        Enum = { PowerType = { Rage = 1 } },
    }
    local saved = {}
    for k, v in pairs(fakes) do
        saved[k] = rawget(_G, k) or false
        _G[k] = v
    end
    local ns = {
        VirtualState = {
            Track = function(t)
                for k, v in pairs(t.talents or {}) do
                    w.track[k] = v
                end
            end,
        },
    }
    local ok, err = pcall(assert(loadfile("Forever/Warrior.lua")), "Hekili", ns)
    for k, v in pairs(saved) do
        _G[k] = v or nil
    end
    assert(ok, err)
    for _, call in ipairs(reg.RegisterAbilities or {}) do
        for k, v in pairs(call[1]) do
            w.abilities[k] = v
        end
    end
    for _, call in ipairs(reg.RegisterAuras or {}) do
        for k, v in pairs(call[1]) do
            w.auras[k] = v
        end
    end
    w.talents = reg.RegisterTalents and reg.RegisterTalents[1][1]
    w.resource = reg.RegisterResource and reg.RegisterResource[1]
    for _, call in ipairs(reg.RegisterHook or {}) do
        w.hooks[call[1]] = call[2]
    end
    for _, call in ipairs(reg.RegisterStateFunction or {}) do
        w.funcs[call[1]] = call[2]
    end
    for _, call in ipairs(reg.RegisterStateExpr or {}) do
        w.exprs[call[1]] = call[2]
    end
    w.settings = {}
    for _, call in ipairs(reg.RegisterSetting or {}) do
        w.settings[call[1]] = { default = call[2], option = call[3] }
    end
    w.packs = reg.RegisterPack or {}
    w.options = reg.RegisterOptions and reg.RegisterOptions[1][1]
    return w
end

local function default(value)
    return setmetatable({}, {
        __index = function()
            return value
        end,
    })
end

--- A stand-in `state` that records applyBuff/applyDebuff (into `applied`), removeBuff, spend and gain, with every
--- talent at rank 0, every aura down and every cooldown ready. The class file's state functions are bound to it.
function M.env(w)
    local e = { applied = {}, removed = {}, spent = {}, gained = {} }
    e.talent = default({ rank = 0, enabled = false })
    e.buff = default({ up = false, remains = 0, stack = 0 })
    e.debuff = e.buff
    e.cooldown = default({ remains = 0 })
    e.active_dot = default(0)
    e.rage = { current = 50 }
    e.target = { minR = 10, is_boss = false }
    e.combat, e.active_enemies = 0, 1
    function e.applyBuff(key)
        table.insert(e.applied, key)
    end
    function e.applyDebuff(_, key)
        table.insert(e.applied, key)
    end
    function e.removeBuff(key)
        table.insert(e.removed, key)
    end
    function e.spend(n)
        table.insert(e.spent, n)
    end
    function e.gain(n)
        table.insert(e.gained, n)
    end
    function e.setDistance() end
    function e.interrupt() end
    for k, f in pairs(w.funcs) do
        e[k] = setfenv(f, e)
    end
    return e
end

--- Runs `f` (a field function of the class file) in `e`; a non-function is returned as is.
function M.run(f, e, ...)
    if type(f) ~= "function" then
        return f
    end
    return setfenv(f, e)(...)
end

return M
```

`Forever/spec/warrior_spec.lua`:

```lua
-- Forever/spec/warrior_spec.lua: the Forever Warrior class file's registrations against the Forever DB2 (build
-- 1.60.1.70338, wowdb), loaded headless through a recording stand-in for Hekili (helpers/load_warrior.lua). What Hekili
-- does with them is verified in game (the plan's checkpoint).
local lw = require("Forever.spec.helpers.load_warrior")

-- key = { spell IDs in rank order, cost in rage with every talent at rank 0, cooldown, gcd }, from the DB2 (the cost
-- column / 10; the cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd "off" where StartRecoveryTime
-- is 0).
local KIT = {
    battle_shout = { { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, 10, 0, "spell" },
    battle_stance = { { 2457 }, 0, 1, "off" },
    berserker_rage = { { 18499 }, 0, 30, "spell" },
    berserker_stance = { { 2458 }, 0, 1, "off" },
    bloodrage = { { 2687 }, 0, 60, "off" },
    bloodthirst = { { 23881, 23892, 23893, 23894 }, 30, 6, "spell" },
    challenging_shout = { { 1161 }, 5, 600, "spell" },
    charge = { { 100, 6178, 11578 }, 0, 15, "off" },
    cleave = { { 845, 7369, 11608, 11609, 20569 }, 20, 0, "off" },
    concussion_blow = { { 12809 }, 10, 45, "off" },
    death_wish = { { 12328 }, 10, 180, "spell" },
    defensive_stance = { { 71 }, 0, 1, "off" },
    demoralizing_shout = { { 1160, 6190, 11554, 11555, 11556 }, 10, 0, "spell" },
    disarm = { { 676 }, 20, 60, "spell" },
    execute = { { 5308, 20658, 20660, 20661, 20662 }, 15, 0, "spell" },
    hamstring = { { 1715, 7372, 7373 }, 10, 0, "spell" },
    heroic_strike = { { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }, 15, 0, "off" },
    intercept = { { 20252, 20616, 20617 }, 10, 30, "off" },
    intimidating_shout = { { 5246 }, 25, 180, "spell" },
    last_stand = { { 12975 }, 0, 180, "off" },
    mocking_blow = { { 694, 7400, 7402, 20559, 20560 }, 10, 120, "spell" },
    mortal_strike = { { 12294, 21551, 21552, 21553 }, 30, 6, "spell" },
    overpower = { { 7384, 7887, 11584, 11585 }, 5, 5, "spell" },
    piercing_howl = { { 12323 }, 10, 0, "spell" },
    pummel = { { 6552, 6554 }, 10, 10, "spell" },
    recklessness = { { 1719 }, 0, 1800, "spell" },
    rend = { { 772, 6546, 6547, 6548, 11572, 11573, 11574 }, 10, 0, "spell" },
    retaliation = { { 20230 }, 0, 900, "spell" },
    revenge = { { 6572, 6574, 7379, 11600, 11601, 25288 }, 5, 5, "spell" },
    shield_bash = { { 72, 1671, 1672 }, 10, 12, "spell" },
    shield_block = { { 2565 }, 10, 5, "off" },
    shield_slam = { { 23922, 23923, 23924, 23925 }, 20, 6, "spell" },
    shield_wall = { { 871 }, 0, 900, "spell" },
    slam = {
        { 1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200 },
        15,
        18,
        "spell",
    },
    spearing_strike = { { 1310222 }, 15, 20, "spell" },
    sunder_armor = { { 7386, 7405, 8380, 11596, 11597 }, 15, 0, "spell" },
    sweeping_strikes = { { 12292 }, 30, 30, "off" },
    taunt = { { 355 }, 0, 8, "off" },
    thunder_clap = { { 6343, 8198, 8204, 8205, 11580, 11581 }, 20, 6, "spell" },
    victory_rush = { { 402927 }, 0, 30, "spell" },
    whirlwind = { { 1680 }, 25, 10, "spell" },
}

local function idsOf(a)
    local ids = { a.id }
    for _, v in ipairs(a.copy or {}) do
        ids[#ids + 1] = v
    end
    return ids
end

describe("Forever Warrior", function()
    local w

    before_each(function()
        w = lw.load()
    end)

    it("registers the Classic kit plus Victory Rush and Spearing Strike with the DB2's ranks, costs and cooldowns", function()
        local e = lw.env(w)
        local n = 0
        for key, a in pairs(w.abilities) do
            n = n + 1
            local want = KIT[key]
            assert.is_not_nil(want, "unexpected ability " .. key)
            assert.are.same(want[1], idsOf(a), key)
            assert.are.same(
                { want[2], want[3], want[4] },
                { lw.run(a.spend, e) or 0, lw.run(a.cooldown, e), a.gcd },
                key
            )
            assert.are.equal("function", type(a.known), key)
        end
        assert.are.equal(41, n)
        assert.are.equal(1.5, w.abilities.slam.cast)
        assert.is_true(w.abilities.heroic_strike.onNextSwing and w.abilities.cleave.onNextSwing)
    end)

    it("models the talent-modified costs and cooldowns from rank 1's DB2 value x the rank", function()
        local e = lw.env(w)
        e.talent = setmetatable({}, {
            __index = function()
                return { rank = 2, enabled = true }
            end,
        })
        local function at(key, field)
            return lw.run(w.abilities[key][field], e)
        end
        assert.are.same(
            { 13, 14, 5, 9, 8, 6 },
            { at("heroic_strike", "spend"), at("cleave", "spend"), at("execute", "spend"), at("sunder_armor", "spend"),
                at("thunder_clap", "spend"), at("taunt", "cooldown") }
        )
    end)

    it("uses the corrected Classic IDs and Forever's Overpower window", function()
        assert.are.same({ 12328, 12292 }, { w.abilities.death_wish.id, w.abilities.sweeping_strikes.id })
        assert.are.same({ 12328, 12292 }, { w.auras.death_wish.id, w.auras.sweeping_strikes.id })
        assert.are.same({ 1282733, 5 }, { w.auras.overpower_ready.id, w.auras.overpower_ready.duration })
        assert.are.same({ 29131, 10 }, { w.auras.bloodrage.id, w.auras.bloodrage.duration })
    end)

    it("registers every aura a handler, state function or stance gate names", function()
        local e = lw.env(w)
        for key, a in pairs(w.abilities) do
            lw.run(a.handler, e)
            for _, gate in ipairs({ lw.run(a.buff, e), a.nobuff }) do
                table.insert(e.applied, gate)
            end
        end
        for _, k in ipairs(e.applied) do
            assert.is_not_nil(w.auras[k], "unregistered aura " .. tostring(k))
        end
        for _, k in ipairs(e.removed) do
            assert.is_not_nil(w.auras[k], "unregistered aura " .. tostring(k))
        end
    end)

    it("gains Bloodrage's rage over time through an aura-gated regen entry", function()
        local models = w.resource[2]
        assert.are.equal(1, w.resource[1])
        assert.are.same({ "bloodrage", 1, 1 }, { models.bloodrage.aura, models.bloodrage.interval, models.bloodrage.value })
        w.state.buff = { bloodrage = { applied = 10 } }
        w.state.query_time = 13.4
        assert.are.equal(13, models.bloodrage.last())
        assert.are.equal("mainhand", models.mainhand.swing)
    end)

    it("reads the stance, a queued strike and Revenge's window at reset", function()
        local e = lw.env(w)
        w.game.form, w.game.formSpell[2] = 2, 71
        w.game.known[78], w.game.current[78] = true, true
        w.game.known[6572], w.game.noMana[6572] = true, true -- usable but for rage
        lw.run(w.hooks.reset_precast, e)
        assert.are.same({ "defensive_stance", "heroic_strike", "revenge_usable" }, e.applied)
    end)

    it("keeps Tactical Mastery's rage on a stance swap", function()
        local e = lw.env(w)
        w.game.known[1310185] = true
        e.talent = setmetatable({}, {
            __index = function()
                return { rank = 2, enabled = true }
            end,
        })
        e.swap_stance("berserker_stance")
        assert.are.same({ 30 }, e.spent) -- 50 rage, 10 + 2 x 5 kept
        assert.are.same({ "berserker_stance" }, e.applied)
    end)

    it("recommends Execute only inside the client's usability window, at the known rank", function()
        local e = lw.env(w)
        w.game.known[5308], w.game.known[20658] = true, true
        assert.is_false(lw.run(w.abilities.execute.usable, e))
        w.game.usable[20658] = true
        assert.is_true(lw.run(w.abilities.execute.usable, e))
    end)
end)
```

`.busted` (whole file):

```lua
return {
    default = { ROOT = { "VirtualState/spec", "Forever/spec" }, pattern = "_spec", lpath = "./?.lua", verbose = true },
}
```

`.luacheckrc`, apply with `git apply` (the spec directory gets busted's globals; the class file's handlers and state functions run with `setfenv( f, state )`, so luacheck needs the further state names they use):

```diff
diff --git a/.luacheckrc b/.luacheckrc
index efa5c322..5bf5ada4 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -108,4 +108,14 @@ files["Utils.lua"] = { globals = stateEnv }
 files["Hekili.lua"] = { globals = stateEnv }
 files["Constants.lua"] = { globals = stateEnv }
 files["VirtualState/spec/"] = { std = "+busted" }
-files["Forever/Warrior.lua"] = { globals = stateEnv }
+files["Forever/spec/"] = { std = "+busted" }
+-- The Warrior's handlers, state expressions and state functions run with setfenv( f, state ) as well; these are the
+-- further `state` names they use.
+local warriorEnv = {
+    "rage", "cooldown", "combat", "active_enemies", "active_dot", "setDistance", "interrupt", "swap_stance",
+    "should_queue", "mainhand_remains", "nextMH", "mainhand_speed",
+}
+for _, k in ipairs(stateEnv) do
+    warriorEnv[#warriorEnv + 1] = k
+end
+files["Forever/Warrior.lua"] = { globals = warriorEnv }
```

- [ ] **Step 2: Run the spec to verify it fails**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `97 successes / 2 failures / 5 errors` — `warrior_spec.lua:88` (3 abilities, not 41), `:149` (no stance read), and errors at `:101`, `:111` (`death_wish` not registered), `:136` (`bloodrage` not in the resource), `:160` (`swap_stance` nil), `:168` (`execute` not registered).

- [ ] **Step 3: Write the class file**

`Forever/Warrior.lua` (whole file):

```lua
-- Forever/Warrior.lua
-- The Forever Warrior (pseudo-spec 1491): the Classic Warrior kit with Forever's spell data (ranks, costs, cooldowns,
-- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb; a cost of 100 there is 10 rage), Forever's
-- Victory Rush and Spearing Strike, rage with its main-hand swing model and Bloodrage's rage over time, stances from
-- the plain shapeshift reads, and the default priorities.
-- Talent modifiers: only rank 1 of each talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank
-- (Classic's own convention), floored at 0; cooldown and duration modifiers are modelled only where every rank is in
-- the DB2 (Improved Taunt, Improved Shield Block). The in-game checkpoint compares the costs (Snapshot cost= / read=).
-- Credits: Hekili (registration API and pack format); the abilities, auras, stance swap, queue prediction and the Arms
-- and Fury priorities are ported from Hekili's Classic profile (origin/classic:Classic/Warrior.lua,
-- Classic/APLs/WarriorArms.simc, Classic/APLs/WarriorFury.simc); call shapes from archive/TheWarWithin/WarriorArms.lua.
-- Rage per swing from Taco Dog Forever's Warrior pack (src/TacoDogForever_Warrior/Warrior.lua:21-24).

local addon, ns = ...
local C_SpellBook, C_Spell, UnitClassBase = C_SpellBook, C_Spell, UnitClassBase
local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
local Hekili = _G[ addon ]

if UnitClassBase( "player" ) ~= "WARRIOR" then return end

local state = Hekili.State
local IsSpellKnown, IsCurrentSpell, IsSpellUsable = C_SpellBook.IsSpellKnown, C_Spell.IsCurrentSpell, C_Spell.IsSpellUsable
local floor, max, min = math.floor, math.max, math.min

local spec = Hekili:NewSpecialization( 1491, false, 135328 ) -- inv_sword_27; numeric because Options formats it with %d
if not spec then return end

-- Rank IDs, lowest first (the DB2's).
local BATTLE_SHOUT = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local REND = { 772, 6546, 6547, 6548, 11572, 11573, 11574 }
local REND_DURATION = { 9, 12, 15, 18, 21, 21, 21 }
local HEROIC_STRIKE = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }
local BLOODTHIRST = { 23881, 23892, 23893, 23894 }
local CHARGE = { 100, 6178, 11578 }
local CHARGE_RAGE = { 9, 12, 15 }
local CLEAVE = { 845, 7369, 11608, 11609, 20569 }
local DEMORALIZING_SHOUT = { 1160, 6190, 11554, 11555, 11556 }
local EXECUTE = { 5308, 20658, 20660, 20661, 20662 }
local HAMSTRING = { 1715, 7372, 7373 }
local INTERCEPT = { 20252, 20616, 20617 }
local MOCKING_BLOW = { 694, 7400, 7402, 20559, 20560 }
local MORTAL_STRIKE = { 12294, 21551, 21552, 21553 }
local OVERPOWER = { 7384, 7887, 11584, 11585 }
local PUMMEL = { 6552, 6554 }
local REVENGE = { 6572, 6574, 7379, 11600, 11601, 25288 }
local SHIELD_BASH = { 72, 1671, 1672 }
local SHIELD_SLAM = { 23922, 23923, 23924, 23925 }
-- Slam: Forever's rank 1 (1240193), then Improved Slam's replacements of each rank (1310196-1310200, the talent's
-- override effects), so a cast of either is ours.
local SLAM = { 1240193, 1464, 8820, 11604, 11605, 1310196, 1310197, 1310198, 1310199, 1310200 }
local SUNDER_ARMOR = { 7386, 7405, 8380, 11596, 11597 }
local THUNDER_CLAP = { 6343, 8198, 8204, 8205, 11580, 11581 }
local THUNDER_CLAP_DURATION = { 10, 14, 18, 22, 26, 30 }
local VICTORY_RUSH = { 402927 }
local SHIELD_BLOCK_BONUS = { 0.5, 1, 2 } -- Improved Shield Block's seconds by rank (all three in the DB2)
local TACTICAL_MASTERY = 1310185 -- Forever's level 14 passive: rage kept on a stance swap

local function rest( ids )
    local out = {}
    for i = 2, #ids do out[ #out + 1 ] = ids[ i ] end
    return out
end

-- The highest rank of `ids` the player knows (0: none). C_SpellBook, not the deprecation shims (cleanup Q12).
local function knownRank( ids )
    for i = #ids, 1, -1 do
        if IsSpellKnown( ids[ i ] ) then return i end
    end
    return 0
end

local function knows( ids )
    return function () return knownRank( ids ) > 0 end
end

-- A reactive ability's window (Execute, Overpower's stance, Revenge, Victory Rush) from the plain usability read:
-- usable, or unusable only for lack of rage. The client's answer now, not at the simulated time (as Classic's
-- reset_precast read it); Forever has no combat log to time the window.
local function reactive( ids )
    local r = knownRank( ids )
    if r == 0 then return false end
    local usable, noMana = IsSpellUsable( ids[ r ] )
    return usable == true or noMana == true
end

-- Rage a second of the main hand's unhasted weapon speed: a white swing brings rate x that speed (haste adds swings,
-- never rage per swing): 4.5 for a two-hander, 3.46 for a one-hander (Hekili's gear scan sets main_hand.size).
-- shortcut: no off-hand swing source (VirtualState models one swing-paid hand), so a dual wielder's off hand is left
-- to VirtualState's calibration; upgrade when the resources family takes a second hand.
local function rageRate()
    return state.main_hand.size == 1 and 3.46 or 4.5
end

spec:RegisterResource( Enum.PowerType.Rage, {
    mainhand = {
        swing = "mainhand",

        last = function ()
            local swing = state.swings.mainhand
            local t = state.query_time
            if state.mainhand_speed == 0 then return 0 end
            return swing + floor( ( t - swing ) / state.mainhand_speed ) * state.mainhand_speed
        end,

        interval = "mainhand_speed",

        stop = function () return state.swings.mainhand == 0 end,
        value = function () return rageRate() * state.mainhand_speed / state.haste end,
    },

    -- Bloodrage's aura (29131): 1 rage every second for 10 s (DB2 effect: periodic energize 10 every 1000 ms).
    bloodrage = {
        aura = "bloodrage",

        last = function ()
            local app = state.buff.bloodrage.applied
            return app + floor( state.query_time - app )
        end,

        interval = 1,
        value = 1,
    },
} )

-- Talents: { node (unused on Forever), the rank 1 spell, max rank }; VirtualState maps the trait walk's spells to them.
spec:RegisterTalents( {
    improved_heroic_strike           = { 0, 12282, 3 },
    deflection                       = { 0, 16462, 5 },
    improved_rend                    = { 0, 12286, 3 },
    improved_charge                  = { 0, 12285, 2 },
    improved_tactical_mastery        = { 0, 12295, 5 },
    improved_thunder_clap            = { 0, 12287, 3 },
    improved_overpower               = { 0, 12290, 2 },
    anger_management                 = { 0, 12296, 1 },
    deep_wounds                      = { 0, 12834, 3 },
    two_handed_weapon_specialization = { 0, 12163, 5 },
    impale                           = { 0, 16493, 2 },
    sweeping_strikes                 = { 0, 12292, 1 },
    improved_hamstring               = { 0, 12289, 3 },
    mortal_strike                    = { 0, 12294, 1 },
} )

-- The higher rank spells of each talent, in case the trait walk names a rank rather than rank 1 (spec §3.6 Track).
ns.VirtualState.Track( { talents = {
    [ 12663 ] = 12282, [ 12664 ] = 12282,
    [ 16463 ] = 16462, [ 16464 ] = 16462, [ 16465 ] = 16462, [ 16466 ] = 16462,
    [ 12658 ] = 12286, [ 12659 ] = 12286,
    [ 12697 ] = 12285,
    [ 12676 ] = 12295, [ 12677 ] = 12295, [ 12678 ] = 12295, [ 12679 ] = 12295,
    [ 12665 ] = 12287, [ 12666 ] = 12287,
    [ 12963 ] = 12290,
    [ 12849 ] = 12834, [ 12867 ] = 12834,
    [ 12711 ] = 12163, [ 12712 ] = 12163, [ 12713 ] = 12163, [ 12714 ] = 12163,
    [ 16494 ] = 16493,
    [ 12668 ] = 12289, [ 23695 ] = 12289,
} } )

spec:RegisterAuras( {
    battle_shout = {
        id = 6673,
        copy = rest( BATTLE_SHOUT ),
        duration = 180,
        max_stack = 1,
    },
    battle_stance = {
        id = 2457,
        duration = 3600,
        max_stack = 1,
    },
    berserker_rage = {
        id = 18499,
        duration = 10,
        max_stack = 1,
    },
    berserker_stance = {
        id = 2458,
        duration = 3600,
        max_stack = 1,
    },
    blood_craze = {
        id = 16488,
        copy = { 16490, 16491 },
        duration = 6,
        tick_time = 1,
        max_stack = 1,
    },
    bloodrage = {
        id = 29131,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
    },
    challenging_shout = {
        id = 1161,
        duration = 6,
        max_stack = 1,
    },
    charge_stun = {
        id = 7922,
        duration = 1,
        max_stack = 1,
    },
    -- Cleave or Heroic Strike queued on the next swing (C_Spell.IsCurrentSpell, applied in reset_precast). A full
    -- swing long, not the time to the swing, so it can outlast the real queue by up to one swing after a reset.
    cleave = {
        duration = function () return state.mainhand_speed end,
        max_stack = 1,
    },
    concussion_blow = {
        id = 12809,
        duration = 5,
        max_stack = 1,
    },
    death_wish = {
        id = 12328,
        duration = 30,
        max_stack = 1,
    },
    deep_wound = {
        id = 23255,
        copy = { 23256 },
        duration = 12,
        max_stack = 1,
    },
    defensive_stance = {
        id = 71,
        duration = 3600,
        max_stack = 1,
    },
    demoralizing_shout = {
        id = 1160,
        copy = rest( DEMORALIZING_SHOUT ),
        duration = 45,
        max_stack = 1,
    },
    disarm = {
        id = 676,
        duration = 10,
        max_stack = 1,
    },
    enrage = {
        id = 12880,
        copy = { 14201, 14202, 14203, 14204 },
        duration = 12,
        max_stack = 1,
    },
    -- A rogue's armor debuff; the Sunder Armor condition skips a target that has it.
    expose_armor = {
        id = 8647,
        copy = { 8649, 8650, 11197, 11198 },
        duration = 30,
        max_stack = 1,
    },
    flurry = {
        id = 12966,
        copy = { 12967, 12968, 12969, 12970 },
        duration = 15,
        max_stack = 1,
    },
    hamstring = {
        id = 1715,
        copy = rest( HAMSTRING ),
        duration = 15,
        max_stack = 1,
    },
    heroic_strike = {
        duration = function () return state.mainhand_speed end,
        max_stack = 1,
    },
    improved_hamstring = {
        id = 23694,
        duration = 5,
        max_stack = 1,
    },
    intercept_stun = {
        id = 20253,
        copy = { 20614, 20615 },
        duration = 3,
        max_stack = 1,
    },
    intimidating_shout = {
        id = 20511,
        copy = { 5246 },
        duration = 8,
        max_stack = 1,
    },
    last_stand = {
        id = 12976,
        duration = 20,
        max_stack = 1,
    },
    mocking_blow = {
        id = 694,
        copy = rest( MOCKING_BLOW ),
        duration = 6,
        max_stack = 1,
    },
    mortal_strike = {
        id = 12294,
        copy = rest( MORTAL_STRIKE ),
        duration = 10,
        max_stack = 1,
    },
    -- Forever's Overpower window: a 5 s player aura (DB2 1282733, "Overpower"), in place of Classic's combat log. It
    -- also grants a combo point (DB2 effect 0), so it may be a hidden aura the walk never sees (checkpoint Q6); the
    -- fallback is then Overpower on rage alone in Battle Stance, and the swap to Battle Stance after a dodge cannot be
    -- predicted from another stance (no combat log on Forever).
    overpower_ready = {
        id = 1282733,
        duration = 5,
        max_stack = 1,
    },
    piercing_howl = {
        id = 12323,
        duration = 6,
        max_stack = 1,
    },
    recklessness = {
        id = 1719,
        duration = 15,
        max_stack = 1,
    },
    rend = {
        id = 772,
        copy = rest( REND ),
        duration = function () return REND_DURATION[ knownRank( REND ) ] or 9 end,
        tick_time = 3,
        max_stack = 1,
    },
    retaliation = {
        id = 20230,
        duration = 15,
        max_stack = 1,
    },
    revenge_stun = {
        id = 12798,
        duration = 3,
        max_stack = 1,
    },
    -- Revenge's window from its plain usability (reset_precast): 5 s from that read, not from the block, dodge or
    -- parry (no combat log on Forever to time the proc).
    revenge_usable = {
        duration = 5,
        max_stack = 1,
    },
    shield_bash_silenced = {
        id = 18498,
        duration = 3,
        max_stack = 1,
    },
    shield_block = {
        id = 2565,
        duration = function () return 7 + ( SHIELD_BLOCK_BONUS[ talent.improved_shield_block.rank ] or 0 ) end,
        max_stack = 1,
    },
    shield_wall = {
        id = 871,
        duration = 12,
        max_stack = 1,
    },
    sunder_armor = {
        id = 7386,
        copy = rest( SUNDER_ARMOR ),
        duration = 30,
        max_stack = 5,
    },
    sweeping_strikes = {
        id = 12292,
        duration = 20,
        max_stack = 5,
    },
    taunt = {
        id = 355,
        duration = 3,
        max_stack = 1,
    },
    thunder_clap = {
        id = 6343,
        copy = rest( THUNDER_CLAP ),
        duration = function () return THUNDER_CLAP_DURATION[ knownRank( THUNDER_CLAP ) ] or 10 end,
        max_stack = 1,
        shared = "target",
    },
    windfury = {
        id = 8512,
        copy = { 10613, 10614 },
        duration = 300,
        max_stack = 1,
    },
} )

local STANCE_OF_SPELL = { [ 2457 ] = "battle_stance", [ 71 ] = "defensive_stance", [ 2458 ] = "berserker_stance" }

-- A stance change drops all rage above what is kept: Forever's Tactical Mastery passive keeps 10, Improved Tactical
-- Mastery 15 more a rank (DB2: 1310185 keeps $m1 + $12295m1; 12295's m1 is 15). Rage tops out at 100, so no cap.
spec:RegisterStateFunction( "swap_stance", function( stance )
    removeBuff( "battle_stance" )
    removeBuff( "defensive_stance" )
    removeBuff( "berserker_stance" )

    local kept = ( IsSpellKnown( TACTICAL_MASTERY ) and 10 or 0 ) + 15 * talent.improved_tactical_mastery.rank
    local lost = rage.current - kept
    if lost > 0 then spend( lost, "rage" ) end

    applyBuff( stance )
end )

spec:RegisterHook( "reset_precast", function()
    -- The stance from the plain shapeshift reads (forever-facade-notes: GetShapeshiftForm, GetShapeshiftFormInfo).
    removeBuff( "battle_stance" )
    removeBuff( "defensive_stance" )
    removeBuff( "berserker_stance" )
    local form = GetShapeshiftForm()
    if form and form > 0 then
        local _, _, _, spellID = GetShapeshiftFormInfo( form )
        local stance = STANCE_OF_SPELL[ spellID ]
        if stance then applyBuff( stance ) end
    end

    local hs, cl = knownRank( HEROIC_STRIKE ), knownRank( CLEAVE )
    if hs > 0 and IsCurrentSpell( HEROIC_STRIKE[ hs ] ) then applyBuff( "heroic_strike" ) end
    if cl > 0 and IsCurrentSpell( CLEAVE[ cl ] ) then applyBuff( "cleave" ) end

    if reactive( REVENGE ) then applyBuff( "revenge_usable" ) end
end )

-- `timeToReady` of the three stances: they share a 1 s category cooldown.
local function stanceReady()
    return max( cooldown.battle_stance.remains, cooldown.defensive_stance.remains, cooldown.berserker_stance.remains )
end

spec:RegisterAbilities( {
    battle_shout = {
        id = 6673,
        copy = rest( BATTLE_SHOUT ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        known = knows( BATTLE_SHOUT ),

        handler = function ()
            applyBuff( "battle_shout" )
        end,
    },

    battle_stance = {
        id = 2457,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows( { 2457 } ),
        nobuff = "battle_stance",
        timeToReady = stanceReady,

        handler = function ()
            swap_stance( "battle_stance" )
        end,
    },

    berserker_rage = {
        id = 18499,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        startsCombat = false,
        known = knows( { 18499 } ),
        buff = "berserker_stance",

        handler = function ()
            applyBuff( "berserker_rage" )
            if talent.improved_berserker_rage.enabled then gain( 5 * talent.improved_berserker_rage.rank, "rage" ) end
        end,
    },

    berserker_stance = {
        id = 2458,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows( { 2458 } ),
        nobuff = "berserker_stance",
        timeToReady = stanceReady,

        handler = function ()
            swap_stance( "berserker_stance" )
        end,
    },

    -- 10 rage now (DB2: energize 100), then 10 over 10 s from its aura (the resource's bloodrage entry). Its health
    -- cost is not simulated: the player's health is secret on Forever.
    bloodrage = {
        id = 2687,
        cast = 0,
        cooldown = 60,
        gcd = "off",

        startsCombat = true,
        known = knows( { 2687 } ),
        toggle = "cooldowns",

        handler = function ()
            gain( 10 + ( talent.improved_bloodrage.rank == 1 and 2 or talent.improved_bloodrage.rank == 2 and 5 or 0 ), "rage" )
            applyBuff( "bloodrage" )
        end,
    },

    bloodthirst = {
        id = 23881,
        copy = rest( BLOODTHIRST ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 30,
        spendType = "rage",

        talent = "bloodthirst",
        startsCombat = true,
        known = knows( BLOODTHIRST ),
    },

    challenging_shout = {
        id = 1161,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 1161 } ),
        toggle = "defensives",

        handler = function ()
            applyDebuff( "target", "challenging_shout" )
        end,
    },

    charge = {
        id = 100,
        copy = rest( CHARGE ),
        cast = 0,
        cooldown = 15,
        gcd = "off",

        startsCombat = true,
        known = knows( CHARGE ),
        buff = "battle_stance",

        usable = function ()
            return combat == 0 and target.minR >= 8 and target.minR <= 25, "cannot be in combat; target must be outside your deadzone"
        end,

        handler = function ()
            setDistance( 7 )
            if not target.is_boss then applyDebuff( "target", "charge_stun" ) end
            gain( ( CHARGE_RAGE[ knownRank( CHARGE ) ] or 9 ) + 3 * talent.improved_charge.rank, "rage" )
        end,
    },

    cleave = {
        id = 845,
        copy = rest( CLEAVE ),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function () return max( 0, 20 - 3 * talent.improved_cleave.rank ) end,
        spendType = "rage",

        startsCombat = true,
        onNextSwing = true, -- VirtualState: paid at the main hand's next swing, which then brings no rage
        known = knows( CLEAVE ),

        usable = function ()
            return not buff.heroic_strike.up and not buff.cleave.up, "a strike is already queued"
        end,

        handler = function ()
            applyBuff( "cleave" )
        end,
    },

    concussion_blow = {
        id = 12809,
        cast = 0,
        cooldown = 45,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        talent = "concussion_blow",
        startsCombat = true,
        known = knows( { 12809 } ),

        handler = function ()
            applyDebuff( "target", "concussion_blow" )
        end,
    },

    death_wish = {
        id = 12328,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "death_wish",
        startsCombat = true,
        known = knows( { 12328 } ),
        toggle = "cooldowns",

        handler = function ()
            applyBuff( "death_wish" )
        end,
    },

    defensive_stance = {
        id = 71,
        cast = 0,
        cooldown = 1,
        gcd = "off",

        startsCombat = false,
        known = knows( { 71 } ),
        nobuff = "defensive_stance",
        timeToReady = stanceReady,

        handler = function ()
            swap_stance( "defensive_stance" )
        end,
    },

    demoralizing_shout = {
        id = 1160,
        copy = rest( DEMORALIZING_SHOUT ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( DEMORALIZING_SHOUT ),

        handler = function ()
            applyDebuff( "target", "demoralizing_shout" )
            active_dot.demoralizing_shout = active_enemies
        end,
    },

    disarm = {
        id = 676,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = 20,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 676 } ),
        toggle = "cooldowns",
        buff = "defensive_stance",

        handler = function ()
            applyDebuff( "target", "disarm" )
        end,
    },

    -- Usable below 20% health: the target's health is secret on Forever, so the window is the plain usability read.
    execute = {
        id = 5308,
        copy = rest( EXECUTE ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function () return max( 0, 15 - 5 * talent.improved_execute.rank ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( EXECUTE ),

        usable = function () return reactive( EXECUTE ), "requires target health under 20 percent" end,

        handler = function ()
            spend( rage.current, "rage" ) -- the rest of the rage goes into the strike
        end,
    },

    hamstring = {
        id = 1715,
        copy = rest( HAMSTRING ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( HAMSTRING ),
        nobuff = "defensive_stance",

        handler = function ()
            applyDebuff( "target", "hamstring" )
        end,
    },

    heroic_strike = {
        id = 78,
        copy = rest( HEROIC_STRIKE ),
        cast = 0,
        cooldown = 0,
        gcd = "off",

        spend = function () return 15 - talent.improved_heroic_strike.rank end, -- Improved Heroic Strike: -1 a rank
        spendType = "rage",

        startsCombat = true,
        -- VirtualState: paid at the main hand's next swing, which then brings no rage. Hekili's own simulation ignores
        -- onNextSwing: it spends the cost at the press and still adds the replaced swing's rage, so its forward
        -- projection is one swing of rage optimistic per queued strike until VirtualState's next drain corrects the
        -- belief (checkpoint Q9). Cleave alike.
        onNextSwing = true,
        known = knows( HEROIC_STRIKE ),

        usable = function ()
            return not buff.heroic_strike.up and not buff.cleave.up, "a strike is already queued"
        end,

        handler = function ()
            applyBuff( "heroic_strike" )
        end,
    },

    intercept = {
        id = 20252,
        copy = rest( INTERCEPT ),
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( INTERCEPT ),
        buff = "berserker_stance",

        handler = function ()
            setDistance( 7 )
            applyDebuff( "target", "intercept_stun" )
        end,
    },

    intimidating_shout = {
        id = 5246,
        cast = 0,
        cooldown = 180,
        gcd = "spell",

        spend = 25,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 5246 } ),
        toggle = "cooldowns",

        handler = function ()
            applyDebuff( "target", "intimidating_shout" )
        end,
    },

    -- Classic also raised the simulated maximum health; the player's health is secret on Forever.
    last_stand = {
        id = 12975,
        cast = 0,
        cooldown = 180,
        gcd = "off",

        talent = "last_stand",
        startsCombat = false,
        known = knows( { 12975 } ),
        toggle = "defensives",

        handler = function ()
            applyBuff( "last_stand" )
        end,
    },

    mocking_blow = {
        id = 694,
        copy = rest( MOCKING_BLOW ),
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( MOCKING_BLOW ),
        toggle = "cooldowns",
        buff = "battle_stance",

        handler = function ()
            applyDebuff( "target", "mocking_blow" )
        end,
    },

    mortal_strike = {
        id = 12294,
        copy = rest( MORTAL_STRIKE ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 30,
        spendType = "rage",

        talent = "mortal_strike",
        startsCombat = true,
        known = knows( MORTAL_STRIKE ),

        handler = function ()
            applyDebuff( "target", "mortal_strike" )
        end,
    },

    overpower = {
        id = 7384,
        copy = rest( OVERPOWER ),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows( OVERPOWER ),
        buff = "battle_stance",

        usable = function () return buff.overpower_ready.up, "only usable after the target dodges" end,

        handler = function ()
            removeBuff( "overpower_ready" )
        end,
    },

    piercing_howl = {
        id = 12323,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        talent = "piercing_howl",
        startsCombat = true,
        known = knows( { 12323 } ),

        handler = function ()
            applyDebuff( "target", "piercing_howl" )
        end,
    },

    pummel = {
        id = 6552,
        copy = rest( PUMMEL ),
        cast = 0,
        cooldown = 10,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( PUMMEL ),
        buff = "berserker_stance",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
        end,
    },

    recklessness = {
        id = 1719,
        cast = 0,
        cooldown = 1800,
        gcd = "spell",

        startsCombat = false,
        known = knows( { 1719 } ),
        toggle = "cooldowns",
        buff = "berserker_stance",

        handler = function ()
            applyBuff( "recklessness" )
        end,
    },

    rend = {
        id = 772,
        copy = rest( REND ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( REND ),
        nobuff = "berserker_stance",

        handler = function ()
            applyDebuff( "target", "rend" )
        end,
    },

    retaliation = {
        id = 20230,
        cast = 0,
        cooldown = 900,
        gcd = "spell",

        startsCombat = false,
        known = knows( { 20230 } ),
        toggle = "cooldowns",
        buff = "battle_stance",

        handler = function ()
            applyBuff( "retaliation" )
        end,
    },

    revenge = {
        id = 6572,
        copy = rest( REVENGE ),
        cast = 0,
        cooldown = 5,
        gcd = "spell",

        spend = 5,
        spendType = "rage",

        startsCombat = true,
        known = knows( REVENGE ),

        buff = function ()
            if buff.revenge_usable.up then return "defensive_stance" end
            return "revenge_usable"
        end,

        handler = function ()
            removeBuff( "revenge_usable" )
        end,
    },

    shield_bash = {
        id = 72,
        copy = rest( SHIELD_BASH ),
        cast = 0,
        cooldown = 12,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        known = knows( SHIELD_BASH ),
        toggle = "interrupts",
        buff = function () return buff.battle_stance.up and "battle_stance" or "defensive_stance" end,
        equipped = "shield",
        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
            if talent.improved_shield_bash.rank == 2 then applyDebuff( "target", "shield_bash_silenced" ) end
        end,
    },

    shield_block = {
        id = 2565,
        cast = 0,
        cooldown = 5,
        gcd = "off",

        spend = 10,
        spendType = "rage",

        startsCombat = false,
        known = knows( { 2565 } ),
        buff = "defensive_stance",
        equipped = "shield",

        handler = function ()
            applyBuff( "shield_block" )
        end,
    },

    shield_slam = {
        id = 23922,
        copy = rest( SHIELD_SLAM ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 20,
        spendType = "rage",

        startsCombat = true,
        known = knows( SHIELD_SLAM ),
        equipped = "shield",
    },

    shield_wall = {
        id = 871,
        cast = 0,
        cooldown = 900,
        gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)

        startsCombat = false,
        known = knows( { 871 } ),
        toggle = "defensives",
        buff = "defensive_stance",
        equipped = "shield",

        handler = function ()
            applyBuff( "shield_wall" )
        end,
    },

    -- Forever gave Slam an 18 s cooldown (DB2 category recovery) and a rank 1 at level 20.
    slam = {
        id = 1240193,
        copy = rest( SLAM ),
        cast = 1.5,
        cooldown = 18,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        known = knows( SLAM ),
    },

    -- Forever: a strike with a 20 s cooldown, learned at level 1 (DB2 1310222).
    spearing_strike = {
        id = 1310222,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        spend = 15,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 1310222 } ),
    },

    sunder_armor = {
        id = 7386,
        copy = rest( SUNDER_ARMOR ),
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function () return max( 0, 15 - 3 * talent.improved_sunder_armor.rank ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( SUNDER_ARMOR ),

        handler = function ()
            applyDebuff( "target", "sunder_armor", nil, min( 5, debuff.sunder_armor.stack + 1 ) )
        end,
    },

    sweeping_strikes = {
        id = 12292,
        cast = 0,
        cooldown = 30,
        gcd = "off",

        spend = 30,
        spendType = "rage",

        talent = "sweeping_strikes",
        startsCombat = false,
        known = knows( { 12292 } ),
        buff = "battle_stance",

        handler = function ()
            applyBuff( "sweeping_strikes", nil, 5 )
        end,
    },

    taunt = {
        id = 355,
        cast = 0,
        cooldown = function () return 8 - talent.improved_taunt.rank end, -- Improved Taunt: -1 s a rank (both in the DB2)
        gcd = "off",

        startsCombat = true,
        known = knows( { 355 } ),
        buff = "defensive_stance",

        handler = function ()
            applyDebuff( "target", "taunt" )
        end,
    },

    thunder_clap = {
        id = 6343,
        copy = rest( THUNDER_CLAP ),
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = function () return max( 0, 20 - 6 * talent.improved_thunder_clap.rank ) end,
        spendType = "rage",

        startsCombat = true,
        known = knows( THUNDER_CLAP ),
        buff = "battle_stance",

        handler = function ()
            applyDebuff( "target", "thunder_clap" )
            active_dot.thunder_clap = min( active_enemies, 4 + active_dot.thunder_clap )
        end,
    },

    -- Forever: usable for a while after a kill that yields experience or honor; free, 30 s cooldown (DB2 402927).
    victory_rush = {
        id = 402927,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        startsCombat = true,
        known = knows( VICTORY_RUSH ),

        usable = function () return reactive( VICTORY_RUSH ), "only usable after a kill" end,
    },

    whirlwind = {
        id = 1680,
        cast = 0,
        cooldown = 10,
        gcd = "spell",

        spend = 25,
        spendType = "rage",

        startsCombat = true,
        known = knows( { 1680 } ),
        buff = "berserker_stance",
    },
} )

spec:RegisterOptions( { package = "Warrior" } )

-- Payload: spec 1491; precombat battle_shout; default battle_shout, rend (!debuff.rend.up), heroic_strike (rage>=30). Generated by tools/make_pack.lua (the share format RestoreDefaults decodes).
spec:RegisterPack( "Warrior", 20261015, [[Hekili:TkvWUrnmq0VfUbIQWMwajQu4qpuv4WQkmcUn1tCM0yf3yl7jG6f)TZy3DxTlqpGekso2JFZBEVzm0cFfuditW2Z3C(7B30(oqXpgiqfqZmEVSzbFqw)ogJwFSe)rNhhkj2VAD8NwG()KJuGmW223(HwqnzhgONqrjdOU2hPFqXSEhNz9yzHNOS(B2iVIofl8L13oHj5xBwBMiZCWBx4lZ6RqMDsC1KFLZ61Wzz9xOLHSEMc7dCdf9wJaIJ2zb8pT8uwNcyuoefN1iEj6hToXDOHT(Lutisg)d9i31xRXDPsjoZo29I(1XXMJJ2SgYFExI)JWFD3BIIERahOk0Y5FdYu1b3LQgOGTO6p2DXgqjTVKG64oUZM4uDCsJ4QJLTBRJxAb7D0aC1EBkdUJ0fOmrltrlcQ)QQbwkZZqur1NqWPUPK6fptQN4UJ54Glz5tDyI8)0pvMXvEQ8G(gA26Sz9l39U8v1RHF9]] )
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `104 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [104 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 65 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output] (modified and new files, new directories included)
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Warrior.lua Forever/spec/helpers/load_warrior.lua Forever/spec/warrior_spec.lua .busted .luacheckrc
git commit -m "feat(forever): the Classic Warrior kit with Forever's spell data; Bloodrage, stances, Victory Rush, Spearing Strike; a headless spec of the registrations

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-warrior-profile`

### Task 3: The three talent trees with their rank aliases

All 52 talents (`wowdb talents WARRIOR`: 18 Arms, 17 Fury, 17 Protection), as `{ 0, rank 1 spell, max rank }` (the Phase 1 shape, `Forever/Warrior.lua` RegisterTalents), and a `Track{ talents }` alias for each of the 120 higher-rank spells (spec §3.6), so VirtualState's talent family (Phase 1 Task 6) maps whichever rank spell the trait walk reports to its talent. Keys are Classic's (Classic/Warrior.lua:84-137); where the DB2's name is blank or shared they come from Classic too: `axe_specialization` 12700, `mace_specialization` 12284, `sword_specialization` 12281 (all "Weaponmaster" in the DB2), `polearm_specialization` 12165, `iron_will` 12300, `defiance` 12303 (blank), `one_handed_weapon_specialization` 16538 ("Bastion"). `improved_tactical_mastery` keeps Phase 1's key (Classic's was `tactical_mastery`; Task 2's `swap_stance` reads it). Classic's `improved_rend` row listed Rend's rank IDs (Classic/Warrior.lua:87); the DB2's 12286/12658/12659 are used.

**Files:**
- Modify: `Forever/Warrior.lua` (the `RegisterTalents` and `Track` blocks, after `spec:RegisterResource`)
- Test: `Forever/spec/warrior_spec.lua`

**Interfaces:**
- Consumes: Task 2's loader (`w.talents`, `w.track`).
- Produces: the 52 talent keys (Task 4's priorities read `talent.mortal_strike` and `talent.bloodthirst`; Task 2's handlers read `improved_*` ranks).

- [ ] **Step 1: Write the failing spec**

Apply with `git apply`:

```diff
diff --git a/Forever/spec/warrior_spec.lua b/Forever/spec/warrior_spec.lua
index e9d7d6b1..b2144d71 100644
--- a/Forever/spec/warrior_spec.lua
+++ b/Forever/spec/warrior_spec.lua
@@ -55,6 +55,62 @@ local KIT = {
     whirlwind = { { 1680 }, 25, 10, "spell" },
 }
 
+-- key = the talent's rank spells (wowdb talents WARRIOR, r1..r5): 18 Arms, 17 Fury, 17 Protection.
+local TALENTS = {
+    improved_heroic_strike = { 12282, 12663, 12664 },
+    deflection = { 16462, 16463, 16464, 16465, 16466 },
+    improved_rend = { 12286, 12658, 12659 },
+    improved_charge = { 12285, 12697 },
+    improved_tactical_mastery = { 12295, 12676, 12677, 12678, 12679 },
+    improved_thunder_clap = { 12287, 12665, 12666 },
+    improved_overpower = { 12290, 12963 },
+    anger_management = { 12296 },
+    deep_wounds = { 12834, 12849, 12867 },
+    two_handed_weapon_specialization = { 12163, 12711, 12712, 12713, 12714 },
+    impale = { 16493, 16494 },
+    axe_specialization = { 12700, 12781, 12783, 12784, 12785 },
+    sweeping_strikes = { 12292 },
+    mace_specialization = { 12284, 12701, 12702, 12703, 12704 },
+    sword_specialization = { 12281, 12812, 12813, 12814, 12815 },
+    polearm_specialization = { 12165, 12830, 12831, 12832, 12833 },
+    improved_hamstring = { 12289, 12668, 23695 },
+    mortal_strike = { 12294 },
+    booming_voice = { 12321, 12835, 12836, 12837, 12838 },
+    cruelty = { 12320, 12852, 12853, 12855, 12856 },
+    improved_demoralizing_shout = { 12324, 12876, 12877, 12878, 12879 },
+    unbridled_wrath = { 12322, 12999, 13000, 13001, 13002 },
+    improved_cleave = { 12329, 12950, 20496 },
+    piercing_howl = { 12323 },
+    blood_craze = { 16487, 16489, 16492 },
+    improved_battle_shout = { 12318, 12857, 12858, 12860, 12861 },
+    dual_wield_specialization = { 23584, 23585, 23586, 23587, 23588 },
+    improved_execute = { 20502, 20503 },
+    enrage = { 12317, 13045, 13046, 13047, 13048 },
+    improved_slam = { 12862, 12330, 20497, 20498, 20499 },
+    death_wish = { 12328 },
+    improved_intercept = { 20504, 20505 },
+    improved_berserker_rage = { 20500, 20501 },
+    flurry = { 12319, 12971, 12972, 12973, 12974 },
+    bloodthirst = { 23881 },
+    shield_specialization = { 12298, 12724, 12725, 12726, 12727 },
+    anticipation = { 12297, 12750, 12751, 12752, 12753 },
+    improved_bloodrage = { 12301, 12818 },
+    toughness = { 12299, 12761, 12762, 12763, 12764 },
+    iron_will = { 12300, 12959, 12960, 12961, 12962 },
+    last_stand = { 12975 },
+    improved_shield_block = { 12945, 12307, 12944 },
+    improved_revenge = { 12797, 12799, 12800 },
+    defiance = { 12303, 12788, 12789, 12791, 12792 },
+    improved_sunder_armor = { 12308, 12810, 12811 },
+    improved_disarm = { 12313, 12804, 12807 },
+    improved_taunt = { 12302, 12765 },
+    improved_shield_wall = { 12312, 12803 },
+    concussion_blow = { 12809 },
+    improved_shield_bash = { 12311, 12958 },
+    one_handed_weapon_specialization = { 16538, 16539, 16540, 16541, 16542 },
+    shield_slam = { 23922 },
+}
+
 local function idsOf(a)
     local ids = { a.id }
     for _, v in ipairs(a.copy or {}) do
@@ -140,6 +196,26 @@ describe("Forever Warrior", function()
         assert.are.equal("mainhand", models.mainhand.swing)
     end)
 
+    it("registers the three talent trees, and maps every higher rank spell to its rank 1 for the trait walk", function()
+        local n, aliases = 0, 0
+        for key, ranks in pairs(TALENTS) do
+            n = n + 1
+            assert.are.same({ 0, ranks[1], #ranks }, w.talents[key], key)
+            for r = 2, #ranks do
+                assert.are.equal(ranks[1], w.track[ranks[r]], key .. " rank " .. r)
+            end
+            aliases = aliases + #ranks - 1
+        end
+        local registered, tracked = 0, 0
+        for _ in pairs(w.talents) do
+            registered = registered + 1
+        end
+        for _ in pairs(w.track) do
+            tracked = tracked + 1
+        end
+        assert.are.same({ 52, 52, 120, 120 }, { n, registered, aliases, tracked })
+    end)
+
     it("reads the stance, a queued strike and Revenge's window at reset", function()
         local e = lw.env(w)
         w.game.form, w.game.formSpell[2] = 2, 71
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `104 successes / 1 failure / 0 errors` — `warrior_spec.lua:203`, naming the first talent key the file lacks (e.g. `improved_sunder_armor`).

- [ ] **Step 3: Register the three trees and the aliases**

Apply with `git apply`:

```diff
diff --git a/Forever/Warrior.lua b/Forever/Warrior.lua
index dcd5b8b4..7dc1e7a8 100644
--- a/Forever/Warrior.lua
+++ b/Forever/Warrior.lua
@@ -122,8 +122,11 @@ spec:RegisterResource( Enum.PowerType.Rage, {
     },
 } )
 
--- Talents: { node (unused on Forever), the rank 1 spell, max rank }; VirtualState maps the trait walk's spells to them.
+-- Talents: { node (unused on Forever), the rank 1 spell, max rank }, all three trees (wowdb talents WARRIOR); keys are
+-- Classic's where the DB2's name is blank or shared (Weaponmaster, Iron Will, Defiance, the polearm specialization).
+-- VirtualState maps the trait walk's spells to them.
 spec:RegisterTalents( {
+    -- Arms (18)
     improved_heroic_strike           = { 0, 12282, 3 },
     deflection                       = { 0, 16462, 5 },
     improved_rend                    = { 0, 12286, 3 },
@@ -135,13 +138,54 @@ spec:RegisterTalents( {
     deep_wounds                      = { 0, 12834, 3 },
     two_handed_weapon_specialization = { 0, 12163, 5 },
     impale                           = { 0, 16493, 2 },
+    axe_specialization               = { 0, 12700, 5 },
     sweeping_strikes                 = { 0, 12292, 1 },
+    mace_specialization              = { 0, 12284, 5 },
+    sword_specialization             = { 0, 12281, 5 },
+    polearm_specialization           = { 0, 12165, 5 },
     improved_hamstring               = { 0, 12289, 3 },
     mortal_strike                    = { 0, 12294, 1 },
+    -- Fury (17)
+    booming_voice                    = { 0, 12321, 5 },
+    cruelty                          = { 0, 12320, 5 },
+    improved_demoralizing_shout      = { 0, 12324, 5 },
+    unbridled_wrath                  = { 0, 12322, 5 },
+    improved_cleave                  = { 0, 12329, 3 },
+    piercing_howl                    = { 0, 12323, 1 },
+    blood_craze                      = { 0, 16487, 3 },
+    improved_battle_shout            = { 0, 12318, 5 },
+    dual_wield_specialization        = { 0, 23584, 5 },
+    improved_execute                 = { 0, 20502, 2 },
+    enrage                           = { 0, 12317, 5 },
+    improved_slam                    = { 0, 12862, 5 },
+    death_wish                       = { 0, 12328, 1 },
+    improved_intercept               = { 0, 20504, 2 },
+    improved_berserker_rage          = { 0, 20500, 2 },
+    flurry                           = { 0, 12319, 5 },
+    bloodthirst                      = { 0, 23881, 1 },
+    -- Protection (17)
+    shield_specialization            = { 0, 12298, 5 },
+    anticipation                     = { 0, 12297, 5 },
+    improved_bloodrage               = { 0, 12301, 2 },
+    toughness                        = { 0, 12299, 5 },
+    iron_will                        = { 0, 12300, 5 },
+    last_stand                       = { 0, 12975, 1 },
+    improved_shield_block            = { 0, 12945, 3 },
+    improved_revenge                 = { 0, 12797, 3 },
+    defiance                         = { 0, 12303, 5 },
+    improved_sunder_armor            = { 0, 12308, 3 },
+    improved_disarm                  = { 0, 12313, 3 },
+    improved_taunt                   = { 0, 12302, 2 },
+    improved_shield_wall             = { 0, 12312, 2 },
+    concussion_blow                  = { 0, 12809, 1 },
+    improved_shield_bash             = { 0, 12311, 2 },
+    one_handed_weapon_specialization = { 0, 16538, 5 },
+    shield_slam                      = { 0, 23922, 1 },
 } )
 
 -- The higher rank spells of each talent, in case the trait walk names a rank rather than rank 1 (spec §3.6 Track).
 ns.VirtualState.Track( { talents = {
+    -- Arms
     [ 12663 ] = 12282, [ 12664 ] = 12282,
     [ 16463 ] = 16462, [ 16464 ] = 16462, [ 16465 ] = 16462, [ 16466 ] = 16462,
     [ 12658 ] = 12286, [ 12659 ] = 12286,
@@ -152,7 +196,41 @@ ns.VirtualState.Track( { talents = {
     [ 12849 ] = 12834, [ 12867 ] = 12834,
     [ 12711 ] = 12163, [ 12712 ] = 12163, [ 12713 ] = 12163, [ 12714 ] = 12163,
     [ 16494 ] = 16493,
+    [ 12781 ] = 12700, [ 12783 ] = 12700, [ 12784 ] = 12700, [ 12785 ] = 12700,
+    [ 12701 ] = 12284, [ 12702 ] = 12284, [ 12703 ] = 12284, [ 12704 ] = 12284,
+    [ 12812 ] = 12281, [ 12813 ] = 12281, [ 12814 ] = 12281, [ 12815 ] = 12281,
+    [ 12830 ] = 12165, [ 12831 ] = 12165, [ 12832 ] = 12165, [ 12833 ] = 12165,
     [ 12668 ] = 12289, [ 23695 ] = 12289,
+    -- Fury
+    [ 12835 ] = 12321, [ 12836 ] = 12321, [ 12837 ] = 12321, [ 12838 ] = 12321,
+    [ 12852 ] = 12320, [ 12853 ] = 12320, [ 12855 ] = 12320, [ 12856 ] = 12320,
+    [ 12876 ] = 12324, [ 12877 ] = 12324, [ 12878 ] = 12324, [ 12879 ] = 12324,
+    [ 12999 ] = 12322, [ 13000 ] = 12322, [ 13001 ] = 12322, [ 13002 ] = 12322,
+    [ 12950 ] = 12329, [ 20496 ] = 12329,
+    [ 16489 ] = 16487, [ 16492 ] = 16487,
+    [ 12857 ] = 12318, [ 12858 ] = 12318, [ 12860 ] = 12318, [ 12861 ] = 12318,
+    [ 23585 ] = 23584, [ 23586 ] = 23584, [ 23587 ] = 23584, [ 23588 ] = 23584,
+    [ 20503 ] = 20502,
+    [ 13045 ] = 12317, [ 13046 ] = 12317, [ 13047 ] = 12317, [ 13048 ] = 12317,
+    [ 12330 ] = 12862, [ 20497 ] = 12862, [ 20498 ] = 12862, [ 20499 ] = 12862,
+    [ 20505 ] = 20504,
+    [ 20501 ] = 20500,
+    [ 12971 ] = 12319, [ 12972 ] = 12319, [ 12973 ] = 12319, [ 12974 ] = 12319,
+    -- Protection
+    [ 12724 ] = 12298, [ 12725 ] = 12298, [ 12726 ] = 12298, [ 12727 ] = 12298,
+    [ 12750 ] = 12297, [ 12751 ] = 12297, [ 12752 ] = 12297, [ 12753 ] = 12297,
+    [ 12818 ] = 12301,
+    [ 12761 ] = 12299, [ 12762 ] = 12299, [ 12763 ] = 12299, [ 12764 ] = 12299,
+    [ 12959 ] = 12300, [ 12960 ] = 12300, [ 12961 ] = 12300, [ 12962 ] = 12300,
+    [ 12307 ] = 12945, [ 12944 ] = 12945,
+    [ 12799 ] = 12797, [ 12800 ] = 12797,
+    [ 12788 ] = 12303, [ 12789 ] = 12303, [ 12791 ] = 12303, [ 12792 ] = 12303,
+    [ 12810 ] = 12308, [ 12811 ] = 12308,
+    [ 12804 ] = 12313, [ 12807 ] = 12313,
+    [ 12765 ] = 12302,
+    [ 12803 ] = 12312,
+    [ 12958 ] = 12311,
+    [ 16539 ] = 16538, [ 16540 ] = 16538, [ 16541 ] = 16538, [ 16542 ] = 16538,
 } } )
 
 spec:RegisterAuras( {
```

- [ ] **Step 4: Run the spec to verify it passes**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `105 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [105 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 65 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output] (modified and new files, new directories included)
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Warrior.lua Forever/spec/warrior_spec.lua
git commit -m "feat(forever): the Warrior's Arms, Fury and Protection talent trees with their rank aliases

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-warrior-profile`

### Task 4: The Arms, Fury and Protection priorities, queue prediction and the Classic settings

> The `should_queue` and `mainhand_remains` code blocks below are superseded by f728e30f (the final fix wave).

`tools/make_pack.lua` becomes the source of the three priorities: each is SimC-style text, parsed into Hekili's list entries (`action`, `enabled`, `criteria`, `list_name`, `use_off_gcd`, the shape Hekili's own importer stores, as the decoded Classic packs show) and printed as a share string, one line per pack. The class file registers the three strings (`RegisterPack`, one spec 1491; Hekili picks the default from `RegisterOptions`' `package`, here Arms; `/hekili priority <name>` switches, `Options/ChatCommands.lua:586-655`).

Arms and Fury are Classic's lists (Classic/APLs/WarriorArms.simc, WarriorFury.simc) with these changes, each for a reason on Forever: `target.health.pct<=20` becomes `execute_phase` (a state expression on Execute's plain usability; the target's health always reads 100, Task 9b's warning); the `cooldowns` list Classic called but never defined is defined (Arms: Sweeping Strikes with two or more enemies, Death Wish, Recklessness; Fury: Death Wish, Recklessness; each is talent-, stance- or toggle-gated by its ability) and called on bosses or targets 3 levels above (`boss|target.level>=level+3`; Classic's `target.level>=63` assumed level 60); Classic's `rage.current>hamstring_threshold` reads the setting (`settings.hamstring_threshold`; the bare name was undefined); Fury's `bloodthirst,if=…bt_over_exec&target.time_to_die>2` and `whirlwind,if=active_enemies>=ww_breakpoint` lose the secret inputs (attack power, weapon damage, time to die): the first is dropped, the second reads `settings.ww_min_enemies` (which `ww_breakpoint` returned with adaptive Whirlwind off, its default); a precombat Battle Shout; and three Forever additions in the rotation: Victory Rush first (free, after a kill), Spearing Strike after the main strike, Rend while Mortal Strike (Arms) or Bloodthirst (Fury) is not talented (leveling below 40). Protection is provisional, in the War Within Protection list's shape (`archive/TheWarWithin/Priorities/WarriorProtection.simc:5-60`: interrupt, mitigation, `run_action_list,name=aoe` at three or more enemies, `call_action_list,name=generic`): Shield Bash, Defensive Stance, Victory Rush, Shield Block, Bloodrage below 20 rage, Battle Shout; then Revenge, Shield Slam (only when known), Sunder Armor to 5 stacks or when it runs low, Heroic Strike (Cleave in the aoe list) as the rage dump.

Queue prediction (`should_hs`, `should_cleave`, the state function `should_queue` and `mainhand_remains`) is ported from Classic/Warrior.lua:462-575 without its per-call debug strings and with a sort comparator that is not rebuilt per call; `should_queue` keys its three events by priority (Classic overwrote them by array index after sorting, which mixed them up between calls). The settings are the twelve Classic settings the lists read, with Classic's defaults (Classic/Warrior.lua:1574-1734) except `debuff_sunder_min_level`: 10, Sunder Armor's own level in the DB2 (7386), where Classic's 61 (raid bosses at level 60) would keep Sunder off at Forever's level cap; adaptive Whirlwind, adaptive execute and the unused queueing threshold are left out.

**Files:**
- Modify (whole file): `tools/make_pack.lua`
- Modify: `Forever/Warrior.lua` (from `spec:RegisterOptions( { package = "Warrior" } )` to the end)
- Test: `Forever/spec/warrior_spec.lua`

**Interfaces:**
- Consumes: Task 2's `reactive`, `knownRank`, `EXECUTE`, `MORTAL_STRIKE`, `state`, the abilities and auras (this task's own patch adds the `sort` local to the file's `local floor, max, min` line); Task 3's talent keys; Task 9b's `VS.AplSecretToken(condition)` (`VirtualState/AplWarnings.lua:65`), loaded in the spec through `VirtualState/spec/helpers/load.lua`; Hekili's `RegisterStateExpr` (`Classes.lua:414`), `RegisterSetting` (`Classes.lua:1198`), `state:TimeToResource` (`State.lua:3340`), `state.nextMH` (`State.lua:6363`).
- Produces: state expressions `execute_phase`, `mainhand_remains`, `should_hs`, `should_cleave`; state function `should_queue(cost) -> boolean`; settings `adaptive_queueing_enabled`, `execute_queueing_enabled`, `ww_min_enemies`, `ww_cd_diff`, `overpower_enabled`, `overpower_threshold`, `hamstring_threshold`, `hamstring_cd_diff`, `debuff_sunder_enabled`, `debuff_sunder_max_stack`, `debuff_sunder_min_level`, `debuff_demoshout_enabled`; packs "Arms", "Fury", "Protection" (version 20261015); `tools/make_pack.lua` prints three lines and, loaded with the argument `"lists"`, returns `PACKS` (`{ name, desc, simc, lists }`).

- [ ] **Step 1: Write the failing specs**

Apply with `git apply`:

```diff
diff --git a/Forever/spec/warrior_spec.lua b/Forever/spec/warrior_spec.lua
index b2144d71..5f1a6be8 100644
--- a/Forever/spec/warrior_spec.lua
+++ b/Forever/spec/warrior_spec.lua
@@ -245,4 +245,71 @@ describe("Forever Warrior", function()
         w.game.usable[20658] = true
         assert.is_true(lw.run(w.abilities.execute.usable, e))
     end)
+
+    it("registers the Arms, Fury and Protection priorities exactly as tools/make_pack.lua prints them", function()
+        local printed = {}
+        local pipe = assert(io.popen("lua5.1 tools/make_pack.lua"))
+        for line in pipe:lines() do
+            printed[#printed + 1] = line
+        end
+        pipe:close()
+        assert.are.equal(3, #w.packs)
+        for i, name in ipairs({ "Arms", "Fury", "Protection" }) do
+            assert.are.same({ name, 20261015, printed[i] }, w.packs[i])
+        end
+        assert.are.same({ package = "Arms" }, w.options)
+    end)
+
+    it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
+        local packs = assert(loadfile("tools/make_pack.lua"))("lists")
+        local secretToken = require("VirtualState.spec.helpers.load").module().VirtualState.AplSecretToken
+        local kinds = {
+            buff = w.auras,
+            debuff = w.auras,
+            action = w.abilities,
+            cooldown = w.abilities,
+            talent = w.talents,
+            settings = w.settings,
+        }
+        for _, p in ipairs(packs) do
+            for list, entries in pairs(p.lists) do
+                for i, e in ipairs(entries) do
+                    local where = p.name .. " " .. list .. " " .. i
+                    if e.list_name then
+                        assert.is_not_nil(p.lists[e.list_name], where .. ": no list " .. e.list_name)
+                    else
+                        assert.is_not_nil(w.abilities[e.action], where .. ": no ability " .. e.action)
+                    end
+                    local c = e.criteria or ""
+                    for kind, key in c:gmatch("(%a+)%.([%w_]+)") do
+                        if kinds[kind] then
+                            assert.is_not_nil(kinds[kind][key], where .. ": no " .. kind .. " " .. key)
+                        end
+                    end
+                    assert.is_nil(secretToken(c), where) -- no health or time to die: secret on Forever (Task 9b)
+                end
+            end
+        end
+        for _, name in ipairs({ "execute_phase", "should_hs", "should_cleave", "mainhand_remains" }) do
+            assert.are.equal("function", type(w.exprs[name]), name)
+        end
+    end)
+
+    it("queues a strike only when the rage for the next strike and Whirlwind still arrives in time", function()
+        local e = lw.env(w)
+        e.query_time, e.mainhand_remains = 0, 2
+        e.action = setmetatable({}, {
+            __index = function()
+                return { cost = 30 }
+            end,
+        })
+        w.state.TimeToResource = function(_, _, amount)
+            return amount / 10 -- 10 rage a second
+        end
+        assert.is_false(e.should_queue(15)) -- Bloodthirst and Whirlwind are both ready now: 60 rage needed at once
+        w.state.TimeToResource = function()
+            return 0
+        end
+        assert.is_true(e.should_queue(15))
+    end)
 end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `105 successes / 1 failure / 2 errors` — `warrior_spec.lua:256` (1 pack, not 3), `:274: bad argument #1 to 'ipairs'` (the old generator returns no lists), `:309: attempt to call field 'should_queue' (a nil value)`.

- [ ] **Step 3: Write the generator**

`tools/make_pack.lua` (whole file):

```lua
-- tools/make_pack.lua: prints the Forever Warrior's priorities in the share format RegisterPack takes ("Hekili:" +
-- LibDeflate print encoding of the AceSerializer'd package), one line per pack in PACKS order, built headless with the
-- vendored libraries. Run from the repository root:
--   lua5.1 tools/make_pack.lua
-- Edit a pack's SimC-style text below, run it, and paste each printed string into its spec:RegisterPack( ... [[ ]] )
-- in Forever/Warrior.lua (Forever/spec/warrior_spec.lua fails until they match). Loaded with the argument "lists"
-- (loadfile(...)("lists")) it returns PACKS with each pack's parsed lists instead, for that spec.
-- The Arms and Fury lists are ported from Hekili's Classic profile (origin/classic:Classic/APLs/WarriorArms.simc,
-- WarriorFury.simc); the Protection list's shape is archive/TheWarWithin/Priorities/WarriorProtection.simc's.

local DATE = 20261015

-- Shared by Arms and Fury (Classic's head of both lists). Forever changes: the execute phase is the plain usability
-- read (`execute_phase`), the target's health being secret; `cooldowns` is defined (Classic called it undefined) and
-- called on bosses and on targets 3 levels above (Classic: target.level>=63 at level 60).
local HEAD = [[
actions.precombat=battle_shout,if=!buff.battle_shout.up
actions=sunder_armor,if=settings.debuff_sunder_enabled&debuff.sunder_armor.stack<settings.debuff_sunder_max_stack&!debuff.expose_armor.up&target.level>=settings.debuff_sunder_min_level
actions+=/demoralizing_shout,if=settings.debuff_demoshout_enabled&!debuff.demoralizing_shout.up
actions+=/call_action_list,name=cooldowns,if=boss|target.level>=level+3
actions+=/run_action_list,name=execute,if=execute_phase
actions+=/run_action_list,name=rotation
]]

local PACKS = {
    {
        name = "Arms",
        desc = "Forever Arms Warrior, ported from Hekili's Classic Arms priority.",
        simc = HEAD .. [[
actions.cooldowns=sweeping_strikes,if=active_enemies>1
actions.cooldowns+=/death_wish
actions.cooldowns+=/recklessness
actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/execute
actions.rotation=victory_rush
actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/overpower
actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies|(!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.mortal_strike.remains+settings.ww_cd_diff)
actions.rotation+=/mortal_strike
actions.rotation+=/spearing_strike
actions.rotation+=/rend,if=!debuff.rend.up&!talent.mortal_strike.enabled
actions.rotation+=/hamstring,if=cooldown.mortal_strike.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
actions.rotation+=/bloodrage,if=rage.current<90
actions.rotation+=/battle_shout,if=!up
actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
actions.rotation+=/battle_stance,use_off_gcd=1,if=!up&settings.overpower_enabled&buff.overpower_ready.up&rage.current>=action.overpower.cost&rage.current<settings.overpower_threshold
]],
    },
    {
        name = "Fury",
        desc = "Forever Fury Warrior, ported from Hekili's Classic Fury priority.",
        simc = HEAD .. [[
actions.cooldowns=death_wish
actions.cooldowns+=/recklessness
actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.execute+=/execute
actions.rotation=victory_rush
actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
actions.rotation+=/overpower
actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies
actions.rotation+=/bloodthirst
actions.rotation+=/whirlwind,if=!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.bloodthirst.remains&cooldown.bloodthirst.remains>=settings.ww_cd_diff
actions.rotation+=/spearing_strike
actions.rotation+=/rend,if=!debuff.rend.up&!talent.bloodthirst.enabled
actions.rotation+=/hamstring,if=cooldown.bloodthirst.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
actions.rotation+=/bloodrage,if=rage.current<90
actions.rotation+=/battle_shout,if=!up
actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
actions.rotation+=/battle_stance,use_off_gcd=1,if=!up&settings.overpower_enabled&buff.overpower_ready.remains>1&rage.current>=action.overpower.cost&rage.current<settings.overpower_threshold&!buff.flurry.up&!cooldown.bloodthirst.up&!cooldown.whirlwind.up
]],
    },
    {
        name = "Protection",
        desc = "Forever Protection Warrior (provisional): Defensive Stance, Shield Block up, Revenge and Shield Slam, "
            .. "Sunder Armor stacked to 5, Heroic Strike or Cleave with spare rage.",
        simc = [[
actions.precombat=battle_shout,if=!buff.battle_shout.up
actions.precombat+=/defensive_stance,if=!buff.defensive_stance.up
actions=shield_bash
actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
actions+=/victory_rush
actions+=/shield_block,use_off_gcd=1,if=!buff.shield_block.up
actions+=/bloodrage,use_off_gcd=1,if=rage.current<20
actions+=/battle_shout,if=!buff.battle_shout.up
actions+=/run_action_list,name=aoe,if=active_enemies>=3
actions+=/call_action_list,name=generic
actions.aoe=demoralizing_shout,if=!debuff.demoralizing_shout.up
actions.aoe+=/revenge
actions.aoe+=/shield_slam
actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=40
actions.aoe+=/sunder_armor
actions.generic=revenge
actions.generic+=/shield_slam
actions.generic+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<3
actions.generic+=/heroic_strike,use_off_gcd=1,if=rage.current>=50
actions.generic+=/sunder_armor
]],
    },
}

-- One SimC-style line into its list and entry: actions[.list](=|+=/)action[,name=list][,use_off_gcd=1][,if=criteria].
local function parse(simc)
    local lists = {}
    for line in simc:gmatch("[^\n]+") do
        local list, body = line:match("^actions%.?([%w_]*)%+?=/?(.+)$")
        assert(body, "bad line: " .. line)
        list = list == "" and "default" or list
        local action, opts = body:match("^([%w_]+),?(.*)$")
        local e = { action = action, enabled = true }
        local criteria = opts:match("if=(.*)$")
        opts = opts:gsub(",?if=.*$", "")
        for k, v in opts:gmatch("([%w_]+)=([^,]+)") do
            if k == "name" then
                e.list_name = v
            elseif k == "use_off_gcd" then
                e.use_off_gcd = tonumber(v)
            end
        end
        e.criteria = criteria
        lists[list] = lists[list] or {}
        table.insert(lists[list], e)
    end
    return lists
end

for _, p in ipairs(PACKS) do
    p.lists = parse(p.simc)
end

if ... == "lists" then
    return PACKS
end

_G.strbyte, _G.strchar, _G.strsub, _G.strfind, _G.format = string.byte, string.char, string.sub, string.find, string.format
dofile("Libs/LibStub/LibStub.lua")
dofile("Libs/LibDeflate/LibDeflate.lua")
dofile("Libs/AceSerializer-3.0/AceSerializer-3.0.lua")
local LibDeflate, Serializer = LibStub("LibDeflate"), LibStub("AceSerializer-3.0")

for _, p in ipairs(PACKS) do
    local pack = {
        type = "package",
        name = p.name,
        date = DATE,
        payload = {
            spec = 1491,
            builtIn = false,
            hidden = false,
            date = DATE,
            version = DATE,
            author = "Hekili (Forever)",
            desc = p.desc,
            profile = p.simc,
            lists = p.lists,
        },
    }
    print("Hekili:" .. LibDeflate:EncodeForPrint(LibDeflate:CompressDeflate(Serializer:Serialize(pack), { level = 5 })))
end
```

Run: `lua5.1 tools/make_pack.lua | wc -l`
Expected: `3`. Run it twice and compare (`lua5.1 tools/make_pack.lua | md5sum`): the same sum both times (Lua 5.1's table order for these keys is fixed, so the strings are reproducible).

- [ ] **Step 4: Register the state expressions, settings and the three packs**

Apply with `git apply` (the three `[[Hekili:…]]` strings are the generator's three lines, in order; if a later edit changes a list, paste the new line in place of the old):

```diff
diff --git a/Forever/Warrior.lua b/Forever/Warrior.lua
index 7dc1e7a8..28673b16 100644
--- a/Forever/Warrior.lua
+++ b/Forever/Warrior.lua
@@ -20,7 +20,7 @@ if UnitClassBase( "player" ) ~= "WARRIOR" then return end
 
 local state = Hekili.State
 local IsSpellKnown, IsCurrentSpell, IsSpellUsable = C_SpellBook.IsSpellKnown, C_Spell.IsCurrentSpell, C_Spell.IsSpellUsable
-local floor, max, min = math.floor, math.max, math.min
+local floor, max, min, sort = math.floor, math.max, math.min, table.sort
 
 local spec = Hekili:NewSpecialization( 1491, false, 135328 ) -- inv_sword_27; numeric because Options formats it with %d
 if not spec then return end
@@ -1260,7 +1260,182 @@ spec:RegisterAbilities( {
     },
 } )
 
-spec:RegisterOptions( { package = "Warrior" } )
+-- The execute phase: Execute's plain usability window (the target's health is secret on Forever).
+spec:RegisterStateExpr( "execute_phase", function()
+    return reactive( EXECUTE )
+end )
 
--- Payload: spec 1491; precombat battle_shout; default battle_shout, rend (!debuff.rend.up), heroic_strike (rage>=30). Generated by tools/make_pack.lua (the share format RestoreDefaults decodes).
-spec:RegisterPack( "Warrior", 20261015, [[Hekili:TkvWUrnmq0VfUbIQWMwajQu4qpuv4WQkmcUn1tCM0yf3yl7jG6f)TZy3DxTlqpGekso2JFZBEVzm0cFfuditW2Z3C(7B30(oqXpgiqfqZmEVSzbFqw)ogJwFSe)rNhhkj2VAD8NwG()KJuGmW223(HwqnzhgONqrjdOU2hPFqXSEhNz9yzHNOS(B2iVIofl8L13oHj5xBwBMiZCWBx4lZ6RqMDsC1KFLZ61Wzz9xOLHSEMc7dCdf9wJaIJ2zb8pT8uwNcyuoefN1iEj6hToXDOHT(Lutisg)d9i31xRXDPsjoZo29I(1XXMJJ2SgYFExI)JWFD3BIIERahOk0Y5FdYu1b3LQgOGTO6p2DXgqjTVKG64oUZM4uDCsJ4QJLTBRJxAb7D0aC1EBkdUJ0fOmrltrlcQ)QQbwkZZqur1NqWPUPK6fptQN4UJ54Glz5tDyI8)0pvMXvEQ8G(gA26Sz9l39U8v1RHF9]] )
+-- Queue prediction, ported from Hekili's Classic profile (Classic/Warrior.lua:462-575, without its debug lines): the
+-- time to the next main-hand swing, and whether a strike queued now still leaves rage for the next Mortal Strike (or
+-- Bloodthirst) and Whirlwind as they come off cooldown.
+spec:RegisterStateExpr( "mainhand_remains", function()
+    if now == query_time then
+        local real = nextMH - now
+        return real > 0 and real or 0
+    end
+    if query_time <= nextMH then return nextMH - query_time end
+    return ( query_time - nextMH ) % mainhand_speed
+end )
+
+local queueEvents = {
+    { time = 0, spend = 0, priority = 1 },
+    { time = 0, spend = 0, priority = 2 },
+    { time = 0, spend = 0, priority = 3 },
+}
+
+local function byTime( a, b )
+    if a.time == b.time then return a.priority < b.priority end
+    return a.time < b.time
+end
+
+spec:RegisterStateFunction( "should_queue", function( queue_cost )
+    local ms = knownRank( MORTAL_STRIKE ) > 0
+    for i = 1, #queueEvents do
+        local e = queueEvents[ i ]
+        if e.priority == 1 then
+            e.time = query_time + ( ms and cooldown.mortal_strike.remains or cooldown.bloodthirst.remains )
+            e.spend = ms and action.mortal_strike.cost or action.bloodthirst.cost
+        elseif e.priority == 2 then
+            e.time = query_time + cooldown.whirlwind.remains
+            e.spend = action.whirlwind.cost
+        else
+            e.time = query_time + mainhand_remains
+            e.spend = queue_cost
+        end
+    end
+    sort( queueEvents, byTime )
+
+    local spent = 0
+    for i = 1, #queueEvents - 1 do
+        spent = spent + queueEvents[ i ].spend
+        local nextEvent = queueEvents[ i + 1 ]
+        if query_time + state:TimeToResource( rage, nextEvent.spend + spent ) > nextEvent.time then return false end
+    end
+    return true
+end )
+
+spec:RegisterStateExpr( "should_hs", function()
+    return should_queue( action.heroic_strike.cost )
+end )
+
+spec:RegisterStateExpr( "should_cleave", function()
+    return should_queue( action.cleave.cost )
+end )
+
+-- The Classic settings the Arms and Fury priorities read (Classic/Warrior.lua:1574-1734, same defaults). Left out:
+-- adaptive Whirlwind and Bloodthirst-in-execute (they need attack power and weapon damage, secret on Forever) and the
+-- unused queueing threshold.
+spec:RegisterSetting( "adaptive_queueing_enabled", true, {
+    type = "toggle",
+    name = "Use Queue Prediction",
+    desc = "When enabled, recommendations will use swing timers and rage calculations to determine if Heroic Strike or Cleave should be queued.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "execute_queueing_enabled", true, {
+    type = "toggle",
+    name = "Queue During Execute",
+    desc = "When enabled, recommendations will always queue Heroic Strike or Cleave during the execute phase.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "ww_min_enemies", 2, {
+    type = "range",
+    name = "Minimum Enemies For Whirlwind",
+    desc = "Select the minimum number of enemies before recommending Whirlwind over Bloodthirst or Mortal Strike.",
+    width = "full",
+    min = 0,
+    softMax = 4,
+    step = 1,
+} )
+
+spec:RegisterSetting( "ww_cd_diff", 1.5, {
+    type = "range",
+    name = "Whirlwind Cooldown Differential",
+    desc = "Select the remaining time on Bloodthirst or Mortal Strike before Whirlwind can be recommended.",
+    width = "full",
+    min = 0,
+    softMax = 2,
+    step = 0.1,
+} )
+
+spec:RegisterSetting( "overpower_enabled", true, {
+    type = "toggle",
+    name = "Use Overpower",
+    desc = "When enabled, recommendations will include swapping to Battle Stance for Overpower.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "overpower_threshold", 45, {
+    type = "range",
+    name = "Maximum Rage for Overpower",
+    desc = "Select the maximum rage allowed for a stance swap to Overpower.",
+    width = "full",
+    min = 1,
+    max = 100,
+    step = 1,
+} )
+
+spec:RegisterSetting( "hamstring_threshold", 80, {
+    type = "range",
+    name = "Hamstring Rage Threshold",
+    desc = "Select the rage threshold after which Hamstring will be recommended.",
+    width = "full",
+    min = 0,
+    softMax = 100,
+    step = 1,
+} )
+
+spec:RegisterSetting( "hamstring_cd_diff", 1.5, {
+    type = "range",
+    name = "Hamstring Cooldown Differential",
+    desc = "Select the remaining time on Bloodthirst or Mortal Strike and Whirlwind before Hamstring can be recommended.",
+    width = "full",
+    min = 0,
+    softMax = 2,
+    step = 0.1,
+} )
+
+spec:RegisterSetting( "debuff_sunder_enabled", true, {
+    type = "toggle",
+    name = "Maintain Sunder Armor",
+    desc = "When enabled, the Arms and Fury priorities will include Sunder Armor.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "debuff_sunder_max_stack", 1, {
+    type = "range",
+    name = "Max Sunders",
+    desc = "Select the maximum number of Sunder Armor stacks for Sunder Armor recommendations.",
+    width = "full",
+    min = 1,
+    max = 5,
+    step = 1,
+} )
+
+-- Forever default: Sunder Armor's own level in the DB2 (7386, level 10), so Sunder is on from the start; Classic's 61
+-- kept it to raid bosses at level 60.
+spec:RegisterSetting( "debuff_sunder_min_level", 10, {
+    type = "range",
+    name = "Minimum Sunder Level",
+    desc = "Select the minimum target level before recommending Sunder Armor.",
+    width = "full",
+    min = 0,
+    max = 63,
+    step = 1,
+} )
+
+spec:RegisterSetting( "debuff_demoshout_enabled", false, {
+    type = "toggle",
+    name = "Maintain Demoralizing Shout",
+    desc = "When enabled, the Arms and Fury priorities will include Demoralizing Shout.",
+    width = "full",
+} )
+
+spec:RegisterOptions( { package = "Arms" } )
+
+-- The three priorities, generated by tools/make_pack.lua (lua5.1 tools/make_pack.lua prints these strings, in this
+-- order; Forever/spec/warrior_spec.lua checks they match). Pick one with /hekili priority <name>.
+spec:RegisterPack( "Arms", 20261015, [[Hekili:LJv3UTUnm4NLEtwlAHxCpTNTcuxGTbmSTl6nza7o7OyZelezlpj5MMdkYZ(O8pYYoY(KcC2qx7fPnrIFuKFIIKGH(H)z4IeIccF865x)z)5(3gUqTVacxuqI3s2GFjNKH)9Nezs9I7zCsIg1Qskt975HRowbYcio8r)BUZpCrknjbQLcKXHl(vUaEcehwQv4HL)friOCXvhwwWfki5WY1cE2HL)gSLYOFhkXVWisjnUfqHwCQAVhAmc(AkdTnsSIYZLEfciMNTIOcWpkgejt5LQRORdoBv561E2R6vwC4pAagilZtarerKHMckUeukA(gPxcObg1SpKtwXGKz1R6zJYtQq(6(raMrEoQsGzN1GfEUGlHgSLfZueXgq5XqUH9WyNFgnpQscJLFzW3NaOkim6xqaDo8qnOLQAtJt0AjhJ3MAWdiMWyr1)mIrLQR0bebXColHVlxQpTvCP8L(Uq1)U8t2ksuMFSEGNH4sfO1sZxJksjs4RcuWve9sgb9mMuGChafv(Jsq3cv2OwQNa09HmkiFW3bUk2KOsJ2rLPU3hJW2YaPmh)0jrJLhKcconU5uVQeVG5i3VjojW)ytiWF25NFM5IIKqkQ2(VlHsqB8T3uTNVhErPiSg17jGmcnx(qGaFM6POzqKIhDZ1VCcQuFpZsIsLx8Y59O9zgWTlpe7fxCKFRdsya5PVQl)W)kU8TZFfUCTH(TYTB(w3wTrLbprJvCX(irPDOu72i0pAXkwU(hQGfl)MJf(k47WQFU2DxkvW2rZtCqfD5Z3TRQmqZgV8nHGSvECsucD96tHK6ZR3E)0hZLoof30up4oLaBWGi6YV7ugbuZKT150)wxP9mu3qUAGr24tUFPsY0sLVrRUtMlnOAD2URbZn9jbRIMJlfOdOEWHCQubGXRm3g)kgNNOvH24Tv193n3nGHToz1nqp5aHeeBX2sWoBYJD8CEuKnNW4W6EHzEYyI6QUm7wwaKK9671E0uq9X2jhwexQ6jZ9oodlQmCbUQe1HDJT6UpK6MFB9g87pw1dDJ1f(ZTDJI4TQaeQq1mqUySnwqqj1iEhKRVZ17vBlCH1vSMUqU4tNix8)6AaD8rToCre3msWJjMul0TJiKjpYee471khAE5ZJWl90IwWFyebhuhrl6poIO6Yh208RQSIwX3nIInjYT1(jZ7)3xLr7l(ZhXzmvBSDMbvDQuWyjnTR(0JUllQWnEsuTeDQzqXjxp98hpj0BHsqhZjJ5jk9SvwtkzQPkhzpTcBF1ydVrN1HRsNT(0XZUykp7vodKPRtn(ipSs7pyYj1nqevpqnZufCvgO7C6v1XkDu)rI0tZnqMQYXuWn92ufzzMP2uXwJ(Q11y3Q1BRr6qRFKBm6uBs8DFJrdF51IOl4wz)gAQeFdgg4uK60jBAhn4u2N9acRms0mjLQuDs36HAFy55ndb)IQTd)N)]] )
+spec:RegisterPack( "Fury", 20261015, [[Hekili:LJvWUnUnq0VLCXnbBGQv2KTnar5qlqrBpKlUa9MKPfhBrykrvsQ44Ia)TxskjkkzkfBSTf7U5GtSfN5XzECOEdM4W4)iEbgjH4NUz(nFkCE4DXlK7lH4fLO0TOnQVuGYv)9xQ471pCpLHWAVwvrOYFRiE1XaikH04NcV9(W4fzemgQTcePkCyC4zGFyPgWdl)teNty8RpSSKXLa(WY1Cw(HL)kSLqjFN4WYFMIecsARdLAZjY9bQGHZwtOQydLkjScrqjhsz5RqYi1hjfsezSk51K1rxSQA96a3NguvE43BCmsuvGbEcINRcfL5cqkjfBebyq7ysZ6qbAffWZQFAGRxbcPIVEyehZrVKymy2fn(cVuYeqJVvLZKi(gqgqvCd9XX2)CsrIXcBK)HOVhdkiquYFRCOlHhIG2kZI2KOnso2FxQrTbPiknP(NjuIqETUGikLXOy2UcHE3wXeIx7NcM)9Hp6ceVQ4yCGxG0kjOrP5RjLzib8MoYzsK(rwddSHuegqYSKDerMNv1acPBPGquO(0zrZ(hLbCgjvDGXjBHRRuhtmfdUjfhfQdtT5pdkEeYjGikC2LxEHLUryuPz5)QcQanL2Y3T7FWkkJHLzeUqgWHCePq8yexDvlqsYHejl52BE9eauFwrXjzIRE9YEu3mRZTpEOVxD1rzT(GMcONFZe(X)ds47MFgjCDy(Vvs38TULARRIEMKkz89j8k3YO2LvU((QoXjXFhvO4K1mLSvjBNs7Y3Q7uHnDhPa7Hi6EB8UDMxI3SGxGCiH3EJ(8Px3qlfNGjRxFkuC)tL7EyQn58JaVjUQRce3iszUW51go0WlnIB6FRLxVqIOqHSxa0Kk(VAJY17sXgnyNy4B9Pnl6YB7z2j5MHBtR4QGx(Oh7KzCqvIt9h6MGudHo0DH6H7N73HH9k5i)3ZoGla(wvFiQwzks9C)FupB2HXDR7sP9wMTuZCq29yoGW7T8yyF2kQE37mxj7lK9S5bpBLLrNv3O4AQY29MchVh(9wO7WvN(XluOkuXGBdX6Uwe6MMBjf13FY07Dtsg)tTDXQ83r3jwQGzGDPQ2Fbobv7Xx9kmDjEp904fo1jAYsXeF8ezIVIvE6yJAm8rd3osHJTEwB0DJyKTADc6Bm9knUFAeCDyqTz)W5S9F(hvFrQIP5HFCeEyGyM207hXuTgwp260120WgoFeCTckUGFIj5))ADMuzSxzA18CtLbAFgag(UulaoAG946QsJFJ)MhTfDWmqI03T3WHxF7H13kcHhtTJris9KHwJQOYPefDN1IlLzZHVqNuJpb82C64jVmvMDMtWzA9YXhyJJa0G5(u3gts94aTttXNGu3(0t)Z5vA9hOtpKBCzknSPC32HLPYYorWPQTg9YVVHgwJBBq6b13VTNDQnQ(nE7zdV116rxHT09(ZefMDJXCQxJ4omtd4k4rvYm9lkRhJ(HLx2m29Rmlh)p)]] )
+spec:RegisterPack( "Protection", 20261015, [[Hekili:LA12UTnpm4NLD3kwq(tAs62(rDbw3WqxVOyyEa7ozRithlefjdj5m0Hb)SpkBNe5tPTBx0MeE4JKFIKsK5KVtctOwG8WLZU8Q5ZMVIeAFmhiH5u2w6g8ls6o8)FvRSaZYvsNQhfkAIZ31fCH9lsY6(WyYbg5H5lF)CsygpjbQTcmms4NvAypOlJpbBz8pOAnxHcFDUwTNBqHuXf)Fz8NGuqA47HY4qlvYGj4xY4GiPm(wHITTmUihL9net5g0kQm5KfHc6oNdfYexe)GENlgglwFaQ2QkJxH6Vd0koZfbnFlIHZOpkaQlQ)KBZqxYPA8hAKvMIKGwLYfiZqRsFZ0CnWu7wtTb4FwbezYuf2j80GxTUinDQV0Pf5L33ZX3e8Fjhk1itDLE09UA8HiWuvRrRPMSJchcTcdePstJ2WscM)8WgHzpNzv6hJ0fTH)quDhbJbTVnDGfLPsCSzFFR4ywHwds71xoRLxViYfDqxiJQ)vKGBStC9Zbuvf16KJvniHDCWCtWcFhzuHOVNBqJ1yJYXJpeQGeaBQOc(V4YnEPwc0qVD1268hbWLMnnVDe3WFgSjURkwv355jVBcwoRhKvtcr0QbHJ6AQRGE5rJIXYfp1E46YJMQ3x80QXURx97H0PHDuU0C9IHapRA8e7pDtNpvnVA2tLFL3tcXfqUDm(7SChZg3EnKPWpEOA)iiPRfqc52dZ6UTyDprjHmn3IrIscp75oXIbCeyB4ENjlgXeVZaNzl7y2PKOBxWjiQ7BiHEKORsr0wnwq9yo0oSyBy1ZXrEfZy1BNIz0A2p8EL4FDd2lH5w5XCTAc)3iqCLlTqyphb6TuFis0RFBSL4(nSTvouYpg97V()8m3GR87xqofph2B4Je8(GtqE8oKHW7Qrki)ll6N(DUkXb0BhnX6DbIx)F77DQxUev)Ak36fe33nsc29MNw(Ey0RQn64BhoxJ0lUEhBETFx0ZPj0wNQ0cBMB(9oylxWXx518iWlQut(Zp]] )
```

Check: `lua5.1 tools/make_pack.lua | while read -r s; do grep -qF "$s" Forever/Warrior.lua || echo MISSING; done`
Expected: no output.

- [ ] **Step 5: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `108 successes / 0 failures / 0 errors`.

- [ ] **Step 6: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [108 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 65 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output] (modified and new files, new directories included)
lua5.1 tools/make_pack.lua | while read -r s; do grep -qF "$s" Forever/Warrior.lua || echo MISSING; done   # [no output]
```

- [ ] **Step 7: Commit**

```bash
git add tools/make_pack.lua Forever/Warrior.lua Forever/spec/warrior_spec.lua
git commit -m "feat(forever): Arms, Fury and Protection priorities from tools/make_pack.lua; queue prediction, the execute phase and the Classic settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Push** (orchestrator, after this task's review is clean): `git push origin forever-warrior-profile`

### Task 5: CHECKPOINT: the Warrior in game

No code. The orchestrator presents this checkpoint; the user runs the game. Every in-game line prints through `VSCopy(` (ForeverProbe's copy box, `~/src/ForeverProbe/Copy.lua:46`; ForeverProbe must be loaded, and `/vscopy` reopens the box), because chat cannot be copied; each `/run` line is under 255 characters.

- [ ] **Step 1: Point the client at the branch**

```bash
git -C ~/src/hekili checkout --detach forever-warrior-profile
```

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, on the Warrior**

1. `/reload`. Expected: no Lua error, no popup.
2. `/hekili priority`. Expected: the list names `Arms`, `Fury` and `Protection` (built-in, blue) besides the Phase 1 `Warrior` (a profile that used it keeps it selected; it stays as a saved priority, harmless). Then `/hekili priority arms` (or `fury`, `protection` for the talents the character has). Expected: `Priority set to Arms.`
3. Out of combat: `/run VSCopy(Hekili.VirtualState.Snapshot())`, then paste the box. Expected: `resource RAGE type=1 max=100 swing=1 … auraRegen=1`; one `ability <key> qid=<id> cost=<n> read=<n> …` line for each of the 41 abilities (plus any `track_<id>` line from another file's `Track`); 52 `talent <key> spell=<id> rank=<n>/<max>` lines matching the talent pane (report any mismatch).
4. Attack a training dummy for 60 s following the recommendations. Expected: recommendations appear and change (Battle Shout, Rend or the main strike, Sunder Armor, Heroic Strike with spare rage, Overpower after a dodge, Victory Rush after a kill if one happens); no ability the character does not know.
5. Answer the questions below (each is a fact the DB2 cannot settle) and report each answer; where a question says Snapshot, run the line from item 3 and paste the box.

| # | Question (how to see it) | Answer → action (each action its own commit, with the verification block and, where a value changes, the matching `KIT` row in `Forever/spec/warrior_spec.lua`) |
|---|---|---|
| Q1 | **Stance gates.** In each stance the character has, try Thunder Clap, Overpower, Hamstring, Rend, Charge, Revenge, Shield Block, Disarm, Taunt, Intercept, Whirlwind, Pummel, Berserker Rage. Answer once per stance: "<stance>: works: <abilities>; refused: <abilities>". Classic requires Battle for Thunder Clap, Overpower, Charge, Mocking Blow, Retaliation, Sweeping Strikes; Defensive for Revenge, Shield Block, Disarm, Taunt, Shield Wall; Berserker for Intercept, Whirlwind, Pummel, Berserker Rage, Recklessness; not Berserker for Rend; not Defensive for Hamstring. | As Classic → none. An ability that works in more stances → in `Forever/Warrior.lua` replace its `buff = "<stance>"` (or `nobuff`) with a function returning the current stance's aura when that stance is allowed, as `shield_bash`'s `buff` does, or delete the gate if it works in all three. |
| Q2 | **GCD of Pummel, Shield Bash, Shield Wall.** Press each with another ability ready: does the other ability show the GCD sweep? | Sweep → none (the DB2's `gcd = "spell"` stands). No sweep → `gcd = "off"` for that ability and its `KIT` row. |
| Q3 | **Level-cap usability.** At the beta's level cap, which of Mortal Strike, Bloodthirst, Shield Slam and Whirlwind are in the spellbook or talent pane? Is any ability recommended that the client refuses (a red error when pressed)? | Not in the spellbook and never recommended → none (`known` keeps them out). Recommended but refused → add `usable = function () return reactive( <RANKS> ), "<reason>" end` to that ability (the plain usability read). |
| Q4 | **Slam's 18 s.** Cast Slam, then press it again: does it show an 18 s cooldown sweep? | Yes → add `actions.rotation+=/slam,if=!talent.mortal_strike.enabled` (Arms) and `…,if=!talent.bloodthirst.enabled` (Fury) after `spearing_strike` in `tools/make_pack.lua`, bump `DATE` in `tools/make_pack.lua:11` (e.g. 20261016) and the pack version in `Forever/spec/warrior_spec.lua:271` (Hekili re-imports a built-in pack only when its version changes, `Classes.lua:1239`), re-run it and paste the strings. No cooldown → `cooldown = 0` for `slam` and its `KIT` row. |
| Q5 | **Talent costs.** For each known ability whose cost a taken talent changes (Heroic Strike, Cleave, Execute, Sunder Armor, Thunder Clap), compare the Snapshot line's `cost=` with `read=`, using an untalented line (Rend: `cost=10`) to see `read`'s unit. | Equal (in that unit) → none. Different → set that ability's per-rank reduction in its `spend` function to match (the DB2 only has rank 1; this is the real rank's value). |
| Q6 | **Is Overpower's aura visible to the player aura walk?** Aura 1282733 also grants a combo point, so it may be hidden. In Battle Stance, when the dummy dodges and Overpower lights up, run the Snapshot line within 5 s: does `aura player overpower_ready` show `basis=observed` with a recent `O=…@<time>`? Also: in Berserker Stance after a dodge, is Battle Stance recommended? | Visible → none (the aura is the window; the stance swap works). Not visible → fallback (ruling W6a): delete `overpower`'s `usable` line (Overpower then needs only its Battle Stance gate and 5 rage; the client refuses it outside the window), make the `overpower_ready` comment say the window is unseen on Forever, and delete the two `battle_stance,…buff.overpower_ready…` entries from Arms and Fury in `tools/make_pack.lua` (the dodge cannot be seen from another stance), bump `DATE` in `tools/make_pack.lua:11` (e.g. 20261016) and the pack version in `Forever/spec/warrior_spec.lua:271` (Hekili re-imports a built-in pack only when its version changes, `Classes.lua:1239`), re-run it and paste the strings. |
| Q7 | **Bloodrage.** Out of combat at 0 rage, press Bloodrage, wait 10 s, then the Snapshot. Compare `power rage est=` with the client's rage bar (expected about 20: 10 at once, 10 over 10 s). | Matches the bar → none. About 10 below the bar → the aura is not believed up: report the `auras player gen=… up=…` line before and after the press; if `up` does not rise, VirtualState does not see aura 29131, so stop and report (a sources change, outside this plan). Other → change the entry's `value`/`interval` or the handler's `gain` to the observed numbers. |
| Q8 | **Stance swap rage.** With 50 rage, swap stance; how much rage is left? | `10 + 15 x Improved Tactical Mastery rank` (or 0 below level 14) → none. Other → change `kept` in `swap_stance` to the observed rule. |
| Q9 | **Hekili's rage around a queued strike.** In combat with about 40 rage, press Heroic Strike and at once `/run VSCopy(Hekili.State.rage.current)`; then right after the next swing lands, the same line. Compare each number with the rage bar at that moment. | Within a few rage of the bar both times → none. About the strike's cost below the bar before the swing, or one swing's rage above it after → the known simulation risk (ruling W9): record the numbers in the report; if it hides Mortal Strike or Bloodthirst when they come off cooldown, report it for a follow-up plan (Classic's `swingSpend` model), no change here. |

Fix what the user reports (each fix its own commit, then the verification block; a fix that changes a pack also bumps `DATE` and the spec's pack version, as in Q4), then repeat the affected lines. Continue only when the user confirms. Then `git push origin forever-warrior-profile`. When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

**1. Coverage of the rulings and the research inventory**

| Requirement | Where |
|---|---|
| W8/W10 branch and worktree `forever-warrior-profile` from `virtualstate-phase1` at 0403af6b; push after each task's green verification and clean review | Global Constraints; each task's push step; Task 5 |
| W1 full Classic kit in `Forever/Warrior.lua` (spec 1491): every Classic ability (40 less `auto_attack`), every Classic aura (less the three left out above), Forever IDs, ranks as `copy`, DB2 costs/cooldowns/durations with category cooldowns joined; Victory Rush 402927 and Spearing Strike 1310222; no SoD runes | Task 2 (`KIT` pins all 41 abilities against the DB2) |
| W1 all three talent trees (18/17/17) with `Track{ talents }` aliases | Task 3 (52 talents, 120 aliases pinned) |
| W2 Death Wish 12328, Sweeping Strikes 12292 (ability and aura), `improved_rend` 12286/12658/12659 | Task 2 "uses the corrected Classic IDs…"; Task 3 (`TALENTS.improved_rend`) |
| W3 Bloodrage back; aura-gated regen (`aura`, `interval`, `value` from the aura family's belief) with a `resources_spec` case, zero allocation, fold order kept | Task 1 (four cases, one of them the allocation check); Task 2 (the `bloodrage` entry and handler) |
| W4 Arms and Fury ported from Classic with a defined `cooldowns` list; provisional Protection in the War Within shape; `tools/make_pack.lua` generates several packs; strings byte-identical, checked | Task 4 (spec and verification block) |
| W5 stances through the plain form reads, no new source (`GetShapeshiftForm` is plain, facade notes :115-116) | Task 2 (`reset_precast`, spec "reads the stance…") |
| W6/W6a Overpower's window from aura 1282733 (name "Overpower", 5 s, applied to the caster: it fits); fallback rage-only behind the Battle Stance gate, no usability read | Task 2 (`overpower_ready` and its comment), Task 5 Q6 (is the aura visible to the walk; the fallback's edits) |
| W7 one checkpoint: `/reload`, three packs, Snapshot shows the kit, recommendations on a dummy; stance gates, off-GCD Pummel/Shield Bash, level-cap usability, Slam's 18 s as questions with actions | Task 5 (Q1-Q4, plus Q5-Q8 for the other facts the DB2 cannot settle) |
| Research §2b-2c Classic bugs (swapped IDs, unregistered auras, `improved_rend`), §5b Slam rank 1, §5c changed values, §6 open questions 1-10 | Task 2 (bugs, values), Task 3, Task 4 (Q6: the `cooldowns` list; Q8: three packs on one spec), Task 5 (Q1, Q2, Q3, Q7, Q10); Q4 (API support) answered by reading Classes.lua (`RegisterStateExpr`/`RegisterStateFunction`/`RegisterHook`/`RegisterSetting` exist; `RegisterStances` and `RegisterPackSelector` do not exist in this fork, so neither is used) |

**2. Placeholder scan:** no "TBD", "TODO", "implement later" or "similar to Task N"; every code step is a whole file or a `git apply` patch generated from the replay; every command has its expected output from the replay.

**3. Names and types across tasks:** `auraRegen` (adapter → `def.resources[r].auraRegen` → `I.res.auraRegen`, `G.n/slot/aura/value/interval`) is the same in Task 1's code, specs and Snapshot line; Task 2's `reactive`, `knownRank`, `EXECUTE`, `MORTAL_STRIKE` and `state` are the names Task 4's patch uses (Task 4 adds `sort` itself); `improved_tactical_mastery`, `improved_cleave`, `improved_execute`, `improved_sunder_armor`, `improved_thunder_clap`, `improved_taunt`, `improved_shield_block`, `improved_bloodrage`, `improved_charge`, `improved_berserker_rage`, `improved_shield_bash` read by Task 2's functions are all Task 3 keys; the settings, auras, abilities and state expressions Task 4's lists name are checked against the registrations by Task 4's spec.

**4. Review Focus:** the five lines above each have a pinned test in the owning task (Tasks 1, 2, 4); the Heroic Strike/Cleave simulation risk is named there and in the class file and checked by Q9, with no modelling change (ruling W9). Checked and left to the checkpoint rather than a test: the stance bar's index order (the hook maps by spell ID, so the order cannot matter), and Hekili's handling of a `buff` gate function (Classic used the same shape for Revenge and Shield Bash).

**Facts the DB2 does not settle** (each has a Task 5 question): Hekili's simulated rage around a queued strike (Q9), stance requirements (no SpellShapeshift table in the DB2 the CLI exposes), Pummel/Shield Bash/Shield Wall GCD, which spells are usable at the beta's cap, Slam's 18 s, talent ranks 2+ (only rank 1 spells exist), whether aura 1282733 is visible to the aura walk, whether Bloodrage's aura is seen, the rage kept by Tactical Mastery.
