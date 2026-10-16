<!-- Ported from TacoDogForever docs/research/2026-10-13-forever-druid-balance-bear-rotations.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# WoW Forever druid: Balance and bear rotations, plus the Feral-cat settings Hekili exposed (2026-10-12)

Research for two new specs in `TacoDogForever_Druid` (Balance, bear) and a short review of the settings Hekili's classic
Druid gave Feral cat, which is already shipped (`src/TacoDogForever_Druid/`: Feral.lua, Expressions.lua,
APLs/feral.simc: Shifting Power below 50 energy, Rip at 5 combo points, Rake, Shred or Claw by `group`, `excess_e`
pooling; nothing here repeats it). Client 1.60.1 build 70338, beta, **level cap 30** (since 2026-10-01), launch
2026-11-04, level 60 content not open: every level-60 rotation below is theory from guides and the DB2.

Confidence tags on each claim:
- **F** = Forever-verified: Blizzard's own words (S1 deep dive 2026-09-30, S2 beta notes 2026-10-01, S3 notes 2026-09-24
  as relayed) or the Forever DB2 for build 70338 (S23, queried directly: spell, cost, cast, duration, cooldown, effect
  numbers, descriptions).
- **G** = Forever-specific third-party guide, not Blizzard, not verified in game by us.
- **V** = vanilla-assumed (nothing Forever-specific found).
- **I** = inferred by me from DB2 numbers or engine facts.
Source keys S1..S26 are listed at the end. Section 10 is the Feral addendum; open questions are section 11. Nobody on our side has played a Balance or bear druid on Forever yet.

## 1. Forever changes to the class

Whole class
- **Tiger's Fury removed; King of the Jungle removed (F, S2).** DB2 still carries Tiger's Fury 5217 (a stale row; its
  description mentions a SoD "instantly grants Energy" talent), so presence in DB2 proves nothing (see Runes below).
- **Shifting Power (Feral row 4, needs Shredding Attacks) (F, S2, DB2 1322605).** Cat Form only: converts 55% of base
  mana (same cost as Cat Form; reduced by Natural Shapeshifter) into 40 energy, 16 s cooldown, 1.0 s GCD. Improved Shifting
  Power (row 5, DB2 1322670) cuts the cooldown by 4/8 s. Guides add "does not work at full energy" (G, S6/S7).
- **Furor redesigned (Resto) (F, S1, DB2 17056).** No energy burst on entering Cat Form. It restores 20% per rank (100% at 5/5)
  of the energy you had when you last left Cat Form, plus 10 energy per second spent outside it; Bear Form forfeits that
  energy and halts the restoration. Chance (20%/rank) for 10 rage on entering Bear Form. Blizzard's stated reason: stop
  "bear-weaving". **Powershifting is gone**; Shifting Power replaces it (section 10).
- **Omen of Clarity is a passive trained at level 20 (F, S1, DB2 16864)**: "Your spells and attacks have a chance to
  grant you Clearcasting" (not a cast buff any more). Clearcasting (DB2 16870, 15 s, -100% cost of the next damage or
  healing spell or offensive ability) is **not consumed by Wrath or by zero-cost abilities** (F).
- Nature's Grasp trained at 10, works indoors and in form (F). Revive (new out-of-combat resurrection) at 12 (F). Entangling
  Roots works indoors (F); Overgrowth lets it hold 3 targets (F). **Hurricane has no cooldown (F, S1; DB2 cooldown 0).**
  Faerie Fire is a baseline spell (level 18, no longer a talent) and **can be cast in Bear, Dire Bear and Cat Form for no
  resource cost with a 6 s cooldown (F, S1/S2); it no longer resets the swing timer (F, S2).** Barkskin and mana potions
  work in form (G, S4: Oct 8). Improved Mark of the Wild and Improved Enrage are baseline (F, S1). All forms are immune to
  Disarm (F, S2).
- **Cat, Bear and Dire Bear auto-attack uses the equipped weapon's DPS**; swing speed is **1.0 s (cat) or 2.5 s (bear)**;
  weapon enchants and procs work in form (F, S1). Most potions and consumables work in form (F).
- **Insect Swarm moved from Restoration to Balance** as a 1-point talent in row 4, available from level 25 (F/G, S1 via S6;
  S10: "unlocks at level 25"). DB2 still lists the spell ranks 5570, 24974-24977 at levels 20/30/40/50/60.
- Spells cast with ranks "vastly below your level" get reduced benefit and a lower chance to trigger talents (F, S2).
  Always use the highest rank (the engine already does).

Balance
- **Wrath redesigned (F, S1; DB2).** Mana cost greatly reduced, damage reduced to match; base damage +~50% in the 09-24 build
  (F, S3) and ranks 1-5 re-tuned on 10-08 (G, S4). DB2 Rank 8 (9912): 120 mana, 2.0 s cast, spell-power coefficient
  0.571, base ~91 (vanilla: 180 mana, 236-264).
- **Eclipse (new, row 5, 3 ranks) (F: DB2 408248/408255; G: rank numbers S4/S13/S15/S25).** "Your Wrath spell reduces the cast
  time of your next 2 Starfire spells; stores up to 4 charges; lasts 15 s." Per-charge reduction 0.17 / 0.33 / 0.50 s by rank.
  Wrath builds it with no critical strike needed (G, S4). It is a row-5 talent that S10 says is not available at level 30.
- **Nature's Splendor** (1 point, 11-point gate): Moonfire +3 s, Insect Swarm +2 s, Rejuvenation +3 s, Regrowth +6 s (F,
  DB2 1223083). **Nature's Majesty** (2 ranks): +1% spell and melee crit each (F, DB2 1223082). **Genesis** (5 ranks): +1%
  periodic damage and healing each (G; DB2 1223081). **Moonglow** moved to row 2: -8/-17/-25% mana on damaging spells only (G,
  S4; DB2 -25% at 3/3). **Nature's Grace** redesigned: a non-periodic spell crit gives +10% cast speed and -10% GCD for 3 s
  (F, DB2 16880/16886). Improved Wrath 5/5: -0.5 s cast, -50% mana. Improved Starfire 5/5: -0.5 s cast, 15% chance to stun for
  3 s (F, DB2 16814, 16850).
- **Moonkin Form (talent, level 40 with 31 points, 35% base mana, DB2 24858):** party members within 45 yd get +3% crit on
  **spells and attacks**, exclusive with Leader of the Pack; **all non-healing spells can be cast in form** and healing is
  blocked; Omen of Clarity's trigger chance +100%; armor from items +360% (F, S1; DB2 24905/24907). Potions don't drop it (G).
