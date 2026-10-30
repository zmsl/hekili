# Modern Display, Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in, experimental per-display toggle, "Modern (game truth)", that leaves the display on its own style
(Classic or Timeline) with every setting where it is and paints three plain-or-display-only truths over Hekili's
picks: the game's real cooldown swipe, an event-driven "not yet" dim from the game's usability answer, and a proc
mark from the game's overlay glow on the next and focus icons only.

**Architecture:** Modern is a core layer, not a style (spec §5.1, decision M2, owner 2026-10-29). A core display
field `displays[id].truth` (`enabled` off by default, plus the overlay toggles) has its own core "Modern" tab on
every style. When it is on, `UI/UI.lua` attaches the truth layer `UI/Truth.lua` to the buttons the bound style's
`Build` returned and calls `Truth.Tick` / `Draw` / `OnGameEvent` / `Clear` right after the style's own; when it is
off, nothing of Truth runs. Truth sees a button only through an optional button contract (`b.recIndex`, `b.isFocus`,
`b.Cooldown`, `b.round`; `UI/Styles.lua`), which Classic and Timeline set in a few lines each with no change to how
they draw. Truth is the only file that reads the new fourth facade class `Facade.Display` (raw calls whose answers
go to a widget only), and reads no style's subtable.

**Tech Stack:** Lua 5.1 (WoW, Forever 1.60.1), busted, luacheck, StyLua, the headless harness
(`tests/Game/harness/headless.lua`), LibCustomGlow-1.0, AceConfig (options), AceLocale (`L[...]`).

**Spec:** `docs/superpowers/specs/2026-10-29-modern-display-design.md` (APPROVED 2026-10-29, revised the same day to
the layer design; §9 answers binding, answer 3 superseded by §5.1; rulings R3 / M11, §7.1 / M10, M12).
Research: `docs/research/2026-10-29-modern-display-api.md`. Executors read both. Line numbers below are as of
`forever-modern-research` 3d334aab6.

## Scope

Phase 1 only (spec §2, §9 answer 8): true cooldown swipes, the usability edge, proc confirmation from usability and
the overlay glow. Not built (YAGNI, phases 2-3): truth bars, the execute border, the Timeline ride and its contract
fields, the Cooldown Manager field, curves, `UnitPower` / `UnitHealthPercent` / `GetSpellChargeDuration` rows, the
`execute` and `ride` options, the Developer header, following Timeline's `oocTimers` (open owner question, spec §9
answer 3). `Truth.VERIFIED` exists with every key false and nothing reads it but its test.

## Rulings on the spec (this plan's; recorded in architecture §7 by Task 3)

The first plan's rulings 1 (the base's option tabs) and 2 (the base's shared groups) are moot under the layer design:
there is no `base`, the display's own style keeps its own tabs and groups, and `Engine.StyleGroup` and `optionConf`
are untouched. The rest are kept, renumbered:

1. **Proc confirmation from usability.** Spec §2 and §5.2 read route 2 from `r.usable`, but Resolve keeps only
   `IsSpellUsable`'s second return (`insufficientPower`, `UI/Resolve.lua:94-96`), and a proc that gates usability
   (research §2.6 route 2) flips the first (`isUsable`). Ruling: Truth asks `C_Spell.IsSpellUsable` (a plain
   passthrough, `Facade.lua:908`) itself, on `SPELL_UPDATE_USABLE` and on a button's spell change, and the edge dims
   on `not isUsable` (short of resource, or an unmet proc or condition). Usability confirms a proc as the absence of
   that dim (dim, never promote: no pack fact says which abilities are proc-gated, so no usability-only mark). The
   confirm mark is the overlay glow (route 3, `r.glow`), on the next and focus icons only (R3), and never on a dimmed
   icon.
2. **`Output.Acted` "through a getter".** No getter exists (`acts` is local, `Engine/Output.lua:101-109`), but every
   publish copies it to the display's `out.acts` (`Engine/Output.lua:203`). Ruling: Truth reads `out.acts` and
   `out.version` from the published table it is handed; no engine change (spec: none for phases 1-2).
3. **Display rows are untraced.** Spec §4 puts the display rows in `Facade.QUIET` (traced, counted, not written).
   Ruling: a display row is the raw function with no trace wrapper, so no secret answer ever sits in the trace's
   locals or counters; `Facade.QUIET` is unchanged. The inventory, `Facade.Status` ("display") and `Facade.Why` still
   list it.
4. **GCD rule and the swipe source together.** R2 shows the real cooldown only while `isActive and not isOnGCD`;
   §3.4's `ignoreGCD = false` for the press icon then matters only when the GCD outlasts the rest of a running
   cooldown. Both are kept as written: the source switches on the plain flags, the fetch passes
   `ignoreGCD = not press`, where the press button is the one whose `recIndex` is 1.
5. **Names for the layer** (this revision). The toggle is `displays[id].truth.enabled`; the core tab key is `truth`
   (label "Modern"); Truth's per-display state is `d.truthState` and the on flag `d.truthOn` (set by `bindStyle`).
   The contract names are `recIndex`, `isFocus`, `round`, plus the existing `Cooldown` (spec §5.1). Truth copies the
   count-number look with `b.Cooldown:GetHideCountdownNumbers()` (in the Forever API); there is no getter for a
   circular edge, hence `b.round`. `DisplayStyleAPI` stays 1 (M12).
6. **Core calls Truth through `ns.UI.Truth.<member>`** at each call (no local cached at file load), so the TOC order
   does not matter and a test can count the calls.

## Global Constraints

- Core generic (DEVELOPMENT.md §4, architecture §3, spec requirement 7): nothing under `src/Hekili/` or a core test
  names a class, spec, spell, aura, talent or form; `tests/boundary_spec.lua` stays green. Only `tests/Forever/`
  may use the Warrior world (`Forever.helpers.warrior_world`). Style names (`classic`, `timeline`) and `truth` are
  not content.
- Secret safety (architecture §1, spec §3.3, M4): a `Facade.Display` answer goes from one call into one widget
  method or into the per-button held `ov.dur` (a duration object, userdata) and then only into
  `Cooldown:SetCooldownFromDurationObject`. Never compare, do arithmetic on, concatenate, `tostring` or index it;
  never read back a fed aspect (`GetCooldownTimes`, `GetAlpha`, `IsShown` of a fed widget). Branches use plain
  values only (`isActive`, `isOnGCD`, usability, `r.glow`, the contract fields). Nothing from `Facade.Display`
  reaches `d.resolved`, the engine, Snapshot, WeakAuras or the options.
- `Facade.Display` (and `Hekili.Client.Display`) is read only in `src/Hekili/UI/Truth.lua`
  (`tools/check_api_reads.sh`, Task 1).
- No allocation, closure or string building in recurring paths: `Tick`, `Draw` and `OnGameEvent` of Truth and the
  contract assignments in Classic and Timeline allocate nothing (the 0 B tests, Tasks 3 and 6). Frames, textures,
  closures (`ov.done`) and tables are made in `Truth.Build` only. The only client allocation is
  `GetSpellCooldownDuration`'s 56 B per call, on the cooldown events and spell changes only (spec §9 answer 7).
- No jitter (spec requirement 4, §3.2): "less ready" (dim on, mark off) shows at once; "back" shows after the new
  state held for `ns.Output.hold` publishes or `0.1` s, whichever is shorter, or at once after `out.acts` changed.
- Dim, never promote (R1-R3): Truth never writes a record or `d.resolved` field, never moves, hides or adds a pick;
  an overlay may only take the pressable look away.
- Classic and Timeline draw unchanged (requirement 5 as restated): they gain only the contract assignments (Task 2);
  with the toggle off nothing of Truth runs, and the bound style's picks are the same on and off (the parity test,
  Task 3). Truth reads no style's subtable (`conf.classic`, `conf.timeline`), only `conf.truth` and the buttons.
- Every player-visible string is `L["English"]`; after changing text run `python3 tools/locales.py` and commit the
  rewritten `Locales/*.lua`; an intended English change re-records `tests/Forever/fixtures/enus_text.txt` with
  `ENUS_GOLDEN=update` and says why in the commit (architecture §9).
- Lua 5.1. Every addon file starts `local _, ns = ...`. Files under `src/Hekili/UI/` and `src/Hekili/Options/` keep
  upstream's style (spaces inside parentheses; `.styluaignore`); `Game/API/Facade.lua` and tests are
  StyLua-formatted (`stylua <file>`).
- `make check` green on every commit, run as `flock /tmp/hekili-gate.lock make check` (another plan runs its gates
  on this machine; `make gate` takes the lock itself). Single spec runs: `.lua/bin/busted <spec>`.
