# Restructure src/Hekili and introduce the engine seams: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan
> task-by-task. Approved by the user on 2026-10-17 (plan-mode file `shimmering-forging-blanket.md`, verbatim below with
> the tasks renumbered 1-9: the approved "Task 5c" is Task 6 here, pack tooling is Task 7, the content addons Task 8,
> docs Task 9).

**Goal:** a directory layout that names the engine, the schema and the UI; a publish/subscribe output seam and a
command/registry/configure port on `Hekili.Engine`; content in its own addons; packs built from APL files.

**Spec:** the design is this plan's Context and Target architecture sections (no separate spec); the architecture
page https://claude.ai/artifact/FLHSskFhvdwczFd7BRpimH mirrors them.

## Global Constraints

- `make check` green at every commit; the headless `Arms solo:` gate line byte-identical to the base (timings aside)
  after Tasks 1-4 and 6-8; `make test-loop`, `make test-party`, `make test-druid` green where touched.
- No new tables, closures or string building in recurring paths (Output, Driver, annotators, subscribers).
- Secret values never leave the facade; nothing new compares a possibly-secret value.
- Clean room: no Taco Dog Forever code copied into this repo; patterns may be copied, with a comment naming the origin.
- `local _, ns = ...` opens every core file; content files use `local ADDON = ...` only (Task 8).
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.


## Context

The fork has grown three bodies of code that the directory layout no longer describes. Eleven upstream Hekili files
sit at the addon root (`src/Hekili/*.lua`): the boot file, the simulation and recommendation engine, and the editor
UI. The fork's own registration layer lives in `Engine/` (Spec, Races, Shared), which makes "Engine" name the schema
rather than the engine. The belief lives in `Virtual/`, the content in `Forever/`.

Two couplings block a modern UI (the goal: render the way Taco Dog Forever did, from a model, secret-safe):
- The engine writes its queue into UI-owned tables (`ns.queue`, `ns.UI.Displays[name].Recommendations`) field by
  field between coroutine yields, calls the UI's draw function synchronously (`UI:OnUpdate(1000)`), reads the UI's
  `Active`/`alpha` to decide whether to compute, and writes profiling fields onto the display frame from `State.lua`.
- Options and the UI read the simulation (`state.*`) and the registry (`class.*`) directly; the pack editor runs the
  simulation itself.

The pack pipeline is encode-only: `tools/make_pack.lua` prints share strings that are pasted into the class files
by hand; the build only verifies they match.

Decisions taken with the user (2026-10-17): layout `Engine/Sim` + `Engine/Schema` + `UI/`, `Hekili.lua` at the root;
scope = the move, the engine output seam as publish/subscribe, the Options command/read interface, pack tooling with a
per-class APL file pipeline (one `.simc` per pack + a manifest; add/update/remove); order = move first, then the seams.
Folded in after the architecture page (2026-10-17): `Hekili.Engine` IS the port, six members only (Output,
Subscribe, Unsubscribe, Registry, Snapshot, Evaluate, Configure); engine-internal calls (Begin, Publish, Wanted,
Annotate) and the frame live on the private `ns` (`ns.Output.*`, `ns.EngineFrame`) since Core, the belief and the
driver share the addon; nothing is named "Read"; the engine takes its settings through `Engine.Configure(settings)`
and never names `Hekili.DB`; live facts (combat, target count, spec, pack) are published as `Engine.Output.status`;
an `ns.Output.Annotate(fn)` hook lets the belief add est/lo/hi, basis and confidence to every published record
without touching `Engine/Sim`. Content's whole public surface is the upstream registration API plus `Hekili.Client`
(the facade); character facts reach content through the environment the Schema gives its functions. Also (user,
2026-10-17): the content leaves the core addon as `Hekili_Forever` (shared + races, always loaded) and
`Hekili_Forever_<Class>` (load-on-demand by class), Task 8, so a class release does not bump the engine.

## Target architecture

```
client (WoW Forever)
   │ events + reads (many secret in combat)
   ▼
Virtual/            the believed present: API/Facade (every read), Events (synthesized combat log), State (the belief)
   │ answers every read the engine makes
   ▼
Engine/             Hekili.Engine is the port: the only table UI, Options, WeakAuras and tests touch
  Schema/           Spec, Races, Shared: what content may declare (class-neutral, boundary-tested)
  Sim/              Core, State, Scripts, Events, Targets, Constants, Utils (upstream; baseline-tested)
  Driver.lua        the ns.EngineFrame OnUpdate loop (moved out of UI.lua), profiling fields
  Output.lua        Engine.Output[display]: resolved records, double-buffered, versioned; Engine.Output.status
                    Engine.Subscribe/Unsubscribe (public); ns.Output.Begin/Publish/Wanted/Annotate (private)
  Registry.lua      Engine.Registry.*: views over what content registered; Engine.Snapshot/Evaluate commands
  Settings.lua      Engine.Configure(settings): the profile port; Engine.settings is what Sim/Schema read
   ▲ declares (public Hekili object only)                │ publishes
Hekili_Forever (Shared, Races) + Hekili_Forever_<Class>  ▼
  (separate addons; Content.lua loads the class pack)    UI/ (displays, editor), Engine/WeakAuras.lua, headless loop
Options/ (owns Hekili.DB) ── Configure, Snapshot, Evaluate, Registry ──▶ Engine
Virtual/ ── ns.Output.Annotate ──▶ belief fields on every record (est/lo/hi, basis, confidence)
```

