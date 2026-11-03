# Full wowsims re-pin and the Movement toggle (design, 2026-11-03)

Status: DRAFT for the owner. A design, not a plan: intent, goals, decisions and what is left to the builder. Branch
`forever-repin` from `origin/forever` 0d98cb02c. Paths are under `src/Hekili/` unless they start with `tests/`,
`tools/` or `docs/`.

Research this rests on: the sizing research (audit `followups/repin-research.md`, 2026-11-03: the changed APLs, the
new proto kinds, the SIML converter, the request changes, a suggested order; its dry translation of every recipe
against the trees at both commits is the source of every omit count below). Ledger: the open-questions file,
"2026-11-03 — full wowsims re-pin started".

## 0. The owner's decisions (binding)

1. Re-pin target: the recipes' APLs and requests move to the current sim pin e2842f0a78 (the oracle's commit),
   hunters included; `M.OLD_SIM` goes away. The work merges after launch, in the first post-launch release, not before.
2. "I want to be as true to the rotations as possible." Where a rotation moves to reach the next ability, that ability
   is displayed out of range, with Hekili's normal out-of-range tint. "Any spec where movement is considered must have
   movement toggleable." The Movement toggle starts ON. The specs whose new APLs move: the Hunters (the weave builds),
   Feral and Guardian (the adaptive APLs), Retribution, and Demonology (the brand builds).
3. "For movement modeling, just follow what we need to to prove the rotation accuracy." The replay already follows
   wowsims's Movement aura. The loop world gets only the minimum its gates need, for example a start distance and
   timed walking at base run speed, and only if a gate needs it. No speed buffs unless a gate needs them.
4. Accuracy must stay close. Floors move only with a named, traced cause. No jittery recommendations: flicker is an
   acceptance metric.
5. (Owner ruling, 2026-11-03, replacing the open Hunter question.) "When movement is off, abilities that assume
   movement to use should be hidden." Every spec keeps its one translated rotation: the Hunters keep the weave
   builds, and there is no switch to wowsims's Turret, Turret Hawk or Melee APLs. With Movement OFF, the entries
   that need a move to reach are hidden, because their range gate holds. With Movement ON, they are shown out of range.

The standing constraints apply unchanged. The core stays class-neutral: Movement is a generic core toggle that packs
opt into. The belief/core border holds (§6 says why no new crossing is needed). Secret values are guarded with
`issecretvalue`. Recurring paths do no allocation. The addon is display only.

## 1. Goals and non-goals

Goals:
- Every one of the 26 recipes reads its APL, build and gear at e2842f0a78. `M.PIN == M.SIM_PIN`, and every
  checked-in request and log is re-exported on one CLI.
- The translator handles every new kind that a shipped APL uses and that the client lets us show. Every other kind is
  an omission it lists, as rule 2 does today.
- Movement is a generic core toggle, ON by default. The five moving spec groups opt in. ON shows the ability a move
  reaches, out of range. OFF hides it.
- The hunter weave's `wait` steps become Hekili's delay countdown, timed from the ranged auto-shot clock (C7).
- The oracle patches whose reasons the re-pin removes are dropped: `leftover_db.go`, and `no-cast-end-pick.patch`
  once `spellIsCasting` is translated.
- Accuracy stays close to the pre-re-pin baseline. Every floor that moves names its traced cause.

Non-goals:
- Moving past e2842f0a78. A newer upstream needs a second bump later.
- New packs (Frost mage, Retribution Holy Shock), even where upstream now ships an APL for them.
- Shipping SIML: the converter is a tools step, and nothing in the addon or the translator parses SIML.
- Modelling speed buffs, Dash's speed, the target's movement or per-entity positions, unless a gate needs them
  (decision 3).
- Automation of any kind. A move is never performed. It is only what makes an ability show.

## 2. The Movement toggle

### 2.1 What it is

Movement is a core toggle beside Cooldowns, Defensives and Potions: `settings.toggles.movement`, read in the
simulation as `toggle.movement`, with a keybind and an entry in the toggle UI, default ON. It is generic: the core
names no spec. A spec opts in through data, not code. The builder chooses the form: a spec field set by the class
file, or a flag that the generated pack's header carries when the translator emitted a movement term. Either way, the
toggle's options row appears only for a spec that opted in. A spec that never moves never sees it.

