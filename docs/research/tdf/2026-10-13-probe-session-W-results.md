<!-- Ported from TacoDogForever docs/research/2026-10-13-probe-session-W-results.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# Probe session W (Warrior) — results

Source: `ForeverProbe.lua` SavedVariables written at the user's `/reload` on 2026-10-13 16:13 (7.8 MB, ForeverProbe
0.2.0), parsed with a non-executing script. Raw copy: `~/src/ForeverProbe/results/ForeverProbe-2026-10-13-W.lua`
(git-ignored there). Questions and expected answers: `2026-10-13-port-probes-runbook.md`. Cross-checked against
`2026-10-13-probe-results-swing-usable.md` (no contradiction; two refinements of it and one of the gate spike, marked **refines**) and
`docs/spikes/2026-10-gate-spike-findings.md`.

## 1. Header

| Item | Value |
|---|---|
| Character | Warrior, level 21 (`PR14.pLevel` = 21 in 675 samples; the swing note says level 30, same character class and weapons), single spec "Warrior" (id 1491, `PR15.spec1_*`), power type RAGE (`PR16.powerToken`) |
| Client | Forever 1.60.1 build 70338, interface 16001; `C_Secrets.HasSecretRestrictions()` = true |
| Weapons | dual wield: main hand 2.2 s, off hand 2.5 s, ranged 2.2 s (`PR2.as_mh/as_oh/as_rg`); item ids main hand 15230, off hand 2849, ranged 269742; head and both trinket slots empty (`PR13.inv_head/inv_trinket*` nil) |
| Talents | 6 points, from the C_Traits walk: Dual Wield Specialization 2/5, Blood Craze 1/3, Piercing Howl 1/1, Unbridled Wrath 5/5, Cruelty 5/5, Furious Precision 3/3 (`PR5.facts.walkO.list`) |
| Bars (slots 1–12) | Attack, Battle Shout, Charge, Rend, Thunder Clap, Hamstring, Bloodrage, Taunt, Sunder Armor, Overpower, Shield Bash, Piercing Howl (`PR10.slot<n>_spell`); Heroic Strike on slot 74, Cleave on slot 75 (`PR1.facts`) |
| Targets | open-world mobs, not dummies: Southsea Brigand (level 12) and Southsea Cannoneer (level 14), classification `normal`, creature type Humanoid (`PR14.tLevel/tName/tClass/tCreature`) |
| Enemy nameplates | none were ever created (see PR6) |

### Sessions

Four sessions were recorded (the addon keeps the last four). Only the last was closed with `/fprobe stop`; the first
three ended in a `/reload` (the panel code changed between them: ForeverProbe commits `316211c` PR7 uses Rend, `071e152` PR20 dim slots).
Times are clock times; the end time of an unclosed session is its last sample.

| Session | Start | End | Length | Samples (in combat) | Events (in combat) | Notes |
|---|---|---|---|---|---|---|
| S1 | 15:49:23 | ~15:54:12 | 289 s | 6,339 (1,132) | 2,589 (1,023) | 1 |
| S2 | 15:54:34 | ~16:01:40 | 426 s | 8,326 (0) | 158 (0) | 0 (no combat at all) |
| S3 | 16:02:05 | ~16:06:54 | 289 s | 5,774 (301) | 885 (313) | 1 |
| **S4** | **16:07:24** | **16:13:05** (stopped) | **341 s** | **6,918 (1,202)** | **2,490 (537)** | **9; the full run, with panel and spike** |

"Samples" sum the PR1–PR19 rings' counters; the counts below that say "S4" are from this session unless a session is
named. S4's combat share is 105 of 675 half-second ticks (about 52 s, three fights: ~16:09:03–16:09:4x,
16:10:12–16:10:39, 16:10:59–16:11:09). Per-probe counts for S4 (samples / of them in combat / events / of them in
combat): PR1 718/124/74/34, PR2 340/54/5/5, PR3 339/53/1958/245, PR4 360/71/39/35, PR5 26/2/3/0, PR6 675/105/26/24,
PR7 886/185/211/80, PR8 675/105/27/14, PR9 702/119/27/14, PR10 13/2/2/2, PR11 696/125/35/33, PR12 170/27/0/0,
PR13 191/47/21/20, PR14 367/63/34/13, PR15 12/1/0/0, PR16 675/105/0/0, PR17 0/0/18/8, PR18 73/14/10/10, PR19 facts
only. No probe recorded an error (`errors` absent everywhere). The legacy 0.1.0 sampler wrote 15,469 samples over
its life; the ring keeps the last 2,000 (S4, 16:09:49–16:13:05, 200 in combat).

### The user's `/fprobe note` texts, verbatim

| Session | Time | In combat | Text |
|---|---|---|---|
| S1 | 15:53:06 | no | `PR20 ooc rage 0: gold lit, green dark, both pairs` |
| S3 | 16:03:40 | no | `PR7 tint: red far, green close with Rend; Heroic Strike reads in range at any distance (on-next-swing)` |
| S4 | 16:07:57 | no | `PR20 ooc rage 0: gold, dark, gold, dark` |
| S4 | 16:08:09 | no | `PR7 tint: red far, green close` |
| S4 | 16:09:40 | no | `PR20 combat: 2nd dark green went light green` |
| S4 | 16:10:32 | **yes** | `PR28:both` |
| S4 | 16:11:50 | no | `PR27: left end of the icons float over the left end of the timeline bar, right end is never overlapped` |
| S4 | 16:12:08 | no | `scale set to 0.8` (written by `/fprobe scale`) |
| S4 | 16:12:29 | no | `scale set to 1.2` (written by `/fprobe scale`) |
| S4 | 16:12:41 | no | `scale set to 1` (written by `/fprobe scale`) |
| S4 | 16:12:49 | no | `halo: clean at all times` |

There are no notes for PR21, PR23, PR24, PR29 or PR30, and no `PR8 skipped` note.

### How to read the evidence

Encoding: `S` secret, `P` plain, `N` nil, `E` call errored, `A` API absent; `C` in combat, `O` out of combat
(`InCombatLockdown()` at the sample). Counts come from each key's tally and cover the whole session. Value
examples are limited: a tally keeps only the first and last plain value per side, and the sample ring keeps the
last 160 samples (about 80 s), so for S4 the ring is almost all out of combat. Where S1 or S3 hold the combat
window the doc says so. Clock times are derived from `GetTime()` against each session's start (±1 s).

## 2. Per-probe results

### PR1 — IsCurrentSpell / IsCurrentAction for the queued strike

**Question.** Is a queued Heroic Strike / Cleave (Maul on the Druid) visible through `C_Spell.IsCurrentSpell`,
`C_ActionBar.IsCurrentAction` and `CURRENT_SPELL_CAST_CHANGED` in combat?

**Evidence.**
- `cur_hs`, `cur_cl`, `act_hs`, `act_cl`, `cur_at` (Attack, 6603): **P in 124 of 124 combat samples** and 594 of 594 out
  of combat; none secret. `cur_ml` is absent (no Maul on a Warrior).
- Control works: in S1 the ring holds the start of a fight; `cur_at` went false → true on the
  `CURRENT_SPELL_CAST_CHANGED` at 15:53:47 and stayed true for 18 ticks (~9 s), then false.
- `CURRENT_SPELL_CAST_CHANGED` n=40 (18 in combat), arg 1 (`cancelledCast`) plain; `ACTIONBAR_UPDATE_STATE` n=21;
  `UNIT_SPELLCAST_SENT` n=9 (3 in combat) with plain unit, target name (7 of 9; nil when no target), castGUID and
  spellID; `UNIT_SPELLCAST_SUCCEEDED` n=4.
- **No queued strike was captured.** The first and last combat value of `cur_hs/cur_cl/act_hs/act_cl` is false in
  every session. In the retained records the only Heroic Strike event is one `UNIT_SPELLCAST_FAILED` for spell 285
  (S1, a failed queue); no `SENT` for 285 or 845 appears. The booleans' tallies keep no
  per-value counts, so a transient `true` that fell outside the ring is invisible.

**Verdict: partial.** The three reads are plain in combat (124/124); whether they turn true while a strike is
queued was not captured.

**Feeds.** G006 `Queued` observation and G075 press highlight: the plain-read half is settled; the queued-true half
needs a re-run of runbook step 5 (and a probe fix, section 6).

### PR2 — Unit stats in combat: attack speed, weapon damage, attack power

**Question.** Are `UnitAttackSpeed`, `UnitDamage`, `UnitAttackPower`, `UnitRangedDamage` readable in combat?

**Evidence.**

