# Fury priority vs wowsims/forever (2026-10-18)

Research for the Fury APL plan (`.superpowers/sdd/2026-10-18-fury-apl/`, Task 1). It compares the user's Fury
priority (the plan's Design, 2026-10-18) with the Fury rotation of wowsims/forever and says where `focus=1` fits in
the three Warrior packs. The user's list stays the spec. Everything here is a recommendation.

**Credit.** wowsims/forever, https://github.com/wowsims/forever, MIT License ("Copyright (c) 2022 wowsims team",
`LICENSE`). I read it as a reference only. Nothing was built, linked or copied. The fork's lines below are written
fresh with the fork's own keys.

**Clone.** `/home/zack/src/wowsims-forever`, shallow, commit `d33930d04030c3f556582f31949f1f22c17da0e4`
(2026-10-18, "[UI] Read an empty Simple spec json as the default rotation in the preset match (#553)"). Paths
below are relative to it. Fury's default rotation is `ui/specs/warrior/dps/apls/fury.apl.json` (one APL entry per
line, so line numbers cite entries). The spell code is in `sim/warrior/`. I resolved spell IDs from
`sim/warrior/spell_data_auto_gen.go:152-276`. On Forever, Death Wish is 12328 and Sweeping Strikes is 12292
(lines 174, 262). The Overpower window aura 1282733 is `OffensiveStateTriggered` (line 243).

## The user's lines vs wowsims

wowsims order (priority list, `fury.apl.json:10-39`): toggles and trinkets; Sunder (15); potions and racials;
Death Wish (19); Recklessness (20); Sweeping Strikes on >1 target (21); Whirlwind on >1 target (22); Bloodthirst
(23); Whirlwind if Bloodthirst is at least 1.5 s away (24); Execute (25); Cleave (26); the Overpower weave group
(27, group at 51); Hamstring weave (28); back to Berserker Stance (29); Heroic Strike (30, 31); Bloodrage (32);
Berserker Rage (33); Battle Shout (34).

