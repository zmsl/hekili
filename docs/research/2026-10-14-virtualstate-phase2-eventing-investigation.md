# VirtualState Phase 2: eventing investigation plan

Date: 2026-10-14. Branch: `virtualstate-design` from `forever` at fc61b6d9. Phase 2 starts after the Phase 1
exit criterion (spec §11) holds in game. This is a research plan: it produces a results document and a go or
no-go per event family, not code.

Cite conventions (the spec's):
- A bare `File.lua:N` is Hekili at fc61b6d9.
- "spec §N" is `docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md`.
- "feasibility §X" is section X of
  `~/src/docs/research/tdf/2026-10-14-hekili-virtual-state-feasibility.md`. Its Hekili cites are at
  36daec38; this plan re-cites at fc61b6d9 every line it carries.
- "[V] §X" is section X of `~/src/docs/research/tdf/2026-10-14-virtual-combat-log-events.md`, the
  137-row virtual combat log. Its row ids (C, M, N), detection patterns (D1-D18) and probe ids (O1-O16) are
  quoted as [V] gives them.
- "cleanup Qn" is row n of §5 of `docs/forever-cleanup.md`.

Desk-research step 7 reads [V] in full; everything else this plan needs from the two TDF research documents is
inlined below.

## 0. Question

Phase 1 answers Hekili's secret *reads* (spec §0) and feeds the across-reset caches the dead combat log used
to write (spec §4.6). It synthesises no events (spec §14). Some Hekili consumers learn only from an event: the
combat log handler `CLEU_HANDLER` (`Events.lua:1461-1766`, registered at `:1768` but never delivered on
Forever), and three plain-event handlers whose payload is secret or whose meaning shifts under the facade.

Phase 2 answers, per consumer: does VirtualState synthesise the event (a Phase 3 event bus delivers it), or
does Phase 1's read plus a Hekili edit stay the answer? It ends with a go or no-go per event family, the
subscription shape Phase 3 needs (push or pull), the delivery mechanism and the timestamp policy.

## 1. Inputs

| Input | Path | What Phase 2 takes from it |
|---|---|---|
| Phase 1 spec | `docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md` | §4.2 event table, §4.4 urgent lane, §4.6 across-reset feeds, §5 drain, §7.4 AuraData shape, §10 edits, §12 G1-G8, §14 |
| Feasibility | `~/src/docs/research/tdf/2026-10-14-hekili-virtual-state-feasibility.md` | §B.1-B.4 (consumers, payload contract), §C.2 (event half), §C.4 (caches), §D.3 (retractions) |
| Virtual combat log | `~/src/docs/research/tdf/2026-10-14-virtual-combat-log-events.md` | §2.4 counts, §3 D1-D18, §5 O1-O16 results, §6 consumers |
| Cleanup questions | `docs/forever-cleanup.md` §5 | Q3 (event facade), Q4 (combat log timing), Q5 (registration popup) |
| First outline | `docs/research/2026-10-14-virtualstate-inputs/library-design-draft.md` §H | the original Phase 2 question list, superseded in shape |
| Hekili code | `Events.lua`, `Targets.lua`, `State.lua`, `Classes.lua:2855-2879` | the consumers below |
| Warrior hooks | `archive/TheWarWithin/WarriorArms.lua:701`, `WarriorFury.lua:711`, `WarriorProtection.lua:731` | W1-W3 |
| Phase 1 evidence | the user's in-game logs | `VirtualState.Snapshot()` from a dummy and a dungeon, the G2 order probe, the G7 drain cost |

## 2. Consumers that need events rather than reads

### 2.1 The combat log consumers (feasibility §B.2, re-cited at fc61b6d9)

`CLEU_HANDLER` fans every event out to the pack hooks first (`Events.lua:1463` → `ns.callHook`), handles
deaths and returns (`:1465-1481`), then stamps `time = GetTime()` (`:1483`) and filters on identity
(`:1485-1487`). Feed column: R reconstructable, P partial, as [V] scores them after probe session O.

| # | Consumer | Feeds | [V] rows | Feed | Phase 1 answer | With no feed |
|---|---|---|---|---|---|---|
| E2 | Death cleanup `:1465-1481` → `ns.eliminateUnit` (`Targets.lua:925`) | `targets`, `myTargets`, `active_dot` purge | C66, C67, C68 R (O6: `UNIT_DIED` 34, `PARTY_KILL` 23, `PLAYER_TARGET_DIED` 23 firings, GUIDs plain); C69, C70, C41 P | R | none | dead units stay counted until the 1 s auditor (`Targets.lua:1112`) drops them after the spec's `damageExpiration`, default 6 s (`Targets.lua:1086`) |
| E3 | Summon `:1497-1509` | `minions` | C45 P, C46 I | P | none | inert unless `damagePets` is on |
| E4 | Damage taken `:1513-1558` → `ns.storeDamage` (`Targets.lua:966`) | `incoming_damage_Ns` | C2, C4 R (O1: `UNIT_COMBAT` on the player plain); C52, C60 P; C13, M10 I | R direct, P periodic | none | defensives never fire; they also read player health percent (unprobed, cleanup Q11) |
| E5a-c | Cast start, failed, channel end `:1567-1612` | `realQueue`: `CAST_FINISH`, `CHANNEL_*`, projectiles | C36, C40, C30 R | R | §4.6 queues `CAST_FINISH` on our start and the channel events on our channel start, and removes them on our success, failure, interrupt or channel stop | phantom finishes stay until their time |
| E5d | Cast success and history `:1613-1663` | `AddToHistory` (`Events.lua:912-943`): `prev_gcd`, `lastcast`, `realCast` | C38 R (O16: 134 successes plain) | R | §4.6 calls `AddToHistory` on our `UNIT_SPELLCAST_SUCCEEDED` | every `prev_gcd` test false, no error |
| E5f | Projectile impact `:1668-1673` | in-flight events | C7 R | R | none | bounded |
| E5g | GCD anchor `:1676` | `state.gcd.lastStart` | none | edit | spec §10 (61304 → 29515); the time comes from the facade's `GcdInfo` | not an event question |
| E6 | Tank attacker `:1681-1682` | `targets` | the attacker GUID is I; N20, N21, D16 substitute | P | none | Protection under-counts unplated attackers |
| E7 | Swing timers `:1684-1700` | `swings.mh_actual`, `oh_actual`, Hekili's swing-rage models | C1, C3 R (`PLAYER_SWING` plain per hand); C24 P | R | §4.6 writes the swing fields on `PLAYER_SWING` | swing rage stops forecasting |
| E8a | Hostile debuff tracking `:1720-1736` → `ns.trackDebuff` (`Targets.lua:765`) | `active_dot`, ticks, `pmultiplier` | C27, C33, C30 R; C31, C51 P; C53 I | R / P | none (spec §14) | `active_dot` 0, `cycle_targets` degrades |
| E8b | Friendly HoTs `:1740-1748` | `trackDebuff` | C25 R, C54 P | P | none | healers only |
| E9 | Damage-seen enemy counting `:1755-1763` → `ns.updateTarget` (`Targets.lua:653`), `ns.eliminateUnit` | `active_enemies`, `my_enemies` | C1, C7, C9, M1-M4 R; overkill and source filtering I | P | the plate walk, `Count.Enemies` (spec §6.9) | count 1 plus plates; no overkill elimination |
| W1-W3 | Warrior pack hooks, `archive/TheWarWithin/WarriorArms.lua:701`, `WarriorFury.lua:711`, `WarriorProtection.lua:731` | Colossus Smash early apply, Whirlwind stacks, refreshes | C38 R; C25, C26, C30 R / P | R / P | none: archived, not loaded; `Forever/Warrior.lua` registers no hook | retail spell IDs; a Forever class file registers hooks only if Phase 3 delivers the log |

Of the rows that apply, feasibility §B.2 counts 8 R and 8 P, none entirely impossible; the impossible pieces
(overkill, the attacker's GUID, absorbed amounts, `SPELL_PERIODIC_MISSED`) sit inside partial rows. The
consumers touch about 50 of [V]'s 137 rows. Ranked by silent damage when absent (feasibility §B.3): cast
history (E5d, fed in Phase 1), enemy count (E9 + E2 + E6), swing clock (E7, fed in Phase 1), debuff tracking
(E8a), damage taken (E4).

### 2.2 The plain-event handlers

| Handler | Where | What breaks or shifts on Forever | Phase 1 answer |
|---|---|---|---|
| `UNIT_AURA` (player, target) | `Events.lua:1265-1325` | tests `data.isFullUpdate` at `:1269`; in combat the payload table is plain and its fields secret ([V] §5 O12: player 86, target 85 firings), so the boolean test raises. The handler is the only setter of `state[unit].updated` (G1) | spec §10: the handler stops reading the payload and keeps its `ForceUpdate`; the drain sets `updated` from `AuraGen` (spec §5.2 step 5) |
| `UNIT_POWER_FREQUENT` (player) | `Events.lua:1175-1210`, registered `:1212` | averages focus and energy tick intervals from event times (`:1177-1200`), then compares `UnitPower` with `lastPower` (`:1173`, `:1202-1208`) and forces an update on a drop | the compare reads `floor(Power(pt).lo)` through the facade (spec §7.4): a plain number, no error, but it moves only when a drain moves the belief |
| `UNIT_SPELLCAST_SUCCEEDED`, `_START` (player and target) | `Events.lua:1014`, `:1034` | the target's `spellID` and `castGUID` are secret ([V] §5 O4). At fc61b6d9 both handlers test `unit == "player"` before indexing `class.abilities` (`:1023`, `:1035`), so the secret is never indexed; the target arm runs only the load-warning notices. Feasibility §C.2.2 describes the 36daec38 handler, which indexed it | the target's cast is a belief (spec §6.8) read through the facade's `UnitCastingInfo` policy |

## 3. Per consumer: synthesised event or read + edit

For each row of §2 the investigation fills one line of this comparison, with evidence:

| Criterion | Synthesised event | Read + edit |
|---|---|---|
| Hekili code touched | none in the consumer; the bus and a delivery hook (§6) | one edit per consumer, or a VirtualState write into the cache |
| Edits saved | count the edit sites the event makes unnecessary, by file and line | none |
| Timing | Hekili stamps its handler's `GetTime()` (§4.2), so late rows need back-dating | the module writes at the observation's own time |
| Pack hooks | a class file's `RegisterCombatLogEvent` hooks run unchanged | packs cannot hook |
| Cost | one CLEU tuple per row plus Hekili's dispatch (`GenericOnEvent`, `Events.lua:78-95`, builds a key string per handler call at `:84`) | the module's own write, zero allocation (spec §2) |
| Retraction | a compensating event (§7) | a module write that undoes the cache entry |

The starting positions, to confirm or overturn: E5a-d and E7 stay read + edit (Phase 1 already feeds them
synchronously and exactly, spec §4.6) unless the bus subsumes them at no extra edit; E2, E8a and E9 are the
candidates for synthesis, because their consumers (`eliminateUnit`, `trackDebuff`, `updateTarget`) carry
logic Phase 1 does not replicate; E3, E4, E6 and E8b are out of a Warrior's scope; `UNIT_AURA` is §5;
`UNIT_POWER_FREQUENT` compares a facade read with the previous one, so the question is whether a forced update
on our own spend (already sent by the urgent lane on our cast, spec §4.4) makes it redundant; the target
`UNIT_SPELLCAST_*` arm is a candidate for dropping the `"target"` registration (one edit at `:1014` and
`:1034`) rather than synthesis.

## 4. The virtual combat log VirtualState can emit

### 4.1 Rows by provenance

[V] scores 137 rows after probe session O: 59 reconstructable, 52 partial, 19 impossible, 7 not applicable
([V] §2.4). Each derived row carries a provenance: *observed* (a plain signal says it happened), *inferred*
(plain signals plus a rule imply it), *modelled* (spell data and a clock predict it) ([V] §1). VirtualState's
own observation kinds (spec §2, `VirtualState.Obs`) map onto them:

| Lane | Rows | Source signal ([V] §3) | When known |
|---|---|---|---|
| Synchronous observed | our `SPELL_CAST_START`, `_SUCCESS`, `_FAILED` (D1); swing timing per hand (D7); deaths `UNIT_DIED`, `PARTY_KILL` (D11); hits, misses, dodges, parries and crits on the target, plates and us from `UNIT_COMBAT` (O1: 779 firings, 0 secret, 752 in combat; D13, D14) | the event itself | in its handler |
| Late inferred | our debuff applied on the target from cast plus travel (D3); a landed swing from a same-frame power burst (D7; O3: 36 of 235 swings had no rage); a dodge from a missing reward (D8); procs from unexplained flips (D9); our interrupt on an enemy (D10a, the target's `_INTERRUPTED` within 0.2 s, by `castBarID`) | a later signal or a window closing | 0.1-0.5 s after the fact |
| Modelled | our aura's expiry (D2); the periodic tick grid (D4); totem expiry (D12) | spell data and a clock | scheduled ahead |

[V] §3 also lists what no signal restores: overkill, absorbed amounts, the source of any hit (`UNIT_COMBAT` is
victim-side), other units' casts and auras beyond timing and `castBarID`, and which aura left our target
early.

### 4.2 Timestamp policy

`CLEU_HANDLER` ignores the combat log timestamp and stamps `time = GetTime()` at `Events.lua:1483`; deaths
take no time at all (`:1465-1481`). Swing anchors (`:1687-1697`), debuff `applied` and `last_seen`
(`trackDebuff`, `Targets.lua:765`) and history times all take the delivery time. Delivery once per frame
shifts them by up to a frame (7-17 ms, harmless); an inferred row delivered late shifts them by the inference
delay, a direct phase error in the swing clock and the DoT grid (feasibility §C.2.3). The candidates:
1. **Synchronous only:** emit observed rows from VirtualState's handler for the triggering event; never emit
   inferred rows into a time-stamping consumer.
2. **Back-dated delivery:** during delivery `GetTime` returns the row's own time. After Phase 1's passthrough
   revert `GetTime` is a direct alias in `Events.lua` (spec §7.7 step 2; today `VGA.GetTime` at
   `Events.lua:9`), so back-dating needs `GetTime` under VirtualState's control in `Events.lua`, `Targets.lua`
   and every pack hook that reads time. Phase 2 lists those reads and their count.

### 4.3 Payload contract (feasibility §B.4, re-cited at fc61b6d9)

Hekili destructures the tuple positionally (`Events.lua:1461`), so a synthesised row honours:
- `destFlags` is a number: `bit.band( destFlags, ... )` at `:1511` raises on nil. Synthesise it from the plain
  `UnitCanAttack` and `UnitIsFriend`.
- `destGUID` is a string, `""` for none: `:len()` at `:1574`, `:1619`; `:match` at `:1471`, `:1500`.
- `school` is a number: it becomes `damageType` (`:1549`) and goes through `bit.band` at `:1556`.
- Overkill is 0, never nil: `interrupt > 0` and, for `SWING_DAMAGE`, `spellName > 0` at `:1758`.
- `SWING_DAMAGE` shifts its slots: the amount sits in the `spellID` position, slot 12 (`:1530-1531`).
- Delivery never nests inside a pack hook: `ns.callHook` returns at once while `inProgress[ event ]` is set
  (`Classes.lua:2869`), so a row published from a hook is dropped.

## 5. `UNIT_AURA` synthesis depth

Facts: in combat the `UNIT_AURA` payload table is plain and its fields secret ([V] §5 O12); that *an* aura was
added, removed or updated is visible by key presence (60, 22 and 3 of 82 firings, [V] §3 item 4). Phase 1
retires the payload test (spec §10) and marks `updated` from `AuraGen` inside the drain.

| Depth | Payload | Hekili path it drives | Cost and gaps |
|---|---|---|---|
| 0: none | the Phase 1 edit stays | the drain's `updated` marking; the handler's `ForceUpdate` | no edit retired |
| 1: full update | `{ isFullUpdate = true }`, one preallocated table per unit, when `AuraGen(unit)` moved | `:1269-1278`: wipes the instance table, walks both filters through the facade's `ForEachAura`, sets `updated`, forces an update | the walk calls `StoreInstanceInfo`, which reads `isBossAura`, `isStealable` and `isFromPlayerOrPlayerPet`; the facade's shared AuraData (spec §7.4) carries none of the three, so they read nil and every aura counts as not of concern |
| 2: incremental | `addedAuras`, `updatedAuraInstanceIDs`, `removedAuraInstanceIDs` from `AuraGen` diffs, using the invented stable instance IDs (spec §6.3) | `:1282-1324` | a diff record per unit in preallocated arrays; `GetAuraDataByAuraInstanceID` through the facade (`:1298`) |

Phase 2 settles which depth retires the most edits at bounded cost, whether the AuraData shape gains the three
fields, and where delivery happens: never from the drain, which runs inside `Hekili.Update` (spec §5.1), so a
synthesised `UNIT_AURA` would nest in Hekili's own call.

## 6. `RegisterEvent` diversion or the `Events.lua:174` edit (cleanup Q5)

Facts: `ns.RegisterEvent` (`Events.lua:168`) keeps the handler list and registers the event on the real frame
at `:174`, which since Checkpoint B skips `FRAME_UPDATE` and `COMBAT_LOG_EVENT_UNFILTERED` (the edit
feasibility §C.2.1 placed at `:163` in the 36daec38 numbering); `ns.UnregisterEvent` carries the matching
guard (`:197`). The combat log closure still joins the handler list (`:1768`) and calls the stubbed
`CombatLogGetCurrentEventInfo` (spec §7.2), which throws if it ever fires (cleanup Q5). A second live
registration sits in a dev tool, `Options/DevTools.lua:1156`. The frame dispatches every handler of an event
from `GenericOnEvent` (`Events.lua:78-95`).

| Option | How a virtual event reaches Hekili | Open |
|---|---|---|
| (a) keep `:174` | the bus invokes the general frame's `OnEvent` with `"COMBAT_LOG_EVENT_UNFILTERED"`; `CombatLogGetCurrentEventInfo` becomes a facade policy that returns the row being delivered (feasibility §C.2.3) | how the bus reaches the file-local `events` frame without an edit |
| (b) diversion | an instance-level `RegisterEvent` on Hekili's frames routes virtual event names to a VirtualState subscription and passes real ones through (Hekili's frames are insecure, so this is legal, feasibility §C.2.1) | whether a diverted registration on an insecure frame avoids the popup (unprobed; moot when no virtual name ever reaches the client) |

The output names one option for the combat log and one for `UNIT_AURA` (§5), with the edit count of each.

## 7. Retractions to the across-reset caches

Hekili re-reads everything at each reset, so a belief that jumps is absorbed at the next reset; the caches
that persist across resets are the exception, and a correction to a past fact reaches them only as a
compensating event or a direct write (feasibility §C.4, §D.3). The caches, with their Phase 1 writer and the
retraction question Phase 2 answers:

| Cache | Where | Phase 1 writer | Retraction question |
|---|---|---|---|
| `realQueue` | `State.lua:5619`, pruned `:5857-5866` | §4.6: `CAST_FINISH` on our hard-cast start, `CHANNEL_FINISH` and `CHANNEL_TICK`s on our channel start; their removal on our success, failure, interrupt or channel stop, as the combat log did on `SPELL_CAST_SUCCESS` (`Events.lua:1613-1614`), `SPELL_CAST_FAILED` (`:1603-1606`) and a channel's `SPELL_AURA_REMOVED` (`:1609-1610`) | only whether a synthesised `SPELL_CAST_*` row would supersede these writes; the ordering of back-dated applies against the queue stays G8, whose in-game result Phase 2 reuses |
| `prev*` histories, `player.last*`, `ability.realCast` | `AddToHistory`, `Events.lua:912-943` | §4.6, on our `UNIT_SPELLCAST_SUCCEEDED` | none: retail's log also records a dodged strike's success (feasibility §D.3; [V] D1, O16) |
| `swings.mh_actual`, `oh_actual` | zeroed on `PLAYER_REGEN_ENABLED` (`Events.lua:875`) | §4.6, on `PLAYER_SWING` | none: `PLAYER_SWING` is exact, and fires on avoided swings too ([V] §5 O3) |
| `trackDebuff`'s per-GUID table | `Targets.lua:765` | none | a synthesised `SPELL_AURA_APPLIED` after an unseen dodge, resist or dispel needs a compensating `SPELL_AURA_REMOVED` (handled at `Events.lua:1734-1735`), driven by the target's `UNIT_COMBAT` DODGE or the `UNIT_AURA` removed key; how long is the window? |
| `state[unit].updated` | set in the `UNIT_AURA` handler (G1) | the drain, from `AuraGen` (spec §5.2 step 5) | §5 |
| `gcd.lastStart` | written only at `Events.lua:1676`, inside the dead `CLEU_HANDLER` (E5g); `UI.lua:1716` reads it as a fallback | none on Forever | does the fallback need a writer? |
| `cast_target`, `holds`, `lastPower`, the TTD samples | `Events.lua:1121-1125`, `state.holds`, `:1173`, `Targets.lua:1528-1581` | Hekili's own handlers | does any need a write when a belief is corrected? |

Spec §12 already closes G1 (aura rescan) and states G8 (`realQueue` ordering against back-dated applies) and
G2 (event order between the two frames); Phase 2 reuses their in-game results and does not reopen them.

## 8. Desk research and in-game probes

Sessions never run the game. A probe is a `/run` line or a ForeverProbe addition (`~/src/ForeverProbe`, the
probe addon) that a session writes and the user runs; the user returns the log.

**Desk research** (a session, read-only on Hekili):
1. Confirm every §2 line at the Phase 1 head and list each consumer's writes.
2. Count, per consumer, the edit sites a synthesised event saves (§3).
3. Audit every `CLEU_HANDLER` branch and every loaded Forever class file's hooks against §4.3.
4. List every time read reached during delivery (§4.2 candidate 2).
5. Audit `StoreInstanceInfo` and the `UNIT_AURA` paths against the facade's AuraData (§5).
6. Find a way for the bus to reach Hekili's general frame without an edit, or count the edit (§6).
7. Map each [V] row Hekili consumes to its VirtualState observation kind and lane (§4.1).

**In-game probes** (the user runs them):
1. The dodge window: the target's `UNIT_COMBAT` DODGE or MISS against our `UNIT_SPELLCAST_SUCCEEDED`, in ms,
   on a dummy (bounds the retraction window of §7).
2. The `UNIT_AURA` key-presence pattern for our own Rend application and expiry on the target in combat
   (whether depth 2 of §5 has a plain trigger).
3. `UNIT_DIED` and `PARTY_KILL` range for plated and unplated mobs ([V] D11 lists the range as unmeasured).
4. IMMUNE and RESIST through `UNIT_COMBAT` ([V] M5, M7, M9 stay partial until seen).
5. Only if §6 option (b) calls the real `RegisterEvent` for any name: whether a diverted registration on an
   insecure frame raises the popup.

Phase 1's own in-game results feed in unchanged: the Snapshot logs, the G2 order probe and the G7 drain cost.

## 9. Output: go or no-go per event family

The results document is `docs/research/<date>-virtualstate-phase2-eventing-results.md`. It fills this table
and states the choices beneath it:

| Family | Consumers | Go when | No-go fallback |
|---|---|---|---|
| Own casts | E5a-d | the bus removes edits Phase 1 needs, at no timing loss | Phase 1's §4.6 writes |
| Swings | E7 | the bus subsumes §4.6 at no extra edit | §4.6 |
| Deaths | E2 | synchronous observed rows reach `eliminateUnit` | the auditor's grace |
| Debuff tracking | E8a | a retraction path exists within a measured window | `active_dot` stays 0 (spec §14) |
| Enemy counting | E9, E6 | victim-side rows do not over-count | the plate walk (spec §6.9) |
| Damage taken | E4 | player health is plain or believed | none |
| Summons, HoTs | E3, E8b | a class needs them | none |
| Pack hooks | W1-W3 | the family above that a hook reads is a go | packs read beliefs |
| `UNIT_AURA` | §5 | a depth retires the §10 edit at bounded cost | the Phase 1 edit |
| `UNIT_POWER_FREQUENT` | §2.2 | the urgent lane does not already cover it | the facade read |
| Target `UNIT_SPELLCAST_*` | §2.2 | never synthesised (identity secret) | keep or drop the `"target"` registration |

Beneath the table: the subscription shape (push or pull), the delivery option of §6, the timestamp policy of
§4.2, and the list of Phase 1 edits each go retires.

## 10. Hand-off to Phase 3

The results document is the only input Phase 3 needs besides the Phase 1 code. Phase 3 is outlined in
`docs/research/2026-10-14-virtualstate-phase3-event-bus-outline.md`; once the results exist, a session fills
that outline into an executable plan under `docs/superpowers/plans/`, for the go families only. A family with
no go stays on Phase 1's reads and edits, and Phase 3 does not plan it.