| Key | Combat | Out of combat | Example (out of combat) |
|---|---|---|---|
| `as_mh`, `as_oh`, `as_rg` | **S 54/54** | P 286/286 | 2.2, 2.5, 2.2 |
| `dmg_min/max`, `dmg_ohmin/ohmax`, `dmg_pct` | S 54/54 | P 286/286 | 45.871–63.871, 27.795–37.695, 1 |
| `ap`, `ap_pos`, `ap_neg`, `rap` | S 54/54 | P 286/286 | 171, 0→23, 0, 91 |
| `rdmg_speed/min/max` | S 54/54 | P 286/286 | 2.2, 26.3–37.3 |
| `statsSecret` (`C_Secrets.ShouldUnitStatsBeSecret()`) | **P, true 54/54** | **P, false 286/286** | the plain predicate tracks the secrecy exactly |

- A +23 attack-power buff (after the Battle Shout at 16:10:35) shows out of combat: `ap_pos` 0 → 23 and weapon
  damage 45.871–63.871 → 49.486–67.486.
- Events: `UNIT_DAMAGE` n=4 and `UNIT_ATTACK_POWER` n=1, all in combat, unit argument plain; `UNIT_ATTACK_SPEED` never fired.

**Verdict: answered.** Every stat read is plain out of combat and secret in combat; `ShouldUnitStatsBeSecret()` is a
plain flag that says which. (Confirms the known result.)

**Feeds.** G027 reads speeds out of combat and takes the in-combat speed from `PLAYER_SWING`; G028's rage per swing is
learned, not computed from weapon damage. Fallback branch of the runbook applies.

### PR3 — Swing anchors: PLAYER_SWING, rage power events, HS/Maul success timing

**Question.** Is `PLAYER_SWING` plain in combat; when do rage power events arrive relative to swings; is
`C_SwingTimer` range usable?

**Evidence.**
- `PLAYER_SWING`: S4 n=37, all in combat, arg 1 (duration) and arg 2 (type) **P 37/37**. Over S1, S3 and S4: 77 events.
  Durations 2.2 (type 0, main hand) and 2.5 (type 1, off hand). The retained anchors (S1 and S3) give consecutive
  intervals: main hand 2.17, 2.27, 2.20, 2.18, 2.27, 2.17, 2.16 s (mean 2.20); off hand 2.56, 2.42, 2.58, 2.36, 2.51,
  2.50 s (mean 2.49). The two hands' swings land 0.08–0.68 s apart.
