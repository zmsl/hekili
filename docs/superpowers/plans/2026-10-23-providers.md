# Providers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The engine asks two contracts (Outcomes, AuraPresence) instead of guessing; the build config injects which
provider answers them; the damage meter and the Cooldown Manager become two experimental, switchable providers in their
own files, measured against today's behaviour (the Default providers) on every gate.

**Architecture:** Five provider files under `Game/State/Sources/Outcomes/` and `Game/State/Sources/Presence/`, each
self-registering in `I.OUTCOMES` / `I.PRESENCE` and sharing no code; the Presence router holds only a tracked map and
delegates to the viewer leaf. `I.Build` resolves `def.providers` and activates them; consumers in `Events/Rows.lua`,
`Events/Tickets.lua`, `Events/Melee.lua`, `Events/Attackers.lua` and `Sources/Auras.lua` call `I.outcomes` /
`I.presence` only. The game layer (`Game/State/Adapter.lua`) maps two profile toggles to `def.providers`. The harness
gains the measured meter and viewer shapes and an A/B arm switch.

**Tech Stack:** Lua 5.1 (WoW), busted, luacheck, StyLua, the combat harness (`tests/Game/harness/`).

**Spec:** `docs/superpowers/specs/2026-10-23-providers-design.md` (binding; decisions 65-91), on top of the recovery spec
(`docs/superpowers/specs/2026-10-23-attribution-recovery-design.md`, decisions 46-56). Cited as "spec §N". Line numbers
are as of `forever-attribution-2` cbdfdc41.

**Prerequisite:** recovery plan Task 3 merged (`T.ASSUMED`, `T.onAssume`, `T.tol`, `Obs.Swing` c = 5-7). Task 1 Step 4
extracts its inline assumption into `T.Assume`. If Task 3 is not merged when this plan starts, run Tasks 2 and 5-6 first
(they do not touch tickets) and Task 1 after it.

## Global Constraints

- Core/pack boundary: nothing under `src/Hekili/Game`, `tests/Game` or the provider files names a class, spell, aura or
  spell ID (`tests/boundary_spec.lua`). Spell IDs live only in `tools/data/cooldownviewer/*.lua` fixtures (dev-only, not
  loaded by any TOC) and in docs.
- Secret safety: the only new client reads are in the provider files, through the injected `api`, each value through
  `api.issecretvalue` (or `S.Plain`) before any other use; never `a and b or c` on a possibly-secret value; no viewer or
  meter value is passed back to an API. New API names join `tools/api_inventory.txt` (`make api-check`).
- No allocation in recurring paths: the meter ring, the row hold ring, `T.told`, the router's `tracked`, the leaf's
  per-pair state are preallocated (load or build). Getters that allocate (`C_DamageMeter.Get*`,
  `C_CooldownViewer.Get*`, `GetChildren`) run only out of combat (build, activation, combat end). The hook function is
  one shared function. `tests/Game/State/alloc_spec.lua` and `tests/Game/harness/alloc_spec.lua` extend to the meter
  handler, the hold ring and the hook.
