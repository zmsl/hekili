# Forever Protection Warrior Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rage from damage taken reaches both halves of the model. VirtualState sees every hit on the player (`UNIT_COMBAT`, plain) as a `PlayerHit` observation, credits the rage a class's paying entry declares for it (`taken`), and learns the incoming rate; Hekili's forecast steps that rate as a generated `__taken` regen entry. Shield Block's two blocks become aura stacks spent by blocks (`consumedBy`). Generic `threat.*` reads let a priority taunt. The Warrior file declares the rage of a hit (armor, block value, Defensive Stance and Shield Wall divided back, Shield Specialization and Master of Defense as expected values), and the Protection priority runs threat first, Shield Block kept up, and Heroic Strike and Cleave at user-set rage thresholds. No defensives, no current-health model.

**Architecture:**
- **Task 1 (source):** `Obs.PlayerHit = 36` and `I.HitKind`/`I.HitName` (VirtualState.lua); Sources/Player.lua stages every player `UNIT_COMBAT` with its kind, amount and attacker level; the stat cache gains `GetShieldBlock`.
- **Task 2 (belief):** Families/Resources.lua applies a slot's `taken` on `PlayerHit` kinds 1-6 (est, lo, hi by the half-width; `R.gain` and `R.pinDelta`), keeps ten one-second bins and answers `VS.TakenRate`; Families/Now.lua's `I.NowAt(t)` makes the `now` context read the belief at the hit; the Adapter forwards the paying entry's `taken`.
- **Task 3 (sim):** Adapter.lua generates `regenModel.__taken` (interval 1, value `VS.TakenRate`, `stop` out of combat); the walk skips it.
- **Task 4 (auras):** Families/Auras.lua spends one stack of a `consumedBy` player aura per listed `PlayerHit`, the aura down at 0.
- **Task 5 (threat):** Engine/Spec.lua's `all` spec registers the `threat` state table (`situation`, `on_me`, `lost`, `loose`); Events/Attackers.lua answers `VS.LooseEnemies()`; Facade.lua exports `issecretvalue`.
- **Task 6 (Warrior kit):** the `mainhand` entry's `taken`, Shield Block's aura `max_stack = 2` and `consumedBy`, its `now`/`handler` applying 2 stacks, the talent comments, the 2026-10-16 talent dump in docs/research.
- **Task 7 (priority):** the three settings, the Protection list in tools/packs/warrior.lua, the regenerated `RegisterPack("Protection", ...)`.
- **Task 8:** the in-game CHECKPOINT (design §5.2, with the user's rulings), deferred to the user.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, StyLua, `lua5.1` (tools/make_pack.lua), `make check` (Makefile: lint, fmt-check, typecheck, test, syntax, api-check).

**Spec:** `docs/superpowers/specs/2026-10-16-forever-protection-design.md` (binding), as amended by the user's rulings of 2026-10-16 below. Every other deviation is listed with its evidence.

### User rulings 2026-10-16 (they override the design text)

| Ruling | Design text it replaces | Where |
|---|---|---|
| R1 Rage from damage taken comes from the UNREDUCED hit: the observed amount is divided by the armor reduction and, while their auras are up, by Defensive Stance's 0.9 and Shield Wall's factor (0.4, design §1.3). No `RAGE_BEFORE_REDUCTION` constant. | §1.3 `TAKEN_SCALE` behind `RAGE_BEFORE_REDUCTION`; D1; checkpoint Q5 as the decider | Task 6; Q5 becomes a sanity read (Task 8) |
| R2 The sub-170-armor doubling is not modelled (as the design). | — | Task 6 (`shortcut:` comment naming Q6 and D2) |
| R3 Heroic Strike 50, Cleave 40, Challenging Shout 3 are user settings; no health threshold anywhere (as the design). | — | Task 7 |
| R4 Mocking Blow only in Battle Stance (as the design: its `buff = "battle_stance"` already gates it). | — | Task 7 |
| R5 Shield Specialization: a 20% chance a rank to gain 5 rage on a block (20-100% at ranks 1-5); Master of Defense: 50% a rank on a dodge or parry with a shield (50/100%). Tooltips read in game; modelled as expected values (chance x 5), the band carrying the spread (half-width max(p, 1 - p) x 5). | §1.3 "p = 1 (the rank-1 row's 100%)"; D5 | Task 6; checkpoint Q9 is answered |
| R6 The live talent dump (`docs/research/2026-10-16-warrior-talent-dump.md`, copied in Task 6 from the job's `tmp/prot/talent-dump-2026-10-16.md`): 52 nodes, no Improved Shield Block, Improved Taunt or Toughness, Defiance max 3, Bastion 16538. D6 stands; no registration changes and no talent question at the checkpoint. | — | Task 6 (header comment and the dump file) |

### Deviations from the design (each measured or read, not guessed)

1. **`I.NowContext` is the existing `I.nowCtx`, and the context needs a clock.** Families/Now.lua already exposes the context as `I.nowCtx` (Now.lua:43). Its `buff`/`talent` proxies read the belief at Now.lua's private `T`, which only a cast sets; a `taken` run at a hit would read the last cast's time. Task 2 adds `I.NowAt(t)` (sets `T` and the context's `now`), called before each `taken`.
2. **A `taken` gain goes into `R.pinDelta` as well as `R.gain`** (design §1.2.3 names only `R.gain`). `R.gain` explains a later flip (the exact-pin branch, Resources.lua's Usable apply); `R.pinDelta` is what keeps the gain out of a regen measurement between two measuring pins (`calibrate(r, (vm - pinV - pinDelta) / dt)`). `I.ResourceShift`, which the design cites, does both.
3. **No Adapter forward for `consumedBy`.** `def.auras[j]` is the class's aura table itself (Adapter.lua's `insert(def.auras, a)`), and Engine/Spec.lua's RegisterAura stores a non-function field raw (Spec.lua:267-274), so Families/Auras.lua reads `rawget(def.auras[j], "consumedBy")` at the build.
4. **`threat.lost` needs a plain `false` from `UnitIsUnit("targettarget", "player")`.** The design's `UnitExists("targettarget") and not threat.on_me` reads a secret answer (`on_me` false) as lost and would recommend Taunt on a mob attacking us. A secret answer is neither on us nor lost; `VS.LooseEnemies` uses the same rule per token.
5. **Engine/Spec.lua tests secrecy through `Facade.issecretvalue`** (one new export of the facade's own resolver). The `threat` table's `__index` runs under `setfenv( __index, state )` (Spec.lua `RegisterStateTable`), so every name it reads is an upvalue taken from `ns.Facade`; the engine test's stub facade supplies all four.
6. **Concussion Blow carries `use_off_gcd=1`** in the Protection list. Without it `tests/Forever/packs_spec.lua` "flag use_off_gcd=1 on exactly the off-GCD abilities (warrior)" fails (`Protection single[6]: concussion_blow`): its DB2 StartRecovery is 0 (design §3, "Concussion Blow off the GCD").
7. **The Protection pack's version is lower than today's** (20261016287 against 20261016796): `tools/make_pack.lua` derives it from the date and a checksum of the text. A saved profile still reloads it (Engine/Spec.lua reloads on `~=`) but reports "reverted" rather than "updated". The date is not bumped: that would also change the Arms and Fury versions, and `warrior_spec` pins `20261016`.
8. **The Warrior's `taken` passes the belief's values to its helpers.** `setfenv(taken, I.nowCtx)` binds only that function; `rageTaken` and `proc` keep the file's environment (in game `_G`, where `buff` is nil), so `taken` reads `buff`/`talent` itself and passes the reduction factor and ranks down.
9. **The core files cite the design as "tank design §x"**, not by its title, so no core line names the class's specialization (the leakage audit's boundary rule).

### The current code, where it differs from the design's description

The design (written against forever 939a64cc) describes swing rage as paid per PLAYER_SWING. Today's code (63a6ec48), read for this plan:
- Events/Rows.lua stages `Obs.Swing` with **c = 1** at the swing's time when the target's WOUND pairs with our white swing, and **c = 3** (same frame) for a CRITICAL one; Sources/Swing.lua stages **c = 4** for every PLAYER_SWING.
- Families/Resources.lua pays a hand's step on c = 1 and the `crit` on c = 3; c = 4 only decays the hand's hit rate (an EMA, `HIT_ALPHA = 0.1`), which **scales `I.SwingPerSecond`** (the calibration's reference).

Consequences for this plan: `PlayerHit` is its own observation, so neither the pairing nor the hit-rate EMA sees a hit on us; the damage-taken gain is kept out of the swing calibration by `pinDelta` (Deviation 2), so the scale keeps measuring landed swings only; the player's `UNIT_COMBAT` handler in Events/Attackers.lua (rows on us) is untouched and runs beside the new source handler, each registered for every unit.

## How this plan was checked

Replayed, not hand-derived. A throwaway clone of `~/src/hekili` at `63a6ec48` (in `/tmp`, bootstrapped tools from the main checkout's `.lua/`):
- Each task was written there, its test patch applied and run red, then its implementation patch and `make check`.
- The patches below are `git diff` between the task states; they were re-applied with `git apply` to a fresh clone at `63a6ec48`, in this plan's order, with busted after every test patch and `make check` after every task. The final tree equals the hand-built one. Nothing was committed to `~/src/hekili`.

Measured counts (full suite, `busted`):

| State | Result |
|---|---|
| base `63a6ec48` | 453 successes / 0 / 0 / 0 |
| T1 tests only | 453 / 0 failures / 4 errors |
| T1 green | 457 / 0 / 0 |
| T2 tests only | 457 / 6 failures / 3 errors |
| T2 green | 466 / 0 / 0 |
| T3 tests only | 465 / 1 failure / 1 error |
| T3 green | 467 / 0 / 0 |
| T4 tests only | 469 / 1 failure / 0 errors |
| T4 green | 470 / 0 / 0 |
| T5 tests only | 470 / 0 failures / 3 errors |
| T5 green | 473 / 0 / 0 |
| T6 tests only | 473 / 4 failures / 2 errors |
| T6 green | 479 / 0 / 0 |
| T7 tests only | 479 / 1 failure / 0 errors |
| T7 green | 480 / 0 / 0 |

`make check` exited 0 after every task: luacheck 0 / 0 in 105 files, lua-language-server no problems, api-check ok in 65 loaded files with an empty inventory diff, `stylua --check .` silent.

## Global Constraints

From the design, verbatim:

> **The boundary, binding for every section.** Core (`Virtual/**`, `Engine/**`, fork edits to stock files) gets generic
> rules read from declared fields, with no class, spell, aura, talent name, spell ID or Warrior constant. Everything
> Warrior-specific is a field or function on `Forever/Classes/Warrior.lua`'s declarations. Each section ends with
> "Owns", the split by file.

> Already decided, not reopened: the white-crit rage bonus, `pausesDecay`, UnitPower answering `lo`, UnitHealthMax
> player plain. Layering: Events may stage State observations (reviewer ruling, 2026-10-16).

The house rules for this plan:
- **Worktree.** Repository `~/src/hekili`. The orchestrator creates the worktree after the plan is committed: `git -C ~/src/hekili worktree add .claude/worktrees/forever-protection -b forever-protection forever`. Git from WSL only. After each task's green verification and clean review the orchestrator pushes `forever-protection`; never push to `forever` or any other branch; never force-push. No task merges.
- **Commits.** Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. An implementer on another model uses its own model's name.
- **The boundary** (above; `docs/research/2026-10-16-core-leakage-audit.md`). No class name, spell ID or Warrior constant in any core change, comments included: `git diff forever -- src/Hekili/Virtual src/Hekili/Engine | grep '^+' | grep -iE 'taunt|warrior|defensive|protection|revenge|stance|2565|12298|1310316'` prints nothing after every task.
- **Zero allocation on every per-event path.** The `PlayerHit` stage, the `taken` apply, the bins, `VS.TakenRate`, the `consumedBy` spend, `VS.LooseEnemies` and the `__taken` entry's functions allocate nothing; arrays and closures are built at a build or at load. Tests: player_spec, resources_spec, auras_spec, event_facade_spec and alloc_spec, each 0 bytes.
- **Secret safety.** No comparison or arithmetic on a client value before `issecretvalue` (through `Plain` in Sources, `Facade.issecretvalue` in Engine/Spec.lua); no `a and b or c` on a possibly-secret value. A secret `UnitLevel`, `UnitIsUnit` or `UnitExists` answer falls to the next source or reads 0/false; a WOUND whose amount is not plain is dropped with a `Note`.
- **Every game read through the facade or the injected `api`.** New client reads: `UnitLevel`, `UnitIsUnit` (Sources/Player.lua, through `api`), `GetShieldBlock` (the stat cache, through `api`), `UnitThreatSituation`/`UnitIsUnit`/`UnitExists` (Engine/Spec.lua, through `ns.Facade`'s existing passthrough rows). `tools/api_inventory.txt` stays unchanged.
- **Style.** StyLua formats our files; Engine/Spec.lua is in `.styluaignore` and keeps Hekili's style (spaces inside parentheses). Each task's patch is StyLua-clean.
- **Tools.** Run everything from the worktree root. The worktree has no `.lua/`: `make check LUA_ENV=$HOME/src/hekili/.lua`; busted alone: `$HOME/src/hekili/.lua/bin/busted`.
- **Patches** are applied with `git apply` from the worktree root, in the order given. Each block is a heredoc, so copy it whole.
- **Every task ends green on `make check`** (the verification block in each task).
- **The user runs the game.** The CHECKPOINT task stops execution: the orchestrator pushes the branch, points the client's checkout at it (`git -C ~/src/hekili checkout --detach forever-protection`), asks the user to run the exact lines, and waits. Every line is under 255 characters and copies its answer through `VSCopy(` (ForeverProbe). No new TOC file: `/reload` suffices. When the session ends: `git -C ~/src/hekili checkout --detach forever`.

## Review Focus

1. **The `now` context at a hit** (Deviations 1 and 8): `I.NowAt(t)` before every `taken`; the Warrior's helpers get the belief's values as arguments. Tests: resources_spec "reads the belief at the hit's time through the `now` context", adapter_spec "forwards the paying entry's `taken`, bound to the `now` context", warrior_spec "divides back Defensive Stance's 10% and Shield Wall's reduction".
2. **Secrets on the new reads**: the hit's amount and level, the threat reads, the loose count (Deviation 4). Tests: player_spec "drops a wound whose amount is not plain" and "takes the attacker's level from the target only while the target's target is the player"; engine_load_spec "reads a secret answer as 0 or false, never as lost"; event_facade_spec "counts the hostiles attacking someone else once by GUID".
3. **The swing calibration keeps measuring landed swings** (Deviation 2 and the current-code note): the taken gain in `pinDelta` and `R.gain`, never in the hit rate. Test: resources_spec "explains a later flip by its gain: an exact pin, no swing calibration (the scale stays 1)".
4. **The forecast's `__taken` entry**: one event a second from the reset (`last` = now + offset), the rate frozen at the reset, removed out of combat by `stop` (State.lua removes an entry whose `stop` holds). Fifteen events in the default 15 s window, inside the loop guard `3 x timeout + 10`. Test: adapter_spec "generates the sim's `__taken` entry".
5. **Shield Block's stacks**: two from the cast (`now` and `handler`), one spent per BLOCK or BLOCKED hit while believed up, down at 0; out of combat a plain aura read overrides (Q1 says which field shows 2). Tests: auras_spec "an aura spent by hits on the player", warrior_spec "blocks twice per Shield Block".

## File structure

```
src/Hekili/Virtual/State/VirtualState.lua         T1  Obs.PlayerHit = 36, I.HitKind, I.HitName
src/Hekili/Virtual/State/Sources/Player.lua       T1  UNIT_COMBAT (every unit) -> PlayerHit; statCall GetShieldBlock
src/Hekili/Virtual/State/Families/Player.lua      T1  I.STATS row { "GetShieldBlock" }
src/Hekili/Virtual/State/Families/Resources.lua   T2  R.taken/takenBin/takenSec, the PlayerHit apply, VS.TakenRate, bins cleared at CombatEnd
src/Hekili/Virtual/State/Families/Now.lua         T2  I.NowAt(t)
src/Hekili/Virtual/State/Adapter.lua              T2  forwards `taken`; T3 TAKEN, takenEntry, the walk skips __taken
src/Hekili/Virtual/State/Families/Auras.lua       T4  consumedBy: CONS at build, the PlayerHit spend
src/Hekili/Virtual/API/Facade.lua                 T5  Facade.issecretvalue
src/Hekili/Virtual/Events/Attackers.lua           T5  tokLoose, VS.LooseEnemies
src/Hekili/Engine/Spec.lua                        T5  the `threat` state table on `all`
src/Hekili/Forever/Classes/Warrior.lua            T6  taken, constants, Shield Block stacks, comments; T7 settings, Protection pack
docs/research/2026-10-16-warrior-talent-dump.md   T6  the live trait walk (copied)
tools/packs/warrior.lua                           T7  the Protection list and description
tests/Virtual/State/helpers/fake_api.lua          T1  UnitLevel (ctl.level), GetShieldBlock
tests/Virtual/State/player_spec.lua               T1  "hits on the player" (4 cases)
tests/Virtual/State/resources_spec.lua            T2  "rage from damage taken" (8 cases)
tests/Virtual/State/adapter_spec.lua              T2  `taken` forwarded; T3 the `__taken` entry
tests/Virtual/State/alloc_spec.lua                T2  player hits + TakenRate; T3 the entry's functions
tests/Virtual/State/auras_spec.lua                T4  "an aura spent by hits on the player" (3 cases)
tests/Forever/helpers/engine.lua                  T5  the stub facade's threat reads (`env.client`)
tests/Forever/engine_load_spec.lua                T5  "the engine's threat table" (2 cases)
tests/Virtual/Events/event_facade_spec.lua        T5  LooseEnemies
tests/Forever/helpers/load_warrior.lua            T6  VS.Stat, VS.HealthMax, state.equipped, applyBuff's stacks
tests/Forever/warrior_spec.lua                    T6  "rage from damage taken" (5 cases), Shield Block; T7 the Protection list
```

Deliberately not built (a review should not flag these):
- a current-health model, a health gate anywhere, defensives in the priority (design §6, §7);
- the sub-170-armor doubling (R2), Berserker Rage's extra rage taken, Improved Revenge's stun, threat amounts;
- Devastate and Commanding Shout (registered only if checkpoint Q3 shows them known: a follow-up commit, data only);
- group attribution (hits on others, others' heals), per-target Sunder stacks;
- a `charges` field on Shield Block or a `C_Spell.GetSpellCharges` read (design §3: aura charges, no charge category);
- caching the threat reads (each read is one passthrough call).

---
### Task 1: The source: every hit on the player as a `PlayerHit`; the block value in the stat cache

Design §1.2.1 and §1.3's stat-cache line; §5.1's `player_spec.lua` cases.

**Files:**
- Modify: `src/Hekili/Virtual/State/VirtualState.lua`, `src/Hekili/Virtual/State/Sources/Player.lua`, `src/Hekili/Virtual/State/Families/Player.lua`
- Test: `tests/Virtual/State/player_spec.lua` (new describe "hits on the player (UNIT_COMBAT, tank design §1.2.1)": "stages the seven kinds, a wound flagged BLOCK or BLOCK_REDUCED as BLOCKED, attributed or not", "takes the attacker's level from the target only while the target's target is the player", "drops a wound whose amount is not plain, with a note, and allocates nothing", "caches the shield's block value out of combat only"), `tests/Virtual/State/helpers/fake_api.lua` (`UnitLevel` from `ctl.level`, default `{ player = 20 }`, nil = secret; `GetShieldBlock` = zeros)

**Interfaces:**
- Consumes: the event facade's `UNIT_COMBAT` payload (`unit, act, flag, amount`, every slot already through `Plain`: a secret slot arrives nil); `api.UnitIsUnit`, `api.UnitLevel`, `api.GetShieldBlock`.
- Produces:
  - `VS.Obs.PlayerHit = 36`: `a` the kind, `b` the amount (0 when none), `c` the attacker's level (0 when no plain level);
  - `I.HitKind = { WOUND = 1, BLOCKED = 2, BLOCK = 3, DODGE = 4, PARRY = 5, MISS = 6, HEAL = 7 }`, `I.HitName[kind]` the names;
  - `VS.Stat("GetShieldBlock")`: the block value, cached out of combat like every stat.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/helpers/fake_api.lua b/tests/Virtual/State/helpers/fake_api.lua
index 8e89bdd1..2efa578f 100644
--- a/tests/Virtual/State/helpers/fake_api.lua
+++ b/tests/Virtual/State/helpers/fake_api.lua
@@ -58,6 +58,7 @@ function M.new()
         handlers = {},
         unitSpeed = {}, -- [unit] = speed for UnitAttackSpeed of a unit other than the player (default: secret)
         unitIs = {}, -- [unit] = the token UnitIsUnit(unit, x) is true for (SECRET: a secret answer)
+        level = { player = 20 }, -- [unit] = UnitLevel (nil: a secret answer)
         unknownEvents = {}, -- [event] = true: RegisterEvent raises, as the client does for an event it does not know
         form = 0, -- GetShapeshiftForm (0: none)
         forms = {}, -- [form index] = its spell ID (GetShapeshiftFormInfo's 4th return)
@@ -127,6 +128,13 @@ function M.new()
         end
         return ctl.speed[1], ctl.speed[2]
     end
+    function api.UnitLevel(unit)
+        local v = ctl.level[unit]
+        if v == nil then
+            return SECRET
+        end
+        return v
+    end
     function api.UnitIsUnit(a, b)
         local v = ctl.unitIs[a]
         if v == SECRET then
@@ -170,6 +178,7 @@ function M.new()
     end
     api.UnitStat, api.GetSpellBonusDamage, api.UnitAttackPower, api.UnitWeaponAttackPower = zeros, zeros, zeros, zeros
     api.UnitDamage, api.UnitArmor, api.GetMasteryEffect, api.GetCritChance = zeros, zeros, zeros, zeros
+    api.GetShieldBlock = zeros
     api.GetSpellCritChance, api.GetRangedCritChance, api.GetCombatRating, api.GetCombatRatingBonus =
         zeros, zeros, zeros, zeros
     api.CR_CRIT_MELEE, api.CR_HASTE_MELEE, api.CR_CRIT_TAKEN_SPELL, api.CR_MASTERY = 10, 18, 11, 26
diff --git a/tests/Virtual/State/player_spec.lua b/tests/Virtual/State/player_spec.lua
index 5c46837f..e3ce4fba 100644
--- a/tests/Virtual/State/player_spec.lua
+++ b/tests/Virtual/State/player_spec.lua
@@ -1,5 +1,6 @@
 -- tests/Virtual/State/player_spec.lua: VS.Start on a client that lacks a CR_* constant, and a start hook that raises
--- (CHECKPOINT 2: Forever defines no CR_CRIT_TAKEN_SPELL, and the raise aborted every later start hook).
+-- (CHECKPOINT 2: Forever defines no CR_CRIT_TAKEN_SPELL, and the raise aborted every later start hook); the hits on
+-- the player as `PlayerHit` observations (tank design §1.2.1) and the block value in the stat cache.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local fs = require("Virtual.State.helpers.fake_spec")
@@ -105,4 +106,87 @@ describe("player start", function()
         assert.truthy(seen and seen:find("boom"))
         assert.is_true(after)
     end)
+
+    describe("hits on the player (UNIT_COMBAT, tank design §1.2.1)", function()
+        local seen, ctl
+
+        local function fire(...)
+            ctl.Fire("UNIT_COMBAT", ...)
+            S.Flush()
+            I.Fold(ctl.now, false)
+        end
+
+        before_each(function()
+            ctl = api.ctl
+            seen = {}
+            I.On(VS.Obs.PlayerHit, function(o)
+                seen[#seen + 1] = { o.a, o.b, o.c }
+            end)
+            VS.Start(api)
+        end)
+
+        it("stages the seven kinds, a wound flagged BLOCK or BLOCK_REDUCED as BLOCKED, attributed or not", function()
+            fire("player", "WOUND", "", 12, 1)
+            fire("player", "WOUND", "BLOCK_REDUCED", 7, 1)
+            fire("player", "WOUND", "BLOCK", 5, 1)
+            fire("player", "BLOCK", "", 0, 1)
+            fire("player", "DODGE", "", 0, 1)
+            fire("player", "PARRY", "", 0, 1)
+            fire("player", "MISS", "", 0, 1)
+            fire("player", "HEAL", "", 30, 1)
+            fire("player", "ABSORB", "", 9, 1) -- not a kind
+            fire("target", "WOUND", "", 40, 1) -- the target's: Sources/Target.lua's
+            assert.are.same({
+                { 1, 12, 20 },
+                { 2, 7, 20 },
+                { 2, 5, 20 },
+                { 3, 0, 20 },
+                { 4, 0, 20 },
+                { 5, 0, 20 },
+                { 6, 0, 20 },
+                { 7, 30, 20 },
+            }, seen)
+            assert.are.equal(7, I.Log.unattributed) -- no hostile on us: Attackers made no row, the belief still sees them
+        end)
+
+        it("takes the attacker's level from the target only while the target's target is the player", function()
+            ctl.level.target = 23
+            fire("player", "WOUND", "", 12, 1) -- the target attacks someone else
+            ctl.unitIs.targettarget = "player"
+            fire("player", "WOUND", "", 12, 1)
+            ctl.level.target = nil -- secret: the player's level
+            fire("player", "WOUND", "", 12, 1)
+            ctl.level.target, ctl.level.player = -1, nil -- "??" and a secret player level: 0
+            fire("player", "WOUND", "", 12, 1)
+            assert.are.same({ 20, 23, 20, 0 }, { seen[1][3], seen[2][3], seen[3][3], seen[4][3] })
+        end)
+
+        it("drops a wound whose amount is not plain, with a note, and allocates nothing", function()
+            fire("player", "WOUND", "", nil, 1) -- the event facade passes a secret slot as nil
+            assert.are.same({}, seen)
+            assert.equal("secret", S.status["UNIT_COMBAT player amount"])
+            assert.are.equal(
+                0,
+                alloc.bytes(function()
+                    ctl.Fire("UNIT_COMBAT", "player", "WOUND", "BLOCK", 12, 1)
+                    S.Flush()
+                end, 2000)
+            )
+        end)
+
+        it("caches the shield's block value out of combat only", function()
+            local block = 31
+            api.GetShieldBlock = function()
+                return block
+            end
+            ctl.Fire("PLAYER_EQUIPMENT_CHANGED")
+            assert.are.equal(31, (VS.Stat("GetShieldBlock")))
+            ctl.Fire("PLAYER_REGEN_DISABLED")
+            block = 40
+            ctl.Fire("PLAYER_EQUIPMENT_CHANGED")
+            assert.are.equal(31, (VS.Stat("GetShieldBlock")))
+            ctl.Fire("PLAYER_REGEN_ENABLED")
+            assert.are.equal(40, (VS.Stat("GetShieldBlock")))
+        end)
+    end)
 end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `453 successes / 0 failures / 4 errors / 0 pending`.
- player_spec's new describe errors in its `before_each` (`Belief.lua:20: table index is nil`: `VS.Obs.PlayerHit` does not exist yet).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/State/Families/Player.lua b/src/Hekili/Virtual/State/Families/Player.lua
index 548512bf..1515145a 100644
--- a/src/Hekili/Virtual/State/Families/Player.lua
+++ b/src/Hekili/Virtual/State/Families/Player.lua
@@ -100,7 +100,7 @@ function VS.TTD(unit, now)
 end
 
 -- The stat cache (spec §6.5): the 12 stat names with the arguments Hekili reads them with (State.lua:2236-2356),
--- read out of combat; up to 7 returns each.
+-- and the shield's block value (a class's rage from a blocked hit), read out of combat; up to 7 returns each.
 I.STATS = {
     { "UnitStat", 1 },
     { "UnitStat", 2 },
@@ -112,6 +112,7 @@ I.STATS = {
     { "UnitWeaponAttackPower" },
     { "UnitDamage" },
     { "UnitArmor" },
+    { "GetShieldBlock" },
     { "GetMasteryEffect" },
     { "GetCritChance" },
     { "GetSpellCritChance" },
diff --git a/src/Hekili/Virtual/State/Sources/Player.lua b/src/Hekili/Virtual/State/Sources/Player.lua
index 7d430f04..7b067176 100644
--- a/src/Hekili/Virtual/State/Sources/Player.lua
+++ b/src/Hekili/Virtual/State/Sources/Player.lua
@@ -1,7 +1,7 @@
 -- Virtual/State/Sources/Player.lua
--- Player sources (spec §4.2): combat start and end, movement, spell haste, the player's health (poll 1.5) and the
+-- Player sources (spec §4.2): combat start and end, movement, spell haste, the player's health (poll 1.5), the
 -- out-of-combat stat cache (login, PLAYER_REGEN_ENABLED, PLAYER_EQUIPMENT_CHANGED, UNIT_DAMAGE, UNIT_ATTACK_POWER,
--- PLAYER_LEVEL_UP).
+-- PLAYER_LEVEL_UP) and every hit on the player (UNIT_COMBAT, plain) as a `PlayerHit`.
 -- Credits: secret-value handling after Catnip's (Durts) research.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Player.lua.
 
@@ -25,6 +25,8 @@ local function statCall(api, name, arg)
         return api.UnitDamage("player") -- secret: readStat tests every return
     elseif name == "UnitArmor" then
         return api.UnitArmor("player") -- secret: readStat tests every return
+    elseif name == "GetShieldBlock" then
+        return api.GetShieldBlock() -- secret: readStat tests every return
     elseif name == "GetMasteryEffect" then
         return api.GetMasteryEffect() -- secret: readStat tests every return
     elseif name == "GetCritChance" then
@@ -152,6 +154,31 @@ S.On("PLAYER_LEVEL_UP", nil, function(api, t)
     readStats(api, t)
 end)
 
+-- Every hit on the player, attributed or not (Events/Attackers.lua names the attacker only when it can): the kind, the
+-- amount and the attacker's level, the target's while its target is the player, else the player's own (a secret answer
+-- falls to the next). Registered for every unit, as Sources/Target.lua's: a "player" registration would narrow the
+-- client's and starve Rows/Attackers. A WOUND without a plain amount is dropped. Allocates nothing.
+local HIT, BLOCKS = I.HitKind, { BLOCK = true, BLOCK_REDUCED = true }
+S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount)
+    local kind = unit == "player" and type(act) == "string" and HIT[act]
+    if not kind then
+        return
+    elseif kind == HIT.WOUND and type(amount) ~= "number" then
+        Note("UNIT_COMBAT player amount", "secret")
+        return
+    elseif kind == HIT.WOUND and type(flag) == "string" and BLOCKS[flag] then
+        kind = HIT.BLOCKED
+    end
+    local level = 0
+    if Plain(api, api.UnitIsUnit("targettarget", "player")) == true then
+        level = Plain(api, api.UnitLevel("target")) or 0
+    end
+    if type(level) ~= "number" or level <= 0 then
+        level = Plain(api, api.UnitLevel("player")) or 0
+    end
+    Stage(Obs.PlayerHit, t, kind, type(amount) == "number" and amount or 0, type(level) == "number" and level or 0)
+end)
+
 S.On("PLAYER_STARTED_MOVING", nil, function(api, t)
     Stage(Obs.Moving, t, 0, 1)
 end)
diff --git a/src/Hekili/Virtual/State/VirtualState.lua b/src/Hekili/Virtual/State/VirtualState.lua
index 5ad45aab..de5b822a 100644
--- a/src/Hekili/Virtual/State/VirtualState.lua
+++ b/src/Hekili/Virtual/State/VirtualState.lua
@@ -53,8 +53,14 @@ VS.Obs = {
     Range = 33, -- a: plate index; b: count in range of the range spell
     TargetCast = 34, -- a: TargetCastOf; b: castBarID; c: interruptible 1 / 0 / -1 unknown
     TargetDamage = 35, -- b: a WOUND amount the target took (UNIT_COMBAT, plain); VirtualState's own, past TDF's range
+    PlayerHit = 36, -- a: I.HitKind; b: the amount (0: none); c: the attacker's level (UNIT_COMBAT on the player, plain)
 }
 
+--- What a `PlayerHit` observation reports (its `a`), and each kind's name (the `taken` and `consumedBy` keys): a WOUND
+--- flagged BLOCK or BLOCK_REDUCED is BLOCKED (part of it blocked), the BLOCK action a full block.
+I.HitKind = { WOUND = 1, BLOCKED = 2, BLOCK = 3, DODGE = 4, PARRY = 5, MISS = 6, HEAL = 7 }
+I.HitName = { "WOUND", "BLOCKED", "BLOCK", "DODGE", "PARRY", "MISS", "HEAL" }
+
 --- What a `Read` observation read (its `c`): TDF's Enum.ReadOf integers (5 and 7-9 reserved), plus Health = 10, a
 --- VirtualState kind past TDF's range.
 I.ReadOf = { Resource = 1, Aura = 2, TargetAura = 3, Max = 4, Regen = 6, Health = 10 }
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `457 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 105 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      457 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/VirtualState.lua src/Hekili/Virtual/State/Sources/Player.lua \
  src/Hekili/Virtual/State/Families/Player.lua tests/Virtual/State/player_spec.lua tests/Virtual/State/helpers/fake_api.lua
git commit -m "feat(vs): every hit on the player as a PlayerHit observation, attributed or not; the block value in the stat cache (tank design §1.2.1)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-protection`

---

### Task 2: The belief: a slot's `taken` gain on a hit, and the learned incoming rate

Design §1.2.2-§1.2.4 (as amended by Deviations 1 and 2); §5.1's `resources_spec.lua`, `adapter_spec.lua` (`taken` forwarded) and `alloc_spec.lua` cases.

**Files:**
- Modify: `src/Hekili/Virtual/State/Families/Resources.lua`, `src/Hekili/Virtual/State/Families/Now.lua`, `src/Hekili/Virtual/State/Adapter.lua`
- Test: `tests/Virtual/State/resources_spec.lua` (new describe "rage from damage taken (tank design §1.2: the paying entry's `taken`)": "gains on every kind but a heal, with the kind's name, the amount and the level", "moves lo by gain - width (never below 0) and hi by gain + width, clamped to the maximum", "ignores a gain that is not a positive number, and a `taken` that raises counts as a now error", "changes nothing for a slot without `taken`", "reads the belief at the hit's time through the `now` context (buff, talent, the resources)", "explains a later flip by its gain: an exact pin, no swing calibration (the scale stays 1)", "learns the rate: the last 10 s of gains / 10, in combat only, cleared at combat end", "allocates nothing over 100 hits and rate reads"), `tests/Virtual/State/adapter_spec.lua` ("forwards the paying entry's `taken`, bound to the `now` context, and no other entry's"), `tests/Virtual/State/alloc_spec.lua` (player WOUNDs, some flagged BLOCK, through a `taken` reading `buff`; `VS.TakenRate` each step)

**Interfaces:**
- Consumes: `Obs.PlayerHit` (Task 1), `I.HitKind`/`I.HitName`; the paying regen entry's `taken(kind, amount, level) -> gain, width` (a class declaration); `I.nowCtx`.
- Produces:
  - `I.res.taken[r]` (the function bound to `I.nowCtx`, or false), `I.res.takenBin[r][1..10]`, `I.res.takenSec[r][1..10]`, `I.TAKEN_WINDOW = 10`;
  - on `PlayerHit` kinds 1-6: est += gain, lo += max(0, gain - width), hi += gain + width (clamped to [0, max]), `R.pinDelta` and `R.gain` += gain, one `modelled` sample, the gain into its second's bin;
  - `VS.TakenRate(powerType, now)`: the bins of the last 10 whole seconds / 10, in combat only;
  - `I.NowAt(t)` (Families/Now.lua): the context's reads answer at `t`;
  - Adapter: `d.taken` = the paying swing entry's `taken`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/adapter_spec.lua b/tests/Virtual/State/adapter_spec.lua
index 983f06cf..8ac2c4b1 100644
--- a/tests/Virtual/State/adapter_spec.lua
+++ b/tests/Virtual/State/adapter_spec.lua
@@ -127,6 +127,21 @@ describe("Adapter", function()
         assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
     end)
 
+    it("forwards the paying entry's `taken`, bound to the `now` context, and no other entry's", function()
+        local model = h.Class.resources.rage.state.regenModel
+        local function taken()
+            return buff.battle_shout.up and 3 or 1 -- luacheck: ignore 113 (the `now` context's names)
+        end
+        model.mainhand.taken = taken
+        model.offhand = { swing = "offhand", value = 4, taken = function() end } -- not the paying entry: unread
+        VS.SpecChanged()
+        assert.are.equal(taken, I.res.taken[1])
+        assert.are.equal(I.nowCtx, getfenv(taken))
+        model.mainhand.taken, model.offhand = nil, nil
+        VS.SpecChanged()
+        assert.is_false(I.res.taken[1])
+    end)
+
     it("generates the sim's stepped decay entry, on the belief's beats and from a tick aura's expiry", function()
         local model, rank = h.Class.resources.rage.state.regenModel, 0
         model.bloodrage = { aura = "bloodrage", interval = 1, value = 1, pausesDecay = true }
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
index 5959cfd4..56efdd76 100644
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -1,8 +1,8 @@
 -- tests/Virtual/State/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
--- usability flipping on a health-gated spender, own casts, UNIT_AURA after a form swap, the target's UNIT_COMBAT, combat
--- ending and starting under a stepped rage decay) with a drain every tick against the fake spec, every accessor and
--- every facade policy and passthrough called, every combat-log row delivered to a subscriber: VirtualState allocates
--- nothing.
+-- usability flipping on a health-gated spender, own casts, UNIT_AURA after a form swap, the target's UNIT_COMBAT, hits
+-- on the player paying rage through a `taken`, combat ending and starting under a stepped rage decay) with a drain every
+-- tick against the fake spec, every accessor and every facade policy and passthrough called, every combat-log row
+-- delivered to a subscriber: VirtualState allocates nothing.
 local load = require("Virtual.State.helpers.load")
 local fake = require("Virtual.State.helpers.fake_api")
 local fs = require("Virtual.State.helpers.fake_spec")
@@ -66,6 +66,9 @@ describe("zero allocation", function()
                 return 1
             end,
         }
+        h.Class.resources.rage.state.regenModel.mainhand.taken = function(kind, amount) -- rage from hits on us
+            return buff.battle_shout.up and amount / 10 or 1, 0.5 -- luacheck: ignore 113 (the `now` context's names)
+        end
         VS.Start(api)
         VS.SpecChanged()
         local decay = h.Class.resources.rage.state.regenModel.__decay -- the sim's (Adapter.lua), called as a forecast
@@ -97,6 +100,7 @@ describe("zero allocation", function()
                 ctl.Fire("UNIT_AURA", "player")
             else
                 ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 10, 1)
+                ctl.Fire("UNIT_COMBAT", "player", "WOUND", i % 12 == 5 and "BLOCK" or "", 12, 1)
             end
             if i % 100 == 50 then
                 ctl.Fire("PLAYER_REGEN_ENABLED") -- out of combat: the rage decays on its beats
@@ -108,6 +112,7 @@ describe("zero allocation", function()
             local t = ctl.now
             VS.Power(fs.RAGE, t)
             VS.DecayAnchor(fs.RAGE)
+            VS.TakenRate(fs.RAGE, t)
             decay.last()
             decay.stop()
             decay.value()
diff --git a/tests/Virtual/State/resources_spec.lua b/tests/Virtual/State/resources_spec.lua
index 449b99eb..a544941c 100644
--- a/tests/Virtual/State/resources_spec.lua
+++ b/tests/Virtual/State/resources_spec.lua
@@ -910,4 +910,160 @@ describe("resources", function()
             within(15 + 9.9, r.hi)
         end)
     end)
+
+    describe("rage from damage taken (tank design §1.2: the paying entry's `taken`)", function()
+        local WOUND, BLOCKED, BLOCK, DODGE, PARRY, MISS, HEAL = 1, 2, 3, 4, 5, 6, 7
+        local calls
+
+        local function taken(fn)
+            local def = fs.def(fs.new(9))
+            def.resources[1].taken = fn
+            boot(def)
+            I.Fold(10, false)
+        end
+
+        local function hit(t, kind, amount, level)
+            obs(Obs.PlayerHit, t, kind, amount or 0, level or 20)
+            I.Fold(t, false)
+        end
+
+        before_each(function()
+            calls = {}
+        end)
+
+        it("gains on every kind but a heal, with the kind's name, the amount and the level", function()
+            taken(function(kind, amount, level)
+                calls[#calls + 1] = kind .. " " .. amount .. " " .. level
+                return 2, 0.5
+            end)
+            hit(11, WOUND, 40, 12)
+            hit(12, BLOCKED, 30)
+            hit(13, BLOCK)
+            hit(14, DODGE)
+            hit(15, PARRY)
+            hit(16, MISS)
+            hit(17, HEAL, 50)
+            assert.are.same({
+                "WOUND 40 12",
+                "BLOCKED 30 20",
+                "BLOCK 0 20",
+                "DODGE 0 20",
+                "PARRY 0 20",
+                "MISS 0 20",
+            }, calls)
+            local r = VS.Power(fs.RAGE, 17)
+            assert.are.same({ 12, 9, 100, "modelled" }, { r.est, r.lo, r.hi, r.basis }) -- lo += 1.5 a hit; hi was 100
+            assert.are.equal(12, I.res.gain[1]) -- our own gain: a flip it explains pins exactly
+        end)
+
+        it("moves lo by gain - width (never below 0) and hi by gain + width, clamped to the maximum", function()
+            taken(function()
+                return 3, 5
+            end)
+            obs(Obs.Usable, 10, 2, 0, 1) -- heroic strike (15) short: hi 14.99
+            I.Fold(10, false)
+            hit(11, WOUND, 40)
+            local r = VS.Power(fs.RAGE, 11)
+            within(3, r.est)
+            within(0, r.lo)
+            within(15 - I.EPS + 8, r.hi)
+            for k = 1, 40 do
+                hit(11 + k, WOUND, 40)
+            end
+            r = VS.Power(fs.RAGE, 60)
+            assert.are.same({ 100, 100 }, { r.est, r.hi })
+        end)
+
+        it("ignores a gain that is not a positive number, and a `taken` that raises counts as a now error", function()
+            local answer
+            taken(function()
+                if answer == "raise" then
+                    error("boom")
+                end
+                return answer
+            end)
+            for _, a in ipairs({ 0, -4, "5" }) do
+                answer = a
+                hit(11, WOUND, 40)
+            end
+            answer = "raise"
+            hit(12, WOUND, 40)
+            local r = VS.Power(fs.RAGE, 12)
+            assert.are.same({ 0, "default" }, { r.est, r.basis })
+            assert.are.equal(1, I.nowErrors)
+        end)
+
+        it("changes nothing for a slot without `taken`", function()
+            boot(fs.def(fs.new(9)))
+            hit(11, WOUND, 40)
+            local r = VS.Power(fs.RAGE, 11)
+            assert.are.same({ 0, "default" }, { r.est, r.basis })
+        end)
+
+        it("reads the belief at the hit's time through the `now` context (buff, talent, the resources)", function()
+            taken(function()
+                return buff.battle_shout.up and 4 or 1 -- luacheck: ignore 113 (the `now` context's names)
+            end)
+            I.AuraModel(1, 1, 10, 20, 1, 10, 0) -- Battle Shout (aura 1) up from 10 to 20
+            hit(12, WOUND, 40)
+            hit(25, WOUND, 40)
+            assert.are.equal(5, VS.Power(fs.RAGE, 25).est)
+        end)
+
+        it("explains a later flip by its gain: an exact pin, no swing calibration (the scale stays 1)", function()
+            taken(function()
+                return 8
+            end)
+            obs(Obs.Usable, 10, 2, 0, 1) -- heroic strike (15) short at 0
+            I.Fold(10, false)
+            hit(11, WOUND, 40)
+            hit(12, WOUND, 40)
+            obs(Obs.Usable, 12.1, 2, 1, 0) -- usable: the hits crossed 15
+            I.Fold(12.1, false)
+            local r = VS.Power(fs.RAGE, 12.1)
+            assert.are.same({ 16, 16, 16, "pinned" }, { r.est, r.lo, r.hi, r.basis })
+            assert.are.same({ 1, false }, { I.res.scale[1], I.res.pinValid[1] })
+        end)
+
+        it("learns the rate: the last 10 s of gains / 10, in combat only, cleared at combat end", function()
+            taken(function()
+                return 2
+            end)
+            assert.are.equal(0, VS.TakenRate(fs.RAGE, 10))
+            obs(Obs.CombatStart, 10)
+            hit(11.5, WOUND, 40)
+            hit(14.2, WOUND, 40)
+            hit(18.9, WOUND, 40)
+            within(0.6, VS.TakenRate(fs.RAGE, 19))
+            within(0.4, VS.TakenRate(fs.RAGE, 21.5)) -- the second 11 left the window
+            within(0.2, VS.TakenRate(fs.RAGE, 27.9))
+            assert.are.equal(0, VS.TakenRate(fs.RAGE, 28)) -- ten quiet seconds
+            hit(30, WOUND, 40)
+            within(0.2, VS.TakenRate(fs.RAGE, 30))
+            obs(Obs.CombatEnd, 31)
+            I.Fold(31, false)
+            assert.are.equal(0, VS.TakenRate(fs.RAGE, 31))
+            obs(Obs.CombatStart, 32)
+            I.Fold(32, false)
+            assert.are.equal(0, VS.TakenRate(fs.RAGE, 32)) -- nothing kept from the last fight
+            assert.are.equal(0, VS.TakenRate(ENERGY, 32)) -- an untracked type
+        end)
+
+        it("allocates nothing over 100 hits and rate reads", function()
+            taken(function(kind, amount)
+                return amount / 10, amount / 40
+            end)
+            obs(Obs.CombatStart, 10)
+            I.Fold(10, false)
+            local t = 10
+            assert.are.equal(
+                0,
+                alloc.bytes(function()
+                    t = t + 0.7
+                    hit(t, WOUND, 40)
+                    VS.TakenRate(fs.RAGE, t)
+                end, 100)
+            )
+        end)
+    end)
 end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `457 successes / 6 failures / 3 errors / 0 pending`.
- resources_spec fails five new cases (no gain is applied) and errors on the rate and allocation cases (`VS.TakenRate` is nil).
- adapter_spec errors on the forwarding case (`I.res.taken` is nil).
- alloc_spec fails: the step raises inside `pcall` (`VS.TakenRate` is nil).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/State/Adapter.lua b/src/Hekili/Virtual/State/Adapter.lua
index 0a56d95d..d83a4bc2 100644
--- a/src/Hekili/Virtual/State/Adapter.lua
+++ b/src/Hekili/Virtual/State/Adapter.lua
@@ -170,6 +170,7 @@ local function buildDef()
         local r = class.resources[k]
         local swing, value, offValue, auraRegen, swingAura = 0, nil, nil, nil, nil
         local crit, offCrit -- a white crit's extra amount by hand (Resources.lua, I.SwingCrit)
+        local taken -- the paying entry's gain from a hit on the player (Resources.lua, tank design §1.2)
         local model = r.state and r.state.regenModel
         if model then
             for name, m in pairs(model) do
@@ -177,7 +178,7 @@ local function buildDef()
                     offValue, offCrit = m.value, m.crit
                 elseif m.swing and HANDS[m.swing] and swing == 0 then
                     swing, value, swingAura = HANDS[m.swing], m.value, m.aura -- `aura`: swings pay only while it is up
-                    crit = m.crit
+                    crit, taken = m.crit, m.taken
                 elseif
                     name ~= DECAY
                     and not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting)
@@ -210,6 +211,7 @@ local function buildDef()
             swingCrit = crit,
             swingOffCrit = offCrit,
             swingAura = swingAura,
+            taken = taken,
             auraRegen = auraRegen,
             decay = r.state and r.state.meta and r.state.meta.decay, -- out-of-combat loss per second (Resources.lua)
             decayInterval = r.state and r.state.meta and r.state.meta.decayInterval, -- seconds per quantum (stepped)
diff --git a/src/Hekili/Virtual/State/Families/Now.lua b/src/Hekili/Virtual/State/Families/Now.lua
index ef007df2..c6f920b2 100644
--- a/src/Hekili/Virtual/State/Families/Now.lua
+++ b/src/Hekili/Virtual/State/Families/Now.lua
@@ -46,6 +46,13 @@ I.nowErrors, I.nowError, I.nowRuns, I.castsRun = 0, nil, 0, 0
 -- The cast's belief time and ability while its effects run; `live` only then: a `now` called from anywhere else (Hekili
 -- keeps it in `ability.funcs`, where RunStressTest or an APL reading `action.x.now` can call it) writes nothing.
 local T, curA, live = 0, 0, false
+
+--- The context's reads answer at `t` from now on (a resource's `taken`, run at a hit: Families/Resources.lua); its
+--- verbs stay inert outside a cast. Allocates nothing.
+function I.NowAt(t)
+    T = t
+    rawset(NAMES, "now", t)
+end
 local abByKey, auraByKey, auraSpell, auraDur, auraMax, resByKey = {}, {}, {}, {}, {}, {}
 
 ----------------------------------------------------------------------------------------------------------------------
diff --git a/src/Hekili/Virtual/State/Families/Resources.lua b/src/Hekili/Virtual/State/Families/Resources.lua
index 91430a57..2b905d80 100644
--- a/src/Hekili/Virtual/State/Families/Resources.lua
+++ b/src/Hekili/Virtual/State/Families/Resources.lua
@@ -2,7 +2,8 @@
 -- The resources family (spec §6.1): the cost ladder (a usability report pins or bounds a resource at the ability's
 -- cost), exact reads, regen calibration between pins (an EMA), swing steps for a swing-paid resource (rage), our own
 -- casts' changes (Adapter.lua, spec §5.3), periodic regen (Hekili's regen-model entries with `interval` and `value`:
--- with an `aura`, Bloodrage's rage over time; without one, in combat: Anger Management), and the Power/Regen accessors.
+-- with an `aura`, Bloodrage's rage over time; without one, in combat: Anger Management), the gain from a hit on the
+-- player (the paying entry's `taken`, tank design §1.2) and its learned rate, and the Power/Regen accessors.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Resources.lua (calibrate :117-136, pin :218-263,
 -- ladder :275-315, Applier Usable :327, Reader Resource :365-372) and the resource conf of
 -- src/TacoDogForever/Model/Belief.lua:695-699. The power-tick phase (TDF's Applier PowerTick :378) is not modelled in
@@ -65,6 +66,9 @@ local R = {
     maxMods = {},
     maxRead = {},
     gain = {},
+    taken = {},
+    takenBin = {},
+    takenSec = {},
 }
 I.res = R
 R.slotOf, R.slotOfToken = {}, {}
@@ -79,6 +83,9 @@ R.slotOf, R.slotOfToken = {}, {}
 -- HIT_ALPHA). It scales the model's swing rate, so the step scale calibrates the value of a landed swing.
 local hitRate, HIT_ALPHA = { 1, 1 }, 0.1
 local G = { n = 0, slot = {}, aura = {}, value = {}, interval = {}, talent = {}, pause = {} }
+-- `taken[r]`: the paying entry's `taken(kind, amount, level)` bound to the `now` context (Families/Now.lua), or false.
+-- Its gains in one-second bins: `takenBin[r][i]` the gain of the second `takenSec[r][i]` (-1: empty), i = sec % 10 + 1.
+I.TAKEN_WINDOW = 10
 -- In combat (fold order, for the entries without an aura: aura index 0) and since when.
 local fighting, fightT = false, 0
 R.auraRegen = G
@@ -188,6 +195,11 @@ I.OnBuild(function(def, now)
         R.decay[r] = decayOf(r)
         local iv = eval(d.decayInterval)
         R.decayIv[r], R.decayNext[r] = type(iv) == "number" and iv > 0 and iv or 0, 0
+        R.taken[r] = type(d.taken) == "function" and setfenv(d.taken, I.nowCtx) or false
+        R.takenBin[r], R.takenSec[r] = {}, {}
+        for i = 1, I.TAKEN_WINDOW do
+            R.takenBin[r][i], R.takenSec[r][i] = 0, -1
+        end
         R.power[r] = I.NewBelief("power " .. tostring(d.key))
         R.regen[r] = I.NewBelief("regen " .. tostring(d.key))
         I.Sample(R.power[r], "default", R.rest[r], now, 0)
@@ -622,6 +634,59 @@ I.On(Obs.CastSuccess, function(o, t, lag)
     end
 end)
 
+-- A hit on the player (kinds 1-6; a heal brings no rage): each slot with a `taken` gains what it returns, the interval
+-- by its half-width (lo never below the estimate's gain minus it), clamped to [0, max]; kept out of the regen
+-- measurement and counted as our own gain (a flip it explains pins exactly, as I.ResourceShift's); one `modelled`
+-- sample at the hit, and the gain into its second's bin. A `taken` that raises is counted as a `now`'s error.
+I.On(Obs.PlayerHit, function(o, t)
+    local kind = o.a
+    if kind < I.HitKind.WOUND or kind > I.HitKind.MISS then
+        return
+    end
+    for r = 1, R.n do
+        local f = R.taken[r]
+        if f then
+            I.NowAt(t)
+            local ok, gain, width = pcall(f, I.HitName[kind], o.b, o.c)
+            if not ok then
+                I.nowErrors, I.nowError = I.nowErrors + 1, gain
+            elseif type(gain) == "number" and gain > 0 then
+                width = type(width) == "number" and width > 0 and width or 0
+                local max = R.max[r]
+                R.est0[r] = clamp(R.est0[r] + gain, max)
+                R.lo0[r] = clamp(R.lo0[r] + (gain > width and gain - width or 0), max)
+                R.hi0[r] = clamp(R.hi0[r] + gain + width, max)
+                R.pinDelta[r], R.gain[r] = R.pinDelta[r] + gain, R.gain[r] + gain
+                I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.PlayerHit)
+                local sec = floor(t)
+                local i = sec % I.TAKEN_WINDOW + 1
+                local bin, stamp = R.takenBin[r], R.takenSec[r]
+                if stamp[i] ~= sec then
+                    bin[i], stamp[i] = 0, sec
+                end
+                bin[i] = bin[i] + gain
+            end
+        end
+    end
+end)
+
+--- (tank design §1.2.4) A power type's learned gain per second from hits on the player: its `taken` gains of
+--- the last TAKEN_WINDOW whole seconds to `now` / TAKEN_WINDOW, in combat only (0 out of combat, or with no `taken`).
+--- Allocates nothing.
+function VS.TakenRate(powerType, now)
+    local r = R.slotOf[powerType]
+    if not r or not R.taken[r] or not fighting then
+        return 0
+    end
+    local sec, sum, bin, stamp = floor(now), 0, R.takenBin[r], R.takenSec[r]
+    for i = 1, I.TAKEN_WINDOW do
+        if stamp[i] > sec - I.TAKEN_WINDOW and stamp[i] <= sec then
+            sum = sum + bin[i]
+        end
+    end
+    return sum / I.TAKEN_WINDOW -- nonzero: a constant
+end
+
 I.On(Obs.CombatStart, function(o, t)
     fighting, fightT = true, t
     for r = 1, R.n do
@@ -634,6 +699,9 @@ end)
 I.On(Obs.CombatEnd, function(o, t)
     fighting = false
     for r = 1, R.n do
+        for i = 1, I.TAKEN_WINDOW do
+            R.takenSec[r][i] = -1
+        end
         R.decay[r] = decayOf(r)
         if not R.maxRead[r] then
             setMax(r, maxOf(r))
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `466 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 105 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      466 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/Families/Resources.lua src/Hekili/Virtual/State/Families/Now.lua \
  src/Hekili/Virtual/State/Adapter.lua tests/Virtual/State/resources_spec.lua tests/Virtual/State/adapter_spec.lua \
  tests/Virtual/State/alloc_spec.lua
git commit -m "feat(vs): a hit on the player pays the paying entry's `taken`, kept out of the swing calibration; the learned incoming rate (tank design §1.2.2-4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-protection`

---

### Task 3: The sim: the generated `__taken` regen entry

Design §1.2.5; §5.1's `adapter_spec.lua` case. Built like Adapter.lua's `__decay`: once per regen model, at a build, skipped by the `auraRegen` walk.

**Files:**
- Modify: `src/Hekili/Virtual/State/Adapter.lua`
- Test: `tests/Virtual/State/adapter_spec.lua` ("generates the sim's `__taken` entry: every second from the reset, the learned rate, out of combat removed"), `tests/Virtual/State/alloc_spec.lua` (the entry's `last`, `stop`, `value` each step)

**Interfaces:**
- Consumes: `VS.TakenRate` (Task 2); Hekili's `state.now`, `state.offset`, `state.time`.
- Produces: `class.resources[k].state.regenModel.__taken` when the paying entry has a `taken`: `{ resource = k, interval = 1, value() = VS.TakenRate(type, state.now), last() = state.now + state.offset, stop() = state.time == 0 }`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/adapter_spec.lua b/tests/Virtual/State/adapter_spec.lua
index 8ac2c4b1..9f7f20bc 100644
--- a/tests/Virtual/State/adapter_spec.lua
+++ b/tests/Virtual/State/adapter_spec.lua
@@ -142,6 +142,38 @@ describe("Adapter", function()
         assert.is_false(I.res.taken[1])
     end)
 
+    it(
+        "generates the sim's `__taken` entry: every second from the reset, the learned rate, out of combat removed",
+        function()
+            local model = h.Class.resources.rage.state.regenModel
+            VS.SpecChanged()
+            assert.is_nil(model.__taken) -- no `taken`: none
+            model.mainhand.taken = function()
+                return 2
+            end
+            local got
+            local build = I.Build
+            I.Build = function(def, t)
+                got = def
+                return build(def, t)
+            end
+            VS.SpecChanged()
+            local e = model.__taken
+            VS.SpecChanged()
+            I.Build = build
+            assert.are.same({ e, "rage", 1 }, { model.__taken, e.resource, e.interval }) -- built once
+            assert.is_nil(got.resources[1].auraRegen) -- the walk skips it: not a regen entry of the belief
+            state.time, state.now, state.offset = 0, 20, 0
+            assert.are.same({ true, 0 }, { e.stop(), e.value() }) -- out of combat
+            I.Sources.Direct(VS.Obs.CombatStart, 10)
+            I.Sources.Direct(VS.Obs.PlayerHit, 12, 1, 40, 20)
+            I.Sources.Direct(VS.Obs.PlayerHit, 15, 4, 0, 20)
+            I.Fold(15)
+            state.time, state.now, state.offset = 5, 16, 1.5
+            assert.are.same({ false, 0.4, 17.5 }, { e.stop(), e.value(), e.last() }) -- 2 + 2 in 10 s; from the reset
+        end
+    )
+
     it("generates the sim's stepped decay entry, on the belief's beats and from a tick aura's expiry", function()
         local model, rank = h.Class.resources.rage.state.regenModel, 0
         model.bloodrage = { aura = "bloodrage", interval = 1, value = 1, pausesDecay = true }
diff --git a/tests/Virtual/State/alloc_spec.lua b/tests/Virtual/State/alloc_spec.lua
index 56efdd76..7924e2ff 100644
--- a/tests/Virtual/State/alloc_spec.lua
+++ b/tests/Virtual/State/alloc_spec.lua
@@ -72,6 +72,7 @@ describe("zero allocation", function()
         VS.Start(api)
         VS.SpecChanged()
         local decay = h.Class.resources.rage.state.regenModel.__decay -- the sim's (Adapter.lua), called as a forecast
+        local taken = h.Class.resources.rage.state.regenModel.__taken
         state.time, state.query_time = 0, 1
         ctl.guid.target = "Creature-2" -- a target never held before: its first flip learns M, then WOUNDs move it
         ctl.Fire("PLAYER_TARGET_CHANGED")
@@ -116,6 +117,9 @@ describe("zero allocation", function()
             decay.last()
             decay.stop()
             decay.value()
+            taken.last()
+            taken.stop()
+            taken.value()
             VS.Regen(fs.RAGE, t)
             VS.Cooldown(fs.REND, t)
             VS.Charges(fs.REND, t)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `465 successes / 1 failure / 1 error / 0 pending`.
- adapter_spec errors on the new case (`model.__taken` is nil, indexed).
- alloc_spec fails (the step indexes the nil entry inside `pcall`).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/State/Adapter.lua b/src/Hekili/Virtual/State/Adapter.lua
index d83a4bc2..43c8b1f0 100644
--- a/src/Hekili/Virtual/State/Adapter.lua
+++ b/src/Hekili/Virtual/State/Adapter.lua
@@ -71,6 +71,7 @@ local def = {
 
 local HANDS = { mainhand = 1, offhand = 2 }
 local DECAY = "__decay" -- the generated entry's reserved name in a regen model
+local TAKEN = "__taken" -- the generated incoming-rage entry's (tank design §1.2.5)
 
 local function eval(v)
     if type(v) == "function" then
@@ -120,6 +121,23 @@ local function decayEntry(key, model, meta, powerType)
     return e
 end
 
+-- The sim's rage from hits on the player (tank design §1.2.5): a regen-model entry Hekili's forecast steps every
+-- second from the reset, the belief's learned rate (VS.TakenRate) a step, removed out of combat (`stop`). The belief
+-- never reads it: real hits are observed. Built once per regen model, at a build.
+local function takenEntry(key, powerType)
+    local e = { resource = key, interval = 1 }
+    function e.value()
+        return VS.TakenRate(powerType, state.now)
+    end
+    function e.last()
+        return state.now + state.offset
+    end
+    function e.stop()
+        return state.time == 0
+    end
+    return e
+end
+
 -- Point resources (a count, not a pool): a percentage maximum modifier does not apply to them.
 local POINTS = {
     combo_points = true,
@@ -181,6 +199,7 @@ local function buildDef()
                     crit, taken = m.crit, m.taken
                 elseif
                     name ~= DECAY
+                    and name ~= TAKEN
                     and not (m.swing or m.debuff or m.channel or m.spec or m.equip or m.set_bonus or m.setting)
                 then
                     auraRegen = auraRegen or {}
@@ -196,6 +215,9 @@ local function buildDef()
         if model and type(iv) == "number" and iv > 0 and model[DECAY] == nil then
             model[DECAY] = decayEntry(k, model, meta, r.type)
         end
+        if model and type(taken) == "function" and model[TAKEN] == nil then
+            model[TAKEN] = takenEntry(k, r.type)
+        end
         if swing == 0 and offValue ~= nil then
             swing, value, offValue, crit, offCrit = 2, offValue, nil, offCrit, nil -- the off hand alone pays it
         end
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `467 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 105 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      467 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/Adapter.lua tests/Virtual/State/adapter_spec.lua tests/Virtual/State/alloc_spec.lua
git commit -m "feat(vs): the sim's `__taken` regen entry steps the learned incoming rate every second in combat (tank design §1.2.5)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-protection`

---

### Task 4: Auras: a `consumedBy` aura loses a stack per listed hit on the player

Design §3 (the generic aura field) and §5.1's `auras_spec.lua` cases; Deviation 3 (no Adapter forward).

**Files:**
- Modify: `src/Hekili/Virtual/State/Families/Auras.lua`
- Test: `tests/Virtual/State/auras_spec.lua` (new describe "an aura spent by hits on the player (`consumedBy`, tank design §3)": "takes one stack per hit of a listed kind and removes the aura at 0", "ignores the other kinds, an expired aura, and an aura without `consumedBy`", "allocates nothing over 1000 hits")

**Interfaces:**
- Consumes: `Obs.PlayerHit` (Task 1), `I.HitKind`; an aura registration's `consumedBy = { <HitKind name> = true, ... }` (read raw from `def.auras[j]`).
- Produces: per `PlayerHit` of a listed kind, each such player aura believed up (expiry after the hit) loses one stack (`modelled`, event `Obs.PlayerHit`); at 0 it is down.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Virtual/State/auras_spec.lua b/tests/Virtual/State/auras_spec.lua
index b78f6c01..4238f7d2 100644
--- a/tests/Virtual/State/auras_spec.lua
+++ b/tests/Virtual/State/auras_spec.lua
@@ -249,4 +249,55 @@ describe("auras", function()
         I.Fold(12, false)
         assert.are.equal(30, VS.Aura("target", fs.REND, 12).est)
     end)
+
+    describe("an aura spent by hits on the player (`consumedBy`, tank design §3)", function()
+        local BLOCKED, BLOCK, DODGE = 2, 3, 4
+
+        local function hit(t, kind)
+            S.Direct(Obs.PlayerHit, t, kind, 0, 20)
+            I.Fold(t, false)
+        end
+
+        before_each(function()
+            local def = fs.def(fs.new(9))
+            def.auras[SHOUT] =
+                { key = "battle_shout", id = fs.SHOUT, max_stack = 2, consumedBy = { BLOCK = true, BLOCKED = true } }
+            I.Build(def, 1)
+            I.ObsLog.Clear(I.log)
+            I.AuraModel(1, SHOUT, 10, 17, 2, 10, 0) -- up from 10 to 17 with 2 stacks (its `now`)
+        end)
+
+        it("takes one stack per hit of a listed kind and removes the aura at 0", function()
+            hit(11, BLOCK)
+            local rec, stacks = VS.Aura("player", fs.SHOUT, 11)
+            assert.are.same({ 17, 1, "modelled" }, { rec.est, stacks, rec.basis })
+            hit(12, BLOCKED)
+            assert.is_nil(VS.Aura("player", fs.SHOUT, 12))
+            hit(13, BLOCK) -- down: nothing to spend
+            assert.is_nil(VS.Aura("player", fs.SHOUT, 13))
+        end)
+
+        it("ignores the other kinds, an expired aura, and an aura without `consumedBy`", function()
+            hit(11, DODGE)
+            assert.are.equal(2, select(2, VS.Aura("player", fs.SHOUT, 11)))
+            I.AuraModel(1, REND, 10, 30, 1, 10, 0) -- no `consumedBy`
+            hit(12, BLOCK)
+            assert.are.equal(1, select(2, VS.Aura("player", fs.REND, 12)))
+            hit(18, BLOCK) -- past the shout's expiry
+            assert.is_nil(VS.Aura("player", fs.SHOUT, 18))
+        end)
+
+        it("allocates nothing over 1000 hits", function()
+            local alloc = require("Virtual.State.helpers.alloc")
+            local t = 11
+            assert.are.equal(
+                0,
+                alloc.bytes(function()
+                    t = t + 0.01
+                    I.AuraModel(1, SHOUT, t, t + 7, 2, t, 0)
+                    hit(t, BLOCK)
+                end, 1000)
+            )
+        end)
+    end)
 end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `469 successes / 1 failure / 0 errors / 0 pending`.
- auras_spec fails "takes one stack per hit of a listed kind and removes the aura at 0" (the stack stays 2). The other two new cases pass before the implementation: they pin what must not change.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Virtual/State/Families/Auras.lua b/src/Hekili/Virtual/State/Families/Auras.lua
index 35187e22..02828a72 100644
--- a/src/Hekili/Virtual/State/Families/Auras.lua
+++ b/src/Hekili/Virtual/State/Families/Auras.lua
@@ -1,7 +1,8 @@
 -- Virtual/State/Families/Auras.lua
 -- The auras family (spec §6.3): per unit and tracked aura, the believed expiry, stacks, applied time and an invented
 -- stable instance ID; plain walk reads (observed), our casts' handler writes (modelled, Adapter.lua), expiry by time;
--- per-target memory by GUID slot (TARGET_CAP); the index order for AuraAt; AuraGen; Count.WithAura.
+-- per-target memory by GUID slot (TARGET_CAP); the index order for AuraAt; AuraGen; Count.WithAura; a player aura's
+-- stacks spent by hits on the player (its `consumedBy`, tank design §3).
 -- Ported from Taco Dog Forever, src/TacoDogForever/Model/Belief/Auras.lua and Belief/Targets.lua (Applier TargetSwap
 -- :147); the aura conf of src/TacoDogForever/Model/Belief.lua:709.
 
@@ -41,6 +42,9 @@ I.nextInst = 0
 local memExp, memApplied, memStacks, memInst = {}, {}, {}, {}
 I.curSlot = 0
 
+-- The player auras with a `consumedBy` (a set of I.HitKind names): their indices, and each one's kinds by I.HitKind.
+local CONS, consKinds = { n = 0 }, {}
+
 I.OnBuild(function(def, now)
     for k in pairs(U.bySpell) do
         U.bySpell[k] = nil
@@ -77,6 +81,22 @@ I.OnBuild(function(def, now)
         memExp[s], memApplied[s], memStacks[s], memInst[s] = e, ap, st, ins
     end
     I.curSlot = 0
+    CONS.n = 0
+    for j = 1, U.nAura do
+        local by = rawget(auras[j], "consumedBy")
+        if type(by) == "table" then
+            CONS.n = CONS.n + 1
+            CONS[CONS.n] = j
+            local kinds = {}
+            for name in pairs(by) do
+                local kind = I.HitKind[name]
+                if kind then
+                    kinds[kind] = true
+                end
+            end
+            consKinds[CONS.n] = kinds
+        end
+    end
     I.TRACKED.aura = U.id
     I.TRACKED.unit = U.token
 end)
@@ -151,6 +171,22 @@ function I.AuraModel(u, j, applied, expires, stacks, t, event, harmful)
     set(u, j, expires, applied, stacks > 0 and stacks or 1, t, "modelled", event, harmful)
 end
 
+-- A hit of a listed kind spends one stack of each `consumedBy` player aura believed up (a modelled sample at the hit),
+-- and takes it down at 0. Allocates nothing.
+I.On(Obs.PlayerHit, function(o, t)
+    for k = 1, CONS.n do
+        local j = CONS[k]
+        if consKinds[k][o.a] and U.exp0[1][j] > t then -- unit 1 is always "player" (Adapter.lua's def.units)
+            local n = U.stacks[1][j] - 1
+            if n > 0 then
+                set(1, j, U.exp0[1][j], U.applied[1][j], n, t, "modelled", Obs.PlayerHit)
+            else
+                set(1, j, 0, 0, 0, t, "modelled", Obs.PlayerHit)
+            end
+        end
+    end
+end)
+
 -- Per-target memory: the target's arrays into slot s, and back.
 local function save(s)
     if s == 0 or U.n < 2 then
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `470 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 105 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      470 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Virtual/State/Families/Auras.lua tests/Virtual/State/auras_spec.lua
git commit -m "feat(vs): an aura's `consumedBy` spends a stack per listed hit on the player (tank design §3)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-protection`

---

### Task 5: Threat: the engine's `threat` table and `VS.LooseEnemies`

Design §2 and §5.1's `engine_load_spec.lua` and `event_facade_spec.lua` cases; Deviations 4 and 5.

**Files:**
- Modify: `src/Hekili/Engine/Spec.lua` (the fork's `all` block, Hekili style), `src/Hekili/Virtual/Events/Attackers.lua`, `src/Hekili/Virtual/API/Facade.lua`
- Test: `tests/Forever/engine_load_spec.lua` (new describe "the engine's threat table (tank design §2)": "reads the situation, whether the target attacks us or someone else, and the loose hostiles", "reads a secret answer as 0 or false, never as lost"), `tests/Forever/helpers/engine.lua` (the stub facade's `UnitThreatSituation`, `UnitIsUnit`, `UnitExists`, `issecretvalue`, answered from `env.client`), `tests/Virtual/Events/event_facade_spec.lua` ("counts the hostiles attacking someone else once by GUID (VirtualState.LooseEnemies)")

**Interfaces:**
- Consumes: `Facade.UnitThreatSituation`, `Facade.UnitIsUnit`, `Facade.UnitExists` (existing passthrough rows), the new `Facade.issecretvalue`; Attackers.lua's per-token reads (`recheck`).
- Produces:
  - `state.threat.situation` (0-3, 0 when secret or none), `.on_me`, `.lost` (target of target exists and is plainly not us), `.loose` (`VS.LooseEnemies()`); computed on read;
  - `VS.LooseEnemies()`: hostile tokens (target, focus, nameplate1-40) whose target exists and is plainly not the player, one per GUID;
  - `Facade.issecretvalue`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/engine_load_spec.lua b/tests/Forever/engine_load_spec.lua
index 863bf111..bc1c101a 100644
--- a/tests/Forever/engine_load_spec.lua
+++ b/tests/Forever/engine_load_spec.lua
@@ -124,3 +124,31 @@ describe("Forever content through the real Engine/Spec.lua", function()
         end
     end
 end)
+
+describe("the engine's threat table (tank design §2)", function()
+    local env, threat
+
+    before_each(function()
+        env = engine.load("WARRIOR")
+        threat = env.class.stateTables.threat
+    end)
+
+    it("reads the situation, whether the target attacks us or someone else, and the loose hostiles", function()
+        local c = env.client
+        assert.are.same({ 0, false, false }, { threat.situation, threat.on_me, threat.lost }) -- no target
+        c.threat, c.exists.targettarget, c.isUnit.targettarget = 3, true, true
+        assert.are.same({ 3, true, false }, { threat.situation, threat.on_me, threat.lost })
+        c.threat, c.isUnit.targettarget = 1, false
+        assert.are.same({ 1, false, true }, { threat.situation, threat.on_me, threat.lost })
+        assert.are.equal(0, threat.loose) -- VirtualState.LooseEnemies: no hostile seen
+        assert.is_nil(threat.other)
+    end)
+
+    it("reads a secret answer as 0 or false, never as lost", function()
+        local c = env.client
+        c.threat, c.exists.targettarget, c.isUnit.targettarget = c.SECRET, true, c.SECRET
+        assert.are.same({ 0, false, false }, { threat.situation, threat.on_me, threat.lost })
+        c.exists.targettarget, c.isUnit.targettarget = c.SECRET, false
+        assert.is_false(threat.lost)
+    end)
+end)
diff --git a/tests/Forever/helpers/engine.lua b/tests/Forever/helpers/engine.lua
index f267791a..4deefd30 100644
--- a/tests/Forever/helpers/engine.lua
+++ b/tests/Forever/helpers/engine.lua
@@ -122,8 +122,9 @@ local function newState(class, race)
 end
 
 --- Loads the engine for a player of class token `classToken` (UnitClassBase) and race token `race` (UnitRace's second
---- return; default "Scourge"). Returns `{ Hekili, ns, state, class, errors, loadErrors }`: `errors` the Hekili:Error
---- calls, `loadErrors` one "<file>: <error>" per file whose main chunk raised (the rest still load).
+--- return; default "Scourge"). Returns `{ Hekili, ns, state, class, errors, loadErrors, client }`: `errors` the
+--- Hekili:Error calls, `loadErrors` one "<file>: <error>" per file whose main chunk raised (the rest still load),
+--- `client` the threat reads' answers (`threat`, `isUnit[unit]`, `exists[unit]`; `client.SECRET` a secret answer).
 function M.load(classToken, race)
     race = race or "Scourge"
     -- Hekili.lua's Class (Hekili.lua:102-130), strict: a misspelt field (class.abilites) raises at the reader
@@ -163,7 +164,8 @@ function M.load(classToken, race)
     class.itemPack = { lists = { items = {} } }
     strict(class, "class")
     local state = newState(class, race)
-    local env = { errors = {}, loadErrors = {}, class = class, state = state }
+    local client = { SECRET = {}, isUnit = {}, exists = {} }
+    local env = { errors = {}, loadErrors = {}, class = class, state = state, client = client }
     local hekili = { Class = class, State = state }
     function hekili.IsRetail()
         return false
@@ -231,6 +233,18 @@ function M.load(classToken, race)
         end,
         GetShapeshiftFormInfo = noop,
         CombatLogGetCurrentEventInfo = noop,
+        UnitThreatSituation = function()
+            return client.threat
+        end,
+        UnitIsUnit = function(a)
+            return client.isUnit[a]
+        end,
+        UnitExists = function(u)
+            return client.exists[u]
+        end,
+        issecretvalue = function(v)
+            return v == client.SECRET
+        end,
     }
     ns.commitKey = noop
     ns.metatables = { mt_resource = {} }
diff --git a/tests/Virtual/Events/event_facade_spec.lua b/tests/Virtual/Events/event_facade_spec.lua
index a45f5dde..c4040a03 100644
--- a/tests/Virtual/Events/event_facade_spec.lua
+++ b/tests/Virtual/Events/event_facade_spec.lua
@@ -254,4 +254,28 @@ describe("the event facade", function()
         end, 10000)
         assert.are.equal(0, bytes)
     end)
+
+    it("counts the hostiles attacking someone else once by GUID (VirtualState.LooseEnemies)", function()
+        VS.Start(api)
+        ctl.guid.nameplate1, ctl.guid.nameplate2, ctl.guid.nameplate3 = "Creature-7", "Creature-8", "Creature-9"
+        ctl.exists.nameplate1target, ctl.exists.nameplate2target = true, true
+        ctl.unitIs.nameplate1target = "party1" -- attacks a party member
+        ctl.unitIs.nameplate2target = "player" -- attacks us
+        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
+        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
+        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3") -- no target
+        assert.are.equal(1, VS.LooseEnemies())
+        ctl.guid.target, ctl.exists.targettarget, ctl.unitIs.targettarget = "Creature-7", true, "party1"
+        ctl.Fire("PLAYER_TARGET_CHANGED") -- the same mob as nameplate1: counted once
+        assert.are.equal(1, VS.LooseEnemies())
+        ctl.unitIs.nameplate2target = fake.SECRET
+        ctl.Fire("UNIT_TARGET", "nameplate2") -- a secret answer: neither on us nor loose
+        assert.are.equal(1, VS.LooseEnemies())
+        ctl.unitIs.nameplate2target = "party1"
+        ctl.Fire("UNIT_TARGET", "nameplate2")
+        assert.are.equal(2, VS.LooseEnemies())
+        ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
+        assert.are.equal(2, VS.LooseEnemies()) -- the target still holds Creature-7
+        assert.are.equal(0, alloc.bytes(VS.LooseEnemies, 2000))
+    end)
 end)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `470 successes / 0 failures / 3 errors / 0 pending`.
- engine_load_spec errors on both threat cases (`env.class.stateTables.threat` is nil).
- event_facade_spec errors on the LooseEnemies case (`VS.LooseEnemies` is nil).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Engine/Spec.lua b/src/Hekili/Engine/Spec.lua
index 57e508bd..b7b6d4e0 100644
--- a/src/Hekili/Engine/Spec.lua
+++ b/src/Hekili/Engine/Spec.lua
@@ -9,6 +9,7 @@ local C_Item, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_Specializa
 local GetSpecializationInfoByID, GetTime, InCombatLockdown, UnitAttackSpeed = Facade.GetSpecializationInfoByID, Facade.GetTime, Facade.InCombatLockdown, Facade.UnitAttackSpeed
 local UnitCanAttack, UnitCastingInfo, UnitChannelInfo, UnitClassBase = Facade.UnitCanAttack, Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClassBase
 local UnitGUID = Facade.UnitGUID
+local UnitExists, UnitIsUnit, UnitThreatSituation, issecretvalue = Facade.UnitExists, Facade.UnitIsUnit, Facade.UnitThreatSituation, Facade.issecretvalue
 local Hekili = _G[ addon ]
 
 local class = Hekili.Class
@@ -1709,6 +1710,31 @@ all:RegisterAbilities( {
     }
 } )
 
+-- Threat (tank design §2), read on demand through the facade's plain rows, a secret answer as 0 or false:
+-- `situation` UnitThreatSituation( "player", "target" ) (0-3); `on_me` the target attacks us; `lost` the target attacks
+-- someone else; `loose` the hostiles attacking someone else (VirtualState.LooseEnemies). No
+-- caching, no allocation. Every name is upvalued: Register's setfenv( __index, state ) leaves upvalues alone.
+local LooseEnemies = ns.VirtualState.LooseEnemies
+
+local function plain( v )
+    if issecretvalue( v ) then return nil end
+    return v
+end
+
+all:RegisterStateTable( "threat", setmetatable( {}, {
+    __index = function( t, k )
+        if k == "situation" then
+            return plain( UnitThreatSituation( "player", "target" ) ) or 0
+        elseif k == "on_me" then
+            return plain( UnitIsUnit( "targettarget", "player" ) ) == true
+        elseif k == "lost" then
+            return plain( UnitExists( "targettarget" ) ) == true and plain( UnitIsUnit( "targettarget", "player" ) ) == false
+        elseif k == "loose" then
+            return LooseEnemies()
+        end
+    end,
+} ) )
+
 
 ns.addToggle = function( name, default, optionName, optionDesc )
 
diff --git a/src/Hekili/Virtual/API/Facade.lua b/src/Hekili/Virtual/API/Facade.lua
index d23cb30b..f415b481 100644
--- a/src/Hekili/Virtual/API/Facade.lua
+++ b/src/Hekili/Virtual/API/Facade.lua
@@ -44,6 +44,7 @@ local GetTime = resolve("GetTime")
 local issecretvalue = resolve("issecretvalue") or function()
     return false
 end
+Facade.issecretvalue = issecretvalue -- the secrecy test a passthrough row's reader needs (Engine/Spec.lua's `threat`)
 
 ----------------------------------------------------------------------------------------------------------------------
 -- The trace (event-facade spec §5, decision 3): while Hekili makes a snapshot (`Hekili.ActiveDebug`), every facade
diff --git a/src/Hekili/Virtual/Events/Attackers.lua b/src/Hekili/Virtual/Events/Attackers.lua
index e23ce0cb..1664c319 100644
--- a/src/Hekili/Virtual/Events/Attackers.lua
+++ b/src/Hekili/Virtual/Events/Attackers.lua
@@ -6,12 +6,13 @@
 -- UnitAttackSpeed(unit) when plain, else learned from the gaps between hits on us. A hit is credited to the attacker
 -- whose clock predicts a swing nearest it within ATTACK_TOLERANCE; while a single hostile targets us and its clock is
 -- not set yet, to that one (which starts its clock); otherwise it stays unattributed and makes no row (no phantom
--- enemy for the tank branch, Events.lua's `ns.updateTarget( sourceGUID, ... )`).
+-- enemy for the tank branch, Events.lua's `ns.updateTarget( sourceGUID, ... )`). The same per-token reads count the
+-- hostiles attacking someone else (VirtualState.LooseEnemies, tank design §2).
 -- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
 -- (docs/research/2026-10-14-virtual-combat-log-events.md, C2, C4, M1-M4, D13).
 
 local _, ns = ...
-local I = ns.VirtualStateInternal
+local VS, I = ns.VirtualState, ns.VirtualStateInternal
 local S = I.Sources
 local Plain, Note = S.Plain, S.Note
 local L = I.Log
@@ -28,9 +29,9 @@ end
 for i = 1, #TOKENS do
     TT[i], INDEX[TOKENS[i]] = TOKENS[i] .. "target", i
 end
-local tokGUID, tokOnMe, tokSpeed = {}, {}, {}
+local tokGUID, tokOnMe, tokSpeed, tokLoose = {}, {}, {}, {}
 for i = 1, #TOKENS do
-    tokGUID[i], tokOnMe[i], tokSpeed[i] = "", false, 0
+    tokGUID[i], tokOnMe[i], tokSpeed[i], tokLoose[i] = "", false, 0, false
 end
 
 -- Attacker clocks by GUID (8, the oldest anchor gives way).
@@ -77,6 +78,8 @@ local function recheck(api, i)
         Note("UnitIsUnit target-of", S.StatusOf(api, raw))
     end
     tokGUID[i], tokOnMe[i] = guid, hostile and Plain(api, raw) == true
+    -- attacking someone else: its target exists and is plainly not us (a secret answer counts as neither)
+    tokLoose[i] = hostile and Plain(api, raw) == false and Plain(api, api.UnitExists(TT[i])) == true
     tokSpeed[i] = 0
     if tokOnMe[i] then
         local rawSpeed = api.UnitAttackSpeed(tok) -- secret: tested with issecretvalue next, then read through Plain
@@ -99,7 +102,7 @@ S.On("NAME_PLATE_UNIT_ADDED", nil, onUnit)
 S.On("NAME_PLATE_UNIT_REMOVED", nil, function(_, _, unit)
     local i = unit and INDEX[unit]
     if i then -- the token still answers during the event: clear it rather than recheck
-        tokGUID[i], tokOnMe[i], tokSpeed[i] = "", false, 0
+        tokGUID[i], tokOnMe[i], tokSpeed[i], tokLoose[i] = "", false, 0, false
     end
 end)
 local function readTarget(api)
@@ -112,6 +115,24 @@ S.On("PLAYER_FOCUS_CHANGED", nil, function(api)
     recheck(api, 2)
 end)
 
+--- (tank design §2) The hostiles (target, focus, nameplates) whose target exists and is not the player, each GUID
+--- once, as of their last UNIT_TARGET, plate or target/focus change. Allocates nothing.
+function VS.LooseEnemies()
+    local n = 0
+    for i = 1, #TOKENS do
+        if tokLoose[i] then
+            local seen = false
+            for j = 1, i - 1 do
+                seen = seen or (tokLoose[j] and tokGUID[j] == tokGUID[i])
+            end
+            if not seen then
+                n = n + 1
+            end
+        end
+    end
+    return n
+end
+
 -- How far `t` lies from the nearest swing a clock predicts (huge when the clock is not set). Allocates nothing.
 local function clockError(k, period, t)
     local anchor = k and atkAnchor[k] or 0
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `473 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
git diff forever -- src/Hekili/Virtual src/Hekili/Engine | grep '^+' \
  | grep -iE 'taunt|warrior|defensive|protection|revenge|stance|2565|12298|1310316'   # [no output]
```
```bash
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 105 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      473 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Engine/Spec.lua src/Hekili/Virtual/Events/Attackers.lua src/Hekili/Virtual/API/Facade.lua \
  tests/Forever/engine_load_spec.lua tests/Forever/helpers/engine.lua tests/Virtual/Events/event_facade_spec.lua
git commit -m "feat(engine): `threat` reads through the facade's plain rows and VirtualState.LooseEnemies (tank design §2)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-protection`

---

### Task 6: The Warrior kit: rage from damage taken, the two procs, Shield Block's two blocks

Design §1.3 and §3 with rulings R1, R2, R5 and R6; §5.1's `warrior_spec.lua` cases for §1 and §3. The talent registrations do not change (R6: the 52-node pin stays).

**Files:**
- Modify: `src/Hekili/Forever/Classes/Warrior.lua`
- Create: `docs/research/2026-10-16-warrior-talent-dump.md` (in the implementation patch; the job's `tmp/prot/talent-dump-2026-10-16.md`, verbatim)
- Test: `tests/Forever/warrior_spec.lua` (new describe "rage from damage taken (the main-hand entry's `taken`, Protection design §1.3)": "gives magey's log 01: 110 pre-armor from a level-5 attacker at 593 armor and 203 health is 5.4 rage", "adds the cached block value to a partial block, and estimates a full block from the unblocked amounts", "divides back Defensive Stance's 10% and Shield Wall's reduction (rage from the unreduced hit)", "adds Shield Specialization's 20% a rank of 5 rage on a block, partial or full", "adds Master of Defense's 50% a rank of 5 rage on a dodge or parry, only with a shield"; and "blocks twice per Shield Block: aura stacks spent by blocks, not ability charges"), `tests/Forever/helpers/load_warrior.lua` (`VS.Stat` from `game.stat`, `VS.HealthMax` from `game.healthMax`, `state.equipped`, `applyBuff`'s stacks into `env.stacks`)

**Interfaces:**
- Consumes: the `taken` declaration (Task 2), `consumedBy` (Task 4), `VS.Stat("UnitArmor")` (second return), `VS.Stat("GetShieldBlock")` (Task 1), `VS.HealthMax("player")`; in the `now` context `buff.defensive_stance`, `buff.shield_wall`, `talent.shield_specialization`, `talent.master_of_defense`; the upvalue `state.equipped.shield`.
- Produces:
  - `regenModel.mainhand.taken(kind, amount, level) -> gain, width`: WOUND/BLOCKED `post / (1 - armor / (armor + 400 + 85 x level)) / reduced x 10 / max health`, width 0.15 x gain (BLOCKED adds the block value to `post`); BLOCK from `min(block value, EMA of unblocked amounts)`, width = gain; Shield Specialization `+ 0.2 x rank x 5` on BLOCK/BLOCKED; Master of Defense `0.5 x rank x 5` on DODGE/PARRY with a shield; each proc's half-width `max(p, 1 - p) x 5`; MISS 0;
  - file constants `RAGE_TAKEN_FACTOR = 10`, `TAKEN_SPREAD = 0.15`, `DEFENSIVE_STANCE_TAKEN = 0.9`, `SHIELD_WALL_TAKEN = 0.4`, `PROC_RAGE = 5`, `SHIELD_SPECIALIZATION_CHANCE = 0.2`, `MASTER_OF_DEFENSE_CHANCE = 0.5`;
  - aura `shield_block`: `max_stack = 2`, `consumedBy = { BLOCK = true, BLOCKED = true }`; ability `shield_block` `now`/`handler`: `applyBuff("shield_block", nil, 2)`; no `charges`.

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/helpers/load_warrior.lua b/tests/Forever/helpers/load_warrior.lua
index 1125e18e..3b9c02eb 100644
--- a/tests/Forever/helpers/load_warrior.lua
+++ b/tests/Forever/helpers/load_warrior.lua
@@ -9,7 +9,8 @@ local M = {}
 --- Loads the class file. Returns `w`: `w.abilities`, `w.auras` (merged by key), `w.talents`, `w.track`, `w.resource`
 --- ({ powerType, models }), `w.hooks[name]`, `w.events[event]` (spec:RegisterEvent's handlers), `w.funcs[name]`,
 --- `w.exprs[name]`, `w.settings[key]` ({ default, option }), `w.packs` (in order: { name, version, string }),
---- `w.options`, `w.specID`, `w.state` (Hekili.State's stand-in) and `w.game`.
+--- `w.options`, `w.specID`, `w.state` (Hekili.State's stand-in) and `w.game` (its `stat` and `healthMax` answer
+--- VS.Stat and VS.HealthMax).
 function M.load()
     local reg = {}
     local spec = setmetatable({}, {
@@ -28,11 +29,13 @@ function M.load()
         form = 0,
         formSpell = {},
         base = { 0, 0 }, -- VS.SwingBase: each hand's unhasted speed (0: no plain read yet)
+        stat = {}, -- VS.Stat: [api name] = its cached returns (default zeros)
+        healthMax = 100, -- VS.HealthMax("player")
         now = 0, -- GetTime()
         row = {}, -- the combat-log row CombatLogGetCurrentEventInfo answers
     }
     local w = { game = game, abilities = {}, auras = {}, track = {}, hooks = {}, funcs = {}, exprs = {} }
-    w.state = { main_hand = { size = 2 }, timeToInterrupt = function() end }
+    w.state = { main_hand = { size = 2 }, equipped = {}, timeToInterrupt = function() end }
     local hekili = { State = w.state }
     function hekili:NewSpecialization(id)
         w.specID = id
@@ -94,6 +97,13 @@ function M.load()
             SwingBase = function(hand)
                 return game.base[hand]
             end,
+            Stat = function(name)
+                local v = game.stat[name] or {}
+                return v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0
+            end,
+            HealthMax = function()
+                return game.healthMax
+            end,
         },
     }
     local ok, err = pcall(assert(loadfile("src/Hekili/Forever/Classes/Warrior.lua")), "Hekili", ns)
@@ -143,10 +153,10 @@ local function default(value)
     })
 end
 
---- A stand-in `state` that records applyBuff/applyDebuff (into `applied`), removeBuff, spend and gain, with every
+--- A stand-in `state` that records applyBuff/applyDebuff (into `applied`; applyBuff's stacks into `stacks`), removeBuff, spend and gain, with every
 --- talent at rank 0, every aura down and every cooldown ready. The class file's state functions are bound to it.
 function M.env(w)
-    local e = { applied = {}, durations = {}, removed = {}, spent = {}, gained = {} }
+    local e = { applied = {}, durations = {}, stacks = {}, removed = {}, spent = {}, gained = {} }
     e.talent = default({ rank = 0, enabled = false })
     e.buff = default({ up = false, remains = 0, stack = 0 })
     e.debuff = e.buff
@@ -155,9 +165,9 @@ function M.env(w)
     e.rage = { current = 50 }
     e.target = { minR = 10, is_boss = false }
     e.combat, e.active_enemies = 0, 1
-    function e.applyBuff(key, duration)
+    function e.applyBuff(key, duration, stacks)
         table.insert(e.applied, key)
-        e.durations[key] = duration
+        e.durations[key], e.stacks[key] = duration, stacks
     end
     function e.applyDebuff(_, key)
         table.insert(e.applied, key)
diff --git a/tests/Forever/warrior_spec.lua b/tests/Forever/warrior_spec.lua
index 854e5eda..c73a3627 100644
--- a/tests/Forever/warrior_spec.lua
+++ b/tests/Forever/warrior_spec.lua
@@ -395,6 +395,102 @@ describe("Forever Warrior", function()
         assert.are.same({ "offhand", "offhand_speed" }, { models.offhand.swing, models.offhand.interval })
     end)
 
+    describe("rage from damage taken (the main-hand entry's `taken`, Protection design §1.3)", function()
+        local taken, e
+
+        -- The belief's `now` context as `taken` sees it: these auras up, these talent ranks.
+        local function ctx(auras, ranks)
+            e = {
+                buff = setmetatable({}, {
+                    __index = function(_, k)
+                        return { up = auras[k] == true }
+                    end,
+                }),
+                talent = setmetatable({}, {
+                    __index = function(_, k)
+                        return { rank = ranks[k] or 0 }
+                    end,
+                }),
+            }
+        end
+
+        local function run(kind, amount, level)
+            return lw.run(taken, e, kind, amount, level)
+        end
+
+        before_each(function()
+            taken = w.resource[2].mainhand.taken
+            w.game.stat.UnitArmor = { 593, 593 } -- base, effective: the second is the armor
+            w.game.healthMax = 203
+            ctx({}, {})
+        end)
+
+        it(
+            "gives magey's log 01: 110 pre-armor from a level-5 attacker at 593 armor and 203 health is 5.4 rage",
+            function()
+                local sum, band = 0, 0
+                for _ = 1, 20 do
+                    local g, wd = run("WOUND", 3.2, 5) -- 64 post-armor over 20 hits: 64 / (1 - 593 / 1418) = 110
+                    sum, band = sum + g, band + wd
+                end
+                assert.is_true(math.abs(sum - 110 * 10 / 203) < 1e-3, tostring(sum)) -- 5.419
+                assert.is_true(math.abs(band - 0.15 * sum) < 1e-9)
+                assert.is_true(math.abs(sum - 5.4) <= band)
+            end
+        )
+
+        it(
+            "adds the cached block value to a partial block, and estimates a full block from the unblocked amounts",
+            function()
+                w.game.stat.UnitArmor = { 0, 0 }
+                w.game.healthMax = 100
+                w.game.stat.GetShieldBlock = { 20 }
+                assert.are.same({ 3, 0.15 * 3 }, { run("BLOCKED", 10, 5) }) -- (10 + 20) x 10 / 100
+                local full = run("BLOCK", 0, 5)
+                assert.is_true(full > 0 and full <= 2) -- min(block value 20, the average unblocked amount) x 10 / 100
+                local g, wd = run("BLOCK", 0, 5)
+                assert.are.equal(g, wd) -- a full block's band is its whole estimate
+            end
+        )
+
+        it("divides back Defensive Stance's 10% and Shield Wall's reduction (rage from the unreduced hit)", function()
+            local open = run("WOUND", 50, 20)
+            ctx({ defensive_stance = true }, {})
+            assert.is_true(math.abs(run("WOUND", 50, 20) - open / 0.9) < 1e-9)
+            ctx({ defensive_stance = true, shield_wall = true }, {})
+            assert.is_true(math.abs(run("WOUND", 50, 20) - open / 0.36) < 1e-9)
+        end)
+
+        it("adds Shield Specialization's 20% a rank of 5 rage on a block, partial or full", function()
+            w.game.stat.GetShieldBlock = { 0 }
+            ctx({}, { shield_specialization = 1 })
+            assert.are.same({ 1, 4 }, { run("BLOCK", 0, 20) }) -- p = 0.2: 1 expected, half-width max(p, 1 - p) x 5
+            ctx({}, { shield_specialization = 5 })
+            assert.are.same({ 5, 5 }, { run("BLOCK", 0, 20) })
+            assert.are.same({ 0, 0 }, { run("DODGE", 0, 20) })
+        end)
+
+        it("adds Master of Defense's 50% a rank of 5 rage on a dodge or parry, only with a shield", function()
+            ctx({}, { master_of_defense = 1 })
+            assert.are.same({ 0, 0 }, { run("DODGE", 0, 20) }) -- no shield
+            w.state.equipped.shield = true
+            assert.are.same({ 2.5, 2.5 }, { run("DODGE", 0, 20) })
+            ctx({}, { master_of_defense = 2 })
+            assert.are.same({ 5, 5 }, { run("PARRY", 0, 20) })
+            assert.are.same({ 0, 0 }, { run("MISS", 0, 20) })
+        end)
+    end)
+
+    it("blocks twice per Shield Block: aura stacks spent by blocks, not ability charges", function()
+        local aura, ability = w.auras.shield_block, w.abilities.shield_block
+        assert.are.same({ 2, { BLOCK = true, BLOCKED = true } }, { aura.max_stack, aura.consumedBy })
+        assert.is_nil(ability.charges)
+        local env = lw.env(w)
+        lw.run(ability.handler, env)
+        lw.run(ability.now, env)
+        assert.are.same({ { "shield_block", "shield_block" }, 2 }, { env.applied, env.stacks.shield_block })
+    end)
+
     it("takes the believed swing speed before a plain base speed is read", function()
         local models = w.resource[2]
         w.state.talent = rank(0)
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `473 successes / 4 failures / 2 errors / 0 pending`.
- warrior_spec errors on magey's log and the stance case (`taken` is nil, called) and fails the block, Shield Specialization, Master of Defense and Shield Block cases.

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/docs/research/2026-10-16-warrior-talent-dump.md b/docs/research/2026-10-16-warrior-talent-dump.md
new file mode 100644
index 00000000..066b49fd
--- /dev/null
+++ b/docs/research/2026-10-16-warrior-talent-dump.md
@@ -0,0 +1,3 @@
+# Live Warrior talent tree, Forever client, 2026-10-16 (C_Traits walk: name, ranksPurchased, maxRanks, spellID; one tree 1117, 52 nodes)
+Improved Intercept 0 2 20504 | Death Wish 0 1 12328 | Flurry 0 5 12319 | Bloodthirst 0 1 23881 | Enrage 0 5 12317 | Improved Execute 0 2 20502 | Dual Wield Specialization 3 5 23584 | Blood Craze 1 3 16487 | Piercing Howl 1 1 12323 | Unbridled Wrath 5 5 12322 | Booming Voice 0 5 12321 | Cruelty 5 5 12320 | Mortal Strike 0 1 12294 | Improved Hamstring 0 3 12289 | Weaponmaster 0 5 1290261 | Sweeping Strikes 0 1 12292 | Impale 0 2 16493 | Two-Handed Weapon Specialization 0 3 12163 | Spearing Strike 0 1 1310222 | Deep Wounds 0 3 12834 | Anger Management 0 1 12296 | Improved Overpower 0 2 12290 | Furious Precision 3 3 1323963 | Improved Tactical Mastery 0 5 12295 | Improved Charge 0 2 12285 | Improved Rend 0 3 12286 | Deflection 0 5 16462 | Improved Heroic Strike 0 3 12282 | Shield Slam 0 1 23922 | Focused Rage 0 3 29787 | Bastion 0 5 16538 | Improved Shield Bash 0 2 12311 | Improved Shield Wall 0 2 12312 | Concussion Blow 0 1 12809 | Vanguard 0 1 1310317 | Improved Disarm 0 3 12313 | Improved Sunder Armor 0 3 12308 | Improved Revenge 0 3 12797 | Last Stand 0 1 12975 | Master of Defense 0 2 1310316 | Improved Thunder Clap 0 3 12287 | Improved Bloodrage 0 2 12301 | Anticipation 0 5 12297 | Shield Specialization 0 5 12298 | Raging Blows 0 1 1310315 | Improved Berserker Rage 0 2 20500 | Bloodthrill 0 5 1289682 | Defiance 0 3 12792 | Lingering Rage 0 5 1323964 | Improved Slam 0 2 12862 | Gore Drinker 0 2 1323967 | Iron Will 0 5 12962
+Confirms: no Improved Shield Block, no Improved Taunt, no Toughness; Defiance max 3. Tooltips: Shield Specialization 20%/rank for 5 rage on block (+1% block/rank); Master of Defense 50%/rank for 5 rage on dodge/parry with a shield.
diff --git a/src/Hekili/Forever/Classes/Warrior.lua b/src/Hekili/Forever/Classes/Warrior.lua
index 15a44b14..192a5cb3 100644
--- a/src/Hekili/Forever/Classes/Warrior.lua
+++ b/src/Hekili/Forever/Classes/Warrior.lua
@@ -4,7 +4,9 @@
 -- client is 1.60.1.70374, and its export wins where they differ), Forever's Victory Rush and Spearing Strike, rage per
 -- hit for both hands, Bloodrage's and Anger Management's rage over time, stances from the belief's Forms source, and
 -- the default priorities.
--- Talents: the 52 live nodes (a ForeverProbe export of the client, 1.60.1.70374, 2026-10-15). Only rank 1 of each
+-- Talents: the 52 live nodes (a ForeverProbe export of the client, 1.60.1.70374, 2026-10-15; confirmed by the trait
+-- walk of 2026-10-16, docs/research/2026-10-16-warrior-talent-dump.md: no Improved Shield Block, Improved Taunt or
+-- Toughness, Defiance max 3, so Shield Block stays 7 s and Taunt 8 s). Only rank 1 of each
 -- talent is in the Forever DB2, so a cost modifier is rank 1's value x the rank (Classic's own convention), floored
 -- at 0; no cooldown or duration modifier is modelled. The in-game checkpoint compares the costs (Snapshot cost= /
 -- read=).
@@ -141,6 +143,37 @@ local function rageOf(hand)
     return (twoHand and 4.5 or 3.46) * speed + wrath
 end
 
+-- Rage from damage taken (Protection design §1.3; magey/forever-warrior issue 3, level 8-9): the hit before every
+-- reduction x 10 / maximum health; a blocked hit gives the rage of its unblocked amount; attacker level made no
+-- difference. The pre-armor amount is the post-armor one / (1 - armor / (armor + 400 + 85 x attacker level)), with the
+-- armor and block value from VirtualState's out-of-combat stat cache. Defensive Stance's 10% and Shield Wall's
+-- reduction come off before the rage too (user ruling 2026-10-16: rage is from the unreduced hit): their factors divide
+-- the amount back. Shield Specialization (a 20% chance a rank to gain 5 on a block) and Master of Defense (50% a rank on
+-- a dodge or parry with a shield) as their expected values, the band carrying the spread (tooltips read in game
+-- 2026-10-16). Not modelled: Berserker Rage's extra rage taken.
+-- shortcut: below about 130-170 armor magey's rate was exactly double (checkpoint Q6, design D2); a tank wears more by
+-- level 10, so it is not modelled. Upgrade if Q6 reproduces it at the tank's level.
+local RAGE_TAKEN_FACTOR = 10
+local TAKEN_SPREAD = 0.15 -- the fit's scatter (9.6-11 around 10) and a stale cached armor
+local DEFENSIVE_STANCE_TAKEN, SHIELD_WALL_TAKEN = 0.9, 0.4
+local PROC_RAGE = 5
+local SHIELD_SPECIALIZATION_CHANCE, MASTER_OF_DEFENSE_CHANCE = 0.2, 0.5 -- a rank
+local unblockedAvg, UNBLOCKED_WEIGHT = 0, 0.2 -- an EMA of the unblocked post-armor amounts (a full block's estimate)
+
+-- The rage of a post-armor amount `post` from an attacker of `level`, divided back by `reduced` (the percentage
+-- reductions' product). Allocates nothing.
+local function rageTaken(post, level, reduced)
+    local armor = select(2, VS.Stat("UnitArmor"))
+    local mitigated = armor / (armor + 400 + 85 * level) -- nonzero: 400 + 85 x level > 0
+    return post / (1 - mitigated) / reduced * RAGE_TAKEN_FACTOR / VS.HealthMax("player") -- nonzero: max > 0 (100)
+end
+
+-- A proc's expected rage at chance p and its half-width.
+local function proc(p)
+    p = min(p, 1)
+    return p * PROC_RAGE, max(p, 1 - p) * PROC_RAGE
+end
+
 spec:RegisterResource(
     Enum.PowerType.Rage,
     {
@@ -167,6 +200,41 @@ spec:RegisterResource(
             crit = function()
                 return 3.46 * baseSpeed(1)
             end,
+            -- VirtualState's rage from a hit on us (kind: "WOUND", "BLOCKED", "BLOCK", "DODGE", "PARRY", "MISS"): the
+            -- expected gain and its half-width. Run in the belief's `now` context: `buff` and `talent` read the belief
+            -- at the hit; the helpers it calls get those values as arguments (their own environment is the file's).
+            taken = function(kind, amount, level)
+                local reduced = 1
+                if buff.defensive_stance.up then
+                    reduced = reduced * DEFENSIVE_STANCE_TAKEN
+                end
+                if buff.shield_wall.up then
+                    reduced = reduced * SHIELD_WALL_TAKEN
+                end
+                local gain, width = 0, 0
+                if kind == "WOUND" or kind == "BLOCKED" then
+                    local post = amount
+                    if kind == "BLOCKED" then
+                        post = post + VS.Stat("GetShieldBlock") -- the unblocked amount
+                    end
+                    unblockedAvg = unblockedAvg + UNBLOCKED_WEIGHT * (post - unblockedAvg)
+                    gain = rageTaken(post, level, reduced)
+                    width = TAKEN_SPREAD * gain
+                elseif kind == "BLOCK" then
+                    gain = rageTaken(min(VS.Stat("GetShieldBlock"), unblockedAvg), level, reduced)
+                    width = gain
+                end
+                local rank = talent.shield_specialization.rank
+                if (kind == "BLOCK" or kind == "BLOCKED") and rank > 0 then
+                    local g, w = proc(SHIELD_SPECIALIZATION_CHANCE * rank)
+                    gain, width = gain + g, width + w
+                end
+                rank = talent.master_of_defense.rank
+                if (kind == "DODGE" or kind == "PARRY") and rank > 0 and state.equipped.shield then
+                    gain, width = proc(MASTER_OF_DEFENSE_CHANCE * rank)
+                end
+                return gain, width
+            end,
         },
 
         offhand = {
@@ -312,8 +380,8 @@ spec:RegisterTalents({
     improved_shield_bash = { 0, 12311, 2 },
     one_handed_weapon_specialization = { 0, 16538, 5 }, -- "Bastion" on Forever
     shield_slam = { 0, 23922, 1 },
-    -- Forever-only: Focused Rage (-3 rage a rank on the offensive abilities), Vanguard (Charge in Defensive Stance);
-    -- Master of Defense unmodelled.
+    -- Forever-only: Focused Rage (-3 rage a rank on the offensive abilities), Vanguard (Charge in Defensive Stance),
+    -- Master of Defense (rage on a dodge or parry: the rage resource's `taken`).
     focused_rage = { 0, 29787, 3 },
     vanguard = { 0, 1310317, 1 },
     master_of_defense = { 0, 1310316, 2 },
@@ -515,10 +583,13 @@ spec:RegisterAuras({
         duration = 3,
         max_stack = 1,
     },
+    -- Shield Block's blocks are the aura's charges (DB2: SpellAuraOptions.ProcCharges = 2, no charge category): its
+    -- stacks, each block or partial block on us spending one (VirtualState's `consumedBy`).
     shield_block = {
         id = 2565,
         duration = 7,
-        max_stack = 1,
+        max_stack = 2,
+        consumedBy = { BLOCK = true, BLOCKED = true },
     },
     shield_wall = {
         id = 871,
@@ -1429,11 +1500,11 @@ spec:RegisterAbilities({
         equipped = "shield",
 
         now = function()
-            applyBuff("shield_block")
+            applyBuff("shield_block", nil, 2)
         end,
 
         handler = function()
-            applyBuff("shield_block")
+            applyBuff("shield_block", nil, 2)
         end,
     },
 
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `479 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 105 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      479 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Forever/Classes/Warrior.lua docs/research/2026-10-16-warrior-talent-dump.md \
  tests/Forever/warrior_spec.lua tests/Forever/helpers/load_warrior.lua
git commit -m "feat(warrior): rage from damage taken, Shield Specialization and Master of Defense as expected values, Shield Block's two blocks as aura stacks (protection design §1.3, §3; user rulings 2026-10-16)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-protection`

---

### Task 7: The Protection priority

Design §4 with rulings R3 and R4 and Deviations 6 and 7; §5.1's §4 cases. The string in `RegisterPack("Protection", ...)` is what `lua5.1 tools/make_pack.lua` prints on its third line (the patch carries it; Step 5 re-checks it).

**Files:**
- Modify: `tools/packs/warrior.lua`, `src/Hekili/Forever/Classes/Warrior.lua`
- Test: `tests/Forever/warrior_spec.lua` ("tanks in Protection: threat first, Shield Block kept up, no defensives, the rage thresholds as settings"; "writes priorities that name only registered abilities, auras, talents, settings and lists" learns the `threat` keys; "registers the Arms, Fury and Protection priorities exactly as tools/make_pack.lua prints them" and `tests/Forever/packs_spec.lua` unchanged)

**Interfaces:**
- Consumes: `threat.lost`, `threat.loose` (Task 5), `buff.shield_block.stack` (Tasks 4 and 6), `rage.current` (Tasks 2-3 feed it).
- Produces: settings `prot_heroic_strike_rage` 50 (0-100), `prot_cleave_rage` 40 (0-100), `challenging_shout_loose` 3 (0-10); the Protection pack (version 20261016287); the description without "(provisional)".

- [ ] **Step 1: Write the failing specs**

```bash
git apply <<'PATCH'
diff --git a/tests/Forever/warrior_spec.lua b/tests/Forever/warrior_spec.lua
index c73a3627..06259680 100644
--- a/tests/Forever/warrior_spec.lua
+++ b/tests/Forever/warrior_spec.lua
@@ -639,6 +639,7 @@ describe("Forever Warrior", function()
             cooldown = w.abilities,
             talent = w.talents,
             settings = w.settings,
+            threat = { situation = true, on_me = true, lost = true, loose = true }, -- Engine/Spec.lua's `threat` table
         }
         for _, p in ipairs(packs) do
             for list, entries in pairs(p.lists) do
@@ -664,6 +665,47 @@ describe("Forever Warrior", function()
         end
     end)
 
+    it(
+        "tanks in Protection: threat first, Shield Block kept up, no defensives, the rage thresholds as settings",
+        function()
+            local packs = assert(loadfile("tools/make_pack.lua"))("lists")
+            local prot = packs[3]
+            assert.are.equal("Protection", prot.name)
+            local order = {}
+            for i, e in ipairs(prot.lists.default) do
+                order[i] = e.action
+            end
+            assert.are.same({
+                "shield_bash",
+                "defensive_stance",
+                "taunt",
+                "mocking_blow",
+                "challenging_shout",
+                "shield_block",
+                "victory_rush",
+                "bloodrage",
+                "battle_shout",
+                "run_action_list",
+                "run_action_list",
+            }, order)
+            assert.are.equal("buff.shield_block.stack<2", prot.lists.default[6].criteria)
+            for list, entries in pairs(prot.lists) do
+                for _, e in ipairs(entries) do
+                    for _, never in ipairs({ "last_stand", "shield_wall", "healthstone" }) do
+                        assert.are_not.equal(never, e.action, list)
+                    end
+                end
+            end
+            local d = dofile("tools/packs/warrior.lua").packs[3].desc
+            assert.is_nil(d:find("provisional"))
+            assert.are.same({ 50, 40, 3 }, {
+                w.settings.prot_heroic_strike_rage.default,
+                w.settings.prot_cleave_rage.default,
+                w.settings.challenging_shout_loose.default,
+            })
+        end
+    )
+
     it("queues a strike only when the rage for the next strike and Whirlwind still arrives in time", function()
         local e = lw.env(w)
         e.query_time, e.mainhand_remains = 0, 2
PATCH
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `479 successes / 1 failure / 0 errors / 0 pending`.
- warrior_spec fails the new Protection case (the old list's order: no taunt, mocking_blow, challenging_shout).

- [ ] **Step 3: Write the implementation**

```bash
git apply <<'PATCH'
diff --git a/src/Hekili/Forever/Classes/Warrior.lua b/src/Hekili/Forever/Classes/Warrior.lua
index 192a5cb3..3cf4882e 100644
--- a/src/Hekili/Forever/Classes/Warrior.lua
+++ b/src/Hekili/Forever/Classes/Warrior.lua
@@ -1874,6 +1874,36 @@ spec:RegisterSetting("debuff_demoshout_enabled", false, {
     width = "full",
 })
 
+spec:RegisterSetting("prot_heroic_strike_rage", 50, {
+    type = "range",
+    name = "Protection: Heroic Strike Rage",
+    desc = "The Protection priority recommends Heroic Strike on one target at or above this much rage.",
+    width = "full",
+    min = 0,
+    max = 100,
+    step = 1,
+})
+
+spec:RegisterSetting("prot_cleave_rage", 40, {
+    type = "range",
+    name = "Protection: Cleave Rage",
+    desc = "The Protection priority recommends Cleave on three or more targets at or above this much rage.",
+    width = "full",
+    min = 0,
+    max = 100,
+    step = 1,
+})
+
+spec:RegisterSetting("challenging_shout_loose", 3, {
+    type = "range",
+    name = "Protection: Challenging Shout Enemies",
+    desc = "The Protection priority recommends Challenging Shout when at least this many enemies attack someone else.",
+    width = "full",
+    min = 0,
+    max = 10,
+    step = 1,
+})
+
 spec:RegisterOptions({ package = "Arms" })
 
 -- The three priorities, generated by tools/make_pack.lua (lua5.1 tools/make_pack.lua prints these strings, in this
@@ -1890,6 +1920,6 @@ spec:RegisterPack(
 )
 spec:RegisterPack(
     "Protection",
-    20261016796,
-    [[Hekili:TA12UTnpm4NLD3kwqwsBt66qDbw3WqxVOyyEa7ozRithlefjdj5(J(Jb)SpkBNe5tPTB9I2KWdFK8JuuImN8tsyc1cK7pD2PlNpB(YlUCjj0(yoqcZPSn014xK0T4))UwzbMLRKovpku0eN7Rk4c73KKvdIKjhyK7NF(LZjHz8KeO2qWWiHFvPHhaDz8bKlJ)fvR5ku4BZ1Qh4guivCYhlJ)cKcsd)bOmo0sLmyc(LmoiskJVrOyBkJlYrz)aXuUgTIktoyrOGU15qHmXfXpP36IHXILiGQTQY4fO(BbTIZCrqZ3Gy4m6ZcG6I6)XTzOl5un(dnsmtrEqRs5cKCOvPVzAUgyQTRO2a8pRaImzQc7eEAWBwvKMo1x60I8Y76547cEplJQxdtkmqKknnAnljy(WwMSJuIm1CslFoe2U25h6atfhfTIAY2l8vcBeMh4mRs)yKUOn87IQR1ng0(20bwuMkX1f67BvVHvO1G0E1PZA51lQPGoOlKr1)ksWn2jUJcbuf4C2jhRAqcB5G56GZ8DKrfI(EUgnwJdy7BMiubjaomsf8)Nlx7LAjqd92vBR5geaxA2m03rCd)zWH)UQyvt1hN8Uo48z9GS6eueT6a0EDn1vqV8OrXy5INApCD5rt17lEA1X1Rw87H0PHTuU0C1zdbEw1XAC(0DQ(PQ5fZEQ8R8osiU4YTBQZ6oxN242kIKf(X9vlybjDLasi3SBnHBby3MkjKP5wmyus4rB9elgZrGTH(DMC2iM41gCMDEhZoKeDheoar9Odj0JhDvkI2IXcQh5H2HfBdXEmoYRygRE7umJwZ(H3Re)RNXEjm3cpMR1C4)gbIBDPfc7XiqV96drIEZBJTh3FGTTYHs(XOF)BaooZn4w)(fKtXZH9gULGxjCaY9xJmeElhPG8VVOF6352ehqxmAI17oeV5)2x9uVCjQ(TyU1liUFyKeS7LpT8D3rVQXO9pM4ydsV46DSZR1pS55m78ApCwvS0cBMBdWTWgUGJpXS5fONuPM8Np]]
+    20261016287,
+    [[Hekili:TEvBVTTnq4Fl7lDBybAXonPTdrbyDddzddbdtfOFts0sNJimnPbjvm8qH(TV7KKTOEHQ2BbfTnH3Dph5Z9CKNIxe)P4OCMfIFA51lVBX1lUB57FxCK9WoioAhlBd7z8hKST4)(xALfYSCLKmDqOy5u4Rk5c7VlJxnjsMDqw8tlE7hwehvWZZHghbtwC0VP0WlGUkTd5Q0pZ0AUs)tvP)kSgKg(lqvAKLjZGRQs)eRuARs3xaOR2c0KLPFgWLSLAPPkLTNDa9dZfiYRs)OqLTPkDdSdDPChA5VXukFgdKjZ78lsW2sHvkZPn0pR3QW)ZyrgaqZwvv6TO9hbTINr7hnFdIb50ViagTh3ZTfT7jnJsqb3IBOvAU85GQ0NqiYpEIm4X7pzgBZjl3zd)zMq0U3EeycBHXQKaDW0ql67eSdG(BX1YqNdWIHwTMlWkeRMdnb70qMA7kMne)RvajMcvP9k(6WVzv561bURguUR6pgf4pe(JzfeZEvPbsuRxN8CwE4IP980XkX0uN6ftxAh6NBQdn1eqYkMP40IVsyJWyjDZ4yTfAGzdekSu449wu0GvTKvc1(bU9MmLsKR2ldQHmqdBzCP5HfUXJuNqGQmcJtu)jqug4HqdyTOztWiFtQ9WfUJudPLhFgQp(UUeulBVFPleVWZSk9HeDzF6fdqLtY1X4sRgKvQ1G0E)YR7f1fPQWa0LYKMFlrWn2ROluczkGcMwhlBGe2YbZdH38vd0GCLOJHcA(9qDBN9G17iqd2KpL16M(eg1ZtBOCOHsDwULsV9ltzRvcC)ntGTTOXZmbBxnt1cG7696apfzoGyZe8)PNi6KSPbNeYRgvdizReq(BoMHXXpDEYuYSsJHy4A5UN(9t(xuFfi2Lr3aoVQXrLJxrzt6fAs9LKZxn6mJALWZKl)sRGkxz7z6((cTEy7LVpt2SbIrcWMLNu91ykR(TJlJfBIza91MPECxCe(4kvyh8Km1izOxUB4C8NEQEoGwfu8hp(qsCu7jk2Iq4XfNth52n(CZzRfhLP5wqZz0Ka)hB2OK9wpjZTS7MmpkgcQB9a14cVlG)pBhPeFNNepOVmoYrKqfmm03ni0U91L1f2L0E2MkLV)CkVw8prOICoL1fwIoZM65eQZxj)Q1jFcBNweFYXbTidLANxzZPT3rKuV4ufkFYQXfkCYjwPWoxXYz2SPyyhw03SyULH(gNAZpKR7sGZKyoAjAsSPWXxbXD(opO7DoV5USy0SCtc(zn)3u1WoS8oZ34Agz9CU84yCUtkovh)0QvCaXoionu5u59dEYR70JJLudMTKaAX1E3z9VuahP0PDT)aLnVgM08bU0vweWEFnCMyBFlTUJ603gnxp1fFE9DVwZ3PDzTrVo9Pn3ZxAlON0Fe2Wf8Q0VR9R6)(AZX)7p]]
 )
diff --git a/tools/packs/warrior.lua b/tools/packs/warrior.lua
index ef376380..78c572fe 100644
--- a/tools/packs/warrior.lua
+++ b/tools/packs/warrior.lua
@@ -73,30 +73,38 @@ actions.rotation+=/berserker_stance,use_off_gcd=1,if=!buff.berserker_stance.up
     },
     {
         name = "Protection",
-        desc = "Forever Protection Warrior (provisional): Defensive Stance, Shield Block up, Revenge and Shield Slam, "
-            .. "Sunder Armor stacked to 5, Heroic Strike or Cleave with spare rage.",
+        desc = "Forever Protection Warrior: Defensive Stance, Taunt when the target turns away, Shield Block kept up, "
+            .. "Revenge and Shield Slam, Sunder Armor stacked to 5, Heroic Strike or Cleave with the rage hits bring. "
+            .. "No defensives: Last Stand, Shield Wall and Healthstones are the player's call.",
         simc = [[
 actions.precombat=battle_shout,if=!buff.battle_shout.up
 actions.precombat+=/charge,use_off_gcd=1
 actions.precombat+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
 actions=shield_bash
 actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up
+actions+=/taunt,use_off_gcd=1,if=threat.lost
+actions+=/mocking_blow,if=threat.lost&cooldown.taunt.remains>1
+actions+=/challenging_shout,if=threat.loose>=settings.challenging_shout_loose
+actions+=/shield_block,use_off_gcd=1,if=buff.shield_block.stack<2
 actions+=/victory_rush
-actions+=/shield_block,use_off_gcd=1,if=!buff.shield_block.up
 actions+=/bloodrage,use_off_gcd=1,if=rage.current<20
 actions+=/battle_shout,if=!buff.battle_shout.up
 actions+=/run_action_list,name=aoe,if=active_enemies>=3
-actions+=/call_action_list,name=generic
-actions.aoe=demoralizing_shout,if=!debuff.demoralizing_shout.up
+actions+=/run_action_list,name=single
+actions.single=revenge
+actions.single+=/shield_slam
+actions.single+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<3
+actions.single+=/thunder_clap,if=!debuff.thunder_clap.up
+actions.single+=/demoralizing_shout,if=settings.debuff_demoshout_enabled&!debuff.demoralizing_shout.up
+actions.single+=/concussion_blow,use_off_gcd=1
+actions.single+=/heroic_strike,use_off_gcd=1,if=rage.current>=settings.prot_heroic_strike_rage
+actions.single+=/sunder_armor
+actions.aoe=thunder_clap,if=!debuff.thunder_clap.up|active_dot.thunder_clap<active_enemies
+actions.aoe+=/demoralizing_shout,if=!debuff.demoralizing_shout.up
 actions.aoe+=/revenge
 actions.aoe+=/shield_slam
-actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=40
+actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=settings.prot_cleave_rage
 actions.aoe+=/sunder_armor
-actions.generic=revenge
-actions.generic+=/shield_slam
-actions.generic+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<3
-actions.generic+=/heroic_strike,use_off_gcd=1,if=rage.current>=50
-actions.generic+=/sunder_armor
 ]],
     },
 }
PATCH
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `$HOME/src/hekili/.lua/bin/busted`

Expected: `480 successes / 0 failures / 0 errors / 0 pending`.

- [ ] **Step 5: Verify** (from the worktree root)

```bash
stylua --check .                                              # [silent]
lua5.1 tools/make_pack.lua | sed -n 3p | cut -c1-24     # 20261016287 Hekili:TEvBV
```
```bash
make check LUA_ENV=$HOME/src/hekili/.lua
#   lint:      Total: 0 warnings / 0 errors in 105 files
#   fmt-check: (silent)
#   typecheck: Diagnosis completed, no problems found
#   test:      480 successes / 0 failures / 0 errors / 0 pending
#   syntax:    (silent)
#   api-check: ok: no direct game API read in 65 loaded files; inventory diff empty
```

- [ ] **Step 6: Commit**

```bash
git add tools/packs/warrior.lua src/Hekili/Forever/Classes/Warrior.lua tests/Forever/warrior_spec.lua
git commit -m "feat(warrior): the Protection priority: threat first, Shield Block kept up, Heroic Strike and Cleave at user-set rage, no defensives (protection design §4)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git status --short                                            # [empty]
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin forever-protection`

---

### Task 8: CHECKPOINT: Protection in game (design §5.2), deferred to the user

No code unless an answer calls for it. An answer that changes code is its own commit with the verification block; the changes the table names are data in Warrior.lua (a constant, a registration) or one line of the pack (regenerate with `lua5.1 tools/make_pack.lua`).

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin forever-protection
git -C ~/src/hekili checkout --detach forever-protection
```

Then `/reload` in game (no new file).

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game and report each answer**

A Protection-specced Warrior with a shield, ForeverProbe loaded (`VSCopy`, `/vscopy` reopens it; S = secret), open-world mobs (no dummies). Possible at 22-30: Shield Block (16), Revenge (14), Taunt (10), Mocking Blow (16), Disarm (18), Victory Rush (20), Challenging Shout (26), Concussion Blow (30, with 20 Protection points), Shield Specialization, Master of Defense. Waits for 40: Shield Slam (level 40, 30 points). Every line is under 255 characters.

The talent tree needs no question: the 2026-10-16 trait walk (`docs/research/2026-10-16-warrior-talent-dump.md`, R6) confirmed the registrations.

| # | Question | Line | Answer -> action |
|---|---|---|---|
| Q0 | the build loads, the rate line exists | `/run local V,t=Hekili.VirtualState,GetTime() VSCopy(V.TakenRate(1,t),V.Power(1,t).est)` | numbers -> none; an error -> stop and report |
| Q1 | which Shield Block field counts blocks | out of combat, after Shield Block: `/run local a=C_UnitAuras.GetPlayerAuraBySpellID(2565) VSCopy(a and a.applications,a and a.charges,a and a.maxCharges,a and a.duration)` | `2` in one field -> the aura read maps it to stacks; 0/nil everywhere -> the belief alone (as designed) |
| Q1b | the belief spends a block (new) | in a fight, after Shield Block and after each block: `/run local r,n=Hekili.VirtualState.Aura("player",2565,GetTime()) VSCopy(r and format("%.1f",r.est),n)` | 2, then 1, then nil -> none; no change on a block -> report the Q2 line's flag for that hit |
| Q2 | every hit reaches the belief | in a fight: `/run local f=CreateFrame("Frame")f:RegisterEvent("UNIT_COMBAT")f:SetScript("OnEvent",function(_,_,u,e,fl,a)if u=="player"then VSCopy(format("%.2f",GetTime()),e,fl,a)end end)` | after each hit `/run local r=Hekili.VirtualState.Power(1,GetTime()) VSCopy(format("%.1f %.1f %.1f",r.lo,r.est,r.hi),UnitPower("player",1))`: the estimate moves on every WOUND -> none |
| Q3 | Devastate / Commanding Shout known | `/run VSCopy(IsPlayerSpell(403196),IsPlayerSpell(403195),IsPlayerSpell(403215),IsPlayerSpell(29787),C_Engraving~=nil)` | all false -> nothing registered; true -> design §3's registrations (a follow-up commit) |
| Q4 | the rage factor at this level, Battle Stance | 20 hits in Battle Stance: the Q2 line plus `/run VSCopy(UnitPower("player",1),select(2,UnitArmor("player")),UnitHealthMax("player"),UnitLevel("target"))` before and after, out of combat | rage ~ sum(pre) x 10 / max -> none; another factor -> `RAGE_TAKEN_FACTOR` (data) |
| Q5 | sanity: Defensive Stance's 10% divided back (R1: no longer a decision) | Q4 again in Defensive Stance, same mob type | rage per post-armor point about 1/0.9 of Q4's -> none; equal to Q4's -> report (R1 assumed the server's rage ignores the stance; the user decides) |
| Q6 | the armor step | Q4 with armor under 130 (remove pieces) | double -> D2 (R2: still not modelled unless the user reopens it) |
| Q7 | block value and the full block's amount | `/run VSCopy(select(2,UnitArmor("player")),GetShieldBlock(),InCombatLockdown())` in and out of combat; Q2 lines for `BLOCK` | plain out, S in -> the cache; a BLOCK amount above 0 -> use it in place of the EMA |
| Q8 | threat reads | in a fight: `/run VSCopy(UnitThreatSituation("player","target"),UnitThreatSituation("player"),UnitIsUnit("targettarget","player"),UnitExists("targettarget"),UnitIsUnit("nameplate1target","player"))` | plain -> none; S for the plate -> `threat.loose` counts the target and focus only (documented) |
| Q8b | the engine's threat table (new) | in a fight of two or more: `/run local s=Hekili.State.threat VSCopy(s.situation,s.on_me,s.lost,s.loose,Hekili.VirtualState.LooseEnemies())` | `lost` true exactly while the target attacks someone else; `loose` the mobs not on us -> none |
| Q9 | Shield Specialization and Master of Defense numbers | answered 2026-10-16 (R5: 20% and 50% a rank, 5 rage); at a new rank only: `/run for _,i in ipairs({12298,1310316,12792,29787}) do VSCopy(i,C_Spell.GetSpellDescription(i)) end` | a different chance -> `SHIELD_SPECIALIZATION_CHANCE` / `MASTER_OF_DEFENSE_CHANCE` |
| Q10 | the pseudo-spec's role | `/run local i=GetSpecialization() VSCopy(i,i and select(5,GetSpecializationInfo(i)),Hekili.State.role.tank)` | recorded (`tanking` is not used) |
| Q11 | the priority | a pull of one, then three | Taunt only when the mob turns away; Shield Block pressed whenever a block is spent and it is ready; Revenge after blocks; HS above the threshold as rage arrives from hits; Thunder Clap and Demoralizing first at 3+; never Last Stand, Shield Wall or a Healthstone |

Known limits (say them with the results):
- A full BLOCK's rage is estimated from the average unblocked hit (capped at the block value) until Q7 shows the event's amount; its band is the whole estimate.
- The armor and block value are cached out of combat: a gear swap in combat leaves them stale until it ends.
- `__taken` freezes the learned rate at each reset; a burst of hits shows in the forecast one reset later.
- A hit's level falls back to the player's when the target is not attacking us (its attacker is then unknown).

Fix what the user reports, then repeat the affected lines. Continue only when the user confirms. When the session ends: `git -C ~/src/hekili checkout --detach forever`.

---

## Self-Review

**1. Coverage of the design**

| Design | Task |
|---|---|
| §1.1 facts (UNIT_COMBAT plain, kinds and flags, armor second return, GetShieldBlock out of combat) | 1 (source, stat row), 6 (`select(2, ...)`) |
| §1.2.1 `Obs.PlayerHit = 36`, `I.HitKind`, the stage for every unit, attributed or not, the level rule, a secret amount dropped with a `Note` | 1 |
| §1.2.2 the `taken` declaration on the paying entry, forwarded as `d.taken`, bound to the `now` context | 2 (Deviation 1) |
| §1.2.3 est/lo/hi by the width, clamped; `R.gain`; one `modelled` sample; a non-positive gain ignored; zero allocation | 2 (Deviation 2) |
| §1.2.4 ten one-second bins, `VS.TakenRate`, combat only, cleared at `CombatEnd` | 2 |
| §1.2.5 the generated `__taken` entry, skipped by the walk, `stop` out of combat | 3 |
| §1.3 the Warrior's `taken`: armor, block value, EMA for BLOCK, the two procs, MISS/HEAL 0, the stance and Shield Wall factors, the doubling not modelled | 6 (R1, R2, R5) |
| §1.3 the stat cache's `GetShieldBlock` | 1 |
| §2 `threat.situation/on_me/lost/loose` on `all`; `VS.LooseEnemies`; secret as 0/false | 5 (Deviations 4, 5) |
| §3 Improved Shield Block / Improved Taunt / Toughness not registered; Defiance 3 | unchanged; 6 (R6 comment and dump) |
| §3 Shield Block: aura stacks, no `charges`, `consumedBy`, `now` 2 stacks | 4 (core), 6 (content; Deviation 3) |
| §3 Shield Specialization and Master of Defense comments | 6 |
| §3 Devastate / Commanding Shout only after Q3 | 8 (Q3) |
| §4 settings, the list, the description, the regenerated pack | 7 (Deviations 6, 7) |
| §5.1 tests: resources, adapter, player, alloc, warrior §1; engine_load, event_facade §2; auras, warrior §3; warrior §4, packs unchanged | 1-7 (each task's Files line names the cases) |
| §5.2 checkpoint | 8 (Q5 a sanity read per R1, Q9 answered per R5, Q1b and Q8b added) |
| §6 decisions D1-D6 | D1 replaced by R1; D2 = R2; D3 = R3; D4 = R4; D5 replaced by R5; D6 = R6 |
| §7 out of scope | "Deliberately not built" |

**2. Placeholder scan:**
- No "TBD", "TODO", "implement later" or "similar to Task N"; R5 replaced the planned TODO constants with the tooltips' values.
- Every code step is a `git apply` patch from the replay, and every test step states its measured busted counts.

**3. Names across tasks:** spelled the same in every task and in the checkpoint:
- `Obs.PlayerHit`, `I.HitKind`, `I.HitName`, `I.NowAt`, `I.nowCtx`, `I.TAKEN_WINDOW`
- `R.taken`, `R.takenBin`, `R.takenSec`, `VS.TakenRate`, `__taken` (`TAKEN` in the Adapter), `takenEntry`
- `consumedBy`, `VS.LooseEnemies`, `Facade.issecretvalue`, `threat.situation/on_me/lost/loose`
- `prot_heroic_strike_rage`, `prot_cleave_rage`, `challenging_shout_loose`

**4. Review Focus:** each line has its pinned tests (named in Review Focus 1-5).

**Concerns for the orchestrator:**
- (a) R1 divides Defensive Stance's 10% back unconditionally; if the server computes rage after the stance, rage reads 11% high in Defensive Stance. Q5 is the sanity read; the calibration does not absorb it (the taken gain is outside the swing scale by design).
- (b) The Protection pack's version reads as "reverted" in a saved profile (Deviation 7).
- (c) A `taken` that raises is counted in `I.nowErrors`/`I.nowError` (Snapshot shows them) and the hit pays nothing.
- (d) `VS.LooseEnemies` counts a token as of its last UNIT_TARGET or plate event; a mob that changes target without the event stays counted until the next one.
