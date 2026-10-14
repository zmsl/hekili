# VirtualState Phase 3: event-bus outline

**Outline: fill after Phase 2; not an executable plan.**

Date: 2026-10-14. Branch: `virtualstate-design` from `forever` at fc61b6d9. This file lists the decisions an
event-bus plan has to make and the facts they rest on. After the Phase 2 results exist
(`docs/research/<date>-virtualstate-phase2-eventing-results.md`, produced by
`docs/research/2026-10-14-virtualstate-phase2-eventing-investigation.md`), a session turns it into a
task-by-task plan under `docs/superpowers/plans/`, for the event families Phase 2 marked go and no others.

Cite conventions are the Phase 1 spec's (`docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md`,
"spec §N"): a bare `File.lua:N` is Hekili at fc61b6d9. "[V] §N" is section N of
`~/src/TacoDogForever/docs/research/2026-10-14-virtual-combat-log-events.md`; the facts this outline takes
from it are inlined in §1. "Phase 2 §N" is a section of the Phase 2 investigation plan.

## 1. Facts from the virtual combat log research

- **No combat log for addons.** Registering `COMBAT_LOG_EVENT_UNFILTERED` on Forever raises the "Blizzard UI
  only" popup, and the reader exists only in the secure namespace; all 54 retail subevents are gone as events
  ([V] §0). Hekili's frame never registers it (`Events.lua:174`), and the forbidden registration is never
  proposed as a probe ([V] §5).
- **Provenance.** Every derived row is *observed* (a plain client signal says it happened), *inferred* (plain
  signals plus a rule imply it) or *modelled* (spell data and a clock predict it) ([V] §1). Of 137 rows, 59
  are reconstructable, 52 partial, 19 impossible and 7 not applicable after probe session O ([V] §2.4).
- **What session O made plain** ([V] §5): `UNIT_COMBAT` for every unit token in combat, with event type,
  flag text (CRITICAL, GLANCING, CRUSHING, BLOCK), amount and school (O1: 779 firings, 0 secret, 752 in
  combat); `UNIT_DIED`, `PARTY_KILL`, `PLAYER_TARGET_DIED` with plain GUIDs (O6: 34 / 23 / 23);
  `PLAYER_SWING` per hand, also on avoided swings (O3: 235 swings, 36 without a same-frame rage event); plate
  add and remove with plain token, GUID, `UnitIsDead`, `UnitCanAttack` (O8: 27 / 27); our
  `UNIT_SPELLCAST_SUCCEEDED` (O16: 134 successes). Still secret: other units' cast `spellID`, `castGUID` and
  `interruptedBy` (`castBarID` plain, O4), and every `UNIT_AURA` payload field in combat (the table itself
  plain, O12).
- **Three recipes** ([V] §0): the cast-driven aura ledger (own `UNIT_SPELLCAST_*` plus durations give cast,
  aura applied, refresh and removed rows and the tick grid); the swing ledger (`PLAYER_SWING` for timing and
  hand, the target's `UNIT_COMBAT` for outcome, amount and crit); flips and facts (unexplained usability or
  cost flips give procs; the death events give deaths).
- **Never restored** ([V] §3): overkill, absorbed amounts, over-energize; the source of any hit
  (`UNIT_COMBAT` is victim-side); third parties' auras and casts; which aura left our target early.
- **Forecast rows** ([V] §4): modelled rows are emitted for our own casts, our aura applications and expiries,
  our tick grids, our energizes, swings on the swing clock and our totems. Misses, dodges, parries and crits
  are never emitted as modelled rows; they are observed (from `UNIT_COMBAT`) or not at all. Each forecast row
  carries the horizon class it was emitted in, so a subscriber can ignore proc rows beyond the close horizon.
