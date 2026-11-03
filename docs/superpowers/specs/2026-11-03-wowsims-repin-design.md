# Full wowsims re-pin and the Movement toggle (design, 2026-11-03)

Status: DRAFT for the owner, revised the same day to the owner's movement ruling (decision 6). A design, not a plan:
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

The standing constraints apply unchanged:
- The core stays class-neutral. The Movement toggle is a generic setting that packs opt into.
- The belief/core border holds: this design needs no new crossing.
- Secrets are guarded with `issecretvalue`.
- Recurring paths do no allocation.
- The addon is display only.

## 1. Goals and non-goals

Goals:
- Every one of the 26 recipes reads its APL, build and gear at e2842f0a78, with `M.PIN == M.SIM_PIN`. Every
  checked-in request and log is re-exported on one CLI.
- The translator handles every new kind a shipped APL uses that the client lets us show. Every other kind is an
  omission, listed as rule 2 does today.
- Movement in Hekili is a toggle and one translator rewrite (§2). Nothing else.
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
becomes `(toggle.movement|<its range gate>)`. The range gate is the `unitDistance` term (rule 11's
`target.within<N>`/`outside<N>`), the `spellInRange` term, or the omitted `waitUntil`'s condition, carried onto the
lines it held.
- ON: the gate always passes. The ability shows when the rest of its condition holds, and the client's range read
  tints it out of range (`UI/Resolve.lua`'s `inRange`, drawn by Classic and Timeline today).
- OFF: the real range bracket decides, so the entry is hidden until the player is in range (decision 5).

Nothing in the engine or the belief changes. The rewrite reads only a setting and the range bracket that exists
today. An unknown bracket (no plain range answer yet) still answers both sides (rule 11), so OFF can show a
move-gated line before the first answer. That rule is kept and documented beside the new one.

Which entries a move reaches is the translator's derivation, recorded per spec in the recipe header: those under the
move in the same list whose range gate is the move's target range. Where a move has terms beyond distance (the
hunter weave's "Weave fits" and the ranged clock's "more than 0.5 s to the next shot"), the owner's form drops them
on the ON side. The melee strikes then show whenever they are ready, not only when the weave fits. An alternative is
`(toggle.movement&<the move's other terms>|<range gate>)`: still nothing modelled, but those terms read the ranged
clock and walk-time variables. This is an owner check (§9).

### 2.3 Where it applies at e2842f0a78

| Spec | Move reached entries | ON | OFF |
| --- | --- | --- | --- |
| Hunter BM / MM / SV (weave) | Raptor Strike, Mongoose Bite (`within5`); the shots (`outside5`) after the move back | Strikes and shots both eligible; APL order decides; strikes tinted at range, shots tinted in the dead zone | Strikes only within 5, shots only outside it (today's pack) |
| Feral (adaptive) | The damage lines after "Finish closing to melee" | Shown, tinted, out of melee | Hidden until in melee |
| Guardian (adaptive) | As Feral; Feral Charge is a cast and stays as it is | As Feral | As Feral |
| Retribution (default) | The melee lines the "Move to melee" group (`not spellInRange(Crusader Strike)`) defers | Shown, tinted | The group's ranged lines only, until in range |
| Demonology (brand) | The melee-range AoE behind the 3-target move | Shown, tinted | Hidden until within 5 |

Pre-pull "pull range" moves (the hunters' and Retribution Holy Shock's, at -19 / -20 s) reach no rotation entry, so
nothing changes.

## 3. Waits, and the ranged clock

wowsims's `wait` holds the rotation for a duration, and the weave times several waits from the ranged auto-shot.
Hekili's engine has a `wait,sec=` action (Core advances the delay and re-walks, so the next pick shows with its
countdown). Each evaluation stays stateless.

Default: waits stay omitted, as today. A `wait` is translated only if the replay shows it moves agreement with
wowsims. Phase 3 measures this on today's hunter logs, whose weave already has the waits. Any `wait` or `waitUntil`
whose duration or condition reads walk terms ("Time to walk in", `unitMovementSpeed`) stays omitted regardless, since
those are movement (decision 6). Non-distance `waitUntil` entries (Protection Paladin, Rogue pooling) are classified
by the builder entry by entry. Each becomes `wait,sec=` only when the time to its condition is a read the engine
already has. Otherwise it is omitted and listed.

The ranged auto-shot clock (class-completion C7) is needed only if waits are translated and their durations read
`RangedAuto`. It is a timer in the belief, not movement: Auto Shot's swing clock (hand 3,
`Game/State/Sources/Swing.lua`), already built and merged. It reaches the engine through the existing
`UnitRangedDamage` tail (`state.swings.ranged_projected` / `ranged_speed`). The only new code would be an engine
expression twin of `mainhand_remains`. Owner check (§9): keep reading it for the waits, or keep the waits omitted.
C7's in-game questions (layout.md H2-H5) stay open until launch either way.

`startAttack` and `petAttack` stay omitted.

## 4. The translator's new kinds

From the research's census. "Needed" means translated. "Omit" means rule 2, listed in the header.

