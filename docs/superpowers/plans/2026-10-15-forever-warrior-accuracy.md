# Forever Warrior Accuracy Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Forever/Warrior.lua` match the live client (the ForeverProbe export of 2026-10-15: 52 talent nodes, Spearing Strike as a talent, Vanguard, Overpower's second power cost) and make the rage model accurate (Classic's damage-based rage per hit for both hands, Unbridled Wrath, Dual Wield Specialization, Anger Management).

**Architecture:** Two VirtualState changes and two class-file changes. VirtualState's resources family learns a second paying hand (each hand its own per-swing value, fed by the swing family's per-hand anchors) and drops the cost-ladder rung of an ability with two power costs (Overpower: rage plus a combo point); on the Warrior branch, its periodic regen entries (Warrior plan Task 1's aura-gated ones) learn an aura-less, combat-gated form with an optional talent gate, which the adapter forwards with the off hand's swing value. The class file registers the 52 live talents and replaces the readers of the 10 removed ones, gates Spearing Strike on its talent, Charge on Vanguard, Overpower on the plain usability read, and computes rage per hit per hand from VirtualState's out-of-combat `UnitDamage` cache and the player's level.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1 build 70374, interface 16001), busted, luacheck, lua-language-server, `lua5.1`/`luac5.1`, the `wowdb` CLI (Forever DB2 build 1.60.1.70338).

**Spec:** `docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md` (§3.6 `Track{}`, §4.3 polls, §6.1 resources, §6.5 the stat cache). The requirements are the rulings A1-A8 at the end of the Warrior ledger (`.superpowers/sdd/2026-10-15-forever-warrior-profile/progress.md`, final; A9 was withdrawn, see below) and the reconciliation of the live export against the class file (`/home/zack/.claude/jobs/080a308e/tmp/warrior/reconcile.md`, with `export/talents.txt`, `export/spells.txt`, `export/db2ranks.tsv` beside it). House style and the previous design: `docs/superpowers/plans/2026-10-15-forever-warrior-profile.md`.

## How this plan was checked

Every patch below was written and run before the plan was saved, on clones of the two worktrees at their current heads (`virtualstate-phase1` at `0d480aa7`, `forever-warrior-profile` at `b62beacf`): Task 1 on the Phase 1 clone, then that clone merged into the Warrior clone (clean: `Auto-merging` of `VirtualState/Families/Resources.lua` and `VirtualState/spec/resources_spec.lua`, no conflict), then Tasks 2 to 4 on the Warrior clone. Each spec patch was applied and run red, then the implementation patch and the whole verification block; the counts below are the replay's. A review round re-ran Tasks 1 to 4 after its fixes (the stat re-reads, the adapter's gates, the combat seed, the Focused Rage rule). Base counts: `virtualstate-phase1` 97 busted successes, luacheck 63 files; `forever-warrior-profile` 118 successes, luacheck 65 files; 43 loaded files for `tools/check_api_reads.sh` on both. The in-game checkpoint (Task 5) is the user's.

## Global Constraints

- Repository `~/src/hekili`. Two worktrees, both existing: `~/src/hekili/.claude/worktrees/virtualstate-phase1` (branch `virtualstate-phase1`, Task 1 only) and `~/src/hekili/.claude/worktrees/forever-warrior-profile` (branch `forever-warrior-profile`, Tasks 2-5). Two-branch rule: Phase 1 VirtualState code is committed on `virtualstate-phase1` and reaches the Warrior branch only by a merge (`git merge --no-edit virtualstate-phase1` in the Warrior worktree, Task 2 Step 1); the Warrior branch's own VirtualState code (Warrior plan Task 1's aura-gated regen, which never went to Phase 1) is extended on the Warrior branch (Task 2). Git from WSL only. After each task's green verification and clean review, push that task's branch (`git push origin virtualstate-phase1` or `git push origin forever-warrior-profile`); never push to `forever` or `classic`; never force-push; the only merge is Task 2 Step 1.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, naming the model that wrote the commit; an implementer on another model replaces `Claude Opus 5.5` with its own model's name.
- No LICENSE or README changes, in any repository. No changes to `archive/`.
- Taco Dog Forever is read only; clean-room direction: TDF mechanics may be ported into Hekili with credit in the file header (spec §13), Hekili code never flows into TDF.
- Secret safety (spec §4.5): no VirtualState code compares or does arithmetic on a client value without `issecretvalue()` first, none uses `a and b or c` on a possibly-secret value, no secret value leaves the sources or the facade. The class file reads directly only names outside `tools/api_inventory.txt` (`tools/check_api_reads.sh` enforces it): this plan adds `UnitLevel` (plain) and reads `UnitDamage` only through `ns.VirtualState.Stat` (the out-of-combat cache, plain numbers).
- Performance (spec §2): VirtualState accessors, the fold, Flush, the polls and the facade policies allocate nothing; arrays are built at `SpecChanged`. This plan's two-hand swing path and combat-gated regen path each have a 0-byte allocation case. The class file's swing values (`rageOf`) allocate nothing (multiple returns, arithmetic).
- TOC order (spec §9) is unchanged; no new files, no new TOC entries.
- Scope: nothing from the Phase 2 investigation or the Phase 3 event bus (the dodge event that will give Overpower its window belongs to a later "virtual event facade" plan), nothing in spec §14, no new VirtualState source, no SoD rune spells.
- Tools: `BUSTED=~/src/TacoDogForever/.lua/bin/busted`, `LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`, `LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server`, `lua5.1`, `luac5.1`. All commands run from the task's worktree root.
- Every task ends with the verification block (busted, luacheck, `tools/check_api_reads.sh`, the api-inventory diff, LuaLS `--checklevel=Error`, `luac5.1 -p` on the touched Lua files), written out per task with its expected results, then a commit.
- Style: VirtualState files and specs use the TDF layout (4 spaces, no spaces inside parentheses, 120 columns); `Forever/Warrior.lua` keeps Hekili's style (spaces inside parentheses); Forever specs use the TDF layout.
- The user runs the game. The **CHECKPOINT** step stops execution: the orchestrator points the client's checkout at the branch (`git -C ~/src/hekili checkout --detach forever-warrior-profile`), asks the user to run the exact lines, and waits. Every in-game line prints through `VSCopy(` (ForeverProbe's copy box) and is under 255 characters. When the session ends, `git -C ~/src/hekili checkout forever`.

## Rulings applied