- **Who consumed the log** ([V] §6): Hekili's engine uses death cleanup (`UNIT_DIED`, `UNIT_DESTROYED`,
  `UNIT_DISSIPATES`, `PARTY_KILL`, `SPELL_INSTAKILL`), `SPELL_SUMMON`, damage and misses on the player, the
  cast queue (`SPELL_CAST_START`, `_FAILED`, `_SUCCESS`, `SPELL_DAMAGE`, a channel's `SPELL_AURA_REMOVED`),
  `SPELL_EMPOWER_END`, `SWING_*`, `SPELL_AURA_*` plus periodic damage and misses on hostiles, friendly HoTs,
  and damage dealt for enemy counting. It does not use `SPELL_ENERGIZE`, `SPELL_INTERRUPT`, `SPELL_DISPEL` or
  `SPELL_HEAL`; class modules add `SPELL_ENERGIZE`, `SPELL_ABSORBED`, `SPELL_MISSED`, `SWING_MISSED`,
  `SPELL_AURA_REMOVED_DOSE` and `SPELL_EMPOWER_END`.

## 2. Subscription API or frame diversion

Decided by Phase 2 §6 (option (a): keep the `Events.lua:174` skip and invoke Hekili's handlers; option (b): an
instance-level `RegisterEvent` diversion on Hekili's frames). To fill:
- the public function(s) on `ns.VirtualState` a reader subscribes with, functions only (spec decision 4),
  registered at load and never in a recurring path;
- how the bus reaches Hekili's general event frame (`events`, a file local of `Events.lua`, dispatched by
  `GenericOnEvent` at `Events.lua:78-95`), and the edit count if it needs one;
- push or pull, as Phase 2 §9 states.

## 3. Preallocated payload pools

- One pooled row per queue slot holding the positional combat log tuple `CLEU_HANDLER` destructures
  (`Events.lua:1461`: timestamp, subtype, hideCaster, source GUID, name, flags, raid flags, dest GUID, name,
  flags, raid flags, spellID, spellName, school, amount, then the subevent's extra slots).
- Every row honours the payload contract of Phase 2 §4.3: `destFlags` and `school` numbers, `destGUID` a
  string (`""` for none), overkill 0, the `SWING_DAMAGE` slot shift.
- One preallocated `UNIT_AURA` payload table per unit at the depth Phase 2 §5 picks, with its arrays.
- Pool sizes and the zero-allocation rule follow spec §2: allocated when the tracked set is built, overwritten
  in place.

## 4. Queue model

To fill: one shared ring with a cursor per reader, or a ring per reader; capacity; the overflow policy (drop
the oldest and count it, as the observation log does, spec §4.1); the counters `Snapshot()` shows.

## 5. Lanes

- **Urgent, synchronous:** observed rows, emitted from VirtualState's handler for the triggering event
  (`PLAYER_SWING`, our `UNIT_SPELLCAST_*`, `UNIT_COMBAT`, the death events). Hekili's handler stamps
  `GetTime()` (`Events.lua:1483`), which is then the row's own time. This extends the spec's urgent lane
  (§4.4), which today only shortens Hekili's wait.
- **Deferred, back-dated:** inferred rows (a debuff applied after travel, a dodge, a proc), delivered after
  their window closes with the row's own time, by the timestamp policy Phase 2 §4.2 picks (synchronous only,
  or `GetTime` under VirtualState's control during delivery).
- **Modelled rows:** only if Phase 2 marks a consumer that needs them (the tick grid for `trackDebuff`).

## 6. Delivery point

On the frame update path: VirtualState's own event handlers for the urgent lane and its own `OnUpdate`, the
one that flushes staged observations (spec §4.4), for the deferred lane. Never nested: not inside
`Hekili.Update`'s coroutine (where the drain runs, spec §5.1, and where a delivery would write the caches in
the middle of a reset, against state Hekili already copied), not inside a reset, not inside a pack hook. To
fill: whether VirtualState's `OnUpdate` needs to run before Hekili's engine frame (`UI.lua:2370-2450`) and how
that order is guaranteed or measured.

## 7. Re-entrancy and drop policy

`ns.callHook` returns at once while `inProgress[ event ]` is set (`Classes.lua:2869`), so a row published from
inside a pack hook is dropped silently. The bus therefore queues any row published during a delivery for the
next delivery, never delivers it nested, and counts it. To fill: the counter names and whether a dropped or
overflowed row is ever re-emitted (default: no).

## 8. Readers

- **Combat log feed:** `CombatLogGetCurrentEventInfo`, a stay stub in Phase 1 (spec §7.2), becomes a facade
  policy that returns the pooled row being delivered; `CLEU_HANDLER` and, through `ns.callHook`, every pack
  hook then run unchanged. Hekili's dispatch builds a key string per handler per event (`Events.lua:84`), an
  allocation on Hekili's side outside VirtualState's own zero-allocation test; measure it per delivered row.
- **`UNIT_AURA` synthesis:** at Phase 2 §5's depth, delivered to Hekili's `UNIT_AURA` handler
  (`Events.lua:1265`). The real event still fires with a secret payload, so the real registration is diverted
  or the handler tells the two apart.
- No TDF reader: TDF reuse is not a goal (spec decision 1).

## 9. Tests

- Zero allocation per delivered row and per synthesised `UNIT_AURA`, with the alloc helper of spec §11, on the
  VirtualState side; Hekili's dispatch cost measured separately (§8).
- Golden ordering: observed rows arrive in handler order; deferred rows carry their back-dated time; nothing
  is delivered nested in a reset, the update coroutine or a hook.
- Payload contract: one case per subevent the bus emits (Phase 2 §4.3).
- Re-entrancy: a hook that publishes sees its row next delivery, counted, never nested.
- Overflow: a full queue drops the oldest and counts it.
- In game: per go family, the consumer's cache shows the row (for example `prev_gcd` after a cast,
  `active_dot` after Rend), checked by the user on a dummy.

## 10. Phase 1 edits it retires

From spec §10, and the module-internal writes of spec §4.6:

| Phase 1 edit or write | Phase 3 effect |
|---|---|
| `UNIT_AURA` handler stops reading `data.isFullUpdate`; the drain sets `updated` from `AuraGen` (`Events.lua:1265-1269`; spec §5.2 step 5) | retired when Phase 2 picks synthesis depth 1 or 2: the handler reads a plain synthesised payload again and sets `updated` itself |
| The own-cast and swing feeds (spec §4.6: `AddToHistory`, `CAST_FINISH` and channel events into `realQueue` and their removal on success, failure, interrupt or channel stop, `swings.*_actual`) | retired per family with a go: `CLEU_HANDLER` writes them from the delivered rows, as on retail |
| `CombatLogGetCurrentEventInfo` stay stub (spec §7.2) | becomes a facade policy (§8) |
| GCD spell 61304 → 29515 (`Events.lua:1676` among others) | kept; the line inside `CLEU_HANDLER` runs again once rows flow |
| The Warrior class file (`Forever/Warrior.lua`) | kept; it gains `RegisterCombatLogEvent` hooks only for families with a go |
| The drain and `SpecChanged` calls, the spec 1491 loop break, the talent walk, the version gates, the passthrough revert | kept, unrelated to events |

The `Events.lua:174` skip of the combat log registration stays in every option.

## 11. What the filled plan produces

An executable plan, `docs/superpowers/plans/<date>-virtualstate-event-bus.md`, task by task with checkpoints,
covering §§2-10 for the go families, with the user's in-game checks named per checkpoint.
