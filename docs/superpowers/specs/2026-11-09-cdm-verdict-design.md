# The Cooldown Manager verdict: a proven item dark for W closes the record (spec amendment, 2026-11-09)

Amends `2026-11-07-cdm-default-design.md` (decisions 92-115) with decisions 116-124. Base integ/0.7 38daebe33. Written by
the Fable lead under the owner's mandate (cdm-fable-brief.md); every judgement call is in cdm-fable-decisions.md.

Amended 2026-11-10 after the Fable 5.2 review (cdm-verdict-fable52-review.md; M1, M2, M3, S1, S2): the close names the
application it judged, the dark is continuous for W, silent verdicts suspend a proof, the seen memory is not inherited, the
builds are counted. Each changed passage carries the note with its finding.

## 0. The owner's rulings this rests on

- L364: "after a certain time dark means dark; a wrong belief must not carry the full duration." For a PROVEN item (per
  cooldownID, lit before in this build) continuously dark for W (from the latest of the write, the last UP and the start
  of the watched dark; W per cast, >= 1.0 s plus travel) close the record of ANY opener (our cast, a walk read of ours, a
  CDM open), no refund; a strike counter caps wrong verdicts at 2 per item; two verdicts with no light of the item
  between them suspend its proof until it lights again; unproven items and the non-current mob after a swap stay
  belief-only; unknown never closes. ("the start of the watched dark" and the suspension: amended 2026-11-10 after the
  Fable 5.2 review, M2 and M3.)
