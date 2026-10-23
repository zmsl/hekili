# Parry Haste Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Model parry haste both ways as the game rule: when a unit that is auto-attacking parries any attack, its
pending main-hand swing (due in `r` s, duration `d`) is pulled by `min(0.4 d, r - 0.2 d)` when `r > 0.2 d`, else not at
all; the off hand never. Our parry moves our believed next main-hand swing (the swing family, Hekili's `nextMH`, the
rage forecast, `mainhand_remains`); a mob's parry moves its attacker clock; the harness world hastens both directions;
the replay feeds the tank logs' parries.

**Ruling:** the owner, 2026-10-23: "let's assume that the increase in swing speed for the next swing is a consistent
rule for us and enemies". wowsims's `applyParryHaste` (`~/src/wowsims-forever/sim/core/attack.go:1173-1207`: the
parrier's main hand only, any parried attack, both directions) is Forever's rule. It supersedes the spec's probe gate:
ledger row PHS1 becomes a launch-day (2026-11-04) confirmation, not a prerequisite.

**Architecture:** One pure helper, `L.ParryPull(r, d)` (`Game/Events/Melee.lua`, constants `L.PARRY_PULL` 0.4 and
`L.PARRY_FLOOR` 0.2: a game rule, no pack field), read by the swing family (our parry, `Obs.PlayerHit` a = PARRY) and
by `Game/Events/Attackers.lua` (a PARRY row on a mob's token). The family exposes `VS.SwingPull(1)`: the pull **and
the swing it was taken from**; Hekili's reset applies it as `mh_pseudo` and to `nextMH` only while `mh_actual` is that
swing. The harness world keeps its own copy of the rule (`behaviours.parryPull`, pinned equal by a test) and
reschedules a parrier's main-hand swing; the replay emits the target's Parry lines as its swings at us.

**Tech Stack:** Lua 5.1 (WoW), busted, luacheck, StyLua, the combat harness (`tests/Game/harness/`), the wowsims replay
gates (`tests/Forever/wowsims_*_spec.lua`).

**Spec:** `docs/superpowers/specs/2026-10-23-parry-haste-design.md` (decisions 57-64, binding except where this plan
says "amends"); research `docs/research/2026-10-23-parry-haste.md`. Line numbers are as of `forever-attribution-2`
97af35e2.

## Amendments to the spec (recorded in its Status line by Task 5)

1. **The pull is keyed to its swing, not cleared at `Obs.Swing` c = 4** (spec §2 said c = 4 resets `pull[1]`; the
   parry-haste reviewer's minor asked for a well-defined order against `mh_actual`). Hekili's `mh_actual` is set by
   the swing's own row (`Engine/Sim/Events.lua:1676-1679`, fed by `Game/Events/Rows.lua:247`), which lands a landing
   lag (median 0.47 s) **after** `PLAYER_SWING`, while `Obs.Swing` c = 4 is staged at `PLAYER_SWING`
   (`Sources/Swing.lua:19-26`). Clearing at c = 4 would make `nextMH` read late by the pull for that lag; keeping it
   past c = 4 unkeyed would let a parry taken against the new swing shift the old `mh_actual` (an early `nextMH`). So
   `VS.SwingPull(1)` returns `pull, from` (`from` = `VS.LastSwing(1)` when the pull was taken), the family restarts the
   pull when a parry comes after a newer swing, and the reset applies it only when `|mh_actual - from| < 1 ms`. One
   poll can never apply a pull to a swing other than the one it was computed from. This is the reviewer's second option
   ("apply it only while ...") made exact.
2. **No `parryHaste` opt-in:** the world hastens by default (`W.parryHaste = true`); the field exists only for the
   Task 4 A/B and is never set false in a committed test.
3. **Replay scope (spec open question 3):** only the target's Parry lines on us; its blocks, dodges and wounds stay
   unreplayed (gap AH, narrowed).
4. **Count correction:** `paladin_protection.log` has 11 Parry lines, not the research's 18 (7 of them hastened, as the
   research says: gaps 0.9 s x5, 1.3 s, 1.43 s after a 1.5 s swing). Warrior Protection: 14, 6 hastened, as written.

## Global Constraints

- Core/pack boundary: nothing under `src/Hekili/Game`, `tests/Game/` or `tests/Game/harness` names a class, spec,
  spell, aura or form (`tests/boundary_spec.lua`); the outcome word PARRY is already core vocabulary
  (`Melee.lua:64`, `VirtualState.lua:66`). Harness comments say "the tank logs", never the spec names. Only
  `tests/Forever/` may name the Warrior world.
- Secret safety: no new client read. `UNIT_COMBAT`'s unit and action reach `S.On` handlers plain or nil (the facade
  nils a secret slot, `EventFacade.lua` onEvent); `PLAYER_SWING`'s payload is plain in combat.
- No allocation in recurring paths: the `Obs.PlayerHit` handler, `VS.SwingPull`, the Attackers branch and the reset
  branch use locals and preallocated arrays only (Task 1's alloc case; `tests/Game/State/alloc_spec.lua`;
  `tests/Game/Events/cleu_rows_spec.lua` "allocates nothing per paired swing"). Harness code (`behaviours.lua`,
  `world.lua`, `replay.lua`) is test code and allocates freely.
- The belief and the world change together (spec §5): Tasks 1-3 change the belief only, so a harness gate that runs
  the world (the `#slow` tier: solo, detect, onus, flicker, the wowsims replays; `make test-loop`) may dip between
  them. Tasks 1-3 gate on `make test-fast`, lint, format, types and syntax; **`make check` is green from Task 4's
  commit on**, and `make gate` before the merge. No floor is edited before Task 4.
- Floors (decision 64, under the owner's ruling as the named cause): every wowsims replay floor holds (none moves
  down; Warrior Protection may rise by at most +2/94 and Paladin Protection by at most +1/46 from parry haste alone,
  research §4; a rise beyond that is attributed in the commit message by the A/B in Task 4 Step 7); the solo safety
  gates (`tests/Game/harness/solo_spec.lua:18-26`: `over`, `lo`, `danger`, the false rates) do not move at all (a
  failure stops the task for the owner); detection floors (`tests/Game/harness/detect_floors.lua`) and loop floors
  (`make test-loop`, `make gate`) may move with this plan as the named cause, each moved cell listed in Task 4's commit
  message with the A/B that attributes it; flicker floors do not move up.
