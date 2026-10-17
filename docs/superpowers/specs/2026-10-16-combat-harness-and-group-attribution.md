# Combat harness and group-fidelity attribution (design, 2026-10-16)

Status: built on forever-group (2026-10-16); where the text and the code differ, "As built" (§9) rules. Base: forever 6dd6d6c2. Paths under `src/Hekili/` unless they start with `tests/`, `tools/`
or `docs/`. Inputs: `docs/research/2026-10-16-swing-outcome-pairing.md` (logs 1-2, "P"), the party log 3 and its
reading (`tmp/group/log3-group.md`, "G"), `docs/research/2026-10-16-unit-combat-event.md` ("U"), `Virtual/Events/Rows.lua`
and `Attackers.lua` as merged at 08def3ae, `Virtual/State/Sources/Swing.lua`, `Families/Resources.lua`, the replay
fixture `tests/Virtual/Events/pairing_replay_spec.lua`, the fakes under `tests/Virtual/State/helpers/`, the event-facade
spec §2.4 and §4, the core leakage audit (boundary rule). Constants are tagged MEASURED (log rows), PROTOTYPE (the
§1.6 replay of a throwaway Python model, `tmp/group/proto/`, not shipped) or UNMEASURED.

**Boundary, binding for every section.** Everything here is core: `Virtual/**` and `tests/Virtual/**`. No class,
spell, aura, form or rotation name; the harness names source profiles by shape (`melee`, `caster`, `ranged`, `pet`),
never by class. The one class-shaped fact the model uses is the declared `onNextSwing` field.

## 0. Is swing-to-outcome correlation still needed?

Not for rage. Solo, classifying each white (school 1) wound on the target by amount into a hand and staging that
hand's landed swing (`Swing` c = 1) pays rage as well as pairing does: all 69 white wounds of log 2 fall in their
hand's exact `UnitDamage` range (crits halved), and Rend ticks (13) and procs fall outside both. The avoid case does not
matter for rage at all: an avoid pays nothing, paired or not (c = 4 pays nothing; c = 1 is staged only for a wound).

It earns its place for three things only, and the design keeps exactly what they need:
1. **Yellow exclusion.** A yellow strike's own wound can sit inside a weapon range (log 1's 77 and 84 are outside,
   but Overpower-sized damage is not). That needs the *cast* correlation (our success claims a wound of its own frame)
   and the on-next-swing frame rule; not the swing's.
2. **Hand tie-break when ranges overlap.** Loose ranges overlap (main [21.6, 55] and off [14.4, 35.2] in log 2), a
   crit is halved, glancing and BLOCK_REDUCED open the range down to 0, and an armoured target pushes main-hand hits
   down into the off-hand's range. Which hand has a swing pending, and how far along its lag, breaks the tie.
3. **Group rejection by timing.** UNIT_COMBAT on our target reports every player's outcomes with plain amounts (G fact
   1). Without a pending swing of ours in its lag band, a party member's in-range white hit would pay us rage.

So the pending-swing buffer stays (it already exists: 8 slots), and the per-hand windows become per-hand lag
*densities*. Amount stays the hand classifier; timing becomes the evidence that it is ours. The hit-rate EMA and the
back-dated swing rows keep reading `PLAYER_SWING` as today.

## 1. Attribution model (Virtual/Events/Rows.lua)

### 1.1 Facts the constants rest on (MEASURED)
| Fact | Value | Source |
|---|---|---|
| Main-hand lag, outcome after its `PLAYER_SWING` | median 474 ms; 435-552 in 31 of 34; outliers 134, 869, 1237, 1287 | P log 2 |
| Main-hand lag in the party log | 369 ms (165116 -> 165485) | G |
| Off-hand lag | median 953 ms; 694-1070 in 22 of 31; up to 1686; SD of the core 0.20 s | P log 2 (SD recomputed) |
| Off-hand lag, log 1 | 754, 704, 1002, 691 ms | P log 1 |
| Avoid rate of our swings | 16 avoids / 71 swings = 0.22 (10 MISS, 3 DODGE, 3 PARRY) | P log 2 |
| Avoids in the same ms as a swing event | 3 of 16 (log 2), 1 (log 1); in two of them the coincident hand's real wound came 353-437 ms later | P logs 1-2 |
| Crit share of white wounds | 8 / 69 | P log 2 |
| Amount: our white wounds vs `UnitDamage` | 69 / 69 inside the exact range (crit halved); effective armour reduction about 0 at level 22 (INFERRED: the amounts fill the range) | P log 2 |
| Others' outcomes on our target | plain amount and school; their glancing (1-5), misses, dodges, parries, spells (school 8) | G facts 1-2 |
| Someone else's on-next-swing strike | WOUND 0 then the damage, 1 ms apart, no cast success of ours | G 177249/177250 |
| Others' cast successes | spellID and castGUID secret | G 49873 |
| Avoids carry a school | `MISS 0 1`: school 1 on every avoid row of logs 1-2 | P (corrects "school absent") |
| Off-hand landing, two references (G5, 20 off-hand wounds) | 11 at 691-707 ms after its own off swing; 7 at 1686-1687 ms after the previous MAIN swing (one more at 1755); 1 in the main hit's frame (swings 250 ms apart) | G5 (`tmp/pairing/g5-analysis.md`, log5.txt) |
| Main-hand lag, G5 | 436-556 in 17 of 22 (median 453); 157, 167, 371 short; 736, 805 long | G5 (seeds unchanged) |
| An on-swing racial proc (Undead, Touch of the Grave) | `UNIT_COMBAT target WOUND 36 32` (school 32) and `UNIT_COMBAT player HEAL 36 1` in the same ms, 1-2 ms after a `PLAYER_SWING` (fires on the swing event, not the landing); no `UNIT_SPELLCAST_SUCCEEDED`; 2 in 88 s | G5 (37174, 68467) |

**Off-hand landing (RULED, 2026-10-16, after G5).** The off hand's "wide" lag of log 2 is two narrow modes: its
hit lands about 0.70 s after its own swing event, or, when the main hand's timing pushes it, about 1.69 s after the
previous main-hand swing event (log 2: 9 of 33 at 702-704 ms and 21 of 33 at 1686-1702 ms after the main swing;
log 1's 704 and 691; G5's table row above). Rarely it lands in the main hit's frame. The off hand is scored against
both references and takes the better (§1.2); the single wide off-hand density is dropped.