| Ruling | What this plan does | Task |
|---|---|---|
| A1 talents | `RegisterTalents` = the 52 live nodes with the export's definition spells and max ranks (Two-Handed Weapon Specialization 3, Improved Slam 2, Defiance 3; Iron Will 12962 and Defiance 12792 as the live nodes define them); 9 Forever-only keys (`weaponmaster`, `spearing_strike`, `bloodthrill`, `raging_blows`, `lingering_rage`, `gore_drinker`, `focused_rage`, `vanguard`, `master_of_defense`; `furious_precision` was already there); the 10 removed Classic talents dropped. Readers: Cleave's Improved Cleave → Raging Blows (-3, also on Whirlwind); Improved Shield Block (Shield Block's duration) and Improved Taunt (Taunt's cooldown) → deleted (no Forever talent does that job); Focused Rage -3 a rank on the offensive abilities. Rank aliases: **none**. The export's owned multi-rank nodes (Unbridled Wrath 5/5, Cruelty 5/5, Dual Wield Specialization 3/5, Blood Craze 1/3, Furious Precision 3/3) each report their rank 1 spell at their current rank, and every node reports one definition spell; the "aliases used" seen at the last checkpoint was Iron Will and Defiance reaching 12300/12303 through the DB2 aliases 12962/12792, which are now registered directly. The `Track{ talents }` call is deleted. | 3 |
| A2 Spearing Strike | `talent = "spearing_strike"` on the ability (node 1310222, max 1); comments fixed. | 3 |
| A3 Vanguard | Charge's `buff` becomes a function: `defensive_stance` while in it with Vanguard, else `battle_stance`. | 3 |
| A4 rage | VirtualState: two paying hands per resource (Phase 1), combat-gated periodic entries with a talent gate (Warrior branch). Class file: `mainhand` and `offhand` entries whose value is vanilla's formula, 7.5 x average damage / c(level), from `VS.Stat("UnitDamage")` and `UnitLevel("player")` (TBC's weapon-speed term behind `RAGE_SPEED_TERM = 0`, ruling on the planner's concern), DWS +10% off-hand a rank, Unbridled Wrath +0.12 a rank both hands; `anger_management` as a combat-gated entry (1 every 3 s). Hekili's own forecast already handles `swing = "offhand"` entries (State.lua:1214-1225 gates them on `swings.offhand_speed > 0`) and `talent` gates. `UnitDamage`'s off-hand range is the pane's (Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua:974-991, through `PaperDollFrame_GetDamage` :865-901, where the shown min/max are UnitDamage's returns 3-4 as is, with the off-hand penalty applied by the client), so vanilla's off-hand halving is already in the damage and is not applied again. | 1, 2, 4 |
| A5 multi-cost | The Spellbook source records `multiCost` from `GetSpellPowerCost`'s entry count out of combat (where it already reads the cost); the Usable handler takes no rung from such an ability. Its cast-success rung stays (a cast proves the rage). Overpower's rage spend stays. Snapshot prints `multi=`. | 1 |
| A6 housekeeping | Dead `overpower_enabled`/`overpower_threshold` settings deleted (no pack names them); `WALK[u]` built at OnBuild for every tracked unit; a complete walk notes `readable`; the GCD learned bound `[1.0, 2.0)`; the header's build note (DB2 70338, client 70374); the Warrior plan's Task 4 note "superseded by f728e30f". | 1, 4 |
| A7 checkpoint | One checkpoint (Task 5) with the listed lines and the known limits. | 5 |
| A8 Overpower | `usable` = the plain `C_Spell.IsSpellUsable` of the known rank, strictly `true` (not "short": without a dodge the combo-point cost reads as insufficient power), with the comment "interim until the virtual event facade delivers the dodge event"; out of the ladder (A5); no stance-swap entries. | 3 |
| A9 (withdrawn) | Withdrawn by the user in all its versions: no window, `onUsable` or usable-since mechanism in VirtualState or the class file. The dodge event comes later from the virtual event facade plan; Overpower then gets Classic's `applyBuff( "overpower_ready", 5 )`. | — |

## Review Focus

1. **A character with no off-hand weapon, or a two-hander** (most Arms warriors): no off-hand rage may be believed. VirtualState pays a hand-2 swing only when the resource has an off-hand value, and Hekili's forecast skips the `offhand` entry while `offhand_speed` is 0. Tests: Task 1 `resources_spec` "pays nothing for an off-hand swing when only the main hand pays"; Task 4 `warrior_spec` "falls back to the weapon-speed rate before the weapon damage is cached" (`offhand` value 0 without an off hand).
2. **The weapon damage not cached yet** (a `/reload` in combat, a secret read out of combat): rage per hit must not drop to the hit-factor term alone. `rageOf` falls back to the old weapon-speed rate. Test: Task 4 "falls back to the weapon-speed rate …".
3. **Overpower without a dodge** reads "short" (the combo-point cost), at any rage: it must give no rage rung and must not be recommended. Tests: Task 1 `facts_spec` "takes no rung from an ability with a second power cost"; Task 3 `warrior_spec` "recommends Overpower only while the client calls it usable, not when it is short of its combo point".
4. **Anger Management untaken, or out of combat**: the periodic entry must credit nothing. Test: Task 2 `resources_spec` "credits a plain periodic entry only in combat, from the combat start, and only with its talent".
5. **The fold and `VS.Power`/`VS.Regen` with two hands or a combat entry** run on every swing and every facade read: they must allocate nothing. Tests: Task 1 "allocates nothing paying and projecting two hands"; Task 2 the allocation check inside the combat-entry case.

Named, not test-pinned: the formula ignores misses, dodges, parries and crits (every white swing counts as an average hit) and uses the damage before armour (vanilla's rage comes from damage dealt, so armoured targets read high; the training dummy barely shows it); VirtualState's swing-scale calibration absorbs a steady bias, Hekili's own forecast does not. Above the highest usable rung (Whirlwind 25 rage where known, else the highest-cost known spender) the belief has no rung to correct it; the checkpoint measures both. The weapon damage is cached out of combat only (it is secret in combat): a weapon swap or a level-up in combat leaves it stale until combat ends. `multiCost` is read out of combat only and resets at every build, so a spec change or `/reload` in combat puts Overpower back on the ladder until combat ends (a secret second cost entry also reads as single-cost), as `readCost` already does.

## File structure

```
VirtualState/Families/Resources.lua    Task 1  two paying hands (swingOff, SwingValue(r, hand), SwingPerSecond); no rung from a multi-cost ability
                                       Task 2  periodic entries without an aura (combat-gated) and with a talent gate
VirtualState/Families/Casts.lua        Task 1  multiCost per ability, Snapshot `multi=`, GCD bound [1.0, 2.0)
VirtualState/Sources/Spellbook.lua     Task 1  multiCost from GetSpellPowerCost's entry count (out of combat)
VirtualState/Sources/Auras.lua         Task 1  WALK names per tracked unit; a complete walk notes readable
VirtualState/Adapter.lua               Task 2  forwards the off hand's swing value and aura-less periodic entries
VirtualState/spec/*                    Tasks 1-2  resources, casts, facts, auras, adapter cases; fake_api per-spell costs
Forever/Warrior.lua                    Tasks 3-4  talents and readers, Vanguard, Spearing Strike, Overpower; rage per hit, Anger Management, settings
Forever/spec/warrior_spec.lua, helpers/load_warrior.lua   Tasks 3-4  the cases; the loader fakes UnitLevel and VS.Stat
.luacheckrc                            Task 3  `offensive_cost` in the Warrior's state names
docs/superpowers/plans/2026-10-15-forever-warrior-profile.md   Task 4  one line: its Task 4 code blocks superseded by f728e30f
```

The packs (`tools/make_pack.lua`) do not change: no priority names a removed talent, ability or setting (the spec "writes priorities that name only registered …" stays green in Tasks 3 and 4), so there is no pack task and no version bump.

## Order and checkpoint

Task 1 (Phase 1 worktree), then Task 2 (its Step 1 merges Phase 1 into the Warrior branch), Task 3, Task 4, then Task 5, the one in-game CHECKPOINT. Deliberately not built (a review should not flag them): per-rank numbers the DB2 lacks (Bloodthrill's proc chance, Lingering Rage, Master of Defense, Furious Precision's off-hand hit term, Improved Slam's cast and cooldown); Gore Drinker (health is secret); Weaponmaster (damage only); an off-hand hit table (Furious Precision) in the rage formula; Lingering Rage's and Anger Management's out-of-combat decay changes.

---

### Task 1: Two paying hands, no rung from a multi-cost ability, and the Phase 1 housekeeping (virtualstate-phase1)

Work in `~/src/hekili/.claude/worktrees/virtualstate-phase1` (branch `virtualstate-phase1`, HEAD `0d480aa7`).

The resources family models one paying hand per resource today: `R.swing[r]` (1 main, 2 off) and one per-swing value, and the adapter takes the first `swing` entry (`VirtualState/Adapter.lua` buildDef). A dual-wielding Fury warrior's off-hand swings bring rage that no model pays (Warrior ledger, Task 5 run 2, Q9). This task adds an off-hand value per resource slot, `R.swingOff[r]` (0: none; a number or the model's state-bound function, like `swingValue`), paid at each landed hand-2 swing (the swing family's hand 2 anchor already produces them: `Sources/Swing.lua` posts `Obs.Swing` with `a = 2`), never taken by a queued on-next-swing strike (only the main hand's swing is). Calibration and `VS.Regen` measure against the sum of both hands' value per second (`I.SwingPerSecond`), and the ladder's crossing pin is one step of the larger hand wide. The adapter does not forward the off hand yet: on Phase 1 nothing registers one, and the adapter's resource loop differs on the Warrior branch, so Task 2 does that there.

The stat cache (`VS.Stat`, Sources/Player.lua) is read at login, at combat end and on PLAYER_EQUIPMENT_CHANGED only, so an out-of-combat attack-power or level change (Battle Shout before a pull, a level-up) left Task 4's weapon damage stale. The source now also re-reads on `UNIT_DAMAGE` and `UNIT_ATTACK_POWER` for the player and on `PLAYER_LEVEL_UP`, through the same `readStats` (which skips while in combat, where the stats are secret; allocates nothing).

A5: Overpower costs rage and a combo point (`GetSpellPowerCost(7384)` returns two entries, RAGE 5 and COMBO_POINTS 5/min 1, reconcile §A). Without a dodge `IsSpellUsable` answers "short" at any rage, so its ladder rung pins rage below 5 wrongly. The Spellbook source, which already reads each spender's cost out of combat, now records whether the cost list has a second entry (`A.multiCost[a]`), and the Usable handler takes no rung from such an ability. Its cast-success rung stays: a successful cast proves the rage.

A6 (Phase 1 items): `Sources/Auras.lua`'s walk status names come from the built unit list (a third tracked unit, e.g. `focus` from another file's `Track`, gets `aura walk focus` instead of `nil`); a complete walk notes `readable` even when no tracked aura is up (a clean walk on a bare player read "unknown" before); the GCD learned bound is `[1.0, 2.0)`: a 2.0 s falling edge is two chained 1.0 s GCDs, not one.

**Files:**
- Modify: `VirtualState/Families/Resources.lua` (header comment of `R` :21-22, `R` :29-30, OnBuild :81-82, `I.SwingValue` :101-108, `calibrate` :125-131, the Usable handler :218-224 and its crossing step :234-235, the Swing handler :269-278, `VS.Regen` :353-360)
- Modify: `VirtualState/Families/Casts.lua` (`A` :23, `GCD_MIN, GCD_MAX` :41, OnBuild :77, the GCD edge :163, Snapshot :342-349)
- Modify: `VirtualState/Sources/Spellbook.lua` (`resolve` :24-40)
- Modify: `VirtualState/Sources/Auras.lua` (`WALK` :19-20, OnBuild :26-28, after a complete walk :90)
- Modify: `VirtualState/Sources/Player.lua` (header :2-3; three handlers before `PLAYER_STARTED_MOVING` :134)
- Test: `VirtualState/spec/resources_spec.lua` (three cases in "a swing-paid resource", before "answers an untracked power type …"), `VirtualState/spec/casts_spec.lua` (the GCD case :56, a Snapshot case), `VirtualState/spec/facts_spec.lua` (a multi-cost case), `VirtualState/spec/auras_spec.lua` (a third-unit case), `VirtualState/spec/player_spec.lua` (a stat re-read case with an allocation check), `VirtualState/spec/helpers/fake_api.lua` (`ctl.costs`, per-spell `GetSpellPowerCost`)

**Interfaces:**
- Consumes: `I.SwingSpeedEst(h)` (Families/Swing.lua, hand 1 and 2), `Obs.Swing` with `a` = hand, `I.ab` (Families/Casts.lua), `def.resources[r]` (Phase 1 Task 4).
- Produces: `def.resources[r].swingOff` (read by the family: a number or a function of no meaningful argument, like `swingValue`; 0/nil: no off-hand pay); `I.res.swingOff[r]`; `I.SwingValue(r, hand)` (hand 2 → the off-hand value when the slot is main-hand paid; otherwise the paying hand's); `I.SwingPerSecond(r)` (the slot's model value per second of swinging, both hands); `I.ab.multiCost[a]` (boolean); Snapshot's `ability …` line gains ` multi=<true|false>`; the stat cache refreshes on `UNIT_DAMAGE`/`UNIT_ATTACK_POWER` (player) and `PLAYER_LEVEL_UP` out of combat; `ctl.costs[spellID]` in `fake_api` (a `GetSpellPowerCost` list).

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/auras_spec.lua b/VirtualState/spec/auras_spec.lua
index a85c79a0..2ca400ac 100644
--- a/VirtualState/spec/auras_spec.lua
+++ b/VirtualState/spec/auras_spec.lua
@@ -85,6 +85,21 @@ describe("auras", function()
         assert.are.equal("error", S.status["aura walk target"])
     end)
 
+    it("names a third unit's walk status, and notes a clean walk readable with no tracked aura up", function()
+        local api2, ctl2 = fake.new()
+        local ns2 = load.module()
+        local def = fs.def(fs.new(9))
+        def.units[3] = "focus"
+        ctl2.auras.focus = { HELPFUL = {}, HARMFUL = {} }
+        ctl2.exists.focus = true
+        ns2.VirtualStateInternal.Build(def, 1)
+        ns2.VirtualState.Start(api2)
+        ctl2.Fire("UNIT_AURA", "player") -- nothing on the player
+        ctl2.Fire("UNIT_AURA", "focus")
+        local status = ns2.VirtualStateInternal.Sources.status
+        assert.are.same({ "readable", "readable" }, { status["aura walk player"], status["aura walk focus"] })
+    end)
+
     it("stops at an entry whose spellId is secret, so a modelled debuff is not logged down", function()
         ctl.now = 10
         I.AuraModel(2, REND, 10, 25, 1, 10, Obs.CastSuccess, true)
diff --git a/VirtualState/spec/casts_spec.lua b/VirtualState/spec/casts_spec.lua
index 070c746a..b2a15b75 100644
--- a/VirtualState/spec/casts_spec.lua
+++ b/VirtualState/spec/casts_spec.lua
@@ -53,15 +53,23 @@ describe("casts and cooldowns", function()
         assert.are.equal(30, VS.CooldownLength(fs.REND))
     end)
 
-    it("learns a GCD only from a falling edge within [1.0, 2.0] s", function()
+    it("learns a GCD only from a falling edge within [1.0, 2.0) s", function()
         S.Direct(Obs.Cooldown, 100, 0, 1, 1)
         S.Direct(Obs.Cooldown, 101.4, 0, 0, 1)
         S.Direct(Obs.Cooldown, 110, 0, 1, 1)
         S.Direct(Obs.Cooldown, 114.38, 0, 0, 1) -- chained GCDs merged into one edge
-        I.Fold(114.4, false)
+        S.Direct(Obs.Cooldown, 120, 0, 1, 1)
+        S.Direct(Obs.Cooldown, 122, 0, 0, 1) -- exactly 2.0 s: two chained 1.0 s GCDs, not one
+        I.Fold(122.1, false)
         assert.is_true(math.abs(I.gcdLearned - 1.4) < 0.002) -- the earlier, plausible one stands
     end)
 
+    it("names an ability with a second power cost in Snapshot", function()
+        I.ab.multiCost[REND] = true
+        local line = "ability rend qid=772 cost=10 read=0 len=30.00 flag=-1 multi=true\n"
+        assert.is_truthy(VS.Snapshot():find(line, 1, true))
+    end)
+
     it("logs a Cooldown only on a plain flag edge, and the GCD's edges, on the urgent lane", function()
         h.forced = {}
         I.urgent = function(e)
diff --git a/VirtualState/spec/facts_spec.lua b/VirtualState/spec/facts_spec.lua
index bfa693da..e99aabdb 100644
--- a/VirtualState/spec/facts_spec.lua
+++ b/VirtualState/spec/facts_spec.lua
@@ -37,6 +37,19 @@ describe("facts and polls", function()
         assert.are.equal(10, r.lo) -- rend's rung; heroic strike's secret answer is no news
     end)
 
+    it("takes no rung from an ability with a second power cost", function()
+        ctl.costs[fs.REND] = { { type = 1, cost = 10 }, { type = 4, cost = 5, minCost = 1 } } -- rage + combo points
+        ctl.known[fs.REND] = true
+        ctl.Fire("SPELLS_CHANGED")
+        assert.are.same({ true, false }, { I.ab.multiCost[3], I.ab.multiCost[1] })
+        ctl.usable[fs.REND] = { false, true } -- "short": of rage or of the combo point?
+        drain(5)
+        assert.are.equal(100, VS.Power(fs.RAGE, 5).hi) -- no rung
+        ctl.usable[fs.REND] = { true, false }
+        drain(6)
+        assert.are.equal(0, VS.Power(fs.RAGE, 6).lo) -- nor from its usable answer
+    end)
+
     it("walks the talent tree into ranks by registered spell ID, and defers a walk in combat", function()
         ctl.traits = { config = 1, trees = { 7 }, nodeIDs = { 70 }, nodes = {}, defs = { [700] = 12286 } }
         ctl.traits.nodes[70] = { entryIDs = { 700 }, activeRank = 2 }
diff --git a/VirtualState/spec/helpers/fake_api.lua b/VirtualState/spec/helpers/fake_api.lua
index 0c4c7959..d0daabc8 100644
--- a/VirtualState/spec/helpers/fake_api.lua
+++ b/VirtualState/spec/helpers/fake_api.lua
@@ -36,6 +36,7 @@ function M.new()
         powerMax = {}, -- [powerType] = max
         regen = {}, -- [powerType] = { inactive, active }
         usable = {}, -- [spellID] = { ok, short }
+        costs = {}, -- [spellID] = GetSpellPowerCost's list (default: none)
         known = {}, -- [spellID] = true
         cooldown = {}, -- [spellID] = { isActive = bool, isOnGCD = bool, startTime = SECRET, duration = SECRET }
         current = {}, -- [spellID] = true while queued (IsCurrentSpell)
@@ -162,8 +163,8 @@ function M.new()
         IsCurrentSpell = function(id)
             return ctl.current[id] == true
         end,
-        GetSpellPowerCost = function()
-            return COSTS
+        GetSpellPowerCost = function(id)
+            return ctl.costs[id] or COSTS
         end,
         IsSpellInRange = function(id, unit)
             return ctl.inRange[unit] == true
diff --git a/VirtualState/spec/player_spec.lua b/VirtualState/spec/player_spec.lua
index 1b2ca7b9..ac716003 100644
--- a/VirtualState/spec/player_spec.lua
+++ b/VirtualState/spec/player_spec.lua
@@ -3,6 +3,7 @@
 local load = require("VirtualState.spec.helpers.load")
 local fake = require("VirtualState.spec.helpers.fake_api")
 local fs = require("VirtualState.spec.helpers.fake_spec")
+local alloc = require("VirtualState.spec.helpers.alloc")
 
 describe("player start", function()
     local VS, I, S, api
@@ -43,6 +44,38 @@ describe("player start", function()
         assert.are.same({ 7, "observed" }, { h.est, h.basis })
     end)
 
+    it("re-reads the stats out of combat when the weapon damage, attack power or level changes", function()
+        local ctl = api.ctl
+        local damage = { 40, 60, 15, 25, 0, 0, 1 }
+        api.UnitDamage = function()
+            return damage[1], damage[2], damage[3], damage[4], damage[5], damage[6], damage[7]
+        end
+        VS.Start(api)
+        assert.are.same({ 40, 60, 15, 25, 0, 0, 1 }, { VS.Stat("UnitDamage") })
+        damage[1], damage[2] = 44, 66 -- Battle Shout before a pull
+        ctl.Fire("UNIT_ATTACK_POWER", "player")
+        assert.are.same({ 44, 66, 15, 25, 0, 0, 1 }, { VS.Stat("UnitDamage") })
+        damage[1] = 50
+        ctl.Fire("UNIT_DAMAGE", "target") -- another unit: no read
+        assert.are.equal(44, (VS.Stat("UnitDamage")))
+        ctl.Fire("UNIT_DAMAGE", "player")
+        assert.are.equal(50, (VS.Stat("UnitDamage")))
+        damage[1] = 52
+        ctl.Fire("PLAYER_LEVEL_UP", 23)
+        assert.are.equal(52, (VS.Stat("UnitDamage")))
+        ctl.Fire("PLAYER_REGEN_DISABLED")
+        damage[1] = 70 -- a weapon swap in combat: secret then, so stale until combat ends
+        ctl.Fire("UNIT_DAMAGE", "player")
+        assert.are.equal(52, (VS.Stat("UnitDamage")))
+        ctl.Fire("PLAYER_REGEN_ENABLED")
+        assert.are.equal(70, (VS.Stat("UnitDamage")))
+        ctl.Fire("PLAYER_REGEN_DISABLED")
+        ctl.Fire("PLAYER_REGEN_ENABLED")
+        assert.are.equal(0, alloc.bytes(function()
+            ctl.Fire("UNIT_DAMAGE", "player")
+        end, 2000))
+    end)
+
     it("notes complete when every CR_* constant resolves", function()
         VS.Start(api)
         assert.equal("complete", S.status["stats CR_* constants"])
diff --git a/VirtualState/spec/resources_spec.lua b/VirtualState/spec/resources_spec.lua
index d5610919..cc856435 100644
--- a/VirtualState/spec/resources_spec.lua
+++ b/VirtualState/spec/resources_spec.lua
@@ -4,6 +4,7 @@
 local load = require("VirtualState.spec.helpers.load")
 local fake = require("VirtualState.spec.helpers.fake_api")
 local fs = require("VirtualState.spec.helpers.fake_spec")
+local alloc = require("VirtualState.spec.helpers.alloc")
 
 local ENERGY = 3
 
@@ -141,6 +142,43 @@ describe("resources", function()
             assert.are.equal(0, VS.Power(fs.RAGE, 6).lo)
         end)
 
+        it("pays nothing for an off-hand swing when only the main hand pays", function()
+            obs(Obs.Swing, 5, 2, 1.8, 1)
+            I.Fold(5, false)
+            assert.are.equal(0, VS.Power(fs.RAGE, 5).est)
+        end)
+
+        it("pays each hand its own value when both hands pay it, and calibrates against their sum", function()
+            local def = fs.def(fs.new(9))
+            def.resources[1].swingOff = 4.5
+            boot(def)
+            obs(Obs.Swing, 5, 1, 2.6, 1)
+            obs(Obs.Swing, 5.5, 2, 1.8, 1)
+            I.Fold(5.5, false)
+            assert.are.equal(13.5, VS.Power(fs.RAGE, 6).est)
+            within(9 / 2.6 + 4.5 / 1.8, I.SwingPerSecond(1))
+            within(9 / 2.6 + 4.5 / 1.8, VS.Regen(fs.RAGE, 6).est)
+            obs(Obs.Queued, 6, 2, 1) -- a queued strike takes the main hand's swing, not the off hand's
+            obs(Obs.Swing, 7.3, 2, 1.8, 1)
+            I.Fold(7.3, false)
+            assert.are.equal(18, VS.Power(fs.RAGE, 7.3).est)
+        end)
+
+        it("allocates nothing paying and projecting two hands", function()
+            local def = fs.def(fs.new(9))
+            def.resources[1].swingOff = 4.5
+            boot(def)
+            local t = 5
+            local bytes = alloc.bytes(function(i)
+                t = t + 0.1
+                obs(Obs.Swing, t, i % 2 + 1, 2, 1)
+                I.Fold(t, false)
+                VS.Power(fs.RAGE, t)
+                VS.Regen(fs.RAGE, t)
+            end, 2000)
+            assert.are.equal(0, bytes)
+        end)
+
         it("answers an untracked power type with the unknown record", function()
             local u = VS.Power(99, 1)
             assert.are.same({ 0, "unknown" }, { u.conf, u.basis })
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `98 successes / 4 failures / 2 errors`: failures in `auras_spec.lua @ 88` (the third unit's status is `nil`), `casts_spec.lua @ 56` (the 2.0 s edge is learned), `player_spec.lua @ 47` (no re-read on UNIT_ATTACK_POWER), `resources_spec.lua @ 151` (the off hand pays nothing); errors in `casts_spec.lua @ 67` and `facts_spec.lua @ 40` (`multiCost` is nil). The fifth new case ("pays nothing for an off-hand swing when only the main hand pays") and the allocation case already pass: they guard behaviour that must not change.

- [ ] **Step 3: Write the implementation**

Apply with `git apply`:

```diff
diff --git a/VirtualState/Families/Casts.lua b/VirtualState/Families/Casts.lua
index 94e2d7b6..97117b1f 100644
--- a/VirtualState/Families/Casts.lua
+++ b/VirtualState/Families/Casts.lua
@@ -21,6 +21,7 @@ local A = {
     slot = {},
     qid = {},
     readCost = {},
+    multiCost = {},
     ready0 = {},
     cdLen = {},
     castT = {},
@@ -38,7 +39,7 @@ A.bySpell = {}
 
 -- Unknown, not ready, ready (the plain isActive flag as last reported).
 local UNKNOWN, NOT, YES = -1, 0, 1
-local GCD_MIN, GCD_MAX = 1.0, 2.0 -- the plausible GCD lengths a falling edge may teach
+local GCD_MIN, GCD_MAX = 1.0, 2.0 -- the plausible GCD lengths a falling edge may teach: [1.0, 2.0)
 
 -- The cast or channel in progress (0: none), and the GCD fixed at its rising edge.
 I.castAb, I.castEnd, I.channel = 0, 0, false
@@ -74,7 +75,7 @@ I.OnBuild(function(def, now)
             A.bySpell[ids[k]] = a
         end
         A.slot[a] = def.abilitySlot[a]
-        A.qid[a], A.readCost[a] = ids[1], 0
+        A.qid[a], A.readCost[a], A.multiCost[a] = ids[1], 0, false
         A.ready0[a], A.cdLen[a], A.castT[a], A.flag[a] = 0, 0, 0, UNKNOWN
         A.charges0[a], A.next0[a] = maxCharges(a), 0
         A.queued[a], A.castStartT[a] = false, 0
@@ -160,7 +161,7 @@ I.On(Obs.Cooldown, function(o, t)
             I.Sample(gcd, "pinned", gcd.est, t, Obs.Cooldown)
         else
             local len = o.t - I.gcdStart
-            if I.gcdStart > 0 and len >= GCD_MIN and len <= GCD_MAX then -- chained GCDs merge into one long edge
+            if I.gcdStart > 0 and len >= GCD_MIN and len < GCD_MAX then -- chained GCDs merge into one long edge
                 I.gcdLearned = quantise(len)
             end
             I.gcdStart, I.gcdDur = 0, 0
@@ -339,13 +340,14 @@ I.OnSnapshot(function(out, now)
         VS.Cooldown(A.id[a], now)
         VS.Charges(A.id[a], now)
         out[#out + 1] = string.format(
-            "ability %s qid=%d cost=%s read=%s len=%.2f flag=%d",
+            "ability %s qid=%d cost=%s read=%s len=%.2f flag=%d multi=%s",
             tostring(A.key[a]),
             A.qid[a],
             tostring(I.CostOf(a)),
             tostring(A.readCost[a]),
             VS.CooldownLength(A.id[a]),
-            A.flag[a]
+            A.flag[a],
+            tostring(A.multiCost[a])
         )
     end
     VS.Gcd(now)
diff --git a/VirtualState/Families/Resources.lua b/VirtualState/Families/Resources.lua
index edb7dae1..05fcf72a 100644
--- a/VirtualState/Families/Resources.lua
+++ b/VirtualState/Families/Resources.lua
@@ -18,8 +18,9 @@ I.PIN_EXACT = 0.15
 -- Usability as observed: unknown, not usable, usable, not usable for lack of its resource.
 local UNKNOWN, NOT, YES, SHORT = -1, 0, 1, 2
 
--- By resource slot r. `swing[r]` is the hand that pays it (1 main, 2 off; 0: continuous regen). Continuous regen is
--- per second (regE/regL/regH); a swing-paid resource's step is the spec's model value x scale (spread around it).
+-- By resource slot r. `swing[r]` is the hand that pays it (1 main, 2 off; 0: continuous regen) and `swingOff[r]` the
+-- off hand's own value when both hands pay it (0: none). Continuous regen is per second (regE/regL/regH); a swing-paid
+-- resource's step is the spec's model value of that hand x scale (spread around it).
 local R = {
     n = 0,
     type = {},
@@ -28,6 +29,7 @@ local R = {
     rest = {},
     swing = {},
     swingValue = {},
+    swingOff = {},
     est0 = {},
     lo0 = {},
     hi0 = {},
@@ -80,6 +82,7 @@ I.OnBuild(function(def, now)
         R.rest[r] = d.rest or 0
         R.swing[r] = d.swing or 0
         R.swingValue[r] = d.swingValue or 0
+        R.swingOff[r] = d.swingOff or 0
         R.est0[r], R.lo0[r], R.hi0[r] = R.rest[r], 0, R.max[r]
         local rate = d.regen or 0
         R.decl[r] = rate
@@ -98,9 +101,13 @@ I.OnBuild(function(def, now)
     end
 end)
 
---- The spec's per-swing value of a swing-paid slot (a number, or the model's state-bound function). Allocates nothing.
-function I.SwingValue(r)
+--- The spec's per-swing value of a swing-paid slot for `hand` (2: the off hand's `swingOff`; else the paying hand's): a
+--- number, or the model's state-bound function. Allocates nothing.
+function I.SwingValue(r, hand)
     local v = R.swingValue[r]
+    if hand == 2 and R.swing[r] == 1 then
+        v = R.swingOff[r]
+    end
     if type(v) == "function" then
         v = v(I.clock)
     end
@@ -120,13 +127,26 @@ I.OnAdvance(function(from, to)
     end
 end)
 
+--- A swing-paid slot's model value per second of swinging: each paying hand's value / its believed speed (a hand
+--- with no speed adds nothing). Allocates nothing.
+function I.SwingPerSecond(r)
+    local per, speed = 0, I.SwingSpeedEst(R.swing[r])
+    if speed > 0 then
+        per = I.SwingValue(r) / speed -- nonzero: speed > 0 checked
+    end
+    local off = R.swing[r] == 1 and R.swingOff[r] ~= 0 and I.SwingSpeedEst(2) or 0
+    if off > 0 then
+        per = per + I.SwingValue(r, 2) / off -- nonzero: off > 0 checked
+    end
+    return per
+end
+
 -- One regen measurement m (per second, between two pins ending at t) into the slot's regen (the EMA, TDF
 -- calibrate). A swing-paid slot calibrates its step scale against the spec's value per second of swinging.
 local function calibrate(r, m, t)
     local ref
     if R.swing[r] > 0 then
-        local speed = I.SwingSpeedEst(R.swing[r])
-        ref = speed > 0 and I.SwingValue(r) / speed or 0 -- nonzero: speed > 0 checked
+        ref = I.SwingPerSecond(r)
     else
         ref = R.decl[r]
     end
@@ -221,8 +241,8 @@ I.On(Obs.Usable, function(o, t, lag)
     local was = usable[a]
     usable[a] = now
     local r = I.ab.slot[a]
-    if r == 0 or now == NOT or R.readable[r] then
-        return
+    if r == 0 or now == NOT or R.readable[r] or I.ab.multiCost[a] then
+        return -- a second power cost (Overpower's combo points) makes a short answer ambiguous: no rung
     end
     local c = I.CostOf(a)
     if c <= 0 then
@@ -231,8 +251,9 @@ I.On(Obs.Usable, function(o, t, lag)
     if was == SHORT and now == YES and lag <= 0 and abs(c - shortCost[a]) <= I.EPS then
         -- It just became affordable at an unchanged cost: it crossed the cost since the last short report.
         if R.swing[r] > 0 then
-            -- a swing-paid resource crosses at a swing: [c, c + one step), measured at its midpoint
-            local step = I.SwingValue(r) * (R.scale[r] + R.spread[r])
+            -- a swing-paid resource crosses at a swing: [c, c + one step of the larger hand), measured at its midpoint
+            local v, off = I.SwingValue(r), R.swingOff[r] ~= 0 and I.SwingValue(r, 2) or 0
+            local step = (v > off and v or off) * (R.scale[r] + R.spread[r])
             pin(r, c, step, t, "pinned", Obs.Usable, true)
         else
             local width = R.regH[r] * (t - shortT[a])
@@ -266,15 +287,17 @@ I.On(Obs.Read, function(o, t, lag)
     end
 end)
 
--- A landed swing pays each slot of its hand one step, unless an on-next-swing strike took that swing (spec §6.4).
+-- A landed swing pays each slot of its hand one step (the off hand its own value), unless an on-next-swing strike
+-- took that swing (spec §6.4).
 I.On(Obs.Swing, function(o, t)
     if o.c ~= 1 then
         return
     end
     local hand = o.a
     for r = 1, R.n do
-        if R.swing[r] == hand and not (hand == 1 and I.queuedStrike) then
-            local v, max = I.SwingValue(r), R.max[r]
+        local pays = R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0)
+        if pays and not (hand == 1 and I.queuedStrike) then
+            local v, max = I.SwingValue(r, hand), R.max[r]
             local s, sp = R.scale[r], R.spread[r]
             R.est0[r] = clamp(R.est0[r] + v * s, max)
             R.lo0[r] = clamp(R.lo0[r] + v * (s - sp), max)
@@ -357,8 +380,7 @@ function VS.Regen(powerType, now, casting)
     end
     local rec = R.regen[r]
     if R.swing[r] > 0 then
-        local speed = I.SwingSpeedEst(R.swing[r])
-        local per = speed > 0 and I.SwingValue(r) / speed or 0 -- nonzero: speed > 0 checked
+        local per = I.SwingPerSecond(r)
         local s, sp = R.scale[r], R.spread[r]
         rec.est, rec.lo, rec.hi = per * s, per * (s - sp), per * (s + sp)
         rec.conf = s > 0 and 1 - sp / s or 0 -- nonzero: s > 0 checked
diff --git a/VirtualState/Sources/Auras.lua b/VirtualState/Sources/Auras.lua
index d17d1b08..be4b8fbe 100644
--- a/VirtualState/Sources/Auras.lua
+++ b/VirtualState/Sources/Auras.lua
@@ -16,8 +16,9 @@ local Plain, Direct, Note = S.Plain, S.Direct, S.Note
 
 local SCAN = 40
 local FILTERS = { "HELPFUL", "HARMFUL" }
--- The walk status per unit index (def.units is player, target), so Snapshot tells the two apart.
-local WALK = { "aura walk player", "aura walk target" }
+-- The walk status per unit index ("aura walk <unit>", built at OnBuild for every tracked unit), so Snapshot tells
+-- them apart.
+local WALK = {}
 
 -- By unit index and aura index: the walk serial that last found it, and whether it was seen plain in combat.
 local found, seen = {}, {}
@@ -26,6 +27,7 @@ local serial = 0
 I.OnBuild(function(def)
     local U = I.auras
     for u = 1, U.n do
+        WALK[u] = "aura walk " .. tostring(def.units[u])
         local f, s = {}, {}
         for j = 1, U.nAura do
             f[j], s[j] = 0, false
@@ -88,6 +90,7 @@ local function walk(api, u, unit, t)
         end
     end
     if complete then
+        Note(WALK[u], "readable") -- a clean walk, even with no tracked aura up
         local e = U.exp0[u]
         for j = 1, U.nAura do
             if e[j] > 0 and found[u][j] ~= serial and (not I.inCombat or seen[u][j]) then
diff --git a/VirtualState/Sources/Player.lua b/VirtualState/Sources/Player.lua
index 4df1e072..0b910d4c 100644
--- a/VirtualState/Sources/Player.lua
+++ b/VirtualState/Sources/Player.lua
@@ -1,6 +1,7 @@
 -- VirtualState/Sources/Player.lua
 -- Player sources (spec §4.2): combat start and end, movement, spell haste, the player's health (poll 1.5) and the
--- out-of-combat stat cache (login, PLAYER_REGEN_ENABLED, PLAYER_EQUIPMENT_CHANGED).
+-- out-of-combat stat cache (login, PLAYER_REGEN_ENABLED, PLAYER_EQUIPMENT_CHANGED, UNIT_DAMAGE, UNIT_ATTACK_POWER,
+-- PLAYER_LEVEL_UP).
 -- Credits: secret-value handling after Catnip's (Durts) research.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Player.lua.
 
@@ -134,6 +135,20 @@ S.On("PLAYER_EQUIPMENT_CHANGED", nil, function(api, t)
     readStats(api, t)
 end)
 
+-- The weapon damage, attack power and level also change out of combat (Battle Shout before a pull, a level-up): read
+-- the stats again (readStats skips while in combat, where they are secret).
+local function onPlayerStats(api, t, unit)
+    if unit == "player" then
+        readStats(api, t)
+    end
+end
+S.On("UNIT_DAMAGE", "player", onPlayerStats)
+S.On("UNIT_ATTACK_POWER", "player", onPlayerStats)
+
+S.On("PLAYER_LEVEL_UP", nil, function(api, t)
+    readStats(api, t)
+end)
+
 S.On("PLAYER_STARTED_MOVING", nil, function(api, t)
     Stage(Obs.Moving, t, 0, 1)
 end)
diff --git a/VirtualState/Sources/Spellbook.lua b/VirtualState/Sources/Spellbook.lua
index b41f57b1..a54863ff 100644
--- a/VirtualState/Sources/Spellbook.lua
+++ b/VirtualState/Sources/Spellbook.lua
@@ -19,7 +19,7 @@ I.GCD_SPELL = 29515
 local last, gcdLast = {}, -1
 
 -- The highest known rank of each ability (rank order: its `id`, then its `copy` IDs) and, out of combat, its plain
--- cost. Out of the hot path: build, SPELLS_CHANGED.
+-- cost and whether it costs a second power type. Out of the hot path: build, SPELLS_CHANGED.
 local function resolve(api)
     local A = I.ab
     for a = 1, A.n do
@@ -36,6 +36,7 @@ local function resolve(api)
             local first = type(costs) == "table" and Plain(api, costs[1])
             local cost = type(first) == "table" and Plain(api, first.cost)
             A.readCost[a] = type(cost) == "number" and cost or 0
+            A.multiCost[a] = type(costs) == "table" and Plain(api, costs[2]) ~= nil -- a second power type (A5)
         end
     end
 end
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `104 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/virtualstate-phase1
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [104 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 63 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Families/Resources.lua VirtualState/Families/Casts.lua VirtualState/Sources/Spellbook.lua \
  VirtualState/Sources/Auras.lua VirtualState/Sources/Player.lua VirtualState/spec/resources_spec.lua \
  VirtualState/spec/casts_spec.lua VirtualState/spec/facts_spec.lua VirtualState/spec/auras_spec.lua \
  VirtualState/spec/player_spec.lua VirtualState/spec/helpers/fake_api.lua
git commit -m "feat(virtualstate): two paying hands per swing-paid resource; no ladder rung from an ability with two power costs; stats re-read on UNIT_DAMAGE, UNIT_ATTACK_POWER, PLAYER_LEVEL_UP; aura walk names per unit, a clean walk readable, GCD bound [1.0, 2.0)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-phase1`

---

### Task 2: The off hand and combat-gated periodic regen reach the resources family (forever-warrior-profile)

Work in `~/src/hekili/.claude/worktrees/forever-warrior-profile` (branch `forever-warrior-profile`, HEAD `b62beacf`).

The Warrior plan's Task 1 (aura-gated regen: `I.res.auraRegen`, `auraGain`, the adapter's `elseif m.aura` branch) was committed on this branch only, so its extension lives here too. Anger Management (12296: "Generates $m2 Rage every $m3 sec while in combat", m2 = 1, m3 = 3; reconcile §E) is a Hekili regen-model entry without an aura: `{ talent = "anger_management", interval = 3, value = 1, last, stop }` (Task 4). This task lets a periodic entry have no aura (aura index 0: credited from the combat start while in combat, in fold order: an `Obs.CombatStart` handler records it, the existing `Obs.CombatEnd` handler stops it) and an optional `talent` key (credited only while `VS.Talent(spell)` > 0, the spell resolved from `def.talents` at build: the entry exists for every Warrior, the talent is per character). The adapter forwards every entry with none of `swing`, `debuff`, `channel`, `spec`, `equip`, `set_bonus`, `setting` (an aura's or a plain periodic one; Hekili honours those five gates at State.lua:1214-1222 and VirtualState cannot see them, so such an entry stays Hekili's alone) and the off hand's swing value as `swingOff` (an off-hand entry alone becomes the paying hand 2). A build in combat (`/reload`, a spec change) seeds the combat flag from `I.inCombat` with the build time as the start (a `shortcut:`: the next pull's CombatStart sets the real start), so Anger Management is not lost until the next pull.

**Files:**
- Modify: `VirtualState/Adapter.lua` (buildDef's resource loop :102-122)
- Modify: `VirtualState/Families/Resources.lua` (header :4-5, the `G` comment and table :57-61, OnBuild's entry loop after `G.n = 0`, `auraGain`, a new `Obs.CombatStart` handler before the `Obs.CombatEnd` one)
- Test: `VirtualState/spec/adapter_spec.lua` (a case after "forwards a resource's player-aura regen entries …"), `VirtualState/spec/resources_spec.lua` (a case in "aura-gated regen …" before "allocates nothing advancing or projecting through an entry")

**Interfaces:**
- Consumes: Task 1's `def.resources[r].swingOff`, `I.res.swingOff`; `VS.Talent(spellID)` (Families/Talents.lua); `def.talents[i] = { key, spell, max }`; `Obs.CombatStart`/`Obs.CombatEnd`.
- Produces: `I.res.auraRegen.talent[g]` (spell ID, 0: none); `G.aura[g] == 0` for a combat-gated entry; the adapter forwards Hekili regen-model entries with `swing = "offhand"` (as `swingOff`) and every entry with no `swing`, no `debuff` and none of `channel`/`spec`/`equip`/`set_bonus`/`setting` (as `auraRegen`). Snapshot's `auraRegen=` now counts both kinds (the Warrior: 2).

- [ ] **Step 1: Merge Phase 1 (Task 1)**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
git merge --no-edit -m "Merge branch 'virtualstate-phase1' into forever-warrior-profile" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" virtualstate-phase1
~/src/TacoDogForever/.lua/bin/busted
```

Expected: `Auto-merging VirtualState/Families/Resources.lua`, `Auto-merging VirtualState/spec/resources_spec.lua`, a merge commit with no conflict; busted `125 successes / 0 failures / 0 errors` (118 + Task 1's 7).

- [ ] **Step 2: Write the failing specs**

Apply with `git apply`:

```diff
diff --git a/VirtualState/spec/adapter_spec.lua b/VirtualState/spec/adapter_spec.lua
index 131a1ee0..d6b015fc 100644
--- a/VirtualState/spec/adapter_spec.lua
+++ b/VirtualState/spec/adapter_spec.lua
@@ -86,6 +86,24 @@ describe("Adapter", function()
         assert.are.equal(1, I.res.swing[1]) -- the swing source is still found
     end)
 
+    it("forwards the off hand's swing value and a plain periodic entry (combat-gated), with its talent", function()
+        local model = h.Class.resources.rage.state.regenModel
+        model.offhand = { swing = "offhand", value = 4 }
+        model.anger_management = { talent = "improved_rend", interval = 3, value = 1 }
+        VS.SpecChanged()
+        assert.are.same({ 1, 9, 4 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
+        local G = I.res.auraRegen
+        assert.are.same({ 1, 0, 1, 3, 12286 }, { G.n, G.aura[1], G.value[1], G.interval[1], G.talent[1] })
+        model.shield_test = { equip = "shield", interval = 2, value = 1 } -- a gate VirtualState cannot see: dropped
+        model.channel_test = { channel = "rend", interval = 1, value = 1 }
+        VS.SpecChanged()
+        assert.are.equal(1, I.res.auraRegen.n)
+        model.shield_test, model.channel_test = nil, nil
+        model.mainhand = nil -- an off hand alone pays as the paying hand
+        VS.SpecChanged()
+        assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
+    end)
+
     it("feeds the cast history and the real queue from our own cast events, and asks for a cycle", function()
         ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
         assert.are.same({ "rend" }, state.history)
diff --git a/VirtualState/spec/resources_spec.lua b/VirtualState/spec/resources_spec.lua
index a40158f9..a5937116 100644
--- a/VirtualState/spec/resources_spec.lua
+++ b/VirtualState/spec/resources_spec.lua
@@ -225,6 +225,46 @@ describe("resources", function()
             assert.are.equal(2, VS.Power(fs.RAGE, 20).est)
         end)
 
+        it("credits a plain periodic entry only in combat, from the combat start, and only with its talent", function()
+            local def = fs.def(fs.new(9))
+            def.resources[1].auraRegen = { { talent = "improved_rend", interval = 3, value = 1 } }
+            boot(def)
+            I.Fold(10, false)
+            I.Settle(20)
+            assert.are.equal(0, VS.Power(fs.RAGE, 20).est) -- out of combat
+            S.Direct(Obs.CombatStart, 21)
+            I.Fold(21, false)
+            I.Settle(28)
+            assert.are.equal(0, VS.Power(fs.RAGE, 28).est) -- in combat, but the talent is not taken
+            I.SetTalentRank(1, 1)
+            I.Settle(31)
+            assert.are.equal(1, VS.Power(fs.RAGE, 31).est) -- the tick at 30 (combat start 21 + 3 x 3)
+            assert.are.equal(2, VS.Power(fs.RAGE, 33.5).est) -- projected: 33
+            S.Direct(Obs.CombatEnd, 34)
+            I.Fold(34, false)
+            I.Settle(40)
+            assert.are.equal(2, VS.Power(fs.RAGE, 40).est) -- 33 was the last tick
+            S.Direct(Obs.CombatStart, 50)
+            I.Fold(50, false)
+            local t = 50
+            assert.are.equal(0, alloc.bytes(function()
+                t = t + 0.1
+                I.Settle(t)
+                VS.Power(fs.RAGE, t + 0.5)
+            end, 2000))
+        end)
+
+        it("credits a plain periodic entry after a build in combat, from the build", function()
+            local def = fs.def(fs.new(9))
+            def.resources[1].auraRegen = { { interval = 3, value = 1 } }
+            boot(def)
+            I.inCombat = true -- a /reload or a spec change in combat: no CombatStart comes
+            I.Build(def, 10)
+            I.Fold(10, false)
+            I.Settle(16.5)
+            assert.are.equal(2, VS.Power(fs.RAGE, 16.5).est) -- ticks at 13 and 16
+        end)
+
         it("allocates nothing advancing or projecting through an entry", function()
             I.AuraModel(1, BLOODRAGE, 10, 1e9, 1, 10, 0)
             local t = 10
```

- [ ] **Step 3: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `125 successes / 3 failures / 0 errors`: failures in `adapter_spec.lua @ 89` (the off hand is not forwarded), `resources_spec.lua @ 228` (the plain entry is ignored) and `resources_spec.lua @ 257` (no credit after a build in combat).

- [ ] **Step 4: Write the implementation**

Apply with `git apply`:

```diff
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index 15532a24..afbe486a 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -99,18 +99,26 @@ local function buildDef()
     local slotByKey = {}
     for _, k in ipairs(sortedKeys(class.resources)) do
         local r = class.resources[k]
-        local swing, value, auraRegen = 0, nil, nil
+        local swing, value, offValue, auraRegen = 0, nil, nil, nil
         local model = r.state and r.state.regenModel
         if model then
             for _, m in pairs(model) do
-                if m.swing and HANDS[m.swing] and swing == 0 then
+                if m.swing == "offhand" then
+                    offValue = m.value
+                elseif m.swing and HANDS[m.swing] and swing == 0 then
                     swing, value = HANDS[m.swing], m.value
-                elseif m.aura and not m.debuff then
+                elseif not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting) then
                     auraRegen = auraRegen or {}
-                    auraRegen[#auraRegen + 1] = m -- a player aura's regen: { aura, interval, value } (Resources.lua)
+                    -- a player aura's regen { aura, interval, value }, or without `aura` a periodic one credited in
+                    -- combat; either may name a `talent` (Resources.lua). Hekili's other gates are unseen here, so an
+                    -- entry with one is not forwarded.
+                    auraRegen[#auraRegen + 1] = m
                 end
             end
         end
+        if swing == 0 and offValue ~= nil then
+            swing, value, offValue = 2, offValue, nil -- the off hand alone pays it
+        end
         local d = {
             key = k,
             type = r.type,
@@ -119,6 +127,7 @@ local function buildDef()
             rest = ns.ResourceRegenerates(k) and 100 or 0,
             swing = swing,
             swingValue = value,
+            swingOff = offValue,
             auraRegen = auraRegen,
         }
         insert(def.resources, d)
diff --git a/VirtualState/Families/Resources.lua b/VirtualState/Families/Resources.lua
index 0540f162..02794ae1 100644
--- a/VirtualState/Families/Resources.lua
+++ b/VirtualState/Families/Resources.lua
@@ -1,8 +1,8 @@
 -- VirtualState/Families/Resources.lua
 -- The resources family (spec §6.1): the cost ladder (a usability report pins or bounds a resource at the ability's
 -- cost), exact reads, regen calibration between pins (an EMA), swing steps for a swing-paid resource (rage), our own
--- casts' changes (Adapter.lua, spec §5.3), aura-gated regen (Hekili's regen-model entries with `aura`, `interval`,
--- `value`: Bloodrage's rage over time), and the Power/Regen accessors.
+-- casts' changes (Adapter.lua, spec §5.3), periodic regen (Hekili's regen-model entries with `interval` and `value`:
+-- with an `aura`, Bloodrage's rage over time; without one, in combat: Anger Management), and the Power/Regen accessors.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Resources.lua (calibrate :117-136, pin :218-263,
 -- ladder :275-315, Applier Usable :327, Reader Resource :365-372) and the resource conf of
 -- src/TacoDogForever/Model/Belief.lua:695-699. The power-tick phase (TDF's Applier PowerTick :378) is not modelled in
@@ -54,11 +54,14 @@ local R = {
 I.res = R
 R.slotOf, R.slotOfToken = {}, {}
 
--- Aura-gated regen entries g of every slot (built from each resource's `auraRegen`): `value` every `interval`
--- seconds from the aura's application while the player's aura j is believed up. Credited only as the clock moves on:
--- an aura first seen after its application loses the ticks before that, and a removal seen late keeps the ticks
--- already credited; both are bounded by the aura's duration and the next pin or rung corrects them.
-local G = { n = 0, slot = {}, aura = {}, value = {}, interval = {} }
+-- Periodic regen entries g of every slot (built from each resource's `auraRegen`): `value` every `interval` seconds
+-- from the aura's application while the player's aura j is believed up, or (no aura: j = 0) from the combat start
+-- while in combat (Anger Management); an entry with a `talent` only while that talent has a rank. Credited only as
+-- the clock moves on: an aura first seen after its application loses the ticks before that, and a removal seen late
+-- keeps the ticks already credited; both are bounded by the aura's duration and the next pin or rung corrects them.
+local G = { n = 0, slot = {}, aura = {}, value = {}, interval = {}, talent = {} }
+-- In combat (fold order, for the entries without an aura: aura index 0) and since when.
+local fighting, fightT = false, 0
 R.auraRegen = G
 
 -- By ability index a: the last usability answer and the last short report (cost, time).
@@ -105,17 +108,30 @@ I.OnBuild(function(def, now)
     end
     I.TRACKED.resource = R.type
     G.n = 0
+    -- shortcut: a build in combat (a /reload, a spec change) times the combat entries from the build, not the pull;
+    -- the next pull's CombatStart sets the real start.
+    fighting, fightT = I.inCombat == true, now
     for r = 1, R.n do
         local entries = list[r].auraRegen
         for k = 1, entries and #entries or 0 do
             local e = entries[k]
-            local ok = type(e.value) == "number" and type(e.interval) == "number" and e.interval > 0
-            for j = 1, #def.auras do
-                if ok and def.auras[j].key == e.aura then
-                    G.n = G.n + 1
-                    G.slot[G.n], G.aura[G.n], G.value[G.n], G.interval[G.n] = r, j, e.value, e.interval
+            local j, tid = e.aura == nil and 0 or -1, e.talent == nil and 0 or -1 -- -1: named but not tracked
+            for i = 1, #def.auras do
+                if def.auras[i].key == e.aura then
+                    j = i
                 end
             end
+            for i = 1, #def.talents do
+                if def.talents[i].key == e.talent then
+                    tid = def.talents[i].spell
+                end
+            end
+            local ok = type(e.value) == "number" and type(e.interval) == "number" and e.interval > 0
+            if ok and j >= 0 and tid >= 0 then
+                G.n = G.n + 1
+                G.slot[G.n], G.aura[G.n], G.value[G.n], G.interval[G.n] = r, j, e.value, e.interval
+                G.talent[G.n] = tid
+            end
         end
     end
     for a = 1, #def.abilities do
@@ -139,12 +155,23 @@ end
 -- What entry g brings in (from, to]: `value` at each `interval` after the player's aura was applied, up to its
 -- believed expiry. Allocates nothing.
 local function auraGain(g, from, to)
-    local j = G.aura[g]
-    local e = I.auras.exp0[1][j] -- unit 1 is always "player" (Adapter.lua's def.units)
+    local j, tid = G.aura[g], G.talent[g]
+    if tid > 0 and VS.Talent(tid) == 0 then
+        return 0
+    end
+    local e, ap
+    if j == 0 then
+        if not fighting then
+            return 0
+        end
+        e, ap = to, fightT
+    else
+        e, ap = I.auras.exp0[1][j], I.auras.applied[1][j] -- unit 1 is always "player" (Adapter.lua's def.units)
+    end
     if e <= from then
         return 0
     end
-    local ap, iv = I.auras.applied[1][j], G.interval[g]
+    local iv = G.interval[g]
     if to > e then
         to = e
     end
@@ -376,8 +403,13 @@ I.On(Obs.CastSuccess, function(o, t, lag)
     end
 end)
 
+I.On(Obs.CombatStart, function(o, t)
+    fighting, fightT = true, t
+end)
+
 -- Out of combat a resource falls toward its rest value: the interval opens down to it (lo never over-promises).
 I.On(Obs.CombatEnd, function()
+    fighting = false
     for r = 1, R.n do
         if R.rest[r] < R.lo0[r] then
             R.lo0[r] = R.rest[r]
```

- [ ] **Step 5: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `128 successes / 0 failures / 0 errors`.

- [ ] **Step 6: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [128 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 65 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output]
```

- [ ] **Step 7: Commit**

```bash
git add VirtualState/Adapter.lua VirtualState/Families/Resources.lua VirtualState/spec/adapter_spec.lua \
  VirtualState/spec/resources_spec.lua
git commit -m "feat(virtualstate): combat-gated periodic regen entries with a talent gate; the adapter forwards the off hand's swing value and aura-less periodic entries

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Push** (orchestrator, after this task's review is clean): `git push origin forever-warrior-profile`

---

### Task 3: The 52 live talents and their readers, Spearing Strike, Vanguard, Overpower's gate (forever-warrior-profile)

`RegisterTalents` (`Forever/Warrior.lua:129-190`) and the `Track{ talents }` aliases (:192-240) are replaced by the 52 nodes of the export (`export/talents.txt`; trees by the nodes' columns: Improved Thunder Clap sits in the Protection columns, Improved Slam in the Arms ones). Three max ranks change (Two-Handed Weapon Specialization 3, Improved Slam 2, Defiance 3), Iron Will and Defiance take the spell IDs their nodes define (12962, 12792), and no alias is needed (see "Rulings applied", A1). The readers of removed talents change: Cleave's `improved_cleave` becomes Raging Blows (1310315: "Reduces the Rage cost of your Cleave and Whirlwind abilities by 3"), also on Whirlwind; Shield Block's duration and Taunt's cooldown lose their removed talents (7 s, 8 s). Focused Rage (29787: "Reduces the Rage cost of your offensive abilities by 3", DB2 -30 at rank 1) becomes a state function `offensive_cost( cost )` = `max( 0, cost - 3 x rank )` on every ability that strikes an enemy, and Disarm (not the debuffing shouts: Demoralizing, Piercing Howl, Intimidating, Challenging; the rule is narrowed to match the list) (concussion_blow, disarm, hamstring, intercept, mocking_blow, mortal_strike, bloodthirst, overpower, pummel, rend, revenge, shield_bash, shield_slam, slam, spearing_strike, cleave, execute, heroic_strike, sunder_armor, thunder_clap, whirlwind; not the shouts, stances, Bloodrage, Berserker Rage, the defensives). Which abilities Forever counts as offensive is unseen until someone buys the talent (reconcile §F6): the list is this plan's reading of "offensive". Spearing Strike (1310222) is an Arms talent node, not a level-1 spell (A2). Vanguard (1310317: "Your Charge ability is now usable while in Defensive Stance") makes Charge's stance gate a function (A3). Overpower's `usable` is the strict plain read (A8).

**Files:**
- Modify: `Forever/Warrior.lua` (header :6-8; `SHIELD_BLOCK_BONUS` :57; `reactive`'s comment :78 (Overpower no longer uses it); a `usableNow` helper before :88; `RegisterTalents` and `Track` :129-240; `overpower_ready`'s comment :388-390; `shield_block`'s duration :436; `offensive_cost` before `reset_precast` :491; the `spend` of the 21 abilities above; `charge` :635-650; `overpower` :933-950; `spearing_strike` :1155-1169; `taunt` :1207-1219)
- Modify: `.luacheckrc` (`warriorEnv` :114-117: `offensive_cost`, else luacheck reports 21 W113 "accessing undefined variable offensive_cost")
- Test: `Forever/spec/warrior_spec.lua` (`TALENTS` and its comment :58-114 replaced, plus a `rank(n)` helper; the talent-cost case :151-166 rewritten; two new cases after it; the talent-tree case :208-227 rewritten; the `rank(1)` simplifications in :237-260)

**Interfaces:**
- Consumes: the loader `Forever/spec/helpers/load_warrior.lua` (`w.game.usable`, `w.game.noMana`, `w.game.known`; `lw.env(w)` binds the file's state functions, so `offensive_cost` resolves inside `spend` functions).
- Produces: talent keys (Task 4 reads `unbridled_wrath`, `dual_wield_specialization`, `anger_management`); the state function `offensive_cost( cost )`; `usableNow( ids )` (file-local: true only when the known rank's `IsSpellUsable` first return is `true`).

- [ ] **Step 1: Write the failing specs**

Apply with `git apply`:

```diff
diff --git a/Forever/spec/warrior_spec.lua b/Forever/spec/warrior_spec.lua
index 96181c6b..50ac191f 100644
--- a/Forever/spec/warrior_spec.lua
+++ b/Forever/spec/warrior_spec.lua
@@ -55,64 +55,72 @@ local KIT = {
     whirlwind = { { 1680 }, 25, 10, "spell" },
 }
 
--- key = the talent's rank spells (wowdb talents WARRIOR, r1..r5): 18 Arms, 18 Fury, 17 Protection;
--- `max` where the DB2 has only rank 1 (Furious Precision: Forever-only, no rank spells to alias).
+-- key = { definition spell, max rank } of each of the 52 live talent nodes (ForeverProbe export, client 1.60.1.70374,
+-- 2026-10-15: 17 Arms, 17 Fury, 18 Protection by the nodes' columns). Every owned multi-rank node reported its rank 1
+-- spell at its current rank, so no rank aliases; Iron Will and Defiance define themselves by a higher DB2 rank's ID.
 local TALENTS = {
-    improved_heroic_strike = { 12282, 12663, 12664 },
-    deflection = { 16462, 16463, 16464, 16465, 16466 },
-    improved_rend = { 12286, 12658, 12659 },
-    improved_charge = { 12285, 12697 },
-    improved_tactical_mastery = { 12295, 12676, 12677, 12678, 12679 },
-    improved_thunder_clap = { 12287, 12665, 12666 },
-    improved_overpower = { 12290, 12963 },
-    anger_management = { 12296 },
-    deep_wounds = { 12834, 12849, 12867 },
-    two_handed_weapon_specialization = { 12163, 12711, 12712, 12713, 12714 },
-    impale = { 16493, 16494 },
-    axe_specialization = { 12700, 12781, 12783, 12784, 12785 },
-    sweeping_strikes = { 12292 },
-    mace_specialization = { 12284, 12701, 12702, 12703, 12704 },
-    sword_specialization = { 12281, 12812, 12813, 12814, 12815 },
-    polearm_specialization = { 12165, 12830, 12831, 12832, 12833 },
-    improved_hamstring = { 12289, 12668, 23695 },
-    mortal_strike = { 12294 },
-    booming_voice = { 12321, 12835, 12836, 12837, 12838 },
-    cruelty = { 12320, 12852, 12853, 12855, 12856 },
-    improved_demoralizing_shout = { 12324, 12876, 12877, 12878, 12879 },
-    unbridled_wrath = { 12322, 12999, 13000, 13001, 13002 },
-    improved_cleave = { 12329, 12950, 20496 },
-    piercing_howl = { 12323 },
-    blood_craze = { 16487, 16489, 16492 },
-    improved_battle_shout = { 12318, 12857, 12858, 12860, 12861 },
-    dual_wield_specialization = { 23584, 23585, 23586, 23587, 23588 },
-    improved_execute = { 20502, 20503 },
-    enrage = { 12317, 13045, 13046, 13047, 13048 },
-    improved_slam = { 12862, 12330, 20497, 20498, 20499 },
-    death_wish = { 12328 },
-    improved_intercept = { 20504, 20505 },
-    improved_berserker_rage = { 20500, 20501 },
-    flurry = { 12319, 12971, 12972, 12973, 12974 },
-    bloodthirst = { 23881 },
-    furious_precision = { 1323963, max = 3 },
-    shield_specialization = { 12298, 12724, 12725, 12726, 12727 },
-    anticipation = { 12297, 12750, 12751, 12752, 12753 },
-    improved_bloodrage = { 12301, 12818 },
-    toughness = { 12299, 12761, 12762, 12763, 12764 },
-    iron_will = { 12300, 12959, 12960, 12961, 12962 },
-    last_stand = { 12975 },
-    improved_shield_block = { 12945, 12307, 12944 },
-    improved_revenge = { 12797, 12799, 12800 },
-    defiance = { 12303, 12788, 12789, 12791, 12792 },
-    improved_sunder_armor = { 12308, 12810, 12811 },
-    improved_disarm = { 12313, 12804, 12807 },
-    improved_taunt = { 12302, 12765 },
-    improved_shield_wall = { 12312, 12803 },
-    concussion_blow = { 12809 },
-    improved_shield_bash = { 12311, 12958 },
-    one_handed_weapon_specialization = { 16538, 16539, 16540, 16541, 16542 },
-    shield_slam = { 23922 },
+    anger_management = { 12296, 1 },
+    bloodthrill = { 1289682, 5 },
+    deep_wounds = { 12834, 3 },
+    deflection = { 16462, 5 },
+    impale = { 16493, 2 },
+    improved_charge = { 12285, 2 },
+    improved_hamstring = { 12289, 3 },
+    improved_heroic_strike = { 12282, 3 },
+    improved_overpower = { 12290, 2 },
+    improved_rend = { 12286, 3 },
+    improved_slam = { 12862, 2 },
+    improved_tactical_mastery = { 12295, 5 },
+    mortal_strike = { 12294, 1 },
+    spearing_strike = { 1310222, 1 },
+    sweeping_strikes = { 12292, 1 },
+    two_handed_weapon_specialization = { 12163, 3 },
+    weaponmaster = { 1290261, 5 },
+    blood_craze = { 16487, 3 },
+    bloodthirst = { 23881, 1 },
+    booming_voice = { 12321, 5 },
+    cruelty = { 12320, 5 },
+    death_wish = { 12328, 1 },
+    dual_wield_specialization = { 23584, 5 },
+    enrage = { 12317, 5 },
+    flurry = { 12319, 5 },
+    furious_precision = { 1323963, 3 },
+    gore_drinker = { 1323967, 2 },
+    improved_berserker_rage = { 20500, 2 },
+    improved_execute = { 20502, 2 },
+    improved_intercept = { 20504, 2 },
+    lingering_rage = { 1323964, 5 },
+    piercing_howl = { 12323, 1 },
+    raging_blows = { 1310315, 1 },
+    unbridled_wrath = { 12322, 5 },
+    anticipation = { 12297, 5 },
+    one_handed_weapon_specialization = { 16538, 5 }, -- "Bastion" on Forever
+    concussion_blow = { 12809, 1 },
+    defiance = { 12792, 3 },
+    focused_rage = { 29787, 3 },
+    improved_bloodrage = { 12301, 2 },
+    improved_disarm = { 12313, 3 },
+    improved_revenge = { 12797, 3 },
+    improved_shield_bash = { 12311, 2 },
+    improved_shield_wall = { 12312, 2 },
+    improved_sunder_armor = { 12308, 3 },
+    improved_thunder_clap = { 12287, 3 },
+    iron_will = { 12962, 5 },
+    last_stand = { 12975, 1 },
+    master_of_defense = { 1310316, 2 },
+    shield_slam = { 23922, 1 },
+    shield_specialization = { 12298, 5 },
+    vanguard = { 1310317, 1 },
 }
 
+local function rank(n)
+    return setmetatable({}, {
+        __index = function()
+            return { rank = n, enabled = n > 0 }
+        end,
+    })
+end
+
 local function idsOf(a)
     local ids = { a.id }
     for _, v in ipairs(a.copy or {}) do
@@ -148,21 +156,39 @@ describe("Forever Warrior", function()
         assert.is_true(w.abilities.heroic_strike.onNextSwing and w.abilities.cleave.onNextSwing)
     end)
 
-    it("models the talent-modified costs and cooldowns from rank 1's DB2 value x the rank", function()
+    it("models the talent-modified costs from rank 1's value x the rank, Focused Rage on the offensive ones", function()
         local e = lw.env(w)
-        e.talent = setmetatable({}, {
-            __index = function()
-                return { rank = 2, enabled = true }
-            end,
-        })
-        local function at(key, field)
-            return lw.run(w.abilities[key][field], e)
+        e.talent = rank(2)
+        local function at(key)
+            return lw.run(w.abilities[key].spend, e)
         end
+        -- Focused Rage -3 a rank; Raging Blows -3 (Cleave, Whirlwind); Improved Heroic Strike -1, Improved Execute -5,
+        -- Improved Sunder Armor -3, Improved Thunder Clap -6 a rank; floored at 0
         assert.are.same(
-            { 13, 14, 5, 9, 8, 6 },
-            { at("heroic_strike", "spend"), at("cleave", "spend"), at("execute", "spend"), at("sunder_armor", "spend"),
-                at("thunder_clap", "spend"), at("taunt", "cooldown") }
+            { 7, 8, 0, 3, 2, 13, 0, 24, 10 },
+            { at("heroic_strike"), at("cleave"), at("execute"), at("sunder_armor"), at("thunder_clap"), at("whirlwind"),
+                at("overpower"), at("mortal_strike"), at("battle_shout") }
         )
+        assert.are.same({ 8, 7 }, { lw.run(w.abilities.taunt.cooldown, e), lw.run(w.auras.shield_block.duration, e) })
+    end)
+
+    it("gates Spearing Strike on its talent, and Charge on Defensive Stance with Vanguard", function()
+        local e = lw.env(w)
+        assert.are.equal("spearing_strike", w.abilities.spearing_strike.talent)
+        e.buff = setmetatable({ defensive_stance = { up = true } }, getmetatable(e.buff))
+        assert.are.equal("battle_stance", lw.run(w.abilities.charge.buff, e))
+        e.talent = rank(1)
+        assert.are.equal("defensive_stance", lw.run(w.abilities.charge.buff, e))
+    end)
+
+    it("recommends Overpower only while the client calls it usable, not when it is short of its combo point", function()
+        local e = lw.env(w)
+        w.game.known[7384] = true
+        assert.is_false(lw.run(w.abilities.overpower.usable, e))
+        w.game.noMana[7384] = true -- no dodge: the second power cost (a combo point) is missing
+        assert.is_false(lw.run(w.abilities.overpower.usable, e))
+        w.game.usable[7384] = true
+        assert.is_true(lw.run(w.abilities.overpower.usable, e))
     end)
 
     it("gates Thunder Clap, Execute and Spearing Strike on the stances Forever's tooltips name", function()
@@ -205,24 +231,17 @@ describe("Forever Warrior", function()
         assert.are.equal("mainhand", models.mainhand.swing)
     end)
 
-    it("registers the three talent trees, and maps every higher rank spell to its rank 1 for the trait walk", function()
-        local n, aliases = 0, 0
-        for key, ranks in pairs(TALENTS) do
+    it("registers the 52 live talent nodes with their definition spells and max ranks, and no rank aliases", function()
+        local n, registered = 0, 0
+        for key, t in pairs(TALENTS) do
             n = n + 1
-            assert.are.same({ 0, ranks[1], ranks.max or #ranks }, w.talents[key], key)
-            for r = 2, #ranks do
-                assert.are.equal(ranks[1], w.track[ranks[r]], key .. " rank " .. r)
-            end
-            aliases = aliases + #ranks - 1
+            assert.are.same({ 0, t[1], t[2] }, w.talents[key], key)
         end
-        local registered, tracked = 0, 0
         for _ in pairs(w.talents) do
             registered = registered + 1
         end
-        for _ in pairs(w.track) do
-            tracked = tracked + 1
-        end
-        assert.are.same({ 53, 53, 120, 120 }, { n, registered, aliases, tracked })
+        assert.are.same({ 52, 52 }, { n, registered })
+        assert.is_nil(next(w.track))
     end)
 
     it("reads the stance, a queued strike and Revenge's window at reset", function()
@@ -237,11 +256,7 @@ describe("Forever Warrior", function()
     it("keeps Tactical Mastery's rage on a stance swap", function()
         local e = lw.env(w)
         w.game.known[1310185] = true
-        e.talent = setmetatable({}, {
-            __index = function()
-                return { rank = 1, enabled = true }
-            end,
-        })
+        e.talent = rank(1)
         e.swap_stance("berserker_stance")
         assert.are.same({ 25 }, e.spent) -- 50 rage, 10 + 1 x 15 kept (DB2 12295: 15 a rank)
         assert.are.same({ "berserker_stance" }, e.applied)
@@ -251,11 +266,7 @@ describe("Forever Warrior", function()
         local e = lw.env(w)
         lw.run(w.abilities.shield_bash.handler, e)
         assert.are.same({}, e.applied)
-        e.talent = setmetatable({}, {
-            __index = function()
-                return { rank = 1, enabled = true }
-            end,
-        })
+        e.talent = rank(1)
         lw.run(w.abilities.shield_bash.handler, e)
         assert.are.same({ "shield_bash_silenced" }, e.applied) -- DB2 12311: 100% at rank 1
     end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `126 successes / 4 failures / 0 errors`: `warrior_spec.lua @ 159` (costs: 13 for Heroic Strike, no Focused Rage), `@ 175` (Spearing Strike has no `talent`), `@ 184` (Overpower has no `usable`), `@ 234` (`vanguard` is not registered).

- [ ] **Step 3: Write the implementation**

Apply with `git apply`:

```diff
diff --git a/.luacheckrc b/.luacheckrc
index 5bf5ada4..e513f8f7 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -113,7 +113,7 @@ files["Forever/spec/"] = { std = "+busted" }
 -- further `state` names they use.
 local warriorEnv = {
     "rage", "cooldown", "combat", "active_enemies", "active_dot", "setDistance", "interrupt", "swap_stance",
-    "should_queue", "mainhand_remains", "nextMH", "mainhand_speed",
+    "should_queue", "mainhand_remains", "nextMH", "mainhand_speed", "offensive_cost",
 }
 for _, k in ipairs(stateEnv) do
     warriorEnv[#warriorEnv + 1] = k
diff --git a/Forever/Warrior.lua b/Forever/Warrior.lua
index 7ed2aacc..112c208d 100644
--- a/Forever/Warrior.lua
+++ b/Forever/Warrior.lua
@@ -3,9 +3,10 @@
 -- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb; a cost of 100 there is 10 rage), Forever's
 -- Victory Rush and Spearing Strike, rage with its main-hand swing model and Bloodrage's rage over time, stances from
 -- the plain shapeshift reads, and the default priorities.
--- Talent modifiers: only rank 1 of each talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank
--- (Classic's own convention), floored at 0; cooldown and duration modifiers are modelled only where every rank is in
--- the DB2 (Improved Taunt, Improved Shield Block). The in-game checkpoint compares the costs (Snapshot cost= / read=).
+-- Talents: the 52 live nodes (a ForeverProbe export of the client, 1.60.1.70374, 2026-10-15). Only rank 1 of each
+-- talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank (Classic's own convention), floored
+-- at 0; no cooldown or duration modifier is modelled. The in-game checkpoint compares the costs (Snapshot cost= /
+-- read=).
 -- Unmodelled: Improved Slam's cast and GCD -0.5 s and cooldown -3 s (12862; only its replacement spells are tracked).
 -- Credits: Hekili (registration API and pack format); the abilities, auras, stance swap, queue prediction and the Arms
 -- and Fury priorities are ported from Hekili's Classic profile (origin/classic:Classic/Warrior.lua,
@@ -54,7 +55,6 @@ local THUNDER_CLAP = { 6343, 8198, 8204, 8205, 11580, 11581 }
 local THUNDER_CLAP_DURATION = { 10, 14, 18, 22, 26, 30 }
 local VICTORY_RUSH = { 402927 }
 local WHIRLWIND = { 1680 }
-local SHIELD_BLOCK_BONUS = { 0.5, 1, 2 } -- Improved Shield Block's seconds by rank (all three in the DB2)
 local TACTICAL_MASTERY = 1310185 -- Forever's level 14 passive: rage kept on a stance swap
 
 local function rest( ids )
@@ -75,7 +75,7 @@ local function knows( ids )
     return function () return knownRank( ids ) > 0 end
 end
 
--- A reactive ability's window (Execute, Overpower's stance, Revenge, Victory Rush) from the plain usability read:
+-- A reactive ability's window (Execute, Revenge, Victory Rush) from the plain usability read:
 -- usable, or unusable only for lack of rage. The client's answer now, not at the simulated time (as Classic's
 -- reset_precast read it); Forever has no combat log to time the window.
 local function reactive( ids )
@@ -85,6 +85,13 @@ local function reactive( ids )
     return usable == true or noMana == true
 end
 
+-- Usable now by the plain read, not merely short of a cost: Overpower's second cost (a combo point a dodge grants)
+-- reads as "short" without a dodge.
+local function usableNow( ids )
+    local r = knownRank( ids )
+    return r > 0 and IsSpellUsable( ids[ r ] ) == true
+end
+
 -- Rage a second of the main hand's unhasted weapon speed: a white swing brings rate x that speed (haste adds swings,
 -- never rage per swing): 4.5 for a two-hander, 3.46 for a one-hander (Hekili's gear scan sets main_hand.size).
 -- shortcut: no off-hand swing source (VirtualState models one swing-paid hand), so a dual wielder's off hand is left
@@ -126,119 +133,74 @@ spec:RegisterResource( Enum.PowerType.Rage, {
     },
 } )
 
--- Talents: { node (unused on Forever), the rank 1 spell, max rank }, all three trees (wowdb talents WARRIOR); keys are
--- Classic's where the DB2's name is blank or shared (Weaponmaster, Iron Will, Defiance, the polearm specialization).
--- VirtualState maps the trait walk's spells to them.
+-- Talents: { node (unused on Forever), the definition spell, max rank }: the 52 nodes of Forever's one talent tree,
+-- grouped by their columns as the pane shows them. Keys are Classic's where the talent exists (Bastion keeps Classic's
+-- one_handed_weapon_specialization), snake_case names for the Forever-only ones. Each node reported one definition
+-- spell at every rank the export saw (owned nodes at ranks 1-5 report their rank 1 spell; Iron Will and Defiance
+-- define themselves by a higher DB2 rank's ID), so there are no rank aliases. VirtualState maps the trait walk's
+-- spells to them.
 spec:RegisterTalents( {
-    -- Arms (18)
+    -- Arms (17)
     improved_heroic_strike           = { 0, 12282, 3 },
     deflection                       = { 0, 16462, 5 },
     improved_rend                    = { 0, 12286, 3 },
     improved_charge                  = { 0, 12285, 2 },
     improved_tactical_mastery        = { 0, 12295, 5 },
-    improved_thunder_clap            = { 0, 12287, 3 },
     improved_overpower               = { 0, 12290, 2 },
     anger_management                 = { 0, 12296, 1 },
     deep_wounds                      = { 0, 12834, 3 },
-    two_handed_weapon_specialization = { 0, 12163, 5 },
+    two_handed_weapon_specialization = { 0, 12163, 3 },
     impale                           = { 0, 16493, 2 },
-    axe_specialization               = { 0, 12700, 5 },
     sweeping_strikes                 = { 0, 12292, 1 },
-    mace_specialization              = { 0, 12284, 5 },
-    sword_specialization             = { 0, 12281, 5 },
-    polearm_specialization           = { 0, 12165, 5 },
     improved_hamstring               = { 0, 12289, 3 },
     mortal_strike                    = { 0, 12294, 1 },
-    -- Fury (18)
+    improved_slam                    = { 0, 12862, 2 }, -- effect unmodelled
+    -- Forever-only; Weaponmaster (in place of the four weapon specializations) and Bloodthrill unmodelled.
+    weaponmaster                     = { 0, 1290261, 5 },
+    spearing_strike                  = { 0, 1310222, 1 },
+    bloodthrill                      = { 0, 1289682, 5 },
+    -- Fury (17)
     booming_voice                    = { 0, 12321, 5 },
     cruelty                          = { 0, 12320, 5 },
-    improved_demoralizing_shout      = { 0, 12324, 5 },
     unbridled_wrath                  = { 0, 12322, 5 },
-    improved_cleave                  = { 0, 12329, 3 },
     piercing_howl                    = { 0, 12323, 1 },
     blood_craze                      = { 0, 16487, 3 },
-    improved_battle_shout            = { 0, 12318, 5 },
     dual_wield_specialization        = { 0, 23584, 5 },
     improved_execute                 = { 0, 20502, 2 },
     enrage                           = { 0, 12317, 5 },
-    improved_slam                    = { 0, 12862, 5 },
     death_wish                       = { 0, 12328, 1 },
     improved_intercept               = { 0, 20504, 2 },
     improved_berserker_rage          = { 0, 20500, 2 },
     flurry                           = { 0, 12319, 5 },
     bloodthirst                      = { 0, 23881, 1 },
-    -- Forever-only, not in the DB2 talent table (DB2 spell_info name); max rank 3 from the talent pane; effect unmodelled.
+    -- Forever-only: Raging Blows (-3 rage on Cleave and Whirlwind); the others unmodelled.
     furious_precision                = { 0, 1323963, 3 },
-    -- Protection (17)
+    raging_blows                     = { 0, 1310315, 1 },
+    lingering_rage                   = { 0, 1323964, 5 },
+    gore_drinker                     = { 0, 1323967, 2 },
+    -- Protection (18)
     shield_specialization            = { 0, 12298, 5 },
     anticipation                     = { 0, 12297, 5 },
     improved_bloodrage               = { 0, 12301, 2 },
-    toughness                        = { 0, 12299, 5 },
-    iron_will                        = { 0, 12300, 5 },
+    improved_thunder_clap            = { 0, 12287, 3 },
+    iron_will                        = { 0, 12962, 5 },
     last_stand                       = { 0, 12975, 1 },
-    improved_shield_block            = { 0, 12945, 3 },
     improved_revenge                 = { 0, 12797, 3 },
-    defiance                         = { 0, 12303, 5 },
+    defiance                         = { 0, 12792, 3 },
     improved_sunder_armor            = { 0, 12308, 3 },
     improved_disarm                  = { 0, 12313, 3 },
-    improved_taunt                   = { 0, 12302, 2 },
     improved_shield_wall             = { 0, 12312, 2 },
     concussion_blow                  = { 0, 12809, 1 },
     improved_shield_bash             = { 0, 12311, 2 },
-    one_handed_weapon_specialization = { 0, 16538, 5 },
+    one_handed_weapon_specialization = { 0, 16538, 5 }, -- "Bastion" on Forever
     shield_slam                      = { 0, 23922, 1 },
+    -- Forever-only: Focused Rage (-3 rage a rank on the offensive abilities), Vanguard (Charge in Defensive Stance);
+    -- Master of Defense unmodelled.
+    focused_rage                     = { 0, 29787, 3 },
+    vanguard                         = { 0, 1310317, 1 },
+    master_of_defense                = { 0, 1310316, 2 },
 } )
 
--- The higher rank spells of each talent, in case the trait walk names a rank rather than rank 1 (spec §3.6 Track).
-ns.VirtualState.Track( { talents = {
-    -- Arms
-    [ 12663 ] = 12282, [ 12664 ] = 12282,
-    [ 16463 ] = 16462, [ 16464 ] = 16462, [ 16465 ] = 16462, [ 16466 ] = 16462,
-    [ 12658 ] = 12286, [ 12659 ] = 12286,
-    [ 12697 ] = 12285,
-    [ 12676 ] = 12295, [ 12677 ] = 12295, [ 12678 ] = 12295, [ 12679 ] = 12295,
-    [ 12665 ] = 12287, [ 12666 ] = 12287,
-    [ 12963 ] = 12290,
-    [ 12849 ] = 12834, [ 12867 ] = 12834,
-    [ 12711 ] = 12163, [ 12712 ] = 12163, [ 12713 ] = 12163, [ 12714 ] = 12163,
-    [ 16494 ] = 16493,
-    [ 12781 ] = 12700, [ 12783 ] = 12700, [ 12784 ] = 12700, [ 12785 ] = 12700,
-    [ 12701 ] = 12284, [ 12702 ] = 12284, [ 12703 ] = 12284, [ 12704 ] = 12284,
-    [ 12812 ] = 12281, [ 12813 ] = 12281, [ 12814 ] = 12281, [ 12815 ] = 12281,
-    [ 12830 ] = 12165, [ 12831 ] = 12165, [ 12832 ] = 12165, [ 12833 ] = 12165,
-    [ 12668 ] = 12289, [ 23695 ] = 12289,
-    -- Fury
-    [ 12835 ] = 12321, [ 12836 ] = 12321, [ 12837 ] = 12321, [ 12838 ] = 12321,
-    [ 12852 ] = 12320, [ 12853 ] = 12320, [ 12855 ] = 12320, [ 12856 ] = 12320,
-    [ 12876 ] = 12324, [ 12877 ] = 12324, [ 12878 ] = 12324, [ 12879 ] = 12324,
-    [ 12999 ] = 12322, [ 13000 ] = 12322, [ 13001 ] = 12322, [ 13002 ] = 12322,
-    [ 12950 ] = 12329, [ 20496 ] = 12329,
-    [ 16489 ] = 16487, [ 16492 ] = 16487,
-    [ 12857 ] = 12318, [ 12858 ] = 12318, [ 12860 ] = 12318, [ 12861 ] = 12318,
-    [ 23585 ] = 23584, [ 23586 ] = 23584, [ 23587 ] = 23584, [ 23588 ] = 23584,
-    [ 20503 ] = 20502,
-    [ 13045 ] = 12317, [ 13046 ] = 12317, [ 13047 ] = 12317, [ 13048 ] = 12317,
-    [ 12330 ] = 12862, [ 20497 ] = 12862, [ 20498 ] = 12862, [ 20499 ] = 12862,
-    [ 20505 ] = 20504,
-    [ 20501 ] = 20500,
-    [ 12971 ] = 12319, [ 12972 ] = 12319, [ 12973 ] = 12319, [ 12974 ] = 12319,
-    -- Protection
-    [ 12724 ] = 12298, [ 12725 ] = 12298, [ 12726 ] = 12298, [ 12727 ] = 12298,
-    [ 12750 ] = 12297, [ 12751 ] = 12297, [ 12752 ] = 12297, [ 12753 ] = 12297,
-    [ 12818 ] = 12301,
-    [ 12761 ] = 12299, [ 12762 ] = 12299, [ 12763 ] = 12299, [ 12764 ] = 12299,
-    [ 12959 ] = 12300, [ 12960 ] = 12300, [ 12961 ] = 12300, [ 12962 ] = 12300,
-    [ 12307 ] = 12945, [ 12944 ] = 12945,
-    [ 12799 ] = 12797, [ 12800 ] = 12797,
-    [ 12788 ] = 12303, [ 12789 ] = 12303, [ 12791 ] = 12303, [ 12792 ] = 12303,
-    [ 12810 ] = 12308, [ 12811 ] = 12308,
-    [ 12804 ] = 12313, [ 12807 ] = 12313,
-    [ 12765 ] = 12302,
-    [ 12803 ] = 12312,
-    [ 12958 ] = 12311,
-    [ 16539 ] = 16538, [ 16540 ] = 16538, [ 16541 ] = 16538, [ 16542 ] = 16538,
-} } )
-
 spec:RegisterAuras( {
     battle_shout = {
         id = 6673,
@@ -386,8 +348,8 @@ spec:RegisterAuras( {
         max_stack = 1,
     },
     -- Forever's Overpower window: a 5 s player aura (DB2 1282733, "Overpower"). It is unseen on Forever (checkpoint Q6:
-    -- the aura walk raises in combat), so Overpower goes on rage alone in Battle Stance (the client refuses it outside
-    -- the window), and the swap to Battle Stance after a dodge cannot be predicted (no combat log on Forever).
+    -- the aura walk raises in combat), so Overpower's gate is the client's usability read, and the swap to Battle
+    -- Stance after a dodge cannot be predicted (no combat log on Forever).
     overpower_ready = {
         id = 1282733,
         duration = 5,
@@ -433,7 +395,7 @@ spec:RegisterAuras( {
     },
     shield_block = {
         id = 2565,
-        duration = function () return 7 + ( SHIELD_BLOCK_BONUS[ talent.improved_shield_block.rank ] or 0 ) end,
+        duration = 7,
         max_stack = 1,
     },
     shield_wall = {
@@ -488,6 +450,14 @@ spec:RegisterStateFunction( "swap_stance", function( stance )
     applyBuff( stance )
 end )
 
+-- Focused Rage: -3 rage a rank on the offensive abilities (Forever's tooltip; DB2 29787 -30 at rank 1), floored at 0.
+-- shortcut: which abilities count is a guess (every ability that strikes an enemy, and Disarm; not the shouts),
+-- unseen until someone buys the talent; correct the offensive_cost calls from the client's costs (Snapshot cost= /
+-- read=) then.
+spec:RegisterStateFunction( "offensive_cost", function( cost )
+    return max( 0, cost - 3 * talent.focused_rage.rank )
+end )
+
 spec:RegisterHook( "reset_precast", function()
     -- The stance from the plain shapeshift reads (forever-facade-notes: GetShapeshiftForm, GetShapeshiftFormInfo).
     removeBuff( "battle_stance" )
@@ -606,7 +576,7 @@ spec:RegisterAbilities( {
         cooldown = 6,
         gcd = "spell",
 
-        spend = 30,
+        spend = function () return offensive_cost( 30 ) end,
         spendType = "rage",
 
         talent = "bloodthirst",
@@ -641,7 +611,11 @@ spec:RegisterAbilities( {
 
         startsCombat = true,
         known = knows( CHARGE ),
-        buff = "battle_stance",
+        -- Vanguard: Charge also in Defensive Stance (Forever, 1310317)
+        buff = function ()
+            if talent.vanguard.enabled and buff.defensive_stance.up then return "defensive_stance" end
+            return "battle_stance"
+        end,
 
         usable = function ()
             return combat == 0 and target.minR >= 8 and target.minR <= 25, "cannot be in combat; target must be outside your deadzone"
@@ -661,7 +635,7 @@ spec:RegisterAbilities( {
         cooldown = 0,
         gcd = "off",
 
-        spend = function () return max( 0, 20 - 3 * talent.improved_cleave.rank ) end,
+        spend = function () return offensive_cost( 20 - 3 * talent.raging_blows.rank ) end, -- Raging Blows: -3
         spendType = "rage",
 
         startsCombat = true,
@@ -683,7 +657,7 @@ spec:RegisterAbilities( {
         cooldown = 45,
         gcd = "off",
 
-        spend = 10,
+        spend = function () return offensive_cost( 10 ) end,
         spendType = "rage",
 
         talent = "concussion_blow",
@@ -755,7 +729,7 @@ spec:RegisterAbilities( {
         cooldown = 60,
         gcd = "spell",
 
-        spend = 20,
+        spend = function () return offensive_cost( 20 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -776,7 +750,7 @@ spec:RegisterAbilities( {
         cooldown = 0,
         gcd = "spell",
 
-        spend = function () return max( 0, 15 - 5 * talent.improved_execute.rank ) end,
+        spend = function () return offensive_cost( max( 0, 15 - 5 * talent.improved_execute.rank ) ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -797,7 +771,7 @@ spec:RegisterAbilities( {
         cooldown = 0,
         gcd = "spell",
 
-        spend = 10,
+        spend = function () return offensive_cost( 10 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -816,7 +790,8 @@ spec:RegisterAbilities( {
         cooldown = 0,
         gcd = "off",
 
-        spend = function () return 15 - talent.improved_heroic_strike.rank end, -- Improved Heroic Strike: -1 a rank
+        -- Improved Heroic Strike: -1 a rank
+        spend = function () return offensive_cost( 15 - talent.improved_heroic_strike.rank ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -843,7 +818,7 @@ spec:RegisterAbilities( {
         cooldown = 30,
         gcd = "off",
 
-        spend = 10,
+        spend = function () return offensive_cost( 10 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -898,7 +873,7 @@ spec:RegisterAbilities( {
         cooldown = 120,
         gcd = "spell",
 
-        spend = 10,
+        spend = function () return offensive_cost( 10 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -918,7 +893,7 @@ spec:RegisterAbilities( {
         cooldown = 6,
         gcd = "spell",
 
-        spend = 30,
+        spend = function () return offensive_cost( 30 ) end,
         spendType = "rage",
 
         talent = "mortal_strike",
@@ -937,13 +912,16 @@ spec:RegisterAbilities( {
         cooldown = 5,
         gcd = "spell",
 
-        spend = 5,
+        spend = function () return offensive_cost( 5 ) end,
         spendType = "rage",
 
         startsCombat = true,
         known = knows( OVERPOWER ),
         buff = "battle_stance",
 
+        -- interim until the virtual event facade delivers the dodge event
+        usable = function () return usableNow( OVERPOWER ), "no dodge to overpower" end,
+
         handler = function ()
             removeBuff( "overpower_ready" )
         end,
@@ -974,7 +952,7 @@ spec:RegisterAbilities( {
         cooldown = 10,
         gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)
 
-        spend = 10,
+        spend = function () return offensive_cost( 10 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -1011,7 +989,7 @@ spec:RegisterAbilities( {
         cooldown = 0,
         gcd = "spell",
 
-        spend = 10,
+        spend = function () return offensive_cost( 10 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -1046,7 +1024,7 @@ spec:RegisterAbilities( {
         cooldown = 5,
         gcd = "spell",
 
-        spend = 5,
+        spend = function () return offensive_cost( 5 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -1069,7 +1047,7 @@ spec:RegisterAbilities( {
         cooldown = 12,
         gcd = "spell", -- the DB2's (start recovery 1500 ms); Classic had it off the GCD (checkpoint question)
 
-        spend = 10,
+        spend = function () return offensive_cost( 10 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -1112,7 +1090,7 @@ spec:RegisterAbilities( {
         cooldown = 6,
         gcd = "spell",
 
-        spend = 20,
+        spend = function () return offensive_cost( 20 ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -1145,24 +1123,25 @@ spec:RegisterAbilities( {
         cooldown = 18,
         gcd = "spell",
 
-        spend = 15,
+        spend = function () return offensive_cost( 15 ) end,
         spendType = "rage",
 
         startsCombat = true,
         known = knows( SLAM ),
     },
 
-    -- Forever: a strike with a 20 s cooldown, learned at level 1 (DB2 1310222).
+    -- Forever: a strike with a 20 s cooldown, an Arms talent (node 1310222; the DB2's level 1 is not the gate).
     spearing_strike = {
         id = 1310222,
         cast = 0,
         cooldown = 20,
         gcd = "spell",
 
-        spend = 15,
+        spend = function () return offensive_cost( 15 ) end,
         spendType = "rage",
 
         startsCombat = true,
+        talent = "spearing_strike",
         known = knows( { 1310222 } ),
         buff = "battle_stance",
     },
@@ -1174,7 +1153,7 @@ spec:RegisterAbilities( {
         cooldown = 0,
         gcd = "spell",
 
-        spend = function () return max( 0, 15 - 3 * talent.improved_sunder_armor.rank ) end,
+        spend = function () return offensive_cost( max( 0, 15 - 3 * talent.improved_sunder_armor.rank ) ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -1207,7 +1186,7 @@ spec:RegisterAbilities( {
     taunt = {
         id = 355,
         cast = 0,
-        cooldown = function () return 8 - talent.improved_taunt.rank end, -- Improved Taunt: -1 s a rank (both in the DB2)
+        cooldown = 8,
         gcd = "off",
 
         startsCombat = true,
@@ -1226,7 +1205,7 @@ spec:RegisterAbilities( {
         cooldown = 6,
         gcd = "spell",
 
-        spend = function () return max( 0, 20 - 6 * talent.improved_thunder_clap.rank ) end,
+        spend = function () return offensive_cost( max( 0, 20 - 6 * talent.improved_thunder_clap.rank ) ) end,
         spendType = "rage",
 
         startsCombat = true,
@@ -1258,7 +1237,7 @@ spec:RegisterAbilities( {
         cooldown = 10,
         gcd = "spell",
 
-        spend = 25,
+        spend = function () return offensive_cost( 25 - 3 * talent.raging_blows.rank ) end, -- Raging Blows: -3
         spendType = "rage",
 
         startsCombat = true,
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `130 successes / 0 failures / 0 errors`. Then confirm no removed talent is still read: `grep -n 'improved_cleave\|improved_taunt\|improved_shield_block\|axe_specialization\|mace_specialization\|sword_specialization\|polearm_specialization\|improved_demoralizing_shout\|improved_battle_shout\|toughness\|Track' Forever/Warrior.lua` prints nothing.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [130 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 65 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Warrior.lua .luacheckrc Forever/spec/warrior_spec.lua
git commit -m "fix(forever): the 52 live Warrior talents (removed ones dropped, no rank aliases); Raging Blows and Focused Rage costs; Spearing Strike talent-gated; Vanguard's Charge; Overpower on the plain usability read

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-warrior-profile`

---

### Task 4: Rage per hit for both hands, Anger Management, and the class-file housekeeping (forever-warrior-profile)

The main-hand entry's value was `rageRate() x speed / haste` (4.5 or 3.46 rage per second of weapon speed, TDF's numbers): blind to the weapon's damage, the level and the off hand, so at the last checkpoint Hekili read 47 against a bar of 100 (ledger, Q9). Forever is vanilla-based, so the default rage per hit is vanilla's damage term alone, per hand: average damage / c(level) x 7.5 (c(level) = 0.0091 level² + 3.23 level + 4.27); TBC's weapon-speed term, hit factor x unhasted weapon speed / 2 (3.5 main, 1.75 off), sits behind the file constant `RAGE_SPEED_TERM = 0` (1 adds it) for the checkpoint to decide. The off-hand damage is the client's, already halved by the off-hand penalty (the pane shows `UnitDamage`'s returns 3-4 as is), so no extra 0.5. The inputs come from `VS.Stat( "UnitDamage" )` (VirtualState's out-of-combat cache; `UnitDamage` is `SecretWhenUnitStatsRestricted`, Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:1047-1051) and the plain `UnitLevel( "player" )`; Dual Wield Specialization x (1 + 0.1 x rank) on the off hand; Unbridled Wrath + 0.12 x rank on both (12% a rank for 1 rage: 60% at 5/5, the export's tooltip). Before the first plain damage read (zeros) the main hand keeps the old rate and the off hand brings nothing. A new `offhand` entry (Hekili's own forecast models `swing = "offhand"` entries, State.lua:1214-1225) and an `anger_management` entry (combat-gated, talent-gated, Task 2) join `mainhand` and `bloodrage`. Housekeeping (A6): the dead `overpower_enabled`/`overpower_threshold` settings go (no pack names them since the stance-swap entries were removed), the header names the client build and the export, and the Warrior plan's Task 4 gets its one-line "superseded" note.

**Files:**
- Modify: `Forever/Warrior.lua` (header :2-5 and the credit :13, locals :17 and :22, `rageRate` :86-94 plus `rageOf`, `RegisterResource` :96-135 (`mainhand`'s value, `offhand`, `anger_management`), the settings comment :1336-1338 and `overpower_enabled`/`overpower_threshold` :1373-1388)
- Modify: `docs/superpowers/plans/2026-10-15-forever-warrior-profile.md` (one line under `### Task 4`, :2304)
- Test: `Forever/spec/helpers/load_warrior.lua` (`game.damage`, `game.level`, fakes `UnitLevel` and `ns.VirtualState.Stat`), `Forever/spec/warrior_spec.lua` (three cases before "gains Bloodrage's rage over time …")

**Interfaces:**
- Consumes: Task 2's adapter forwarding (`offhand` → `swingOff`, `anger_management` → a combat-gated `auraRegen` entry with `talent`); Task 3's talent keys; `VS.Stat( apiName )` (Families/Player.lua: the seven cached plain returns, zeros before the first read); Hekili's `state.mainhand_speed`, `state.offhand_speed`, `state.haste`, `state.swings.offhand`, `state.combat`, `state.query_time`, `state.talent`.
- Produces: `rageOf( hand )` (file-local; allocates nothing); Hekili regen-model entries `mainhand`, `offhand`, `bloodrage`, `anger_management`.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply`:

```diff
diff --git a/Forever/spec/helpers/load_warrior.lua b/Forever/spec/helpers/load_warrior.lua
index 799d3ab4..caaae475 100644
--- a/Forever/spec/helpers/load_warrior.lua
+++ b/Forever/spec/helpers/load_warrior.lua
@@ -1,7 +1,8 @@
 -- Forever/spec/helpers/load_warrior.lua
 -- Loads Forever/Warrior.lua headless against a recording stand-in for Hekili: every spec:RegisterX call is kept by
 -- method name, ns.VirtualState.Track's tables are merged, and the plain game reads the file captures at load answer
--- from `game` (known spells, queued spells, usability, the shapeshift form). `env()` is a stand-in `state` for running
+-- from `game` (known spells, queued spells, usability, the shapeshift form, the level, VirtualState's cached weapon
+-- damage). `env()` is a stand-in `state` for running
 -- the file's handlers, state functions and hooks (Hekili runs them with setfenv( f, state )).
 local M = {}
 
@@ -19,7 +20,16 @@ function M.load()
             end
         end,
     })
-    local game = { known = {}, current = {}, usable = {}, noMana = {}, form = 0, formSpell = {} }
+    local game = {
+        known = {},
+        current = {},
+        usable = {},
+        noMana = {},
+        form = 0,
+        formSpell = {},
+        damage = { 0, 0, 0, 0 }, -- UnitDamage's first four returns in VirtualState's stat cache
+        level = 22,
+    }
     local w = { game = game, abilities = {}, auras = {}, track = {}, hooks = {}, funcs = {}, exprs = {} }
     w.state = { main_hand = { size = 2 }, timeToInterrupt = function() end }
     local hekili = { State = w.state }
@@ -51,6 +61,9 @@ function M.load()
         GetShapeshiftFormInfo = function(i)
             return 0, true, true, game.formSpell[i]
         end,
+        UnitLevel = function()
+            return game.level
+        end,
         Enum = { PowerType = { Rage = 1 } },
     }
     local saved = {}
@@ -65,6 +78,13 @@ function M.load()
                     w.track[k] = v
                 end
             end,
+            Stat = function(name)
+                if name ~= "UnitDamage" then
+                    return 0, 0, 0, 0, 0, 0, 0
+                end
+                local d = game.damage
+                return d[1], d[2], d[3], d[4], 0, 0, 1
+            end,
         },
     }
     local ok, err = pcall(assert(loadfile("Forever/Warrior.lua")), "Hekili", ns)
diff --git a/Forever/spec/warrior_spec.lua b/Forever/spec/warrior_spec.lua
index 50ac191f..090ed3c5 100644
--- a/Forever/spec/warrior_spec.lua
+++ b/Forever/spec/warrior_spec.lua
@@ -221,6 +221,41 @@ describe("Forever Warrior", function()
         end
     end)
 
+    it("gains rage per hit per hand by vanilla's damage formula from the cached weapon damage and the level", function()
+        local models = w.resource[2]
+        w.state.mainhand_speed, w.state.offhand_speed, w.state.haste = 2.6, 1.8, 1
+        w.state.talent = rank(0)
+        w.game.damage = { 40, 60, 15, 25 } -- averages 50 and 20
+        local c = 0.0091 * 22 * 22 + 3.23 * 22 + 4.27 -- 79.7344 at level 22
+        local mh, oh = 50 / c * 7.5, 20 / c * 7.5 -- no weapon-speed term (RAGE_SPEED_TERM = 0)
+        assert.is_true(math.abs(models.mainhand.value() - mh) < 1e-9)
+        assert.is_true(math.abs(models.offhand.value() - oh) < 1e-9)
+        w.state.talent = setmetatable({
+            unbridled_wrath = { rank = 5, enabled = true }, -- 60%: 0.6 rage a hit, both hands
+            dual_wield_specialization = { rank = 3, enabled = true }, -- +30% off-hand rage
+        }, getmetatable(rank(0)))
+        assert.is_true(math.abs(models.mainhand.value() - (mh + 0.6)) < 1e-9)
+        assert.is_true(math.abs(models.offhand.value() - (oh * 1.3 + 0.6)) < 1e-9)
+        assert.are.same({ "offhand", "offhand_speed" }, { models.offhand.swing, models.offhand.interval })
+    end)
+
+    it("falls back to the weapon-speed rate before the weapon damage is cached", function()
+        local models = w.resource[2]
+        w.state.mainhand_speed, w.state.offhand_speed, w.state.haste = 3, 0, 1
+        w.state.talent = rank(0)
+        assert.are.same({ 4.5 * 3, 0 }, { models.mainhand.value(), models.offhand.value() })
+    end)
+
+    it("gains Anger Management's rage every 3 s in combat through a combat-gated periodic entry", function()
+        local am = w.resource[2].anger_management
+        assert.are.same({ "anger_management", 3, 1 }, { am.talent, am.interval, am.value })
+        assert.is_nil(am.aura)
+        w.state.combat, w.state.query_time = 100, 107.5
+        assert.are.same({ 106, false }, { am.last(), am.stop() })
+        w.state.combat = 0
+        assert.is_true(am.stop())
+    end)
+
     it("gains Bloodrage's rage over time through an aura-gated regen entry", function()
         local models = w.resource[2]
         assert.are.equal(1, w.resource[1])
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `130 successes / 1 failure / 2 errors`: `warrior_spec.lua @ 224` (the main hand still uses the rate), errors `@ 242` and `@ 249` (no `offhand`, no `anger_management` entry).

- [ ] **Step 3: Write the implementation**

Apply with `git apply`:

```diff
diff --git a/Forever/Warrior.lua b/Forever/Warrior.lua
index 112c208d..cb2aa460 100644
--- a/Forever/Warrior.lua
+++ b/Forever/Warrior.lua
@@ -1,8 +1,9 @@
 -- Forever/Warrior.lua
 -- The Forever Warrior (pseudo-spec 1491): the Classic Warrior kit with Forever's spell data (ranks, costs, cooldowns,
--- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb; a cost of 100 there is 10 rage), Forever's
--- Victory Rush and Spearing Strike, rage with its main-hand swing model and Bloodrage's rage over time, stances from
--- the plain shapeshift reads, and the default priorities.
+-- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb, a cost of 100 there being 10 rage; the
+-- client is 1.60.1.70374, and its export wins where they differ), Forever's Victory Rush and Spearing Strike, rage per
+-- hit for both hands, Bloodrage's and Anger Management's rage over time, stances from the plain shapeshift reads, and
+-- the default priorities.
 -- Talents: the 52 live nodes (a ForeverProbe export of the client, 1.60.1.70374, 2026-10-15). Only rank 1 of each
 -- talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank (Classic's own convention), floored
 -- at 0; no cooldown or duration modifier is modelled. The in-game checkpoint compares the costs (Snapshot cost= /
@@ -11,16 +12,17 @@
 -- Credits: Hekili (registration API and pack format); the abilities, auras, stance swap, queue prediction and the Arms
 -- and Fury priorities are ported from Hekili's Classic profile (origin/classic:Classic/Warrior.lua,
 -- Classic/APLs/WarriorArms.simc, Classic/APLs/WarriorFury.simc); call shapes from archive/TheWarWithin/WarriorArms.lua.
--- Rage per swing from Taco Dog Forever's Warrior pack (src/TacoDogForever_Warrior/Warrior.lua:21-24).
+-- The fallback rage rate from Taco Dog Forever's Warrior pack (src/TacoDogForever_Warrior/Warrior.lua:21-24).
 
 local addon, ns = ...
 local C_SpellBook, C_Spell, UnitClassBase = C_SpellBook, C_Spell, UnitClassBase
-local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
+local GetShapeshiftForm, GetShapeshiftFormInfo, UnitLevel = GetShapeshiftForm, GetShapeshiftFormInfo, UnitLevel
 local Hekili = _G[ addon ]
 
 if UnitClassBase( "player" ) ~= "WARRIOR" then return end
 
 local state = Hekili.State
+local VS = ns.VirtualState
 local IsSpellKnown, IsCurrentSpell, IsSpellUsable = C_SpellBook.IsSpellKnown, C_Spell.IsCurrentSpell, C_Spell.IsSpellUsable
 local floor, max, min, sort = math.floor, math.max, math.min, table.sort
 
@@ -92,14 +94,40 @@ local function usableNow( ids )
     return r > 0 and IsSpellUsable( ids[ r ] ) == true
 end
 
--- Rage a second of the main hand's unhasted weapon speed: a white swing brings rate x that speed (haste adds swings,
--- never rage per swing): 4.5 for a two-hander, 3.46 for a one-hander (Hekili's gear scan sets main_hand.size).
--- shortcut: no off-hand swing source (VirtualState models one swing-paid hand), so a dual wielder's off hand is left
--- to VirtualState's calibration; upgrade when the resources family takes a second hand.
+-- Rage a second of the main hand's unhasted weapon speed before the weapon damage is cached: a white swing brings
+-- rate x that speed: 4.5 for a two-hander, 3.46 for a one-hander (Hekili's gear scan sets main_hand.size).
 local function rageRate()
     return state.main_hand.size == 1 and 3.46 or 4.5
 end
 
+-- Rage per white hit, vanilla's formula: 7.5 x average weapon damage / c(level), c(level) = 0.0091 level^2 +
+-- 3.23 level + 4.27. TBC's adds a weapon-speed term, hit factor x unhasted weapon speed / 2 (hit factor 3.5 main
+-- hand, 1.75 off hand), with half the damage term; RAGE_SPEED_TERM = 1 adds that term to vanilla's (the checkpoint
+-- decides). The damage is UnitDamage's (VirtualState's out-of-combat cache: secret in combat), whose off-hand range
+-- already carries the off-hand penalty (the character pane shows it as is), so it is not halved again. Dual Wield
+-- Specialization +10% off-hand rage a rank; Unbridled Wrath 12% a rank for 1 rage a hit, both hands (60% at 5/5,
+-- Forever's tooltip).
+-- shortcut: misses, dodges and crits are ignored (every swing counts as an average hit); VirtualState's calibration
+-- scale absorbs the difference. Upgrade if the checkpoint's rage estimate drifts by more than 10.
+local RAGE_SPEED_TERM = 0
+local HIT_FACTOR = { 3.5, 1.75 }
+
+local function rageOf( hand )
+    local speed = hand == 1 and state.mainhand_speed or state.offhand_speed
+    local haste = state.haste
+    if haste and haste > 0 then speed = speed / haste end
+    local lo, hi, offLo, offHi = VS.Stat( "UnitDamage" )
+    local damage = hand == 1 and ( lo + hi ) / 2 or ( offLo + offHi ) / 2
+    if damage <= 0 then
+        return hand == 1 and rageRate() * speed or 0 -- no plain damage read yet
+    end
+    local level = UnitLevel( "player" )
+    local rage = damage / ( 0.0091 * level * level + 3.23 * level + 4.27 ) * 7.5
+        + RAGE_SPEED_TERM * HIT_FACTOR[ hand ] * speed / 2
+    if hand == 2 then rage = rage * ( 1 + 0.1 * state.talent.dual_wield_specialization.rank ) end
+    return rage + 0.12 * state.talent.unbridled_wrath.rank
+end
+
 spec:RegisterResource( Enum.PowerType.Rage, {
     mainhand = {
         swing = "mainhand",
@@ -114,7 +142,39 @@ spec:RegisterResource( Enum.PowerType.Rage, {
         interval = "mainhand_speed",
 
         stop = function () return state.swings.mainhand == 0 end,
-        value = function () return rageRate() * state.mainhand_speed / state.haste end,
+        value = function () return rageOf( 1 ) end,
+    },
+
+    offhand = {
+        swing = "offhand",
+
+        last = function ()
+            local swing = state.swings.offhand
+            local t = state.query_time
+            if state.offhand_speed == 0 then return 0 end
+            return swing + floor( ( t - swing ) / state.offhand_speed ) * state.offhand_speed
+        end,
+
+        interval = "offhand_speed",
+
+        stop = function () return state.swings.offhand == 0 end,
+        value = function () return rageOf( 2 ) end,
+    },
+
+    -- Anger Management (12296): 1 rage every 3 s in combat (DB2 m2 = 1, m3 = 3), from the combat start.
+    anger_management = {
+        talent = "anger_management",
+
+        last = function ()
+            local start = state.combat
+            if start == 0 then return state.query_time end
+            return start + floor( ( state.query_time - start ) / 3 ) * 3
+        end,
+
+        interval = 3,
+
+        stop = function () return state.combat == 0 end,
+        value = 1,
     },
 
     -- Bloodrage's aura (29131): 1 rage every second for 10 s (DB2 effect: periodic energize 10 every 1000 ms).
@@ -1313,8 +1373,8 @@ spec:RegisterStateExpr( "should_cleave", function()
 end )
 
 -- The Classic settings the Arms and Fury priorities read (Classic/Warrior.lua:1574-1734, same defaults). Left out:
--- adaptive Whirlwind and Bloodthirst-in-execute (they need attack power and weapon damage, secret on Forever) and the
--- unused queueing threshold.
+-- adaptive Whirlwind and Bloodthirst-in-execute (they need attack power and weapon damage, secret on Forever), the
+-- unused queueing threshold, and the Overpower stance-swap settings (the dodge is unseen from another stance).
 spec:RegisterSetting( "adaptive_queueing_enabled", true, {
     type = "toggle",
     name = "Use Queue Prediction",
@@ -1349,23 +1409,6 @@ spec:RegisterSetting( "ww_cd_diff", 1.5, {
     step = 0.1,
 } )
 
-spec:RegisterSetting( "overpower_enabled", true, {
-    type = "toggle",
-    name = "Use Overpower",
-    desc = "When enabled, recommendations will include swapping to Battle Stance for Overpower.",
-    width = "full",
-} )
-
-spec:RegisterSetting( "overpower_threshold", 45, {
-    type = "range",
-    name = "Maximum Rage for Overpower",
-    desc = "Select the maximum rage allowed for a stance swap to Overpower.",
-    width = "full",
-    min = 1,
-    max = 100,
-    step = 1,
-} )
-
 spec:RegisterSetting( "hamstring_threshold", 80, {
     type = "range",
     name = "Hamstring Rage Threshold",
diff --git a/docs/superpowers/plans/2026-10-15-forever-warrior-profile.md b/docs/superpowers/plans/2026-10-15-forever-warrior-profile.md
index 22635518..b77d6495 100644
--- a/docs/superpowers/plans/2026-10-15-forever-warrior-profile.md
+++ b/docs/superpowers/plans/2026-10-15-forever-warrior-profile.md
@@ -2303,6 +2303,8 @@ Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
 
 ### Task 4: The Arms, Fury and Protection priorities, queue prediction and the Classic settings
 
+> The `should_queue` and `mainhand_remains` code blocks below are superseded by f728e30f (the final fix wave).
+
 `tools/make_pack.lua` becomes the source of the three priorities: each is SimC-style text, parsed into Hekili's list entries (`action`, `enabled`, `criteria`, `list_name`, `use_off_gcd`, the shape Hekili's own importer stores, as the decoded Classic packs show) and printed as a share string, one line per pack. The class file registers the three strings (`RegisterPack`, one spec 1491; Hekili picks the default from `RegisterOptions`' `package`, here Arms; `/hekili priority <name>` switches, `Options/ChatCommands.lua:586-655`).
 
 Arms and Fury are Classic's lists (Classic/APLs/WarriorArms.simc, WarriorFury.simc) with these changes, each for a reason on Forever: `target.health.pct<=20` becomes `execute_phase` (a state expression on Execute's plain usability; the target's health always reads 100, Task 9b's warning); the `cooldowns` list Classic called but never defined is defined (Arms: Sweeping Strikes with two or more enemies, Death Wish, Recklessness; Fury: Death Wish, Recklessness; each is talent-, stance- or toggle-gated by its ability) and called on bosses or targets 3 levels above (`boss|target.level>=level+3`; Classic's `target.level>=63` assumed level 60); Classic's `rage.current>hamstring_threshold` reads the setting (`settings.hamstring_threshold`; the bare name was undefined); Fury's `bloodthirst,if=…bt_over_exec&target.time_to_die>2` and `whirlwind,if=active_enemies>=ww_breakpoint` lose the secret inputs (attack power, weapon damage, time to die): the first is dropped, the second reads `settings.ww_min_enemies` (which `ww_breakpoint` returned with adaptive Whirlwind off, its default); a precombat Battle Shout; and three Forever additions in the rotation: Victory Rush first (free, after a kill), Spearing Strike after the main strike, Rend while Mortal Strike (Arms) or Bloodthirst (Fury) is not talented (leveling below 40). Protection is provisional, in the War Within Protection list's shape (`archive/TheWarWithin/Priorities/WarriorProtection.simc:5-60`: interrupt, mitigation, `run_action_list,name=aoe` at three or more enemies, `call_action_list,name=generic`): Shield Bash, Defensive Stance, Victory Rush, Shield Block, Bloodrage below 20 rage, Battle Shout; then Revenge, Shield Slam (only when known), Sunder Armor to 5 stacks or when it runs low, Heroic Strike (Cleave in the aoe list) as the rage dump.
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `133 successes / 0 failures / 0 errors`. The packs are unchanged: `git diff --quiet HEAD -- tools/make_pack.lua && echo unchanged` prints `unchanged`, and the spec "registers the Arms, Fury and Protection priorities exactly as tools/make_pack.lua prints them" passes with version 20261016.

- [ ] **Step 5: Verify**

```bash
cd ~/src/hekili/.claude/worktrees/forever-warrior-profile
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [133 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 65 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 43 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                          # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | xargs -r -n1 luac5.1 -p   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Forever/Warrior.lua Forever/spec/helpers/load_warrior.lua Forever/spec/warrior_spec.lua \
  docs/superpowers/plans/2026-10-15-forever-warrior-profile.md
git commit -m "feat(forever): Warrior rage per hit for both hands (vanilla's damage formula from the cached weapon damage, DWS, Unbridled Wrath; TBC's speed term off); Anger Management; dead Overpower settings removed

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-warrior-profile`

---

### Task 5: CHECKPOINT: the accuracy pass in game

No code. The orchestrator presents this checkpoint; the user runs the game on the Warrior (the character the export came from: level 22, Fury points: Dual Wield Specialization 3/5, Blood Craze 1/3, Piercing Howl 1/1, Unbridled Wrath 5/5, Cruelty 5/5, Furious Precision 3/3). ForeverProbe must be loaded (`VSCopy`, `/vscopy` reopens the box).

- [ ] **Step 1: Point the client at the branch**

```bash
git -C ~/src/hekili checkout --detach forever-warrior-profile
```

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, and report each answer**

1. `/reload`. Expected: no Lua error. `/hekili priority fury`. Expected: `Priority set to Fury.`
2. Out of combat: `/run VSCopy(Hekili.VirtualState.Snapshot())`, paste the box. Expected: `talent walk unmatched: 0`; exactly 52 `talent <key> spell=<id> rank=<n>/<max>` lines, matching the pane, among them `furious_precision spell=1323963 rank=3/3`, `unbridled_wrath spell=12322 rank=5/5`, `cruelty spell=12320 rank=5/5`, `dual_wield_specialization spell=23584 rank=3/5`, `blood_craze spell=16487 rank=1/3`, `piercing_howl spell=12323 rank=1/1`, every other node `0/<its max>`; `resource RAGE type=1 max=100 swing=1 … auraRegen=2`; `ability overpower qid=7384 cost=5 read=5 … multi=true`; `read aura walk player: readable` (absent before this plan when no tracked aura was up).
3. Out of combat: `/run local a,b,c,d=Hekili.VirtualState.Stat("UnitDamage") VSCopy(format("mh %.1f-%.1f oh %.1f-%.1f",a,b,c,d))`. Compare with the character pane's main-hand and off-hand damage (hover the damage line). Expected: the same ranges; the off hand's as the pane shows it (already reduced).
4. First, out of combat: cast Battle Shout and wait a second (the attack-power change re-reads the cached weapon damage), and do not level up or swap weapons during this item. Then in combat on a training dummy, auto-attacking only, at about 40 rage on the bar: `/run VSCopy(format("hekili %.1f vs %.1f",Hekili.State.rage.current,Hekili.VirtualState.Power(1,GetTime()).est))`, and write down the bar's number. Then keep auto-attacking (no spenders) until the bar is near 100 and run the same line again. Expected: both numbers within 10 of the bar both times.
5. Spearing Strike (talent not bought): over 60 s of the Fury priority, is Spearing Strike ever recommended? Expected: never.
6. Overpower: in Battle Stance on the dummy, before any dodge, is Overpower recommended? Expected: no. After the dummy dodges (the "Dodge" text; the action button lights), is it recommended within a few seconds? Expected: yes, and gone once used or after its window.
7. Anger Management: the character has 0/1 (Arms), so this cannot be seen on it: report "not taken". If a character has it: in combat at 0 rage, standing out of melee range (no swings), does the bar tick up by 1 every 3 s, and does the line from item 4 follow it?
8. Focused Rage (a guess, see Task 3): only on a character that has it: run the Snapshot line from item 2 and compare `cost=` with `read=` on every rage spender.

| # | Answer → action (each action its own commit with the verification block) |
|---|---|
| 2 | A talent line missing, extra or with another spell/max → change that row in `RegisterTalents` and in `TALENTS` (`Forever/spec/warrior_spec.lua`) to the pane's; `talent walk unmatched: N [ids]` → each id is a node's definition at a rank: register it, or (if it is another rank of a registered node) add a `ns.VirtualState.Track( { talents = { [ id ] = <registered spell> } } )` entry and a spec row. `auraRegen=1` → the adapter did not forward `anger_management`: stop and report (Task 2 regression). `multi=false` on Overpower → its cost list has one entry in this build: Overpower rejoins the ladder by itself; note it. |
| 3 | Zeros → the stat cache has no plain read (Snapshot's `read stats:` line says `secret`): the formula falls back to the old rate; stop and report (a sources question, outside this plan). Off hand twice the pane's, or half → the client's `UnitDamage` off-hand range is not the pane's: halve or double it in `rageOf` and in the spec's expected value. |
| 4 | Within 10 both times → none. VirtualState's `est` within 10 but `hekili` not → Hekili's own forecast (`state.rage.current` at reset comes from the facade's rage, so a difference is the forecast window): record the numbers, no change. `est` low by roughly the weapon-speed term (3.5 x main-hand speed / 2 a main-hand swing, 1.75 x off-hand speed / 2 an off-hand one, times the swings since the last rung) → set `RAGE_SPEED_TERM = 1` in `Forever/Warrior.lua` and the spec's expected values to include the term. High by more than 10 → lower the Unbridled Wrath (0.12 a rank) or Dual Wield Specialization (0.1 a rank) factors, whichever the item-3 damage and the swing counts point at, and their spec values. Both below by more than 10 at 100 but not at 40 → the belief cannot correct above its highest usable rung (known limit): record it. |
| 8 | Focused Rage's list is a guess: if a character with Focused Rage is available, compare Snapshot's `cost=` with `read=` for each spender; every mismatch (`read` lower than `cost` on an ability without `offensive_cost`, or equal to the base where it has it) → add or remove that ability's `offensive_cost` call. Without one: report "not taken". |
| 5 | Recommended → `talent = "spearing_strike"` is not stopping it: report the Snapshot `talent spearing_strike` line and the ability line. |
| 6 | Recommended before a dodge → the client's flag is true without a dodge: report `/run VSCopy(tostring(C_Spell.IsSpellUsable(7384)))` before a dodge. Never recommended after a dodge → the same line inside the window. |
| 7 | Ticks not believed → report the `resource RAGE …` line and `talent anger_management …`. |

Known limits (say them to the user with the results): above the highest usable rung the belief cannot self-correct (no spender's answer bounds it); the formula ignores misses, dodges, parries and crits (every swing an average hit) and armour (damage before mitigation: armoured targets read high), which VirtualState's swing-scale calibration absorbs and Hekili's forecast does not; the weapon damage is read out of combat only, so a weapon swap or level-up in combat leaves it stale until combat ends; Overpower's two-cost flag is read out of combat only (a `/reload` in combat puts it back on the ladder until combat ends); Overpower's window is the client's usability flag "now" until the virtual event facade delivers the dodge event, so Hekili cannot plan for it ahead of time.

Fix what the user reports (each fix its own commit, then the verification block), then repeat the affected lines. Continue only when the user confirms. Then `git push origin forever-warrior-profile`. When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

**1. Coverage of the rulings and the reconciliation**

| Requirement | Where |
|---|---|
| A1 52 live nodes, export IDs and max ranks, 9 new keys, 10 removed dropped with their readers replaced or deleted, aliases decided from the export | Task 3 (`TALENTS` pins all 52; the grep in Step 4; "Rulings applied" A1 says what was found) |
| A2 Spearing Strike talent-gated | Task 3 ("gates Spearing Strike on its talent …"); Task 5 item 5 |
| A3 Vanguard | Task 3 (same case) |
| A4 two-hand swing income in VirtualState (zero allocation, resources_spec); periodic combat-gated regen forwarded (a case); the formula per hand from the stat cache and level; DWS; Unbridled Wrath; Anger Management; Hekili's own model both hands | Task 1 (three resources cases), Task 2 (adapter and resources cases), Task 4 (three warrior cases); Task 5 items 3, 4, 7 |
| A5 multi-cost exclusion with a spec; Overpower's rage spend stays | Task 1 (facts and casts cases; spend unchanged in KIT) |
| A6 dead Overpower settings; WALK for a third unit; clean walk readable; GCD bound; header build note; the Warrior plan's stale Task 4 note | Task 1 (auras and casts cases), Task 4 (settings, header, plan line) |
| A7 one checkpoint: 52 talents incl. the six owned; rage within 10 at ~40 and ~100 with the two values; Spearing Strike never; Overpower after a dodge; Anger Management or "not taken"; VSCopy lines under 255; known limits | Task 5 |
| A8 Overpower `usable` = the plain read, comment, out of the ladder, no stance-swap entries, spec case, checkpoint before/after a dodge | Task 3 (case and code), Task 1 (ladder), Task 5 item 6 |
| Review round (I1, M1-M5, N1-N4): stats re-read out of combat on UNIT_DAMAGE/UNIT_ATTACK_POWER/PLAYER_LEVEL_UP (I1); the adapter drops entries with gates it cannot see (M1); the combat flag seeded at build (M2); the Focused Rage rule narrowed to the list (M3); armour, in-combat staleness and `multiCost`'s out-of-combat read named as limits (M4, M5, I1); the merge commit's trailer (N1); `reactive`'s comment (N2); the pane citation (N3); N4 needs no change | Task 1 (player_spec case), Task 2 (adapter and resources cases), Task 3, "Named, not test-pinned", Task 5 item 4 and known limits |
| Reconcile: tree placement notes (Improved Thunder Clap Protection, Improved Slam Arms); Bastion key; DB2 vs client build | Task 3 (section comments and the Bastion comment), Task 4 (header) |
| Reconcile's other recommendations not taken: Bloodthrill's Overpower window (A9 withdrawn; the dodge event plan); Master of Defense, Lingering Rage (no per-rank numbers) | "Order and checkpoint" |

**2. Placeholder scan:** no "TBD", "TODO", "implement later" or "similar to Task N"; every code step is a `git apply` patch generated from the replay; every command has its replay output.

**3. Names and types across tasks:** `swingOff` (Task 1 family field, Task 2 adapter output), `I.SwingValue(r, hand)`, `I.SwingPerSecond(r)`, `I.ab.multiCost`, `I.res.auraRegen.talent`, `offensive_cost`, `usableNow`, `rageOf`, the regen-model keys `mainhand`/`offhand`/`bloodrage`/`anger_management`, and the talent keys `unbridled_wrath`/`dual_wield_specialization`/`anger_management`/`raging_blows`/`focused_rage`/`vanguard`/`spearing_strike` are spelled the same in every task, spec and Snapshot line above.

**4. Review Focus:** each of the five lines has its pinned test in the owning task (Tasks 1, 2, 3, 4).

**Concerns for the orchestrator:** (a) Task 2 is VirtualState code on the Warrior branch, because the aura-gated regen it extends was committed only there (Warrior plan Task 1); merging `forever-warrior-profile` into `forever` brings it along with Phase 1. (b) Settled by ruling: vanilla's damage term is the default; TBC's weapon-speed term is behind `RAGE_SPEED_TERM = 0`, and checkpoint item 4 decides it. (c) The Focused Rage ability list is a guess, marked `shortcut:` in the code and checked by checkpoint item 8.

Checkpoint 2026-10-15 (Task 5, item 4): level 22, 2.2 s main hand, Unbridled Wrath 5/5, main-hand hits of 38/40/44 damage gave 8/9/10 rage (damage term alone predicts ~4.4, with the speed term ~8.2), so `RAGE_SPEED_TERM` is now 1 and the spec's expected values include the term.
