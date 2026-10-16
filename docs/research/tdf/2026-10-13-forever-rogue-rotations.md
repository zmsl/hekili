<!-- Ported from TacoDogForever docs/research/2026-10-13-forever-rogue-rotations.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# WoW Forever rogue: rotations, mechanics and a pack design (2026-10-12)

Research for a Rogue class pack (Combat, Assassination, Subtlety). Sources are Forever-beta guides (client 1.60.1,
Interface 16001, level cap 30 since 2026-10-01), Blizzard's own Rogue deep dive (2026-10-07), Forever's DB2 (build
1.60.1.70338: the shared data addon `TacoDogForeverData.ROGUE`, plus the raw SQLite at
`~/.local/share/wow-db2/forever/current.sqlite` for descriptions and effects), and Hekili's classic rogue APLs
(`origin/classic`, read for priorities only). Level 60 is not open in the beta; every level-60 build below is
theorycraft. Launch is reported for 2026-11-04 (not confirmed by Blizzard in anything I could read).

Tags on claims: **F** Forever-verified (Blizzard post, DB2 text/effects, or two or more independent Forever sources),
**V** vanilla-assumed (Forever says nothing; Classic Era behaviour carried over), **I** inferred (my reasoning from the
mechanics, no source). Each §3 subsection states its confidence.

## 1. What Forever changes about the rogue

Baseline (Blizzard 2026-10-07, read via its Blizzard News page, MMO-Champion and Warcraft Tavern; all **F**):
- **Energy regenerates continuously**, not in 2 s ticks of 20 (Blizzard's 2026-09-30 class highlights per
  classicwow.gg; Thundrael's addon issue 2026-09-19 saw the bar move "fluidly"). **No rate was published.** The 10/s
  of Classic (20 per 2 s) is the natural guess. Adrenaline Rush doubles it for 15 s (DB2 13750: +100%). **F** on
  continuous, **I** on 10/s.
- **Combo points stay on their target when you change targets**; they clear only when you start building on a different
  enemy. A missed Expose Armor no longer costs the combo points (2026-10-01 notes). `GetComboPoints("player","target")`
  is a plain 0-5 in combat (our Rogue spike, 2026-10-11). **F**
- **Weapons:** rogues can equip one-handed axes. Dagger/Mace/Sword/Fist Weapon Specialization are removed; **Hack and
  Slash** (Combat row 5, 5 ranks) replaces them: Sword/Axe 5% extra attack, Dagger/Fist +5% crit, Mace ignores 15%
  armor (DB2 13960; classicwow.gg). **F**
- **Poisons** carry more charges (Instant I 60 vs 40, Deadly I 90 vs 60 per classicwow.gg), scale with Attack Power, and
  can sit on a weapon with a Sharpening Stone or Weightstone. Learned from a level-20 class quest chain (Mmonster). **F**
- Feint's threat reduction doubled. Sap no longer breaks Stealth. Distract also lowers enemy stealth detection for 10 s.
  Expose Armor now matches five Sunder Armors; it no longer blocks Sunder, and Sunder won't overwrite it unless its
  own effect is weaker. **F**

Assassination (all **F** unless marked):
- **Mutilate (new, 21-point talent):** 60 energy, instant, both weapons must be daggers, 2 combo points, +20% damage
  against Poisoned targets, each hand can proc, Seal Fate triggers once if either hand crits. DB2 1310707 (rank 1),
  399956 (rank 2, the SoD rune ID reused), 1241582, 1241584; ranks 2-4 at levels 40/50/60 (SpellLevels). The text has
  **no "must be behind" clause**: Assassination needs no positioning.
- **Venom (new, 31-point talent):** 25 energy finisher, a self buff: Poison damage +30%, poison application chance
  +10%, lasting 9/12/15/18/21 s for 1-5 points (DB2 1310703, duration index 185 = 6 s + 3 s per point). Learned at
  level 40. Cold Blood cannot crit it (no damage). Blizzard's stated intent: "Assassination focuses its finishers on
  maintaining Venom and Slice and Dice", damage finishers (Rupture, Eviscerate) are lower priority.
- Cold Blood moved to 16 points and also affects Mutilate (next Sinister Strike/Backstab/Ambush/Eviscerate/Mutilate,
  +100% crit, 3 min). Seal Fate no longer needs Cold Blood. Vigor is a 2-point row-5 talent (+5/+10 max energy; DB2
  14983 +10 on the old single rank). Improved Poisons: +2%..+10% application and 10%..50% chance a proc keeps its
  charge. Improved Expose Armor: -5/-10 energy and refunds 1/2 combo points when cast at 5. Remorseless Attacks,
  Lethality (smaller bonus) and Opportunity now cover Mutilate; Malice's crit applies to all attacks and Poisons.
- **Coup de Grace (new, DB2 1310709):** Eviscerate +2% per Deadly Poison application on the target (the poison stacks
  to 5, so +10%); Leprestore (2026-10-04/05) lists it as a Combat/Assassination passive. Absent from Blizzard's
  2026-10-07 deep dive and every other guide; it is in the 70338 build's DB2, so it arrived later. **F** (DB2) on
  existence and value, **I** on how it is learned.

Combat:
- **Flawless Execution (new, 16-point):** Eviscerate costs 10 less energy (DB2 1310711). Eviscerate is 35 energy
  otherwise, 25 with it. It does not discount Slice and Dice, Venom, Rupture or Expose Armor.
- **Hack and Slash** above; **Weapon Expertise** now cuts the target's dodge/parry chance (1%/2%); Aggression also
  covers Backstab; **Puncturing Wounds** (was Improved Backstab: Backstab +10/20/30% crit, Mutilate +5/10/15% crit,
  Backstab 15/30/45% to add a combo point; DB2 1224716). Improved Eviscerate moved here (+7/13/20%).
- Blade Flurry: 25 energy, 2 min, 15 s, melee speed +20% and hits one additional nearby enemy (DB2 13877: the
  speed bonus applies against one target too). Adrenaline Rush: 5 min, 15 s, energy regeneration +100%; needs 31
  points, so **Adrenaline Rush and Mutilate/Venom never fit one 51-point build**.

Subtlety:
- **Hemorrhage:** 35 energy, 100% weapon damage (145% with a dagger), 1 combo point, target takes **+15% Rupture damage
  from you for 15 s** (DB2 16511 effect 271). **Thousand Cuts (31-point, requires Preparation):** each Rupture tick
  makes the next Hemorrhage or Backstab within 10 s cost 3 less, up to 5 stacks (DB2 1310721/1310723, cumulative 5).
  **Quietus** (row 6, needs Dirty Deeds): Sinister Strike, Ghostly Strike and Hemorrhage +2%..+10% below 35% target
  health (DB2 1310728). **Cutthroat** (row 6): Backstab 3%..15% to make the next Ambush within 10 s need no Stealth
  (DB2 424980 teaches 462708, aura 462707). **Premeditation** is a 16-point talent, no Stealth needed, +2 points, 20 s,
  2 min cooldown (DB2 14183). Dirty Tricks (was Improved Sap): Sap/Blind -25%/-50% energy. Serrated Blades: armor %
  and Rupture +10/20/30%. Removed: Sleight of Hand, Deadliness. **Death Mark replacing Thousand Cuts** as the 31-point
  talent is reported by one guide ("announced 2026-10-01") and not in the beta client or any Blizzard text I could
  read: **low**, flagged in §10.
- Rupture lasts 6 s + 2 s per point (8-16 s, ticks every 2 s; DB2 duration index 553, effect period 2000 ms).

What did **not** change or does not exist (unlike Druid's Shifting Power surprise): there is no new baseline rogue
ability. Forever's DB2 still carries Season of Discovery rune spells with `SpellLevel 1 / BaseLevel 0` (Saber Slash
424785, Main Gauche 424919, Quick Draw 398196, Between the Eyes 400009, Blade Dance 400012, Poisoned Knife 425012, Shiv
424799, Shadowstrike 399985, Shuriken Toss 399986, Redirect 438040, `engrave_*`). No Forever guide, patch note or
Blizzard text mentions engraving or any of them (wow.gg, 2026-10-01: combo points "can't be transferred to a new one yet"). **Treat as
unavailable (I); the pack ignores them**, like the warrior pack ignores runes.

Data addon gaps the pack author must know (`src/TacoDogForever_Data/Generated/Spells.lua`, `ns.ROGUE`):
- It has **none of Forever's new talents** (Flawless Execution 1310711, Coup de Grace 1310709, Thousand Cuts
  1310721/1310723, Quietus 1310728, Cutthroat 424980/462707/462708, Puncturing Wounds 1224716, Dirty Tricks 1224782,
  Hack and Slash 13960, Vigor 1310708). The generator reads the stale `Talent` table (it still lists Sleight of Hand,
  Deadliness, Improved Sap, TBC Weapon Expertise IDs). Use this document's IDs (all checked against `SpellName`) or
  add them to `tools/data/overrides.json`.
