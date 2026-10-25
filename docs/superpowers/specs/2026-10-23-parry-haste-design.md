# Parry haste: design

Status: **BUILT** (plan `docs/superpowers/plans/2026-10-23-parry-haste.md`). The owner's ruling of 2026-10-23 ("let's
assume that the increase in swing speed for the next swing is a consistent rule for us and enemies") makes wowsims's
rule Forever's; PHS1 is a launch-day (2026-11-04) confirmation, not a prerequisite. Amended by the plan: the pull is
keyed to the swing it was taken from (`VS.SwingPull` returns `pull, from`; Hekili applies it only while `mh_actual` is
that swing) instead of cleared at `Obs.Swing` c = 4; the world hastens by default (`W.parryHaste`, off only in
world_spec's own case for the knob); the replay feeds the tank logs' Parry, Dodge and Block lines on us (open 3). The
build's further amendments, the one-time re-floor and the belief bugs found while gating are in §7. Parent:
`2026-10-23-attribution-recovery-design.md` §8 (which links here).
Research: `docs/research/2026-10-23-parry-haste.md` (the rule from wowsims's source, the code today, the replay counts).
Decisions continue the parent's numbering (its last is 56).

## 1. The rule as data

When a unit that is auto-attacking parries any attack (white or special), its main-hand swing, due in `r` seconds with
current duration `d`, is pulled by `min(PULL x d, r - FLOOR x d)` when `r > FLOOR x d`; else nothing. Off hand never.
`PULL = 0.4`, `FLOOR = 0.2`: core constants (`L.PARRY_PULL`, `L.PARRY_FLOOR` in `Game/Events/Melee.lua`, beside the
other swing constants). They are a game rule, not class content: no pack field. (Decision 57.)

A shared pure helper, `L.ParryPull(r, d)` (returns the pull, 0 when none), used by the belief, Attackers.lua and the
harness world, so the three agree by construction; one busted spec pins it on the replay's pulls (226 ms at
d 2.353 s with r 0.697; 941 = 0.4 x 2.353; 600 = 0.4 x 1.5; 68 at d 1.5 with r 0.368).

## 2. Our parry: our next main-hand swing

Observation: none new. A plain `UNIT_COMBAT player PARRY` is already `Obs.PlayerHit` with `a = I.HitKind.PARRY`
(`Sources/Player.lua:167-188`). (Decision 58.)

Belief, `Game/State/Families/Swing.lua`:

- `I.On(Obs.PlayerHit, ...)`: when `o.a == HitKind.PARRY`, `I.inCombat`, hand 1 has an anchor and a speed: `p = after(1,
  o.t)`, `r = p - o.t`, `x = L.ParryPull(r, speed[1])`; when `x > 0`, `anchorT[1] = anchorT[1] - x` and `pull[1] = pull[1]
  + x` (a second parry before the swing stacks, as in wowsims: each parry reads the already-pulled `swingAt`). The
  weight and `confAt` are kept (the anchor's evidence is the same `PLAYER_SWING`). `last[1]` is untouched (it is the
  real last swing).
- The pull is kept with the swing it was taken from (`from` = `VS.LastSwing(1)` at the parry) and restarts at a
  parry after a newer swing; `Obs.Swing` c = 4 re-anchors the hand without touching it (the plan's amendment 1).
  `Obs.CombatEnd` clears it.
- Shifting the anchor moves every later predicted swing too, which is right until the next `PLAYER_SWING` and then
  overwritten.
- `VS.SwingPull(hand)` (new, `docs/api` entry): `pull[hand]`, 0 for hands 2 and 3. Allocates nothing.

Hekili's state, `Engine/Sim/State.lua` reset (`:6386-6407`): after `mainhand_speed` is set, with `x = VS.SwingPull(1)`
and `x > 0` and `mh_actual > 0`: `swings.mh_pseudo = swings.mh_actual - x` (so `swings.mainhand`, the rage forecast's
`last`, steps from the pulled phase) and `nextMH = mh_actual - x + mainhand_speed`. The E8 branch (`mh_actual == 0`)
is unchanged (no swing yet, nothing to pull). `mh_actual` itself stays the real swing time. Readers that gain without
change: the rage forecast (`State.lua:1300-1320`, Warrior `last` at `Warrior.lua:197-215`), `mainhand_remains`
(Warrior, Paladin, Hunter packs), the Slam weave and the queued strike's timing. (Decision 59.)

Unchanged, by design: `VS.SwingPending` (a past swing), the swing ticket anchor (`Rows.lua:95-116`: the real
`PLAYER_SWING`), the landing-lag model, `Obs.Swing` c = 1/3/5/6/7. (Decision 60.)

The row's own lag: the server pulls at the parry and the client sees the row later, so `r` is read up to that lag
short. In the `0.4 d` branch the pull is exact (it does not depend on `r`); in the `r - 0.2 d` branch it is that lag
short, so the forecast is at most that lag late. Accepted; PHS1 measures the residual. (Decision 61.)

## 3. The mob's parry: its next swing on us

`Game/Events/Attackers.lua`: a second branch of its `UNIT_COMBAT` handler (`:196`), for `unit ~= "player"` and
`act == "PARRY"`: the unit's GUID (`U.Bound(INDEX[unit])`); if it has a clock `k` with an anchor and a period (the plain
`tokSpeed` when known, else `atkPeriod[k]`): `p` = its next predicted swing after `t`, `x = L.ParryPull(p - t, period)`,
`atkAnchor[k] = atkAnchor[k] - x`. Whose attack was parried does not matter (the rule is the parrier's), so no ticket is
consulted. The same row arrives on several tokens (target, nameplate, softinteract): apply once per GUID per row time
(remember the last `(guid, t)` applied; one pair of locals, no table). No new observation, no row emitted (the row
already pays our ticket through `Rows.lua`). Gains: the hastened hit stays within `ATTACK_TOLERANCE` with two or more
hostiles on us (credited instead of `L.unattributed`), and `learn`'s period EMA sees the full gap. (Decision 62.)

## 4. Harness

World (`tests/Game/harness/behaviours.lua`): per entity and hand, the swing's due time is kept (`e.swingAt[h]`) and
each scheduled swing callback carries the due time it was scheduled for, returning when it is stale. On an emitted
swing or special with `act == "PARRY"`, the victim (the parrier), if it auto-attacks, is pulled by `L.ParryPull` and its
main-hand swing rescheduled. Both `M.melee` (us, `:58`) and `M.mob` (`:373`). The `scenarios.lua:102-103` shortcut
loses "no parry haste on our swing timer". A world knob `parryHaste` (default true, false reproduces today's world for
an A/B). (Decision 63.)

Observer: nothing new. The world's `PLAYER_SWING` comes at the pulled time and the parry rows already exist
(`observer_spec.lua:108`).

Replay (`tests/Game/harness/replay.lua`): parse the target's swing lines on us (`[Target 1] [<us> (#1)] {OtherID: 3, ...}
<outcome>`), today dropped (`:145-157`), as `hit` events with `src = mob, dst = us`, and emit at least the Parry ones
(`UNIT_COMBAT player PARRY`). Emitting every target swing (wounds, blocks, dodges) is the fuller fix and feeds the tank
packs' hits-on-us content; the plan decides whether that is in scope or a follow-up (open question 3). The log's swings
already carry the haste, so the world schedules nothing.

## 5. Floors expected to move

| gate | expected | why |
|---|---|---|
| Warrior Protection replay (`wowsims_warrior_spec.lua:189-195`, floor 0.97, measured 0.979) | up, at most +0.021 (2/94) | 6 hastened swings; 2 on-GCD decisions in the windows |
| Paladin Protection replay (`wowsims_paladin_spec.lua:96-99`, floor 0.62) | up, at most +0.022 (1/46) | 7 hastened swings; 1 decision in a window |
| every other replay (25 logs) | unchanged | no parries in them (`inFrontOfTarget` unset) |
| harness loop gates (`make test-loop`: Fury L24, Arms, tank), flicker, rage error at disagreements | unchanged within noise with world + belief; down with the world alone | the world and belief agree today; both change together |
| onus credit with 2+ attackers (detection floors, `tests/Game/harness/detect_floors.lua`) | unchanged or up with world + Attackers; down with the world alone | the hastened mob hit leaves the 0.2 s tolerance |
| solo safety gates (`over`, `lo`, `danger`), bench, memory, allocation specs | unchanged | no allocation, no new path in recurring code beyond one comparison |

The plan's first task measures the windows' disagreements in both Protection replays and the world A/B
(`parryHaste` false/true) before the belief changes, so each move above is attributed. (Decision 64.)

## 6. Probes and open questions

- **PHS1** (`docs/dev/ingame-ledger.md`): ten parries each way, our `PLAYER_SWING` and the mob's hits around them;
  confirms the clamp, that the off hand is not pulled, and the row's lag residual. Launch-day confirmation (2026-11-04)
  under the owner's ruling.
- Open 1: whether Forever applies it to specials as wowsims does (PHS1 (a) with a parried Sunder Armor or Mortal
  Strike; the design assumes yes, as the source).
- Open 2: the swing ticket's pending window is capped at the payload duration (`Rows.lua:110-114`); after our parry the
  next swing can come at `0.6 d`, inside the previous ticket's window. Proposed: no change (LR by lag separates them);
  revisit if the world A/B shows main-hand credit errors after parries.
- Open 3: replay scope: only the Parry lines (enough for this spec), or every target swing on us. Resolved by the plan:
  the Parry lines only; the rest stays gap AH. Amended 2026-10-24 (Task 5): the build emits the Dodge and Block lines
  too (§7.4).
- Open 4: a parry by us while the main hand is not swinging (out of auto-attack, a cast in progress): wowsims requires
  `AutoSwingMelee`; the belief requires an anchor in combat. PHS1 (b) with a mid-cast parry would show the game's.

## Decisions made in this spec

| # | Decision | Reason |
|---|---|---|
| 57 | Parry haste is a core rule with constants `PULL` 0.4 and `FLOOR` 0.2 and one helper `L.ParryPull(r, d)` shared by belief, Attackers and the harness | a game rule (wowsims `attack.go:1173-1207`), not class content; one helper keeps the three in agreement |
| 58 | Our parry is read from the existing `Obs.PlayerHit` a = PARRY; no new observation or source | the row is plain and already staged |
| 59 | The swing family shifts hand 1's anchor by the pull and exposes `VS.SwingPull(1)`; Hekili's reset applies it as `mh_pseudo` and to `nextMH`; `mh_actual` stays the real swing | every reader of the next main-hand swing gains without its own change; the next `PLAYER_SWING` clears it |
| 60 | `VS.SwingPending`, the ticket anchor and the landing lag are unchanged | they are about the real, past swing (research §3) |
| 61 | The pull is computed at the row's time; the row's lag is accepted | the lag is unmeasured and small; PHS1 measures it |
| 62 | A PARRY row on a hostile with an attacker clock shifts that clock's anchor by the pull, once per GUID per row time, whoever was parried | the rule is the parrier's; keeps onus credit in a crowd |
| 63 | The harness world hastens both directions behind a `parryHaste` knob (default on); the replay emits the log's Parry lines on us | the replay's truth has it; the world must too, or its floors measure nothing |
| 64 | The floors move with this spec as the named cause; the plan measures each move first (replay windows, world A/B) | no floor moves unexplained |

## 7. Amended 2026-10-24 (Task 5): what was built and measured

These notes amend the sections above, which keep the text as designed.

### 7.1 Decision 59: the pull is keyed to its swing

Decision 59's reason says "the next `PLAYER_SWING` clears it"; the build does not clear it there. `VS.SwingPull(1)`
returns `pull, from`, `from` being the swing the pull was taken against (`VS.LastSwing(1)` at the parry); a parry after
a newer swing restarts the pull at that swing (`Game/State/Families/Swing.lua:119-120`), and `Obs.CombatEnd` clears it. Hekili's
reset applies it only while `mh_actual` is `from` (within 1 ms, `Engine/Sim/State.lua:6405-6409`): before the pulled
swing and between its `PLAYER_SWING` and its row, never after that row and never to another swing. A missed
`PLAYER_SWING` lets a later parry add to the old pull under one `from`; the next swing row corrects it. A queued
strike's swing emits a spell row and never moves `mh_actual`, so a pull taken after it is not applied (the safe side;
the plan's open question 1).

### 7.2 E8: a parry before the fight's first swing

§2 said the E8 branch (`mh_actual == 0`) is unchanged. It gains one line: a pull taken before this fight's first swing
(`from` 0 or an older fight's swing, so `from < state.combat`) anchors `mh_pseudo` at `state.combat - pull`
(`State.lua:6417`); `nextMH` stays 0 as E8 has it. A first swing that has landed but whose row has not come yet
(`mh_actual` 0, `from >= state.combat`) waits for the row, at most a landing lag (about 0.47 s; the safe side). The
belief's combat start and Hekili's `state.combat` can differ slightly (bounded).

### 7.3 The mob's clock: the pull dated at our swing, and the latest-hit guard

§3 computed the pull at the PARRY row's time. The server (and the world) pulls at our swing, a landing lag (about
0.474 s, more than the 0.2 d floor) before our row, so a row-time pull came short or landed on the wrong swing. Built
(d6a094e68): when the PARRY row is the avoid Rows just credited to our swing (`L.avoidRowT == t`, `Rows.lua:235`),
Attackers dates the parry at that swing (`L.avoidT`, `Attackers.lua:223`); the rule is unchanged. And (9c3e77e9f) a
parry dated before the hostile's latest learned hit pulls nothing: the swing it pulled has landed and re-anchored the
clock already. Onus with two attackers (seeds 1-100): joining precision 0.939 -> 0.948 and coverage 0.735 -> 0.811
with the dating; the guard moved nothing measurable. The residual (the pulled hit can land before our parry row) is
re-floored (§7.5). The dated parry has no GUID or act check (`docs/dev/gaps.md`).

### 7.4 The world both ways; the replay's Parry, Dodge and Block lines

The world hastens both ways by default (06d527b97): our parry pulls our main hand, a mob's parry of us pulls its swing
on us, never an off hand. The replay emits the target's Parry, Dodge and Block of its swings on us as
`UNIT_COMBAT player` rows (06d527b97, 808a242cf), not its hits on us (gap AH). With the Parry lines alone the Warrior
Protection replay fell 0.979 -> 0.968: Revenge's window opened at a Parry, and the sim refreshed it with Blocks the
replay did not emit. With the Dodge and Block lines it is back at 0.979 (94); two Protection timing fixtures moved by
1 ms. wowsims's partial "Block for N" is emitted as a full BLOCK avoid, a stand-in: in game a partial block is a WOUND
flagged BLOCK_REDUCED, which the Warrior pack's Revenge trigger does not read (gap AH).

### 7.5 The one-time re-floor (the owner's Option A, 2026-10-24)

Cause: decision 63, the world models parry haste. Its swing reschedule reorders the draws of every seeded fight, so
world off against world on is not an A/B of the belief (world off already spans K2 solo recall 0.99-1.00 and staged
0.92-1.00 over five seed sets), and our own pull moves nothing (`L.PARRY_PULL = 0` gives bit-identical solo cells).
Rule: a floor that failed in any seed set (worst of three), or improved in all three, is set to the worst of three
seed sets with the floors file's own rounding and margin. The seed sets: the 200-fight gates 1-200 / 201-400 /
401-600; detection 1-20 / 21-40 / 41-60; onus 1-100 / 101-200 / 201-300; the loops 1-20 / 21-40 / 41-60 (the floors
commit e85d26eb1's message names the detection and onus ranges wrongly; these are the ones measured).

Measured at dafe8312a; the full table is archived in `.superpowers/sdd/2026-10-23-parry-haste/refloor-24679ce0-dafe8312.txt`
(gitignored, so its counts are here):

- Detection: 210 cell-metrics down (53 cells: 47 by draw reordering, 6 by twins drift in K14/K14p, where the world
  pulls one hand of a lockstep pair), 51 up, 579 unchanged.
- Loops (`pack_gate.FLICKER`): 11 down, 5 up (Arms, Fury L24, Feral, Balance, Arcane); `FLICKER_K` 1.6 -> 1.7
  (Balance's flicker against the oracle).
- Named exceptions: Fury L60 retracted 0.1 -> 0.4 (a pre-existing class: a cost-gated ability shown ready on a swing's
  forecast rage; ours 0.16 against the oracle's 0.09 per minute over the 60 fights); Fury L60 flicker 1.8 -> 1.9 (set 3
  1.88); onus 2x joining precision 0.95 -> 0.94 and coverage 0.80 -> 0.77; the Arms replay 0.89 -> 0.88 (the same-frame
  Bloodrage gap, fix 40, which the tie hand-back's correct dodge refund exposed); the Fury replay 0.89 -> 0.92 (up);
  ready-time floors Arms {0.80, 6} -> {0.88, 5} and Guardian {0.54, 40} -> {0.54, 41}; live Paladin Protection L40
  10.4 -> 11.0 s and Enhancement L60 8.0 -> 8.2 s; the Fury (decisions 55, 70), Guardian (52-53, 79-81) and Arms (68,
  74: 177.88 Sunder Armor late -> never) timing fixtures and arms_recs re-recorded (e3f39a083).
- Unmoved: the solo safety gates (3/0 on all three 200-fight sets, `order` 0 after §7.6's restamp), the Warrior
  Protection replay (0.979) and the Paladin Protection replay (0.625).

### 7.6 Belief and harness bugs found while gating

Each fails its test when reverted.

- Tie hand-back narrowed (f8ebe1545): a white-school avoid in a swing's frame (`SAME_FRAME` 0.05 s) that the swing's LR
  refused went foreign, so an instant special pressed 20 ms after a white swing lost its refund (Druid decay errMax
  9.75). The row now goes back to the ticket it tied with, only for a pass-1 match tied by the swing's frame alone (not
  the first swing's window, not the core band; pass (d) never). A `T.Replaceable` match keeps pass 1, so it is handed
  back too and replaces there (tickets_spec).
- Expiry-row restamp (3293c5a18): a swing whose row fell in the lag tail stayed open, the pulled next swing's row came
  first, and the old ticket's expiry row was stamped before it (solo `order` 0 / 1 / 1). A late expiry row is stamped
  at the hand's latest emitted row (K10 cells bit-identical; expiring the stale ticket instead worsened K10 party
  rageErr).
- Combat-end expectation (e7e63ec33): `T.EndCombat` closed a swing opened inside its land window with no expectation,
  so its rage was never believed (decay errMax 3.15); it now stages the expectation (c = 5).
- Demoralizing Roar declared non-damaging (aed652a11): `expects = "instant"` without a school gives school 0, which
  takes avoids only; a Maul landing 0-25 ms after an instant Roar had been paid to the Roar's older ticket. Other
  non-damaging instants still on the default school are a gap.
- The harness's `druid_vs` copy (503ff11f6): `M.boot` copied no `expects`, `velocity` or `school` of an ability and no
  `tick_time` or `dot` of an aura, so no Druid declaration reached the harness belief (bear maulRows 2470 -> 2473).
- The observer's form-change frame (24679ce0f): a form delta in a frame that a later gain joined was answered alone, with
  the pre-shift rage (Maul usable in Bear); it now moves with the frame's spend (Bear-entry overshoot 3.74 -> 0).
- Reverted, `woundSeen` (52ed18355, reverted by dafe8312a): no expectation at a lost close when an untaken white wound
  fell in the swing's window. Its target was the observer bug above, and it cost 23 detection rageErr cells (a
  partner's white wound suppressed a valid expectation: K10 party 24.2 -> 30.2, K10 busy 29.5 -> 36.6, K14f busy
  48.0 -> 53.6); after the revert all 23 are byte-identical to before it.

### 7.7 Accepted edges (D1-D3, ruled 2026-10-24)

- D1, decision 61 amended: only WOUND rows on us were measured late (0.48 s, the providers plan's DM §3); our PARRY
  row's lag is unmeasured. If it lags as much, a parry whose hastened swing fires inside the lag reaches the belief
  after that swing's `PLAYER_SWING`, restarts under the new `from` and pulls the following swing: one early `nextMH`,
  at most 0.4 d, corrected by the next swing row. Accepted with no guard; PHS1 measures it.
- D2: in the `lagged` arm the mob clocks anchor at the lagged row time, so `r` reads late there. Accepted (a
  measurement arm; in game our ~0.47 s landing lag roughly cancels the taken lead). Record only: lagged Fury L60
  flicker 2.05 against 1.9, meter Fury L24 flicker 2.95 against 2.9.
- D3: in the `meter` arm a dated mob hit whose row comes after the PARRY row re-anchors the clock and drops the pull.
  Accepted (an opt-in arm; it misses a pull and never doubles one).
