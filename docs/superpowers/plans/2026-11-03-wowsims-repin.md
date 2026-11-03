# Full wowsims Re-pin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every one of the 26 recipes reads its APL, build and gear at wowsims/forever e2842f0a78 (`M.PIN == M.SIM_PIN`),
the translator handles every new kind the client lets us show, and the specs whose rotations move get a generic
Movement toggle, with accuracy held close and every moved floor traced.

**Architecture:** Tools first (pins, the SIML step, recipe paths), then the translator's new kinds, then the Movement
toggle (core UI, one translator rewrite, the Hunter kit's ranged clock, the harness hook), then one lane per class
that re-exports, regenerates, gates and re-floors its specs, and last the oracle patches and the docs. Nothing in the
engine or the belief changes for movement.

**Tech Stack:** Lua 5.1 (the WoW client's), busted, luacheck, StyLua, the combat harness (`tests/Game/harness/`), the
wowsims/forever Go CLI built at the pin (`tools/wowsims/sim-pin/build.sh`), `wowdb` (the Forever DB2) for IDs and ranges.

**Spec:** `docs/superpowers/specs/2026-11-03-wowsims-repin-design.md` (binding, decisions 1-8). Cited as "spec §N" and
"decision N". The research it rests on: the audit's `followups/repin-research.md` (cited as "the research"). The owner
ledger is the open-questions file, from "2026-11-03 — full wowsims re-pin started".

## Global Constraints

From the spec (verbatim):
- The core stays class-neutral. The Movement toggle is a generic setting that packs opt into.
- The belief/core border holds: this design needs no new crossing.
- Secrets are guarded with `issecretvalue`.
- Recurring paths do no allocation.
- The addon is display only.
- Accuracy must stay close. Floors move only with a named, traced cause. No jittery recommendations: flicker is an
  acceptance metric.
- Fresh-floor rule (owner "yes"): a fresh floor (Retribution, Feral, Guardian, the Hunters) ships only if every
  remaining top disagreement is classified unfixable: API-forced, or a gap already in `docs/dev/gaps.md`. Any
  fixable cause (kit, world, translator, engine) blocks the merge until it is fixed.
- Movement terms (owner "ok"): every movement term is dropped from translated conditions: run speed
  (`unitMovementSpeed`), "is moving" (`unitIsMoving`, any unit) and arithmetic on yards (`unitDistance` inside
  `math`, `min`/`max`, or compared with anything but a whole-number constant). The rest of the condition decides.
  Hekili holds only the Movement toggle, the client's range gate (rule 11's bracket, `spellInRange`) and the
  rotation's timing terms.
- The replay gates score with Movement ON for every spec whose APL moves. OFF is covered by the per-spec toggle tests
  only. The loops run with Movement OFF.

Project rules:
- Gate lock: `make gate`, `make gate-ab`, `make accuracy` and the rig's `run.sh` take `/tmp/hekili-gate.lock`
  themselves; never wrap them. Every other busted run or test target (`make check`, `make test-<tag>`, a single
  `.lua/bin/busted <file>`) runs under `flock /tmp/hekili-gate.lock ...`.
- Belief/core border (`src/Hekili/Game/` vs `src/Hekili/Engine/`): the belief never touches Hekili state; Hekili
  reads it only through facades; `tools/check_border.sh` enforces the names. No new crossing without the owner's
  explicit yes: if a task seems to need one (a new belief function or facade read), stop and report it.
- Secrets: never compare or compute on a possibly secret value without `issecretvalue()`; never `a and b or c` on one.
- No allocation in recurring paths (per update, per event, per poll): no tables, closures or strings built there.
- Core is class-neutral: nothing under `src/Hekili/` names a class, spec, spell, aura, talent or form
  (`tests/boundary_spec.lua`). Class specifics live in the class kit or the recipe.
- Display only: no automation.
- Lua 5.1. The WoW client raises on `x/0` and `x%0` (stock Lua returns inf/nan): guard every divisor.
- Floors are measured, then set: the measured `decisions on-GCD` truncated to two decimals, never a pre-guessed
  number. A pack within max(0.02, 2/n) of its Phase 0 baseline is re-floored naming "re-pin e2842f0a78"; beyond it,
  the top three disagreements are traced (kit, world, central, API-forced: `docs/dev/wowsims-packs.md` P7) and the
  cause written beside the number. Flicker ceilings and LIVE60 follow the same rule.
- A central cause (translator, engine, belief) found in a lane is a `docs/dev/gaps.md` entry and is fixed centrally,
  never worked around in a lane: the lane stops and reports it.
- `flock /tmp/hekili-gate.lock make check` green on every commit; `make gate` at the end of every task that moves a
  pack. Text a player sees is `L["..."]`, then `python3 tools/locales.py`. A player-visible change adds a CHANGELOG
  "Unreleased" line in the same commit.
- Credit wowsims/forever (MIT) for data taken from it, as the recipes and the translator header already do.
- Git from WSL only. Never push, never force-push. Every commit ends with exactly:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01G2hWWPbEDL8y2U5eTPeBi9`

## Review Focus

1. The unknown range bracket (just after a target swap, before poll 14 answers; or a secret range answer in
   combat): a move-gated line must still show with Movement OFF (rule 11: unknown never blocks). Pinned in Task 7.
2. A saved profile from before the re-pin (no `toggles.movement`): it loads with Movement ON, and `toggle.movement`
   reads true. Pinned in Task 6.
3. Switching from an opted-in spec to one that is not: the options row and the menu entry hide, the saved value
   stays, nothing else reads it. Pinned in Task 6.
4. A move-reached entry whose own condition fails while its move condition holds: it stays hidden with Movement ON
   (ON relaxes only the range gate). Pinned in Task 7.
5. A ranged swing speed of 0 (no ranged weapon, or no read yet): `ranged_remains` answers 0 without dividing by zero.
   Pinned in Task 8.

---

## Settled here (the spec left these to the plan)

### S1. The Movement toggle's core UI (spec §2.1)

One profile toggle, `toggles.movement = { key = "", value = true }`, beside Potions in the profile defaults
(`src/Hekili/Options/Options.lua`). Everything else reuses the toggle plumbing every other toggle already goes
through:
- Simulation: `toggle.movement` through `mt_toggle` (`Engine/Sim/State.lua`), unchanged.
- Opt-in: a spec sets `movement = true` in the table it passes to `RegisterOptions` (class data, no spec name in the
  core). `Registry.MovementSpec(specID) -> boolean` (`src/Hekili/Engine/Registry.lua`) answers it. A packs test
  checks that a spec opts in exactly when its pack reads `toggle.movement`.
- Options: an inline group `movement` in the Toggles section after `potions` (keybinding `key`, checkbox `value`),
  hidden unless `Registry.MovementSpec(Hekili.State.spec.id)`.
- Minimap menu (`src/Hekili/UI/UI.lua`): a Movement entry after Potions, listed only for an opted-in spec.
- Chat: `/hek set movement [on|off]` already works through the generic `profile.toggles` branch
  (`Options/ChatCommands.lua`). Name it in the help text. Add no `move` alias: `/hek move` is already a command
  (`HandleMoveCommand`).
- Keybind: the existing `key` field. `SetOverrideBinds` already binds every toggle with a key. It is unbound by default.
- Notifications, Snapshot dump, WeakAuras `HEKILI_TOGGLE`: free through `FireToggle` (add `movement` to its name table).

Strings: `L["Movement"]`, `L["Enable Movement"]`, `L["Set a key to toggle Movement on or off."]`, and the checkbox
description `L["If checked, an ability your priority moves to reach is shown out of range while you would be moving to it. If unchecked, it is hidden until you are in range."]`.

### S2. Range in the replay at wowsims's logged distances (spec §2.2, §7)

The replay uses the real client path, with no shortcut:
- Position: the request's `distanceFromTarget` at 0 s, then each Movement stack (`replay.lua` `M.MOVE = 20`; whole
  yards, truncated by wowsims, at least 1). The `0` at a move's end is ignored, so the last stack holds (5 at melee).
  Pre-pull moves are in the log and are replayed the same way.
- Answers: `W.moveTo` emits `@distance`, and the fake client's `C_Spell.IsSpellInRange` (`tests/Game/State/helpers/fake_api.lua`)
  answers each spell from the character's `ranges` at that distance. Both reads use it: the sim's `action.<key>.in_range`
  (asked per query through the facade; a secret or nil answer reads as in range), and the belief's poll-14 bracket
  behind `target.within<N>`/`outside<N>`.
- Requirement: every opted-in class's world character lists DB2 ranges for every kit ability (SpellMisc.RangeIndex
  -> SpellRange, from `wowdb`), as `tests/Forever/helpers/hunter_world.lua`'s `RANGE` already does. An unlisted
  spell answers melee (0-5), which would put Judgement (10 yd) and Exorcism (30 yd) out of range at 8 yd. The
  Paladin, Druid and Warlock lanes add them (Tasks 17, 18, 16).
- Truncation: a logged 10 may be 10.9, so our 10-yd check can pass up to one stack early (at most about 0.15 s at
  wowsims's speed). A P7 "world: replay limit", named, not fixed.
- Unknown bracket: before poll 14's first plain answer after the target appears, `within` and `outside` both answer
  true (rule 11, kept). The replay's target appears at the 0.1 s pre-pull event, so the pull's first decision already
  has a bracket. Task 9 pins this.

### S3. Retribution's "Move to melee" (spec §2.3, rule 14)

At e2842f0a78 the main list's first entry calls the group "Move to melee" when `not spellInRange(Crusader Strike)`.
The group holds three `sequence`s (`move1`-`move3`; talent- and variable-selected), each:
`move` to 5 yd -> `waitUntil spellInRange(Judgement)` -> cast Judgement -> `wait inputDelay` -> cast a seal ->
`waitUntil spellInRange(Crusader Strike)`, guarded by `not sequenceIsComplete(<own name>)`.

Translation: a group of chains, written by **rule 14's mechanism** (a `sequence` is not a `strictSequence`, so this
extends rule 14 as rule 14b):
- The group stays a called list (`actions.move_to_melee`), called under `!action.crusader_strike.in_range`.
- Each `sequence` is a rule 14 chain over its **cast members only**: the first cast (Judgement) under the sequence's
  condition, each later cast (the seal) behind `prev.1.<the previous cast>`. `move` and `wait` members are omitted
  (§2.2, §3; `inputDelay` is already `0`).
- A `waitUntil` before a cast is that cast's range gate (§2.2): Judgement's line ends
  `&(toggle.movement&<move condition>|action.judgement.in_range)`, where the move condition is the call's condition
  and the sequence's own (`!action.crusader_strike.in_range&<sequence condition>`).
- The trailing `waitUntil spellInRange(Crusader Strike)` holds the rotation, so its gate,
  `(toggle.movement&<move condition>|action.crusader_strike.in_range)`, is carried onto every later line of the list
  that calls the group: the main list's lines after the call. This is the same rule as Feral's and Guardian's main-list
  "Finish closing to melee" `waitUntil`, which holds every later line of its own list.
- The sequence's own `not sequenceIsComplete(<own name>)` is dropped: the stateless chain replaces it (the APL
  stateless-guards rule). Deviation, written in the header: the chain arms again if the target leaves Crusader Strike's
  range later in the fight (wowsims runs each sequence once). The replay's boss never moves, so no scored decision
  changes. Any other `sequenceIsComplete` read stays unsupported (rule 2).
- A `sequence` with any other member kind stays rule 2.

### S4. Smaller rulings (the spec's "left to the builder")

- Pin names (§5): keep `M.PIN` and `M.SIM_PIN`, equal from Task 1 on, asserted equal in `wowsims_pin_spec.lua`.
  `M.OLD_SIM` becomes `{ [spec] = "<old pin>" }` for the three hunters until the Hunter lane re-exports and deletes it.
- `export` runs the oracle CLI `$WOWSIMS/wowsimcli-sim-pin` (the patched build `rerun` already uses), so every
  re-exported log is made by the same oracle as today's.
- A `not` over a rule 11 comparison is written as the opposite bracket (`not(d>5)` -> `target.within5`), never
  `!target.outside5`, so an unknown bracket still passes. That is the form a carried OFF gate needs.
- `spellIsCasting(X)`: `action.<key>.executing` for an ability with a cast time, constant false for an instant
  (wowsims never counts an instant as casting). `spellInRange(X)`: `action.<key>.in_range`.
- Hunter `unitDistance OpNe max(...)` (default #16): arithmetic on yards, so it is a dropped movement term
  (decision 8). This replaces the spec table's earlier "omit".
- Waits (§3): Task 9 translates `wait` behind a translator context flag, used only for its measurement. If kept,
  the flag becomes the default. If not, the flag and its code are deleted.
- The CHANGELOG line for the Movement toggle goes in Task 6 (DEVELOPMENT.md §7: in the same commit), not in Phase 9.

## Task order

| Phase | Tasks | Gate at the phase's end |
| --- | --- | --- |
| 0 Baseline | 0 | the baseline report committed |
| 1 Plumbing | 1, 2 | `make check`; one spec exports; the dry-run omit counts match the research |
| 2 Translator kinds | 3, 4, 5 | `make check`; the omit counts fall on the low-change specs (dry run) |
| 3 Movement | 6, 7, 8, 9 | `make gate`; the toggle tests; the hunter packs at the old pin replayed ON; waits decided |
| 4 Low-change | 10, 11, 12 | `make gate` per task |
| 5 Rogue, Warrior | 13, 14 | `make gate` per task |
| 6 Enh, Warlock, Ret | 15, 16, 17 | `make gate` per task |
| 7 Feral, Guardian | 18 | `make gate` |
| 8 Hunters | 19 | `make gate` |
| 9 Oracle, docs | 20, 21 | `make gate`; `packs-check`; every request re-exported |

Phases 0-3 run in order. In Tasks 3-8, a checked-in pack whose text changes is regenerated and committed in the
same task (`packs-check`), and a replay line that moves follows R5/R6 naming that task as its cause. Expected: only
the hunter packs change, because their old-pin weave carries moves, waits and walk terms. Task 9 is their full measurement. Tasks 10-19 need only Phases 1-3 on the branch and may run in parallel lanes (one
worktree each, merged back in phase order). The gate lock serialises their gates. Phase 9 runs after every lane.

## The per-spec procedure (R1-R9), used by every lane task

Each lane task names its specs and the spec-specific items. For each spec, in this order:

- **R1 Export.** With the wowsims checkout at e2842f0a78 and the oracle CLI built (Task 1),
  `make wowsims-export SPEC=<spec>`. This rewrites `tests/Forever/wowsims/<spec>.json` and `.log`.
- **R2 Regenerate.** `make wowsims-packs && make packs`. Read the pack's `# Omitted:` block. Each omission must be a
  kind this plan or the spec lists as omitted. Every other omission is an ID the kit lacks: add the rank ID to the
  kit ability's `copy` (or the recipe's `map`), checked with `wowdb`, then repeat R2. `tools/wowsims/dry.lua <spec>`
  (Task 2) prints the count. Record the before and after counts in the recipe header.