- `duration` of Slice and Dice, Rupture, Venom (6) and Kidney Shot (1) is only the base of a per-combo-point formula:
  use `base + k * combo_points` (§9).
- `families.json` makes Expose Armor and Sunder Armor `replace`. Forever says they coexist and the stronger wins
  (**strongest**): fix before a rogue pack registers Expose Armor.

## 2. Specs and the builds players run

The talent system: one point per level from level 10 (21 points at the 30 cap, 51 at 60), trees unlock gold-medal
talents at 11/16/21/31 points spent (Blizzard). Respec is at a class trainer. Dual spec at 40. **F**

| Spec | Level-30 build (21 pts) | Level-60 build (theory, 51 pts) | Source |
|---|---|---|---|
| Combat (swords/axes/any) | Improved Eviscerate 3, Improved Sinister Strike 2, Precision 3, Endurance 2, Deflection 3, Lightning Reflexes 1-2, Riposte, Flawless Execution, Dual Wield Spec 3-4, Blade Flurry | 18/33/0: those plus Dual Wield 5, Hack and Slash 5, Weapon Expertise 2, Aggression 3, Adrenaline Rush; the 18 Assassination points are Malice 5, Ruthlessness 3, Improved Slice and Dice 3, Relentless Strikes, Lethality 5, Cold Blood | Leprestore (2026-10-05), foreverdb builds #9-#12 (checked vs 70338), Mmonster |
| Combat (daggers) | Puncturing Wounds 3 replaces Lightning Reflexes/Deflection; Backstab builder, stay behind | rare; Hack and Slash gives dagger crit instead | foreverdb #8, #10 |
| Assassination (daggers) | Remorseless 2, Malice 5, Ruthlessness 3, Murder 2, Relentless Strikes, Lethality 5, Cold Blood, Mutilate: 21/0/0 | 36/13/2 or 38/11/2 or 39/12/0: Mutilate, Venom, Seal Fate 5, Vile Poisons 5, Improved Poisons 5, Vigor 2, Relentless Strikes, Cold Blood, Improved Slice and Dice 3, Improved Eviscerate/Puncturing Wounds/Precision | Leprestore (2026-10-04), Mmonster, classicwowforever.com |
| Subtlety (daggers) | Opportunity 2, Camouflage, Improved Ambush 3, Setup 3, Ghostly Strike, Initiative 3, Serrated Blades 3, Premeditation, Hemorrhage | 20/0/31: Thousand Cuts, Quietus 5, Hemorrhage, Preparation, Dirty Deeds 2, Premeditation (+Cutthroat variants); Hemorrhage Subtlety is the dungeon build, Preparation the PvP one | Mmonster, foreverdb #13-#18, classicwowforever.com (22/3/26) |

Which talents change the rotation (the pack needs each as a **setting**, because `talent.*` is unreadable on Forever;
`C_SpecializationInfo.GetTalentInfo` and `IsPlayerSpell` on the passive IDs are probes, §10):
- **Improved Slice and Dice (0-3):** SnD duration x(1 + 0.15 x rank), DB2 14165. Changes how long a SnD lasts, so the
  refresh model.
- **Slice and Dice rank:** +20% attack speed before level 42, +30% from 42 (DB2 5171 vs 6774; SpellLevels 10/42). The
  player's level selects it (`UnitLevel("player")` should be plain; confirm).
- **Flawless Execution:** Eviscerate 35 -> 25 energy. **Improved Sinister Strike:** 45 -> 42/40. **Thousand Cuts** stacks
  (-3 each, up to -15). **Vigor:** max energy 100 -> 105/110. **Relentless Strikes:** 20% per point to refund 25
  energy (certain at 5 points). **Seal Fate / Ruthlessness / Puncturing Wounds:** extra combo points on crit/finish/
  Backstab (stochastic; the combo-point read corrects the belief within a frame).
