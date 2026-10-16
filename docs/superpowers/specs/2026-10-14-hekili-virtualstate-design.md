# VirtualState: Phase 1 design

Date: 2026-10-14. Branch: `virtualstate-design` from `forever` at fc61b6d9 (Checkpoint B, a clean load on
Forever). Implementation branch: `virtualstate-phase1`. Line numbers below are as read at fc61b6d9 unless a
cite says otherwise.

Cite conventions:
- A bare `File.lua:N` is Hekili at fc61b6d9.
- `TDF src/TacoDogForever/<path>:<lines>` and `TDF tests/<path>:<lines>` are Taco Dog Forever (TDF) at main
  7bef7b5.
- `inputs/<name>.md §N` is a research output saved in this repo under
  `docs/research/2026-10-14-virtualstate-inputs/`.
- "feasibility §X" is section X of
  `~/src/docs/research/tdf/2026-10-14-hekili-virtual-state-feasibility.md`. Its Hekili cites are at
  36daec38 (before the cleanup); this spec re-cites them at fc61b6d9 where it carries a line. Everything this
  spec needs from it is inlined below.
- "cleanup Qn" is row n of §5 of `docs/forever-cleanup.md`; "facade notes" is `docs/forever-facade-notes.md`.

## 0. Purpose and scope

Hekili on `forever` loads cleanly on WoW Forever, and every game read goes through one facade (today
`Libs/VirtualGameAPI-1.0`, 124 passthroughs and 51 stubs, `tools/api_inventory.txt` 175 names). The stubs are
the reads that are secret in combat (resources, cooldown times, aura data, stats, target health, swing speed,
totems) or absent on Forever, so Hekili loads but cannot recommend: `UnitPower` reads 0 and nothing with a
cost is ever recommended, `UnitHealth` reads 0 and the enemy scan sees one target, regen is 0, and every spell
is off cooldown (cleanup Q16; facade notes "Stub call sites that would throw or misbehave").

VirtualState is the missing piece: a module inside Hekili (`ns.VirtualState`, files under `Virtual/State/`)
that keeps the present game state carried forward from plain observations (our own casts, swings, usability
flips, cooldown flag edges, aura reads, out-of-combat reads) and answers the secret reads in combat. The
facade folds into the same folder as `Virtual/API/Facade.lua` (`ns.Facade`) and keeps only the names that are
secret in combat, partly secret, or absent on Forever; every plain name goes back to a direct call.

Phase 1 covers all state Hekili needs to recommend for a Warrior on a dummy: resources and regen, cooldowns,
charges and the GCD, auras on the player and target, swings and attack speed, haste, health, movement, totems,
talents, the target's cast and the enemy count. It reuses the mechanics TDF proved in game (the observation
log, the belief families, the secrecy gate, the test helpers) and Hekili's own class model, which the specs
already register. Phase 2 (investigating an eventing API) and Phase 3 (an event bus) are deferred; §14 lists
what Phase 1 leaves out.

## 1. Decisions

These ten decisions were made with the user on 2026-10-14. They are fixed for Phase 1.

