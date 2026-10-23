# Unit Registry and Tickets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attribute every own outcome (white swings, strikes, instants, projectiles, DoT ticks) to the commit that made it,
on the GUID it was sent to, through one unit registry that every `UNIT_COMBAT` consumer reads and one generic ticket
model, so projectile landings, post-clear killing blows and swaps pay their own commit and every caster's floors rise.

**Architecture:** A new Source, `Game/State/Sources/Units.lua`, is the only code that turns a token into a GUID: it binds
tokens to unit slots, resolves and deduplicates each `UNIT_COMBAT` and dispatches it to `OnRow` listeners, and owns unit
lifetimes and deaths. A pure ticket pool (`Game/Events/Tickets.lua`) opens one ticket per commit and pays it by the
consumption order; the matching rules live once in `Game/Events/Kinds.lua` (FRAME, FLIGHT, STRIKE, TICKS, CHANNEL,
UNMAPPED) and `Game/Events/Melee.lua` (the swing LR, moved unchanged out of Rows). `Game/Events/Rows.lua` shrinks to
the consumer that opens tickets on commits and turns payments into combat-log rows and staged observations.

**Tech Stack:** Lua 5.1 (WoW), busted, luacheck, StyLua, the combat harness (`tests/Game/harness/`), python3 sqlite3
for the dev-only DB2 check.

**Spec:** `docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md` (binding; 37 decisions). Sections are
cited as "spec §N".

## Global Constraints

- Core/pack boundary: nothing under `src/Hekili/Game`, `src/Hekili/Engine/Schema` or `tests/Game/harness` names a class, spell, aura, form or spell ID (`tests/boundary_spec.lua`); schools are a game concept and live in core as `ns.SCHOOL`, published as `Hekili.SCHOOL` (added to the boundary's `PUBLIC` list).
- Secret safety: every client value reaches a decision only through `S.Plain(api, v)`; a nil from `Plain` is "no answer", never a value; `UnitGUID` on a hostile token is read only in `Units.lua` (`tests/Game/State/secrets_spec.lua` and the grep step of Task 3).
- No allocation in recurring paths: no table, closure, `{...}` or string built after load in event handlers, `OnRow`, `OnGone`, `L.OnTick` or the polls (`tests/Game/State/alloc_spec.lua`, `tests/Game/harness/alloc_spec.lua`).
- Pools: `UNIT_CAP` = 64 unit slots; 44 token indices (target, focus, nameplate1-40, softenemy, softinteract); `TICKETS` = 32 (16 at planning; owner ruling 2026-10-22, multi-dotting); `LAG_CAP` = 16 (GUID, speed) lag records; a dedupe ring of `DUP_N` = 4 groups with a 4 x 44 token bitset.
- Times: `DUP_WINDOW` = 0.005 s; `GRACE` = 0.1 s (a floor while held); `KILL_TELL` = 0.010 s; `TOL` = 0.15 s; `CLOSE` = 7 yd/s; `CROWD` = 5 s (the crowd gate, spec §3.3.1); `SAME_FRAME` 0.05 s, `CAST_WINDOW` 0.2 s, `STRIKE_WINDOW` 0.2 s, `L.UNMAPPED_WINDOW` 2 s (unchanged); TICKS band +-0.1 s; amount band `[0.6 x lo, 1.6 x hi]` after 3 clean wounds.
- School enum (core, `ns.SCHOOL`): `physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64`; a pack declares the name, never a number; ANY = -1 (default type, no `school` field); 0 = a declared type with no school (only an avoid pays).
- Expectation types and kinds: `"none"` NONE 0, `"instant"` FRAME 1, `"travel"` FLIGHT 2, `"melee"` MELEE 3 (engine-only, never declarable), `"strike"` STRIKE 4, `"ticks"` TICKS 5, `"channel"` CHANNEL 6 (opt-in by `expects` only; implemented, untested in game, unused by packs); UNMAPPED 7 is the engine's own for a success no ability maps.
- No `ticks` or `tickPeriod` ability fields (owner ruling 2026-10-22): a ticking kind reads its aura (`ability.cycle or ability.aura or ability.key`, as the simulation does): period `tick_time`, count `floor(duration / tick_time)`, function fields called at the commit in Hekili's own state; a declared `"instant"` or `"travel"` ability also ticks when that aura has a `tick_time` and upstream's aura field `dot = "debuff"` (`Engine/Sim/State.lua:3302-3312`), and `"ticks"` requires both; no ability-level flag; `velocity` stays, `impact` is never added.
- Default type when `expects` is absent: `"strike"` if `onNextSwing`, else `"instant"` if `startsCombat`, else `"none"`; a malformed declaration counts one `I.nowErrors` and takes the default.
- Floors only move up. A downward move stops the branch for the owner's ruling, with a named cause written beside the number; the expected upward moves for casters are recorded in the pack notes.
- Hekili has no `tools/apiref_surface.lua` or `make apiref` (those are Taco Dog Forever's); the equivalent gate here is `make api-check` (`tools/check_api_reads.sh`, `tools/api_inventory.txt`) plus `make check`; every new `I.*` function carries a `---` doc comment.
- `make check` (luacheck, StyLua, LuaLS, busted, syntax, api-check, packs-check, tools-test) is green on every commit; `make gate` before the merge.
- Every commit ends with the trailer:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw`.

## Module Layout

Layering kept: Sources read the client through the injected `api`; Events and Families are pure (no client read).

| File | Responsibility | Consumes | Produces | Tested by |
|---|---|---|---|---|
| `src/Hekili/Game/State/Sources/Units.lua` (new) | the unit registry: token to GUID, unit slots and lifetimes, `UNIT_COMBAT` resolve, dedupe, dispatch, death events and kill tell, the player's GUID, the SENT pin | `api.UnitGUID` (through `Plain`), `PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`, `NAME_PLATE_UNIT_ADDED/REMOVED`, `PLAYER_SOFT_*_CHANGED`, `UNIT_COMBAT`, `UNIT_DIED`, `PARTY_KILL`, `PLAYER_TARGET_DIED`, `UNIT_SPELLCAST_SENT/FAILED`, `PLAYER_REGEN_ENABLED`, `PLAYER_ENTERING_WORLD` | `I.Units`: `TOKENS`, `INDEX`, `Resolve`, `Bound`, `Uid`, `GUID`, `Find`, `Pin`, `Sent`, `Alive`, `IsDead`, `Ours`, `IsTarget`, `Dead`, `Hold`, `Release`, `OnRow`, `OnGone`, `Tick`, `Claims` hook; `I.Log.player` | `tests/Game/State/units_spec.lua` |
| `src/Hekili/Engine/Schema/Spec.lua` (edit) | the school enum | none | `ns.SCHOOL`, `Hekili.SCHOOL` | `tests/Game/State/expect_spec.lua`, `tests/boundary_spec.lua` |
| `src/Hekili/Game/State/Families/Expect.lua` (new) | compiles each ability's `expects`, `school`, `velocity` and its ticking aura (`tick_time` with `dot = "debuff"`) at build; default type; validation | `I.ab` (`Families/Casts.lua`), `ns.SCHOOL`, the build's `def.abilities` and `def.auras` | `I.Expect` (kind and school constants, `X.Tick(a)`, `X.Malformed`), `A.expKind`, `A.expDeclared`, `A.velocity`, `A.school`, `A.tickAura`, `A.ticking`; `I.nowErrors` on a malformed one | `tests/Game/State/expect_spec.lua` |
| `src/Hekili/Game/Events/Tickets.lua` (new) | the ticket pool and lifecycle: open (swing, commit, arm, unclaimed success), consumption order (`Pick`), pay, expiry, closes and their counters, FIFO by expected closure, learned flight lag records, per-ability amount bands, the single owner of a pending swing (`SwingPending`, Task 6b) and of a strike's swallowed swing, Snapshot line | `I.Units` (`Find`, `Hold`, `Release`, `IsDead`, `Ours`, `OnGone`), `I.Expect`, `I.Kinds` (at run time), `I.ab` | `I.Tickets`: pool arrays, `OpenSwing`, `OpenCast`, `Commit`, `Arm`, `Stop`, `Pick`, `Pay`, `Provisional`, `Expire`, `EndCombat`, `Unmapped`, `LagOf`, `Learn`, `closed`, `paid`, `lost` | `tests/Game/Events/tickets_spec.lua` |
| `src/Hekili/Game/Events/Melee.lua` (new, moved) | the MELEE kind: the swing likelihood ratio, amount classes, landing-lag density and learning, background rates (moved from Rows unchanged) | `I.Tickets` arrays, `VS.Stat("UnitDamage")` | `I.Melee`: `score`, `advance`, `background`, `lambda`, `learn`, `classOf`, `AVOIDS`, `SAME_FRAME`, `CAST_WINDOW`, `STRIKE_WINDOW`; `L.LandWindow` and the `L.*` tuning | `tests/Game/Events/pairing_replay_spec.lua`, `tests/Game/Events/cleu_rows_spec.lua` (unchanged) |
| `src/Hekili/Game/Events/Kinds.lua` (new) | every other kind's rule, once: which rows a ticket accepts (school, amount band, avoid) and its band per pass (FRAME, STRIKE, FLIGHT, TICKS, CHANNEL) | `I.Tickets` arrays, `I.Melee` constants, `L.LandWindow`, `VS.TargetRange`, `I.Units.Bound` | `I.Kinds`: `Accepts`, `Band` | `tests/Game/Events/kinds_spec.lua` |
| `src/Hekili/Game/State/Stats.lua` (new, Task 7a) | the running statistics, once: `Ema`, `Median`, `Clamp` | nothing | `I.Stats` | `tests/Game/State/stats_spec.lua` |
| `src/Hekili/Game/Events/Bands.lua` (new, Task 7b) | amount bands, once: `Normalise` (per-caller policy), `Learn`, `Fits`, `Class` | nothing | `I.Bands` | `tests/Game/Events/bands_spec.lua` |
| `src/Hekili/Game/Events/CombatLog.lua` (edit, Task 5b) | the row builders `L.Swing`, `L.SpellHit`, `L.Miss` beside `L.Cast`, `auraRow`, `L.Energize`: every combat-log row shape in one file | `L.Emit` | the builders | `cleu_rows_spec.lua` |
| `src/Hekili/Game/Events/Rows.lua` (shrunk) | before: its own pending ring, its own `target`-only `UNIT_COMBAT` handler, its own GUID reads, every scoring rule. After: opens a ticket for each commit (`PLAYER_SWING`, a hard cast's START, each success), feeds each `OnRow` row through the consumption order, and turns payments into `SWING_*` / `SPELL_*` / `SPELL_PERIODIC_DAMAGE` rows and `Obs.Swing` / `Obs.Crit` / `Obs.Avoided`; keeps the credit records, `I.CreditVerdict`, the provisional avoid, WOUND 0 and the strike replacement | `I.Units.OnRow`, `I.Tickets`, `I.Melee`, `I.Kinds`, `I.Expect` | combat-log rows, staged observations | `cleu_rows_spec.lua`, `pairing_replay_spec.lua`, harness specs |
| `src/Hekili/Game/Events/Attackers.lua` (edit) | hits on us; its own token reads become `I.Units.Bound(i)` | `I.Units` | unchanged | `tests/Game/harness/onus_spec.lua` |
| `src/Hekili/Game/State/Sources/Target.lua` (edit) | memory slots (TargetHealth's, keyed by GUID, outliving registry slots), range poll, `TargetDamage` from `OnRow`, `TargetGone` from `OnGone` DEAD | `I.Units` | unchanged observations | `tests/Game/State/target_health_spec.lua` |
| `src/Hekili/Game/State/Sources/Casts.lua` (edit) | own-cast observations; its `I.sentGUID` read becomes `I.Units.Sent`/`Pin`; the player's GUID read moves to Units | `I.Units` | unchanged | `tests/Game/State/casts_spec.lua` |
| `src/Hekili/Game/State/Sources/Nameplates.lua` (edit) | poll 5 also reports a plain dead plate to `I.Units.Dead` | `I.Units` | unchanged | `units_spec.lua` |

## Review Focus

Most likely to bite a player first (items 4-8 added by the owner):

1. A post-clear killing blow or a swap landing that pays the wrong unit (or none): the registry's held-unit fallback and the swap exception. Exercised by Task 2 (`units_spec.lua` "resolves the killing blow after the clear", "keeps a swapped token's row on the old unit when its ticket owes it"), Task 11 (`capture_swap` and `capture_b` replays) and Task 13 (K5, K11, K12, K19).
2. Melee drift from the ticket refactor (swing LR, provisional avoid, `CreditVerdict` re-open, strike replacement): Tasks 5 and 6 run `pairing_replay_spec.lua`, `cleu_rows_spec.lua`, `group_spec.lua`, `solo_spec.lua`, `onus_spec.lua` unchanged, and Task 17 compares every melee floor.
3. Wider spell windows taking foreign rows (the first ticket's `[0, H]` hard window, widened bands): Task 7 (`kinds_spec.lua` FLIGHT bands, the capture a MISS case) and Task 12 (K4 and K8 foreign leak in party-light and busy bands).
4. A consumer that still reads a token itself (boundary leak: a stale GUID after a swap or a kill): Task 3's grep step (`UnitGUID` appears only in `Units.lua`) and `units_spec.lua`'s "no other file reads UnitGUID" check.
5. Duplicated matching logic between a kind and Rows.lua (two rules that drift apart): Task 6 removes `cast()`, `another()`, `unmappedT` and every window constant from Rows; `kinds_spec.lua` and Task 6's grep step check Rows names no window.
6. A hot path that builds a string or a table (a `"nameplate" .. i` at run time, a closure per row, a Snapshot string
   built outside Snapshot): Task 15's alloc specs over a K16 raid-40 300 s run and a solo 300 s run, the memory ceiling
   spec and `make bench-ta`; Task 2's and Task 6's zero-allocation cases.
7. Two layers each keeping a pending swing (or a strike's swing) with their own expiry: Task 6b makes the swing
   ticket the single owner (`T.SwingPending`); its test asserts Resources holds no `pendT`, and the rage gates must
   not move down.
8. A hand-written combat-log row (school 1 in Rows, the real mask in Attackers before): Task 5b's builders and its
   test that neither file calls `L.Emit` itself; Task 6's test that an own SPELL_DAMAGE row carries the ability's
   compiled school.

## Task order

1. The school enum (`ns.SCHOOL`) and Hekili_Shared's lockouts on it
2. The unit registry source (`Units.lua`)
3. Refactor: every consumer reads the registry (behaviour preserved)
4. Expectation compile and validation (`Expect.lua`)
5. Refactor: the ticket pool and the MELEE kind out of Rows (behaviour preserved)
   5b. Combat-log row builders (`L.Swing`, `L.SpellHit`, `L.Miss`)
   5c. Drop the redundant payload re-Plain calls
6. Tickets: lifecycle, consumption order and the FRAME, STRIKE, UNMAPPED and NONE kinds
   6b. The swing ticket owns the pending swing; the strike ticket owns the swallowed swing
7. The FLIGHT kind: hard window, range bracket, learned lag, amount band
   7a. One home for the running statistics (`State/Stats.lua`)
   7b. One home for amount bands (`Events/Bands.lua`), the SENT pin
8. The TICKS and CHANNEL kinds
9. Closes on death, divergence, the first swing, Snapshot, `TargetGone` on a kill
   9b. Expected rage for an uncredited swing (before the suites, so their floors are recorded against it)
10. Harness corrections: observer, world and the scenario knobs for K1-K20
11. Fixtures from the captures and their replay (K20)
12. Detection suite K1-K9
13. Detection suite K10-K19
14. The invariant sweep
15. Performance: pools, allocation, memory ceiling, `make bench-ta`
16. Pack data pass (casters and Hunter)
17. `make spell-data-check`
18. The gate
19. Docs and ledger

Tasks 7a and 7b come before Task 7 in the file (Task 7 uses them). Tasks 3 and 5 are the behaviour-preserving refactors: they change no decision, and every existing spec passes unchanged
before Task 6 turns the new consumption order on. Fixtures are named `capture_*.lua`, not after the spells the
captures cast: `tests/boundary_spec.lua` scans `tests/Game/harness/**` code for content keys, and a fixture's name is
a string in the replay spec's code.

---

### Task 1: The school enum and Hekili_Shared's lockouts on it

**Files:**
- Modify: `src/Hekili/Engine/Schema/Spec.lua:12` (after `local Hekili = _G[ addon ]`)
- Modify: `src/Hekili_Shared/Shared/Auras.lua:23`
- Modify: `tests/boundary_spec.lua:23-30` (`PUBLIC` gains `SCHOOL`)
- Modify: `tests/Game/State/helpers/load.lua:21-30` (`M.module` seeds `ns.SCHOOL` from Spec.lua's own line)
- Test: `tests/Game/State/school_spec.lua` (new)

**Interfaces:**
- Consumes: nothing.
- Produces: `ns.SCHOOL = { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 }`;
  `Hekili.SCHOOL` (the same table) for content addons.
- Boundary: Engine/Schema owns the enum; Game reads `ns.SCHOOL` only at build (Task 4); content reads `Hekili.SCHOOL`
  only (public object).

- [ ] **Step 1: Write the failing test** `tests/Game/State/school_spec.lua`:

```lua
-- tests/Game/State/school_spec.lua (unit-registry spec §5.1): the school enum is one core table, Engine/Schema/Spec.lua's
-- `ns.SCHOOL`, and the headless loader hands the same table to the Game files.
local load = require("Game.State.helpers.load")

describe("the school enum", function()
    it("is Spec.lua's table, seeded into a headless ns", function()
        local ns = load.module()
        assert.are.same(
            { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 },
            ns.SCHOOL
        )
    end)

    it("is published on the Hekili object and read by Hekili_Shared's lockouts", function()
        local src = assert(io.open("src/Hekili/Engine/Schema/Spec.lua")):read("*a")
        assert.is_truthy(src:find("Hekili.SCHOOL = ns.SCHOOL", 1, true))
        local shared = assert(io.open("src/Hekili_Shared/Shared/Auras.lua")):read("*a")
        assert.is_truthy(shared:find("local SCHOOLS = Hekili.SCHOOL", 1, true))
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/State/school_spec.lua`
Expected: FAIL, `Expected objects to be the same ... Passed in: (nil)` (no `ns.SCHOOL`).

- [ ] **Step 3: Implement.** In `src/Hekili/Engine/Schema/Spec.lua`, after line 12 (`local Hekili = _G[ addon ]`):

```lua
-- The client's spell schools by name (unit-registry spec §5.1): a game concept, not class content. Packs declare an
-- ability's `school` by name; Game/State/Families/Expect.lua compiles it to this mask at build.
ns.SCHOOL = { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16, shadow = 32, arcane = 64 }
Hekili.SCHOOL = ns.SCHOOL
```

In `src/Hekili_Shared/Shared/Auras.lua` replace line 23:

```lua
local SCHOOLS = Hekili.SCHOOL
```

In `tests/boundary_spec.lua`, inside `local PUBLIC = {` (line 23), add after `Client = true,`:

```lua
    SCHOOL = true,
```

In `tests/Game/State/helpers/load.lua`, replace `M.module` (lines 21-30) with:

```lua
-- Spec.lua's school enum (Engine/Schema loads after Game in Hekili.toc and needs Hekili, so a headless ns takes the
-- table from Spec.lua's own line: one source of truth).
local function school()
    local src = assert(io.open(M.ROOT .. "Engine/Schema/Spec.lua")):read("*a")
    return assert(loadstring("return " .. assert(src:match("ns%.SCHOOL = (%b{})"))))()
end

--- A fresh ns with every VirtualState file but Adapter.lua loaded, `ns.SCHOOL` seeded as Spec.lua sets it.
function M.module()
    local ns = { SCHOOL = school() }
    for _, path in ipairs(M.files()) do
        if not path:match("Adapter%.lua$") then
            assert(loadfile(path))("Hekili", ns)
        end
    end
    return ns
end
```

- [ ] **Step 4: Run it and the boundary**

Run: `.lua/bin/busted tests/Game/State/school_spec.lua tests/boundary_spec.lua`
Expected: PASS (both files, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Engine/Schema/Spec.lua src/Hekili_Shared/Shared/Auras.lua tests/boundary_spec.lua \
  tests/Game/State/helpers/load.lua tests/Game/State/school_spec.lua
git commit -m "feat(schema): ns.SCHOOL enum, published as Hekili.SCHOOL; Shared lockouts read it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 2: The unit registry source

**Files:**
- Create: `src/Hekili/Game/State/Sources/Units.lua`
- Modify: `src/Hekili/Hekili.toc:31` (add `Game\State\Sources\Units.lua` as line 32, right after `Sources.lua`)
- Test: `tests/Game/State/units_spec.lua` (new)

**Interfaces:**
- Consumes: `S.On`, `S.OnStart`, `S.Plain` (`Sources.lua`); `I.Events.STUB` (`EventFacade.lua:32`, at run time);
  `I.Log.OnTick`, `I.Log.player` (`CombatLog.lua`, at Start).
- Produces (`I.Units`, internal, spec §2.7, plus the four marked + needed by later tasks):
  `TOKENS[i]`, `INDEX[token]`, `NTOK` (44); `Resolve(api, i, t, act, school) -> guid|nil, uid, swapped`;
  `Bound(i) -> guid|""`; `Uid(i) -> uid` (+); `GUID(uid) -> guid|""` (+); `Find(guid) -> uid|0`;
  `Pin(api, t) -> guid|nil`; `Sent(castGUID) -> guid|nil` (+, the SENT pin); `Alive(uid)`; `IsDead(uid)`;
  `Ours(uid)`; `IsTarget(uid, t)` (+); `Dead(uid, t)`; `Hold(uid)`; `Release(uid, t)`; `OnRow(fn)` with
  `fn(t, guid, uid, act, flag, amount, school)`; `OnGone(fn)` with `fn(uid, guid, why, t)`, why `U.GONE` 3, `U.DEAD`
  4, `U.RESET` 0; `Tick(now)`; `U.Claims` (a hook Tasks 6-8 set: `fn(uid, act, school) -> bool`); `U.player`.
  Counters `U.unresolved`, `U.dup`, `U.evicted`, `U.deaths.tell|poll|event`.
- Boundary: the only file that reads `UnitGUID` on a token or the player; owns no belief; Events code never calls the
  client through it except `Pin`/`Resolve`, which take the injected `api`.

Implementation choices: the tick is registered with `I.Log.OnTick` from `S.OnStart` because `CombatLog.lua` loads after
the Sources (Hekili.toc:48) and `I.Log` does not exist at this file's load. `Resolve` takes the row's `act` and
`school` (beyond spec §2.7's `(api, i, t)`) because the swap exception (spec §2.3) asks the ticket pool whether the old
unit owes such a row. A secret payload slot is stored in the dedupe ring as `false`, so it never equals a plain one.

- [ ] **Step 1: Write the failing test** `tests/Game/State/units_spec.lua`:

```lua
-- tests/Game/State/units_spec.lua (unit-registry spec §2): the unit registry. Tokens bind to unit slots by plain GUID;
-- one outcome's fan-out (plate, target, soft) dispatches once; a cleared target's slot resolves the killing blow while
-- held and GRACE after; death events, the kill-tell fallback, eviction and the combat-end reset; the SENT pin.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("the unit registry", function()
    local api, ctl, ns, VS, I, U, saved, rows, gone

    local function boot(unknown)
        api, ctl = fake.new()
        for _, e in ipairs(unknown or {}) do
            ctl.unknownEvents[e] = true
        end
        for k, v in pairs(saved or {}) do -- a second boot in one case puts the globals back first
            _G[k] = v or nil
        end
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        U = I.Units
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        rows, gone = {}, {}
        U.OnRow(function(t, guid, uid, act, flag, amount, school)
            rows[#rows + 1] = { t = t, guid = guid, uid = uid, act = act, amount = amount, school = school }
        end)
        U.OnGone(function(uid, guid, why, t)
            gone[#gone + 1] = { uid = uid, guid = guid, why = why, t = t }
        end)
    end

    local function combat(unit, act, amount, school)
        ctl.Fire("UNIT_COMBAT", unit, act, "", amount, school)
    end

    before_each(function()
        boot()
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        saved = nil
    end)

    it("dispatches one outcome's plate, target and soft rows once, counting the duplicates", function()
        ctl.guid.nameplate1, ctl.guid.softenemy = "Creature-1", "Creature-1"
        ctl.now = 10
        combat("nameplate1", "WOUND", 14, 8)
        combat("target", "WOUND", 14, 8)
        combat("softenemy", "WOUND", 14, 8)
        assert.are.equal(1, #rows)
        assert.are.same({ "Creature-1", "WOUND", 14, 8 }, { rows[1].guid, rows[1].act, rows[1].amount, rows[1].school })
        assert.are.equal(2, U.dup)
    end)

    it("keeps two equal outcomes that share a token as two rows", function()
        ctl.now = 10
        combat("target", "WOUND", 20, 1)
        ctl.now = 10.001
        combat("target", "WOUND", 20, 1)
        assert.are.equal(2, #rows)
        assert.are.equal(0, U.dup)
    end)

    it("ignores targettarget, party and player rows", function()
        combat("targettarget", "WOUND", 5, 1)
        combat("party1", "WOUND", 5, 1)
        combat("player", "WOUND", 5, 1)
        assert.are.equal(0, #rows)
    end)

    it("resolves the killing blow after the clear to the old unit, within GRACE", function()
        ctl.now = 20
        ctl.Fire("PLAYER_TARGET_CHANGED") -- binds Creature-1 again (the same slot)
        local uid = U.Uid(1)
        ctl.guid.target = nil
        ctl.now = 20.003
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.are.equal("", U.Bound(1))
        ctl.now = 20.04
        combat("target", "WOUND", 16, 8)
        assert.are.same({ "Creature-1", uid }, { rows[1].guid, rows[1].uid })
    end)

    it("ends a released unit GRACE after its last token left: GONE, unresolvable", function()
        ctl.guid.target = nil
        ctl.now = 30
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.Tick(30.2)
        assert.are.equal(1, #gone)
        assert.are.same({ "Creature-1", U.GONE }, { gone[1].guid, gone[1].why })
        combat("target", "WOUND", 16, 8)
        assert.are.equal(0, #rows)
        assert.are.equal(1, U.unresolved)
    end)

    it("keeps a held unit resolvable past GRACE until its ticket releases it", function()
        local uid = U.Uid(1)
        U.Hold(uid)
        ctl.guid.target = nil
        ctl.now = 40
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.Tick(40.4)
        assert.are.equal(0, #gone)
        ctl.now = 40.37 + 0.1
        combat("target", "WOUND", 5, 1) -- a melee killing blow about 370 ms after the clear
        assert.are.equal(1, #rows)
        U.Release(uid, 40.5)
        ctl.Tick(40.65)
        assert.are.equal(U.GONE, gone[1].why)
    end)

    it("checks a removed plate's live GUID against its binding before unbinding", function()
        ctl.guid.nameplate2 = "Creature-7"
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
        assert.are.equal("Creature-7", U.Bound(U.INDEX.nameplate2))
        ctl.guid.nameplate2 = "Creature-8" -- a missed ADDED: the removal still answers the plate's GUID
        ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
        assert.are.equal("", U.Bound(U.INDEX.nameplate2))
        assert.is_true(U.Find("Creature-8") > 0)
    end)

    it("revives a churned plate's unit in the same slot", function()
        ctl.guid.nameplate3 = "Creature-9"
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        local uid = U.Find("Creature-9")
        ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
        ctl.Tick(ctl.now + 0.5)
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
        assert.are.equal(uid, U.Find("Creature-9"))
        assert.is_true(U.Alive(uid))
    end)

    it("marks UNIT_DIED's unit DEAD at once, PARTY_KILL's as ours, and notifies once", function()
        local uid = U.Uid(1)
        ctl.Fire("PARTY_KILL", "Player-1", "Creature-1")
        ctl.Fire("UNIT_DIED", "Creature-1")
        ctl.Fire("PLAYER_TARGET_DIED")
        assert.is_true(U.IsDead(uid) and U.Ours(uid))
        assert.are.equal(1, #gone)
        assert.are.same({ U.DEAD, 1 }, { gone[1].why, U.deaths.event })
    end)

    it("uses the FAILED-then-clear tell only when the client refused the death events", function()
        boot({ "UNIT_DIED", "PLAYER_TARGET_DIED" })
        local uid = U.Uid(1)
        ctl.now = 50
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0", 1)
        ctl.guid.target = nil
        ctl.now = 50.003
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.is_true(U.IsDead(uid))
        assert.are.equal(1, U.deaths.tell)
    end)

    it("does not use the tell while the death events are delivered", function()
        local uid = U.Uid(1)
        ctl.now = 50
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-2-0-0-0", 1)
        ctl.guid.target = nil
        ctl.now = 50.003
        ctl.Fire("PLAYER_TARGET_CHANGED")
        assert.is_false(U.IsDead(uid))
    end)

    it("reports a poll's plain death once", function()
        local uid = U.Uid(1)
        U.Dead(uid, 60)
        U.Dead(uid, 61)
        assert.are.equal(1, U.deaths.poll)
        assert.are.equal(1, #gone)
    end)

    it("evicts only a released GONE or DEAD unit when every slot is taken", function()
        for k = 1, U.UNIT_CAP do
            ctl.guid.nameplate1 = "Creature-x" .. k
            ctl.now = 100 + k
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
            ctl.Tick(ctl.now + 0.2)
        end
        assert.is_true(U.evicted >= 1)
        assert.is_true(U.Find("Creature-1") > 0) -- the target is bound: never evicted
        assert.are.equal(0, U.Find("Creature-x1")) -- the oldest released one gave way
    end)

    it("pins the target, else the soft enemy, and keeps the SENT pin by castGUID", function()
        assert.are.equal("Creature-1", U.Pin(api, 1))
        ctl.guid.target, ctl.guid.softenemy = nil, "Creature-5"
        assert.are.equal("Creature-5", U.Pin(api, 1))
        ctl.guid.target = "Creature-6"
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-9", 1)
        ctl.guid.target = "Creature-7" -- swapped mid-cast
        assert.are.equal("Creature-6", U.Sent("Cast-9"))
        assert.is_nil(U.Sent("Cast-10"))
    end)

    it("frees every unbound unit at combat end and keeps the bound target", function()
        ctl.guid.nameplate4 = "Creature-4"
        ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
        ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate4")
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(0, U.Find("Creature-4"))
        assert.are.equal("Creature-1", U.Bound(1))
        assert.are.equal(U.RESET, gone[#gone].why)
    end)

    it("reads the player's GUID for the rows' source", function()
        assert.are.equal("Player-1", U.player)
        assert.are.equal("Player-1", I.Log.player)
    end)

    it("allocates nothing resolving, deduplicating and dispatching rows", function()
        ctl.guid.nameplate1 = "Creature-1"
        local bytes = alloc.bytes(function(i)
            ctl.now = 200 + i * 0.01
            combat("nameplate1", "WOUND", 10 + i % 7, 1)
            combat("target", "WOUND", 10 + i % 7, 1)
        end, 2000)
        assert.are.equal(0, bytes)
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/State/units_spec.lua`
Expected: FAIL, `attempt to index field 'Units' (a nil value)` (or `attempt to index local 'U' (a nil value)`).

- [ ] **Step 3: Implement** `src/Hekili/Game/State/Sources/Units.lua`:

```lua
-- Game/State/Sources/Units.lua
-- The unit registry (unit-registry spec §2): the only code that turns a unit token into a GUID for attribution. Token
-- indices are fixed at load (1 target, 2 focus, 3-42 nameplate1-40, 43 softenemy, 44 softinteract: Attackers.lua's
-- order); each binds to a unit slot by plain GUID. A slot lives while a token names it (LIVE), while an open ticket
-- pins it (Events/Tickets.lua: Hold/Release) and GRACE after its release; then GONE. Deaths: UNIT_DIED and
-- PLAYER_TARGET_DIED (plain), a poll's plain UnitIsDead (Dead), or, only when the client refused the death events, a
-- clear to none within KILL_TELL of a player FAILED. PARTY_KILL with our GUID marks our kill. UNIT_COMBAT on a table
-- token is resolved, deduplicated across one outcome's fan-out (plate, target, soft: a token never repeats within one
-- outcome) and dispatched once to each OnRow listener. Also the player's GUID and the SENT pin. Owns no belief.
-- Allocates nothing after load.
-- Credits: secret-value handling after Catnip's (Durts) research.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local U = {}
I.Units = U

U.UNIT_CAP, U.DUP_N, U.DUP_WINDOW, U.GRACE, U.KILL_TELL = 64, 4, 0.005, 0.1, 0.010
U.FREE, U.LIVE, U.GRACE_S, U.GONE, U.DEAD, U.RESET = 0, 1, 2, 3, 4, 0
local FREE, LIVE, GRACE_S, GONE, DEAD, RESET = 0, 1, 2, 3, 4, 0
local CAP, DUP_N, NTOK = U.UNIT_CAP, U.DUP_N, 44

local TOKENS, INDEX = { "target", "focus" }, {}
for k = 1, 40 do
    TOKENS[k + 2] = "nameplate" .. k
end
TOKENS[43], TOKENS[44] = "softenemy", "softinteract"
for i = 1, NTOK do
    INDEX[TOKENS[i]] = i
end
U.TOKENS, U.INDEX, U.NTOK = TOKENS, INDEX, NTOK

-- Per token index: the slot bound now (0 none), the slot bound before the last change, the change's time.
local tokUid, tokPrev, tokAt = {}, {}, {}
for i = 1, NTOK do
    tokUid[i], tokPrev[i], tokAt[i] = 0, 0, 0
end
-- Per unit slot (spec §2.1): GUID ("" free), state, tokens bound, last seen, last token left, tickets held, last ticket
-- released, our kill.
local uGUID, uState, uTokens, uSeen, uLeft, uHeld, uFree, uOurs = {}, {}, {}, {}, {}, {}, {}, {}
for u = 1, CAP do
    uGUID[u], uState[u], uTokens[u], uSeen[u] = "", FREE, 0, 0
    uLeft[u], uHeld[u], uFree[u], uOurs[u] = 0, 0, 0, false
end
U.uState = uState -- read-only: Snapshot and the specs

-- The dedupe ring (spec §2.4): DUP_N groups, each with the 44-token set of the tokens already seen in it.
local dT, dUid, dAct, dFlag, dAmount, dSchool, dTok = {}, {}, {}, {}, {}, {}, {}
for e = 1, DUP_N do
    dT[e], dUid[e], dAct[e], dFlag[e], dAmount[e], dSchool[e] = -1e9, 0, "", false, false, false
end
for k = 1, DUP_N * NTOK do
    dTok[k] = false
end
local dNext = 0

U.unresolved, U.dup, U.evicted = 0, 0, 0
U.deaths = { tell = 0, poll = 0, event = 0 }
U.player, U.sentCast, U.sentGUID = "", nil, nil
U.Claims = nil -- set by Events/Tickets.lua: whether an open ticket on a unit owes a row of this act and school
local failT = -1e9
local ROW, GONE_FN = {}, {}

local function released(u)
    return uTokens[u] == 0 and uHeld[u] == 0
end

local function releaseT(u)
    return uLeft[u] > uFree[u] and uLeft[u] or uFree[u]
end

-- Whether rows may resolve to slot u at t (spec §2.1's table).
local function resolvable(u, t)
    local st = uState[u]
    if st == LIVE then
        return true
    elseif st == GRACE_S or st == DEAD then
        return not released(u) or t - releaseT(u) < U.GRACE
    end
    return false
end

local function notify(u, why, t)
    for k = 1, #GONE_FN do
        GONE_FN[k](u, uGUID[u], why, t)
    end
end

--- The slot holding `guid`, or 0. Allocates nothing.
function U.Find(guid)
    if guid == nil or guid == "" then
        return 0
    end
    for u = 1, CAP do
        if uGUID[u] == guid then
            return u
        end
    end
    return 0
end

-- A slot for guid (spec §2.6): its own, else a FREE one, else the released GONE or DEAD one seen longest ago, else a
-- released GRACE one seen longest ago. A LIVE or held slot is never taken. 0 only if all 64 are LIVE or held, which
-- 44 tokens and 16 tickets cannot reach.
local function take(guid, t)
    local u = U.Find(guid)
    if u > 0 then
        return u
    end
    local best, bestRank = 0, 9
    for v = 1, CAP do
        local st, rank = uState[v], 9
        if st == FREE then
            rank = 1
        elseif released(v) and (st == GONE or st == DEAD) then
            rank = 2
        elseif released(v) and st == GRACE_S then
            rank = 3
        end
        if rank < bestRank or (rank < 9 and rank == bestRank and uSeen[v] < uSeen[best]) then
            best, bestRank = v, rank
        end
    end
    if best == 0 then
        return 0
    end
    if bestRank > 1 then
        U.evicted = U.evicted + 1
    end
    uGUID[best], uState[best], uTokens[best], uSeen[best] = guid, GRACE_S, 0, t
    uLeft[best], uHeld[best], uFree[best], uOurs[best] = t, 0, 0, false
    return best
end

local function unbind(i, t)
    local u = tokUid[i]
    if u == 0 then
        return
    end
    tokPrev[i], tokUid[i], tokAt[i] = u, 0, t
    uTokens[u] = uTokens[u] - 1
    if uTokens[u] == 0 then
        uLeft[u] = t
        if uState[u] == LIVE then
            uState[u] = GRACE_S
        end
    end
end

local function bind(i, guid, t)
    local u = take(guid, t)
    if u == 0 then
        return 0
    end
    uSeen[u] = t
    if tokUid[i] == u then
        return u
    end
    unbind(i, t)
    tokUid[i], tokAt[i] = u, t
    uTokens[u] = uTokens[u] + 1
    if uState[u] ~= DEAD then
        uState[u] = LIVE
    end
    return u
end

-- Token i's live GUID (plain, non-empty), or nil.
local function read(api, i)
    local g = Plain(api, api.UnitGUID(TOKENS[i]))
    if type(g) == "string" and g ~= "" then
        return g
    end
end

local function rebind(api, i, t)
    local g = read(api, i)
    if g then
        bind(i, g, t)
    else
        unbind(i, t)
    end
end

local function kill(u, t, how)
    if u == 0 or uState[u] == DEAD or uState[u] == FREE then
        return
    end
    uState[u] = DEAD
    U.deaths[how] = U.deaths[how] + 1
    notify(u, DEAD, t)
end

--- (spec §2.3) The GUID a row on token index i at t is about, its slot, and whether token i was swapped away from a
--- still-resolvable unit. 1: the live read (rebinding a stale token first), except that a row the old unit's open
--- ticket owes (U.Claims) stays on the old unit; 2: while the live read is nil, the bound or previous slot while it
--- resolves; 3: nil (counted). Allocates nothing.
function U.Resolve(api, i, t, act, school)
    local g = read(api, i)
    if g then
        local u = tokUid[i]
        if u == 0 or uGUID[u] ~= g then
            u = bind(i, g, t)
        end
        local p = tokPrev[i]
        local swapped = p > 0 and p ~= u and resolvable(p, t)
        if swapped and U.Claims and U.Claims(p, act, school) then
            return uGUID[p], p, true
        end
        return g, u, swapped
    end
    local u = tokUid[i] > 0 and tokUid[i] or tokPrev[i]
    if u > 0 and resolvable(u, t) then
        return uGUID[u], u, false
    end
    U.unresolved = U.unresolved + 1
    return nil, 0, false
end

-- Whether a resolved row is a duplicate of a group in the ring (spec §2.4): same slot (any slot when `swapped`), same
-- payload within DUP_WINDOW, and its token not yet in that group; a duplicate joins the group.
local function dupOf(i, t, u, act, fk, ak, sk, swapped)
    for e = 1, DUP_N do
        if
            t - dT[e] <= U.DUP_WINDOW
            and (dUid[e] == u or swapped)
            and dAct[e] == act
            and dFlag[e] == fk
            and dAmount[e] == ak
            and dSchool[e] == sk
        then
            local k = (e - 1) * NTOK + i
            if not dTok[k] then
                dTok[k] = true
                return true
            end
        end
    end
    return false
end

S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)
    local i = unit and INDEX[unit]
    if not i or type(act) ~= "string" then
        return -- player rows stay with Attackers and Player; targettarget, partyN, raidN, mouseover are echoes
    end
    local g, u, swapped = U.Resolve(api, i, t, act, school)
    if not g then
        return
    end
    local fk, ak, sk = flag or false, amount or false, school or false -- a secret slot (nil) never equals a plain one
    if dupOf(i, t, u, act, fk, ak, sk, swapped) then
        U.dup = U.dup + 1
        return
    end
    dNext = dNext % DUP_N + 1
    local e, base = dNext, (dNext - 1) * NTOK
    dT[e], dUid[e], dAct[e], dFlag[e], dAmount[e], dSchool[e] = t, u, act, fk, ak, sk
    for k = base + 1, base + NTOK do
        dTok[k] = false
    end
    dTok[base + i] = true
    uSeen[u] = t
    for k = 1, #ROW do
        ROW[k](t, g, u, act, flag, amount, school)
    end
end)

S.On("PLAYER_TARGET_CHANGED", nil, function(api, t)
    local before = tokUid[1]
    rebind(api, 1, t)
    local stub = I.Events.STUB
    if tokUid[1] == 0 and before > 0 and t - failT <= U.KILL_TELL and stub.UNIT_DIED and stub.PLAYER_TARGET_DIED then
        kill(before, t, "tell") -- spec §2.5's fallback: the death events are refused
    end
end)
S.On("PLAYER_FOCUS_CHANGED", nil, function(api, t)
    rebind(api, 2, t)
end)
S.On("PLAYER_SOFT_ENEMY_CHANGED", nil, function(api, t)
    rebind(api, 43, t)
end)
S.On("PLAYER_SOFT_INTERACT_CHANGED", nil, function(api, t)
    rebind(api, 44, t)
end)
S.On("NAME_PLATE_UNIT_ADDED", nil, function(api, t, unit)
    local i = unit and INDEX[unit]
    if i then
        rebind(api, i, t)
    end
end)
S.On("NAME_PLATE_UNIT_REMOVED", nil, function(api, t, unit)
    local i = unit and INDEX[unit]
    if not i then
        return
    end
    local g = read(api, i) -- the removal still answers the plate's GUID (soft-targeting log)
    if g and (tokUid[i] == 0 or uGUID[tokUid[i]] ~= g) then
        bind(i, g, t)
    end
    unbind(i, t)
end)

S.On("UNIT_DIED", nil, function(api, t, guid)
    kill(U.Find(guid), t, "event")
end)
S.On("PLAYER_TARGET_DIED", nil, function(api, t)
    kill(tokUid[1], t, "event")
end)
S.On("PARTY_KILL", nil, function(api, t, killer, victim)
    if killer ~= nil and killer == U.player then
        local u = U.Find(victim)
        if u > 0 then
            uOurs[u] = true
        end
    end
end)
S.On("UNIT_SPELLCAST_FAILED", "player", function(api, t, unit)
    if unit == "player" then
        failT = t -- any castGUID, key spam included: read only by the fallback tell
    end
end)

--- (spec §2.7) Pins a commit: the target's live GUID, else the soft enemy's, else nil. Allocates nothing.
function U.Pin(api, t)
    local g = read(api, 1)
    if g then
        bind(1, g, t)
        return g
    end
    g = read(api, 43)
    if g then
        bind(43, g, t)
    end
    return g
end

S.On("UNIT_SPELLCAST_SENT", "player", function(api, t, unit, _, castGUID)
    if unit == "player" then
        U.sentCast, U.sentGUID = castGUID, U.Pin(api, t)
    end
end)

--- The GUID our cast `castGUID` was SENT to (spec §1 row 3: a cast keeps its SENT target), or nil.
function U.Sent(castGUID)
    if castGUID ~= nil and castGUID == U.sentCast then
        return U.sentGUID
    end
end

--- Moves each released GRACE slot past GRACE to GONE (OnGone GONE). Every OnUpdate. Allocates nothing.
function U.Tick(now)
    for u = 1, CAP do
        if uState[u] == GRACE_S and released(u) and now - releaseT(u) >= U.GRACE then
            uState[u] = GONE
            notify(u, GONE, now)
        end
    end
end

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    for u = 1, CAP do
        if uState[u] ~= FREE and uTokens[u] == 0 then
            notify(u, RESET, t)
            uGUID[u], uState[u], uHeld[u], uOurs[u] = "", FREE, 0, false
        end
    end
    for i = 1, NTOK do
        if tokPrev[i] > 0 and uState[tokPrev[i]] == FREE then
            tokPrev[i] = 0
        end
    end
    for e = 1, DUP_N do
        dT[e] = -1e9
    end
    failT = -1e9
end)

local function readPlayer(api)
    U.player = Plain(api, api.UnitGUID("player")) or ""
    I.Log.player = U.player
end
S.On("PLAYER_ENTERING_WORLD", nil, readPlayer)
S.OnStart(function(api, t)
    readPlayer(api)
    rebind(api, 1, t)
    rebind(api, 2, t)
    rebind(api, 43, t)
    rebind(api, 44, t)
    I.Log.OnTick(U.Tick) -- CombatLog.lua loads after the Sources: its lane exists from Start
end)

--- The GUID bound to token index i, "" none.
function U.Bound(i)
    local u = tokUid[i]
    return u > 0 and uGUID[u] or ""
end
--- The slot bound to token index i, 0 none.
function U.Uid(i)
    return tokUid[i]
end
--- Slot u's GUID, "" none.
function U.GUID(u)
    return u > 0 and uGUID[u] or ""
end
--- Whether slot u is LIVE or GRACE.
function U.Alive(u)
    return u > 0 and (uState[u] == LIVE or uState[u] == GRACE_S)
end
--- Whether slot u is DEAD.
function U.IsDead(u)
    return u > 0 and uState[u] == DEAD
end
--- Whether slot u died to our kill (PARTY_KILL with our GUID).
function U.Ours(u)
    return u > 0 and uOurs[u]
end
--- Whether slot u is the current target, or (no target) the cleared target's slot while it still resolves at t.
function U.IsTarget(u, t)
    if u == 0 then
        return false
    elseif tokUid[1] > 0 then
        return u == tokUid[1]
    end
    return u == tokPrev[1] and resolvable(u, t)
end
--- Marks slot u DEAD from a poll's plain UnitIsDead (Target poll 4, Nameplates poll 5).
function U.Dead(u, t)
    kill(u, t, "poll")
end
--- An open ticket pins slot u (Events/Tickets.lua).
function U.Hold(u)
    if u > 0 then
        uHeld[u] = uHeld[u] + 1
    end
end
--- A ticket pinned to slot u closed at t.
function U.Release(u, t)
    if u > 0 and uHeld[u] > 0 then
        uHeld[u] = uHeld[u] - 1
        if uHeld[u] == 0 then
            uFree[u] = t
        end
    end
end
--- Load-time: `fn(t, guid, uid, act, flag, amount, school)` for every resolved, deduplicated row, in registration order.
function U.OnRow(fn)
    ROW[#ROW + 1] = fn
end
--- Load-time: `fn(uid, guid, why, t)`, why GONE 3, DEAD 4 or RESET 0.
function U.OnGone(fn)
    GONE_FN[#GONE_FN + 1] = fn
end

--- Snapshot's line (allocates; debugging only).
I.OnSnapshot(function(out)
    local n = { [LIVE] = 0, [GRACE_S] = 0, [GONE] = 0, [DEAD] = 0 }
    for u = 1, CAP do
        local st = uState[u]
        if st ~= FREE then
            n[st] = n[st] + 1
        end
    end
    local d = U.deaths
    out[#out + 1] = string.format(
        "units live=%d grace=%d gone=%d dead=%d unresolved=%d dup=%d evicted=%d deaths tell=%d poll=%d event=%d",
        n[LIVE],
        n[GRACE_S],
        n[GONE],
        n[DEAD],
        U.unresolved,
        U.dup,
        U.evicted,
        d.tell,
        d.poll,
        d.event
    )
end)
```

Add to `src/Hekili/Hekili.toc` after line 31 (`Game\State\Sources\Sources.lua`):

```
Game\State\Sources\Units.lua
```

- [ ] **Step 4: Run it**

Run: `.lua/bin/busted tests/Game/State/units_spec.lua`
Expected: PASS, 17 successes, 0 failures.

- [ ] **Step 5: Run the existing VirtualState specs (the registry is additive here)**

Run: `.lua/bin/busted tests/Game/State tests/Game/Events`
Expected: PASS, 0 failures (no consumer reads the registry yet; Casts.lua still sets `I.Log.player` too, to the same
value).

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Game/State/Sources/Units.lua src/Hekili/Hekili.toc tests/Game/State/units_spec.lua
git commit -m "feat(units): the unit registry: token to GUID, dedupe, dispatch, lifetimes, deaths, SENT pin

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 3: Refactor: every consumer reads the registry (behaviour preserved)

**Files:**
- Modify: `src/Hekili/Game/State/Sources/Target.lua:54-66` (`swap`), `:79-89` (poll 4), `:135-143` (`TargetDamage`)
- Modify: `src/Hekili/Game/Events/Attackers.lua:30-41`, `:79-124`, `:128-145`, `:206-262`
- Modify: `src/Hekili/Game/State/Sources/Casts.lua:15-35`, `:47`, `:61-62`
- Modify: `src/Hekili/Game/State/Sources/Nameplates.lua:42-51` (poll 5)
- Modify: `src/Hekili/Game/Events/Rows.lua:338`, `:341`, `:362`, `:443-447`, `:484`
- Test: `tests/Game/State/units_spec.lua` (two cases added); the existing specs unchanged

**Interfaces:**
- Consumes: `I.Units.Bound`, `Uid`, `Pin`, `Sent`, `IsTarget`, `Dead`, `OnRow`, `OnGone`, `DEAD` (Task 2).
- Produces: nothing new; `I.sentGUID` is removed (its two readers, Casts' START and SUCCESS rows, read
  `I.Units.Sent(castGUID)` instead); `Obs.TargetGone` for a dead target now comes from `OnGone` DEAD.
- Boundary: after this task no file but `Units.lua` reads `UnitGUID`; Target keeps its GUID-keyed memory slots
  (TargetHealth's, which outlive registry slots) fed from `I.Units.Bound(1)`; Attackers keeps its own `UnitIsUnit`,
  `UnitCanAttack`, `UnitAttackSpeed` reads and its clocks.

Behaviour guarantee: every existing spec passes unchanged. Rows still credits only rows about the target
(`I.Units.IsTarget`, the registry's equivalent of `unit == "target"`); the dedupe hands it the first token of a fan-out,
which carries the same payload at the same time as the `target` row it used to read.

- [ ] **Step 1: Write the failing tests.** Append inside `describe("the unit registry", ...)` of
  `tests/Game/State/units_spec.lua`:

```lua
    it("is the only file that reads UnitGUID", function()
        local readers = {}
        for _, path in ipairs(load.files()) do
            local src = assert(io.open(path)):read("*a")
            if src:find("UnitGUID%(") and not path:match("Units%.lua$") and not path:match("Facade%.lua$") then
                readers[#readers + 1] = path
            end
        end
        assert.are.same({}, readers)
    end)

    it("hands a dead target's death to TargetHealth's memory slot once", function()
        local gone0 = 0
        I.On(VS.Obs.TargetGone, function()
            gone0 = gone0 + 1
        end)
        ctl.Fire("UNIT_DIED", "Creature-1")
        I.Sources.Flush()
        I.Fold(ctl.now)
        assert.are.equal(1, gone0) -- at the death event, before any poll
        ctl.dead.target = true
        I.Sources.RunPolls(ctl.now) -- poll 4 sees it too: the registry already has it DEAD
        I.Fold(ctl.now)
        assert.are.equal(1, gone0)
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/State/units_spec.lua`
Expected: FAIL: "is the only file that reads UnitGUID" lists `Target.lua`, `Casts.lua`, `Rows.lua`, `Attackers.lua`;
"hands a dead target's death" fails `Expected 1, Passed in 0` at its first assertion (no TargetGone from UNIT_DIED
yet).

- [ ] **Step 3: Implement Target.lua.** Replace `swap` (lines 54-66) with:

```lua
local function swap(api, t)
    local g = I.Units.Bound(1) -- the registry bound it first (its PLAYER_TARGET_CHANGED handler is registered earlier)
    local s, fresh = 0, false
    if g ~= "" then
        s, fresh = slotFor(g, t)
    end
    local attackable = s > 0 and Plain(api, api.UnitCanAttack("player", "target")) == true
    dead, lastLo, lastHi = false, -1, -1
    Direct(Obs.TargetSwap, t, s, fresh and 1 or 0, attackable and 1 or 0)
    if s > 0 and I.auras.n >= 2 then
        I.WalkAuras(api, 2, "target", t)
    end
end
```

Replace poll 4 (lines 79-89) with:

```lua
-- Poll 4: the target's plain death goes to the registry, which tells every listener once (OnGone DEAD, below).
S.Poll(4, function(api, t)
    if I.curSlot == 0 then
        return
    end
    local d = Plain(api, api.UnitIsDead("target")) == true
    if d and not dead then
        I.Units.Dead(I.Units.Uid(1), t)
    end
    dead = d
end)
```

Replace the `UNIT_COMBAT` handler (lines 135-143) with:

```lua
-- The target's damage taken (target-health design §2.3c): the registry's rows about the current target's unit, any
-- token (every attacker's hits count). A dead unit's memory slot forgets it at its death (unit-registry spec §4.3),
-- from whichever tell came first. Registered at Start: Rows' listener (loaded later) must see each row first.
local function damage(t, g, uid, act, flag, amount)
    if act == "WOUND" and type(amount) == "number" and amount > 0 and uid == I.Units.Uid(1) then
        Direct(Obs.TargetDamage, t, 0, amount) -- logged straight, as the swap: a same-frame WOUND keeps its target
    end
end
local function died(uid, g, why, t)
    if why ~= I.Units.DEAD then
        return
    end
    for s = 1, I.TARGET_CAP do
        if guid[s] == g then
            Direct(Obs.TargetGone, t, s)
            return
        end
    end
end
S.OnStart(function()
    I.Units.OnRow(damage)
    I.Units.OnGone(died)
end)
```

- [ ] **Step 4: Implement Attackers.lua.** Replace lines 30-41 with:

```lua
-- The tokens whose target is checked: the registry's 1-42 (target, focus, nameplate1-40); "<token>target" built once.
local U = I.Units
local TOKENS, INDEX, NT = U.TOKENS, U.INDEX, 42
local TT = {}
for i = 1, NT do
    TT[i] = TOKENS[i] .. "target"
end
local tokOnMe, tokSpeed, tokLoose = {}, {}, {}
for i = 1, NT do
    tokOnMe[i], tokSpeed[i], tokLoose[i] = false, 0, false
end
```

In `recheck` (line 81) replace `local guid = Plain(api, api.UnitGUID(tok)) or ""` with `local guid = U.Bound(i)`, and
on line 88 replace `tokGUID[i], tokOnMe[i] = guid, hostile and onMe == true` with
`tokOnMe[i] = hostile and onMe == true`.

Replace `onUnit` and the three handlers after it (lines 102-124) with:

```lua
local function onUnit(api, t, unit)
    local i = unit and INDEX[unit]
    if i and i <= NT then
        recheck(api, i)
    end
end
S.On("UNIT_TARGET", nil, onUnit)
S.On("NAME_PLATE_UNIT_ADDED", nil, onUnit)
S.On("NAME_PLATE_UNIT_REMOVED", nil, function(_, _, unit)
    local i = unit and INDEX[unit]
    if i and i <= NT then -- the registry unbound it; the plate's own answers clear here
        tokOnMe[i], tokSpeed[i], tokLoose[i] = false, 0, false
    end
end)
local function readTarget(api)
    recheck(api, 1)
    L.target = U.Bound(1)
end
S.On("PLAYER_TARGET_CHANGED", nil, readTarget)
S.OnStart(readTarget)
S.On("PLAYER_FOCUS_CHANGED", nil, function(api)
    recheck(api, 2)
end)
```

In `VS.LooseEnemies` (lines 128-145) replace `for i = 1, #TOKENS do` with `for i = 1, NT do` and
`tokLoose[j] and tokGUID[j] == tokGUID[i]` with `tokLoose[j] and U.Bound(j) == U.Bound(i)`.
In the player `UNIT_COMBAT` handler replace `for i = 1, #TOKENS do` (line 209) with `for i = 1, NT do`,
`local guid, seen = tokGUID[i], false` (line 211) with `local guid, seen = U.Bound(i), false`,
`tokGUID[j] == guid` (line 213) with `U.Bound(j) == guid`, `find(tokGUID[tolI])` (line 242) with
`find(U.Bound(tolI))`, and `local src, dst = tokGUID[best], L.player` (line 262) with
`local src, dst = U.Bound(best), L.player`.

- [ ] **Step 5: Implement Casts.lua.** Delete lines 15-21 (`I.sentGUID = nil` and `readPlayer`: the registry reads
  the player's GUID) and the `UNIT_SPELLCAST_SENT` handler (lines 31-35). Line 47 becomes:

```lua
        I.Log.Cast("SPELL_CAST_START", t, spellID, I.Units.Sent(guid)) -- nil when unknown: CLEU falls back to the target
```

Lines 61-62 become:

```lua
    I.Log.Cast("SPELL_CAST_SUCCESS", t, spellID, I.Units.Sent(castGUID) or I.Units.Pin(api, t))
```

- [ ] **Step 6: Implement Nameplates.lua.** Replace poll 5 (lines 42-51) with:

```lua
-- Poll 5: the enemy count; a plate whose plain UnitIsDead answers true is reported to the registry (one death).
S.Poll(5, function(api, t)
    local n = 0
    for k = 1, PLATES do
        if active[k] then
            if live(api, token[k]) then
                n = n + 1
            elseif Plain(api, api.UnitIsDead(token[k])) == true then
                I.Units.Dead(I.Units.Uid(k + 2), t) -- nameplateK is the registry's token K + 2
            end
        end
    end
    Direct(Obs.Enemies, t, 0, n)
end)
```

- [ ] **Step 7: Implement Rows.lua's reads.** Line 338 becomes
  `hold(1, hand, I.Units.Pin(api, t) or "", w, t)`. Line 341's handler takes the castGUID: it already does
  (`function(api, t, unit, castGUID, spellID)`); line 362 becomes
  `hold(2, spellID, I.Units.Sent(castGUID) or I.Units.Pin(api, t) or "", L.LandWindow(1), t)`.
  Replace lines 443-447 (the handler head) with:

```lua
I.Units.OnRow(function(t, g, uid, act, flag, amount, school)
    -- the registry's equivalent of today's `unit == "target"`: the current target's unit, or the cleared one's while
    -- it still resolves (Task 6 replaces this with the tickets' own GUID match)
    if not I.Units.IsTarget(uid, t) or (act ~= "WOUND" and not MISSES[act]) then
        return
    end
    local api = I.api
    advance(t)
```

  and keep the rest of the body as it is, ending in `end)` as before (the closing `end)` of line 549 now closes
  `OnRow(function ...`).

- [ ] **Step 8: Run the new cases and every existing spec**

Run: `.lua/bin/busted tests/Game/State tests/Game/Events tests/Game/API && make test-fast`
Expected: PASS, 0 failures; `units_spec.lua` 19 successes. If any existing case fails, stop: the refactor changed a
decision. Report the case and the stream; do not edit the existing spec.

- [ ] **Step 9: Run the harness gates that read rows**

Run: `.lua/bin/busted --tags=slow tests/Game/harness/group_spec.lua tests/Game/harness/solo_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/alloc_spec.lua`
Expected: PASS with the printed numbers equal to the `measured` comments in `group_spec.lua` (1.76, 6.35, 0.36, 0.81).

- [ ] **Step 10: Commit**

```bash
git add src/Hekili/Game/State/Sources/Target.lua src/Hekili/Game/Events/Attackers.lua \
  src/Hekili/Game/State/Sources/Casts.lua src/Hekili/Game/State/Sources/Nameplates.lua \
  src/Hekili/Game/Events/Rows.lua tests/Game/State/units_spec.lua
git commit -m "refactor(units): Target, Attackers, Casts, Nameplates and Rows read the registry

No decision changes: every existing spec passes unchanged.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 4: Expectation compile and validation

**Files:**
- Create: `src/Hekili/Game/State/Families/Expect.lua`
- Modify: `src/Hekili/Hekili.toc:29` (add `Game\State\Families\Expect.lua` right after `Game\State\Families\Now.lua`)
- Modify: `tests/Game/State/helpers/fake_spec.lua:12-13` (new IDs), `:17` (`M.new`'s fourth argument), `:105-117`
  (the abilities and their auras), `:154-180` (`M.def`)
- Test: `tests/Game/State/expect_spec.lua` (new)

**Interfaces:**
- Consumes: `I.ab` (`A.n`, `A.key`), the build's `def.abilities` and `def.auras` (Hekili ability and aura tables:
  non-function fields are copied onto them by `RegisterAbility`, `Engine/Schema/Spec.lua:893-902`), `ns.SCHOOL`,
  `I.nowErrors`/`I.nowError`.
- Produces: `I.Expect` = `{ NONE = 0, FRAME = 1, FLIGHT = 2, MELEE = 3, STRIKE = 4, TICKS = 5, CHANNEL = 6,
  UNMAPPED = 7, ANY = -1, KIND = { none = 0, instant = 1, travel = 2, melee = 3, strike = 4, ticks = 5,
  channel = 6 } }`; per ability index `a`: `A.expKind[a]`, `A.expDeclared[a]` (bool), `A.velocity[a]`,
  `A.school[a]` (mask, `ANY` -1, or 0 none), `A.tickAura[a]` (the aura it applies when that aura declares a
  `tick_time`, else false), `A.ticking[a]` (bool: its kind is TICKS or CHANNEL, or it is a declared FRAME or FLIGHT
  whose aura also has `dot = "debuff"`);
  `X.Tick(a) -> period, count` (the aura's `tick_time` and `floor(duration / tick_time)` now, each called in Hekili's
  own state when the pack wrote a function; `0, 0` when it does not tick). The ticket pool (Task 8) calls `X.Tick` at
  a commit.
  Fake spec: `fs.SPENDER_F` 1008 (instant fire), `SPENDER_P` 1009 (travel, 1.5 s, velocity 20, nature),
  `SPENDER_M` 1010 (instant arcane, its aura 12 s / 3 s with `dot = "debuff"`), `SPENDER_S` 1012 (ticks, nature,
  velocity 40, its aura 15 s / 3 s with `dot = "debuff"`), `SPENDER_N` 1013 (none), `SPENDER_Q` 1014 (malformed `expects = "bogus"`, starts combat),
  `SPENDER_H` 1015 (`expects = "channel"`, arcane, its aura 3 s / 1 s);
  `fs.new(swing, kinds, ranged, expect)` adds them with `expect`.
- Boundary: pure Family code; no client read; the pack writes data only (on the ability: `expects`, `velocity`,
  `school`; on the aura: `tick_time`, `duration`, `dot = "debuff"`, upstream's own fields), the engine maps it once.

The owner's ruling (2026-10-22, spec amended alike): there are no `ticks` or `tickPeriod` ability fields. A ticking
kind reads the aura the ability applies, resolved as the simulation resolves it, `ability.cycle or ability.aura or
ability.key` (`Engine/Sim/State.lua:676`, `Engine/Sim/Events.lua:1609`): its `tick_time` is the period and
`floor(duration / tick_time)` the count, the fields packs already declare on auras (`src/Hekili_Priest/Priest.lua:265-280`,
`src/Hekili_Druid/Druid.lua:512-519`) and the simulation already reads (`Engine/Sim/State.lua:2283-2285`). A function
`duration` or `tick_time` (Moonfire's duration is one) is called at the commit in Hekili's own state, as the
simulation calls it (the pack's function is already bound to `state` by `RegisterAura`), never rebound into the
belief context (spec row 44). There is no ability-level flag: a declared `"instant"` or `"travel"` ability also opens a
TICKS ticket when its resolved aura has a `tick_time` and upstream's aura field `dot = "debuff"` (the field the
simulation's `mt_dot` reads, `Engine/Sim/State.lua:3302-3312`); `expects = "ticks"` alone means a hit that only ticks
and requires the same two aura fields. Implementation choice: the inference applies to declared types only, so an
ability on its default type keeps today's behaviour exactly (a default FRAME with school ANY opening a schedule would
take white rows in its tick bands). CHANNEL is opt-in only: a `channeled = true` ability with no
`expects` keeps today's default (strike, instant or none); only `expects = "channel"` opens a CHANNEL ticket.
`velocity` stays; `impact` is never added. Validation needs only that the aura exists and declares a `tick_time`
(a number above 0 or a function); its value is read at the commit.

- [ ] **Step 1: Extend the fake spec.** In `tests/Game/State/helpers/fake_spec.lua`, after line 13 add:

```lua
-- With `expect` (M.new's fourth argument) the declared-outcome fixtures follow (unit-registry spec §6.2's fake spec):
-- an instant (school fire), a hard-cast projectile (velocity 20, nature), an instant that also ticks (arcane, its aura
-- 12 s / 3 s, dot = "debuff"), a ticks-only one with a flight (nature, velocity 40, its aura 15 s / 3 s, dot =
-- "debuff"), one that owes nothing, one malformed, a channel (arcane, its aura 3 s / 1 s).
M.SPENDER_F, M.SPENDER_P, M.SPENDER_M, M.SPENDER_S = 1008, 1009, 1010, 1012
M.SPENDER_N, M.SPENDER_Q, M.SPENDER_H = 1013, 1014, 1015
```

Change line 17 to `function M.new(swingValue, kinds, ranged, expect)`. After the `if ranged then ... end` block
(line 117) add:

```lua
    if expect then
        ability("spender_f", { id = M.SPENDER_F, startsCombat = true, expects = "instant", school = "fire" })
        ability("spender_p", {
            id = M.SPENDER_P,
            cast = 1.5,
            startsCombat = true,
            expects = "travel",
            velocity = 20,
            school = "nature",
        })
        ability("spender_m", {
            id = M.SPENDER_M,
            startsCombat = true,
            expects = "instant",
            school = "arcane",
        })
        ability("spender_s", {
            id = M.SPENDER_S,
            startsCombat = true,
            expects = "ticks",
            school = "nature",
            velocity = 40,
        })
        ability("spender_n", { id = M.SPENDER_N, expects = "none" })
        ability("spender_q", { id = M.SPENDER_Q, startsCombat = true, expects = "bogus" })
        ability("spender_h", { id = M.SPENDER_H, startsCombat = true, channeled = true, expects = "channel",
            school = "arcane" })
        class.auras.spender_m = { key = "spender_m", id = M.SPENDER_M, duration = 12, tick_time = 3, dot = "debuff" }
        class.auras.spender_s = { key = "spender_s", id = M.SPENDER_S, duration = 15, tick_time = 3, dot = "debuff" }
        class.auras.spender_h = { key = "spender_h", id = M.SPENDER_H, duration = 3, tick_time = 1 }
    end
```

In `M.def`, replace the loop `for _, k in ipairs({ "spender_t", "spender_u", "spender_r" }) do` with:

```lua
    local extra = { "spender_t", "spender_u", "spender_r", "spender_f", "spender_p", "spender_m", "spender_s" }
    extra[#extra + 1], extra[#extra + 2], extra[#extra + 3] = "spender_n", "spender_q", "spender_h"
    for _, k in ipairs({ "spender_m", "spender_s", "spender_h" }) do -- the ticking auras (with `expect`)
        local au = class.auras[k]
        if au then
            def.auras[#def.auras + 1], def.auraIds[#def.auraIds + 1] = au, { au.id }
        end
    end
    for _, k in ipairs(extra) do
```

- [ ] **Step 2: Write the failing test** `tests/Game/State/expect_spec.lua`:

```lua
-- tests/Game/State/expect_spec.lua (unit-registry spec §5): each ability's declared outcome compiled at build: the
-- type's kind, its school and velocity, a ticking kind's aura (resolved as the simulation does: cycle, aura, key)
-- whose period and count are read at the commit, the default type when absent, and a malformed declaration reported
-- once and falling back to the default.
local load = require("Game.State.helpers.load")
local fs = require("Game.State.helpers.fake_spec")

describe("expectation compile", function()
    local ns, I, A, X

    local function build(h)
        ns = load.module()
        I = ns.VirtualStateInternal
        A, X = I.ab, I.Expect
        I.Build(fs.def(h or fs.new(9, false, false, true)), 1)
    end

    -- kind, school, declared, velocity, tick count, period
    local function of(id)
        local a = A.bySpell[id]
        local period, count = X.Tick(a)
        return A.expKind[a], A.school[a], A.expDeclared[a], A.velocity[a], count, period
    end

    -- spender_a (def.abilities[1]) with `fields` set; `auras` { [aura key] = { field = value } } set on the fake
    -- spec's auras: kind, school, errors counted, the last error
    local function one(fields, auras)
        local h = fs.new(9)
        for k, v in pairs(fields) do
            h.Class.abilities.spender_a[k] = v
        end
        for key, f in pairs(auras or {}) do
            for k, v in pairs(f) do
                h.Class.auras[key][k] = v
            end
        end
        build(h)
        return A.expKind[1], A.school[1], I.nowErrors, I.nowError
    end

    it("compiles each declared type with its fields; a ticking one from its aura at the commit", function()
        build()
        assert.are.same({ X.FLIGHT, 8, true, 20, 0, 0 }, { of(fs.SPENDER_P) })
        assert.are.same({ X.FRAME, 4, true, 0, 0, 0 }, { of(fs.SPENDER_F) })
        assert.are.same({ X.FRAME, 64, true, 0, 4, 3 }, { of(fs.SPENDER_M) }) -- its aura: 12 s / 3 s, a debuff dot
        assert.are.same({ X.TICKS, 8, true, 40, 5, 3 }, { of(fs.SPENDER_S) }) -- 15 s / 3 s
        assert.are.same({ X.CHANNEL, 64, true, 0, 3, 1 }, { of(fs.SPENDER_H) }) -- 3 s / 1 s
        assert.are.same({ X.NONE, 0, true, 0, 0, 0 }, { of(fs.SPENDER_N) })
        assert.is_true(A.ticking[A.bySpell[fs.SPENDER_M]])
        assert.is_false(A.ticking[A.bySpell[fs.SPENDER_F]])
    end)

    it("maps an absent expects to today's behaviour; a channeled ability stays on it", function()
        build()
        local k, sc, d = of(fs.SPENDER_B)
        assert.are.same({ X.STRIKE, X.ANY, false }, { k, sc, d })
        assert.are.equal(X.FRAME, (of(fs.SPENDER_C)))
        assert.are.equal(X.ANY, select(2, of(fs.SPENDER_C)))
        assert.are.equal(X.NONE, (of(fs.SPENDER_A)))
        local kind = one({ startsCombat = true, channeled = true }, { spender_a = { tick_time = 1 } })
        assert.are.equal(X.FRAME, kind) -- CHANNEL is opt-in
    end)

    it("resolves the aura as the simulation does: cycle, else aura, else the ability's key", function()
        one({ expects = "ticks", school = "shadow", aura = "spender_c", cycle = "spender_a" }, {
            spender_a = { tick_time = 4, duration = 20, dot = "debuff" },
            spender_c = { tick_time = 3, dot = "debuff" },
        })
        assert.are.same({ 4, 5 }, { X.Tick(1) }) -- the cycle aura's 20 s / 4 s
        one({ expects = "ticks", school = "shadow", aura = "spender_c" }, { spender_c = { tick_time = 5, dot = "debuff" } })
        assert.are.same({ 5, 3 }, { X.Tick(1) }) -- the aura field's 15 s / 5 s
    end)

    it("infers an instant's ticks from its aura's tick_time and dot = \"debuff\", never from either alone", function()
        one({ expects = "instant", school = "fire" }, { spender_a = { tick_time = 3, duration = 9 } })
        assert.is_false(A.ticking[1])
        one({ expects = "instant", school = "fire" }, { spender_a = { tick_time = 3, duration = 9, dot = "debuff" } })
        assert.is_true(A.ticking[1])
        assert.are.same({ 3, 3 }, { X.Tick(1) })
        one({ startsCombat = true }, { spender_a = { tick_time = 3, duration = 9, dot = "debuff" } })
        assert.is_false(A.ticking[1]) -- a default type keeps today's behaviour
    end)

    it("calls a function duration in Hekili's own state at the commit, not at the build", function()
        local n, rank = 0, 1
        local h = fs.new(9, false, false, true)
        h.Class.auras.spender_m.duration = function()
            n = n + 1
            return rank > 1 and 12 or 9
        end
        build(h)
        assert.are.equal(0, n)
        assert.are.same({ 3, 3 }, { X.Tick(A.bySpell[fs.SPENDER_M]) })
        rank = 2
        assert.are.same({ 3, 4 }, { X.Tick(A.bySpell[fs.SPENDER_M]) })
    end)

    it("reports a malformed declaration once and falls back to the default type", function()
        build()
        local k, sc, d = of(fs.SPENDER_Q)
        assert.are.same({ X.FRAME, X.ANY, false }, { k, sc, d })
        assert.are.equal(1, I.nowErrors)
        assert.is_truthy(I.nowError:find("spender_q unknown expects bogus", 1, true))
    end)

    for _, case in ipairs({
        { { expects = "travel", school = "nature" }, nil, "travel needs velocity" },
        { { expects = "ticks" }, nil, "ticks needs an aura with tick_time and dot" },
        { { expects = "ticks" }, { spender_a = { tick_time = 3 } }, "ticks needs an aura with tick_time and dot" },
        { { expects = "channel" }, nil, "channel needs an aura with tick_time" },
        { { expects = "strike" }, nil, "strike needs onNextSwing" },
        { { expects = "melee" }, nil, "expects melee is the engine's own" },
        { { expects = "instant", school = "fel" }, nil, "unknown school fel" },
        { { expects = "instant", school = 8 }, nil, "unknown school 8" },
        { { expects = "travel", velocity = "fast" }, nil, "velocity is not a number" },
    }) do
        it("rejects " .. case[3], function()
            local kind, school, errors, err = one(case[1], case[2])
            assert.are.same({ X.NONE, X.ANY, 1 }, { kind, school, errors })
            assert.is_truthy(err:find(case[3], 1, true))
        end)
    end

    it("keeps a declared school on a default type", function()
        local kind, school, errors = one({ startsCombat = true, school = "frost" })
        assert.are.same({ X.FRAME, 16, 0 }, { kind, school, errors })
    end)
end)
```

- [ ] **Step 3: Run it**

Run: `.lua/bin/busted tests/Game/State/expect_spec.lua`
Expected: FAIL, `attempt to index local 'X' (a nil value)` / `attempt to index field 'Expect' (a nil value)`.

- [ ] **Step 4: Implement** `src/Hekili/Game/State/Families/Expect.lua`:

```lua
-- Game/State/Families/Expect.lua
-- Each ability's declared outcome (unit-registry spec §5): `expects`, a plain string from a fixed set, each mapped to
-- one engine kind whose matching and closing rule lives once in Game/Events/Kinds.lua and Melee.lua; the fields that
-- kind reads (`velocity`, `school` by name), compiled at each build into per-ability
-- arrays the ticket pool reads by ability index. A ticking kind's period and count are its aura's: the aura resolved as
-- the simulation resolves it (`cycle`, else `aura`, else the ability's key: Engine/Sim/State.lua:676), its
-- `tick_time` and floor(`duration` / `tick_time`), read at the commit (X.Tick) in Hekili's own state when the pack
-- wrote a function, as Engine/Sim/State.lua:2283-2285 reads them. A declared instant or travel ability also ticks when
-- that aura is upstream's debuff dot (`dot = "debuff"`, the field mt_dot reads). An absent `expects` takes today's behaviour:
-- "strike" with `onNextSwing`, "instant" with `startsCombat`, else "none", with school ANY unless the ability names
-- one (CHANNEL is opt-in). A malformed declaration is counted once in I.nowErrors (Snapshot's error line) and takes
-- the default. Pure: no client read.

local _, ns = ...
local I = ns.VirtualStateInternal
local A = I.ab

local X = {}
I.Expect = X
X.NONE, X.FRAME, X.FLIGHT, X.MELEE, X.STRIKE, X.TICKS, X.CHANNEL, X.UNMAPPED = 0, 1, 2, 3, 4, 5, 6, 7
X.ANY = -1 -- school: any WOUND or avoid pays, never lost (a default type on an ability with no `school`)
X.KIND = { none = 0, instant = 1, travel = 2, melee = 3, strike = 4, ticks = 5, channel = 6 }

A.expKind, A.expDeclared, A.velocity, A.school, A.tickAura, A.ticking = {}, {}, {}, {}, {}, {}

-- The aura ability `obj` (key `key`) applies, resolved as the simulation does, when it declares a tick_time (a number
-- above 0 or a function); else nil.
local function tickAura(obj, key, byKey)
    local name = rawget(obj, "cycle") or rawget(obj, "aura") or key
    local au = type(name) == "string" and byKey[name] or nil
    local tt = au and au.tick_time
    if type(tt) == "function" or (type(tt) == "number" and tt > 0) then
        return au
    end
end

-- A number field of an aura now: the pack's function called as the simulation calls it (bound to Hekili's `state`
-- by RegisterAura; a raising one answers nil).
local function num(v)
    if type(v) == "function" then
        local ok, r = pcall(v)
        v = ok and r or nil
    end
    return type(v) == "number" and v > 0 and v or nil
end

--- Ticking ability a's period and tick count now (its aura's tick_time and floor(duration / tick_time)); 0, 0 when
--- it does not tick or the aura cannot answer. Called at a commit; allocates nothing of its own.
function X.Tick(a)
    local au = A.tickAura[a]
    if not au then
        return 0, 0
    end
    local tt, d = num(au.tick_time), num(au.duration)
    if not (tt and d) then
        return 0, 0
    end
    return tt, math.floor(d / tt + 1e-6)
end

local function default(obj)
    if obj.onNextSwing then
        return X.STRIKE
    elseif obj.startsCombat then
        return X.FRAME
    end
    return X.NONE
end

-- Why `obj`'s declaration of kind `k` (nil: an unknown string) with school mask `s` (nil: none or unknown) and a
-- ticking aura `au` (nil: none) is malformed, or nil (spec §5.3).
local function malformed(obj, e, k, s, au)
    local v = obj.velocity
    if k == nil then
        return "unknown expects " .. tostring(e)
    elseif k == X.MELEE then
        return "expects melee is the engine's own"
    elseif v ~= nil and type(v) ~= "number" then
        return "velocity is not a number"
    elseif obj.school ~= nil and not s then
        return "unknown school " .. tostring(obj.school)
    elseif k == X.FLIGHT and not v then
        return "travel needs velocity"
    elseif k == X.TICKS and not (au and au.dot == "debuff") then
        return "ticks needs an aura with tick_time and dot = \"debuff\""
    elseif k == X.CHANNEL and not au then
        return "channel needs an aura with tick_time"
    elseif k == X.STRIKE and not obj.onNextSwing then
        return "strike needs onNextSwing"
    end
end
X.Malformed = malformed -- the pack check (tests/Forever/expects_spec.lua) runs the build's own rule

I.OnBuild(function(def)
    local SCHOOL = ns.SCHOOL
    local byKey = {} -- once a build
    for j = 1, #(def.auras or {}) do
        local au = def.auras[j]
        if type(au) == "table" and au.key then
            byKey[au.key] = au
        end
    end
    for a = 1, A.n do
        local obj = def.abilities[a]
        local e = rawget(obj, "expects")
        local s = type(obj.school) == "string" and SCHOOL[obj.school] or nil
        local au = tickAura(obj, A.key[a], byKey)
        local kind, school, declared = default(obj), X.ANY, false
        A.velocity[a] = 0
        if e == nil then
            if s then
                school = s -- a default type whose ability names its school checks it
            elseif obj.school ~= nil then
                I.nowErrors, I.nowError = I.nowErrors + 1, "expects: " .. tostring(A.key[a]) .. " unknown school " .. tostring(obj.school)
            end
        else
            local k = type(e) == "string" and X.KIND[e] or nil
            local why = malformed(obj, e, k, s, au)
            if why then
                I.nowErrors, I.nowError = I.nowErrors + 1, "expects: " .. tostring(A.key[a]) .. " " .. why
            else
                kind, school, declared = k, s or 0, true
                A.velocity[a] = obj.velocity or 0
            end
        end
        local direct = declared and (kind == X.FRAME or kind == X.FLIGHT) and au and au.dot == "debuff"
        local ticks = kind == X.TICKS or kind == X.CHANNEL or direct == true
        A.expKind[a], A.school[a], A.expDeclared[a] = kind, school, declared
        A.tickAura[a], A.ticking[a] = ticks and au or false, ticks
    end
end)
```

Add to `src/Hekili/Hekili.toc` after line 29 (`Game\State\Families\Now.lua`):

```
Game\State\Families\Expect.lua
```

- [ ] **Step 5: Run it and the specs that use the fake spec**

Run: `.lua/bin/busted tests/Game/State/expect_spec.lua && make test-fast`
Expected: PASS (expect_spec 16 successes; test-fast 0 failures: the old fake spec gains nothing without `expect`).

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Game/State/Families/Expect.lua src/Hekili/Hekili.toc tests/Game/State/helpers/fake_spec.lua \
  tests/Game/State/expect_spec.lua
git commit -m "feat(expect): compile expects, school, velocity, dot; ticking kinds read their aura; validate

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 5: Refactor: the ticket pool and the MELEE kind out of Rows (behaviour preserved)

**Files:**
- Create: `src/Hekili/Game/Events/Tickets.lua` (the pool, first form)
- Create: `src/Hekili/Game/Events/Melee.lua` (Rows.lua lines 28-49, 57-93, 115-116, 186-279, 365-429 moved)
- Modify: `src/Hekili/Game/Events/Rows.lua` (the `act*` ring and the moved functions removed; every use renamed)
- Modify: `src/Hekili/Hekili.toc:48` (after `Game\Events\CombatLog.lua`: `Game\Events\Tickets.lua`,
  `Game\Events\Melee.lua`, then the existing `Game\Events\Rows.lua`)
- Test: the existing `tests/Game/Events/pairing_replay_spec.lua`, `cleu_rows_spec.lua`, the harness specs, unchanged;
  `tests/Game/Events/tickets_spec.lua` (new, the pool's own two cases)

**Interfaces:**
- Consumes: `I.Expect.MELEE`, `I.Expect.FRAME` (Task 4), `I.Log`, `VS.Stat`.
- Produces: `I.Tickets` (first form): `T.CAP` 16; arrays `T.state`, `T.kind`, `T.x`, `T.guid`, `T.at`, `T.w`, `T.ref`,
  `T.lr`, `T.avoid`; `T.FREE` 0, `T.OPEN` 2, `T.PROV` 3; `T.Hold(kind, x, guid, w, t, ref) -> i`; `T.Close(i)`.
  `I.Melee`: `M.SAME_FRAME` 0.05, `M.CAST_WINDOW` 0.2, `M.STRIKE_WINDOW` 0.2, `M.AVOIDS`,
  `M.classOf(h, amount, flag)`, `M.density(i, t) -> f, ref`, `M.learn(ref, d)`, `M.lambda(c)`, `M.advance(t)`,
  `M.pending(t)`, `M.thetaIndex(h, cls, ref, d)`, `M.score(t, g, amount, flag, avoid, unknown) -> best|nil, lr, ref,
  lag, second, idx` (`g` nil: any GUID, as today), `M.background(act, amount, flag, white, avoid, unknown)`; the `L.*`
  tuning values and `L.LandWindow` keep their names.
- Boundary: Melee owns the MELEE rule; Tickets owns the records; Rows owns the rows and the staging.

Behaviour guarantee: the moved code is the same statements over the same values; the pool grows from 8 to 16 slots
(the oldest still gives way when full, which 16 open commits within 2 s never reach in any existing stream).

- [ ] **Step 1: Write the failing test** `tests/Game/Events/tickets_spec.lua`:

```lua
-- tests/Game/Events/tickets_spec.lua (unit-registry spec §3): the ticket pool. Task 5's form: holding and closing;
-- Tasks 6-9 add the lifecycle, the consumption order and the kinds.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the ticket pool", function()
    local api, ctl, ns, VS, I, T, X, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X = I.Tickets, I.Expect
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("holds 16 commits and gives the oldest way when full", function()
        for k = 1, T.CAP do
            T.Hold(X.MELEE, 1, "Creature-1", 1.5, k, 0)
        end
        local i = T.Hold(X.MELEE, 2, "Creature-1", 2.0, 100, 0)
        assert.are.same({ 100, 2, T.OPEN }, { T.at[i], T.x[i], T.state[i] })
        local open = 0
        for j = 1, T.CAP do
            open = open + (T.state[j] ~= T.FREE and 1 or 0)
        end
        assert.are.equal(T.CAP, open)
    end)

    it("frees a closed ticket for the next commit", function()
        local i = T.Hold(X.FRAME, fs.SPENDER_C, "Creature-1", 0.6, 5, 0)
        T.Close(i)
        assert.are.equal(T.FREE, T.state[i])
        assert.are.equal(i, T.Hold(X.FRAME, fs.SPENDER_C, "Creature-1", 0.6, 6, 0))
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua`
Expected: FAIL, `attempt to index local 'T' (a nil value)`.

- [ ] **Step 3: Create** `src/Hekili/Game/Events/Tickets.lua` (first form):

```lua
-- Game/Events/Tickets.lua
-- The ticket pool (unit-registry spec §3): one record per commit of ours, preallocated (TICKETS = 16; Rows held 8, and
-- a 2.1 s flight window plus two hands needs more). This file owns the records and their lifecycle; the matching rules
-- live in Events/Melee.lua (MELEE) and Events/Kinds.lua (every other kind); Events/Rows.lua turns payments into rows.
-- Pure: no client read. Allocates nothing after load.

local _, ns = ...
local I = ns.VirtualStateInternal

local T = {}
I.Tickets = T
T.CAP = 16
T.FREE, T.COMMITTED, T.OPEN, T.PROV = 0, 1, 2, 3
local CAP = T.CAP

-- Per ticket: state, kind (I.Expect's), x (hand for a swing, spell ID for a spell), the pinned GUID, the anchor time,
-- the window length, an off-hand swing's main reference, and a provisional avoid's LR and action ("" none).
T.state, T.kind, T.x, T.guid, T.at, T.w, T.ref, T.lr, T.avoid = {}, {}, {}, {}, {}, {}, {}, {}, {}
local state, kind, x, guid, at, w, ref, lr, avoid = T.state, T.kind, T.x, T.guid, T.at, T.w, T.ref, T.lr, T.avoid
for i = 1, CAP do
    state[i], kind[i], x[i], guid[i], at[i], w[i], ref[i], lr[i], avoid[i] = 0, 0, 0, "", 0, 0, 0, 0, ""
end

--- A free ticket, else the oldest open one (it gives way, unemitted). Allocates nothing.
function T.Slot()
    local oldest = 1
    for i = 1, CAP do
        if state[i] == 0 then
            return i
        elseif at[i] < at[oldest] then
            oldest = i
        end
    end
    return oldest
end

--- Opens a ticket of `k` for `xx` pinned to `g` ("" none) at t with window `win` s and main reference `mref`.
function T.Hold(k, xx, g, win, t, mref)
    local i = T.Slot()
    state[i], kind[i], x[i], guid[i], at[i], w[i] = T.OPEN, k, xx, g, t, win
    ref[i], lr[i], avoid[i] = mref or 0, 0, ""
    return i
end

--- Frees ticket i.
function T.Close(i)
    state[i], lr[i], avoid[i] = 0, 0, ""
end
```

- [ ] **Step 4: Create** `src/Hekili/Game/Events/Melee.lua` (Rows.lua's swing scoring, moved; each statement as it
  was, `actT/actKind/actX/actDst/actW/actRef/actLR/actAvoid` read through the pool):

```lua
-- Game/Events/Melee.lua
-- The MELEE kind (unit-registry spec §3.3, §3.4; moved unchanged from Events/Rows.lua): a white (school 1) outcome is
-- scored against our open swing tickets, LR = q(amount class) x f(landing lag) / lambda(the learned background rate of
-- that class), and credited to the best swing when LR >= THETA (avoids) or theta[k] (wounds), else it is background.
-- The landing-lag density per reference (main from its swing; off from its own swing or its main reference), learned
-- from clean credits; the amount classes from UnitDamage; the background rates over the quiet time. Also the frame
-- constants every spell kind shares. Pure: reads VS.Stat only.
-- Measured: docs/research/2026-10-16-swing-outcome-pairing.md (P), docs/research/2026-10-16-group-pairing-captures.md
-- (G, G5).

local _, ns = ...
local I = ns.VirtualStateInternal
local VS = ns.VirtualState
local L = I.Log
local T, X = I.Tickets, I.Expect

local M = {}
I.Melee = M

-- Per hand (1 main, 2 off), the support of a swing's landing lag (ms), capped at the hand's swing period: measured
-- maximum lags 1287 / 1686 ms plus a margin (P log 2).
L.PAIR_WINDOW_MS = { 1500, 2000 }
-- Seconds a cast waits for its own wound, and within which an on-next-swing strike's success and its swing are one
-- event pair (the same frame, log 1).
M.CAST_WINDOW, M.STRIKE_WINDOW = 0.2, 0.2
-- Seconds within which a cast's own wound comes (its frame); also the foreign strike frame after a WOUND 0
-- (G 177249/177250).
M.SAME_FRAME = 0.05
local CAST_WINDOW = M.CAST_WINDOW
-- The window our cast's own avoid may follow its success in: a main-hand landing lag's window (the learned median
-- plus three spreads). Hand h's; also how long a swing's rage stays pending (VS.SwingPending).
function L.LandWindow(h)
    return L.med[h] + 3 * L.spr[h]
end
-- GAP AX (docs/dev/gaps.md): the landing window holds for a refused avoid only while L.bg[7] stays below this.
-- UNMEASURED: a chosen constant (GAP AX residue in docs/dev/gaps.md).
L.FOREIGN_AVOIDS = 0.05

-- The score (harness design §1.2-§1.4, decision D1; PROTOTYPE values, the harness's gates hold them).
L.THETA = 5
L.Q = { 0.90, 0.08, 0.02 }
L.Q_AVOID = 0.22
L.EPS = { 0.12, 0.10 }
L.LAMBDA0, L.T0, L.TAU = 0.01, 5, 10
-- The landing lag per reference (1 main; 2 off from its own swing; 3 off from the latest main swing), seeds
-- (MEASURED: P log 2, G5) learned online from clean credits.
L.med, L.spr = { 0.474, 0.703, 1.686 }, { 0.060, 0.020, 0.020 }
-- The background: per class (1-3 main exact, loose, above; 4-6 off; 7 avoid; 8 white, any amount) and the quiet time.
L.bg, L.quiet = { 0, 0, 0, 0, 0, 0, 0, 0 }, 0
local lastT = 0
L.credited, L.background, L.avoidsBack = { 0, 0, 0 }, 0, 0
L.avoids, L.avoidX, L.avoidT = 0, 0, 0
-- The usability oracle (harness design §2, decision D8).
L.ORACLE_MIN = 0.1
L.THETA_MIN, L.THETA_MAX = 2, 16
L.theta = {}
for k = 1, 16 do
    L.theta[k] = L.THETA
end
L.oracle = { judged = 0, confirmed = 0, retracted = 0, soft = 0, vetoed = 0 }
L.vetoX, L.vetoAt = 0, 0

-- The avoids a swing can have (school 1).
M.AVOIDS = { DODGE = true, PARRY = true, MISS = true, BLOCK = true, DEFLECT = true, EVADE = true }
local AVOIDS = M.AVOIDS

--- Whether an action of ours is pending at t for the background: a swing, or a spell within CAST_WINDOW of its
--- anchor (past it a spell waits only for an avoid, which the background's wound rates do not see).
function M.pending(t)
    for i = 1, T.CAP do
        if T.state[i] ~= 0 and (T.kind[i] == X.MELEE or t - T.at[i] <= CAST_WINDOW) then
            return true
        end
    end
    return false
end

--- The background's clock: in combat the counts and the quiet time decay by exp(-dt / TAU), and the quiet time grows
--- while nothing of ours is pending. Allocates nothing.
function M.advance(t)
    if t <= lastT then
        return
    end
    if I.inCombat then
        local dt = t - lastT
        local k = math.exp(-dt / L.TAU)
        local bg = L.bg
        for c = 1, 8 do
            bg[c] = bg[c] * k
        end
        L.quiet = L.quiet * k + (M.pending(t) and 0 or dt)
    end
    lastT = t
end

--- The background rate of class c (nonzero: T0 > 0).
function M.lambda(c)
    return (L.bg[c] + L.LAMBDA0 * L.T0) / (L.quiet + L.T0)
end

--- The amount class of a wound for hand h (1 exact, 2 loose, 3 above, 0 none), on half a crit (Rows.lua's rule).
function M.classOf(h, amount, flag)
    local minMain, maxMain, minOff, maxOff = VS.Stat("UnitDamage")
    local lo, hi = minMain, maxMain
    if h == 2 then
        lo, hi = minOff, maxOff
    end
    if flag == "CRITICAL" then
        amount = amount / 2
    end
    local looseLo = 0.6 * lo
    if flag == "GLANCING" or flag == "BLOCK_REDUCED" then
        looseLo = 0
    end
    if hi <= 0 or amount < looseLo or amount > 2 * hi then
        return 0
    elseif amount >= lo and amount <= hi then
        return 1
    end
    return amount <= 1.1 * hi and 2 or 3
end

local function normal(d, m, s)
    local z = (d - m) / s -- nonzero: spr clamped at 0.02 s
    return math.exp(-0.5 * z * z) / (s * 2.5066283)
end

--- The landing-lag density of swing ticket i for an outcome at t (0 outside its window) and the reference that scored.
function M.density(i, t)
    local d, win = t - T.at[i], T.w[i]
    if d < 0 or d > win then
        return 0, 0
    end
    local med, spr = L.med, L.spr
    if T.x[i] == 1 then
        return (1 - L.EPS[1]) * normal(d, med[1], spr[1]) + L.EPS[1] / win, 1 -- nonzero: win > 0
    end
    local f, r = normal(d, med[2], spr[2]), 2
    if T.ref[i] > 0 then
        local m = normal(t - T.ref[i], med[3], spr[3])
        if m > f then
            f, r = m, 3
        end
    end
    return (1 - L.EPS[2]) * f + L.EPS[2] / win, r -- nonzero: win > 0
end

--- A clean credit moves its reference's median and spread (a running median; mean absolute deviation to SD).
function M.learn(r, d)
    local med, spr = L.med, L.spr
    med[r] = med[r] + 0.005 * (d > med[r] and 1 or -1)
    local s = spr[r] + 0.05 * (1.2533 * math.abs(d - med[r]) - spr[r])
    spr[r] = s < 0.02 and 0.02 or (s > 0.4 and 0.4 or s)
    local win = L.PAIR_WINDOW_MS[r == 1 and 1 or 2] / 1000
    med[r] = med[r] < 0 and 0 or (med[r] > win and win or med[r])
end

--- The theta index of hand h's amount class `cls` (1-3, 4 unknown) at lag d from reference `r`: core band or tail.
function M.thetaIndex(h, cls, r, d)
    local band = math.abs(d - L.med[r]) <= 2 * L.spr[r] and 1 or 2
    return (h - 1) * 8 + (cls - 1) * 2 + band
end

--- The best open swing ticket on `g` (nil: any) for an outcome at t: its index, LR, reference, lag, the runner-up's LR
--- and its theta index. Allocates nothing.
function M.score(t, g, amount, flag, avoid, unknown)
    local best, bestLR, r0, lag, second, idx = nil, 0, 0, 0, 0, 1
    for i = 1, T.CAP do
        if
            T.state[i] ~= 0
            and T.kind[i] == X.MELEE
            and (g == nil or T.guid[i] == g)
            and not (avoid and T.avoid[i] ~= "")
        then
            local f, r = M.density(i, t)
            local q, c, cls = L.Q_AVOID, 7, 4
            if not avoid then
                if unknown then
                    q, c = 1, 8
                else
                    cls = M.classOf(T.x[i], amount, flag)
                    q, c = cls > 0 and L.Q[cls] or 0, (T.x[i] - 1) * 3 + cls
                end
            end
            local lri = f > 0 and q > 0 and q * f / M.lambda(c) or 0
            if lri > T.lr[i] or T.avoid[i] == "" then -- a wound takes a provisionally avoided swing only by beating it
                if lri > bestLR then
                    local d = r == 3 and t - T.ref[i] or t - T.at[i]
                    best, bestLR, r0, lag, second = i, lri, r, t - T.at[i], bestLR
                    idx = M.thetaIndex(T.x[i], cls, r, d)
                elseif lri > second then
                    second = lri
                end
            end
        end
    end
    return best, bestLR, r0, lag, second, idx
end

--- An outcome nobody of ours claimed: counted, and while in combat with nothing of ours pending it teaches the
--- background rate of each white class it qualifies for (§1.3, §1.4).
function M.background(act, amount, flag, white, avoid, unknown)
    L.background = L.background + 1
    if M.pending(lastT) or not I.inCombat or not white then
        return
    end
    local bg = L.bg
    if avoid then
        if AVOIDS[act] then
            bg[7] = bg[7] + 1
        end
        return
    end
    bg[8] = bg[8] + 1
    if not unknown then
        for h = 1, 2 do
            local cls = M.classOf(h, amount, flag)
            if cls > 0 then
                bg[(h - 1) * 3 + cls] = bg[(h - 1) * 3 + cls] + 1
            end
        end
    end
end
```

- [ ] **Step 5: Shrink Rows.lua.** Delete the moved lines (28-49 except line 50-55's unmapped block, 57-93, 104-111,
  115-116, 129-151's `free`, 186-279, 365-429). At the top, after `local L = I.Log` (line 26), add:

```lua
local T, M, X = I.Tickets, I.Melee, I.Expect
local SAME_FRAME, CAST_WINDOW, STRIKE_WINDOW = M.SAME_FRAME, M.CAST_WINDOW, M.STRIKE_WINDOW
local AVOIDS, MELEE, FRAME = M.AVOIDS, X.MELEE, X.FRAME
local lastW0, lastMain = -1, 0
```

  Keep the credit records (lines 94-103), `MISSES` (117-127), `REFUSED`, `another`, `avoided`, `emit`, the handlers,
  `I.CreditVerdict`, the tick, the combat end and Snapshot. Replace `cast` with:

```lua
-- Our open cast still in its window at `t` (or within `age` s of it), the oldest first.
local function cast(t, age)
    local best
    for i = 1, T.CAP do
        local a = T.at[i]
        if T.state[i] ~= 0 and T.kind[i] == FRAME and t - a <= (age or T.w[i]) and (not best or a < T.at[best]) then
            best = i
        end
    end
    return best
end
```

  and `hold` with:

```lua
local function hold(kind, xx, dst, win, t)
    return T.Hold(kind == 1 and MELEE or FRAME, xx, dst, win, t, kind == 1 and xx == 2 and lastMain or 0)
end
```

  Then apply this rename to the rest of Rows.lua, as a script (each pattern is exact; run from the worktree root):

```bash
sed -i \
  -e 's/actT\[\([a-z]*\)\] > 0 and actKind\[\1\] == 2/T.state[\1] ~= 0 and T.kind[\1] == FRAME/g' \
  -e 's/actT\[\([a-z]*\)\] > 0 and actKind\[\1\] == 1/T.state[\1] ~= 0 and T.kind[\1] == MELEE/g' \
  -e 's/actKind\[\([a-z]*\)\] == 1/T.kind[\1] == MELEE/g' \
  -e 's/actT\[\([a-z]*\)\] = 0$/T.Close(\1)/' \
  -e 's/actT\[\([a-z]*\)\], actAvoid\[\1\], actLR\[\1\] = 0, "", 0/T.Close(\1)/' \
  -e 's/actT\[i\], actAvoid\[i\], actLR\[i\] = 0, "", 0/T.Close(i)/' \
  -e 's/actT\[/T.at[/g; s/actX\[/T.x[/g; s/actDst\[/T.guid[/g; s/actW\[/T.w[/g' \
  -e 's/actRef\[/T.ref[/g; s/actLR\[/T.lr[/g; s/actAvoid\[/T.avoid[/g' \
  -e 's/for i = 1, N do/for i = 1, T.CAP do/g' \
  -e 's/\badvance(/M.advance(/g; s/\bbackground(/M.background(/g; s/\bscore(t, /M.score(t, nil, /g' \
  -e 's/\bclassOf(/M.classOf(/g; s/\blearn(ref, d)/M.learn(ref, d)/g; s/\blambda(/M.lambda(/g' \
  src/Hekili/Game/Events/Rows.lua
```

  Three spots the script cannot express, by hand:
  - `another(p, t)`: its loop condition becomes
    `if i ~= p and T.state[i] ~= 0 and T.kind[i] == FRAME and t - T.at[i] <= T.w[i] then`.
  - the provisional avoid in the `OnRow` body stays `T.lr[credited], T.avoid[credited] = lr, act`.
  - the strike replacement's loop (old lines 353-357) sets `T.at[i], found = 0, true` after the script; make it
    `T.Close(i)` then `found = true` on the next line.
  - the tick loop: replace its body with

```lua
L.OnTick(function(now)
    M.advance(now)
    for i = 1, T.CAP do
        local t = T.at[i]
        if T.state[i] ~= 0 and now - t > T.w[i] then
            if T.kind[i] == MELEE then
                emit(1, T.x[i], T.guid[i], T.avoid[i] ~= "" and T.avoid[i] or "WOUND", "", 0, t)
            end
            T.Close(i)
        end
    end
end)
```

  and the combat end's loop body with `T.Close(i)`.
  - `I.CreditVerdict`'s re-open (old line 582) becomes `hold(1, hand, recDst[id], recW[id], at)` followed by
    `T.ref[...]`: write it as

```lua
        if t - at <= recW[id] then
            local i = hold(1, hand, recDst[id], recW[id], at)
            T.ref[i] = recRef[id]
```

  - Snapshot's `lambda(1), lambda(4), lambda(7)` read `M.lambda(1), M.lambda(4), M.lambda(7)` (the script did it).

Add to `src/Hekili/Hekili.toc` after line 48 (`Game\Events\CombatLog.lua`):

```
Game\Events\Tickets.lua
Game\Events\Melee.lua
```

- [ ] **Step 6: Check nothing of the old ring is left in Rows**

Run: `grep -nE "act(T|Kind|X|Dst|W|Ref|LR|Avoid)\b|local N = 8|^local function (classOf|density|learn|score|background|advance|pending)" src/Hekili/Game/Events/Rows.lua`
Expected: no output.

- [ ] **Step 7: Run the pool test, then every existing spec unchanged**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua && make test-fast && .lua/bin/busted --tags=slow tests/Game/harness/group_spec.lua tests/Game/harness/solo_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/alloc_spec.lua tests/Game/harness/flicker_spec.lua`
Expected: PASS, 0 failures; `group_spec.lua`'s printed numbers equal Task 3's run. Any moved number stops the task.

- [ ] **Step 8: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Melee.lua src/Hekili/Game/Events/Rows.lua \
  src/Hekili/Hekili.toc tests/Game/Events/tickets_spec.lua
git commit -m "refactor(rows): the pending ring becomes the ticket pool; the swing LR moves to Melee.lua

No decision changes: every existing spec passes unchanged.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 5b: Combat-log row builders (part of the Rows shrink)

**Files:**
- Modify: `src/Hekili/Game/Events/CombatLog.lua` (after `L.Energize`, line 215: `L.Swing`, `L.SpellHit`, `L.Miss`)
- Modify: `src/Hekili/Game/Events/Rows.lua` (`emit`, Rows.lua:281-306 before Task 5)
- Modify: `src/Hekili/Game/Events/Attackers.lua:274-288` (the three hand-written rows)
- Test: `tests/Game/Events/cleu_rows_spec.lua` (cases added)

**Interfaces:**
- Consumes: `L.Emit` (`CombatLog.lua:46`).
- Produces: `L.Swing(t, family, src, srcFlags, dst, dstFlags, amount, flag, offhand)` (SWING_DAMAGE, 21 slots);
  `L.SpellHit(sub, t, family, src, srcFlags, dst, dstFlags, spellID, school, amount, flag)` (SPELL_DAMAGE or
  SPELL_PERIODIC_DAMAGE, 24 slots, `school` in slots 14 and 17); `L.Miss(t, family, src, srcFlags, dst, dstFlags,
  spellID, school, action, offhand)` (SWING_MISSED when `spellID` is nil, else SPELL_MISSED with `school` in slot 14).
  All back-dated, `inferred`, allocating nothing.
- Boundary: CombatLog owns the row shapes beside `L.Cast` (:77), `auraRow` (:158) and `L.Energize` (:208); Rows and
  Attackers only choose what to emit.

Behaviour guarantee: Rows passes school 1 to its spell rows here, exactly as it writes today (`Rows.lua:300`, `:304`),
and Attackers its real mask (`:280-281`); Task 6 then passes the ticket's school (its test asserts the own
SPELL_DAMAGE row's school equals the ability's compiled school). The one difference between the two hand-written
encodings becomes a parameter.

- [ ] **Step 1: Write the failing test.** Append inside `describe("the synthesized combat log", ...)` of
  `tests/Game/Events/cleu_rows_spec.lua`:

```lua
    it("builds the swing, spell and miss rows in one place, each with the school it is given", function()
        ctl.now = 5
        L.Swing(4.9, "swing", "Player-1", L.PLAYER_FLAGS, "Creature-1", L.HOSTILE_FLAGS, 30, "CRITICAL", true)
        L.SpellHit("SPELL_DAMAGE", 4.8, "damage", "Player-1", L.PLAYER_FLAGS, "Creature-1", L.HOSTILE_FLAGS, 99, 8, 15, "")
        L.Miss(4.7, "missed", "Player-1", L.PLAYER_FLAGS, "Creature-1", L.HOSTILE_FLAGS, 99, 1, "MISS")
        L.Miss(4.6, "missed", "Player-1", L.PLAYER_FLAGS, "Creature-1", L.HOSTILE_FLAGS, nil, 1, "DODGE", true)
        L.Deliver()
        assert.are.same({ "SWING_DAMAGE", 21, 30, true, true }, { got[1].row[2], got[1].n, got[1].row[12],
            got[1].row[18], got[1].row[21] })
        assert.are.same({ "SPELL_DAMAGE", 24, 99, 8, 15, 8 }, { got[2].row[2], got[2].n, got[2].row[12],
            got[2].row[14], got[2].row[15], got[2].row[17] })
        assert.are.same({ "SPELL_MISSED", 18, 1, "MISS" }, { got[3].row[2], got[3].n, got[3].row[14], got[3].row[15] })
        assert.are.same({ "SWING_MISSED", 15, "DODGE", true }, { got[4].row[2], got[4].n, got[4].row[12],
            got[4].row[13] })
    end)

    it("leaves no hand-written combat-log row outside CombatLog.lua", function()
        for _, f in ipairs({ "src/Hekili/Game/Events/Rows.lua", "src/Hekili/Game/Events/Attackers.lua" }) do
            local src = assert(io.open(f)):read("*a")
            assert.is_nil(src:find("L.Emit(", 1, true), f)
        end
    end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/Events/cleu_rows_spec.lua`
Expected: FAIL, `attempt to call field 'Swing' (a nil value)` and the `L.Emit(` finds in both files.

- [ ] **Step 3: The builders.** In `src/Hekili/Game/Events/CombatLog.lua`, after `L.Energize`'s `end` add:

```lua
--- (unit-registry spec §3.5) A white hit's row: SWING_DAMAGE at `t` (back-dated), from `src` to `dst`. Allocates
--- nothing.
function L.Swing(t, family, src, srcFlags, dst, dstFlags, amount, flag, offhand)
    local r = L.Emit("SWING_DAMAGE", 21, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
    r[12], r[13], r[14], r[15], r[16], r[17] = amount, 0, 1, 0, 0, 0
    r[18], r[19], r[20], r[21] = flag == "CRITICAL", flag == "GLANCING", flag == "CRUSHING", offhand == true
end

--- A spell's damage row (`sub`: SPELL_DAMAGE or SPELL_PERIODIC_DAMAGE) with `school` in slots 14 and 17.
function L.SpellHit(sub, t, family, src, srcFlags, dst, dstFlags, spellID, school, amount, flag)
    local r = L.Emit(sub, 24, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
    r[12], r[13], r[14], r[15], r[16], r[17], r[18] = spellID, "", school, amount, 0, school, 0
    r[19], r[20], r[21], r[22], r[23], r[24] = 0, 0, flag == "CRITICAL", false, false, false
end

--- An avoid's row: SWING_MISSED for a swing (`spellID` nil), else SPELL_MISSED with `school` in slot 14.
function L.Miss(t, family, src, srcFlags, dst, dstFlags, spellID, school, action, offhand)
    if spellID == nil then
        local r = L.Emit("SWING_MISSED", 15, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
        r[12], r[13], r[14], r[15] = action, offhand == true, 0, false
        return
    end
    local r = L.Emit("SPELL_MISSED", 18, t, true, family, "inferred", src, srcFlags, dst, dstFlags)
    r[12], r[13], r[14], r[15], r[16], r[17], r[18] = spellID, "", school, action, false, 0, false
end
```

- [ ] **Step 4: Rows calls them.** Replace Rows.lua's `emit` body (Task 5's form) with:

```lua
local function emit(kind, x, dst, action, flag, amount, t)
    if dst == "" then
        return
    end
    local me, mf, hf = L.player, L.PLAYER_FLAGS, L.HOSTILE_FLAGS
    if kind == 1 then
        if action == "WOUND" then
            L.Swing(t, "swing", me, mf, dst, hf, amount, flag, x == 2)
        else
            L.Miss(t, "missed", me, mf, dst, hf, nil, 1, action, x == 2)
        end
    elseif action == "WOUND" then
        L.SpellHit("SPELL_DAMAGE", t, "damage", me, mf, dst, hf, x, 1, amount, flag) -- school 1 until Task 6
    else
        L.Miss(t, "missed", me, mf, dst, hf, x, 1, action)
    end
end
```

- [ ] **Step 5: Attackers calls them.** Replace Attackers.lua's three row blocks (lines 274-288) with:

```lua
    local amt = type(amount) == "number" and amount or 0
    if act == "WOUND" and melee then
        L.Swing(t, "onus", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS, amt, flag, false)
    elseif act == "WOUND" then
        L.SpellHit("SPELL_DAMAGE", t, "onus", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS, 0,
            type(school) == "number" and school or 1, amt, flag)
    else
        L.Miss(t, "onus", src, L.HOSTILE_FLAGS, dst, L.PLAYER_FLAGS, nil, 1, act, false)
    end
```

- [ ] **Step 6: Run the row specs and everything that reads rows**

Run: `.lua/bin/busted tests/Game/Events && make test-fast`
Expected: PASS, 0 failures (the rows are slot for slot what they were).

- [ ] **Step 7: Commit**

```bash
git add src/Hekili/Game/Events/CombatLog.lua src/Hekili/Game/Events/Rows.lua src/Hekili/Game/Events/Attackers.lua \
  tests/Game/Events/cleu_rows_spec.lua
git commit -m "refactor(log): SWING/SPELL/MISS row builders in CombatLog; Rows and Attackers call them

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 5c: Drop the redundant payload re-Plain calls (part of the Rows shrink)

**Files:**
- Modify: `src/Hekili/Game/Events/Attackers.lua:202`, `src/Hekili/Game/State/Sources/Player.lua:170`,
  `src/Hekili/Game/State/Sources/Casts.lua:42`, `:69`, `:83`, `:99`, `:114` (each a `Plain` on a handler argument)
- Test: `tests/Game/State/secrets_spec.lua` (a case added)

**Interfaces:**
- Consumes: `EventFacade.lua:221-226` (every payload slot already through `Plain` before any source runs).
- Produces: no new function. Every `Plain` on a direct API read stays (the grep below lists the payload ones only).
- Boundary: the facade is the one gate for event payloads; sources gate their own API reads.

- [ ] **Step 1: Write the failing test.** Append inside the top `describe` of `tests/Game/State/secrets_spec.lua`:

```lua
    it("delivers a secret payload slot to the sources as nil, so no handler re-gates its arguments", function()
        local load = require("Game.State.helpers.load")
        local fake = require("Game.State.helpers.fake_api")
        local fs = require("Game.State.helpers.fake_spec")
        local api, ctl = fake.new()
        local saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        local ns = load.module()
        local I = ns.VirtualStateInternal
        I.Build(fs.def(fs.new(9)), 1)
        ns.VirtualState.Start(api)
        local seen = "unset"
        I.Sources.On("UNIT_COMBAT", nil, function(_, _, _, _, flag, amount)
            seen = { flag, amount }
        end)
        ctl.Fire("UNIT_COMBAT", "player", "WOUND", fake.SECRET, fake.SECRET, 1)
        assert.are.same({}, seen) -- both nil
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
        -- and no source re-gates a handler argument
        local hits = {}
        for _, f in ipairs({ "src/Hekili/Game/Events/Attackers.lua", "src/Hekili/Game/State/Sources/Player.lua",
            "src/Hekili/Game/State/Sources/Casts.lua" }) do
            local src = assert(io.open(f)):read("*a")
            for m in src:gmatch("Plain%(api, (%a+)%)") do
                if m == "flag" or m == "amount" or m == "act" or m == "guid" then
                    hits[#hits + 1] = f .. ": Plain(api, " .. m .. ")"
                end
            end
        end
        assert.are.same({}, hits)
    end)
```

  (`S.On` registered after Start is not in the client registration, but `UNIT_COMBAT` is already registered by the
  registry, so the fake delivers it to every handler in the list.)

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/State/secrets_spec.lua`
Expected: FAIL on the second assertion, listing `Attackers.lua: Plain(api, flag)`, `Player.lua: Plain(api, act)`
and the `Plain(api, guid)` lines of `Casts.lua`.

- [ ] **Step 3: Remove them.** `Attackers.lua:202`: delete the line
  `flag, amount = Plain(api, flag), Plain(api, amount) -- a secret one is neither banded nor learned` (the facade
  already made a secret slot nil). `Player.lua:170`: delete
  `act, flag, amount = Plain(api, act), Plain(api, flag), Plain(api, amount) -- a secret number answers "number" to type`.
  `Casts.lua`: `castGUID = Plain(api, guid)` (:42) becomes `castGUID = guid`; `local g = Plain(api, guid)` (:69, :83,
  :114) becomes `local g = guid`; `chanGUID = Plain(api, guid)` (:99) becomes `chanGUID = guid`. Each comment above
  them that names the re-gate is shortened to `-- the facade made a secret slot nil (EventFacade.lua:221-226)`.

- [ ] **Step 4: Run it and every spec**

Run: `.lua/bin/busted tests/Game/State/secrets_spec.lua && make test-fast`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Game/Events/Attackers.lua src/Hekili/Game/State/Sources/Player.lua \
  src/Hekili/Game/State/Sources/Casts.lua tests/Game/State/secrets_spec.lua
git commit -m "refactor(sources): the facade gates event payloads once; handlers drop their re-Plain

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 6: Tickets: lifecycle, consumption order and the FRAME, STRIKE, UNMAPPED and NONE kinds

**Files:**
- Modify (rewrite): `src/Hekili/Game/Events/Tickets.lua` (the pool's lifecycle)
- Create: `src/Hekili/Game/Events/Kinds.lua`
- Modify: `src/Hekili/Game/Events/Melee.lua` (`M.pending` skips UNMAPPED tickets)
- Modify (rewrite): `src/Hekili/Game/Events/Rows.lua`
- Modify: `src/Hekili/Hekili.toc` (add `Game\Events\Kinds.lua` after `Game\Events\Melee.lua`)
- Modify: `tests/Game/State/now_spec.lua:1012-1024` (the two-casts case: see Step 9)
- Test: `tests/Game/Events/tickets_spec.lua` (rewritten), `tests/Game/Events/kinds_spec.lua` (new)

**Interfaces:**
- Consumes: `I.Units` (`Find`, `Hold`, `Release`, `IsDead`, `Ours`, `IsTarget`, `OnRow`, `OnGone`, `GONE`, `Pin`,
  `Sent`), `I.Expect`, `A.expKind`, `A.school`, `I.Melee`, `L.LandWindow`, `L.UNMAPPED_WINDOW` (moved to Kinds).
- Produces (`I.Tickets`): arrays `state, kind, ab, x, guid, uid, school, owed, at, hi, w, ref, lr, avoid, cast, done,
  first`; `T.Slot(t) -> i`; `T.OpenSwing(t, hand, g, win, mref, isFirst) -> i`; `T.OpenCast(t, a, spellID, g) -> i|0`;
  `T.Commit(t, a, spellID, g, castGUID) -> i|0`; `T.Arm(castGUID, t) -> i|0`; `T.Stop(castGUID, t)`;
  `T.Pick(t, g, pass, act, flag, amount, school, isAvoid) -> i|0, n`; `T.Pay(i, t, isAvoid, amount, flag, clean, pass)`;
  `T.Provisional(i, lr, act)`; `T.Close(i, t, why)`; `T.Expire(now)`; `T.EndCombat(t)`; `T.Unmapped(t) -> bool`;
  `T.Claims(uid, act, school) -> bool` (installed as `I.Units.Claims`); `T.onExpire` (Rows sets it: `fn(i, now)`);
  `T.onPay` (harness capture hook, nil in game: `fn(i, t, pass)`); counters `T.opened`, `T.closed[why]` (why:
  none, paid, signal, replaced, refreshed, stopped, expired, lost, dead, gone, ended, overflow, unpinned,
  provisional), `T.paid[kind]`, `T.lost[kind]` (rows), `T.ours`, `T.foreign`, `T.absorbed`, `T.divergent`,
  `T.bandRejected`, `T.aoeOther`. (`I.Kinds`): `K.Accepts(i, act, flag, amount, school, isAvoid) -> ok, banded` (banded: a learned amount band accepted the row; `T.Pick` ranks those candidates first within a pass, then expected closure, owner ruling 2026-10-22),
  `K.Band(i, pass, t, isAvoid, act, school) -> lo, hi, E | nil`, `L.UNMAPPED_WINDOW` 2.
- Boundary: Tickets owns records, order and closes; Kinds owns acceptance and bands; Melee owns the swing LR; Rows
  owns the rows and staging and names no window.

Implementation choices: the spec's `CTX` table (decision 14) is not built: every field it lists already lives in the
pool's arrays, the lag records (Task 7) and `A.*`, which Kinds reads directly (one copy fewer). A default-type FRAME
ticket (school ANY) takes a non-white WOUND only in its frame, as today (`Rows.lua:458`, `:497`); a declared school
opens the CAST_WINDOW pass to its own school. A committed hard cast that never stops expires after 60 s as `stopped`
(a lost STOP must not hold a unit forever). A divergent avoid (spec §4.2) pays the oldest candidate and stages nothing
but emits no `SPELL_MISSED` row: Hekili's `missable` would drop the other cast's debuff on that row
(`tests/Game/State/now_spec.lua:1012`'s reason); a divergent crit emits its row, as today.

- [ ] **Step 1: Write the failing tests.** Replace `tests/Game/Events/tickets_spec.lua` with:

```lua
-- tests/Game/Events/tickets_spec.lua (unit-registry spec §3): the ticket pool's lifecycle. One ticket per commit
-- (swing, success mapped or not, a hard cast at its START); payment in expected-closure order on the row's GUID;
-- closes and their counters; the conservation identity.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the ticket pool", function()
    local api, ctl, ns, VS, I, T, X, U, saved, got, cleu

    local function sum()
        local n = 0
        for _, v in pairs(T.closed) do
            n = n + v
        end
        for i = 1, T.CAP do
            n = n + (T.state[i] ~= T.FREE and 1 or 0)
        end
        return n
    end

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X, U = I.Tickets, I.Expect, I.Units
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
        got = {}
        cleu = I.Events.CreateFrame("Frame")
        cleu:SetScript("OnEvent", function()
            local r = { ns.Facade.CombatLogGetCurrentEventInfo() }
            got[#got + 1] = r
        end)
        cleu:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("opens one ticket per commit: a swing, a mapped success, an unmapped one; NONE closes at once", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 999999)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", fs.SPENDER_N)
        assert.are.equal(4, T.opened)
        assert.are.equal(1, T.closed.none)
        assert.are.equal(T.opened, sum())
    end)

    it("pays a row on the ticket's own GUID only; another GUID's row is foreign", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.guid.nameplate2 = "Creature-2"
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "nameplate2", "WOUND", "", 30, 4)
        assert.are.equal(1, T.foreign)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 4)
        assert.are.equal(1, T.paid[X.FRAME])
        assert.are.same({ "SPELL_DAMAGE", "Creature-1", fs.SPENDER_F, 4, 30 }, {
            got[#got][2],
            got[#got][8],
            got[#got][12],
            got[#got][14],
            got[#got][15],
        })
    end)

    it("pays the least expected closure first: the older of two frames", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        local first = T.Arm("none", 0) -- no committed ticket: 0
        assert.are.equal(0, first)
        ctl.now = 10.02
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_F)
        ctl.now = 10.03
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 4)
        local open = 0
        for i = 1, T.CAP do
            if T.state[i] == T.OPEN and T.kind[i] == X.FRAME then
                open = open + 1
                assert.are.equal(10.02, T.at[i])
            end
        end
        assert.are.equal(1, open)
    end)

    it("refuses a WOUND of another school on a declared ticket", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.002
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 4, 32) -- a life-steal proc in the strike's frame
        assert.are.equal(0, T.paid[X.FRAME])
        assert.are.equal(1, T.foreign)
    end)

    it("closes by expiry: lost for a declared school, expired for ANY, unpinned with no pin", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_C)
        ctl.guid.target = nil
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", fs.SPENDER_F)
        ctl.Tick(12)
        assert.are.same({ 1, 1, 1 }, { T.closed.lost, T.closed.expired, T.closed.unpinned })
        assert.are.equal(1, T.lost[X.FRAME])
        assert.are.equal(T.opened, sum())
    end)

    it("commits a hard cast at START, arms it at its success, and drops it uncounted on FAILED", function()
        ctl.casting = { 10000, 11500 }
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-5", fs.SPENDER_C)
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-5", fs.SPENDER_C)
        local i = 0
        for j = 1, T.CAP do
            if T.state[j] == T.COMMITTED then
                i = j
            end
        end
        assert.is_true(i > 0)
        ctl.now = 11.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-5", fs.SPENDER_C)
        assert.are.same({ T.OPEN, 11.5 }, { T.state[i], T.at[i] })
        ctl.now = 12
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-6", fs.SPENDER_C)
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-6", fs.SPENDER_C)
        ctl.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-6", fs.SPENDER_C)
        assert.are.equal(1, T.closed.stopped)
    end)

    it("lets an unmapped success's window absorb an avoid past a cast's frame as nobody's", function()
        ctl.now = 4
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 999999)
        ctl.now = 5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 5.4
        ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
        assert.are.equal(1, T.absorbed)
        assert.are.equal(0, T.paid[X.FRAME])
    end)

    it("claims for the registry a row an open ticket on a unit still owes", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        local u = U.Uid(1)
        assert.is_true(T.Claims(u, "WOUND", 4))
        assert.is_true(T.Claims(u, "MISS", 1))
        assert.is_false(T.Claims(u, "WOUND", 8))
    end)

    it("closes every open ticket at combat end, counted once", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(2, T.closed.ended)
        assert.are.equal(T.opened, sum())
    end)
end)
```

`tests/Game/Events/kinds_spec.lua`:

```lua
-- tests/Game/Events/kinds_spec.lua (unit-registry spec §3.3, §3.4): each kind's acceptance and bands, written once.
-- Task 6: FRAME and STRIKE; Tasks 7 and 8 add FLIGHT, TICKS and CHANNEL.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("the kinds", function()
    local api, ctl, ns, VS, I, T, K, X, L, saved

    local function open(id, t)
        return T.OpenCast(t, I.ab.bySpell[id], id, "Creature-1")
    end

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, K, X, L = I.Tickets, I.Kinds, I.Expect, I.Log
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("FRAME: the frame at pass 1; an avoid's landing window, or CAST_WINDOW once others avoid", function()
        local i = open(fs.SPENDER_F, 10)
        assert.are.same({ 10, 10 + 0.05, 10 }, { K.Band(i, 1, 10.01, false, "WOUND", 4) })
        local lo, hi = K.Band(i, 2, 10.3, true, "DODGE", 1)
        assert.are.same({ 10, 10 + L.LandWindow(1) }, { lo, hi })
        L.bg[7] = 1 -- others avoid on the target too (GAP AX)
        local lo2, hi2 = K.Band(i, 2, 10.1, true, "DODGE", 1)
        assert.are.same({ 10, 10 + 0.2 }, { lo2, hi2 })
        L.bg[7] = 0
        local lo3, hi3 = K.Band(i, 2, 10.1, true, "BLOCK", 1) -- not a refused avoid: the cast's own window
        assert.are.same({ 10, 10 + 0.2 }, { lo3, hi3 })
    end)

    it("FRAME on a default type: a non-white WOUND only in its frame (today's rule)", function()
        local i = open(fs.SPENDER_C, 10)
        assert.is_nil(K.Band(i, 2, 10.1, false, "WOUND", 8))
        assert.is_truthy(K.Band(i, 2, 10.1, false, "WOUND", 1))
    end)

    it("accepts by school: equal mask, ANY, or none (only an avoid)", function()
        local f, c = open(fs.SPENDER_F, 10), open(fs.SPENDER_C, 10)
        assert.is_true(K.Accepts(f, "WOUND", "", 30, 4, false))
        assert.is_false(K.Accepts(f, "WOUND", "", 30, 8, false))
        assert.is_true(K.Accepts(f, "MISS", "", 0, 1, true))
        assert.is_true(K.Accepts(c, "WOUND", "", 30, 32, false))
        T.school[f] = 0
        assert.is_false(K.Accepts(f, "WOUND", "", 30, 4, false))
        assert.is_true(K.Accepts(f, "PARRY", "", 0, 1, true))
    end)
end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/Events/kinds_spec.lua`
Expected: FAIL, `attempt to index field 'Kinds' (a nil value)` and `attempt to call field 'OpenCast' (a nil value)`.

- [ ] **Step 3: Rewrite** `src/Hekili/Game/Events/Tickets.lua`:

```lua
-- Game/Events/Tickets.lua
-- The ticket pool (unit-registry spec §3): one record per commit of ours, preallocated (TICKETS = 16). A ticket opens
-- for every commit: every PLAYER_SWING (MELEE), every hard cast at its START (committed, pinned at SENT, armed at its
-- success), every other success, mapped (its ability's kind, Families/Expect.lua) or not (UNMAPPED); NONE closes at
-- once. Rows are consumed online (Events/Rows.lua) by the order of spec §3.4: candidates on the row's GUID, by pass
-- (1 narrow, 2 widened, 3 hard), the least expected closure first, so FIFO per queue falls out. Closes are counted
-- once each (spec §3.6). The matching rules live in Events/Kinds.lua and Events/Melee.lua; this file owns records,
-- order and closes. Pure: no client read. Allocates nothing after load.

local _, ns = ...
local I = ns.VirtualStateInternal
local A = I.ab
local X, U = I.Expect, I.Units

local T = {}
I.Tickets = T
T.CAP = 16
T.FREE, T.COMMITTED, T.OPEN, T.PROV = 0, 1, 2, 3
local CAP, COMMITTED, OPEN, PROV = T.CAP, T.COMMITTED, T.OPEN, T.PROV
local NONE, MELEE, UNMAPPED, ANY = X.NONE, X.MELEE, X.UNMAPPED, X.ANY
T.COMMIT_HOLD = 60 -- s: a committed cast with no stop event closes as stopped (a lost STOP must not pin a unit)

-- Per ticket (spec §3.1): state, kind, ability index (0 swing or unmapped), x (hand or spell ID), the pinned GUID and
-- its registry slot, the school mask (ANY -1, 0 none), rows owed, the anchor, the expiry, the window length, a main
-- reference, a provisional avoid's LR and action, the castGUID of a committed cast, rows paid, first swing of combat.
T.state, T.kind, T.ab, T.x, T.guid, T.uid, T.school, T.owed = {}, {}, {}, {}, {}, {}, {}, {}
T.at, T.hi, T.w, T.ref, T.lr, T.avoid, T.cast, T.done, T.first = {}, {}, {}, {}, {}, {}, {}, {}, {}
local state, kind, ab, x, guid, uid, school, owed = T.state, T.kind, T.ab, T.x, T.guid, T.uid, T.school, T.owed
local at, hi, w, ref, lr, avoid, cast, done, first = T.at, T.hi, T.w, T.ref, T.lr, T.avoid, T.cast, T.done, T.first
for i = 1, CAP do
    state[i], kind[i], ab[i], x[i], guid[i], uid[i], school[i], owed[i] = 0, 0, 0, 0, "", 0, ANY, 0
    at[i], hi[i], w[i], ref[i], lr[i], avoid[i], cast[i], done[i], first[i] = 0, 0, 0, 0, 0, "", "", 0, false
end

T.opened = 0
T.closed = {
    none = 0,
    paid = 0,
    signal = 0,
    replaced = 0,
    refreshed = 0,
    stopped = 0,
    expired = 0,
    lost = 0,
    dead = 0,
    gone = 0,
    ended = 0,
    overflow = 0,
    unpinned = 0,
    provisional = 0,
}
T.paid, T.lost = {}, {} -- by kind: tickets paid out, rows lost
for k = 0, 7 do
    T.paid[k], T.lost[k] = 0, 0
end
T.ours, T.foreign, T.absorbed, T.divergent, T.bandRejected, T.aoeOther = 0, 0, 0, 0, 0, 0
T.onExpire, T.onPay = nil, nil

--- Closes ticket i at t for `why` (a T.closed key) and releases its unit. Allocates nothing.
function T.Close(i, t, why)
    if state[i] == 0 then
        return
    end
    state[i], lr[i], avoid[i] = 0, 0, ""
    T.closed[why] = T.closed[why] + 1
    U.Release(uid[i], t)
end
local close = T.Close

--- A free ticket, else the oldest gives way (spec §3.6: `overflow`, unemitted). Allocates nothing.
function T.Slot(t)
    local oldest = 1
    for i = 1, CAP do
        if state[i] == 0 then
            return i
        elseif at[i] < at[oldest] then
            oldest = i
        end
    end
    close(oldest, t, "overflow")
    return oldest
end

local function fill(i, k, a, xx, g, t)
    state[i], kind[i], ab[i], x[i], guid[i], uid[i] = OPEN, k, a, xx, g, U.Find(g)
    school[i], owed[i], at[i], hi[i], w[i] = ANY, 1, t, t, 0
    ref[i], lr[i], avoid[i], cast[i], done[i], first[i] = 0, 0, "", "", 0, false
    U.Hold(uid[i])
    T.opened = T.opened + 1
end

-- Anchors spell ticket i at its success t and sets its window by its kind (spec §3.3).
local function arm(i, t)
    local k = kind[i]
    state[i], at[i] = OPEN, t
    if k == X.FRAME or k == X.STRIKE then
        local cw = I.Melee.CAST_WINDOW
        w[i] = I.Log.LandWindow(1)
        hi[i] = t + (w[i] > cw and w[i] or cw)
    elseif k == UNMAPPED then
        owed[i], hi[i] = 0, t + I.Log.UNMAPPED_WINDOW
    end
end

--- A swing of `hand` at t pinned to `g` with window `win`; an off hand's main reference `mref`. Allocates nothing.
function T.OpenSwing(t, hand, g, win, mref, isFirst)
    local i = T.Slot(t)
    fill(i, MELEE, 0, hand, g, t)
    school[i], w[i], hi[i], ref[i], first[i] = 1, win, t + win, mref or 0, isFirst == true
    return i
end

--- A success at t of ability `a` (0: unmapped) pinned to `g`: its ticket, armed; 0 for NONE (counted). Allocates
--- nothing.
function T.OpenCast(t, a, spellID, g)
    local k = a > 0 and A.expKind[a] or UNMAPPED
    if k == NONE then
        T.opened = T.opened + 1
        T.closed.none = T.closed.none + 1
        return 0
    end
    local i = T.Slot(t)
    fill(i, k, a, spellID, k == UNMAPPED and "" or g, t)
    if a > 0 then
        school[i] = A.school[a]
    end
    arm(i, t)
    return i
end

--- A hard cast of `a` started at t, pinned to `g` (its SENT pin): committed until its success (T.Arm) or its stop
--- (T.Stop). 0 for NONE. Allocates nothing.
function T.Commit(t, a, spellID, g, castGUID)
    if A.expKind[a] == NONE or castGUID == nil then
        return 0
    end
    local i = T.Slot(t)
    fill(i, A.expKind[a], a, spellID, g, t)
    school[i], cast[i], state[i], hi[i] = A.school[a], castGUID, COMMITTED, t + T.COMMIT_HOLD
    return i
end

--- Arms the committed ticket of `castGUID` at its success t; its index, or 0 when none claims it.
function T.Arm(castGUID, t)
    if castGUID == nil then
        return 0
    end
    for i = 1, CAP do
        if state[i] == COMMITTED and cast[i] == castGUID then
            arm(i, t)
            return i
        end
    end
    return 0
end

--- Closes the committed ticket of `castGUID` uncounted toward lost (its FAILED or INTERRUPTED).
function T.Stop(castGUID, t)
    for i = 1, CAP do
        if state[i] == COMMITTED and castGUID ~= nil and cast[i] == castGUID then
            close(i, t, "stopped")
        end
    end
end

--- (spec §3.4 steps 2-4, owner ruling 2026-10-22) The candidate for a row at t on `g` at pass `p`: among the open
--- tickets on `g` that accept the row and whose band at p holds t, those whose learned amount band accepts it first
--- (K.Accepts' second answer), then those with no band or an unlearned one; within each group the least expected
--- closure. Also how many matched. Allocates nothing.
function T.Pick(t, g, p, act, flag, amount, sch, isAvoid)
    local K = I.Kinds
    local best, bestE, bestBanded, n = 0, math.huge, false, 0
    for i = 1, CAP do
        if state[i] >= OPEN and guid[i] == g then
            local ok, banded = K.Accepts(i, act, flag, amount, sch, isAvoid)
            if ok then
                local lo, h, e = K.Band(i, p, t, isAvoid, act, sch)
                if lo and t >= lo - 1e-9 and t <= h + 1e-9 then
                    n, banded = n + 1, banded == true
                    if (banded and not bestBanded) or (banded == bestBanded and e < bestE) then
                        best, bestE, bestBanded = i, e, banded
                    end
                end
            end
        end
    end
    return best, n
end

--- Ticket i paid by a row at t (`clean`: the only candidate at its pass): one row fewer owed; closed when none is.
function T.Pay(i, t, isAvoid, amount, flag, clean, pass)
    if T.onPay then
        T.onPay(i, t, pass)
    end
    done[i], owed[i] = done[i] + 1, owed[i] - 1
    if owed[i] <= 0 then
        T.paid[kind[i]] = T.paid[kind[i]] + 1
        close(i, t, "paid")
    end
end

--- A swing ticket holds an avoid provisionally (spec §3.7): it is emitted at its close unless a wound overtakes it.
function T.Provisional(i, lri, act)
    state[i], lr[i], avoid[i] = PROV, lri, act
end

--- Whether an UNMAPPED ticket's window holds t.
function T.Unmapped(t)
    for i = 1, CAP do
        if state[i] >= OPEN and kind[i] == UNMAPPED and t <= hi[i] then
            return true
        end
    end
    return false
end

--- (registry hook, spec §2.3) Whether an open ticket on slot u still owes a row of `act` and school `sch`.
function T.Claims(u, act, sch)
    for i = 1, CAP do
        if state[i] >= OPEN and uid[i] == u and owed[i] > 0 and kind[i] ~= UNMAPPED then
            if act ~= "WOUND" or school[i] == ANY or school[i] == sch then
                return true
            end
        end
    end
    return false
end
U.Claims = T.Claims

-- Why ticket i closes at its window's end (spec §3.6).
local function expiry(i)
    local st, k = state[i], kind[i]
    if st == COMMITTED then
        return "stopped"
    elseif st == PROV then
        return "provisional"
    elseif k == UNMAPPED or owed[i] <= 0 then
        return "expired"
    elseif guid[i] == "" then
        return "unpinned"
    elseif school[i] == ANY or school[i] == 0 then
        return "expired"
    elseif U.IsDead(uid[i]) then
        if U.Ours(uid[i]) then
            T.ours = T.ours + 1
        end
        return "dead"
    end
    T.lost[k] = T.lost[k] + owed[i]
    return "lost"
end

--- Closes every ticket whose window ended by `now`, after Rows' T.onExpire (a swing's row). Every OnUpdate.
function T.Expire(now)
    for i = 1, CAP do
        if state[i] ~= 0 and now > hi[i] then
            if state[i] ~= COMMITTED and T.onExpire then
                T.onExpire(i, now)
            end
            close(i, now, expiry(i))
        end
    end
end

--- Combat end (spec §3.6): every ticket closes, emitting nothing, counted `ended`.
function T.EndCombat(t)
    for i = 1, CAP do
        close(i, t, "ended")
    end
end

-- A unit gone (released and past GRACE, so normally no ticket pins it): any ticket still on it closes as at expiry.
U.OnGone(function(u, g, why, t)
    if why ~= U.GONE then
        return
    end
    for i = 1, CAP do
        if state[i] ~= 0 and uid[i] == u then
            if state[i] ~= COMMITTED and T.onExpire then
                T.onExpire(i, t)
            end
            close(i, t, "gone")
        end
    end
end)

--- Snapshot's line (allocates; debugging only).
I.OnSnapshot(function(out)
    local c, open = T.closed, 0
    for i = 1, CAP do
        open = open + (state[i] ~= 0 and 1 or 0)
    end
    local lost = 0
    for k = 0, 7 do
        lost = lost + T.lost[k]
    end
    out[#out + 1] = string.format(
        "tickets open=%d none=%d paid=%d lost=%d expired=%d refreshed=%d foreign=%d unpinned=%d dead=%d gone=%d bandRejected=%d divergent=%d overflow=%d absorbed=%d ours=%d aoeOther=%d",
        open,
        c.none,
        c.paid,
        lost,
        c.expired,
        c.refreshed,
        T.foreign,
        c.unpinned,
        c.dead,
        c.gone,
        T.bandRejected,
        T.divergent,
        c.overflow,
        T.absorbed,
        T.ours,
        T.aoeOther
    )
end)
```

- [ ] **Step 4: Create** `src/Hekili/Game/Events/Kinds.lua`:

```lua
-- Game/Events/Kinds.lua
-- Each engine kind's matching rule, once (unit-registry spec §3.3, §3.4): which rows an open ticket accepts (an avoid
-- pays any kind that owes a row; a WOUND only a kind of its school, or ANY; a school of 0 only an avoid) and its band
-- per pass (1 narrow, 2 widened, 3 hard) with its expected closure E. MELEE's rule is Events/Melee.lua's; NONE and
-- UNMAPPED accept no row. Packs write no matching code: they declare data (Families/Expect.lua). Pure.

local _, ns = ...
local I = ns.VirtualStateInternal
local L = I.Log
local T, M, X = I.Tickets, I.Melee, I.Expect

local K = {}
I.Kinds = K
-- Fix 31 G4, now the UNMAPPED kind's window: an avoid or crit within it of a success the kit does not map, past another
-- ticket's own frame, is nobody's. UNMEASURED: a chosen bound (the Affliction log's thrown explosive, 1.43 s).
L.UNMAPPED_WINDOW = 2
local SAME_FRAME, CAST_WINDOW = M.SAME_FRAME, M.CAST_WINDOW
local REFUSED = { DODGE = true, PARRY = true, MISS = true }
local FRAME, STRIKE, MELEE, UNMAPPED, NONE, ANY = X.FRAME, X.STRIKE, X.MELEE, X.UNMAPPED, X.NONE, X.ANY

--- Whether open ticket i accepts a row of `act` (an avoid when `isAvoid`) and school `sch` (spec §3.4 step 2), and
--- whether a learned amount band accepted it (Tasks 7 and 8 add the bands; T.Pick ranks banded candidates first).
function K.Accepts(i, act, flag, amount, sch, isAvoid)
    local k = T.kind[i]
    if T.owed[i] <= 0 or k == MELEE or k == UNMAPPED or k == NONE then
        return false
    elseif isAvoid then
        return true
    end
    local s = T.school[i]
    return s == ANY or (s > 0 and s == sch)
end

--- Ticket i's band at pass p for a row at t: lo, hi (absolute) and its expected closure E; nil when it has none.
function K.Band(i, p, t, isAvoid, act, sch)
    local k, a0 = T.kind[i], T.at[i]
    if k == FRAME or k == STRIKE then
        if p == 1 then
            return a0, a0 + SAME_FRAME, a0
        elseif isAvoid then
            -- GAP AX: the landing window for a refused avoid while others rarely avoid, else the cast's own window
            if REFUSED[act] and L.bg[7] < L.FOREIGN_AVOIDS then
                return a0, a0 + T.w[i], a0
            end
            return a0, a0 + CAST_WINDOW, a0
        elseif T.school[i] == ANY and sch ~= 1 then
            return nil -- a default type takes a non-white wound only in its frame (Rows.lua:458, :497 before)
        end
        return a0, a0 + CAST_WINDOW, a0
    end
end
```

- [ ] **Step 5: Melee's pending skips UNMAPPED.** In `src/Hekili/Game/Events/Melee.lua` `M.pending`, replace the
  condition with:

```lua
        local k = T.kind[i]
        if T.state[i] ~= 0 and k ~= X.UNMAPPED and (k == X.MELEE or t - T.at[i] <= CAST_WINDOW) then
```

  and its loop body's `return true` stays.

- [ ] **Step 6: Rewrite** `src/Hekili/Game/Events/Rows.lua`:

```lua
-- Game/Events/Rows.lua
-- Our own commits and their outcomes as combat-log rows (event-facade spec §2.4, §3; unit-registry spec §3).
-- Before (to 2026-10-22): an 8-slot pending ring, its own target-only UNIT_COMBAT handler, its own GUID reads, and
-- every scoring rule inline. Now: it opens a ticket (Events/Tickets.lua) for each commit (PLAYER_SWING, a hard cast's
-- START, each success), feeds each row the unit registry resolved and deduplicated (State/Sources/Units.lua's OnRow)
-- through the consumption order (spec §3.4: spell kinds by pass, Events/Kinds.lua; the swing LR, Events/Melee.lua),
-- and turns each payment into SWING_DAMAGE / SWING_MISSED / SPELL_DAMAGE / SPELL_MISSED / SPELL_PERIODIC_DAMAGE at
-- the commit's time (back-dated; ticks at their own) and the staged observations: `Swing` c = 1 (landed) and c = 3
-- (that hand's crit), `Crit` and `Avoided` for a spell when no second candidate matched. It keeps the credit records,
-- I.CreditVerdict, the provisional avoid, WOUND 0's foreign strike frame and the on-next-swing replacement.
-- Measured: docs/research/2026-10-16-swing-outcome-pairing.md (P), docs/research/2026-10-16-group-pairing-captures.md
-- (G, G5); the 2026-10-22 captures (unit-registry spec §1).
-- Credits: secret-value handling after Catnip's (Durts) research; the signals are Taco Dog Forever's research
-- (docs/research/2026-10-14-virtual-combat-log-events.md, C1, C3, C9, D7).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local VS = ns.VirtualState
local Obs = VS.Obs
local Plain = S.Plain
local L = I.Log
local T, M, X, U = I.Tickets, I.Melee, I.Expect, I.Units
local A = I.ab
local SAME_FRAME, STRIKE_WINDOW = M.SAME_FRAME, M.STRIKE_WINDOW
local AVOIDS, MELEE, TICKS, CHANNEL = M.AVOIDS, X.MELEE, X.TICKS, X.CHANNEL

-- Credit records (ids 1-8, a ring; `Swing` c = 1's b): the outcome's time, amount and flag, the swing's time, hand,
-- destination, window and main reference, the class index, LR, and whether a verdict is still open.
local RECORDS = 8
local recT, recAmount, recFlag, recAt, recHand, recDst, recW, recRef, recK, recLR, recOpen =
    {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}
for k = 1, RECORDS do
    recT[k], recAmount[k], recFlag[k], recAt[k], recHand[k], recDst[k], recW[k], recRef[k] = 0, 0, "", 0, 0, "", 0, 0
    recK[k], recLR[k], recOpen[k] = 1, 0, false
end
local recNext = 0

local strikeWait, lastMain, lastW0, fresh = 0, 0, -1, false

local MISSES = {
    DODGE = true,
    PARRY = true,
    MISS = true,
    BLOCK = true,
    DEFLECT = true,
    EVADE = true,
    IMMUNE = true,
    RESIST = true,
    ABSORB = true,
}
local REFUSED = { DODGE = true, PARRY = true, MISS = true } -- the avoids that refuse the whole ability (Obs.Avoided)

-- One row from an own action of kind `k` and its outcome at `t` (school mask `sch` for a spell), through CombatLog's
-- builders (Task 5b). None without a destination: Hekili's handler would count a "" GUID as an enemy
-- (`ns.updateTarget`, Events.lua:1693-1701).
local function emit(k, xx, dst, action, flag, amount, t, sch)
    if dst == "" then
        return
    end
    local me, mf, hf = L.player, L.PLAYER_FLAGS, L.HOSTILE_FLAGS
    if k == MELEE then
        if action == "WOUND" then
            L.Swing(t, "swing", me, mf, dst, hf, amount, flag, xx == 2)
        else
            L.Miss(t, "missed", me, mf, dst, hf, nil, 1, action, xx == 2)
        end
    elseif action == "WOUND" then
        local sub = (k == TICKS or k == CHANNEL) and "SPELL_PERIODIC_DAMAGE" or "SPELL_DAMAGE"
        L.SpellHit(sub, t, "damage", me, mf, dst, hf, xx, sch, amount, flag) -- the ticket's school, spec §3.5
    else
        L.Miss(t, "missed", me, mf, dst, hf, xx, sch, action)
    end
end

-- Our cast's own avoid for the belief (Families/Now.lua): an action that refuses the whole ability, staged at the
-- ticket's anchor (the refund belongs there).
local function avoided(i, t, act)
    local a = T.ab[i]
    if REFUSED[act] and a > 0 then
        S.Stage(Obs.Avoided, t, a, T.at[i], I.HitKind[act])
        S.Urgent("VS_CAST_AVOIDED")
    end
end

-- A swing closing unpaid: SWING_MISSED for a provisional avoid, else SWING_DAMAGE 0 (the swing timer reads it).
T.onExpire = function(i)
    if T.kind[i] == MELEE then
        emit(MELEE, T.x[i], T.guid[i], T.avoid[i] ~= "" and T.avoid[i] or "WOUND", "", 0, T.at[i], 1)
    end
end

-- swingType 2, the ranged hand (C7), is no melee swing: its clock is Sources/Swing.lua's, and the shot's outcome pays
-- its ability's ticket.
S.On("PLAYER_SWING", nil, function(api, t, duration, swingType)
    if type(swingType) ~= "number" or swingType > 2 then
        return
    end
    M.advance(t)
    if swingType == 2 then
        return
    end
    if swingType == 0 then
        lastMain = t
    end
    if swingType == 0 and strikeWait > 0 and t - strikeWait <= STRIKE_WINDOW then
        strikeWait = 0 -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
        return
    end
    local hand = swingType + 1
    local win = L.PAIR_WINDOW_MS[hand] / 1000
    if type(duration) == "number" and duration > 0 and duration < win then
        win = duration -- the hand's next swing comes first
    end
    T.OpenSwing(t, hand, U.Pin(api, t) or "", win, hand == 2 and lastMain or 0, fresh)
    fresh = false
end)

S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    if unit ~= "player" or type(spellID) ~= "number" then
        return
    end
    local a = A.bySpell[spellID] or 0
    if a > 0 and A.expKind[a] ~= X.NONE then
        M.advance(t)
    end
    if a > 0 and A.expKind[a] == X.STRIKE then -- the strike replaces its swing, in the same frame before or after
        local found = false
        for i = 1, T.CAP do
            if T.state[i] ~= 0 and T.kind[i] == MELEE and T.x[i] == 1 and t - T.at[i] <= STRIKE_WINDOW then
                T.Close(i, t, "replaced")
                found = true
            end
        end
        if not found then
            strikeWait = t
        end
    end
    if T.Arm(castGUID, t) == 0 then
        T.OpenCast(t, a, spellID, U.Sent(castGUID) or U.Pin(api, t) or "")
    end
end)

-- A hard cast commits at its START, pinned where it was SENT (spec §3.2; capture c: the cast keeps its SENT target).
S.On("UNIT_SPELLCAST_START", "player", function(api, t, unit, castGUID, spellID)
    local a = unit == "player" and type(spellID) == "number" and A.bySpell[spellID]
    if a then
        T.Commit(t, a, spellID, U.Sent(castGUID) or U.Pin(api, t) or "", castGUID)
    end
end)

local function stopped(api, t, unit, castGUID)
    if unit == "player" then
        T.Stop(castGUID, t)
    end
end
S.On("UNIT_SPELLCAST_FAILED", "player", stopped)
S.On("UNIT_SPELLCAST_INTERRUPTED", "player", stopped)

-- A spell row paid to ticket p at pass `pass` with n candidates at that pass: staged when it was the only one (a
-- divergent pair stages nothing, spec §4.2), then emitted. A divergent avoid emits no SPELL_MISSED (Hekili's
-- `missable` would drop the other cast's debuff on it).
local function paySpell(p, n, pass, t, act, flag, amount, school, avoid, crit)
    local divergent = (avoid or crit) and n > 1
    if divergent then
        T.divergent = T.divergent + 1
    elseif avoid then
        avoided(p, t, act)
    elseif crit and T.ab[p] > 0 then
        S.Stage(Obs.Crit, t, T.ab[p], T.at[p], 0) -- our cast's own crit (the target's row carries the flag plain): GAP T
    end
    local kk, xx, dst, at0, sch = T.kind[p], T.x[p], T.guid[p], T.at[p], T.school[p]
    T.Pay(p, t, avoid, amount, flag, n == 1, pass)
    L.credited[3] = L.credited[3] + 1
    if not (divergent and avoid) then
        emit(kk, xx, dst, act, flag, amount, (kk == TICKS or kk == CHANNEL) and t or at0, sch > 0 and sch or school)
    end
end

-- A row of ours no ticket took (spec §3.4 step 5): an avoid or crit inside an UNMAPPED window is nobody's; else
-- foreign, teaching the background only when it is about the target (as the target-only reading did).
local function foreign(uid, t, act, flag, amount, white, avoid, unknown)
    if (avoid or flag == "CRITICAL") and T.Unmapped(t) then
        T.absorbed = T.absorbed + 1
        return
    end
    T.foreign = T.foreign + 1
    if U.IsTarget(uid, t) then
        M.background(act, amount, flag, white, avoid, unknown)
    end
end

-- The row at `t` on unit `g`, in the consumption order (spec §3.4): (1) a spell ticket's narrow band, then for an
-- avoid its widened and hard bands; a white avoid or crit a swing of ours explains is the swing's (MELEE wins a tie,
-- today's Rows.lua:458-478 order); (2) the swing LR among the swing tickets on `g`; (3) a wound's widened then hard
-- band; else nobody's. A WOUND 0 is the white
-- swing an on-next-swing strike replaced and pays nothing; a wound right after one that no ticket took is another
-- player's strike frame.
U.OnRow(function(t, g, uid, act, flag, amount, school)
    if act ~= "WOUND" and not MISSES[act] then
        return
    end
    M.advance(t)
    if type(amount) ~= "number" or type(flag) ~= "string" or type(school) ~= "number" then
        if U.IsTarget(uid, t) then -- a secret slot (never seen in game): only counted
            M.background(act, 0, "", false, act ~= "WOUND", false)
        end
        return
    end
    local white, avoid = school == 1, act ~= "WOUND"
    if act == "WOUND" and amount <= 0 then
        lastW0 = t
        return
    end
    local crit = not avoid and flag == "CRITICAL"
    local p, n = T.Pick(t, g, 1, act, flag, amount, school, avoid)
    local pass = 1
    if p == 0 and avoid then
        p, n = T.Pick(t, g, 2, act, flag, amount, school, true)
        pass = 2
        if p == 0 then
            p, n = T.Pick(t, g, 3, act, flag, amount, school, true)
            pass = 3
        end
    end
    if p > 0 and white and (avoid or crit) then
        local sw, _, ref, lag = M.score(t, g, amount, flag, avoid, crit) -- a crit by its timing alone, as an avoid
        local h = ref == 3 and 2 or ref
        if sw and (lag <= SAME_FRAME or math.abs(lag - L.med[h]) <= 2 * L.spr[h]) then
            if avoid then
                p = 0 -- the swing's (MELEE wins the tie): the LR below takes it, the spell keeps its effects
            else
                crit = false
            end
        end
    end
    local credited, lr, ref, lag, second, k = nil, 0, 0, 0, 0, 1
    local unknown = false
    if p == 0 and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
        if not avoid then
            local _, maxMain = VS.Stat("UnitDamage")
            local form = Plain(I.api, I.api.GetShapeshiftForm()) -- secret: Plain; plain in combat (Facade's stance row)
            unknown = maxMain <= 0 or form ~= I.damageForm
        end
        credited, lr, ref, lag, second, k = M.score(t, g, amount, flag, avoid, unknown)
        if credited and lr < (avoid and L.THETA or L.theta[k]) then
            credited = nil
        elseif credited and not avoid and I.Missed and I.Missed(T.x[credited], T.at[credited]) then
            -- the veto: that swing gave no rage (its usability answers since it showed), so this wound is another's
            L.oracle.vetoed, L.vetoX, L.vetoAt = L.oracle.vetoed + 1, T.x[credited], T.at[credited]
            credited = nil
        end
    end
    if p == 0 and not credited and not avoid then
        p, n = T.Pick(t, g, 2, act, flag, amount, school, false)
        pass = 2
        if p == 0 then
            p, n = T.Pick(t, g, 3, act, flag, amount, school, false)
            pass = 3
        end
    end
    if p > 0 then
        if (avoid or crit) and pass > 1 and T.Unmapped(t) then
            T.absorbed = T.absorbed + 1 -- past p's own frame, inside an unmapped success's window: nobody's
            return
        end
        paySpell(p, n, pass, t, act, flag, amount, school, avoid, crit)
        return
    elseif not credited then
        foreign(uid, t, act, flag, amount, white, avoid, unknown)
        return
    end
    local xx, at0 = T.x[credited], T.at[credited]
    if avoid then
        T.Provisional(credited, lr, act) -- emitted when the window closes
        L.avoids, L.avoidX, L.avoidT = L.avoids + 1, xx, at0
        return
    end
    if T.avoid[credited] ~= "" then
        L.avoidsBack = L.avoidsBack + 1 -- the avoid it held was someone else's after all
    end
    if not unknown and M.classOf(xx, amount, flag) == 1 and second < L.THETA and not T.first[credited] then
        local d = ref == 3 and t - T.ref[credited] or lag
        if math.abs(d - L.med[ref]) < 3 * L.spr[ref] then
            M.learn(ref, d)
        end
    end
    recNext = recNext % RECORDS + 1
    local id = recNext
    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = t, amount, flag, at0, xx
    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] =
        T.guid[credited], T.w[credited], T.ref[credited], k, lr, true
    local dst = T.guid[credited]
    T.Pay(credited, t, false, amount, flag, second < L.THETA, 2)
    L.credited[xx] = L.credited[xx] + 1
    emit(MELEE, xx, dst, act, flag, amount, at0, 1)
    S.Stage(Obs.Swing, at0, xx, id, 1) -- landed, at the swing's time: the resources family pays its rage (record id)
    if flag == "CRITICAL" then
        S.Stage(Obs.Swing, t, xx, id, 3) -- the same record: a retraction takes the crit back too
    end
    S.Urgent("VS_SWING_LANDED")
end)

--- (harness design §2.2) The verdict on credit record `id` from a usability answer at t (`ok`: usable, false: short,
--- nil: not usable for another reason; `firm`: the credit's floor reached the cost), asked by Families/Resources.lua:
--- nil before ORACLE_MIN after the swing or on a nil `ok` (no verdict yet), false once one landing lag (the hand's
--- learned median) has passed since the wound or when the record is closed, true when judged. Usable confirms it (theta of its class / 1.1). Short and firm retracts it
--- (theta x 1.5): its swing is pending again inside its window on a unit still held, else closed as SWING_MISSED
--- (the SWING_DAMAGE row already went out: two rows for that swing, decision D9), and its wound counts as
--- background. Short and soft labels it at half weight (x 1.22). Allocates nothing.
function I.CreditVerdict(id, ok, t, firm)
    if not recOpen[id] then
        return false
    end
    if t - recAt[id] < L.ORACLE_MIN - 1e-6 then -- (a float sum of the two may fall a ulp short)
        return nil
    end
    if t - recT[id] > L.med[recHand[id] == 2 and 2 or 1] then
        recOpen[id] = false
        return false -- past its window: no verdict
    elseif ok == nil then
        return nil -- a NOT answer (no rung): no verdict yet, the record stays open
    end
    recOpen[id] = false
    local o, th, k = L.oracle, L.theta, recK[id]
    o.judged = o.judged + 1
    if ok then
        o.confirmed = o.confirmed + 1
        th[k] = th[k] / 1.1 > L.THETA_MIN and th[k] / 1.1 or L.THETA_MIN
    elseif firm then
        o.retracted = o.retracted + 1
        th[k] = th[k] * 1.5 < L.THETA_MAX and th[k] * 1.5 or L.THETA_MAX
        local hand, at = recHand[id], recAt[id]
        if t - at <= recW[id] and U.Find(recDst[id]) > 0 then
            T.OpenSwing(at, hand, recDst[id], recW[id], recRef[id], false)
        else
            emit(MELEE, hand, recDst[id], "MISS", "", 0, at, 1)
        end
        L.background = L.background + 1
    else
        o.soft = o.soft + 1
        th[k] = th[k] * 1.22 < L.THETA_MAX and th[k] * 1.22 or L.THETA_MAX
    end
    return true
end

-- Closes the windows at `now` (each swing's row at its own time). Every OnUpdate. Allocates nothing.
L.OnTick(function(now)
    M.advance(now)
    T.Expire(now)
end)

-- Combat end: nothing open survives into the next pull; the background and the lags are kept (decision D6).
S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    M.advance(t)
    T.EndCombat(t)
    strikeWait = 0
end)

--- Snapshot's lines (allocates; debugging only): the credits and the background, the learned lags (ms) and the
--- background rates (per second); the oracle's counts.
I.OnSnapshot(function(out)
    local c, med, spr, o = L.credited, L.med, L.spr, L.oracle
    out[#out + 1] = string.format(
        "rows credited main=%d off=%d cast=%d background=%d avoidsBack=%d lag main=%.0f/%.0f off=%.0f/%.0f ref=%.0f/%.0f lambda exact=%.2f/%.2f avoid=%.2f",
        c[1],
        c[2],
        c[3],
        L.background,
        L.avoidsBack,
        med[1] * 1000,
        spr[1] * 1000,
        med[2] * 1000,
        spr[2] * 1000,
        med[3] * 1000,
        spr[3] * 1000,
        M.lambda(1),
        M.lambda(4),
        M.lambda(7)
    )
    out[#out + 1] = string.format(
        "rows oracle judged=%d confirmed=%d retracted=%d soft=%d vetoed=%d",
        o.judged,
        o.confirmed,
        o.retracted,
        o.soft,
        o.vetoed
    )
end)
```

Add to `src/Hekili/Hekili.toc` after `Game\Events\Melee.lua`:

```
Game\Events\Kinds.lua
```

- [ ] **Step 7: Check Rows names no window and no ring**

Run: `grep -nE "CAST_WINDOW|UNMAPPED_WINDOW|LandWindow|unmappedT|local function (cast|another|hold|free)\b" src/Hekili/Game/Events/Rows.lua`
Expected: no output (the windows live in Kinds.lua and Melee.lua only).

- [ ] **Step 8: Run the new tests**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/Events/kinds_spec.lua`
Expected: PASS (9 and 3 successes).

- [ ] **Step 9: Run every existing spec; update only the named divergence case.** The one existing case whose
  assertion follows a rule this task changes is `tests/Game/State/now_spec.lua:1012` ("two casts pending"): its
  assertions (no Obs.Avoided, no SPELL_MISSED) still hold under the divergent rule above, so it stays as written.

Run: `make test-fast && .lua/bin/busted --tags=slow tests/Game/harness/group_spec.lua tests/Game/harness/solo_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/alloc_spec.lua tests/Game/harness/flicker_spec.lua`
Expected: PASS, 0 failures; `group_spec.lua`'s printed numbers equal Task 5's. A moved number or a failing case stops
the task for review with the stream that moved.

- [ ] **Step 10: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Kinds.lua src/Hekili/Game/Events/Melee.lua \
  src/Hekili/Game/Events/Rows.lua src/Hekili/Hekili.toc tests/Game/Events/tickets_spec.lua \
  tests/Game/Events/kinds_spec.lua
git commit -m "feat(tickets): one ticket per commit, paid by pass in expected-closure order on its own GUID

FRAME, STRIKE, UNMAPPED and NONE as kinds (Kinds.lua); Rows keeps only rows and staging.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 6b: The swing ticket owns "a swing is pending"; the strike ticket owns the swallowed swing

**Files:**
- Modify: `src/Hekili/Game/Events/Tickets.lua` (`T.lastSwing`, `T.PEND_CAP`, `T.PendingWindow`, `T.SwingPending`,
  `T.OpenStrikeWait`, `T.Swallows`; `T.OpenSwing` records the hand's latest swing)
- Modify: `src/Hekili/Game/Events/Rows.lua` (`strikeWait` removed: the `PLAYER_SWING` and success handlers use the
  strike ticket; `I.CreditVerdict`'s re-open passes `retry`)
- Modify: `src/Hekili/Game/State/Families/Resources.lua:193-195` (`pendT`, `LAND_CAP` removed), `:1164-1177` (the
  float-equality link removed), `:1279-1296` (`VS.SwingPending` reads the ticket), `:1326`
- Test: `tests/Game/Events/tickets_spec.lua`, `tests/Game/State/resources_spec.lua` (cases added)

**Interfaces:**
- Consumes: the ticket pool (Task 6), `L.LandWindow`, `M.STRIKE_WINDOW`.
- Produces: `T.SwingPending(hand, t) -> at|0` (the hand's latest swing, while its ticket is open, unpaid and within
  `T.PendingWindow(hand)` of its swing); `T.PendingWindow(hand)` = `min(L.LandWindow(hand), T.PEND_CAP)`, `T.PEND_CAP`
  1.0 (the one expiry; Resources' LAND_CAP drift guard moves here unchanged); `T.OpenSwing(..., retry)` (a retraction's
  re-open does not become the hand's latest swing, as `pendT` stayed 0 after a credit before); `T.OpenStrikeWait(i)`
  and `T.Swallows(t) -> bool` (a strike whose success came before its swing swallows the next main-hand swing within
  `STRIKE_WINDOW`).
- Boundary: the ticket layer is the single owner of a pending swing; Resources keeps only the belief's own
  conditions (an answer above the floor heard since, a spend from the slot, a plain read) and asks the ticket for the
  swing. `Families/Swing.lua`'s `anchorT` (:45-56) stays: it is the swing clock (when the next swing comes, read by
  Hekili's forecast), not a pending swing. `A.queued` (`Families/Casts.lua:201`, `:231`) stays: it is the client's
  `IsCurrentSpell` answer before the strike's success, a fact Rows never held.

Behaviour: the pending window was `min(L.LandWindow(h), 1.0)` in Resources and is the same number here; credit closes
the ticket as it cleared `pendT`; a retraction's re-open never made `pendT` pending again and does not here. One
difference is named: a white swing an on-next-swing strike replaced (its ticket closed `replaced`) is no longer
pending, because it pays no white rage; `pendT` held it pending until its window. Gate: `solo_spec.lua`,
`group_spec.lua` and `onus_spec.lua` rage metrics and `over` must not move down; a move down stops the task for the
owner.

- [ ] **Step 1: Write the failing tests.** Append inside `describe("the ticket pool", ...)` of
  `tests/Game/Events/tickets_spec.lua`:

```lua
    describe("the pending swing (single owner)", function()
        it("is the hand's latest open swing within min(landing window, 1 s), until its credit", function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            assert.are.equal(10, T.SwingPending(1, 10.3))
            assert.are.equal(0, T.SwingPending(2, 10.3))
            assert.are.equal(0, T.SwingPending(1, 10 + T.PendingWindow(1) + 0.01))
            ctl.now = 10.47
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1) -- credited
            assert.are.equal(0, T.SwingPending(1, 10.5))
        end)

        it("does not make a retraction's re-open the hand's latest swing", function()
            local i = T.OpenSwing(20, 1, "Creature-1", 1.5, 0, false, true)
            assert.are.equal(T.OPEN, T.state[i])
            assert.are.equal(0, T.SwingPending(1, 20.1))
        end)

        it("swallows the main-hand swing after a strike whose success came first", function()
            ctl.now = 30
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_B)
            ctl.now = 30.1
            ctl.Fire("PLAYER_SWING", 2.6, 0) -- the strike's own swing: no swing ticket
            for j = 1, T.CAP do
                assert.is_false(T.state[j] ~= T.FREE and T.kind[j] == X.MELEE, "a swing ticket for the strike's swing")
            end
            ctl.now = 32.8
            ctl.Fire("PLAYER_SWING", 2.6, 0) -- the next one is a swing again
            assert.are.equal(32.8, T.SwingPending(1, 32.9))
        end)
    end)
```

  Append inside the top `describe` of `tests/Game/State/resources_spec.lua` (its booted fake spec with a swing-paid
  rage slot; `ctl`, `VS`, `I` as that file names them):

```lua
    it("asks the swing ticket whether a swing is pending (no private copy)", function()
        local src = assert(io.open("src/Hekili/Game/State/Families/Resources.lua")):read("*a")
        assert.is_nil(src:find("pendT", 1, true))
        assert.is_nil(src:find("LAND_CAP", 1, true))
        ctl.now = 40
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        I.Sources.Flush()
        I.Fold(40.05)
        I.clock = 40.05
        assert.are.equal(40, VS.SwingPending(1))
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/State/resources_spec.lua`
Expected: FAIL, `attempt to call field 'SwingPending' (a nil value)` and the `pendT` find.

- [ ] **Step 3: Tickets.** In `src/Hekili/Game/Events/Tickets.lua`, after `T.onExpire, T.onPay = nil, nil` add:

```lua
-- The pending swing (owner ruling 2026-10-22: the ticket is its single owner): each hand's latest swing ticket and its
-- time; a swing is pending while that ticket is open and within the hand's pending window. PEND_CAP: Resources'
-- drift guard, moved here unchanged (Melee's learn can widen the landing window to about 2.7 s main, 3.2 s off).
T.PEND_CAP = 1.0
T.lastSwing, T.lastSwingT = { 0, 0 }, { 0, 0 }
-- A strike whose success came before its swing: the open STRIKE ticket that swallows the next main-hand swing.
local strikeWait = 0
```

  Change `T.OpenSwing`'s signature to `function T.OpenSwing(t, hand, g, win, mref, isFirst, retry)` and add before its
  `return i`:

```lua
    if not retry then -- a retraction's re-open is not the hand's latest swing (pendT stayed 0 after a credit)
        T.lastSwing[hand], T.lastSwingT[hand] = i, t
    end
```

  and after `T.OpenSwing` add:

```lua
--- Hand's pending window: its landing window, capped at PEND_CAP. Allocates nothing.
function T.PendingWindow(hand)
    local w = I.Log.LandWindow(hand)
    return w < T.PEND_CAP and w or T.PEND_CAP
end

--- The time of hand's latest swing while its ticket is open (not credited, retracted away or expired) and t is within
--- its pending window; else 0 (VS.SwingPending's swing). Allocates nothing.
function T.SwingPending(hand, t)
    local i, at0 = T.lastSwing[hand], T.lastSwingT[hand]
    if i == 0 or state[i] < OPEN or kind[i] ~= MELEE or at[i] ~= at0 or t > at0 + T.PendingWindow(hand) then
        return 0
    end
    return at0
end

--- Strike ticket i's success came before its swing: it swallows the next main-hand swing within STRIKE_WINDOW.
function T.OpenStrikeWait(i)
    strikeWait = i
end

--- Whether a main-hand swing at t is a waiting strike's own (consumed when it is). Allocates nothing.
function T.Swallows(t)
    local i = strikeWait
    if i > 0 and state[i] >= OPEN and kind[i] == X.STRIKE and t - at[i] <= I.Melee.STRIKE_WINDOW then
        strikeWait = 0
        return true
    end
    strikeWait = 0
    return false
end
```

  and in `T.EndCombat`, after its loop, add `strikeWait = 0`.

- [ ] **Step 4: Rows.** In `src/Hekili/Game/Events/Rows.lua`: remove `strikeWait` from the `local strikeWait, lastMain,
  lastW0, fresh = ...` line (it becomes `local lastMain, lastW0, fresh = 0, -1, false`); in the `PLAYER_SWING` handler
  replace

```lua
    if swingType == 0 and strikeWait > 0 and t - strikeWait <= STRIKE_WINDOW then
        strikeWait = 0 -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
        return
    end
```

  with

```lua
    if swingType == 0 and T.Swallows(t) then
        return -- the on-next-swing strike whose success came first is this swing: its outcome is the ability's
    end
```

  replace the `UNIT_SPELLCAST_SUCCEEDED` handler with:

```lua
S.On("UNIT_SPELLCAST_SUCCEEDED", "player", function(api, t, unit, castGUID, spellID)
    if unit ~= "player" or type(spellID) ~= "number" then
        return
    end
    local a = A.bySpell[spellID] or 0
    if a > 0 and A.expKind[a] ~= X.NONE then
        M.advance(t)
    end
    local strike, found = a > 0 and A.expKind[a] == X.STRIKE, false
    if strike then -- the strike replaces its swing, in the same frame before or after this success
        for i = 1, T.CAP do
            if T.state[i] ~= 0 and T.kind[i] == MELEE and T.x[i] == 1 and t - T.at[i] <= STRIKE_WINDOW then
                T.Close(i, t, "replaced")
                found = true
            end
        end
    end
    local i = T.Arm(castGUID, t)
    if i == 0 then
        i = T.OpenCast(t, a, spellID, U.Sent(castGUID) or U.Pin(api, t) or "")
    end
    if strike and not found and i > 0 then
        T.OpenStrikeWait(i) -- its swing comes after: the strike ticket swallows it (T.Swallows)
    end
end)
```

  In the combat-end handler drop `strikeWait = 0`; in
  `I.CreditVerdict` the re-open becomes `T.OpenSwing(at, hand, recDst[id], recW[id], recRef[id], false, true)`.

- [ ] **Step 5: Resources.** In `src/Hekili/Game/State/Families/Resources.lua`: delete lines 193 (`local pendT`) and
  195 (`local LAND_CAP`); in the `c == 4` branch delete `pendT[hand] = o.t`; in the `c == 1` branch delete the
  `if abs(o.t - pendT[hand]) < 1e-6 then ... end` block; in the combat-end hook delete `pendT[1], pendT[2] = 0, 0`;
  replace `VS.SwingPending` (lines 1279-1296) with:

```lua
function VS.SwingPending(hand)
    local p = I.Tickets.SwingPending(hand, I.clock) -- the swing ticket owns it (open, uncredited, in its window)
    if p == 0 or heardT > p + I.Log.ORACLE_MIN - 1e-6 then
        return 0 -- shown, credited, or no credit one landing lag on: avoided
    end
    local paid = false
    for r = 1, R.n do
        if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
            if R.readable[r] or R.spends[r] ~= swSp[hand] then
                return 0
            end
            paid = true
        end
    end
    return paid and p or 0 -- no swing-paid slot on that hand: nothing pends
end
```

  and update its doc comment's last sentences to: `Not pending once an answer above the floor since that point was
  heard, once its swing ticket closes (credited, or no credit within its pending window: Events/Tickets.lua's
  T.SwingPending), after a spend from the slot, or for a slot read plain. Allocates nothing.`

- [ ] **Step 6: Run the tests, then the rage gates**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/State/resources_spec.lua && make test-fast`
Expected: PASS, 0 failures.

Run: `.lua/bin/busted --tags=slow tests/Game/harness/solo_spec.lua tests/Game/harness/group_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/flicker_spec.lua`
Expected: PASS; every printed rage metric and `over` count at or better than Task 6's run. A move down stops the task
for the owner with the metric and the first window that moved.

- [ ] **Step 7: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Rows.lua \
  src/Hekili/Game/State/Families/Resources.lua tests/Game/Events/tickets_spec.lua tests/Game/State/resources_spec.lua
git commit -m "refactor(tickets): the swing ticket owns the pending swing; the strike ticket swallows its swing

Resources' pendT, LAND_CAP and the float-equality link are gone.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 7a: One home for the running statistics (`State/Stats.lua`)

**Files:**
- Create: `src/Hekili/Game/State/Stats.lua`
- Modify: `src/Hekili/Hekili.toc:17` (add `Game\State\Stats.lua` after `Game\State\Belief.lua`)
- Modify: `src/Hekili/Game/State/Families/Resources.lua:627-647` (`ema`), `:683-686` (`calibrate`'s inline copy),
  `:1164` (the hit rate's decay)
- Modify: `src/Hekili/Game/Events/Attackers.lua:171` (the learned attack period)
- Modify: `src/Hekili/Game/Events/Melee.lua` (`M.learn`, Rows.lua:272-279 before Task 5)
- Test: `tests/Game/State/stats_spec.lua` (new); the existing resources, onus and pairing specs unchanged

**Interfaces:**
- Consumes: nothing.
- Produces: `I.Stats.Ema(est, dev, sample, alpha, floor) -> est, dev, spread` (the EMA, its mean absolute deviation
  against the new estimate, and the deviation never below `floor`); `I.Stats.Median(med, spr, d, step, lo, hi) -> med,
  spr` (a sign step of `step` toward `d`, clamped to [lo, hi]; the spread an EMA (`Stats.SPR_ALPHA` 0.05) of
  1.2533 x |d - med| clamped to [`Stats.SPR_LO` 0.02, `Stats.SPR_HI` 0.4]); `I.Stats.Clamp(x, lo, hi)`. Pure, no
  allocation.
- Boundary: the belief layer's statistics live in one file; callers keep their constants.

Implementation choices: the two Resources EMA copies differ only in how they write the spread floor (`ema` scales
`REGEN_SPREAD_MIN` by the reference's magnitude, `calibrate` uses it bare because its sample is a ratio to the
reference); the one rule kept is "the floor is `REGEN_SPREAD_MIN` times the reference the sample is measured
against": `abs(scale)` in `ema`, 1 in `calibrate`, which is exactly what each computes today. The hit rate's landed
step (`+ HIT_ALPHA`, capped at 1, `:1178`) is a count step, not an EMA, and stays inline; its decay (`x (1 -
HIT_ALPHA)`) becomes `Stats.Ema` toward 0, equal up to the last bit of rounding (the step's run of the rage specs
checks it). Rows' median keeps its behaviour exactly (the unit test replays the old code against the new over 500
samples).

- [ ] **Step 1: Write the failing test** `tests/Game/State/stats_spec.lua`:

```lua
-- tests/Game/State/stats_spec.lua (owner ruling 2026-10-22): the running statistics, written once.
local load = require("Game.State.helpers.load")

describe("the running statistics", function()
    local Stats = load.module().VirtualStateInternal.Stats

    it("moves an EMA and its deviation, the spread never below the floor", function()
        local e, d, s = Stats.Ema(10, 1, 20, 0.1, 0.5)
        assert.are.equal(11, e)
        assert.is_true(math.abs(d - (1 + 0.1 * (9 - 1))) < 1e-12)
        assert.are.equal(d, s)
        assert.are.same({ 10, 0, 0.5 }, { Stats.Ema(10, 0, 10, 0.1, 0.5) })
    end)

    it("keeps the swing lag's sign-step median exactly as Rows learned it", function()
        local function old(med, spr, d, w) -- Rows.lua:272-279 before Task 5, verbatim
            med = med + 0.005 * (d > med and 1 or -1)
            local s = spr + 0.05 * (1.2533 * math.abs(d - med) - spr)
            spr = s < 0.02 and 0.02 or (s > 0.4 and 0.4 or s)
            med = med < 0 and 0 or (med > w and w or med)
            return med, spr
        end
        local m1, s1, m2, s2, x = 0.474, 0.06, 0.474, 0.06, 1
        for _ = 1, 500 do
            x = (x * 16807) % 2147483647
            local d = 0.2 + (x % 1000) / 1000
            m1, s1 = old(m1, s1, d, 1.5)
            m2, s2 = Stats.Median(m2, s2, d, 0.005, 0, 1.5)
            assert.are.same({ m1, s1 }, { m2, s2 })
        end
    end)

    it("clamps", function()
        assert.are.same({ 0.02, 0.4, 0.3 }, { Stats.Clamp(0.01, 0.02, 0.4), Stats.Clamp(9, 0.02, 0.4),
            Stats.Clamp(0.3, 0.02, 0.4) })
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/State/stats_spec.lua`
Expected: FAIL, `attempt to index local 'Stats' (a nil value)`.

- [ ] **Step 3: Implement** `src/Hekili/Game/State/Stats.lua`:

```lua
-- Game/State/Stats.lua
-- The belief layer's running statistics, written once (owner ruling 2026-10-22, the belief-layer audit): an
-- exponential moving average with a mean-absolute-deviation spread and a floor (Resources' regen calibration and hit
-- rate, Attackers' learned period, the flight lag of Events/Tickets.lua), and a sign-step running median with a
-- clamped spread (Melee's swing landing lag). Pure arithmetic: no table, no client read.

local _, ns = ...
local I = ns.VirtualStateInternal

local Stats = {}
I.Stats = Stats
Stats.SPR_LO, Stats.SPR_HI, Stats.SPR_ALPHA = 0.02, 0.4, 0.05
local abs = math.abs

--- x clamped to [lo, hi]. Allocates nothing.
function Stats.Clamp(x, lo, hi)
    return x < lo and lo or (x > hi and hi or x)
end

--- One sample into an EMA: the new estimate, the new deviation (an EMA of |sample - the new estimate|) and the spread
--- (that deviation, never below `floor`). Allocates nothing.
function Stats.Ema(est, dev, sample, alpha, floor)
    local e = est + alpha * (sample - est)
    local d = dev + alpha * (abs(sample - e) - dev)
    return e, d, d > floor and d or floor
end

--- One sample d into a sign-step running median `med` (a step of `step` toward d, then clamped to [lo, hi]) and its
--- spread (mean absolute deviation to SD, 1.2533 x |d - med| against the stepped median, an EMA of SPR_ALPHA, clamped
--- to [SPR_LO, SPR_HI]). Allocates nothing.
function Stats.Median(med, spr, d, step, lo, hi)
    med = med + step * (d > med and 1 or -1)
    spr = Stats.Clamp(spr + Stats.SPR_ALPHA * (1.2533 * abs(d - med) - spr), Stats.SPR_LO, Stats.SPR_HI)
    return Stats.Clamp(med, lo, hi), spr
end
```

  Add `Game\State\Stats.lua` to `src/Hekili/Hekili.toc` after `Game\State\Belief.lua` (line 17).

- [ ] **Step 4: Move the callers onto it.**

  `Resources.lua`, at the top beside `local abs`: `local Stats = I.Stats`. In `ema` (lines 627-647) replace

```lua
    local est = E[r] + I.ALPHA * (m - E[r])
    local dev = D[r] + I.ALPHA * (abs(m - est) - D[r])
    local floor = abs(scale) * I.REGEN_SPREAD_MIN
    local spread = dev > floor and dev or floor
```

  with

```lua
    local est, dev, spread = Stats.Ema(E[r], D[r], m, I.ALPHA, abs(scale) * I.REGEN_SPREAD_MIN)
```

  In `calibrate` replace

```lua
    local scale = R.scale[r] + I.ALPHA * (ratio - R.scale[r])
    local dev = R.dev[r] + I.ALPHA * (abs(ratio - scale) - R.dev[r])
    R.scale[r], R.dev[r] = scale, dev
    R.spread[r] = dev > I.REGEN_SPREAD_MIN and dev or I.REGEN_SPREAD_MIN
```

  with

```lua
    local scale, dev, spread = Stats.Ema(R.scale[r], R.dev[r], ratio, I.ALPHA, I.REGEN_SPREAD_MIN) -- floor x 1: a ratio
    R.scale[r], R.dev[r], R.spread[r] = scale, dev, spread
```

  At line 1164 replace `hitRate[hand] = hitRate[hand] * (1 - HIT_ALPHA)` with
  `hitRate[hand] = (Stats.Ema(hitRate[hand], 0, 0, HIT_ALPHA, 0)) -- a swing: the share decays toward 0`.

  `Attackers.lua`: add `local Stats = I.Stats` beside `local floor = math.floor`, and at line 171 replace
  `atkPeriod[k] = period * 0.8 + gap / n * 0.2 -- shortcut: a plain EMA; a dual-wielding attacker blurs it` with
  `atkPeriod[k] = (Stats.Ema(period, 0, gap / n, 0.2, 0)) -- shortcut: a plain EMA; a dual-wielding attacker blurs it`.

  `Melee.lua`: replace `M.learn`'s body with

```lua
function M.learn(r, d)
    L.med[r], L.spr[r] = I.Stats.Median(L.med[r], L.spr[r], d, 0.005, 0, L.PAIR_WINDOW_MS[r == 1 and 1 or 2] / 1000)
end
```

- [ ] **Step 5: Run the unit test, then every spec that reads these numbers**

Run: `.lua/bin/busted tests/Game/State/stats_spec.lua && make test-fast && .lua/bin/busted --tags=slow tests/Game/harness/solo_spec.lua tests/Game/harness/group_spec.lua tests/Game/harness/onus_spec.lua`
Expected: PASS, 0 failures; the printed metrics equal Task 6b's run.

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Game/State/Stats.lua src/Hekili/Hekili.toc src/Hekili/Game/State/Families/Resources.lua \
  src/Hekili/Game/Events/Attackers.lua src/Hekili/Game/Events/Melee.lua tests/Game/State/stats_spec.lua
git commit -m "refactor(stats): one EMA and one running median for the belief layer's statistics

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 7b: One home for amount bands (`Events/Bands.lua`)

**Files:**
- Create: `src/Hekili/Game/Events/Bands.lua`
- Modify: `src/Hekili/Hekili.toc` (add `Game\Events\Bands.lua` after `Game\Events\CombatLog.lua`, before
  `Game\Events\Tickets.lua`)
- Modify: `src/Hekili/Game/Events/Melee.lua` (`M.classOf`, Rows.lua:223-242 before Task 5)
- Modify: `src/Hekili/Game/Events/Attackers.lua:182-198` (`base`, `fits`), `:269-271` (the band's learning)
- Test: `tests/Game/Events/bands_spec.lua` (new); the existing onus and pairing specs unchanged

**Interfaces:**
- Consumes: nothing.
- Produces: `I.Bands.Normalise(amount, flag, policy) -> v|nil` (a crit halved; policy `"ours"`: a partly blocked
  hit kept as given, a crushing one unchanged, Rows' white classes; policy `"theirs"`: a crushing one / 1.5 and a
  partly blocked one nil, Attackers' hits on us); `I.Bands.Learn(lo, hi, n, k, v, creep)` (band k in the caller's
  arrays: the first value sets both ends, a new low or high takes it, otherwise each end creeps toward v by `creep`;
  0 keeps min and max); `I.Bands.Fits(lo, hi, n, k, v, kLo, kHi, minN) -> bool`; `I.Bands.Class(v, lo, hi, looseLo) ->
  0..3` (a fixed range's grades: 1 inside, 2 loose [looseLo, 1.1 hi], 3 above (1.1 hi, 2 hi], 0 none).
- Boundary: the band arithmetic lives once; each caller keeps its own constants (Rows' 0.6/1.1/2 grades, Attackers'
  0.8/1.2 after 3, the cast bands' 0.6/1.6 after 3) and its BLOCK_REDUCED policy.

Implementation choice: BLOCK_REDUCED differs by caller today (Rows grades it in the loose class from 0; Attackers
drops it, since the blocked part is not given); the difference is kept as the `policy` parameter, not resolved, so no
caller's behaviour changes. A crushing blow is only ever dealt to the player, so `"ours"` leaving it unchanged is
today's code too.

- [ ] **Step 1: Write the failing test** `tests/Game/Events/bands_spec.lua`:

```lua
-- tests/Game/Events/bands_spec.lua (owner ruling 2026-10-22): amount bands, written once.
local load = require("Game.State.helpers.load")

describe("amount bands", function()
    local B = load.module().VirtualStateInternal.Bands

    it("normalises by policy: a crit halved; theirs divide a crush and drop a partial block", function()
        assert.are.same({ 15, 30, 30 }, { B.Normalise(30, "CRITICAL", "ours"), B.Normalise(30, "CRUSHING", "ours"),
            B.Normalise(30, "BLOCK_REDUCED", "ours") })
        assert.are.same({ 15, 20 }, { B.Normalise(30, "CRITICAL", "theirs"), B.Normalise(30, "CRUSHING", "theirs") })
        assert.is_nil(B.Normalise(30, "BLOCK_REDUCED", "theirs"))
        assert.is_nil(B.Normalise(nil, "", "ours"))
    end)

    it("learns min and max with no creep, and creeps toward a sample inside", function()
        local lo, hi, n = { 0 }, { 0 }, { 0 }
        for _, v in ipairs({ 20, 24, 18 }) do
            B.Learn(lo, hi, n, 1, v, 0)
        end
        assert.are.same({ 18, 24, 3 }, { lo[1], hi[1], n[1] })
        B.Learn(lo, hi, n, 1, 22, 0.05)
        assert.is_true(math.abs(lo[1] - 18.2) < 1e-12 and math.abs(hi[1] - 23.9) < 1e-12)
    end)

    it("fits once taught, and grades a fixed range", function()
        local lo, hi, n = { 18 }, { 24 }, { 3 }
        assert.is_true(B.Fits(lo, hi, n, 1, 28, 0.8, 1.2, 3))
        assert.is_false(B.Fits(lo, hi, n, 1, 29, 0.8, 1.2, 3))
        assert.is_false(B.Fits(lo, hi, { 2 }, 1, 20, 0.8, 1.2, 3))
        assert.are.same({ 1, 2, 3, 0, 0 }, { B.Class(40, 36, 50, 21.6), B.Class(54, 36, 50, 21.6),
            B.Class(90, 36, 50, 21.6), B.Class(101, 36, 50, 21.6), B.Class(10, 36, 50, 21.6) })
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/Events/bands_spec.lua`
Expected: FAIL, `attempt to index local 'B' (a nil value)`.

- [ ] **Step 3: Implement** `src/Hekili/Game/Events/Bands.lua`:

```lua
-- Game/Events/Bands.lua
-- Amount bands, written once (owner ruling 2026-10-22, the belief-layer audit): a hit's amount normalised to its
-- unmodified size, and band records kept in the caller's arrays (lo, hi, n by index) with their learning, their fit
-- and a fixed range's grades. Callers: Melee's white amount classes (a fixed UnitDamage range), Attackers' bands per
-- attacker, the ticket pool's cast bands. Pure: no table, no client read.

local _, ns = ...
local I = ns.VirtualStateInternal

local B = {}
I.Bands = B

--- A hit's amount as its unmodified size, or nil: a crit halved; `policy` "theirs" (hits on us) also divides a
--- crushing blow by 1.5 and drops a partly blocked hit (its blocked part is not given); "ours" keeps both as given.
function B.Normalise(amount, flag, policy)
    if type(amount) ~= "number" then
        return nil
    elseif flag == "CRITICAL" then
        return amount / 2
    elseif policy == "theirs" and flag == "CRUSHING" then
        return amount / 1.5
    elseif policy == "theirs" and flag == "BLOCK_REDUCED" then
        return nil
    end
    return amount
end

--- Band k learns v: the first value sets both ends; a new low or high takes it; otherwise each end creeps toward v by
--- `creep` (0: plain min and max). Allocates nothing.
function B.Learn(lo, hi, n, k, v, creep)
    if n[k] == 0 then
        lo[k], hi[k] = v, v
    else
        lo[k] = v < lo[k] and v or lo[k] + creep * (v - lo[k])
        hi[k] = v > hi[k] and v or hi[k] + creep * (v - hi[k])
    end
    n[k] = n[k] + 1
end

--- Whether band k, taught at least minN values, holds v within [kLo x lo, kHi x hi].
function B.Fits(lo, hi, n, k, v, kLo, kHi, minN)
    return v ~= nil and n[k] >= minN and v >= kLo * lo[k] and v <= kHi * hi[k]
end

--- v's grade against a fixed range [lo, hi]: 1 inside, 2 loose [looseLo, 1.1 hi], 3 above (1.1 hi, 2 hi], 0 none.
function B.Class(v, lo, hi, looseLo)
    if hi <= 0 or v < looseLo or v > 2 * hi then
        return 0
    elseif v >= lo and v <= hi then
        return 1
    end
    return v <= 1.1 * hi and 2 or 3
end
```

  Add `Game\Events\Bands.lua` to `src/Hekili/Hekili.toc` after `Game\Events\CombatLog.lua`.

- [ ] **Step 4: Move the callers onto it.** `Melee.lua`: replace `M.classOf`'s body with

```lua
function M.classOf(h, amount, flag)
    local minMain, maxMain, minOff, maxOff = VS.Stat("UnitDamage")
    local lo, hi = minMain, maxMain
    if h == 2 then
        lo, hi = minOff, maxOff
    end
    -- a glancing or partly blocked hit opens the loose band down to 0 (G's glancing 1-5 are another player's)
    local looseLo = (flag == "GLANCING" or flag == "BLOCK_REDUCED") and 0 or 0.6 * lo
    return I.Bands.Class(I.Bands.Normalise(amount, flag, "ours"), lo, hi, looseLo)
end
```

  `Attackers.lua`: replace `base` and `fits` (lines 182-198) with

```lua
local Bands = I.Bands

-- A wound's amount as its attacker's unmodified hit (Bands' "theirs": a crit halved, a crush / 1.5, a partly blocked
-- one nil), or nil for a secret amount or flag.
local function base(amount, flag)
    if type(flag) ~= "string" then
        return nil
    end
    return Bands.Normalise(amount, flag, "theirs")
end

-- Whether clock k's band is usable and holds `a`.
local function fits(k, a)
    return k ~= nil and Bands.Fits(atkLo, atkHi, atkN, k, a, L.BAND_LO, L.BAND_HI, L.BAND_N)
end
```

  and its band learning (lines 269-271) with `Bands.Learn(atkLo, atkHi, atkN, k, a, 0)`.

- [ ] **Step 5: Run the unit test, then the specs that use them**

Run: `.lua/bin/busted tests/Game/Events/bands_spec.lua && make test-fast && .lua/bin/busted --tags=slow tests/Game/harness/group_spec.lua tests/Game/harness/onus_spec.lua`
Expected: PASS, 0 failures; the printed metrics equal Task 7a's run.

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Game/Events/Bands.lua src/Hekili/Hekili.toc src/Hekili/Game/Events/Melee.lua \
  src/Hekili/Game/Events/Attackers.lua tests/Game/Events/bands_spec.lua
git commit -m "refactor(bands): one amount-band module; Melee's classes and Attackers' bands use it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 7: The FLIGHT kind: hard window, range bracket, learned lag, amount band

**Files:**
- Modify: `src/Hekili/Game/Events/Tickets.lua` (FLIGHT fields, lag records, amount bands, `arm`, `T.Pay`)
- Modify: `src/Hekili/Game/Events/Kinds.lua` (`K.Flight`, the FLIGHT branch of `K.Band`, the amount band in
  `K.Accepts`)
- Test: `tests/Game/Events/kinds_spec.lua`, `tests/Game/Events/tickets_spec.lua` (cases added)

**Interfaces:**
- Consumes: `I.Stats.Ema`, `I.Stats.Clamp` (Task 7a), `I.Bands.Learn`, `I.Bands.Fits`, `I.Bands.Normalise`
  (Task 7b), `A.velocity`, `A.rMax` (`Sources/Spellbook.lua:43`), `A.expDeclared`, `VS.TargetRange()`
  (`Families/Enemies.lua:71-73`: `{ lo, hi, last.observed.t }`), `I.Units.Bound(1)`.
- Produces: `T.speed[i]`, `T.H[i]`; `T.TOL` 0.15, `T.CLOSE` 7, `T.LAG_CAP` 16; `T.lagGUID/lagSpeed/lagE/lagSpr/lagT/
  lagN`; `T.LagOf(g, v) -> r|0`; `T.Learn(g, v, lag, t)`; `T.bandLo/bandHi/bandN` by ability;
  `K.Flight(i, p, t, v, H, a0) -> lo, hi, E | nil`; `K.SPELL_BAND_LO` 0.6, `K.SPELL_BAND_HI` 1.6, `K.BAND_N` 3.
- Boundary: the lag records and bands are the pool's state (Tickets); the band arithmetic is the kind's rule (Kinds).

Implementation choices: a clean payment at any pass teaches its (GUID, speed) record, pass (c) included: spec §3.3.1
says only (a) or (b), but with no record a ticket is a candidate in (c) only, so no record would ever be made. Task 19
copies this into spec §3.3.1 so the spec and the plan agree. A new record's spread starts at `TOL / 2` (so the first narrow band is `TOL` wide each side). The
amount band learns only for abilities that declared `expects` (a default type keeps today's acceptance exactly) and
is reset at each build (ability indices change with the spec).

- [ ] **Step 1: Write the failing tests.** Append inside `describe("the kinds", ...)` of
  `tests/Game/Events/kinds_spec.lua`:

```lua
    describe("FLIGHT", function()
        local a

        before_each(function()
            a = I.ab.bySpell[fs.SPENDER_P]
            I.ab.rMax[a] = 30 -- a 30 yd spell: H = 30 / 20 + 0.15 = 1.65
        end)

        it("with no record: only the hard window [0, rMax / speed + TOL], at pass 3", function()
            local i = open(fs.SPENDER_P, 100)
            assert.is_nil(K.Band(i, 1, 101.5, false, "WOUND", 8))
            assert.is_nil(K.Band(i, 2, 101.5, false, "WOUND", 8))
            local lo, hi, e = K.Band(i, 3, 101.5, false, "WOUND", 8)
            assert.is_true(lo == 100 and math.abs(hi - 101.65) < 1e-9)
            assert.is_true(math.abs(e - 100.825) < 1e-9)
        end)

        it("raises the lower bound from the target's plain range bracket, less a running mob's closing", function()
            VS.TargetRange = function()
                return { lo = 20, hi = 30, last = { observed = { t = 100 } } }
            end
            local i = open(fs.SPENDER_P, 100)
            local lo = K.Band(i, 3, 101, false, "WOUND", 8)
            -- (20 - 7 x 1) / 20 - 0.15 = 0.5 s after the success
            assert.is_true(math.abs(lo - 100.5) < 1e-9)
        end)

        it("with a record: the narrow band at pass 1, the widened one at pass 2, none at pass 3", function()
            T.Learn("Creature-1", 20, 1.5, 99)
            local i = open(fs.SPENDER_P, 100)
            local lo, hi, e = K.Band(i, 1, 101.5, false, "WOUND", 8)
            assert.is_true(math.abs(lo - 101.35) < 1e-9 and math.abs(hi - 101.65) < 1e-9 and e == 101.5)
            lo, hi = K.Band(i, 2, 101.5, false, "WOUND", 8) -- d = 2.5 s: down 0.35 x 2.5, up 0.175 x 2.5
            assert.is_true(math.abs(lo - (101.5 - 0.875)) < 1e-9 and math.abs(hi - 101.65) < 1e-9)
            assert.is_nil(K.Band(i, 3, 101.5, false, "WOUND", 8))
        end)

        it("leaves capture a's late MISS foreign once the GUID has a learned lag (spec §3.4's example)", function()
            T.Learn("Creature-1", 20, 1.5, 96.4)
            local i = open(fs.SPENDER_P, 97.374)
            for p = 1, 3 do
                local lo, hi = K.Band(i, p, 97.891, true, "MISS", 1)
                assert.is_false(lo ~= nil and 97.891 >= lo and 97.891 <= hi, "pass " .. p)
            end
        end)

        it("refuses a WOUND outside [0.6 lo, 1.6 hi] once three clean wounds taught the band", function()
            for _, v in ipairs({ 14, 16, 15 }) do
                local i = open(fs.SPENDER_P, 100)
                T.Pay(i, 101.5, false, v, "", true, 3)
            end
            local i = open(fs.SPENDER_P, 110)
            assert.is_true(K.Accepts(i, "WOUND", "", 15, 8, false))
            assert.is_true(K.Accepts(i, "WOUND", "CRITICAL", 30, 8, false))
            assert.is_false(K.Accepts(i, "WOUND", "", 40, 8, false))
            assert.are.equal(1, T.bandRejected)
            assert.are.same({ true, true }, { K.Accepts(i, "WOUND", "", 15, 8, false) }) -- banded: ranked first
        end)

        it("ranks a candidate whose learned band accepts the row before an older unbanded one", function()
            for _, v in ipairs({ 30, 32, 31 }) do -- teach the fire instant's band
                T.Pay(open(fs.SPENDER_F, 100), 100.01, false, v, "", true, 1)
            end
            local older = open(fs.SPENDER_C, 110.30) -- a default instant: school ANY, no band, the least closure
            local banded = open(fs.SPENDER_F, 110.32)
            assert.are.equal(banded, (T.Pick(110.33, "Creature-1", 1, "WOUND", "", 31, 4, false)))
            assert.are_not.equal(older, banded)
        end)
    end)
```

Append inside `describe("the ticket pool", ...)` of `tests/Game/Events/tickets_spec.lua`:

```lua
    it("pays a projectile's landing in its hard window and learns the GUID's lag from it", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        ctl.casting = { 10000, 11500 }
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SENT", "player", "Mob", "Cast-1", fs.SPENDER_P)
        ctl.Fire("UNIT_SPELLCAST_START", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 11.5
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 13.0
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 8)
        assert.are.equal(1, T.paid[X.FLIGHT])
        local r = T.LagOf("Creature-1", 20)
        assert.is_true(r > 0 and math.abs(T.lagE[r] - 1.5) < 1e-9)
        assert.are.same({ "SPELL_DAMAGE", 11.5, 8, true }, { got[#got][2], got[#got][1], got[#got][14], got[#got][21] })
    end)

    it("pays two projectiles of one queue in cast order (FIFO by expected closure)", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        T.Learn("Creature-1", 20, 1.5, 9)
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 10.6
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_P)
        ctl.now = 11.5
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8)
        ctl.now = 12.1
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 16, 8)
        local t1, t2 = got[#got - 1][1], got[#got][1]
        assert.are.same({ 10, 10.6 }, { t1, t2 })
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/kinds_spec.lua tests/Game/Events/tickets_spec.lua`
Expected: FAIL, `attempt to call field 'Learn' (a nil value)` and the FLIGHT bands nil at pass 3.

- [ ] **Step 3: Implement Tickets.lua.** After `T.onExpire, T.onPay = nil, nil` add:

```lua
-- FLIGHT (spec §3.3.1): per ticket its speed (yd/s) and hard window length H = rMax / speed + TOL.
T.TOL, T.CLOSE, T.LAG_CAP = 0.15, 7, 16
T.speed, T.H = {}, {}
for i = 1, CAP do
    T.speed[i], T.H[i] = 0, 0
end
-- The learned flight lag per (GUID, speed): the last observed lag, its spread, the time and count of observations.
-- Survive combat end (a GUID does not return); reset at load.
T.lagGUID, T.lagSpeed, T.lagE, T.lagSpr, T.lagT, T.lagN = {}, {}, {}, {}, {}, {}
for r = 1, T.LAG_CAP do
    T.lagGUID[r], T.lagSpeed[r], T.lagE[r], T.lagSpr[r], T.lagT[r], T.lagN[r] = "", 0, 0, 0, 0, 0
end

--- The lag record of (g, v), or 0.
function T.LagOf(g, v)
    for r = 1, T.LAG_CAP do
        if T.lagGUID[r] == g and T.lagSpeed[r] == v then
            return r
        end
    end
    return 0
end

--- A clean flight payment's lag teaches (g, v)'s record (a full pool gives the oldest way). Allocates nothing.
function T.Learn(g, v, lag, t)
    local r = T.LagOf(g, v)
    if r == 0 then
        r = 1
        for q = 1, T.LAG_CAP do
            if T.lagGUID[q] == "" then
                r = q
                break
            elseif T.lagT[q] < T.lagT[r] then
                r = q
            end
        end
        T.lagGUID[r], T.lagSpeed[r], T.lagE[r], T.lagSpr[r], T.lagN[r] = g, v, lag, T.TOL / 2, 0
    end
    local Stats = I.Stats -- Task 7a: the one EMA (spread 0.25 x 1.2533 |lag - last|, clamped [0.02, 0.4])
    local s = Stats.Ema(T.lagSpr[r], 0, 1.2533 * math.abs(lag - T.lagE[r]), 0.25, 0)
    T.lagSpr[r] = Stats.Clamp(s, Stats.SPR_LO, Stats.SPR_HI)
    T.lagE[r], T.lagT[r], T.lagN[r] = lag, t, T.lagN[r] + 1 -- the last lag: a closing mob makes it shrink
end

-- Per ability: the amount band of its own clean wounds (a crit halved), declared abilities only (spec §3.4).
T.bandLo, T.bandHi, T.bandN = {}, {}, {}
I.OnBuild(function()
    for a = 1, A.n do
        T.bandLo[a], T.bandHi[a], T.bandN[a] = 0, 0, 0
    end
end)

local function teach(a, amount, flag) -- Task 7b's band: a new low or high takes it, else each end creeps by 0.05
    I.Bands.Learn(T.bandLo, T.bandHi, T.bandN, a, I.Bands.Normalise(amount, flag, "ours"), 0.05)
end
```

In `arm`, before `elseif k == UNMAPPED then`, add:

```lua
    elseif k == X.FLIGHT then
        local a = ab[i]
        local r = A.rMax[a] > 0 and A.rMax[a] or 40 -- 0: no range read; 40 yd covers every spell range
        T.speed[i] = A.velocity[a]
        T.H[i] = r / T.speed[i] + T.TOL
        hi[i] = t + T.H[i]
```

In `T.Pay`, after the `T.onPay` call, add:

```lua
    local k, a = kind[i], ab[i]
    if clean and k == X.FLIGHT then
        T.Learn(guid[i], T.speed[i], t - at[i], t)
    end
    if clean and not isAvoid and a > 0 and A.expDeclared[a] and (k == X.FRAME or k == X.FLIGHT or k == X.STRIKE) then
        teach(a, amount, flag)
    end
```

- [ ] **Step 4: Implement Kinds.lua.** After `local FRAME, STRIKE, ... = ...` add:

```lua
local FLIGHT, TICKS, CHANNEL = X.FLIGHT, X.TICKS, X.CHANNEL
K.SPELL_BAND_LO, K.SPELL_BAND_HI, K.BAND_N = 0.6, 1.6, 3

-- Seconds after its anchor before which a flight to ticket i's GUID cannot land, from the target's plain range
-- bracket (poll 14) when the GUID is the current target: (lo - CLOSE x age) / speed - TOL, never below 0. The
-- bracket's upper bound is never used (a closing mob makes it stale on the wrong side).
local function rangeLow(i, t, v)
    if T.guid[i] ~= I.Units.Bound(1) then
        return 0
    end
    local r = ns.VirtualState.TargetRange()
    if not (r.lo and r.lo > 0 and r.last) then
        return 0
    end
    local lo = (r.lo - T.CLOSE * (t - r.last.observed.t)) / v - T.TOL
    return lo > 0 and lo or 0
end

--- (spec §3.3.1) A flight's band for ticket i at pass p (speed v, hard window H from anchor a0): with no (GUID, v)
--- record, only the whole hard window at pass 3 (E its middle); with one, the narrow band lagE +- b at pass 1 and the
--- widened band at pass 2 (down by CLOSE / v per second since the last landing, up by half that), clipped to the
--- hard window, and nothing at pass 3.
function K.Flight(i, p, t, v, H, a0)
    local lo0, hiH = a0 + rangeLow(i, t, v), a0 + H
    local r = T.LagOf(T.guid[i], v)
    if r == 0 then
        if p < 3 then
            return nil
        end
        return lo0, hiH, a0 + H / 2
    elseif p == 3 then
        return nil
    end
    local e = a0 + T.lagE[r]
    local b = 2 * T.lagSpr[r] > T.TOL and 2 * T.lagSpr[r] or T.TOL
    local down, up = b, b
    if p == 2 then
        local d = t - T.lagT[r]
        down = T.CLOSE / v * d > b and T.CLOSE / v * d or b
        up = T.CLOSE / 2 / v * d > b and T.CLOSE / 2 / v * d or b
    end
    local lo, h = e - down, e + up
    return lo > lo0 and lo or lo0, h < hiH and h or hiH, e
end
```

In `K.Band`, before its final `end`, add:

```lua
    if k == FLIGHT then
        return K.Flight(i, p, t, T.speed[i], T.H[i], a0)
    end
```

Replace `K.Accepts`'s last two lines (`local s = T.school[i]` and `return s == ANY or ...`) with:

```lua
    local s = T.school[i]
    if not (s == ANY or (s > 0 and s == sch)) then
        return false
    end
    local a = T.ab[i]
    if a > 0 and k ~= TICKS and k ~= CHANNEL and T.bandN[a] >= K.BAND_N then
        local B = I.Bands
        local v = B.Normalise(amount, flag, "ours")
        if not B.Fits(T.bandLo, T.bandHi, T.bandN, a, v, K.SPELL_BAND_LO, K.SPELL_BAND_HI, K.BAND_N) then
            T.bandRejected = T.bandRejected + 1
            return false
        end
        return true, true -- a learned band accepted it: ranked first (T.Pick)
    end
    return true, false
```

- [ ] **Step 5: Run them**

Run: `.lua/bin/busted tests/Game/Events/kinds_spec.lua tests/Game/Events/tickets_spec.lua`
Expected: PASS (9 and 11 successes).

- [ ] **Step 6: Run every existing spec**

Run: `make test-fast`
Expected: PASS, 0 failures (no fake-spec ability without `expect` declares `travel`).

- [ ] **Step 7: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Kinds.lua tests/Game/Events/kinds_spec.lua \
  tests/Game/Events/tickets_spec.lua
git commit -m "feat(tickets): FLIGHT kind: hard window, range bracket, learned per-GUID lag, amount band

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 8: The TICKS and CHANNEL kinds

**Files:**
- Modify: `src/Hekili/Game/Events/Tickets.lua` (schedule fields, `fill`, `arm`, `compose`, `T.Pay`, the `OnGone`
  listener, `T.AuraGone`, `T.ChannelStop`)
- Modify: `src/Hekili/Game/Events/Kinds.lua` (TICKS and CHANNEL bands)
- Modify: `src/Hekili/Game/Events/CombatLog.lua:189-192`, `:199-202` (a removed target debuff tells the pool)
- Modify: `src/Hekili/Game/Events/Rows.lua` (a `UNIT_SPELLCAST_CHANNEL_STOP` handler)
- Test: `tests/Game/Events/tickets_spec.lua`, `tests/Game/Events/kinds_spec.lua` (cases added)

**Interfaces:**
- Consumes: `I.Expect.Tick(a)` and `A.ticking` (Task 4: the aura's period and count, read at the commit),
  `A.velocity`, `A.rMax`; `T.LagOf`, `T.H`, `T.speed`, `K.Flight` (Task 7);
  `I.Units.OnGone` DEAD.
- Produces: `T.period[i]`, `T.anchor[i]`, `T.wide[i]`, `T.link[i]` (j on a direct ticket, -1 on its composed TICKS
  ticket, 0 none), `T.tickAmt[i]` (the last paid tick's amount, 0 before the first: the soft band
  `[K.TICK_BAND_LO, K.TICK_BAND_HI]` = `[0.5x, 2x]` of it, owner ruling 2026-10-22); `T.TICK_BAND` 0.1; `T.AuraGone(spellID, guid, t)` (installed as `L.AuraGone`);
  `T.ChannelStop(spellID, t)`.
- Boundary: the schedule's state is the pool's; the tick band is the kind's; CombatLog only tells the pool a debuff
  row left, it decides nothing.

Implementation choices: a debuff's removal closes its TICKS ticket (`signal`) only when it comes before the last
tick's band opens; at the modelled expiry (the duration, where the last tick also falls, +-50 ms) the ticket keeps its
band and expires on its own, so the last tick is not turned foreign by the removal row's order. CHANNEL owes rows
without end and closes only on `T.ChannelStop` or combat end (spec §3.3; U9's channel half deferred: implemented,
tested against the harness's own tick model only, used by no pack).

- [ ] **Step 1: Write the failing tests.** Append inside `describe("the ticket pool", ...)`:

```lua
    describe("TICKS", function()
        local function wound(t, amount, sch)
            ctl.now = t
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", amount, sch)
        end

        it("opens the direct ticket and the ticks of an instant with ticks; pays each tick on schedule", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64) -- the direct hit re-anchors the schedule
            for _, t in ipairs({ 13.038, 16.022, 19.072, 21.969 }) do
                wound(t, 4, 64)
            end
            assert.are.same({ 1, 1 }, { T.paid[X.FRAME], T.paid[X.TICKS] })
            assert.are.same({ "SPELL_PERIODIC_DAMAGE", 21.969 }, { got[#got][2], got[#got][1] })
        end)

        it("leaves a tick outside every band foreign", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            wound(11.5, 4, 64)
            assert.are.equal(1, T.foreign)
        end)

        it("closes the old schedule as refreshed on a recast; the new one pays", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            wound(13.0, 4, 64)
            ctl.now = 14
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_M)
            wound(14.002, 8, 64)
            assert.are.equal(1, T.closed.refreshed)
            wound(17.01, 4, 64)
            local paidTicks = 0
            for i = 1, T.CAP do
                if T.state[i] ~= T.FREE and T.kind[i] == X.TICKS then
                    paidTicks = T.done[i]
                end
            end
            assert.are.equal(1, paidTicks)
            assert.are.equal(0, T.lost[X.TICKS])
        end)

        it("closes a dead unit's ticks as closedDead, ours when we killed it, never lost", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            ctl.Fire("PARTY_KILL", "Player-1", "Creature-1")
            ctl.Fire("UNIT_DIED", "Creature-1")
            assert.are.same({ 1, 1, 0 }, { T.closed.dead, T.ours, T.lost[X.TICKS] })
        end)

        it("anchors a ticks-only flight at half the flight with a widened band, then snaps to the first tick", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30 -- 30 / 40: a 0.75 s flight at most
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S)
            wound(13.7, 6, 8) -- 3 s after a 0.7 s flight: inside 10.375 + 3 +- (0.1 + 0.375)
            local i
            for j = 1, T.CAP do
                if T.state[j] ~= T.FREE and T.kind[j] == X.TICKS then
                    i = j
                end
            end
            assert.are.same({ 1, 0 }, { T.done[i], T.wide[i] })
            assert.is_true(math.abs(T.anchor[i] - 10.7) < 1e-9)
        end)

        it("closes a ticks-only ticket with nothing owed when its application is avoided at range", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S)
            ctl.now = 10.7
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
            assert.are.same({ 1, 0 }, { T.paid[X.TICKS], T.lost[X.TICKS] })
        end)

        it("closes a schedule on an early removal of its debuff, not at its modelled expiry", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
            wound(10.002, 9, 64)
            T.AuraGone(fs.SPENDER_M, "Creature-1", 22.002) -- the duration: the last tick still owed
            assert.are.equal(0, T.closed.signal)
            T.AuraGone(fs.SPENDER_M, "Creature-1", 15) -- removed early (a handler's removeDebuff)
            assert.are.equal(1, T.closed.signal)
        end)
    end)

    it("pays a tick in a learned schedule's and a banded projectile's bands to the schedule (owner ruling)", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_S]] = 30
        for _, v in ipairs({ 14, 16, 15 }) do -- the nature projectile's band: [0.6 x 14.1, 1.6 x 15.95]; its lag 1.5 s
            T.Pay(T.OpenCast(1, I.ab.bySpell[fs.SPENDER_P], fs.SPENDER_P, "Creature-1"), 2.5, false, v, "", true, 3)
        end
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_S) -- a nature schedule (3 s ticks)
        ctl.now = 13.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 6, 8) -- its first tick: no tick band yet; snaps to 10.7
        ctl.now = 15.2
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", fs.SPENDER_P) -- due at 16.7 +- 0.15
        ctl.now = 16.7
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 7, 8) -- the second tick, also in the projectile's narrow band
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8) -- the projectile's own landing, the same ms
        local ticks
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.TICKS then
                ticks = j
            end
        end
        assert.are.same({ 2, 7, 4 }, { T.done[ticks], T.tickAmt[ticks], T.paid[X.FLIGHT] })
    end)

    it("CHANNEL (untested in game, U9): pays a tick per period and closes on its stop", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_H)
        for _, t in ipairs({ 11.02, 11.98, 13.1 }) do
            ctl.now = t
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 5, 64)
        end
        ctl.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "Cast-1", fs.SPENDER_H)
        assert.are.same({ 1, 0 }, { T.closed.signal, T.foreign })
    end)
```

Append inside `describe("the kinds", ...)`:

```lua
    it("TICKS: tick k at the anchor + k x period +- 0.1 s, every pass alike", function()
        local i = open(fs.SPENDER_M, 10) -- the direct ticket; its TICKS ticket is link[i]
        local j = T.link[i]
        for p = 1, 3 do
            local lo, hi, e = K.Band(j, p, 13, false, "WOUND", 64)
            assert.is_true(math.abs(lo - 12.9) < 1e-9 and math.abs(hi - 13.1) < 1e-9 and e == 13)
        end
        assert.is_nil(K.Band(j, 2, 10.1, true, "MISS", 1)) -- a composed schedule takes no avoid
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/Events/kinds_spec.lua`
Expected: FAIL, `attempt to index field 'link' (a nil value)` and `attempt to call field 'AuraGone' (a nil value)`.

- [ ] **Step 3: Implement Tickets.lua.** After the FLIGHT fields add:

```lua
-- TICKS and CHANNEL (spec §3.3): the period, the schedule's anchor (the application), a widening while a velocity
-- TICKS ticket has no learned lag, and the link between a direct ticket (j) and its composed TICKS ticket (-1).
T.TICK_BAND = 0.1
T.period, T.anchor, T.wide, T.link, T.tickAmt = {}, {}, {}, {}, {}
for i = 1, CAP do
    T.period[i], T.anchor[i], T.wide[i], T.link[i], T.tickAmt[i] = 0, 0, 0, 0, 0
end
```

In `fill`, append the line:

```lua
    T.period[i], T.anchor[i], T.wide[i], T.link[i], T.speed[i], T.H[i], T.tickAmt[i] = 0, t, 0, 0, 0, 0, 0
```

Before `arm`, add:

```lua
-- TICKS ticket i of ability a: its aura's count of rows owed (read now, Families/Expect.lua's X.Tick), tick k at
-- app + k x period +- (TICK_BAND + wide). The count at any time is done + owed.
local function schedule(i, a, app, wide)
    local period, count = X.Tick(a)
    T.period[i], owed[i], T.anchor[i], T.wide[i] = period, count, app, wide
    hi[i] = app + count * period + T.TICK_BAND + wide
end

-- A new application of a on g closes its open TICKS ticket as refreshed (unpaid rows not lost; decision 37).
local function refresh(a, g, t, except)
    for j = 1, CAP do
        if j ~= except and state[j] >= OPEN and kind[j] == X.TICKS and ab[j] == a and guid[j] == g then
            close(j, t, "refreshed")
        end
    end
end
```

In `arm`, before `elseif k == UNMAPPED then`, add:

```lua
    elseif k == X.TICKS then -- alone (Corruption-shaped): anchored at the success, after the flight with a velocity
        local a = ab[i]
        refresh(a, guid[i], t, i)
        local v = A.velocity[a]
        if v > 0 then
            local rm = A.rMax[a] > 0 and A.rMax[a] or 40
            T.speed[i], T.H[i] = v, rm / v + T.TOL
            local r = T.LagOf(guid[i], v)
            if r > 0 then
                schedule(i, a, t + T.lagE[r], 0)
            else
                schedule(i, a, t + rm / v / 2, rm / v / 2) -- decision 36: widened until the first tick
            end
        else
            schedule(i, a, t, 0)
        end
    elseif k == X.CHANNEL then -- U9 deferred: owes rows until its stop
        T.period[i], owed[i], hi[i] = (X.Tick(ab[i])), math.huge, math.huge
```

After `arm`, add:

```lua
-- A direct ticket whose aura is a debuff dot (A.ticking) opens its TICKS ticket on the same GUID (decision 35), anchored at
-- the success (widened by the flight's hard window for a projectile) until the direct row re-anchors it.
local function compose(i, t)
    local a = ab[i]
    if a == 0 or not A.ticking[a] or (kind[i] ~= X.FRAME and kind[i] ~= X.FLIGHT) then
        return
    end
    refresh(a, guid[i], t, i)
    local j = T.Slot(t)
    fill(j, X.TICKS, a, x[i], guid[i], t)
    school[j], T.link[j], T.link[i] = school[i], -1, j
    schedule(j, a, t, kind[i] == X.FLIGHT and T.H[i] or 0)
end
```

In `T.OpenCast`, after `arm(i, t)`, add `compose(i, t)`. In `T.Arm`, replace `arm(i, t)` with
`arm(i, t)` followed by `compose(i, t)`.

In `T.Pay`, before `if owed[i] <= 0 then`, add:

```lua
    if k == X.TICKS and not isAvoid then -- the owner's soft band: the last paid tick's amount (a crit halved)
        T.tickAmt[i] = flag == "CRITICAL" and amount / 2 or amount
    end
    if k == X.TICKS and T.wide[i] > 0 then -- the first tick paid: the schedule snaps to it
        T.anchor[i], T.wide[i] = t - done[i] * T.period[i], 0
        hi[i] = T.anchor[i] + (done[i] + owed[i]) * T.period[i] + T.TICK_BAND
    end
    if isAvoid and k == X.TICKS then
        owed[i] = 0 -- the application avoided: nothing owed, not lost
    end
    local j = T.link[i]
    if j > 0 and state[j] >= OPEN and kind[j] == X.TICKS and T.link[j] == -1 then
        if isAvoid then
            close(j, t, "signal") -- the direct hit was avoided: no debuff, no ticks
        else
            T.anchor[j], T.wide[j] = t, 0 -- the application is the direct row
            hi[j] = t + owed[j] * T.period[j] + T.TICK_BAND
        end
    end
```

Replace the `U.OnGone` listener with:

```lua
-- A unit gone (released and past GRACE: normally nothing pins it) or dead: a dead unit's schedules end at once
-- (`dead`, ours when we killed it); its other tickets stay open until paid or their own window ends (decision 8).
U.OnGone(function(u, g, why, t)
    for i = 1, CAP do
        if state[i] ~= 0 and uid[i] == u then
            if why == U.GONE then
                if state[i] ~= COMMITTED and T.onExpire then
                    T.onExpire(i, t)
                end
                close(i, t, "gone")
            elseif why == U.DEAD and kind[i] == X.TICKS then
                if U.Ours(u) then
                    T.ours = T.ours + 1
                end
                close(i, t, "dead")
            end
        end
    end
end)

--- Our debuff `spellID` left `g` at t (CombatLog's SPELL_AURA_REMOVED): its schedule closes (`signal`) when that is
--- before its last tick's band. Allocates nothing.
function T.AuraGone(spellID, g, t)
    local a = A.bySpell[spellID]
    if not a then
        return
    end
    for i = 1, CAP do
        if state[i] >= OPEN and kind[i] == X.TICKS and ab[i] == a and guid[i] == g then
            local last = T.anchor[i] + (done[i] + owed[i]) * T.period[i]
            if t < last - T.TICK_BAND - T.wide[i] then
                T.paid[X.TICKS] = T.paid[X.TICKS] + 1
                close(i, t, "signal")
            end
        end
    end
end
I.Log.AuraGone = T.AuraGone

--- Our channel `spellID` stopped at t: its CHANNEL ticket closes (`signal`).
function T.ChannelStop(spellID, t)
    for i = 1, CAP do
        if state[i] >= OPEN and kind[i] == X.CHANNEL and x[i] == spellID then
            T.paid[X.CHANNEL] = T.paid[X.CHANNEL] + 1
            close(i, t, "signal")
        end
    end
end
```

- [ ] **Step 4: Implement Kinds.lua.** In `K.Accepts`, after its school check (`if not (s == ANY or ...) then
  return false end`), add the TICKS soft band:

```lua
    if k == TICKS then -- owner ruling 2026-10-22: no band before the first paid tick, then [0.5x, 2x] of the last one
        local m = T.tickAmt[i]
        if m <= 0 then
            return true, false
        end
        local v = flag == "CRITICAL" and amount / 2 or amount
        if v < K.TICK_BAND_LO * m or v > K.TICK_BAND_HI * m then
            T.bandRejected = T.bandRejected + 1
            return false
        end
        return true, true
    end
```

  and beside `K.SPELL_BAND_LO, ...` add `K.TICK_BAND_LO, K.TICK_BAND_HI = 0.5, 2`. In `K.Band`, before the
  `if k == FLIGHT then` block, add:

```lua
    if k == TICKS then
        if isAvoid then -- only an alone ticket's application, before its first tick (decision 35)
            if T.link[i] == -1 or T.done[i] > 0 then
                return nil
            elseif T.speed[i] > 0 then
                return K.Flight(i, p, t, T.speed[i], T.H[i], a0)
            elseif p == 1 then
                return nil
            end
            return a0, a0 + L.LandWindow(1), a0
        end
        local e = T.anchor[i] + (T.done[i] + 1) * T.period[i]
        local half = T.TICK_BAND + T.wide[i] -- the schedule is the only discriminator: every pass alike
        return e - half, e + half, e
    elseif k == CHANNEL then
        local e = a0 + (T.done[i] + 1) * T.period[i]
        local half = p == 1 and T.TOL or 2 * T.TOL
        return e - half, e + half, e
    end
```

- [ ] **Step 5: CombatLog tells the pool.** In `src/Hekili/Game/Events/CombatLog.lua`, after `L.target = ""` (line 145)
  add `L.AuraGone = nil -- Events/Tickets.lua: a removed target debuff of ours ends its schedule early`. In `L.Aura`'s
  removal branch (lines 189-192), after `auraRow("SPELL_AURA_REMOVED", u, j, t, true, "inferred")` add:

```lua
        if u == 2 and L.AuraGone then
            L.AuraGone(auraId[u][j], auraDst[u][j], t)
        end
```

  and in the modelled-expiry tick (lines 199-202), after `auraRow("SPELL_AURA_REMOVED", u, j, now, false, "modelled")`:

```lua
                if u == 2 and L.AuraGone then
                    L.AuraGone(auraId[u][j], auraDst[u][j], now)
                end
```

- [ ] **Step 6: Rows closes a channel on its stop.** In `src/Hekili/Game/Events/Rows.lua`, after the
  `UNIT_SPELLCAST_INTERRUPTED` registration add:

```lua
S.On("UNIT_SPELLCAST_CHANNEL_STOP", "player", function(api, t, unit, castGUID, spellID)
    if unit == "player" and type(spellID) == "number" then
        T.ChannelStop(spellID, t)
    end
end)
```

- [ ] **Step 7: Run them, then every existing spec**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/Events/kinds_spec.lua && make test-fast`
Expected: PASS (tickets 20, kinds 10 successes; test-fast 0 failures).

- [ ] **Step 8: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Kinds.lua src/Hekili/Game/Events/CombatLog.lua \
  src/Hekili/Game/Events/Rows.lua tests/Game/Events/tickets_spec.lua tests/Game/Events/kinds_spec.lua
git commit -m "feat(tickets): TICKS (composed, refreshed, flight-anchored) and CHANNEL (untested in game) kinds

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 9: Kills, the first swing of a combat, and TargetHealth's note

**Files:**
- Modify: `src/Hekili/Game/Events/Rows.lua` (`PLAYER_ENTER_COMBAT` handler; the swing-explains check reads
  `T.first`)
- Modify: `src/Hekili/Game/State/Families/TargetHealth.lua:10-11` (the stale secrecy note)
- Test: `tests/Game/Events/kills_spec.lua` (new)

**Interfaces:**
- Consumes: `I.Units` deaths (Task 2), `T.first`, `T.closed.dead`, `T.ours` (Task 6).
- Produces: no new function. `T.first[i]` is true on the first swing ticket after `PLAYER_ENTER_COMBAT` (spec §3.3.2,
  U10): it never teaches the lag (Task 6's `not T.first[credited]`) and its Due band is its whole LR window.
- Boundary: Rows reads the flag; Melee's learning is unchanged.

- [ ] **Step 1: Write the failing test** `tests/Game/Events/kills_spec.lua`:

```lua
-- tests/Game/Events/kills_spec.lua (unit-registry spec §2.5, §3.3.2, §3.6): a kill's rows and closes, from the
-- 2026-10-22 kill-events capture's order: the killing swing and PARTY_KILL in one ms, UNIT_DIED and PLAYER_TARGET_DIED
-- 2 ms later, the target cleared 2 ms after that, a new target 20 ms later, and the killing WOUND 456 ms after the
-- swing on softinteract alone (the corpse); and the first swing of a combat.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("kills and the first swing", function()
    local api, ctl, ns, VS, I, T, X, saved, got

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
        T, X = I.Tickets, I.Expect
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        VS.Start(api)
        got = {}
        local f = I.Events.CreateFrame("Frame")
        f:SetScript("OnEvent", function()
            got[#got + 1] = { ns.Facade.CombatLogGetCurrentEventInfo() }
        end)
        f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("pays the white killing blow that lands on softinteract after the clear", function()
        ctl.now = 4.364
        ctl.Fire("PLAYER_SWING", 1.6, 0)
        ctl.Fire("PARTY_KILL", "Player-1", "Creature-1")
        ctl.now = 4.366
        ctl.Fire("UNIT_DIED", "Creature-1")
        ctl.Fire("PLAYER_TARGET_DIED")
        ctl.guid.target = nil
        ctl.now = 4.368
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.guid.target = "Creature-2"
        ctl.now = 4.388
        ctl.Fire("PLAYER_TARGET_CHANGED")
        ctl.guid.softinteract = "Creature-1"
        ctl.now = 4.82
        ctl.Fire("UNIT_COMBAT", "softinteract", "WOUND", "", 5, 1)
        assert.are.equal(1, T.paid[X.MELEE])
        local r = got[#got]
        assert.are.same({ "SWING_DAMAGE", 4.364, "Creature-1", 5 }, { r[2], r[1], r[8], r[12] })
    end)

    it("closes a projectile's ticket on a unit another source killed as closedDead, not lost, not ours", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 10.5
        ctl.Fire("UNIT_DIED", "Creature-1")
        ctl.Tick(12)
        assert.are.same({ 1, 0, 0 }, { T.closed.dead, T.lost[X.FLIGHT], T.ours })
    end)

    it("marks the first swing after PLAYER_ENTER_COMBAT, which explains an avoid anywhere in its window", function()
        ctl.Fire("PLAYER_ENTER_COMBAT")
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        local i
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.MELEE then
                i = j
            end
        end
        assert.is_true(T.first[i])
        ctl.now = 10.9
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
        ctl.now = 10.91
        ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1) -- in the cast's frame, 0.91 s after the first swing
        for _, r in ipairs(got) do
            assert.is_false(r[2] == "SPELL_MISSED", "the first swing's lag spans its window: the swing's avoid")
        end
        ctl.now = 13
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        for j = 1, T.CAP do
            if T.state[j] ~= T.FREE and T.kind[j] == X.MELEE and T.at[j] == 13 then
                assert.is_false(T.first[j])
            end
        end
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/Events/kills_spec.lua`
Expected: FAIL on the third case, `Expected objects to be the same` / `is_true` on `T.first[i]` (no handler sets it),
and the `SPELL_MISSED` assertion.

- [ ] **Step 3: Implement.** In `src/Hekili/Game/Events/Rows.lua`, after the `PLAYER_SWING` handler add:

```lua
-- U10 (owner ruling): auto-attack turns on at once, and the first PLAYER_SWING after entering combat is that first
-- swing; its row's lag is one sample (989 ms in the second Rogue capture), so it teaches nothing and its Due band is
-- its whole window. The client may send that swing first in the same ms (second Rogue capture: both at 628).
S.On("PLAYER_ENTER_COMBAT", nil, function(api, t)
    for i = 1, T.CAP do
        if T.state[i] ~= 0 and T.kind[i] == MELEE and t - T.at[i] <= 0.01 then
            T.first[i] = true
            return
        end
    end
    fresh = true
end)
```

In the `OnRow` body, the swing-explains condition becomes:

```lua
        if sw and (T.first[sw] or lag <= SAME_FRAME or math.abs(lag - L.med[h]) <= 2 * L.spr[h]) then
```

In `src/Hekili/Game/State/Families/TargetHealth.lua` replace lines 10-11 with:

```lua
-- Not built until the in-game checkpoint (design §7) answers: a short answer (c = 1) as a health signal (line 4).
-- UnitHealth and UnitHealthMax are secret on the target and on nameplates, out of combat too (the 2026-10-22
-- captures, probe U5), so M stays learned, never read. A kill ends the slot at its death (TargetGone from the unit
-- registry's death events, Sources/Target.lua).
```

- [ ] **Step 4: Run it and every existing spec**

Run: `.lua/bin/busted tests/Game/Events/kills_spec.lua && make test-fast`
Expected: PASS (3 successes; test-fast 0 failures).

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Game/Events/Rows.lua src/Hekili/Game/State/Families/TargetHealth.lua \
  tests/Game/Events/kills_spec.lua
git commit -m "feat(rows): the first swing of a combat; kill rows pay after the clear; TargetHealth's note

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 9b: Expected rage for an uncredited swing

**Files:**
- Modify: `src/Hekili/Game/Events/Rows.lua` (`T.onExpire` stages the uncredited swing)
- Modify: `src/Hekili/Game/State/Families/Resources.lua:1159-1213` (`Obs.Swing` c = 5, and a later credit of the same
  swing retracts the expectation)
- Test: `tests/Game/State/resources_spec.lua` (cases added)

**Interfaces:**
- Consumes: the swing ticket's expiry (`T.onExpire`, Tasks 6 and 6b), `hitRate` (`Resources.lua:133`),
  `I.SwingValue(r, hand, at)` and `R.scale[r]` (the credit's own step, `swingStep` `:856-885`).
- Produces: `Obs.Swing` with c = 5 (b = 0) at the swing's time: "this swing's window closed with no row of its own"
  (staged by Rows for a MELEE ticket that expires pinned, unpaid and with no provisional avoid). Resources adds that
  swing's expected rage `hitRate[hand] x I.SwingValue(r, hand, at) x R.scale[r]` to `est` and `hi` of each slot the
  hand pays; `lo` is unchanged (the floor stays a floor, so the simulation never over-spends). A credit (c = 1) of the
  same swing (`o.t` equal to the expectation's swing time: the same `T.at` value, no float arithmetic between them)
  first takes the expectation back out, then pays as before.
- Boundary: the ticket says what happened to the swing; the belief alone decides what that is worth.

Evidence (owner-confirmed, 2026-10-22): a level-25 Fury Warrior with two 1.5 s weapons and 20% haste had about 100
rage in game while the belief read est 42.6 (lo 37, hi 51): about 23% of swings credited (41 main and 39 off of about
350 swing rows, 664 rows to the background), the last usability pin 12.6 s earlier, and a Heroic Strike line at rage
>= 40 flickering at its threshold. Uncredited swings added nothing to the estimate.

Implementation choice: `hitRate` is the credited share of swings (it decays at each swing and rises at each credit),
so with a low credit rate the expectation is that low share times the step: conservative against the truth, never
above it; the gates measure what it recovers.

- [ ] **Step 1: Write the failing test.** Append inside the top `describe` of `tests/Game/State/resources_spec.lua`
  (its booted fake spec: a rage slot paid by the main hand's swings; `ctl`, `VS`, `I` as that file names them):

```lua
    it("adds an uncredited swing's expected rage to est and hi, never to lo", function()
        local R, slot = I.res, nil
        slot = R.slotOf[fs.RAGE]
        local step = I.SwingValue(slot, 1, 0) * R.scale[slot]
        local e0, lo0 = R.est0[slot], R.lo0[slot]
        for k = 1, 10 do
            ctl.now = 50 + 3 * k
            ctl.Fire("PLAYER_SWING", 2.6, 0) -- no row ever comes for it
            ctl.Tick(ctl.now + 2) -- its window closes uncredited
            I.Sources.Flush()
            I.Fold(ctl.now)
        end
        local rise = R.est0[slot] - e0
        assert.is_true(rise >= 10 * 0.9 ^ 10 * step - 1e-9 and rise <= 10 * step + 1e-9, ("rise %.2f"):format(rise))
        assert.are.equal(lo0, R.lo0[slot])
    end)

    it("takes the expectation back when the same swing is credited after all", function()
        local R = I.res
        local slot = R.slotOf[fs.RAGE]
        ctl.now = 90
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Tick(92)
        I.Sources.Flush()
        I.Fold(92)
        local withExpectation = R.est0[slot]
        I.Sources.Stage(VS.Obs.Swing, 90, 1, 0, 1) -- its credit after all (a retraction's re-open, then its wound)
        I.Sources.Flush()
        I.Fold(92.1)
        local credit = I.SwingValue(slot, 1, 90) * R.scale[slot]
        assert.is_true(R.est0[slot] <= withExpectation + credit + 1e-9)
        assert.is_true(R.est0[slot] >= withExpectation - 1e-9) -- the credit replaced the smaller expectation
    end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/State/resources_spec.lua`
Expected: FAIL on the first new case: `rise 0.00`.

- [ ] **Step 3: Rows stages it.** In `src/Hekili/Game/Events/Rows.lua`, replace `T.onExpire` with:

```lua
-- A swing closing unpaid: SWING_MISSED for a provisional avoid, else SWING_DAMAGE 0 (the swing timer reads it) and,
-- pinned to a unit, "no row of its own came" for the belief (Task 9b: its expected rage, Families/Resources.lua).
T.onExpire = function(i)
    if T.kind[i] ~= MELEE then
        return
    end
    emit(MELEE, T.x[i], T.guid[i], T.avoid[i] ~= "" and T.avoid[i] or "WOUND", "", 0, T.at[i], 1)
    if T.avoid[i] == "" and T.guid[i] ~= "" and T.owed[i] > 0 then
        S.Stage(Obs.Swing, T.at[i], T.x[i], 0, 5)
    end
end
```

- [ ] **Step 4: Resources adds and retracts it.** In `src/Hekili/Game/State/Families/Resources.lua`, beside
  `local hitRate, HIT_ALPHA = ...` (line 133) add:

```lua
-- Per hand: the latest uncredited swing's expected rage (Task 9b): its swing time, its amount and its slot (0 none).
local expT, expV, expR = { 0, 0 }, { 0, 0 }, { 0, 0 }
```

  In the `Obs.Swing` handler, after the `elseif c == 4 then ... return` branch, add:

```lua
    elseif c == 5 then -- a swing's window closed with no row of its own: its expected rage, on est and hi only
        for r = 1, R.n do
            if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
                local v = hitRate[hand] * I.SwingValue(r, hand, o.t) * R.scale[r]
                if v > 0 then
                    local max = R.max[r]
                    R.est0[r], R.hi0[r] = clamp(R.est0[r] + v, max), clamp(R.hi0[r] + v, max)
                    norm(r)
                    expT[hand], expV[hand], expR[hand] = o.t, v, r
                    I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
                end
                break
            end
        end
        return
```

  and at the start of the `elseif c == 1 then` branch add:

```lua
        if expR[hand] > 0 and o.t == expT[hand] then -- credited after all: the expectation comes back out first
            local r = expR[hand]
            R.est0[r], R.hi0[r] = R.est0[r] - expV[hand], R.hi0[r] - expV[hand]
            norm(r)
            expR[hand] = 0
        end
```

  and in the combat-end hook add `expR[1], expR[2] = 0, 0`.

- [ ] **Step 5: Run it, then the rage gates**

Run: `.lua/bin/busted tests/Game/State/resources_spec.lua && make test-fast`
Expected: PASS, 0 failures.

Run: `.lua/bin/busted --tags=slow tests/Game/harness/solo_spec.lua tests/Game/harness/group_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/flicker_spec.lua && make test-loop`
Expected: PASS; `over`, the drift (err mean and max) and `danger` at or better than Task 9's run. Report every
number that moved, either way, in the commit message; a move down stops the task for the owner.

- [ ] **Step 6: Commit**

```bash
git add src/Hekili/Game/Events/Rows.lua src/Hekili/Game/State/Families/Resources.lua \
  tests/Game/State/resources_spec.lua
git commit -m "feat(resources): an uncredited swing adds its expected rage to est and hi, never to lo

<the rage metrics before -> after: over, err mean/max, danger, per gate>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

(The angle-bracket line is the run's own numbers, one line per gate.)

---

### Task 10: Harness corrections: observer, world and the scenario knobs for K1-K20

**Files:**
- Modify: `tests/Game/harness/world.lua:94-113` (`W.emit`'s kill marks the killing wound), `:306-312`
  (`W.endCasts(e, cause)`), `:571-581` (`W.dot` with school, key, castT and jitter), after `:619` (`W.hitAt`)
- Modify: `tests/Game/harness/observer.lua:10-43` (knobs), `:44-47` (`M.SPELLS`), `:122-188` (`push`, `tokensOf`,
  `outcome`, `targets`), `:340-345` (the swing branch keeps its order), `:437-453` (`kill`), `:454-500`
  (`cast`, `castStart`, `castStop`), new branches `refused`, `plateOff`, `plateOn`, `:637-660` (`step` copies `castT`)
- Modify: `tests/Game/harness/behaviours.lua` (new `M.ours`; `M.melee`'s `p.noSwing`)
- Modify: `tests/Game/harness/scenarios.lua:13-36` (archetypes `lockstep`, `cleave`), `:59-185` (knobs `noMelee`,
  `spells`, `churn`, `switchTo`, `extraMobs`, `actionTargeting`, `pushback`, `jitter`)
- Modify: `tests/Game/harness/replay.lua:696`, `:709`, `:721`, `:760` (a spell outcome's school from the content)
- Modify: `tests/Game/harness/drive.lua:59-68` (captures `payAt`, `payKind`, `staged`), `:120-138` (`Stage` wrapper),
  the `T.onPay` hook
- Modify: `tests/Game/harness/press_spec.lua:342-354` (`casts()` skips SENT), `:459-466` (the death shape)
- Test: `tests/Game/harness/observer_spec.lua` (cases added)

**Interfaces:**
- Consumes: the fake spec's expect abilities (Task 4), `I.Tickets.onPay` (Task 6).
- Produces: stream field `s.castT[i]` (the success an own spell outcome belongs to; 0 otherwise);
  `observer.DEFAULTS.actionTargeting` (false), `.pushback` (false), `.killTiming` (`{ died = 0.002,
  meleeClear = 0.100, flightClear = 0.002, flightRow = 0.020, strikeClear = 0.100 }`, the measured kill shapes),
  `.killTokens` (`{ melee = { "softinteract" }, flight = { "plate", "target", "softinteract" } }`);
  `observer.SPELLS.INSTANT/BOLT/DOTI/TICKS/NONE/BOGUS/CHAN/POTION`; `W.hit(e, dst, amount, school, set, castT,
  flight)`; `W.hitAt(e, dst, amount, school, set, delay, castT)`; a kill truth event carries `cause` (the event that
  killed); `W.dot(e, dst, every, n, amount, school, key, castT)`; `W.endCasts(e, cause)` (`"death"` default,
  `"move"`); `behaviours.ours(p)` with `p.spells = { { t, kind } }`, kinds `instant`, `bolt`, `doti`, `ticks`, `none`,
  `bogus`, `unmapped`, `refused`, `aoe`, `chan`; scenario knobs above; drive captures `c.payAt[i]`, `c.payKind[i]`,
  `c.staged[i]` (1 Crit, 2 Avoided).
- Boundary: harness only; no content name (the boundary scans `tests/Game/harness/**`).

Implementation choices: the DELAYED pushback row (spec §6.1 row 5) is opt-in (`pushback`), because it moves the
player's `UNIT_COMBAT` 0.37 s later and would shift the existing onus floors; the detection suite turns it on. Kills
follow the measured shape per kind, each number a knob defaulting to the captures (spec §2.5, §6.1 row 7): a
white-swing kill is the server's at the swing, so the world now applies our swing's damage at the swing (it applied it
at the landing, `world.lua:94`; rage was already at the swing), `PARTY_KILL` at the swing, `UNIT_DIED` and
`PLAYER_TARGET_DIED` 2 ms later, the clear 100 ms after the swing, and the killing row at the landing lag (about 450 ms,
up to 990 ms in K10's sessions) on `softinteract` only, so about 370 ms after the clear; a projectile kill clears 2 ms
after the death and its row comes 20 ms after the clear (11-36 ms measured) on the plate, `target` and
`softinteract`; an instant kill's row comes in its frame on the usual tokens and the clear 100 ms after it. Our white
kills therefore end each loop fight a landing lag earlier than before: the named cause for any loop number it moves
(Task 18). Every player cast event (SENT, START, SUCCEEDED, STOP, FAILED, INTERRUPTED, DELAYED, CHANNEL_START) is
echoed on `targettarget` while our target targets us (captures b and c). Cast-event jitter is a non-negative delay (0-50 ms), because an incremental observer cannot push before a released step.

- [ ] **Step 1: Write the failing observer tests.** Append inside the top `describe` of
  `tests/Game/harness/observer_spec.lua`:

```lua
    describe("the 2026-10-22 client shapes (unit-registry spec §6.1)", function()
        local world = require("Game.harness.world")
        local entities = require("Game.harness.entities")
        local function fight(build, k)
            local W = world.new(1)
            local us = W.add(entities.new({ guid = "Player-1", weapons = entities.weapons(22) }))
            local mob = W.add(entities.new({ guid = "Creature-1", kind = "mob", health = 1e9 }))
            us.target, mob.target = mob, us
            mob.avoid = { miss = 0, dodge = 0, parry = 0, block = 0 } -- every hit lands: the shapes, not the rolls
            build(W, us, mob)
            W.run(30)
            local s = observer.observe(W, setmetatable(k or {}, { __index = observer.DEFAULTS }))
            local out = {}
            for i = 1, s.n do
                if s.ev[i]:sub(1, 1) ~= "@" then
                    out[#out + 1] = { t = s.t[i], ev = s.ev[i], a1 = s.a1[i], a2 = s.a2[i], a3 = s.a3[i], a4 = s.a4[i],
                        a5 = s.a5[i], castT = s.castT[i] }
                end
            end
            return out
        end
        local function find(out, ev, a1)
            for _, e in ipairs(out) do
                if e.ev == ev and (a1 == nil or e.a1 == a1) then
                    return e
                end
            end
        end

        it("sends SENT before a hard cast's START, with castBarIDs, echoed on targettarget", function()
            local out = fight(function(W, us)
                W.at(1, function()
                    W.press(us, "spender_p", { spell = "BOLT", cast = 1.5 })
                end)
            end)
            local sent, start = find(out, "UNIT_SPELLCAST_SENT", "player"), find(out, "UNIT_SPELLCAST_START", "player")
            assert.is_true(sent.t <= start.t and sent.a3 == start.a2)
            assert.is_truthy(tostring(start.a4):match("^Bar%-"))
            assert.is_truthy(find(out, "UNIT_SPELLCAST_START", "targettarget"))
        end)

        it("lands a projectile distance / velocity after its success, with its school and its castT", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.hitAt(us, mob, 15, 8, "spell", 1.5, 1)
                end)
            end)
            local row = find(out, "UNIT_COMBAT", "target")
            assert.are.same({ 2.5, 8, 1 }, { row.t, row.a5, row.castT })
        end)

        it("ticks a DoT in its school at its period from the application; a recast resets the schedule", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.dot(us, mob, 3, 4, 4, 64, "doti", 1)
                end)
                W.at(5, function()
                    W.dot(us, mob, 3, 4, 4, 64, "doti", 5)
                end)
            end)
            local ticks = {}
            for _, e in ipairs(out) do
                if e.ev == "UNIT_COMBAT" and e.a1 == "target" then
                    ticks[#ticks + 1] = math.floor(e.t + 0.5)
                    assert.are.equal(64, e.a5)
                end
            end
            assert.are.same({ 4, 8, 11, 14, 17 }, ticks) -- the first schedule's 7 never comes
        end)

        local function kill(out)
            return find(out, "PARTY_KILL"), find(out, "UNIT_DIED"), find(out, "PLAYER_TARGET_CHANGED"),
                find(out, "UNIT_COMBAT")
        end

        it("kills by a white swing as measured: death at the swing, the clear 100 ms on, the row on the corpse later", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    local sw = W.emit({ kind = "swing", src = us, dst = mob, hand = 1, act = "WOUND", flag = "",
                        amount = 2e9, school = 1, ours = true })
                    W.at(1.456, function()
                        W.emit({ kind = "land", src = us, dst = mob, hand = 1, act = "WOUND", flag = "",
                            amount = 2e9, school = 1, swing = sw })
                    end)
                end)
            end)
            local pk, died, clear, row = kill(out)
            assert.are.same({ "Player-1", "Creature-1", 1 }, { pk.a1, pk.a2, pk.t })
            assert.is_true(math.abs(died.t - 1.002) < 1e-9 and math.abs(clear.t - 1.1) < 1e-9)
            assert.are.same({ 1.456, "softinteract" }, { row.t, row.a1 }) -- 356 ms after the clear, the corpse only
        end)

        it("kills by a projectile: the clear, then the row 20 ms later on the plate, target and softinteract", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.hitAt(us, mob, 2e9, 8, "spell", 1.5, 1)
                end)
            end)
            local _, died, clear, row = kill(out)
            assert.is_true(died.t < clear.t and clear.t < row.t and math.abs(row.t - clear.t - 0.02) < 1e-9)
            assert.are.equal("nameplate1", row.a1)
        end)

        it("kills by an instant: its row in its frame, the clear 100 ms after it", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.emit({ kind = "spell", src = us, dst = mob, act = "WOUND", flag = "", amount = 2e9, school = 1 })
                end)
            end)
            local _, _, clear, row = kill(out)
            assert.is_true(row.t < clear.t and math.abs(clear.t - row.t - 0.1) < 1e-9)
        end)

        it("echoes every player cast event on targettarget while our target targets us", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.press(us, "spender_p", { spell = "BOLT", cast = 1.5 })
                end)
                W.at(2, function()
                    W.endCasts(us)
                end)
                W.at(3, function()
                    W.emit({ kind = "refused", src = us, spell = "BOLT" })
                end)
            end)
            for _, ev in ipairs({ "SENT", "START", "FAILED", "STOP", "INTERRUPTED" }) do
                assert.is_truthy(find(out, "UNIT_SPELLCAST_" .. ev, "targettarget"), ev)
            end
        end)

        it("stops a cast at a death with FAILED then STOP, then three INTERRUPTED with no castBarID", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.press(us, "spender_p", { spell = "BOLT", cast = 1.5 })
                end)
                W.at(2, function()
                    W.endCasts(us)
                end)
            end)
            local f, st = find(out, "UNIT_SPELLCAST_FAILED", "player"), find(out, "UNIT_SPELLCAST_STOP", "player")
            assert.are.equal(f.t, st.t)
            local n = 0
            for _, e in ipairs(out) do
                if e.ev == "UNIT_SPELLCAST_INTERRUPTED" and e.a1 == "player" then
                    n = n + 1
                    assert.is_nil(e.a5)
                end
            end
            assert.are.equal(3, n)
        end)

        it("churns a plate: removed while it still answers, re-added within the gap", function()
            local out = fight(function(W, us, mob)
                W.at(3, function()
                    W.emit({ kind = "plateOff", mob = mob })
                end)
                W.at(3.4, function()
                    W.emit({ kind = "plateOn", mob = mob })
                end)
            end)
            local off, on = find(out, "NAME_PLATE_UNIT_REMOVED"), find(out, "NAME_PLATE_UNIT_ADDED", "nameplate1")
            assert.are.same({ 3, "nameplate1" }, { off.t, off.a1 })
            assert.is_truthy(on)
        end)

        it("fans an outcome out to softenemy with Action Targeting on", function()
            local out = fight(function(W, us, mob)
                W.at(1, function()
                    W.hit(us, mob, 10, 1)
                end)
            end, { actionTargeting = true })
            assert.is_truthy(find(out, "UNIT_COMBAT", "softenemy"))
        end)
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/harness/observer_spec.lua`
Expected: FAIL, `attempt to call field 'hitAt' (a nil value)`, `attempt to index field 'castT' (a nil value)`, and
the missing SENT / PARTY_KILL / FAILED rows.

- [ ] **Step 3: World.** In `tests/Game/harness/world.lua`:

In `W.emit`, change the health condition (line 94) from
`if ev.act == "WOUND" and ev.dst and (ev.kind ~= "swing" or not ev.ours) then -- ours take it at \`land\``
to

```lua
        if ev.act == "WOUND" and ev.dst and ev.kind ~= "land" then -- ours take it at the swing: the server's hit
            -- (a white-swing kill clears the target before its row arrives, the Rogue kill-events capture)
```

inside `if v.health <= 0 and not v.dead then` (line 98), before `v.dead, W.killAt = true, W.t`, add
`ev.killing = true -- the observer shapes this outcome by kind (unit-registry spec §6.1 row 7)`, and change
`W.emit({ kind = "kill", dst = v })` to `W.emit({ kind = "kill", dst = v, src = ev.src, cause = ev })`.

Replace `W.endCasts` (lines 306-312) with:

```lua
    function W.endCasts(e, cause)
        if e.hardSpell then
            W.emit({ kind = "castStop", src = e, spell = e.hardSpell, cause = cause or "death" })
            e.hardSpell, e.castUntil = nil, W.t
        end
        W.stopChannel(e)
    end
```

Replace `W.dot` (lines 571-581) with:

```lua
    --- `n` ticks of `amount` in `school` [1] from `e` on `dst`, every `every` s from now, each +-50 ms (W.crng; the
    --- druid-moonfire capture); `key` names the schedule: a new one with the same key on `dst` ends the old (a recast
    --- resets it); `castT` the success it belongs to (the detection suite's truth). A kill stops it.
    function W.dot(e, dst, every, n, amount, school, key, castT)
        local mark = {}
        if key then
            dst.dots = dst.dots or {}
            dst.dots[key] = mark
        end
        for k = 1, n do
            W.at(W.t + k * every + (W.crng.next() - 0.5) * 0.1, function()
                if not dst.dead and (not key or dst.dots[key] == mark) then
                    W.emit({ kind = "tick", src = e, dst = dst, act = "WOUND", flag = "", amount = amount,
                        school = school or 1, castT = castT })
                end
            end)
        end
    end
```

`W.hit` takes two more arguments, `castT` (the success the outcome belongs to) and `flight` (a projectile's landing),
set on the event before it is emitted so a kill's `cause` carries them: its signature becomes
`function W.hit(e, dst, amount, school, set, castT, flight)` and its emit (line 615) becomes

```lua
        e.lastHit = W.emit({ kind = "spell", src = e, dst = dst, act = act, flag = flag, amount = amt,
            school = act == "WOUND" and school or 1, castT = castT, flight = flight }) -- a spell miss is school 1
```

  After `W.hit` (line 619) add:

```lua
    --- A projectile of `e`'s landing `delay` s from now (distance / velocity): W.hit's outcome then, carrying `castT`
    --- (its success). A target dead by then takes nothing.
    function W.hitAt(e, dst, amount, school, set, delay, castT)
        W.at(W.t + delay, function()
            if not dst.dead then
                W.hit(e, dst, amount, school, set, castT, true)
            end
        end)
    end
```

- [ ] **Step 4: Observer.** In `tests/Game/harness/observer.lua`:

Add to `M.DEFAULTS` (before its closing brace):

```lua
    -- 2026-10-22 captures (unit-registry spec §6.1): Action Targeting off by default (softenemy then never fires);
    -- the DELAYED pushback row is opt-in (it moves the player's UNIT_COMBAT 0.37 s later).
    actionTargeting = false,
    pushback = false,
    -- A kill's shape by kind (s, from the kill truth; spec §2.5): the death events after the blow; a white swing's
    -- clear after its swing (its row comes at the landing lag, on the corpse); a projectile's clear after the death and
    -- its row after the clear (11-36 ms measured); an instant's clear after its row.
    killTiming = { died = 0.002, meleeClear = 0.100, flightClear = 0.002, flightRow = 0.020, strikeClear = 0.100 },
    killTokens = { melee = { "softinteract" }, flight = { "plate", "target", "softinteract" } },
```

Replace `M.SPELLS` (line 46) with:

```lua
M.SPELLS = {
    STRIKE = fs.SPENDER_B,
    DOT = fs.SPENDER_C,
    CAST = fs.SPENDER_A,
    OTHER = 1,
    INSTANT = fs.SPENDER_F,
    BOLT = fs.SPENDER_P,
    DOTI = fs.SPENDER_M,
    TICKS = fs.SPENDER_S,
    NONE = fs.SPENDER_N,
    BOGUS = fs.SPENDER_Q,
    CHAN = fs.SPENDER_H,
    POTION = 999999, -- no ability's: an unmapped success
}
```

In `M.new`, change the stream's fields line to
`s.src, s.hand, s.swingT, s.actor, s.castT = {}, {}, {}, {}, {}` and `push` to:

```lua
    local function push(t, ev, a1, a2, a3, a4, a5, src, hand, swingT, actor, castT)
        seq = seq + 1
        list[#list + 1] =
            { t, seq, ev, a1, a2, a3, a4, a5, src or 0, hand or 0, swingT or 0, actor or 0, castT or 0 }
    end
```

In `tokensOf`, inside `elseif v == ev.ourTarget then`, after its loop add:

```lua
            if k.actionTargeting then
                out[#out + 1] = "softenemy"
            end
```

Replace `outcome` with:

```lua
    local castOpen = false -- our hard cast in progress (DELAYED, pushback)
    -- One player cast event, echoed on targettarget (another castBarID) while our target targets us: every kind of
    -- them (captures b and c: SENT, START, SUCCEEDED, STOP, FAILED, INTERRUPTED, DELAYED).
    local function castEv(t, onUs, name, g, id, a4, a5)
        push(t, name, "player", g, id, a4, a5)
        if onUs then
            push(t, name, "targettarget", g, id, a4 and (a4 .. "-tt") or nil, a5 and (a5 .. "-tt") or nil)
        end
    end
    local function sent(t, onUs, g, id)
        push(t, "UNIT_SPELLCAST_SENT", "player", "Mob", g, id)
        if onUs then
            push(t, "UNIT_SPELLCAST_SENT", "targettarget", "Mob", g, id)
        end
    end
    -- The tokens and time of a killing outcome (killTiming, killTokens); nil: the usual ones (an instant's).
    local function killShape(t, ev)
        local sw = ev.swing
        local kt = k.killTiming
        local list
        if ev.kind == "land" and sw and sw.killing then
            list = k.killTokens.melee -- at the landing lag, after the clear: the corpse only
        elseif ev.killing and ev.flight then
            t, list = t + kt.died + kt.flightClear + kt.flightRow, k.killTokens.flight
        end
        if not list then
            return nil
        end
        local toks = {}
        for _, tok in ipairs(list) do
            toks[#toks + 1] = tok == "plate" and plate[ev.dst] or tok
        end
        return t, toks
    end
    local function outcome(t, ev, src, hand, swingT)
        local toks = tokensOf(ev.dst, ev)
        local kt, ktoks = killShape(t, ev)
        if kt then
            t, toks = kt, ktoks
        end
        if ev.dst == us and castOpen and k.pushback and ev.act == "WOUND" then
            castEv(t, ev.onUs, "UNIT_SPELLCAST_DELAYED", "Cast-" .. hardN, spellID(castSpell), "Bar-" .. hardN)
            t = t + 0.37 -- the player's row comes about 0.37 s after DELAYED (capture b)
        end
        for _, tok in ipairs(toks) do
            push(t, "UNIT_COMBAT", tok, ev.act, ev.flag or "", ev.amount or 0, ev.school or 1, src, hand, swingT,
                idx[ev.src], ev.castT)
        end
    end
```

  (`outcome` now reads `hardN`, `castSpell` and `spellID` as upvalues: move `local function spellID(name) ... end`
  (line 275) and the line `local hardN, chanN = 0, 0` (line 318, now `local hardN, chanN, castSpell = 0, 0, nil`) above
  `tokensOf`, so they are in scope.) In `targets`, after the `push(t, "@guid", "target", tgt and tgt.guid)` line, add:

```lua
        if k.actionTargeting then
            push(t, "@guid", "softenemy", tgt and tgt.guid)
        end
```

Replace the `kind == "kill"` branch with:

```lua
        elseif kind == "kill" then -- 2026-10-22 kill-events capture: PARTY_KILL with the blow when ours; UNIT_DIED and
            -- PLAYER_TARGET_DIED `died` later; the clear by kind (killTiming); the corpse answers softinteract
            local kt, c = k.killTiming, ev.cause or {}
            local clear = t + kt.strikeClear -- an instant's (its row came in its frame)
            if c.kind == "swing" then
                clear = t + kt.meleeClear
            elseif c.flight then
                clear = t + kt.died + kt.flightClear
            end
            if ev.src == us then
                push(t, "PARTY_KILL", us.guid, ev.dst.guid)
            end
            push(t + kt.died, "UNIT_DIED", ev.dst.guid)
            if ev.dst == ev.ourTarget then
                push(t + kt.died, "PLAYER_TARGET_DIED")
                push(t + kt.died, "@dead", "target", true)
                push(clear, "@guid", "target", nil)
                push(clear, "@guid", "softinteract", ev.dst.guid)
                push(clear, "PLAYER_TARGET_CHANGED")
                push(clear, "UNIT_HEALTH", "target")
            end
            local left = false
            for _, e in ipairs(mobs) do
                left = left or (not e.dead and e.target == us)
            end
            if not left then -- after the killing row (Rogue capture: about 1 s after the kill)
                push(t + 1.0, "@combat", false)
                combat(t + 1.0, false)
                if not k.plain then
                    push(t + 1.0, "@auraError", "target", false)
                end
                push(t + 1.0, "PLAYER_REGEN_ENABLED")
            end
```

Replace the `cast` (ours), `castStart` and `castStop` branches with:

```lua
        elseif kind == "cast" and ev.src == us then -- others' secret (G 49873)
            castN = castN + 1
            local gcdFirst = ev.gcd and k.gcdSpell and ev.order == 2
            if gcdFirst then
                cooldown(t, k.gcdSpell, ev.gcd)
            end
            local guid, bar, id = "Cast-" .. castN, nil, spellID(ev.spell)
            local tc = t + (ev.jitter or 0) -- cast-event latency (K10), recorded on the truth by the behaviour
            if ev.hard then -- the start's castGUID; UnitCastingInfo answers nothing from the success on
                castN, guid, bar, castOpen = castN - 1, "Cast-" .. hardN, "Bar-" .. hardN, false
                push(tc, "@casting", nil)
            elseif ev.chanEnds then
                chanN = castN
                sent(tc, ev.onUs, guid, id)
                push(tc, "@channel", t * 1000, ev.chanEnds * 1000)
                castEv(tc, ev.onUs, "UNIT_SPELLCAST_CHANNEL_START", guid, id)
            else
                sent(tc, ev.onUs, guid, id) -- an instant's SENT, the same ms
            end
            castEv(tc, ev.onUs, "UNIT_SPELLCAST_SUCCEEDED", guid, id, bar)
            if (ev.cd or 0) > 0 then
                for _, rid in ipairs(ev.ids or { id }) do
                    cooldown(t, rid, ev.cd)
                end
            end
            if ev.gcd and k.gcdSpell and not gcdFirst then
                cooldown(t, k.gcdSpell, ev.gcd)
            end
            if ev.hard then
                castEv(tc, ev.onUs, "UNIT_SPELLCAST_STOP", guid, id, bar)
            end
        elseif kind == "castStart" and ev.src == us then -- our hard cast: SENT, UnitCastingInfo, START, the GCD
            castN = castN + 1
            hardN, castSpell, castOpen = castN, ev.spell, true
            local g, id, bar = "Cast-" .. castN, spellID(ev.spell), "Bar-" .. castN
            sent(t, ev.onUs, g, id)
            push(t, "@casting", t * 1000, ev.ends * 1000)
            castEv(t, ev.onUs, "UNIT_SPELLCAST_START", g, id, bar)
            if ev.gcd and k.gcdSpell then
                cooldown(t, k.gcdSpell, ev.gcd)
            end
        elseif kind == "castStop" and ev.src == us then -- capture b: a death is FAILED then STOP in one ms, then three
            -- INTERRUPTED with no castBarID 0.15 s later; a move is INTERRUPTED (castBarID 5th), STOP 1 ms later, then two;
            -- each echoed on targettarget while our target targets us
            local g, id, bar = "Cast-" .. hardN, spellID(ev.spell), "Bar-" .. hardN
            castOpen = false
            push(t, "@casting", nil)
            if ev.cause == "move" then
                castEv(t, ev.onUs, "UNIT_SPELLCAST_INTERRUPTED", g, id, nil, bar)
                castEv(t + 0.001, ev.onUs, "UNIT_SPELLCAST_STOP", g, id, bar)
                for _ = 1, 2 do
                    castEv(t + 0.15, ev.onUs, "UNIT_SPELLCAST_INTERRUPTED", g, id, nil, nil)
                end
            else
                castEv(t, ev.onUs, "UNIT_SPELLCAST_FAILED", g, id, bar)
                castEv(t, ev.onUs, "UNIT_SPELLCAST_STOP", g, id, bar)
                for _ = 1, 3 do
                    castEv(t + 0.15, ev.onUs, "UNIT_SPELLCAST_INTERRUPTED", g, id, nil, nil)
                end
            end
        elseif kind == "refused" and ev.src == us then -- a cast refused at its start (range, line of sight): K15
            castN = castN + 1
            local g, id = "Cast-" .. castN, spellID(ev.spell)
            sent(t, ev.onUs, g, id)
            castEv(t, ev.onUs, "UNIT_SPELLCAST_FAILED", g, id, nil)
        elseif kind == "plateOff" then -- soft-targeting log: the removal still answers the GUID; the plate goes after
            push(t, "NAME_PLATE_UNIT_REMOVED", plate[ev.mob])
            push(t + 0.001, "@guid", plate[ev.mob], nil)
        elseif kind == "plateOn" then
            push(t, "@guid", plate[ev.mob], ev.mob.guid)
            push(t, "NAME_PLATE_UNIT_ADDED", plate[ev.mob])
```

In `obs.step`, the copy loop's second line becomes
`s.src[i], s.hand[i], s.swingT[i], s.actor[i], s.castT[i] = e[9], e[10], e[11], e[12], e[13]`.

- [ ] **Step 5: Behaviours.** In `tests/Game/harness/behaviours.lua`, in `M.melee`'s per-hand loop, wrap the first
  scheduling so `p.noSwing` skips our swings: replace
  `W.at(W.t + (p.phase and p.phase[h] or W.rng.next() * e.weapons[h][3]), swing)` with

```lua
            if not p.noSwing then
                W.at(W.t + (p.phase and p.phase[h] or W.rng.next() * e.weapons[h][3]), swing)
            end
```

  and add before `--- A caster:`:

```lua
--- Our scripted spells (the detection suite, unit-registry spec §6.2), as the fake spec's expect abilities:
--- `p.spells` { { t, kind } }: "instant" (fire 30-40 at once), "bolt" (a 1.5 s cast of nature 14-18 landing
--- `p.distance` / 20 s after its success), "doti" (arcane 8-9 at once, then 4 ticks of 4 every 3 s), "ticks" (5 ticks of
--- 6 every 3 s after a `p.distance` / 40 s flight; its miss arrives then), "none", "bogus" (an instant on its
--- default type), "unmapped" (a success no ability maps), "refused" (SENT then FAILED: no success), "aoe" (an
--- instant on our target and every other mob with a plate), "chan" (a 3 s channel ticking arcane 5 every 1 s).
--- `p.distance` yards [20]; `p.jitter` the cast events' extra latency bound [0] (W.crng, on the truth).
function M.ours(p)
    local KEYS = {
        instant = { "spender_f", "INSTANT" },
        bolt = { "spender_p", "BOLT" },
        doti = { "spender_m", "DOTI" },
        ticks = { "spender_s", "TICKS" },
        none = { "spender_n", "NONE" },
        bogus = { "spender_q", "BOGUS" },
        aoe = { "spender_f", "INSTANT" },
        chan = { "spender_h", "CHAN" },
    }
    return function(W, e)
        local d = p.distance or 20
        local function effect(kind)
            return function(W2, me)
                local tgt, t0 = me.target, W2.t
                if not tgt then
                    return
                end
                if kind == "instant" or kind == "bogus" then
                    W2.hit(me, tgt, W2.rng.int(30, 40), 4, "spell", t0)
                elseif kind == "aoe" then
                    for _, m in ipairs(W2.ents) do
                        if m.kind == "mob" and not m.dead and (m == tgt or m.plate) then
                            W2.hit(me, m, W2.rng.int(30, 40), 4, "spell", t0)
                        end
                    end
                elseif kind == "bolt" then
                    W2.hitAt(me, tgt, W2.rng.int(14, 18), 8, "spell", d / 20, t0)
                elseif kind == "doti" then
                    local ev = W2.hit(me, tgt, W2.rng.int(8, 9), 64, "spell", t0)
                    if ev.act == "WOUND" then
                        W2.dot(me, tgt, 3, 4, 4, 64, "doti", t0)
                    end
                elseif kind == "ticks" then
                    W2.at(t0 + d / 40, function()
                        local act = W2.rollOutcome(tgt, "spell")
                        if act ~= "WOUND" then
                            W2.emit({ kind = "spell", src = me, dst = tgt, act = act, flag = "", amount = 0, school = 1,
                                castT = t0 })
                        else
                            W2.dot(me, tgt, 3, 5, 6, 8, "ticks", t0)
                        end
                    end)
                end
            end
        end
        for _, sp in ipairs(p.spells or {}) do
            W.at(sp[1], function()
                local kind = sp[2]
                if e.stopped then
                    return
                elseif kind == "unmapped" then
                    W.emit({ kind = "cast", src = e, dst = e.target, spell = "POTION" })
                    return
                elseif kind == "refused" then
                    W.emit({ kind = "refused", src = e, spell = "BOLT" })
                    return
                end
                local key = KEYS[kind]
                local press = { spell = key[2], gcd = 1.5, effect = effect(kind) }
                if kind == "bolt" then
                    press.cast = 1.5
                elseif kind == "chan" then
                    press.channel = { length = 3, tick = 1, effect = function(W2, me)
                        if me.target then
                            W2.hit(me, me.target, 5, 64, "spell", W2.t)
                        end
                    end }
                    press.effect = nil
                end
                W.press(e, key[1], press)
                local last = W.truth[#W.truth]
                if p.jitter and last and last.kind == "cast" then
                    last.jitter = W.crng.next() * p.jitter
                end
            end)
        end
    end
end
```

- [ ] **Step 6: Scenarios.** In `tests/Game/harness/scenarios.lua`, add to `ARCHETYPES`:

```lua
    -- K13: a caster in lockstep with our bolt (nature, our amount band), phase-shifted by `W.phase` s
    lockstep = function(W, lvl)
        local e = entities.new({ level = lvl })
        return e, behaviours.caster({ every = 1.5, cast = 1.5 + (W.phase or 0), amount = { 14, 18 }, school = 8,
            resist = 0.05 })
    end,
    -- K18: a melee whose swings also hit the mob beside our target (a cleave)
    cleave = function(W, lvl)
        local w = entities.weapons(lvl)[1]
        local e = entities.new({ weapons = { { w[1], w[2], 2.4 } }, level = lvl })
        return e, behaviours.melee({ rates = { miss = 0.05, crit = 0.1 }, cleave = true })
    end,
```

  (`behaviours.melee`'s `p.cleave`: in its non-strike branch, after the `W.emit({ kind = "swing", ... })` for a
  foreign swing, add:

```lua
                    if p.cleave and not p.land then -- another player's cleave: the same hit on a second mob
                        for _, m in ipairs(W.ents) do
                            if m.kind == "mob" and m ~= tgt and not m.dead then
                                W.emit({ kind = "swing", src = e, dst = m, hand = h, act = act, flag = flag,
                                    amount = amt, school = 1, speed = w[3] })
                                break
                            end
                        end
                    end
```
  )

  In `M.world`: pass `noSwing = o.noMelee` into the `behaviours.melee({ ... })(W, us)` call; set `W.phase = o.phase`
  before the archetypes run; after `mobs[i] = mob` add `mob.plate = i > 1 and o.extraMobs ~= nil or nil`; change the
  attacker loop to `for i = 1, math.max(1, o.attackers or 1) + (o.extraMobs or 0) do` with
  `mob.target = (i <= (o.attackers or 1) and not (o.joinAt and o.joinAt[i])) and us or nil` unchanged; and add before
  `W.at(stop, ...)`:

```lua
    if o.spells then -- our scripted spells (the detection suite)
        W.at(pull, function()
            behaviours.ours({ spells = o.spells, distance = o.distance, jitter = o.jitter })(W, us)
        end)
    end
    for _, sw in ipairs(o.switchTo or {}) do -- { t, mob index }: our target changes (K5, K12, K19)
        W.at(sw[1], function()
            us.target = mobs[sw[2]]
            W.emit({ kind = "target" })
        end)
    end
    if o.churn then -- { every, gap }: our target's plate leaves and comes back (K7)
        for t = pull + o.churn[1], stop, o.churn[1] do
            W.at(t, function()
                W.emit({ kind = "plateOff", mob = mobs[1] })
            end)
            W.at(t + o.churn[2], function()
                W.emit({ kind = "plateOn", mob = mobs[1] })
            end)
        end
    end
```

  and in `M.stream`, extend `k` with `actionTargeting = o.actionTargeting, pushback = o.pushback`.

- [ ] **Step 7: Replay schools.** In `tests/Game/harness/replay.lua`, after `local function keyFor(e) ... end`
  (line 387) add:

```lua
    -- a spell outcome's school (unit-registry spec §6.1 row 6): the content's declared one; a miss is school 1 (fact 2)
    local SCHOOL = H.Hekili.SCHOOL or {}
    local function schoolOf(e)
        local key = e.id and keyFor(e)
        local a = key and class.abilities[key]
        return e.act == "WOUND" and a and SCHOOL[a.school] or 1
    end
```

  and change `school = 1,` to `school = schoolOf(e),` at line 721 (the non-swing hit) and line 760 (the tick); the
  swing lines 696 and 709 stay 1.

- [ ] **Step 8: Drive captures.** In `tests/Game/harness/drive.lua` `M.boot`, after the `c.crHand ...` arrays add:

```lua
    -- by stream index: the anchor and kind of the ticket a row paid (0 none), and what it staged (1 Crit, 2 Avoided)
    c.payAt, c.payKind, c.staged = {}, {}, {}
    for i = 1, CAP do
        c.payAt[i], c.payKind[i], c.staged[i] = 0, 0, 0
    end
    local T = c.I.Tickets
    T.onPay = function(i)
        local k = c.cur
        if k > 0 then
            c.payAt[k], c.payKind[k] = T.at[i], T.kind[i]
        end
    end
```

  In the `S.Stage` wrapper, before `return stage(kind, t, a, b, cc)`, add:

```lua
        if c.cur > 0 and (kind == c.VS.Obs.Crit or kind == c.VS.Obs.Avoided) then
            c.staged[c.cur] = kind == c.VS.Obs.Crit and 1 or 2
        end
```

  In `M.run`'s reset loop add `c.payAt[i], c.payKind[i], c.staged[i] = 0, 0, 0`.

- [ ] **Step 9: press_spec.** In `tests/Game/harness/press_spec.lua` `casts()` (line 346), change the condition to
  `if (ev:match("^UNIT_SPELLCAST") and ev ~= "UNIT_SPELLCAST_SENT" and s.a1[i] == "player") or ev == "@casting" or ev == "@channel" then`,
  and replace the expected list at lines 459-466 with:

```lua
        assert.are.same({
            "1.00 @casting 1000 2500 nil",
            "1.00 UNIT_SPELLCAST_START player Cast-1 " .. a,
            "2.00 @casting nil nil nil",
            "2.00 UNIT_SPELLCAST_FAILED player Cast-1 " .. a,
            "2.00 UNIT_SPELLCAST_STOP player Cast-1 " .. a,
            "2.00 UNIT_SPELLCAST_SUCCEEDED player Cast-2 " .. tostring(fs.SPENDER_B),
            "2.15 UNIT_SPELLCAST_INTERRUPTED player Cast-1 " .. a,
            "2.15 UNIT_SPELLCAST_INTERRUPTED player Cast-1 " .. a,
            "2.15 UNIT_SPELLCAST_INTERRUPTED player Cast-1 " .. a,
        }, casts())
```

- [ ] **Step 10: Run the observer tests and the whole harness**

Run: `.lua/bin/busted tests/Game/harness/observer_spec.lua tests/Game/harness/press_spec.lua tests/Game/harness/world_spec.lua && make test-fast`
Expected: PASS, 0 failures.

Run: `.lua/bin/busted --tags=slow tests/Game/harness/group_spec.lua tests/Game/harness/solo_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/alloc_spec.lua tests/Game/harness/flicker_spec.lua`
Expected: PASS. The kill shape changes the last row of each killing fight (now on the plate after the clear); a moved
number in `group_spec.lua` is reported with that named cause in the commit; a gate that fails stops the task.

- [ ] **Step 11: Commit**

```bash
git add tests/Game/harness/world.lua tests/Game/harness/observer.lua tests/Game/harness/behaviours.lua \
  tests/Game/harness/scenarios.lua tests/Game/harness/replay.lua tests/Game/harness/drive.lua \
  tests/Game/harness/press_spec.lua tests/Game/harness/observer_spec.lua
git commit -m "test(harness): the 2026-10-22 client shapes: SENT, castBarIDs, echoes, death, kill, flight, ticks, churn

Knobs for the detection suite: our scripted spells, switches, churn, Action Targeting, pushback, jitter, lockstep
and cleave partners; drive captures each row's paying ticket.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 11: Fixtures from the captures and their replay (K20)

**Files:**
- Modify: `tools/vslog_fixture.lua:1-28` (header and `parse`)
- Create: `tests/Game/harness/fixtures/capture_a.lua`, `capture_b.lua`, `capture_swap.lua`, `capture_strike.lua`,
  `capture_kill.lua`, `capture_ticks.lua` (generated, each with a header comment)
- Modify: `tests/Game/harness/drive.lua:417-457` (`M.fixtureStream`: the new row kinds and `extra` rows)
- Create: `tests/Game/harness/captures_spec.lua`
- Test: `tests/tools` stays green; `tests/Game/harness/fixtures_spec.lua` (unchanged: the old fixtures parse as
  before)

**Interfaces:**
- Consumes: Task 10's drive captures (`c.payAt`, `c.payKind`, `c.staged`), the fake expect abilities (Task 4), the
  registry and tickets (Tasks 2-9).
- Produces: fixture row kinds `{ ms, "SC", sub, unit, castGUID, spell, bar, a5 }` (`sub` SENT, START, STOP,
  SUCCEEDED, FAILED, INTERRUPTED, DELAYED; for SENT `bar` holds the target's name), `{ ms, "T", guid }` ("" none),
  `{ ms, "B", token, guid }` (a token's binding, inferred), `{ ms, "P+"|"P-", token, guid }`, `{ ms, "D", guid }`
  (UNIT_DIED), `{ ms, "K", killer, victim }` (PARTY_KILL; our GUID written `ME`), `{ ms, "TD" }`, `{ ms, "E", event }`;
  `drive.fixtureStream(fix, base, dedupe, extra)` (`extra`: fixture rows merged in by ms).
- Boundary: the fixture files are data (`tests/boundary_spec.lua` skips `fixtures/`); spells appear only as the fake
  spec's names (`BOLT`, `DOTI`, `HIT`), never IDs, outside the fixtures.

Implementation choices: the captures record no plate GUIDs before the 2026-10-22 recorder fix, so the tool infers each
plate and soft token's binding: a token row in the same ms as a `target` row of the same payload binds to the current
target (or, after a clear, to the target just cleared: the corpse); a lone token row keeps its binding, or takes the
corpse when it has none. A capture with no opening `TARGET` line gets `Creature-fixture-1`. The capture-a recorder
truncated every cast event to `UNIT_SPELLCA`; the tool decodes them by payload as the captures' README says (first
line of a castGUID: START; its next line at a later ms: SUCCEEDED, or FAILED when an INTERRUPTED of it follows within
0.3 s; the line after that: STOP). The druid-moonfire capture recorded no death events; its replay adds the kill-events
capture's measured `UNIT_DIED` 2 ms after the killing row (an `extra` row, named in the spec).

- [ ] **Step 1: Write the failing replay spec** `tests/Game/harness/captures_spec.lua`:

```lua
-- tests/Game/harness/captures_spec.lua (unit-registry spec §6.3, K20): every saved 2026-10-22 capture replayed through
-- the real sources (registry, tickets, rows) with its exact credits, so the suite is anchored on the game.
local drive = require("Game.harness.drive")
local fs = require("Game.State.helpers.fake_spec")

local BASE = 1

-- A booted VirtualState with the expect abilities, a 30 yd projectile, and (`stub`) the death events refused.
local function boot(stub)
    return drive.boot({
        boot = function(c)
            for _, e in ipairs(stub and { "UNIT_DIED", "PLAYER_TARGET_DIED", "PARTY_KILL" } or {}) do
                c.ctl.unknownEvents[e] = true
            end
            c.I.Build(fs.def(fs.new(9, false, false, true)), 0.1)
            c.VS.Start(c.api)
            c.I.ab.rMax[c.I.ab.bySpell[fs.SPENDER_P]] = 30
        end,
    })
end

local function replay(name, stub, extra, from)
    local fix = dofile("tests/Game/harness/fixtures/" .. name .. ".lua")
    if from then
        local rows = {}
        for _, r in ipairs(fix.rows) do
            if r[1] >= from or r[2] == "T" then -- the target lines keep their binding
                rows[#rows + 1] = r
            end
        end
        fix = { damage = fix.damage, rows = rows }
    end
    local c = boot(stub)
    local s = drive.fixtureStream(fix, BASE, false, extra)
    drive.run(c, s)
    drive.restore(c)
    return c, s
end

-- The stream index of the first non-player UNIT_COMBAT at `ms` with action `act` (and school `sch`).
local function at(s, ms, act, sch)
    for i = 1, s.n do
        if
            s.ev[i] == "UNIT_COMBAT"
            and math.abs(s.t[i] - (BASE + ms / 1000)) < 1e-6
            and s.a1[i] ~= "player"
            and s.a1[i] ~= "targettarget"
            and s.a2[i] == act
            and (sch == nil or s.a5[i] == sch)
        then
            return i
        end
    end
    error("no row at " .. ms)
end

-- The ticket that paid the outcome at `ms` (any of its tokens): its anchor and kind, else 0, 0.
local function paid(c, s, ms, act, sch)
    local i = at(s, ms, act, sch)
    for j = i, s.n do
        if s.t[j] ~= s.t[i] then
            break
        elseif c.payAt[j] > 0 then
            return c.payAt[j], c.payKind[j], c.staged[j]
        end
    end
    return 0, 0, 0
end

describe("the 2026-10-22 captures (K20)", function()
    it("b: every projectile landing pays its ticket; the late miss pays and is avoided; each kill tells", function()
        local c, s = replay("capture_b", true)
        local X = c.I.Expect
        local n = 0
        for i = 1, s.n do
            if s.ev[i] == "UNIT_COMBAT" and s.a2[i] == "WOUND" and s.a5[i] == 8 and c.payKind[i] == X.FLIGHT then
                n = n + 1
            end
        end
        assert.are.equal(14, n) -- 0 of 14 before (unit-registry spec §1 row 1)
        local _, kind, staged = paid(c, s, 71327, "MISS")
        assert.are.same({ X.FLIGHT, 2 }, { kind, staged })
        assert.are.equal(0, c.L.bg[7])
        assert.are.equal(3, c.I.Units.deaths.tell)
        local _, k2 = paid(c, s, 74805, "WOUND")
        assert.are.equal(X.FLIGHT, k2) -- on the plate and softinteract only, after the clear
    end)

    it("c-swap: the plate-only landing pays the cast pinned at SENT to the old mob; the post-clear row pays", function()
        local c, s = replay("capture_swap")
        local X = c.I.Expect
        local a, k = paid(c, s, 216184, "WOUND")
        assert.are.same({ BASE + 215818 / 1000, X.FLIGHT }, { a, k })
        local _, k2 = paid(c, s, 219922, "WOUND")
        assert.are.equal(X.FLIGHT, k2)
    end)

    it("a: the crit stages Crit; the late MISS is foreign once the GUID has a learned lag", function()
        local c, s = replay("capture_a")
        local _, _, staged = paid(c, s, 5367, "WOUND")
        assert.are.equal(1, staged)
        assert.are.equal(0, (paid(c, s, 97891, "MISS")))
    end)

    it("a: the same MISS pays the 97374 ticket under the first-ticket rule (no learned lag)", function()
        local c, s = replay("capture_a", false, nil, 97000)
        assert.are.equal(BASE + 97374 / 1000, (paid(c, s, 97891, "MISS")))
    end)

    it("rogue b: strikes pay their frames, the life-steal row is foreign, white hits pay their swings", function()
        local c, s = replay("capture_strike")
        local X = c.I.Expect
        local function pk(ms, sch)
            local a, k = paid(c, s, ms, "WOUND", sch)
            return { a, k }
        end
        assert.are.same({ BASE + 630 / 1000, X.FRAME }, pk(630))
        assert.are.same({ BASE + 2248 / 1000, X.FRAME }, pk(2250, 1))
        assert.are.same({ 0, 0 }, pk(2250, 32))
        assert.are.same({ BASE + 628 / 1000, X.MELEE }, pk(1617)) -- the first swing: 989 ms, teaches nothing
        assert.are.same({ BASE + 2250 / 1000, X.MELEE }, pk(2702))
        assert.are.same({ BASE + 3500 / 1000, X.FRAME }, pk(3501)) -- before the clear at 3602
    end)

    -- the post-clear white killing row (452 ms after the clear, on softinteract only) pays its swing
    it("rogue kill-events: the death events mark the unit ours; the corpse's row pays the killing swing", function()
        local c, s = replay("capture_kill")
        local X, U = c.I.Expect, c.I.Units
        local a, k = paid(c, s, 4820, "WOUND")
        assert.are.same({ BASE + 4364 / 1000, X.MELEE }, { a, k })
        assert.are.equal(0, (paid(c, s, 2765, "WOUND", 32)))
        local u = U.Find("Creature-0-6782-0-9-1508-AE12DF4C33")
        assert.is_true(U.IsDead(u) and U.Ours(u))
    end)

    it("druid moonfire: direct hits pay FRAME, ticks pay on schedule, a recast refreshes, the kill closes", function()
        local died = { { 21926, "D", "Creature-0-4621-1-7-2955-C057713E6D" } }
        local c, s = replay("capture_ticks", false, died)
        local X, T = c.I.Expect, c.I.Tickets
        for _, ms in ipairs({ 2000, 11788, 21924 }) do
            assert.are.equal(X.FRAME, select(2, paid(c, s, ms, "WOUND")))
        end
        for _, ms in ipairs({ 5036, 8020, 11070, 14755, 17722, 20755 }) do
            assert.are.equal(X.TICKS, select(2, paid(c, s, ms, "WOUND")), "tick at " .. ms)
        end
        assert.is_true(T.closed.refreshed >= 1 and T.closed.dead >= 1)
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/harness/captures_spec.lua`
Expected: FAIL, `cannot open tests/Game/harness/fixtures/capture_b.lua`.

- [ ] **Step 3: Extend the tool.** In `tools/vslog_fixture.lua`, replace the header's row list (lines 1-8) with:

```lua
-- tools/vslog_fixture.lua: turns a ForeverProbe /vslog dump (the in-game checkpoint's captures, combat harness design
-- §5; the 2026-10-22 captures, unit-registry spec §6.3) into a harness fixture (tests/Game/harness/fixtures/): every
-- token row kept, in ms since the first event; our spells as the fake spec's names (by the IDs given: STRIKE, DOT,
-- BOLT, DOTI, HIT; else OTHER), another player's (secret) as `SECRET`; a row that is not raw /vslog raises. Run from
-- the repository root:
--   lua5.1 tools/vslog_fixture.lua dump.txt "min,max,min,max" BOLT=<id> ... > tests/Game/harness/fixtures/x.lua
-- then write the fixture's header comment. Loaded with the argument "rows" (loadfile(...)("rows", text, ids)) it
-- returns the parsed rows instead, for the specs.
-- Rows: { ms, "S", duration, swingType }; { ms, "U", unit, action, flag, amount, school }; { ms, "C", unit, spell }
-- (the old recorder's UNIT_SPELLCAST_SUCCEEDED); { ms, "SC", sub, unit, castGUID, spell, bar, a5 } (SENT's `bar` is
-- the target's name); { ms, "T", guid } ("" none); { ms, "B", token, guid } (a plate or soft token's binding,
-- inferred: the captures record no plate GUID); { ms, "P+" | "P-", token, guid }; { ms, "D", guid } UNIT_DIED;
-- { ms, "K", killer, victim } PARTY_KILL (a player killer is ours: `ME`); { ms, "TD" }; { ms, "E", event }.
```

Replace `parse` (lines 10-28) with:

```lua
local EVENTS = {
    PLAYER_ENTER_COMBAT = true,
    PLAYER_LEAVE_COMBAT = true,
    PLAYER_REGEN_DISABLED = true,
    PLAYER_REGEN_ENABLED = true,
}
local SKIP = { NOTE = true, UNIT_TARGET = true, Recorder = true }

local function parse(text, ids)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        local p = {}
        for w in line:gmatch("%S+") do
            p[#p + 1] = w
        end
        p.line = line
        lines[#lines + 1] = p
    end
    local rows, target, corpse, bound, state = {}, "", nil, {}, {}
    local first = tonumber(lines[1] and lines[1][1])
    if first and lines[1][2] ~= "TARGET" then
        target = "Creature-fixture-1" -- a capture with no opening TARGET line
        rows[1] = { first, "T", target }
    end
    local function castFields(p)
        for k = 3, #p do
            if p[k]:match("^Cast%-") then
                return p[k], p[k + 1], p[k + 2], p[k + 3]
            end
        end
    end
    -- whether line n's ms holds a `target` UNIT_COMBAT row with the same payload
    local function withTarget(n)
        local p = lines[n]
        for m = n - 3, n + 3 do
            local q = lines[m]
            if q and q[1] == p[1] and q[2] == "UNIT_COMBAT" and q[3] == "target" and q[4] == p[4] and q[#q] == p[#p] then
                return true
            end
        end
        return false
    end
    for n, p in ipairs(lines) do
        local ms, ev = tonumber(p[1]), p[2]
        if not ms or SKIP[ev] then
            -- the dump's summary line, a note, a target-of change
        elseif ev == "PLAYER_SWING" then
            rows[#rows + 1] = { ms, "S", math.floor(tonumber(p[3]) * 10 + 0.5) / 10, tonumber(p[4]) }
        elseif ev == "UNIT_COMBAT" then
            local unit, flag, amount, school = p[3], "", p[5], p[6]
            if #p >= 7 then
                flag, amount, school = p[5], p[6], p[7]
            end
            assert(tonumber(amount) and tonumber(school), "not a raw /vslog row: " .. p.line)
            if unit:match("^nameplate") or unit:match("^soft") then
                local g
                if withTarget(n) then
                    g = target ~= "" and target or corpse
                else
                    g = bound[unit] or corpse or (target ~= "" and target or nil)
                end
                if g and bound[unit] ~= g then
                    bound[unit] = g
                    rows[#rows + 1] = { ms, "B", unit, g }
                end
            end
            rows[#rows + 1] = { ms, "U", unit, p[4], flag, tonumber(amount), tonumber(school) }
        elseif ev == "TARGET" then
            local g = p.line:match("guid=(%S+)") or ""
            if g == "" and target ~= "" then
                corpse = target
            end
            target = g
            rows[#rows + 1] = { ms, "T", g }
        elseif ev:match("^SC_") then
            local g, id, a4, a5 = castFields(p)
            local spell = ids[id] or "OTHER"
            if ev == "SC_SENT" then
                rows[#rows + 1] = { ms, "SC", "SENT", p[3], g, spell, p.line:match(p[3] .. " (.-) Cast%-") }
            else
                rows[#rows + 1] = { ms, "SC", ev:sub(4), p[3], g, spell, a4 ~= "nil" and a4 or false,
                    a5 ~= "nil" and a5 or false }
            end
        elseif ev == "UNIT_SPELLCA" then -- the truncated recorder: decoded by payload (captures README)
            local g, id, a4, a5 = castFields(p)
            local key, sub = p[3] .. g, nil
            if a4 == "nil" then
                sub = a5 == "nil" and "FAILED" or "INTERRUPTED"
            elseif not state[key] then
                sub, state[key] = "START", 1
            elseif state[key] == 1 then
                sub, state[key] = "SUCCEEDED", 2
                for m = n + 1, #lines do
                    local q = lines[m]
                    if tonumber(q[1]) and tonumber(q[1]) - ms > 300 then
                        break
                    elseif q[2] == "UNIT_SPELLCA" and q.line:find(g, 1, true) and q[#q - 1] == "nil" then
                        sub = "FAILED"
                    end
                end
            else
                sub, state[key] = "STOP", 3
            end
            rows[#rows + 1] = { ms, "SC", sub, p[3], g, ids[id] or "OTHER", a4 ~= "nil" and a4 or false,
                a5 ~= "nil" and a5 or false }
        elseif ev == "PLATE+" or ev == "PLATE-" then
            local g = p.line:match("guid=(%S+)")
            bound[p[3]] = ev == "PLATE+" and g or nil
            rows[#rows + 1] = { ms, ev == "PLATE+" and "P+" or "P-", p[3], g }
        elseif ev == "UNIT_DIED" then
            rows[#rows + 1] = { ms, "D", p[3] }
        elseif ev == "PARTY_KILL" then
            rows[#rows + 1] = { ms, "K", p[3]:match("^Player%-") and "ME" or p[3], p[4] }
        elseif ev == "PLAYER_TARGET_DIED" then
            rows[#rows + 1] = { ms, "TD" }
        elseif EVENTS[ev] then
            rows[#rows + 1] = { ms, "E", ev }
        elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then -- the first recorder's success line
            rows[#rows + 1] = { ms, "C", p[3], p[4] == "S" and "SECRET" or (ids[p[5]] or "OTHER") }
        else
            error("not a raw /vslog row: " .. p.line)
        end
    end
    return rows
end
```

  (The old `UNIT_SPELLCA` branch that emitted `"C"` rows is replaced by the decoding branch; the old fixtures are
  checked-in data and are not regenerated, so `fixtures_spec.lua` is unaffected.) In the printer, `cell` already
  quotes strings; it also writes `false` for the absent castBarIDs.

- [ ] **Step 4: Generate the six fixtures** (from the worktree root):

```bash
C=~/.claude/jobs/080a308e/tmp/captures
F=tests/Game/harness/fixtures
fixture() { # name, capture, header lines..., then the tool's arguments after --
    local name=$1 cap=$2; shift 2
    { while [ "$1" != "--" ]; do echo "-- $1"; shift; done; shift
      lua5.1 tools/vslog_fixture.lua "$C/$cap" "0,0,0,0" "$@"; } > "$F/$name.lua"
}
fixture capture_a wrath-5176-2026-10-22.log \
  "tests/Game/harness/fixtures/capture_a.lua: capture a of 2026-10-22 (captures README), solo, a Speed-20 nature" \
  "projectile hard cast (BOLT) at four mobs; cast events decoded from the truncated recorder; the 5367 CRITICAL and" \
  "the 97891 MISS (unit-registry spec §3.4's example). No TARGET line: the target is Creature-fixture-1." \
  -- BOLT=5176
fixture capture_b wrath-5176-2026-10-22-b.log \
  "tests/Game/harness/fixtures/capture_b.lua: capture b of 2026-10-22: 14 BOLT landings at max range, the 71327" \
  "spell MISS (school 1), three kills (FAILED then the clear), the 74805 killing blow on the plate and softinteract." \
  -- BOLT=5176
fixture capture_swap wrath-5176-2026-10-22-c-swap.log \
  "tests/Game/harness/fixtures/capture_swap.lua: capture c of 2026-10-22: a target swap at 215719 mid-cast; the" \
  "216184 landing on nameplate1 only; the 219922 post-clear killing row. No opening TARGET: Creature-fixture-1." \
  -- BOLT=5176
fixture capture_strike rogue-ss-2026-10-22-b.log \
  "tests/Game/harness/fixtures/capture_strike.lua: the second Rogue capture of 2026-10-22: instant strikes (HIT)," \
  "the first swing with PLAYER_ENTER_COMBAT in its ms (628), a school-32 life-steal row at 2250, an instant kill." \
  -- HIT=1752 HIT=2098
fixture capture_kill rogue-kill-events-2026-10-22.log \
  "tests/Game/harness/fixtures/capture_kill.lua: the Rogue kill-events capture of 2026-10-22: PARTY_KILL, UNIT_DIED," \
  "PLAYER_TARGET_DIED, the clear, a new target, the killing WOUND on softinteract 456 ms after its swing." \
  -- HIT=1752
fixture capture_ticks druid-moonfire-2026-10-22.log \
  "tests/Game/harness/fixtures/capture_ticks.lua: the druid DoT capture of 2026-10-22 (echoes trimmed): an arcane" \
  "instant with 3 s ticks (DOTI), a recast resetting the schedule, a kill by the direct hit (no death events recorded)." \
  -- DOTI=8921
```

  (`ids` maps an ID string to a name, so `HIT=1752 HIT=2098` maps both strikes to `HIT`.)

- [ ] **Step 5: Extend `drive.fixtureStream`.** Replace its doc comment and body (lines 417-457) with:

```lua
--- A fixture (fixtures/*.lua) as a stream: its rows from `base` seconds, the cache read out of combat first.
--- `dedupe`: one row per outcome on the target, fed as "target" (the old fixtures' research table). `extra`: fixture
--- rows merged in by ms (a measured event a capture did not record). Our casts as the fake spec's (STRIKE, DOT, BOLT,
--- DOTI, HIT), other spell IDs as 1; a secret ID as fake_api's SECRET; our GUID (`ME`) as the fake player's.
function M.fixtureStream(fix, base, dedupe, extra)
    local s = { n = 0, t = {}, ev = {}, a1 = {}, a2 = {}, a3 = {}, a4 = {}, a5 = {}, src = {}, hand = {}, swingT = {} }
    s.castT = {}
    local function push(t, ev, a1, a2, a3, a4, a5)
        local n = s.n + 1
        s.n = n
        s.t[n], s.ev[n], s.a1[n], s.a2[n], s.a3[n], s.a4[n], s.a5[n] = t, ev, a1, a2, a3, a4, a5
        s.src[n], s.hand[n], s.swingT[n], s.castT[n] = 0, 0, 0, 0
    end
    local d = fix.damage
    push(base - 1, "@damage", d[1], d[2], d[3], d[4])
    push(base - 1, "PLAYER_EQUIPMENT_CHANGED")
    local IDS = {
        STRIKE = fs.SPENDER_B,
        DOT = fs.SPENDER_C,
        HIT = fs.SPENDER_C,
        BOLT = fs.SPENDER_P,
        DOTI = fs.SPENDER_M,
        OTHER = 1,
        SECRET = fake.SECRET,
    }
    local TARGET_SIDE = { target = true, softenemy = true, softinteract = true }
    local rows = fix.rows
    if extra then
        rows = {}
        for _, r in ipairs(fix.rows) do
            rows[#rows + 1] = r
        end
        for _, r in ipairs(extra) do
            local k = #rows + 1
            while k > 1 and rows[k - 1][1] > r[1] do
                k = k - 1
            end
            table.insert(rows, k, r)
        end
    end
    local last = {}
    for _, r in ipairs(rows) do
        local t, kind = base + r[1] / 1000, r[2]
        if kind == "S" then
            push(t, "PLAYER_SWING", r[3], r[4])
        elseif kind == "C" then
            push(t, "UNIT_SPELLCAST_SUCCEEDED", r[3], r[4] == "SECRET" and fake.SECRET or "Cast", IDS[r[4]])
        elseif kind == "SC" then
            local sub, unit, g, id = r[3], r[4], r[5], IDS[r[6]]
            if sub == "SENT" then
                push(t, "UNIT_SPELLCAST_SENT", unit, r[7] or "Mob", g, id)
            else
                if unit == "player" and sub == "START" then
                    push(t, "@casting", t * 1000, t * 1000 + 1500)
                elseif unit == "player" and (sub == "SUCCEEDED" or sub == "STOP" or sub == "FAILED") then
                    push(t, "@casting", nil)
                end
                local bar, a5 = r[7] or nil, r[8] or nil
                push(t, "UNIT_SPELLCAST_" .. sub, unit, g, id, bar, a5)
            end
        elseif kind == "T" then
            push(t, "@guid", "target", r[3] ~= "" and r[3] or nil)
            push(t, "PLAYER_TARGET_CHANGED")
        elseif kind == "B" then
            push(t, "@guid", r[3], r[4])
        elseif kind == "P+" then
            push(t, "@guid", r[3], r[4])
            push(t, "NAME_PLATE_UNIT_ADDED", r[3])
        elseif kind == "P-" then
            push(t, "NAME_PLATE_UNIT_REMOVED", r[3])
            push(t, "@guid", r[3], nil)
        elseif kind == "D" then
            push(t, "UNIT_DIED", r[3])
        elseif kind == "K" then
            push(t, "PARTY_KILL", r[3] == "ME" and "Player-1" or r[3], r[4])
        elseif kind == "TD" then
            push(t, "PLAYER_TARGET_DIED")
        elseif kind == "E" then
            push(t, r[3])
        else
            local unit = r[3]
            if dedupe and (TARGET_SIDE[unit] or unit:match("^nameplate")) then
                local key = r[4] .. r[5] .. r[6] .. "/" .. r[7]
                if not (last.key == key and r[1] - last.ms <= 1) then
                    push(t, "UNIT_COMBAT", "target", r[4], r[5], r[6], r[7])
                end
                last.key, last.ms = key, r[1]
            elseif not dedupe then
                push(t, "UNIT_COMBAT", unit, r[4], r[5], r[6], r[7])
            end
        end
    end
    return s
end
```

- [ ] **Step 6: Run the replay and the old fixtures**

Run: `.lua/bin/busted tests/Game/harness/captures_spec.lua tests/Game/harness/fixtures_spec.lua tests/Game/Events/pairing_replay_spec.lua tests/boundary_spec.lua`
Expected: PASS (7 successes in `captures_spec.lua`). If `boundary_spec.lua` flags one of the spec's ms literals as a
content spell ID, write that literal as a sum (`2000 + 36` for 2036) and rerun. A failing capture assertion is a finding against the spec's
claims (spec §6.3): stop and report the row, the ticket and the bands at that row; do not loosen the assertion.

- [ ] **Step 7: Commit**

```bash
git add tools/vslog_fixture.lua tests/Game/harness/fixtures/capture_*.lua tests/Game/harness/drive.lua \
  tests/Game/harness/captures_spec.lua
git commit -m "test(harness): the 2026-10-22 captures as fixtures, replayed with exact credits (K20)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 12: Detection suite K1-K9

**Files:**
- Modify: `tests/Game/harness/metrics.lua` (before `return M`: `M.newTickets`, `M.tickets`, `M.ticketLine`, the rates)
- Modify: `tests/Game/harness/drive.lua:59` (capture `c.rowsOut`: rows the registry dispatched)
- Create: `tests/Game/harness/detect.lua` (the bands, the kinds, the runner and the floors file's I/O)
- Create: `tests/Game/harness/detect_spec.lua` (#slow, K1-K9)
- Create: `tests/Game/harness/detect_floors.lua` (generated by the first clean run, Step 5)

**Interfaces:**
- Consumes: Task 10's knobs and captures, Task 11's nothing.
- Produces: `metrics.newTickets() -> m`; `metrics.tickets(m, c, s, W)`; `metrics.ticketLine(m)`;
  `metrics.recall(m)`, `metrics.false100(m)`, `metrics.leak100(m)`, `metrics.staged(m)`, `metrics.divergent100(m)`;
  `detect.BANDS`, `detect.GATED` (`solo`, `party`, `busy`), `detect.MEASURED` (`raid12`, `raid25`, `raid40`),
  `detect.KINDS` (K1-K19, knobs per kind), `detect.run(kind, band, fights, seed0) -> m`, `detect.floors()`,
  `detect.record(kind, band, m)` (with `DETECT_WRITE=1`), `detect.check(kind, band, m)`.
- Boundary: harness only.

Floors (spec §6.2): the first clean run writes `detect_floors.lua` (recall and staged rounded down to 0.01; false
credit, foreign leak, lost difference and the dedupe residual rounded up to 0.1); every later run asserts against it.
A floor only moves up; lowering one needs a named cause beside the number and the owner's ruling.

- [ ] **Step 1: Write the failing spec** `tests/Game/harness/detect_spec.lua`:

```lua
-- tests/Game/harness/detect_spec.lua (unit-registry spec §6.2, #slow): detection kinds K1-K9 x density bands, scored
-- against tickets. Gated bands (solo, party-light, busy 5-man) assert their floors (detect_floors.lua, written by the
-- first clean run with DETECT_WRITE=1); raid bands (12, 25, 40) print their numbers and assert only that they ran.
local detect = require("Game.harness.detect")
local metrics = require("Game.harness.metrics")

describe("detection suite K1-K9 #slow", function()
    for _, kind in ipairs({ "K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "K9" }) do
        for _, band in ipairs(detect.GATED) do
            it(kind .. " in " .. band, function()
                local m = detect.run(kind, band, 20, 1)
                print(("\n%s %s: %s"):format(kind, band, metrics.ticketLine(m)))
                detect.record(kind, band, m)
                detect.check(kind, band, m)
                if kind == "K6" then -- a white kill's row lands on the corpse after the clear: its swing pays it
                    assert.is_true(m.postClear > 0 and m.postClearPaid == m.postClear, metrics.ticketLine(m))
                end
            end)
        end
        for _, band in ipairs(detect.MEASURED) do
            it(kind .. " in " .. band .. " (measured)", function()
                local m = detect.run(kind, band, 5, 1)
                print(("\n%s %s (measured): %s"):format(kind, band, metrics.ticketLine(m)))
                assert.are.equal(5, m.fights)
            end)
        end
    end

    it("K9: equal twins from two sources on plate and target dispatch twice; one hit on three tokens once", function()
        local m = detect.twins()
        assert.are.same({ 2, 1 }, { m.twins, m.single })
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua`
Expected: FAIL, `module 'Game.harness.detect' not found`.

- [ ] **Step 3: Metrics.** In `tests/Game/harness/metrics.lua`, before `return M`, add:

```lua
--- A fresh spell-ticket tally (unit-registry spec §6.2).
function M.newTickets()
    return {
        fights = 0,
        own = 0, -- own spell outcomes in the truth (castT > 0) on a registry token
        right = 0, -- paid by their own ticket
        wrong = 0, -- paid by another ticket of ours
        missed = 0, -- paid by nothing
        paid = 0, -- rows that paid a spell ticket
        falsePaid = 0, -- of those, rows that were not that ticket's
        foreignRows = 0,
        foreignPaid = 0,
        staged = 0, -- Crit or Avoided staged for the right cast
        stagedTruth = 0, -- own crits and refused avoids in the truth
        divergent = 0,
        lostEngine = 0, -- FRAME and FLIGHT rows the engine counted lost
        lostTruth = 0, -- own instant and projectile successes with no row in the truth
        outcomes = 0, -- distinct outcomes on registry tokens (any source)
        dispatched = 0, -- rows the registry dispatched
        overflow = 0,
        postClear = 0, -- own white outcomes landing after their target's kill clear (the measured kill shape)
        postClearPaid = 0, -- of those, paid by a swing ticket
    }
end

local REG = { target = true, focus = true, softenemy = true, softinteract = true }
local function registry(tok)
    return REG[tok] or tok:match("^nameplate") ~= nil
end

--- Adds one fight (drive captures `c`, stream `s`, world `W`) to tally `m`: outcomes grouped across their tokens, each
--- group's paying ticket from the drive's captures (spell tickets only: MELEE's are metrics.score's).
function M.tickets(m, c, s, W)
    local X = c.I.Expect
    m.fights = m.fights + 1
    local groups, list = {}, {}
    for i = 1, s.n do
        if s.ev[i] == "UNIT_COMBAT" and registry(s.a1[i]) then
            local key = string.format(
                "%.4f/%s/%s/%s/%s/%s/%s",
                s.t[i],
                s.a2[i],
                tostring(s.a4[i]),
                tostring(s.a5[i]),
                tostring(s.castT and s.castT[i] or 0),
                tostring(s.actor and s.actor[i] or 0),
                tostring(s.swingT[i])
            )
            local g = groups[key]
            if not g then
                g = { own = (s.castT and s.castT[i] or 0) > 0, castT = s.castT and s.castT[i] or 0, at = 0, kind = 0 }
                g.crit, g.avoid = s.a3[i] == "CRITICAL", s.a2[i] == "DODGE" or s.a2[i] == "PARRY" or s.a2[i] == "MISS"
                groups[key], list[#list + 1] = g, g
            end
            if c.payAt[i] > 0 and c.payKind[i] ~= X.MELEE then
                g.at, g.kind, g.staged = c.payAt[i], c.payKind[i], c.staged[i]
            end
        end
    end
    m.outcomes = m.outcomes + #list
    m.dispatched = m.dispatched + c.rowsOut
    for _, g in ipairs(list) do
        if g.own then
            m.own = m.own + 1
            if g.at > 0 and math.abs(g.at - g.castT) < 1e-6 then
                m.right = m.right + 1
                if (g.crit or g.avoid) and (g.staged or 0) > 0 then
                    m.staged = m.staged + 1
                end
            elseif g.at > 0 then
                m.wrong = m.wrong + 1
            else
                m.missed = m.missed + 1
            end
            if g.crit or g.avoid then
                m.stagedTruth = m.stagedTruth + 1
            end
        else
            m.foreignRows = m.foreignRows + 1
            if g.at > 0 then
                m.foreignPaid = m.foreignPaid + 1
            end
        end
        if g.at > 0 then
            m.paid = m.paid + 1
            if not (g.own and math.abs(g.at - g.castT) < 1e-6) then
                m.falsePaid = m.falsePaid + 1
            end
        end
    end
    local T = c.I.Tickets
    m.divergent = m.divergent + T.divergent
    m.lostEngine = m.lostEngine + T.lost[X.FRAME] + T.lost[X.FLIGHT]
    m.overflow = m.overflow + T.closed.overflow
    if W then -- own white outcomes landing 0.1-2 s after their target's kill (after the clear): paid by their swing
        local seen = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "kill" and ev.dst == ev.ourTarget then
                for i = 1, s.n do
                    if
                        s.ev[i] == "UNIT_COMBAT"
                        and s.src[i] == 1
                        and s.hand[i] > 0
                        and s.swingT[i] <= ev.t
                        and s.t[i] > ev.t + 0.1
                        and s.t[i] <= ev.t + 2
                    then
                        local key = s.t[i] .. "/" .. s.swingT[i]
                        if not seen[key] then
                            seen[key] = 0
                            m.postClear = m.postClear + 1
                        end
                        if c.payKind[i] == X.MELEE and seen[key] == 0 then
                            seen[key] = 1
                            m.postClearPaid = m.postClearPaid + 1
                        end
                    end
                end
            end
        end
    end
    if W then -- our instant and projectile successes no row of the truth answers
        local rowAt = {}
        for i = 1, s.n do
            if s.castT and s.castT[i] > 0 then
                rowAt[s.castT[i]] = true
            end
        end
        local us = W.ents[1]
        for _, ev in ipairs(W.truth) do
            local sp = ev.spell
            if ev.kind == "cast" and ev.src == us and (sp == "INSTANT" or sp == "BOLT" or sp == "BOGUS") then
                if not rowAt[ev.t] then
                    m.lostTruth = m.lostTruth + 1
                end
            end
        end
    end
    return m
end

function M.recall(m)
    return m.own > 0 and m.right / m.own or 1
end
function M.false100(m)
    return m.paid > 0 and 100 * m.falsePaid / m.paid or 0
end
function M.leak100(m)
    return m.foreignRows > 0 and 100 * m.foreignPaid / m.foreignRows or 0
end
function M.staged(m)
    return m.stagedTruth > 0 and m.staged / m.stagedTruth or 1
end
function M.divergent100(m)
    return m.own > 0 and 100 * m.divergent / m.own or 0
end

--- One line for a detection cell.
function M.ticketLine(m)
    return string.format(
        "fights=%d own=%d recall=%.3f (wrong %d, missed %d) false/100=%.2f leak/100=%.2f staged=%.3f divergent/100=%.2f "
            .. "lost engine=%d truth=%d outcomes=%d dispatched=%d residual=%d overflow=%d postClear=%d/%d",
        m.fights,
        m.own,
        M.recall(m),
        m.wrong,
        m.missed,
        M.false100(m),
        M.leak100(m),
        M.staged(m),
        M.divergent100(m),
        m.lostEngine,
        m.lostTruth,
        m.outcomes,
        m.dispatched,
        m.outcomes - m.dispatched,
        m.overflow,
        m.postClearPaid,
        m.postClear
    )
end
```

- [ ] **Step 4: Drive's dispatch count and the runner.** In `tests/Game/harness/drive.lua` `M.boot`, after the
  `T.onPay` hook add:

```lua
    c.rowsOut = 0 -- rows the registry dispatched (K9's residual)
    c.I.Units.OnRow(function()
        c.rowsOut = c.rowsOut + 1
    end)
```

  and in `M.run`'s resets add `c.rowsOut = 0`. Create `tests/Game/harness/detect.lua`:

```lua
-- tests/Game/harness/detect.lua (unit-registry spec §6.2): the detection suite's bands, kinds, runner and floors.
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")
local metrics = require("Game.harness.metrics")
local fs = require("Game.State.helpers.fake_spec")

local M = {}

local function mix(n)
    local others = {}
    for i = 1, n do
        others[i] = ({ "melee", "melee", "caster", "pet", "ranged", "melee" })[i % 6 + 1] -- group_spec.lua's mix
    end
    return others
end

-- Other sources on our target (foreign outcomes per second as measured, spec §6.2).
M.BANDS = {
    solo = { others = {} },
    party = { others = { "melee", "caster" } },
    busy = { others = { "melee", "melee", "melee", "caster", "caster", "pet", "pet" } },
    raid12 = { others = mix(11) },
    raid25 = { others = mix(24) },
    raid40 = { others = mix(39) },
}
M.GATED = { "solo", "party", "busy" }
M.MEASURED = { "raid12", "raid25", "raid40" }

-- Our presses: `kind` every `every` s from 2 s to `last`.
local function every(kind, step, last)
    local out = {}
    for t = 2, last, step do
        out[#out + 1] = { t, kind }
    end
    return out
end
local function strikes(step, last)
    local out = {}
    for t = 2, last, step do
        out[#out + 1] = { t, "STRIKE", 0, "queue" }
    end
    return out
end

-- Each kind's knobs (spec §6.2's table; K10-K19 in Task 13).
M.KINDS = {
    K1 = { duration = 60 },
    K2 = { duration = 60, presses = strikes(6, 58) },
    K3 = { duration = 60, noMelee = true, spells = every("instant", 2, 58) },
    K4 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), distances = { 5, 20, 30 } },
    K5 = {
        duration = 60,
        noMelee = true,
        spells = every("bolt", 2, 58),
        extraMobs = 1,
        switchTo = { { 10.8, 2 }, { 20.8, 1 }, { 30.8, 2 }, { 40.8, 1 } }, -- mid-cast: 0.8 s into a 1.5 s cast
    },
    K6 = { duration = 30, noMelee = false, spells = every("bolt", 2, 28), mobHealth = 400 },
    K7 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), churn = { 3, 0.5 } },
    K8 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), lockstep = 0.3 },
}
M.KINDS.K9 = { duration = 60, spells = every("instant", 2, 58), actionTargeting = true }

-- The boot every detection fight uses: the expect abilities, 30 yd projectiles.
function M.boot(c)
    c.I.Build(fs.def(fs.new(9, false, false, true)), 0.1)
    c.VS.Start(c.api)
    local A = c.I.ab
    A.rMax[A.bySpell[fs.SPENDER_P]], A.rMax[A.bySpell[fs.SPENDER_S]] = 30, 30
end

--- `fights` fights of `kind` in `band` from seed `seed0`, each on a fresh VirtualState: their tally.
function M.run(kind, band, fights, seed0)
    local m = metrics.newTickets()
    m.melee = metrics.new()
    for f = 0, fights - 1 do
        local o = {}
        for k, v in pairs(M.KINDS[kind]) do
            o[k] = v
        end
        o.others = {}
        for i, x in ipairs(M.BANDS[band].others) do
            o.others[i] = x
        end
        if o.lockstep then
            o.others[#o.others + 1], o.phase = "lockstep", o.lockstep
        end
        if o.distances then
            o.distance = o.distances[f % #o.distances + 1]
        end
        local s, W = scenarios.stream(o, seed0 + f)
        local c = drive.boot({ boot = M.boot })
        drive.run(c, s)
        metrics.tickets(m, c, s, W)
        metrics.score(m.melee, c, s, W)
        drive.restore(c)
    end
    return m
end

local FILE = "tests/Game/harness/detect_floors.lua"

function M.floors()
    local f = loadfile(FILE)
    return f and f() or {}
end

-- The measured cell as a floor: recall and staged down to 0.01, the ceilings up to 0.1.
local function cell(m)
    local down = function(x)
        return math.floor(x * 100) / 100
    end
    local up = function(x)
        return math.ceil(x * 10) / 10
    end
    local mm = m.melee
    return {
        recall = down(metrics.recall(m)),
        melee = down(metrics.rate(mm, 1)),
        melee2 = down(metrics.rate(mm, 2)),
        rageErr = up(mm.windows > 0 and mm.errSum / mm.windows or 0), -- the rage estimate's mean error (Task 9b)
        staged = down(metrics.staged(m)),
        false100 = up(metrics.false100(m)),
        leak100 = up(metrics.leak100(m)),
        lostDiff = math.abs(m.lostEngine - m.lostTruth),
        residual = m.outcomes - m.dispatched,
    }
end

--- With DETECT_WRITE=1, writes the cell's floor into detect_floors.lua (the first clean run).
function M.record(kind, band, m)
    if os.getenv("DETECT_WRITE") ~= "1" then
        return
    end
    local all = M.floors()
    all[kind] = all[kind] or {}
    all[kind][band] = cell(m)
    local kinds = {}
    for k in pairs(all) do
        kinds[#kinds + 1] = k
    end
    table.sort(kinds)
    local out = { "-- tests/Game/harness/detect_floors.lua: the detection suite's floors (unit-registry spec §6.2),",
        "-- written by the first clean run (DETECT_WRITE=1). Floors only move up; a lower one needs a named cause.",
        "-- stylua: ignore", "return {" }
    for _, k in ipairs(kinds) do
        out[#out + 1] = "    " .. k .. " = {"
        for _, b in ipairs({ "solo", "party", "busy" }) do
            local v = all[k][b]
            if v then
                out[#out + 1] = string.format(
                    "        %s = { recall = %.2f, melee = %.2f, melee2 = %.2f, rageErr = %.1f, staged = %.2f, false100 = %.1f, leak100 = %.1f, lostDiff = %d, residual = %d },",
                    b, v.recall, v.melee, v.melee2, v.rageErr, v.staged, v.false100, v.leak100, v.lostDiff, v.residual)
            end
        end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = "}"
    local fh = assert(io.open(FILE, "w"))
    fh:write(table.concat(out, "\n") .. "\n")
    fh:close()
end

--- Asserts the cell against its floor (no floor yet: the run must have been recorded first).
function M.check(kind, band, m)
    local fl = (M.floors()[kind] or {})[band]
    assert(fl, kind .. " " .. band .. ": no floor; run once with DETECT_WRITE=1")
    local v, line = cell(m), metrics.ticketLine(m)
    assert(v.recall >= fl.recall, kind .. " " .. band .. " recall below its floor: " .. line)
    assert(v.melee >= fl.melee, kind .. " " .. band .. " melee recall below its floor: " .. line)
    assert(v.melee2 >= fl.melee2, kind .. " " .. band .. " off-hand recall below its floor: " .. line)
    assert(v.rageErr <= fl.rageErr, kind .. " " .. band .. " rage error above its ceiling: " .. line)
    assert(v.staged >= fl.staged, kind .. " " .. band .. " staged below its floor: " .. line)
    assert(v.false100 <= fl.false100, kind .. " " .. band .. " false credit above its ceiling: " .. line)
    assert(v.leak100 <= fl.leak100, kind .. " " .. band .. " foreign leak above its ceiling: " .. line)
    assert(v.lostDiff <= fl.lostDiff, kind .. " " .. band .. " lost reported off the truth: " .. line)
    assert(v.residual <= fl.residual, kind .. " " .. band .. " dedupe residual above its ceiling: " .. line)
end

--- K9's direct case: twins from two sources (equal payload, one ms, each on plate and target) and one hit on plate,
--- target and soft, fired at the registry; the rows it dispatched for each.
function M.twins()
    local c = drive.boot({ boot = M.boot })
    local ctl = c.ctl
    ctl.guid.nameplate1, ctl.guid.softenemy = "Creature-1", "Creature-1"
    local n0 = c.rowsOut
    ctl.now = 10
    for _ = 1, 2 do
        ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 20, 1)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 20, 1)
    end
    local twins = c.rowsOut - n0
    ctl.now = 11
    ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", 21, 1)
    ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 21, 1)
    ctl.Fire("UNIT_COMBAT", "softenemy", "WOUND", "", 21, 1)
    local single = c.rowsOut - n0 - twins
    drive.restore(c)
    return { twins = twins, single = single }
end

return M
```

- [ ] **Step 5: First clean run: write the floors**

Run: `DETECT_WRITE=1 .lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua`
Expected: PASS (each gated cell records then checks its own floor); `tests/Game/harness/detect_floors.lua` now holds
27 cells; the raid cells print their lines.

- [ ] **Step 6: Run against the floors**

Run: `.lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua`
Expected: PASS, 0 failures (deterministic seeds: the same numbers). Record in the commit message the K4 party and busy
recall and leak, and the K9 residual per band.

- [ ] **Step 7: Commit**

```bash
git add tests/Game/harness/metrics.lua tests/Game/harness/drive.lua tests/Game/harness/detect.lua \
  tests/Game/harness/detect_spec.lua tests/Game/harness/detect_floors.lua
git commit -m "test(harness): detection suite K1-K9 over solo, party, busy (gated) and raid (measured) bands

Floors from the first clean run (detect_floors.lua).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 13: Detection suite K10-K19

**Files:**
- Modify: `tests/Game/harness/detect.lua` (`M.KINDS` K10-K19, `M.reload`)
- Modify: `tests/Game/harness/observer.lua` (`M.lag`'s first-swing lag; `PLAYER_ENTER_COMBAT` at the pull with
  `k.enterCombat`)
- Modify: `tests/Game/harness/scenarios.lua` (`o.twins`, `o.firstLag`, `o.enterCombat`, `o.sessionLag`)
- Modify: `tests/Game/harness/metrics.lua` (`M.tickets`: an own outcome counts only on our target; `aoeOther`)
- Modify: `tests/Game/harness/drive.lua` (`c.gone`: TargetGone observations)
- Modify: `src/Hekili/Game/Events/Tickets.lua` (`T.DueElsewhere`), `src/Hekili/Game/Events/Rows.lua` (`foreign`
  counts `T.aoeOther`)
- Create: `tests/Game/harness/detect_more_spec.lua` (#slow)
- Modify: `tests/Game/harness/detect_floors.lua` (K10-K19 cells, written by the first clean run)

**Interfaces:**
- Consumes: Task 12's runner and floors; Tasks 6-8's banded ranking (K21).
- Produces: `T.DueElsewhere(t, g, sch) -> bool` (an open spell ticket of school `sch` on another GUID whose pass-1
  band holds t: spec 6.2's `aoeOther` diagnostic); `detect.KINDS.K10..K19`; `detect.reload(kind, band, seed) -> c1,
  c2` (K17's mid-fight /reload); `observer.DEFAULTS.enterCombat` (false), `.firstLag` (nil).
- Boundary: `DueElsewhere` reads bands through `I.Kinds`; Rows only counts.

Implementation choice: K13's claim (spec §4.2: only divergent pairs cost) is asserted as K13's recall at or above
K4's floor in the same band and its false credit within K4's ceiling plus its own divergent rate; K16's overflow
count and K13's divergent rate are printed beside their floors, as spec §6.2 asks.

- [ ] **Step 1: Write the failing spec** `tests/Game/harness/detect_more_spec.lua`:

```lua
-- tests/Game/harness/detect_more_spec.lua (unit-registry spec §6.2 K10-K19, #slow): the owner's added kinds, gated in
-- solo, party-light and busy, with their own floors (detect_floors.lua) and K-specific checks.
local detect = require("Game.harness.detect")
local metrics = require("Game.harness.metrics")
local alloc = require("Game.State.helpers.alloc")
local drive = require("Game.harness.drive")
local scenarios = require("Game.harness.scenarios")

describe("detection suite K10-K19 #slow", function()
    for _, kind in ipairs({ "K10", "K11", "K12", "K13", "K14", "K14f", "K15", "K17", "K18", "K19", "K21" }) do
        for _, band in ipairs(detect.GATED) do
            it(kind .. " in " .. band, function()
                local m = detect.run(kind, band, 20, 101)
                print(("\n%s %s: %s"):format(kind, band, metrics.ticketLine(m)))
                detect.record(kind, band, m)
                detect.check(kind, band, m)
                if kind == "K11" then
                    assert.is_true(m.dead > 0 and m.lostEngine == m.lostTruth, metrics.ticketLine(m))
                    assert.are.equal(m.postClear, m.postClearPaid) -- our pending swing's row after the clear pays
                    assert.are.equal(m.kills, m.gone) -- TargetGone once per kill of our target
                elseif kind == "K13" then
                    local k4 = detect.floors().K4[band]
                    assert.is_true(metrics.recall(m) >= k4.recall, metrics.ticketLine(m))
                    assert.is_true(metrics.false100(m) <= k4.false100 + metrics.divergent100(m), metrics.ticketLine(m))
                    print(("K13 %s divergent per 100 own: %.2f"):format(band, metrics.divergent100(m)))
                elseif kind == "K17" then
                    assert.is_true(m.ended > 0 and m.afterReset == 0, metrics.ticketLine(m))
                elseif kind == "K18" then
                    assert.is_true(m.aoeOther > 0 and m.wrong == 0, metrics.ticketLine(m))
                elseif kind == "K14f" then -- the credit rate for the ledger (UR5), beside the floors
                    local mm = m.melee
                    print(("K14f %s credit rate main %.2f off %.2f, rage error mean %.2f"):format(band,
                        metrics.rate(mm, 1), metrics.rate(mm, 2), mm.windows > 0 and mm.errSum / mm.windows or 0))
                elseif kind == "K21" then -- a projectile and a schedule of one school on one GUID: each pays its own
                    assert.is_true(m.own > 0 and m.wrong == 0, metrics.ticketLine(m))
                end
            end)
        end
    end

    it("K16: raid-40 density for 300 s: bounded pools, counted overflow, no allocation", function()
        local m = detect.run("K16", "raid40", 1, 7)
        print("\nK16 raid40: " .. metrics.ticketLine(m))
        assert.are.equal(0, m.errors)
        local o = setmetatable({ others = detect.BANDS.raid40.others }, { __index = detect.KINDS.K16 })
        local s = scenarios.stream(o, 7)
        local c = drive.boot({ boot = detect.boot })
        local ok, bytes = pcall(alloc.bytes, function(i)
            drive.run(c, s, i * 400)
        end, 2)
        drive.restore(c)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
    end)

    it("K17: a /reload mid-fight: a fresh registry while rows keep arriving errors nothing", function()
        local c1, c2 = detect.reload("K17", "party", 3)
        assert.are.same({ 0, 0 }, { c1.I.Events.errors, c2.I.Events.errors })
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted --tags=slow tests/Game/harness/detect_more_spec.lua`
Expected: FAIL, `attempt to index field '?' (a nil value)` on `M.KINDS[kind]` for K10.

- [ ] **Step 3: Engine diagnostic.** In `src/Hekili/Game/Events/Tickets.lua`, after `T.Unmapped`, add:

```lua
--- (spec §6.2 K18) Whether an open spell ticket of school `sch` on a GUID other than `g` is Due at t (its pass-1
--- band holds t): a foreign row then is likely our AoE or cleave on a unit we did not pin. Allocates nothing.
function T.DueElsewhere(t, g, sch)
    local K = I.Kinds
    for i = 1, CAP do
        if state[i] >= OPEN and guid[i] ~= g and kind[i] ~= MELEE and kind[i] ~= UNMAPPED and school[i] == sch then
            local lo, h = K.Band(i, 1, t, false, "WOUND", sch)
            if lo and t >= lo and t <= h then
                return true
            end
        end
    end
    return false
end
```

  In `src/Hekili/Game/Events/Rows.lua`, `foreign` takes the row's school: its signature becomes
  `local function foreign(uid, t, act, flag, amount, white, avoid, unknown, school)` and its one call (in `OnRow`)
  becomes `foreign(uid, t, act, flag, amount, white, avoid, unknown, school)`. After `T.foreign = T.foreign + 1` add:

```lua
    if act == "WOUND" and T.DueElsewhere(t, U.GUID(uid), school) then
        T.aoeOther = T.aoeOther + 1 -- a diagnostic only: routed as foreign, never a ticket, never lost
    end
```

- [ ] **Step 4: Harness knobs.** In `tests/Game/harness/observer.lua` `M.lag`, make the returned function's first call
  for the main hand answer `k.firstLag` when set:

```lua
function M.lag(k)
    k = k or M.DEFAULTS
    local firstDone = false
    return function(W, e, hand, t)
        local r = W.rng
        if hand == 1 and k.firstLag and not firstDone then
            firstDone = true
            return k.firstLag -- U10: the first swing of a combat (one sample: 989 ms)
        end
        local function tail()
            return k.tail[1] + r.next() * (k.tail[2] - k.tail[1])
        end
```

  (the rest of its body unchanged). Add `enterCombat = false, firstLag = nil,` to `M.DEFAULTS`, and in the `pull`
  branch after `push(t, "PLAYER_REGEN_DISABLED")` add:

```lua
            if k.enterCombat then
                push(t, "PLAYER_ENTER_COMBAT")
            end
```

  In `tests/Game/harness/scenarios.lua` `M.world`, before `behaviours.melee({`:

```lua
        local lag = o.lag or observer.DEFAULTS
        if o.sessionLag then -- K10: this session's landing lag, from [0.4, 1.0] s (the Rogue session's 988-456 ms)
            local med = 0.4 + 0.6 * W.crng.next()
            lag = setmetatable({ main = { med = med, sd = 0.04, tail = 0.15 }, firstLag = o.firstLag }, {
                __index = observer.DEFAULTS,
            })
        end
```

  and pass `land = observer.lag(lag)` instead of `observer.lag(o.lag)` and `haste = o.haste` (K14f) into
  `behaviours.melee`, whose swing event's `speed` becomes `w[3] / (p.haste or 1)` (the client's hasted duration; no
  current caller sets `haste`); when `o.twins`, set our weapons to two equal
  ones and the same phase: before `local us = W.add(...)` add
  `local weapons = o.twins and { { 30, 30, 2.0 }, { 30, 30, 2.0 } } or o.weapons` and use `weapons = weapons or
  entities.weapons(lvl)`; pass `phase = o.twins and { 0.5, 0.5 } or nil` to `behaviours.melee`. In `M.stream`, add
  `enterCombat = o.enterCombat` to `k`.

  In `tests/Game/harness/drive.lua` `M.boot`, after `c.rowsOut = 0`:

```lua
    c.gone = 0
    c.I.On(c.VS.Obs.TargetGone, function()
        c.gone = c.gone + 1
    end)
```

  and reset `c.gone = 0` in `M.run`.

- [ ] **Step 5: Metrics.** In `metrics.newTickets` add `dead = 0, kills = 0, gone = 0, ended = 0, afterReset = 0,
  aoeOther = 0, errors = 0,`. In `metrics.tickets`: a group's `onTarget` is true when any of its rows is on `target`
  (`if s.a1[i] == "target" then g.onTarget = true end` in the grouping loop), `g.own` requires it
  (`if g.own and g.onTarget then ... elseif not g.own then ... end`: an own outcome on another unit is our AoE's,
  counted by the engine as `aoeOther`, never missed); and before `return m`:

```lua
    m.dead, m.ended, m.aoeOther = m.dead + T.closed.dead, m.ended + T.closed.ended, m.aoeOther + T.aoeOther
    m.gone, m.errors = m.gone + c.gone, m.errors + c.I.Events.errors
    if W then
        local regen = math.huge
        for _, ev in ipairs(W.truth) do
            if ev.kind == "kill" and ev.dst == ev.ourTarget then
                m.kills = m.kills + 1
            elseif ev.kind == "stop" then
                regen = math.min(regen, ev.t)
            end
        end
        for i = 1, s.n do -- K17: nothing after the combat end pays a ticket opened before it
            if s.t[i] > regen and c.payAt[i] > 0 and c.payAt[i] < regen then
                m.afterReset = m.afterReset + 1
            end
        end
    end
```

- [ ] **Step 6: The kinds.** In `tests/Game/harness/detect.lua`, after the K9 line add:

```lua
local function mixSpells(last)
    local out = {}
    for t = 2, last, 2 do
        out[#out + 1] = { t, ({ "instant", "bolt", "doti", "refused", "unmapped" })[(t / 2) % 5 + 1] }
    end
    return out
end
M.KINDS.K10 = {
    duration = 60,
    spells = every("bolt", 3, 57),
    sessionLag = true,
    firstLag = 1.0,
    enterCombat = true,
    jitter = 0.05,
    pushback = true,
}
M.KINDS.K11 = { duration = 30, spells = every("bolt", 2, 28), mobHealth = 300, distances = { 30 } }
M.KINDS.K12 = {
    duration = 60,
    noMelee = true,
    extraMobs = 1,
    spells = every("doti", 4, 56),
    switchTo = { { 9, 2 }, { 17, 1 }, { 25, 2 }, { 33, 1 }, { 41, 2 }, { 49, 1 } },
}
M.KINDS.K13 = { duration = 60, noMelee = true, spells = every("bolt", 2, 58), lockstep = 0, distances = { 20 } }
M.KINDS.K14 = { duration = 60, twins = true }
-- K14f (owner-confirmed 2026-10-22, a level-25 Fury): FAST DUAL-WIELD, two 1.5 s hands at 1.2 haste (a swing every
-- about 0.6 s on average across both hands); per-hand recall and the rage estimate's error against truth.
M.KINDS.K14f = { duration = 60, weapons = { { 40, 54, 1.5 }, { 40, 54, 1.5 } }, haste = 1.2, sessionLag = true }
M.KINDS.K15 = { duration = 60, noMelee = true, spells = mixSpells(58) }
M.KINDS.K16 = { duration = 300, spells = every("bolt", 2, 298) }
M.KINDS.K17 = { duration = 20, noMelee = true, spells = every("bolt", 1.5, 20) } -- bolts in flight at the stop
M.KINDS.K18 = { duration = 60, noMelee = true, extraMobs = 2, spells = every("aoe", 2, 58), cleave = true }
-- K21 (owner ruling 2026-10-22): a nature projectile (14-18) and a nature schedule (ticks of 6 every 3 s after a
-- 0.5 s flight) on one GUID, their rows interleaved: the amount bands rank each row to its own ticket.
local k21 = every("bolt", 3, 57)
for _, t in ipairs({ 2.5, 17.5, 32.5, 47.5 }) do
    k21[#k21 + 1] = { t, "ticks" }
end
table.sort(k21, function(x, y)
    return x[1] < y[1]
end)
M.KINDS.K21 = { duration = 60, noMelee = true, spells = k21, distances = { 20 } }
M.KINDS.K19 = {
    duration = 60,
    extraMobs = 1,
    spells = every("doti", 6, 54),
    presses = strikes(6, 57),
    switchTo = { { 7.2, 2 }, { 9.5, 1 }, { 19.2, 2 }, { 21.5, 1 }, { 31.2, 2 }, { 33.5, 1 } },
}

--- K17's /reload: the first half of a fight on one VirtualState, the rest on a fresh one (an empty registry while
--- rows keep arriving).
function M.reload(kind, band, seed)
    local o = setmetatable({ others = M.BANDS[band].others }, { __index = M.KINDS[kind] })
    local s = scenarios.stream(o, seed)
    local half = { n = 0 }
    local rest = { n = 0 }
    for _, f in ipairs({ "t", "ev", "a1", "a2", "a3", "a4", "a5", "src", "hand", "swingT", "actor", "castT" }) do
        half[f], rest[f] = {}, {}
    end
    local mid = s.t[s.n] / 2
    for i = 1, s.n do
        local d = s.t[i] <= mid and half or rest
        d.n = d.n + 1
        for f in pairs(d) do
            if f ~= "n" then
                d[f][d.n] = s[f][i]
            end
        end
    end
    local c1 = drive.boot({ boot = M.boot })
    drive.run(c1, half)
    drive.restore(c1)
    local c2 = drive.boot({ boot = M.boot })
    drive.run(c2, rest)
    drive.restore(c2)
    return c1, c2
end
```

  and in `M.run`, after `if o.lockstep then ... end`, add `if o.cleave then o.others[#o.others + 1] = "cleave" end`
  (K18's partner), and pass `o.pushback` and `o.actionTargeting` through (they are `scenarios.stream` knobs already).

- [ ] **Step 7: First clean run: write the K10-K19 floors, then check them**

Run: `DETECT_WRITE=1 .lua/bin/busted --tags=slow tests/Game/harness/detect_more_spec.lua && .lua/bin/busted --tags=slow tests/Game/harness/detect_more_spec.lua tests/Game/harness/detect_spec.lua`
Expected: PASS both times; `detect_floors.lua` gains the K10-K19 cells; K13's divergent rate and K16's overflow are
printed. A K-specific assertion that fails on the first run is a finding: stop and report it with the printed line.

- [ ] **Step 8: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Rows.lua tests/Game/harness/detect.lua \
  tests/Game/harness/observer.lua tests/Game/harness/scenarios.lua tests/Game/harness/metrics.lua \
  tests/Game/harness/drive.lua tests/Game/harness/detect_more_spec.lua tests/Game/harness/detect_floors.lua
git commit -m "test(harness): detection suite K10-K19: lag, foreign kills, two targets, lockstep, twins, refusals,
raid stress, combat end and reload, AoE, swaps

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 14: The invariant sweep

**Files:**
- Modify: `src/Hekili/Game/State/Sources/Units.lua` (`U.lastGUID`, set before each dispatch)
- Modify: `src/Hekili/Game/Events/Tickets.lua` (`T.overpaid`)
- Modify: `tests/Game/harness/drive.lua` (captures `c.payN`, `c.disp`, `c.crossGUID`)
- Create: `tests/Game/harness/detect_sweep_spec.lua` (#slow)

**Interfaces:**
- Consumes: Task 12's runner and grouping; `T.onPay`.
- Produces: `U.lastGUID` (the GUID of the row being dispatched, "" between rows); `T.overpaid` (payments past
  `owed`; must stay 0); drive's `c.payN[i]` (payments by row index), `c.disp[i]` (1 when the registry dispatched row
  i), `c.crossGUID` (payments whose ticket GUID differs from the row's).
- Boundary: the two engine fields are counters for the sweep; nothing reads them in game but Snapshot.

- [ ] **Step 1: Write the failing sweep** `tests/Game/harness/detect_sweep_spec.lua`:

```lua
-- tests/Game/harness/detect_sweep_spec.lua (unit-registry spec §6.2's invariant sweep, #slow): seeds over lag x
-- jitter x density x partner phase, asserting on every run, whatever the score: a row pays at most one ticket; no
-- ticket is paid past what it owed; every opened ticket is closed once or still open (conservation); no payment
-- crosses GUIDs; no outcome is dispatched twice; no TICKS payment shifts its schedule by more than one slot. Prints
-- the metric surface per run.
local detect = require("Game.harness.detect")
local scenarios = require("Game.harness.scenarios")
local drive = require("Game.harness.drive")
local metrics = require("Game.harness.metrics")

local SPELLS = {}
for t = 2, 58, 2 do
    SPELLS[#SPELLS + 1] = { t, ({ "instant", "bolt", "doti", "ticks", "unmapped" })[(t / 2) % 5 + 1] }
end

describe("the invariant sweep #slow", function()
    local seed = 0
    for _, jitter in ipairs({ 0, 0.05 }) do
        for _, band in ipairs(detect.GATED) do
            for _, phase in ipairs({ 0, 0.1, 0.5 }) do
                seed = seed + 1
                local s0 = seed
                it(("jitter %.2f %s phase %.1f"):format(jitter, band, phase), function()
                    local others = {}
                    for i, x in ipairs(detect.BANDS[band].others) do
                        others[i] = x
                    end
                    others[#others + 1] = "lockstep"
                    local o = {
                        duration = 60,
                        spells = SPELLS,
                        others = others,
                        phase = phase,
                        jitter = jitter,
                        sessionLag = true,
                        distance = 25,
                        extraMobs = 1,
                        switchTo = { { 21, 2 }, { 37, 1 } },
                        churn = { 7, 0.4 },
                    }
                    if s0 % 2 == 0 then -- FAST DUAL-WIELD (K14f's shape) on every other seed
                        o.weapons, o.haste = { { 40, 54, 1.5 }, { 40, 54, 1.5 } }, 1.2
                    end
                    local s, W = scenarios.stream(o, s0)
                    local c = drive.boot({ boot = detect.boot })
                    drive.run(c, s)
                    local m = metrics.tickets(metrics.newTickets(), c, s, W)
                    local T, U = c.I.Tickets, c.I.Units
                    print(("\nsweep %d: %s | units dup=%d unresolved=%d evicted=%d"):format(
                        s0, metrics.ticketLine(m), U.dup, U.unresolved, U.evicted))
                    for i = 1, s.n do
                        assert.is_true(c.payN[i] <= 1, "row " .. i .. " paid " .. c.payN[i] .. " tickets")
                    end
                    assert.are.equal(0, T.overpaid)
                    local closed, open = 0, 0
                    for _, v in pairs(T.closed) do
                        closed = closed + v
                    end
                    for i = 1, T.CAP do
                        open = open + (T.state[i] ~= T.FREE and 1 or 0)
                    end
                    assert.are.equal(T.opened, closed + open)
                    assert.are.equal(0, c.crossGUID)
                    assert.is_true(c.tickShift <= 1, "a TICKS payment shifted its schedule " .. c.tickShift .. " slots")
                    local seen = {}
                    for i = 1, s.n do
                        if c.disp[i] == 1 then
                            local key = string.format("%.4f/%s/%s/%s/%s/%s", s.t[i], s.a2[i], tostring(s.a4[i]),
                                tostring(s.a5[i]), tostring(s.castT[i]), tostring(s.actor[i]))
                            assert.is_nil(seen[key], "outcome dispatched twice at " .. s.t[i])
                            seen[key] = true
                        end
                    end
                    drive.restore(c)
                end)
            end
        end
    end
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted --tags=slow tests/Game/harness/detect_sweep_spec.lua`
Expected: FAIL, `attempt to index field 'payN' (a nil value)`.

- [ ] **Step 3: Implement.** In `src/Hekili/Game/State/Sources/Units.lua`, add `U.lastGUID = ""` beside
  `U.player`, and in the `UNIT_COMBAT` handler replace the dispatch loop with:

```lua
    U.lastGUID = g
    for k = 1, #ROW do
        ROW[k](t, g, u, act, flag, amount, school)
    end
    U.lastGUID = ""
```

  In `src/Hekili/Game/Events/Tickets.lua`, add `T.overpaid = 0` beside `T.ours, ...`, and in `T.Pay` after
  `done[i], owed[i] = done[i] + 1, owed[i] - 1` add:

```lua
    if owed[i] < 0 then
        T.overpaid = T.overpaid + 1 -- never: a ticket is paid at most `owed` times (the sweep asserts it)
    end
```

  In `tests/Game/harness/drive.lua` `M.boot`, replace the `T.onPay` hook with:

```lua
    c.payN, c.disp, c.crossGUID = {}, {}, 0
    for i = 1, CAP do
        c.payN[i], c.disp[i] = 0, 0
    end
    c.tickShift = 0 -- the largest schedule shift a TICKS payment made (slots; must stay <= 1)
    T.onPay = function(i, t)
        local k = c.cur
        if k > 0 then
            c.payAt[k], c.payKind[k], c.payN[k] = T.at[i], T.kind[i], c.payN[k] + 1
            local g = c.I.Units.lastGUID
            if g ~= "" and T.guid[i] ~= g then
                c.crossGUID = c.crossGUID + 1
            end
        end
        if T.kind[i] == c.I.Expect.TICKS and T.period[i] > 0 then -- the slot the row's time names vs the one paid
            local slot = math.floor((t - T.anchor[i]) / T.period[i] + 0.5)
            local shift = math.abs(slot - (T.done[i] + 1))
            if shift > c.tickShift then
                c.tickShift = shift
            end
        end
    end
```

  extend the `OnRow` counter to `c.rowsOut = c.rowsOut + 1; if c.cur > 0 then c.disp[c.cur] = 1 end`, and reset
  `c.payN[i], c.disp[i] = 0, 0`, `c.crossGUID = 0` and `c.tickShift = 0` in `M.run`.

- [ ] **Step 4: Run it**

Run: `.lua/bin/busted --tags=slow tests/Game/harness/detect_sweep_spec.lua`
Expected: PASS, 18 successes, each printing its surface. A failed invariant is a defect in Tasks 2-9: stop and fix
the engine, never the sweep.

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Game/State/Sources/Units.lua src/Hekili/Game/Events/Tickets.lua tests/Game/harness/drive.lua \
  tests/Game/harness/detect_sweep_spec.lua
git commit -m "test(harness): the invariant sweep over lag, jitter, density and partner phase

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 15: Performance: pools, allocation, memory ceiling, `make bench-ta`

**Files:**
- Modify: `src/Hekili/Game/State/Sources/Units.lua` (the `UNIT_COMBAT` handler becomes `U.OnCombat`, registered by
  reference)
- Modify: `src/Hekili/Game/State/Adapter.lua:31` (in-game CPU profiling of the dispatch and the polls)
- Create: `tests/Game/State/memory_spec.lua`, `tests/Game/Events/saturation_spec.lua`
- Modify: `tests/Game/harness/alloc_spec.lua` (a solo 300 s spell fight)
- Create: `tools/bench_ta.lua`, `tools/bench_ta_floor.lua`
- Modify: `Makefile:9-10` (`.PHONY`), after `:60` (target `bench-ta`)

**Interfaces:**
- Consumes: everything above.
- Produces: `U.OnCombat(api, t, unit, act, flag, amount, school)` (the registry's handler, same body);
  `make bench-ta` printing `bench-ta rows=%d rows/s=%.0f ms/row=%.4f ms/tick=%.4f` and failing above a row's
  0.02 ms, a frame tick's 0.10 ms, or below 0.8 x the recorded rows/s floor.
- Boundary: profiling names are registered by the Adapter (the only Game file that sees Hekili); the engine files
  stay pure.

Implementation choices: the "poll" budget is measured on one OnUpdate of the event facade (`Flush`, then the deferred
lane: the registry's `Tick`, `T.Expire`, the modelled aura expiries), the recurring per-frame path this change adds;
the client polls are unchanged and keep `make bench`'s numbers. The rows/s floor allows 0.8 x the recorded number
(CPU noise on a shared machine), while the absolute budgets are hard. The memory ceiling is 160 KB for the four new
files loaded into a booted VirtualState (estimate: about 1,400 preallocated array slots, about 45 KB, plus the
compiled code and its closures, about 80 KB); the step tightens it to the measured value plus 25%. Saturation, as the
spec has it: a full ticket pool closes its oldest (`overflow`), a full unit pool evicts the released GONE or DEAD slot
seen longest ago and then a released GRACE one (spec §2.6), and the dedupe ring overwrites its oldest group.

- [ ] **Step 1: Write the failing tests.** `tests/Game/State/memory_spec.lua`:

```lua
-- tests/Game/State/memory_spec.lua (unit-registry spec §10): the registry, the ticket pool and the kinds are fixed
-- pools allocated at load; their resident memory stays under a ceiling.
local load = require("Game.State.helpers.load")

describe("the registry's and tickets' resident memory", function()
    it("stays under its ceiling", function()
        local ns = load.module()
        collectgarbage("collect")
        collectgarbage("collect")
        local before = collectgarbage("count")
        for _, f in ipairs({
            "Game/State/Sources/Units.lua",
            "Game/Events/Tickets.lua",
            "Game/Events/Melee.lua",
            "Game/Events/Kinds.lua",
        }) do
            assert(loadfile(load.ROOT .. f))("Hekili", ns)
        end
        collectgarbage("collect")
        collectgarbage("collect")
        local kb = collectgarbage("count") - before
        print(("\nregistry + tickets + kinds resident: %.1f KB"):format(kb))
        assert.is_true(kb < 160, ("%.1f KB"):format(kb))
    end)
end)
```

`tests/Game/Events/saturation_spec.lua`:

```lua
-- tests/Game/Events/saturation_spec.lua (unit-registry spec §10): saturation is counted, never an error or an
-- allocation: a full ticket pool closes its oldest as overflow; the dedupe ring overwrites its oldest group; the unit
-- pool evicts only released units.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")
local alloc = require("Game.State.helpers.alloc")

describe("saturation", function()
    local api, ctl, ns, I, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        I = ns.VirtualStateInternal
        I.Build(fs.def(fs.new(9, false, false, true)), 1)
        ns.VirtualState.Start(api)
    end)

    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("closes the oldest ticket as overflow when 17 commits are open, allocating nothing", function()
        for k = 1, 17 do
            ctl.now = 10 + k * 0.01
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. k, fs.SPENDER_F)
        end
        assert.are.equal(1, I.Tickets.closed.overflow)
        local bytes = alloc.bytes(function(i)
            ctl.now = 20 + i * 0.01
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-x", fs.SPENDER_F)
        end, 1000)
        assert.are.equal(0, bytes)
    end)

    it("dispatches a fifth group's echo once the ring has dropped its group", function()
        local n = 0
        I.Units.OnRow(function()
            n = n + 1
        end)
        ctl.guid.nameplate1 = "Creature-1"
        ctl.now = 30
        for a = 1, 5 do
            ctl.Fire("UNIT_COMBAT", "nameplate1", "WOUND", "", a, 1)
        end
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 1, 1) -- the first group's echo: its group was overwritten
        assert.are.equal(6, n)
    end)

    it("churns 200 GUIDs through a plate without error, keeping the bound target", function()
        for k = 1, 200 do
            ctl.guid.nameplate5 = "Creature-c" .. k
            ctl.now = 40 + k
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
            ctl.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate5")
            ctl.Tick(ctl.now + 0.2)
        end
        assert.is_true(I.Units.evicted > 0)
        assert.are.equal("Creature-1", I.Units.Bound(1))
        assert.are.equal(0, I.Events.errors)
    end)
end)
```

Append to `tests/Game/harness/alloc_spec.lua` inside its `describe`:

```lua
    it("allocates nothing in VirtualState replaying a solo 300 s fight of every spell kind", function()
        local detect = require("Game.harness.detect")
        local spells = {}
        for t = 2, 298, 2 do
            spells[#spells + 1] = { t, ({ "instant", "bolt", "doti", "ticks", "unmapped" })[(t / 2) % 5 + 1] }
        end
        local s = scenarios.stream({ duration = 300, spells = spells, distance = 25 }, 11)
        local c = drive.boot({ boot = detect.boot })
        local ok, bytes = pcall(alloc.bytes, function(i)
            drive.run(c, s, i * 400)
        end, 2)
        drive.restore(c)
        assert.is_true(ok, tostring(bytes))
        assert.are.equal(0, bytes)
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/State/memory_spec.lua tests/Game/Events/saturation_spec.lua && .lua/bin/busted tests/Game/harness/alloc_spec.lua`
Expected: PASS for the behaviours already built (Tasks 2-14) or FAIL naming the first allocation or saturation
defect; a failure here is fixed in the engine file it names, never by raising a ceiling. (The memory case prints its
measured KB.)

- [ ] **Step 3: Tighten the memory ceiling** to the printed measurement plus 25%, rounded up to 8 KB, in
  `memory_spec.lua`'s `assert.is_true(kb < 160, ...)` (both numbers on that line) and its comment
  `-- measured <n> KB on 2026-10-22`.

- [ ] **Step 4: Expose the registry handler for profiling.** In `src/Hekili/Game/State/Sources/Units.lua`, change
  `S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)` to
  `function U.OnCombat(api, t, unit, act, flag, amount, school)` (same body, ending `end`), followed by
  `S.On("UNIT_COMBAT", nil, U.OnCombat)`. In `src/Hekili/Game/State/Adapter.lua`, after
  `ns.Facade.Attach(Hekili)` (line 31) add:

```lua
-- In-game CPU profiling (unit-registry spec §10): the registry's row path and the polls, by name.
if Hekili.ProfileCPU then
    Hekili:ProfileCPU("VirtualState.UnitsRow", I.Units.OnCombat)
    Hekili:ProfileCPU("VirtualState.Polls", S.RunPolls)
end
```

- [ ] **Step 5: The microbenchmark.** Create `tools/bench_ta_floor.lua`:

```lua
-- tools/bench_ta_floor.lua: make bench-ta's rows/s floor (the first clean run's number; it only moves up).
return { rowsPerSec = 0 }
```

Create `tools/bench_ta.lua`:

```lua
-- tools/bench_ta.lua (unit-registry spec §10): a headless microbenchmark of the unit registry and the ticket pool.
-- Feeds N synthetic rows (plate, target and soft tokens of one outcome, our successes and swings among them) through
-- the event facade into a booted VirtualState and times them, then times the per-frame tick. Prints rows/s, ms/row and
-- ms/tick; fails above 0.02 ms a row or 0.10 ms a tick, or below 0.8 x tools/bench_ta_floor.lua's rows/s.
-- Run: make bench-ta (or lua5.1 tools/bench_ta.lua [N]).
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

local api, ctl = fake.new()
for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
    _G[k] = v
end
local ns = load.module()
local I = ns.VirtualStateInternal
I.Build(fs.def(fs.new(9, false, false, true)), 0.1)
ns.VirtualState.Start(api)
local TOK = {}
for k = 1, 40 do
    TOK[k] = "nameplate" .. k
    ctl.guid[TOK[k]] = "Creature-" .. k
    ctl.Fire("NAME_PLATE_UNIT_ADDED", TOK[k])
end
ctl.guid.softenemy = "Creature-1"
local FAN = { "nameplate1", "target", "softenemy" }

local N = tonumber(arg and arg[1]) or 200000
local now = 10
collectgarbage("collect")
local t0 = os.clock()
for i = 1, N do
    now = now + 0.001
    ctl.now = now
    if i % 50 == 0 then
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
    elseif i % 37 == 0 then
        ctl.Fire("PLAYER_SWING", 2.0, 0)
    end
    local k = i % 3 + 1
    ctl.Fire("UNIT_COMBAT", FAN[k], "WOUND", "", 30 + i % 11, i % 7 == 0 and 4 or 1)
end
local row = (os.clock() - t0) / N

local M = 20000
local t1 = os.clock()
for _ = 1, M do
    now = now + 0.016
    ctl.Tick(now)
end
local tick = (os.clock() - t1) / M

local floor = dofile("tools/bench_ta_floor.lua").rowsPerSec
print(("bench-ta rows=%d rows/s=%.0f ms/row=%.4f ms/tick=%.4f (floor rows/s %d)"):format(
    N, 1 / row, row * 1000, tick * 1000, floor))
if row * 1000 >= 0.02 or tick * 1000 >= 0.10 or 1 / row < 0.8 * floor then
    print("bench-ta: over budget or under the floor")
    os.exit(1)
end
```

In `Makefile`, add `bench-ta` to the `.PHONY` list (line 9) and after the `bench:` target (line 60):

```make
# The unit registry and ticket pool microbenchmark (unit-registry spec §10): rows/s, ms/row and ms per frame tick
# against hard budgets and a rows/s floor (tools/bench_ta_floor.lua); not part of `check`.
bench-ta:
	$(LUA) tools/bench_ta.lua
```

- [ ] **Step 6: Record the floor**

Run: `make bench-ta`
Expected: one line `bench-ta rows=200000 rows/s=<R> ms/row=<r> ms/tick=<k> (floor rows/s 0)`, exit 0, with
`<r>` < 0.02 and `<k>` < 0.10. Write `<R>` rounded down to a thousand into `tools/bench_ta_floor.lua`
(`return { rowsPerSec = <R> }`), then run `make bench-ta` again: exit 0.

- [ ] **Step 7: Run every spec touched**

Run: `.lua/bin/busted tests/Game/State/memory_spec.lua tests/Game/Events/saturation_spec.lua tests/Game/harness/alloc_spec.lua tests/Game/State/alloc_spec.lua && make test-fast`
Expected: PASS, 0 failures.

- [ ] **Step 8: Commit**

```bash
git add src/Hekili/Game/State/Sources/Units.lua src/Hekili/Game/State/Adapter.lua tests/Game/State/memory_spec.lua \
  tests/Game/Events/saturation_spec.lua tests/Game/harness/alloc_spec.lua tools/bench_ta.lua tools/bench_ta_floor.lua \
  Makefile
git commit -m "perf(units): memory ceiling, saturation and allocation specs; make bench-ta with its floor

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 16: Pack data pass (casters and Hunter)

**Files:**
- Modify: `src/Hekili_Druid/Druid.lua:1754`, `:1659`, `:1325`, `:1216` (abilities), `:518`, `:489` (the Moonfire
  and Insect Swarm auras gain `dot = "debuff"`); `src/Hekili_Hunter/Hunter.lua:232` (the Serpent Sting aura, likewise); `src/Hekili_Warlock/Warlock.lua:803`, `:785`,
  `:709`, `:439`; `src/Hekili_Mage/Mage.lua:484`, `:441`, `:399`, `:378`; `src/Hekili_Shaman/Shaman.lua:434`, `:378`;
  `src/Hekili_Priest/Priest.lua:681`; `src/Hekili_Paladin/Paladin.lua:428`; `src/Hekili_Hunter/Hunter.lua:442`,
  `:426`, `:408`, `:370`, `:353`, `:295` (one line inserted after each ability's `id = ...,` line)
- Modify: `docs/dev/wowsims-packs.md:196-211` (Pack notes: the expected upward moves)
- Test: `tests/Forever/expects_spec.lua` (new)

**Interfaces:**
- Consumes: `I.Expect.Malformed(obj, e, k, s, au)` (Task 4), `I.Expect.KIND`, `ns.SCHOOL`; the recording pack loader
  (`tests/Forever/helpers/load_druid.lua:18`, as `tests/boundary_lib.lua:6-48` uses it).
- Produces: the declarations of spec §5.4 as amended (no `ticks`/`tickPeriod`: a ticking ability reads its aura's
  `tick_time` and `duration`, which the packs already declare, plus upstream's aura field `dot = "debuff"` on each
  DoT aura: a declared instant or projectile whose aura has both also ticks; the abilities carry only `expects`,
  `school` and `velocity`), and Starfire
  and Insect Swarm, named by the owner's scope (DB2 `SpellMisc.Speed` 0 and `SchoolMask` 64 on all seven Starfire
  ranks; Insect Swarm `SchoolMask` 8, a 2 s `EffectAuraPeriod` over a 12 s `SpellDuration` on all five ranks, no
  direct hit, its aura already `tick_time = 2`, `Druid.lua:489`); melee packs untouched (default types).
- Boundary: packs declare data only; no matching code.

The Moonfire aura's duration per rank, checked against DB2 (`SpellDuration` through `SpellMisc.DurationIndex`): rank 1
(8921) lasts 9000 ms and every later rank (8924-9835) 12000 ms, each with a 3000 ms `EffectAuraPeriod`. The pack's
aura (`Druid.lua:512-519`) already answers `(knownRank(MOONFIRE) > 1 and 12 or 9) + 3 x Nature's Splendor`, so rank 1
owes 3 ticks (+3, +6, +9 s), as the druid-moonfire capture shows before its 9.8 s recast; the step below re-reads DB2
and changes the aura only if a rank disagrees. Whether an unrefreshed rank-1 Moonfire ever ticks a fourth time at +12 s
is an in-game check (Task 19's UR4), not assumed. Starfire and Insect Swarm are declared because the owner's scope
names them; spec §5.4 does not, and its note allows any instant to declare its school. Each ticking ability's aura is
resolved as the simulation does (`cycle`, else `aura`, else its key), and the spec asserts that aura declares a
`tick_time`.

- [ ] **Step 1: Write the failing test** `tests/Forever/expects_spec.lua`:

```lua
-- tests/Forever/expects_spec.lua (unit-registry spec §5.4): the casters' and Hunter's declared outcomes, as each pack
-- registers them, are well formed by Families/Expect.lua's own rule and match the spec's table.
local load = require("Game.State.helpers.load")
local loader = require("Forever.helpers.load_druid")

-- { expects, velocity, school } as each pack registers them; TICKING: the abilities whose aura (cycle, aura or key)
-- must declare a tick_time and dot = "debuff"
local TICKING = { moonfire = true, insect_swarm = true, serpent_sting = true }
local DECLARED = {
    Druid = {
        wrath = { "travel", 20, "nature" },
        starfire = { "instant", nil, "arcane" },
        moonfire = { "instant", nil, "arcane" },
        insect_swarm = { "ticks", nil, "nature" },
    },
    Warlock = {
        shadow_bolt = { "travel", 20, "shadow" },
        incinerate = { "travel", 20, "fire" },
        soul_fire = { "travel", 24, "fire" },
        death_coil = { "travel", 24, "shadow" },
    },
    Mage = {
        frostbolt = { "travel", 28, "frost" },
        fireball = { "travel", 24, "fire" },
        pyroblast = { "travel", 24, "fire" },
        frostfire_bolt = { "travel", 24, nil },
    },
    Shaman = { lightning_bolt = { "travel", 20, "nature" }, lava_burst = { "travel", 20, "fire" } },
    Priest = { shoot = { "travel", 20, "physical" } },
    Paladin = { hammer_of_wrath = { "travel", 35, "holy" } },
    Hunter = {
        auto_shot = { "travel", 40, "physical" },
        aimed_shot = { "travel", 40, "physical" },
        arcane_shot = { "travel", 40, "arcane" },
        multi_shot = { "travel", 30, "physical" },
        sniper_shot = { "travel", 60, "physical" },
        serpent_sting = { "ticks", 40, "nature" },
    },
}

describe("the packs' declared outcomes", function()
    local ns = load.module()
    local X = ns.VirtualStateInternal.Expect

    for class, list in pairs(DECLARED) do
        it(class .. ": each declaration is the spec's and well formed", function()
            local w = loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
            for key, want in pairs(list) do
                local d = assert(w.abilities[key], key)
                assert.are.same(want, { d.expects, d.velocity, d.school }, key)
                local s = d.school and ns.SCHOOL[d.school] or nil
                local au = w.auras[d.cycle or d.aura or key] -- resolved as the simulation does
                if TICKING[key] then
                    assert.is_truthy(au and au.tick_time and au.dot == "debuff", key .. ": its aura is no debuff dot")
                end
                assert.is_nil(X.Malformed(d, d.expects, X.KIND[d.expects], s, au and au.tick_time and au or nil), key)
            end
        end)
    end

    it("leaves the melee packs on their default types", function()
        for _, class in ipairs({ "Warrior", "Rogue" }) do
            local w = loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
            for key, d in pairs(w.abilities) do
                assert.is_nil(d.expects, class .. " " .. tostring(key))
            end
        end
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Forever/expects_spec.lua`
Expected: FAIL, `attempt to call field 'Malformed' (a nil value)`, then the declarations missing.

- [ ] **Step 3: Check Moonfire's aura against DB2.**

Run: `python3 -c "import sqlite3,os; c=sqlite3.connect(os.path.expanduser('~/.local/share/wow-db2/forever/current.sqlite')); print([(i, c.execute('select d.Duration from SpellMisc m join SpellDuration d on d.ID = m.DurationIndex where m.SpellID = ?', (i,)).fetchone()[0], c.execute('select EffectAuraPeriod from SpellEffect where SpellID = ? and EffectAura = 3', (i,)).fetchone()[0]) for i in (8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835)])"`
Expected: `[(8921, 9000, 3000), (8924, 12000, 3000), ..., (9835, 12000, 3000)]`, which the aura's duration function
already answers (`Druid.lua:515-517`): leave it. If a rank differs, set the aura's duration function to DB2's value
for that rank (one `knownRank` branch per distinct duration) and note it in the commit.

- [ ] **Step 4: Declare the data.** Each command inserts one line after the ability's `id = ...,` line; within a file
  they run bottom-up so the line numbers hold:

```bash
D='        '
sed -i -e "1754a\\${D}expects = \"travel\", velocity = 20, school = \"nature\"," \
  -e "1659a\\${D}expects = \"instant\", school = \"arcane\"," \
  -e "1325a\\${D}expects = \"instant\", school = \"arcane\", -- its debuff dot aura ticks every 3 s, 9 or 12 s by rank" \
  -e "1216a\\${D}expects = \"ticks\", school = \"nature\", -- its debuff dot aura: 2 s ticks over 12 s" \
  -e "518a\\${D}dot = \"debuff\", -- upstream's aura field (Engine/Sim/State.lua:3302): Moonfire's schedule" \
  -e "489a\\${D}dot = \"debuff\", -- Insect Swarm's schedule" src/Hekili_Druid/Druid.lua
sed -i -e "803a\\${D}expects = \"travel\", velocity = 24, school = \"fire\"," \
  -e "785a\\${D}expects = \"travel\", velocity = 20, school = \"fire\"," \
  -e "709a\\${D}expects = \"travel\", velocity = 24, school = \"shadow\"," \
  -e "439a\\${D}expects = \"travel\", velocity = 20, school = \"shadow\"," src/Hekili_Warlock/Warlock.lua
sed -i -e "484a\\${D}expects = \"travel\", velocity = 24, -- no school: DB2 mask 20 (fire and frost), U7 deferred" \
  -e "441a\\${D}expects = \"travel\", velocity = 24, school = \"fire\"," \
  -e "399a\\${D}expects = \"travel\", velocity = 24, school = \"fire\"," \
  -e "378a\\${D}expects = \"travel\", velocity = 28, school = \"frost\"," src/Hekili_Mage/Mage.lua
sed -i -e "434a\\${D}expects = \"travel\", velocity = 20, school = \"fire\"," \
  -e "378a\\${D}expects = \"travel\", velocity = 20, school = \"nature\"," src/Hekili_Shaman/Shaman.lua
sed -i -e "681a\\${D}expects = \"travel\", velocity = 20, school = \"physical\", -- the wand's school: U7 deferred" \
  src/Hekili_Priest/Priest.lua
sed -i -e "428a\\${D}expects = \"travel\", velocity = 35, school = \"holy\"," src/Hekili_Paladin/Paladin.lua
sed -i -e "442a\\${D}expects = \"travel\", velocity = 60, school = \"physical\"," \
  -e "426a\\${D}expects = \"travel\", velocity = 30, school = \"physical\", -- pays the pinned target's row only" \
  -e "408a\\${D}expects = \"travel\", velocity = 40, school = \"physical\"," \
  -e "370a\\${D}expects = \"travel\", velocity = 40, school = \"arcane\"," \
  -e "353a\\${D}expects = \"ticks\", school = \"nature\", velocity = 40, -- its debuff dot aura: 3 s over 15 s" \
  -e "295a\\${D}expects = \"travel\", velocity = 40, school = \"physical\"," \
  -e '232s/tick_time = 3, max_stack = 1 }/tick_time = 3, dot = "debuff", max_stack = 1 }/' src/Hekili_Hunter/Hunter.lua
```

  (`sed` applies every `-e` to the original numbering in one pass, so the order within a command does not matter.)

- [ ] **Step 5: Pack notes.** In `docs/dev/wowsims-packs.md`, at the end of "## Pack notes" (before line 212), add:

```markdown
Casters and Hunter (unit-registry spec §5.4, 2026-10-22): each projectile, DoT and shot declares `expects` with its
DB2 `velocity` and `school` (checked by `make spell-data-check`). Their outcomes now pay their own casts (a projectile's
landing up to `rMax / velocity + 0.15` s after its success), so `SPELL_DAMAGE` rows reach Hekili's enemy tracker for
the first time (`ns.updateTarget`, `Engine/Sim/Events.lua:1735-1743`). Expected: the replay floors of Balance,
Affliction, Destruction, Demonology, Arcane, Fire, Frostfire, Elemental, Shadow, Smite and the three Hunter specs rise
or hold (crits now run `onCrit`, misses refund); an AoE line's target count may read higher, each such move named in
the gate's report. The melee packs keep their default types (unchanged).
```

- [ ] **Step 6: Run it, then the class specs and packs check**

Run: `.lua/bin/busted tests/Forever/expects_spec.lua tests/boundary_spec.lua && make test-fast && make packs-check`
Expected: PASS (8 successes in `expects_spec.lua`; `packs-check` reports no diff: the declarations live outside the
generated RegisterPack blocks).

- [ ] **Step 7: Commit**

```bash
git add src/Hekili_Druid/Druid.lua src/Hekili_Warlock/Warlock.lua \
  src/Hekili_Mage/Mage.lua src/Hekili_Shaman/Shaman.lua src/Hekili_Priest/Priest.lua src/Hekili_Paladin/Paladin.lua \
  src/Hekili_Hunter/Hunter.lua docs/dev/wowsims-packs.md tests/Forever/expects_spec.lua
git commit -m "feat(packs): casters and Hunter declare expects, velocity and school from DB2

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 17: `make spell-data-check`

**Files:**
- Create: `tools/check_spell_data.lua` (dumps every pack's declarations and ranks as tab-separated lines)
- Create: `tools/check_spell_data.py` (reads `$WOW_DB2` with sqlite3 and checks them)
- Create: `tests/tools/test_check_spell_data.py` (offline: an in-memory DB2 subset)
- Modify: `Makefile:9-10` (`.PHONY`), after the `bench-ta` target (target `spell-data-check`)

**Interfaces:**
- Consumes: the recording pack loader; DB2 tables `SpellMisc` (`SpellID`, `Speed`, `SchoolMask`) and `SpellEffect`
  (`SpellID`, `EffectAura` 3 = periodic damage, `EffectAuraPeriod` ms), from `$WOW_DB2` (default
  `~/.local/share/wow-db2/forever/current.sqlite`).
- Produces: `make spell-data-check` (dev-only, outside `make check`: CI has no DB2 file); `check(rows, db) -> errors,
  notes` in the Python module.
- Boundary: tools only.

Implementation choice: the Lua side loads the packs (the only code that can run them) and prints
`class key ids velocity school tick_time startsCombat expects` per ability (`tick_time`: the ticking aura's, resolved
`cycle or aura or key`, a number or `fn`; empty when the ability does not tick); the Python side owns every DB2 read,
as the spec's SQL mode does. A ticking aura's `tick_time` is compared with each listed rank's periodic damage
`EffectAuraPeriod` and a difference is a note, never a failure (owner ruling: an aura may be rank-generic); a
function `tick_time` is not compared.

- [ ] **Step 1: Write the failing test** `tests/tools/test_check_spell_data.py`:

```python
"""tools/check_spell_data.py against an in-memory DB2 subset (unit-registry spec §5.5)."""
import sqlite3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import check_spell_data as csd  # noqa: E402


def db():
    c = sqlite3.connect(":memory:")
    c.executescript(
        """
        create table SpellMisc (SpellID int, Speed real, SchoolMask int, DurationIndex int);
        create table SpellDuration (ID int, Duration int);
        create table SpellEffect (SpellID int, EffectAura int, EffectAuraPeriod int);
        insert into SpellMisc values (10, 20, 8, 0), (11, 20, 8, 0), (20, 24, 20, 0), (30, 0, 64, 1), (31, 0, 64, 2);
        insert into SpellMisc values (40, 35, 1, 0);
        insert into SpellDuration values (1, 9000), (2, 12000);
        insert into SpellEffect values (30, 3, 3000), (31, 3, 3000);
        """
    )
    return c


def row(key, ids, velocity="", school="", tick="", starts="1", expects="travel"):
    return ["C", key, ",".join(map(str, ids)), velocity, school, tick, starts, expects]


class CheckTest(unittest.TestCase):
    def test_agreeing_declarations_pass(self):
        errors, notes = csd.check([row("bolt", [10, 11], "20", "nature")], db())
        self.assertEqual([], errors)

    def test_a_velocity_off_any_rank_fails(self):
        errors, _ = csd.check([row("bolt", [10, 11], "24", "nature")], db())
        self.assertEqual(1, len(errors))

    def test_a_school_name_off_the_mask_fails_and_a_two_school_mask_says_leave_it_nil(self):
        errors, _ = csd.check([row("bolt", [10], "20", "fire"), row("ffb", [20], "24", "frost")], db())
        self.assertEqual(2, len(errors))
        self.assertIn("leave school nil", errors[1])

    def test_a_projectile_that_starts_combat_must_declare_its_velocity(self):
        errors, _ = csd.check([row("shot", [40], expects="")], db())
        self.assertEqual(1, len(errors))

    def test_an_aura_tick_time_off_the_period_is_a_note_never_a_failure(self):
        errors, notes = csd.check([row("dot", [30, 31], "", "arcane", "3", expects="instant")], db())
        self.assertEqual(([], []), (errors, notes))
        errors, notes = csd.check([row("dot", [30, 31], "", "arcane", "2", expects="instant")], db())
        self.assertEqual(([], 2), (errors, len(notes)))
        errors, notes = csd.check([row("dot", [30, 31], "", "arcane", "fn", expects="instant")], db())
        self.assertEqual(([], []), (errors, notes))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it**

Run: `python3 -m unittest discover -s tests/tools -t tests/tools -p "test_check_spell_data.py"`
Expected: FAIL, `ModuleNotFoundError: No module named 'check_spell_data'`.

- [ ] **Step 3: Implement** `tools/check_spell_data.py`:

```python
#!/usr/bin/env python3
"""The DB2 check of the packs' declared outcomes (unit-registry spec §5.5). Dev-only: `make spell-data-check`.

Reads tools/check_spell_data.lua's tab-separated lines on stdin (class, key, ids, velocity, school, tick_time,
startsCombat, expects) and $WOW_DB2 (default ~/.local/share/wow-db2/forever/current.sqlite). Fails when a declared
velocity differs from SpellMisc.Speed on any listed rank; when a declared school's name differs from SchoolMask's on
any listed rank (a mask with no single name: the pack leaves `school` nil); when an ability that starts combat has
Speed > 0 on its first rank and declares no velocity (a "ticks" ability's velocity is optional). A ticking aura's
tick_time that differs from a rank's periodic damage EffectAuraPeriod is a note (an aura may be rank-generic).
"""
import os
import sqlite3
import sys

SCHOOL = {"physical": 1, "holy": 2, "fire": 4, "nature": 8, "frost": 16, "shadow": 32, "arcane": 64}
NAME = {v: k for k, v in SCHOOL.items()}


def misc(db, sid):
    return db.execute("select Speed, SchoolMask from SpellMisc where SpellID = ?", (sid,)).fetchone()


def periodic(db, sid):
    r = db.execute("select EffectAuraPeriod from SpellEffect where SpellID = ? and EffectAura = 3", (sid,)).fetchone()
    return r[0] if r else 0


def check(rows, db):
    errors, notes = [], []
    for cls, key, ids, velocity, school, tick, starts, expects in rows:
        ranks = [int(i) for i in ids.split(",") if i]
        where = f"{cls} {key}"
        data = [(sid, misc(db, sid)) for sid in ranks]
        data = [(sid, m) for sid, m in data if m]
        if not data:
            continue
        for sid, (speed, mask) in data:
            if velocity and float(velocity) != speed:
                errors.append(f"{where}: velocity {velocity} but SpellMisc {sid} Speed {speed:g}")
            if school:
                name = NAME.get(mask)
                if name is None:
                    errors.append(f"{where}: SchoolMask {mask} of {sid} has no single name: leave school nil")
                elif name != school:
                    errors.append(f"{where}: school {school} but SpellMisc {sid} SchoolMask {mask} ({name})")
        first_speed = data[0][1][0]
        if starts == "1" and first_speed > 0 and not velocity and expects != "ticks":
            errors.append(f"{where}: Speed {first_speed:g} on {data[0][0]} but no velocity declared")
        if tick and tick != "fn":
            for sid, _ in data:
                p = periodic(db, sid)
                if p and float(tick) * 1000 != p:
                    notes.append(f"{where}: aura tick_time {tick} s but {sid} EffectAuraPeriod {p} ms")
    return errors, notes


def main():
    path = os.environ.get("WOW_DB2", os.path.expanduser("~/.local/share/wow-db2/forever/current.sqlite"))
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    rows = [line.rstrip("\n").split("\t") for line in sys.stdin if line.strip()]
    errors, notes = check(rows, db)
    for n in notes:
        print("note: " + n)
    for e in errors:
        print("FAIL: " + e)
    print(f"spell-data-check: {len(rows)} abilities, {len(errors)} failures, {len(notes)} notes")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
```

`tools/check_spell_data.lua`:

```lua
-- tools/check_spell_data.lua (unit-registry spec §5.5): prints every class pack's abilities that start combat or
-- declare `expects`, one tab-separated line each (class, key, ids, velocity, school, tick_time, startsCombat,
-- expects), for tools/check_spell_data.py; tick_time is the ticking aura's (resolved `cycle or aura or key`, as the
-- simulation does; `fn` for a function; empty when the ability does not tick). Loads each pack through the recording
-- loader the specs use.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local loader = require("Forever.helpers.load_druid")

local CLASSES = { "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior" }
for _, class in ipairs(CLASSES) do
    local w = loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
    local keys = {}
    for key, d in pairs(w.abilities) do
        if type(key) == "string" and type(d) == "table" and (d.startsCombat or d.expects) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local d = w.abilities[key]
        local ids = { type(d.id) == "number" and d.id or nil }
        for _, c in ipairs(type(d.copy) == "table" and d.copy or { d.copy }) do
            if type(c) == "number" then
                ids[#ids + 1] = c
            end
        end
        local function s(v)
            return v == nil and "" or tostring(v)
        end
        local au = w.auras[d.cycle or d.aura or key]
        local tick = ""
        if type(au) == "table" and (d.expects == "ticks" or d.expects == "channel" or au.dot == "debuff") then
            tick = type(au.tick_time) == "function" and "fn" or s(au.tick_time)
        end
        print(table.concat({
            class,
            key,
            table.concat(ids, ","),
            s(d.velocity),
            s(d.school),
            tick,
            d.startsCombat and "1" or "0",
            s(d.expects),
        }, "\t"))
    end
end
```

In `Makefile`, add `spell-data-check` to `.PHONY` and after the `bench-ta` target:

```make
# The packs' declared expects/velocity/school/ticks against DB2 (unit-registry spec §5.5): SpellMisc, SpellDuration,
# SpellEffect from $WOW_DB2; dev-only, outside `make check` (CI has no DB2 file).
spell-data-check:
	$(LUA) tools/check_spell_data.lua | python3 tools/check_spell_data.py
```

- [ ] **Step 4: Run the unit test, then the real check**

Run: `python3 -m unittest discover -s tests/tools -t tests/tools && make spell-data-check`
Expected: the unit tests pass (5); the check ends `spell-data-check: <n> abilities, 0 failures, <m> notes`, exit 0
(each note names an aura whose `tick_time` differs from a rank's `EffectAuraPeriod`; none is expected for Moonfire,
Insect Swarm or Serpent Sting, whose auras match DB2). A failure on a melee pack's ability (rule 3: Speed > 0 with no velocity, for example a thrown weapon)
stops the task for the owner's ruling: spec §5.4 keeps melee packs on their default type while §5.5's third rule
covers every pack.

- [ ] **Step 5: Commit**

```bash
git add tools/check_spell_data.lua tools/check_spell_data.py tests/tools/test_check_spell_data.py Makefile
git commit -m "feat(tools): make spell-data-check: the packs' declared outcomes against DB2

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 18: The gate

**Files:**
- Modify (only to raise a floor, with its named cause beside the number): `tests/Forever/wowsims_*_spec.lua`, the
  loop specs' flicker and recall floors, `tests/Game/harness/detect_floors.lua`, `tools/bench_ta_floor.lua`
- Create: nothing else

**Interfaces:**
- Consumes: every task above.
- Produces: the gate report in the merge commit message: every floor that moved, up or down, with its named cause.
- Boundary: no engine change here. A floor that moves down stops the branch for the owner's ruling; it is never
  lowered in this task.

- [ ] **Step 1: The full check**

Run: `make check`
Expected: exit 0 (lint, StyLua, LuaLS, every busted spec including the #slow harness and wowsims tiers, syntax,
api-check with `tools/api_inventory.txt` unchanged: no new client API is read, the reads moved into `Units.lua`
through the same `api`, packs-check, tools-test).

- [ ] **Step 2: The loops**

Run: `make test-loop`
Expected: exit 0. Read each loop's printed recall and flicker per minute against its floor.

- [ ] **Step 3: The wowsims replay floors for every class**

Run: `make test-wowsims 2>&1 | tee /tmp/wowsims-gate.txt && grep -E "wowsims:.*decisions on-GCD" /tmp/wowsims-gate.txt`
Expected: exit 0; one `decisions on-GCD X (n)` line per pack. For every caster pack (Balance, the three Warlock
specs, Arcane, Fire, Frostfire, Elemental, Shadow, Smite, the three Hunter specs) whose number rose, raise its floor in
`tests/Forever/wowsims_<class>_spec.lua` to the new value truncated to two decimals, with the comment
`-- <value> (<n>/<m>) on the unit registry and tickets (central fix 32: projectile, DoT and miss rows pay their casts)`
beside it (docs/dev/wowsims-packs.md "Re-flooring"). A change in an AoE line's target count (`active_enemies`, spec
§7) is named in the report. A melee pack's number that moves at all, or any number that falls, stops the branch:
report the pack, the old and new value and the first decision that changed.

- [ ] **Step 4: The detection suite, the sweep, the captures**

Run: `.lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua tests/Game/harness/detect_sweep_spec.lua tests/Game/harness/captures_spec.lua`
Expected: PASS against `detect_floors.lua`.

- [ ] **Step 5: Performance**

Run: `make bench-ta && .lua/bin/busted tests/Game/State/alloc_spec.lua tests/Game/harness/alloc_spec.lua tests/Game/State/memory_spec.lua tests/Game/Events/saturation_spec.lua && make bench`
Expected: `bench-ta` exits 0 at or above its floor (raise `tools/bench_ta_floor.lua` if the number rose by more than
10%); the alloc, memory and saturation specs pass; `make bench`'s per-Update time and allocation are reported beside
the base commit's (`git stash` is not needed: run it on `origin/forever` in a second worktree) and show no new
allocation.

- [ ] **Step 6: The merge gate**

Run: `make gate`
Expected: exit 0.

- [ ] **Step 7: Commit the raised floors**

```bash
git add tests/Forever/wowsims_*_spec.lua tests/Game/harness/detect_floors.lua tools/bench_ta_floor.lua
git commit -m "test(wowsims): re-floor the casters on the unit registry and tickets

<each pack: old -> new floor (n/m), and any AoE line whose count moved, with its cause>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

(The angle-bracket line is the report the run produced, one line per pack; if no floor rose, skip this commit.)

---

### Task 19: Docs and ledger

**Files:**
- Modify: `docs/dev/gaps.md:54` ("Travel time"), `:56` ("Unmapped-success window"); new rows after `:56`
- Modify: `docs/dev/ingame-ledger.md` (rows after `:30`)
- Modify: `DEVELOPMENT.md:276-281` (a subsection after "### Adding a class")
- Modify: `docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md:1-3` (status line)

**Interfaces:**
- Consumes: the findings of Tasks 7, 8, 10, 15-18.
- Produces: docs only. (Hekili has no `docs/api` or `make apiref`; the internal `I.Units`, `I.Tickets`, `I.Kinds`
  functions carry `---` doc comments in their files.) The union-belief work of spec §4.2 is not in this plan; it
  stays a gaps row with its build trigger.

- [ ] **Step 1: gaps.md.** Replace the "Travel time" row (line 54) with:

```markdown
| Travel time | An aura consumed when the hit lands, not at the end of the cast (Elemental's Revelation is spent on landing), so the belief spends it a travel time early; 2 Elemental replay decisions, and Mage has the same issue. The other half (Warlock lane's G6: a projectile's crit and miss past `CAST_WINDOW`) is fixed by central fix 32: a projectile's ticket pays its landing (`Events/Kinds.lua` FLIGHT), so `onCrit` and the avoid refund run at the landing | core belief | Elemental, Mage |
```

  Replace the "Unmapped-success window" row's text `(\`Events/Rows.lua\` \`another()\`)` with
  `(the UNMAPPED ticket, \`Events/Kinds.lua\` and \`Events/Tickets.lua\`)` and its layer cell with
  `core belief (\`Events/Tickets.lua\`)`. After it add:

```markdown
| Divergent ambiguity | Two candidate tickets whose choice changes a belief (hit vs miss, hit vs crit, swing rage: unit-registry spec §4.2) stage nothing and count `divergent`; the union belief that would keep both is designed, not built. Build trigger: Snapshot's `divergent` above 1 per 100 paid in a five-man run, or the detection suite's busy band (K13) above that with a flicker cost | core belief | in-game UR2 |
| Two-school spells and wands | Frostfire Bolt (DB2 mask 20) declares no `school`, and a wand's school may differ from Shoot's mask (U7, deferred by owner ruling): their WOUNDs pay only by an avoid until measured | kit + core | in-game U7 |
| Resist, immune, absorb shapes | `SPELL_MISSED` with RESIST, IMMUNE, ABSORB, EVADE are emitted from rows never captured (U1, U6, deferred); partial resists unmodelled | core belief | in-game U1, U6 |
| Channel ticks | The CHANNEL kind is implemented and tested against the harness's own tick model only; no pack declares it (U9's channel half, deferred) | core belief | in-game U9 |
| Rank-generic aura periods | A ticking kind reads its aura's `tick_time` and `duration` at the commit (owner ruling 2026-10-22); an aura whose `tick_time` is one number for every rank while DB2's `EffectAuraPeriod` differs by rank pays its ticks on the wrong schedule for those ranks; `make spell-data-check` notes each such rank | kit | none known |
| FLIGHT's first record | Spec §3.3.1 lets only passes (a) and (b) teach a lag record, which no first ticket reaches; the build teaches from any clean payment, pass (c) included (a recorded deviation) | core belief | none |
| `closedGone` | A unit with an open ticket is held, so it never goes GONE while a ticket pins it; the `gone` close is reachable only through a registry reset and stays at 0 in every run | core belief | none |
| Harness pushback | The DELAYED pushback row is opt-in in the harness (`pushback`), off in the class loops (it would move the player's rows 0.37 s and the onus floors); the kill shapes follow the captures (`killTiming`) | harness | none |
```

- [ ] **Step 2: ingame-ledger.md.** After the PV1 row (line 30) add:

```markdown
| UR1 | Core | the unit registry in a five-man pull: the Snapshot's `units` line (`unresolved`, `dup`, `evicted`, deaths by `tell`/`poll`/`event`) after a pull of three or more mobs | the registry's resolution and dedupe were measured solo and on two plates (U5); a high `unresolved` or any `evicted` while fighting means the token set or the pool size is wrong | open |
| UR2 | Core | the tickets in a five-man run: the Snapshot's `tickets` line (`paid`, `lost`, `divergent`, `bandRejected`, `aoeOther`) | `divergent` above 1 per 100 paid is the build trigger of the union belief (unit-registry spec §4.2); `lost` on a caster means a projectile row is not seen | open |
| UR3 | Core | a caster's kill: the target's modelled debuffs end at the death (no `SPELL_AURA_REMOVED` 16 s later in a `/vslog`); `deaths event=` counts it | the death events are the primary kill tell (U3); this confirms TargetGone reaches the belief | open |
| U1 | Core | RESIST, IMMUNE, ABSORB, EVADE rows: `/vslog` with UNIT_COMBAT while casting a school the mob is immune to (an Elemental at a fire mob) and a mob that evades (leash) | the untested `SPELL_MISSED` branches (deferred by owner ruling 2026-10-22) | open |
| U6 | Core | partial resists: a `/vslog` of a Shadow Bolt series on a mob with shadow resistance (a WOUND with a RESIST flag and a reduced amount, or two rows) | the amount band and the school check assume one row per hit | open |
| U7 | Core | two-school spells and wands: the school a Frostfire Bolt WOUND carries (20, 4 or 16) and a non-physical wand's Shoot | Frostfire Bolt and Shoot keep no or a guessed `school` until then | open |
| U9 | Core | channel rows: `/vslog` of Arcane Missiles and Drain Life on solo mobs: per tick, which tokens, action, flag, amount, school | CHANNEL stays unused by packs until its shape is measured | open |
| UR4 | Druid | an unrefreshed rank-1 Moonfire (8921, level 4-9): does a fourth tick come at +12 s? DB2 gives 9 s (3 ticks); the pack's aura answers 9 s | the TICKS ticket owes the aura's count; a fourth tick would be foreign | open |
| UR5 | Warrior | a fast dual-wield Fury (two 1.5 s weapons, about 20% haste): the Snapshot's `rows credited main/off` against the swings, and est against the real rage a few seconds after a usability pin | the harness's K14f credit rate (Task 13 prints it; copy the party-band number here) against the game's: the owner's level-25 session credited about 23% and read est 42.6 at about 100 real rage before Task 9b | open |
| U10 | Core | ten pulls with auto-attack only: `PLAYER_SWING`, `PLAYER_ENTER_COMBAT` and the target's UNIT_COMBAT, amounts on | the first swing of a combat (one sample: 989 ms) does not teach the lag; this measures its lag distribution | open |
```

- [ ] **Step 3: DEVELOPMENT.md.** After the "### Adding a class" paragraph (line 281), add:

```markdown
### Declaring what an ability's hit looks like (`expects`)

The client gives addons no combat log. The core pays each outcome it sees on a unit (a hit, a miss, a tick) to the
cast that made it by a ticket, and a pack tells the core what to expect from each ability with plain data on the
ability, never code:

- `expects`: one of `"none"` (owes no row: a buff), `"instant"` (its row comes in the same frame), `"travel"` (a
  projectile: `velocity` in yards a second, DB2 `SpellMisc.Speed`), `"strike"` (on the next swing), `"ticks"` (a
  DoT with no direct hit), `"channel"` (opt-in, untested in game; no pack uses it). `"melee"` is the core's own.
- A ticking kind reads the aura the ability applies (`cycle`, else `aura`, else the ability's key, as the simulation
  does): its `tick_time` is the period and `floor(duration / tick_time)` the count, read at each cast (a function
  is called in Hekili's state). There are no `ticks`, `tickPeriod` or `dot` fields on the ability.
- `school`: the client's school by name, `"physical"`, `"holy"`, `"fire"`, `"nature"`, `"frost"`, `"shadow"` or
  `"arcane"` (`Hekili.SCHOOL`); leave it out when the spell's mask has no single name.
- A declared `"instant"` or `"travel"` ability whose aura has a `tick_time` and upstream's `dot = "debuff"` also
  ticks (a hit that then ticks); `"ticks"` needs the same two aura fields; `velocity` may join `"ticks"`
  (a DoT that flies).

An ability with no `expects` keeps the default: `"strike"` with `onNextSwing`, `"instant"` with `startsCombat`, else
`"none"`. A malformed declaration shows in the Snapshot's error count and falls back to the default. Check the numbers
against DB2 with `make spell-data-check` (it needs `$WOW_DB2`). The design is
[docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md](docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md).
```

- [ ] **Step 4: The spec's status and §3.3.1.** In the spec's status line (line 3), replace `Status: DESIGNED.` with
  `Status: BUILT (docs/superpowers/plans/2026-10-22-unit-registry-and-tickets.md); §4.2's union belief designed, not built.`
  In §3.3.1 (line 349), replace `A FLIGHT ticket paid in pass (a) or (b) (3.4) with no other candidate in that pass
  teaches its record:` with `A FLIGHT ticket paid in any pass (3.4) with no other candidate in that pass teaches its
  record (a pass (c) payment makes the first record: with none, a ticket is a candidate in pass (c) only, so no record
  would ever exist):`, and in the gaps row "FLIGHT's first record" (Step 1) replace `(a recorded deviation)` with
  `(spec §3.3.1 amended to match)`.

- [ ] **Step 5: Check and commit**

Run: `make check`
Expected: exit 0.

```bash
git add docs/dev/gaps.md docs/dev/ingame-ledger.md DEVELOPMENT.md \
  docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md
git commit -m "docs: unit registry and tickets: gaps, in-game ledger, the expects guide, spec status

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```