- Every commit ends with the trailer:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw`.

## Module Layout

| File | Change | Tested by |
|---|---|---|
| `src/Hekili/Game/Events/Melee.lua` | `L.PARRY_PULL`, `L.PARRY_FLOOR`, `L.ParryPull(r, d)` | `tests/Game/State/swing_spec.lua` |
| `src/Hekili/Game/State/Families/Swing.lua` | `Obs.PlayerHit` a = PARRY pulls hand 1's anchor; `pull`, `pullFrom`; `VS.SwingPull(hand)`; cleared at combat end and build | `swing_spec.lua` |
| `src/Hekili/Engine/Sim/State.lua` | reset: `mh_pseudo` and `nextMH` from the keyed pull, then the swing forecast | `tests/Forever/parry_haste_spec.lua` (new) |
| `src/Hekili/Game/Events/Attackers.lua` | a PARRY row on a hostile's token pulls its clock, once per GUID and row time | `tests/Game/Events/cleu_rows_spec.lua` |
| `tests/Game/harness/behaviours.lua` | `M.parryPull`; `melee` and `mob` keep each swing's due time and generation, `e.hasten` | `tests/Game/harness/world_spec.lua` |
| `tests/Game/harness/world.lua` | `W.parryHaste` (true); `W.emit` hastens the parrier of a parried swing, strike or spell | `world_spec.lua` |
| `tests/Game/harness/replay.lua` | the target's Parry line on us parsed as `taken`, emitted as its swing at us | `tests/Game/harness/replay_spec.lua`, the Protection replays |
| `tests/Game/harness/scenarios.lua` | the shortcut comment loses "no parry haste" | none |
| docs: the spec, the research table, `docs/dev/gaps.md`, `docs/dev/ingame-ledger.md`, `CHANGELOG.md` | status, AH narrowed, PHS1 as launch-day confirmation, the player line | `tests/Forever/changelog_spec.lua` |

## Review Focus

1. **The pull's order against `mh_actual` (reviewer minor).** `VS.SwingPull(1)` returns `pull, from`; the reset applies
   it only when `mh_actual` is `from`. Check the four states: before the pulled swing (applied); between the pulled
   swing's `PLAYER_SWING` and its row (still applied: `mh_actual` is the old swing, the pull still names it, so
   `nextMH` = the real swing just taken, not late); after its row (not applied: `mh_actual` moved on); a parry between
   a `PLAYER_SWING` and its row (a new `from`, not applied until that row). No path adds a pull taken against one swing
   to another (`pullFrom ~= last[1]` restarts it).
2. **The rule in three places agrees.** `L.ParryPull` (belief), `Attackers.lua` (through `L.ParryPull`) and
   `behaviours.parryPull` (world, a deliberate copy: the truth runs no addon code) are pinned equal on a grid
   (`world_spec.lua`) and on the replay's pulls (`swing_spec.lua`).
3. **Once per row.** The same mob PARRY row arrives on target, plate and soft tokens; Attackers applies it once per
   (GUID, row time). A second application is visible in Task 3's test (the hit falls off the clock).
4. **The world hastens at the server's moment.** `W.emit` hastens at the swing, strike or spell event; the outcome
   row comes a landing lag later (our swings) or at once (others'). The belief reads the row (decision 61): `r` is up
   to that lag short in the 20% branch, exact in the 40% branch.
5. **Allocation.** No table, closure, `{...}` or string in the `Obs.PlayerHit` handler, `VS.SwingPull`, `parried` or
   the reset branch; `ForecastSwingbasedResources` runs only while a pull is live.
6. **Floors.** The replay floors hold; the solo safety gates are untouched; every other moved floor is listed with its
   A/B (world on/off) and the baseline from Task 1 Step 1.

## Task order

1. The belief: `L.ParryPull`, our parry pulls the main hand, `VS.SwingPull`
2. Hekili's reset applies the keyed pull to `mh_pseudo` and `nextMH`
3. The attacker clocks: a mob's parry pulls its clock
4. The harness: the world hastens both ways, the replay feeds the Parry lines; every gate
5. Docs: the spec's status and amendments, gaps, the ledger, the changelog

---

### Task 1: The belief: our parry pulls our next main-hand swing

**Files:**
- Modify: `src/Hekili/Game/Events/Melee.lua` (after `L.FOREIGN_AVOIDS = 0.05`, line 37)
- Modify: `src/Hekili/Game/State/Families/Swing.lua` (state :20-24, `OnBuild` :27-39, after `after` :93-102, `CombatEnd`
  :152-156, after `VS.LastSwing` :188-191)
- Test: `tests/Game/State/swing_spec.lua`

**Interfaces:**
- Produces: `L.ParryPull(r, d)` (`I.Log.ParryPull`): seconds, `min(L.PARRY_PULL x d, r - L.PARRY_FLOOR x d)` when
  `d > 0` and `r > L.PARRY_FLOOR x d`, else 0. Pure; allocates nothing.
- Produces: `VS.SwingPull(hand)`: `pull, from` for hand 1 (the summed pull of the pending main-hand swing, and
  `VS.LastSwing(1)` at the parry that started it); `0, 0` for hands 2 and 3, before any parry and after combat end.
- Consumes: `Obs.PlayerHit` (`o.a` = `I.HitKind.PARRY` 5, `o.t` the row's time; `Sources/Player.lua:167-188`),
  `I.inCombat`, the family's `anchorT`, `speed`, `last`, `after`.

- [ ] **Step 1: The baseline (decision 64).** Before any change, record the gates this plan may move:

Run:
```bash
mkdir -p /tmp/ph
.lua/bin/busted --tags=wowsims tests/Forever/wowsims_warrior_spec.lua tests/Forever/wowsims_paladin_spec.lua 2>&1 | grep "wowsims:" > /tmp/ph/replay-base.txt
.lua/bin/busted --tags=slow tests/Game/harness/solo_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/flicker_spec.lua tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua > /tmp/ph/slow-base.txt 2>&1
make test-loop > /tmp/ph/loop-base.txt 2>&1; tail -3 /tmp/ph/loop-base.txt
cat /tmp/ph/replay-base.txt
```
Expected: every run passes; `replay-base.txt` holds every replay line, among them the two Protection lines (Warrior
on-GCD agreement 0.979 of 94). Keep `/tmp/ph/` for Task 4.

- [ ] **Step 2: Write the failing tests.** In `tests/Game/State/swing_spec.lua`, add at the top
  `local alloc = require("Game.State.helpers.alloc")` after the `fs` require, and after the "clears anchors at combat
  end and keeps speeds" case (line 93) add:

```lua
    describe("parry haste (parry-haste spec decisions 57-59, the owner's ruling 2026-10-23)", function()
        -- in combat: the main hand (2.0 s) swung at 100, next at 102; the off hand (2.0 s) at 100.1
        local function swung()
            I.inCombat = true
            S.Direct(Obs.Swing, 100, 1, 2.0, 4)
            S.Direct(Obs.Swing, 100.1, 2, 2.0, 4)
            I.Fold(100.1, false)
        end
        local function parry(t)
            S.Direct(Obs.PlayerHit, t, I.HitKind.PARRY, 0, 60)
            I.Fold(t, false)
        end
        local function near(want, got)
            assert.is_true(math.abs(want - got) < 1e-9, ("%.6f vs %.6f"):format(got, want))
        end

        it("L.ParryPull: the replay's pulls; nothing at or under 20% of the swing left", function()
            local P = I.Log.ParryPull
            near(0.2264, P(0.697, 2.353)) -- the 20% branch: 0.697 - 0.4706
            near(0.9412, P(2.0, 2.353)) -- the 40% branch
            near(0.6, P(1.2, 1.5))
            near(0.2, P(0.5, 1.5))
            near(0.068, P(0.368, 1.5))
            assert.are.same({ 0, 0, 0 }, { P(0.3, 1.5), P(0.2, 1.5), P(1, 0) })
        end)

        it("pulls the next main-hand swing by 40% of its duration when more than 60% is left", function()
            swung()
            parry(100.5) -- r = 1.5 > 1.2: 0.8
            near(101.2, VS.Swing(1, 100.5).est)
            local x, from = VS.SwingPull(1)
            near(0.8, x)
            assert.are.equal(100, from)
            near(103.2, VS.Swing(1, 101.3).est) -- the swings after it move with it until the next PLAYER_SWING
        end)

        it("pulls it down to 20% of its duration when 20-60% is left", function()
            swung()
            parry(101.3) -- r = 0.7: 0.7 - 0.4
            near(101.7, VS.Swing(1, 101.3).est)
            near(0.3, (VS.SwingPull(1)))
        end)

        it("pulls nothing at or under 20% left", function()
            swung()
            parry(101.7) -- r = 0.3 <= 0.4
            near(102, VS.Swing(1, 101.7).est)
            assert.are.same({ 0, 0 }, { VS.SwingPull(1) })
        end)

        it("never pulls the off hand; a second parry pulls again from the pulled time", function()
            swung()
            parry(100.2) -- r = 1.8: 0.8, next 101.2
            parry(100.3) -- r = 0.9: min(0.8, 0.5), next 100.7
            near(100.7, VS.Swing(1, 100.3).est)
            near(1.3, (VS.SwingPull(1)))
            near(102.1, VS.Swing(2, 100.3).est)
            assert.are.same({ 0, 0 }, { VS.SwingPull(2) })
        end)

        it("keys the pull to its swing: a later swing is never pulled by it; combat end clears it", function()
            swung()
            parry(100.5) -- 0.8, taken from the swing at 100
            S.Direct(Obs.Swing, 101.2, 1, 2.0, 4) -- the hastened swing
            I.Fold(101.2, false)
            near(103.2, VS.Swing(1, 101.2).est) -- the real swing's anchor: the pull is not applied again
            local x, from = VS.SwingPull(1)
            near(0.8, x)
            assert.are.equal(100, from) -- still the swing at 100: a reader whose last swing is 101.2 ignores it
            parry(101.5) -- r = 1.7: 0.8 from the swing at 101.2, a new pull, not added to the old one
            x, from = VS.SwingPull(1)
            near(0.8, x)
            assert.are.equal(101.2, from)
            S.Direct(Obs.CombatEnd, 102)
            I.Fold(102, false)
            assert.are.same({ 0, 0 }, { VS.SwingPull(1) })
        end)

        it("allocates nothing per parry", function()
            swung()
            local n = 0
            local bytes = alloc.bytes(function()
                n = n + 1
                local t = 100 + 2 * n
                S.Direct(Obs.Swing, t, 1, 2.0, 4)
                S.Direct(Obs.PlayerHit, t + 0.5, I.HitKind.PARRY, 0, 60)
                I.Fold(t + 0.5, false)
                VS.SwingPull(1)
            end, 2000)
            assert.are.equal(0, bytes)
        end)
    end)
