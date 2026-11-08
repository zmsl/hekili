# CDM Facts, Always On: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Cooldown Manager (CDM) becomes an always-on, adaptive fact layer under the belief: every CDM item in any
viewer is evidence, a pure reducer turns it into one fact per tracked aura and unit, and the belief's aura records take
that fact by one rule set; with no fact the model runs alone.

**Architecture:** A pure reducer (`Game/State/Sources/Presence/Reduce.lua`) between the providers and the belief. The
CDM leaf (`Presence/CooldownViewer.lua`) keeps a complete cooldownID->aura map built out of combat and sweeps its slots
by `rawget` at poll 15; it installs no hooks. The router (`Presence/Router.lua`) holds the reduced records and picks the
highest standing with evidence; `Sources/Auras.lua` `apply` reconciles. The game layer removes the experimental setting
and shows a coverage line computed in `Options/`; the CDM debug information is a section of the belief's own snapshot.

**Tech Stack:** Lua 5.1 (WoW), busted, luacheck, StyLua, the combat harness (`tests/Game/harness/`).

**Spec:** `docs/superpowers/specs/2026-11-07-cdm-default-design.md` (binding; decisions 92-115), on top of the
providers spec (`docs/superpowers/specs/2026-10-23-providers-design.md`; 79 and 89 superseded, 82 superseded for the
viewer). Cited "spec §N". Line numbers are as of `integ/0.7` a0bd6f8dd. Review round 1:
`~/src/hekili-central-needs/cdm-design-review.md`.

**Prerequisites and central lanes in flight:**
- **CN8** (cooldown lane: `Families/Casts.lua`, `Families/State.lua`, `tests/Game/harness/world.lua`, `loop.lua`, and
  `Options/Options.lua` near `:4175` plus `Locales/enUS.lua`, `zhCN.lua`): Task 6 (removes the setting from
  `Options.lua` `:312`, `:4212-4227` and the locales) and Task 8 (`loop.lua` `:333`, `:368`; maybe `world.lua` `:51`)
  run **after CN8 merges into integ/0.7**. Tasks 1-5 and 7 do not touch CN8's files.
- **CN13** (generic consumption model: `Families/Auras.lua` `Obs.PlayerHit`, `Sources/Player.lua`): owner Q4, CN13
  builds the generic floor `I.auraFloor[j]` (spec §7). This plan writes it (Task 4b) and never edits
  `Families/Auras.lua` unless CN13 merged without the floor (Task 4c). Tasks 4a/4b/5 edit `Sources/Auras.lua`; if CN13
  edits it too (unverified), merge CN13 first and rebase.

## Global Constraints

- **Border.** Nothing under `src/Hekili/Game` names the core; the core reaches the belief only through Drain, Build,
  SetLog and the facade. This plan adds **no** crossing: the coverage line reads the client API and `class.auras` in
  `Options/`; the CDM debug section is an `I.OnSnapshot` callback inside `Game/`, reaching the core as text through the
  SetLog logger; `Hekili.cdmOff` is read by the core's own `providersOf`. Run `tools/check_border.sh` in every task
  that touches `src/` (expected output unchanged). Any new crossing: stop and ask the owner.
- **Class-neutral.** No class, spell, aura or spell ID under `src/Hekili/Game` or `tests/Game` (`tests/boundary_spec.lua`).
  IDs live in `tools/data/cooldownviewer/*.lua` and docs.
- **Secrets.** `auraInstanceID` only via `api.issecretvalue(x) or x ~= nil`; every other client value through `S.Plain`;
  never `a and b or c` on a raw value; nothing read passed back to an API. New API names (`C_Spell.GetOverrideSpell`,
  viewer `IsVisible`, `GetNumChildren`; in Task 11 `C_Secrets.GetSpellAuraSecrecy`, `C_UnitAuras.GetUnitAuraBySpellID`)
  join `tools/api_inventory.txt` (`make api-check`).
- **No allocation in recurring paths.** The sweep, `I.ReduceFact`, the router's reduction and `apply` allocate nothing
  (`tests/Game/State/alloc_spec.lua` extended). Getters that allocate run out of combat. The only in-combat insert is a
  new child's frame-to-slot entry, bounded by `MAX_SLOTS = 128`.
- **Taint rule (spec §3.5).** rawget on items; on Blizzard frames only `GetChildren`, `GetNumChildren`, `IsVisible`; no
  hooks of any kind (`HookScript` removed); nothing written to Blizzard frames.
- **No jitter.** UNKNOWN never flips the belief; no per-poll re-staging (spec rule 2.5.4); a viewer arm may not raise
  flicker beyond seed noise (±0.3/min) on any spec.
- **First gate.** The `default` A/B arm (viewer off) is identical to the digit before and after every task (providers
  plan "First gate", `docs/superpowers/plans/2026-10-23-providers.md:47-55`).
- **Model sizing.** **[belief]** tasks change `src/Hekili/Game`: Opus builds, Fable reviews. **[options/docs/harness]**:
  Sonnet builds, Opus reviews. Runs (`make gate`, `make gate-ab`) through `tdf-runner` (haiku) with a report file.
- `make check` green on every commit; `make gate` on every [belief] task before its merge; `make gate`, `make gate-ab`,
  `make accuracy` take `/tmp/hekili-gate.lock` themselves (never wrap them); other busted runs go under
  `flock /tmp/hekili-gate.lock`.
- **Deferrals.** Every real deferral a task makes (a finding not fixed now and not in a named next commit, a ruling that
  accepts a gap, a postponed step, a pending in-game check) goes into the task's report as "Deferral candidates" (what,
  why, trigger); the controller writes the ledger the same turn.
