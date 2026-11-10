# The Cooldown Manager verdict: a proven item dark for W closes the record (spec amendment, 2026-11-09)

Amends `2026-11-07-cdm-default-design.md` (decisions 92-115) with decisions 116-124. Base integ/0.7 38daebe33. Written by
the Fable lead under the owner's mandate (cdm-fable-brief.md); every judgement call is in cdm-fable-decisions.md.

## 0. The owner's rulings this rests on

- L364: "after a certain time dark means dark; a wrong belief must not carry the full duration." For a PROVEN item (per
  cooldownID, lit before in this build) continuously dark for W (from the later of the write or the last UP; W per cast,
  >= 1.0 s plus travel) close the record of ANY opener (our cast, a walk read of ours, a CDM open), no refund; a strike
  counter caps wrong verdicts at 2 per item; unproven items and the non-current mob after a swap stay belief-only;
  unknown never closes.
- L366/L368: proof is required (an item that never lit gives no verdict); config-trust would loop a never-lighting item.
- L375: tolerance for frame reshuffling (state keyed by cooldownID; a re-pointed frame settles; dark is continuous across
  sweeps); shared auras are DROPPED from this slice (the viewer lights only player-cast auras: a partner overwrite costs
  one recast, L291); NO rebuild trigger on rank change: the pack audit (every rank in id/copy) replaces it.
- L353: edge anchors are not built; the hold rule (decision 112) is unchanged.
- L374/L376: the per-aura switch `def.auras[j].cdm == false` (the Cooldown Manager options panel) takes the aura out of the
  leaf's map: no proof, no dark, no strikes, no verdict for it.

## 1. Facts (measured 2026-11-09, L361; Blizzard's Forever viewer source, cdm-uses-fable-review.md §1)

- Cast -> item lit: +1 frame, median ~10 ms, tail 100-120 ms (n ~10 of ~150), outliers 323 ms (Rip, instant) and 863 ms
  (Feral Charge, travel). Modelled expiry matches the item's dark to ~50 ms.
- The viewer reads PLAYER-cast auras only (`HARMFUL|PLAYER` / `HELPFUL|PLAYER`): a lit item is always our own aura.
- Every UNIT_AURA full update (each target swap) releases and re-acquires every item frame in all four viewers: the
  frame <-> cooldownID assignment is reshuffled; a frame keeps nothing of its old item. The cooldownID is the item's
  identity; the frame is not.
- Hide-when-inactive only hides the item; `cooldownID` and `layoutIndex` stay; a dark tracked item keeps a frame with its
  cooldownID in both settings (Q16).