- DB2-only, unconfirmed by any guide: **Improved Wrath (1248996)**: Wrath has a 50% chance to restore 35 mana (via 1302521). It
  would cut Wrath's net mana cost from 45 to about 27. Treat as unknown until a probe (section 11, P5).
- Tier 1 (raid tier, first lockout 2026-12-09): Balance 5-piece +3 s Insect Swarm (DB2 1301242). Forever idol "Idol of the Wild
  Court" (1307400): Wrath crits extend Insect Swarm. Not needed for a v1 pack; noted so the DoT-duration setting can grow.

Bear (Feral tree, shared with cat)
- **Mangle was renamed Primal Bite and lost its debuff (F, S3, 09-24).** It is the bear's main threat button: a 16-point
  talent (row 4, requires Savage Fury 2/2), **20 rage** (15 with Ferocity 5/5), **6 s cooldown**, instant, 1.5 s GCD, "100% normal
  damage plus 26 (R1) / 77 (R4) and a high amount of threat" (F, DB2 407995, 1238069, 1238070, 1238073 at levels 25/36/48/60).
  **Threat roughly doubled on 10-01 (F, S2).** Rage costs here and in the Lacerate/Maul/Swipe lines are DB2 base costs; guides
  quote post-Ferocity numbers (mmonster trainer: Primal Bite 15, Maul 10, Swipe 15).
- **Lacerate baseline at level 42 (F, S1; DB2 414644, 1235826, 1235827 at 42/50/58).** 15 rage (Shredding Attacks takes 1 per
  rank off, to 12), 1.5 s GCD, 15 s bleed (tick 3 s), stacks to 5; recasting adds 10% weapon damage per existing stack; high
  threat. The guides disagree on its place: S7 (level 60) omits it, S9 puts it first.
- **Berserk** (31-point talent, 15 s, 3 min, any form, off the GCD, DB2 417141): Primal Bite loses its cooldown and hits up to
  3 targets, cat combo-point builders get +100% crit, fear cleared and blocked (F, S1). Tier 1 Guardian 5-piece: -15 s cooldown
  (DB2 1301249).
- **Bear threat bonus 30% -> 50%; rage from critical hits +75% (10-01, F, S2) -> +100% (10-08, G, S4/S5).** Swipe now scales with
  3% of attack power (fixed 10-01, F, S2) and hits up to 3 targets (V; S5). Feral Instinct now adds Swipe damage 10/20/30%
  instead of threat (F, S1). **Natural Reaction** (row 6, 5 ranks): +1% dodge per rank, 20% per rank to gain 5 rage on a dodge
  (F, DB2 417051/417053). **Blood Frenzy** (2 ranks, merged with Primal Fury): 50/100% chance for 5 rage on a bear crit (F, S1).
  **Thick Hide** reworked to turn Defense into armor in every form (F, S1). Enrage: 10 rage up front then 2/s for 10 s, armor
  -27% (Bear) or -16% (Dire), 60 s (F, DB2 5229/25503). Frenzied Regeneration heals up to 100% of max health given enough rage (F, S1);
  **DB2 gives it a 180 s cooldown** (22842) that no guide mentions (I; probe P12). Growl's cooldown matches Taunt (8 s, DB2 6795).
  Demoralizing Roar's missing threat fixed 10-08 (G, S4/S5). Rage taken from damage fixed 10-08: Stamina no longer lowers it,
  absorbs count as if absent (G, S4). Known beta issues: armor buffs multiply in Bear Form; Faerie Fire and Demoralizing
  Shout generated no threat on 10-01 (F, S2).

Runes (all three specs)
- Forever has **no engraving**. The 271 "Engrave" spells in the client are Season of Discovery leftovers (S20). The DB2 still
  holds SoD Druid rune spells as ordinary class spells: **Starsurge 417157** (6 s cooldown), **Sunfire 414684** (and 414687
  bear, 414689 cat), **Starfall 439748**, **Skull Bash 410176**, **Survival Instincts 408024**, **Savage Roar 407988**,
  Swipe (Cat) 411128, Lifebloom, Nourish. **No Forever source lists any of them for Druid** (S6 lists Wild Growth, Berserk,
  Eclipse, Primal Bite as the new Druid kit; S16 and S18 list none of the rune spells). One junk guide names Starsurge (S22,
  discarded). The pack ignores them; the engine never recommends an unknown spell, so a guarded APL line would be harmless,
  but not worth writing until P2 says one is learnable. The shared data addon's `starsurge`, `sunfire*`, `starfall` and
  `skull_bash` records are therefore dead weight.

## 2. Specs and the talent builds players run

Forever's real talent tree is **not** in our DB2 (the `Talent` table is the old Classic tree: Overgrowth, Omen of Clarity and
Nature's Grasp rows still there, no Eclipse); take talents from guides. There is no readable talent API on Forever, so a
pack needs settings or game-read numbers.

**Balance (S10, S15, S25, S26).** 16 talents, 5 new. Order: Improved Wrath, Genesis, Moonglow, Improved Moonfire, Nature's
Majesty, Nature's Reach, Improved Entangling Roots, Nature's Splendor, Vengeance, Insect Swarm, Improved Starfire,
Overgrowth, Nature's Grace, Eclipse, Moonfury, Moonkin Form. Players run:
- **Level 30 (21 points), S10: 16/0/5.** Improved Wrath 5, Moonglow 3, Improved Moonfire 2, Nature's Majesty 2, Nature's
  Reach 2, Nature's Splendor 1, Insect Swarm 1, plus Nature's Focus 5 in Restoration. No Eclipse, no Moonkin Form. At level
  20 the 11 points are Improved Wrath 5, Moonglow 3, Nature's Reach 2, Improved Moonfire 1 (S12).
- **Level 60 (theory), S6/S7: about 41 Balance / 10 Restoration**, Moonkin Form, Improved Wrath, Vengeance, Eclipse 3/3, Improved
  Starfire, Moonglow, Reflection (Resto) for mana ("Mana hungry, you need Reflection", S26).
- Talents that change the rotation: **Improved Wrath** (cost and cast time), **Improved Starfire** (cast time), **Moonglow**
  (every cost), **Eclipse** (the Starfire rule), **Nature's Splendor** (DoT durations 15 s / 14 s), **Insect Swarm** (the spell
  exists only if taken), **Moonkin Form** (a form to maintain), **Nature's Grace** (cast speed; unobservable crits), **Nature's
  Reach** (fewer misses).

**Bear (S5, S7, S9, S11, S13).** Shares the Feral tree with cat (20 talents, 7 new). Players run:
- **Level 30 (0/21/0), S11, one build for both forms:** Ferocity 5, Feral Instinct 3, Feral Swiftness 2, Shredding Attacks 3,
  Savage Fury 2, Shifting Power 1, Primal Bite 1, Sharpened Claws 2, Blood Frenzy 1 of 2, Leader of the Pack 1. (It takes both
  Shifting Power and Primal Bite; a cat/bear hybrid at 30.)