- The first gate (spec decision 68): with the Default providers (and the router with no leaf) every detection floor,
  solo/group gate, flicker floor, `make gate` loop line, `make bench-ta`, the memory ceiling and every Snapshot line
  that existed before are identical. Tasks 1, 2, 4, 6 and 7 prove it by diffing a gate log before and after (Step "first
  gate" below).
- Provider arms are measured, never gated (spec decision 86): no floor file is rewritten for a provider arm.
- Display only: nothing here presses, queues or casts anything.
- `make check` green on every commit; `make gate` before the merge.
- Every commit ends with the trailer:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw`.

**First gate (used by several tasks):**

```bash
git stash -u && make gate 2>&1 | grep -E "recall|agreement|flicker|over|rows |tickets |cpu|KB" > /tmp/gate-before.txt; git stash pop
make gate 2>&1 | grep -E "recall|agreement|flicker|over|rows |tickets |cpu|KB" > /tmp/gate-after.txt
diff /tmp/gate-before.txt /tmp/gate-after.txt && echo IDENTICAL
```

Expected: `IDENTICAL` (CPU-time lines excepted: compare them by eye, within the run-to-run noise of `make bench`).

## Module Layout

| File | Change | Tested by |
|---|---|---|
| `src/Hekili/Game/State/Belief.lua` | `I.OUTCOMES`, `I.PRESENCE`, the answer constants, provider resolution in `I.Build`, `VS.SetProviders`, `VS.PresenceScope` | `tests/Game/State/providers_spec.lua` (new) |
| `src/Hekili/Game/State/Sources/Sources.lua` | `S.Dormant` | `providers_spec.lua` |
| `src/Hekili/Game/Events/EventFacade.lua` | `sync` skips dormant events; `E.Sync` | `tests/Game/API/facade_spec.lua` |
| `src/Hekili/Game/State/Sources/Outcomes/Default.lua` | new | `providers_spec.lua` |
| `src/Hekili/Game/State/Sources/Outcomes/Meter.lua` | new | `tests/Game/State/meter_spec.lua` (new) |
| `src/Hekili/Game/State/Sources/Presence/Default.lua` | new | `providers_spec.lua` |
| `src/Hekili/Game/State/Sources/Presence/CooldownViewer.lua` | new (the leaf) | `tests/Game/State/viewer_spec.lua` (new) |
| `src/Hekili/Game/State/Sources/Presence/Router.lua` | new | `tests/Game/State/router_spec.lua` (new) |
| `src/Hekili/Game/Events/Tickets.lua` | `T.told`, `T.Decide`, `T.Assume` (extracted), `T.SwingPending` honours AVOID | `tests/Game/Events/tickets_spec.lua` |
| `src/Hekili/Game/Events/Melee.lua` | `M.score`, `M.Overdue` skip a told-AVOID ticket for a wound | `tickets_spec.lua` |
| `src/Hekili/Game/Events/Rows.lua` | the row hold ring, `RowOwner` routing, `T.Decide` and `T.Expire(now - ROW_DELAY)` in the tick, fight counters, the audit line | `tickets_spec.lua`, `meter_spec.lua` |
| `src/Hekili/Game/Events/Attackers.lua` | `EnemyHitAt` | `tests/Game/Events/attackers_spec.lua` |
| `src/Hekili/Game/State/Sources/Auras.lua` | presence consumption (poll 11 and `onEdge`), `targetPlain`, per-aura audit lines | `tests/Game/State/auras_spec.lua`, `router_spec.lua` |
| `src/Hekili/Game/State/Families/Resources.lua` | pin error counters at the flip | `tests/Game/State/resources_spec.lua` |
| `src/Hekili/Game/State/Adapter.lua` | `def.providers` from the profile, `Hekili:ProvidersChanged` | `tests/Forever/providers_option_spec.lua` (new) |
| `src/Hekili/Options/Options.lua` | two toggles and their defaults | `providers_option_spec.lua` |
| `src/Hekili/Hekili.toc` | the five provider files | `make check` (the loader reads the TOC) |
| `tests/Game/harness/{ab,observer,world,drive,detect}.lua`, `tests/Game/State/helpers/fake_api.lua`, `tests/Forever/helpers/pack_gate.lua`, `solo_spec.lua`, `group_spec.lua`, `Makefile` | the A/B arm, the shapes, the fakes, `make gate-ab` | `tests/Game/harness/ab_spec.lua` (new), `observer_spec.lua` |
| `tools/check_cooldown_viewer.lua`, `tools/data/cooldownviewer/WARRIOR.lua`, `Makefile` | the coverage report, `make cdv-coverage` | run by hand (dev-only) |

## Review Focus

1. **Identical Default path.** Every consumer's new code must sit behind a branch the Default providers never take
   (`SWING_DELAY == 0`, `ROW_DELAY == 0`, `covered == 0`, `EnemyHitAt == nil`). The first gate diff is the evidence.
2. **No shared code between providers.** No provider file requires or reads another; the router reaches its leaf only as
   `I.PRESENCE.viewer` through the contract's fields.
3. **Never mid-fight.** `I.Build` and `VS.SetProviders` swap only out of combat; the router's `tracked` changes only out
   of combat; a pending swap applies at `PLAYER_REGEN_ENABLED`.
4. **Secrets.** Each meter and viewer value through `issecretvalue` first; presence is `issecretvalue(id) or id ~= nil`;
   the audit drops a read with any secret field.
5. **The row hold.** Rows are routed in arrival order with their own time; `T.Expire` cuts at `now - ROW_DELAY`; combat
   end flushes the hold before `T.EndCombat`.
6. **`lo` untouched by a provider answer.** HIT goes through `T.Assume` (c = 5: `est`, `hi` only).

## Task order

1. The contracts, the Default providers, injection and the consumer call sites (first gate: identical)
2. The harness: A/B arm, observer shapes, fakes, `make gate-ab` (first gate: identical)
3. The Meter provider, its unit tests and the Snapshot audit line
4. The damage-meter experimental option and the in-game wiring (first gate: identical)
5. The CooldownViewer leaf, its frame fakes, the coverage report
6. The Presence router and the per-aura audit (first gate: identical)
7. The Cooldown Manager experimental option and the wiring (first gate: identical)
8. The A/B measurement, the docs and the changelog

---

### Task 1: The contracts, the Default providers, injection and the call sites

**Files:**
- Create: `src/Hekili/Game/State/Sources/Outcomes/Default.lua`, `src/Hekili/Game/State/Sources/Presence/Default.lua`,
  `tests/Game/State/providers_spec.lua`
- Modify: `src/Hekili/Game/State/Belief.lua`, `src/Hekili/Game/State/Sources/Sources.lua`,
  `src/Hekili/Game/Events/EventFacade.lua`, `src/Hekili/Game/Events/Tickets.lua`, `src/Hekili/Game/Events/Melee.lua`,
  `src/Hekili/Game/Events/Rows.lua`, `src/Hekili/Game/Events/Attackers.lua`, `src/Hekili/Game/State/Sources/Auras.lua`,
  `src/Hekili/Hekili.toc`, `tests/Game/Events/tickets_spec.lua`

- [ ] **Step 1: Failing tests.** `tests/Game/State/providers_spec.lua`:

```lua
-- tests/Game/State/providers_spec.lua (providers spec §1-§3): the contracts, the Default providers, injection.
local load = require("Game.State.helpers.load")
local fake = require("Game.State.helpers.fake_api")
local fs = require("Game.State.helpers.fake_spec")

describe("providers", function()
    local api, ctl, ns, VS, I, saved

    before_each(function()
        api, ctl = fake.new()
        saved = {}
        for k, v in pairs({ CreateFrame = api.CreateFrame, issecretvalue = api.issecretvalue, GetTime = api.GetTime }) do
            saved[k] = rawget(_G, k) or false
            _G[k] = v
        end
        ns = load.module()
        VS, I = ns.VirtualState, ns.VirtualStateInternal
    end)
    after_each(function()
        for k, v in pairs(saved) do
            _G[k] = v or nil
        end
    end)

    it("resolves a missing or unknown name to default", function()
        I.Build(fs.def(fs.new(9)), 1)
        assert.are.equal("default", I.outcomes.name)
        assert.are.equal("default", I.presence.name)
        local d = fs.def(fs.new(9))
        d.providers = { outcomes = "nonesuch", presence = "nonesuch" }
        I.Build(d, 1)
        assert.are.same({ "default", "default" }, { I.outcomes.name, I.presence.name })
    end)

    it("the Default providers answer UNKNOWN and cover nothing", function()
        I.Build(fs.def(fs.new(9)), 1)
        local P, Q = I.outcomes, I.presence
        assert.are.same({ 0, 0 }, { P.SWING_DELAY, P.ROW_DELAY })
        assert.are.equal(I.UNKNOWN, P.SwingOutcome(1, 2))
        assert.are.equal(I.UNKNOWN, P.RowOwner(1, 1, 1, 10, "WOUND", 2))
        assert.is_nil(P.EnemyHitAt(1))
        assert.is_nil(P.Audit())
        assert.are.same({ 0, nil }, { Q.covered, Q.scope })
        assert.are.equal(I.UNKNOWN, Q.Presence(1, 1))
    end)

    it("swaps out of combat at once, in combat at combat end", function()
        I.OUTCOMES.probe = setmetatable({ name = "probe" }, { __index = I.OUTCOMES.default })
        I.Build(fs.def(fs.new(9)), 1)
        VS.Start(api)
        I.inCombat = true
        VS.SetProviders("probe", "default")
        assert.are.equal("default", I.outcomes.name)
        I.inCombat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("probe", I.outcomes.name)
    end)

    it("a dormant event is not registered with the client until woken", function()
        I.Build(fs.def(fs.new(9)), 1)
        local S = I.Sources
        S.On("TEST_DORMANT_EVENT", nil, function() end)
        S.Dormant("TEST_DORMANT_EVENT", true)
        VS.Start(api)
        assert.is_falsy(api.frame:IsEventRegistered("TEST_DORMANT_EVENT"))
        S.Dormant("TEST_DORMANT_EVENT", false)
        I.Events.Sync("TEST_DORMANT_EVENT")
        assert.is_truthy(api.frame:IsEventRegistered("TEST_DORMANT_EVENT"))
    end)
end)
```

  Add to `tests/Game/Events/tickets_spec.lua` (a stub provider proves the call sites; the Meter's own rules are Task 3's):

```lua
    describe("with a stub Outcomes provider", function()
        local answer
        before_each(function()
            answer = I.UNKNOWN
            I.OUTCOMES.stub = setmetatable({
                name = "stub",
                SWING_DELAY = 0.015,
                SwingOutcome = function()
                    return answer
                end,
            }, { __index = I.OUTCOMES.default })
            local d = fs.def(fs.new(9, false, false, true))
            d.providers = { outcomes = "stub" }
            I.Build(d, 1)
        end)

        it("AVOID: the swing takes no wound and pends no rage", function()
            answer = I.AVOID
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(10.02)
            local i = T.lastSwing[1]
            assert.are.equal(2, T.told[i])
            assert.are.equal(0, T.SwingPending(1, 10.02))
            ctl.now = 10.47
            ctl.Fire("UNIT_COMBAT", "target", "WOUND", "", 30, 1)
            assert.are.equal(1, T.foreign)
        end)

        it("HIT: the swing is assumed at once (the recovery shadow)", function()
            answer = I.HIT
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(10.02)
            local i = T.lastSwing[1]
            assert.are.same({ 1, T.ASSUMED }, { T.told[i], T.state[i] })
        end)

        it("UNKNOWN: today's path", function()
            ctl.now = 10
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(10.02)
            local i = T.lastSwing[1]
            assert.are.same({ 0, T.OPEN }, { T.told[i], T.state[i] })
        end)
    end)
```

- [ ] **Step 2: Run, expect failure.**

```bash
.lua/bin/busted tests/Game/State/providers_spec.lua tests/Game/Events/tickets_spec.lua
```

Expected: FAIL (`I.outcomes` is nil; `T.told` is nil).

- [ ] **Step 3: Belief, Sources, facade.** In `Belief.lua`, above `I.Build` (line 99):

```lua
-- The provider contracts (providers spec §1): answers, and the registries each provider file fills at load.
I.UNKNOWN, I.HIT, I.AVOID, I.OURS, I.FOREIGN, I.UP, I.DOWN = 0, 1, 2, 1, 2, 1, 2
I.OUTCOMES, I.PRESENCE = {}, {}
I.outcomes, I.presence = nil, nil
local wantO, wantP, wantV -- a swing asked for in combat (VS.SetProviders): applied at combat end

-- Activates the named providers (spec §3.1): unknown names are "default"; only a changed choice is swapped.
local function provide(oName, pName, viewer, now, def)
    local O = I.OUTCOMES[oName or "default"] or I.OUTCOMES.default
    local P = I.PRESENCE[pName or "default"] or I.PRESENCE.default
    if O ~= I.outcomes then
        if I.outcomes then
            I.outcomes.Deactivate(now)
        end
        I.outcomes = O
        O.Activate(I.api, now)
    end
    if P ~= I.presence or viewer ~= I.presenceViewer or def then
        if I.presence then
            I.presence.Deactivate(now)
        end
        I.presence, I.presenceViewer = P, viewer
        P.Activate(I.api, now, def or I.def, { viewer = viewer == true })
        if I.OnPresence then
            I.OnPresence(P) -- Sources/Auras.lua sets P.onEdge
        end
    end
end
I.Provide = provide
```

  In `I.Build`, after `I.clock = now` and before the build hooks: `I.def = def` and, after the hooks (the families'
  arrays exist), `local pv = def.providers or {}; provide(pv.outcomes, pv.presence, pv.viewer, now, def)`. Below
  `I.Build`:

```lua
--- (spec §3.1) Swaps the providers without a rebuild: out of combat at once, in combat at PLAYER_REGEN_ENABLED.
function VS.SetProviders(outcomes, presence, viewer)
    if I.inCombat then
        wantO, wantP, wantV = outcomes, presence, viewer
        return
    end
    provide(outcomes, presence, viewer, I.clock)
end

--- Applies a swap asked for in combat. Rows calls it at PLAYER_REGEN_ENABLED, after T.EndCombat.
function I.ApplyProviders(now)
    if wantO or wantP then
        local o, p, v = wantO, wantP, wantV
        wantO, wantP, wantV = nil, nil, nil
        provide(o, p, v, now)
    end
end

--- (spec §3.4) The active presence provider's scope ("self", "any") for aura `key` on `unit`, nil when uncovered.
function VS.PresenceScope(unit, key)
    local P, U = I.presence, I.auras
    local u, j = U and U.index[unit], U and U.byKey and U.byKey[key]
    if P and u and j and P.Presence(j, u) ~= I.UNKNOWN then
        return P.scope
    end
    return nil
end
```

  (`I.auras.byKey`: add it in `Families/Auras.lua`'s build beside `bySpell` if absent: `U.byKey[def.auras[j].key] = j`.)
  In `VS.Start` (`Sources.lua:174`), after `I.Events.Attach(api)`: `if I.outcomes then I.outcomes.Activate(api, t)
  I.presence.Activate(api, t, I.def, { viewer = I.presenceViewer == true }) end` (a build before Start activated
  without an api).

  `Sources.lua`, after `S.On`:

```lua
-- Events a provider owns while it is inactive: the facade does not register them with the client (spec §3.2).
S.DORMANT = {}
--- Marks `event` dormant (on) or awake; the caller then asks the facade to sync it. Load time and activation only.
function S.Dormant(event, on)
    S.DORMANT[event] = on or nil
end
```

  `EventFacade.lua:62`: `if I.api and S.HANDLERS[e] then` becomes `if I.api and S.HANDLERS[e] and not S.DORMANT[e] then`;
  after `sync` add `E.Sync = sync`.

- [ ] **Step 4: The Default providers.** `Sources/Outcomes/Default.lua`:

```lua
-- Game/State/Sources/Outcomes/Default.lua
-- The Default Outcomes provider (providers spec §2.1): no evidence beyond the rows; every consumer runs today's path
-- (the swing's LR at its row, the recovery spec's assumption past the lag tolerance).

local _, ns = ...
local I = ns.VirtualStateInternal

local P = { name = "default", SWING_DELAY = 0, ROW_DELAY = 0 }
function P.Activate() end
function P.Deactivate() end
function P.SwingOutcome()
    return I.UNKNOWN
end
function P.RowOwner()
    return I.UNKNOWN
end
function P.EnemyHitAt()
    return nil
end
function P.Audit()
    return nil
end
I.OUTCOMES.default = P
```

  `Sources/Presence/Default.lua`:

```lua
-- Game/State/Sources/Presence/Default.lua
-- The Default AuraPresence provider (providers spec §2.3): covers nothing; the belief's modelled timers stand.

local _, ns = ...
local I = ns.VirtualStateInternal

local Q = { name = "default", scope = nil, covered = 0, onEdge = nil }
function Q.Activate() end
function Q.Deactivate() end
function Q.Presence()
    return I.UNKNOWN
end
I.PRESENCE.default = Q
```

  `Hekili.toc`: after `Game\State\Sources\Units.lua` (line 34) add `Game\State\Sources\Outcomes\Default.lua` and
  `Game\State\Sources\Presence\Default.lua`.

- [ ] **Step 5: Tickets.** Beside `T.first` (line 27) declare `T.told = {}` and fill it with 0 in the load loop
  (line 30-33) and in `fill` (`T.told[i] = 0`). Extract recovery Task 3's inline transition in `T.Expire` into:

```lua
--- (recovery decision 51) Ticket i becomes the ASSUMED shadow at `now`; Rows' T.onAssume stages the assumption.
--- Called by T.Expire past the lag tolerance and by T.Decide on a provider's HIT (providers decision 70).
function T.Assume(i, now)
    state[i], T.assumed[i] = T.ASSUMED, true
    if T.onAssume then
        T.onAssume(i, now)
    end
end
```

  and call it there (no behaviour change). In that `T.Expire` condition add `and T.told[i] ~= 2` (an AVOID swing is
  never assumed). Add:

```lua
--- (providers decision 70) Asks the Outcomes provider once about each OPEN swing ticket SWING_DELAY after its swing.
--- Allocates nothing; with the Default provider (SWING_DELAY 0) returns at once.
function T.Decide(now)
    local P = I.outcomes
    local d = P.SWING_DELAY
    if d <= 0 then
        return
    end
    for i = 1, CAP do
        if state[i] == OPEN and kind[i] == MELEE and T.told[i] == 0 and now >= at[i] + d then
            local a = P.SwingOutcome(i, now)
            if a == I.HIT then
                T.told[i] = 1
                if guid[i] ~= "" and not T.retry[i] then
                    T.Assume(i, now)
                end
            elseif a == I.AVOID then
                T.told[i] = 2
            else
                T.told[i] = 3 -- asked, unanswered: never asked again (the audit's `unknown`)
            end
        end
    end
end
```

  In `T.SwingPending` (line 320-331), before `return at0`: `if i > 0 and T.told[i] == 2 then return 0 end`.

- [ ] **Step 6: Melee.** In `M.score`'s candidate test (`Melee.lua:155-160`) add `and not (not avoid and T.told[i] == 2)`;
  the same clause in `M.Overdue` (recovery Task 1).

- [ ] **Step 7: Rows.** The hold ring and routing, above `U.OnRow` (line 222):

```lua
-- (providers decision 73) Rows held ROW_DELAY so the Outcomes provider can answer RowOwner; routed in arrival order
-- with their own time. With ROW_DELAY 0 (Default) a row is routed at once and the ring is never touched.
local HOLD = 32
local hT, hG, hU, hA, hF, hM, hS = {}, {}, {}, {}, {}, {}, {}
for k = 1, HOLD do
    hT[k], hG[k], hU[k], hA[k], hF[k], hM[k], hS[k] = 0, "", 0, "", "", 0, 0
end
local hHead, hN = 0, 0
L.fight = { ownUnclaimed = 0, foreignByMeter = 0, paid = 0, held = 0, overflow = 0 }
```

  Rename the body of the `U.OnRow(function(t, g, uid, act, flag, amount, school) ... end)` listener to
  `local function route(t, g, uid, act, flag, amount, school, owner)` (`owner`: the provider's answer, `I.UNKNOWN` when
  not held). At its top, after the secret-slot check (line 227-232), add:

```lua
    if owner == I.FOREIGN then
        L.fight.foreignByMeter = L.fight.foreignByMeter + 1
        foreign(uid, t, act, flag, amount, school == 1, act ~= "WOUND", false, school)
        return
    end
```

  and in the `elseif not credited then` branch (line 310-312) before `foreign(...)`:
  `if owner == I.OURS then L.fight.ownUnclaimed = L.fight.ownUnclaimed + 1 end`. Then:

```lua
local function release(now)
    local d = I.outcomes.ROW_DELAY
    while hN > 0 do
        local k = (hHead - hN) % HOLD + 1
        local t = hT[k]
        if now < t + d then
            return
        end
        hN = hN - 1
        local owner = I.outcomes.RowOwner(t, hU[k], hS[k], hM[k], hA[k], now)
        route(t, hG[k], hU[k], hA[k], hF[k], hM[k], hS[k], owner)
    end
end

U.OnRow(function(t, g, uid, act, flag, amount, school)
    if I.outcomes.ROW_DELAY <= 0 then
        return route(t, g, uid, act, flag, amount, school, I.UNKNOWN)
    end
    if hN >= HOLD then -- full: the oldest goes now (counted), never dropped
        L.fight.overflow = L.fight.overflow + 1
        release(math.huge)
    end
    hHead = hHead % HOLD + 1
    hN = hN + 1
    hT[hHead], hG[hHead], hU[hHead], hA[hHead], hF[hHead], hM[hHead], hS[hHead] =
        t, g, uid, act, flag, amount, school
    L.fight.held = L.fight.held + 1
end)
```

  (The secret-slot case stores `amount`, `flag`, `school` as they came; `route` tests their types first, as today.)
  The tick (line 389-392) becomes:

```lua
L.OnTick(function(now)
    M.advance(now)
    release(now)
    T.Decide(now)
    T.Expire(now - I.outcomes.ROW_DELAY)
end)
```

  `PLAYER_REGEN_ENABLED` (line 395-399): `release(math.huge)` before `T.EndCombat(t)`, then `I.ApplyProviders(t)` after.
  `PLAYER_REGEN_DISABLED`: reset `L.fight`'s counters (a new handler).

- [ ] **Step 8: Attackers.** In the `UNIT_COMBAT` handler (line 196), after the early return:

```lua
    local te = nil -- the hit's resolved time from the Outcomes provider (its own clock, plain); else the row's
    if act == "WOUND" then
        te = I.outcomes.EnemyHitAt(t)
    end
    te = te or t
```

  then use `te` in place of `t` in `clockError(k, period, t)` (line 218) and `learn(k, t, ...)` (line 262). The emitted
  row keeps `t`.

- [ ] **Step 9: Auras.** Track `targetPlain` beside `playerPlain` (line 36; set in `walk` at line 132-134 for `u == 2`).
  Add after poll 11 (line 197):

```lua
-- (providers decision 80) Presence from the injected provider, with the overlay's rule: a plain walk wins; UP while
-- believed down stages up with no expiry, DOWN while believed up stages down. Per aura, the audit (decision 90).
I.presenceFacts, I.presenceDisagree = {}, {}
local function plainOf(u)
    if u == 1 then
        return playerPlain
    end
    return targetPlain
end
local function apply(j, u, up, t)
    local U = I.auras
    if u > U.n or plainOf(u) then
        return false
    end
    local k = (u - 1) * I.AURA_UNIT + j
    local believed = U.exp0[u][j] > t
    I.presenceFacts[k] = (I.presenceFacts[k] or 0) + 1 -- shortcut: a hash entry per (aura, unit) on its first fact; preallocate at build if alloc_spec flags it
    if believed ~= up then
        I.presenceDisagree[k] = (I.presenceDisagree[k] or 0) + 1
        Direct(Obs.Read, t, k, up and -1 or 0, ReadOf.Aura)
        return true
    end
    return false
end
I.OnPresence = function(P)
    P.onEdge = function(j, u, up, t)
        if apply(j, u, up, t) then
            S.Urgent("VS_PRESENCE")
        end
    end
end
S.Poll(13, function(api, t)
    local P = I.presence
    if not I.built or P.covered == 0 then
        return
    end
    local U = I.auras
    for u = 1, (U.n < 2 and U.n or 2) do
        for j = 1, U.nAura do
            local a = P.Presence(j, u)
            if a ~= I.UNKNOWN then
                apply(j, u, a == I.UP, t)
            end
        end
    end
end)
```

  (The closure in `I.OnPresence` is made once per activation, out of combat. Check poll order 13 is free:
  `grep -n "S.Poll(13" -r src/Hekili/Game`; take the next free order above 11 if not.) Pre-allocate
  `I.presenceFacts`/`I.presenceDisagree` in `I.OnBuild` for every `(u - 1) * AURA_UNIT + j` with 0 and drop the
  shortcut comment.

- [ ] **Step 10: Run the unit tests.**

```bash
.lua/bin/busted tests/Game/State/providers_spec.lua tests/Game/Events/tickets_spec.lua tests/Game/API/facade_spec.lua
```

Expected: PASS.

- [ ] **Step 11: `make check`, then the first gate.** Expected: green; `IDENTICAL`.

- [ ] **Step 12: Commit.**

```bash
git add -A src/Hekili tests/Game
git commit -m "feat(providers): Outcomes and AuraPresence contracts, Default providers, injection through def.providers

Consumers (Rows' tick and row hold, Tickets, Melee, Attackers, the Auras overlay) ask the injected
provider; the Default providers answer UNKNOWN and every gate is identical to the digit
(providers spec decisions 65-70, 73, 80).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 2: The harness: A/B arm, observer shapes, fakes, `make gate-ab`

**Files:**
- Create: `tests/Game/harness/ab.lua`, `tests/Game/harness/ab_spec.lua`
- Modify: `tests/Game/harness/observer.lua`, `world.lua`, `drive.lua`, `detect.lua`, `solo_spec.lua`, `group_spec.lua`,
  `tests/Forever/helpers/pack_gate.lua`, `tests/Game/State/helpers/fake_api.lua`, `tests/Game/harness/observer_spec.lua`,
  `Makefile`, `.gitignore`

- [ ] **Step 1: Failing tests.** `tests/Game/harness/ab_spec.lua`:

```lua
-- tests/Game/harness/ab_spec.lua (providers spec §4): the A/B arm and the measured shapes.
local ab = require("Game.harness.ab")
local observer = require("Game.harness.observer")
local scenarios = require("Game.harness.scenarios")

describe("the A/B harness", function()
    it("the default arm asserts, a provider arm records", function()
        assert.has_error(function()
            ab.check(false, "x", "line", "default")
        end)
        assert.has_no.errors(function()
            ab.check(false, "x", "line", "meter")
        end)
    end)

    local function count(s, ev)
        local n = 0
        for i = 1, s.n do
            n = n + (s.ev[i] == ev and 1 or 0)
        end
        return n
    end

    it("meter shapes only add events: the rest of the stream is today's", function()
        local o = { duration = 30 }
        local base = scenarios.stream(o, 7)
        o.meter = true
        local with = scenarios.stream(o, 7)
        assert.is_true(count(with, "DAMAGE_METER_COMBAT_SESSION_UPDATED") > 0)
        local j = 0
        for i = 1, with.n do
            if with.ev[i] ~= "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
                j = j + 1
                assert.are.same({ base.t[j], base.ev[j], base.a1[j] }, { with.t[i], with.ev[i], with.a1[i] })
            end
        end
        assert.are.equal(base.n, j)
    end)

    it("a hit swing of ours groups 0-11 ms after PLAYER_SWING; an avoid never", function()
        local s, W = scenarios.stream({ duration = 60, meter = true }, 11)
        for _, ev in ipairs(W.truth) do
            if ev.kind == "swing" and ev.ours then
                local got = false
                for i = 1, s.n do
                    if s.ev[i] == "DAMAGE_METER_COMBAT_SESSION_UPDATED" and s.a1[i] == 0 then
                        local d = s.t[i] - ev.t
                        got = got or (d >= 0 and d <= 0.011)
                    end
                end
                assert.are.equal(ev.act == "WOUND", got)
            end
        end
    end)
end)
```

  (Adjust the truth accessor names to `world.lua`'s if they differ: `W.truth` holds `{ t, kind, src, ... }` records,
  `world.lua:39-46`; a swing of ours is `src == W.ents[1]`.) In `observer_spec.lua` add: with `viewer = true` an `aura`
  truth event of ours makes one `@viewer` event 3-5 ms after it, a partner's none.

- [ ] **Step 2: Run, expect failure.** `.lua/bin/busted tests/Game/harness/ab_spec.lua` (module not found).

- [ ] **Step 3: `ab.lua`.**

```lua
-- tests/Game/harness/ab.lua (providers spec §4.1, decision 83): the arm (HEKILI_AB) and the floor assertions every gate
-- routes through: the default arm asserts; a provider arm records each cell in .ab/<arm>.tsv and never fails.
local M = {}

M.ARMS = {
    default = { outcomes = "default", presence = "router", viewer = false },
    meter = { outcomes = "meter", presence = "router", viewer = false },
    viewer = { outcomes = "default", presence = "router", viewer = true },
}

function M.arm()
    local a = os.getenv("HEKILI_AB")
    return (a and M.ARMS[a]) and a or "default"
end

--- def.providers for the current arm (a fresh table: the build keeps it).
function M.providers(arm)
    local p = M.ARMS[arm or M.arm()]
    return { outcomes = p.outcomes, presence = p.presence, viewer = p.viewer }
end

function M.check(ok, label, line, arm)
    arm = arm or M.arm()
    if arm == "default" then
        assert(ok, label .. ": " .. tostring(line))
        return
    end
    os.execute("mkdir -p .ab")
    local fh = assert(io.open(".ab/" .. arm .. ".tsv", "a"))
    fh:write(label, "\t", ok and "ok" or "MISS", "\t", tostring(line), "\n")
    fh:close()
end

return M
```

  Until Task 6 lands, `presence = "router"` resolves to "default" (unknown name): identical. `.gitignore`: add `.ab/`.

- [ ] **Step 4: Route the floors.** In `detect.check` (`detect.lua:296-312`) replace each `assert(cond, msg)` with
  `ab.check(cond, kind .. " " .. band, msg)`. In `pack_gate.flicker` and `pack_gate.gate`
  (`tests/Forever/helpers/pack_gate.lua:71-100`) replace each `assert.is_true(cond, msg)` with `ab.check(cond, label, msg)`;
  leave `pack_gate.health` as plain asserts. In `solo_spec.lua:21-25` and `group_spec.lua`'s bars, the same. In
  `detect.boot` (`detect.lua:149-152`) and `drive.boot`'s default build (`drive.lua:52-56`): `def.providers =
  ab.providers()` before `I.Build`.

- [ ] **Step 5: The shapes.** `world.lua:47-50`: `W.mrng = rng.new(seed + 32452843) -- the meter and viewer shapes, apart
  from every other draw`. `observer.lua` `DEFAULTS`: `meter = false`, `viewer = false`, `takenLag = 0`, `group = true`.
  In `M.new`, a helper:

```lua
    -- (providers spec §4.2) a damage group: types 0, 1, 10 for the session, then the same for session 0 (DM §1)
    local session = 200
    local function group(t)
        for _, sid in ipairs({ session, 0 }) do
            for _, ty in ipairs({ 0, 1, 10 }) do
                push(t, "DAMAGE_METER_COMBAT_SESSION_UPDATED", ty, sid)
            end
        end
    end
    local function inGroup(e)
        return e == us or (k.group and party[e] ~= nil)
    end
```

  and in the event loop: at `kind == "swing"` with `inGroup(ev.src)` and `ev.act == "WOUND"` (ours or a partner's, any
  hand): `if k.meter then group(t + W.mrng.int(0, 11) / 1000) end`; at `spell`, `proc`, `strike` WOUND outcomes of a group
  member: `group(t + W.mrng.int(3, 14) / 1000)`; at `tick`: `group(t + W.mrng.int(1, 2) / 1000)`; at a WOUND whose `dst`
  is us or a party member (a mob's swing or spell): `push(t, "DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, session)`, and when
  `k.takenLag > 0` and `dst == us`, the row on us moves to `t + k.takenLag + W.mrng.real() * 0.24 - 0.12`. At `kind ==
  "aura"` of ours (the existing branch, `observer.lua:526-531`): `if k.viewer then push(t + W.mrng.int(3, 5) / 1000,
  "@viewer", unit, ev.aura, ev.stacks > 0) end`. Add `meter`, `viewer`, `takenLag` to the knobs `scenarios.stream`
  passes through, and `detect.BANDS` gains `group = true` (party, raid12-40) and `group = false` (busy), passed as
  `o.group`.

- [ ] **Step 6: The fakes.** `fake_api.lua`: `ctl.meter = { available = true, done = {}, taken = {} }` and
  `api.C_DamageMeter = { IsDamageMeterAvailable = function() return ctl.meter.available end,
  GetCombatSessionFromType = function(st, ty) ... end }`: in combat (`ctl.combat`) every number field is `SECRET`;
  out of combat `{ combatSources = { { isLocalPlayer = true, totalAmount = ctl.meter.done[1] or 0 } } }` for type 0 and
  the same from `taken` for type 7. `ctl.viewer = { available = true, sets = { [0] = {}, ... }, infos = {}, items = {} }`
  and `api.C_CooldownViewer = { IsCooldownViewerAvailable, GetCooldownViewerCategorySet, GetCooldownViewerCooldownInfo }`
  reading it; four viewer frames on `api` (`EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`,
  `BuffBarCooldownViewer`) whose `GetChildren()` returns `ctl.viewer.items[name]` (plain tables with `layoutIndex`,
  `cooldownID`, `auraInstanceID`, `auraDataUnit`, `HookScript`, and `ctl.ViewerShow(item, up)`, which sets
  `auraInstanceID` to `SECRET` or nil and runs the OnShow or OnHide hooks). `drive.lua`'s `@viewer` (unit, spellID, up):
  finds the item whose info's `spellID` is that spell and calls `ctl.ViewerShow`. The drive's meter totals:
  `drive.lua` accumulates our true row amounts into `ctl.meter.done[1]` as it fires them.

- [ ] **Step 7: Make.**

```make
# The A/B (providers spec §4.1): the gate once per arm on the same seeds; the provider arms record in .ab/<arm>.tsv.
gate-ab:
	rm -rf .ab
	$(MAKE) gate
	HEKILI_AB=meter $(MAKE) gate
	HEKILI_AB=viewer $(MAKE) gate
	@wc -l .ab/*.tsv
```

  (add `gate-ab` to `.PHONY`).

- [ ] **Step 8: Run.** `.lua/bin/busted tests/Game/harness/ab_spec.lua tests/Game/harness/observer_spec.lua`: PASS.
  `make check`; the first gate: `IDENTICAL` (the shapes are off by default; `ab.check` asserts in the default arm).

- [ ] **Step 9: Commit.**

```bash
git add -A tests Makefile .gitignore
git commit -m "test(harness): the providers A/B arm, the measured meter and viewer shapes, make gate-ab

ab.check asserts in the default arm and records in a provider arm; the observer's meter ticks
(0-11 ms after a hit swing, none for an avoid; spells 3-14 ms after their row; type 7 at hits on
the group) and viewer edges (3-5 ms) only add events, from their own generator (providers spec
decisions 83-84). Every gate is identical.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 3: The Meter provider, its unit tests and the Snapshot audit line

**Files:**
- Create: `src/Hekili/Game/State/Sources/Outcomes/Meter.lua`, `tests/Game/State/meter_spec.lua`
- Modify: `src/Hekili/Hekili.toc`, `src/Hekili/Game/Events/Rows.lua` (the audit line, `L.fight.paid`),
  `src/Hekili/Game/State/Families/Resources.lua` (pin error), `tools/api_inventory.txt`,
  `tests/Game/State/alloc_spec.lua`

- [ ] **Step 1: Failing tests.** `tests/Game/State/meter_spec.lua` (setup as `providers_spec.lua`, building with
  `d.providers = { outcomes = "meter" }`, `VS.Start(api)`, `ctl.combat = true` and `ctl.Fire("PLAYER_REGEN_DISABLED")`):

```lua
    local function group(t)
        ctl.now = t
        ctl.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 200)
        ctl.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 0) -- the duplicate set: ignored
    end

    it("is UNKNOWN before the first group of the fight (not live)", function()
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Tick(10.02)
        assert.are.equal(3, I.Tickets.told[I.Tickets.lastSwing[1]])
    end)

    it("HIT for a group within 15 ms of the swing, AVOID without", function()
        group(5)
        ctl.now = 10
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        group(10.008)
        ctl.Tick(10.02)
        assert.are.equal(1, I.Tickets.told[I.Tickets.lastSwing[1]])
        ctl.now = 12.6
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Tick(12.62)
        assert.are.equal(2, I.Tickets.told[I.Tickets.lastSwing[1]])
    end)

    it("mutes after three more told avoids than avoid rows", function()
        group(5)
        for n = 0, 3 do
            ctl.now = 10 + 2.6 * n
            ctl.Fire("PLAYER_SWING", 2.6, 0)
            ctl.Tick(ctl.now + 0.02)
        end
        ctl.now = 21
        ctl.Fire("PLAYER_SWING", 2.6, 0)
        ctl.Tick(21.02)
        assert.are.equal(3, I.Tickets.told[I.Tickets.lastSwing[1]])
        assert.are.equal(1, I.outcomes.muted)
    end)

    it("RowOwner: a spell row with no group in its frame is FOREIGN; with one, UNKNOWN in a group", function()
        local P = I.outcomes
        group(5)
        assert.are.equal(I.FOREIGN, P.RowOwner(6, 1, 32, 50, "WOUND", 6.02))
        group(7.004)
        ctl.inGroup = true -- IsInGroup, read at PLAYER_REGEN_DISABLED
        ctl.Fire("PLAYER_REGEN_DISABLED")
        assert.are.equal(I.UNKNOWN, P.RowOwner(7, 1, 32, 50, "WOUND", 7.02))
        assert.are.equal(I.UNKNOWN, P.RowOwner(7, 1, 1, 0, "DODGE", 7.02))
    end)

    it("RowOwner: a white row with a group in the 2 s before it is not FOREIGN", function()
        group(5)
        assert.are.equal(I.OURS, I.outcomes.RowOwner(6.2, 1, 1, 40, "WOUND", 6.22))
        assert.are.equal(I.FOREIGN, I.outcomes.RowOwner(7.2, 1, 1, 40, "WOUND", 7.22))
    end)

    it("EnemyHitAt: a taken group 0.3-0.6 s before a white row on us, once", function()
        group(5)
        ctl.now = 9.6
        ctl.Fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 7, 200)
        assert.are.equal(9.6, I.outcomes.EnemyHitAt(10))
        assert.is_nil(I.outcomes.EnemyHitAt(10.01))
    end)

    it("Audit: out of combat, plain, the local player's totals; nil while secret", function()
        ctl.meter.done[1], ctl.meter.taken[1] = 923, 51
        ctl.combat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        fs.fold(ns, 30.1)
        local a = I.outcomes.Audit()
        assert.are.same({ true, 923, 51 }, { a.valid, a.done, a.taken })
    end)

    it("dormant while the default provider is active", function()
        local d = fs.def(fs.new(9))
        I.Build(d, 1)
        assert.is_falsy(api.frame:IsEventRegistered("DAMAGE_METER_COMBAT_SESSION_UPDATED"))
    end)
```

  (`ctl.inGroup` and `api.IsInGroup` join `fake_api.lua`: `function api.IsInGroup() return ctl.inGroup == true end`.)
  `alloc_spec.lua`: 1000 meter events, 100 swings and their ticks allocate 0 bytes with the Meter active.

- [ ] **Step 2: Run, expect failure** (`meter` resolves to default).

- [ ] **Step 3: `Sources/Outcomes/Meter.lua`.**

```lua
-- Game/State/Sources/Outcomes/Meter.lua
-- The damage-meter Outcomes provider (providers spec §2.2): DAMAGE_METER_COMBAT_SESSION_UPDATED's plain (type,
-- sessionID) as a ring of group times; a swing hit iff a damage group lies within 15 ms after it; a row is foreign iff
-- no group stands behind it; a taken group dates a hit on us; the getters only out of combat, for the audit.
-- Measured: docs/research/2026-10-23-damagemeter-api.md (DM §2-§4, §7). Shares no code with any other provider.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local EVENT = "DAMAGE_METER_COMBAT_SESSION_UPDATED"
local RING, MERGE, SWING_WIN, WHITE_BACK = 64, 0.003, 0.015, 2.0
local TAKEN_LO, TAKEN_HI, SPELL_TAKEN, MUTE_AT, AUDIT_FOR = 0.6, 0.3, 0.005, 3, 3

