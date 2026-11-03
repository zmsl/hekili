# Full wowsims re-pin and the Movement toggle (design, 2026-11-03)

Status: APPROVED for planning, revised the same day to the owner's movement ruling (decision 6) and the builder
check's rulings (decision 8), then to the owner's waits ruling (decision 9), the Retribution opener ruling (decision 10)
and the rotation windows design (decision 11, §3a). A design, not a plan:
intent, goals, decisions and what is left to the builder. Branch `forever-repin` from `origin/forever` 0d98cb02c.
Paths are under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`.

Research this rests on: the sizing research (audit `followups/repin-research.md`, 2026-11-03: the changed APLs, the
new proto kinds, the SIML converter, the request changes, a suggested order). Its dry translation of every recipe
against the trees at both commits is the source of every omit count below. Ledger: the open-questions file, under
"2026-11-03 — full wowsims re-pin started".

## 0. The owner's decisions (binding)

1. Re-pin target: the recipes' APLs and requests move to the current sim pin e2842f0a78 (the oracle's commit),
   hunters included. `M.OLD_SIM` goes away. The work merges after launch, in the first post-launch release, not
   before.
2. "I want to be as true to the rotations as possible." Where a rotation moves to reach the next ability, that ability
   is displayed out of range, with Hekili's normal out-of-range tint. "Any spec where movement is considered must have
   movement toggleable." The Movement toggle starts ON. The specs whose new APLs move: the Hunters (the weave builds),
   Feral and Guardian (the adaptive APLs), Retribution, and Demonology (the brand builds).
3. "For movement modeling, just follow what we need to to prove the rotation accuracy." The replay already follows
   wowsims's Movement aura. No speed buffs unless a gate needs them.
4. Accuracy must stay close. Floors move only with a named, traced cause. No jittery recommendations: flicker is an
   acceptance metric.
5. (2026-11-03, this replaces the open Hunter question.) "When movement is off, abilities that assume movement to use
   should be hidden." Every spec keeps its one translated rotation. The Hunters keep the weave builds; there is no
   switch to wowsims's Turret, Turret Hawk or Melee APLs.
6. (2026-11-03, this narrows decisions 2 and 3.) "We shouldn't have to have any movement stuff in hekili or our
   beliefs. The movement is just for the test world and ONLY IF it helps us prove rotational match between our apl
   through hekili and wowsims."
7. (2026-11-03, the owner's answers to this spec's checks.)
   - The ON form is the variant: a move-reached entry shows out of range only when the move entry's own conditions
     hold (§2.2).
   - "We should be testing exactly how wowsims rotation is working. If the apl assumes movement, we should as well,
     which is effectively testing 'on'." The replay gate scores with Movement ON for every spec whose APL moves. OFF is
     covered by the per-spec toggle tests only.
   - Fresh floors for Retribution, Feral, Guardian and the Hunters are approved ("ok"). Each one's top disagreements
     are classified first, and the re-pin is named as the cause.
   - Pre-pull moves: "as long as it matches wowsims". They stay omitted from the display. A replay disagreement traced
     to one is a defect to fix, not a floor cost (§2.3).

8. (2026-11-03, the builder check's rulings. Binding; where they meet older text below, they win.)
   - Fresh-floor rule (owner "yes"): a fresh floor (Retribution, Feral, Guardian, the Hunters) ships only if every
     remaining top disagreement is classified unfixable: API-forced, or a gap already in `docs/dev/gaps.md`. Any
     fixable cause (kit, world, translator, engine) blocks the merge until it is fixed.
   - Movement terms (owner "ok"): every movement term is dropped from translated conditions: run speed
     (`unitMovementSpeed`), "is moving" (`unitIsMoving`, any unit) and arithmetic on yards (`unitDistance` inside
     `math`, `min`/`max`, or compared with anything but a whole-number constant). The rest of the condition decides.
     A dropped term reads as wowsims's nil (rule 6): it leaves its `and`/`or`, and a comparison or `math` over it is
     nil too. This supersedes every "falls to false", "reads false" and "constant run speed" text. Hekili holds only
     the Movement toggle, the client's range gate (rule 11's bracket, `spellInRange`) and the rotation's timing terms.
     The ranged auto-shot clock (C7) stays, as a belief timer, because the timing part of the weave's move
     condition reads it.
   - ON flicker is measured: the replay runs ON (decision 7), so each opted-in spec's replay gate line carries an
     ON flicker figure with a ceiling. The no-jitter rule applies to the default, which is ON.
   - Phase 0: a baseline `make accuracy` run on `forever` 0d98cb02c before any change (it takes the gate lock
     itself). The floors' baseline in §7 is that run.
   - Phase 1 first verifies that the CLI built at e2842f0a78 has the `siml` subcommand.
   - Settled in the plan (`docs/superpowers/plans/2026-11-03-wowsims-repin.md`): the Movement toggle's core UI
     (options row, minimap menu, chat command, keybind, profile default; class-neutral), how the replay answers range
     brackets and `spellInRange` at wowsims's logged distances (the real client path, the unknown bracket
     included), and how Retribution's "Move to melee" group translates (a group of `sequence`s, rule 14's chain).

9. (2026-11-03, the owner's waits ruling: "yes". Modelling waits in Hekili is bad practice; use Hekili's
   capabilities. Binding; it replaces every "waits translated if phase 3 earns them" text.)
   - wowsims `wait` and `waitUntil` are never translated into packs. No `wait,sec=` line, no translator flag, no
     phase-3 measurement of waits.
   - The weave's timing variables ("Just shot", "Windup close", "Weave fits", "Wait at melee" and the rest) are
     translated as APL variables and conditions on clocks: the melee swing clock (`mainhand_remains`, and the time
     since the last main-hand swing) and the ranged auto-shot clock (C7). Walk-time terms still drop (decision 8).
   - The engine's existing recheck forecast (`Engine/Sim/Core.lua`, `script.Recheck` / `state.recheck`) turns "true
     in t" into the icon's countdown. That is the replacement for the waits, so the ranged clock's expressions must
     produce recheck times the way `mainhand_remains` does.
   - Raptor Strike's queued aura resolves at the next main-hand swing (`mainhand_remains`, not a full
     `mainhand_speed`), so a queued strike is not re-recommended and the pick after the swing is made without it.
   - The Hunter replay with Movement ON measures the result; the fresh-floor rule (decision 8) applies.
10. (2026-11-03, the owner's ruling on Retribution's opener and on what "shown out of range" means. Binding.)
   - Retribution's "Move to melee" sequences (`move1`-`move3`) must match wowsims, which runs each once per fight, at
     the pull. Their `not sequenceIsComplete(<own name>)` is not dropped: it becomes a pull-only gate, the closest a
     stateless list can come (the plan's S3 picks it: no main-hand swing has landed this combat). The opener never
     returns mid-fight, even out of melee after a knockback.
   - No movement cue or movement icon is ever shown to the player. "Shown out of range" means only the ability's own
     icon with Hekili's normal out-of-range tint.
11. (2026-11-03, the owner's rotation windows design: "WINDOW DESIGN APPROVED"; it supersedes the core-persisted
   version. Binding; §3a holds the detail, and where it meets §3's weave text, §3a wins.)
   - A window is a first-class span, not a buff: `spec:RegisterWindow(name, { evaluator, duration, refresh,
     max_duration?, max_refresh? })`, handed to the belief through `Build(def)` the way an ability's `now()` is. Both
     caps are optional; a refresh with no cap is allowed.
   - The belief owns the real windows: inside `Drain`, after the fold, it runs each evaluator and applies edge
     semantics, the duration and the caps; it clears them at combat end. `now()` on a real cast may open or close one.
   - The core reads them through a new, dedicated window facade read (owner "yes"; explicitly not the aura copy). This
     is the one new crossing this design adds.
   - The core stays stateless: each cycle starts from the copy. `open_window` / `close_window` APL lines and `handler()`
     change windows only in that cycle's forecast; the recheck forecast gives an `open_window` line's countdown.
   - Guard (owner "ok"): a harness replay check that every open the forecast predicts is opened by the belief's
     evaluator within one poll (drift is flicker).
   - Windows only where no aura fits (owner, 2026-11-03: "I don't want windows to be used in places where auras
     naturally fit. However, when a real 'is usable' for Mongoose Bite, Revenge, etc. flips, it could open a window if
     there is no buff to track."). A window is only for a span with no real aura behind it. Where the client has an
     aura, even a hidden one such as Defensive State (5302) when it is readable, the aura stays. An observed usability
     flip (`IsSpellUsable` going true) may open a window when no aura tracks it; that window closes when usable flips
     back, when the ability is cast, or at its duration.
   - The hunter weave is the first user (§3a). Migrating hand-rolled spans, and new windows elsewhere, are follow-ups.
   - Stepped windows (owner "yes", 2026-11-03): a window may carry `steps` (ability keys in order), `loop` and
     `on_deviation` ("stay", the default and wowsims-true; "skip"; "end") and `strict` (default false: any other on-GCD
     cast ends it; a wowsims `strictSequence`). The
     belief advances the step on the observed real cast of the due step's ability; the core's forecast advances it
     in that cycle only ("the apl would be able to 'persist' the fact that the player already used one of the
     sequence and it recommends the next, which would mark it in the core Hekili state as used only"), never written
     back. A wowsims `sequence` translates to one (§3a); the actual sequences are translated in the Retribution and
     Hunter lanes, gated.

The standing constraints apply unchanged (the border's one new read is decision 11's):
- The core stays class-neutral. The Movement toggle is a generic setting that packs opt into.
- The belief/core border holds: the only new crossing is decision 11's window facade read (owner "yes").
- Secrets are guarded with `issecretvalue`.
- Recurring paths do no allocation.
- The addon is display only.

## 1. Goals and non-goals

Goals:
- Every one of the 26 recipes reads its APL, build and gear at e2842f0a78, with `M.PIN == M.SIM_PIN`. Every
  checked-in request and log is re-exported on one CLI.
- The translator handles every new kind a shipped APL uses that the client lets us show. Every other kind is an
  omission, listed as rule 2 does today.
- Movement in Hekili is a toggle and one translator rewrite (§2). Nothing else. No movement cue or movement icon is
  ever shown: an ability "shown out of range" is its own icon with Hekili's normal out-of-range tint (decision 10).
- The oracle patches the re-pin makes unnecessary are dropped: `leftover_db.go`, and `no-cast-end-pick.patch` once
  `spellIsCasting` is translated.
- Accuracy stays close to the pre-re-pin baseline, and every floor that moves names its traced cause.

Non-goals:
- Any model of position or movement in the engine or the belief. That rules out a simulated move, a simulated walk,
  `state.setDistance` for moves, run speed, speed buffs and target movement.
- Moving past e2842f0a78. A newer upstream gets a second bump later.
- New packs (Frost mage, Retribution Holy Shock).
- SIML in the addon or the translator. The converter is a tools step only.
- Automation.

## 2. The Movement toggle

### 2.1 What it is

Movement is a generic setting, read in the simulation as `toggle.movement`, default ON. The core names no spec. A spec
opts in through data; the builder chooses the form (a spec field the class file sets, or a flag the generated pack's
header carries when the translator emitted a movement term). Its options row, beside Cooldowns, Defensives and
Potions, appears only for a spec that opted in. Whether it also gets a keybind like those toggles is the builder's
call.

### 2.2 How a move translates

wowsims's `move` entries stay omitted, as rule 2 does today. A distance-only `waitUntil` (Feral and Guardian's "finish
closing to melee") is omitted too: it exists only to hold the rotation during the move.

The one change is to the entries a move reaches, meaning those wowsims casts after moving. Each one's range gate
becomes `(toggle.movement&<the move's condition>|<its range gate>)`, the form decision 7 chose. The move's condition
is its own entry's condition, translated by the usual rules and including its distance term. The range gate is the
`unitDistance` term (rule 11's `target.within<N>`/`outside<N>`), the `spellInRange` term, or the omitted
`waitUntil`'s condition, carried onto the lines it held.
- ON: the entry passes its gate where wowsims would move to reach it. The ability shows when the rest of its own
  condition holds, and the client's range read tints it out of range (`UI/Resolve.lua`'s `inRange`, drawn by Classic
  and Timeline today).
- OFF: the real range bracket decides, so the entry is hidden until the player is in range (decision 5).

The move conditions read three kinds of term:
- The ranged clock (the weave's "more than 0.5 s to the next shot"): see §3. Kept: a timing term.
- Range brackets (rule 11's whole-yard comparisons, `spellInRange`): kept, the client's range gate.
- Movement terms (run speed, "is moving", arithmetic on yards such as a walk time): dropped, as decision 8 rules,
  wherever they appear (not only in carried move conditions). Each dropped term is listed in the recipe header.

Nothing in the engine or the belief changes. The rewrite reads only a setting and the range bracket that exists
today. An unknown bracket (no plain range answer yet) still answers both sides (rule 11), so OFF can show a
move-gated line before the first answer. That rule is kept and documented beside the new one.

Which entries a move reaches is the translator's derivation, recorded per spec in the recipe header: those under the
move in the same list whose range gate is the move's target range. A line reached by two moves (the weave's
walk_in and its melee move) takes one `toggle.movement&(...)` term with the conditions joined by "or".

### 2.3 Where it applies at e2842f0a78

| Spec | Move reached entries | ON | OFF |
| --- | --- | --- | --- |
| Hunter BM / MM / SV (weave) | Raptor Strike, Mongoose Bite (`within5`); the shots (`outside5`) after the move back | Strikes tinted at range while the weave's move condition holds; shots tinted in the dead zone after a strike | Strikes only within 5, shots only outside it (today's pack) |
| Feral (adaptive) | The damage lines after "Finish closing to melee" | Shown, tinted, out of melee | Hidden until in melee |
| Guardian (adaptive) | As Feral; Feral Charge is a cast and stays as it is | As Feral | As Feral |
| Retribution (default) | The melee lines the "Move to melee" group (`not spellInRange(Crusader Strike)`) defers | Shown, tinted | The group's ranged lines only, until in range |
| Demonology (brand) | The melee-range AoE behind the 3-target move | Shown, tinted | Hidden until within 5 |

Pre-pull "pull range" moves (the hunters' and Retribution Holy Shock's, at -19 / -20 s) stay omitted from the
display and reach no rotation entry. They still match wowsims because the replay starts us at the request's
distance and then follows the log's Movement aura. Our position at the pull is wowsims's, so the pre-pull walk is
already in the test world's truth (decision 7). A replay disagreement traced to a pre-pull move is a defect to fix (in
the replay's placement or the translation), never a floor cost.

## 3. Waits, and the ranged clock

wowsims's `wait` holds the rotation for a duration, and the weave times several waits from the ranged auto-shot.
Under decision 9 no `wait` or `waitUntil` is ever translated into a pack. Hekili's own capability replaces them: each
evaluation stays stateless, and a line whose condition will be true in t seconds is shown with that countdown by the
engine's recheck forecast (`Engine/Sim/Core.lua`: `script.Recheck`, `state.recheck`, the `delayMin` it sets). The
recheck parser (`Engine/Sim/Scripts.lua`, `ConvertTimeComparison`) finds a comparison on a term ending `remains` (the
`decreases` table), which is how `mainhand_remains<x` already forecasts.

- (Where §3a's weave window covers a timing variable, §3a wins: "Just shot" is read from the window.) The weave's
  timing variables are translated as variables on the clocks. "Just shot" (time since the last Auto Shot
  under the input delay), "Windup close", "Weave fits" (next shot plus the allowed delay against the weave's end) and
  "Wait at melee" read `ranged_remains`, `ranged_speed`, `mainhand_remains` and `mainhand_speed`. Their walk-time
  terms ("Time to walk in", `unitMovementSpeed`) drop (decision 8), and the rest of each condition decides.
- A `wait` whose end is a clock read becomes no line: the lines it held take its end as a clock condition, so the
  forecast shows their countdown. A `wait` with any other end is omitted and listed in the recipe header.
- "Time since the last swing" is written as a `remains` comparison (`autoTimeSinceLast < x` becomes
  `ranged_remains>ranged_speed-x`, and the same for the main hand), because the parser does not see
  `(ranged_speed-ranged_remains)` as a clock. This changes today's main-hand row too.
- Non-distance `waitUntil` entries (Protection Paladin, Rogue pooling) are omitted. Where the lines they held do not
  already carry the same condition, it is carried onto them as a condition (as §2.2 carries a distance-only one), so
  the forecast times them. Each is listed in the recipe header.
- Raptor Strike's queued aura (`Hekili_Hunter/Hunter.lua`, applied in `reset_precast` while `IsCurrentSpell`) lasts
  until the next main-hand swing (`mainhand_remains`), like the Warrior's `onNextSwing` abilities resolve at the
  swing, not a full `mainhand_speed`.

The ranged auto-shot clock (class-completion C7) is needed: the weave's move condition and its timing variables read
`autoTimeToNext RangedAuto` (§2.2). It is a timer in the belief, not movement: Auto Shot's swing clock (hand 3,
`Game/State/Sources/Swing.lua`), already built and merged. It reaches the engine through the existing
`UnitRangedDamage` tail (`state.swings.ranged_projected` / `ranged_speed`). The only new code is an engine expression
twin of `mainhand_remains`, named so the recheck parser forecasts it. C7's in-game questions (layout.md H2-H5) stay
open until launch. Until they are answered, the in-game ON display rests on a modelled clock; the replay feeds it from
the log.

`startAttack` and `petAttack` stay omitted.

## 3a. Windows

A window is a rotation span the client shows no aura for: "since the last Auto Shot, while the main hand was ready,
until the weave's strike". Decision 11 makes it first-class. It is not a buff and is never read as one.

Registration. `spec:RegisterWindow(name, { evaluator, duration, refresh, max_duration?, max_refresh?, close_on_false? })`
in the class file. `evaluator` is a function of the belief's reads returning a boolean; `duration` (seconds) is how
long an open lasts; `refresh` (boolean) lets a new open edge while open restart the duration; `max_duration` caps the
span from the first open, `max_refresh` the count of refreshes (both optional, either alone, neither allowed: then
a closer ends it, or the duration). `close_on_false` (default false) closes the window on the evaluator's true→false
edge: the form a usability-flip window takes (below). It reaches the belief as a plain record in `Build(def)`
(`def.windows`), exactly as an ability's `now` does today: `Engine/Schema/Tracked.lua`'s `recordOf` copies a
registration's raw fields and flattens `funcs` beside them, so a function field crosses as the function itself; the
belief rebinds it with `setfenv` into its own context (`Game/State/Families/Now.lua`, `A.now[a] = setfenv(f, ctx)`) and
never runs it under `state`. An evaluator crosses the same way, into the same context, with the same rules (it captures
no `state`, `Hekili` or `class`; `tests/Forever/plain_records_spec.lua` walks its upvalues).

The belief (real windows). Inside `Drain`, after the fold, the belief runs each evaluator once, in order:
- reads only: the `now` context's reads (resources, `buff`/`debuff`, `talent`, the swing clocks, `now`, `combat`) plus
  the swing reads a weave needs (the last observed swing and the next projected one, per hand) and `usable.<key>` (the
  last plain `IsSpellUsable` answer). Every read is `issecretvalue`-guarded where it can be secret; no allocation.
- edges: each window remembers its last evaluation. false→true opens a closed window, or, with `refresh`, restarts an
  open one's duration (one refresh per new edge, counted against `max_refresh`, bounded by `max_duration`). A
  condition held true does nothing. true→false closes it only with `close_on_false`. A close acts only on an open
  window.
- expiry: an open window closes at its duration (or its `max_duration` cap).
- `now()` on a real cast may open or close a window (`openWindow(name)`, `closeWindow(name)`, verbs of the `now`
  context; the same rules: a close only if open).
- combat end closes every window. The last evaluations are kept, so a condition held through the edge needs a new edge.

The facade read. A new, dedicated read copies the belief's windows to the core at each update (owner "yes"). It is
not the aura copy: an aura row carries the client's shape and its secrecy rules, a window has neither. It is a
belief-only facade function, like `Facade.KnownRank`, and the only window path the border allows.

The core (forecast only). Each cycle starts from that copy and keeps nothing between updates (the stateless rule,
unchanged). Within a cycle:
- `actions+=/open_window,name=<w>,if=...[,refresh=1][,duration=<s>]` and `actions+=/close_window,name=<w>,if=...`
  are APL lines like `variable`: no icon, order matters, and a name the spec has not registered fails at load.
- `handler()` may call `openWindow(name)` / `closeWindow(name)`, the same verbs as `now()`'s.
- reads: `window.<name>.up`, `.remains`, `.elapsed` (own tables, not `buff`).
- an `open_window` line whose condition becomes true in t is the recheck forecast's countdown (§3's mechanism).

The guard. A harness replay check: every open the forecast predicts (an `open_window` line or a `handler()` open, at
its predicted time) is matched by the belief's evaluator opening the same window within one poll. A miss is drift, and
drift is flicker; the check lists each with its log time.

Windows only where no aura fits (decision 11). Where the client has an aura, even a hidden one such as Defensive
State (5302) when it is readable, the aura stays. An observed usability flip may open a window when no aura tracks it:
its evaluator reads `usable.<key>`, it sets `close_on_false`, and the ability's `now()` closes it, so it ends when
usable flips back, at the cast, or at the duration.

Stepped windows (decision 11's amendment). `RegisterWindow` takes two more optional fields: `steps = { "<ability
key>", ... }`, `loop = true|false` (default false) and `on_deviation = "stay" | "skip" | "end"` (default "stay") and `strict = true|false` (default false). A stepped window's state adds `step` (1..n).
- Reads: `window.<name>.step`, and `window.<name>.next.<ability key>`, true when that ability is the due step (and
  the window is up).
- Belief (truth): the step advances when the belief observes the real cast of the due step's ability. This is generic
  (by ability index, from the cast the belief already folds), with no per-ability `now()`. After the last step the
  window closes, or with `loop` goes back to step 1 (wowsims's `resetSequence`). An observed cast of a later step
  (the player went out of order) follows `on_deviation`:
  - "stay" (default, wowsims-true: a sequence advances only on its due step): nothing happens.
  - "skip": the step jumps to the one after that later step (after the last: close, or step 1 with `loop`).
  - "end": the window closes; a fresh one needs the evaluator's next edge (or `loop`'s step 1 does not apply: a
    deviation ends it).
  We cannot tell which APL line a player's cast belonged to, so an observed cast of the due step's ability always
  advances it. The duration and the close conditions still end a stalled sequence (with "stay", the only way out of
  a deviation).
- Strict (owner "yes", 2026-11-03): with `strict`, any observed (belief) or simulated (core) on-GCD cast that is not
  the due step's ability ends the window. Off-GCD casts (no GCD triggered: trinkets, Blood Fury, Rapid Fire) never
  spoil it (a controller ruling, flippable). A later step's cast still follows `on_deviation`. A non-strict window
  ignores unrelated casts.
- One per-cast hook in each layer, generic: in the belief, the cast fold (`Families/Now.lua`'s `run`, on every own
  CastSuccess, with the ability index and its `A.gcdKind`); in the core, `state:RunHandler` (`Engine/Sim/State.lua`),
  which every simulated cast passes. Each window precomputes at Build an ability-index -> step lookup (0 for an
  ability not in it), so a cast costs one array read per stepped window and allocates nothing.
- Core (forecast): the cycle starts from the copied step. A simulated cast of the due step advances it in that
  cycle's core state only, so the list recommends the next step; it is never written back, and the next update starts
  from the belief's copy again.
- Translation (the translator's mapping, recorded in `apl.lua`'s header when the lanes build it):
  - `sequence { a1..an }` with a condition becomes a stepped window whose steps are the cast members. The condition
    becomes the evaluator only when it is expressible in belief reads (talents, settings, clocks, range); otherwise the
    sequence is omitted and listed as a deviation.
  - `sequenceIsComplete(<name>)` becomes `!window.<name>.up`.
  - `resetSequence` becomes `loop`.
  - `strictSequence` becomes a strict stepped window. Its start rule (wowsims: every step castable at once) becomes
    the evaluator: each step's cooldown readiness read from the belief, and the sequence's own condition. A part not
    readable in the belief (a secret resource, say) is omitted and listed as a deviation. Where rule 14's chain
    already translates a shipped `strictSequence` (the Warrior stance swaps), it stays until its lane moves it, gated.
  - The actual sequences (Retribution's `move1`-`move3`, the Hunters' if any) are translated in their lanes, gated;
    the windows core only provides the mechanism.

The hunter weave. The first window, built with the ranged clock (§3) in the same task:
- `weave`: the evaluator opens it on an observed Auto Shot with the main-hand swing ready; Raptor Strike's `now()`
  (real cast) and `handler()` (forecast) close it.
- "Just shot" reads the window. The other timing variables that do not conflict ("Windup close", "Weave fits", "Wait
  at melee") stay clock conditions (§3). Walk-time terms stay dropped (decision 8), and no wait is ever translated
  (decision 9).
- The forecast's open is a recipe `extra` line, `open_window,name=weave,if=<the shot fires with the swing ready>`, on
  the ranged clock, so the recheck gives it a countdown.
- Raptor Strike's queued aura stays (§3: it ends at the next main-hand swing): that span has a real client answer
  (`IsCurrentSpell`), so it is not a window.

Out of scope now (follow-ups, not tasks):
- Migrating hand-rolled spans to windows in their class lanes, optional and gated. Each is checked first for a real
  aura (keep the aura) against none (a window candidate): Hunter Mongoose Bite's `biteAt` (Defensive State 5302, an
  aura when readable), Warrior Revenge's `defensive_state` aura, Rogue Cutthroat (proc 462707), the Retribution
  opener's `mainhand_swung`. The weave and the Retribution opener have no aura, so they qualify.
- New windows elsewhere (Heroic Strike queue timing, proc reaction windows, seal twisting, the five-second rule),
  priced after the re-pin.

## 4. The translator's new kinds

From the research's census. "Needed" means translated. "Omit" means rule 2, listed in the header.

| Kind | Used by | Decision |
| --- | --- | --- |
| `talentIsKnown`, `talentRank` | 9 specs; Feral | Needed: `talent.<key>.enabled` / `.rank` (rule 4's mechanism) |
| `spellIsCasting` | Balance, Fire, Frostfire, Arms, Demonology x2 | Needed: the engine's casting read of that spell; a precondition for dropping `no-cast-end-pick.patch` |
| `spellInRange` | Retribution, hunter weave | Needed: the ability's range read; §2's rewrite where a move reaches it |
| `unitDistance` beyond rule 11 (`OpNe` of a `max`) | hunter default #16 | A movement term (arithmetic on yards): dropped (decision 8) |
| `move`, distance-only `waitUntil` | §2 | Omit; their range gate goes to the reached entries |
| `wait`, other `waitUntil` | §3 | Never translated (decision 9); a clock-timed end or a non-distance condition goes onto the lines it held as a condition (§3) |
| `unitMovementSpeed` | hunter walk variables | A movement term: dropped (decision 8) |
| `unitIsMoving` (any unit) | Demonology's move condition | A movement term: dropped (decision 8) |
| `sequence` whose members are casts, moves, waits and `waitUntil`s | Retribution's "Move to melee" | Rule 14's chain over its cast members; moves and waits as §2.2 and §3; its own `not sequenceIsComplete` becomes the pull-only gate (decision 10, the plan's S3) |
| `startAttack`, `petAttack`, `changeTarget`, `newTarget`, `itemSwap`, `recheckWhileMoving` | hunters, Warlocks, Enhancement | Omit: display-impossible or no Hekili equivalent |
| `spellFullCooldown`, `gcdIsReady`, `spellGcdHastedDuration`, `currentHealth`, `auraDuration`, `dotBaseDuration`, `spellTravelTime` | various | Needed: one-line reads |
| `hpPercentForDefensives` | Feral, Guardian | Needed as the build's constant; health is hidden in combat (Protection's precedent) |
| `druidBleedIsActive` | Feral, Guardian | Needed: the kit's bleed auras on the target |
| `multipleCdUsages`, `alignCdEnd`, `selectedPotion` (`slot`) | Arms, Fury | Fold to a constant where the fight's length decides it, else omit; each recorded |
| `spellExpectedDpet` | Shadow, SM/Ruin | Omit (no damage model), as `dotExpectedDps` was |
| `strictMultidot` | Destruction, SM/Ruin | Needed: rule 17's current-target `multidot` |
| `curseType`, `warlockIsAssignedCurse`, `warlockAssignedCurseIsActiveOnAllTargets`, `warlockBaneIsActiveOnAllTargets`, `dotIsActiveOnAllTargets` | Warlock builds | Needed where a rule 16 `select` exists; "on all targets" read on the current target (rule 17's precedent) |
| `doAtValue` not a constant | Mages, Warlocks | Needed when it folds to a constant from the kit's cast time, else omit (rule 1) |

Upstream now casts trainer and book ranks by spell ID, so recipe `map` entries and kit `copy` lists take the new rank
IDs as the omit lists reveal them. This is kit work in each class lane: Sniper Shot, Skyborne, Windshaper, Lacerate
as a talent.

The warlock crash: four of five warlock builds dropped `curseOptions`, because the Banes are now cast directly (Agony,
Doom). Rule 16's `select` raises "the build sets no curseOptions" on them.
- Those recipes drop `select`, their Bane lines become plain casts, and the class stops registering `assigned_curse`
  for those specs. The builder confirms the orphaned saved value is harmless.
- Affliction keeps `select` if its build still carries the option.

## 5. Requests, the export and the oracle

- Pins: `M.PIN` moves to e2842f0a78 and `M.OLD_SIM` is deleted (`tests/Forever/wowsims_pin_spec.lua` updated).
  Whether the two names fold into one is the builder's call.
- SIML: the export gains one step, `siml parse -json` on the hunter build with the sim-pin CLI, and the converted JSON
  is checked in as the recipe's `build`. `tools/wowsims/sim-pin/build.sh` builds the CLI with the `with_db` tag.
- Recipes naming deleted paths:
  - Feral and Guardian move to the adaptive APLs.
  - Retribution moves to `default.apl.json` and its new gear.
  - Enhancement drops `apl` (the build carries the rotation).
  - The hunters move to bm_weave / mm_weave / sv_weave (BM's pet Raptor; `petAggression` and `cobraReflexes` no
    longer set).
- Request fields:
  - Talents come from the new builds, re-encoded by spell ID against the new trees.
  - Races follow the builds: Elemental and Enhancement become Windshaper Skyborne, the four warlock builds Human. The
    racial and autocast lines change with them.
  - Greater blessings carry the build's `1` (upstream's on, at the top rank), replacing our `2`. The builder checks
    the log applies the top rank.
  - `executeProportion25/45/90` leave `M.ENCOUNTER`.
  - `conjuredItems` and the item swap are taken as the builds carry them; their nodes are already omitted.
- Oracle patches:
  - `leftover_db.go` is dropped, once the builder confirms no new request wears one of the 28 items.
  - `no-cast-end-pick.patch` is dropped in the last phase. By then every hardcast pack is re-exported from its
    guarded APL; every hardcast log is rerun on the unpatched CLI and the replays compared.
  - `darkmantle-set-512.patch` stays, because e2842f0a78 still has the mismatched set ID.

## 6. The border, secrets, allocation

- One new crossing: decision 11's window facade read (owner "yes", §3a). Otherwise the engine and the belief change
  nothing for movement. The rewrite reads a setting and the
  existing range bracket. The ranged clock arrives through the existing `UnitRangedDamage` tail; the recheck forecast
  it feeds is the engine's existing one.
- If the builder finds anything needing a further belief function or facade read, it stops and asks the owner.
- The new translated reads are simulation values or existing belief answers. The window evaluators' reads are
  `issecretvalue`-guarded in the belief (§3a); the window copy itself carries only plain times and counts.
- No closures or per-update tables are added on the walk.

## 7. Gates, the test world and accuracy

The rotation match with wowsims is proven by the replay. It already places us where wowsims stood, from the log's
Movement aura (`tests/Game/harness/replay.lua` `M.MOVE = 20`; the hunter logs carry 1257-1353 Movement lines). It
scores our pick at each of wowsims's casts.
- The replay gates score with Movement ON for every spec whose APL moves (decision 7: "effectively testing 'on'").
  At wowsims's positions, a carried move condition holds where wowsims moves instead of casting, so ON adds no scored
  decision there. Where it would, that is a translation defect, not a floor cost.
- OFF is covered by one translation test per opted-in spec: a reached entry is hidden out of range and shown in
  range. No OFF replay gate.
- The loops measure the belief against the oracle (the same engine), not the APL against wowsims. Movement modelling
  does not help that, so under decision 6 the loop world gets none and there is no loop walk. The loops run with
  Movement OFF. The hunter worlds keep their fixed distance and today's range-gated strikes. With ON there, every
  shown strike would be refused "range" and the loop would measure the missing walk, not the belief. No loop line
  moves for the toggle.
- No test assumed a simulated move (none was built). The harness sets the toggle through the profile it boots, ON for
  the replay and OFF for the loops; the builder picks the hook.

Floors (decision 4): the baseline is the pre-re-pin `make accuracy`.
- A pack within max(0.02, 2/n) of it (the lane P rule R2) is re-floored on its re-export, naming the re-pin.
- A pack beyond that is traced first (kit, world, central or API-forced, P7's classes), and the cause is written
  beside the number.
- Flicker and LIVE60 follow the same rule.
- Fresh floors for Retribution, Feral, Guardian and the Hunters are approved (decision 7). Each takes the re-pin as
  its named cause, and its top three disagreements are classified first. It ships only if every remaining top
  disagreement is unfixable (decision 8's fresh-floor rule).
- ON flicker: each opted-in spec's replay line (Movement ON) carries a flicker ceiling, set measured-then-held like
  any flicker floor (decision 8).

| Spec | Change | Expected |
| --- | --- | --- |
| Balance, Mage x3, Shadow, Smite, Affliction, Elemental, Prot Paladin, Prot Warrior | APL edits, gear, talents; casters' `spellIsCasting` guards | Hold. Casters may move at the patch drop |
| Rogue x3 | energy-pooling group, `affords` | Small; the omitted pooling `waitUntil`, its condition carried as a forecast condition, is the risk |
| Arms, Fury | strict-sequence stance swaps, per-spell GCD compares, cd-usage folds | Likely drop; trace each |
| Enhancement | rotation inside the build; Skyborne; item swap omitted | Small to medium |
| Warlock x5 | Banes replace `select`; Sesam's Demonology APLs; `petAttack` / `changeTarget` omitted | Demonology and Destruction likely drop |
| Retribution | new talent-adaptive APL and gear | Fresh floor. ON replay: the carried `spellInRange` move condition is the risk |
| Feral, Guardian | adaptive APLs (42 / 15 variables), Berserk gone | Fresh floor. The omitted `waitUntil` is a small risk: wowsims holds where we may show a lower line, but it casts nothing while holding, so few scored decisions |
| Hunters x3 | SIML weave builds, Sniper Shot, carried move conditions, waits never translated (decision 9): the timing variables on the clocks and the recheck forecast | Fresh floor: the old floors (1.00 / 0.92 / 0.97) are not comparable. Risks: the dropped yard arithmetic in the move conditions, a wait the forecast cannot time (its end not a clock read), the modelled ranged clock, the queued Raptor Strike's expiry at the swing |

## 8. Order of work: independently gated phases

Each phase ends green (`make check`, and `make gate` where packs move).

0. Baseline: `make accuracy` on `forever` 0d98cb02c, the report kept beside the plan (decision 8).
1. Plumbing (first: the e2842f0a78 CLI answers `siml`): the CLI with `siml`, the SIML step, the recipe paths, `M.ENCOUNTER`. Gate: one request exports, and the
   dry-run omit counts match the research.
2. Translator kinds (§4). Gate: unit tests, and the omit counts falling on the low-change specs.
3. The Movement setting, the range-gate rewrite with carried move conditions, the windows core, and the ranged-hand
   expression with the weave window (§2, §3, §3a). Gate: the toggle tests, and today's hunter packs regenerated at the old pin, whose weave already moves and
   waits, replayed with ON (the waits as decision 9: clock conditions and the forecast).
4. Low-change specs: re-export, gate, re-floor.
5. Rogue x3, then Warrior x3.
6. Enhancement, Warlock x5 (the `select` fix first), Retribution.
7. Feral, Guardian.
8. Hunters.
9. Oracle patches dropped and logs rerun. Docs: layout.md's pin section, wowsims-packs.md rules 2 and 11 and the new
   rewrite rule, gaps.md. Then `packs-check` and a CHANGELOG line for the Movement toggle.

Phases 4-8 run in parallel by class once phases 1-3 are on the branch.

## 9. Left to the builder, and owner checks

- Builder: the opt-in form and the keybind (§2.1); folding the pin names (§5); classifying the non-distance
  `waitUntil` entries and Warrior's cd-usage nodes (§3, §4).
- Resolved by decision 9: waits are never translated; the clocks and the recheck forecast replace them.
- Resolved by decision 11: rotation windows (§3a); the migrations and new windows are follow-ups.
- Resolved by decision 8: run speed and "is moving" are dropped, not constants (the owner's "ok").
- Resolved by decision 7: the ON form, the replay scoring ON, the fresh floors, and the pre-pull moves.
- In game after launch: C7's H2-H5 (the weave's timing reads the ranged clock), and the tint during a walk with Movement ON (a ledger row
  added in phase 3).