| User's line | In wowsims Fury? | Ordering | Condition differences |
|---|---|---|---|
| Victory Rush (focus) | No | — | Registered but never in the APL: "This spell works but the Sim never kills a target" (`sim/warrior/victory_rush.go:15`). There's nothing to compare. |
| Overpower in Battle Stance (focus) | Yes, as a stance dance | Below BT/WW/Execute/Cleave (27) | wowsims *switches into* Battle Stance for it: wait for the GCD, then Battle Stance, Overpower, Rend if due, then back to Berserker (`fury.apl.json:51`). The variable `Overpower: Can Cast` (55) needs the window aura 1282733, BT and WW both at least 1.5 s away, no execute phase, and rage 5-100. The user's line only fires when already in Battle Stance and has no BT/WW timing guard. |
| Revenge in Defensive Stance (focus) | No (Protection only) | — | It's only in `ui/specs/warrior/protection/apls/default.apl.json:31`. |
| Heroic Strike, `rage>=hs_threshold`, 1 target (focus) | Yes | Last of the damage lines (30, 31), below BT/WW | Line 30: 1 target, not execute phase, rage >= 40. Line 31: the `Delay Check` (BT and WW both at least 1.5 s away, line 54) and rage > 60, any target count, execute included. |
| Cleave, `rage>=cleave_threshold`, >1 target (focus) | Yes | Below BT/WW/Execute (26) | >1 target and rage >= 40. It has no cooldown guard. |
| Keep Rend up | Only inside the Overpower weave | In group 51 | `Rend: Can Cast` (56): the Rend Weave toggle (on by default; its group isn't hidden, line 11), the Delay Check, no execute phase, Rend's remaining time <= 3 s, rage >= 10. It's cast only while already in Battle Stance (51). |
| Sunder Armor (`maintain_sunder`) | Yes | Near the top (15), above every damage line | Single target only and stacks < 5 (group, line 48). A hidden refresh variant (16, 49) re-sunders at <= 10 s with the Delay Check. |
| Thunder Clap (`maintain_thunder_clap`) | No (Protection only) | — | Protection `default.apl.json:26,32` (more than 2 targets, and more than 1 target). |
| Demoralizing Shout (`maintain_demo_shout`) | No (Protection only) | — | Protection `default.apl.json:33` (`auraShouldRefresh`, 6 s overlap). |
| Bloodthirst | Yes | 23, unconditional | Same. On a single target wowsims ranks BT above WW like the user does. On >1 target WW goes above BT (22). |
| Whirlwind | Yes | 22 (>1 target, above BT), 24 | On a single target only when BT is at least 1.5 s away (24). The user's WW has no BT guard. |

Stance facts that hold in both. In the fork, Rend and Thunder Clap are `nobuff = "berserker_stance"`
(`src/Hekili_Warrior/Warrior.lua`, `rend` and `thunder_clap` abilities). In Berserker Stance, where Fury lives for
Whirlwind (`buff = "berserker_stance"`), the user's Rend and Thunder Clap lines stay silent. That's the same reason
wowsims only Rends inside the Battle Stance weave.

## The HS/Cleave no-clip rule in wowsims

wowsims has **no rage reservation** for Bloodthirst or Whirlwind. Its protection comes from three things:

1. **The queue spends at the swing, and a short swing drops it.** The APL casts a tag-1 "queue" spell. It's
   castable when nothing is queued and rage >= the strike's cost *at queue time*, after the Queue Delay ICD
   (`sim/warrior/heroic_strike_cleave.go:94-99`; the delay is `queuedRealismICD`, 250 ms in the preset at
   `ui/specs/warrior/dps/presets.ts:145`). The main-hand swing calls `TryHSOrCleave`
   (`sim/warrior/warrior.go:163`). That deactivates the queue and, if the strike can no longer be cast (rage
   below cost), swings white (`heroic_strike_cleave.go:119-131`; comment at 57-60). A Bloodthirst pressed between
   queueing and the swing spends first, and the strike drops if the rest doesn't cover it.
2. **Priority.** BT and WW rank above every HS/Cleave line (`fury.apl.json:22-24` vs `26, 30, 31`), so when they're
   ready they're cast first.
3. **Rage floors plus a GCD guard.** HS at >= 40 rage on a single target outside execute, with no cooldown check
   (30). HS at > 60 rage only with the `Delay Check` (31): `spellTimeToReady(Bloodthirst) >= 1.5s` and
   `spellTimeToReady(Whirlwind) >= 1.5s` (54). Cleave at >= 40 rage, no cooldown check (26).

So wowsims does *not* implement the user's rule: "after HS/Cleave's cost, enough rage remains for BT/WW if either
comes off cooldown before the next swing". It relies on the floors and the game's drop-at-swing. Note that at
40 rage, HS (15 minus Improved Heroic Strike's rank in the fork, `offensive_cost(15 - talent.improved_heroic_strike.rank)`) leaves 25 to 28, which is below Bloodthirst's 30. The 1.5 s `Delay Check` is one GCD, not the swing
time.

**The user's rule in the fork's keys.** The fork already exposes these keys: `mainhand_remains` (the time to the
next main-hand swing, `RegisterStateExpr` in `src/Hekili_Warrior/Warrior.lua`), `rage.current`,
`action.<x>.cost` (talent-adjusted through `offensive_cost`), and `cooldown.bloodthirst.remains` /
`cooldown.whirlwind.remains`. The literal rule is: refuse HS while
`rage - cost < cost of the earlier of BT/WW when that cooldown ends before the next swing`. The pack tool doesn't accept
`variable,...,value=` lines: `tools/make_pack.lua:18` whitelists only `name`, `use_off_gcd`, `focus` and `if=`. So
the rule goes inline, or into a small `RegisterStateExpr` in the Warrior file if Task 3 prefers a name:

```
actions+=/heroic_strike,use_off_gcd=1,focus=1,if=rage.current>=settings.hs_threshold&active_enemies=1&(cooldown.bloodthirst.remains>=mainhand_remains|rage.current-action.heroic_strike.cost>=action.bloodthirst.cost)&(cooldown.whirlwind.remains>=mainhand_remains|rage.current-action.heroic_strike.cost>=action.whirlwind.cost)
```

Cleave is the same with `action.cleave.cost`. Requiring both terms covers "the earlier of the two". The case where
both come up before the swing is a design choice (needing both costs is stricter), so I left it out. The rule
ignores rage gained before the swing. In-game an HS swing brings no white rage, so ignoring income is the
conservative reading.

The fork also has Classic's `should_queue`/`should_hs`/`should_cleave` (same file). They simulate the BT/MS, WW and
swing events in time order with rage income (`TimeToResource`), which is a looser, income-aware version of the
same rule. Task 3 can reuse them, but the plan asks for the explicit stateless rule, and these use the
`adaptive_queueing_enabled` setting the plan removes.

## What wowsims does that the user's list lacks

- **Execute (below 20%).** `execute` is cast when `isExecutePhase E20` (`fury.apl.json:25`). It sits after BT and
  WW, before Cleave, Overpower, Hamstring and HS. In execute, HS line 30 is off (`not isExecutePhase`) but line 31
  (Delay Check and > 60 rage) still dumps, and the Overpower, Rend and Hamstring weaves are all off (`not
  isExecutePhase` in 28, 55, 56). Execute spends all extra rage, capped (`sim/warrior/execute.go:28-35`). **The
  user's list has no Execute**, so below 20% the fork would keep pressing BT, WW and HS. The fork has
  `execute_phase` (the plain usability read, because target health is secret).
- **Death Wish**: on cooldown, unconditional (`fury.apl.json:19`).
- **Recklessness**: gated by a hidden ON/OFF group (20, 10, 43), so off by default (`presets.ts:133`,
  `useRecklessness: false`).
- **Bloodrage**: when rage < 90 (32). The Go cooldown default is rage < 70 (`sim/warrior/bloodrage.go:37-41`).
  It's also cast pre-pull at -3 s (5).
- **Berserker Rage**: with the Delay Check, only when Improved Berserker Rage (20500) is talented (33), as a rage
  generator. It's also cast pre-pull at -4.5 s (4).
- **Battle Shout**: with the Delay Check when <= 10 s remain (34). It's also cast pre-pull (6). In code it refuses
  until <= 3 s left (`sim/warrior/battle_shout.go:13,65-72`).
- **Berserker Stance return**: when out of it and BT or WW is ready within the input delay (29).
- **Sweeping Strikes** on >1 target (21; 12723 is its hit spell, `sim/warrior/talents_arms.go:418`).
- **Hamstring weave** only with Windfury Totem (aura 10612) and the Delay Check, outside execute (28). Trinkets,
  racials, potions and engineering items (13, 14, 17, 18).
- **Rage dump thresholds**: HS 40 (1 target, not execute), HS 60 (Delay Check), Cleave 40.

## Recommendation

Keep the user's list, with the explicit no-clip condition above on Heroic Strike and Cleave. It's stricter than
anything wowsims does and needs only existing keys. Raise three things with the user, without adding them:
(1) **Execute**. wowsims casts it below 20% right after BT/WW and turns off the cheap fillers there, so the user
needs to decide whether `execute,if=execute_phase` goes after Bloodthirst/Whirlwind. (2) **Bloodrage, Battle
Shout and Death Wish**. Today's Fury list has them (`bloodrage,if=rage.current<90`, `battle_shout`, `death_wish`
under `cooldowns`), wowsims uses all three, and the user's list drops them. They're cheap rage and uptime, so
deciding to keep or drop them is worth one line each. (3) **Rend and Thunder Clap are silent in Berserker
Stance**. Unless the player sits in Battle Stance, those lines never fire; wowsims Rends only inside an Overpower
stance dance. A Berserker Stance return line (wowsims 29; today's list ends with one) keeps Whirlwind usable.
Lower priority: wowsims guards the Whirlwind filler and the GCD fillers with "BT/WW at least 1.5 s away". The user's
BT/WW order already gets most of that.

## Where focus fits in the Warrior APL

`focus=1` puts a pick in the Timeline's Now circle with a countdown when it's predicted within the focus horizon,
and turns it gold when it becomes the press (`src/Hekili/UI/Styles/Timeline.lua:503-560`). "Predicted" means it
appears in the published records within the horizon (`focusHorizon` 10 s, clamped to the lane's, line 514). The
plan's Design has the full rules (`docs/superpowers/plans/2026-10-18-timeline-focus.md`).

**What the engine can predict.** In the fork's Warrior file:
- **Reactive windows are read at `now` only.** `reset_precast` applies `overpower_ready` and `revenge_usable`
  only when `now == query_time`, from a dodge, parry or block in the combat log, or from the usability read.
  `reactive()` (Execute, Revenge, Victory Rush, `execute_phase`) returns the client's answer *now* whatever the
  simulated time. So Overpower, Revenge, Victory Rush and Execute-phase entry are **never predicted before the
  event**. Once a window is open it lasts in the simulation (`overpower_ready` with its remaining time), so it
  can show a countdown while it waits behind a GCD or a cooldown. Otherwise it shows **gold on arrival**.
- **Interrupts and threat** (`shield_bash` on a cast, `taunt`/`mocking_blow` on `threat.lost`, `challenging_shout`
  on `threat.loose`) are reads of now: gold on arrival.
- **Predictable ahead:** debuffs the belief applies with a duration (Rend, Thunder Clap, Demoralizing Shout,
  Sunder through `applyDebuff`), player buffs with a duration (Battle Shout, Shield Block), cooldown-gated picks
  (Bloodrage, Shield Block, Death Wish) and rage-gated dumps (`rage.time_to_*`). Each one still shows only if it
  falls inside the records the engine publishes. A refresh 8 s out shows only when the sequence reaches that far.

### Fury (`tools/packs/warrior/Fury.simc`, today's list; Task 3 replaces it)

| Line | Score | Why |
|---|---|---|
| 8 precombat battle_shout | EITHER | Buff upkeep, but out of combat, so the Timeline countdown rarely matters. The in-combat refresh (33) is the focus one. |
| 9 precombat charge | EITHER | Opener in range. It's a one-off, not a window. |
| 10 sunder_armor (stack < max) | EITHER | Stack ramp is steady. It would be FOCUS as a near-expiry refresh, which this line doesn't test. |
| 11 demoralizing_shout `!up` | FOCUS | Refresh on expiry, predictable. |
| 12 call cooldowns | — | Not a pick. |
| 13-14 run_action_list | — | Not picks. |
| 15 death_wish | EITHER | Burst cooldown, predictable. It's player timing, not a window. |
| 16 recklessness | EITHER | Same as Death Wish. |
| 17-18 execute heroic_strike / cleave | ROTATION | Rage dumps. |
| 19 execute | FOCUS | Phase entry, gold on arrival. |
| 20 victory_rush | FOCUS | After a kill, gold on arrival. |
| 21 intercept | EITHER | Gap closer, a range window read now. |
| 22-23 heroic_strike / cleave | EITHER | Swing-timed and off-GCD, but steady while rage is high (see below). |
| 24 overpower | FOCUS | After a dodge, gold on arrival or a short countdown once open. |
| 25, 27 whirlwind | ROTATION | Steady press. |
| 26 bloodthirst | ROTATION | Steady press. |
| 28 spearing_strike | ROTATION | 20 s cooldown, Battle Stance. |
| 29 slam | ROTATION | Filler. |
| 30 rend `!up` | FOCUS | Refresh, predictable. |
| 31 hamstring | ROTATION | Filler. |
| 32 bloodrage | FOCUS | Timing: cooldown and rage, predictable. |
| 33 battle_shout `!up` | FOCUS | Refresh, predictable (player buff). |
| 34 berserker_stance | EITHER | A stance fix, steady, but easy to miss after an Overpower dance. |

Scoring of the user's new Fury lines (the plan's Design list), which Task 3 writes:

| User's line | Score | Why |
|---|---|---|
| victory_rush (focus) | FOCUS | After a kill, gold on arrival. |
| overpower in Battle Stance (focus) | FOCUS | After a dodge, gold on arrival, or a short countdown once open. |
| revenge in Defensive Stance (focus) | FOCUS | After a block, dodge or parry, gold on arrival. |
| heroic_strike, 1 target (focus) | EITHER | Swing-timed, but steady while rage is high (see below). |
| cleave, >1 target (focus) | EITHER | Same as Heroic Strike. |
| rend (keep up) | FOCUS | Refresh, predictable. Silent in Berserker Stance. |
| sunder_armor (`maintain_sunder`) | EITHER | The ramp is steady, a refresh would be focus. |
| thunder_clap (`maintain_thunder_clap`) | FOCUS | Refresh, predictable. Silent in Berserker Stance. |
| demoralizing_shout (`maintain_demo_shout`) | FOCUS | Refresh, predictable. |
| bloodthirst | ROTATION | Steady press. |
| whirlwind | ROTATION | Steady press. |

Check on the user's focus set (Victory Rush, Overpower, Revenge, Heroic Strike, Cleave): Victory Rush,
Overpower and Revenge fit, and all three are gold-on-arrival windows. **Heroic Strike and Cleave are the questionable
part.** They're timing-bound to the swing, but with rage above the threshold they're predicted almost all the time,
so they'd hold the Now circle and push the real press (BT/WW) to the Next box most of the fight. That works against
the attention zone. It's the user's spec, so this is raised, not changed.

### Arms (`tools/packs/warrior/Arms.simc`)

Lines 8-14 are shared with Fury and score the same. 15 sweeping_strikes (>1 target): EITHER, a cooldown on add
pulls. 16-17 death_wish, recklessness: EITHER. 18-19 execute-list HS/Cleave: ROTATION. 20 execute: FOCUS (phase
entry, gold on arrival). 21 victory_rush: FOCUS (gold on arrival). 22 intercept: EITHER. 23-24 HS/Cleave: EITHER (as
in Fury). 25 overpower: FOCUS (gold on arrival). 26 whirlwind, 27 mortal_strike, 28 spearing_strike, 29 slam, 31
hamstring: ROTATION. 30 rend `!up`: FOCUS (predictable). 32 bloodrage: FOCUS (predictable). 33 battle_shout:
FOCUS (predictable). 34 berserker_stance: EITHER.

### Protection (`tools/packs/warrior/Protection.simc`)

| Line | Score | Why |
|---|---|---|
| 5 precombat battle_shout | EITHER | Buff, but out of combat. The in-combat refresh (16) is the focus one. |
| 6 charge | EITHER | Opener. |
| 7, 10 defensive_stance | EITHER | A stance fix. |
| 8 shield_bash | FOCUS | Interrupt window, gold on arrival. |
| 9 mocking_blow `threat.lost` | FOCUS | Gold on arrival. |
| 11 taunt `threat.lost` | FOCUS | Gold on arrival. |
| 12 challenging_shout | FOCUS | Loose-threat event, gold on arrival. |
| 13 shield_block `stack<2` | FOCUS | Timing, predictable (cooldown and buff). |
| 14 victory_rush | FOCUS | Gold on arrival. |
| 15 bloodrage `rage<20` | FOCUS | Predictable. |
| 16 battle_shout | FOCUS | Predictable. |
| 17-18 run_action_list | — | Not picks. |
| 19, 29 revenge | FOCUS | After a block, dodge or parry, gold on arrival. |
| 20, 30 shield_slam | ROTATION | Steady press. |
| 21 sunder_armor `stack<5\|remains<3` | EITHER | The ramp is steady and the `remains<3` refresh is focus. Splitting the line would let only the refresh carry `focus=1`. |
| 22, 27 thunder_clap `!up` | FOCUS | Refresh, predictable. |
| 23, 28 demoralizing_shout `!up` | FOCUS | Refresh, predictable. 23 is setting-gated. |
| 24 concussion_blow | ROTATION | Cooldown press. |
| 25, 31 heroic_strike / cleave | ROTATION | Rage dumps. |
| 26, 32 sunder_armor | ROTATION | Filler. |

### Recommended `focus=1` sets

Keep each set small, so the Now circle means "look here" rather than "always occupied".

- **Fury** (the user's list fixes it): victory_rush, overpower, revenge, heroic_strike, cleave. Advisory: drop
  heroic_strike/cleave from focus (they'd occupy Now most of the fight). If Execute is added, give it focus. Rend and bloodrage score FOCUS on today's list but stay out: the user's list has no Bloodrage line and fixes its focus lines, and Rend is silent in Berserker Stance.
- **Arms**: overpower, victory_rush, execute, rend, battle_shout (the in-combat line 33, not precombat 8).
- **Protection**: revenge (both lists), shield_block, shield_bash, taunt, mocking_blow, victory_rush, thunder_clap
  (both lists).