local P = { name = "meter", SWING_DELAY = SWING_WIN, ROW_DELAY = SWING_WIN, muted = 0 }
local gT, gKind, gUsed = {}, {}, {}
for k = 1, RING do
    gT[k], gKind[k], gUsed[k] = -1e9, 0, false
end
local head = 0
local active, available, seen, grouped = false, false, false, false
local toldAvoid, avoidRows = 0, 0
local audit = { valid = false, done = 0, taken = 0, at = 0 }
local auditFrom = 0 -- the time of the combat end the audit waits for (0: none pending)

S.On(EVENT, nil, function(api, t, ty, sid)
    if not active or sid == 0 or type(ty) ~= "number" then
        return
    end
    local kind = (ty == 7) and 7 or ((ty == 0 or ty == 1 or ty == 10) and 0 or -1)
    if kind < 0 then
        return
    end
    if gKind[head] == kind and head > 0 and t - gT[head] <= MERGE then
        return -- the same server batch (DM §2: 29244/29245)
    end
    head = head % RING + 1
    gT[head], gKind[head], gUsed[head] = t, kind, false
    if kind == 0 then
        seen = true
    end
end)
S.Dormant(EVENT, true)

-- Any damage group in [lo, hi]. Allocates nothing.
local function any(lo, hi)
    for k = 1, RING do
        if gKind[k] == 0 and gT[k] >= lo and gT[k] <= hi then
            return true
        end
    end
    return false