- **R3 Request fields.** Confirm in the request what spec §5 says moves with the build: race (and its racial and
  autocast lines), greater blessings `1` applied at the top rank in the log, talents re-encoded by spell ID against the
  e2842f0a78 trees, and no `executeProportion25/45/90`.
- **R4 Replay, floor at 0.** Set the spec's replay floor to 0 in `tests/Forever/wowsims_<class>_spec.lua`, then run
  `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/wowsims_<class>_spec.lua`. Read the `wowsims:` line:
  `decisions on-GCD X (n) top [...]` and `flicker`.
- **R5 Classify.** Within max(0.02, 2/n) of the Phase 0 baseline: go to R6. Beyond it: work the top three
  disagreements (P7: wowsims -> ours, log time, class) into the recipe header's "Disagreements (P7; floor F)" block.
  A kit cause is fixed in this task, test first. A world cause is a harness fix in this task, or a named replay limit.
  A central cause stops the task (Global Constraints). Re-run R4 after each fix.
- **R6 Floor.** Set the floor to the final measured value truncated to two decimals, with the history comment beside
  it: old floor, the new measurement, "re-pin e2842f0a78", and any traced cause. The same goes for the flicker ceiling.
- **R7 Levels and loops.** `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/wowsims_levels_spec.lua` for
  the spec's brackets and LIVE60, and `flock /tmp/hekili-gate.lock make test-<tag>` for its 20-fight loops (the tag
  from the Makefile's `GATE_TAGS`; Warrior's is `loop`). A moved line follows R5/R6. A lower bracket over the limit
  gets a recipe `leveling` filler (the existing rule), never a higher limit.