- Floors only move up. No gate floor is expected to move; a change that moves one stops and says why.
- Commit trailer on every commit, exactly:

  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw
  ```

## Module layout

| File | Change |
|---|---|
| `src/Hekili/Game/API/Facade.lua` | `Facade.Display` and its one row (Task 1) |
| `tools/api_inventory.txt`, `tools/check_api_reads.sh` | the `display` row; the read rule; optional file arguments (Task 1) |
| `src/Hekili/UI/Styles.lua` | the button contract, documented beside `MEMBERS` (Task 2) |
| `src/Hekili/UI/Styles/Classic.lua`, `src/Hekili/UI/Styles/Timeline.lua` | the contract assignments only (Task 2) |
| `src/Hekili/Options/Options.lua` | `displayTemplate.truth`; the core "Modern" tab (Task 3) |
| `src/Hekili/UI/UI.lua` | `bindStyle` attaches Truth; Truth called after the style's `Tick`, `Draw`, `OnGameEvent`, `Clear` (Task 3) |
| `src/Hekili/UI/Truth.lua` (new) | the truth layer (Tasks 3-6) |
| `src/Hekili/Hekili.toc` | `UI\Truth.lua` after `UI\Styles\Timeline.lua` (line 98) (Task 3) |
| `tools/check_engine_reads.sh` | `src/Hekili/UI/Truth.lua` in its `ui` list (Task 3) |
| `tests/Game/API/facade_spec.lua`, `tests/Game/API/display_reads_spec.lua` (new), `tests/Game/API/fixtures/` (new) | Task 1 |
| `tests/Forever/display_modern_spec.lua` (new) | Tasks 2-6 |
| `docs/dev/architecture.md` §5, §7; `docs/dev/layout.md` (line 35); `docs/dev/ingame-ledger.md`; `CHANGELOG.md` | Tasks 1, 3-6 |

## Review Focus

1. **A style without the contract** (a third-party style written for API 1): with the toggle on it draws as before,
   Truth paints nothing and fetches nothing, and nothing errors. Test: Task 3 "paints nothing on a style without the
   button contract".
2. **Switching the style (classic to timeline) or flipping the toggle while a display is shown:** nothing Truth drew
   on the old buttons stays on screen; Truth's events are registered exactly while the toggle is on; with it off no
   Truth member is called. Tests: Task 3 "registers its events only while on" and "runs nothing with the toggle off".
3. **The display's alpha dropping to 0 and coming back** (core calls `Clear` on every unsubscribe and does not
   rebuild, architecture §7): overlays and events come back on the next publish. Test: Task 4 "shows the real swipe
   again on the first publish after a Clear".
4. **A blank publish (`out.count` 0) or a slot with no record:** no veil, mark or real swipe is left on any button.
   Test: Task 5 "leaves nothing on a slot whose record went away".
5. **Items, negative action IDs and charge spells:** never fetched (charges stay modelled until MD-CH; items have no
   spell cooldown) and never dimmed from a spell answer. Test: Task 4 "never fetches for an item or a charge spell".
6. **The contract assignments in Classic and Timeline** set on every path that changes what a button draws (a
   publish, a blank publish, `Clear`), so a stale `recIndex` never points Truth at a record the button no longer
   shows. Test: Task 2.

---

### Task 1: `Facade.Display`, its inventory row and the read rule

**Files:**
- Modify: `src/Hekili/Game/API/Facade.lua` (header comment :1-10; new section before `table.sort(inventory)`, :1001)
- Modify: `tools/api_inventory.txt` (after `C_Spell.GetSpellCooldown	hybrid`, line 36)
- Modify: `tools/check_api_reads.sh` (file list :13; new grep before the final `echo`, :25)
- Modify: `tests/Game/API/facade_spec.lua` (`entry` :41-47; counts :119)
- Create: `tests/Game/API/display_reads_spec.lua`, `tests/Game/API/fixtures/display_outside_truth.lua`,
  `tests/Game/API/fixtures/display_clean.lua`
- Modify: `docs/dev/architecture.md` §5 (the `check_api_reads.sh` bullet, :264-265)

**Interfaces:**
- Produces: `ns.Facade.Display` (also `Hekili.Client.Display`): a table mirroring the game's namespaces; phase 1
  holds `Facade.Display.C_Spell.GetSpellCooldownDuration(spellID, ignoreGCD)` → the client's duration object or
  nil (the raw function; `nothing` when the client lacks it). `Facade.Status("C_Spell.GetSpellCooldownDuration")` is
  `"display"`. `Facade.C_Spell.GetSpellCooldownDuration` stays nil.
- Produces: `tools/check_api_reads.sh [file ...]`: with arguments, checks only those files; fails (exit 1) printing
  `path:line:` for any line matching `(Facade|Client)\.Display\b` outside `src/Hekili/UI/Truth.lua`.

- [ ] **Step 1: Write the failing tests.** In `tests/Game/API/facade_spec.lua` change `entry` to look a display row
  up in `Facade.Display`:

```lua
    local function entry(name)
        local nsName, key = name:match("^([%w_]+)%.([%w_]+)$")
        local root = Facade.Status(name) == "display" and Facade.Display or Facade
        if nsName then
            return root[nsName] and root[nsName][key]
        end
        return root[name]
    end
