# Timeline Focus Candidates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let APL lines be marked `focus=1` so the Timeline's Now circle becomes an attention zone (a flagged ability predicted within the horizon shows there with a countdown while the immediate press moves to the Next box); add ruler styles, per-zone option tabs and equal gaps to the Timeline; title every style's options group "Style".

**Architecture:** one additive entry flag flowing SimC text → pack tool → importer → editor → `entry.focus` → `slot.focus` on the published record; the Timeline assigns zones by role (press / focus / lane) instead of by record index; everything that means "the key to press" follows the press record's cell. Ruler styles draw from one preallocated texture pool. No engine behaviour change: gates and fixtures stay byte-identical.

**Tech Stack:** Lua 5.1 (WoW), AceConfig, busted headless harness, `tools/make_pack.lua`.

**Spec:** the Design section below, approved by the user 2026-10-18 (display-styles plan `docs/superpowers/plans/2026-10-18-display-styles.md` is the parent design; its Global Constraints apply).

## Global Constraints

- No new tables, closures, varargs, string building or `C_Timer.After` in recurring paths (Draw, Tick, publish); preallocate at Build.
- UI never reads `state.*`/`class.*`; `tools/check_engine_reads.sh` enforces it.
- `make check` green before every commit (`git diff --exit-code src` inside it needs a clean or staged tree).
- Recommendations byte-identical: `make test-loop` `Arms solo:` line unchanged except timings; `tests/Forever/arms_recs_spec.lua` fixture untouched; the classic fixture `tests/Forever/fixtures/classic_draw.lua` untouched; `make test-druid` green when the Druid pack changes.
- Styles stay isolated; a style reads only `Engine.Output[id]`, `Output.status`, `d.resolved` and its own subtable.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. With a focus record in the Now circle, every "press" affordance (keybind text, glow, flash, range tint, cast highlight, `OnGameEvent` glow, alternatives) must sit on the cell that draws record 1, never on cell 1 by index. Test in Task 2: the fixture asserts keybind/glow state per cell with focus on and off.
2. A reused record must not carry a stale `focus` from a previous publish. Test in Task 1: publish a flagged record, then an unflagged set in the same slot; `focus` is nil.
3. A profile saved before this change has no `gap` and may have `nextOffset`; it must render with the same spacing as before. Test in Task 2b: derive `gap` once from `nextOffset`, assert the cells' anchors are unchanged.
4. The focus horizon must never exceed the lane horizon or a flagged record beyond the lane would occupy Now with a countdown the lane cannot show. Test in Task 2: `focusHorizon` clamped.
5. `focus=1` must survive a pack round trip (parse → unparse → parse) and the in-game import path, and an unknown option must still error in the tool. Test in Task 1.

---

## Context