- L366/L368: proof is required (an item that never lit gives no verdict); config-trust would loop a never-lighting item.
- L375: tolerance for frame reshuffling (proof and strikes keyed by cooldownID; a re-pointed frame settles: it starts with
  no seen memory and its dark starts over; dark is continuous across sweeps; amended 2026-11-10 after the Fable 5.2
  review, S1); shared auras are DROPPED from this slice (the viewer lights only player-cast auras: a partner overwrite costs
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
  rank's build starts unproven) is set true whenever a slot with plain `cooldownID == id` reads UP for its single
  mapped aura j while its viewer is visible, on either unit, in or out of combat (an out-of-combat light during the walk
  counts), unless the strikes retired it (§2.5). Every such light also zeroes `silentCd[id]`, so it ends a suspension
  (§2.5; amended 2026-11-10 after the Fable 5.2 review, M3). `provenU[id]` remembers the unit it last lit for (1
  player, 2 target): a dark item is dark for THAT unit (a dark item carries no `auraDataUnit`; the item's unit is what
  it was seen lighting for).
- Never per slot: a per-slot bit dies at every reshuffle.
- `strikesCd[id]` (§2.5) at `STRIKES_MAX` clears the proof for the build. `silentCd[id]` (§2.5) at `STRIKES_MAX`
  suspends it until the item's next visible light (amended 2026-11-10 after the Fable 5.2 review, M3).
- `Q.builds` counts the leaf's builds per session (never reset per fight): each build zeroes every proof, so the first
  cast per item after one is never judged; the snapshot shows how often that happens (amended 2026-11-10 after the
  Fable 5.2 review, S2; when proof is zeroed is unchanged).

### 2.2 The dark count and its start (decision 118; amended 2026-11-10 after the Fable 5.2 review, M2)

The leaf's `Q.Counts(j, u)` gains a 7th value, `nDark`: the slots that this sweep are
- configured and mapped to one aura j (`m > 0`, as for UP/NONE), and proven (`provenCd[sCd[s]]`), and
- silent (`auraInstanceID` nil, not secret), and
- monitored: their viewer visible and, for `provenU == 2`, not settling (§2.4).
A slot counts from its first such sweep, and the leaf keeps that sweep's t per slot (`sDarkT[s]`, written with the slot's
dark thing `sDk[s]` in one place, so it restarts at every point where the monitoring restarts, §2.4c). `Q.Counts` returns
an 8th value, `tDark`: the LATEST `sDarkT` among the thing's dark slots (0 none), recomputed in the sweep's reduction
like `tUp`/`tNone` (allocation-free). "Continuously dark for W" is then a time, not a number of sweeps: the thing has
been watched dark since `tDark` (§2.3 rule 4). `DARK_SWEEPS` and the per-slot sweep count are gone: two sweeps after a
swap back, a viewer shown again or a re-point was "watched for 0.2-0.4 s", while `applied` and `upAt` were old, so W
had "elapsed" before the watching began and a real dot that re-lit a moment later was closed and struck (review M2).
Counted for `k = (provenU[id] - 1) * AURA_UNIT + j` as `cDark[k]` (preallocated like `cUp`), moved in O(1) like the other
counters (it does not make the slot "live": `nLive`, `covered`, `Reduce` and the reduced state are unchanged). A slot
that also passes the seen rule is a NONE AND a dark: both counts hold; the reduced DOWN closes first (rule 1), the
verdict finds the record closed and does nothing (§2.3 keys on the record's applied time).

### 2.3 The router and the verdict (decisions 119-120)

- Router: `fact.pdark[k] = nDark > 0 and nUp == 0` and `fact.pdarkT[k] = tDark` at every reduction of thing k (no state
  change, no edge, no `fact.t`). `R.Presence` is unchanged; both are read by poll 15 only (`pdarkT`: amended 2026-11-10
  after the Fable 5.2 review, M2).
- Poll 15 (`Sources/Auras.lua`), after `apply` for the pair, under the same guards as `apply` (in combat only or the
  walk not plain; forms and enchants skipped; `I.targetSlot == I.curSlot`): the record of (j, u) is closed when ALL hold:
  1. the record is up: `U.exp0[u][j] > t`;
  2. our evidence opened this application: `ours[k] ~= 0 and oursAp[k] == U.applied[u][j]` (any opener: cast, walk read
     with source player/pet, CDM open; a record a partner's walk read opened has `ours` 0 and is never judged);
  3. the reduced state is not UP and `fact.pdark[k]` is true now;
  4. `t >= max(oursAp[k], upAt[k], fact.pdarkT[k]) + W[k]`: W elapsed since the latest of the write, the last UP read
     and the start of the watched dark (amended 2026-11-10 after the Fable 5.2 review, M2);
  5. `I.verdictOff` is not set (harness only, §6).
  The verdict runs for every pair at every poll 15, INCLUDING the poll's no-live-slot branch (`P.covered == 0`): a dark
  slot is never live, so a lone dodged aura has `covered` 0 and the verdict must not sit behind the live-slot guard
  (implementer's finding; the rule is the same, only its placement).
  Then `Direct(Obs.Read, t, k, applied, ReadOf.AuraVerdict)` once (the `staged[k]` guard): the close NAMES the
  application it judged (its `b` is the record's applied time at the poll). The fold (`Families/Auras.lua`) closes the
  record only while `U.applied[u][j]` still equals it, else drops the read (the F3 pattern of `AuraOpen`). A drain is
  Flush, polls, fold in log order, so our recast's cast event, logged before the poll staged the close, folds first:
  without the name the close took down the NEW, landed application and the light then filed a strike (review M1; W0 is
  the Cat and Rogue GCD, and "it dodged, press it again" is the normal reaction).
  A verdict is counted when its close folds, not when it is staged: the fold calls `I.AuraVerdictClosed(k, t)`
  (`Sources/Auras.lua`), which sets `verdictAt[k] = t`, `verdictN[k] += 1`, drops `lastE/lastSt/longE` (§2.6) and feeds
  the silent count (§2.5). A dropped close counts nothing and leaves no strike window: the recast is a new application
  with its own W (amended 2026-11-10 after the Fable 5.2 review, M1).
  No refund, no ticket change (brief-1 M1/N3: tickets expire on their own). The close label stays `expired`.
- W per record: `I.AuraOurs(u, j, travel)` (Families/Now.lua passes `travel = rMax / velocity` seconds for an ability
  with `A.velocity[a] > 0`, else 0); `W[k] = max(W0, travel + TOL)`, W0 = 1.0 s, TOL = 0.3 s (viewer tail 0.12 s + one
  frame + margin; tune from Task 10's P1). A walk read or a CDM open sets `W[k] = W0`.

### 2.4 Reshuffle tolerance (decision 121)

- (a) Identity is the cooldownID. Per cooldownID (preallocated at build): `provenCd`, `provenU`, `strikesCd`, `silentCd`.
  The seen rule's memory (`sSeen`, `sUnit`) stays per slot: a slot whose plain `cooldownID` changes is reset as on the
  base and starts with `sSeen, sUnit = 0, 0`. The first build let the new frame inherit a per-cooldownID seen memory
  (`seenCd`/`seenUnitCd`); that answered NONE with no settle, so one dark sweep on a re-pointed frame closed a player
  buff through rule 1 with no W (review S1). Removed: the verdict covers "lit on frame X, dark on frame Y" after W
  (amended 2026-11-10 after the Fable 5.2 review, S1).
- (b) Settle after a re-point: a re-pointed or re-acquired frame's dark starts over (`sDarkT[s]` restarts at its first
  monitored dark sweep), so the verdict needs W of watched dark on the new frame: the settle is W itself, no extra
  constant. UP is counted at once (a light is real whichever frame shows it).
- (c) Continuity: the dark's start restarts on a light, a re-point, a non-monitored sweep (hidden viewer, settling), a
  held sweep for no unit we track, a target swap (for `provenU == 2` items), `ForgetEdges` (the viewer's data reloaded)
  and activation ((b), (c): amended 2026-11-10 after the Fable 5.2 review, M2).
- (d) "Never close from a slot whose cooldownID changed since the cast" is NOT a rule: with identity by cooldownID a
  re-pointed frame IS the same item, and blocking it would make the verdict blind after every swap (the owner's "too
  rigid"). Proof and dark are keyed by cooldownID, so the frame change is invisible to them.
- (e) A swap inside W: the target slots reset and settle (today's §3.4), the record in memory is the other mob's
  (`applied ~= oursAp`), so no verdict for mob B from mob A's cast; after a swap back to A, A's record returns with its
  applied == oursAp, and a dark item closes it W after the first monitored dark sweep that follows the settle: the item
  must be watched dark on A for W before dark means dark (amended 2026-11-10 after the Fable 5.2 review, M2).
- (f) Mob A's phantom while B is targeted: belief-only (the item cannot see A); it lives until the model's expiry or the
  swap back. Accepted (Fable A.4).

### 2.5 Strikes (decision 122)

A wrong verdict: a verdict close at `verdictAt[k]` followed by an UP `apply` for the same k within `STRIKE_WIN` (2.0 s)
with no new cast of ours since (`not (ours[k] == BY_CAST and oursAp[k] >= verdictAt[k])`; `>=`, amended 2026-11-10: a
recast stamped at the verdict's own time is a new cast, the judged application being at least W older; gate arm
viewer-recast, Feral seed 3). Then `P.Strike(j, u)` (router ->
`leaf.Strike(j, u)`): every slot counted UP for (j, u) this sweep has its cooldownID struck (`strikesCd[id] += 1`); at
`STRIKES_MAX` (2) `provenCd[id] = false` and it cannot be re-proven until the next build. `verdictAt[k] = 0` after the
check or after `STRIKE_WIN`. The late UP re-opens the record as a CDM open (rule 3, `hold()`): one flip, as today for any
late light. Counters per fight: `strikeN[k]`.

Silent verdicts (amended 2026-11-10 after the Fable 5.2 review, M3). A strike needs a light, so a proven item that is
silent for some applications (a rank or variant ID it does not follow, an ID the audit adds to `copy`, F12 silence) gave
a wrong close on every cast and never a strike: the recast loop config-trust was rejected for (L368). Per cooldownID
(`silentCd[id]`, preallocated at build like `strikesCd`) the leaf counts the verdict closes of things the item was dark
for since its last visible light: when a verdict's close folds, `P.Silent(j, u)` (router -> `leaf.Silent(j, u)`) raises
the count of every slot counted dark for (j, u). At `STRIKES_MAX` (2) the proof is SUSPENDED (`provenCd[id] = false`,
`Q.suspended += 1`): no dark, no verdict from the item, the aura belief-only. ANY later visible light of the item
re-proves it and zeroes the count (§2.1); strike retirement is unchanged (for the build). The loop is bounded at two
casts and heals itself; against a truly immune mob Hekili stops asking for the aura a third time. Like a strike, an
item with two dark frames is counted once per frame (conservative: it suspends sooner). The cost: CORRECT verdicts feed the
count too, so two genuinely avoided or immune casts with no light between them suspend the proof and a third such
phantom lives its modelled duration (today's behaviour) until the item next lights. A dropped close (§2.3) counts
nothing.

### 2.6 Interaction with the rules as built

- Rule 1 (seen-rule DOWN) is unchanged and faster (next sweep); the verdict is for the case rule 1 cannot see (never lit for
  this application, or lit and dark between two sweeps).
- Rules 3-4 (hold, CDM open) unchanged. A verdict close drops `lastE/lastSt/longE` like any close (the record's expiry
  moved): `I.AuraVerdictClosed` zeroes them when the close folds. As first built only the next non-UP poll dropped
  them, so a late light at the very next poll was debounced against the old expiry and the record stayed down
  (amended 2026-11-10 after the Fable 5.2 review, Nice).
- A refresh into a lit item: `upAt` moves every UP poll; `t >= upAt + W` is false while lit; no verdict.
- Out of combat the walk wins (`apply`'s guard) and the verdict sits behind the same guard.
- Panel switch off (`def.auras[j].cdm == false`): not in `byId`, never mapped, never proven, never dark, never judged.
- `Hekili.cdmOff` (router leafless): no leaf, no `fact.pdark`, no verdict.

### 2.7 Counterexamples walked

| Case | Result |
|---|---|
| Fresh Rake dodged, item proven, dark | closes at the first poll >= cast + 1.0 s (the item watched dark since before the cast); the phantom lives ~1.0-1.5 s instead of 9 s |
| Rake dodged, re-pressed at the GCD, the recast's drain is the first poll >= W (amended 2026-11-10, M1) | the poll stages the close of the OLD application; the fold writes the recast first and drops the close (its applied differs): the recast stands with its own expiry, `ours` BY_CAST, no verdict counted, no strike |
| Fresh Rake lands, item lights at +10 ms | UP at the next sweep; `upAt` moves; `pdark` false; no verdict |
| Rip lit 323 ms late | inside W0; no verdict |
| Feral Charge effect 863 ms | inside W0 (no velocity in the pack: travel 0); a projectile pack ability gets `rMax/velocity + TOL` |
| Light > W late (lag spike) | wrong close, re-open at the light (BY_CDM) with a full duration from the light (too long by the lag), one flip, one strike; two strikes retire the item for the build |
| Item never lit (Nature's Grasp, a rank the item does not list) | unproven: no verdict; snapshot "mapped, never lit" lists it |
| A cast the proven item stays silent for (a downrank, a variant ID, F12 silence) (amended 2026-11-10, M3) | a wrong close after W, no UP so no strike; the second such verdict with no light between suspends the item's proof: belief-only from the third cast until the item lights again, then judged as before |
| Target swap inside W | target slots reset + settle; `applied ~= oursAp` on B: no verdict; A's phantom is belief-only until swap back or expiry |
| Swap back to A (amended 2026-11-10, M2) | A's record loads (`applied == oursAp`); the item is watched dark from the first sweep after the settle: a real dot that re-lights within W is never closed; a truly dark one closes W after that sweep |
| Combat end inside W | the walk wins (guard); nothing |
| Form shift | player form auras skipped (`I.formAura`) |
| Hidden viewer / `InCombat` setting | not monitored: the dark's start resets, `pdark` false; no verdict (and the walk/model run) |
| A viewer shown again mid-fight (amended 2026-11-10, M2) | watched dark from its first visible sweep: W from there, whatever the age of the cast |
| Multi-dot on several mobs | current target only; per record; memory keeps the others. `ours`/`oursAp` are per unit key, so after a cast on mob B, mob A's record is not judged again on a swap back (safe: belief-only) |
| Partner overwrites our shared debuff | our item goes dark while the debuff is up: rule 1 closes (seen rule) or the verdict closes after W: one recast (owner accepted, L291/L375) |
| Miss from a lit item (refresh dodged) | UP stands; the rows decide; no verdict |
| Aura applies late (travel) | W per cast |
| Immune / fully resisted | item stays dark; verdict after W: correct (the one path that catches it, S2); after two with no light the proof is suspended, so a third cast into the immune mob is belief-only (M3) |
| CC broken by our tick between two sweeps | lit and dark unseen; dark at W: closes; correct |
| Target dies inside W | TargetGone clears the record; `exp0` 0: nothing |
| Pre-pull buff of ours (BY_WALK), item proven out of combat, dispelled in combat | rule 1 closes if seen, else the verdict after W0 |
| Partner's MotW on us (walk source partner) | `ours` 0: never judged |
| Reshuffle at a swap re-points the Thorns frame (amended 2026-11-10, S1) | proof and strikes are the cooldownID's and survive; the new frame has no seen memory, so its first dark sweep closes nothing; a light counts at once; dark for W on the new frame closes by the verdict |
| Panel switch off | unmapped: nothing |
| Items that never light while the pack tracks them | listed in the snapshot; proof protects; the panel switch is the user's hatch |

## 3. Snapshot (decision 123)

- `presence-verdict <key> unit=<u> W=%.2f verdicts=%d strikes=%d pdark=<bool> darkSlots=%d` for each k with a verdict,
  strike or pdark this fight.
- `presence-proof mappedNeverLit=<keys or ->` (mapped auras none of whose cooldownIDs lit this build; an item that lit
  and was struck or suspended is not listed) and `presence-proof repoints=%d struck=%d suspended=%d builds=%d` (per
  fight re-points seen by the leaf; per build the cooldownIDs whose proof the strikes dropped and the times silent
  verdicts suspended a proof; per session the leaf's builds, never reset per fight). `verdicts=%d` counts closes that
  folded (amended 2026-11-10 after the Fable 5.2 review, M1/M3/S2).
All counters preallocated; the snapshot allocates (debug only).

## 4. Pack audit (decision 124)

Every CDM-trackable aura's `id`/`copy` covers every rank the viewer can report (Forever's Wrath rules: each rank its own
spell ID; the item follows the current rank). Druid first, then each class; a spec test compares each class's aura rank
tables against `tools/data/cooldownviewer/<CLASS>.lua` where a fixture exists, and against the DB2 rank families where the
`wowdb` tool answers. Clearly missing ranks are added; uncertain ones are logged, not changed.

## 5. Harness and A/B (amended 2026-11-10 after the Fable 5.2 review, M4/S6, and the batch review)

Arms (harness only; `ab.lua`), each with a verdict-off twin (`I.verdictOff`, set by the harness only: `*-novd`, same
seeds):
- `viewer-reshuffle`: the mixed layout + a full-update reshuffle of every viewer's frames at each target change.
- `viewer-nonland`: the buffs layout in a world with raised avoid rates (an avoided press applies no aura).
- `secret-viewer-buffs` / `secret-viewer-mixed`: the secret-amount stream crossed with the viewer.
- `viewer-swap`: several mobs, our target swapped every few seconds (a swap re-lists the fake client's target auras).
- `viewer-late`: a seeded share of lights arrives 1.2-1.8 s late (later than W): strikes and the flicker of wrong
  verdicts are exercised.
- `viewer-recast`: the non-landing world where an avoided aura press is pressed again at the next free GCD (the recast
  in or beside the verdict's drain: M1, and the `>=` tie).
- `viewer-swap-dark`: `viewer-swap` with a non-atomic reshuffle (a moved lit frame reads dark until the next flush).

Metric "phantom seconds" = edgestats `staleUp` (the belief up while the viewer is dark, in combat, tracked auras),
WITHOUT form and enchant auras (the leaf never judges them), reported player/target.

Running: `make gate-ab-body` on the head (the default arm's body, then every arm of `AB_ARMS`, logs and rows in `.ab/`;
no check-full per arm); on the base the six arms it knows. Comparing: `scripts/results.sh` on the two `default.log`
(IDENTICAL), then `scripts/ab_delta.sh <base .ab> <head .ab>`: per arm base -> head, and per verdict arm its `-novd`
twin -> on. It exits 1 on a flicker rise beyond +0.3/min, an agreement fall, or a spec or arm the head lacks.

Acceptance: default arm IDENTICAL to 38daebe33; the existing viewer arms within +-0.3/min flicker and no agreement
fall against the base; per verdict arm and spec, "verdicts > 0 with the verdict on" is a PRECONDITION (`ab_delta` prints
"vacuous" otherwise: no claim is made for that spec); where it holds, target phantom seconds fall against the twin and
flicker stays within +0.3/min; `viewer-late`: strikes > 0 and at most `STRIKES_MAX` per item; `viewer-recast`: strikes 0
on our own recasts; `viewer-swap` / `viewer-swap-dark`: no strike, no flicker rise.

## 6. Constants and switches

`W0 = 1.0`, `TOL = 0.3`, `STRIKE_WIN = 2.0`, `STRIKES_MAX = 2` (strikes per build, and silent verdicts since the item's
last light); `HOLD`, `REFRESH_LAG` unchanged. `DARK_SWEEPS` is gone (amended 2026-11-10 after the Fable 5.2 review, M2:
continuity is W of watched dark). `ReadOf.AuraVerdict = 14` is the verdict's read kind (M1).
`I.verdictOff` (Game-internal, harness-set, never a user option, not read from the environment inside Game/) turns the
verdict off for the A/B; `Hekili.cdmOff` remains the only global switch; the per-aura switch is the panel's.

## 7. Decisions

| # | Decision | Reason |
|---|---|---|
| 116 | A second signal, the proven positive dark, beside the seen rule: the leaf counts proven, monitored, continuously dark slots (`nDark`), the router sets `fact.pdark`, poll 15 closes an up record of ours after W; the seen rule, `closes()` and the reducer unchanged | L364; relaxing the seen rule would close BY_WALK/BY_CDM records at the first silent sweep (Fable M2) |
| 117 | Proof per cooldownID, set by any UP for the item's mapped aura on either unit, in or out of combat, zeroed at every build; with the last lit unit | a never-lighting item gives no UP so strikes cannot retire it: config-trust loops (L368); per-slot proof dies at each reshuffle (F-b) |
| 118 | (amended 2026-11-10 after the Fable 5.2 review, M2) A dark counts from its first monitored dark sweep and carries that sweep's t; the thing's start is the latest among its dark slots (`tDark`, `fact.pdarkT`), and the verdict needs W past it; it never makes the slot live. Replaces "`DARK_SWEEPS` (2) consecutive sweeps" | the owner's rule is CONTINUOUSLY dark for W (L364): two sweeps after a swap back or a re-shown viewer closed a real dot whose light came a moment later; nLive/Reduce untouched |
| 119 | The verdict closes any opener of ours (`ours ~= 0`, same applied), never a record with `ours` 0 | L364 "any opener"; a partner-sourced walk record stays |
| 120 | `W = max(W0 1.0, travel + TOL 0.3)` per record, travel from the pack's velocity and the ability's rMax at the cast's write; W0 for walk/CDM openers | measured tail 0.12 s, Rip 0.32 s, Feral Charge 0.86 s; a 0.5 s W would flip the Rip cast (Fable M5) |
| 121 | Identity is the cooldownID: proof, strikes and the silent count carry across frame re-points; a re-pointed frame restarts its dark and starts with NO seen memory (amended 2026-11-10 after the Fable 5.2 review, S1: the inherited seen memory answered NONE with no settle); no "cooldownID changed since the cast" block | Blizzard reshuffles every frame at every full update; a frame-keyed rule is blind after every swap (L375 "too rigid"); the verdict covers the re-pointed dark after W |
| 122 | Strikes per cooldownID: a verdict followed by an UP within 2.0 s with no new cast = wrong; 2 strikes drop the proof for the build. (amended 2026-11-10 after the Fable 5.2 review, M1/M3) A verdict is one whose close folded: the close names its application and a recast folded first drops it, uncounted. Silent verdicts per cooldownID: 2 since the item's last light suspend the proof until it lights again | caps a flaky item at one flip per cast, then silence (no-jitter rule); a strike needs a light, so only the silent count bounds an item that never lights for some casts |
| 123 | Snapshot: verdicts, strikes, pdark, mapped-never-lit, re-points, struck, suspended, builds per session (amended 2026-11-10) | Task 10 reads them; user reports show silent items |
| 124 | No rebuild on rank change; the pack audit covers ranks in id/copy; proof zeroes at every build | owner L375 |

## 8. Deferral candidates

| # | What | Why | Trigger |
|---|---|---|---|
| V1 | (amended 2026-11-10 after the Fable 5.2 review, M3: bounded) A cast a proven item stays silent for: two wrong verdicts, then the proof is suspended until the item lights | bounded at two casts, self-healing; an item that lights for one rank and never for another alternates between two wrong closes and belief-only | a `suspended` count > 0 in a Task 10 snapshot names the item: fix its pack IDs or switch it off |
| V2 | Mob A's phantom while B is targeted | the item cannot see A | swap-heavy spec data |
| V3 | Shared debuff partner overwrite = one recast (two with a partner's stronger copy, then the suspension, M3) | owner dropped `shared` from the slice | group report |
| V4 | S1 (row before the cast event) and S2 (RESIST row shape) ticket-side items: NOT in this work | ticket side, needs P2/P6 data | P2/P6 results |
| V5 | W0/TOL untuned (`DARK_SWEEPS` is gone, M2) | need P1/P3 | Task 10 |
| V6 | `I.verdictOff` harness switch left in Game/ | A/B needs it | delete after Task 10 or keep as debug like `cdmOff` (owner) |
| V7 | Travel is `rMax / velocity` with the ability's rMax as read from the client; an ability whose range was never read has rMax 0, so a projectile falls back to W0 (Tickets.lua assumes 40 yd there) | no pack ability with velocity lacks a range read today | Task 10 shows a strike on a projectile aura |
| V8 | Rule 1's close (`closes()`, a `Read` with b 0) has M1's fold-order hole: a recast folded first in the drain of a seen-rule DOWN is closed (amended 2026-11-10 after the Fable 5.2 review: found, not fixed here) | older code, rarer trigger (needs a NONE: the item lit this application, then dark, and the recast in that drain) | next belief lane touching `closes()`: stage it with the verdict's kind (the judged applied time) |
| V9 | Proof dies at every build; builds may be frequent (`COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`, a panel switch) | needs the in-game build count | Task 10 shows `builds` rising within a session's fights: carry proof across a rebuild for a cooldownID whose mapping is unchanged |
| V10 | A cooldownID shown on two frames at once is struck or counted silent once per frame | the client keeps one frame per cooldownID; conservative (suspends or retires sooner) | a snapshot shows `struck`/`suspended` after a single wrong verdict |