- Every commit ends with the trailer given in the brief that dispatches the task.

## Module Layout

```
src/Hekili/Game/State/Sources/Presence/Reduce.lua          NEW      I.ReduceFact (pure)
src/Hekili/Game/State/Sources/Presence/CooldownViewer.lua  REWRITE  map, collect, slots, sweep, settle, self-off; no hooks
src/Hekili/Game/State/Sources/Presence/Router.lua          MODIFY   reduced records, standings, Sweep, onEdge on change
src/Hekili/Game/State/Sources/Presence/Default.lua         MODIFY   Sweep/Counts/Mappable no-ops
src/Hekili/Game/State/Sources/Presence/Direct.lua          NEW, CONDITIONAL (Task 11)
src/Hekili/Game/State/Sources/Auras.lua                    MODIFY   apply rules 2.5.1-8, ours, Sweep call, exitFix, CDM snapshot section
src/Hekili/Game/State/Families/Now.lua                     MODIFY   one line: our cast sets I.auraOurs (Task 4b)
src/Hekili/Hekili.toc                                      MODIFY   Reduce.lua before CooldownViewer.lua (line 54)
src/Hekili/Engine/Schema/Tracked.lua                       MODIFY   providersOf: viewer = Hekili.cdmOff ~= true
src/Hekili/Options/Options.lua (+ Locales)                 MODIFY   remove the setting, its Experimental entry and strings; coverage line
src/Hekili/Options/Coverage.lua                            NEW      the core-side coverage helper (or a local in Options.lua)
tests/Game/State/helpers/fake_api.lua                      MODIFY   the any-layout fake viewer
tests/Game/State/{reduce,fake_viewer,viewer,router,auras,alloc}_spec.lua
tests/Forever/providers_option_spec.lua                    REWRITE  no option; viewer always on
tests/Game/harness/{drive,observer,scenarios,ab,loop}.lua  MODIFY   (Task 8, after CN8)
tools/data/cooldownviewer/DRUID.lua                        NEW      from the 2026-11-07 probe (§2 and §8 of the probe file)
DEVELOPMENT.md                                             MODIFY   Hekili.cdmOff (debug-only session off)
```

## Review Focus

1. **The reducer is pure and total.** Every row of spec §2.3 in the table test; no upvalue read but the constants.
2. **No layout assumption.** No item anywhere is UNKNOWN; unconfigured, released, invisible, unmapped, settling and
   secret-field slots are not live; roles never consulted.
3. **No wrong DOWN.** A silent slot counts as NONE only for an application that same slot was seen holding (the seen
   rule, per slot, decision 115); a DOWN closes only with `ours` (the target too since decision 111's 2026-11-08 amendment; after our cast only past
   `REFRESH_LAG`, D14); the walk wins only out of combat.
4. **Never stuck up.** No `math.huge` on the target or with a numeric duration; bounded lapse; a hold re-stage about every `HOLD - LAPSE`,
   at most once per poll (every poll at 0.5 s or slower rates).