- **Venom, Mutilate, Blade Flurry, Adrenaline Rush, Cold Blood, Hemorrhage, Premeditation, Ghostly Strike, Riposte** are
  spells: core's spellbook check ("unknown means never ready", spec §5.3) already skips them. `detect`: Mutilate
  (1310707) known -> Assassination; Hemorrhage (16511) or Ghostly Strike (14278) known -> Subtlety; else Combat (the
  1-29 default and the sword build).

## 3. Single-target priority

### 3.0 Shared machinery (all specs)

- **GCD is a fixed 1.0 s** for every energy ability (DB2 `StartRecoveryTime` 1000; Distract 1.5). Not hasted. Cold
  Blood, Riposte, Evasion, Sprint, Vanish, Stealth, Premeditation are off the GCD.
- **The rogue is energy-bound, not GCD-bound.** At 10 energy/s a 40-60 energy builder is affordable every 4-6 s while
  the GCD allows one every second. So "pooling" is not a mode: the engine already waits for the cost. The real
  decisions are (a) which spender, and (b) never letting a **builder's energy starve a maintenance finisher** whose
  buff is about to fall off (§6 `excess_e`).
- **Slice and Dice is the biggest damage button** (+20%/+30% melee speed, DB2; every guide agrees). Duration
  `(6 + 3 x points) x (1 + 0.15 x Improved SnD)` seconds: with 3/3, 13.1/17.4/21.8/26.1/30.5 s for 1-5 points; with 0/3,
  9/12/15/18/21 s. Cost 25 energy. **Re-casting replaces the remaining time (no carry-over) (V; probe).** Refresh
  rules the guides give: "refresh at 5 points just before it expires" (foreverdb #2; Warcraft Tavern's Classic guide:
  finishers only at 5 points; Hekili classic Combat: 5 points with under 3 s left),
  "keep it up always" (wowtbc.gg combat), "use it on durable targets only" (Leprestore, wow.gg).
- **Relentless Strikes** makes a **5-point finisher return 25 energy for certain** (20% per point): SnD, Venom, Rupture
  then cost nothing net, Eviscerate 10 (0 with Flawless Execution). That is why every guide spends at 5.
- **Energy budget (I):** 10 energy/s is 600 a minute. Sinister Strike makes a point for 40-45, Mutilate for 30.
  Keeping Slice and Dice up costs one 5-point finisher per 30 s (21 s of buff x 1.45), Venom one per 21 s. A minute
  of Assassination affords about 18 points (3.6 finishers) against the 4.9 finishers SnD and Venom want, so some
  refreshes will be at 3-4 points and Seal Fate, Ruthlessness and Relentless Strikes refunds close part of the gap:
  **Eviscerate is a spare, not a staple**, which is exactly Blizzard's stated design. Combat has ~13 points a minute
  and needs 10 for SnD alone. Adrenaline Rush adds 150 energy per 5 min.
- **Eviscerate vs Rupture:** Rupture costs 25 (Eviscerate 35, 25 with Flawless), lasts 16 s at 5 points and does more
  total damage than Eviscerate if the target lives (Warcraft Tavern Classic guide: "does more damage but uses a debuff
  slot"). Rupture is a bleed: Combat/Assassination ignore it (no Forever guide uses it outside Subtlety, where
  Hemorrhage +15%, Serrated Blades +30% and Thousand Cuts feed it). Use Rupture only when the target will outlive
  most of its 16 s (**I**: needs a fight-length signal; `time_to_die` is unavailable, so `settings.boss`).

### 3A. Combat (swords, axes, daggers)