- Rage power events: `UNIT_POWER_FREQUENT` n=1,733 (124 in combat) and `UNIT_POWER_UPDATE` n=145 (65 in combat); payload
  (unit, power token) plain (`player`, `RAGE`); the rage value is not in the payload. In S1 and S3's retained anchors,
  34 of 56 and 40 of 64 combat power events arrive **in the same frame as a swing** (bursts of 3 to 8 events in the swing's frame); the rest follow casts (Rend, Battle Shout, Bloodrage) or decay.
- `UNIT_SPELLCAST_SENT` n=9 / `SUCCEEDED` n=4 / `FAILED` n=23 (12 in combat), payload plain. The first of S4's failures is
  spell 402927 (Victory Rush, unusable at the time); in S3 the 15 retained failures are Rend (7), Bloodrage (5) and Battle Shout (3) presses, ~0.16 s apart (key repeat).
- `PLAYER_ENTER_COMBAT` n=3 (0 with `InCombatLockdown()` true) and `PLAYER_LEAVE_COMBAT` n=3 (2 true): these are the
  auto-attack start and stop events and fire before the lockdown flips.
- `C_SwingTimer.IsTargetWithinSwingRange(0/1)` (`swRangeMH/OH`): **N (nil) in 53 of 53 combat and 286 of 286 out-of-combat
  samples**, including S1 samples where Rend, Heroic Strike and `CheckInteractDistance` all said the target was in melee range.
  `EnableRangeCheck(0, true)` succeeded (`facts.enableRange` = true) but `PLAYER_SWING_RANGE_UPDATE` fired once, at
  session start (`0, false, false`: swing type, in range, **checksRange false**), and never when the user walked in and out of range.
- HS/Maul `SUCCEEDED` timing: **no data.** No Heroic Strike or Cleave cast reached a retained record (see PR1).

**Verdict: answered for the anchors; the HS success timing is missing.** `PLAYER_SWING` is a plain, exact per-hand
clock in combat; the rage power events are same-frame timing markers; the swing-range API returns nil on this client.

**Refines** the known results: they plan the range of on-next-swing strikes from `C_SwingTimer` /
`PLAYER_SWING_RANGE_UPDATE`. In this run the API never produced a range answer, so that route is not available.

**Feeds.** G027 anchors on `PLAYER_SWING` (primary); G028 reads the rage step from the burst; HS stays on its usable gate.
The on-next-swing range gate cannot use the swing-range API: it needs a melee spell on the same pack (as PR7 does with
Rend) or `CheckInteractDistance`.

### PR4 — Haste and the GCD length

**Question.** Are haste reads and the GCD duration readable in combat?

**Evidence.**
- `spellHaste`, `haste`, `meleeHaste`, `rangedHaste`, `quiverHaste`: **S 71/71 in combat**, P 289/289 out of combat (all 0 on this character).
- `C_Spell.GetSpellCooldown(29515)` (Forever's GCD spell): `isActive` and `isEnabled` **P 71/71 in combat** (`isActive` true in 4
  of the 42 retained combat samples of the S1 and S4 rings); `isOnGCD` true in 4 and nil in 67 (S4 tally P4 N67); `startTime`, `duration`, `modRate` **S 71/71**
  in combat, plain out of combat (0, 0, 1).
- `C_Spell.GetSpellCooldownDuration(29515)` returns a userdata duration object in and out of combat (`gcdDurType`), but `gcdRemain`
  is S in combat (71/71), plain out of combat.
- `GetSpellCooldown(61304)` (retail GCD spell): nil in every sample; Forever has no such spell.
- `SPELL_UPDATE_COOLDOWN` n=35 (33 in combat): arg 1 (spell id) plain; the ids seen are Charge Stun (7922) and three proc or
  talent spells, Rule of Rage (1313291), Unbridled Wrath (12964) and Touch of the Grave (1260198).

**Verdict: answered.** Haste and GCD length are secret in combat; the GCD's running flag is plain.

**Feeds.** G029 cannot observe haste in combat. The runbook fallback applies: calibrate from observed GCD lengths and the
`PLAYER_SWING` duration; the `isActive` flag gives the GCD's start and end edges.

### PR5 — Talents: the C_Traits walk, spec points, known rank spells

**Question.** Can the talent tree be walked in combat with the same answers as out of combat?

**Evidence (S4; S1 has the same walks).**
- `walkO` (16:07:24) and `walkC` (16:09:09, flagged in combat): both `trees` 1, `nodes` 52, `active` 6, `bought` 6, **`secret` 0, `errors` 0**,
  one try each. The 52 node records are **identical node for node** (id, ranks purchased `rp`, active rank `ar`, max rank
  `mr`, entry, definition, spell id and name). Six nodes have `rp > 0` (listed in the header). Spell names resolve
  (`C_Spell.GetSpellName`), e.g. Improved Intercept 20504, Death Wish 12328, Flurry 12319, Bloodthirst 23881, Enrage 12317.
- `walkO.ips` and `walkC.ips` (`IsPlayerSpell` for the first three walk spells) read `E:false`; this is the probe encoding a
  plain `false` (an `and/or` slip in the probe, section 6), and agrees with `rp = 0` for those nodes.
- Rank ladders (`facts.known`): `IsSpellKnown`, `IsPlayerSpell`, `C_SpellBook.IsSpellKnown` report only the rank-1 spell of a talent
  (Cruelty `TFFFF` with 5/5 purchased) and a single rank of Rend (6547) and Heroic Strike (285) as known. `GetSpellInfo`
  non-nil is true for nearly every id. Ladders carry no rank information; the walk does.
- `C_SpecializationInfo`: `GetSpecialization` 1, `GetActiveSpecGroup` 1, `CanPlayerUseTalentSpecUI` true;
  `GetSpecializationInfo(1)` = 1491 "Warrior" with 0 points (spec 2 and 3 id 0, name nil); `GetTalentInfo{talentIndex=}` errors
  (`query.tier must be specified`) and `{specializationIndex, tier=1, column=1}` returns nil; legacy `GetNumTalentTabs`, `GetTalentTabInfo`,
  `GetTalentInfo` absent; `C_Engraving` absent.
- Events: `PLAYER_REGEN_DISABLED` only; no talent event (no talent change during the run).

**Verdict: answered.** The `C_Traits` walk is readable in combat and equals the out-of-combat walk (52 nodes, 0 secret, 0
errors); the points-based spec APIs and the rank ladders are not usable.

**Feeds.** G031 `Talent` observation reads ranks from the tree, in or out of combat; G062 uses the walk (points API is
dead, `spec1_points` = 0 with 6 spent).

### PR6 — Nameplates in combat

**Question.** Can plates be enumerated and judged (hostile, in combat with us, threat, range) in combat?

**Evidence.** `np`, `hostile`, `secretAttack`, `threatPlain`, `unitSecret`: P in all 675 samples, first and last value 0.
`NAME_PLATE_UNIT_ADDED` and `NAME_PLATE_UNIT_REMOVED` **never fired in any of the four sessions**, and the legacy sampler's `np` is 0
in all 2,000 retained samples (200 in combat). Threat events do arrive: `UNIT_THREAT_LIST_UPDATE` n=20 (all in combat, unit `target`)
and `UNIT_THREAT_SITUATION_UPDATE` n=6, payload plain.

**Verdict: no data.** No enemy plate existed, so nothing about plate units, `UnitCanAttack` on plates or their threat could be
read. Most likely enemy nameplates were off (runbook step 0.4, key `V`, or `nameplateShowEnemies`).

**Feeds.** G033 / G034 / G058: undecided. Re-run with enemy plates on (the runbook's step 11).

### PR7 — Range: IsSpellInRange, IsActionInRange, swing range, tint

**Question.** Are spell and action range reads and `ACTION_RANGE_CHECK_UPDATE` plain in combat; does `SetVertexColorFromBoolean` work?

**Evidence (S4: 886 samples, 185 in combat; range spells Rend `rd`, Heroic Strike `hs`, Charge `ch`).**

| Key | Combat | Out of combat | Meaning |
|---|---|---|---|
| `range_rd` (Rend, melee) | P 155, N 30 (no target) | P 114, N 587 | false at distance, true in melee (S1 ring: 22 combat samples, all true) |
| `range_hs` (Heroic Strike) | P 155, N 30 | P 114, N 587 | **true in every sample with a target, at any distance** (S1 ring, out of combat: 87 of 87, including 77 where Rend said false) |
| `range_ch` (Charge, 8–25 yd) | P 155, N 30 | P 114, N 587 | false when the target is closer than 8 yd (S1 ring: 22 combat samples), true in the Charge band (31 out of combat) |
| `actRange_*` (`IsActionInRange`) | identical to `range_*` | identical | same answers, slots 4 (Rend), 3 (Charge), 74 (Heroic Strike) |
| `hasRangeReq_*` | P 185/185, true | P 701/701, true | |
| `interact2`, `interact3` (`CheckInteractDistance`, 10–11 yd) | P 185/185 | P 701/701 | true when in melee |
| `swingRange` (`IsTargetWithinSwingRange`) | **N 185/185** | N 701/701 | nil always (see PR3) |
| `unitInRange` (`UnitInRange("target")`) | **S 185/185** | S 701/701 | secret even out of combat |
| `tintOK` (`SetVertexColorFromBoolean` on the plain range boolean) | true in 22 retained combat samples, "nil" without a target | same | works; the argument was never secret |

- `ACTION_RANGE_CHECK_UPDATE` n=203 (77 in combat): payload (slot, isInRange, checksRange) **plain** (P 203/203). Slots seen
  include many that are not ours (31, 47, 55, 57, 75, 77, 78, 82, 84), so the enable call is global and other addons' buttons fire it;
  filter by our slot. `PLAYER_TARGET_CHANGED` n=8.
- User notes (S3 and S4): tint red at distance, green in melee, with Rend; "Heroic Strike reads in range at any distance
  (on-next-swing)". Matches the data.

**Verdict: answered.** Spell and action range reads and their update event are plain in combat; on-next-swing strikes answer
"in range" at any distance; the swing-range API and `UnitInRange` are unusable (nil, secret). The tint works with a plain
boolean; a secret boolean was never exercised because no range read was secret.

**Feeds.** G059 range roots and the range filter are viable from `IsSpellInRange`; G073 tint through `FromBoolean` is fine. A pack
declares the range spell of an on-next-swing ability as a real melee spell (Rend, Hamstring), never the strike itself.

### PR8 — Target casts and channels

**Question.** Can the target's `UnitCastingInfo` / `UnitChannelInfo` (end time, `notInterruptible`) and cast events be read in combat?

**Evidence.** `cast_*` and `chan_*` for `target`: N (nil) in all samples (105 combat, 570 out): no target cast happened. `castingSecret`
(`C_Secrets.ShouldUnitSpellCastingBeSecret("target")`) is **plain true** in combat and out of combat (first and last value on both
sides). No `UNIT_SPELLCAST_*` event for unit `target` was recorded; the 27 events counted are the player's own.
Runbook step 12 was not done (no casting mob, no `PR8 skipped` note).

**Verdict: partial.** The secrecy flag predicts that a target's cast info is secret (true even at rest); no actual target cast was observed.

**Feeds.** G060 target-cast observation / interrupt timing: plan for the fallback (interrupts by toggle, no timing) until a re-run sees a
real cast; the flag is a plain, cheap guard.

### PR9 — Own casts and channels

**Question.** Are the player's `UnitCastingInfo` / `UnitChannelInfo` end time, channel events and pushback readable?

**Evidence.**
- A cast-time ability did occur: **Slam (spell 1240193) has a 1.5 s cast** (S3, 16:02:31; `cast_start` 191467334, `cast_end`
  191468834, milliseconds). Both `UnitCastingInfo("player")` samples taken in combat were **plain**: name, display name, texture, start, end, spell
  id, castGUID, castBarID, `notInterruptible` (true), delay (0), trade (false).
- Events for that cast, in combat, payload plain: `UNIT_SPELLCAST_START` n=1, `_STOP` n=1, `_INTERRUPTED` n=4 (a fifth argument, the castBarID, plain once),
  plus `_FAILED` n=15 and `_SUCCEEDED` n=3 for instants. Arguments: unit, castGUID, spell id, castBarID plain.
- `castingSecret` (`ShouldUnitSpellCastingBeSecret("player")`): **plain false** in and out of combat (S3: 43 combat, 556 out).
- Channels: `chan_*` nil in all combat samples (no channel; a Warrior has none). No `CHANNEL_*` or `DELAYED` event.
- S4 has no cast-time ability (cast_* nil).

**Verdict: partial.** Own cast start/end are plain in combat and the player flag says so; channel behaviour (end time, update, pushback)
is untested.

**Feeds.** Cast part of G045/G048: the belief reads the player's cast end directly. Channel half (G046 and the Phase 3
critical chain) needs the Druid session (Tranquility, Hurricane).

### PR10 — Keybinds and action slots

**Question.** Can slot → spell → key be read in combat (G072)?

**Evidence (S4, 13 samples, 2 in combat; all P, identical in and out of combat).**
- `GetBindingKey("ACTIONBUTTON1..12")` = 1,2,3,4,Q,E,R,T,F,G,`` ` `` for slots 1–12 plus the shapeshift button key (`CTRL-F1`);
  `key_mb1b1` (MULTIACTIONBAR1BUTTON1) nil; `GetBindingAction("1")` = `ACTIONBUTTON1`; `C_KeyBindings.GetBindingByKey("1")` and
  `GetBindingIndex` plain.
- `C_ActionBar.GetSpell(slot)` for slots 1–12 returns the spell ids listed in the header; `GetActionText` nil (no macros).
- Bar state: page 1, `GetBonusBarOffset` 1, `GetBonusBarIndex` 7, `HasBonusActionBar` true, `HasTempShapeshiftActionBar` false.
- `meleeSlotKey` (key of Rend's slot 4) = `4`. Heroic Strike's slot is **74**, a bonus-bar slot outside the ACTIONBUTTON1–12 range
  read here; its key was not read.

**Verdict: answered, one gap.** All binding and slot reads are plain in combat. Slots above 12 (stance/bonus pages) were not
exercised; the lookup there must map the bonus-bar slot to its button through `GetBonusBarOffset`.

**Feeds.** G072 slot → command → key lookup is viable without the per-ability override shrink, for slots 1–12; slot 74 needs the bonus-bar mapping.

### PR11 — Proc glow, cooldown duration objects, SetCooldown with secret times

**Question.** Does `IsSpellOverlayed` + `GLOW_SHOW/HIDE` work; do duration objects drive a Cooldown; does `SetCooldown` accept secret times?

**Evidence (S4, cooldown spell Bloodrage).**
- `ovl_hs`, `ovl_op`, `ovl_rv` (`C_SpellActivationOverlay.IsSpellOverlayed`): P 125/125 in combat, false throughout; `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` n=0.
  Overpower was never usable (legacy `u_op` false in all 2,000 samples), so no proc occurred.
- `C_Spell.GetSpellCooldownDuration(Bloodrage)` returns a userdata in and out of combat (`durType`); its `GetRemainingDuration`, `HasStarted`, `GetTotalDuration` are **S 125/125 in combat**, plain out of combat (0, true, 0).
- `Cooldown:SetCooldownFromDurationObject(duration)` (`setFromDurOK`): **true** in and out of combat (S4's first and last combat call true; 30 of 30 combat samples in the S1 ring).
- `Cooldown:SetCooldown(startTime, duration)` with the cooldown table's numbers (`setCooldownRawOK`): out of combat true (every retained sample); in combat **rejected**, S4's first combat call and 30 of 30 in the S1 ring:
  `bad argument #2 to '?' (Usage: self:SetCooldown(start, duration [, modRate])`. `cd_start`, `cd_dur` are S in all 125 combat samples, so each combat call had secret numbers.
- `cd_active` (the same cooldown table): P 125/125 in combat (false first, true last), `cd_start`/`cd_dur` S.
- `GetSpellCooldownDuration` allocates **56 B per call**, in and out of combat (`facts.allocDurC/allocDurO`).

**Verdict: partial.** The duration-object route works in combat and the raw secret-number route is rejected. The proc-glow half
has no data: no proc occurred.

**Flag.** The user's `PR28:both` note says a sweep showed on both the PR28 square (duration object) and the PR11 square (raw
`SetCooldown`). The raw call fails in combat (125/125 combat calls carried secret numbers), so the PR11 sweep he saw in combat can only have come from a plain call made
before combat (Bloodrage was cast earlier, in the 16:09 fight). The note does not confirm a secret-time `SetCooldown`.