The Timeline style (forever 963c301c) maps records by index: record 1 in the Now circle, record 2 in
the Next box, 3+ on the lane. The user wants Now to be an attention zone: APL lines marked as focus
candidates (e.g. Feral's `rip`) take over the Now circle with a countdown whenever the engine's predicted
sequence shows them coming within the lane horizon, even when they are not the first priority. The
immediate press then shows in the Next box (user's choice), and "on the horizon" means "present in the
published records within the horizon" (user's choice; no extra engine work).

Research (2026-10-18): TDF had no such flag; its Now was always the immediate press, so this is new
design. Hekili facts: SimC `k=v` options are whitelisted in `tools/make_pack.lua:17-41` (`name`,
`use_off_gcd`; `if=` must stay last) and written back by `unparse` (60-66); the in-game importer
(`Options.lua:8165-8206`) stores unknown keys verbatim and numbers only listed ones; the pack editor's
per-entry controls (`Options.lua:5297-5804`) use generic `GetActionOption`/`SetActionOption`
(4008/4059) with `toggleToNumber` (3979) and `review_options` (4049); Core copies entry data onto the
record at `Core.lua:1107-1109` (wait branch) and `1224-1226` (`slot.caption`, `slot.indicator`); the
Timeline assigns zones in `assign` (`Timeline.lua:467-568`), countdown in `Tick` (617-622) via
`showEta` (396), lane placement in `moveLane` (426); `Draw` (629-687) applies range, usability, glow,
wait edges to cells 1-2 and the target count to cell 1. (Line numbers at 963c301c.)

Also folded in: every style's options group is titled "Style" instead of the style's label
(`Options.lua:1683`) so the editor looks unchanged.

## Design

**Flag.** `focus=1` on an APL line (`actions+=/rip,focus=1,if=...`). Stored as `entry.focus = 1`.
Per line, not per ability.

**Record.** `slot.focus = entry.focus` (nil or 1) written at both Core copy sites, unconditionally so a
reused record is cleared. Additive. Classic ignores it.

**Timeline zone rule** (replaces the fixed index mapping):
- `press` = record 1 (always the thing to press now).
- `focus` = the earliest record i ≥ 2 with `focus` and `exact_time - now ≤ tl.focusHorizon` (default =
  lane horizon, clamped to it). Record 1 never counts.
- If `focus` exists: Now circle ← focus record, countdown to its `exact_time`, no keybind, a gold
  "focus" ring (`focusColor`); Next box ← press record with the full press look (keybind, glow, flash,
  range, cast highlight, target count, alternatives of record 1); lane ← every other record, excluding
  the focus record.
- Else: today's layout (Now ← press, Next ← record 2, lane ← 3+).
- Everything that means "the key to press" follows the press record's cell. Alternatives follow their
  record wherever it is drawn.
- Options: `focusEnabled` true, `focusHorizon` 10, `focusColor` gold rgba.
- *2026-10-18, user decision:* the "Else" fallback changed. Without a focus record the Now circle is empty
  and the Next box always draws the press (record 1), the lane 2..; the layout above stays behind
  `nowFallback = "press"` (default `"empty"`).

**Ruler styles.** `rulerStyle` ∈ { `ruler` (today: baseline + a tick a second, taller every
`majorEvery`), `dots` (one small square per second, no baseline), `lines` (short vertical per second, no
baseline), `center` (one line through the vertical centre of the lane rows, no ticks) }, drawn from the
same preallocated texture pool; `rulerColor` rgb (white), `rulerAlphaCombat` 0.5, `rulerAlphaOOC` 0.25,
applied when `status.combat` flips (in Draw, not per frame).

**Per-zone tabs.** The timeline's `Options(id, conf)` returns four tabs inside its "Style" group: Now,
Next, Lane, Timeline. Zone tabs hold the zone's layout fields then its per-zone shared groups
(`src/Hekili/Options/StyleOptions.lua` builders, zones as the settings analysis allows). The Timeline tab
holds `horizon`, `pxPerSec`, `direction`, `rows`, `rowGap`, `laneHeight`, the ruler fields, `laneAlpha`,
`laneDim`, `glide`, and the Focus section. Tab keys must not collide with config keys (the nested getter
descends only into existing keys): `tab_now`, `tab_next`, `tab_lane`, `tab_timeline`; option keys stay
flat in `displays[id].timeline`.

**Equal gaps.** One `gap` field (default = today's visual Now→Next gap) drives both spacings:
`nextX = nowX + nowSize + gap`, `laneX0 = nextX + nextSize + gap`. `nextOffset` leaves the defaults; a
profile that has it gets `gap = nextOffset - nowSize` once, then `nextOffset = nil`. The ruler's first
mark sits at `laneX0`.

**Content.** Feral `rip` lines get `focus=1` in the Druid pack SimC (`tools/packs/druid/*.simc`;
`make packs` regenerates `src/Hekili_Forever_Druid/Druid.lua`; bumps the pack date so saved profiles
report "updated" once). No Warrior lines yet.

---

## Tasks

Each task is one reviewed commit set on `forever-focus`; `make check` green; gates per Global Constraints.

### Task 0: Style tab title
- [ ] `src/Hekili/Options/Options.lua` ~1683: `name = style.label` → `name = "Style"`.
- [ ] `docs/dev/architecture.md` (the `label` row, ~201): add "the options group itself is always titled Style".
- [ ] `make check`, commit.

### Task 1: the `focus` entry flag end to end
**Files:** `tools/make_pack.lua`, `src/Hekili/Options/Options.lua` (importer ~8196, editor ~5734 area, `toggleToNumber` ~3979, `review_options` ~4049), `src/Hekili/Engine/Sim/Core.lua` (~1107, ~1224), `src/Hekili/Engine/Output.lua` (record template); tests `tests/Forever/make_pack_spec.lua` (or the existing pack spec), `tests/Forever/output_spec.lua`.
- [ ] Specs first: pack round trip of a line with `focus=1` (parse → unparse → parse equal; `if=` still last; unknown key still errors); `output_spec`: `focus` copied from the entry onto the record, and nil after a publish whose entry has no flag in the same slot.
- [ ] `make_pack.lua`: `OPTIONS.focus = "focus"` numeric; `unparse` writes `focus=1` when set.
- [ ] Importer: `focus` numeric; editor: "Focus candidate" toggle beside `use_off_gcd` (`toggleToNumber`, `review_options`), description: "Timeline style: when this entry is predicted within the focus horizon it takes the Now circle."
- [ ] Core: `slot.focus = entry.focus` at both copy sites; Output template gains `focus`.
- [ ] `make check`; `Arms solo:` unchanged; `arms_recs` untouched; `make packs-check` clean; commit.

### Task 2: Timeline focus zone
**Files:** `src/Hekili/UI/Styles/Timeline.lua`; test `tests/Forever/display_style_spec.lua` (timeline describe), fixture `tests/Forever/fixtures/timeline_draw.lua` (re-recorded).
- [ ] `assign` computes `press`/`focus`/lane per the rule; `Draw`/`Tick`/`OnGameEvent` index by role; countdown + gold ring on the focus cell; options `focusEnabled`, `focusHorizon` (clamped), `focusColor`.
- [ ] Fixture spec: record 3 flagged within horizon → Now = record 3 with ETA and no keybind, Next = record 1 with keybind + press look (glow/flash/range on that cell), lane = records 2, 4.. not 3; `focusEnabled = false` or record 3 beyond `focusHorizon` → today's layout; alloc 0 B over 1,000 frames. Classic fixture untouched.
- [ ] `make check`, commit.

### Task 2b: ruler styles, per-zone tabs, equal gaps
**Files:** `src/Hekili/UI/Styles/Timeline.lua`, `src/Hekili/Options/StyleOptions.lua` if a builder needs a new zone, tests as Task 2 plus an options spec.
- [ ] Ruler styles per the Design from one texture pool; alpha on combat flip in Draw.
- [ ] Four tabs; every field resolves through `Hekili:GetDisplayOption` to `displays.Primary.timeline.<key>` (spec).
- [ ] `gap` replaces `nextOffset` with the one-time derivation; the cells' anchors are unchanged for a profile that had `nextOffset` (spec); `laneX0 = nextX + nextSize + gap`.
- [ ] Fixture: one describe per ruler style (texture count, positions, shown), gap equality from anchors, alpha switch on a combat flip; alloc 0 B.
- [ ] `make check`, commit.

### Task 3: content + docs
- [ ] Feral `rip` lines get `focus=1` in `tools/packs/druid/*.simc`; `make packs`; `make packs-check` clean; `make test-druid` green.
- [ ] `docs/dev/architecture.md`: the `focus` record field and the Timeline zone rule; wherever the fork documents SimC line options for pack authors (search `use_off_gcd` under docs/ and `src/Hekili_Forever*/README.md`; if nowhere, add a short "APL line options" list to `docs/dev/architecture.md`), add `focus=1`.
- [ ] `make check`, commit.

## Verification
- `make check` green; `Arms solo:` unchanged; `arms_recs` and classic fixtures untouched; Druid gate green; timeline fixture compare green after re-record.
- In game (`/reload`): Feral Primary on Timeline: with Rip up and ~4 s left, Now shows Rip counting down with the gold ring, Next shows the actual press with keybind and glow; when Rip is the press, Now shows Rip as before; classic display unchanged; the entry editor shows the Focus toggle on the rip entry; every style tab reads "Style"; ruler style switches live; Now→Next and Next→lane gaps equal.

### Task 2c: no lane overlap with the Next box; out-of-combat pinning (user, 2026-10-18, in-game screenshot)

**Files:** `src/Hekili/UI/Styles/Timeline.lua`; tests `tests/Forever/display_style_spec.lua` (timeline describe), fixture re-record allowed.

**No overlap.** A lane icon's x is `max(0, tRel) * pxPerSec` from `laneX0`, so an icon whose predicted time is
already past (negative `tRel`) sits at the lane start, never left of it; icons beyond `horizon` stay hidden.
`laneX0` is after the Next box plus `gap` (Task 2b), so the lane can never reach the Next cell. Row stacking
(`rowGap`) still separates icons that land on the same x.

**Out-of-combat pinning.** When `status.combat` is false, lane positions and countdowns use press-relative
time, `tRel = rec.time - recs[1].time` (the engine's simulated offsets, which only change when the
recommendation set changes), instead of `exact_time - GetTime()`. In combat, wall-clock as today. Option
`oocPinned` (default true) in the Timeline tab. Effect: out of combat the lane is still between publishes
and moves only when a different sequence is published; the per-refresh slide-then-jump ("bounce") from
the simulated swing timer disappears. The Now/Next cells keep showing the press (record 1) and its ETA
relative to the press (0 when pinned).

- [x] Spec: with `status.combat = false`, a published set whose `exact_time`s shift by 0.2 s per publish
  with unchanged `time` offsets produces identical lane anchors across publishes and frames (no
  movement); the same set in combat moves with the clock; a record with negative relative time anchors
  at `laneX0`; a record beyond `horizon` is hidden; alloc 0 B.
- [x] `make check`, commit; the implementer commits this plan section's file with its work.
