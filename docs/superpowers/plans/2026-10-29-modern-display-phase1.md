# Modern Display, Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in, experimental display style `modern` ("Modern (game truth)") that draws a display with the
player's Classic or Timeline layout unchanged and paints three plain-or-display-only truths over Hekili's picks: the
game's real cooldown swipe, an event-driven "not yet" dim from the game's usability answer, and a proc mark from the
game's overlay glow on the next and focus icons only.

**Architecture:** `UI/Styles/Modern.lua` registers `modern` and delegates every style member to the base style
(`classic` or `timeline`, from `displays[id].modern.base`), then calls the truth layer `UI/Truth.lua`, the only file
that reads the new fourth facade class `Facade.Display` (raw calls whose answers go to a widget only). Truth reads
only the published records, `d.resolved`, the plain facade rows and a read-only layout accessor per base that
Modern owns (decision M2). Classic and Timeline are not edited; core gains one generic rule (a style subtable that
names a `base` style takes that style's shared groups and shows its option group).

**Tech Stack:** Lua 5.1 (WoW, Forever 1.60.1), busted, luacheck, StyLua, the headless harness
(`tests/Game/harness/headless.lua`), LibCustomGlow-1.0, AceConfig (options), AceLocale (`L[...]`).

**Spec:** `docs/superpowers/specs/2026-10-29-modern-display-design.md` (APPROVED 2026-10-29; §9 answers binding;
rulings R3 / M11 and §7.1 / M10). Research: `docs/research/2026-10-29-modern-display-api.md`. Executors read both.
Line numbers below are as of `forever-modern-research` 3d334aab6.

## Scope

Phase 1 only (spec §2, §9 answer 8): true cooldown swipes, the usability edge, proc confirmation from usability and
the overlay glow. Not built (YAGNI, phases 2-3): truth bars, the execute border, the Timeline ride, the Cooldown
Manager field, curves, `UnitPower` / `UnitHealthPercent` / `GetSpellChargeDuration` rows, the `execute` and `ride`
options, the Developer header. `Truth.VERIFIED` exists with every key false and nothing reads it but its test.

## Rulings on the spec (this plan's; recorded in architecture §7 by Task 3)

1. **The base's option tabs.** Spec §5.1 says `Modern.Options` returns "the base's tabs plus one Modern tab". Core
   puts a style's tabs in one group keyed by the style's name and resolves every option under it to
   `displays[id].<group key>.*` (`optionConf`, `Options/Options.lua:681-691`), so base tabs inside the `modern` group
   would read and write `displays[id].modern.keybindings` etc., not the base's. Ruling: `Modern.Options` returns only
   the Modern tab; core shows a style's own group also while the display's bound style's subtable names it as `base`
   (Task 2, generic). The player edits the base's layout in the base's own group, at its own paths, as M2 intends.
2. **The base's shared groups.** `Hekili.Engine.StyleGroup` (`Engine/Settings.lua:57-64`) falls back to classic's
   range, flash and keybinding groups for a style without them, so a timeline-based Modern would make the engine and
   Resolve read classic's settings. Ruling: a style subtable whose `base` names another style subtable takes that
   subtable's groups (Task 2, generic, the same `base` key as ruling 1).
3. **Proc confirmation from usability.** Spec §2 and §5.2 read route 2 from `r.usable`, but Resolve keeps only
   `IsSpellUsable`'s second return (`insufficientPower`, `UI/Resolve.lua:94-96`), and a proc that gates usability
   (research §2.6 route 2) flips the first (`isUsable`). Ruling: Truth asks `C_Spell.IsSpellUsable` (a plain
   passthrough, `Facade.lua:908`) itself, on `SPELL_UPDATE_USABLE` and on a button's spell change, and the edge dims
   on `not isUsable` (short of resource, or an unmet proc or condition). Usability confirms a proc as the absence of
   that dim (dim, never promote: no pack fact says which abilities are proc-gated, so no usability-only mark). The
   confirm mark is the overlay glow (route 3, `r.glow`), on the next and focus icons only (R3), and never on a dimmed
   icon.
4. **`Output.Acted` "through a getter".** No getter exists (`acts` is local, `Engine/Output.lua:101-109`), but every
   publish copies it to the display's `out.acts` (`Engine/Output.lua:203`). Ruling: Truth reads `out.acts` and
   `out.version` from the published table it is handed; no engine change (spec: none for phases 1-2).
5. **Display rows are untraced.** Spec §4 puts the display rows in `Facade.QUIET` (traced, counted, not written).
   Ruling: a display row is the raw function with no trace wrapper, so no secret answer ever sits in the trace's
   locals or counters; `Facade.QUIET` is unchanged. The inventory, `Facade.Status` ("display") and `Facade.Why` still
   list it.
6. **GCD rule and the swipe source together.** R2 shows the real cooldown only while `isActive and not isOnGCD`;
   §3.4's `ignoreGCD = false` for the press icon then matters only when the GCD outlasts the rest of a running
   cooldown. Both are kept as written: the source switches on the plain flags, the fetch passes
   `ignoreGCD = not press`.

## Global Constraints

- Core generic (DEVELOPMENT.md §4, architecture §3, spec requirement 7): nothing under `src/Hekili/` or a core test
  names a class, spec, spell, aura, talent or form; `tests/boundary_spec.lua` stays green. Only `tests/Forever/`
  may use the Warrior world (`Forever.helpers.warrior_world`). Style names (`classic`, `timeline`, `modern`) are not
  content.
- Secret safety (architecture §1, spec §3.3, M4): a `Facade.Display` answer goes from one call into one widget
  method or into the per-button held `ov.dur` (a duration object, userdata) and then only into
  `Cooldown:SetCooldownFromDurationObject`. Never compare, do arithmetic on, concatenate, `tostring` or index it;
  never read back a fed aspect (`GetCooldownTimes`, `GetAlpha`, `IsShown` of a fed widget). Branches use plain
  values only (`isActive`, `isOnGCD`, usability, `r.glow`). Nothing from `Facade.Display` reaches `d.resolved`,
  the engine, Snapshot, WeakAuras or the options.
- `Facade.Display` (and `Hekili.Client.Display`) is read only in `src/Hekili/UI/Truth.lua`
  (`tools/check_api_reads.sh`, Task 1).
- No allocation, closure or string building in recurring paths: `Tick`, `Draw` and `OnGameEvent` of Modern and
  Truth allocate nothing (the 0 B tests, Tasks 3 and 6). Frames, textures, closures (`ov.done`) and tables are made
  in `Build` only. The only client allocation is `GetSpellCooldownDuration`'s 56 B per call, on the cooldown events
  and spell changes only (spec §9 answer 7).
- No jitter (spec requirement 4, §3.2): "less ready" (dim on, mark off) shows at once; "back" shows after the new
  state held for `ns.Output.hold` publishes or `0.1` s, whichever is shorter, or at once after `out.acts` changed.
- Dim, never promote (R1-R3): Modern never writes a record or `d.resolved` field, never moves, hides or adds a pick;
  an overlay may only take the pressable look away.
- Classic untouched (requirement 5): no edit to `src/Hekili/UI/Styles/Classic.lua` or `Timeline.lua` in this plan.
- Every player-visible string is `L["English"]`; after changing text run `python3 tools/locales.py` and commit the
  rewritten `Locales/*.lua`; an intended English change re-records `tests/Forever/fixtures/enus_text.txt` with
  `ENUS_GOLDEN=update` and says why in the commit (architecture §9).
- Lua 5.1. Every addon file starts `local _, ns = ...`. Files under `src/Hekili/UI/` and `src/Hekili/Options/` keep
  upstream's style (spaces inside parentheses; `.styluaignore`); `Game/API/Facade.lua`, `Engine/Settings.lua` and
  tests are StyLua-formatted (`stylua <file>`).
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
| `src/Hekili/Engine/Settings.lua`, `src/Hekili/Options/Options.lua` | the `base` rule (Task 2) |
| `src/Hekili/UI/Styles/Modern.lua` (new) | the style: delegation, layout accessor, options (Task 3) |
| `src/Hekili/UI/Truth.lua` (new) | the truth layer (Tasks 3-6) |
| `src/Hekili/Hekili.toc` | `UI\Truth.lua`, `UI\Styles\Modern.lua` after `UI\Styles\Timeline.lua` (line 98) (Task 3) |
| `tools/check_engine_reads.sh` | `src/Hekili/UI/Truth.lua` in its `ui` list (Task 3) |
| `tests/Game/API/facade_spec.lua`, `tests/Game/API/display_reads_spec.lua` (new), `tests/Game/API/fixtures/` (new) | Task 1 |
| `tests/Forever/style_options_spec.lua` | Task 2 |
| `tests/Forever/display_modern_spec.lua` (new) | Tasks 3-6 |
| `docs/dev/architecture.md` §5, §7; `docs/dev/layout.md` (line 35); `docs/dev/ingame-ledger.md`; `CHANGELOG.md` | Tasks 1, 3-6 |

## Review Focus

1. **A profile whose `modern.base` is missing, `"modern"`, or a style that does not exist** (an edited or imported
   profile): the display draws as `classic` with no error and no recursion. Test: Task 3 "draws classic for a base
   it does not know".
2. **Switching the base (classic to timeline) or the style (modern to classic and back) while a display is shown:**
   nothing the old base or Truth drew stays on screen; Truth's events are registered exactly while `modern` is bound.
   Tests: Task 3 "switching the base hides the old base's buttons" and "registers its events only while bound".
3. **The display's alpha dropping to 0 and coming back** (core calls `Clear` on every unsubscribe and does not
   rebuild, architecture §7): overlays and events come back on the next publish. Test: Task 4 "shows the real
   swipe again on the first publish after a Clear".
