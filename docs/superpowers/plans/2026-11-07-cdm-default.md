# CDM Facts by Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Cooldown Manager (CDM) becomes a default-on, generic fact layer under the belief: every CDM item in any
viewer is evidence, a pure reducer turns it into one fact per tracked aura and unit, and the belief's aura records take
that fact by one rule set; with no fact the model runs alone.

**Architecture:** A pure reducer (`Game/State/Sources/Presence/Reduce.lua`) between the providers and the belief. The
CDM leaf (`Presence/CooldownViewer.lua`) keeps a complete cooldownID->aura map built out of combat and sweeps its item
slots by `rawget` at poll 15; it installs no hooks (a forced update never shortens the wait, perf 2.1a). The router
(`Presence/Router.lua`) holds the reduced records and picks the highest standing with evidence; `Sources/Auras.lua`
`apply` reconciles. The game layer flips the default and shows a coverage line computed in `Options/`.

**Tech Stack:** Lua 5.1 (WoW), busted, luacheck, StyLua, the combat harness (`tests/Game/harness/`).

**Spec:** `docs/superpowers/specs/2026-11-07-cdm-default-design.md` (binding; decisions 92-110), on top of the
providers spec (`docs/superpowers/specs/2026-10-23-providers-design.md`, decisions 65-91; 79 and 89 superseded). Cited
"spec §N". Line numbers are as of `integ/0.7` a0bd6f8dd.

**Prerequisites and central lanes in flight:**
- **CN8** (cooldown lane: `Families/Casts.lua`, `Families/State.lua`, `tests/Game/harness/world.lua`, `loop.lua`):
  Task 8 (harness loops) edits `loop.lua` (`:333`, `:368`) and may need `world.lua` (`W.mrng`, `:51`). **Run Task 8
  after CN8 merges into integ/0.7**; expect conflicts in `loop.lua`'s arm wiring if not. Tasks 1-7 do not touch CN8's
  files.