Rules the layout encodes:
- `Virtual/**` and `Engine/Schema/**` contain no class, spell, ability, form or talent name (tests/boundary_spec.lua).
- `Engine/Sim/**` is upstream code: inherited class branches tolerated against a frozen baseline; growth fails.
- `UI/**` and `Options/**` never read `state.*` or `class.*` directly; only `Hekili.Engine.*` (a grep check in
  `make check`, like tools/check_api_reads.sh). `Engine/**` never names `Hekili.DB` or a display frame.
- Content (the `Hekili_Forever*` addons) declares only, through the public `Hekili` object; it never sees the core's
  `ns`. The engine owns everything that runs. A pack addon names the `ContentAPI` it was built against.
- The APL files under `tools/packs/<class>/` are the source of the packs; the class files' `RegisterPack` blocks are
  generated from them.

## Tasks

(Filled from the two design agents' reports; each task is one reviewed branch commit set with `make check` green,
the headless Arms gate line unchanged, and `make test-loop`/`test-party`/`test-druid` green where touched.)

### Task 1: the move (mechanical, one commit)

- `git mv` (after `mkdir -p` Sim and Schema): Core, State, Scripts, Events, Targets, Constants, Utils →
  `src/Hekili/Engine/Sim/`; Spec, Races, Shared → `src/Hekili/Engine/Schema/`; UI, Formatting, MultilineEditor →
  `src/Hekili/UI/` (PopupSlider already there). `Hekili.lua` stays at the root.
- `src/Hekili/Hekili.toc` lines 47-78: same order, paths prefixed (`Engine\Sim\Utils.lua`, `UI\Formatting.lua`, ...,
  `Engine\Schema\Races.lua`, `Engine\Schema\Spec.lua`, `Engine\Schema\Shared.lua`, `UI\UI.lua`, `Engine\Sim\Core.lua`).
  `embeds.xml`, textures (absolute paths), `.luarc.json`: untouched.
- `.styluaignore`: the eleven root entries + `Engine/Spec.lua` become `src/Hekili/Hekili.lua`,
  `src/Hekili/Engine/Sim/`, `src/Hekili/Engine/Schema/Spec.lua` (the existing `src/Hekili/UI/` rule covers the moved
  UI files; Races/Shared stay formatted).
- `.luacheckrc` lines 82-94: four keys replace ten: `Engine/Schema/Spec.lua`, `Engine/Sim/` (dir), `UI/UI.lua` (file
  key, not the dir: Formatting/MultilineEditor/PopupSlider never had `stateEnv`), `Hekili.lua`.
- One sed pass (ERE) over `tests/**`, `tools/*.lua`, `src/Hekili/**` minus Libs, `docs/research/**`,
  `docs/superpowers/specs/*`, `docs/forever-facade-notes.md` (NOT plans, layout.md, the configs, the TOC):
  `src/Hekili/(Core|State|Scripts|Events|Targets|Constants|Utils)\.lua → src/Hekili/Engine/Sim/\1.lua`;
  `src/Hekili/(UI|Formatting|MultilineEditor)\.lua → src/Hekili/UI/\1.lua`;
  `Engine/(Spec|Races|Shared)\.lua → Engine/Schema/\1.lua` (idempotent). Bare `State.lua:123` citations stay valid.
- Hand edits: `tests/Forever/helpers/engine.lua:36` filter → `^Engine\\Schema\\` or `^Forever\\` (else it would load
  Sim too), `:320` → `Engine/Sim/Constants.lua`, header comment; `tests/Forever/shared_spec.lua:283` find →
  `src/Hekili/Engine/Schema src/Hekili/Forever tools/packs`; `tests/boundary_spec.lua:18` CORE →
  `{ Virtual, Engine/Schema, tests/Virtual/harness }`; a comment at `Engine/Sim/Events.lua:180,219` (the debugstack
  match now captures `Engine/Sim/...`; no other reader); `docs/dev/layout.md` first bullet rewritten as the module map
  (+ one sentence: an upstream merge lands new root files at the root; re-home by hand).
- Verify: `make test-loop | grep '^Arms solo:'` saved before, byte-identical after (timings aside); `make check`,
  `make test-party`, `make test-druid` green; boundary file count still 59; `stylua --check --respect-ignores
  src/Hekili/Engine/Sim/State.lua` exits 0 while without `--respect-ignores` it fails (the ignore rule works);
  `make fmt` leaves the tree clean; the stale-path grep (the three old patterns, excluding plans/Libs/.claude/archive)
  returns nothing; `git log --follow` shows the renames. In game: full client restart (TOC changed).

### Task 2: the boundary baseline for Engine/Sim (one commit)

- `tests/boundary_lib.lua`: the scanner moved verbatim out of `tests/boundary_spec.lua` (`read`, `tokens`,
  `content`, `nameWords`, `snake`, `hasWord`, `coreFiles(dirs, skip)`, `nameLeak`, `idLeak`, `leaks`, the ALLOW tables,
  CLASS_WORDS) plus one new `counts(path, c, words) → { [token] = n }`. The spec requires it (`.busted` lpath
  `./tests/?.lua`; no `_spec` suffix so busted does not run it).
- `tools/boundary_baseline.lua` writes `tests/boundary_baseline.lua`: per Sim file, sorted `{ [token] = count }`,
  header "regenerate only when removing an inherited leak; never to admit one". Deterministic (regenerate twice,
  no diff).
