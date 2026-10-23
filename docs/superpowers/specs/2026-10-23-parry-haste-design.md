# Parry haste: design

Status: **spec, ready for a plan.** Parent: `2026-10-23-attribution-recovery-design.md` §8 (which links here).
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
- `Obs.Swing` c = 4 on hand 1 (`:50-72`) resets `pull[1] = 0` (the real swing re-anchors). `Obs.CombatEnd` likewise.
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
  confirms the clamp, that the off hand is not pulled, and the row's lag residual.
- Open 1: whether Forever applies it to specials as wowsims does (PHS1 (a) with a parried Sunder Armor or Mortal
  Strike; the design assumes yes, as the source).
- Open 2: the swing ticket's pending window is capped at the payload duration (`Rows.lua:110-114`); after our parry the
  next swing can come at `0.6 d`, inside the previous ticket's window. Proposed: no change (LR by lag separates them);
  revisit if the world A/B shows main-hand credit errors after parries.
- Open 3: replay scope: only the Parry lines (enough for this spec), or every target swing on us.
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