5. **Reconciliation only in `Sources/Auras.lua`** (plus Now.lua's one line; `Families/Auras.lua` only in Task 4c).
6. **Default arm identical**; viewer arms measured.
7. **Border, secrets, allocation** as the Global Constraints.

## Task order and parallelism

| Wave | Tasks (parallel within a wave) | Needs |
|---|---|---|
| A | 1 Reducer [belief] · 2 Fake viewer [harness] · 5 Exit counter [belief]: **startable now** (none depends on the seen rule; no file shared with CN8 or CN11) | nothing |
| B | 3a Map and collect [belief] | 1, 2 |
| C | 3b The sweep [belief] | 3a |
| C' | 3c Target settle, the seen rule, self-off [belief] | 3b |
| D | 4a Router and reduced records [belief] | 3c, 5 (both edit `Sources/Auras.lua`: 5 first) |
| E | 4b Reconciliation in apply, `ours`, hold, floor write, snapshot section [belief] | 4a |
| F | 6 Always on: remove the setting [options] · 7 Coverage line [options] | 4b and CN8 merged (6); 2 and 6 (7) |
| G | 8 Harness loops and layouts [harness] | 4b, **CN8 merged** |
| H | 9 A/B and docs [docs] | 8 |
| I | 10 In-game checklist (owner) | a dev build with 1-7 |
| J | 4c CN13 fallback floor [belief] (only if CN13 merged without `I.auraFloor`) · 11 Direct provider [belief], CONDITIONAL on the Shaman flag-0 finding | 4b |

Tasks that depend on the seen rule (decision 115): 3c (builds it), 4a (reduces its liveness), 4b (its red tests and
`ours`), 8 (the `mixed` layout's silent and lagging items), 9 (reads its counts) and 10 (the F12 check).

**Release gate** (the owner's acceptance list, all of it): no release is tagged from a branch holding Task 6 until Task 9
shows no flicker rise on any spec (the Shaman `consumedBy` and target-DoT-past-duration rows included) and Task 10
passes CDM-T (taint), CDM-I (no wrong DOWN in a dungeon), CDM-O (no target-switch mis-attribution), CDM-P (a partner's
copy never closes our record), the invisible-viewer and Alt-Z rows and the coverage rows, with `tools/check_border.sh`
unchanged. If the gate fails, the controller reverts Task 6's commit (the setting returns, default off) or holds the
release; players meanwhile have `Hekili.cdmOff`.

---

### Task 1 [belief]: The fact reducer, table-driven test first

**Files:** Create `src/Hekili/Game/State/Sources/Presence/Reduce.lua`, `tests/Game/State/reduce_spec.lua`;
Modify `src/Hekili/Hekili.toc` (before `Presence\CooldownViewer.lua`, line 54).

- [ ] **Step 1: Failing test.** One row per spec §2.3 case:

```lua
local load = require("Game.State.helpers.load")
describe("I.ReduceFact (cdm-default spec §2.3)", function()
    local I
    before_each(function() I = load.module().VirtualStateInternal end)
    -- nLive, nUp, nNone, nStale, tUp, tNone -> state, agree
    local ROWS = {
        { "no item anywhere", 0, 0, 0, 0, 0, 0, "UNDECIDED", true },
        { "no item, only stale", 0, 0, 0, 2, 0, 0, "UNDECIDED", true },
        { "live but no answer (totality)", 1, 0, 0, 0, 0, 0, "UNDECIDED", true },
        { "one item up", 1, 1, 0, 0, 5, 0, "UP", true },
        { "two items up", 2, 2, 0, 0, 5, 0, "UP", true },
        { "one item none", 1, 0, 1, 0, 0, 5, "DOWN", true },
        { "all none, one stale", 2, 0, 1, 1, 0, 5, "UNDECIDED", true },
        { "up and none, up fresher", 2, 1, 1, 0, 6, 5, "UP", false },
        { "up and none, same time", 2, 1, 1, 0, 5, 5, "UP", false },
        { "up and none, none fresher", 2, 1, 1, 0, 5, 6, "UNDECIDED", false },
        { "up with a stale peer", 2, 1, 0, 1, 5, 0, "UP", true },
    }
    for _, r in ipairs(ROWS) do
        it(r[1], function()
            local s, a = I.ReduceFact(r[2], r[3], r[4], r[5], r[6], r[7])
            assert.are.equal(I[r[8]], s)
            assert.are.equal(r[9], a)
        end)
    end
    it("allocates nothing", function() --[[ collectgarbage count around 1e4 calls, as alloc_spec does ]] end)
end)
```

- [ ] **Step 2: Run, expect failure** (`flock /tmp/hekili-gate.lock busted tests/Game/State/reduce_spec.lua`).
- [ ] **Step 3: Implement** `I.ReduceFact` as spec §2.3 (only `I.UP`, `I.DOWN`, `I.UNDECIDED` cached at load). The seen
  rule (decision 115) is folded into liveness by the leaf (Task 3c), so the reducer takes no extra input.
- [ ] **Step 4: Run** PASS; `make check`; first gate `IDENTICAL`.
- [ ] **Step 5: Commit** `feat(belief): the pure fact reducer (cdm-default decision 94)`.

### Task 2 [harness]: The any-layout fake viewer

**Files:** Modify `tests/Game/State/helpers/fake_api.lua` (`:81-82`, `:666-712`); Create
`tests/Game/State/fake_viewer_spec.lua`. Keep `ctl.ViewerItem` / `ctl.ViewerShow` working for the old specs until
Task 3a rewrites them.

- [ ] **Step 1: Failing tests,** one per fake behaviour:
  - `ctl.ViewerItem(viewer, layoutIndex, id)` (`id == nil`: unconfigured); `ctl.ViewerChild(viewer)` a non-item child
    (no `cooldownID`, no `layoutIndex`);
  - viewers: `IsVisible()` (false when `ctl.viewer.shown[name]` or `ctl.viewer.parentShown` is false), `GetChildren()`
    (varargs), `GetNumChildren()`; `ctl.ViewerAcquire(viewer, id)` adds a child (pool growth, also in combat; a new frame table, so an item can be
    replaced by a different frame for the same cooldownID; spec F13), and an acquired item whose aura is up lights at
    once (F13) unless `silent` or `lag`;
  - `ctl.ViewerAura(item, unit|nil)` follows the client order (BD:368-392): changing a held aura clears first, then sets
    (`auraInstanceID = SECRET`, `auraSpellID` SECRET or plain per `ctl.viewer.plainSpell`, `auraDataUnit = unit`);
  - `ctl.ViewerRelease(item)`: `cooldownID = nil` (BD:95), then the aura clear (BD:98), then `layoutIndex = nil`;
  - `ctl.ViewerRepoint(item, id)`: `cooldownID = id`, then refresh (BV:137-147);
  - `GetCooldownViewerCategorySet(c, allowUnlearned)`: `sets[c]` plus `unlearned[c]` when true;
  - infos may carry `overrideSpellID`, `overrideTooltipSpellID`, `linkedSpellIDs`, `hasAura`, `selfAura`, and a
    `linkedSpellID` that reads SECRET; `api.C_Spell.GetOverrideSpell(id)` from `ctl.overrides[id]` else `id`;
  - `ctl.ViewerAuraBySpell(unit, spellID, up, source)`: every configured item in any viewer whose info candidates name
    the spell gets `ViewerAura`, **only when `source` is "player"** (a partner's copy lights nothing, F10);
  - `HookScript` on items and `api.hooksecurefunc` record their calls (asserted unused later);
  - `ctl.ViewerAuraBySpell` lights an item only if the spell is one of its info's candidates (a test pins it);
  - **silent item** flag (`item.silent = true`, F12): the item never lights, whatever the aura does;
  - **lag** option (`ctl.viewer.lag = 1`, I-B): pending lights are applied at the next `ctl.Tick`
    (`fake_api.lua:793`), not in the call that raised the aura (the client's `UNIT_AURA` arriving after our cast's
    record write); a removal of an aura stays immediate. A **refresh of a held item stays held**: under lag the clear
    and the set move together at the Tick (the client's pair is one call, BD:368-380), so the fake never shows a
    one-poll silence (UNKNOWN, floor 0) the real client does not; Task 8's `viewer-mixed` flicker feeds the release
    gate. Tasks 4b and 8 use this same mechanism. Tests for both, plus "under lag, a held item's refresh is never read
    silent at any sweep".
- [ ] **Step 2: Run, expect failure. Step 3: Implement** in the fake only. **Step 4:** `make check`; old viewer and router
  specs still pass. **Step 5: Commit** `test(harness): the any-layout Cooldown Manager fake`.

### Task 3a [belief]: The CDM leaf, part 1: the map and the collect

**Files:** Rewrite the map and collect of `src/Hekili/Game/State/Sources/Presence/CooldownViewer.lua`; Modify
`Presence/Default.lua` (no-op `Sweep`, zero `Counts`, `Mappable` false); Rewrite `tests/Game/State/viewer_spec.lua`
(map/collect part); `tools/api_inventory.txt`.

- [ ] **Step 0: Read** Blizzard `GetAssociatedAuraSpellPriority` (BD:327-358, wow MCP flavor `forever`) and record in the
  report whether the base spell can bear the aura while links exist; widen §2.2's candidate set if so.
- [ ] **Step 1: Failing tests:**
  1. "maps by spellID, overrideSpellID, overrideTooltipSpellID, linkedSpellIDs and GetOverrideSpell; never the singular linkedSpellID"
  2. "maps unlearned entries (allowUnlearned)"
  3. "Omen-like: linked proc tracked, passive untracked: UP counts for the proc" (F4)
  4. "Eclipse-like: two linked procs, the pack tracks one: ambiguous (maps to the tracked one), UP counts for none" (I2)
  5. "an item naming two pack auras is ambiguous: maps to both, UP for neither"
  (An ambiguous slot's silence is never live once Task 3c's seen rule lands: spec §2.2, decision 97.)
  6. "the collect keeps every child once, items and non-items; past MAX_SLOTS a child is ignored and counted (overflow)"
  7. "collects at activation, rebuild and PLAYER_REGEN_ENABLED; in combat only on GetNumChildren growth, the new indices only, allocating no table"
  8. "a NEW pack aura added to the fake viewer with no code change is mapped" (owner acceptance, generic)
  9. "no HookScript and no hooksecurefunc call is made"
- [ ] **Step 2: expect failure. Step 3: Implement** spec §3.1 and §3.2's collect: `cdvToJ` (j, or -a with `amb[a]`),
  `Q.Mappable(j)`, the slot arrays preallocated to `MAX_SLOTS` (`sJ`, `sAmb`, `sV`, `sAns`, `sUnit`, `sT`, `sSeen`,
  `sCd`; `sAns`/`sUnit` are what the slot is counted as; `sSeen`/`sCd` are used from Task 3c), the
  frame-to-slot weak map, `known[v]` children per viewer. Delete the `HookScript` path (`:107-133`). Header credits
  TellMeWhen (Cybeloras) for the hidden-viewer rule, the all-viewers presence bit and the mapping (ideas, GPL-3.0).
- [ ] **Step 4:** specs; `make check`; `tools/check_border.sh`; first gate `IDENTICAL`.
- [ ] **Step 5: Commit** `feat(belief): CDM leaf map over all candidates and an allocation-free collect (decisions 97-98, 101)`.

### Task 3b [belief]: The CDM leaf, part 2: the sweep

**Files:** `Presence/CooldownViewer.lua` (sweep), `tests/Game/State/viewer_spec.lua`, `alloc_spec.lua`.

- [ ] **Step 1: Failing tests:**
  1. "a cooldown entry (Essential) holding an aura is UP evidence; a Buff icon entry for the same aura agrees" (F6)
  2. "no item in any viewer: counts all zero"
  3. "an unconfigured slot, a non-item child, an unmapped id and a secret cooldownID are not live"
  4. "a held slot for the other unit, or with a secret unit, is not live for this unit" (I3)
  5. "a viewer that is not visible (itself or its parent) makes its slots stale; visible again they count, with tUp/tNone at that poll" (I3)
  6. "the refresh pair (clear then set in one call) is never seen as NONE"
  7. "a release, held or not, drops the slot (no NONE)"
  8. "a re-point moves the slot's evidence from the old aura to the new"
  `alloc_spec`: the sweep over a 40-slot layout with changes allocates nothing.
  (Until Task 3c, a silent slot counts as NONE unconditionally; 3c adds the seen gate.)
- [ ] **Step 2: expect failure. Step 3: Implement** `Q.Sweep(t)` (per viewer `IsVisible`, `GetNumChildren` growth ->
  collect; per slot rawgets; change-only O(1) counter moves; a touched list) and `Q.Counts(j, u)`.
- [ ] **Step 4:** specs; `make check`; first gate `IDENTICAL`.
- [ ] **Step 5: Commit** `feat(belief): CDM leaf reads every slot by a poll sweep (decisions 95-96, 100, 102)`.

### Task 3c [belief]: The CDM leaf, part 3: the target settle, the seen rule, the self-off

**Files:** `Presence/CooldownViewer.lua`, `tests/Game/State/viewer_spec.lua`, `alloc_spec.lua`.

- [ ] **Step 1: Failing tests** (counts read through `Q.Counts`; each "not live" test has its positive control):
  1. "target change: target and NONE slots settle for SETTLE as stale; settle end is a change at that poll" (L299
     renamed it: "... are stale in the switch's frame; the next frame's sweep is a change")
  2. "an error in the sweep turns the leaf off for the session with one def.error line"
  3. **seen** "sSeen[s] is written at every sweep the slot is held for u, not only on a change" (a refresh that keeps
     the item held moves `applied`; the next sweep's `sSeen >= applied`)
  4. **seen** "a silent item for an application it never held is not live (counts 0); control: the same item, lit this
     application, then silent, is live as NONE"
  5. **seen** "our new cast moves applied past sSeen: the silent item is not live until it lights again (I-B); control:
     once it lights, its later silence is live"
  6. **seen per slot** "two items for one aura, B never lit: B is never live (A held: UP, agree true; our refresh while A
     is held: no flip); A released mid-application: counts all zero (UNKNOWN, not DOWN); control: A stays and goes
     silent: live as NONE"
  7. **seen per slot** "re-point resets the slot: re-pointed to another aura and silent, it is not live for either;
     re-pointed back, not live until it lights again; re-pointed to another cooldownID that maps to the **same** aura
     (`sCd` changes, `sJ` does not), then silent: not live; control: it lights the new aura, then goes silent: live"
  8. **seen per slot** "a held slot with a secret or nil unit, or a plain unit that is neither player nor target
     (e.g. "focus"), then silent, is not live for either unit; control: held with plain unit u, then silent: live for
     u only"; and "a reset of a slot counted as NONE (target switch, cooldownID change) un-counts it first: no `nNone`
     is left with no live slot"
  9. **seen per slot** "an ambiguous slot, held then silent, is never live; control: an unambiguous slot, same sequence,
     is live"
  10. **seen per slot** "a rebuild resets every slot's sSeen; a target switch resets the target-held slots' sSeen (not
     live for the new target until lit); a record that closed (`U.exp0[u][j] <= t`) makes its silent slots not live
     at the next sweep"
  `alloc_spec`: the seen write, the resets and the gate allocate nothing.
- [ ] **Step 2: expect failure. Step 3: Implement** settling, `sSeen`/`sUnit`/`sCd` per spec §2.2a (every reset
  un-counts the slot first; preallocated slot arrays,
  owned by the leaf; the router never reads them), the gate in liveness reading `I.auras` (`U.applied`, `U.exp0`):
  every sweep re-checks the gate of every silent mapped slot (bounded by `MAX_SLOTS`; no hook, nothing added to
  `Families/Auras.lua`), and a changed gate result moves the counters like a reading change; the resets; the `pcall`
  self-off. Delete the immediate target re-read (`:161-168`).
- [ ] **Step 4:** specs; `make check`; first gate `IDENTICAL`.
- [ ] **Step 5: Commit** `feat(belief): CDM leaf target settle, the seen rule, self-off (decisions 103, 107, 115)`.

### Task 4a [belief]: The router hosts the reduced facts

**Files:** `src/Hekili/Game/State/Sources/Presence/Router.lua`; `Sources/Auras.lua` (poll 15 `:257-271` only);
`tests/Game/State/router_spec.lua`, `alloc_spec.lua`.

- [ ] **Step 1: Failing tests:** "the reduced state per (aura, unit) from the leaf's counts through I.ReduceFact";
  "the highest standing with nLive > 0 decides"; "onEdge fires on a reduced change only"; "disagree counts transitions
  to disagreement, not polls" (M8); "lost counts a thing that had a fact and went UNKNOWN while its record is up; control: a fact that goes UNKNOWN
  because its record closed (U.exp0 <= t) is not lost"; "fact.t is the last
  UNKNOWN/DOWN->UP time" (I3); "rebuild events in combat wait for combat end; evidence changes apply at once"
  (decision 99); "activated with zero items, an item collected later is counted and followed" (the sweep runs before
  poll 15's `covered == 0` guard, `Sources/Auras.lua:259`).
- [ ] **Step 2: expect failure. Step 3: Implement** spec §2.4: preallocated `fact.*`; `R.Sweep(t)` = leaf sweep, reduce
  the touched things, `R.onEdge` on change; `R.Presence`; `R.tracked` from `leaf.Mappable`; delete `mark`
  (`Router.lua:43-80`). Poll 15 calls `P.Sweep(t)` before its guard.
- [ ] **Step 4:** specs; `make check`; border; first gate `IDENTICAL`.
- [ ] **Step 5: Commit** `feat(belief): one reduced fact per aura and unit in the router (decisions 92-94)`.

### Task 4b [belief]: Reconciliation in apply, ours, the hold, the floor, the snapshot section

**Files:** `Sources/Auras.lua` (`apply` `:218-243`, walk `:76-152` for `sourceUnit` and the out-of-combat gate,
Snapshot `:281-306`); `Families/Now.lua:325` (one line: `I.auraOurs[k] = true` on our cast's write);
`tests/Game/State/auras_spec.lua`, `alloc_spec.lua`; one engine spec under `tests/Forever` for the flap test.

- [ ] **Step 1: Failing tests** (the review's red tests first):
  - **C1** "partner copy up (walk read, source party1), item NONE in combat: no DOWN"; "our cast opened it, item NONE:
    DOWN"; "a CDM UP opened it, then NONE: DOWN"; "walk read with source player sets ours, with a secret source clears it".
  - **C2** "target UP fact past its registered duration: remains HOLD, re-staged once per HOLD, not per poll"; "the item
    clears: the target record lapses within HOLD"; "a refreshed target aura (our cast) is never math.huge: t0 =
    max(fact.t, applied)"; "target aura with no numeric duration: HOLD, never math.huge"; "player aura with no numeric
    duration: -1, closed by an ours NONE".
  - **I7** "in combat, a walk with nil at index 1 does not suppress CDM facts" (`walkWins` = plain and out of combat).
  - **Seen rule** (decision 115). Each test that asserts "no close" carries a **positive control in the same test**
    (the same setup with the item lit this application, then the aura ends: DOWN closes the record), so it is red
    against an unbuilt `apply`:
    - "silent item (F12 flag) while our buff is up in combat, ours set: the record never goes down; the reduced fact
      reads UNKNOWN (`R.Presence`)"; control as above.
    - "never-lit item: UNKNOWN, the model closes the record at its expiry"; control as above.
    - **I-B** "our cast, the item lights at the next `ctl.Tick` (fake `lag = 1`): the record never goes down; then the aura
      ends: DOWN closes".
    - **I-B refresh** "our cast refreshes; the item stays held; the aura then ends: DOWN closes" (red for a change-only
      `sSeen` write).
    - "a buff re-applied after its item went silent (the item stops lighting): UNKNOWN, never closed by the item";
      control as above.
    - **per slot** "two items for one aura, one silent (F12 flag): release the working one mid-application in combat:
      no close, the reduced fact UNKNOWN"; control: "the same two items, the working one stays and the aura ends: DOWN
      closes".
    - **per slot** "re-point the working item mid-application: no close"; control as above.
    - **per slot** "the working item held with a secret or nil unit, then silent: no close"; control as above.
    - **replaced frame** (F13) "mid-application, the item's frame is released and a new frame table is acquired for the
      same cooldownID, not lit yet (`lag = 1`): no close while it is silent (new slot, `sSeen` 0); it lights: UP";
      control: "the new frame lit, then the aura ends: DOWN closes".
  - **C1 partner** keeps its control: "partner copy overwrites ours out of combat (walk read, source party1), item NONE in
    combat: no close; control: our own cast, item lit, then ends: DOWN closes".
  - **M5** "a form or enchant aura on the player is never written by apply".
  - "UP while believed up stages nothing"; "UNKNOWN leaves the record untouched".
  - **flap** (tests/Forever engine spec): an item appears, is released, reappears during one record: the belief never
    goes down and the recommendation does not change between polls. **re-map**: an override re-point mid-fight: the
    old aura UNKNOWN keeps its belief, the new one follows.
  - **floor**: "while the player fact is UP, I.auraFloor[j] is 1; otherwise 0" (written whether or not CN13 reads it).
  - **snapshot**: the CDM section of spec §6 (per-thing line, summary line with `leaf=on|off(error)|off(debug)`), each
    line under 255 chars.
- [ ] **Step 2: expect failure. Step 3: Implement** spec §2.5 rules 1-8, §2.6's display, §6's section, the floor write.
  `ours`, durations (`def.auras[j].duration` numbers cached at OnBuild) and `HOLD` preallocated / constants.
- [ ] **Step 4:** specs; `make check`; border; first gate `IDENTICAL`; `make gate` (tdf-runner).
- [ ] **Step 5: Commit** `feat(belief): reconcile reduced facts: ours, bounded hold, walk out of combat only (decisions 104, 111-114)`.

### Task 4c [belief], CONDITIONAL: the floor read, if CN13 merged without it

**Files:** `Families/Auras.lua` (`Obs.PlayerHit` `:240-252`), `tests/Game/State/auras_spec.lua`.
- [ ] Red test "a hit that would spend the last charge of a consumedBy aura with I.auraFloor[j] == 1 leaves one stack;
  with 0 it spends as before"; implement the three-line read; `make gate`; commit
  `fix(belief): honour the aura floor in consumption (decision 114)`.

### Task 5 [belief]: The combat-exit reconcile counted

**Files:** `Sources/Auras.lua` (`walk` `:128-145`, poll 10 `:180-190`); `tests/Game/State/auras_spec.lua`.

- [ ] **Step 1: Failing test:** "the first plain walk after combat counts a fix per aura whose believed presence it
  changed, none for an agreeing aura; reset at PLAYER_REGEN_DISABLED".
- [ ] **Step 2: expect failure. Step 3: Implement:** preallocated `exitFix[k]`; poll 10 marks "this is the exit walk";
  compare `U.exp0[u][j] > t` before with the walk's verdict. (Task 4b prints it.) **Step 4:** specs, `make check`,
  first gate `IDENTICAL`. **Step 5: Commit** `feat(belief): count the combat-exit walk's corrections (decision 105)`.

### Task 6 [options]: Always on; the setting removed (after Task 4b and CN8)

**Files:** `src/Hekili/Options/Options.lua` (`:312`, `:4212-4227`), `src/Hekili/Locales/*` (the two strings),
`src/Hekili/Engine/Schema/Tracked.lua` (`providersOf` `:216-226`), `tests/Forever/providers_option_spec.lua` (rewrite),
`tests/Game/harness/loop.lua:333`, `DEVELOPMENT.md`, `CHANGELOG.md`, `docs/dev/architecture.md:133-135`.

- [ ] **Owner direction 2026-11-08: the DAMAGE METER setting goes in this task too** (the same dev-only 'Experimental' block):
  delete `performance.damageMeter` (`Options.lua:311`, its entry `:4171-4186`, the two locale strings `enUS.lua:500-501` and
  `zhCN`), make `providersOf` (`Tracked.lua:220`) stop reading `p.damageMeter` (the Outcomes provider is always the
  default one; keep the meter provider code only if the A/B harness still uses it, say which in the report), tests: "no
  damage meter option exists in the options table" and "a saved performance.damageMeter = true is ignored without an
  error"; update `providers_option_spec`, `docs/dev/providers-ab.md`, DEVELOPMENT.md and CHANGELOG (no player-visible
  setting existed in release builds, so no Changed line unless something visible moves). Owner rule: no user-facing
  toggles for adaptive features, only the undocumented `Hekili.cdmOff` session switch.
- [ ] **Step 1: Failing tests:** "providersOf gives viewer true in a release build with any saved value"; "no Cooldown
  Manager option exists in the options table"; "a saved performance.cooldownViewer = false is ignored"; "Hekili.cdmOff =
  true then ProvidersChanged gives viewer false (out of combat at once, else at combat end)".
- [ ] **Forever-spec audit:** list every `tests/Forever` spec that boots the engine (`Forever.helpers.engine`.boot); each
  now gets the router with the leaf. Their fake viewers are empty (`covered` 0), but the `COOLDOWN_VIEWER_*` events stop
  being dormant (`Router.lua:106-114`) and poll 15 now sweeps: check every Snapshot / event-count assertion; record the
  list in the report.
- [ ] **Step 2: expect failure. Step 3: Implement:** `providersOf` returns `Hekili.cdmOff ~= true` for the viewer;
  delete the setting, its entry and its locale strings; `loop.lua:333` sets `Hekili.cdmOff = not arm.viewer` instead of
  the profile value (the default arm stays off: check `detect.lua:155` already passes `ab.providers()`); DEVELOPMENT.md
  documents `/run Hekili.cdmOff = true; Hekili:ProvidersChanged()`; CHANGELOG "The Cooldown Manager now corrects aura
  presence whenever it shows the aura (any of its bars); no setting". architecture.md: `cooldownViewer` no longer
  exists; three dev-only switches remain.
- [ ] **Step 4:** `make check`; first gate `IDENTICAL`; border unchanged. **Step 5: Commit**
  `feat(options): Cooldown Manager facts always on; the experimental setting removed (decision 107)`.

### Task 7 [options]: The coverage line

**Files:** Create `src/Hekili/Options/Coverage.lua` (or a local helper in `Options.lua`); Modify `Options.lua` (a
standalone `description` in the Performance tab, `name` a function), TOC, `tests/Forever/cdm_coverage_spec.lua`.

- [ ] **Step 1: Failing tests:** "N of M equals the belief's covered on the same fake layout" (the spec boots the
  engine with Task 2's fake layout; the belief's number read in the test from the snapshot's summary line, test-only);
  "uncovered names listed, at most five, then 'and N more'"; "in combat the line says it updates after combat";
  "Options code reads no belief" (`tools/check_border.sh` unchanged).
- [ ] **Step 2: expect failure. Step 3: Implement** spec §6: the client API as the rest of `Options/` reads it
  (globals; `Hekili.Client` lists the names, `Facade.lua:1141-1148`), the four viewers' `GetChildren`, rawget
  `cooldownID`, the §3.1 candidates, the active spec's `class.auras` IDs. **Step 4:** `make check`. **Step 5: Commit**
  `feat(options): Cooldown Manager coverage line (decision 108)`.

### Task 8 [harness]: Viewer layouts in the loops (after CN8 merges)

**Files:** `tests/Game/harness/drive.lua` (`@viewer` `:457-466`), `observer.lua` (`:580-581`), `scenarios.lua` (`:322`),
`ab.lua` (`:6-24`), `loop.lua` (`:368`), `tools/data/cooldownviewer/DRUID.lua` (new), `drive_spec.lua`,
`observer_spec.lua`, `Makefile` (`gate-ab` arms).

- [ ] **Step 1: Failing tests:** drive: "`@viewer` lights every item in any viewer naming the spell, cooldown entries
  included, our auras only"; "`@viewerLayout` acquires (also in combat), releases, re-points; `@viewerShown` hides a
  viewer or the parent"; scenarios: "presets none, buffs, fixture, mixed build the fake from the spec's auras / the
  class fixture"; ab: arms `viewer-none`, `viewer-buffs`, `viewer-fixture`, `viewer-mixed`; `default` unchanged.
- [ ] **Step 2: expect failure. Step 3: Implement.** `mixed`: each pack aura gets 0-3 items over the four viewers (from
  `W.mrng`), unconfigured slots, one viewer hidden for a random 10 s, one mid-fight re-point, one viewer whose pool
  grows in the first fight, at least one silent item (`item.silent`) beside a working item for the same aura, and
  `ctl.viewer.lag = 1` on one seed set (so the viewer arms exercise the seen rule). `fixture`: `tools/data/cooldownviewer/<CLASS>.lua` plus an Essential entry per ability whose
  aura the pack registers (F6). Classes without a fixture skip that arm (reported).
- [ ] **Step 4:** `make check`; `make gate` (default arm identical); `make gate-ab` runs the new arms.
- [ ] **Step 5: Commit** `test(harness): Cooldown Manager layouts in the loops; four viewer arms (decision 110)`.

### Task 9 [docs]: The A/B and the docs

**Files:** `docs/dev/providers-ab.md` (new section), `docs/dev/gaps.md` (rows 102-103), `docs/dev/ingame-ledger.md`
(CDM rows `:57-66`), the spec's status line, `CHANGELOG.md`.

- [ ] **Step 1: Run** (tdf-runner): `make gate-ab` on the gate's seeds plus four more seed sets; per spec and arm:
  flicker/min, readyShort, agreement, facts, disagreements, item disagreements, ambiguous, lost, exit fixes, overflow;
  the Shaman `consumedBy` flicker row (`buffs` layout) and a target-DoT-past-duration flicker row (`mixed`, records
  past `d`: the `HOLD` rule).
- [ ] **Step 2: Record** per arm with the default beside it, the difference and the noise band; header "Measured, not
  gated (decisions 86, 110). Acceptance: no flicker rise beyond ±0.3/min on any spec." Any spec over the band: stop and
  report; **the release waits**. Read item disagreements as lag (spec §2.3, M3); a silent item beside a working one
  is never live (per-slot seen rule), so it adds no disagreement; `lost` excludes normal aura ends (spec §2.4).
- [ ] **Step 3: Docs.** gaps row 103 for "any viewer" coverage (Druid fixture added); ledger: CDM-E closed by P0
  result 9; CDM-T/O/I/P and e4b/ACQ open with the `/fprobe cdm` commands. **Step 4:** `make check`. **Step 5: Commit**
  `docs(cdm): the viewer A/B per layout; ledger and gaps`.

### Task 10 (owner, in game): the checklist

Needs a dev build with Tasks 1-7. ForeverProbe branch `aurasec` beside it (`~/src/forever-probe-cdm-report.md`;
helpers are lost on `/reload`). Results through the copy box (`/vscopy`); the CDM state is read from the debug
snapshot's `presence` section.

- [ ] **CDM-T:** `/console taintLog 1`, ForeverProbe hooks OFF, a full pull with a DoT and a proc (Druid: Moonfire,
  Clearcasting); after `/reload` `Logs/taint.log` names neither Hekili nor a `CooldownViewer` or `DamageMeter` frame;
  the CDM keeps updating in combat. Not clean: the release is held; `Hekili.cdmOff` meanwhile.
- [ ] **e4b, Alt-Z, hidden bar:** `/fprobe cdm items` with Alt-Z in combat and with one bar hidden in Edit Mode: the
  viewers read not visible (plain); the debug snapshot shows `fact=unknown` (never down) meanwhile, the right facts
  after.
- [ ] **Dropped frame (F13):** removing the item of a buff that is up is answered for the active list (it reads as no
  item, and re-added it lights at once). Still to read: after a removal, is the dropped frame still a child of its
  viewer (`/fprobe cdm items` over `GetChildren()`: listed with `cooldownID` nil, or absent)? Why it matters: the
  in-combat collect (spec §3.2) fires only when `GetNumChildren` grows and walks the new indices only. If a dropped
  frame leaves the child list, a replacement can arrive with the count unchanged and is never collected: safe
  (UNKNOWN) but that item's coverage is lost for the rest of the fight. Fallback then: on any count change walk all
  indices and insert only frames not yet mapped (no allocation but the new inserts).
  Also read the dropped frame's own fields: the probe keeps a reference to the item's frame from before the removal
  and rawgets its `cooldownID`, `layoutIndex` and `auraInstanceID` afterwards (the leaf sweeps that frame by rawget
  whether or not it is still a child). Expected from source: `cooldownID` nil (BD:95). A plain configured
  `cooldownID` and `layoutIndex` after the removal contradicts BD:95 and **blocks the release under CDM-I**.
- [ ] **ACQ:** set one viewer to show "In Combat", log in, first fight: `/fprobe cdm hooks` counts `OnAcquireItemFrame`
  in combat; the debug snapshot shows its auras covered during that fight.
- [ ] **LAT:** the time from `OnAuraInstanceInfoSet` (probe) to the change in the snapshot (player: within one forced
  update; target changes we did not cause: up to 0.5 s).
- [ ] **CDM-I:** dungeon and boss: no `fact=down` for an aura that is up; secret fields not live.
- [ ] **CDM-P:** in a party, a partner's copy of a buff we track: our item stays dark and the record is not closed.
- [x] **CDM-O:** `/fprobe cdm target`, our debuff on mob A only, switch B then A: done 2026-11-08 (the event's frame
  only; the settle became the frame rule, L299). Still open: a second mob with the same debuff (D2T).
- [ ] **Shaman flag run (e1-e3):** `/fprobe aurasec` for every Lightning Shield and Water Shield rank, then
  `/fprobe aurawatch` in combat. Any 0: Task 11 go; else Task 11 dropped (ledger).
- [ ] **Coverage:** the options line on a Druid and a Warrior matches the bars.
- [ ] **Silent item (F12):** a Druid with Mark of the Wild up and its item in a bar: in combat the record stays up (no
  "rebuff"); the snapshot shows the aura `fact=unknown` while the item is silent. Run `/fprobe cdm sets` on the Mark of
  the Wild entry (spellID, override, linkedSpellIDs) so its cause is recorded once (D15).
- [ ] Results into `docs/dev/ingame-ledger.md` (controller); any `IsVisible` fallback in one commit (the settle is
  done: L299's frame rule).

### Task 11 [belief], CONDITIONAL: the direct never-secret provider

Only if Task 10's Shaman run finds a flag-0 pack aura. **Files:** `Presence/Direct.lua`, its spec; `Router.lua`
(standing 2); TOC; `tools/api_inventory.txt`.
- [ ] Red tests: "classifies pack aura IDs by GetSpellAuraSecrecy at build, out of combat"; "a flagged aura's plain
  table stages a full Read like the walk"; "nil is NONE for a flagged aura"; "a target UP needs a plain sourceUnit of
  player or pet"; "unflagged auras are never read"; "standing 2 beats the viewer". Then implement, gate, commit
  `feat(belief): direct reads for never-secret auras (decision 109)`.

## Candidate deferrals (for the controller's ledger)

Spec §13 (D1, D3-D6, D8, D9, D13 player aura with no numeric duration whose item is lost mid-fight, D14 the latency
window: one wrong close on a refresh whose new application the item does not light, D15 the silent item's cause), plus:
- P1: Task 8's `fixture` arm covers only Warrior and Druid. Trigger: each class's `/fprobe cdm sets` (CDM-C).
- P2: the release gate above. Trigger: Tasks 9 and 10 done.
- P3: Task 4c if CN13 merges without `I.auraFloor`. Trigger: CN13 merged.
