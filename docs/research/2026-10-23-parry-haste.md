# Parry haste on Forever

Task 6 of the attribution-recovery plan (spec `docs/superpowers/specs/2026-10-23-attribution-recovery-design.md` §8).
Research only; the design is `docs/superpowers/specs/2026-10-23-parry-haste-design.md`.

The owner: "It's one area that will accelerate a swing when we get parried and it works both ways: when we or an enemy
is parried it applies parry haste which speeds up the next MH swing."

## 1. The rule (wowsims, on disk)

Source: `~/src/wowsims-forever/sim/core/attack.go:1173-1207` (`applyParryHaste`), checked out at a2061b0be6; the file is
unchanged since the replay logs' pin d33930d0 (`git diff d33930d0 HEAD -- sim/core/attack.go` has no parry line).

```go
OnSpellHitTaken: func(aura *Aura, sim *Simulation, spell *Spell, result *SpellResult) {
    if !result.Outcome.Matches(OutcomeParry) { return }
    remainingTime := aura.Unit.AutoAttacks.mh.swingAt - sim.CurrentTime
    swingSpeed := aura.Unit.AutoAttacks.mh.curSwingDuration
    minRemainingTime := time.Duration(float64(swingSpeed) * 0.2) // 20% of Swing Speed
    defaultReduction := minRemainingTime * 2                     // 40% of Swing Speed
    if remainingTime <= minRemainingTime { return }
    parryHasteReduction := min(defaultReduction, remainingTime-minRemainingTime)
    aura.Unit.AutoAttacks.mh.swingAt -= parryHasteReduction
```

As a formula, for the unit that parried (the parrier), with `r` its main hand's remaining swing time and `d` its current
(hasted) swing duration:

- `r <= 0.2 d`: nothing.
- else the swing is pulled by `min(0.4 d, r - 0.2 d)`: it never lands sooner than `0.2 d` from the parry.

Facts from the source:

- **The parrier's timer, main hand only.** The aura is on the unit that took the hit (`OnSpellHitTaken`) and moves
  `AutoAttacks.mh` only; the off hand is never hastened. The attacker's timer is untouched.
- **Any parried attack, white or special.** `OnSpellHitTaken` fires for every spell; the only filter is
  `OutcomeParry`. A parried Mortal Strike or Sunder Armor hastens the mob exactly as a parried white swing does.
- **Only a unit that is auto-attacking** (`AutoAttacks.AutoSwingMelee`, `attack.go:1174`).
- **Who has it.** Targets by the encounter option (`sim/core/target.go:230`, `ParryHaste = options.ParryHaste`);
  characters whenever they can parry (`sim/core/character.go:424`, `ParryHaste = CanParry`). So both directions: a mob
  that parries us hastens its next swing; when we parry a mob our main hand is hastened.
- **No test pins the clamp.** `grep -rn "ParryHaste\|parry haste" sim --include=*_test.go` finds only
  `sim/druid/feralcat/dps_report_test.go:62` setting the target option; nothing asserts the 0.2 / 0.4 numbers. The
  replay logs below confirm them numerically.

The classic statement of the rule (remaining above 60% of the speed: minus 40%; between 20% and 60%: down to 20%) is the
same function.

## 2. The rule in game

One sample so far: log 1 of `docs/research/2026-10-16-swing-outcome-pairing.md:28`: "a parry on us pulls the next
main-hand swing forward (log 1: 771 -> 2110, 1.34 s on a 2.2 s weapon)". Read as main-hand swing to main-hand swing:
1339 ms instead of 2200, 861 ms early = 0.39 d, the 40% branch. Log 1's raw rows are not on disk (not in the research
note, not in `~/src/ForeverProbe/results`), so the parry row's own time is unknown and the clamp cannot be checked
against it.

A control from log 2 (same note, rows printed at its end): three of our swings parried by the mob
(`UNIT_COMBAT target PARRY` at 85948, 88247, 100148 ms). Our next main-hand swings came on schedule (gaps 2217, 2200,
2150 ms on the 2.2 s weapon): a mob's parry does not hasten us, as the rule says. The hits on the player were removed
from log 2, so whether the mob's next hit on us came early is not in it.

Capture to take: ledger row PHS1 (`docs/dev/ingame-ledger.md`), with the ForeverProbe recorder (its default events,
PLAYER_SWING and UNIT_COMBAT for every token, are the ones needed):