- New `it` in boundary_spec: for every `Engine/Sim` file, any token whose count exceeds the baseline fails (lower
  passes); a baseline entry for a missing file fails. The audit's inherited branches (Rogue/Druid GCD, Druid/Rogue
  blocks, Death Knight) appear as class-word tokens; the other ~230 hits are stock field names a Forever key shares
  (`charge`, `execute`, `main_hand`, `use_items`, `trinket1`, `travel_time`, `form`) and `Constants.lua`'s
  class-keyed pseudo-spec rows: baseline, not ALLOW_KEYS (that would loosen the strict scan).
- `docs/dev/layout.md` Checks: two sentences; the audit doc's inherited paragraph: one "now frozen by" line.
- Verify: `busted tests/boundary_spec.lua` green; inject `local x = rend` into a Sim file → the Sim `it` fails, the
  strict `it` untouched; inject into Schema → the strict `it` fails.
- Known limit (documented): a per-file token ceiling, not a line lock; a fork edit that adds one `charge` and removes
  another passes. New content registering a key a Sim identifier already uses fails the Sim `it`: `git blame` the Sim
  line, regenerate, say so in the commit.

### Task 3: the engine output and publish/subscribe (one commit; runs after Task 1's paths)

- The port. `Hekili.Engine` becomes a plain table created in `Hekili.lua` at load (before any TOC file that adds to
  it); the frame created at `UI.lua:2292` becomes `ns.EngineFrame` (global name `HekiliEngine` kept for
  `ProfileFrame`; private because only Driver, Core, Targets, Spec and the snapshot command touch it, all in the
  addon). Sites: `UI.lua:2292-2300, 2371, 2414, 2452, 2455` (`Hekili.Engine` → `ns.EngineFrame`),
  `Targets.lua:1070`, `Engine/Spec.lua:2217`, `Hekili.lua:606` (`HekiliEngine.` → `ns.EngineFrame.`),
  `Options.lua:9725` (see R1). `tests/Virtual/harness/headless.lua` and any spec that touches `HekiliEngine`
  follow (grep before editing).
