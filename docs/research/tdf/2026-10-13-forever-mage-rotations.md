<!-- Ported from TacoDogForever docs/research/2026-10-13-forever-mage-rotations.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# WoW Forever mage: Frost, Fire and Arcane rotations and a pack design (2026-10-12)

Research for a Taco Dog Forever Mage pack. Forever is client 1.60.1 (Interface 16001), beta, level cap 30 (full 1-60 trees are
visible but untested at 60); launch is announced for 2026-11-04. Sources: Blizzard's Mage deep dive (2026-10-07) and dev notes
(09-24, 10-01, 10-08), Forever's DB2 (build 1.60.1.70338, our shared data and the local SQLite it came from), the wowtbc.gg
talent-calculator JSON (rank text), and guides listed in section 10 (S1..S18). **Nobody has published a tested rotation**; every
guide says "sims will tell". Tags used on each claim:

- **FV** Forever-verified: Blizzard post or notes, DB2 1.60.1.70338, or two independent Forever sources agree.
- **VA** vanilla-assumed: Classic Era behaviour that nothing in Forever contradicts.
- **IN** inferred: my arithmetic or logic from DB2 numbers; no source says it.
- **?** single weak source or contradicted; do not build on it.

## 1. What Forever's mage is

Classic Era 1.15 trees and spell ranks, rebuilt around a **talent-granted spell** model. The DB2 still carries every Season of
Discovery rune (`Engrave ...` spells, Arcane Barrage/Surge, Icy Veins 425121, Living Bomb, Frozen Orb, Spellfrost/Balefire
Bolt, Molten Armor 428741, Brain Freeze, Burnout, Deep Freeze ...) with acquire method 3; Blizzard "fixed an issue that made a
Season of Discovery rune ability visible" (09-24). **No Forever source offers runes; the pack ignores them (FV by absence).** Two
guides list SoD abilities (wowtbc.gg Frost says "Molten Armor" and "Missile Barrage procs"; wowforever.games says "Arcane
Barrage" and "Mind Mastery"): template/AI residue, rejected.

New or rebuilt (talent point counts: the milestone talents sit at 11, 16, 21 and 31 points = levels 20, 25, 30, 40):

| Thing | Forever behaviour | Tag |
|---|---|---|
| **Arcane Blast** (Arcane, 11 pts, row 3) | 2.5 s cast, 15% of **base** mana (all 5 ranks), 5 ranks: the talent gives R1 (L20); ranks 2-5 are ordinary class spells at L30/40/50/60 in DB2 (trainer, per one source; unconfirmed). Each cast: other spells +10% damage, Arcane Blast's own cost +175% (additive, so cost x2.75/4.5/6.25/8 at 1..4 stacks), max 4 stacks, 8 s, "or until any other damage spell is cast". **It does not buff itself.** Buff aura 400573 | FV (S1, S3, S7); additive cost IN |
| **Missile Barrage** (Arcane, 16 pts) | Arcane Blast 40%, Fireball/Frostbolt/Frostfire Bolt 20%: next Arcane Missiles **-50% channel (2.5 s), 0 mana, a missile every 0.5 s**; buff 400589 lasts 15 s | FV (S1, S3, S4) |
| **Ice Lance** (Frost, 11 pts, row 3) | instant, 6 ranks (talent R1 L20; trainer L28/34/42/48/56), 45..160 mana, no cooldown, 30 yd, **+300% vs Frozen** targets (incl. targets treated as Frozen) | FV (S1, S3, S10) |
| **Fingers of Frost** (Frost, row 5, needs Ice Lance) | Chill effects have 15% to grant a 15 s buff that makes your next 1 (rank 1) or 2 (rank 2) spells count the target as Frozen (no root). Buff 400669/400670 (2 stacks) | FV (S1, S4, S10) |
| **Heating Up** (Fire, row 4, needs Pyroblast; was Hot Streak until 10-01) | non-periodic crits of Fireball, Frostfire Bolt, Fire Blast, Scorch: next Pyroblast cast time -25% per stack, max 3, 20 s (was 15). 3 stacks = 1.5 s. Ignite ticks and Pyroblast crits do not count. Buff 400625 | FV (S1, S2, S3) |
| **Frostfire Bolt** | trainer spell L40/50/60, 3 s cast, Fire+Frost, higher of your two school bonuses and lower of target resists, 40% slow, 9 s DoT. Improved Fireball also shortens it; Missile Barrage 20% | FV (S1) |
| **Ignite** | **personal** per Mage (not a raid debuff); 8%/rank, 40% of the crit over 4 s (2 s ticks); closely timed crits no longer lose damage; no longer double-dips % modifiers (09-24) | FV (S1, S2, S4) |
| **Improved Scorch** | 33/66/100% per Scorch to add a stack of +3% Fire damage **from you**, 5 stacks, 30 s. Personal. 10-01: no second resist roll | FV (S1, S2, S4) |
| **Winter's Chill** | personal; 20%/rank chance, **rank = stack cap**; +2% crit per stack to **Ice Lance and Frostbolt only**, 15 s; 5/5 = 100% and 5 stacks. 10-01: no resist roll on application | FV (S1, S4) |
| **Wake of Fire** (was Improved Fire Blast, row 1) | Fire Blast cooldown -1/-2 s; kill of a non-trivial target: next Fire Blast within **30 s** (was 20) +25/+50% crit. Buff 1312934 | FV (S2, S4, S14) |
| **Combustion** | 3 min; each Fire hit +10% Fire crit until **3** non-periodic Fire crits (4 in an early build; back to 3 on 10-01; conquestcapped still says 4: stale). Charges are aura 11129, stack aura 28682 | FV (S2, S3) |
| **Arcane Power** | +30% damage, +30% mana cost, 15 s, 3 min; **now requires Presence of Mind** (3 min) | FV (S1, S4) |
| **Cold Snap** | 10 min (was 5), 21-point row; resets other Frost cooldowns. **No Icy Veins** | FV (S1, S4) |
| Ice Block / Ice Barrier | Ice Block 16-point row (5 min); Ice Barrier 31-pt capstone, requires Cold Snap, 305-480 mana, 30 s, also stops pushback | FV (S1, S4) |
| Mana | Mage Armor (L34!) Spirit regen "increased"; Arcane Meditation 17/33/50% regen while casting (was 15% max); Arcane Mind = Intellect, not max mana; Eureka (gnome) = 10% cheaper + 10% damage on next 3 damaging spells | FV (S1, S4, S18) |
| Smaller | Flamestrike: one active per Mage, no rank overlap; Cone of Cold duration cut (DB2 6 s, 10 s cd); Improved Blizzard slow 15/25/40% (was 65); Improved Counterspell = guaranteed 2/4 s silence; wands no longer scale with spell power; Magic Attunement and Detect Magic removed; Arcane Missiles checks line of sight once per channel (09-24); spells cast at ranks far below your level get less spell damage and proc talents less (Rank 1 Frostbolt at 60 cannot proc Frostbite) | FV (S1, S2, S4) |
| Known issue (10-01) | taking damage during Arcane Missiles fires a full-damage missile. Treat as a bug | FV (S2) |
| Planned | Blizzard says each spec will get "a few more buttons" in coming weeks (10-01). Expect churn; re-read DB2 each build | FV (S9) |

Druid-style surprises here: (a) **mana, not a cooldown, is the rotation**: every source and every forum report is about mana
(see 6); (b) Arcane's stack buff boosts only *other* spells, so repeated Arcane Blasts are a mana tax that you spend on a
different damage spell; (c) three of the five "debuff" mechanics are **personal**, so another mage's Scorch/Ignite/Winter's Chill
never helps you and yours never helps them.

## 2. Specs and the builds players run

Level 30 = 21 points (beta). Talent text and ranks: S4. Talents are **not readable** on Forever; the pack uses spell knowledge
and settings (see 7, 10).

**Arcane (18 talents).** Points that change the rotation: Arcane Blast (1, row 3), Missile Barrage (1, row 4), Arcane
Concentration (Clearcasting 2%..10% per damage spell hit, next damage spell free 15 s; chance falls when casting far below-rank
spells, FV S1), Arcane Meditation (17/33/50% regen while casting), Improved Channeling (Missiles 20..100% / Blast 14..70%
pushback avoidance), Arcane Impact (+2..6% Arcane crit), Presence of Mind, Arcane Mind (+2..10% Int, +20..100% Arcane crit
damage), Arcane Instability (+1..3% damage and crit), Arcane Power (35 pts).
- Level 30 (21/0/0), two published: cwf (S9, 10-04) Focus 5, Concentration 5, Blast, Geometry 2, Impact 2, Barrage, Meditation 3,
  Shielding 1, Presence of Mind; overgear (S11) Focus 2, Channeling 5, Concentration 5, Impact 3, Blast, Meditation 3, Barrage,
  Presence of Mind. cwf and IV both take Blast at 20 and Barrage at 25.
- Level 60: overgear 35/8/8 (Arcane to Power, Incineration 3, Elemental Precision 5, Permafrost 3, Frost Nova 2, Blizzard 3);
  cwf 32/14/5. Untested.

**Fire (17 talents).** Improved Fireball 5 (-0.5 s on Fireball and Frostfire Bolt), Ignite 5, Pyroblast 1 (R1 is a talent, ranks
2-8 train 24..60), Heating Up 1, Improved Scorch 3, Master of Elements 3 (10/20/30% of base mana back on Fire and Frost crits),
Critical Mass 3, Fire Power 5, Wake of Fire 2, Incineration 3 (+2..6% crit on Fire Blast, Scorch, **Ice Lance, Arcane Blast**),
Burning Soul 3 (70% pushback avoidance), Blast Wave 1, Combustion 1 (needs Critical Mass 3).
- Level 30 (0/21/0, mmoexp S14, low confidence storefront): Improved Fireball 5, Ignite 5, Flame Throwing 2, Burning Soul 3,
  Pyroblast, Heating Up, Improved Scorch 3, Blast Wave. IV (S5): Wake of Fire first, then Ignite, Blast Wave, Pyroblast.
- Level 60: cwf 12/34/5; Blizzard's own hybrid example (S1): Ignite + Ice Shards, so a Frostfire Bolt crit is 200% and Ignite adds
  40% of that = **280%** total (FV).

**Frost (19 talents).** Improved Frostbolt 5 (-0.5 s), Ice Lance 1, Fingers of Frost 2, Shatter 3 (17/33/50% crit vs Frozen),
Ice Shards 5 (+20%/rank crit damage, 100% at 5), Winter's Chill 5, Frostbite 3 (5/10/15% to Freeze 5 s per Chill), Permafrost,
Piercing Ice, Frost Channeling 3 (-15% Frost cost), Elemental Precision 5 (+1% Fire/Frost hit each), Cold Snap, Ice Block, Ice
Barrier, Improved Cone of Cold/Blizzard/Frost Nova.
- Level 30 (0/0/21): leprestore (S10, 10-03) Improved Frostbolt 5, Ice Shards 5, Improved Frost Nova 2, Frostbite 3, Ice Lance,
  Ice Block, Shatter 3, Fingers of Frost 1; IV (S5): Improved Frostbolt, Frostbite 3, Elemental Precision 2, Ice Shards, Shatter.
- Level 60: 16/0/35 (leprestore theorycraft, with a Missile Barrage dip), 18/0/33 (cwf), 20/0/31 (PvP). Untested.

Spec detection (the Warrior pack's pattern, `C_SpellBook.IsSpellKnown`): Arcane = Arcane Blast (400574 any rank) or Presence of
Mind (12043); Fire = Pyroblast (11366) or Combustion (11129); Frost = Ice Lance (any rank) or Cold Snap (12472). A 21-point
hybrid (Blast + Lance) is possible; `/tdf spec` decides then. Level 20 and below: no talent spell exists, so default to Frost
(Frostbolt, the best leveling kit per S5, S8).

## 3. Single-target priority

Common to all three: keep Arcane Intellect (30 min..1 h) and one armor up (Frost Armor to L29, Ice Armor L30+, Mage Armor L34+;
Ice/Frost Armor when melee will reach you, Mage Armor for regen while casting; only one at a time) (FV S5). Never downrank
as a habit: rank penalties on damage and procs are new (FV). Rank 1 Frostbolt (25 mana, 1.5 s, 40% slow) is a pull/slow/finisher on
a separate button, not the filler (S5). Oct 8 rescaled Frostbolt and Fireball ranks 1-5 and Arcane Missiles ranks 1-3 (FV S2).

### 3.1 Frost

1. Precombat: Arcane Intellect, armor. (Optional: Ice Barrier in a group.) *FV*
2. **Ice Lance while Fingers of Frost is up.** Spend it before the next Frostbolt and within 15 s; IV says cancel a Frostbolt you
   just started if the proc landed mid-cast, because the next *cast* consumes a charge. *Why:* +300% and Shatter's crit apply, and
   Lance is instant. *IN:* Lance R6 is (145 + coefficient x spell power) x4 vs Frozen; with 300 spell power and the instant-spell
   default coefficient 0.43 (DB2 lists none) that is ~1,100 against ~720 for Frostbolt R11, in a 1.5 s GCD instead of 2.5-3 s.
   *FV (S5, S10, forum S13 reports the mid-cast proc)*
3. **Ice Lance while the target is Frozen** (Frostbite proc, or Frost Nova we cast): first Lance snapshots the Frozen state at
   range; damage can break the freeze, so Lance first. In melee range the freeze may drop before the cast lands. *FV (S5)*.
   Frozen is a target state, so it is not observable (see 7).
4. **Frostbolt** otherwise, highest rank. It is the Chill source: every hit has 15% to give Fingers of Frost, 15% to Freeze
   (Frostbite 3/3), and 100% to add a Winter's Chill stack (+2% crit each to Frostbolt and Lance, cap 5, 15 s). 20% Missile
   Barrage only with the Arcane dip. *FV*
5. **Ice Lance as the movement filler** and to keep Winter's Chill stacks when you cannot hard-cast (160 mana at R6, no cd). *FV (S5)*.
   Needs a `moving` state the engine lacks (section 8 gaps).
6. Wand when mana-starved; drink out of combat. *FV*.

Blizzard/Cone fish procs: Improved Blizzard's Chill and Cone of Cold both count as Chill effects (IN; whether Frostfire Bolt's slow
counts is explicitly unverified, S10).

### 3.2 Fire

1. Precombat: Arcane Intellect, armor, **Pyroblast from range** (6 s cast, 12 s DoT, a crit starts Ignite; cwf and IV both open with
   it, fall back to Fireball when the target is short-lived or already on you). *FV (S5, S9)*
2. **Improved Scorch to 5 stacks, only if the fight is long.** Scorch R7: 178 base, 1.5 s cast, 150 mana. *IN:* about 73% of
   Fireball's damage per second at similar damage per mana, so five casts (7.5 s) cost ~2 s of Fireball output and return +15%
   on all your Fire damage: break-even near 14 s of Fire casting afterwards; use it when the target lives 20+ s (bosses, tank
   pulls with a pack of two or more, never trash). *Refresh* with one more Scorch when the debuff has <= ~5 s left (a Scorch resets
   the 30 s timer and adds a stack up to 5; there is no pandemic carry-over). Scorch crits also build Heating Up, Master of
   Elements mana and Ignite. *FV (mechanics S1,S4), threshold IN*
3. **Combustion** (cooldowns toggle) once Scorch is at 5 stacks, or at the start of a burn if Scorch is off; then Fireball/Pyroblast
   to burn the 3 charges. *VA/FV charges*
4. **Fire Blast when Wake of Fire is up** (kill buff, +25/50% crit, 30 s), else on cooldown (8 s, -1/-2 s with Wake). It is an instant,
   cheap, no-travel hit that crits into Heating Up and refunds Master of Elements mana. *FV (S5, S4)*
5. **Pyroblast when Heating Up >= 2.** *IN from DB2 numbers:* R8 Pyroblast = 583 + 4 x 53 DoT, spell-power coefficient 1.0 direct +
   0.6 over time, against Fireball R12 = 483 + 60 and coefficient 1.0. At 2 stacks Pyroblast is 3.0 s, the same as a 5/5 Improved
   Fireball (3.5-0.5), and does ~1.5x the damage for ~equal mana (440 vs 410); at 3 stacks it is 1.5 s. At 1 stack (4.5 s) it is
   break-even with Fireball; at 0 stacks (6 s) it is worse. mmoexp (S14) says the same ("at one stack continue Fireball"), wowtbc
   (S6) says wait for 3. Make the stack count a setting (default 2). Stacks are consumed by the cast (all at once).
6. **Frostfire Bolt (L40+) or Fireball** as filler. IV and wowtbc say Frostfire Bolt replaces Fireball because it double-dips
   Fire and Frost talents. *IN caution:* DB2 puts FFB R3 at 292 + 57 DoT, coefficient 0.814, against Fireball R12 483 + 60, coefficient
   1.0, but FFB is 0.5 s faster with 5/5 Improved Fireball (2.5 s vs 3.0), cheaper (370 vs 410), slows, and with Ice Shards and
   Ignite crits for 280% (Blizzard). Near parity on raw numbers; a `frostfire` setting (default on once known) lets players flip it.
7. Wand and drink. Fire is reported "the most mana-intensive" (S8) and "worse than Classic" by one level-30 mage (S13).

### 3.3 Arcane

The loop (IV S5, wowtbc S6, overgear S11, cwf S9): **build Arcane Blast stacks, then spend them on a different damage spell, then
repeat.** Stack count is the mana dial.

1. Precombat: Arcane Intellect, armor. Solo/leveling: pull with **Frostbolt** (slow; also a 20% Barrage chance). *FV (S5)*
2. **Arcane Power** (cooldowns toggle) when mana is high (> ~70%, since +30% cost for 15 s), then Presence of Mind into an
   instant Arcane Blast inside the window. Align Berserking/Blood Fury. *FV mechanics, thresholds IN*
3. **Arcane Missiles when Missile Barrage is up** and Blast stacks >= 2 (or the proc has < 4 s left): free, 2.5 s, +10% per stack
   if the channel benefits (unknown, probe M10). *FV mechanics*
4. **Clearcasting: spend it on Arcane Blast at 2-3 stacks** (the next cast costs 6.25x or 8x; free). Otherwise Clearcasting is
   0 cost on whatever comes next. *IN*
5. **Dump at N stacks** (setting, default 3; IV "2-3", overgear "2-3 sustained, 4 for burst"): **Fire Blast** if off cooldown
   (instant, 340 mana), else **Frostbolt** (290 mana, 20% Barrage), **Arcane Missiles** (655 mana) only in an Arcane Power window.
   Any other damage spell removes the stacks. *FV (S5, S6 for Frostbolt at 4 stacks)*
6. **Arcane Blast** to build (2.5 s, cost 15% base x (1 + 1.75 x stacks)). *FV*
7. **Arcane Explosion/Fire Blast while moving** (instants); Presence of Mind covers short moves. No DoTs: a wand is the only
   free filler. *FV (S5)*
8. Wand and drink; stop stacking when the target is nearly dead (do not buy a 6.25x cast for the last 20% of a mob). *FV (S5)*

*Mana math (IN):* four Blasts in a row cost 1 + 2.75 + 4.5 + 6.25 = 14.5 x the 0-stack cost (2.2 x base mana for 15%). A level-25
arcane mage reports "four Arcane Blasts in a row and you're out of mana" (S13), consistent. Two Blasts cost 3.75x, three 8.25x.
Since the buff gives +10% per stack to *one* dump, the third and fourth Blast buy +10% each on a single cast for 4.5x and 6.25x:
default stop at 2-3.

Reddit (S15, 2026-09-13): cast Blast until Missile Barrage procs, then Missiles; "nobody has measured" against four stacks.

## 4. AoE and thresholds

All from IV (S5) unless marked; no sim backs the numbers. None of the mage's AoE has a target-count fall-off (S5).

| Spec | Rule | Switch |
|---|---|---|
| Arcane | Tanked: spam **Arcane Explosion**. Kiting: Frost Nova, Flamestrike (3 s), Cone of Cold, Explosion. Open with 1-2 Blasts so the first AoE gets the stack buff. Blizzard from range for 5+ | AE at **3+** (S5); Blizzard 5+ (IN) |
| Fire | Tanked: **Flamestrike > Blast Wave > Arcane Explosion**. Pulled by you: gather, Frost Nova, Flamestrike, Cone of Cold, Explosion kiting, Blast Wave for the slow | Flamestrike 4+, Blast Wave and Explosion 3+ (IN) |
| Frost | 3+: **Cone of Cold** the group (Chill for Frostbite/Fingers), Ice Lance on unfrozen targets to burn Fingers charges, Lance frozen targets, Frost Nova to create more. 5+: Cone on cooldown, Blizzard between casts, Explosion if you have aggro and cannot channel | 3+ and 5+ (S5) |

*Why 3 (IN):* base Arcane Explosion R6 = 242 per target for 390 mana, 1.5 s. Fireball R12 = 543 for 410 mana, 3.0 s. Two targets is
mana parity (1.24 vs 1.32 per mana) at 1.8x the damage per second; three targets is 1.86 per mana and ~2.7x the rate. Sustained
dungeon play (mana-limited) crosses at 3; solo with full mana can use 2. Blizzard R6 costs 1400 for an 8 s channel and gets
Improved Blizzard's Chill (FoF on every tick: IN). Flamestrike R6 = 417 + DoT, 990 mana, 3 s cast, one at a time.

Tanks hold 3-4 targets (Blizzard dev, FV via S8), so Polymorph one extra target and keep AoE off it (damage breaks Polymorph, so Ignite/
Pyroblast DoT on a sheep also breaks it).

## 5. Cooldowns, defensives, interrupts

**Cooldowns toggle** (`toggle = "cooldowns"`): Arcane Power (12042), Presence of Mind (12043, only inside Arcane Power or for movement),
Combustion (11129), Cold Snap (12472; recommend only when Ice Block, Frost Nova, Cone of Cold and Ice Barrier are all on cooldown, i.e.
everything it would reset: it is not a DPS cooldown), Evocation (12051; below ~20% mana; 8 min), racials: Berserking (Troll 20554,
aura 26635, 10 s, 180 s cd, +10% cast speed), Blood Fury (Orc 20572, 15 s, 120 s cd, +10% spell power), Eureka! (Gnome, 15 s, 120 s cd,
10% cost + 10% damage on the next 3 damaging spells; IDs 1259817/1259821/1259823), Cannibalize (Undead 20577, restores 35% health and
mana over 10 s from a corpse). Troll Berserking also speeds mana use. *FV (S1, S3)*

**Defensives** (no health read in combat, so never auto-recommended; keep as bindable abilities): Ice Block (5 min, 15 mana),
Ice Barrier (30 s cd), Mana Shield, Fire/Frost Ward (30 s), Frost Nova + Blink (Blink 15 s, 35% base mana, breaks stuns/roots),
Polymorph (dungeon job per Blizzard: tanks hold 3-4 targets). Ice Barrier and Ice Block also protect casts from pushback.

**Interrupt: Counterspell** 2139: L24, 100 mana, 30 s cd, off the GCD, 30 yd, 10 s school lockout; Improved Counterspell adds a
guaranteed 2/4 s silence (FV S3, S4). The engine has no target-cast observation (`UnitCastingInfo('target')` is probe PR8), so the
pack registers it for binding and options but leaves it out of the APL; if PR8 passes, add `counterspell,if=toggle.custom1&target.casting`.

## 6. Resources

**Mana is secret even out of combat** (design spec §3; gate spike). Readable: `C_Spell.IsSpellUsable` with `insufficientPower`,
`GetSpellPowerCost` (Clearcasting reads 0), our cast events, `UnitPowerPercent` through a curve for display gates only. So mana
is a belief: pinned by the cost ladder (each spell's cost against usability flips), our own casts, and `Evocation`/mana-gem jumps.

- **Costs.** Flat for most spells (section 9). **Percent-of-base-mana spells need the base mana**: Arcane Blast (15%) and Blink (35%).
  Base mana comes from reading Arcane Blast's own `GetSpellPowerCost` at 0 stacks (cost / 0.15) or a
  level table; Parity-1 row D3 already flags "% costs need mana max". With stacks the readable cost *is* the stack count:
  `stacks = (cost / cost0 - 1) / 1.75` when Arcane Power (x1.3) and Clearcasting (x0) are accounted for (IN).
- **Regeneration.** Spirit-based, in 2 s ticks, **five-second rule**: any mana spent stops regeneration until 5 s later (S5 states
  it for Forever; VA). While casting you keep a fraction: Mage Armor 50% (DB2 aura, all three ranks) + Arcane Meditation
  17/33/50%, which add (IN) up to a cap near 100%. Players report Forever regen "feels faster in combat" (S17, threads disagree
  whether the rate changed); `GetManaRegen()` returns base and casting rates out of combat (probe PR16). Model: tick model
  `interval=2` gated by "no spend in the last 5 s", plus a casting-fraction tick, calibrated by the belief; never hard-code a Spirit
  formula.
- **Evocation** 12051: L20, instant channel 8 s, 8 min, **mana regeneration +1500% and 100% regen uninterrupted** (DB2 aura 110/134); the
  yield scales with Spirit, so it is not a fixed 60%. Missing from the generated data (class mask 0 in DB2 `spell_skill`): the pack needs
  literals.
- **Mana gems.** Conjure Mana Agate/Jade/Citrine/Ruby at L28/38/48/58 (spells 759, 3552, 10053, 10054; cost 530/800/1130/1470). Items
  trigger `Replenish Mana` spells (5405, 10052, 10057, 10058; base 400/600/850/1100 + a die we do not extract; item-to-spell mapping
  inferred by rank), 60 s category in DB2 (Classic shipped 2 min: unverified). Beta known issue: gem cooldown tracking starts only
  after another cast. Needs item support in the engine (open); mana potions and runes likewise.
- **Wand (Shoot, 5019).** Free mana-less filler; Wand Specialization 13/25%; wands no longer scale with spell power, but at L10-30
  "wands do a lot of DPS, comparable to spells" (S5; forum S13: "wanding your life away"). A cast after the wand restarts the 5 s
  clock. Real play at level 20-30 is ~15-20 s casting then ~20 s drinking (S13).
- **No pets, totems or shards.** Channels: Arcane Missiles (5 x 1 s, or 5 x 0.5 s with Barrage) and Blizzard (8 s); Evocation (8 s).
  Cancelling a channel loses the remaining ticks, so never clip it for a Frost Lance proc (IN).

## 7. Auras, procs and trackers

Readability: player buffs are *probably* readable in combat by spell ID (the warrior research lists "player auras by spell ID";
parity-2 H7 still has it as "?"), target debuffs are secret. Fallbacks are the readable costs and our own casts. **Key**: P = player
buff, T = target debuff; "addon" = present in `TacoDogForeverData.MAGE` (most Forever IDs are not: the pack needs literals).

| Key | IDs | Unit | Dur / stacks | Addon | How to know it in combat |
|---|---|---|---|---|---|
| arcane_blast | 400573 | P | 8 s / 4 | no | aura; else own Blast casts, +1 each, cleared by any other damage cast; or the cost ladder above |
| missile_barrage | 400588 (talent), 400589 (buff) | P | 15 s | no | aura; else `GetSpellPowerCost(Arcane Missiles)==0` without Clearcasting |
| clearcasting | 12536 | P | 15 s | yes | `GetSpellPowerCost` = 0 (readable per spike) |
| arcane_power | 12042 | P | 15 s | yes | aura, or own cast + fixed 15 s |
| presence_of_mind | 12043 | P | until next cast | yes | own cast; consumed by the next >0 s-cast spell |
| heating_up | 400624 (talent), 400625 (buff) | P | 20 s / 3 | no | aura; else `GetSpellInfo(Pyroblast).castTime` (6/4.5/3/1.5 s, probe M4) |
| wake_of_fire | 1312934 | P | 30 s | no | aura only (kill event unreadable) |
| combustion | 11129 (3 charges), 28682 (stacking crit) | P | until 3 crits | yes / no | aura; our casts cannot see crits |
| fingers_of_frost | 400647 (talent), 400669, 400670 | P | 15 s / 2 | no | aura only (no cost or cast change); display gate otherwise |
| fire_vulnerability | 22959 | T | 30 s / 5 | yes | own landed Scorches: +1 each (handler), 30 s timer; chance = rank (33/66/100%) |
| winters_chill | 12579 (talent 11180) | T | 15 s / 5 | no | own Frost damage hits; cap = rank (setting) |
| ignite | 412538 | T | 4 s | no | not needed (a damage amplifier, no decision) |
| frostbite freeze / Frozen | 12494 (5 s), 1306620 | T | 5 s | no | **not observable**; Frost Nova (122.., 8 s) from our cast, broken by damage |
| pyroblast / fireball / ffb DoT | 11366.., 133.., 401502.. | T | 12/8/9 s | yes | own casts (`dot.pyroblast.ticking` for the 12 s) |
| flamestrike DoT | 2120.. | T | 8 s | yes | own cast; one at a time |
| armors | Mage 6117.., Ice 7302.., Frost 168.. | P | 30 min | yes | aura out of combat; pack expression `armor_up` |
| arcane_intellect | 1459.. | P | 1 h | yes | aura out of combat |
| ice_barrier | 11426.. | P | 60 s | yes | aura or own cast; stops pushback |
| berserking | 20554 / aura 26635 | P | 10 s | no | own cast + 10 s |

Trackers the pack should register (all allocation-free, per the cookbook): (1) **arcane_blast stacks** from cast observations (`CastSuccess`
of Arcane Blast adds, of any other damage ability clears, 8 s expiry); (2) **fire_vulnerability** from landed Scorch casts at the current target
slot; (3) a **frost_nova** window; (4) **base mana / cost ladder** pinning for percent-cost spells; (5) optionally **heating_up** from a
Pyroblast cast-time read. Do not infer crits. Combustion ends on three crits we cannot see, so give the `combustion` aura a guessed 12 s duration.

## 8. Draft APLs (our dialect, stateless guards)

Pack names: abilities by DB2 key (section 9), auras as in section 7 (`buff.arcane_blast`, `buff.missile_barrage`, ...), `armor_up` a pack
expression (any of the three armor auras), settings `ab_stacks` (num 1-4, default 3), `pyro_stacks` (num 1-3, default 2), `scorch` (bool),
`frostfire` (bool), `mage_armor` (bool), `use_wand` (bool, default true). `shoot` is last: when every spell is unaffordable it is the earliest
ready entry. Lines use only compiler roots (`mana`, `mana.max`, `buff.`, `debuff.`, `dot.`, `cooldown.`, `toggle.`, `settings.`,
`active_enemies`; `mana<mana.max*0.2` assumes the compiler accepts a product on the right-hand side, else use a pack expression `mana_low`;
`shoot` and the other free abilities declare a 0-mana `spend` so Sources poll their usability, as in the Warrior pack). The `precombat` list is called first; the compiler does not yet restrict it to out-of-combat (port plan 1A1), so keep
only buffs and the opener there.

```
# arcane.simc
actions=call_action_list,name=precombat
# Burst cooldown: only with plenty of mana, since it costs +30% for 15 s.
actions+=/arcane_power,if=toggle.cooldowns&!buff.arcane_power.up&mana>=mana.max*0.7
# Presence of Mind turns the next Arcane Blast instant inside the window.
actions+=/presence_of_mind,if=toggle.cooldowns&buff.arcane_power.up&!buff.presence_of_mind.up
# Mana reset when nearly dry; Spirit-scaled, 8 s channel, so only on the cooldowns toggle.
actions+=/evocation,if=toggle.cooldowns&mana<mana.max*0.2
actions+=/call_action_list,name=aoe,if=active_enemies>=3
# Free 2.5 s channel: best with the Blast buff up, or before the proc (15 s) runs out.
actions+=/arcane_missiles,if=buff.missile_barrage.up&(buff.arcane_blast.stack>=2|buff.missile_barrage.remains<4)
# A Clearcasting proc pays for the expensive 3rd/4th Blast.
actions+=/arcane_blast,if=buff.clearcasting.up&buff.arcane_blast.stack>=2&buff.arcane_blast.stack<4
actions+=/arcane_blast,if=buff.presence_of_mind.up
# Spend the stacks: Fire Blast (instant, 8 s cd), then Frostbolt (cheap, 20% Barrage), Missiles only inside Arcane Power.
actions+=/fire_blast,if=buff.arcane_blast.stack>=settings.ab_stacks
actions+=/arcane_missiles,if=buff.arcane_power.up&buff.arcane_blast.stack>=settings.ab_stacks
actions+=/frostbolt,if=buff.arcane_blast.stack>=settings.ab_stacks
# Build.
actions+=/arcane_blast
actions+=/shoot,if=settings.use_wand
actions.precombat=arcane_intellect,if=!buff.arcane_intellect.up
actions.precombat+=/mage_armor,if=settings.mage_armor&!armor_up
actions.precombat+=/ice_armor,if=!armor_up
actions.precombat+=/frost_armor,if=!armor_up
# Solo pull: Frostbolt slows and can proc Barrage.
actions.precombat+=/frostbolt,if=solo
actions.aoe=flamestrike,if=active_enemies>=4&!dot.flamestrike.ticking
actions.aoe+=/arcane_explosion
```
Notes: `fire_blast` needs no cooldown test (a cooling ability is never ready, so the next line fires). Missile Barrage inside the
dump list uses `arcane_missiles` first (free). `arcane_blast` at the tail is the builder.

```
# fire.simc
actions=call_action_list,name=precombat
# Combustion: stacks of Scorch first (or Scorch off), then burn the 3 charges with Fire casts.
actions+=/combustion,if=toggle.cooldowns&!buff.combustion.up&(debuff.fire_vulnerability.stack>=5|!settings.scorch)
actions+=/evocation,if=toggle.cooldowns&mana<mana.max*0.2
actions+=/call_action_list,name=aoe,if=active_enemies>=3
# Wake of Fire: +25/50% crit on the next Fire Blast for 30 s after a kill.
actions+=/fire_blast,if=buff.wake_of_fire.up
# Improved Scorch to 5 stacks on long fights, refreshed before the 30 s runs out.
actions+=/scorch,if=settings.scorch&debuff.fire_vulnerability.stack<5
actions+=/scorch,if=settings.scorch&debuff.fire_vulnerability.remains<5
# Heating Up shortens Pyroblast: 3.0 s at two stacks (as long as a 5/5 Fireball), 1.5 s at three.
actions+=/pyroblast,if=buff.heating_up.stack>=settings.pyro_stacks
# Fire Blast on cooldown: instant, crits feed Heating Up and Master of Elements.
actions+=/fire_blast
actions+=/frostfire_bolt,if=settings.frostfire
actions+=/fireball
actions+=/shoot,if=settings.use_wand
actions.precombat=arcane_intellect,if=!buff.arcane_intellect.up
actions.precombat+=/mage_armor,if=settings.mage_armor&!armor_up
actions.precombat+=/ice_armor,if=!armor_up
actions.precombat+=/frost_armor,if=!armor_up
# Opening Pyroblast from range puts the 12 s DoT up before the Fireballs.
actions.precombat+=/pyroblast,if=!dot.pyroblast.ticking
actions.aoe=flamestrike,if=active_enemies>=4&!dot.flamestrike.ticking
actions.aoe+=/blast_wave,if=active_enemies>=3
actions.aoe+=/arcane_explosion
```

```
# frost.simc
actions=call_action_list,name=precombat
# Cold Snap only when everything it resets is cooling down (not a damage cooldown).
actions+=/cold_snap,if=toggle.cooldowns&!cooldown.ice_block.ready&!cooldown.frost_nova.ready&!cooldown.cone_of_cold.ready&!cooldown.ice_barrier.ready
actions+=/evocation,if=toggle.cooldowns&mana<mana.max*0.2
actions+=/call_action_list,name=aoe,if=active_enemies>=3
# Fingers of Frost: instant, +300% and Shatter; spend before the next Frostbolt.
actions+=/ice_lance,if=buff.fingers_of_frost.up
# Chill source and Winter's Chill stacker; highest rank.
actions+=/frostbolt
actions+=/shoot,if=settings.use_wand
actions.precombat=arcane_intellect,if=!buff.arcane_intellect.up
actions.precombat+=/mage_armor,if=settings.mage_armor&!armor_up
actions.precombat+=/ice_armor,if=!armor_up
actions.precombat+=/frost_armor,if=!armor_up
actions.aoe=cone_of_cold
actions.aoe+=/ice_lance,if=buff.fingers_of_frost.up
# 5+: Blizzard between Cones (a channel: see the gaps); explosion when you cannot stand still.
actions.aoe+=/blizzard,if=active_enemies>=5
actions.aoe+=/arcane_explosion,if=active_enemies>=5
actions.aoe+=/frostbolt
```

**Engine gaps the mage hits** (from the parity-1/3/4 audits; parked for core, not pack work): (1) channels (A25/A26, B8: Arcane Missiles,
Blizzard, Evocation look instant and get clipped); (2) `moving` (A35): Ice Lance/Fire Blast/Explosion-while-moving lines cannot be
written; (3) enemy count fixed at 1 (B17): the AoE lists never fire until nameplate counting lands; (4) cast pushback (A28); (5) item
spells (mana gems, potions); (6) a percent-of-base-mana `spend`; (7) target cast state for Counterspell (G060).

## 9. Spell and aura table

IDs and numbers from the generated data addon (DB2 1.60.1.70338); trainer levels read back from DB2 `spell_info`. Talent spells' own
levels are meaningless; costs are the top rank's; durations are the top rank's (Frostbolt's is its chill). `ids` order is rank order
(Ice Lance rank 1 is 1312002, not the lowest number).

| key | name | ranks: spell IDs | trainer levels | cost | cast s | dur s | cd s | gcd |
|---|---|---|---|---|---|---|---|---|
| frostbolt | Frostbolt | 116,205,837,7322,8406,8407,8408,10179,10180,10181,25304 | 4,8,14,20,26,32,38,44,50,56,60 | 290 | 3 | 9 | 0 | 1.5 |
| fireball | Fireball | 133,143,145,3140,8400,8401,8402,10148,10149,10150,10151,25306 | 1,6,12,18,24,30,36,42,48,54,60,60 | 410 | 3.5 | 8 | 0 | 1.5 |
| scorch | Scorch | 2948,8444,8445,8446,10205,10206,10207 | 22,28,34,40,46,52,58 | 150 | 1.5 | 0 | 0 | 1.5 |
| pyroblast | Pyroblast | 11366,12505,12522,12523,12524,12525,12526,18809 | talent R1; 24,30,36,42,48,54,60 | 440 | 6 | 12 | 0 | 1.5 |
| fire_blast | Fire Blast | 2136,2137,2138,8412,8413,10197,10199 (+ SoD variants 400616,400618-400623) | 6,14,22,30,38,46,54 | 340 | 0 | 0 | 8 | 1.5 |
| frostfire_bolt | Frostfire Bolt | 401502,1237312,1237313 | 40,50,60 | 370 | 3 | 9 | 0 | 1.5 |
| arcane_blast | Arcane Blast | 400574,1239696,1239697,1239699,1239700 | talent R1 (L20); 30,40,50,60 | 15% base | 2.5 | 0 | 0 | 1.5 |
| arcane_missiles | Arcane Missiles | 5143,5144,5145,8416,8417,10211,10212,25345 | 8,16,24,32,40,48,56,56 | 655 | 0 (channel 5) | 5 | 0 | 1.5 |
| ice_lance | Ice Lance | 1312002,400640,1240044,1240045,1240046,1240047 | talent R1 (L20); 28,34,42,48,56 | 160 | 0 | 0 | 0 | 1.5 |
| arcane_explosion | Arcane Explosion | 1449,8437,8438,8439,10201,10202 | 14,22,30,38,46,54 | 390 | 0 | 0 | 0 | 1.5 |
| flamestrike | Flamestrike | 2120,2121,8422,8423,10215,10216 | 16,24,32,40,48,56 | 990 | 3 | 8 | 0 | 1.5 |
| blizzard | Blizzard | 10,6141,8427,10185,10186,10187 | 20,28,36,44,52,60 | 1400 | 0 (channel 8) | 8 | 0 | 1.5 |
| cone_of_cold | Cone of Cold | 120,8492,10159,10160,10161 | 26,34,42,50,58 | 555 | 0 | 6 | 10 | 1.5 |
| blast_wave | Blast Wave | 11113,13018,13019,13020,13021 | talent R1; 36,44,52,60 | 545 | 0 | 6 | 45 | 1.5 |
| frost_nova | Frost Nova | 122,865,6131,10230 | 10,26,40,54 | 145 | 0 | 8 | 25 | 1.5 |
| counterspell | Counterspell | 2139 | 24 | 100 | 0 | 10 | 30 | 0 |
| arcane_power | Arcane Power | 12042 | talent | 0 | 0 | 15 | 180 | 0 |
| presence_of_mind | Presence of Mind | 12043 | talent | 0 | 0 | until used | 180 | 0 |
| combustion | Combustion | 11129 | talent | 0 | 0 | 3 crits | 180 | 0 |
| cold_snap | Cold Snap | 12472 | talent | 0 | 0 | 0 | 600 | 0 |
| ice_barrier | Ice Barrier | 11426,13031,13032,13033 | talent R1; 46,52,58 | 480 | 0 | 60 | 30 | 1.5 |
| ice_block | Ice Block | 11958 | talent | 15 | 0 | 10 | 300 | 1.5 |
| blink | Blink | 1953 | 20 | 35% base | 0 | 1 | 15 | 1.5 |
| mana_shield | Mana Shield | 1463,8494,8495,10191,10192,10193 | 20,28,36,44,52,60 | 140 | 0 | 60 | 0 | 1.5 |
| mage_armor | Mage Armor | 6117,22782,22783 | 34,46,58 | 490 | 0 | 1800 | 0 | 1.5 |
| ice_armor | Ice Armor | 7302,7320,10219,10220 | 30,40,50,60 | 500 | 0 | 1800 | 0 | 1.5 |
| frost_armor | Frost Armor | 168,7300,7301 | 1,10,20 | 170 | 0 | 1800 | 0 | 1.5 |
| arcane_intellect | Arcane Intellect | 1459,1460,1461,10156,10157 | 1,14,28,42,56 | 1510 | 0 | 3600 | 0 | 1.5 |
| polymorph | Polymorph | 118,12824,12825,12826 | 8,20,40,60 | 150 | 1.5 | 50 | 0 | 1.5 |
| evocation | Evocation | 12051 | 20 | 0 | 0 (channel 8) | 8 | 480 | 1.5 | **not in the data addon** |
| shoot | Shoot (wand) | 5019 | 0 | 0 | repeating | | 0 | off | not in the data addon |

Per-rank costs (mana, flat): Frostbolt 25/35/50/65/100/130/160/195/225/260/290; Fireball 30/45/65/95/140/185/220/260/305/350/395/410;
Arcane Missiles 85/140/235/320/410/500/595/655; Scorch 50/65/80/100/115/135/150; Pyroblast 125/150/195/240/285/335/385/440; Fire Blast
40/75/115/165/220/280/340; Ice Lance 45/55/70/105/120/160. Frostbolt cast by rank 1.5/1.8/2.2/2.6/3.0 then 3.0 (5/5 Improved Frostbolt -0.5);
Fireball 1.5/2.0/2.5/3.0 then 3.5 (5/5 Improved Fireball -0.5); Missiles 3/4/5 s channel, 1 s ticks. Base damage (before spell power):
Frostbolt R11 475; Fireball R12 483 + 15 per 2 s over 8 s; Pyroblast R8 583 + 53 per 3 s over 12 s; Fire Blast R7 438; Scorch R7 178; Arcane Blast
R5 394 (coefficient 0.714); Missiles R8 209 per missile (0.286 each); Ice Lance R6 145 (x4 vs Frozen); Frostfire Bolt R3 292 + 19 per 3 s over 9 s.

Data-addon gaps found: Evocation (12051), Presence of Mind and Arcane Power exist but only through talents; none of the Forever buffs in section 7
(400573, 400589, 400625, 400669/70, 1312934, 28682, 12579, 412538) and the wand are present. The generator keeps spells on class skill lines plus
what they trigger; Forever's talents live outside that, so the pack needs literal IDs (commented with the DB2 name) or a `gen_data.py` extension.

## 10. Open questions, probes, sources

**Probes (a "Session M" on a mage, ForeverProbe style).** Stand at a dummy, one block per question; note results with `/fprobe note`.

- **M1 mana secrecy:** `UnitPower/UnitPowerMax('player', 0)` and `GetManaRegen()` in/out of combat, at rest, while casting, after Evocation. Decides
  whether mana is read or believed and gives the regen rates.
- **M2 cost reads:** `GetSpellPowerCost(Arcane Blast)` at 0..4 stacks, with Arcane Power, with Clearcasting, with Missile Barrage on Missiles. Expect
  1/2.75/4.5/6.25/8 x base; confirms stack inference and the additive 175%.
- **M3 player auras in combat** by ID: 400573, 400589, 400625, 400669/400670, 12536, 12042, 12043, 1312934, 28682/11129, armors. Stacks and expiry
  readable, or secret? (also decides whether Fingers of Frost can be recommended at all.)
- **M4 Pyroblast cast time** (`GetSpellInfo(...).castTime`) at 0..3 Heating Up stacks and under Presence of Mind.
- **M5 talent passives:** `C_SpellBook.IsSpellKnown` on Improved Scorch ranks (11095/12872/12873), Ignite (11119..), Arcane Concentration
  (11213/12574..), Missile Barrage 400588, Heating Up 400624, Fingers of Frost 400647, Winter's Chill 11180.. Lets the pack read ranks.
- **M6 spell usability:** is Counterspell "usable" without a casting target; does Ice Lance/Fire Blast usable flip on Frozen/Wake of Fire?
- **M7 target casts:** `UnitCastingInfo/ChannelInfo('target')` incl. `notInterruptible` (runbook PR8) for Counterspell timing.
- **M8 channels:** `UnitChannelInfo('player')` during Arcane Missiles, with Barrage (2.5 s / 0.5 s?), and Blizzard; `UNIT_SPELLCAST_CHANNEL_*`.
- **M9 Evocation yield** (screenshots of the mana bar before/after at known Spirit), mana-gem restore and cooldown (60 s or 2 min?) and
  whether `IsSpellUsable(10058)` works for an item spell.
- **M10 Arcane Blast buff vs Missiles:** does the channel consume the stacks at its start, and do all five missiles carry the bonus? (Blizzard's
  text says "until another damage spell is cast"; wfg says the descriptions disagree on cast vs damage spell.)
- **M11 Chill sources:** which of Frostbolt, Cone of Cold, Blizzard (Improved Blizzard), Frostfire Bolt, Frost Armor/Ice Armor hits grant Fingers
  of Frost and Frostbite (S10 flags Frostfire Bolt as unknown).
- **M12 nameplate count** for `active_enemies` (PR6) and **movement** (`IsPlayerMoving`).

**Open design questions.** (1) Optimal Arcane stack target and whether Fire Blast/Frostbolt/Missiles is the better dump (no sims; default 3);
(2) Frostfire Bolt vs Fireball for Fire at 40+ (near parity on raw numbers, section 3.2); (3) how many Heating Up stacks to wait for (default 2);
(4) Scorch worth it on dungeon fights (>= ~20 s); (5) Cold Snap value (none in DPS; PvP/defensive only); (6) whether runes or extra "buttons" arrive
(Blizzard promised more buttons per spec); (7) how Combustion's three charges interact with Heating Up. (8) Does Missile Barrage's 15 s buff survive
a stack-dump? (9) Level 60 numbers: the whole 31+ point layer (Arcane Power, Combustion, Ice Barrier) is untested.

**Confidence.** Frost: medium (mechanics FV, rotation shape agreed by three sources, no sim, Frozen state unobservable). Fire: medium-low
(Heating Up/Scorch mechanics FV, priority between Pyroblast stacks, Scorch and Frostfire is IN). Arcane: medium (Blast/Barrage mechanics FV,
stack count and dump choice are judgment, buff-vs-channel interaction unknown). All three: mana belief and AB percent cost need probes M1/M2.

**Sources** (all fetched 2026-10-12 unless noted; "(rank text)" = used for numbers):
- S1 Blizzard, "Forever Class Deep Dives: Mage and Shaman", 2026-10-07: https://worldofwarcraft.blizzard.com/en-us/news/24302097
- S2 Blizzard Beta Development Notes 09-24 (mirror https://www.arenamaster.io/news/638-wow-forever-beta-development-notes-updated-october-8), 10-01 and 10-08
  (summaries https://wowforeverguides.com/classes/changes, https://wowforeverguides.com/news/wow-forever-beta-patch-notes-october-8)
- S3 Forever DB2 build 1.60.1.70338 (`~/.local/share/wow-db2/forever/current.sqlite`; `TacoDogForever_Data/Generated/Spells.lua`)
- S4 wowtbc.gg Forever mage talent calculator JSON (rank text): https://wowtbc.gg/page-data/warcraftforever/talent-calculator/mage/page-data.json
- S5 Icy Veins Forever guides: https://www.icy-veins.com/wow-forever/frost-mage-ranged-dps-pve-guide, .../arcane-mage-ranged-dps-pve-guide,
  .../fire-mage-ranged-dps-pve-guide (undated; level-30 beta; WebFetch 403, read with curl)
- S6 wowtbc.gg Forever rotations (templated, low): https://wowtbc.gg/warcraftforever/class-guides/{fire,frost,arcane}-mage/
- S7 classicwow.gg Forever mage, updated 2026-10-08: https://classicwow.gg/forever/guides/mage
- S8 wowforeverguides.com mage and spec pages, 2026-09-13 updated 10-11: https://wowforeverguides.com/classes/mage (+ /arcane, /fire, /frost)
- S9 classicwowforever.com mage guides, 2026-10-04..07: https://classicwowforever.com/class-guides/mage/ (+ /arcane/, /fire/, /frost/),
  https://classicwowforever.com/class-changes/mage/
- S10 leprestore Frost, 2026-09-22 upd 10-03: https://leprestore.com/guides/world-of-warcraft-forever/wow-forever-frost-mage-guide-best-builds-race-professions/
- S11 overgear Arcane (undated, Oct): https://overgear.com/guides/wow-forever/arcane-mage-how-to-play/
- S12 conquestcapped, 2026-10-04: https://conquestcapped.com/guides/wow-forever/wow-forever-mage-talents/
- S13 Blizzard forum threads, 2026-10-02/06: https://us.forums.blizzard.com/en/wow/t/the-death-of-mages-in-wow-forever/2369703,
  https://us.forums.blizzard.com/en/wow/t/mage-at-30-serious-concerns/2374603
- S14 mmoexp Fire level 30 guide, 2026-10-10 (gold storefront, low): https://www.mmoexp.com/News/wow-forever-fire-mage-level-30-guide-talents-rotation-and-mana-management.html
- S15 r/classicwow Hot_Constant7764, 2026-09-13 (via S9); S16 Esfand video 2026-09-14 (via S8)
- S17 https://us.forums.blizzard.com/en/wow/t/mana-regen-in-wow-forever/2359901 (2026-09-24/25, player claims)
- S18 Gnome/racial text: Blizzard Create the Hero (2026-09-22) via S8
- Rejected: https://www.wowforever.games/49.html, /500.html (AI templates: "Mind Mastery", "Arcane Barrage").
- Hekili `origin/classic:Classic/Mage.lua` is a 5197-line WotLK-shaped spec with three serialized Wowhead packs (not readable SimC); not used.
