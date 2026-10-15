# VirtualState Event Facade, Phases A and B, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make VirtualState the only thing between Hekili and the client in both directions, and let class files declare what a cast does to the now-state (`now` handlers) instead of VirtualState replaying Hekili's sim handlers. Phase A: every frame Hekili makes comes from `Facade.CreateFrame` and subscribes to VirtualState's one client frame, which runs its sources and then delivers each event in the game's own shape; every game function Hekili reads goes through `ns.Facade` in one of three classes (passthrough, hybrid, virtual); the trace writes into Hekili's own snapshots. Phase B: the combat-log rows Hekili consumes (our casts, our swings and their outcomes, hits on us, our casts' auras, energize) synthesized from plain signals, back-dated to their observed time, with the Phase 1 feeds retired and the Warrior's Overpower and Revenge windows back in Classic's event-driven shape.

**Architecture:** `VirtualState/EventFacade.lua` owns the client frame from file load: subscriptions keep a unit list per subscriber, the frame's registration is the union of subscribers and sources, each event's slots go through `Plain` into locals, the sources run, then every subscriber's current `OnEvent`, then the rows the event completed. `VirtualState/CombatLog.lua` keeps a 64-row pool and delivers rows as `COMBAT_LOG_EVENT_UNFILTERED` with no payload; `Facade.CombatLogGetCurrentEventInfo` answers the row being delivered and `Facade.GetTime` its observed time while a back-dated row is delivered. The row sources are `Sources/Casts.lua` (own casts), `Sources/Rows.lua` (our swings and casts paired with the target's `UNIT_COMBAT` within `PAIR_WINDOW`), `Sources/Attackers.lua` (hits on us, credited by the hostiles-targeting-us set and per-attacker swing clocks) and our casts' auras and energize (Task 9 from the drain's apply; Task 10 from the `now` verbs). `VirtualState/Families/Now.lua` (Task 10) writes each own cast's effects when the fold reaches it: cost, cooldown and GCD from the declared fields, then the ability's `now` function in one shared context of Hekili's verb names mapped onto the belief; the drain no longer resets or replays Hekili's `state`. `VirtualState/Facade.lua` puts every row behind one wrapper whose single branch traces through `Hekili:Debug` while Hekili makes a snapshot.

**Tech Stack:** Lua 5.1 (WoW Forever client 1.60.1, interface 16001), busted, luacheck, lua-language-server, `lua5.1`/`luac5.1`.

**Spec:** `docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md` (binding, as amended with the user's nine decisions, its §13 "Decisions taken"). Read with it: the Phase 1 spec `docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md` ("spec §N" there), `docs/forever-facade-notes.md` (the 175 names and their evidence), `docs/research/2026-10-14-virtualstate-phase2-eventing-investigation.md` and `docs/research/2026-10-14-virtualstate-phase3-event-bus-outline.md`. House style: `docs/superpowers/plans/2026-10-14-hekili-virtualstate-phase1.md` and `docs/superpowers/plans/2026-10-15-forever-warrior-accuracy.md`.

## How this plan was checked

Every patch below was written and run before the plan was saved, on a scratch clone of `~/src/hekili` with a branch at `forever` = `75d71c8b` (which already holds the Warrior branch: its accuracy pass, the speed-based rage per swing, the `decay` and `max` fields, Bloodrage's `startsCombat = false`): Tasks 1 to 4 and 6 to 13 in order, each spec patch applied and run red, then the implementation patch and the whole verification block; the counts below are that replay's. Then every patch was extracted again from this markdown and the whole plan replayed from `75d71c8b` in a fresh clone: per task the spec patch run red, the implementation patch, the verification block, `git add` with exactly the task's commit list, a commit, and an empty `git status` after it (so each commit holds everything its tests need). The base counts at `75d71c8b`: 139 busted successes, luacheck 0 warnings in 65 files, `tools/check_api_reads.sh` 43 loaded files, the inventory diff empty, LuaLS no problems. The in-game checkpoints (Tasks 5 and 14) are the user's.

## Global Constraints

- Repository `~/src/hekili`. Work only in the worktree `~/src/hekili/.claude/worktrees/virtualstate-event-facade`, branch `virtualstate-event-facade`, which the controller creates from `forever` at `75d71c8b` (`git worktree add -b virtualstate-event-facade .claude/worktrees/virtualstate-event-facade 75d71c8b`). Git from WSL only. After each task's green verification and clean review, push the branch (`git push origin virtualstate-event-facade`); never push to `forever` or `classic`; never force-push. No task merges: `forever` at `75d71c8b` already holds the Warrior branch, so no task is blocked.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, naming the model that wrote the commit; an implementer on another model replaces `Claude Opus 5.5` with its own model's name.
- No LICENSE or README changes, in any repository. No changes to `archive/` or `Libs/`.
- Taco Dog Forever is read only; clean-room direction: TDF mechanics may be ported into Hekili with credit in the file header (spec §13 of the Phase 1 spec), Hekili code never flows into TDF. Files carrying `Plain`, the `issecretvalue` handling or another secret-value technique credit Catnip (Durts) in their header.
- Secret safety (event-facade spec §8, decision 8): no VirtualState code compares, indexes or does arithmetic on a client value without `issecretvalue()` first; none uses `a and b or c` on a possibly-secret value; every client read in `VirtualState/Sources/` goes through `Plain(api, v)` or carries a `-- secret:` comment saying why the raw value is safe (`VirtualState/spec/secrets_spec.lua` enforces it); every event slot reaches a subscriber through `Plain`; every combat-log row holds plain values or the layer's constants; a hybrid tests its raw answer before using it; a passthrough is raw by its class and the trace counts its secret answers.
- Performance: receiving, gating, delivering, emitting and queueing rows, `CombatLogGetCurrentEventInfo`, the pairing and attribution, every facade row's wrapper with the trace off: no allocation, no closures or tables in recurring paths; allocations happen at load, at `Start`, at `SpecChanged` or at a subscription. Each task with a recurring path has a 0-byte case (`VirtualState/spec/helpers/alloc.lua`).
- TOC order (`Hekili.toc`): `VirtualState\Families\Now.lua` (Task 10) goes right after `VirtualState\Families\Enemies.lua`, and `VirtualState\Families\Modifiers.lua` (Task 11) right after it; `Races.lua` (Task 11) right after `State.lua`; the class file at `Forever\Classes\Warrior.lua` and every race file (`Forever\Races\Gnome.lua`, Task 11) after it; the other new files go after `VirtualState\AplWarnings.lua` and before `VirtualState\Facade.lua`, in this order: `VirtualState\EventFacade.lua` (Task 1), `VirtualState\CombatLog.lua` (Task 6), `VirtualState\Sources\Rows.lua` (Task 7), `VirtualState\Sources\Attackers.lua` (Task 8). Adding files to the TOC needs a client restart, not a `/reload`, before the next checkpoint.
- Scope: phases A and B of the spec (§11), `now` handlers (§12a, version 1: cast success), the shared racials and resource modifiers (§12b) and the decision-7 follow-up. Not phase C (deaths, plates' damage, the believed `UNIT_AURA` lists) or phase D (debuff travel, the compensating removal); not the stance swap into Battle Stance for Overpower (spec §12).
- Tools: `BUSTED=~/src/TacoDogForever/.lua/bin/busted`, `LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`, `LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server`, `lua5.1`, `luac5.1`. All commands run from the worktree root.
- Every task ends with the verification block, written out per task with its expected results, then a commit:

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
- Style: VirtualState files and specs use the TDF layout (4 spaces, no spaces inside parentheses, 120 columns); edits to Hekili's own files keep Hekili's style (spaces inside parentheses); `Forever/Classes/Warrior.lua` and `Forever/Races/*.lua` keep Hekili's style, the Forever specs the TDF layout.
- The user runs the game. A **CHECKPOINT** task stops execution: the orchestrator (not a subagent) pushes the branch, points the client's checkout at it with `git -C ~/src/hekili checkout --detach virtualstate-event-facade`, asks the user to run the exact lines given, and waits. Every in-game line is under 255 characters and copies its answer through `VSCopy(` (ForeverProbe's copy box, `/vscopy` reopens it): the user cannot copy chat. When the session ends, `git -C ~/src/hekili checkout forever`.

## The events this plan handles (signatures)

Checked on 2026-10-15 against the client's event and API docs with the `wow` MCP server, flavor `forever` (`wow_api_event_search`, `wow_api_search`); the controller re-checks them before execution. Positions are what the handlers below destructure.

| Event or function | Payload / signature (Forever docs) | Read by |
|---|---|---|
| `UNIT_COMBAT` | `unitTarget, event, flagText, amount, schoolMask` | `Sources/Rows.lua` (target), `Sources/Attackers.lua` (player); Hekili's player handler (`Events.lua:1716`) |
| `PLAYER_SWING` | `swingDuration, swingType` (0 main hand, 1 off hand) | `Sources/Swing.lua`, `Sources/Rows.lua` |
| `UNIT_SPELLCAST_SUCCEEDED`, `_START`, `_FAILED`, `_DELAYED`, `_CHANNEL_START`, `_CHANNEL_UPDATE` | `unitTarget, castGUID, spellID, castBarID?` | `Sources/Casts.lua`, `Sources/Rows.lua` |
| `UNIT_SPELLCAST_INTERRUPTED`, `_CHANNEL_STOP` | `unitTarget, castGUID, spellID, interruptedBy, castBarID?` | `Sources/Casts.lua` (slots 1-3) |
| `UNIT_SPELLCAST_SENT` | `unitTarget, target, castGUID, spellID` | `Sources/Casts.lua` (slot 1) |
| `UNIT_TARGET` | `unitTarget` | `Sources/Attackers.lua` |
| `NAME_PLATE_UNIT_ADDED`, `_REMOVED` | `unitToken` | `Sources/Nameplates.lua`, `Sources/Attackers.lua` |
| `PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED` | none documented | `Sources/Attackers.lua` |
| `UNIT_AURA` | `unitTarget, updateInfo` | the layer replaces `updateInfo` (spec §2.2) |
| `COMBAT_LOG_EVENT_UNFILTERED` | none documented; the row from `CombatLogGetCurrentEventInfo()` | Hekili's `CLEU_HANDLER` (`Events.lua:1399, 1706`), class hooks, the DevTools listener |
| `UnitAttackSpeed(unit)` | `attackSpeed, offhandAttackSpeed?, rangedAttackSpeed?` | the facade (hybrid), `Sources/Attackers.lua` (probe 1) |
| `UnitIsUnit(unit1, unit2)` | `result` | `Sources/Attackers.lua` (probe 2) |

## Review Focus

1. **Hekili cannot tell** (decision 2): a frame's `OnEvent` gets the same arguments whether the event is real or synthesized; `COMBAT_LOG_EVENT_UNFILTERED` arrives with no payload. Tests: Task 1 `event_facade_spec` "runs the source before the subscriber ..."; Task 6 `cleu_rows_spec` "emits SPELL_CAST_SUCCESS after the cast event's subscribers, in the client's shape".
2. **A raising Hekili handler or a frame unregistering itself mid-delivery** must not stop the next subscriber (the boot frame unregisters at `PLAYER_LOGIN`). Test: Task 1 "keeps delivering after a handler raises or unregisters itself mid-delivery".
3. **A hit on us that nothing can attribute** must make no row (Protection's tank branch would count a phantom enemy). Tests: Task 8 "emits no row when nobody is known to target us, or the answer is secret" and "credits each hit ... none off both clocks".
4. **A back-dated row** must give Hekili its observed time and leave the clock real after: Task 6 "answers a back-dated row's time from Facade.GetTime while it is delivered, the clock after"; Task 7 "emits an unpaired swing as SWING_DAMAGE 0 once its window closes, at its own time".
5. **Double recording**: the Phase 1 feeds are gone in the tasks that land the rows. Tests: Task 6 and 7's `adapter_spec` "leaves the cast history, the real queue and the swing fields to the combat-log rows".
6. **A `now` handler that raises, or reaches for Hekili's state**: the fold must go on and Hekili's `state` must stay untouched. Tests: Task 10 `now_spec` "counts a raising `now` and keeps folding the observations after it", "shifts a resource by `gain` (est, lo and hi) and writes its energize row back-dated to the cast" (it asserts `state.rage.actual` stays 0) and "writes nothing when a `now` runs outside a cast (RunStressTest, an APL reading action.x.now)".

## File structure

```
VirtualState/EventFacade.lua        Task 1  the client frame, subscriptions with per-subscriber units, delivery, UNIT_AURA's payload
                                    Task 4  a trace line per event; Task 6  E.Deliver, rows at the end of each event and OnUpdate
VirtualState/Sources/Sources.lua    Task 1  S.Run (gated slots), S.HANDLERS/S.UNITS, VS.Start attaches to the layer's frame
                                    Task 7  I.feed removed
VirtualState/Facade.lua             Task 2  three classes, passthrough/hybrid helpers, all 176 names, CreateFrame
                                    Task 4  one wrapper per row with the trace branch; Facade.Attach; secret counts
                                    Task 6  GetTime (hybrid: back-dating), CombatLogGetCurrentEventInfo (the current row)
                                    Task 12 the GCD spell, the empty spec slot, GetTalentInfoByID from the walk
VirtualState/CombatLog.lua          Task 6  the row pool, Emit/Cast/Deliver/Current, the deferred lane; Task 9  aura and energize rows
VirtualState/Sources/Casts.lua      Task 6  own-cast rows instead of the feeds; the player's GUID
VirtualState/Sources/Rows.lua       Task 7  our swings and abilities paired with the target's UNIT_COMBAT
VirtualState/Sources/Swing.lua      Task 7  the swing feed call removed
VirtualState/Sources/Attackers.lua  Task 8  who targets us, attacker clocks, rows on us; Task 9  the target's GUID for aura rows
VirtualState/Adapter.lua            Task 2  boot frame and clock from the facade; Task 4  Facade.Attach, SetupDebug wrap
                                    Task 6  cast feeds removed; Task 7  swing feed removed; Task 9  aura and energize rows
                                    Task 10 the apply route (reset, readBefore/readAfter, apply) removed; the drain is the fold
VirtualState/Families/Now.lua       Task 10 the `now` context, the automatic cost/cooldown/GCD, VS.KnownRank; Task 11 charged cost modifiers
VirtualState/Families/Modifiers.lua Task 11 `costMods`: I.CostMod, I.SpendCostCharges (and the `maxMods` contract)
VirtualState/Families/Resources.lua Task 11 the one maximum evaluator applies `maxMods`
VirtualState/Families/Casts.lua     Task 11 I.CostOf through the cost modifiers, I.BaseCostOf
Classes.lua, State.lua              Task 11 RegisterAbility's cost wrap and ns.applyRace after the merge; `state.race_token`, `race.<token>`; the sim's charge call
Races.lua                           Task 11 Hekili:NewRace (race packs), ns.applyRace (the race wins a key clash); the simulation's half of `costMods`
VirtualState/Belief.lua, Snapshot.lua, Facade.lua, Sources/Spellbook.lua   Task 10 no stop-at-cast, `now` counters, no pinned clock, A.known
VirtualState/spec/*                 every task; helpers/fake_api.lua Tasks 1 and 8
Hekili files (14), Formatting.lua and Forever/Warrior.lua  Task 2  file-top locals from ns.Facade, CreateFrame from the facade
Events.lua                          Task 3  UNIT_AURA's original body; Task 6  the CLEU skip reverted; Task 12  GCD 61304, updateTalents
Classes.lua, UI.lua, Options/Options.lua   Task 12  GCD 61304, the spec loop's original break
.luacheckrc, tools/check_api_reads.sh, tools/api_inventory.txt   Task 2 (inventory classes again in Tasks 6 and 12; .luacheckrc again in Tasks 10 and 11)
Hekili.toc                          Tasks 1, 6, 7, 8, 10, 11
Forever/Classes/Warrior.lua         Task 11 moved from Forever/Warrior.lua; Task 13: windows, `now` lines, `knownRank`, no Gnome max
Forever/spec/*                      Task 2 the loader's ns.Facade; Task 11 its path; Task 13 its fakes and the Warrior's tests
Forever/Races/Gnome.lua             Task 11 the Gnome race pack: Eureka!, Expansive Mind, Eureka!'s spell-scoped cost modifier
```

## Order and checkpoints

Tasks 1 to 4 (phase A), then Task 5, CHECKPOINT A. Tasks 6 to 9 (phase B's rows), Task 10 (`now` handlers: our casts' effects from the class files' declared now-state, which retires the drain's reset-apply-reset; after Task 9 because it moves Task 9's aura and energize rows into its verbs), Task 11 (race packs, the class file's move to `Forever/Classes/`, and the resource definition's `maxMods`/`costMods`; after Task 10 because it extends `I.CostOf` and Task 10's automatic cost step), Task 12 (the decision-7 follow-up), Task 13 (the Warrior file: its windows, its `now` lines, and no Gnome stopgap), then Task 14, CHECKPOINT B, which starts with phase B's two probes and the pairing gap. Decision 7 asks for the follow-up after phase A; it runs here after phase B's code because its patches were replayed in that order, and CHECKPOINT B checks it with the rest.

Deliberately not built (a review should not flag them): `now` handlers for non-cast triggers (`spec:RegisterNow(kind, fn)`: the dodge, the kill, an aura tick; spec §12a, later with phase C's observation kinds); an event inventory file (spec §1.2: registrations depend on runtime; `Snapshot()` lists refused events); a separate trace ring or `/hekili vs` command (decision 3); rows for other units' casts, deaths, plates' damage and the believed `UNIT_AURA` lists (phase C); debuff travel and the compensating removal (phase D); Overpower's stance swap (spec §12); a channel's `SPELL_CAST_SUCCESS` from `UNIT_SPELLCAST_CHANNEL_START` (it comes from `UNIT_SPELLCAST_SUCCEEDED`, like every success; no Forever Warrior ability channels).

---

### Task 1: The event facade: VirtualState's client frame, subscriptions and delivery

Phase A, spec §2.1-§2.3, decisions 1 and 2. Today `VS.Start` creates VirtualState's frame at `PLAYER_LOGIN` (`VirtualState/Sources/Sources.lua:176-189`) and Hekili's frames register with the client directly. This task adds `VirtualState/EventFacade.lua`: the layer's client frame exists from file load (from the client's `CreateFrame`, resolved once from `_G`; a headless spec sets `_G.CreateFrame` and `_G.issecretvalue` to the fake's before loading, or the frame is made at `Start` from the injected `api`), and `I.Events.CreateFrame` returns client frames whose `RegisterEvent`, `RegisterUnitEvent`, `UnregisterEvent`, `UnregisterAllEvents` and `IsEventRegistered` are the layer's. Each subscription keeps its own units (Hekili's player and target frames both subscribe to the same unit events, `Events.lua:207, 227`); the client registration of an event is the union of the subscribers' and, after `Start`, the sources' units (two or fewer: `RegisterUnitEvent`; more, or a general subscriber: `RegisterEvent`), registered through `pcall` (a refused event is a stub, never delivered). One client event: every slot through `Plain` into a local, the sources (`S.Run`, once `I.api` is set), then each matching subscriber's current `OnEvent` script under `pcall` (an error is counted and reported through `geterrorhandler`; the loop goes on). An unsubscription touches the client registration only for an event the frame had (`UnregisterAllEvents` walks every event). `UNIT_AURA` reaches a player or target subscriber with the layer's preallocated `{ isFullUpdate = true }` and other units with nil. `COMBAT_LOG_EVENT_UNFILTERED` and `FRAME_UPDATE` are never registered with the client. Nothing in Hekili uses the layer yet (Task 2 points `CreateFrame` at it).

`Sources.lua` loses its frame: `S:OnEvent` becomes `S.Run(api, event, a1..a5)` (slots already gated), the registry is exposed as `S.HANDLERS`/`S.UNITS`, and `VS.Start` calls `I.Events.Attach(api)`. The fake client's frames gain `UnregisterEvent` and `GetScript`, `RegisterEvent` raises for `ctl.unknownEvents`, and `api.frame` is the first frame made (the layer's).

**Files:**
- Create: `VirtualState/EventFacade.lua`, `VirtualState/spec/event_facade_spec.lua`
- Modify: `VirtualState/Sources/Sources.lua` (header :2-4; the registry :114-115; `S:OnEvent`, `onEvent`, `onUpdate`, `VS.Start` :152-203), `Hekili.toc` (after `VirtualState\AplWarnings.lua`), `VirtualState/spec/helpers/fake_api.lua` (`ctl` :56-57, the frame :209-230)

**Interfaces:**
- Consumes: `S.Plain`, `S.Flush`, `I.OnSnapshot` (Phase 1).
- Produces: `I.Events` (`E`): `E.CreateFrame(...)`, `E.Subscribe(frame, e, u1, u2) -> boolean`, `E.Unsubscribe(frame, e)`, `E.IsSubscribed(frame, e)`, `E.Attach(api)`, `E.frame`, `E.STUB[e]`, `E.delivered`, `E.errors`, `E.lastError`; `S.Run(api, event, a1..a5)`, `S.HANDLERS`, `S.UNITS`; `Snapshot()`'s line `events delivered=<n> errors=<n> stubs=[...]`; fake api: `ctl.unknownEvents`, `frame:GetScript`, `frame:UnregisterEvent`.

- [ ] **Step 0: Put the spec and this plan on the branch**

The controller commits the final versions of both on `forever-warrior-profile`, where they were written (`forever` at `75d71c8b` holds earlier drafts); bring them over:

```bash
git checkout forever-warrior-profile -- docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md \
  docs/superpowers/plans/2026-10-15-virtualstate-event-facade-phase-ab.md
git commit -m "docs: the VirtualState event-facade spec (amended with the user's decisions) and its phase A and B plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/event_facade_spec.lua b/VirtualState/spec/event_facade_spec.lua
new file mode 100644
index 00000000..6044375d
--- /dev/null
+++ b/VirtualState/spec/event_facade_spec.lua
@@ -0,0 +1,216 @@
+-- VirtualState/spec/event_facade_spec.lua (event-facade spec §2, §9): frames from the event facade's CreateFrame
+-- subscribe to VirtualState's frame, the only one the fake client sees; the layer runs the sources first, then each
+-- subscriber's current OnEvent with the game's payload shape (secret slots nil, UNIT_AURA's full update), filters
+-- units per subscriber, never registers the combat log, and allocates nothing per event.
+local load = require("VirtualState.spec.helpers.load")
+local fake = require("VirtualState.spec.helpers.fake_api")
+local alloc = require("VirtualState.spec.helpers.alloc")
+
+describe("the event facade", function()
+    local api, ctl, ns, VS, I, E, S, saved
+
+    -- A Hekili-like frame: its handler records (event, a1, a2) and an order stamp.
+    local order
+    local function subscriber(log)
+        local f = E.CreateFrame("Frame")
+        f:SetScript("OnEvent", function(_, event, a1, a2)
+            order = order + 1
+            log[#log + 1] = { event = event, a1 = a1, a2 = a2, at = order }
+        end)
+        return f
+    end
+
+    before_each(function()
+        api, ctl = fake.new()
+        saved = { CreateFrame = rawget(_G, "CreateFrame") or false, issecretvalue = rawget(_G, "issecretvalue") or false }
+        _G.CreateFrame, _G.issecretvalue = api.CreateFrame, api.issecretvalue -- the client, as the game has it at load
+        ns = load.module()
+        VS, I = ns.VirtualState, ns.VirtualStateInternal
+        E, S = I.Events, I.Sources
+        order = 0
+    end)
+
+    after_each(function()
+        for k, v in pairs(saved) do
+            _G[k] = v or nil
+        end
+    end)
+
+    it("delivers from load, before Start, and adds the sources at Start without registering anything twice", function()
+        local log = {}
+        local f = subscriber(log)
+        f:RegisterEvent("PLAYER_ENTERING_WORLD")
+        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
+        assert.are.equal(E.frame, api.frame) -- the layer's frame exists from load
+        assert.is_true(api.frame.events.PLAYER_ENTERING_WORLD)
+        assert.is_nil(api.frame.events.PLAYER_SWING) -- a source event waits for Start
+        assert.are.same({}, f.events) -- the subscriber is never registered with the client
+        ctl.Fire("PLAYER_ENTERING_WORLD", true, false)
+        assert.are.equal(1, #log) -- before Start: delivered, the sources skipped (I.api is nil)
+        assert.are.equal(0, S.stN)
+        VS.Start(api)
+        assert.are.equal(E.frame, api.frame)
+        assert.is_true(api.frame.events.PLAYER_SWING)
+        assert.are.same({ "player" }, api.frame.units.UNIT_SPELLCAST_SUCCEEDED) -- the sources' player and ours: one unit
+        local staged = S.stN
+        ctl.Fire("PLAYER_SWING", 2.6, 0)
+        assert.are.equal(staged + 1, S.stN) -- the source ran
+        assert.are.equal(0, E.errors)
+    end)
+
+    it("runs the source before the subscriber, and hands a secret slot over as nil", function()
+        local sourceAt, got
+        S.On("TEST_EVENT", nil, function(_, _, a1)
+            order = order + 1
+            sourceAt, got = order, a1
+        end)
+        VS.Start(api)
+        local log = {}
+        subscriber(log):RegisterEvent("TEST_EVENT")
+        ctl.Fire("TEST_EVENT", fake.SECRET, "plain")
+        assert.are.equal(1, sourceAt)
+        assert.is_nil(got)
+        assert.are.equal(2, log[1].at)
+        assert.is_nil(log[1].a1)
+        assert.are.equal("plain", log[1].a2)
+    end)
+
+    it("filters units per subscriber: the player's and the target's frame each hear their own unit once", function()
+        local pl, tl = {}, {}
+        subscriber(pl):RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
+        subscriber(tl):RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
+        assert.are.same({ "player", "target" }, api.frame.units.UNIT_SPELLCAST_START)
+        ctl.Fire("UNIT_SPELLCAST_START", "target", "Cast-1", 78)
+        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-2", 78)
+        assert.are.equal(1, #pl)
+        assert.are.equal("player", pl[1].a1)
+        assert.are.equal(1, #tl)
+        assert.are.equal("target", tl[1].a1)
+    end)
+
+    it("registers a third unit as the general event and still filters each subscriber", function()
+        local a, b, c = {}, {}, {}
+        subscriber(a):RegisterUnitEvent("UNIT_TARGET", "player", "target")
+        subscriber(b):RegisterUnitEvent("UNIT_TARGET", "focus")
+        subscriber(c):RegisterUnitEvent("UNIT_TARGET", "player")
+        assert.is_true(api.frame.events.UNIT_TARGET)
+        assert.is_nil(api.frame.units.UNIT_TARGET) -- general
+        ctl.Fire("UNIT_TARGET", "nameplate3")
+        ctl.Fire("UNIT_TARGET", "focus")
+        ctl.Fire("UNIT_TARGET", "player")
+        assert.are.equal(1, #a)
+        assert.are.equal(1, #b)
+        assert.are.equal(1, #c)
+    end)
+
+    it("delivers UNIT_AURA with the layer's full update for the player and target, nil for other units", function()
+        local log = {}
+        subscriber(log):RegisterUnitEvent("UNIT_AURA", "player", "target")
+        local other = {}
+        subscriber(other):RegisterEvent("UNIT_AURA")
+        ctl.Fire("UNIT_AURA", "player", fake.SECRET)
+        ctl.Fire("UNIT_AURA", "nameplate2", { addedAuras = {} })
+        assert.are.equal(1, #log)
+        assert.is_true(log[1].a2.isFullUpdate)
+        assert.are.equal(2, #other)
+        assert.are.equal(log[1].a2, other[1].a2) -- the same preallocated table
+        assert.is_nil(other[2].a2)
+    end)
+
+    it("stops on UnregisterEvent, dropping the client registration nobody needs, and on a cleared OnEvent", function()
+        local log = {}
+        local f = subscriber(log)
+        f:RegisterEvent("PLAYER_TARGET_CHANGED")
+        assert.is_true(f:IsEventRegistered("PLAYER_TARGET_CHANGED"))
+        f:UnregisterEvent("PLAYER_TARGET_CHANGED")
+        assert.is_false(f:IsEventRegistered("PLAYER_TARGET_CHANGED"))
+        assert.is_nil(api.frame.events.PLAYER_TARGET_CHANGED)
+        f:RegisterEvent("PLAYER_TARGET_CHANGED")
+        f:SetScript("OnEvent", nil) -- ns.StopEventHandler
+        ctl.Fire("PLAYER_TARGET_CHANGED")
+        assert.are.equal(0, #log)
+    end)
+
+    it("makes an event the client refuses a stub, never delivered", function()
+        ctl.unknownEvents.NOT_AN_EVENT = true
+        local log = {}
+        assert.is_false(subscriber(log):RegisterEvent("NOT_AN_EVENT"))
+        assert.is_true(E.STUB.NOT_AN_EVENT)
+        assert.is_nil(api.frame.events.NOT_AN_EVENT)
+    end)
+
+    it("never registers the combat log with the client", function()
+        local f = subscriber({})
+        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+        VS.Start(api)
+        assert.is_nil(api.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
+        assert.is_true(f:IsEventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
+    end)
+
+    it("delivers a client event fired from a handler in its own call, with its own payload", function()
+        local outer, inner = {}, {}
+        local first = E.CreateFrame("Frame")
+        first:SetScript("OnEvent", function(_, event)
+            if event == "OUTER" then
+                ctl.Fire("INNER", "i1")
+            end
+        end)
+        first:RegisterEvent("OUTER")
+        subscriber(outer):RegisterEvent("OUTER")
+        subscriber(inner):RegisterEvent("INNER")
+        ctl.Fire("OUTER", "o1", "o2")
+        assert.are.equal("i1", inner[1].a1)
+        assert.are.equal("o1", outer[1].a1)
+        assert.are.equal("o2", outer[1].a2)
+        assert.is_true(inner[1].at < outer[1].at)
+    end)
+
+    it("keeps delivering after a handler raises or unregisters itself mid-delivery", function()
+        local boot = E.CreateFrame("Frame")
+        boot:SetScript("OnEvent", function(self)
+            self:UnregisterAllEvents()
+            error("boom")
+        end)
+        boot:RegisterEvent("PLAYER_LOGIN")
+        local log = {}
+        subscriber(log):RegisterEvent("PLAYER_LOGIN")
+        ctl.Fire("PLAYER_LOGIN")
+        ctl.Fire("PLAYER_LOGIN")
+        assert.are.equal(2, #log)
+        assert.are.equal(1, E.errors)
+        assert.is_false(boot:IsEventRegistered("PLAYER_LOGIN"))
+    end)
+
+    it("re-registers on UnregisterAllEvents only the events the frame had", function()
+        local a, b = subscriber({}), subscriber({})
+        a:RegisterEvent("PLAYER_ENTERING_WORLD")
+        b:RegisterEvent("SPELLS_CHANGED")
+        local touched = {}
+        local unregister = api.frame.UnregisterEvent
+        api.frame.UnregisterEvent = function(self, e)
+            touched[#touched + 1] = e
+            unregister(self, e)
+        end
+        a:UnregisterAllEvents()
+        assert.are.same({ "PLAYER_ENTERING_WORLD" }, touched)
+        assert.is_true(api.frame.events.SPELLS_CHANGED)
+    end)
+
+    it("allocates nothing per delivered event", function()
+        VS.Start(api)
+        local sink = E.CreateFrame("Frame")
+        sink:SetScript("OnEvent", function() end)
+        sink:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
+        sink:RegisterUnitEvent("UNIT_AURA", "player", "target")
+        sink:RegisterEvent("PLAYER_TARGET_CHANGED")
+        local bytes = alloc.bytes(function(i)
+            ctl.now = i
+            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 6673)
+            ctl.Fire("UNIT_AURA", i % 2 == 0 and "player" or "target", fake.SECRET)
+            ctl.Fire("PLAYER_TARGET_CHANGED")
+            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "target", fake.SECRET, fake.SECRET)
+            S.Flush()
+        end, 10000)
+        assert.are.equal(0, bytes)
+    end)
+end)
diff --git a/VirtualState/spec/helpers/fake_api.lua b/VirtualState/spec/helpers/fake_api.lua
index d0daabc8..b83de73e 100644
--- a/VirtualState/spec/helpers/fake_api.lua
+++ b/VirtualState/spec/helpers/fake_api.lua
@@ -56,6 +56,7 @@ function M.new()
         traits = nil, -- { config = id, trees = { tree }, nodes = { [node] = info }, entries = {}, defs = {} }
         inRange = {},
         handlers = {},
+        unknownEvents = {}, -- [event] = true: RegisterEvent raises, as the client does for an event it does not know
     }
     local api = { ctl = ctl }
 
@@ -207,26 +208,39 @@ function M.new()
         end,
     }
 
-    -- The frame: records registrations; Fire delivers an event to its OnEvent, ctl.Tick runs its OnUpdate.
+    -- Frames: each records its registrations; the first one made is the client's view of VirtualState's frame
+    -- (`api.frame`): Fire delivers an event to its OnEvent when registered, ctl.Tick runs its OnUpdate.
     function api.CreateFrame()
         local f = { events = {}, units = {}, scripts = {} }
         function f:RegisterEvent(e)
+            if ctl.unknownEvents[e] then
+                error("Attempt to register unknown event \"" .. e .. "\"")
+            end
             self.events[e] = true
+            self.units[e] = nil
+            return true
         end
         function f:RegisterUnitEvent(e, u1, u2)
             self.events[e] = true
             self.units[e] = { u1, u2 }
+            return true
+        end
+        function f:UnregisterEvent(e)
+            self.events[e], self.units[e] = nil, nil
         end
         function f:SetScript(name, fn)
             self.scripts[name] = fn
         end
+        function f:GetScript(name)
+            return self.scripts[name]
+        end
         function f:Fire(event, ...)
             local fn = self.scripts.OnEvent
             if fn and self.events[event] then
                 fn(self, event, ...)
             end
         end
-        api.frame = f
+        api.frame = api.frame or f
         return f
     end
     function ctl.Tick(now)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `130 successes / 9 failures / 12 errors`: every `event_facade_spec` case errors with `attempt to index upvalue 'E' (a nil value)`, and the old `VS.Start` fails against the fake's first-frame rule (the adapter's boot frame becomes `api.frame`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Hekili.toc b/Hekili.toc
index e6ffad54..cbc49894 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -34,6 +34,7 @@ VirtualState\Sources\Nameplates.lua
 VirtualState\Sources\Totems.lua
 VirtualState\Snapshot.lua
 VirtualState\AplWarnings.lua
+VirtualState\EventFacade.lua
 VirtualState\Facade.lua
 
 Hekili.lua
diff --git a/VirtualState/EventFacade.lua b/VirtualState/EventFacade.lua
new file mode 100644
index 00000000..d07e14c9
--- /dev/null
+++ b/VirtualState/EventFacade.lua
@@ -0,0 +1,264 @@
+-- VirtualState/EventFacade.lua
+-- The event facade (event-facade spec §2): VirtualState's frame is the only frame registered with the client. Every
+-- frame Hekili makes comes from Facade.CreateFrame, whose event methods subscribe to this layer instead of the client;
+-- the layer registers the union of its subscribers and VirtualState's sources, runs the sources first, then calls
+-- each subscriber's current OnEvent script with the event in the game's own shape (secret slots nil; UNIT_AURA's
+-- payload the layer's own full update). COMBAT_LOG_EVENT_UNFILTERED is never registered with the client.
+-- Credits: the Plain gate on every payload slot follows Catnip's (Durts) secret-value research.
+
+local _, ns = ...
+local VS, I = ns.VirtualState, ns.VirtualStateInternal
+local S = I.Sources
+local Plain = S.Plain
+local _G = _G
+
+local E = {}
+I.Events = E
+
+-- The client table: `_G` in game; a spec sets `_G.CreateFrame` (and `_G.issecretvalue`) to its fake before loading.
+local client = _G
+local realCreateFrame = client.CreateFrame
+
+-- Events the client never sees: COMBAT_LOG_EVENT_UNFILTERED is the layer's own log (spec §2.2; registering it on an
+-- addon frame is forbidden on Forever), FRAME_UPDATE is Hekili's OnUpdate.
+local NEVER = { COMBAT_LOG_EVENT_UNFILTERED = true, FRAME_UPDATE = true }
+
+-- UNIT_AURA's payload for the units VirtualState believes (spec §2.5): always a full update, preallocated. Other units
+-- get nil (their table has secret fields in combat and the layer has no beliefs for them).
+local AURA_INFO = { player = { isFullUpdate = true }, target = { isFullUpdate = true } }
+
+-- Subscriptions by event: parallel arrays, `false` in `f` for a removed one (reused by the next subscription).
+local SUB = {}
+E.STUB = {} -- events the client refused at registration: never delivered
+E.delivered, E.errors, E.lastError = 0, 0, nil
+
+E.frame = nil
+
+-- The client registration for `e`: the union of the sources' units (once Start has set I.api) and the subscribers'.
+-- One or two units register per unit, anything more or a general subscriber registers the event. Not recurring.
+local any, general, un1, un2
+local function add(u)
+    any = true
+    if u == nil then
+        general = true
+    elseif u ~= un1 and u ~= un2 then
+        if un1 == nil then
+            un1 = u
+        elseif un2 == nil then
+            un2 = u
+        else
+            general = true
+        end
+    end
+end
+
+local function sync(e)
+    local frame = E.frame
+    if NEVER[e] or E.STUB[e] or not frame then
+        return
+    end
+    any, general, un1, un2 = false, false, nil, nil
+    if I.api and S.HANDLERS[e] then
+        local su = S.UNITS[e]
+        if su then
+            for k = 1, #su do
+                add(su[k])
+            end
+        else
+            add(nil)
+        end
+    end
+    local list = SUB[e]
+    if list then
+        for k = 1, list.n do
+            if list.f[k] then
+                add(list.u1[k])
+                if list.u2[k] then
+                    add(list.u2[k])
+                end
+            end
+        end
+    end
+    frame:UnregisterEvent(e)
+    if not any then
+        return
+    end
+    local ok
+    if general then
+        ok = pcall(frame.RegisterEvent, frame, e)
+    else
+        ok = pcall(frame.RegisterUnitEvent, frame, e, un1, un2)
+    end
+    if not ok then
+        E.STUB[e] = true
+    end
+end
+
+--- Subscribes `frame` to `e` (for one or two units, or every unit). Load time and rare runtime registrations only.
+function E.Subscribe(frame, e, u1, u2)
+    local list = SUB[e]
+    if not list then
+        list = { n = 0, f = {}, u1 = {}, u2 = {} }
+        SUB[e] = list
+    end
+    local free
+    for k = 1, list.n do
+        local f = list.f[k]
+        if f == frame then
+            free = k
+            break
+        elseif not f and not free then
+            free = k
+        end
+    end
+    if not free then
+        free = list.n + 1
+        list.n = free
+    end
+    list.f[free], list.u1[free], list.u2[free] = frame, u1, u2
+    sync(e)
+    return not E.STUB[e]
+end
+
+--- Ends `frame`'s subscription to `e`; the client registration drops what no one needs any more.
+function E.Unsubscribe(frame, e)
+    local list = SUB[e]
+    if not list then
+        return
+    end
+    local changed = false
+    for k = 1, list.n do
+        if list.f[k] == frame then
+            list.f[k], list.u1[k], list.u2[k] = false, nil, nil
+            changed = true
+        end
+    end
+    if changed then -- UnregisterAllEvents walks every event: only the ones this frame had touch the client
+        sync(e)
+    end
+end
+
+function E.IsSubscribed(frame, e)
+    local list = SUB[e]
+    if list then
+        for k = 1, list.n do
+            if list.f[k] == frame then
+                return true
+            end
+        end
+    end
+    return false
+end
+
+-- The event methods every facade frame gets: shared functions, no closure per frame.
+local function register(self, e)
+    return E.Subscribe(self, e)
+end
+local function registerUnit(self, e, u1, u2)
+    return E.Subscribe(self, e, u1, u2)
+end
+local function unregister(self, e)
+    E.Unsubscribe(self, e)
+end
+local function unregisterAll(self)
+    for e in pairs(SUB) do
+        E.Unsubscribe(self, e)
+    end
+end
+local function isRegistered(self, e)
+    return E.IsSubscribed(self, e)
+end
+
+--- Facade.CreateFrame: the client's frame with its event methods shadowed by the layer's (spec §2.1).
+function E.CreateFrame(...)
+    local f = realCreateFrame(...)
+    f.RegisterEvent, f.RegisterUnitEvent, f.UnregisterEvent = register, registerUnit, unregister
+    f.UnregisterAllEvents, f.IsEventRegistered = unregisterAll, isRegistered
+    return f
+end
+
+-- One client event: (1) the sources (once Start has run), (2) the payload, (3) every matching subscriber in
+-- subscription order, through its current OnEvent script. Each slot is gated into a local, so a nested client event
+-- is delivered in its own call with its own values. Allocates nothing.
+local function onEvent(_, event, r1, r2, r3, r4, r5, r6, r7, r8)
+    local api = I.api or client
+    local a1, a2, a3, a4 = Plain(api, r1), Plain(api, r2), Plain(api, r3), Plain(api, r4)
+    local a5, a6, a7, a8 = Plain(api, r5), Plain(api, r6), Plain(api, r7), Plain(api, r8)
+    if I.api then
+        S.Run(api, event, a1, a2, a3, a4, a5)
+    end
+    local list = SUB[event]
+    if not list then
+        return
+    end
+    if event == "UNIT_AURA" then
+        a2 = AURA_INFO[a1]
+    end
+    for k = 1, list.n do -- a subscription made during this delivery starts with the next event
+        local f = list.f[k]
+        if f then
+            local u = list.u1[k]
+            if u == nil or u == a1 or list.u2[k] == a1 then
+                local fn = f:GetScript("OnEvent")
+                if fn then
+                    E.delivered = E.delivered + 1
+                    local ok, err = pcall(fn, f, event, a1, a2, a3, a4, a5, a6, a7, a8)
+                    if not ok then
+                        E.errors, E.lastError = E.errors + 1, err
+                        local handler = client.geterrorhandler
+                        if handler then
+                            handler()(err)
+                        end
+                    end
+                end
+            end
+        end
+    end
+end
+
+local function onUpdate()
+    S.Flush()
+end
+
+local function makeFrame(createFrame)
+    local frame = createFrame("Frame")
+    E.frame = frame
+    frame:SetScript("OnEvent", onEvent)
+    frame:SetScript("OnUpdate", onUpdate)
+    for e in pairs(SUB) do
+        sync(e)
+    end
+end
+
+-- In game the frame exists from load, so the events before login (VARIABLES_LOADED, PLAYER_LOGIN) reach Hekili.
+if realCreateFrame then
+    makeFrame(realCreateFrame)
+end
+
+--- VirtualState.Start's half: the frame (from `api` when the client had none at load: a headless spec), then the
+--- sources' registrations added to it. Once.
+function E.Attach(api)
+    if not E.frame then
+        realCreateFrame = realCreateFrame or api.CreateFrame
+        makeFrame(api.CreateFrame)
+    end
+    for e in pairs(S.HANDLERS) do
+        sync(e)
+    end
+end
+
+--- Snapshot's lines: delivery counts, handler errors, refused events. Allocates (debugging only).
+I.OnSnapshot(function(out)
+    local stubs = {}
+    for e in pairs(E.STUB) do
+        stubs[#stubs + 1] = e
+    end
+    table.sort(stubs)
+    out[#out + 1] = string.format(
+        "events delivered=%d errors=%d stubs=[%s]%s",
+        E.delivered,
+        E.errors,
+        table.concat(stubs, " "),
+        E.lastError and (" last error=" .. tostring(E.lastError)) or ""
+    )
+end)
diff --git a/VirtualState/Sources/Sources.lua b/VirtualState/Sources/Sources.lua
index 59e30b29..a23b43f3 100644
--- a/VirtualState/Sources/Sources.lua
+++ b/VirtualState/Sources/Sources.lua
@@ -1,7 +1,7 @@
 -- VirtualState/Sources/Sources.lua
 -- Sources (spec §4): the only VirtualState code that touches the game, and only through the injected `api` (`_G` in
 -- game, a fake in tests). This file: the `Plain` secrecy gate, staging and the per-frame Flush, the polls, the event
--- registry and the module's own frame (VirtualState.Start).
+-- registry and VirtualState.Start (the frame is the event facade's, VirtualState/EventFacade.lua).
 -- Credits: the `Plain` gate and the issecretvalue/pcall handling follow Catnip's (Durts) secret-value research.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Sources.lua (Plain :42-46, STAGE :52, Stage :540, Flush
 -- :552-561, the poll loop :564-588 with Sources.Poll at :576).
@@ -111,8 +111,10 @@ function S.RunPolls(t)
     end
 end
 
--- The event registry: event -> handlers, and event -> the units it is registered for (unit events).
+-- The event registry: event -> handlers, and event -> the units it is registered for (unit events). The event facade
+-- registers them with the client at Start.
 local HANDLERS, UNITS = {}, {}
+S.HANDLERS, S.UNITS = HANDLERS, UNITS
 
 --- Registers `fn(api, t, a1, a2, a3, a4, a5)` for `event`; `unit` ("player" or "target") makes it a unit event
 --- for that unit (the handler still checks a1). Every argument reaches the handler through Plain. Load time only.
@@ -149,44 +151,24 @@ function S.Urgent(event)
     end
 end
 
-function S:OnEvent(event, r1, r2, r3, r4, r5)
-    local api = I.api
+--- Runs the sources for one client event. The event facade has already passed every slot through Plain.
+function S.Run(api, event, a1, a2, a3, a4, a5)
     local list = HANDLERS[event]
     if not list then
         return
     end
     local t = api.GetTime()
-    local a1, a2, a3, a4, a5 = Plain(api, r1), Plain(api, r2), Plain(api, r3), Plain(api, r4), Plain(api, r5)
     for k = 1, #list do
         list[k](api, t, a1, a2, a3, a4, a5)
     end
 end
 
-local function onEvent(_, event, r1, r2, r3, r4, r5)
-    S:OnEvent(event, r1, r2, r3, r4, r5)
-end
-
-local function onUpdate()
-    S.Flush()
-end
-
---- Once, at PLAYER_LOGIN: `api` is `_G` in game and a fake in tests. Creates the module's frame, registers the source
---- events (spec §4.2) and starts the per-frame flush. Allocates; once.
+--- Once, at PLAYER_LOGIN: `api` is `_G` in game and a fake in tests. Adds the source events (spec §4.2) to the event
+--- facade's frame, which also runs the per-frame flush. Allocates; once.
 ---@param api table
 function VS.Start(api)
     I.api = api
-    local frame = api.CreateFrame("Frame")
-    S.frame = frame
-    for event in pairs(HANDLERS) do
-        local u = UNITS[event]
-        if u then
-            frame:RegisterUnitEvent(event, u[1], u[2])
-        else
-            frame:RegisterEvent(event)
-        end
-    end
-    frame:SetScript("OnEvent", onEvent)
-    frame:SetScript("OnUpdate", onUpdate)
+    I.Events.Attach(api)
     local t = api.GetTime()
     for k = 1, #STARTS do
         -- one raising hook (a client without some API) must not stop the hooks after it
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `151 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [151 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 67 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct secret or absent game API read in 44 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/EventFacade.lua VirtualState/Sources/Sources.lua Hekili.toc VirtualState/spec/event_facade_spec.lua VirtualState/spec/helpers/fake_api.lua
git commit -m "feat(virtualstate): the event facade: one client frame from load, per-subscriber unit filters, gated payloads, UNIT_AURA's full update, the combat log never registered

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 2: The read facade in three classes, and Hekili on it (file-top locals, CreateFrame, the tools)

Phase A, spec §1, decisions 1, 4 and 8. `VirtualState/Facade.lua` grows from the 51 kept names to every name Hekili reads: the 124 former passthroughs (from `docs/forever-facade-notes.md`, their secrecy column verbatim as the reason) through `passthrough(name, reason)` (the raw function; a name the client lacks becomes a virtual row answering nothing, which retires the files' `X or function() end` shims); 24 Phase 1 rows become `hybrid` (the raw call; any secret among the first four values, or a cooldown or charge table's secret or non-numeric times, hands over to the Phase 1 policy; `C_Spell.GetSpellCharges` answers a plain nil, "not a charge spell", as the client does, after testing it with `issecretvalue`): the 12 stats, `GetHaste`, `GetMeleeHaste`, `UnitSpellHaste`, `UnitAttackSpeed`, `GetUnitSpeed`, `GetTotemInfo`, `GetPowerRegenForPowerType`, `GetManaRegen`, `C_Spell.GetSpellCooldown`, `C_Spell.GetSpellCharges`, and `UnitCastingInfo`/`UnitChannelInfo` (player raw, target modelled); the rest are `virtual` (Phase 1's 17 stubs included); `IsUsableSpell` is a passthrough of `C_Spell.IsSpellUsable`; `CreateFrame` is the event facade's (virtual). `Facade.Stubs()` goes with the stub status. `tools/api_inventory.txt` lists all 176 names as `Name<TAB>class` (125 passthrough, 24 hybrid, 27 virtual).

Every Hekili file then reads the game only through the facade: each pure alias line at a file's top (`local A, B = A, B`, shims included) points at `Facade.X`, and a file without one gains `local Facade = ns.Facade` after `local addon, ns = ...` (the script below produced this part of the patch, `Forever/Warrior.lua`'s two alias lines included: do not run it in this task, the patch already contains its output); the files that make frames gain `local CreateFrame = Facade.CreateFrame` (`Formatting.lua`: `ns.Facade.CreateFrame`); `State.lua`, at the 200-locals cap, reads its 14 remaining bare names inline as `Facade.Name`; `VirtualState/Adapter.lua` takes `GetTime` and its boot frame's `CreateFrame` from the facade (so `PLAYER_LOGIN` reaches it through the layer, and no loaded file is exempt). `.luacheckrc` drops the plain game reads and `CreateFrame` from `read_globals`; `tools/check_api_reads.sh` returns to "no inventory name is read directly" over every name (W113 on the namespace or bare global, the `_G.Name` grep, and a grep for a frame method reached through `getmetatable`).

The templates `Facade.CreateFrame` now also creates were checked in the client's FrameXML (spec §2.1): `GameTooltipTemplate` (its OnLoad registers `TOOLTIP_DATA_UPDATE` on the client for Blizzard's own script), `UIPanelButtonTemplate`, `BackdropTemplate`, `UIDropDownMenuTemplate`, `CooldownFrameTemplate`, `HekiliPopupDropdownRangeTemplate`: none registers an event Hekili handles.

The Warrior's spec loader (`Forever/spec/helpers/load_warrior.lua`) gives the class file's `ns` its fakes table as `Facade`, so the file's facade locals resolve headless.

The script that rewrote the alias lines, for reference (a later class file runs it the same way), saved as `/tmp/facade_locals.lua` (the script appends a final newline; the replay removed it again from the three files that had none, `Options/ChatCommands.lua`, `Options/DevTools.lua`, `Utils.lua`, so the patch changes no file's ending):

```lua
-- One-off: point every pure alias line `local A, B = A, B` of a Hekili file at ns.Facade for inventory names, and
-- add `local Facade = ns.Facade` after `local addon, ns = ...` where the file has none.
-- Usage: lua facade_locals.lua tools/api_inventory.txt file...
local inv = {}
for line in io.lines(arg[1]) do
    local name = line:match("^(%S+)")
    if name then
        inv[name:match("^([%w_]+)")] = true
    end
end
for i = 2, #arg do
    local path = arg[i]
    local out, changed = {}, 0
    for line in io.lines(path) do
        local lhs, rhs = line:match("^(local%s+[%w_,%s]+=%s*)(.-)%s*$")
        if lhs then
            local items, pure = {}, true
            for item in (rhs .. ","):gmatch("%s*(.-)%s*,") do
                local bare = item:match("^([%w_]+) or function%(%) end$") or item:match("^([%w_]+)$")
                if bare and inv[bare] then
                    items[#items + 1] = "Facade." .. bare
                elseif item:match("^Facade%.[%w_]+$") or (bare and not inv[bare]) then
                    items[#items + 1] = item
                else
                    pure = false
                    break
                end
            end
            local new = pure and lhs .. table.concat(items, ", ")
            if new and new ~= line then
                line, changed = new, changed + 1
            end
        end
        out[#out + 1] = line
    end
    if changed > 0 then
        local has = false
        for k = 1, #out do
            has = has or out[k]:match("^local Facade = ns%.Facade") ~= nil
        end
        for k = 1, #out do
            if not has and out[k]:match("^local [%w_]+, ns = %.%.%.") then
                table.insert(out, k + 1, "local Facade = ns.Facade")
                break
            end
        end
        local f = assert(io.open(path, "w"))
        f:write(table.concat(out, "\n"), "\n")
        f:close()
        print(path .. ": " .. changed .. " lines")
    end
end
```

**Files:**
- Modify: `VirtualState/Facade.lua` (header :2-5; after the resolved reals :63; the rows' classes throughout; the frames and passthrough sections before `table.sort(inventory)` :509; `Stubs` :523-525), `tools/api_inventory.txt` (all names with classes), `tools/check_api_reads.sh` (whole file), `.luacheckrc` (header :1-3; `read_globals` :50-77), `VirtualState/Adapter.lua` (:17), `Classes.lua`, `Constants.lua`, `Core.lua`, `Events.lua`, `Forever/Warrior.lua`, `Formatting.lua`, `Hekili.lua`, `MultilineEditor.lua`, `Options/ChatCommands.lua`, `Options/DevTools.lua`, `Options/Options.lua`, `State.lua`, `Targets.lua`, `UI.lua`, `Utils.lua` (file-top locals; `State.lua` also its 14 inline reads), `VirtualState/EventFacade.lua` (one comment)
- Test: `Forever/spec/helpers/load_warrior.lua` (`ns.Facade = fakes`), `VirtualState/spec/facade_spec.lua` (inventory with classes; virtual rows never call the game; passthrough transparency; hybrid raw then model; an absent passthrough), `VirtualState/spec/alloc_spec.lua` (passthrough reads in the loop)

**Interfaces:**
- Consumes: `I.Events.CreateFrame` (Task 1).
- Produces: `Facade.Status(name)` → `"passthrough" | "hybrid" | "virtual"`; `Facade.<every inventory name>`; `tools/api_inventory.txt` as `Name<TAB>class` lines; `Facade.Stubs` removed.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/spec/helpers/load_warrior.lua b/Forever/spec/helpers/load_warrior.lua
index ff6ee1f0..2cda0b06 100644
--- a/Forever/spec/helpers/load_warrior.lua
+++ b/Forever/spec/helpers/load_warrior.lua
@@ -68,6 +68,7 @@ function M.load()
         _G[k] = v
     end
     local ns = {
+        Facade = fakes, -- the class file reads the game through ns.Facade (event-facade spec §1.2)
         VirtualState = {
             Track = function(t)
                 for k, v in pairs(t.talents or {}) do
diff --git a/VirtualState/spec/alloc_spec.lua b/VirtualState/spec/alloc_spec.lua
index 73de2eec..99176104 100644
--- a/VirtualState/spec/alloc_spec.lua
+++ b/VirtualState/spec/alloc_spec.lua
@@ -1,6 +1,6 @@
 -- VirtualState/spec/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
 -- usability, own casts, UNIT_AURA) with a drain every tick against the fake spec, every accessor and every facade
--- policy called: VirtualState allocates nothing.
+-- policy and passthrough called: VirtualState allocates nothing.
 local load = require("VirtualState.spec.helpers.load")
 local fake = require("VirtualState.spec.helpers.fake_api")
 local fs = require("VirtualState.spec.helpers.fake_spec")
@@ -128,6 +128,9 @@ describe("zero allocation", function()
             Facade.UnitCastingInfo("target")
             Facade.UnitChannelInfo("target")
             Facade.IsUsableSpell(fs.REND)
+            Facade.GetTime() -- passthroughs
+            Facade.UnitGUID("target")
+            Facade.GetInstanceInfo() -- absent here: virtual, answers nothing
         end
         local ok, bytes = pcall(alloc.bytes, step, 10000)
         for k, v in pairs(saved) do
diff --git a/VirtualState/spec/facade_spec.lua b/VirtualState/spec/facade_spec.lua
index af27ae5a..96ac1504 100644
--- a/VirtualState/spec/facade_spec.lua
+++ b/VirtualState/spec/facade_spec.lua
@@ -1,5 +1,6 @@
--- VirtualState/spec/facade_spec.lua: ns.Facade (spec §7): the inventory equals tools/api_inventory.txt, every kept
--- name answers in its real shape, the stubs never call the game, and the GCD numbers are bit-identical.
+-- VirtualState/spec/facade_spec.lua: ns.Facade (spec §7; event-facade spec §1.1): the inventory and each name's class
+-- equal tools/api_inventory.txt, every name answers in its real shape, a virtual row never calls the game, a
+-- passthrough is transparent, a hybrid answers the raw value unless it is secret, and the GCD numbers are bit-identical.
 -- The inventory and shape cases move here from Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua.
 local load = require("VirtualState.spec.helpers.load")
 local fake = require("VirtualState.spec.helpers.fake_api")
@@ -7,15 +8,17 @@ local fs = require("VirtualState.spec.helpers.fake_spec")
 
 local INVENTORY = "tools/api_inventory.txt"
 
+-- The inventory's names in order and their classes ("Name<TAB>class" lines).
 local function readInventory()
-    local names = {}
+    local names, classes = {}, {}
     for line in io.lines(INVENTORY) do
-        line = line:gsub("%s+$", "")
-        if line ~= "" and not line:match("^#") then
-            names[#names + 1] = line
+        local name, class = line:match("^(%S+)\t(%a+)%s*$")
+        if name then
+            names[#names + 1] = name
+            classes[name] = class
         end
     end
-    return names
+    return names, classes
 end
 
 -- The real functions Facade.lua resolves at load, from the fake client; `calls` records any call of a kept name.
@@ -29,10 +32,11 @@ local RESOLVED = {
     "C_Spell.GetSpellInfo",
     "UnitCastingInfo",
     "UnitChannelInfo",
+    "CreateFrame",
 }
 
 describe("ns.Facade", function()
-    local names, ns, Facade, VS, I, api, ctl, calls, saved, powerType
+    local names, classes, ns, Facade, VS, I, api, ctl, calls, saved, powerType, answers
 
     local function entry(name)
         local nsName, key = name:match("^([%w_]+)%.([%w_]+)$")
@@ -43,7 +47,7 @@ describe("ns.Facade", function()
     end
 
     setup(function()
-        names = readInventory()
+        names, classes = readInventory()
     end)
 
     before_each(function()
@@ -56,13 +60,19 @@ describe("ns.Facade", function()
         api.C_Spell.GetSpellInfo = function(id)
             return { name = "Spell " .. id, iconID = 1 }
         end
-        calls = {}
+        calls, answers = {}, {}
         saved = {}
-        -- every kept name in _G records a call; the resolved reals answer from the fake client
+        -- every name in _G records a call and answers as the client does in combat (secret) unless `answers` names
+        -- a plain answer; the resolved reals answer from the fake client
         for _, n in ipairs(names) do
             local nsName, key = n:match("^([%w_]+)%.([%w_]+)$")
-            local f = function()
+            local f = function(...)
                 calls[#calls + 1] = n
+                local a = answers[n]
+                if a then
+                    return a(...)
+                end
+                return fake.SECRET
             end
             if nsName then
                 saved[nsName] = saved[nsName] or rawget(_G, nsName) or false
@@ -96,24 +106,27 @@ describe("ns.Facade", function()
         end
     end)
 
-    it("keeps exactly the inventory's names, each with a status, a reason and a function", function()
+    it("keeps exactly the inventory's names, each with its class, a reason and a function", function()
         assert.are.same(names, Facade.Inventory())
+        local count = { passthrough = 0, hybrid = 0, virtual = 0 }
         for _, n in ipairs(names) do
-            local s = Facade.Status(n)
-            assert.is_true(s == "virtual" or s == "stub", n .. " status is " .. tostring(s))
+            local c = Facade.Status(n)
+            assert.are.equal(classes[n], c, n)
+            count[c] = count[c] + 1
             assert.is_function(entry(n), n)
             assert.is_string(Facade.Why(n), n)
         end
-        assert.are.equal(51, #names)
-        assert.are.equal(17, #Facade.Stubs())
-        assert.is_nil(Facade.Status("UnitExists"))
+        assert.are.same({ passthrough = 125, hybrid = 24, virtual = 27 }, count)
+        assert.is_nil(Facade.Status("NotAGameFunction"))
     end)
 
-    it("never calls the game from a stub (absent names never reach _G)", function()
-        for _, n in ipairs(Facade.Stubs()) do
-            assert.has_no.errors(function()
-                entry(n)("target", 1)
-            end, n)
+    it("never calls the game for a virtual row's answer", function()
+        for _, n in ipairs(names) do
+            if classes[n] == "virtual" and n ~= "CreateFrame" then
+                assert.has_no.errors(function()
+                    entry(n)("target", 1)
+                end, n)
+            end
         end
         assert.are.same({}, calls)
         assert.are.same({ false, true }, { Facade.UnitInRange("party1") })
@@ -255,6 +268,46 @@ describe("ns.Facade", function()
         assert.are.equal(0, Facade.UnitSpellHaste("target"))
     end)
 
+    it("passes a passthrough's arguments and every result through unchanged", function()
+        local got
+        answers.GetInstanceInfo = function(...)
+            got = { ... }
+            return "Map", "party", 1, "Normal", 5, 0, false, 33, 5
+        end
+        assert.are.same({ "Map", "party", 1, "Normal", 5, 0, false, 33, 5 }, { Facade.GetInstanceInfo("x", 2) })
+        assert.are.same({ "x", 2 }, got)
+        assert.are.equal(9, select("#", Facade.GetInstanceInfo()))
+        assert.are.equal(fake.SECRET, Facade.UnitName("target")) -- transparent: a secret is the trace's to count
+    end)
+
+    it("answers a hybrid's raw value while it is plain and the policy's once it is secret", function()
+        answers.GetHaste = function()
+            return 12.5
+        end
+        assert.are.equal(12.5, Facade.GetHaste())
+        answers.GetHaste = nil
+        assert.are.equal(0, Facade.GetHaste()) -- secret: Haste()
+        answers.UnitAttackSpeed = function(unit)
+            return unit == "target" and 2.4 or nil
+        end
+        assert.are.equal(2.4, Facade.UnitAttackSpeed("target"))
+        ctl.cooldown[fs.REND] = { startTime = 5, duration = 10, isActive = true, isOnGCD = false }
+        assert.are.equal(ctl.cooldown[fs.REND], Facade.C_Spell.GetSpellCooldown(fs.REND)) -- plain times: the client's
+        answers["C_Spell.GetSpellCharges"] = function()
+            return nil -- not a charge spell
+        end
+        assert.is_nil(Facade.C_Spell.GetSpellCharges(fs.REND))
+    end)
+
+    it("makes a passthrough the client lacks a virtual row answering nothing", function()
+        local was = _G.HasOverrideActionBar
+        _G.HasOverrideActionBar = nil
+        local ns2 = load.module()
+        _G.HasOverrideActionBar = was
+        assert.are.equal("virtual", ns2.Facade.Status("HasOverrideActionBar"))
+        assert.are.equal(0, select("#", ns2.Facade.HasOverrideActionBar()))
+    end)
+
     it("aliases IsUsableSpell to C_Spell.IsSpellUsable", function()
         ctl.usable[5] = { true, false }
         assert.is_true(Facade.IsUsableSpell(5))
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `138 successes / 1 failure / 15 errors`: every `facade_spec` case errors in its setup (`facade_spec.lua:89: attempt to index field '?' (a nil value)`: a namespace the inventory now names has no facade table yet), and `alloc_spec` fails (`attempt to call field 'GetTime' (a nil value)`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/.luacheckrc b/.luacheckrc
index e513f8f7..ceeecb20 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -1,6 +1,6 @@
--- Lint for the Forever branch. Every secret or absent game read goes through ns.Facade (VirtualState/Facade.lua; see
--- tools/check_api_reads.sh): those names (tools/api_inventory.txt) are deliberately NOT declared here, so a bare read
--- shows up as W113 "accessing undefined variable". The plain game reads are declared in read_globals below.
+-- Lint for the Forever branch. Every game read goes through ns.Facade (VirtualState/Facade.lua; see
+-- tools/check_api_reads.sh): the names of tools/api_inventory.txt, CreateFrame among them, are deliberately NOT
+-- declared here, so a bare read shows up as W113 "accessing undefined variable".
 std = "lua51"
 max_line_length = false
 codes = true
@@ -41,7 +41,7 @@ globals = {
 -- The facade covers game-STATE READS only. Deliberately declared here because they are outside it: writes (SetCVar,
 -- SetOverrideBindingClick, ClearOverrideBindings, ClearCursor, Screenshot), timers (C_Timer), secure hooks
 -- (hooksecurefunc), profiling (debugprofilestop), secrecy predicates (issecretvalue, issecrettable, C_Secrets), and
--- UI construction (CreateFrame, UIParent), which is not a read.
+-- UI widgets that read no game state (UIParent, GameTooltip). CreateFrame is the event facade's (Facade.CreateFrame).
 read_globals = {
     -- Lua extensions provided by the client
     "wipe", "format", "strupper", "strlower", "strfind", "strsub", "strlen", "strsplit", "strjoin", "strtrim",
@@ -51,7 +51,7 @@ read_globals = {
     -- libraries and other addons
     "LibStub", "WeakAuras", "ElvUI", "ConsolePort", "SpellFlashCore", "Masque",
     -- FrameXML (Lua-defined UI utilities, not reads)
-    "CreateFrame", "UIParent", "GameTooltip", "GameTooltip_SetTitle", "GameTooltip_AddNormalLine",
+    "UIParent", "GameTooltip", "GameTooltip_SetTitle", "GameTooltip_AddNormalLine",
     "GetAppropriateTooltip", "UIDropDownMenu_SetDisplayMode", "UIDropDownMenu_AddSeparator",
     "UIDropDownMenu_AddButton", "ToggleDropDownMenu", "UIFrameFadeOut", "PixelUtil", "PlayerUtil", "ExportUtil",
     "ClassTalentImportExportMixin", "Item", "ItemLocation", "Mixin", "hooksecurefunc", "CreateAtlasMarkup",
@@ -63,22 +63,6 @@ read_globals = {
     "PET_TYPE_DEMON", "BATTLE_PET_NAME_4", "COMBATLOG_OBJECT_REACTION_FRIENDLY",
     "CR_VERSATILITY_DAMAGE_TAKEN", "CR_VERSATILITY_DAMAGE_DONE", "CR_MASTERY", "CR_HASTE_MELEE",
     "CR_CRIT_TAKEN_SPELL", "CR_CRIT_MELEE",
-    -- plain game reads (spec §7.7): called directly; namespaces declared whole (their kept members are caught by
-    -- tools/check_api_reads.sh's dotted grep)
-    "AuraUtil", "C_AddOns", "C_ClassColor", "C_ClassTalents", "C_Item", "C_LossOfControl", "C_PetBattles",
-    "C_PlayerInfo", "C_PvP", "C_SpecializationInfo", "C_Spell", "C_SpellActivationOverlay", "C_SpellBook",
-    "C_Texture", "C_TooltipInfo", "C_Traits", "C_VideoOptions", "GetActionInfo", "GetBindingKey", "GetBuildInfo",
-    "GetCVar", "GetClassInfo", "GetCursorInfo", "GetFrameCPUUsage", "GetFramerate", "GetInstanceInfo",
-    "GetInventoryItemID", "GetNetStats", "GetNumClasses", "GetNumGroupMembers", "GetNumSubgroupMembers",
-    "GetRealmName", "GetShapeshiftForm", "GetShapeshiftFormInfo", "GetSpecializationInfoByID", "GetStablePetInfo",
-    "GetTime", "HasOverrideActionBar", "HasVehicleActionBar", "InCombatLockdown", "IsActionInRange", "IsInGroup",
-    "IsInInstance", "IsInJailersTower", "IsInRaid", "IsMounted", "IsPlayerSpell", "IsResting", "IsSpellKnown",
-    "IsSpellKnownOrOverridesKnown", "SecureCmdOptionParse", "SpellIsSelfBuff", "UnitAffectingCombat",
-    "UnitCanAssist", "UnitCanAttack", "UnitClass", "UnitClassBase", "UnitClassification", "UnitCreatureType",
-    "UnitEffectiveLevel", "UnitExists", "UnitFactionGroup", "UnitGUID", "UnitHasVehicleUI", "UnitInParty",
-    "UnitInRaid", "UnitInVehicle", "UnitIsConnected", "UnitIsDead", "UnitIsDeadOrGhost", "UnitIsFriend", "UnitIsPVP",
-    "UnitIsPlayer", "UnitIsTrivial", "UnitIsUnit", "UnitLevel", "UnitName", "UnitOnTaxi", "UnitPhaseReason",
-    "UnitPowerMax", "UnitPowerType", "UnitRace", "UnitSex", "UnitThreatSituation", "UnitTokenFromGUID",
     -- client additions to the Lua standard tables
     table = { fields = { "wipe", "unpack" } },
     string = { fields = { "trim" } },
diff --git a/Classes.lua b/Classes.lua
index f341fa76..3bd7a121 100644
--- a/Classes.lua
+++ b/Classes.lua
@@ -3,10 +3,10 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local C_Item, C_LossOfControl, C_SpecializationInfo, C_Spell = C_Item, C_LossOfControl, C_SpecializationInfo, C_Spell
-local GetSpecializationInfoByID, GetTime, InCombatLockdown, UnitAttackSpeed = GetSpecializationInfoByID, GetTime, InCombatLockdown, Facade.UnitAttackSpeed
-local UnitCanAttack, UnitCastingInfo, UnitChannelInfo, UnitClassBase = UnitCanAttack, Facade.UnitCastingInfo, Facade.UnitChannelInfo, UnitClassBase
-local UnitGUID, UnitGetTotalAbsorbs = UnitGUID, Facade.UnitGetTotalAbsorbs
+local C_Item, C_LossOfControl, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_LossOfControl, Facade.C_SpecializationInfo, Facade.C_Spell
+local GetSpecializationInfoByID, GetTime, InCombatLockdown, UnitAttackSpeed = Facade.GetSpecializationInfoByID, Facade.GetTime, Facade.InCombatLockdown, Facade.UnitAttackSpeed
+local UnitCanAttack, UnitCastingInfo, UnitChannelInfo, UnitClassBase = Facade.UnitCanAttack, Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClassBase
+local UnitGUID, UnitGetTotalAbsorbs = Facade.UnitGUID, Facade.UnitGetTotalAbsorbs
 local Hekili = _G[ addon ]
 
 local class = Hekili.Class
diff --git a/Constants.lua b/Constants.lua
index 9bfbe6cd..cf63c83d 100644
--- a/Constants.lua
+++ b/Constants.lua
@@ -2,8 +2,9 @@
 -- June 2014
 
 local addon, ns = ...
-local C_SpecializationInfo = C_SpecializationInfo
-local GetClassInfo, GetNumClasses, UnitSex = GetClassInfo, GetNumClasses, UnitSex
+local Facade = ns.Facade
+local C_SpecializationInfo = Facade.C_SpecializationInfo
+local GetClassInfo, GetNumClasses, UnitSex = Facade.GetClassInfo, Facade.GetNumClasses, Facade.UnitSex
 local Hekili = _G[ addon ]
 
 local GetSpecialization = C_SpecializationInfo.GetSpecialization
diff --git a/Core.lua b/Core.lua
index 3ad6eed5..033d2f3d 100644
--- a/Core.lua
+++ b/Core.lua
@@ -2,7 +2,9 @@
 -- April 2014
 
 local addon, ns = ...
-local GetFrameCPUUsage, GetTime, InCombatLockdown = GetFrameCPUUsage, GetTime, InCombatLockdown
+local Facade = ns.Facade
+local CreateFrame = Facade.CreateFrame
+local GetFrameCPUUsage, GetTime, InCombatLockdown = Facade.GetFrameCPUUsage, Facade.GetTime, Facade.InCombatLockdown
 local Hekili = _G[ addon ]
 
 local class = Hekili.Class
diff --git a/Events.lua b/Events.lua
index 96e46f21..9830f470 100644
--- a/Events.lua
+++ b/Events.lua
@@ -3,15 +3,16 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local AuraUtil, C_AddOns = AuraUtil, C_AddOns
-local C_Item, C_SpecializationInfo, C_Spell, C_UnitAuras = C_Item, C_SpecializationInfo, C_Spell, Facade.C_UnitAuras
-local CombatLogGetCurrentEventInfo, GetActionInfo, GetBindingKey, GetInstanceInfo = Facade.CombatLogGetCurrentEventInfo, GetActionInfo, GetBindingKey, GetInstanceInfo
-local GetInventoryItemID, GetTalentInfoByID, GetTime = GetInventoryItemID, Facade.GetTalentInfoByID, GetTime
-local InCombatLockdown, IsInGroup = InCombatLockdown, IsInGroup
-local IsPlayerSpell, IsResting, SecureCmdOptionParse = IsPlayerSpell or function() end, IsResting, SecureCmdOptionParse
-local SpellIsSelfBuff, UnitAttackSpeed, UnitCastingInfo, UnitChannelInfo = SpellIsSelfBuff or function() end, Facade.UnitAttackSpeed, Facade.UnitCastingInfo, Facade.UnitChannelInfo
-local UnitClass, UnitExists, UnitGUID, UnitInParty = UnitClass, UnitExists, UnitGUID, UnitInParty
-local UnitInRaid, UnitIsPlayer, UnitLevel, UnitName = UnitInRaid, UnitIsPlayer, UnitLevel, UnitName
+local CreateFrame = Facade.CreateFrame
+local AuraUtil, C_AddOns = Facade.AuraUtil, Facade.C_AddOns
+local C_Item, C_SpecializationInfo, C_Spell, C_UnitAuras = Facade.C_Item, Facade.C_SpecializationInfo, Facade.C_Spell, Facade.C_UnitAuras
+local CombatLogGetCurrentEventInfo, GetActionInfo, GetBindingKey, GetInstanceInfo = Facade.CombatLogGetCurrentEventInfo, Facade.GetActionInfo, Facade.GetBindingKey, Facade.GetInstanceInfo
+local GetInventoryItemID, GetTalentInfoByID, GetTime = Facade.GetInventoryItemID, Facade.GetTalentInfoByID, Facade.GetTime
+local InCombatLockdown, IsInGroup = Facade.InCombatLockdown, Facade.IsInGroup
+local IsPlayerSpell, IsResting, SecureCmdOptionParse = Facade.IsPlayerSpell, Facade.IsResting, Facade.SecureCmdOptionParse
+local SpellIsSelfBuff, UnitAttackSpeed, UnitCastingInfo, UnitChannelInfo = Facade.SpellIsSelfBuff, Facade.UnitAttackSpeed, Facade.UnitCastingInfo, Facade.UnitChannelInfo
+local UnitClass, UnitExists, UnitGUID, UnitInParty = Facade.UnitClass, Facade.UnitExists, Facade.UnitGUID, Facade.UnitInParty
+local UnitInRaid, UnitIsPlayer, UnitLevel, UnitName = Facade.UnitInRaid, Facade.UnitIsPlayer, Facade.UnitLevel, Facade.UnitName
 local UnitPower = Facade.UnitPower
 local Hekili = _G[ addon ]
 
diff --git a/Forever/Warrior.lua b/Forever/Warrior.lua
index 09d9f952..ff407b70 100644
--- a/Forever/Warrior.lua
+++ b/Forever/Warrior.lua
@@ -16,8 +16,9 @@
 -- (src/TacoDogForever_Warrior/Warrior.lua:21-24).
 
 local addon, ns = ...
-local C_SpellBook, C_Spell, UnitClassBase = C_SpellBook, C_Spell, UnitClassBase
-local GetShapeshiftForm, GetShapeshiftFormInfo = GetShapeshiftForm, GetShapeshiftFormInfo
+local Facade = ns.Facade
+local C_SpellBook, C_Spell, UnitClassBase = Facade.C_SpellBook, Facade.C_Spell, Facade.UnitClassBase
+local GetShapeshiftForm, GetShapeshiftFormInfo = Facade.GetShapeshiftForm, Facade.GetShapeshiftFormInfo
 local Hekili = _G[ addon ]
 
 if UnitClassBase( "player" ) ~= "WARRIOR" then return end
diff --git a/Formatting.lua b/Formatting.lua
index 887b46f7..3ebcfba8 100644
--- a/Formatting.lua
+++ b/Formatting.lua
@@ -2,6 +2,7 @@
 -- Modified from For all Indents and Purposes, info below.
 
 local addon, ns = ...
+local CreateFrame = ns.Facade.CreateFrame
 local Hekili = _G[ addon ]
 
 --[[ For all Indents and Purposes
diff --git a/Hekili.lua b/Hekili.lua
index 13e17f7e..92a86514 100644
--- a/Hekili.lua
+++ b/Hekili.lua
@@ -3,8 +3,9 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local AuraUtil, C_AddOns, C_UnitAuras = AuraUtil, C_AddOns, Facade.C_UnitAuras
-local GetBuildInfo, GetFramerate, GetTime = GetBuildInfo, GetFramerate, GetTime
+local CreateFrame = Facade.CreateFrame
+local AuraUtil, C_AddOns, C_UnitAuras = Facade.AuraUtil, Facade.C_AddOns, Facade.C_UnitAuras
+local GetBuildInfo, GetFramerate, GetTime = Facade.GetBuildInfo, Facade.GetFramerate, Facade.GetTime
 Hekili = LibStub("AceAddon-3.0"):NewAddon( "Hekili", "AceConsole-3.0", "AceSerializer-3.0" )
 Hekili.Version = C_AddOns.GetAddOnMetadata( "Hekili", "Version" )
 Hekili.Flavor = C_AddOns.GetAddOnMetadata( "Hekili", "X-Flavor" ) or "Retail"
diff --git a/MultilineEditor.lua b/MultilineEditor.lua
index e4e163ac..319466be 100644
--- a/MultilineEditor.lua
+++ b/MultilineEditor.lua
@@ -2,7 +2,8 @@
 -- Revised MultiLineEditBox, to allow for my own tweaks.
 
 local addon, ns = ...
-local GetCursorInfo = GetCursorInfo
+local Facade = ns.Facade
+local GetCursorInfo = Facade.GetCursorInfo
 local Hekili = _G[ addon ]
 
 local Type, Version = "HekiliCustomEditor", 6
@@ -14,7 +15,7 @@ local pairs = pairs
 
 -- WoW APIs
 local GetCursorInfo, GetSpellInfo, ClearCursor = GetCursorInfo, ns.GetUnpackedSpellInfo, ClearCursor
-local CreateFrame, UIParent = CreateFrame, UIParent
+local CreateFrame, UIParent = Facade.CreateFrame, UIParent
 local _G = _G
 
 -- local utilities
diff --git a/Options/ChatCommands.lua b/Options/ChatCommands.lua
index b82d5b5d..bd971c53 100644
--- a/Options/ChatCommands.lua
+++ b/Options/ChatCommands.lua
@@ -2,7 +2,8 @@
 -- Handles /hekili CLI commands.
 
 local addon, ns = ...
-local InCombatLockdown = InCombatLockdown
+local Facade = ns.Facade
+local InCombatLockdown = Facade.InCombatLockdown
 local Hekili = _G[ addon ]
 
 local class = Hekili.Class
diff --git a/Options/DevTools.lua b/Options/DevTools.lua
index 9b305232..0a6f839a 100644
--- a/Options/DevTools.lua
+++ b/Options/DevTools.lua
@@ -3,11 +3,12 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local C_ClassTalents, C_SpecializationInfo, C_Spell, C_SpellActivationOverlay = C_ClassTalents, C_SpecializationInfo, C_Spell, C_SpellActivationOverlay
-local C_SpellBook, C_Traits, C_UnitAuras = C_SpellBook, C_Traits, Facade.C_UnitAuras
-local CombatLogGetCurrentEventInfo, GetBuildInfo, GetSpellBaseCooldown = Facade.CombatLogGetCurrentEventInfo, GetBuildInfo, Facade.GetSpellBaseCooldown
-local GetTime, InCombatLockdown, IsPlayerSpell, UnitCanAttack = GetTime, InCombatLockdown, IsPlayerSpell or function() end, UnitCanAttack
-local UnitClass, UnitClassBase, UnitIsUnit, UnitPowerMax = UnitClass, UnitClassBase, UnitIsUnit, UnitPowerMax
+local CreateFrame = Facade.CreateFrame
+local C_ClassTalents, C_SpecializationInfo, C_Spell, C_SpellActivationOverlay = Facade.C_ClassTalents, Facade.C_SpecializationInfo, Facade.C_Spell, Facade.C_SpellActivationOverlay
+local C_SpellBook, C_Traits, C_UnitAuras = Facade.C_SpellBook, Facade.C_Traits, Facade.C_UnitAuras
+local CombatLogGetCurrentEventInfo, GetBuildInfo, GetSpellBaseCooldown = Facade.CombatLogGetCurrentEventInfo, Facade.GetBuildInfo, Facade.GetSpellBaseCooldown
+local GetTime, InCombatLockdown, IsPlayerSpell, UnitCanAttack = Facade.GetTime, Facade.InCombatLockdown, Facade.IsPlayerSpell, Facade.UnitCanAttack
+local UnitClass, UnitClassBase, UnitIsUnit, UnitPowerMax = Facade.UnitClass, Facade.UnitClassBase, Facade.UnitIsUnit, Facade.UnitPowerMax
 local UnitSpellHaste = Facade.UnitSpellHaste
 local Hekili = _G[ addon ]
 
diff --git a/Options/Options.lua b/Options/Options.lua
index 3df3c3b7..fe2ef866 100644
--- a/Options/Options.lua
+++ b/Options/Options.lua
@@ -2,10 +2,12 @@
 -- Everything related to building/configuring options.
 
 local addon, ns = ...
-local C_ClassColor, C_SpecializationInfo, C_Spell = C_ClassColor, C_SpecializationInfo, C_Spell
-local GetBindingKey, GetCVar, GetFramerate, GetRealmName = GetBindingKey, GetCVar, GetFramerate, GetRealmName
-local GetSpecializationInfoByID, InCombatLockdown, UnitClass, UnitEffectiveLevel = GetSpecializationInfoByID, InCombatLockdown, UnitClass, UnitEffectiveLevel
-local C_VideoOptions, UnitLevel, UnitName = C_VideoOptions, UnitLevel, UnitName
+local Facade = ns.Facade
+local CreateFrame = Facade.CreateFrame
+local C_ClassColor, C_SpecializationInfo, C_Spell = Facade.C_ClassColor, Facade.C_SpecializationInfo, Facade.C_Spell
+local GetBindingKey, GetCVar, GetFramerate, GetRealmName = Facade.GetBindingKey, Facade.GetCVar, Facade.GetFramerate, Facade.GetRealmName
+local GetSpecializationInfoByID, InCombatLockdown, UnitClass, UnitEffectiveLevel = Facade.GetSpecializationInfoByID, Facade.InCombatLockdown, Facade.UnitClass, Facade.UnitEffectiveLevel
+local C_VideoOptions, UnitLevel, UnitName = Facade.C_VideoOptions, Facade.UnitLevel, Facade.UnitName
 local Hekili = _G[ addon ]
 
 local class = Hekili.Class
diff --git a/State.lua b/State.lua
index badb686c..a03d3802 100644
--- a/State.lua
+++ b/State.lua
@@ -3,18 +3,18 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local C_Item, C_LossOfControl, C_Spell = C_Item, C_LossOfControl, C_Spell
-local C_SpellBook, C_UnitAuras = C_SpellBook, Facade.C_UnitAuras
-local GetCombatRating, GetCombatRatingBonus, GetManaRegen, GetNumGroupMembers = Facade.GetCombatRating, Facade.GetCombatRatingBonus, Facade.GetManaRegen, GetNumGroupMembers
-local GetPowerRegenForPowerType, GetShapeshiftForm, GetShapeshiftFormInfo, GetTime = Facade.GetPowerRegenForPowerType, GetShapeshiftForm, GetShapeshiftFormInfo, GetTime
-local GetTotemInfo, GetUnitSpeed, InCombatLockdown, IsInJailersTower = Facade.GetTotemInfo, Facade.GetUnitSpeed, InCombatLockdown, IsInJailersTower
-local IsInRaid, IsMounted, IsPlayerSpell, IsSpellKnown = IsInRaid, IsMounted, IsPlayerSpell or function() end, IsSpellKnown or function() end
-local IsSpellKnownOrOverridesKnown, IsUsableSpell, UnitAttackSpeed, UnitAuraBySlot = IsSpellKnownOrOverridesKnown or function() end, Facade.IsUsableSpell, Facade.UnitAttackSpeed, Facade.UnitAuraBySlot
-local UnitCanAttack, UnitClassification, UnitCreatureType, UnitExists = UnitCanAttack, UnitClassification, UnitCreatureType, UnitExists
-local UnitGUID, UnitGetTotalAbsorbs, UnitHealth, UnitHealthMax = UnitGUID, Facade.UnitGetTotalAbsorbs, Facade.UnitHealth, Facade.UnitHealthMax
-local UnitInRange, UnitIsConnected, UnitIsDead, UnitIsDeadOrGhost = Facade.UnitInRange, UnitIsConnected, UnitIsDead, UnitIsDeadOrGhost
-local UnitIsPlayer, UnitLevel, UnitPower, UnitPowerMax = UnitIsPlayer, UnitLevel, Facade.UnitPower, UnitPowerMax
-local UnitPowerType, UnitStat, UnitThreatSituation = UnitPowerType, Facade.UnitStat, UnitThreatSituation
+local C_Item, C_LossOfControl, C_Spell = Facade.C_Item, Facade.C_LossOfControl, Facade.C_Spell
+local C_SpellBook, C_UnitAuras = Facade.C_SpellBook, Facade.C_UnitAuras
+local GetCombatRating, GetCombatRatingBonus, GetManaRegen, GetNumGroupMembers = Facade.GetCombatRating, Facade.GetCombatRatingBonus, Facade.GetManaRegen, Facade.GetNumGroupMembers
+local GetPowerRegenForPowerType, GetShapeshiftForm, GetShapeshiftFormInfo, GetTime = Facade.GetPowerRegenForPowerType, Facade.GetShapeshiftForm, Facade.GetShapeshiftFormInfo, Facade.GetTime
+local GetTotemInfo, GetUnitSpeed, InCombatLockdown, IsInJailersTower = Facade.GetTotemInfo, Facade.GetUnitSpeed, Facade.InCombatLockdown, Facade.IsInJailersTower
+local IsInRaid, IsMounted, IsPlayerSpell, IsSpellKnown = Facade.IsInRaid, Facade.IsMounted, Facade.IsPlayerSpell, Facade.IsSpellKnown
+local IsSpellKnownOrOverridesKnown, IsUsableSpell, UnitAttackSpeed, UnitAuraBySlot = Facade.IsSpellKnownOrOverridesKnown, Facade.IsUsableSpell, Facade.UnitAttackSpeed, Facade.UnitAuraBySlot
+local UnitCanAttack, UnitClassification, UnitCreatureType, UnitExists = Facade.UnitCanAttack, Facade.UnitClassification, Facade.UnitCreatureType, Facade.UnitExists
+local UnitGUID, UnitGetTotalAbsorbs, UnitHealth, UnitHealthMax = Facade.UnitGUID, Facade.UnitGetTotalAbsorbs, Facade.UnitHealth, Facade.UnitHealthMax
+local UnitInRange, UnitIsConnected, UnitIsDead, UnitIsDeadOrGhost = Facade.UnitInRange, Facade.UnitIsConnected, Facade.UnitIsDead, Facade.UnitIsDeadOrGhost
+local UnitIsPlayer, UnitLevel, UnitPower, UnitPowerMax = Facade.UnitIsPlayer, Facade.UnitLevel, Facade.UnitPower, Facade.UnitPowerMax
+local UnitPowerType, UnitStat, UnitThreatSituation = Facade.UnitPowerType, Facade.UnitStat, Facade.UnitThreatSituation
 local Hekili = _G[ addon ]
 
 local auras = ns.auras
@@ -36,7 +36,7 @@ local GetSpellInfo, GetSpellCharges, GetSpellLossOfControlCooldown = ns.GetUnpac
 local UnitBuff, UnitDebuff = ns.UnitBuff, ns.UnitDebuff
 
 local GetBuffDataByIndex, GetDebuffDataByIndex = Facade.C_UnitAuras.GetBuffDataByIndex, Facade.C_UnitAuras.GetDebuffDataByIndex
-local UnpackAuraData = AuraUtil.UnpackAuraData
+local UnpackAuraData = Facade.AuraUtil.UnpackAuraData
 
 local GetSpellCharges = function(spellID)
     local spellChargeInfo = GetSpellCharges(spellID);
@@ -46,7 +46,7 @@ local GetSpellCharges = function(spellID)
 end
 local FindPlayerAuraByID, IsAbilityDisabled = ns.FindPlayerAuraByID, ns.IsAbilityDisabled
 
-local GetSpecialization = C_SpecializationInfo.GetSpecialization
+local GetSpecialization = Facade.C_SpecializationInfo.GetSpecialization
 
 -- Clean up table_x later.
 ---@diagnostic disable-next-line: deprecated
@@ -442,7 +442,7 @@ state.GetSpellCount = Facade.C_Spell.GetSpellCastCount
 state.GetSpellInfo = ns.GetUnpackedSpellInfo
 state.GetSpellLink = Facade.GetSpellLink
 state.GetSpellTexture = C_Spell.GetSpellTexture
-state.GetStablePetInfo = GetStablePetInfo
+state.GetStablePetInfo = Facade.GetStablePetInfo
 state.GetTime = GetTime
 state.GetTotemInfo = GetTotemInfo
 state.InCombatLockdown = InCombatLockdown
@@ -465,10 +465,10 @@ state.UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
 state.UnitGUID = UnitGUID
 state.UnitHealth = UnitHealth
 state.UnitHealthMax = UnitHealthMax
-state.UnitName = UnitName
-state.UnitIsFriend = UnitIsFriend
+state.UnitName = Facade.UnitName
+state.UnitIsFriend = Facade.UnitIsFriend
 
-local UnitIsUnit = UnitIsUnit
+local UnitIsUnit = Facade.UnitIsUnit
 
 state.UnitIsUnit = function( a, b )
     return a == b or UnitIsUnit( a, b )
@@ -509,8 +509,8 @@ state.safebool = function( val )
 end
 
 state.combat = 0
-state.faction = UnitFactionGroup( "player" )
-state.race[ formatKey( UnitRace("player") ) ] = true
+state.faction = Facade.UnitFactionGroup( "player" )
+state.race[ formatKey( Facade.UnitRace("player") ) ] = true
 
 state.class = Hekili.Class
 state.targets = ns.targets
@@ -1791,7 +1791,7 @@ do
 
             -- Internal processing stuff.
             elseif k == "display" then t[k] = "Primary"
-            elseif k == "latency" then t[k] = select( 4, GetNetStats() ) / 1000
+            elseif k == "latency" then t[k] = select( 4, Facade.GetNetStats() ) / 1000
             elseif k == "resetting" then t[k] = false
             elseif k == "scriptID" then t[k] = "NilScriptID"
             elseif k == "whitelist" then return nil
@@ -1856,7 +1856,7 @@ do
 
                 t[k] = max( 1, count )
 
-            elseif k == "level" then t[k] = UnitEffectiveLevel("player") or MAX_PLAYER_LEVEL
+            elseif k == "level" then t[k] = Facade.UnitEffectiveLevel("player") or MAX_PLAYER_LEVEL
             elseif k == "mounted" or k == "is_mounted" then t[k] = IsMounted()
             elseif k == "moving" then t[k] = ( GetUnitSpeed("player") > 0 )
             elseif k == "raid" then t[k] = IsInRaid() and t.group_members > 5
@@ -2757,7 +2757,7 @@ do
                 if not t.exists then t[k] = "virtual"
                 elseif not t.is_player then t[k] = "npc"
                 else
-                    local c = UnitClassBase( "target" )
+                    local c = Facade.UnitClassBase( "target" )
                     if c then t[k] = strlower( c )
                     else t[k] = "unknown" end
                 end
@@ -2765,7 +2765,7 @@ do
             elseif k == "health_current" then return t.health.current
             elseif k == "health_max" then return t.health.max
             elseif k == "health_pct" or k == "health_percent" then return t.health.percent
-            elseif k == "has_vehicle_ui" then t[k] = UnitInVehicle( "target" )
+            elseif k == "has_vehicle_ui" then t[k] = Facade.UnitInVehicle( "target" )
             elseif k == "is_add" then t[k] = not t.is_boss
             elseif k == "is_boss" then
                 if UnitExists( "boss1" ) and UnitIsUnit( "target", "boss1" ) or
@@ -2778,9 +2778,9 @@ do
                 end
             elseif k == "is_dead" then t[k] = UnitIsDeadOrGhost("target")
             elseif k == "is_demon" then t[k] = UnitCreatureType( "target" ) == PET_TYPE_DEMON
-            elseif k == "is_friendly" then t[k] = UnitCanAssist( "player", "target" )
-            elseif k == "is_in_party" then t[k] = UnitInParty( "target" )
-            elseif k == "is_in_raid" then t[k] = UnitInRaid( "target" ) ~= nil
+            elseif k == "is_friendly" then t[k] = Facade.UnitCanAssist( "player", "target" )
+            elseif k == "is_in_party" then t[k] = Facade.UnitInParty( "target" )
+            elseif k == "is_in_raid" then t[k] = Facade.UnitInRaid( "target" ) ~= nil
             elseif k == "is_player" then
                 local isPlayer = UnitIsPlayer( "target" )
                 if not isPlayer then isPlayer = PvpDummies[ t.npcid ] end
diff --git a/Targets.lua b/Targets.lua
index eeba9a4e..9099fa73 100644
--- a/Targets.lua
+++ b/Targets.lua
@@ -3,15 +3,15 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local C_AddOns, C_PlayerInfo, C_PvP = C_AddOns, C_PlayerInfo, C_PvP
-local GetActionInfo, GetCVar, GetHaste, GetNumGroupMembers = GetActionInfo, GetCVar, Facade.GetHaste, GetNumGroupMembers
-local GetTime, GetUnitSpeed, InCombatLockdown, IsActionInRange = GetTime, Facade.GetUnitSpeed, InCombatLockdown, IsActionInRange or function() end
-local IsInInstance, IsInRaid, UnitAffectingCombat, UnitCanAttack = IsInInstance, IsInRaid, UnitAffectingCombat, UnitCanAttack
-local UnitClassBase, UnitExists, UnitGUID, UnitGetTotalAbsorbs = UnitClassBase, UnitExists, UnitGUID, Facade.UnitGetTotalAbsorbs
-local UnitHealth, UnitHealthMax, UnitInParty, UnitInRaid = Facade.UnitHealth, Facade.UnitHealthMax, UnitInParty, UnitInRaid
-local UnitIsDead, UnitIsFriend, UnitIsPVP, UnitIsPlayer = UnitIsDead, UnitIsFriend, UnitIsPVP, UnitIsPlayer
-local UnitIsTrivial, UnitIsUnit, UnitLevel, UnitName = UnitIsTrivial, UnitIsUnit, UnitLevel, UnitName
-local UnitPhaseReason, UnitTokenFromGUID = UnitPhaseReason, UnitTokenFromGUID
+local C_AddOns, C_PlayerInfo, C_PvP = Facade.C_AddOns, Facade.C_PlayerInfo, Facade.C_PvP
+local GetActionInfo, GetCVar, GetHaste, GetNumGroupMembers = Facade.GetActionInfo, Facade.GetCVar, Facade.GetHaste, Facade.GetNumGroupMembers
+local GetTime, GetUnitSpeed, InCombatLockdown, IsActionInRange = Facade.GetTime, Facade.GetUnitSpeed, Facade.InCombatLockdown, Facade.IsActionInRange
+local IsInInstance, IsInRaid, UnitAffectingCombat, UnitCanAttack = Facade.IsInInstance, Facade.IsInRaid, Facade.UnitAffectingCombat, Facade.UnitCanAttack
+local UnitClassBase, UnitExists, UnitGUID, UnitGetTotalAbsorbs = Facade.UnitClassBase, Facade.UnitExists, Facade.UnitGUID, Facade.UnitGetTotalAbsorbs
+local UnitHealth, UnitHealthMax, UnitInParty, UnitInRaid = Facade.UnitHealth, Facade.UnitHealthMax, Facade.UnitInParty, Facade.UnitInRaid
+local UnitIsDead, UnitIsFriend, UnitIsPVP, UnitIsPlayer = Facade.UnitIsDead, Facade.UnitIsFriend, Facade.UnitIsPVP, Facade.UnitIsPlayer
+local UnitIsTrivial, UnitIsUnit, UnitLevel, UnitName = Facade.UnitIsTrivial, Facade.UnitIsUnit, Facade.UnitLevel, Facade.UnitName
+local UnitPhaseReason, UnitTokenFromGUID = Facade.UnitPhaseReason, Facade.UnitTokenFromGUID
 local Hekili = _G[addon]
 
 local class = Hekili.Class
diff --git a/UI.lua b/UI.lua
index 6cf59209..a379bb6a 100644
--- a/UI.lua
+++ b/UI.lua
@@ -3,12 +3,13 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local C_Item, C_PetBattles, C_SpecializationInfo, C_Spell = C_Item, C_PetBattles, C_SpecializationInfo, C_Spell
-local C_SpellActivationOverlay, C_VideoOptions = C_SpellActivationOverlay, C_VideoOptions
-local GetFramerate, GetTime, HasOverrideActionBar, HasVehicleActionBar = GetFramerate, GetTime, HasOverrideActionBar or function() end, HasVehicleActionBar or function() end
-local InCombatLockdown, IsInInstance, IsMounted, UnitCanAttack = InCombatLockdown, IsInInstance, IsMounted, UnitCanAttack
-local UnitCastingInfo, UnitChannelInfo, UnitClass, UnitExists = Facade.UnitCastingInfo, Facade.UnitChannelInfo, UnitClass, UnitExists
-local UnitHasVehicleUI, UnitIsDead, UnitOnTaxi = UnitHasVehicleUI, UnitIsDead, UnitOnTaxi
+local CreateFrame = Facade.CreateFrame
+local C_Item, C_PetBattles, C_SpecializationInfo, C_Spell = Facade.C_Item, Facade.C_PetBattles, Facade.C_SpecializationInfo, Facade.C_Spell
+local C_SpellActivationOverlay, C_VideoOptions = Facade.C_SpellActivationOverlay, Facade.C_VideoOptions
+local GetFramerate, GetTime, HasOverrideActionBar, HasVehicleActionBar = Facade.GetFramerate, Facade.GetTime, Facade.HasOverrideActionBar, Facade.HasVehicleActionBar
+local InCombatLockdown, IsInInstance, IsMounted, UnitCanAttack = Facade.InCombatLockdown, Facade.IsInInstance, Facade.IsMounted, Facade.UnitCanAttack
+local UnitCastingInfo, UnitChannelInfo, UnitClass, UnitExists = Facade.UnitCastingInfo, Facade.UnitChannelInfo, Facade.UnitClass, Facade.UnitExists
+local UnitHasVehicleUI, UnitIsDead, UnitOnTaxi = Facade.UnitHasVehicleUI, Facade.UnitIsDead, Facade.UnitOnTaxi
 local Hekili = _G[ addon ]
 
 local class = Hekili.Class
diff --git a/Utils.lua b/Utils.lua
index 8821ffd7..7b65b0ec 100644
--- a/Utils.lua
+++ b/Utils.lua
@@ -3,12 +3,12 @@
 
 local addon, ns = ...
 local Facade = ns.Facade
-local AuraUtil, C_Item = AuraUtil, C_Item
-local C_Spell, C_SpellBook, C_Texture, C_TooltipInfo = C_Spell, C_SpellBook, C_Texture, C_TooltipInfo
+local AuraUtil, C_Item = Facade.AuraUtil, Facade.C_Item
+local C_Spell, C_SpellBook, C_Texture, C_TooltipInfo = Facade.C_Spell, Facade.C_SpellBook, Facade.C_Texture, Facade.C_TooltipInfo
 local C_UnitAuras = Facade.C_UnitAuras
-local GetNumGroupMembers, GetNumSubgroupMembers, GetTime, IsInGroup = GetNumGroupMembers, GetNumSubgroupMembers, GetTime, IsInGroup
-local IsInRaid, UnitHealth, UnitHealthMax, UnitIsUnit = IsInRaid, Facade.UnitHealth, Facade.UnitHealthMax, UnitIsUnit
-local UnitName = UnitName
+local GetNumGroupMembers, GetNumSubgroupMembers, GetTime, IsInGroup = Facade.GetNumGroupMembers, Facade.GetNumSubgroupMembers, Facade.GetTime, Facade.IsInGroup
+local IsInRaid, UnitHealth, UnitHealthMax, UnitIsUnit = Facade.IsInRaid, Facade.UnitHealth, Facade.UnitHealthMax, Facade.UnitIsUnit
+local UnitName = Facade.UnitName
 local Hekili = _G[ addon ]
 
 local format, gsub, lower = string.format, string.gsub, string.lower
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index 24b9fd09..553a11bb 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -14,7 +14,7 @@ local CAST_SUCCESS, CHANNEL_START = Obs.CastSuccess, Obs.ChannelStart
 local Hekili = _G[addon]
 local state, class = Hekili.State, Hekili.Class
 local spendResources = ns.spendResources
-local GetTime, CreateFrame = GetTime, CreateFrame
+local GetTime, CreateFrame = ns.Facade.GetTime, ns.Facade.CreateFrame
 local debugprofilestop = debugprofilestop
 local insert, sort = table.insert, table.sort
 
@@ -32,7 +32,7 @@ I.urgent = function(event)
     Hekili:ForceUpdate(event)
 end
 
--- Start once, at PLAYER_LOGIN, on a frame of its own.
+-- Start once, at PLAYER_LOGIN, on a frame of its own (a subscriber of the event facade like Hekili's frames).
 do
     local boot = CreateFrame("Frame")
     boot:RegisterEvent("PLAYER_LOGIN")
diff --git a/VirtualState/EventFacade.lua b/VirtualState/EventFacade.lua
index d07e14c9..bc4722ae 100644
--- a/VirtualState/EventFacade.lua
+++ b/VirtualState/EventFacade.lua
@@ -15,7 +15,7 @@ local _G = _G
 local E = {}
 I.Events = E
 
--- The client table: `_G` in game; a spec sets `_G.CreateFrame` (and `_G.issecretvalue`) to its fake before loading.
+-- The client table: `_G` in game; a spec sets its CreateFrame (and issecretvalue) to the fake's before loading.
 local client = _G
 local realCreateFrame = client.CreateFrame
 
diff --git a/VirtualState/Facade.lua b/VirtualState/Facade.lua
index 44ab8641..e356ee44 100644
--- a/VirtualState/Facade.lua
+++ b/VirtualState/Facade.lua
@@ -1,8 +1,11 @@
 -- VirtualState/Facade.lua
--- ns.Facade (spec §7): the game API names that are secret in combat, partly secret, or absent on WoW Forever. Each is
--- `virtual` (a policy answering from VirtualState, §7.4) or `stub` (a fixed, API-shaped result, §7.3); every other
--- game read in Hekili is a direct call. Namespaces mirror the game (Facade.UnitPower, Facade.C_Spell.GetSpellCooldown,
--- Facade.AuraUtil.ForEachAura). Query with Facade.Status(name), Facade.Why(name), Facade.Stubs(), Facade.Inventory().
+-- ns.Facade (spec §7; event-facade spec §1.1): every game function Hekili core and the class files read, in one of
+-- three classes (event-facade decision 8): `passthrough` (the raw call: plain by probe, or a value Hekili never uses
+-- in a way a secret breaks), `hybrid` (the raw call; a secret answer is replaced by the policy's, for names secret
+-- only sometimes) and `virtual` (the policy only, never the game's answer: secret always, absent on Forever, or
+-- answered from VirtualState for a reason beyond secrecy). Namespaces mirror the game (Facade.UnitPower,
+-- Facade.C_Spell.GetSpellCooldown, Facade.AuraUtil.ForEachAura). Query with Facade.Status(name) (the class),
+-- Facade.Why(name), Facade.Inventory(); tools/api_inventory.txt lists every name with its class.
 -- Every policy uses now = GetTime(), or the clock Drain pins while it applies a cast (spec §5.5 R1), and returns
 -- shared preallocated result tables that callers read at once and never keep or mutate.
 -- Origin: Libs/VirtualGameAPI-1.0, folded into Hekili. Copyright (c) 2026 Zack Samsel. MIT licence, see
@@ -60,6 +63,52 @@ local realIsSpellUsable = resolve("C_Spell.IsSpellUsable")
 local realGetSpellInfo = resolve("C_Spell.GetSpellInfo")
 local realUnitCastingInfo = resolve("UnitCastingInfo")
 local realUnitChannelInfo = resolve("UnitChannelInfo")
+local realGetSpellCharges = resolve("C_Spell.GetSpellCharges")
+
+--- A passthrough: the raw function, wrapped once at load so a later finding changes one row, not Hekili. A name the
+--- client lacks (the deprecation shims while `loadDeprecationFallbacks` is off) answers nothing and is virtual.
+local function passthrough(name, reason)
+    local real = resolve(name)
+    if not real then
+        kept(name, "virtual", function() end, "absent on this client; answers nothing (" .. reason .. ")")
+        return
+    end
+    kept(name, "passthrough", function(...)
+        return real(...)
+    end, reason)
+end
+
+-- The raw answer, or the policy's when any of its first four values is secret. Allocates nothing.
+local function pick(policy, x, y, z, a, b, c, d, ...)
+    if issecretvalue(a) or issecretvalue(b) or issecretvalue(c) or issecretvalue(d) then
+        return policy(x, y, z)
+    end
+    return a, b, c, d, ...
+end
+
+--- A hybrid of up to three arguments: the raw call, its secret answer replaced by `policy`'s (absent: the policy).
+local function hybrid(name, policy, reason)
+    local real = resolve(name)
+    if not real then
+        kept(name, "virtual", policy, reason .. "; absent on this client")
+        return
+    end
+    kept(name, "hybrid", function(x, y, z)
+        return pick(policy, x, y, z, real(x, y, z))
+    end, reason)
+end
+
+-- Whether a cooldown or charge table's two time fields are plain numbers (the hybrid tables' test).
+local function plainTimes(info, startKey, durationKey)
+    if issecretvalue(info) or type(info) ~= "table" then
+        return false
+    end
+    local s, d = info[startKey], info[durationKey]
+    if issecretvalue(s) or issecretvalue(d) then
+        return false
+    end
+    return type(s) == "number" and type(d) == "number"
+end
 
 -- The facade's clock: the pinned cast time during a drain, else GetTime().
 local function now()
@@ -98,22 +147,22 @@ kept("UnitPower", "virtual", function(unit, powerType)
     return floor(powerType == 1 and b.est or b.lo) -- rage answers est (G4, CHECKPOINT 4); others lo
 end, "secret always [W PR16]; rage Power().est (G4), others Power().lo")
 
-kept("GetPowerRegenForPowerType", "virtual", function(powerType)
+hybrid("GetPowerRegenForPowerType", function(powerType)
     local r = I.res.slotOf[powerType]
     if r and I.res.swing[r] > 0 and VS.InCombat() then
         return 0, 0 -- Hekili's swing regen model adds that resource (no double count, G3)
     end
     local est = VS.Regen(powerType, now()).est
     return est, est
-end, "secret in combat [W PR16]; Regen()")
+end, "secret in combat [W PR16]; Regen(), 0 for a swing-paid resource in combat (G3)")
 
-kept("GetManaRegen", "virtual", function()
+hybrid("GetManaRegen", function()
     local t = now()
     local inactive = VS.Regen(0, t).est
     return inactive, VS.Regen(0, t, true).est
 end, "secret in combat [W PR16]; Regen(0)")
 
-kept("UnitPartialPower", "stub", zero, "secret always [W PR16]; no Forever user")
+kept("UnitPartialPower", "virtual", zero, "secret always [W PR16]; no Forever user")
 
 ----------------------------------------------------------------------------------------------------------------------
 -- Health [W PR14]
@@ -135,46 +184,46 @@ kept("UnitHealthMax", "virtual", function(unit)
     return VS.HealthMax(unit)
 end, "target secret always [W PR14]; HealthMax()")
 
-kept("UnitGetTotalAbsorbs", "stub", zero, "target secret always [W PR14]")
+kept("UnitGetTotalAbsorbs", "virtual", zero, "target secret always [W PR14]")
 
 ----------------------------------------------------------------------------------------------------------------------
 -- Stats: the out-of-combat cache [W PR2, PR4]
 
 local STAT = "secret in combat [W PR2, PR4]; Stat()"
-kept("GetCombatRating", "virtual", function(cr)
+hybrid("GetCombatRating", function(cr)
     return VS.Stat("GetCombatRating", cr)
 end, STAT)
-kept("GetCombatRatingBonus", "virtual", function(cr)
+hybrid("GetCombatRatingBonus", function(cr)
     return VS.Stat("GetCombatRatingBonus", cr)
 end, STAT)
-kept("GetCritChance", "virtual", function()
+hybrid("GetCritChance", function()
     return VS.Stat("GetCritChance")
 end, STAT)
-kept("GetMasteryEffect", "virtual", function()
+hybrid("GetMasteryEffect", function()
     return VS.Stat("GetMasteryEffect")
 end, STAT)
-kept("GetRangedCritChance", "virtual", function()
+hybrid("GetRangedCritChance", function()
     return VS.Stat("GetRangedCritChance")
 end, STAT)
-kept("GetSpellBonusDamage", "virtual", function(school)
+hybrid("GetSpellBonusDamage", function(school)
     return VS.Stat("GetSpellBonusDamage", school)
 end, STAT)
-kept("GetSpellCritChance", "virtual", function()
+hybrid("GetSpellCritChance", function()
     return VS.Stat("GetSpellCritChance")
 end, STAT)
-kept("UnitArmor", "virtual", function()
+hybrid("UnitArmor", function()
     return VS.Stat("UnitArmor")
 end, STAT)
-kept("UnitAttackPower", "virtual", function()
+hybrid("UnitAttackPower", function()
     return VS.Stat("UnitAttackPower")
 end, STAT)
-kept("UnitDamage", "virtual", function()
+hybrid("UnitDamage", function()
     return VS.Stat("UnitDamage")
 end, STAT)
-kept("UnitStat", "virtual", function(unit, index)
+hybrid("UnitStat", function(unit, index)
     return VS.Stat("UnitStat", index)
 end, STAT)
-kept("UnitWeaponAttackPower", "virtual", function()
+hybrid("UnitWeaponAttackPower", function()
     return VS.Stat("UnitWeaponAttackPower")
 end, STAT)
 
@@ -184,17 +233,17 @@ end, STAT)
 local function meleeHaste()
     return (VS.Haste(now()).est - 1) * 100
 end
-kept("GetHaste", "virtual", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")
-kept("GetMeleeHaste", "virtual", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")
+hybrid("GetHaste", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")
+hybrid("GetMeleeHaste", meleeHaste, "secret in combat [W PR2, PR4]; Haste()")
 
-kept("UnitSpellHaste", "virtual", function(unit)
+hybrid("UnitSpellHaste", function(unit)
     if unit ~= "player" then
         return 0
     end
     return VS.SpellHaste(now()).est
 end, "secret in combat [W PR2, PR4]; SpellHaste()")
 
-kept("UnitAttackSpeed", "virtual", function(unit)
+hybrid("UnitAttackSpeed", function(unit)
     if unit ~= "player" then
         return 2, nil
     end
@@ -207,7 +256,7 @@ kept("UnitAttackSpeed", "virtual", function(unit)
     return main, nil
 end, "secret in combat [SU PR2]; SwingSpeed()")
 
-kept("GetUnitSpeed", "virtual", function(unit)
+hybrid("GetUnitSpeed", function(unit)
     if unit == "player" and VS.Moving() then
         return 7, 7, 7, 4.72
     elseif unit == "player" then
@@ -216,12 +265,12 @@ kept("GetUnitSpeed", "virtual", function(unit)
     return 0, 0, 0, 0
 end, "secret in combat [W PR14]; Moving()")
 
-kept("UnitInRange", "stub", inRangeUnknown, "secret always [W PR7]; no signal")
+kept("UnitInRange", "virtual", inRangeUnknown, "secret always [W PR7]; no signal")
 
 ----------------------------------------------------------------------------------------------------------------------
 -- Totems [W PR12]
 
-kept("GetTotemInfo", "virtual", function(slot)
+hybrid("GetTotemInfo", function(slot)
     local spellID, name, icon, start = VS.TotemFacts(slot)
     local rec = spellID and VS.Totem(slot, now())
     if not rec then
@@ -364,9 +413,9 @@ kept("AuraUtil.FindAura", "virtual", function(predicate, unit, filter, arg1, arg
     return nil
 end, "wraps secret aura data [W §4]; AuraAt()")
 
-kept("C_UnitAuras.GetAuraSlots", "stub", nothing, "secret in combat [W §4]; no retained consumer")
-kept("UnitAura", "stub", nothing, "absent on Forever")
-kept("UnitAuraBySlot", "stub", nothing, "absent on Forever")
+kept("C_UnitAuras.GetAuraSlots", "virtual", nothing, "secret in combat [W §4]; no retained consumer")
+kept("UnitAura", "virtual", nothing, "absent on Forever")
+kept("UnitAuraBySlot", "virtual", nothing, "absent on Forever")
 
 ----------------------------------------------------------------------------------------------------------------------
 -- Cooldowns [W PR4, PR11]: times secret in combat, flags plain
@@ -390,7 +439,7 @@ local function flags(spellID)
     return active, onGcd
 end
 
-kept("C_Spell.GetSpellCooldown", "virtual", function(spellID)
+local function cooldownPolicy(spellID)
     local t = now()
     if spellID == 61304 or spellID == I.GCD_SPELL then
         local s, d = VS.GcdInfo(t)
@@ -426,9 +475,16 @@ kept("C_Spell.GetSpellCooldown", "virtual", function(spellID)
         CD.isActive = rec.est > t
     end
     return CD
+end
+kept("C_Spell.GetSpellCooldown", "hybrid", function(spellID)
+    local info = realGetSpellCooldown and realGetSpellCooldown(spellID)
+    if plainTimes(info, "startTime", "duration") then
+        return info
+    end
+    return cooldownPolicy(spellID)
 end, "times secret in combat, flags plain [W PR4, PR11]; Cooldown(), GcdInfo()")
 
-kept("C_Spell.GetSpellCharges", "virtual", function(spellID)
+local function chargesPolicy(spellID)
     local cur, nextAt = VS.Charges(spellID, now())
     if not cur then
         return nil
@@ -441,17 +497,27 @@ kept("C_Spell.GetSpellCharges", "virtual", function(spellID)
     CHARGES.cooldownStartTime = nextAt.est > 0 and nextAt.est - recharge or 0
     CHARGES.cooldownDuration = recharge
     return CHARGES
+end
+kept("C_Spell.GetSpellCharges", "hybrid", function(spellID)
+    local info = realGetSpellCharges and realGetSpellCharges(spellID)
+    if not issecretvalue(info) and info == nil then
+        return nil -- not a charge spell (plain)
+    end
+    if plainTimes(info, "cooldownStartTime", "cooldownDuration") then
+        return info
+    end
+    return chargesPolicy(spellID)
 end, "times secret in combat [W §4 cooldowns]; Charges()")
 
-kept("C_Spell.GetSpellCastCount", "stub", zero, "flagged SecretWhenCooldownsRestricted; unprobed, unused")
-kept("C_Spell.GetSpellLossOfControlCooldown", "stub", nothing, "absent on Forever")
+kept("C_Spell.GetSpellCastCount", "virtual", zero, "flagged SecretWhenCooldownsRestricted; unprobed, unused")
+kept("C_Spell.GetSpellLossOfControlCooldown", "virtual", nothing, "absent on Forever")
 
 ----------------------------------------------------------------------------------------------------------------------
 -- Casts: the player's own are plain [W PR9], the target's secret [W PR8]
 
 local CAST_ICON = 136243
 
-kept("UnitCastingInfo", "virtual", function(unit, ...)
+kept("UnitCastingInfo", "hybrid", function(unit, ...)
     if unit == "player" then
         if realUnitCastingInfo then
             return realUnitCastingInfo(unit, ...)
@@ -468,7 +534,7 @@ kept("UnitCastingInfo", "virtual", function(unit, ...)
     return "Casting", "", CAST_ICON, start * 1000, rec.est * 1000, false, castBarID, kick == 0, 0
 end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")
 
-kept("UnitChannelInfo", "virtual", function(unit, ...)
+kept("UnitChannelInfo", "hybrid", function(unit, ...)
     if unit == "player" then
         if realUnitChannelInfo then
             return realUnitChannelInfo(unit, ...)
@@ -488,31 +554,164 @@ end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")
 ----------------------------------------------------------------------------------------------------------------------
 -- Combat log, talents, spells and items: absent on Forever, or replaced
 
-kept("CombatLogGetCurrentEventInfo", "stub", nothing, "absent; registering CLEU is forbidden (Phases 2 and 3)")
-kept("GetTalentInfoByID", "stub", nothing, "dead on Forever [W PR5]; ranks come from VirtualState.Talent")
-kept("IsUsableSpell", "virtual", function(spellID)
+kept("CombatLogGetCurrentEventInfo", "virtual", nothing, "absent; registering CLEU is forbidden (Phases 2 and 3)")
+kept("GetTalentInfoByID", "virtual", nothing, "dead on Forever [W PR5]; ranks come from VirtualState.Talent")
+kept("IsUsableSpell", "passthrough", function(spellID)
     if realIsSpellUsable then
         return realIsSpellUsable(spellID)
     end
     return false
 end, "absent on Forever; alias of C_Spell.IsSpellUsable (plain [W PR14; SU])")
-kept("GetSpellBaseCooldown", "stub", nothing, "absent on Forever")
-kept("GetSpellLink", "stub", nothing, "absent on Forever")
-kept("IsHarmfulSpell", "stub", isFalse, "absent on Forever")
-kept("IsHelpfulSpell", "stub", isFalse, "absent on Forever")
-kept("IsPassiveSpell", "stub", isFalse, "absent on Forever")
-kept("GetItemGem", "stub", nothing, "absent on Forever")
-kept("GetItemInfo", "stub", nothing, "absent on Forever")
+kept("GetSpellBaseCooldown", "virtual", nothing, "absent on Forever")
+kept("GetSpellLink", "virtual", nothing, "absent on Forever")
+kept("IsHarmfulSpell", "virtual", isFalse, "absent on Forever")
+kept("IsHelpfulSpell", "virtual", isFalse, "absent on Forever")
+kept("IsPassiveSpell", "virtual", isFalse, "absent on Forever")
+kept("GetItemGem", "virtual", nothing, "absent on Forever")
+kept("GetItemInfo", "virtual", nothing, "absent on Forever")
+
+----------------------------------------------------------------------------------------------------------------------
+-- Frames: the event facade's entry point (event-facade spec §2.1)
+
+kept("CreateFrame", "virtual", I.Events.CreateFrame, "the event facade: a frame whose events subscribe to the layer")
+
+----------------------------------------------------------------------------------------------------------------------
+-- Passthroughs: the evidence per name from docs/forever-facade-notes.md ("unprobed": present on Forever, never probed;
+-- not combat state, and the trace counts any secret answer, event-facade spec §5)
+
+local PASSTHROUGH = {
+    { "AuraUtil.UnpackAuraData", "pure Lua unpack of a table" },
+    { "C_AddOns.GetAddOnMetadata", "unprobed" },
+    { "C_AddOns.IsAddOnLoaded", "unprobed" },
+    { "C_AddOns.LoadAddOn", "unprobed" },
+    { "C_ClassColor.GetClassColor", "unprobed" },
+    { "C_ClassTalents.GetActiveConfigID", "unprobed" },
+    { "C_ClassTalents.GetHeroTalentSpecsForClassSpec", "unprobed" },
+    { "C_Item.GetDetailedItemLevelInfo", "plain [W PR13]" },
+    { "C_Item.GetItemCooldown", "plain [W PR13]" },
+    { "C_Item.GetItemCount", "plain [W PR13]" },
+    { "C_Item.GetItemGem", "plain [W PR13]" },
+    { "C_Item.GetItemInfo", "plain [W PR13]" },
+    { "C_Item.GetItemInfoInstant", "plain [W PR13]" },
+    { "C_Item.GetItemSpell", "plain [W PR13]" },
+    { "C_Item.IsCurrentItem", "plain [W PR13]" },
+    { "C_Item.IsEquippedItem", "plain [W PR13]" },
+    { "C_Item.IsUsableItem", "plain [W PR13]" },
+    { "C_LossOfControl.GetActiveLossOfControlData", "plain [W PR18]" },
+    { "C_LossOfControl.GetActiveLossOfControlDataCount", "plain [W PR18]" },
+    { "C_PetBattles.IsInBattle", "unprobed" },
+    { "C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier", "unprobed" },
+    { "C_PvP.IsWarModeDesired", "unprobed" },
+    { "C_SpecializationInfo.GetSpecialization", "plain [W PR15]" },
+    { "C_SpecializationInfo.GetSpecializationInfo", "plain [W PR15]" },
+    { "C_SpecializationInfo.GetTalentInfo", "unprobed" },
+    { "C_Spell.GetSpellDescription", "unprobed" },
+    { "C_Spell.GetSpellInfo", "unprobed" },
+    { "C_Spell.GetSpellPowerCost", "plain [W §4]" },
+    { "C_Spell.GetSpellTexture", "unprobed" },
+    { "C_Spell.IsCurrentSpell", "plain [W PR1]" },
+    { "C_Spell.IsSpellDataCached", "unprobed" },
+    { "C_Spell.IsSpellHarmful", "unprobed" },
+    { "C_Spell.IsSpellHelpful", "unprobed" },
+    { "C_Spell.IsSpellPassive", "unprobed" },
+    { "C_Spell.IsSpellUsable", "plain [W PR14; SU]" },
+    { "C_Spell.RequestLoadSpellData", "unprobed" },
+    { "C_SpellActivationOverlay.IsSpellOverlayed", "plain [W PR11]" },
+    { "C_SpellBook.FindSpellBookSlotForSpell", "unprobed" },
+    { "C_SpellBook.GetNumSpellBookSkillLines", "unprobed" },
+    { "C_SpellBook.GetSpellBookItemInfo", "unprobed" },
+    { "C_SpellBook.GetSpellBookSkillLineInfo", "unprobed" },
+    { "C_SpellBook.IsSpellInSpellBook", "unprobed" },
+    { "C_SpellBook.IsSpellKnown", "unprobed" },
+    { "C_Texture.GetAtlasInfo", "unprobed" },
+    { "C_TooltipInfo.GetInventoryItem", "unprobed" },
+    { "C_TooltipInfo.GetItemByID", "unprobed" },
+    { "C_TooltipInfo.GetSpellByID", "unprobed" },
+    { "C_Traits.GetConfigInfo", "plain, walk identical in combat [W PR5]" },
+    { "C_Traits.GetDefinitionInfo", "plain, walk identical in combat [W PR5]" },
+    { "C_Traits.GetEntryInfo", "plain, walk identical in combat [W PR5]" },
+    { "C_Traits.GetNodeCost", "plain, walk identical in combat [W PR5]" },
+    { "C_Traits.GetNodeInfo", "plain, walk identical in combat [W PR5]" },
+    { "C_Traits.GetSubTreeInfo", "plain, walk identical in combat [W PR5]" },
+    { "C_Traits.GetTreeCurrencyInfo", "plain, walk identical in combat [W PR5]" },
+    { "C_Traits.GetTreeNodes", "plain, walk identical in combat [W PR5]" },
+    { "C_VideoOptions.GetCurrentGameWindowSize", "unprobed" },
+    { "GetActionInfo", "plain [W PR10]" },
+    { "GetBindingKey", "plain [W PR10]" },
+    { "GetBuildInfo", "unprobed" },
+    { "GetCVar", "unprobed" },
+    { "GetClassInfo", "unprobed" },
+    { "GetCursorInfo", "unprobed" },
+    { "GetFrameCPUUsage", "unprobed" },
+    { "GetFramerate", "unprobed" },
+    { "GetInstanceInfo", "unprobed" },
+    { "GetInventoryItemID", "plain [W PR13]" },
+    { "GetNetStats", "unprobed" },
+    { "GetNumClasses", "unprobed" },
+    { "GetNumGroupMembers", "unprobed" },
+    { "GetNumSubgroupMembers", "unprobed" },
+    { "GetRealmName", "unprobed" },
+    { "GetShapeshiftForm", "plain [W §4 (stance)]" },
+    { "GetShapeshiftFormInfo", "plain [W PR10]" },
+    { "GetSpecializationInfoByID", "unprobed" },
+    { "GetStablePetInfo", "unprobed" },
+    { "GetTime", "plain [W]" },
+    { "HasOverrideActionBar", "unprobed" },
+    { "HasVehicleActionBar", "unprobed" },
+    { "InCombatLockdown", "plain [W §3; lags at PLAYER_REGEN_DISABLED]" },
+    { "IsActionInRange", "plain [W PR7]" },
+    { "IsInGroup", "unprobed" },
+    { "IsInInstance", "unprobed" },
+    { "IsInJailersTower", "unprobed" },
+    { "IsInRaid", "unprobed" },
+    { "IsMounted", "unprobed" },
+    { "IsPlayerSpell", "unprobed" },
+    { "IsResting", "unprobed" },
+    { "IsSpellKnown", "unprobed" },
+    { "IsSpellKnownOrOverridesKnown", "unprobed" },
+    { "SecureCmdOptionParse", "unprobed" },
+    { "SpellIsSelfBuff", "unprobed" },
+    { "UnitAffectingCombat", "plain in combat [W PR14; gate spike]" },
+    { "UnitCanAssist", "unprobed" },
+    { "UnitCanAttack", "plain in combat [W PR14; gate spike]" },
+    { "UnitClass", "plain in combat [W PR14; gate spike]" },
+    { "UnitClassBase", "plain in combat [W PR14; gate spike]" },
+    { "UnitClassification", "plain in combat [W PR14; gate spike]" },
+    { "UnitCreatureType", "plain in combat [W PR14; gate spike]" },
+    { "UnitEffectiveLevel", "unprobed" },
+    { "UnitExists", "plain in combat [W PR14; gate spike]" },
+    { "UnitFactionGroup", "unprobed" },
+    { "UnitGUID", "plain in combat [W PR14; gate spike]" },
+    { "UnitHasVehicleUI", "unprobed" },
+    { "UnitInParty", "unprobed" },
+    { "UnitInRaid", "unprobed" },
+    { "UnitInVehicle", "unprobed" },
+    { "UnitIsConnected", "unprobed" },
+    { "UnitIsDead", "plain in combat [W PR14; gate spike]" },
+    { "UnitIsDeadOrGhost", "unprobed" },
+    { "UnitIsFriend", "plain in combat [W PR14; gate spike]" },
+    { "UnitIsPVP", "unprobed" },
+    { "UnitIsPlayer", "plain in combat [W PR14; gate spike]" },
+    { "UnitIsTrivial", "unprobed" },
+    { "UnitIsUnit", "plain in combat [W PR14; gate spike]" },
+    { "UnitLevel", "plain in combat [W PR14; gate spike]" },
+    { "UnitName", "plain in combat [W PR14; gate spike]" },
+    { "UnitOnTaxi", "unprobed" },
+    { "UnitPhaseReason", "unprobed" },
+    { "UnitPowerMax", "plain (100 for rage) [W PR16]" },
+    { "UnitPowerType", "plain [W PR16]" },
+    { "UnitRace", "unprobed" },
+    { "UnitSex", "unprobed" },
+    { "UnitThreatSituation", "plain in combat [W PR14; gate spike]" },
+    { "UnitTokenFromGUID", "unprobed" },
+}
+for i = 1, #PASSTHROUGH do
+    passthrough(PASSTHROUGH[i][1], PASSTHROUGH[i][2])
+end
 
 ----------------------------------------------------------------------------------------------------------------------
 
 table.sort(inventory)
-local stubs = {}
-for _, name in ipairs(inventory) do
-    if status[name] == "stub" then
-        stubs[#stubs + 1] = name
-    end
-end
 
 function Facade.Status(name)
     return status[name]
@@ -520,9 +719,6 @@ end
 function Facade.Why(name)
     return why[name]
 end
-function Facade.Stubs()
-    return stubs
-end
 function Facade.Inventory()
     return inventory
 end
diff --git a/tools/api_inventory.txt b/tools/api_inventory.txt
index 345f6e1b..d0e26d29 100644
--- a/tools/api_inventory.txt
+++ b/tools/api_inventory.txt
@@ -1,51 +1,176 @@
-AuraUtil.FindAura
-AuraUtil.ForEachAura
-C_Spell.GetSpellCastCount
-C_Spell.GetSpellCharges
-C_Spell.GetSpellCooldown
-C_Spell.GetSpellLossOfControlCooldown
-C_UnitAuras.GetAuraDataByAuraInstanceID
-C_UnitAuras.GetAuraSlots
-C_UnitAuras.GetBuffDataByIndex
-C_UnitAuras.GetDebuffDataByIndex
-C_UnitAuras.GetPlayerAuraBySpellID
-CombatLogGetCurrentEventInfo
-GetCombatRating
-GetCombatRatingBonus
-GetCritChance
-GetHaste
-GetItemGem
-GetItemInfo
-GetManaRegen
-GetMasteryEffect
-GetMeleeHaste
-GetPowerRegenForPowerType
-GetRangedCritChance
-GetSpellBaseCooldown
-GetSpellBonusDamage
-GetSpellCritChance
-GetSpellLink
-GetTalentInfoByID
-GetTotemInfo
-GetUnitSpeed
-IsHarmfulSpell
-IsHelpfulSpell
-IsPassiveSpell
-IsUsableSpell
-UnitArmor
-UnitAttackPower
-UnitAttackSpeed
-UnitAura
-UnitAuraBySlot
-UnitCastingInfo
-UnitChannelInfo
-UnitDamage
-UnitGetTotalAbsorbs
-UnitHealth
-UnitHealthMax
-UnitInRange
-UnitPartialPower
-UnitPower
-UnitSpellHaste
-UnitStat
-UnitWeaponAttackPower
+AuraUtil.FindAura	virtual
+AuraUtil.ForEachAura	virtual
+AuraUtil.UnpackAuraData	passthrough
+C_AddOns.GetAddOnMetadata	passthrough
+C_AddOns.IsAddOnLoaded	passthrough
+C_AddOns.LoadAddOn	passthrough
+C_ClassColor.GetClassColor	passthrough
+C_ClassTalents.GetActiveConfigID	passthrough
+C_ClassTalents.GetHeroTalentSpecsForClassSpec	passthrough
+C_Item.GetDetailedItemLevelInfo	passthrough
+C_Item.GetItemCooldown	passthrough
+C_Item.GetItemCount	passthrough
+C_Item.GetItemGem	passthrough
+C_Item.GetItemInfo	passthrough
+C_Item.GetItemInfoInstant	passthrough
+C_Item.GetItemSpell	passthrough
+C_Item.IsCurrentItem	passthrough
+C_Item.IsEquippedItem	passthrough
+C_Item.IsUsableItem	passthrough
+C_LossOfControl.GetActiveLossOfControlData	passthrough
+C_LossOfControl.GetActiveLossOfControlDataCount	passthrough
+C_PetBattles.IsInBattle	passthrough
+C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier	passthrough
+C_PvP.IsWarModeDesired	passthrough
+C_SpecializationInfo.GetSpecialization	passthrough
+C_SpecializationInfo.GetSpecializationInfo	passthrough
+C_SpecializationInfo.GetTalentInfo	passthrough
+C_Spell.GetSpellCastCount	virtual
+C_Spell.GetSpellCharges	hybrid
+C_Spell.GetSpellCooldown	hybrid
+C_Spell.GetSpellDescription	passthrough
+C_Spell.GetSpellInfo	passthrough
+C_Spell.GetSpellLossOfControlCooldown	virtual
+C_Spell.GetSpellPowerCost	passthrough
+C_Spell.GetSpellTexture	passthrough
+C_Spell.IsCurrentSpell	passthrough
+C_Spell.IsSpellDataCached	passthrough
+C_Spell.IsSpellHarmful	passthrough
+C_Spell.IsSpellHelpful	passthrough
+C_Spell.IsSpellPassive	passthrough
+C_Spell.IsSpellUsable	passthrough
+C_Spell.RequestLoadSpellData	passthrough
+C_SpellActivationOverlay.IsSpellOverlayed	passthrough
+C_SpellBook.FindSpellBookSlotForSpell	passthrough
+C_SpellBook.GetNumSpellBookSkillLines	passthrough
+C_SpellBook.GetSpellBookItemInfo	passthrough
+C_SpellBook.GetSpellBookSkillLineInfo	passthrough
+C_SpellBook.IsSpellInSpellBook	passthrough
+C_SpellBook.IsSpellKnown	passthrough
+C_Texture.GetAtlasInfo	passthrough
+C_TooltipInfo.GetInventoryItem	passthrough
+C_TooltipInfo.GetItemByID	passthrough
+C_TooltipInfo.GetSpellByID	passthrough
+C_Traits.GetConfigInfo	passthrough
+C_Traits.GetDefinitionInfo	passthrough
+C_Traits.GetEntryInfo	passthrough
+C_Traits.GetNodeCost	passthrough
+C_Traits.GetNodeInfo	passthrough
+C_Traits.GetSubTreeInfo	passthrough
+C_Traits.GetTreeCurrencyInfo	passthrough
+C_Traits.GetTreeNodes	passthrough
+C_UnitAuras.GetAuraDataByAuraInstanceID	virtual
+C_UnitAuras.GetAuraSlots	virtual
+C_UnitAuras.GetBuffDataByIndex	virtual
+C_UnitAuras.GetDebuffDataByIndex	virtual
+C_UnitAuras.GetPlayerAuraBySpellID	virtual
+C_VideoOptions.GetCurrentGameWindowSize	passthrough
+CombatLogGetCurrentEventInfo	virtual
+CreateFrame	virtual
+GetActionInfo	passthrough
+GetBindingKey	passthrough
+GetBuildInfo	passthrough
+GetCVar	passthrough
+GetClassInfo	passthrough
+GetCombatRating	hybrid
+GetCombatRatingBonus	hybrid
+GetCritChance	hybrid
+GetCursorInfo	passthrough
+GetFrameCPUUsage	passthrough
+GetFramerate	passthrough
+GetHaste	hybrid
+GetInstanceInfo	passthrough
+GetInventoryItemID	passthrough
+GetItemGem	virtual
+GetItemInfo	virtual
+GetManaRegen	hybrid
+GetMasteryEffect	hybrid
+GetMeleeHaste	hybrid
+GetNetStats	passthrough
+GetNumClasses	passthrough
+GetNumGroupMembers	passthrough
+GetNumSubgroupMembers	passthrough
+GetPowerRegenForPowerType	hybrid
+GetRangedCritChance	hybrid
+GetRealmName	passthrough
+GetShapeshiftForm	passthrough
+GetShapeshiftFormInfo	passthrough
+GetSpecializationInfoByID	passthrough
+GetSpellBaseCooldown	virtual
+GetSpellBonusDamage	hybrid
+GetSpellCritChance	hybrid
+GetSpellLink	virtual
+GetStablePetInfo	passthrough
+GetTalentInfoByID	virtual
+GetTime	passthrough
+GetTotemInfo	hybrid
+GetUnitSpeed	hybrid
+HasOverrideActionBar	passthrough
+HasVehicleActionBar	passthrough
+InCombatLockdown	passthrough
+IsActionInRange	passthrough
+IsHarmfulSpell	virtual
+IsHelpfulSpell	virtual
+IsInGroup	passthrough
+IsInInstance	passthrough
+IsInJailersTower	passthrough
+IsInRaid	passthrough
+IsMounted	passthrough
+IsPassiveSpell	virtual
+IsPlayerSpell	passthrough
+IsResting	passthrough
+IsSpellKnown	passthrough
+IsSpellKnownOrOverridesKnown	passthrough
+IsUsableSpell	passthrough
+SecureCmdOptionParse	passthrough
+SpellIsSelfBuff	passthrough
+UnitAffectingCombat	passthrough
+UnitArmor	hybrid
+UnitAttackPower	hybrid
+UnitAttackSpeed	hybrid
+UnitAura	virtual
+UnitAuraBySlot	virtual
+UnitCanAssist	passthrough
+UnitCanAttack	passthrough
+UnitCastingInfo	hybrid
+UnitChannelInfo	hybrid
+UnitClass	passthrough
+UnitClassBase	passthrough
+UnitClassification	passthrough
+UnitCreatureType	passthrough
+UnitDamage	hybrid
+UnitEffectiveLevel	passthrough
+UnitExists	passthrough
+UnitFactionGroup	passthrough
+UnitGUID	passthrough
+UnitGetTotalAbsorbs	virtual
+UnitHasVehicleUI	passthrough
+UnitHealth	virtual
+UnitHealthMax	virtual
+UnitInParty	passthrough
+UnitInRaid	passthrough
+UnitInRange	virtual
+UnitInVehicle	passthrough
+UnitIsConnected	passthrough
+UnitIsDead	passthrough
+UnitIsDeadOrGhost	passthrough
+UnitIsFriend	passthrough
+UnitIsPVP	passthrough
+UnitIsPlayer	passthrough
+UnitIsTrivial	passthrough
+UnitIsUnit	passthrough
+UnitLevel	passthrough
+UnitName	passthrough
+UnitOnTaxi	passthrough
+UnitPartialPower	virtual
+UnitPhaseReason	passthrough
+UnitPower	virtual
+UnitPowerMax	passthrough
+UnitPowerType	passthrough
+UnitRace	passthrough
+UnitSex	passthrough
+UnitSpellHaste	hybrid
+UnitStat	hybrid
+UnitThreatSituation	passthrough
+UnitTokenFromGUID	passthrough
+UnitWeaponAttackPower	hybrid
diff --git a/tools/check_api_reads.sh b/tools/check_api_reads.sh
index 9e6b0662..43ca8447 100755
--- a/tools/check_api_reads.sh
+++ b/tools/check_api_reads.sh
@@ -1,29 +1,24 @@
 #!/usr/bin/env bash
-# Fails when a file loaded by Hekili.toc reads a game API from tools/api_inventory.txt (the names that are secret in
-# combat, partly secret or absent on Forever) directly instead of through ns.Facade (VirtualState/Facade.lua). Bare
-# reads come from luacheck W113 (which ignores strings and comments); _G.Name and _G["Name"] reads, and dotted reads of
-# a kept namespace member (C_Spell.GetSpellCooldown: a declared namespace global hides its members from W113), come
-# from grep. VirtualState/ reads the game only through its injected `api` (VirtualState/spec/secrets_spec.lua checks
-# it); VirtualState/Facade.lua names every kept read in strings, so the dotted grep skips it.
+# Fails when a file loaded by Hekili.toc reads a game API from tools/api_inventory.txt directly instead of through
+# ns.Facade (VirtualState/Facade.lua; event-facade spec §1.2): every game read goes through the facade. Bare reads,
+# namespace globals included, come from luacheck W113 (which ignores strings and comments; a `local C_Spell =
+# Facade.C_Spell` covers its members); _G.Name and _G["Name"] reads come from grep, and so does a frame method reached
+# through getmetatable, the one way around the event facade's shadowed RegisterEvent. VirtualState/ reads the game
+# only through its injected `api` (VirtualState/spec/secrets_spec.lua checks it).
 set -uo pipefail
 cd "$(dirname "$0")/.."
 LUACHECK="${LUACHECK:-luacheck}"
 command -v "$LUACHECK" >/dev/null || { echo "luacheck not found: set LUACHECK" >&2; exit 1; }
 mapfile -t files < <(grep -E '\.lua\s*$' Hekili.toc | tr -d '\r' | sed 's/\\/\//g; s/[[:space:]]*$//')
-bare=$(grep -vF '.' tools/api_inventory.txt | paste -sd'|')
-dotted=$(grep -F '.' tools/api_inventory.txt | sed 's/\./\\./' | paste -sd'|')
+globals=$(cut -f1 tools/api_inventory.txt | sed -E 's/\..*//' | sort -u | paste -sd'|')
 fail=0
 out=$("$LUACHECK" --no-config --std none --formatter plain --codes "${files[@]}"); rc=$?
 [ $rc -ge 2 ] && { echo "luacheck failed (syntax error?)" >&2; exit 1; }
-hits=$(grep -E "accessing undefined variable '($bare)'" <<<"$out")
+hits=$(grep -E "accessing undefined variable '($globals)'" <<<"$out")
 [ -n "$hits" ] && { echo "$hits"; fail=1; }
-hits=$(grep -nE "_G(\.|\[[\"'])($bare)\b" "${files[@]}")
+hits=$(grep -nE "_G(\.|\[[\"'])($globals)\b" "${files[@]}")
 [ -n "$hits" ] && { echo "$hits"; fail=1; }
-# comments stripped, so a comment naming a kept read is not a read
-hits=$(for f in "${files[@]}"; do
-    [ "$f" = VirtualState/Facade.lua ] && continue
-    sed 's/--.*$//' "$f" | grep -nE "(^|[^.[:alnum:]_])($dotted)\b" | sed "s|^|$f:|"
-done)
+hits=$(grep -nE "getmetatable\(.*(Register|Unregister)[A-Za-z]*Event" "${files[@]}")
 [ -n "$hits" ] && { echo "$hits"; fail=1; }
-[ $fail -eq 0 ] && echo "ok: no direct secret or absent game API read in ${#files[@]} loaded files"
+[ $fail -eq 0 ] && echo "ok: no direct game API read in ${#files[@]} loaded files"
 exit $fail
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `154 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [154 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 67 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 44 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

Also: `grep -c . tools/api_inventory.txt` prints `176`; `cut -f2 tools/api_inventory.txt | sort | uniq -c` prints `24 hybrid`, `125 passthrough`, `27 virtual`.

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Facade.lua VirtualState/Adapter.lua VirtualState/EventFacade.lua tools/api_inventory.txt tools/check_api_reads.sh .luacheckrc Classes.lua Constants.lua Core.lua Events.lua Forever/Warrior.lua Formatting.lua Hekili.lua MultilineEditor.lua Options/ChatCommands.lua Options/DevTools.lua Options/Options.lua State.lua Targets.lua UI.lua Utils.lua VirtualState/spec/facade_spec.lua VirtualState/spec/alloc_spec.lua Forever/spec/helpers/load_warrior.lua
git commit -m "feat(virtualstate): the full read facade in three classes (125 passthrough, 24 hybrid, 27 virtual); every Hekili file reads the game and makes frames through ns.Facade; the tools enforce it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 3: UNIT_AURA's original handler restored

Phase A, spec §2.5, decision 2. Phase 1 neutered the player/target `UNIT_AURA` handler (`Events.lua:1259-1263`) because the client's payload is secret in combat. The layer now hands Hekili its own `{ isFullUpdate = true }` for the player and the target (Task 1), so the original body (`fc61b6d9:Events.lua:1265-1325`) comes back as it was: the full-update path wipes the instance table, walks both filters through `Facade.AuraUtil.ForEachAura` (already the local `ForEachAura`, `Events.lua:1250`), sets `state[ unit ].updated` and asks for `UNIT_AURA_FULL`. The incremental branches stay in the body and are dead until phase C's believed lists. Drain step 5 stays (spec §7). `Events.lua` cannot load headless; the payload is pinned by Task 1's `event_facade_spec` case "delivers UNIT_AURA with the layer's full update ..." and the body by CHECKPOINT A.

**Files:**
- Modify: `Events.lua` (the `UNIT_AURA` registration, :1259-1263)

**Interfaces:**
- Consumes: the layer's `UNIT_AURA` payload (Task 1).
- Produces: nothing new.

- [ ] **Step 1: Restore the body**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Events.lua b/Events.lua
index 9830f470..145c0bd2 100644
--- a/Events.lua
+++ b/Events.lua
@@ -1257,10 +1257,66 @@ do
         instanceDB[ aura.auraInstanceID ] = aura.isBossAura or aura.isStealable or model and ( model.shared or model.used and aura.isFromPlayerOrPlayerPet )
     end
 
-    -- Forever: the payload is secret in combat (a boolean test of data.isFullUpdate raises), so the handler no longer
-    -- reads it; VirtualState's drain sets state[ unit ].updated when that unit's believed auras changed (spec G1).
-    RegisterUnitEvent( "UNIT_AURA", "player", "target", function( event, unit )
-        Hekili:ForceUpdate( event )
+    RegisterUnitEvent( "UNIT_AURA", "player", "target", function( event, unit, data )
+        local isPlayer = ( unit == "player" )
+        instanceDB = isPlayer and playerInstances or targetInstances
+
+        if data.isFullUpdate then
+            wipe( instanceDB )
+
+            ForEachAura( unit, "HELPFUL", nil, StoreInstanceInfo, true )
+            ForEachAura( unit, "HARMFUL", nil, StoreInstanceInfo, true )
+
+            state[ unit ].updated = true
+            Hekili:ForceUpdate( "UNIT_AURA_FULL", true )
+            return
+        end
+
+        local forceUpdateNeeded = false
+
+        if data.addedAuras and #data.addedAuras > 0 then
+            for _, aura in ipairs( data.addedAuras ) do
+                local id = aura.spellId
+                local model = class.auras[ id ]
+
+                local ofConcern = aura.isBossAura or aura.isStealable or model and ( model.shared or model.used and aura.isFromPlayerOrPlayerPet )
+                instanceDB[ aura.auraInstanceID ] = ofConcern
+
+                if ofConcern then
+                    forceUpdateNeeded = true
+                end
+            end
+        end
+
+        if data.updatedAuraInstanceIDs and #data.updatedAuraInstanceIDs > 0 then
+            for _, instance in ipairs( data.updatedAuraInstanceIDs ) do
+                local aura = GetAuraDataByAuraInstanceID( unit, instance )
+                local ofConcern = false
+
+                if aura then
+                    local id = aura.spellId
+                    local model = class.auras[ id ]
+
+                    ofConcern = aura.isBossAura or aura.isStealable or model and ( model.shared or model.used and aura.isFromPlayerOrPlayerPet )
+                    instanceDB[ instance ] = ofConcern
+                end
+
+                if ofConcern then
+                    forceUpdateNeeded = true
+                end
+            end
+        end
+
+        if data.removedAuraInstanceIDs and #data.removedAuraInstanceIDs > 0 then
+            for _, instance in ipairs( data.removedAuraInstanceIDs ) do
+                if instanceDB[ instance ] then forceUpdateNeeded = true end
+                instanceDB[ instance ] = nil
+            end
+        end
+
+        state[ unit ].updated = true
+
+        if forceUpdateNeeded then Hekili:ForceUpdate( "UNIT_AURA_ITER" ) end
     end )
 
     RegisterEvent( "PLAYER_TARGET_CHANGED", function( event )
```

- [ ] **Step 2: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [154 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 67 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 44 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 3: Commit**

```bash
git add Events.lua
git commit -m "revert(events): UNIT_AURA's original handler; the event facade hands it a full-update payload for the player and the target

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 4: The trace through Hekili's snapshots

Phase A, spec §5, decisions 3, 4 and 8. No ring and no command: while Hekili makes a snapshot (`Hekili.ActiveDebug`, set by `Hekili:MakeSnapshot`, `Options/Options.lua:9671-9681`), every facade read writes one `Hekili:Debug` line into the display's snapshot log, `[vs] <class> <name>(<a1>, <a2>) -> <r1>, <r2>, <r3>, <r4> #<count>`, where a hybrid says whether the raw value (`hybrid:raw`) or the model (`hybrid:model`) answered; `GetTime` is counted, not written (`Facade.QUIET`); a secret is written `S` after `issecretvalue`, and a passthrough's secret answer is counted per name (`Facade.secrets`, a `Snapshot()` line). A table result is written as its scalars at call time (`aura:<spellId>/<expirationTime>/<applications>`, `cd:<startTime>/<duration>`): every field passes `issecretvalue` before it is compared or converted (a secret field is `S`; the client's tables reach the trace raw through the passthroughs). The whole line is built and written inside a function the trace calls through `pcall`, and `busy` is reset after it on every path, so a strange value or a raising `Hekili:Debug` never reaches the read and never silences the trace. Every row, whatever its class, sits behind one wrapper built in `kept` (decision 4): off, one field test. The event facade writes `[vs] event <name>(...)` per client event during a snapshot. `Adapter.lua` attaches the addon table (`Facade.Attach(Hekili)`) and wraps `Hekili:SetupDebug` so each display's snapshot log opens with `VirtualState.Snapshot()`.

**Files:**
- Modify: `VirtualState/Facade.lua` (the row wrapper and the trace before `kept`; `passthrough` stores the raw function; `pick`, the cooldown, charges and cast hybrids mark the model's answer; a `Snapshot()` line), `VirtualState/EventFacade.lua` (`onEvent`), `VirtualState/Adapter.lua` (after `Hekili.VirtualState = VS`)
- Create: `VirtualState/spec/trace_spec.lua`

**Interfaces:**
- Consumes: `Hekili.ActiveDebug`, `Hekili:Debug`, `Hekili.SetupDebug` (`Hekili.lua:206-256`, `:229`).
- Produces: `Facade.Attach(hekili)`, `I.hekili`, `Facade.secrets`, `Facade.counts`, `Facade.QUIET`; `Snapshot()`'s line `facade secret passthrough answers: none | Name=n ...`.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/trace_spec.lua b/VirtualState/spec/trace_spec.lua
new file mode 100644
index 00000000..eddbc9fe
--- /dev/null
+++ b/VirtualState/spec/trace_spec.lua
@@ -0,0 +1,110 @@
+-- VirtualState/spec/trace_spec.lua (event-facade spec §5, decisions 3 and 8): while Hekili makes a snapshot
+-- (`ActiveDebug`), every facade read and every event writes one line through Hekili:Debug, naming the class that
+-- answered; a secret is shown as S and counted for a passthrough; off, nothing is written and nothing allocated.
+local load = require("VirtualState.spec.helpers.load")
+local fake = require("VirtualState.spec.helpers.fake_api")
+local alloc = require("VirtualState.spec.helpers.alloc")
+local fs = require("VirtualState.spec.helpers.fake_spec")
+
+describe("the facade trace", function()
+    local api, ctl, ns, Facade, lines, hekili, saved
+
+    before_each(function()
+        api, ctl = fake.new()
+        saved = {}
+        local globals = {
+            CreateFrame = api.CreateFrame,
+            issecretvalue = api.issecretvalue,
+            GetTime = api.GetTime,
+            UnitName = function(unit)
+                if unit == "target" then
+                    return fake.SECRET
+                end
+                return "Me"
+            end,
+            GetHaste = function()
+                return fake.SECRET
+            end,
+            GetInstanceInfo = function()
+                return { spellId = fake.SECRET, expirationTime = 5 }, { startTime = fake.SECRET, duration = 1 }
+            end,
+        }
+        for k, v in pairs(globals) do
+            saved[k] = rawget(_G, k) or false
+            _G[k] = v
+        end
+        ns = load.module()
+        Facade = ns.Facade
+        lines = {}
+        hekili = { ActiveDebug = false }
+        function hekili:Debug(fmt, ...)
+            lines[#lines + 1] = string.format(fmt, ...)
+        end
+        Facade.Attach(hekili)
+        ns.VirtualStateInternal.Build(fs.def(fs.new(9)), 1)
+        ns.VirtualState.Start(api)
+    end)
+
+    after_each(function()
+        for k, v in pairs(saved) do
+            _G[k] = v or nil
+        end
+    end)
+
+    it("writes nothing while Hekili is not debugging", function()
+        Facade.UnitName("player")
+        ctl.Fire("PLAYER_TARGET_CHANGED")
+        assert.are.same({}, lines)
+    end)
+
+    it("writes one line per read naming the class, with a secret shown as S and counted", function()
+        hekili.ActiveDebug = true
+        Facade.UnitName("player")
+        Facade.UnitName("target")
+        Facade.GetHaste()
+        Facade.UnitPower("target", 1)
+        Facade.GetTime()
+        assert.are.same({
+            "[vs] passthrough UnitName(player, nil) -> Me, nil, nil, nil #1",
+            "[vs] passthrough UnitName(target, nil) -> S, nil, nil, nil #1",
+            "[vs] hybrid:model GetHaste(nil, nil) -> 0, nil, nil, nil #1",
+            "[vs] virtual UnitPower(target, 1) -> 0, nil, nil, nil #1",
+        }, lines) -- GetTime is quiet: counted, not written
+        assert.are.equal(1, Facade.secrets.UnitName)
+        assert.are.equal(1, Facade.counts.GetTime)
+    end)
+
+    it("writes a table result's secret fields as S, and keeps tracing after a raising Debug", function()
+        hekili.ActiveDebug = true
+        Facade.GetInstanceInfo()
+        assert.are.same({ "[vs] passthrough GetInstanceInfo(nil, nil) -> aura:S/5/nil, cd:S/1, nil, nil #2" }, lines)
+        local debug = hekili.Debug
+        hekili.Debug = function()
+            error("boom")
+        end
+        assert.has_no.errors(function()
+            Facade.UnitName("player")
+        end)
+        hekili.Debug = debug
+        Facade.UnitName("player")
+        assert.are.equal("[vs] passthrough UnitName(player, nil) -> Me, nil, nil, nil #1", lines[#lines])
+    end)
+
+    it("writes a line per event the layer receives", function()
+        local f = ns.VirtualStateInternal.Events.CreateFrame("Frame")
+        f:SetScript("OnEvent", function() end)
+        f:RegisterEvent("PLAYER_TARGET_CHANGED")
+        hekili.ActiveDebug = true
+        ctl.Fire("PLAYER_TARGET_CHANGED", fake.SECRET)
+        assert.are.same({ "[vs] event PLAYER_TARGET_CHANGED(nil, nil, nil)" }, lines)
+    end)
+
+    it("allocates nothing per read while tracing is off", function()
+        local bytes = alloc.bytes(function()
+            Facade.UnitName("player")
+            Facade.GetHaste()
+            Facade.UnitPower("player", 1)
+        end, 10000)
+        assert.are.equal(0, bytes)
+    end)
+end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `154 successes / 0 failures / 5 errors` (`trace_spec.lua:43: attempt to call field 'Attach' (a nil value)`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index 553a11bb..cb50d466 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -27,6 +27,19 @@ end
 -- The debug handle: /run print(Hekili.VirtualState.Snapshot())
 Hekili.VirtualState = VS
 
+-- The trace (event-facade spec §5): facade reads and events write into Hekili's snapshot while it debugs, and each
+-- display's snapshot log opens with VirtualState's own Snapshot().
+ns.Facade.Attach(Hekili)
+do
+    local setupDebug = Hekili.SetupDebug
+    function Hekili:SetupDebug(display)
+        setupDebug(self, display)
+        if self.ActiveDebug and display then
+            self:Debug("%s", VS.Snapshot())
+        end
+    end
+end
+
 -- The urgent lane (spec §4.4): shortens Hekili's wait before its next cycle; never interrupts one.
 I.urgent = function(event)
     Hekili:ForceUpdate(event)
diff --git a/VirtualState/EventFacade.lua b/VirtualState/EventFacade.lua
index bc4722ae..5a3b19ea 100644
--- a/VirtualState/EventFacade.lua
+++ b/VirtualState/EventFacade.lua
@@ -187,6 +187,10 @@ local function onEvent(_, event, r1, r2, r3, r4, r5, r6, r7, r8)
     if I.api then
         S.Run(api, event, a1, a2, a3, a4, a5)
     end
+    local h = I.hekili -- the trace (§5): one line per event while Hekili makes a snapshot
+    if h and h.ActiveDebug then
+        pcall(h.Debug, h, "[vs] event %s(%s, %s, %s)", event, tostring(a1), tostring(a2), tostring(a3))
+    end
     local list = SUB[event]
     if not list then
         return
diff --git a/VirtualState/Facade.lua b/VirtualState/Facade.lua
index e356ee44..581db446 100644
--- a/VirtualState/Facade.lua
+++ b/VirtualState/Facade.lua
@@ -40,6 +40,78 @@ local function resolve(name)
     return _G[key]
 end
 
+local GetTime = resolve("GetTime")
+local issecretvalue = resolve("issecretvalue") or function()
+    return false
+end
+
+----------------------------------------------------------------------------------------------------------------------
+-- The trace (event-facade spec §5, decision 3): while Hekili makes a snapshot (`Hekili.ActiveDebug`), every facade
+-- read writes one line through Hekili:Debug into the snapshot: the class that answered (a hybrid says whether the
+-- raw value or the model did), the name, two arguments and four results, a secret shown as S. Off, a read costs one
+-- field test. Facade.Attach(Hekili) (Adapter.lua) names the addon table; until then nothing is traced.
+
+local hk = { ActiveDebug = false }
+function Facade.Attach(hekili)
+    hk, I.hekili = hekili, hekili
+end
+
+local busy, modelled = false, false
+Facade.secrets = {} -- by name: secret answers from a passthrough while tracing (a misfiled name, E11)
+Facade.QUIET = { GetTime = true } -- read so often it would bury the snapshot: counted, not written
+Facade.counts = {} -- by name: reads while tracing
+
+-- A value as trace text: S for a secret, scalars of a table copied now (never the shared table, whose values change
+-- later), each field tested with issecretvalue before it is compared or converted.
+local function field(v)
+    if issecretvalue(v) then
+        return "S"
+    end
+    return tostring(v)
+end
+
+local function show(v)
+    if issecretvalue(v) then
+        return "S"
+    elseif type(v) ~= "table" then
+        return tostring(v)
+    end
+    local id, start = v.spellId, v.startTime
+    if issecretvalue(id) or id ~= nil then
+        return "aura:" .. field(id) .. "/" .. field(v.expirationTime) .. "/" .. field(v.applications)
+    elseif issecretvalue(start) or start ~= nil then
+        return "cd:" .. field(start) .. "/" .. field(v.duration)
+    end
+    return "table"
+end
+
+-- One trace line (run through pcall: a raising Debug or a strange value never reaches the read).
+local function write(name, kind, a1, a2, n, r1, r2, r3, r4)
+    Facade.counts[name] = (Facade.counts[name] or 0) + 1
+    if kind == "passthrough" then
+        if issecretvalue(r1) or issecretvalue(r2) or issecretvalue(r3) or issecretvalue(r4) then
+            Facade.secrets[name] = (Facade.secrets[name] or 0) + 1
+        end
+    elseif kind == "hybrid" then
+        kind = modelled and "hybrid:model" or "hybrid:raw"
+    end
+    if not Facade.QUIET[name] then
+        hk:Debug("[vs] %s %s(%s, %s) -> %s, %s, %s, %s #%d", kind, name, show(a1), show(a2), show(r1), show(r2),
+            show(r3), show(r4), n)
+    end
+end
+
+local function traced(name, kind, a1, a2, ...)
+    if not busy then
+        busy = true
+        local r1, r2, r3, r4 = ...
+        pcall(write, name, kind, a1, a2, select("#", ...), r1, r2, r3, r4)
+        busy = false -- every path: pcall returns whatever write did
+    end
+    return ...
+end
+
+-- Every row is stored behind one wrapper that traces it while Hekili debugs (decision 4: one branch when off).
 local function kept(name, kind, fn, reason)
     local nsName, key = split(name)
     local t = Facade
@@ -47,15 +119,17 @@ local function kept(name, kind, fn, reason)
         Facade[nsName] = Facade[nsName] or {}
         t = Facade[nsName]
     end
-    t[key] = fn
+    t[key] = function(...)
+        if hk.ActiveDebug then
+            local a1, a2 = ...
+            modelled = false
+            return traced(name, kind, a1, a2, fn(...))
+        end
+        return fn(...)
+    end
     inventory[#inventory + 1] = name
     status[name], why[name] = kind, reason
 end
-
-local GetTime = resolve("GetTime")
-local issecretvalue = resolve("issecretvalue") or function()
-    return false
-end
 local realUnitPowerType = resolve("UnitPowerType")
 local realUnitIsDead = resolve("UnitIsDead")
 local realGetSpellCooldown = resolve("C_Spell.GetSpellCooldown")
@@ -65,7 +139,7 @@ local realUnitCastingInfo = resolve("UnitCastingInfo")
 local realUnitChannelInfo = resolve("UnitChannelInfo")
 local realGetSpellCharges = resolve("C_Spell.GetSpellCharges")
 
---- A passthrough: the raw function, wrapped once at load so a later finding changes one row, not Hekili. A name the
+--- A passthrough: the raw function behind the row's wrapper, so a later finding changes one row, not Hekili. A name the
 --- client lacks (the deprecation shims while `loadDeprecationFallbacks` is off) answers nothing and is virtual.
 local function passthrough(name, reason)
     local real = resolve(name)
@@ -73,14 +147,13 @@ local function passthrough(name, reason)
         kept(name, "virtual", function() end, "absent on this client; answers nothing (" .. reason .. ")")
         return
     end
-    kept(name, "passthrough", function(...)
-        return real(...)
-    end, reason)
+    kept(name, "passthrough", real, reason)
 end
 
 -- The raw answer, or the policy's when any of its first four values is secret. Allocates nothing.
 local function pick(policy, x, y, z, a, b, c, d, ...)
     if issecretvalue(a) or issecretvalue(b) or issecretvalue(c) or issecretvalue(d) then
+        modelled = true
         return policy(x, y, z)
     end
     return a, b, c, d, ...
@@ -481,6 +554,7 @@ kept("C_Spell.GetSpellCooldown", "hybrid", function(spellID)
     if plainTimes(info, "startTime", "duration") then
         return info
     end
+    modelled = true
     return cooldownPolicy(spellID)
 end, "times secret in combat, flags plain [W PR4, PR11]; Cooldown(), GcdInfo()")
 
@@ -506,6 +580,7 @@ kept("C_Spell.GetSpellCharges", "hybrid", function(spellID)
     if plainTimes(info, "cooldownStartTime", "cooldownDuration") then
         return info
     end
+    modelled = true
     return chargesPolicy(spellID)
 end, "times secret in combat [W §4 cooldowns]; Charges()")
 
@@ -526,6 +601,7 @@ kept("UnitCastingInfo", "hybrid", function(unit, ...)
     elseif unit ~= "target" then
         return nil
     end
+    modelled = true
     local channel, castBarID, start, kick = VS.TargetCastFacts()
     local rec = channel == false and VS.TargetCast(now())
     if not rec then
@@ -543,6 +619,7 @@ kept("UnitChannelInfo", "hybrid", function(unit, ...)
     elseif unit ~= "target" then
         return nil
     end
+    modelled = true
     local channel, _, start, kick = VS.TargetCastFacts()
     local rec = channel == true and VS.TargetCast(now())
     if not rec then
@@ -722,3 +799,13 @@ end
 function Facade.Inventory()
     return inventory
 end
+
+-- Snapshot's line: what the trace counted (allocates; debugging only).
+I.OnSnapshot(function(out)
+    local parts = {}
+    for name, n in pairs(Facade.secrets) do
+        parts[#parts + 1] = name .. "=" .. n
+    end
+    table.sort(parts)
+    out[#out + 1] = "facade secret passthrough answers: " .. (#parts > 0 and table.concat(parts, " ") or "none")
+end)
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `159 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [159 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 68 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 44 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Facade.lua VirtualState/EventFacade.lua VirtualState/Adapter.lua VirtualState/spec/trace_spec.lua
git commit -m "feat(virtualstate): the facade trace through Hekili's snapshots: one Hekili:Debug line per read and per event naming the answering class; secret passthrough answers counted; Snapshot() heads each display's log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 5: CHECKPOINT A: the full facade in game

No code. The orchestrator presents this checkpoint; the user runs the game on the Warrior at a training dummy, ForeverProbe loaded (`VSCopy`). `Hekili.toc` lists a new file, so the client restarts once.

- [ ] **Step 0: The baseline first** (before the branch's TOC is ever loaded): the orchestrator runs `git -C ~/src/hekili checkout --detach 75d71c8b`; the user restarts the client and runs the line of item 3 and the two lines of item 6 below, and keeps the three answers.

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin virtualstate-event-facade
git -C ~/src/hekili checkout --detach virtualstate-event-facade
```

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, and report each answer**

1. Restart the client, log in. Expected: no Lua error, no "Interface action failed because of an AddOn" or "Blizzard UI only" popup.
2. Out of combat: `/run VSCopy(Hekili.VirtualState.Snapshot())`, paste the box. Expected, among the lines: `events delivered=<n> errors=0 stubs=[]` and `facade secret passthrough answers: none`.
3. Every Hekili event still arrives: `/run local t={} for k in pairs(Hekili.EData) do t[#t+1]=k end table.sort(t) VSCopy(table.concat(t," "))` after a minute of targeting, casting and moving. Expected: the same keys as the same line on `forever` (baseline, item 7 below), e.g. `PLAYER_TARGET_CHANGED_1`, `SPELLS_CHANGED_1`, `UNIT_POWER_FREQUENT_1`; no `COMBAT_LOG_EVENT_UNFILTERED_1` (no rows in phase A).
4. The trace: out of combat `/hekili snapshot`, then `/hekili` → Snapshots → the newest. Expected: the log's second line (after Hekili's own "New Recommendations for [...]") starts the Snapshot block `VirtualState t=...`, then `[vs] passthrough ...` lines (e.g. `UnitExists(target, nil) -> true`) and `[vs] hybrid:raw GetHaste(...)`. In combat at the dummy, another snapshot. Expected: `[vs] hybrid:model GetHaste(...)`, `[vs] virtual UnitPower(player, 1) -> <rage>`, and no passthrough line with an `S` result. Report any `S` in a passthrough line (its name) and the snapshot's rough size.
5. `UNIT_AURA` in combat: cast Battle Shout and Rend on the dummy, then `/run local s=Hekili.State VSCopy(format("%s %s",tostring(s.buff.battle_shout.up),tostring(s.debuff.rend.up)))`. Expected: `true true`, and no Lua error during the fight.
6. The drain and the cycle in combat (60 s of the Arms priority at the dummy): `/run VSCopy(Hekili.VirtualState.Snapshot():match("drain=[%d.]+ms"))` and `/run local u=Hekili.Engine.threadUpdates VSCopy(format("work %.2f ms frames %.1f",u.meanWorkTime,u.meanFrames))`. Expected: the drain 0.1-0.5 ms (CHECKPOINT 4 of Phase 1).
7. Compare items 3 and 6 with the Step 0 baseline.

| # | Answer → action (each action its own commit with the verification block) |
|---|---|
| 1 | A Lua error → report its first line and stack; an "AddOn action" popup → a frame the facade shadowed is protected: report its name (the template list of Task 2 missed it) |
| 2 | `errors=<n>` above 0 → `/run VSCopy(Hekili.VirtualState.Snapshot():match("events [^\n]+"))` (the line ends with `last error=...`) and report; a stub listed → that event's name is unknown to the client: report which file registers it |
| 3 | A key missing against the baseline → that event no longer reaches Hekili: report it (a subscription the layer dropped). `COMBAT_LOG_EVENT_UNFILTERED_1` present → a row reached Hekili in phase A: report the Snapshot's `rows` line (there should be none before Task 6) |
| 4 | No `[vs]` lines or no Snapshot block → the trace is not attached: report the snapshot's first five lines. An `S` in a passthrough line → that name is secret in that state: move it to `hybrid` in `VirtualState/Facade.lua` with the Phase 1 or a new policy, and its class in `tools/api_inventory.txt` and `facade_spec`'s counts |
| 5 | `false` for either → report the Snapshot's `aura` lines (the full-update path did not rescan) |
| 6 | `meanWorkTime` above the baseline by more than 5 % → spec E1: report both numbers; the user decides between keeping the always-on wrapper and giving the hottest names the raw function (decision 4) |

Fix what the user reports, then repeat the affected items. Continue only when the user confirms.

---

### Task 6: The combat-log rows: pool, delivery and back-dating; own casts; the cast feeds retired

Phase B, spec §2.4, §3, §4, decision 5. `VirtualState/CombatLog.lua` keeps a pool of 64 rows (each a fixed table of 24 slots plus its time, family and provenance; `L.Emit(sub, last, t, backdate, family, prov, src, srcFlags, dst, dstFlags)` fills slots 1-11 and returns the row for slots 12 on; a full pool drops the oldest, counted). `L.Deliver()` delivers queued rows oldest first as `COMBAT_LOG_EVENT_UNFILTERED` with no payload through the event facade's `E.Deliver` (the subscriber loop of Task 1, now a function), never nested: a row emitted during a delivery follows the current one (counted `requeued`). It runs at the end of each client event and at the layer's `OnUpdate` after the flush and the deferred lane (`L.Tick` runs the functions registered with `L.OnTick`: Task 7's pairing windows, Task 9's modelled expiries), and never inside a coroutine (`coroutine.running()`: a client event fired synchronously inside `Hekili.Update`'s coroutine leaves its rows for the `OnUpdate`, spec §3). A full pool drops the oldest row; during a delivery, when only the delivered row's slot is left, the new row is dropped instead, so the row being read is never overwritten. An own-cast row needs a numeric spell ID (no nil hole). While a back-dated row is delivered, `I.backdate` holds its slot 1, which `Facade.GetTime` (now a hybrid) answers; `Facade.CombatLogGetCurrentEventInfo` (virtual) returns `unpack(row, 1, row.n)` during a delivery and nothing outside one.

The own-cast rows replace the Phase 1 feeds in the same task (spec §7, E4): `Sources/Casts.lua` emits `SPELL_CAST_START` (destination the sent target's GUID or `""`; Hekili's handler falls back to the target), `SPELL_CAST_SUCCESS`, `SPELL_CAST_FAILED` (failedType `""`) and a channel's `SPELL_AURA_REMOVED` on us, each observed and back-dated to its event, and reads the player's GUID at `Start` and `PLAYER_ENTERING_WORLD`; `Adapter.lua`'s `I.feed.CastSucceeded`, `CastStart`, `CastFailed`, `ChannelStart` and `ChannelStop` are deleted. `Events.lua`'s two registration lines lose their combat-log skip (`fc61b6d9`'s originals): Hekili's `COMBAT_LOG_EVENT_UNFILTERED` subscription now reaches the layer, which never registers it with the client. Flags are the layer's constants: ours `0x511`, a hostile's `0xA48`; names `""`.

**Files:**
- Create: `VirtualState/CombatLog.lua`, `VirtualState/spec/cleu_rows_spec.lua`
- Modify: `VirtualState/EventFacade.lua` (`deliver`/`E.Deliver`, `onEvent`, `onUpdate`), `VirtualState/Facade.lua` (`GetTime` hybrid, `CombatLogGetCurrentEventInfo`, `GetTime` out of the passthrough list), `VirtualState/Sources/Casts.lua` (header, the player's GUID, rows instead of feeds), `VirtualState/Adapter.lua` (header; the five cast feeds), `Events.lua` (:174, :197), `Hekili.toc` (after `VirtualState\EventFacade.lua`), `tools/api_inventory.txt` (`GetTime hybrid`)
- Test: `VirtualState/spec/alloc_spec.lua` (a combat-log subscriber, so the rows ride along in the 0-byte loop), `VirtualState/spec/adapter_spec.lua` (the feed case becomes "leaves the cast history ... to the combat-log rows"; the hard-cast and channel cases lose their queue asserts; the nil-target case moves to `cleu_rows_spec`), `VirtualState/spec/facade_spec.lua` (counts 124/25/27)

**Interfaces:**
- Consumes: `E` (Task 1), `Facade`'s `kept`/`modelled` (Task 4).
- Produces: `I.Log` (`L`): `L.Emit`, `L.Cast(sub, t, spellID, dstGUID)`, `L.Deliver()`, `L.Current()`, `L.Tick(now)`, `L.OnTick(fn(now))`, `L.POOL`, `L.PLAYER_FLAGS`, `L.HOSTILE_FLAGS`, `L.player`, `L.emitted`, `L.delivered`, `L.requeued`, `L.dropped`, `L.counts[family]`; `I.backdate`; `E.Deliver(event, ...)`; `Snapshot()`'s line `rows emitted=... delivered=... requeued=... dropped=... cast=... swing=... missed=... damage=... onus=... aura=... energize=...`.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/adapter_spec.lua b/VirtualState/spec/adapter_spec.lua
index d6b015fc..56139a10 100644
--- a/VirtualState/spec/adapter_spec.lua
+++ b/VirtualState/spec/adapter_spec.lua
@@ -1,5 +1,5 @@
 -- VirtualState/spec/adapter_spec.lua: Adapter.lua against the fake spec provider (spec §3.6, §4.6, §5): the tracked
--- set from the registrations, the across-reset feeds, and Drain's apply through the spec (the read-before /
+-- set from the registrations, the swing feed, and Drain's apply through the spec (the read-before /
 -- read-after diff as `modelled` samples, two full resets, the offset restored, `updated` marked). The apply against
 -- the real `state` is verified in game (spec §11).
 local load = require("VirtualState.spec.helpers.load")
@@ -104,18 +104,15 @@ describe("Adapter", function()
         assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
     end)
 
-    it("feeds the cast history and the real queue from our own cast events, and asks for a cycle", function()
+    it("leaves the cast history and the real queue to the combat-log rows, asks for a cycle, feeds the swing", function()
         ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
-        assert.are.same({ "rend" }, state.history)
-        assert.are.same({ "rend:CAST_FINISH" }, state.removed)
-        assert.are.same({ "UNIT_SPELLCAST_SUCCEEDED" }, h.forced)
-        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2", fs.REND) -- never STARTed: the source ignores it
-        assert.are.same({ "rend:CAST_FINISH" }, state.removed)
         ctl.casting = { 1000, 2500 }
         ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", fs.REND)
-        assert.are.same({ "rend:CAST_FINISH" }, state.queue)
         ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-3", fs.REND)
-        assert.are.same({ "rend:CAST_FINISH", "rend:CAST_FINISH" }, state.removed)
+        assert.are.same({}, state.history) -- CLEU_HANDLER writes them from the rows (cleu_rows_spec)
+        assert.are.same({}, state.removed)
+        assert.are.same({}, state.queue)
+        assert.are.same({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_FAILED" }, h.forced)
         ctl.Fire("PLAYER_SWING", 2.6, 0)
         assert.are.same({ 1, 3.6 }, { state.swings.mh_actual, state.swings.mh_projected })
     end)
@@ -163,12 +160,10 @@ describe("Adapter", function()
         ctl.now = 10
         ctl.casting = { 10000, 11500 }
         ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", 1464)
-        assert.are.same({ "slam_test:CAST_FINISH" }, state.queue) -- the real queue's finish, as CLEU queued it
         ctl.Tick(10.05)
         ctl.now = 11.5
         ctl.casting = nil
         ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 1464)
-        assert.are.same({ "slam_test:CAST_FINISH" }, state.removed) -- removed on success
         ctl.Tick(11.55)
         ctl.now = 11.6
         VS.Drain(11.6)
@@ -179,7 +174,7 @@ describe("Adapter", function()
         assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
     end)
 
-    it("applies a channel at its start and feeds its finish and ticks; CHANNEL_STOP removes them", function()
+    it("applies a channel at its start", function()
         local ran = false
         register("drain_test", {
             id = 5555,
@@ -196,10 +191,6 @@ describe("Adapter", function()
         ctl.now = 20
         ctl.channel = { 20000, 23000 }
         ctl.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 5555)
-        assert.are.same(
-            { "drain_test:CHANNEL_FINISH", "drain_test:CHANNEL_TICK", "drain_test:CHANNEL_TICK" },
-            state.queue
-        )
         ctl.Tick(20.05)
         ctl.now = 20.1
         VS.Drain(20.1)
@@ -208,8 +199,6 @@ describe("Adapter", function()
         near(30, cd.est) -- the cooldown step at the channel's start
         assert.are.equal("modelled", cd.basis)
         assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
-        ctl.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", 5555)
-        assert.are.same({ "drain_test:all" }, state.removed)
     end)
 
     it("folds a swing staged this frame before poll 3 clears the queued strike: the swing is skipped as paid", function()
@@ -333,27 +322,6 @@ describe("Adapter", function()
         assert.are.same({ 2, false, false }, { state.resets, state.player.updated, state.target.updated })
     end)
 
-    it("queues a hard cast's finish with a nil target when the sent GUID is unknown, reading no GUID", function()
-        register("slam_test", { id = 1464, cast = 1.5, cooldown = 0 })
-        VS.SpecChanged()
-        local target, calls = false, 0
-        function state:QueueEvent(key, start, finish, eType, guid)
-            target = guid
-        end
-        local unitGUID = api.UnitGUID
-        api.UnitGUID = function(unit)
-            calls = calls + 1
-            return unitGUID(unit)
-        end
-        I.sentGUID = nil
-        ctl.now = 50
-        ctl.casting = { 50000, 51500 }
-        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-7", 1464)
-        api.UnitGUID = unitGUID
-        assert.is_nil(target)
-        assert.are.equal(0, calls)
-    end)
-
     it("runs no reset when the log holds no own cast", function()
         ctl.now = 3
         VS.Drain(3)
diff --git a/VirtualState/spec/alloc_spec.lua b/VirtualState/spec/alloc_spec.lua
index 99176104..140da2b6 100644
--- a/VirtualState/spec/alloc_spec.lua
+++ b/VirtualState/spec/alloc_spec.lua
@@ -1,6 +1,6 @@
 -- VirtualState/spec/alloc_spec.lua (spec §2, §11): 10,000 mixed events (PLAYER_SWING, UNIT_POWER_FREQUENT,
 -- usability, own casts, UNIT_AURA) with a drain every tick against the fake spec, every accessor and every facade
--- policy and passthrough called: VirtualState allocates nothing.
+-- policy and passthrough called, every combat-log row delivered to a subscriber: VirtualState allocates nothing.
 local load = require("VirtualState.spec.helpers.load")
 local fake = require("VirtualState.spec.helpers.fake_api")
 local fs = require("VirtualState.spec.helpers.fake_spec")
@@ -48,6 +48,12 @@ describe("zero allocation", function()
             return false
         end
         load.adapter(ns, h)
+        local sink = I.Events.CreateFrame("Frame") -- a combat-log subscriber: the rows ride along
+        local GetInfo = Facade.CombatLogGetCurrentEventInfo
+        sink:SetScript("OnEvent", function()
+            GetInfo()
+        end)
+        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
         VS.Start(api)
         VS.SpecChanged()
         ctl.auras.player.HELPFUL[1] = { spellId = fs.SHOUT, expirationTime = 1e9, applications = 0 }
diff --git a/VirtualState/spec/cleu_rows_spec.lua b/VirtualState/spec/cleu_rows_spec.lua
new file mode 100644
index 00000000..6ae54062
--- /dev/null
+++ b/VirtualState/spec/cleu_rows_spec.lua
@@ -0,0 +1,192 @@
+-- VirtualState/spec/cleu_rows_spec.lua (event-facade spec §2.4, §3, §4): the synthesized combat log. Each row reaches
+-- a COMBAT_LOG_EVENT_UNFILTERED subscriber after the client event that completed it, with the slot table's tuple (no
+-- nil up to its last slot, so ns.callHook's rebuild keeps it whole), and with Facade.GetTime answering the row's
+-- observed time while it is delivered.
+local load = require("VirtualState.spec.helpers.load")
+local fake = require("VirtualState.spec.helpers.fake_api")
+local alloc = require("VirtualState.spec.helpers.alloc")
+local fs = require("VirtualState.spec.helpers.fake_spec")
+
+describe("the synthesized combat log", function()
+    local api, ctl, ns, VS, I, L, Facade, saved, got, order, cleu
+
+    -- ns.callHook's rebuild (Classes.lua:2858-2877): load_args into a wiped table, then unpack( vars ).
+    local function viaCallHook(...)
+        local vars = {}
+        for i = 1, select("#", ...) do
+            vars[i] = select(i, ...)
+        end
+        return #vars, vars
+    end
+
+    before_each(function()
+        api, ctl = fake.new()
+        saved = {}
+        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
+            saved[k] = rawget(_G, k) or false
+            _G[k] = v
+        end
+        ns = load.module()
+        VS, I, Facade = ns.VirtualState, ns.VirtualStateInternal, ns.Facade
+        L = I.Log
+        I.Build(fs.def(fs.new(9)), 1)
+        VS.Start(api)
+        got, order = {}, 0
+        cleu = I.Events.CreateFrame("Frame") -- CLEU_HANDLER's registration (Events.lua)
+        cleu:SetScript("OnEvent", function(_, event, ...)
+            order = order + 1
+            local n, vars = viaCallHook(Facade.CombatLogGetCurrentEventInfo())
+            got[#got + 1] = { event = event, args = select("#", ...), n = n, row = vars, now = Facade.GetTime(), at = order }
+        end)
+        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+    end)
+
+    after_each(function()
+        for k, v in pairs(saved) do
+            _G[k] = v or nil
+        end
+    end)
+
+    it("emits SPELL_CAST_SUCCESS after the cast event's subscribers, in the client's shape", function()
+        local seen
+        local f = I.Events.CreateFrame("Frame")
+        f:SetScript("OnEvent", function()
+            order = order + 1
+            seen = order
+        end)
+        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
+        ctl.now = 10
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
+        assert.are.equal(1, #got)
+        local r = got[1]
+        assert.are.equal("COMBAT_LOG_EVENT_UNFILTERED", r.event)
+        assert.are.equal(0, r.args) -- no payload, as the client delivers it
+        assert.are.equal(14, r.n) -- no nil up to the last slot
+        assert.are.same(
+            { 10, "SPELL_CAST_SUCCESS", false, "Player-1", "", L.PLAYER_FLAGS, 0, "Creature-1", "", L.HOSTILE_FLAGS, 0, fs.REND, "", 1 },
+            r.row
+        )
+        assert.is_true(seen < r.at)
+        assert.is_nil(Facade.CombatLogGetCurrentEventInfo()) -- nothing outside a delivery
+    end)
+
+    it("emits SPELL_CAST_START with an empty target when the sent GUID is unknown, reading no GUID", function()
+        local calls, unitGUID = 0, api.UnitGUID
+        api.UnitGUID = function(unit)
+            calls = calls + 1
+            return unitGUID(unit)
+        end
+        I.sentGUID = nil
+        ctl.casting = { 50000, 51500 }
+        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-7", fs.REND)
+        api.UnitGUID = unitGUID
+        assert.are.equal(0, calls)
+        assert.are.equal("SPELL_CAST_START", got[1].row[2])
+        assert.are.equal("", got[1].row[8])
+        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-7", fs.REND)
+        assert.are.same({ "SPELL_CAST_FAILED", 15, "" }, { got[2].row[2], got[2].n, got[2].row[15] })
+    end)
+
+    it("ends a channel with its SPELL_AURA_REMOVED on us", function()
+        ctl.channel = { 20000, 23000 }
+        ctl.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", fs.REND)
+        assert.are.equal(0, #got) -- its success row comes from UNIT_SPELLCAST_SUCCEEDED
+        ctl.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-4", fs.REND)
+        assert.are.same({ "SPELL_AURA_REMOVED", "Player-1", 16, "BUFF", 0 }, {
+            got[1].row[2],
+            got[1].row[8],
+            got[1].n,
+            got[1].row[15],
+            got[1].row[16],
+        })
+    end)
+
+    it("answers a back-dated row's time from Facade.GetTime while it is delivered, the clock after", function()
+        local r = L.Emit("SWING_DAMAGE", 21, 7.25, true, "swing", "observed", "Player-1", 1, "Creature-1", 2)
+        for k = 12, 21 do
+            r[k] = 0
+        end
+        ctl.now = 7.4
+        L.Deliver()
+        assert.are.equal(7.25, got[1].now)
+        assert.are.equal(7.4, Facade.GetTime())
+        L.Emit("SPELL_CAST_SUCCESS", 14, 7.3, false, "cast", "modelled", "Player-1", 1, "", 1)
+        L.Deliver()
+        assert.are.equal(7.4, got[2].now) -- a purely modelled row is stamped at delivery
+    end)
+
+    it("delivers a row emitted during a delivery after the current one, never nested, and counts it", function()
+        local depth, maxDepth = 0, 0
+        local f = I.Events.CreateFrame("Frame")
+        f:SetScript("OnEvent", function()
+            depth = depth + 1
+            maxDepth = math.max(maxDepth, depth)
+            if #got == 1 then
+                L.Cast("SPELL_CAST_SUCCESS", 2, fs.SHOUT, "")
+            end
+            depth = depth - 1
+        end)
+        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+        L.Cast("SPELL_CAST_SUCCESS", 1, fs.REND, "")
+        L.Deliver()
+        assert.are.equal(2, #got)
+        assert.are.equal(fs.SHOUT, got[2].row[12])
+        assert.are.equal(1, maxDepth)
+        assert.are.equal(1, L.requeued)
+    end)
+
+    it("drops the oldest row when the pool is full, and counts it", function()
+        for i = 1, L.POOL + 6 do
+            L.Cast("SPELL_CAST_SUCCESS", i, fs.REND, "")
+        end
+        L.Deliver()
+        assert.are.equal(L.POOL, #got)
+        assert.are.equal(7, got[1].row[1])
+        assert.are.equal(6, L.dropped)
+    end)
+
+    it("keeps the row being delivered intact when the pool fills during its delivery", function()
+        local seen
+        local f = I.Events.CreateFrame("Frame")
+        f:SetScript("OnEvent", function()
+            if not seen then
+                seen = "pending"
+                for i = 1, L.POOL do
+                    L.Cast("SPELL_CAST_SUCCESS", 100 + i, fs.SHOUT, "")
+                end
+                seen = select(12, Facade.CombatLogGetCurrentEventInfo())
+            end
+        end)
+        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+        L.Cast("SPELL_CAST_SUCCESS", 1, fs.REND, "")
+        L.Deliver()
+        assert.are.equal(fs.REND, seen)
+        assert.are.equal(1, L.dropped) -- 64 emitted into 63 free slots: the last one gave way
+    end)
+
+    it("makes no row without a spell ID, and delivers nothing inside a coroutine", function()
+        L.Cast("SPELL_CAST_SUCCESS", 1, nil, "")
+        assert.are.equal(0, L.emitted)
+        L.Cast("SPELL_CAST_SUCCESS", 2, fs.REND, "")
+        coroutine.wrap(L.Deliver)() -- Hekili.Update's coroutine
+        assert.are.equal(0, #got)
+        L.Deliver()
+        assert.are.equal(1, #got)
+    end)
+
+    it("allocates nothing per row emitted and delivered", function()
+        local sink = I.Events.CreateFrame("Frame")
+        local GetInfo = Facade.CombatLogGetCurrentEventInfo
+        sink:SetScript("OnEvent", function()
+            GetInfo()
+        end)
+        sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- the capturing one allocates by design
+        local bytes = alloc.bytes(function(i)
+            ctl.now = i
+            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
+            I.Sources.Flush()
+        end, 10000)
+        assert.are.equal(0, bytes)
+    end)
+end)
diff --git a/VirtualState/spec/facade_spec.lua b/VirtualState/spec/facade_spec.lua
index 96ac1504..29d068fc 100644
--- a/VirtualState/spec/facade_spec.lua
+++ b/VirtualState/spec/facade_spec.lua
@@ -116,7 +116,7 @@ describe("ns.Facade", function()
             assert.is_function(entry(n), n)
             assert.is_string(Facade.Why(n), n)
         end
-        assert.are.same({ passthrough = 125, hybrid = 24, virtual = 27 }, count)
+        assert.are.same({ passthrough = 124, hybrid = 25, virtual = 27 }, count)
         assert.is_nil(Facade.Status("NotAGameFunction"))
     end)
 
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `157 successes / 3 failures / 7 errors` (`cleu_rows_spec`: `attempt to index upvalue 'L' (a nil value)` and no row captured; `adapter_spec.lua:112`: the feeds still write the history; `facade_spec.lua:119`: `GetTime` is still a passthrough).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Events.lua b/Events.lua
index 145c0bd2..d6dbddc5 100644
--- a/Events.lua
+++ b/Events.lua
@@ -171,8 +171,7 @@ ns.RegisterEvent = function( event, handler )
     handlers[ event ] = handlers[ event ] or {}
     insert( handlers[ event ], handler )
 
-    -- Forever forbids CLEU registration on addon frames; Phase 3b delivers a virtual combat log to the handler.
-    if event ~= "FRAME_UPDATE" and event ~= "COMBAT_LOG_EVENT_UNFILTERED" then events:RegisterEvent( event ) end
+    if event ~= "FRAME_UPDATE" then events:RegisterEvent( event ) end
 
     local key = event .. "_" .. #handlers[event]
     Hekili:ProfileCPU( key, handler )
@@ -195,7 +194,7 @@ ns.UnregisterEvent = function( event, handler )
         end
     end
 
-    if #hands == 0 and event ~= "COMBAT_LOG_EVENT_UNFILTERED" then events:UnregisterEvent( event ) end
+    if #hands == 0 then events:UnregisterEvent( event ) end
 end
 local UnregisterEvent = ns.UnregisterEvent
 
diff --git a/Hekili.toc b/Hekili.toc
index cbc49894..bda1d634 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -35,6 +35,7 @@ VirtualState\Sources\Totems.lua
 VirtualState\Snapshot.lua
 VirtualState\AplWarnings.lua
 VirtualState\EventFacade.lua
+VirtualState\CombatLog.lua
 VirtualState\Facade.lua
 
 Hekili.lua
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index cb50d466..fbff9cb6 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -1,8 +1,8 @@
 -- VirtualState/Adapter.lua
 -- VirtualState's glue to Hekili (spec §3.6, §4.6, §5): VirtualState.Start at PLAYER_LOGIN, the tracked set from the
--- active spec's registrations (SpecChanged), the across-reset feeds (cast history, the real queue's cast and
--- channel events, the swing fields), and Drain: the fold plus "apply through the spec", which runs each of our real
--- casts through Hekili's own registered functions on `state` and records what changed as `modelled` samples.
+-- active spec's registrations (SpecChanged), the swing feed (the swing fields), and Drain: the fold plus "apply
+-- through the spec", which runs each of our real casts through Hekili's own registered functions on `state` and records
+-- what changed as `modelled` samples.
 -- Loads after Core.lua. The apply follows Hekili's own simulation (Core.lua:1984-2045) and keeps Hekili's credits.
 
 local addon, ns = ...
@@ -218,64 +218,6 @@ end
 ----------------------------------------------------------------------------------------------------------------------
 -- Feeding Hekili's across-reset caches (spec §4.6), synchronously in VirtualState's handlers, where CLEU did it.
 
-local function abilityOf(a)
-    local key = I.ab.key[a]
-    return key, key and class.abilities[key]
-end
-
-I.feed.CastSucceeded = function(a, spellID, guid)
-    local key, ability = abilityOf(a)
-    if not ability then
-        return
-    end
-    state:RemoveSpellEvent(key, true, "CAST_FINISH") -- as CLEU SPELL_CAST_SUCCESS (Events.lua:1613-1614)
-    state:AddToHistory(key, guid) -- the only writer of the cast history (Events.lua:912-943)
-end
-
-I.feed.CastStart = function(a, start, finish, guid)
-    local key, ability = abilityOf(a)
-    if ability and not ability.channeled then
-        -- as CLEU SPELL_CAST_START (Events.lua:1579); UNIT_SPELLCAST_DELAYED re-queues it (Events.lua:1076-1089).
-        -- `guid` is nil when the target's GUID was secret or absent: never read it here (it may be secret).
-        state:QueueEvent(key, start, finish, "CAST_FINISH", guid, true)
-    end
-end
-
-I.feed.CastFailed = function(a)
-    local key, ability = abilityOf(a)
-    if not ability then
-        return
-    end
-    -- as CLEU SPELL_CAST_FAILED (Events.lua:1603-1606)
-    if state:RemoveSpellEvent(key, true, "CAST_FINISH") and ability.isProjectile then
-        state:RemoveSpellEvent(key, true, "PROJECTILE_IMPACT", true)
-    end
-end
-
-I.feed.ChannelStart = function(a, start, finish, guid)
-    local key, ability = abilityOf(a)
-    if not ability then
-        return
-    end
-    -- as CLEU SPELL_CAST_SUCCESS of a channel (Events.lua:1627-1635)
-    state:QueueEvent(key, start, finish, "CHANNEL_FINISH", guid, true)
-    local tickTime = ability.tick_time or (ability.aura and class.auras[ability.aura].tick_time)
-    if tickTime and tickTime > 0 then
-        local tick = tickTime
-        while start + tick < finish do
-            state:QueueEvent(key, start, start + tick, "CHANNEL_TICK", guid, true)
-            tick = tick + tickTime
-        end
-    end
-end
-
-I.feed.ChannelStop = function(a)
-    local key, ability = abilityOf(a)
-    if ability then
-        state:RemoveSpellEvents(key, true) -- ticks, finish, impacts (Events.lua:1609-1610)
-    end
-end
-
 -- The swing fields the dead CLEU SWING_* branch wrote (Events.lua:1684-1699), read by the swing regen models.
 I.feed.Swing = function(hand, t, duration)
     local sw = state.swings
diff --git a/VirtualState/CombatLog.lua b/VirtualState/CombatLog.lua
new file mode 100644
index 00000000..68c906d3
--- /dev/null
+++ b/VirtualState/CombatLog.lua
@@ -0,0 +1,158 @@
+-- VirtualState/CombatLog.lua
+-- The synthesized combat log (event-facade spec §2.4, §3, §4): rows in the client's positional shape, emitted by the
+-- sources from plain signals into a 64-row pool, delivered as COMBAT_LOG_EVENT_UNFILTERED (no payload) to the event
+-- facade's subscribers after the client event that completed them, or at the next OnUpdate; the facade's
+-- CombatLogGetCurrentEventInfo returns the row being delivered. A row with an observed basis carries the observed
+-- time in slot 1 and is back-dated: Facade.GetTime answers that time while the row is delivered (decision 5).
+-- Credits: the slot layout is the client's combat log (warcraft.wiki.gg COMBAT_LOG_EVENT); the plain signals behind
+-- each row follow Taco Dog Forever's research (docs/research/2026-10-14-virtual-combat-log-events.md).
+
+local _, ns = ...
+local VS, I = ns.VirtualState, ns.VirtualStateInternal
+local unpack = unpack
+
+local L = {}
+I.Log = L
+
+L.POOL = 64
+L.PLAYER_FLAGS = 0x511 -- mine, friendly, player
+L.HOSTILE_FLAGS = 0xA48 -- outsider, hostile, NPC
+
+local rows = {}
+for i = 1, L.POOL do
+    local r = { n = 0, t = 0, backdate = false, family = "", prov = "" }
+    for k = 1, 24 do
+        r[k] = false
+    end
+    rows[i] = r
+end
+local head, count = 1, 0
+-- the row a dropped emission fills in (its caller still writes slots 12 on): never queued
+local spare = { n = 0, t = 0, backdate = false, family = "", prov = "" }
+local delivering, current = false, nil
+
+L.emitted, L.dropped, L.requeued, L.delivered = 0, 0, 0, 0
+L.counts = { cast = 0, swing = 0, missed = 0, damage = 0, onus = 0, aura = 0, energize = 0 }
+
+-- The player's plain GUID (rows' source), read by Sources/Casts.lua at Start and on PLAYER_ENTERING_WORLD.
+L.player = ""
+
+--- Queues one row and returns it for its slots 12 on; `last` is its last slot (no nil up to it: ns.callHook rebuilds
+--- the tuple with unpack). A full pool drops the oldest undelivered row (counted); during a delivery, when only the
+--- delivered row's slot is left, the new row is dropped instead. Allocates nothing.
+function L.Emit(sub, last, t, backdate, family, prov, srcGUID, srcFlags, dstGUID, dstFlags)
+    if delivering then
+        L.requeued = L.requeued + 1 -- delivered after the current row, never nested (ns.callHook drops nested ones)
+    end
+    local r
+    if delivering and count >= L.POOL - 1 then
+        -- the row being delivered still holds the slot after the queue: the new row gives way, never that one
+        L.dropped = L.dropped + 1
+        r = spare
+    else
+        if count == L.POOL then
+            head = head % L.POOL + 1
+            count = count - 1
+            L.dropped = L.dropped + 1
+        end
+        r = rows[(head + count - 1) % L.POOL + 1]
+        count = count + 1
+    end
+    r[1], r[2], r[3], r[4], r[5], r[6], r[7] = t, sub, false, srcGUID, "", srcFlags, 0
+    r[8], r[9], r[10], r[11] = dstGUID, "", dstFlags, 0
+    r.n, r.t, r.backdate, r.family, r.prov = last, t, backdate, family, prov
+    L.emitted = L.emitted + 1
+    L.counts[family] = L.counts[family] + 1
+    return r
+end
+
+-- The last slot of each own-cast row (event-facade spec §2.4's table).
+local CAST_LAST = { SPELL_CAST_START = 14, SPELL_CAST_SUCCESS = 14, SPELL_CAST_FAILED = 15, SPELL_AURA_REMOVED = 16 }
+
+--- An own-cast row (observed): our spell `spellID` at `t` on `dstGUID` ("" none). A channel's end is its
+--- SPELL_AURA_REMOVED on us.
+function L.Cast(sub, t, spellID, dstGUID)
+    if type(spellID) ~= "number" then
+        return -- no nil hole in slot 12
+    end
+    local dst = dstGUID or ""
+    local flags = L.HOSTILE_FLAGS
+    if dst == "" or dst == L.player then
+        flags = L.PLAYER_FLAGS
+    end
+    local r = L.Emit(sub, CAST_LAST[sub], t, true, "cast", "observed", L.player, L.PLAYER_FLAGS, dst, flags)
+    r[12], r[13], r[14] = spellID, "", 1
+    if sub == "SPELL_CAST_FAILED" then
+        r[15] = "" -- failedType
+    elseif sub == "SPELL_AURA_REMOVED" then
+        r[15], r[16] = "BUFF", 0
+    end
+end
+
+--- Delivers every queued row, oldest first, to the combat log's subscribers; a row emitted meanwhile follows the
+--- current one. Runs at the end of each client event and at each OnUpdate, never inside a coroutine (Hekili.Update's:
+--- a client event fired synchronously there waits for the OnUpdate, spec §3). Allocates nothing.
+function L.Deliver()
+    if delivering or count == 0 or coroutine.running() then
+        return
+    end
+    delivering = true
+    local h = I.hekili
+    while count > 0 do
+        local r = rows[head]
+        head = head % L.POOL + 1
+        count = count - 1
+        current = r
+        if r.backdate then
+            I.backdate = r.t
+        end
+        if h and h.ActiveDebug then
+            pcall(h.Debug, h, "[vs] row %s %s %s t=%.3f", r[2], r.family, r.prov, r.t)
+        end
+        I.Events.Deliver("COMBAT_LOG_EVENT_UNFILTERED")
+        I.backdate = nil
+        L.delivered = L.delivered + 1
+    end
+    current = nil
+    delivering = false
+end
+
+--- The row being delivered, as the client's CombatLogGetCurrentEventInfo returns it; nothing outside a delivery.
+function L.Current()
+    local r = current
+    if r then
+        return unpack(r, 1, r.n)
+    end
+end
+
+-- The deferred lane: functions run at every OnUpdate with the clock (pairing windows, modelled expiries).
+local TICKS = {}
+function L.OnTick(fn)
+    TICKS[#TICKS + 1] = fn
+end
+
+--- Runs the deferred lane at `now` (the event facade's OnUpdate, before it delivers). Allocates nothing.
+function L.Tick(now)
+    for k = 1, #TICKS do
+        TICKS[k](now)
+    end
+end
+
+--- Snapshot's line: the rows (allocates; debugging only).
+I.OnSnapshot(function(out)
+    local c = L.counts
+    out[#out + 1] = string.format(
+        "rows emitted=%d delivered=%d requeued=%d dropped=%d cast=%d swing=%d missed=%d damage=%d onus=%d aura=%d energize=%d",
+        L.emitted,
+        L.delivered,
+        L.requeued,
+        L.dropped,
+        c.cast,
+        c.swing,
+        c.missed,
+        c.damage,
+        c.onus,
+        c.aura,
+        c.energize
+    )
+end)
diff --git a/VirtualState/EventFacade.lua b/VirtualState/EventFacade.lua
index 5a3b19ea..cea60f3f 100644
--- a/VirtualState/EventFacade.lua
+++ b/VirtualState/EventFacade.lua
@@ -177,27 +177,13 @@ function E.CreateFrame(...)
     return f
 end
 
--- One client event: (1) the sources (once Start has run), (2) the payload, (3) every matching subscriber in
--- subscription order, through its current OnEvent script. Each slot is gated into a local, so a nested client event
--- is delivered in its own call with its own values. Allocates nothing.
-local function onEvent(_, event, r1, r2, r3, r4, r5, r6, r7, r8)
-    local api = I.api or client
-    local a1, a2, a3, a4 = Plain(api, r1), Plain(api, r2), Plain(api, r3), Plain(api, r4)
-    local a5, a6, a7, a8 = Plain(api, r5), Plain(api, r6), Plain(api, r7), Plain(api, r8)
-    if I.api then
-        S.Run(api, event, a1, a2, a3, a4, a5)
-    end
-    local h = I.hekili -- the trace (§5): one line per event while Hekili makes a snapshot
-    if h and h.ActiveDebug then
-        pcall(h.Debug, h, "[vs] event %s(%s, %s, %s)", event, tostring(a1), tostring(a2), tostring(a3))
-    end
+-- Calls every subscriber of `event` whose units match, in subscription order, through its current OnEvent script; a
+-- raising handler is reported and the loop goes on. Allocates nothing.
+local function deliver(event, a1, a2, a3, a4, a5, a6, a7, a8)
     local list = SUB[event]
     if not list then
         return
     end
-    if event == "UNIT_AURA" then
-        a2 = AURA_INFO[a1]
-    end
     for k = 1, list.n do -- a subscription made during this delivery starts with the next event
         local f = list.f[k]
         if f then
@@ -206,7 +192,12 @@ local function onEvent(_, event, r1, r2, r3, r4, r5, r6, r7, r8)
                 local fn = f:GetScript("OnEvent")
                 if fn then
                     E.delivered = E.delivered + 1
-                    local ok, err = pcall(fn, f, event, a1, a2, a3, a4, a5, a6, a7, a8)
+                    local ok, err
+                    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
+                        ok, err = pcall(fn, f, event) -- no payload, as the client delivers it
+                    else
+                        ok, err = pcall(fn, f, event, a1, a2, a3, a4, a5, a6, a7, a8)
+                    end
                     if not ok then
                         E.errors, E.lastError = E.errors + 1, err
                         local handler = client.geterrorhandler
@@ -219,9 +210,36 @@ local function onEvent(_, event, r1, r2, r3, r4, r5, r6, r7, r8)
         end
     end
 end
+E.Deliver = deliver
+
+-- One client event: (1) the sources (once Start has run), (2) the payload, (3) every matching subscriber, (4) the
+-- combat-log rows it completed (CombatLog.lua). Each slot is gated into a local, so a nested client event is
+-- delivered in its own call with its own values. Allocates nothing.
+local function onEvent(_, event, r1, r2, r3, r4, r5, r6, r7, r8)
+    local api = I.api or client
+    local a1, a2, a3, a4 = Plain(api, r1), Plain(api, r2), Plain(api, r3), Plain(api, r4)
+    local a5, a6, a7, a8 = Plain(api, r5), Plain(api, r6), Plain(api, r7), Plain(api, r8)
+    if I.api then
+        S.Run(api, event, a1, a2, a3, a4, a5)
+    end
+    local h = I.hekili -- the trace (§5): one line per event while Hekili makes a snapshot
+    if h and h.ActiveDebug then
+        pcall(h.Debug, h, "[vs] event %s(%s, %s, %s)", event, tostring(a1), tostring(a2), tostring(a3))
+    end
+    if event == "UNIT_AURA" then
+        a2 = AURA_INFO[a1]
+    end
+    deliver(event, a1, a2, a3, a4, a5, a6, a7, a8)
+    I.Log.Deliver()
+end
 
 local function onUpdate()
     S.Flush()
+    local api = I.api
+    if api then
+        I.Log.Tick(api.GetTime()) -- closes pairing windows (deferred rows)
+    end
+    I.Log.Deliver()
 end
 
 local function makeFrame(createFrame)
diff --git a/VirtualState/Facade.lua b/VirtualState/Facade.lua
index 581db446..da30a0fa 100644
--- a/VirtualState/Facade.lua
+++ b/VirtualState/Facade.lua
@@ -631,7 +631,7 @@ end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")
 ----------------------------------------------------------------------------------------------------------------------
 -- Combat log, talents, spells and items: absent on Forever, or replaced
 
-kept("CombatLogGetCurrentEventInfo", "virtual", nothing, "absent; registering CLEU is forbidden (Phases 2 and 3)")
+kept("CombatLogGetCurrentEventInfo", "virtual", I.Log.Current, "absent; the row being delivered (event-facade §2.4)")
 kept("GetTalentInfoByID", "virtual", nothing, "dead on Forever [W PR5]; ranks come from VirtualState.Talent")
 kept("IsUsableSpell", "passthrough", function(spellID)
     if realIsSpellUsable then
@@ -647,6 +647,18 @@ kept("IsPassiveSpell", "virtual", isFalse, "absent on Forever")
 kept("GetItemGem", "virtual", nothing, "absent on Forever")
 kept("GetItemInfo", "virtual", nothing, "absent on Forever")
 
+----------------------------------------------------------------------------------------------------------------------
+-- The clock: the client's, except while a back-dated row is delivered (event-facade spec §3, decision 5)
+
+kept("GetTime", "hybrid", function()
+    local b = I.backdate
+    if b then
+        modelled = true
+        return b
+    end
+    return GetTime()
+end, "plain [W]; a back-dated combat-log row's observed time while it is delivered")
+
 ----------------------------------------------------------------------------------------------------------------------
 -- Frames: the event facade's entry point (event-facade spec §2.1)
 
@@ -732,7 +744,6 @@ local PASSTHROUGH = {
     { "GetShapeshiftFormInfo", "plain [W PR10]" },
     { "GetSpecializationInfoByID", "unprobed" },
     { "GetStablePetInfo", "unprobed" },
-    { "GetTime", "plain [W]" },
     { "HasOverrideActionBar", "unprobed" },
     { "HasVehicleActionBar", "unprobed" },
     { "InCombatLockdown", "plain [W §3; lags at PLAYER_REGEN_DISABLED]" },
diff --git a/VirtualState/Sources/Casts.lua b/VirtualState/Sources/Casts.lua
index 770bff13..f05de333 100644
--- a/VirtualState/Sources/Casts.lua
+++ b/VirtualState/Sources/Casts.lua
@@ -1,7 +1,8 @@
 -- VirtualState/Sources/Casts.lua
--- Own-cast sources (spec §4.2, §4.6): our UNIT_SPELLCAST_* events become staged observations (urgent lane) and,
--- synchronously in the handler, feed Hekili's across-reset caches through the hooks Adapter.lua sets in `I.feed`
--- (cast history, the real queue's CAST_FINISH and channel events, their removal). Poll 3: the on-next-swing queue.
+-- Own-cast sources (spec §4.2; event-facade spec §2.4): our UNIT_SPELLCAST_* events become staged observations
+-- (urgent lane) and the combat log's own-cast rows (SPELL_CAST_START, _SUCCESS, _FAILED, a channel's
+-- SPELL_AURA_REMOVED), which Hekili's CLEU handler turns into its cast history and real queue as on retail. Poll 3:
+-- the on-next-swing queue.
 -- Credits: secret-value handling after Catnip's (Durts) research.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Casts.lua (castGUID matching: castStopped, isChannel).
 
@@ -13,6 +14,12 @@ local Plain, Stage, Direct, Urgent = S.Plain, S.Stage, S.Direct, S.Urgent
 
 I.sentGUID = nil
 
+local function readPlayer(api)
+    I.Log.player = Plain(api, api.UnitGUID("player")) or ""
+end
+S.OnStart(readPlayer)
+S.On("PLAYER_ENTERING_WORLD", nil, readPlayer)
+
 -- The castGUIDs of our cast and channel in progress (plain strings; nil none or secret). Only these stop, delay or
 -- update them: a second press that fails ("another action is in progress") has another castGUID.
 local castGUID, chanGUID = nil, nil
@@ -37,10 +44,7 @@ S.On("UNIT_SPELLCAST_START", "player", function(api, t, unit, guid, spellID)
     local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
     if type(start) == "number" and type(finish) == "number" then
         Stage(Obs.CastStart, t, a, finish / 1000)
-        local f = I.feed.CastStart
-        if f then
-            f(a, start / 1000, finish / 1000, I.sentGUID)
-        end
+        I.Log.Cast("SPELL_CAST_START", t, spellID, I.sentGUID) -- "" when unknown: CLEU falls back to the target
     end
     Urgent("UNIT_SPELLCAST_START")
 end)
@@ -51,10 +55,7 @@ S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spel
         return
     end
     Stage(Obs.CastSuccess, t, a)
-    local f = I.feed.CastSucceeded
-    if f then
-        f(a, spellID, I.sentGUID or Plain(api, api.UnitGUID("target")))
-    end
+    I.Log.Cast("SPELL_CAST_SUCCESS", t, spellID, I.sentGUID or Plain(api, api.UnitGUID("target")))
     I.sentGUID = nil
     Urgent("UNIT_SPELLCAST_SUCCEEDED")
 end)
@@ -67,10 +68,7 @@ local function stopped(api, t, unit, guid, spellID)
     end
     castGUID = nil
     Stage(Obs.CastStop, t, a)
-    local f = I.feed.CastFailed
-    if f then
-        f(a)
-    end
+    I.Log.Cast("SPELL_CAST_FAILED", t, spellID, nil)
     Urgent("UNIT_SPELLCAST_FAILED")
 end
 S.On("UNIT_SPELLCAST_FAILED", "player", stopped)
@@ -98,11 +96,7 @@ S.On("UNIT_SPELLCAST_CHANNEL_START", "player", function(api, t, unit, guid, spel
     local _, _, _, rawStart, rawEnd = api.UnitChannelInfo("player") -- secret: both through Plain next
     local start, finish = Plain(api, rawStart), Plain(api, rawEnd)
     if type(start) == "number" and type(finish) == "number" then
-        Stage(Obs.ChannelStart, t, a, finish / 1000)
-        local f = I.feed.ChannelStart
-        if f then
-            f(a, start / 1000, finish / 1000, I.sentGUID or Plain(api, api.UnitGUID("target")))
-        end
+        Stage(Obs.ChannelStart, t, a, finish / 1000) -- its SPELL_CAST_SUCCESS row comes from UNIT_SPELLCAST_SUCCEEDED
     end
     Urgent("UNIT_SPELLCAST_CHANNEL_START")
 end)
@@ -135,10 +129,7 @@ S.On("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(api, t, unit, guid, spell
         return
     end
     Stage(Obs.ChannelStop, t, a)
-    local f = I.feed.ChannelStop
-    if f then
-        f(a)
-    end
+    I.Log.Cast("SPELL_AURA_REMOVED", t, spellID, I.Log.player)
     Urgent("UNIT_SPELLCAST_CHANNEL_STOP")
 end)
 
diff --git a/tools/api_inventory.txt b/tools/api_inventory.txt
index d0e26d29..b049f967 100644
--- a/tools/api_inventory.txt
+++ b/tools/api_inventory.txt
@@ -102,7 +102,7 @@ GetSpellCritChance	hybrid
 GetSpellLink	virtual
 GetStablePetInfo	passthrough
 GetTalentInfoByID	virtual
-GetTime	passthrough
+GetTime	hybrid
 GetTotemInfo	hybrid
 GetUnitSpeed	hybrid
 HasOverrideActionBar	passthrough
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `167 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [167 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 70 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 45 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/CombatLog.lua VirtualState/EventFacade.lua VirtualState/Facade.lua VirtualState/Sources/Casts.lua VirtualState/Adapter.lua Events.lua Hekili.toc tools/api_inventory.txt VirtualState/spec/cleu_rows_spec.lua VirtualState/spec/adapter_spec.lua VirtualState/spec/facade_spec.lua VirtualState/spec/alloc_spec.lua
git commit -m "feat(virtualstate): the synthesized combat log: a 64-row pool delivered as COMBAT_LOG_EVENT_UNFILTERED, back-dated through Facade.GetTime; own-cast rows replace the cast feeds; Hekili's CLEU registration restored

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 7: Our swings and abilities on the target; the swing feed retired

Phase B, spec §2.4 ("Our swings", "Our ability missed", "Damage we deal" on the target), §3 (pairing window). `VirtualState/Sources/Rows.lua` holds our pending actions (`PLAYER_SWING` with its hand; our `UNIT_SPELLCAST_SUCCEEDED` of an ability that starts combat or strikes on the next swing) and the target's pending outcomes (`UNIT_COMBAT` for the token `target`: `WOUND` or a miss type), 8 each, and pairs them in either order within `L.PAIR_WINDOW` (0.2 s, spec §3's `PAIR_WINDOW_MS` until CHECKPOINT B measures it): `SWING_DAMAGE` (amount, critical, glancing, crushing, isOffHand; last slot 21), `SWING_MISSED` (missType, isOffHand; last 15), `SPELL_DAMAGE` (last 24), `SPELL_MISSED` (missType in slot 15; last 18), inferred, at the earlier event's time, back-dated, destination the target's GUID at the action; with no target GUID no row is made (a `""` destination would be counted as an enemy by `ns.updateTarget`). An on-next-swing strike's success takes its swing's place in either order (the swing makes no row: a pending main-hand swing is removed, or the next one within the window is skipped). A function registered with `L.OnTick` (Task 6's deferred lane) closes windows: an unpaired swing becomes `SWING_DAMAGE` with amount 0 at its own time; an unpaired cast or outcome is dropped. Combat end clears both buffers. The swing feed is retired in the same task: `Sources/Swing.lua` no longer calls `I.feed.Swing`, `Adapter.lua`'s feed goes, and `I.feed` with it; Hekili's `CLEU_HANDLER` writes `state.swings.*` from the rows at their observed time (`Events.lua:1622-1637`).

**Files:**
- Create: `VirtualState/Sources/Rows.lua`
- Modify: `VirtualState/Sources/Swing.lua` (header, the feed call), `VirtualState/Sources/Sources.lua` (`I.feed`), `VirtualState/Adapter.lua` (header, the swing feed), `Hekili.toc` (after `VirtualState\CombatLog.lua`)
- Test: `VirtualState/spec/cleu_rows_spec.lua` (describe "our swings and abilities on the target"), `VirtualState/spec/adapter_spec.lua` (the swing field stays 0)

**Interfaces:**
- Consumes: `L.Emit`, `L.player`, `L.HOSTILE_FLAGS` (Task 6); `I.ab.bySpell`, `I.ab.obj` (Phase 1).
- Produces: `L.PAIR_WINDOW`; `I.feed` removed. Consumes also `L.OnTick` (Task 6).

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/adapter_spec.lua b/VirtualState/spec/adapter_spec.lua
index 56139a10..88ed0ce9 100644
--- a/VirtualState/spec/adapter_spec.lua
+++ b/VirtualState/spec/adapter_spec.lua
@@ -104,7 +104,7 @@ describe("Adapter", function()
         assert.are.same({ 2, 4, 0 }, { I.res.swing[1], I.res.swingValue[1], I.res.swingOff[1] })
     end)
 
-    it("leaves the cast history and the real queue to the combat-log rows, asks for a cycle, feeds the swing", function()
+    it("leaves the cast history, the real queue and the swing fields to the combat-log rows, asks for a cycle", function()
         ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
         ctl.casting = { 1000, 2500 }
         ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", fs.REND)
@@ -114,7 +114,7 @@ describe("Adapter", function()
         assert.are.same({}, state.queue)
         assert.are.same({ "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_FAILED" }, h.forced)
         ctl.Fire("PLAYER_SWING", 2.6, 0)
-        assert.are.same({ 1, 3.6 }, { state.swings.mh_actual, state.swings.mh_projected })
+        assert.are.equal(0, state.swings.mh_actual) -- CLEU_HANDLER writes it from the swing row
     end)
 
     it("applies an instant cast through the spec: modelled rage, GCD and debuff, two resets, offset restored", function()
diff --git a/VirtualState/spec/cleu_rows_spec.lua b/VirtualState/spec/cleu_rows_spec.lua
index 6ae54062..fd269361 100644
--- a/VirtualState/spec/cleu_rows_spec.lua
+++ b/VirtualState/spec/cleu_rows_spec.lua
@@ -189,4 +189,127 @@ describe("the synthesized combat log", function()
         end, 10000)
         assert.are.equal(0, bytes)
     end)
+
+    describe("our swings and abilities on the target", function()
+        local function row(i)
+            return got[i] and got[i].row
+        end
+
+        it("pairs a swing with the target's dodge that follows it: SWING_MISSED at the swing's time", function()
+            ctl.now = 10
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            assert.are.equal(0, #got)
+            ctl.now = 10.05
+            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
+            assert.are.equal(1, #got)
+            assert.are.same(
+                { 10, "SWING_MISSED", false, "Player-1", "", L.PLAYER_FLAGS, 0, "Creature-1", "", L.HOSTILE_FLAGS, 0, "DODGE", false, 0, false },
+                row(1)
+            )
+            assert.are.equal(15, got[1].n)
+            assert.are.equal(10, got[1].now) -- back-dated to the swing
+        end)
+
+        it("pairs a wound that arrives before the swing: SWING_DAMAGE at the wound's time", function()
+            ctl.now = 20
+            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 120, 1)
+            ctl.now = 20.04
+            ctl.Fire("PLAYER_SWING", 1.8, 1)
+            assert.are.equal(21, got[1].n)
+            assert.are.same({ "SWING_DAMAGE", 120, 0, 1, 0, 0, 0, true, false, false, true }, {
+                row(1)[2], row(1)[12], row(1)[13], row(1)[14], row(1)[15], row(1)[16], row(1)[17],
+                row(1)[18], row(1)[19], row(1)[20], row(1)[21],
+            })
+            assert.are.equal(20, got[1].now)
+        end)
+
+        it("emits an unpaired swing as SWING_DAMAGE 0 once its window closes, at its own time", function()
+            ctl.now = 30
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            ctl.Tick(30.15)
+            assert.are.equal(0, #got)
+            ctl.Tick(30.25)
+            assert.are.equal(1, #got)
+            assert.are.same({ "SWING_DAMAGE", 0, 0 }, { row(1)[2], row(1)[12], row(1)[13] })
+            assert.are.equal(30, got[1].now)
+        end)
+
+        it("drops an outcome nothing of ours pairs within the window", function()
+            ctl.now = 40
+            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
+            ctl.Tick(40.3)
+            ctl.now = 40.35
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            ctl.Tick(40.6)
+            assert.are.equal(1, #got)
+            assert.are.same({ "SWING_DAMAGE", 0 }, { row(1)[2], row(1)[12] })
+            ctl.Fire("UNIT_COMBAT", "nameplate1", "DODGE", "", 0, 1) -- another token: not the target's outcome
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            ctl.now = 40.65
+            ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 30, 1)
+            assert.are.equal(1, #got)
+        end)
+
+        it("pairs our ability with the target's parry: SPELL_MISSED with the miss type in slot 15", function()
+            ctl.now = 50
+            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", fs.REND)
+            ctl.now = 50.02
+            ctl.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
+            assert.are.equal("SPELL_CAST_SUCCESS", row(1)[2])
+            assert.are.same({ "SPELL_MISSED", fs.REND, "", 1, "PARRY", false, 0, false }, {
+                row(2)[2], row(2)[12], row(2)[13], row(2)[14], row(2)[15], row(2)[16], row(2)[17], row(2)[18],
+            })
+            assert.are.equal(18, got[2].n)
+        end)
+
+        it("gives an on-next-swing strike its swing's outcome: SPELL_DAMAGE, no swing row", function()
+            ctl.now = 60
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", fs.STRIKE)
+            ctl.now = 60.03
+            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 250, 1)
+            ctl.Tick(61)
+            assert.are.equal(2, #got)
+            assert.are.same({ "SPELL_DAMAGE", fs.STRIKE, 250, 24 }, { row(2)[2], row(2)[12], row(2)[15], got[2].n })
+        end)
+
+        it("gives the strike its swing's outcome when the success comes before the swing", function()
+            ctl.now = 70
+            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-11", fs.STRIKE)
+            ctl.now = 70.02
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            ctl.now = 70.04
+            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
+            ctl.Tick(71)
+            assert.are.equal(2, #got)
+            assert.are.same({ "SPELL_MISSED", fs.STRIKE, "DODGE" }, { row(2)[2], row(2)[12], row(2)[15] })
+        end)
+
+        it("makes no row without a target", function()
+            ctl.guid.target = nil
+            ctl.now = 80
+            ctl.Fire("PLAYER_SWING", 2.6, 0)
+            ctl.Tick(81)
+            assert.are.equal(0, #got)
+        end)
+
+        it("allocates nothing per paired swing", function()
+            local sink = I.Events.CreateFrame("Frame")
+            local GetInfo = Facade.CombatLogGetCurrentEventInfo
+            sink:SetScript("OnEvent", function()
+                GetInfo()
+            end)
+            sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+            cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+            local bytes = alloc.bytes(function(i)
+                ctl.now = i
+                ctl.Fire("PLAYER_SWING", 2.6, 0)
+                ctl.Fire("UNIT_COMBAT", "target", i % 2 == 0 and "WOUND" or "DODGE", "", 100, 1)
+                ctl.Fire("PLAYER_SWING", 2.6, 1)
+                ctl.Tick(i + 0.5)
+                I.Sources.Flush()
+            end, 10000)
+            assert.are.equal(0, bytes)
+        end)
+    end)
 end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `168 successes / 6 failures / 2 errors` (no swing or outcome rows yet; `adapter_spec.lua:117`: the swing feed still writes `mh_actual`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Hekili.toc b/Hekili.toc
index bda1d634..bb5c8caf 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -36,6 +36,7 @@ VirtualState\Snapshot.lua
 VirtualState\AplWarnings.lua
 VirtualState\EventFacade.lua
 VirtualState\CombatLog.lua
+VirtualState\Sources\Rows.lua
 VirtualState\Facade.lua
 
 Hekili.lua
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index fbff9cb6..0f3586d0 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -1,8 +1,8 @@
 -- VirtualState/Adapter.lua
 -- VirtualState's glue to Hekili (spec §3.6, §4.6, §5): VirtualState.Start at PLAYER_LOGIN, the tracked set from the
--- active spec's registrations (SpecChanged), the swing feed (the swing fields), and Drain: the fold plus "apply
--- through the spec", which runs each of our real casts through Hekili's own registered functions on `state` and records
--- what changed as `modelled` samples.
+-- active spec's registrations (SpecChanged), and Drain: the fold plus "apply through the spec", which runs each of
+-- our real casts through Hekili's own registered functions on `state` and records what changed as `modelled` samples.
+-- Hekili's across-reset caches (cast history, the real queue, the swing fields) come from the combat-log rows.
 -- Loads after Core.lua. The apply follows Hekili's own simulation (Core.lua:1984-2045) and keeps Hekili's credits.
 
 local addon, ns = ...
@@ -215,19 +215,6 @@ function VS.SpecChanged()
     end
 end
 
-----------------------------------------------------------------------------------------------------------------------
--- Feeding Hekili's across-reset caches (spec §4.6), synchronously in VirtualState's handlers, where CLEU did it.
-
--- The swing fields the dead CLEU SWING_* branch wrote (Events.lua:1684-1699), read by the swing regen models.
-I.feed.Swing = function(hand, t, duration)
-    local sw = state.swings
-    if hand == 1 then
-        sw.mh_actual, sw.mh_speed, sw.mh_projected = t, duration, t + duration
-    else
-        sw.oh_actual, sw.oh_speed, sw.oh_projected = t, duration, t + duration
-    end
-end
-
 ----------------------------------------------------------------------------------------------------------------------
 -- Apply through the spec (spec §5.2, §5.3).
 
diff --git a/VirtualState/Sources/Rows.lua b/VirtualState/Sources/Rows.lua
new file mode 100644
index 00000000..794aa682
--- /dev/null
+++ b/VirtualState/Sources/Rows.lua
@@ -0,0 +1,171 @@
+-- VirtualState/Sources/Rows.lua
+-- The combat-log rows of our swings and of our abilities on the target (event-facade spec §2.4, §3): PLAYER_SWING
+-- (time and hand, plain) and our UNIT_SPELLCAST_SUCCEEDED of an ability that starts combat or strikes on the next
+-- swing are paired with the
+-- target's UNIT_COMBAT (the outcome, plain, victim-side) when the two arrive within PAIR_WINDOW of each other, in
+-- either order: SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED, inferred, at the earlier event's time
+-- (back-dated). A swing still unpaired when its window closes is emitted as SWING_DAMAGE with amount 0 (its time is
+-- still the swing's); an outcome or a cast unpaired then is dropped (someone else's, or no outcome).
+-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
+-- (docs/research/2026-10-14-virtual-combat-log-events.md, C1, C3, C9, D7).
+
+local _, ns = ...
+local I = ns.VirtualStateInternal
+local S = I.Sources
+local Plain = S.Plain
+local L = I.Log
+
+-- Seconds within which a swing or cast and the target's outcome pair (PAIR_WINDOW_MS / 1000; event-facade spec §3:
+-- [V] D10a's 0.2 s until the phase B checkpoint measures the gap).
+L.PAIR_WINDOW = 0.2
+
+local N = 8
+-- Pending own actions: kind 1 swing (hand in `x`), 2 cast (spell ID in `x`); `t` 0 is a free entry.
+local actT, actKind, actX, actDst = {}, {}, {}, {}
+-- Pending target outcomes: action ("WOUND", "DODGE" ...), flag text, amount.
+local outT, outAction, outFlag, outAmount = {}, {}, {}, {}
+for i = 1, N do
+    actT[i], actKind[i], actX[i], actDst[i] = 0, 0, 0, ""
+    outT[i], outAction[i], outFlag[i], outAmount[i] = 0, "", "", 0
+end
+
+local strikeWait = 0 -- an on-next-swing strike's success still waiting for its main-hand swing
+
+local MISSES = { DODGE = true, PARRY = true, MISS = true, BLOCK = true, DEFLECT = true, EVADE = true, IMMUNE = true,
+    RESIST = true, ABSORB = true }
+
+local function free(ts)
+    local oldest = 1
+    for i = 1, N do
+        if ts[i] == 0 then
+            return i
+        elseif ts[i] < ts[oldest] then
+            oldest = i
+        end
+    end
+    return oldest -- full: the oldest gives way
+end
+
+local function oldest(ts, now)
+    local best
+    for i = 1, N do
+        local t = ts[i]
+        if t > 0 and now - t <= L.PAIR_WINDOW and (not best or t < ts[best]) then
+            best = i
+        end
+    end
+    return best
+end
+
+-- One row from an own action and its outcome, at the earlier time. None without a destination: Hekili's handler would
+-- count a "" GUID as an enemy (`ns.updateTarget`, Events.lua:1693-1701).
+local function emit(kind, x, dst, action, flag, amount, t)
+    if dst == "" then
+        return
+    end
+    local flags = L.HOSTILE_FLAGS
+    if kind == 1 then
+        local offhand = x == 2
+        if action == "WOUND" then
+            local r = L.Emit("SWING_DAMAGE", 21, t, true, "swing", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
+            r[12], r[13], r[14], r[15], r[16], r[17] = amount, 0, 1, 0, 0, 0
+            r[18], r[19], r[20], r[21] = flag == "CRITICAL", flag == "GLANCING", flag == "CRUSHING", offhand
+        else
+            local r = L.Emit("SWING_MISSED", 15, t, true, "missed", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
+            r[12], r[13], r[14], r[15] = action, offhand, 0, false
+        end
+    elseif action == "WOUND" then
+        local r = L.Emit("SPELL_DAMAGE", 24, t, true, "damage", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
+        r[12], r[13], r[14], r[15], r[16], r[17], r[18] = x, "", 1, amount, 0, 1, 0
+        r[19], r[20], r[21], r[22], r[23], r[24] = 0, 0, flag == "CRITICAL", false, false, false
+    else
+        local r = L.Emit("SPELL_MISSED", 18, t, true, "missed", "inferred", L.player, L.PLAYER_FLAGS, dst, flags)
+        r[12], r[13], r[14], r[15], r[16], r[17], r[18] = x, "", 1, action, false, 0, false
+    end
+end
+
+-- An own action at `t`: paired with a pending outcome, else held.
+local function action(kind, x, dst, t)
+    local o = oldest(outT, t)
+    if o then
+        local ot = outT[o]
+        outT[o] = 0
+        emit(kind, x, dst, outAction[o], outFlag[o], outAmount[o], ot < t and ot or t)
+        return
+    end
+    local i = free(actT)
+    actT[i], actKind[i], actX[i], actDst[i] = t, kind, x, dst
+end
+
+S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
+    if type(swingType) ~= "number" or swingType > 1 then
+        return
+    end
+    if swingType == 0 and strikeWait > 0 and t - strikeWait <= L.PAIR_WINDOW then
+        strikeWait = 0 -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
+        return
+    end
+    action(1, swingType + 1, Plain(api, api.UnitGUID("target")) or "", t)
+end)
+
+S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
+    local a = unit == "player" and spellID and I.ab.bySpell[spellID]
+    local obj = a and I.ab.obj[a]
+    if not obj or not (obj.startsCombat or obj.onNextSwing) then
+        return
+    end
+    if obj.onNextSwing then -- the strike replaces its swing, which came before or comes after this success
+        local found = false
+        for i = 1, N do
+            if actT[i] > 0 and actKind[i] == 1 and actX[i] == 1 and t - actT[i] <= L.PAIR_WINDOW then
+                actT[i], found = 0, true
+            end
+        end
+        if not found then
+            strikeWait = t
+        end
+    end
+    action(2, spellID, Plain(api, api.UnitGUID("target")) or "", t)
+end)
+
+S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount)
+    if unit ~= "target" or type(act) ~= "string" or (act ~= "WOUND" and not MISSES[act]) then
+        return
+    end
+    amount = type(amount) == "number" and amount or 0
+    flag = type(flag) == "string" and flag or ""
+    local p = oldest(actT, t)
+    if p then
+        local at = actT[p]
+        actT[p] = 0
+        emit(actKind[p], actX[p], actDst[p], act, flag, amount, at)
+        return
+    end
+    local i = free(outT)
+    outT[i], outAction[i], outFlag[i], outAmount[i] = t, act, flag, amount
+end)
+
+-- Closes the windows at `now`: an unpaired swing becomes SWING_DAMAGE with amount 0 at its own time; an unpaired
+-- cast or outcome is dropped. Every OnUpdate (the deferred lane, CombatLog.lua). Allocates nothing.
+L.OnTick(function(now)
+    for i = 1, N do
+        local t = actT[i]
+        if t > 0 and now - t > L.PAIR_WINDOW then
+            actT[i] = 0
+            if actKind[i] == 1 then
+                emit(1, actX[i], actDst[i], "WOUND", "", 0, t)
+            end
+        end
+        if outT[i] > 0 and now - outT[i] > L.PAIR_WINDOW then
+            outT[i] = 0
+        end
+    end
+end)
+
+-- Combat end: nothing pending survives into the next pull.
+S.On("PLAYER_REGEN_ENABLED", nil, function()
+    for i = 1, N do
+        actT[i], outT[i] = 0, 0
+    end
+    strikeWait = 0
+end)
diff --git a/VirtualState/Sources/Sources.lua b/VirtualState/Sources/Sources.lua
index a23b43f3..6ea948cb 100644
--- a/VirtualState/Sources/Sources.lua
+++ b/VirtualState/Sources/Sources.lua
@@ -13,10 +13,6 @@ local Add = I.ObsLog.Add
 local S = {}
 I.Sources = S
 
--- Adapter.lua's hooks into Hekili's across-reset caches (spec §4.6), called by the own-cast and swing sources; nil
--- until Adapter.lua sets them (and in headless specs that do not).
-I.feed = {}
-
 --- A client value VirtualState may test, compare or use: the value itself, or nil if it is secret. It asks
 --- `issecretvalue` before touching the value in any other way. Allocates nothing.
 function S.Plain(api, v)
diff --git a/VirtualState/Sources/Swing.lua b/VirtualState/Sources/Swing.lua
index ea7c61e9..042be80a 100644
--- a/VirtualState/Sources/Swing.lua
+++ b/VirtualState/Sources/Swing.lua
@@ -1,9 +1,9 @@
 -- VirtualState/Sources/Swing.lua
 -- Swing sources (spec §4.2): PLAYER_SWING (payload swingDuration, swingType; plain in combat) is a `Swing` with
--- a = swingType + 1, b = the duration, c = 1, staged on the urgent lane, and synchronously feeds Hekili's
--- `state.swings.*_actual/_projected` through Adapter.lua's hook (spec §4.6). Out of combat, UNIT_ATTACK_SPEED and
--- PLAYER_EQUIPMENT_CHANGED (and login, and combat end) read both hands' speeds (c = 0), the unhasted base speeds
--- (c = 2, speed x (1 + melee haste / 100)) and the melee haste multiplier (`Haste`, c = 1).
+-- a = swingType + 1, b = the duration, c = 1, staged on the urgent lane (Hekili's `state.swings` come from the swing
+-- rows, Sources/Rows.lua). Out of combat, UNIT_ATTACK_SPEED and PLAYER_EQUIPMENT_CHANGED (and login, and combat end)
+-- read both hands' speeds (c = 0), the unhasted base speeds (c = 2, speed x (1 + melee haste / 100)) and the melee
+-- haste multiplier (`Haste`, c = 1).
 -- Credits: secret-value handling after Catnip's (Durts) research.
 -- Ported from Taco Dog Forever, src/TacoDogForever/Sources/Swing.lua.
 
@@ -19,10 +19,6 @@ S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
     end
     local hand = swingType + 1
     Stage(Obs.Swing, t, hand, duration, 1)
-    local f = I.feed.Swing
-    if f then
-        f(hand, t, duration)
-    end
     S.Urgent("PLAYER_SWING")
 end)
 
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `176 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [176 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 71 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 46 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Sources/Rows.lua VirtualState/Sources/Swing.lua VirtualState/Sources/Sources.lua VirtualState/Adapter.lua Hekili.toc VirtualState/spec/cleu_rows_spec.lua VirtualState/spec/adapter_spec.lua
git commit -m "feat(virtualstate): swing and ability outcome rows on the target, paired with its UNIT_COMBAT within the window and back-dated; an unpaired swing at its own time; the swing feed retired

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 8: Hits on us: who targets us, and a swing clock per attacker

Phase B, spec §2.4 ("Avoided on us", "Damage on us", "Attribution of hits on us"), decision 6. The player's `UNIT_COMBAT` says what landed or was avoided, not who swung. `VirtualState/Sources/Attackers.lua` keeps, for the tokens `target`, `focus` and `nameplate1`-`40` (each with its `"<token>target"` string built at load), the token's plain GUID and whether it is a hostile targeting us (`UnitCanAttack("player", token)` and `UnitIsUnit("<token>target", "player")`, both through `Plain`; a secret `UnitIsUnit` means "not us", and its status is noted as `read UnitIsUnit target-of`), rechecked on `UNIT_TARGET`, `NAME_PLATE_UNIT_ADDED/REMOVED`, `PLAYER_TARGET_CHANGED` and `PLAYER_FOCUS_CHANGED`; and 8 attacker clocks by GUID (anchor, period). A targeting hostile's period is its `UnitAttackSpeed` when plain (noted `read UnitAttackSpeed hostile`), else learned from the gaps between hits credited to it (the first gap in [1, 5] s; later gaps within `L.ATTACK_TOLERANCE` (0.2 s) of a whole number of periods refine it, 0.8/0.2). A melee hit or avoidance on us goes to the targeting hostile whose clock predicts a swing nearest it within the tolerance; with one hostile on us and its clock not yet set, to that one; a non-physical hit only to a lone hostile (clock set or not: a spell does not follow the swing clock). A clock is made only when a hit is credited (in a free slot first, else the oldest anchor's), so enumerating candidates never evicts a learned period. The credited hit re-anchors the clock and becomes a row from that GUID (`SWING_DAMAGE`, `SPELL_DAMAGE` with spellId 0 and the school, or `SWING_MISSED` with the miss type), observed time, back-dated. An unattributed hit makes no row (`L.unattributed`, a `Snapshot()` line). Combat end clears the anchors; learned periods stay. The fake client answers `UnitAttackSpeed(unit)` for other units from `ctl.unitSpeed` (secret by default) and `UnitIsUnit` from `ctl.unitIs`.

**Files:**
- Create: `VirtualState/Sources/Attackers.lua`
- Modify: `Hekili.toc` (after `VirtualState\Sources\Rows.lua`), `VirtualState/spec/helpers/fake_api.lua` (`ctl.unitSpeed`, `ctl.unitIs`, `UnitAttackSpeed(unit)`, `UnitIsUnit`)
- Test: `VirtualState/spec/cleu_rows_spec.lua` (describe "hits on us")

**Interfaces:**
- Consumes: `L.Emit`, `L.player` (Task 6); `S.Plain`, `S.Note`, `S.StatusOf`.
- Produces: `L.ATTACK_TOLERANCE`, `L.unattributed`; read statuses `UnitIsUnit target-of` and `UnitAttackSpeed hostile`.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/cleu_rows_spec.lua b/VirtualState/spec/cleu_rows_spec.lua
index fd269361..bc1008fb 100644
--- a/VirtualState/spec/cleu_rows_spec.lua
+++ b/VirtualState/spec/cleu_rows_spec.lua
@@ -312,4 +312,114 @@ describe("the synthesized combat log", function()
             assert.are.equal(0, bytes)
         end)
     end)
+
+    describe("hits on us", function()
+        local function onUs(unit, guid, speed)
+            ctl.guid[unit] = guid
+            ctl.unitIs[unit .. "target"] = "player"
+            ctl.unitSpeed[unit] = speed
+        end
+
+        it("credits a dodge on us to the one hostile targeting us: SWING_MISSED from its GUID", function()
+            onUs("target", "Creature-1", nil)
+            ctl.Fire("PLAYER_TARGET_CHANGED")
+            ctl.now = 5
+            ctl.Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1)
+            assert.are.same(
+                { 5, "SWING_MISSED", false, "Creature-1", "", L.HOSTILE_FLAGS, 0, "Player-1", "", L.PLAYER_FLAGS, 0, "DODGE", false, 0, false },
+                got[1].row
+            )
+            assert.are.equal("readable", I.Sources.status["UnitIsUnit target-of"])
+        end)
+
+        it("emits no row when nobody is known to target us, or the answer is secret", function()
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 300, 1)
+            ctl.guid.target = "Creature-1"
+            ctl.unitIs.targettarget = fake.SECRET
+            ctl.Fire("PLAYER_TARGET_CHANGED")
+            ctl.Fire("UNIT_COMBAT", "player", "PARRY", "", 0, 1)
+            assert.are.equal(0, #got)
+            assert.are.equal(2, L.unattributed)
+            assert.are.equal("secret", I.Sources.status["UnitIsUnit target-of"])
+        end)
+
+        it("credits each hit to the attacker whose plain swing speed predicts it, and none off both clocks", function()
+            onUs("nameplate1", "Creature-A", 2.0)
+            onUs("nameplate2", "Creature-B", 3.0)
+            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
+            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
+            ctl.unitIs.nameplate2target = nil -- B not yet on us: A alone starts its clock
+            ctl.Fire("UNIT_TARGET", "nameplate2")
+            ctl.now = 10
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 100, 1)
+            ctl.unitIs.nameplate2target = "player"
+            ctl.unitIs.nameplate1target = nil
+            ctl.Fire("UNIT_TARGET", "nameplate2")
+            ctl.Fire("UNIT_TARGET", "nameplate1")
+            ctl.now = 10.7
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 90, 1) -- B alone, no clock: B's anchor
+            ctl.unitIs.nameplate1target = "player"
+            ctl.Fire("UNIT_TARGET", "nameplate1")
+            ctl.now = 12.05 -- A's clock: 10 + 2.0
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 80, 1)
+            ctl.now = 13.65 -- B's clock: 10.7 + 3.0
+            ctl.Fire("UNIT_COMBAT", "player", "BLOCK", "", 0, 1)
+            ctl.now = 15.0 -- A predicts 14.05, B 16.7: off both
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 70, 1)
+            assert.are.same({ "Creature-A", "Creature-B", "Creature-A", "Creature-B" }, {
+                got[1].row[4], got[2].row[4], got[3].row[4], got[4].row[4],
+            })
+            assert.are.equal(4, #got)
+            assert.are.equal("BLOCK", got[4].row[12])
+            assert.are.equal(1, L.unattributed)
+        end)
+
+        it("learns an attacker's period from the gaps when its speed is secret", function()
+            onUs("target", "Creature-1", nil)
+            ctl.Fire("PLAYER_TARGET_CHANGED")
+            for _, t in ipairs({ 20, 22, 24.02 }) do
+                ctl.now = t
+                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1)
+            end
+            onUs("nameplate3", "Creature-2", nil) -- a second hostile joins, no clock
+            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
+            ctl.now = 26.05
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- on Creature-1's learned clock
+            ctl.now = 27.0
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- on nobody's
+            assert.are.equal(4, #got)
+            assert.are.equal("Creature-1", got[4].row[4])
+            assert.are.equal(1, L.unattributed)
+            ctl.Fire("PLAYER_REGEN_ENABLED") -- combat ends: anchors go, the learned period stays
+            ctl.unitIs.nameplate3target = nil
+            ctl.Fire("UNIT_TARGET", "nameplate3")
+            ctl.now = 100
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- alone again: re-anchors
+            ctl.unitIs.nameplate3target = "player"
+            ctl.Fire("UNIT_TARGET", "nameplate3")
+            ctl.now = 102.02
+            ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1) -- two on us: the kept period names Creature-1
+            assert.are.equal(6, #got)
+            assert.are.equal("Creature-1", got[6].row[4])
+        end)
+
+        it("allocates nothing per hit on us", function()
+            local sink = I.Events.CreateFrame("Frame")
+            local GetInfo = Facade.CombatLogGetCurrentEventInfo
+            sink:SetScript("OnEvent", function()
+                GetInfo()
+            end)
+            sink:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+            cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+            onUs("target", "Creature-1", 2.0)
+            ctl.Fire("PLAYER_TARGET_CHANGED")
+            local bytes = alloc.bytes(function(i)
+                ctl.now = i * 2
+                ctl.Fire("UNIT_COMBAT", "player", i % 2 == 0 and "WOUND" or "PARRY", "", 40, 1)
+                ctl.Fire("UNIT_TARGET", "target")
+                I.Sources.Flush()
+            end, 10000)
+            assert.are.equal(0, bytes)
+        end)
+    end)
 end)
diff --git a/VirtualState/spec/helpers/fake_api.lua b/VirtualState/spec/helpers/fake_api.lua
index b83de73e..05ec1fa7 100644
--- a/VirtualState/spec/helpers/fake_api.lua
+++ b/VirtualState/spec/helpers/fake_api.lua
@@ -56,6 +56,8 @@ function M.new()
         traits = nil, -- { config = id, trees = { tree }, nodes = { [node] = info }, entries = {}, defs = {} }
         inRange = {},
         handlers = {},
+        unitSpeed = {}, -- [unit] = speed for UnitAttackSpeed of a unit other than the player (default: secret)
+        unitIs = {}, -- [unit] = the token UnitIsUnit(unit, x) is true for (SECRET: a secret answer)
         unknownEvents = {}, -- [event] = true: RegisterEvent raises, as the client does for an event it does not know
     }
     local api = { ctl = ctl }
@@ -113,9 +115,23 @@ function M.new()
     function api.GetMeleeHaste()
         return ctl.meleeHaste
     end
-    function api.UnitAttackSpeed()
+    function api.UnitAttackSpeed(unit)
+        if unit ~= nil and unit ~= "player" then
+            local v = ctl.unitSpeed[unit]
+            if v == nil then
+                return SECRET, SECRET
+            end
+            return v, nil
+        end
         return ctl.speed[1], ctl.speed[2]
     end
+    function api.UnitIsUnit(a, b)
+        local v = ctl.unitIs[a]
+        if v == SECRET then
+            return SECRET
+        end
+        return v == b
+    end
     function api.GetTotemInfo(slot)
         local t = ctl.totems[slot]
         if not t then
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `177 successes / 2 failures / 2 errors` (no rows on us; `L.unattributed` is nil).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Hekili.toc b/Hekili.toc
index bb5c8caf..977beb4b 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -37,6 +37,7 @@ VirtualState\AplWarnings.lua
 VirtualState\EventFacade.lua
 VirtualState\CombatLog.lua
 VirtualState\Sources\Rows.lua
+VirtualState\Sources\Attackers.lua
 VirtualState\Facade.lua
 
 Hekili.lua
diff --git a/VirtualState/Sources/Attackers.lua b/VirtualState/Sources/Attackers.lua
new file mode 100644
index 00000000..095e1929
--- /dev/null
+++ b/VirtualState/Sources/Attackers.lua
@@ -0,0 +1,206 @@
+-- VirtualState/Sources/Attackers.lua
+-- Hits on us as combat-log rows (event-facade spec §2.4, §6, decision 6). The player's UNIT_COMBAT says what landed or
+-- was avoided but not who swung, so the layer keeps (a) the set of hostiles targeting us, from UNIT_TARGET and the
+-- target, focus and nameplate tokens (UnitIsUnit("<unit>target", "player"), through Plain: a secret answer counts as
+-- not targeting us), and (b) a swing clock per attacker, an anchor and a period like our own hands: the period is
+-- UnitAttackSpeed(unit) when plain, else learned from the gaps between hits on us. A hit is credited to the attacker
+-- whose clock predicts a swing nearest it within ATTACK_TOLERANCE; while a single hostile targets us and its clock is
+-- not set yet, to that one (which starts its clock); otherwise it stays unattributed and makes no row (no phantom
+-- enemy for the tank branch, Events.lua's `ns.updateTarget( sourceGUID, ... )`).
+-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
+-- (docs/research/2026-10-14-virtual-combat-log-events.md, C2, C4, M1-M4, D13).
+
+local _, ns = ...
+local I = ns.VirtualStateInternal
+local S = I.Sources
+local Plain, Note = S.Plain, S.Note
+local L = I.Log
+local floor = math.floor
+
+L.ATTACK_TOLERANCE = 0.2 -- seconds between a clock's predicted swing and a hit credited to it
+L.unattributed = 0
+
+-- The tokens whose target is checked: target, focus, nameplate1-40; each with "<token>target" built once.
+local TOKENS, TT, INDEX = { "target", "focus" }, {}, {}
+for i = 1, 40 do
+    TOKENS[#TOKENS + 1] = "nameplate" .. i
+end
+for i = 1, #TOKENS do
+    TT[i], INDEX[TOKENS[i]] = TOKENS[i] .. "target", i
+end
+local tokGUID, tokOnMe, tokSpeed = {}, {}, {}
+for i = 1, #TOKENS do
+    tokGUID[i], tokOnMe[i], tokSpeed[i] = "", false, 0
+end
+
+-- Attacker clocks by GUID (8, the oldest anchor gives way).
+local N = 8
+local atkGUID, atkAnchor, atkPeriod = {}, {}, {}
+for k = 1, N do
+    atkGUID[k], atkAnchor[k], atkPeriod[k] = "", 0, 0
+end
+
+-- The clock of `guid`, or nil. Allocates nothing.
+local function find(guid)
+    for k = 1, N do
+        if atkGUID[k] == guid then
+            return k
+        end
+    end
+end
+
+-- The clock of `guid`, made on first credit in a free slot, else in the one with the oldest anchor.
+local function clockOf(guid)
+    local k = find(guid)
+    if k then
+        return k
+    end
+    local slot = 1
+    for j = 1, N do
+        if atkGUID[j] == "" then
+            slot = j
+            break
+        elseif atkAnchor[j] < atkAnchor[slot] then
+            slot = j
+        end
+    end
+    atkGUID[slot], atkAnchor[slot], atkPeriod[slot] = guid, 0, 0
+    return slot
+end
+
+local function recheck(api, i)
+    local tok = TOKENS[i]
+    local guid = Plain(api, api.UnitGUID(tok)) or ""
+    local hostile = guid ~= "" and Plain(api, api.UnitCanAttack("player", tok)) == true
+    local raw = api.UnitIsUnit(TT[i], "player") -- secret: tested with issecretvalue next, then read through Plain
+    Note("UnitIsUnit target-of", S.StatusOf(api, raw))
+    tokGUID[i], tokOnMe[i] = guid, hostile and Plain(api, raw) == true
+    tokSpeed[i] = 0
+    if tokOnMe[i] then
+        local rawSpeed = api.UnitAttackSpeed(tok) -- secret: tested with issecretvalue next, then read through Plain
+        Note("UnitAttackSpeed hostile", S.StatusOf(api, rawSpeed))
+        local speed = Plain(api, rawSpeed)
+        if type(speed) == "number" and speed > 0 then
+            tokSpeed[i] = speed
+        end
+    end
+end
+
+local function onUnit(api, t, unit)
+    local i = unit and INDEX[unit]
+    if i then
+        recheck(api, i)
+    end
+end
+S.On("UNIT_TARGET", nil, onUnit)
+S.On("NAME_PLATE_UNIT_ADDED", nil, onUnit)
+S.On("NAME_PLATE_UNIT_REMOVED", nil, onUnit)
+S.On("PLAYER_TARGET_CHANGED", nil, function(api)
+    recheck(api, 1)
+end)
+S.On("PLAYER_FOCUS_CHANGED", nil, function(api)
+    recheck(api, 2)
+end)
+
+-- How far `t` lies from the nearest swing a clock predicts (huge when the clock is not set). Allocates nothing.
+local function clockError(k, period, t)
+    local anchor = k and atkAnchor[k] or 0
+    if period <= 0 or anchor <= 0 then
+        return math.huge
+    end
+    local d = (t - anchor) % period
+    return d < period - d and d or period - d
+end
+
+-- A credited hit re-anchors the clock and, without a plain speed, refines the learned period from the gap.
+local function learn(k, t, speed)
+    local gap = t - atkAnchor[k]
+    if speed > 0 then
+        atkPeriod[k] = speed
+    elseif atkAnchor[k] > 0 then
+        local period = atkPeriod[k]
+        if period <= 0 then
+            if gap >= 1 and gap <= 5 then
+                atkPeriod[k] = gap
+            end
+        else
+            local n = floor(gap / period + 0.5)
+            if n >= 1 and math.abs(gap - n * period) <= L.ATTACK_TOLERANCE then
+                atkPeriod[k] = period * 0.8 + gap / n * 0.2 -- shortcut: a plain EMA; a dual-wielding attacker blurs it
+            end
+        end
+    end
+    atkAnchor[k] = t
+end
+
+local MISSES = { DODGE = true, PARRY = true, BLOCK = true, MISS = true }
+
+S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
+    if unit ~= "player" or (act ~= "WOUND" and not MISSES[act]) then
+        return
+    end
+    local melee = act ~= "WOUND" or school == 1
+    -- the candidates: each hostile targeting us once (a GUID can be the target and a plate); no clock is made here
+    local best, bestErr, single, n = nil, L.ATTACK_TOLERANCE, nil, 0
+    for i = 1, #TOKENS do
+        if tokOnMe[i] then
+            local guid, seen = tokGUID[i], false
+            for j = 1, i - 1 do
+                seen = seen or (tokOnMe[j] and tokGUID[j] == guid)
+            end
+            if not seen then
+                n, single = n + 1, i
+                local k = find(guid)
+                local period = tokSpeed[i]
+                if period <= 0 and k then
+                    period = atkPeriod[k]
+                end
+                local err = clockError(k, period, t)
+                if melee and err <= bestErr then
+                    best, bestErr = i, err
+                end
+            end
+        end
+    end
+    if not best and n == 1 then
+        local k = find(tokGUID[single])
+        local set = k and atkAnchor[k] > 0 and (tokSpeed[single] > 0 or atkPeriod[k] > 0)
+        if not set or not melee then
+            best = single -- one hostile on us, and no clock to test yet or a non-physical hit: it is that one
+        end
+    end
+    if not best then
+        L.unattributed = L.unattributed + 1
+        return
+    end
+    local speed = tokSpeed[best]
+    best = clockOf(tokGUID[best])
+    if melee then
+        learn(best, t, speed)
+    end
+    local src, dst = atkGUID[best], L.player
+    if act == "WOUND" and melee then
+        local r = L.Emit("SWING_DAMAGE", 21, t, true, "onus", "inferred", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS)
+        r[12], r[13], r[14], r[15], r[16], r[17] = type(amount) == "number" and amount or 0, 0, 1, 0, 0, 0
+        r[18], r[19], r[20], r[21] = flag == "CRITICAL", flag == "GLANCING", flag == "CRUSHING", false
+    elseif act == "WOUND" then
+        local r = L.Emit("SPELL_DAMAGE", 24, t, true, "onus", "inferred", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS)
+        local mask = type(school) == "number" and school or 1
+        r[12], r[13], r[14], r[15], r[16], r[17], r[18] = 0, "", mask, type(amount) == "number" and amount or 0, 0, mask, 0
+        r[19], r[20], r[21], r[22], r[23], r[24] = 0, 0, flag == "CRITICAL", false, false, false
+    else
+        local r = L.Emit("SWING_MISSED", 15, t, true, "onus", "inferred", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS)
+        r[12], r[13], r[14], r[15] = act, false, 0, false
+    end
+end)
+
+-- Combat end: the clocks lose their anchors (a new pull starts them again); learned periods stay.
+S.On("PLAYER_REGEN_ENABLED", nil, function()
+    for k = 1, N do
+        atkAnchor[k] = 0
+    end
+end)
+
+I.OnSnapshot(function(out)
+    out[#out + 1] = string.format("rows unattributed hits on us=%d", L.unattributed)
+end)
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `181 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [181 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 72 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 47 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Sources/Attackers.lua Hekili.toc VirtualState/spec/helpers/fake_api.lua VirtualState/spec/cleu_rows_spec.lua
git commit -m "feat(virtualstate): rows for hits on us, credited by the hostiles targeting us and a swing clock per attacker (plain attack speed, else learned); an unattributed hit makes no row

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 9: Our casts' aura rows and energize

Phase B, spec §2.4 ("Our casts' auras", "Energize"), §3's time table. The drain's apply through the spec already reads every tracked aura's expiry and every resource before and after our cast (`Adapter.lua` `readBefore`/`readAfter`). Where a buff (on us) or a debuff (on the target) changed, `readAfter` now also calls `I.Log.Aura(unit, j, spellID, before, after, t)`: up after the cast → `SPELL_AURA_APPLIED` (or `_REFRESH` when it was up), back-dated to the cast; removed by the cast → `SPELL_AURA_REMOVED` at the cast's time. `CombatLog.lua` keeps each such aura's believed expiry and, in the deferred lane, emits `SPELL_AURA_REMOVED` once it passes, stamped at delivery (modelled). A resource the cast added becomes `SPELL_ENERGIZE` on us (amount, power type, maximum; last slot 18), back-dated. With no target GUID (or no spell ID) no aura row is made, as for Task 7's rows. The modelled expiries run in the deferred lane through `L.OnTick` (Task 6). The target's GUID comes from `Sources/Attackers.lua` (`L.target`, read at `Start` and `PLAYER_TARGET_CHANGED`). The adapter keeps each aura's first spell ID beside its key. These rows reach Hekili at the next delivery point after the drain (never inside `Hekili.Update`). Task 10 replaces the apply route this task hooks into and moves the two calls into its `now` verbs.

**Files:**
- Modify: `VirtualState/CombatLog.lua` (`L.target`, `L.Aura`, the expiry lane, `L.Energize`), `VirtualState/Sources/Attackers.lua` (`readTarget`), `VirtualState/Adapter.lua` (`auraId`; `readAfter(t, kind, a)`; its call in `apply`)
- Test: `VirtualState/spec/adapter_spec.lua` ("emits our casts' aura and energize rows ...", "emits no debuff row while there is no target to name")

**Interfaces:**
- Consumes: `readAfter`'s before/after values (Phase 1), `I.ab.qid`, `I.res.type`, `I.res.max`.
- Produces: `L.Aura(u, j, spellID, before, after, t)`, `L.Energize(spellID, amount, powerType, maxPower, t)`, `L.target`.

- [ ] **Step 1: Write the failing spec**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/adapter_spec.lua b/VirtualState/spec/adapter_spec.lua
index 88ed0ce9..e5688269 100644
--- a/VirtualState/spec/adapter_spec.lua
+++ b/VirtualState/spec/adapter_spec.lua
@@ -153,6 +153,64 @@ describe("Adapter", function()
         assert.is_true(math.abs(want - got) < 1e-6, ("want %s, got %s"):format(want, got))
     end
 
+    it("emits our casts' aura and energize rows: APPLIED and REFRESH back-dated, REMOVED at the modelled expiry", function()
+        local rows = {}
+        local cleu = I.Events.CreateFrame("Frame")
+        cleu:SetScript("OnEvent", function()
+            local _, sub, _, src, _, _, _, dst, _, _, _, spellID, _, _, a15, _, a17 = ns.Facade.CombatLogGetCurrentEventInfo()
+            rows[#rows + 1] = { sub, dst, spellID, a15, a17, ns.Facade.GetTime() }
+        end)
+        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+        register("rage_test", {
+            id = 2687,
+            cooldown = 60,
+            handler = function()
+                state.rage.actual = state.rage.actual + 10
+            end,
+        })
+        VS.SpecChanged()
+        I.ObsLog.Clear(I.log)
+        ctl.Fire("PLAYER_TARGET_CHANGED")
+        ctl.now = 5
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
+        ctl.Tick(5.05)
+        VS.Drain(5.1) -- the apply: Rend on the target until 20
+        ctl.Tick(5.15) -- delivered at the next OnUpdate
+        assert.are.same({ "SPELL_CAST_SUCCESS", "Creature-1", fs.REND }, { rows[1][1], rows[1][2], rows[1][3] })
+        assert.are.same({ "SPELL_AURA_APPLIED", "Creature-1", fs.REND, "DEBUFF", nil, 5 }, rows[2])
+        ctl.now = 8
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.REND)
+        ctl.Tick(8.05)
+        VS.Drain(8.1)
+        ctl.Tick(8.15)
+        assert.are.same({ "SPELL_AURA_REFRESH", 8 }, { rows[4][1], rows[4][6] })
+        ctl.now = 9
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 2687)
+        ctl.Tick(9.05)
+        VS.Drain(9.1)
+        ctl.Tick(9.15)
+        assert.are.same({ "SPELL_ENERGIZE", "Player-1", 2687, 10, fs.RAGE, 9 }, rows[6])
+        ctl.Tick(23.5) -- past Rend's modelled expiry (8 + 15)
+        assert.are.same({ "SPELL_AURA_REMOVED", "Creature-1", fs.REND, "DEBUFF", nil, 23.5 }, rows[7])
+    end)
+
+    it("emits no debuff row while there is no target to name", function()
+        local subs = {}
+        local cleu = I.Events.CreateFrame("Frame")
+        cleu:SetScript("OnEvent", function()
+            subs[#subs + 1] = select(2, ns.Facade.CombatLogGetCurrentEventInfo())
+        end)
+        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+        ctl.guid.target = nil
+        ctl.Fire("PLAYER_TARGET_CHANGED")
+        ctl.now = 5
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
+        ctl.Tick(5.05)
+        VS.Drain(5.1)
+        ctl.Tick(30)
+        assert.are.same({ "SPELL_CAST_SUCCESS" }, subs)
+    end)
+
     it("applies a hard cast at its finish: the GCD at the start's time, CAST_FINISH through HandleEvent", function()
         register("slam_test", { id = 1464, cast = 1.5, cooldown = 0, spend = 15, spendType = "rage" })
         VS.SpecChanged()
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `182 successes / 1 failure / 0 errors` (`adapter_spec.lua:180`: no aura row after the cast's success).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index 0f3586d0..5d23024c 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -101,7 +101,7 @@ local function sortedKeys(t)
     return keys
 end
 
-local resourceKey, auraKey = {}, {}
+local resourceKey, auraKey, auraId = {}, {}, {}
 
 local function buildDef()
     for _, list in pairs(def) do
@@ -109,6 +109,7 @@ local function buildDef()
     end
     wipe(resourceKey)
     wipe(auraKey)
+    wipe(auraId)
     local slotByKey = {}
     for _, k in ipairs(sortedKeys(class.resources)) do
         local r = class.resources[k]
@@ -173,7 +174,7 @@ local function buildDef()
             if #ids > 0 then
                 insert(def.auras, a)
                 def.auraIds[#def.auras] = ids
-                auraKey[#def.auras] = k
+                auraKey[#def.auras], auraId[#def.auras] = k, ids[1]
             end
         end
     end
@@ -251,8 +252,8 @@ local function readBefore(t)
 end
 
 -- Step 3.7: what changed, as `modelled` samples at t.
-local function readAfter(t, kind)
-    local R = I.res
+local function readAfter(t, kind, a)
+    local R, spellID = I.res, I.ab.qid[a]
     for r = 1, R.n do
         local res = rawget(state, resourceKey[r])
         if res then
@@ -260,6 +261,9 @@ local function readAfter(t, kind)
             if delta > 1e-6 or delta < -1e-6 then
                 I.ResourceShift(r, delta, t, kind)
             end
+            if delta > 1e-6 then
+                I.Log.Energize(spellID, delta, R.type[r], R.max[r], t) -- the cast gave us resource
+            end
         end
     end
     local A, cooldown = I.ab, state.cooldown
@@ -286,9 +290,11 @@ local function readAfter(t, kind)
             local be, de = field(b, "expires"), field(d, "expires")
             if be ~= buffExp[j] or field(b, "count") ~= buffCnt[j] then
                 I.AuraModel(1, j, field(b, "applied"), be, field(b, "count"), t, kind, false)
+                I.Log.Aura(1, j, auraId[j], buffExp[j], be, t)
             end
             if (de ~= debuffExp[j] or field(d, "count") ~= debuffCnt[j]) and I.auras.n >= 2 then
                 I.AuraModel(2, j, field(d, "applied"), de, field(d, "count"), t, kind, true)
+                I.Log.Aura(2, j, auraId[j], debuffExp[j], de, t)
             end
         end
     end
@@ -344,7 +350,7 @@ local function apply(kind, a, t)
         spendResources(key)
         state:RunHandler(key)
     end
-    readAfter(t, kind)
+    readAfter(t, kind, a)
     return true
 end
 I.Apply = apply
diff --git a/VirtualState/CombatLog.lua b/VirtualState/CombatLog.lua
index 68c906d3..897498aa 100644
--- a/VirtualState/CombatLog.lua
+++ b/VirtualState/CombatLog.lua
@@ -138,6 +138,79 @@ function L.Tick(now)
     end
 end
 
+-- The target's plain GUID (rows' destination for our debuffs), kept by Sources/Attackers.lua.
+L.target = ""
+
+-- Our auras' rows (decision 5: APPLIED and REFRESH at the cast's time, back-dated; REMOVED at the modelled expiry,
+-- stamped at delivery). Per tracked aura and unit (1 player, 2 target): the believed expiry, its spell, its target.
+local auraExp, auraId, auraDst = { {}, {} }, { {}, {} }, { {}, {} }
+I.OnBuild(function(def)
+    for u = 1, 2 do
+        for j = 1, math.max(#def.auras, #auraExp[u]) do
+            auraExp[u][j], auraId[u][j], auraDst[u][j] = 0, 0, ""
+        end
+    end
+end)
+
+local function auraRow(sub, u, j, t, backdate, prov)
+    local dst = auraDst[u][j]
+    local flags = L.HOSTILE_FLAGS
+    if u == 1 then
+        flags = L.PLAYER_FLAGS
+    end
+    local r = L.Emit(sub, 16, t, backdate, "aura", prov, L.player, L.PLAYER_FLAGS, dst, flags)
+    r[12], r[13], r[14], r[15], r[16] = auraId[u][j], "", 1, u == 1 and "BUFF" or "DEBUFF", 0
+end
+
+--- What our cast at `t` did to tracked aura `j` on unit `u` (1 player, 2 target): its expiry before and after the
+--- apply through the spec (Adapter.lua). No row without a destination GUID (Hekili would count "" as an enemy).
+--- Allocates nothing.
+function L.Aura(u, j, spellID, before, after, t)
+    if type(spellID) ~= "number" then
+        return
+    end
+    if after > t then
+        local dst = L.player
+        if u == 2 then
+            dst = L.target
+        end
+        if dst == "" then
+            return
+        end
+        auraId[u][j], auraExp[u][j], auraDst[u][j] = spellID, after, dst
+        if before > t then
+            auraRow("SPELL_AURA_REFRESH", u, j, t, true, "inferred")
+        else
+            auraRow("SPELL_AURA_APPLIED", u, j, t, true, "inferred")
+        end
+    elseif before > t and auraExp[u][j] > 0 then
+        auraExp[u][j] = 0
+        auraRow("SPELL_AURA_REMOVED", u, j, t, true, "inferred") -- the cast removed it (a handler's removeBuff)
+    end
+end
+
+L.OnTick(function(now)
+    for u = 1, 2 do
+        local exp = auraExp[u]
+        for j = 1, #exp do
+            if exp[j] > 0 and now >= exp[j] then
+                exp[j] = 0
+                auraRow("SPELL_AURA_REMOVED", u, j, now, false, "modelled")
+            end
+        end
+    end
+end)
+
+--- Resource our cast at `t` gave us (Adapter.lua's apply): SPELL_ENERGIZE, back-dated to the cast.
+function L.Energize(spellID, amount, powerType, maxPower, t)
+    if type(spellID) ~= "number" or L.player == "" then
+        return
+    end
+    local me, flags = L.player, L.PLAYER_FLAGS
+    local r = L.Emit("SPELL_ENERGIZE", 18, t, true, "energize", "modelled", me, flags, me, flags)
+    r[12], r[13], r[14], r[15], r[16], r[17], r[18] = spellID, "", 1, amount, 0, powerType, maxPower
+end
+
 --- Snapshot's line: the rows (allocates; debugging only).
 I.OnSnapshot(function(out)
     local c = L.counts
diff --git a/VirtualState/Sources/Attackers.lua b/VirtualState/Sources/Attackers.lua
index 095e1929..91ccebd3 100644
--- a/VirtualState/Sources/Attackers.lua
+++ b/VirtualState/Sources/Attackers.lua
@@ -95,9 +95,12 @@ end
 S.On("UNIT_TARGET", nil, onUnit)
 S.On("NAME_PLATE_UNIT_ADDED", nil, onUnit)
 S.On("NAME_PLATE_UNIT_REMOVED", nil, onUnit)
-S.On("PLAYER_TARGET_CHANGED", nil, function(api)
+local function readTarget(api)
     recheck(api, 1)
-end)
+    L.target = tokGUID[1]
+end
+S.On("PLAYER_TARGET_CHANGED", nil, readTarget)
+S.OnStart(readTarget)
 S.On("PLAYER_FOCUS_CHANGED", nil, function(api)
     recheck(api, 2)
 end)
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `183 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [183 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 72 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 47 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/CombatLog.lua VirtualState/Sources/Attackers.lua VirtualState/Adapter.lua VirtualState/spec/adapter_spec.lua
git commit -m "feat(virtualstate): aura rows for our casts (APPLIED and REFRESH back-dated to the cast, REMOVED at the modelled expiry) and SPELL_ENERGIZE from the drain's apply

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 10: `now` handlers: a cast's effects from the class file's declared now-state; the drain's reset-apply-reset retired

Spec §12a (the user's approved design, 2026-10-15). Placed after Task 9 because it replaces the route Task 9's aura and energize rows come from (the drain's read-before/apply/read-after diff of Hekili's `state`) and moves those rows into its own verbs, and it needs Task 6's combat log for them.

Today `VS.Drain` stops the fold at each own cast, resets Hekili's `state`, runs the ability's sim `handler` through it and diffs the tracked fields (`Adapter.lua` `readBefore`, `apply`, `readAfter`, a trailing reset). Afterwards no sim handler is read for truth:
- `VirtualState/Families/Now.lua` registers on `Obs.CastSuccess` only (after the Resources family's ladder pin for the same observation, by load order; a channel stages both `ChannelStart` and `CastSuccess`, so registering both would run it twice) and, for every tracked ability but a `track_<id>` extra (`VS.Track`: no ability, no effects), writes, at the cast's belief time t: (1) the cost, `I.ResourceShift(slot, -I.CostOf(a), t, kind)`, an on-next-swing strike's included: its `UNIT_SPELLCAST_SUCCEEDED` arrives with the swing it replaces ([V] O16), so paying at its success is paying at its swing (the design brief's "keep paying at their swing; nothing here" would have left the strike's cost unpaid, since the Phase 1 apply was what paid it); (2) the declared `cooldown` through `I.CooldownModel`, or a charge through `I.ChargesModel`; the GCD through `I.GcdModel` (a hard cast's GCD began at its start, so it is written only while it still runs); (3) the ability's `now` function, if declared, under `pcall` (an error counted in `I.nowErrors`/`I.nowError`; the fold goes on).
- Hekili's `RegisterAbility` (`Classes.lua:784-793` at 75d71c8b) setfenv's every function field to `state` and keeps a non-protected one in `ability.funcs` (reading `ability.now` would call it): the family reads it raw, `rawget(ability.funcs, "now")`, at SpecChanged and setfenv's it to one shared context table. Upvalues are untouched, so a class file's constants serve both its sim `handler` and its `now`.
- The context carries Hekili's verbs, with Hekili's own signatures (`State.lua`; the user's ruling, superseding the design brief's shorthand), so a Classic handler's lines port by copying: `gain(amount, resource)`/`spend(amount, resource)` → `I.ResourceShift` (a gain also writes Task 9's `SPELL_ENERGIZE` row; a resource the tracked set does not have, or none, raises inside the `now`, which is counted like any error, and writes nothing: no guessed resource); `applyBuff(aura, duration, stacks)`, `applyDebuff(unit, aura, duration, stacks)`, `removeBuff(aura)`, `removeDebuff(unit, aura)`, `addStack(aura, duration, stacks)` → `I.AuraModel` plus Task 9's aura rows (a missing duration takes the aura's registered number; an aura whose duration is a function needs the `now` to pass one); `setCooldown(action, duration)` → `I.CooldownModel`. Every write checks a `live` flag that is set only around the `pcall` of a cast's `now`: Hekili keeps `now` in `ability.funcs`, where DevTools' `RunStressTest` (`Options/DevTools.lua:140`) or an APL reading `action.<x>.now` (`State.lua:5076`) can call it, and such a call writes nothing. Reads, as proxies built at SpecChanged (no allocation per call): `talent.<key>.rank`/`.enabled` (the Talents family), `buff.<key>`/`debuff.<key>` (`up`, `down`, `remains`, `stack`, `count`, `expires`, `applied`, from the aura family at t), `<resource>.current`/`.max` (the belief), `knownRank(ids)` (`VS.KnownRank`, the belief's spellbook), `now` (t), `combat` (the combat start), and Lua's pure helpers (`math`, `min`, `max`, `floor`, `ceil`, `abs`, `type`, `select`, `tonumber`, `error`). No game API and no Hekili state are reachable. `.luacheckrc` declares those names for the specs (`nowEnv`).
- `VS.KnownRank(ids)` answers the highest known rank of a tracked rank list from the plain `IsSpellKnown` reads the Spellbook source already makes (`A.known[a]`, new), 0 when none is known or the list is untracked.
- `VS.Drain` becomes: flush, polls, `I.Fold(cutoff)` (the `stopAtCast` parameter goes), `I.Settle`, and Hekili's rescan flags from `AuraGen`; `I.pinned`, the resets, `I.Apply`, `I.applyErrors`/`I.applyError` and the read-before arrays go; `I.drainCasts` counts the casts the fold ran. `Snapshot()`'s drain line reads `casts=<n> errors=<now errors> now=<now runs>` (and `error=` the last). The facade's clock is `GetTime()` (no pinned cast time).
- Tests: `now_spec` (new) carries the brief's cases, the moved aura/energize-row case, a case running `removeBuff`, `spend`, `addStack` and `setCooldown` through the context, an untracked resource counted as an error, a `now` called outside a cast writing nothing, a tracked extra getting no effects, and an on-next-swing strike paying at its success; `adapter_spec` loses its apply cases (instant, hard cast, channel, raising apply and reset, trailing resets, Task 9's row cases, which move to `now_spec`) and gains "never resets or replays Hekili's state in the drain ..."; `fold_spec` loses "stops right after an own cast"; the fake spec's Rend and Battle Shout declare `now` (in `funcs`, as Hekili stores it).

The `I.feed.*` writes the design brief says stay were already retired by Tasks 6 and 7 (the combat-log rows write Hekili's cast history, queue and swing fields); nothing of them is left to keep.

**Files:**
- Create: `VirtualState/Families/Now.lua`, `VirtualState/spec/now_spec.lua`
- Modify: `VirtualState/Adapter.lua` (header; `CAST_SUCCESS`/`spendResources` locals; the read-before arrays; `VS.SpecChanged`; the apply section and `VS.Drain`), `VirtualState/Belief.lua` (`I.Fold`), `VirtualState/Facade.lua` (`now()`), `VirtualState/Snapshot.lua` (the drain line), `VirtualState/Sources/Spellbook.lua` (`resolve`: `A.known`), `Hekili.toc` (after `VirtualState\Families\Enemies.lua`), `.luacheckrc` (`nowEnv` for `VirtualState/spec/`)
- Test: `VirtualState/spec/adapter_spec.lua`, `VirtualState/spec/fold_spec.lua`, `VirtualState/spec/helpers/fake_spec.lua`

**Interfaces:**
- Consumes: `I.ResourceShift`, `I.AuraModel`, `I.CooldownModel`, `I.ChargesModel`, `I.GcdModel`, `I.CostOf`, `VS.Aura`, `VS.Power`, `VS.Talent`, `VS.Haste`, `I.gcdLearned`, `I.combatT` (Phase 1); `I.Log.Aura`, `I.Log.Energize` (Task 9).
- Produces: `VS.KnownRank(ids)`, `I.ab.now[a]`, `I.ab.known[a]`, `I.ab.extra[a]`, `I.nowCtx`, `I.nowErrors`, `I.nowError`, `I.nowRuns`, `I.castsRun`; a class file's ability field `now`; `I.Fold(upto)` (one argument).

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/adapter_spec.lua b/VirtualState/spec/adapter_spec.lua
index e5688269..1e999176 100644
--- a/VirtualState/spec/adapter_spec.lua
+++ b/VirtualState/spec/adapter_spec.lua
@@ -1,7 +1,5 @@
 -- VirtualState/spec/adapter_spec.lua: Adapter.lua against the fake spec provider (spec §3.6, §4.6, §5): the tracked
--- set from the registrations, the swing feed, and Drain's apply through the spec (the read-before /
--- read-after diff as `modelled` samples, two full resets, the offset restored, `updated` marked). The apply against
--- the real `state` is verified in game (spec §11).
+-- set from the registrations, and Drain (the fold; our casts' effects are Families/Now.lua's, see now_spec.lua).
 local load = require("VirtualState.spec.helpers.load")
 local fake = require("VirtualState.spec.helpers.fake_api")
 local fs = require("VirtualState.spec.helpers.fake_spec")
@@ -117,148 +115,6 @@ describe("Adapter", function()
         assert.are.equal(0, state.swings.mh_actual) -- CLEU_HANDLER writes it from the swing row
     end)
 
-    it("applies an instant cast through the spec: modelled rage, GCD and debuff, two resets, offset restored", function()
-        ctl.usable[fs.REND] = { true, false } -- rage >= 10 (the poll's rung)
-        ctl.now = 4
-        VS.Drain(4)
-        ctl.usable[fs.REND] = nil -- no answer after the cast
-        ctl.now = 5
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
-        ctl.Tick(5.05)
-        ctl.now = 5.1
-        VS.Drain(5.1)
-        assert.are.equal(2, state.resets)
-        assert.are.same({ 0, 0 }, { state.offset, state.delay })
-        assert.is_nil(I.pinned)
-        assert.are.equal(5 - 0.01, state.combat) -- rend starts combat (R2)
-        local rage = VS.Power(fs.RAGE, 5.1)
-        assert.are.equal("modelled", rage.basis)
-        assert.are.same({ 0, 0 }, { rage.est, rage.lo }) -- 10 seen at the poll, then 10 spent
-        assert.are.same({ 0, 5 }, { rage.last.modelled.v, rage.last.modelled.t })
-        local rend = VS.Aura("target", fs.REND, 5.1)
-        assert.are.same({ 20, "modelled" }, { rend.est, rend.basis })
-        assert.is_true(state.target.updated)
-        assert.are.same({ 6.5, "modelled" }, { VS.Gcd(5.1).est, VS.Gcd(5.1).basis })
-        assert.are.equal(1, I.drainCasts)
-    end)
-
-    -- A test ability on the fake spec, registered under its key and its spell ID.
-    local function register(key, t)
-        t.key, t.funcs = key, {}
-        t.charges, t.recharge = 1, 0
-        h.Class.abilities[key], h.Class.abilities[t.id] = t, t
-    end
-
-    local function near(want, got)
-        assert.is_true(math.abs(want - got) < 1e-6, ("want %s, got %s"):format(want, got))
-    end
-
-    it("emits our casts' aura and energize rows: APPLIED and REFRESH back-dated, REMOVED at the modelled expiry", function()
-        local rows = {}
-        local cleu = I.Events.CreateFrame("Frame")
-        cleu:SetScript("OnEvent", function()
-            local _, sub, _, src, _, _, _, dst, _, _, _, spellID, _, _, a15, _, a17 = ns.Facade.CombatLogGetCurrentEventInfo()
-            rows[#rows + 1] = { sub, dst, spellID, a15, a17, ns.Facade.GetTime() }
-        end)
-        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
-        register("rage_test", {
-            id = 2687,
-            cooldown = 60,
-            handler = function()
-                state.rage.actual = state.rage.actual + 10
-            end,
-        })
-        VS.SpecChanged()
-        I.ObsLog.Clear(I.log)
-        ctl.Fire("PLAYER_TARGET_CHANGED")
-        ctl.now = 5
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
-        ctl.Tick(5.05)
-        VS.Drain(5.1) -- the apply: Rend on the target until 20
-        ctl.Tick(5.15) -- delivered at the next OnUpdate
-        assert.are.same({ "SPELL_CAST_SUCCESS", "Creature-1", fs.REND }, { rows[1][1], rows[1][2], rows[1][3] })
-        assert.are.same({ "SPELL_AURA_APPLIED", "Creature-1", fs.REND, "DEBUFF", nil, 5 }, rows[2])
-        ctl.now = 8
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.REND)
-        ctl.Tick(8.05)
-        VS.Drain(8.1)
-        ctl.Tick(8.15)
-        assert.are.same({ "SPELL_AURA_REFRESH", 8 }, { rows[4][1], rows[4][6] })
-        ctl.now = 9
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 2687)
-        ctl.Tick(9.05)
-        VS.Drain(9.1)
-        ctl.Tick(9.15)
-        assert.are.same({ "SPELL_ENERGIZE", "Player-1", 2687, 10, fs.RAGE, 9 }, rows[6])
-        ctl.Tick(23.5) -- past Rend's modelled expiry (8 + 15)
-        assert.are.same({ "SPELL_AURA_REMOVED", "Creature-1", fs.REND, "DEBUFF", nil, 23.5 }, rows[7])
-    end)
-
-    it("emits no debuff row while there is no target to name", function()
-        local subs = {}
-        local cleu = I.Events.CreateFrame("Frame")
-        cleu:SetScript("OnEvent", function()
-            subs[#subs + 1] = select(2, ns.Facade.CombatLogGetCurrentEventInfo())
-        end)
-        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
-        ctl.guid.target = nil
-        ctl.Fire("PLAYER_TARGET_CHANGED")
-        ctl.now = 5
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
-        ctl.Tick(5.05)
-        VS.Drain(5.1)
-        ctl.Tick(30)
-        assert.are.same({ "SPELL_CAST_SUCCESS" }, subs)
-    end)
-
-    it("applies a hard cast at its finish: the GCD at the start's time, CAST_FINISH through HandleEvent", function()
-        register("slam_test", { id = 1464, cast = 1.5, cooldown = 0, spend = 15, spendType = "rage" })
-        VS.SpecChanged()
-        I.ObsLog.Clear(I.log)
-        ctl.now = 10
-        ctl.casting = { 10000, 11500 }
-        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-3", 1464)
-        ctl.Tick(10.05)
-        ctl.now = 11.5
-        ctl.casting = nil
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 1464)
-        ctl.Tick(11.55)
-        ctl.now = 11.6
-        VS.Drain(11.6)
-        assert.are.equal("slam_test", state.handled) -- HandleEvent ran the finish
-        near(11.5, state.cooldown.slam_test.expires) -- at the success time
-        near(11.5, VS.Gcd(11.6).est) -- the GCD began at the start (10 + 1.5)
-        assert.are.equal("modelled", VS.Gcd(11.6).basis)
-        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
-    end)
-
-    it("applies a channel at its start", function()
-        local ran = false
-        register("drain_test", {
-            id = 5555,
-            channeled = true,
-            cast = 3,
-            tick_time = 1,
-            cooldown = 10,
-            handler = function()
-                ran = true
-            end,
-        })
-        VS.SpecChanged()
-        I.ObsLog.Clear(I.log)
-        ctl.now = 20
-        ctl.channel = { 20000, 23000 }
-        ctl.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-4", 5555)
-        ctl.Tick(20.05)
-        ctl.now = 20.1
-        VS.Drain(20.1)
-        assert.is_true(ran) -- the handler
-        local cd = VS.Cooldown(5555, 20.1)
-        near(30, cd.est) -- the cooldown step at the channel's start
-        assert.are.equal("modelled", cd.basis)
-        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
-    end)
-
     it("folds a swing staged this frame before poll 3 clears the queued strike: the swing is skipped as paid", function()
         ctl.current[fs.STRIKE] = true
         ctl.now = 2
@@ -276,113 +132,15 @@ describe("Adapter", function()
         assert.are.equal(before, VS.Power(fs.RAGE, 3.1).est) -- no swing income
     end)
 
-    it("counts a raising apply and still restores: unpinned, offset 0, the trailing reset run", function()
-        register("boom_test", {
-            id = 7777,
-            cooldown = 0,
-            handler = function()
-                error("spec handler raised")
-            end,
-        })
-        VS.SpecChanged()
-        I.ObsLog.Clear(I.log)
-        ctl.now = 30
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", 7777)
-        ctl.Tick(30.05)
-        ctl.now = 30.1
-        VS.Drain(30.1)
-        assert.is_nil(I.pinned)
-        assert.are.same({ 0, 0, 2 }, { state.offset, state.delay, state.resets })
-        assert.are.equal(1, I.applyErrors)
-        assert.are.equal(0, I.drainCasts)
-        assert.is_truthy(VS.Snapshot():find("errors=1", 1, true))
-        assert.is_truthy(VS.Snapshot():find("spec handler raised", 1, true))
-    end)
-
-    it("counts a raising first reset, skips the apply and still restores", function()
-        local reset, raised = state.reset, false
-        state.reset = function()
-            if not raised then
-                raised = true
-                error("reset raised")
-            end
-            reset()
-        end
-        ctl.now = 32
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-8", fs.REND)
-        ctl.Tick(32.05)
-        ctl.now = 32.1
-        assert.has_no.errors(function()
-            VS.Drain(32.1)
-        end)
-        assert.is_nil(I.pinned)
-        assert.are.same({ 0, 0, 1 }, { state.offset, state.delay, state.resets }) -- only the trailing reset ran
-        assert.are.same({ 1, 0 }, { I.applyErrors, I.drainCasts })
-        assert.is_truthy(VS.Snapshot():find("reset raised", 1, true))
-    end)
-
-    it("runs no reset for an own cast of a tracked extra with no ability", function()
-        I.extra.abilities[1] = 6666
-        VS.SpecChanged()
-        I.extra.abilities[1] = nil
-        I.ObsLog.Clear(I.log)
-        ctl.now = 34
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 6666)
-        ctl.Tick(34.05)
-        ctl.now = 34.1
-        VS.Drain(34.1)
-        assert.are.same({ 0, 0, 0 }, { state.resets, I.applyErrors, I.drainCasts })
-    end)
-
-    it("rescans both units at the trailing reset, so an untracked apply-time aura write does not survive", function()
-        register("untracked_test", {
-            id = 8888,
-            cooldown = 0,
-            handler = function()
-                state.applyBuff("untracked_buff", 30)
-            end,
-        })
-        VS.SpecChanged()
-        I.ObsLog.Clear(I.log)
-        local reset = state.reset
-        state.reset = function() -- as Hekili's reset: an `updated` unit is scraped afresh (State.lua:6199-6207)
-            reset()
-            if state.player.updated then
-                state.buff.untracked_buff = nil -- the scrape finds no such aura
-                state.player.updated = false
-            end
-            if state.target.updated then
-                state.target.updated = false
-            end
-        end
-        ctl.now = 40
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-6", 8888)
-        ctl.Tick(40.05)
-        ctl.now = 40.1
-        VS.Drain(40.1)
-        assert.are.equal(2, state.resets)
-        assert.is_nil(state.buff.untracked_buff)
-    end)
-
-    it("marks no unit after the trailing reset rescanned both, even when the believed auras moved", function()
-        local reset = state.reset
-        state.reset = function() -- a scrape clears `updated` (State.lua:6199-6207)
-            reset()
-            state.player.updated, state.target.updated = false, false
-        end
-        ctl.now = 42
-        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-10", fs.REND)
-        ctl.Tick(42.05)
-        ctl.now = 42.1
-        local gen = VS.AuraGen("target")
-        VS.Drain(42.1)
-        assert.are_not.equal(gen, VS.AuraGen("target")) -- rend's debuff moved the target's set
-        assert.are.same({ 2, false, false }, { state.resets, state.player.updated, state.target.updated })
-    end)
-
-    it("runs no reset when the log holds no own cast", function()
+    it("never resets or replays Hekili's state in the drain, and marks a unit whose believed auras moved", function()
         ctl.now = 3
         VS.Drain(3)
-        assert.are.equal(0, state.resets)
+        ctl.now = 5
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.REND)
+        ctl.Tick(5.05)
+        VS.Drain(5.1)
+        assert.are.same({ 0, 0, 0 }, { state.resets, state.offset, state.delay })
+        assert.is_true(state.target.updated) -- Rend's `now` moved the target's set
+        assert.are.equal(1, I.drainCasts)
     end)
 end)
diff --git a/VirtualState/spec/fold_spec.lua b/VirtualState/spec/fold_spec.lua
index 342b386c..48b6154d 100644
--- a/VirtualState/spec/fold_spec.lua
+++ b/VirtualState/spec/fold_spec.lua
@@ -20,7 +20,7 @@ describe("the fold", function()
     it("starts the clock at the first observation and never moves it backward", function()
         I.started = false
         S.Direct(VS.Obs.Moving, 105, 0, 1)
-        I.Fold(110, false)
+        I.Fold(110)
         assert.are.equal(105, I.clock)
         I.Settle(110)
         assert.are.equal(110, I.clock)
@@ -30,21 +30,11 @@ describe("the fold", function()
         I.On(VS.Obs.Moving, function(o, t, lag)
             lagSeen = { t, lag }
         end)
-        I.Fold(111, false)
+        I.Fold(111)
         assert.are.same({ 110, 6 }, lagSeen)
         assert.are.equal(0, I.Dt(109))
     end)
 
-    it("stops right after an own cast and hands it back", function()
-        S.Direct(VS.Obs.Moving, 101, 0, 1)
-        S.Direct(VS.Obs.CastSuccess, 102, 3)
-        S.Direct(VS.Obs.Moving, 103, 0, 0)
-        assert.are.same({ VS.Obs.CastSuccess, 3, 102 }, { I.Fold(110, true) })
-        assert.is_true(VS.Moving())
-        assert.is_nil(I.Fold(110, true))
-        assert.is_false(VS.Moving())
-    end)
-
     it("stages event observations until the next frame and puts aura reads first", function()
         ctl.Fire("PLAYER_STARTED_MOVING")
         assert.are.equal(0, I.log.n)
diff --git a/VirtualState/spec/helpers/fake_spec.lua b/VirtualState/spec/helpers/fake_spec.lua
index cc279150..9ec6e4e5 100644
--- a/VirtualState/spec/helpers/fake_spec.lua
+++ b/VirtualState/spec/helpers/fake_spec.lua
@@ -70,7 +70,8 @@ function M.new(swingValue)
         talents = { improved_rend = { 0, 12286, 3 } },
     }
     local function ability(key, t)
-        t.key, t.funcs = key, {}
+        t.key, t.funcs = key, { now = t.now } -- Hekili keeps an unknown function field in `funcs`
+        t.now = nil
         t.cast, t.cooldown, t.charges, t.recharge = t.cast or 0, t.cooldown or 0, t.charges or 1, t.recharge or 0
         class.abilities[key] = t
         class.abilities[t.id] = t
@@ -84,6 +85,9 @@ function M.new(swingValue)
         handler = function()
             state.applyDebuff("rend", 15)
         end,
+        now = function()
+            applyDebuff("target", "rend", 15) -- the `now` context's verb (Families/Now.lua)
+        end,
     })
     ability("heroic_strike", { id = M.STRIKE, spend = 15, spendType = "rage", gcd = "off", onNextSwing = true })
     ability("battle_shout", {
@@ -93,6 +97,9 @@ function M.new(swingValue)
         handler = function()
             state.applyBuff("battle_shout", 120)
         end,
+        now = function()
+            applyBuff("battle_shout")
+        end,
     })
     class.auras.rend = { key = "rend", id = M.REND, copy = { M.REND_R2 }, duration = 15 }
     class.auras.battle_shout = { key = "battle_shout", id = M.SHOUT, duration = 120 }
@@ -156,7 +163,7 @@ end
 function M.fold(ns, t)
     local I = ns.VirtualStateInternal
     I.Sources.RunPolls(t)
-    I.Fold(t, false)
+    I.Fold(t)
     I.Settle(t)
 end
 
diff --git a/VirtualState/spec/now_spec.lua b/VirtualState/spec/now_spec.lua
new file mode 100644
index 00000000..a35b3193
--- /dev/null
+++ b/VirtualState/spec/now_spec.lua
@@ -0,0 +1,274 @@
+-- VirtualState/spec/now_spec.lua (event-facade spec §12a): a cast's effects on the belief. The automatic ones from the
+-- ability's declared fields (cost, cooldown, GCD) and the class file's `now` function, run in VirtualState's context
+-- with Hekili's verb names, as `modelled` samples at the cast's time; never Hekili's `state`.
+local load = require("VirtualState.spec.helpers.load")
+local fake = require("VirtualState.spec.helpers.fake_api")
+local fs = require("VirtualState.spec.helpers.fake_spec")
+local alloc = require("VirtualState.spec.helpers.alloc")
+
+describe("now handlers", function()
+    local ns, VS, I, api, ctl, h, state, saved, rows, cleu
+
+    local function register(key, t)
+        t.key, t.funcs = key, { now = t.now }
+        t.now = nil
+        t.cast, t.cooldown, t.charges, t.recharge = t.cast or 0, t.cooldown or 0, t.charges or 1, t.recharge or 0
+        h.Class.abilities[key], h.Class.abilities[t.id] = t, t
+    end
+
+    local function cast(id, t)
+        ctl.now = t
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
+        ctl.Tick(t + 0.01)
+        VS.Drain(t + 0.02)
+        ctl.Tick(t + 0.03) -- the drain's rows reach Hekili at the next delivery point
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
+        h = fs.new(9)
+        state = h.State
+        fs.clock = api.GetTime
+        ns.spendResources = fs.spend
+        ns.ResourceRegenerates = function()
+            return false
+        end
+        load.adapter(ns, h)
+        rows = {}
+        cleu = I.Events.CreateFrame("Frame")
+        cleu:SetScript("OnEvent", function()
+            local _, sub, _, _, _, _, _, dst, _, _, _, spellID, _, _, a15, _, a17 = ns.Facade.CombatLogGetCurrentEventInfo()
+            rows[#rows + 1] = { sub, dst, spellID, a15, a17, ns.Facade.GetTime() }
+        end)
+        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
+    end)
+
+    after_each(function()
+        for k, v in pairs(saved) do
+            _G[k] = v or nil
+        end
+        fs.clock = nil
+    end)
+
+    local function start()
+        VS.Start(api)
+        VS.SpecChanged()
+        ctl.Tick(1)
+        I.ObsLog.Clear(I.log)
+    end
+
+    it("writes the cost, the GCD and the `now` debuff as modelled samples at the cast's time", function()
+        start()
+        ctl.usable[fs.REND] = { true, false } -- rage >= 10 (the poll's rung)
+        ctl.now = 4
+        VS.Drain(4)
+        ctl.usable[fs.REND] = nil
+        cast(fs.REND, 5)
+        local rage = VS.Power(fs.RAGE, 5.1)
+        assert.are.same({ 0, "modelled", 5 }, { rage.est, rage.basis, rage.last.modelled.t })
+        local rend, stacks = VS.Aura("target", fs.REND, 5.1)
+        assert.are.same({ 20, "modelled", 1 }, { rend.est, rend.basis, stacks })
+        assert.are.equal("modelled", VS.Gcd(5.1).basis)
+        assert.is_true(VS.Gcd(5.1).est > 5)
+        assert.are.same({ 0, 0, 0 }, { state.resets, state.offset, state.delay }) -- Hekili's state untouched
+    end)
+
+    it("shifts a resource by `gain` (est, lo and hi) and writes its energize row back-dated to the cast", function()
+        register("rage_test", {
+            id = 2687,
+            cooldown = 60,
+            now = function()
+                gain(10, "rage")
+            end,
+        })
+        start()
+        local before = VS.Power(fs.RAGE, 9)
+        local est, lo, hi = before.est, before.lo, before.hi
+        cast(2687, 9)
+        local after = VS.Power(fs.RAGE, 9.1)
+        assert.are.same({ est + 10, lo + 10, math.min(hi + 10, 100) }, { after.est, after.lo, after.hi })
+        assert.are.same({ "modelled", 9, VS.Obs.CastSuccess }, { after.basis, after.last.modelled.t, after.last.modelled.event })
+        assert.are.equal(0, state.rage.actual) -- the `now` never touches Hekili's state
+        assert.are.same({ "SPELL_ENERGIZE", "Player-1", 2687, 10, fs.RAGE, 9 }, rows[#rows])
+        assert.is_true(VS.Cooldown(2687, 9.1).est > 60) -- the declared cooldown
+    end)
+
+    it("emits our casts' aura rows: APPLIED, REFRESH back-dated, REMOVED at the modelled expiry", function()
+        start()
+        ctl.Fire("PLAYER_TARGET_CHANGED")
+        cast(fs.REND, 5)
+        assert.are.same({ "SPELL_AURA_APPLIED", "Creature-1", fs.REND, "DEBUFF", nil, 5 }, rows[#rows])
+        cast(fs.REND, 8)
+        assert.are.same({ "SPELL_AURA_REFRESH", 8 }, { rows[#rows][1], rows[#rows][6] })
+        ctl.Tick(23.5) -- past Rend's modelled expiry (8 + 15)
+        assert.are.same({ "SPELL_AURA_REMOVED", "Creature-1", fs.REND, "DEBUFF", nil, 23.5 }, rows[#rows])
+        cast(fs.SHOUT, 30)
+        assert.are.same({ "SPELL_AURA_APPLIED", "Player-1", fs.SHOUT, "BUFF" }, { rows[#rows][1], rows[#rows][2], rows[#rows][3], rows[#rows][4] })
+        local shout = VS.Aura("player", fs.SHOUT, 30.1)
+        assert.are.equal(150, shout.est) -- the aura's registered duration (120) when the `now` passes none
+    end)
+
+    it("pays an on-next-swing strike's cost at its success, which arrives with its swing", function()
+        start()
+        cast(fs.STRIKE, 14)
+        local rage = VS.Power(fs.RAGE, 14.1)
+        assert.are.equal(14, rage.last.modelled.t)
+        assert.are.equal(-15, I.res.pinDelta[1])
+    end)
+
+    it("lets a later observation win over a `now` write, and not an earlier one", function()
+        start()
+        local j = I.auras.bySpell[fs.REND]
+        I.Sources.Direct(VS.Obs.Read, 4.9, I.AURA_UNIT + j, 0, I.ReadOf.Aura) -- an earlier read: down
+        cast(fs.REND, 5)
+        assert.are.equal("modelled", VS.Aura("target", fs.REND, 5.5).basis)
+        I.Sources.Direct(VS.Obs.Read, 6, I.AURA_UNIT + j, 0, I.ReadOf.Aura) -- a newer read: down
+        I.Fold(6.5)
+        assert.is_nil(VS.Aura("target", fs.REND, 6.5))
+    end)
+
+    it("changes only cost, cooldown and GCD for an ability without `now`", function()
+        register("plain_test", { id = 4444, cooldown = 6, spend = 5, spendType = "rage" })
+        start()
+        local gen = VS.AuraGen("player") + VS.AuraGen("target")
+        local n = #rows
+        cast(4444, 12)
+        assert.are.equal(gen, VS.AuraGen("player") + VS.AuraGen("target"))
+        assert.are.equal("modelled", VS.Cooldown(4444, 12.1).basis)
+        local rage = VS.Power(fs.RAGE, 12.1)
+        assert.are.equal(12, rage.last.modelled.t) -- the cost, written at the cast (the ladder's pin ties it)
+        assert.are.equal(n + 1, #rows) -- only the cast's own SPELL_CAST_SUCCESS row
+    end)
+
+    it("runs removeBuff, spend, addStack and setCooldown through the context with Hekili's signatures", function()
+        register("verbs_test", {
+            id = 6161,
+            now = function()
+                removeBuff("battle_shout")
+                spend(4, "rage")
+                addStack("rend", 15, 2)
+                setCooldown("verbs_test", 30)
+            end,
+        })
+        start()
+        cast(fs.SHOUT, 20) -- Battle Shout up (its `now`)
+        local before = VS.Power(fs.RAGE, 21)
+        local est = before.est
+        cast(6161, 21)
+        assert.is_nil(VS.Aura("player", fs.SHOUT, 21.1)) -- removeBuff
+        assert.are.equal(math.max(est - 4, 0), VS.Power(fs.RAGE, 21.1).est) -- spend
+        local rend, stacks = VS.Aura("player", fs.REND, 21.1)
+        assert.are.same({ 36, 2 }, { rend.est, stacks }) -- addStack( aura, duration, stacks ) on us
+        local cd = VS.Cooldown(6161, 21.1)
+        assert.are.same({ 51, "modelled" }, { cd.est, cd.basis }) -- setCooldown( action, duration )
+        assert.are.equal("SPELL_AURA_REMOVED", rows[#rows - 1][1])
+    end)
+
+    it("counts a gain or spend naming no tracked resource as the `now`'s error, writing nothing", function()
+        register("bad_test", {
+            id = 6262,
+            now = function()
+                gain(10, "health")
+            end,
+        })
+        start()
+        local est = VS.Power(fs.RAGE, 22).est
+        cast(6262, 22)
+        assert.are.equal(1, I.nowErrors)
+        assert.is_truthy(tostring(I.nowError):find("health", 1, true))
+        assert.are.equal(est, VS.Power(fs.RAGE, 22.1).est)
+    end)
+
+    it("writes nothing when a `now` runs outside a cast (RunStressTest, an APL reading action.x.now)", function()
+        start()
+        local a = I.ab.bySpell[fs.REND]
+        local gen = VS.AuraGen("target")
+        pcall(I.ab.now[a]) -- as DevTools' RunStressTest calls every function in ability.funcs
+        assert.are.equal(gen, VS.AuraGen("target"))
+        assert.is_nil(VS.Aura("target", fs.REND, 1.5))
+    end)
+
+    it("gives a tracked extra (VS.Track) no effects: no GCD, no cooldown", function()
+        I.extra.abilities[#I.extra.abilities + 1] = 9898
+        start()
+        local g = VS.Gcd(30).basis
+        cast(9898, 30)
+        assert.are.equal(g, VS.Gcd(30.1).basis)
+        assert.are.equal(0, I.castsRun)
+    end)
+
+    it("counts a raising `now` and keeps folding the observations after it", function()
+        register("boom_test", {
+            id = 7777,
+            now = function()
+                error("now raised")
+            end,
+        })
+        start()
+        cast(7777, 30)
+        assert.are.equal(1, I.nowErrors)
+        assert.is_truthy(tostring(I.nowError):find("now raised"))
+        cast(fs.REND, 31)
+        assert.are.equal(31 + 15, VS.Aura("target", fs.REND, 31.1).est)
+        assert.is_truthy(VS.Snapshot():find("errors=1", 1, true))
+    end)
+
+    it("reads talents, auras and resources through the context and answers knownRank from the belief", function()
+        local seen = {}
+        register("read_test", {
+            id = 5151,
+            now = function()
+                seen.rank = talent.improved_rend.rank
+                seen.none = talent.not_a_talent.rank
+                seen.rend = debuff.rend.up
+                seen.shout = buff.battle_shout.remains
+                seen.rage = rage.current
+                seen.known = knownRank({ 772, 6546 })
+                seen.t = now
+            end,
+        })
+        start()
+        I.SetTalentRank(1, 2)
+        cast(fs.REND, 40)
+        cast(5151, 41)
+        assert.are.same({ 2, 0, true, 0, 41 }, { seen.rank, seen.none, seen.rend, seen.shout, seen.t })
+        assert.is_number(seen.rage)
+        assert.are.equal(0, seen.known) -- no rank in the fake spellbook
+        ctl.known[fs.REND_R2] = true
+        ctl.Fire("SPELLS_CHANGED")
+        cast(5151, 42)
+        assert.are.equal(2, seen.known)
+    end)
+
+    it("allocates nothing across 1000 casts with `now` handlers", function()
+        register("rage_test", {
+            id = 2687,
+            now = function()
+                gain(1, "rage")
+                applyDebuff("target", "rend", 15)
+                local _ = talent.improved_rend.rank + rage.current
+            end,
+        })
+        start()
+        function h:ForceUpdate() end -- the fake records each call; Hekili's own only sets fields
+        cleu:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED") -- the capturing subscriber allocates by design
+        local t = 50
+        local bytes = alloc.bytes(function()
+            t = t + 1
+            cast(2687, t)
+            cast(fs.REND, t + 0.5)
+        end, 1000)
+        assert.are.equal(0, bytes)
+    end)
+end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `175 successes / 9 failures / 1 error` (`now_spec`: the GCD and debuff come from the apply, not a modelled `now` write at the cast's time, and the verbs, the error count and the extras do not exist yet; `adapter_spec.lua:142`: the drain still resets Hekili's state).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/.luacheckrc b/.luacheckrc
index ceeecb20..974f3a85 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -91,7 +91,12 @@ files["UI.lua"] = { globals = stateEnv }
 files["Utils.lua"] = { globals = stateEnv }
 files["Hekili.lua"] = { globals = stateEnv }
 files["Constants.lua"] = { globals = stateEnv }
-files["VirtualState/spec/"] = { std = "+busted" }
+-- The names a class file's `now` function reads in VirtualState's context (VirtualState/Families/Now.lua).
+local nowEnv = {
+    "gain", "spend", "applyBuff", "applyDebuff", "removeBuff", "removeDebuff", "addStack", "setCooldown", "talent",
+    "buff", "debuff", "knownRank", "now", "combat", "rage", "energy", "mana", "focus", "runic_power",
+}
+files["VirtualState/spec/"] = { std = "+busted", read_globals = nowEnv }
 files["Forever/spec/"] = { std = "+busted" }
 -- The Warrior's handlers, state expressions and state functions run with setfenv( f, state ) as well; these are the
 -- further `state` names they use.
diff --git a/Hekili.toc b/Hekili.toc
index 977beb4b..cc61ef69 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -21,6 +21,7 @@ VirtualState\Families\TargetCast.lua
 VirtualState\Families\Talents.lua
 VirtualState\Families\Totems.lua
 VirtualState\Families\Enemies.lua
+VirtualState\Families\Now.lua
 VirtualState\Sources\Sources.lua
 VirtualState\Sources\Player.lua
 VirtualState\Sources\Spellbook.lua
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index 5d23024c..a8ca263f 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -1,19 +1,16 @@
 -- VirtualState/Adapter.lua
 -- VirtualState's glue to Hekili (spec §3.6, §4.6, §5): VirtualState.Start at PLAYER_LOGIN, the tracked set from the
--- active spec's registrations (SpecChanged), and Drain: the fold plus "apply through the spec", which runs each of
--- our real casts through Hekili's own registered functions on `state` and records what changed as `modelled` samples.
+-- active spec's registrations (SpecChanged), and Drain: the fold, whose own casts write their effects through the
+-- class files' `now` handlers (Families/Now.lua), never through Hekili's `state`.
 -- Hekili's across-reset caches (cast history, the real queue, the swing fields) come from the combat-log rows.
--- Loads after Core.lua. The apply follows Hekili's own simulation (Core.lua:1984-2045) and keeps Hekili's credits.
+-- Loads after Core.lua.
 
 local addon, ns = ...
 local VS, I = ns.VirtualState, ns.VirtualStateInternal
 local S = I.Sources
-local Obs = VS.Obs
-local CAST_SUCCESS, CHANNEL_START = Obs.CastSuccess, Obs.ChannelStart
 
 local Hekili = _G[addon]
 local state, class = Hekili.State, Hekili.Class
-local spendResources = ns.spendResources
 local GetTime, CreateFrame = ns.Facade.GetTime, ns.Facade.CreateFrame
 local debugprofilestop = debugprofilestop
 local insert, sort = table.insert, table.sort
@@ -101,15 +98,10 @@ local function sortedKeys(t)
     return keys
 end
 
-local resourceKey, auraKey, auraId = {}, {}, {}
-
 local function buildDef()
     for _, list in pairs(def) do
         wipe(list)
     end
-    wipe(resourceKey)
-    wipe(auraKey)
-    wipe(auraId)
     local slotByKey = {}
     for _, k in ipairs(sortedKeys(class.resources)) do
         local r = class.resources[k]
@@ -146,7 +138,6 @@ local function buildDef()
             decay = r.state and r.state.meta and r.state.meta.decay, -- out-of-combat loss per second (Resources.lua)
         }
         insert(def.resources, d)
-        resourceKey[#def.resources] = k
         slotByKey[k] = #def.resources
     end
     for _, k in ipairs(sortedKeys(class.abilities)) do
@@ -174,7 +165,6 @@ local function buildDef()
             if #ids > 0 then
                 insert(def.auras, a)
                 def.auraIds[#def.auras] = ids
-                auraKey[#def.auras], auraId[#def.auras] = k, ids[1]
             end
         end
     end
@@ -196,171 +186,19 @@ local function buildDef()
     end
 end
 
--- Read-before arrays for the apply (spec §5.3), sized at SpecChanged.
-local resBefore, cdBefore, buffExp, buffApp, buffCnt, debuffExp, debuffApp, debuffCnt = {}, {}, {}, {}, {}, {}, {}, {}
-local gcdBefore = 0
-
 --- Rebuilds the tracked set from the active spec (decision 8). Called at the end of Hekili:SpecializationChanged,
 --- after every registration. Allocates; SpecChanged only.
 function VS.SpecChanged()
     buildDef()
     I.Build(def, GetTime())
-    for i = 1, #def.resources do
-        resBefore[i] = 0
-    end
-    for a = 1, #def.abilities do
-        cdBefore[a] = 0
-    end
-    for j = 1, #def.auras do
-        buffExp[j], buffApp[j], buffCnt[j], debuffExp[j], debuffApp[j], debuffCnt[j] = 0, 0, 0, 0, 0, 0
-    end
 end
 
 ----------------------------------------------------------------------------------------------------------------------
--- Apply through the spec (spec §5.2, §5.3).
+-- The drain (event-facade spec §12a): our casts' effects are written by the `now` handlers as the fold reaches them
+-- (Families/Now.lua); Hekili's state is never reset or replayed here.
 
-local finishEvent = { type = "CAST_FINISH", action = "", time = 0, start = 0 }
-
-local function field(t, k)
-    return t and rawget(t, k) or 0
-end
-
--- Step 3.5: the tracked fields before the apply. Each tracked resource's `actual` is set to the belief at the cast
--- first, so a spend is never clipped at 0 by a stale `actual` (the cast succeeded: the game had the cost).
-local function readBefore(t)
-    local R = I.res
-    for r = 1, R.n do
-        local res = rawget(state, resourceKey[r])
-        if res then
-            local v = VS.Power(R.type[r], t).est
-            res.actual, res.fcount = v, 0
-            resBefore[r] = v
-        end
-    end
-    local A, cooldown = I.ab, state.cooldown
-    for a = 1, A.n do
-        cdBefore[a] = field(rawget(cooldown, A.key[a]), "expires")
-    end
-    gcdBefore = field(rawget(cooldown, "global_cooldown"), "expires")
-    local buff, debuff = state.buff, state.debuff
-    for j = 1, I.auras.nAura do
-        local k = auraKey[j]
-        local b, d = k and rawget(buff, k), k and rawget(debuff, k)
-        buffExp[j], buffApp[j], buffCnt[j] = field(b, "expires"), field(b, "applied"), field(b, "count")
-        debuffExp[j], debuffApp[j], debuffCnt[j] = field(d, "expires"), field(d, "applied"), field(d, "count")
-    end
-end
-
--- Step 3.7: what changed, as `modelled` samples at t.
-local function readAfter(t, kind, a)
-    local R, spellID = I.res, I.ab.qid[a]
-    for r = 1, R.n do
-        local res = rawget(state, resourceKey[r])
-        if res then
-            local delta = res.actual - resBefore[r]
-            if delta > 1e-6 or delta < -1e-6 then
-                I.ResourceShift(r, delta, t, kind)
-            end
-            if delta > 1e-6 then
-                I.Log.Energize(spellID, delta, R.type[r], R.max[r], t) -- the cast gave us resource
-            end
-        end
-    end
-    local A, cooldown = I.ab, state.cooldown
-    for a = 1, A.n do
-        local cd = rawget(cooldown, A.key[a])
-        local e = field(cd, "expires")
-        if e ~= cdBefore[a] then
-            if A.ch[a] then
-                I.ChargesModel(a, field(cd, "charge"), e, t, kind)
-            else
-                I.CooldownModel(a, e, field(cd, "duration"), t, kind)
-            end
-        end
-    end
-    local g = field(rawget(cooldown, "global_cooldown"), "expires")
-    if g ~= gcdBefore then
-        I.GcdModel(g, t, kind)
-    end
-    local buff, debuff = state.buff, state.debuff
-    for j = 1, I.auras.nAura do
-        local k = auraKey[j]
-        if k then
-            local b, d = rawget(buff, k), rawget(debuff, k)
-            local be, de = field(b, "expires"), field(d, "expires")
-            if be ~= buffExp[j] or field(b, "count") ~= buffCnt[j] then
-                I.AuraModel(1, j, field(b, "applied"), be, field(b, "count"), t, kind, false)
-                I.Log.Aura(1, j, auraId[j], buffExp[j], be, t)
-            end
-            if (de ~= debuffExp[j] or field(d, "count") ~= debuffCnt[j]) and I.auras.n >= 2 then
-                I.AuraModel(2, j, field(d, "applied"), de, field(d, "count"), t, kind, true)
-                I.Log.Aura(2, j, auraId[j], debuffExp[j], de, t)
-            end
-        end
-    end
-end
-
-local function gcdStep(ability)
-    if ability.gcd ~= "off" and state.cooldown.global_cooldown.remains == 0 then
-        state.setCooldown("global_cooldown", state.gcd.execute)
-    end
-end
-
-local function cooldownStep(key, ability)
-    if ability.charges and ability.charges > 1 and ability.recharge > 0 then
-        state.spendCharges(key, 1)
-    elseif ability.cooldown > 0 then
-        state.setCooldown(key, ability.cooldown)
-    end
-end
-
--- Steps 3.3-3.7 for one own cast of ability index `a` at t.
-local function apply(kind, a, t)
-    local key = I.ab.key[a]
-    local ability = key and class.abilities[key]
-    if not ability or not ability.id or ability.id <= 0 then
-        return false
-    end
-    -- 3.3: combat start (R2), the value PLAYER_REGEN_DISABLED writes (Events.lua:856-863)
-    if ability.startsCombat and state.combat == 0 then
-        state.combat = t - 0.01
-    end
-    readBefore(t)
-    local now = state.now
-    if kind == CHANNEL_START then
-        state.offset, state.delay = t - now, 0
-        gcdStep(ability)
-        cooldownStep(key, ability)
-        state:RunHandler(key) -- takes the channel path (State.lua:6135-6137)
-        spendResources(key)
-    elseif (ability.cast or 0) > 0 and not ability.channeled then
-        -- a hard cast, at its finish: the GCD at its start, then the CAST_FINISH event at the finish
-        local started = I.ab.castStartT[a]
-        if started > 0 and started < t then
-            state.offset, state.delay = started - now, 0
-            gcdStep(ability)
-        end
-        state.offset, state.delay = t - now, 0
-        finishEvent.action, finishEvent.time, finishEvent.start = key, t, started
-        state:HandleEvent(finishEvent) -- charges/cooldown, spend, handler (State.lua:5921-5953)
-    else
-        state.offset, state.delay = t - now, 0
-        gcdStep(ability)
-        cooldownStep(key, ability)
-        spendResources(key)
-        state:RunHandler(key)
-    end
-    readAfter(t, kind, a)
-    return true
-end
-I.Apply = apply
-
--- Applies (or the drain's first reset) whose spec code raised, and the last error (Snapshot's log line); the drain
--- carries on so its restore always runs.
-I.applyErrors, I.applyError = 0, nil
-
---- The fold plus apply through the spec (spec §5.2), called only from Hekili.Update after its guards. Allocates
---- nothing beyond what Hekili's own reset and handlers allocate.
+--- The fold, called only from Hekili.Update after its guards: this frame's staged observations, the polls, the fold
+--- to the cut-off, the settle, and Hekili's rescan flags. Allocates nothing.
 ---@param cutoff number GetTime() at the drain's entry
 function VS.Drain(cutoff)
     if not I.built then
@@ -368,51 +206,17 @@ function VS.Drain(cutoff)
     end
     local t0 = debugprofilestop()
     local genP, genT = VS.AuraGen("player"), VS.AuraGen("target")
+    local casts = I.castsRun
     S.Flush() -- this frame's staged observations first, whichever OnUpdate runs first (poll 3's Queued(0) follows them)
-    S.RunPolls(cutoff) -- step 1
-    local applied, reset, resetOk = 0, false, false
-    while true do
-        local kind, a, t = I.Fold(cutoff, true) -- steps 2 and 3.8
-        if not kind then
-            break
-        end
-        local key = I.ab.key[a]
-        if key and class.abilities[key] then -- a track_<id> extra has no ability to apply
-            I.pinned = t -- 3.1: the facade answers at the cast's time (R1)
-            if not reset then
-                reset = true
-                local err
-                resetOk, err = pcall(state.reset) -- 3.2: once, full ("Primary", State.lua:6181-6184)
-                if not resetOk then
-                    I.applyErrors, I.applyError = I.applyErrors + 1, err
-                end
-            end
-            if resetOk then
-                local ok, done = pcall(apply, kind, a, t)
-                if not ok then
-                    I.applyErrors, I.applyError = I.applyErrors + 1, done
-                elseif done then
-                    applied = applied + 1
-                end
-            end
-        end
-    end
-    -- 4: restore, unpin, settle, and one more full reset when anything was applied (R2, R3)
-    state.offset, state.delay = 0, 0
-    I.pinned = nil
+    S.RunPolls(cutoff)
+    I.Fold(cutoff)
     I.Settle(cutoff)
-    if reset then
-        -- the trailing reset rescans both units' auras, so an apply-time write outside the tracked set never survives
-        state.player.updated, state.target.updated = true, true
-        state.reset()
-    else
-        -- 5: Hekili rescans a unit's auras when its believed set moved (G1)
-        if VS.AuraGen("player") ~= genP then
-            state.player.updated = true
-        end
-        if VS.AuraGen("target") ~= genT then
-            state.target.updated = true
-        end
+    -- Hekili rescans a unit's auras when its believed set moved (G1)
+    if VS.AuraGen("player") ~= genP then
+        state.player.updated = true
     end
-    I.drainMs, I.drainCasts = debugprofilestop() - t0, applied
+    if VS.AuraGen("target") ~= genT then
+        state.target.updated = true
+    end
+    I.drainMs, I.drainCasts = debugprofilestop() - t0, I.castsRun - casts
 end
diff --git a/VirtualState/Belief.lua b/VirtualState/Belief.lua
index e9a6cad6..c55b9460 100644
--- a/VirtualState/Belief.lua
+++ b/VirtualState/Belief.lua
@@ -9,7 +9,6 @@ local _, ns = ...
 local VS, I = ns.VirtualState, ns.VirtualStateInternal
 local At, Shift = I.ObsLog.At, I.ObsLog.Shift
 local Obs = VS.Obs
-local CAST_SUCCESS, CHANNEL_START = Obs.CastSuccess, Obs.ChannelStart
 
 local APPLY, ADVANCE, SETTLE = {}, {}, {}
 
@@ -47,12 +46,11 @@ local function advance(t)
 end
 I.Advance = advance
 
---- Folds the log in order (spec §5.2 steps 2 and 3.8). With `stopAtCast`, returns right after applying an own cast
---- (CastSuccess or ChannelStart) as `kind, ability, t`; otherwise folds everything stamped at or before `upto` and
---- returns nil. An observation older than the clock is applied at the clock with `lag`. Allocates nothing.
+--- Folds the log in order (spec §5.2 step 2): everything stamped at or before `upto`; an own cast's effects are
+--- written by its appliers (Families/Now.lua). An observation older than the clock is applied at the clock with
+--- `lag`. Allocates nothing.
 ---@param upto number
----@param stopAtCast boolean
-function I.Fold(upto, stopAtCast)
+function I.Fold(upto)
     local log = I.log
     if not I.started then
         -- The clock starts at the first thing heard, not at 0 (TDF Belief.lua:723-728).
@@ -78,9 +76,6 @@ function I.Fold(upto, stopAtCast)
                 list[k](o, t, lag)
             end
         end
-        if stopAtCast and (kind == CAST_SUCCESS or kind == CHANNEL_START) then
-            return kind, o.a, t
-        end
     end
     return nil
 end
diff --git a/VirtualState/Facade.lua b/VirtualState/Facade.lua
index da30a0fa..f23db22e 100644
--- a/VirtualState/Facade.lua
+++ b/VirtualState/Facade.lua
@@ -183,9 +183,9 @@ local function plainTimes(info, startKey, durationKey)
     return type(s) == "number" and type(d) == "number"
 end
 
--- The facade's clock: the pinned cast time during a drain, else GetTime().
+-- The facade's clock.
 local function now()
-    return I.pinned or GetTime()
+    return GetTime()
 end
 Facade.Now = now
 
diff --git a/VirtualState/Families/Now.lua b/VirtualState/Families/Now.lua
new file mode 100644
index 00000000..7a3027f2
--- /dev/null
+++ b/VirtualState/Families/Now.lua
@@ -0,0 +1,302 @@
+-- VirtualState/Families/Now.lua
+-- `now` handlers (event-facade spec §12a): what our cast did to the now-state, written into the belief at the cast.
+-- On each own CastSuccess (a channel's included) the family writes the automatic effects from the ability's declared fields
+-- (its cost, its cooldown or charge, the GCD), then runs the ability's `now` function, if the class file declared
+-- one beside `handler`, in one shared context whose names are Hekili's verbs (`gain`, `spend`, `applyBuff`,
+-- `applyDebuff`, `removeBuff`, `removeDebuff`, `addStack`, `setCooldown`) and reads (`talent`, `buff`, `debuff`, the
+-- resources by key, `knownRank`, `now`, `combat`) with belief meanings. Every write is a `modelled` sample at the
+-- cast's time, so any later observation overrides it (I.Basis). Hekili's sim `handler` is never read for truth.
+-- Allocates nothing per cast: the context, its proxies and every per-ability array are built at SpecChanged.
+
+local _, ns = ...
+local VS, I = ns.VirtualState, ns.VirtualStateInternal
+local Obs = VS.Obs
+local CAST = Obs.CastSuccess
+
+local A = I.ab
+A.now = {} -- by ability index: the `now` function, bound to the context, or false
+A.extra = {} -- by ability index: a `track_<id>` extra (VS.Track): no ability, no effects
+A.known = A.known or {} -- by ability index: any rank in the spellbook (Sources/Spellbook.lua)
+
+-- The one environment of every `now` function: the verbs and reads below, and Lua's own pure helpers (no game API,
+-- no Hekili state, nothing that allocates by itself).
+local SAFE = {
+    math = math,
+    min = math.min,
+    max = math.max,
+    floor = math.floor,
+    ceil = math.ceil,
+    abs = math.abs,
+    type = type,
+    select = select,
+    tonumber = tonumber,
+    error = error,
+}
+local ctx = setmetatable({}, { __index = SAFE })
+I.nowCtx = ctx
+I.nowErrors, I.nowError, I.nowRuns, I.castsRun = 0, nil, 0, 0
+
+-- The cast's belief time and ability while its effects run; `live` only then: a `now` called from anywhere else (Hekili
+-- keeps it in `ability.funcs`, where RunStressTest or an APL reading `action.x.now` can call it) writes nothing.
+local T, curA, live = 0, 0, false
+local abByKey, auraByKey, auraSpell, auraDur, resByKey = {}, {}, {}, {}, {}
+
+----------------------------------------------------------------------------------------------------------------------
+-- Reads: proxies built at SpecChanged, answered from the belief at the cast's time.
+
+local function auraField(r, f)
+    local rec, stacks, applied = VS.Aura(rawget(r, "unit"), rawget(r, "spell"), T)
+    if f == "up" then
+        return rec ~= nil
+    elseif f == "down" then
+        return rec == nil
+    elseif f == "remains" then
+        return rec and rec.est - T or 0
+    elseif f == "stack" or f == "count" then
+        return rec and stacks or 0
+    elseif f == "expires" then
+        return rec and rec.est or 0
+    elseif f == "applied" then
+        return rec and applied or 0
+    end
+    return nil
+end
+local auraMeta = { __index = auraField }
+local NO_AURA = setmetatable({ unit = "player", spell = 0 }, auraMeta)
+local function noAura()
+    return NO_AURA
+end
+ctx.buff = setmetatable({}, { __index = noAura })
+ctx.debuff = setmetatable({}, { __index = noAura })
+
+local talentMeta = {
+    __index = function(r, f)
+        local rank = VS.Talent(rawget(r, "spell"))
+        if f == "rank" then
+            return rank
+        elseif f == "enabled" then
+            return rank > 0
+        end
+        return nil
+    end,
+}
+local NO_TALENT = setmetatable({ spell = 0 }, talentMeta)
+ctx.talent = setmetatable({}, {
+    __index = function()
+        return NO_TALENT
+    end,
+})
+
+local resourceMeta = {
+    __index = function(r, f)
+        local pt = rawget(r, "type")
+        if f == "current" then
+            return VS.Power(pt, T).est
+        elseif f == "max" then
+            return I.res.max[I.res.slotOf[pt]] or 0
+        end
+        return nil
+    end,
+}
+
+--- The highest known rank of a tracked ability's rank list (1-based), 0 when none is known or the list is untracked.
+--- Reads the belief's spellbook, never the game: the class file's own `knownRank` may call it in both its sim and its
+--- `now` environments. Allocates nothing.
+function VS.KnownRank(ids)
+    local a = ids and A.bySpell[ids[1]]
+    if not a or not A.known[a] then
+        return 0
+    end
+    local q = A.qid[a]
+    for k = #ids, 1, -1 do
+        if ids[k] == q then
+            return k
+        end
+    end
+    return 0
+end
+ctx.knownRank = VS.KnownRank
+
+----------------------------------------------------------------------------------------------------------------------
+-- Writes: Hekili's verbs, as `modelled` belief samples at T (and the combat log's aura and energize rows).
+
+local function shift(n, resource)
+    if not live then
+        return
+    end
+    local r = resByKey[resource]
+    if not r then
+        error("now: no tracked resource " .. tostring(resource), 3) -- counted as the `now`'s error; no write
+    end
+    if type(n) ~= "number" or n == 0 then
+        return
+    end
+    I.ResourceShift(r, n, T, CAST)
+    if n > 0 then
+        I.Log.Energize(A.qid[curA], n, I.res.type[r], I.res.max[r], T)
+    end
+end
+function ctx.gain(amount, resource)
+    shift(amount, resource)
+end
+function ctx.spend(amount, resource)
+    shift(type(amount) == "number" and -amount or amount, resource)
+end
+
+local function aura(u, key, duration, stacks)
+    local j = auraByKey[key]
+    if not live or not j or (u == 2 and I.auras.n < 2) then
+        return
+    end
+    local rec = VS.Aura(u == 1 and "player" or "target", auraSpell[j], T)
+    local before = rec and rec.est or 0
+    local after = 0
+    if duration ~= 0 then
+        local d = duration or auraDur[j]
+        if type(d) ~= "number" then
+            return -- the aura's registered duration is a function (Hekili's state): the `now` must pass one
+        end
+        after = T + d
+    end
+    I.AuraModel(u, j, T, after, stacks or 1, T, CAST, u == 2)
+    I.Log.Aura(u, j, auraSpell[j], before, after, T)
+end
+-- Hekili's own signatures (State.lua), so a Classic handler's lines port by copying.
+function ctx.applyBuff(aura_, duration, stacks)
+    aura(1, aura_, duration, stacks)
+end
+function ctx.applyDebuff(unit, aura_, duration, stacks)
+    aura(unit == "player" and 1 or 2, aura_, duration, stacks)
+end
+function ctx.removeBuff(aura_)
+    aura(1, aura_, 0)
+end
+function ctx.removeDebuff(unit, aura_)
+    aura(unit == "player" and 1 or 2, aura_, 0)
+end
+function ctx.addStack(aura_, duration, stacks)
+    local j = auraByKey[aura_]
+    if not live or not j then
+        return
+    end
+    local _, have = VS.Aura("player", auraSpell[j], T)
+    aura(1, aura_, duration, (have or 0) + (stacks or 1))
+end
+function ctx.setCooldown(action, duration)
+    local a = abByKey[action]
+    if live and a and type(duration) == "number" then
+        I.CooldownModel(a, T + duration, duration, T, CAST)
+    end
+end
+
+----------------------------------------------------------------------------------------------------------------------
+-- The tracked set: keys to indices, proxies, and each ability's `now` bound to the context.
+
+I.OnBuild(function(def)
+    for k in pairs(abByKey) do
+        abByKey[k] = nil
+    end
+    for k in pairs(auraByKey) do
+        auraByKey[k] = nil
+    end
+    for k in pairs(resByKey) do
+        ctx[k], resByKey[k] = nil, nil
+    end
+    for k in pairs(ctx.buff) do
+        ctx.buff[k], ctx.debuff[k] = nil, nil
+    end
+    for k in pairs(ctx.talent) do
+        ctx.talent[k] = nil
+    end
+    for a = 1, A.n do
+        abByKey[A.key[a]] = a
+        A.known[a] = A.known[a] or false
+        A.extra[a] = type(A.key[a]) == "string" and A.key[a]:sub(1, 6) == "track_"
+        local obj = def.abilities[a]
+        local funcs = type(obj) == "table" and rawget(obj, "funcs")
+        local f = type(funcs) == "table" and rawget(funcs, "now") -- Hekili keeps unknown functions in `funcs`
+        A.now[a] = type(f) == "function" and setfenv(f, ctx) or false
+    end
+    for j = 1, #def.auras do
+        local key = def.auras[j].key
+        auraSpell[j] = def.auraIds[j][1]
+        local d = rawget(def.auras[j], "duration")
+        auraDur[j] = type(d) == "number" and d or false
+        if key then
+            auraByKey[key] = j
+            ctx.buff[key] = setmetatable({ unit = "player", spell = auraSpell[j] }, auraMeta)
+            ctx.debuff[key] = setmetatable({ unit = "target", spell = auraSpell[j] }, auraMeta)
+        end
+    end
+    for r = 1, #def.resources do
+        local d = def.resources[r]
+        if d.key then
+            resByKey[d.key] = r
+            ctx[d.key] = setmetatable({ type = d.type }, resourceMeta)
+        end
+    end
+    for k = 1, #def.talents do
+        local d = def.talents[k]
+        ctx.talent[d.key] = setmetatable({ spell = d.spell }, talentMeta)
+    end
+end)
+
+----------------------------------------------------------------------------------------------------------------------
+-- The trigger: our cast's automatic effects, then its `now`.
+
+local function automatic(a, t, kind)
+    local obj = A.obj[a]
+    local r = A.slot[a]
+    if r > 0 then -- an on-next-swing strike's success arrives with its swing, which is when it pays
+        local c = I.CostOf(a)
+        if c > 0 then
+            I.ResourceShift(r, -c, t, kind)
+        end
+    end
+    if A.ch[a] then
+        local recharge = type(obj.recharge) == "number" and obj.recharge or 0
+        local charges = A.charges0[a] - 1
+        local nextAt = A.next0[a] > t and A.next0[a] or t + recharge
+        I.ChargesModel(a, charges > 0 and charges or 0, nextAt, t, kind)
+    else
+        local cd = obj.cooldown
+        if type(cd) == "number" and cd > 0 then
+            I.CooldownModel(a, t + cd, cd, t, kind)
+        end
+    end
+    if obj.gcd ~= "off" then
+        local start = t
+        if kind == CAST and A.castStartT[a] > 0 and A.castStartT[a] < t then
+            start = A.castStartT[a] -- a hard cast's GCD began at its start
+        end
+        local h = VS.Haste(t).est
+        local len = I.gcdLearned > 0 and I.gcdLearned or 1.5 / (h > 0 and h or 1) -- nonzero: h > 0 checked
+        if start + len > t then
+            I.GcdModel(start + len, t, kind)
+        end
+    end
+end
+
+local function run(o, t)
+    local a = o.a
+    if not A.obj[a] or not A.key[a] or A.extra[a] then
+        return
+    end
+    automatic(a, t, o.kind)
+    I.castsRun = I.castsRun + 1
+    local f = A.now[a]
+    if f then
+        T, curA = t, a
+        ctx.now = t
+        ctx.combat = I.combatT
+        live = true
+        local ok, err = pcall(f)
+        live = false
+        I.nowRuns = I.nowRuns + 1
+        if not ok then
+            I.nowErrors, I.nowError = I.nowErrors + 1, err
+        end
+    end
+end
+-- CastSuccess only: a channel stages ChannelStart and CastSuccess both (Sources/Casts.lua), and must run once.
+I.On(Obs.CastSuccess, run)
diff --git a/VirtualState/Snapshot.lua b/VirtualState/Snapshot.lua
index 22def121..5baaa47e 100644
--- a/VirtualState/Snapshot.lua
+++ b/VirtualState/Snapshot.lua
@@ -27,17 +27,18 @@ function VS.Snapshot()
         tostring(I.moving)
     )
     out[#out + 1] = format(
-        "log %d/%d dropped=%d stage dropped=%d drain=%.2fms casts=%d errors=%d",
+        "log %d/%d dropped=%d stage dropped=%d drain=%.2fms casts=%d errors=%d now=%d",
         I.log.n,
         I.log.cap,
         I.log.dropped,
         S.dropped,
         I.drainMs or 0,
         I.drainCasts or 0,
-        I.applyErrors or 0
+        I.nowErrors or 0,
+        I.nowRuns or 0
     )
-    if I.applyError ~= nil then
-        out[#out] = out[#out] .. " error=" .. tostring(I.applyError)
+    if I.nowError ~= nil then
+        out[#out] = out[#out] .. " error=" .. tostring(I.nowError)
     end
     local names = {}
     for name in pairs(S.status) do
diff --git a/VirtualState/Sources/Spellbook.lua b/VirtualState/Sources/Spellbook.lua
index edbd477e..729a5d7e 100644
--- a/VirtualState/Sources/Spellbook.lua
+++ b/VirtualState/Sources/Spellbook.lua
@@ -23,13 +23,16 @@ local last, gcdLast = {}, -1
 local function resolve(api)
     local A = I.ab
     for a = 1, A.n do
-        local ids, q = A.ids[a], A.ids[a][1]
+        local ids, q, known = A.ids[a], A.ids[a][1], false
         for k = 1, #ids do
             if Plain(api, api.C_SpellBook.IsSpellKnown(ids[k])) == true then
-                q = ids[k]
+                q, known = ids[k], true
             end
         end
         A.qid[a] = q
+        if A.known then
+            A.known[a] = known -- VS.KnownRank (Families/Now.lua)
+        end
         if not I.inCombat and A.slot[a] > 0 then
             local raw = api.C_Spell.GetSpellPowerCost(q) -- secret: Plain next, then each field
             local costs = Plain(api, raw)
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `185 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [185 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 74 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 48 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Families/Now.lua VirtualState/Adapter.lua VirtualState/Belief.lua VirtualState/Facade.lua VirtualState/Snapshot.lua VirtualState/Sources/Spellbook.lua Hekili.toc .luacheckrc VirtualState/spec/now_spec.lua VirtualState/spec/adapter_spec.lua VirtualState/spec/fold_spec.lua VirtualState/spec/helpers/fake_spec.lua
git commit -m "feat(virtualstate): now handlers: a cast's effects from the declared fields and the class file's now function, in a context of Hekili's verbs mapped onto the belief; the drain no longer resets or replays Hekili's state

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 11: Race packs and the resource definition's `maxMods` and `costMods`

Spec §12b (the user's approved design, 2026-10-15: race packs; it supersedes a shared `all`-spec registration with a per-class scope table). Placed right after Task 10 because it extends `I.CostOf` and Task 10's automatic cost step.

Racials are race content, not class content. The layout and the core change:
- **Folders.** `Forever/Warrior.lua` moves to `Forever/Classes/Warrior.lua` (a `git mv`; its first line names the new path; the TOC, `.luacheckrc`, the loader `Forever/spec/helpers/load_warrior.lua` and the comment in `tools/make_pack.lua` follow; `Forever/spec/` keeps its place). `Forever/Races/Gnome.lua` is new; the TOC lists every race file unconditionally, after the class file. Races with only Hekili's stock racials (Berserking, Blood Fury, Stoneform, Shadowmeld, Will to Survive) stay in the shared `all` spec.
- **Race token** (named core edit, `State.lua`): at load the core reads UnitRace's second return, the locale-free token, into `state.race_token`, and sets `state.race[ formatKey( token ) ]` beside Hekili's localized key.
- **`Hekili:NewRace( token )`** (`Races.lua`, new, Hekili core, TOC right after `State.lua`): a registration object with `RegisterAbility( key, def )` and `RegisterAura( key, def )` (into the shared `all` spec, over `all`'s own entry for the same key; the race keeps the keys it registered, `copy` aliases included), `RegisterResourceMod{ max = pct }` (every resource the loaded class registered) and `RegisterCostMod{ aura, pct | flat, charges, spells = { IDs } }`. On a race that is not the player's, every call is accepted and inert, so a race file always runs and loads headless. Hekili's merge in `SpecializationChanged` (`Classes.lua:3258-3268` at `75d71c8b`) takes the class first and `all` last and only adds missing keys, so a race entry would lose to the class's; `ns.applyRace( class )`, one named call after the merge loop, writes the race's keys over `class.abilities` and `class.auras`: a race registration wins a key clash with the class and with `all`. The modifiers go to `ns.raceMods`, which the adapter copies into every resource definition (`maxMods`, `costMods`).
- **`Forever/Races/Gnome.lua`**: Eureka! (1259813 with the other classes' 1259812, 1259817, 1259821, 1259823 as `copy`; cooldown 120, off the GCD, a handler and a `now` applying `eureka` for 15 s with 3 stacks), its aura, Expansive Mind (`RegisterResourceMod{ max = 0.05 }`), and Eureka!'s cost modifier `{ aura = "eureka", pct = -0.10, charges = 3, spells = { ... } }`. Eureka!'s cost effect is spell-family masked in the DB2 (1784679630 / 5 / 1 / 0 against SpellClassSet 4 for the Warrior), so it lists the 17 Warrior abilities it covers by the class file's own rank-1 IDs (checked against `Forever/Warrior.lua` at `75d71c8b`: 78, 845, 1240193, 5308, 7384, 12294, 23881, 1680, 23922, 6572, 6343, 1715, 20252, 694, 6552, 72, 1310222), higher ranks matching through the class's `copy` lists; not Rend, Sunder Armor, the shouts, Concussion Blow, Death Wish, Disarm, Retaliation, Shield Block or Sweeping Strikes. The comment gives the masks and the wowdb query for a later class.
- **`maxMods`** (contract in `VirtualState/Families/Modifiers.lua`'s header): the declared `max` (a number or a state-bound function, default 100) × Π(1 + pct) over the modifiers whose `when` holds. One evaluator: the Resources family's `maxOf` applies it, so the build seeds the interval (`hi0`) at the raised maximum, and each CombatEnd re-evaluates it until a plain maximum read wins for good. The adapter copies `maxMods` into every resource but the point resources (`combo_points`, `runes`, `soul_shards`, `holy_power`, `chi`, `arcane_charges`, `essence`): Expansive Mind's percentage does not apply to a count. Until Task 13 drops the Warrior's own Gnome stopgap (`max` 105 for a Gnome), a Gnome Warrior's declared rage maximum is 110.25 (no checkpoint falls in between).
- **`costMods` in the belief**: `spells` resolve at the build to ability indices through `I.ab.bySpell` (every id and `copy` rank of a tracked ability; an ID the class does not register is absent; no `spells`: every ability paid from the resource). `I.CostOf(a)` passes the declared cost through `I.CostMod(a, slot, cost, I.clock)`: each modifier in a's scope whose aura is believed up applies (`pct` multiplies, `flat` adds; floored at 0), so the ladder's pin and Task 10's automatic cost step pay the modified cost; with `charges`, an in-scope cast whose declared cost is above 0 (`I.BaseCostOf(a) > 0`, so a cast the discount made free still pays: `pct = -1, charges = 1` is Clearcasting's shape) spends one believed stack (`I.SpendCostCharges`, a modelled sample; at 0 the aura goes), and an observed aura read still wins by `I.Basis`.
- **`costMods` in the simulation: one declaration, two readers** (named core edits). `Races.lua` also wraps every ability's `spend` when `Classes.lua`'s RegisterAbility builds it (one call, `ns.costMods.Wrap( a )`): reading `ability.spend` (what `action.<x>.cost`, `ns.hasRequiredResources`, `state:TimeToReady` and `ns.spendResources` read, `State.lua:2113-2121, 5007-5021, 7062-7092, 7138-7148, 6608-6636` at 75d71c8b) answers the declared cost through the modifiers in the ability's scope (no `spells`: every ability paid from the resource, as in the belief; else its `id` or a `copy` rank listed, cached per ability key once) whose buff is up in the simulated state, a fraction-of-maximum cost (below 1) taking the same `pct` as in the belief; `ability.baseSpend` keeps the declared cost, which `I.CostOf` reads so the belief applies its own modifiers once. `ns.spendResources` calls `ns.costMods.Spend( action.baseSpend, ability )` before its `cost ~= 0` test: when the declared cost is above 0 (the same gate as the belief's), each charged modifier in scope whose buff is up loses a stack (`state.removeStack`), even when the discounted cost is 0. A `spend` hook was not used: `state.spend` also runs for spends that are no ability's cost (the Warrior's stance swap), which must take no charge.

**Files:**
- Create: `Races.lua`, `Forever/Races/Gnome.lua`, `VirtualState/Families/Modifiers.lua`, `VirtualState/spec/modifiers_spec.lua`, `VirtualState/spec/races_spec.lua`
- Move: `Forever/Warrior.lua` → `Forever/Classes/Warrior.lua`
- Modify: `VirtualState/Families/Casts.lua` (`I.CostOf`, `I.BaseCostOf`), `VirtualState/Families/Now.lua` (the automatic cost step), `VirtualState/Families/Resources.lua` (`maxOf` applies `maxMods`), `VirtualState/Adapter.lua` (`buildDef`: `ns.raceMods` into each resource, `POINTS`), `Classes.lua` (RegisterAbility's `ns.costMods.Wrap( a )`; `ns.applyRace( class )` after the merge loop), `State.lua` (the race token; `ns.spendResources`' charge), `Hekili.toc` (`Races.lua` after `State.lua`; `VirtualState\Families\Modifiers.lua` after `VirtualState\Families\Now.lua`; the class file's new path and `Forever\Races\Gnome.lua` after it), `.luacheckrc` (the class file's path; `Forever/Races/`), `Forever/spec/helpers/load_warrior.lua` (the path), `tools/make_pack.lua` (comment :6)

**Interfaces:**
- Consumes: `I.CostOf`, the automatic cost step (Task 10); `VS.Aura`, `I.AuraModel`, `I.res`, `I.ab.bySpell`, `I.ReadOf.Max` (Phase 1).
- Produces: `Hekili:NewRace( token )` and its four registration methods; `state.race_token`, `state.race.<token>`; `ns.raceMods`; resource definition fields `maxMods` and `costMods` (with `spells`); `I.mods`, `I.CostMod(a, r, cost, now)`, `I.SpendCostCharges(a, r, t, event)`, `I.BaseCostOf(a)`; `ns.applyRace( class )`; `Hekili.RaceMods` (`ns.raceMods`, for the in-game checkpoint); `ns.costMods` (`Apply`, `Spend( baseCost, key )`, `Wrap`), `ability.baseSpend`; the Gnome's `eureka` ability and aura.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/modifiers_spec.lua b/VirtualState/spec/modifiers_spec.lua
new file mode 100644
index 00000000..4fffa752
--- /dev/null
+++ b/VirtualState/spec/modifiers_spec.lua
@@ -0,0 +1,149 @@
+-- VirtualState/spec/modifiers_spec.lua (event-facade spec §12b): the resource definition's `maxMods` and `costMods`,
+-- as a race pack declares them (Races.lua's ns.raceMods: Expansive Mind, Eureka!), through the adapter.
+local load = require("VirtualState.spec.helpers.load")
+local fake = require("VirtualState.spec.helpers.fake_api")
+local fs = require("VirtualState.spec.helpers.fake_spec")
+local alloc = require("VirtualState.spec.helpers.alloc")
+
+local EUREKA = 1259813
+
+describe("resource modifiers", function()
+    local ns, VS, I, api, ctl, h, saved
+
+    local function cast(id, t)
+        ctl.now = t
+        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
+        ctl.Tick(t + 0.01)
+        VS.Drain(t + 0.02)
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
+        h = fs.new(9)
+        fs.clock = api.GetTime
+        ns.spendResources = fs.spend
+        ns.ResourceRegenerates = function()
+            return false
+        end
+        h.Class.auras.eureka = { key = "eureka", id = EUREKA, duration = 15 }
+        -- the Gnome race pack's declarations (Forever/Races/Gnome.lua through Races.lua), as Adapter.lua reads them
+        ns.raceMods = {
+            maxMods = { { pct = 0.05 } },
+            costMods = { { aura = "eureka", pct = -0.10, charges = 3, spells = { fs.STRIKE, 999999 } } },
+        }
+        function h:ForceUpdate() end
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
+    it("raises the maximum by Expansive Mind through the modifier, until a plain read", function()
+        assert.are.equal(105, I.res.max[1]) -- 100 declared x 1.05
+        assert.are.equal(105, I.res.hi0[1]) -- one evaluator: the interval is seeded at the raised maximum
+        I.Sources.Direct(VS.Obs.CombatEnd, 2)
+        I.Fold(2)
+        assert.are.equal(105, I.res.max[1])
+        I.Sources.Direct(VS.Obs.Read, 3, 1, 120, I.ReadOf.Max)
+        I.Fold(3)
+        I.Sources.Direct(VS.Obs.CombatEnd, 4)
+        I.Fold(4)
+        assert.are.equal(120, I.res.max[1]) -- the plain read keeps winning
+        ns.raceMods = { maxMods = {}, costMods = {} } -- another race: no modifier
+        VS.SpecChanged()
+        assert.are.equal(100, I.res.max[1])
+    end)
+
+    it("takes 10% off Heroic Strike while Eureka! is up and spends a charge a cast; Rend, out of scope, neither", function()
+        local strike, rend = I.ab.bySpell[fs.STRIKE], I.ab.bySpell[fs.REND]
+        assert.are.equal(15, I.CostOf(strike))
+        local j = I.auras.bySpell[EUREKA]
+        I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false) -- Eureka! up with its three charges
+        I.clock = 5
+        assert.are.same({ 13.5, 10 }, { I.CostOf(strike), I.CostOf(rend) })
+        cast(fs.REND, 5.5)
+        local _, stacks = VS.Aura("player", EUREKA, 5.6)
+        assert.are.equal(3, stacks) -- Rend took no charge
+        for k = 1, 3 do
+            cast(fs.STRIKE, 5.5 + k)
+            _, stacks = VS.Aura("player", EUREKA, 5.5 + k + 0.05)
+            assert.are.equal(3 - k > 0 and 3 - k or nil, stacks)
+        end
+        assert.is_nil(VS.Aura("player", EUREKA, 8.6))
+        assert.are.equal(15, I.CostOf(strike))
+    end)
+
+    it("lets an observed aura read win over the charges it modelled", function()
+        local j = I.auras.bySpell[EUREKA]
+        I.AuraModel(1, j, 5, 20, 3, 5, VS.Obs.CastSuccess, false)
+        cast(fs.STRIKE, 6) -- 2 left, modelled
+        I.Sources.Direct(VS.Obs.Read, 6.5, j, 13.5, I.ReadOf.Aura + 3 * I.AURA_STACK) -- the client says 3
+        I.Fold(6.6)
+        local _, stacks = VS.Aura("player", EUREKA, 6.7)
+        assert.are.equal(3, stacks)
+    end)
+
+    it("never raises a point resource's maximum", function()
+        h.Class.resources.combo_points = { type = 4 }
+        VS.SpecChanged()
+        local R = I.res
+        assert.are.same({ 105, 100 }, { R.max[R.slotOfToken.RAGE], R.max[R.slotOfToken.COMBO_POINTS] })
+    end)
+
+    it("matches a listed `copy` rank, and every ability of the resource when `spells` is absent", function()
+        local strike, rend = I.ab.bySpell[fs.STRIKE], I.ab.bySpell[fs.REND]
+        ns.raceMods.costMods = { { aura = "eureka", pct = -0.10, spells = { fs.REND_R2 } } }
+        VS.SpecChanged()
+        I.AuraModel(1, I.auras.bySpell[EUREKA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
+        I.clock = 5
+        assert.are.same({ 15, 9 }, { I.CostOf(strike), I.CostOf(rend) }) -- Rend by its rank 2 ID
+        ns.raceMods.costMods = { { aura = "eureka", pct = -0.10 } }
+        VS.SpecChanged()
+        I.AuraModel(1, I.auras.bySpell[EUREKA], 5, 20, 3, 5, VS.Obs.CastSuccess, false)
+        assert.are.same({ 13.5, 9 }, { I.CostOf(strike), I.CostOf(rend) })
+    end)
+
+    it("spends a charge on a cast the modifier made free (pct = -1, the Clearcasting shape)", function()
+        local strike = I.ab.bySpell[fs.STRIKE]
+        ns.raceMods.costMods = { { aura = "eureka", pct = -1, charges = 1, spells = { fs.STRIKE } } }
+        VS.SpecChanged()
+        I.AuraModel(1, I.auras.bySpell[EUREKA], 5, 20, 1, 5, VS.Obs.CastSuccess, false)
+        I.clock = 5
+        assert.are.equal(0, I.CostOf(strike))
+        cast(fs.STRIKE, 6)
+        assert.is_nil(VS.Aura("player", EUREKA, 6.1)) -- the free cast took the charge
+        assert.are.equal(15, I.CostOf(strike))
+    end)
+
+    it("allocates nothing over 1000 casts with both modifiers declared", function()
+        local j = I.auras.bySpell[EUREKA]
+        local t = 10
+        local bytes = alloc.bytes(function()
+            t = t + 1
+            I.AuraModel(1, j, t, t + 15, 3, t, VS.Obs.CastSuccess, false)
+            cast(fs.STRIKE, t + 0.5)
+            cast(fs.REND, t + 0.7)
+        end, 1000)
+        assert.are.equal(0, bytes)
+    end)
+
+end)
diff --git a/VirtualState/spec/races_spec.lua b/VirtualState/spec/races_spec.lua
new file mode 100644
index 00000000..c7544111
--- /dev/null
+++ b/VirtualState/spec/races_spec.lua
@@ -0,0 +1,155 @@
+-- VirtualState/spec/races_spec.lua (event-facade spec §12b): race packs. Races.lua's `Hekili:NewRace` and the Gnome's
+-- pack (Forever/Races/Gnome.lua), loaded headless against a stand-in for Hekili: inert for another race, registered for
+-- the Gnome; and the simulation's half of the cost modifier on abilities built as RegisterAbility builds them.
+
+describe("race packs", function()
+    local ns, hekili, state, all, saved
+
+    -- Hekili's state.removeStack (State.lua:857-868), on the fake buff table.
+    local function removeStack(aura, stacks)
+        stacks = stacks or 1
+        local b = state.buff[aura]
+        if b.count > stacks then
+            b.count = math.max(1, b.count - stacks)
+        else
+            state.buff[aura] = nil
+        end
+    end
+
+    local function load(token, seed)
+        state = {
+            race_token = token,
+            buff = setmetatable({}, {
+                __index = function()
+                    return { up = false, count = 0 }
+                end,
+            }),
+            removeStack = removeStack,
+        }
+        all = { abilities = seed or {}, auras = {} } -- `seed`: what Classes.lua's `all` already registered
+        function all:RegisterAbility(key, def)
+            self.abilities[key] = def
+        end
+        function all:RegisterAura(key, def)
+            self.auras[key] = def
+        end
+        hekili = { State = state, Class = { specs = { [0] = all }, abilities = {} } }
+        _G.Hekili = hekili
+        ns = {}
+        assert(loadfile("Races.lua"))("Hekili", ns)
+        assert(loadfile("Forever/Races/Gnome.lua"))("Hekili", ns)
+    end
+
+    -- An ability as Classes.lua's RegisterAbility builds it: function fields in `funcs`, called on access, wrapped.
+    local function ability(key, data)
+        local a = setmetatable({ funcs = {} }, {
+            __index = function(t, k)
+                if t.funcs[k] then
+                    return t.funcs[k]()
+                end
+            end,
+        })
+        a.key = key
+        for k, v in pairs(data) do
+            if type(v) == "function" then
+                a.funcs[k] = v
+            else
+                a[k] = v
+            end
+        end
+        ns.costMods.Wrap(a)
+        hekili.Class.abilities[key] = a
+        return a
+    end
+
+    before_each(function()
+        saved = rawget(_G, "Hekili") or false
+    end)
+
+    after_each(function()
+        _G.Hekili = saved or nil
+    end)
+
+    it("is inert for another race: nothing registered, no modifier", function()
+        load("Human")
+        assert.are.same({}, all.abilities)
+        assert.are.same({}, all.auras)
+        assert.are.same({ maxMods = {}, costMods = {} }, ns.raceMods)
+    end)
+
+    it("registers Eureka!, its aura and both modifiers for a Gnome, into the shared spec (the race wins a clash)", function()
+        load("Gnome", { eureka = { id = 1 } }) -- a stock `all` registration under the same key
+        assert.are.equal(1259813, all.abilities.eureka.id) -- the race file loads later and wins
+        assert.are.equal(3, all.auras.eureka.max_stack)
+        assert.is_function(all.abilities.eureka.now)
+        assert.are.same({ { pct = 0.05 } }, ns.raceMods.maxMods)
+        assert.are.same({ "eureka", -0.10, 3, 17 }, {
+            ns.raceMods.costMods[1].aura,
+            ns.raceMods.costMods[1].pct,
+            ns.raceMods.costMods[1].charges,
+            #ns.raceMods.costMods[1].spells,
+        })
+    end)
+
+    it("writes the race's abilities and auras over the class's after Classes.lua's merge, aliases too", function()
+        load("Gnome")
+        local class = { abilities = { eureka = { id = 2 } }, auras = { eureka = { id = 2 } } } -- the class's own
+        ns.applyRace(class)
+        assert.are.same({ 1259813, 1259813 }, { class.abilities.eureka.id, class.auras.eureka.id })
+        load("Human")
+        class = { abilities = { eureka = { id = 2 } }, auras = {} }
+        ns.applyRace(class)
+        assert.are.equal(2, class.abilities.eureka.id) -- inert for another race
+    end)
+
+    it("covers every ability without `spells`, and spends a charge on a cast made free (pct = -1)", function()
+        load("Gnome")
+        ns.raceMods.costMods[1] = { aura = "eureka", pct = -1, charges = 1 }
+        local rend = ability("rend", { id = 772, spend = 10, spendType = "rage" })
+        state.buff.eureka = { up = true, count = 1 }
+        assert.are.equal(0, rend.spend)
+        ns.costMods.Spend(rend.baseSpend, "rend") -- ns.spendResources passes the declared cost
+        assert.is_false(state.buff.eureka.up)
+        assert.are.equal(10, rend.spend)
+    end)
+
+    it("applies pct to a fraction-of-maximum cost", function()
+        load("Gnome")
+        local strike = ability("heroic_strike", { id = 78, spend = 0.2, spendType = "rage" })
+        state.buff.eureka = { up = true, count = 3 }
+        assert.is_true(math.abs(strike.spend - 0.18) < 1e-9)
+    end)
+
+    it("prices Heroic Strike at 13.5 with Eureka! up in the simulation, three casts remove it; Rend stays 10", function()
+        load("Gnome")
+        local heroic_strike = ability("heroic_strike", { id = 78, copy = { 284, 285 }, spend = 15, spendType = "rage" })
+        local rend = ability("rend", { id = 772, spend = 10, spendType = "rage" })
+        local cleave = ability("cleave", { id = 99999, copy = { 845 }, spend = function() return 20, "rage" end })
+        assert.are.equal(15, heroic_strike.spend)
+        state.buff.eureka = { up = true, count = 3 }
+        assert.are.same({ 13.5, 10, 18 }, { heroic_strike.spend, rend.spend, cleave.spend }) -- cleave by a copy rank
+        assert.are.equal(15, heroic_strike.baseSpend) -- the belief reads the declared cost
+        ns.costMods.Spend(rend.baseSpend, "rend") -- out of scope: no charge
+        assert.are.equal(3, state.buff.eureka.count)
+        for k = 1, 3 do
+            ns.costMods.Spend(heroic_strike.baseSpend, "heroic_strike") -- ns.spendResources' call
+            if k < 3 then
+                assert.are.equal(3 - k, state.buff.eureka.count)
+            end
+        end
+        assert.is_false(state.buff.eureka.up)
+        assert.are.equal(15, heroic_strike.spend)
+    end)
+
+    it("ignores a listed spell the class does not register", function()
+        load("Gnome")
+        local shout = ability("battle_shout", { id = 6673, spend = 10 })
+        state.buff.eureka = { up = true, count = 3 }
+        assert.has_no.errors(function()
+            ns.costMods.Spend(shout.baseSpend, "battle_shout")
+            ns.costMods.Spend(5, "not_an_ability")
+        end)
+        assert.are.equal(10, shout.spend)
+        assert.are.equal(3, state.buff.eureka.count)
+    end)
+end)
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `187 successes / 12 failures / 0 errors` (`modifiers_spec`: the maximum stays 100, the costs stay 15 and 10 and no charge is spent; `races_spec`: `cannot open Races.lua`).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/.luacheckrc b/.luacheckrc
index 974f3a85..ae56dde1 100644
--- a/.luacheckrc
+++ b/.luacheckrc
@@ -107,4 +107,5 @@ local warriorEnv = {
 for _, k in ipairs(stateEnv) do
     warriorEnv[#warriorEnv + 1] = k
 end
-files["Forever/Warrior.lua"] = { globals = warriorEnv }
+files["Forever/Classes/Warrior.lua"] = { globals = warriorEnv }
+files["Forever/Races/"] = { globals = stateEnv }
diff --git a/Classes.lua b/Classes.lua
index 3bd7a121..ffb66d3a 100644
--- a/Classes.lua
+++ b/Classes.lua
@@ -793,6 +793,9 @@ local HekiliSpecMixin = {
             end
         end
 
+        -- The race packs' cost modifiers in the simulation (Races.lua, event-facade spec §12b).
+        ns.costMods.Wrap( a )
+
         if ( a.velocity or a.flightTime ) and a.impact and a.isProjectile == nil then
             a.isProjectile = true
         end
@@ -3330,6 +3333,9 @@ function Hekili:SpecializationChanged()
         end
     end
 
+    -- The race pack's abilities and auras win a key clash with the class's and `all`'s (Races.lua, spec §12b).
+    ns.applyRace( class )
+
     for k in pairs( class.abilityList ) do
         local ability = class.abilities[ k ]
 
diff --git a/Forever/Warrior.lua b/Forever/Classes/Warrior.lua
similarity index 99%
rename from Forever/Warrior.lua
rename to Forever/Classes/Warrior.lua
index ff407b70..190446de 100644
--- a/Forever/Warrior.lua
+++ b/Forever/Classes/Warrior.lua
@@ -1,4 +1,4 @@
--- Forever/Warrior.lua
+-- Forever/Classes/Warrior.lua
 -- The Forever Warrior (pseudo-spec 1491): the Classic Warrior kit with Forever's spell data (ranks, costs, cooldowns,
 -- cast times and durations from the Forever DB2 at build 1.60.1.70338, wowdb, a cost of 100 there being 10 rage; the
 -- client is 1.60.1.70374, and its export wins where they differ), Forever's Victory Rush and Spearing Strike, rage per
diff --git a/Forever/Races/Gnome.lua b/Forever/Races/Gnome.lua
new file mode 100644
index 00000000..2e8f1942
--- /dev/null
+++ b/Forever/Races/Gnome.lua
@@ -0,0 +1,54 @@
+-- Forever/Races/Gnome.lua
+-- The Gnome's Forever racials (DB2 1.60.1.70338), for every class: Eureka! (15 s: the next 3 abilities in its scope
+-- cost 10% less, +10% damage not modelled; 120 s, off the GCD) and Expansive Mind (+5% maximum resources: 20591
+-- Priest/Mage/Warlock, 1259802 Warrior, 1259803 Rogue). Inert for any other race (Races.lua).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local race = Hekili:NewRace( "Gnome" )
+
+local EUREKA = { 1259812, 1259817, 1259821, 1259823 } -- the other classes' Eureka!
+
+race:RegisterAbility( "eureka", {
+    id = 1259813,
+    copy = EUREKA,
+    cast = 0,
+    cooldown = 120,
+    gcd = "off",
+    startsCombat = false,
+    toggle = "cooldowns",
+
+    handler = function ()
+        applyBuff( "eureka", 15, 3 )
+    end,
+    -- VirtualState's now-state of the cast (event-facade spec §12a)
+    now = function ()
+        applyBuff( "eureka", 15, 3 )
+    end,
+} )
+
+race:RegisterAura( "eureka", {
+    id = 1259813,
+    copy = EUREKA,
+    duration = 15,
+    max_stack = 3,
+} )
+
+race:RegisterResourceMod( { max = 0.05 } ) -- Expansive Mind: +5% maximum resources
+
+race:RegisterCostMod( {
+    aura = "eureka",
+    pct = -0.10,
+    charges = 3,
+    -- Eureka! 1259813 effect 0: aura 108 (ADD_PCT_MODIFIER) misc 14 (cost) -10, class masks
+    -- 1784679630 / 5 / 1 / 0 against SpellClassSet 4 (Warrior). Other classes: append their IDs from
+    -- select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
+    --   join SpellPower p on p.SpellID=o.SpellID where o.SpellClassSet=<set> and p.ManaCost>0 and not
+    --   ((o.SpellClassMask_0 & 1784679630)=0 and (o.SpellClassMask_1 & 5)=0 and (o.SpellClassMask_2 & 1)=0)
+    -- Warrior: heroic_strike, cleave, slam, execute, overpower, mortal_strike, bloodthirst, whirlwind, shield_slam,
+    -- revenge, thunder_clap, hamstring, intercept, mocking_blow, pummel, shield_bash, spearing_strike (rank 1 IDs;
+    -- higher ranks resolve through the class's `copy` lists). Not: rend, sunder_armor, the shouts, concussion_blow,
+    -- death_wish, disarm, retaliation, shield_block, sweeping_strikes.
+    spells = { 78, 845, 1240193, 5308, 7384, 12294, 23881, 1680, 23922, 6572, 6343, 1715, 20252, 694, 6552, 72, 1310222 },
+} )
diff --git a/Forever/spec/helpers/load_warrior.lua b/Forever/spec/helpers/load_warrior.lua
index 2cda0b06..e13a3a43 100644
--- a/Forever/spec/helpers/load_warrior.lua
+++ b/Forever/spec/helpers/load_warrior.lua
@@ -1,7 +1,7 @@
 -- Forever/spec/helpers/load_warrior.lua
--- Loads Forever/Warrior.lua headless against a recording stand-in for Hekili: every spec:RegisterX call is kept by
--- method name, ns.VirtualState.Track's tables are merged, and the plain game reads the file captures at load answer
--- from `game` (known spells, queued spells, usability, the shapeshift form, VirtualState's per-hand base weapon
+-- Loads Forever/Classes/Warrior.lua headless against a recording stand-in for Hekili: each spec:RegisterX call is
+-- kept by method name, ns.VirtualState.Track's tables are merged, and the plain game reads the file captures at load
+-- answer from `game` (known spells, queued spells, usability, the shapeshift form, VirtualState's per-hand base weapon
 -- speeds). `env()` is a stand-in `state` for running
 -- the file's handlers, state functions and hooks (Hekili runs them with setfenv( f, state )).
 local M = {}
@@ -80,7 +80,7 @@ function M.load()
             end,
         },
     }
-    local ok, err = pcall(assert(loadfile("Forever/Warrior.lua")), "Hekili", ns)
+    local ok, err = pcall(assert(loadfile("Forever/Classes/Warrior.lua")), "Hekili", ns)
     for k, v in pairs(saved) do
         _G[k] = v or nil
     end
diff --git a/Hekili.toc b/Hekili.toc
index cc61ef69..abc90078 100644
--- a/Hekili.toc
+++ b/Hekili.toc
@@ -22,6 +22,7 @@ VirtualState\Families\Talents.lua
 VirtualState\Families\Totems.lua
 VirtualState\Families\Enemies.lua
 VirtualState\Families\Now.lua
+VirtualState\Families\Modifiers.lua
 VirtualState\Sources\Sources.lua
 VirtualState\Sources\Player.lua
 VirtualState\Sources\Spellbook.lua
@@ -47,10 +48,12 @@ Formatting.lua
 MultilineEditor.lua
 Constants.lua
 State.lua
+Races.lua
 Events.lua
 
 Classes.lua
-Forever\Warrior.lua
+Forever\Classes\Warrior.lua
+Forever\Races\Gnome.lua
 
 Targets.lua
 Options\DevTools.lua
diff --git a/Races.lua b/Races.lua
new file mode 100644
index 00000000..703d8380
--- /dev/null
+++ b/Races.lua
@@ -0,0 +1,160 @@
+-- Races.lua
+-- Race packs (event-facade spec §12b). `Hekili:NewRace( token )` returns a registration object a race file
+-- (Forever/Races/<Race>.lua) uses like a spec: RegisterAbility, RegisterAura, RegisterResourceMod, RegisterCostMod.
+-- Registrations count only when the token is the player's race (`state.race_token`, UnitRace's locale-free second
+-- return); otherwise they are accepted and inert, so every race file runs unconditionally and loads headless.
+-- Abilities and auras go to the shared `all` spec (over `all`'s own entry for the same key), and ns.applyRace writes
+-- them over the class's after Classes.lua's merge (which takes the class first and only adds missing keys), so a race
+-- registration wins a key clash with the class and with `all`. Resource and cost modifiers go to `ns.raceMods`, one
+-- declaration read by two layers:
+-- VirtualState's belief (VirtualState/Families/Modifiers.lua, through Adapter.lua) and Hekili's simulation (below).
+
+local addon, ns = ...
+local Hekili = _G[ addon ]
+
+local mods = { maxMods = {}, costMods = {} }
+ns.raceMods = mods
+Hekili.RaceMods = mods -- read in game at CHECKPOINT B (ns is not global)
+
+local function all()
+    return Hekili.Class.specs[ 0 ]
+end
+
+-- The keys (and `copy` aliases) the live race registered, by kind: what ns.applyRace writes over the class's.
+local owned = { abilities = {}, auras = {} }
+
+-- Records every key of `all`'s `kind` table that holds the entry just registered under `key` (its aliases too).
+local function own( kind, key )
+    local t = all()[ kind ]
+    local v = t[ key ]
+    for k, w in pairs( t ) do
+        if w == v then owned[ kind ][ k ] = true end
+    end
+end
+
+--- Classes.lua's SpecializationChanged, after merging the specs: the race's abilities and auras win over the class's.
+function ns.applyRace( class )
+    local spec = all()
+    for kind, keys in pairs( owned ) do
+        for k in pairs( keys ) do
+            class[ kind ][ k ] = spec[ kind ][ k ]
+        end
+    end
+end
+
+local Race = {}
+Race.__index = Race
+
+function Race:RegisterAbility( key, def )
+    if self.live then
+        all():RegisterAbility( key, def )
+        own( "abilities", key )
+    end
+end
+
+function Race:RegisterAura( key, def )
+    if self.live then
+        all():RegisterAura( key, def )
+        own( "auras", key )
+    end
+end
+
+--- { max = pct }: every resource the loaded class registered gets pct more maximum.
+function Race:RegisterResourceMod( def )
+    if self.live and type( def.max ) == "number" then
+        mods.maxMods[ #mods.maxMods + 1 ] = { pct = def.max }
+    end
+end
+
+--- { aura = key, pct = n | flat = n, charges = k | nil, spells = { spell IDs } | nil }: an ability whose spell ID (or
+--- one of its `copy` ranks) is listed (every ability paid from the resource when `spells` is nil) costs less while the
+--- aura is up; with charges, each such cast whose declared cost is above 0 takes a stack.
+function Race:RegisterCostMod( def )
+    if self.live then mods.costMods[ #mods.costMods + 1 ] = def end
+end
+
+function Hekili:NewRace( token )
+    return setmetatable( { token = token, live = Hekili.State.race_token == token }, Race )
+end
+
+----------------------------------------------------------------------------------------------------------------------
+-- The simulation's half of the cost modifiers: every ability's `spend` answers through the modifiers in scope whose
+-- buff is up in Hekili's `state`, and a paid ability in the simulation takes a stack of each charged one.
+
+local M = {}
+ns.costMods = M
+
+-- Whether ability `a` is in a modifier's scope: no `spells` (every ability), or its spell ID or a `copy` rank is
+-- listed. Cached per ability key the first time (an allocation once per key, never per read).
+local function inScope( m, a )
+    if not m.spells then return true end
+    local scope = m.scope
+    if not scope then
+        scope = {}
+        m.scope = scope
+    end
+    local key = rawget( a, "key" )
+    local hit = key and scope[ key ]
+    if hit ~= nil then return hit end
+    hit = false
+    local id, copy = rawget( a, "id" ), rawget( a, "copy" )
+    for _, spell in ipairs( m.spells ) do
+        if spell == id or spell == copy then hit = true end
+        if type( copy ) == "table" then
+            for _, c in ipairs( copy ) do
+                if c == spell then hit = true end
+            end
+        end
+    end
+    if key then scope[ key ] = hit end
+    return hit
+end
+
+--- A declared cost of ability `a` after the modifiers in scope whose buff is up in the simulated state; a fraction of
+--- the maximum (cost < 1) takes the same pct as the belief applies to it.
+function M.Apply( cost, a )
+    local list = mods.costMods
+    if #list == 0 or type( cost ) ~= "number" or cost <= 0 then return cost end
+    local buff = Hekili.State.buff
+    for i = 1, #list do
+        local m = list[ i ]
+        if buff[ m.aura ].up and inScope( m, a ) then
+            if type( m.pct ) == "number" then cost = cost * ( 1 + m.pct )
+            elseif type( m.flat ) == "number" then cost = cost + m.flat end
+        end
+    end
+    return cost > 0 and cost or 0
+end
+
+--- Ability `key` was cast in the simulation with declared cost `base` (ns.spendResources, before any discount): when
+--- `base` is above 0, a stack of each charged modifier in scope whose buff is up (gone at the last), even when the
+--- discount brought the paid cost to 0.
+function M.Spend( base, key )
+    local list = mods.costMods
+    if #list == 0 or type( base ) ~= "number" or base <= 0 then return end
+    local state = Hekili.State
+    local a = Hekili.Class.abilities[ key ]
+    if not a then return end
+    for i = 1, #list do
+        local m = list[ i ]
+        if m.charges and state.buff[ m.aura ].up and inScope( m, a ) then state.removeStack( m.aura ) end
+    end
+end
+
+--- Classes.lua's RegisterAbility: the ability's `spend` answers through the modifiers; `baseSpend` keeps the declared
+--- cost (VirtualState's belief applies the same modifiers to it itself).
+function M.Wrap( a )
+    local declared = rawget( a.funcs, "spend" )
+    if declared == nil then declared = rawget( a, "spend" ) end
+    if declared == nil then return end
+    rawset( a, "spend", nil )
+    local function base()
+        if type( declared ) == "function" then return declared() end
+        return declared
+    end
+    a.funcs.baseSpend = base
+    a.funcs.spend = function()
+        local c, r = base()
+        return M.Apply( c, a ), r
+    end
+end
diff --git a/State.lua b/State.lua
index a03d3802..19f1081c 100644
--- a/State.lua
+++ b/State.lua
@@ -511,6 +511,10 @@ end
 state.combat = 0
 state.faction = Facade.UnitFactionGroup( "player" )
 state.race[ formatKey( Facade.UnitRace("player") ) ] = true
+-- The race token (UnitRace's second return), the same on every client language: race packs match it (Races.lua), and
+-- race.gnome, race.troll ... hold beside the localized key.
+state.race_token = select( 2, Facade.UnitRace( "player" ) )
+if state.race_token then state.race[ formatKey( state.race_token ) ] = true end
 
 state.class = Hekili.Class
 state.targets = ns.targets
@@ -6629,6 +6633,9 @@ ns.spendResources = function( ability )
             cost = ( cost * state[ resource ].modmax )
         end
 
+        -- a charged cost modifier's buff loses a stack when the declared cost is above 0, even at a discounted 0 (Races.lua)
+        ns.costMods.Spend( action.baseSpend, ability )
+
         if cost ~= 0 then
             state.spend( cost, resource )
         end
diff --git a/VirtualState/Adapter.lua b/VirtualState/Adapter.lua
index a8ca263f..75a9a4c7 100644
--- a/VirtualState/Adapter.lua
+++ b/VirtualState/Adapter.lua
@@ -67,6 +67,16 @@ local def = {
 }
 
 local HANDS = { mainhand = 1, offhand = 2 }
+-- Point resources (a count, not a pool): a percentage maximum modifier does not apply to them.
+local POINTS = {
+    combo_points = true,
+    runes = true,
+    soul_shards = true,
+    holy_power = true,
+    chi = true,
+    arcane_charges = true,
+    essence = true,
+}
 
 -- The spell IDs of a registration: its `id`, then its `copy` IDs (rank order), positive numbers only.
 local function idsOf(obj)
@@ -139,6 +149,12 @@ local function buildDef()
         }
         insert(def.resources, d)
         slotByKey[k] = #def.resources
+        -- the race pack's resource and cost modifiers (Races.lua, event-facade spec §12b): every resource of the class,
+        -- but a maximum modifier never scales a point resource (combo points, runes, ...)
+        local race = ns.raceMods
+        if race then
+            d.maxMods, d.costMods = not POINTS[k] and race.maxMods or nil, race.costMods
+        end
     end
     for _, k in ipairs(sortedKeys(class.abilities)) do
         local a = class.abilities[k]
diff --git a/VirtualState/Families/Casts.lua b/VirtualState/Families/Casts.lua
index 97117b1f..60e81763 100644
--- a/VirtualState/Families/Casts.lua
+++ b/VirtualState/Families/Casts.lua
@@ -239,7 +239,20 @@ end
 --- (Hekili's ability table already evaluates a function `spend` on access; a raw one is called here). The plain
 --- out-of-combat read (`readCost`, Sources/Spellbook.lua) only confirms it, in Snapshot(): its units are the client's.
 function I.CostOf(a)
-    local c = I.ab.obj[a].spend
+    local c = I.BaseCostOf(a)
+    if I.CostMod then
+        c = I.CostMod(a, A.slot[a], c, I.clock) -- the resource's cost modifiers in scope (Families/Modifiers.lua)
+    end
+    return c
+end
+
+--- Ability a's declared cost, before any cost modifier (0 when it has none). Allocates nothing.
+function I.BaseCostOf(a)
+    local obj = I.ab.obj[a]
+    local c = obj.baseSpend -- the declared cost before the simulation's modifiers (Races.lua)
+    if c == nil then
+        c = obj.spend
+    end
     if type(c) == "function" then
         c = c()
     end
diff --git a/VirtualState/Families/Modifiers.lua b/VirtualState/Families/Modifiers.lua
new file mode 100644
index 00000000..85d816d8
--- /dev/null
+++ b/VirtualState/Families/Modifiers.lua
@@ -0,0 +1,105 @@
+-- VirtualState/Families/Modifiers.lua
+-- Declarative resource modifiers (event-facade spec §12b): two fields of a resource definition, filled by the race
+-- packs (Races.lua, through Adapter.lua) and open to talents and class auras alike.
+-- - `maxMods`: { { pct = n, when = fn|nil }, ... }; the maximum is the declared `max` (a number or a state-bound
+--   function, default 100) x the product of (1 + pct) over the modifiers whose `when` holds. Families/Resources.lua's
+--   one maximum evaluator applies it (at the build, seeding the interval, and at each CombatEnd) until a plain maximum
+--   read arrives, which wins from then on.
+-- - `costMods`: { { aura = "<key>", pct = n | flat = n, charges = k|nil, spells = { IDs }|nil }, ... }; an ability
+--   paying that resource whose spell ID (or a `copy` rank) is in `spells` (every ability when `spells` is nil) costs
+--   less while the aura is believed up on the player (I.CostOf). With `charges`, each cast whose declared cost is above
+--   0 (even one the discount brought to 0) spends one of the aura's believed stacks (a modelled sample at the cast),
+--   and the aura goes at 0; an observed aura read still wins.
+-- Allocates nothing per cast: the lists are the definitions' own tables, resolved to aura indices at the build.
+
+local _, ns = ...
+local VS, I = ns.VirtualState, ns.VirtualStateInternal
+
+local M = { costMods = {}, modAura = {}, modSpell = {}, modScope = {} }
+I.mods = M
+
+I.OnBuild(function(def)
+    local auraByKey = {} -- the build allocates
+    for j = 1, #def.auras do
+        if def.auras[j].key then
+            auraByKey[def.auras[j].key] = j
+        end
+    end
+    for r = 1, #def.resources do
+        local mods = def.resources[r].costMods
+        M.costMods[r] = mods
+        if mods then
+            local ja, js, sc = M.modAura[r] or {}, M.modSpell[r] or {}, M.modScope[r] or {}
+            M.modAura[r], M.modSpell[r], M.modScope[r] = ja, js, sc
+            for k = 1, #mods do
+                local j = auraByKey[mods[k].aura]
+                ja[k], js[k] = j or 0, j and def.auraIds[j][1] or 0
+                -- the scope as ability indices: a listed ID matches an ability's id or a `copy` rank (I.ab.bySpell);
+                -- an ID the class did not register is absent; no `spells`: every ability
+                local spells = mods[k].spells
+                if spells then
+                    local set = {}
+                    for _, id in ipairs(spells) do
+                        local a = I.ab.bySpell[id]
+                        if a then
+                            set[a] = true
+                        end
+                    end
+                    sc[k] = set
+                else
+                    sc[k] = false
+                end
+            end
+        end
+    end
+end)
+
+-- Whether modifier k of slot r covers ability a.
+local function inScope(r, k, a)
+    local set = M.modScope[r][k]
+    return not set or set[a] == true
+end
+
+--- Ability a's cost `c` on slot r after the cost modifiers in its scope whose aura is believed up on the player at
+--- `now`. Allocates nothing.
+function I.CostMod(a, r, c, now)
+    local mods = r and M.costMods[r]
+    if not mods or c <= 0 then
+        return c
+    end
+    local js = M.modSpell[r]
+    for k = 1, #mods do
+        if js[k] > 0 and inScope(r, k, a) and VS.Aura("player", js[k], now) then
+            local mod = mods[k]
+            if type(mod.pct) == "number" then
+                c = c * (1 + mod.pct)
+            elseif type(mod.flat) == "number" then
+                c = c + mod.flat
+            end
+        end
+    end
+    return c > 0 and c or 0
+end
+
+--- A paid cast of ability a at t on slot r spends one believed stack of each charged modifier in its scope whose aura
+--- is up; at 0 the aura goes. Called by the `now` family's cost step (Families/Now.lua). Allocates nothing.
+function I.SpendCostCharges(a, r, t, event)
+    local mods = r and M.costMods[r]
+    if not mods then
+        return
+    end
+    local ja, js = M.modAura[r], M.modSpell[r]
+    for k = 1, #mods do
+        if mods[k].charges and ja[k] > 0 and inScope(r, k, a) then
+            local rec, stacks, applied = VS.Aura("player", js[k], t)
+            if rec then
+                local left = (stacks or 1) - 1
+                if left > 0 then
+                    I.AuraModel(1, ja[k], applied or t, rec.est, left, t, event, false)
+                else
+                    I.AuraModel(1, ja[k], 0, 0, 0, t, event, false)
+                end
+            end
+        end
+    end
+end
diff --git a/VirtualState/Families/Now.lua b/VirtualState/Families/Now.lua
index 7a3027f2..28b462be 100644
--- a/VirtualState/Families/Now.lua
+++ b/VirtualState/Families/Now.lua
@@ -252,6 +252,10 @@ local function automatic(a, t, kind)
         if c > 0 then
             I.ResourceShift(r, -c, t, kind)
         end
+        -- a charged cost modifier in scope loses a stack, even when its discount made the cast free (Modifiers.lua)
+        if I.BaseCostOf(a) > 0 then
+            I.SpendCostCharges(a, r, t, kind)
+        end
     end
     if A.ch[a] then
         local recharge = type(obj.recharge) == "number" and obj.recharge or 0
diff --git a/VirtualState/Families/Resources.lua b/VirtualState/Families/Resources.lua
index 23aa5ff5..fd36385a 100644
--- a/VirtualState/Families/Resources.lua
+++ b/VirtualState/Families/Resources.lua
@@ -53,6 +53,7 @@ local R = {
     decayDef = {},
     decay = {},
     maxDef = {},
+    maxMods = {},
     maxRead = {},
 }
 I.res = R
@@ -78,14 +79,29 @@ local function decayOf(r)
     return type(d) == "number" and d > 0 and d or 0
 end
 
--- Slot r's declared maximum from its `max` (a number or a state-bound function; default 100), used until a plain
--- read arrives. Allocates nothing.
-local function maxOf(r)
-    local m = R.maxDef[r]
-    if type(m) == "function" then
-        m = m()
+local function eval(v)
+    if type(v) == "function" then
+        v = v()
     end
-    return type(m) == "number" and m > 0 and m or 100
+    return v
+end
+
+-- Slot r's declared maximum from its `max` (a number or a state-bound function; default 100) x the product of
+-- (1 + pct) over its `maxMods` whose `when` holds (Families/Modifiers.lua), used until a plain read arrives.
+-- Allocates nothing.
+local function maxOf(r)
+    local m = eval(R.maxDef[r])
+    m = type(m) == "number" and m > 0 and m or 100
+    local mods = R.maxMods[r]
+    if mods then
+        for k = 1, #mods do
+            local mod = mods[k]
+            if mod.when == nil or eval(mod.when) == true then
+                m = m * (1 + (type(mod.pct) == "number" and mod.pct or 0))
+            end
+        end
+    end
+    return m
 end
 
 -- By ability index a: the last usability answer and the last short report (cost, time).
@@ -113,7 +129,7 @@ I.OnBuild(function(def, now)
         local d = list[r]
         R.type[r], R.token[r] = d.type, d.token
         R.slotOf[d.type], R.slotOfToken[d.token] = r, r
-        R.maxDef[r], R.maxRead[r] = d.max, false
+        R.maxDef[r], R.maxMods[r], R.maxRead[r] = d.max, d.maxMods, false
         R.max[r] = maxOf(r)
         R.rest[r] = d.rest or 0
         R.swing[r] = d.swing or 0
diff --git a/tools/make_pack.lua b/tools/make_pack.lua
index 79dc7647..f7c119b5 100644
--- a/tools/make_pack.lua
+++ b/tools/make_pack.lua
@@ -3,8 +3,8 @@
 -- vendored libraries. Run from the repository root:
 --   lua5.1 tools/make_pack.lua
 -- Edit a pack's SimC-style text below, run it, and paste each printed string into its spec:RegisterPack( ... [[ ]] )
--- in Forever/Warrior.lua (Forever/spec/warrior_spec.lua fails until they match). Loaded with the argument "lists"
--- (loadfile(...)("lists")) it returns PACKS with each pack's parsed lists instead, for that spec.
+-- in Forever/Classes/Warrior.lua (Forever/spec/warrior_spec.lua fails until they match). Loaded with the argument
+-- "lists" (loadfile(...)("lists")) it returns PACKS with each pack's parsed lists instead, for that spec.
 -- The Arms and Fury lists are ported from Hekili's Classic profile (origin/classic:Classic/APLs/WarriorArms.simc,
 -- WarriorFury.simc); the Protection list's shape is archive/TheWarWithin/Priorities/WarriorProtection.simc's.
 
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `199 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [199 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 79 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 51 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

- [ ] **Step 6: Commit**

```bash
git add Races.lua Forever/Races/Gnome.lua Forever/Classes/Warrior.lua Forever/Warrior.lua Forever/spec/helpers/load_warrior.lua tools/make_pack.lua VirtualState/Families/Modifiers.lua VirtualState/Families/Casts.lua VirtualState/Families/Now.lua VirtualState/Families/Resources.lua VirtualState/Adapter.lua Classes.lua State.lua Hekili.toc .luacheckrc VirtualState/spec/modifiers_spec.lua VirtualState/spec/races_spec.lua
git commit -m "feat(virtualstate): race packs: Hekili:NewRace and the Gnome's (Eureka!, Expansive Mind); maxMods and spell-scoped costMods with charges, one declaration read by the belief and the simulation; race keyed by its token; the class file in Forever/Classes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 12: The follow-up (decision 7): the GCD spell, the empty spec slot and the talent read move into the facade

Spec §7, decision 7. Three Forever edits in Hekili core become facade answers, so the core lines return to Hekili's own:
- **GCD spell.** Retail's 61304 is back at its five sites (`Classes.lua:2469` the `global_cooldown` ability, `UI.lua:1494, 1695`, `Events.lua:1670`, `Options/Options.lua:4043`); `C_Spell.GetSpellCooldown` (before its raw call), `C_Spell.GetSpellInfo` and `C_Spell.GetSpellTexture` ask for 61304 as Forever's 29515 (`I.GCD_SPELL`). The latter two become hybrid rows.
- **Spec slot.** `C_SpecializationInfo.GetSpecializationInfo` (now hybrid) answers Forever's id 0 for an empty slot as nil, retail's shape, so `Hekili:SpecializationChanged`'s loop is back to `if not id then break end` (`Classes.lua:3135-3136`).
- **Talents.** `GetTalentInfoByID(entry, 1)` (virtual) answers a `RegisterTalents` entry `{ node, spell, max }` (or a spell ID) from VirtualState's `C_Traits` walk in retail's shape: always named, selected and known with any rank, and the rank as a 12th return. `ns.updateTalents` is back to its `GetTalentInfoByID( v, 1 )` body (`fc61b6d9:Events.lua:424-449`) with one Forever line kept: it stores that 12th return as `state.talent[ k ].rank` (retail and Classic Hekili have no ranks there; the Warrior's multi-rank talents need them).

After it: 121 passthrough, 28 hybrid, 27 virtual.

**Files:**
- Modify: `VirtualState/Facade.lua` (`GetTalentInfoByID`; `C_Spell.GetSpellCooldown`'s alias; a "Forever's answers in retail's shape" section; three names out of the passthrough list), `Classes.lua` (:2469, :3135-3136), `Events.lua` (`ns.updateTalents` :424-435, :1670), `UI.lua` (:1494, :1695), `Options/Options.lua` (:4043), `tools/api_inventory.txt` (three classes)
- Test: `VirtualState/spec/facade_spec.lua` (counts; "answers Forever's GCD spell, empty spec slots and talent ranks in retail's shape")

**Interfaces:**
- Consumes: `VS.Talent(spell)`, `I.GCD_SPELL` (Phase 1).
- Produces: `GetTalentInfoByID`'s 12th return (rank).

- [ ] **Step 1: Write the failing spec**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/VirtualState/spec/facade_spec.lua b/VirtualState/spec/facade_spec.lua
index 29d068fc..5213d4d3 100644
--- a/VirtualState/spec/facade_spec.lua
+++ b/VirtualState/spec/facade_spec.lua
@@ -116,7 +116,7 @@ describe("ns.Facade", function()
             assert.is_function(entry(n), n)
             assert.is_string(Facade.Why(n), n)
         end
-        assert.are.same({ passthrough = 124, hybrid = 25, virtual = 27 }, count)
+        assert.are.same({ passthrough = 121, hybrid = 28, virtual = 27 }, count)
         assert.is_nil(Facade.Status("NotAGameFunction"))
     end)
 
@@ -308,6 +308,37 @@ describe("ns.Facade", function()
         assert.are.equal(0, select("#", ns2.Facade.HasOverrideActionBar()))
     end)
 
+    it("answers Forever's GCD spell, empty spec slots and talent ranks in retail's shape (decision 7)", function()
+        local g = Facade.C_Spell.GetSpellCooldown(61304)
+        local f = Facade.C_Spell.GetSpellCooldown(29515)
+        assert.are.same({ f.startTime, f.duration }, { g.startTime, g.duration })
+        assert.are.equal("Spell 29515", Facade.C_Spell.GetSpellInfo(61304).name)
+        local asked
+        answers["C_Spell.GetSpellTexture"] = function(id)
+            asked = id
+            return 1
+        end
+        Facade.C_Spell.GetSpellTexture(61304)
+        assert.are.equal(29515, asked)
+        answers["C_SpecializationInfo.GetSpecializationInfo"] = function(i)
+            if i == 1 then
+                return 1491, "Warrior", "", 1, "DAMAGER", 1
+            end
+            return 0, "", "", 0
+        end
+        assert.are.same({ 1491, "Warrior", "", 1, "DAMAGER", 1 }, { Facade.C_SpecializationInfo.GetSpecializationInfo(1) })
+        assert.is_nil(Facade.C_SpecializationInfo.GetSpecializationInfo(2))
+        local talent = { 0, 12286, 3 }
+        local rank = VS.Talent
+        VS.Talent = function(spell)
+            return spell == 12286 and 2 or 0
+        end
+        local _, name, _, selected, _, spell, _, _, _, known, _, r = Facade.GetTalentInfoByID(talent, 1)
+        local _, _, _, untaken = Facade.GetTalentInfoByID({ 0, 99999, 1 }, 1)
+        VS.Talent = rank
+        assert.are.same({ "", true, 12286, true, 2, false }, { name, selected, spell, known, r, untaken })
+    end)
+
     it("aliases IsUsableSpell to C_Spell.IsSpellUsable", function()
         ctl.usable[5] = { true, false }
         assert.is_true(Facade.IsUsableSpell(5))
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `198 successes / 2 failures / 0 errors` (`facade_spec.lua:119`: the counts; `facade_spec.lua:315`: `GetSpellInfo(61304)` asks the client for 61304).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Classes.lua b/Classes.lua
index ffb66d3a..3bc861eb 100644
--- a/Classes.lua
+++ b/Classes.lua
@@ -2469,7 +2469,7 @@ end
 
 all:RegisterAbilities( {
     global_cooldown = {
-        id = 29515, -- Forever's GCD spell (retail: 61304; cleanup Q6)
+        id = 61304,
         cast = 0,
         cooldown = 0,
         gcd = "spell",
@@ -3135,8 +3135,7 @@ function Hekili:SpecializationChanged()
     for i = 1, 4 do
         local id, name, _, _, role, primaryStat = GetSpecializationInfo( i )
 
-        -- Forever answers id 0 for spec slots 2 and 3 (cleanup Q7).
-        if not id or id == 0 then break end
+        if not id then break end
 
         if i == currentSpec then
             insert( specs, 1, id )
diff --git a/Events.lua b/Events.lua
index d6dbddc5..52f87078 100644
--- a/Events.lua
+++ b/Events.lua
@@ -426,16 +426,24 @@ function ns.updateTalents()
         state.talent[ k ].enabled = false
     end
 
-    -- Forever: GetTalentInfoByID is dead; ranks come from VirtualState's C_Traits walk (cleanup Q9), keyed by the
-    -- talent's registered spell ID (RegisterTalents entries are { node, spell, max rank }).
-    for k, v in pairs( class.talents ) do
-        local rank = type( v ) == "table" and ns.VirtualState.Talent( v[ 2 ] ) or 0
+    -- local specGroup = GetSpecialization()
 
+    for k, v in pairs( class.talents ) do
+        local _, name, _, enabled, _, sID, _, _, _, _, known, rank = GetTalentInfoByID( v, 1 )
+
+        if not name then
+            -- We probably used a spellID.
+            enabled = IsPlayerSpell( v )
+        end
+
+        enabled = enabled or known
+
+        -- Forever: the facade answers a 12th return, the rank (event-facade decision 7); retail has none.
         if rawget( state.talent, k ) then
-            state.talent[ k ].enabled = rank > 0
+            state.talent[ k ].enabled = enabled
             state.talent[ k ].rank = rank
         else
-            state.talent[ k ] = { enabled = rank > 0, rank = rank }
+            state.talent[ k ] = { enabled = enabled, rank = rank }
         end
     end
 
@@ -1667,7 +1675,7 @@ local function CLEU_HANDLER( event, timestamp, subtype, hideCaster, sourceGUID,
                 end
             end
 
-            state.gcd.lastStart = max( state.gcd.lastStart, ( GetSpellCooldown( 29515 ) ) )
+            state.gcd.lastStart = max( state.gcd.lastStart, ( GetSpellCooldown( 61304 ) ) )
             -- if subtype ~= "SPELL_DAMAGE" then Hekili:ForceUpdate( subtype, true ) end
         end
     end
diff --git a/Options/Options.lua b/Options/Options.lua
index fe2ef866..72eec609 100644
--- a/Options/Options.lua
+++ b/Options/Options.lua
@@ -4040,7 +4040,7 @@ self:ForceUpdate( "SPEC_PACKAGE_CHANGED" )
 
         for k, v in pairs( class.abilityList ) do
             local a = class.abilities[ k ]
-            if a and a.id and ( a.id > 0 or a.id < -100 ) and a.id ~= 29515 and not a.item then
+            if a and a.id and ( a.id > 0 or a.id < -100 ) and a.id ~= 61304 and not a.item then
                 abilities[ v ] = k
             end
         end
diff --git a/UI.lua b/UI.lua
index a379bb6a..c5b5b147 100644
--- a/UI.lua
+++ b/UI.lua
@@ -1491,7 +1491,7 @@ do
                         local start, duration = 0, 0
 
                         if a.gcd ~= "off" then
-                            start, duration = GetSpellCooldown( 29515 )
+                            start, duration = GetSpellCooldown( 61304 )
                             if start > 0 then earliest_time = start + duration - now end
                         end
 
@@ -1692,7 +1692,7 @@ do
         end
 
         function d:RefreshCooldowns( event )
-            local gStart = GetSpellCooldown( 29515 )
+            local gStart = GetSpellCooldown( 61304 )
             local cStart = ( select( 4, UnitCastingInfo( "player" ) ) or select( 4, UnitChannelInfo( "player" ) ) or 0 ) / 1000
 
             local now = GetTime()
diff --git a/VirtualState/Facade.lua b/VirtualState/Facade.lua
index f23db22e..a48593fa 100644
--- a/VirtualState/Facade.lua
+++ b/VirtualState/Facade.lua
@@ -550,6 +550,9 @@ local function cooldownPolicy(spellID)
     return CD
 end
 kept("C_Spell.GetSpellCooldown", "hybrid", function(spellID)
+    if spellID == 61304 then
+        spellID = I.GCD_SPELL -- retail's GCD spell asked as Forever's (decision 7)
+    end
     local info = realGetSpellCooldown and realGetSpellCooldown(spellID)
     if plainTimes(info, "startTime", "duration") then
         return info
@@ -632,7 +635,20 @@ end, "player plain [W PR9]; target secret [W PR8]; TargetCast()")
 -- Combat log, talents, spells and items: absent on Forever, or replaced
 
 kept("CombatLogGetCurrentEventInfo", "virtual", I.Log.Current, "absent; the row being delivered (event-facade §2.4)")
-kept("GetTalentInfoByID", "virtual", nothing, "dead on Forever [W PR5]; ranks come from VirtualState.Talent")
+-- A talent in retail's GetTalentInfoByID shape from the C_Traits walk (event-facade decision 7): `talent` is a
+-- RegisterTalents entry { node, spell, max rank } or a spell ID; always named (the caller's IsPlayerSpell fallback
+-- would get a table), selected and known with any rank, the rank as a 12th return (Forever's; not in retail's shape).
+kept("GetTalentInfoByID", "virtual", function(talent)
+    local spell = talent
+    if type(talent) == "table" then
+        spell = talent[2]
+    end
+    if type(spell) ~= "number" then
+        return nil
+    end
+    local rank = VS.Talent(spell)
+    return spell, "", 0, rank > 0, true, spell, nil, 0, 0, rank > 0, false, rank
+end, "dead on Forever [W PR5]; VirtualState.Talent (the C_Traits walk)")
 kept("IsUsableSpell", "passthrough", function(spellID)
     if realIsSpellUsable then
         return realIsSpellUsable(spellID)
@@ -659,6 +675,36 @@ kept("GetTime", "hybrid", function()
     return GetTime()
 end, "plain [W]; a back-dated combat-log row's observed time while it is delivered")
 
+----------------------------------------------------------------------------------------------------------------------
+-- Forever's answers in retail's shape (event-facade decision 7): the GCD spell, an empty specialization slot
+
+local realGetSpellTexture = resolve("C_Spell.GetSpellTexture")
+local realGetSpecializationInfo = resolve("C_SpecializationInfo.GetSpecializationInfo")
+
+kept("C_Spell.GetSpellInfo", "hybrid", function(spellID, ...)
+    if spellID == 61304 then
+        spellID = I.GCD_SPELL
+    end
+    return realGetSpellInfo(spellID, ...)
+end, "unprobed; retail's GCD spell 61304 asked as Forever's 29515")
+
+kept("C_Spell.GetSpellTexture", "hybrid", function(spellID, ...)
+    if spellID == 61304 then
+        spellID = I.GCD_SPELL
+    end
+    return realGetSpellTexture(spellID, ...)
+end, "unprobed; retail's GCD spell 61304 asked as Forever's 29515")
+
+local function noEmptySlot(id, ...)
+    if not issecretvalue(id) and id == 0 then
+        return nil -- Forever answers id 0 for an empty slot; retail answers nothing
+    end
+    return id, ...
+end
+kept("C_SpecializationInfo.GetSpecializationInfo", "hybrid", function(...)
+    return noEmptySlot(realGetSpecializationInfo(...))
+end, "plain [W PR15]; Forever's id 0 for an empty slot answered as nil (cleanup Q7)")
+
 ----------------------------------------------------------------------------------------------------------------------
 -- Frames: the event facade's entry point (event-facade spec §2.1)
 
@@ -692,12 +738,9 @@ local PASSTHROUGH = {
     { "C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier", "unprobed" },
     { "C_PvP.IsWarModeDesired", "unprobed" },
     { "C_SpecializationInfo.GetSpecialization", "plain [W PR15]" },
-    { "C_SpecializationInfo.GetSpecializationInfo", "plain [W PR15]" },
     { "C_SpecializationInfo.GetTalentInfo", "unprobed" },
     { "C_Spell.GetSpellDescription", "unprobed" },
-    { "C_Spell.GetSpellInfo", "unprobed" },
     { "C_Spell.GetSpellPowerCost", "plain [W §4]" },
-    { "C_Spell.GetSpellTexture", "unprobed" },
     { "C_Spell.IsCurrentSpell", "plain [W PR1]" },
     { "C_Spell.IsSpellDataCached", "unprobed" },
     { "C_Spell.IsSpellHarmful", "unprobed" },
diff --git a/tools/api_inventory.txt b/tools/api_inventory.txt
index b049f967..635e0d98 100644
--- a/tools/api_inventory.txt
+++ b/tools/api_inventory.txt
@@ -23,16 +23,16 @@ C_PetBattles.IsInBattle	passthrough
 C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier	passthrough
 C_PvP.IsWarModeDesired	passthrough
 C_SpecializationInfo.GetSpecialization	passthrough
-C_SpecializationInfo.GetSpecializationInfo	passthrough
+C_SpecializationInfo.GetSpecializationInfo	hybrid
 C_SpecializationInfo.GetTalentInfo	passthrough
 C_Spell.GetSpellCastCount	virtual
 C_Spell.GetSpellCharges	hybrid
 C_Spell.GetSpellCooldown	hybrid
 C_Spell.GetSpellDescription	passthrough
-C_Spell.GetSpellInfo	passthrough
+C_Spell.GetSpellInfo	hybrid
 C_Spell.GetSpellLossOfControlCooldown	virtual
 C_Spell.GetSpellPowerCost	passthrough
-C_Spell.GetSpellTexture	passthrough
+C_Spell.GetSpellTexture	hybrid
 C_Spell.IsCurrentSpell	passthrough
 C_Spell.IsSpellDataCached	passthrough
 C_Spell.IsSpellHarmful	passthrough
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `200 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [200 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 79 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 51 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

Also: `grep -n '29515' Classes.lua UI.lua Events.lua Options/Options.lua` prints nothing.

- [ ] **Step 6: Commit**

```bash
git add VirtualState/Facade.lua Classes.lua Events.lua UI.lua Options/Options.lua tools/api_inventory.txt VirtualState/spec/facade_spec.lua
git commit -m "refactor(virtualstate): the GCD spell, the empty spec slot and the talent read answered by the facade in retail's shape; Hekili's own lines restored (decision 7)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 13: The Warrior's Overpower and Revenge back to Classic's event-driven windows, and its `now` lines

Replayed on `forever` at `75d71c8b`, which already holds the Warrior branch (its accuracy pass, the speed-based `rageOf`, the `decay` and `max` fields, Bloodrage's `startsCombat = false`): no merge, plain patches. Task 2 already pointed the file's top locals at `ns.Facade` and gave the loader's `ns` the fakes as its facade; Task 11 moved the file to `Forever/Classes/Warrior.lua` and its loader's path.

Spec §6. The Warrior file models Overpower's and Revenge's windows as Classic did (`origin/classic:Classic/Warrior.lua:400-456, 625-640, 1198-1199`), from the rows the layer now delivers: a `spec:RegisterEvent( "COMBAT_LOG_EVENT_UNFILTERED", ... )` handler records our dodged swing or ability (`enemy_dodged`, its target), a dodge, parry or block on us (`enemy_revenge_trigger`) and our Overpower's success (`last_overpower`), each at `GetTime()`, which is the row's observed time while it is delivered; `reset_precast`, when `now == query_time`, applies `overpower_ready` for the rest of the 5 s after a dodge under 6 s old on the current target and not yet spent (Classic's rules as written), else for 5 s when the client calls Overpower usable (the strict read, `usableNow`), and `revenge_usable` for the rest of 5 s after a trigger, else 5 s, both only while `reactive( REVENGE )`. Overpower's `usable` is `buff.overpower_ready.up` again; the interim plain-read gate (accuracy ruling A8) goes, and so do the comments saying Forever has no combat log. The file reads `CombatLogGetCurrentEventInfo` and `GetTime` through `ns.Facade`.

The `now` lines (spec §12a, Task 10): Charge, Bloodrage, Berserker Rage, Rend, Sunder Armor, Thunder Clap, Hamstring, Demoralizing Shout, Piercing Howl and the three stances each declare `now` beside `handler`, sharing its constants (`CHARGE_RAGE`, `REND_DURATION`, `THUNDER_CLAP_DURATION`; Rend and Thunder Clap pass their rank's duration, since their auras' durations are functions); the stances remove the other two, spend the rage above what a swap keeps and apply theirs. The file's `knownRank` reads `VS.KnownRank` (VirtualState's spellbook), so it answers the same in the sim's `state` environment and in a `now`; Tactical Mastery, a passive, is tracked (`VS.Track{ abilities = { TACTICAL_MASTERY } }`) so the spellbook knows it, and the rage a swap keeps (`stanceKeep( improvedRank )`) is shared by `swap_stance` and the stances' `now`. A `now` reaches only the context's names: a file-local helper it calls runs in the file's environment, so the stances pass their talent rank to `stanceKeep` rather than letting it read `talent`.

The Gnome stopgap goes: the rage meta table's `max = function () return state.race.gnome and 105 or 100 end` (c095ded4) is removed, so rage is 100 by default and a Gnome's 105 comes from the Gnome race pack's Expansive Mind (Task 11); its test becomes "declares no rage maximum of its own ...". The class file registers nothing for Eureka! (the race pack owns it).

The spec loader gains `GetTime`, `CombatLogGetCurrentEventInfo`, `w.events`, the applied durations and a fake `VirtualState.KnownRank` (from `game.known`).

**Files:**
- Modify: `Forever/Classes/Warrior.lua` (file-top locals; the rage meta table's `max` removed; `knownRank` from `VS.KnownRank`, Tactical Mastery tracked, `stanceKeep`; `now` on twelve abilities; `reactive`/`usableNow` comments; the `overpower_ready` and `revenge_usable` aura comments; the combat-log handler before `reset_precast`; `reset_precast`'s Revenge line; Overpower's `usable`), `Forever/spec/helpers/load_warrior.lua`, `Forever/spec/warrior_spec.lua` (the Overpower usability case becomes describe "the reactive windows from the combat log")
- Not touched: `.luacheckrc`. Tasks 2, 10 and 11 left it with no `CreateFrame` and no plain game read in `read_globals`, and with the Warrior's globals as `forever` declares them: `local warriorEnv = { "rage", "cooldown", "combat", "active_enemies", "active_dot", "setDistance", "interrupt", "swap_stance", "should_queue", "mainhand_remains", "nextMH", "mainhand_speed", "offensive_cost" }` plus every `stateEnv` name, `files["Forever/Classes/Warrior.lua"] = { globals = warriorEnv }` and `files["Forever/Races/"] = { globals = stateEnv }`. The new code reads the game only through `ns.Facade` locals, so it needs no new global; never take another branch's whole `.luacheckrc`.

**Interfaces:**
- Consumes: the own-cast, swing, ability-outcome and on-us rows (Tasks 6-8); `Facade.GetTime`'s back-dating (Task 6). `VS.KnownRank`, `VS.Track`, the `now` context (Task 10).
- Produces: `w.events[event]` in the Warrior spec loader; `e.durations` in its `env`. The Warrior abilities' `now` fields.

- [ ] **Step 1: Write the failing specs**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/spec/helpers/load_warrior.lua b/Forever/spec/helpers/load_warrior.lua
index e13a3a43..b2772703 100644
--- a/Forever/spec/helpers/load_warrior.lua
+++ b/Forever/spec/helpers/load_warrior.lua
@@ -7,9 +7,9 @@
 local M = {}
 
 --- Loads the class file. Returns `w`: `w.abilities`, `w.auras` (merged by key), `w.talents`, `w.track`, `w.resource`
---- ({ powerType, models }), `w.hooks[name]`, `w.funcs[name]`, `w.exprs[name]`, `w.settings[key]` ({ default,
---- option }), `w.packs` (in order: { name, version, string }), `w.options`, `w.specID`, `w.state` (Hekili.State's
---- stand-in) and `w.game`.
+--- ({ powerType, models }), `w.hooks[name]`, `w.events[event]` (spec:RegisterEvent's handlers), `w.funcs[name]`,
+--- `w.exprs[name]`, `w.settings[key]` ({ default, option }), `w.packs` (in order: { name, version, string }),
+--- `w.options`, `w.specID`, `w.state` (Hekili.State's stand-in) and `w.game`.
 function M.load()
     local reg = {}
     local spec = setmetatable({}, {
@@ -28,6 +28,8 @@ function M.load()
         form = 0,
         formSpell = {},
         base = { 0, 0 }, -- VS.SwingBase: each hand's unhasted speed (0: no plain read yet)
+        now = 0, -- GetTime()
+        row = {}, -- the combat-log row CombatLogGetCurrentEventInfo answers
     }
     local w = { game = game, abilities = {}, auras = {}, track = {}, hooks = {}, funcs = {}, exprs = {} }
     w.state = { main_hand = { size = 2 }, timeToInterrupt = function() end }
@@ -60,6 +62,12 @@ function M.load()
         GetShapeshiftFormInfo = function(i)
             return 0, true, true, game.formSpell[i]
         end,
+        GetTime = function()
+            return game.now
+        end,
+        CombatLogGetCurrentEventInfo = function()
+            return unpack(game.row, 1, 15)
+        end,
         Enum = { PowerType = { Rage = 1 } },
     }
     local saved = {}
@@ -70,6 +78,14 @@ function M.load()
     local ns = {
         Facade = fakes, -- the class file reads the game through ns.Facade (event-facade spec §1.2)
         VirtualState = {
+            KnownRank = function(ids) -- VirtualState's spellbook: the plain known reads (`game.known`)
+                for i = #ids, 1, -1 do
+                    if game.known[ids[i]] then
+                        return i
+                    end
+                end
+                return 0
+            end,
             Track = function(t)
                 for k, v in pairs(t.talents or {}) do
                     w.track[k] = v
@@ -97,6 +113,10 @@ function M.load()
     end
     w.talents = reg.RegisterTalents and reg.RegisterTalents[1][1]
     w.resource = reg.RegisterResource and reg.RegisterResource[1]
+    w.events = {}
+    for _, call in ipairs(reg.RegisterEvent or {}) do
+        w.events[call[1]] = call[2]
+    end
     for _, call in ipairs(reg.RegisterHook or {}) do
         w.hooks[call[1]] = call[2]
     end
@@ -126,7 +146,7 @@ end
 --- A stand-in `state` that records applyBuff/applyDebuff (into `applied`), removeBuff, spend and gain, with every
 --- talent at rank 0, every aura down and every cooldown ready. The class file's state functions are bound to it.
 function M.env(w)
-    local e = { applied = {}, removed = {}, spent = {}, gained = {} }
+    local e = { applied = {}, durations = {}, removed = {}, spent = {}, gained = {} }
     e.talent = default({ rank = 0, enabled = false })
     e.buff = default({ up = false, remains = 0, stack = 0 })
     e.debuff = e.buff
@@ -135,8 +155,9 @@ function M.env(w)
     e.rage = { current = 50 }
     e.target = { minR = 10, is_boss = false }
     e.combat, e.active_enemies = 0, 1
-    function e.applyBuff(key)
+    function e.applyBuff(key, duration)
         table.insert(e.applied, key)
+        e.durations[key] = duration
     end
     function e.applyDebuff(_, key)
         table.insert(e.applied, key)
diff --git a/Forever/spec/warrior_spec.lua b/Forever/spec/warrior_spec.lua
index 171e4316..477b80d4 100644
--- a/Forever/spec/warrior_spec.lua
+++ b/Forever/spec/warrior_spec.lua
@@ -181,14 +181,91 @@ describe("Forever Warrior", function()
         assert.are.equal("defensive_stance", lw.run(w.abilities.charge.buff, e))
     end)
 
-    it("recommends Overpower only while the client calls it usable, not when it is short of its combo point", function()
+    it("declares the now-state of Charge, Bloodrage, Berserker Rage, the debuffs and the stances (spec §12a)", function()
+        for _, k in ipairs({ "charge", "bloodrage", "berserker_rage", "rend", "sunder_armor", "thunder_clap", "hamstring",
+            "demoralizing_shout", "piercing_howl", "battle_stance", "defensive_stance", "berserker_stance" }) do
+            assert.is_function(w.abilities[k].now, k)
+        end
         local e = lw.env(w)
-        w.game.known[7384] = true
-        assert.is_false(lw.run(w.abilities.overpower.usable, e))
-        w.game.noMana[7384] = true -- no dodge: the second power cost (a combo point) is missing
-        assert.is_false(lw.run(w.abilities.overpower.usable, e))
-        w.game.usable[7384] = true
-        assert.is_true(lw.run(w.abilities.overpower.usable, e))
+        w.game.known[100], w.game.known[6178] = true, true -- Charge rank 2
+        lw.run(w.abilities.charge.now, e)
+        assert.are.same({ 12 }, e.gained)
+        assert.are.same({ "charge_stun" }, e.applied)
+        e = lw.env(w)
+        e.rage.current = 60
+        w.game.known[1310185] = true -- Tactical Mastery: 10 kept
+        lw.run(w.abilities.battle_stance.now, e)
+        assert.are.same({ 50 }, e.spent)
+        assert.are.same({ "battle_stance" }, e.applied)
+        assert.are.same({ "defensive_stance", "berserker_stance" }, e.removed)
+    end)
+
+    describe("the reactive windows from the combat log (event-facade spec §6)", function()
+        local ME, MOB = "Player-1", "Creature-1"
+
+        local function row(t, sub, src, dst, a12, a15)
+            w.game.now = t
+            w.game.row = { t, sub, false, src, "", 0, 0, dst, "", 0, 0, a12, "", 1, a15 or 0 }
+            w.events.COMBAT_LOG_EVENT_UNFILTERED()
+        end
+
+        local function reset(t)
+            local e = lw.env(w)
+            e.now, e.query_time, e.target.unit = t, t, MOB
+            lw.run(w.hooks.reset_precast, e)
+            return e
+        end
+
+        before_each(function()
+            w.state.GUID = ME
+            w.game.known[7384], w.game.known[6572] = true, true
+        end)
+
+        it("opens Overpower's window on our dodged swing for the rest of its 5 s, on that target only", function()
+            row(10, "SWING_MISSED", ME, MOB, "DODGE")
+            local e = reset(12)
+            assert.are.equal(3, e.durations.overpower_ready)
+            assert.is_nil(reset(16.5).durations.overpower_ready) -- past Classic's 6 s age test
+            w = lw.load()
+            w.state.GUID = ME
+            w.game.known[7384] = true
+            row(20, "SPELL_MISSED", ME, "Creature-2", 7384, "DODGE") -- another unit dodged
+            assert.is_nil(reset(21).durations.overpower_ready)
+        end)
+
+        it("closes Overpower's window once Overpower is cast, and keeps the usability fallback", function()
+            row(10, "SWING_MISSED", ME, MOB, "DODGE")
+            row(10.5, "SPELL_CAST_SUCCESS", ME, MOB, 7384)
+            row(11, "SWING_MISSED", ME, MOB, "PARRY")
+            local e = reset(12)
+            for _, k in ipairs(e.applied) do
+                assert.are_not.equal("overpower_ready", k) -- the dodge's window was spent
+            end
+            w.game.usable[7384] = true -- the client says usable: a dodge the log did not attribute
+            e = reset(13)
+            assert.are.same({ "overpower_ready" }, { e.applied[#e.applied] })
+            assert.is_nil(e.durations.overpower_ready)
+        end)
+
+        it("gates Overpower on its window, not on the usability read", function()
+            local e = lw.env(w)
+            w.game.usable[7384] = true
+            assert.is_false(lw.run(w.abilities.overpower.usable, e))
+            e.buff = { overpower_ready = { up = true } }
+            assert.is_true(lw.run(w.abilities.overpower.usable, e))
+        end)
+
+        it("opens Revenge's window on a parry on us while Revenge is usable", function()
+            row(20, "SWING_MISSED", MOB, ME, "PARRY")
+            w.game.noMana[6572] = true -- usable but for rage
+            assert.are.equal(4, reset(21).durations.revenge_usable)
+            assert.is_nil(reset(26).durations.revenge_usable) -- older than 5 s: the full window from the read
+            w.game.noMana[6572] = nil
+            local e = reset(21)
+            for _, k in ipairs(e.applied) do
+                assert.are_not.equal("revenge_usable", k)
+            end
+        end)
     end)
 
     it("gates Thunder Clap, Execute and Spearing Strike on the stances Forever's tooltips name", function()
@@ -272,12 +349,8 @@ describe("Forever Warrior", function()
         assert.is_true(math.abs(0.875 - decay()) < 1e-9) -- 1.25 x (1 - 0.3 x 1) = 1.25 x 0.7 = 0.875
     end)
 
-    it("caps rage at 105 for a Gnome (Expansive Mind, +5% maximum resources) and 100 otherwise", function()
-        local max = w.resource[4].max
-        w.state.race = { gnome = true }
-        assert.are.equal(105, max())
-        w.state.race = {}
-        assert.are.equal(100, max())
+    it("declares no rage maximum of its own: a Gnome's 105 is the race pack's Expansive Mind", function()
+        assert.is_nil(w.resource[4].max) -- 100 by default; the Gnome's race pack adds Expansive Mind
     end)
 
     it("gains Bloodrage's rage over time through an aura-gated regen entry", function()
```

- [ ] **Step 2: Run the specs to verify they fail**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `198 successes / 3 failures / 3 errors` (`warrior_spec`: `w.events.COMBAT_LOG_EVENT_UNFILTERED` is nil; Overpower's `usable` still follows the client's read; no ability declares `now`; the rage meta table still declares its own 105).

- [ ] **Step 3: Write the implementation**

Apply with `git apply` (from the worktree root):

```diff
diff --git a/Forever/Classes/Warrior.lua b/Forever/Classes/Warrior.lua
index 190446de..f708b6fd 100644
--- a/Forever/Classes/Warrior.lua
+++ b/Forever/Classes/Warrior.lua
@@ -19,6 +19,7 @@ local addon, ns = ...
 local Facade = ns.Facade
 local C_SpellBook, C_Spell, UnitClassBase = Facade.C_SpellBook, Facade.C_Spell, Facade.UnitClassBase
 local GetShapeshiftForm, GetShapeshiftFormInfo = Facade.GetShapeshiftForm, Facade.GetShapeshiftFormInfo
+local CombatLogGetCurrentEventInfo, GetTime = Facade.CombatLogGetCurrentEventInfo, Facade.GetTime
 local Hekili = _G[ addon ]
 
 if UnitClassBase( "player" ) ~= "WARRIOR" then return end
@@ -67,12 +68,19 @@ local function rest( ids )
     return out
 end
 
--- The highest rank of `ids` the player knows (0: none). C_SpellBook, not the deprecation shims (cleanup Q12).
+-- The highest known rank of a rank list, from VirtualState's spellbook (the plain IsSpellKnown reads it keeps): the
+-- same answer in the sim's `state` environment and in a `now` handler's (event-facade spec §12a).
 local function knownRank( ids )
-    for i = #ids, 1, -1 do
-        if IsSpellKnown( ids[ i ] ) then return i end
-    end
-    return 0
+    return VS.KnownRank( ids )
+end
+
+-- Tactical Mastery is a passive, not an ability: tracked so VirtualState's spellbook knows it.
+local TACTICAL_MASTERY_IDS = { TACTICAL_MASTERY }
+VS.Track( { abilities = { TACTICAL_MASTERY } } )
+
+-- The rage a stance swap keeps (Tactical Mastery and its improvement): shared by swap_stance and the stances' `now`.
+local function stanceKeep( improvedRank )
+    return ( knownRank( TACTICAL_MASTERY_IDS ) > 0 and 10 or 0 ) + 15 * improvedRank
 end
 
 local function knows( ids )
@@ -81,7 +89,7 @@ end
 
 -- A reactive ability's window (Execute, Revenge, Victory Rush) from the plain usability read:
 -- usable, or unusable only for lack of rage. The client's answer now, not at the simulated time (as Classic's
--- reset_precast read it); Forever has no combat log to time the window.
+-- reset_precast read it).
 local function reactive( ids )
     local r = knownRank( ids )
     if r == 0 then return false end
@@ -90,7 +98,7 @@ local function reactive( ids )
 end
 
 -- Usable now by the plain read, not merely short of a cost: Overpower's second cost (a combo point a dodge grants)
--- reads as "short" without a dodge.
+-- reads as "short" without a dodge. reset_precast's fallback when no dodge row timed the window (event-facade §6).
 local function usableNow( ids )
     local r = knownRank( ids )
     return r > 0 and IsSpellUsable( ids[ r ] ) == true
@@ -184,8 +192,8 @@ spec:RegisterResource( Enum.PowerType.Rage, {
     -- Out-of-combat rage loss per second, VirtualState's `decay` (in the meta table: Hekili takes every regen entry for
     -- a model): the client's Rage tooltip, "1.25 Rage is lost every 1 sec" (measured 100 -> 0 in 82.2 s: 80 s plus
     -- reaction time); Anger Management's tooltip: 30% less.
-    -- Gnome's Warrior racial Expansive Mind (1259802): +5% maximum resources, so a 105 rage cap.
-    max = function () return state.race.gnome and 105 or 100 end,
+    -- No `max`: rage is 100, and a Gnome's 105 comes from Expansive Mind in the Gnome's race pack
+    -- (Forever/Races/Gnome.lua, VirtualState's `maxMods`, event-facade spec §12b).
     decay = function () return 1.25 * ( 1 - 0.3 * state.talent.anger_management.rank ) end,
 } )
 
@@ -403,9 +411,8 @@ spec:RegisterAuras( {
         duration = 10,
         max_stack = 1,
     },
-    -- Forever's Overpower window: a 5 s player aura (DB2 1282733, "Overpower"). It is unseen on Forever (checkpoint Q6:
-    -- the aura walk raises in combat), so Overpower's gate is the client's usability read, and the swap to Battle
-    -- Stance after a dodge cannot be predicted (no combat log on Forever).
+    -- Forever's Overpower window: a 5 s player aura (DB2 1282733, "Overpower"), unseen in combat (checkpoint Q6: the
+    -- aura walk raises). Modelled as Classic did, from the dodge in the combat log (reset_precast).
     overpower_ready = {
         id = 1282733,
         duration = 5,
@@ -438,8 +445,7 @@ spec:RegisterAuras( {
         duration = 3,
         max_stack = 1,
     },
-    -- Revenge's window from its plain usability (reset_precast): 5 s from that read, not from the block, dodge or
-    -- parry (no combat log on Forever to time the proc).
+    -- Revenge's window from the block, dodge or parry on us in the combat log, while Revenge is usable (reset_precast).
     revenge_usable = {
         duration = 5,
         max_stack = 1,
@@ -499,8 +505,7 @@ spec:RegisterStateFunction( "swap_stance", function( stance )
     removeBuff( "defensive_stance" )
     removeBuff( "berserker_stance" )
 
-    local kept = ( IsSpellKnown( TACTICAL_MASTERY ) and 10 or 0 ) + 15 * talent.improved_tactical_mastery.rank
-    local lost = rage.current - kept
+    local lost = rage.current - stanceKeep( talent.improved_tactical_mastery.rank )
     if lost > 0 then spend( lost, "rage" ) end
 
     applyBuff( stance )
@@ -514,6 +519,28 @@ spec:RegisterStateFunction( "offensive_cost", function( cost )
     return max( 0, cost - 3 * talent.focused_rage.rank )
 end )
 
+-- The reactive windows from the combat log, as Classic models them (origin/classic:Classic/Warrior.lua:400-456): our
+-- dodged swing or ability opens Overpower's, a dodge, parry or block on us opens Revenge's. On Forever the rows come
+-- from VirtualState's event facade (docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md §6).
+local enemy_revenge_trigger, enemy_dodged, enemy_dodged_target = 0, 0, nil
+local last_overpower = 0
+local misses = { DODGE = true, PARRY = true, BLOCK = true }
+local overpower_ids = {}
+for _, id in ipairs( OVERPOWER ) do overpower_ids[ id ] = true end
+
+spec:RegisterEvent( "COMBAT_LOG_EVENT_UNFILTERED", function()
+    local _, subtype, _, sourceGUID, _, _, _, destGUID, _, _, _, actionType, _, _, spellMissType = CombatLogGetCurrentEventInfo()
+
+    if sourceGUID == state.GUID and subtype:match( "_MISSED$" ) and ( actionType == "DODGE" or spellMissType == "DODGE" ) then
+        enemy_dodged = GetTime()
+        enemy_dodged_target = destGUID
+    elseif destGUID == state.GUID and subtype:match( "_MISSED$" ) and misses[ actionType ] then
+        enemy_revenge_trigger = GetTime()
+    elseif sourceGUID == state.GUID and subtype == "SPELL_CAST_SUCCESS" and overpower_ids[ actionType ] then
+        last_overpower = GetTime()
+    end
+end )
+
 spec:RegisterHook( "reset_precast", function()
     -- The stance from the plain shapeshift reads (forever-facade-notes: GetShapeshiftForm, GetShapeshiftFormInfo).
     removeBuff( "battle_stance" )
@@ -530,7 +557,22 @@ spec:RegisterHook( "reset_precast", function()
     if hs > 0 and IsCurrentSpell( HEROIC_STRIKE[ hs ] ) then applyBuff( "heroic_strike" ) end
     if cl > 0 and IsCurrentSpell( CLEAVE[ cl ] ) then applyBuff( "cleave" ) end
 
-    if reactive( REVENGE ) then applyBuff( "revenge_usable" ) end
+    if now == query_time then
+        if knownRank( OVERPOWER ) > 0 then
+            if enemy_dodged > 0 and query_time - enemy_dodged < 6 and target.unit == enemy_dodged_target and ( last_overpower == 0 or enemy_dodged - last_overpower > 5 ) then
+                applyBuff( "overpower_ready", enemy_dodged + 5 - now )
+            elseif usableNow( OVERPOWER ) then
+                applyBuff( "overpower_ready" )
+            end
+        end
+        if reactive( REVENGE ) then
+            if enemy_revenge_trigger > 0 and now - enemy_revenge_trigger < 5 then
+                applyBuff( "revenge_usable", enemy_revenge_trigger + 5 - now )
+            else
+                applyBuff( "revenge_usable" )
+            end
+        end
+    end
 end )
 
 -- `timeToReady` of the three stances: they share a 1 s category cooldown.
@@ -568,6 +610,15 @@ spec:RegisterAbilities( {
         nobuff = "battle_stance",
         timeToReady = stanceReady,
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            removeBuff( "defensive_stance" )
+            removeBuff( "berserker_stance" )
+            local lost = rage.current - stanceKeep( talent.improved_tactical_mastery.rank )
+            if lost > 0 then spend( lost, "rage" ) end
+            applyBuff( "battle_stance" )
+        end,
+
         handler = function ()
             swap_stance( "battle_stance" )
         end,
@@ -583,6 +634,12 @@ spec:RegisterAbilities( {
         known = knows( { 18499 } ),
         buff = "berserker_stance",
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            applyBuff( "berserker_rage" )
+            if talent.improved_berserker_rage.enabled then gain( 10 * talent.improved_berserker_rage.rank, "rage" ) end
+        end,
+
         handler = function ()
             applyBuff( "berserker_rage" )
             -- DB2 20500: energize 100 (10 rage) a rank.
@@ -601,6 +658,15 @@ spec:RegisterAbilities( {
         nobuff = "berserker_stance",
         timeToReady = stanceReady,
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            removeBuff( "battle_stance" )
+            removeBuff( "defensive_stance" )
+            local lost = rage.current - stanceKeep( talent.improved_tactical_mastery.rank )
+            if lost > 0 then spend( lost, "rage" ) end
+            applyBuff( "berserker_stance" )
+        end,
+
         handler = function ()
             swap_stance( "berserker_stance" )
         end,
@@ -618,6 +684,12 @@ spec:RegisterAbilities( {
         known = knows( { 2687 } ),
         toggle = "cooldowns",
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            gain( 10 * ( 1 + 0.5 * talent.improved_bloodrage.rank ), "rage" )
+            applyBuff( "bloodrage" )
+        end,
+
         handler = function ()
             -- DB2 12301: +50% of the rage Bloodrage generates a rank.
             gain( 10 * ( 1 + 0.5 * talent.improved_bloodrage.rank ), "rage" )
@@ -677,6 +749,12 @@ spec:RegisterAbilities( {
             return combat == 0 and target.minR >= 8 and target.minR <= 25, "cannot be in combat; target must be outside your deadzone"
         end,
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            gain( ( CHARGE_RAGE[ knownRank( CHARGE ) ] or 9 ) + 3 * talent.improved_charge.rank, "rage" )
+            applyDebuff( "target", "charge_stun" )
+        end,
+
         handler = function ()
             setDistance( 7 )
             if not target.is_boss then applyDebuff( "target", "charge_stun" ) end
@@ -755,6 +833,15 @@ spec:RegisterAbilities( {
         nobuff = "defensive_stance",
         timeToReady = stanceReady,
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            removeBuff( "battle_stance" )
+            removeBuff( "berserker_stance" )
+            local lost = rage.current - stanceKeep( talent.improved_tactical_mastery.rank )
+            if lost > 0 then spend( lost, "rage" ) end
+            applyBuff( "defensive_stance" )
+        end,
+
         handler = function ()
             swap_stance( "defensive_stance" )
         end,
@@ -773,6 +860,11 @@ spec:RegisterAbilities( {
         startsCombat = true,
         known = knows( DEMORALIZING_SHOUT ),
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            applyDebuff( "target", "demoralizing_shout" )
+        end,
+
         handler = function ()
             applyDebuff( "target", "demoralizing_shout" )
             active_dot.demoralizing_shout = active_enemies
@@ -834,6 +926,11 @@ spec:RegisterAbilities( {
         known = knows( HAMSTRING ),
         nobuff = "defensive_stance",
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            applyDebuff( "target", "hamstring" )
+        end,
+
         handler = function ()
             applyDebuff( "target", "hamstring" )
         end,
@@ -975,8 +1072,7 @@ spec:RegisterAbilities( {
         known = knows( OVERPOWER ),
         buff = "battle_stance",
 
-        -- interim until the virtual event facade delivers the dodge event
-        usable = function () return usableNow( OVERPOWER ), "no dodge to overpower" end,
+        usable = function () return buff.overpower_ready.up, "only usable after dodging" end,
 
         handler = function ()
             removeBuff( "overpower_ready" )
@@ -996,6 +1092,11 @@ spec:RegisterAbilities( {
         startsCombat = true,
         known = knows( { 12323 } ),
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            applyDebuff( "target", "piercing_howl" )
+        end,
+
         handler = function ()
             applyDebuff( "target", "piercing_howl" )
         end,
@@ -1052,6 +1153,11 @@ spec:RegisterAbilities( {
         known = knows( REND ),
         nobuff = "berserker_stance",
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            applyDebuff( "target", "rend", REND_DURATION[ knownRank( REND ) ] or 9 )
+        end,
+
         handler = function ()
             applyDebuff( "target", "rend" )
         end,
@@ -1215,6 +1321,11 @@ spec:RegisterAbilities( {
         startsCombat = true,
         known = knows( SUNDER_ARMOR ),
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            applyDebuff( "target", "sunder_armor", nil, min( 5, debuff.sunder_armor.stack + 1 ) )
+        end,
+
         handler = function ()
             applyDebuff( "target", "sunder_armor", nil, min( 5, debuff.sunder_armor.stack + 1 ) )
         end,
@@ -1268,6 +1379,11 @@ spec:RegisterAbilities( {
         known = knows( THUNDER_CLAP ),
         nobuff = "berserker_stance",
 
+        -- what the cast did to the now-state, in VirtualState's context (spec §12a)
+        now = function ()
+            applyDebuff( "target", "thunder_clap", THUNDER_CLAP_DURATION[ knownRank( THUNDER_CLAP ) ] or 10 )
+        end,
+
         handler = function ()
             applyDebuff( "target", "thunder_clap" )
             active_dot.thunder_clap = min( active_enemies, 4 + active_dot.thunder_clap )
```

- [ ] **Step 4: Run the specs to verify they pass**

Run: `~/src/TacoDogForever/.lua/bin/busted`
Expected: `204 successes / 0 failures / 0 errors`.

- [ ] **Step 5: Verify**

```bash
BUSTED=~/src/TacoDogForever/.lua/bin/busted; LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck
LUALS=~/.local/share/mise/installs/lua-language-server/latest/bin/lua-language-server
$BUSTED                                                     # [204 successes / 0 failures / 0 errors]
$LUACHECK .                                                 # [0 warnings / 0 errors in 79 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh                 # [ok: no direct game API read in 51 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf <(cut -f1 tools/api_inventory.txt) | sort -u \
  | diff - <(cut -f1 tools/api_inventory.txt)               # [empty]
$LUALS --check . --checklevel=Error --logpath=/tmp/luals    # [Diagnosis completed, no problems found]
git ls-files -mo --exclude-standard '*.lua' | while read -r f; do [ -f "$f" ] && luac5.1 -p "$f"; done   # [no output]
```

Also: `grep -c '"CreateFrame"' .luacheckrc` prints `0` and `git diff HEAD --stat -- .luacheckrc` prints nothing (the task leaves `.luacheckrc` as Task 11 left it).

- [ ] **Step 6: Commit**

```bash
git add Forever/Classes/Warrior.lua Forever/spec/helpers/load_warrior.lua Forever/spec/warrior_spec.lua
git commit -m "feat(forever): Overpower and Revenge windows from the combat log as Classic models them (the dodge row, the usability read as fallback); now handlers on Charge, Bloodrage, Berserker Rage, the debuffs and the stances; knownRank from VirtualState's spellbook

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push** (orchestrator, after this task's review is clean): `git push origin virtualstate-event-facade`

---

### Task 14: CHECKPOINT B: the probes, then the rows in game

No code unless an answer calls for it. The user runs the game on the Warrior: items 1-3 against a mob that fights back (an open-world enemy), items 4-10 at a training dummy. ForeverProbe loaded (`VSCopy`). `Hekili.toc` lists new files since CHECKPOINT A: restart the client once.

- [ ] **Step 1: Point the client at the branch**

```bash
git push origin virtualstate-event-facade
git -C ~/src/hekili checkout --detach virtualstate-event-facade
```

- [ ] **Step 2: CHECKPOINT: stop and ask the user to run the following in game, and report each answer**

The probes come first (spec §9 step 8); their lines use a frame of their own (`VSPF`), not Hekili's.

1. **The pairing gap.** Out of combat, run these three lines once:
   `/run VSPP={s=0,c=0,ms=0,mc=0,n=0} VSPF=VSPF or CreateFrame("Frame") for _,e in ipairs{"PLAYER_SWING","UNIT_COMBAT","UNIT_SPELLCAST_SUCCEEDED"} do VSPF:RegisterEvent(e) end`
   `/run function VSPG(t) local P=VSPP local g,h=floor(t-P.s),floor(t-P.c) P.n=P.n+1 if g<1000 and g>P.ms then P.ms=g end if h<1000 and h>P.mc then P.mc=h end end`
   `/run VSPF:SetScript("OnEvent",function(_,e,u) local t=debugprofilestop() if e=="PLAYER_SWING" then VSPP.s=t elseif e=="UNIT_COMBAT" then if u=="target" then VSPG(t) end elseif u=="player" then VSPP.c=t end end)`
   Fight the mob for a minute with white swings and a few instant abilities (Rend, Overpower when it lights). Then `/run VSPF:UnregisterAllEvents() VSCopy(format("outcomes %d swing %d cast %d",VSPP.n,VSPP.ms,VSPP.mc))` and report the box: the largest gaps below 1000 ms between an outcome on the target and our last swing, and our last cast.
2. **A hostile's swing speed in combat** (the mob targeted and attacking): `/run local a=UnitAttackSpeed("target") VSCopy("speed "..tostring(issecretvalue(a) or a))`. Report the box (`true` = secret, a number = plain).
3. **Who targets me, in combat**: `/run local r=UnitIsUnit("targettarget","player") VSCopy("isunit "..(issecretvalue(r) and "secret" or tostring(r)))`. Report the box. Then, still fighting: `/run VSCopy(Hekili.VirtualState.Snapshot():match("rows [^\n]+").." "..Hekili.VirtualState.Snapshot():match("unattributed[^\n]+"))`. Expected: `onus=` above 0 and few unattributed hits with one mob on you.
4. **Overpower after a dodge** (Arms, Battle Stance, dummy): before any dodge, is Overpower recommended? Expected: no. After a floating "Dodge" on the dummy, within a second? Expected: yes; and gone once Overpower is cast, or 5 s after the dodge.
5. **The cast history**: cast Battle Shout, Rend, Heroic Strike, and wait until the Heroic Strike swing lands (its success arrives with the swing); then `/run local p=Hekili.State.player VSCopy(p.lastcast.." "..p.lastgcd)` and `/run local d=Hekili.EData.COMBAT_LOG_EVENT_UNFILTERED_1 VSCopy(d and format("rows %.3f ms max %.3f",d.total,d.max) or "none")`. Expected: `heroic_strike rend` (the last cast, the last GCD cast), and a `rows` line (each cast once in the history: Rend's recommendation does not repeat right after its cast).
6. **The swing clock**: auto-attack the dummy for 60 s; five times, between swings, `/run VSCopy(format("%.3f %.3f",Hekili.State.swings.mh_actual,Hekili.VirtualState.LastSwing(1)))`. Expected: the two numbers within 0.050 each time (the second is the `PLAYER_SWING` time VirtualState folded).
7. **The follow-up (Task 12)**: the GCD sweep on the buttons still shows after a cast; `/run VSCopy(format("%s %d",tostring(Hekili.State.spec.id),Hekili.State.talent.unbridled_wrath.rank))`. Expected: `1491` and the talent's rank from the pane (5 on the export's character).
8. **The dev tools hear modelled rows** (decision 9): `/hekili skeleton`, then 10 s of auto-attack and Rend at the dummy, then `/run VSCopy(Hekili.VirtualState.Snapshot():match("events [^\n]+"))`. Expected: `errors=0` (the skeleton listener took every row without an error).
9. **`now` handlers (Task 10)**: out of combat at 0 rage, Charge the dummy, then at once `/run VSCopy(format("%.0f %s",Hekili.VirtualState.Power(1,GetTime()).est,Hekili.VirtualState.Snapshot():match("errors=%d+ now=%d+")))`; then Rend it and `/run VSCopy(tostring(Hekili.State.debuff.rend.up))`; then swap to Defensive Stance at about 50 rage and run the first line again. Expected: the rage close to the bar after Charge (the `now` gain) and after the swap (what Tactical Mastery keeps), `errors=0`, `now=` growing, and `true` for Rend.
10. **Race packs (Task 11)**, on a Gnome only: out of combat `/run VSCopy(Hekili.VirtualState.Snapshot():match("resource RAGE[^\n]+"))`. Expected: `max=105`. Then use Eureka! and, with it up: `/run VSCopy(Hekili.VirtualState.Snapshot():match("ability heroic_strike[^\n]+"))` reads `cost=13.5` (15 without it) and the same line for `rend` reads `cost=10` (out of Eureka!'s scope); in the simulation `/run local a=Hekili.State.action VSCopy(format("%s %s",tostring(a.heroic_strike.cost),tostring(a.rend.cost)))` reads `13.5 10`; three Heroic Strikes later Eureka! is gone, a Rend in between took no charge. Another race: report "not a Gnome".
11. **A traced snapshot**: inside an Overpower window, `/hekili snapshot`, then `/hekili` → Snapshots → the newest. Expected: `rows ... missed=<n>` in the Snapshot block and `[vs] row SWING_MISSED missed inferred t=...` or `SPELL_MISSED` lines only if a row was delivered during the snapshot (rare); the `overpower_ready` buff up in the snapshot's aura list.

| # | Answer → action (each action its own commit with the verification block) |
|---|---|
| 1 | `outcomes 0` → the probe heard no outcome on the target: target the mob and repeat. Largest gap G ms (swing or cast, below 1000) → set `L.PAIR_WINDOW` in `VirtualState/Sources/Rows.lua` to `(G + 17)` ms rounded up to the next 10 ms, in seconds; if it is not 0.2, move `cleu_rows_spec`'s window-relative times with it (the `ctl.Tick(30.15)`/`(30.25)` pair straddles the window, `40.3`/`40.6` exceed it). Gaps near a whole swing → outcomes come first: no change (both orders pair). |
| 2 | Plain → the clocks use it (no change). Secret → periods are learned (no change); note it in the spec's E13 row. |
| 3 | First line `secret` → no row on us is ever emitted: Revenge falls back to its usability read (spec §6); note it in E13 and tell the user that Revenge's window is the client's read only. Second line `onus=0` with a plain `isunit` → the targeting set misses the mob: report `/run VSCopy(Hekili.VirtualState.Snapshot():match("read UnitIsUnit[^\n]+"))`. Many `unattributed` with one mob on you → its clock never sets: report the item 2 answer and the `rows` line. |
| 4 | Recommended before a dodge → report `/run VSCopy(tostring(C_Spell.IsSpellUsable(7384)))` (the fallback's read) and the Snapshot's `rows` line. Not recommended after a dodge → report the `rows` line (`missed=0`: no pairing; raise `PAIR_WINDOW` per item 1). |
| 5 | A cast twice in the history → a feed still writes it: report (Task 6 regression). `none` → no row reached `CLEU_HANDLER`: report `/run VSCopy(Hekili.VirtualState.Snapshot():match("rows [^\n]+"))`. |
| 6 | Off by more than 0.050 → report the five pairs; a constant lag of about `PAIR_WINDOW` means back-dating did not apply (Task 6 regression). |
| 7 | Spec id other than 1491 or a rank of 1 for a multi-rank talent → report (Task 12 regression). No GCD sweep after a cast → the facade's 61304 → 29515 answer is not reaching `UI.lua`: report it with the Snapshot's `cast ab=... gcd=...` line (Task 12 regression). |
| 8 | `errors=` above 0 → the skeleton handler raised on a row: report the line's `last error=`. |
| 9 | Rage far from the bar after Charge or the swap → report both numbers and the Snapshot's `resource RAGE` line; `errors=` above 0 → report the drain line's `error=` (a `now` raised: the named ability's `now` is wrong); Rend `false` → report the Snapshot's `aura target rend` line. |
| 10 | `max=100` on a Gnome, or the belief's cost unchanged after Eureka! → the race pack is not live: report `/run local m=Hekili.RaceMods VSCopy(format("%s max=%d cost=%d",tostring(Hekili.State.race_token),#m.maxMods,#m.costMods))` (expected `Gnome max=1 cost=1`), the Snapshot's `ability heroic_strike` line (`/run VSCopy(Hekili.VirtualState.Snapshot():match("ability heroic_strike[^\n]+"))`) and its `aura player eureka` line. |
| 10b | The simulation's line not `13.5 10` with Eureka! up, or Eureka! still up (in the belief's `aura player eureka` line or `/run VSCopy(tostring(Hekili.State.buff.eureka.stack))`) after three Heroic Strikes → `ns.costMods` misses the ability or its charge: report both lines, the token line above, and `/run local a=Hekili.Class.abilities.heroic_strike VSCopy(format("%s %s",tostring(a.baseSpend),tostring(a.spend)))`. |
| 11 | No `rows` line in the Snapshot block → Task 6 regression: report the snapshot's first lines. No `overpower_ready` inside a window → report item 4's lines. |

Known limits (say them with the results): attribution of hits on us is a model (decision 6): with several attackers whose clocks align, or spell hits, a hit can stay unattributed (no row) or, rarely, go to the wrong one; our swings' outcomes pair by time only, so in a group another attacker's dodge inside the window can open Overpower's window (the usability read corrects it at the next reset in Battle Stance); aura rows come from the `now` verbs, written at the drain after the cast and back-dated to it; Overpower's stance swap is not modelled.

Fix what the user reports, then repeat the affected items. Continue only when the user confirms. Then `git push origin virtualstate-event-facade`. When the session ends: `git -C ~/src/hekili checkout forever`.

---

## Self-Review

**1. Coverage of the spec (as amended) and the brief**

| Requirement | Where |
|---|---|
| Decision 1: diversion at `Facade.CreateFrame`; every Hekili frame's registrations through the layer; the boot frame a subscriber too | Task 1 (the layer, shadowed methods), Task 2 (`CreateFrame` from the facade in every file, `Adapter.lua`'s boot frame) |
| Decision 2: every event in the game's shape, Hekili cannot tell; `UNIT_AURA` full update in phase A | Task 1 (`Plain` slots, `UNIT_AURA`'s payload, CLEU with no payload in Task 6), Task 3 (the original handler) |
| Per-subscriber unit filters; the layer's frame at file load, sources after Start; refused events as stubs; zero allocation | Task 1 (`event_facade_spec`, its 0-byte case) |
| Decision 8: three classes over all 175 names (plus `CreateFrame`), probe evidence as the reason, `api_inventory.txt` with classes, `check_api_reads.sh` enforcing facade-only reads, file-top locals back in every Hekili file | Task 2; the classes move in Tasks 6 (`GetTime`) and 12 (three Forever shapes) |
| Decision 3: the trace through `Hekili:Debug` and Hekili's snapshots, no ring or command; the answering class per read | Task 4 (`trace_spec`) |
| Decision 4: every row wrapped, one branch | Task 4 (`kept`'s wrapper; the 0-byte case off) |
| Phase A checkpoint: reload clean, every event still arrives, a traced snapshot, drain and cycle cost | Task 5 |
| Phase B rows: own casts; SWING_DAMAGE/SWING_MISSED incl. DODGE; SPELL_CAST_SUCCESS; SPELL_AURA_APPLIED/REFRESH/REMOVED for our casts; SPELL_ENERGIZE; the slot table per subevent | Tasks 6, 7, 9 (`cleu_rows_spec`, `adapter_spec`) |
| Decision 5: observed-time back-dating via slot 1 and `Facade.GetTime` during delivery; modelled rows stamped at delivery; the basis per family | Task 6 (the mechanism and its case), Tasks 7-9 (each family's flag), spec §3's table |
| The swing-pairing window as a constant measured by phase B's first probe | Task 7 (`L.PAIR_WINDOW`), Task 14 item 1 |
| Decision 6: the "who targets me" set and per-attacker clocks (plain `UnitAttackSpeed` or learned), tolerance, unattributed otherwise; our swings' dodges by the pairing window; the two probes | Task 8, Task 14 items 2-3 |
| The Phase 1 feeds retired in the task that adds their rows | Task 6 (cast feeds), Task 7 (swing feed) |
| The `COMBAT_LOG_EVENT_UNFILTERED` skip restored in Hekili | Task 6 (`Events.lua:174, 197`) |
| The Warrior's Overpower/Revenge back to Classic's event-driven windows; the interim usability gate removed | Task 13 |
| Phase B checkpoint: probes first, Overpower only after a dodge, swing times within 50 ms, a trace | Task 14 |
| Decision 7: the GCD sites, the spec-1491 loop break and the talent read moved into the facade, a named task | Task 12 |
| Decision 9: the dev-tools listener hears modelled rows | by construction (it subscribes like `CLEU_HANDLER`, Task 2 makes its frame a facade frame); CHECKPOINT B item 8 |
| Race packs and resource modifiers (spec §12b): `Forever/Classes/` and `Forever/Races/`; `state.race_token`; `Hekili:NewRace` inert for another race, registering into `all` for the player's and written over the class's after Hekili's merge (`ns.applyRace`: the race wins a clash with the class and with `all`); `maxMods` (105 for a Gnome through the one maximum evaluator, the interval seeded at it, a plain read wins, point resources untouched); `costMods` scoped by `spells` resolved through id and `copy` ranks, every ability of the resource without `spells`, in both layers (Heroic Strike 13.5 and a charge, Rend 10 and none, Rend by its rank-2 ID; an unknown ID ignored; a fraction-of-maximum cost takes the pct), charges gated on the declared cost above 0 in both layers (`pct = -1, charges = 1` spends its charge), from one declaration (named core edits); allocation; the Warrior's 105 constant gone | Task 11 (`modifiers_spec`, `races_spec`), Task 13, CHECKPOINT B item 10 |
| `now` handlers (spec §12a): `now` read raw from `funcs` and setfenv'd to one context; Hekili's verbs onto the belief; reads by prebuilt proxies; cost, cooldown and GCD automatic; `pcall` and an error count; the drain without reset-apply-reset; zero allocation; the brief's six tests; Warrior `now` lines and `knownRank` in both environments | Task 10 (`now_spec`), Task 13 (`warrior_spec` "declares the now-state ..."), CHECKPOINT B item 9 |
| Branch `virtualstate-event-facade` from `forever` at 75d71c8b; the controller creates it | Global Constraints, Task 1 Step 0 |

**2. Placeholder scan:** no "TBD", "TODO", "implement later" or "similar to Task N"; every code step is a `git apply` patch generated by the replay, or a script shown in full; every command has its replay output. Every task, Task 13 included, was replayed on `forever` at `75d71c8b`, the base the branch is created from.

**3. Names and types across tasks:** `I.Events` (`E.CreateFrame`, `E.Subscribe`, `E.Deliver`, `E.Attach`, `E.STUB`), `S.Run`, `S.HANDLERS`, `S.UNITS`, `I.Log` (`L.Emit`, `L.Cast`, `L.Deliver`, `L.Current`, `L.Tick`, `L.OnTick`, `L.Aura`, `L.Energize`, `L.player`, `L.target`, `L.PAIR_WINDOW`, `L.ATTACK_TOLERANCE`, `L.unattributed`), `I.backdate`, `I.hekili`, `Facade.Attach`, `Facade.secrets`, `Facade.QUIET`, the classes `passthrough`/`hybrid`/`virtual` and the trace's `hybrid:raw`/`hybrid:model`, the read statuses `UnitIsUnit target-of` and `UnitAttackSpeed hostile`, and the Snapshot lines `events ...`, `rows ...`, `rows unattributed hits on us=...`, `facade secret passthrough answers: ...` are spelled the same in every task, spec and checkpoint line.

**4. Review Focus:** each of the six lines has its pinned test in the owning task (Tasks 1, 6, 7, 8, 10).

**Concerns for the orchestrator:** (a) Between Tasks 11 and 13 a Gnome Warrior's declared rage maximum is 110.25 (Expansive Mind over the Warrior's own 105 stopgap, which Task 13 removes); no checkpoint falls in between. (b) Decision 7's talent move keeps one Forever line in `ns.updateTalents` (storing the rank, the facade's 12th return): Hekili's original body has no rank, and the Warrior's multi-rank talents need one. (c) The 24 Phase 1 rows that became hybrid answer the client's raw values out of combat, where Phase 1 answered its beliefs; CHECKPOINT A item 4 shows both classes answering, and spec E12 names the edge at combat start. (d) Hits on us need a hostile whose target is the player; a training dummy never attacks, so CHECKPOINT B items 1-3 need an open-world mob. (e) `now` handlers deviate from the design brief in named places, each by the user's ruling or stated here: every verb takes Hekili's own signature (`applyDebuff`/`removeDebuff` unit first, `addStack(aura, duration, stacks)`, `setCooldown(action, duration)`; the user's ruling of 2026-10-15), so Classic handlers port by copying; `now` runs on `CastSuccess` only, not also on `ChannelStart` (ruling: no double run for a channel); a `gain`/`spend` naming no tracked resource is a counted error, never a guess (ruling); writes are live only during a cast's `now` (ruling); tracked extras get no effects (ruling); the brief's "`I.feed.*` writes stay" no longer applies (Tasks 6-7 retired them for the combat-log rows); a `now` may call Lua's pure helpers (`math`, `min`, `error` ...), which the brief's forbidden list does not name. A class file's file-local helper called from a `now` runs in the file's environment (Lua 5.1), so the Warrior passes its talent rank to `stanceKeep`.
