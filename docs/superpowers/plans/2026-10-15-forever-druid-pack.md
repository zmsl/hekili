# Forever Druid Class Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hekili recommends a Forever Druid's Feral (cat) rotation with the Warrior's machinery: the Classic kit re-based on the Forever DB2, VirtualState's belief for the secret resources and auras, `now` handlers for the cast effects the client hides, Clearcasting as one cost modifier read by both layers, and default priorities built by `tools/make_pack.lua` (Feral the default, Guardian and Balance provisional); first the three belief gaps that block it (fractional costs, a resource resting at its maximum, a swing entry gated on an aura), and after one in-game export the live talent tree and the client's pseudo-spec ID.

**Architecture:** Three layer edits in `Virtual/State` (Task 1): `I.BaseCostOf` prices a declared cost between 0 and 1 as that fraction of the slot's believed maximum, so the ladder, the `now` cost step and `I.CostMod` pay the real number; the adapter forwards `rest` as a flag and a regenerating slot rests at its maximum, raising its estimate by any maximum increase (`setMax`); a swing entry's `aura` is forwarded as `swingAura` and `I.SwingValue` pays 0 while that player aura is not believed up (its two other callers, the calibration's `SwingPerSecond` and the ladder pin's step, follow). One named core edit (Task 2): `spec:RegisterCostMod( def )` in `Classes.lua`'s mixin appends to the list the race packs already fill (`ns.RegisterCostMod` in `Races.lua`), which the adapter forwards to the belief and the `spend` wrapper reads in the simulation. `tools/make_pack.lua` takes a class (Task 3; the Warrior's text moves verbatim to `tools/packs/warrior.lua`). `Forever/Classes/Druid.lua` (Task 4) registers one pseudo-spec (`DRUID_SPEC`, a placeholder 1499 until Q1), Energy, Combo Points, Rage (bear swings gated on `bear_form`, Enrage's 2/s, decay 1.25) and Mana, 44 abilities with `now` beside `handler` on the 33 whose cast changes more than its cost, cooldown and GCD, the auras, the DB2's 47 talents plus three placeholders, forms from the plain shapeshift reads, the bleeds' misses from the combat-log rows, the not-behind window, `excess_e` and `shred_ok`. Its priorities (Task 5) come from `tools/packs/druid.lua`. Night Elf and Tauren race packs (Task 6) register Elune's Light and War Stomp. Then the in-game session: Q1 first (Task 7), the export's talent tree and the read pseudo-spec (Task 8), the rest of the checkpoint (Task 9).

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, `lua5.1`/`luac5.1`, the Forever DB2 through `~/.local/share/wow-db2/bin/wowdb` (build 1.60.1.70338).

**Spec:** `docs/superpowers/specs/2026-10-15-forever-druid-pack.md` (binding; §0 layer prerequisites, §11 checkpoint, the controller's rulings at its end: D1 `spec:RegisterCostMod`, D2 Feral ships with Guardian and Balance provisional and Restoration deferred, D3 the 47 nodes now and the export as its own commit, D4 bear 3.46 x 2.5 s, D5 Improved Shifting Power 16 - 4 x rank; the spec ID read in Q1 with the 1491 stop rule; per-class pack text). Read with it: the research brief `docs/research/2026-10-15-forever-druid/research.md` ("R §n"), the event-facade spec `docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md` (§12a `now`, §12b race packs and modifiers) and its plan `docs/superpowers/plans/2026-10-15-virtualstate-event-facade-phase-ab.md` (house style; its Task 13 is the Warrior file's shape with `now` lines). The Warrior plans `docs/superpowers/plans/2026-10-15-forever-warrior-profile.md` and `...-forever-warrior-accuracy.md` (KIT pins, the export's reconciliation).

## How this plan was checked

Every patch below was written and run before the plan was saved, on a scratch clone of the worktree at `b534caca` (`forever-druid`: the event-facade branch's final `e0bd4ed6` plus the spec's docs commit): Tasks 1 to 6 in order, each spec patch applied and run red, then the implementation patch and the whole verification block. Then every patch was extracted again from this markdown and the whole plan replayed from `b534caca` in a fresh clone: per task the spec patch run red, the implementation patch, the verification block, `git add` with exactly the task's commit list, a commit, and an empty `git status` after it; the counts below are that replay's. The base counts at `b534caca`: 219 busted successes, luacheck 0 warnings in 80 files, `tools/check_api_reads.sh` 51 loaded files, the inventory diff empty, LuaLS no problems. Every row of Task 4's KIT table was re-read from the DB2 (`wowdb`, the query in Task 4 Step 0) and matched. The in-game checkpoints (Tasks 7 and 9) and the export-driven Task 8 are the user's and the orchestrator's; Task 8's generator script was run against the Warrior's export (52 nodes, every key mapped, none gone).

## Global Constraints

- Repository `~/src/hekili`. Work only in the worktree `~/src/hekili/.claude/worktrees/forever-druid`, branch `forever-druid`, at `b534caca` when Task 1 starts. Git from WSL only. After each task's green verification and clean review, push the branch (`git push origin forever-druid`); never push to `forever`, `classic` or `virtualstate-event-facade`; never force-push. No task merges.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, naming the model that wrote the commit; an implementer on another model replaces `Claude Opus 5.5` with its own model's name.
- No LICENSE or README changes, in any repository. No changes to `archive/` or `Libs/`.
- Taco Dog Forever is read only; clean-room direction: TDF mechanics may be ported into Hekili with credit in the file header (the Druid file's header names each: `excess_e`, the three priorities, the not-behind window, Enrage's 10 + 2/s, Faerie Fire free in form, the `form` alias), Hekili code never flows into TDF.
- Secret safety (event-facade spec §8): nothing compares, indexes or does arithmetic on a client value without `issecretvalue()` first, and nothing uses `a and b or c` on a possibly-secret value. The Druid file reads the game only through `ns.Facade` (`tools/check_api_reads.sh` enforces it): `GetShapeshiftForm`, `GetShapeshiftFormInfo` and `C_Spell.IsCurrentSpell` are plain in combat for the Warrior (PR10; Q2 and Q13 confirm them on a Druid), `CombatLogGetCurrentEventInfo` answers the layer's own rows, `UI_ERROR_MESSAGE`'s slots reach a subscriber through `Plain`.
- `now` handlers (event-facade spec §12a): a `now` names only the context's verbs and reads (`gain`, `spend`, `applyBuff`, `applyDebuff`, `removeBuff`, `removeDebuff`, `addStack`, `setCooldown`; `talent`, `buff`, `debuff`, the resources by key, `knownRank`, `now`, `combat`, Lua's pure `min`/`max`/`floor`); no Hekili `state`, no game API, no file-local helper that reads either (a helper runs in the file's environment, not the context, so a `now` writes its verbs inline: the forms' removal loop is spelled in each). Rank tables and amounts are file-level constants shared as upvalues by `handler`, `now` and the KIT pins (`BASH_STUN`, `ROOTS_DURATION`, `SHIFTING_POWER_ENERGY`, as the Warrior's `CHARGE_RAGE`). `now` and `handler` are two closures (one shared is refused). A `now` passes a duration wherever the aura's registered duration is a function. Task 4's strict-context specs run every Druid `now` through `Families/Now.lua` and require 0 errors.
- Performance: no allocation in recurring paths (a cast's fold, a swing, the ladder, `excess_e`); allocation only at load or at `SpecChanged`. Each recurring path this plan adds has a 0-byte case (`Virtual/State/spec/helpers/alloc.lua`): Task 1 (swings and casts in and out of the gate), Task 4 (1000 calls of `excess_e`; 1000 rounds of Druid casts with `now`).
- TOC order (`Hekili.toc`): `Forever\Classes\Druid.lua` right after `Forever\Classes\Warrior.lua` (Task 4); `Forever\Races\NightElf.lua` and `Forever\Races\Tauren.lua` right after `Forever\Races\Gnome.lua` (Task 6). Adding files to the TOC needs a client restart, not a `/reload`, before the checkpoint.
- Scope: the spec's §0-§10 and its checkpoint (§11). Not: Restoration's priority, a pack selector, rune-era spells, Tiger's Fury, powershifting, a non-cast `now` trigger (Blood Frenzy, Natural Reaction, the belief's missed-bleed removal), a Clearcasting inference from usability (spec §7 known limit).
- Tools: `BUSTED=~/src/TacoDogForever/.lua/bin/busted`, `LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`, `LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server`, `lua5.1`, `luac5.1`, `WOWDB=~/.local/share/wow-db2/bin/wowdb`. All commands run from the worktree root.
- Every code task ends with the verification block, written out per task with its expected results, then a commit:

  ```bash
  BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
  LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
  $BUSTED                                                     # [N successes / 0 failures / 0 errors]
  $LUACHECK .                                                 # [0 warnings / 0 errors in F files]
  LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: ... in L loaded files]
  LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
    | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
  $LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
  git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
  ```
- Patches are applied with `git apply` from the worktree root, in the order given; each was generated by `git diff` in the replay.
- Style: `Virtual/State` files, specs and `tools/` use the TDF layout (4 spaces, no spaces inside parentheses); edits to Hekili's own files (`Classes.lua`, `Races.lua`, `Constants.lua`) and `Forever/Classes/*.lua`, `Forever/Races/*.lua` keep Hekili's style (spaces inside parentheses).
- The user runs the game. A **CHECKPOINT** task stops execution: the orchestrator (not a subagent) pushes the branch, points the client's checkout at it with `git -C ~/src/hekili checkout --detach forever-druid`, asks the user to run the exact lines given, and waits. Every in-game line is under 255 characters (checked by script) and copies its answer through `VSCopy(` (ForeverProbe's copy box, `/vscopy` reopens it): the user cannot copy chat. ForeverProbe (`~/src/ForeverProbe`) is loaded. When the session ends, `git -C ~/src/hekili checkout forever`.

## Review Focus

1. **The Warrior does not move.** Task 1 changes the resources family under every class: rage rests at 0 (`rest = false`), its maximum read leaves the estimate alone, an entry without `aura` pays every swing; Task 3's make_pack refactor prints the Warrior's three strings byte for byte. Tests: Task 1 `resources_spec` "leaves a slot resting at 0 (rage) unchanged by a maximum read", "pays nothing when the gate names an untracked aura, and as before without a gate"; every `warrior_spec` case in every task; Task 3 Step 4's `cmp`.
2. **A mana cost is the real number in both layers.** 0.55 is 55% of the believed maximum in the ladder, the cost step and under a `pct` modifier (Task 1 `resources_spec` "prices a cost below 1 ...", "pins the ladder at 660 ...", "pays 660 at the cast's cost step, and 330 ..."), and Hekili's simulation already prices it so (`State.lua`).
3. **Bear rage only in Bear Form, in the belief too.** Task 1 "pays only while the aura is believed up ..." and "out of the aura: no swing rate to calibrate against, and a zero-width pin"; Task 4 "runs a Feral and a bear sequence ..." (Bear Form's `now` turns the swing on, Cat Form's turns it off).
4. **Every Druid `now` runs in the strict context.** Task 4 "runs every declared `now` in the context without an error" (33 abilities, `I.nowErrors == 0`), plus the sequence and the allocation cases.
5. **Clearcasting is declared once.** Task 2's mixin case (the class declaration lands in the list both layers read), Task 4 "declares Clearcasting as one cost modifier ..., and no `spend` reads it" (a grep over the file) and "makes a covered cast free while Clearcasting is believed up, which the cast then takes".
6. **The packs name only what exists and nothing secret.** Task 5 "writes priorities that name only registered abilities, auras, talents, settings and lists" (with `VS.AplSecretToken`), and the strings match `make_pack.lua druid`.

## File structure

```
Virtual/State/Families/Casts.lua      Task 1  I.BaseCostOf: a cost in (0, 1) is that fraction of the slot's believed maximum
Virtual/State/Families/Resources.lua  Task 1  R.restMax, setMax (rest at the maximum, estimate raised by an increase);
                                              R.swingAura resolved at the build; I.SwingValue gated on it
Virtual/State/Adapter.lua             Task 1  `rest` as a flag; a swing entry's `aura` forwarded as `swingAura`
Virtual/State/spec/resources_spec.lua Task 1  the mana and swing-gate cases; energy's def takes `rest = true`
Virtual/State/spec/adapter_spec.lua   Task 1  `rest` and `swingAura` forwarded
Virtual/State/spec/helpers/fake_spec.lua  Task 1  rage's def takes `rest = false`
Races.lua, Classes.lua                Task 2  ns.RegisterCostMod (the shared append); spec:RegisterCostMod (named core edit)
Virtual/State/spec/races_spec.lua     Task 2  the mixin's case; Task 6 every race file loaded, Night Elf and Tauren
tools/make_pack.lua                   Task 3  the class argument (default warrior), tools/packs/<class>.lua, the pack's spec
tools/packs/warrior.lua               Task 3  the Warrior's packs, moved verbatim
Forever/spec/warrior_spec.lua         Task 3  the Warrior's packs file and make_pack's default class
Forever/Classes/Druid.lua             Task 4  the class file; Task 5 its three RegisterPack lines; Task 8 talents, DRUID_SPEC
Forever/spec/druid_spec.lua           Task 4  KIT, TALENTS, behaviour, strict-context cases; Task 5 packs; Task 8 pins
Forever/spec/helpers/load_druid.lua   Task 4  the recording loader (load_warrior.lua's shape; an optional real VirtualState)
Constants.lua                         Task 4  the Druid's pseudo-spec row; Task 8 its key
Hekili.toc                            Task 4  Forever\Classes\Druid.lua; Task 6 Forever\Races\NightElf.lua, Tauren.lua
.luacheckrc                           Task 4  druidEnv
tools/packs/druid.lua                 Task 5  Feral, Guardian, Balance; Task 8 its spec
Forever/Races/NightElf.lua, Tauren.lua  Task 6  Elune's Light; War Stomp
```

## Order and checkpoints

Tasks 1 and 2 (the layer and the core edit the class file needs), Task 3 (make_pack per class, before the Druid's packs), Task 4 (the class file), Task 5 (its priorities), Task 6 (race packs), then Task 7, CHECKPOINT A: Q1 alone (the export and the spec ID; no Druid code runs in game yet, since `DRUID_SPEC` is a placeholder). Task 8 applies Q1's answers (the live talent tree, the read pseudo-spec, the regenerated pack strings), gated on Task 7; then Task 9, CHECKPOINT B: Q2-Q16 on the branch Task 8 left. The spec's §11 asks for Q1 first because its answer rewrites §6 before anything else is judged; splitting the session in two is this plan's cut (the Druid's packs cannot load before its spec ID is right).

Deliberately not built (a review should not flag them): Restoration's priority; a pack selector; Furor's energy on entering Cat (Q3), Feral Dedication's regen (Q3), Moonglow, Brutal Impact's cooldown, Berserk's Primal Bite rule; the five-second rule (Q5); a Clearcasting inference; a non-cast `now` trigger (the belief keeps a missed bleed's modelled expiry; the simulation drops it at the next reset); Shred's success closing the not-behind window (TDF's tracker does; the spec asks only for the 5 s window).

---

### Task 1: Layer prerequisites: fractional costs, resting at the maximum, aura-gated swings

Spec §0. Three belief gaps block the Druid; each is a `Virtual/State` edit with its tests, and the Warrior's rage is unchanged by all three.

1. `I.BaseCostOf` (`Virtual/State/Families/Casts.lua`) returns a declared cost `c` with `0 < c < 1` as `c * I.res.max[A.slot[a]]` (allocation-free). The ladder (`I.CostOf` in `Resources.lua`'s Usable and CastSuccess handlers), the `now` cost step (`Now.lua`'s `automatic`) and `I.CostMod` all go through it, so a `pct` modifier scales the multiplied cost, as the simulation's wrapper does.
2. The adapter forwards `rest = ns.ResourceRegenerates( k ) == true` (a flag). `Resources.lua` keeps `R.restMax[r]`, sets `R.rest[r]` to the maximum for such a slot at the build, and changes every maximum through one local `setMax( r, m )` (the plain Max read; `maxOf` at CombatEnd): a resting-at-maximum slot rests at the new maximum and its `est0`/`hi0` rise by an increase, kept out of the regen measurement (`pinDelta`); a decrease only caps them. A slot resting at 0 (rage) is untouched.
3. The adapter forwards a swing entry's `aura` as `d.swingAura`; the build resolves it to the player aura index (0: none; -1: named but not tracked, which pays nothing), as the aura-regen entries do. `I.SwingValue` returns 0 unless that aura's believed expiry is after `I.clock` and its application at or before it. Its two other callers: `I.SwingPerSecond` (the calibration's reference) is then 0, so `calibrate` returns without an update; the ladder pin's swing step is then 0, a zero-width pin.

Test defs that still say `rest = 0`/`rest = 100` move to the flag (`fake_spec.lua`'s rage, `resources_spec`'s energy).

**Files:**
- Modify: `Virtual/State/Families/Casts.lua` (`I.BaseCostOf`), `Virtual/State/Families/Resources.lua` (header comment of `R`, `R.restMax`, `R.swingAura`, `setMax` after `clamp`, the build, `I.SwingValue`, the Max read, CombatEnd), `Virtual/State/Adapter.lua` (`buildDef`'s swing branch and `d`)
- Test: `Virtual/State/spec/resources_spec.lua`, `Virtual/State/spec/adapter_spec.lua`, `Virtual/State/spec/helpers/fake_spec.lua`

**Interfaces:**
- Consumes: `I.res` (`R.max`, `R.slotOf`), `I.ab.slot`, `I.auras.exp0[1]`/`applied[1]`, `I.clock`, `ns.ResourceRegenerates` (Constants.lua).
- Produces: `def.resources[r].rest` (boolean), `def.resources[r].swingAura` (aura key or nil); `I.res.restMax[r]`, `I.res.swingAura[r]`; `I.BaseCostOf(a)` in points.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/spec/adapter_spec.lua b/Virtual/State/spec/adapter_spec.lua
index dca6eab1..f7de6b0f 100644
--- a/Virtual/State/spec/adapter_spec.lua
+++ b/Virtual/State/spec/adapter_spec.lua
@@ -127,6 +127,24 @@ describe("Adapter", function()
         assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
     end)
 
+    it("forwards a regenerating resource's rest as a flag and a swing entry's `aura` as its gate", function()
+        local got
+        local build = I.Build
+        I.Build = function(def, t)
+            got = def
+            return build(def, t)
+        end
+        VS.SpecChanged()
+        assert.are.same({ false, nil }, { got.resources[1].rest, got.resources[1].swingAura })
+        ns.ResourceRegenerates = function(k)
+            return k == "rage"
+        end
+        h.Class.resources.rage.state.regenModel.mainhand.aura = "bear_form"
+        VS.SpecChanged()
+        I.Build = build
+        assert.are.same({ true, "bear_form" }, { got.resources[1].rest, got.resources[1].swingAura })
+    end)
+
     it("leaves the cast history, the real queue and the swing fields to the combat-log rows, asks for a cycle", function()
         ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
         ctl.casting = { 1000, 2500 }
diff --git a/Virtual/State/spec/helpers/fake_spec.lua b/Virtual/State/spec/helpers/fake_spec.lua
index 92deaf6d..47b13347 100644
--- a/Virtual/State/spec/helpers/fake_spec.lua
+++ b/Virtual/State/spec/helpers/fake_spec.lua
@@ -151,7 +151,7 @@ function M.def(hekili)
         abilities = { class.abilities.battle_shout, class.abilities.heroic_strike, class.abilities.rend },
         abilityIds = { { M.SHOUT }, { M.STRIKE }, { M.REND, M.REND_R2 } },
         abilitySlot = { 1, 1, 1 },
-        resources = { { key = "rage", type = M.RAGE, token = "RAGE", max = 100, rest = 0, swing = 1, swingValue = mh.value } },
+        resources = { { key = "rage", type = M.RAGE, token = "RAGE", max = 100, rest = false, swing = 1, swingValue = mh.value } },
         auras = { class.auras.battle_shout, class.auras.rend },
         auraIds = { { M.SHOUT }, { M.REND, M.REND_R2 } },
         talents = { { key = "improved_rend", spell = 12286, max = 3 } },
diff --git a/Virtual/State/spec/resources_spec.lua b/Virtual/State/spec/resources_spec.lua
index 1a15c5fe..5fd415a6 100644
--- a/Virtual/State/spec/resources_spec.lua
+++ b/Virtual/State/spec/resources_spec.lua
@@ -36,7 +36,7 @@ describe("resources", function()
                 abilities = { { key = "finisher", spend = 25 }, { key = "builder", spend = 40 } },
                 abilityIds = { { 1001 }, { 1002 } },
                 abilitySlot = { 1, 1 },
-                resources = { { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = 100, regen = 10 } },
+                resources = { { key = "energy", type = ENERGY, token = "ENERGY", max = 100, rest = true, regen = 10 } },
                 auras = {},
                 auraIds = {},
                 talents = {},
@@ -73,6 +73,10 @@ describe("resources", function()
             assert.are.equal("modelled", rr.basis)
         end)
 
+        it("rests at its maximum of 100, as before rest became a flag", function()
+            assert.are.same({ 100, 100 }, { VS.Power(ENERGY, 1).est, I.res.rest[1] })
+        end)
+
         it("pins an exact plain read and widens a late one by the regen spread", function()
             obs(Obs.Read, 20, 1, 55, I.ReadOf.Resource)
             I.Fold(20, false)
@@ -338,4 +342,159 @@ describe("resources", function()
             assert.are.equal(0, bytes)
         end)
     end)
+    describe("a resource resting at its maximum, and a fractional cost (mana, 0.55 of the maximum)", function()
+        local MANA, FORM, BIG = 0, 1, 2
+        local def
+
+        before_each(function()
+            def = {
+                abilities = { { key = "form", spend = 0.55 }, { key = "big", spend = 1200 } },
+                abilityIds = { { 768 }, { 1001 } },
+                abilitySlot = { 1, 1 },
+                resources = { { key = "mana", type = MANA, token = "MANA", max = 100, rest = true } },
+                auras = { { key = "clearcasting", id = 16870 } },
+                auraIds = { { 16870 } },
+                talents = {},
+                units = { "player", "target" },
+            }
+            boot(def)
+        end)
+
+        local function maxRead(t, v)
+            obs(Obs.Read, t, 1, v, I.ReadOf.Max)
+            I.Fold(t, false)
+        end
+
+        it("seeds at its declared maximum, and a plain maximum read moves the rest and raises the estimate", function()
+            assert.are.same({ 100, 100, 100 }, { VS.Power(MANA, 1).est, I.res.rest[1], I.res.max[1] })
+            maxRead(2, 1200)
+            local m = VS.Power(MANA, 2)
+            assert.are.same({ 1200, 1200, 1200, 1200 }, { m.est, m.hi, I.res.rest[1], I.res.max[1] })
+            assert.are.equal(1100, I.res.pinDelta[1]) -- kept out of the next regen measurement
+        end)
+
+        it("raises the estimate only by an increase; a lower maximum only caps it", function()
+            I.ResourceShift(1, -60, 2, Obs.CastSuccess) -- 40 of 100
+            maxRead(3, 1200)
+            assert.are.equal(1140, VS.Power(MANA, 3).est)
+            maxRead(4, 1000)
+            assert.are.same({ 1000, 1000, 1000 }, { VS.Power(MANA, 4).est, I.res.max[1], I.res.rest[1] })
+        end)
+
+        it("prices a cost below 1 as that fraction of the maximum; a cost of 1 or more is unchanged", function()
+            within(55, I.CostOf(FORM)) -- 0.55 x the declared 100
+            assert.are.equal(1200, I.CostOf(BIG))
+            maxRead(2, 1200)
+            assert.are.same({ 660, 1200 }, { I.CostOf(FORM), I.CostOf(BIG) })
+        end)
+
+        it("pins the ladder at 660 when the form reads usable and below 660 when it reads short", function()
+            maxRead(2, 1200)
+            I.ResourceShift(1, -1000, 2, Obs.CastSuccess) -- 200 believed
+            obs(Obs.Usable, 3, FORM, 1, 0)
+            I.Fold(3, false)
+            local m = VS.Power(MANA, 3)
+            assert.are.same({ 660, 660 }, { m.est, m.lo })
+            obs(Obs.Usable, 4, FORM, 0, 1)
+            I.Fold(4, false)
+            within(660 - I.EPS, VS.Power(MANA, 4).hi)
+        end)
+
+        it("pays 660 at the cast's cost step, and 330 under a cost modifier pct = -0.5", function()
+            maxRead(2, 1200)
+            obs(Obs.CastSuccess, 3, FORM)
+            I.Fold(3, false)
+            assert.are.equal(540, VS.Power(MANA, 3).est)
+            def.resources[1].costMods = { { aura = "clearcasting", pct = -0.5 } }
+            I.Build(def, 4)
+            maxRead(4, 1200)
+            I.AuraModel(1, 1, 4, 19, 1, 4, Obs.CastSuccess, false)
+            I.Settle(5)
+            assert.are.equal(330, I.CostOf(FORM))
+            obs(Obs.CastSuccess, 6, FORM)
+            I.Fold(6, false)
+            assert.are.equal(870, VS.Power(MANA, 6).est)
+        end)
+
+        it("leaves a slot resting at 0 (rage) unchanged by a maximum read", function()
+            boot(fs.def(fs.new(9)))
+            I.ResourceShift(1, 30, 2, Obs.CastSuccess)
+            obs(Obs.Read, 3, 1, 120, I.ReadOf.Max)
+            I.Fold(3, false)
+            assert.are.same({ 30, 0, 120 }, { VS.Power(fs.RAGE, 3).est, I.res.rest[1], I.res.max[1] })
+        end)
+    end)
+
+    describe("a swing entry gated on a player aura (bear rage: swings pay only in Bear Form)", function()
+        local BEAR, REND = 3, 3 -- the aura index; fs.def's ability index of Rend (10 rage)
+
+        local function gated(aura)
+            local def = fs.def(fs.new(9))
+            def.auras[BEAR] = { key = "bear_form", id = 5487 }
+            def.auraIds[BEAR] = { 5487 }
+            def.resources[1].swingAura = aura
+            boot(def)
+            I.Fold(10, false)
+        end
+
+        local function swing(t)
+            obs(Obs.Swing, t, 1, 2.5, 1)
+            I.Fold(t, false)
+            return VS.Power(fs.RAGE, t).est
+        end
+
+        it("pays only while the aura is believed up: never applied, applied (as a `now` writes it), expired", function()
+            gated("bear_form")
+            assert.are.equal(0, swing(11))
+            I.AuraModel(1, BEAR, 12, 30, 1, 12, Obs.CastSuccess, false) -- the shift's applyBuff
+            assert.are.equal(9, swing(13.5))
+            assert.are.equal(18, swing(16))
+            assert.are.equal(18, swing(31)) -- past the believed expiry
+        end)
+
+        it("pays nothing when the gate names an untracked aura, and as before without a gate", function()
+            gated("dire_bear_test")
+            I.AuraModel(1, BEAR, 12, 30, 1, 12, Obs.CastSuccess, false)
+            assert.are.equal(0, swing(13.5))
+            gated(nil)
+            assert.are.equal(9, swing(11))
+        end)
+
+        it("out of the aura: no swing rate to calibrate against, and a zero-width pin on the ladder", function()
+            gated("bear_form")
+            swing(11) -- a speed to divide by
+            I.AuraModel(1, BEAR, 12, 30, 1, 12, Obs.CastSuccess, false)
+            I.Settle(12)
+            within(9 / 2.5, I.SwingPerSecond(1))
+            I.AuraModel(1, BEAR, 0, 0, 0, 13, Obs.CastSuccess, false) -- left Bear Form
+            I.Settle(13)
+            assert.are.equal(0, I.SwingPerSecond(1))
+            obs(Obs.Usable, 14, REND, 0, 1)
+            obs(Obs.Usable, 14, REND, 1, 0) -- the flip pins at Rend's 10 with a step of 0
+            I.Fold(14, false)
+            local r = VS.Power(fs.RAGE, 14)
+            assert.are.same({ 10, 10, 10 }, { r.est, r.lo, r.hi })
+            obs(Obs.Usable, 16, REND, 0, 1)
+            obs(Obs.Usable, 16, REND, 1, 0) -- a second measuring pin: nothing to calibrate against
+            I.Fold(16, false)
+            assert.are.same({ 1, 0 }, { I.res.scale[1], VS.Regen(fs.RAGE, 16).est })
+        end)
+
+        it("allocates nothing over 1000 swings and casts in and out of the aura", function()
+            gated("bear_form")
+            local t = 10
+            local bytes = alloc.bytes(function(i)
+                t = t + 1
+                if i % 2 == 0 then
+                    I.AuraModel(1, BEAR, t, t + 1.5, 1, t, Obs.CastSuccess, false)
+                end
+                obs(Obs.Swing, t + 0.5, 1, 2.5, 1)
+                obs(Obs.CastSuccess, t + 0.6, REND)
+                I.Fold(t + 0.6, false)
+                VS.Power(fs.RAGE, t + 0.7)
+                I.SwingPerSecond(1)
+            end, 1000)
+            assert.are.equal(0, bytes)
+        end)
+    end)
 end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `219 successes / 5 failures / 7 errors` (`adapter_spec`: `rest` is still a number and `swingAura` nil; `resources_spec`: three of the energy describe's cases error on `rest = true` in arithmetic, five of the six mana cases fail or error (no fractional pricing, no rest at the maximum; the rage case passes), and the three swing-gate cases fail).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/Adapter.lua b/Virtual/State/Adapter.lua
index 92dc8448..39ad9620 100644
--- a/Virtual/State/Adapter.lua
+++ b/Virtual/State/Adapter.lua
@@ -117,14 +117,14 @@ local function buildDef()
     local slotByKey = {}
     for _, k in ipairs(sortedKeys(class.resources)) do
         local r = class.resources[k]
-        local swing, value, offValue, auraRegen = 0, nil, nil, nil
+        local swing, value, offValue, auraRegen, swingAura = 0, nil, nil, nil, nil
         local model = r.state and r.state.regenModel
         if model then
             for _, m in pairs(model) do
                 if m.swing == "offhand" then
                     offValue = m.value
                 elseif m.swing and HANDS[m.swing] and swing == 0 then
-                    swing, value = HANDS[m.swing], m.value
+                    swing, value, swingAura = HANDS[m.swing], m.value, m.aura -- `aura`: swings pay only while it is up
                 elseif not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting) then
                     auraRegen = auraRegen or {}
                     -- a player aura's regen { aura, interval, value }, or without `aura` a periodic one credited in
@@ -142,10 +142,11 @@ local function buildDef()
             type = r.type,
             token = k:upper(),
             max = r.state and r.state.meta and r.state.meta.max or 100, -- a number or a state-bound function
-            rest = ns.ResourceRegenerates(k) and 100 or 0,
+            rest = ns.ResourceRegenerates(k) == true, -- a regenerating resource rests at its maximum (Resources.lua)
             swing = swing,
             swingValue = value,
             swingOff = offValue,
+            swingAura = swingAura,
             auraRegen = auraRegen,
             decay = r.state and r.state.meta and r.state.meta.decay, -- out-of-combat loss per second (Resources.lua)
         }
diff --git a/Virtual/State/Families/Casts.lua b/Virtual/State/Families/Casts.lua
index 8d6c1e4a..3de4f4c3 100644
--- a/Virtual/State/Families/Casts.lua
+++ b/Virtual/State/Families/Casts.lua
@@ -247,7 +247,8 @@ function I.CostOf(a)
     return c
 end
 
---- Ability a's declared cost, before any cost modifier (0 when it has none). Allocates nothing.
+--- Ability a's declared cost, before any cost modifier (0 when it has none); a cost between 0 and 1 is that fraction
+--- of its resource's believed maximum, as Hekili's simulation prices it (State.lua's spend). Allocates nothing.
 function I.BaseCostOf(a)
     local obj = I.ab.obj[a]
     local c = obj.baseSpend -- the declared cost before the simulation's modifiers (Races.lua)
@@ -257,7 +258,13 @@ function I.BaseCostOf(a)
     if type(c) == "function" then
         c = c()
     end
-    return type(c) == "number" and c or 0
+    if type(c) ~= "number" then
+        return 0
+    end
+    if c > 0 and c < 1 and A.slot[a] > 0 then
+        c = c * I.res.max[A.slot[a]]
+    end
+    return c
 end
 
 local function ageConf(rec, now)
diff --git a/Virtual/State/Families/Resources.lua b/Virtual/State/Families/Resources.lua
index f2fb401b..af500ea4 100644
--- a/Virtual/State/Families/Resources.lua
+++ b/Virtual/State/Families/Resources.lua
@@ -20,15 +20,19 @@ I.PIN_EXACT = 0.15
 local UNKNOWN, NOT, YES, SHORT = -1, 0, 1, 2
 
 -- By resource slot r. `swing[r]` is the hand that pays it (1 main, 2 off; 0: continuous regen) and `swingOff[r]` the
--- off hand's own value when both hands pay it (0: none). Continuous regen is per second (regE/regL/regH); a swing-paid
--- resource's step is the spec's model value of that hand x scale (spread around it).
+-- off hand's own value when both hands pay it (0: none); `swingAura[r]` the player aura index its swings need (0: none;
+-- -1: named but not tracked, so no swing pays). Continuous regen is per second (regE/regL/regH); a swing-paid
+-- resource's step is the spec's model value of that hand x scale (spread around it). `restMax[r]`: a regenerating
+-- resource rests at its maximum (energy, mana), the others at 0 (rage).
 local R = {
     n = 0,
     type = {},
     token = {},
     max = {},
     rest = {},
+    restMax = {},
     swing = {},
+    swingAura = {},
     swingValue = {},
     swingOff = {},
     est0 = {},
@@ -116,6 +120,22 @@ local function clamp(v, max)
     return v
 end
 
+-- Slot r's maximum becomes m. A slot resting at its maximum rests at the new one, and its estimate and upper bound rise
+-- by an increase (seeded at 100, a plain read of 1200 believes 1200), kept out of the regen measurement; a decrease
+-- never lowers them here. Allocates nothing.
+local function setMax(r, m)
+    local up = m - R.max[r]
+    R.max[r] = m
+    if R.restMax[r] then
+        R.rest[r] = m
+        if up > 0 then
+            R.est0[r] = clamp(R.est0[r] + up, m)
+            R.hi0[r] = clamp(R.hi0[r] + up, m)
+            R.pinDelta[r] = R.pinDelta[r] + up
+        end
+    end
+end
+
 I.OnBuild(function(def, now)
     for k in pairs(R.slotOf) do
         R.slotOf[k] = nil
@@ -131,7 +151,8 @@ I.OnBuild(function(def, now)
         R.slotOf[d.type], R.slotOfToken[d.token] = r, r
         R.maxDef[r], R.maxMods[r], R.maxRead[r] = d.max, d.maxMods, false
         R.max[r] = maxOf(r)
-        R.rest[r] = d.rest or 0
+        R.restMax[r] = d.rest == true
+        R.rest[r] = R.restMax[r] and R.max[r] or 0
         R.swing[r] = d.swing or 0
         R.swingValue[r] = d.swingValue or 0
         R.swingOff[r] = d.swingOff or 0
@@ -150,6 +171,16 @@ I.OnBuild(function(def, now)
         I.Sample(R.regen[r], "default", rate, now, 0)
     end
     I.TRACKED.resource = R.type
+    for r = 1, R.n do
+        local name = list[r].swingAura
+        local j = name == nil and 0 or -1
+        for i = 1, #def.auras do
+            if def.auras[i].key == name then
+                j = i
+            end
+        end
+        R.swingAura[r] = j
+    end
     G.n = 0
     -- shortcut: a build in combat (a /reload, a spec change) times the combat entries from the build, not the pull;
     -- the next pull's CombatStart sets the real start.
@@ -183,8 +214,13 @@ I.OnBuild(function(def, now)
 end)
 
 --- The spec's per-swing value of a swing-paid slot for `hand` (2: the off hand's `swingOff`; else the paying hand's): a
---- number, or the model's state-bound function. Allocates nothing.
+--- number, or the model's state-bound function; 0 while the slot's swing aura is not believed up at the clock (its
+--- application after it, or its expiry at or before it). Allocates nothing.
 function I.SwingValue(r, hand)
+    local j = R.swingAura[r]
+    if j < 0 or j > 0 and (I.auras.exp0[1][j] <= I.clock or I.auras.applied[1][j] > I.clock) then
+        return 0 -- unit 1 is always "player" (Adapter.lua's def.units)
+    end
     local v = R.swingValue[r]
     if hand == 2 and R.swing[r] == 1 then
         v = R.swingOff[r]
@@ -429,7 +465,8 @@ I.On(Obs.Read, function(o, t, lag)
         end
     elseif c == ReadOf.Max then
         if o.b > 0 then
-            R.max[r], R.maxRead[r] = o.b, true -- a plain read wins over the declared maximum from now on
+            setMax(r, o.b)
+            R.maxRead[r] = true -- a plain read wins over the declared maximum from now on
         end
     elseif c == ReadOf.Regen and R.swing[r] == 0 then
         R.decl[r], R.readT[r] = o.b, t
@@ -483,7 +520,7 @@ I.On(Obs.CombatEnd, function()
     for r = 1, R.n do
         R.decay[r] = decayOf(r)
         if not R.maxRead[r] then
-            R.max[r] = maxOf(r)
+            setMax(r, maxOf(r))
         end
         if R.rest[r] < R.lo0[r] then
             R.lo0[r] = R.rest[r]
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `231 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [231 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 80 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 51 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Virtual/State/Adapter.lua Virtual/State/Families/Casts.lua Virtual/State/Families/Resources.lua \
  Virtual/State/spec/adapter_spec.lua Virtual/State/spec/helpers/fake_spec.lua Virtual/State/spec/resources_spec.lua
git commit -m "feat(virtual): fractional costs of the believed maximum, regenerating resources rest at their maximum, swing entries gated on a player aura (Druid spec §0)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-druid`

---

### Task 2: `spec:RegisterCostMod` (named core edit)

Spec §7, ruling D1. Class content declares a cost modifier with the race object's signature: `Races.lua` gains `ns.RegisterCostMod( def )`, the one append into `ns.raceMods.costMods` (the race object's `RegisterCostMod` now calls it while live), and `Classes.lua`'s spec mixin gains `RegisterCostMod = function( self, def ) ns.RegisterCostMod( def ) end`. A class file has already returned for any other class, so its append is the player's; the adapter forwards the list to every resource of the class (scoped by `spells`) and `ns.costMods.Apply`/`Spend` read it in the simulation, unchanged.

The test compiles the mixin's entry from `Classes.lua`'s own text (the file cannot load headless) and checks the declaration reaches the list both layers read, with the simulation's pricing and charge.

**Files:**
- Modify: `Races.lua` (header; `ns.RegisterCostMod`, `Race:RegisterCostMod`), `Classes.lua` (`HekiliSpecMixin`, after `RegisterOptions`)
- Test: `Virtual/State/spec/races_spec.lua`

**Interfaces:**
- Consumes: `ns.raceMods.costMods` (Races.lua), `ns.costMods.Wrap`/`Apply`/`Spend`.
- Produces: `ns.RegisterCostMod( def )`; `spec:RegisterCostMod( def )` with `def = { aura, pct | flat, charges?, spells? }`.

- [ ] **Step 1: Write the failing spec**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/spec/races_spec.lua b/Virtual/State/spec/races_spec.lua
index 6cdfd6fb..4c6a6635 100644
--- a/Virtual/State/spec/races_spec.lua
+++ b/Virtual/State/spec/races_spec.lua
@@ -162,6 +162,23 @@ describe("race packs", function()
         assert.are.equal(15, heroic_strike.spend)
     end)
 
+    it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
+        load("Human")
+        -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
+        local src = assert(io.open("Classes.lua")):read("*a")
+        local entry = assert(src:match("\n(    RegisterCostMod = function%( self, def %).-\n    end,)\n"))
+        local mixin = assert(loadstring("local ns = ...\nreturn {\n" .. entry .. "\n}"))(ns)
+        local def = { aura = "clearcasting", pct = -1, charges = 1, spells = { 5221 } }
+        mixin:RegisterCostMod(def)
+        assert.are.equal(def, ns.raceMods.costMods[1]) -- the list Adapter.lua forwards to the belief
+        local shred = ability("shred", { id = 5221, copy = { 6800 }, spend = 60, spendType = "energy" })
+        local claw = ability("claw", { id = 1082, spend = 45, spendType = "energy" })
+        state.buff.clearcasting = { up = true, count = 1 }
+        assert.are.same({ 0, 45 }, { shred.spend, claw.spend })
+        ns.costMods.Spend(shred.baseSpend, "shred")
+        assert.is_false(state.buff.clearcasting.up)
+    end)
+
     it("ignores a listed spell the class does not register", function()
         load("Gnome")
         local shout = ability("battle_shout", { id = 6673, spend = 10 })
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `231 successes / 1 failure / 0 errors` (`races_spec` "takes a class file's spec:RegisterCostMod ...": `Classes.lua` has no such entry).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Classes.lua b/Classes.lua
index 3bc861eb..f9c3f52e 100644
--- a/Classes.lua
+++ b/Classes.lua
@@ -1074,6 +1074,12 @@ local HekiliSpecMixin = {
         self.options = options
     end,
 
+    -- A class's cost modifier (a proc that makes the next abilities cheaper, e.g. Clearcasting): the race object's
+    -- RegisterCostMod signature, into the list both VirtualState's belief and the simulation read (Races.lua).
+    RegisterCostMod = function( self, def )
+        ns.RegisterCostMod( def )
+    end,
+
     RegisterEvent = function( self, event, func )
         RegisterEvent( event, function( ... )
             if state.spec.id == self.id then func( ... ) end
diff --git a/Races.lua b/Races.lua
index 2a3ac1f7..9f550144 100644
--- a/Races.lua
+++ b/Races.lua
@@ -1,6 +1,7 @@
 -- Races.lua
 -- Race packs (event-facade spec §12b). `Hekili:NewRace( token )` returns a registration object a race file
--- (Forever/Races/<Race>.lua) uses like a spec: RegisterAbility, RegisterAura, RegisterResourceMod, RegisterCostMod.
+-- (Forever/Races/<Race>.lua) uses like a spec: RegisterAbility, RegisterAura, RegisterResourceMod, RegisterCostMod
+-- (a class file declares its own cost modifiers with spec:RegisterCostMod, into the same list).
 -- Registrations count only when the token is the player's race (`state.race_token`, UnitRace's locale-free second
 -- return); otherwise they are accepted and inert, so every race file runs unconditionally and loads headless.
 -- Abilities and auras go to the shared `all` spec (over `all`'s own entry for the same key), and ns.applyRace writes
@@ -68,9 +69,14 @@ end
 
 --- { aura = key, pct = n | flat = n, charges = k | nil, spells = { spell IDs } | nil }: an ability whose spell ID (or
 --- one of its `copy` ranks) is listed (every ability paid from the resource when `spells` is nil) costs less while the
---- aura is up; with charges, each such cast whose declared cost is above 0 takes a stack.
+--- aura is up; with charges, each such cast whose declared cost is above 0 takes a stack. Also a class file's
+--- `spec:RegisterCostMod` (Classes.lua): the class file has returned for any other class, so its append is the player's.
+function ns.RegisterCostMod( def )
+    mods.costMods[ #mods.costMods + 1 ] = def
+end
+
 function Race:RegisterCostMod( def )
-    if self.live then mods.costMods[ #mods.costMods + 1 ] = def end
+    if self.live then ns.RegisterCostMod( def ) end
 end
 
 function Hekili:NewRace( token )
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `232 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [232 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 80 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 51 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Races.lua Classes.lua Virtual/State/spec/races_spec.lua
git commit -m "feat(core): spec:RegisterCostMod, a class file's cost modifier into the race packs' list (Druid spec §7, D1)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-druid`

---

### Task 3: `tools/make_pack.lua` per class (the Warrior's strings unchanged)

Spec §8 (ruling: per-class pack text accepted). `make_pack.lua` takes the class, default `warrior`, and reads `tools/packs/<class>.lua`, which returns `{ date, spec, packs = { { name, desc, simc } } }`; the payload's `spec` comes from that file (1491 for the Warrior). The Warrior's `HEAD` and `PACKS` move to `tools/packs/warrior.lua` verbatim (same strings, no date bump). `loadfile( "tools/make_pack.lua" )( "lists" )` still returns the Warrior's parsed lists (the existing `warrior_spec` call), `( "lists", "druid" )` the Druid's (Task 5), and `lua5.1 tools/make_pack.lua` still prints the Warrior's three strings.

**Files:**
- Create: `tools/packs/warrior.lua`
- Modify: `tools/make_pack.lua` (header; the class argument; the pack's `spec`)
- Test: `Forever/spec/warrior_spec.lua`

**Interfaces:**
- Consumes: nothing new.
- Produces: `lua5.1 tools/make_pack.lua [class]`; `loadfile( "tools/make_pack.lua" )( "lists" [, class] )`; `tools/packs/<class>.lua` returning `{ date, spec, packs }`.

- [ ] **Step 1: Write the failing spec**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/spec/warrior_spec.lua b/Forever/spec/warrior_spec.lua
index 776f753a..ba520f66 100644
--- a/Forever/spec/warrior_spec.lua
+++ b/Forever/spec/warrior_spec.lua
@@ -425,6 +425,19 @@ describe("Forever Warrior", function()
         assert.are.same({ package = "Arms" }, w.options)
     end)
 
+    it("keeps its priorities in tools/packs/warrior.lua, tools/make_pack.lua's default class", function()
+        local def = dofile("tools/packs/warrior.lua")
+        local names = {}
+        for i, p in ipairs(def.packs) do
+            names[i] = p.name
+        end
+        assert.are.same({ 20261016, 1491, { "Arms", "Fury", "Protection" } }, { def.date, def.spec, names })
+        local byName = assert(loadfile("tools/make_pack.lua"))("lists", "warrior")
+        local byDefault = assert(loadfile("tools/make_pack.lua"))("lists")
+        assert.are.same(byDefault, byName)
+        assert.are.equal(def.packs[1].simc, byName[1].simc)
+    end)
+
     it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
         local packs = assert(loadfile("tools/make_pack.lua"))("lists")
         local secretToken = require("Virtual.State.spec.helpers.load").module().VirtualState.AplSecretToken
```

- [ ] **Step 2: Run the specs to verify they fail, and record the Warrior's strings**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `232 successes / 0 failures / 1 error` (`warrior_spec` "keeps its priorities in tools/packs/warrior.lua ...": no such file).

Then, before the implementation: `lua5.1 tools/make_pack.lua > /tmp/warrior_packs_before.txt && wc -l < /tmp/warrior_packs_before.txt` prints `3`.

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/tools/make_pack.lua b/tools/make_pack.lua
index f7c119b5..205ecf5a 100644
--- a/tools/make_pack.lua
+++ b/tools/make_pack.lua
@@ -1,106 +1,16 @@
--- tools/make_pack.lua: prints the Forever Warrior's priorities in the share format RegisterPack takes ("Hekili:" +
--- LibDeflate print encoding of the AceSerializer'd package), one line per pack in PACKS order, built headless with the
--- vendored libraries. Run from the repository root:
---   lua5.1 tools/make_pack.lua
--- Edit a pack's SimC-style text below, run it, and paste each printed string into its spec:RegisterPack( ... [[ ]] )
--- in Forever/Classes/Warrior.lua (Forever/spec/warrior_spec.lua fails until they match). Loaded with the argument
--- "lists" (loadfile(...)("lists")) it returns PACKS with each pack's parsed lists instead, for that spec.
--- The Arms and Fury lists are ported from Hekili's Classic profile (origin/classic:Classic/APLs/WarriorArms.simc,
--- WarriorFury.simc); the Protection list's shape is archive/TheWarWithin/Priorities/WarriorProtection.simc's.
+-- tools/make_pack.lua: prints a Forever class's priorities in the share format RegisterPack takes ("Hekili:" +
+-- LibDeflate print encoding of the AceSerializer'd package), one line per pack in the class's order, built headless
+-- with the vendored libraries. Each class's packs are in tools/packs/<class>.lua ({ date, spec, packs = { { name,
+-- desc, simc } } }). Run from the repository root, the class defaulting to warrior:
+--   lua5.1 tools/make_pack.lua [class]
+-- Edit a pack's SimC-style text there, run this, and paste each printed string into its spec:RegisterPack( ... [[ ]] )
+-- in Forever/Classes/<Class>.lua (the class's spec fails until they match). Loaded with the argument "lists"
+-- (loadfile(...)("lists"[, class])) it returns the class's packs with each pack's parsed lists instead, for the specs.
 
-local DATE = 20261016
-
--- Shared by Arms and Fury (Classic's head of both lists). Forever changes: the execute phase is the plain usability
--- read (`execute_phase`), the target's health being secret; `cooldowns` is defined (Classic called it undefined) and
--- called on bosses and on targets 3 levels above (Classic: target.level>=63 at level 60).
-local HEAD = [[
-actions.precombat=battle_shout,if=!buff.battle_shout.up
-actions=sunder_armor,if=settings.debuff_sunder_enabled&debuff.sunder_armor.stack<settings.debuff_sunder_max_stack&!debuff.expose_armor.up&target.level>=settings.debuff_sunder_min_level
-actions+=/demoralizing_shout,if=settings.debuff_demoshout_enabled&!debuff.demoralizing_shout.up
-actions+=/call_action_list,name=cooldowns,if=boss|target.level>=level+3
-actions+=/run_action_list,name=execute,if=execute_phase
-actions+=/run_action_list,name=rotation
-]]
-
-local PACKS = {
-    {
-        name = "Arms",
-        desc = "Forever Arms Warrior, ported from Hekili's Classic Arms priority.",
-        simc = HEAD .. [[
-actions.cooldowns=sweeping_strikes,if=active_enemies>1
-actions.cooldowns+=/death_wish
-actions.cooldowns+=/recklessness
-actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
-actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
-actions.execute+=/execute
-actions.rotation=victory_rush
-actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
-actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
-actions.rotation+=/overpower
-actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies|(!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.mortal_strike.remains+settings.ww_cd_diff)
-actions.rotation+=/mortal_strike
-actions.rotation+=/spearing_strike
-actions.rotation+=/slam,if=!talent.mortal_strike.enabled
-actions.rotation+=/rend,if=!debuff.rend.up&!talent.mortal_strike.enabled
-actions.rotation+=/hamstring,if=cooldown.mortal_strike.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
-actions.rotation+=/bloodrage,if=rage.current<90
-actions.rotation+=/battle_shout,if=!up
-actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
-]],
-    },
-    {
-        name = "Fury",
-        desc = "Forever Fury Warrior, ported from Hekili's Classic Fury priority.",
-        simc = HEAD .. [[
-actions.cooldowns=death_wish
-actions.cooldowns+=/recklessness
-actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
-actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
-actions.execute+=/execute
-actions.rotation=victory_rush
-actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
-actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
-actions.rotation+=/overpower
-actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies
-actions.rotation+=/bloodthirst
-actions.rotation+=/whirlwind,if=!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.bloodthirst.remains&cooldown.bloodthirst.remains>=settings.ww_cd_diff
-actions.rotation+=/spearing_strike
-actions.rotation+=/slam,if=!talent.bloodthirst.enabled
-actions.rotation+=/rend,if=!debuff.rend.up&!talent.bloodthirst.enabled
-actions.rotation+=/hamstring,if=cooldown.bloodthirst.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
-actions.rotation+=/bloodrage,if=rage.current<90
-actions.rotation+=/battle_shout,if=!up
-actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
-]],
-    },
-    {
-        name = "Protection",
-        desc = "Forever Protection Warrior (provisional): Defensive Stance, Shield Block up, Revenge and Shield Slam, "
-            .. "Sunder Armor stacked to 5, Heroic Strike or Cleave with spare rage.",
-        simc = [[
-actions.precombat=battle_shout,if=!buff.battle_shout.up
-actions.precombat+=/defensive_stance,if=!buff.defensive_stance.up
-actions=shield_bash
-actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
-actions+=/victory_rush
-actions+=/shield_block,use_off_gcd=1,if=!buff.shield_block.up
-actions+=/bloodrage,use_off_gcd=1,if=rage.current<20
-actions+=/battle_shout,if=!buff.battle_shout.up
-actions+=/run_action_list,name=aoe,if=active_enemies>=3
-actions+=/call_action_list,name=generic
-actions.aoe=demoralizing_shout,if=!debuff.demoralizing_shout.up
-actions.aoe+=/revenge
-actions.aoe+=/shield_slam
-actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=40
-actions.aoe+=/sunder_armor
-actions.generic=revenge
-actions.generic+=/shield_slam
-actions.generic+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<3
-actions.generic+=/heroic_strike,use_off_gcd=1,if=rage.current>=50
-actions.generic+=/sunder_armor
-]],
-    },
-}
+local first, second = ...
+local class = first == "lists" and (second or "warrior") or (first or "warrior")
+local def = dofile("tools/packs/" .. class .. ".lua")
+local PACKS, DATE = def.packs, def.date
 
 -- One SimC-style line into its list and entry: actions[.list](=|+=/)action[,name=list][,use_off_gcd=1][,if=criteria].
 local function parse(simc)
@@ -131,7 +41,7 @@ for _, p in ipairs(PACKS) do
     p.lists = parse(p.simc)
 end
 
-if ... == "lists" then
+if first == "lists" then
     return PACKS
 end
 
@@ -147,7 +57,7 @@ for _, p in ipairs(PACKS) do
         name = p.name,
         date = DATE,
         payload = {
-            spec = 1491,
+            spec = def.spec,
             builtIn = false,
             hidden = false,
             date = DATE,
diff --git a/tools/packs/warrior.lua b/tools/packs/warrior.lua
new file mode 100644
index 00000000..9bd0b967
--- /dev/null
+++ b/tools/packs/warrior.lua
@@ -0,0 +1,98 @@
+-- tools/packs/warrior.lua: the Forever Warrior's priorities for tools/make_pack.lua (its default class): the pack
+-- date and pseudo-spec, and each pack's name, description and SimC-style text.
+-- The Arms and Fury lists are ported from Hekili's Classic profile (origin/classic:Classic/APLs/WarriorArms.simc,
+-- WarriorFury.simc); the Protection list's shape is archive/TheWarWithin/Priorities/WarriorProtection.simc's.
+
+-- Shared by Arms and Fury (Classic's head of both lists). Forever changes: the execute phase is the plain usability
+-- read (`execute_phase`), the target's health being secret; `cooldowns` is defined (Classic called it undefined) and
+-- called on bosses and on targets 3 levels above (Classic: target.level>=63 at level 60).
+local HEAD = [[
+actions.precombat=battle_shout,if=!buff.battle_shout.up
+actions=sunder_armor,if=settings.debuff_sunder_enabled&debuff.sunder_armor.stack<settings.debuff_sunder_max_stack&!debuff.expose_armor.up&target.level>=settings.debuff_sunder_min_level
+actions+=/demoralizing_shout,if=settings.debuff_demoshout_enabled&!debuff.demoralizing_shout.up
+actions+=/call_action_list,name=cooldowns,if=boss|target.level>=level+3
+actions+=/run_action_list,name=execute,if=execute_phase
+actions+=/run_action_list,name=rotation
+]]
+
+local PACKS = {
+    {
+        name = "Arms",
+        desc = "Forever Arms Warrior, ported from Hekili's Classic Arms priority.",
+        simc = HEAD .. [[
+actions.cooldowns=sweeping_strikes,if=active_enemies>1
+actions.cooldowns+=/death_wish
+actions.cooldowns+=/recklessness
+actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
+actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
+actions.execute+=/execute
+actions.rotation=victory_rush
+actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
+actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
+actions.rotation+=/overpower
+actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies|(!settings.adaptive_queueing_enabled&cooldown.mortal_strike.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.mortal_strike.remains+settings.ww_cd_diff)
+actions.rotation+=/mortal_strike
+actions.rotation+=/spearing_strike
+actions.rotation+=/slam,if=!talent.mortal_strike.enabled
+actions.rotation+=/rend,if=!debuff.rend.up&!talent.mortal_strike.enabled
+actions.rotation+=/hamstring,if=cooldown.mortal_strike.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
+actions.rotation+=/bloodrage,if=rage.current<90
+actions.rotation+=/battle_shout,if=!up
+actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
+]],
+    },
+    {
+        name = "Fury",
+        desc = "Forever Fury Warrior, ported from Hekili's Classic Fury priority.",
+        simc = HEAD .. [[
+actions.cooldowns=death_wish
+actions.cooldowns+=/recklessness
+actions.execute=heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
+actions.execute+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
+actions.execute+=/execute
+actions.rotation=victory_rush
+actions.rotation+=/heroic_strike,use_off_gcd=1,if=active_enemies=1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_42|settings.adaptive_queueing_enabled&should_hs)|(execute_phase&settings.execute_queueing_enabled))
+actions.rotation+=/cleave,use_off_gcd=1,if=active_enemies>1&((!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=rage.time_to_50|settings.adaptive_queueing_enabled&should_cleave)|(execute_phase&settings.execute_queueing_enabled))
+actions.rotation+=/overpower
+actions.rotation+=/whirlwind,if=active_enemies>=settings.ww_min_enemies
+actions.rotation+=/bloodthirst
+actions.rotation+=/whirlwind,if=!settings.adaptive_queueing_enabled&cooldown.bloodthirst.remains>=settings.ww_cd_diff|settings.adaptive_queueing_enabled&rage.time_to_55<cooldown.bloodthirst.remains&cooldown.bloodthirst.remains>=settings.ww_cd_diff
+actions.rotation+=/spearing_strike
+actions.rotation+=/slam,if=!talent.bloodthirst.enabled
+actions.rotation+=/rend,if=!debuff.rend.up&!talent.bloodthirst.enabled
+actions.rotation+=/hamstring,if=cooldown.bloodthirst.remains>=settings.hamstring_cd_diff&cooldown.whirlwind.remains>=settings.hamstring_cd_diff&rage.current>settings.hamstring_threshold
+actions.rotation+=/bloodrage,if=rage.current<90
+actions.rotation+=/battle_shout,if=!up
+actions.rotation+=/berserker_stance,use_off_gcd=1,if=!up
+]],
+    },
+    {
+        name = "Protection",
+        desc = "Forever Protection Warrior (provisional): Defensive Stance, Shield Block up, Revenge and Shield Slam, "
+            .. "Sunder Armor stacked to 5, Heroic Strike or Cleave with spare rage.",
+        simc = [[
+actions.precombat=battle_shout,if=!buff.battle_shout.up
+actions.precombat+=/defensive_stance,if=!buff.defensive_stance.up
+actions=shield_bash
+actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
+actions+=/victory_rush
+actions+=/shield_block,use_off_gcd=1,if=!buff.shield_block.up
+actions+=/bloodrage,use_off_gcd=1,if=rage.current<20
+actions+=/battle_shout,if=!buff.battle_shout.up
+actions+=/run_action_list,name=aoe,if=active_enemies>=3
+actions+=/call_action_list,name=generic
+actions.aoe=demoralizing_shout,if=!debuff.demoralizing_shout.up
+actions.aoe+=/revenge
+actions.aoe+=/shield_slam
+actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=40
+actions.aoe+=/sunder_armor
+actions.generic=revenge
+actions.generic+=/shield_slam
+actions.generic+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<3
+actions.generic+=/heroic_strike,use_off_gcd=1,if=rage.current>=50
+actions.generic+=/sunder_armor
+]],
+    },
+}
+
+return { date = 20261016, spec = 1491, packs = PACKS }
```

- [ ] **Step 4: Run the specs to verify they pass, and that the Warrior's strings did not move**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `233 successes / 0 failures / 0 errors`.

Run: `lua5.1 tools/make_pack.lua | cmp - /tmp/warrior_packs_before.txt && lua5.1 tools/make_pack.lua warrior | cmp - /tmp/warrior_packs_before.txt && echo identical`
Expected: `identical`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [233 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 81 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 51 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add tools/make_pack.lua tools/packs/warrior.lua Forever/spec/warrior_spec.lua
git commit -m "refactor(tools): make_pack.lua takes the class, its packs in tools/packs/<class>.lua (warrior by default; the Warrior's strings unchanged)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-druid`

---

### Task 4: The Druid class file

Spec §1-§7 and §8's state, §10 cases 1-13. `Forever/Classes/Druid.lua` (Hekili's style; header credits Hekili's Classic Druid and Taco Dog Forever's ported mechanics) returns unless `UnitClassBase( "player" ) == "DRUID"` and registers one specialization with the file constant `DRUID_SPEC = 1499` (an unused ID until Q1; `Constants.lua` gains its row `{ key = "druid", class = "DRUID", ranged = false, forever = "Druid" }`, 1491's shape). What it registers:

- **Resources** in this order: Energy (no regen model, no decay: the plain out-of-combat read seeds the rate), Combo Points, Rage (`mainhand = { swing = "mainhand", aura = "bear_form", last, interval = "mainhand_speed", stop = swings 0 or not in Bear Form, value = 3.46 x the form's unhasted swing }`, `enrage = { aura = "enrage", last, interval = 1, value = 2 }`, meta `decay = function () return 1.25 end`: Hekili's `RegisterResource` setfenv's every meta field, so it must be a function), Mana. No `max` anywhere.
- **Abilities**: the 44 of the KIT table, each `known = knows( RANKS )` (VS.KnownRank), its form gate (spec §3), costs from file-level per-rank tables read through `byRank` (the first rank's while nothing is known) and talent modifiers rank 1's value x the rank floored at 0 (Ferocity, Shredding Attacks as `improved_shred` on Shred and Lacerate, Natural Shapeshifter on the forms and Shifting Power), Improved Shifting Power's cooldown `16 - 4 x rank` (D5), Faerie Fire free with a 6 s cooldown while `buff.feral_form.up`. `now` beside `handler` on the 33 abilities spec §4 gives one; no `now` writes combo points; the forms' `now` remove every form and Maul inline and Bear Form's spends all rage; Bite's spends the energy left; Shifting Power's gains `SHIFTING_POWER_ENERGY`; Wrath's adds two Eclipse stacks only while `talent.eclipse.rank > 0`; Starfire's `handler` removes one.
- **Auras** of spec §5 plus `hurricane` (the channel's aura), the `form`, `feral_form` and `bleed` aliases; **talents**: the DB2's 47 plus `improved_shifting_power`, `natures_splendor`, `eclipse` placeholders.
- **Clearcasting**: `spec:RegisterCostMod{ aura = "clearcasting", pct = -1, charges = 1, spells = <22 rank-1 IDs> }`, the spec §7 list resolved by name to the rank-1 IDs this file registers: Moonfire 8921, Starfire 2912, Insect Swarm 5570, Hurricane 16914, Healing Touch 5185, Regrowth 8936, Rejuvenation 774, Claw 1082, Rake 1822, Shred 5221, Rip 1079, Ferocious Bite 22568, Pounce 9005, Ravage 6785, Swipe 779, Maul 6807, Lacerate 414644, Bash 5211, Feral Charge 1238122, Entangling Roots 339, Thorns 467, Nature's Grasp 16689. The file comment carries the DB2 query (16870's effect masks 15973374 / 100664659 / 1024 / 142606400 against SpellClassSet 7). The query also matches Primal Bite and Demoralizing Roar, which the spec leaves to Q6; the comment says so. No `spend` mentions Clearcasting.
- **State**: `swap_form( form )` (the sim's shift); `reset_precast` removes every form, applies the one `GetShapeshiftForm()` -> `GetShapeshiftFormInfo( form )`'s fourth return names (Dire Bear -> `bear_form`), Maul's queue from `IsCurrentSpell`, and, while `now == query_time`, removes a Rake/Rip/Pounce bleed whose miss row is at or after its application and applies `not_behind` for the rest of 5 s after a listed error; a `COMBAT_LOG_EVENT_UNFILTERED` handler records our `SPELL_MISSED` of a bleed rank, a `UI_ERROR_MESSAGE` handler the time of an error whose type is in `NOT_BEHIND_ERRORS` (empty until Q11; on `ns.DruidNotBehindErrors` so the specs can name one); `shred_ok`; `excess_e` (TDF's, ported: up to three events in preallocated arrays, the credit used only if its GCD starts no refresh later, solved backwards, `-huge` when the spender's GCD would delay an on-time refresh, nothing reserved for an unknown Rip/Rake/Shifting Power); the eleven settings; `RegisterOptions{ package = "Feral" }` (the pack lands in Task 5).

`Hekili.toc` lists the file after the Warrior's; `.luacheckrc` gains `druidEnv`. The loader `Forever/spec/helpers/load_druid.lua` is `load_warrior.lua`'s shape (Energy, ComboPoints, Mana in `Enum.PowerType`; every `RegisterResource` call kept by power type; `RegisterCostMod` recorded; `w.ns`; an optional real VirtualState to bind). `druid_spec.lua` pins the KIT and TALENTS against the DB2 and covers cases 1-13; its last describe loads the class file against a real VirtualState, builds Hekili's class from the file's registrations, and casts through the layer, so every Druid `now` runs bound to `Families/Now.lua`'s context (the Warrior plan had no such case).

**Files:**
- Create: `Forever/Classes/Druid.lua`, `Forever/spec/druid_spec.lua`, `Forever/spec/helpers/load_druid.lua`
- Modify: `Constants.lua` (the row after 1491's), `Hekili.toc` (after `Forever\Classes\Warrior.lua`), `.luacheckrc` (`druidEnv` after the Warrior's entry)

**Interfaces:**
- Consumes: Task 1's `rest` flag, fractional costs and `swingAura`; Task 2's `spec:RegisterCostMod`; `VS.KnownRank`, `VS.SwingBase`; the `now` context (Families/Now.lua); the combat-log rows (Virtual/Events).
- Produces: `DRUID_SPEC`; the Druid's abilities, auras, talents, resources; `swap_form`, `excess_e`, `shred_ok`; `ns.DruidNotBehindErrors`; `load_druid.load( vs )` returning `w` (`w.resources[powerType] = { models, meta }`, `w.order`, `w.costMods`, `w.ns`, the rest as `load_warrior`'s), `load_druid.env( w )`, `load_druid.run( f, e )`.

- [ ] **Step 0: Re-read the KIT from the DB2**

Run (the IDs are the KIT table's, every rank):

```bash
WOWDB=~/.local/share/wow-db2/bin/wowdb
$WOWDB "SELECT n.ID, n.Name_lang, lv.BaseLevel, coalesce(p.ManaCost,0), coalesce(p.PowerCostPct,0), coalesce(p.PowerType,-1),
  max(coalesce(c.RecoveryTime,0),coalesce(c.CategoryRecoveryTime,0)), coalesce(c.StartRecoveryTime,-1), coalesce(ct.Base,0)
  FROM SpellName n LEFT JOIN SpellLevels lv ON lv.SpellID=n.ID LEFT JOIN SpellPower p ON p.SpellID=n.ID AND p.OrderIndex=0
  LEFT JOIN SpellCooldowns c ON c.SpellID=n.ID LEFT JOIN SpellMisc m ON m.SpellID=n.ID LEFT JOIN SpellCastTimes ct ON ct.ID=m.CastingTimeIndex
  WHERE n.ID IN (1082,3029,5201,9849,9850,5221,6800,8992,9829,9830,1822,1823,1824,9904,1289140,1079,9492,9493,9752,9894,9896,1289141,
  22568,22827,22828,22829,31018,1289142,6785,6787,9866,9867,9005,9823,9827,8998,9000,9892,5215,6783,9913,1850,9821,1322605,417141,
  768,5487,9634,24858,783,1066,6807,6808,6809,8972,9745,9880,9881,779,780,769,9754,9908,407995,1238069,1238070,1238073,414644,
  1235826,1235827,99,1735,9490,9747,9898,6795,5211,6798,8983,5209,5229,22842,1238122,16979,770,778,9749,9907,5176,5177,5178,5179,
  5180,6780,8905,9912,2912,8949,8950,8951,9875,9876,25298,8921,8924,8925,8926,8927,8928,8929,9833,9834,9835,5570,24974,24975,24976,
  24977,16914,17401,17402,339,1062,5195,5196,9852,9853,29166,22812,16689,16810,16811,16812,16813,17329,1126,5232,6756,5234,8907,
  9884,9885,21849,21850,467,782,1075,8914,9756,9910,5185,5186,5187,5188,5189,6778,8903,9758,9888,9889,25297,8936,8938,8939,8940,
  8941,9750,9856,9857,9858,774,1058,1430,2090,2091,3627,8910,9839,9840,9841,25299)" | wc -l
```

Expected: `182` (a header and the 181 IDs). Each row agrees with the KIT table in Step 1 (cost column 4 as energy or mana points, or rage x 10; column 5 the percent for the forms, Shifting Power and Innervate; column 7 the cooldown in ms; column 8 the GCD, 1000 = `"totem"`, 0 or -1 = `"off"`; column 9 the cast in ms: Wrath 1500/1700/2000, Starfire 3500, Entangling Roots 1500, Regrowth 2000, Healing Touch 1500-3500); the three Forever variants 1289140-1289142 have no cost or cooldown row. A row that disagrees is corrected in the KIT and the file, never the DB2.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/spec/druid_spec.lua b/Forever/spec/druid_spec.lua
new file mode 100644
index 00000000..0505434b
--- /dev/null
+++ b/Forever/spec/druid_spec.lua
@@ -0,0 +1,754 @@
+-- Forever/spec/druid_spec.lua: the Forever Druid class file's registrations against the Forever DB2 (build
+-- 1.60.1.70338, wowdb), loaded headless through a recording stand-in for Hekili (helpers/load_druid.lua), and its `now`
+-- handlers run by VirtualState itself, in Families/Now.lua's strict context. What Hekili does with the rest is verified
+-- in game (the plan's checkpoint).
+local ld = require("Forever.spec.helpers.load_druid")
+local alloc = require("Virtual.State.spec.helpers.alloc")
+
+-- key = { spell IDs in rank order, cost with every talent at rank 0 (a list: by rank; below 1: a fraction of maximum
+-- mana), spendType, cooldown, gcd }, from the DB2: energy and mana costs as points, rage as the cost / 10; the
+-- cooldown is the larger of RecoveryTime and CategoryRecoveryTime; gcd "totem" for the 1.0 s StartRecoveryTime, "off"
+-- where it is 0 or has no row.
+local KIT = {
+    claw = { { 1082, 3029, 5201, 9849, 9850 }, 45, "energy", 0, "totem" },
+    shred = { { 5221, 6800, 8992, 9829, 9830 }, 60, "energy", 0, "totem" },
+    rake = { { 1822, 1823, 1824, 9904, 1289140 }, 40, "energy", 0, "totem" },
+    rip = { { 1079, 9492, 9493, 9752, 9894, 9896, 1289141 }, 30, "energy", 0, "totem" },
+    ferocious_bite = { { 22568, 22827, 22828, 22829, 31018, 1289142 }, 35, "energy", 0, "totem" },
+    ravage = { { 6785, 6787, 9866, 9867 }, 60, "energy", 0, "totem" },
+    pounce = { { 9005, 9823, 9827 }, 50, "energy", 0, "totem" },
+    cower = { { 8998, 9000, 9892 }, 20, "energy", 10, "totem" },
+    prowl = { { 5215, 6783, 9913 }, 0, nil, 10, "off" },
+    dash = { { 1850, 9821 }, 0, nil, 300, "off" },
+    shifting_power = { { 1322605 }, 0.55, "mana", 16, "totem" },
+    berserk = { { 417141 }, 0, nil, 180, "off" },
+    cat_form = { { 768 }, 0.55, "mana", 0, "spell" },
+    bear_form = { { 5487, 9634 }, 0.55, "mana", 0, "spell" },
+    moonkin_form = { { 24858 }, 0.35, "mana", 0, "spell" },
+    travel_form = { { 783 }, 0.20, "mana", 0, "spell" },
+    aquatic_form = { { 1066 }, 0.20, "mana", 0, "spell" },
+    maul = { { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }, 15, "rage", 0, "off" },
+    swipe_bear = { { 779, 780, 769, 9754, 9908 }, 20, "rage", 0, "spell" },
+    primal_bite = { { 407995, 1238069, 1238070, 1238073 }, 20, "rage", 6, "spell" },
+    lacerate = { { 414644, 1235826, 1235827 }, 15, "rage", 0, "spell" },
+    demoralizing_roar = { { 99, 1735, 9490, 9747, 9898 }, 10, "rage", 0, "spell" },
+    growl = { { 6795 }, 0, nil, 8, "off" },
+    bash = { { 5211, 6798, 8983 }, 10, "rage", 60, "spell" },
+    challenging_roar = { { 5209 }, 15, "rage", 600, "spell" },
+    enrage = { { 5229 }, 0, nil, 60, "off" },
+    frenzied_regeneration = { { 22842 }, 0, nil, 180, "spell" },
+    feral_charge = { { 1238122, 16979 }, 5, "rage", 15, "off" },
+    faerie_fire = { { 770, 778, 9749, 9907 }, { 55, 75, 95, 115 }, "mana", 0, "spell" },
+    wrath = { { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 }, { 10, 20, 40, 50, 70, 80, 100, 120 }, "mana", 0, "spell" },
+    starfire = { { 2912, 8949, 8950, 8951, 9875, 9876, 25298 }, { 95, 135, 180, 230, 275, 315, 340 }, "mana", 0, "spell" },
+    moonfire = {
+        { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },
+        { 25, 50, 75, 105, 150, 190, 235, 280, 325, 375 },
+        "mana",
+        0,
+        "spell",
+    },
+    insect_swarm = { { 5570, 24974, 24975, 24976, 24977 }, { 45, 85, 100, 140, 160 }, "mana", 0, "spell" },
+    hurricane = { { 16914, 17401, 17402 }, { 880, 1180, 1495 }, "mana", 0, "spell" },
+    entangling_roots = { { 339, 1062, 5195, 5196, 9852, 9853 }, { 50, 65, 80, 95, 110, 125 }, "mana", 0, "spell" },
+    innervate = { { 29166 }, 0.05, "mana", 360, "spell" },
+    barkskin = { { 22812 }, 0, nil, 60, "spell" },
+    natures_grasp = { { 16689, 16810, 16811, 16812, 16813, 17329 }, { 50, 65, 80, 95, 110, 125 }, "mana", 60, "spell" },
+    mark_of_the_wild = {
+        { 1126, 5232, 6756, 5234, 8907, 9884, 9885 },
+        { 20, 50, 100, 160, 240, 340, 445 },
+        "mana",
+        0,
+        "spell",
+    },
+    gift_of_the_wild = { { 21849, 21850 }, { 900, 1200 }, "mana", 0, "spell" },
+    thorns = { { 467, 782, 1075, 8914, 9756, 9910 }, { 35, 60, 105, 170, 240, 320 }, "mana", 0, "spell" },
+    healing_touch = {
+        { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },
+        { 25, 55, 110, 190, 280, 350, 425, 520, 630, 755, 840 },
+        "mana",
+        0,
+        "spell",
+    },
+    regrowth = {
+        { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
+        { 70, 125, 170, 210, 250, 305, 370, 445, 525 },
+        "mana",
+        0,
+        "spell",
+    },
+    rejuvenation = {
+        { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
+        { 25, 40, 75, 105, 135, 160, 195, 235, 280, 335, 360 },
+        "mana",
+        0,
+        "spell",
+    },
+}
+
+-- key = { rank 1's spell, max rank }: the DB2's 47 Classic nodes (`wowdb talents DRUID`), then the three placeholders
+-- the live export (checkpoint Q1) replaces.
+local TALENTS = {
+    improved_wrath = { 16814, 5 },
+    natures_grasp = { 16689, 1 },
+    improved_natures_grasp = { 17245, 4 },
+    improved_entangling_roots = { 16918, 3 },
+    improved_moonfire = { 16821, 5 },
+    natural_weapons = { 16902, 5 },
+    natural_shapeshifter = { 16833, 3 },
+    improved_thorns = { 16836, 3 },
+    omen_of_clarity = { 16864, 1 },
+    natures_reach = { 16819, 2 },
+    vengeance = { 16909, 5 },
+    improved_starfire = { 16850, 5 },
+    natures_grace = { 16880, 1 },
+    moonglow = { 16845, 3 },
+    moonfury = { 16896, 5 },
+    moonkin_form = { 24858, 1 },
+    ferocity = { 16934, 5 },
+    feral_aggression = { 16858, 5 },
+    feral_instinct = { 16947, 5 },
+    brutal_impact = { 16940, 2 },
+    thick_hide = { 16929, 5 },
+    feline_swiftness = { 17002, 2 },
+    feral_charge = { 16979, 1 },
+    sharpened_claws = { 16942, 3 },
+    improved_shred = { 16966, 2 },
+    predatory_strikes = { 16972, 3 },
+    blood_frenzy = { 16952, 2 },
+    primal_fury = { 16958, 2 },
+    savage_fury = { 16998, 2 },
+    faerie_fire_feral = { 16857, 1 },
+    heart_of_the_wild = { 17003, 5 },
+    leader_of_the_pack = { 17007, 1 },
+    improved_mark_of_the_wild = { 17050, 5 },
+    furor = { 17056, 5 },
+    improved_healing_touch = { 17069, 5 },
+    natures_focus = { 17063, 5 },
+    improved_enrage = { 17079, 2 },
+    reflection = { 17106, 3 },
+    insect_swarm = { 5570, 1 },
+    subtlety = { 17118, 5 },
+    tranquil_spirit = { 24968, 5 },
+    improved_rejuvenation = { 17111, 3 },
+    natures_swiftness = { 17116, 1 },
+    gift_of_nature = { 17104, 5 },
+    improved_tranquility = { 17123, 2 },
+    improved_regrowth = { 17074, 5 },
+    swiftmend = { 18562, 1 },
+    improved_shifting_power = { 1322670, 2 },
+    natures_splendor = { 1223083, 1 },
+    eclipse = { 408248, 3 },
+}
+
+-- The abilities whose cast changes the now-state beyond its declared cost, cooldown and GCD (spec §4).
+local NOW = {
+    "rake", "rip", "ferocious_bite", "ravage", "pounce", "prowl", "dash", "shifting_power", "berserk", "cat_form",
+    "bear_form", "moonkin_form", "travel_form", "aquatic_form", "lacerate", "demoralizing_roar", "growl", "bash",
+    "challenging_roar", "enrage", "frenzied_regeneration", "feral_charge", "faerie_fire", "wrath", "moonfire",
+    "insect_swarm", "entangling_roots", "innervate", "barkskin", "natures_grasp", "mark_of_the_wild",
+    "gift_of_the_wild", "thorns",
+}
+
+-- Clearcasting's covered abilities (spec §7), by rank 1's ID.
+local COVERED = { 8921, 2912, 5570, 16914, 5185, 8936, 774, 1082, 1822, 5221, 1079, 22568, 9005, 6785, 779, 6807,
+    414644, 5211, 1238122, 339, 467, 16689 }
+
+local function rank(n)
+    return setmetatable({}, {
+        __index = function()
+            return { rank = n, enabled = n > 0 }
+        end,
+    })
+end
+
+local function idsOf(a)
+    local ids = { a.id }
+    for _, v in ipairs(a.copy or {}) do
+        ids[#ids + 1] = v
+    end
+    return ids
+end
+
+local function near(want, got)
+    assert.is_true(math.abs(got - want) < 1e-9, ("want %.4f, got %.4f"):format(want, got))
+end
+
+-- A buff/debuff table whose named keys are up (with the given fields) and the rest down.
+local function auras(up)
+    return setmetatable(up, {
+        __index = function()
+            return { up = false, remains = 0, stack = 0, applied = 0 }
+        end,
+    })
+end
+
+describe("Forever Druid", function()
+    local w
+
+    before_each(function()
+        w = ld.load()
+    end)
+
+    it("registers the kit with the DB2's ranks, costs, cooldowns and GCDs, and no rune or Tiger's Fury spell", function()
+        local e = ld.env(w)
+        local n = 0
+        for key, a in pairs(w.abilities) do
+            n = n + 1
+            local want = KIT[key]
+            assert.is_not_nil(want, "unexpected ability " .. key)
+            assert.are.same(want[1], idsOf(a), key)
+            assert.are.same({ want[3], want[4], want[5] }, { a.spendType, ld.run(a.cooldown, e), a.gcd }, key)
+            assert.are.equal("function", type(a.known), key)
+            if type(want[2]) == "table" then
+                for r, cost in ipairs(want[2]) do -- the cost of each rank, as the spellbook learns it
+                    w.game.known[want[1][r]] = true
+                    assert.are.equal(cost, ld.run(a.spend, e), key .. " rank " .. r)
+                end
+            else
+                assert.are.equal(want[2], ld.run(a.spend, e) or 0, key)
+            end
+        end
+        assert.are.equal(44, n)
+        local stale = { tigers_fury = true }
+        for _, id in ipairs({ 5217, 417045, 407988, 417157, 414684, 439748, 408124, 408247, 408120, 410176, 411128, 414924 }) do
+            stale[id] = true
+        end
+        for key, a in pairs(w.abilities) do
+            assert.is_nil(stale[key], key)
+            for _, id in ipairs(idsOf(a)) do
+                assert.is_nil(stale[id], key .. " " .. id)
+            end
+        end
+        assert.is_true(w.abilities.maul.onNextSwing)
+        assert.are.same({ true, 10 }, { w.abilities.hurricane.channeled, w.abilities.hurricane.cast })
+        -- Wrath's cast at its top rank (the cost loop above learned every rank)
+        assert.are.same({ 2, 3.5, 2 }, { ld.run(w.abilities.wrath.cast, e), w.abilities.starfire.cast, w.abilities.regrowth.cast })
+    end)
+
+    it("models the talent-modified costs from rank 1's value x the rank, floored at 0", function()
+        local e = ld.env(w)
+        e.talent = rank(2)
+        local function at(key)
+            return ld.run(w.abilities[key].spend, e)
+        end
+        -- Ferocity -1 a rank; Shredding Attacks -6 a rank (Shred; Lacerate by its DB2 text, checkpoint Q12)
+        assert.are.same({ 43, 38, 13, 18, 18, 48, 3 },
+            { at("claw"), at("rake"), at("maul"), at("swipe_bear"), at("primal_bite"), at("shred"), at("lacerate") })
+        -- Natural Shapeshifter -10% a rank on the forms and Shifting Power
+        for key, cost in pairs({ cat_form = 0.44, bear_form = 0.44, shifting_power = 0.44, moonkin_form = 0.28,
+            travel_form = 0.16, aquatic_form = 0.16 }) do
+            near(cost, at(key))
+        end
+        assert.are.same({ 8, 1.3 }, { ld.run(w.abilities.shifting_power.cooldown, e), ld.run(w.abilities.wrath.cast, e) })
+        e.talent = rank(5)
+        assert.are.same({ 40, 0, 30 }, { at("claw"), at("lacerate"), at("shred") })
+    end)
+
+    it("gates every ability on the form it needs, Ravage and Pounce on Prowl, Faerie Fire free only in Cat or Bear", function()
+        local a = w.abilities
+        local gates = {
+            cat_form = { "claw", "shred", "rake", "rip", "ferocious_bite", "cower", "prowl", "dash", "shifting_power" },
+            prowl = { "ravage", "pounce" },
+            bear_form = { "maul", "swipe_bear", "primal_bite", "lacerate", "demoralizing_roar", "growl", "bash",
+                "challenging_roar", "enrage", "frenzied_regeneration", "feral_charge" },
+        }
+        for gate, keys in pairs(gates) do
+            for _, k in ipairs(keys) do
+                assert.are.same({ gate, nil }, { a[k].buff, a[k].nobuff }, k)
+            end
+        end
+        for _, k in ipairs({ "wrath", "starfire", "moonfire", "insect_swarm", "hurricane", "entangling_roots",
+            "healing_touch", "regrowth", "rejuvenation", "mark_of_the_wild", "gift_of_the_wild", "thorns", "innervate",
+            "natures_grasp" }) do
+            assert.are.same({ nil, "feral_form" }, { a[k].buff, a[k].nobuff }, k)
+        end
+        for _, k in ipairs({ "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }) do
+            assert.are.same({ nil, k }, { a[k].buff, a[k].nobuff }, k)
+        end
+        for _, k in ipairs({ "faerie_fire", "barkskin" }) do
+            assert.are.same({ nil, nil }, { a[k].buff, a[k].nobuff }, k)
+        end
+        local e = ld.env(w)
+        assert.are.same({ "cat_form", 55, 0 }, { ld.run(a.berserk.buff, e), ld.run(a.faerie_fire.spend, e),
+            ld.run(a.faerie_fire.cooldown, e) })
+        e.buff = auras({ bear_form = { up = true }, feral_form = { up = true } })
+        assert.are.same({ "bear_form", 0, 6 }, { ld.run(a.berserk.buff, e), ld.run(a.faerie_fire.spend, e),
+            ld.run(a.faerie_fire.cooldown, e) })
+    end)
+
+    it("registers the DB2's 47 talent nodes and the three placeholders, and no rank aliases", function()
+        local n, registered = 0, 0
+        for key, t in pairs(TALENTS) do
+            n = n + 1
+            assert.are.same({ 0, t[1], t[2] }, w.talents[key], key)
+        end
+        for _ in pairs(w.talents) do
+            registered = registered + 1
+        end
+        assert.are.same({ 50, 50 }, { n, registered })
+    end)
+
+    it("registers every aura a handler, `now`, state function, gate, resource entry or alias names", function()
+        local e = ld.env(w)
+        e.talent = rank(1) -- Wrath's Eclipse
+        for _, a in pairs(w.abilities) do
+            ld.run(a.handler, e)
+            ld.run(a.now, e)
+            ld.run(a.start, e)
+            for _, gate in ipairs({ ld.run(a.buff, e), a.nobuff, a.aura }) do
+                table.insert(e.applied, gate)
+            end
+        end
+        e.swap_form("bear_form")
+        for _, m in pairs(w.resources[1].models) do
+            table.insert(e.applied, m.aura)
+        end
+        for _, alias in ipairs({ w.auras.form, w.auras.feral_form, w.auras.bleed }) do
+            for _, k in ipairs(alias.alias) do
+                table.insert(e.applied, k)
+            end
+        end
+        table.insert(e.applied, w.costMods[1].aura)
+        for _, list in ipairs({ e.applied, e.removed, e.added }) do
+            for _, k in ipairs(list) do
+                k = type(k) == "table" and k[1] or k
+                assert.is_not_nil(w.auras[k], "unregistered aura " .. tostring(k))
+            end
+        end
+    end)
+
+    describe("the now-state (spec §4, event-facade spec §12a)", function()
+        it("declares `now` beside `handler` exactly on the abilities whose cast changes more than its cost", function()
+            local has = {}
+            for _, k in ipairs(NOW) do
+                has[k] = true
+            end
+            for key, a in pairs(w.abilities) do
+                assert.are.equal(has[key] == true, type(a.now) == "function", key)
+                if a.now then
+                    assert.are_not.equal(a.now, a.handler, key) -- two closures: one shared would be refused
+                end
+            end
+        end)
+
+        it("writes the debuffs, Lacerate's stack to 5, Pounce's stun with Brutal Impact and Bash's at rank 0", function()
+            local e = ld.env(w)
+            for _, k in ipairs({ "rake", "rip", "demoralizing_roar", "faerie_fire" }) do
+                ld.run(w.abilities[k].now, e)
+            end
+            assert.are.same({ "rake", "rip", "demoralizing_roar", "faerie_fire" }, e.applied)
+            e = ld.env(w)
+            e.debuff = auras({ lacerate = { up = true, stack = 4 } })
+            ld.run(w.abilities.lacerate.now, e)
+            assert.are.same({ 15, 5 }, { e.durations.lacerate, e.stacks.lacerate })
+            e.debuff = auras({ lacerate = { up = true, stack = 5 } })
+            ld.run(w.abilities.lacerate.now, e)
+            assert.are.equal(5, e.stacks.lacerate)
+            e = ld.env(w)
+            e.talent = rank(2)
+            ld.run(w.abilities.pounce.now, e)
+            assert.are.same({ { "pounce", "pounce_bleed" }, { "prowl" }, 3 }, { e.applied, e.removed, e.durations.pounce })
+            e = ld.env(w)
+            ld.run(w.abilities.bash.now, e) -- the spellbook answers 0: rank 1's 2 s
+            assert.are.equal(2, e.durations.bash)
+            w.game.known[5211], w.game.known[6798] = true, true
+            e.talent = rank(1)
+            ld.run(w.abilities.bash.now, e)
+            assert.are.equal(3.5, e.durations.bash)
+            w.game.known[8921], w.game.known[8924] = true, true
+            ld.run(w.abilities.moonfire.now, e)
+            ld.run(w.abilities.insect_swarm.now, e)
+            assert.are.same({ 15, 14 }, { e.durations.moonfire, e.durations.insect_swarm }) -- Nature's Splendor
+        end)
+
+        it("gains Shifting Power's 40 energy and Enrage's 10 rage, and Bite spends the energy left", function()
+            local e = ld.env(w)
+            ld.run(w.abilities.shifting_power.now, e)
+            ld.run(w.abilities.enrage.now, e)
+            e.energy.current = 25
+            ld.run(w.abilities.ferocious_bite.now, e)
+            assert.are.same({ { 40, "energy" }, { 10, "rage" } }, e.gained)
+            assert.are.same({ { 25, "energy" } }, e.spent)
+            assert.are.same({ "enrage" }, e.applied)
+        end)
+
+        it("adds Wrath's Eclipse charges only with the talent, and Starfire's handler spends one", function()
+            local e = ld.env(w)
+            ld.run(w.abilities.wrath.now, e)
+            assert.are.same({}, e.added)
+            e.talent = rank(1)
+            ld.run(w.abilities.wrath.now, e)
+            ld.run(w.abilities.wrath.handler, e)
+            assert.are.same({ { "eclipse", 2 }, { "eclipse", 2 } }, e.added)
+            ld.run(w.abilities.starfire.handler, e)
+            assert.are.same({}, e.removed)
+            e.buff = auras({ eclipse = { up = true, stack = 2 } })
+            ld.run(w.abilities.starfire.handler, e)
+            assert.are.same({ "eclipse" }, e.removed)
+        end)
+
+        it("writes no combo points from any `now`", function()
+            local e = ld.env(w)
+            e.talent = rank(1)
+            for _, k in ipairs(NOW) do
+                ld.run(w.abilities[k].now, e)
+            end
+            for _, list in ipairs({ e.gained, e.spent }) do
+                for _, v in ipairs(list) do
+                    assert.are_not.equal("combo_points", v[2])
+                end
+            end
+        end)
+    end)
+
+    it("shifts: Bear Form spends all rage and removes the other forms and Maul; Cat Form writes no energy", function()
+        local e = ld.env(w)
+        e.rage.current = 40
+        ld.run(w.abilities.bear_form.now, e)
+        assert.are.same({ { 40, "rage" } }, e.spent)
+        assert.are.same({ "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form", "maul" }, e.removed)
+        assert.are.same({ "bear_form" }, e.applied)
+        e = ld.env(w)
+        ld.run(w.abilities.cat_form.now, e)
+        e.swap_form("cat_form")
+        assert.are.same({ {}, {}, { "cat_form", "cat_form" } }, { e.spent, e.gained, e.applied })
+        e = ld.env(w)
+        e.rage.current = 30
+        e.swap_form("bear_form")
+        assert.are.same({ { 30, "rage" } }, e.spent)
+    end)
+
+    it("reads the form at reset from the shapeshift read (Dire Bear is bear_form), and Maul's queue", function()
+        local e = ld.env(w)
+        w.game.form, w.game.formSpell[2] = 2, 9634
+        w.game.known[6807], w.game.current[6807] = true, true
+        e.now, e.query_time = 10, 10
+        ld.run(w.hooks.reset_precast, e)
+        assert.are.same({ "bear_form", "maul" }, e.applied)
+        assert.are.same({ "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }, e.removed)
+    end)
+
+    it("gains rage per white swing in Bear Form only, at the form's 2.5 s x 3.46; Enrage 2/s; decay 1.25", function()
+        local models = w.resources[1].models
+        w.state.buff.bear_form = { up = false }
+        w.state.swings.mainhand, w.state.mainhand_speed = 5, 2.5
+        assert.are.same({ "mainhand", "bear_form", "mainhand_speed" }, { models.mainhand.swing, models.mainhand.aura,
+            models.mainhand.interval })
+        assert.is_true(models.mainhand.stop()) -- out of Bear Form
+        w.state.buff.bear_form.up = true
+        assert.is_false(models.mainhand.stop())
+        near(2.5 * 3.46, models.mainhand.value()) -- the believed swing speed before a plain base read
+        w.game.base = { 2.5, 0 }
+        w.state.mainhand_speed = 2.0 -- hasted: the rage follows the unhasted speed
+        near(8.65, models.mainhand.value())
+        assert.are.same({ "enrage", 1, 2 }, { models.enrage.aura, models.enrage.interval, models.enrage.value })
+        w.state.buff.enrage, w.state.query_time = { applied = 10 }, 13.4
+        assert.are.equal(13, models.enrage.last())
+        assert.are.equal(1.25, w.resources[1].meta.decay())
+    end)
+
+    it("declares energy with no regen model, combo points and mana with no maximum, in Classic's order", function()
+        assert.are.same({ 3, 4, 1, 0 }, w.order)
+        for _, pt in ipairs({ 3, 4, 0 }) do
+            assert.are.same({ nil, nil }, { w.resources[pt].models, w.resources[pt].meta }, pt)
+        end
+        assert.is_nil(w.resources[1].meta.max)
+    end)
+
+    it("declares Clearcasting as one cost modifier over the covered rank-1 IDs, and no `spend` reads it", function()
+        assert.are.equal(1, #w.costMods)
+        local m = w.costMods[1]
+        assert.are.same({ "clearcasting", -1, 1, COVERED }, { m.aura, m.pct, m.charges, m.spells })
+        local first = {}
+        for _, a in pairs(w.abilities) do
+            first[a.id] = true
+        end
+        for _, id in ipairs(m.spells) do
+            assert.is_true(first[id], tostring(id)) -- each is the rank-1 ID of a registered ability
+        end
+        local src = assert(io.open("Forever/Classes/Druid.lua")):read("*a")
+        assert.is_nil(src:find("buff%.clearcasting")) -- the modifier, not each `spend`, prices it
+    end)
+
+    describe("the combat log and the not-behind window", function()
+        local ME, MOB = "Player-1", "Creature-1"
+
+        local function row(t, sub, spellID)
+            w.game.now = t
+            w.game.row = { t, sub, false, ME, "", 0, 0, MOB, "", 0, 0, spellID, "", 1, "DODGE" }
+            w.events.COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED")
+        end
+
+        local function reset(t, debuffs)
+            local e = ld.env(w)
+            e.now, e.query_time = t, t
+            e.debuff = auras(debuffs or {})
+            ld.run(w.hooks.reset_precast, e)
+            return e
+        end
+
+        local function removed(e, key)
+            for _, k in ipairs(e.removed) do
+                if k == key then
+                    return true
+                end
+            end
+            return false
+        end
+
+        before_each(function()
+            w.state.GUID = ME
+        end)
+
+        it("removes a missed Rake or Rip at the next reset, not a hit or a newer application", function()
+            row(10, "SPELL_MISSED", 1823) -- Rake rank 2, dodged
+            assert.is_true(removed(reset(11, { rake = { up = true, applied = 9.9 } }), "rake"))
+            assert.is_false(removed(reset(13, { rake = { up = true, applied = 12 } }), "rake")) -- reapplied since
+            row(20, "SPELL_CAST_SUCCESS", 1079) -- a Rip that landed
+            assert.is_false(removed(reset(21, { rip = { up = true, applied = 20 } }), "rip"))
+            row(30, "SPELL_MISSED", 9827) -- Pounce: its bleed
+            assert.is_true(removed(reset(31, { pounce_bleed = { up = true, applied = 29.9 } }), "pounce_bleed"))
+        end)
+
+        it("opens not_behind for the rest of 5 s after a listed error, never for another", function()
+            w.ns.DruidNotBehindErrors[51] = true -- the type checkpoint Q11 records
+            w.game.now = 20
+            w.events.UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 50, "Another error.")
+            assert.is_nil(reset(21).durations.not_behind)
+            w.events.UI_ERROR_MESSAGE("UI_ERROR_MESSAGE", 51, "You must be behind your target.")
+            assert.are.equal(3, reset(22).durations.not_behind)
+            assert.is_nil(reset(25.5).durations.not_behind)
+        end)
+    end)
+
+    describe("excess_e (ported from Taco Dog Forever)", function()
+        local e, excess
+
+        before_each(function()
+            e = ld.env(w)
+            e.energy = { current = 100, max = 100, regen = 10 }
+            e.combo_points.current = 5
+            e.debuff = auras({ rip = { remains = 5 }, rake = { remains = 6 } })
+            e.cooldown = setmetatable({ shifting_power = { remains = 30 } }, getmetatable(e.cooldown))
+            e.action = setmetatable({ rip = { cost = 30 }, rake = { cost = 40 } }, getmetatable(e.action))
+            for _, id in ipairs({ 1079, 1822, 1322605 }) do
+                w.game.known[id] = true
+            end
+            excess = setfenv(w.exprs.excess_e, e)
+        end)
+
+        it("allows Shred when the energy covers it, Rip and Rake in time", function()
+            -- Rake's 40 at 6 s, Rip's 30 at 5 s less 10 s of regen: 10 held back
+            assert.are.equal(90, excess())
+        end)
+
+        it("holds Shred when Rip at 5 combo points is due within the regen", function()
+            e.energy.current = 40
+            e.debuff = auras({ rip = { remains = 2 }, rake = { remains = 9 } })
+            assert.are.equal(30, excess()) -- below Shred's 60
+            e.combo_points.current = 4 -- Rip not due at settings.rip_cp: nothing for it
+            assert.are.equal(40, excess())
+        end)
+
+        it("credits Shifting Power's 40 once it is off cooldown", function()
+            e.energy.current = 40
+            e.debuff = auras({ rip = { remains = 2 }, rake = { remains = 9 } })
+            e.cooldown.shifting_power.remains = 0
+            assert.are.equal(40, excess())
+        end)
+
+        it("is -math.huge when the spender's GCD would delay a refresh that could start on time", function()
+            e.debuff = auras({ rip = { remains = 0.5 }, rake = { remains = 6 } })
+            assert.are.equal(-math.huge, excess())
+            e.energy.current = 20 -- Rip could not start on time anyway
+            assert.is_true(excess() > -math.huge)
+        end)
+
+        it("reserves nothing for a Rip the druid does not know", function()
+            w.game.known[1079] = nil
+            e.energy.current = 40
+            e.debuff = auras({ rip = { remains = 2 }, rake = { remains = 9 } })
+            assert.are.equal(40, excess())
+        end)
+
+        it("allocates nothing over 1000 calls", function()
+            assert.are.equal(0, alloc.bytes(function()
+                excess()
+            end, 1000))
+        end)
+    end)
+
+    it("reads shred_ok from the behind setting, the group and the not-behind window", function()
+        local e = ld.env(w)
+        local ok = function()
+            return ld.run(w.exprs.shred_ok, e)
+        end
+        assert.is_false(ok())
+        e.group = true
+        assert.is_true(ok())
+        e.buff = auras({ not_behind = { up = true } })
+        assert.is_false(ok())
+        e.settings.behind = true
+        assert.is_true(ok())
+    end)
+
+    it("declares its pseudo-spec once, as a placeholder until checkpoint Q1, and the settings the packs read", function()
+        assert.are.equal(1499, w.specID)
+        for key, default in pairs({ rip_cp = 5, bite_finisher = false, behind = false, buffs = true, dump_rage = 60,
+            use_enrage = false, moonkin = true, trash_dots = true, starfire_filler = false, hurricane_targets = 4,
+            innervate = true }) do
+            assert.are.equal(default, w.settings[key].default, key)
+        end
+        assert.are.same({ package = "Feral" }, w.options)
+    end)
+end)
+
+-- The Druid's `now` handlers as VirtualState runs them: bound to Families/Now.lua's context (Hekili's verbs onto the
+-- belief, nothing else reachable), on our own casts' success.
+describe("Forever Druid in VirtualState's now context", function()
+    local load = require("Virtual.State.spec.helpers.load")
+    local fake = require("Virtual.State.spec.helpers.fake_api")
+    local fs = require("Virtual.State.spec.helpers.fake_spec")
+    local ns, VS, I, api, ctl, w, h, saved
+
+    local function cast(id, t)
+        ctl.now = t
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
+        ctl.Tick(t + 0.01)
+        VS.Drain(t + 0.02)
+    end
+
+    local function power(pt, t)
+        return VS.Power(pt, t).est
+    end
+
+    before_each(function()
+        api, ctl = fake.new()
+        ctl.now = 1
+        saved = {}
+        for _, k in ipairs({ "GetTime", "UnitGUID", "CreateFrame", "issecretvalue", "debugprofilestop" }) do
+            saved[k] = rawget(_G, k) or false
+        end
+        _G.GetTime, _G.UnitGUID, _G.CreateFrame, _G.issecretvalue = api.GetTime, api.UnitGUID, api.CreateFrame, api.issecretvalue
+        _G.debugprofilestop = function()
+            return 0
+        end
+        ns = load.module()
+        VS, I = ns.VirtualState, ns.VirtualStateInternal
+        w = ld.load(VS) -- the class file's knownRank and swing base read this VirtualState
+        w.state.mainhand_speed = 2.5
+        -- Hekili's class from the file's registrations: values evaluated at talent rank 0, functions kept in `funcs`
+        local e = ld.env(w)
+        local class = { primaryResource = "energy", abilities = {}, auras = {}, talents = w.talents }
+        class.resources = {
+            energy = { type = 3, state = {} },
+            combo_points = { type = 4, state = {} },
+            rage = { type = 1, state = { regenModel = w.resources[1].models, meta = w.resources[1].meta } },
+            mana = { type = 0, state = {} },
+        }
+        for key, a in pairs(w.abilities) do
+            class.abilities[key] = {
+                key = key,
+                id = a.id,
+                copy = a.copy,
+                spend = a.spend ~= nil and ld.run(a.spend, e) or nil,
+                spendType = a.spendType,
+                cooldown = ld.run(a.cooldown, e),
+                gcd = a.gcd,
+                onNextSwing = a.onNextSwing,
+                cast = 0,
+                charges = 1,
+                recharge = 0,
+                funcs = { now = a.now, handler = a.handler },
+            }
+        end
+        for key, a in pairs(w.auras) do
+            class.auras[key] = { key = key, id = a.id, copy = a.copy, duration = a.duration, max_stack = a.max_stack }
+        end
+        h = fs.new(9)
+        h.Class = class
+        fs.clock = api.GetTime
+        ns.spendResources = fs.spend
+        ns.ResourceRegenerates = function(k)
+            return k == "energy" or k == "mana"
+        end
+        ns.raceMods = { maxMods = {}, costMods = w.costMods } -- Clearcasting, as spec:RegisterCostMod appends it
+        load.adapter(ns, h)
+        VS.Start(api)
+        VS.SpecChanged()
+        ctl.Tick(1)
+        I.ObsLog.Clear(I.log)
+    end)
+
+    after_each(function()
+        for k, v in pairs(saved) do
+            _G[k] = v or nil
+        end
+        fs.clock = nil
+    end)
+
+    it("runs a Feral and a bear sequence: costs, energy, forms, debuffs and bear rage, with no `now` error", function()
+        I.Sources.Direct(VS.Obs.CombatStart, 1.5) -- in combat: no rage decay
+        cast(768, 2) -- Cat Form: 55 mana (0.55 of the declared 100)
+        assert.is_not_nil(VS.Aura("player", 768, 2.1))
+        near(45, power(0, 2.1))
+        cast(5221, 3) -- Shred: 60 of 100 energy
+        cast(1322605, 4) -- Shifting Power: +40
+        assert.are.equal(80, power(3, 4.1))
+        cast(1822, 5) -- Rake: 40, and its 9 s debuff
+        assert.are.equal(14, VS.Aura("target", 1822, 5.1).est)
+        cast(22568, 6) -- Ferocious Bite: 35, then the 5 left
+        assert.are.equal(0, power(3, 6.1))
+        cast(5487, 7) -- Bear Form
+        assert.are.same({ true, false }, { VS.Aura("player", 5487, 7.1) ~= nil, VS.Aura("player", 768, 7.1) ~= nil })
+        I.Sources.Direct(VS.Obs.Swing, 8, 1, 2.5, 1)
+        VS.Drain(8)
+        near(8.65, power(1, 8))
+        cast(5229, 9) -- Enrage: 10 now, 2 a second
+        I.Settle(12)
+        near(8.65 + 10 + 6, power(1, 12))
+        cast(414644, 13) -- Lacerate twice: 2 stacks
+        cast(414644, 14)
+        assert.are.equal(2, select(2, VS.Aura("target", 414644, 14.1)))
+        cast(768, 15) -- back to Cat Form: the swing pays nothing
+        I.Sources.Direct(VS.Obs.Swing, 16, 1, 2.5, 1)
+        VS.Drain(16)
+        assert.are.equal(power(1, 15.1), power(1, 16))
+        assert.are.same({ 0, 9 }, { I.nowErrors, I.nowRuns })
+    end)
+
+    it("runs every declared `now` in the context without an error", function()
+        local runs = 0
+        local t = 2
+        for _, a in pairs(w.abilities) do
+            if a.now then
+                t = t + 1
+                cast(a.id, t)
+                runs = runs + 1
+            end
+        end
+        assert.are.same({ 0, runs }, { I.nowErrors, I.nowRuns }, tostring(I.nowError))
+    end)
+
+    it("makes a covered cast free while Clearcasting is believed up, which the cast then takes", function()
+        cast(5221, 2) -- 40 energy left
+        I.AuraModel(1, I.auras.bySpell[16870], 3, 18, 1, 3, VS.Obs.CastSuccess, false)
+        cast(5221, 4) -- free
+        assert.are.same({ 40, nil }, { power(3, 4.1), VS.Aura("player", 16870, 4.1) })
+        cast(5221, 5)
+        assert.are.equal(0, power(3, 5.1))
+    end)
+
+    it("allocates nothing over 1000 casts with `now` handlers", function()
+        function h:ForceUpdate() end -- the fake records each call; Hekili's own only sets fields
+        local t = 2
+        local bytes = alloc.bytes(function()
+            t = t + 1
+            cast(1322605, t)
+            cast(1822, t + 0.3)
+            cast(414644, t + 0.6)
+        end, 1000)
+        assert.are.equal(0, bytes)
+    end)
+end)
diff --git a/Forever/spec/helpers/load_druid.lua b/Forever/spec/helpers/load_druid.lua
new file mode 100644
index 00000000..ad8034c2
--- /dev/null
+++ b/Forever/spec/helpers/load_druid.lua
@@ -0,0 +1,200 @@
+-- Forever/spec/helpers/load_druid.lua
+-- Loads Forever/Classes/Druid.lua headless against a recording stand-in for Hekili (load_warrior.lua's shape): each
+-- spec:RegisterX call is kept by method name, and the plain game reads the file captures at load answer from `game`
+-- (known spells, queued spells, the shapeshift form, the time, the combat-log row, VirtualState's per-hand base weapon
+-- speeds). `env()` is a stand-in `state` for running the file's handlers, state functions, expressions and hooks
+-- (Hekili runs them with setfenv( f, state )).
+local M = {}
+
+--- Loads the class file. `vs` (optional) is the VirtualState the file binds as ns.VirtualState (a real one, for the
+--- strict-context specs); by default a fake whose KnownRank answers from `game.known`. Returns `w`: `w.abilities`,
+--- `w.auras` (merged by key), `w.talents`, `w.resources[powerType]` ({ models, meta }), `w.costMods` (the
+--- RegisterCostMod declarations), `w.hooks[name]`, `w.events[event]`, `w.funcs[name]`, `w.exprs[name]`,
+--- `w.settings[key]` ({ default, option }), `w.packs` (in order: { name, version, string }), `w.options`, `w.specID`,
+--- `w.ns`, `w.state` (Hekili.State's stand-in) and `w.game`.
+function M.load(vs)
+    local reg = {}
+    local spec = setmetatable({}, {
+        __index = function(_, method)
+            return function(_, ...)
+                reg[method] = reg[method] or {}
+                table.insert(reg[method], { ... })
+            end
+        end,
+    })
+    local game = {
+        known = {},
+        current = {},
+        form = 0,
+        formSpell = {},
+        base = { 0, 0 }, -- VS.SwingBase: each hand's unhasted speed (0: no plain read yet)
+        now = 0, -- GetTime()
+        row = {}, -- the combat-log row CombatLogGetCurrentEventInfo answers
+    }
+    local w = { game = game, abilities = {}, auras = {}, resources = {}, hooks = {}, funcs = {}, exprs = {} }
+    w.state = { buff = {}, swings = {} }
+    local hekili = { State = w.state }
+    function hekili:NewSpecialization(id)
+        w.specID = id
+        return spec
+    end
+    local fakes = {
+        Hekili = hekili,
+        UnitClassBase = function()
+            return "DRUID"
+        end,
+        C_Spell = {
+            IsCurrentSpell = function(id)
+                return game.current[id] == true
+            end,
+        },
+        GetShapeshiftForm = function()
+            return game.form
+        end,
+        GetShapeshiftFormInfo = function(i)
+            return 0, true, true, game.formSpell[i]
+        end,
+        GetTime = function()
+            return game.now
+        end,
+        CombatLogGetCurrentEventInfo = function()
+            return unpack(game.row, 1, 15)
+        end,
+        Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4 } },
+    }
+    local saved = {}
+    for k, v in pairs(fakes) do
+        saved[k] = rawget(_G, k) or false
+        _G[k] = v
+    end
+    local ns = {
+        Facade = fakes, -- the class file reads the game through ns.Facade (event-facade spec §1.2)
+        VirtualState = vs or {
+            KnownRank = function(ids) -- VirtualState's spellbook: the plain known reads (`game.known`)
+                for i = #ids, 1, -1 do
+                    if game.known[ids[i]] then
+                        return i
+                    end
+                end
+                return 0
+            end,
+            SwingBase = function(hand)
+                return game.base[hand]
+            end,
+        },
+    }
+    w.ns = ns
+    local ok, err = pcall(assert(loadfile("Forever/Classes/Druid.lua")), "Hekili", ns)
+    for k, v in pairs(saved) do
+        _G[k] = v or nil
+    end
+    assert(ok, err)
+    for _, call in ipairs(reg.RegisterAbilities or {}) do
+        for k, v in pairs(call[1]) do
+            w.abilities[k] = v
+        end
+    end
+    for _, call in ipairs(reg.RegisterAuras or {}) do
+        for k, v in pairs(call[1]) do
+            w.auras[k] = v
+        end
+    end
+    w.talents = reg.RegisterTalents and reg.RegisterTalents[1][1]
+    w.order = {}
+    for i, call in ipairs(reg.RegisterResource or {}) do
+        w.order[i] = call[1]
+        w.resources[call[1]] = { models = call[2], meta = call[4] }
+    end
+    w.costMods = {}
+    for i, call in ipairs(reg.RegisterCostMod or {}) do
+        w.costMods[i] = call[1]
+    end
+    w.events = {}
+    for _, call in ipairs(reg.RegisterEvent or {}) do
+        w.events[call[1]] = call[2]
+    end
+    for _, call in ipairs(reg.RegisterHook or {}) do
+        w.hooks[call[1]] = call[2]
+    end
+    for _, call in ipairs(reg.RegisterStateFunction or {}) do
+        w.funcs[call[1]] = call[2]
+    end
+    for _, call in ipairs(reg.RegisterStateExpr or {}) do
+        w.exprs[call[1]] = call[2]
+    end
+    w.settings = {}
+    for _, call in ipairs(reg.RegisterSetting or {}) do
+        w.settings[call[1]] = { default = call[2], option = call[3] }
+    end
+    w.packs = reg.RegisterPack or {}
+    w.options = reg.RegisterOptions and reg.RegisterOptions[1][1]
+    return w
+end
+
+local function default(value)
+    return setmetatable({}, {
+        __index = function()
+            return value
+        end,
+    })
+end
+
+--- A stand-in `state` that records applyBuff/applyDebuff (into `applied`, durations and stacks by key), removeBuff,
+--- removeDebuff, removeStack, addStack, spend and gain, with every talent at rank 0, every aura down and every cooldown
+--- ready, the settings at their defaults. The class file's state functions are bound to it.
+function M.env(w)
+    local e = { applied = {}, durations = {}, stacks = {}, removed = {}, spent = {}, gained = {}, added = {} }
+    e.talent = default({ rank = 0, enabled = false })
+    e.buff = default({ up = false, remains = 0, stack = 0, applied = 0 })
+    e.debuff = e.buff
+    e.cooldown = default({ remains = 0 })
+    e.action = default({ cost = 0 })
+    e.settings = {}
+    for k, s in pairs(w.settings) do
+        e.settings[k] = s.default
+    end
+    e.energy = { current = 100, max = 100, regen = 10 }
+    e.rage = { current = 50 }
+    e.mana = { current = 1000 }
+    e.combo_points = { current = 0 }
+    e.combat, e.active_enemies, e.group = 0, 1, false
+    e.pairs, e.ipairs = pairs, ipairs -- Hekili's state has them (State.lua)
+    function e.applyBuff(key, duration)
+        table.insert(e.applied, key)
+        e.durations[key] = duration
+    end
+    function e.applyDebuff(_, key, duration, stacks)
+        table.insert(e.applied, key)
+        e.durations[key], e.stacks[key] = duration, stacks
+    end
+    function e.removeBuff(key)
+        table.insert(e.removed, key)
+    end
+    e.removeStack = e.removeBuff
+    function e.removeDebuff(_, key)
+        table.insert(e.removed, key)
+    end
+    function e.addStack(key, _, n)
+        table.insert(e.added, { key, n })
+    end
+    function e.spend(n, resource)
+        table.insert(e.spent, { n, resource })
+    end
+    function e.gain(n, resource)
+        table.insert(e.gained, { n, resource })
+    end
+    for k, f in pairs(w.funcs) do
+        e[k] = setfenv(f, e)
+    end
+    return e
+end
+
+--- Runs `f` (a field function of the class file) in `e`; a non-function is returned as is.
+function M.run(f, e, ...)
+    if type(f) ~= "function" then
+        return f
+    end
+    return setfenv(f, e)(...)
+end
+
+return M
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `233 successes / 0 failures / 29 errors` (every `druid_spec` case errors in its `before_each`: no `Forever/Classes/Druid.lua`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/.luacheckrc b/.luacheckrc
index 4128d946..b5d08de1 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -110,4 +110,12 @@ for _, k in ipairs(stateEnv) do
     warriorEnv[#warriorEnv + 1] = k
 end
 files["Forever/Classes/Warrior.lua"] = { globals = warriorEnv }
+-- The Druid's further `state` names.
+local druidEnv = {
+    "rage", "energy", "mana", "combo_points", "cooldown", "combat", "group", "swap_form", "addStack", "removeStack",
+}
+for _, k in ipairs(stateEnv) do
+    druidEnv[#druidEnv + 1] = k
+end
+files["Forever/Classes/Druid.lua"] = { globals = druidEnv }
 files["Forever/Races/"] = { globals = stateEnv }
diff --git a/Constants.lua b/Constants.lua
index cf63c83d..933afef8 100644
--- a/Constants.lua
+++ b/Constants.lua
@@ -250,6 +250,12 @@ ns.Specializations = {
         ranged = false,
         forever = "Warrior" -- the spec name; also selects the Forever path in Hekili:NewSpecialization
     },
+    [1499] = { -- Forever Druid pseudo-spec (Forever/Classes/Druid.lua's DRUID_SPEC): a placeholder until the client's
+        key = "druid", -- ID is read in game (the Druid plan's checkpoint Q1)
+        class = "DRUID",
+        ranged = false,
+        forever = "Druid"
+    },
 }
 
 ns.getSpecializationKey = function ( id )
diff --git a/Forever/Classes/Druid.lua b/Forever/Classes/Druid.lua
new file mode 100644
index 00000000..a2b7f06a
--- /dev/null
+++ b/Forever/Classes/Druid.lua
@@ -0,0 +1,1707 @@
+-- Forever/Classes/Druid.lua
+-- The Forever Druid (one pseudo-spec, DRUID_SPEC below): the Classic Druid kit with Forever's spell data (ranks,
+-- costs, cooldowns, cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb; energy and mana costs
+-- are DB2 points, rage the DB2 cost / 10), Forever's Shifting Power, Berserk, Primal Bite and Lacerate, bear rage per
+-- white swing in Bear Form only, Enrage's rage over time, Clearcasting as a cost modifier, forms from the plain
+-- shapeshift reads, the bleeds' misses from the combat log, and the default priorities (Feral; Guardian and Balance
+-- provisional). Design: docs/superpowers/specs/2026-10-15-forever-druid-pack.md.
+-- Talents: the DB2's 47 Classic nodes plus three placeholders the live export replaces (checkpoint Q1). Only rank 1 of
+-- each talent is in the Forever DB2, so a modifier is rank 1's value x the rank (Classic's convention), floored at 0;
+-- no cooldown or duration modifier is modelled but Improved Shifting Power's (spec D5).
+-- Credits: Hekili (registration API and pack format); the abilities, auras, handlers and `swap_form` are ported from
+-- Hekili's Classic profile (origin/classic:Classic/Druid.lua). Ported from Taco Dog Forever
+-- (src/TacoDogForever_Druid/): the `excess_e` energy reservation (Expressions.lua, itself after Zachary Samsel's
+-- `excess_e` in Hekili's Wrath Feral module, origin/wrath_release:Wrath/Druid.lua L413-566), the Feral, bear and
+-- Balance priorities (APLs/feral.simc, bear.simc, balance.simc, after Nerdegghead and the guides they cite), the
+-- not-behind window (Feral.lua), Enrage's 10 + 2/s and Faerie Fire free in form (Bear.lua), and the `form` alias over
+-- the forms (Expressions.lua, ns.RegisterForms).
+
+local addon, ns = ...
+local Facade = ns.Facade
+local C_Spell, UnitClassBase = Facade.C_Spell, Facade.UnitClassBase
+local GetShapeshiftForm, GetShapeshiftFormInfo = Facade.GetShapeshiftForm, Facade.GetShapeshiftFormInfo
+local CombatLogGetCurrentEventInfo, GetTime = Facade.CombatLogGetCurrentEventInfo, Facade.GetTime
+local Hekili = _G[ addon ]
+
+if UnitClassBase( "player" ) ~= "DRUID" then return end
+
+local state = Hekili.State
+local VS = ns.VirtualState
+local IsCurrentSpell = C_Spell.IsCurrentSpell
+local floor, max, min, huge = math.floor, math.max, math.min, math.huge
+
+-- The pseudo-spec the client reports for a Druid (Constants.lua's row). A placeholder until checkpoint Q1 reads it.
+local DRUID_SPEC = 1499
+
+local spec = Hekili:NewSpecialization( DRUID_SPEC, false, 132115 ) -- ability_druid_catform
+if not spec then return end
+
+-- Rank IDs, lowest first (the DB2's), and the per-rank values the DB2 gives.
+local CLAW = { 1082, 3029, 5201, 9849, 9850 }
+local SHRED = { 5221, 6800, 8992, 9829, 9830 }
+local RAKE = { 1822, 1823, 1824, 9904, 1289140 } -- 1289140: Forever's variant
+local RIP = { 1079, 9492, 9493, 9752, 9894, 9896, 1289141 }
+local FEROCIOUS_BITE = { 22568, 22827, 22828, 22829, 31018, 1289142 }
+local RAVAGE = { 6785, 6787, 9866, 9867 }
+local POUNCE = { 9005, 9823, 9827 }
+local POUNCE_BLEED = { 9007, 9824, 9826 }
+local COWER = { 8998, 9000, 9892 }
+local PROWL = { 5215, 6783, 9913 }
+local DASH = { 1850, 9821 }
+local SHIFTING_POWER = { 1322605 }
+local BERSERK = { 417141 }
+local CAT_FORM = { 768 }
+local BEAR_FORM = { 5487, 9634 } -- Dire Bear Form is Bear Form's rank 2
+local MOONKIN_FORM = { 24858 }
+local TRAVEL_FORM = { 783 }
+local AQUATIC_FORM = { 1066 }
+local MAUL = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }
+local SWIPE = { 779, 780, 769, 9754, 9908 }
+local PRIMAL_BITE = { 407995, 1238069, 1238070, 1238073 } -- Mangle, renamed
+local LACERATE = { 414644, 1235826, 1235827 }
+local DEMORALIZING_ROAR = { 99, 1735, 9490, 9747, 9898 }
+local GROWL = { 6795 }
+local BASH = { 5211, 6798, 8983 }
+local BASH_STUN = { 2, 3, 4 }
+local CHALLENGING_ROAR = { 5209 }
+local ENRAGE = { 5229 }
+local FRENZIED_REGENERATION = { 22842 }
+local FERAL_CHARGE = { 1238122, 16979 } -- the trainer's spell, then the old talent's
+local FAERIE_FIRE = { 770, 778, 9749, 9907 }
+local FAERIE_FIRE_COST = { 55, 75, 95, 115 }
+local WRATH = { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 }
+local WRATH_COST = { 10, 20, 40, 50, 70, 80, 100, 120 }
+local WRATH_CAST = { 1.5, 1.7, 2, 2, 2, 2, 2, 2 }
+local STARFIRE = { 2912, 8949, 8950, 8951, 9875, 9876, 25298 }
+local STARFIRE_COST = { 95, 135, 180, 230, 275, 315, 340 }
+local MOONFIRE = { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 }
+local MOONFIRE_COST = { 25, 50, 75, 105, 150, 190, 235, 280, 325, 375 }
+local INSECT_SWARM = { 5570, 24974, 24975, 24976, 24977 }
+local INSECT_SWARM_COST = { 45, 85, 100, 140, 160 }
+local HURRICANE = { 16914, 17401, 17402 }
+local HURRICANE_COST = { 880, 1180, 1495 }
+local ROOTS = { 339, 1062, 5195, 5196, 9852, 9853 }
+local ROOTS_COST = { 50, 65, 80, 95, 110, 125 }
+local ROOTS_DURATION = { 12, 15, 18, 21, 24, 27 }
+local INNERVATE = { 29166 }
+local BARKSKIN = { 22812 }
+local NATURES_GRASP = { 16689, 16810, 16811, 16812, 16813, 17329 }
+local NATURES_GRASP_COST = { 50, 65, 80, 95, 110, 125 }
+local MARK_OF_THE_WILD = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }
+local MARK_OF_THE_WILD_COST = { 20, 50, 100, 160, 240, 340, 445 }
+local GIFT_OF_THE_WILD = { 21849, 21850 }
+local GIFT_OF_THE_WILD_COST = { 900, 1200 }
+local THORNS = { 467, 782, 1075, 8914, 9756, 9910 }
+local THORNS_COST = { 35, 60, 105, 170, 240, 320 }
+local HEALING_TOUCH = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 }
+local HEALING_TOUCH_COST = { 25, 55, 110, 190, 280, 350, 425, 520, 630, 755, 840 }
+local HEALING_TOUCH_CAST = { 1.5, 2, 2.5, 3, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5 }
+local REGROWTH = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }
+local REGROWTH_COST = { 70, 125, 170, 210, 250, 305, 370, 445, 525 }
+local REJUVENATION = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }
+local REJUVENATION_COST = { 25, 40, 75, 105, 135, 160, 195, 235, 280, 335, 360 }
+
+-- The forms, in `buff.form`'s member order (one is up at a time), and each form's spell -> its aura.
+local FORMS = { "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }
+local FORM_OF_SPELL = { [ 768 ] = "cat_form", [ 5487 ] = "bear_form", [ 9634 ] = "bear_form",
+    [ 24858 ] = "moonkin_form", [ 783 ] = "travel_form", [ 1066 ] = "aquatic_form" }
+
+-- Shifting Power's energy (DB2 1322605 effect 30, base 40) and bear rage per white swing (spec §2.3, D4): the
+-- Warrior's measured one-hand main-hand rate x the form's unhasted 2.5 s swing, 8.65 a swing, until checkpoint Q8.
+local SHIFTING_POWER_ENERGY = 40
+local BEAR_RAGE_RATE = 3.46
+
+local function rest( ids )
+    local out = {}
+    for i = 2, #ids do out[ #out + 1 ] = ids[ i ] end
+    return out
+end
+
+-- The highest known rank of a rank list, from VirtualState's spellbook: the same answer in the sim's `state`
+-- environment and in a `now` handler's (event-facade spec §12a).
+local function knownRank( ids )
+    return VS.KnownRank( ids )
+end
+
+local function knows( ids )
+    return function () return knownRank( ids ) > 0 end
+end
+
+-- A per-rank value at the highest known rank, else the first rank's (nothing known yet).
+local function byRank( values, ids )
+    return values[ knownRank( ids ) ] or values[ 1 ]
+end
+
+-- The form's unhasted swing (2.5 s in Bear Form): VirtualState's plain base read, else the believed swing speed.
+local function bearSwing()
+    local speed = VS.SwingBase( 1 )
+    if speed <= 0 then speed = state.mainhand_speed end -- no plain base read yet
+    return speed
+end
+
+spec:RegisterResource( Enum.PowerType.Energy )
+spec:RegisterResource( Enum.PowerType.ComboPoints )
+
+spec:RegisterResource( Enum.PowerType.Rage, {
+    -- Rage per white swing in Bear or Dire Bear Form only (the Warrior's speed rule; Cat and caster swings add none).
+    -- `aura` gates it in both layers (VirtualState's swing entry, spec §0.3; Hekili's forecast); `stop` too.
+    -- shortcut: crits, misses, Blood Frenzy, Natural Reaction and rage from damage taken are unmodelled; VirtualState's
+    -- swing-scale calibration absorbs a steady bias. Upgrade from the combat-log rows once a non-cast `now` exists.
+    mainhand = {
+        swing = "mainhand",
+        aura = "bear_form",
+
+        last = function ()
+            local swing = state.swings.mainhand
+            local t = state.query_time
+            if state.mainhand_speed == 0 then return 0 end
+            return swing + floor( ( t - swing ) / state.mainhand_speed ) * state.mainhand_speed
+        end,
+
+        interval = "mainhand_speed",
+
+        stop = function () return state.swings.mainhand == 0 or not state.buff.bear_form.up end,
+        value = function () return BEAR_RAGE_RATE * bearSwing() end,
+    },
+
+    -- Enrage's aura (25503): 2 rage every second for 10 s (DB2: periodic energize 20 every 1000 ms).
+    enrage = {
+        aura = "enrage",
+
+        last = function ()
+            local app = state.buff.enrage.applied
+            return app + floor( state.query_time - app )
+        end,
+
+        interval = 1,
+        value = 2,
+    },
+}, nil, {
+    -- Out-of-combat rage loss per second: the Warrior's measured 1.25 (its Rage tooltip), until checkpoint Q9 reads
+    -- it in Bear Form.
+    decay = function () return 1.25 end,
+} )
+
+-- Mana: secret even out of combat; costs below 1 are fractions of the maximum in both layers (spec §0.1).
+spec:RegisterResource( Enum.PowerType.Mana )
+
+-- Talents: { node (unused on Forever), rank 1's spell, max rank }: the DB2's 47 Classic nodes (16 Balance, 16 Feral
+-- Combat, 15 Restoration), keys Classic's, until the live export (checkpoint Q1) replaces them. The last three are
+-- placeholders the export replaces, so no reader names an unregistered key.
+spec:RegisterTalents( {
+    -- Balance (16)
+    improved_wrath            = { 0, 16814, 5 },
+    natures_grasp             = { 0, 16689, 1 },
+    improved_natures_grasp    = { 0, 17245, 4 },
+    improved_entangling_roots = { 0, 16918, 3 },
+    improved_moonfire         = { 0, 16821, 5 },
+    natural_weapons           = { 0, 16902, 5 },
+    natural_shapeshifter      = { 0, 16833, 3 },
+    improved_thorns           = { 0, 16836, 3 },
+    omen_of_clarity           = { 0, 16864, 1 },
+    natures_reach             = { 0, 16819, 2 },
+    vengeance                 = { 0, 16909, 5 },
+    improved_starfire         = { 0, 16850, 5 },
+    natures_grace             = { 0, 16880, 1 },
+    moonglow                  = { 0, 16845, 3 },
+    moonfury                  = { 0, 16896, 5 },
+    moonkin_form              = { 0, 24858, 1 },
+    -- Feral Combat (16)
+    ferocity                  = { 0, 16934, 5 },
+    feral_aggression          = { 0, 16858, 5 },
+    feral_instinct            = { 0, 16947, 5 },
+    brutal_impact             = { 0, 16940, 2 },
+    thick_hide                = { 0, 16929, 5 },
+    feline_swiftness          = { 0, 17002, 2 },
+    feral_charge              = { 0, 16979, 1 },
+    sharpened_claws           = { 0, 16942, 3 },
+    improved_shred            = { 0, 16966, 2 }, -- Shredding Attacks
+    predatory_strikes         = { 0, 16972, 3 },
+    blood_frenzy              = { 0, 16952, 2 },
+    primal_fury               = { 0, 16958, 2 }, -- "Blood Frenzy" on Forever
+    savage_fury               = { 0, 16998, 2 },
+    faerie_fire_feral         = { 0, 16857, 1 },
+    heart_of_the_wild         = { 0, 17003, 5 },
+    leader_of_the_pack        = { 0, 17007, 1 },
+    -- Restoration (15)
+    improved_mark_of_the_wild = { 0, 17050, 5 },
+    furor                     = { 0, 17056, 5 },
+    improved_healing_touch    = { 0, 17069, 5 },
+    natures_focus             = { 0, 17063, 5 },
+    improved_enrage           = { 0, 17079, 2 },
+    reflection                = { 0, 17106, 3 },
+    insect_swarm              = { 0, 5570, 1 },
+    subtlety                  = { 0, 17118, 5 },
+    tranquil_spirit           = { 0, 24968, 5 },
+    improved_rejuvenation     = { 0, 17111, 3 },
+    natures_swiftness         = { 0, 17116, 1 },
+    gift_of_nature            = { 0, 17104, 5 },
+    improved_tranquility      = { 0, 17123, 2 },
+    improved_regrowth         = { 0, 17074, 5 },
+    swiftmend                 = { 0, 18562, 1 },
+    -- Forever-only placeholders, replaced by the export (checkpoint Q1).
+    improved_shifting_power   = { 0, 1322670, 2 },
+    natures_splendor          = { 0, 1223083, 1 },
+    eclipse                   = { 0, 408248, 3 },
+} )
+
+spec:RegisterAuras( {
+    aquatic_form = {
+        id = 1066,
+        duration = 3600,
+        max_stack = 1,
+    },
+    barkskin = {
+        id = 22812,
+        duration = 15,
+        max_stack = 1,
+    },
+    bash = {
+        id = 5211,
+        copy = rest( BASH ),
+        duration = function () return ( BASH_STUN[ knownRank( BASH ) ] or 2 ) + 0.5 * talent.brutal_impact.rank end,
+        max_stack = 1,
+    },
+    bear_form = {
+        id = 5487,
+        copy = { 9634 },
+        duration = 3600,
+        max_stack = 1,
+    },
+    berserk = {
+        id = 417141,
+        duration = 15,
+        max_stack = 1,
+    },
+    -- Classic's alias without the other classes' bleeds.
+    bleed = {
+        alias = { "rake", "rip", "pounce_bleed", "lacerate" },
+        aliasType = "debuff",
+        aliasMode = "longest",
+    },
+    cat_form = {
+        id = 768,
+        duration = 3600,
+        max_stack = 1,
+    },
+    challenging_roar = {
+        id = 5209,
+        duration = 6,
+        max_stack = 1,
+    },
+    -- Omen of Clarity's proc (a passive on Forever): the next covered ability is free (the cost modifier below).
+    clearcasting = {
+        id = 16870,
+        duration = 15,
+        max_stack = 1,
+    },
+    dash = {
+        id = 1850,
+        copy = rest( DASH ),
+        duration = 15,
+        max_stack = 1,
+    },
+    demoralizing_roar = {
+        id = 99,
+        copy = rest( DEMORALIZING_ROAR ),
+        duration = 30,
+        max_stack = 1,
+    },
+    eclipse = {
+        id = 408255,
+        copy = { 441260 },
+        duration = 15,
+        max_stack = 4,
+    },
+    entangling_roots = {
+        id = 339,
+        copy = rest( ROOTS ),
+        duration = function () return ROOTS_DURATION[ knownRank( ROOTS ) ] or 12 end,
+        max_stack = 1,
+    },
+    -- The rage entry's aura: 25503 is the 10 s buff, 5229 the cast.
+    enrage = {
+        id = 25503,
+        copy = { 5229 },
+        duration = 10,
+        tick_time = 1,
+        max_stack = 1,
+    },
+    faerie_fire = {
+        id = 770,
+        copy = rest( FAERIE_FIRE ),
+        duration = 40,
+        max_stack = 1,
+    },
+    feral_charge_effect = {
+        id = 19675,
+        duration = 4,
+        max_stack = 1,
+    },
+    -- Cat or Bear Form: Faerie Fire's free cost and cooldown.
+    feral_form = {
+        alias = { "cat_form", "bear_form" },
+        aliasType = "buff",
+        aliasMode = "first",
+    },
+    form = {
+        alias = FORMS,
+        aliasType = "buff",
+        aliasMode = "first",
+    },
+    frenzied_regeneration = {
+        id = 22842,
+        duration = 10,
+        tick_time = 1,
+        max_stack = 1,
+    },
+    gift_of_the_wild = {
+        id = 21849,
+        copy = rest( GIFT_OF_THE_WILD ),
+        duration = 3600,
+        max_stack = 1,
+    },
+    growl = {
+        id = 6795,
+        duration = 3,
+        max_stack = 1,
+    },
+    hurricane = {
+        id = 16914,
+        copy = rest( HURRICANE ),
+        duration = 10,
+        tick_time = 1,
+        max_stack = 1,
+    },
+    innervate = {
+        id = 29166,
+        duration = 20,
+        tick_time = 1,
+        max_stack = 1,
+    },
+    insect_swarm = {
+        id = 5570,
+        copy = rest( INSECT_SWARM ),
+        duration = function () return 12 + 2 * talent.natures_splendor.rank end,
+        tick_time = 2,
+        max_stack = 1,
+    },
+    lacerate = {
+        id = 414644,
+        copy = rest( LACERATE ),
+        duration = 15,
+        tick_time = 3,
+        max_stack = 5,
+    },
+    mark_of_the_wild = {
+        id = 1126,
+        copy = rest( MARK_OF_THE_WILD ),
+        duration = 3600,
+        max_stack = 1,
+    },
+    -- Maul queued on the next swing (C_Spell.IsCurrentSpell, applied in reset_precast), a full swing long.
+    maul = {
+        duration = function () return state.mainhand_speed end,
+        max_stack = 1,
+    },
+    moonfire = {
+        id = 8921,
+        copy = rest( MOONFIRE ),
+        duration = function () return ( knownRank( MOONFIRE ) > 1 and 12 or 9 ) + 3 * talent.natures_splendor.rank end,
+        tick_time = 3,
+        max_stack = 1,
+    },
+    moonkin_form = {
+        id = 24858,
+        duration = 3600,
+        max_stack = 1,
+    },
+    natures_grace = {
+        id = 16886,
+        duration = 3,
+        max_stack = 1,
+    },
+    natures_grasp = {
+        id = 16689,
+        copy = rest( NATURES_GRASP ),
+        duration = 45,
+        max_stack = 1,
+    },
+    -- The target faces us: the rest of 5 s after a "must be behind" error (reset_precast).
+    not_behind = {
+        duration = 5,
+        max_stack = 1,
+    },
+    pounce = {
+        id = 9005,
+        copy = rest( POUNCE ),
+        duration = function () return 2 + 0.5 * talent.brutal_impact.rank end,
+        max_stack = 1,
+    },
+    pounce_bleed = {
+        id = 9007,
+        copy = rest( POUNCE_BLEED ),
+        duration = 18,
+        tick_time = 3,
+        max_stack = 1,
+    },
+    prowl = {
+        id = 5215,
+        copy = rest( PROWL ),
+        duration = 3600,
+        max_stack = 1,
+    },
+    rake = {
+        id = 1822,
+        copy = rest( RAKE ),
+        duration = 9,
+        tick_time = 3,
+        max_stack = 1,
+    },
+    rip = {
+        id = 1079,
+        copy = rest( RIP ),
+        duration = 12,
+        tick_time = 2,
+        max_stack = 1,
+    },
+    thorns = {
+        id = 467,
+        copy = rest( THORNS ),
+        duration = 600,
+        max_stack = 1,
+    },
+    travel_form = {
+        id = 783,
+        duration = 3600,
+        max_stack = 1,
+    },
+} )
+
+-- Clearcasting (16870): aura 108 misc 14 (cost) -100% on the abilities its class masks name (15973374 / 100664659 /
+-- 1024 / 142606400 against SpellClassSet 7), so the next one is free; a covered cast whose declared cost is above 0
+-- takes the charge. The rank-1 IDs of the covered abilities this file registers (higher ranks resolve through each
+-- ability's `copy`), from
+--   select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
+--     join SpellPower p on p.SpellID=o.SpellID where o.SpellClassSet=7 and (p.ManaCost>0 or p.PowerCostPct>0) and not
+--     ((o.SpellClassMask_0 & 15973374)=0 and (o.SpellClassMask_1 & 100664659)=0 and (o.SpellClassMask_2 & 1024)=0
+--     and (o.SpellClassMask_3 & 142606400)=0)
+-- Covered but unregistered: Tranquility, Swiftmend, the rune spells. The query also names Primal Bite and Demoralizing
+-- Roar; the spec leaves them out until checkpoint Q6 sees one usable at 0 rage with Clearcasting up. Not covered:
+-- Wrath, Faerie Fire, Cower, Challenging Roar, Mark and Gift of the Wild, Shifting Power.
+spec:RegisterCostMod( {
+    aura = "clearcasting",
+    pct = -1,
+    charges = 1,
+    spells = { 8921, 2912, 5570, 16914, 5185, 8936, 774, 1082, 1822, 5221, 1079, 22568, 9005, 6785, 779, 6807, 414644,
+        5211, 1238122, 339, 467, 16689 },
+} )
+
+-- A shift (Classic's swap_form, Forever's rules): the other forms and a queued Maul go; into Bear all rage is lost
+-- (Furor's 20%-a-rank chance of 10 is unknowable at the cast: none); into Cat the energy is kept (Furor's Forever
+-- restore is unmodelled until checkpoint Q3). The forms' `now` write the same lines.
+spec:RegisterStateFunction( "swap_form", function( form )
+    for i = 1, #FORMS do removeBuff( FORMS[ i ] ) end
+    removeBuff( "maul" )
+    if form == "bear_form" then spend( rage.current, "rage" ) end
+    applyBuff( form )
+end )
+
+-- The bleeds' misses, as Classic's combat-log windows (event-facade spec §6): a dodged, parried or missed Rake, Rip or
+-- Pounce still raised SPELL_CAST_SUCCESS, so its `now` applied the debuff; the miss row removes it at the next reset.
+local bleedOf = {} -- spell ID -> the debuff its miss leaves off the target
+for _, id in ipairs( RAKE ) do bleedOf[ id ] = "rake" end
+for _, id in ipairs( RIP ) do bleedOf[ id ] = "rip" end
+for _, id in ipairs( POUNCE ) do bleedOf[ id ] = "pounce_bleed" end
+local missedAt = { rake = 0, rip = 0, pounce_bleed = 0 }
+
+-- The UI_ERROR_MESSAGE types of "You must be behind your target" (checkpoint Q11 records it; until then none, and the
+-- window never opens). On ns so the headless specs can name one.
+local NOT_BEHIND_ERRORS = {}
+ns.DruidNotBehindErrors = NOT_BEHIND_ERRORS
+local NOT_BEHIND_WINDOW = 5
+local behindErrAt = 0
+
+spec:RegisterEvent( "COMBAT_LOG_EVENT_UNFILTERED", function()
+    local _, subtype, _, sourceGUID, _, _, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
+
+    if sourceGUID == state.GUID and subtype == "SPELL_MISSED" and bleedOf[ spellID ] then
+        missedAt[ bleedOf[ spellID ] ] = GetTime()
+    end
+end )
+
+spec:RegisterEvent( "UI_ERROR_MESSAGE", function( _, errorType )
+    if NOT_BEHIND_ERRORS[ errorType ] then behindErrAt = GetTime() end
+end )
+
+spec:RegisterHook( "reset_precast", function()
+    -- The form from the plain shapeshift reads, as the Warrior's stance (forever-facade-notes: GetShapeshiftForm,
+    -- GetShapeshiftFormInfo); Dire Bear Form reads as bear_form.
+    for i = 1, #FORMS do removeBuff( FORMS[ i ] ) end
+    local form = GetShapeshiftForm()
+    if form and form > 0 then
+        local _, _, _, spellID = GetShapeshiftFormInfo( form )
+        local aura = FORM_OF_SPELL[ spellID ]
+        if aura then applyBuff( aura ) end
+    end
+
+    local maul = knownRank( MAUL )
+    if maul > 0 and IsCurrentSpell( MAUL[ maul ] ) then applyBuff( "maul" ) end
+
+    if now == query_time then
+        for key, t in pairs( missedAt ) do
+            if t > 0 and debuff[ key ].up and t >= debuff[ key ].applied then removeDebuff( "target", key ) end
+        end
+        if behindErrAt > 0 and now - behindErrAt < NOT_BEHIND_WINDOW then
+            applyBuff( "not_behind", behindErrAt + NOT_BEHIND_WINDOW - now )
+        end
+    end
+end )
+
+spec:RegisterAbilities( {
+    aquatic_form = {
+        id = 1066,
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return 0.20 * ( 1 - 0.1 * talent.natural_shapeshifter.rank ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( AQUATIC_FORM ),
+        nobuff = "aquatic_form",
+
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            for i = 1, #FORMS do removeBuff( FORMS[ i ] ) end
+            removeBuff( "maul" )
+            applyBuff( "aquatic_form" )
+        end,
+
+        handler = function ()
+            swap_form( "aquatic_form" )
+        end,
+    },
+
+    barkskin = {
+        id = 22812,
+        cast = 0,
+        cooldown = 60,
+        gcd = "spell",
+
+        startsCombat = false,
+        known = knows( BARKSKIN ),
+        toggle = "defensives",
+
+        now = function ()
+            applyBuff( "barkskin" )
+        end,
+
+        handler = function ()
+            applyBuff( "barkskin" )
+        end,
+    },
+
+    bash = {
+        id = 5211,
+        copy = rest( BASH ),
+        cast = 0,
+        cooldown = 60, -- Brutal Impact's -30 s unmodelled (a cooldown modifier)
+        gcd = "spell",
+
+        spend = 10,
+        spendType = "rage",
+
+        startsCombat = true,
+        known = knows( BASH ),
+        buff = "bear_form",
+
+        now = function ()
+            applyDebuff( "target", "bash", ( BASH_STUN[ knownRank( BASH ) ] or 2 ) + 0.5 * talent.brutal_impact.rank )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "bash" )
+        end,
+    },
+
+    bear_form = {
+        id = 5487,
+        copy = { 9634 },
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return 0.55 * ( 1 - 0.1 * talent.natural_shapeshifter.rank ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( BEAR_FORM ),
+        nobuff = "bear_form",
+
+        now = function ()
+            for i = 1, #FORMS do removeBuff( FORMS[ i ] ) end
+            removeBuff( "maul" )
+            spend( rage.current, "rage" )
+            applyBuff( "bear_form" )
+        end,
+
+        handler = function ()
+            swap_form( "bear_form" )
+        end,
+    },
+
+    berserk = {
+        id = 417141,
+        cast = 0,
+        cooldown = 180,
+        gcd = "off",
+
+        startsCombat = false,
+        known = knows( BERSERK ),
+        toggle = "cooldowns",
+        -- "Requires Cat Form, Bear Form, Dire Bear Form" (DB2 text): whichever is up.
+        buff = function ()
+            if buff.bear_form.up then return "bear_form" end
+            return "cat_form"
+        end,
+
+        now = function ()
+            applyBuff( "berserk" )
+        end,
+
+        handler = function ()
+            applyBuff( "berserk" )
+        end,
+    },
+
+    cat_form = {
+        id = 768,
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return 0.55 * ( 1 - 0.1 * talent.natural_shapeshifter.rank ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( CAT_FORM ),
+        nobuff = "cat_form",
+
+        now = function ()
+            for i = 1, #FORMS do removeBuff( FORMS[ i ] ) end
+            removeBuff( "maul" )
+            applyBuff( "cat_form" )
+        end,
+
+        handler = function ()
+            swap_form( "cat_form" )
+        end,
+    },
+
+    challenging_roar = {
+        id = 5209,
+        cast = 0,
+        cooldown = 600,
+        gcd = "spell",
+
+        spend = 15,
+        spendType = "rage",
+
+        startsCombat = true,
+        known = knows( CHALLENGING_ROAR ),
+        buff = "bear_form",
+
+        now = function ()
+            applyDebuff( "target", "challenging_roar" )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "challenging_roar" )
+        end,
+    },
+
+    claw = {
+        id = 1082,
+        copy = rest( CLAW ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "totem",
+
+        spend = function () return max( 0, 45 - talent.ferocity.rank ) end,
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( CLAW ),
+        buff = "cat_form",
+
+        handler = function ()
+            gain( 1, "combo_points" )
+        end,
+    },
+
+    cower = {
+        id = 8998,
+        copy = rest( COWER ),
+        cast = 0,
+        cooldown = 10,
+        gcd = "totem",
+
+        spend = 20,
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( COWER ),
+        buff = "cat_form",
+    },
+
+    dash = {
+        id = 1850,
+        copy = rest( DASH ),
+        cast = 0,
+        cooldown = 300,
+        gcd = "off",
+
+        startsCombat = false,
+        known = knows( DASH ),
+        buff = "cat_form",
+
+        now = function ()
+            applyBuff( "dash" )
+        end,
+
+        handler = function ()
+            applyBuff( "dash" )
+        end,
+    },
+
+    demoralizing_roar = {
+        id = 99,
+        copy = rest( DEMORALIZING_ROAR ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = 10,
+        spendType = "rage",
+
+        startsCombat = true,
+        known = knows( DEMORALIZING_ROAR ),
+        buff = "bear_form",
+
+        now = function ()
+            applyDebuff( "target", "demoralizing_roar" )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "demoralizing_roar" )
+        end,
+    },
+
+    -- 10 rage now (DB2 effect 30 base 100), then 2 a second for 10 s from its aura (the rage resource's entry).
+    enrage = {
+        id = 5229,
+        cast = 0,
+        cooldown = 60,
+        gcd = "off",
+
+        startsCombat = false,
+        known = knows( ENRAGE ),
+        buff = "bear_form",
+
+        now = function ()
+            gain( 10, "rage" )
+            applyBuff( "enrage" )
+        end,
+
+        handler = function ()
+            gain( 10, "rage" )
+            applyBuff( "enrage" )
+        end,
+    },
+
+    entangling_roots = {
+        id = 339,
+        copy = rest( ROOTS ),
+        cast = 1.5,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( ROOTS_COST, ROOTS ) end,
+        spendType = "mana",
+
+        startsCombat = true,
+        known = knows( ROOTS ),
+        nobuff = "feral_form",
+
+        now = function ()
+            applyDebuff( "target", "entangling_roots", ROOTS_DURATION[ knownRank( ROOTS ) ] or 12 )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "entangling_roots" )
+        end,
+    },
+
+    faerie_fire = {
+        id = 770,
+        copy = rest( FAERIE_FIRE ),
+        cast = 0,
+        -- Free with a 6 s cooldown in Cat or Bear Form (TDF Bear.lua; checkpoint Q7 confirms).
+        cooldown = function () return buff.feral_form.up and 6 or 0 end,
+        gcd = "spell",
+
+        spend = function ()
+            if buff.feral_form.up then return 0 end
+            return byRank( FAERIE_FIRE_COST, FAERIE_FIRE )
+        end,
+        spendType = "mana",
+
+        startsCombat = true,
+        known = knows( FAERIE_FIRE ),
+
+        now = function ()
+            applyDebuff( "target", "faerie_fire" )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "faerie_fire" )
+        end,
+    },
+
+    feral_charge = {
+        id = 1238122,
+        copy = { 16979 },
+        cast = 0,
+        cooldown = 15,
+        gcd = "off",
+
+        spend = 5,
+        spendType = "rage",
+
+        startsCombat = true,
+        known = knows( FERAL_CHARGE ),
+        buff = "bear_form",
+
+        now = function ()
+            applyDebuff( "target", "feral_charge_effect" )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "feral_charge_effect" )
+        end,
+    },
+
+    -- Bite converts all the energy left after its cost (DB2 22568 text), Clearcasting's free Bite too.
+    ferocious_bite = {
+        id = 22568,
+        copy = rest( FEROCIOUS_BITE ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "totem",
+
+        spend = 35,
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( FEROCIOUS_BITE ),
+        buff = "cat_form",
+
+        usable = function () return combo_points.current > 0, "requires combo points" end,
+
+        now = function ()
+            spend( energy.current, "energy" )
+        end,
+
+        handler = function ()
+            spend( combo_points.current, "combo_points" )
+            spend( energy.current, "energy" )
+        end,
+    },
+
+    -- Its rage drain is unmodelled: health is secret, and the drain stops at full health.
+    frenzied_regeneration = {
+        id = 22842,
+        cast = 0,
+        cooldown = 180,
+        gcd = "spell",
+
+        startsCombat = false,
+        known = knows( FRENZIED_REGENERATION ),
+        toggle = "defensives",
+        buff = "bear_form",
+
+        now = function ()
+            applyBuff( "frenzied_regeneration" )
+        end,
+
+        handler = function ()
+            applyBuff( "frenzied_regeneration" )
+        end,
+    },
+
+    gift_of_the_wild = {
+        id = 21849,
+        copy = rest( GIFT_OF_THE_WILD ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( GIFT_OF_THE_WILD_COST, GIFT_OF_THE_WILD ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( GIFT_OF_THE_WILD ),
+        nobuff = "feral_form",
+
+        now = function ()
+            applyBuff( "gift_of_the_wild" )
+        end,
+
+        handler = function ()
+            applyBuff( "gift_of_the_wild" )
+        end,
+    },
+
+    growl = {
+        id = 6795,
+        cast = 0,
+        cooldown = 8,
+        gcd = "off",
+
+        startsCombat = true,
+        known = knows( GROWL ),
+        buff = "bear_form",
+
+        now = function ()
+            applyDebuff( "target", "growl" )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "growl" )
+        end,
+    },
+
+    -- No pack line: registered so a cast spends Clearcasting.
+    healing_touch = {
+        id = 5185,
+        copy = rest( HEALING_TOUCH ),
+        cast = function () return byRank( HEALING_TOUCH_CAST, HEALING_TOUCH ) end,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( HEALING_TOUCH_COST, HEALING_TOUCH ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( HEALING_TOUCH ),
+        nobuff = "feral_form",
+    },
+
+    hurricane = {
+        id = 16914,
+        copy = rest( HURRICANE ),
+        cast = 10,
+        channeled = true,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( HURRICANE_COST, HURRICANE ) end,
+        spendType = "mana",
+
+        startsCombat = true,
+        known = knows( HURRICANE ),
+        nobuff = "feral_form",
+        aura = "hurricane",
+
+        start = function ()
+            applyDebuff( "target", "hurricane" )
+        end,
+    },
+
+    innervate = {
+        id = 29166,
+        cast = 0,
+        cooldown = 360,
+        gcd = "spell",
+
+        spend = 0.05,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( INNERVATE ),
+        toggle = "cooldowns",
+        nobuff = "feral_form",
+
+        now = function ()
+            applyBuff( "innervate" )
+        end,
+
+        handler = function ()
+            applyBuff( "innervate" )
+        end,
+    },
+
+    insect_swarm = {
+        id = 5570,
+        copy = rest( INSECT_SWARM ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( INSECT_SWARM_COST, INSECT_SWARM ) end,
+        spendType = "mana",
+
+        startsCombat = true,
+        known = knows( INSECT_SWARM ),
+        nobuff = "feral_form",
+
+        now = function ()
+            applyDebuff( "target", "insect_swarm", 12 + 2 * talent.natures_splendor.rank )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "insect_swarm" )
+        end,
+    },
+
+    lacerate = {
+        id = 414644,
+        copy = rest( LACERATE ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        -- Shredding Attacks: -6 rage a rank by its DB2 text (m2 = -60; checkpoint Q12)
+        spend = function () return max( 0, 15 - 6 * talent.improved_shred.rank ) end,
+        spendType = "rage",
+
+        startsCombat = true,
+        known = knows( LACERATE ),
+        buff = "bear_form",
+
+        now = function ()
+            applyDebuff( "target", "lacerate", 15, min( 5, debuff.lacerate.stack + 1 ) )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "lacerate", 15, min( 5, debuff.lacerate.stack + 1 ) )
+        end,
+    },
+
+    mark_of_the_wild = {
+        id = 1126,
+        copy = rest( MARK_OF_THE_WILD ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( MARK_OF_THE_WILD_COST, MARK_OF_THE_WILD ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( MARK_OF_THE_WILD ),
+        nobuff = "feral_form",
+
+        now = function ()
+            applyBuff( "mark_of_the_wild" )
+        end,
+
+        handler = function ()
+            applyBuff( "mark_of_the_wild" )
+        end,
+    },
+
+    maul = {
+        id = 6807,
+        copy = rest( MAUL ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "off",
+
+        spend = function () return max( 0, 15 - talent.ferocity.rank ) end,
+        spendType = "rage",
+
+        startsCombat = true,
+        -- VirtualState: paid at the main hand's next swing, which then brings no rage. Hekili's own simulation pays
+        -- at the press (the Warrior's Heroic Strike alike), so the two differ by up to one swing.
+        onNextSwing = true,
+        known = knows( MAUL ),
+        buff = "bear_form",
+
+        usable = function () return not buff.maul.up, "Maul is already queued" end,
+
+        handler = function ()
+            applyBuff( "maul" )
+        end,
+    },
+
+    moonfire = {
+        id = 8921,
+        copy = rest( MOONFIRE ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( MOONFIRE_COST, MOONFIRE ) end,
+        spendType = "mana",
+
+        startsCombat = true,
+        known = knows( MOONFIRE ),
+        nobuff = "feral_form",
+
+        now = function ()
+            local base = knownRank( MOONFIRE ) > 1 and 12 or 9 -- rank 1 lasts 9 s
+            applyDebuff( "target", "moonfire", base + 3 * talent.natures_splendor.rank )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "moonfire" )
+        end,
+    },
+
+    moonkin_form = {
+        id = 24858,
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return 0.35 * ( 1 - 0.1 * talent.natural_shapeshifter.rank ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( MOONKIN_FORM ),
+        nobuff = "moonkin_form",
+
+        now = function ()
+            for i = 1, #FORMS do removeBuff( FORMS[ i ] ) end
+            removeBuff( "maul" )
+            applyBuff( "moonkin_form" )
+        end,
+
+        handler = function ()
+            swap_form( "moonkin_form" )
+        end,
+    },
+
+    natures_grasp = {
+        id = 16689,
+        copy = rest( NATURES_GRASP ),
+        cast = 0,
+        cooldown = 60,
+        gcd = "spell",
+
+        spend = function () return byRank( NATURES_GRASP_COST, NATURES_GRASP ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( NATURES_GRASP ),
+        nobuff = "feral_form",
+
+        now = function ()
+            applyBuff( "natures_grasp" )
+        end,
+
+        handler = function ()
+            applyBuff( "natures_grasp" )
+        end,
+    },
+
+    pounce = {
+        id = 9005,
+        copy = rest( POUNCE ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "totem",
+
+        spend = 50,
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( POUNCE ),
+        buff = "prowl",
+
+        now = function ()
+            removeBuff( "prowl" )
+            applyDebuff( "target", "pounce", 2 + 0.5 * talent.brutal_impact.rank )
+            applyDebuff( "target", "pounce_bleed" )
+        end,
+
+        handler = function ()
+            removeBuff( "prowl" )
+            applyDebuff( "target", "pounce" )
+            applyDebuff( "target", "pounce_bleed" )
+            gain( 1, "combo_points" )
+        end,
+    },
+
+    primal_bite = {
+        id = 407995,
+        copy = rest( PRIMAL_BITE ),
+        cast = 0,
+        cooldown = 6, -- Berserk's no-cooldown rule unmodelled
+        gcd = "spell",
+
+        spend = function () return max( 0, 20 - talent.ferocity.rank ) end,
+        spendType = "rage",
+
+        startsCombat = true,
+        known = knows( PRIMAL_BITE ),
+        buff = "bear_form",
+    },
+
+    prowl = {
+        id = 5215,
+        copy = rest( PROWL ),
+        cast = 0,
+        cooldown = 10,
+        gcd = "off",
+
+        startsCombat = false,
+        known = knows( PROWL ),
+        buff = "cat_form",
+
+        usable = function () return combat == 0, "cannot be in combat" end,
+
+        now = function ()
+            applyBuff( "prowl" )
+        end,
+
+        handler = function ()
+            applyBuff( "prowl" )
+        end,
+    },
+
+    rake = {
+        id = 1822,
+        copy = rest( RAKE ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "totem",
+
+        spend = function () return max( 0, 40 - talent.ferocity.rank ) end,
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( RAKE ),
+        buff = "cat_form",
+
+        now = function ()
+            applyDebuff( "target", "rake" )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "rake" )
+            gain( 1, "combo_points" )
+        end,
+    },
+
+    ravage = {
+        id = 6785,
+        copy = rest( RAVAGE ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "totem",
+
+        spend = 60,
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( RAVAGE ),
+        buff = "prowl",
+
+        now = function ()
+            removeBuff( "prowl" )
+        end,
+
+        handler = function ()
+            removeBuff( "prowl" )
+            gain( 1, "combo_points" )
+        end,
+    },
+
+    -- No pack line: registered so a cast spends Clearcasting.
+    regrowth = {
+        id = 8936,
+        copy = rest( REGROWTH ),
+        cast = 2,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( REGROWTH_COST, REGROWTH ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( REGROWTH ),
+        nobuff = "feral_form",
+    },
+
+    rejuvenation = {
+        id = 774,
+        copy = rest( REJUVENATION ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( REJUVENATION_COST, REJUVENATION ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( REJUVENATION ),
+        nobuff = "feral_form",
+    },
+
+    rip = {
+        id = 1079,
+        copy = rest( RIP ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "totem",
+
+        spend = 30,
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( RIP ),
+        buff = "cat_form",
+
+        usable = function () return combo_points.current > 0, "requires combo points" end,
+
+        now = function ()
+            applyDebuff( "target", "rip" )
+        end,
+
+        handler = function ()
+            applyDebuff( "target", "rip" )
+            spend( combo_points.current, "combo_points" )
+        end,
+    },
+
+    -- Forever's Tiger's Fury replacement: 55% of base mana into 40 energy (DB2 1322605). No toggle: it is the core.
+    shifting_power = {
+        id = 1322605,
+        cast = 0,
+        cooldown = function () return 16 - 4 * talent.improved_shifting_power.rank end, -- spec D5; checkpoint Q4
+        gcd = "totem",
+
+        spend = function () return 0.55 * ( 1 - 0.1 * talent.natural_shapeshifter.rank ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( SHIFTING_POWER ),
+        buff = "cat_form",
+
+        now = function ()
+            gain( SHIFTING_POWER_ENERGY, "energy" )
+        end,
+
+        handler = function ()
+            gain( SHIFTING_POWER_ENERGY, "energy" )
+        end,
+    },
+
+    shred = {
+        id = 5221,
+        copy = rest( SHRED ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "totem",
+
+        spend = function () return max( 0, 60 - 6 * talent.improved_shred.rank ) end, -- Shredding Attacks
+        spendType = "energy",
+
+        startsCombat = true,
+        known = knows( SHRED ),
+        buff = "cat_form",
+
+        handler = function ()
+            gain( 1, "combo_points" )
+        end,
+    },
+
+    starfire = {
+        id = 2912,
+        copy = rest( STARFIRE ),
+        cast = 3.5, -- shorter with an Eclipse charge (unmodelled)
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( STARFIRE_COST, STARFIRE ) end,
+        spendType = "mana",
+
+        startsCombat = true,
+        known = knows( STARFIRE ),
+        nobuff = "feral_form",
+
+        -- No `now`: spending a charge is no `now` verb; the belief's charges end with the 15 s aura.
+        handler = function ()
+            if buff.eclipse.up then removeStack( "eclipse" ) end
+        end,
+    },
+
+    swipe_bear = {
+        id = 779,
+        copy = rest( SWIPE ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return max( 0, 20 - talent.ferocity.rank ) end,
+        spendType = "rage",
+
+        startsCombat = true,
+        known = knows( SWIPE ),
+        buff = "bear_form",
+    },
+
+    thorns = {
+        id = 467,
+        copy = rest( THORNS ),
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( THORNS_COST, THORNS ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( THORNS ),
+        nobuff = "feral_form",
+
+        now = function ()
+            applyBuff( "thorns" )
+        end,
+
+        handler = function ()
+            applyBuff( "thorns" )
+        end,
+    },
+
+    travel_form = {
+        id = 783,
+        cast = 0,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return 0.20 * ( 1 - 0.1 * talent.natural_shapeshifter.rank ) end,
+        spendType = "mana",
+
+        startsCombat = false,
+        known = knows( TRAVEL_FORM ),
+        nobuff = "travel_form",
+
+        now = function ()
+            for i = 1, #FORMS do removeBuff( FORMS[ i ] ) end
+            removeBuff( "maul" )
+            applyBuff( "travel_form" )
+        end,
+
+        handler = function ()
+            swap_form( "travel_form" )
+        end,
+    },
+
+    wrath = {
+        id = 5176,
+        copy = rest( WRATH ),
+        cast = function () return byRank( WRATH_CAST, WRATH ) - 0.1 * talent.improved_wrath.rank end,
+        cooldown = 0,
+        gcd = "spell",
+
+        spend = function () return byRank( WRATH_COST, WRATH ) end,
+        spendType = "mana",
+
+        startsCombat = true,
+        known = knows( WRATH ),
+        nobuff = "feral_form",
+
+        -- Eclipse's charges (R §9 open: +1 or +2 a Wrath) while the talent is known.
+        now = function ()
+            if talent.eclipse.rank > 0 then addStack( "eclipse", nil, 2 ) end
+        end,
+
+        handler = function ()
+            if talent.eclipse.rank > 0 then addStack( "eclipse", nil, 2 ) end
+        end,
+    },
+} )
+
+-- Shred needs us behind the target, which the game tells only by refusing: in a group the tank holds it, so Shred;
+-- otherwise Claw. settings.behind says the player stands behind; a "must be behind" error says the target faces us
+-- for 5 s (TDF Feral.lua; Classic's combat_mode setting replaced by Hekili's `group`).
+spec:RegisterStateExpr( "shred_ok", function()
+    return settings.behind or ( group and not buff.not_behind.up )
+end )
+
+-- excess_e (ported from Taco Dog Forever's Expressions.excess_e, credited above): the energy a GCD-triggering spender
+-- (Shred, Claw) may use now and still pay the coming Rip (at settings.rip_cp combo points) and Rake refreshes, with
+-- Shifting Power's energy counted once it is off cooldown, unless its GCD would start a refresh later than without it.
+-- Up to three events sorted by due time in preallocated arrays (no table per call); solved backwards: the energy
+-- needed before each event is its cost plus whatever regen cannot cover of the events after it, which honours the
+-- energy cap. -math.huge when the spender's GCD would delay a refresh that could otherwise start on time. A refresh the
+-- druid does not know reserves nothing. Refreshes are reserved at full price (the spender uses up Clearcasting); no
+-- time to die (Forever hides target health). Times are relative to query_time.
+local TOLERANCE = 0.1 -- within this much of its due time a refresh counts as on time
+local CAT_GCD = 1 -- gcd = "totem"
+local evT, evC, evK = { 0, 0, 0 }, { 0, 0, 0 }, { false, false, false } -- due, energy (negative: the credit), credit
+local evS, evS0 = { 0, 0, 0 }, { 0, 0, 0 } -- start times with and without the credit
+
+local function insertEvent( n, at, c, k )
+    local j = n
+    while j >= 1 and evT[ j ] > at do
+        evT[ j + 1 ], evC[ j + 1 ], evK[ j + 1 ] = evT[ j ], evC[ j ], evK[ j ]
+        j = j - 1
+    end
+    evT[ j + 1 ], evC[ j + 1 ], evK[ j + 1 ] = at, c, k
+    return n + 1
+end
+
+-- Forward pass into `out`: nothing starts before the GCD before it ends (every event is on the GCD).
+local function starts( n, gcdFree, useCredit, out )
+    for k = 1, n do
+        if useCredit or not evK[ k ] then
+            local st = evT[ k ]
+            if st < gcdFree then st = gcdFree end
+            out[ k ] = st
+            gcdFree = st + CAT_GCD
+        end
+    end
+end
+
+spec:RegisterStateExpr( "excess_e", function()
+    local cur, cap, regen = energy.current, energy.max, energy.regen
+    local gcdFree = CAT_GCD
+    local n = 0
+    -- Rip, then Rake: due when the debuff falls off; -math.huge when it could start on time but for the spender's GCD
+    -- (Clearcasting may make it free then: action.x.cost); reserved at the full price.
+    if knownRank( RIP ) > 0 and combo_points.current >= settings.rip_cp then
+        local due = debuff.rip.remains
+        if due < gcdFree - TOLERANCE and min( cap, cur + regen * due ) >= action.rip.cost then return -huge end
+        n = insertEvent( n, due, 30, false )
+    end
+    if knownRank( RAKE ) > 0 then
+        local due = debuff.rake.remains
+        if due < gcdFree - TOLERANCE and min( cap, cur + regen * due ) >= action.rake.cost then return -huge end
+        n = insertEvent( n, due, max( 0, 40 - talent.ferocity.rank ), false )
+    end
+    if knownRank( SHIFTING_POWER ) > 0 then
+        n = insertEvent( n, cooldown.shifting_power.remains, -SHIFTING_POWER_ENERGY, true )
+    end
+    -- Use the credit only if its GCD starts no refresh later than without it.
+    starts( n, gcdFree, false, evS0 )
+    starts( n, gcdFree, true, evS )
+    local useCredit = true
+    for k = 1, n do
+        if not evK[ k ] and evS[ k ] > evS0[ k ] + TOLERANCE then useCredit = false end
+    end
+    local st = useCredit and evS or evS0
+    -- Backward: the energy needed just before each event so it and everything after it are paid for.
+    local need, nextStart = 0, nil
+    for k = n, 1, -1 do
+        if useCredit or not evK[ k ] then
+            local carry = need
+            if nextStart then
+                carry = need - regen * ( nextStart - st[ k ] )
+                if carry < 0 then carry = 0 end
+            end
+            need = evC[ k ] + carry
+            if need < 0 then need = 0 end
+            nextStart = st[ k ]
+        end
+    end
+    if nextStart then
+        need = need - regen * nextStart
+        if need < 0 then need = 0 end
+    end
+    return cur - need
+end )
+
+-- The settings the priorities read (TDF's names and defaults).
+spec:RegisterSetting( "rip_cp", 5, {
+    type = "range",
+    name = "Rip Combo Points",
+    desc = "Select the combo points at which Rip is applied and its energy reserved.",
+    width = "full",
+    min = 1,
+    max = 5,
+    step = 1,
+} )
+
+spec:RegisterSetting( "bite_finisher", false, {
+    type = "toggle",
+    name = "Ferocious Bite Finisher",
+    desc = "When enabled, Ferocious Bite spends 5 combo points while Rip is up and no energy is held back.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "behind", false, {
+    type = "toggle",
+    name = "Always Behind",
+    desc = "When enabled, Shred is recommended over Claw as if you always stand behind the target.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "buffs", true, {
+    type = "toggle",
+    name = "Out-of-Combat Buffs",
+    desc = "When enabled, Mark of the Wild and Thorns are recommended before combat when missing.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "dump_rage", 60, {
+    type = "range",
+    name = "Swipe Rage Threshold",
+    desc = "Select the rage at or above which the Guardian priority spends rage on Swipe.",
+    width = "full",
+    min = 0,
+    max = 100,
+    step = 1,
+} )
+
+spec:RegisterSetting( "use_enrage", false, {
+    type = "toggle",
+    name = "Use Enrage",
+    desc = "When enabled, the Guardian priority uses Enrage when rage is short.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "moonkin", true, {
+    type = "toggle",
+    name = "Moonkin Form",
+    desc = "When enabled, the Balance priority recommends Moonkin Form before combat.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "trash_dots", true, {
+    type = "toggle",
+    name = "Moonfire on Trash",
+    desc = "When enabled, the Balance priority keeps Moonfire on targets that are not bosses.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "starfire_filler", false, {
+    type = "toggle",
+    name = "Starfire Filler",
+    desc = "When enabled, the Balance priority fills with Starfire instead of Wrath.",
+    width = "full",
+} )
+
+spec:RegisterSetting( "hurricane_targets", 4, {
+    type = "range",
+    name = "Hurricane Targets",
+    desc = "Select the number of enemies at which the Balance priority channels Hurricane (0: never).",
+    width = "full",
+    min = 0,
+    max = 10,
+    step = 1,
+} )
+
+spec:RegisterSetting( "innervate", true, {
+    type = "toggle",
+    name = "Innervate",
+    desc = "When enabled, the Balance priority uses Innervate when mana runs low.",
+    width = "full",
+} )
+
+spec:RegisterOptions( { package = "Feral" } )
diff --git a/Hekili.toc b/Hekili.toc
index 2537e2ef..f4c51692 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -53,6 +53,7 @@ Events.lua
 
 Classes.lua
 Forever\Classes\Warrior.lua
+Forever\Classes\Druid.lua
 Forever\Races\Gnome.lua
 
 Targets.lua
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `262 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [262 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 84 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 52 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

Also: `grep -c 'now = function' Forever/Classes/Druid.lua` prints `33`, and `grep -n 'buff%.clearcasting\|buff.clearcasting' Forever/Classes/Druid.lua` prints nothing.

- [ ] **Step 6: Commit**

```bash
git add Forever/Classes/Druid.lua Forever/spec/druid_spec.lua Forever/spec/helpers/load_druid.lua Constants.lua Hekili.toc .luacheckrc
git commit -m "feat(forever): the Forever Druid class file: Feral, bear and Balance kit on the Forever DB2, now handlers, Clearcasting as a cost modifier, forms from the shapeshift reads, the bleeds' misses, excess_e

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-druid`

---

### Task 5: The Druid's priorities

Spec §8, ruling D2. `tools/packs/druid.lua` holds the three packs (date 20261015, `spec = 1499`, the file's `DRUID_SPEC`): Feral (the spec's SimC text: Nerdegghead via TDF's `feral.simc`, Classic's precombat buffs), Guardian and Balance (TDF's `bear.simc` and `balance.simc`, each description saying it is provisional and why). `lua5.1 tools/make_pack.lua druid` prints the three strings, pasted into `Forever/Classes/Druid.lua` as `spec:RegisterPack( <name>, 20261015, [[...]] )` after `RegisterOptions`. The specs check the strings match the tool's output, the packs' `spec` is the file's `DRUID_SPEC`, and every list names only registered abilities (plus `use_items`, Hekili's `all`), auras, talents, settings and lists, with no secret token (`VS.AplSecretToken`).

**Files:**
- Create: `tools/packs/druid.lua`
- Modify: `Forever/Classes/Druid.lua` (three `RegisterPack` lines at the end)
- Test: `Forever/spec/druid_spec.lua`

**Interfaces:**
- Consumes: Task 3's `make_pack.lua` class argument; Task 4's abilities, auras, talents, settings, `excess_e`, `shred_ok`.
- Produces: the packs `Feral` (default), `Guardian`, `Balance` (`/hekili priority <name>`).

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/spec/druid_spec.lua b/Forever/spec/druid_spec.lua
index 0505434b..8df4a540 100644
--- a/Forever/spec/druid_spec.lua
+++ b/Forever/spec/druid_spec.lua
@@ -593,6 +593,56 @@ describe("Forever Druid", function()
         assert.is_true(ok())
     end)
 
+    it("registers the Feral, Guardian and Balance packs exactly as tools/make_pack.lua druid prints them", function()
+        local printed = {}
+        local pipe = assert(io.popen("lua5.1 tools/make_pack.lua druid"))
+        for line in pipe:lines() do
+            printed[#printed + 1] = line
+        end
+        pipe:close()
+        assert.are.equal(3, #w.packs)
+        for i, name in ipairs({ "Feral", "Guardian", "Balance" }) do
+            assert.are.same({ name, 20261015, printed[i] }, w.packs[i])
+        end
+        assert.are.equal(w.specID, dofile("tools/packs/druid.lua").spec) -- the packs' spec is the file's
+    end)
+
+    it("writes priorities that name only registered abilities, auras, talents, settings and lists", function()
+        local packs = assert(loadfile("tools/make_pack.lua"))("lists", "druid")
+        local secretToken = require("Virtual.State.spec.helpers.load").module().VirtualState.AplSecretToken
+        local shared = { use_items = true } -- Hekili's `all` (Classes.lua's use_items)
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
+                        assert.is_true(w.abilities[e.action] ~= nil or shared[e.action], where .. ": no ability " .. e.action)
+                    end
+                    local c = e.criteria or ""
+                    for kind, key in c:gmatch("(%a+)%.([%w_]+)") do
+                        if kinds[kind] then
+                            assert.is_not_nil(kinds[kind][key], where .. ": no " .. kind .. " " .. key)
+                        end
+                    end
+                    assert.is_nil(secretToken(c), where) -- no health or time to die: secret on Forever
+                end
+            end
+        end
+        for _, name in ipairs({ "excess_e", "shred_ok" }) do
+            assert.are.equal("function", type(w.exprs[name]), name)
+        end
+    end)
+
     it("declares its pseudo-spec once, as a placeholder until checkpoint Q1, and the settings the packs read", function()
         assert.are.equal(1499, w.specID)
         for key, default in pairs({ rip_cp = 5, bite_finisher = false, behind = false, buffs = true, dump_rage = 60,
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `262 successes / 1 failure / 1 error` (the strings case: no `RegisterPack`; the lists case: no `tools/packs/druid.lua`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root). The three strings are `lua5.1 tools/make_pack.lua druid`'s output once `tools/packs/druid.lua` exists; if a pack's text is edited, rerun it and paste again.

```diff
diff --git a/Forever/Classes/Druid.lua b/Forever/Classes/Druid.lua
index a2b7f06a..9a3fea31 100644
--- a/Forever/Classes/Druid.lua
+++ b/Forever/Classes/Druid.lua
@@ -1705,3 +1705,10 @@ spec:RegisterSetting( "innervate", true, {
 } )
 
 spec:RegisterOptions( { package = "Feral" } )
+
+-- The three priorities, generated by tools/make_pack.lua from tools/packs/druid.lua (lua5.1 tools/make_pack.lua druid
+-- prints these strings, in this order; Forever/spec/druid_spec.lua checks they match). Pick one with
+-- /hekili priority <name>. Guardian and Balance are provisional (their descriptions say why); Restoration is deferred.
+spec:RegisterPack( "Feral", 20261015, [[Hekili:1wzuVnnmqC8pl8sfvmfwhRdgIUhaec4Hj0cp7yhNZTw11oY2HsFXF25StAjPDzunjuLADT)F)VZN)fhYmYpj5vmpqU)QlV6MzxoBoj3VRgi51m(A2sCGMTb)(lGLPIZUtzyvXWkBKk)30KYtDWvdCY9ZU(2Bj5RKvvqRkWXrJmw4xGnqtogOF22iRc0xYz(PVpqr9cVuVmq)HzBuwjOmBd05xgOGgSl3DrG(GSoqz(a1VccuhGJ4MnLMaT2i1EhUOg98b2ACzMlPBxGkykmHgHaTq3weCLSUgt3fDEzbhAg6HjwkwiwzFsXWcy7kq3jYZSlJ5uW4aA(otZum(vgvvQWtAAR1dUkqJxffRHKNWVXqDfW0mSNAncPc7XmUxA0USAle3om)Inm76cJOaDPyRuvDHuSa3UXgKlRSriCtEr8NSJfM1u3TYsSFE0kHVFsME1Ix7xzSA3OzOD5rJgp(keg7My8TbSFM(HS48KH(564GI6igeL32rZ4nwlO9FabIEYBCqH0dBC9NSeSoWUU)uwzD0ReTu0cl7D8U)UVrvfCSbwbPse)7rvNfjR0wyVc8)hjrawdxAACfLyHnSTItuiKAjIe2jpETmFYGKpzpWC3r9HH9meytzkoOWSUxuTQYsRKXnUbbYrcpTDgpWOKU4i54JooCY(pYRKoVlDBciynkpo8(0TlGMvQGkYh3Z3K89h54il2kSsgj)eyG4r7hXGHWrFBobsI28MrS5a0efD9iI6GOOK5JibpI6xdph4kA)nJzpcxdAvdHUyOVDKqhcH9n5)cmglL3n6zgIwdQGZasJgE7yuesKdAlNb8sIFYpCV1tbPhFJ6J38EUxb)u0D7nT)Z8D4c5NcXp3h1s9fwt0ts(xH1sLeFlv37QNMwM8Nd]] )
+spec:RegisterPack( "Guardian", 20261015, [[Hekili:9A12UTjtq4NLCt0FvS4pojoTPkKlIQ6j1Avv61lSadoRmSlA3LeLQkE27ma2EnyCtDI6ng8C8BN5BNb2u2pybPClWMF2PND50tNoJfyFSeybL8KL8f4lsEb(7hQ46ubxskEmxXtjpJRe52pjzXddIPesyZNEXvxXcUtKMcTwbMewW7vA4EqxhTkO1rVtxjsRJ(VyGRNuhvQv3lmcLKN)26isyDKgrtDKqMOkWNCjAEkKWFeFxJcQKfa3uPH0xHU8oOqP55IFkKlQJ(UQjQFHNaAeN1rwvD0muY30IcEED0TcsQcbsIsLNQEqIk)kVkVlrbpikrdEqyVRoYu2KqcpEy5qRYe5yfINyraB8k1acXyU1NWDyMsxmrK5FuCvwM3ArEvL1FUZLNSHN4))6kzy7)cZfg7eQ74Zva5jj)EieKqHam34FMRJXG2a6LUIQmqiEWlmUctDQCHAQWrykfAq1aL9qxExfM8PZLvI8mwKrDJ)SJ7RqdfCH0CT)fEZCdwztZjmM6noIZ4GwaHzcn4cnhX7buXkJzaaAq21BL7cS3pHQpQSSWfjP(tjVBA5jvAniT343AThzQxIYypPtGdUBK)RJ2HILsKK5MrdrXcB4)dYKbSwSIB8sRkkdBUi44jijjKxRTJqER4JDJ01JGWTkVOH)uaPHAybYKWceQyTbEivZ)WPiK7B4I7IZEEFBhss7uSl6rNQn1Y(AEo91nr9aB3hFq5P)r4jY)zb4iwAeQ7uzAKHHMCJHcFmVz(pi5X5qk72vZWO509AISGenEo0colyFDAMft3ibTRR7gQbDFY)ZhX)1mbYOlgXiNIoz2SrmBtnMS6YEwTbGhuh7FfZyZXHSSTa1XRPwlEWE9ihFhYYU6SBZLWazjkrgMe7(ynR3zTvmhSoBxCKXPeNTj(9291sNdB)(eIqVhUZkU3EyoBrVgJ38SUy0NMTkORwe5gRdA75(A59Uy8MxiMX8R(lou7B7lfRPN(mVi(0VX9NV7mDmAUZSJrb4Wn2nHCSrJT7QDd3HUkVjnJDlyN72BVEV(RwFzUG3etEL9ofwK(iSuKlWVUV7d)FvJA2Vd]] )
+spec:RegisterPack( "Balance", 20261015, [[Hekili:LAvtVTnmm0Fl9sw7wHxtxB36WspuSn0oG1lEa7MSzKLJfISKHKCkkWG)Tps)vDsTtaAVKetY3JmKpkz2C2FyHjGxWE48Zo)Q5Nn)swO)PcblSa4RHv4p0qo(5TGc08A7pPmqcbCzPu5VxZw(soCfco7H5xC91SWmzsIOjkHJZc)PXk2iSvXTCwf)DBPmPk(4cRzJ0jnAq91Q4CqdvXsxvSUjERasGLkeaOXW)bxjlCI3HbWZa7k0UTK8sqk1CJovAZfjNGC9BJrVwQRIXKNFAZZO3oQUx7eCFvC4JGnVkETOaFOSadm0d2Man6(u2LqhgWFTGpRk2BQItLkfA5UsRvYbDlg8VXtOFkEVlaBGwdgi2jbUh)R6ckScUjFj4xK3uLrPurktx4eEVuVYf06y2rllttdggwqzr1VEbtFyXhZb76itAKpte9OuLSfFenUo22jqKXwpRKP(D8mEU8zgR2nzgACpe9cPwlSBqrZwG6ToJM9bCSrk0(V1akW1okc4gN)9N3tgwaLorK0lYDdnYbLkQ5XiL05pLuYlaZ25mRBAf1oIU5SzeOnIiHwKlfUB2tWdZxERMIO)Oer)OQUMXM6Xlno3)65YBbxwuIX7ozilYAPyKJuIdzAODInISH466o1yYX9i9Qz1afnAwQ9XxFZI5hcuFb25mI014(3aCpsI(bGEwwGT3fhOrSvWiz9n1TiKfI780zbdpwHgJo6Ohej(1d1NFj00HcjSB7wPyHDzJfYTOUWkbw4ivcZJKpbf9v1wC0uDiopDAwkuQ87Ro6f0dj51j33xT2l)PG(0obnsIFBA(NZ7UByndOOMBmOrewox82gr7zRHy)YjB8pVTmwggBBI47Qj4RBymIyy8TmISp)kiBQTpIVVmbF1BJtkt7pO(qlmDxPmQKzV3aTpT5UxVmk7V67JgtW3L5MRDoy(6VDQUDHnmOKmXcVtSwQK4RL0(clNu7M9)d]] )
diff --git a/tools/packs/druid.lua b/tools/packs/druid.lua
new file mode 100644
index 00000000..1d4bc714
--- /dev/null
+++ b/tools/packs/druid.lua
@@ -0,0 +1,82 @@
+-- tools/packs/druid.lua: the Forever Druid's priorities for tools/make_pack.lua (lua5.1 tools/make_pack.lua druid): the
+-- pack date and pseudo-spec (Forever/Classes/Druid.lua's DRUID_SPEC; regenerate the strings when it changes), and each
+-- pack's name, description and SimC-style text.
+-- Ported from Taco Dog Forever's src/TacoDogForever_Druid/APLs/feral.simc (Nerdegghead's priority, via the user),
+-- bear.simc and balance.simc (after the guides they cite), with Classic's precombat buffs
+-- (origin/classic:Classic/APLs/DruidFeral.simc). Left out on purpose: Tiger's Fury, powershifting and the
+-- cat_ps/innervate_or_shift lists, Omen of Clarity's precombat line, `ttd` guards (target health is secret), Faerie
+-- Fire in cat, the ranged Moonfire opener, and the consumables.
+
+local PACKS = {
+    {
+        name = "Feral",
+        desc = "Forever Feral Druid (cat): Shifting Power below 50 energy, Rip at the set combo points and Rake as they "
+            .. "fall off, never clipping, the rest into Shred (Claw when the target faces you), holding the energy the "
+            .. "refreshes need (excess_e).",
+        simc = [[
+actions.precombat=mark_of_the_wild,if=settings.buffs&!buff.mark_of_the_wild.up&!buff.gift_of_the_wild.up
+actions.precombat+=/thorns,if=settings.buffs&!buff.thorns.up
+actions.precombat+=/cat_form,if=!buff.cat_form.up
+actions=cat_form,if=!buff.cat_form.up
+actions+=/shifting_power,if=energy.current<50
+actions+=/use_items
+actions+=/berserk
+actions+=/rip,if=combo_points.current>=settings.rip_cp&!debuff.rip.up
+actions+=/rake,if=!debuff.rake.up
+actions+=/ferocious_bite,if=settings.bite_finisher&combo_points.current>=5&debuff.rip.up&excess_e>=energy.current
+actions+=/shred,if=shred_ok&excess_e>=action.shred.cost
+actions+=/claw,if=!shred_ok&excess_e>=action.claw.cost
+]],
+    },
+    {
+        name = "Guardian",
+        desc = "Forever Guardian Druid (bear, provisional: bear rage income and decay are unmeasured): Demoralizing "
+            .. "Roar, Lacerate to 5, Primal Bite on cooldown, Maul and Swipe with spare rage.",
+        simc = [[
+actions.precombat=bear_form,if=!buff.bear_form.up
+actions=bear_form,if=!buff.bear_form.up
+actions+=/run_action_list,name=aoe,if=active_enemies>=2
+actions+=/berserk
+actions+=/use_items
+actions+=/demoralizing_roar,if=!debuff.demoralizing_roar.up
+actions+=/lacerate,if=debuff.lacerate.stack>=5&debuff.lacerate.remains<=4.5
+actions+=/primal_bite
+actions+=/faerie_fire,if=!debuff.faerie_fire.up
+actions+=/lacerate,if=boss&debuff.lacerate.stack<5
+actions+=/maul,use_off_gcd=1,if=rage.current>=action.maul.cost+action.primal_bite.cost|!action.primal_bite.known
+actions+=/swipe_bear,if=rage.current>=settings.dump_rage
+actions+=/enrage,if=settings.use_enrage&rage.current<action.primal_bite.cost
+actions+=/frenzied_regeneration
+actions.aoe=demoralizing_roar,if=!debuff.demoralizing_roar.up
+actions.aoe+=/berserk,if=active_enemies>=3
+actions.aoe+=/use_items
+actions.aoe+=/primal_bite
+actions.aoe+=/swipe_bear
+actions.aoe+=/maul,use_off_gcd=1,if=rage.current>=action.maul.cost+action.swipe_bear.cost+action.primal_bite.cost|!action.primal_bite.known&rage.current>=action.maul.cost+action.swipe_bear.cost
+actions.aoe+=/faerie_fire,if=!debuff.faerie_fire.up
+]],
+    },
+    {
+        name = "Balance",
+        desc = "Forever Balance Druid (provisional: mana is never readable and Eclipse's charge rule is unconfirmed): "
+            .. "Moonkin Form, Moonfire and Insect Swarm kept up, Starfire on Eclipse charges, Wrath to fill, Hurricane "
+            .. "on many targets.",
+        simc = [[
+actions.precombat=moonkin_form,if=settings.moonkin&!buff.moonkin_form.up
+actions.precombat+=/mark_of_the_wild,if=settings.buffs&!buff.mark_of_the_wild.up&!buff.gift_of_the_wild.up
+actions.precombat+=/thorns,if=settings.buffs&!buff.thorns.up
+actions=innervate,if=settings.innervate&mana.current<action.starfire.cost*2
+actions+=/use_items
+actions+=/call_action_list,name=aoe,if=settings.hurricane_targets>0&active_enemies>=settings.hurricane_targets
+actions+=/moonfire,if=!debuff.moonfire.up&(boss|settings.trash_dots)
+actions+=/insect_swarm,if=!debuff.insect_swarm.up&boss
+actions+=/starfire,if=!moving&buff.eclipse.stack>=1
+actions+=/starfire,if=!moving&settings.starfire_filler
+actions+=/wrath,if=!moving
+actions.aoe=moonfire,if=!debuff.moonfire.up
+actions.aoe+=/hurricane,if=!moving
+]],
+    },
+}
+
+return { date = 20261015, spec = 1499, packs = PACKS }
```

- [ ] **Step 4: Run the specs to verify they pass, and that the Warrior's strings did not move**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `264 successes / 0 failures / 0 errors`.

Run: `lua5.1 tools/make_pack.lua druid | wc -l; lua5.1 tools/make_pack.lua | cmp - <(grep -o '\[\[Hekili:[^]]*' Forever/Classes/Warrior.lua | cut -c3-) && echo warrior-identical`
Expected: `3` then `warrior-identical`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [264 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 85 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 52 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add tools/packs/druid.lua Forever/Classes/Druid.lua Forever/spec/druid_spec.lua
git commit -m "feat(forever): the Druid's priorities: Feral (default), Guardian and Balance (provisional), built by tools/make_pack.lua druid

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-druid`

---

### Task 6: Night Elf and Tauren race packs

Spec §9 (and the controller's brief, which adds a Tauren file the spec had left out). Both files are `Forever/Races/Gnome.lua`'s shape, `Hekili:NewRace( <token> )`, inert for any other race, so they serve every class: `NightElf.lua` registers Elune's Light (1259799: +10% crit, 15 s; 180 s, off the GCD, `toggle = "cooldowns"`, `startsCombat = false`) and its aura; `Tauren.lua` registers War Stomp (20549: 2 s stun, 0.5 s cast, 120 s, off the GCD, `toggle = "cooldowns"`), which Hekili's stock racials lack, and its target aura (Plainsrunning, Endurance and Cultivation have nothing to register). Each ability has `now` beside `handler`, two closures. No resource or cost modifier; no pack names either. `races_spec`'s loader runs every race file, as the TOC does.

**Files:**
- Create: `Forever/Races/NightElf.lua`, `Forever/Races/Tauren.lua`
- Modify: `Hekili.toc` (after `Forever\Races\Gnome.lua`)
- Test: `Virtual/State/spec/races_spec.lua`

**Interfaces:**
- Consumes: `Hekili:NewRace` (Races.lua).
- Produces: the race abilities `elunes_light`, `war_stomp` and their auras in `all` for the player's race.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Virtual/State/spec/races_spec.lua b/Virtual/State/spec/races_spec.lua
index 4c6a6635..4a1329bf 100644
--- a/Virtual/State/spec/races_spec.lua
+++ b/Virtual/State/spec/races_spec.lua
@@ -47,7 +47,9 @@ describe("race packs", function()
         _G.Hekili = hekili
         ns = {}
         assert(loadfile("Races.lua"))("Hekili", ns)
-        assert(loadfile("Forever/Races/Gnome.lua"))("Hekili", ns)
+        for _, file in ipairs({ "Gnome", "NightElf", "Tauren" }) do -- every race file runs, as Hekili.toc loads them
+            assert(loadfile("Forever/Races/" .. file .. ".lua"))("Hekili", ns)
+        end
     end
 
     -- An ability as Classes.lua's RegisterAbility builds it: function fields in `funcs`, called on access, wrapped.
@@ -162,6 +164,27 @@ describe("race packs", function()
         assert.are.equal(15, heroic_strike.spend)
     end)
 
+    it("registers Elune's Light and its aura for a Night Elf, War Stomp for a Tauren, and neither elsewhere", function()
+        load("NightElf")
+        local light = all.abilities.elunes_light
+        assert.are.same({ 1259799, 0, 180, "off", "cooldowns" }, { light.id, light.cast, light.cooldown, light.gcd, light.toggle })
+        assert.are.same({ 1259799, 15 }, { all.auras.elunes_light.id, all.auras.elunes_light.duration })
+        assert.is_nil(all.abilities.war_stomp)
+        assert.are.same({ maxMods = {}, costMods = {} }, ns.raceMods) -- no resource or cost modifier
+        load("Tauren")
+        local stomp = all.abilities.war_stomp
+        assert.are.same({ 20549, 0.5, 120, "off" }, { stomp.id, stomp.cast, stomp.cooldown, stomp.gcd })
+        assert.are.same({ 20549, 2 }, { all.auras.war_stomp.id, all.auras.war_stomp.duration })
+        assert.is_nil(all.abilities.elunes_light)
+        for _, a in ipairs({ light, stomp }) do
+            assert.is_function(a.now)
+            assert.are_not.equal(a.handler, a.now) -- two closures: one shared would be refused
+        end
+        load("Gnome")
+        assert.is_not_nil(all.abilities.eureka)
+        assert.is_nil(all.abilities.elunes_light or all.abilities.war_stomp)
+    end)
+
     it("takes a class file's spec:RegisterCostMod (Classes.lua) into the same list, for any race", function()
         load("Human")
         -- the mixin's entry as Classes.lua declares it, compiled with this `ns` as its upvalue
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `256 successes / 9 failures / 0 errors` (every `races_spec` case: its loader asserts on the missing `Forever/Races/NightElf.lua`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/Races/NightElf.lua b/Forever/Races/NightElf.lua
new file mode 100644
index 00000000..2f8d2a32
--- /dev/null
+++ b/Forever/Races/NightElf.lua
@@ -0,0 +1,33 @@
+-- Forever/Races/NightElf.lua
+-- The Night Elf's Forever racial (DB2 1.60.1.70338), for every class: Elune's Light (1259799: +10% critical strike
+-- chance with spells and attacks, aura 290 base 10, for 15 s; 180 s, off the GCD). Shadowmeld stays Hekili's stock
+-- racial (`all`); Quickness and Wisp Spirit are passives. No resource or cost modifier. No pack names it: a race
+-- ability is absent for other races; a player adds it to a priority if wanted. Inert for any other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "NightElf" )
+
+race:RegisterAbility( "elunes_light", {
+    id = 1259799,
+    cast = 0,
+    cooldown = 180,
+    gcd = "off",
+    startsCombat = false,
+    toggle = "cooldowns",
+
+    handler = function ()
+        applyBuff( "elunes_light" )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        applyBuff( "elunes_light" )
+    end,
+} )
+
+race:RegisterAura( "elunes_light", {
+    id = 1259799,
+    duration = 15,
+    max_stack = 1,
+} )
diff --git a/Forever/Races/Tauren.lua b/Forever/Races/Tauren.lua
new file mode 100644
index 00000000..451969f2
--- /dev/null
+++ b/Forever/Races/Tauren.lua
@@ -0,0 +1,33 @@
+-- Forever/Races/Tauren.lua
+-- The Tauren's castable racial on Forever (DB2 1.60.1.70338), for every class: War Stomp (20549: stuns up to 5 enemies
+-- within 8 yards for 2 s; 0.5 s cast, 120 s, off the GCD), which Hekili's stock racials (`all`) lack. Plainsrunning
+-- (1259918, Forever's movement-speed ramp), Endurance and Cultivation have no cast, cost, maximum or rotation effect:
+-- nothing to register. No pack names it. Inert for any other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "Tauren" )
+
+race:RegisterAbility( "war_stomp", {
+    id = 20549,
+    cast = 0.5,
+    cooldown = 120,
+    gcd = "off",
+    startsCombat = true,
+    toggle = "cooldowns",
+
+    handler = function ()
+        applyDebuff( "target", "war_stomp" )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        applyDebuff( "target", "war_stomp" )
+    end,
+} )
+
+race:RegisterAura( "war_stomp", {
+    id = 20549,
+    duration = 2,
+    max_stack = 1,
+} )
diff --git a/Hekili.toc b/Hekili.toc
index f4c51692..7d5efb14 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -55,6 +55,8 @@ Classes.lua
 Forever\Classes\Warrior.lua
 Forever\Classes\Druid.lua
 Forever\Races\Gnome.lua
+Forever\Races\NightElf.lua
+Forever\Races\Tauren.lua
 
 Targets.lua
 Options\DevTools.lua
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `265 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [265 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 87 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 54 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Races/NightElf.lua Forever/Races/Tauren.lua Hekili.toc Virtual/State/spec/races_spec.lua
git commit -m "feat(forever): Night Elf and Tauren race packs: Elune's Light and War Stomp, inert for other races

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-druid`

---

### Task 7: CHECKPOINT A: the export and the pseudo-spec (Q1)

No code. One short session on a Druid, out of combat, ForeverProbe loaded; Hekili's Druid is not active yet (its `DRUID_SPEC` is the placeholder), which Q1 does not need. `Hekili.toc` lists three new files since the client last loaded the branch: a full client restart.

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin forever-druid
git -C ~/src/hekili checkout --detach forever-druid
```

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, and report each answer**

1. Out of combat: `/fprobe export`, then `/reload`, then
   `/run local e=ForeverProbeDB.export;VSCopy(e.meta.class,#e.spells,#e.talents.trees,e.stances.num)`. Report the box. Expected: `DRUID`, a spell count, a tree count and the number of forms on the bar.
2. `/run VSCopy(C_SpecializationInfo.GetSpecialization(),GetSpecializationInfo(1))`. Report the box: the second value is the pseudo-spec ID.
3. The orchestrator copies the beta's `WTF/Account/<account>/SavedVariables/ForeverProbe.lua` (under `_classic_beta_`) to `/home/zack/.claude/jobs/080a308e/tmp/druid/export/ForeverProbe.lua`.

| Answer | → action |
|---|---|
| class not `DRUID`, or 0 trees | the export ran on another character or before the talent pane loaded: repeat item 1 on the Druid after opening the talent pane once |
| spec ID 1491 | **stop and report** to the user: `Constants.lua` keys its rows by ID alone, so the Druid's row would overwrite the Warrior's; a class key is a design change outside this plan |
| spec ID other than 1491 | note it as `ID`; Task 8 writes it into `DRUID_SPEC`, the `Constants.lua` row and `tools/packs/druid.lua` |
| the file copied | Task 8 runs on it |

When the session ends: `git -C ~/src/hekili checkout forever`.

---

### Task 8: The live talent tree and the pseudo-spec (after the export)

Gated on Task 7: the export is at `/home/zack/.claude/jobs/080a308e/tmp/druid/export/ForeverProbe.lua` and the spec ID `ID` is read and is not 1491. Spec §6 "Forever-only addendum", ruling D3. The Warrior's accuracy plan (ruling A1) is the precedent: every node becomes `key = { 0, definitionSpell, maxRank }` with no rank aliases; keys stay Classic's where the talent exists, snake_case names for the Forever-only ones; the three placeholders are replaced (same key when the export carries the same spell); a removed talent's readers lose their term (the Warrior's `improved_cleave` became Raging Blows).

**Files:**
- Modify: `Forever/Classes/Druid.lua` (`DRUID_SPEC`, `RegisterTalents`, the readers of a removed or renamed talent, the three `RegisterPack` strings), `Constants.lua` (the Druid row's key and comment), `tools/packs/druid.lua` (`spec`)
- Test: `Forever/spec/druid_spec.lua` (`TALENTS`, its count, the pseudo-spec case)
- Not in the repository: `/home/zack/.claude/jobs/080a308e/tmp/druid/export/{talents.txt,spells.txt,talents_block.lua,block.txt,reconcile.md}`

**Interfaces:**
- Consumes: the export; the Warrior's dump scripts `/home/zack/.claude/jobs/080a308e/tmp/warrior/export/{t.lua,dump.lua}`.
- Produces: the live `RegisterTalents`; `DRUID_SPEC = ID`; the pack strings for `ID`.

- [ ] **Step 1: Dump the export**

```bash
X=/home/zack/.claude/jobs/080a308e/tmp/druid/export
lua5.1 /home/zack/.claude/jobs/080a308e/tmp/warrior/export/t.lua $X/ForeverProbe.lua > $X/talents.txt
lua5.1 /home/zack/.claude/jobs/080a308e/tmp/warrior/export/dump.lua $X/ForeverProbe.lua > $X/spells.txt
head -2 $X/talents.txt; grep -c '^N' $X/talents.txt
```

Expected: `cfg <configID> <trees>`, a `TREE` line, and the node count (one line per node entry).

- [ ] **Step 2: Generate the talent block**

Write `/home/zack/.claude/jobs/080a308e/tmp/druid/export/talents_block.lua` (run once against the Warrior's export and `Forever/Classes/Warrior.lua` while this plan was written: 52 nodes, every key mapped, nothing gone):

```lua
-- talents_block.lua: the Druid's RegisterTalents block from a ForeverProbe export's node dump (t.lua's talents.txt).
-- Usage, from the worktree root: lua5.1 talents_block.lua talents.txt Forever/Classes/Druid.lua
-- Keys: the class file's own key for a node whose spell it already registers, else the node's name in snake_case.
-- Prints the block (nodes by column, then row) and, as comments, the registered keys the export no longer has.
local dump, classFile = arg[1], arg[2]
local known = {} -- rank 1's spell -> the key the class file registers
for line in io.lines(classFile) do
    local key, spell = line:match("^%s+([%w_]+)%s*= { 0, (%d+), %d+ },")
    if key then
        known[tonumber(spell)] = key
    end
end
local nodes, seen = {}, {}
for line in io.lines(dump) do
    local x, y, max, spell, name = line:match("^N%d+ pos=(%-?%d+),(%-?%d+) cur=%S+ max=(%d+) .- spell=(%d+) name==?(.-) |")
    if x and not seen[spell] then
        seen[spell] = true
        spell = tonumber(spell)
        local key = known[spell] or name:lower():gsub("'", ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
        nodes[#nodes + 1] = { x = tonumber(x), y = tonumber(y), key = key, spell = spell, max = tonumber(max), new = not known[spell] }
        known[spell] = nil
    end
end
table.sort(nodes, function(a, b)
    if a.x ~= b.x then
        return a.x < b.x
    end
    return a.y < b.y
end)
local width = 0
for _, n in ipairs(nodes) do
    width = math.max(width, #n.key)
end
print(("-- %d nodes"):format(#nodes))
local col
for _, n in ipairs(nodes) do
    if n.x ~= col then
        col = n.x
        print(("    -- column x=%d"):format(col))
    end
    print(("    %s = { 0, %d, %d },%s"):format(n.key .. (" "):rep(width - #n.key), n.spell, n.max, n.new and " -- Forever-only" or ""))
end
for spell, key in pairs(known) do
    print(("-- gone from the tree: %s (%d)"):format(key, spell))
end
```

Run: `lua5.1 $X/talents_block.lua $X/talents.txt Forever/Classes/Druid.lua > $X/block.txt; head -1 $X/block.txt; grep -c 'Forever-only' $X/block.txt; grep '^-- gone' $X/block.txt`
Expected: `-- <n> nodes`, the count of nodes this file did not register, and one `-- gone from the tree: <key> (<spell>)` line per registered talent the export no longer has (the spec expects Tiger's Fury-era removals and King of the Jungle among the 47; Furor and Insect Swarm moved, not gone, when their spells match).

Write `$X/reconcile.md`: one table of the export's nodes (key, definition spell, max rank, new / kept / max rank changed against the 47), the gone keys with each one's readers (`grep -n "talent\.<key>\b" Forever/Classes/Druid.lua tools/packs/druid.lua`) and the decision for each (drop the term; or the same talent under another spell: keep the key, take the export's spell), and the max-rank changes the spec names (Shredding Attacks, Sharpened Claws, Feral Instinct, Thick Hide).

- [ ] **Step 3: Pin the export in the spec (red)**

In `Forever/spec/druid_spec.lua`: replace the `TALENTS` table's body with the export's nodes (`key = { spell, max }`, one per line of `block.txt`, the reconciled keys), change its comment to "the live tree's nodes (ForeverProbe export, client 1.60.1.<build>, <date>)", and change the count in "registers the DB2's 47 talent nodes ..." to `{ n, n }` with the case's name "registers the live talent tree's n nodes with their definition spells and max ranks, and no rank aliases"; then the pseudo-spec (`ID` is Task 7's read):

```bash
ID=<the spec ID Task 7 read>
sed -i "s/assert.are.equal(1499, w.specID)/assert.are.equal($ID, w.specID)/" Forever/spec/druid_spec.lua
sed -i "s/as a placeholder until checkpoint Q1, and the settings/as the client reports it (checkpoint Q1), and the settings/" Forever/spec/druid_spec.lua
```

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `263 successes / 2 failures / 0 errors` (the talents case and the pseudo-spec case), or one more failure per other case that names a talent key the export renamed.

- [ ] **Step 4: Apply the export (green)**

1. `Forever/Classes/Druid.lua`: replace `RegisterTalents`' body with `block.txt`'s lines, grouped under `-- Balance (n)`, `-- Feral Combat (n)`, `-- Restoration (n)` by the columns the pane shows (the block's `-- column x=` comments, replaced), each Forever-only key commented as the Warrior's are ("Forever-only; <effect> unmodelled" where nothing reads it); replace the comment above it with "Talents: { node (unused on Forever), the definition spell, max rank }: the n nodes of Forever's live tree (a ForeverProbe export of the client, 1.60.1.<build>, <date>) ... no rank aliases." Apply `reconcile.md`'s reader decisions (a dropped term keeps its ability's KIT cost at rank 0, so the KIT case stays green).
2. `DRUID_SPEC` and the Constants row's key:

   ```bash
   sed -i "s/^local DRUID_SPEC = 1499\$/local DRUID_SPEC = $ID/" Forever/Classes/Druid.lua
   sed -i "s/^-- The pseudo-spec the client reports for a Druid (Constants.lua's row). A placeholder until checkpoint Q1 reads it.\$/-- The pseudo-spec the client reports for a Druid (Constants.lua's row), read at checkpoint Q1./" Forever/Classes/Druid.lua
   sed -i "s/^    \[1499\] = { -- Forever Druid pseudo-spec (Forever\/Classes\/Druid.lua's DRUID_SPEC): a placeholder until the client's\$/    [$ID] = { -- Forever Druid pseudo-spec (Forever\/Classes\/Druid.lua's DRUID_SPEC), read in game (checkpoint Q1)/" Constants.lua
   sed -i "s/^        key = \"druid\", -- ID is read in game (the Druid plan's checkpoint Q1)\$/        key = \"druid\",/" Constants.lua
   grep -n "DRUID_SPEC = \|\[$ID\] = \|key = \"druid\"" Forever/Classes/Druid.lua Constants.lua
   ```

   Expected: three lines (`local DRUID_SPEC = ID`, `[ID] = { -- Forever Druid ...`, `key = "druid",`).
3. `tools/packs/druid.lua`: `sed -i "s/spec = 1499, packs/spec = $ID, packs/" tools/packs/druid.lua`; then replace the three `spec:RegisterPack( ... )` lines with the new strings:

```bash
lua5.1 tools/make_pack.lua druid > /tmp/druid_packs.txt
python3 -I - <<'EOF'
p = "Forever/Classes/Druid.lua"
lines = open(p).read().split("\n")
new = open("/tmp/druid_packs.txt").read().split("\n")[:3]
for i, l in enumerate(lines):
    for k, name in enumerate(("Feral", "Guardian", "Balance")):
        if l.startswith('spec:RegisterPack( "%s", ' % name):
            lines[i] = 'spec:RegisterPack( "%s", 20261015, [[%s]] )' % (name, new[k])
open(p, "w").write("\n".join(lines))
EOF
```

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `265 successes / 0 failures / 0 errors`.

Run: `grep -c 'now = function' Forever/Classes/Druid.lua; grep -o 'talent\.[a-z_]*' Forever/Classes/Druid.lua tools/packs/druid.lua | sort -u`
Expected: `33`, and only keys `RegisterTalents` now registers (the "registers every aura ..." and "names only registered ... talents" cases check the rest).

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [265 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 87 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 54 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Classes/Druid.lua Forever/spec/druid_spec.lua Constants.lua tools/packs/druid.lua
git commit -m "feat(forever): the Druid's live talent tree and pseudo-spec from the ForeverProbe export (checkpoint Q1)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-druid`

---

### Task 9: CHECKPOINT B: the Druid in game (Q2-Q16)

No code unless an answer calls for it. The user plays the Druid at a training dummy (Q3, Q5, Q9, Q14, Q16 out of combat), ForeverProbe loaded, the client on the branch Task 8 pushed (`git -C ~/src/hekili checkout --detach forever-druid`, then `/reload`: no new files since Task 7's restart). First: `/run VSCopy(tostring(Hekili.State.spec.id),Hekili.State.spec.key)` reads `ID druid`; `/hekili priority Feral`.

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin forever-druid
git -C ~/src/hekili checkout --detach forever-druid
```

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, and report each answer**

| # | Question | Line(s) | Answer → action (each action its own commit with the verification block; a changed value also changes its KIT row) |
|---|---|---|---|
| Q2 | **Form read in combat** | `/run for i=1,GetNumShapeshiftForms() do VSCopy(i,GetShapeshiftFormInfo(i)) end`, then in each form in combat `/run VSCopy(GetShapeshiftForm(),pcall(C_UnitAuras.GetPlayerAuraBySpellID,768))` | plain form index → none (§3 stands); secret → `reset_precast` infers Cat/Bear from the usability read (Claw/Maul unusable for a non-power reason = not in that form), TDF's tracker: report first, it is a design change |
| Q3 | **Energy regen and Furor** | in Cat out of combat `/run VSCopy(GetTime(),GetPowerRegenForPowerType(3))` now and every 20 s for 2 min; then leave Cat at a known energy (the bar), wait 5 s, shift back and read the bar | 10 flat → none; rises 25% → an aura- or talent-gated regen entry for Feral Dedication; ticks → Classic's tick model back; Furor's energy matches 20%/rank + 10/s out → Cat Form's `now` gains it (leave time and energy as file-level upvalues written by the other forms' `now`) |
| Q4 | **Costs with talents; Shifting Power's cooldown** | `/run for _,i in ipairs({5221,1082,1822,1079,22568,6807,779,407995,414644,1322605}) do local c=C_Spell.GetSpellPowerCost(i) c=c and c[1] VSCopy(i,c and c.type,c and c.minCost) end`; after Shifting Power `/run local c=C_Spell.GetSpellCooldown(1322605) VSCopy(c.duration)` | equal to `spend` at the character's ranks → none; different → that ability's per-rank reduction; cooldown ≠ 16 - 4 x rank → D5's formula |
| Q5 | **Mana: max, regen, five-second rule** | `/run VSCopy(UnitPowerMax("player",0),GetPowerRegenForPowerType(0),GetManaRegen())` out of combat, again right after a cast; then `/run VSCopy(Hekili.VirtualState.Snapshot():match("resource MANA[^\n]+"))` | plain maximum and the Snapshot's `max=` equal → none (Task 1's costs and rest use it); secret → a `max` in a mana meta table from the reported value (a function returning it), which the costs and rest then use; the regen shape recorded for a Balance follow-up |
| Q6 | **Clearcasting visibility and coverage** | when it procs in combat: `/run VSCopy(pcall(C_UnitAuras.GetPlayerAuraBySpellID,16870))`; below 60 energy `/run VSCopy(C_Spell.IsSpellUsable(5221))`; with it up in Bear at 0 rage: `/run VSCopy(C_Spell.IsSpellUsable(407995),C_Spell.IsSpellUsable(99))` | readable → none; secret and usable below cost → recorded for the follow-up tracker (spec §7 known limit); Primal Bite or Demoralizing Roar usable at 0 rage → add its rank-1 ID (407995, 99) to `spells` (the DB2 masks already match both) |
| Q7 | **Faerie Fire in forms** | in Bear: `/run local c=C_Spell.GetSpellCooldown(9907) VSCopy(c.startTime,c.duration,C_Spell.IsSpellUsable(9907))`; out of combat after casting on a dummy `/run VSCopy(C_UnitAuras.GetAuraDataByIndex("target",1,"HARMFUL").spellId)` | free and 6 s → none; else `spend`/`cooldown` from the reads; debuff 1288561 → add it to the `faerie_fire` aura's `copy` |
| Q8 | **Bear swing rage** | in Bear on a dummy `/run VSCopy(UnitAttackSpeed("player"))`, then before and after 10 swings `/run VSCopy(format("%.2f",Hekili.VirtualState.Power(1,GetTime()).est))` and `/run VSCopy(Hekili.VirtualState.Snapshot():match("resource RAGE[^\n]+"))`, comparing with the bar | ~8.65 a swing → none; ~11.25 → `BEAR_RAGE_RATE = 4.5`; other → the measured rate per second of swing; `scale=` far from 1.00 after the fight → report |
| Q9 | **Bear rage decay and the shift's rage** | in Bear out of combat `/run VSCopy(GetPowerRegenForPowerType(1))` (Warrior -12.499); shift out and back with rage up and read the bar | -12.5 → none; else `decay` from the read; rage kept on a shift → Bear Form's `now` and `swap_form` stop spending it |
| Q10 | **Combo points** | at 3 CP in combat `/run VSCopy(GetComboPoints("player","target"),UnitPower("player",4))`, again after `/targetlasttarget`, after the target dies, after a dodged Rip | both plain → none; `UnitPower(4)` secret → **stop and report** (a Power source change, outside the class file); a missed finisher spends them → the miss handler also zeroes them in the sim |
| Q11 | **"Must be behind" error** | `/run local f=CreateFrame("Frame") f:RegisterEvent("UI_ERROR_MESSAGE") f:SetScript("OnEvent",function(_,e,a,b) VSCopy(a,b) end)`, then Shred from the front | the message type `T` → `NOT_BEHIND_ERRORS = { [ T ] = true }` in the class file |
| Q12 | **Shredding Attacks on Lacerate** | with 1 point: `/run local c=C_Spell.GetSpellPowerCost(414644) VSCopy(c and c[1] and c[1].minCost)` | 9 → none (-6 a rank); 14 → -1 a rank |
| Q13 | **Maul queue; Frenzied Regeneration's cooldown** | right after pressing Maul in combat `/run VSCopy(C_Spell.IsCurrentSpell(6807))`; after Frenzied Regeneration `/run local c=C_Spell.GetSpellCooldown(22842) VSCopy(c.startTime,c.duration)` | true → none; secret → Maul's `usable` falls back to none (the client refuses a double queue); duration ≠ 180 → `cooldown` and its KIT row |
| Q14 | **Race and racials** | `/run VSCopy(UnitRace("player"))` and `/run VSCopy(IsSpellKnown(1259799),IsSpellKnown(1259918),IsSpellKnown(20580),IsSpellKnown(20549),IsSpellKnown(20554))` | `NightElf` or `Tauren` with its racial known → none; another token, or the racial unknown → fix `NewRace`'s token or report; a Troll Druid knowing 20554 → none (stock) |
| Q15 | **Form gates per form** (the Warrior's Q1) | in each form `/run VSCopy(GetShapeshiftForm(),C_Spell.IsSpellUsable(5221),C_Spell.IsSpellUsable(6807),C_Spell.IsSpellUsable(5176),C_Spell.IsSpellUsable(1126),C_Spell.IsSpellUsable(770))` | as §3 → none; an ability usable in more forms → its `buff` becomes a function returning the current form's aura, or the gate goes |
| Q16 | **What exists at the cap** | `/run VSCopy(IsSpellKnown(407995),IsSpellKnown(1322605),IsSpellKnown(417141),IsSpellKnown(414644),IsSpellKnown(408255),IsSpellKnown(417157),IsSpellKnown(407988),IsSpellKnown(414924))` | rune spells (417157, 407988, 414924) false → none; true → report (a scope question, not this plan) |

Also recorded, in Feral at the dummy for a minute: any recommended ability the client refuses; one Rip cycle (Shred held for Rip at 5 combo points, Rip recommended as it falls off); then `/run VSCopy(Hekili.VirtualState.Snapshot():match("errors=%d+ now=%d+"))` (expected `errors=0` and `now=` growing) and `/run local d=Hekili.State.debuff VSCopy(tostring(d.rip.up),tostring(d.rake.up),Hekili.State.combo_points.current)` right after a Rip and a Rake (expected `true true` and the bar's combo points). `errors=` above 0 → report the Snapshot's drain line `error=` (a `now` raised: the named ability's `now` is wrong).

Known limits (say them with the results): Clearcasting unseen in combat (spec §7: a covered ability can read usable below its cost; the next rung corrects it); Furor's energy on entering Cat (Q3); rage from damage taken, crits, Blood Frenzy and Natural Reaction (§2.3, absorbed by the swing-scale calibration); a missed bleed stays in the belief until its modelled expiry (the simulation drops it at the next reset); mana costs are fractions of maximum, not base, mana (gear Intellect overstates them, Q5).

Fix what the user reports, then repeat the affected items. Continue only when the user confirms. Then `git push origin forever-druid`. When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

**1. Coverage of the spec**

| Requirement | Where |
|---|---|
| §0.1 a cost below 1 is that fraction of the maximum, in the ladder, the cost step and under `pct` | Task 1 (`I.BaseCostOf`; `resources_spec` 55/660/330 cases) |
| §0.2 a regenerating resource rests at its maximum, seeds at its declared maximum, rises with a plain maximum read; rage untouched; energy still 100 | Task 1 (`setMax`, the adapter's flag; the mana, rage and energy cases) |
| §0.3 a swing entry gated on `aura`; `SwingPerSecond` and the ladder pin with it; no gate pays as before; zero allocation; `adapter_spec` forwards `rest` and `swingAura` | Task 1 (the swing-gate describe; `adapter_spec`) |
| D1 `spec:RegisterCostMod` in `Classes.lua` with the race object's signature, into the list both layers read | Task 2 |
| §8 make_pack per class, default warrior, the Warrior's strings byte-identical, `( "lists", "druid" )` | Task 3 (Step 4 `cmp`), Task 5 |
| §1 one pseudo-spec `DRUID_SPEC` (1499 until Q1), its Constants row, the TOC, `.luacheckrc` | Task 4; Task 8 (the read ID) |
| §2 Energy (no regen model, no decay), Combo Points (no max), Rage (bear-gated swing entry with `stop`, Enrage 2/s, decay 1.25), Mana (no max), in Classic's order | Task 4 cases 9-10 |
| §3 forms from the shapeshift read (Dire Bear -> `bear_form`), the aliases, the gates, the shift in `now` and `handler` | Task 4 cases 3, 7, 8 |
| §4 the kit (44 abilities, KIT pinned against a DB2 re-read), `now` on 33 with constants shared, Maul on the next swing, the misses from the combat log | Task 4 (Step 0; cases 1, 6, 12) |
| §5 auras | Task 4 case 5 |
| §6 the 47 DB2 nodes plus three placeholders now; the export as its own commit after Q1 (D3) | Task 4 case 4; Task 8 |
| §7 Clearcasting through `spec:RegisterCostMod`, the covered rank-1 IDs, no `spend` mentions it, the free cast takes the charge | Task 4 case 11 and the strict-context case |
| §8 `excess_e`, `shred_ok`, the not-behind window, the eleven settings, Feral default and Guardian/Balance provisional (D2) | Task 4 cases 12-13, Task 5 |
| §9 Night Elf's Elune's Light, inert for other races | Task 6 (and a Tauren War Stomp file, per the controller's brief) |
| §10 the `now` functions run in Now.lua's strict context | Task 4's "Forever Druid in VirtualState's now context" describe (every `now`, a sequence, Clearcasting, allocation) |
| §11 Q1 first with the 1491 stop rule; Q2-Q16 answer → action; every line VSCopy and under 255 characters | Tasks 7 and 9 (lines checked by script: 31 lines, the longest 181) |
| Rulings D4 (3.46 x 2.5 s) and D5 (16 - 4 x rank) | Task 4 cases 2 and 9 |

**2. Placeholder scan:** no "TBD", "TODO", "implement later" or "similar to Task N"; Tasks 1-6 are `git apply` patches generated by the replay and every command has its replay output. Task 8's values (the export's nodes, the spec ID) exist only after Task 7: its steps are the exact commands and edits, its generator script is given in full and was run, and its expected counts follow from the replay's 265.

**3. Names across tasks:** `I.res.restMax`, `I.res.swingAura`, `setMax`, `d.swingAura`, `rest` (boolean), `ns.RegisterCostMod`, `spec:RegisterCostMod`, `tools/packs/<class>.lua` (`date`, `spec`, `packs`), `DRUID_SPEC`, `swap_form`, `excess_e`, `shred_ok`, `ns.DruidNotBehindErrors`, `load_druid.load( vs )`/`env`/`run`, `w.resources`, `w.order`, `w.costMods`, `w.ns`, the pack names `Feral`/`Guardian`/`Balance` and the pack date 20261015 are spelled the same in every task and checkpoint line.

**4. Review Focus:** each of the six lines has its pinned test in the owning task (Tasks 1-5).

**Concerns for the orchestrator:** (a) The DB2 mask query for Clearcasting (in the class file's comment) also matches Primal Bite and Demoralizing Roar, which the spec's §7 lists as "unlisted, absent = not covered (Q6)"; the plan follows the spec and Q6's action adds them. (b) Task 6 adds `Forever/Races/Tauren.lua` (War Stomp) per the controller's brief; the spec's §9 says "Tauren: no file" because War Stomp has no rotation line. (c) The checkpoint is split: Task 7 (Q1) before Task 8, Task 9 (Q2-Q16) after, because the Druid only activates in game once `DRUID_SPEC` is the client's ID. (d) The rage meta's `decay` is a function returning 1.25, not the spec's number: Hekili's `RegisterResource` setfenv's every meta field. (e) Bear swing rage in the belief keeps paying after a Bear Form click-off in combat until the next shift or combat end (spec §2.3); Hekili's simulation drops it at once (`buff.bear_form` from the shapeshift read).