4. **A blank publish (`out.count` 0) or a slot with no record:** no veil, mark or real swipe is left on any button.
   Test: Task 5 "leaves nothing on a slot whose record went away".
5. **Items, negative action IDs and charge spells:** never fetched (charges stay modelled until MD-CH; items have no
   spell cooldown) and never dimmed from a spell answer. Test: Task 4 "never fetches for an item or a charge spell".

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

### Task 2: A style may draw with another style's layout (`base`)

**Files:**
- Modify: `src/Hekili/Engine/Settings.lua:55-64` (`Engine.StyleGroup`)
- Modify: `src/Hekili/Options/Options.lua:1195-1212` (`styleOf`, `notStyle`)
- Test: `tests/Forever/style_options_spec.lua` (new `describe` after the one ending at :310)

**Interfaces:**
- Produces: the rule "a display whose bound style's subtable has `base = <name>`, where `displays[id][name]` is a
  table, draws with that style's layout": `Hekili.Engine.StyleGroup(display, group)` returns
  `display[base][group]` (else the bound style's own, else classic's, as today); the options show the group of
  `base` as well as the bound style's own.
- Consumes: nothing new.

- [ ] **Step 1: Write the failing tests.** In `tests/Forever/style_options_spec.lua`, after the
  "engine's and the shared resolve's range, flash and keybinding settings" describe, add:

```lua
describe("a style that draws with another style's layout (its subtable's `base`)", function()
    it("takes the base's range, flash and keybinding groups; an unknown base changes nothing", function()
        local H = boot()
        assert.is_true(external(H, { "range" }))
        local conf = H.Hekili.DB.profile.displays.Primary
        local group = H.Hekili.Engine.StyleGroup
        conf.style, conf.ext.base = "ext", "timeline"
        assert.are.equal(conf.timeline.range, group(conf, "range"))
        assert.are.equal(conf.timeline.flash, group(conf, "flash"))
        assert.are.equal(conf.timeline.keybindings, group(conf, "keybindings"))
        conf.ext.base = "nope"
        assert.are.equal(conf.ext.range, group(conf, "range"))
        assert.are.equal(conf.classic.flash, group(conf, "flash"))
        assert.are.same({}, H.errors)
    end)

    it("shows the base's option group beside the style's own", function()
        local H = boot()
        assert.is_true(external(H, { "range" }))
        local conf = H.Hekili.DB.profile.displays.Primary
        conf.style, conf.ext.base = "ext", "timeline"
        H.Hekili:EmbedDisplayOptions()
        local args = H.Hekili.Options.args.displays.plugins.Primary.Primary.args
        assert.is_false(args.ext.hidden())
        assert.is_false(args.timeline.hidden())
        assert.is_true(args.classic.hidden())
        conf.ext.base = nil
        assert.is_true(args.timeline.hidden())
        assert.are.same({}, H.errors)
    end)
end)
```

- [ ] **Step 2: Run to see them fail.**
  Run: `.lua/bin/busted tests/Forever/style_options_spec.lua`
  Expected: FAIL: `group(conf, "range")` is `conf.ext.range`; `args.timeline.hidden()` is true.

- [ ] **Step 3: Implement.**
  - `Engine.StyleGroup`: after `local own = display[display.style or "classic"]`, when `own` is a table whose
    `base` is a string naming a table in `display`, use `display[own.base]` as `own` (one `if`; the doc comment
    gains "or, when that style's subtable names a `base`, the base's").
  - `Options.lua`: a local `drawsWith(display, style)` beside `styleOf`: true when `styleOf(display) == style`, or
    when `displays[display][styleOf(display)]` is a table whose `base == style`; `notStyle` tests
    `not drawsWith(...)` in both branches (single display and Multi). `notClassic` follows automatically.

- [ ] **Step 4: Run to see them pass.** Run: `.lua/bin/busted tests/Forever/style_options_spec.lua
  tests/Forever/display_style_spec.lua` — expected: PASS (classic and timeline unchanged).