- **R8 Movement (opted-in specs only: Retribution, Feral, Guardian, Demonology x2, Hunters x3).** Set
  `movement = true` in the spec's `RegisterOptions`. Give the world character DB2 `ranges` (S2). Add one OFF test
  per spec in the class's spec file (`tests/Forever/<class>_spec.lua`): with Movement OFF, a move-reached entry is
  not recommended at a distance outside its range and is recommended inside it; with ON, it is recommended outside
  its range when the entry's own condition and the move's condition hold. The replay line is the ON measurement:
  its flicker gets a ceiling (R6).
- **R9 Commit.** `flock /tmp/hekili-gate.lock make check`, then `make gate`. Commit the recipe, request, log,
  regenerated pack, kit and test changes together:
  `test(wowsims): re-pin <spec> to e2842f0a78 (<old> -> <new>, <cause>)`.

A fresh floor (R5 for Retribution, Feral, Guardian and the Hunters) takes "re-pin e2842f0a78" as its named cause.
Its top three are classified first, and it ships only when every remaining top disagreement is unfixable
(the fresh-floor rule).

---

### Task 0: Baseline accuracy (Phase 0)

**Files:**
- Create: `docs/superpowers/plans/2026-11-03-wowsims-repin-baseline.md` (the report, copied)

**Interfaces:**
- Produces: the per-spec baseline every later floor decision compares with (decisions on-GCD, n, flicker, LIVE60 per pack).

- [ ] **Step 1: Confirm the tree is the base.** Run `make bootstrap` once if the worktree has no `.lua/`. Then run `git diff --stat 0d98cb02c HEAD -- src tests tools Makefile`.
  Expected: no output (this branch has only docs so far).
- [ ] **Step 2: Run** `make accuracy` (it takes the gate lock itself; do not wrap it). Expected: `.accuracy/report.md`
  and `.accuracy/report.json` written.
- [ ] **Step 3: Copy** `.accuracy/report.md` to the baseline file under a two-line header: the commit, 0d98cb02c, and
  the date. Also add each wowsims spec file's current `wowsims:` gate line (the floors in
  `tests/Forever/wowsims_*_spec.lua`) as a table.
- [ ] **Step 4: Commit** `docs(plan): re-pin baseline accuracy on forever 0d98cb02c`.

### Task 1: Pins, the oracle CLI and the SIML step (Phase 1)

**Files:**
- Modify: `tools/wowsims/export.lua` (`M.PIN`, `M.OLD_SIM`, `M.ENCOUNTER`, `M.OUT`, the CLI default, a `siml` step)
- Modify: `tests/Forever/wowsims_pin_spec.lua`
- Modify: `Makefile` (`wowsims-siml` target)

**Interfaces:**
- Produces: `M.PIN == M.SIM_PIN == "e2842f0a784d2f329dde0bc682a6b84202a780f2"`;
  `M.OLD_SIM = { hunter_beast_mastery = "d33930d04030c3f556582f31949f1f22c17da0e4", hunter_marksmanship = ..., hunter_survival = ... }`
  (the pin each of those logs was made at); `M.OUT = os.getenv("WOWSIMS_OUT") or "tests/Forever/wowsims/"`;
  the recipe key `siml = "<checkout path of a .siml build>"`, which `export` converts first;
  `export.lua siml <spec>` writes `tests/Forever/wowsims/<spec>.build.json`, and `request()` uses that file as the
  recipe's `build` whenever the recipe has `siml`.

- [ ] **Step 1: Verify the CLI has `siml`.** Check out the wowsims checkout (or a clean worktree of it) at e2842f0a78,
  run `make wowsims-sim-cli WOWSIMS=<that checkout>`, then
  `<checkout>/wowsimcli-sim-pin siml parse -json <checkout>/ui/specs/hunter/dps/builds/sv_weave.siml | head -c 300`.
  Expected: protojson starting with `{` that contains `"rotation"`. If the subcommand is missing, stop and report:
  the plan assumes it.
- [ ] **Step 2: Write the failing tests** in `wowsims_pin_spec.lua`:
  `assert.are.equal(ex.SIM_PIN, ex.PIN)`; the log-header check reads `ex.OLD_SIM[spec] or ex.SIM_PIN`;
  `assert.is_nil(ex.ENCOUNTER.executeProportion25)` (also for 45 and 90), and
  `assert.are.equal(0.2, ex.ENCOUNTER.executeProportion20)` (also 0.35 for 35);
  and a test that `ex.request` given a recipe with `siml = "x"` reads `build` from `ex.OUT .. spec .. ".build.json"`
  (written to a temp `WOWSIMS_OUT`).
- [ ] **Step 3: Run** `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/wowsims_pin_spec.lua`. Expected: FAIL on the pin equality.
- [ ] **Step 4: Implement** the pins, `M.OLD_SIM`'s new shape, the encounter fields removed, `M.OUT` from the
  environment, `WOWSIMS_CLI` defaulting to `$WOWSIMS/wowsimcli-sim-pin`, and `siml <spec>`, which runs
  `$WOWSIMS_CLI siml parse -json <checkout>/<recipe.siml>` and writes the JSON. `export <spec>` runs the `siml` step
  first when the recipe has `siml`. Add a `wowsims-siml` Makefile target beside `wowsims-export`. Update the header
  comments: the two pins are now equal, and why `OLD_SIM` lasts until Task 19.
