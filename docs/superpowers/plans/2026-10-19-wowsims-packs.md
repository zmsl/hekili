# wowsims.com Packs and the Replay Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Run after the per-spec plan (`docs/superpowers/plans/2026-10-19-forever-specs.md`) merges into `forever`**: packs
> bind to spec keys (`APLs/packs.lua` `{ class, packs, specs = { [<Pack>] = "<key>" } }`), classes call
> `Hekili:NewClass`, spec ids are `100000 + classID x 10 + slot`, `CONTENT_API` is 6. Every line number below is from
> `forever` 149d286f and has drifted: grep for the quoted anchor text. Tasks 12-14 wait for their class pack (Mage on
> Day 6, Warlock, Priest and Elemental on Day 7).
>
> **Pack choice, binding (user, 2026-10-19):** at the end every spec has ONE priority, "<Spec> (wowsims.com)", and it
> is the spec's default. The per-spec plan's pack-choice migration therefore simplifies to "every spec's choice is its
> wowsims pack": Task 1 adds `RetirePacks`, and each spec's task retires the old list, so a stored choice of a retired
> list falls back to the spec's default (the wowsims pack) on the first login after the update, whichever of the two
> migrations runs last. The only hand-built list kept is one whose spec has no wowsims default APL: Mage Frost (Day 6),
> if that day ships a Frost pack. Healing trees keep "no priorities".

**Goal:** Every spec with a wowsims/forever default APL gets the priority "<Spec> (wowsims.com)", translated from that
APL, as its only and default priority; the headless harness replays wowsims fights so a gate holds how closely the
pack's first on-GCD icon follows wowsims's own casts, and a leveling gate holds that the pack stays live from the
spec's first level to 60.