| Kind | Used by | Decision |
| --- | --- | --- |
| `talentIsKnown`, `talentRank` | 9 specs; Feral | Needed: `talent.<key>.enabled` / `.rank` (rule 4's mechanism) |
| `spellIsCasting` | Balance, Fire, Frostfire, Arms, Demonology x2 | Needed: the engine's casting read of that spell; a precondition for dropping `no-cast-end-pick.patch` |
| `spellInRange` | Retribution, hunter weave | Needed: the ability's range read; §2's rewrite where a move reaches it |
| `unitDistance` beyond rule 11 (`OpNe` of a `max`) | hunter default #16 | Omit, as today |
| `move`, distance-only `waitUntil` | §2 | Omit; their range gate goes to the reached entries |
| `wait`, other `waitUntil` | §3 | Omit by default; translated only as §3 allows |
| `unitMovementSpeed`, `unitIsMoving` | hunter walk variables, Demonology | Omit, with what reads them (movement, decision 6). Demonology's move goes with them, its reached line taking §2's rewrite |
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

- No new crossing, and the engine and the belief change nothing for movement. The rewrite reads a setting and the
  existing range bracket. If waits are translated, the ranged clock arrives through the existing `UnitRangedDamage`
  tail.
- If the builder finds anything needing a new belief function or facade read, it stops and asks the owner.
- The new translated reads are simulation values or existing belief answers, so no new secret handling is needed.
- No closures or per-update tables are added on the walk.

## 7. Gates, the test world and accuracy

The rotation match with wowsims is proven by the replay. It already places us where wowsims stood, from the log's
Movement aura (`tests/Game/harness/replay.lua` `M.MOVE = 20`; the hunter logs carry 1257-1353 Movement lines). It
scores our pick at each of wowsims's casts.
- The replay gates run with Movement OFF. With wowsims's own positions, OFF's range gates read exactly what wowsims
  saw, which is the faithful match.
- ON's display widening is not a rotation difference to measure against wowsims. It is checked by one translation
  test per opted-in spec: with the toggle on, a reached entry shows out of range; with it off, it is hidden until in
  range. ON's replay agreement is printed as a reported, ungated line, so its cost is visible.
- The loops measure the belief against the oracle (the same engine), not the APL against wowsims. Movement modelling
  does not help that, so under decision 6 the loop world gets none, and the earlier draft's hunter loop walk is
  dropped. The loops run with Movement OFF. The hunter worlds keep their fixed distance and play today's range-gated
  strikes, so no loop line moves for the toggle.
- No test assumed a simulated move (none was built), so none needs to change. The harness sets the toggle through the
  profile it boots; the builder picks the hook.

Floors (decision 4): the baseline is the pre-re-pin `make accuracy`.
- A pack within max(0.02, 2/n) of it (the lane P rule R2) is re-floored on its re-export, naming the re-pin.
- A pack beyond that is traced first (kit, world, central or API-forced, P7's classes), and the cause is written
  beside the number.
- Flicker and LIVE60 follow the same rule.
- "New basis" packs (below) take the re-pin as the named cause, and their top three disagreements are classified
  before the floor is set.

| Spec | Change | Expected |
| --- | --- | --- |
| Balance, Mage x3, Shadow, Smite, Affliction, Elemental, Prot Paladin, Prot Warrior | APL edits, gear, talents; casters' `spellIsCasting` guards | Hold. Casters may move at the patch drop |
| Rogue x3 | energy-pooling group, `affords` | Small; the pooling `waitUntil` (omitted or a `wait`) is the risk |
| Arms, Fury | strict-sequence stance swaps, per-spell GCD compares, cd-usage folds | Likely drop; trace each |
| Enhancement | rotation inside the build; Skyborne; item swap omitted | Small to medium |
| Warlock x5 | Banes replace `select`; Sesam's Demonology APLs; `petAttack` / `changeTarget` omitted | Demonology and Destruction likely drop |
| Retribution | new talent-adaptive APL and gear | New basis. OFF replay: the move-reached lines are gated as wowsims's positions say |
| Feral, Guardian | adaptive APLs (42 / 15 variables), Berserk gone | New basis. The omitted `waitUntil` is a small risk: wowsims holds where we may show a lower line, but it casts nothing while holding, so few scored decisions |
| Hunters x3 | SIML weave builds, Sniper Shot, waits omitted unless §3 earns them | New basis: the old floors (1.00 / 0.92 / 0.97) are not comparable. The omitted waits and walk terms are the main risk |

## 8. Order of work: independently gated phases

Each phase ends green (`make check`, and `make gate` where packs move).

1. Plumbing: the CLI with `siml`, the SIML step, the recipe paths, `M.ENCOUNTER`. Gate: one request exports, and the
   dry-run omit counts match the research.
2. Translator kinds (§4). Gate: unit tests, and the omit counts falling on the low-change specs.
3. The Movement setting and the range-gate rewrite (§2). Also the wait measurement (§3): today's hunter packs
   regenerated at the old pin, the replay run OFF (must equal today's) and ON (reported), and with and without
   translated waits. That decides whether waits, and so the ranged clock read, are kept.
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
- Owner check: the ON form. Either the owner's `(toggle.movement|<range gate>)`, where the hunter strikes show
  whenever ready, or the variant that keeps the move's non-distance terms (§2.2).
- Owner check: whether the hunter weave's waits are translated with the ranged auto-shot clock (C7, a belief timer,
  not movement), decided on phase 3's measurement (§3).
- Owner check: the replay gates run OFF, with ON reported only (§7).
- In game after launch: C7's H2-H5 if the waits are kept, and the tint during a walk with Movement ON (a ledger row
  added in phase 3).