1. **VirtualState lives inside Hekili.** It is a module of several files under a new `Virtual/State/` folder,
   reached as `ns.VirtualState`, not a LibStub package. Rationale (the user's): extracting state tracking out
   of Hekili duplicates the class model Hekili's specs already define. TDF reuse is not a goal. The first
   design draft, saved with the research inputs, was a standalone library named VirtualGameState-1.0 (VGS)
   with its own class data; the integration pass called the component a nowcast. Both shapes are superseded;
   their families, policy table, clock, tests and risks carry over into §§2-12.
2. **One registration, two consumers.** The class file registers its models once with Hekili: resource regen
   models in `RegisterResource`, each ability's `spend` and `handler`, each aura's `duration`, cooldowns and
   charges. Hekili's predictor applies them to `state`; VirtualState applies the same registered functions to
   learn what a real cast did ("apply through the spec", §5). Those functions are bound to `state` at
   registration (feasibility §D.2: `spend` and `handler` are `setfenv`'d to the singleton `state`, which has
   no second instance), so VirtualState uses `state` itself as the calculator. There is no second model and no
   data file. A new registration API is added only for a Forever-only fact Hekili's model lacks; none is
   identified for Warrior (swing-based rage regen models already exist, e.g.
   `archive/TheWarWithin/WarriorArms.lua:36-56`).
3. **The facade folds into Hekili and is stripped.** `Libs/VirtualGameAPI-1.0` becomes
   `Virtual/API/Facade.lua` (`ns.Facade`) covering only the 51 names that are secret in combat, partly secret
   or absent on Forever (§7). The 124 plain passthroughs revert to direct calls (about 100 lines across 14
   files, 42 of them in `State.lua`). The absent names cannot be called directly on Forever and stay as
   guarded stubs. `tools/api_inventory.txt`, `tools/check_api_reads.sh` and `.luacheckrc` then enforce only
   the facade list. Four passthroughs are probed in combat before their revert: `C_Item.GetItemCooldown`,
   `C_Spell.IsSpellUsable`, `UnitThreatSituation` and `InCombatLockdown` (it lags at `PLAYER_REGEN_DISABLED`,
   feasibility §C.3).
4. **Access is through functions only.** Facts return plain values; drifting quantities take `now` and return
   a preallocated Belief record (§2). There are no metatables and no open state tables. The Belief is a
   preallocated record handed out read-only by convention, and `VirtualState.Count` is a namespace table of
   functions. Iterators fill caller-supplied arrays. `VirtualState.Snapshot()` exists from day one.
5. **The Belief record** has four origin slots and no tri-state (§2): unknown is a wide interval, low conf and
   basis `"unknown"`. Records are preallocated and overwritten in place; a debug-only ring keeps at most 8
   samples per origin.
6. **The API is keyed by entity; aggregates are separate.** An accessor names one entity (a unit token or
   GUID, a spell ID) plus `now`. Units are a tracked set the sources populate (the walks of decision 7 feed
   it). Aggregates live in `VirtualState.Count.*` (`Enemies`, `WithAura(id)`, `InRange(id)`) and are what
   `active_enemies`, `active_dot.x` and `spell_targets` stand on (no Hekili code reads them in Phase 1, §6.9).
   How a source reads (a walk or per ID) is invisible to the accessor.
7. **Collection walks by default, per-ID reads as the fallback** (the user's ruling). Wherever the game offers
   a collection read, the source walks it once per trigger and filters by the tracked set with a hash lookup.
   Per-ID reads remain where no collection exists or the collection costs more (§4.5).
8. **Tracking is declared by Hekili core; packs are the exception.** Core enables tracking for everything
   `state` itself reads to serve packs: the categories `state.reset()` and the lazy metatables consume
   (resources and regen, cooldowns and charges, GCD, auras per unit, swing and attack speed, haste, casts,
   health, movement, totems, talents, enemy count), with the per-ID sets taken from the active spec's
   registrations (`class.abilities`, `class.auras`, `class.resources` after `Hekili:SpecializationChanged`,
   `Classes.lua:3077`). That is the whole tracked set in the normal case, with no growth at runtime.
   `VirtualState.Track{}` exists only for a class pack that needs something core does not already track (a
   proc source, an extra unit). The collection sources (nameplates, range) are always on in Phase 1; enabling
   them only when a loaded pack's scripts reference `active_enemies`, `spell_targets` or range is a later
   refinement.
9. **TDF mechanics are ported, not its engine.** The observation log ring, the families' pin, ladder, regen
   EMA, swing and aura logic, the `Sources.Plain` secrecy gate, the test helpers and the secrets static test
   move into `Virtual/State/`, adapted to the Belief record and the functions-only API. TDF's SpecBuilder,
   Helpers, Timeline and Forecast are not ported: the effects of a cast come from decision 2. Both
   repositories are the user's; the clean-room rule forbids only Hekili → TDF.
10. **Three phases.** Phase 1 is this spec: core VirtualState for all the state Hekili needs. Phase 2 is a
    deferred investigation of an eventing API. Phase 3 is a deferred event-bus plan written after Phase 2.

## 2. The Belief record

Every drifting quantity (a resource, a cooldown's ready time, an aura's expiry, a swing, haste, health, a
totem, the target's cast end, the enemy count) is answered with one Belief record:

```lua
Belief = {
  est, lo, hi, conf,              -- projection to `now`; hot-path reads
  basis = "pinned",               -- which `last` slot est stands on; "unknown" if none
  last = {
    observed = { v, t, event },   -- last plain read or exact event ("last seen")
    pinned   = { v, t, event },   -- last exact inference from a plain fact (usability flip, cost ladder)
    modelled = { v, t, event },   -- last carry-forward written by applying the spec
    default  = { v, t, event },   -- the fallback in force (spec duration, rest value)
  },
}
```

**Fields.**
- `est`, `lo`, `hi`: the estimate and its interval, projected to the `now` the caller passed.
  `lo <= est <= hi`.
- `conf`: 0..1, by the family's formula (§6).
- `basis`: one of the interned strings `"observed"`, `"pinned"`, `"modelled"`, `"default"`, `"unknown"`. It
  names the `last` slot the estimate stands on: the newest of `observed`, `pinned` and `modelled` by `t` (ties
  go in that order), else `default` when one is in force, else `"unknown"`.
- `last.<origin>.v`: the sample's value in the quantity's own units (a resource amount, an absolute ready
  time, an absolute expiry, a swing time). `t`: the absolute `GetTime()` of the sample. `event`: the integer
  observation kind that produced it (`VirtualState.Obs`, below), 0 when none. A slot never written has
  `t = 0`.

**Origins** (the provenance terms of the virtual combat log research, feasibility §D.2):
- `observed`: a plain read (out of combat, or a value that stays plain in combat) or an exact event
  (`PLAYER_SWING`, our own `UNIT_SPELLCAST_*`).
- `pinned`: an exact inference from a plain fact. A usability flip pins a resource to that ability's cost; the
  set of usable and unusable abilities bounds it (the cost ladder); a cooldown flag edge snaps a ready time.
- `modelled`: a carry-forward written by applying Hekili's registered functions to a real cast (§5), or by a
  family's own model (regen between pins, a swing step).
- `default`: the fallback in force: the spec's aura duration, a resource's rest value, a weapon speed of 2.0,
  a TTD of 30 s.

**Event enum.** `VirtualState.Obs` is TDF's `Enum.Obs` with the same 34 kinds and the same integers
(`TDF src/TacoDogForever/Engine/Enum.lua:70-114`): `Usable` 1, `CastStart` 2, `CastSuccess` 3, `CastStop` 4,
`Read` 5 (with `c` a `ReadOf`), `Cooldown` 6, `PowerTick` 7, `TargetSwap` 8, `CombatStart` 9, `CombatEnd` 10,
`TargetGone` 12, `Queued` 14, `Swing` 15, `Haste` 16, `Moving` 17, `Talent` 18, `Enemies` 19, `ChannelStart`
24, `ChannelStop` 25, `ChannelUpdate` 26, `CastDelay` 27, `Totem` 30, `Range` 33, `TargetCast` 34. The kinds
Phase 1 does not log (`Group`, `Known`, `Encounter`, `TargetInfo`, `PlayerInfo`, `GameError`, `PackEvent`,
`Pet`, `Gear`, `ItemCooldown`) keep their integers reserved so the two enums never diverge.

**No tri-state.** There is no separate "unknown" flag. A quantity with nothing known has `lo` and `hi` at the
widest legal bounds (0 and the max for a resource), `conf = 0`, and basis `"unknown"`; `est` is the default
when one exists. This follows TDF, where unknown is a wide interval plus low conf
(inputs/tdf-state-patterns.md §2).

**Projection rules.** The fold (§8) keeps each family's values at the belief clock in preallocated arrays
(`est0`, `lo0`, `hi0` by slot). An accessor writes the record's `est`, `lo`, `hi` and `conf` from those values
projected to `now` and returns the record. Every projection starts from the clock values, so the order of
reads never matters, and accessors never fold, flush or call the game. With `dt = max(0, now − clock)`:
- **Resources:** `est0 + regen.est·dt`, `lo0 + regen.lo·dt`, `hi0 + regen.hi·dt`, each clamped to `[0, max]`.
- **Absolute-time quantities** (a cooldown's ready time, an aura's expiry, a totem's expiry, the target's cast
  end) do not move; only their conf decays with age.
- **Swing:** `est` is the first predicted swing strictly after `now`,
  `anchorT + (floor((now − anchorT)/speed) + 1)·speed`
  (`TDF src/TacoDogForever/Model/Belief/Swing.lua:197-201`).
- **No backward projection:** a `now` before the clock projects with `dt = 0`.

**Zero-allocation rule.** Every record, every `last` sub-table and every result array is allocated once, when
the tracked set is built (§3.6), and overwritten in place. Accessors, the fold, flush, polls and the facade
policies allocate nothing (§11 tests it). A record is reused per (family, entity): a second call for the same
entity overwrites the record the first call returned, so a caller copies the fields it needs before the next
call.

**Debug rings.** `VirtualState.SetDebug(true)` allocates, per record and per origin, a ring of 8 preallocated
`{ v, t, event }` slots; each sample written to `last.<origin>` is also pushed into its ring. With debug off
(the default) no ring exists and nothing is pushed. `Snapshot()` prints the rings when present.

## 3. Public API

`ns.VirtualState` is a table of functions. No field of it is state; nothing is read by indexing into it except
functions and the `Obs`/`Count` namespaces. Every drifting accessor returns the Belief record:

```lua
Belief = {
  est, lo, hi, conf,              -- projection to `now`; hot-path reads
  basis = "pinned",               -- which `last` slot est stands on; "unknown" if none
  last = {
    observed = { v, t, event },   -- last plain read or exact event ("last seen")
    pinned   = { v, t, event },   -- last exact inference from a plain fact (usability flip, cost ladder)
    modelled = { v, t, event },   -- last carry-forward written by applying the spec
    default  = { v, t, event },   -- the fallback in force (spec duration, rest value)
  },
}
```

### 3.1 Facts (plain values)

| Function | Returns |
|---|---|
| `InCombat()` | boolean, from `PLAYER_REGEN_DISABLED`/`ENABLED` (not `InCombatLockdown`, which lags, feasibility §C.3) |
| `Talent(talentID)` | rank (integer, 0 when not taken), from the `C_Traits` walk |
| `TalentGen()` | integer, bumped when any rank changes |
| `Stat(apiName, arg)` | the returns of the last plain out-of-combat call `apiName(arg)` for the 12 stat names (§7), in the real API's return order; zeros before the first read |
| `CooldownLength(spellID)` | seconds: the length learned from the last observed cooldown, else the spec's `cooldown` |
| `GcdInfo(now)` | `start, duration` of the current GCD as plain numbers, fixed between edges (§7.5); `0, 0` when none |
| `LastSwing(hand)` | the absolute time of the last observed swing of hand 1 (main) or 2 (off), 0 when none |
| `Moving()` | boolean, from `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING` |
| `HealthMax(unit)` | number: the player's last plain read; 100 for any other unit |
| `AuraGen(unit)` | integer, bumped when that unit's believed aura set changes (an aura appears, disappears or changes stacks or expiry) |
| `TargetCastFacts()` | `channel, castBarID, start, interruptible` (interruptible 1 yes, 0 no, -1 unknown); `nil` when the target is not casting |
| `TotemFacts(slot)` | `spellID, name, icon, start, duration` for totem slot 1-4; `nil` when the slot is empty |

### 3.2 Drifting accessors (take `now`, return a Belief)

Origins: O observed, P pinned, M modelled, D default.

| Function | Returns | Origins that write it |
|---|---|---|
| `Power(powerType, now)` | Belief amount | O (types plain in combat, e.g. combo points; out-of-combat reads), P (usability flip, cost ladder), M (casts via §5, regen, swing steps), D (rest value) |
| `Regen(powerType, now, casting)` | Belief per second; `casting` selects the in-cast rate | O (out-of-combat read), M (EMA calibration between pins), D (the spec's declared rate) |
| `Cooldown(spellID, now)` | Belief ready time, or `nil` for an untracked spell | O (out-of-combat times), P (`isActive` edges, `CD_PROBE`), M (cast via §5), D (spec cooldown) |
| `Charges(spellID, now)` | two Beliefs: current charges, next charge time; `nil` for a spell without charges | M (cast via §5), D (spec `charges`/`recharge`) |
| `Gcd(now)` | Belief GCD end | P (`isOnGCD` edges), M (cast via §5) |
| `Aura(unit, spellID, now)` | Belief expiry, then `stacks, applied, instanceID`; `nil` when not believed up | O (plain walk), P (a flag edge), M (cast via §5), D (spec duration) |
| `AuraAt(unit, filter, i, now)` | `spellID`, Belief expiry, `stacks, applied, instanceID` for the i-th believed aura matching `"HELPFUL"`/`"HARMFUL"`; `nil` past the last. Order: applied time ascending, then walk order; only auras with `est > now` | as `Aura` |
| `AuraByInstance(unit, instanceID, now)` | `spellID`, Belief expiry, `stacks, applied`; `nil` when gone | as `Aura` |
| `Swing(hand, now)` | Belief next swing | O (`PLAYER_SWING`), M (anchor + k·speed, paired rage steps), D |
| `SwingSpeed(hand, now)` | Belief seconds | O (`PLAYER_SWING` duration, out-of-combat read), D 2.0 |
| `Haste(now)` | Belief melee multiplier | O (out-of-combat read), M (base speed ÷ observed swing duration) |
| `SpellHaste(now)` | Belief percent | O (last plain read), D 0 |
| `Health(unit, now)` | Belief fraction 0..1 | player: O (plain read), D 1.0; target and others: D 1.0 |
| `TTD(unit, now)` | Belief seconds | D 30 |
| `Totem(slot, now)` | Belief expiry, `nil` when empty | O (out-of-combat read), P (`PLAYER_TOTEM_UPDATE` with no cast: destroyed), M (cast via §5) |
| `TargetCast(now)` | Belief cast end, `nil` when not casting | O (start and stop events by `castBarID`), D (default length) |

### 3.3 Aggregates: `VirtualState.Count`

| Function | Returns |
|---|---|
| `Count.Enemies(now)` | Belief count: O (nameplate walk, plain `UnitIsDead`/`UnitCanAttack`), D 1 |
| `Count.WithAura(spellID, now)` | integer: tracked units (target and remembered target slots) on which the aura is believed up |
| `Count.InRange(spellID, now)` | integer: tracked enemies in range of the spell (plain `C_Spell.IsSpellInRange` per plate) |

### 3.4 Iterators

`VirtualState.Tracked(kind, out)` fills the caller's array `out` with the tracked IDs of `kind` (`"ability"`,
`"aura"`, `"resource"`, `"unit"`) and returns the count. It never allocates; `out` is reused by the caller.

### 3.5 Snapshot and debug

- `VirtualState.Snapshot() → string`: every tracked record (est, lo, hi, conf, basis, the four `last` slots),
  the facts, the log's fill and drop counts, the read statuses per source (`"readable"`, `"secret"`, `"nil"`,
  `"error"`) and, with debug on, the rings. It allocates and is for debugging only
  (`/run print(Hekili.VirtualState.Snapshot())`; Adapter.lua sets the `Hekili.VirtualState` handle, §9).
- `VirtualState.SetDebug(on)`: creates or drops the debug rings (§2).

### 3.6 The tracked set and lifecycle

- `VirtualState.Start(api)`: once, at `PLAYER_LOGIN`; `api` is `_G` in game and a fake in tests. Creates the
  module's own event frame, registers the source events (§4.1) and starts the per-frame flush.
- `VirtualState.SpecChanged()`: called at the end of `Hekili:SpecializationChanged` (`Classes.lua:3077-3362`).
  It rebuilds the tracked set from what `state` reads (decision 8): every key of `class.abilities` (spell IDs
  and cooldown, charges, cost and GCD flags), `class.auras` (player and target, durations), `class.resources`
  (power types, regen models, rest values), the swing hands, the four totem slots, the talents in
  `class.talents`, the target's cast, the player's health and movement, and the enemy count. It allocates
  every record and array for that set; nothing grows afterwards.
- `VirtualState.Track{ abilities = {...}, auras = {...}, units = {...} }`: the pack exception. Called from a
  class file at load, it adds IDs core does not already track; they join the set at the next `SpecChanged`. It
  allocates (load time only).
- `VirtualState.Drain(cutoff)`: the fold plus apply through the spec (§5), called only from `Hekili.Update`.

## 4. Observation log and sources

### 4.1 The log

A preallocated ring of 256 observations `{ kind, t, a, b, c }`: `kind` a `VirtualState.Obs`, `t` the
`GetTime()` of the handler, `a` an ability, aura or resource slot (or 0), `b` the value, `c` extra (by kind).
`Add` allocates nothing; a full ring drops the oldest and counts it in `dropped`; `At` and `Shift` hand out
reused records (read them, never keep them); `Clear` empties it. Port of
`TDF src/TacoDogForever/Model/ObsLog.lua:26-82` (`New` :26, `Add` :44, `At` :63, `Shift` :70, `Clear` :79);
the size is TDF's `App.LOG_CAP = 256` (`TDF src/TacoDogForever/Game/App.lua:26`). Only `Drain` consumes the
log. If `Hekili.Update` returns at a guard for a long time, the ring drops the oldest observations;
`Snapshot()` shows the count, and the beliefs coast on their models until the next drain.

### 4.2 Sources and the event table

Sources are the only VirtualState code that touches the game, and only through the injected `api` table. Each
source registers its events on VirtualState's own frame and logs observations. The table below is the Phase 1
set (port of `TDF src/TacoDogForever/Sources/Sources.lua:64-129`, `Sources.EVENTS`). "New" marks an event no
loaded Hekili file registers today: `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_USABLE`, `ACTIONBAR_UPDATE_USABLE`
and `PLAYER_SWING*` are registered nowhere, and the only swing code is CLEU `SWING_*` at
`Events.lua:1684-1699`, dead on Forever (inputs/hekili-integration-points.md §4). These are new *event
registrations*, distinct from decision 2's registration API.

| Event | Source | Logs | New |
|---|---|---|---|
| `UNIT_SPELLCAST_SENT` (player) | Casts | the cast target GUID for the next start/success | |
| `UNIT_SPELLCAST_START`, `_SUCCEEDED`, `_FAILED`, `_INTERRUPTED`, `_DELAYED` (player) | Casts | `CastStart` (b: end), `CastSuccess`, `CastStop`, `CastDelay` (b: new end) | |
| `UNIT_SPELLCAST_CHANNEL_START`, `_UPDATE`, `_STOP` (player) | Casts | `ChannelStart`, `ChannelUpdate`, `ChannelStop` | |
| `UNIT_SPELLCAST_START`, `_STOP`, `_INTERRUPTED`, `_CHANNEL_START`, `_CHANNEL_STOP`, `_INTERRUPTIBLE`, `_NOT_INTERRUPTIBLE` (target) | Target | `TargetCast` by `castBarID` (plain; spellID and castGUID are secret on the target) | |
| `SPELL_UPDATE_USABLE`, `ACTION_USABLE_CHANGED` | Spellbook | triggers the usability ladder poll (§4.3) | yes |
| `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES` | Spellbook | `Cooldown` per tracked spell whose plain `isActive` flag changed (b: 1 ready / 0 not); GCD edges from `isOnGCD` | yes |
| `PLAYER_SWING` | Swing | `Swing` (a: hand, b: swing duration, c: 1 swung) | yes |
| `UNIT_ATTACK_SPEED`, `PLAYER_EQUIPMENT_CHANGED` | Swing | `Swing` reads (c: 0) out of combat | yes |
| `UNIT_POWER_FREQUENT`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER` (player) | Power | `PowerTick` (a: slot); a plain `UnitPower` read as `Read` | |
| `UNIT_AURA` (player, target) | Auras | the walk of §4.5 into `Read` (c: aura) per tracked aura found | |
| `PLAYER_TARGET_CHANGED` | Auras, Target | `TargetSwap` | |
| `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED` | Player | `CombatStart`, `CombatEnd`; on `ENABLED` the out-of-combat re-read of stats, regen, speeds and totems | |
| `PLAYER_STARTED_MOVING`, `PLAYER_STOPPED_MOVING` | Player | `Moving` | |
| `UNIT_SPELL_HASTE` (player) | Player | `Haste` (a plain read only) | yes |
| `TRAIT_CONFIG_UPDATED`, `PLAYER_TALENT_UPDATE`, `SPELLS_CHANGED` | Talents | `Talent` per changed rank after the walk | |
| `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED` | Nameplates | the plate GUID set; `Enemies` at the next poll | |
| `PLAYER_TOTEM_UPDATE` | Totems | `Totem` (a: slot) | yes |

Hekili's own handlers for the shared events stay as they are; VirtualState's frame hears the same events
independently (risk G2 covers the order).

### 4.3 Polls

Once per drain, before the fold, the polls run in this order, each straight into the log at the drain's time
(port of `TDF src/TacoDogForever/Sources/Sources.lua:563-588`, `Sources.Poll` and its order list):
1. readable resources (types plain in combat, e.g. combo points);
1.5. the player's health, when plain, and its maximum;
2. the usability ladder: `C_Spell.IsSpellUsable` per tracked spending ability, each answer a `Usable`
   observation (b: usable, c: 1 when unusable for lack of its resource); a secret in either return means no
   news (`TDF src/TacoDogForever/Sources/Power.lua:62-95`);
3. the swing queue: `C_Spell.IsCurrentSpell` for each `onNextSwing` ability (`Queued`);
4. target death (plain `UnitIsDead`);
5. the nameplate walk (`Enemies`);
6. the deferred talent walk;
7. the four totem slots (out of combat);
8. range (`C_Spell.IsSpellInRange` per tracked plate for `Count.InRange`); TDF runs range after its item
   answers, which are not ported.
9. the form read after a build or a form event;
10. once combat has ended, the player's (and an existing target's) aura walk of §4.5 again, retried until the
    player walk completes: the in-combat down-states stand until a plain walk, and no `UNIT_AURA` comes while
    the buffs stay unchanged.

### 4.4 Staging, flush and the urgent lane

Aura reads go straight to the log. Every other event observation is staged (cap 128, excess dropped and
counted) and flushed into the log at the start of the next frame by VirtualState's own `OnUpdate`, so a
frame's aura reads always precede its casts in the log (`TDF src/TacoDogForever/Sources/Sources.lua:52` the
cap, `:540` `Stage`, `:552-561` `Flush`). Every record carries the `GetTime()` of its handler.

**Urgent lane.** `PLAYER_SWING`, our own `UNIT_SPELLCAST_*`, usability flips and cooldown flag edges call
`Hekili:ForceUpdate(event)` from VirtualState's handler. `ForceUpdate` only shortens the wait before the next
cycle; it never interrupts a running cycle (`UI.lua:2459-2470`). No source drains, folds or applies inside an
event handler.

### 4.5 Collection walks and the per-ID fallbacks

**Cost rule.** A collection walk is the default when its cost is bounded by the unit's own aura count (or the
plate count, or a fixed slot count) and it aborts early on a secret. A per-ID read is the fallback where no
collection exists or the collection costs more.

Walks (one per trigger, filtered by the tracked set with one hash lookup per entry):
- **Auras:** one `C_UnitAuras.GetAuraDataByIndex(unit, i, filter)` walk per unit per `UNIT_AURA`, helpful then
  harmful, each call `pcall`'d. The walk stops at the first error, secret or nil, so in combat it costs one
  call per filter. Entries whose `spellId` is tracked become `Read` observations (remaining time, stacks). The
  walk sees `sourceUnit`, so "ours or someone else's" falls out of it for free.
- **Enemies:** the nameplate tokens from `NAME_PLATE_UNIT_ADDED`/`_REMOVED`, judged with plain `UnitExists`,
  `UnitIsDead`, `UnitCanAttack`.
- **Totems:** the four slots of `GetTotemInfo` (out of combat).
- **Equipped weapons:** the inventory slots for weapon speed (out of combat).
- **Talents:** one `C_Traits` tree walk, itself a collection (plain and identical in combat, facade comment
  `[W PR5]` at `Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua:177-184`).

Per-ID reads (no collection, or the collection costs more):
- cooldown flags and usability: `C_Spell.GetSpellCooldown` (only the plain `isActive`/`isOnGCD` flags are
  used) and `C_Spell.IsSpellUsable` per tracked spell;
- `C_Spell.GetSpellPowerCost` per tracked ability (plain), read out of combat to confirm the spec's cost;
- auras by ID where a unit has no walk worth doing: TDF's per-ID loops
  (`TDF src/TacoDogForever/Sources/Auras.lua:71-74` for the player, `:145-148` for the target) are the
  fallback.

**The `Plain` gate and `pcall`.** Every client value passes through `Plain(api, v)`, which returns nil when
`api.issecretvalue(v)` (`TDF src/TacoDogForever/Sources/Sources.lua:42-46`, from Catnip's secret-value
research). A secret means no observation is logged. Calls that raise on secret data
(`C_UnitAuras.GetAuraDataByIndex` on a target in combat raises "Auras cannot be accessed when secret while
tainted", feasibility §C.3) are `pcall`'d and their raw result tested with `issecretvalue` before any field is
touched (`TDF src/TacoDogForever/Sources/Auras.lua:42, 74, 148`). A table with mixed fields
(`C_Spell.GetSpellCooldown`: `isActive` and `isOnGCD` plain, times secret) is tested field by field. In combat
a missing aura counts as down only after that aura was seen readable in combat; before that a nil may be the
client hiding it, and nothing is logged (`TDF src/TacoDogForever/Sources/Auras.lua:58-61`). No VirtualState
code compares or does arithmetic on a value without `issecretvalue()` first, and none uses `a and b or c` on a
possibly-secret value.

### 4.6 Feeding Hekili's across-reset caches

On Forever the CLEU handler is not registered (`Events.lua:174`), so nothing writes cast history:
`AddToHistory` (`Events.lua:912-943`) is the only writer of `player.lastcast`, `casttime`, `lastgcd`,
`lastoffgcd`, the `prev*` histories and `ability.realCast`, and it is called only from CLEU
(`Events.lua:1663, 1666`). Missing it makes every `prev_gcd` test false with no error (feasibility §B.2 E5d).
The own-cast source takes that job, synchronously in its handler, exactly where CLEU did it:
- on our `UNIT_SPELLCAST_SUCCEEDED`: `state:AddToHistory(key, destGUID)` for a known ability (the
  `UNIT_SPELLCAST_SENT` target GUID, else the target's);
- on our `UNIT_SPELLCAST_START` of a hard cast:
  `state:QueueEvent(key, start, finish, "CAST_FINISH", target, true)` into `realQueue`, as CLEU
  `SPELL_CAST_START` did (`Events.lua:1579`), with `start`/`finish` from the plain player `UnitCastingInfo`;
  `UNIT_SPELLCAST_DELAYED` already re-queues it (`Events.lua:1076-1089`);
- on our `UNIT_SPELLCAST_SUCCEEDED`, `_FAILED` and `_INTERRUPTED` of a tracked ability:
  `state:RemoveSpellEvent(key, true, "CAST_FINISH")` (`State.lua:5786`; `real = true` selects `realQueue`)
  removes the queued finish, as CLEU `SPELL_CAST_SUCCESS` (`Events.lua:1613-1614`) and `SPELL_CAST_FAILED`
  (`Events.lua:1603-1606`) did; on a failure or interrupt of a projectile ability it also removes the last
  `PROJECTILE_IMPACT` (`state:RemoveSpellEvent(key, true, "PROJECTILE_IMPACT", true)`, `Events.lua:1605`). On
  our `UNIT_SPELLCAST_CHANNEL_STOP` it removes the channel's queued ticks, finish and impacts with
  `state:RemoveSpellEvents(key, true)` (`State.lua:5820`), as CLEU did on a channel's `SPELL_AURA_REMOVED`
  (`Events.lua:1609-1610`);
- on our `UNIT_SPELLCAST_CHANNEL_START`: `CHANNEL_FINISH` and its `CHANNEL_TICK`s, as CLEU did
  (`Events.lua:1627-1635`).

The swing source writes the across-reset swing fields the dead CLEU branch wrote (`Events.lua:1684-1699`): on
`PLAYER_SWING` for a hand, `state.swings.mh_actual`/`oh_actual` = the event time and
`mh_projected`/`oh_projected` = that time plus the observed duration. Hekili's swing-rage models read them
through `mt_swings` (`State.lua:5119-5137`), so this is the feed feasibility §B.2 E7 calls exact from
`PLAYER_SWING`.

## 5. Applying through the spec

VirtualState learns what a real cast did by running the cast through Hekili's own registered functions on
`state`, then reading back what changed. This runs only on the update thread, inside `Hekili.Update`, never in
an event handler and never nested in a reset.

### 5.1 The drain point (closes R4)

`VirtualState.Drain(GetTime())` is called at the top of `Hekili.Update` (`Core.lua:1547`) after its guards:
`ScriptsLoaded` (`:1548-1551`), `IsValidSpec` (`:1553-1555`), `specID` (`:1559-1560`) and the spec and pack
lookups (`:1562-1569`), and before `Hekili:GetNumTargets( true )` (`:1573`) and the display loop (`:1580`).
`state.reset()` and the packs' `reset_precast` hooks assume those guards. The alternative, `UI.lua:2389-2393`
outside the coroutine, runs before the guards and is not used. The cycle runs
`state.reset(dispName, fullReset)` once per display (`Core.lua:1619`) in the order Interrupts, Defensives,
Cooldowns, Primary, AOE (`displayRules`, `Core.lua:1536`); a cycle starts when no thread is live and
`refreshTimer > (criticalUpdate and combatRate or refreshRate)` (`UI.lua:2383`), 0.2 s in combat and 0.5 s
otherwise (`UI.lua:2377-2378, 2434-2435`; the out-of-combat rate starts at 0.25 s until the first thread
ends).

The drain captures its cut-off at entry. Observations stamped later stay in the log for the next drain.

### 5.2 The procedure

One drain folds the log in order (§8) and applies each own cast at its own time. With the cut-off `T`:

1. Run the polls (§4.3), stamped `T`.
2. Fold observations in log order up to the first own-cast observation (`CastSuccess`, or `ChannelStart`) or
   `T`.
3. At an own cast at `t_cast` for a tracked ability `key`:
   1. **Pin the clock** (R1): set the facade's clock to `t_cast`, so every facade read answers the beliefs
      folded up to `t_cast` and projected to `t_cast`, not to `GetTime()`.
   2. **Reset once** (first own cast of this drain only): `state.reset()`. With no display name it resets as
      `"Primary"`, which forces the full path (`State.lua:6181-6184`).
   3. **Combat start** (R2): if the ability `startsCombat` and `state.combat == 0`, set
      `state.combat = t_cast − 0.01`, the value the `PLAYER_REGEN_DISABLED` handler writes
      (`Events.lua:856-863`).
   4. **Set the time:** `state.offset = t_cast − state.now`, `state.delay = 0`, so
      `query_time = now + offset + delay` (`State.lua:1814`) equals `t_cast`. This is the same offset step
      Hekili's simulation uses for a past event (`Core.lua:1714-1720`).
   5. **Read before:** copy the tracked fields named in §5.3 into preallocated arrays.
   6. **Apply the cast exactly as the simulation does** (`Core.lua:1984-2045`):
      - an instant: `state.setCooldown("global_cooldown", state.gcd.execute)` when the ability is on the GCD
        (`Core.lua:1993-1995`); `state.spendCharges(key, 1)` when `charges > 1 and recharge > 0`, else
        `state.setCooldown(key, ability.cooldown)` (`:2035-2040`); `ns.spendResources(key)` (`:2043`,
        `State.lua:6608-6636`); `state:RunHandler(key)` (`:2044`, `State.lua:6124-6168`);
      - a hard cast (its `CastSuccess` at the finish): the GCD step first, with the offset set to the
        `CastStart` observation's time (`state.offset = t_start − state.now`), then the offset of step 3.4
        (`t_cast`, the success time) for `state:HandleEvent(e)` on one preallocated event
        `{ type = "CAST_FINISH", action = key, time = t_cast }`, which runs `spendCharges`/`setCooldown`,
        `ns.spendResources` and `RunHandler` (`State.lua:5921-5953`);
      - a channel (at `ChannelStart`): `spendCharges`/`setCooldown`, `RunHandler` (which takes the channel
        path, `ability.start()` and `channelSpell`, `State.lua:6135-6137`) and `ns.spendResources`, as the
        simulation's channel branch (`Core.lua:2008-2031`).
   7. **Read after** and record each change as a `modelled` sample at `t_cast` (§5.3).
   8. Continue folding up to the next own cast or `T`. Later own casts in the same drain repeat steps 3.1 and
      3.3-3.7 without another reset: between casts `state` carries Hekili's own forward state, as in its
      simulation.
4. **Restore and reset** (R2, R3): `state.offset = 0`, `state.delay = 0`; unpin the facade's clock; fold the
   rest of the log up to `T`; if any cast was applied, mark both `state.player.updated` and
   `state.target.updated` and run one more `state.reset()` (full), so it rescans both units' auras. No apply-time
   mutation survives into recommendations, except the step 3.3 combat-start write, which stands in for
   `PLAYER_REGEN_DISABLED` (`state.combat` is not rebuilt by a reset; it is set only at `State.lua:511` and in
   event handlers, `Events.lua:346, 860-862, 879`).
5. When step 4 ran no reset, mark `state.player.updated` / `state.target.updated` for each unit whose
   `AuraGen` moved during the fold, so the cycle's resets rescan its auras (G1). After a trailing reset both units
   are already rescanned, so step 5 marks nothing.

Preconditions held by the procedure: `state.resetting` is false during step 3.6 (a reset clears it at its end,
`State.lua:6461`; with it true, `RunHandler` skips `state.modified`, `State.lua:6133`); the drain never calls
`state.advance`, so the 3-decimal rounding `advance` applies outside a reset (`State.lua:6519`) does not touch
`t_cast`; `realQueue` may hold future events, and the ordering of `HandleEvent` against back-dated applies is
verified in game (G8).

### 5.3 What is read back, and how it becomes `modelled`

For the applied ability and every tracked entity it can touch:
- each tracked resource's `state[resource].actual`: the change (after − before) shifts the resource belief's
  `est`, `lo` and `hi` by the same amount, and the shifted `est` is written as
  `last.modelled = { est, t_cast, CastSuccess }`. This is TDF's `step()`, which diffs the believed state
  around a cast and moves each interval by what the step changed
  (`TDF src/TacoDogForever/Model/Belief/Casts.lua:34-78`);
- `cooldown[key].expires`, `.duration`, `.charge`: the ready time (`expires`) as a `modelled` sample of
  `Cooldown(spellID)` (or of `Charges`), and the duration as the learned length when no edge has been seen;
- `buff[x]` and `debuff[x]` `.applied`, `.expires`, `.count` for each tracked aura whose fields changed: a
  `modelled` expiry sample, with stacks and applied time, and an `AuraGen` bump;
- `cooldown.global_cooldown.expires`: a `modelled` sample of `Gcd`.

The sample's `t` is `t_cast` and its `event` the observation kind applied (`CastSuccess`, `ChannelStart`). A
later `pinned` or `observed` sample supersedes it by time (§2).

### 5.4 Cost budget (G7)

A drain with own casts costs two full resets plus one apply per own cast per cycle; a drain with none costs
the fold only. Measured with `debugprofilestop()` around `Drain` and shown in `Snapshot()`; the expectation is
about 1-2 ms per cycle in combat. The trailing full reset is never skipped (R3). A drain whose log holds no
own cast runs neither reset and costs only the fold, so the reset cost scales with the number of own casts per
cycle.

### 5.5 Risks R1-R4, resolved

- **R1, clock mismatch.** `state.reset()` reads VirtualState through the facade, so a handler's reads
  (`buff.x.up`, `cooldown.x`, talents) would see beliefs projected to `GetTime()`, possibly including
  observations later than the cast. **Decision: clock pinning.** During a drain the facade's clock is pinned
  to the cast being applied, and the log is folded sequentially up to that time (steps 2, 3.1, 3.8). A skew
  allowance is not used. One limit remains, because a drain resets only once (step 3.2): for the second and
  later casts of a drain, a handler's reads of values cached at that first reset (resource `.actual`, scraped
  auras) see Hekili's simulated forward state, not beliefs folded to that cast's time; only lazy facade reads
  see the pinned clock. This is accepted because only the before/after difference of each cast is recorded
  (§5.3), and the skew is bounded by one cycle (0.2 s in combat).
- **R2, negative offset.** `query_time = now + offset` (`State.lua:1814`); a negative offset makes
  `state.time` negative, so `RunHandler`'s `StartCombat` branch (`State.lua:6159-6163`) never fires for the
  first cast, `fight_remains` inflates, and `full = dispName == "Primary" or state.offset > 0`
  (`State.lua:6184`) does not see a negative offset as needing a full reset. **Closer:** the restore and
  trailing full reset of step 4, the explicit `"Primary"` reset of step 3.2, and the combat-start write of
  step 3.3.
- **R3, dirty state.** The cycle's first display is Interrupts, a partial reset, which returns before the
  resources are re-read (`State.lua:6236-6250`), so apply-time mutations could leak. **Closer:** the trailing
  full reset of step 4; the spec relies on the full reset only, not on `ClearMarks` or the partial path.
- **R4, guards.** `UI.lua:2389` runs before `Hekili.Update`'s `ScriptsLoaded`/`IsValidSpec`/`specID` checks.
  **Closer:** the drain point of §5.1.

## 6. Belief families

Each family keeps its clock values in arrays by tracked slot, registers appliers per observation kind, and
writes its records at projection time. TDF registers families through `ns.BeliefShared` (`Applier(kind)`,
`Reader(readOf)`, `Listener(kind)`, `Init`; `TDF src/TacoDogForever/Model/Belief.lua:98-166`, per
inputs/tdf-port-mapping.md §2); VirtualState keeps that pattern and drops the Writer/FinalWriter/Serial parts
(no snapshot state, no persistence). Constants keep TDF's values: `PIN_GAP` 1, `ALPHA` 0.3, `REGEN_SPREAD`
0.1, `REGEN_SPREAD_MIN` 0.02, `REGEN_RATIO` 2, `EPS` 0.01, `CD_PROBE` 0.5, `SNAP_HOLD` 1, `AURA_HALF_LIFE` 10,
`CAST_GRACE` 0.5, `TARGET_CAP` 16, `FALSE_START` 1 (`TDF src/TacoDogForever/Model/Belief.lua:39-72`),
`READ_HOLD` 2 (`TDF src/TacoDogForever/Model/Belief/Resources.lua:26`), `SWING_DECAY` 10
(`TDF src/TacoDogForever/Model/Belief/Swing.lua:46`).

### 6.1 Resources

- **Appliers:** `Usable` (a flip pins the resource to that ability's cost; every report is a cost-ladder
  rung), `Read` of a resource (an exact pin; a late one is widened by the regen spread × lag), `PowerTick`,
  own casts through §5.
- **Pins and models:** `pin` (`TDF src/TacoDogForever/Model/Belief/Resources.lua:218-263`) sets the interval
  and, when two pins are at least `PIN_GAP` of white time apart, measures regen net of our own spends;
  `ladder` (`:275-315`) raises `lo` to an affordable cost or lowers `hi` below an unaffordable one, the newest
  bound winning; a late rung is moved by regen × lag and dropped if it then conflicts. `calibrate`
  (`:117-136`) is the regen EMA: a measurement within `1/REGEN_RATIO..REGEN_RATIO` of the declared rate
  updates `est` by `ALPHA`, the deviation sets the spread (floor `REGEN_SPREAD_MIN` of the rate). Swing-paid
  resources (rage) add the swing step (§6.4) and calibrate net of it. The declared rate, the rest value and
  the swing model come from the spec's `RegisterResource` (decision 2).
- **Conf:** `1 − (hi − lo)/max`, halved within `SNAP_HOLD` of a ladder snap
  (`TDF src/TacoDogForever/Model/Belief.lua:695-699`). Regen conf: `1 − spread/|est|`, floored at 0
  (`Resources.lua:131-132`).
- **Origin:** `TDF src/TacoDogForever/Model/Belief/Resources.lua` (`Applier` Usable :327, PowerTick :378;
  `Reader` Resource :365).

### 6.2 Casts, cooldowns, charges and the GCD

- **Appliers:** `CastStart`, `CastSuccess`, `CastStop`, `CastDelay`, `ChannelStart/Update/Stop` (the §5
  applies and the cast-in-progress fields); `Cooldown` (the plain ready flag); `Queued`.
- **Pins and models:** the cast step of §5 writes `modelled` ready times and charges. `constrain`
  (`TDF src/TacoDogForever/Model/Belief.lua:652-684`) snaps each cooldown to the game's flag after every fold:
  a ready flag pulls a later ready time back to now (and restores a charge); a not-ready flag pushes an
  earlier one to at least `now + CD_PROBE`. A ready edge after a cast teaches the real length (talent
  reductions included). The GCD starts at the `isOnGCD` rising edge; its duration is learned from the falling
  edge, else the spec's GCD ÷ haste.
- **Conf:** `1/(1 + age/AURA_HALF_LIFE)` with `age` since the last anchor; a flag edge resets age.
- **Origin:** `TDF src/TacoDogForever/Model/Belief/Casts.lua` (`step()` :34-78, `Applier` Cooldown :385),
  `Model/Belief.lua:652-684`.

### 6.3 Auras and per-target memory

- **Appliers:** `Read` of an aura (a plain walk entry: `expiry = t + remaining`, stacks; an exact `observed`
  sample), own casts through §5 (`modelled` expiry from the handler's `applyBuff`/`applyDebuff`),
  `TargetSwap`, `TargetGone`, `CombatEnd`.
- **Pins and models:** the spec's duration is the `default` for a newly applied aura. Per-target memory keeps
  `TARGET_CAP` (16) target slots by GUID, so a swap back restores what we believed about that target
  (`TDF src/TacoDogForever/Model/Belief/Targets.lua`, `Applier` TargetSwap :147). Each unit keeps an
  index-order array (applied time ascending, then walk order) for `AuraAt`, and `AuraGen(unit)` bumps on any
  change. Instance IDs are invented: a stable integer per (unit, aura) assigned when the aura first appears.
- **Conf:** `1/(1 + age/AURA_HALF_LIFE)`, age since the last anchor, floored at age 0
  (`TDF src/TacoDogForever/Model/Belief.lua:709`).
- **Origin:** `TDF src/TacoDogForever/Model/Belief/Auras.lua`, `Targets.lua`.

### 6.4 Swing

- **Appliers:** `Swing` (c: 1 a `PLAYER_SWING` anchor, 0 a speed read); own casts that reset or queue a swing;
  `PowerTick` pairing (a same-frame rage step marks a landed swing); `CombatStart`, `CombatEnd` (anchors
  cleared, speeds kept).
- **Pins and models:** the next swing is `anchorT + k·speed`; anchors carry weights 1.0 (`PLAYER_SWING`), 0.9
  (an on-next-swing strike), 0.8 (a swing reset), 0.5 (a paired rage step), 0.3 (combat start)
  (`TDF src/TacoDogForever/Model/Belief/Swing.lua:54`). The observed swing duration is the hasted speed; rage
  per swing comes from the spec's resource model for a swing-paid resource.
- **Conf:** the last accepted anchor's weight, falling linearly to 0 over `SWING_DECAY` (10 s)
  (`TDF src/TacoDogForever/Model/Belief/Swing.lua:181-188`).
- **Origin:** `TDF src/TacoDogForever/Model/Belief/Swing.lua` (`Applier` Swing :602).

### 6.5 Player: haste, movement, health, stats, TTD

- **Haste:** melee is `observed` out of combat and `modelled` in combat as the base weapon speed ÷ the
  observed swing duration; spell haste is the last plain read. Conf as swing (melee) or as aura (spell).
  `TDF src/TacoDogForever/Model/Belief/Player.lua` (`Applier` Haste :130).
- **Movement:** `Moving` events set the fact (`Player.lua`, `Applier` Moving :194).
- **Health:** the player's plain read when plain (unprobed, cleanup Q11), else the last value with conf
  decaying as aura; target and other units have only the `default` 1.0. Phase 1 has no target-health pin: no
  registration in the Warrior model says "this ability is usable only below 20 %", so execute-phase conditions
  read the default until a class file declares one through decision 2's exception.
- **Stats:** a cache of the 12 stat calls (§7) read out of combat at `PLAYER_REGEN_ENABLED`,
  `PLAYER_EQUIPMENT_CHANGED` and login; plain facts with their read time.
- **TTD:** `default` 30 s, conf 0 (Hekili's `DEFAULT_TTD`, feasibility §C.4).

### 6.6 Talents

One `C_Traits` walk per talent event (deferred out of combat), mapped to Hekili's `class.talents` keys by
definition spell ID; ranks are plain facts (`TDF src/TacoDogForever/Model/Belief/Talents.lua`, `Applier`
Talent :39). Hekili's `ns.updateTalents` (`Events.lua:424-435`) reads them from `VirtualState.Talent` (§10).

### 6.7 Totems

The four slots: an out-of-combat read is `observed`; an own cast that summons a totem is `modelled` (spec
duration); `PLAYER_TOTEM_UPDATE` for a slot with no cast is a `pinned` destruction. Conf as aura. Origin: the
totem half of `TDF src/TacoDogForever/Model/Belief/Pets.lua` (`Applier` Totem :57).

### 6.8 The target's cast

`TargetCast` observations by `castBarID` (plain on the target; spellID and times secret,
inputs/tdf-port-mapping.md §2): a start sets `start` and a `default` end (a fixed default length); stop,
interrupt or a new `castBarID` ends it; the interruptible events set the flag. Conf as aura. Origin:
`TDF src/TacoDogForever/Model/Belief/Target.lua` (`Applier` TargetCast :103).

### 6.9 Enemies

The plate walk counts live, attackable plates (plain `UnitIsDead`, `UnitCanAttack`); `Count.Enemies` is
`observed` from the latest walk, `default` 1 without plates. `Count.WithAura` counts the per-target memory
(§6.3); `Count.InRange` counts the range poll. Conf as aura from the last walk. In Phase 1 no Hekili code
reads `Count.*`: `active_enemies` comes from Hekili's plate scan through the `UnitHealth` policy (§7.4), and
wiring `active_dot` and `spell_targets` to `Count.*` is Phase 2/3 work (Phase 2 doc, consumers E8a and E9).

## 7. The facade

### 7.1 Fold-in

`Libs/VirtualGameAPI-1.0` becomes `Virtual/API/Facade.lua`, which builds `ns.Facade` at load. It keeps the
original's shape: namespaces mirror the game (`ns.Facade.UnitPower`, `ns.Facade.C_Spell.GetSpellCooldown`,
`ns.Facade.AuraUtil.ForEachAura`) and the query functions stay (`Facade.Status(name)`, `Facade.Why(name)`,
`Facade.Stubs()`, `Facade.Inventory()`; `VirtualGameAPI-1.0.lua:317-320`). Each kept name has the status
`virtual` (answered by a policy, §7.4) or `stub` (a fixed result, §7.3). There are no passthroughs. Facade.lua
resolves the real functions it needs (the player-only paths, `C_Spell.IsSpellUsable` for `IsUsableSpell`,
`C_Spell.GetSpellCooldown` for the plain `isActive`/`isOnGCD` flags) by name from `_G` at load, as the
original's `resolve` does (`VirtualGameAPI-1.0.lua:34-41`). Every policy uses `now = GetTime()` except during
a drain, when `now` is the pinned clock (§5.5 R1), and returns shared preallocated result tables, which Hekili
unpacks at once (`GetUnpackedSpellCooldown`, `State.lua:2905-2910`).

### 7.2 The kept names

The facade keeps exactly the 51 stub names of `VirtualGameAPI-1.0.lua:104-234`. 34 are answered by a policy
(§7.4); the other 17 stay stubs (§7.3). The stay-stub list is the stub list minus the policy names.

| Group | Names | Why kept |
|---|---|---|
| Resources | `UnitPower`, `GetPowerRegenForPowerType`, `GetManaRegen` (policy); `UnitPartialPower` (stub) | secret always or in combat [W PR16] |
| Health | `UnitHealth`, `UnitHealthMax` (policy); `UnitGetTotalAbsorbs` (stub) | target secret always [W PR14] |
| Stats | `GetCombatRating`, `GetCombatRatingBonus`, `GetCritChance`, `GetMasteryEffect`, `GetRangedCritChance`, `GetSpellBonusDamage`, `GetSpellCritChance`, `UnitArmor`, `UnitAttackPower`, `UnitDamage`, `UnitStat`, `UnitWeaponAttackPower` (policy) | secret in combat [W PR2, PR4] |
| Haste and speed | `GetHaste`, `GetMeleeHaste`, `UnitSpellHaste`, `UnitAttackSpeed`, `GetUnitSpeed` (policy); `UnitInRange` (stub) | secret in combat or always [W PR2, PR7, PR14; SU PR2] |
| Totems | `GetTotemInfo` (policy) | secret in combat [W PR12] |
| Auras | `AuraUtil.FindAura`, `AuraUtil.ForEachAura`, `C_UnitAuras.GetAuraDataByAuraInstanceID`, `C_UnitAuras.GetBuffDataByIndex`, `C_UnitAuras.GetDebuffDataByIndex`, `C_UnitAuras.GetPlayerAuraBySpellID` (policy); `C_UnitAuras.GetAuraSlots` (stub); `UnitAura`, `UnitAuraBySlot` (stub, absent) | secret in combat, errors when tainted [W §4]; absent on Forever |
| Cooldowns | `C_Spell.GetSpellCooldown`, `C_Spell.GetSpellCharges` (policy); `C_Spell.GetSpellCastCount` (stub); `C_Spell.GetSpellLossOfControlCooldown` (stub, absent) | times secret in combat, flags plain [W PR4, PR11]; flagged `SecretWhenCooldownsRestricted`, unprobed; absent |
| Casts | `UnitCastingInfo`, `UnitChannelInfo` (policy) | player plain [W PR9], target secret [W PR8] |
| Combat log | `CombatLogGetCurrentEventInfo` (stub) | absent; registering CLEU is forbidden |
| Talents | `GetTalentInfoByID` (stub, absent) | dead on Forever [W PR5] |
| Spells | `IsUsableSpell` (policy: alias); `GetSpellBaseCooldown`, `GetSpellLink`, `IsHarmfulSpell`, `IsHelpfulSpell`, `IsPassiveSpell` (stub, absent) | absent on Forever |
| Items | `GetItemGem`, `GetItemInfo` (stub, absent) | absent on Forever |

Stay stubs (17, keeping the original stub results, `VirtualGameAPI-1.0.lua:77-88`): `UnitPartialPower` (no
Forever user), `UnitGetTotalAbsorbs`, `UnitInRange` (no signal), `C_UnitAuras.GetAuraSlots` (no retained
consumer, `State.lua:456`), `C_Spell.GetSpellCastCount` (unprobed, unused), `CombatLogGetCurrentEventInfo`
(Phases 2 and 3), `GetTalentInfoByID` (Hekili's talent loop moves to the `C_Traits` walk, cleanup Q9), and the
guarded absent names `UnitAura`, `UnitAuraBySlot`, `C_Spell.GetSpellLossOfControlCooldown`,
`GetSpellBaseCooldown`, `GetSpellLink`, `IsHarmfulSpell`, `IsHelpfulSpell`, `IsPassiveSpell`, `GetItemGem`,
`GetItemInfo`.

### 7.3 Guarded stubs for absent names

An absent name cannot be called directly on Forever: its global is nil and a call raises. The facade keeps it
with a fixed, API-shaped result (nil, false or the original's shared shape), so call sites keep working
unchanged. The seven deprecation shims among the passthroughs (`HasOverrideActionBar`, `HasVehicleActionBar`,
`IsActionInRange`, `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `SpellIsSelfBuff`) exist
only while the CVar `loadDeprecationFallbacks` is on (cleanup §1 status table, cleanup Q12); they revert to
direct calls with a file-top alias that falls back to a file-local no-op when the global is nil
(`local IsPlayerSpell = IsPlayerSpell or nop`), until cleanup Q12 ports them to `C_SpellBook.IsSpellKnown` and
`C_ActionBar.*`.

### 7.4 The policy table

Every row reads VirtualState through the §3 functions. Where a row reads a Belief, it is this record:

```lua
Belief = {
  est, lo, hi, conf,              -- projection to `now`; hot-path reads
  basis = "pinned",               -- which `last` slot est stands on; "unknown" if none
  last = {
    observed = { v, t, event },   -- last plain read or exact event ("last seen")
    pinned   = { v, t, event },   -- last exact inference from a plain fact (usability flip, cost ladder)
    modelled = { v, t, event },   -- last carry-forward written by applying the spec
    default  = { v, t, event },   -- the fallback in force (spec duration, rest value)
  },
}
```

| Kept name(s) | Policy | Accessors |
|---|---|---|
| `UnitPower(unit, pt)` | player: `floor(Power(pt or UnitPowerType("player"), now).lo)`; other units: 0. `lo` never over-promises a spender (feasibility §D.3) | `Power` |
| `GetPowerRegenForPowerType(pt)` | `est, est` of `Regen(pt, now)`; for a swing-paid resource `0, 0` (in combat Hekili's swing model adds it; out of combat nothing swings) (no double count, G3) | `Regen` |
| `GetManaRegen()` | `Regen(0, now).est`, then `Regen(0, now, true).est` (the first value copied before the second call) | `Regen` |
| `UnitHealth(unit)`, `UnitHealthMax(unit)` | player: `Health("player", now).est · HealthMax("player")` and `HealthMax("player")`; target: `Health("target", now).est · 100` and 100; plates and pet: 100 and 100 when plain `UnitIsDead(unit)` is false, else 0 and 100, which keeps the enemy scan's `UnitHealth( unit ) > 1` test (`Targets.lua:407, 484`) meaningful | `Health`, `HealthMax` |
| the 12 stat names | the cached returns in the real return order | `Stat` |
| `GetHaste()`, `GetMeleeHaste()` | `(Haste(now).est − 1) · 100` | `Haste` |
| `UnitSpellHaste(unit)` | player: `SpellHaste(now).est`; others 0 | `SpellHaste` |
| `UnitAttackSpeed(unit)` | player: `SwingSpeed(1, now).est`, then `SwingSpeed(2, now).est` or nil without an off hand; others `2, nil` | `SwingSpeed` |
| `GetUnitSpeed(unit)` | player: `Moving() and 7 or 0, 7, 7, 4.72` (a plain boolean); others `0, 0, 0, 0` | `Moving` |
| `GetTotemInfo(slot)` | up: `true, name, start, duration, icon, 1, spellID` from `TotemFacts(slot)` with `duration = Totem(slot, now).est − start`; else `false, "", 0, 0, 0` | `Totem`, `TotemFacts` |
| `C_UnitAuras.GetBuffDataByIndex`, `GetDebuffDataByIndex` | `AuraAt(unit, filter, i, now)` into one shared AuraData table per index slot: `name`, `icon` (spell data), `applications` = stacks, `duration` = expiry − applied, `expirationTime` = `lo` (the early bound: refresh sooner rather than late), `sourceUnit` = "player", `spellId`, `timeMod` 1, `auraInstanceID` = the invented stable ID, `points` = one shared empty table | `AuraAt` |
| `C_UnitAuras.GetPlayerAuraBySpellID(id)` | `Aura("player", id, now)` into the shared AuraData, nil when not believed up | `Aura` |
| `C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)` | `AuraByInstance(unit, id, now)` into the shared AuraData | `AuraByInstance` |
| `AuraUtil.ForEachAura(unit, filter, max, fn, usePackedAura)` | walks `AuraAt` calling `fn` with the shared AuraData until `fn` returns true | `AuraAt` |
| `AuraUtil.FindAura(predicate, unit, filter, ...)` | walks `AuraAt` and returns the first match | `AuraAt` |
| `C_Spell.GetSpellCooldown(id)` | 61304 or 29515: `GcdInfo(now)`. A spell whose plain `isOnGCD` flag is true: the same two `GcdInfo` numbers, bit-identical (§7.5). Otherwise `startTime = Cooldown(id, now).est − CooldownLength(id)`, `duration = CooldownLength(id)`, `isActive` = the plain `isActive` flag when plain, else `est > now`, `isEnabled = true`, `modRate = 1`. One shared result table | `GcdInfo`, `Cooldown`, `CooldownLength` |
| `C_Spell.GetSpellCharges(id)` | `currentCharges` = `floor` of the charges Belief's `est`, `maxCharges` from the spec, `cooldownStartTime` = next − recharge, `cooldownDuration` = recharge, `chargeModRate` 1; nil for a spell without charges (what the real API returns) | `Charges` |
| `UnitCastingInfo(unit)`, `UnitChannelInfo(unit)` | player: the real function (plain [W PR9]); target: `"Casting", "", 136243, start·1000, TargetCast(now).est·1000, false, castBarID, interruptible == 0, 0` (`UnitChannelInfo` shifts the slots as the real API does), which feeds Hekili's `casting` generator (`Classes.lua:1645-1660, 1677`); nil when no cast | `TargetCast`, `TargetCastFacts` |
| `IsUsableSpell(id)` | alias of the real `C_Spell.IsSpellUsable` (plain [W PR14; SU]); fixes `State.lua:6965` | none |

### 7.5 GCD bit-identity

Hekili zeroes any spell cooldown that equals the GCD:
`gcdStart, gcdDuration = gcd.expires − gcd.duration, gcd.duration`, then
`if gcdStart == start and gcdDuration == duration then start, duration = 0, 0 end` (`State.lua:2972-2975`).
The facade must therefore return, for every spell whose plain `isOnGCD` flag is true, the exact numbers it
returns for the GCD spell, and those numbers must survive Hekili's `(start + duration) − duration` round trip.
`GcdInfo` fixes `start` and `duration` once at the rising edge and quantises both to multiples of 2^-10 s, so
the sum and difference are exact in double precision for any session-length `GetTime()`; it never recomputes
them between edges. Without this every GCD-locked spell reads as on cooldown (feasibility §C.4).

### 7.6 Feasibility §C.6 mapping

Every Hekili-shaped quantity of feasibility §C.6 maps to a §3 accessor, a direct game call, or a named stay
stub:

| Hekili reads | Answered by |
|---|---|
| `UnitPower(p, t)` | `Power` |
| `UnitPowerMax` | direct call (plain) |
| `GetPowerRegenForPowerType` → inactive, active | `Regen` |
| `C_Spell.GetSpellCooldown(id)` | `Cooldown`, `CooldownLength`, `GcdInfo` |
| GCD (61304 → 29515) start and duration | `GcdInfo`, `Gcd` |
| `GetSpellCharges` | `Charges` |
| `C_UnitAuras.Get{Buff,Debuff}DataByIndex(unit, i)` | `AuraAt` |
| `GetPlayerAuraBySpellID` | `Aura` |
| `UNIT_AURA` payload | `AuraGen` (the drain marks `updated`, §5.2 step 5; G1) |
| `UnitAttackSpeed` | `SwingSpeed` |
| Swings (CLEU `SWING_*`) | `Swing`, `LastSwing` (the swing source writes `state.swings.*_actual`, §4.6) |
| `UnitSpellHaste`, `GetMeleeHaste` | `SpellHaste`, `Haste` |
| `UnitCastingInfo("player")` | the real function through the facade's player path |
| `UnitChannelInfo` (player) | the real function through the facade's player path |
| `UnitHealth/Max("target")` | `Health`, `HealthMax` |
| `UnitHealth("player")` | `Health`, `HealthMax` |
| `GetTotemInfo` | `Totem`, `TotemFacts` |
| `GetUnitSpeed("player")` | `Moving` |
| `UnitDamage`, `UnitAttackPower`, ratings | `Stat` |
| `GetTalentInfoByID` | stay stub `GetTalentInfoByID`; ranks come from `Talent` through the `C_Traits` walk (§10) |
| `GetSpecializationInfo` | direct call; the pseudo-spec 1491 loop fix is a Hekili edit (§10) |
| `CombatLogGetCurrentEventInfo` | stay stub `CombatLogGetCurrentEventInfo` (Phases 2 and 3) |

### 7.7 Reverting the passthroughs, and the tool updates

Before the revert, the four double-check names are probed in combat on a dummy with `/dump issecretvalue(...)`
on each return: `C_Item.GetItemCooldown` (marked plain but cooldown-shaped), `C_Spell.IsSpellUsable`,
`UnitThreatSituation`, `InCombatLockdown`. A name that returns a secret joins the kept list as a `virtual`
name with a `Plain`-guarded answer (the plain value, else the stub shape) and its own policy row;
`InCombatLockdown`'s known lag is answered by `VirtualState.InCombat()` wherever VirtualState itself needs
combat state.

The revert, file by file, over the 14 files with facade reads (`State.lua` 42 lines, `Events.lua` 10,
`Targets.lua` 9, `Options/DevTools.lua` 9, `Utils.lua` 6, `UI.lua` 6, `Classes.lua` 4, `Options/Options.lua`
4, `Hekili.lua` 2, `Constants.lua` 2, `MultilineEditor.lua` 1, `Core.lua` 1, `Forever/Warrior.lua` 1,
`Options/ChatCommands.lua` 1; counts of lines matching `VGA\.`):
1. Line 5, `local VGA = LibStub( "VirtualGameAPI-1.0" )`, becomes `local Facade = ns.Facade` in a file that
   reads a kept name, and is deleted otherwise.
2. A file-top alias of a reverted name (`Core.lua:6` aliases `VGA.GetTime` with two others) becomes a direct
   alias (`local GetTime = GetTime`); an alias of a kept name becomes `Facade.<name>`.
3. A namespace alias (`local C_Item, C_LossOfControl, C_Spell = VGA.C_Item, VGA.C_LossOfControl, VGA.C_Spell`,
   `State.lua:6`) becomes the direct namespace; each call of a kept member of it (`C_Spell.GetSpellCooldown`,
   `C_Spell.GetSpellCharges`, `C_Spell.GetSpellCastCount`, `C_Spell.GetSpellLossOfControlCooldown`, the
   `C_UnitAuras` and `AuraUtil` members of §7.2) is rewritten to `Facade.<ns>.<name>`.
4. An inline read (`VGA.Name(`; `State.lua` has 34, kept inline because its main chunk is at the 200-locals
   cap, cleanup Q2) becomes `Name(` or `Facade.Name(`. No new file-top local is added to `State.lua`.
5. The seven deprecation shims follow §7.3.

Tools and lint:
- `tools/api_inventory.txt` lists exactly the kept names (51, plus any name a probe added); the facade spec
  asserts `Facade.Inventory()` equals it.
- `tools/check_api_reads.sh` keeps its two checks (luacheck W113 for a bare kept name, grep for `_G.Name` and
  `_G["Name"]`) and adds a grep for each dotted kept name (`C_Spell.GetSpellCooldown`, ...) outside
  `Virtual/API/Facade.lua`, because a declared namespace global hides its members from W113. Its message
  names `ns.Facade`. `tools/list_api_reads.sh` lists `Facade.` reads in place of the old facade reads.
- `.luacheckrc`: lines 1-3 restate the rule ("every secret or absent game read goes through `ns.Facade`");
  every reverted name is declared in `read_globals` (namespaces as whole globals), and the kept names stay
  undeclared so a bare read still shows as W113; `Virtual/State/spec/` gets `std = "+busted"`.

## 8. Clock and timing

- **Time base:** absolute `GetTime()` everywhere. Each observation carries the `GetTime()` of its handler.
  `now` is a required argument of every drifting accessor; the facade passes `GetTime()`, or the pinned clock
  during a drain. TDF's belief is on the same absolute clock (`TDF src/TacoDogForever/Model/Belief.lua:4`,
  "`s.now` is the belief clock").
- **When the fold runs:** only inside `Drain`, once per Hekili cycle, on the update thread (§5.1). Between
  drains every read is a projection of the last fold to the caller's `now`; a read in an event handler or in
  the UI's per-frame `d:OnUpdate` (GCD and cooldown swipes) is at most one cycle stale (0.2 s in combat), and
  never mutates anything.
- **Clock start:** the clock starts at the first observation, not at 0
  (`TDF src/TacoDogForever/Model/Belief.lua:723-728`).
- **Lag clamp:** an observation older than the clock is applied at the clock with `lag = clock − t`
  (`Belief.lua:733-736`). A late ladder rung is moved by regen × lag and dropped if it then conflicts
  (`Model/Belief/Resources.lua:278-290`); a late exact read is widened by the regen spread × lag
  (`Resources.lua:365-372`); swing anchors use `t − lag`.
- **No backward projection:** a `now` before the clock projects with `dt = 0`.
- **Pinned clock during a drain:** set per own cast to `t_cast` and released before the trailing reset (§5.2,
  R1).
- **Hekili's reads in its coroutine** are pure projections, so a read can never nest a fold inside a reset
  (the "nests in a reset" hazard, feasibility §C.2.3).

## 9. File layout and TOC order

```
Virtual/State/
  VirtualState.lua      ns.VirtualState, Obs/ReadOf enums, origin strings, Belief factory, projection,
                        debug rings
  ObsLog.lua            the 256-slot ring
  Belief.lua            the fold: dispatch per kind, advance, constrain, sync, lag clamp
  Families/             one file per family (§6): appliers, pins, models, record writes:
                        Resources, Casts, Auras, Swing, Player, Talents, Totems, TargetCast, Enemies
  Sources/Sources.lua   Plain, staging, Flush, Poll, the event table, the module's frame
  Sources/              Power, Spellbook, Casts, Auras, Swing, Player, Target, Talents, Nameplates, Totems
  Snapshot.lua          Snapshot(), SetDebug()
  Facade.lua            ns.Facade (§7)
  Adapter.lua           Drain, apply through the spec (§5), SpecChanged, the across-reset feeds (§4.6),
                        Hekili.VirtualState debug handle
  spec/                 busted specs and helpers (not in the TOC)
```

TOC order (`Hekili.toc`): `embeds.xml`; then `Virtual\State\VirtualState.lua`, `ObsLog.lua`, `Belief.lua`, the
family files, the source files, `Snapshot.lua`, `Facade.lua`, all before `Hekili.lua`, because `Hekili.lua`
already reads facade names at load (`Hekili.lua:6`); then Hekili's files as today; then
`Virtual\State\Adapter.lua` after `Core.lua`, so it can take `Hekili.State`, `Hekili.Class` and
`ns.spendResources` as file-top locals. Nothing before Adapter.lua touches `state` or `class`; the facade
policies reach VirtualState only at call time.

What changes outside the folder:
- `embeds.xml`: line 3 (`<Include file="Libs\VirtualGameAPI-1.0\VirtualGameAPI-1.0.xml"/>`) is deleted.
- `Libs/VirtualGameAPI-1.0/` is removed. Its spec's inventory and shape cases move to
  `Virtual/API/spec/facade_spec.lua`.
- `.busted`: `ROOT = { "Virtual/State/spec" }` (today `{ "Libs/VirtualGameAPI-1.0/spec" }`).
- `.luacheckrc` and `tools/`: §7.7. VirtualState's own sources read the game only through the injected `api`,
  so the read checks never flag them; the ported secrets spec (§11) enforces the `Plain` rule on them instead.

## 10. Hekili edits outside the module

| Edit | Where | Why |
|---|---|---|
| Call `VirtualState.Drain(GetTime())` after the guards | `Core.lua:1569-1573` | §5.1 (R4) |
| Call `VirtualState.SpecChanged()` at the end | `Hekili:SpecializationChanged`, `Classes.lua:3077-3362` | §3.6, decision 8 |
| `UNIT_AURA` handler stops reading the secret `data.isFullUpdate` and keeps its `ForceUpdate`; `updated` is set by the drain from `AuraGen` | `Events.lua:1265-1269` | G1; the handler is the only setter of `state[unit].updated`, which gates `ScrapeUnitAuras` (`State.lua:6199-6207`) |
| GCD spell 61304 → 29515 | `Classes.lua:2469`, `UI.lua:1493, 1694`, `Events.lua:1676` | a constant, not a call (cleanup Q6) |
| Spec 1491 loop break: `if not id or id == 0 then break end` | `Classes.lua:3133-3138` (the test at `:3135`) | Forever returns id 0 for slots 2 and 3, so `all` merges and `reset_precast` runs 2-3 times per reset (cleanup Q7) |
| Talents: `ns.updateTalents` reads ranks from `VirtualState.Talent` (the `C_Traits` walk) | `Events.lua:424-435` | `GetTalentInfoByID` is dead; the fallback `IsPlayerSpell( table )` probably throws (cleanup Q9) |
| Version gates | `Hekili.lua:18-56`, `Core.lua:205` | `IsDragonflight`/`IsTWW`/`IsMidnight`/`ns.PTR` are false on 16001 and `BuiltFor > CurrentBuild` reports a newer client (cleanup Q15) |
| The passthrough revert | 14 files (§7.7) | decision 3 |
| The Warrior class file for the checkpoint | `Forever/Warrior.lua` | today a load-only stub: rage with no model and no abilities (`Forever/Warrior.lua:1-3, 16`). The checkpoint (§11) needs rage registered with its swing model (shape: `archive/TheWarWithin/WarriorArms.lua:36-56`) and the abilities the dummy test casts (Rend, Heroic Strike and the spenders its list picks) with `spend`, `cooldown`, `handler` and aura `duration` |

The enemy scan's `UnitHealth( unit ) > 1` (`Targets.lua:407, 484`) needs no edit: the facade answers 100 for a
live plate and 0 for a dead one (§7.4).

## 11. Testing

**Runner.** busted under Lua 5.1 from the repo root; `.busted` points at `Virtual/State/spec` (§9).

**Injected `api`.** Sources take the client as `api`: `_G` in game, a fake in tests, so every source runs
headless (the TDF pattern, `TDF src/TacoDogForever/Game/App.lua:55-99` lists the client functions it
requires).

**Helpers** (`Virtual/State/spec/helpers/`):
- `fake_api.lua`: the `SECRET` proxy that raises on compare, arithmetic, concat, length, index and tostring
  (`TDF tests/helpers/wow.lua:16-25`), plus a fake frame with `Fire(event, ...)` and `Tick(now)`;
- `alloc.lua`: copied as is (`TDF tests/helpers/alloc.lua:7-33`): 200 warm-ups, two collections, collector
  stopped, the `collectgarbage("count")` delta in bytes;
- `fake_spec.lua`: a tiny fake spec provider: a fake `state` with `offset`, `delay`, `now`, `query_time`,
  resources, `cooldown`, `buff`, `debuff`; a fake `class` with abilities, auras and resources whose `spend`
  and `handler` are bound to that fake `state`; a fake `ns` with `spendResources`. It drives §5's read-before
  / read-after diff headless;
- `replay.lua`: a trimmed `TDF tests/helpers/replay.lua` that asserts accessors.

**Ported specs.** `obslog_spec`; the resources part of `belief_spec`; the swing specs; `secrets_spec` (a
static check that every source read goes through `Plain`, from `TDF tests/game/secrets_spec.lua`);
`facade_spec` (inventory equals `tools/api_inventory.txt`; every kept name answers in its real shape; absent
names never call `_G`; GCD bit-identity: for random `GetTime()` values up to 10^6 s,
`(start + duration) − duration == start` and the GCD-locked spell returns the same two numbers).

**Zero allocation.** 10,000 mixed events (`PLAYER_SWING`, `UNIT_POWER_FREQUENT`, usability, own casts,
`UNIT_AURA`) with a drain every tick against the fake spec, every accessor and every facade policy called; the
test asserts `alloc.bytes == 0`.

**Golden scenarios** (from TDF, rewritten against accessors):
1. swing anchors within tolerance from rage steps every 2.6 s with casts interleaved
   (`TDF tests/model/swing_replay_spec.lua:96`);
2. the cost ladder bounds a resource (affordable finisher 25, unaffordable builder 40) and regen is measured
   between two pins net of our own spends (`TDF tests/model/belief_spec.lua:197, 568`);
3. cooldowns snap to the game's ready flags (`TDF tests/model/belief_spec.lua:401`).

**Verified in game, not headless:** the apply-through-the-spec adapter against the real `state` (§5).

**In-game checkpoint (the Phase 1 exit criterion).** Warrior on Forever:
- `/reload` gives no Lua error and no popup.
- Out of combat, `/run print(Hekili.VirtualState.Snapshot())` shows class WARRIOR, the talent ranks, and rage
  with basis `default` at est 0.
- After 60 s on a dummy:
  - rage alternates between `pinned` and `modelled`, its interval is 15 wide or less, and it contains the rage
    bar's value;
  - the main-hand swing basis is `observed`, with speed equal to the weapon speed ±0.01;
  - Rend's believed expiry is within 0.2 s of the debuff timer;
  - Hekili recommends spenders.

## 12. Risks with closers

| # | Risk | Closer |
|---|---|---|
| G1 | Hekili never rescans auras in combat: its `UNIT_AURA` handler tests the secret `data.isFullUpdate` (`Events.lua:1269`) and is the only setter of `state[unit].updated` (`State.lua:6199-6207`) | §10 edit: the handler stops reading the payload; the drain sets `updated` when `AuraGen` moved (§5.2 step 5) |
| G2 | Event order between VirtualState's frame and Hekili's for the same event | probe: stamp `debugprofilestop()` in both `PLAYER_SWING` and `UNIT_SPELLCAST_SUCCEEDED` handlers; if Hekili's fires first, the one-cycle staleness of §8 is accepted |
| G3 | Rage counted twice (regen from the facade plus Hekili's swing model) | the 0 regen rule for swing-paid resources (§7.4); confirm on the dummy by comparing Hekili's forecast with the next pin; out of combat also 0 (2026-10-15: a positive out-of-combat regen made the sim forecast rage up while the belief decayed it, flipping Rend) |
| G4 | Returning `lo` for resources makes Hekili too passive near costs | log picks on a dummy where `lo < cost ≤ est`; choose `lo` or `est` per resource as a facade constant |
| G5 | `/reload` in combat loses VirtualState | persistence is out of scope for Phase 1 (§14); after a reload reads start wide and re-anchor from the next observations |
| G6 | The target's cast length is unknown (its spellID and times are secret) | time `START`/`STOP`/`INTERRUPTED` by `castBarID`; the default length meanwhile (§6.8) |
| G7 | Drain cost: two full resets plus one apply per own cast per cycle | measure with `debugprofilestop()` in `Snapshot()`; expect about 1-2 ms (§5.4) |
| G8 | `realQueue` ordering against back-dated applies: it may hold future events (`State.lua:5619`, pruned `:5857-5866`), and `HandleEvent` may remove events | verify in game that a back-dated `CAST_FINISH` apply leaves the real queue's own `CAST_FINISH` for the cast in progress intact, and that the trailing reset rebuilds `virtualQueue` from it (`State.lua:5850-5878`) |
| R1 | Clock mismatch between a handler's reads and the cast time | clock pinning during the drain (§5.5) |
| R2 | Negative offset: `StartCombat` never fires, `fight_remains` inflates, a negative offset reads as a partial reset | restore, trailing full reset, explicit `"Primary"` reset, combat-start write (§5.5) |
| R3 | Dirty state through the cycle's partial resets | the trailing full reset; no reliance on the partial path (§5.5) |
| R4 | The drain running before `Hekili.Update`'s guards | drain after the guards at `Core.lua:1569` (§5.1) |

## 13. Credits

- **Catnip (Durts):** the secret-value research and the `Plain` gate technique. Every file that carries
  `Plain`, the `issecretvalue`/`pcall` handling or a secret-value technique credits Catnip in its header
  (`Sources/Sources.lua`, `Sources/Auras.lua`, `Sources/Power.lua`, `Facade.lua`).
- **TDF origin:** each ported file's header names its TDF source file (for example "Ported from Taco Dog
  Forever, `src/TacoDogForever/Model/ObsLog.lua`"). TDF has no LICENSE file (inputs/tdf-port-mapping.md §6);
  both repositories are the user's, and the clean-room rule forbids only Hekili → TDF. TDF's Hekili-derived
  files raise no question inside the Hekili fork.
- **Hekili:** the apply procedure follows Hekili's own simulation (`Core.lua:1984-2045`) and keeps Hekili's
  credits where its code is touched.
- **VirtualGameAPI-1.0:** `Facade.lua`'s header names its origin, `Libs/VirtualGameAPI-1.0`, whose own header
  and LICENSE carry an MIT notice (`VirtualGameAPI-1.0.lua:13`); the folded file keeps that notice line.

## 14. Out of scope for Phase 1

- **Persistence:** VirtualState is not saved across `/reload` (G5); TDF's reload record is not ported.
- **Items and gear families:** item counts and cooldowns and worn gear are not tracked; the only gear fact is
  the weapon speed the swing source reads.
- **Events and callbacks:** no synthesised `UNIT_AURA`, `UNIT_POWER_FREQUENT` or `UNIT_SPELLCAST_*` payloads,
  no virtual combat log, no subscription API. These are Phase 2 (investigation) and Phase 3 (event bus); so
  are the `active_dot` and damage-seen enemy-count feeds that Hekili takes from CLEU today (feasibility §B.2
  E8a, E9).
- **Caching** at the facade.
- **TDF's engine:** SpecBuilder, Helpers, Timeline, Forecast, the APL compiler, its options, history, ranks,
  pets (beyond totems) and its DB2 data file.
- **Confidence in Hekili's UI:** Hekili consumes only the bound the facade picks; showing confidence needs
  Hekili UI code (feasibility §D.3).
- **A target-health pin and other Forever-only registrations:** none in Phase 1 (§6.5).