### 1.2 Actions and predictions
A pending action is a slot in today's buffer (`N = 8`, `actT/actKind/actX/actDst/actW`). Each predicts its outcome:
- **Swing of hand h:** school 1; amount class against hand h's cached range (§1.3); lag density
  `f(d) = (1 - eps) * Normal(d; med, spr) + eps / W_h` on `0 <= d <= W_h`, else 0. `W_h` is the support (today's
  `PAIR_WINDOW_MS`, 1.5 / 2.0 s, capped at the hand's period: the next swing of that hand comes first). The main hand
  has one reference, its own swing. The off hand has two: `d_own` from its own swing and `d_main` from the latest main
  swing at or before its own (kept per pending off swing at hold time: `actRef`, zero allocation); its density is
  `max(f_own(d_own), f_main(d_main))`, each a narrow normal, plus the shared tail (which covers the main-frame case).
- **Our cast:** unchanged and not scored: a wound within `SAME_FRAME` (0.05 s) of our success is the cast's, an avoid
  within `CAST_WINDOW` (0.2 s) is the cast's. It claims first, before any swing is scored.

| Constant | Main (own ref) | Off, own ref | Off, main ref | Kind |
|---|---|---|---|---|
| `med` seed | 0.474 s | 0.703 s | 1.686 s | MEASURED (logs 2, G5), learned online (§1.5) |
| `spr` seed | 0.060 s | 0.020 s | 0.020 s | MEASURED (brief's +-60; G5's 691-707 and 1686-1687 clusters), learned online |
| `eps` tail weight | 0.12 | 0.10 (shared) | | MEASURED (log 2 4/34; G5 2/20: 1755 and the main-frame hit), constant |
| `W_h` (from its own swing) | 1.5 s | 2.0 s | | MEASURED max lags 1287/1686 plus margin, constant |
| `q_avoid` | 0.22 | 0.22 | | MEASURED, constant |

### 1.3 Outcome classes
- **White wound** (WOUND, amount > 0, school 1): for each hand, a class `c` from today's `fits` plus one band:
  exact [min, max] (q = 0.90), loose [0.6 min, 1.1 max] (q = 0.08), **above** (1.1 max, 2 max] (q = 0.02), else not a
  candidate. CRITICAL halves the amount; GLANCING and BLOCK_REDUCED open the range from 0. The q values are UNMEASURED
  except that log 2 put 69 of 69 in "exact"; they are a smoothed prior. "Above" replaces the N = 3 stale fallback: a
  damage buff after the out-of-combat read (Battle-Shout-sized: about +9 on a 2.2 s weapon at 22, INFERRED) produces
  "above" wounds that solo still beat background when their timing is in the core band, and in a group do not.
- **Avoid** (MISS, DODGE, PARRY, BLOCK, DEFLECT, EVADE; amount 0, school 1): no amount term, `q = q_avoid`; timing
  alone decides. A non-physical avoid (a resisted spell: school != 1) is never a swing's.
- **Not a candidate:** any wound with school != 1 (a party caster's spell, a weapon proc, an on-swing racial proc:
  G5's school-32 WOUND 36 in the swing event's frame, with a HEAL on us), a WOUND 0, and a wound
  in a **foreign strike frame**: within `SAME_FRAME` after a WOUND 0 when no `onNextSwing` success of ours arrived
  within `SAME_FRAME` of that WOUND 0 (G's Maul frame; our own strike frame keeps today's handling in either order).
- **Amount unknown** (no `UnitDamage` read yet, or `GetShapeshiftForm` differs from the form of the read): every hand
  takes q = 1 and the background class is "white, any amount"; timing and school decide. This is today's form check,
  kept because a form changes the weapon damage the cache holds (Druid bear: G's 36-40 vs the caster's weapon) and the
  cache cannot be re-read in combat. The out-of-combat refresh (`UnitDamage` on combat end, equipment and attack-speed
  events) is kept because it is the only source of the ranges.

### 1.4 Score and decision
An arriving target outcome (token `target` only, which dedupes the other tokens as today) is scored against every
pending swing it can be a candidate for: `LR = q_class * f_h(d) / lambda_class`, where `lambda_class` is the learned
**background rate** of that class (outcomes per second that fit no action of ours).
- **Background estimate (quiet windows).** An outcome that arrives while *no* own action is pending is background by
  construction (our outcomes always have their action pending until credited). Counted per class: `bg[h][c]` for a
  white wound (it counts in every hand's class it qualifies for), `bg.avoid`, `bg.unknown`; quiet time accrues while
  nothing is pending, in combat only. `lambda = (count + LAMBDA0 * T0) / (quiet + T0)`; count and quiet decay by
  `exp(-dt / TAU)` each tick. Others' rhythms are independent of ours, so the quiet-window rate is unbiased inside our
  windows. `LAMBDA0 = 0.01/s`, `T0 = 5 s`, `TAU = 10 s` (PROTOTYPE).
- **Decision.** The outcome is credited to the pending swing with the highest LR when that LR >= `THETA = 4`
  (PROTOTYPE); otherwise it is background (no row; counted). One action per outcome, one outcome per action.
- **Rejection bias.** A missed own hit costs one swing's rage until the next pin (rage reads `lo`, so it lags: a
  delayed spender). A false credit lifts `lo` above the real rage and can recommend a spender the client refuses.
  Hence THETA above 1, the "above" class at q = 0.02, and no fallback that credits without timing.
- **Provisional avoids.** An avoid credited to a swing does not close it: the swing keeps the avoid's LR and kind. A
  later wound that scores that swing with a higher LR takes it (the avoid becomes background); otherwise, when the
  window closes, the swing emits `SWING_MISSED` (back-dated to the swing) instead of today's `SWING_DAMAGE` 0. Rage is
  untouched either way. This removes log 2's four orphan wounds (an avoid took the other hand's swing) and costs the
  avoid row a delay of up to `W_h`, the same delay an unpaired swing's row has today (decision D3).
- **Same-ms avoids** (log 2: 3 of 16) sit at lag 0, in both hands' tails: LR < THETA solo, so they become background.
  Two of the four have their hand's real wound 353-437 ms later, so they were probably not that swing's (UNMEASURED
  whose); if one was ours, only the dodge row is lost.