- [ ] **Step 5: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/Engine/Settings.lua src/Hekili/Options/Options.lua tests/Forever/style_options_spec.lua
git commit -m "feat(styles): a style subtable naming a base takes the base's groups and shows its options

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01PSygyDGe77y6FKXJAcabWw"
```

---

### Task 3: The `modern` style: delegation, the layout accessor, options and Truth's lifecycle

**Files:**
- Create: `src/Hekili/UI/Styles/Modern.lua`, `src/Hekili/UI/Truth.lua`
- Modify: `src/Hekili/Hekili.toc` (after line 98: `UI\Truth.lua`, then `UI\Styles\Modern.lua`)
- Modify: `tools/check_engine_reads.sh` (`ui=(...)` list: add `src/Hekili/UI/Truth.lua`)
- Modify: `src/Hekili/Locales/*.lua` (via `python3 tools/locales.py`), `tests/Forever/fixtures/enus_text.txt`
  (via `ENUS_GOLDEN=update`)
- Create: `tests/Forever/display_modern_spec.lua`
- Modify: `docs/dev/architecture.md` §7, `docs/dev/layout.md:35-36`, `docs/dev/ingame-ledger.md` (row MD-TAINT)

**Interfaces:**
- Produces (`Modern.lua`): style `modern` registered with `Hekili:RegisterDisplayStyle("modern", Modern)`,
  `api = Hekili.DisplayStyleAPI`, `label = L["Modern (game truth)"]`,
  `defaults = { base = "classic", swipes = true, edge = true, confirm = true }`. Members:
  `Build(d, conf)` → the base's button list; `Tick(d, conf, out, now, elapsed)`; `Draw(d, conf, out, status)`;
  `OnGameEvent(d, conf, event, ...)`; `Clear(d)`; `Perimeter(d)`; `UpdateKeybindings(d)`; `Options(id, conf)` → one
  tab `tab_modern`; `NeedsFor(id, conf)` → the base's `NeedsFor(id, conf)` or `needs`. Each delegates to the base
  first, then Truth. The base name is `conf.modern.base` when it is `"timeline"`, else `"classic"`; kept on
  `d.styleFrames.modern.base`.
- Produces: `Modern.LAYOUT[base]`, the read-only layout accessor (M2), per base:
  `record(d, conf, c)` → the record index button `c` draws (0: none); `press(d)` → the button drawing record 1
  (0: none); `focus(d)` → the button drawing the focus record (0: none); `round(c)` → bool (the swipe and veil are
  round); `hideNumbers` (bool). Classic: `c <= conf.numIcons and c or 0`, `1`, `0`, false, false. Timeline (reads
  `d.styleFrames.timeline`, never writes it): `T.rec[c] or 0`, `T.has and T.press or 0`, `T.focused and 1 or 0`,
  `c == 1`, true.
- Produces (`Truth.lua`, `ns.UI.Truth`): `Truth.VERIFIED = { strip = false, execute = false, ride = false, cdm =
  false }`; `Truth.EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE" }`;
  `Truth.Build(d, conf, buttons, layout)`, `Truth.Tick(d, conf, out, now)`, `Truth.Draw(d, conf, out)`,
  `Truth.OnGameEvent(d, conf, event, ...)`, `Truth.Clear(d)`. State `S = d.styleFrames.modern`:
  `S.base`, `S.layout`, `S.buttons`, `S.ov` (per button of the current base, `S.sets[base][c]`), `S.cleared`.
  Each `ov` starts `{ spell = 0, press = false }`; Tasks 4-6 add their fields.
- Consumes: Task 2's `base` rule; `ns.UI.Styles.classic` / `.timeline`.

- [ ] **Step 1: Write the failing tests.** Create `tests/Forever/display_modern_spec.lua` with the helpers the
  later tasks reuse and this task's cases:

```lua
-- tests/Forever/display_modern_spec.lua (Modern display phase 1 plan; spec docs/superpowers/specs/2026-10-29-modern-
-- display-design.md): the modern style draws its base's picks unchanged (R1) and paints the real cooldown swipe, the
-- usability edge and the proc mark (R2, R3, §3.2). The client's overlay answer and GetSpellCooldownDuration are faked
-- per instance (boot wraps fake.new only while it builds the instance, so other specs' wrappers stay theirs).
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

-- A headless Hekili with Primary on `style` (and `base` for modern); every button, texture, cooldown, veil and
-- real-swipe frame records its calls.
local function boot(style, base)
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
    if base then
        conf.modern.base = base
    end
    H.Hekili:BuildUI()
    local d = rawget(H.env, "HekiliDisplayPrimary")
    for _, b in ipairs(d.Buttons) do
        instrument(b)
        instrument(b.Texture)
        instrument(rawget(b, "Cooldown"))
    end
    local S = d.styleFrames.modern
    if S and style == "modern" then
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

local function frame(H, d, dt)
    H.ctl.now = H.ctl.now + dt
    d.__scripts.OnUpdate(d, dt)
end

local function picks(d)
    local t = {}
    for c, b in ipairs(d.Buttons) do
        t[c] = { b:IsShown(), b.Action or false, rawget(b.Texture, "__tex") or false }
    end
    return t
end

describe("the modern style", function()
    for _, base in ipairs({ "classic", "timeline" }) do
        it("draws exactly the picks " .. base .. " draws, in the same slots (R1)", function()
            for _, set in ipairs({ SET, SET_FOCUS, SET_ONE }) do
                local H, d = boot(base)
                usableAll(H)
                publish(H, set)
                frame(H, d, 0.2)
                local want = picks(d)
                local H2, d2 = boot("modern", base)
                usableAll(H2)
                publish(H2, set)
                frame(H2, d2, 0.2)
                assert.are.same(want, picks(d2))
                assert.are.equal(H2.ns.UI.Styles.modern, d2.style)
                assert.are.same({}, H2.errors)
            end
        end)

        it("allocates nothing over 1,000 display frames after the first publish on a " .. base .. " base", function()
            local H, d = boot("modern", base)
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

    it("defaults off, with its own subtable, label and one Modern tab; the base's tabs show beside it", function()
        local H = boot("classic")
        local conf = H.Hekili.DB.profile.displays.Primary
        assert.are.equal("classic", conf.style)
        -- AceDB serves defaults through metatables: read each field
        local m = conf.modern
        assert.are.same({ "classic", true, true, true }, { m.base, m.swipes, m.edge, m.confirm })
        assert.are.equal("Modern (game truth)", H.ns.UI.Styles.modern.label)
        conf.style = "modern"
        H.Hekili:EmbedDisplayOptions()
        local args = H.Hekili.Options.args.displays.plugins.Primary.Primary.args
        assert.is_false(args.modern.hidden())
        assert.is_false(args.classic.hidden())
        assert.is_true(args.timeline.hidden())
        local path = { "displays", "Primary", "modern", "tab_modern", "base" }
        assert.are.equal("classic", H.Hekili:GetDisplayOption(path))
        H.Hekili:SetDisplayOption(path, "timeline")
        assert.are.equal("timeline", conf.modern.base)
        for _, k in ipairs({ "swipes", "edge", "confirm" }) do
            assert.is_true(H.Hekili:GetDisplayOption({ "displays", "Primary", "modern", "tab_modern", k }), k)
        end
        assert.is_nil(args.modern.args.tab_modern.args.execute)
        assert.is_nil(args.modern.args.tab_modern.args.ride)
        assert.are.same({}, H.errors)
    end)

    it("draws classic for a base it does not know", function()
        for _, bad in ipairs({ "modern", "nope", false }) do
            local H, d = boot("modern", bad or nil)
            H.Hekili.DB.profile.displays.Primary.modern.base = bad or nil
            H.Hekili:BuildUI()
            assert.are.equal("classic", d.styleFrames.modern.base)
            assert.are.equal(d.styleFrames.classic, d.Buttons)
            assert.are.same({}, H.errors)
        end
    end)

    it("switching the base hides the old base's buttons; switching to classic hides Truth's state", function()
        local H, d = boot("modern", "classic")
        usableAll(H)
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_true(d.styleFrames.classic[1]:IsShown())
        H.Hekili:SetDisplayOption({ "displays", "Primary", "modern", "tab_modern", "base" }, "timeline")
        H.Hekili:BuildUI()
        for i, b in ipairs(d.styleFrames.classic) do
            assert.is_false(b:IsShown(), "classic button " .. i)
        end
        assert.are.equal(d.styleFrames.timeline.cells, d.Buttons)
        assert.are.equal("timeline", d.styleFrames.modern.base)
        assert.are.same({}, H.errors)
    end)

    it("registers its events only while bound, again after a Clear on the next draw", function()
        local H, d = boot("modern", "classic")
        local function registered()
            local n = 0
            for _, e in ipairs(H.ns.UI.Truth.EVENTS) do
                n = n + (d:IsEventRegistered(e) and 1 or 0)
            end
            return n
        end
        assert.are.equal(3, registered())
        d.style.Clear(d)
        assert.are.equal(0, registered())
        publish(H, SET)
        frame(H, d, 0.2)
        assert.are.equal(3, registered())
        H.Hekili:SetDisplayOption({ "displays", "Primary", "main", "style" }, "classic")
        H.Hekili:BuildUI()
        assert.are.equal(0, registered())
        assert.are.same({}, H.errors)
    end)

    it("keeps every probe-gated overlay off in code (M1)", function()
        local H = boot("modern", "classic")
        assert.are.same({ strip = false, execute = false, ride = false, cdm = false }, H.ns.UI.Truth.VERIFIED)
    end)
end)
```

  (`d:IsEventRegistered` is the harness's recording method, `headless.lua:478-480`. In the R1 case the first boot
  is the plain base style, the second the same base under `modern`.)

- [ ] **Step 2: Run to see them fail.** Run: `.lua/bin/busted tests/Forever/display_modern_spec.lua` — expected:
  FAIL (`conf.modern` nil, no `modern` style).

- [ ] **Step 3: Implement `Truth.lua` (lifecycle only).** Header comment: the truth layer of the modern style
  (spec §5.2), the only reader of `Facade.Display`, what it reads (records, `d.resolved`, plain facade rows, the
  layout accessor), credits as in Classic's header for the glow helper use. `Truth.Build` creates `S` on first use
  (`{ sets = {} }`), sets `S.base`, `S.layout`, `S.buttons`, makes `S.sets[base][c]` for every button that lacks one,
  points `S.ov` at that set, resets each `ov` (`spell = 0`), registers `Truth.EVENTS` on `d`, `S.cleared = false`.
  `Truth.Clear` unregisters them, resets each `ov`, sets `S.cleared = true` (no-op when `S` is nil). `Truth.Draw`
  re-registers when `S.cleared` and clears the flag. `Tick` and `OnGameEvent` return at once for now.
- [ ] **Step 4: Implement `Modern.lua`.** Header: decision M2, the `base` rule (Task 2), that Classic and Timeline
  are not edited. A local `baseName(conf)` (ruling: anything but `"timeline"` is `"classic"`), `Modern.LAYOUT` as in
  Interfaces, the members as in Interfaces (`Build`: when `d.styleFrames.modern` holds a different `base`, call the
  old base's `Clear(d)` and `Truth.Clear(d)` first; then `buttons = base.Build(d, conf)`,
  `Truth.Build(d, conf, buttons, Modern.LAYOUT[name])`, return `buttons`). `Options(id, conf)` returns
  `{ tab_modern = { type = "group", name = L["Modern"], desc = ..., order = 1, args = { ... } } }` with:
  a `description` (`order = 0`, `fontSize = "medium"`): `L["Experimental. Your Classic or Timeline layout, with the game's own cooldown swipes, an immediate grey when the game says an ability cannot be used yet, and a gold glow on the next ability when the game lights its proc. Hekili still decides what to show."]`;
  `base` (select, `values = { classic = L["Classic"], timeline = L["Timeline"] }`, `name = L["Layout"]`,
  `desc = L["The layout Modern draws. Its settings are in that layout's own tabs."]`);
  `swipes` (toggle, `L["Real Cooldown Swipes"]`, `L["Show the game's own cooldown on an icon while it runs, instead of Hekili's estimate."]`);
  `edge` (toggle, `L["Grey When Not Usable"]`, `L["Grey an icon as soon as the game says the ability cannot be used yet (short of resource, or its proc or condition is not up)."]`);
  `confirm` (toggle, `L["Proc Glow"]`, `L["Glow the next ability (and the focus ability) when the game lights its proc. Never on a greyed icon."]`).
  End with `Modern.api = Hekili.DisplayStyleAPI` and `Hekili:RegisterDisplayStyle( "modern", Modern )`.
- [ ] **Step 5: TOC, engine-reads list, locales, golden.** Add the two TOC lines; add
  `src/Hekili/UI/Truth.lua` to `check_engine_reads.sh`'s `ui=(...)`. Run `python3 tools/locales.py`, then
  `ENUS_GOLDEN=update .lua/bin/busted tests/Forever/enus_text_spec.lua` and check `git diff
  tests/Forever/fixtures/enus_text.txt` adds only the Modern strings and the dropdown's new value.
- [ ] **Step 6: Docs.**
  - `docs/dev/architecture.md` §7: the built-in styles list gains modern (`UI/Styles/Modern.lua`: a base layout,
    classic or timeline, plus `UI/Truth.lua`'s overlays; experimental, never the default); a paragraph **Wrapping a
    layout** stating the `base` rule (Task 2) and decision M2 as the one exception to "No style reads another
    style's subtable" (Modern reads the base's config only through the base's own code, and the base's layout state
    only through `Modern.LAYOUT`); "What a style may read" gains `out.acts` (the `Output.Acted` count at the last
    publish, ruling 4). Rulings 1-6 of this plan in one short list under it.
  - `docs/dev/layout.md:35-36`: "the shared truth overlays (`Truth`, the only reader of `Facade.Display`)" and
    `Styles/Modern` in the styles list.
  - `docs/dev/ingame-ledger.md`: row `| MD-TAINT | Core | /console taintLog 1, Hekili with one display on Modern (Primary, base Classic), two pulls on an open-world mob, then a dungeon pull, /reload: Logs/taint.log names no Hekili frame; no "blocked" popup; action bars and Cooldown Manager keep working | research §3: a Modern overlay calls protected widget methods (SetCooldownFromDurationObject) from addon code; a fail keeps Modern developer-only until the culprit is found | open: launch day 2026-11-04 |`.
- [ ] **Step 7: Run to see them pass.** Run: `.lua/bin/busted tests/Forever/display_modern_spec.lua
  tests/Forever/display_style_spec.lua tests/Forever/style_options_spec.lua tests/Forever/enus_text_spec.lua` —
  expected: PASS.
- [ ] **Step 8: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/UI/Styles/Modern.lua src/Hekili/UI/Truth.lua src/Hekili/Hekili.toc tools/check_engine_reads.sh src/Hekili/Locales tests/Forever/display_modern_spec.lua tests/Forever/fixtures/enus_text.txt docs/dev
git commit -m "feat(styles): the experimental modern style wraps classic or timeline (no overlays yet)

The English golden gains the style's label and its Modern tab.

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
- Produces, per `ov` (a button with a `Cooldown` region only; Timeline's lane cells have none): `ov.cd` (a
  `Cooldown` frame, `CooldownFrameTemplate`, all points on the button, the base cooldown's frame level,
  `SetDrawBling(false)`, `SetDrawEdge(false)`, `SetHideCountdownNumbers(layout.hideNumbers)`, and for a round cell
  `SetSwipeTexture(CIRCLE)` / `SetUseCircularEdge(true)`, `CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"`);
  `ov.done` (its `OnCooldownDone` script, made once in Build); `ov.real` (bool), `ov.dur` (held duration object or
  nil), `ov.cdShown` (bool), `ov.charged` (bool), `ov.press` (bool).
- Consumes: `Facade.C_Spell.GetSpellCooldown(spell)` (`.isActive`, `.isOnGCD`, plain), `Facade.Display` (Task 1),
  `Hekili.Engine.Registry.Abilities()[name]` (`rawget(def, "charges")`), the layout accessor (Task 3).

- [ ] **Step 1: Write the failing tests.** Append to `tests/Forever/display_modern_spec.lua`:

```lua
local ACTIVE = { isActive = true, isOnGCD = false, startTime = fake.SECRET, duration = fake.SECRET }
local ON_GCD = { isActive = true, isOnGCD = true, startTime = fake.SECRET, duration = fake.SECRET }

describe("Modern's real cooldown swipe (R2, §3.4)", function()
    it("shows the game's cooldown while it runs and hands the base its own swipe back when it ends", function()
        local H, d = boot("modern", "classic")
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike] = ACTIVE
        H.ctl.cooldown[A.overpower] = ON_GCD
        durations[A.mortal_strike], durations[A.overpower] = fake.SECRET, fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local ov, b = d.styleFrames.modern.ov, d.Buttons
        assert.is_true(ov[1].real)
        assert.is_true(rawequal(fake.SECRET, ov[1].cd.__dur))
        assert.is_true(ov[1].cd.__shown)
        assert.is_false(b[1].Cooldown.__shown)
        assert.is_false(fx.ignore[A.mortal_strike]) -- the press icon's swipe includes the GCD
        assert.is_false(ov[2].real) -- the GCD alone: the base's swipe
        assert.is_nil(fx.ignore[A.overpower])
        H.ctl.cooldown[A.mortal_strike] = nil
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_false(ov[1].real)
        assert.is_false(ov[1].cd.__shown)
        assert.is_true(b[1].Cooldown.__shown)
        -- R2: the base's own delay look (classic's extend) still runs to Hekili's time
        local exact = H.Hekili.Engine.Output.Primary.recs[1].exact_time
        assert.is_true(math.abs(b[1].Cooldown.__cdStart + b[1].Cooldown.__cdDuration - exact) < 1e-6)
        assert.are.same({}, H.errors)
    end)

    it("fetches a queued icon's cooldown without the GCD; ends on the widget's own OnCooldownDone", function()
        local H, d = boot("modern", "classic")
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.overpower] = ACTIVE
        durations[A.overpower] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local ov = d.styleFrames.modern.ov[2]
        assert.is_true(fx.ignore[A.overpower])
        assert.is_true(ov.real)
        ov.cd.__scripts.OnCooldownDone(ov.cd)
        assert.is_false(ov.real)
        assert.is_true(d.Buttons[2].Cooldown.__shown)
        assert.are.same({}, H.errors)
    end)

    it("fetches only on a spell change and the cooldown events, never per frame", function()
        local H, d = boot("modern", "classic")
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
        local H, d = boot("modern", "classic")
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
        H.Hekili.DB.profile.displays.Primary.modern.swipes = false
        H.Hekili:BuildUI()
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_UPDATE_COOLDOWN")
        assert.are.equal(0, fx.n)
        assert.are.same({}, H.errors)
    end)

    it("shows the real swipe again on the first publish after a Clear", function()
        local H, d = boot("modern", "timeline")
        local A = ids(H)
        usableAll(H)
        H.ctl.cooldown[A.mortal_strike] = ACTIVE
        durations[A.mortal_strike] = fake.SECRET
        publish(H, SET)
        frame(H, d, 0.2)
        local T = d.styleFrames.timeline
        local c = T.press
        local ov = d.styleFrames.modern.ov[c]
        assert.is_true(ov.real)
        d.style.Clear(d)
        assert.is_false(ov.cd.__shown)
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_true(ov.real)
        assert.is_true(ov.cd.__shown)
        assert.is_false(T.cells[c].Cooldown.__shown)
        assert.is_nil(d.styleFrames.modern.ov[3].cd) -- a lane cell has no swipe
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
        local H, d = boot("modern", "classic")
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
  - Draw: `local blank = out.count == 0 or out.version == d.blankVersion`; per button `c`, `press =
    S.layout.press(d)`, `i = blank and 0 or S.layout.record(d, conf, c)`, the record `out.recs[i]` when
    `1 <= i <= out.count`; its plain spell: `rec.actionID` when `rec.actionName`, `rec.exact_time`, no `rec.item`
    and `rec.actionID > 0`, else 0. When the spell or `c == press` changed: store them, `ov.charged =
    rawget(def, "charges") ~= nil`, and refresh the swipe. Then apply.
  - The refresh (the only fetch; on a change and on `SPELL_UPDATE_COOLDOWN` / `SPELL_UPDATE_CHARGES` for every
    `ov` with a spell):

```lua
local function swipe( ov, conf )
    ov.real, ov.dur, ov.dirty = false, nil, true
    if not ( conf.modern.swipes and ov.cd and ov.spell > 0 and not ov.charged ) then return end
    local info = C_Spell.GetSpellCooldown( ov.spell ) -- the hybrid: isActive and isOnGCD are plain
    if info and info.isActive and not info.isOnGCD then
        ov.dur = Display.C_Spell.GetSpellCooldownDuration( ov.spell, not ov.press )
        ov.real = ov.dur ~= nil
    end
end
```

  - Apply (Draw, OnGameEvent, `ov.done`): when dirty, either `ov.cd:SetCooldownFromDurationObject(ov.dur)`,
    `ov.cd:Show()`, `b.Cooldown:Hide()`, `ov.cdShown = true`; or, when `ov.cdShown`, `ov.cd:Hide()`,
    `b.Cooldown:Show()`, `ov.cdShown = false`. After every base Draw, `if ov.cdShown then b.Cooldown:Hide() end`
    (a base may re-show its own, e.g. Timeline's `reveal`).
  - Clear: hide every `ov.cd`, show `b.Cooldown` where `ov.cdShown`, reset `real`, `dur`, `cdShown`, `spell = 0`.
- [ ] **Step 4: Ledger row.** `docs/dev/ingame-ledger.md`: `| MD-CD | Warrior | /vslog md cd (research §3): a button-sized Cooldown fed GetSpellCooldownDuration(id, false) on SPELL_UPDATE_COOLDOWN beside the Hekili icon; fight, press Mortal Strike or Bloodthirst and Charge, let them come back. Then the same with a display on Modern: its swipe ends with the action bar's | MDCD set ok every call; the swipe ends on the frame the plain isActive goes false (MDCD end dt within one frame); 0 B per frame between events. Fail: Modern's real swipes off for that kind (a commit sets swipes off in code and cites this row) | open: launch day 2026-11-04 |`.
- [ ] **Step 5: Run to see them pass.** `.lua/bin/busted tests/Forever/display_modern_spec.lua` — PASS, the
  Task 3 cases included (R1 and 0 B with swipes on).
- [ ] **Step 6: Full check and commit.** `flock /tmp/hekili-gate.lock make check` — exit 0.

```bash
git add src/Hekili/UI/Truth.lua tests/Forever/display_modern_spec.lua docs/dev/ingame-ledger.md
git commit -m "feat(modern): the game's own cooldown swipe over the base's while it runs

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
  `OVERLAY` texture on it, all points, `WHITE = "Interface\\Buttons\\WHITE8X8"` or `CIRCLE` for a round cell,
  vertex colour `0, 0, 0, VEIL_ALPHA` with `VEIL_ALPHA = 0.5`); `ov.usable` (plain bool: `IsSpellUsable`'s first
  return); `ov.dim = { ready, want, since, ver, acts }` (preallocated in Build); `ov.dimShown` (bool).
- Produces: `local function settle( g, want, now, ver, acts )` → `g.ready`: the shared debounce for the dim and
  (Task 6) the mark; `local function reset( g, want, now, ver, acts )` (a spell change: no debounce).
- Consumes: `Facade.C_Spell.IsSpellUsable` (plain), `out.version`, `out.acts`, `ns.Output.hold`,
  `Facade.GetTime()` in `OnGameEvent`.

- [ ] **Step 1: Write the failing tests.** Append:

```lua
describe("Modern's usability edge (§3.2)", function()
    local function setup(base)
        local H, d = boot("modern", base or "classic")
        usableAll(H)
        publish(H, SET)
        frame(H, d, 0.2)
        return H, d, ids(H), d.styleFrames.modern.ov[1]
    end

    it("dims at once on SPELL_UPDATE_USABLE when the game says not usable, between pulses", function()
        local H, d, A, ov = setup()
        assert.is_false(ov.dimShown)
        H.ctl.usable[A.mortal_strike] = { false, true }
        H.Fire("SPELL_UPDATE_USABLE")
        assert.is_true(ov.dimShown)
        assert.is_true(ov.veil.__shown)
        H.ctl.usable[A.mortal_strike] = { false, false } -- an unmet proc or condition dims too (plan ruling 3)
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
        assert.is_true(d.styleFrames.modern.ov[lane].dimShown)
        H.Hekili.DB.profile.displays.Primary.modern.edge = false
        H.Hekili:BuildUI()
        publish(H, SET)
        frame(H, d, 0.2)
        H.Fire("SPELL_UPDATE_USABLE")
        for c, ov in ipairs(d.styleFrames.modern.ov) do
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
        assert.is_true(d.styleFrames.modern.ov[4].dimShown)
        publish(H, SET_ONE)
        frame(H, d, 0.2)
        for c = 2, #d.Buttons do
            assert.is_false(d.styleFrames.modern.ov[c].dimShown, "button " .. c)
        end
        H.ns.Output.Begin("Primary")
        H.ns.Output.Publish("Primary", 0)
        frame(H, d, 0.2)
        for c, ov in ipairs(d.styleFrames.modern.ov) do
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
  ov.usable, now, out.version, out.acts )`, apply. Apply: `dim = conf.modern.edge and ov.spell > 0 and not
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
- Produces, per `ov`: `ov.glow` (plain: the button is the press or focus button, `conf.modern.confirm`, and
  `d.resolved[i].glow`), `ov.mark = { ready, want, since, ver, acts }`, `ov.markShown` (bool). The mark is
  `LibCustomGlow`'s `AutoCastGlow_Start( b, MARK, nil, nil, nil, nil, nil, KEY )` / `AutoCastGlow_Stop( b, KEY )`
  with `KEY = "modern"` and `MARK = { 1, 0.8, 0.1, 1 }` (Timeline's gold, built once), apart from the base's own
  glow (no key) and Timeline's ready glow (`"focus"`).
- Consumes: `S.layout.press(d)`, `S.layout.focus(d)`, `d.resolved[i].glow`, Task 5's `settle`.

- [ ] **Step 1: Write the failing tests.** Append:

```lua
describe("Modern's proc mark (R3, M11)", function()
    it("marks the next icon when the game lights its overlay, never a queued one", function()
        local H, d = boot("modern", "classic")
        local A = ids(H)
        usableAll(H)
        overlayed[A.mortal_strike], overlayed[A.overpower] = true, true
        publish(H, SET)
        frame(H, d, 0.2)
        local ov = d.styleFrames.modern.ov
        assert.is_true(ov[1].markShown)
        assert.is_false(ov[2].markShown)
        assert.are.same({}, H.errors)
    end)

    it("marks the focus cell and the next box on a timeline base, never a lane icon", function()
        local H, d = boot("modern", "timeline")
        local A = ids(H)
        usableAll(H)
        for _, e in ipairs(SET_FOCUS) do
            overlayed[A[e[1]]] = true
        end
        publish(H, SET_FOCUS)
        frame(H, d, 0.2)
        local T, ov = d.styleFrames.timeline, d.styleFrames.modern.ov
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
        local H, d = boot("modern", "classic")
        local A = ids(H)
        usableAll(H)
        H.ns.Output.hold = 3
        overlayed[A.mortal_strike] = true
        publish(H, SET)
        frame(H, d, 0.2)
        local ov = d.styleFrames.modern.ov[1]
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
        H.Hekili.DB.profile.displays.Primary.modern.confirm = false
        H.Hekili:BuildUI()
        publish(H, SET)
        frame(H, d, 0.2)
        assert.is_false(d.styleFrames.modern.ov[1].markShown)
        assert.are.same({}, H.errors)
    end)

    for _, base in ipairs({ "classic", "timeline" }) do
        it("allocates nothing over 1,000 frames with a real swipe, a dim and a mark showing on " .. base, function()
            local H, d = boot("modern", base)
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
            local ov = d.styleFrames.modern.ov
            local press = H.ns.UI.Styles.modern.LAYOUT[base].press(d)
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
  conf.modern.confirm and ( c == press or c == focus ) and i >= 1 and d.resolved[ i ].glow or false` (so a spell
  change `reset`s the mark from the new record's glow, and a glow that appears later settles like the dim). Tick and the usability event: `settle( ov.mark, ov.glow
  and ov.usable, now, out.version, out.acts )` beside the dim's (a spell change `reset`s it); apply `mark =
  ov.mark.ready and not ov.dimShown` (R3: never on a dimmed icon), starting or stopping the keyed glow only on a
  change of `ov.markShown`. Clear stops every mark and resets `markShown`.
- [ ] **Step 4: Changelog.** `CHANGELOG.md`, Unreleased, New:
  `- New experimental display style, Modern (game truth): your Classic or Timeline layout with the game's own cooldown swipes, an immediate grey when the game says an ability cannot be used yet, and a glow on the next ability when the game lights its proc. Hekili still decides what to show; pick it in a display's Style to try it.`
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
- **Timeline's `oocTimers` off** hides the base's sweeps out of combat; Modern's real swipe still shows a running
  cooldown there. Decide with the owner whether the real swipe follows that setting.
- **Promotion:** Modern stays experimental until the three probes pass and the owner's checklist (spec §8, in game
  only) is walked.