- **Level 60 "Primal Bite tank", S6: about 38 Feral / 13 Restoration.** Key picks: Savage Fury 2, Primal Bite, Natural Reaction
  5, Thick Hide 3, Heart of the Wild 5, Blood Frenzy 2 (needs Sharpened Claws), Berserk (31 points), Furor (Bear: 10 rage on shifting).
- Talents that change the rotation: **Ferocity** (-1 rage per rank on Maul, Primal Bite, Swipe, Claw, Rake), **Primal Bite** (the
  button exists only if talented), **Savage Fury**, **Shredding Attacks** (Lacerate cost), **Berserk**, **Natural Reaction /
  Blood Frenzy** (rage income, unobservable events), **Feral Instinct** (Swipe value).

Spec detection in `Register.lua` (`detect(api)` returning IsSpellKnown): Balance = Moonkin Form 24858 or Insect Swarm 5570 known (and neither
Primal Bite 407995 nor Shifting Power 1322605); bear = Primal Bite known (or Bear Form 5487 once Feral); cat = Shifting
Power known. Below level 25 a druid is ambiguous: the user sets `/tdf spec`. Hekili's classic pack picks cat/bear in one APL
by `buff.bear_form.up`; here bear is its own spec because the two share a tree but not a button set.

## 3. Single-target priority

### 3.1 Balance

Basis: S7 (mmonster trainer, level 60), S8 (wowtbc.gg), S10 (level 30), S12 (wow.gg level 20), S21 (Warcraft Tavern); the
reasoning is mine from DB2 coefficients (I). Guides are pre-sim; wowtbc.gg says the rotation is "preliminary ... the sims
will determine the optimal rotation".

Per-cast numbers at level 60, ranks from DB2, talents 5/5 Improved Wrath, 5/5 Improved Starfire, 3/3 Moonglow, 3/3 Eclipse,
spell power 400 (illustrative; no Moonfury/Vengeance/crit) (I):

| Spell | Cast | Mana | Damage | Per cast second | Per mana |
|---|---|---|---|---|---|
| Wrath R8 | 1.5 s (GCD floor) | 45 | 91 + 0.571 SP = 319 | 213 | 7.1 |
| Starfire R7 | 3.0 s | 255 | 381 + 1.0 SP = 781 | 260 | 3.1 |
| Starfire R7 with an Eclipse charge (3/3) | 2.5 s | 255 | 781 | 312 | 3.1 |
| Moonfire R10 | instant, 12 s | 281 | 135+0.15 SP direct, 4 ticks of 60+0.13 SP = 643 | n/a | 2.3 |
| Insect Swarm R5 | instant, 12 s | 120 | 6 ticks of 31+0.158 SP = 565 | n/a | 4.7 |
| W then 2 S cycle | 1.5+2.5+2.5 = 6.5 s | 555 | 1881 | 289 | 3.4 |

Reading: Starfire burns ~85 mana/s (255 per 3.0 s), Wrath 30 mana/s. Wrath is the sustainable filler; Starfire is the DPS
button and a mana sink; Eclipse turns Wrath casts into Starfire speed (the W S S cycle beats pure Starfire by ~10% at
no extra mana per second). A DoT is worth its GCD when the target lives about 7 s (Insect Swarm: 565 vs Wrath 319 per 1.5 s GCD, break-even 6.8 s);
Moonfire's direct hit pays at once.

