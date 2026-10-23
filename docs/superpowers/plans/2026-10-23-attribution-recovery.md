# Attribution Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Always expect a result for our commits: a row outside every lag band still pays the oldest ticket of its
queue (Overdue), a payment outside the narrow band stays replaceable until that band passes, and a ticket past its lag
tolerance is assumed (a swing's rage believed at once) and reconciled by a late row (confirmed or refunded), without
moving the solo safety gates or flipping an icon on a correction.

**Architecture:** All in the ticket layer and the rage family. `Game/Events/Tickets.lua` gains two states (TENT 4: paid
but replaceable until `fin`; ASSUMED 5: the shadow of an overdue ticket until `hi`), a pass (d) in `T.Pick`, the
replacement and finalisation calls, and the `assumed`, `confirmed`, `refunded` closes. `Game/Events/Kinds.lua` gives
every non-ticking kind a pass-4 band (its hard window); `Game/Events/Melee.lua` gives swings `M.Overdue` and
`M.Replaceable`. `Game/Events/Rows.lua` routes the rows (pass (d) last, replacement after pass (a) and after the LR),
holds a provisional spell payment's `Obs.Crit` / `Obs.Avoided` until it is final, and stages three new swing codes.
`Game/State/Families/Resources.lua` reads them: `Obs.Swing` c = 5 (an assumed hit: `est` and `hi` only), c = 6 (take a
record back: `lo` at once, `est` held to the next answer or spend), c = 7 (an assumption confirmed).

**Tech Stack:** Lua 5.1 (WoW), busted, luacheck, StyLua, the combat harness (`tests/Game/harness/`).

**Spec:** `docs/superpowers/specs/2026-10-23-attribution-recovery-design.md` (binding; decisions 46-56), amending
`docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md` (the base spec; decision 33 superseded). Cited as
"spec §N" and "base §N". Line numbers are as of `forever` 093313ae.

## Global Constraints

- Core/pack boundary: nothing under `src/Hekili/Game` or `tests/Game/harness` names a class, spell, aura, form or spell ID
  (`tests/boundary_spec.lua`). The harness test names keep `fs.SPENDER_*`.
- Secret safety: no new client read. Every value here is a plain row payload the registry already passed through `Plain`.
- No allocation in recurring paths: every new per-ticket field is an array of `T.CAP` entries filled at load; every
  per-slot field (`estDebt`) is filled at build with the slot count; no table, closure, `{...}` or string in `OnRow`,
  `T.Expire`, the folds or the polls (`tests/Game/State/alloc_spec.lua`, `tests/Game/harness/alloc_spec.lua`).
- States: `FREE 0, COMMITTED 1, OPEN 2, PROV 3` (as built), new `TENT 4`, `ASSUMED 5`. `T.Pick` keeps `state >= OPEN`:
  a TENT ticket has `owed` 0, so `K.Accepts` refuses it (`Kinds.lua:82`); an ASSUMED ticket owes its row.
- `Obs.Swing` codes: 0 speeds, 1 landed, 2 base speeds (`Sources/Swing.lua`), 3 crit, 4 swung (as built); new 5
  assumed hit, 6 take record `b` back, 7 assumption `b` confirmed.
- Floors under this ruling (spec decision 54): a task whose change moves a detection cell in the ruled direction
  (recall up; false credit, leak, `lostDiff` or K14p's pet rows up) rewrites `tests/Game/harness/detect_floors.lua`
  with `DETECT_WRITE=1` in the same commit, the ruling's header line above it, and lists every moved cell in the commit
  message. A solo cell's recall or `staged` moving down, a K20 capture assertion changing, or the solo `over`, `lo` over
  or `danger` gate (`tests/Game/harness/solo_spec.lua:21-25`) moving at all stops the task for the owner. The party and
  pet `falseNet` bars (`tests/Game/harness/group_spec.lua:25`, `:38`) may re-base the same way, with the measured value
  plus 1 and the ruling named beside it; their drift `over` bars do not move.
- The no-jitter rule: no retraction moves `est` by itself (spec §2.4); `tests/Game/harness/flicker_spec.lua` floors do
  not move up; `make test-loop` loop floors do not move down; Fury L24 agreement is expected UP.
- `make check` is green on every commit; `make gate` before the merge.
- Every commit ends with the trailer:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw`.

## Module Layout

| File | Change | Tested by |
|---|---|---|
| `src/Hekili/Game/Events/Kinds.lua` | `K.Band(i, 4, ...)`: the hard window for FLIGHT, FRAME, STRIKE; nil for TICKS, CHANNEL | `tests/Game/Events/kinds_spec.lua` |
| `src/Hekili/Game/Events/Melee.lua` | `M.Overdue`, `M.Replaceable`; `M.score` skips TENT | `tests/Game/Events/tickets_spec.lua` |
| `src/Hekili/Game/Events/Tickets.lua` | TENT, ASSUMED, `fin`, `tol`, the stored row, `T.PayTentative`, `T.Final`, `T.Replaceable`, `T.Replace`, the assumption in `T.Expire`, closes `confirmed`, `refunded`, `assumed`, counter `T.replaced`, the Snapshot line, `T.ASSUME_AT` | `tickets_spec.lua`, `tests/Game/harness/detect_sweep_spec.lua` |
| `src/Hekili/Game/Events/Rows.lua` | pass (d), the replacement checks, held spell observations, `T.onFinal`, `T.onReplace`, `T.onAssume`, `T.onLost` | `tickets_spec.lua`, harness specs |
| `src/Hekili/Game/State/Families/Resources.lua` | `Obs.Swing` c = 5, 6, 7; `retract`; `estDebt` and `I.Settle`; `I.ASSUME_VALUE` | `tests/Game/State/resources_spec.lua` |
| `tests/Game/harness/drive.lua`, `metrics.lua`, `detect.lua`, `detect_floors.lua` | hooks for finalisation, replacement and verdict times; `recovered100`, `wash`; the floors regenerated | `detect_spec.lua`, `detect_more_spec.lua`, `metrics_spec.lua` |

## Review Focus

1. Rows' order (spec §1.1): pass (a), the spell replacement, the avoid passes and the MELEE tie, the LR, the swing
   replacement, the wound passes, pass (d), foreign. A pass (d) or replacement step placed before the LR changes the
   solo melee numbers; Task 1 and Task 2 run `solo_spec.lua` and `pairing_replay_spec.lua` unchanged.
2. A ticket closed twice or never: every TENT and ASSUMED path must end in exactly one close (spec §3.5); the
   invariant sweep's conservation line (Task 4) and `tickets_spec.lua`'s `sum()` check it.
3. `lo` moved by an assumption or a provisional credit not taken back: c = 5 never touches `lo`; c = 6 always restores
   it; `solo_spec.lua:25`'s `danger == 0` and the `lo` over counts.
4. An `est` retraction applied outside an answer or a spend (a flash): c = 6 only adds to `estDebt`; `I.Settle` runs
   only at the top of the `Obs.Usable` and `Obs.CastSuccess` handlers.
5. A hot path that allocates: the new loops in `T.Replaceable`, `M.Overdue`, `M.Replaceable` and `T.Expire` are fixed
   32-step scans over preallocated arrays.

## Task order

1. Overdue (pass (d)) for every ticket; the base spec's decision 33 superseded
2. Replaceable payments: TENT, replacement, held observations, the rage retraction and its hold
3. Assumed outcomes past the lag tolerance (the shadow ticket), against the expiry-time expectation: four variants
   measured, the best kept
4. The crowd gate as a ranking aid; the Snapshot line and the conservation sweep
5. Detection suite: recovery and net-wash metrics, the floors with the ruling as their cause, the gate, the docs
6. Research and spec: parry haste (no code)

---

### Task 1: Overdue (pass (d)) for every ticket

**Files:**
- Modify: `src/Hekili/Game/Events/Kinds.lua:114-117` (`K.Band`'s head)
- Modify: `src/Hekili/Game/Events/Melee.lua` (after `M.score`, line 184)
- Modify: `src/Hekili/Game/Events/Rows.lua:285-292` (after the wound passes)
- Modify: `src/Hekili/Game/Events/Tickets.lua:409-412` (`T.Pick`'s doc comment)
- Modify: `tests/Game/harness/detect.lua:255-260` (the floors file's header line)
- Modify: `docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md` (§3.4.1 and decision 33)
- Test: `tests/Game/Events/kinds_spec.lua`, `tests/Game/Events/tickets_spec.lua`

**Interfaces:**
- Produces: `K.Band(i, 4, t, isAvoid, act, sch)` returns `lo, hi, E` = `at (+ rangeLow for FLIGHT), T.hi[i], at` for
  FLIGHT always and for FRAME and STRIKE when the row is an avoid, the ticket's school is not ANY, or the row is white;
  nil otherwise (TICKS, CHANNEL, NONE, UNMAPPED, MELEE). `T.Pick(t, g, 4, ...)` then picks the oldest anchor (E = `at`),
  amount-banded first (decision 45, unchanged).
- Produces: `M.Overdue(t, g, amount, flag, avoid, unknown)`: the open MELEE ticket on `g` with the least `at`, no
  provisional avoid, `t` inside `[at, at + w]`, a wound only in an amount class above 0 (or of unknown class), a wound
  never to a vetoed swing (`I.Missed`); nil when none.
- Consumes: `T.Pick` (`Tickets.lua:413-435`), `M.classOf`, `M.thetaIndex` (`Melee.lua:103-148`).

- [ ] **Step 1: Write the failing tests.** In `tests/Game/Events/kinds_spec.lua`, after the "accepts by school" case
  (line 63), add:

```lua
    it("Overdue (pass 4): the hard window, oldest first, after every band; none for a ticking kind", function()
        local a = open(fs.SPENDER_F, 10) -- hard window [10, 10 + max(LandWindow(1), 0.2)] = [10, 10.654]
        local b = open(fs.SPENDER_F, 10.1)
        for p = 1, 3 do -- 10.35: past both frames and both CAST_WINDOWs (10.2, 10.3)
            assert.are.equal(0, (T.Pick(10.35, "Creature-1", p, "WOUND", "", 30, 4, false)))
        end
        assert.are.equal(a, (T.Pick(10.35, "Creature-1", 4, "WOUND", "", 30, 4, false)))
        assert.are_not.equal(a, b)
        assert.are.same({ 10, T.hi[a], 10 }, { K.Band(a, 4, 10.35, false, "WOUND", 4) })
        local m = open(fs.SPENDER_M, 20) -- an instant with ticks: its composed schedule has no Overdue band
        assert.is_true(T.link[m] > 0)
        assert.is_nil(K.Band(T.link[m], 4, 23, false, "WOUND", T.school[m]))
    end)

    it("Overdue: a default type (school ANY) takes only a white wound past its frame", function()
        local c = open(fs.SPENDER_C, 10)
        assert.is_nil(K.Band(c, 4, 10.4, false, "WOUND", 8))
        assert.is_truthy(K.Band(c, 4, 10.4, false, "WOUND", 1))
        assert.is_truthy(K.Band(c, 4, 10.4, true, "DODGE", 1))
    end)
```

  In `tests/Game/Events/tickets_spec.lua`, after "pays two projectiles of one queue in cast order" (line 307), add:

```lua
    it("pays a row past a learned ticket's widened band inside its hard window: Overdue (decision 46)", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30 -- H = 1.65
        T.Learn("Creature-1", 20, 1.5, 9) -- d = 2.5 s at the 10 s anchor: widened band [10.313, 11.65]
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        ctl.now = 10.2 -- under the widened band's lower edge, inside the hard window
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8)
        assert.are.equal(0, T.foreign)
        assert.are.same({ "SPELL_DAMAGE", 10 }, { got[#got][2], got[#got][1] })
    end)

    it("pays a white wound the swing LR leaves below its bar to the oldest open swing: Overdue", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        for c = 1, 8 do
            I.Log.bg[c] = 50 -- a crowd: every background rate high, so the LR stays below its bar
        end
        ctl.now = 11.2 -- 1.2 s: past the core band, inside the 1.5 s window
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
        assert.are.equal(0, T.foreign)
        assert.are.same({ "SWING_DAMAGE", 10 }, { got[#got][2], got[#got][1] })
    end)

    it("leaves a tick outside every schedule band foreign: no Overdue for ticks (decision 47)", function()
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_M)
        ctl.now = 10.01
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 9, 64) -- the direct hit
        ctl.now = 11.5 -- between the application and the first tick (13 +- 0.1)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 4, 64)
        assert.are.equal(1, T.foreign)
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/kinds_spec.lua tests/Game/Events/tickets_spec.lua`
Expected: FAIL: the pass-4 Pick returns 0 (`K.Band` has no pass 4); the two Overdue cases count `T.foreign` 1. The
ticks case passes already (it guards decision 47).

- [ ] **Step 3: The pass-4 band.** In `src/Hekili/Game/Events/Kinds.lua`, replace the head of `K.Band`:

```lua
--- Ticket i's band at pass p for a row at t: lo, hi (absolute) and its expected closure E; nil when it has none.
function K.Band(i, p, t, isAvoid, act, sch)
    local k, a0 = T.kind[i], T.at[i]
```

  with:

```lua
--- Ticket i's band at pass p for a row at t: lo, hi (absolute) and its expected closure E; nil when it has none. Pass
--- 4, Overdue (attribution-recovery spec decision 46): the hard window, E the anchor (oldest first); a ticking kind
--- has none (decision 47: a paid tick moves its schedule).
function K.Band(i, p, t, isAvoid, act, sch)
    local k, a0 = T.kind[i], T.at[i]
    if p == 4 then
        if k == FLIGHT then
            return a0 + rangeLow(i, T.speed[i]), T.hi[i], a0
        elseif (k == FRAME or k == STRIKE) and (isAvoid or T.school[i] ~= ANY or sch == 1) then
            return a0, T.hi[i], a0
        end
        return nil
    end
```

- [ ] **Step 4: The swing's Overdue.** In `src/Hekili/Game/Events/Melee.lua`, after `M.score` (line 184), add:

```lua
--- (attribution-recovery spec §1.1, decision 46) Overdue: the oldest open swing ticket on `g` whose window holds a white
--- row at t that no band and no LR credit took: no provisional avoid on it, a wound only in an amount class of its
--- hand (or of unknown class) and never to a vetoed swing (I.Missed). Nil when none. Allocates nothing.
function M.Overdue(t, g, amount, flag, avoid, unknown)
    local best = nil
    for i = 1, T.CAP do
        if T.state[i] == T.OPEN and T.kind[i] == X.MELEE and T.guid[i] == g and T.avoid[i] == "" then
            local d = t - T.at[i]
            if d >= 0 and d <= T.w[i] and (best == nil or T.at[i] < T.at[best]) then
                local h = T.x[i]
                local fits = avoid or unknown or M.classOf(h, amount, flag) > 0
                if fits and (avoid or not (I.Missed and I.Missed(h, T.at[i]))) then
                    best = i
                end
            end
        end
    end
    return best
end
```

- [ ] **Step 5: Rows runs pass (d) last.** In `src/Hekili/Game/Events/Rows.lua`, after the wound passes block

```lua
    if p == 0 and not credited and not avoid then
        p, n = T.Pick(t, g, 2, act, flag, amount, school, false)
        pass = 2
        if p == 0 then
            p, n = T.Pick(t, g, 3, act, flag, amount, school, false)
            pass = 3
        end
    end
```

  add:

```lua
    -- pass (d), Overdue (attribution-recovery decision 46): after every band and the LR, the oldest ticket of the
    -- queue whose hard window holds the row; spells first (their bands are narrower), then a swing
    if p == 0 and not credited then
        p, n = T.Pick(t, g, 4, act, flag, amount, school, avoid)
        pass = 4
        if p == 0 and white and (AVOIDS[act] or not avoid) and not (not avoid and t - lastW0 <= SAME_FRAME) then
            credited = M.Overdue(t, g, amount, flag, avoid, unknown)
            if credited then
                local h = T.x[credited]
                lag = t - T.at[credited]
                lr, ref, second = 0, h, math.huge -- no LR: it teaches nothing and is never clean
                k = M.thetaIndex(h, (avoid or unknown) and 4 or M.classOf(h, amount, flag), h, lag)
            end
        end
    end
```

  and change `T.Pick`'s doc comment head in `Tickets.lua:409` from "at most 3 passes" to "at most 4 passes (pass 4:
  Overdue, attribution-recovery decision 46)".

- [ ] **Step 6: Run the unit tests**

Run: `.lua/bin/busted tests/Game/Events/kinds_spec.lua tests/Game/Events/tickets_spec.lua tests/Game/Events/pairing_replay_spec.lua tests/Game/Events/cleu_rows_spec.lua && make test-fast`
Expected: PASS, 0 failures.

- [ ] **Step 7: The floors' header names the ruling.** In `tests/Game/harness/detect.lua`'s `M.record`, after
  `"-- written by the first clean run (DETECT_WRITE=1). Floors only move up; a lower one needs a named cause.",` add:

```lua
        "-- 2026-10-23 (attribution-recovery spec decision 54): regenerated under the owner's ruling (recall over"
            .. " precision): recall up; false credit, leak, lostDiff and pet rows may rise.",
```

- [ ] **Step 8: The gates.** Run the solo and group gates, then the detection suite:

Run: `.lua/bin/busted --tags=slow tests/Game/harness/solo_spec.lua tests/Game/harness/group_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/captures_spec.lua`
Expected: solo PASS unchanged (stop the task if it fails); captures PASS unchanged; group: the `falseNet` bars may fail
(re-base each at the measured value + 1, comment `-- attribution-recovery decision 54: measured <x>`), the drift
`over` bars must pass.

Run: `DETECT_WRITE=1 .lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua && git diff --stat tests/Game/harness/detect_floors.lua && .lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua tests/Game/harness/detect_sweep_spec.lua`
Expected: the rewrite, then PASS. Read `git diff tests/Game/harness/detect_floors.lua`: every moved cell in the ruled
direction (spec §5.1); a solo recall or `staged` cell down stops the task.

Run: `make check && make test-loop`
Expected: exit 0; loop floors unchanged or better.

- [ ] **Step 9: Amend the base spec.** In `docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md`
  replace

```
| Overdue | inside the hard window only | (c), reachable only by tickets with no learned record (decision 33) |
```

  with

```
| Overdue | inside the hard window only | (c) for a ticket with no learned record; (d), after every band, for every ticket (decision 46 of `docs/superpowers/specs/2026-10-23-attribution-recovery-design.md`, superseding 33) |
```

  replace "is in no phase\nfor that row: it is not a candidate." with "is Overdue\nfor that row (pass (d), 2026-10-23
  amendment)." and prefix the decision 33 row's text with "SUPERSEDED by decision 46 of the 2026-10-23
  attribution-recovery spec (owner ruling 2026-10-23). Was: ".

- [ ] **Step 10: Commit**

```bash
git add src/Hekili/Game/Events/Kinds.lua src/Hekili/Game/Events/Melee.lua src/Hekili/Game/Events/Rows.lua \
  src/Hekili/Game/Events/Tickets.lua tests/Game/Events/kinds_spec.lua tests/Game/Events/tickets_spec.lua \
  tests/Game/harness/detect.lua tests/Game/harness/detect_floors.lua tests/Game/harness/group_spec.lua \
  docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md
git commit -m "feat(tickets): Overdue for every ticket, the oldest of its queue after every band

Owner ruling 2026-10-23 (attribution-recovery decision 46, superseding decision 33). Ticks have no
Overdue (decision 47).
<every moved detection cell, before -> after, and any re-based group bar>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

(The angle-bracket line is the run's own numbers.)

---

### Task 2: Replaceable payments

**Files:**
- Modify: `src/Hekili/Game/Events/Tickets.lua` (state TENT, per-ticket arrays, `T.PayTentative`, `T.Final`,
  `T.Replaceable`, `T.Replace`, `T.Expire`, `T.EndCombat`)
- Modify: `src/Hekili/Game/Events/Melee.lua` (`M.score` skips TENT; `M.Replaceable`)
- Modify: `src/Hekili/Game/Events/Rows.lua` (`paySpell`, the replacement checks, the swing credit's pass, the hooks)
- Modify: `src/Hekili/Game/State/Families/Resources.lua` (`retract`, `estDebt`, `I.Settle`, c = 6)
- Modify: `tests/Game/harness/drive.lua` (the hooks' captures)
- Test: `tests/Game/Events/tickets_spec.lua`, `tests/Game/State/resources_spec.lua`

**Interfaces:**
- Produces (Tickets): `T.TENT = 4`; per ticket `T.fin`, `T.rowT`, `T.rowAct`, `T.rowFlag`, `T.rowAmt`, `T.rowSch`,
  `T.rowClean`, `T.held` (0 none, 1 crit, 2 avoid), `T.rec` (the swing's credit record, 0 none); `T.replaced`.
  `T.NarrowEnd(i)`: the end of i's narrow band, nil when it has none (a FLIGHT with no record). `T.PayTentative(i, t,
  isAvoid, amount, flag, clean, pass, act, sch)`: final (calls `T.Pay`, returns false) at pass 1 or 3, past the narrow
  band, for a ticket with a live TICKS link or a ticking kind; else TENT (returns true). `T.Final(i, now)`,
  `T.Replaceable(t, g, act, flag, amount, sch, isAvoid)`, `T.Replace(i, t)`. Hooks `T.onFinal(i, now)`,
  `T.onReplace(i, t)`.
- Produces (Melee): `M.Replaceable(t, g, amount, flag, avoid, unknown)`.
- Produces (Resources): `Obs.Swing` c = 6, b = record: the record's credit taken back (spec §2.3, §2.4);
  `I.Settle(r)`: the slot's held `est` debt applied (the next answer or spend).
- Consumes: the credit records (`Rows.lua:30-37`, `Resources.lua:198-213`), `back()` (`Resources.lua:919-925`).

- [ ] **Step 1: Write the failing tests.** In `tests/Game/Events/tickets_spec.lua`, after the Task 1 cases, add:

```lua
    describe("replaceable payments (attribution-recovery decision 48)", function()
        local staged, stage

        before_each(function()
            staged, stage = {}, I.Sources.Stage
            I.Sources.Stage = function(kind, t, a, b, c)
                staged[#staged + 1] = { kind, b, c }
                return stage(kind, t, a, b, c)
            end
        end)

        after_each(function()
            I.Sources.Stage = stage
        end)

        local function count(kind, c)
            local n = 0
            for _, s in ipairs(staged) do
                n = n + ((s[1] == kind and (c == nil or s[3] == c)) and 1 or 0)
            end
            return n
        end

        it("a dodge in the swing's core band replaces a wound credited before it; the rage is taken back", function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.now = 10.2 -- before the core band (0.474 +- 0.12): credited by the LR, provisionally
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.equal(T.TENT, T.state[i])
            assert.are.equal(1, count(VS.Obs.Swing, 1))
            ctl.now = 10.47 -- our own DODGE, in the core band
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            assert.are.same({ 1, 1 }, { T.replaced, T.foreign })
            assert.are.equal(1, count(VS.Obs.Swing, 6))
            assert.are.same({ T.PROV, "DODGE" }, { T.state[i], T.avoid[i] })
        end)

        it("holds a provisional spell payment's crit and drops it on replacement by the cast's own avoid", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
            T.Learn("Creature-1", 20, 1.5, 9) -- narrow band [11.35, 11.65] for the 10 s cast
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
            ctl.now = 10.6 -- the widened band, before the narrow one: provisional
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 8)
            assert.are.equal(0, count(VS.Obs.Crit))
            ctl.now = 11.5
            ctl.Fire("UNIT_COMBAT", "target", "MISS", "", 0, 1)
            assert.are.same({ 1, 1 }, { T.replaced, T.foreign })
            assert.are.same({ 0, 1 }, { count(VS.Obs.Crit), count(VS.Obs.Avoided) })
            assert.are.equal(1, T.paid[X.FLIGHT])
        end)

        it("stages a held crit once the narrow band passes with no replacement, and teaches then", function()
            I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
            T.Learn("Creature-1", 20, 1.5, 9)
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
            ctl.now = 10.6
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 8)
            local r = T.LagOf("Creature-1", 20)
            assert.is_true(math.abs(T.lagE[r] - 1.5) < 1e-9) -- not taught while provisional
            ctl.Tick(11.7) -- past the narrow band's end (11.65): final
            assert.are.same({ 1, 1 }, { count(VS.Obs.Crit), T.paid[X.FLIGHT] })
            assert.is_true(math.abs(T.lagE[r] - 0.6) < 1e-9)
            assert.are.equal(T.opened, sum())
        end)

        it("pays a pass (a) row final at once: no TENT", function()
            ctl.now = 10
            ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_F)
            ctl.now = 10.01
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 30, 4)
            assert.are.same({ 1, 1 }, { T.paid[X.FRAME], count(VS.Obs.Crit) })
        end)
    end)
```

  In `tests/Game/State/resources_spec.lua`, inside the top `describe` (beside the swing cases at lines 60-77), add:

```lua
        it("takes a replaced credit back: lo at once, hi down to est at most, est only when settled", function()
            local R = I.res
            local slot = R.slotOf[fs.RAGE]
            ctl.now = 150 -- after the fake client's start (100): the fold is in order
            I.Sources.Stage(VS.Obs.Swing, 150, 1, 1, 1) -- record 1: a landed main-hand swing
            I.Sources.Flush()
            I.Fold(150)
            local e1, lo1 = R.est0[slot], R.lo0[slot]
            I.Sources.Stage(VS.Obs.Swing, 150.5, 1, 1, 6) -- record 1 replaced
            I.Sources.Flush()
            I.Fold(150.5)
            assert.is_true(R.lo0[slot] < lo1 - 1e-9)
            assert.are.equal(e1, R.est0[slot]) -- the hold: est waits for an answer or a spend
            assert.is_true(R.hi0[slot] >= R.est0[slot])
            I.Settle(slot)
            assert.is_true(R.est0[slot] < e1 - 1e-9 and R.est0[slot] >= R.lo0[slot])
            I.Settle(slot) -- settled once
            assert.is_true(R.est0[slot] >= R.lo0[slot])
        end)

        it("takes nothing back once a spend of ours from the slot measured the pool", function()
            local R = I.res
            local slot = R.slotOf[fs.RAGE]
            ctl.now = 160
            I.Sources.Stage(VS.Obs.Swing, 160, 1, 2, 1) -- record 2
            I.Sources.Flush()
            I.Fold(160)
            R.spends[slot] = R.spends[slot] + 1
            local lo1 = R.lo0[slot]
            I.Sources.Stage(VS.Obs.Swing, 160.5, 1, 2, 6)
            I.Sources.Flush()
            I.Fold(160.5)
            assert.are.equal(lo1, R.lo0[slot])
        end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/State/resources_spec.lua`
Expected: FAIL: `T.TENT` is nil; `I.Settle` is nil.

- [ ] **Step 3: Tickets: the TENT state and its fields.** In `src/Hekili/Game/Events/Tickets.lua`, change line 18 to

```lua
T.FREE, T.COMMITTED, T.OPEN, T.PROV, T.TENT = 0, 1, 2, 3, 4
```

  and after the `paidAt` block (line 46) add:

```lua
-- Per ticket (attribution-recovery decision 48): a payment outside the narrow band, before it passed, is provisional:
-- the ticket stays TENT (owed 0, its unit held) until `fin`; the row that paid it (time, action, flag, amount, school,
-- clean) to teach from at `fin` or to re-label foreign; a held observation (1 Obs.Crit, 2 Obs.Avoided); the swing's
-- credit record (0 none).
T.fin, T.rowT, T.rowAct, T.rowFlag, T.rowAmt, T.rowSch, T.rowClean, T.held, T.rec = {}, {}, {}, {}, {}, {}, {}, {}, {}
for i = 1, CAP do
    T.fin[i], T.rowT[i], T.rowAct[i], T.rowFlag[i], T.rowAmt[i], T.rowSch[i] = 0, 0, "", "", 0, 0
    T.rowClean[i], T.held[i], T.rec[i] = false, 0, 0
end
T.replaced = 0 -- first rows re-labelled foreign by a narrow-band row (not a close)
T.onFinal, T.onReplace = nil, nil -- Rows' hooks: a TENT ticket final, a TENT ticket's row replaced
```

  In `fill` (line 225) add `T.held[i], T.rec[i] = 0, 0` to the resets.

- [ ] **Step 4: Tickets: teaching split out of `T.Pay`, and the tentative path.** Replace the two teaching `if`s at the
  top of `T.Pay` (lines 463-470) with a call `teachFrom(i, t, isAvoid, amount, flag, clean)` and define above `T.Pay`:

```lua
-- What a clean payment teaches: a flight's lag (any pass, pass 3 included: with no record a ticket is a candidate at
-- pass 3 alone, so no record would ever be made) and a declared direct ability's amount band.
local function teachFrom(i, t, isAvoid, amount, flag, clean)
    local k, a = kind[i], ab[i]
    if clean and k == X.FLIGHT then
        T.Learn(guid[i], T.speed[i], t - at[i], t)
    end
    if clean and not isAvoid and a > 0 and A.expDeclared[a] and (k == X.FRAME or k == X.FLIGHT or k == X.STRIKE) then
        teach(a, amount, flag)
    end
end
```

  After `T.Pay`, add:

```lua
--- The end of ticket i's narrow band (MELEE: the hand's core band), or nil when it has none (a flight with no lag
--- record). Allocates nothing.
function T.NarrowEnd(i)
    if kind[i] == MELEE then
        local h = x[i]
        return at[i] + I.Log.med[h] + 2 * I.Log.spr[h]
    end
    local _, h = I.Kinds.Band(i, 1, at[i], false, "WOUND", school[i])
    return h
end

--- (attribution-recovery decision 48) Ticket i paid at pass `pass` by a row at t: final (T.Pay, false) at pass 1 or
--- 3, once its narrow band passed, for a ticking kind or a direct ticket with a live schedule (its refresh cannot be
--- undone); else TENT until fin = min(narrow band end, hi), its row kept to teach from or re-label (true).
--- Allocates nothing.
function T.PayTentative(i, t, isAvoid, amount, flag, clean, pass, act, sch)
    local k = kind[i]
    local n = (pass == 2 or pass == 4) and k ~= X.TICKS and k ~= X.CHANNEL and T.link[i] <= 0 and T.NarrowEnd(i)
    if not n or t >= n then
        T.Pay(i, t, isAvoid, amount, flag, clean, pass)
        return false
    end
    if T.onPay then
        T.onPay(i, t, pass)
    end
    state[i], owed[i], done[i] = T.TENT, owed[i] - 1, done[i] + 1
    T.fin[i] = n < hi[i] and n or hi[i]
    T.rowT[i], T.rowAct[i], T.rowFlag[i], T.rowAmt[i], T.rowSch[i], T.rowClean[i] = t, act, flag, amount, sch, clean
    return true
end

--- TENT ticket i is final at `now`: Rows stages what it held (T.onFinal), it teaches from its row, and it closes paid.
function T.Final(i, now)
    if T.onFinal then
        T.onFinal(i, now)
    end
    teachFrom(i, T.rowT[i], T.rowAct[i] ~= "WOUND", T.rowAmt[i], T.rowFlag[i], T.rowClean[i])
    T.paid[kind[i]] = T.paid[kind[i]] + 1
    close(i, now, "paid")
end

--- The oldest TENT spell ticket on `g` whose narrow band holds a row at t that it would accept with its row still
--- owed; 0 when none. Allocates nothing.
function T.Replaceable(t, g, act, flag, amount, sch, isAvoid)
    local K, best = I.Kinds, 0
    for i = 1, CAP do
        if state[i] == T.TENT and kind[i] ~= MELEE and guid[i] == g and t <= T.fin[i] then
            owed[i] = 1 -- K.Accepts reads `owed`: asked as if the row were still owed
            local ok = K.Accepts(i, act, flag, amount, sch, isAvoid)
            owed[i] = 0
            local lo, h = K.Band(i, 1, t, isAvoid, act, sch)
            if ok and lo and t >= lo - 1e-9 and t <= h + 1e-9 and (best == 0 or at[i] < at[best]) then
                best = i
            end
        end
    end
    return best
end

--- TENT ticket i's row is replaced at t by a narrow-band row: the first row becomes foreign (it arms the crowd gate at
--- its own time), Rows undoes its effects (T.onReplace), and the ticket owes its row again. Allocates nothing.
function T.Replace(i, t)
    T.replaced, T.foreign = T.replaced + 1, T.foreign + 1
    T.Foreign(uid[i], T.rowSch[i], T.rowT[i])
    if T.onReplace then
        T.onReplace(i, t)
    end
    state[i], owed[i], done[i], T.held[i] = OPEN, owed[i] + 1, done[i] - 1, 0
end
```

  In `T.Expire`, before the `now > hi[i]` test, finalise:

```lua
function T.Expire(now)
    for i = 1, CAP do
        if state[i] == T.TENT and now > T.fin[i] then
            T.Final(i, now)
        end
        if state[i] ~= 0 and now > hi[i] then
```

  (the rest unchanged). `T.EndCombat` already closes every state `ended`; add `T.held[i] = 0` in its loop.

- [ ] **Step 5: Melee: TENT is no candidate; the swing's replacement.** In `M.score`'s condition (`Melee.lua:155-160`)
  add `and T.state[i] ~= T.TENT`. After `M.Overdue`, add:

```lua
--- (attribution-recovery decision 48) The oldest TENT swing ticket on `g` (credited outside its core band) whose
--- core band holds a white row at t: a wound in an amount class of its hand (or unknown), or an avoid. Nil when none.
--- Allocates nothing.
function M.Replaceable(t, g, amount, flag, avoid, unknown)
    local best = nil
    for i = 1, T.CAP do
        if T.state[i] == T.TENT and T.kind[i] == X.MELEE and T.guid[i] == g and t <= T.fin[i] then
            local h = T.x[i]
            if
                math.abs(t - T.at[i] - L.med[h]) <= 2 * L.spr[h]
                and (avoid or unknown or M.classOf(h, amount, flag) > 0)
                and (best == nil or T.at[i] < T.at[best])
            then
                best = i
            end
        end
    end
    return best
end
```

- [ ] **Step 6: Rows: hold, replace, hooks.** In `src/Hekili/Game/Events/Rows.lua`:

  Replace `paySpell` (lines 182-197) with:

```lua
-- A spell row paid to ticket p at pass `pass` with n candidates at that pass: staged unless another candidate implies
-- a different state (divergent, T.Divergent: it stages nothing, spec §4.2), then emitted. A divergent avoid emits no
-- SPELL_MISSED (Hekili's `missable` would drop the other cast's debuff on it). A provisional payment (TENT,
-- attribution-recovery decision 48) holds its Crit or Avoided until it is final (T.onFinal) or replaced.
local function paySpell(p, n, pass, t, act, flag, amount, school, avoid, crit)
    local divergent = (avoid or crit) and n > 1 and T.Divergent(p, t, pass, act, flag, amount, school, avoid)
    local kk, xx, dst, at0, sch = T.kind[p], T.x[p], T.guid[p], T.at[p], T.school[p]
    local held = T.PayTentative(p, t, avoid, amount, flag, n == 1, pass, act, school)
    if divergent then
        T.divergent = T.divergent + 1
    elseif held then
        T.held[p] = avoid and 2 or (crit and T.ab[p] > 0 and 1 or 0)
    elseif avoid then
        avoided(p, t, act)
    elseif crit and T.ab[p] > 0 then
        S.Stage(Obs.Crit, t, T.ab[p], at0, 0) -- our cast's own crit (the target's row carries the flag plain): GAP T
    end
    L.credited[3] = L.credited[3] + 1
    if not (divergent and avoid) then
        emit(kk, xx, dst, act, flag, amount, (kk == TICKS or kk == CHANNEL) and t or at0, sch > 0 and sch or school)
    end
end

-- A TENT ticket final: what it held is staged now (attribution-recovery decision 48).
T.onFinal = function(i, now)
    if T.held[i] == 2 then
        avoided(i, now, T.rowAct[i])
    elseif T.held[i] == 1 then
        S.Stage(Obs.Crit, now, T.ab[i], T.at[i], 0)
    end
end

-- A TENT ticket's first row re-labelled foreign: its swing credit taken back (the record's verdict closed, Resources
-- retracts with its hold), a spell's held observation dropped (Tickets clears T.held); its emitted row stays.
T.onReplace = function(i, t)
    if T.kind[i] == MELEE then
        if T.rec[i] > 0 then
            recOpen[T.rec[i]] = false
            S.Stage(Obs.Swing, t, T.x[i], T.rec[i], 6)
        end
        L.credited[T.x[i]] = L.credited[T.x[i]] - 1
    else
        L.credited[3] = L.credited[3] - 1
    end
    L.background = L.background + 1
end
```

  `avoided(i, t, act)` already stages at the ticket's anchor (`T.at[i]`), so Now's latest-cast check (`Now.lua:470`)
  still matches. In the row handler, right after the first `T.Pick` (line 239), add the spell replacement:

```lua
    local replacing = 0
    if p == 0 then -- a narrow-band row for a provisionally paid ticket (attribution-recovery decision 48)
        replacing = T.Replaceable(t, g, act, flag, amount, school, avoid)
        p, n = replacing, 1
    end
```

  and in the `if p > 0 then` payment block (line 293), before `paySpell`, add `if replacing > 0 and p == replacing then
  T.Replace(p, t) end` (the MELEE tie may have set `p` to 0, which leaves the TENT ticket untouched). After the LR block
  (line 284), add the swing replacement:

```lua
    if p == 0 and not credited and white and (AVOIDS[act] or not avoid) then
        local r = M.Replaceable(t, g, amount, flag, avoid, unknown)
        if r then -- the swing's own row in its core band replaces a provisional credit (decision 48)
            T.Replace(r, t)
            local h = T.x[r]
            credited, lr, ref, lag, second = r, math.huge, h, t - T.at[r], 0
            k = M.thetaIndex(h, (avoid or unknown) and 4 or M.classOf(h, amount, flag), h, lag)
        end
    end
```

  In the swing credit path, replace `T.Pay(credited, t, false, amount, flag, second < L.THETA, 2)` with:

```lua
    local core = T.first[credited] or lag <= SAME_FRAME or math.abs(lag - L.med[xx]) <= 2 * L.spr[xx]
    T.rec[credited] = id
    T.PayTentative(credited, t, false, amount, flag, second < L.THETA, core and 1 or 2, act, 1)
```

  and guard the median learning just above it with `core and` (a provisional credit never teaches it: decision 48):
  `if core and not unknown and M.classOf(xx, amount, flag) == 1 and ...`. Move the `core` line above the learning `if`.

- [ ] **Step 7: Resources: the retraction and its hold.** In `src/Hekili/Game/State/Families/Resources.lua`, after
  `back()` (line 925), add:

```lua
-- Per slot: est still owed back by a retraction (attribution-recovery spec §2.4, the hold): applied at the slot's next
-- usability answer or spend (I.Settle), dropped at combat end. Filled at build.
local estDebt = {}

-- Record k's credit taken back at t (a replacement, a refund): lo at once (it must never stand above the truth), hi
-- down to est at most, est into the slot's debt; the hit rate loses its step. Nothing once a spend of ours from the
-- slot measured the pool. The verdict's own retraction (verdict) is unchanged: an answer is a measurement. Allocates
-- nothing.
local function retract(k, t)
    local s = recR[k]
    if s == 0 or R.spends[s] ~= recSpends[k] then
        recA[k], recR[k] = 0, 0
        return
    end
    local max = R.max[s]
    R.lo0[s] = back(R.lo0[s], recLo[k], recLo0[k], max)
    local h = back(R.hi0[s], recHi[k], recHi0[k], max)
    R.hi0[s] = h > R.est0[s] and h or R.est0[s]
    estDebt[s] = estDebt[s] + recEst[k]
    local hr = hitRate[recHand[k]] - recHit[k]
    hitRate[recHand[k]] = hr > 0 and hr or 0
    recA[k], recR[k] = 0, 0
    I.Sample(R.power[s], "modelled", R.est0[s], t, Obs.Swing)
end

--- Slot r's held est debt applied (its next usability answer or spend): est loses it, never below lo. Allocates nothing.
function I.Settle(r)
    local d = estDebt[r]
    if r > 0 and d and d > 0 then
        estDebt[r] = 0
        local e = R.est0[r] - d
        R.est0[r] = e > R.lo0[r] and e or R.lo0[r]
    end
end
```

  Fill it at build where the other per-slot arrays are built (the loop over `R.n` in the build hook): `estDebt[r] = 0`;
  clear it in the `Obs.CombatEnd` handler's slot loop (`Resources.lua:1312-1320`): `estDebt[r] = 0`. Call `I.Settle(r)`
  at the top of the `Obs.Usable` handler after `local r = I.ab.slot[a]` (`:1036`) and of the `Obs.CastSuccess` handler
  after `local r = I.ab.slot[a]` (`:1210`), before their ladders. In the `Obs.Swing` handler (`:1152`), after the
  `c == 4` branch, add:

```lua
    elseif c == 6 then -- a credit taken back (attribution-recovery spec §2.3): its record's deltas, with the hold
        local k = o.b >= 1 and o.b <= RECORDS and o.b or 0
        if k > 0 then
            retract(k, t)
        end
        return
```

- [ ] **Step 8: The drive's captures.** In `tests/Game/harness/drive.lua`, after `T.onPay` (line 83), record which
  stream row paid each ticket, attribute a finalisation's staging to that row, and un-pay a replaced row:

```lua
    c.tIdx, c.finIdx, c.replacedAt, c.replacedT = {}, 0, {}, {} -- ticket -> paying row; replaced rows' times
    for i = 1, T.CAP do
        c.tIdx[i] = 0
    end
    for i = 1, CAP do
        c.replacedAt[i] = 0
    end
    local onPay = T.onPay
    T.onPay = function(i, t, pass)
        c.tIdx[i] = c.cur
        onPay(i, t, pass)
    end
    local onFinal, onReplace = T.onFinal, T.onReplace
    T.onFinal = function(i, now)
        c.finIdx = c.tIdx[i]
        onFinal(i, now)
        c.finIdx = 0
    end
    T.onReplace = function(i, t)
        local k = c.tIdx[i]
        if k > 0 then
            c.payAt[k], c.payKind[k], c.staged[k], c.replacedAt[k] = 0, 0, 0, t
        end
        onReplace(i, t)
    end
```

  In the `Stage` wrapper (line 208), use `local idx = c.cur > 0 and c.cur or c.finIdx` for the `c.staged` index.
  Reset `c.replacedAt[i] = 0` where `c.payAt` is reset (line 449).

- [ ] **Step 9: Run the unit tests**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/State/resources_spec.lua tests/Game/Events/kinds_spec.lua tests/Game/Events/pairing_replay_spec.lua tests/Game/Events/cleu_rows_spec.lua tests/Game/Events/kills_spec.lua && make test-fast`
Expected: PASS, 0 failures.

- [ ] **Step 10: The gates and the floors**, as Task 1 Step 8 (solo, group, onus, captures, then `DETECT_WRITE=1` and
  the detection suite, then `make check && make test-loop`), plus:

Run: `.lua/bin/busted --tags=slow tests/Game/harness/flicker_spec.lua tests/Game/harness/alloc_spec.lua`
Expected: PASS; flicker floors unchanged.

- [ ] **Step 11: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Melee.lua src/Hekili/Game/Events/Rows.lua \
  src/Hekili/Game/State/Families/Resources.lua tests/Game/harness/drive.lua tests/Game/Events/tickets_spec.lua \
  tests/Game/State/resources_spec.lua tests/Game/harness/detect_floors.lua
git commit -m "feat(tickets): a payment outside the narrow band is replaceable until that band passes

Attribution-recovery decisions 48-50: TENT tickets hold a spell's Crit/Avoided and teach at fin; a
narrow-band row replaces the first row (re-labelled foreign); a swing credit is taken back through its
record (Obs.Swing c = 6) with lo at once and est held to the next answer or spend.
<moved detection cells and gate numbers>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 3: Assumed outcomes past the lag tolerance (four variants measured)

**Files:**
- Modify: `src/Hekili/Game/Events/Tickets.lua` (ASSUMED, `tol`, `retry`, `assumed`, `T.Expire`, `expiry`, `T.Pay`'s
  close, `T.ASSUME_AT`)
- Modify: `src/Hekili/Game/Events/Melee.lua` (`M.Overdue` takes ASSUMED)
- Modify: `src/Hekili/Game/Events/Rows.lua` (`T.onAssume`, `T.onLost`, the reconcile in the swing credit path)
- Modify: `src/Hekili/Game/State/Families/Resources.lua` (`Obs.Swing` c = 5 and c = 7; `I.ASSUME_VALUE`)
- Modify: `tests/Game/harness/drive.lua` (the variant flags from the environment)
- Test: `tests/Game/Events/tickets_spec.lua`, `tests/Game/State/resources_spec.lua`

**Interfaces:**
- Produces (Tickets): `T.ASSUMED = 5`; per ticket `T.tol` (the lag tolerance, `math.huge` none), `T.retry`
  (a firm retraction's re-open), `T.assumed` (it was assumed); closes `confirmed`, `refunded`, `assumed`; hooks
  `T.onAssume(i, now)` (the tolerance variant) and `T.onLost(i)` (the expiry variant); `T.ASSUME_AT` =
  `"tolerance"` or `"expiry"`.
- Produces (Resources): `Obs.Swing` c = 5, b = record or 0: an assumed hit, `est` and `hi` only (FULL: the step; EV:
  `hitRate` x the step, `I.ASSUME_VALUE` = `"full"` or `"ev"`); c = 7, b = record: the assumption confirmed by a wound
  (the record becomes the credit: `est`, `hi` take the rest of a landed step, `lo` its floor, the hit rate its step).
- Consumes: `T.PendingWindow` (`Tickets.lua:311-314`), `K.Flight` (`Kinds.lua:47-76`), `swingStep`'s shape
  (`Resources.lua:849-882`), `predict` (`:889-905`), Task 2's `retract` and records.

- [ ] **Step 1: Write the failing tests.** In `tests/Game/Events/tickets_spec.lua`, add:

```lua
    describe("assumed outcomes (attribution-recovery decision 51)", function()
        local staged, stage

        before_each(function()
            T.ASSUME_AT = "tolerance"
            staged, stage = {}, I.Sources.Stage
            I.Sources.Stage = function(kind, t, a, b, c)
                staged[#staged + 1] = { kind, b, c }
                return stage(kind, t, a, b, c)
            end
            for c = 1, 8 do
                I.Log.bg[c] = 50 -- a crowd: late rows stay below the LR bar and reach the shadow through Overdue
            end
        end)

        after_each(function()
            I.Sources.Stage = stage
        end)

        local function count(c)
            local n = 0
            for _, s in ipairs(staged) do
                n = n + ((s[1] == VS.Obs.Swing and s[3] == c) and 1 or 0)
            end
            return n
        end

        local function swingPastTolerance()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            local i = T.lastSwing[1]
            ctl.Tick(10 + T.PendingWindow(1) + 0.01)
            return i
        end

        it("assumes a swing past its tolerance: rage staged at once, the ticket a shadow", function()
            local i = swingPastTolerance()
            assert.are.same({ T.ASSUMED, 1 }, { T.state[i], count(5) })
        end)

        it("confirms a late hit: the assumption's record becomes the credit", function()
            local i = swingPastTolerance()
            ctl.now = 11.2
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.same({ 1, 0, 1 }, { count(7), count(6), T.closed.confirmed })
            assert.are.equal(0, T.state[i])
        end)

        it("refunds a late dodge: the assumed rage taken back, closed refunded at the window's end", function()
            swingPastTolerance()
            ctl.now = 11.2
            ctl.Fire("UNIT_COMBAT", "target", "DODGE", "", 0, 1)
            assert.are.equal(1, count(6))
            ctl.Tick(11.6)
            assert.are.equal(1, T.closed.refunded)
        end)

        it("lets the assumption stand when no row comes: closed assumed, never lost", function()
            swingPastTolerance()
            ctl.Tick(11.6)
            assert.are.same({ 1, 0 }, { T.closed.assumed, T.lost[X.MELEE] })
            assert.are.equal(T.opened, sum())
        end)

        it("never assumes a retraction's re-open", function()
            ctl.now = 10
            local i = T.OpenSwing(10, 1, "Creature-1", 1.5, 0, false, true)
            ctl.Tick(10 + T.PendingWindow(1) + 0.01)
            assert.are.same({ T.OPEN, 0 }, { T.state[i], count(5) })
        end)

        it("the expiry variant: no shadow; the expectation at the lost close", function()
            T.ASSUME_AT = "expiry"
            local i = swingPastTolerance()
            assert.are.same({ T.OPEN, 0 }, { T.state[i], count(5) })
            ctl.Tick(11.6)
            assert.are.same({ 1, 1 }, { T.closed.lost, count(5) })
        end)
    end)
```

  In `tests/Game/State/resources_spec.lua`, add:

```lua
        it("an assumed hit adds the step to est and hi, never to lo (FULL), or hitRate x the step (EV)", function()
            local R = I.res
            local slot = R.slotOf[fs.RAGE]
            local step = I.SwingValue(slot, 1, 170) * R.scale[slot]
            for _, variant in ipairs({ "full", "ev" }) do
                I.ASSUME_VALUE = variant
                ctl.now = variant == "full" and 170 or 175
                local e0, lo0 = R.est0[slot], R.lo0[slot]
                I.Sources.Stage(VS.Obs.Swing, ctl.now, 1, 3, 5)
                I.Sources.Flush()
                I.Fold(ctl.now)
                local rise = R.est0[slot] - e0
                if variant == "full" then
                    assert.is_true(math.abs(rise - step) < 1e-6 or R.est0[slot] == R.max[slot])
                else -- hitRate x the step: at most the step
                    assert.is_true(rise > 0 and rise <= step + 1e-6)
                end
                assert.are.equal(lo0, R.lo0[slot])
            end
            I.ASSUME_VALUE = "full"
        end)

        it("a confirmed assumption lifts lo by the landed step and leaves est where the assumption put it", function()
            local R = I.res
            local slot = R.slotOf[fs.RAGE]
            I.ASSUME_VALUE = "full"
            ctl.now = 180
            I.Sources.Stage(VS.Obs.Swing, 180, 1, 4, 5)
            I.Sources.Flush()
            I.Fold(180)
            local e1, lo1 = R.est0[slot], R.lo0[slot]
            I.Sources.Stage(VS.Obs.Swing, 180, 1, 4, 7)
            I.Sources.Flush()
            I.Fold(180.8)
            assert.is_true(math.abs(R.est0[slot] - e1) < 1e-6)
            assert.is_true(R.lo0[slot] > lo1)
        end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/State/resources_spec.lua`
Expected: FAIL: `T.ASSUMED` is nil; c = 5 and c = 7 change nothing.

- [ ] **Step 3: Tickets: the shadow.** In `Tickets.lua`: line 18 becomes
  `T.FREE, T.COMMITTED, T.OPEN, T.PROV, T.TENT, T.ASSUMED = 0, 1, 2, 3, 4, 5`. Add `confirmed = 0, refunded = 0,
  assumed = 0,` to `T.closed`. After Task 2's arrays add:

```lua
-- Per ticket (attribution-recovery decision 51): its lag tolerance (math.huge: none), a firm retraction's re-open
-- (never assumed), and whether it was assumed. T.ASSUME_AT: "tolerance" (the shadow ticket, primary) or "expiry" (the
-- expectation at the lost close, the measured alternative); Task 3 keeps one.
T.ASSUME_AT = "tolerance"
T.tol, T.retry, T.assumed = {}, {}, {}
for i = 1, CAP do
    T.tol[i], T.retry[i], T.assumed[i] = math.huge, false, false
end
T.onAssume, T.onLost = nil, nil
```

  In `fill`: `T.tol[i], T.retry[i], T.assumed[i] = math.huge, false, false`. In `T.OpenSwing`, after `fill`:
  `T.retry[i] = retry == true` and `T.tol[i] = retry and math.huge or t + T.PendingWindow(hand)`. In `arm`'s FLIGHT branch,
  after `hi[i] = t + T.H[i]`:

```lua
        if T.LagOf(guid[i], T.speed[i]) > 0 then -- a learned lag: tolerance at the widened band's end
            local _, h = I.Kinds.Band(i, 2, t, false, "WOUND", school[i])
            T.tol[i] = h or math.huge
        end
```

  In `T.Expire`, after the TENT finalisation and before the `hi` test:

```lua
        if
            state[i] == OPEN
            and now > T.tol[i]
            and now <= hi[i]
            and T.ASSUME_AT == "tolerance"
            and guid[i] ~= ""
            and not U.IsDead(uid[i])
        then
            state[i], T.assumed[i] = T.ASSUMED, true -- the shadow: open to the hard window's end
            if T.onAssume then
                T.onAssume(i, now)
            end
        end
```

  In `expiry(i)`: after `if st == COMMITTED then return "stopped"`, change the PROV line to
  `elseif st == PROV then return T.assumed[i] and "refunded" or "provisional"` and add
  `elseif st == T.ASSUMED then return U.IsDead(uid[i]) and "dead" or "assumed"`; before `T.lost[k] = ...` add
  `if T.ASSUME_AT == "expiry" and T.onLost then T.onLost(i) end`. In `T.Pay`'s close
  (`close(i, t, "paid")`), use `close(i, t, T.assumed[i] and (isAvoid and "refunded" or "confirmed") or "paid")` and count
  `T.paid[kind]` only for `paid`.

- [ ] **Step 4: Melee.** In `M.Overdue`, change `T.state[i] == T.OPEN` to
  `(T.state[i] == T.OPEN or T.state[i] == T.ASSUMED)`.

- [ ] **Step 5: Rows.** Add after `T.onExpire`:

```lua
-- A swing past its lag tolerance (attribution-recovery decision 51): assumed a hit at once, as a credit record the
-- oracle can judge and a late avoid can take back (Obs.Swing c = 5); a retry is never assumed (T.tol).
T.onAssume = function(i, now)
    if T.kind[i] ~= MELEE then
        return -- a spell: nothing to believe; the ticket only waits as a shadow
    end
    recNext = recNext % RECORDS + 1
    local id = recNext
    recT[id], recAmount[id], recFlag[id], recAt[id], recHand[id] = now, 0, "", T.at[i], T.x[i]
    recDst[id], recW[id], recRef[id], recK[id], recLR[id], recOpen[id] = T.guid[i], T.w[i], T.ref[i], 1, 0, true
    T.rec[i] = id
    S.Stage(Obs.Swing, T.at[i], T.x[i], id, 5)
end

-- The measured alternative (decision 51's comparison, the parked 9b): the expectation at a swing's lost close.
T.onLost = function(i)
    if T.kind[i] == MELEE and not T.retry[i] then
        S.Stage(Obs.Swing, T.at[i], T.x[i], 0, 5)
    end
end
```

  In the swing credit path, reconcile an assumed ticket. For an avoid, before `T.Provisional(credited, lr, act)`:

```lua
        if T.state[credited] == T.ASSUMED and T.rec[credited] > 0 then -- refunded: the assumed rage comes back out
            recOpen[T.rec[credited]] = false
            S.Stage(Obs.Swing, t, xx, T.rec[credited], 6)
        end
```

  For a wound, replace the record allocation (`recNext = recNext % RECORDS + 1; local id = recNext`) with:

```lua
    local confirm = T.state[credited] == T.ASSUMED and T.rec[credited] > 0
    local id = T.rec[credited]
    if not confirm then
        recNext = recNext % RECORDS + 1
        id = recNext
    end
```

  and stage `S.Stage(Obs.Swing, at0, xx, id, confirm and 7 or 1)` in place of the c = 1 line (the c = 3 line keeps
  `id`).

- [ ] **Step 6: Resources.** Beside `local hitRate, HIT_ALPHA = ...` (line 134) add
  `I.ASSUME_VALUE = "full" -- attribution-recovery decision 52: "full" (the step) or "ev" (hitRate x the step)`. In the
  `Obs.Swing` handler, after Task 2's c = 6 branch, add:

```lua
    elseif c == 5 or c == 7 then -- assumed (5) or its confirmation (7), attribution-recovery spec §3.2
        local k = o.b >= 1 and o.b <= RECORDS and o.b or 0
        for r = 1, R.n do
            if R.swing[r] == hand or (hand == 2 and R.swing[r] == 1 and R.swingOff[r] ~= 0) then
                local v, s, sp, max = I.SwingValue(r, hand, o.t), R.scale[r], R.spread[r], R.max[r]
                local e, lo, hi = R.est0[r], R.lo0[r], R.hi0[r]
                if c == 5 then -- est and hi only: affordability never rests on an assumption
                    local de = v * s * (I.ASSUME_VALUE == "ev" and hitRate[hand] or 1)
                    R.est0[r], R.hi0[r] = clamp(e + de, max), clamp(hi + de, max)
                    if k > 0 then
                        predict(k, r, hand, e, lo, hi, 0, e, math.huge)
                    end
                elseif k > 0 and recR[k] == r then -- confirmed: the rest of a landed step, and its floor
                    local de, dh = v * s - recEst[k], v * (s + sp) - recHi[k]
                    R.est0[r] = clamp(e + (de > 0 and de or 0), max)
                    R.hi0[r] = clamp(hi + (dh > 0 and dh or 0), max)
                    R.lo0[r] = clamp(lo + v * (s - sp), max)
                    local h = hitRate[hand] + HIT_ALPHA
                    h = h < 1 and h or 1
                    predict(k, r, hand, recE0[k], recLo0[k], recHi0[k], h - hitRate[hand], recX0[k], math.huge)
                    hitRate[hand] = h
                end
                norm(r)
                I.Sample(R.power[r], "modelled", R.est0[r], t, Obs.Swing)
                break
            end
        end
        return
```

- [ ] **Step 7: The variant flags in the harness.** In `tests/Game/harness/drive.lua`'s `M.boot`, after the module
  loads: `c.I.Tickets.ASSUME_AT = os.getenv("ASSUME_AT") or "tolerance"` and
  `c.I.ASSUME_VALUE = os.getenv("ASSUME_VALUE") or "full"`.

- [ ] **Step 8: Run the unit tests**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua tests/Game/State/resources_spec.lua && make test-fast`
Expected: PASS, 0 failures.

- [ ] **Step 9: Measure the four variants on the same seeds.** For each of
  `ASSUME_AT=tolerance ASSUME_VALUE=full`, `tolerance ev`, `expiry full`, `expiry ev`, run:

Run: `ASSUME_AT=<at> ASSUME_VALUE=<v> .lua/bin/busted --tags=slow tests/Game/harness/solo_spec.lua tests/Game/harness/group_spec.lua tests/Game/harness/flicker_spec.lua tests/Game/harness/detect_spec.lua 2>&1 | tee /tmp/assume-<at>-<v>.txt`
Run: `ASSUME_AT=<at> ASSUME_VALUE=<v> make test-loop 2>&1 | tee /tmp/assume-loop-<at>-<v>.txt`
Expected: four tables. Record per variant: solo `over` (must be 0), `lo` over and `danger` (unchanged), each group
gate's `over`, err mean and max, `est over`; every flicker line; Fury L24 agreement and flicker; K10, K14f `rageErr`.

- [ ] **Step 10: Keep the best.** Choose by spec decision 52's order: the solo `over`, `lo` over and `danger` hold;
  then the lowest flicker; then the highest Fury L24 agreement; then the smallest mean error. If no variant keeps the
  solo `over` at 0, stop the task for the owner with the four tables (spec §3.4). Delete the losing branches: for
  `"tolerance"` remove `T.onLost`, the `T.ASSUME_AT` field and its test; for `"expiry"` remove ASSUMED, `tol`,
  `T.onAssume`, the reconcile code and their tests; for `"full"` / `"ev"` remove `I.ASSUME_VALUE` and keep the chosen
  expression; remove the environment reads from `drive.lua`. Write the four tables and the choice under a new row
  "Assumed outcomes (decision 51)" in `docs/dev/gaps.md`'s table, and replace the "Task 9b, parked" finding in
  `docs/dev/ingame-ledger.md:90-93` with one line pointing at it.

- [ ] **Step 11: The gates and the floors**, as Task 2 Step 10.

- [ ] **Step 12: Commit**

```bash
git add src/Hekili/Game/Events/Tickets.lua src/Hekili/Game/Events/Melee.lua src/Hekili/Game/Events/Rows.lua \
  src/Hekili/Game/State/Families/Resources.lua tests/Game/harness/drive.lua tests/Game/Events/tickets_spec.lua \
  tests/Game/State/resources_spec.lua tests/Game/harness/detect_floors.lua docs/dev/gaps.md docs/dev/ingame-ledger.md
git commit -m "feat(tickets): assume a swing's hit past its lag tolerance; a late row confirms or refunds it

Attribution-recovery decisions 51-52 (owner refinement 2026-10-23). Measured on the same seeds:
<the four variants' rage gates, flicker, Fury L24 agreement, rageErr; the kept one>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 4: The crowd gate as a ranking aid; the Snapshot line and the conservation sweep

**Files:**
- Modify: `src/Hekili/Game/Events/Kinds.lua:41-46` (`K.Flight`'s doc comment), `src/Hekili/Game/Events/Tickets.lua:77-81`
  (the crowd gate's comment), `:669-699` (Snapshot)
- Modify: `tests/Game/harness/detect_sweep_spec.lua` (the conservation identity)
- Test: `tests/Game/Events/tickets_spec.lua`

**Interfaces:**
- Produces: the Snapshot line of spec §3.5; the sweep's conservation with `confirmed`, `refunded`, `assumed` and open
  TENT and ASSUMED tickets.

- [ ] **Step 1: Write the failing test.** In `tests/Game/Events/tickets_spec.lua`, add:

```lua
    it("the crowd gate ranks, never refuses: its region pays at pass 4, replaceable (decision 53)", function()
        I.ab.rMax[I.ab.bySpell[fs.SPENDER_P]] = 30
        T.Learn("Creature-1", 20, 1.5, 9) -- bound edge 10.313; crowded edge 11.5 - 0.875 = 10.625
        ctl.now = 10
        ctl.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", fs.SPENDER_P)
        local i = 0
        for j = 1, T.CAP do
            i = (T.state[j] == T.OPEN and T.kind[j] == X.FLIGHT) and j or i
        end
        T.Foreign(T.uid[i], 8, 9.5) -- another nature source on the unit within CROWD
        ctl.now = 10.45 -- inside the bound, under the crowded edge: before, refused (foreign)
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 15, 8)
        assert.are.same({ 0, T.TENT }, { T.foreign, T.state[i] })
        ctl.now = 11.5 -- the cast's own row in its narrow band replaces it
        ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 16, 8)
        assert.are.same({ 1, 1 }, { T.replaced, T.paid[X.FLIGHT] })
    end)

    it("prints the recovery counters on the Snapshot line", function()
        local line = VS.Snapshot() -- Game/State/Snapshot.lua: every OnSnapshot line, joined
        assert.is_truthy(line:find("tentative=%d+ replaced=%d+ assumed=%d+ confirmed=%d+ refunded=%d+"))
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua`
Expected: the crowd case PASSES already (Tasks 1-2 made the region Overdue and replaceable; it guards decision 53);
the Snapshot case FAILS.

- [ ] **Step 3: The Snapshot line.** In `Tickets.lua`'s `I.OnSnapshot`, count `tentative` (`state[i] == T.TENT`) in the
  open loop and append to the format string `" tentative=%d replaced=%d assumed=%d confirmed=%d refunded=%d"` with
  `tentative, T.replaced, c.assumed, c.confirmed, c.refunded`. (After Task 3 kept "expiry", drop `assumed`, `confirmed`,
  `refunded` from the line and from spec §3.5 in the same commit.)

- [ ] **Step 4: Comments.** `K.Flight`'s doc comment: replace "the widened band's lower edge is lagE less CLOSE / v per
  second of it (at least b) instead of the bound." with "the widened band's lower edge is lagE less CLOSE / v per second
  of it (at least b) instead of the bound; a row between the two is Overdue (pass 4), never refused (attribution-recovery
  decision 53)." Same sentence appended to the crowd-gate comment at `Tickets.lua:77-81`.

- [ ] **Step 5: The sweep.** In `tests/Game/harness/detect_sweep_spec.lua`, the conservation check sums `T.closed`
  and the open tickets; make sure the open count takes every state 1-5 (`T.state[i] ~= T.FREE`) and that the new keys
  are summed (they are, if it iterates `pairs(T.closed)`; if it names keys, add the three).

- [ ] **Step 6: Run**

Run: `.lua/bin/busted tests/Game/Events/tickets_spec.lua && .lua/bin/busted --tags=slow tests/Game/harness/detect_sweep_spec.lua && make check`
Expected: PASS; the sweep's conservation holds on every seed.

- [ ] **Step 7: Commit**

```bash
git add src/Hekili/Game/Events/Kinds.lua src/Hekili/Game/Events/Tickets.lua tests/Game/Events/tickets_spec.lua \
  tests/Game/harness/detect_sweep_spec.lua
git commit -m "feat(tickets): the crowd gate ranks, never refuses; recovery counters on the Snapshot line

Attribution-recovery decisions 53 and 56; the sweep's conservation counts confirmed, refunded,
assumed and the TENT/ASSUMED open tickets.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 5: Detection suite: recovery and net wash; the floors; the gate; the docs

**Files:**
- Modify: `tests/Game/harness/drive.lua` (the verdict's time), `tests/Game/harness/metrics.lua` (`recovery`, `wash`,
  `lostDiff` with `assumed`), `tests/Game/harness/detect.lua` (`cell`, `record`, `check`)
- Modify: `tests/Game/harness/detect_floors.lua` (regenerated)
- Modify: `docs/dev/gaps.md` (the running-mob row, the 9b finding), `docs/dev/ingame-ledger.md` (U17, U18),
  `CHANGELOG.md` (known issues), `docs/superpowers/specs/2026-10-23-attribution-recovery-design.md` (Status: BUILT)
- Test: `tests/Game/harness/metrics_spec.lua`

**Interfaces:**
- Produces: `m.falseRows`, `m.recovered`, `m.recoverMs` (a list, for the median), `m.washNet`, `m.washGross`,
  `m.washFights` in `metrics.newTickets()`; `metrics.recovered100(m)`, `metrics.wash(m)`; cells `recovered100`
  (floor) and `wash` (ceiling).
- Consumes: Task 2's `c.replacedAt`; the drive's `c.verdict` (`drive.lua:214-223`) and a new `c.verdictT`.

- [ ] **Step 1: Write the failing test.** In `tests/Game/harness/metrics_spec.lua`, add:

```lua
    it("recovery: a false credit replaced, re-pinned, neutral or unrecovered; wash: own swaps' net error", function()
        local m = metrics.newTickets()
        metrics.recoverRow(m, 10.0, 10.3, 0, false) -- replaced 300 ms later
        metrics.recoverRow(m, 11.0, 0, 11.5, false) -- re-pinned by a verdict 500 ms later
        metrics.recoverRow(m, 12.0, 0, 0, true) -- neutral: it staged nothing
        metrics.recoverRow(m, 13.0, 0, 0, false) -- unrecovered
        assert.are.equal(75, metrics.recovered100(m))
        assert.are.same({ 300, 500 }, { math.floor(m.recoverMs[1] + 0.5), math.floor(m.recoverMs[2] + 0.5) })
        metrics.washFight(m, { 9, -9, 4 }) -- signed per-swap rage errors of one fight
        metrics.washFight(m, {})
        assert.are.equal(2, metrics.wash(m)) -- mean absolute net per fight: (|4| + 0) / 2
        assert.are.equal(11, m.washGross) -- 9 + 9 + 4 over 2 fights
    end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/harness/metrics_spec.lua`
Expected: FAIL: `metrics.recoverRow` is nil.

- [ ] **Step 3: The metrics.** In `tests/Game/harness/metrics.lua`, add to `M.newTickets()`'s table:
  `falseRows = 0, recovered = 0, recoverMs = {}, washNet = 0, washGross = 0, washFights = 0,`. Add:

```lua
--- One false credit at `t`: replaced at `replacedT` (0 none), re-pinned at `pinT` (0 none), or `neutral` (it staged
--- nothing). Records the ms to the earlier recovery (attribution-recovery spec §5.2).
function M.recoverRow(m, t, replacedT, pinT, neutral)
    m.falseRows = m.falseRows + 1
    local at = 0
    if replacedT > 0 and (pinT == 0 or replacedT < pinT) then
        at = replacedT
    elseif pinT > 0 then
        at = pinT
    end
    if at > 0 then
        m.recovered = m.recovered + 1
        m.recoverMs[#m.recoverMs + 1] = 1000 * (at - t)
    elseif neutral then
        m.recovered = m.recovered + 1
    end
end

--- One fight's own swaps: their signed rage errors (believed - true). Adds |net| and the gross.
function M.washFight(m, errs)
    local net = 0
    for _, e in ipairs(errs) do
        net, m.washGross = net + e, m.washGross + math.abs(e)
    end
    m.washNet, m.washFights = m.washNet + math.abs(net), m.washFights + 1
end

function M.recovered100(m)
    return m.falseRows > 0 and 100 * m.recovered / m.falseRows or 100
end
function M.wash(m)
    return m.washFights > 0 and m.washNet / m.washFights or 0
end
```

  In `M.tickets`, where a spell row is counted false (`m.falsePaid` rises), call
  `M.recoverRow(m, g.t, c.replacedAt[idx] or 0, 0, (c.staged[idx] or 0) == 0)` with `idx` the group's paying stream
  index (record it beside `g.at` when the group is built: `g.idx = i`). In `M.score` (the melee tally), where a credit is
  counted false (`falseNet`'s population), call `M.recoverRow(m.tk or m, t, c.replacedAt[i], c.verdict[i] == 2 and
  c.verdictT[i] or 0, false)`; and collect, per fight, for each own white row `i` credited to another of our swings
  (`c.crHand[i] > 0` and `c.crAt[i] ~= s.swingT[i]`), the signed error
  `val(c.crHand[i], class) - val(s.hand[i], class)` with `val(h, class)` = 0 for an avoid,
  `I.SwingValue(slot, h, 0) * scale` for a hit, plus `I.SwingCrit(slot, h, 0)` for a crit (`slot` the rage slot,
  `c.I.res.slotOf[fs.RAGE]`); pass the list to `M.washFight(m.tk or m, errs)`. In `M.ticketLine`, append
  `" recovered/100=%.1f wash=%.2f (gross %.1f)"`. `lostDiff` in `detect.lua`'s `cell` becomes
  `math.abs(m.lostEngine + m.assumedEngine - m.lostTruth)` with `m.assumedEngine` counted like `lostEngine` from
  `T.closed.assumed` (0 when Task 3 kept "expiry").

- [ ] **Step 4: The drive's verdict time.** In `drive.lua`'s verdict wrapper (line 223), beside
  `c.verdict[i] = ...`, set `c.verdictT[i] = t`; allocate and reset `c.verdictT` beside `c.verdict` (lines 68, 447).
  `M.run` in `detect.lua` passes the melee tally's recovery into the same `m` (`m.melee.tk = m`).

- [ ] **Step 5: Cells.** In `detect.lua`'s `cell`, add `recovered100 = down(metrics.recovered100(m) / 100) * 100` and
  `wash = up(metrics.wash(m))`; extend `record`'s format with `recovered100 = %.0f, wash = %.1f` and `check` with
  `assert(v.recovered100 >= (fl.recovered100 or 0), ...)` and `assert(v.wash <= (fl.wash or math.huge), ...)`.

- [ ] **Step 6: Run, regenerate, check**

Run: `.lua/bin/busted tests/Game/harness/metrics_spec.lua`
Expected: PASS.

Run: `DETECT_WRITE=1 .lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua && .lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua tests/Game/harness/detect_sweep_spec.lua`
Expected: the rewrite, then PASS. Compare `git diff` of `detect_floors.lua` against spec §5.1's table; every cell
moved since 093313ae is listed in the commit message with its direction.

- [ ] **Step 7: The gate**

Run: `make gate`
Expected: exit 0. Then compare every wowsims replay and loop line with the gate on 093313ae
(`git stash; make gate > /tmp/gate-base.txt; git stash pop`, or the gate log of 093313ae): no replay floor down, no
loop floor down, flicker floors not up, Fury L24 agreement up (state the number), `make bench-ta` at or above 97000
rows/s.

- [ ] **Step 8: Docs.** `docs/dev/gaps.md`: the "Running-mob widening in crowds" row gains "Since 2026-10-23
  (attribution-recovery decision 53) the crowd region pays at pass (d), replaceable; <K4 party, busy recall / false
  credit now>"; the deferred minors list loses "The cascade bound (spec §3.4) has no single test" if Task 1's FIFO test
  covers it, else keeps it. `docs/dev/ingame-ledger.md`: add rows U17 and U18 (spec §7) under the open probes, and
  update the K10 finding with its new numbers. `CHANGELOG.md`'s Unreleased known issues: replace "In a crowded pull
  with a laggy connection, white swings are credited less often ..." and "Fast dual-wield rage can still read low ..."
  with the measured state, and add one line for players: "Late or out-of-order hits now still count: a swing whose
  result arrives late is assumed to have hit and is corrected (without the icon jumping) when its result arrives."
  Set the spec's Status line to "BUILT (plan ...); Task 3 kept <variant>".

- [ ] **Step 9: Commit**

```bash
git add tests/Game/harness/drive.lua tests/Game/harness/metrics.lua tests/Game/harness/metrics_spec.lua \
  tests/Game/harness/detect.lua tests/Game/harness/detect_floors.lua docs/dev/gaps.md docs/dev/ingame-ledger.md \
  CHANGELOG.md docs/superpowers/specs/2026-10-23-attribution-recovery-design.md
git commit -m "test(detect): recovery and net-wash metrics; floors regenerated under the 2026-10-23 ruling

Attribution-recovery decisions 54-56. Named cause: the owner's ruling (recall over precision).
<moved cells; gate comparison: replay, loop, flicker, Fury L24 agreement, bench-ta>

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 6: Research and spec: parry haste (research + spec only, no code)

**Files:**
- Create: `docs/research/2026-10-xx-parry-haste.md` (the date of the work)
- Modify: `docs/superpowers/specs/2026-10-23-attribution-recovery-design.md` (§8 gains its spec section, or a new spec
  `docs/superpowers/specs/2026-10-xx-parry-haste-design.md` that §8 links)
- Modify: `docs/dev/ingame-ledger.md` (the capture as a probe row, PH1)

**Interfaces:** none (no code). The deliverable is a spec section a plan can be written from.

- [ ] **Step 1: The rule, from wowsims.** Read `~/src/wowsims-forever/sim/core/attack.go:1173-1207`
  (`applyParryHaste`), where `PseudoStats.ParryHaste` is set (`sim/core/character.go:424`, `sim/core/target.go:230`)
  and any test that pins it (`grep -rn "ParryHaste\|parry haste" ~/src/wowsims-forever/sim --include=*_test.go`). Write
  down: the 20% floor, the 40% reduction, main hand only, both directions (a target with the option, a character that
  can parry), and whether a parried special attack (not a white swing) also triggers it (`OnSpellHitTaken` fires for
  every spell; check the outcome mask).

- [ ] **Step 2: The rule, from the game.** Write the capture instructions for the owner into the research note and the
  ledger row PH1 (the owner cannot copy chat: the ForeverProbe recorder, `/vslog`, writes the copy box, lines under 255
  chars): (a) a melee character auto-attacking a mob that parries: ten `UNIT_COMBAT target PARRY` rows, with
  `PLAYER_SWING` (payload speed, hand) and `UNIT_COMBAT player` rows around each; (b) a tank or a melee with Parry:
  ten `UNIT_COMBAT player PARRY` rows with our `PLAYER_SWING` before and after. Measure each shortening against
  `min(0.4 x speed, remaining - 0.2 x speed)`. The one existing sample (`docs/research/2026-10-16-swing-outcome-pairing.md:28`:
  771 -> 2110 ms on a 2.2 s weapon) goes in as the first row.

- [ ] **Step 3: What each belief must do on a PARRY row on us.** Read and answer, with file:line citations:
  - `VS.SwingPending` (`src/Hekili/Game/State/Families/Resources.lua:1269-1285`, `Tickets.lua:320-330`): a past swing;
    expected: unchanged. Confirm.
  - The next-swing forecast: `src/Hekili/Game/State/Sources/Swing.lua` (`Obs.Swing` c = 4 at `PLAYER_SWING`),
    Hekili's `state.swings.mh_actual` and speed, `src/Hekili/Engine/Sim/State.lua`'s swing forecast and rage gain; say
    whether the next main-hand swing time must move earlier at the parry row, by which observation (a new
    `Obs.Swing` code or a `Swing` source re-anchor), and what the simulation reads.
  - The swing ticket anchor (`Rows.lua:95-116`): `PLAYER_SWING` comes at the real (hastened) swing, so expected:
    unchanged. Confirm from the capture.
  - A mob parrying us: `src/Hekili/Game/Events/Attackers.lua:43-75` (per-attacker anchor and period) and
    `ATTACK_TOLERANCE` 0.2 s (`:24`): the mob's next hit can come up to 0.4 x its period early; say whether its clock
    re-anchors at our swing's PARRY row on that mob, and what the hits-on-us credit (onus) gains.
- [ ] **Step 4: The replay and the gates.** The wowsims replay simulates it already (`tools/wowsims/export.lua:40`,
  `tests/Forever/wowsims/*.json:15` `parryHaste: true`). From the replay logs of Fury, Arms and Protection (and Feral,
  Enhancement, Retribution), count the parries and the loop disagreements within one swing after each, and estimate
  what modelling it would move (agreement, flicker, rage error). Say whether the harness world should model it
  (`tests/Game/harness/scenarios.lua:102-103`'s shortcut) and which floors would move, in which direction.
- [ ] **Step 5: The spec section.** Write it ready for a plan: the observation(s) it adds, the belief changes (files,
  functions), the harness change, the floors expected to move with their direction, the probes left open, and its
  decisions numbered after this spec's last.
- [ ] **Step 6: Commit**

```bash
git add docs/research/2026-10-xx-parry-haste.md docs/superpowers/specs/2026-10-23-attribution-recovery-design.md \
  docs/dev/ingame-ledger.md
git commit -m "docs(research): parry haste on Forever, and the spec section for it

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```