What happens to the rows and staging is unchanged: a credited wound emits `SWING_DAMAGE` at the swing's time and stages
`Swing` c = 1 (and c = 3 for a crit); a credited cast outcome emits `SPELL_DAMAGE`/`SPELL_MISSED`.

### 1.5 Learned online vs constant; allocation
- **Learned:** `med` and `spr` per reference (main; off own; off main-ref: credited to the reference that scored), from credits that are exact-class, inside 3 `spr_h` of `med_h`, and
  unambiguous (the runner-up LR below THETA): `med += 0.005 * sign(d - med)` (a running median), `spr += 0.05 *
  (1.2533 * |d - med| - spr)` (mean absolute deviation to SD), `spr` clamped to [0.02, 0.4] s, `med` to [0, W_h]. They
  persist across pulls and reset to the seeds at load. The background counts and quiet time (8 numbers) persist across
  pulls and decay only with combat time (decision D6).
- **Constant:** `eps_h`, `W_h`, the q values, `q_avoid`, THETA, LAMBDA0, T0, TAU, `SAME_FRAME`, `CAST_WINDOW`.
- **Dropped:** the N = 3 no-fit fallback (`STALE_AFTER`, `misses`): it credited G's glancing 1-5 and the hits that
  followed (G failure mode c). "Avoid -> oldest pending swing" (mode a) and "best amount, else oldest" (mode b) give way
  to the score.
- **Zero allocation:** two more per-slot arrays (`actLR`, `actAvoid`: the avoid's LR and its event string, an interned
  constant), `med[2]`, `spr[2]`, `bg[8]`, `quiet`, `lastW0`; scoring is a scalar loop over 8 slots with `math.exp`.
  `alloc_spec` and the harness assert 0 bytes.
- **Snapshot line:** `rows credited main=%d off=%d cast=%d background=%d avoidsBack=%d lag main=%.0f/%.0f off=%.0f/%.0f
  lambda exact=%.2f/%.2f avoid=%.2f` (ms; per second).

### 1.6 Prototype check (PROTOTYPE, not a measurement)
The model above (per-hand-class background, provisional avoids, the frame rule) replayed in Python on log 2: main 36 of
36 and off 33 of 33 wounds credited to the right hand, 0 false; THETA 2-8 and LAMBDA0 0.002-0.02 all give that. The
replay spec's floors (34/36, 31/33) hold with margin. The same replay with one synthetic party melee on the target
(white every 2.5 s, 36-40 inside our main exact range, 8% miss, 5% dodge, a WOUND-0 strike frame on 40% of swings;
50 seeds, about 117 s each) at THETA 4: main 28.9/36, off 32.7/33, about 3.0 false credits per fight (2.5 at THETA 8,
3.7 at 2). The same member with amounts inside our *off* range: off 15/33 and 5.1 false: the off hand's wide band is
the weak spot. These off-hand numbers predate the two-reference ruling (§1.1), whose bands are about 20 ms wide, not
1 s; the harness re-measures them. False credits inside our core band are the floor of mode b: an in-range foreign hit that
lands in our band is indistinguishable without a source. The harness (§3) replaces these numbers.

**Owns.** `Virtual/Events/Rows.lua` (the model, the snapshot line); nothing in State; `pairing_replay_spec.lua` keeps
its frame-by-frame cases (the N = 3 case becomes the "above" case; new cases in §6).

## 2. Usability oracle: retraction and recovery

The client answers `IsSpellUsable` plainly in combat (TDF gate spike: readable in combat), and its "short of power"
answer is the only truth about rage we get in combat. A credited white hit predicts some of those answers, so the
next answer judges the credit. Placement: the verdict is taken in `Families/Resources.lua` (it owns the ladder and
`Obs.Usable`); the credit records, the retraction and the rescue live in `Events/Rows.lua`, which registers
`I.CreditVerdict(id, ok, t)` and `I.Rescue(r, need, since, t)` at load (Events already stage State observations; this
is the one call back, a registered hook as `I.OnSnapshot` is).

### 2.1 Prediction
A credit stages `Swing` c = 1 with `b` = its record id (1..8; today `b` is 0). Resources pays it as today and stores,
per record, the deltas it added (`dEst`, `dLo`, `dHi`; `g` = `dEst`) and the pre-credit `e`, `lo`. For every tracked
spender `a` of that slot with cost `c` (not multi-cost, slot not readable) and `e < c <= e + g`, the credit
**predicts** a flip to usable. The record keeps the cheapest such ability (one judge per credit) and whether the
prediction is **firm**: the post-credit floor says usable (`lo + dLo >= c`). A credit crossing no rung is not judged.