Numbered rules (single target, level 40-60 with Moonkin/Eclipse; lower levels drop the lines the spells don't exist for):
1. **Moonkin Form** if known and not in it (G, S8 rule 1). Costs 35% base mana and a GCD: do it out of combat. Stay in it:
   it casts everything but heals and doubles Omen of Clarity procs (F).
2. **Moonfire** when the debuff is down (G S7: "before it drops; cheap upkeep"). Refresh rule: **recast when the last tick has
   landed (the debuff is down), not before**. Re-applying a DoT replaces its ticks (V): Moonfire ticks every 3 s (4 ticks / 12 s;
   5 / 15 s with Nature's Splendor), so a recast with 3 s or less left throws away the final tick (25% of the DoT part) for no
   uptime benefit that matters. This assumes Forever has no pandemic-style carry-over; the engine's default 0.3 would then
   be wrong for these auras (set `pandemic = 0`; probe P3). Skip on trash that dies in under ~7 s (setting; section 8).
3. **Insect Swarm** (talent, from level 25) when down, same refresh rule (ticks every 2 s; 12 s, 14 s with Splendor). Cast after
   Moonfire in the opener (S7, S10). On bosses and long fights; on trash only with the setting.
4. **Starfire while an Eclipse charge is up** (G, S7 rule 3: "the next Starfire casts 0.5 s faster, so spend the charges";
   S8 rule 3). Each Starfire cast uses one charge.
5. **Wrath otherwise** (S7 rule 4: "fast and cheap with Improved Wrath, and every cast charges Eclipse"). With Eclipse the
   loop is W, S, S, W, S, S (Wrath puts two charges up; the cap is four, 15 s).
6. Optional (setting `starfire_filler`): Starfire as the filler when mana is plentiful and no Eclipse (a Starfire is
   1.2 times a Wrath per cast second, 2.8 times the mana); off by default.
7. Level 20-29 and 30 (no Eclipse, no Moonkin): Moonfire, Insect Swarm (25+, long fights), **Wrath as the stationary filler**;
   Starfire (R1 95 mana, R2 135 at 26) only as a precast opener at maximum range (G, S10/S12 "Moonfire on every target
   fighting you, otherwise Wrath", "do not refresh healthy DoTs early just because you need a movement global"). Spam Wrath;
   Wrath costs about 26 mana at level 30 (R5 70 base, -50% Improved Wrath, -25% Moonglow), so mana is not the limiter until
   Starfire joins.
8. While moving: Moonfire / Insect Swarm if down, nothing otherwise (all DoTs are instant) (G, S10). The engine has no `moving`
   input (section 11, G2).

### 3.2 Bear (Guardian)

Basis: S9 (wowtbc.gg level-30 list, labelled "an idea"), S7 (trainer, level 60), S11 (level 30), S5 (classicwow.gg bear guide),
Hekili's classic bear sub-list (S24: `maul,use_off_gcd=1,if=!buff.maul.up`; `swipe_bear,if=rage>60`; `faerie_fire_feral`).
Two sources order Lacerate differently and none is sim-backed; I merged them (I).

S9, verbatim order: Dire Bear Form; Frenzied Regeneration (emergency); Berserk with on-use effects; maintain 5 Lacerate stacks;
maintain Faerie Fire (Feral); maintain Demoralizing Roar; Maul with excess rage; Primal Bite; Lacerate if under 5 stacks; Swipe.
S7 (level 60): Primal Bite on cooldown; Demoralizing Roar whenever it drops; Maul with spare rage; Swipe "with a full bar" on one
target, the main button on packs while Primal Bite recharges. Opener Roar, Primal Bite, Maul. S5: "save rage for the next Primal
Bite ... rather than spending it on damage right before Primal Bite comes off cooldown"; weigh Lacerate's rage against the
target's remaining life.

Numbered rules (merged; rage costs are base, minus Ferocity):
1. **Bear Form / Dire Bear Form** (Dire from level 40 replaces Bear; both 55% base mana) if not in form; the spec-level
   usable requires it for every bear ability (as Feral does for Cat Form).
2. **Demoralizing Roar** when the debuff is down (10 rage, 30 s, GCD 1.5; opener; family `attack_power_reduction` replaces with
   a warrior's Demoralizing Shout, so a group's other tank may already hold it: mark the aura `shared = Target`).
3. **Faerie Fire (Feral)** when its debuff is down (free, 6 s cooldown, 1.5 s GCD presumed; 40 s armor debuff). It is free, so
   it only costs a GCD; but "Faerie Fire doesn't generate threat" was a known issue on 10-01 (F, S2): low priority until
   fixed. (Cost, cooldown and debuff ID are unverified for the feral version: P7.)
4. **Lacerate refresh**: at 5 stacks, recast when the bleed has 4.5 s left or less (one tick plus one GCD) to keep 5 stacks up
   (S9 rule 4: maintain 5 stacks). Each recast adds 10% weapon damage per stack, so the last tick matters less than the stack.
5. **Primal Bite on cooldown** (S7 rule 1, S9 rule 8, S11 rule 3). It is the hardest-hitting and highest-threat button.
6. **Lacerate to 5 stacks** (stack count below 5) (S9 rule 9): only after Primal Bite has been used this cooldown, and only on
   targets that live long enough (a 15 s bleed; `settings.boss`, since `ttd` is unavailable).
7. **Maul with excess rage**, only if the next Primal Bite stays affordable: `rage >= maul.cost + primal_bite.cost` (S5, S9
   rule 7). Maul is off the GCD and rides the next swing (2.5 s in bear); one queued at a time (V; Hekili `usable = not
   buff.maul.up`).
8. **Swipe as a rage dump** at or above `settings.dump_rage` (default 60, Hekili's classic number; S7 "full bar") on a single target.
9. **Enrage** (setting, off): 10 rage up front, 2/s for 10 s; reduces armor 27% (Bear) / 16% (Dire): use only on a pull that
   starves of rage (G, S5); not a priority.
Level 10-29: Bear Form (10), Maul (R1 at 10, rage 15), Demoralizing Roar (10), Enrage (12), Bash (14), Swipe (16), Feral Charge (20,
talent). Level 25+: Primal Bite if talented. Level 30: Primal Bite, Swipe on groups, Maul with excess rage (S11).

## 4. AoE

- **Balance:** no AoE below level 40. Hurricane (R1 40, 10 s channel, 880 / 1180 / 1495 mana base for R1/R2/R3, no cooldown
  on Forever) is the only AoE. Switch at **4 or more targets (I; no Forever source gives a count; vanilla habit)** and mana to
  spare (R3 costs about 1121 after Moonglow: 25 Wraths' worth, 37% of an illustrative 3000-mana pool). On 2-3 targets: the single-target list on
  each target, with Moonfire / Insect Swarm cast on a target the player has selected and that lacks them (the engine's
  `cycle_targets` is disabled in v1; the per-target memory in the belief makes `!dot.moonfire.up` track the current
  target). Entangling Roots (1.5 s cast, 27 s, up to 3 targets with Overgrowth) is control, not damage.
- **Bear:** **2 or more targets** switches to Swipe as the main spender (S7, S5; Swipe hits up to 3). Order: Demoralizing Roar,
  Berserk if 3+ targets and the cooldowns toggle is on, Primal Bite on cooldown (it cleaves three under Berserk only),
  Swipe whenever affordable, Maul only with rage above Swipe + Primal Bite. Lacerate is skipped on packs (rage better spent on
  Swipe) unless a single target needs the bleed. Challenging Roar (15 rage, 10 min, 6 s) and Growl are manual.

## 5. Cooldowns, defensives, interrupts

| Behind `cooldowns` | Why | Notes |
|---|---|---|
| Berserk (bear, 417141) | 15 s window, 3 min | Cleave value only with 3+ targets or high rage income; S9 lists it with on-use effects |
| Innervate (Balance, 29166, level 40) | +400% mana regeneration for 20 s, and 100% of it continues while casting, 6 min | 5% base mana; Hekili's classic Druid had `innervate_enabled` and `innervate_threshold` (20% mana). Mana is hidden: use "cannot afford a Starfire" |
| Shifting Power (cat, shipped) | already behind it | |

**Not in the APL** (the game won't tell us health): Frenzied Regeneration (22842, 10 s, DB2 180 s cooldown), Barkskin
(22812, level 44, 15 s / 60 s, works in form), Enrage, Survival Instincts (rune, probably absent). Expose them as `custom1`
("defensives") so a player flips the toggle while hurt: `frenzied_regeneration,if=toggle.custom1`. Interrupts: **Feral Charge
(Bear)** 16979, 5 rage, 15 s, 8-25 yd, immobilizes and interrupts 4 s; Bash stuns 2/3/4 s (not bosses); Balance has no
interrupt (Improved Starfire's 15% stun is a proc). Nothing in the APL: target casting isn't readable.

## 6. Resources

**Mana (Balance, and every shapeshift).** Hidden in combat; affordability via `C_Spell.IsSpellUsable` is readable, so the belief
calibrates mana from usability flips as for energy and rage (gate spike). Vanilla regeneration (V; none of it checked on Forever):
spirit-based regeneration pauses for **5 seconds after each cast** (five-second rule); a fraction continues while casting from
Reflection (Resto: 15% in vanilla, "50% at max rank" on Forever, S21) and Innervate (100%); out of combat it is full rate.
Whether regeneration is continuous or in 2 s ticks is unknown (energy is continuous on Forever; mana probably follows,
P5). Model: two regeneration models around a pack-owned 5 s aura applied by every mana cast (one while it is up, one
while it is down; the second needs a "while absent" gate that models don't have today: section 11, G3). Forms cost 55% of
base mana (Moonkin 35%), reduced by Natural Shapeshifter (-10/-20/-30%), so a form re-entry is an expensive mistake.
Nothing in Balance is pooled for; the mana rule is "Starfire only with Eclipse" (a self-limiting burn) and Innervate.

**Rage (bear).** Hidden (power is secret even out of combat; gate spike). Sources: damage taken (Stamina no longer reduces it since
10-08), swings (bear swing is 2.5 s weapon-DPS based; whether swing rage is "normalized by weapon speed" like Forever's warrior is
unknown, P8), Enrage (10 + 2/s), Natural Reaction (5 on a dodge), Blood Frenzy (5 on a crit), Furor (10 on shifting), crits give +100%.
Rage decays out of combat (set `rest = 0`, a `restRate`, as the warrior pack does). Costs after Ferocity 5/5: Maul 10, Primal Bite 15, Swipe 15,
Lacerate 15 (12 with Shredding Attacks), Roar 10, Bash 10. The belief pins rage with usability flips (cost ladder: Roar 10
< Maul 10/15 < Primal Bite 15/20 < Swipe 15/20). **Maul needs the engine's on-next-swing support** (the warrior pack's open gap): spend at the next
swing; `C_Spell.IsCurrentSpell(Maul)` shows it queued (exists on Forever, `AllowedWhenTainted`; not verified readable in combat).

**Energy / combo points (cat):** shipped.

**No pooling.** Neither spec pools; the stateless-guard rule (`pool_resource` is rejected) is satisfied by
`rage >= maul.cost + primal_bite.cost` style guards.

## 7. Auras, procs and trackers

Readable in combat on Forever (gate spike): `IsSpellUsable`, `insufficientPower`, cooldown flags, combo points, group, `UI_ERROR_MESSAGE`.
Hidden: power values, target auras (`GetAuraDataBy*` on the target errors in combat), target health; player auras are
"read by spell ID out of combat; in combat unknown (the Druid's were secret in the §15 note)". An aura on the target shows
up/down through the AuraContainer gate (our child frame shows with the aura; OnShow/OnHide don't fire to Lua).

| Aura / proc | ID (DB2) | Unit | Duration, stacks | Readable in combat? | Belief without it |
|---|---|---|---|---|---|
| Moonkin Form | 24858 (form), 24905 passive, 24907 party aura | player | until cancelled | unknown (player aura) | persists once cast; clear on form change error; re-read out of combat |
| Moonfire | 8921, 8924-8929, 9833-9835 | target | 12 s (R1 9 s); 15 s with Splendor | no (target) | set at our cast; up/down by gate; drop on target swap (memory) |
| Insect Swarm | 5570, 24974-24977 | target | 12 s; 14 s with Splendor | no | same |
| Eclipse | 408248 (talent), 408255 (aura), 441260 | player | 15 s, 4 charges | unknown; ID to confirm (P1) | our casts: a Wrath success adds 2 charges (cap 4), a Starfire cast start uses one, 15 s expiry |
| Clearcasting | 16870 (via 16864) | player | 15 s, 1 charge | unknown | `Read` of the aura if readable; else the free-cast signal: a mana spell reports usable at belief-mana below its cost |
| Nature's Grace | 16886 | player | 3 s | no (needs crit events) | ignore (cast speed and GCD 10% for 3 s; keep GCD floor at 1.5) |
| Faerie Fire | 770, 778, 9749, 9907 (DB2 also has an unexplained 1288561: 15 s, 30 s cooldown) | target | 40 s | no | our cast sets it; the feral free cast's debuff ID is unconfirmed (P7) |
| Lacerate | 414644, 1235826, 1235827 | target | 15 s, 5 stacks | no | our casts; stack +1 per hit; 15 s refresh; hit unknown (bleeds can miss/dodge as a yellow attack) |
| Demoralizing Roar | 99, 1735, 9490, 9747, 9898 | target | 30 s | no | our cast; `shared = Target` (a warrior's Shout counts) |
| Bear Form | 5487, 9634 (Dire) | player | until cancelled | unknown | aura alias (Dire counts as Bear) |
| Maul queued | pack-owned | player | next swing (2.5 s) | `IsCurrentSpell` | set at cast, cleared by the swing guess |
| Enrage | 5229 / 25503 | player | 10 s | unknown | our cast |
| Berserk | 417141 | player | 15 s | unknown | our cast |
| Frenzied Regeneration | 22842 | player | 10 s | unknown | our cast |
| Innervate | 29166 | player/target | 20 s | unknown | our cast |
| Shifting Power energy | 1322605 | player | instant | no (energy hidden) | shipped |

Trackers to write: (1) **eclipse** (cast observations only: Wrath success +2 charges, cap 4, expiry 15 s from the latest; Starfire
cast start -1 charge; uncertain until P1 settles +1 vs +2); (2) **lacerate stacks** (from our casts; the Feral bleed tracker's
combo-point trick doesn't exist for rage, so assume hits); (3) **clearcasting** via usable-below-cost evidence; (4) a **pull
gate** for Maul from `IsCurrentSpell`. Nothing observes a Moonfire or Insect Swarm resist.

## 8. Draft APLs

Both are single files per spec in our dialect: `actions` is the default list, `actions.aoe` the AoE list; every line is a
stateless guard. They use names that must exist: abilities and auras registered with those keys, settings registered in
the spec. `ttd` is unavailable, `talent.*` is unavailable, `prev_gcd` and `time` aren't tracked, `wait` and `potion` are
unsupported, and `cycle_targets` / `target_if` are disabled; hence the settings.

### 8.1 Balance (`APLs/balance.simc`)

```
# Settings: moonkin (bool, true), buffs (bool, false), boss (bool, false: "the fight is long", stands in for ttd),
#           trash_dots (bool, true: Moonfire on short fights), hurricane_targets (num, 4), innervate (bool, true),
#           starfire_filler (bool, false).
actions=moonkin_form,if=settings.moonkin&!buff.moonkin_form.up                              # a form, out of combat; known at 40+
actions+=/mark_of_the_wild,if=settings.buffs&!buff.mark_of_the_wild.up&!buff.gift_of_the_wild.up  # long buff; out of combat
actions+=/thorns,if=settings.buffs&!buff.thorns.up                                           # long buff; out of combat
actions+=/innervate,if=toggle.cooldowns&settings.innervate&mana.current<action.starfire.cost*2   # regen window when a Starfire is almost out of reach
actions+=/run_action_list,name=aoe,if=active_enemies>=settings.hurricane_targets&settings.hurricane_targets>0
actions+=/moonfire,if=!dot.moonfire.up&(settings.boss|settings.trash_dots)                  # DoT down; recast on the last tick, not before
actions+=/insect_swarm,if=!dot.insect_swarm.up&settings.boss                                # talent from 25; long fights only
actions+=/starfire,if=buff.eclipse.stack>=1                                                  # Eclipse: spend the shortened Starfires
actions+=/starfire,if=settings.starfire_filler                                               # optional, mana-rich play
actions+=/wrath                                                                              # filler; two charges of Eclipse per cast
actions.aoe=moonfire,if=!dot.moonfire.up                                                    # keep Moonfire on the target the player picked
actions.aoe+=/hurricane                                                                      # 10 s channel; no cooldown on Forever
```

Notes: `hurricane` needs a channel (engine "channels are not built yet"); model it as a 10 s hard cast meanwhile. `eclipse` is a
pack aura keyed to 408255 (not in the shared data: add an override, or a literal). `innervate` (29166) is also not in the shared
data (its skill-line ability has no class mask). The Starfire `cast` is a function of the Eclipse stack and a game-read
or setting-given base (3.5 minus Improved Starfire); the same for Wrath's cost and cast.

### 8.2 Bear (`APLs/bear.simc`)

```
# Settings: boss (bool, false), dump_rage (num, 60), use_enrage (bool, false).
actions=bear_form,if=!buff.bear_form.up                                                      # Dire counts as Bear
actions+=/run_action_list,name=aoe,if=active_enemies>=2                                      # packs: Swipe-led
actions+=/berserk,if=toggle.cooldowns                                                        # 15 s window with on-use effects (S9)
actions+=/demoralizing_roar,if=!debuff.demoralizing_roar.up                                  # AP reduction; also threat since 10-08
actions+=/lacerate,if=debuff.lacerate.stack>=5&debuff.lacerate.remains<=4.5                   # keep 5 stacks
actions+=/primal_bite                                                                        # main threat; 6 s cooldown
actions+=/faerie_fire,if=!debuff.faerie_fire.up                                              # free in form; low threat for now
actions+=/lacerate,if=settings.boss&debuff.lacerate.stack<5                                  # build stacks on long fights
actions+=/maul,if=rage>=action.maul.cost+action.primal_bite.cost                             # excess rage, Primal Bite still affordable
actions+=/swipe,if=rage>=settings.dump_rage                                                  # rage dump on one target
actions+=/enrage,if=settings.use_enrage&rage<action.primal_bite.cost                          # starved: optional
actions+=/frenzied_regeneration,if=toggle.custom1                                            # defensives toggle
actions.aoe=demoralizing_roar,if=!debuff.demoralizing_roar.up
actions.aoe+=/berserk,if=toggle.cooldowns&active_enemies>=3                                  # Primal Bite hits three, no cooldown
actions.aoe+=/primal_bite                                                                    # on cooldown (cleave only under Berserk)
actions.aoe+=/swipe                                                                          # main spender on groups
actions.aoe+=/maul,if=rage>=action.maul.cost+action.swipe.cost+action.primal_bite.cost
actions.aoe+=/faerie_fire,if=!debuff.faerie_fire.up
```

Notes: `rage` is a hidden ("G") resource; thresholds are ones the cost ladder can confirm (Maul 10, Primal Bite 15, Swipe 15). Primal Bite
and Lacerate are skipped by the engine when not learned. `faerie_fire` is the Balance spell's ID family used in form; the
pack needs a bear usable (`form = BEAR`) on every bear ability and a separate Faerie Fire entry that works in both forms.

## 9. Spell and aura table (IDs and values verified against `TacoDogForeverData.DRUID`, built from DB2 70338)

Costs are DB2 base costs (no talents); mana in points, rage in rage; GCD 1.5 s unless noted; "rank levels" are DB2 `BaseLevel`.

| Key (data addon) | Ranks (spell IDs) and levels | Cost | Cast | Duration | Cooldown | Notes |
|---|---|---|---|---|---|---|
| wrath | 5176 (1), 5177 (6), 5178 (14), 5179 (22), 5180 (30), 6780 (38), 8905 (46), 9912 (54) | 10/20/40/50/70/80/100/120 mana | R1 1.5 s, R2 1.7 s, R3+ 2.0 s | instant | none | coeff R8 0.571 |
| starfire | 2912 (20), 8949 (26), 8950 (34), 8951 (42), 9875 (50), 9876 (58), 25298 (60) | 95/135/180/230/275/315/340 | 3.5 s | | none | coeff 1.0 |
| moonfire | 8921 (4), 8924 (10), 8925 (16), 8926 (22), 8927 (28), 8928 (34), 8929 (40), 9833 (46), 9834 (52), 9835 (58) | 25/50/75/105/150/190/235/280/325/375 | instant | 9 s (R1), 12 s | none | tick 3 s; direct 0.15 SP, ticks 0.13 SP |
| insect_swarm | 5570 (20), 24974 (30), 24975 (40), 24976 (50), 24977 (60) | 45/85/100/140/160 | instant | 12 s | none | tick 2 s, 0.158 SP per tick, -2% to hit; talent |
| hurricane | 16914 (40), 17401 (50), 17402 (60) | 880/1180/1495 | channel 10 s | 10 s | none (F) | damage spell 1278759 for R3; tick period 1 s |
| entangling_roots | 339 (8), 1062 (18), 5195 (28), 5196 (38), 9852 (48), 9853 (58) | 50-125 | 1.5 s | 12-27 s | none | |
| faerie_fire | 770 (18), 778 (30), 9749 (42), 9907 (54) | 55/75/95/115 mana (free in forms, F) | instant | 40 s | 6 s in forms (F) | feral version not separately in DB2 |
| moonkin_form | 24858 (40), passive 24905, aura 24907 | 35% base mana | instant | until cancelled | none | |
| innervate | 29166 (40) | 5% base mana | instant | 20 s | 360 s | **not in the data addon** |
| barkskin | 22812 (44) | none | instant | 15 s | 60 s | |
| clearcasting | 16870 (via 16864, learned 20) | | | 15 s | | |
| natures_grace | 16880 -> aura 16886 | | | 3 s | | |
| eclipse | 408248 / 408255 / 441260 | | | 15 s, 4 stacks | | **not in the data addon** |
| bear_form | 5487 (10), dire_bear_form 9634 (40) | 55% base mana | instant | until cancelled | none | |
| maul | 6807 (10), 6808 (18), 6809 (26), 8972 (34), 9745 (42), 9880 (50), 9881 (58) | 15 rage | next swing, off GCD | | none | R7 bonus 128 |
| swipe | 779 (16), 780 (24), 769 (34), 9754 (44), 9908 (54) | 20 rage | instant | | none | R5 83; up to 3 targets |
| primal_bite | 407995 (25), 1238069 (36), 1238070 (48), 1238073 (60) | 20 rage | instant | | 6 s | 100% weapon + 26..77 |
| lacerate | 414644 (42), 1235826 (50), 1235827 (58) | 15 rage | instant | 15 s, 5 stacks | none | tick 3 s |
| demoralizing_roar | 99 (10), 1735 (20), 9490 (32), 9747 (42), 9898 (52) | 10 rage | instant | 30 s | none | family attack_power_reduction |
| enrage | 5229 (12) | 0 | instant, off GCD | 10 s | 60 s | 10 now + 2/s |
| frenzied_regeneration | 22842 (36) | rage converted, up to 10/s | instant | 10 s | **180 s (DB2)** | |
| bash | 5211 (14), 6798 (30), 8983 (46) | 10 rage | instant | 2/3/4 s | 60 s | Brutal Impact: +stun, -cooldown |
| growl | 6795 (10) | 0 | instant, off GCD | 3 s | 8 s | |
| challenging_roar | 5209 (28) | 15 rage | instant | 6 s | 600 s | |
| feral_charge_bear | 16979 (20); 1238122 shared record | 5 rage | instant | | 15 s | 8-25 yd; interrupt 4 s |
| berserk | 417141 | 0 | instant, off GCD | 15 s | 180 s | |
| shifting_power | 1322605 | 55% base mana | instant | | 16 s | GCD 1.0 s |
| thorns / mark_of_the_wild / natures_grasp | 467..9910 / 1126..9885 / 16689..17329 | 35-320 / 20-445 / 50-125 | | 10 min / 1 h / 45 s | none / none / 60 s | |

IDs absent from the shared data and needed here: Innervate 29166, Eclipse 408248/408255, Nature's Splendor 1223083, Nature's Majesty 1223082,
Genesis 1223081, Improved Shifting Power 1322670, Nature's Grace aura 16886, the Faerie Fire (Feral) form variant. They need
`tools/data/overrides.json` entries or literals in the pack.

## 10. Feral cat: Hekili's classic settings against Forever (short)

Hekili's classic Feral (`Classic/Druid.lua`, `DruidFeral.simc`; S24) exposed `combat_mode` (group/solo), `powershift_enabled`,
`powershift_time`, `rip_enabled`/`rip_cp`, `bite_enabled`/`bite_cp`/`bite_time`, `claw_trick_enabled`, `innervate_*`.
- **Powershifting (Wolfshead + Furor).** Hekili: `cat_form` in the `innervate_or_shift` list when `settings.powershift_enabled &
  set_bonus.wolfshead=1 & talent.furor.rank=5`, gain 40 energy on shifting with Furor 5/5 and 20 with Wolfshead Helm
  (item 8345). **Dead on Forever (F, S1 + DB2 17056, G S7):** the energy comes back only as much as you had when leaving
  Cat Form, plus 10 per second away; a shift gains almost nothing and costs 55% of base mana plus a GCD. Replace the
  whole list with Shifting Power (shipped: `shifting_power,if=energy<50`, behind `cooldowns`). Retire `powershift_*`. Wolfshead Helm
  exists in the Forever item DB (level 40, rare) but its effect isn't in our DB2 subset; unmodelled. `claw_trick` was a powershift
  trick (Claw into the shift): retire it.
- **Omen of Clarity.** Hekili's precombat `omen_of_clarity,if=!buff.omen_of_clarity.up` is obsolete: the spell is a passive
  at level 20. Clearcasting (15 s, free next ability) is what the pack reads; its in-combat visibility is unknown (P11), and
  Moonkin Form's doubling doesn't apply to cats. The shipped Feral treats a free Shred as `energyCost` 0 via the aura.
- **"Must be behind" Shred vs Claw.** Hekili `combat_mode` (default group): Shred in groups (the tank holds aggro), Claw solo.
  Shipped: `group` stands in. No Forever change found: Shred keeps its positional requirement (the SoD "no positional
  requirement" item set, DB2 1213171, is a SoD item, presumably not Forever). Better signal: the cast error. The
  `UI_ERROR_MESSAGE` payload is not secret (checked in a 2-person party in combat; whether the error lines fire in combat
  is unverified), so a tracker can mark "not behind" for ~5 s when Shred reports the positioning error and fall back to
  Claw; the error's exact message ID is unverified (open since the 10-12 checks; P14). Add `settings.behind`
  (bool) as the manual override.
- **Bite and Rip options.** Hekili exposed `rip_cp`, `bite_cp`, `bite_time` because vanilla Feral is a Rip-or-Bite choice. Nerdegghead's
  priority leaves Bite out, the trainer (S7) uses Ferocious Bite only on a target under 20% with 5 combo points (needs target health: unreadable); keep
  one `bite_finisher` toggle off by default.
- **Shifting Power** needs the mana to be there: `IsSpellUsable` with `insufficientPower` is readable, so the pack can skip it on
  "short of mana". A `settings.shift_mana` isn't needed.
- New to the cat: Feral Dedication (DB2 1231380-1231382: +25% energy regeneration after staying in Cat Form for a while, no guide
  mentions it) and Tier 1 Feral 5-piece (Shifting Power -1 s, DB2 1301247); both would change the regeneration estimate.

## 11. Open questions and the in-game probes that would settle them

Probes need a druid (levels 20 for Balance basics, 25 for Insect Swarm/Primal Bite, 40 for Moonkin/Hurricane/Innervate, 42 for
Lacerate; the beta cap is 30, so level 40+ probes wait for launch).
- **P1 Eclipse.** Charges per Wrath (+1 or +2), reduction per charge, whether the reduction is capped at 4 total, aura ID.
  Out of combat on a dummy: `/dump C_UnitAuras.GetPlayerAuraBySpellID(408255)` (and 441260), iterate
  `C_UnitAuras.GetAuraDataByIndex("player", i)` for the name and `applications`; `C_Spell.GetSpellInfo(2912).castTime`
  (and 25298) after each Wrath; try again in combat to see if `applications` is secret.
- **P2 Runes.** `IsSpellKnown(417157 / 414684 / 439748 / 410176 / 408024 / 407988)` and a trainer visit; `C_SpellBook` scan.
- **P3 Refresh model.** Recast Moonfire with 6 s left, then read the aura's `expirationTime` (carry-over or replace?);
  repeat for Insect Swarm and Lacerate (does a stack refresh the clock). Settles `pandemic = 0`.
- **P4 Durations.** Aura duration of Moonfire (12 vs 15 with Splendor), Insect Swarm (12 vs 14), Lacerate (15).
- **P5 Mana model and the Wrath proc.** Is regeneration continuous or 2 s ticks; five-second-rule behaviour; Reflection;
  whether Wrath restores mana (1248996: 50% to restore 35). Sample `UnitPower` out of combat (secret) is no use: calibrate by
  `IsSpellUsable` flips as for energy.
- **P6 Primal Bite.** `C_Spell.GetSpellPowerCost(1238073)` (15 or 20 with Ferocity), `C_Spell.GetSpellCooldown` (6 s), GCD,
  whether Berserk resets it, and whether its learned state needs Savage Fury 2/2 (`IsSpellKnown(407995)`).
- **P7 Faerie Fire (Feral).** In Bear Form: `GetSpellPowerCost(9907)` (0?), cooldown (6 s), GCD, the debuff's spell ID on the
  target, whether it joins the armor family (Sunder/Expose): out-of-combat target aura read.
- **P8 Rage and Maul.** Is rage secret in combat (selftest hidden-resource line); rage per swing at 2.5 s and per damage taken
  (calibrate `restRate`/regen); is Maul's cost taken at the swing or at the press; `C_Spell.IsCurrentSpell(6807)` readable in combat.
- **P9 Lacerate.** Stack/refresh behaviour, rage refunded on a miss, bleed tick 3 s: and whether Lacerate or Primal Bite wins on
  threat (no data; a sim or a parse decides, S9 and S7 disagree).
- **P10 Hurricane.** Channel tick count and mana; does `active_enemies` come out right in a pull.
- **P11 Player auras in combat.** Eclipse, Clearcasting, Enrage, Berserk, forms: readable or secret (selftest aura lines).
- **P12 Frenzied Regeneration.** DB2 says a 180 s category cooldown; guides say none.
- **P13 Spec detection.** Which spell ID `IsSpellKnown` answers true for after taking Eclipse, Primal Bite, Shifting Power,
  Insect Swarm (talent ID vs. the trained ID).
- **P14 "Not behind" error.** Cast Shred from the front and log `UI_ERROR_MESSAGE` (type and message).
- **P15 Feral oddities.** Wolfshead Helm's equip effect, Feral Dedication, and Furor's real returned energy on a quick shift.
- Engine gaps this document depends on: **G1** on-next-swing (Maul, as the warrior's Heroic Strike); **G2** no `moving` input and no
  in-combat flag (Hekili's precombat list can't be expressed); **G3** a regeneration model gated by an aura being absent (the five-second
  rule); **G4** channels (Hurricane); **G5** a `ttd` stand-in is `settings.boss` only; **G6** reading cast time and cost from the
  game instead of per-talent settings (proposal: `C_Spell.GetSpellInfo(id).castTime`, `C_Spell.GetSpellPowerCost(id)` out of combat,
  both `AllowedWhenTainted`).

## 12. Sources (read 2026-10-12 unless noted)

- S1 Blizzard Druid and Hunter class deep dive, 2026-09-30, relayed by Warcraft Tavern: https://www.warcrafttavern.com/forever/news/powershifting-is-back-sort-of-hunter-druid-deep-dive-for-wow-forever/
- S2 Blizzard "WoW Forever Beta Development Notes", updated 2026-10-01 (quoted on arctium.io): https://arctium.io/blue-posts/1063
- S3 Beta notes 2026-09-24 (Druid lines) at wow-forever.gg: https://wow-forever.gg/news/2026-09-24-druid-changes-in-wow-forever-beta/
- S4 classicwow.gg Druid class changes (talent numbers, dates to 2026-10-08): https://classicwow.gg/forever/guides/druid
- S5 classicwow.gg bear guide (updated 2026-10-08): https://classicwow.gg/forever/guides/druid/bear
- S6 mmonster.co Druid guide (data of 10-08, updated 10-10): https://mmonster.co/wow-forever/guides/druid
- S7 mmonster.co rotation trainer (level 20 and 60 fights): https://mmonster.co/wow-forever/tools/rotation-trainer/druid
- S8 wowtbc.gg Balance (undated, 2026): https://wowtbc.gg/warcraftforever/class-guides/balance-druid/
- S9 wowtbc.gg Feral tank (undated, 2026): https://wowtbc.gg/warcraftforever/class-guides/feral-tank-druid/
- S10 Leprestore Balance (published 2026-09-22, updated 10-05): https://leprestore.com/guides/world-of-warcraft-forever/wow-forever-balance-druid-guide-best-builds-rotation-race-professions-leveling/
- S11 Leprestore Feral (2026-09-22, updated 10-05): https://leprestore.com/guides/world-of-warcraft-forever/wow-forever-feral-druid-guide-best-builds-rotation-tanking-race-professions/
- S12 wow.gg Balance beta guide (2026-10-01): https://wow.gg/guides/wow-forever-balance-druid-beta
- S13 conquestcapped.com Druid talents (updated 2026-10-06): https://conquestcapped.com/guides/wow-forever/wow-forever-druid-talents/
- S14 theforeverera.com Druid (updated 2026-10-02): https://theforeverera.com/en/guides/classes/druid/
- S15 kami-labs.fr Balance talents (2026-09-14): https://kami-labs.fr/en/wow-forever/build-druide-equilibre-wow-forever/
- S16 classicwowforever.com Druid beta summary (observed 10-07): https://classicwowforever.com/class-guides/druid/
- S17 lfcarry Feral (2026-10-08) and Balance (2026-10-11): https://lfcarry.com/guides/wow-forever-feral-druid-pve ; https://lfcarry.com/guides/wow-forever-balance-druid-pve
- S18 foreverdb.net Druid ability list: https://foreverdb.net/class/Druid
- S19 metammo.com Druid (2026-10-02): https://metammo.com/wow-forever/classes/druid
- S20 wow-forever.gg on engraving (2026-09-30): https://wow-forever.gg/guides/systems/engraving/
- S21 Warcraft Tavern Forever Druid guide (2026): https://www.warcrafttavern.com/forever/guides/druid/
- S22 wowforever.games Balance (2026-09-21; invented talents, discarded): https://www.wowforever.games/448.html
- S23 Forever DB2 build 1.60.1.70338 as a local SQLite (`~/.local/share/wow-db2/forever/current.sqlite`), plus `TacoDogForever_Data/Generated/Spells.lua`.
- S24 Hekili classic Druid: `git -C ~/src/hekili show origin/classic:Classic/Druid.lua` and `Classic/APLs/DruidFeral.simc` (no Balance or bear APL exists there).
- S25 Icy Veins Forever Balance guide: https://www.icy-veins.com/wow-forever/balance-druid-ranged-dps-pve-guide (fetch returned 403; used only via a search summary: Moonfire up, then Wrath; Insect Swarm from level 25).
- S26 mmonster.co talent path: https://mmonster.co/wow-forever/tools/talent-path/druid
- Not readable (403 or certificate errors): Icy Veins Feral, Mobalytics, wowforeverbuilds.com, foreverdiff.com, wowvendor, exitlag, wow4ever.quest.
- Project docs read: warrior research doc, class-pack guide (README, hekili, walkthrough, boundary, cookbook), Druid and Warrior packs,
  gate-spike findings, parity-2 aura rows.