end

local function live()
    return active and available and seen and P.muted == 0
end

function P.Activate(api, t)
    active = true
    available = false
    if api then
        local ok, a = pcall(api.C_DamageMeter.IsDamageMeterAvailable) -- secret: Plain next (measured plain, DM §4)
        available = ok and Plain(api, a) == true
        S.Dormant(EVENT, false)
        I.Events.Sync(EVENT)
    end
end

function P.Deactivate()
    active = false
    S.Dormant(EVENT, true)
    I.Events.Sync(EVENT)
end

function P.SwingOutcome(i, now)
    if not live() then
        return I.UNKNOWN
    end
    local at = I.Tickets.at[i]
    if any(at, at + SWING_WIN) then
        return I.HIT
    end
    toldAvoid = toldAvoid + 1
    if toldAvoid > avoidRows + MUTE_AT then
        P.muted = 1
        return I.UNKNOWN
    end
    return I.AVOID
end

function P.RowOwner(t, uid, school, amount, act, now)
    if not live() or act ~= "WOUND" then
        return I.UNKNOWN
    end
    local lo = school == 1 and t - WHITE_BACK or t - MERGE
    if not any(lo, t + SWING_WIN) then
        return I.FOREIGN
    end
    return grouped and I.UNKNOWN or I.OURS