```

  change the count at line 119 to `{ passthrough = 125, hybrid = 34, virtual = 25, display = 1 }` (and its
  `count` initialiser to include `display = 0`), and after the "never calls the game for a virtual row's answer" case
  add:

```lua
    it("answers a display row raw from Facade.Display only, untraced (Modern spec §4, plan ruling 5)", function()
        assert.is_nil(Facade.C_Spell.GetSpellCooldownDuration)
        local n = #calls
        assert.is_true(rawequal(fake.SECRET, Facade.Display.C_Spell.GetSpellCooldownDuration(7, true)))
        assert.are.equal(n + 1, #calls)
        assert.are.equal("C_Spell.GetSpellCooldownDuration", calls[#calls])
        assert.is_nil(Facade.counts["C_Spell.GetSpellCooldownDuration"])
        assert.is_truthy(Facade.Why("C_Spell.GetSpellCooldownDuration"):find("widget", 1, true))
    end)
```

  Create `tests/Game/API/fixtures/display_outside_truth.lua`:

```lua
local _, ns = ...
-- a file other than UI/Truth.lua reading the display class: tools/check_api_reads.sh must fail on line 3
return ns.Facade.Display.C_Spell.GetSpellCooldownDuration(1, false)
```

  and `tests/Game/API/fixtures/display_clean.lua`:

```lua
local _, ns = ...
return ns.Facade.C_Spell.GetSpellCooldown(1)
```

  Create `tests/Game/API/display_reads_spec.lua`:

```lua
-- tests/Game/API/display_reads_spec.lua (Modern display phase 1 plan, Task 1; spec §4, M3): tools/check_api_reads.sh
-- fails any file but UI/Truth.lua that reads the facade's display class, whose answers may be secret.
local function run(path)
    local p = assert(io.popen("bash tools/check_api_reads.sh " .. path .. " 2>&1; echo rc=$?"))
    local out = p:read("*a")
    p:close()
    return tonumber(out:match("rc=(%d+)%s*$")), out
end

describe("tools/check_api_reads.sh's display rule", function()
    it("fails a file outside UI/Truth.lua that reads Facade.Display, naming the line", function()
        local rc, out = run("tests/Game/API/fixtures/display_outside_truth.lua")
        assert.are.equal(1, rc, out)
        assert.is_truthy(out:find("display_outside_truth.lua:3:", 1, true), out)
    end)

    it("passes a file that reads only the facade's other classes", function()
        local rc, out = run("tests/Game/API/fixtures/display_clean.lua")
        assert.are.equal(0, rc, out)
    end)
end)
```

- [ ] **Step 2: Run them to see them fail.**
  Run: `.lua/bin/busted tests/Game/API/facade_spec.lua tests/Game/API/display_reads_spec.lua`
  Expected: FAIL: the count case (no `display` class), the display-row case (`Facade.Display` nil), and the
  outside-Truth case (rc 0: no rule yet; the script also ignores its argument).

- [ ] **Step 3: Implement.**
  - `Facade.lua`: the header says four classes, the fourth `display` (the raw call whose answer may be secret, for
    a widget only, in `Facade.Display`, read only by `UI/Truth.lua`). Before `table.sort(inventory)` add a section
    with `Facade.Display = {}` and a local `display(name, reason)` that stores `resolve(name) or nothing` at
    `Facade.Display[nsName][key]` (creating the namespace table), appends `name` to `inventory` and sets
    `status[name], why[name] = "display", reason`; no `kept` wrapper (ruling 5). One row:
    `display("C_Spell.GetSpellCooldownDuration", "a duration object (userdata; its getters secret in combat), 56 B per call [W PR11, PR28]; MayReturnNothing [SP:327-343]; for a widget only (Cooldown:SetCooldownFromDurationObject), UI/Truth.lua")`.
  - `tools/api_inventory.txt`: add `C_Spell.GetSpellCooldownDuration	display` (a tab) after line 36.
  - `tools/check_api_reads.sh`: `if [ $# -gt 0 ]; then files=("$@"); else mapfile ... ; fi` in place of line 13
    (the emptiness check stays), and before the final `echo`:

```bash
# Modern display spec §4 (M3): the display class answers raw, possibly secret values meant for a widget; only
# UI/Truth.lua reads it. shortcut: catches Facade.Display / Client.Display spelled out; an alias of the facade
# table (`local F = ns.Facade; F.Display`) needs review.
hits=$(grep -nE '(Facade|Client)\.Display\b' "${files[@]}" | grep -v '^src/Hekili/UI/Truth\.lua:')
[ -n "$hits" ] && { echo "$hits"; fail=1; }
```

    and the `ok:` line unchanged. (With one file, grep prints no `path:` prefix: pass `-H`, i.e. `grep -nHE`.)
  - `docs/dev/architecture.md` §5, the `check_api_reads.sh` bullet: add "and only `UI/Truth.lua` reads
    `Facade.Display`, the display class (raw, possibly secret answers for a widget; Modern display spec §4); given
    file arguments it checks only those".

- [ ] **Step 4: Run them to see them pass.**
  Run: `.lua/bin/busted tests/Game/API/facade_spec.lua tests/Game/API/display_reads_spec.lua`
  Expected: PASS.

- [ ] **Step 5: Full check and commit.**
  Run: `flock /tmp/hekili-gate.lock make check` — expected: exit 0 (`api-check` prints `ok: no direct game API read`).

```bash
git add src/Hekili/Game/API/Facade.lua tools/api_inventory.txt tools/check_api_reads.sh tests/Game/API docs/dev/architecture.md
git commit -m "feat(facade): the display class, Facade.Display, readable only from UI/Truth.lua

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 2: The button contract, set by Classic and Timeline

**Files:**
- Modify: `src/Hekili/UI/Styles.lua` (a comment block after `MEMBERS`, :21)
- Modify: `src/Hekili/UI/Styles/Classic.lua` (`Classic.Draw`: the blank loop :757-760 and the record loop :767-769;
  `Classic.Clear` :1217-1223)
- Modify: `src/Hekili/UI/Styles/Timeline.lua` (`newCell` :163-171; `assign`: the blank loop :638-645 and the cell
  loop :654-657; `Timeline.Clear` :930-942)
- Create: `tests/Forever/display_modern_spec.lua`

**Interfaces:**
- Produces (spec §5.1, every field optional for a style): `b.recIndex` (number: the record index `out.recs[i]` the
  button draws now, 0 for none), `b.isFocus` (bool: the button draws the display's focus record), `b.round` (bool:
  a round icon), and the existing `b.Cooldown` (the button's own `Cooldown` frame, may be nil). Classic: `recIndex =
  i` for `i <= conf.numIcons` and `i <= out.count`, else 0; 0 on a blank publish and in `Clear`; never `isFocus` or
  `round`. Timeline: `recIndex = T.rec[c]` and `isFocus = c == 1 and T.focused` in `assign`; 0 / false on a blank
  publish and in `Clear`; `round = true` on cell 1 from `newCell`.
- Consumes: nothing new. `Hekili.DisplayStyleAPI` stays 1 (M12).

- [ ] **Step 1: Write the failing tests.** Create `tests/Forever/display_modern_spec.lua` with the helpers the
  later tasks reuse and this task's cases:

```lua
-- tests/Forever/display_modern_spec.lua (Modern display phase 1 plan; spec docs/superpowers/specs/2026-10-29-modern-
-- display-design.md): Modern is a core layer over the display's own style (§5.1, M2). The styles publish an optional
-- button contract; with the toggle on, the style draws the same picks (R1) and Truth paints the real cooldown swipe,
-- the usability edge and the proc mark (R2, R3, §3.2). The client's overlay answer and GetSpellCooldownDuration are
-- faked per instance (boot wraps fake.new only while it builds the instance, so other specs' wrappers stay theirs).
local headless = require("Game.harness.headless")
local ww = require("Forever.helpers.warrior_world")
local fake = require("Game.State.helpers.fake_api")

local overlayed, durations = {}, {}
local fx = { n = 0, ignore = {} } -- GetSpellCooldownDuration: calls, and the last ignoreGCD per spell

local rec = {}
function rec.Show(self)
    rawset(self, "__shown", true)
end
function rec.Hide(self)
    rawset(self, "__shown", false)
end
function rec.SetShown(self, v)
    rawset(self, "__shown", v and true or false)
end
function rec.IsShown(self)
    return rawget(self, "__shown") == true
end
function rec.SetTexture(self, t)
    rawset(self, "__tex", t)
end
function rec.SetCooldown(self, start, duration)
    rawset(self, "__cdStart", start)
    rawset(self, "__cdDuration", duration)
end
function rec.SetCooldownFromDurationObject(self, dur)
    rawset(self, "__dur", dur)
end
local function instrument(f)
    if f then
        for k, fn in pairs(rec) do
            rawset(f, k, fn)
        end
    end
end

-- A headless Hekili with Primary on `style` and the Modern toggle `truth` (default off); every button, texture,
-- cooldown, veil and real-swipe frame records its calls.
local function boot(style, truth)
    for k in pairs(overlayed) do
        overlayed[k] = nil
    end
    for k in pairs(durations) do
        durations[k] = nil
    end
    fx.n = 0
    for k in pairs(fx.ignore) do
        fx.ignore[k] = nil
    end
    local saved = fake.new
    fake.new = function(...)
        local api, ctl = saved(...)
        api.C_SpellActivationOverlay.IsSpellOverlayed = function(id)
            return overlayed[id] == true
        end
        api.C_Spell.GetSpellCooldownDuration = function(id, ignoreGCD)
            fx.n = fx.n + 1
            fx.ignore[id] = ignoreGCD
            return durations[id]
        end
        return api, ctl
    end
    local H = headless.new({ character = ww.character(), pack = ww.PACK })
    fake.new = saved
    assert.are.same({}, H.loadErrors)
    H.ctl.inRange.target, H.ctl.level.target = true, 60
    H.Fire("PLAYER_TARGET_CHANGED")
    assert(headless.cycle(H, H.ctl.now + 0.2))
    local conf = H.Hekili.DB.profile.displays.Primary
    conf.style = style
    if conf.truth then -- Task 3 adds the field; Task 2's cases boot with it off
        conf.truth.enabled = truth == true
    end
    H.Hekili:BuildUI()
    local d = rawget(H.env, "HekiliDisplayPrimary")
    for _, b in ipairs(d.Buttons) do
        instrument(b)
        instrument(b.Texture)
        instrument(rawget(b, "Cooldown"))
    end
    local S = d.truthState
    if S and d.truthOn then
        for _, ov in ipairs(S.ov) do
            instrument(ov.cd)
            instrument(ov.veil)
        end
    end
    return H, d
end

local function ids(H)
    local out = {}
    for k, a in pairs(H.Hekili.Engine.Registry.Abilities()) do
        out[k] = a.id
    end
    return out
end

-- Every spell of the Warrior world usable (the fake answers unusable for a spell it was not told about).
local function usableAll(H)
    for _, id in pairs(ids(H)) do
        if type(id) == "number" and id > 0 then
            H.ctl.usable[id] = { true, false }
        end
    end
end

-- { name, seconds from now, focus tier or nil }
local SET = { { "mortal_strike", 1.0 }, { "overpower", 1.5 }, { "slam", 2.0 }, { "rend", 2.5 } }
local SET_FOCUS = { { "mortal_strike", 0.5 }, { "slam", 1.0 }, { "overpower", 2.0, 1 }, { "rend", 3.0 } }
local SET_ONE = { { "slam", 0.3 } }

local function publish(H, set)
    local abilities = H.Hekili.Engine.Registry.Abilities()
    local now = H.ctl.now
    local s = H.ns.Output.Begin("Primary")
    for i, e in ipairs(set) do
        local r = s[i]
        r.actionName, r.actionID = e[1], abilities[e[1]].id
        r.texture, r.keybind = "tex" .. i, "K" .. i
        r.time, r.exact_time, r.focus = e[2], now + e[2], e[3]
    end
    H.ns.Output.Publish("Primary", #set)
end

local function blank(H)
    H.ns.Output.Begin("Primary")
    H.ns.Output.Publish("Primary", 0)
end

local function frame(H, d, dt)
    H.ctl.now = H.ctl.now + dt
    d.__scripts.OnUpdate(d, dt)
end

-- What each button shows, with its contract fields (the R1 parity key).
local function picks(d)
    local t = {}
    for c, b in ipairs(d.Buttons) do
        t[c] = { b:IsShown(), b.Action or false, rawget(b.Texture, "__tex") or false, b.recIndex, b.isFocus or false }
    end
    return t
end

-- The button drawing record 1 (the press icon), or 0.
local function nextButton(d)
    for c, b in ipairs(d.Buttons) do
        if b.recIndex == 1 then
            return c
        end
    end
    return 0
end

describe("the button contract (spec §5.1)", function()
    it("Classic: each button's record while it draws one, 0 past the records, on a blank publish and after Clear", function()
        local H, d = boot("classic")
        usableAll(H)
        publish(H, SET)
        frame(H, d, 0.2)
        local n = H.Hekili.DB.profile.displays.Primary.numIcons
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(c <= n and c <= #SET and c or 0, b.recIndex, "button " .. c)
            assert.is_falsy(b.isFocus)
            assert.is_falsy(b.round)
        end
        assert.are.equal(1, nextButton(d))
        publish(H, SET_ONE)
        frame(H, d, 0.2)
        assert.are.same({ 1, 0 }, { d.Buttons[1].recIndex, d.Buttons[2].recIndex })
        blank(H)
        frame(H, d, 0.2)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "button " .. c)
        end
        publish(H, SET)
        frame(H, d, 0.2)
        d.style.Clear(d)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "button " .. c)
        end
        assert.are.same({}, H.errors)
    end)

    it("Timeline: each cell's record and the focus cell; cell 1 is round", function()
        local H, d = boot("timeline")
        usableAll(H)
        publish(H, SET_FOCUS)
        frame(H, d, 0.2)
        local T = d.styleFrames.timeline
        assert.is_true(T.focused)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(T.rec[c], b.recIndex, "cell " .. c)
            assert.are.equal(c == 1, b.isFocus == true, "cell " .. c)
        end
        assert.are.equal(3, d.Buttons[1].recIndex) -- the flagged record in the now circle
        assert.are.equal(T.press, nextButton(d))
        assert.is_true(d.Buttons[1].round)
        assert.is_falsy(d.Buttons[2].round)
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_false(d.Buttons[1].isFocus)
        blank(H)
        frame(H, d, 0.2)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "cell " .. c)
            assert.is_false(b.isFocus, "cell " .. c)
        end
        publish(H, SET)
        frame(H, d, 0.2)
        d.style.Clear(d)
        for c, b in ipairs(d.Buttons) do
            assert.are.equal(0, b.recIndex, "cell " .. c)
        end
        assert.are.same({}, H.errors)
    end)

    it("costs nothing per frame", function()
        for _, style in ipairs({ "classic", "timeline" }) do
            local H, d = boot(style)
            usableAll(H)
            publish(H, SET)
            for _ = 1, 3 do
                frame(H, d, 0.2)
            end
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for _ = 1, 1000 do
                d.__scripts.OnUpdate(d, 0.01)
            end
            local bytes = (collectgarbage("count") - before) * 1024
            collectgarbage("restart")
            assert.are.equal(0, bytes, style)
        end
    end)
end)
```

  (Timeline's `T.rec[c]` is 0 for an empty cell, and `roles` writes it on every publish; Classic's `numIcons`
  default is 4.)

- [ ] **Step 2: Run to see them fail.** Run: `.lua/bin/busted tests/Forever/display_modern_spec.lua` — expected:
  FAIL (`b.recIndex` nil).

- [ ] **Step 3: Implement.**
  - `UI/Styles.lua`, after `MEMBERS`:

```lua
-- The button contract (Modern display spec §5.1, decision M2; every field optional, so DisplayStyleAPI stays 1, M12).
-- Core's truth layer (UI/Truth.lua, the display's Modern toggle) paints over a button only through these; a style
-- that sets none of them draws exactly as before with the toggle on, and gets no overlays.
--   b.recIndex  the record the button draws now (out.recs[ b.recIndex ]), 0 for none; set on every publish, a blank
--               publish and Clear (the "next" icon is the button whose recIndex is 1)
--   b.isFocus   true while the button draws the display's focus record
--   b.Cooldown  the button's own Cooldown frame (Truth hides it while it shows the game's)
--   b.round     true for a round icon (Truth's swipe and veil use the circle)
```

  - `Classic.Draw`: in the blank loop, `b.recIndex = 0` beside `b.Action = nil`; in the record loop, after
    `b.Recommendation = ...`: `b.recIndex = ( i <= conf.numIcons and i <= out.count ) and i or 0`.
    `Classic.Clear`: `b.recIndex = 0` beside `b.Action = nil`.
  - `Timeline.lua` `newCell`: in the `if i <= 2 then` block's `if i == 1 then`, `b.round = true`. `assign`: in the
    blank loop, `b.recIndex, b.isFocus = 0, false`; in the cell loop, after `b.Recommendation = recs[ i ]`:
    `b.recIndex, b.isFocus = i, c == 1 and T.focused`. `Timeline.Clear`: `b.recIndex, b.isFocus = 0, false` in its
    cell loop.
  No other line of either style changes.

- [ ] **Step 4: Run to see them pass.** Run: `.lua/bin/busted tests/Forever/display_modern_spec.lua
  tests/Forever/display_style_spec.lua` — expected: PASS (the styles' own specs unchanged).

- [ ] **Step 5: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/UI/Styles.lua src/Hekili/UI/Styles/Classic.lua src/Hekili/UI/Styles/Timeline.lua tests/Forever/display_modern_spec.lua
git commit -m "feat(styles): the optional button contract (recIndex, isFocus, round), set by classic and timeline

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 3: The Modern toggle: core field and tab, Truth attached to the bound style, parity

**Files:**
- Create: `src/Hekili/UI/Truth.lua`
- Modify: `src/Hekili/Options/Options.lua` (`displayTemplate` :179-215: `truth` after `visibility`; `newDisplayOption`:
  a `truth` tab in `option[ name ].args` beside `main` :1317 and `visibility` :1525)
- Modify: `src/Hekili/UI/UI.lua` (`unsubscribe` :934; `bindStyle` :1081-1096; `d.OnUpdate` :1157-1162; `d:OnEvent`
  :1224; `d:Deactivate` :1307)
- Modify: `src/Hekili/Hekili.toc` (after line 98: `UI\Truth.lua`)
- Modify: `tools/check_engine_reads.sh` (`ui=(...)` list: add `src/Hekili/UI/Truth.lua`)
- Modify: `src/Hekili/Locales/*.lua` (via `python3 tools/locales.py`), `tests/Forever/fixtures/enus_text.txt`
  (via `ENUS_GOLDEN=update`)
- Test: `tests/Forever/display_modern_spec.lua` (new `describe`)
- Modify: `docs/dev/architecture.md` §7, `docs/dev/layout.md:35-36`, `docs/dev/ingame-ledger.md` (row MD-TAINT)

**Interfaces:**
- Produces (`Options.lua`): `displayTemplate.truth = { enabled = false, swipes = true, edge = true, confirm = true }`
  (so `StyleNameTaken( "truth" )` is true); the core tab `truth` (path `{ "displays", <id>, "truth", <option> }`,
  stored at `displays[id].truth.<option>` by the existing `optionConf`), shown on every style.
- Produces (`UI.lua`): `d.truthOn` (bool), set by `bindStyle` from `conf.truth.enabled`; while it is true, core calls
  `ns.UI.Truth.Build( d, conf, d.Buttons )` after the style's `Build`, `ns.UI.Truth.Tick( d, conf, out, now )` after
  `style.Tick`, `ns.UI.Truth.Draw( d, conf, out )` after `style.Draw`, `ns.UI.Truth.OnGameEvent( d, conf, event, ... )`
  after `style.OnGameEvent`, and `ns.UI.Truth.Clear( d )` after every `style.Clear` and before a rebuild.
- Produces (`Truth.lua`, `ns.UI.Truth`): `Truth.VERIFIED = { strip = false, execute = false, ride = false, cdm =
  false }`; `Truth.EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE" }`;
  `Truth.Build( d, conf, buttons )`, `Truth.Tick( d, conf, out, now )`, `Truth.Draw( d, conf, out )`,
  `Truth.OnGameEvent( d, conf, event, ... )`, `Truth.Clear( d )`. State `S = d.truthState`: `S.buttons`,
  `S.sets[ buttons ][ c ]` (one `ov` per button of each button list the display has bound, so a style switch back
  reuses its overlays), `S.ov` (the current set), `S.cleared`. Each `ov` starts `{ spell = 0, press = false }`;
  Tasks 4-6 add their fields.
- Consumes: Task 2's contract.

- [ ] **Step 1: Write the failing tests.** Append to `tests/Forever/display_modern_spec.lua`:

```lua
describe("the Modern toggle (spec §5.1, §7)", function()
    for _, style in ipairs({ "classic", "timeline" }) do
        it("leaves " .. style .. "'s picks and contract unchanged with the toggle on (R1 parity)", function()
            for _, set in ipairs({ SET, SET_FOCUS, SET_ONE }) do
                local H, d = boot(style)
                usableAll(H)
                publish(H, set)
                frame(H, d, 0.2)
                local want = picks(d)
                local H2, d2 = boot(style, true)
                usableAll(H2)
                publish(H2, set)
                frame(H2, d2, 0.2)
                assert.are.same(want, picks(d2))
                assert.are.equal(H2.ns.UI.Styles[style], d2.style)
                assert.is_true(d2.truthOn)
                assert.are.same({}, H2.errors)
            end
        end)

        it("allocates nothing over 1,000 display frames with the toggle on, on " .. style, function()
            local H, d = boot(style, true)
            usableAll(H)
            publish(H, SET)
            for _ = 1, 3 do
                frame(H, d, 0.2)
            end
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for _ = 1, 1000 do
                d.__scripts.OnUpdate(d, 0.01)
            end
            local bytes = (collectgarbage("count") - before) * 1024
            collectgarbage("restart")
            assert.are.same({}, H.errors)
            assert.are.equal(0, bytes)
        end)
    end

    it("defaults off, in its own core field and one Modern tab on every style", function()
        local H = boot("classic")
        local conf = H.Hekili.DB.profile.displays.Primary
        -- AceDB serves defaults through metatables: read each field
        local t = conf.truth
        assert.are.same({ false, true, true, true }, { t.enabled, t.swipes, t.edge, t.confirm })
        assert.is_true(H.ns.UI.StyleNameTaken("truth"))
        assert.is_nil(H.ns.UI.Styles.modern)
        H.Hekili:EmbedDisplayOptions()
        local args = H.Hekili.Options.args.displays.plugins.Primary.Primary.args
        assert.is_table(args.truth)
        assert.is_nil(args.truth.hidden)
        assert.is_nil(args.classic.args.tab_modern)
        local path = { "displays", "Primary", "truth", "enabled" }
        assert.is_false(H.Hekili:GetDisplayOption(path))
        assert.is_true(args.truth.args.swipes.disabled())
        H.Hekili:SetDisplayOption(path, true)
        assert.is_true(conf.truth.enabled)
        assert.is_false(args.truth.args.swipes.disabled())
        for _, k in ipairs({ "swipes", "edge", "confirm" }) do
            assert.is_true(H.Hekili:GetDisplayOption({ "displays", "Primary", "truth", k }), k)
        end
        assert.is_nil(args.truth.args.execute)
        assert.is_nil(args.truth.args.ride)
        conf.style = "timeline"
        assert.is_nil(args.truth.hidden) -- core's tab, whatever the style
        assert.are.same({}, H.errors)
    end)

    it("registers its events only while on, again after a Clear on the next draw, across a style switch", function()
        local H, d = boot("classic", true)
        local function registered()
            local n = 0
            for _, e in ipairs(H.ns.UI.Truth.EVENTS) do
                n = n + (d:IsEventRegistered(e) and 1 or 0)
            end
            return n
        end
        assert.are.equal(3, registered())
        d.style.Clear(d) -- what core's unsubscribe does, then Truth's
        H.ns.UI.Truth.Clear(d)
        assert.are.equal(0, registered())
        publish(H, SET)
        frame(H, d, 0.2)
        assert.are.equal(3, registered())
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "timeline")
        H.Hekili:BuildUI()
        assert.are.equal(3, registered())
        assert.are.equal(d.styleFrames.timeline.cells, d.truthState.buttons)
        H.Hekili:SetDisplayOption({ "displays", "Primary", "truth", "enabled" }, false)
        H.Hekili:BuildUI()
        assert.are.equal(0, registered())
        assert.is_false(d.truthOn)
        assert.are.same({}, H.errors)
    end)

    it("runs nothing with the toggle off", function()
        local H, d = boot("classic")
        local T, calls = H.ns.UI.Truth, 0
        for _, k in ipairs({ "Build", "Tick", "Draw", "OnGameEvent", "Clear" }) do
            local f = T[k]
            T[k] = function(...)
                calls = calls + 1
                return f(...)
            end
        end
        H.Hekili:BuildUI()
        usableAll(H)
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 1)
        d.style.Clear(d)
        assert.are.equal(0, calls)
        assert.is_false(d.truthOn)
        assert.are.same({}, H.errors)
    end)

    it("paints nothing on a style without the button contract", function()
        local H = boot("classic")
        assert.is_true(H.Hekili:RegisterDisplayStyle("bare", {
            api = H.Hekili.DisplayStyleAPI,
            label = "Bare",
            Build = function(d)
                local b = rawget(d, "bareButton") or H.env.CreateFrame("Button", nil, d)
                rawset(d, "bareButton", b)
                return { b }
            end,
            Draw = function() end,
            Tick = function() end,
            OnGameEvent = function() end,
            Clear = function() end,
            Perimeter = function() end,
            UpdateKeybindings = function() end,
            Options = function()
                return nil
            end,
        }))
        local conf = H.Hekili.DB.profile.displays.Primary
        conf.style, conf.truth.enabled = "bare", true
        H.Hekili:BuildUI()
        local d = rawget(H.env, "HekiliDisplayPrimary")
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike] = { isActive = true, isOnGCD = false }
        durations[A.mortal_strike] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(d.truthOn)
        assert.are.equal(0, d.truthState.ov[1].spell)
        assert.is_nil(d.truthState.ov[1].cd)
        assert.are.equal(0, fx.n)
        assert.are.same({}, H.errors)
    end)

    it("keeps every probe-gated overlay off in code (M1)", function()
        local H = boot("classic", true)
        assert.are.same({ strip = false, execute = false, ride = false, cdm = false }, H.ns.UI.Truth.VERIFIED)
    end)
end)
```

  (`d:IsEventRegistered` is the harness's recording method, `headless.lua:478-480`. In the parity case the first
  boot has the toggle off, the second on; `picks` includes the contract fields. `Options = function() return nil end`
  is allowed: core skips a style that returns no tabs, `Options.lua:1753-1754`.)

- [ ] **Step 2: Run to see them fail.** Run: `.lua/bin/busted tests/Forever/display_modern_spec.lua` — expected:
  FAIL (`conf.truth` nil, `ns.UI.Truth` nil).

- [ ] **Step 3: Implement `Truth.lua` (lifecycle only).** Header comment: the truth layer behind a display's Modern
  toggle (spec §5.1-5.2, decision M2), attached by core to the bound style's buttons; the only reader of
  `Facade.Display`; what it reads (the button contract, records, `d.resolved`, plain facade rows, `conf.truth`; no
  style's subtable); credits as in Classic's header for the glow helper use. `Truth.Build` creates `S =
  d.truthState` on first use (`{ sets = {} }`), sets `S.buttons`, makes `S.sets[ buttons ]` and an `ov` for every
  button that lacks one, points `S.ov` at that set, resets each `ov` (`spell = 0`, `press = false`), registers
  `Truth.EVENTS` on `d`, `S.cleared = false`. `Truth.Clear` unregisters them, resets each `ov` of `S.ov`, sets
  `S.cleared = true` (no-op when `S` is nil). `Truth.Draw` re-registers when `S.cleared` and clears the flag. `Tick`
  and `OnGameEvent` return at once for now. End with `ns.UI.Truth = Truth`.
- [ ] **Step 4: Wire core.**
  - `Options.lua` `displayTemplate`, after `visibility`: `truth = { enabled = false, swipes = true, edge = true,
    confirm = true }, -- the Modern layer (UI/Truth.lua): core's, on every style (Modern display spec §5.1, §7)`.
  - `Options.lua` `newDisplayOption`, a tab beside `main` and `visibility`:
    `truth = { type = "group", name = L["Modern"], desc = L["The game's own truth painted over this display's icons, whatever its style."], order = 2.5, args = { ... } }`
    with: a `description` (`order = 0`, `fontSize = "medium"`):
    `L["Experimental. Keeps this display's style and settings, and adds the game's own cooldown swipes, an immediate grey when the game says an ability cannot be used yet, and a gold glow on the next ability when the game lights its proc. Hekili still decides what to show."]`;
    `enabled` (toggle, `order = 1`, `width = "full"`, `L["Modern (game truth)"]`, `L["Turn the Modern overlays on for this display. Turn it off to go back to the plain style."]`);
    `swipes` (toggle, `L["Real Cooldown Swipes"]`, `L["Show the game's own cooldown on an icon while it runs, instead of Hekili's estimate."]`);
    `edge` (toggle, `L["Grey When Not Usable"]`, `L["Grey an icon as soon as the game says the ability cannot be used yet (short of resource, or its proc or condition is not up)."]`);
    `confirm` (toggle, `L["Proc Glow"]`, `L["Glow the next ability (and the focus ability) when the game lights its proc. Never on a greyed icon."]`).
    `swipes`, `edge` and `confirm` share one `disabled` function, true while the display's `truth.enabled` is off
    (on Multi: Primary's, as the other Multi getters). Get and set go through the group's `GetDisplayOption` /
    `SetDisplayOption`, whose `optionConf` already maps `{ display, "truth", option }` to `displays[display].truth`.
  - `UI.lua` `bindStyle`, around the style's `Build`:

```lua
        if d.truthOn then ns.UI.Truth.Clear( d ) end -- what the layer drew on the old buttons goes with them
        ns.UI.Buttons[ d.id ] = d.style.Build( d, conf )
        d.Buttons = ns.UI.Buttons[ d.id ]
        -- Modern (spec §5.1, M2): core's layer over whichever style is bound, only while its toggle is on
        d.truthOn = conf.truth.enabled == true
        if d.truthOn then ns.UI.Truth.Build( d, conf, d.Buttons ) end
```

  - `UI.lua`: `if self.truthOn then ns.UI.Truth.Tick( self, conf, out, now ) end` after `style.Tick( ... )`;
    `if self.truthOn then ns.UI.Truth.Draw( self, conf, out ) end` after `style.Draw( ... )` (inside `if draw`);
    `if self.truthOn then ns.UI.Truth.OnGameEvent( self, conf, event, ... ) end` after `self.style.OnGameEvent( ... )`;
    `if d.truthOn then ns.UI.Truth.Clear( d ) end` after `d.style.Clear( d )` in `unsubscribe`, and the same after
    `self.style.Clear( self )` in `Deactivate`. (The style-switch `Clear` in `bindStyle` is covered by the line above
    the `Build`.) Ruling 6: each call looks `ns.UI.Truth` up when it runs.
- [ ] **Step 5: TOC, engine-reads list, locales, golden.** Add `UI\Truth.lua` after `UI\Styles\Timeline.lua`; add
  `src/Hekili/UI/Truth.lua` to `check_engine_reads.sh`'s `ui=(...)`. Run `python3 tools/locales.py`, then
  `ENUS_GOLDEN=update .lua/bin/busted tests/Forever/enus_text_spec.lua` and check `git diff
  tests/Forever/fixtures/enus_text.txt` adds only the Modern tab's strings.
- [ ] **Step 6: Docs.**
  - `docs/dev/architecture.md` §7: a paragraph **The Modern layer**: a core per-display toggle (`displays[id].truth`,
    its own core tab on every style) that attaches `UI/Truth.lua` to the bound style's buttons and calls it right
    after each style member, only while on (decision M2, the owner's 2026-10-29 layer design; no style wraps another,
    so "No style reads another style's subtable" holds with no exception); the optional **button contract**
    (`recIndex`, `isFocus`, `Cooldown`, `round`; `UI/Styles.lua`), optional so `DisplayStyleAPI` stays 1 (M12), and
    that a style without it gets no overlays. "What a style may read" gains `out.acts` (the `Output.Acted` count at
    the last publish, ruling 2). Rulings 1-6 of this plan in one short list under it.
  - `docs/dev/layout.md:35-36`: "the Modern layer (`Truth`, the only reader of `Facade.Display`)".
  - `docs/dev/ingame-ledger.md`: row `| MD-TAINT | Core | /console taintLog 1, Hekili with Modern on for one display (Primary, Classic style), two pulls on an open-world mob, then a dungeon pull, /reload; then the same on Timeline: Logs/taint.log names no Hekili frame; no "blocked" popup; action bars and Cooldown Manager keep working | research §3: a Modern overlay calls protected widget methods (SetCooldownFromDurationObject) from addon code; a fail keeps Modern developer-only until the culprit is found | open: launch day 2026-11-04 |`.
- [ ] **Step 7: Run to see them pass.** Run: `.lua/bin/busted tests/Forever/display_modern_spec.lua
  tests/Forever/display_style_spec.lua tests/Forever/style_options_spec.lua tests/Forever/enus_text_spec.lua` —
  expected: PASS.
- [ ] **Step 8: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/UI/Truth.lua src/Hekili/UI/UI.lua src/Hekili/Options/Options.lua src/Hekili/Hekili.toc tools/check_engine_reads.sh src/Hekili/Locales tests/Forever/display_modern_spec.lua tests/Forever/fixtures/enus_text.txt docs/dev
git commit -m "feat(display): the experimental Modern toggle attaches the truth layer to any style (no overlays yet)

The English golden gains the Modern tab's strings.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 4: Truth: the real cooldown swipe

**Files:**
- Modify: `src/Hekili/UI/Truth.lua`
- Test: `tests/Forever/display_modern_spec.lua` (new `describe`)
- Modify: `docs/dev/ingame-ledger.md` (row MD-CD)

**Interfaces:**
- Produces, per `ov` (a button with a `b.Cooldown` only, contract §5.1; Timeline's lane cells have none): `ov.cd` (a
  `Cooldown` frame, `CooldownFrameTemplate`, all points on the button, `b.Cooldown`'s frame level,
  `SetDrawBling(false)`, `SetDrawEdge(false)`, `SetHideCountdownNumbers(b.Cooldown:GetHideCountdownNumbers())`, and
  for a `b.round` button `SetSwipeTexture(CIRCLE)` / `SetUseCircularEdge(true)`, `CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"`);
  `ov.done` (its `OnCooldownDone` script, made once in Build); `ov.real` (bool), `ov.dur` (held duration object or
  nil), `ov.cdShown` (bool), `ov.charged` (bool), `ov.press` (bool).
- Consumes: `Facade.C_Spell.GetSpellCooldown(spell)` (`.isActive`, `.isOnGCD`, plain), `Facade.Display` (Task 1),
  `Hekili.Engine.Registry.Abilities()[name]` (`rawget(def, "charges")`), the button contract (Task 2).

- [ ] **Step 1: Write the failing tests.** Append to `tests/Forever/display_modern_spec.lua`:

```lua
local ACTIVE = { isActive = true, isOnGCD = false, startTime = fake.SECRET, duration = fake.SECRET }
local ON_GCD = { isActive = true, isOnGCD = true, startTime = fake.SECRET, duration = fake.SECRET }

describe("Modern's real cooldown swipe (R2, §3.4)", function()
    it("shows the game's cooldown while it runs and hands the style its own swipe back when it ends", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike] = ACTIVE
        H.ctl.cooldown[A.overpower] = ON_GCD
        durations[A.mortal_strike], durations[A.overpower] = fake.SECRET, fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local ov, b = d.truthState.ov, d.Buttons
        assert.is_true(ov[1].real)
        assert.is_true(rawequal(fake.SECRET, ov[1].cd.__dur))
        assert.is_true(ov[1].cd.__shown)
        assert.is_false(b[1].Cooldown.__shown)
        assert.is_false(fx.ignore[A.mortal_strike]) -- the press icon's swipe includes the GCD
        assert.is_false(ov[2].real) -- the GCD alone: the style's swipe
        assert.is_nil(fx.ignore[A.overpower])
        H.ctl.cooldown[A.mortal_strike] = nil
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_false(ov[1].real)
        assert.is_false(ov[1].cd.__shown)
        assert.is_true(b[1].Cooldown.__shown)
        -- R2: the style's own delay look (classic's extend) still runs to Hekili's time
        local exact = H.Hekili.Engine.Output.Primary.recs[1].exact_time
        assert.is_true(math.abs(b[1].Cooldown.__cdStart + b[1].Cooldown.__cdDuration - exact) < 1e-6)
        assert.are.same({}, H.errors)
    end)

    it("fetches a queued icon's cooldown without the GCD; ends on the widget's own OnCooldownDone", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.overpower] = ACTIVE
        durations[A.overpower] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local ov = d.truthState.ov[2]
        assert.is_true(fx.ignore[A.overpower])
        assert.is_true(ov.real)
        ov.cd.__scripts.OnCooldownDone(ov.cd)
        assert.is_false(ov.real)
        assert.is_true(d.Buttons[2].Cooldown.__shown)
        assert.are.same({}, H.errors)
    end)

    it("fetches only on a spell change and the cooldown events, never per frame", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike], H.ctl.cooldown[A.overpower] = ACTIVE, ACTIVE
        durations[A.mortal_strike], durations[A.overpower] = fake.SECRET, fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        assert.are.equal(2, fx.n)
        for _ = 1, 50 do
            frame(H, d, 0.01)
        end
        assert.are.equal(2, fx.n)
        publish(H, SET) -- the same spells in the same slots
        frame(H, d, 0.01)
        assert.are.equal(2, fx.n)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.are.equal(4, fx.n)
        H.Fire("SPELL_UPDATE_CHARGES")
        assert.are.equal(6, fx.n)
        publish(H, { { "overpower", 1.0 }, { "mortal_strike", 1.5 } }) -- both slots change spell
        frame(H, d, 0.01)
        assert.are.equal(8, fx.n)
        assert.is_false(fx.ignore[A.overpower]) -- now the press icon
        assert.is_true(fx.ignore[A.mortal_strike])
        assert.are.same({}, H.errors)
    end)

    it("never fetches for an item or a charge spell, and not with swipes off", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike], H.ctl.cooldown[A.overpower] = ACTIVE, ACTIVE
        durations[A.mortal_strike], durations[A.overpower] = fake.SECRET, fake.SECRET
        rawset(H.Hekili.Engine.Registry.Abilities().overpower, "charges", 2)
        local s = H.ns.Output.Begin("Primary")
        s[1].actionName, s[1].actionID, s[1].item = "mortal_strike", A.mortal_strike, 1234 -- an item record
        s[1].texture, s[1].time, s[1].exact_time = "t1", 1, H.ctl.now + 1
        s[2].actionName, s[2].actionID = "overpower", A.overpower
        s[2].texture, s[2].time, s[2].exact_time = "t2", 1.5, H.ctl.now + 1.5
        H.ns.Output.Publish("Primary", 2)
        frame(H, d, 0.2)
        assert.are.equal(0, fx.n)
        H.Hekili.DB.profile.displays.Primary.truth.swipes = false
        H.Hekili:BuildUI()
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.are.equal(0, fx.n)
        assert.are.same({}, H.errors)
    end)

    it("shows the real swipe again on the first publish after a Clear", function()
        local H, d = boot("timeline", true)
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike] = ACTIVE
        durations[A.mortal_strike] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local T = d.styleFrames.timeline
        local c = T.press
        local ov = d.truthState.ov[c]
        assert.is_true(ov.real)
        d.style.Clear(d) -- what core's unsubscribe does, then Truth's
        H.ns.UI.Truth.Clear(d)
        assert.is_false(ov.cd.__shown)
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_true(ov.real)
        assert.is_true(ov.cd.__shown)
        assert.is_false(T.cells[c].Cooldown.__shown)
        assert.is_nil(d.truthState.ov[3].cd) -- a lane cell has no swipe
        assert.are.same({}, H.errors)
    end)

    it("passes the duration object only to the swipe: one read site, no error on the secret sentinel", function()
        local reads = {}
        for l in io.lines("src/Hekili/UI/Truth.lua") do
            local code = l:gsub("%-%-.*$", "")
            if code:find("Display%.") or code:find("Facade%.Display") then
                reads[#reads + 1] = code:match("^%s*(.-)%s*$")
            end
        end
        assert.are.equal(2, #reads)
        assert.is_truthy(reads[1]:match("^local Display = ns%.Facade%.Display$"), reads[1])
        assert.is_truthy(reads[2]:match("^ov%.dur = Display%.C_Spell%.GetSpellCooldownDuration%(.*%)$"), reads[2])
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        for _, id in pairs(A) do
            H.ctl.cooldown[id], durations[id] = ACTIVE, fake.SECRET -- raises on compare, arithmetic, concat, index
        end
        publish(H, SET)
        for _ = 1, 5 do
            frame(H, d, 0.2)
            H.Fire("SPELL_UPDATE_COOLDOWN")
            H.Fire("SPELL_UPDATE_USABLE")
        end
        assert.are.same({}, H.errors)
    end)
end)
```

- [ ] **Step 2: Run to see them fail.** `.lua/bin/busted tests/Forever/display_modern_spec.lua` — FAIL (`ov.real`
  nil, no `ov.cd`).

- [ ] **Step 3: Implement in `Truth.lua`.**
  - Build: per button `b` with `b.Cooldown`, create `ov.cd` and `ov.done` as in Interfaces (`ov.done` sets
    `ov.real, ov.dur = false, nil` and marks the swipe dirty, then applies it); `ov.cd:SetScript("OnCooldownDone",
    ov.done)`; `ov.cd:Hide()`.
  - Draw: `local blank = out.count == 0 or out.version == d.blankVersion`; per button `c` (`b = S.buttons[c]`),
    `i = blank and 0 or b.recIndex or 0`, `press = i == 1`, the record `out.recs[i]` when `1 <= i <= out.count`;
    its plain spell: `rec.actionID` when `rec.actionName`, `rec.exact_time`, no `rec.item`
    and `rec.actionID > 0`, else 0. When the spell or `press` changed: store them, `ov.charged =
    rawget(def, "charges") ~= nil`, and refresh the swipe. Then apply.
  - The refresh (the only fetch; on a change and on `SPELL_UPDATE_COOLDOWN` / `SPELL_UPDATE_CHARGES` for every
    `ov` with a spell):

```lua
local function swipe( ov, conf )
    ov.real, ov.dur, ov.dirty = false, nil, true
    if not ( conf.truth.swipes and ov.cd and ov.spell > 0 and not ov.charged ) then return end
    local info = C_Spell.GetSpellCooldown( ov.spell ) -- the hybrid: isActive and isOnGCD are plain
    if info and info.isActive and not info.isOnGCD then
        ov.dur = Display.C_Spell.GetSpellCooldownDuration( ov.spell, not ov.press )
        ov.real = ov.dur ~= nil
    end
end
```

  - Apply (Draw, OnGameEvent, `ov.done`): when dirty, either `ov.cd:SetCooldownFromDurationObject(ov.dur)`,
    `ov.cd:Show()`, `b.Cooldown:Hide()`, `ov.cdShown = true`; or, when `ov.cdShown`, `ov.cd:Hide()`,
    `b.Cooldown:Show()`, `ov.cdShown = false`. Truth.Draw runs after the style's Draw, so it ends with `if ov.cdShown then
    b.Cooldown:Hide() end` (a style may re-show its own, e.g. Timeline's `reveal`).
  - Clear: hide every `ov.cd`, show `b.Cooldown` where `ov.cdShown`, reset `real`, `dur`, `cdShown`, `spell = 0`.
- [ ] **Step 4: Ledger row.** `docs/dev/ingame-ledger.md`: `| MD-CD | Warrior | /vslog md cd (research §3): a button-sized Cooldown fed GetSpellCooldownDuration(id, false) on SPELL_UPDATE_COOLDOWN beside the Hekili icon; fight, press Mortal Strike or Bloodthirst and Charge, let them come back. Then the same with a display on Modern: its swipe ends with the action bar's | MDCD set ok every call; the swipe ends on the frame the plain isActive goes false (MDCD end dt within one frame); 0 B per frame between events. Fail: Modern's real swipes off for that kind (a commit sets swipes off in code and cites this row) | open: launch day 2026-11-04 |`.
- [ ] **Step 5: Run to see them pass.** `.lua/bin/busted tests/Forever/display_modern_spec.lua` — PASS, the
  Task 3 cases included (R1 and 0 B with swipes on).
- [ ] **Step 6: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/UI/Truth.lua tests/Forever/display_modern_spec.lua docs/dev/ingame-ledger.md
git commit -m "feat(modern): the game's own cooldown swipe over the style's while it runs

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 5: Truth: the usability edge (event-driven dim, debounced)

**Files:**
- Modify: `src/Hekili/UI/Truth.lua`
- Test: `tests/Forever/display_modern_spec.lua` (new `describe`)
- Modify: `docs/dev/ingame-ledger.md` (row MD-USE)

**Interfaces:**
- Produces, per `ov`: `ov.top` (a frame on the button, all points, level `b:GetFrameLevel() + 3`), `ov.veil` (an
  `OVERLAY` texture on it, all points, `WHITE = "Interface\\Buttons\\WHITE8X8"` or `CIRCLE` for a `b.round` button,
  vertex colour `0, 0, 0, VEIL_ALPHA` with `VEIL_ALPHA = 0.5`); `ov.usable` (plain bool: `IsSpellUsable`'s first
  return); `ov.dim = { ready, want, since, ver, acts }` (preallocated in Build); `ov.dimShown` (bool).
- Produces: `local function settle( g, want, now, ver, acts )` → `g.ready`: the shared debounce for the dim and
  (Task 6) the mark; `local function reset( g, want, now, ver, acts )` (a spell change: no debounce).
- Consumes: `Facade.C_Spell.IsSpellUsable` (plain), `out.version`, `out.acts`, `ns.Output.hold`,
  `Facade.GetTime()` in `OnGameEvent`.

- [ ] **Step 1: Write the failing tests.** Append:

```lua
describe("Modern's usability edge (§3.2)", function()
    local function setup(style)
        local H, d = boot(style or "classic", true)
        usableAll(H)
        publish(H, SET)
        frame(H, d, 0.2)
        return H, d, ids(H), d.truthState.ov[1]
    end

    it("dims at once on SPELL_UPDATE_USABLE when the game says not usable, between pulses", function()
        local H, d, A, ov = setup()
        assert.is_false(ov.dimShown)
        H.ctl.usable[A.mortal_strike] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(ov.dimShown)
        assert.is_true(ov.veil.__shown)
        H.ctl.usable[A.mortal_strike] = { false, false } -- an unmet proc or condition dims too (plan ruling 1)
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(ov.dimShown)
        assert.are.same({}, H.errors)
    end)

    it("undims only after 0.1 s with no publish and no cast of ours", function()
        local H, d, A, ov = setup()
        H.ns.Output.hold = 3
        H.ctl.usable[A.mortal_strike] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        H.ctl.usable[A.mortal_strike] = { true, false }
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(ov.dimShown)
        frame(H, d, 0.05)
        assert.is_true(ov.dimShown)
        frame(H, d, 0.06)
        assert.is_false(ov.dimShown)
        assert.is_false(ov.veil.__shown)
    end)

    it("never blinks: a flip back and forth restarts the wait", function()
        local H, d, A, ov = setup()
        H.ns.Output.hold = 3
        H.ctl.usable[A.mortal_strike] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        H.ctl.usable[A.mortal_strike] = { true, false }
        H.Fire("SPELL_UPDATE_USABLE")
        frame(H, d, 0.05)
        H.ctl.usable[A.mortal_strike] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        H.ctl.usable[A.mortal_strike] = { true, false }
        H.Fire("SPELL_UPDATE_USABLE")
        frame(H, d, 0.06)
        assert.is_true(ov.dimShown)
        frame(H, d, 0.05)
        assert.is_false(ov.dimShown)
    end)

    it("undims after Output.hold publishes, or at the first publish after our own cast", function()
        local H, d, A, ov = setup()
        H.ns.Output.hold = 2
        H.ctl.usable[A.mortal_strike] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        H.ctl.usable[A.mortal_strike] = { true, false }
        H.Fire("SPELL_UPDATE_USABLE")
        publish(H, SET)
        frame(H, d, 0.01)
        assert.is_true(ov.dimShown)
        publish(H, SET)
        frame(H, d, 0.01)
        assert.is_false(ov.dimShown)
        H.ns.Output.hold = 3
        H.ctl.usable[A.mortal_strike] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        H.ctl.usable[A.mortal_strike] = { true, false }
        H.Fire("SPELL_UPDATE_USABLE")
        H.ns.Output.Acted()
        publish(H, SET)
        frame(H, d, 0.01)
        assert.is_false(ov.dimShown)
        assert.are.same({}, H.errors)
    end)

    it("dims a lane icon too, and nothing with the edge off", function()
        local H, d, A = setup("timeline")
        local T = d.styleFrames.timeline
        local lane = 3
        local spell = A[T.cells[lane].Action]
        H.ctl.usable[spell] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(d.truthState.ov[lane].dimShown)
        H.Hekili.DB.profile.displays.Primary.truth.edge = false
        H.Hekili:BuildUI()
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_UPDATE_USABLE")
        for c, ov in ipairs(d.truthState.ov) do
            assert.is_false(ov.dimShown, "button " .. c)
        end
        assert.are.same({}, H.errors)
    end)

    it("leaves nothing on a slot whose record went away", function()
        local H, d, A = setup()
        for _, id in pairs(A) do
            H.ctl.usable[id] = { false, true }
        end
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(d.truthState.ov[4].dimShown)
        publish(H, SET_ONE)
        frame(H, d, 0.2)
        for c = 2, #d.Buttons do
            assert.is_false(d.truthState.ov[c].dimShown, "button " .. c)
        end
        H.ns.Output.Begin("Primary")
        H.ns.Output.Publish("Primary", 0)
        frame(H, d, 0.2)
        for c, ov in ipairs(d.truthState.ov) do
            assert.is_false(ov.dimShown, "button " .. c)
            assert.is_false(ov.real or false, "button " .. c)
        end
        assert.are.same({}, H.errors)
    end)
end)
```

- [ ] **Step 2: Run to see them fail.** `.lua/bin/busted tests/Forever/display_modern_spec.lua` — FAIL
  (`ov.dimShown` nil).
- [ ] **Step 3: Implement in `Truth.lua`.** `SETTLE = 0.1` (spec §3.2). The debounce:

```lua
-- Less ready shows at once; back to ready once the wanted state held SETTLE seconds or Output.hold publishes, or at
-- once after our own cast (out.acts moved) (spec §3.2). `g.ready` is the shown state.
local function settle( g, want, now, ver, acts )
    if want ~= g.want then g.want, g.since, g.ver, g.acts = want, now, ver, acts end
    if not want then g.ready = false
    elseif not g.ready and ( now - g.since >= SETTLE or ver - g.ver >= Output.hold or acts ~= g.acts ) then g.ready = true end
    return g.ready
end
```

  `reset` sets `g.want, g.ready` to `want` and the stamps to now. On a spell change (Task 4's change branch):
  `ov.usable = ov.spell == 0 or ( C_Spell.IsSpellUsable( ov.spell ) )` and `reset( ov.dim, ov.usable, ... )`. On
  `SPELL_UPDATE_USABLE`: per `ov` with a spell, re-read `ov.usable`, `settle`, apply. Tick: per `ov`, `settle( ov.dim,
  ov.usable, now, out.version, out.acts )`, apply. Apply: `dim = conf.truth.edge and ov.spell > 0 and not
  ov.dim.ready`; on a change of `ov.dimShown`, `ov.veil:SetShown( dim )`. Clear hides every veil and resets
  `dimShown`.
- [ ] **Step 4: Ledger row.** `| MD-USE | Warrior, Druid | none (auto, research §3): record SPELL_UPDATE_USABLE's time against the poll's insufficientPower flip for the spenders (Sources/Power.lua's ladder) on open-world mobs | the event comes no later than the next poll in at least 95% of flips. Fail: Modern's grey keeps the 0.2 s pulse (no loss against Classic) | open: launch day 2026-11-04 |`.
- [ ] **Step 5: Run to see them pass.** `.lua/bin/busted tests/Forever/display_modern_spec.lua` — PASS.
- [ ] **Step 6: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/UI/Truth.lua tests/Forever/display_modern_spec.lua docs/dev/ingame-ledger.md
git commit -m "feat(modern): grey an icon on the game's usability edge, back only after the hold

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 6: Truth: the proc mark on the next and focus icons; every overlay at 0 B; the changelog

**Files:**
- Modify: `src/Hekili/UI/Truth.lua`
- Test: `tests/Forever/display_modern_spec.lua` (new `describe`)
- Modify: `CHANGELOG.md` (Unreleased, New)

**Interfaces:**
- Produces, per `ov`: `ov.glow` (plain: the button is the press or focus button, `conf.truth.confirm`, and
  `d.resolved[i].glow`), `ov.mark = { ready, want, since, ver, acts }`, `ov.markShown` (bool). The mark is
  `LibCustomGlow`'s `AutoCastGlow_Start( b, MARK, nil, nil, nil, nil, nil, KEY )` / `AutoCastGlow_Stop( b, KEY )`
  with `KEY = "truth"` and `MARK = { 1, 0.8, 0.1, 1 }` (Timeline's gold, built once), apart from the style's own
  glow (no key) and Timeline's ready glow (`"focus"`).
- Consumes: the contract's `b.recIndex` (the press button: `recIndex == 1`) and `b.isFocus` (Task 2), `d.resolved[i].glow`, Task 5's `settle`.

- [ ] **Step 1: Write the failing tests.** Append:

```lua
describe("Modern's proc mark (R3, M11)", function()
    it("marks the next icon when the game lights its overlay, never a queued one", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        overlayed[A.mortal_strike], overlayed[A.overpower] = true, true
        publish(H, SET)
        frame(H, d, 0.2)
        local ov = d.truthState.ov
        assert.is_true(ov[1].markShown)
        assert.is_false(ov[2].markShown)
        assert.are.same({}, H.errors)
    end)

    it("marks the focus cell and the next box on timeline, never a lane icon", function()
        local H, d = boot("timeline", true)
        local A = ids(H)
        usableAll(H)
        for _, e in ipairs(SET_FOCUS) do
            overlayed[A[e[1]]] = true
        end
        publish(H, SET_FOCUS)
        frame(H, d, 0.2)
        local T, ov = d.styleFrames.timeline, d.truthState.ov
        assert.is_true(T.focused)
        assert.are.equal(3, T.rec[1]) -- the flagged record in the now circle
        assert.are.equal(1, T.rec[T.press])
        assert.is_true(ov[1].markShown)
        assert.is_true(ov[T.press].markShown)
        for c = 3, #ov do
            assert.is_false(ov[c].markShown, "lane cell " .. c)
        end
        assert.are.same({}, H.errors)
    end)

    it("never marks a dimmed icon; the mark comes back with the dim's hold", function()
        local H, d = boot("classic", true)
        local A = ids(H)
        usableAll(H)
        H.ns.Output.hold = 3
        overlayed[A.mortal_strike] = true
        publish(H, SET)
        frame(H, d, 0.2)
        local ov = d.truthState.ov[1]
        assert.is_true(ov.markShown)
        H.ctl.usable[A.mortal_strike] = { false, false }
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(ov.dimShown)
        assert.is_false(ov.markShown)
        H.ctl.usable[A.mortal_strike] = { true, false }
        H.Fire("SPELL_UPDATE_USABLE")
        frame(H, d, 0.05)
        assert.is_false(ov.markShown)
        frame(H, d, 0.06)
        assert.is_false(ov.dimShown)
        assert.is_true(ov.markShown)
        H.Hekili.DB.profile.displays.Primary.truth.confirm = false
        H.Hekili:BuildUI()
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_false(d.truthState.ov[1].markShown)
        assert.are.same({}, H.errors)
    end)

    for _, style in ipairs({ "classic", "timeline" }) do
        it("allocates nothing over 1,000 frames with a real swipe, a dim and a mark showing on " .. style, function()
            local H, d = boot(style, true)
            local A = ids(H)
            usableAll(H)
            H.ctl.cooldown[A.mortal_strike] = ACTIVE
            durations[A.mortal_strike] = fake.SECRET
            overlayed[A.mortal_strike] = true
            H.ctl.usable[A.slam] = { false, true }
            publish(H, SET)
            for _ = 1, 3 do
                frame(H, d, 0.2)
            end
            local ov = d.truthState.ov
            local press = nextButton(d)
            assert.is_true(ov[press].real)
            assert.is_true(ov[press].markShown)
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for _ = 1, 1000 do
                d.__scripts.OnUpdate(d, 0.01)
            end
            local bytes = (collectgarbage("count") - before) * 1024
            collectgarbage("restart")
            assert.are.same({}, H.errors)
            assert.are.equal(0, bytes)
        end)
    end
end)
```

- [ ] **Step 2: Run to see them fail.** `.lua/bin/busted tests/Forever/display_modern_spec.lua` — FAIL
  (`ov.markShown` nil).
- [ ] **Step 3: Implement in `Truth.lua`.** Draw: per button, before Task 4's change branch, `ov.glow =
  conf.truth.confirm and ( press or b.isFocus == true ) and i >= 1 and d.resolved[ i ].glow or false` (so a spell
  change `reset`s the mark from the new record's glow, and a glow that appears later settles like the dim). Tick and the usability event: `settle( ov.mark, ov.glow
  and ov.usable, now, out.version, out.acts )` beside the dim's (a spell change `reset`s it); apply `mark =
  ov.mark.ready and not ov.dimShown` (R3: never on a dimmed icon), starting or stopping the keyed glow only on a
  change of `ov.markShown`. Clear stops every mark and resets `markShown`.
- [ ] **Step 4: Changelog.** `CHANGELOG.md`, Unreleased, New:
  `- New experimental display option, Modern (game truth): keeps your Classic or Timeline display as it is and adds the game's own cooldown swipes, an immediate grey when the game says an ability cannot be used yet, and a glow on the next ability when the game lights its proc. Hekili still decides what to show; turn it on in a display's Modern tab to try it.`
- [ ] **Step 5: Run to see them pass.** `.lua/bin/busted tests/Forever/display_modern_spec.lua
  tests/Forever/display_style_spec.lua` — PASS.
- [ ] **Step 6: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/UI/Truth.lua tests/Forever/display_modern_spec.lua CHANGELOG.md
git commit -m "feat(modern): proc glow on the next and focus icons from the game's overlay, never on a greyed icon

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

## Open after phase 1

- **Probes (launch day 2026-11-04, ledger rows):** MD-TAINT (Task 3), MD-CD (Task 4), MD-USE (Task 5). Their
  verdicts may turn phase 1 parts off in code; none flips a `VERIFIED` key.
- **Phase 2 (after GC-T):** truth bars, dev build only (`Hekili.IsDev`, §7.1, M10): `Facade.Display.UnitPower`,
  `UnitPowerPercent`, `UnitHealthPercent`, `C_CurveUtil.CreateCurve` rows, the bars and ticks, `VERIFIED.strip`;
  the execute border (`healthGate`, step curves per §6, `VERIFIED.execute`, MD-PVP for player targets).
- **Phase 3:** the Cooldown Manager confirmation (`rec.confirmed`, pack field `confirmAura`, `DisplayStyleAPI` 2,
  CDM-T; `VERIFIED.cdm`); the Timeline ride (one hook in `Timeline.lua`'s `moveLane` / `assign`, `ride[i]` bars,
  clamp curves, GC-T and MD-TL; `VERIFIED.ride`); charge spells' real recharge (`GetSpellChargeDuration`, MD-CH).
- **Timeline's `oocTimers` off** hides Timeline's sweeps out of combat; Modern's real swipe still shows a running
  cooldown there. Open for the owner (spec §9 answer 3); recommended: the real swipe follows the bound style's
  setting, through one more optional contract field (Truth reads no style's subtable).
- **Promotion:** Modern stays experimental until the three probes pass and the owner's checklist (spec §8, in game
  only) is walked.