**Feeds.** G074 swipe: drive the Cooldown from the duration object. Do not pass cooldown-table numbers to `SetCooldown` in combat. G075 proc glow:
needs a proc (Overpower after a dodge, or a Druid proc) to test.

### PR12 — Pets and totems

**Question.** (Opportunistic.) Are `UnitExists("pet")`, pet reads and `GetTotemInfo` readable?

**Evidence.** A Warrior has neither. `petExists` P false (27 of 27 in combat), `petGUID` nil, `petPower` P 0, **`petHealth` S in
every sample** (in combat and out, though no pet exists); `GetTotemInfo(1..4)` for empty slots: **S in combat (27/27)**, plain out of combat (143/143: `have` false, name `""`, 0);
`ShouldTotemSlotBeSecret` is **plain false in combat** while the values it describes are secret; `PLAYER_TOTEM_UPDATE`, `UNIT_PET` n=0.

**Verdict: no data** for pets and totems as such (nothing to read). The side facts are recorded, not extrapolated.

**Feeds.** G050 observed pets and totems: needs a Hunter, Warlock or Shaman; the secret-in-combat `GetTotemInfo` and `UnitHealth("pet")` are first hints.

### PR13 — Gear and items

**Question.** Are inventory ids, item cooldowns, counts and usability readable in combat?

**Evidence (S4, 47 combat samples).** `GetInventoryItemID` for hands, main hand, off hand, ranged: P 47/47 (head and trinkets nil: empty slots);
`C_Item.GetItemCooldown`, `C_Container.GetItemCooldown`, `GetItemCount`, `IsUsableItem` for four potion ids: P 47/47 but all zero/false (the character owns none, count 0, no cooldown running);
`C_Item.GetWeaponEnchantInfo` and legacy `GetWeaponEnchantInfo`: P 47/47 (no enchant). `BAG_UPDATE_COOLDOWN` n=21 (20 in combat): fires in combat, **on ability presses** too. The head/trinket reads (`isEquippedHead`, trinket cooldown) were never taken.

**Verdict: partial.** The calls return plain values in combat, but no item was on cooldown, no potion owned, and no head/trinket worn, so a plain read of a **running** item cooldown was never seen.

**Feeds.** G051–G053: gear scan reads plain in combat; item readiness from the client remains unproven (runbook: have a potion in the bags).

### PR14 — Context: movement, target classification, threat, mount/vehicle

**Question.** Which context reads stay plain in combat?

**Evidence (S4: 367 samples, 63 in combat).**
- **Plain in combat (P 63/63 unless noted):** `moving` (`IsPlayerMoving`), `mounted`, `taxi`, `vehicle`, `vehicleUI`, `pLevel`, `affectingCombat`, `tAffectingCombat`,
  `tCanAttack`, `tEnemy`, `tExists`, `tDead`, `tDeadOrGhost`, `tPlayer`, `tTapDenied`, `tClass` (`normal`), `tLevel` (12, 14; 0 with no target), `tCreature`/`tCreatureID`
  (Humanoid, 7; nil with no target), `tGUID`, `tName`, `tThreat`, `tTanking`, `tThreatStatus`, `tThreatPct` (3, true, 3, 100; nil with no target), and the flags
  `tIdSecret` and `tThreatSecret` (both **plain false** in and out of combat).
- **Secret in combat, plain out:** `speed` (`GetUnitSpeed` current; 0, 7, 4.5 seen out of combat) and `runSpeed` (7): S 63/63.
- **Secret always (in and out of combat):** `tHealth`, `tHealthMax`, `tHealthPct` (S 63/63 and 304/304).
- Events in combat: `PLAYER_STARTED_MOVING` / `PLAYER_STOPPED_MOVING` n=7 each (2 and 4 in combat), `PLAYER_TARGET_CHANGED` n=8 (3 in combat),
  `UNIT_THREAT_SITUATION_UPDATE` n=6. `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` n=3 each, **both with `InCombatLockdown()` false** (0 of 3
  and 0 of 3); the legacy sampler agrees (0 of 25 each over all runs).
- No `ENCOUNTER_*` events; no elite, rare or boss target: `tClass` only `normal`, `tLevel` never -1.

**Verdict: answered** for target identity and threat (plain in combat), movement (`IsPlayerMoving` plain, speed secret), mount/vehicle (plain), and target health (secret always). Boss-only (level -1 /
`worldboss`) was not exercised.

**Feeds.** G030, G038–G040, G076 context roots: use the plain list; mark `speed`, `target.health` as unreadable; `moving` from `IsPlayerMoving` or the events. Use the event identity, not
`InCombatLockdown()`, inside the REGEN handlers.

### PR15 — Specialization API on Forever, talent groups

**Question.** What do the spec APIs mean on Forever; does dual spec exist?

**Evidence.** `GetSpecialization` 1, `GetSpecializationSystem` 1, `GetActiveSpecGroup` 1, `GetNumSpecializationsForClassID(1)` = 1, class id 1;
`GetSpecializationInfo(1)` = (1491, "Warrior", ... points 0), specs 2 and 3 id 0 and name nil; legacy `GetNumTalentGroups` / `GetActiveTalentGroup` absent. P in and out of combat. `ACTIVE_TALENT_GROUP_CHANGED` and `PLAYER_TALENT_UPDATE` never fired
(the user did not switch).

**Verdict: partial.** One pseudo-spec per class (id 1491 for the Warrior); a switch event was not observed.

**Feeds.** G062 re-detects spec on events: the detection key is the class-wide spec 1; the actual spec identity comes from the talent walk (PR5). Dual spec switch untested.

### PR16 — Power max and regen

**Question.** Are mana/rage/energy max and regen readable in combat?