end

function P.EnemyHitAt(t)
    if not live() or grouped then
        return nil
    end
    for k = 1, RING do
        if gKind[k] == 7 and not gUsed[k] and t - gT[k] <= TAKEN_LO and t - gT[k] >= TAKEN_HI then
            gUsed[k] = true
            return gT[k]
        end
    end
    return nil
end

function P.Audit()
    return audit.valid and audit or nil
end

-- the white avoid rows the mute compares against (any unit: an avoid of ours is on the unit we swung at)
I.Units.OnRow(function(t, g, uid, act, flag, amount, school)
    if active and school == 1 and (act == "MISS" or act == "DODGE" or act == "PARRY") then
        avoidRows = avoidRows + 1
    end
end)

S.On("PLAYER_REGEN_DISABLED", nil, function(api, t)
    if not active then
        return
    end
    seen, P.muted, toldAvoid, avoidRows = false, 0, 0, 0
    grouped = Plain(api, api.IsInGroup()) == true -- secret: Plain (IsInGroup is plain)
    audit.valid, auditFrom = false, 0
end)

S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    if active then
        auditFrom = t
    end
end)

-- One getter read of `ty` (0 done, 7 taken): the local player's total, or nil when anything read is secret or
-- missing. Out of combat only: the getters allocate (DM §7).
local function total(api, ty)
    local ok, s = pcall(api.C_DamageMeter.GetCombatSessionFromType, 1, ty) -- secret: tested next
    if not ok or api.issecretvalue(s) or type(s) ~= "table" then
        return nil
    end
    local list = s.combatSources
    if api.issecretvalue(list) or type(list) ~= "table" then
        return nil
    end
    for k = 1, #list do
        local src = list[k]
        local mine = Plain(api, src.isLocalPlayer) -- NeverSecret (DM §4)
        if mine == true then
            local v = Plain(api, src.totalAmount)
            return type(v) == "number" and v or nil
        end
    end
    return 0 -- no row of ours this session
end

-- Poll 12: the audit, out of combat, retried for AUDIT_FOR s after combat end.
S.Poll(12, function(api, t)
    if auditFrom == 0 or I.inCombat then
        return
    end
    if t - auditFrom > AUDIT_FOR then
        auditFrom = 0
        return
    end
    local d, k = total(api, 0), total(api, 7)
    if d and k then
        audit.valid, audit.done, audit.taken, audit.at, auditFrom = true, d, k, t, 0
    end
end)

I.OUTCOMES.meter = P
```

  (Check that poll 12 is free: `grep -n "S.Poll(12" -r src/Hekili/Game`; take the next free order if not, and update the
  comment.) `Hekili.toc`: `Game\State\Sources\Outcomes\Meter.lua` after `Game\State\Sources\Enchants.lua`.
  `tools/api_inventory.txt`: `C_DamageMeter.GetCombatSessionFromType\tpassthrough`,
  `C_DamageMeter.IsDamageMeterAvailable\tpassthrough`, `IsInGroup\tpassthrough` (if absent), sorted.

- [ ] **Step 4: The audit line.** In Rows: `L.fight.paid` adds `amount` at `paySpell` (`T.Pay` call, line 192) and at the
  swing credit (line 335); add `swingsTick`, `swingsAvoid`, `swingsRow`, `swingsUnknown` to `L.fight`, counted in
  `T.Decide` (1, 2, 3) and in the swing credit and `T.Provisional` paths when `T.told[credited] == 0` (by a row). In
  Resources' flip branch (`Resources.lua:1055`): `R.pinN[r], R.pinErr[r] = R.pinN[r] + 1, R.pinErr[r] + abs(e1 - c)`
  (preallocated per slot at build; reset at `PLAYER_REGEN_DISABLED`), and `I.PinError()` returning the sums over slots.
  Rows' snapshot:

```lua
I.OnSnapshot(function(out)
    local f, a = L.fight, I.outcomes.Audit()
    local pn, pe = I.PinError()
    local up, down = I.presenceEdges and I.presenceEdges.up or 0, I.presenceEdges and I.presenceEdges.down or 0
    out[#out + 1] = string.format(
        "providers outcomes=%s presence=%s swings tick=%d/%d row=%d unknown=%d muted=%d ownUnclaimed=%d foreignByMeter=%d",
        I.outcomes.name, I.presence.name, f.swingsTick, f.swingsAvoid, f.swingsRow, f.swingsUnknown,
        I.outcomes.muted or 0, f.ownUnclaimed, f.foreignByMeter
    )
    out[#out + 1] = string.format(
        "providers paid=%d meter=%s pins=%d pinErr=%.1f edges up=%d down=%d",
        f.paid, a and tostring(a.done) or "-", pn, pn > 0 and pe / pn or 0, up, down
    )
end)
```

  (Two lines so each stays under 255 characters for VSCopy. `I.presenceEdges` is counted by the router in Task 6; until
  then 0.)

- [ ] **Step 5: Run.** `.lua/bin/busted tests/Game/State/meter_spec.lua tests/Game/State/alloc_spec.lua`: PASS.
  `make check`. The first gate: `IDENTICAL` except the two new `providers` Snapshot lines where a spec prints the whole
  Snapshot (a spec that compares Snapshot text adds them).

- [ ] **Step 6: Commit.**

```bash
git add -A src/Hekili tests tools/api_inventory.txt
git commit -m "feat(providers): the damage-meter Outcomes provider and the per-fight audit line

A preallocated ring of the plain group events; HIT iff a damage group within 15 ms of the swing,
live only after the fight's first group and until told avoids outrun avoid rows by 3; FOREIGN
iff no group behind the row; taken groups date hits on us solo; the getters read out of combat
only for the audit (providers spec §2.2, decisions 71-76, 85). Dormant unless injected.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 4: The damage-meter experimental option and the in-game wiring