Sources agree (wowtbc.gg, Mmonster trainer L20 and L60, Leprestore, foreverdb, Hekili classic): **F** for the loop,
**I** for thresholds.
1. Slice and Dice is down, 2+ points: cast it. (A fight under ~8 s does not repay 25 energy + 2 points, but the pack
   cannot see fight length; Hekili's classic Combat APL does not either. `settings.boss` is not consulted here.)
2. Slice and Dice has 3 s or less left: refresh with 2+ points; with 1.5 s or less, with any point. At 5 points refresh
   up to `early_refresh` (default 6 s) early rather than idle at the point cap (foreverdb: "refresh at 5 points
   just before it expires").
3. Adrenaline Rush (cooldowns toggle): right after SnD, when energy is below ~50, so the doubled regeneration is
   not wasted at the cap (Mmonster, classicwow.gg "do not activate at full energy"). It adds 150 energy over 15 s.
4. Blade Flurry (cooldowns toggle): on cooldown. Single target it is still +20% speed for 25 energy (DB2); against
   two or more it also cleaves (Mmonster opener: Sinister Strike, SnD, Adrenaline Rush, Blade Flurry).
5. Riposte when the game says it is lit (after a parry; 10 energy, 6 s, off GCD, 150% + disarm). Needs a usability gate
   (same mechanism as the warrior's Overpower). Leveling build only.
6. Eviscerate at 5 points (4 in a short fight) when SnD has more than `early_refresh` left. Rank 9 (DB2 31016) is 108
   + 170 per point before attack power, Improved Eviscerate and Aggression; cost 25 with Flawless Execution.
7. Builder: Sinister Strike (40 with Improved SS 2/2, 45 base, 1 point). Backstab only with `settings.backstab`
   (main-hand dagger and behind the target; the game cannot tell us we are behind, §6).
Why: SnD uptime and AR/BF alignment are worth more than which finisher; Hack and Slash and Dual Wield scale with
swings, which SnD and BF multiply. Rupture and Expose Armor are not in the Combat loop. **Confidence: high** for the
loop (four independent guides), medium for the 3 s / 6 s thresholds.

### 3B. Assassination (Mutilate daggers)

Forever-specific and brand new; sources disagree on Venom (wowtbc.gg and Blizzard want it maintained; the Mmonster
trainer's level-60 bar omits it; Leprestore's level-30 notes predate it being reachable). **Medium.**
0. Cold Blood is off the GCD, so it leads the list (see 3).
1. Slice and Dice down, 2+ points: cast. Refresh at 3 s with 2+ points (1.5 s with any); at 5 points up to
   `early_refresh` early.
2. Venom (level 40+, setting `venom`): not up and 3+ points: cast. Refresh at `refresh_window` (3 s) with 4+ points;
   at 5 points up to `early_refresh` early, **after** Slice and Dice. SnD lasts up to 30 s and Venom up to 21 s;
   "keep them from expiring together" (classicwow.gg) is satisfied by SnD taking the 5-point slot first.
3. Cold Blood (cooldowns toggle): on cooldown with SnD up and at most 2 points, so the next Mutilate is a guaranteed
   crit (Seal Fate then adds a point) (Mmonster: "Cold Blood right before Mutilate"; wowtbc and Leprestore: not on a
   dying target). Or before a 5-point Eviscerate in a short burn.
4. Eviscerate at 5 points only when SnD and Venom both have more than `early_refresh` left (wowtbc.gg: "Eviscerate only
   if it won't delay Venom or Slice and Dice"). Mmonster allows 4 points because Mutilate gives 2 (see 5).
5. Builder at 4 points: **Sinister Strike**, not Mutilate (Warcraft Tavern: SS "adds the last combo point when that
   saves energy"; 45 vs 60 energy and no wasted point). At 0-3 points: **Mutilate** (60 energy, 2 points: 30 energy
   per point against SS 45, so Mutilate is the efficient builder). Below level 30 or without two daggers: SS.
6. Deadly Poison stacks (Coup de Grace, 5 stacks, 12 s debuff, tick 3 s) cannot be read; Eviscerate is not held for
   them. The "Poisoned target" bonus on Mutilate is ignored: Mutilate is the only efficient builder either way.
Why: Blizzard's design makes poison uptime the damage engine; the two self-buff finishers buy poison damage and
speed, and a 5-point refresh pays its own cost back through Relentless Strikes. Poisons themselves (weapon enchants
applied from items) are not recommendable abilities; the pack leaves them to the player (probe
`C_Item.GetWeaponEnchantInfo`, §10).

### 3C. Subtlety (Hemorrhage / Backstab daggers)

Guides disagree more than for any other spec (the Sub rotation in wowtbc.gg lists nine steps with no thresholds; the
Mmonster trainer ranks Rupture above Hemorrhage yet says Rupture follows it). **Low-medium.**
1. Slice and Dice down, 2+ points: cast; refresh as 3A (wowtbc.gg lists it first; Warcraft Tavern: Sub "splits points
   between Rupture and SnD").
2. Rupture at 5 points when `settings.boss` and Rupture has 2 s or less left (or is down with 4+ points). Hemorrhage
   first if its debuff is down: the order that pays is Hemorrhage, then Rupture (Mmonster: "Rupture right after
   Hemorrhage", +15% for 15 s covers the first 15 of Rupture's 16 s).
3. Hemorrhage whenever its debuff is down or has 2 s or less left (it doubles as a 1-point builder at 35 energy).
4. Premeditation (cooldowns toggle): at 2 points or fewer (wowtbc: below 4); free 2 points in or out of Stealth.
5. Eviscerate at 5 points when Rupture is up or `settings.boss` is off; the Sub "cut short" rule (foreverdb #16: 5-point
   Rupture on long-lived targets, Eviscerate on trash).
6. Ambush when Cutthroat has procced (aura 462707, 10 s, one charge) or in Stealth; needs a dagger and behind.
7. Ghostly Strike on cooldown (40 energy, 20 s, 180% dagger, +15% dodge, 1 point).
8. Builder: Backstab (60) with `settings.backstab`/`group`, else Hemorrhage (35). **I:** per energy Backstab's flat
   bonus keeps it level with Hemorrhage per energy at current gear, and Thousand Cuts discounts whichever of the two
   is cast next, so it does not separate them. wowtbc.gg itself says "it's unclear whether Sinister Strike or Backstab will be stronger".
Premeditation/Preparation/Vanish loops are PvP-flavoured and left to the toggle. Thousand Cuts (stacks readable if
player auras are readable in combat) makes the next Hemorrhage/Backstab 3 energy cheaper per Rupture tick: **do not
wait at full energy for five stacks** (classicwow.gg).

## 4. AoE

- **Blade Flurry is the only rogue AoE**: one additional nearby target (so two targets). No Forever rogue guide lists
  another (Fan of Knives and Crimson Tempest are SoD runes, unavailable). `active_enemies` (nameplate count) switches
  the **display mode**, not the rotation: at 2+ enemies Blade Flurry is recommended even with `bf_single` off (and
  Adrenaline Rush with it); the loop is otherwise unchanged. **F** (Mmonster L60 Combat, wowtbc, DB2).
- Combat: the same list; Blade Flurry with Adrenaline Rush on packs. Keep Sap/Gouge targets out of cleave
  ("not near Sapped or Gouged targets", foreverdb #10/#12).
- Subtlety with 3+ long-lived targets: Rupture on each (`active_dot.rupture < active_enemies`) **I**; no source.
- Assassination: nothing. Poisons proc per hit; Blade Flurry would be the only extra, and it cannot share a build
  with Venom (31 + 21 points exceeds 51; Leprestore).
- Switch point: 2 enemies. **High** that it is 2 (Blade Flurry's cap); **I** for the Sub Rupture spread.

## 5. Cooldowns, defensives, interrupts

Toggle mapping (core's `cooldowns`, `custom1`, `custom2`; the ability's `toggle` field keeps it out of the APL text):

| Toggle | Abilities | Why |
|---|---|---|
| `cooldowns` | Adrenaline Rush (300 s), Blade Flurry (120 s), Cold Blood (180 s), Premeditation (120 s), Preparation (600 s) | burst behind the toggle (our choice; Hekili's classic rogue APL leaves them ungated) |
| `custom1` (name "Interrupts") | Kick (10 s, 25 energy, 5 s school lockout, Improved Kick: 50/100% for a 2 s silence) | no interrupt toggle exists yet (reconciliation A35); until `target.casting` exists it is an opt-in "kick now" |
| `custom2` | Expose Armor (25 energy, 30 s, 5 points, now ~5 Sunder stacks), Kidney Shot (20 s) | opt-in utilities |
| never recommended | Evasion (300 s, -30/-60% with Endurance), Sprint, Vanish (300 s; Elusiveness -45/-90 s), Feint (10 s, 20 energy), Gouge (10 s, 45), Blind, Sap, Riposte (lit gate) | no health observation; the player decides |

Interrupts: **Kick is the rogue interrupt on Forever** (every guide; DB2 1766-1769, 15..80 damage by rank, interrupts
the school for 5 s). `kick,if=target.casting` is blocked until PR8 (`UnitCastingInfo("target")` and target cast
events readable?) lands; draft §8 leaves it commented. Gouge (stop melee, 4 s) and Kidney Shot are the stuns.

## 6. Resources

**Energy (secret always, even out of combat; the belief reads it through usability flips).**
- Max 100; **105/110 with Vigor 1/2** (setting `vigor` 0-2; the resource max is static at registration, so default
  100 and accept ~5% overestimation, or build the max from the setting at load).
- Regeneration: `regen = 10` (linear, Classic's 20 per 2 s), until calibrated. Continuous on Forever, so **no tick
  model and no `tickGrid`** (spec §15 asks whether retail's 0.1 s grid applies; at most 0.1 s of error). Keep the
  linear fast path (`resAtLinear`) by not adding `models` for the base rate.
- **Adrenaline Rush** doubles it for 15 s: a `models` entry gated on its aura, `{ interval = 0.5, value = 5, aura =
  buff.adrenaline_rush }`, as the warrior pack models Bloodrage (cost: the forecast path is slower than linear).
- **Relentless Strikes:** +25 energy after a finisher: certain at 5 points, 20% per point below. Model only the
  certain part (5 points) and let the combo-point/usability reads correct lower counts.
- Cost modifiers a pack folds into `spend` functions: Improved Sinister Strike (-5), Flawless Execution (-10),
  Thousand Cuts stacks (-3 each, consumed by the next Hemorrhage or Backstab, `reads = { buff.thousand_cuts }`),
  Improved Expose Armor (-5/-10), Dirty Deeds/Dirty Tricks. Costs of all other abilities are the DB2 values in §9.
- No five-second rule, no pets, totems or shards. `rest` is the default (max): out of combat energy refills and a
  stealth opener starts at the cap.
- **The cost ladder is unusually rich:** costs of 20 (Feint), 25 (SnD, Rupture, Venom, Kick, Blade Flurry,
  Eviscerate with Flawless), 35 (Eviscerate, Hemorrhage), 40/45 (Sinister Strike, Ghostly Strike, Gouge), 50
  (Garrote), 60 (Mutilate, Backstab, Ambush, Cheap Shot). Each `IsSpellUsable` flip pins energy to a cost at that instant,
  so regeneration calibrates within a few seconds of play. **Caution:** a finisher with 0 combo points, a stealth
  ability out of Stealth, Mutilate without daggers and Riposte unlit may report "not usable" for a reason that is
  not power; the ladder must only use abilities whose other requirements hold (gate them as `Gates.lua` does).

**Combo points** (readable): max 5, per target, plain `GetComboPoints`. Gains: Sinister Strike/Backstab/Hemorrhage/
Ghostly Strike/Ambush/Garrote 1; Mutilate and Cheap Shot 2; Premeditation +2 (any time); Seal Fate (crit, 20% per
rank, 100% at 5), Ruthlessness (finisher), Initiative (opener), Setup (after a dodge, now current-target only),
Puncturing Wounds (Backstab) add more. Finishers spend all; Rupture, SnD, Venom, Eviscerate, Kidney Shot, Expose
Armor, Blade Dance. Because the read is exact each frame, the simulation only needs the deterministic gain.

**`excess_e` for the rogue (the Druid's, reused).** The Feral pack's `excess_e` (Druid `Expressions.lua`; Zachary
Samsel's Wrath logic) is the right shape: reservations = {Slice and Dice 25 energy, due when its buff ends; Venom 25;
Rupture 25} instead of {Rip, Rake}; the "spender" is the builder (Mutilate/Sinister Strike/Hemorrhage). A builder is
recommended only when `excess_e >= action.<builder>.cost`, so a Mutilate at 4 points is never cast if it would leave
Slice and Dice unaffordable at its expiry. Without it, "earliest ready wins" lets a ready builder beat a refresh that
is 2 s away from affording. Reservation due times come from the tracked buff expiry, so §7's accuracy bounds this.

**Timing.** There is no swing-based resource, so swing timers do not matter to the pack. Auto-attack speed matters only
through SnD/BF and poison procs.

## 7. Auras, procs and trackers

"Readable" = Forever lets addon code read it in combat. Player-aura reads in combat are **unverified** (the gate spike
says auras are secret in combat via `C_Secrets`; `FindPlayerAuraByID` was out-of-combat only; parity-2 H5/H7 and the
port-probes runbook PR2 `UnitAttackSpeed` ask).
Until probed, assume player auras are secret in combat and **track from our own casts** (the Warrior/Druid approach).

| Aura | IDs (DB2) | Where | Readable? | Inference if not |
|---|---|---|---|---|
| Slice and Dice | 5171, 6774 | player | probe; assume secret | cast time + duration `(6+3 cp)(1+.15 r)` from the combo points read just before the cast; `UnitAttackSpeed("player")` drops x1/1.2 or x1/1.3 while up (probe PR2) |
| Venom | 1310703 | player | same | cast + `6+3 cp` |
| Adrenaline Rush / Blade Flurry | 13750 / 13877 | player | same | cast + 15 s |
| Cold Blood | 14177 | player, 1 charge | same | cast; consumed by the next Mutilate/SS/BS/Ambush/Eviscerate (handlers remove it) |
| Stealth / Vanish | 1784-1787 / 11327 | player | `IsStealthed()` is a plain bool in the Forever API index | read it; Sap, Distract and Sprint do not break it (DB2 text), Premeditation is not documented as breaking it |
| Thousand Cuts | 1310723 (cumulative 5, 10 s) | player | same as player auras | +1 per our Rupture tick (every 2 s while Rupture is up), consumed by the next Hemorrhage/Backstab |
| Cutthroat proc | 462707 (10 s, 1 charge) | player | same | Backstab cast: 3%..15% chance; cannot be inferred; skip when unreadable |
| Remorseless | 14143 (20 s) | player | same | a kill; skip |
| Rupture | 1943..11275 | target | **no** (target auras secret) | cast + `6+2 cp`; hit confirmed by points spent; dropped on target swap (spec §20.3 per-target memory) |
| Hemorrhage debuff | 16511 | target | no | cast + 15 s |
| Deadly Poison (12 s, stacks 5) | 25349 (R5) | target | no | assumed present; do not model |
| Expose Armor | 8647..11198 | target | no | cast + 30 s |
| Riposte lit, Ambush/Garrote/Cheap Shot usable | n/a | game | **yes** via `C_Spell.IsSpellUsable` | a gate aura per ability (`Gates.lua`) |

Trackers worth writing: (a) a Slice and Dice confirmation using `UnitAttackSpeed` if readable; (b) a finisher
tracker: a finisher that leaves the combo points unchanged missed (needs Q9: "combo points after a missed finisher");
(c) a usability gate for Riposte and the stealth/weapon-gated abilities; (d) a Cold Blood consumption note.

## 8. Draft APLs (our dialect; settings, not talents)

Pack settings these use (`spec:RegisterSetting`): `boss` bool (default true; "target lives long enough for Rupture,
Venom, long buffs"), `refresh_window` num 3 (1-6), `early_refresh` num 6 (0-10; refresh a 5-point buff this early
rather than cap), `venom` bool true, `backstab` bool false, `bf_single` bool true, `min_finisher_cp` num 5 (3-5).
Abilities that carry `toggle = "cooldowns"` are never recommended with it off, so the lines need no `toggle.cooldowns`.
`dot.x`, `debuff.x`, `buff.x` accept the pack's aura keys; `action.x.cost` and `cooldown.x` are core names.

```
# Combat: Sinister Strike builder, Slice and Dice always, Eviscerate at 5, Adrenaline Rush + Blade Flurry on cooldown.
actions=call_action_list,name=stealth,if=buff.stealth.up
# Slice and Dice is the biggest button: cast it as soon as there are 2 points...
actions+=/slice_and_dice,if=!buff.slice_and_dice.up&combo_points>=2
# ...refresh it in the last seconds with whatever 2+ points we have (1 point in the last 1.5 s), so it never drops
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=settings.refresh_window&combo_points>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=1.5&combo_points>=1
# at 5 points refresh early rather than idling at the combo-point cap (Relentless Strikes pays 25 back)
actions+=/slice_and_dice,if=combo_points>=5&buff.slice_and_dice.remains<=settings.early_refresh
actions+=/call_action_list,name=aoe,if=active_enemies>1
# doubled energy regeneration for 15 s: only below 50 energy so none is wasted at the cap
actions+=/adrenaline_rush,if=buff.slice_and_dice.up&energy<50
# +20% speed (and a second target); on cooldown even on one target, because the speed bonus is real
actions+=/blade_flurry,if=buff.slice_and_dice.up&settings.bf_single
# lit after a parry (usability gate); 10 energy, off the GCD
actions+=/riposte
# spend 5 points (4 with min_finisher_cp) once Slice and Dice has time; cost 25 with Flawless Execution
actions+=/eviscerate,if=combo_points>=settings.min_finisher_cp
# dagger main hand and behind the target (group is the proxy, as Feral's Shred): Backstab builds
actions+=/backstab,if=settings.backstab&group&combo_points<5
# the builder: any weapon, no position needed
actions+=/sinister_strike,if=combo_points<5
# TODO(PR8): actions+=/kick,if=target.casting&toggle.custom1
# two or more enemies: Blade Flurry cleaves its second target; Adrenaline Rush follows it (both behind the toggle)
actions.aoe=blade_flurry,if=buff.slice_and_dice.up
actions.aoe+=/adrenaline_rush,if=buff.blade_flurry.up&energy<50
# the precombat list: Cheap Shot is the safe opener (no dagger, no position, 2 points); Ambush needs both
actions.stealth=ambush,if=group
actions.stealth+=/cheap_shot
```

```
# Assassination: Mutilate + Venom + Slice and Dice; Eviscerate only with spare points. Falls back to Sinister Strike
# below level 30 (Mutilate unknown) and to a Venom-less loop when settings.venom is off. No aoe list (nothing to add).
actions=call_action_list,name=stealth,if=buff.stealth.up
# Cold Blood before a Mutilate: guaranteed crit (+1 point from Seal Fate); off the GCD, behind the cooldowns toggle
actions+=/cold_blood,if=buff.slice_and_dice.up&!buff.cold_blood.up&combo_points<=2
actions+=/slice_and_dice,if=!buff.slice_and_dice.up&combo_points>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=settings.refresh_window&combo_points>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=1.5&combo_points>=1
actions+=/slice_and_dice,if=combo_points>=5&buff.slice_and_dice.remains<=settings.early_refresh
# Venom: poisons +30% damage / +10% chance; second in line, after Slice and Dice has had its 5-point slot
actions+=/venom,if=settings.venom&!buff.venom.up&combo_points>=3&buff.slice_and_dice.up
actions+=/venom,if=settings.venom&buff.venom.remains<=settings.refresh_window&combo_points>=4
actions+=/venom,if=settings.venom&combo_points>=5&buff.venom.remains<=settings.early_refresh
# a damage finisher only when it delays neither buff
actions+=/eviscerate,if=combo_points>=settings.min_finisher_cp&buff.slice_and_dice.remains>settings.early_refresh&(!settings.venom|buff.venom.remains>settings.early_refresh)
# at 4 points a Mutilate would waste one: Sinister Strike makes the 5th for 45 energy
actions+=/sinister_strike,if=combo_points=4
actions+=/mutilate,if=combo_points<=3
# no Mutilate yet (or no daggers): the Combat builder
actions+=/sinister_strike,if=combo_points<5
actions.stealth=ambush,if=group
actions.stealth+=/cheap_shot
```

```
# Subtlety: Slice and Dice, Hemorrhage debuff, Rupture on durable targets, Eviscerate otherwise; Backstab/Hemorrhage build.
actions=call_action_list,name=stealth,if=buff.stealth.up
actions+=/slice_and_dice,if=!buff.slice_and_dice.up&combo_points>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=settings.refresh_window&combo_points>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=1.5&combo_points>=1
actions+=/slice_and_dice,if=combo_points>=5&buff.slice_and_dice.remains<=settings.early_refresh
actions+=/call_action_list,name=aoe,if=active_enemies>2
# Hemorrhage first so Rupture lands inside its 15 s +15% window; it is also a 35-energy builder
actions+=/hemorrhage,if=!debuff.hemorrhage.up|debuff.hemorrhage.remains<=settings.refresh_window
actions+=/rupture,if=settings.boss&combo_points>=5&dot.rupture.remains<=settings.refresh_window
# free 2 points (any time on Forever), behind the cooldowns toggle
actions+=/premeditation,if=combo_points<=2
# 5 points: Eviscerate on trash, or when Rupture and Slice and Dice both have time
actions+=/eviscerate,if=combo_points>=settings.min_finisher_cp&(!settings.boss|dot.rupture.remains>settings.early_refresh)&buff.slice_and_dice.remains>settings.early_refresh
# Cutthroat made the next Ambush stealth-free (aura 462707); needs a dagger and position
actions+=/ambush,if=buff.cutthroat.up&group&combo_points<=4
actions+=/ghostly_strike,if=combo_points<=4
actions+=/backstab,if=settings.backstab&group&combo_points<5
actions+=/hemorrhage,if=combo_points<5
actions+=/sinister_strike,if=combo_points<5
# three or more long-lived targets: put Rupture on the ones that lack it (the player swaps; nothing here targets)
actions.aoe=rupture,if=settings.boss&combo_points>=5&active_dot.rupture<active_enemies&!dot.rupture.up
actions.stealth=premeditation,if=combo_points<=2
actions.stealth+=/ambush,if=group
actions.stealth+=/cheap_shot
```

Notes on the drafts: they need the pack's `stealth` aura (1784, kept in step with `IsStealthed()`), the `venom`,
`cutthroat`, `thousand_cuts`, `rupture`, `hemorrhage` auras of §7, and the `excess_e` guard of §6 on the builders once
it exists (`mutilate,if=combo_points<=3&excess_e>=action.mutilate.cost` and so on).
Abilities that cannot be used for non-power reasons (Ambush unstealthed, Mutilate without daggers, Riposte unlit) rely
on the usability gate; core skips unknown spells.

## 9. Spell and aura table (DB2 build 1.60.1.70338; `TacoDogForeverData.ROGUE` keys)

IDs are lowest-rank first as the data addon lists them; levels in parentheses are SpellLevels `BaseLevel`. Energy cost
is the top rank's.
GCD is 1 s unless noted.

| Key | Name | IDs / ranks (levels) | Energy | CD | Duration | Notes |
|---|---|---|---|---|---|---|
| `sinister_strike` | Sinister Strike | 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 (1, 6, 14, 22, 30, 38, 46, 54) | 45 (40 with Improved SS 2/2) | - | - | 1 point |
| `backstab` | Backstab | 53, 2589, 2590, 2591, 8721, 11279-11281, 25300 (4, 12, 20, 28, 36, 44, 52, 60, 60) | 60 | - | - | dagger, behind; 150% + flat |
| `hemorrhage` | Hemorrhage | 16511 | 35 | - | 15 s debuff | +15% Rupture; 100%/145% dagger |
| `mutilate` | Mutilate | 1310707, 399956, 1241582, 1241584 (30, 40, 50, 60) | 60 | - | - | daggers both hands, 2 points, +20% vs Poisoned |
| `eviscerate` | Eviscerate | 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 (1, 8, 16, 24, 32, 40, 48, 56, 60) | 35 (25 Flawless) | - | - | rank 9: 108 + 170 per point before AP |
| `rupture` | Rupture | 1943, 8639, 8640, 11273, 11274, 11275 (20, 28, 36, 44, 52, 60) | 25 | - | 6 + 2/pt s, tick 2 s | data says 6 |
| `slice_and_dice` | Slice and Dice | 5171 (10, +20%), 6774 (42, +30%) | 25 | - | 6 + 3/pt s x Improved SnD | data says 6; range 100 |
| `venom` | Venom | 1310703 (40) | 25 | - | 6 + 3/pt s | self buff |
| `expose_armor` | Expose Armor | 8647, 8649, 8650, 11197, 11198 (14, 26, 36, 46, 56) | 25 | - | 30 s | family fix needed |
| `kick` | Kick | 1766, 1767, 1768, 1769 (12, 26, 42, 58) | 25 | 10 s | 5 s lockout | `silenced_kick` 18425, 2 s |
| `blade_flurry` | Blade Flurry | 13877 | 25 | 120 s | 15 s | +20% speed, +1 target |
| `adrenaline_rush` | Adrenaline Rush | 13750 | 0 | 300 s | 15 s | +100% energy regen |
| `cold_blood` | Cold Blood | 14177 | 0 (off GCD) | 180 s | 1 charge | +100% crit |
| `premeditation` | Premeditation | 14183 | 0 (off GCD) | 120 s | 20 s | +2 points |
| `preparation` | Preparation | 14185 | 0 | 600 s | - | resets cooldowns |
| `ghostly_strike` | Ghostly Strike | 14278 | 40 | 20 s | 7 s | 125%/180% dagger, +15% dodge |
| `ambush` | Ambush | 8676, 8724, 8725, 11267, 11268, 11269 (18..58) | 60 | - | - | stealth, behind, dagger |
| `garrote` | Garrote | 703, 8631-8633, 11289, 11290 (14..54) | 50 | - | 18 s | stealth, behind (Dirty Deeds waives) |
| `cheap_shot` | Cheap Shot | 1833 (26) | 60 | - | 4 s | stealth; 2 points |
| `kidney_shot` | Kidney Shot | 408, 8643 (30, 50) | 25 | 20 s | rank 1: 1-5 s; rank 2: 2-6 s | data says 1 |
| `gouge` | Gouge | 1776, 1777, 8629, 11285, 11286 | 45 | 10 s | 4 s | 1 point |
| `feint` | Feint | 1966, 6768, 8637, 11303, 25302 | 20 | 10 s | - | threat -750..-4000 |
| `riposte` | Riposte | 14251 | 10 (off GCD) | 6 s | 6 s | lit after a parry; 150% + disarm |
| `evasion` | Evasion | 5277 (8) | 0 (off GCD) | 300 s | 15 s | +50% dodge; Endurance -30/-60% cooldown |
| `sprint` | Sprint | 2983, 8696, 11305 (10, 34, 58) | 0 (off GCD) | 300 s | 15 s | +50% speed; does not break Stealth |
| `vanish` | Vanish | 1856, 1857 (22, 42) | 0 (off GCD) | 300 s | stealth state 11327 | Elusiveness -45/-90 s |
| `stealth` | Stealth | 1784-1787 (1, 20, 40, 60) | 0 | 10 s | until cancelled | off GCD |
| `sap` | Sap | 6770, 2070, 11297 (10, 28, 48) | 65 | - | 45 s | no longer breaks Stealth |

Auras that are not abilities: Hemorrhage debuff 16511, Rupture debuff (ability IDs), Thousand Cuts buff 1310723,
Cutthroat proc 462707, Remorseless 14143, Deadly Poison debuff 25349 (R5; 2818 R1; 12 s, 3 s tick, 5 stacks), Expose
Armor (ability IDs), Silenced - Kick 18425 (2 s). Poison items: Instant Poison 8679..11340 (up to Rank VI), Deadly
Poison 2823..25351 (Rank V).

## 10. Open questions, probes, sources

Open questions and the probe that settles each (a Rogue session for `~/src/ForeverProbe`):
1. **Energy regeneration rate** and whether it is linear or on a 0.1 s grid. Probe: `GetPowerRegenForPowerType(Enum.
   PowerType.Energy)` (exists in the Forever index; may be plain), and time the Kick (25) and Sinister Strike (45)
   usability flips from a known low. Also repeat under Adrenaline Rush.
2. **Player auras in combat:** are `C_UnitAuras.GetPlayerAuraBySpellID(5171/6774/13750/13877/14177/1310703/1310723/462707)`
   present and are `duration`/`expirationTime` secret? Does `IsStealthed()` stay plain?
3. **`UnitAttackSpeed("player")`** readable in combat? With SnD up it falls by 1/1.2 or 1/1.3; with Blade Flurry by
   1/1.2. That would be an exact Slice and Dice uptime signal.
4. **Slice and Dice recast semantics:** does a recast with fewer points replace, extend or refuse (V: replaces)?
5. **Combo points after a missed finisher** (Q9): a Rupture/Eviscerate dodged by a mob: points kept or lost?
   Also confirm points survive a target swap and return on swapping back.
6. **`IsSpellUsable` semantics** for rogue spells: a finisher at 0 points, Ambush unstealthed, Mutilate without
   daggers, Riposte unlit, Backstab from the front (the error name via `UI_ERROR_MESSAGE`).
7. **Talent reads:** `IsPlayerSpell` / `C_SpellBook.IsSpellKnown` for 14165 (Improved SnD), 14179 (Relentless),
   1310711 (Flawless), 1310721 (Thousand Cuts), 14983/1310708 (Vigor); `C_SpecializationInfo.GetTalentInfo`.
8. **Target casting** (PR8): `UnitCastingInfo("target")` and its events, for Kick.
9. **Weapon poisons:** `C_Item.GetWeaponEnchantInfo(slot)` result and secrecy, to show a "poison missing" reminder.
10. **Relentless Strikes certainty:** after a 5-point SnD, does an energy jump of 25 show in usability flips every time?
11. **Death Mark vs Thousand Cuts**, **Coup de Grace** numbers (DB2 has 2% per stack, 10% at five),
    **Venom's real value** against Eviscerate: needs the level-60 build or a sim; the Mmonster trainer leaves it out.
12. **Is the Mutilate "Poisoned target" bonus satisfied by Instant Poison only?** (it leaves no debuff.)

Sources (all fetched 2026-10-12 unless noted):
- Blizzard, "World of Warcraft: Forever Class Deep Dives - Rogue and Warlock", 2026-10-07:
  https://news.blizzard.com/en-us/article/24310968/world-of-warcraft-forever-class-deep-dives-rogue-and-warlock and
  https://worldofwarcraft.blizzard.com/en-us/news/24310968
- MMO-Champion mirror (2026-10-07): https://www.mmo-champion.com/content/14586-World-of-Warcraft-Forever-Class-Deep-Dives-Rogue-and-Warlock
- Warcraft Tavern deep dive (2026-10-07): https://www.warcrafttavern.com/forever/news/poison-pets-rogue-warlock-deep-dive-for-wow-forever/
- classicwow.gg Rogue overview, changes, Combat/Assassination/Subtlety (updated 2026-10-08, build 70245):
  https://classicwow.gg/forever/guides/rogue (+ /combat, /assassination, /subtlety)
- classicwowforever.com class changes (2026-10-07, build 70245) and class guide: https://classicwowforever.com/class-changes/rogue/
- EndGameTools beta-client reading (2026-09-27, updated 2026-10-09, build 70291): https://endgametools.com/en/wow-forever/news/wow-forever-rogue
- gamer-guides.com (2026-09-30): https://gamer-guides.com/warcraft-forever/rogue-talents-changes/
- foreverdb.net rogue builds (extracted 2026-10-12, build 70338): https://foreverdb.net/class/Rogue/builds
- Mmonster guide (2026-09-26, updated 2026-10-10) and rotation trainer: https://mmonster.co/wow-forever/guides/rogue ;
  https://mmonster.co/wow-forever/tools/rotation-trainer/rogue
- wowtbc.gg (undated): https://wowtbc.gg/warcraftforever/class-guides/{assassination,combat,subtlety}-rogue/
- Leprestore Assassination (2026-09-20, updated 10-04), Combat (updated 10-05):
  https://leprestore.com/guides/world-of-warcraft-forever/
- ExpCarry (2026-10-08): https://expcarry.com/wow-forever-rogue-guide ; wow.gg beta guides (2026-10-01/07):
  https://wow.gg/guides/wow-forever-assassination-rogue-beta (+ combat, subtlety)
- Method leveling (2026-10-09): https://www.method.gg/wow-forever/wow-forever-rogue-leveling-guide-and-talents ; Warcraft Tavern Forever rogue
  guide: https://www.warcrafttavern.com/forever/guides/rogue/ ; Master of Warcraft (2026-10):
  https://www.masterofwarcraft.net/2026/10/wow-forever-rogue-guide.html
- Beta notes: https://wowforeverguides.com/classes/changes (Sept 24, Oct 1);
  https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-october-8/2360696 (no rogue changes Oct 8)
- Energy: https://github.com/wowaddonmaker/classicuiforever/issues/17 (2026-09-19, fluid regen)
- Vanilla: https://wowsod.pro/classic/rogue ; https://www.warcrafttavern.com/wow-classic/guides/pve-combat-rogue/ ;
  https://github.com/plamf/wow-combat-swords-rogue-rota ; Hekili `origin/classic:Classic/APLs/RogueCombat.simc`,
  `RogueAssassination.simc`, `Classic/Rogue.lua`
- Blocked/unreachable: Mobalytics, Icy Veins (403), Epic Carry (403), wowclassicforever.info and wowtbc-style undated pages
  (cert errors), foreverchanges.pro/talentsforever.com (blocked by the local network filter).
- DB2: `~/.local/share/wow-db2/forever/current.sqlite` (build 1.60.1.70338): Spell, SpellName, SpellEffect, SpellMisc,
  SpellPower, SpellCooldowns, SpellDuration, SpellLevels, SpellAuraOptions; WoW API index `wow_api_search` (flavor forever).