1. `/vslog clear`, `/vslog on`, then:
   (a) a melee character auto-attacking an open-world mob from the front (no target dummies on Forever) until the mob
   has parried ten of our attacks (`UNIT_COMBAT target PARRY`): the mob's hits on us (`UNIT_COMBAT player ...`) around
   each parry say whether its next swing came early;
   (b) a character with Parry (Warrior, Paladin, Rogue, Hunter; not a bear) letting a mob hit it until ten
   `UNIT_COMBAT player PARRY` rows: our `PLAYER_SWING` (payload: duration, swingType) before and after each.
   `/vslog note a` and `/vslog note b` between the two parts.
2. `/vslog off`, `/vslog dump` (lines under 255 chars in the copy box), paste the dump.

Measure, per parry row at `t` with our previous main-hand `PLAYER_SWING` at `s` and duration `d`: `r = s + d - t`, the
expected pull `min(0.4 d, r - 0.2 d)` (0 when `r <= 0.2 d`), against the observed `s + d - next`. For part (a), the
same with the mob's hits on us and its period from their gaps. The residual is the row's lag (the server hastens at the
parry; the client sees the row later); a residual of tens of ms is expected and fine.

## 3. What the beliefs do today

**`VS.SwingPending`** (`src/Hekili/Game/State/Families/Resources.lua:1269-1285`, `src/Hekili/Game/Events/Tickets.lua:320-330`):
it names the time of a swing that has already happened and whose rage the floor does not show yet. A parry after it
changes nothing about that swing. Unchanged; confirmed.

**The swing ticket anchor** (`src/Hekili/Game/Events/Rows.lua:95-116`): a ticket opens at each `PLAYER_SWING`, which the
client sends at the real swing, hastened or not (log 1). The anchor is right without change; attribution and the landing
lag (`Melee.lua`) are measured from it. Confirmed by reading; PHS1 (b) confirms it in game (the hastened swing's
`PLAYER_SWING` comes at the pulled time).

**The next-swing forecast is late after we parry.** Three readers:

- The swing family (`src/Hekili/Game/State/Families/Swing.lua`): `PLAYER_SWING` stages `Obs.Swing` c = 4
  (`Sources/Swing.lua:18-25`), which anchors the hand (`Families/Swing.lua:50-72`); `VS.Swing(1, now)` predicts
  `anchor + k x speed` (`after`, `:93-104`). Nothing moves the anchor at a parry.
- Hekili's `state.swings.mh_actual`, set from our swing rows at the swing's time (`Engine/Sim/Events.lua:1676-1679`, fed
  by `Rows.lua:327-330`), with `state.nextMH = mh_actual + mainhand_speed` (`Engine/Sim/State.lua:6399`). The rage
  forecast (`Engine/Sim/State.lua:1300-1320`, the Warrior pack's `last`/`interval` at `Hekili_Warrior/Warrior.lua:197-215`)
  steps from `swings.mainhand` by `mainhand_speed`.
- `mainhand_remains` (`Hekili_Warrior/Warrior.lua:1831-1845`; the same shape in the Paladin and Hunter packs) reads
  `nextMH`: the Slam weave and the queued strike's timing.

After a parry on us, all three put the next main-hand swing up to `0.4 d` too late (0.88 s on a 2.2 s weapon) until
that swing's `PLAYER_SWING` re-anchors them: the rage of that swing is forecast late, `mainhand_remains` is too long,
and a rage-gated line can show unaffordable for up to that long. Attribution is not hurt (the anchor is the real
`PLAYER_SWING`). A side effect worth a look: a swing ticket's pending window is capped by the payload duration
(`Rows.lua:110-114`), which assumes the next swing comes a full duration later; after a parry it can come at `0.6 d`
(1.32 s on 2.2 s, inside the 1.5 s main-hand window), so the previous swing's ticket and the next one overlap briefly.
The LR scoring by lag separates them; no change proposed, an open question in the design.

**The observation is already there.** `Sources/Player.lua:167-188` stages every `UNIT_COMBAT player` row as
`Obs.PlayerHit` with `a = I.HitKind.PARRY` (5, `VirtualState.lua:66`), plain. No new source is needed.

**A mob parrying us** (`src/Hekili/Game/Events/Attackers.lua`): each attacker has an anchor and a period (`:43-75`);
a hit on us is credited to the clock predicting a swing within `ATTACK_TOLERANCE` 0.2 s (`:24`, `clockError` `:148-156`).
After the mob parries any attack of ours (or anyone's: the rule is the parrier's), its next hit comes up to `0.4 x
period` early, outside the tolerance. Today: alone on us, the lone-hostile rule still credits it and `learn` re-anchors
(`:158-176`, the period not refined: the gap is off by more than the tolerance); with two or more hostiles on us the hit
is unattributed (`L.unattributed`) and the next one too, until a lone or band credit re-anchors. Attackers.lua reads
only `unit == "player"` rows (`:196-198`); the PARRY row on the mob (`UNIT_COMBAT target PARRY`, or a nameplate token)
is not read. Re-anchoring the clock there gains the onus credit for that hit in a crowd (and keeps the period's EMA
clean).

## 4. The replay and the gates

The replay's truth has parry haste: every request sets `parryHaste: true` (`tools/wowsims/export.lua:40`,
`tests/Forever/wowsims/*.json`). But the export never sets `inFrontOfTarget`, so wowsims gives the target no parry
chance against us (`sim/core/spell_outcome.go:875`): **no log has the mob parrying us.** Only the tanks' logs (the target
swings at us) have our parries:

| log | our parries | hastened (r > 0.2 d) | pulls (ms) | window parry -> swing (s) | our casts in the windows (on-GCD / all on-GCD) |
|---|---|---|---|---|---|
| warrior_protection | 14 | 6 | 226, 941 x3, 470, 743 (d 2.35 s) | 5.1 | 2 / 94 (Shield Slam 57.15, Rend 156.17; Heroic Strike queued at 4.50 and 96.26, Shield Block at 57.04 and 95.54 are off the GCD) |
| paladin_protection | 18 | 7 | 600 x5, 68, 200 (d 1.5 s) | 3.5 | 1 / 46 (126.04) |
| every other log (25) | 0 | 0 | | | |

The replay world parses only our lines and the target's auras (`tests/Game/harness/replay.lua:145-157`, "Not replayed:
the target's swings", `:13-14`): the target's swing lines, its Parry by us included, are dropped, while our swings are
replayed at the log's (hastened) times. So the belief in the replay sees the hastened `PLAYER_SWING` but never the parry:
it is late in exactly those windows, and early nowhere.

Estimate: the replay gates are on-GCD decision agreement. At most 2 of 94 Warrior Protection decisions (floor 0.97,
measured 0.979; `tests/Forever/wowsims_warrior_spec.lua:189-195`) and 1 of 46 Paladin Protection decisions (floor 0.62;
`tests/Forever/wowsims_paladin_spec.lua:96-99`) fall in a window, so modelling it (belief plus the replay emitting the
parry rows) can raise them by at most 0.021 and 0.022; likely less (Shield Slam and Rend are not swing-gated; the queued
Heroic Strikes are off the GCD and not counted). Fury, Arms, Feral, Enhancement, Retribution and every caster: no
parries, no change. The loop disagreements in those windows were not listed individually (the gate prints only its top
three confusions); the plan's first step records them before and after.

The harness world (`tests/Game/harness/`): mobs swing at us (`behaviours.lua:373-397`) and are parried at the
victim's `avoid.parry` (entities default 0.05), and our swings are parried at `RATES.parry` 0.04
(`behaviours.lua:8`), but neither timer is hastened (`scenarios.lua:102-103`'s shortcut). The world and the belief agree
today, so the harness floors measure nothing about parry haste. Modelling it in the world alone would push the
swing-timing floors down (Fury L24 and Arms agreement, flicker, rage error at disagreements, the onus credit with two
or more attackers); world and belief together should land near today's values. It is worth doing in the world, because
the in-game rate is real: a melee in front of a mob that parries 5% of its 2 s swings is hastened about once every
40 s, a tank three times as often.

## 5. Summary

- Rule confirmed from source: parrier's main hand, any parried attack, pull `min(0.4 d, r - 0.2 d)` when `r > 0.2 d`.
- Our parry (`UNIT_COMBAT player PARRY`, plain, already `Obs.PlayerHit` a = 5): our next main-hand swing comes early;
  the swing family, `nextMH`/`mh_actual` and the rage forecast are late by up to `0.4 d` today.
- The mob's parry (`UNIT_COMBAT <its token> PARRY`): the mob's next hit on us comes early; only Attackers.lua's clock
  cares.
- Unchanged and right: `VS.SwingPending`, the swing ticket anchor, the landing lag.
- Replay: only Warrior and Paladin Protection have parries (ours); at most +2/94 and +1/46 once modelled.
- In game: one sample (0.39 d, consistent with the 40% branch); PHS1 measures ten each way.