**Files:**
- Modify: `src/Hekili/Options/Options.lua` (defaults line 297-301; the Experimental group after line 4100),
  `src/Hekili/Game/State/Adapter.lua` (`buildDef` line 211, after `VS.SpecChanged` line 344-347),
  `tests/Game/harness/loop.lua` (the arm's toggles), `CHANGELOG.md`
- Create: `tests/Forever/providers_option_spec.lua`

- [ ] **Step 1: Failing test.** `tests/Forever/providers_option_spec.lua` (boot as `tests/Forever/output_spec.lua`'s `H`
  helper does):

```lua
describe("the providers options", function()
    it("default off: the build injects the Default outcomes and the router with no leaf", function()
        local H = require("Forever.helpers.engine").boot()
        assert.are.same({ "default", false }, { H.ns.VirtualStateInternal.outcomes.name, H.Hekili.DB.profile.performance.damageMeter })
    end)

    it("on, out of combat: the meter at once; in combat: at combat end", function()
        local H = require("Forever.helpers.engine").boot()
        local I = H.ns.VirtualStateInternal
        H.Hekili.DB.profile.performance.damageMeter = true
        H.Hekili:ProvidersChanged()
        assert.are.equal("meter", I.outcomes.name)
        H.Hekili.DB.profile.performance.damageMeter = false
        I.inCombat = true
        H.Hekili:ProvidersChanged()
        assert.are.equal("meter", I.outcomes.name)
        I.inCombat = false
        H.ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal("default", I.outcomes.name)
    end)
end)
```

  (Use the boot helper the other `tests/Forever/*_spec.lua` engine specs use; `grep -ln "Forever.helpers.engine"
  tests/Forever` shows it.)

- [ ] **Step 2: Run, expect failure** (`damageMeter` nil; `ProvidersChanged` missing).

- [ ] **Step 3: Options.** Defaults: `performance = { frameBudget = 0.7, forecastWindow = 15, damageMeter = false,
  cooldownViewer = false }`. After `steadyIcons` (line 4089-4099):

```lua
                                damageMeter = {
                                    type = "toggle",
                                    name = "Experimental: use the damage meter for swing outcomes",
                                    desc = "Reads the game's damage meter events (they work with the Damage Meter window hidden or disabled) to know "
                                        .. "at once whether your white swing hit, and that another player's hit was not yours.\n\n"
                                        .. "Changes apply at once out of combat, otherwise when the fight ends. Applies to every specialization.\n\n"
                                        .. "|cFFFF7F00Experimental|r: off by default while it is being play-tested.",
                                    get = function() return Hekili.DB.profile.performance.damageMeter == true end,
                                    set = function( _, v )
                                        Hekili.DB.profile.performance.damageMeter = v
                                        Hekili:ProvidersChanged()
                                    end,
                                    order = 22,
                                    width = "full",
                                },
```

- [ ] **Step 4: Adapter.**

```lua
-- (providers spec §3.4, decision 82) The experimental toggles as the build config's providers. The router is always
-- injected; without the viewer leaf it covers nothing (the Default path).
local function providersOf()
    local p = Hekili.Engine.settings.performance or {}
    return p.damageMeter == true and "meter" or "default", "router", p.cooldownViewer == true
end
```

  In `buildDef()` after `wipe`: `def.providers = def.providers or {}` and
  `def.providers.outcomes, def.providers.presence, def.providers.viewer = providersOf()` (the `wipe` loop skips
  `providers`: give `def` a `providers = {}` entry and wipe it like the lists, then refill). Then:

```lua
--- Re-reads the experimental toggles: applied at once out of combat, else at combat end (VS.SetProviders).
function Hekili:ProvidersChanged()
    VS.SetProviders(providersOf())
end
```

  (`Engine.settings.performance` is the profile's table by reference, `Engine/Settings.lua:9-25`, `:39-52`.)

- [ ] **Step 5: The loops follow the arm.** In `tests/Game/harness/loop.lua`, where the profile is prepared for a run
  (beside `sp.steadyIcons`, line 258): `local arm = ab.ARMS[ab.arm()]` and
  `Hekili.DB.profile.performance.damageMeter, Hekili.DB.profile.performance.cooldownViewer = arm.outcomes == "meter",
  arm.viewer` before the spec change; the loop's observer knobs gain `meter = arm.outcomes == "meter"` and
  `viewer = arm.viewer` (so the default arm's stream is today's: the shapes are off).

- [ ] **Step 6: Changelog.** Under "Unreleased": "Experimental option (off by default): use the game's damage meter
  events to know at once whether a white swing hit. Options > Performance > Experimental."

- [ ] **Step 7: Run.** `.lua/bin/busted tests/Forever/providers_option_spec.lua`: PASS. `make check`; the first gate:
  `IDENTICAL`.

- [ ] **Step 8: In-game checkpoint (owner).** `/reload`; toggle the option out of combat; one solo pull each way;
  `/run VSCopy(Hekili.Virtual.State.Snapshot())`; the `providers` lines show `outcomes=meter` with `tick` counts near the
  swing count and `paid` equal to `meter` (DM §3: exact solo), and `outcomes=default` with `tick=0/0`.

- [ ] **Step 9: Commit.**

```bash
git add -A src/Hekili tests CHANGELOG.md
git commit -m "feat(options): experimental damage-meter switch, injected as the Outcomes provider

profile.performance.damageMeter (off by default) under Performance > Experimental; the game layer
maps it to def.providers at build and through Hekili:ProvidersChanged (at once out of combat,
else at combat end); the loops take the A/B arm's toggles (providers spec decision 82).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 5: The CooldownViewer leaf, its frame fakes, the coverage report

**Files:**
- Create: `src/Hekili/Game/State/Sources/Presence/CooldownViewer.lua`, `tests/Game/State/viewer_spec.lua`,
  `tools/check_cooldown_viewer.lua`, `tools/data/cooldownviewer/WARRIOR.lua`
- Modify: `src/Hekili/Hekili.toc`, `tools/api_inventory.txt`, `Makefile`

- [ ] **Step 1: Failing tests.** `tests/Game/State/viewer_spec.lua` (setup as `providers_spec.lua`; a fixture: aura
  `fs.SPENDER_A`'s ID in category 2 as cooldownID 501 with a BuffIcon item for it, unit "player"; `fs.SPENDER_C_R2` as
  `linkedSpellIDs` of cooldownID 502 with an item on "target"; the leaf injected directly with
  `d.providers = { presence = "viewer" }`):

```lua
    it("maps by spell, override and linked IDs; covers what it maps", function()
        local Q = I.presence
        assert.are.equal("viewer", Q.name)
        assert.are.equal("self", Q.scope)
        assert.are.equal(2, Q.covered)
        assert.are.equal(I.DOWN, Q.Presence(1, 1))
        assert.are.equal(I.UNKNOWN, Q.Presence(3, 1))
    end)

    it("reads presence at the hook: secret id is up, nil is down; a change only", function()
        local edges = {}
        I.presence.onEdge = function(j, u, up, t)
            edges[#edges + 1] = { j, u, up }
        end
        ctl.combat = true
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true) -- a layout refresh: no change, no edge
        assert.are.same({ { 1, 1, true } }, edges)
        assert.are.equal(I.UP, I.presence.Presence(1, 1))
    end)

    it("a hide with the aura still up is no edge (layout refresh, CDM-S)", function()
        local item = ctl.viewer.items.BuffIconCooldownViewer[1]
        ctl.ViewerShow(item, true)
        local n = 0
        I.presence.onEdge = function()
            n = n + 1
        end
        item.auraInstanceID = fake.SECRET
        item.__scripts.OnHide(item)
        assert.are.equal(0, n)
    end)

    it("reads nothing and hooks nothing with the Cooldown Manager unavailable", function()
        ctl.viewer.available = false
        I.Build(d, 1) -- re-activate
        assert.are.equal(0, I.presence.covered)
    end)

    it("deactivated, its hooks return at once", function()
        local d2 = fs.def(fs.new(9))
        I.Build(d2, 1) -- default presence
        local item = ctl.viewer.items.BuffIconCooldownViewer[1]
        assert.has_no.errors(function()
            ctl.ViewerShow(item, true)
        end)
    end)
```

  `alloc_spec.lua`: 100 hook calls allocate 0 bytes.

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: The leaf.**

```lua
-- Game/State/Sources/Presence/CooldownViewer.lua
-- The Cooldown Manager AuraPresence leaf (providers spec §2.4): the viewer's item frames carry a plain presence bit in
-- combat (auraInstanceID secret while up, nil while down); HookScript OnShow/OnHide read it 3-5 ms after the edge.
-- Scope "self": the viewer tracks player-cast auras only (probe CDM-S); presence only, never stacks or durations.
-- Read, never call: rawget on items, GetChildren out of combat, HookScript once per item; nothing written to the
-- viewer. Measured: docs/research/2026-10-23-cooldown-manager-api.md (CV §2, §5, §6). Shares no code with any other
-- provider.

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local VIEWERS = { "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local UNIT = { player = 1, target = 2 }

local Q = { name = "viewer", scope = "self", covered = 0, onEdge = nil }
local active, api0 = false, nil
local cdvToJ = {} -- cooldownID -> aura index (built out of combat)
local st = {} -- (u - 1) * AURA_UNIT + j -> 0 unknown, 1 up, 2 down
local items = {} -- the hooked item frames, for the target re-read (built out of combat)
local hooked = setmetatable({}, { __mode = "k" })

-- The hook (one function for every item): presence at fire time, a change only. Allocates nothing.
local function hook(self)
    if not active then
        return
    end
    local api = api0
    local id = Plain(api, rawget(self, "cooldownID"))
    local j = id and cdvToJ[id]
    local u = UNIT[Plain(api, rawget(self, "auraDataUnit")) or ""]
    if not j or not u then
        return -- a cooldown item, or an unmapped aura
    end
    local aid = rawget(self, "auraInstanceID")
    local up = api.issecretvalue(aid) or aid ~= nil -- secret: only tested, never compared
    local k = (u - 1) * I.AURA_UNIT + j
    local v = up and I.UP or I.DOWN
    if st[k] ~= v then
        st[k] = v
        if Q.onEdge then
            Q.onEdge(j, u, up, api.GetTime())
        end
    end
end

-- The map and the hooks, out of combat (allocates: the getters' tables, GetChildren's list).
local function build(api, def)
    for k in pairs(cdvToJ) do
        cdvToJ[k] = nil
    end
    for k in pairs(st) do
        st[k] = 0
    end
    Q.covered = 0
    local ok, avail = pcall(api.C_CooldownViewer.IsCooldownViewerAvailable) -- secret: Plain next
    if not ok or Plain(api, avail) ~= true or not def then
        return
    end
    local byId = {}
    for j = 1, #def.auraIds do
        for _, sid in ipairs(def.auraIds[j]) do
            byId[sid] = j
        end
    end
    for c = 0, 8 do
        local okS, set = pcall(api.C_CooldownViewer.GetCooldownViewerCategorySet, c)
        if okS and type(set) == "table" and not api.issecretvalue(set) then
            for _, id in ipairs(set) do
                local okI, info = pcall(api.C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                if okI and type(info) == "table" and not api.issecretvalue(info) then
                    local j = byId[Plain(api, info.spellID) or 0] or byId[Plain(api, info.overrideSpellID) or 0]
                    for _, l in ipairs(type(info.linkedSpellIDs) == "table" and info.linkedSpellIDs or {}) do
                        j = j or byId[Plain(api, l) or 0]
                    end
                    if j and not cdvToJ[id] then
                        cdvToJ[id] = j
                    end
                end
            end
        end
    end
    for n = 1, #items do
        items[n] = nil
    end
    local seen = {}
    for _, name in ipairs(VIEWERS) do
        local v = api[name]
        if v and v.GetChildren then
            for _, item in ipairs({ v:GetChildren() }) do
                if rawget(item, "layoutIndex") ~= nil then
                    if not hooked[item] then
                        item:HookScript("OnShow", hook)
                        item:HookScript("OnHide", hook)
                        hooked[item] = true
                    end
                    items[#items + 1] = item
                    local id = Plain(api, rawget(item, "cooldownID"))
                    local j = id and cdvToJ[id]
                    local u = UNIT[Plain(api, rawget(item, "auraDataUnit")) or ""]
                    if j and u and not seen[(u - 1) * I.AURA_UNIT + j] then
                        seen[(u - 1) * I.AURA_UNIT + j] = true
                        st[(u - 1) * I.AURA_UNIT + j] = I.DOWN
                        Q.covered = Q.covered + 1
                    end
                end
            end
        end
    end
end

function Q.Activate(api, t, def)
    api0, active = api, api ~= nil
    if api then
        build(api, def)
        for n = 1, #items do
            hook(items[n]) -- the state now
        end
    end
end

function Q.Deactivate()
    active, Q.covered = false, 0
end

function Q.Presence(j, u)
    local v = active and st[(u - 1) * I.AURA_UNIT + j] or 0
    if v == I.UP or v == I.DOWN then
        return v
    end
    return I.UNKNOWN
end

-- The target's items may change without a show edge ("hide when inactive" off, CV §7): re-read them.
S.On("PLAYER_TARGET_CHANGED", nil, function()
    if active then
        for n = 1, #items do
            hook(items[n])
        end
    end
end)

I.PRESENCE.viewer = Q
```

  Notes for the implementer: the `{ v:GetChildren() }` and `seen` tables are built out of combat only (activation); the
  router (Task 6) owns the set-change rebuild, which calls `Activate` again. `auraDataUnit` is set on an item only while
  its aura data is known; an item whose unit reads nil at build is counted when its first edge comes (add
  `Q.covered = Q.covered + 1` in `hook` the first time a mapped pair is seen, guarded by `st[k] == 0`).
  `Hekili.toc`: `Game\State\Sources\Presence\CooldownViewer.lua` after the Meter. `tools/api_inventory.txt`:
  `C_CooldownViewer.IsCooldownViewerAvailable`, `C_CooldownViewer.GetCooldownViewerCategorySet`,
  `C_CooldownViewer.GetCooldownViewerCooldownInfo` (passthrough).

- [ ] **Step 4: The coverage report.** `tools/data/cooldownviewer/WARRIOR.lua` (from the 2026-10-23 `/vslog cdv ids`
  capture in the session transcript; the owner re-captures if the transcript is gone):

```lua
-- tools/data/cooldownviewer/WARRIOR.lua: the Forever client's default Cooldown Manager sets for the Warrior
-- (ForeverProbe /vslog cdv ids, 2026-10-23, Fury L25). Dev-only: tools/check_cooldown_viewer.lua reads it.
-- stylua: ignore
return {
    -- [cooldownID] = { category, spellID, overrideSpellID, { linkedSpellIDs } }
    [199683] = { 0, 7405, nil, {} }, -- Sunder Armor (CDM-S)
    -- ... every id of categories 0, 1, 2, 5, 7 from the capture
}
```

  `tools/check_cooldown_viewer.lua`:

```lua
-- tools/check_cooldown_viewer.lua (providers spec §2.4, decision 81): a coverage report, never a failure. For each
-- class pack, the auras the Cooldown Manager tracks (answered by the fact) and the ones it does not (the modelled timer),
-- from tools/data/cooldownviewer/<CLASS>.lua. Loads packs as tools/check_spell_data.lua does.
package.path = "./src/Hekili/?.lua;./tests/?.lua;./?.lua;" .. package.path
local loader = require("Forever.helpers.load_druid")
local warrior = require("Forever.helpers.load_warrior")

local CLASSES = { "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior" }
for _, class in ipairs(CLASSES) do
    local f = loadfile("tools/data/cooldownviewer/" .. class:upper() .. ".lua")
    local okF, fix = pcall(f or error)
    if not f then
        print(class .. "\tno fixture")
    elseif not okF or type(fix) ~= "table" then
        print(class .. "\tunreadable fixture")
    else
        local ids = {}
        for _, e in pairs(fix) do
            for _, sid in ipairs({ e[2], e[3], unpack(e[4] or {}) }) do
                ids[sid] = true
            end
        end
        local w = class == "Warrior" and warrior.load()
            or loader.load(nil, "src/Hekili_" .. class .. "/" .. class .. ".lua", class:upper())
        local keys = {}
        for key, a in pairs(w.auras) do
            if type(key) == "string" and type(a) == "table" and a.key == key then
                keys[#keys + 1] = key
            end
        end
        table.sort(keys)
        local n, hit = 0, 0
        for _, key in ipairs(keys) do
            local a = w.auras[key]
            local list = { a.id }
            for _, c in ipairs(type(a.copy) == "table" and a.copy or { a.copy }) do
                list[#list + 1] = c
            end
            local tracked = false
            for _, sid in ipairs(list) do
                tracked = tracked or (type(sid) == "number" and ids[sid] == true)
            end
            n, hit = n + 1, hit + (tracked and 1 or 0)
            print(class .. "\t" .. key .. "\t" .. (tracked and "viewer" or "model"))
        end
        print(class .. "\tcoverage\t" .. hit .. "/" .. n)
    end
end
os.exit(0)
```

  `Makefile`: `cdv-coverage:` / `\t$(LUA) tools/check_cooldown_viewer.lua` with a comment "dev-only coverage report
  (providers spec decision 81); not part of check", and `.PHONY`.

- [ ] **Step 5: Run.** `.lua/bin/busted tests/Game/State/viewer_spec.lua tests/Game/State/alloc_spec.lua`: PASS.
  `make cdv-coverage | tail -3`: prints the Warrior coverage line and exits 0. `make check`.

- [ ] **Step 6: Commit.**

```bash
git add -A src/Hekili tests tools Makefile
git commit -m "feat(providers): the Cooldown Manager presence leaf and its coverage report

Item frames' auraInstanceID (secret up, nil down) read at HookScript OnShow/OnHide time, a change
only; the map from the client's category sets by spell, override and linked IDs, out of combat;
scope self (probe CDM-S); make cdv-coverage reports pack auras tracked vs modelled, never fails
(providers spec §2.4, decisions 77-79, 81). Not injected yet.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 6: The Presence router and the per-aura audit

**Files:**
- Create: `src/Hekili/Game/State/Sources/Presence/Router.lua`, `tests/Game/State/router_spec.lua`
- Modify: `src/Hekili/Hekili.toc`, `src/Hekili/Game/State/Sources/Auras.lua` (per-aura Snapshot lines),
  `tools/api_inventory.txt` (none new)

- [ ] **Step 1: Failing tests.** `tests/Game/State/router_spec.lua` (the Task 5 fixture; build with
  `d.providers = { presence = "router", viewer = true }`):

```lua
    it("a tracked aura is answered by the viewer leaf", function()
        local R = I.presence
        assert.are.equal("router", R.name)
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        assert.are.equal(I.UP, R.Presence(1, 1))
    end)

    it("an untracked aura answers UNKNOWN (the modelled timer)", function()
        assert.are.equal(I.UNKNOWN, I.presence.Presence(3, 1))
    end)

    it("switch off: every aura UNKNOWN, covered 0, no hook installed, no getter read", function()
        local calls = 0
        local get = api.C_CooldownViewer.GetCooldownViewerCategorySet
        api.C_CooldownViewer.GetCooldownViewerCategorySet = function(...)
            calls = calls + 1
            return get(...)
        end
        local d2 = fs.def(fs.new(9))
        d2.providers = { presence = "router", viewer = false }
        I.Build(d2, 1)
        assert.are.same({ 0, 0 }, { I.presence.covered, calls })
        for j = 1, I.auras.nAura do
            assert.are.equal(I.UNKNOWN, I.presence.Presence(j, 1))
        end
    end)

    it("rebuilds on the viewer's set-change event out of combat only", function()
        ctl.viewer.sets[2][#ctl.viewer.sets[2] + 1] = 503 -- spender_m's cooldown now tracked
        ctl.viewer.infos[503] = { cooldownID = 503, spellID = fs.SPENDER_M, linkedSpellIDs = {} }
        I.inCombat = true
        ctl.Fire("COOLDOWN_VIEWER_DATA_LOADED")
        local jm = I.auras.byKey.spender_m
        assert.is_false(I.presence.tracked[jm])
        I.inCombat = false
        ctl.Fire("PLAYER_REGEN_ENABLED")
        assert.is_true(I.presence.tracked[jm])
    end)

    it("passes only tracked edges on and counts them", function()
        ctl.ViewerShow(ctl.viewer.items.BuffIconCooldownViewer[1], true)
        assert.are.equal(1, I.presenceEdges.up)
    end)
```

  And in `tests/Game/State/auras_spec.lua`: with the router and viewer on, a viewer UP for an aura the belief holds down
  stages one `Obs.Read` up and counts one disagreement; an UP for an aura already believed up counts a fact, no
  disagreement.

- [ ] **Step 2: Run, expect failure.**

- [ ] **Step 3: The router.**

```lua
-- Game/State/Sources/Presence/Router.lua
-- The Presence router (providers spec §2.5, decisions 88-90): only a map and delegation. At activation, out of combat,
-- it reads the Cooldown Manager's category sets itself and marks each tracked aura; a tracked aura is answered by the
-- viewer leaf (a fact), an untracked one UNKNOWN (the belief's modelled timer). The experimental switch (cfg.viewer)
-- decides whether it has the leaf: without it every answer is UNKNOWN, as the Default provider. The tracked set
-- changes only out of combat. Knows the leaf only through the contract (I.PRESENCE.viewer).

local _, ns = ...
local I = ns.VirtualStateInternal
local S = I.Sources
local Plain = S.Plain

local R = { name = "router", scope = nil, covered = 0, onEdge = nil, tracked = {} }
local tracked = R.tracked
local leaf, api0, def0, pending = nil, nil, nil, false
I.presenceEdges = { up = 0, down = 0 }

local function forward(j, u, up, t)
    if tracked[j] then
        if up then
            I.presenceEdges.up = I.presenceEdges.up + 1
        else
            I.presenceEdges.down = I.presenceEdges.down + 1
        end
        if R.onEdge then
            R.onEdge(j, u, up, t)
        end
    end
end

-- Marks tracked[j] from the client's sets, out of combat (allocates: the getters).
local function mark(api, def)
    for j = 1, #tracked do
        tracked[j] = false
    end
    if not def then
        return
    end
    for j = 1, #def.auraIds do
        tracked[j] = false
    end
    if not leaf or not api then
        return
    end
    local ok, avail = pcall(api.C_CooldownViewer.IsCooldownViewerAvailable) -- secret: Plain next
    if not ok or Plain(api, avail) ~= true then
        return
    end
    local byId = {}
    for j = 1, #def.auraIds do
        for _, sid in ipairs(def.auraIds[j]) do
            byId[sid] = j
        end
    end
    for c = 0, 8 do
        local okS, set = pcall(api.C_CooldownViewer.GetCooldownViewerCategorySet, c)
        if okS and type(set) == "table" and not api.issecretvalue(set) then
            for _, id in ipairs(set) do
                local okI, info = pcall(api.C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                if okI and type(info) == "table" and not api.issecretvalue(info) then
                    local j = byId[Plain(api, info.spellID) or 0] or byId[Plain(api, info.overrideSpellID) or 0]
                    for _, l in ipairs(type(info.linkedSpellIDs) == "table" and info.linkedSpellIDs or {}) do
                        j = j or byId[Plain(api, l) or 0]
                    end
                    if j then
                        tracked[j] = true
                    end
                end
            end
        end
    end
end

local function activate(api, t, def)
    mark(api, def)
    if leaf then
        leaf.onEdge = forward
        leaf.Activate(api, t, def, nil)
        R.covered, R.scope = leaf.covered, leaf.scope
    else
        R.covered, R.scope = 0, nil
    end
end

function R.Activate(api, t, def, cfg)
    api0, def0, pending = api, def, false
    leaf = (cfg and cfg.viewer) and I.PRESENCE.viewer or nil
    activate(api, t, def)
end

function R.Deactivate(t)
    if leaf then
        leaf.Deactivate(t)
    end
    leaf, R.covered, R.scope = nil, 0, nil
end

function R.Presence(j, u)
    if leaf and tracked[j] then
        return leaf.Presence(j, u)
    end
    return I.UNKNOWN
end

-- The viewer's sets changed (CV §3): rebuild out of combat, else at combat end (decision 89).
local function changed(api, t)
    if not leaf or I.presence ~= R then
        return
    end
    if I.inCombat then
        pending = true
    else
        activate(api0, t, def0)
    end
end
S.On("COOLDOWN_VIEWER_DATA_LOADED", nil, changed)
S.On("COOLDOWN_VIEWER_TABLE_HOTFIXED", nil, changed)
S.On("PLAYER_REGEN_ENABLED", nil, function(api, t)
    if pending and I.presence == R then
        pending = false
        activate(api0, t, def0)
    end
end)

I.PRESENCE.router = R
```

  `Hekili.toc`: `Game\State\Sources\Presence\Router.lua` after the
  CooldownViewer leaf. The two `COOLDOWN_VIEWER_*` events stay registered in every arm (rare, out of combat; the
  handler returns at once without a leaf); if the first gate's `events delivered` line differs, mark them dormant like
  the Meter's and wake them in `R.Activate` when `leaf`.

- [ ] **Step 4: Per-aura audit lines.** In `Sources/Auras.lua`, a Snapshot hook:

```lua
I.OnSnapshot(function(out)
    local P, U = I.presence, I.auras
    if not U or not P or P.name == "default" then
        return
    end
    for u = 1, (U.n < 2 and U.n or 2) do
        for j = 1, U.nAura do
            local k = (u - 1) * I.AURA_UNIT + j
            local facts = I.presenceFacts[k] or 0
            local path = (P.tracked and P.tracked[j]) and "viewer" or "model"
            if facts > 0 or path == "viewer" then
                out[#out + 1] = string.format(
                    "presence %s unit=%s path=%s facts=%d disagree=%d",
                    tostring(I.def.auras[j].key), u == 1 and "player" or "target", path, facts,
                    I.presenceDisagree[k] or 0
                )
            end
        end
    end
end)
```

  (Reset `I.presenceFacts`/`I.presenceDisagree` and `I.presenceEdges` at `PLAYER_REGEN_DISABLED`, so the lines are per
  fight.) Snapshot allocates; it is debugging only.

- [ ] **Step 5: Run.** `.lua/bin/busted tests/Game/State/router_spec.lua tests/Game/State/auras_spec.lua
  tests/Game/State/viewer_spec.lua`: PASS. `make check`. The first gate: `IDENTICAL` (the default arm now injects
  the router with no leaf, `ab.ARMS.default`; with no leaf it records no facts, so it prints no `presence` lines).

- [ ] **Step 6: Commit.**

```bash
git add -A src/Hekili tests
git commit -m "feat(providers): the Presence router: viewer facts for tracked auras, the model elsewhere

A third container holding only the tracked map (read from the Cooldown Manager's sets out of
combat, rebuilt on its set-change events only out of combat) and delegation to the viewer leaf;
switch off answers UNKNOWN everywhere, identical to the Default provider; per-aura audit lines
(path, facts, disagreements with the modelled timer) (providers spec §2.5, decisions 88-90).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 7: The Cooldown Manager experimental option and the wiring

**Files:**
- Modify: `src/Hekili/Options/Options.lua`, `tests/Forever/providers_option_spec.lua`, `CHANGELOG.md`

- [ ] **Step 1: Failing test.** Add to `providers_option_spec.lua`:

```lua
    it("the viewer switch gives the router its leaf, out of combat at once", function()
        local H = require("Forever.helpers.engine").boot()
        local I = H.ns.VirtualStateInternal
        assert.are.same({ "router", 0 }, { I.presence.name, I.presence.covered })
        H.Hekili.DB.profile.performance.cooldownViewer = true
        H.Hekili:ProvidersChanged()
        assert.is_true(I.presenceViewer)
    end)
```

- [ ] **Step 2: Run, expect failure** (no option; `ProvidersChanged` already passes the third value from Task 4's
  `providersOf`, so the failure is the missing default; if it passes, keep it as the regression test).

- [ ] **Step 3: Options.** After `damageMeter`:

```lua
                                cooldownViewer = {
                                    type = "toggle",
                                    name = "Experimental: use the Cooldown Manager for aura presence",
                                    desc = "Reads whether your own buffs and your debuffs on the target are up from the game's Cooldown Manager, "
                                        .. "for the auras it tracks; the others keep their timers. Needs the Cooldown Manager enabled in the game options. "
                                        .. "Shows presence only (no durations or stacks), and only auras you applied.\n\n"
                                        .. "Changes apply at once out of combat, otherwise when the fight ends.\n\n"
                                        .. "|cFFFF7F00Experimental|r: off by default while it is being play-tested.",
                                    get = function() return Hekili.DB.profile.performance.cooldownViewer == true end,
                                    set = function( _, v )
                                        Hekili.DB.profile.performance.cooldownViewer = v
                                        Hekili:ProvidersChanged()
                                    end,
                                    order = 23,
                                    width = "full",
                                },
```

- [ ] **Step 4: Changelog.** "Experimental option (off by default): read aura presence from the game's Cooldown Manager
  for the auras it tracks. Options > Performance > Experimental."

- [ ] **Step 5: Run.** The spec: PASS. `make check`; the first gate: `IDENTICAL`.

- [ ] **Step 6: In-game checkpoint (owner).** With `/console taintLog 1` (probe CDM-T): toggle on out of combat; a pull
  with our DoT and a proc; `/run VSCopy(Hekili.Virtual.State.Snapshot())`: `presence <key> path=viewer facts>0` lines
  for the tracked auras, `edges up/down` counts; the Cooldown Manager still updates in combat; `Logs/taint.log` names
  neither Hekili nor the viewer. If it does: stop, report to the owner (spec §6 CDM-T: the per-poll fallback).

- [ ] **Step 7: Commit.**

```bash
git add -A src/Hekili tests CHANGELOG.md
git commit -m "feat(options): experimental Cooldown Manager switch: the presence router gets the viewer leaf

profile.performance.cooldownViewer (off by default); off, the router covers nothing (the Default
path) (providers spec decisions 82, 88).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 8: The A/B measurement, the docs and the changelog

**Files:**
- Create: `docs/dev/providers-ab.md`
- Modify: `docs/dev/gaps.md`, `docs/dev/ingame-ledger.md`, `docs/superpowers/specs/2026-10-23-providers-design.md`
  (status), `CHANGELOG.md`, `tests/Game/harness/detect.lua` (the shapes on in a provider arm)

- [ ] **Step 1: Shapes on in the provider arms.** In `detect.run` (`detect.lua:155-191`) and `loop.lua`: `o.meter =
  ab.arm() == "meter"`, `o.viewer = ab.arm() == "viewer"`. The default arm keeps them off (its stream is today's). A
  second meter arm with `takenLag` on for both runs (`HEKILI_AB=meter HEKILI_TAKENLAG=1`, read in `scenarios.stream`) is
  recorded for Attackers only.

- [ ] **Step 2: Run the A/B.**

```bash
make gate-ab 2>&1 | tee /tmp/gate-ab.log
cp .ab/meter.tsv .ab/viewer.tsv /tmp/
```

  Expected: the default gate passes unchanged (the first gate holds); the two TSVs hold every cell.

- [ ] **Step 3: Record.** `docs/dev/providers-ab.md`: for each arm, one table per gate family (detection kinds x bands:
  recall, melee recall, rage error, false credit, leak; the solo/group rage gates; flicker; each loop's agreement and
  react), the default value beside the provider value and the difference, from the TSVs and the default run's log; the
  measured party collision rate (wrong HITs per 100 avoided swings in the party band, from the drive's truth) against
  spec §2.2's bound; the meter's `foreignByMeter` precision against truth; the viewer's facts and disagreements per aura
  in the Druid and Warrior loops. Header: "Measured, not gated (providers spec decision 86). The owner decides whether a
  provider becomes default." No floor file changes.

- [ ] **Step 4: Docs.** `docs/dev/gaps.md`: partners' debuffs not identifiable stays open (CDM-S: the viewer is self
  only); stacks unreadable (CDM-S 5609). `docs/dev/ingame-ledger.md`: probes DM-P, CDM-T, DM-PET, DM-FL, DM-I, CDM-I,
  CDM-C with their sequences (spec §6). The spec's status line: "BUILT (plan done); A/B in docs/dev/providers-ab.md".

- [ ] **Step 5: `make check`, `make gate`.** Green; the default gate unchanged.

- [ ] **Step 6: Commit.**

```bash
git add -A docs tests CHANGELOG.md
git commit -m "docs(providers): the A/B measured on every gate, both arms recorded; probes in the ledger

Default floors unchanged; the meter and viewer arms' numbers recorded beside them, not gated
(providers spec decision 86); the owner decides.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```
