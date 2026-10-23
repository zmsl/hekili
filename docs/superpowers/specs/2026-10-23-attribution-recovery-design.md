# Attribution recovery: Overdue for every ticket, replaceable payments, assumed outcomes (design, 2026-10-23)

Status: DESIGNED (plan: `docs/superpowers/plans/2026-10-23-attribution-recovery.md`). Amends the built unit-registry
spec, `docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md` (called "the base spec" below; its
decisions 1-45 stand except where this one names them). Base: `forever` 093313ae.
Paths are under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`. Line numbers are as of 093313ae.

## 0. The ruling and what it overturns

The owner's ruling (2026-10-23, verbatim): "We shouldn't be so rigid about lag windows. That is an inconsistent element
and we should lean towards always expecting some result if it falls out of the expected lag tolerance. Misattribution
is acceptable if it's recoverable or if the entangled tickets swapping results amount to a functional wash over time."

The owner's refinement (2026-10-23, verbatim): "Can we test what happens if we simply assume success on overdue
tickets past a lag tolerance and then issue some form of foreign ticket to be handled as a refund or whatever it
needs?" Section 3 makes that the primary mechanism and keeps the expiry-time expectation (the parked Task 9b) as the
variant it is measured against.

Overturned:

| Base | What it said | Now |
|---|---|---|
| Decision 33 | pass (c), the hard window, is open only to tickets with no learned record | every ticket has an Overdue pass, ranked after every banded candidate (decision 46) |
| §3.4.1 | a ticket with a record whose row falls outside its widened band is in no phase for that row | it is Overdue (decision 46) |
| §6.2 floors, read precision-first | false credit and foreign leak are ceilings that "only move down"; recall falls rather than precision | floors regenerate once with this ruling as the named cause; recall must rise, false credit may rise (decision 54) |
| §3.3.1 crowd gate | while crowded, the bound's early edge is refused | it is ranked: the early region becomes Overdue, never refused (decision 53) |
| Task 9b parking (`docs/dev/ingame-ledger.md:90-93`) | crediting an uncredited swing's rage cannot keep the solo `over` gate at 0 | Overdue removes the wrong-credit/lost pairs that double-counted (section 3.4); the assumed outcome is measured against that gate |

Stands: the no-jitter rule (`no-jittery-recommendations`, owner 2026-10-20): a later correction never flips an icon
by itself. Every undo in this spec obeys the hold of decision 50. The solo `over` gate
(`tests/Game/harness/solo_spec.lua:21`), `lo` over and `danger` (`solo_spec.lua:25`) stay exactly as they are: the
floor `lo` never rests on an assumption or a provisional payment.

## 1. Overdue open to every ticket

### 1.1 The rule

A row that matches no ticket at pass (a) narrow, (b) widened, (c) first-ticket hard window, and that the swing LR did
not credit, goes to a new last pass, (d) Overdue: the oldest open ticket of its queue (kind, school, speed for FLIGHT,
hand for MELEE, GUID) whose hard window holds the row. Ranked after every banded candidate, by construction: pass (d)
runs only when passes (a)-(c) and the LR found nobody. Inside pass (d), decision 45's rule still ranks a candidate whose
learned amount band accepts the row before an unbanded one; inside each group the oldest anchor (`T.at`) pays first.

Amendment (owner ruling 2026-10-23, after Task 1's gates): pass (d) is the Overdue phase of the base spec's §3.4
phase table, not "anywhere in the hard window": late, never early ("if it falls out of the expected lag tolerance").
A spell ticket is a pass (d) candidate for a row at t only once its expected tolerance has ended before t and its hard
window still holds t: a learned flight after `at + lagE + b` (its narrow band), an unlearned flight after its expected
landing `at + H / 2`, a FRAME or STRIKE wound after `at + CAST_WINDOW`. A FRAME or STRIKE avoid has no pass (d): its
pass-(b) window is its whole phase (GAP AX). Pass (d) runs after the melee scoring, so a row the swing path accepts
never reaches it, and a row the MELEE tie gave a swing that the scoring then rejected is never offered back to the cast
that lost the tie (it stays foreign). A swing ticket reaches pass (d) only in the ASSUMED state (past its tolerance,
Task 3), where a late hit is a wash and only an avoid changes the belief. A pass (d) payment teaches neither the lag
nor the amount band. Cause: the wash argument (1.3) holds for own-ticket swaps, not for other players' rows on the
same mob, which an early or open-swing grab takes (measured with an open-swing pass (d): party-with-pet drift `over`
49 -> 474 of 1200, raid false wounds 10 -> 65 per 100, three loop floors failed; with an early spell pass (d): K6 solo
recall 0.96 -> 0.87, K11 party 0.81 -> 0.46). The MELEE row below applies from Task 3.

The hard window per kind (the ticket's `hi`, set at opening, `Game/Events/Tickets.lua:250-283` and `:300-308`):

| Kind | Hard window | Pass (d) accepts |
|---|---|---|
| FLIGHT | `[at, at + H]`, `H = rMax / speed + TOL` (`Tickets.lua:257-262`) | as pass (b): a WOUND of its school inside its amount band, any avoid |
| FRAME, STRIKE | `[at, at + max(LandWindow(1), CAST_WINDOW)]` (`Tickets.lua:253-256`) | as pass (b), and a school-ANY ticket takes only a white wound past its frame (`Game/Events/Kinds.lua:126-128`) |
| MELEE (ASSUMED only, amendment above) | the LR window `[at, at + w]` (`Game/Events/Melee.lua:120-124`) | a white row, the swing not vetoed (`I.Missed`, `Rows.lua:279-282`); a wound only when its amount class for the hand is not 0 (`Melee.lua:103-112`); an avoid only on a swing not already holding one |
| TICKS, CHANNEL | none (decision 47) | nothing |
| NONE, UNMAPPED | none | nothing |

The passes as built (`Game/Events/Rows.lua:239-305`) gain one step at the end:

1. pass (a) for every kind (`Rows.lua:239`);
2. replacement (section 2.2: a provisionally paid ticket whose narrow band holds the row);
3. for an avoid, passes (b) and (c) (`Rows.lua:241-248`), then the MELEE tie (`:249-267`);
4. the swing LR (`:270-284`); a MELEE replacement when the LR credits nobody (section 2.2);
5. for a wound, passes (b) and (c) (`:285-292`);
6. new: pass (d), spell kinds (`T.Pick(t, g, 4, ...)`), then MELEE (`M.Overdue(t, g, ...)`);
7. foreign (`:302-304`).

`K.Band(i, 4, ...)` returns `at, hi[i], at` for FLIGHT, FRAME and STRIKE (E = the anchor: oldest first), and nil for
the other kinds. `M.Overdue(t, g, amount, flag, avoid, unknown)` returns the open MELEE ticket on `g` with the least
`at` that accepts the row as in the table, or nil. Both allocate nothing (one pass over the 32 records).

A pass (d) payment is provisional when the ticket's narrow band is still ahead of the row (section 2) and reconciles a
shadow ticket when the ticket is already past its lag tolerance (section 3). It teaches a lag or a band only once it
is final, and a provisional swing credit never teaches the melee median (decision 48).

### 1.2 Why TICKS and CHANNEL are excluded (decision 47)

A tick's schedule is its only discriminator (base §3.3, decision 36): a paid tick advances `done`
(`Tickets.lua:471`), so an off-schedule row paid to a TICKS ticket moves every later expected tick one period late and
the rest of the schedule goes foreign. Base decision 45 already ranks a stolen tick as worse than an unattributed row.
A tick row outside every band stays foreign, as base §3.3 says.

### 1.3 The wash argument

The base spec's FIFO proof (§3.4, "FIFO per queue, proof") shows that, within one queue, own rows arrive in commit
order: a projectile at speed `v` lands first only if the distance shrinks faster than `v` between the two successes,
and no mob or player closes at 20 yd/s. For MELEE, the same hand's swings are at least one swing period apart (1.3 s
or more) and the landing-lag spread is under 0.4 s (`Melee.lua:47`, the learned `spr` clamped to [0.02, 0.4] by
`I.Stats`), so a hand's rows also arrive in swing order.

Pass (d) pays the oldest open ticket of the queue. So the payments of one queue are a monotone matching of its rows to
its tickets, whatever mix of own and foreign rows arrives. Let a queue hold tickets `q1 < q2 < ... < qn` that all
stage the same effect for the same row class (the same ability, or the same hand: `swingStep` reads only the hand and
the row's class, `Game/State/Families/Resources.lua:849-882`; `Obs.Crit` and `Obs.Avoided` read the ability,
`Rows.lua:76-84`, `:188-190`). The belief after the queue is `B = sum over paid rows of effect(class(row))`. Two
monotone matchings of the same set of paid rows give the same `B`: a swap inside the queue changes which ticket
carries a row, not the multiset of classes. That is the wash: own-ticket swaps inside a queue change no belief over
time.

What is not a wash, and where it goes:

- A foreign row in, an own row out (the cascade of base §3.4 ends with one own row foreign). The difference is
  `effect(class(foreign)) - effect(class(own))`: zero when both are plain hits, one step of rage or one crit or one
  avoid otherwise. Section 2 replaces it when the own row lands in its ticket's narrow band before the hard window
  ends; the usability oracle re-pins rage when it does not (`Rows.lua:344-378`, `Resources.lua:926-952`).
- A swap across queues of different effect: main and off hand (different `I.SwingValue`), or two abilities with
  different `onCrit`. Bounded by the base cascade bound (decision 32) and counted by the net-wash metric (section 5).
- Timing: a swapped swing's rage is staged at the other swing's time (`Rows.lua:330`), at most one swing period off;
  over a fight the sum is unchanged.

## 2. Replaceable payments

### 2.1 Provisional and final

A payment is final at once when it is made at pass (a) (the row is Due), at pass (c) (no record: the ticket has no
narrow band, so nothing could replace it), or when the row is already past the ticket's narrow band end. Otherwise
(pass (b) or (d) before the narrow band has passed, or a MELEE credit whose lag is outside the hand's core band,
`Melee.lua:145-148` band 2, before that band has passed) it is provisional.

A provisionally paid ticket goes to a new state TENT (4) instead of closing: `owed` is 0 (so `K.Accepts` refuses it,
`Kinds.lua:82`, and `T.Pick` never offers it), it keeps its unit held (`U.Hold`, `Tickets.lua:227`), and it records
`fin[i]`, the time it becomes final:

- spell kinds: `min(narrow band end, hi[i])`, the narrow band from `K.Band(i, 1, ...)`;
- MELEE: `min(at + L.med[h] + 2 x L.spr[h], at + w[i])`, `h` the hand (the core band, `Melee.lua:146`).

`T.Expire` (`Tickets.lua:598-607`) closes a TENT ticket whose `fin` has passed as `paid` (counted once, `T.paid[kind]`
then) and runs its deferred work (2.3). `T.EndCombat` closes it as `ended` like any other (`Tickets.lua:610-619`) and
drops its held observation, as combat end drops a provisional avoid today.

### 2.2 Replacement

A later row on the same GUID that falls inside a TENT ticket's narrow band, that the ticket would accept with one row
owed (school, amount band, `Kinds.lua:80-112`), and that no open ticket took at pass (a), replaces the first row
(for MELEE: inside the hand's core band, the LR crediting no open swing, the amount class not 0 for a wound). The
oldest TENT ticket that qualifies is replaced. Then:

1. The first row is re-labelled foreign: `T.foreign + 1`, `T.Foreign(uid, its school, its time)` (it arms the crowd gate
   at the time it arrived), `T.replaced + 1` (a new counter; the existing `closed.replaced` stays the strike's swing).
2. Its staged effects are undone where the machinery can (2.3) and dropped where they were held.
3. The new row pays the ticket as a pass (a) payment: final at once, staged at once, the ticket closes `paid`.
4. Nothing re-routes the first row to another ticket (no cascade from a replacement).

The answer to the owner's question, "what happens if we misattribute but then we see a dodge": a foreign WOUND paid our
swing ticket in its Widened phase (provisional: TENT, `Obs.Swing` c = 1 staged with record `id`); our own DODGE arrives
in the swing's core band. The DODGE replaces the WOUND: the WOUND becomes foreign; Rows stages `Obs.Swing` c = 6 for
record `id` and Resources retracts that credit's rage through the existing retraction (2.3); the ticket holds the DODGE
as its avoid (`T.Provisional(i, math.huge, "DODGE")`: final, no wound overtakes it) and emits `SWING_MISSED` at its
window's end. For a spell ticket (a WOUND paid a Mortal-Strike-like FRAME ticket at pass (b), then its own DODGE lands
in its frame): the WOUND's held `Obs.Crit` (if any) is dropped, the DODGE stages `Obs.Avoided`, and
`Game/State/Families/Now.lua:469-486` undoes the cast's target auras and refunds its `refundOnAvoid` share, when it is
still the latest cast (as for every avoid today, `Now.lua:470`).

### 2.3 What can be undone, and what cannot

Undone with existing machinery:

| Effect of the first row | Undone by | Condition |
|---|---|---|
| MELEE rage, `Obs.Swing` c = 1 and its crit c = 3 (`Rows.lua:330-333`) | the credit record's deltas: `recLo`, `recHi`, `recEst`, `recHit` and `back()` (`Resources.lua:919-925`), the same deltas `verdict`'s retraction takes back (`:943-950`, left as it is: an answer is a measurement), in a new `retract(k, t)` that `Obs.Swing` c = 6 calls, with the hold of 2.4 | the record still names its slot (`recR[k] > 0`) and no spend of ours from the slot since (`R.spends[recR[k]] == recSpends[k]`, `:930-933`); else final (the spend's rung measured the pool) |
| the credit record's open verdict | `recOpen[id] = false` in Rows (`Rows.lua:345-347`) | always |
| `L.credited[hand]`, `L.credited[3]` | decrement | always |
| a provisional swing avoid (`T.Provisional`) | it stages nothing until its close (`Rows.lua:87-91`) | always (as today, a higher-LR wound overtakes it, `Melee.lua:172`) |
| spell `Obs.Crit` | held, not staged, while TENT; staged at `fin`, dropped on replacement | always |
| spell `Obs.Avoided` (aura undo and refund) | held while TENT; staged at `fin`, dropped on replacement | always |
| the FLIGHT lag record (`T.Learn`, `Tickets.lua:465-467`) and the amount band (`teach`, `:468-470`) | not taught while TENT: taught at `fin` from the stored row (time, amount, flag), never when replaced | always |
| the melee median (`M.learn`, `Rows.lua:315-320`) | a provisional swing credit never teaches it: it lies outside the core band, and the learn gate (3 spreads) then loses only its 2-3 spread ring | always |

Final (cannot be undone; the payment is then made final at once, never TENT):

| Effect | Why |
|---|---|
| the emitted combat-log row (`SWING_DAMAGE`, `SPELL_DAMAGE`, `SPELL_MISSED`, `Rows.lua:57-74`) | Hekili's CLEU handler already consumed it. The replacing row is emitted too: two rows for one ticket, the precedent of the firm retraction (`Rows.lua:368-370`, harness decision D9) |
| a direct ticket's composed TICKS work (`Tickets.lua:488-500`: re-anchor, `refresh` closes older schedules) | a closed schedule cannot reopen; so a direct ticket with a live link (`T.link[i] > 0`) is never provisional |
| an `onCrit` already run | pack code with untracked writes (`Now.lua:455-462`, `journal = false`); never run while TENT (held) |
| a divergent payment (`Rows.lua:183-186`) | it staged nothing; replacement only re-labels it |
| the background rates | the first row arrived while our ticket was pending, so `M.background` would not have taught (`Melee.lua:190`); nothing to undo |

### 2.4 The hold (decision 50)

Retracting rage moves three numbers. `lo` takes the retraction at once: the floor must never stand above the truth
(the `lo` over and `danger` gates). `hi` takes it down to `est` at most. `est` does not move by itself: the retraction's
`est` part waits in a per-slot debt (`estDebt[r]`, preallocated) and is applied, through `back()`, at the slot's next
usability answer (before its ladder, `Resources.lua:1033-1047`), at its next spend's rung (`Obs.CastSuccess`,
`Resources.lua:1208-1220`), or dropped at combat end. Recommendations read `est`; an answer or a spend is a measurement, so the icon
changes only when the game says so. This is the same rule as base §4.2 ("a wide belief never flips the icon by
itself") and the owner's preference for a one-poll hold over a flash. The hold covers every retraction this spec
makes: a replacement (2.2) and a refund of an assumed outcome (3.2).

## 3. Assumed outcomes past the lag tolerance

### 3.1 The lag tolerance and the shadow state

Each ticket that can be assumed has a lag tolerance `tol[i]`, set when it is armed:

| Kind | `tol` | Assumed outcome |
|---|---|---|
| MELEE | `at + T.PendingWindow(h)` (`Tickets.lua:311-314`: the hand's landing window, capped at 1 s), the moment `VS.SwingPending` stops counting the swing (`Resources.lua:1269-1285`) | a hit: rage staged (3.2) |
| FLIGHT with a lag record | the widened band's end, `K.Flight(i, 2, at, ...)`'s `hi` (`Kinds.lua:72-75`) | a hit: nothing staged (no resource belief for a spell hit) |
| FLIGHT with no record, FRAME, STRIKE | none: their widened band ends at `hi` (`Tickets.lua:253-262`) | none: their expiry stays as today |
| TICKS, CHANNEL, NONE, UNMAPPED | none | none |

When `now > tol[i]` and the ticket is still OPEN (unpaid, no provisional avoid, pinned, its unit not DEAD), the
per-frame `T.Expire` moves it to a new state ASSUMED (5), the shadow ticket, in the same slot. It stays a candidate to
the end of its hard window (`hi`): the late rows that reach it come through the LR (MELEE, still inside `[0, w]`) or
pass (d) (section 1). Rows' hook `T.onAssume(i, now)` stages the assumption (3.2).

The swing case is the continuity the belief needs: until `tol` the swing's rage is forecast as pending
(`VS.SwingPending`, the simulation's forecast, `Resources.lua:1259-1268`); from `tol` it is believed, without a gap in
which the swing counts as neither.

### 3.2 Staging and reconciling

Assumption, MELEE: Rows takes a credit record (`Rows.lua:321-325`, `recOpen` true, `recLR` 0) and stages `Obs.Swing`
c = 5, b = that record. Resources pays it like a landed step on `est` and `hi` only: `lo` is untouched, so
affordability never rests on an assumption, and the record keeps the deltas (`recLo` = 0) so that `retract(k, t)` can
take it back. What it stages is a variant, measured (3.3):

- FULL: the full step, `I.SwingValue(r, hand, at) x R.scale[r]` (the shape of c = 1's `est` delta, `Resources.lua:851-854`);
- EV: the expected step, `hitRate[hand] x` that (the parked 9b patch's shape, `task-9b-round2-blocked.patch`).

Assumption, FLIGHT: nothing is staged; the ticket only moves to ASSUMED.

Reconciling, when a row pays an ASSUMED ticket before `hi`:

| Row | MELEE | FLIGHT | Close |
|---|---|---|---|
| WOUND | `Obs.Swing` c = 7, b = the assumption's record: the record becomes the credit; `est` and `hi` take what a landed step adds beyond what the assumption already added (0 for FULL, `(1 - hitRate)` of the step for EV), `lo` takes the landed step's floor, the hit rate rises as for c = 1; a CRITICAL adds c = 3 with the same record. No retraction, so no hold is needed and nothing is counted twice | `Obs.Crit` on CRITICAL as a normal payment; the row emitted | `confirmed` |
| avoid (DODGE, PARRY, MISS) | c = 6 (the assumed rage retracted, with the hold of 2.4); the ticket holds the avoid (`SWING_MISSED` at `hi`) | `Obs.Avoided` staged: Now undoes the cast's target auras and refunds `refundOnAvoid` (`Now.lua:469-486`) when it is still the latest cast | `refunded` |
| none by `hi` | the assumption stands; `SWING_DAMAGE` 0 is still emitted for the swing timer (`Rows.lua:87-91`) | the assumption stands | `assumed` |

An ASSUMED ticket is never counted `lost`: `assumed` replaces `lost` for the kinds that assume. `T.lost[kind]` keeps
counting the kinds that do not (FRAME, STRIKE, FLIGHT with no record, TICKS).

A firm retraction's re-open (`Rows.lua:367-368`, `T.OpenSwing(..., retry)`) is never assumed: the usability answer
said the slot is short, so its swing most likely gave nothing (`T.retry[i]`, a preallocated boolean).

### 3.3 The comparison variant: expectation at expiry

The parked 9b design, kept as the measured alternative: no ASSUMED state; a MELEE ticket that closes `lost` (its
window ends unpaid on a live unit, not provisional, not a retry) stages `Obs.Swing` c = 5 at its close
(`task-9b-round2-blocked.patch`: `T.onLost` in `expiry()`), FULL or EV, `lo` unchanged, no reconciliation (nothing can
pay a closed ticket). Spells expiring unpaid stay silent in both variants.

The four variants (tolerance or expiry, FULL or EV) run on the same seeds under a harness flag (`T.ASSUME_AT`
`"tolerance"` or `"expiry"`, `I.ASSUME_VALUE` `"full"` or `"ev"`, load-time constants the harness sets). Measured: the
four rage gates (`over`, `lo` over, `danger`, the mean error, `solo_spec.lua:21-25`, `group_spec.lua:25`, `:38`), the
loop flicker floors (`tests/Game/harness/flicker_spec.lua`), Fury L24 agreement (`make test-loop`) and the recovery
metric (section 5). The plan's Task 3 keeps the variant that measures best (the order of the criteria: the solo `over`
gate and `lo`/`danger` must hold; then flicker; then agreement; then the mean error) as the only code path, deletes the
other, and records all four rows of numbers with the owner's ruling in the commit and in `docs/dev/gaps.md`.

### 3.4 Why the solo `over` gate can hold now

The 9b root cause (`task-9-report.md`, round 2): in solo, 132 of 2400 swings closed lost; a wrong credit paid the
other hand's ticket, so the true ticket closed lost and its expectation counted the same rage twice; and a lost
ticket whose row was a miss gained a swing it never had. With pass (d), the true ticket's own row, arriving later in
its window, pays it (Overdue) instead of going foreign, so the wrong-credit/lost pair becomes a cross-hand swap: rage
error `I.SwingValue(main) - I.SwingValue(off)`, under one step, which `over` does not count (`err >= step`,
`tests/Game/harness/metrics.lua:201`). A missed swing's MISS row likewise reaches its ticket (an avoid at pass (d)) and
no rage is assumed for it. What is left lost in solo is a ticket with no row at all, which the truth also has none
for. Not a proof: the gate decides (3.3).

### 3.5 Counters and conservation

`T.closed` gains `confirmed`, `refunded`, `assumed`; `T.replaced` counts re-labelled first rows (not a close). The
Snapshot line (`Tickets.lua:670-699`) becomes:

```
tickets open=%d none=%d paid=%d lost=%d expired=%d refreshed=%d foreign=%d unpinned=%d dead=%d gone=%d bandRejected=%d
divergent=%d overflow=%d absorbed=%d ours=%d aoeOther=%d overpaid=%d tentative=%d replaced=%d assumed=%d confirmed=%d
refunded=%d
```

(`tentative` is the number of TENT tickets open now.) Conservation (the invariant sweep,
`tests/Game/harness/detect_sweep_spec.lua`, base §6.2):

`opened = none + paid + signal + replaced(strike) + refreshed + stopped + expired + lost + dead + gone + ended +
overflow + unpinned + provisional + confirmed + refunded + assumed + open (COMMITTED, OPEN, PROV, TENT, ASSUMED)`.

Every TENT ticket closes exactly once (`paid` at `fin`, or `ended`, `overflow`, `gone`); every ASSUMED ticket exactly
once (`confirmed`, `refunded`, `assumed`, or `ended`, `overflow`, `gone`, `dead`). A DEAD unit's ASSUMED ticket closes
`dead` at `hi` (base decision 8) and its assumption stands.

## 4. The crowd gate as a ranking aid

Base §3.3.1's crowd gate (`Kinds.lua:65-71`) moves the widened band's lower edge from the running-mob bound back to
`lagE - max(b, CLOSE / v x d)` while a foreign row of the ticket's school reached its unit within `CROWD`. Before this
spec a row in between was refused (no phase). Now it is Overdue: pass (d) offers it to the oldest ticket of the queue,
after every banded candidate, and the payment is provisional (its narrow band is still ahead, 2.1), so the ticket's
own row replaces it if it lands in the narrow band. The gate never refuses; it only orders. No code changes in
`K.Flight`: the region simply falls to pass (d). The arming rule (`Rows.lua:207`, foreign rows only) is unchanged.

## 5. Detection suite

### 5.1 Floors regenerate, with this ruling as the named cause

`tests/Game/harness/detect_floors.lua` is rewritten once by `DETECT_WRITE=1` (`tests/Game/harness/detect.lua:243-291`)
after Tasks 1-4, with a note above each kind whose cells moved down: "2026-10-23 ruling (attribution recovery): recall
over precision; false credit may rise". The expected directions:

| Cells | Recall | False credit, leak | Why |
|---|---|---|---|
| K1 party, busy (melee) | up | up | white rows past the LR bar pay the oldest swing (pass (d)) |
| K10 party, busy | up (the largest move: tail lags of a slow session now pay) | up | `docs/dev/ingame-ledger.md:82-84` |
| K4, K5, K7, K8 party, busy | up | up | the running-mob region and the crowd region are Overdue, not refused |
| K6 party, busy; K11, K11m | up | up | late rows pay their tickets |
| K13 (all phases) | up | up | the twin's displaced row pays at pass (d) |
| K14p | n/a | pet rows paid up | pass (d) MELEE cannot tell a pet's white hit from ours (U15 family) |
| K14f, K10 `rageErr` | | mean error down (toward 0) | assumed rage for the late swings |
| K16 raid-40 (measured) | up from 0 is possible | up | Overdue pays before a band is learned; still measured only |
| K1-K3, K9, K12, K15, K17, K19, K21 solo; K20 captures | unchanged | unchanged | no foreign rows; own rows land in their narrow bands |
| `lostDiff` party, busy | | may rise | engine `lost` falls (assumed, Overdue), truth's lost does not; the metric compares `lost + assumed` with the truth (5.2) |

Floors still only move up afterwards. A solo cell that moves down, any K20 capture assertion that changes, or a
`staged` cell that moves down stops the branch for the owner.

### 5.2 New metrics

Per kind x band, printed by `metrics.ticketLine` and floored like the others:

- **recovery**: for each false credit (a row paid to a ticket truth says is not its own), whether it was recovered
  and how many ms later: `replaced` (the engine re-labelled it, `T.onReplace` hook in the drive), `re-pinned` (a
  usability verdict retracted its record, or the slot's next pin moved `est` within one step of the truth; drive hook
  on `I.CreditVerdict` and the `pinned` samples), `neutral` (it staged nothing: a plain hit for a plain hit, or a
  divergent row), or `unrecovered`. Cells: `recovered100` (replaced + re-pinned + neutral, per 100 false credits;
  a floor) and the median ms to recovery (printed only).
- **net wash**: per fight, the sum over own-ticket swaps (a row of ours paid to another ticket of ours) of the signed
  staged difference: rage `believed - true` for swings, and per ability the count of staged crits and avoids believed
  minus true. Cells: `wash` = mean over fights of the absolute net rage error of swaps (a ceiling) and the gross
  (mean of the absolute per-swap errors, printed): a wash shows as `wash` well under the gross.
- `lostDiff` compares the engine's `lost + assumed` with the truth's lost.

The solo `over` gate and `lo`/`danger` (`solo_spec.lua:21-25`) stay exactly as they are and are not re-floored.

## 6. Risks and gate

The gate is the full merge gate (`make gate`), as base §9.

| Must not move down | Expected |
|---|---|
| every wowsims replay floor (`make check`'s slow tier) | unchanged for casters (FLIGHT tickets with records gain a pass (d)); melee classes may gain credited swings (rage belief closer); any move gets its named cause |
| `make test-loop`, every loop tag | Fury L24 agreement UP (more swings credited, assumed rage at the tolerance; today 0.960 with the swallowed swing, base §3.7); no flicker floor up |
| `flicker_spec.lua` | unchanged or better: the hold (2.4) keeps every retraction off the icon |
| the solo `over`, `lo` over and `danger` gates | unchanged (0, measured, 0) |
| `make bench-ta` rows/s floor 97000 (`tools/bench_ta_floor.lua`) | pass (d) is one more 32-record scan per unmatched row; the bench must hold its floor |
| memory ceiling 192 KB, `alloc_spec.lua` | new per-ticket arrays (about 14 x 32 numbers) and per-slot `estDebt`: preallocated |

| Risk | Why | What the gate shows |
|---|---|---|
| Party melee false credit rises past `group_spec.lua:25` (`falseNet <= 4`) and `:38` (`<= 6`) | pass (d) pays foreign white rows to our swings | these two bars are precision-first bars of the overturned reading: re-based with this ruling as the named cause if they fail; the drift bars (`over <= 0.05`, `0.10` windows) stay |
| Assumed rage overshoots | a swing assumed hit that really missed with its row lost | `over` gates; the oracle's verdict retracts it (the assumption is a record) |
| A retraction flips an icon | rage taken back at a row | the hold (2.4); flicker floors |
| A replaced row's emitted combat-log row lingers | not undoable (2.3) | Hekili's handler sees two rows for one ticket, as with a firm retraction today |
| TENT tickets fill the pool | a ticket stays held up to `fin` | K16 overflow count unchanged (fin is at most the narrow band's end, under `hi`) |

## 7. Probes

| ID | Question | Capture |
|---|---|---|
| U17 | How often a late row (past `tol`) reconciles an assumed swing in game, and how often it is an avoid (`refunded`) | Snapshot's `assumed`, `confirmed`, `refunded` after a five-man dungeon run as Fury, plus a `/vslog` of the same pull |
| U18 | The in-game replacement rate: a provisional payment replaced by a narrow-band row | Snapshot's `replaced` and `tentative` over the same run |
| U16 (kept) | the crowd rate; now it decides how often the crowd region pays at pass (d) | as base §8 |

No new capture is needed to build: every rule here reads rows the registry already dispatches.

## 8. Research and spec: parry haste (research task, not a design)

Status: research + spec only. No code. Deliverable: `docs/research/2026-10-xx-parry-haste.md` and a spec section
(a new section of this spec, or its own spec) ready for a plan.

What is known:

- Classic rule, as wowsims implements it (`~/src/wowsims-forever/sim/core/attack.go:1173-1207`, `applyParryHaste`):
  when a unit parries a melee attack, if its main-hand swing has more than 20% of its swing duration remaining, the
  swing is pulled forward by `min(0.4 x duration, remaining - 0.2 x duration)`. It applies to any unit whose
  `PseudoStats.ParryHaste` is set: targets by encounter option (`sim/core/target.go:230`) and characters that can parry
  (`sim/core/character.go:424`). So it applies both ways: a mob parrying us hastens the mob's next swing; us parrying a
  mob hastens our main hand.
- The replay already carries it: every wowsims request sets `parryHaste: true` (`tools/wowsims/export.lua:40`,
  `tests/Forever/wowsims/*.json:15`).
- One in-game observation: log 1 of `docs/research/2026-10-16-swing-outcome-pairing.md:28`: a parry on us pulled the
  next main-hand swing forward, 771 to 2110 ms (1.34 s on a 2.2 s weapon; 0.86 s early, which is 0.39 of the weapon
  speed, the 40% rule).
- Nothing in `src/` models it. The harness says so (`tests/Game/harness/scenarios.lua:102-103`: "no parry haste on our
  swing timer").

The task must:

1. Confirm the Forever rule. Read the wowsims code above and its tests (`sim/core/*_test.go`) for the exact clamp;
   check whether the off hand is ever hastened (wowsims: main hand only). Capture in game with the ForeverProbe
   recorder (the owner cannot copy chat: `/vslog` writes the copy box, lines under 255 chars): ten parries on us
   (`UNIT_COMBAT player PARRY`) while auto-attacking, `PLAYER_SWING` with its payload (speed, hand) before and after
   each; and ten of our swings parried by the mob (`UNIT_COMBAT target PARRY`) with the hits on us around them. Measure
   the shortening against `min(0.4 s x speed, remaining - 0.2 x speed)`.
2. Say what the beliefs must do on an observed PARRY on us:
   - `VS.SwingPending` (`Resources.lua:1269-1285`, `Tickets.lua:320-330`) is about a swing that already happened: a
     parry changes nothing there (expected; confirm).
   - The forecast of our next swing (Hekili's `state.swings.mh_actual` + speed, fed by `SWING_DAMAGE` rows and
     `Sources/Swing.lua`'s `Obs.Swing` c = 4; `Engine/Sim/State.lua` forecasts its rage): whether the next main-hand
     swing time should move earlier at the parry row, and through which observation (a new `Obs.Swing` code, or the
     swing clock's anchor in `Sources/Swing.lua`).
   - The swing ticket anchor: tickets anchor at `PLAYER_SWING` (`Rows.lua:95-116`), which the client sends at the real,
     hastened swing, so the anchor is right without change (confirm from the capture).
   - A mob parrying us: `Game/Events/Attackers.lua`'s per-attacker clock (`:43-75`, anchor and period) predicts the
     mob's next hit for the hits-on-us credit (`ATTACK_TOLERANCE` 0.2 s, `:24`); a parry by the mob pulls its next swing
     up to 0.4 x its period early, outside that tolerance. Say whether the clock should re-anchor at our swing's PARRY
     row on that mob.
3. Say what the gates would do: the wowsims replay already simulates it, so a harness and belief without it differ
   from the replay's truth exactly at parries; estimate how many loop disagreements (Fury L24, Arms, Protection) fall
   within one swing after a parry, from the replay logs, before and after modelling it; and whether the harness's
   world (`tests/Game/harness/world.lua`) should model it (the `scenarios.lua:102-103` shortcut).
4. End with a spec section: the observation(s), the belief changes, the harness change, the floors expected to move
   and in which direction, and the probes left open.

## Decisions made in this spec

| # | Decision | Reason |
|---|---|---|
| 46 | Supersedes decision 33. A new last pass (d), Overdue, for every ticket: a row that no pass (a)-(c) and no LR credit took pays the oldest open ticket of its queue whose hard window holds it (amount-banded first, decision 45); spells by `K.Band(i, 4)`, swings by `M.Overdue` (white, not vetoed, amount class not 0, an avoid only on a swing holding none). AMENDED 2026-10-23: phase-gated, late never early: a spell ticket is a candidate only once its expected tolerance has ended (a learned flight past its narrow band, an unlearned flight past `at + H / 2`, a FRAME or STRIKE wound past `CAST_WINDOW`; no FRAME or STRIKE avoid) and its hard window holds the row; after the melee scoring, never a row the MELEE tie took from the cast; a swing ticket only ASSUMED (Task 3); a pass (d) payment teaches neither the lag nor the amount band | the owner's ruling: always expect some result outside the lag tolerance; FIFO per queue keeps own swaps a wash (1.3). The amendment: the wash holds for own-ticket swaps, not for other players' rows on the same mob, which an early or open-swing grab takes (party-with-pet `over` 49 -> 474 of 1200, raid false wounds 10 -> 65 per 100, three loop floors; K6 solo recall 0.96 -> 0.87 with early spell payments) |
| 47 | TICKS and CHANNEL have no Overdue pass and are never assumed | a paid tick moves the schedule (`done`), so an off-schedule row would make every later tick foreign; a stolen tick is worse than an unattributed row (decision 45) |
| 48 | A payment at pass (b) or (d), or a MELEE credit outside its core band, made before the ticket's narrow band has passed, is provisional: the ticket goes TENT (state 4, `owed` 0, unit held) until `fin` = min(narrow band end, `hi`); a later row inside that narrow band (no open ticket taking it at pass (a); for MELEE, the LR crediting no open swing) replaces it: the first row becomes foreign, the new row pays final; a provisional payment teaches the lag and the band only at `fin`; a provisional swing credit never teaches the median | "recoverable": the narrow band is the strongest evidence of ownership; teaching late keeps undo trivial |
| 49 | Undoable: swing rage (c = 1, c = 3) through the credit record's deltas and `back()` (`retract(k, t)`, called by `Obs.Swing` c = 6; the verdict's own retraction unchanged), while no spend of ours from the slot since; spell `Obs.Crit` and `Obs.Avoided` are held while TENT. Final, and so never TENT: a direct ticket with a live TICKS link; the emitted combat-log row stays (the replacing row is emitted too, as the firm retraction's two rows) | each undo uses machinery that exists; what has no undo is either held or not made provisional |
| 50 | The hold: a retraction (replacement or refund) takes `lo` at once, `hi` down to `est` at most, and `est` only at the slot's next usability answer, its next spend's rung, or never (combat end) | no-jitter: a correction never flips an icon by itself; `lo` stays a floor |
| 51 | Primary: past its lag tolerance (MELEE: the pending window; FLIGHT with a record: the widened band's end) an unpaid ticket goes ASSUMED (state 5, a shadow in the same slot) until `hi`; a swing stages its assumed rage at once as a credit record (`Obs.Swing` c = 5, `est` and `hi` only); a late hit closes `confirmed` (`Obs.Swing` c = 7 turns the assumption's record into the credit: a wash), a late avoid `refunded` (c = 6 retracts it with the hold, `Obs.Avoided` for a spell), no row `assumed`; a retry ticket is never assumed; comparison variant: the expectation at the `lost` close (9b) | the owner's refinement: assume success past the tolerance, then a refund ticket; continuity with `VS.SwingPending` |
| 52 | Two values measured for the assumption: FULL (the step) and EV (`hitRate` x the step); the four variants run on the same seeds behind load-time constants; Task 3 keeps the best (solo `over` and `lo`/`danger` first, then flicker, agreement, mean error) as the only code path and records all four | the owner asked to test it; the gates choose |
| 53 | The crowd gate orders, never refuses: its region falls to pass (d) and pays provisionally | the ruling; no code change in `K.Flight` |
| 54 | The detection floors regenerate once with this ruling as the named cause (recall up, false credit and leak may rise; the expected cells in 5.1); the group gates' `falseNet` bars (`group_spec.lua:25`, `:38`) may re-base the same way; the solo `over`, `lo` and `danger` gates do not move | precision-first was the overturned reading; the safety gates are not about precision |
| 55 | New detection metrics: `recovered100` (replaced, re-pinned or neutral per 100 false credits, a floor; median ms printed) and `wash` (mean absolute net rage error of own swaps per fight, a ceiling; gross printed); `lostDiff` compares `lost + assumed` with the truth | misattribution is acceptable only when recovered or a wash: both must be measured |
| 56 | Gate: every wowsims replay floor, `make test-loop` (Fury L24 agreement expected up), the flicker floors, the solo safety gates, `make bench-ta`, the memory ceiling and the allocation specs must not move down; the Snapshot line gains `tentative`, `replaced`, `assumed`, `confirmed`, `refunded` | the base spec's gate, plus the counters the in-game probes U17 and U18 read |