- **CN13** (generic consumption model: `Families/Auras.lua` `Obs.PlayerHit`, `Sources/Player.lua` hit staging):
  this plan never edits `Families/Auras.lua` (spec §7). Tasks 4 and 5 edit `Sources/Auras.lua`; CN13 should not. If
  CN13 does edit `Sources/Auras.lua`, merge it first and rebase Tasks 4-5. The A/B (Task 9) reads better after CN13
  (it measures CN13's error as disagreements) but does not need it.

## Global Constraints

- **Border.** Nothing under `src/Hekili/Game` names the core; the core reaches the belief only through Drain, Build,
  SetLog and the facade. This plan adds **no** crossing: the coverage line is computed in `Options/` from the client
  API and `class.auras`; `/hekili cdm` uses the existing debug bridge (`Hekili.Virtual`, `Hekili.lua:213-215`). Run
  `tools/check_border.sh` in every task that touches `src/`. Any new crossing: stop and ask the owner.
- **Class-neutral.** No class, spell, aura or spell ID under `src/Hekili/Game` or `tests/Game` (`tests/boundary_spec.lua`).
  IDs live in `tools/data/cooldownviewer/*.lua` and docs.
- **Secrets.** `auraInstanceID` only via `api.issecretvalue(x) or x ~= nil`; every other client value through `S.Plain`
  before use; never `a and b or c` on a raw value; nothing read passed back to an API. New API names
  (`C_Spell.GetOverrideSpell`, viewer `IsVisible`, and in Task 11 `C_Secrets.GetSpellAuraSecrecy`,
  `C_UnitAuras.GetUnitAuraBySpellID`) join `tools/api_inventory.txt` (`make api-check`).
- **No allocation in recurring paths.** The sweep, `I.ReduceFact`, the router's reduction and `apply` allocate nothing
  (`tests/Game/State/alloc_spec.lua` extended). Getters that allocate run out of combat only. The only in-combat
  inserts: none (frames are collected out of combat; slot arrays preallocated to `MAX_SLOTS = 128`).
- **Taint rule (spec §3.5).** rawget on items; on Blizzard frames only `GetChildren` (out of combat) and `IsVisible`;
  no hooks of any kind (`HookScript` removed); nothing written to Blizzard frames.
- **No jitter.** UNKNOWN never flips the belief; a viewer arm may not raise flicker beyond seed noise (±0.3/min) on any spec.
- **First gate.** The `default` A/B arm (viewer off) is identical to the digit before and after every task (providers
  plan "First gate", `docs/superpowers/plans/2026-10-23-providers.md:47-55`). Tasks 1-5 and 7 prove it.
- **Model sizing.** Tasks marked **[belief]** change `src/Hekili/Game`: Opus builds, Fable reviews. Tasks marked
  **[options/docs/harness]**: Sonnet builds, Opus reviews. Runs (`make gate`, `make gate-ab`) go through `tdf-runner`
  (haiku) with a report file.
- `make check` green on every commit; `make gate` on every [belief] task before its merge; `make gate`, `make gate-ab`,
  `make accuracy` take `/tmp/hekili-gate.lock` themselves (never wrap them); any other busted target runs under
  `flock /tmp/hekili-gate.lock`.
- **Deferrals.** Every real deferral a task makes (a review finding not fixed now and not in a named next commit, a
  ruling accepting a known gap, a postponed step, a pending owner in-game check) goes into the task's report as a
  "Deferral candidates" list (what, why, trigger); the controller writes the ledger the same turn.
- Every commit ends with the trailer given in the brief that dispatches the task.

## Module Layout

```
src/Hekili/Game/State/Sources/Presence/Reduce.lua          NEW   I.ReduceFact (pure), I.FACT constants
src/Hekili/Game/State/Sources/Presence/CooldownViewer.lua  REWRITE  map, slots, sweep, counts, no hooks
src/Hekili/Game/State/Sources/Presence/Router.lua          MODIFY  reduced records, standings, Sweep, onEdge on change
src/Hekili/Game/State/Sources/Presence/Default.lua         MODIFY  Sweep/Counts/Mappable no-ops
src/Hekili/Game/State/Sources/Presence/Direct.lua          NEW, CONDITIONAL (Task 11)
src/Hekili/Game/State/Sources/Auras.lua                    MODIFY  apply rule 2.5.3, Sweep call, exitFix, Snapshot lines
src/Hekili/Hekili.toc                                      MODIFY  Reduce.lua before CooldownViewer.lua (line 54)
src/Hekili/Engine/Schema/Tracked.lua                       MODIFY  providersOf: cooldownViewer read in every build
src/Hekili/Options/Options.lua (+ Locales)                 MODIFY  default true, visible group, coverage line
src/Hekili/Options/Coverage.lua                            NEW     the core-side coverage helper (or inside Options.lua)
src/Hekili/Options/ChatCommands.lua                        MODIFY  /hekili cdm
tests/Game/State/helpers/fake_api.lua                      MODIFY  the any-layout fake viewer
tests/Game/State/{reduce,viewer,router,auras,alloc}_spec.lua
tests/Game/harness/{drive,scenarios,ab,loop}.lua           MODIFY  (Task 8, after CN8)
tools/data/cooldownviewer/DRUID.lua                        NEW     from the 2026-11-07 probe (§2 and §8 of the probe file)
```

## Review Focus

1. **The reducer is pure and total.** Every row of spec §2.3 in the table test; no upvalue read.
2. **No layout assumption.** No item anywhere is UNKNOWN, never DOWN; unconfigured, hidden, unmapped, settling and
   secret-field slots are not evidence; roles never consulted.
3. **The sweep reads after the call stack.** No hooks; the sweep runs before poll 15's `covered` guard.
4. **Release and re-point.** A released slot (`cooldownID`/`layoutIndex` nil) leaves the evidence; a re-pointed one
   moves; neither stages DOWN.
5. **Reconciliation only in `Sources/Auras.lua`** (no `Families/Auras.lua` diff).
6. **Default arm identical**; the viewer arms measured.
7. **Border, secrets, allocation** as the Global Constraints.

## Task order and parallelism

| Wave | Tasks (parallel within a wave) | Needs |
|---|---|---|
| A | 1 Reducer [belief] · 2 Fake viewer [harness] · 5 Exit counter [belief] · 6a Options text and default plumbing behind a constant [options] | nothing |
| B | 3 CDM leaf [belief] | 1, 2 |
| C | 4 Router + reconciliation [belief] | 3, 5 (same file `Sources/Auras.lua`: 5 lands first) |
| D | 6b Default flip on · 7 Coverage line and `/hekili cdm` [options] | 4 (6b), 2 + 6a (7) |
| E | 8 Harness loops and layouts [harness] | 4, **CN8 merged** |
| F | 9 A/B and docs [docs] | 8 |
| G | 10 In-game checklist (owner) | a dev build with 1-7; sets `SETTLE`, confirms `IsVisible` |
| G' | 4b The CN13 floor: while the fact says UP, consumption keeps one stack [belief] | 4 and CN13 merged, unless CN13 builds it (owner question 4) |
| H | 11 Direct never-secret provider [belief], CONDITIONAL | 4, and the Shaman probe finding a flag-0 aura |

Release gate (the owner's acceptance list, all of it): no tag carries 6b until Task 9 shows no flicker rise on any
spec (Shaman `consumedBy` row included) and Task 10 passes CDM-T (taint), CDM-I (no wrong DOWN in a dungeon), CDM-O (no
target-switch mis-attribution), the hidden-viewer and Alt-Z rows, and the coverage rows; and `tools/check_border.sh` is
unchanged. One mechanism: 6b is merged into integ/0.7 (default ON for everyone in that branch, so the A/B and the
owner's dev build exercise it); the controller does not tag a release from a branch holding 6b until the gate passes,
and reverts 6b's one-line default if the gate fails.

---

### Task 1 [belief]: The fact reducer, table-driven test first

**Files:** Create `src/Hekili/Game/State/Sources/Presence/Reduce.lua`, `tests/Game/State/reduce_spec.lua`;
Modify `src/Hekili/Hekili.toc` (before `Presence\CooldownViewer.lua`, line 54).

- [ ] **Step 1: Failing test.** `tests/Game/State/reduce_spec.lua`, one row per spec §2.3 case plus edges:

```lua
local load = require("Game.State.helpers.load")
describe("I.ReduceFact (cdm-default spec §2.3)", function()
    local I
    before_each(function() I = load.module().VirtualStateInternal end)
    -- nLive, nUp, nNone, nStale, tUp, tNone -> state, agree
    local ROWS = {
        { "no item anywhere", 0, 0, 0, 0, 0, 0, "UNDECIDED", true },
        { "no item, only stale", 0, 0, 0, 2, 0, 0, "UNDECIDED", true },
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

- [ ] **Step 2: Run, expect failure** (`flock /tmp/hekili-gate.lock busted tests/Game/State/reduce_spec.lua`): `ReduceFact` nil.
- [ ] **Step 3: Implement** `I.ReduceFact` as spec §2.3 (no upvalues besides `I.UP`, `I.DOWN`, `I.UNDECIDED` cached at
  load). Header comment credits nobody (original); cites spec §2.3.
- [ ] **Step 4: Run** the spec: PASS; `make check`; first gate `IDENTICAL` (nothing calls it yet).
- [ ] **Step 5: Commit** `feat(belief): the pure fact reducer (cdm-default decision 94)`.

### Task 2 [harness]: The any-layout fake viewer

**Files:** Modify `tests/Game/State/helpers/fake_api.lua` (`:81-82`, `:666-712`); Create
`tests/Game/State/fake_viewer_spec.lua`. Keep `ctl.ViewerItem` and `ctl.ViewerShow` working for the existing
`viewer_spec`/`router_spec` until Task 3 rewrites them.

- [ ] **Step 1: Failing tests** in `fake_viewer_spec.lua` for each fake behaviour:
  - `ctl.ViewerItem(viewer, layoutIndex, id)` with `id == nil` makes an unconfigured slot;
  - each viewer has `IsVisible()` (false when `ctl.viewer.shown[name]` or `ctl.viewer.parentShown` is false; default
    true) and `GetChildren()`; `ctl.ViewerAcquire(viewer, id)` adds a new frame (pool growth in combat);
  - `HookScript` on items and a fake `api.hooksecurefunc` record their calls (Task 3 asserts none);
  - `ctl.ViewerAura(item, unit|nil)` follows the client order (BD:371-392): when held and changing, clear first
    (fields nil, then Cleared), then set (`auraInstanceID = SECRET`, `auraSpellID = SECRET` or plain per
    `ctl.viewer.plainSpell`, `auraDataUnit = unit`, then Set); clearing with nothing held fires nothing;
  - `ctl.ViewerRelease(item)`: `cooldownID = nil` first, then the aura clear (Cleared fires only if held), then
    `layoutIndex = nil`, hidden (BV:1645-1650, BD:96-98);
  - `ctl.ViewerRepoint(item, id)`: `cooldownID = id`, clear, refresh (BV:176-177);
  - `GetCooldownViewerCategorySet(c, allowUnlearned)`: `ctl.viewer.sets[c]` plus `ctl.viewer.unlearned[c]` when true;
  - infos may carry `overrideSpellID`, `overrideTooltipSpellID`, `linkedSpellIDs`, and a `linkedSpellID` that reads
    SECRET; `api.C_Spell.GetOverrideSpell(id)` from `ctl.overrides[id]` else `id`;
  - `ctl.ViewerAuraBySpell(unit, spellID, up)`: every configured item in any viewer whose info names the spell (any of
    the §3.1 IDs) gets `ViewerAura` (cooldown entries included, F6).
- [ ] **Step 2: Run, expect failure.** **Step 3: Implement** in the fake only. **Step 4:** `make check`; the existing
  viewer and router specs still pass. **Step 5: Commit** `test(harness): the any-layout Cooldown Manager fake`.

### Task 3 [belief]: The CDM leaf: complete map, slots, sweep, no hooks

**Files:** Rewrite `src/Hekili/Game/State/Sources/Presence/CooldownViewer.lua`; Modify
`src/Hekili/Game/State/Sources/Presence/Default.lua` (no-op `Sweep`, `Counts` returning zeros, `Mappable` false);
Rewrite `tests/Game/State/viewer_spec.lua`; Modify `tools/api_inventory.txt`, `tests/Game/State/alloc_spec.lua`.

- [ ] **Step 1: Failing tests** (`viewer_spec.lua`, against Task 2's fake; names are the assertions):
  1. "maps by spellID, overrideSpellID, overrideTooltipSpellID, linkedSpellIDs and GetOverrideSpell; never the singular linkedSpellID"
  2. "maps unlearned entries (allowUnlearned)"
  3. "an item naming two pack auras is ambiguous: NONE for both, UP for neither" (`ambiguous` counted)
  4. "a cooldown entry (Essential) holding an aura is UP evidence; a Buff icon entry for the same aura agrees" (F6)
  5. "no item in any viewer: counts all zero (UNKNOWN)"
  6. "an unconfigured slot, an unmapped id and a secret cooldownID are not evidence"
  7. "a viewer that is not visible (itself or its parent hidden) gives stale items, not evidence; visible again they count at the next sweep"
  8. "the refresh pair (clear then set in one call) is invisible to the sweep: no NONE ever counted"
  9. "a release with the aura held drops the slot (no NONE), a release with nothing held drops it too"
  10. "a re-point moves the slot's evidence from the old aura to the new"
  11. "a frame created in combat is not swept until the combat-end collect, and is counted in unseenFrames"
  12. "frames are collected at activation, at a rebuild and at PLAYER_REGEN_ENABLED, never in combat"
  13. "target change: target slots settle for SETTLE, counted stale; after it they count again"
  14. "a NEW pack aura added to the fake viewer with no code change is covered and followed" (owner acceptance, generic)
  15. "an error in the sweep turns the leaf off for the session with one def.error line"
  16. "no HookScript and no hooksecurefunc call is made" (the fake records both; zero)
  `alloc_spec`: the sweep over a 40-slot layout with edges allocates nothing.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement** spec §3.1-§3.5: `build` (out of combat; categories 0-8 with `true`; candidate IDs;
  `cdvToJ[id]` = j or -a; `amb[a]`), slots (`slotOf` weak-keyed frame->index; preallocated per-slot arrays `sJ`, `sV`,
  `sUp`, `sUnit`, `sLive`; per (u, j) counters `nLive`, `nUp`, `nNone`, `nStale`, `tUp`, `tNone`, `via`), `Q.Sweep(t)`
  (per viewer `IsVisible` once; per slot rawgets; change-only counter moves; a list of touched things for the router),
  `Q.Counts(j, u)`, `Q.Mappable(j)`, `PLAYER_TARGET_CHANGED` settling, the frame collect at activation, rebuild and
  `PLAYER_REGEN_ENABLED`, `unseenFrames`, the `pcall` self-off. Delete the `HookScript` path and the immediate target
  re-read (`:107-133`, `:161-168`). File header: credits TellMeWhen (Cybeloras) for the hidden-viewer rule, the
  all-viewers presence bit and the mapping (ideas only, GPL-3.0).
- [ ] **Step 4: Run** `viewer_spec`, `alloc_spec`; `make check`; `tools/check_border.sh`; first gate `IDENTICAL`
  (default arm has no leaf).
- [ ] **Step 5: Commit** `feat(belief): CDM leaf reads every item by a poll sweep; complete map; no hooks (decisions 95-103)`.

### Task 4 [belief]: The router hosts the reduced facts; reconciliation in apply

**Files:** Modify `src/Hekili/Game/State/Sources/Presence/Router.lua`, `src/Hekili/Game/State/Sources/Auras.lua`
(`apply` `:218-243`, poll 15 `:257-271`, Snapshot `:281-306`); Modify `tests/Game/State/router_spec.lua`,
`tests/Game/State/auras_spec.lua`, `tests/Game/State/alloc_spec.lua`.

- [ ] **Step 1: Failing tests:**
  - router: "the reduced state per (aura, unit) from the leaf's counts through I.ReduceFact"; "the highest standing
    with nLive > 0 decides (a plain walk over the viewer)"; "a self-scoped DOWN on the target stays no answer";
    "onEdge fires on a reduced state change only"; "a persisting disagreement is counted once per poll it persists,
    a same-frame lag never"; "lost counts a thing that had a fact and went UNKNOWN"; "rebuild events in combat wait for
    combat end; evidence changes apply at once" (decision 99).
  - auras: "UP with no model behind it: registered duration from the fact's time"; "... with no numeric duration: -1";
    "UP while believed up stages nothing (the model's expiry and stacks stand)"; "the model's expiry passing while the
    fact is UP is re-staged in the same drain (no gap)"; "DOWN closes"; "UNKNOWN leaves the record untouched".
  - **flap test**: an item appears, disappears, appears (release/acquire) during one record: the belief never goes
    down and the recommendation under `tests/Forever` (one small engine spec with the default fake spec) does not
    change between polls.
  - **re-map test**: an override re-points mid-fight (`ViewerRepoint`): the old aura goes UNKNOWN and keeps its belief;
    the new one follows its item.
  - "activated with zero items, an item collected later (combat end) is counted and followed" (the sweep runs before
    poll 15's `covered == 0` guard, `Sources/Auras.lua:259`).
  - Snapshot: the `presence <key> ...` line of spec §6 and the `presence covered=...` summary.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Router: preallocated `fact.*` arrays (spec §2.4) at build; `R.Sweep(t)` calls the leaf's
  `Sweep`, then reduces the touched things and calls `R.onEdge` on a change; `R.Presence` returns the reduced state;
  `R.tracked` now reads `leaf.Mappable(j)`; delete the router's own `mark` (`Router.lua:43-80`). `Sources/Auras.lua`:
  poll 15 calls `P.Sweep(t)` first, before its `covered == 0` return; `apply` gains rule 2.5.3 (duration from `def.auras[j].duration` when a number,
  cached at OnBuild into a preallocated array; `fact.t[k]` read through a router field, not a new crossing: both are
  `Game/`); Snapshot lines.
- [ ] **Step 4: Run** the specs; `make check`; `tools/check_border.sh`; first gate `IDENTICAL`; `make gate` (tdf-runner).
- [ ] **Step 5: Commit** `feat(belief): one reduced fact per aura and unit; reconciliation rules (decisions 92-94, 99, 104)`.

### Task 4b [belief], after CN13: the consumption floor while the fact is UP

Only if CN13 does not build it (spec §7, owner question 4). **Files:** `src/Hekili/Game/State/Families/Auras.lua`
(`Obs.PlayerHit` `:240-252`), `tests/Game/State/auras_spec.lua`.

- [ ] **Step 1: Failing test:** "a hit that would spend the last charge of a consumedBy aura whose reduced fact is UP
  leaves one stack; with the fact UNKNOWN or DOWN it spends as before".
- [ ] **Steps 2-5:** implement by reading the router's `fact.state` (both `Game/`, no crossing); `make gate`; commit
  `fix(belief): no one-update flash of a consumed aura the CDM still shows`.

### Task 5 [belief]: The combat-exit reconcile counted

**Files:** Modify `src/Hekili/Game/State/Sources/Auras.lua` (`walk` `:128-145`, poll 10 `:180-190`, Snapshot);
`tests/Game/State/auras_spec.lua`.

- [ ] **Step 1: Failing test:** "the first plain walk after combat counts a fix per aura whose believed presence it
  changed (up not found; found while believed down), none for an agreeing aura; reset at PLAYER_REGEN_DISABLED;
  Snapshot `presence exit <key> unit=... fixes=N`".
- [ ] **Step 2: Run, expect failure.** **Step 3: Implement:** a preallocated `exitFix[k]`; `walk` takes a flag "this is
  the exit walk" from poll 10 (`pending` true and out of combat) and compares `U.exp0[u][j] > t` before and the walk's
  verdict after. **Step 4:** specs, `make check`, first gate `IDENTICAL` (counts only). **Step 5: Commit**
  `feat(belief): count the combat-exit walk's corrections (decision 105)`.

### Task 6 [options]: Default ON, visible toggle, kill switch

Split in two commits so the default flips only after Task 4.

**Files:** `src/Hekili/Options/Options.lua` (`:312`, `:4212-4227`), `src/Hekili/Locales/*` (new strings, English
only), `src/Hekili/Engine/Schema/Tracked.lua` (`providersOf` `:216-226`), `tests/Forever/providers_option_spec.lua`,
`CHANGELOG.md`, `docs/dev/architecture.md:133-135`.

- [ ] **6a Step 1: Failing tests:** "the Cooldown Manager toggle is visible in a non-dev build"; "providersOf reads
  cooldownViewer in a non-dev build; the other three stay off there". **Step 2: expect failure.** **Step 3:** move the
  toggle to its own visible group (spec §6 text: needs, presence only, applies out of combat), `hidden` removed;
  `providersOf` reads `p.cooldownViewer == true` from the live settings in every build (others still dev-gated).
  Default stays `false` in this commit. **Step 4:** `make check`; first gate `IDENTICAL`. **Step 5: Commit**
  `feat(options): the Cooldown Manager facts toggle leaves Experimental`.
- [ ] **Forever-spec audit (6a, before 6b):** list every `tests/Forever` spec that boots the default profile
  (`require("Forever.helpers.engine").boot()`); with the default ON each gets the router with the leaf. Their fake
  viewers are empty, so `covered` is 0 and every answer UNDECIDED, but the `COOLDOWN_VIEWER_*` events stop being
  dormant (`Router.lua:106-114`): check every Snapshot/event-count assertion. Record the list in the task report.
- [ ] **6b (after Task 4):** `Options.lua:312` `cooldownViewer = true`; the harness `default` arm stays off explicitly
  (`tests/Game/harness/loop.lua:333` already writes `arm.viewer`; `detect.lua:155` sets `def.providers = ab.providers()`,
  so `viewer = false` in the default arm; check every other harness `def.providers` writer); fix the audited specs (set the profile value explicitly where a spec means
  "off"). Test: "a fresh profile and an existing profile with no saved value read cooldownViewer true; a profile switched off after the flip stays off" (AceDB never stored the old default `false`). `make check`; first gate
  `IDENTICAL`; CHANGELOG "The Cooldown Manager now corrects aura presence by default, for every profile (switch it off under Performance); not yet checked in game for
  classes without a fixture". Commit `feat(options): Cooldown Manager facts on by default (decision 107)`.

### Task 7 [options]: The coverage line and `/hekili cdm`

**Files:** Create `src/Hekili/Options/Coverage.lua` (or a local helper in `Options.lua`), Modify `Options.lua` (a
`description` under the toggle, `name` a function), `src/Hekili/Options/ChatCommands.lua` (`:80-96`), TOC,
`tests/Forever/cdm_coverage_spec.lua`.

- [ ] **Step 1: Failing tests:** "N of M: the count equals the belief's covered on the same fake layout" (the spec
  boots the engine, builds a fake layout with Task 2's fake, compares `Coverage()` with
  `Hekili.Virtual.State.Snapshot()`'s summary line, test-only read); "uncovered names listed, at most five, then
  'and N more'"; "out of combat only (in combat the line says 'updates after combat')"; "`/hekili cdm` prints the
  presence lines and the summary through the debug bridge into the copy box".
- [ ] **Step 2: expect failure. Step 3: Implement** spec §6: the helper reads `C_CooldownViewer` as the rest of
  `Options/` reads the client (globals; `Hekili.Client` is the facade and lists these names, `Facade.lua:1141-1148`, so
  either works; `IsVisible`/`GetChildren` are frame methods on the viewer globals), viewers' `GetChildren`, rawget `cooldownID`, the cooldown info's IDs,
  `C_Spell.GetOverrideSpell`, and the active spec's `class.auras` IDs. **Step 4:** `make check`;
  `tools/check_border.sh` (expected unchanged output). **Step 5: Commit** `feat(options): Cooldown Manager coverage
  line and /hekili cdm (decision 108)`.

### Task 8 [harness]: Viewer layouts in the loops (after CN8 merges)

**Files:** `tests/Game/harness/drive.lua` (`@viewer` `:457-466`), `observer.lua` (`:580-581`, a release/acquire knob),
`scenarios.lua` (`:322`), `ab.lua` (`:6-24`), `loop.lua` (`:333`, `:368`), `tools/data/cooldownviewer/DRUID.lua` (new,
from the probe file §2 and §8), `tests/Game/harness/drive_spec.lua`, `observer_spec.lua`, `Makefile` (`gate-ab` arms).

- [ ] **Step 1: Failing tests:** drive: "`@viewer` lights every item in any viewer naming the spell, cooldown entries
  included"; "`@viewerLayout` acquires, releases, re-points; `@viewerShown` hides a viewer"; scenarios: "layout presets
  none, buffs, fixture, mixed build the fake from the spec's auras / the class fixture"; ab: arms `viewer-none`,
  `viewer-buffs`, `viewer-fixture`, `viewer-mixed`, each `viewer = true` with its preset; `default` unchanged.
- [ ] **Step 2: expect failure. Step 3: Implement.** `mixed`: each pack aura gets 0-3 items over the four viewers
  (drawn from `W.mrng`), some unconfigured slots, one viewer hidden for a random 10 s, one mid-fight re-point.
  `fixture`: `tools/data/cooldownviewer/<CLASS>.lua` entries, plus an Essential entry for each ability whose aura the
  pack registers (F6). Classes without a fixture skip the arm (reported).
- [ ] **Step 4:** `make check`; `make gate` (the default arm identical); `make gate-ab` runs the new arms without error.
- [ ] **Step 5: Commit** `test(harness): Cooldown Manager layouts in the loops; four viewer arms (decision 110)`.

### Task 9 [docs]: The A/B and the docs

**Files:** `docs/dev/providers-ab.md` (new section), `docs/dev/gaps.md` (rows 102-103), `docs/dev/ingame-ledger.md`
(CDM rows `:57-66`), `docs/dev/architecture.md:133-135`, the spec's status line, `CHANGELOG.md`.

- [ ] **Step 1: Run** (tdf-runner): `make gate-ab` on the gate's seeds plus four more seed sets (seed noise rule); collect
  per spec and arm: flicker/min, readyShort, agreement, presence facts and disagreements, item disagreements, ambiguous,
  lost, exit fixes, unseenFrames (viewer arms vs default); and a Shaman `consumedBy` row (Lightning Shield flicker
  with the `buffs` layout): the one-update flash of spec §7, before and after Task 4b / CN13's floor.
- [ ] **Step 2: Record** a table per arm with the default beside it, the difference and the noise band. Header:
  "Measured, not gated (decision 86 / 110). Acceptance: no flicker rise beyond ±0.3/min on any spec." Any spec over the
  band: stop and report to the controller (the default flip waits).
- [ ] **Step 3: Docs.** gaps row 103 rewritten for "any viewer" coverage (Druid fixture added); ledger rows CDM-E
  closed by P0 result 9, CDM-T/O/I/P stay open with the `/fprobe cdm` commands; architecture note: `cooldownViewer`
  is no longer dev-only. **Step 4:** `make check`. **Step 5: Commit** `docs(cdm): the viewer A/B per layout; ledger and gaps`.

### Task 10 (owner, in game): the checklist

Needs a dev build with Tasks 1-7. Use ForeverProbe branch `aurasec` beside it (`~/src/forever-probe-cdm-report.md`;
helpers are lost on `/reload`, re-run them). Copy results through the ForeverProbe copy box (`/vscopy`).

- [ ] **CDM-T taint:** `/console taintLog 1`, Hekili's toggle on, ForeverProbe's hooks OFF, a full pull with a DoT and
  a proc (Druid: Moonfire, Clearcasting); after `/reload` `Logs/taint.log` names neither Hekili nor a `CooldownViewer`
  or `DamageMeter` frame; the CDM keeps updating in combat. Not clean: the default goes back off; report.
- [ ] **IsVisible and Alt-Z (e4b):** `/fprobe cdm items` with Alt-Z pressed in combat: the viewers' visible state reads
  plain false; `/hekili cdm` shows `fact=unknown` (never down) while hidden, the right facts after.
- [ ] **New frames in combat (ACQ):** `/fprobe cdm hooks` counts `OnAcquireItemFrame` calls in combat; > 0 with a
  steady layout raises deferral D7.
- [ ] **Latency (LAT):** from the hooks run, the time from `OnAuraInstanceInfoSet` to the `presence` change in
  `/hekili cdm` (expected: within one update).
- [ ] **Dungeon (CDM-I):** `/fprobe cdm items` and `/hekili cdm` in a dungeon and on a boss: no `fact=down` for an aura
  that is up; secret fields counted, not evidence.
- [ ] **Partner buffs (CDM-P):** in a party, a partner's copy of a buff we track: does our item drop while the buff is up?
- [ ] **Target switch (CDM-O):** `/fprobe cdm target` with our debuff on mob A only, switch B then A: the settle time
  that `SETTLE` should take; a second mob with the same debuff (D2T).
- [ ] **Hidden viewer:** hide one bar in Edit Mode (or turn the CDM off): its auras read `fact=unknown`, never down.
- [ ] **Shaman flag run (e1-e3):** `/fprobe aurasec` for every Lightning Shield and Water Shield rank, then
  `/fprobe aurawatch` in combat. Any 0: Task 11 is go; else Task 11 is dropped (ledger).
- [ ] **Coverage:** the options line on a Druid and a Warrior matches the bars.
- [ ] Results into `docs/dev/ingame-ledger.md` rows (controller), `SETTLE` (and any `IsVisible` fallback) in one commit.

### Task 11 [belief], CONDITIONAL: the direct never-secret provider

Only if Task 10's Shaman run finds a flag-0 pack aura. **Files:** Create `Presence/Direct.lua`, its spec; Modify
`Router.lua` (standing 2), TOC, `tools/api_inventory.txt`.

- [ ] **Step 1: Failing tests:** "classifies pack aura IDs by GetSpellAuraSecrecy at build, out of combat"; "a flagged
  aura's plain table stages a full Read (remaining, stacks) like the walk"; "nil is NONE for a flagged aura"; "a target
  UP needs a plain sourceUnit of player or pet"; "unflagged auras are never read"; "standing 2 beats the viewer".
- [ ] **Steps 2-5** as Task 4 (gate, border, commit `feat(belief): direct reads for never-secret auras (decision 109)`).

## Candidate deferrals (for the controller's ledger)

Spec §13 D1-D6, plus:
- P1: Task 8's `fixture` arm covers only classes with a fixture (Warrior, Druid); the other classes run `buffs` and
  `mixed` only. Trigger: each class's `/fprobe cdm sets` (CDM-C).
- P2: 6b's release gate (the whole acceptance list above). Trigger: Tasks 9 and 10 done.
- P3: Task 4b (the consumption floor) if CN13 does not build it. Trigger: CN13 merged.