### 2.2 The verdict (the first usability report after the outcome)
The first `Obs.Usable` answer for the judged ability arriving `ORACLE_MIN = 0.1 s` to `ORACLE_MAX = 0.6 s` after the
outcome (the event `SPELL_UPDATE_USABLE` or the drain's poll 2, 0.2 s in combat) is the oracle. Both bounds are
UNMEASURED: the delay from a target WOUND to the client's power update is captured by G7 (§5). No verdict if one of
our casts spent from the slot in between, or the answer is secret or NOT (no rung).
- **Usable:** confirmed; a positive label (§2.5).
- **Short, firm prediction:** the hit was not ours (the floor said usable, and only a wrong credit can break a floor).
  Retract: `est -= dEst`, `lo -= dLo`, `hi -= dHi`, each clamped at 0; `R.gain -= g`; the hit-rate EMA takes back its
  `HIT_ALPHA` step. Then Rows: the swing returns to pending (its slot re-held at its own time, hand and destination)
  if `now - t_swing <= W_h`, else it is closed as `SWING_MISSED` (missType `MISS`, back-dated to the swing). The
  `SWING_DAMAGE` row already delivered cannot be withdrawn: Hekili sees two rows for that swing (the swing timer reads
  the same time; a `MISS` opens no dodge window). The wound goes to the dropped buffer (§2.3) as background, and a
  negative label is recorded against its class.
- **Short, soft prediction** (only `est` crossed): the error may predate the credit (an estimate already high), so no
  retraction: a negative label at half weight, and the ladder clamp corrects the estimate as today.

### 2.3 Recovery (the inverse)
Rows keeps the wounds it dropped in a fixed ring (`DROP = 8`: time, amount, flag, hand candidate, its swing's time and
slot, LR), each for one window (`W_off`, 2.0 s). On a flip SHORT -> usable at cost `c` that the slot's modelled gains
since the short report do not explain (`R.gain - shortGain < c - shortEst`; `R.gain` already carries every modelled
gain: credited swings, aura ticks, hits taken (Protection's `taken`), a cast's `gain`), Resources calls `I.Rescue`:
the dropped wound with the best LR whose swing is still unclaimed (pending, or closed unpaired) and whose step
explains the gap is credited now: `Swing` c = 1 at its swing's time (and c = 3 for a crit), its row emitted if the
swing is still pending (else rage only, counted `rescuedLate`), a positive label. Then the existing flip branch pins as
today. No candidate: today's behaviour (the swing-paid pin `[c, c + step)`).

### 2.4 Only threshold-crossing credits are judged
A credit that crosses no rung changes no answer the client gives, so there is nothing to judge it with, and nothing to
judge it for: until a rung is crossed, recommendations cannot change because of it. The rungs are dense (a swing-paid
slot's tracked spenders cost every 5-10 units below the top cost, and a white step is of that size, so most credits
below the top cost cross one). A non-crossing false credit leaves the estimate inside the same rung interval, and the
next report on either side (the next crossing, or the next spend's short answer) pins it through the ladder. Above the
top cost every spender is usable either way, and the first short answer after a spend corrects the estimate.

### 2.5 Labels and bounded thresholds
Labels adjust a per-class threshold `theta[k]`, k = hand x amount class (exact, loose, above, unknown) x lag band
(core: within 2 `spr_h`; tail), 16 numbers, start `THETA` = 4. Positive: `theta[k] = max(THETA_MIN, theta[k] / 1.1)`;
negative: `theta[k] = min(THETA_MAX, theta[k] * 1.5)` (soft negative: `* 1.22`). Bounds `THETA_MIN = 2`,
`THETA_MAX = 16`: a run of bad polls can at most quadruple a class's bar, and one negative outweighs four positives
(rejection bias). Labels never move `med_h`, `spr_h` or the background rates. The thresholds persist across pulls and
reset at load. Zero allocation: the credit records (8 x 7 numbers), the dropped ring (8 x 7), `theta[16]`; the buffers
stay fixed-size, the oldest entry gives way.

### 2.6 With the ladder clamp
The verdict and the clamp see the same poll. The retraction is applied first, then the answer goes through the ladder
as today; in the common case the retraction already put `est` and `hi` below the rung and the clamp has nothing left
to do. A retraction only subtracts what its credit added, so it never pushes `lo` above the pre-credit `lo`; the
clamp may still lower it (a short rung lowers a floor above it, as today).

**Owns.** `Families/Resources.lua` (records' deltas, the verdict, the rescue call, the hit-rate take-back),
`Events/Rows.lua` (records, the dropped ring, retraction, rescue, `theta[16]`, snapshot `rows oracle judged=%d
confirmed=%d retracted=%d soft=%d rescued=%d rescuedLate=%d`).

## 3. The combat harness (tests/Virtual/harness/)

The harness is a model of the Forever client in five layers. Layers 1-3 are the true fight; layer 4, the observer,
is the only place that encodes what the client shows us; layer 5 scripts a scenario. **The observer is shared by
every future headless test** (Druid forms, casters, Protection's damage-taken rage, pulls and kills, target health):
the pairing of §1 is its first customer, not its purpose. Nothing in it is class-named (boundary).

### 3.1 The five layers
1. **Entities** (`harness/entities.lua`): the true state per actor: our character, party members, enemies, pets.
   Each has a GUID, level, health and max, power and max, weapons per hand (pre-armour [min, max], speed), armour (as a
   damage reduction `DR`), auras (id, applied, expiry, stacks) and a current target. Plain Lua tables (test code).
2. **Behaviours** (`harness/behaviours.lua`): seeded, attached to entities, driving them over time. Version 1 keeps
   them few and parametric:
   - `melee` player archetype: white swings per hand (period from speed and haste; outcome table hit, miss, dodge,
     parry, glancing, crit; amount from the weapon and the victim's `DR`), abilities with casts, a queued
     (`onNextSwing`) strike that replaces a main-hand swing, a proc (a non-physical wound on a chance per hit), a DoT
     with ticks, a form change that swaps weapon damage.
   - `caster` player archetype: cast bars, school 2/4/8/32 wounds, an occasional instant; optionally a `pet`
     (a melee behaviour of its own on the caster's target).
   - one `mob`: swings with outcomes against its target (our dodge/parry/block table), a spell or two, target
     selection (highest threat stand-in: the first attacker, switching on a set piece).
   The matrix comes from parameters and seeds, not from more behaviours: level 10-60 (weapon ranges scaled by
   level / 22 from log 2's 36-50 / 24-32, UNMEASURED scaling), `DR` 0 / 0.15 / 0.30 (log 2 inferred about 0; the
   higher values stress the hand overlap), the outcome rates (default log 2: miss 0.14, dodge 0.04, parry 0.04, crit
   0.12, glancing 0; other level gaps UNMEASURED knobs), rhythms and phases, and `n` seeds.
3. **The world** (`harness/world.lua`): runs every behaviour on one clock (a priority queue by time, test code) and
   emits the TRUE event stream: `{ t, source, dest, kind (swing, cast start/success, strike, tick, aura), hand,
   outcome, amount, school, flags }`. It applies its own effects (health, the swing timer's parry haste: log 1) and
   holds the ground truth the metrics read: who hit whom, every landed swing of ours and its rage step.
4. **The observer** (`harness/observer.lua`): turns the true stream into what the addon sees for OUR character,
   through `fake_api` (`ctl.Fire`, `ctl.Tick`, the `ctl` answers). Every rule cites its log; a rule without a log is
   tagged UNMEASURED and has a knob:
   | Client fact | Rule | Source |
   |---|---|---|
   | Victim-side `UNIT_COMBAT`, no source | an outcome on X fires `UNIT_COMBAT(token, action, flag, amount, school)` for X; nothing names the source | U §1; G fact 1 |
   | One firing per token resolving to the victim | same ms, fixed order: on our target `target`, `nameplateN`, `softenemy`/`softinteract`; on us `player`, then `targettarget` when our target targets us; on a party member `partyN` (and `raidN`) | P logs 1-2 (target+nameplate1, target+softinteract, player+targettarget); U §4; G (party1) |
   | Our landing lag | our white outcome arrives after our `PLAYER_SWING` by the hand's lag (§1.2: main from its own swing; off at 0.703 s from its own or 1.686 s from the previous main swing, G5's shares 11:7, 1 in the main hit's frame); `PLAYER_SWING` fires on avoided swings too | P log 2; U O3 |
   | Same-ms avoids | a share 3/87 of outcomes on the target, truth "unexplained" | P log 2 |
   | On-swing proc | a school-32 `UNIT_COMBAT target WOUND` and a `UNIT_COMBAT player HEAL` of the same amount, same ms, 1-2 ms after a `PLAYER_SWING` (the swing event, not the landing), no cast event; a per-swing chance knob (G5: 2 in about 70 swings) | G5 37174, 68467 |
   | Queued strike frame | `PLAYER_SWING`, WOUND 0, the success, the strike's wound, same frame, swing and success in either order | P log 1; the brief's order |
   | Our casts | `UNIT_SPELLCAST_SUCCEEDED("player", guid, spellID)` plain | event-facade spec §2.4 (O16) |
   | Others' casts | `UNIT_SPELLCAST_SUCCEEDED("partyN", SECRET, SECRET)` | G 49873 |
   | Auras in combat | `GetAuraDataByIndex` on the target raises (`ctl.auraError`); our own read as today | fake_api (Phase 1 measurement) |
   | Secret reads | `UnitAttackSpeed(hostile)` secret (knob); `UnitIsUnit("<plate>target","player")` plain or secret (knob); power secret in combat; `UnitDamage` and armour plain out of combat only | Attackers.lua notes; Protection spec §1.1 |
   | Plain reads | `UNIT_COMBAT` args (0 of 779 secret), `GetShapeshiftForm`, `UnitGUID` | U §1-2; Rows.lua |
   | Usability | `IsSpellUsable` answered from our entity's TRUE power against the fake spec's costs; `SPELL_UPDATE_USABLE` fired a knob delay (default 0.1 s, UNMEASURED until G7) after a true power change that flips an answer | TDF gate spike (readable in combat); G7 |
   The observer owns the `PLAYER_SWING` and the out-of-combat refresh of `UnitDamage` (`ctl.damage` set from our
   entity's weapons when out of combat only), so a mid-fight buff or form change leaves the cache stale as in game.
5. **The script** (`harness/scenarios.lua`): a scenario is a roster (entities), a behaviour per entity, and a timeline
   of set pieces (`pull` at t, `add` at t, `formChange` at t, `damageBuff` at t, `targetSwitch` at t, `kill` at t);
   between set pieces the fight is emergent. Our character's behaviour in v1 is a scripted press list (time, ability)
   on top of auto-attack. **Later extension: "press what the display recommends"**, closing the loop against truth:
   the world asks the real Hekili engine (through the facades) for its first recommendation each GCD, presses it
   if the true state allows (resource, cooldown, range: the world's truth), and the metrics add "recommended but
   unpressable" and "pressable but not recommended". It needs: the Hekili engine loaded headless with a Forever class
   file (the test loader's pack path), the world's truth exposed as the client's usability answers through `fake_api`
   (`IsSpellUsable`, cooldowns), and a time budget per GCD in busted.

Files beside the layers: `harness/rng.lua` (a seeded Park-Miller generator, multiplier 48271: Lua 5.1's `math.random` is the C library's and
differs between machines); `harness/drive.lua` (boots VirtualState on `fake_api` + `fake_spec` as
`pairing_replay_spec` does; captures rows through a `COMBAT_LOG_EVENT_UNFILTERED` sink and `Swing` c = 1/c = 3
through the `S.Stage` wrapper; samples `VS.Power(RAGE, t)` each tick); `harness/metrics.lua` (§3.3);
`harness/fixtures/log1.lua`, `log2.lua`, `log3.lua` (the pasted logs with every token row kept: the observer's
duplicate rule is fitted on them; log 2's rows move here from `pairing_replay_spec.lua`; for log 3 only G's key rows are
in the inputs, and the full dump from the job transcript must be pasted). Specs: `harness/fixtures_spec.lua`,
`solo_spec.lua`, `group_spec.lua`, `onus_spec.lua`, `sweep_spec.lua` (marked `slow`, run by `make check`; split out if
it passes 20 s), `alloc_spec.lua`, and `observer_spec.lua` (each observer rule on a one-event true stream).
`fake_api.lua` additions: `UnitGUID`/`UnitIsUnit` answers per token for `party1-4`, `raid1-40`, `partypet1`,
`nameplate1-40`, `softenemy`, `softinteract`, `targettarget`; `UnitDamage` from `ctl.damage`. Nothing else.

### 3.2 Scenario knobs (this design's customers)
`others` (0 solo, 4 party, 39 raid, of which `onTarget` attack our target: default 2 party, 12 raid; archetype mix
`melee` in our main range, `caster`, a `pet`, and a physical ranged stand-in: a `melee` with a 2-3 s period and no
avoids by the target's facing), `attackers` on us (count, period, range, plain or secret speed, `targetSwitch` set
pieces), `damageBuff` (+20% at t, cache not re-read), `formChange` at t, `level`, `DR`, `duration` (120 s), `n`. Truth
per outcome: source (ours by hand / cast / other), and per own swing: landed, avoided, crit, its rage step.

### 3.3 Metrics
- Own hits per hand: credited to the right swing, credited to the wrong hand, missed (fell to background).
- False credits: an other source's outcome credited to any action of ours, per hand, per fight and per 100 own swings.
- Rage error: believed `est` minus truth (truth = the fake spec's swing value per landed swing plus crit extra; no
  pins are fed, so the scale stays 1 and the error is attribution alone), over every 10 s window (the order of the
  time between usability pins in game, UNMEASURED): mean, max, and the share of windows with an overshoot >= 1 step
  (the dangerous sign: `lo` above the real rage).
- Hits on us: precision (credited to the right attacker / credited), coverage (credited / all), unattributed by cause.
- Rows: no row with a `""` destination; no outcome credited twice across tokens; rows in time order per hand.
- Oracle (§2): firings per fight (credits judged), false credits caught (retracted / false credits that crossed a rung), false retractions (a real hit of ours retracted, e.g. a coinciding gain or a stale estimate), rescues and their precision (rescued wound was ours / rescued).

### 3.4 Scenarios and gates (proposed; D4, D5)
| Scenario | n | Gate |
|---|---|---|
| Fixture log 2 (replay) | 1 | main >= 34/36, off >= 31/33 right-hand credits (today's floor), 0 late, 8/8 crits |
| Fixture log 1 | 1 | the two strike frames give `SPELL_DAMAGE` 77/84 and no swing row; the Rend tick 13 and the unexplained 30 + 90 frame at 2463 are background or credited as P reads them (main crit 90 at 353 ms) |
| Fixture log 3 (key rows) | 1 | our 50 at 165485 credited to main; his glancing 4 (7 ms) and MISS (53 ms) background; his Maul frame (177249/177250) background; segment C (we idle): 0 credits |
| Solo, log-2 profile | 200 | right-hand credits >= 94% per hand (34/36, 31/33); wrong hand <= 2%; overshoot windows 0% |
| Solo, `buffAt` +20% | 100 | main credits >= 85% after the buff; false 0 |
| Solo, `formAt` | 100 | credits after the change >= 85% (amount unknown: timing alone); false 0 |
| Party of 5, 2 on target (`melee` in our main range, `caster`) | 100 | main >= 75%, off >= 85%; false <= 4 per 100 own swings; overshoot windows <= 5% |
| Party of 5 with `pet` and `ranged` on target | 100 | main >= 70%, off >= 70%; false <= 6 per 100; overshoot windows <= 10% |
| Raid, 12 on target | 30 | report only (no gate, D5) |
| Level sweep 10-60 x DR {0, 0.15, 0.30}, solo | 20 each | solo gates at DR 0; at DR 0.30 wrong-hand <= 5% |
| Hits on us (§4) | 100 | see §4.3 |
| Oracle, solo log-2 profile | 200 | false retractions <= 0.5% of own credits; rescue precision >= 0.95 |
| Oracle, party of 5 (in-range `melee`) | 100 | caught >= 60% of rung-crossing false credits; false retractions <= 1% of own credits; overshoot windows at most half the no-oracle run's; rescue precision >= 0.90 |

### 3.5 Fixtures and the model's fit
Every pasted log is replayed through the real Rows.lua (as today) and also fitted: `fixtures_spec` computes, from the
log's own rows, the main and off lag medians and core shares, the avoid rate, the crit share and the amount envelope,
and asserts the behaviour and observer defaults within tolerance: main median 474 +- 25 ms with core share 0.85 +- 0.10; off-hand
own-reference median 703 +- 15 ms and main-reference median 1686 +- 15 ms, their shares within 0.15 of the log's
(G5 11:7 of 20; log 2 9:21 of 33), tail share <= 0.15;
avoid rate 0.22 +- 0.06; crit share 0.12 +- 0.05; every white wound inside the configured ranges. A new capture (§5)
is added as a fixture with its own fit; a fit outside tolerance fails, and the defaults are retuned in the same change.

### 3.6 Allocation
Layers 1-3 and 5 allocate (test code); the world runs ahead into flat arrays, and the drive loop reads preallocated arrays and calls `ctl.Fire` with fixed
arguments; `harness/alloc_spec` wraps one generated party fight in `alloc.bytes` (warm-up, then 5 replays) and asserts
0 bytes for VirtualState, as `alloc_spec` and the replay spec do.

## 4. Hits on us in groups (Virtual/Events/Attackers.lua)

### 4.1 Per-attacker amount bands
Each attacker clock slot gains `atkLo`, `atkHi`, `atkN` (preallocated, cleared when the slot is reassigned). A
physical WOUND credited **by clock or by the lone-hostile rule** (never by band, so the band does not feed itself)
adds its amount (CRITICAL halved, CRUSHING / 1.5; BLOCK_REDUCED skipped: the blocked part is not given) to the band:
the min and max over the slot's life. A band is usable from `atkN >= 3`.

### 4.2 The credit rule (decision 6, extended)
Candidates are the hostiles targeting us (today). For a physical WOUND: a candidate *fits* when its band is usable and
holds the amount within [0.8 lo, 1.2 hi] (UNMEASURED margins). Order: (1) exactly one candidate within
`ATTACK_TOLERANCE` of its clock -> it (today), unless its band is usable and excludes the amount and another
candidate's fits, then that one; (2) several within tolerance, or none with a clock: exactly one that fits -> it;
(3) one hostile on us -> it (today); else unattributed. Avoids and spells: today's rule (clock, or the lone hostile).
Two mobs of different strength then separate after three clean hits each; two of the same kind separate only by clock.

### 4.3 What stays unattributed, and why
Two or more same-kind hostiles whose clocks are unset or in phase; a spell (non-physical) with two or more hostiles on
us; a hostile with no token (plates off or out of view) or a secret `UnitIsUnit` answer; more than 8 attackers (the
slots). Cost: no row, so Hekili's `storeDamage` and the tank enemy count miss it, and Revenge falls back to its
usability read (as on Forever today). Harness gates (`onus_spec`, n = 100): two attackers of 2x different strength:
precision >= 0.95, coverage >= 0.80; two identical attackers: precision >= 0.90, coverage reported.

### 4.4 Protection's damage-taken rage
Unchanged: `Sources/Player.lua` stages `Obs.PlayerHit` for every hit on us before and independent of attribution
(Protection spec §1.2 point 1), so an unattributed hit still pays its rage. Nothing here touches it; `onus_spec`
asserts that the staged `PlayerHit` count equals the hits fed, attributed or not.

**Owns.** `Virtual/Events/Attackers.lua` (bands, rule, snapshot `rows onus credited=%d unattributed=%d byBand=%d`).

## 5. In-game checkpoint (user)
ForeverProbe loaded (`/vslog`, `VSCopy`; restart the client once if `Log.lua` is new), open-world mobs (no dummies).
Each capture: `/vslog clear`, `/vslog on`, the fight, `/vslog off`, `/vslog dump`, then the snapshot line R, then
paste. Each dump becomes a fixture (§3.5) and is replayed; the pass criteria are checked on the replay.
R = `/run for l in Hekili.VirtualState.Snapshot():gmatch("rows [^\n]*") do VSCopy(l) end`

| # | Capture | Line(s) | Pass |
|---|---|---|---|
| G0 | build loads, new lines exist | R out of combat | `rows credited`, `rows oracle` and `rows onus` lines present |
| G1 | 2-player fight, dual wield, one partner in melee on the same mob: 20 s alone, 40 s both, 20 s partner alone | the /vslog sequence, then R | replay: segment A right-hand credits >= 94%; segment C 0 credits; segment B: no credit with school != 1 or in a foreign strike frame, credits per own swing within 10 points of segment A's. With the partner also recording (D7), aligned on the shared target rows: false credits <= 4 per 100 own swings |
| G2 | 5-player fight (dungeon pack or elite), >= 2 melee on our target, 60 s+ | as G1 | replay: the fitted background rates and lags inside the party scenario's ranges; the party gates (§3.4) hold on the model refitted to this capture |
| G3 | as G2 with a pet (`partypet1`) on our target | as G1 | as G2; no outcome counted twice across `target`/plate/soft tokens |
| G4 | B15: UNIT_AURA full-update cost after 60 s of a 5-player fight | `/run local u=Hekili.Engine.threadUpdates VSCopy(format("work %.2f ms frames %.1f",u.meanWorkTime,u.meanFrames))` | work <= 5.5 ms (solo 4.38 ms + 25%, proposed) |
| G5 | DONE 2026-10-16 (`tmp/pairing/log5.txt`): solo, dual wield, auto-attack only, 88 s | - | ruled the off-hand's two references (§1.1); add log 5 as a fixture |
| G6 | solo, one hostile, our damage buff cast in combat (a self buff that adds attack power) | the /vslog sequence, then R | replay: main credits after the buff >= 85%, `background` does not grow faster than before it |
| G7 | party fight, we auto-attack and press nothing (the partner tanks: no damage taken), 60 s; record `SPELL_UPDATE_USABLE` too (`/vslog add SPELL_UPDATE_USABLE` before `/vslog on`) | the /vslog sequence, then R, then at combat end `/run local r=Hekili.VirtualState.Power(1,GetTime()) VSCopy(format("%.1f %.1f %.1f",r.lo,r.est,r.hi),UnitPower("player",1))` | `rows oracle` judged > 0; retracted <= 1 per 30 s; rescued counted; est within one white step of `UnitPower`; the log gives the WOUND -> `SPELL_UPDATE_USABLE` delay that sets `ORACLE_MIN/MAX` |

## 6. Tests
- **§1** (`tests/Virtual/Events/pairing_replay_spec.lua`, frame by frame, the fake spec): a glancing 4 at 7 ms and
  a MISS at 53 ms after our main swing are background and our 50 at 369 ms is credited (G's frame); a WOUND 0 then 36
  1 ms later with no success of ours: no row, swing still pending; our strike frame in both orders unchanged; a school-8
  wound inside our range: no row; an avoid credited provisionally and taken back by the hand's wound (one
  `SWING_DAMAGE`, no `SWING_MISSED`); an avoid kept: `SWING_MISSED` at window close, back-dated; an "above" wound in
  the core band credited solo, the same with the background raised (10 quiet-window wounds of that class) rejected; form
  mismatch: credited by timing; the lag median and spread move toward a stream of 520 ms lags and not on tail credits;
  log 2 replay at the floors and 0 bytes. The removed `STALE_AFTER` case is replaced by the "above" case.
- **§3** the harness specs of §3.4-3.6; `alloc_spec.lua` keeps its UNIT_COMBAT mix and adds a provisional avoid.
- **§2** (`tests/Virtual/State/resources_spec.lua` with Rows loaded, the fake spec's spender at 10 and 15): a credit from 8 to 17 predicts the 10-cost flip (firm when `lo` crosses); usable -> confirmed, `theta` of its class down to `4/1.1`; short -> est/lo/hi back to the pre-credit values, the swing pending again inside its window (a later wound takes it), `SWING_MISSED` after it; soft short -> no retraction, half label; an unexplained flip with a dropped 45 in the ring -> rescued (c = 1 at its swing time), without one -> today's pin; a cast spend between outcome and poll -> no verdict; ten negatives cap `theta` at 16, positives floor it at 2; `lo` never above its pre-credit value after a retraction; `alloc_spec` adds a retraction and a rescue, 0 bytes.
- **§4** (`tests/Virtual/Events/cleu_rows_spec.lua` beside the decision-6 cases): bands from three clock credits;
  two candidates in tolerance, one band fits -> that one; no band usable -> unattributed; band never learned from a
  band credit; BLOCK_REDUCED not learned; `onus_spec` gates.
- Every task ends with busted, luacheck, StyLua, LuaLS and the boundary check (no class word in `Virtual/**` or the
  harness).

## 7. Decisions (accepted as recommended, user 2026-10-16: "count all break points as approved")
1. **D1 thresholds:** THETA = 4, LAMBDA0 = 0.01/s, T0 = 5 s, TAU = 10 s, q exact/loose/above 0.90/0.08/0.02
   (PROTOTYPE; the harness retunes them). Higher THETA trades missed own hits (a delayed spender) for fewer false ones
   (an unpressable spender).
2. **D2 per-hand windows:** keep them only as the support `W_h` of the lag density (1.5 / 2.0 s, capped at the period),
   or drop them for a pure density cut-off at 4 SD. Recommended: keep (they bound the buffer and the row delay).
3. **D3 avoid rows:** provisional, emitted at window close (up to `W_h` late, back-dated; recommended), or immediate
   when decisive (LR >= 4 x THETA and no other swing pending), which the dodge hook would see sooner.
4. **D4 fight counts:** solo 200, party 100, raid 30, sweep 20 per cell (18 cells): about 1 min of busted, UNMEASURED.
5. **D5 gates and raid scope:** the §3.4 numbers as proposed; raid report-only (no gate) until a raid capture exists.
6. **D6 background memory:** the background rates persist across pulls and decay with combat time (recommended: a
   group pull starts informed; a solo pull after a group pull starts cautious, about 10 s to relax), or reset at
   each pull to the prior (the first seconds of a group pull then over-credit).
7. **D7 G1 truth:** ask the partner to record with ForeverProbe too (exact false-credit truth), or rely on the
   segment protocol alone.
8. **D8 oracle bounds:** `THETA_MIN = 2`, `THETA_MAX = 16`, steps /1.1 and x1.5, `ORACLE_MIN/MAX` 0.1/0.6 s until G7
   measures the delay; and whether a soft prediction labels at all.
9. **D9 the retracted swing's row:** close it as `SWING_MISSED` (as directed; two rows for one swing), or emit
   nothing more (one `SWING_DAMAGE` row that overstates, no contradiction in the log).

## 8. Out of scope
Attributing other players' outcomes to them (no source in the event; their casts are secret); heals and damage on
party members beyond what the world emits for realism; the swing timer from `PLAYER_SWING` directly (rows stay the
carrier); destinations other than the target (plates, phase C); Phase D's compensating aura removal on a missed cast;
damage-taken rage (Protection spec, unchanged); raid tuning; UNIT_AURA cost beyond the B15 line; the same-ms avoids'
origin (recorded by the harness as "unexplained" until a capture explains them).

## 9. As built (2026-10-16)
Where §0-§7 and the code differ, this table rules. "Deviation n" is the plan's; "ruling" is the ledger's; "Tn" is a
task's review round.

| Topic | Spec text | As built | Source |
|---|---|---|---|
| THETA (§1.4, §2.5, D1) | 4 | `L.THETA = 5`; the oracle's theta[16] starts at it | Deviation 1 |
| Glancing / BLOCK_REDUCED (§1.3) | open the range from 0 | open the loose band (class 2) down to 0 only; the exact band is unchanged | Deviation 2 |
| Background (§1.4) | every unclaimed outcome | white outcomes only (school 1); bg[7] counts AVOIDS only; bg[8] (white, any amount) always | ruling |
| Snapshot (§1.5) | no off-hand reference | `rows credited ... ref=%.0f/%.0f ...`, `rows oracle ...`, `rows onus credited/unattributed/byBand` | Task 5 |
| Verdict window (§2.2) | checked in Resources | checked in Rows (`I.CreditVerdict`) | Deviation 5 |
| Rescue test (§2.3) | `R.gain - shortGain` | `est < c` | Deviation 6 |
| Rescue candidates (§2.3) | any dropped wound | the dropped ring's wounds 0.1-0.6 s (ORACLE_MIN/MAX) before the flip; Resources pays the rescue directly (Rows stages nothing) | Deviation 7 |
| Retraction (§2.2) | take the credit back | bounded by the credit's pre-credit values (`max(cur - d, min(cur, pre))`, clamped to [0, max]); the crit's step goes with it | T3 round 2 |
| Rescue suppression (§2.3) | - | no rescue when a confirmed or open record of the slot explains the flip | T3 round 2 |
| Usability answers (§3.4) | oracle scenarios only | every gate runs `scenarios.oracle`, the sweep included | ruling |
| Overshoot (§3.4) | measured with the oracle | read from a companion run without answers: a model-only metric (the drift); the oracle's "at most half" became danger == 0 | ruling (no answers); Deviation 9 (danger) |
| False wounds (§3.3, §3.4) | one count | gross (every false credit) and net (less those retracted at their verdict); the spec's bounds apply to net (party <= 4, party+pet <= 6); gross <= measured + 1; false avoids and form wrong <= 3% gated too | ruling |
| Solo rescue gate (§3.4) | precision | "one miss" (<= 1 wrong rescue) | Deviation 10 |
| Fixtures (§3.1) | logs 1-3 | logs 1, 2, 3 and 5 (G5); `tools/vslog_fixture.lua` turns a dump into one | Task 5 |
| RNG (§3.1) | seeded | Park-Miller minimal standard (48271, 2^31 - 1), not xorshift | Task 1 |
| Observation draws (§3.1) | the observer rolls the same-ms avoid and the strike frame's order | the melee behaviour rolls both from the world's second generator `W.crng` (seed + 7919) and records them on the truth event (`sameMs`, `order`); the observer draws nothing, so its incremental and batch streams are equal | headless loop plan, Task 2 |
| Attackers, rule 2 (§4.2) | the band that holds it | only when every candidate's band is known, one holds it and more than one hostile is on us; with one, the lone rule credits it and its band learns | T4, Task 5 |
| Attackers, joiner (§4.1) | - | a joining attacker without a band is found by elimination (every known band excludes the wound) | Task 4 |
| Same strength (§4.3, §3.4) | precision >= 0.90 | from the pull: `credited == 0` (equal bands never separate); different strength from the pull is never attributed either (T4 #5, open) | T4 |
| Runtime (D4) | about 1 min | `make check` about 108 s (busted about 95 s); `make test-fast` about 11 s skips the `#slow` gates | final review |

Final gates (deterministic seeds; re-measured at the same bounds after the observation draws moved into the
behaviour, headless loop plan Task 2). Hit rates main / off; false
wounds and avoids per 100 swings; overshoot from the run without answers.

| Gate | Hit rates | Wrong | False wounds, gross | False wounds, net | False avoids | Overshoot |
|---|---|---|---|---|---|---|
| solo, 200 fights | .991 / .989 | 26 / 8 | 0 | 0 | 0.08 | 0 |
| buff, 100 fights | .897 / .944 | 38 / 79 | 0 | 0 | 0.18 | not gated |
| form, 100 fights | .965 / .966 | 82 / 61 (2.6% / 2.1%) | 0 | 0 | 0.09 | not gated |
| party, 100 fights | .831 / .979 | 0 / 7 | 1.76 (<= 2.76) | 1.16 (<= 4) | 0.36 | 22/1200 |
| party+pet, 100 fights | .774 / .898 | 0 / 1 | 6.35 (<= 7.33) | 5.12 (<= 6) | 0.81 | 47/1200 |

| Oracle | Judged | False credits caught | False retractions | Rescues that were ours | Danger |
|---|---|---|---|---|---|
| solo | 5554 | none judged | 1 of 15844 | 1 of 2 | 0 |
| buff | 1888 | none judged | 0 | 43 of 50 | 0 |
| form | 1953 | none judged | 0 | 1 of 1 | 0 |
| party | 2616 | 61 of 82, 74% | 8 of 7226 | 138 of 148, 93.2% (gate 90%) | 0 |
| party+pet | 2548 | 126 of 238, 53% | 20 of 6705 | 260 of 285, 91.2% (not gated) | 0 |

Hits on us (`onus_spec`): 2x strength, the second joining at 15 s: precision 0.967 (>= 0.95), coverage 0.893
(>= 0.80); same strength from the pull: 0 of 10592 credited; same strength joining (reported): precision 0.879.