### 2.2 How a move translates

wowsims's `move` action (to `rangeFromTarget` N yards) becomes a simulation-only step, written only when the toggle is
on (`toggle.movement&...`, under the entry's own condition):
- The step shows no icon. It sets the simulated target's range bracket to where the move ends, using the engine's
  existing `state.setDistance`, the one Hekili uses for leaps and charges. It then lets the walk continue, as
  `variable` and `wait` lines do. The next pick is the ability wowsims would cast on arrival. The client's own range
  read tints it out of range (`UI/Resolve.lua`'s `inRange`; Classic and Timeline already draw it).
- The engine's reset puts the real bracket back each update, so nothing a move sets outlives the walk that set it, and
  nothing reaches the belief.
- Walk time: the step advances no simulated time (decision 3's minimum). The player's own walk is the delay, and
  every poll during the walk re-runs the same move, so the shown ability holds still until the real bracket says it
  has arrived. If a gate shows that the waits after a move need the walk's duration (the weave's "Time to walk in"),
  the builder adds it as the bracket's gap divided by base run speed (7 yd/s), and the spec records the measurement.
- `rangeFromTarget` read from a variable (the weave's "Melee spot" and "Shoot spot") is inlined like any other
  variable. A yard value maps to the bracket it falls in, using rule 11's `within`/`outside` semantics.

With Movement OFF, the move step is not written. The range gates around it (`unitDistance` through rule 11,
`spellInRange`, a distance-only `waitUntil`) read the real bracket, so the entries that need a move are hidden until
the player is in range, as decision 5 asks. One existing semantic carries over: an unknown bracket (no plain range
answer yet) answers both `within` and `outside`, so before the first answer an OFF rotation can still show a
move-gated line. The builder keeps that rule (unknown never blocks) and documents it beside rule 11.

### 2.3 Where it applies at e2842f0a78

| Spec | What moves | ON | OFF |
| --- | --- | --- | --- |
| Hunter BM / MM / SV (weave builds) | Weave group: move to "Melee spot", strike, move to "Shoot spot"; walk_in group | Raptor Strike / Mongoose Bite shown out of melee while the weave fits; the next shot shown in melee (dead zone tint) | Melee strikes only when already within 5; the shots only when outside it |
| Feral (adaptive) | "Run into melee with Dash" (move to 5), then a distance-only `waitUntil` | The first damage ability shown, tinted, while out of melee | The `waitUntil` holds as a range gate: the damage lines are hidden until in melee |
| Guardian (adaptive) | Feral Charge when out of melee (a real cast, kept either way); move when Charge cannot close; `waitUntil` | As Feral, after Charge | As Feral |
| Retribution (default) | `not spellInRange(Crusader Strike)` calls the "Move to melee" group | Crusader Strike's line shown, tinted, while that group's ranged lines still run | The group's ranged lines only; melee lines hidden until in range |
| Demonology (fire / shadow brand) | Move to 5 at 3 or more targets, target not moving | The melee-range AoE shown, tinted | Hidden until within 5 |

Pre-pull moves (the hunters' and Retribution Holy Shock's "Pull range" at -19 / -20 s) stay omitted whatever the
toggle. Positioning before the pull is the player's, as the pre-pull guard ruling (2026-10-21) already says the player
decides when to press. This is a design call, listed for the owner's veto (§9).

## 3. Waits and the ranged clock

wowsims's `wait` (a duration) and `waitUntil` (a condition) hold the rotation. Hekili's engine already has the
`wait,sec=` action: Core advances the delay by `sec` and re-walks, so the next real pick shows with its countdown. Each
evaluation stays stateless (the APL stateless-guards rule): a wait lives only inside one walk.
- `wait` translates to `wait,sec=<duration>` under its condition, when every read in its duration translates. The
  weave's durations read the GCD, the spell's time to ready, `inputDelay` (the request's reaction time, a constant),
  the main hand (`mainhand_remains` and `mainhand_speed`, already translated) and the ranged hand.
- `autoTimeToNext` and `autoTimeSinceLast` of `RangedAuto` need an engine expression for the ranged hand, the twin of
  `mainhand_remains`, read from `state.swings.ranged_projected` / `ranged_speed`. Those come from the belief's ranged
  clock (class-completion C7: `Game/State/Sources/Swing.lua` hand 3) through the facade's existing `UnitRangedDamage`
  tail. That is an existing crossing, so no new one is needed. C7's in-game questions (layout.md H2-H5: is swingType 2
  fired, is Auto Shot's success seen, does UnitRangedDamage carry haste) are unanswered until launch. The replay feeds
  the clock from the log, so the gates measure the translation, not the client.
- `waitUntil` with a distance-only condition is §2.2's range gate. Any other `waitUntil` (Protection Paladin, Rogue
  energy pooling) is classified by the builder per entry. It becomes a `wait,sec=` when the time until the condition
  holds is a read the engine has (a resource's time to a value, a cooldown's remains). Otherwise it is omitted and
  listed. Hekili's forecast already pools, and a line that waits without a countdown would show nothing.
- `startAttack` and `petAttack` stay omitted. Hekili shows no auto-attack toggling, and the weave's own melee lines
  are what the player sees.

## 4. The translator's new kinds

From the research's census (proto NextIndex 136 to 143, plus older kinds that shipped APLs now use). Needed means
translated. Omit means rule 2, listed in the header, because the client cannot show it or Hekili has no equivalent.

| Kind | Used by | Decision |
| --- | --- | --- |
| `talentIsKnown`, `talentRank` | 9 specs; Feral | Needed: `talent.<key>.enabled` / `.rank` (rule 4's mechanism; the talent keyed by spell ID) |
| `spellIsCasting` | Balance, Fire, Frostfire, Arms, Demonology x2 | Needed: the engine's casting read of that spell. It is the precondition for dropping `no-cast-end-pick.patch` (§5) |
| `spellInRange` | Retribution, hunter weave | Needed: the ability's range read (in sim, the bracket against its range), subject to §2 |
| `unitDistance` beyond rule 11 (`OpNe` of a `max`) | hunter default #16 | Omit, as today |
| `unitMovementSpeed` | hunter weave variables | Needed as a constant, base run speed 7 yd/s: an API-forced deviation (no speed buffs, decision 3; no new client read) |
| `unitIsMoving` (target) | Demonology | Needed as false (the engine does not track target movement); recorded as a deviation |
| `move`, `wait`, `waitUntil` | §2, §3 | Needed as §2 and §3 say; the pre-pull move is omitted |
| `startAttack`, `petAttack`, `changeTarget`, `newTarget`, `itemSwap`, `recheckWhileMoving` | hunters, Demonology, Destruction, Enhancement | Omit: display-impossible or no Hekili equivalent |
| `spellFullCooldown`, `gcdIsReady`, `spellGcdHastedDuration`, `currentHealth`, `auraDuration`, `dotBaseDuration`, `spellTravelTime` | various | Needed: one-line reads |
| `hpPercentForDefensives` | Feral, Guardian | Needed as a constant, the build's value; the line reads health, which the client hides in combat (Protection's precedent) |
| `druidBleedIsActive` | Feral, Guardian | Needed: the kit's bleed auras on the target |
| `multipleCdUsages`, `alignCdEnd`, `selectedPotion` (`slot`) | Arms, Fury | Fold to a constant where the fight's length decides it; else omit. The builder records each |
| `spellExpectedDpet` | Shadow, SM/Ruin | Omit (no damage model), as `dotExpectedDps` was |
| `strictMultidot` | Destruction, SM/Ruin | Needed: rule 17's current-target `multidot` (other targets' DoTs are not readable) |
| `curseType`, `warlockIsAssignedCurse`, `warlockAssignedCurseIsActiveOnAllTargets`, `warlockBaneIsActiveOnAllTargets`, `dotIsActiveOnAllTargets` | Warlock builds | Needed where a rule 16 `select` exists; "on all targets" read on the current target (rule 17's precedent) |
| `doAtValue` not a constant (pre-pull timed from cast times) | Mages, Warlocks | Needed when the value folds to a constant from the kit's cast time; else omit, as rule 1 does |

Upstream now casts trainer and book ranks by spell ID. Recipe `map` entries and kit `copy` lists take the new rank
IDs as the omit lists reveal them. These are kit work in each class lane (Sniper Shot, Skyborne, Windshaper, Lacerate
as a talent, and the ranks the research lists).

The warlock crash: four of five warlock builds dropped `curseOptions` (Banes are cast directly: Agony, Doom), and rule
16's `select` raises "the build sets no curseOptions". Those recipes drop `select`. Their Bane lines become plain
casts, and the class stops registering `assigned_curse` for those specs. An orphaned saved value is harmless; the
builder confirms the options panel ignores it. Affliction keeps `select` if its build still carries the option.

## 5. Requests, the export and the oracle

- Pins: `M.PIN` moves to e2842f0a78 and `M.OLD_SIM` is deleted, with `tests/Forever/wowsims_pin_spec.lua` updated.
  The builder decides whether to keep two names for one value (cheap, and ready for a future split) or fold them.
- SIML: the hunter presets are SIML only. The export gains one step that runs the sim-pin CLI's `siml parse -json` on
  the hunter build and checks in the converted JSON as the recipe's `build`. Only `export` needs the CLI and Go; the
  translator reads JSON as today. `tools/wowsims/sim-pin/build.sh` must build a CLI with the `siml` subcommand (the
  `with_db` tag).
- Recipes naming deleted paths change: Feral and Guardian to the adaptive APLs; Retribution to `default.apl.json` and
  its new gear; Enhancement drops `apl` (the build carries the rotation); the three hunters to bm_weave / mm_weave /
  sv_weave (BM's pet Raptor; `petAggression` and `cobraReflexes` no longer set).
- Request fields: talents taken from the new builds, re-encoded by spell ID against the new trees as the 2026-11-02
  edit did. Races follow the builds: Elemental and Enhancement become Windshaper Skyborne, the four warlock builds
  Human. The racial and autocast lines change with them, and the kit must know Skyborne. Greater blessings carry the
  build's `1`: upstream folded them to on at the top rank, which replaces our `2`. The builder verifies the log
  applies the top rank. `executeProportion25/45/90` are removed from `M.ENCOUNTER`, since the proto dropped them.
  `conjuredItems`, `enableItemSwap` and the item swap are taken as the builds carry them; the translator already
  omits their nodes.
- Oracle patches: `leftover_db.go` is dropped, because no re-exported gear wears one of the 28 items (the builder
  confirms on the new requests). `no-cast-end-pick.patch` is dropped once `spellIsCasting` is translated and every
  hardcast pack is re-exported from its guarded APL. One CLI serves every log, so it drops in the last phase, followed
  by an `export.lua rerun` of every hardcast log and a replay comparison. `darkmantle-set-512.patch` stays: e2842f0a78
  still has the mismatched set ID.

## 6. The border, secrets, allocation

- No new belief/core crossing. The move step uses only simulation state (`setDistance`, reset each update). The range
  bracket and the ranged clock reach the engine through reads that exist today (the target range bracket and the
  `UnitRangedDamage` tail). `unitMovementSpeed` is a constant, not `GetUnitSpeed`. If the builder finds that any of
  these needs a new belief function or facade read, it stops and asks the owner.
- Secrets: the new reads are simulation values or existing belief answers. A range answer stays guarded where it is
  read today.
- Allocation: the move step and the wait translation run inside the walk. No closures and no per-update tables; the
  existing allocation tests cover the driver.

## 7. Gates, harness and accuracy

- Replay: already places us by the log's Movement aura (`tests/Game/harness/replay.lua` `M.MOVE = 20`; the hunter
  logs carry 1257-1353 Movement lines). It scores on-GCD casts, never the move, so it measures ON exactly where wowsims
  stood. The harness runs with the toggle ON (the default).
- Loop: the loop world has no positions (every target in range), so Feral, Guardian, Retribution and Demonology never
  trigger a move there and need nothing new. The hunter loops are the one gate that needs walking. With the weave ON
  at the hunter worlds' distance, the first icon would be a strike out of range, and `W.press` refuses "range". The
  minimum (decision 3): the loop's player, given a range refusal, walks to the pressed ability's range at base run
  speed through `W.moveTo` steps, then presses. Ours and the oracle walk alike. No speed buffs. The builder adds this
  only once a hunter loop gate shows the need.
- One OFF check per opted-in spec: a short test that with the toggle off the move-gated lines are hidden out of range
  and shown in range. This is not a floor.
- Floors (decision 4): the baseline is the pre-re-pin `make accuracy`. A pack within max(0.02, 2/n) of it (the lane P
  rule R2) is re-floored on the re-export, naming the re-pin. A drop beyond that is traced (kit, world, central or
  API-forced, as P7 classifies) before any re-floor, and the cause is written beside the number. Flicker per pack
  follows the same rule. LIVE60 is re-measured, with its cause.

| Spec | Change | Expected |
| --- | --- | --- |
| Balance, Mage x3, Shadow, Smite, Affliction, Elemental, Protection Paladin, Protection Warrior | APL edits, gear and talents; casters' `spellIsCasting` guards | Hold. Casters may move when the patch drops (their guarded APLs should replay as with the patch) |
| Rogue x3 | energy-pooling group, `affords` | Small moves; pooling `waitUntil` is the risk |
| Arms, Fury | stance-swap strict sequences, per-spell GCD compares, cd-usage nodes folded | Likely drop; trace each |
| Enhancement | rotation inside the build; Skyborne; item swap omitted | Small to medium |
| Warlock x5 | Banes replace `select`; Sesam's Demonology APLs; `petAttack` / `changeTarget` omitted | Demonology and Destruction likely drop; trace each |
| Retribution | new talent-adaptive APL, new gear, Move to melee | New basis; floor re-set from the first clean run with the re-pin named |
| Feral, Guardian | new adaptive APLs (42 / 15 variables), Berserk gone, moves | New basis, as Retribution |
| Hunters x3 | SIML weave builds, waits on the ranged clock, moves, Sniper Shot | New basis: the old floors (1.00 / 0.92 / 0.97) are not comparable; the hunter logs leave `OLD_SIM` |

For the "new basis" rows, the re-pin is the named cause, but the first clean run still classifies its top three
disagreements (P7) before the floor is set.

## 8. Order of work: independently gated phases

Each phase ends green (`make check`, and `make gate` where packs move) and can be reviewed alone.

1. Plumbing: the CLI with `siml`, the SIML conversion step, the recipe paths, `M.ENCOUNTER`'s three fields. Gate: one
   request exports at the new pin, and the dry run's omit counts match the research.
2. Translator kinds (§4, without move and wait): gated by unit tests and by the dry run's omit counts falling to the
   old levels on the low-change specs. Packs at the old pin may not change, except where a kind was already present.
3. The Movement toggle, the move step, waits and the ranged-hand expression (§2, §3). Gate: the toggle tests, and the
   current hunter packs regenerated at the old pin. Their old weave APL already moves and waits, so the replay
   measures the toggle on today's logs before any re-export.
4. Low-change specs (Balance, Mage x3, Shadow, Smite, Affliction, Elemental, Protection Paladin, Protection Warrior):
   re-export, gate, re-floor.
5. Rogue x3, then Warrior x3.
6. Enhancement, Warlock x5 (the `select` fix first), Retribution.
7. Feral, Guardian.
8. Hunters: the SIML builds, the weave, the loop walk if needed.
9. Oracle patches dropped, every affected log rerun, replay compared; docs (layout.md pin section, wowsims-packs.md
   rules 2 and 11 and the new move and wait rules, gaps.md), `packs-check`, the CHANGELOG line for players (the
   Movement toggle).

Phases 4-8 are parallel by class once phases 1-3 are merged on the branch.

## 9. Left to the builder, and for the owner's veto

- The opt-in mechanism's form (§2.1), and whether the two pin names fold (§5).
- Walk time in the move step: zero unless a gate needs it (§2.2).
- The per-entry classification of the non-distance `waitUntil` and of Warrior's cd-usage nodes (§3, §4).
- For the owner's veto: pre-pull moves stay omitted whatever the toggle (§2.3). `unitIsMoving` of the target reads
  false, and `unitMovementSpeed` is the constant 7 yd/s (§4).
- In game after launch: C7's H2-H5 for the ranged clock the weave's waits rely on, and whether the range tint reads
  right during a walk (a ledger row added with phase 3).