```

- [ ] **Step 3: Run them**

Run: `.lua/bin/busted tests/Game/State/swing_spec.lua`
Expected: FAIL: the pull cases read the unpulled swing (`102.000000 vs 101.200000`), the rule case "attempt to call
local 'P' (a nil value)", the keyed cases "attempt to call field 'SwingPull' (a nil value)"; the existing cases pass.

- [ ] **Step 4: The rule.** In `src/Hekili/Game/Events/Melee.lua`, after `L.FOREIGN_AVOIDS = 0.05` add:

```lua
-- Parry haste (parry-haste spec decision 57; wowsims's attack.go applyParryHaste, taken as Forever's rule by the
-- owner's ruling of 2026-10-23): a unit that parries pulls its main-hand swing, due in r s of duration d, by
-- min(PULL x d, r - FLOOR x d) when r > FLOOR x d. A game rule: no pack field. PHS1 confirms it on launch day.
L.PARRY_PULL, L.PARRY_FLOOR = 0.4, 0.2

--- The pull (seconds) of a parrier's main-hand swing due in `r` s with duration `d`; 0 when none. Allocates nothing.
function L.ParryPull(r, d)
    local least = L.PARRY_FLOOR * d
    if d <= 0 or r <= least then
        return 0
    end
    local cap = L.PARRY_PULL * d
    return r - least < cap and r - least or cap
end
```

- [ ] **Step 5: The swing family.** In `src/Hekili/Game/State/Families/Swing.lua`:

  After `local swingRec, speedRec, haste = {}, {}, nil` (line 24) add:

```lua
-- Parry haste (parry-haste spec decision 59): the main hand's pull and the swing it was taken from (VS.SwingPull)
local pull, pullFrom = 0, 0
```

  In `I.OnBuild`, after `haste = I.NewBelief("haste melee")` (line 37) add `pull, pullFrom = 0, 0`.

  After the `after` function (line 102) add:

```lua
-- Our parry (Obs.PlayerHit a = PARRY): the main hand's pending swing comes early by L.ParryPull; the anchor moves, so
-- every later predicted swing does until the next PLAYER_SWING re-anchors. The pull is kept with the swing it was taken
-- from (VS.SwingPull), and restarts when a parry comes after a newer swing. Off hand never. Allocates nothing.
I.On(Obs.PlayerHit, function(o, t)
    if o.a ~= I.HitKind.PARRY or not I.inCombat or anchorT[1] <= 0 or speed[1] <= 0 then
        return
    end
    -- I.Log at call time: Events/CombatLog.lua loads after the families
    local x = I.Log.ParryPull(after(1, o.t) - o.t, speed[1])
    if x <= 0 then
        return
    end
    if pullFrom ~= last[1] then
        pull, pullFrom = 0, last[1]
    end
    anchorT[1], pull = anchorT[1] - x, pull + x
    I.Sample(swingRec[1], "modelled", after(1, o.t), t, Obs.PlayerHit)
end)
```

  In the `Obs.CombatEnd` handler (line 152), after the loop add `pull, pullFrom = 0, 0`.

  After `VS.LastSwing` (line 191) add:

```lua
--- (parry-haste spec decision 59) The parry-haste pull of the main hand's next swing (seconds) and the time of the swing
--- it was taken from (VS.LastSwing(1) at the parry): a reader applies it only to that swing. 0, 0 for hands 2 and 3,
--- before a parry and after combat end. Allocates nothing.
function VS.SwingPull(hand)
    if hand ~= 1 then
        return 0, 0
    end
    return pull, pullFrom
end
```

- [ ] **Step 6: Run the unit tests**

Run: `.lua/bin/busted tests/Game/State/swing_spec.lua tests/Game/State/alloc_spec.lua tests/Game/State/resources_spec.lua`
Expected: PASS, 0 failures.

Run: `make lint fmt-check typecheck syntax && make test-fast`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add src/Hekili/Game/Events/Melee.lua src/Hekili/Game/State/Families/Swing.lua tests/Game/State/swing_spec.lua
git commit -m "feat(swing): our parry pulls our next main-hand swing (parry haste)

Parry-haste decisions 57-59 under the owner's ruling of 2026-10-23 (wowsims's rule is Forever's):
L.ParryPull(r, d) = min(0.4 d, r - 0.2 d) when r > 0.2 d; the main hand only. VS.SwingPull(1)
returns the pull and the swing it was taken from, so a reader never applies it to a later swing.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 2: Hekili's reset applies the keyed pull

**Files:**
- Modify: `src/Hekili/Engine/Sim/State.lua:6399-6400` (after the `nextMH` / `nextOH` lines, before the E8 block)
- Create: `tests/Forever/parry_haste_spec.lua`

**Interfaces:**
- Consumes: `VS.SwingPull(1)` (Task 1), `state.swings.mh_actual` (`Engine/Sim/Events.lua:1676-1679`),
  `state.mainhand_speed`, `state:ForecastSwingbasedResources()` (`State.lua:1432`).
- Produces: while a pull taken from the swing `mh_actual` names is live: `state.swings.mh_pseudo` = `mh_actual - pull`
  (so `swings.mainhand`, the rage forecast's `last`, steps from the pulled phase), `state.nextMH` = `mh_actual - pull +
  mainhand_speed` (`mainhand_remains` in the packs reads it), and the swing-based forecast re-run. `mh_actual` stays the
  real swing. The E8 branch (`mh_actual == 0`) is unchanged.

- [ ] **Step 1: Write the failing test.** Create `tests/Forever/parry_haste_spec.lua`:

```lua
-- tests/Forever/parry_haste_spec.lua (parry-haste spec decision 59, plan amendment 1): Hekili's reset applies the
-- belief's parry-haste pull to the main hand's phase (swings.mainhand, the rage forecast's `last`) and to nextMH,
-- only while mh_actual is the swing the pull was taken from.
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")

describe("parry haste in Hekili's swing state", function()
    local H, st, VS, pull0, pending0

    before_each(function()
        H = headless.new({ character = ww.character(), pack = ww.PACK })
        assert.are.same({}, H.loadErrors)
        assert(headless.cycle(H, H.ctl.now + 0.2))
        st, VS = H.Hekili.State, H.ns.VirtualState
        pull0, pending0 = VS.SwingPull, VS.SwingPending
        VS.SwingPending = function()
            return 0
        end
    end)

    after_each(function()
        VS.SwingPull, VS.SwingPending = pull0, pending0
    end)

    -- A reset in combat with our last main-hand swing 0.3 s ago and a belief pull of `x` taken from swing `from`
    -- (an offset from that swing). Returns the swing time and the main-hand forecast entries' times.
    local function resetWith(x, fromOffset)
        local s = H.ctl.now - 0.3
        st.combat, st.swings.mh_actual = H.ctl.now - 10, s
        VS.SwingPull = function(hand)
            if hand ~= 1 then
                return 0, 0
            end
            return x, s + fromOffset
        end
        st.reset("Primary", true)
        local out = {}
        for i = 1, st.rage.fcount do
            local f = st.rage.forecast[i]
            if f.e == "mainhand" then
                out[#out + 1] = f.t
            end
        end
        return s, out
    end

    local function near(want, got)
        assert.is_true(math.abs(want - got) < 1e-6, ("%.4f vs %.4f"):format(got, want))
    end

    it("pulls nextMH, the swing phase and the rage forecast by the pull taken from mh_actual's swing", function()
        local s, f = resetWith(0.6, 0)
        local speed = st.mainhand_speed
        assert.is_true(speed > 1)
        near(s, st.swings.mh_actual) -- the real swing stays
        near(s - 0.6, st.swings.mainhand)
        near(s - 0.6 + speed, st.nextMH)
        near(s - 0.6 + speed, f[1])
    end)

    it("ignores a pull taken from another swing (its row not landed yet, or a stale one) and no pull", function()
        for _, case in ipairs({ { 0.6, 2.0 }, { 0.6, -2.0 }, { 0, 0 } }) do
            local s, f = resetWith(case[1], case[2])
            local speed = st.mainhand_speed
            near(s, st.swings.mainhand)
            near(s + speed, st.nextMH)
            near(s + speed, f[1])
        end
    end)
end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Forever/parry_haste_spec.lua`
Expected: FAIL in the first case (`st.swings.mainhand` is `s`, `nextMH` is `s + speed`); the second case passes.

- [ ] **Step 3: The reset.** In `src/Hekili/Engine/Sim/State.lua`, after

```lua
        state.nextOH = ( state.combat > 0 and state.swings.oh_actual > state.combat and state.swings.oh_actual + state.offhand_speed ) or 0
```

  add:

```lua

        -- Forever parry haste (parry-haste spec decision 59): after our parry the next main-hand swing comes early. The
        -- pull holds only while mh_actual is the swing it was taken from: that swing's row lands after its PLAYER_SWING,
        -- so a pull never shifts a later swing, nor an earlier one.
        local pull, pullFrom = VS.SwingPull( 1 )
        if pull > 0 and state.nextMH > 0 and math.abs( state.swings.mh_actual - pullFrom ) < 0.001 then
            state.swings.mh_pseudo = state.swings.mh_actual - pull
            state.nextMH = state.nextMH - pull
            state:ForecastSwingbasedResources()
        end
```

- [ ] **Step 4: Run the tests**

Run: `.lua/bin/busted tests/Forever/parry_haste_spec.lua tests/Forever/swing_pending_spec.lua tests/Forever/warrior_spec.lua tests/Forever/hunter_spec.lua`
Expected: PASS, 0 failures.

Run: `make lint fmt-check typecheck syntax && make test-fast`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Engine/Sim/State.lua tests/Forever/parry_haste_spec.lua
git commit -m "feat(state): the reset applies the parry-haste pull to nextMH and the swing phase

Parry-haste decision 59 with the plan's amendment 1: applied only while mh_actual is the swing the
pull was taken from, so one poll never reads an early nextMH from a stale pull (reviewer minor).
mh_actual stays the real swing; the rage forecast steps from the pulled phase.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 3: The attacker clocks: a mob's parry pulls its next swing

**Files:**
- Modify: `src/Hekili/Game/Events/Attackers.lua` (before the `UNIT_COMBAT` handler, line 196; its first lines
  :196-199)
- Test: `tests/Game/Events/cleu_rows_spec.lua` (the "hits on us" describe, after "learns an attacker's period from the
  gaps when its speed is secret", line 600)

**Interfaces:**
- Consumes: `L.ParryPull` (Task 1), `U.Bound`, `INDEX`, `tokSpeed`, `find`, `atkAnchor`, `atkPeriod`.
- Produces: on `UNIT_COMBAT <token> PARRY` for any token but `player`: the bound GUID's clock (anchor and period set:
  the token's plain speed, else the learned period) has its anchor moved back by `L.ParryPull(p - t, period)`, `p` its
  next predicted swing after `t`. Once per (GUID, row time). No row, no observation, no clock made.

- [ ] **Step 1: Write the failing test.** In `tests/Game/Events/cleu_rows_spec.lua`, after the "learns an attacker's
  period from the gaps when its speed is secret" case, add:

```lua
        it("pulls a hostile's clock when it parries (parry haste), once per row on several tokens", function()
            local function hit(t)
                ctl.now = t
                ctl.Fire("UNIT_COMBAT", "player", "WOUND", "", 50, 1)
            end
            local function onUsRows()
                local out = {}
                for _, g in ipairs(got) do
                    if g.row[8] == L.player then
                        out[#out + 1] = g.row[4]
                    end
                end
                return out
            end
            onUs("nameplate2", "Creature-B", 3.0) -- B alone on us: its clock at 9.5 (period 3.0: 12.5, 15.5)
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
            hit(9.5)
            ctl.unitIs.nameplate2target = nil
            ctl.Fire("UNIT_TARGET", "nameplate2")
            onUs("target", "Creature-A", 2.0) -- A alone: its clock at 10 (period 2.0: 12, 14)
            ctl.Fire("PLAYER_TARGET_CHANGED")
            hit(10)
            onUs("nameplate1", "Creature-A", 2.0) -- A's plate too: its rows come on target and nameplate1
            ctl.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            ctl.unitIs.nameplate2target = "player" -- both on us now: only the clocks name a hit
            ctl.Fire("UNIT_TARGET", "nameplate2")
            ctl.now = 10.1 -- A parries our swing: r = 1.9 > 1.2, pulled 0.8 (once: twice would be 0.8 + 0.7)
            ctl.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
            ctl.Fire("UNIT_COMBAT", "nameplate1", "PARRY", "", 0, 1)
            hit(11.2) -- A's pulled swing: on its clock (unpulled 12.0, twice-pulled 10.5; B's 12.5)
            ctl.now = 12.9 -- r = 0.3 <= 0.4: no pull
            ctl.Fire("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
            hit(13.2) -- A's next on its period (B's 12.5 and 15.5 are off it)
            assert.are.same({ "Creature-B", "Creature-A", "Creature-A", "Creature-A" }, onUsRows())
            assert.are.equal(0, L.unattributed)
        end)
```

- [ ] **Step 2: Run it**

Run: `.lua/bin/busted tests/Game/Events/cleu_rows_spec.lua`
Expected: FAIL: two rows on us, `L.unattributed` 2 (the hits at 11.2 and 13.2 are 0.8 s off A's unpulled clock,
anchored at 10); the other cases pass.

- [ ] **Step 3: The parry branch.** In `src/Hekili/Game/Events/Attackers.lua`, before
  `S.On("UNIT_COMBAT", nil, function(api, t, unit, act, flag, amount, school)` add:

```lua
-- Parry haste on a hostile (parry-haste spec decision 62): a PARRY row on its token pulls its clock's next swing by
-- L.ParryPull, whoever's attack it parried (the rule is the parrier's). One row comes on several tokens (target, plate,
-- soft target): applied once per GUID and row time. No row, no clock made. Allocates nothing.
local parriedGUID, parriedT = "", -1
local function parried(t, unit)
    local i = INDEX[unit]
    local guid = i and U.Bound(i) or ""
    if guid == "" or (guid == parriedGUID and t == parriedT) then
        return
    end
    parriedGUID, parriedT = guid, t
    local k = find(guid)
    if not k or atkAnchor[k] <= 0 then
        return
    end
    local period = i <= NT and tokSpeed[i] or 0
    if period <= 0 then
        period = atkPeriod[k]
    end
    if period <= 0 then
        return
    end
    local a = atkAnchor[k]
    local p = a + (floor((t - a) / period) + 1) * period -- its next predicted swing after t
    atkAnchor[k] = a - L.ParryPull(p - t, period)
end
```

  and replace the handler's head

```lua
    if unit ~= "player" or (act ~= "WOUND" and not MISSES[act]) then
        return
    end
```

  with

```lua
    if unit ~= "player" then
        if act == "PARRY" then
            parried(t, unit)
        end
        return
    elseif act ~= "WOUND" and not MISSES[act] then
        return
    end
```

- [ ] **Step 4: Run the tests**

Run: `.lua/bin/busted tests/Game/Events/cleu_rows_spec.lua tests/Game/Events/tickets_spec.lua tests/Game/Events/event_facade_spec.lua`
Expected: PASS, 0 failures (including "allocates nothing per paired swing").

Run: `make lint fmt-check typecheck syntax && make test-fast`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Game/Events/Attackers.lua tests/Game/Events/cleu_rows_spec.lua
git commit -m "feat(attackers): a mob's parry pulls its swing clock (parry haste)

Parry-haste decision 62: a PARRY row on a hostile's token moves its clock's anchor back by
L.ParryPull, once per GUID and row time, so its hastened hit stays on its clock with two or more
hostiles on us.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 4: The harness: the world hastens both ways, the replay feeds the Parry lines

**Files:**
- Modify: `tests/Game/harness/behaviours.lua` (after `local SAME_MS`, line 11; `M.melee` :58-205; `M.mob` :373-398)
- Modify: `tests/Game/harness/world.lua` (`M.new`'s fields :53-56; `W.emit` after the HEAL branch :112-114)
- Modify: `tests/Game/harness/scenarios.lua:102-103` (the shortcut comment)
- Modify: `tests/Game/harness/replay.lua` (header :13-14; `theirs` :145-157; the event loop's `hit` branch :688)
- Modify, if the measured value moved: `tests/Game/harness/detect_floors.lua` (regenerated), the "measured" comments
  of `tests/Forever/wowsims_warrior_spec.lua:194` and `tests/Forever/wowsims_paladin_spec.lua:98`
- Test: `tests/Game/harness/world_spec.lua`, `tests/Game/harness/replay_spec.lua`

**Interfaces:**
- Produces: `behaviours.parryPull(r, d)`: the world's copy of the rule. `e.hasten()` on every entity running `melee`
  (main hand only) or `mob`: pulls its pending main-hand swing by the rule and reschedules it (the old schedule goes
  stale by generation). `e.swingAt[h]` (melee) holds each hand's due time.
- Produces: `W.parryHaste` (default true): `W.emit` of a `swing`, `strike` or `spell` with `act == "PARRY"` calls
  `ev.dst.hasten()` when the victim has one.
- Produces: `replay.parse`: a `[Target 1] [<us> (#1)] {...} Parry` line is `{ kind = "taken", act = "PARRY", t }`; the
  replay world emits it as `{ kind = "swing", src = mob, dst = us, hand = 1, act = "PARRY", amount = 0, school = 1 }`
  (the observer already turns a hit on us into `UNIT_COMBAT player PARRY`, `observer.lua:664-665`). The log's own swing
  times carry the haste, so the replay schedules nothing.

- [ ] **Step 1: Write the failing tests.** In `tests/Game/harness/world_spec.lua`, inside "the world's resources"
  after "lets our `landed` see each of our swings land, after its land event" (line 158's case), add:

```lua
    describe("parry haste (parry-haste spec decision 63, the owner's ruling 2026-10-23)", function()
        local function ms(t)
            return math.floor(t * 1000 + 0.5) / 1000
        end
        local function swingsOf(e, hand)
            local out = {}
            for _, ev in ipairs(W.truth) do
                if ev.kind == "swing" and ev.src == e and (hand == nil or ev.hand == hand) then
                    out[#out + 1] = ms(ev.t)
                end
            end
            return out
        end

        it("its rule is the belief's L.ParryPull on a grid", function()
            local L = require("Game.State.helpers.load").module().VirtualStateInternal.Log
            for _, d in ipairs({ 1.5, 2.0, 2.353, 3.6 }) do
                for k = 0, 80 do
                    local r = d * k / 80
                    assert.are.equal(L.ParryPull(r, d), behaviours.parryPull(r, d))
                end
            end
        end)

        it("pulls the mob's next swing when it parries ours, down to 20% of its swing left", function()
            setup()
            us.avoid = { miss = 0, dodge = 0, parry = 0 }
            behaviours.melee({ rates = { miss = 0, dodge = 0, parry = 1, crit = 0 }, phase = { 1 } })(W, us)
            behaviours.mob({ phase = 0.5 })(W, mob)
            W.run(3.5)
            -- the mob at 0.5; our parried swing at 1 (its 2.5 due, r 1.5): 0.8 -> 1.7; ours at 3 (its 3.7 due, r 0.7):
            -- 0.3 -> 3.4
            assert.are.same({ 0.5, 1.7, 3.4 }, swingsOf(mob))
            assert.are.same({ 1, 3 }, swingsOf(us)) -- the attacker's own timer untouched
        end)

        it("pulls our main hand when we parry, never the off hand; nothing with the world's knob off", function()
            setup()
            us.weapons[2] = { 10, 10, 2.0 }
            us.avoid = { miss = 0, dodge = 0, parry = 1 }
            mob.weapons[1][3] = 3
            behaviours.melee({ rates = { miss = 0, dodge = 0, parry = 0, crit = 0 }, phase = { 1, 1.1 } })(W, us)
            behaviours.mob({ phase = 0.2 })(W, mob)
            W.run(4.0)
            -- parried at 0.2 (our 1 due, r 0.8): 0.4 -> 0.6; at 3.2 (our 4.6 due, r 1.4): 0.8 -> 3.8
            assert.are.same({ 0.6, 2.6, 3.8 }, swingsOf(us, 1))
            assert.are.same({ 1.1, 3.1 }, swingsOf(us, 2))
            setup()
            W.parryHaste = false
            us.avoid = { miss = 0, dodge = 0, parry = 1 }
            mob.weapons[1][3] = 3
            behaviours.melee({ rates = { miss = 0, dodge = 0, parry = 0, crit = 0 }, phase = { 1 } })(W, us)
            behaviours.mob({ phase = 0.2 })(W, mob)
            W.run(4.0)
            assert.are.same({ 1, 3 }, swingsOf(us, 1))
        end)
    end)
```

  In `tests/Game/harness/replay_spec.lua`, at the end of "the wowsims log parser" add:

```lua
    it("reads the target's Parry on us as `taken`; its other outcomes on us stay unread (gap AH)", function()
        local q = replay.parse(table.concat({
            "[4.03] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Parry (SpellSchool: 1). (Threat: 0.000)",
            "[6.34] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Block for 15.9 damage (SpellSchool: 1). (Threat: 15.9)",
        }, "\n"))
        assert.are.equal(1, #q.ev)
        assert.are.same({ 4.03, "taken", "PARRY" }, { q.ev[1].t, q.ev[1].kind, q.ev[1].act })
    end)
```

  and at the end of "the replay world" add:

```lua
    it("replays the target's Parry on us as its swing at us, at the line's time", function()
        local line = "[0.10] [Target 1] [Tester (#1)] {OtherID: 3, Tag: 1} Parry (SpellSchool: 1). (Threat: 0.000)"
        local log = text():gsub("(\n%[0%.10%][^\n]*)", "%1\n" .. line, 1) -- in time order, after the first 0.10 line
        local R = replay.new(log, H, O)
        local W = at(R.world(setmetatable({ tag = "-y" }, { __index = WO }), 1), R.pull + 0.2)
        local got = {}
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" and ev.dst == W.ents[1] then
                got[#got + 1] = { math.floor((ev.t - R.pull) * 1000 + 0.5), ev.act, ev.src == W.ents[2] }
            end
        end
        assert.are.same({ { 100, "PARRY", true } }, got)
    end)
```

- [ ] **Step 2: Run them**

Run: `.lua/bin/busted tests/Game/harness/world_spec.lua tests/Game/harness/replay_spec.lua`
Expected: FAIL: `behaviours.parryPull` is nil; the mob's swings are `{ 0.5, 2.5 }`; ours `{ 1, 3 }`; the parse case
finds 0 events; the replay world emits no swing at us. The existing cases pass.

- [ ] **Step 3: The world's rule and the behaviours.** In `tests/Game/harness/behaviours.lua`, after
  `local SAME_MS = { "MISS", "DODGE", "PARRY" }` add:

```lua

--- Parry haste (parry-haste spec decision 57; wowsims's attack.go applyParryHaste, the owner's ruling 2026-10-23):
--- the pull of a parrier's main-hand swing due in `r` s of duration `d`. The world's own copy of the belief's
--- L.ParryPull (world_spec pins them equal): the truth runs no addon code.
function M.parryPull(r, d)
    if d <= 0 or r <= 0.2 * d then
        return 0
    end
    return math.min(0.4 * d, r - 0.2 * d)
end
```

  In `M.melee`, replace

```lua
        e.lastSwing, e.landAt = { 0, 0 }, { 0, 0 }
        for h = 1, #e.weapons do
            local function swing()
```

  with

```lua
        e.lastSwing, e.landAt = { 0, 0 }, { 0, 0 }
        e.swingAt, e.swingGen = { 0, 0 }, { 0, 0 } -- per hand: the pending swing's due time, its schedule's generation
        for h = 1, #e.weapons do
            local swing
            -- (re)schedules this hand's swing at t; an earlier schedule goes stale (parry haste moves it)
            local function due(t)
                local g = e.swingGen[h] + 1
                e.swingGen[h], e.swingAt[h] = g, t
                W.at(t, function()
                    if e.swingGen[h] == g then
                        swing()
                    end
                end)
            end
            if h == 1 then -- parry haste (decision 63): our parry pulls the main hand's pending swing
                e.hasten = function()
                    local x = M.parryPull(e.swingAt[1] - W.t, e.weapons[1][3] / (p.haste or 1))
                    if x > 0 and not e.stopped then
                        due(e.swingAt[1] - x)
                    end
                end
            end
            function swing() -- the local above
```

  then, in the same function, replace both `W.at(W.t + w[3] / (p.haste or 1), swing)` (the out-of-reach one and the
  last line of `swing`) with `due(W.t + w[3] / (p.haste or 1))`, and
  `W.at(W.t + (p.phase and p.phase[h] or W.rng.next() * e.weapons[h][3]), swing)` with
  `due(W.t + (p.phase and p.phase[h] or W.rng.next() * e.weapons[h][3]))`.

  In `M.mob`, replace

```lua
    return function(W, e)
        local function swing()
```

  with

```lua
    return function(W, e)
        local swing
        local gen, at = 0, 0
        local function due(t) -- (re)schedules the swing at t; an earlier schedule goes stale (parry haste moves it)
            gen, at = gen + 1, t
            local g = gen
            W.at(t, function()
                if gen == g then
                    swing()
                end
            end)
        end
        -- parry haste (decision 63): this mob's parry pulls its pending swing while it attacks
        e.hasten = function()
            local x = M.parryPull(at - W.t, e.weapons[1][3])
            if x > 0 and e.target and not e.stopped then
                due(at - x)
            end
        end
        function swing() -- the local above
```

  then replace both `W.at(W.t + e.weapons[1][3], swing)` with `due(W.t + e.weapons[1][3])` and
  `W.at(W.t + (p.phase or W.rng.next() * e.weapons[1][3]), swing)` with
  `due(W.t + (p.phase or W.rng.next() * e.weapons[1][3]))`.

- [ ] **Step 4: The world.** In `tests/Game/harness/world.lua`'s `M.new`, after the `W.hitAtSwing = true` line add:

```lua
    W.parryHaste = true -- a parried attack pulls the parrier's next main-hand swing (parry-haste spec decision 63)
```

  and in `W.emit`, after

```lua
        elseif ev.act == "HEAL" and ev.dst then
            ev.dst.health = math.min(ev.dst.healthMax, ev.dst.health + (ev.amount or 0))
        end
```

  add:

```lua
        -- parry haste: a parried attack, white or special, pulls the parrier's pending main-hand swing at the server's
        -- moment (its outcome row comes later); `land` is a row, not an attack
        local struck = ev.kind == "swing" or ev.kind == "strike" or ev.kind == "spell"
        if W.parryHaste and struck and ev.act == "PARRY" and ev.dst and ev.dst.hasten then
            ev.dst.hasten()
        end
```

  In `tests/Game/harness/scenarios.lua:102-103` replace

```lua
-- shortcut: only the other sources on our target are simulated (the rest fire rows on tokens nothing reads), with no
-- heals on party members and no parry haste on our swing timer; add them when a customer reads them.
```

  with

```lua
-- shortcut: only the other sources on our target are simulated (the rest fire rows on tokens nothing reads), with no
-- heals on party members; add them when a customer reads them.
```

- [ ] **Step 5: The replay.** In `tests/Game/harness/replay.lua`, replace the header's
  `-- last 20% of the duration) and never dead, our distance to it (the request's, then the log's Movement stacks). Not`
  `-- replayed: the target's swings.` with
  `-- last 20% of the duration) and never dead, our distance to it (the request's, then the log's Movement stacks), and`
  `-- the target's Parry of its swings on us (parry-haste spec §4; its other outcomes on us are not replayed: gap AH).`

  In `theirs(rest)`, before its final `end`, add:

```lua
    if rest:match("^%[[^%]]+ %(#1%)%] {[^}]*} Parry") then -- its swing on us, parried (parry-haste spec §4)
        return { kind = "taken", act = "PARRY" }
    end
```

  In the world's event loop, before `elseif e.kind == "hit" then` (line 688), add:

```lua
            elseif e.kind == "taken" then -- the target's swing on us (UNIT_COMBAT player); the log's swings carry the haste
                W.emit({ kind = "swing", src = mob, dst = us, hand = 1, act = e.act, flag = "", amount = 0, school = 1 })
```

  (`kind = "taken"`, not `"hit"`: the mob's health sum and the swing period read only our `hit` events, `:483`,
  `:495`.)

- [ ] **Step 6: Run the harness unit tests**

Run: `.lua/bin/busted tests/Game/harness/world_spec.lua tests/Game/harness/replay_spec.lua tests/Game/harness/observer_spec.lua tests/Game/harness/drive_spec.lua tests/boundary_spec.lua`
Expected: PASS, 0 failures.

- [ ] **Step 7: The gates, with the A/B (decision 64).** Run each gate with the world on (as committed), then with
  `W.parryHaste = false` (a local edit of `world.lua`, never committed: belief new, world old), and compare both with
  the baseline of Task 1 Step 1:

Run:
```bash
.lua/bin/busted --tags=wowsims tests/Forever/wowsims_warrior_spec.lua tests/Forever/wowsims_paladin_spec.lua 2>&1 | grep "wowsims:" > /tmp/ph/replay-on.txt; diff /tmp/ph/replay-base.txt /tmp/ph/replay-on.txt
```
Expected: exit of busted 0 (every replay floor holds). Only the two Protection lines may differ. Warrior Protection
at most 0.979 + 2/94 and Paladin Protection at most its baseline + 1/46 from parry haste; a rise beyond that is the
Parry rows now reaching the content (an avoid on us opens the reactive windows and its rage, `onus` rows): attribute
it by re-running with `L.PARRY_PULL = 0` set locally in `Melee.lua` (rows on, pull off) and name both numbers in the
commit message. A drop stops the task.

Run: `.lua/bin/busted --tags=slow tests/Game/harness/solo_spec.lua tests/Game/harness/group_spec.lua tests/Game/harness/onus_spec.lua tests/Game/harness/captures_spec.lua tests/Game/harness/flicker_spec.lua`
Expected: solo PASS unchanged (a failure stops the task for the owner); captures PASS; onus precision >= 0.90 (expected
unchanged or up: the hastened hit stays on its clock); flicker floors hold.

Run: `.lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua tests/Game/harness/detect_sweep_spec.lua`
Expected: PASS, or a cell off its floor. If a cell moved: `DETECT_WRITE=1 .lua/bin/busted --tags=slow tests/Game/harness/detect_spec.lua tests/Game/harness/detect_more_spec.lua`, then the same three specs again (PASS), and add above the floors file's first floor line (through `detect.lua`'s `M.record` header list, as the attribution-recovery plan's Task 1 Step 7 did):

```lua
        "-- 2026-10-23 (parry-haste spec decision 64): regenerated with parry haste in the world, the belief and the"
            .. " attacker clocks (the owner's ruling: wowsims's rule is Forever's).",
```

  A solo recall or `staged` cell down stops the task.

Run: `make test-loop > /tmp/ph/loop-on.txt 2>&1; diff <(grep -E "agree|flicker|L24" /tmp/ph/loop-base.txt) <(grep -E "agree|flicker|L24" /tmp/ph/loop-on.txt)`
Expected: exit 0 (loop floors hold). Then the A/B: set `W.parryHaste = false` locally, run the loop and the detect specs
again into `/tmp/ph/*-off.txt`, restore `world.lua` (`git diff --stat` shows only the intended files). Expected per
spec §5: with the world on, the loop and detect lines near the baseline; with it off (belief alone), swing-timing
lines (Fury L24 and Arms agreement, rage error at disagreements, onus with 2+ attackers) at or below them. A loop
floor that fails with the world on is re-based only with the owner's approval, its line naming this plan.

Run: `make check && make gate`
Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add tests/Game/harness/behaviours.lua tests/Game/harness/world.lua tests/Game/harness/scenarios.lua \
  tests/Game/harness/replay.lua tests/Game/harness/world_spec.lua tests/Game/harness/replay_spec.lua \
  tests/Game/harness/detect.lua tests/Game/harness/detect_floors.lua \
  tests/Forever/wowsims_warrior_spec.lua tests/Forever/wowsims_paladin_spec.lua
git commit -m "test(harness): parry haste in the world both ways; the replay feeds the tank logs' parries

Parry-haste decisions 63-64 under the owner's ruling of 2026-10-23. The world pulls the parrier's
main-hand swing (behaviours.parryPull, pinned equal to L.ParryPull); the replay emits the target's
Parry lines on us (gap AH narrowed).
Replay: <Warrior Protection before -> after>, <Paladin Protection before -> after> (rows on, pull off: <..>).
Loop and detection, baseline / world off / world on: <every moved line and cell>.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

(The angle-bracket lines are the run's own numbers; `git add` of an unchanged file is harmless.)

---

### Task 5: Docs

**Files:**
- Modify: `docs/superpowers/specs/2026-10-23-parry-haste-design.md` (Status, line 3; §2's c = 4 bullet; §6 PHS1 and
  open 3)
- Modify: `docs/research/2026-10-23-parry-haste.md:133` (the Paladin count)
- Modify: `docs/dev/gaps.md:17` (row AH)
- Modify: `docs/dev/ingame-ledger.md:28` (row PHS1)
- Modify: `CHANGELOG.md` (Unreleased, New)

**Interfaces:** none (docs only).

- [ ] **Step 1: The spec.** Replace line 3 with

```
Status: **BUILT** (plan `docs/superpowers/plans/2026-10-23-parry-haste.md`). The owner's ruling of 2026-10-23 ("let's
assume that the increase in swing speed for the next swing is a consistent rule for us and enemies") makes wowsims's
rule Forever's; PHS1 is a launch-day (2026-11-04) confirmation, not a prerequisite. Amended by the plan: the pull is
keyed to the swing it was taken from (`VS.SwingPull` returns `pull, from`; Hekili applies it only while `mh_actual` is
that swing) instead of cleared at `Obs.Swing` c = 4; the world hastens by default (no knob in committed tests); the
replay feeds only the Parry lines (open 3). Parent: `2026-10-23-attribution-recovery-design.md` §8 (which links here).
```

  In §2, replace the bullet beginning "- `Obs.Swing` c = 4 on hand 1 (`:50-72`) resets `pull[1] = 0`" with
  "- The pull is kept with the swing it was taken from (`from` = `VS.LastSwing(1)` at the parry) and restarts at a
  parry after a newer swing; `Obs.Swing` c = 4 re-anchors the hand without touching it (the plan's amendment 1).
  `Obs.CombatEnd` clears it." In §6, PHS1's bullet gains "Launch-day confirmation (2026-11-04) under the owner's
  ruling." and open 3 gains "Resolved by the plan: the Parry lines only; the rest stays gap AH."

- [ ] **Step 2: The research table.** In `docs/research/2026-10-23-parry-haste.md:133` change
  `| paladin_protection | 18 | 7 |` to `| paladin_protection | 11 | 7 |` and add after the table: "(Corrected
  2026-10-23 by the plan: the log has 11 Parry lines; the 7 hastened ones are unchanged.)"

- [ ] **Step 3: The gap register.** In `docs/dev/gaps.md`, row AH's mechanism becomes
  "The replay does not replay the target's swings beyond its Parry of them (since parry haste, 2026-10-23, those come
  as `UNIT_COMBAT player PARRY`): its blocks, dodges and wounds on us (Revenge's window from a block or dodge, blocks,
  rage from damage taken) are not checked against wowsims" and its status "open (Parry lines done)".

- [ ] **Step 4: The ledger.** Replace row PHS1's "Why it matters" and "Status" cells
  (`| the parry-haste design (...) follows wowsims's rule; one in-game sample so far (...) | open |`) with
  `| launch-day confirmation (2026-11-04) of the rule the addon models since the parry-haste plan (owner's ruling 2026-10-23: wowsims's rule is Forever's): if the game differs (another clamp, the off hand pulled, no pull on a parried special, our pull after a mid-cast parry), change \`L.PARRY_PULL\` / \`L.PARRY_FLOOR\` (\`Game/Events/Melee.lua\`) and \`behaviours.parryPull\` together; one in-game sample so far (771 -> 2110 ms on a 2.2 s weapon, 0.39 d early: \`docs/research/2026-10-16-swing-outcome-pairing.md:28\`) | open: launch day 2026-11-04 |`
  (the backslashes are only this plan's escaping; the row uses plain backticks).

- [ ] **Step 5: The changelog.** Under `## Unreleased` / `### New` add:

```
- Parry haste: when you parry, your next main-hand swing comes sooner, and the addon now expects it then: the swing
  timer, the rage that swing brings and anything timed to it (a Slam between swings, a queued strike) follow. A mob
  that parries you swings sooner too, and its hit on you is still matched to it when several mobs are on you.
```

Run: `.lua/bin/busted tests/Forever/changelog_spec.lua && make check`
Expected: PASS; exit 0.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-23-parry-haste-design.md docs/research/2026-10-23-parry-haste.md \
  docs/dev/gaps.md docs/dev/ingame-ledger.md CHANGELOG.md
git commit -m "docs: parry haste built; PHS1 a launch-day confirmation; gap AH narrowed

The spec's status and the plan's amendments (the keyed pull, the default world, the Parry lines only);
the research's Paladin count corrected (11 Parry lines, 7 hastened).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

## Open questions the code did not settle

1. **A queued strike's swing leaves `mh_actual` behind.** Hekili's `mh_actual` moves only on `SWING_*` rows
   (`Engine/Sim/Events.lua:1673-1679`); a swing that is an on-next-swing strike (`T.Swallows`, `Rows.lua:106`) emits a
   spell row, so `mh_actual` keeps the white swing before it while the family's `last[1]` is the strike's swing. A
   pull taken after a strike swing then never matches `mh_actual` and is not applied (today's behaviour, the safe
   side). Whether `nextMH` itself is late after every strike swing is a pre-existing question for the owner, outside
   this plan.
2. **Mid-cast parries** (spec open 4): the belief pulls whenever the main hand has an anchor in combat; whether the
   game pulls a swing paused by a cast is PHS1 (b)'s to show.