- The sweep's t is the drain's: forced 0.2 s after our cast or a target change, 0.5 s unforced.
- One of ~30 dark-at-cast casts never lit although UNIT_AURA fired (Nature's Grasp); Mark of the Wild lit only after the
  player levelled past the old rank (the item follows the current rank).

## 2. The signal: a proven positive dark (decision 116)

Today a silent slot is evidence (NONE) only for an application it was seen holding (the seen rule, decision 115); a cast
that never lights the item is never closed by the item: the belief carries the modelled duration (Rake 9 s, Roots 15 s)
after a dodge, resist or immune. The verdict adds a second, separate signal and leaves the seen rule, `closes()` and the
reducer untouched.

### 2.1 Proof, per cooldownID (decision 117)

- `provenCd[id]` (the leaf, preallocated at `build()` to the map's keys, out of combat; zeroed at every build, so a new
  rank's build starts unproven) becomes true the first time a slot with plain `cooldownID == id` reads UP for its single
  mapped aura j while its viewer is visible, on either unit, in or out of combat (an out-of-combat light during the walk
  counts). `provenU[id]` remembers the unit it last lit for (1 player, 2 target): a dark item is dark for THAT unit (a dark
  item carries no `auraDataUnit`; the item's unit is what it was seen lighting for).
- Never per slot: a per-slot bit dies at every reshuffle.
- `strikesCd[id]` (§2.5) at `STRIKES_MAX` clears the proof for the build.

### 2.2 The dark count (decision 118)

The leaf's `Q.Counts(j, u)` gains a 7th value, `nDark`: the slots that this sweep are
- configured and mapped to one aura j (`m > 0`, as for UP/NONE), and proven (`provenCd[sCd[s]]`), and
- silent (`auraInstanceID` nil, not secret), and
- monitored: their viewer visible and, for `provenU == 2`, not settling (§2.4), and
- continuously dark: `sDarkN[s] >= DARK_SWEEPS` (2) consecutive monitored dark sweeps (the first dark sweep after a light,
  a re-point or a settle counts 1).
Counted for `k = (provenU[id] - 1) * AURA_UNIT + j` as `cDark[k]` (preallocated like `cUp`), moved in O(1) like the other
counters (it does not make the slot "live": `nLive`, `covered`, `Reduce` and the reduced state are unchanged). A slot
that also passes the seen rule is a NONE AND a dark: both counts hold; the reduced DOWN closes first (rule 1), the
verdict finds the record closed and does nothing (§2.3 keys on the record's applied time).

### 2.3 The router and the verdict (decisions 119-120)

- Router: `fact.pdark[k] = nDark > 0 and nUp == 0` at every reduction of thing k (no state change, no edge, no `fact.t`).
  `R.Presence` is unchanged; `fact.pdark` is read by poll 15 only.
- Poll 15 (`Sources/Auras.lua`), after `apply` for the pair, under the same guards as `apply` (in combat only or the
  walk not plain; forms and enchants skipped; `I.targetSlot == I.curSlot`): the record of (j, u) is closed when ALL hold:
  1. the record is up: `U.exp0[u][j] > t`;
  2. our evidence opened this application: `ours[k] ~= 0 and oursAp[k] == U.applied[u][j]` (any opener: cast, walk read
     with source player/pet, CDM open; a record a partner's walk read opened has `ours` 0 and is never judged);
  3. the reduced state is not UP and `fact.pdark[k]` is true now;
  4. `t >= max(oursAp[k], upAt[k]) + W[k]`: W elapsed since the later of the write and the last UP read;
  5. `I.verdictOff` is not set (harness only, §6).
  The verdict runs for every pair at every poll 15, INCLUDING the poll's no-live-slot branch (`P.covered == 0`): a dark
  slot is never live, so a lone dodged aura has `covered` 0 and the verdict must not sit behind the live-slot guard
  (implementer's finding; the rule is the same, only its placement).
  Then `Direct(Obs.Read, t, k, 0, ReadOf.Aura)` once (the `staged[k]` guard), `verdictAt[k] = t`, `verdictN[k] += 1`.
  No refund, no ticket change (brief-1 M1/N3: tickets expire on their own). The close label stays `expired`.
- W per record: `I.AuraOurs(u, j, travel)` (Families/Now.lua passes `travel = rMax / velocity` seconds for an ability
  with `A.velocity[a] > 0`, else 0); `W[k] = max(W0, travel + TOL)`, W0 = 1.0 s, TOL = 0.3 s (viewer tail 0.12 s + one
  frame + margin; tune from Task 10's P1). A walk read or a CDM open sets `W[k] = W0`.

### 2.4 Reshuffle tolerance (decision 121)

- (a) Identity is the cooldownID. Per cooldownID (preallocated at build): `provenCd`, `provenU`, `strikesCd`, and the seen
  rule's memory `seenCd[id]` (the last UP's t) with `seenUnitCd[id]`. A slot whose plain `cooldownID` changes is reset as
  today, then inherits `sSeen[s], sUnit[s] = seenCd[id], seenUnitCd[id]` of its NEW cooldownID: the item moved frame, its
  evidence moves with it (Fable S5). Written at every UP sweep beside `sSeen`. A target swap zeroes `seenCd` of every
  cooldownID whose `seenUnitCd == 2` (as it resets target slots today).
- (b) Settle after a re-point: a re-pointed or re-acquired frame's dark count restarts (`sDarkN[s] = 0`), so it needs
  `DARK_SWEEPS` consecutive monitored dark sweeps before it counts (>= one poll gap, 0.2 s forced / 0.5 s unforced): the
  default "S" is the sweep cadence, not a constant. UP is counted at once (a light is real whichever frame shows it).
- (c) Continuity: `sDarkN` resets on a light, a re-point, a non-monitored sweep (hidden viewer, settling), a held sweep for
  no unit we track, a target swap (for `provenU == 2` items).
- (d) "Never close from a slot whose cooldownID changed since the cast" is NOT a rule: with identity by cooldownID a
  re-pointed frame IS the same item, and blocking it would make the verdict blind after every swap (the owner's "too
  rigid"). Proof and dark are keyed by cooldownID, so the frame change is invisible to them.
- (e) A swap inside W: the target slots reset and settle (today's §3.4), the record in memory is the other mob's
  (`applied ~= oursAp`), so no verdict for mob B from mob A's cast; after a swap back to A, A's record returns with its
  applied == oursAp, W has elapsed, and a dark item closes it `DARK_SWEEPS` sweeps after the settle: dark means dark.
- (f) Mob A's phantom while B is targeted: belief-only (the item cannot see A); it lives until the model's expiry or the
  swap back. Accepted (Fable A.4).

### 2.5 Strikes (decision 122)

A wrong verdict: a verdict close at `verdictAt[k]` followed by an UP `apply` for the same k within `STRIKE_WIN` (2.0 s)
with no new cast of ours since (`not (ours[k] == BY_CAST and oursAp[k] > verdictAt[k])`). Then `P.Strike(j, u)` (router ->
`leaf.Strike(j, u)`): every slot counted UP for (j, u) this sweep has its cooldownID struck (`strikesCd[id] += 1`); at
`STRIKES_MAX` (2) `provenCd[id] = false` and it cannot be re-proven until the next build. `verdictAt[k] = 0` after the
check or after `STRIKE_WIN`. The late UP re-opens the record as a CDM open (rule 3, `hold()`): one flip, as today for any
late light. Counters per fight: `strikeN[k]`.

### 2.6 Interaction with the rules as built

- Rule 1 (seen-rule DOWN) is unchanged and faster (next sweep); the verdict is for the case rule 1 cannot see (never lit for
  this application, or lit and dark between two sweeps).
- Rules 3-4 (hold, CDM open) unchanged. A verdict close drops `lastE/lastSt/longE` like any close (the record's expiry
  moved).
- A refresh into a lit item: `upAt` moves every UP poll; `t >= upAt + W` is false while lit; no verdict.
- Out of combat the walk wins (`apply`'s guard) and the verdict sits behind the same guard.
- Panel switch off (`def.auras[j].cdm == false`): not in `byId`, never mapped, never proven, never dark, never judged.
- `Hekili.cdmOff` (router leafless): no leaf, no `fact.pdark`, no verdict.

### 2.7 Counterexamples walked

| Case | Result |
|---|---|
| Fresh Rake dodged, item proven, dark | closes at the first poll >= cast + 1.0 s with 2 consecutive dark sweeps; the phantom lives ~1.0-1.5 s instead of 9 s |
| Fresh Rake lands, item lights at +10 ms | UP at the next sweep; `upAt` moves; `pdark` false; no verdict |
| Rip lit 323 ms late | inside W0; no verdict |
| Feral Charge effect 863 ms | inside W0 (no velocity in the pack: travel 0); a projectile pack ability gets `rMax/velocity + TOL` |
| Light > W late (lag spike) | wrong close, re-open at the light (BY_CDM), one flip, one strike; two strikes retire the item for the build |
| Item never lit (Nature's Grasp, a rank the item does not list) | unproven: no verdict; snapshot "mapped, never lit" lists it |
| Downranked cast into an item proven by the full rank | the item may stay dark: a wrong close per cast, no UP so no strike. Risk accepted and logged (no pack recommends a downrank today; the panel switch is the hatch; Task 10 check) |
| Target swap inside W | target slots reset + settle; `applied ~= oursAp` on B: no verdict; A's phantom is belief-only until swap back or expiry |
| Swap back to A | A's record loads (`applied == oursAp`), W elapsed; a dark item closes it after `DARK_SWEEPS` sweeps |
| Combat end inside W | the walk wins (guard); nothing |
| Form shift | player form auras skipped (`I.formAura`) |
| Hidden viewer / `InCombat` setting | not monitored: `sDarkN` resets, `pdark` false; no verdict (and the walk/model run) |
| Multi-dot on several mobs | current target only; per record; memory keeps the others |
| Partner overwrites our shared debuff | our item goes dark while the debuff is up: rule 1 closes (seen rule) or the verdict closes after W: one recast (owner accepted, L291/L375) |
| Miss from a lit item (refresh dodged) | UP stands; the rows decide; no verdict |
| Aura applies late (travel) | W per cast |
| Immune / fully resisted | item stays dark; verdict after W: correct (the one path that catches it, S2) |
| CC broken by our tick between two sweeps | lit and dark unseen; dark at W: closes; correct |
| Target dies inside W | TargetGone clears the record; `exp0` 0: nothing |
| Pre-pull buff of ours (BY_WALK), item proven out of combat, dispelled in combat | rule 1 closes if seen, else the verdict after W0 |
| Partner's MotW on us (walk source partner) | `ours` 0: never judged |
| Reshuffle at a swap re-points the Thorns frame | its new frame inherits `seenCd`/`provenCd` by cooldownID; evidence survives |
| Panel switch off | unmapped: nothing |
| Items that never light while the pack tracks them | listed in the snapshot; proof protects; the panel switch is the user's hatch |

## 3. Snapshot (decision 123)

- `presence-verdict <key> unit=<u> W=%.2f verdicts=%d strikes=%d pdark=<bool> darkSlots=%d` for each k with a verdict,
  strike or pdark this fight.
- `presence-proof mappedNeverLit=<keys or ->` (mapped auras with no proven cooldownID this build) and
  `presence-proof repoints=%d struck=%d` (per fight re-points seen by the leaf; cooldownIDs with proof dropped).
All counters preallocated; the snapshot allocates (debug only).

## 4. Pack audit (decision 124)

Every CDM-trackable aura's `id`/`copy` covers every rank the viewer can report (Forever's Wrath rules: each rank its own
spell ID; the item follows the current rank). Druid first, then each class; a spec test compares each class's aura rank
tables against `tools/data/cooldownviewer/<CLASS>.lua` where a fixture exists, and against the DB2 rank families where the
`wowdb` tool answers. Clearly missing ranks are added; uncertain ones are logged, not changed.

## 5. Harness and A/B

Arms (harness only; `ab.lua`): `viewer-reshuffle` (the mixed layout + a full-update reshuffle of every viewer's frames at
each target change), `viewer-nonland` (the buffs layout in a world where an avoided press applies no aura:
`auraOnAvoid = false`, phantom seconds measured), `secret-viewer-buffs` / `secret-viewer-mixed` (the secret-amount stream
crossed with the viewer), `viewer-swap` (several mobs, our target swapped every few seconds), and each of them with the
verdict off (`I.verdictOff`, set by the harness only: `*-novd`). Metric "phantom seconds" = edgestats `staleUp` (the belief
up while the viewer is dark, in combat, tracked auras) in the non-landing world. Gates: default arm IDENTICAL to
38daebe33 (`scripts/results.sh`); the four existing viewer arms: flicker within +-0.3/min, agreement no regression; the
new arms: phantom seconds fall with the verdict on, wrong verdicts (strikes) counted, no flicker rise beyond +0.3/min.

## 6. Constants and switches

`W0 = 1.0`, `TOL = 0.3`, `DARK_SWEEPS = 2`, `STRIKE_WIN = 2.0`, `STRIKES_MAX = 2`; `HOLD`, `REFRESH_LAG` unchanged.
`I.verdictOff` (Game-internal, harness-set, never a user option, not read from the environment inside Game/) turns the
verdict off for the A/B; `Hekili.cdmOff` remains the only global switch; the per-aura switch is the panel's.

## 7. Decisions

| # | Decision | Reason |
|---|---|---|
| 116 | A second signal, the proven positive dark, beside the seen rule: the leaf counts proven, monitored, continuously dark slots (`nDark`), the router sets `fact.pdark`, poll 15 closes an up record of ours after W; the seen rule, `closes()` and the reducer unchanged | L364; relaxing the seen rule would close BY_WALK/BY_CDM records at the first silent sweep (Fable M2) |
| 117 | Proof per cooldownID, set by any UP for the item's mapped aura on either unit, in or out of combat, zeroed at every build; with the last lit unit | a never-lighting item gives no UP so strikes cannot retire it: config-trust loops (L368); per-slot proof dies at each reshuffle (F-b) |
| 118 | A dark counts only after `DARK_SWEEPS` (2) consecutive monitored dark sweeps; it never makes the slot live | re-pointed frames settle by cadence, not a constant (L299 spirit); nLive/Reduce untouched |
| 119 | The verdict closes any opener of ours (`ours ~= 0`, same applied), never a record with `ours` 0 | L364 "any opener"; a partner-sourced walk record stays |
| 120 | `W = max(W0 1.0, travel + TOL 0.3)` per record, travel from the pack's velocity and the ability's rMax at the cast's write; W0 for walk/CDM openers | measured tail 0.12 s, Rip 0.32 s, Feral Charge 0.86 s; a 0.5 s W would flip the Rip cast (Fable M5) |
| 121 | Identity is the cooldownID: proof, strikes and the seen memory carry across frame re-points; a re-pointed frame restarts its dark count; no "cooldownID changed since the cast" block | Blizzard reshuffles every frame at every full update; a frame-keyed rule is blind after every swap (L375 "too rigid") |
| 122 | Strikes per cooldownID: a verdict followed by an UP within 2.0 s with no new cast = wrong; 2 strikes drop the proof for the build | caps a flaky item at one flip per cast, then silence (no-jitter rule) |
| 123 | Snapshot: verdicts, strikes, pdark, mapped-never-lit, re-points | Task 10 reads them; user reports show silent items |
| 124 | No rebuild on rank change; the pack audit covers ranks in id/copy; proof zeroes at every build | owner L375 |

## 8. Deferral candidates

| # | What | Why | Trigger |
|---|---|---|---|
| V1 | Downranked cast into a proven item: a wrong verdict per cast, never struck | no pack downranks today | a pack adds a downrank entry, or Task 10 shows it |
| V2 | Mob A's phantom while B is targeted | the item cannot see A | swap-heavy spec data |
| V3 | Shared debuff partner overwrite = one recast | owner dropped `shared` from the slice | group report |
| V4 | S1 (row before the cast event) and S2 (RESIST row shape) ticket-side items: NOT in this work | ticket side, needs P2/P6 data | P2/P6 results |
| V5 | W0/TOL/DARK_SWEEPS untuned | need P1/P3 | Task 10 |
| V6 | `I.verdictOff` harness switch left in Game/ | A/B needs it | delete after Task 10 or keep as debug like `cdmOff` (owner) |
| V7 | Travel is `rMax / velocity` with the ability's rMax as read from the client; an ability whose range was never read has rMax 0, so a projectile falls back to W0 (Tickets.lua assumes 40 yd there) | no pack ability with velocity lacks a range read today | Task 10 shows a strike on a projectile aura |