- [ ] **Step 5: Run** the pin spec. Expected: PASS. Then run `flock /tmp/hekili-gate.lock make check`. Expected: green
  (no pack changes: the requests are unchanged).
- [ ] **Step 6: Commit** `feat(wowsims): pin requests to e2842f0a78, oracle CLI for export, SIML build step`.

### Task 2: Recipe paths and the dry run (Phase 1)

**Files:**
- Create: `tools/wowsims/dry.lua`
- Modify: `tools/wowsims/specs/druid_feral.lua`, `druid_guardian.lua`, `paladin_retribution.lua`,
  `shaman_enhancement.lua`, `hunter_beast_mastery.lua`, `hunter_marksmanship.lua`, `hunter_survival.lua`
- Modify: `docs/dev/wowsims-packs.md` (the recipe section: the `siml` key; it is an export path key, not one of the six additions)

**Interfaces:**
- Consumes: Task 1's `siml` step.
- Produces: `.lua/bin/lua tools/wowsims/dry.lua <spec>...` prints one line per spec,
  `<spec> omitted <N> lines <M>`, from `export.request` plus `apl.translate` against the checkout. It writes nothing.
  Every lane uses it in R2.

- [ ] **Step 1: Retarget the recipes** (spec §5). Feral and Guardian move to `apls/adaptive.apl.json`. Retribution
  moves to `apls/default.apl.json` and its new gear set. Enhancement drops `apl`, because the build carries the
  rotation. The hunters get `siml = ".../builds/{bm,mm,sv}_weave.siml"`; BM gets `petType` Raptor; `petAggression`
  and `cobraReflexes` are removed. Paths and line numbers go in each recipe header.
- [ ] **Step 2: Write `dry.lua`.** It loads `export.lua` and `apl.lua` the way `export.lua pack` does, builds the
  request from the checkout instead of the checked-in JSON, translates it, and counts the `# Omitted:` entries.
- [ ] **Step 3: Run** `make wowsims-siml SPEC=hunter_survival` (and BM and MM). Expected: three
  `tests/Forever/wowsims/hunter_*.build.json` files.
- [ ] **Step 4: Run** `.lua/bin/lua tools/wowsims/dry.lua $(ls tools/wowsims/specs | sed 's/.lua$//')`. Expected: the
  research's "new" counts (Balance 3, Feral 17, Guardian 15, Arcane 2, Fire 4, FFB 3, ProtPal 4, Rogue 13 each,
  Enh 6, Arms 37, Fury 37, ProtWar 24, Shadow 4, Smite 3, Affliction 2, Elemental 1, Demo 22, Shadow Brand 23,
  Destro 7, SM/Ruin 7, hunters 18/18/19). The warlock `select` crash (spec §4) may stop the four warlock builds: record
  it, do not fix it here (Task 16). Any other difference: explain it in the commit message.
- [ ] **Step 5: Smoke export one spec** to a scratch directory:
  `WOWSIMS_OUT=$(mktemp -d)/ make wowsims-export SPEC=warrior_protection`. Expected: a request and a log whose first
  line is `# wowsims e2842f0a78... warrior_protection ...`. Nothing changes in the repo.
- [ ] **Step 6: Run** `flock /tmp/hekili-gate.lock make check` (green: no request changed), and commit the recipes,
  the three build JSONs and `dry.lua`: `feat(wowsims): recipes at e2842f0a78 paths, SIML hunter builds, dry run`.

### Task 3: Translator reads (Phase 2)

**Files:**
- Modify: `tools/wowsims/apl.lua` (`M.VALUES`, `value()`, `bool()`, header rules)
- Test: `tests/Forever/wowsims_apl_spec.lua`