- New `src/Hekili/Engine/Output.lua` (TOC: after `Engine\Schema\Shared.lua`, before Targets/Options/UI) fills
  `Hekili.Engine.Output` and the functions on `Hekili.Engine`. Per display name (Interrupts, Defensives, Cooldowns,
  Primary, AOE), preallocated at load: `version` (+1 per publish), `count` (records with an action), `recs` (the
  published set, never written by the engine), `scratch` (the set Core builds), `subs` (4 slots, `n`), `wanted`
  (non-passive subscriber count), `payload` (the WeakAuras copy, nil without WeakAuras). A record = the 27 slot fields
  Core writes today + `resources` (subtable allocated once) + the debug fields + three resolved fields `item`,
  `offGCD`, `name` + `belief` (a subtable allocated once, filled only by an annotator; nil fields otherwise). API,
  index loops, zero allocation after the first subscribe. Public on `Hekili.Engine`: `Output`, `Subscribe`,
  `Unsubscribe`. Private on `ns.Output` (Core, the belief and tests share the addon's `ns`): `Begin`, `Publish`,
  `Wanted`, `Annotate`, `Unannotate`. `ns.Output.Begin(name) → scratch` (the clear loop from
  `Core.lua:1607-1615`, scratch only), `Engine.Publish(name, count)` (run the annotators over `scratch[1..count]`,
  swap recs/scratch, bump version, call subscribers with `(name, version, o)`; no yield inside),
  `Engine.Subscribe(name, fn, passive)`, `Engine.Unsubscribe(name, fn)`, `Engine.Wanted(name)`,
  `Engine.Annotate(fn)` / `Engine.Unannotate(fn)` (4 slots; `fn(name, rec, i)` runs before the swap; no cost when
  none is registered; the belief annotator itself is a follow-up spec, this task ships the hook and its test).
- `Engine.Output.status`: one record `{ version, combat, numTargets, specID, specKey, packName }` published by the
  engine through the same `Publish("status", 1)` path whenever one of them changes (combat from `Core.lua`'s
  `PLAYER_REGEN_*` handling, targets from the `TARGET_COUNT_CHANGED` hook of Task 4, spec/pack from `SpecializationChanged`);
  it is how a hidden display learns that combat started and how the target counter draws between publishes.
- `Core.lua` (now `Engine/Sim/Core.lua`): `ns.Output.Begin` replaces the `UI`/`SetThreadLocked`/clear/`checkstr`
  lines at 1602-1615, 2111-2125; the gate at 1619 becomes `ns.Output.Wanted(dispName) and rule(profile)`; `Queue[i] =
  Queue[i] or {}` goes; 2119-2125 → `ns.Output.Publish(dispName, numFilled)`; 2172-2174 (rule false, subscribed) →
  `Publish(name, 0)`; a display with no subscriber is skipped untouched; the AutoSnapshot early return (2111-2112) is
  an explicit skip with the version unchanged (the synchronous snapshot run in the same frame publishes; stock did not
  publish either); 1526-1528 (the AOE global write) deleted as redundant with 2172-2174; the global `Hekili_GetRecommendedAbility`
  (`Core.lua:2189-2209`) DELETED, no reader in the fork or the probe and `Engine.Output` plus `Subscribe` replace it
  (changelog line); `Hekili.lua:162 ns.queue` and `:627 SaveDebugSnapshot`
  read the output (bounded by `count`). The WeakAuras block stays in Core for this task, reading `out.recs` (moves in
  Task 4).
- Coroutine safety: the engine writes only `scratch` between Begin and Publish; every yield site (`Core.lua:730`,
  `2166`, DoYield) leaves `recs` the previous complete set; the swap and version bump are one statement apart.
- R1 (new failure mode, lands in THIS task): `Options.lua:9725 HekiliDisplayPrimary.activeThread = nil` is a dead
  write (the thread lives on the engine frame); a manual/auto snapshot runs `Update()` synchronously while the
  coroutine is suspended and the stale thread would then write into the just-published set. Fix:
  `ns.EngineFrame.activeThread = nil` in `MakeSnapshot`; `output_spec` covers suspend-mid-build + snapshot + resume.
- UI side (minimal, so the queue path is swapped in one task): `d:UpdateAlpha` (`UI.lua:1668-1690`) subscribes
  `d.OnPublish` when Active and alpha > 0, unsubscribes otherwise (`UpdateDisplayVisibility` already calls it on every
  transition, so the computed set equals today's `Active and alpha > 0`); `d.OnPublish` sets `NewRecommendations`
  (UI-private flag); the draw happens on the display's next `OnUpdate` (≤ 1 frame later only when the action list
  changed; side benefit: the draw no longer counts against the engine's frame budget); `RecommendationsStr` → `out.count
  == 0`; `IsThreadLocked`/`SetThreadLocked`/`threadLocked` deleted; `d.Recommendations`/`ns.queue` deleted;
  `b.Recommendation = out.recs[i]`; loops bounded by `count`. `b.Ability` still resolves via `class.abilities` in this
  task (Task 5 moves texture resolution into Core).
- Headless: `headless.new` subscribes to Primary (`headless.lua:~943`), `loop.lua:63-78` and `loop_warrior_spec.lua:15`
  read `Engine.Output.Primary.recs` bounded by `count`.
- Tests: `tests/Forever/output_spec.lua`: (a) pure Begin/Publish/Subscribe: version, count, swap identity, unsubscribe
  mid-list, 0 bytes over 1000 rounds with two subscribers; (b) headless Arms boot with `maxFrameTime = 0.001` so
  DoYield yields at every APL entry, `Update` inside `coroutine.create`: after every resume `recs[1..3]` and `version`
  unchanged until the bump, then every `recs[i ≤ count]` complete (the "never half-built" proof); (c) R1: suspend
  mid-build, `Engine.Snapshot()`, assert the dropped thread and intact `recs`; (d) Annotate: an annotator that
  writes `rec.belief.lo = i` runs over exactly `count` records before subscribers see them, and 0 bytes over 1000
  publishes with one annotator; (e) `Output.status` version bumps on a combat flip and not otherwise. Gates:
  `make test` (6-fight Arms), `make test-loop` byte-identical lines.

### Task 4: the engine stops touching frames; WeakAuras as a subscriber (one commit)

- New `src/Hekili/Engine/WeakAuras.lua` (TOC after Output.lua): on `PLAYER_ENTERING_WORLD`, if `WeakAuras.ScanEvents`
  exists, `Subscribe(name, OnPublish, passive = true)` for the five names (passive: WeakAuras alone never makes the
  engine compute a hidden display, as stock); `OnPublish` fills `out.payload[i]` by field copy (allocated once; the
  stock `__index = payload[1]`, `__mode = "kv"` metatable kept) and calls `ScanEvents("HEKILI_RECOMMENDATION_UPDATE",
  name, recs[1].actionID, recs[1].indicator, nil, payload)`. Core's WA block deleted; `headless.lua:86
  KNOWN_RUN_NILS.WeakAuras` dropped.
- `State.lua:6189` and the 36 lines of reset-timing frame writes (6246-6256, 6337-6347, 6478-6488): DELETED (no reader
  anywhere; ruling: delete rather than relocate).
- `Targets.lua:632 HekiliDisplayAOE:UpdateAlpha()` → `ns.callHook("TARGET_COUNT_CHANGED")` (the hook Core already uses
  at 1904); UI.lua registers the hook once at display creation; the engine's `status` publish listens too.
- New `src/Hekili/Engine/Driver.lua` (TOC before `UI\UI.lua`): the engine frame block moves out of `UI.lua:2292-2460`
  verbatim (`CreateFrame("Frame", "HekiliEngine")`, `refreshTimer`, `eventsTriggered`, `UpdatePerformance`, the
  `OnUpdate` script that resumes the thread, `ProfileFrame`, `IsThreadActive`). The UI no longer owns the loop that
  drives the engine; `UI.lua`'s `Hekili:CreateEngineFrame()`-style entry (whatever wraps 2292) calls into Driver.
- `tools/check_engine_reads.sh` (sibling of `check_api_reads.sh`, wired into the Makefile `api-check` target),
  engine direction first: `Engine/Sim/{Core,State,Targets,Scripts}.lua` must not mention `HekiliDisplay`, `ns\.UI\.`,
  `DisplayPool`. Extended in Task 5 to the UI/Options direction.
- Tests: existing specs; `headless.unexpected(H, "run")` stays empty; the check script.

### Task 5: `Engine.Registry` and the commands: the Options/UI interface (two commits: UI side, then Options side)

- New `src/Hekili/Engine/Registry.lua` (TOC after Output.lua). `Hekili.Engine.Registry`: one-line views over what
  content registered, no copies: `Specs()`, `Abilities()`, `AbilityList()`, `ItemList()`, `Auras()`, `AuraList()`,
  `Potions()`, `PotionList()`, `Gear()`, `ClassFile()`, `Settings(specID)` (the AceOption list from `RegisterSetting`),
  `IsDisabled(key, strict)`, `Talents()`, `SetBonus()`, `GCD_SPELL`. Commands on `Hekili.Engine` itself:
  `Snapshot(isAuto)` (the `MakeSnapshot` body; `Hekili:MakeSnapshot` becomes a delegate) and `Evaluate(pack, list,
  action, mod, results)` (the pack editor's reset + RegisterVariable + this_list/this_action/scriptID +
  `scripts:StoreValues` sequence, extracted once from the four copies at `Options.lua:6762-7087`; verify the four
  `mod` names against `StoreValues`'s `ModElements` keys first). Combat, target count, spec and pack are NOT views:
  they come from `Engine.Output.status` (Task 3).
- UI commit: texture resolution moves into Core's final slot write (`Core.lua:1975-1979`): spells `override.icon or
  rec.texture or ability.texture or GetSpellTexture(id)` (override from the spec's abilities option FIRST, as
  `UI.lua:1181-1188` does today), items `rec.texture or ability.texture or GetItemInfoInstant`, through `ns.Facade`;
  `slot.item/offGCD/name` set there; `b.Ability` becomes the record (`.id → .actionID`, `.gcd ~= "off" → .offGCD`) at
  `UI.lua:1206, 1241, 1291-1296, 1492, 1709-1713, 2830`; every `state.*`/`class.*`/`Hekili.State`/`Hekili.Class`/
  `ns.getNumberTargets`/`VirtualStateInternal` read in UI.lua goes through `Engine.Registry` or `Engine.Output.status`
  (sites: 601-870 menu, 990, 1006-1025, 1172, 1248, 1306, 1361, 1446, 1453, 1494, 1695, 1717, 1768, 2180, 2218, 2256,
  2262, 2670, 3052-3058). Dead reads
  removed: `max(state.gcd.lastStart, state.combat)` at 1717 → `Output.status.combat` (lastStart is a constant 0,
  `State.lua:3217`); the empowerment glow block 1731-1737 and the `elseif not ability.empowered` at 1711 deleted (never
  set; Forever has no empowered ability). The file-level `local state`/`local class` in UI.lua deleted so a missed site
  fails luacheck (W113).
- Options commit: `Options/Options.lua` (the table in the design: 630, 3827-4492, 4553-4640, 5070-5101, 5645-5713,
  6029-6083, 6226-6300, 6476-6568, 6622-7096, 7878-7954, 8210-8325, 9344-9627, 9714-9726), `ChatCommands.lua` (22,
  127-137, 235, 337-440, 589), `DevTools.lua` (87, 93), `Hekili.lua:622-627` all through `Engine.Registry`, the
  commands or `Output.status`; the file-level locals deleted; `check_engine_reads.sh` extended: `UI/UI.lua`,
  `Options/*.lua`, `Hekili.lua` must not match `\bstate[.:]`, `\bclass\.`, `Hekili\.State\b`, `Hekili\.Class\b`,
  `ns\.queue`, `ns\.getNumberTargets`, `VirtualStateInternal`, `DisplayPool`,
  `HekiliDisplay[A-Za-z]*\.(RecommendationsStr|NewRecommendations|activeThread)`, `HekiliEngine\b`.

### Task 6: the profile port, `Engine.Configure(settings)` (one commit, after Task 5)

- Today the engine reaches into the AceDB table directly: `Hekili.DB.profile` / `profile.` mentions in Core 19,
  State 20, Targets 4, Scripts 3, Events 5, Schema/Spec 16 (67 mentions; count distinct sites before editing).
  Options (176) owns the table and stays; UI (56) reads display config, which is UI-owned and stays.
- New `src/Hekili/Engine/Settings.lua` (TOC before `Engine\Sim\Utils.lua`): `Engine.settings` is a plain table whose
  shape the engine defines (`toggles`, `specs[id]` (the per-spec settings table, by reference), `packs`, `targeting`
  fields the engine reads (`enemyCount`, `nameplates`, `petbased`, ...), `maxFrameTime`, `enabled`, `notifications`
  fields Core reads). `Engine.Configure(profile)` assigns the subtables BY REFERENCE (zero copies; the live table
  Options edits is the one the engine reads, as `state.settings.spec` already is) and bumps `Engine.settings.version`.
  Options calls `Configure` at load, in AceDB `OnProfileChanged/OnProfileCopied/OnProfileReset`, and after any setter
  that today calls `Hekili:UpdateUseItems`/`Hekili:Refresh`-class refreshes (list them; `Options.lua` setters that
  write `profile.specs[...]`/`profile.toggles` and expect the engine to notice).
- Every `Hekili.DB.profile` / `profile.` read in `Engine/Sim/**` and `Engine/Schema/**` becomes `Engine.settings.*`
  (the local `profile` upvalues in Core/State/Targets/Scripts/Events are rebound to `Engine.settings`; where a function
  did `local profile = Hekili.DB.profile` per call, it reads `Engine.settings` instead). `Spec.lua:2061`'s
  `state.settings.spec = profile.specs[id]` becomes `Engine.settings.specs[id]`.
- `check_engine_reads.sh` engine direction extended: `Engine/**` must not match `Hekili\.DB\b` or `\.profile\b`
  (except `Engine/Settings.lua`'s `Configure` parameter).
- Tests: `tests/Forever/settings_spec.lua`: `Configure` with two profiles swaps every subtable by identity and bumps
  the version; a toggle flipped in the Options-held table is visible to the engine with no second call (reference
  semantics); headless boot calls `Configure` once from the fixture profile and `headless.unexpected(H, "run")` stays
  empty; `make test-loop` byte-identical. Known cost: ~67 edits in upstream code raise merge friction with upstream
  Hekili; recorded in `docs/dev/layout.md` beside the "re-home new root files" note.
- Tests: the check script in `make check`; `make test`; in game: an ability with a custom icon still shows it (the
  override-first order is the one order-sensitive change), the pack editor's criteria field evaluates, `/hekili
  snapshot`, `/hekili set`, the Issues panel's profile generation.
- Risks carried: subscriber callbacks run inside the engine coroutine as the old synchronous calls did (no pcall,
  stock parity); WeakAuras consumers see the same event, arguments and payload quirk (a user aura reading
  `HekiliDisplayX.RecommendationsStr` directly breaks: changelog line); draw latency ≤ 1 frame only when the list
  changed (a one-line inline draw in `OnPublish` restores stock timing if anyone notices).

### Task 7: pack tooling: per-class APL files, decode, sync, `make packs` (one commit, independent of 3-6)

- Layout: `tools/packs/<class>/<Pack>.simc` holds one pack's SimC text; leading `#` lines are the description; other
  `#` lines and blanks dropped before parse. `tools/packs/<class>.lua` shrinks to the manifest
  `{ date, spec, packs = { "Arms", "Fury", "Protection" } }` (order = block order; `date`/`spec` are class facts).
  A listed name without a file, or a file not listed, is refused. Warrior's shared HEAD lines are duplicated into
  Arms.simc and Fury.simc (plain SimC, like upstream's `Classic/APLs/*.simc`), noted in both headers.
- `tools/make_pack.lua`: `load(class)` reads manifest + files and returns today's pack records (`lists` mode and the
  existing specs unchanged; `warrior_spec.lua:643-653,723` adjusted to the manifest shape); `parse` errors on an
  unknown `k=v` option (today a typo is dropped silently); `unparse(lists)` (default list first, others sorted;
  `actions[.list]=body` then `+=/body`; `action[,name=][,use_off_gcd=N][,if=]`); `decode "<Hekili:...>"` =
  DecodeForPrint → DecompressDeflate → Deserialize (as `Options.lua:9192-9205`), prints `# desc` + `unparse(lists)`,
  warns if that differs from `payload.profile` (the payload already carries the SimC text); `sync(src, packs) →
  newSrc, report` (pure): parses every `spec:RegisterPack(\n    "Name",\n    version,\n    [[...]]\n)` block in the
  class file's StyLua layout, refuses on any `RegisterPack(` it cannot parse, duplicate names, non-block content inside
  the block span, or no block at all; replaces the span with the manifest's packs in order (added / updated / removed /
  unchanged per name); `write [class]` runs sync on `Forever/Classes/<Class>.lua`, writes only if changed, exit 1 on
  refusal; `lib` mode returns `{ parse, unparse, encode, decode, sync, load }` for tests.
- Makefile: `packs:` runs `write` for every `tools/packs/*.lua`; `.PHONY`; not part of `check`.
- `tests/Forever/make_pack_spec.lua` (fast): round trip per pack (`unparse(decode(encode(p)).lists) ==
  unparse(p.lists)`, `parse(unparse(lists))` deep-equals, `decode(encode(p)).profile == p.simc`); no-op: `sync` on each
  real class file returns the identical string and all-`unchanged`; add/update/remove on an in-memory Warrior.lua
  (delete the Fury block → restored byte-for-byte `Fury added`; change Arms's version → `Arms updated`; append a `Zzz`
  block → `Zzz removed`; a one-line `RegisterPack(` → error); `parse` errors on `foo=1`.
- Verify: the migration's first `make packs` rewrites all six blocks once (date bump → every saved profile reports
  "updated" in game, once); a second `make packs` prints only `unchanged` and `git diff --exit-code` is clean;
  `make check` green.

### Task 8: the content addons: `Hekili_Forever` and `Hekili_Forever_<Class>` (three commits: spike, surface, split)

Why: a separate addon has its own private `ns`, so content can reach the engine only through the public `Hekili`
object; class releases carry their own version; a player installs the core plus their class. TDF already runs this
shape (`src/TacoDogForever` + `_Data` + `_Druid`/`_Warrior`, load-on-demand via `Boot.lua:162-164`), so the layout,
the TOC fields and the loader pattern are copied from there, not invented.

- Commit 1, the spike (in game, the user; ~10 min): a throwaway `src/Hekili_Forever_Spike/` addon with
  `## Dependencies: Hekili`, `## LoadOnDemand: 1`, one file that calls `Hekili:NewSpecialization` for a fake spec and
  prints; the core's `OnEnable` (`Core.lua:197`, fires at PLAYER_LOGIN, before PLAYER_ENTERING_WORLD where
  `SpecializationChanged` runs, `Events.lua:336-339`) gets a temporary `C_AddOns.LoadAddOn("Hekili_Forever_Spike")`.
  Pass = the spec is registered and `SpecializationChanged` picks it up on `/reload` with no error; also verify a
  `## Dependencies` addon loads after `Core.lua` without `OnInitialize` ordering problems. The spike addon is
  deleted in the same commit's follow-up; the finding goes in `docs/research/2026-10-17-content-addon-spike.md`.
  If the load-on-demand path fails, fall back to plain `## Dependencies` addons (always loaded when installed) and
  say so in the research note; the rest of the task is unchanged.
- Commit 2, the content surface (headless, no in-game step). The whole public surface for content is the upstream
  registration API (`Hekili:NewSpecialization`, `Hekili:NewRace`, `spec:Register*`, `Hekili.State`/`Hekili.Class`
  already public at `Hekili.lua:101,158`) plus ONE new name, `Hekili.Client`: the facade, the game client as the
  addon may read it (set beside `ns.Facade = Facade` at `Virtual/API/Facade.lua:21`; same table, second name).
  Content's file-level game reads go through it: `ns.Facade` at `Warrior.lua:21`, `Druid.lua:20`,
  `Shared/Auras.lua:11`, `Shared/Consumables.lua:12` (`C_Item`, `C_LossOfControl`, `C_Spell`, `C_SpellBook`,
  `CombatLogGetCurrentEventInfo`, `GetTime`, `UnitClassBase`) and `ns.UnitDebuff` at `Shared/Auras.lua:14` (defined
  `Utils.lua:35`; becomes `Hekili.Client.UnitDebuff`, or the facade's own reader if `Facade.lua` already has one).
  The belief is NOT exposed. Its five content uses become environment names and a declaration:
  `VS.KnownRank(ids)` (`Warrior.lua:82`, `Druid.lua:132`) → `knownRank(ids)`, already in the `now` context
  (`Families/Now.lua`); the Schema adds it, with `stat(name)` (→ `VS.Stat`), `swingBase(hand)` (→ `VS.SwingBase`) and
  `healthMax(unit)` (→ `VS.HealthMax`), to the environment of every content function: the sim `state` env (the
  `knownRank` local the class files define today reads `state`; `State.lua`'s mt_state gains the four names answering
  from the belief), the `now` context, and the resource-model functions in the spec's resource meta tables
  (`Warrior.lua:129,170-172,222,228` call `VS.SwingBase`/`VS.Stat`/`VS.HealthMax` from plain functions; `Spec.lua`'s
  `RegisterResource` setfenv's those functions to the same env it gives handlers, which is where the Schema already
  wraps them). `VS.Track({ abilities = { TACTICAL_MASTERY } })` (`Warrior.lua:87`) → a declaration:
  `spec:RegisterAbility("tactical_mastery", { id = ..., passive = true })`, and `Spec.lua`'s ability registration
  forwards `passive` abilities to `VS.Track` (the Schema tells the belief what to watch; content never calls it).
  The content files lose every `ns.` and `VS.` mention; `tests/boundary_spec.lua` gains an `it`: every `Hekili[.:]name`
  token in a content file is in the allowlist `{ NewSpecialization, NewShared, NewRace, State, Class, Client }` (pack
  share strings excluded: skip `[[...]]` long strings before scanning), and no content file mentions `\bns\.`,
  `VirtualState`, `Hekili.Virtual`, `Hekili.Engine` or `local _, ns = ...` (content uses `local ADDON = ...` for its
  own name only). `Hekili.Virtual` (`Adapter.lua:26`) becomes `{ State = VS, Events = I.Events }`: the probe/`/run` debug
  handle, documented as not for content; its `API` member is dropped because it is the same table as `Hekili.Client`
  (one name per thing); the `Hekili.VirtualState` alias (`Adapter.lua:27`, "for one release") is deleted and the
  `Snapshot.lua:4` comment follows; ForeverProbe's `Calib.lua:18,134` read `Hekili.Virtual.State` (the user updates
  the probe; note in the report). The ContentAPI number is NOT a public member: `Engine/Content.lua` holds `local CONTENT_API = 1`
  and compares each pack's TOC field against it.
- Commit 3, the split (mechanical): `git mv src/Hekili/Forever/Shared src/Hekili_Forever/Shared`,
  `src/Hekili/Forever/Races → src/Hekili_Forever/Races`, `src/Hekili/Forever/README.md → src/Hekili_Forever/`,
  `src/Hekili/Forever/Classes/Warrior.lua → src/Hekili_Forever_Warrior/Warrior.lua`, Druid likewise. New TOCs:
  `src/Hekili_Forever/Hekili_Forever.toc` (`## Interface: 16001`, `## Dependencies: Hekili`, `## X-Hekili-ContentAPI:
  1`, the Shared then Races lines from `Hekili.toc:58-60,63-70` in that order) and
  `src/Hekili_Forever_Warrior/Hekili_Forever_Warrior.toc` (`## Dependencies: Hekili, Hekili_Forever`, `## LoadOnDemand:
  1`, `## X-Hekili-ContentAPI: 1`, `Warrior.lua`); Druid likewise. `Hekili.toc:58-70` deleted. Core loader (new
  `src/Hekili/Engine/Content.lua`, TOC after `Driver.lua`): in `OnEnable`, `name = "Hekili_Forever_" ..
  select(2, UnitClass("player"))` title-cased (`WARRIOR → Warrior`), read `C_AddOns.GetAddOnMetadata(name,
  "X-Hekili-ContentAPI")`; if the addon is not installed: `Hekili:Notify` once ("no Forever pack for <Class>; install
  <name>") and continue with no spec; if the number differs from `CONTENT_API`: Notify the mismatch and do not
  load; else `C_AddOns.LoadAddOn(name)` under pcall, Notify on failure (the TDF pattern). `Hekili_Forever` itself is a
  hard dependency so needs no loader. Pack tooling: `make_pack.lua write` targets `src/Hekili_Forever_<Class>/<Class>.lua`
  (Task 7 wrote `Forever/Classes/<Class>.lua`; one path constant). Config: `.luacheckrc:114-124` keys →
  `src/Hekili_Forever_Warrior/Warrior.lua`, `src/Hekili_Forever_Druid/Druid.lua`, `src/Hekili_Forever/Races/`,
  `src/Hekili_Forever/Shared/`; `.styluaignore` unchanged (content is formatted). Every reader of `Hekili.toc`
  (`tests/Forever/helpers/engine.lua:33-41` `M.files()` → reads the three content TOCs after the core's `Engine\`
  lines, in dependency order; `tests/Forever/{shared,races,engine_load}_spec.lua`, `tests/Virtual/harness/headless.lua`,
  `tests/Virtual/State/{now_spec,helpers/load,helpers/fake_api}.lua`, `tests/Virtual/API/facade_spec.lua`,
  `tools/check_api_reads.sh`, `tools/list_api_reads.sh`) gets the list of TOCs from one helper
  (`tests/helpers/addons.lua`: `{ "Hekili", "Hekili_Forever", "Hekili_Forever_Warrior", "Hekili_Forever_Druid" }` with
  each addon's root and TOC path; the TDF loader `tests/helpers/load.lua` is the model). `tests/boundary_spec.lua:18`
  CORE unchanged (content never was core). `tests/Forever/shared_spec.lua:283` find paths → the two content roots +
  `tools/packs`. `docs/dev/layout.md`: the addon list and three more `mklink` lines (line 36 pattern) for
  `Hekili_Forever`, `Hekili_Forever_Warrior`, `Hekili_Forever_Druid`; "a class release bumps the pack addon's
  `## Version`; the core's `ContentAPI` bumps only when the Schema or the content surface changes".
- Tests: `tests/Forever/content_spec.lua`: the loader picks `Hekili_Forever_Warrior` for WARRIOR and Notifies for a
  class with no pack (fake `C_AddOns` with `GetAddOnMetadata`/`LoadAddOn` recorded); a ContentAPI mismatch Notifies and
  does not call `LoadAddOn`; the headless Arms gate line byte-identical; `make check`, `make test-loop`,
  `make test-party`, `make test-druid` green; the boundary `it` for `ns.` in content; `grep -rn 'Forever/' .luacheckrc
  tools tests` finds only the new roots. In game (the user): three new `mklink` entries, full client restart, Warrior
  and Druid each see their spec; a character of a third class sees the "no pack" notice and no Lua error.

### Task 9: docs and the architecture page

- `docs/dev/layout.md` already rewritten in Task 1 (and again in Task 8 for the addon list); `docs/dev/architecture.md`
  (new): the module map above with the rules, the `Hekili.Engine` port (Output, Subscribe, Annotate, Registry,
  Snapshot, Evaluate, Configure), the content surface (`Hekili.Client`, the environment names `knownRank`/`stat`/
  `swingBase`/`healthMax`, `passive` abilities, the `X-Hekili-ContentAPI` TOC field), cross-linked
  from layout.md. Task 9 runs last, after Task 8.
- The architecture artifact page (published, private; https://claude.ai/artifact/FLHSskFhvdwczFd7BRpimH) kept in
  step with the port as built.
- Follow-up spec (not in this plan): the belief annotator, `Virtual/Annotate.lua`, registered through
  `ns.Output.Annotate`: per record the gating resource's est/lo/hi at the record's time, the basis of the usability
  read (observed/pinned/modelled + event), band width relative to cost as a confidence, the gating aura or cooldown
  and its basis, the GCD kind. Needs its own short design (field list, forecast at t) before a task is written.

## Verification

- `make check` green after every task; the `Arms solo:` line printed by the headless gate byte-identical to the base
  (timings excluded) after Tasks 1-2 and after Task 3-4 (the queue must not change).
- `make test-loop`, `make test-party`, `make test-druid` green after Tasks 1, 3, 4.
- The boundary scan's file count and the new Sim baseline pass; an injected leak in Schema fails; a new token in Sim
  fails.
- `tests/Forever/output_spec.lua`: the never-half-built proof under `maxFrameTime = 0.001` and the R1 snapshot case
  pass; zero allocation over 1000 publish rounds.
- `tools/check_engine_reads.sh` in `make check`: Engine/ mentions no display frame and no `Hekili.DB`; UI/ and
  Options/ contain no `state.` / `class.` / `HekiliEngine` reads outside `Hekili.Engine.*`.
- `tests/Forever/settings_spec.lua`: `Configure` swaps by reference; a toggle edit is visible without a second call.
- Pack round trip: encode then decode equals the normalized text; `make packs` is a no-op on a clean tree.
- In game (the user, after the merge): `/reload`, displays draw as before, the options editor opens, a pack edit via
  `make packs` reloads as "updated", a snapshot opens.