**Evidence (S4, 105 combat samples; rage is the Warrior's resource, mana and energy read 0 for a Warrior).**

| Key | Combat | Out of combat |
|---|---|---|
| `cur_rage` (`UnitPower`) | **S 105/105** | **S 570/570** |
| `pct_rage` (`UnitPowerPercent`, no curve) | S 105/105 | S 570/570 |
| `max_rage` (`UnitPowerMax`) | **P, 100** | P, 100 |
| `maxSecret_rage/mana/energy` (`ShouldUnitPowerMaxBeSecret`) | P, false | P, false |
| `regen_rage`, `powerRegen` (`GetPowerRegenForPowerType`, `GetPowerRegen`) | **S** | **P, -12.499** (rage decay, internal units) |
| `regen_energy`, `regenCast_energy` | S | P, 10.001 |
| `regen_mana`, `manaRegen`, `regenCast_*`, `manaRegenCast` | S | P, 0.001 / 0 |
| `spiritRegen`, `spiritRegenCombat` | P, 7.25 / 0 | P, 7.25 / 0 |
| `powerType`, `powerToken` | P, 1, `RAGE` | P |
| `cur_mana`, `cur_energy`, `max_mana`, `max_energy`, `hasMana` | P 0/false | P 0/false (not the Warrior's resources: no information) |

**Verdict: partial.** Rage is answered: current value secret always, max plain, regen rates plain only out of combat. Mana and energy max and regen are
for the Druid session.

**Refines** the known results: `GetPowerRegen()` in combat was "not yet measured"; it is **secret in combat** (105/105), so the rage decay rate is
read out of combat and cached.

**Feeds.** G021/G022 (lane 3D): read max directly; read regen rates out of combat only and calibrate in combat.

### PR17 — UI_ERROR_MESSAGE in combat

**Question.** Are error ids and texts readable in combat?

**Evidence.** Across S1, S3, S4: 120 `UI_ERROR_MESSAGE` events, **errorType and message plain in every one** (no secret payload, `secretCount` absent, no overflow);
`GetGameMessageInfo(type)` returned names. In combat 76 of them (52 + 16 + 8).

| errorType | Name | Text | Events (S1 / S3 / S4) | In combat |
|---|---|---|---|---|
| 62 | `ERR_ABILITY_COOLDOWN` | Ability is not ready yet. | 64 / 11 / 3 | 38 / 11 / 3 |
| 359 | `ERR_OUT_OF_RAGE` | Not enough rage | 5 / 4 / 0 | 5 / 4 / 0 |
| 402 | `ERR_SPELL_OUT_OF_RANGE` | Out of range. | 16 / 0 / 13 | 8 / 0 / 3 |
| 57 | `ERR_SPELL_FAILED_S` | Target too close; Interrupted | 1 / 1 / 2 | 1 / 1 / 2 |

Type 57 is a generic "spell failed + reason string", so the reason is in the text.

**Verdict: answered** for the Warrior. "Must be behind" (Shred) needs the Druid session.

**Feeds.** G042 `GameError` observation is viable: ids 62, 359, 402 are single-meaning; id 57 needs text matching.

### PR18 — Tooltip lines and loss of control

**Question.** Is `C_TooltipInfo.GetSpellByID` readable, and `C_LossOfControl` data?

**Evidence.**
- Tooltips (read once at session start, out of combat): Rend: `10 Rage` / `Melee Range`, `Instant`, `Requires Battle Stance, Defensive Stance`, `Wounds the target causing them to bleed for 45 damage over 15 sec.`;
  Bloodrage: `41 Health`, `Instant` / `1 min cooldown`, `Generates 10 rage at the cost of health ...`. Line type codes 0, 13, 34, 43. **Not re-read in combat.**
- Loss of control (S4, 14 combat samples): two real stuns by Southsea mobs (spell 6253 Backhand) at 16:09:03 and 16:11:04: `LOSS_OF_CONTROL_ADDED` n=2 (both in combat) and `_UPDATE` n=8, unit argument plain;
  `GetActiveLossOfControlDataCount` P in combat; the data table's `locType` `STUN_MECHANIC`, `displayText` `Stunned`, `spellID` 6253, `duration` 2, `priority` 5, `startTime`, `timeRemaining` (2 → 1.399): **all P** in combat.
- `C_Spell.GetSpellLossOfControlCooldownInfo(Rend)`: `startTime`, `duration`, `modRate` **S 14/14** in combat, plain out of combat; `isEnabled` nil.

**Verdict: partial.** Loss-of-control data is readable in combat; tooltip text is readable out of combat and was not tried in combat; the zone-disabled-spell use case (G043) was not exercised.

**Feeds.** G043 zone-disabled spells: tooltip scan out of combat is proven. LoC cooldowns (G016): the spell-level LoC cooldown is secret in combat; use the `C_LossOfControl` data instead.

### PR19 — Launcher and menu plumbing

**Question.** Which launcher, menu and fade pieces exist on Forever?

**Evidence (`PR19.facts`).** Present: `LibStub`, `LibDataBroker-1.1`, `LibDBIcon-1.0`, `AceAddon-3.0`, `LibSharedMedia-3.0` (other addons loaded them), `AddonCompartmentFrame` with `RegisterAddon`, `MenuUtil` with `CreateContextMenu`,
`UIDropDownMenu_Initialize/CreateInfo/AddButton`, `ToggleDropDownMenu`, `UIFrameFade/FadeIn/FadeOut/FadeRemoveFrame`, `Settings` with `RegisterCanvasLayoutCategory` and `RegisterAddOnCategory`, `C_Timer.After`, `C_AddOns.GetAddOnMetadata`, `CreateColor`, `Mixin`, `CreateFromMixins`,
`PixelUtil`, `BackdropTemplateMixin`, `ActionButtonSpellAlertManager`, `GameTooltip`, `Minimap`, `MinimapCluster`. Absent: `EasyMenu`, `InterfaceOptions_AddCategory`, global `GetAddOnMetadata`, `ActionButton_ShowOverlayGlow`, `LibCustomGlow`.
Functional: `UIFrameFadeOut` call ok, `UIDropDownMenuTemplate` frame created ok, `BackdropTemplate` frame created ok. **`/fprobe menu` was not run** (`menuUtilOpenOK`, `dropDownOpenOK` absent).

**Verdict: partial.** Everything needed exists and builds; the menus were not opened.

**Feeds.** G081/G082 launcher and menu: the Hekili-style launcher is feasible (`LibDBIcon` or `AddonCompartment`; `MenuUtil` or `UIDropDownMenu`); fades available.

### PR20 — Descending Step curve through UnitPowerPercent

**Question.** Does a descending Step curve `(0,1),(thr,0)` through `UnitPowerPercent(..., curve)` drive `SetAlpha`, so an inverse gate lifts the wait layer?

**Evidence.**
- S4: 13,120 curve evaluations in combat and 56,992 out of combat, **every result secret** (`pr20_secretC/O`; no plain result), every `SetAlpha(result)` accepted (`pr20_setAlphaOkC/O` equal the counts, no `setAlphaErr`). The same in S1–S3 (no error in any session).
- Squares: the left pair uses a curve on a 0–100 scale (threshold 15), the right pair on a 0–1 scale (threshold 0.15). The user's notes: out of combat at rage 0, **gold lit, green dark in both pairs** (S1 and S4); in combat, "**2nd dark green went light green**".
  Reading: only the second green (the 0–1 pair) lit; the first green (the 0–100 pair) stayed dark. If the percent were 0–100, both greens would have lit once rage passed 15. So `UnitPowerPercent(unit, type, false, curve)` evaluates the curve on a **0–1 fraction**.
  This is my inference from the note; the note does not say whether the paired gold square went dark.

**Verdict: answered.** The gate works in and out of combat with a secret result into `SetAlpha`; the curve's x range is 0–1.

**Refines** the gate-spike's open item ("`UnitPowerPercent` scale likely 0–100"): this run points the other way, 0–1 for the curve input, matching Catnip's `AddPoint(fractionOfMax, value)`.

**Feeds.** 1F's inverse gate lifts the wait layer (`UnitPowerPercent(..., false, curve)` with points in fractions of max).

### PR21 — SetAlpha on a frame holding a Cooldown

**Question.** Does `Frame:SetAlpha(curve result)` hide the child Cooldown's swipe together with the icon?

**Evidence.** `pr21_setAlphaOkC` 3,280 and `pr21_setAlphaOkO` 14,248 (S4), no error. The PR21 frame uses the first gate's curve, the **0–100 scale** one (threshold 15 on a 0–1 domain), so its alpha stayed 1 and the frame never faded.
No note on PR21.

**Verdict: partial.** `SetAlpha` with a secret curve result is accepted on a frame holding a Cooldown; whether the swipe vanishes with the icon was not observable (the frame never faded).

**Feeds.** 1F gold frame / swipe vanish together: re-run with the 0–1 curve and a note.

### PR22 — Plain SetCooldown in combat

**Question.** Does `Cooldown:SetCooldown(GetTime(), 10)` work in combat?

**Evidence.** `pr22_okC` 5 (S4; also 3 in S1, 1 in S3), `pr22_okO` 30, no error; `GetCooldownTimes` returned (start, duration) = (191980594, 10000) ms in combat (and the same shape out).

**Verdict: answered.** A plain-number `SetCooldown` works in combat.

**Feeds.** Slot 1's swipe from our own predicted times is available.

### PR23 — Edit Mode nine-slice atlas pieces

**Question.** Do the Edit Mode atlas pieces exist for the blue configuration outline?

**Evidence.** `DISPLAY.pr23`: all nine entries true (center, corner, corner_fx, corner_fy, corner_fx_fy, edge top/bottom/left/right) in all four sessions; the spike's `errors` table is empty. No note on how the outline looked.

**Verdict: partial.** All atlas pieces resolve and set without error; the visual check (corners and edges drawn) has no note.

**Feeds.** Blue configuration outline: viable; confirm visually in D.

### PR24 — SetGradient alpha ramp vs colour ramp

**Question.** Does `SetGradient` work for an alpha ramp and a colour ramp?

**Evidence.** `pr24_alphaRamp` true, `pr24_colourRamp` true, `pr24_createColor` true (all sessions). No visual note.

**Verdict: partial.** Both gradient calls succeed; the look was not noted.

**Feeds.** NEXT box and window-bar fade: calls work; the halo's gradient on the spike also built without error.

### PR25 — Spike: region count and build cost

**Evidence (S4 `SPIKE`).** 115 regions, built once in **4.817 ms**, 26.9 KB, `errors` empty.

**Verdict: answered.** The two-zone spike (about 100 regions) builds in under 5 ms and 27 KB.

**Feeds.** Option 2 is not blocked (PR25 passes).

### PR26 — Spike: OnUpdate cost and frame rate

**Evidence (S4 `SPIKE`).** 4,324 frames: OnUpdate body **0.069 ms average, 0.562 ms maximum**; `GetFramerate()` averaged 57.2 over 77 s with the spike shown and 51.4 over 261 s hidden.
The hidden window includes the three fights (the spike was shown only after combat, from ~16:11:48), so the frame-rate comparison is confounded; it is not evidence of a speed-up.

**Verdict: answered for cost.** The glide costs 0.07 ms per frame (0.56 ms worst frame); no frame-rate penalty is visible.

**Feeds.** Option 2 stands on cost (`/tdf perf` on the live lane remains the comparison). The in-combat frame-rate with the spike shown was not measured (runbook step 8 asked for it in combat).

### PR27 — Spike: window bar anchored now-line → moving icon

**Evidence.** `maxGapPx` 11.947, `avgGapPx` 0.278 (icon 1, bar right edge against icon left edge, read in the frame the icon moved). User note: "left end of the icons float over the left end of the timeline bar, right end is never overlapped".

**Verdict: answered, with a flag.** The user saw no gap or overlap at the bar's cap end. The measured maximum of 11.9 px (average 0.28 px over 4,324 frames) is probably the wrap frame of the glide (an icon jumping 264 units) or a layout-read lag, not a visible gap; I could not separate the two from the data. The "left end overlaps" is the icon covering the now line at its start, a geometry effect.

**Feeds.** Option 2 / Option 3: the user's observation passes PR27; the numeric outlier is open.

### PR28 — GetSpellCooldownDuration → SetCooldownFromDurationObject in combat

**Evidence.** `PR11.setFromDurOK` true in combat (S4 first and last call, 30 of 30 in the S1 ring); `DISPLAY.pr28_allocC` and `pr28_allocO` = **56 B per call** (the `/fprobe alloc` run in combat); user note at 16:10:32 in combat: "PR28:both" (a sweep on both the PR28 and PR11 squares, see the flag under PR11).

**Verdict: answered.** The game's sweep works from a duration object in combat; allocation 56 B per call.

**Feeds.** Cooldown waits get the game's sweep (G074's delta stays); ring marker only is not needed.

### PR29 — Icon texcoord strip as a window-bar colour

**Evidence.** No note.

**Verdict: no data.** The spike built the strips without error (`errors` empty) but the user did not record whether each bar read as its ability's colour.

**Feeds.** Window-bar colour: undecided (fallback: one neutral colour).

### PR30 — Cooldown sweep on a 20-unit icon, numbers hidden

**Evidence.** No note. The sweep ran (`SetCooldown(now, 6)` every 6 s on icon 2 and the NOW cell, no error).

**Verdict: no data.** Legibility of the sweep at 20 units was not noted.

**Feeds.** Sweeps on hanging icons: undecided (fallback: cooldown waits marked by the ring only).

### Halo — feathered backdrop at three scales

**Evidence.** `halo_setTexture` true, `halo_sliceMargins` true; the panel and spike halos built (no `errors`). User notes: scale 0.8 (16:12:08), 1.2 (16:12:29), 1 (16:12:41), then "**halo: clean at all times**" (16:12:49).

**Verdict: answered.** No seam at 0.8, 1 or 1.2.

**Feeds.** §3.5 direction (b) ships as is.

## 3. Things that stand out

- **The 2,000 `WRONG_WORLD_STATE_EXPRESSION` strings are not UI errors.** They are the legacy 0.1.0 sampler's `acR` key: the second return of
  `C_AssistedCombat.IsAvailable()` (`failureReason`). The legacy ring keeps the last 2,000 samples (of 15,469 written) — 16:09:49 to 16:13:05 in S4, 1,800 out of combat and 200 in combat — and **every one** carries `acA` = false,
  `acN` = nil, `acS` = nil and that reason. The call itself works; the feature is switched off by a world-state expression, in and out of combat. This matches the gate spike (2026-10-11,
  "`C_AssistedCombat` ... `WRONG_WORLD_STATE_EXPRESSION`") and `GetRotationSpells()` returned an empty table in all 13 runs. The PR17 game-error texts are four different strings (table in PR17); none is this.
- **`InCombatLockdown()` is false inside `PLAYER_REGEN_DISABLED`** (0 of 3 in S4; 0 of 25 over all legacy runs) and inside `PLAYER_ENTER_COMBAT` (0 of 3). Retail returns true there. The flag flips afterwards; handlers should key on the event, not the flag.
- **`C_SwingTimer.IsTargetWithinSwingRange` is inert** (nil in 886 samples in S4) and `PLAYER_SWING_RANGE_UPDATE` fires once with `checksRange` false. Contradicts the plan in the known-results note (see PR3).
- **Cooldown `SetCooldown` rejects secret numbers; duration objects work** (PR11). The user's "PR28:both" note conflicts with the PR11 data (flagged there).
- **Slam is a 1.5 s cast** on Forever (spell 1240193, `PR9`); queued Heroic Strike and Cleave are on-next-swing.
- **Spell ids not in the probe's tables:** 402927 (Victory Rush) is the first of 23 failed casts in S4 (unusable at the time); 1313291 (Rule of Rage), 12964 (Unbridled Wrath), 1260198 (Touch of the Grave) fire `SPELL_UPDATE_COOLDOWN`. The ids come from the Forever DB2 in `~/.local/share/wow-db2/forever`.
- **`UnitHealth("pet")` is secret with no pet, `GetTotemInfo` is secret in combat for empty slots, and `ShouldTotemSlotBeSecret` says false while it is** (PR12).
- **`IsPlayerSpell` / `IsSpellKnown` report only a talent's rank-1 spell** (Cruelty 5/5: `TFFFF`) (PR5).
- **`UnitInRange("target")` is secret even out of combat** (PR7). Target health is secret even out of combat (PR14).
- **`UNIT_AURA` fires in combat** with a plain unit and a plain-typed update table (legacy `ui` = `table`, 2 samples); the table's `addedAuras` list is secret per Catnip; the probe did not read it.
- **Coverage gaps in the run itself:** no enemy plates, no casting mob, no Heroic Strike/Cleave press, no potion, no proc, a spike shown only after combat, no notes for PR21/23/24/29/30.

## 4. Extrapolation to the other classes (the Forever secrecy model)

The user's instruction: extrapolate Warrior results where we can; assume resources, range and ability scans are treated consistently across
resource types and classes. Basis: every Warrior fact below is a measured probe key; "Catnip" is the prior-art matrix "What's readable in combat" in
Catnip's `docs/api-research.md` (Durts, a Druid addon verified on Forever; the copy read is under `/tmp/r6/catnip-src`, not in this repo); "gate spike" is
`docs/spikes/2026-10-gate-spike-findings.md` (Warrior level 13 and a level-1 Rogue). Confidence: **measured** (seen on Forever for that signal and resource), **consistent with Catnip**
(Catnip, a different class, matches), **assumed** (no class-independent evidence).

| Signal family | Measured on the Warrior (combat / out, key) | Catnip / gate spike (Feral, Rogue) | Rule for every class | Confidence | Later phases may skip |
|---|---|---|---|---|---|
| **Resource values** (`UnitPower`, `UnitPowerPercent`) | rage: S 105/105 combat, S 570/570 out (`PR16.cur_rage`, `pct_rage`); a curve result into `SetAlpha`: S 56,992 out / 13,120 combat, 0 errors (`DISPLAY.pr20_*`) | Catnip: energy, rage, mana `UnitPower`/`UnitPowerMax` secret. Gate spike: energy S always (Rogue), mana S even out of combat (spec §3) | The current value of any primary resource (rage, energy, mana, assumed focus) is secret in and out of combat; never read it, never compare it. Use usability flips for anchors and `UnitPowerPercent(..., false, curve)` (0–1 fractions) for display gates | measured (rage, energy), consistent with Catnip (mana); focus assumed | An "out-of-combat exact resource" mode; any per-class "is the number readable" probe |
| **Resource max, regen, type** | `max_rage` P 100 both sides, `maxSecret_*` P false (`PR16`); regen reads (`regen_rage` -12.499, `regen_energy` 10.001, `regen_mana` 0.001) **P out, S in combat**; `powerType`/`powerToken` P in combat | Catnip lists `UnitPowerMax` as secret (differs for rage max); `UnitPowerType` readable | Power type is plain. Regen rates are read out of combat only and cached. Max: plain for rage; energy and mana max assumed plain (their `maxSecret_*` flag read false on a Warrior, though their values are 0 there) | rage measured; energy, mana max **assumed** (Catnip says secret; D settles with `PR16.max_energy`, `maxSecret_energy`, `max_mana`) | In-combat regen reads; a rate-from-aura model for the base rate |
| **Usability** (`C_Spell.IsSpellUsable` + `insufficientPower`) | HS, Rend, Thunder Clap: P in 200/200 legacy combat samples (`u_hs/p_hs`, `u_rd/p_rd`, `u_tc/p_tc`; `u_hs` false in 5, true in 195), never S | Gate spike: plain incl. proc-gated Overpower (Warrior) and Sinister Strike `insufficientPower` true x686 (Rogue energy). Catnip: usable follows Clearcasting | Usability and `insufficientPower` are plain in combat for every cost type (rage, energy measured; mana, focus assumed) and for proc-gated spells. It is the in-combat resource signal | measured (rage, energy, procs); mana/focus assumed | A usability probe per class; a secret branch for `insufficientPower` (keep as defensive code only) |
| **Cooldowns** | `cd_active` P 125/125 combat; `cd_start`, `cd_dur`, duration-object getters S 125/125 (`PR11`); GCD `isActive`/`isEnabled` P, `startTime`/`duration`/`modRate` S 71/71, `isOnGCD` P/nil (`PR4`); `SetCooldownFromDurationObject` ok, `SetCooldown(secret)` rejected; predicate `sC` true in combat / false out (legacy) | Catnip: same split (`isActive`, `isOnGCD` readable; start/duration/`modRate` secret; GCD spell 29515; `isActive and isOnGCD ~= true` is a real cooldown) | Ready/not-ready flags are plain for every spell in combat; remaining time is secret in combat and plain out of combat. Remaining time is tracked from our own casts and data, shown through duration objects, never `SetCooldown` with cooldown-table numbers | measured + consistent with Catnip | Per-class cooldown probes; a plain-number sweep path in combat |
| **Player auras** (buffs, procs) | not read directly. Predicates: `ShouldAurasBeSecret` true 200/200 combat, false 1,800/1,800 out (legacy `sA`); `C_Secrets.GetSpellAuraSecrecy` = 2 (contextually secret) for Heroic Strike, Rend, Overpower and Thunder Clap, as are their cast and cooldown secrecy (`runs[13].secrecy.aura_*`, read at session start); `UNIT_AURA` fires in combat, unit plain | Catnip: no Druid aura readable in combat (`ShouldSpellAuraBeSecret` true for every spellbook spell; `GetPlayerAuraBySpellID` nil; `addedAuras`/`auraInstanceID` secret) | Own auras are secret in combat for every class: decisions use tracked state (our casts, `UNIT_AURA` as a timing hint, AuraContainer presence for display). Out of combat they can be read and used to re-sync | consistent with Catnip; the Warrior's predicate and secrecy levels match | Aura-secrecy probes per class; a Clearcasting-style read through the aura (use the readable cost: `GetSpellPowerCost` = 0, Catnip/spec §3) |
| **Target auras** | not probed this session (`sA` true in combat) | Gate spike (Warrior): `GetAuraDataByIndex` errors in combat ("Auras cannot be accessed when secret while tainted"), `GetAuraDataBySpellName` nil with Rend up; Catnip: same | Target debuffs and DoTs cannot be read in combat by any class; DoT up/remaining is tracked from our casts; display only through AuraContainer | measured (gate spike) + consistent with Catnip | A target-aura probe on any later class; per-class debuff-duration reads |
| **Range** | melee spells (`range_rd`, `range_ch`), actions (`actRange_*`), `ACTION_RANGE_CHECK_UPDATE` payload, `CheckInteractDistance`: P in combat; Heroic Strike in range at any distance (87/87); swing range nil, `UnitInRange` S (`PR7`) | Catnip: `C_Spell.IsSpellInRange` seen, `C_SwingTimer` range checks seen (untested) | `IsSpellInRange`/`IsActionInRange` are plain in combat for targeted abilities; nil without a target. On-next-swing abilities (Heroic Strike measured; Cleave, Maul, Raptor Strike assumed) always answer "in range" so they must declare a real range spell. Swing range and `UnitInRange` are unusable | melee spells measured; caster spell ranges **assumed**; on-next-swing for Maul/Cleave/Raptor Strike assumed | Per-class melee-range probes; the swing-range API |
| **Swing events** | `PLAYER_SWING` P in combat (duration 2.2/2.5, type 0/1; 77 events); same-frame `UNIT_POWER_FREQUENT/UPDATE` bursts (`PR3`) | Catnip: `PLAYER_SWING(duration, slot)` readable (Cat 0.99 s, Bear 2.475 s); gate spike n/a | Every melee class gets exact per-hand swing anchors from `PLAYER_SWING` (type 0 main hand, 1 off hand); the swing duration already includes haste. The ranged (auto shot) hand was not measured | measured (Warrior MH/OH) + consistent with Catnip (Druid cat/bear); ranged hand assumed | A pseudo-swing model for melee classes; swing-time probes per class |
| **Attack speed, damage, haste, AP** | `UnitAttackSpeed/Damage/AttackPower/RangedDamage`, `GetHaste`, `GetMeleeHaste`, `UnitSpellHaste`: **P out, S in combat**; `ShouldUnitStatsBeSecret()` P true/false tracks it (`PR2`, `PR4`) | Catnip: "can't scale anything to the GCD or attack speed in combat" | Stat reads are plain out of combat and secret in combat for every class; cache out of combat; melee haste from the `PLAYER_SWING` duration, caster haste from own cast times (`PR9`, plain) and GCD cadence | measured + consistent with Catnip | In-combat stat/haste probes; reading haste from a buff |
| **Cast timing** | own `UnitCastingInfo`: start, end (ms), spell id, castGUID, castBarID, `notInterruptible`: P in combat (Slam, 1.5 s); `ShouldUnitSpellCastingBeSecret("player")` false; events START/STOP/INTERRUPTED/FAILED/SUCCEEDED plain; target flag true (`PR9`, `PR8`) | Catnip: player cast info "unverified" (ThreatPlates treats start/end as secret) | The player's own cast times are exact for every class; the target's cast info is flagged secret (unobserved). Channels: untested | own casts measured; target casts: flag only; channels assumed | A fallback to cast-time data for the player's own cast end (keep as defensive code); the secret-end handling for own casts |
| **Target facts** | exists, can-attack, enemy, player, dead, tap, classification, level, creature type/id, GUID, name, threat: P in combat; health, max, percent S always; `UnitInRange` S; identity/threat flags P false (`PR14`) | Gate spike: `UnitIsUnit` plain, `CanCompareUnitTokens`; target health S always | Target identity, level, classification, threat and flags are plain in combat for every class (unit APIs are class-independent); health and `UnitInRange` are secret. Boss-only (level -1/`worldboss`) untested | measured (class-independent APIs); boss detection assumed | Per-class target-fact probes |
| **Nameplates** | **no data** (0 plates in all sessions, `PR6`) | none | none: do not extrapolate | unknown | nothing: re-run with plates on |
| **Game errors** | `UI_ERROR_MESSAGE` errorType and text P in combat, ids 57/62/359/402 (`PR17`) | Gate spike: 402 and 62 plain (group functions too) | Error ids and texts are plain in combat for every class; the same mechanism is expected for energy/mana errors and the Druid's "must be behind" | measured (4 ids) + gate spike; other ids assumed | Per-class error-readability probes |
| **Talents** | `C_Traits` walk: 52 nodes, 0 secret, 0 errors, identical in and out of combat (`PR5.walkO/walkC`); ladders and point APIs unusable | Catnip: n/a (the forever-talent API lead is `2026-10-13-forever-talent-api-lead.md`) | The tree walk works in combat for every class (the API is class-independent; the trees differ). Read ranks from the walk, never from `IsPlayerSpell` ladders | measured (Warrior); other classes assumed (D re-measures on the Druid tree) | Ladder-based rank inference; a user-declared talents setting as the default path |

**Not safe to extrapolate**

- **Combo points.** The Warrior has none (`upc`/`cp` are 0 plain in all 2,000 legacy samples, no information). The Rogue follow-up of the gate spike read `GetComboPoints('player','target')` plain 0–5 in combat; this run adds `C_Secrets.GetPowerTypeSecrecy(ComboPoints)` = 0 (never secret) next to `...(Energy)` = 2 (`runs[13].secrecy.powerCombo/powerEnergy`) and `ShouldUnitPowerBeSecret(player, ComboPoints)` false (legacy `sCP` 2,000/2,000). Catnip's matrix says `UnitPower(ComboPoints)` is readable but Blood in the Water found it secret in combat, and that the count is per-target and does not reset when the target dies. The Druid session (legacy keys `cp`, `upc`, `sCP`, in cat form) must settle this; do not build on combo points as plain for the Druid until then.
- **`GetShapeshiftForm` / form state in combat.** The Warrior's stance read plain in combat (`GetShapeshiftFormID` = 17, 200/200 combat samples, legacy `ff`; `PR10.bonusOffset` 1), but Druid forms are auras (Catnip: no Druid aura readable in combat) and a stance is not a form aura. Session D must record `ff`, `powerType` and `bonusOffset` while shifting in combat.
- **Pets, totems, items.** Pet: nothing to read (PR12); `GetTotemInfo` and `UnitHealth("pet")` came back secret on empty slots; item cooldown and use were never exercised (PR13). Treat all three API families as unknown.

**What Phases 3–6 can assume without a probe**

1. Resource numbers are never readable (rage, energy, mana, assumed focus); anchors come from `IsSpellUsable` flips and display from `UnitPowerPercent` curves on 0–1 fractions. Max and type are plain; regen rates are cached from an out-of-combat read.
2. `IsSpellUsable` and `insufficientPower` are plain in combat for every class and cost type, procs included (Warrior and Rogue measured).
3. Cooldown ready/not-ready (`isActive`, `isOnGCD`, GCD `isActive`) is plain in combat; times are secret in combat and plain out; sweeps use duration objects, never `SetCooldown` with secret numbers.
4. The player's own casts (start, end, spell id, castGUID) and `UNIT_SPELLCAST_*` payloads are plain in combat; channel behaviour still needs the Druid session.
5. Haste, attack speed and damage are never read in combat; melee uses the `PLAYER_SWING` duration, casters use their own cast times.
6. Own and target auras are unreadable in combat; DoT and buff state is tracked from our casts. No further aura probes.
7. `IsSpellInRange`/`IsActionInRange` and `ACTION_RANGE_CHECK_UPDATE` are plain in combat for targeted abilities; on-next-swing abilities carry a real range spell; the swing-range API and `UnitInRange` are out.
8. Target identity, level, threat and flags are plain in combat; target health is secret always (Phase 5 roots can mark `target.health` unreadable).
9. `UI_ERROR_MESSAGE` payloads are plain; id 57 needs text matching.
10. The `C_Traits` walk gives talent ranks in combat; the points API and rank ladders are dead.
11. `InCombatLockdown()` is false inside `PLAYER_REGEN_DISABLED` handlers: use the event, not the flag.
12. Still open: combo points, forms, channels, mana/energy max, nameplates, pets, totems, items, target casts, proc glow.

## 5. Summary

| Probe | Verdict | One-line fact |
|---|---|---|
| PR1 | partial | `IsCurrentSpell`/`IsCurrentAction` plain in combat (124/124); a queued strike was never captured |
| PR2 | answered | Attack speed, damage, AP secret in combat, plain out; `ShouldUnitStatsBeSecret()` is a plain flag |
| PR3 | answered | `PLAYER_SWING` plain per hand (2.2/2.5 s, 77 events) with same-frame rage events; swing-range API returns nil |
| PR4 | answered | Haste and GCD length secret in combat; GCD `isActive`/`isOnGCD` plain |
| PR5 | answered | `C_Traits` walk readable in combat, identical to out of combat (52 nodes, 0 secret) |
| PR6 | no data | Zero nameplates in all sessions (plates off); threat events plain |
| PR7 | answered | `IsSpellInRange`, `IsActionInRange`, range event plain; Heroic Strike always in range; swing range nil, `UnitInRange` secret |
| PR8 | partial | `ShouldUnitSpellCastingBeSecret("target")` true even at rest; no target cast observed |
| PR9 | partial | Own Slam (1.5 s) start/end plain in combat; no channel tested |
| PR10 | answered | Bindings and slot spells plain in combat; Heroic Strike lives on bonus-bar slot 74 |
| PR11 | partial | Duration object drives a Cooldown in combat; `SetCooldown(secret)` rejected; no proc glow seen |
| PR12 | no data | Warrior has no pet or totem; empty `GetTotemInfo` slots are secret in combat |
| PR13 | partial | Item reads plain in combat but no running item cooldown, potion or trinket |
| PR14 | answered | Target identity and threat plain; target health, speed and `UnitInRange` secret |
| PR15 | partial | One class spec (id 1491); no switch observed |
| PR16 | partial | Rage current secret always, max plain 100, regen plain only out of combat; mana/energy for D |
| PR17 | answered | `UI_ERROR_MESSAGE` ids 57/62/359/402 and texts plain in combat |
| PR18 | partial | Loss-of-control data plain in combat; tooltips readable out of combat only tested |
| PR19 | partial | All launcher, menu and fade pieces exist; `/fprobe menu` not run |
| PR20 | answered | Secret curve result into `SetAlpha` works in and out of combat; curve domain is 0–1 |
| PR21 | partial | `SetAlpha(secret)` on a Cooldown-holding frame is accepted; frame never faded, no visual |
| PR22 | answered | Plain `SetCooldown(GetTime(), 10)` works in combat |
| PR23 | partial | All nine Edit Mode atlas pieces resolve; no visual note |
| PR24 | partial | `SetGradient` alpha and colour ramps succeed; no visual note |
| PR25 | answered | Spike builds 115 regions in 4.8 ms, 27 KB |
| PR26 | answered | Glide OnUpdate 0.069 ms average, 0.562 ms worst; fps comparison confounded |
| PR27 | answered | User saw no gap or overlap at the cap; measured max gap 11.9 px, average 0.28 px (flag) |
| PR28 | answered | `SetCooldownFromDurationObject` works in combat; 56 B per `GetSpellCooldownDuration` call |
| PR29 | no data | No note on the icon-strip bar colour |
| PR30 | no data | No note on sweep legibility at 20 units |

Counts: **14 answered, 12 partial, 4 no data** (halo, a runbook extra row, is answered: clean at 0.8, 1, 1.2).

## 6. Still needing the Druid session (D) or a re-run

**Needs the Druid session (D):**
- PR9 channels (Tranquility, Hurricane: end time, `CHANNEL_UPDATE`, `DELAYED`), PR16 mana/energy max and regen, PR17 "must be behind" and energy/mana errors,
  PR15 dual-spec switch, PR5 Druid tree walk, PR10 form bonus-bar slots, PR1 Maul queue, PR3 cat/bear swing and rage-less swings, combo points and form state in combat, PR7 caster and Maul ranges (D's range list has no Maul), PR6 nameplates in cat.

**Needs a re-run (either session):**
- PR1 (queue a strike five times and note it), PR6 (enemy plates on), PR8 (a casting mob and an interrupt), PR11 proc glow (Overpower after a dodge or a Druid proc), PR13 (a potion, a trinket),
  PR18 tooltips in combat, PR19 (`/fprobe menu`), PR21 (with the 0–1 curve), PR23/PR24/PR29/PR30 (visual notes), the spike shown during combat (PR26 frame rate, PR27), PR12 on a pet or totem class.
- Probe fixes before D (not made here): keep per-value counts or a change log for booleans (PR1's queued `true` is invisible in tallies and rings), keep a longer ring or a combat-window ring, fix PR5's `ips[].isps` and/or idiom (`ok and Enc(v) or ErrText(v)` turns a plain `false` into `E:false`), use the 0–1 curve on PR21,
  add Maul to D's range list, and note which gold square went dark in PR20.