**Interfaces:**
- Produces these translations (spec §4):
  `talentIsKnown` -> `talent.<key>.enabled` (rule 4's `knownTest`/`c.talentKey`); `talentRank` -> `talent.<key>.rank`;
  `spellFullCooldown` -> `cooldown.<key>.duration`; `gcdIsReady` -> `gcd.remains<=0`;
  `spellGcdHastedDuration` -> `gcd.execute`; `currentHealth` -> `health.current`;
  `auraDuration` -> `<unit>.<key>.duration`; `dotBaseDuration` -> `debuff.<key>.duration`;
  `spellTravelTime` -> `action.<key>.travel_time`; `hpPercentForDefensives` -> the build's constant (the request's
  class options value; health is hidden in combat, Protection's precedent);
  `druidBleedIsActive` -> `druid_bleed_active` (a Druid kit state expression that Task 18 defines; until then no
  checked-in pack reads it); `strictMultidot` -> rule 17's line (current target, `# Deviation:` per entry).
  Every read of another ability's field is guarded by rule 6.

- [ ] **Step 1: Write the failing tests**, one `it` per kind, each translating a minimal APL entry and asserting the
  exact line text. Example: `talentIsKnown {spellId 20375}` with the kit talent `seal_of_command` gives
  `actions+=/<cast>,if=talent.seal_of_command.enabled`. Add an unlearned-ability case per read (rule 6's guard text).
- [ ] **Step 2: Run** `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/wowsims_apl_spec.lua`. Expected: FAIL (each kind unsupported).
- [ ] **Step 3: Implement** each read in `value()`/`bool()` (one-liners, or `M.VALUES` rows) and add each to the header's rule list.
- [ ] **Step 4: Run** the spec. Expected: PASS. Then `flock /tmp/hekili-gate.lock make check`. Expected: green, with
  `packs-check` unchanged (no checked-in APL uses these kinds yet).
- [ ] **Step 5: Run** `dry.lua` on Balance, Arcane, Fire, Frostfire, ProtPal and ProtWar, and record the falling counts in the commit message.
- [ ] **Step 6: Commit** `feat(wowsims): translate the talent, cooldown, GCD, health, duration and multidot reads`.

### Task 4: Casting, range, curses and pre-pull timing (Phase 2)

**Files:**
- Modify: `tools/wowsims/apl.lua`
- Test: `tests/Forever/wowsims_apl_spec.lua`

**Interfaces:**
- Produces: `spellIsCasting(X)` -> `action.<key>.executing` when the kit ability has a cast time, else `false` (S4);
  `spellInRange(X)` -> `action.<key>.in_range` (no movement rewrite yet: Task 7);
  `curseType`, `warlockIsAssignedCurse`, `warlockAssignedCurseIsActiveOnAllTargets`,
  `warlockBaneIsActiveOnAllTargets`, `dotIsActiveOnAllTargets`: through rule 16's `select` where the recipe has one,
  "on all targets" read on the current target (rule 17's precedent), else unsupported;
  a non-constant `doAtValue` that folds to a constant from the kit's cast time (e.g. `-spellCastTime(X)` -> `-<cast>`)
  orders the pre-pull line by that constant, else the line is omitted (rule 1); `spellExpectedDpet` stays unsupported.

- [ ] **Step 1: Write the failing tests.** `not(spellIsCasting(Starfire))` with a 3 s cast gives
  `!action.starfire.executing`, and with an instant gives no term (the `not` of false folds true). `spellInRange` gives
  `action.<key>.in_range`. A `doAtValue` of `-spellCastTime(Pyroblast)` sorts the line at `-<kit cast>`. Assert that each
  curse read with a `select` emits the setting term, and that without one it is unsupported.
- [ ] **Step 2: Run** the APL spec under the lock. Expected: FAIL.
- [ ] **Step 3: Implement** the reads and the `doAtValue` fold, and add the header rules.
- [ ] **Step 4: Run** the APL spec, then `flock /tmp/hekili-gate.lock make check`. Expected: PASS, green.
- [ ] **Step 5: Commit** `feat(wowsims): translate spellIsCasting, spellInRange, the curse reads and cast-time pre-pull`.

### Task 5: Movement terms dropped, the bracket's negation (Phase 2)

**Files:**
- Modify: `tools/wowsims/apl.lua` (rules 2, 11, 12 and a new rule 18 in the header)
- Test: `tests/Forever/wowsims_apl_spec.lua`

**Interfaces:**
- Produces: movement terms (`unitMovementSpeed`; `unitIsMoving` on any unit; `unitDistance` inside `math`,
  `min`/`max`, or compared with anything but a whole-number constant) return the empty value's nil triple
  (`nil, nil, true` in `bool()`, the nil value in `value()`). Rule 6 then drops them from their `and`/`or`, and a
  `cmp`/`math` over one is nil. Each dropped term is listed in the header (`# Dropped (movement): <entry>: <kind>`).
  `not` over a rule 11 comparison gives the opposite bracket (S4).

- [ ] **Step 1: Write the failing tests.** `and(cmp(timeToWalkIn <= 0s), cmp(autoTimeToNext RangedAuto > 0.5s))`,
  with "Time to walk in" a `math` over `unitDistance` and `unitMovementSpeed`, keeps only the timing term (written
  once Task 8 maps RangedAuto; until then assert the movement term is gone and the entry is listed).
  `unitIsMoving` alone as a condition gives a line with no condition (nil is true). `not(unitDistance > 5)` gives
  `target.within5`, and `not(unitDistance < 8)` gives `target.outside8`. `unitDistance OpNe max(a, b)` drops.
- [ ] **Step 2: Run** the APL spec under the lock. Expected: FAIL.
- [ ] **Step 3: Implement** the drop and the negation, and write rule 18 in the header: decision 8's text, and the
  note that it supersedes "reads false" and the run-speed constant.
- [ ] **Step 4: Run** the APL spec and `flock /tmp/hekili-gate.lock make check`. Expected: PASS, green. Run `dry.lua` on all
  specs and record the counts.
- [ ] **Step 5: Commit** `feat(wowsims): drop movement terms; a negated range bracket is the opposite bracket`.

### Task 6: The Movement toggle (Phase 3, S1)

**Files:**
- Modify: `src/Hekili/Options/Options.lua` (profile default; the Toggles group; `toggleNames`)
- Modify: `src/Hekili/Engine/Registry.lua` (`Registry.MovementSpec`)
- Modify: `src/Hekili/UI/UI.lua` (minimap menu entry)
- Modify: `src/Hekili/Options/ChatCommands.lua` (help text)
- Modify: `src/Hekili/Locales/*` through `python3 tools/locales.py`; `CHANGELOG.md` (Unreleased)
- Modify: `tests/Game/harness/loop.lua` (the per-driver setup beside `steadyIcons`)
- Test: `tests/Forever/movement_toggle_spec.lua` (new), `tests/Game/harness/replay_spec.lua`

**Interfaces:**
- Produces: `Hekili.DB.profile.toggles.movement` (`key = ""`, `value = true`); `state.toggle.movement`;
  `Registry.MovementSpec(specID: number) -> boolean` (true when that spec's options table has `movement = true`);
  the harness hook `d.H.Hekili.DB.profile.toggles.movement.value = (R ~= nil)` for every driver: ON in a replay, OFF
  in a loop and in `ws.live`.

- [ ] **Step 1: Write the failing tests** (pattern: `tests/Forever/minor_cooldowns_spec.lua`, warrior world):
  - a fresh profile: `t.movement.value == true`, `t.movement.key == ""`, `H.Hekili.State.toggle.movement == true`;
  - a saved profile with no `movement` key (Review Focus 2): the same three asserts;
  - `H.Hekili:FireToggle("movement")` makes `toggle.movement` false, and `H.Hekili:CmdLine("set movement on")` makes it true again;
  - `ParseActionList("actions+=/mortal_strike,if=toggle.movement")` makes Mortal Strike's line recommended or skipped by the value;
  - `Registry.MovementSpec(<warrior spec>) == false`, and true after the test spec's options set `movement = true`;
  - Review Focus 3: the options row's `hidden()` is true for a spec that has not opted in and false for one that has,
    and switching spec leaves `toggles.movement.value` unchanged;
  - in `replay_spec.lua`: a replay run reads `toggle.movement == true`, and a loop run reads false.
- [ ] **Step 2: Run** `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/movement_toggle_spec.lua`. Expected: FAIL.
- [ ] **Step 3: Implement** S1 and the harness hook. The options group copies the `potions` group's shape: `key` and
  `value`, no `override`.
- [ ] **Step 4: Run** `python3 tools/locales.py`, add the CHANGELOG "Unreleased" line ("A Movement toggle for
  priorities that move to reach the next ability: on, they show it out of range; off, they hide it until you are in
  range."), run the spec, then `flock /tmp/hekili-gate.lock make check`. Expected: PASS, green; `tests/boundary_spec.lua` passes (no class name in core).
- [ ] **Step 5: Commit** `feat: Movement toggle, a generic setting packs opt into`.

### Task 7: The move rewrite in the translator (Phase 3, spec §2.2, S3)

**Files:**
- Modify: `tools/wowsims/apl.lua` (rule 19: the move rewrite; rule 14b: a `sequence` as a chain; the header's `# Movement:` block)
- Modify: `src/Hekili_Hunter/Hunter.lua` (`movement = true`, only if the hunter packs read `toggle.movement`: Step 6)
- Test: `tests/Forever/wowsims_apl_spec.lua`, `tests/Forever/packs_spec.lua`
- Test: `tests/Forever/movement_gate_spec.lua` (new, headless)
- Modify: `docs/dev/ingame-ledger.md` (one row: the out-of-range tint during a walk with Movement ON)

**Interfaces:**
- Consumes: Task 4's `spellInRange`, Task 5's negation, Task 6's `toggle.movement`.
- Produces: for each `move` entry, the entries it reaches. In the same list after the move, these are the entries
  whose range gate is the move's target range (a rule 11 bracket at that range, a `spellInRange` of an ability whose
  max range is it, or the condition of a `waitUntil` the move precedes). Each reached entry's range gate becomes
  `(toggle.movement&<move condition>|<range gate>)`. Two moves reaching one entry join their conditions with `|`
  inside one `toggle.movement&(...)`. A distance-only `waitUntil` is omitted, and its condition, as a gate, is carried
  onto every later line of its list, or of the calling list when it ends a group or a sequence (S3). The header gets
  `# Movement: <move entry> reaches <actions>` per move. The pack reads `toggle.movement` exactly when some line was
  rewritten.

- [ ] **Step 1: Write the failing translator tests**, one APL shape each:
  - Feral-shaped: `move` if `dist>5`, `waitUntil not(dist>5)` if `dist>5`, then `shred`. Expected:
    `shred,if=<own>&(toggle.movement&target.outside5|target.within5)`, and the move and the `waitUntil` both listed as omitted.
  - Weave-shaped: a melee move under a timing condition, then `raptor_strike` gated `dist<=5`. Expected:
    `raptor_strike,if=<own>&(toggle.movement&(<timing>&target.outside5)|target.within5)`.
  - Two moves reaching one strike: the `|`-joined form.
  - Retribution-shaped (S3): the group call, the Judgement chain line, the seal behind `prev.1.judgement`, the carried
    Crusader Strike gate on the main list's later lines, and `sequenceIsComplete` absent from every line.
  - Review Focus 4: a reached entry whose own condition is `buff.x.up` keeps `buff.x.up&` outside the gate.
  - A list with no move gives byte-identical output to today's (no `toggle.movement`).
- [ ] **Step 2: Write the failing packs test** in `packs_spec.lua`: for every registered spec,
  `Registry.MovementSpec(id) == (pack text contains "toggle.movement")`.
- [ ] **Step 3: Write the failing headless test** `movement_gate_spec.lua` (warrior world; Mortal Strike's range
  0-5): a pack line `mortal_strike,if=(toggle.movement&target.outside5|target.within5)`.
  - At 20 yd, OFF: not recommended. ON: recommended.
  - At 3 yd: recommended both ways.
  - Review Focus 1: with no range answer yet (`ctl.distance` nil, target fresh) and with a secret answer, it is
    recommended both ways.
- [ ] **Step 4: Run** the three specs under the lock. Expected: FAIL.
- [ ] **Step 5: Implement** rules 19 and 14b and the header block, and write the ledger row.
- [ ] **Step 6: Run** the specs. Expected: PASS. Regenerate the packs (`make wowsims-packs && make packs`). Only the
  hunter packs may change. If they now read `toggle.movement`, set `movement = true` in the Hunter kit's
  `RegisterOptions` here (all three specs; the packs test needs it), and follow the Task order note for their replay
  lines. Then `flock /tmp/hekili-gate.lock make check`. Expected: green.
- [ ] **Step 7: Commit** `feat(wowsims): a move's reached entries take the Movement toggle or their range gate`.

### Task 8: The ranged auto-shot clock (Phase 3, spec §3)

**Files:**
- Modify: `src/Hekili_Hunter/Hunter.lua` (state expressions beside `mainhand_remains`)
- Modify: `tools/wowsims/apl.lua` (`autoTimeToNext`/`autoTimeSinceLast` `RangedAuto`)
- Test: `tests/Forever/hunter_spec.lua`, `tests/Forever/wowsims_apl_spec.lua`

**Interfaces:**
- Produces: `ranged_remains` (seconds to the next Auto Shot, from `swings.ranged_projected`, with the same
  now/query_time anchoring as `mainhand_remains`) and `ranged_speed` (`swings.ranged_speed`), both Hunter kit state
  expressions. The translator maps `autoTimeToNext RangedAuto` -> `ranged_remains` and `autoTimeSinceLast RangedAuto` ->
  `(ranged_speed-ranged_remains)`. No core change: the clock reaches the engine through the existing `UnitRangedDamage` tail.

- [ ] **Step 1: Write the failing tests.** With a projected shot 1.2 s ahead, `ranged_remains` is 1.2 at now and 0.7
  after advancing 0.5. Past a due shot it is `ranged_speed - (elapsed % ranged_speed)`. Review Focus 5: with
  `ranged_speed` 0 it returns 0 and raises nothing (the client's `x%0` raise). The translator test gives `ranged_remains>0.5`.
- [ ] **Step 2: Run** under the lock. Expected: FAIL.
- [ ] **Step 3: Implement** both expressions and the two translator rows. Guard the speed before the modulo.
- [ ] **Step 4: Run** the tests, then `flock /tmp/hekili-gate.lock make check`. Expected: PASS, green.
- [ ] **Step 5: Commit** `feat(hunter): ranged_remains, the Auto Shot clock the weave's timing reads`.

### Task 9: The old-pin hunter ON replay, the range pin, and the waits (Phase 3)

**Files:**
- Modify: `tools/wowsims/apl.lua` (`wait` -> `wait,sec=<constant>` behind `c.waits`; S4)
- Modify: the regenerated hunter packs; `tests/Forever/wowsims_hunter_spec.lua` (floors, flicker ceilings)
- Test: `tests/Game/harness/replay_spec.lua`

**Interfaces:**
- Consumes: Tasks 6-8 (the harness hook, the rewrite, the clock; the Hunter opt-in).
- Produces: the waits decision, recorded in the hunter spec file and in `docs/dev/wowsims-packs.md`'s rule 2 line.

- [ ] **Step 1: Write the failing harness test** in `replay_spec.lua` (S2's unknown-bracket pin): in a replay world
  at distance 20, `VS.TargetRange` is known at the pull, and a melee ability's `action.<key>.in_range` is false there.
  Also add a translator test: with `c.waits` on, a `wait` of a constant `1.5s` gives `wait,sec=1.5`, and one whose
  duration reads a walk term stays omitted.
- [ ] **Step 2: Run** both under the lock. Expected: the replay test passes or fails on the real path (a failure
  is a harness fix here). The translator test fails.
- [ ] **Step 3: Implement** the `c.waits` flag (off by default).
- [ ] **Step 4: Measure at the old pin.** `make wowsims-packs && make packs`, which regenerates the hunter packs from
  today's d3393 requests through Tasks 3-8. Run the hunter replay at floor 0, once with `c.waits` off and once on
  (`WOWSIMS_WAITS=1`, read by `export.lua pack`). Record both lines (decisions, n, top, flicker) per spec in the commit message.
- [ ] **Step 5: Decide the waits.** Keep them only if no hunter's decisions on-GCD falls and at least one rises by more
  than max(0.02, 2/n), with flicker no higher. If kept, `c.waits` becomes the default and the env switch goes. If not,
  delete the flag and its code.
- [ ] **Step 6: Re-floor the hunters on this measurement** (R5/R6 against the baseline; the cause is "Movement
  rewrite + C7 clock at the old pin"), with ON flicker ceilings. Run `flock /tmp/hekili-gate.lock make check`, then
  `make gate`. Expected: green.
- [ ] **Step 7: Commit** `test(wowsims): hunter weave replayed ON at the old pin; waits <kept|omitted>`.

### Task 10: Lane: Balance and the Mages (Phase 4)

**Files:** `tools/wowsims/specs/druid_balance.lua`, `mage_arcane.lua`, `mage_fire.lua`, `mage_frostfire.lua`; their
requests, logs and packs; `src/Hekili_Druid/Druid.lua`, `src/Hekili_Mage/Mage.lua` (rank IDs as R2 reveals);
`tests/Forever/wowsims_druid_spec.lua`, `wowsims_mage_spec.lua`.

**Interfaces:**
- Consumes: Tasks 1-5 (the Phase 1-2 translator) and Task 6's harness hook. None of these specs opts in.

- [ ] **Step 1:** Run R1-R7 for each of the four specs. Specifics: Balance's new pre-pull Innervate and rank-6 Starfire.
  The `spellIsCasting` guards are now translated, so on today's patched oracle they should hold or rise. A fall is
  traced, never accepted as "the patch" (the patch is dropped in Task 20). Arcane is "Deep Arcane" upstream: keep the
  pack name. Fire's and Frostfire's cast-time pre-pull lines come from Task 4's fold.
- [ ] **Step 2:** R9 per spec, then `make gate` once at the end of the lane.

### Task 11: Lane: Shadow, Smite, Affliction, Elemental (Phase 4)

**Files:** the four recipes, requests, logs and packs; `src/Hekili_Priest/Priest.lua`, `src/Hekili_Warlock/Warlock.lua`,
`src/Hekili_Shaman/Shaman.lua` as R2 reveals; `tests/Forever/wowsims_priest_spec.lua`, `wowsims_warlock_spec.lua`,
`wowsims_shaman_spec.lua`.

- [ ] **Step 1:** Run R1-R7 for each spec. Specifics: Shadow and SM/Ruin's `spellExpectedDpet` stays omitted.
  Affliction keeps `select` only if `aff_wrack.build.json` still carries `curseOptions`; if it does not, apply Task
  16's Bane rule here and note it. Elemental becomes Windshaper Skyborne: check the kit knows Skyborne's racial
  (mana-regen merge) and the autocast lines the log now shows. Elemental's unmapped item 272438 is mapped or listed.
- [ ] **Step 2:** R9 per spec; `make gate` at the end.

### Task 12: Lane: Protection Paladin (Phase 4)

**Files:** `tools/wowsims/specs/paladin_protection.lua`, its request, log and pack; `src/Hekili_Paladin/Paladin.lua`;
`tests/Forever/wowsims_paladin_spec.lua`.

- [ ] **Step 1:** Run R1-R7. Specifics: the Righteous Fury pre-pull; `talentIsKnown` and `spellFullCooldown` are now
  read. The non-distance `waitUntil` entries are classified one by one (spec §3): each becomes `wait,sec=` only when
  the time to its condition is a read the engine already has, else it is omitted and listed in the header. Keep the
  tank fields (`tank`, `healingModel`).
- [ ] **Step 2:** R9; `make gate`.

### Task 13: Lane: Rogue x3 (Phase 5)

**Files:** `tools/wowsims/specs/rogue_*.lua`, requests, logs, packs; `src/Hekili_Rogue/Rogue.lua`;
`tests/Forever/wowsims_rogue_spec.lua`.

- [ ] **Step 1:** Run R1-R7 for the three specs. Specifics: the `affords(builder)` definition and the energy-pooling
  group. The pooling `waitUntil` is classified as in Task 12, and the risk the spec names is measured. `darkmantle-set-512.patch`
  stays: check the log shows Rogue Armor Energize 27788.
- [ ] **Step 2:** R9; `make gate`.

### Task 14: Lane: Warrior x3 (Phase 5)

**Files:** `tools/wowsims/specs/warrior_*.lua`, requests, logs, packs; `src/Hekili_Warrior/Warrior.lua`;
`tests/Forever/wowsims_warrior_spec.lua`, the warrior loop specs.

- [ ] **Step 1:** Run R1-R7 for Arms, Fury and Protection. Specifics:
  - The stance-swap `strictSequence`s (rule 14, unchanged).
  - The per-spell GCD compares (`spellGcdHastedDuration`, Task 3).
  - `multipleCdUsages`, `alignCdEnd` and `selectedPotion` (`slot`): each node folds to a constant only where the
    fight's length decides it (180 s), else it is omitted; each is recorded as a `# Deviation:` header line.
  - Whirlwind's tag 14 and the Berserker Rage `requires` stay.
  - `FURY_LIVE_LEVELING` follows R7's rule.
  - Measured rage is wowsims's (the 11-02 catch-up ruling).
- [ ] **Step 2:** R9; `make gate`.

### Task 15: Lane: Enhancement (Phase 6)

**Files:** `tools/wowsims/specs/shaman_enhancement.lua`, request, log, pack; `src/Hekili_Shaman/Shaman.lua`;
`tests/Forever/wowsims_shaman_spec.lua`.

- [ ] **Step 1:** Run R1-R7. Specifics: the rotation comes from the build (`testing.build.json`); Windshaper Skyborne;
  the `itemSwap` item 250617 and `enableItemSwap` are omitted (`itemSwap` is rule 2); the build's Wisdom and Might
  blessings at `1`; the unmapped ID is mapped or listed.
- [ ] **Step 2:** R9; `make gate`.

### Task 16: Lane: Warlock x5 (Phase 6)

**Files:** `tools/wowsims/specs/warlock_*.lua`, requests, logs, packs; `src/Hekili_Warlock/Warlock.lua`;
`tests/Forever/wowsims_warlock_spec.lua`, `tests/Forever/warlock_spec.lua`; `tests/Forever/helpers/warlock_world.lua`
(DB2 `ranges`).

- [ ] **Step 1: The `select` fix first** (spec §4). For each build without `curseOptions` (Demonology, Shadow Brand,
  Destruction, SM/Ruin), the recipe drops `select`, its Bane lines become plain casts (Agony, Doom), and the class
  stops registering `assigned_curse` for those specs. Write a test that a saved `assigned_curse` value for those specs
  loads without error and is read by no line. Run `dry.lua` on the four: no crash.
- [ ] **Step 2:** Run R1-R7 for the five specs. Specifics: Sesam's Demonology APLs; `petAttack`, `changeTarget` and
  `newTarget` are omitted; `strictMultidot` (Task 3); Human race for four builds; `conjuredItems` as the build carries
  them; Destruction's spell 1225228 is mapped or listed.
- [ ] **Step 3: R8 for Demonology and Shadow Brand** (the 3-target move to melee range, spec §2.3): opt-in, ranges,
  the OFF test, the ON flicker ceiling. Demonology's `unitIsMoving` is dropped (Task 5) and listed.
- [ ] **Step 4:** R9; `make gate`.

### Task 17: Lane: Retribution (Phase 6, fresh floor)

**Files:** `tools/wowsims/specs/paladin_retribution.lua`, request, log, pack; `src/Hekili_Paladin/Paladin.lua`;
`tests/Forever/wowsims_paladin_spec.lua`, `tests/Forever/paladin_spec.lua`; `tests/Forever/helpers/paladin_world.lua`
(DB2 `ranges`).

**Interfaces:**
- Consumes: Task 7's rule 14b and the carried gate (S3).

- [ ] **Step 1:** Run R1-R3. Specifics: `default.apl.json` (Unsealed Wrath, talent-adaptive) and its new gear;
  the Twist of Light `requires`, `focus` tiers and `prepullSkip` re-read against the new APL, each kept only where
  its line still exists (an owner ruling that no longer applies is reported, not silently dropped); the pre-pull
  "Pull range" move is omitted (spec §2.3, decision 7).
- [ ] **Step 2: R8 first** (opt-in, ranges for Judgement, Crusader Strike, Exorcism, Consecration and the seals, the
  OFF test on the Judgement chain line and on a held melee line).
- [ ] **Step 3:** R4-R7 as a fresh floor. A disagreement traced to the pre-pull move or the move-in placement is a
  defect to fix (spec §2.3), never a floor cost.
- [ ] **Step 4:** R9; `make gate`.

### Task 18: Lane: Feral and Guardian (Phase 7, fresh floors)

**Files:** `tools/wowsims/specs/druid_feral.lua`, `druid_guardian.lua`, requests, logs, packs;
`src/Hekili_Druid/Druid.lua`; `tests/Forever/wowsims_druid_spec.lua`, `tests/Forever/druid_spec.lua`;
`tests/Forever/helpers/druid_world.lua`, `druid_loop_world.lua` (DB2 `ranges`).

**Interfaces:**
- Produces: `druid_bleed_active` (Druid kit state expression: a bleed of the kit's on the target, wowsims's
  `druidBleedIsActive` list as in sim/druid; the list and its source lines go in the comment).

- [ ] **Step 1: Write the failing kit test** for `druid_bleed_active`: true with Rake or Rip up on the target, false
  with none. Implement it. Run it under the lock.
- [ ] **Step 2:** Run R1-R3 for both. Specifics: the adaptive APLs (42 and 15 variables); Berserk gone (hotfix 113554);
  Lacerate as a talent; `talentRank` (Feral); `hpPercentForDefensives` as the build constant; `gcdIsReady`;
  Feral Charge stays a cast (Guardian). The recipe `requires`/`map`/`maintenance` are re-read against the new APLs.
- [ ] **Step 3: R8 for both** (the main-list "Finish closing to melee" gate on every later line, S3's rule; the OFF
  test on Shred and on Maul or Mangle).
- [ ] **Step 4:** R4-R7 as fresh floors. The omitted `waitUntil` risk (spec §7) is measured and classified.
- [ ] **Step 5:** R9; `make gate`.

### Task 19: Lane: Hunters x3 (Phase 8, fresh floors)

**Files:** `tools/wowsims/specs/hunter_*.lua`, requests, logs, packs, build JSONs; `src/Hekili_Hunter/Hunter.lua`;
`tests/Forever/wowsims_hunter_spec.lua`, `tests/Forever/hunter_spec.lua`; `tests/Forever/helpers/hunter_world.lua`
(the `RANGE` table: Sniper Shot's range checked with `wowdb`); `tools/wowsims/export.lua` (delete `M.OLD_SIM`);
`tests/Forever/wowsims_pin_spec.lua`.

- [ ] **Step 1:** Run R1-R3 for the three weave builds. Specifics: Sniper Shot and the trainer rank IDs in the kit;
  BM's pet Raptor; `startAttack`, `petAttack` and `recheckWhileMoving` are omitted; the dropped yard arithmetic is
  listed per entry; the waits as Task 9 decided.
- [ ] **Step 2: R8** (the opt-in exists since Task 7). Add the OFF tests on Raptor Strike (hidden outside 5 yd) and on
  a shot after the move back (hidden inside 5 yd).
- [ ] **Step 3:** R4-R7 as fresh floors. The old floors (1.00 / 0.92 / 0.97) are not comparable (spec §7); Task 9's
  old-pin ON measurement is the comparison point for the rewrite. A disagreement traced to the pre-pull "pull range"
  move is a defect (spec §2.3).
- [ ] **Step 4: Delete `M.OLD_SIM`** and its pin-spec branch: every log is now at `M.SIM_PIN`. Run the pin spec. Expected: PASS.
- [ ] **Step 5:** R9; `make gate`.

### Task 20: The oracle patches dropped, logs rerun (Phase 9)

**Files:** `tools/wowsims/sim-pin/build.sh`, `tools/wowsims/sim-pin/leftover_db.go`, `no-cast-end-pick.patch`
(deleted); every `tests/Forever/wowsims/*.log`; the floors that move.

- [ ] **Step 1: Check leftover_db's reason is gone.** For each of the 28 item IDs in `docs/dev/wowsims-packs.md`
  "Oracle patches", grep every request. Expected: none worn. If one is, keep `leftover_db.go` and record why.
- [ ] **Step 2:** Delete `leftover_db.go` (and its `build.sh` lines) and `no-cast-end-pick.patch`. Keep
  `darkmantle-set-512.patch`. Rebuild with `make wowsims-sim-cli`.
- [ ] **Step 3:** `.lua/bin/lua tools/wowsims/export.lua rerun <spec>` for all 26. Run `make gate`, and compare every
  replay line with the lanes' floors.
- [ ] **Step 4:** Each moved line follows R5/R6. The hardcast packs (Balance, the Mages, Destruction, Arms' Slam) are
  now read from guarded APLs: a fall is traced (spec §5), never accepted as "the patch".
- [ ] **Step 5:** `flock /tmp/hekili-gate.lock make check`, `make gate`. Commit
  `chore(wowsims): drop leftover_db and no-cast-end-pick; logs rerun on the unpatched oracle`.

### Task 21: Docs and the final check (Phase 9)

**Files:** `docs/dev/layout.md` (the pin section, every pack's gate lines), `docs/dev/wowsims-packs.md` (two pins ->
equal, rules 2, 11, 14b, 18, 19, the Movement toggle, "Oracle patches", the request-edits list), `docs/dev/gaps.md`
(entries the lanes opened or closed), `docs/dev/architecture.md` (the Movement toggle, one line in the content surface),
`DEVELOPMENT.md` (only if a section names the old pin or `OLD_SIM`).

- [ ] **Step 1: Verify every request was re-exported:** for each recipe,
  `git diff --quiet 0d98cb02c -- tests/Forever/wowsims/<spec>.json` must fail (changed). Expected: 26 changed.
- [ ] **Step 2:** Write the docs. Each rule reads as `apl.lua`'s header now does.
- [ ] **Step 3:** Run `make accuracy` and add its report under the baseline in the baseline file, as "after".
  Every spec beyond max(0.02, 2/n) of the baseline must have its cause beside its floor. Check that.
- [ ] **Step 4:** `flock /tmp/hekili-gate.lock make packs-check`, `flock /tmp/hekili-gate.lock make check`, `make gate`.
  Expected: green.
- [ ] **Step 5:** Commit `docs: re-pin to e2842f0a78, the Movement toggle, rules 14b, 18, 19`.

---

## Self-review

- Spec coverage: §0 decisions -> Global Constraints, S1-S4; §1 goals -> Tasks 1-21; §2.1 -> Task 6, S1; §2.2 ->
  Tasks 5, 7, S2, S3; §2.3 -> Tasks 9, 16-19 (R8); §3 -> Tasks 8, 9, 12, 13; §4 -> Tasks 3-5, 14, 16; §5 -> Tasks
  1, 2, 20, R3; §6 -> Global Constraints (no core change outside Options/UI/Registry); §7 -> R4-R8, Tasks 0, 9, 21;
  §8 -> the task order; §9 -> S4, Task 9 (waits), Tasks 12-14 (classifications), Task 7 (ledger row).
- Ordering: the harness hook (Task 6) lands before any pack reads `toggle.movement` (Task 7 at the earliest), and the
  Hunter opt-in lands in the task whose packs first read it, so the packs test holds on every commit.
- Phase 3's spec gate ("today's hunter packs regenerated at the old pin, replayed with ON") is Task 9 Steps 4-6.
- Interfaces: `Registry.MovementSpec`, `toggle.movement`, `ranged_remains`/`ranged_speed`, `druid_bleed_active`,
  `dry.lua`, `M.OLD_SIM`'s shape and `WOWSIMS_OUT` are each defined once and used under the same names.
- Floors: none pre-set. Every floor is R6's measured value with its traced cause.
