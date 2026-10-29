# Mana Regen as wowsims Applies It: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every pack's mana regen belief (and the harness worlds that test it) follow wowsims/forever's model: every item of the regen audit, health regen excluded.

**Architecture:** One regen-entry vocabulary on a resource, each field one of wowsims's mana PseudoStats: `mult` (MultiplyManaRegenSpeed: the whole rate), `spirit` (SpiritRegenMultiplier, DB2 aura 110), `share` (SpiritRegenRateCasting, aura 134, total capped at 1 with the slot's static share) and `mp5` (an MP5 aura, aura 85 or a totem's). The `fsr` meta gains `share` (the static casting share already inside the learned split). The belief computes the rate at an instant from the set of entries up (`coefAt`) and integrates it piecewise between aura edges and the window's end (`spans`), so every new gain stays out of the calibration through the existing weights (pinA/pinB) and pinDelta. Function values (Spirit- or max-mana-scaled) are evaluated at the build and at each combat start, never per frame. A paid channel holds the casting rate to its end in the belief, the sim and the world. Then per-class tasks declare the effects and fix the seeds, and a race pack declares Energized's `mult` through a new generic race regen entry (live for its own race only).

**Tech Stack:** Lua 5.1, busted, the headless harness (tests/Game/harness), wowsims/forever logs in tests/Forever/wowsims/, `wowdb`.

**Spec:** /home/zack/.claude/jobs/080a308e/tmp/followups/regen-audit.md (the regen audit, read it whole: §0 wowsims's model, §2 per class, §3 the fix list) and the owner ruling of 2026-10-26: "Please fix them all"; mana regen must match wowsims (/home/zack/src/wowsims-forever, sim/core/mana.go:170-300, sim/core/spelldata/parse_effects_table.go:358-377); skip health regen; skip Innervate except where the shape generalises; owner amendment 2026-10-26: "we should plan the skyborne racial as well. remember that it's only one faction that gets the mana regen" (Tasks 13-14: Energized for the High Order Skyborne, Alliance, only). Starting point: branch `forever-regress-trace` after the Feral/Innervate work landed (70cf486a4 plus its four re-floors in tests/Forever/helpers/pack_gate.lua).

## Global Constraints

- Core generic rule (DEVELOPMENT.md §4, docs/dev/architecture.md): nothing class-, spell-, aura- or talent-named in `src/Hekili/` or in core tests (`tests/Game/`); core tests use neutral keys (`surge`, `focus`, `spring`); `tests/boundary_spec.lua` enforces it.
- No allocation, closure or string building in recurring paths (`I.OnAdvance`, `VS.Power`, `VS.Regen`, `spans`, `coefAt`, `I.ResourceShift`, the ladder); a function value is called only at the build and in the `Obs.CombatStart` handler.
- Secret safety: no new client read. Spirit comes from the belief's out-of-combat stat cache (`state.stat("UnitStat", 5)`, second return), max mana from `state.mana.max`.
- wowsims is the truth: Spirit regen is `6.25 + Spirit/8` a second for every class (mana.go:75-76, 178-182); in-window rate `(MP5/5 + S x m x min(c + s, 1)) x f`, outside `(MP5/5 + S x m) x f` (mana.go:186-206); window `max(spend + 5, hardcast end)`, held to a paid channel's end however it ends (mana.go:236-241, 286-288, 405-416).
- Our split: the `mp5` part A = M + cS (wowsims's casting rate), the `spirit` part B = (1 - c)S, c the slot's static share.
- Floors only move up (DEVELOPMENT.md "Floors only rise"): a task whose change would loosen a flicker floor (tests/Forever/helpers/pack_gate.lua M.FLICKER), an unmatched bar, or a ready-time floor (tests/Forever/helpers/wowsims.lua M.READY) stops and reports the line, the three seed sets and a named cause for an owner ruling. A line that improves in all three seed sets tightens its floor by pack_gate's decision-63 rule (worst of three rounded up to 0.1), comment `old -> new: <cause>`.
- A replay's decision fixture (tests/Forever/fixtures/timing_<spec>.lua) that changes is re-recorded with `TIMING=record` only when each changed row is explained by the task's regen change; the commit names the rows.
- Locking: every `make` target except `make gate` runs as `flock /tmp/hekili-gate.lock make <target>`; every probe run below holds the same lock; `make gate` takes it itself.
- Every ID is checked with `~/.local/share/wow-db2/bin/wowdb spell <id>` / `wowdb effects <id>` before it is written (IDs absent from the DB2 cite wowsims's spell_data_auto_gen.go).
- A player-visible change adds a line under "Unreleased" in CHANGELOG.md in the same commit; a moved gate line is updated in docs/dev/layout.md and its cause named in the commit.
- `make check` green on every commit; `make fmt` before committing.
- Races: a race's regen effect enters only through `race:RegisterRegenMod` (Engine/Schema/Races.lua), recorded only when the race is the player's (its token, or its race ID: UnitRace's third return), and lands on the class's resource of the named key alone; a class without that resource (Warrior, Rogue: no mana) ignores it. Core and core tests stay race-name free (neutral keys `pool_a`, `racial_a`).

## Review Focus

1. An out-of-combat regen read taken while a `spirit` or `share` aura is up (a pre-pull Innervate, Evocation just before combat ends): no read is taken, the learned parts stay; with only `mult`/`mp5` entries up the read is unscaled and net of the mp5. Pinned in Task 1 (tests "takes no out-of-combat read while a `spirit` or `share` aura is up" and the `mp5` read test).
2. A regen aura applied or expiring inside one advance step or pin interval, and the window's end inside the same step: the integrator splits at every edge. Pinned in Task 1 ("integrates a regen aura applied mid-interval and the window's end inside it").
3. Function values before the first stat read (Spirit 0) or returning a non-number: the entry is inert (spirit 1, mp5 0, value 0, share 0), never NaN. Pinned in Task 2 and in each pack function (`s > 0` guard).
4. The sim's forecast across a regen aura's edge (Evocation's mana is no longer a forecast event; the sim takes VS.Regen at `now` as constant): the Mage gates are re-measured in Task 6; a regression there stops with a named cause (upgrade path: a per-forecast multiplier, Spec.lua's existing shortcut).
5. A paid channel clipped early, pushed back (ChannelUpdate), or a free channel (Missile Barrage's Arcane Missiles, Evocation): the window ends at max(spend + 5, the channel's real end), a free channel holds nothing. Pinned in Task 10 for both event orders (spend before or after ChannelStart).
6. Race exclusivity and rebuilds: Energized's entry reaches only a High Order Skyborne (race ID 95 or its token), never the Windshaper Skyborne (Horde, 96) or a Classic race; every SpecChanged rebuild adds it once and never appends into the class's own `regenMult` table. Pinned in Task 13 (modifiers_spec, races_spec) and Task 14 (tests/Forever/races_spec.lua).
7. Energized's numbers: wowsims racials.go:207-221 doubles the whole rate (MultiplyManaRegenSpeed(2)) for 30 s; the DB2 says 15 s (SpellMisc DurationIndex 8; wowsims's comment at :210 cites index 9, Elemental Blessing's row) and aura 110 +100% (wowsims's own parser, parse_effects_table.go:372-376: SpiritRegenMultiplier, the spirit part only) plus aura 88 (health). Owner ruling 2026-10-26: "follow wowsims" (whole rate x2, 30 s); cite it in the race file's comment with the DB2 disagreement. Ledger SK1 checks it in game after launch.

## Audit item to task

| audit item | task |
|---|---|
| 1 casting-share entry (S1) and the cap (S2) | 1 (`share`, fsr `share`) |
| 2 Shaman Improved Stormstrike | 4 |
| 3 Hunter Resourcefulness, Rapid Recuperation | 5 |
| 4 Evocation from the learned rate | 1 (`spirit` + `share`), 6 |
| 5 per-spec seeds, Classic-formula comments | 4 (Shaman), 5 (Hunter), 6 (Mage), 7 (Paladin), 8 (Priest); fsr fields are already "a number or a function, read at the build" (Spec.lua:193-194): no API change |
| 6 Priest Dark Inspiration (S3 spirit-only) | 1 (`spirit`), 2 (function), 8 |
| 7 Warlock Fel Energy (% of max mana) | 2 (auraRegen `value` function), 9 |
| 8 paid channels hold the window (S5) | 10 |
| 9 Priest Dark Sacrifice from Spirit | 2, 8 |
| 10 Shaman Mana Spring dropped in combat | 1 (`mp5`), 11 |
| 11 Serenity Field (S4) / Skyborne Energized | 12 (Serenity via `spirit` function, Druid); Energized: 13 (race regen entries, race ID), 14 (High Order Skyborne race file, `mult = 2`, High Order only) |

## Measuring a class (the before/after step of Tasks 3-12 and 14)

Run from the worktree root (`$WT`). Baseline = the commit the task starts from.

```bash
BASE=$(git rev-parse HEAD)          # before the task's first edit
rm -rf /tmp/regen-base && mkdir /tmp/regen-base
git archive "$BASE" | tar -x -C /tmp/regen-base
ln -s "$WT/.lua" /tmp/regen-base/.lua
mkdir -p /tmp/regen-cmp /tmp/regen-out
```

`/tmp/regen-cmp/cmp_spec.lua` (outside the tree; never committed):

```lua
-- probe: 20 fights of LABEL from WORLD at SEED0; the loop line printed, nothing gated
local loop = require("Game.harness.loop")
describe("probe", function()
    it("tally", function()
        local w = require(os.getenv("WORLD"))
        local label, s0 = os.getenv("LABEL"), tonumber(os.getenv("SEED0"))
        local m = loop.tally(loop.new(w[label]), 20, { seed0 = s0 })
        local r = loop.summary(m)
        print(("\nRESULT %s s%d-%d flicker %.2f oracleFl %.2f agree %.3f :: %s"):format(
            label, s0 + 1, s0 + 20, r.flicker, r.oracleFlicker, r.agreement or -1, loop.line(m)))
    end)
end)
```

`/tmp/regen-cmp/run.sh TREE WORLD TAG LABEL...` runs, under one lock hold, every label at SEED0 0, 20 and 40 in parallel:

```sh
#!/bin/sh
tree=$1; world=$2; tag=$3; shift 3
cd "$tree" || exit 1
flock /tmp/hekili-gate.lock sh -c '
  for l in "$@"; do for s in 0 20 40; do
    LABEL="$l" SEED0=$s WORLD='"$world"' timeout 2400 .lua/bin/busted /tmp/regen-cmp/cmp_spec.lua \
      > "/tmp/regen-out/'"$tag"'-$l-$s.txt" 2>&1 &
  done; done; wait' sh "$@"
grep -h RESULT /tmp/regen-out/"$tag"-*.txt
```

Replay, both trees: `flock /tmp/hekili-gate.lock .lua/bin/busted --filter "<Label> .wowsims.com." tests/Forever/wowsims_<class>_spec.lua` (prints `<Label> wowsims:` and `wowsims timing:` lines). Then on the task's head: `flock /tmp/hekili-gate.lock make test-<class>`. Record a before/after table (flicker, oracle flicker, agreement, unmatched cost per seed set; replay decisions on-GCD, agreement, timing median) in the task's report.

---

### Task 1: Core: one regen-entry vocabulary in the belief

**Files:**
- Modify: `src/Hekili/Game/State/Families/Resources.lua` (M arrays :150-156; build :336-395; `scaled`/`spans`/`castingAt`/`multAt` :496-571 replaced; OnAdvance :612-635; every `spans(` caller; Read :1225-1253; VS.Power :1605-1641; VS.Regen :1657-1680; header comment :33-42)
- Modify: `src/Hekili/Engine/Schema/Spec.lua:190-220` (doc) and `:274-281` (move entries out of the regen model)
- Modify: `src/Hekili_Druid/Druid.lua:262-275` (Innervate's entry)
- Test: `tests/Game/State/resources_spec.lua` (the five-second rule describe, :1574-1800), `tests/Forever/druid_spec.lua:766-768`

**Interfaces:**
- Consumes: `def.resources[r].fsr` (`{ spirit, mp5, share? }`, numbers or functions) and `def.resources[r].mult` (the list Spec.lua moves out of the regen model), as Adapter.lua:283-288 forwards them.
- Produces (pack-facing): a regen entry `{ aura = key, mult = n, spirit = m, share = s, mp5 = x }`, any subset of the four fields (`mult` and `spirit` > 0, default 1; `share` in (0, 1], default 0; `mp5` > 0 a second, default 0); `fsr.share` = c in [0, 1] (default 0). `casting = true` is removed.
- Produces (internal, Resources.lua): `R.share[r]`; `M.mult/spirit/share/mp5[k]`; `local function coefAt(r, t, inside) -> fa, fb, k` (the rate at t is `regE*fa + spE*fb + k`); `local function spans(r, from, dt) -> a, b, k` (the integrals of fa, fb and k over (from, from + dt]).

- [ ] **Step 1: Write the failing tests** in the five-second rule describe of `tests/Game/State/resources_spec.lua`, with a local helper

```lua
local function shaped(fsr, mult)
    boot({
        abilities = {}, abilityIds = {}, abilitySlot = {},
        resources = { { key = "mana", type = MANA, token = "MANA", max = 1000, rest = true, fsr = fsr, mult = mult } },
        auras = { { key = "surge", id = 1021 }, { key = "focus", id = 1022 }, { key = "spring", id = 1023 } },
        auraIds = { { 1021 }, { 1022 }, { 1023 } },
        talents = {},
        units = { "player", "target" },
    })
    I.Settle(10)
end
```

and these tests (A = 12, B = 10, c = 0.5 means S = 20, M = 2). Where a test polls the fake client, list the modelled aura in `api.ctl.auras.player.HELPFUL` too if the poll's aura walk would otherwise drop it (the fake's GetAuraDataByIndex, tests/Game/State/helpers/fake_api.lua:316-321):

```lua
it("caps a `share` aura's casting share at all of the spirit regen with the slot's static share", function()
    shaped({ spirit = 10, mp5 = 12, share = 0.5 }, { { aura = "focus", share = 0.75 } })
    read(10, 500)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess) -- the window to 15
    I.AuraModel(1, 2, 10, 30, 1, 10, 0) -- focus up 10 to 30
    -- inside: M + S x min(0.5 + 0.75, 1) = 2 + 20, not 12 + 0.75 / 0.5 x 10 = 27
    assert.are.same({ 22, 22, 22 }, {
        VS.Regen(MANA, 12).est, VS.Regen(MANA, 12, VS.CASTING).est, VS.Regen(MANA, 16).est,
    })
    within(400 + 22 * 2, VS.Power(MANA, 12).est)
end)

it("runs a `spirit` and `share` aura at M + m x S in and out of the window", function()
    shaped({ spirit = 10, mp5 = 12, share = 0.5 }, { { aura = "surge", spirit = 16, share = 1 } })
    I.AuraModel(1, 1, 10, 30, 1, 10, 0)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess)
    assert.are.same({ 322, 322, 22, 12 }, {
        VS.Regen(MANA, 12).est, VS.Regen(MANA, 16).est, VS.Regen(MANA, 31).est, VS.Regen(MANA, 31, VS.CASTING).est,
    })
end)

it("takes the spirit regen from the mp5 part when the static share is all of it (shortcut: no mp5)", function()
    shaped({ spirit = 0, mp5 = 20, share = 1 }, { { aura = "surge", spirit = 16, share = 1 } })
    I.AuraModel(1, 1, 10, 30, 1, 10, 0)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess)
    assert.are.same({ 320, 320 }, { VS.Regen(MANA, 12).est, VS.Regen(MANA, 16).est })
end)

it("multiplies overlapping `spirit` auras and adds their shares", function()
    shaped({ spirit = 10, mp5 = 2 }, { { aura = "surge", spirit = 2 }, { aura = "focus", spirit = 3, share = 0.5 } })
    I.AuraModel(1, 1, 10, 30, 1, 10, 0)
    I.AuraModel(1, 2, 10, 30, 1, 10, 0)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess)
    assert.are.same({ 32, 62 }, { VS.Regen(MANA, 12).est, VS.Regen(MANA, 16).est })
end)

it("integrates a regen aura applied mid-interval and the window's end inside it", function()
    shaped({ spirit = 10, mp5 = 2 }, { { aura = "focus", share = 0.5 } })
    read(10, 500)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess) -- the window to 15
    I.AuraModel(1, 2, 12, 30, 1, 12, 0) -- focus from 12
    within(400 + 2 * 2 + 7 * 3 + 12 * 1, VS.Power(MANA, 16).est) -- 10-12 mp5, 12-15 + half the spirit, 15-16 all
end)

it("keeps a `share` aura's gain out of the calibration, its seconds weighing the spirit part", function()
    shaped({ spirit = 10, mp5 = 0 }, { { aura = "focus", share = 0.5 } })
    read(10, 500)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess)
    I.AuraModel(1, 2, 10, 30, 1, 10, 0)
    read(14, 400 + 5.5 * 4) -- 11 a second of spirit, half of it in the window
    within(10 + I.ALPHA * 1, I.res.spE[1])
    assert.are.equal(0, I.res.regE[1])
end)

it("adds an `mp5` aura's rate in both windows, out of the calibration and out of the read", function()
    shaped({ spirit = 10, mp5 = 2 }, { { aura = "spring", mp5 = 5 } })
    I.AuraModel(1, 3, 10, 300, 1, 10, 0)
    read(10, 500)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess)
    assert.are.same({ 7, 17 }, { VS.Regen(MANA, 12).est, VS.Regen(MANA, 16).est })
    read(14, 400 + 7 * 4)
    assert.are.same({ 2, 10 }, { I.res.regE[1], I.res.spE[1] })
    local api = fake.new()
    I.api = api
    VS.Start(api)
    api.ctl.regen[MANA] = { 18, 8 } -- the client's pair with the aura's 5 inside both: mp5 3, spirit 10
    api.ctl.Tick(105)
    S.RunPolls(105)
    I.Fold(105, false)
    assert.are.same({ 3, 10 }, { I.res.regE[1], I.res.spE[1] })
end)

it("takes no out-of-combat read while a `spirit` or `share` aura is up", function()
    shaped({ spirit = 10, mp5 = 12, share = 0.5 }, { { aura = "surge", spirit = 16, share = 1 } })
    local api = fake.new()
    I.api = api
    VS.Start(api)
    I.AuraModel(1, 1, 100, 130, 1, 100, 0)
    api.ctl.regen[MANA] = { 322, 322 }
    api.ctl.Tick(105)
    S.RunPolls(105)
    I.Fold(105, false)
    assert.are.same({ 12, 10 }, { I.res.regE[1], I.res.spE[1] })
end)

it("allocates nothing with regen auras up over 1000 spends, advances and projections", function()
    shaped({ spirit = 10, mp5 = 12, share = 0.5 },
        { { aura = "surge", spirit = 16, share = 1 }, { aura = "spring", mp5 = 5 }, { aura = "focus", mult = 2 } })
    I.AuraModel(1, 1, 10, 1e6, 1, 10, 0)
    I.AuraModel(1, 3, 10, 1e6, 1, 10, 0)
    local t = 10
    local bytes = alloc.bytes(function()
        t = t + 1
        I.ResourceShift(1, -1, t, Obs.CastSuccess)
        I.Settle(t + 0.5)
        VS.Power(MANA, t + 6)
        VS.Regen(MANA, t + 6)
    end, 1000)
    assert.are.equal(0, bytes)
end)
```

Rewrite the two `casting = true` tests (:1724-1800) to `mult = { { aura = "surge", spirit = 5, share = 1 } }` with their assertions unchanged (50 / 50, 104, 24: c = 0, so M + 5S). In `tests/Forever/druid_spec.lua:767` assert `{ innervate = { aura = "innervate", spirit = 5, share = 1 } }`.

- [ ] **Step 2: Run to verify they fail**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/State/resources_spec.lua tests/Forever/druid_spec.lua`
Expected: FAIL (e.g. the cap test `Passed in: { 12, 12, 22 }`: a `share`-only entry is ignored today; druid_spec's model assertion).

- [ ] **Step 3: Implement**

Resources.lua build: keep an entry when any field is valid (`mult`/`spirit` numbers > 0, `share` in (0, 1], `mp5` > 0; a function `spirit`/`mp5` is evaluated once here with `eval`; Task 2 re-evaluates it); store M.mult/spirit/share/mp5 with the defaults; `R.share[r]` = `eval(fsr.share)` clamped to [0, 1] (0 if not a number); `R.shaped[r]` true for any entry. Replace `scaled`, `castingAt`, `multAt` with:

```lua
-- Slot r's rate at t as multiples of its two learned parts plus a known rate (fa x regE + fb x spE + k): wowsims's
-- (MP5/5 + S x m x min(c + s, 1)) x f inside the window and (MP5/5 + S x m) x f outside (sim/core/mana.go:186-206),
-- from the entries up at t: f and m multiply, s and mp5 add. The spirit regen S is spE / (1 - c), or the mp5 part
-- when the static share c is all of it (shortcut: exact while the slot has no mp5; upgrade if a full-share spec has
-- mp5). A plain slot's fb is 0. Allocates nothing.
local function coefAt(r, t, inside)
    local f, m, s, k = 1, 1, 0, 0
    for i = 1, M.n do
        if M.slot[i] == r then
            local j = M.aura[i]
            if I.auras.applied[1][j] <= t and I.auras.exp0[1][j] > t then
                f, m, s, k = f * M.mult[i], m * M.spirit[i], s + M.share[i], k + M.mp5[i]
            end
        end
    end
    if not R.fsr[r] then
        return f, 0, f * k
    end
    local c = R.share[r]
    local fa, fb, e = 1, 1, m - 1
    if inside then
        fb, e = 0, m * (c + s < 1 and c + s or 1) - c
    end
    if c < 1 then
        fb = fb + e / (1 - c) -- nonzero: c < 1
    else
        fa = fa + e
    end
    return f * fa, f * fb, f * k
end

-- Slot r's regen weights over (from, from + dt]: the integrals of coefAt's fa, fb and k, split at the window's end and
-- at every entry's aura edge inside it (each piece read at its midpoint). The window is the latest one: a bound over
-- a past interval that held an earlier window is approximate. Allocates nothing.
local function spans(r, from, dt)
    if not R.shaped[r] then
        return dt, 0, 0
    end
    local to, a, b, k, t = from + dt, 0, 0, 0, from
    local u = R.fsr[r] and R.fsrUntil[r] or -1
    while t < to do
        local nxt = u > t and u < to and u or to
        for i = 1, M.n do
            if M.slot[i] == r then
                local j = M.aura[i]
                local ap, e = I.auras.applied[1][j], I.auras.exp0[1][j]
                if ap > t and ap < nxt then nxt = ap end
                if e > t and e < nxt then nxt = e end
            end
        end
        local mid = (t + nxt) / 2
        local fa, fb, kk = coefAt(r, mid, mid < u)
        local w = nxt - t
        a, b, k, t = a + fa * w, b + fb * w, k + kk * w, nxt
    end
    return a, b, k
end
```

Every `spans(` caller adds `k` where it adds `regE*a + spE*b` (est, lo and hi alike: OnAdvance, the ladder, :1149, :1196, the Read pin at :1232, VS.Power); OnAdvance also adds `k` to `pinDelta[r]` (a known gain, kept out of the measurement like the aura ticks); ResourceShift's window take-back keeps using `b` only. VS.Regen: `local fa, fb, k = coefAt(r, now, R.fsr[r] and (mode == VS.CASTING or mode == nil and now < R.fsrUntil[r]))`, est/lo/hi = `regE/regL/regH * fa + spE/spL/spH * fb + k`, conf as now. The Read handler: no news for Regen or RegenSpirit while an entry with `spirit ~= 1` or `share > 0` is up at t; else Regen stores `o.b / f - mp5` and RegenSpirit `o.b / f` (f and mp5 the products/sums of the entries up). Header comment :33-42 and the M comment :151-153 describe the four fields. Spec.lua RegisterResource :276 moves an entry out of the regen model when `v.mult or v.spirit or v.share or v.mp5`; replace the doc lines :201-209 with:

```lua
-- A regen entry of rate fields (C3b), `{ aura = key, mult = n, spirit = m, share = s, mp5 = x }`, any of the four,
-- each one of wowsims's mana PseudoStats while the player's aura `key` is up (sim/core/mana.go:186-211): `mult` the
-- whole rate x n (MultiplyManaRegenSpeed; an energy surge); `spirit` the spirit regen x m (DB2 aura 110,
-- SpiritRegenMultiplier); `share` + s of the spirit regen while casting (aura 134, SpiritRegenRateCasting), the total
-- with the `fsr` meta's `share` capped at all of it; `mp5` + x a second in and out of the window (an MP5 aura). On an
-- `fsr` resource the four combine as wowsims does: inside the window (MP5 + S x m x min(c + s, 1)) x f, outside
-- (MP5 + S x m) x f. Rate fields are no forecast event: they move out of the regen model into `state.regenMult` here.
-- `fsr`'s `share` (c, 0-1) is the static casting share the learned split already holds (talents, a pre-buffed armor).
-- shortcut: the sim's forecast takes the belief's regen rate at `now` as a constant (Game/API/Facade.lua's
-- GetPowerRegenForPowerType), so it sees neither a rate aura expire mid-forecast nor a simulated cast apply one;
-- upgrade with a per-forecast multiplier when a pack's pooling misjudges across a rate aura's edge.
```

and add `share` to the `fsr` line (:193). Druid.lua: `innervate = { aura = "innervate", spirit = 5, share = 1 }` (comment: DB2 29166 aura 110 +400%, aura 134 100%).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/State/resources_spec.lua tests/Forever/druid_spec.lua tests/Forever/wowsims_druid_spec.lua`
Expected: PASS. Then `flock /tmp/hekili-gate.lock make check` green. Run the Druid probe (Feral, Balance, Guardian at 0/20/40) on both trees: the lines equal the base's (Innervate's numbers are unchanged at c = 0); any difference is reported with its cause before committing.

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Game/State/Families/Resources.lua src/Hekili/Engine/Schema/Spec.lua src/Hekili_Druid/Druid.lua tests/Game/State/resources_spec.lua tests/Forever/druid_spec.lua
git commit -m "feat(belief): mana regen entries as wowsims's PseudoStats (spirit, share, mp5, the share cap)"
```

### Task 2: Core: function values read at the build and each combat start

**Files:**
- Modify: `src/Hekili/Game/State/Families/Resources.lua` (G :145, build :399-422, CombatStart :1484-1490; a local `refresh()`)
- Modify: `src/Hekili/Engine/Schema/Spec.lua` (doc: values may be functions)
- Modify: `docs/dev/gaps.md` (row AQ: mechanism done)
- Test: `tests/Game/State/resources_spec.lua`

**Interfaces:**
- Consumes: Task 1's M arrays and `R.share`.
- Produces: a rate entry's `spirit` / `mp5`, `fsr.share` and an `auraRegen` entry's `value` may each be a function (no arguments; a regen-model function writes `state.` explicitly, as `last` does; `fsr` functions are setfenv'd to state by Spec.lua). A result that is not a valid number makes the field inert (spirit 1, mp5 0, share 0, value 0). Evaluated at the build and in the `Obs.CombatStart` handler only.

- [ ] **Step 1: Write the failing tests**

```lua
it("re-reads function `spirit`, `mp5` and `share` values at each combat start", function()
    local m, x, c = 2, 5, 0.5
    shaped({ spirit = 10, mp5 = 12, share = function() return c end }, {
        { aura = "surge", spirit = function() return m end },
        { aura = "spring", mp5 = function() return x end },
    })
    I.AuraModel(1, 1, 10, 1e6, 1, 10, 0)
    I.AuraModel(1, 3, 10, 1e6, 1, 10, 0)
    assert.are.equal(22 + 20 + 5, VS.Regen(MANA, 12).est) -- outside: 12 + 10 + (2 - 1) x 20 + 5
    m, x, c = 3, "bad", 0
    obs(Obs.CombatStart, 20, 0, 0, 0)
    I.Fold(20, false)
    assert.are.equal(12 + 10 + 2 * 10, VS.Regen(MANA, 21).est) -- c 0: S = 10; mp5 inert
end)

it("credits a function auraRegen `value`, read at the build and at each combat start", function()
    local v = 7
    boot({ abilities = {}, abilityIds = {}, abilitySlot = {},
        resources = { { key = "mana", type = MANA, token = "MANA", max = 1000, rest = true,
            auraRegen = { { aura = "spring", interval = 2, value = function() return v end } } } },
        auras = { { key = "spring", id = 1023 } }, auraIds = { { 1023 } }, talents = {}, units = { "player", "target" } })
    I.Settle(10)
    read(10, 500)
    I.AuraModel(1, 1, 10, 100, 1, 10, 0)
    within(500 + 7, VS.Power(MANA, 12).est)
    v = 9
    obs(Obs.CombatStart, 12, 0, 0, 0)
    I.Fold(12, false)
    within(500 + 7 + 9, VS.Power(MANA, 14).est)
end)
```

- [ ] **Step 2: Run to verify they fail**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/State/resources_spec.lua`
Expected: FAIL (the first: values frozen at the build; the second: the build drops a function `value`).

- [ ] **Step 3: Implement** a local `refresh()` in Resources.lua that, for every M entry and G entry and every fsr slot, evaluates its function source (kept as `M.spiritDef/M.mp5Def`, `G.def`, `R.shareDef`) into the number arrays, validating as above; call it at the end of the OnBuild handler and first thing in the CombatStart handler. The build accepts `type(e.value) == "number" or "function"`. Spec.lua doc: one sentence that `spirit`, `mp5`, `fsr.share` and an aura regen's `value` may be functions, read at the build and at each combat start. gaps.md row AQ: Status `mechanism done (a value may be a function, mana regen plan Task 2); Improved Bloodrage's declaration open (kit Warrior)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/State/resources_spec.lua` then `flock /tmp/hekili-gate.lock make check`
Expected: PASS; every pack test unchanged (no pack uses a function yet).

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Game/State/Families/Resources.lua src/Hekili/Engine/Schema/Spec.lua docs/dev/gaps.md tests/Game/State/resources_spec.lua
git commit -m "feat(belief): regen values as functions, read at the build and each combat start"
```

### Task 3: Harness world: wowsims's regen rule in W.regenRate

**Files:**
- Modify: `tests/Game/harness/world.lua:54, 466-485, 487-497` (W.fsr shape, W.regenRate, docs)
- Modify: `tests/Game/harness/scenarios.lua:116` (doc)
- Modify: `tests/Forever/helpers/druid_loop_world.lua:33-37` (manaFsr)
- Test: `tests/Game/harness/world_spec.lua`

**Interfaces:**
- Produces: a world `fsr` entry `{ B, A, share = c, mp5 = M, auras = { [auraID] = { spirit = m, share = s, mp5 = x } } }` (B the spirit part, A the casting rate, as today; `share` default 0; `mp5` used only when c >= 1, default 0). While no listed aura is up on `e`, W.regenRate returns exactly today's numbers (A, or A + B; bit-identical). With auras up: S = B / (1 - c) (c < 1) or A - mp5, M = A - c x S (or `mp5`); inside `M + Σx + S x Πm x min(c + Σs, 1)`, outside `M + Σx + S x Πm`; "idle" reads the outside rate, "casting" the inside rate. The old `aura`/`mult` fields are removed.

- [ ] **Step 1: Write the failing tests** in world_spec.lua beside "regenerates an `fsr` pool's spirit part only 5 s after our last cast's spend":

```lua
it("runs wowsims's spirit multiplier and capped casting share while an fsr aura is up", function()
    setup()
    W.startRegen(us, {}, 0.1, nil, { [POOL] = { 10, 12, share = 0.5, auras = { [77] = { spirit = 16, share = 1 } } } })
    assert.are.same({ 22, 12 }, { W.regenRate(us, POOL, "idle"), W.regenRate(us, POOL, "casting") })
    W.applyAura(us, 77, 10)
    assert.are.same({ 322, 322 }, { W.regenRate(us, POOL, "idle"), W.regenRate(us, POOL, "casting") })
end)

it("adds an fsr aura's mp5 in both windows and in the read", function()
    setup()
    W.startRegen(us, {}, 0.1, nil, { [POOL] = { 10, 2, auras = { [78] = { mp5 = 5 } } } })
    W.applyAura(us, 78, 10)
    assert.are.same({ 17, 7 }, { W.regenRate(us, POOL, "idle"), W.regenRate(us, POOL, "casting") })
end)
```

- [ ] **Step 2: Run to verify they fail**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/harness/world_spec.lua`
Expected: FAIL (`{ 22, 12 }` stays with the aura up).

- [ ] **Step 3: Implement** the rule in W.regenRate (the no-aura branch returns `f[2]` / `f[2] + f[1]` as today); druid_loop_world's `manaFsr(spirit)` returns `{ [MANA] = { spirit, 0, auras = { [29166] = { spirit = 5, share = 1 } } } }`; docs updated.

- [ ] **Step 4: Run tests to verify they pass, and the Druid lines are unchanged**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/harness/world_spec.lua tests/Game/harness/replay_spec.lua tests/Forever/druid_spec.lua tests/Forever/wowsims_druid_spec.lua`, then the Druid probe (Feral, Balance at 0/20/40) against the base tree: identical lines (Innervate's world rate is 0 + 22 x 5 x 1 = 110 both ways). Then `flock /tmp/hekili-gate.lock make check`.
Expected: PASS, identical.

- [ ] **Step 5: Commit**

```bash
git add tests/Game/harness/world.lua tests/Game/harness/scenarios.lua tests/Forever/helpers/druid_loop_world.lua tests/Game/harness/world_spec.lua
git commit -m "test(harness): the world's mana regen as wowsims's PseudoStats (spirit, share, mp5)"
```

### Task 4: Shaman: Improved Stormstrike and per-spec seeds

**Files:**
- Modify: `src/Hekili_Shaman/Shaman.lua` (talents :626 area, auras, mana resource :312-318, comment :20)
- Modify: `tests/Forever/helpers/shaman_world.lua` (FSR :25-27, Elemental :329-332, Enhancement's talents and Stormstrike effect :214)
- Modify: `CHANGELOG.md`, `docs/dev/layout.md` (moved lines)
- Test: `tests/Forever/shaman_spec.lua:118`

**Interfaces:**
- Consumes: Task 1's `share` and `fsr.share`; Task 3's world `share`/`auras`.
- Produces: talent `improved_stormstrike = { 2, 1223031, 2 }` (verify tree and placement against the pack's DB2/Forever-only rows; wowsims spell_data_auto_gen.go:238), aura `improved_stormstrike = { id = 1238931, duration = 15, max_stack = 1 }`, mana entry `improved_stormstrike = { aura = "improved_stormstrike", share = 0.5 }` (DB2 1238931 aura 134 = 50).

- [ ] **Step 1: Write the failing test** in shaman_spec.lua (replacing the :118 assertion):

```lua
it("declares mana as wowsims's logs measure it per spec, and Improved Stormstrike's casting share", function()
    local r, e = w.resources[0], ld.env(w)
    local function seed(key)
        e.spec = { [key] = true }
        return { ld.run(r.meta.fsr.spirit, e), ld.run(r.meta.fsr.mp5, e), ld.run(r.meta.fsr.share, e) or 0 }
    end
    assert.are.same({ 12.75, 29.75, 0.15 }, seed("elemental")) -- Mindfulness 3/3: 15% while casting
    assert.are.same({ 28.62, 9.8, 0 }, seed("enhancement"))
    assert.are.same({ aura = "improved_stormstrike", share = 0.5 }, r.models.improved_stormstrike)
    assert.are.same({ 2, 1223031, 2 }, w.talents.improved_stormstrike)
    assert.are.same(1238931, w.auras.improved_stormstrike.id)
end)
```

(Adapt `w.talents`/`w.auras` to the stand-in's field names, as the file's other tests read them.)

- [ ] **Step 2: Run to verify it fails**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/shaman_spec.lua`
Expected: FAIL (`{ 17, 2, 0 }`).

- [ ] **Step 3: Measure the base** (section "Measuring a class": `run.sh /tmp/regen-base Forever.helpers.shaman_world base Enhancement Elemental` and both replays).

- [ ] **Step 4: Implement** the pack: the declarations above; `fsr` functions by `spec.elemental`; the comment above the resource cites wowsims's logs (shaman_elemental 29.75 / 42.5, shaman_enhancement 9.8 / 38.42 a second) and Forever's `6.25 + Spirit/8` for every class, replacing "UNMEASURED: a level 60 Shaman's spirit regen"; :20's "the `fsr` meta has no casting share" now names `fsr.share`. The world: Enhancement `fsr = { 28.62, 9.8, auras = { [1238931] = { share = 0.5 } } }`, Elemental `{ 12.75, 29.75, share = 0.15 }` (was `{ 42.5, 29.75 }`: 42.5 is the log's whole outside rate, not its spirit part); Enhancement's talents gain `[1223031] = 2` and each Stormstrike cast applies aura 1238931 for 15 s (rank 2: 100%, wowsims talents_enhancement.go:188-210). The FSR default comment loses "UNMEASURED".

- [ ] **Step 5: Run and measure**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/shaman_spec.lua tests/Forever/wowsims_shaman_spec.lua`, `run.sh $WT Forever.helpers.shaman_world new Enhancement Elemental`, `flock /tmp/hekili-gate.lock make test-shaman`, `flock /tmp/hekili-gate.lock make check`.
Expected: PASS; the before/after table in the report; floors per Global Constraints; layout.md lines updated; CHANGELOG line ("Enhancement Shamans: mana regen counts Improved Stormstrike, and Shaman mana starts from measured rates").

- [ ] **Step 6: Commit**

```bash
git add src/Hekili_Shaman/Shaman.lua tests/Forever/helpers/shaman_world.lua tests/Forever/shaman_spec.lua CHANGELOG.md docs/dev/layout.md
git commit -m "fix(shaman): Improved Stormstrike's casting share and per-spec mana seeds, as wowsims"
```

### Task 5: Hunter: Resourcefulness, Rapid Recuperation and per-spec seeds

**Files:**
- Modify: `src/Hekili_Hunter/Hunter.lua` (mana resource :202-207, auras, talents :590-630)
- Modify: `tests/Forever/helpers/hunter_world.lua` (FSR :26-27 per pack, Resourcefulness proc, :425)
- Modify: `CHANGELOG.md`, `docs/dev/layout.md`, `docs/dev/gaps.md`
- Test: `tests/Forever/hunter_spec.lua:95`

**Interfaces:**
- Produces: auras `resourcefulness = { id = 1242688, duration = 30, max_stack = 1 }`, `rapid_recuperation = { id = 1242512, duration = 15, max_stack = 1 }`; talent `rapid_recuperation = { <tree>, 1223987, 2 }` (wowsims spell_data_auto_gen.go:401; tree by the pack's rule for rows `wowdb talents HUNTER` lacks); mana entries `resourcefulness = { aura = "resourcefulness", share = 0.5 }` and `rapid_recuperation = { aura = "rapid_recuperation", share = 0.5 }` (shortcut comment: its share is 25/50% on a Serpent Sting hit and 50/100% on spending Rapid Killing by rank, one aura ID for both, talents_marksmanship.go:160-200; 0.5 is the common rank; upgrade if a build's rank or source differs). `fsr` per spec: Beast Mastery `{ 7.94, 7.94, share 0.5 }` (Bestial Discipline), Marksmanship and Survival `{ 15.88, 0 }`.

- [ ] **Step 1: Write the failing test** (hunter_spec.lua, replacing :95), same shape as Task 4's: seeds `{ 7.94, 7.94, 0.5 }` for `beast_mastery`, `{ 15.88, 0, 0 }` for `marksmanship` and `survival`; `r.models.resourcefulness` and `r.models.rapid_recuperation` equal the entries above; the two aura IDs.
- [ ] **Step 2: Run to verify it fails.** `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/hunter_spec.lua`; Expected: FAIL (`{ 15, 2, 0 }`).
- [ ] **Step 3: Measure the base** (Beast Mastery, Marksmanship, Survival; their replays).
- [ ] **Step 4: Implement.** Pack as above; the comment cites the logs (BM 7.94 / 15.88, MM and SV 0 / 15.88) and Forever's formula. World: FSR per pack (`{ 7.94, 7.94, share = 0.5 }`, `{ 15.88, 0, auras = { [1242688] = { share = 0.5 } } }` for MM and SV); a landed melee or ranged ability (not Auto Shot) of a build with Resourcefulness (talent 440529 in its talents) applies aura 1242688 for 30 s when it crits: the world's shots do not roll crits, so roll `W.rng()` against the build's ranged-ability crit rate measured from hunter_survival.log and hunter_marksmanship.log (crits / landed among the shot abilities; write the measurement in the comment). Rapid Recuperation: no world change (no export takes it; the loop worlds are the exports' builds). gaps.md row (next free Id): "Rapid Recuperation's share by source and rank, one aura ID: declared 0.5 | kit (Hunter) | open | a build with it".
- [ ] **Step 5: Run and measure** (`hunter_spec`, `wowsims_hunter_spec`, the probe, `make test-hunter`, `make check`). Expected: PASS; table; floors; layout; CHANGELOG.
- [ ] **Step 6: Commit** `fix(hunter): Resourcefulness and Rapid Recuperation casting shares, per-spec mana seeds, as wowsims`.

### Task 6: Mage: Evocation from the learned rate, per-spec seeds

**Files:**
- Modify: `src/Hekili_Mage/Mage.lua:174-206` (EVOCATION_TICK and the `evocation` model entry removed)
- Modify: `tests/Forever/helpers/mage_world.lua:19-22, 33, 489-500, 514, 552`
- Modify: `CHANGELOG.md`, `docs/dev/layout.md`, `docs/dev/gaps.md`
- Test: `tests/Forever/mage_spec.lua:110-118`

**Interfaces:**
- Produces: mana entry `evocation = { aura = "evocation", spirit = 16, share = 1 }` (DB2 12051: aura 110 +1500%, aura 134 +100%; wowsims evocation.go:11-27); `fsr` per spec: Arcane `{ spirit = 0, mp5 = 29.13, share = 1 }`, Fire (Fire and Frostfire) `{ spirit = 14.57, mp5 = 14.56, share = 0.5 }` (logs: Tag 1 14.56, Tag 2 29.13).

- [ ] **Step 1: Write the failing test** (mage_spec.lua :110-118 replaced): seeds by `spec.arcane` / `spec.fire` as above; `r.models.evocation` equals `{ aura = "evocation", spirit = 16, share = 1 }` (no `interval`, `value` or `last`).
- [ ] **Step 2: Run to verify it fails.** Expected: FAIL (`{ 29.13, 0, 0 }`).
- [ ] **Step 3: Measure the base** (Arcane, Fire, Frostfire; their replays).
- [ ] **Step 4: Implement.** Pack as above; the comment: share 1 for Arcane (Arcane Meditation 50% + Mage Armor 50%), 0.5 for Fire (Mage Armor), "shortcut: Mage Armor assumed up, as every wowsims export pre-buffs it (30 min); a Mage without it has a 0 share and Evocation counts double: upgrade by reading the armor when such a build matters" and a gaps.md row saying the same. The Evocation channel's comment (:515) says its mana is the regen entry. World: `FSR = { SPIRIT * (1 - P.casting), SPIRIT * P.casting, share = P.casting, auras = { [12051] = { spirit = 16, share = 1 } } }`; the Evocation channel keeps its length and ticks with no gain (its mana is the regen now: wowsims credits it at the 0.1 s tick, 466 a second in the logs); comments :19-22 updated.
- [ ] **Step 5: Run and measure** (`mage_spec`, `wowsims_mage_spec`, the probe for Arcane, Fire, Frostfire, `make test-mage`, `make check`). Expected: PASS. Review Focus 4: a regression from the forecast no longer seeing Evocation's mana stops with that named cause.
- [ ] **Step 6: Commit** `fix(mage): Evocation's mana from the learned regen (spirit x 16, all while casting), per-spec seeds`.

### Task 7: Paladin: per-spec seeds and Forever's formula

**Files:**
- Modify: `src/Hekili_Paladin/Paladin.lua:220-226`
- Modify: `tests/Forever/helpers/paladin_world.lua:21, 316` (FSR per pack)
- Modify: `CHANGELOG.md`, `docs/dev/layout.md`
- Test: `tests/Forever/paladin_spec.lua:118`

**Interfaces:**
- Produces: `fsr` per spec: Retribution `{ spirit = 13.65, mp5 = 8.25 }` (Reverence's 30% share inside it), Protection `{ spirit = 17.38, mp5 = 0 }`. No `share` (no rate entry reads it).

- [ ] **Step 1: Failing test** (paladin_spec.lua :118): seeds `{ 13.65, 8.25 }` for `retribution`, `{ 17.38, 0 }` for `protection`. Expected FAIL `{ 17, 2 }`.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Measure the base** (Retribution, Protection; replays).
- [ ] **Step 4: Implement.** Pack seeds by `spec.retribution`; the comment :221-222 replaces "(spirit / 5 + 15) per 2 s tick" with wowsims's logs (Ret 8.25 / 21.9, Prot 0 / 17.38 a second) and Forever's `6.25 + Spirit/8` a second, every class; world FSR per pack with the same numbers.
- [ ] **Step 5: Run and measure** (`paladin_spec`, `wowsims_paladin_spec`, probe, `make test-paladin`, `make check`).
- [ ] **Step 6: Commit** `fix(paladin): per-spec mana seeds from wowsims's logs; Forever's regen formula in the comment`.

### Task 8: Priest: Dark Inspiration, Dark Sacrifice from Spirit, per-spec seeds

**Files:**
- Modify: `src/Hekili_Priest/Priest.lua:181-213`
- Modify: `tests/Forever/helpers/priest_world.lua:155-170, 200-210, 449-453` (fsr, stats, Dark Inspiration's application)
- Modify: `CHANGELOG.md`, `docs/dev/layout.md`
- Test: `tests/Forever/priest_spec.lua:108-112`

**Interfaces:**
- Consumes: Task 2's function values.
- Produces: mana entry `dark_inspiration = { aura = "dark_inspiration", spirit = <fn> }` with `local _, s = state.stat("UnitStat", 5); return s > 0 and 1 + 0.15 * (s / 8) / (6.25 + s / 8) or 1` (Spirit x 1.15: talents_shadow.go:107-118); `dark_sacrifice`'s `value = function() local _, s = state.stat("UnitStat", 5); return 320 + s / 5 end` (DARK_SACRIFICE_TICK removed; `last` kept); `fsr` per spec: Shadow `{ spirit = 14.79, mp5 = 26.88, share = 0.5 }` (without Dark Inspiration: the log's pre-pull casting rate 26.88; Spirit 186.67 from Dark Inspiration's +28.000, so S = 29.58 and B = 0.5 S), Smite (`discipline`) `{ spirit = 20.12, mp5 = 35.73 }`.

- [ ] **Step 1: Failing test** (priest_spec.lua :108-112): seeds per spec as above (fsr functions through `ld.run` with `e.spec`); the regen-model functions read the file's `state` upvalue, the stand-in's `w.state` (as mage_spec.lua:117 sets `w.state.buff`): with `w.state.stat = function() return 0, 187 end`, `r.models.dark_inspiration.spirit()` is within 1e-6 of `1 + 0.15 * 23.375 / 29.625`, and 1 with Spirit 0; `r.models.dark_sacrifice.value()` is `320 + 187 / 5`.
- [ ] **Step 2: Run to verify it fails.** Expected FAIL (`{ 16.62, 28.63 }`).
- [ ] **Step 3: Measure the base** (Shadow, Smite; replays).
- [ ] **Step 4: Implement.** Pack as above; the resource comment explains the Shadow derivation (priest_shadow.log: Tag 1 2.688 a 0.1 s tick pre-pull, 2.863 under Dark Inspiration from 0.01 s; "Dynamic dep enabled (Spirit *= 1.15): +28.000"). World: Shadow `fsr = { 14.79, 26.88, share = 0.5, auras = { [1326168] = { spirit = (29.58 + 3.5) / 29.58 } } }`, `stats = { [5] = 187 }`; Dark Inspiration (1326168, 10 s) applied on us at the pull, at each Mind Blast and at each Mind Flay channel's last tick (the talent at 5/5; check the trigger in talents_shadow.go:107-118); Smite `stats = { [5] = 272 }` (the Dark Sacrifice tick's Spirit, unchanged).
- [ ] **Step 5: Run and measure** (`priest_spec`, `wowsims_priest_spec`, probe Shadow and Smite, `make test-priest`, `make check`).
- [ ] **Step 6: Commit** `fix(priest): Dark Inspiration's Spirit and Dark Sacrifice's Spirit term in mana regen; per-spec seeds`.

### Task 9: Warlock: Fel Energy

**Files:**
- Modify: `src/Hekili_Warlock/Warlock.lua:211-217` (mana resource gains a regen model)
- Modify: `tests/Forever/helpers/warlock_world.lua` (the Voidwalker sacrifice's 18792 aura ticks)
- Modify: `CHANGELOG.md`
- Test: `tests/Forever/warlock_spec.lua:148-152`

**Interfaces:**
- Produces: mana regen entry `fel_energy = { aura = "fel_energy", interval = 4, value = function() return 0.02 * state.mana.max end, last = <app + 4 x floor((query_time - app) / 4)> }` (DB2 18792: aura 21, 2 every 4000 ms; talents_demonology.go:168-185 for the first tick's time).

- [ ] **Step 1: Failing test:** with `w.state.mana = { max = 5353 }` (the file's `state` upvalue, as mage_spec.lua:117), `r.models.fel_energy.value()` = 107.06, interval 4, aura `fel_energy`; `last` at `w.state.query_time = 13.4` and `w.state.buff.fel_energy = { applied = 5.2 }` is 9.2.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Measure the base** (the five Warlock labels; replays).
- [ ] **Step 4: Implement** the entry; the world ticks 2% of the pool every 4 s while 18792 is up on us (the press `aura.tick` shape or a W.at loop as the world's other ticking auras).
- [ ] **Step 5: Run and measure** (`warlock_spec`, `wowsims_warlock_spec`, probe, `make test-warlock`, `make check`). No export sacrifices the Voidwalker: the lines should not move; a moved line is a finding.
- [ ] **Step 6: Commit** `fix(warlock): Fel Energy's mana (2% of max every 4 s)`.

### Task 10: Core and harness: a paid channel holds the casting rate to its end

**Files:**
- Modify: `src/Hekili/Game/State/Families/Resources.lua` (ResourceShift :1548-1563; Channel handlers; `R.fsrFrom`)
- Modify: `src/Hekili/Engine/Sim/State.lua:1448` (resourceChange)
- Modify: `tests/Game/harness/world.lua` (W.regenRate's window; the channel's paid flag at W.press)
- Test: `tests/Game/State/resources_spec.lua`, `tests/Game/harness/fsr_forecast_spec.lua`, `tests/Game/harness/world_spec.lua`

**Interfaces:**
- Consumes: `I.channel`, `I.castAb`, `I.castEnd` (Families/Casts.lua:183-229); the sim's `buff.casting` (v3 == 1: a channel).
- Produces: the belief's window `fsrUntil[r] = max(spend + 5, channel end)` for a spend made by the channel in progress (either event order: a spend within I.GAIN_SHOWS of the ChannelStart's start); ChannelUpdate moves it to `max(fsrFrom + 5, new end)`, ChannelStop to `max(fsrFrom + 5, stop time)`; VS.FsrUntil reports it. The sim: a spend while a channel runs sets `fsr_until = max(query_time + VS.FSR, buff.casting.expires)`.

- [ ] **Step 1: Failing tests.**

```lua
-- resources_spec.lua (five-second rule describe)
it("holds the window to a paid channel's end, either event order, and to its stop when clipped", function()
    I.ResourceShift(1, -100, 10, Obs.CastSuccess)
    obs(Obs.ChannelStart, 10, 1, 18, 0) -- an 8 s channel from 10 (a = ability index 1, b = its end)
    I.Fold(10, false)
    assert.are.equal(18, VS.FsrUntil(MANA))
    obs(Obs.ChannelStop, 16, 1, 0, 0)
    I.Fold(16, false)
    assert.are.equal(16, VS.FsrUntil(MANA))
    obs(Obs.ChannelStart, 30, 1, 38, 0)
    I.Fold(30, false)
    I.ResourceShift(1, -100, 30, Obs.CastSuccess) -- the spend after the start
    assert.are.equal(38, VS.FsrUntil(MANA))
    obs(Obs.ChannelStart, 50, 1, 58, 0) -- a free channel: no spend
    I.Fold(50, false)
    assert.are.equal(38, VS.FsrUntil(MANA))
end)
```

(Give the describe's boot one channel ability if the Channel handlers need it; match the Obs payload to Families/Casts.lua.) In fsr_forecast_spec.lua: with a channel's `casting` buff applied for 8 s at now (`v3 = 1`), `S.spend(100, "mana")` sets `r.fsr_until == 108`. In world_spec.lua: a paid 8 s channel press (W.press with `channel = { length = 8, tick = 1 }` and a cost in POOL) keeps `W.regenRate(us, POOL)` at the casting rate at 6.5 s and returns the full rate after 8 s; a clipped one at 6 s returns to the 5 s rule.

- [ ] **Step 2: Run to verify they fail.** Expected FAIL (window 15; fsr_until 105; world full rate at 6.5 s).
- [ ] **Step 3: Measure the base** for every class whose worlds cast a paid channel over 5 s: the five Warlock labels (Drain Soul 15 s, Rain of Fire 8 s, Hellfire 15 s) and Mage (Blizzard); Druid, Hunter and Priest by `make test-<class>` only.
- [ ] **Step 4: Implement** as the Interfaces say (Resources.lua keeps `R.fsrFrom[r]` at each spend and a held flag; the window take-back uses the extended end; State.lua reads `state.buff.casting` only where `fsr_until` exists; the world records at the press whether a channel's cost was paid in `pt`).
- [ ] **Step 5: Run and measure** (`resources_spec`, `fsr_forecast_spec`, `world_spec`, the probes, `make test-warlock`, `make test-mage`, `make test-druid`, `make test-hunter`, `make test-priest`, `make check`).
- [ ] **Step 6: Commit** `fix(belief,sim): a paid channel holds the five-second rule's casting rate to its end (wowsims)`.

### Task 11: Shaman: Mana Spring Totem's mp5

**Files:**
- Modify: `src/Hekili_Shaman/Shaman.lua` (aura, mana entry, seeds' mp5)
- Modify: `tests/Forever/helpers/shaman_world.lua` (base mp5 without the totem, the buff aura while the water totem stands)
- Modify: `docs/dev/ingame-ledger.md`, `CHANGELOG.md`, `docs/dev/layout.md`
- Test: `tests/Forever/shaman_spec.lua`

**Interfaces:**
- Produces: aura `mana_spring = { id = 10494, copy = { 5677, 10491, 10493 }, ... }` (the totem's buff on us, ranks 1-4: DB2 aura 24, 4/6/8/10 every 2000 ms); mana entry `mana_spring = { aura = "mana_spring", mp5 = <fn> }` returning `MANA_SPRING[knownRank(mana spring totem ids)] / 2 * (1 + 0.05 * state.talent.restorative_totems.rank)` (Restorative Totems 16187: +5% a rank; wowsims totems.go:105-109 models it as MP5). Seeds' mp5 without the totem: Elemental 24.75, Enhancement 4.8 (the logs' casting rate before the totem's buff: shaman_elemental.log 2.475 a tick before -2.0 s, shaman_enhancement.log 0.480 before -5.0 s).

- [ ] **Step 1: Failing test:** the seeds `{ 12.75, 24.75, 0.15 }` and `{ 28.62, 4.8, 0 }`; through `w.state` (Task 8's note), with the top rank known and Restorative Totems 0 the entry's `mp5()` is 5, with rank 5 it is 6.25.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Measure the base** (Enhancement, Elemental; replays).
- [ ] **Step 4: Implement.** Pack as above. World: Elemental `{ 12.75, 24.75, share = 0.15, auras = { [10494] = { mp5 = 5 } } }`, Enhancement `{ 28.62, 4.8, auras = { [1238931] = { share = 0.5 }, [10494] = { mp5 = 5 } } }`; summoning the Mana Spring Totem applies 10494 on us for the totem's life, and a replaced or expired water totem removes it. Ledger row: "GetPowerRegenForPowerType with Mana Spring Totem's buff up: does the casting return include its 5 a second (wowsims models it as MP5; the belief subtracts it from the read)?".
- [ ] **Step 5: Run and measure** (`shaman_spec`, `wowsims_shaman_spec`, probe, `make test-shaman`, `make check`).
- [ ] **Step 6: Commit** `fix(shaman): Mana Spring Totem's mp5 while its buff is up, as wowsims`.

### Task 12: Druid: Serenity Field's Spirit; gaps rows for the rest

**Files:**
- Modify: `src/Hekili_Druid/Druid.lua` (aura, mana entry)
- Modify: `tests/Forever/helpers/druid_loop_world.lua` (Balance and Feral `stats`: the replay's Spirit read)
- Modify: `docs/dev/gaps.md`, `CHANGELOG.md`
- Test: `tests/Forever/druid_spec.lua`

**Interfaces:**
- Produces: aura `serenity = { id = 1291103, duration = 15, max_stack = 1 }` (the Serenity Field trinket's buff, item 272439: DB2 aura 29 Spirit +72; stat_bonus_cds_auto_gen.go:365); mana entry `serenity = { aura = "serenity", spirit = <fn> }` returning `s > 0 and 1 + 9 / (6.25 + s / 8) or 1` (72 Spirit = 9 a second).

- [ ] **Step 1: Failing test:** with `w.state.stat` answering Spirit 126 (as Task 8), the entry's `spirit()` is `1 + 9 / 22` (druid_balance.log: Tag 2 22.0 -> 31.0 over 114.9-126 s), with Spirit 0 it is 1.
- [ ] **Step 2: Run to verify it fails.**
- [ ] **Step 3: Measure the base** (Balance replay; Feral, Balance loops).
- [ ] **Step 4: Implement.** Pack as above (comment: an item's buff any Druid may wear; other classes' packs: gaps row). World: Balance `stats = { [5] = 126 }`, Feral `{ [5] = 124 }` (S = 6.25 + Spirit/8: 22.0 and 21.75). gaps.md rows (next free Ids): Serenity Field on the other mana classes (kit, open: declare it in each pack, or a shared item regen hook like Task 13's race one); a Resto Druid's Reflection share undeclared (`fsr.share`; Innervate counts c x S high) (kit Druid, open, no Resto pack).
- [ ] **Step 5: Run and measure** (`druid_spec`, `wowsims_druid_spec`, probe, `make test-druid`, `make check`).
- [ ] **Step 6: Commit** `fix(druid): Serenity Field's Spirit in mana regen; gaps for the other wearers`.

### Task 13: Core: a race's regen entries, and a race matched by its race ID

**Files:**
- Modify: `src/Hekili/Engine/Schema/Races.lua` (header :1-13; `mods` :18; new `Race:RegisterRegenMod` after `Race:RegisterCostMod` :87-91; `Hekili:NewRace` :93-95)
- Modify: `src/Hekili/Game/State/Adapter.lua:293-297` (the race block)
- Modify: `src/Hekili/Engine/Sim/State.lua:549-554` (`state.race_id`)
- Modify: `tests/Forever/helpers/engine.lua:219-235` (the NewRace wrapper forwards the race ID), `tests/boundary_lib.lua:254` (the NewRace pattern)
- Test: `tests/Game/State/races_spec.lua` (:99 and a new test), `tests/Game/State/modifiers_spec.lua` (a new test), `tests/Game/State/resources_spec.lua` (a pin in the five-second rule describe), `tests/Forever/races_spec.lua:128, :194` (`regenMods = {}`)

**Interfaces:**
- Consumes: Task 1's entry vocabulary (`mult`, `spirit`, `share`, `mp5`) and its build (Resources.lua keeps an entry whose aura key is in `def.auras`).
- Produces: `race:RegisterRegenMod({ resource = key, aura = key, mult = n | spirit = m | share = s | mp5 = x })`, appended to `ns.raceMods.regenMods` only when the race is live; Adapter.lua appends each to the built `d.mult` of the resource whose key is `resource` (a fresh list per build: the class's `r.state.regenMult` is never written); `Hekili:NewRace(token, raceID)`: live when `state.race_token == token` or `raceID` equals `state.race_id` (UnitRace's third return; Facade.lua:990 passes UnitRace through, its third return `raceID: number` per the Forever API). Nothing on the sim side: the forecast reads the belief's rate (Spec.lua's shortcut, Task 1).

Why the race ID: no Skyborne character has been probed, so their UnitRace tokens are unknown (races spec 2026-10-15 §1: "a wrong token makes a file silently inert"); the race ID is not a guess's single point of failure (wowsims tools/database/dbc/util.go:44-45: ChrRaces 95 High Order, 96 Windshaper; our DB2 has no ChrRaces table, so ledger SK1 confirms both).

- [ ] **Step 1: Write the failing tests**

`tests/Game/State/races_spec.lua`: at :99 expect `{ maxMods = {}, costMods = {}, regenMods = {} }`; in `load` add `race:RegisterRegenMod({ resource = "pool_a", aura = "racial_a", mult = 2 })` after the cost modifier; in "registers its abilities, auras and modifiers..." (:103) add `assert.are.same({ { resource = "pool_a", aura = "racial_a", mult = 2 } }, ns.raceMods.regenMods)`; and:

```lua
it("goes live by race ID (UnitRace's third return) whatever the token, and only for that ID", function()
    load("Other")
    state.race_id = 95
    local race = hekili:NewRace("Unconfirmed", 95)
    race:RegisterRegenMod({ resource = "pool_a", aura = "racial_a", mult = 2 })
    race:RegisterRegenMod({ aura = "racial_a", mult = 2 }) -- no resource key: dropped
    assert.is_true(race.live)
    assert.are.same({ { resource = "pool_a", aura = "racial_a", mult = 2 } }, ns.raceMods.regenMods)
    assert.is_false(hekili:NewRace("Unconfirmed", 96).live) -- another race's ID
    assert.is_false(hekili:NewRace("Unconfirmed").live) -- no ID, another token
end)
```

`tests/Game/State/modifiers_spec.lua`:

```lua
it("adds a race's regen entry to its named resource only, once per build, the class's list untouched", function()
    h.Class.auras.mod_aura_b = { key = "mod_aura_b", id = 1032, duration = 30 }
    ns.raceMods.regenMods = {
        { resource = "rage", aura = "mod_aura_b", mult = 2 },
        { resource = "mana", aura = "mod_aura_b", mult = 2 }, -- the class has no mana: inert
    }
    VS.SpecChanged()
    VS.SpecChanged() -- a rebuild adds it once
    local R = I.res
    local M = R.regenMult
    assert.are.same({ 1, R.slotOfToken.RAGE, 2 }, { M.n, M.slot[1], M.mult[1] })
    assert.is_nil(h.Class.resources.rage.state.regenMult)
end)
```

`tests/Game/State/resources_spec.lua` (five-second rule describe, beside Task 1's tests; a pin of Task 1's `mult` on an `fsr` slot, the shape Energized takes: green on Task 1's code):

```lua
it("doubles the whole rate in and out of the window under a `mult` entry, out of the calibration", function()
    shaped({ spirit = 10, mp5 = 12, share = 0.5 }, { { aura = "surge", mult = 2 } })
    read(10, 500)
    I.ResourceShift(1, -100, 10, Obs.CastSuccess) -- the window to 15
    I.AuraModel(1, 1, 10, 40, 1, 10, 0) -- surge up 10 to 40
    -- inside (M + c x S) x 2 = (2 + 10) x 2, outside (M + S) x 2 = 22 x 2 (wowsims mana.go:186-211)
    assert.are.same({ 24, 44 }, { VS.Regen(MANA, 12).est, VS.Regen(MANA, 16).est })
    read(20, 400 + 5 * 24 + 5 * 44) -- the model's own answer: no news for either part
    within(12, I.res.regE[1])
    within(10, I.res.spE[1])
end)
```

`tests/Forever/races_spec.lua:128, :194`: expect `{ maxMods = {}, costMods = {}, regenMods = {} }`.

- [ ] **Step 2: Run to verify they fail**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Game/State/races_spec.lua tests/Game/State/modifiers_spec.lua tests/Game/State/resources_spec.lua tests/Forever/races_spec.lua`
Expected: FAIL (`RegisterRegenMod` is nil; `ns.raceMods` lacks `regenMods`; the modifiers test's `M.n` is 0). The resources pin passes (Task 1's code).

- [ ] **Step 3: Implement**

Races.lua: `local mods = { maxMods = {}, costMods = {}, regenMods = {} }`; after `Race:RegisterCostMod`:

```lua
--- { resource = key, aura = key, mult = n | spirit = m | share = s | mp5 = x }: a regen entry (Engine/Schema/Spec.lua's
--- rate fields) on the class's resource `resource` while the player's aura `aura` is up; a class without that resource
--- ignores it (Adapter.lua). The belief's only: the sim's forecast reads the belief's rate.
function Race:RegisterRegenMod(def)
    if self.live and type(def.resource) == "string" and type(def.aura) == "string" then
        mods.regenMods[#mods.regenMods + 1] = def
    end
end
```

and

```lua
--- `raceID` (optional): UnitRace's third return, for a race whose token is unconfirmed; either match makes it live.
function Hekili:NewRace(token, raceID)
    local s = Hekili.State
    local live = s.race_token == token or (raceID ~= nil and rawget(s, "race_id") == raceID) -- rawget: a strict state
    return setmetatable({ token = token, live = live }, Race)
end
```

The header comment names RegisterRegenMod and the race ID. State.lua:552: `raceName, state.race_token, state.race_id = Facade.UnitRace( "player" )` (comment: the race ID, for a race file whose token is unconfirmed). Adapter.lua, inside `if race then` after the maxMods line:

```lua
            -- the race's regen entries on this resource (Races.lua RegisterRegenMod), after the class's: a fresh list,
            -- so a rebuild never appends to the class's own `regenMult`
            for _, e in ipairs(race.regenMods or {}) do
                if e.resource == k then
                    if d.mult == (r.state and r.state.regenMult) then
                        d.mult = { unpack(d.mult or {}) }
                    end
                    insert(d.mult, e)
                end
            end
```

(build time only, once per SpecChanged: no recurring path.) engine.lua's wrapper: `v = function(self, token, ...)` and `local race = newRace(self, token, ...)`. boundary_lib.lua:254: `read(file):match('NewRace%("(%w+)"')` (a second argument no longer hides the token).

- [ ] **Step 4: Run tests to verify they pass**

Run: the Step 2 command, then `flock /tmp/hekili-gate.lock .lua/bin/busted tests/boundary_spec.lua tests/Forever/wowsims_levels_spec.lua`, then `flock /tmp/hekili-gate.lock make check`.
Expected: PASS; no pack line moves (no race declares a regen entry yet).

- [ ] **Step 5: Commit**

```bash
git add src/Hekili/Engine/Schema/Races.lua src/Hekili/Game/State/Adapter.lua src/Hekili/Engine/Sim/State.lua tests/Forever/helpers/engine.lua tests/boundary_lib.lua tests/Game/State/races_spec.lua tests/Game/State/modifiers_spec.lua tests/Game/State/resources_spec.lua tests/Forever/races_spec.lua
git commit -m "feat(races): a race's regen entries on a named resource, and a race matched by its race ID"
```

### Task 14: Shared: the High Order Skyborne's Read Ley Line and Energized

**Files:**
- Create: `src/Hekili_Shared/Races/HighOrderSkyborne.lua`
- Modify: `src/Hekili_Shared/Hekili_Shared.toc` (after `Races\Undead.lua`)
- Modify: `tools/wowsims/specs/mage_arcane.lua:37` (comment), regenerated `src/Hekili_Mage/APLs/{Arcane,Fire,Frostfire} (wowsims.com).simc` and `src/Hekili_Mage/Mage.lua`'s RegisterPack blocks
- Modify: `docs/dev/layout.md:616`, `docs/dev/gaps.md` (two rows), `docs/dev/ingame-ledger.md` (row SK1), `CHANGELOG.md`
- Test: `tests/Forever/races_spec.lua` (`OWN` :27-36, `load` :52-62, a new test)

**Interfaces:**
- Consumes: Task 13's `race:RegisterRegenMod` and `Hekili:NewRace(token, raceID)`; Task 1's `mult`.
- Produces: race file `Hekili:NewRace("HighOrderSkyborne", 95)` (the token is wowsims's enum name without "Race", as tests/Forever/helpers/wowsims.lua:41-45 maps a request's race, so a future Skyborne export goes live in the harness unchanged; unconfirmed in game, the ID decides); ability `read_ley_line` (1259705: `cast = 2`, `cooldown = 120`, `gcd = "spell"`, `startsCombat = false`, `toggle = "cooldowns"` as Innervate's, `handler`/`now` apply `energized`); aura `energized` (1270842, `duration = 30`, `max_stack = 1`); `race:RegisterRegenMod({ resource = "mana", aura = "energized", mult = 2 })`.
- Facts (checked): DB2 1259705 "Read Ley Line" 2000 ms cast, 120000 ms cooldown, GCD 1500, skill line "Skyborne Racial", SkillLineAbility 55323 RaceMasks_1 = 1 (bit 32: High Order only; Skysight 1259686 has 2, Walk on Air, Wind Blessed and Elemental Insight 3); effect 0 triggers 1270842. wowsims: racials.go:204-241 (High Order: Energized 1270842 30 s, MultiplyManaRegenSpeed(2) when `HasManaBar`; the spell 2.0 s cast, GCD, 2 min, SpellFlagAPL), :242-277 (Windshaper: Skysight 1259686 0.5 s -> Elemental Blessing 1259688, +10% movement speed 30 s, 2 min; no mana), :279-284 (both: Wind Blessed +3% attack and cast speed, Elemental slaying +5% damage and crit damage); ui/sim/proto/utils.ts:62, 69 (High Order Alliance, Windshaper Horde); character_constants.go:110-185 (High Order: Warrior, Hunter, Rogue, Mage, Druid; Windshaper: Warrior, Hunter, Rogue, Shaman, Druid). The mana users that can be High Order: Hunter, Mage, Druid. Review Focus 7: the DB2 disagrees on the duration and the field.
- Not built (a review should not flag them): a Windshaper file (Skysight is a movement utility, which race files leave out like Find Treasure: races spec 2026-10-15 §5 "Utility actives"; its passives are the shared ones below); Wind Blessed's haste (the race API carries no stat modifier and needs none: Hekili reads haste from the client) and Elemental Insight (no damage model, as Beast Slaying): one gaps row; Energized's 900 s ley-line variant (1259691, same effects; not Read Ley Line's trigger in the DB2, wowsims models none): the other gaps row; a harness world (no checked-in export is Skyborne: tests/Forever/wowsims/*.json races are Human, NightElf, Orc, Troll, Undead).

- [ ] **Step 1: Write the failing tests** in `tests/Forever/races_spec.lua`: `OWN` gains `HighOrderSkyborne = { { "read_ley_line" }, 0, 0 }`; `load`'s state gains `race_id = type(token) == "number" and token or nil` (a number loads by race ID alone); and:

```lua
it("registers Read Ley Line, Energized and its mana regen entry for the High Order Skyborne only", function()
    for _, who in ipairs({ "HighOrderSkyborne", 95 }) do -- by token, and by race ID alone (an unconfirmed token)
        load(who)
        local rll = all.abilities.read_ley_line
        assert.are.same(
            { 1259705, 2, 120, "spell", "cooldowns", false },
            { rll.id, rll.cast, rll.cooldown, rll.gcd, rll.toggle, rll.startsCombat },
            tostring(who)
        )
        assert.is_function(rll.now)
        assert.are_not.equal(rll.handler, rll.now)
        assert.are.same({ 1270842, 30, 1 }, { all.auras.energized.id, all.auras.energized.duration, all.auras.energized.max_stack })
        assert.are.same({ { resource = "mana", aura = "energized", mult = 2 } }, ns.raceMods.regenMods)
    end
    -- one faction's: the Windshaper Skyborne (Horde, race ID 96) and the Classic races get neither the racial nor the regen
    for _, other in ipairs({ 96, "WindshaperSkyborne", "Orc", "NightElf", "Human" }) do
        load(other)
        local rll = all.abilities.read_ley_line
        assert.are.same({ false, true }, { rll.known, rll.unlisted }, tostring(other))
        assert.are.same({}, ns.raceMods.regenMods, tostring(other))
    end
end)
```

- [ ] **Step 2: Run to verify it fails**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/races_spec.lua`
Expected: FAIL (no `read_ley_line`; "every race file is in Hekili_Shared.toc" fails on the `OWN` row).

- [ ] **Step 3: Energized's numbers are wowsims's** (Review Focus 7; owner ruling 2026-10-26 "follow wowsims"): 30 s and whole-rate `mult = 2`. Put the ruling and the DB2 disagreement (15 s, aura 110 spirit-only) in the race file's comment; nothing to ask.

- [ ] **Step 4: Measure the base** (Mage: Arcane, Fire, Frostfire loops and their replays, section "Measuring a class"): the next step changes the Mage packs' generated lines.

- [ ] **Step 5: Implement.** `src/Hekili_Shared/Races/HighOrderSkyborne.lua`:

```lua
-- Hekili_Shared/Races/HighOrderSkyborne.lua
-- The High Order Skyborne (Alliance; ChrRaces 95: wowsims tools/database/dbc/util.go:44-52, ui/sim/proto/utils.ts:62),
-- one of Forever's two Skyborne races (skill line 2980; the Windshaper, Horde, 96, has no file: its Skysight is a
-- movement utility). Its Forever racial (DB2 1.60.1.70338, SkillLineAbility 55323: RaceMasks_1 bit 32 only): Read Ley
-- Line (1259705: 2 s cast, on the GCD, 120 s), which grants Energized (1270842): on a mana user wowsims doubles the
-- whole mana regen, mp5 and spirit (MultiplyManaRegenSpeed(2)), for 30 s (sim/core/racials.go:204-241). The DB2 says
-- 15 s and +100% spirit regen (aura 110) and health regen (aura 88): wowsims followed (owner ruling, ledger SK1).
-- Shared passives (both Skyborne races): Wind Blessed (1259710; wowsims +3% attack and cast speed: the client's haste,
-- Hekili reads it) and Elemental Insight (1259707: +5% damage vs Elementals; no damage model). No resource maximum or
-- cost modifier. The UnitRace token is unconfirmed: the race ID decides (Engine/Schema/Races.lua).

local race = Hekili:NewRace("HighOrderSkyborne", 95)

race:RegisterAbility("read_ley_line", {
    id = 1259705,
    cast = 2,
    cooldown = 120,
    gcd = "spell",
    startsCombat = false,
    toggle = "cooldowns",

    handler = function()
        applyBuff("energized")
    end,
    -- The belief's now-state of the cast (event-facade spec §12a)
    now = function()
        applyBuff("energized")
    end,
})

race:RegisterAura("energized", {
    id = 1270842,
    duration = 30, -- wowsims racials.go:210; the DB2's SpellMisc says 15 s (DurationIndex 8)
    max_stack = 1,
})

-- the whole mana regen x 2 while Energized is up; a class with no mana resource (Warrior, Rogue) ignores it
race:RegisterRegenMod({ resource = "mana", aura = "energized", mult = 2 })
```

Hekili_Shared.toc: `Races\HighOrderSkyborne.lua` after `Races\Undead.lua`. Regenerate the packs: `flock /tmp/hekili-gate.lock make wowsims-packs packs`. Expected diff: the three Mage `.simc` files lose `# Omitted: default #2: spell 1259705` and `# Omitted: evocation #1: spell 1259705` and gain the two `read_ley_line` lines (wowsims's arcane.apl.json:5 reads `spellIsKnown(1259705) and auraIsActive(Innervate, tag -1)`: an external aura is nil, dropped by rule 6, so default #2 may emit unconditioned, as wowsims casts it; :13 the Evocation group's `!buff.energized.up`), and Mage.lua's RegisterPack blocks follow. Record the emitted lines in the report. mage_arcane.lua:37: "Read Ley Line (1259705) and its Energized (1270842) resolve to the High Order Skyborne race file; the Human the UI defaults to never knows it". layout.md:616: replace "Read Ley Line (a Skyborne racial) dropped (rule 12: no Skyborne race pack)" with "Read Ley Line a High Order Skyborne racial (unknown for the exports' Human)". gaps.md (next free Ids): "Energized's 900 s ley-line variant (1259691, the same aura 110/88 effects, not Read Ley Line's DB2 trigger) unmodelled; Energized declared as wowsims (x2 whole rate, 30 s) against the DB2 (15 s, aura 110: spirit only) | kit (race) | open | ledger SK1" and "Skyborne passives: Wind Blessed (1259710, wowsims +3% attack and cast speed; the DB2's base 1) is the client's haste, no race stat modifier; Elemental Insight (1259707, +5% damage and crit damage vs Elementals) unmodelled, as Beast Slaying (no damage model) | kit (race) | won't fix | -". ingame-ledger.md row SK1 (Every class): "a High Order Skyborne character (after launch, 2026-11-04): `/run VSCopy(UnitRace("player"))` (token and race ID: 95?), and under Energized after Read Ley Line: its duration (15 or 30 s), and GetPowerRegenForPowerType's two returns before and during it (both doubled, as wowsims, or the spirit part only, as the DB2's aura 110); in Cat or Bear Form, does the cast leave the form? | the race file goes live by ID; Energized's declared numbers follow wowsims over the DB2 | open". CHANGELOG under Unreleased: "High Order Skyborne Hunters, Mages and Druids: Read Ley Line is tracked and recommended where the wowsims priorities cast it (the Mage's), and Energized's doubled mana regen counts in the predicted mana. The Windshaper Skyborne get neither."

- [ ] **Step 6: Run and measure**

Run: `flock /tmp/hekili-gate.lock .lua/bin/busted tests/Forever/races_spec.lua tests/Forever/wowsims_levels_spec.lua tests/Forever/wowsims_mage_spec.lua tests/boundary_spec.lua`, `run.sh $WT Forever.helpers.mage_world new Arcane Fire Frostfire`, `flock /tmp/hekili-gate.lock make test-mage`, `flock /tmp/hekili-gate.lock make check`.
Expected: PASS; every Mage line and replay identical to the base (the exports' Human never knows Read Ley Line); a moved line is a finding (stop and report its cause). The levels spec's "every wowsims pack line guarded" passes on the new lines.

- [ ] **Step 7: Commit**

```bash
git add src/Hekili_Shared/Races/HighOrderSkyborne.lua src/Hekili_Shared/Hekili_Shared.toc tools/wowsims/specs/mage_arcane.lua src/Hekili_Mage tests/Forever/races_spec.lua docs/dev/layout.md docs/dev/gaps.md docs/dev/ingame-ledger.md CHANGELOG.md
git commit -m "feat(races): the High Order Skyborne's Read Ley Line, and Energized's x2 mana regen (wowsims), one faction only"
```

### Task 15: The whole gate

**Files:**
- Modify: `docs/dev/layout.md` (any line not yet updated)

- [ ] **Step 1:** `make gate` (it takes the lock). Expected: PASS. A failing floor stops with its line and named cause.
- [ ] **Step 2:** Diff docs/dev/layout.md's pack lines against the gate's output; update any stale line.
- [ ] **Step 3: Commit** (only if layout.md changed) `docs(layout): pack lines after the mana regen plan`.