**Architecture:** A dev-only exporter (`tools/wowsims/export.lua`, Go and a wowsims checkout needed) turns a per-spec
recipe into a RaidSimRequest, runs `wowsimcli` and checks in the request and its debug log; CI needs neither. A
translator (`tools/wowsims/apl.lua`, CI-safe) turns the checked-in request's APL into the pack's `.simc` with the
fork's keys, guarding every cross-ability read so an unlearned ability cannot block a line; `make packs` builds it as
before. The harness gains a log-driven world (`tests/Game/harness/replay.lua`) behind ONE injection in `loop.run`
(`o.replay`: world factory, presses off, wowsims's casts as `theirs`, a cycle just before each wowsims cast), and
`loop.replay`/`loop.summary` report the decision-point on-GCD agreement. `tests/Forever/helpers/wowsims.lua` makes a
class world's content a replay's or a leveling bracket's, and runs the two gates.

**Tech Stack:** Lua 5.1 and busted (`.lua/`), dkjson (installed with busted), wowsims/forever (MIT) at a pinned commit
with its CLI (`go`, `protoc`, `protoc-gen-go` once), `wowdb` for learn levels.

**Spec:** the user's goal (binding): "The goal with the harness will be to get the '<spec> (wowsims.com)' action list
for each class/spec to match as close as possible to wowsims output." The outline
`~/.claude/plans/shimmering-forging-blanket.md`; the spike `~/.claude/jobs/080a308e/tmp/wowsims-spike/report.md` (one
Arms fight replayed: 0.71 decision-point on-GCD agreement with wowsims-matching settings; its `replay_spec.lua` is the
throwaway driver this plan turns into tracked code). User changes of 2026-10-19 (binding): the wowsims pack is each
spec's default; the hand-built lists are removed once the spec's wowsims pack passes its gate; packs work from a
spec's first level to 60 (leveling rule and gate below).

## Global Constraints
- `make check` green before every commit. Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  (the executing model's line).
- **Gate lines.** Before Task 1 record the base (Task 1 Step 0). After every task, every ` solo: ` line from
  `make check` and `make test-druid test-rogue test-paladin test-shaman test-hunter` is byte-identical to the base once
  `cpu mean X p99 Y ms; ` is removed, EXCEPT the lines of the spec whose old list that task retires: those move onto
  its wowsims pack and are re-baselined in that task (new lines into `/tmp/wowsims/solo-base.txt`, the SDD ledger and
  `docs/dev/layout.md`). Their health, react and refusal assertions still hold; never relax a threshold to pass. Any
  other changed line is a bug: superpowers:systematic-debugging.
- **Fixtures.** `tests/Forever/fixtures/{classic_draw,timeline_draw,classic_options}.lua` unchanged.
  `arms_recs_seeds1-3.lua` is re-recorded once, in Task 5, because its pack is retired (`ARMS_RECS=record`); a fixture
  is re-recorded for no other reason.
- **Boundary** (`tests/boundary_spec.lua`): no class, spell, aura, talent or form name in `src/Hekili/Game/**`,
  `src/Hekili/Engine/Schema/**` or `tests/Game/harness/**` (its `fixtures/` excepted). `replay.lua` and its spec use
  only wowsims's log words and invented IDs (900000+). Class names, keys and IDs live in the packs, `tests/Forever/**`
  and `tools/wowsims/**`.
- **Layering:** no WoW globals in tests or tools; the core reads packs only through the existing content surface.
- **Performance:** no new tables, closures or string building in recurring addon paths. This plan touches only
  RestoreDefaults (login, not recurring) in the addon; the harness and tools are test code.
- **Packs:** `.simc` files are repo-only (no TOC lists them); a wowsims pack's `.simc` is generated
  (`make wowsims-packs`), never hand-edited; its recipe `tools/wowsims/specs/<spec>.lua` is the source.
- **Licences and credits:** our files GPL v3 or later (the repository's). wowsims/forever is MIT: every file that
  carries or translates its data (recipes, requests, logs, the generated `.simc` headers, `replay.lua`, the exporter,
  the translator) credits "wowsims/forever (MIT, https://github.com/wowsims/forever)" in its header. No Go code is
  copied; the APL JSON is translated as data.
- **wowsims pin:** `tools/wowsims/export.lua` `M.PIN` = `d33930d04030c3f556582f31949f1f22c17da0e4`; every checked-in
  log's first line names it (`tests/Forever/wowsims_pin_spec.lua`). Moving the pin means re-exporting every spec.
- **Leveling rule:** every condition that reads another ability's cooldown, cast time, cost, readiness or its aura is
  guarded so an unlearned ability cannot block its line (Task 4's translator emits the guards, Task 4's
  `check_pack_levels` refuses an unguarded one). Engine facts this rests on (cite in the translator header):
  `src/Hekili/Engine/Sim/State.lua` `mt_default_cooldown` answers `remains` 0, `charges` max and
  `time_to_max_charges` 0 for an ability `state:IsKnown` says is unknown (the `if not state:IsKnown( t.key )` lines in
  its `__index`), so `cooldown.X.remains>Y` is false and would block; `mt_default_action` answers `known`/`enabled`
  through `state:IsKnown` (the `if k == "enabled" or k == "known"` branch); and `src/Hekili/Engine/Sim/Core.lua`'s list
  walk recommends an entry only when `ability and known and enabled` (the `known, reason = self:IsSpellKnown( action )`
  block), so a line whose own action is unlearned is skipped, never an error.
- StyLua formats our files; `Spec.lua` keeps upstream spacing (`.styluaignore`).
  The code blocks below pass luacheck but are not StyLua-final: run `stylua <file>` on each file you create or edit.
- **Dry run.** The plan writer ran Tasks 2-4's code and Task 5's pipeline on a scratch copy of 149d286f (pre-per-spec:
  the class kit read as `specs[1491]`): the exporter, the parser and world specs, the loop injection, the translator
  on the real Arms APL and the Arms replay passed; the numbers quoted in Task 5 are from it.

## Review Focus
The five ways a replay can lie, most likely first; each is pinned by a test in the owning task.
1. **Off-GCD lines dominating the metric.** wowsims casts off-GCD abilities (rage generators, stances, racials) at
   moments any icon would "agree" with, and our off-GCD lines show during every GCD. Expected: the headline counts only
   wowsims's on-GCD casts, scored against our first on-GCD icon. Pinned in Task 3 (`loop_spec` "decisions": an off-GCD
   decision is not scored) and the replay spec (the fixture's GCD-0 casts carry `gcd = false`).
2. **Procs counted as choices.** A `Casting` line for a proc (Deep Wound, a seal's hit, a weapon proc) that maps to one
   of our keys would be scored as wowsims's choice. Expected: a content's `procs` IDs are neither decisions nor cast
   events. Pinned in Task 3 (`replay_spec` "procs").
3. **Resource after-values versus regen.** Applying the log's deltas, or ticking a regen of our own, drifts from
   wowsims; not reporting a regen rate makes the engine's energy and mana forecast flat. Expected: the truth is each
   logged after-value; the world runs no regen ticks of its own but the client still reads the content's rate.
   Pinned in Task 3 (`replay_spec` "power").
4. **An aura the client never shows.** Forever's Overpower window (1282733) and similar hidden auras drive wowsims's
   choices but the client's aura walk cannot see them; shown, they lie the other way. Expected: `hidden` IDs live in
   the world's truth (usability) and emit no client aura event; known auras take the log's real duration when they
   fade naturally. Pinned in Task 3 (`replay_spec` "auras").
5. **Execute phase from scaled health.** wowsims's execute phase is the last 20% of the duration; the spike's scaled
   health crossed 20% only at the first hit after 144 s. Expected: the mob's health is at or under 20% from exactly
   `pull + 0.8 x duration` and above it before. Pinned in Task 3 (`replay_spec` "execute").

---

## File map
- Create (Task 1): `tests/Forever/retired_packs_spec.lua`.
- Create (Task 2): `tools/wowsims/export.lua`, `tools/wowsims/specs/` (one recipe per spec, from Task 5),
  `tests/Forever/wowsims/` (requests `<spec>.json`, logs `<spec>.log`, `learn_<class>.lua`),
  `tests/Forever/wowsims_pin_spec.lua`.
- Create (Task 3): `tests/Game/harness/replay.lua`, `tests/Game/harness/replay_spec.lua`,
  `tests/Game/harness/fixtures/wowsims_test.log`, `tests/Forever/helpers/wowsims.lua`.
- Create (Task 4): `tools/wowsims/apl.lua`, `tools/check_pack_levels.lua`, `tests/Forever/wowsims_apl_spec.lua`,
  `tests/Forever/wowsims_levels_spec.lua`.
- Create (Tasks 5-14): `tests/Forever/wowsims_<class>_spec.lua`, `src/Hekili_<Class>/APLs/<Spec> (wowsims.com).simc`
  (generated).
- Modify: `src/Hekili/Engine/Schema/Spec.lua` (RestoreDefaults, `RetirePacks`), `src/Hekili/Hekili.lua`
  (`Class.retiredPacks`), `src/Hekili/Engine/Content.lua` (CONTENT_API 7), every content TOC,
  `tests/Forever/helpers/engine.lua`, `tests/Forever/content_spec.lua`, `tests/Game/harness/loop.lua`,
  `tests/Game/harness/loop_spec.lua`, `Makefile`, the class files and their `APLs/packs.lua`, the class worlds
  (`tests/Forever/helpers/*_world.lua`), the gate specs that name a retired pack, `docs/dev/layout.md`,
  `docs/superpowers/plans/2026-10-18-class-completion.md`.

## The gate commands (every task that says "Gate")
```bash
mkdir -p /tmp/wowsims
make check 2>&1 | tee /tmp/wowsims/check-$TASK.log | grep ' solo: fights=' \
  | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort > /tmp/wowsims/solo-$TASK.txt
make test-druid test-rogue test-paladin test-shaman test-hunter 2>&1 | grep ' solo: fights=' \
  | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort >> /tmp/wowsims/solo-$TASK.txt
diff /tmp/wowsims/solo-base.txt /tmp/wowsims/solo-$TASK.txt && echo "gate lines identical"
```
Expected: `make check` exit 0 and `gate lines identical`, or (a swap task) a diff only in the lines of the spec it
retires; then copy those new lines into `/tmp/wowsims/solo-base.txt` and the ledger.

---

### Task 1: retired built-in packs fall back to the spec's default (S)

**Files:**
- Create: `tests/Forever/retired_packs_spec.lua`
- Modify: `src/Hekili/Engine/Schema/Spec.lua` (`HekiliSpecMixin`, `Hekili:RestoreDefaults`), `src/Hekili/Hekili.lua`
  (`Hekili.Class`), `src/Hekili/Engine/Content.lua`, every `src/Hekili_*/Hekili_*.toc`,
  `tests/Forever/helpers/engine.lua` (the strict class stub), `tests/Forever/content_spec.lua`

**Interfaces:**
- Produces: `kit:RetirePacks(names)` (content surface, CONTENT_API 7): `names` a list of built-in pack names the class
  no longer ships. `Hekili.Class.retiredPacks[name] = true`. At RestoreDefaults (every login) a saved built-in pack of
  a retired name is deleted and any spec whose `package` names it reverts to its default (`spec.options.package`).
  A user's own pack (`builtIn` false) of that name is kept.

- [ ] **Step 0: Record the gate base** (before any edit, on the fresh branch):

```bash
mkdir -p /tmp/wowsims
make check 2>&1 | grep ' solo: fights=' | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort > /tmp/wowsims/solo-base.txt
make test-druid test-rogue test-paladin test-shaman test-hunter 2>&1 | grep ' solo: fights=' \
  | sed -E 's/cpu mean [0-9.]+ p99 [0-9.]+ ms; //' | sort >> /tmp/wowsims/solo-base.txt
wc -l /tmp/wowsims/solo-base.txt
```
Expected: the per-spec plan's line count (about 30). Copy the file into the SDD ledger.

- [ ] **Step 1: Write the failing spec** `tests/Forever/retired_packs_spec.lua`:

```lua
-- tests/Forever/retired_packs_spec.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md,
-- Task 1): a built-in pack the class retires (kit:RetirePacks) leaves a saved profile at RestoreDefaults, and a spec
-- that chose it falls back to its default priority; a user's own pack of that name stays.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("retired built-in packs", function()
    it("are dropped from the profile and their specs return to the default priority", function()
        local H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        local hk = H.Hekili
        local p = hk.DB.profile
        local id = hk.State.spec.id
        p.packs["Retired Test"] = { builtIn = true, spec = id, version = 1, date = 1, lists = {}, profile = "" }
        p.packs["Mine Test"] = { builtIn = false, spec = id, version = 1, date = 1, lists = {}, profile = "" }
        p.specs[id].package = "Retired Test"
        hk.Class.retiredPacks["Retired Test"] = true
        hk.Class.retiredPacks["Mine Test"] = true
        hk:RestoreDefaults()
        assert.is_nil(rawget(p.packs, "Retired Test"))
        assert.is_not_nil(rawget(p.packs, "Mine Test")) -- not built in: the user's
        assert.are.equal(hk.Class.specs[id].options.package, p.specs[id].package)
    end)

    it("is a kit method the content calls", function()
        local engine = require("Forever.helpers.engine")
        local env = engine.load("WARRIOR")
        env.class.kit:RetirePacks({ "Old A", "Old B" })
        assert.is_true(env.class.retiredPacks["Old A"] and env.class.retiredPacks["Old B"])
    end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted tests/Forever/retired_packs_spec.lua`
Expected: FAIL (`retiredPacks` is nil; `RetirePacks` is not a method).

- [ ] **Step 3: Implement.**
  - `src/Hekili/Hekili.lua`, in `Hekili.Class = { ...`, after `packs = {},` add `retiredPacks = {}, -- kit:RetirePacks`.
  - `tests/Forever/helpers/engine.lua`, in `M.load`'s list of class fields (the `for _, k in ipairs({ "resources", ...`
    list), add `"retiredPacks",` after `"packs",`.
  - `src/Hekili/Engine/Schema/Spec.lua`, in `HekiliSpecMixin` (beside `RegisterPack`) add:

```lua
    -- Built-in packs the class no longer ships (wowsims packs plan, Task 1): RestoreDefaults drops their saved copies
    -- and points a spec that chose one back at its default.
    RetirePacks = function( self, names )
        for _, name in ipairs( names ) do
            class.retiredPacks[ name ] = true
        end
    end,
```
  - In `function Hekili:RestoreDefaults()`, after `local changed = {}` and before `for k, v in pairs( class.packs ) do`:

```lua
    -- A retired built-in pack (kit:RetirePacks) leaves the profile; a spec that chose it falls back to its default.
    for k, v in pairs( p.packs ) do
        if class.retiredPacks[ k ] and v.builtIn then
            p.packs[ k ] = nil
            for _, sp in pairs( p.specs ) do
                if type( sp ) == "table" and rawget( sp, "package" ) == k then sp.package = nil end
            end
            insert( changed, k )
        end
    end
```
    (`sp.package = nil` lets AceDB's default, the spec's own package, answer again; `changed` makes the existing code
    below reload the scripts.)
  - `src/Hekili/Engine/Content.lua`: add the history line
    `-- 7 (2026-10-2x): kit:RetirePacks (wowsims packs plan, Task 1).` and `local CONTENT_API = 7`; set
    `## X-Hekili-ContentAPI: 7` in every `src/Hekili_*/Hekili_*.toc`; in `tests/Forever/content_spec.lua` change the
    current-version literals 6 -> 7 and the mismatch case's older version to `"6"`.

- [ ] **Step 4: Run the spec, then the gate**

Run: `.lua/bin/busted tests/Forever/retired_packs_spec.lua tests/Forever/content_spec.lua`
Expected: PASS. Gate with `TASK=1`: `gate lines identical`.

- [ ] **Step 5: Commit**

```bash
git add src/Hekili src/Hekili_*/Hekili_*.toc tests/Forever/retired_packs_spec.lua tests/Forever/helpers/engine.lua \
  tests/Forever/content_spec.lua
git commit -m "feat(packs): kit:RetirePacks; a retired built-in pack falls back to the spec's default priority

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: the wowsims exporter and its pin (M)

**Files:**
- Create: `tools/wowsims/export.lua`, `tools/wowsims/specs/.gitkeep`, `tests/Forever/wowsims/.gitkeep`,
  `tests/Forever/wowsims_pin_spec.lua`
- Modify: `Makefile`, `.luacheckrc` (only if luacheck flags `tools/wowsims/`: add `files["tools/"] = { std = "lua51" }`)

**Interfaces:**
- Produces (`assert(loadfile("tools/wowsims/export.lua"))()` returns `M`): `M.PIN`, `M.OUT` (`"tests/Forever/wowsims/"`),
  `M.SEED` 101, `M.DURATION` 180, `M.TARGET_LEVEL` 63, `M.ENCOUNTER`, `M.talents(str, trees) -> { { spellID, rank,
  tree }, ... }`, `M.request(recipe, root) -> table`, `M.export(spec)`, `M.learn(token)`, `M.recipe(spec)`.
- Produces (files): `tests/Forever/wowsims/<spec>.json` (the request), `<spec>.log` (header + the debug log),
  `learn_<class>.lua` (`return { [spellID] = level, ... }`).
- Log header (consumed by Task 3's parser):
  `# wowsims <40-hex pin> <spec> seed <n> <duration> s target <level>` then `# talents <id>=<rank>@<tree> ...`.
- Recipe shape (`tools/wowsims/specs/<spec>.lua`, written per spec in Tasks 5-14):

```lua
return {
    class = "WARRIOR", -- the fork's class token (engine.load)
    pack = "Arms (wowsims.com)", -- the pack's name (packs.lua, RegisterPack)
    spec = "arms", -- the fork's spec key
    name = "Arms", -- the player's name in the request and the log
    talentTree = "warrior", -- wowsims ui/sim/talents/trees/<this>.json
    apl = "ui/specs/warrior/dps/apls/arms.apl.json", -- the default APL (or nil: the build's own rotation)
    build = nil, -- "ui/specs/<class>/<spec>/builds/<x>.build.json": its player wholesale (name replaced; `apl`, when
    -- given, replaces its rotation)
    player = { -- when `build` is nil: transcribed from the spec's presets.ts / spec.ts (cite lines in a comment)
        race = "RaceOrc", class = "ClassWarrior",
        gear = "ui/specs/warrior/dps/gear_sets/p1_arms.gear.json",
        talentsString = "30325213132515201-0505-2",
        specKey = "dpsWarrior", -- the request's oneof field (proto/api.proto `oneof spec`, lowerCamelCase)
        options = { classOptions = { queueDelay = 250 } }, -- the spec's DefaultOptions, as protojson
        profession1 = "Engineering", profession2 = "Blacksmithing",
        reactionTimeMs = 100, distanceFromTarget = 25,
    },
    -- the translation (Task 4)
    executePhase = "execute_phase", -- the class's expression for wowsims's isExecutePhase E20 (nil: unsupported)
    map = {}, -- [wowsims spell ID | "item:<id>" | otherId] = our key, where the class data does not say
    focus = {}, -- [our key] = tier (every line of that action) or { tier, ... } (by occurrence)
    leveling = {}, -- extra default-list lines for low levels, each silent at 60 (`!action.<60 ability>.known&...`)
}
```

- [ ] **Step 1: Write the failing spec** `tests/Forever/wowsims_pin_spec.lua`:

```lua
-- tests/Forever/wowsims_pin_spec.lua (wowsims packs plan, Task 2; check_wowsims_pin): every checked-in wowsims log
-- comes from the wowsims/forever commit tools/wowsims/export.lua pins, every recipe has its request and log, and the
-- exporter's pure parts (the talent string, the request) hold. Data: wowsims/forever (MIT).
local ex = assert(loadfile("tools/wowsims/export.lua"))()

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
    end
    return f ~= nil
end

local function tmp(text)
    local path = os.tmpname()
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
    return path
end

describe("check_wowsims_pin", function()
    it("finds every recipe's log made at the pinned wowsims commit, beside its request", function()
        local pipe = assert(io.popen("ls tools/wowsims/specs"))
        for file in pipe:lines() do
            local spec = file:match("^(.+)%.lua$")
            if spec then
                assert.is_true(exists(ex.OUT .. spec .. ".json"), spec)
                local f = assert(io.open(ex.OUT .. spec .. ".log", "rb"), spec)
                local first = f:read("*l")
                f:close()
                assert.are.equal(ex.PIN, first:match("^# wowsims (%x+) "), spec)
                assert.are.equal(spec, first:match("^# wowsims %x+ (%S+) "), spec)
            end
        end
        pipe:close()
        assert.are.equal(40, #ex.PIN)
    end)

    it("decodes a talent string in its tree file's order: { spell, rank, tree }", function()
        local trees = {
            { talents = { { spellId = 11 }, { spellId = 12 } } },
            { talents = { { spellId = 21 } } },
            { talents = { { spellId = 31 }, { spellId = 32 } } },
        }
        assert.are.same({ { 11, 2, 1 }, { 21, 1, 2 }, { 32, 3, 3 } }, ex.talents("20-1-03", trees))
        assert.are.same({ { 12, 5, 1 } }, ex.talents("05", trees))
        assert.are.same({ { 31, 1, 3 } }, ex.talents("--1", trees))
    end)

    it("builds a seeded one-iteration debug request from a recipe's player, gear and APL", function()
        local gear = tmp('{"items":[{"id":1},{}]}')
        local apl = tmp('{"type":"TypeAPL","priorityList":[]}')
        local req = ex.request({
            name = "Tester",
            apl = apl,
            player = {
                race = "RaceOrc",
                class = "ClassWarrior",
                gear = gear,
                talentsString = "1-2-3",
                specKey = "dpsWarrior",
                options = { classOptions = { startingRage = 50 } },
                profession1 = "Engineering",
                profession2 = "Blacksmithing",
                reactionTimeMs = 100,
                distanceFromTarget = 25,
            },
        }, "")
        os.remove(gear)
        os.remove(apl)
        local p = req.raid.parties[1].players[1]
        assert.are.same({ "Tester", "RaceOrc", "1-2-3", 50, 1 }, {
            p.name,
            p.race,
            p.talentsString,
            p.dpsWarrior.options.classOptions.startingRage,
            p.equipment.items[1].id,
        })
        assert.are.equal("TypeAPL", p.rotation.type)
        assert.are.same({ 1, "101", true }, {
            req.simOptions.iterations,
            req.simOptions.randomSeed,
            req.simOptions.debug,
        })
        assert.are.same({ 180, 63 }, { req.encounter.duration, req.encounter.targets[1].level })
    end)
end)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `.lua/bin/busted tests/Forever/wowsims_pin_spec.lua`
Expected: FAIL, `cannot open tools/wowsims/export.lua`.

- [ ] **Step 3: Create `tools/wowsims/export.lua`**

```lua
-- tools/wowsims/export.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 2): the
-- wowsims/forever side of the "(wowsims.com)" packs. Run from the repository root with the toolchain's Lua:
--   .lua/bin/lua tools/wowsims/export.lua export <spec>  the request tests/Forever/wowsims/<spec>.json from the recipe
--       tools/wowsims/specs/<spec>.lua and the wowsims checkout's preset files, wowsimcli run on it, and
--       tests/Forever/wowsims/<spec>.log: the debug log (noise lines dropped) under a header (the pin, the spec, the
--       seed, the duration, the target level, the build's talents). Needs the checkout at M.PIN and its CLI.
--   .lua/bin/lua tools/wowsims/export.lua learn <CLASS>  tests/Forever/wowsims/learn_<class>.lua: the DB2 learn level
--       of every rank of every ability the class kit registers (wowdb)
--   .lua/bin/lua tools/wowsims/export.lua pack <spec>    the spec's pack .simc from its checked-in request (Task 4;
--       CI-safe: no checkout needed)
-- Loaded with loadfile(...)() it returns M. Env: WOWSIMS (the checkout [~/src/wowsims-forever]), WOWSIMS_CLI
-- [$WOWSIMS/wowsimcli-amd64-linux], WOWDB [~/.local/share/wow-db2/bin/wowdb]. Credit: the request shape, the presets,
-- the talent trees and the APLs are wowsims/forever's (MIT, https://github.com/wowsims/forever); no code copied.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local json = require("dkjson")

local M = {}

--- The wowsims/forever commit every checked-in request and log comes from (tests/Forever/wowsims_pin_spec.lua).
M.PIN = "d33930d04030c3f556582f31949f1f22c17da0e4"
M.OUT = "tests/Forever/wowsims/"
M.SEED, M.DURATION, M.TARGET_LEVEL = 101, 180, 63

-- The encounter of every export (the spike's: wowsims's default target, one, 180 s, execute at 20%).
M.ENCOUNTER = {
    duration = M.DURATION,
    executeProportion20 = 0.2,
    executeProportion25 = 0.25,
    executeProportion35 = 0.35,
    executeProportion45 = 0.45,
    executeProportion90 = 0.9,
    targets = {
        {
            level = M.TARGET_LEVEL,
            -- index 15 (1-based) is attack power 320, index 28 armour 3731: wowsims's default target
            stats = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 320, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3731 },
            mobType = "MobTypeMechanical",
            swingSpeed = 2,
            minBaseDamage = 2601,
            parryHaste = true,
            canCrush = true,
            damageSpread = 0.5,
        },
    },
}

-- Log lines no reader uses (about two thirds of a log).
M.NOISE = { "No available actions", "Pausing rotation", "Dynamic stat change", "[DEBUG]" }

local function home(p)
    return (p:gsub("^~", os.getenv("HOME") or "~"))
end
local function env(name, default)
    return home(os.getenv(name) or default)
end
local function slurp(path)
    local f, err = io.open(path, "rb")
    if not f then
        error(err, 0)
    end
    local s = f:read("*a")
    f:close()
    return s
end
local function spit(path, s)
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
end
local function decode(s, where)
    local v, _, err = json.decode(s)
    if v == nil then
        error(where .. ": " .. tostring(err), 0)
    end
    return v
end
local function capture(cmd)
    local p = assert(io.popen(cmd))
    local s = p:read("*a")
    p:close()
    return s
end
local function join(root, path)
    return root == "" and path or root .. "/" .. path
end

--- The recipe of spec `spec` (tools/wowsims/specs/<spec>.lua).
function M.recipe(spec)
    return dofile("tools/wowsims/specs/" .. spec .. ".lua")
end

--- The build's talents from a wowsims talent string and the class's tree file (a list of trees, each `talents` in
--- the string's order): { { rank-1 spell ID, rank, tree }, ... } in the string's order.
function M.talents(str, trees)
    local out, t = {}, 0
    for part in (str .. "-"):gmatch("([^-]*)-") do
        t = t + 1
        local list = trees[t] and trees[t].talents or {}
        for i = 1, #part do
            local r = tonumber(part:sub(i, i))
            if r and r > 0 then
                local tal = assert(list[i], ("talent %d of tree %d"):format(i, t))
                out[#out + 1] = { tal.spellId, r, t }
            end
        end
    end
    return out
end

--- The RaidSimRequest of recipe `r`, its files read under the wowsims checkout `root` ("" : paths as given).
function M.request(r, root)
    local p
    if r.build then
        p = decode(slurp(join(root, r.build)), r.build).player
    else
        local pl = r.player
        p = {
            race = pl.race,
            class = pl.class,
            equipment = decode(slurp(join(root, pl.gear)), pl.gear),
            talentsString = pl.talentsString,
            profession1 = pl.profession1,
            profession2 = pl.profession2,
            reactionTimeMs = pl.reactionTimeMs,
            distanceFromTarget = pl.distanceFromTarget,
        }
        p[pl.specKey] = { options = pl.options }
    end
    if r.apl then
        p.rotation = decode(slurp(join(root, r.apl)), r.apl)
    end
    p.name = r.name
    return {
        raid = { parties = { { players = { p } } } },
        encounter = M.ENCOUNTER,
        simOptions = { iterations = 1, randomSeed = tostring(M.SEED), debug = true },
        type = "SimTypeIndividual",
    }
end

--- Exports spec `spec`: its request and log under M.OUT (see the header).
function M.export(spec)
    local r = M.recipe(spec)
    local root = env("WOWSIMS", "~/src/wowsims-forever")
    local head = capture("git -C '" .. root .. "' rev-parse HEAD"):gsub("%s+$", "")
    if head ~= M.PIN then
        error(("wowsims checkout at %s, the pin is %s: check out the pin (or move M.PIN and re-export every spec)")
            :format(head, M.PIN), 0)
    end
    local req = M.request(r, root)
    local reqPath = M.OUT .. spec .. ".json"
    spit(reqPath, json.encode(req, { indent = true }) .. "\n")
    local resPath = os.tmpname()
    local cli = env("WOWSIMS_CLI", root .. "/wowsimcli-amd64-linux")
    if os.execute(("'%s' sim --infile '%s' --outfile '%s'"):format(cli, reqPath, resPath)) ~= 0 then
        error("wowsimcli failed on " .. reqPath, 0)
    end
    local res = decode(slurp(resPath), resPath)
    os.remove(resPath)
    if type(res.error) == "table" and next(res.error) then
        error("wowsimcli: " .. json.encode(res.error), 0)
    end
    local trees = decode(slurp(join(root, "ui/sim/talents/trees/" .. r.talentTree .. ".json")), r.talentTree)
    local talents = {}
    for _, t in ipairs(M.talents(req.raid.parties[1].players[1].talentsString, trees)) do
        talents[#talents + 1] = ("%d=%d@%d"):format(t[1], t[2], t[3])
    end
    local out = {
        ("# wowsims %s %s seed %d %d s target %d"):format(M.PIN, spec, M.SEED, M.DURATION, M.TARGET_LEVEL),
        "# talents " .. table.concat(talents, " "),
    }
    for line in res.logs:gmatch("[^\n]+") do
        local noise = false
        for _, n in ipairs(M.NOISE) do
            noise = noise or line:find(n, 1, true) ~= nil
        end
        if not noise then
            out[#out + 1] = line
        end
    end
    spit(M.OUT .. spec .. ".log", table.concat(out, "\n") .. "\n")
    print(("%s: %d log lines, %d talents"):format(spec, #out - 2, #talents))
end

--- Every spell ID of ability `a`: its `id`, then its `copy` (a list or one ID).
function M.ids(a)
    local out = { a.id }
    if type(a.copy) == "table" then
        for _, id in ipairs(a.copy) do
            out[#out + 1] = id
        end
    elseif a.copy then
        out[#out + 1] = a.copy
    end
    return out
end

--- Writes learn_<class>.lua: the DB2 learn level (SpellLevels.BaseLevel) of every positive spell ID of every ability
--- class `token`'s kit registers. IDs the DB2 lacks are left out (the replay content treats them as level 1).
function M.learn(token)
    local kit = assert(require("Forever.helpers.engine").load(token).class.kit, "no kit for " .. token)
    local ids, seen = {}, {}
    for key, a in pairs(kit.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            for _, id in ipairs(M.ids(a)) do
                if type(id) == "number" and id > 0 and not seen[id] then
                    seen[id], ids[#ids + 1] = true, id
                end
            end
        end
    end
    table.sort(ids)
    local wowdb = env("WOWDB", "~/.local/share/wow-db2/bin/wowdb")
    local name = token:lower()
    local out = {
        ("-- tests/Forever/wowsims/learn_%s.lua: generated by `make wowsims-learn CLASS=%s` (tools/wowsims/export.lua)"):format(
            name,
            token
        ),
        "-- from the Forever DB2 (SpellLevels.BaseLevel): the level each rank of each ability is learned at.",
        "return {",
    }
    for i = 1, #ids, 150 do
        local chunk = {}
        for j = i, math.min(i + 149, #ids) do
            chunk[#chunk + 1] = ids[j]
        end
        local tsv = capture(("'%s' \"select SpellID, BaseLevel from SpellLevels where SpellID in (%s) order by SpellID\"")
            :format(wowdb, table.concat(chunk, ",")))
        for id, level in tsv:gmatch("\n(%d+)\t(%d+)") do
            if tonumber(level) > 0 then
                out[#out + 1] = ("    [%s] = %s,"):format(id, level)
            end
        end
    end
    out[#out + 1] = "}"
    spit(M.OUT .. "learn_" .. name .. ".lua", table.concat(out, "\n") .. "\n")
end

local mode, arg = ...
if mode == "export" then
    M.export(assert(arg, "usage: export <spec>"))
elseif mode == "learn" then
    M.learn(assert(arg, "usage: learn <CLASS>"))
elseif mode == "pack" then
    require("tools.wowsims.apl").write(assert(arg, "usage: pack <spec>"), M)
else
    return M
end
```
  (StyLua may rewrap the two long `:format` lines: run `stylua tools/wowsims/export.lua`.)

- [ ] **Step 4: Makefile targets.** Add after the `bench:` target:

```make
# The wowsims/forever packs (docs/superpowers/plans/2026-10-19-wowsims-packs.md). Dev-only, outside `make check`:
# wowsims-cli builds the CLI in the checkout (Go, protoc and protoc-gen-go on PATH), wowsims-export SPEC=<spec>
# exports one recipe's request and log, wowsims-learn CLASS=<TOKEN> the class's learn levels. wowsims-packs (CI-safe)
# rewrites every wowsims pack's .simc from the checked-in requests.
WOWSIMS ?= $(HOME)/src/wowsims-forever
wowsims-cli:
	cd $(WOWSIMS) && make sim/core/proto/api.pb.go && go build --tags=with_db -o wowsimcli-amd64-linux ./cmd/wowsimcli/cli_main.go

wowsims-export:
	WOWSIMS=$(WOWSIMS) $(LUA) tools/wowsims/export.lua export $(SPEC)

wowsims-learn:
	$(LUA) tools/wowsims/export.lua learn $(CLASS)

wowsims-packs:
	for r in tools/wowsims/specs/*.lua; do [ -e "$$r" ] || continue; $(LUA) tools/wowsims/export.lua pack $$(basename $$r .lua) || exit 1; done

# The wowsims replay and leveling gates (#wowsims; `make check` runs them too, in its #slow tier).
test-wowsims:
	$(BUSTED) --tags=wowsims
```
  Add `wowsims-cli wowsims-export wowsims-learn wowsims-packs test-wowsims` to `.PHONY`. Change
  `packs-check: packs` to `packs-check: wowsims-packs packs` (a hand edit of a generated `.simc`, or a recipe change
  without its regeneration, fails `make check`). Create the empty `tools/wowsims/specs/.gitkeep` and
  `tests/Forever/wowsims/.gitkeep` (the `wowsims-packs` loop skips the unmatched glob).

- [ ] **Step 5: Run the spec, a smoke export, and the gate**

Run: `.lua/bin/busted tests/Forever/wowsims_pin_spec.lua && luacheck -q tools && stylua --check tools`
Expected: PASS (`tools/wowsims/specs/` has no recipe yet: the first test checks nothing but the pin's length).
On the dev machine run `make wowsims-cli` once (the CLI the exports need); the first export is Task 5's. Gate with `TASK=2`: `gate lines identical`.

- [ ] **Step 6: Commit**

```bash
git add tools/wowsims tests/Forever/wowsims tests/Forever/wowsims_pin_spec.lua Makefile .luacheckrc
git commit -m "feat(tools): wowsims exporter (request, log, learn levels) pinned to a wowsims/forever commit

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: the replay world, one injection in loop.run, the wowsims gate helpers (L)

**Files:**
- Create: `tests/Game/harness/replay.lua`, `tests/Game/harness/replay_spec.lua`,
  `tests/Game/harness/fixtures/wowsims_test.log`, `tests/Forever/helpers/wowsims.lua`
- Modify: `tests/Game/harness/loop.lua` (`M.run`, `M.tally`, `M.summary`, `M.line`, new `M.replay`),
  `tests/Game/harness/loop_spec.lua`

**Interfaces:**
- Consumes: Task 2's log header.
- Produces (`replay.lua`): `replay.parse(text) -> { header = { pin, spec, seed, duration, targetLevel, talents = {
  { id, rank, tree } } }, ev = { ... } }`; `replay.new(text, H, o) -> R` with `R.pull` (5), `R.duration`,
  `R.targetLevel`, `R.header`, `R.speed`, `R.decisions` (`{ t, key, gcd }` in world time, sorted), `R.casts`,
  `R.world(wo, seed) -> W`, `R.next(t) -> key|false`. `o = { forms = { spellID, ... } (index = the client's form),
  hidden = { [auraID] = true }, procs = { [spellID] = true }, speed = seconds, regen, fsr }`.
- Produces (`loop.lua`): `loop.run`'s `o.replay = R` (presses off, R's world, R.next as `theirs`, a cycle at each
  decision, `run.dec = { ours = {}, theirs = {} }`); `loop.replay(L, R, o) -> m` (a tally; `m.dec = { both, agree,
  conf }`); `loop.summary(m).decisions` (nil without `m.dec`); `loop.line(m)` appends
  `; decisions on-GCD %.3f (%d) top [...]` only when `m.dec` is set (every existing line is unchanged).
- Produces (`tests/Forever/helpers/wowsims.lua`): `ws.header(spec) -> header`, `ws.log(spec) -> text`,
  `ws.learn(token) -> { [spellID] = level }`, `ws.content(base, o) -> content`, `ws.gate(label, C, spec, floor, o)
  -> r, line`, `ws.live(label, C, limit, fights) -> worstSeconds, line`. `ws.content`'s `o = { pack, level [60],
  talents (header.talents), kit = { key, ... }, requires = { [key] = fn(W, e) -> ok, why }, learn }`.

- [ ] **Step 1: The fixture** `tests/Game/harness/fixtures/wowsims_test.log` (invented IDs; the boundary skips
  `fixtures/`):

```
# wowsims 0123456789abcdef0123456789abcdef01234567 test_spec seed 101 10 s target 63
# talents 900100=2@2 900101=1@1 900102=3@2
[0.00] [Tester (#1)] Aura gained: {SpellID: 900011}
[-2.00] [Tester (#1)] Casting {SpellID: 900010} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)
[-2.00] [Tester (#1)] Completed cast {SpellID: 900010}
[-2.00] [Tester (#1)] Spent 10.000 rage from {SpellID: 900010} (50.000 --> 40.000) of 100 total.
[-1.99] [Tester (#1)] Aura faded: {SpellID: 900011}
[-1.99] [Tester (#1)] Aura gained: {SpellID: 900010}
[-1.00] [Tester (#1)] Casting {SpellID: 900002} (Cost = 10.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)
[-1.00] [Tester (#1)] Completed cast {SpellID: 900002}
[-1.00] [Tester (#1)] Spent 10.000 rage from {SpellID: 900002} (40.000 --> 30.000) of 100 total.
[-1.00] [Tester (#1)] Aura gained: {SpellID: 900002}
[0.10] [Tester (#1)] Completed cast {OtherID: 3, Tag: 1}
[0.10] [Tester (#1)] [Target 1] {OtherID: 3, Tag: 1} Hit for 100.000 damage (SpellSchool: 1). (Threat: 100.000)
[0.10] [Tester (#1)] Gained 12.000 rage from {OtherID: 3, Tag: 1} (30.000 --> 42.000) of 100 total.
[0.10] [Tester (#1)] Casting {SpellID: 900001} (Cost = 20.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)
[0.10] [Tester (#1)] Completed cast {SpellID: 900001}
[0.10] [Tester (#1)] Spent 20.000 rage from {SpellID: 900001} (42.000 --> 22.000) of 100 total.
[0.10] [Tester (#1)] [Target 1] {SpellID: 900001} Crit for 300.000 damage (SpellSchool: 1). (Threat: 300.000)
[0.10] [Tester (#1)] Casting {SpellID: 900004} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)
[0.10] [Tester (#1)] Completed cast {SpellID: 900004}
[0.10] [Target 1] Aura gained: {SpellID: 900030}
[0.10] [Target 1] {SpellID: 900030} stacks: 0 --> 1
[1.00] [Tester (#1)] Casting {SpellID: 900003} (Cost = 0.000, Cast Time = 0s, GCD = 0s, Effective Time = 0s)
[1.00] [Tester (#1)] Completed cast {SpellID: 900003}
[1.00] [Tester (#1)] Gained 10.000 rage from {SpellID: 900003} (22.000 --> 32.000) of 100 total.
[1.00] [Tester (#1)] Aura gained: {SpellID: 900020}
[3.90] [Tester (#1)] Completed cast {OtherID: 3, Tag: 1}
[3.90] [Tester (#1)] [Target 1] {OtherID: 3, Tag: 1} Dodge
[3.90] [Tester (#1)] Aura faded: {SpellID: 900020}
[4.00] [Target 1] {SpellID: 900030} stacks: 1 --> 2
[6.00] [Tester (#1)] [Target 1] {SpellID: 900030} tick Hit for 20.000 damage (SpellSchool: 1). (Threat: 20.000)
[8.10] [Tester (#1)] Casting {SpellID: 900001} (Cost = 20.000, Cast Time = 0s, GCD = 1.5s, Effective Time = 1.5s)
[8.10] [Tester (#1)] Completed cast {SpellID: 900001}
[10.10] [Target 1] Aura faded: {SpellID: 900030}
```

- [ ] **Step 2: Write the failing spec** `tests/Game/harness/replay_spec.lua`:

```lua
-- tests/Game/harness/replay_spec.lua (wowsims packs plan, Task 3): the wowsims log parser and the log-driven world on
-- the 30-line fixture (fixtures/wowsims_test.log, invented IDs), each of the plan's Review Focus lies pinned. The class
-- data is a stand-in H (replay.new reads only H.Hekili.Class).
local replay = require("Game.harness.replay")

local function text()
    local f = assert(io.open("tests/Game/harness/fixtures/wowsims_test.log", "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

-- The stand-in class data: ability keys by rank IDs, aura durations.
local H = {
    Hekili = {
        Class = {
            abilities = {
                strike = { key = "strike", id = 900001, cooldown = 6, gcd = "spell" },
                shout = { key = "shout", id = 900002, gcd = "spell" },
                surge = { key = "surge", id = 900003, cooldown = 30, gcd = "off" },
                echo = { key = "echo", id = 900004, gcd = "off" },
                stance_a = { key = "stance_a", id = 900010, gcd = "off" },
                stance_b = { key = "stance_b", id = 900011, gcd = "off" },
            },
            auras = {
                shout = { id = 900002, duration = 120 },
                mark = { id = 900030, duration = 12, max_stack = 5 },
                window = { id = 900020, duration = 5 },
            },
        },
    },
}
local O = { forms = { 900010, 900011 }, hidden = { [900020] = true }, procs = { [900004] = true } }
local WO = { level = 60, max = 100, pt = 1, weapons = { { 100, 150, 3.6 } } }

local function at(W, t) -- the world run to world time `t`
    W.run(t)
    return W
end

describe("the wowsims log parser", function()
    local p = replay.parse(text())

    it("reads the header: pin, spec, seed, duration, target level, talents with their trees", function()
        local h = p.header
        assert.are.same(
            { "0123456789abcdef0123456789abcdef01234567", "test_spec", 101, 10, 63 },
            { h.pin, h.spec, h.seed, h.duration, h.targetLevel }
        )
        assert.are.same({ { 900100, 2, 2 }, { 900101, 1, 1 }, { 900102, 3, 2 } }, h.talents)
    end)

    it("reads casts with their cast time and GCD, powers, auras, stacks and outcomes", function()
        local kinds = {}
        for _, e in ipairs(p.ev) do
            kinds[e.kind] = (kinds[e.kind] or 0) + 1
        end
        assert.are.same({ casting = 6, completed = 8, power = 5, aura = 8, stacks = 2, hit = 4 }, kinds)
        local c = p.ev[2]
        assert.are.same({ "casting", -2, 900010, 0, 0 }, { c.kind, c.t, c.id, c.cast, c.gcd })
        local hit = p.ev[12]
        assert.are.same({ "hit", "swing", 1, "WOUND", "", 100 }, { hit.kind, hit.what, hit.hand, hit.act, hit.flag, hit.amount })
        local tick
        for _, e in ipairs(p.ev) do
            if e.kind == "hit" and e.what == "tick" then
                tick = e
            end
        end
        assert.are.same({ 900030, 20 }, { tick.id, tick.amount })
    end)
end)

describe("the replay world", function()
    it("maps casts to keys and decisions: on-GCD flagged, procs neither decisions nor casts", function()
        local R = replay.new(text(), H, O)
        local keys, gcd = {}, {}
        for i, d in ipairs(R.decisions) do
            keys[i], gcd[i] = d.key, d.gcd
        end
        assert.are.same({ "stance_a", "shout", "strike", "surge", "strike" }, keys)
        assert.are.same({ false, true, true, false, true }, gcd)
        -- each decision just before its Casting line (log time + pull), after the earlier lines of its timestamp
        assert.is_true(R.decisions[3].t > R.pull + 0.1 and R.decisions[3].t < R.pull + 0.1 + 1e-4)
        assert.are.equal("surge", R.next(R.pull + 0.2))
        assert.are.equal("strike", R.next(R.pull + 1.5))
        assert.is_false(R.next(R.pull + 9))
        assert.are.equal(3.8, R.speed) -- the first two main-hand swings
    end)

    it("procs: a mapped proc emits no cast", function()
        local R = replay.new(text(), H, O)
        local W = at(R.world(setmetatable({ tag = "-p" }, { __index = WO }), 1), R.pull + 0.2)
        for _, ev in ipairs(W.truth) do
            assert.is_false(ev.kind == "cast" and ev.spell == 900004)
        end
    end)

    it("power: the truth is each logged after-value, the start the first line's before-value, no regen ticks", function()
        local R = replay.new(text(), H, O)
        local W = R.world(setmetatable({ tag = "-w", regen = { [1] = 0.5 } }, { __index = WO }), 1)
        local us = W.ents[1]
        assert.are.equal(50, us.power)
        at(W, R.pull - 1.5)
        assert.are.equal(40, us.power)
        at(W, R.pull + 0.5)
        assert.are.equal(22, us.power)
        at(W, R.pull + 2)
        assert.are.equal(32, us.power)
        assert.are.equal(0.5, W.rates[1]) -- the client reads the content's rate
        for _, ev in ipairs(W.truth) do
            assert.are_not.equal("regen", ev.kind)
        end
    end)

    it("auras: forms from the stance auras; a hidden aura in the truth only; a fade's real duration", function()
        local R = replay.new(text(), H, O)
        local W = R.world(setmetatable({ tag = "-a" }, { __index = WO }), 1)
        local us, mob = W.ents[1], W.ents[2]
        at(W, 0.05)
        assert.are.equal(2, us.form) -- the log's opening aura: the second form
        at(W, R.pull - 1.5)
        assert.are.equal(1, us.form)
        at(W, R.pull + 2)
        assert.is_not_nil(us.auras[900020]) -- hidden: in the truth
        for _, ev in ipairs(W.truth) do
            assert.is_false(ev.kind == "aura" and ev.aura == 900020)
        end
        at(W, R.pull + 4.1)
        assert.is_nil(us.auras[900020])
        local mark = mob.auras[900030]
        assert.are.equal(2, mark.stacks)
        local function near(x, y)
            return math.abs(x - y) < 1e-4
        end
        assert.is_true(near(R.pull + 10.1, mark.expires)) -- faded at 10.10: 10 s, not the class's 12
        assert.is_true(near(R.pull - 1 + 120, us.auras[900002].expires)) -- never faded: the class's duration
        assert.is_not_nil(us.avoidAt.DODGE)
    end)

    it("execute: the mob is above 20% before pull + 0.8 x duration and at or under it from then, never dead", function()
        local R = replay.new(text(), H, O)
        local W = R.world(setmetatable({ tag = "-e" }, { __index = WO }), 1)
        local mob = W.ents[2]
        at(W, R.pull + 0.8 * R.duration - 0.01)
        assert.is_true(mob.health > 0.2 * mob.healthMax)
        at(W, R.pull + 0.8 * R.duration)
        assert.is_true(mob.health <= 0.2 * mob.healthMax)
        at(W, R.pull + R.duration)
        assert.is_true(mob.health > 0 and not mob.dead)
        assert.are.equal(R.pull + R.duration, W.stopAt)
    end)
end)
```
  Count check for the kinds table: `casting` 6 (900010, 900002, 900001, 900004, 900003, 900001), `completed` 8 (those 6
  plus two swings), `power` 5, `aura` 8 (four gained on us incl. the opening one, two faded on us, one gained and one
  faded on the target), `stacks` 2, `hit` 4 (two swings, one strike, one tick). If an implementer's count differs,
  re-count the fixture by hand before changing the parser.

  Append to `tests/Game/harness/loop_spec.lua` (inside the file, after the existing `describe`):

```lua
describe("the headless loop's replay injection (o.replay)", function()
    local scenarios = require("Game.harness.scenarios")
    it("presses nothing, cycles at each decision and scores only the on-GCD ones", function()
        local stub = {
            character = function()
                return { level = 60, power = { type = 1, token = "RAGE", max = 100 } }
            end,
            resolve = function()
                error("no press in a replay")
            end,
            usable = function()
                return {}
            end,
            uptime = function()
                return {}
            end,
            gain = function()
                return 0
            end,
            WORLD = { level = 60, max = 100, mobHealth = 1e9 },
        }
        local L = loop.new(stub)
        local R = {
            pull = 3,
            duration = 6,
            decisions = {
                { t = 3.3, key = "a", gcd = true },
                { t = 3.5, key = "b", gcd = false },
                { t = 4.1, key = "c", gcd = true },
            },
        }
        function R.world(wo, seed)
            return scenarios.world(wo, seed)
        end
        function R.next(t)
            for _, d in ipairs(R.decisions) do
                if d.t > t then
                    return d.key
                end
            end
            return false
        end
        local m = loop.replay(L, R)
        assert.are.same({ 2, 0 }, { m.dec.both, m.dec.agree }) -- no pack: our on-GCD icon is false at both
        assert.are.equal(0, m.attempts)
        local r = loop.summary(m)
        assert.are.equal(0, r.decisions)
        assert.is_truthy(loop.line(m):find("; decisions on-GCD 0.000 (2)", 1, true))
        assert.is_nil(loop.summary(loop.tally(L, 1, { duration = 6 })).decisions) -- the normal tally: unchanged
    end)
end)
```
  (`m.dec.both` counts on-GCD decisions with a truthy key; ours false and theirs "a"/"c" still count: the tally of
  decisions counts every on-GCD decision, `agree` where ours equals theirs. See Step 4.)

- [ ] **Step 3: Run them to verify they fail**

Run: `.lua/bin/busted tests/Game/harness/replay_spec.lua tests/Game/harness/loop_spec.lua`
Expected: FAIL (`module 'Game.harness.replay' not found`; `loop.replay` nil).

- [ ] **Step 4: Create `tests/Game/harness/replay.lua`**

```lua
-- tests/Game/harness/replay.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 3): a
-- wowsims/forever debug log (tools/wowsims/export.lua) as the headless loop's world. `parse` reads the log;
-- `new` binds it to a booted instance's class data (spell ID -> ability key, aura durations) and gives loop.run its one
-- injection (`o.replay`): the world factory, wowsims's decisions and its next cast after a tick. The truth is the
-- log's: casts at their completion (no cast bars), powers as the logged after-values (no regen ticks; the client
-- still reads the content's rate), our auras and the target's with the log's real duration when they fade, the
-- content's hidden auras in the truth only, swings and spells landing at once, the mob's health at 20% from the
-- execute phase's start (wowsims's is the last 20% of the duration) and never dead. Not replayed: cast bars, landing
-- lag, the target's swings. Class-neutral: the content passes its forms, hidden auras and procs. Credit: the log
-- format is wowsims/forever's (MIT, https://github.com/wowsims/forever); no code copied.
local world = require("Game.harness.world")
local entities = require("Game.harness.entities")

local M = {}

M.PULL = 5 -- world time of the log's 0 (its prepull starts at -4.5)
M.EPS = 1e-6 -- a line's place within its timestamp, as time: a decision falls just before its Casting line
M.EXECUTE = 0.2 -- the exporter's execute proportion

-- wowsims's resource names and the client's power types (Enum.PowerType); other names (health) are not powers.
M.POWER = { mana = 0, rage = 1, focus = 2, energy = 3, ["combo points"] = 4 }

-- wowsims's outcome words and the world's { act, flag }.
local OUTCOME = {
    Hit = { "WOUND", "" },
    Crit = { "WOUND", "CRITICAL" },
    Glance = { "WOUND", "GLANCING" },
    Block = { "WOUND", "" },
    CritBlock = { "WOUND", "CRITICAL" },
    Miss = { "MISS", "" },
    Dodge = { "DODGE", "" },
    Parry = { "PARRY", "" },
}

local function secs(s) -- "1.5s", "250ms", "0s" -> seconds
    local v, m = s:match("^([%d.]+)(m?)s$")
    return v and tonumber(v) / (m == "m" and 1000 or 1) or 0
end
local function ids(s) -- "SpellID: 1, Tag: 2" -> 1, nil, 2; "OtherID: 3, Tag: 1" -> nil, 3, 1
    return tonumber(s:match("SpellID: (%d+)")), tonumber(s:match("OtherID: (%d+)")), tonumber(s:match("Tag: (%-?%d+)"))
end

-- One line of our character's (`rest`, after its "[Name (#1)] ") as an event, or nil.
local function ours(rest)
    local b, cast, gcd = rest:match("^Casting {([^}]*)} %(.-Cast Time = (%S+), GCD = (%S+),")
    if b then
        local id = ids(b)
        return id and { kind = "casting", id = id, cast = secs(cast), gcd = secs(gcd) }
    end
    b = rest:match("^Completed cast {([^}]*)}")
    if b then
        local id, other, tag = ids(b)
        return { kind = "completed", id = id, other = other, tag = tag }
    end
    local name, from, to = rest:match("^%a+ [%d.]+ ([%a ]-) from {[^}]*} %(([%d.]+) %-%-> ([%d.]+)%)")
    if name then
        return { kind = "power", name = name, from = tonumber(from), to = tonumber(to) }
    end
    local verb
    verb, b = rest:match("^Aura (%a+): {([^}]*)}")
    if verb then
        local id = ids(b) -- an OtherID aura (a pre-pull move) is not a spell's
        return id and { kind = "aura", unit = "player", verb = verb, id = id }
    end
    local n
    b, n = rest:match("^{([^}]*)} stacks: %d+ %-%-> (%d+)")
    if b then
        local id = ids(b)
        return id and { kind = "stacks", unit = "player", id = id, to = tonumber(n) }
    end
    local word, tail
    b, word, tail = rest:match("^%[Target 1%] {([^}]*)} tick (%a+)(.*)$")
    local what = b and "tick"
    if not b then
        b, word, tail = rest:match("^%[Target 1%] {([^}]*)} (%a+)(.*)$")
    end
    if b then
        local id, other, tag = ids(b)
        local amount = tonumber(tail:match("for ([%d.]+) damage") or 0)
        local o = OUTCOME[word] or (amount > 0 and OUTCOME.Hit)
        if o then
            what = what or (other == 3 and "swing" or "spell")
            return {
                kind = "hit",
                what = what,
                hand = tag == 2 and 2 or 1,
                id = id,
                act = o[1],
                flag = o[2],
                amount = amount,
            }
        end
    end
end

-- A target line (`rest`, after "[Target 1] ") as an event, or nil.
local function theirs(rest)
    local verb, b = rest:match("^Aura (%a+): {([^}]*)}")
    if verb then
        local id = ids(b) -- an OtherID aura (a pre-pull move) is not a spell's
        return id and { kind = "aura", unit = "target", verb = verb, id = id }
    end
    local n
    b, n = rest:match("^{([^}]*)} stacks: %d+ %-%-> (%d+)")
    if b then
        local id = ids(b)
        return id and { kind = "stacks", unit = "target", id = id, to = tonumber(n) }
    end
end

--- The events of a log's text: { header = { pin, spec, seed, duration, targetLevel, talents = { { id, rank, tree } }
--- }, ev = { { t, kind, ... } } } in line order. Kinds: casting { id, cast, gcd }, completed { id, other, tag },
--- power { name, from, to }, aura { unit ("player" | "target"), verb ("gained" | "faded" | "refreshed"), id }, stacks
--- { unit, id, to }, hit { what ("swing" | "spell" | "tick"), hand, id, act, flag, amount }. Other lines are skipped.
--- The leading aura and stack lines at 0 before any other event are the sim's opening state (`initial`).
function M.parse(text)
    local h, ev = { talents = {} }, {}
    local opening = true
    for line in text:gmatch("[^\n]+") do
        if line:sub(1, 1) == "#" then
            local pin, spec, seed, dur, lvl = line:match("^# wowsims (%x+) (%S+) seed (%d+) (%d+) s target (%d+)")
            if pin then
                h.pin, h.spec, h.seed, h.duration, h.targetLevel =
                    pin, spec, tonumber(seed), tonumber(dur), tonumber(lvl)
            end
            local list = line:match("^# talents (.*)$")
            for id, rank, tree in (list or ""):gmatch("(%d+)=(%d+)@(%d+)") do
                h.talents[#h.talents + 1] = { tonumber(id), tonumber(rank), tonumber(tree) }
            end
        else
            local t, who, rest = line:match("^%[(%-?[%d.]+)%] %[([^%]]+)%] (.*)$")
            t = tonumber(t)
            local e
            if t and who:find(" (#1)", 1, true) then
                e = ours(rest)
            elseif t and who == "Target 1" then
                e = theirs(rest)
            end
            if e then
                e.t = t
                opening = opening and t == 0 and (e.kind == "aura" or e.kind == "stacks")
                e.initial = opening or nil
                ev[#ev + 1] = e
            end
        end
    end
    return { header = h, ev = ev }
end

--- A replay of log `text` bound to booted instance `H`'s class data (abilities by `key`, `id`, `copy`, `cooldown`;
--- auras by `id`, `copy`, `duration`). `o`: forms ({ spellID, ... }: the client's form index of each form's spell and
--- aura), hidden ({ [auraID] = true }: in the truth, never shown to the client), procs ({ [spellID] = true }: neither a
--- decision nor a cast), speed (the main hand's period; default the log's first two main-hand swings), regen and fsr
--- (the rates the client reads: W.rates, W.fsr; no regen ticks).
function M.new(text, H, o)
    o = o or {}
    local p = M.parse(text)
    local h = p.header
    local R = { header = h, pull = M.PULL, duration = h.duration or 180, targetLevel = h.targetLevel }
    local class = H.Hekili.Class
    -- spell ID -> ability key (every rank), the key's IDs and cooldown; aura ID -> duration
    local keyOf, rankIDs, cd, dur, form = {}, {}, {}, {}, {}
    local keys = {}
    for key, a in pairs(class.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local a = class.abilities[key]
        local list = { a.id }
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            list[#list + 1] = id
        end
        rankIDs[key], cd[key] = {}, tonumber(a.cooldown) or 0
        for _, id in ipairs(list) do
            if type(id) == "number" then
                keyOf[id] = keyOf[id] or key
                table.insert(rankIDs[key], id)
            end
        end
    end
    for _, a in pairs(class.auras) do
        if type(a) == "table" and type(a.id) == "number" and type(a.duration) == "number" then
            dur[a.id] = dur[a.id] or a.duration
            for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                if type(id) == "number" then
                    dur[id] = dur[id] or a.duration
                end
            end
        end
    end
    for i, id in ipairs(o.forms or {}) do
        form[id] = i
    end
    local hidden, procs = o.hidden or {}, o.procs or {}
    -- world times: log time + pull, each line after the earlier ones of its timestamp; the opening state at 0
    local seq = {}
    for _, e in ipairs(p.ev) do
        local n = (seq[e.t] or 0) + 1
        seq[e.t] = n
        e.wt = e.initial and 0 or R.pull + e.t + n * M.EPS
    end
    -- each aura application's real duration when its next line is its fade
    local nextOf = {}
    for i = #p.ev, 1, -1 do
        local e = p.ev[i]
        if e.kind == "aura" then
            local k = e.unit .. ":" .. e.id
            local nx = nextOf[k]
            if e.verb ~= "faded" and nx and nx.verb == "faded" then
                e.d = nx.wt - e.wt
            end
            nextOf[k] = e
        end
    end
    -- wowsims's casts (procs out): the decisions just before their Casting lines, sorted
    R.decisions, R.casts = {}, {}
    for _, e in ipairs(p.ev) do
        if e.kind == "casting" and keyOf[e.id] and not procs[e.id] then
            local d = { t = e.wt - M.EPS / 2, key = keyOf[e.id], gcd = e.cast > 0 or e.gcd > 0 }
            R.decisions[#R.decisions + 1], R.casts[#R.casts + 1] = d, d
        end
    end
    table.sort(R.decisions, function(x, y)
        return x.t < y.t
    end)
    -- the main hand's period: the first two main-hand swings
    local last
    for _, e in ipairs(p.ev) do
        if e.kind == "hit" and e.what == "swing" and e.hand == 1 then
            if last then
                R.speed = R.speed or (math.floor((e.t - last) * 1000 + 0.5) / 1000)
                break
            end
            last = e.t
        end
    end
    R.speed = o.speed or R.speed
    -- the mob: health crosses 20% exactly at the execute phase's start (the damage before it is 80%)
    local before, start = 0, R.pull + (1 - M.EXECUTE) * R.duration
    for _, e in ipairs(p.ev) do
        if e.kind == "hit" and e.wt < start then
            before = before + e.amount
        end
    end
    R.mobHealth = math.floor(before / (1 - M.EXECUTE)) + 1
    -- the starting powers: each power's first line's before-value
    local start0 = {}
    for _, e in ipairs(p.ev) do
        local pt = e.kind == "power" and M.POWER[e.name]
        if pt and start0[pt] == nil then
            start0[pt] = e.from
        end
    end

    local ci = 1
    --- wowsims's next cast strictly after world time `t` (its key), or false; `t` only grows within a world.
    function R.next(t)
        while R.casts[ci] and R.casts[ci].t <= t do
            ci = ci + 1
        end
        return R.casts[ci] and R.casts[ci].key or false
    end

    --- The world of the log (loop.run's factory: `wo` the loop's knobs, `seed` the world's generator).
    function R.world(wo, seed)
        ci = 1
        local W = world.new(seed)
        local w = wo.weapons and wo.weapons[1] or { 1, 2, R.speed or 2 }
        local us = W.add(entities.new({
            guid = "Player-1",
            level = wo.level,
            weapons = { { w[1], w[2], R.speed or w[3] } },
            powerMax = wo.max,
            pt = wo.pt,
            res = wo.res,
        }))
        us.power = start0[us.pt] or wo.power or 0
        us.power0 = us.power
        for pt, r in pairs(us.res) do
            if start0[pt] then
                r.cur, us.res0[pt] = start0[pt], start0[pt]
            end
        end
        us.lastSwing, us.landAt = { 0, 0 }, { 0, 0 }
        local mob = W.add(entities.new({
            guid = "Creature-1" .. (wo.tag or ""),
            kind = "mob",
            level = R.targetLevel or wo.level,
            health = R.mobHealth,
        }))
        mob.target, us.target = us, mob
        local env = W.add(entities.new({ guid = "Other-replay", level = wo.level })) -- the execute phase's source
        for pt, rate in pairs(wo.regen or {}) do -- the client's rate reads only: the log's after-values are the truth
            W.rates[pt] = rate
        end
        for pt, f in pairs(wo.fsr or {}) do
            W.fsr[pt] = f
        end
        local function show(dst, id, a) -- an aura change the client sees (not a hidden one)
            if not hidden[id] then
                W.emit({
                    kind = "aura",
                    dst = dst,
                    aura = id,
                    stacks = a and a.stacks or 0,
                    expires = a and a.expires or 0,
                    duration = a and a.duration or 0,
                })
            end
        end
        local function apply(e)
            local T = W.t
            if e.kind == "completed" and e.id and keyOf[e.id] and not procs[e.id] then
                local key = keyOf[e.id]
                W.emit({
                    kind = "cast",
                    src = us,
                    dst = mob,
                    spell = e.id,
                    ids = rankIDs[key],
                    cd = cd[key],
                    gcd = (e.cast or 0) == 0 and (e.gcd or 0) > 0 and e.gcd or nil,
                    order = 1,
                })
                if cd[key] > 0 then
                    us.cdUntil[key] = T + cd[key]
                end
            elseif e.kind == "power" then
                local pt = M.POWER[e.name]
                if pt and (pt == us.pt or us.res[pt]) then
                    local delta = e.to - W.res(us, pt)
                    if delta ~= 0 then
                        W.emit({
                            kind = "gain",
                            src = us,
                            pt = pt ~= us.pt and pt or nil,
                            rage = delta > 0 and delta or nil,
                            cost = delta < 0 and -delta or nil,
                        })
                    end
                end
            elseif e.kind == "aura" and form[e.id] and e.unit == "player" then
                if e.verb ~= "faded" then
                    W.setForm(us, form[e.id])
                elseif us.form == form[e.id] then
                    W.setForm(us, 0)
                end
            elseif e.kind == "aura" and (dur[e.id] or hidden[e.id]) then
                local dst = e.unit == "target" and mob or us
                if e.verb == "faded" then
                    dst.auras[e.id] = nil
                    show(dst, e.id, nil)
                else
                    local d = e.d or dur[e.id] or 3600
                    local cur = dst.auras[e.id]
                    local a = { stacks = cur and cur.stacks or 1, expires = T + d, duration = d }
                    dst.auras[e.id] = a
                    show(dst, e.id, a)
                end
            elseif e.kind == "stacks" and e.to > 0 then
                local dst = e.unit == "target" and mob or us
                local a = dst.auras[e.id]
                if a then
                    a.stacks = e.to
                    show(dst, e.id, a)
                end
            elseif e.kind == "hit" then
                local amount = math.min(e.amount, math.max(0, mob.health - 1)) -- the mob never dies
                if e.act ~= "WOUND" then
                    us.avoidAt[e.act] = T
                end
                if e.what == "swing" then
                    us.lastSwing[e.hand] = T
                    local sw = W.emit({
                        kind = "swing",
                        src = us,
                        dst = mob,
                        hand = e.hand,
                        act = e.act,
                        flag = e.flag,
                        amount = amount,
                        school = 1,
                        speed = R.speed,
                        ours = true,
                    })
                    W.emit({
                        kind = "land",
                        src = us,
                        dst = mob,
                        hand = e.hand,
                        act = e.act,
                        flag = e.flag,
                        amount = amount,
                        school = 1,
                        swing = sw,
                    })
                else
                    W.emit({
                        kind = e.what,
                        src = us,
                        dst = mob,
                        act = e.act,
                        flag = e.flag,
                        amount = amount,
                        school = 1,
                    })
                end
            end
        end
        -- a Completed line carries its Casting line's cast time and GCD
        local lastCast = {}
        for _, e in ipairs(p.ev) do
            if e.kind == "casting" then
                lastCast[e.id] = e
            elseif e.kind == "completed" and e.id and lastCast[e.id] then
                e.cast, e.gcd = lastCast[e.id].cast, lastCast[e.id].gcd
            end
            W.at(e.wt, function()
                apply(e)
            end)
        end
        W.at(0.1, function() -- out of combat: the caches and the target (after the opening state at 0)
            W.emit({ kind = "prepull" })
        end)
        W.at(R.pull, function()
            W.emit({ kind = "pull" })
        end)
        W.at(start, function() -- the execute phase: the mob at 20% (another source's wound, not ours)
            local floor20 = math.floor(M.EXECUTE * mob.healthMax)
            if mob.health > floor20 then
                W.emit({
                    kind = "spell",
                    src = env,
                    dst = mob,
                    act = "WOUND",
                    flag = "",
                    amount = mob.health - floor20,
                    school = 1,
                })
            end
        end)
        W.at(R.pull + R.duration, function()
            for _, e in ipairs(W.ents) do
                e.stopped = true
            end
            W.emit({ kind = "stop" })
        end)
        W.stopAt, W.after = R.pull + R.duration, 0
        return W
    end

    return R
end

return M
```
  Note: the prepull at world 0.1 must come after the opening state (world 0) and before the log's first prepull
  line (pull - 4.5 = 0.5). A log whose prepull starts earlier than -4.9 s needs `M.PULL` raised; assert it in
  `M.new`: add `assert(p.ev[1] == nil or ... )` as `for _, e in ipairs(p.ev) do assert(e.initial or e.t > 0.1 - M.PULL,
  "the log starts before the replay's prepull: raise replay.PULL") end` right after the world-time loop.

- [ ] **Step 5: The injection in `tests/Game/harness/loop.lua`.**
  - Below `queue`, add:

```lua
-- The first on-GCD name of an instance's Primary queue (false: none): the replay's decision-point pick.
local function firstGcd(H)
    local out, abilities = H.Hekili.Engine.Output.Primary, H.Hekili.Class.abilities
    for i = 1, out.count do
        local a = abilities[out.recs[i].actionName]
        if a and a.gcd ~= "off" then
            return out.recs[i].actionName
        end
    end
    return false
end
```
  - In `M.run`'s doc comment add: `o.replay` (replay.lua's R: its world, no presses, wowsims's next cast as `theirs`,
    a cycle just before each decision; `run.dec` { ours, theirs }: our first on-GCD icon and wowsims's on-GCD cast).
  - Replace `local W = scenarios.world(wo, seed)` with:

```lua
    local R = o.replay -- a wowsims log's world (replay.lua): no presses, its casts as `theirs`
    if R then
        wo.pull, wo.duration, wo.targetLevel = R.pull, R.duration, R.targetLevel or wo.targetLevel
    end
    local W = R and R.world(wo, seed) or scenarios.world(wo, seed)
```
  - After `run.ours, run.theirs, run.gap, run.cpu, run.secrets, run.focus = ...` add
    `run.dec = R and { ours = {}, theirs = {} } or nil`.
  - Replace the head of the `while t < stopAt and not W.killAt do` body, from `t = t + tick` through the end of the
    `for i, st in ipairs(steps) do ... queue(st.H, st.q, 3) end` block, with a local `step` (defined just before the
    `while`) and the decision cycles:

```lua
    local function step(tc) -- the world to `tc`, every instance fed and cycled
        W.run(tc)
        for i, st in ipairs(steps) do
            feed(st.H, st.obs, tc, st.base, sink)
            st.H.Hekili.ActiveDebug = o.trace or false
            local c0 = os.clock()
            local ok = headless.cycle(st.H, st.base + tc)
            if i == 1 then
                run.cpu[#run.cpu + 1] = (os.clock() - c0) * 1000
            end
            st.H.Hekili.ActiveDebug = false
            if not ok then
                run.raises = run.raises + 1
            end
            queue(st.H, st.q, 3)
        end
    end
    local di = 1
    while t < stopAt and not W.killAt do
        -- wowsims's decisions before this tick (replay): a cycle just before each cast; the on-GCD ones scored
        -- against our first on-GCD icon (an off-GCD cast would agree with whatever shows during a GCD)
        while R and R.decisions[di] and R.decisions[di].t < t + tick do
            local d = R.decisions[di]
            di = di + 1
            if d.t > t then
                step(d.t)
                if d.gcd then
                    local n = #run.dec.ours + 1
                    run.dec.ours[n], run.dec.theirs[n] = firstGcd(steps[1].H), d.key
                end
            end
        end
        t = t + tick
        step(t)
```
    (the rest of the body, from `run.ticks = run.ticks + 1`, is unchanged.)
  - Presses off: change `local shown = key and q.time[1] <= (o.react or M.REACT)` to
    `local shown = not R and key and q.time[1] <= (o.react or M.REACT)`.
  - `theirs`: change `run.theirs[n] = steps[2] and steps[2].q.name[1] or false` to

```lua
            if R then
                run.theirs[n] = R.next(t)
            else
                run.theirs[n] = steps[2] and steps[2].q.name[1] or false
            end
```
  - In `M.tally`, move the tally's initial table into a local `blank()` (above `M.tally`) and call it:

```lua
-- An empty tally (M.tally's and M.replay's).
local function blank()
    local m = { fights = 0, both = 0, agree = 0, conf = {}, react = {}, refused = {}, attempts = 0, episodes = 0 }
    m.refusedB, m.attemptsB = {}, 0 -- the oracle's own, driving run B (the projection's share: §5.2 as built)
    m.A = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
    m.B = { combat = 0, full = 0, idle = 0, up = {}, damage = 0, time = 0, flicker = 0 }
    m.oracleFlicker, m.errors, m.raises, m.misses, m.secrets, m.selfCheck = 0, 0, 0, {}, {}, 0
    m.cpu, m.gap, m.focus = {}, {}, 0
    return m
end
```
    and in `M.tally` replace those lines with `local m = blank()`.
  - Add after `M.tally`:

```lua
--- One replay of wowsims log `R` (replay.lua) on `L`'s boot: ours alone on the log's world, no presses, wowsims's
--- next cast as `theirs` each tick. A tally for summary and line: the per-tick agreement with wowsims's next cast
--- (reported) and `dec` { both, agree, conf } (our first on-GCD icon just before each on-GCD cast of wowsims's).
function M.replay(L, R, o)
    local a = M.run(L, 1, setmetatable({ replay = R, trace = false }, { __index = o or {} }), { { H = L.us } })
    local m = blank()
    m.fights = 1
    for i = 1, a.combat do
        local x, y = a.ours[i], a.theirs[i]
        if x and y then
            m.both = m.both + 1
            if x == y then
                m.agree = m.agree + 1
            else
                local key = y .. " -> " .. x
                m.conf[key] = (m.conf[key] or 0) + 1
            end
        end
    end
    reactions(a.ours, a.theirs, a.combat, m.react)
    local s = m.A
    s.combat, s.full, s.idle, s.damage, s.time = a.combat, a.full, a.idle, a.damage, a.combat / (o and o.hz or 5)
    s.flicker = flicker(a.ours, a.combat)
    m.B = s -- one side: a replay has no oracle run (the line's A/B fields read 1)
    m.errors, m.raises, m.cpu = a.errors, a.raises, a.cpu
    for _, name in ipairs(a.misses) do
        m.misses[name] = true
    end
    m.dec = { both = 0, agree = 0, conf = {} }
    for i, y in ipairs(a.dec.theirs) do
        local x = a.dec.ours[i]
        m.dec.both = m.dec.both + 1
        if x == y then
            m.dec.agree = m.dec.agree + 1
        else
            local key = y .. " -> " .. tostring(x)
            m.dec.conf[key] = (m.dec.conf[key] or 0) + 1
        end
    end
    return m
end
```
  - In `M.summary`, before `return r`: `if m.dec then r.decisions = m.dec.agree / math.max(1, m.dec.both) end`.
  - In `M.line`, move the confusion-top code into a local `top3(conf)` (above `M.line`) returning
    `table.concat(top, "; ")`; use it for `m.conf`, and replace the final `return (...):format(...)` with
    `local line = (...):format(...)` followed by

```lua
    if m.dec then -- a replay's headline (loop.replay): every other line is unchanged
        line = line .. ("; decisions on-GCD %.3f (%d) top [%s]"):format(r.decisions, m.dec.both, top3(m.dec.conf))
    end
    return line
```

- [ ] **Step 6: Run the specs**

Run: `.lua/bin/busted tests/Game/harness/replay_spec.lua tests/Game/harness/loop_spec.lua tests/boundary_spec.lua`
Expected: PASS. If the boundary flags a word of `replay.lua` (a resource name colliding with a one-word content key),
rename the local, never add an exception.

- [ ] **Step 7: Create `tests/Forever/helpers/wowsims.lua`**

```lua
-- tests/Forever/helpers/wowsims.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 3):
-- a class world's content (tests/Forever/helpers/<class>_world.lua) as a wowsims replay's and as a leveling
-- bracket's, and the two gates. `content`: the build's talents from the log header (cut to a level's points, the
-- dominant tree first), ranks above the level unknown (learn_<class>.lua, the DB2's), the abilities the world's kit
-- lacks, requirement overrides; `gate`: the replay gate (decision-point on-GCD agreement >= a floor, the engine's
-- health); `live`: the leveling gate (the pack driving the loop's own world never idles `n` GCDs while a known on-GCD
-- ability is usable, no error). Data: wowsims/forever (MIT, https://github.com/wowsims/forever).
local assert = require("luassert")
local loop = require("Game.harness.loop")
local replay = require("Game.harness.replay")
local pack_gate = require("Forever.helpers.pack_gate")

local M = {}

M.DIR = "tests/Forever/wowsims/"

local function slurp(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

--- The checked-in log of spec `spec`.
function M.log(spec)
    return slurp(M.DIR .. spec .. ".log")
end

--- The log header of spec `spec` (replay.parse's).
function M.header(spec)
    return replay.parse(M.log(spec)).header
end

--- The learn levels of class `token` ({ [spellID] = level }).
function M.learn(token)
    return dofile(M.DIR .. "learn_" .. token:lower() .. ".lua")
end

local kits = {}
local function abilities(token) -- the class kit's abilities (the engine's headless load), once a class
    if not kits[token] then
        kits[token] = require("Forever.helpers.engine").load(token).class.kit.abilities
    end
    return kits[token]
end
local function rankIDs(token, key)
    local a = assert(abilities(token)[key], "no ability " .. key)
    local out = { a.id }
    for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
        out[#out + 1] = id
    end
    return out
end

--- Content `base` (a class world's: character, usable, resolve, uptime, gain, WORLD, OBSERVE) as pack `o.pack`'s at
--- `o.level` [60]. `o.talents` ({ { id, rank, tree } }: the build's; default the world's) are cut to the level's points
--- (one a level from 10), the dominant tree first, each talent's spell known; `o.learn` ({ [spellID] = level }) drops
--- ranks above the level (an ID it lacks counts as level 1); `o.kit` adds abilities the world's kit lacks (usable on
--- cost); `o.requires` ({ [key] = fn(W, e) -> ok, why }) replaces an ability's requirement in the usability answers
--- (it then owns the stance check too). The world's mob is the character's level.
function M.content(base, o)
    local level = o.level or 60
    local C = setmetatable({ PACK = o.pack or base.PACK }, { __index = base })
    C.WORLD = setmetatable({ level = level }, { __index = base.WORLD })
    local learn = o.learn or {}
    local function learned(id)
        return type(id) ~= "number" or (learn[id] or 1) <= level
    end
    function C.character()
        local c = {}
        for k, v in pairs(base.character()) do
            c[k] = v
        end
        c.level = level
        local known = {}
        for _, id in ipairs(c.known) do
            if learned(id) then
                known[#known + 1] = id
            end
        end
        for _, key in ipairs(o.kit or {}) do
            for _, id in ipairs(rankIDs(c.class, key)) do
                if learned(id) then
                    known[#known + 1] = id
                end
            end
        end
        if o.talents then
            local points, per = math.max(0, level - 9), {}
            for _, t in ipairs(o.talents) do
                per[t[3]] = (per[t[3]] or 0) + t[2]
            end
            local dom, most = 1, -1
            for tree, n in pairs(per) do
                if n > most or (n == most and tree < dom) then
                    dom, most = tree, n
                end
            end
            local order = {}
            for _, t in ipairs(o.talents) do
                if t[3] == dom then
                    order[#order + 1] = t
                end
            end
            for _, t in ipairs(o.talents) do
                if t[3] ~= dom then
                    order[#order + 1] = t
                end
            end
            local talents = {}
            for _, t in ipairs(order) do
                local r = math.min(t[2], points)
                if r <= 0 then
                    break
                end
                talents[t[1]], points = r, points - r
                known[#known + 1] = t[1]
            end
            c.talents = talents
        end
        c.known = known
        return c
    end
    function C.usable(H)
        local token = base.character().class
        local over, out, seen = {}, {}, {}
        for key in pairs(o.requires or {}) do
            for _, id in ipairs(rankIDs(token, key)) do
                over[id] = key
            end
        end
        for _, row in ipairs(base.usable(H)) do
            if not over[row[1]] then
                out[#out + 1], seen[row[1]] = row, true
            end
        end
        local function answer(key, req)
            local cost = H.Hekili.State.action[key].cost or 0
            return function(W, e, power)
                local ok = not req or req(W, e)
                return ok and power >= cost, ok and power < cost
            end
        end
        for key, req in pairs(o.requires or {}) do
            for _, id in ipairs(rankIDs(token, key)) do
                out[#out + 1] = { id, answer(key, req) }
            end
        end
        for _, key in ipairs(o.kit or {}) do
            if not (o.requires and o.requires[key]) then
                for _, id in ipairs(rankIDs(token, key)) do
                    if not seen[id] then
                        out[#out + 1] = { id, answer(key) }
                    end
                end
            end
        end
        table.sort(out, function(x, y)
            return x[1] < y[1]
        end)
        return out
    end
    return C
end

--- The replay gate of content `C` on spec `spec`'s log: prints "<label> wowsims: <line>", asserts the engine's health
--- (pack_gate.health) and decisions on-GCD >= `floor`. `o`: replay.new's knobs over the character's forms and the
--- content WORLD's regen and fsr. Returns the summary and the line.
function M.gate(label, C, spec, floor, o)
    local L = loop.new(C)
    local ro = setmetatable({ forms = C.character().forms }, { __index = o or {} })
    local R = replay.new(M.log(spec), L.oracle, ro)
    local m = loop.replay(L, R)
    local r, line = loop.summary(m), loop.line(m)
    print("\n" .. label .. " wowsims: " .. line)
    pack_gate.health(m, r, line)
    assert.is_true(r.decisions >= floor, line)
    return r, line
end

--- The leveling gate of content `C` (its pack drives the loop's own world at C's level, `fights` [1] fights of 120 s,
--- one instance): prints "<label> live L<level>: ..." and asserts no error, raise or unlisted read, at least one press,
--- and never idle longer than `limit` seconds [6: four GCDs] in a row with a known on-GCD ability the world would
--- accept. Idle: in combat, our GCD free, no cast in progress, no press this tick. Returns the worst idle and the line.
function M.live(label, C, limit, fights)
    limit = limit or 6
    local L = loop.new(C)
    local c = C.character()
    local known = {}
    for _, id in ipairs(c.known) do
        known[id] = true
    end
    local abilities = L.oracle.Hekili.Class.abilities
    local worst, presses, errors = 0, 0, 0
    for seed = 1, fights or 1 do
        local streak, last = 0, 0
        local run = loop.run(L, seed, {
            duration = 120,
            on = function(run, _, t)
                local us = run.us
                local pressed = run.presses > last
                last = run.presses
                local idle = t >= loop.PULL and not pressed and us.gcdUntil <= t and t >= (us.castUntil or 0)
                local usable = false
                if idle then
                    for _, row in ipairs(L.answers) do
                        local a = known[row[1]] and abilities[row[1]]
                        if a and a.gcd ~= "off" and row[2](run.W, us, us.power) then
                            usable = true
                            break
                        end
                    end
                end
                streak = (idle and usable) and streak + 1 or 0
                worst = math.max(worst, streak)
            end,
        }, { { H = L.us } })
        presses = presses + run.presses
        errors = errors + run.errors + run.raises + #run.misses
    end
    local seconds = worst * loop.TICK
    local line = ("worst idle %.1f s with a usable on-GCD ability (limit %.1f), presses %d, errors %d"):format(
        seconds,
        limit,
        presses,
        errors
    )
    print("\n" .. label .. " live L" .. c.level .. ": " .. line)
    assert.are.equal(0, errors, line)
    assert.is_true(presses > 0, line)
    assert.is_true(seconds <= limit + 1e-9, line)
    return seconds, line
end

return M
```
  (`M.content` reads `c.class` from the world's character: every class world sets `class = "<TOKEN>"`. `M.gate`
  passes `regen`/`fsr` through the loop: `loop.run` hands `wo`, which falls through to `C.WORLD`, to `R.world`.)

- [ ] **Step 8: Run, then the gate**

Run: `.lua/bin/busted tests/Game/harness/replay_spec.lua tests/Game/harness/loop_spec.lua tests/boundary_spec.lua && make check`
Expected: PASS. Gate with `TASK=3`: `gate lines identical` (the injection is off unless `o.replay` is set; `step` runs
the same calls in the same order as before; `blank()` builds the same table).

- [ ] **Step 9: Commit**

```bash
git add tests/Game/harness/replay.lua tests/Game/harness/replay_spec.lua tests/Game/harness/fixtures/wowsims_test.log \
  tests/Game/harness/loop.lua tests/Game/harness/loop_spec.lua tests/Forever/helpers/wowsims.lua
git commit -m "feat(harness): replay a wowsims log as the loop's world; decision-point on-GCD agreement

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: the APL translator, the leveling guard check, `make wowsims-packs` (L)

**Files:**
- Create: `tools/wowsims/apl.lua`, `tools/check_pack_levels.lua`, `tests/Forever/wowsims_apl_spec.lua`,
  `tests/Forever/wowsims_levels_spec.lua`

**Interfaces:**
- Consumes: Task 2 (`export.lua`'s `pack` mode calls `require("tools.wowsims.apl").write(spec, ex)`; the request
  JSON's `raid.parties[1].players[1].rotation`).
- Produces (`tools/wowsims/apl.lua`): `apl.context(kit, recipe) -> c`; `apl.translate(rotation, c) -> text, omitted,
  toggles` (`toggles` = `{ { key, default } }`); `apl.write(spec, ex)` (writes
  `src/Hekili_<Class>/APLs/<recipe.pack>.simc`); `apl.snake(name)`.
- Produces (`tools/check_pack_levels.lua`, loaded with `loadfile(...)()`): `levels.unguarded(criteria, self,
  isAbility) -> { "<kind>.<key>.<field>", ... }`; `levels.file(path, isAbility) -> { "<line>: <ref>", ... }`.

**The translation rules** (written into `apl.lua`'s header; the reviewer checks the code against them):
1. One `.simc` line per APL entry, in order: `prepullActions` -> `actions.precombat`, `priorityList` -> `actions`,
   each group a list `actions.<snake of its name>` called with `call_action_list,name=<snake>`, groups in the APL's
   order as first called; `valueVariables` are inlined where referenced.
2. Omitted, and listed in the file's second comment block: `hide: true` entries; entries whose condition folds to
   false; entries whose action or condition uses a node the fork lacks (`autocastOtherCooldowns`,
   `castAllStatBuffCooldowns`, `strictSequence`, `sequence`, `resetSequence`, `schedule`, `itemSwap`, `move`, `wait`,
   `unitDistance`, `sequenceIsComplete`, `activeItemSwapSet`, `selectedConjured`, an unmapped spell, item or other
   ID); a call of a group whose every entry was omitted.
3. Toggles: a group whose actions are all empty is a wowsims ON/OFF switch: `actionGroupUsed` of it reads
   `settings.wowsims_<snake of the name without " ON/OFF">`, its default on exactly when the APL's reference to it is
   not hidden; the class registers that setting for the spec (named "<Group> (wowsims.com)").
4. Solo exports: `auraIsKnown` (another player's aura) is false.
5. Keys: a spell ID maps through the recipe's `map`, else the class kit's abilities (`id` and `copy`), auras by the
   kit's auras then abilities, items by an ability's `item`; `includeReactionTime`, `tag` and `rank` are ignored.
6. **Leveling guard:** every value or test that reads another ability `X` (its cooldown, cast time, cost, readiness,
   or an aura whose key is `X`) is wrapped `(!action.X.known|<test>)` where it must hold and `(action.X.known&<test>)`
   under a `not`, so an unknown `X` never blocks the line; an aura whose ID is a talent's spell is guarded the same way
   by `talent.<key>.enabled`. The line's own action is never guarded (the engine skips an unknown action).
7. `focus` from the recipe (the tiers the retired list carried, by action), `use_off_gcd=1` on an ability whose `gcd`
   is `"off"`; the recipe's `leveling` lines are appended to `actions`, each silent at 60.

- [ ] **Step 1: Write the failing specs.** `tests/Forever/wowsims_apl_spec.lua`:

```lua
-- tests/Forever/wowsims_apl_spec.lua (wowsims packs plan, Task 4): the APL translator's rules on a small APL in
-- wowsims/forever's JSON shape (MIT) with a stand-in class context.
local apl = require("tools.wowsims.apl")

local function ctx(r)
    local kit = {
        abilities = {
            strike = { key = "strike", id = 100, copy = { 101 }, gcd = "spell" },
            big_hit = { key = "big_hit", id = 200, gcd = "spell" },
            roar = { key = "roar", id = 300, gcd = "off" },
            dot = { key = "dot", id = 400, gcd = "spell" },
            trinket = { key = "trinket", id = -1, item = 555, gcd = "off" },
        },
        auras = { dot = { id = 400 }, fury = { id = 900 }, stance = { id = 910 } },
        talents = { furious = { 2, 900, 1 } },
    }
    return apl.context(kit, r or { executePhase = "execute_phase", focus = { strike = 1 } })
end
local function cast(id, cond)
    return { action = { castSpell = { spellId = { spellId = id } }, condition = cond } }
end
local function cmp(op, lhs, rhs)
    return { cmp = { op = op, lhs = lhs, rhs = rhs } }
end
local function const(v)
    return { const = { val = v } }
end

describe("the wowsims APL translator", function()
    it("keeps the order, maps keys, flags off-GCD and focus, and guards another ability's reads", function()
        local text, omitted = apl.translate({
            prepullActions = { cast(300) },
            priorityList = {
                cast(100, cmp("OpGe", { spellTimeToReady = { spellId = { spellId = 200 } } }, const("1.5s"))),
                cast(200, { ["not"] = { val = { auraIsActive = { auraId = { spellId = 900 } } } } }),
                cast(400, cmp("OpLe", { dotRemainingTime = { spellId = { spellId = 400 } } }, const("300ms"))),
                { action = { castSpell = { spellId = { itemId = 555 } } } },
                cast(101, { isExecutePhase = { threshold = "E20" } }),
            },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions.precombat=roar,use_off_gcd=1",
                "actions=strike,focus=1,if=(!action.big_hit.known|cooldown.big_hit.remains>=1.5)",
                "actions+=/big_hit,if=!(talent.furious.enabled&buff.fury.up)",
                "actions+=/dot,if=debuff.dot.remains<=0.3",
                "actions+=/trinket,use_off_gcd=1",
                "actions+=/strike,focus=1,if=execute_phase",
            }, "\n"),
            text
        )
        assert.are.same({}, omitted)
    end)

    it("folds constants, omits hidden and unsupported entries, inlines variables, makes toggles settings", function()
        local text, omitted, toggles = apl.translate({
            priorityList = {
                { hide = true, action = { groupReference = { groupName = "Big ON/OFF" } } },
                { action = { groupReference = { groupName = "Weave ON/OFF" } } },
                cast(100, { ["and"] = { vals = { { actionGroupUsed = { name = "Big ON/OFF" } }, const("true") } } }),
                cast(200, { ["or"] = { vals = { const("false"), { auraIsKnown = { auraId = { spellId = 900 } } } } } }),
                cast(300, { variableRef = { name = "Low" } }),
                { action = { wait = {} } },
                cast(999),
                { action = { groupReference = { groupName = "Opener" } } },
            },
            groups = {
                { name = "Big ON/OFF", actions = { { action = {} } } },
                { name = "Weave ON/OFF", actions = { { action = {} } } },
                { name = "Opener", actions = { cast(400) } },
            },
            valueVariables = { { name = "Low", value = cmp("OpLt", { currentRage = {} }, const("30")) } },
        }, ctx())
        assert.are.equal(
            table.concat({
                "actions=strike,focus=1,if=settings.wowsims_big",
                "actions+=/roar,use_off_gcd=1,if=rage.current<30",
                "actions+=/call_action_list,name=opener",
                "actions.opener=dot",
            }, "\n"),
            text
        )
        assert.are.same({ "default #1: hidden", "default #4: never", "default #6: wait", "default #7: spell 999" }, omitted)
        assert.are.same({ { "wowsims_big", false }, { "wowsims_weave", true } }, toggles)
    end)

    it("drops a call to a group whose entries were all omitted", function()
        local text, omitted = apl.translate({
            priorityList = { { action = { groupReference = { groupName = "Gone" } } }, cast(100) },
            groups = { { name = "Gone", actions = { cast(999) } } },
        }, ctx())
        assert.are.equal("actions=strike,focus=1", text)
        assert.are.same({ "gone #1: spell 999", "default: empty group gone" }, omitted)
    end)
end)
```

  `tests/Forever/wowsims_levels_spec.lua`:

```lua
-- tests/Forever/wowsims_levels_spec.lua (wowsims packs plan, Task 4): the leveling rule. A wowsims pack line may read
-- another ability's state only behind a known guard (tools/check_pack_levels.lua), so an ability a character has not
-- learned cannot block it; checked on every "(wowsims.com)" .simc in the repository.
local levels = assert(loadfile("tools/check_pack_levels.lua"))()
local engine = require("Forever.helpers.engine")

local ABIL = { strike = true, big_hit = true, stance = true }
local function isAbility(k)
    return ABIL[k] == true
end

describe("tools/check_pack_levels.lua", function()
    it("refuses an unguarded read of another ability and accepts the translator's guards", function()
        assert.are.same({ "cooldown.big_hit.remains" }, levels.unguarded("cooldown.big_hit.remains>1.5", "strike", isAbility))
        assert.are.same({}, levels.unguarded("(!action.big_hit.known|cooldown.big_hit.remains>1.5)", "strike", isAbility))
        assert.are.same({}, levels.unguarded("!(action.stance.known&buff.stance.up)&rage.current>10", "strike", isAbility))
        assert.are.same({}, levels.unguarded("cooldown.strike.remains<1&debuff.other_aura.up", "strike", isAbility))
        assert.are.same(
            { "buff.stance.up" },
            levels.unguarded("(!action.big_hit.known|cooldown.big_hit.ready)&buff.stance.up", "strike", isAbility)
        )
        assert.are.same({}, levels.unguarded("!action.big_hit.known&rage.current>=45", "strike", isAbility))
    end)

    it("finds every wowsims pack line guarded", function()
        local pipe = assert(io.popen("ls src"))
        for addon in pipe:lines() do
            local root = "src/" .. addon .. "/APLs/"
            local ok, def = pcall(dofile, root .. "packs.lua")
            if ok and def.class then
                local abilities = engine.load(def.class).class.kit.abilities
                local function isAb(k)
                    local a = abilities[k]
                    return type(a) == "table" and a.key == k
                end
                for _, name in ipairs(def.packs) do
                    if name:find("(wowsims.com)", 1, true) then
                        assert.are.same({}, levels.file(root .. name .. ".simc", isAb), name)
                    end
                end
            end
        end
        pipe:close()
    end)
end)
```

- [ ] **Step 2: Run them to verify they fail**

Run: `.lua/bin/busted tests/Forever/wowsims_apl_spec.lua tests/Forever/wowsims_levels_spec.lua`
Expected: FAIL (`module 'tools.wowsims.apl' not found`, `cannot open tools/check_pack_levels.lua`). Busted's lpath
includes `./?.lua`, so `require("tools.wowsims.apl")` resolves once the file exists.

- [ ] **Step 3: Create `tools/wowsims/apl.lua`**

```lua
-- tools/wowsims/apl.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): a
-- wowsims/forever APL (a request's player.rotation) as a "(wowsims.com)" pack's SimC text with the fork's keys.
-- Rules (the plan's Task 4, "The translation rules"): one line per entry in order; prepull -> precombat, groups ->
-- lists, variables inlined; hidden, never-true and unsupported entries omitted and listed; ON/OFF groups ->
-- settings.wowsims_<name> (default on when shown); auraIsKnown false (solo exports); keys through the recipe's map,
-- then the class kit; focus and leveling lines from the recipe. The leveling guard: a read of another ability X is
-- (!action.X.known|test) (or (action.X.known&test) under a not) because the engine answers an unknown X's
-- cooldown.X.remains 0 (src/Hekili/Engine/Sim/State.lua, mt_default_cooldown's `if not state:IsKnown( t.key )`
-- lines), which would block `cooldown.X.remains>Y`; action.X.known is state:IsKnown (mt_default_action), and an
-- entry whose own action is unknown is skipped (src/Hekili/Engine/Sim/Core.lua, `ability and known and enabled`).
-- Data: wowsims/forever (MIT, https://github.com/wowsims/forever); no code copied.
local M = {}

M.OPS = { OpEq = "=", OpNe = "!=", OpLt = "<", OpLe = "<=", OpGt = ">", OpGe = ">=" }
M.MATH = { OpAdd = "+", OpSub = "-", OpMul = "*", OpDiv = "%" } -- SimC's division is %
-- Values with one translation.
M.VALUES = {
    numberTargets = "active_enemies",
    currentRage = "rage.current",
    currentEnergy = "energy.current",
    currentMana = "mana.current",
    currentManaPercent = "mana.pct",
    maxMana = "mana.max",
    currentManaRegen = "mana.regen",
    currentComboPoints = "combo_points.current",
    currentHealthPercent = "health.pct",
    currentTime = "time",
    remainingTime = "fight_remains",
    gcdTimeToReady = "gcd.remains",
    inputDelay = "0", -- wowsims's modelled reaction; the engine recommends without one
}

local function unsupported(what)
    error({ unsupported = what }, 0)
end

--- A name in snake_case ("Pre-pull: Stance" -> "pre_pull_stance").
function M.snake(s)
    return (s:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

--- The translation context of a class kit (`abilities`, `auras`, `talents` as the engine registers them) and recipe
--- `r` (map, focus, executePhase, leveling).
function M.context(kit, r)
    local c = {
        keyOf = {},
        auraOf = {},
        itemKey = {},
        ability = {},
        offGcd = {},
        talent = {},
        map = r.map or {},
        focus = r.focus or {},
        executePhase = r.executePhase,
        leveling = r.leveling or {},
    }
    local keys = {}
    for key, a in pairs(kit.abilities) do
        if type(key) == "string" and type(a) == "table" and a.key == key then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local a = kit.abilities[key]
        c.ability[key] = true
        c.offGcd[key] = a.gcd == "off" or nil
        if type(a.item) == "number" then
            c.itemKey[a.item] = key
        end
        local list = { a.id }
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            list[#list + 1] = id
        end
        for _, id in ipairs(list) do
            if type(id) == "number" then
                c.keyOf[id] = c.keyOf[id] or key
            end
        end
    end
    local akeys = {}
    for key, a in pairs(kit.auras) do
        if type(key) == "string" and type(a) == "table" and type(a.id) == "number" then
            akeys[#akeys + 1] = key
        end
    end
    table.sort(akeys)
    for _, key in ipairs(akeys) do
        local a = kit.auras[key]
        c.auraOf[a.id] = c.auraOf[a.id] or key
        for _, id in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
            if type(id) == "number" then
                c.auraOf[id] = c.auraOf[id] or key
            end
        end
    end
    for key, t in pairs(kit.talents or {}) do
        local aura = type(t) == "table" and c.auraOf[t[2]]
        if aura and not c.ability[aura] then
            c.talent[aura] = key
        end
    end
    return c
end

local function const(v)
    if v == "true" then
        return nil, true
    elseif v == "false" then
        return nil, false
    end
    local n, unit = tostring(v):match("^(%-?[%d.]+)(m?s?)$")
    if not n then
        unsupported("const " .. tostring(v))
    end
    return ("%g"):format(tonumber(n) / (unit == "ms" and 1000 or 1))
end

local function spellKey(c, s)
    if s.spellId then
        return c.map[s.spellId] or c.keyOf[s.spellId] or unsupported("spell " .. s.spellId)
    elseif s.itemId then
        return c.map["item:" .. s.itemId] or c.itemKey[s.itemId] or unsupported("item " .. s.itemId)
    end
    return c.map[s.otherId] or unsupported("other " .. tostring(s.otherId))
end

local function auraKey(c, id)
    return c.map[id] or c.auraOf[id] or c.keyOf[id] or unsupported("aura " .. tostring(id))
end

local function unit(v)
    return (v.sourceUnit and v.sourceUnit.type == "CurrentTarget") and "debuff" or "buff"
end

-- `atom` reads `x`: guarded so an unknown `x` cannot block its entry (rule 6); `neg` under an odd number of nots.
local function guard(c, x, atom, neg)
    if x == c.self then
        return atom
    end
    local test = c.ability[x] and ("action." .. x .. ".known") or (c.talent[x] and ("talent." .. c.talent[x] .. ".enabled"))
    if not test then
        return atom
    end
    return neg and ("(" .. test .. "&" .. atom .. ")") or ("(!" .. test .. "|" .. atom .. ")")
end

local function value(c, n)
    local k, v = next(n)
    if k == "const" then
        local s = const(v.val)
        if s == nil then
            unsupported("boolean as a value")
        end
        return s, {}
    elseif M.VALUES[k] then
        return M.VALUES[k], {}
    elseif k == "variableRef" then
        return value(c, c.vars[v.name] or unsupported("variable " .. v.name))
    elseif k == "math" then
        local l, lr = value(c, v.lhs)
        local r, rr = value(c, v.rhs)
        for _, x in ipairs(rr) do
            lr[#lr + 1] = x
        end
        return "(" .. l .. (M.MATH[v.op] or unsupported("math " .. tostring(v.op))) .. r .. ")", lr
    elseif k == "spellTimeToReady" or k == "spellCastTime" or k == "spellCurrentCost" then
        local x = spellKey(c, v.spellId)
        local field = ({
            spellTimeToReady = "cooldown." .. x .. ".remains",
            spellCastTime = "action." .. x .. ".cast",
            spellCurrentCost = "action." .. x .. ".cost",
        })[k]
        return field, { x }
    elseif k == "dotRemainingTime" then
        local a = auraKey(c, v.spellId.spellId)
        return "debuff." .. a .. ".remains", { a }
    elseif k == "auraRemainingTime" or k == "auraNumStacks" then
        local a = auraKey(c, v.auraId.spellId)
        return unit(v) .. "." .. a .. (k == "auraNumStacks" and ".stack" or ".remains"), { a }
    elseif k == "autoTimeToNext" and v.autoType == "MainHandAuto" then
        return "mainhand_remains", {}
    elseif k == "autoTimeSinceLast" and v.autoType == "MainHandAuto" then
        return "(mainhand_speed-mainhand_remains)", {}
    elseif k == "totemRemainingTime" then
        return "totem." .. M.snake(tostring(v.totemType)):gsub("^totem_", "") .. ".remains", {}
    end
    unsupported(tostring(k))
end

-- Whether `s` is one parenthesised group from its first character to its last.
local function grouped(s)
    if s:sub(1, 1) ~= "(" then
        return false
    end
    local depth = 0
    for i = 1, #s do
        local ch = s:sub(i, i)
        depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
        if depth == 0 then
            return i == #s
        end
    end
    return false
end

local bool
local function negate(c, n, neg)
    local s, b = bool(c, n, not neg)
    if b ~= nil then
        return nil, not b
    end
    return (s:match("^[%w_.]+$") or grouped(s)) and ("!" .. s) or ("!(" .. s .. ")")
end

-- A condition: its text, or nil and a constant when it folds.
function bool(c, n, neg)
    local k, v = next(n)
    if k == "and" or k == "or" then
        local absorb, parts = k == "or", {}
        for _, x in ipairs(v.vals or {}) do
            local s, b = bool(c, x, neg)
            if b == absorb then
                return nil, absorb
            elseif b == nil then
                parts[#parts + 1] = s
            end
        end
        if #parts == 0 then
            return nil, not absorb
        elseif #parts == 1 then
            return parts[1]
        end
        return "(" .. table.concat(parts, k == "and" and "&" or "|") .. ")"
    elseif k == "not" then
        return negate(c, v.val, neg)
    elseif k == "const" then
        local _, b = const(v.val)
        if b == nil then
            unsupported("number as a condition")
        end
        return nil, b
    elseif k == "cmp" then
        local l, lr = value(c, v.lhs)
        local r, rr = value(c, v.rhs)
        local s = l .. (M.OPS[v.op] or unsupported("op " .. tostring(v.op))) .. r
        local done = {}
        for _, list in ipairs({ lr, rr }) do
            for _, x in ipairs(list) do
                if not done[x] then
                    done[x] = true
                    s = guard(c, x, s, neg)
                end
            end
        end
        return s
    elseif k == "auraIsActive" then
        local a = auraKey(c, v.auraId.spellId)
        return guard(c, a, unit(v) .. "." .. a .. ".up", neg)
    elseif k == "auraIsInactive" then
        return negate(c, { auraIsActive = v }, neg)
    elseif k == "auraIsKnown" then
        return nil, false -- rule 4: solo exports
    elseif k == "dotIsActive" then
        local a = auraKey(c, v.spellId.spellId)
        return guard(c, a, "debuff." .. a .. ".up", neg)
    elseif k == "spellIsReady" then
        local x = spellKey(c, v.spellId)
        return guard(c, x, "cooldown." .. x .. ".ready", neg)
    elseif k == "spellCanCast" then
        local x = spellKey(c, v.spellId)
        return guard(c, x, "action." .. x .. ".ready", neg)
    elseif k == "spellIsKnown" then
        return "action." .. spellKey(c, v.spellId) .. ".known"
    elseif k == "isExecutePhase" then
        if v.threshold == "E20" and c.executePhase then
            return c.executePhase
        end
        unsupported("isExecutePhase " .. tostring(v.threshold))
    elseif k == "actionGroupUsed" then
        return "settings." .. (c.toggles[v.name] or unsupported("actionGroupUsed " .. tostring(v.name)))
    elseif k == "variableRef" then
        return bool(c, c.vars[v.name] or unsupported("variable " .. v.name), neg)
    end
    unsupported(tostring(k))
end

-- One entry as a line body, or nil and why it folds away.
local function entry(c, e)
    local a = e.action or {}
    local kind
    for k in pairs(a) do
        if k ~= "condition" then
            kind = k
        end
    end
    if not kind then
        return nil, "empty"
    end
    local body
    if kind == "castSpell" or kind == "channelSpell" then
        local x = spellKey(c, a[kind].spellId)
        c.self = x
        local tier = c.focus[x]
        if type(tier) == "table" then
            c.seen[x] = (c.seen[x] or 0) + 1
            tier = tier[c.seen[x]] or tier[#tier]
        end
        body = x .. (c.offGcd[x] and ",use_off_gcd=1" or "") .. (tier and (",focus=" .. tier) or "")
    elseif kind == "groupReference" then
        local g = a.groupReference.groupName
        if c.toggles[g] then
            return nil, "toggle"
        end
        c.used[g], c.self = true, nil
        body = "call_action_list,name=" .. M.snake(g)
    else
        unsupported(kind)
    end
    if a.condition then
        local s, b = bool(c, a.condition, false)
        if b == false then
            return nil, "never"
        elseif s then
            body = body .. ",if=" .. s
        end
    end
    return body
end

--- The SimC text of `rotation` (a wowsims APL table) under context `c`, the omitted entries
--- ({ "<list> #<n>: <why>" }) and the toggles ({ { setting key, default } } in the APL's group order).
function M.translate(rotation, c)
    c.vars, c.toggles, c.used, c.seen = {}, {}, {}, {}
    for _, v in ipairs(rotation.valueVariables or {}) do
        c.vars[v.name] = v.value
    end
    local toggles, shown = {}, {}
    for _, e in ipairs(rotation.priorityList or {}) do
        local g = e.action and e.action.groupReference
        if g and not e.hide then
            shown[g.groupName] = true
        end
    end
    for _, g in ipairs(rotation.groups or {}) do
        local empty = true
        for _, x in ipairs(g.actions or {}) do
            empty = empty and next(x.action or {}) == nil
        end
        if empty then
            c.toggles[g.name] = "wowsims_" .. M.snake((g.name:gsub(" ON/OFF$", "")))
            toggles[#toggles + 1] = { c.toggles[g.name], shown[g.name] == true }
        end
    end
    local omitted, lists, byName = {}, {}, {}
    local function run(name, entries)
        local out = {}
        for i, e in ipairs(entries) do
            if e.hide then
                omitted[#omitted + 1] = ("%s #%d: hidden"):format(name, i)
            else
                local ok, body, why = pcall(entry, c, e)
                if not ok then
                    if type(body) ~= "table" then
                        error(body, 0)
                    end
                    omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, body.unsupported)
                elseif body then
                    out[#out + 1] = body
                elseif why ~= "toggle" then
                    omitted[#omitted + 1] = ("%s #%d: %s"):format(name, i, why)
                end
            end
        end
        lists[#lists + 1], byName[name] = { name, out }, out
    end
    run("precombat", rotation.prepullActions or {})
    run("default", rotation.priorityList or {})
    for _, line in ipairs(c.leveling) do
        table.insert(byName.default, line)
    end
    local done = {}
    repeat
        local more = false
        for _, g in ipairs(rotation.groups or {}) do
            if c.used[g.name] and not done[g.name] then
                done[g.name], more = true, true
                run(M.snake(g.name), g.actions or {})
            end
        end
    until not more
    local text = {}
    for _, l in ipairs(lists) do
        local head = l[1] == "default" and "actions" or ("actions." .. l[1])
        local n = 0
        for _, body in ipairs(l[2]) do
            local called = body:match("^call_action_list,name=([%w_]+)")
            if called and #(byName[called] or {}) == 0 then
                omitted[#omitted + 1] = ("%s: empty group %s"):format(l[1], called)
            else
                n = n + 1
                text[#text + 1] = head .. (n == 1 and "=" or "+=/") .. body
            end
        end
    end
    return table.concat(text, "\n"), omitted, toggles
end

--- Writes spec `spec`'s pack: src/Hekili_<Class>/APLs/<recipe.pack>.simc from the checked-in request (`ex`:
--- export.lua's module), its description, toggles and omitted entries in the header.
function M.write(spec, ex)
    local json = require("dkjson")
    local r = ex.recipe(spec)
    local f = assert(io.open(ex.OUT .. spec .. ".json", "rb"))
    local req = json.decode(f:read("*a"))
    f:close()
    local kit = require("Forever.helpers.engine").load(r.class).class.kit
    local text, omitted, toggles = M.translate(req.raid.parties[1].players[1].rotation, M.context(kit, r))
    local Class = r.class:sub(1, 1) .. r.class:sub(2):lower()
    local out = {
        ("# %s: the wowsims/forever default APL for %s (%s), translated to this addon's keys."):format(
            r.pack,
            r.name,
            r.apl or r.build
        ),
        "# Data: wowsims/forever (MIT, https://github.com/wowsims/forever) at " .. ex.PIN:sub(1, 12) .. ".",
        "",
        ("# Generated by `make wowsims-packs` (tools/wowsims/apl.lua) from tools/wowsims/specs/%s.lua: edit that recipe, not this file."):format(
            spec
        ),
    }
    for _, t in ipairs(toggles) do
        out[#out + 1] = ("# Setting %s (wowsims ON/OFF group), default %s."):format(t[1], tostring(t[2]))
    end
    for _, o in ipairs(omitted) do
        out[#out + 1] = "# Omitted: " .. o
    end
    out[#out + 1] = ""
    out[#out + 1] = text
    local path = ("src/Hekili_%s/APLs/%s.simc"):format(Class, r.pack)
    local w = assert(io.open(path, "wb"))
    w:write(table.concat(out, "\n") .. "\n")
    w:close()
    print(("%s: %d omitted, %d toggles"):format(path, #omitted, #toggles))
end

return M
```

- [ ] **Step 4: Create `tools/check_pack_levels.lua`**

```lua
-- tools/check_pack_levels.lua (wowsims packs plan, docs/superpowers/plans/2026-10-19-wowsims-packs.md, Task 4): the
-- leveling rule's static check. A pack line may read another ability X's state (cooldown.X.*, action.X.* but known,
-- buff.X.*, debuff.X.* with X an ability key) only inside a guard group for X: `(!action.X.known|...)` or
-- `(action.X.known&...)`; a line's own action needs none (the engine skips an unknown action). Loaded with
-- loadfile(...)() it returns { unguarded, file }; run directly: lua tools/check_pack_levels.lua <file.simc>... lists
-- offences against every key (no class data), for a quick look.
local M = {}

local KINDS = { cooldown = true, action = true, buff = true, debuff = true }

--- The unguarded cross-ability reads of one line's criteria (`self` its action; `isAbility(key)`).
function M.unguarded(criteria, self, isAbility)
    local spans = {}
    for s, x in criteria:gmatch("()%(!?action%.([%w_]+)%.known[|&]") do
        local depth, i = 0, s
        repeat
            local ch = criteria:sub(i, i)
            depth = depth + (ch == "(" and 1 or ch == ")" and -1 or 0)
            i = i + 1
        until depth == 0 or i > #criteria
        spans[#spans + 1] = { s, i - 1, x }
    end
    local bad = {}
    for s, kind, x, field in criteria:gmatch("()(%a+)%.([%w_]+)%.([%w_]+)") do
        if KINDS[kind] and x ~= self and isAbility(x) and not (kind == "action" and field == "known") then
            local covered = false
            for _, sp in ipairs(spans) do
                covered = covered or (sp[3] == x and s > sp[1] and s <= sp[2])
            end
            if not covered then
                bad[#bad + 1] = kind .. "." .. x .. "." .. field
            end
        end
    end
    return bad
end

--- The offences of a .simc file: { "<line>: <read>" }.
function M.file(path, isAbility)
    local out = {}
    for line in io.lines(path) do
        local body = line:match("^actions[%w_.]*%+?=/?(.+)$")
        if body then
            local action = body:match("^([%w_]+)")
            local criteria = body:match(",if=(.*)$")
            for _, ref in ipairs(criteria and M.unguarded(criteria, action, isAbility) or {}) do
                out[#out + 1] = line .. ": " .. ref
            end
        end
    end
    return out
end

local args = { ... }
if args[1] and args[1]:match("%.simc$") then
    local n = 0
    for _, path in ipairs(args) do
        for _, o in ipairs(M.file(path, function()
            return true
        end)) do
            print(path .. ": " .. o)
            n = n + 1
        end
    end
    os.exit(n == 0 and 0 or 1)
end
return M
```
  Note on the busted spec's `levels.unguarded("cooldown.strike.remains<1&debuff.other_aura.up", ...)`: `other_aura` is
  not an ability, so it passes; `buff.stance.up` outside a `stance` guard is refused.

- [ ] **Step 5: Run the specs**

Run: `.lua/bin/busted tests/Forever/wowsims_apl_spec.lua tests/Forever/wowsims_levels_spec.lua`
Expected: PASS (the second `it` of the levels spec finds no wowsims pack yet). If a translator expectation differs
only in parenthesisation or guard order, fix the code to the expected text (the guard order is the order of the
references, left then right).

- [ ] **Step 6: Gate and commit**

Run: `make check` (gate with `TASK=4`): `gate lines identical`.

```bash
git add tools/wowsims/apl.lua tools/check_pack_levels.lua tests/Forever/wowsims_apl_spec.lua tests/Forever/wowsims_levels_spec.lua
git commit -m "feat(tools): translate wowsims APLs into packs; guard every cross-ability read for leveling

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## The per-spec procedure (Tasks 5-14 run it; each task gives its data)

Each step is concrete; a task's own section names the values. `<spec>` is the recipe name (`warrior_arms`),
`<Pack>` the pack name (`Arms (wowsims.com)`), `<key>` the spec key (`arms`), `<Class>` the addon's class
(`Warrior`), `<TOKEN>` the token (`WARRIOR`), `<world>` the class world module and its per-pack content
(`ww`; `rw.Combat`; `dlw.Feral` ...: read the world file's last lines for its export names).

- **P1 Recipe.** Write `tools/wowsims/specs/<spec>.lua` in Task 2's recipe shape with the task's values; header:
  `-- tools/wowsims/specs/<spec>.lua (wowsims packs plan, Task N): <Pack>'s wowsims/forever request and translation.`
  and `-- Values from wowsims/forever (MIT) <file>:<lines> at the pin.` Transcribe `options` from the named
  `DefaultOptions` (protojson: enum values as their names, e.g. `"WarriorStanceBerserker"`).
- **P2 Learn levels** (once per class): `make wowsims-learn CLASS=<TOKEN>`; check `tests/Forever/wowsims/learn_<class>.lua`
  has a few hundred rows.
- **P3 Export:** `make wowsims-export SPEC=<spec>` (the checkout at the pin, `make wowsims-cli` once). Read the log's
  first lines: `# wowsims <pin> <spec> ...`, `# talents ...`; `grep -c 'Casting' tests/Forever/wowsims/<spec>.log`
  above 50 (a three-minute fight). An error from wowsimcli means a recipe value is wrong: fix the recipe, not the tool.
- **P4 Translate:** `make wowsims-packs`. Read the generated `src/Hekili_<Class>/APLs/<Pack>.simc`'s `# Omitted:`
  lines. For each `spell N` / `aura N` / `item N`: if the class has the ability or aura under another ID, add it to
  the recipe's `map` (`[N] = "key"`); if the class lacks it and wowsims casts it in the log (`grep 'SpellID: N'`), it
  is a kit gap (P6); otherwise leave it omitted (a trinket, a consumable, a racial of another race). Re-run until the
  list holds only rule-2 nodes and true gaps. Then `.lua/bin/lua tools/check_pack_levels.lua "src/Hekili_<Class>/APLs/<Pack>.simc"`
  prints nothing.
- **P5 Register:** `APLs/packs.lua`: add `"<Pack>"` to `packs` (first) and `["<Pack>"] = "<key>"` to `specs`. In the
  class file, for each `# Setting wowsims_x (...) default D` line of the header, add (once per key per spec)

```lua
spec:RegisterSetting("wowsims_x", D, {
    type = "toggle",
    name = "<Group> (wowsims.com)",
    desc = "The wowsims.com priority's <Group> ON/OFF switch (its default in wowsims's own APL).",
    width = "full",
}, "<key>")
```
  then `make packs` (adds the RegisterPack block) and
  `.lua/bin/busted tests/Forever/make_pack_spec.lua tests/Forever/packs_spec.lua tests/Forever/wowsims_levels_spec.lua`.
- **P6 Kit gaps.** For each ability wowsims casts that the class file lacks or models differently (cast time,
  cooldown, a talent's effect, a proc window): fix it in the class file with a test in the class's spec file
  (`tests/Forever/<class>_spec.lua`), values from `wowdb spell <id>` / `wowdb effects <id>`, never from wowsims's Go.
  Content stays in the pack (core/pack boundary).
- **P7 The replay gate.** Create or extend `tests/Forever/wowsims_<class>_spec.lua`:

```lua
-- tests/Forever/wowsims_<class>_spec.lua (wowsims packs plan, Tasks N..): the <Class> wowsims.com packs against
-- wowsims/forever's own fights (tests/Forever/wowsims/*.log, MIT) and at three levels.
local ws = require("Forever.helpers.wowsims")
local W = require("Forever.helpers.<class>_world")

local function content(spec, base, pack, level, extra)
    local o = { pack = pack, level = level, talents = ws.header(spec).talents, learn = ws.learn("<TOKEN>") }
    for k, v in pairs(extra or {}) do
        o[k] = v
    end
    return ws.content(base, o)
end

describe("the <Class> wowsims.com packs #slow #wowsims", function()
    -- one block per pack: the replay floor (measured on the first clean run, never lowered), the pack's own worst
    -- idle at 60 (LIVE60, measured), and the brackets
end)
```
  and per pack inside the `describe`:

```lua
    it("<Pack> follows wowsims's casts", function()
        ws.gate("<Pack>", content("<spec>", <world>, "<Pack>", 60, <extra>), "<spec>", <FLOOR>, <replay knobs>)
    end)
    local LIVE60 = <measured> -- the pack's own worst idle at 60 (wowsims's pooling), seconds rounded up to 0.1
    for _, level in ipairs({ <first>, 40, 60 }) do
        it("<Pack> stays live at level " .. level, function()
            ws.live("<Pack>", content("<spec>", <world>, "<Pack>", level, <extra>), math.max(6, LIVE60))
        end)
    end
```
  First run with `<FLOOR>` = 0: `.lua/bin/busted tests/Forever/wowsims_<class>_spec.lua`. Read the `wowsims:` line's
  `decisions on-GCD X (n) top [...]`. Work the top three disagreements once each, classifying it in the recipe's
  header comment as one of: content gap (fix in P6, re-run), translation gap (a `map` entry or a rule: fix, re-run),
  replay limit (no cast bars, no landing lag, the target's swings, a hidden aura not yet listed: add the aura to the
  replay knobs' `hidden` if the client cannot see it, else note it), or wowsims quirk (note it). Then set `<FLOOR>` to
  the measured value truncated to two decimals and re-run: PASS. `n` (decisions) above 40 for a three-minute fight;
  fewer means the key map misses casts (P4).
- **P8 Leveling.** Ruling (user, 2026-10-19): wowsims is the oracle, so whatever idle the faithful pack shows at 60
  is correct and is never "fixed"; only lower brackets get fillers, and only ones silent at 60. First run with `LIVE60 = 0` and read the 60 bracket's `worst idle X s`: that is wowsims's own
  pooling (Arms leaves Heroic Strike to 90 rage), so set `LIVE60` to X rounded up to 0.1 with that reason in a
  comment. The limit at every bracket is then `max(6 s = four GCDs, LIVE60)`: a lower level may not idle longer than
  the pack does at 60. A failing bracket prints its idle stretch: fix it with a recipe `leveling` line (a filler the
  level has, silent at 60 by `!action.<a level-60 ability of the build>.known&...`), `make wowsims-packs`, re-run;
  the 60 line and the replay floor must not move. Never raise the limit for a lower bracket.
  A world that raises "unmapped key X" lacks the press of an ability the pack recommends: add `X` to the world's MAP
  (its effect in the world's verbs, as the other entries).
- **P9 Swap** (the user's binding change; only after P7 and P8 pass):
  1. Delete the old `src/Hekili_<Class>/APLs/<Old>.simc`; remove `"<Old>"` from `packs.lua` `packs` and `specs`.
  2. In the class file's `Hekili:NewClass` spec entry for `<key>`: `package = "<Pack>"`. Add the old name to the
     class's retirement call, once per class file, after the RegisterPack blocks' anchor
     (`spec:RetirePacks({ "<Old>", ... })`; extend the list in later tasks).
  3. Copy every `focus=N` of the old list (`git show HEAD:"src/Hekili_<Class>/APLs/<Old>.simc" | grep -o
     '[a-z_]*,[^ ]*focus=[0-9]'`) into the recipe's `focus` by action (a list when one action carried two tiers in
     order); `make wowsims-packs && make packs`.
  4. Move the belief gates onto the pack: the world content's `PACK` (or its per-pack `content("<Old>")` name) becomes
     `"<Pack>"`; add to the world's KIT (and TALENTS) the abilities the pack recommends that the world's character
     lacks (the replay's `kit` list), and MAP entries for any "unmapped key". `grep -rln '"<Old>"' tests/` and repoint
     every spec that selects the retired list to `"<Pack>"`; a spec asserting the old list's own text (its lines, its
     description) is deleted with it, and its focus assertions (`r.focus > 0`) keep holding through P9.3.
  5. Settings no remaining list or class Lua reads (`grep -n 'settings\.<name>' src/Hekili_<Class>/`): delete their
     `RegisterSetting` and the tests that set them (only when the class's last old list reading them is retired).
  6. `make packs`, then the Gate. The retired spec's ` solo: ` lines change: they must still pass every assertion
     (agreement, react, refusals, health, focus). Record the new lines in `/tmp/wowsims/solo-base.txt`, the SDD ledger
     and `docs/dev/layout.md` (replacing the old ones, naming the pack). Any other line changing is a bug.
- **P10 Commit** (one commit per pack, or per swap):

```bash
git add tools/wowsims/specs tests/Forever/wowsims src/Hekili_<Class> tests/Forever docs/dev/layout.md
git commit -m "feat(<class>): <Pack>, translated from wowsims/forever; replay floor X, live from level L

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Arms (wowsims.com), the first pack end to end (L)

**Files:**
- Create: `tools/wowsims/specs/warrior_arms.lua`, `tests/Forever/wowsims/warrior_arms.{json,log}`,
  `tests/Forever/wowsims/learn_warrior.lua`, `src/Hekili_Warrior/APLs/Arms (wowsims.com).simc` (generated),
  `tests/Forever/wowsims_warrior_spec.lua`
- Modify: `src/Hekili_Warrior/Warrior.lua` (Slam with Improved Slam, the wowsims settings, NewClass package,
  RetirePacks), `src/Hekili_Warrior/APLs/packs.lua`, `tests/Forever/helpers/warrior_world.lua` (PACK, KIT, TALENTS),
  `tests/Forever/warrior_spec.lua`, the specs naming `"Arms"` as a pack, `tests/Forever/fixtures/arms_recs_seeds1-3.lua`
  (re-recorded), `docs/dev/layout.md`
- Delete: `src/Hekili_Warrior/APLs/Arms.simc`

**Interfaces:**
- Consumes: Tasks 1-4. `ww.SPEC` 100011 (Arms), `ww.PACK`.
- Produces: the Arms recipe (the template the other recipes copy); `spec:RetirePacks({ "Arms" })` in Warrior.lua
  (Task 6 extends it); the settings `wowsims_recklessness`, `wowsims_stance_dance`, `wowsims_hamstring_weave` for
  `"arms"`.

- [ ] **Step 1: P1, the recipe** `tools/wowsims/specs/warrior_arms.lua`:

```lua
-- tools/wowsims/specs/warrior_arms.lua (wowsims packs plan, Task 5): Arms (wowsims.com)'s wowsims/forever request and
-- translation. Values from wowsims/forever (MIT) ui/specs/warrior/dps/presets.ts (ArmsTalents, DefaultOptions,
-- OtherDefaults) at the pin; gear p1_arms (the spike's, a level 60 set; the presets' default is the Fury build).
-- Disagreements worked (P7): <filled at Step 6>.
return {
    class = "WARRIOR",
    pack = "Arms (wowsims.com)",
    spec = "arms",
    name = "Arms",
    talentTree = "warrior",
    apl = "ui/specs/warrior/dps/apls/arms.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassWarrior",
        gear = "ui/specs/warrior/dps/gear_sets/p1_arms.gear.json",
        talentsString = "30325213132515201-0505-2",
        specKey = "dpsWarrior",
        options = {
            classOptions = {
                queueDelay = 250,
                startingRage = 50,
                useBattleShout = true,
                defaultStance = "WarriorStanceBerserker",
                hasBsT2 = true,
                stanceSnapshot = true,
            },
        },
        profession1 = "Engineering",
        profession2 = "Blacksmithing",
        reactionTimeMs = 100,
        distanceFromTarget = 25,
    },
    executePhase = "execute_phase",
    map = {},
    focus = { overpower = 1, rend = 2, slam = 2 }, -- the retired Arms list's tiers (P9.3)
    leveling = {},
}
```

- [ ] **Step 2: P2-P4.** `make wowsims-learn CLASS=WARRIOR`, `make wowsims-export SPEC=warrior_arms`,
  `make wowsims-packs`. Expected omissions (the spike's): the engineering and trinket items (no such gear), the
  potions (`other OtherActionOffensivePotion`, `...ResourcePotion`), `castAllStatBuffCooldowns`, the hidden entries;
  `aura 1282733` must NOT be omitted: if the Warrior kit has no aura for Forever's Overpower window, add one in P6
  (`overpower_window = { id = 1282733, duration = 5 }` in the class's auras, with its DB2 duration from
  `wowdb spell 1282733`).

- [ ] **Step 3: P5.** `packs.lua` gets `"Arms (wowsims.com)"` and `["Arms (wowsims.com)"] = "arms"`. Settings, for
  `"arms"`: `wowsims_recklessness` false, `wowsims_stance_dance` false, `wowsims_hamstring_weave` true (the header's
  `# Setting` lines decide; these are the pin's).

- [ ] **Step 4: P6, the Arms kit gaps (the spike's).** Improved Slam (12862, 2 ranks): the Forever DB2 gives rank 1
  only (`wowdb effects 12862`: misc 10, the cast time, -500 ms; misc 11, the cooldown, -3000 ms; rank 2, 12330, has no
  effects), and the wowsims log of the 2/2 build shows `Casting {SpellID: 11605} (... Cast Time = 1s, GCD = 1s ...)`
  with Slams 16.5 s or more apart. The in-game rank 2/2 tooltip (user, 2026-10-19): "Reduces the global cooldown and
  cast time of your Slam ability by 0.50 sec. In addition, Slam no longer interrupts or delays your melee swing and
  Slam's cooldown is reduced by 3.0 sec." So with the talent: cast 1.0 s, GCD 1.0 s, cooldown 15 s, and the Slam
  handler must NOT reset the swing timer (today's Slam models the swing delay; keep that only when the talent is off).
  Add `gcd = function() return talent.improved_slam.enabled and 1.0 or 1.5 end` beside `cast` below and gate the
  handler's swing reset on `not talent.improved_slam.enabled`; the spec below gets one more `it` for each. In
  `tests/Forever/warrior_spec.lua`, in the block that evaluates ability fields under a talent state, add:

```lua
    it("casts Slam in 1.0 s on a 15 s cooldown with Improved Slam (Forever DB2 12862)", function()
        local env = loadWarrior.env(w)
        env.talent.improved_slam = { rank = 0, enabled = false }
        assert.are.same({ 1.5, 18 }, { env.ability("slam").cast, env.ability("slam").cooldown })
        env.talent.improved_slam = { rank = 2, enabled = true }
        assert.are.same({ 1.0, 15 }, { env.ability("slam").cast, env.ability("slam").cooldown })
    end)
```
  (Use the file's existing helper for evaluating an ability's function fields under a talent state; if it is not
  `env.ability(...)`, follow it.) In `Warrior.lua`'s `slam = {`, replace `cast = 1.5,` and `cooldown = 18,` with

```lua
        -- Improved Slam (12862, Forever DB2): the cast 0.5 s and the cooldown 3 s shorter (wowsims's log: 1 s casts)
        cast = function()
            return talent.improved_slam.enabled and 1.0 or 1.5
        end,
        cooldown = function()
            return talent.improved_slam.enabled and 15 or 18
        end,
```
  and drop the talents line's `-- effect unmodelled`. Run `.lua/bin/busted tests/Forever/warrior_spec.lua`: PASS.
  Gate (`TASK=5a`): the Arms world's build has no Improved Slam (`ww.TALENTS`), so no ` solo:` line moves; if one
  does, stop and debug.

- [ ] **Step 5: P7, the replay gate.** Create `tests/Forever/wowsims_warrior_spec.lua` (the P7 skeleton) with the
  Arms block:

```lua
local ww = require("Forever.helpers.warrior_world")
-- Forever's Overpower window (aura 1282733, 5 s): wowsims's Overpower condition; the client cannot list it, so the
-- replay keeps it in the truth (`hidden`) and answers Overpower's usability from it.
local ARMS = {
    kit = { "spearing_strike", "berserker_rage" },
    requires = {
        overpower = function(_, e)
            return e.auras[1282733] ~= nil and e.form == 1, "no window"
        end,
    },
}
local ARMS_REPLAY = { hidden = { [1282733] = true }, procs = {} }
```
  and the two `it` blocks from P7 with `content("warrior_arms", ww, "Arms (wowsims.com)", level, ARMS)`,
  `"warrior_arms"`, `ARMS_REPLAY`, brackets `{ 10, 40, 60 }`. First run with floor 0. The plan writer's dry run of
  this pipeline (pre-per-spec base, no learn table, Improved Slam not yet modelled) measured
  `decisions on-GCD 0.821 (67) top [sunder_armor -> rend 3; execute -> overpower 1; execute -> sunder_armor 1]`;
  expect about that, and a floor at the truncated value of your run. If the line's top disagreement is `* -> berserker_stance`, the translator's
  stance guard or the toggle default is wrong (stance dancing is off): fix it, do not raise the floor around it.
  Expected classifications to write into the recipe's header: Rend's 1.5 s boundary between our tick and wowsims's
  cast (replay limit, the 0.2 s tick); Sunder after its fall-off (wowsims lets five stacks drop and rebuilds: quirk,
  its Refresh group is hidden).

- [ ] **Step 6: P8, leveling.** The brackets 10, 40 and 60. The dry run (same conditions as Step 5) measured the
  untouched translation at `live L10 14.4 s`, `L40 15.4 s`, `L60 9.4 s` (the 60 figure is wowsims's own: Heroic
  Strike waits for 90 rage), so `LIVE60 = 9.4`. These recipe `leveling` lines brought it to `L10 5.4 s`, `L40 5.6 s`,
  `L60 9.4 s` with the replay line unchanged (Mortal Strike is known at 48 in the build's talent order, so they cover
  10-47):

```lua
    leveling = {
        "heroic_strike,use_off_gcd=1,if=!action.mortal_strike.known&rage.current>=30",
        "thunder_clap,if=!action.mortal_strike.known&!debuff.thunder_clap.up&rage.current>=40",
        "sunder_armor,if=!action.mortal_strike.known",
    },
```
  Start from them; with the real learn table (fewer abilities at 10) re-measure, adjust, and keep the 60 line and the
  replay floor unchanged.

- [ ] **Step 7: P9, the swap.** Delete `Arms.simc`; `packs.lua` -> `packs = { "Arms (wowsims.com)", "Fury",
  "Protection" }`, `specs` without `Arms`; NewClass `arms` entry `package = "Arms (wowsims.com)"`;
  `spec:RetirePacks({ "Arms" })` after the RegisterPack blocks. `warrior_world.lua`: `M.PACK = "Arms (wowsims.com)"`,
  `"spearing_strike"` and `"berserker_rage"` into `M.KIT` (sorted), `M.TALENTS[1310222] = 1` (Spearing Strike, the
  Arms talent the wowsims build takes). The world's Overpower stays its dodge model (the loop's own world rolls dodges;
  only the replay reads the window aura). Repoint the specs: `grep -rln '"Arms"' tests/Forever` (expect
  `alts_spec`, `focus_tier_options_spec`, `known_cache_spec`, `display_resolve_spec`, `registry_spec`,
  `driver_alloc_spec`, `settings_spec`, `display_style_spec`, `make_pack_spec`, `style_options_spec`, `output_spec`,
  `warrior_spec`, `minor_cooldowns_spec`; read each use: a pack selection becomes `"Arms (wowsims.com)"` or `ww.PACK`;
  the make_pack spec's expected `{ Arms = "WARRIOR:arms", ... }` becomes
  `{ ["Arms (wowsims.com)"] = "WARRIOR:arms", Fury = ..., Protection = ... }`). Re-record the Arms recommendations
  fixture: `ARMS_RECS=record .lua/bin/busted tests/Forever/arms_recs_spec.lua`, then run it again without the variable:
  PASS. Settings: keep every Arms setting the Fury or Protection list still reads; delete none yet (Task 6 does, after
  the last Warrior list). Gate (`TASK=5`): only `Arms solo:` lines change (3-fight x3 and the 20-fight in
  `make test-loop`, the party report in `make test-party`); record them.

- [ ] **Step 8: P10, commit** (two commits: Steps 1-6, then the swap):

```bash
git add tools/wowsims/specs/warrior_arms.lua tests/Forever/wowsims "src/Hekili_Warrior" tests/Forever/wowsims_warrior_spec.lua tests/Forever/warrior_spec.lua
git commit -m "feat(warrior): Arms (wowsims.com) from wowsims/forever's Arms APL; Improved Slam modelled

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git add -A src/Hekili_Warrior tests docs/dev/layout.md
git commit -m "feat(warrior): Arms (wowsims.com) is the Arms priority; the hand-built Arms list retired

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Fury and Protection (wowsims.com) (M)

**Files:** recipes `tools/wowsims/specs/warrior_fury.lua`, `warrior_protection.lua`; their requests and logs; the two
generated `.simc`; `tests/Forever/wowsims_warrior_spec.lua`; `Warrior.lua`, `APLs/packs.lua`, `warrior_world.lua`;
specs naming `"Fury"`/`"Protection"` as packs (`fury_spec`, `settings_spec`, `focus_tier_options_spec`, ...); delete
`Fury.simc`, `Protection.simc`.

**Interfaces:** Consumes Task 5 (the recipe template, `content`, the Warrior spec file, `RetirePacks`).

- [ ] **Step 1: P1 recipes.** Fury: `name = "Fury"`, `apl = "ui/specs/warrior/dps/apls/fury.apl.json"`,
  `gear = "ui/specs/warrior/dps/gear_sets/p1_fury.gear.json"`, `talentsString = "30305013002-25053005052010501"`
  (FuryTalents), `specKey = "dpsWarrior"`, the same `classOptions` as Arms (presets.ts DefaultOptions),
  Orc, Engineering/Blacksmithing, `executePhase = "execute_phase"`,
  `focus = { victory_rush = 1, overpower = 1, revenge = 1, heroic_strike = { 1, 2 }, cleave = { 1, 2 } }` (the retired
  Fury list's tiers in order). Protection: `name = "Protection"`, `apl =
  "ui/specs/warrior/protection/apls/default.apl.json"`, `gear = "ui/specs/warrior/protection/gear_sets/prebis.gear.json"`
  (spec.ts default), `talentsString = "35300003-05-050531120300021351"`, `specKey = "protectionWarrior"`, `options`
  from `ui/specs/warrior/protection/presets.ts` `DefaultOptions` (line ~93: `startingRage = 0`,
  `defaultStance = "WarriorStanceDefensive"`, and the rest as written there), Orc, Engineering/Blacksmithing,
  `focus = { shield_bash = 1, mocking_blow = 1, taunt = 1 }`.
- [ ] **Step 2: P3-P5** for both. Fury's toggles at the pin: `wowsims_recklessness` false, `wowsims_rend_weave` true,
  `wowsims_hamstring_weave` true: register each for `"fury"` (the Arms registrations stay `"arms"`; same key, own
  default per spec).
- [ ] **Step 3: P6.** Expect: Fury dual wield (the world's `WORLD.weapons` is the two-hander: for the Fury content give
  `ws.content` a base whose `WORLD.weapons` has a main and an off hand from the log's swings, `{ { 100, 180, mh }, { 60,
  110, oh } }` with the periods from the first `Tag: 1` and `Tag: 2` swing pairs), Bloodthirst and Whirlwind under
  Berserker Stance, Execute; Protection: Shield Slam, Revenge's window (a block, dodge or parry of the target's swing:
  the replay does not replay the target's swings, so Revenge's usability comes from the log: list its window aura as
  `hidden` if wowsims logs one, else classify "replay limit: no target swings" and expect a lower floor).
- [ ] **Step 4: P7/P8** with brackets `{ 10, 40, 60 }` for both; Protection's mob in the live gate is the world's
  (it swings at us: Revenge works there).
- [ ] **Step 5: P9 swap** each: retire `"Fury"`, `"Protection"` (`spec:RetirePacks({ "Arms", "Fury", "Protection" })`);
  then P9.5: the Warrior settings no remaining list reads (`adaptive_queueing_enabled`, `execute_queueing_enabled`,
  `ww_min_enemies`, `ww_cd_diff`, `hamstring_threshold`, `hamstring_cd_diff`, `debuff_sunder_*`,
  `debuff_demoshout_enabled`, `maintain_thunder_clap`, `rage_cap_threshold`, `hs_threshold`, `cleave_threshold`,
  `prot_*`, `challenging_shout_loose`, any other: grep each in `src/Hekili_Warrior/` first) are deleted with their
  tests, and the class Lua that only served them (`should_hs`, `should_cleave` state expressions) only if nothing
  reads them. Gate: the Warrior lines that change are only Fury's and Protection's if they have belief gates (they
  have none at the time of writing: then no line changes).
- [ ] **Step 6: P10** commits.

---

### Task 7: Druid: Feral, Guardian and Balance (wowsims.com) (L)

**Files:** recipes `druid_feral.lua`, `druid_guardian.lua`, `druid_balance.lua`; logs; `learn_druid.lua`; three
generated `.simc`; `tests/Forever/wowsims_druid_spec.lua`; `Druid.lua`, `APLs/packs.lua`,
`tests/Forever/helpers/druid_loop_world.lua`; `loop_druid_spec.lua` and the specs naming the old packs; delete
`Feral.simc`, `Guardian.simc`, `Balance.simc`.

- [ ] **Step 1: P1.** All Night Elf (`RaceNightElf`), `talentTree = "druid"`.
  - Feral: `apl = "ui/specs/druid/feralcat/apls/default.apl.json"` (Monocat), `gear =
    "ui/specs/druid/feralcat/gear_sets/pre_raid.gear.json"`, `talentsString = "050022-55000032021031212051-054"`
    (CatTalents), `specKey = "feralCatDruid"`, `options = { assumeBleedActive = true }` (presets.ts DefaultOptions),
    Engineering/Enchanting, `focus = { shred = 1, claw = 1, rip = 1, rake = 2, innervate = 2 }`.
  - Guardian: `apl = "ui/specs/druid/feralbear/apls/default.apl.json"`, `gear =
    "ui/specs/druid/feralbear/gear_sets/default.gear.json"`, `talentsString =
    "0500220000000000-55200322120132012551-0000000000000000"` (BearTalents), `specKey = "feralBearDruid"`, `options`
    from feralbear presets.ts DefaultOptions (~l.116, `startingRage = 0` ...), Engineering/Enchanting,
    `focus = { lacerate = 2 }`.
  - Balance: `apl = "ui/specs/druid/balance/apls/default.apl.json"`, `gear =
    "ui/specs/druid/balance/gear_sets/prebis.gear.json"`, `talentsString = "5532220115501351--505"`, `specKey =
    "balanceDruid"`, `options` from balance presets.ts DefaultOptions (~l.57), Enchanting/Tailoring,
    `focus = { moonfire = 2, insect_swarm = 2, starfire = 1 }`.
- [ ] **Step 2: P2-P6.** Expected: Feral's two `strictSequence` entries are omitted (rule 2): translate each by hand
  into the recipe's `leveling`? No: a sequence is a level-60 choice; record it as a translation gap in the recipe
  header and accept the floor it costs, or (if the top disagreement) add a later rule to `apl.lua` for
  `strictSequence` = its first action with the sequence's condition, with a test in `wowsims_apl_spec.lua`. Feral's
  energy and the cat's combo points: the Druid world's `res`/`regen` must reach the replay world (`ws.content`'s
  `WORLD` falls through to the world's; check `W.rates[3]` is set in the replay with a one-line assertion in the
  spec). Shifting Power (+40 energy, Forever): mapped if the kit has it. Guardian: rage from damage taken is in the
  log's after-values. Balance: casts at completion (no cast bars: replay limit; the decision cycle sits before each
  Casting line, so a chain cast is scored after its predecessor completed).
- [ ] **Step 3: P7/P8.** Brackets: Feral `{ 20, 40, 60 }` (Cat Form at 20), Guardian `{ 10, 40, 60 }`, Balance
  `{ 10, 40, 60 }`. Replay knobs: `procs` for Omen of Clarity's or Shred's procs if they show as mapped casts.
- [ ] **Step 4: P9** each; `spec:RetirePacks({ "Feral", "Guardian", "Balance" })`; the Druid gates (`loop_druid_spec`,
  Guardian reported, the focus assertions) move onto the wowsims packs; Druid settings no list reads are deleted.
- [ ] **Step 5: P10.**

---

### Task 8: Rogue: Assassination, Combat and Subtlety (wowsims.com) (M)

**Files:** recipes `rogue_assassination.lua`, `rogue_combat.lua`, `rogue_subtlety.lua`; logs; `learn_rogue.lua`;
three generated `.simc` (one APL, three builds: the texts may be identical, which is expected); 
`tests/Forever/wowsims_rogue_spec.lua`; `Rogue.lua`, `APLs/packs.lua`, `rogue_world.lua`; `loop_rogue_spec.lua`;
delete `Assassination.simc`, `Combat.simc`, `Subtlety.simc`.

- [ ] **Step 1: P1.** All: `apl = "ui/specs/rogue/dps/apls/default.apl.json"` (Direct APL), `talentTree = "rogue"`,
  `specKey = "rogue"`, `options` from rogue presets.ts `DefaultOptions` (~l.163), the race from rogue spec.ts
  `defaults`, professions from its presets. Builds: Assassination `00532310151501031-302303202014` (Asn Muti, gear
  `ui/specs/rogue/dps/gear_sets/p1_muti.gear.json`); Combat `005323101012-32030320201515231` (Combat SS, the default,
  `p1_slowmh.gear.json`); Subtlety `005323101014--4323200300013211501` (Subtlety Hemo, `p1_bssub.gear.json`).
  `focus`: all three `{ kick = 1, expose_armor = 2, slice_and_dice = 1 }`, Subtlety adds `ambush = 1, rupture = 2`.
- [ ] **Step 2: P2-P6.** The APL's `Use X` variables are constants: inlined and folded (rule 1). Its
  `strictSequence` (Maintain Expose) as in Task 7. Combo points plain on Forever (UnitPower 4): the world's res.
- [ ] **Step 3: P7/P8.** Brackets `{ 10, 40, 60 }` each. Stealth openers: the replay's form IDs (Stealth as a form if
  the world lists it in `forms`).
- [ ] **Step 4: P9** each; `spec:RetirePacks({ "Combat", "Assassination", "Subtlety" })`; `rw.Combat` etc. content
  names stay, their `PACK` becomes the wowsims one.
- [ ] **Step 5: P10.**

---

### Task 9: Paladin: Retribution and Protection (wowsims.com) (M)

**Files:** recipes `paladin_retribution.lua`, `paladin_protection.lua`; logs; `learn_paladin.lua`; the generated
`.simc`; `tests/Forever/wowsims_paladin_spec.lua`; `Paladin.lua`, `APLs/packs.lua`, `paladin_world.lua`;
`loop_paladin_spec.lua`; delete `Retribution.simc`, `Protection.simc`.

- [ ] **Step 1: P1.** Human, `talentTree = "paladin"`. Retribution: `apl =
  "ui/specs/paladin/retribution/apls/twist_of_light.apl.json"` (spec.ts default), `gear =
  "ui/specs/paladin/retribution/gear_sets/twist_of_light.gear.json"`, `talentsString = "55003003--05225331101330321"`,
  `specKey = "retributionPaladin"`, options from presets.ts DefaultOptions (~l.32), Engineering/Blacksmithing,
  `focus = { hammer_of_wrath = 1, seal_of_command = 1, seal_of_righteousness = 1, consecration = 2, exorcism = 2 }`.
  Protection: `apl = "ui/specs/paladin/protection/apls/default.apl.json"`, `gear =
  "ui/specs/paladin/protection/gear_sets/default.gear.json"`, `talentsString = "50003-0530313321301531-5022"`,
  `specKey = "protectionPaladin"`, options (~l.25), Engineering/Enchanting, `focus = { seal_of_fury = 2, holy_shield = 2 }`.
- [ ] **Step 2: P2-P6.** Seal procs (Seal of Command's hit) logged as Casting lines under the seal's own ID would be
  procs: list them in the replay knobs' `procs` (Review Focus 2) after checking `grep 'Casting {SpellID: <id>}'`
  against the seal's own casts. Mana and the five-second rule: the world's `fsr` reaches the replay world (`wo.fsr`).
- [ ] **Step 3: P7/P8.** Brackets `{ 10, 40, 60 }`.
- [ ] **Step 4: P9**; `spec:RetirePacks({ "Retribution", "Protection" })`.
- [ ] **Step 5: P10.**

---

### Task 10: Shaman: Enhancement (wowsims.com) (S)

**Files:** recipe `shaman_enhancement.lua`; log; `learn_shaman.lua`; the generated `.simc`;
`tests/Forever/wowsims_shaman_spec.lua`; `Shaman.lua`, `APLs/packs.lua`, `shaman_world.lua`; `loop_shaman_spec.lua`;
delete `Enhancement.simc`.

- [ ] **Step 1: P1.** `build = "ui/specs/shaman/enhancement/builds/testing.build.json"` (its gear, the presets'
  DefaultGear) with `apl = "ui/specs/shaman/enhancement/apls/default.apl.json"` (the default rotation replaces the
  build's), `talentTree = "shaman"`, `focus = { grace_of_air_totem = 2, strength_of_earth_totem = 2, fire_nova = 1,
  lightning_shield = 2, searing_totem = 2, lightning_bolt = 1, flame_shock = 2 }`. (The build's talents are its
  `talentsString`; presets.ts's StandardTalents `053503102-053030031005112251` should match: if not, set the
  player's string in the recipe with a `talentsString` override field and add `p.talentsString =
  r.talentsString or p.talentsString` to `M.request` with a test.)
- [ ] **Step 2: P2-P6.** Totems: `totemRemainingTime` -> `totem.<element>.remains` (check the world's totem slots).
  Windfury procs as Casting lines: `procs`.
- [ ] **Step 3: P7/P8.** Brackets `{ 10, 40, 60 }`.
- [ ] **Step 4: P9**; `spec:RetirePacks({ "Enhancement" })`.
- [ ] **Step 5: P10.**

---

### Task 11: Hunter: Beast Mastery, Marksmanship and Survival (wowsims.com) (M)

**Files:** recipes `hunter_beast_mastery.lua`, `hunter_marksmanship.lua`, `hunter_survival.lua`; logs;
`learn_hunter.lua`; three generated `.simc`; `tests/Forever/wowsims_hunter_spec.lua`; `Hunter.lua`,
`APLs/packs.lua`, `hunter_world.lua` (Day 5's; its export names from its last lines); the Hunter loop spec; delete
the three hand-built lists (Day 5's names: `BeastMastery`, `Marksmanship`, `Survival`).

- [ ] **Step 1: P1.** All: `apl = "ui/specs/hunter/dps/apls/default.apl.json"` (Melee Weave, the presets' default),
  `gear = "ui/specs/hunter/dps/gear_sets/p1.gear.json"`, Orc, Engineering/Blacksmithing, `specKey = "hunter"`,
  `options` = presets.ts `DefaultOptions` (= `NoPetOptions`: no pet), `talentTree = "hunter"`. Builds: BM
  `5320001505101251-0053250001-4` (BM Weave), MM `-205305031150001-5502000300502201` (MM Weave), SV
  `-00530501114-550200030050220151` (SV Weave). `focus` from the retired lists' tiers (P9.3).
- [ ] **Step 2: P2-P6.** The weave APL moves in and out of melee (`move`, `unitDistance`: rule 2, omitted). Expect a
  low floor from that; classify as "translation gap: no positions" in the recipe. Auto Shot is `OtherID` (not ours: no
  decision). Ranged swings: `autoType` other than `MainHandAuto` is unsupported (rule 2).
- [ ] **Step 3: P7/P8.** Brackets `{ 10, 40, 60 }`.
- [ ] **Step 4: P9**; retire the three lists.
- [ ] **Step 5: P10.**

---

### Task 12: Mage: Arcane and Fire (wowsims.com) (M, after Day 6)

**Files:** recipes `mage_arcane.lua`, `mage_fire.lua`; logs; `learn_mage.lua`; generated `.simc`;
`tests/Forever/wowsims_mage_spec.lua`; `Mage.lua`, `APLs/packs.lua`, the Mage world; retire Day 6's Arcane and Fire
lists. **Frost keeps Day 6's own list** (wowsims has no Frost APL; FFB is a Fire build).

- [ ] **Step 1: P1.** `talentTree = "mage"`, `specKey = "mage"`, `options` mage presets.ts DefaultOptions (~l.31),
  gear `ui/specs/mage/dps/gear_sets/p1Arcane.gear.json` for both, race from mage spec.ts `defaults`, professions from
  its presets. Arcane: `apl = "ui/specs/mage/dps/apls/arcane.apl.json"`, `talentsString =
  "0552205003100311531-03-0515"`. Fire: `apl = "ui/specs/mage/dps/apls/deepFire.apl.json"`, `talentsString =
  "0502205-23550000130135031-005"`.
- [ ] **Step 2: P2-P10** (brackets `{ 10, 40, 60 }`; `channelSpell` Evocation translates as its key).

---

### Task 13: Warlock: Affliction, Demonology and Destruction (wowsims.com) (M, after Day 7)

**Files:** recipes `warlock_affliction.lua`, `warlock_demonology.lua`, `warlock_destruction.lua`; logs;
`learn_warlock.lua`; generated `.simc`; `tests/Forever/wowsims_warlock_spec.lua`; `Warlock.lua`, `APLs/packs.lua`,
the Warlock world; retire Day 7's lists.

- [ ] **Step 1: P1.** Each a `build` (the build file holds talents, demons, gear and rotation): Affliction
  `ui/specs/warlock/dps/builds/aff_wrack.build.json`, Demonology `demo_fire_brand.build.json` (spec.ts default),
  Destruction `destro.build.json`; `talentTree = "warlock"`.
- [ ] **Step 2: P2-P10** (brackets `{ 10, 40, 60 }`; pets' casts are not ours: no decisions).

---

### Task 14: Priest Shadow and Holy (Smite), Shaman Elemental (wowsims.com) (M, after Day 7)

**Files:** recipes `priest_shadow.lua`, `priest_holy.lua`, `shaman_elemental.lua`; logs; `learn_priest.lua`;
generated `.simc`; `tests/Forever/wowsims_priest_spec.lua`, `wowsims_shaman_spec.lua`; `Priest.lua`, `Shaman.lua`,
their `packs.lua` and worlds; retire Day 7's Shadow, Smite and Elemental lists.

- [ ] **Step 1: P1.** Shadow: `build = "ui/specs/priest/dps/builds/testing.build.json"`; Holy (the Smite pack on the
  Holy tree, per-spec plan): `build = "ui/specs/priest/dps/builds/smite_testing.build.json"`, `spec = "holy"`,
  `pack = "Holy (wowsims.com)"`; Elemental: `build = "ui/specs/shaman/elemental/builds/testing.build.json"`,
  `spec = "elemental"`. `talentTree` `"priest"` / `"shaman"`.
- [ ] **Step 2: P2-P10** (brackets `{ 10, 40, 60 }`).

---

### Task 15: docs and the check tier (S)

**Files:** `docs/dev/layout.md`, `docs/dev/architecture.md`, `docs/superpowers/plans/2026-10-18-class-completion.md`

- [ ] **Step 1: `docs/dev/layout.md`.** A "wowsims packs" subsection under Checks: the pipeline (recipe ->
  `make wowsims-export` -> checked-in request and log -> `make wowsims-packs` -> `make packs`), the pin and how to move
  it (bump `M.PIN`, re-export every recipe, re-measure every floor), `make wowsims-cli` prerequisites (Go, protoc,
  protoc-gen-go), the two gates (`#slow #wowsims`: in `make check`, alone in `make test-wowsims`), the floor policy
  (the first clean run, truncated; raised when content improves, never lowered), the leveling rule and
  `tools/check_pack_levels.lua`, the replay's limits (no cast bars, landing lag or target swings; zero-lag casts at
  completion; the execute phase by time), and every pack's current `wowsims:` and `live` lines. Replace the retired
  lists' gate lines with the wowsims packs' (done per task; check).
- [ ] **Step 2: `docs/dev/architecture.md`** §6 (the pack pipeline): generated wowsims packs, their recipes, the
  translation rules (Task 4's list), `RetirePacks`.
- [ ] **Step 3: The class-completion plan** (Days 6-7 tasks): each new class pack's priorities are its wowsims packs
  (this plan's Tasks 12-14); a hand-built list only for a spec with no wowsims APL (Frost).
- [ ] **Step 4: Verify and commit**

Run: `make check && make test-wowsims`
Expected: PASS.

```bash
git add docs
git commit -m "docs: the wowsims.com packs (pipeline, pin, gates, leveling rule)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Whole-branch review (superpowers:requesting-code-review / `/ponytail-review`) against this plan, the binding
  user changes and the Review Focus; fix findings in the owning task's files.
- [ ] `make check` green; `make test-wowsims` green; the gate commands with `TASK=final`: every difference from the
  Task 1 base is a retired list's lines, each recorded in the ledger with its wowsims pack's new line.
- [ ] `git diff --stat origin/forever -- tests/Forever/fixtures` lists only `arms_recs_seeds1-3.lua`.
- [ ] Every `src/Hekili_*/APLs/packs.lua` lists one pack per supported spec, each "(wowsims.com)" except Mage Frost.

### In game (user: Warrior, Rogue and Druid characters; `/reload` after the update)
1. `/hekili` -> Priorities: each spec shows one priority, "<Spec> (wowsims.com)", selected; the old Arms/Fury/...
   entries are gone (a renamed copy you made yourself stays).
2. The pack names with parentheses and a dot display and select normally in the options tree (if not, report the
   panel's error; the name is the user's binding choice).
3. A low-level alt (any class, level 10-20): the displays recommend something every few seconds in combat with
   resources up; no Lua errors.
4. Warrior Arms at 60: Mortal Strike, Overpower in Battle Stance, Slam right after a swing, Spearing Strike; Heroic
   Strike only at high rage; no stance-dance icon (wowsims's Stance Dance is off: "Stance Dance (wowsims.com)" in the
   Arms options turns it on).
5. Report the Snapshot's first lines (`VSCopy`) if a spec shows no priority.

## Self-review (done while writing)
- Brief coverage: export tool and pin (Task 2), replay world with one injection and the decision metric (Task 3),
  translation rules (Task 4) and Arms with its kit gaps (Task 5: Spearing Strike in the replay kit and the world's
  KIT at the swap, Improved Slam's cast and cooldown, the Overpower window aura), one task per remaining spec batched
  by class (Tasks 6-14), docs and `make test-wowsims` in the slow tier (Tasks 2, 15). The brief's T3 is split into
  Tasks 4 (rules, translator) and 5 (Arms) because a reviewer can reject one and accept the other; Task 1
  (`RetirePacks`) comes from the user's later changes.
- User changes: the wowsims pack is each spec's default (P9.2 `package`), the old lists retired with their gates moved
  (P9, Task 1 for saved profiles), the leveling rule (Task 4 rule 6, the static check, P8 brackets with the liveness
  gate; the floor applies at 60 only).
- Names used across tasks: `replay.parse`, `replay.new`, `R.world`, `R.next`, `R.decisions`, `R.pull`, `R.duration`,
  `R.targetLevel`, `R.speed`, `loop.replay`, `loop.summary(...).decisions`, `m.dec`, `run.dec`, `ws.content`,
  `ws.gate`, `ws.live` (limit in seconds), `ws.header`, `ws.log`, `ws.learn`, `apl.context`, `apl.translate`, `apl.write`, `apl.snake`,
  `levels.unguarded`, `levels.file`, `ex.PIN`, `ex.OUT`, `ex.talents`, `ex.request`, `ex.export`, `ex.learn`,
  `ex.recipe`, `ex.ids`, `kit:RetirePacks`, `class.retiredPacks`.
- Known limits: the replay has no cast bars, landing lag or target swings (Revenge's and the casters' scores carry
  them); one seed, no buffs (`auraIsKnown` false); the leveling gate's talent order (dominant tree first, then the
  string's order) approximates how a player levels; the learn table treats IDs the DB2 lacks as level 1.
