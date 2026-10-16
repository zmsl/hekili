<!-- Ported from TacoDogForever docs/research/2026-10-13-forever-warlock-rotations.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# WoW Forever warlock: rotations, mechanics and a pack design (2026-10-12)

Research for a Taco Dog Forever Warlock pack (research only, no code changed). Evidence tags on every claim:

- **[DB2]** Forever DB2, build 1.60.1.70338 (`~/.local/share/wow-db2/forever/current.sqlite`, the data addon's source), queried directly.
- **[FDB]** ForeverDB (foreverdb.net): extracts the same build (70338, updated 2026-10-12/13) and diffs it against Classic Era 1.15.9. Its
  "level 30 simulator" tips are tagged **[SIM]**.
- **[BLZ]** Blizzard's Rogue and Warlock deep dive (2026-10-07) and beta development notes. **[GUIDE]** a Forever guide (dated in Sources).
- **[VAN]** vanilla-assumed (not re-verified on Forever). **[INF]** inferred by me; a probe is listed in section 10.

Confidence: **Affliction medium-high** (kit and numbers from the client, priorities from two simulators and two trainers that
mostly agree, but only levels 20-30 are playable and Wrack, level 40, is untested), **Destruction medium** (guides disagree on
Conflagrate and on Incinerate vs Shadow Bolt; the sim says leave Conflagrate out at 30), **Demonology medium-low** (it is "pet +
Shadow Bolt + DoTs"; every Demonology talent that matters is a pet or sustain effect we cannot observe), **levels 40-60 low**
(the beta cap is 30; launch is 2026-11-04 with cap 60 and 51 talent points; level 60 builds are theorycraft [GUIDE]).

## 1. What Forever changes in the warlock

**The tree is a rebuild, not a reskin.** 18 new talents, 33 changed, 12 Classic spells/talents removed, 16 Season of Discovery
leftovers still in the client files [FDB]. What matters for a rotation helper:

- **Curses split into Curses and Banes.** Curse of Agony and Curse of Doom become **Bane of Agony** (DB2 980/6217/11711-11713, level 8,
  215 mana at rank 6, 24 s, 552 damage at rank 6 vs Classic 1044; spell power coefficient 0.133 vs 0.083) and **Bane of Doom** (603,
  level 60, 300 mana, 60 s, 1742 damage when it ends, 60 s cooldown, not castable on players, Doomguard chance on death). A warlock
  may keep **one Bane and one Curse on a target at once**; the Bane slot is shared by Agony, Doom and the new **Bane of Havoc**
  (1225228). "Only one Curse per Warlock" still holds per caster, so another warlock's curses coexist [BLZ] [DB2 descriptions].
  **High.**
- **Curse of Shadow is gone** (no record in the client); **Curse of the Elements now covers every magic school**, four ranks at 20/30/40/50
  (440892, 1311676, 1311677, 1311680: 50/100/150/200 mana, +4/6/8/10% magic damage, -30/-45/-60/-75 resistance, 5 min). Curse of Weakness
  has the improved-curse talent folded in [GUIDE]; **Curse of Recklessness** no longer gives the enemy attack power (-armor, still stops
  fleeing and ignores Fear) [GUIDE]; Curse of Exhaustion is a 16-point talent, 30% slow, 12 s [BLZ]. **High.** Guides that still
  say "otherwise Curse of Shadow" (wowtbc.gg) are stale.
- **Dark Pact is removed** (talent, spells 18220/18937/18938 have no Spell rows). **Wrack replaces it in the tree** [FDB] [BLZ]. There is
  no mana-from-pet button. **High.** Also removed or replaced: Improved Curse of Weakness (now Malediction), Improved Drain Soul (Soul Harvest),
  Improved Drain Life (Soul Siphon), Grim Reach (Malevolence), Improved Drain Mana, Improved Curse of Exhaustion; Devastation, Improved
  Immolate, Emberstorm and the Firebolt/Lash of Pain talents on the Destruction side [FDB].
- **New Affliction capstone Wrack** (1316697): a **6 s channel**, 200 mana, 36 Shadow damage every second (spell power coefficient 0.143
  a tick), and for 6 s the target takes **+10% from your other Shadow DoTs**. Requires Siphon Life (1/1). Level 40 spell, 31-point talent
  [DB2] [BLZ]. Benefits from Improved Drains, Soul Siphon, Fel Concentration, Pandemic; **can proc Nightfall** [BLZ]. **High** on the kit.
- **New Destruction capstone Incinerate** (412758/1293812/1293813, levels 40/50/60, 205/265/325 mana, **2.5 s cast**, 90-104 / 134-156 /
  201-233 Fire, coefficient 0.714, **+25% if Immolate is on the target**); 31-point talent requiring Bane of Havoc [DB2] [FDB]. Bane
  shortens its cast. **High.**
- **Conflagrate is a 16-point talent** with six ranks (levels 25/32/40/48/54/60: 1293817, 1293818, 17962, 18930, 18931, 18932; 100-255
  mana, 10 s cooldown, instant, coefficient 0.429) that **consumes Immolate**; **Shadow and Flame** (new, 25 points) lets it keep Immolate
  (20% per rank) and raises Shadow damage 10% for 20 s; **Shadowburn** (talent, 15 s cooldown, six ranks 20-56, instant, coefficient
  0.429, **kill window 8 s instead of 5 s**, range 30 yd) raises Fire damage 10% for 20 s and refunds its shard 20% per rank [DB2]
  [BLZ] [FDB]. **High.**
- **DoTs can crit and are not snapshotted** (they update with your current stats on every tick); **haste does not speed DoTs or
  channels**; haste is now a secondary stat; the debuff slot cap is removed [GUIDE: Warcraft Tavern, LepreStore, Blizzard forum
  thread]. **Pandemic is a crit-damage talent here (+33/67/100% crit bonus on Corruption, both Banes, Siphon Life, the drains,
  Wrack), not Retail's refresh rule.** DB2 427712. **Medium-high.**
- **Life Tap converts health to mana 1:1 plus Spirit** (`420 (+100% of Spirit)` at rank 6) [DB2] [FDB]. Improved Life Tap +10/20%. The
  tooltip once said half; Blizzard fixed the text on 2026-09-24 and a forum thread still disputes the ratio. **Medium.**
- **Drain Soul gives shards on damage ticks** (a chance that rises after each failed tick until guaranteed; always on a kill of a
  non-trivial target). Casting another spell now stops the channel (2026-10-01). **High.**
- **Soul Harvest** (was Improved Drain Soul): killing a non-trivial target with your Drain Soul on it gives +100% mana regeneration for 10 s
  and lets 100% of normal regeneration continue while casting (DB2 437032, aura 1242853). The wording implies the five-second rule exists
  on Forever. **High** on the effect, **medium** on the rule.
- **Firestone and Spellstone are weapon imbues** (3 s cast to apply; Firestone: spell crit and Fire damage; Spellstone: spell haste and
  Shadow damage) that stack with Wizard Oil; the Improved Firestone/Spellstone talents are removed [BLZ] [DB2 758/17945/17947/17949,
  1237152/1237156/1237159]. **High.**
- **Demonic Sacrifice lasts 2 hours and swaps its effects**: Imp +15% **Shadow**, Voidwalker 2% mana per 4 s, Succubus/Incubus +15%
  **Fire**, Felhunter 3% health per 4 s (DB2 18789-18792). **Demonic Pact** (31 points, DB2 425464): summoning a different demon no
  longer cancels it; re-summoning the sacrificed kind does. Master Demonologist can run alongside it [BLZ]. **High.**
- **Pets scale from your stats**; a new summon stuns the current pet (2026-10-08); Aggressive mode is back; Incubus is a separate summon;
  Enslave Demon is **Subjugate Demon**; Command is removed [BLZ] [GUIDE]. **There is no Felguard**: no trainer spell exists
  (`Summon Felguard` 427733 is an SoD rune), and every guide lists Imp, Voidwalker, Succubus, Incubus, Felhunter, Inferno and Doomguard
  only. **High.**
- **Decimation** (Demonology, new): Soul Fire cooldown -90%; **Shadow Bolt or Searing Pain on a target under 35% health** gives 6% more
  damage and, for 10 s, Soul Fire has -40% cast time and costs no shard (DB2 440870, aura 440873) [BLZ]. **Demonic Brand** (new): Searing
  Pain makes -50% threat and brands the target 10 s; the pet's next 6 attacks add Fire/Shadow damage, Shadow is high threat (2026-10-08).
  **Soul Link** (21 points, 30% of your damage goes to the demon, both deal +3%; 20% of base mana to cast, DB2 19028/25228) and
  **Fel Vitality/Demonic Energies** (the pet gets 50-100% of your Life Tap mana) are new [BLZ]. **High.**
- **Season of Discovery leftovers are dormant** [FDB]: Chaos Bolt (403629), Metamorphosis (403789) and its Demon Charge/Demonic Howl/Menace,
  Shadow Cleave (10 ranks), Shadowflame (426320), Fel Armor (403619), Dance of the Wicked, Demonic Grace, Grimoire of Synergy, Invocation,
  Vengeance, Explorer Imp. No trainer, quest or talent teaches them; a forum thread says some warlocks saw Demon Charge in the spellbook
  as a bug. **The pack must not register them**; `IsSpellKnown` would be false. **High** (absence in every guide and in the tree).
- **Portal of Summoning** (437169, level 60, 2-person channeled ritual, 2 min cooldown) is new; Ritual of Doom/Inferno exist but the
  forum is arguing about the hostile-pet rules; Summon Felsteed/Dreadsteed are no longer warlock abilities [FDB].
- **Racial/economy:** Troll is a new warlock race; Reagent Economy removes vendor reagents but **not Soul Shards** (DB2 1225503,
  [GUIDE]). Wands no longer gain damage from spell power [GUIDE].
- **Base numbers are about half of Classic's, coefficients higher or equal**: Shadow Bolt rank 10 is 253-283 (Classic 482-538) at coefficient
  0.857, Corruption 438 over 18 s (Classic 822) at 0.2 (Classic 0.167), Bane of Agony 552 (Classic 1044) at 0.133 (0.083), Immolate 275 over
  15 s + 158 direct at 0.2 + 0.2 [FDB] [DB2]. Spell power dominates, which is why the DoTs are 40-60% of every simulator's damage.

## 2. Specs and the talent builds players run

Beta cap 30 with **21 points** (talents from level 10; rows at 11/16/21/31 points; 51 points at 60). Tree facts are Blizzard's
(2026-10-07) and the client's. Caveat: the DB2 `Talent` table is the Classic tree with some renames (Wrack and Incinerate absent, Dark
Pact present as a ghost); the shipped tree comes from trait tables we do not have (same finding as the Priest note). Use the web tree.

**Affliction** (the recommended leveling spec: ExpCarry, LepreStore, ForeverDB):
- Level 20: Improved Corruption 5/5 (instant, +10%), Improved Life Tap 2/2, Improved Drains 3/3, Suppression (up to 5/5: +1% hit, -4% threat
  per rank on every spell). Group variant: Suppression 5/5, Improved Corruption 5/5, Amplify Curse [FDB].
- Level 30: Siphon Life 1/1 (also the road to Wrack), Nightfall 2/2 (2% / 4% per tick from Corruption, Drain Soul, Drain Life, Wrack, DB2
  18094/18095, "Shadow Trance" aura 17941, 10 s), Malediction 5/5 (+5% periodic), Pandemic 3/3, Improved Bane of Agony 2/2 (+10%),
  Amplify Curse, Fel Concentration 3/3, Soul Harvest 2/2. Level 60 "Deep Affliction": Nightfall + Wrack (Mmonster).
- **Rotation-changing:** Improved Corruption 5/5 (Corruption instant: refresh rules change), Nightfall (instant Shadow Bolt), Siphon Life
  (an extra DoT and the Wrack gate), Wrack (the filler, level 40), Amplify Curse (+50% on the next Bane of Agony), Soul Siphon (+12% per
  other Affliction effect on the target, max 36%, to Drain Life/Drain Soul/Wrack).

**Destruction** (most personal damage at 20-30 per ForeverDB):
- Level 30 (LepreStore, 0/0/21): Bane 5/5 (-0.5 s on Shadow Bolt, Immolate, Incinerate; Soul Fire -2 s), Cataclysm 3/3 (-10% mana), Ruin 1-5
  (+20% crit damage per rank), Shadowburn, Agonizing Flames 3/3 (+10% Destruction damage), Conflagrate, Improved Shadow Bolt 5/5 (group:
  +20% Shadow damage taken from you for 12 s after a Shadow Bolt crit, **own damage only, no charges**), Bane of Havoc (the 21st point,
  15% of your damage on other targets is copied to the cursed target for 5 min).
- Level 60 "Shadowflame" build (Mmonster): Ruin, Shadow and Flame, Incinerate; Succubus (Sacrifice optional, wowtbc.gg).
- **Rotation-changing:** Bane (cast times), Conflagrate (consumes Immolate), Shadow and Flame (ranks decide the consume chance), Improved
  Shadow Bolt (Shadow Bolt as primary filler), Bane of Havoc (second target), Incinerate (filler at 40+), Fire and Brimstone (+8% Conflagrate
  crit per rank, **does not make Incinerate cleave** per LepreStore).

**Demonology** (pet + caster):
- Level 20: Demonic Embrace, Improved Imp 3/3 (+30% Firebolt, Fire Shield), Unholy Power 5/5 (+10% demon damage), Demonic Energies 2/2, Fel
  Vitality. Level 30: Master Summoner/Fel Domination, Soul Link 1/1 (needs Demonic Sacrifice 1/1 in the tree), Decimation 2/2, Demonic
  Knowledge (+33% of your level as spell damage to you and the pet) [FDB] [GUIDE].
- Level 60: Demonic Sacrifice on the **Imp**, then Demonic Pact and re-summon a **Succubus** (Mmonster); Soul Link kept.
- **Rotation-changing:** Decimation (Soul Fire window), Demonic Brand (Searing Pain for pet threat), Soul Link, Sacrifice/Pact (pet swap).

**Pet choice** (guides disagree; Forever-verified fact is the effect table in section 1):

| Situation | Pet | Reason |
|---|---|---|
| Solo leveling 10-30 | Voidwalker | tanks better than Classic; Sacrifice shield [GUIDE] |
| Group damage at 20-30 | Imp | ForeverDB sim: 9-17% less damage without it; ranged, rarely dies; Blood Pact [SIM] |
| Affliction 60 | Felhunter | Spell Lock/Devour Magic, Master Demonologist -10% magic damage taken (Mmonster) |
| Demonology 60 | Succubus after sacrificing an Imp (Pact) | +15% Shadow (Imp sac) and MD +10% Shadow (Mmonster) |
| Destruction 60 | Succubus | Sacrifice +15% Fire (wowtbc.gg, Mmonster) |

## 3. Single-target priority

Each rule: condition, then reason. [SIM] = ForeverDB level 30 simulator; [GUIDE] = trainer/guide; [INF] = mine. The two sources
agree on the DoT core and differ on the filler (Wrack vs Shadow Bolt) and on Conflagrate.

### Affliction (level 20-30: Siphon Life, Nightfall; level 40+: Wrack)

0. **Pre-pull (out of combat):** Demon Armor; pet out (Imp costs no shard; the rest cost 1 [VAN]); optionally Spellstone imbue; Demonic
   Sacrifice on the Imp (wowtbc.gg: Affliction takes it, +15% Shadow). Voidwalker in front for threat while leveling.
1. **Instant Shadow Bolt when Shadow Trance is up** (aura 17941, readable; 10 s window): free damage, never waste a proc [GUIDE: Mmonster, FDB].
2. **Utility curse** (own slot, does not cost the Bane) if grouped: Elements for casters, Recklessness for physical groups/anti-flee,
   Tongues on casters, Weakness solo vs melee [GUIDE: Warcraft Tavern]. Elements is on the boss in every sim (up 100%, 2.4-3.6% of DPS) [SIM].
3. **Amplify Curse right before Bane of Agony** (30 s window, 180 s cooldown, off the GCD, +50% on that Bane) on bosses/elites; it is the
   only cooldown at 20-30 [SIM] [GUIDE].
4. **Bane of Agony when it is down** (24 s, instant). Refresh on expiry only: the damage is back-loaded ("slow at first, builds up"),
   so an early refresh resets the ramp [DB2 text] [GUIDE: Mmonster "refresh as soon as it runs out"]. Sim uptime 87%, 14% of DPS [SIM].
5. **Corruption** (18 s, 6 ticks): refresh when remaining <= its cast time + ~0.5 s. Instant at Improved Corruption 5/5 (refresh at
   <= ~1 s); with fewer points the 2.0 s cast (0.4 s less per point) makes it < 2.5 s [FDB] [INF]. Mmonster: "before it drops". 12.9% of DPS [SIM].
6. **Siphon Life when down** (30 s, instant, 365 mana at rank 4): worth 1.4% of DPS and a weak heal, but it is the Wrack prerequisite
   and is part of the Pandemic/Malediction stack. Optional below 40 [SIM: 85% uptime] [GUIDE: forum calls it weak].
7. **Life Tap when mana < 35%** and health allows (and between pulls). The simulator's rule at 20-29 and at 30 [SIM]; Mmonster: "when mana is
   low and health is fine"; wowtbc.gg: "ideally while moving" (we cannot observe movement).
8. **Wrack** (200 mana, 6 s channel) as the filler once learned: keeps +10% on your Shadow DoTs, can proc Nightfall, mana-cheap
   (Mmonster). Tension: raw Wrack damage is 0.143 per second against Shadow Bolt's 0.286 at the same spell power
   [INF]; the +10% DoT amplifier (DoTs are 50-60% of Affliction damage [SIM]) and the drain talents are what make it competitive. **Do not
   refresh DoTs by interrupting the channel; refresh between channels.** wowtbc.gg lists "Wrack" and "Wrack replaces Shadow Bolt as the
   filler" on the same page; Mmonster puts Shadow Bolt ahead only for Trance.
9. **Immolate** only while Wrack is unavailable (levels 10-39) and the target lives ~15 s: the sim keeps it 69% (1% of DPS) [SIM]; Mmonster
   level 20 puts it last because its direct hit pulls threat (cast after the Voidwalker holds).
10. **Shadow Bolt** as the filler below level 40 (34-41% of damage at 20-30 [SIM]).
11. **Drain Soul to farm shards** (opt-in toggle): finish a dying non-trivial mob; Soul Harvest gives mana on the kill. **Drain Life** when
    health matters (heals each tick; Improved Drains +20%) [GUIDE].

### Destruction (levels 20-30: Bane, Shadowburn, Conflagrate; 40+: Incinerate, Shadow and Flame)

1. **Utility curse** as above. **Bane of Doom** (60 s, off a 60 s cooldown) only on bosses/elites that live >60 s; it shares the Bane slot,
   so never with Bane of Agony on the same target [GUIDE: wowtbc.gg].
2. **Immolate when down or <= its cast time** (15 s, cast 2.0 s, 1.5 s at Bane 5/5; Aftermath +10% initial per rank). Sim uptime 54%
   (7.7% of DPS) because Conflagrate eats it [SIM].
3. **Bane of Agony and Corruption** are in the Destruction simulator too (BoA 8.2% of DPS, 90% uptime; Corruption 3.7%, 76%) because the
   Forever DoT coefficients are high; LepreStore says "only if the target will live" [SIM] [GUIDE].
4. **Conflagrate: policy depends on Shadow and Flame ranks.** The level 30 simulator removed it from single-target ("1.3% more damage without
   it"; the class page still lists it) [SIM]. Players use it **near the end of Immolate** or for burst (LepreStore); with Shadow and
   Flame 5/5 it never consumes Immolate and goes on cooldown (Mmonster "whenever it is ready") [GUIDE] [BLZ]. Rule: if S&F < 5, cast it
   when Immolate has <= ~4 s left (then re-Immolate); if S&F = 5, on cooldown. The consume chance is not observable.
5. **Shadowburn:** with S&F (Fire +10%, 20 s) on cooldown (15 s) to keep the Fire buff, the shard is refunded 20% per rank; without S&F
   as a **finisher** on a target about to die (the kill-in-8-seconds shard is the point). Sim: cast whenever ready, 1.7% of DPS [SIM];
   Mmonster: "under 20%" [GUIDE]. Target health is hidden on Forever, so the "under 20%" form has no observable gate.
6. **Soul Fire while Decimation is up** (aura 440873, readable): 6 s base cast, 40% faster and shard-free for 10 s; the hybrid build (wowtbc.gg:
   Searing Pain below 35% to trigger it) needs target health, which we cannot read; Shadow Bolt triggers Decimation too, so only
   `buff.decimation.up` matters.
7. **Life Tap < 35% mana** (Cataclysm lowers costs: tap between pulls [GUIDE]).
8. **Filler:** Shadow Bolt while the Conflagrate Shadow buff (aura 1293816, "Shadow") is up or when Improved Shadow Bolt is talented;
   **Incinerate** otherwise at 40+ (+25% only with Immolate on the target; Mmonster: "Shadow Bolt while Shadow and Flame is active,
   Incinerate otherwise"); Shadow Bolt below 40. Searing Pain is a threat spike in groups [GUIDE]; solo only.

### Demonology (pet first)

1. Pet out and fighting (the sim loses 17% without the Imp at 30); Demon Armor; **Soul Link** before combat when talented (20% of base mana,
   lasts while the demon lives).
2. Curse, then **Bane of Agony** (or **Bane of Doom** on a >60 s target), **Corruption** (keeps its 2 s cast in the Demonology builds),
   **Immolate** (sim: 61% uptime) [SIM] [GUIDE: Mmonster Corruption, Immolate, Life Tap, Shadow Bolt].
3. **Soul Fire during Decimation** (below 35% health); **Searing Pain** only with Demonic Brand when the pet needs threat.
4. **Life Tap < 35%** (the Imp gets the same mana with Demonic Energies); **Shadow Bolt** as the filler (39% of damage at 30 [SIM]); Health
   Funnel only when the pet is low (Demonic Energies heals it for part of your damage).

## 4. AoE priority and the switch

- **Rain of Fire** (5740/6219/11677/11678, levels 20/34/46/58; 295 to 1185 mana; 8 s channel at the player's feet): "on packs of three or
  more once the tank has them" [FDB PvE guide, Destruction] and "when a pack will die before multi-DoT pays" [GUIDE: LepreStore]. **Switch at
  3 stacked targets, 4 for Affliction** (Hekili's warlock `aoe = 3` default) [INF].
- **Hellfire** (1949/11683/11684, level 30, 645 to 1300 mana, 15 s channel, **damages you**, high threat, can now crit): tank/mage-grind and
  healer-aware only; default off [GUIDE]. 5+ targets or a tanking warlock [INF].
- **Bane of Havoc** is the two-target tool (Destruction only): cast it on the **second** mob, then hit the first; it uses the Bane
  slot of that mob, not yours on the main one [BLZ] [GUIDE]. The engine cannot express "the other target"; make it a toggle (section 8).
- **Multi-DoT:** instant Corruption (Improved Corruption 5/5) on each mob the tank holds, Bane of Agony only on mobs that live ~12+ s;
  "do not over-DoT short-lived mobs" (LepreStore, ForeverDB). Suppression keeps the threat down [GUIDE].
- Shadow Cleave, Shadowflame and Immolation Aura do not exist (leftovers); there is no Seed of Corruption or Shadowfury. **High.**

## 5. Cooldowns, defensives, interrupts

- **Behind the cooldowns toggle:** Amplify Curse (180 s, 30 s window), Fel Domination (300 s, 15 s: next summon -50% mana and ~6 s faster),
  Death Coil as an emergency (120 s, 3 s horror, heals), Bane of Doom (60 s cooldown, rotational but long-fight only), racials (Troll
  Berserking, Orc Blood Fury, Gnome Eureka!: next three damaging spells half mana, +10% damage [GUIDE]).
- **Defensives (not in the DPS APL):** Soul Link (the demon takes 30%), Demon Armor (rank 5 1580 mana, 30 min), Shadow Ward (30 s),
  Voidwalker Sacrifice (30 s shield, scales with 10% of spell healing), Healthstone (1440 at rank 5), Fear (1.5 s cast, up to 20 s at rank
  3), Howl of Terror (level 40, 40 s), Health Funnel. Soulstone for the healer is a pre-boss habit (400 health, 700 mana) [FDB].
- **Interrupt: Spell Lock** (Felhunter, pet ability): **19244** rank 1 (level 36, 120 mana, 6 s lockout), **19647** rank 2 (level 52, 200 mana, 8 s),
  lockout aura 24259, **30 s cooldown** [DB2 SpellCooldowns CategoryRecoveryTime]; Improved Felhunter takes 2/4/6 s off (to 24 s at 3/3). The
  beta cap of 30 means **no Spell Lock in the beta** (the level 38 demo showed it) [GUIDE]. A pet-bar spell: the engine cannot
  cast it and has no "target is casting" observation, so it is an opt-in hint behind a custom toggle (gap in section 10). Devour Magic
  (19505, level 30) is the Felhunter dispel.

## 6. Resources

- **Mana** is the one hidden resource (power values are secret in and out of combat on Forever [gate spike]). Costs are flat for the ranked spells and **percent
  of base mana** for several utility spells (Fear 15%, Curse of Exhaustion 8%, Soul Link 20%, Bane of Havoc 5%, Fel Armor 28% (dormant), summons
  80-100%, Create Soulstone 85%), which gives the belief a usable **cost ladder** for `IsSpellUsable` short reports. Regeneration:
  Spirit-based with the five-second rule [VAN; implied by Soul Harvest's text]; Soul Harvest +100% for 10 s after a drain kill; Blessing of
  Wisdom is the best party buff in the sim (+1.5% DPS at 30) [SIM]. Spellstone adds haste; no mana-per-hit effects exist.
- **Life Tap** (6 ranks, 1454/1455/1456/11687/11688/11689; GCD 1.5 s; instant): health cost = mana gained = `base + Spirit` (+10/20% Improved
  Life Tap) [DB2, FDB]. "At level 6, rank 1 costs about a third of your health" [GUIDE]. Pair with Drain Life/Siphon Life to refill health;
  Demonic Energies gives the pet 50/100% of the mana. A safe rule is mana-based, not health-based, because player health may be hidden;
  the spell's own usability refuses when health cannot pay (probe 3).
- **Soul shards are items** (item 6265), not a power type. Sources: Drain Soul ticks (progressive chance) and guaranteed on kill, Shadowburn kill
  inside 8 s, Shadow and Flame refund (20%/rank), Decimation makes Soul Fire free for 10 s. Sinks: Voidwalker/Succubus/Incubus/Felhunter summons, Soul
  Fire, Shadowburn, Healthstone/Soulstone creation, Ritual of Summoning [VAN; the forum reports Ritual of Summoning consumes none]. Imp is free
  [VAN]. The reagent table is not in our CSVs. Recommended model: shard-spending abilities gate on **game usability** (as the Warrior pack does),
  not on a count (section 7).
- **Pets** are not modelled by core ("pet auras aren't modelled yet"); pet existence matters only for pre-pull and for Demonic Sacrifice.
- **Cast times** the pack must know: Shadow Bolt 3.0 s from rank 4 (1.7 / 2.2 / 2.8 for ranks 1-3), Immolate 2.0 s, Corruption 2.0 s, Searing
  Pain 1.5 s, Incinerate 2.5 s, Soul Fire 6.0 s; Bane -0.1 s/rank (-0.5 at 5/5; Soul Fire -2.0 s), Improved Corruption -0.4 s/rank (instant), spell
  haste on top. Talents are not readable by the engine today, so read the cast time from the client (probe 1) or use settings.
- **GCD 1.5 s, spell haste scales it**; Bane of Havoc, Amplify Curse, Demonic Sacrifice and Fel Domination are the off-GCD buttons (DB2:
  `StartRecoveryTime` 0 and no GCD category); Life Tap, every Bane and Curse, Shadowburn, Conflagrate are 1.5 s GCD instants. **Channels** (Wrack, Drain Soul/Life,
  Rain of Fire, Hellfire, Health Funnel) are not built in the engine ("channels not built yet").
- **Wand:** `Shoot` (5019) is the mana-free filler between casts at low levels (damage no longer scales with spell power) [GUIDE].

## 7. Auras, procs and trackers

"Readable" = player aura by spell ID in combat (the Warrior/Priest work assumes it; probe 2 confirms). Target auras are **not** readable in combat
("Auras cannot be accessed when secret while tainted"), so every DoT is **tracked from our casts**: a successful cast of the DoT sets the
aura (the hit/resist outcome is invisible, no combat log); a target swap files it under the old target slot; **Banes and Curses are known
to lose tracking after you drop and re-acquire a target** (Sep 24 known issue). Use pack handlers: casting a Bane removes the other Banes, casting
a Curse removes the other Curses, on the same target.

| Aura / proc | IDs [DB2] | Source | Readable in combat | Belief if not |
|---|---|---|---|---|
| Shadow Trance (Nightfall) | 17941, 10 s | player buff | yes | none needed |
| Decimation (Soul Fire window) | 440873, 10 s | player buff | yes | none |
| Shadow and Flame, Shadow | 1293816, 20 s | player buff after Conflagrate | yes | from our Conflagrate cast |
| Shadow and Flame, Flame | 426311, 20 s | player buff after Shadowburn | yes | from our Shadowburn cast |
| Soul Harvest | 1242853, 10 s | player buff on drain kill | yes | kill unobservable |
| Amplify Curse | 18288, 30 s | player buff | yes | from our cast |
| Demon Armor | 706, 1086, 11733-11735, 30 min | player buff | yes | from our cast |
| Demonic Sacrifice | 18789 (Shadow), 18790 (health), 18791 (Fire), 18792 (mana), 2 h | player buff | yes | from our cast |
| Soul Link | 25228 | player buff | yes | from our cast |
| Fel Domination | 18708, 15 s | player buff | yes | from our cast |
| Corruption | 172, 6222, 6223, 7648, 11671, 11672, 25311 (12/15/18 s by rank: R1 12, R2 15, R3+ 18) | target | **no** | cast; 3 s ticks |
| Bane of Agony | 980, 1014, 6217, 11711-11713, 24 s, 2 s ticks | target | no | cast |
| Bane of Doom | 603, 60 s (damage at the end) | target | no | cast; ends the Bane |
| Bane of Havoc | 1225228, 300 s | target (another mob) | no | cast; `active_dot` |
| Curse of the Elements | 440892, 1311676, 1311677, 1311680, 300 s | target | no | cast |
| Other curses | Recklessness 704/7658/7659/11717, Weakness 702/1108/6205/7646/11707/11708 (120 s), Tongues 1714/11719 (30 s), Exhaustion 18223 (12 s) | target | no | cast |
| Siphon Life | 18265, 18879, 18880, 18881, 30 s, 3 s ticks | target | no | cast |
| Immolate | 348, 707, 1094, 2941, 11665, 11667, 11668, 25309, 15 s (all ranks) | target | no | cast; Conflagrate consumes (unless S&F) |
| Wrack | 1316697, 6 s | target | no | cast; channel |
| Shadow Vulnerability (Improved Shadow Bolt) | 17794, 12 s, +4%/rank | target | no | only from crits; unknowable, so model as a talent setting |

**Trackers the pack should write:**
- **Cast tracker** (generic): CastSuccess sets/refreshes a DoT; CastStop does not. Banes/Curses mutual exclusion in handlers. This is what the
  Druid bleed tracker does without the combo-point evidence; no hit evidence exists for DoTs.
- **Gate tracker** (Warrior pattern, `Gates.lua`): `IsSpellUsable` reports as gate auras for `shadowburn`, `soul_fire`, the summons (shard
  or "not usable") and for `conflagrate` if the client greys it without Immolate (probe 5). Core treats a spell the player does not know as
  never ready.
- **Consume tracker:** a Conflagrate cast removes Immolate unless `settings.sf_ranks` = 5 (expected value for 1-4 is "consumed"; the cost is a
  recast of a still-running Immolate, never a missed one).
- **Pet tracker (core gap):** `UnitExists("pet")`/pet family as a believed aura for pre-pull summon prompts and Sacrifice.
- **Do not model:** snapshotting (none), pandemic carry-over (none: refreshing replaces the timer; set the DoT auras' `pandemic = 0` so
  `applyDebuff` resets to the full duration [VAN], probe 6).

## 8. Draft APLs (our dialect)

Conventions: `known` and the game's usability gate every line, so unlearned spells are skipped; `dot.x`/`debuff.x` are the cast-tracked target
auras; `=` is equality; `<?`/`>?` min/max; `buff.pet` is a pack-tracked "demon out" aura (section 7); `mana_pct` is a pack expression (`100 * mana / mana.max`, divisor guarded: never divide by 0).
Settings (bool/num only, talents are not readable): `boss` (target lives long), `curse` (0 none, 1 Elements, 2 Recklessness, 3 Weakness,
4 Tongues, 5 Exhaustion; default 1 grouped, 0 solo via the `group`/`solo` names), `bane` (1 Agony, 2 Doom), `pet` (1 Imp, 2 Voidwalker, 3 Succubus,
4 Felhunter, 5 Incubus), `tap_pct` (35), `sf_ranks` (0-5), `isb` (bool), `conflag_window` (4), `rof_targets` (3), `hellfire` (false),
`sacrifice` (bool). Toggles: `cooldowns` (Amplify Curse, Fel Domination, Death Coil, racials), `custom1` = interrupts (Spell Lock), `custom2` =
"second target": Bane of Havoc for Destruction, shard farming (Drain Soul) for the others.

### Affliction

```
# Pre-pull and out-of-combat upkeep.
actions.precombat=demon_armor,if=!buff.demon_armor.up                                  # 30 min armor
actions.precombat+=/summon_imp,if=!buff.pet.up&settings.pet=1                          # Imp: no shard, ranged
actions.precombat+=/summon_voidwalker,if=!buff.pet.up&settings.pet=2                   # leveling tank, 1 shard
actions.precombat+=/summon_felhunter,if=!buff.pet.up&settings.pet=4                    # 60: Spell Lock and magic mitigation
actions.precombat+=/demonic_sacrifice,if=settings.sacrifice&buff.pet.up&!buff.demonic_sacrifice.up  # Imp: +15% Shadow, 2 h
actions=call_action_list,name=precombat
# Free damage: Nightfall's Shadow Trance makes the next Shadow Bolt instant (10 s window, readable aura).
actions+=/shadow_bolt,if=buff.shadow_trance.up
# Utility curse in the Curse slot; does not displace the Bane. Group only (the solo default is none).
actions+=/curse_of_the_elements,if=settings.curse=1&!dot.curse_of_the_elements.up
actions+=/curse_of_recklessness,if=settings.curse=2&!dot.curse_of_recklessness.up
actions+=/curse_of_weakness,if=settings.curse=3&!dot.curse_of_weakness.up
actions+=/curse_of_tongues,if=settings.curse=4&!dot.curse_of_tongues.up
actions+=/curse_of_exhaustion,if=settings.curse=5&!dot.curse_of_exhaustion.up
# Amplify Curse (off the GCD, 30 s window) right before a Bane of Agony; cooldowns toggle.
actions+=/amplify_curse,if=toggle.cooldowns&!dot.bane_of_agony.up&settings.bane=1
# Bane slot: Doom on long bosses, else Agony; refresh only on expiry (back-loaded damage, a clip resets the ramp).
actions+=/bane_of_doom,if=settings.boss&settings.bane=2&!dot.bane_of_doom.up&!dot.bane_of_agony.up
actions+=/bane_of_agony,if=settings.bane=1&!dot.bane_of_agony.up&!dot.bane_of_doom.up&!dot.bane_of_havoc.up
# Corruption: refresh inside its cast time plus latency (instant with Improved Corruption 5/5).
actions+=/corruption,if=dot.corruption.remains<2.5
# Siphon Life: extra DoT, heals, and the Wrack prerequisite.
actions+=/siphon_life,if=!dot.siphon_life.up
# Mana: tap below the sim threshold (health gate is the spell's own usability).
actions+=/life_tap,if=mana_pct<settings.tap_pct
# More than a few targets: Rain of Fire (and optional Hellfire) after the DoTs.
actions+=/call_action_list,name=aoe,if=active_enemies>=4
# Opt-in shard farming: Drain Soul as the filler on a dying non-trivial mob.
actions+=/drain_soul,if=toggle.custom2
# Wrack: the level 40 filler (channel); keeps +10% on the other Shadow DoTs.
actions+=/wrack
# Pre-Wrack: Immolate as a fifth DoT on durable targets (Wrack unknown, so never reached once learned).
actions+=/immolate,if=settings.boss&dot.immolate.remains<2.5
# Filler (levels < 40, or when Wrack cannot be afforded).
actions+=/shadow_bolt
actions.aoe=rain_of_fire,if=active_enemies>=settings.rof_targets                      # 8 s channel at the pack
actions.aoe+=/hellfire,if=settings.hellfire&active_enemies>=5                          # self-damaging; off by default
```

### Destruction

```
actions.precombat=demon_armor,if=!buff.demon_armor.up
actions.precombat+=/summon_voidwalker,if=!buff.pet.up&settings.pet=2
actions.precombat+=/summon_imp,if=!buff.pet.up&settings.pet=1
actions.precombat+=/summon_succubus,if=!buff.pet.up&settings.pet=3                    # 60: Sacrifice +15% Fire, or keep for damage
actions.precombat+=/demonic_sacrifice,if=settings.sacrifice&buff.pet.up&!buff.demonic_sacrifice.up
actions=call_action_list,name=precombat
# Curse slot (see Affliction).
actions+=/curse_of_the_elements,if=settings.curse=1&!dot.curse_of_the_elements.up
actions+=/curse_of_recklessness,if=settings.curse=2&!dot.curse_of_recklessness.up
# Bane slot: Doom on >60 s targets, else Agony (the Destruction sim keeps Agony 90% of the time).
actions+=/bane_of_doom,if=settings.boss&settings.bane=2&!dot.bane_of_doom.up&!dot.bane_of_agony.up
actions+=/bane_of_agony,if=settings.bane=1&!dot.bane_of_agony.up&!dot.bane_of_doom.up&!dot.bane_of_havoc.up
# Second target: Bane of Havoc goes on the mob you are NOT attacking (switch to it, press, switch back).
actions+=/bane_of_havoc,if=toggle.custom2&active_enemies>=2&active_dot.bane_of_havoc<1&!dot.bane_of_agony.up
# Soul Fire inside the Decimation window (target < 35%): faster, free of a shard, readable aura.
actions+=/soul_fire,if=buff.decimation.up
# Conflagrate: on cooldown with S&F 5/5; otherwise near the end of Immolate so little DoT is thrown away.
actions+=/conflagrate,if=dot.immolate.up&(settings.sf_ranks>=5|dot.immolate.remains<=settings.conflag_window)
# Immolate: refresh inside its cast time (2.0 s, 1.5 s at Bane 5/5).
actions+=/immolate,if=dot.immolate.remains<2.5
actions+=/corruption,if=dot.corruption.remains<2.5&settings.boss                       # sim keeps it 76%; long fights only
# Shadowburn: keeps the Fire buff with S&F (refund chance); otherwise a finisher (needs a health observation, see section 10).
actions+=/shadowburn,if=settings.sf_ranks>0
actions+=/shadowburn,if=target.health.pct<20
actions+=/life_tap,if=mana_pct<settings.tap_pct
actions+=/call_action_list,name=aoe,if=active_enemies>=3
# Filler: Shadow Bolt under the Shadow buff or with Improved Shadow Bolt; Incinerate (+25% on Immolated targets) otherwise; Bolt before 40.
actions+=/shadow_bolt,if=buff.shadow_and_flame_shadow.up|settings.isb
actions+=/incinerate
actions+=/shadow_bolt
actions.aoe=rain_of_fire,if=active_enemies>=settings.rof_targets
actions.aoe+=/hellfire,if=settings.hellfire&active_enemies>=5
```

### Demonology

```
actions.precombat=demon_armor,if=!buff.demon_armor.up
actions.precombat+=/summon_imp,if=!buff.pet.up&settings.pet=1                          # group damage pet, no shard
actions.precombat+=/summon_voidwalker,if=!buff.pet.up&settings.pet=2                   # solo leveling, Soul Link build
actions.precombat+=/summon_succubus,if=!buff.pet.up&settings.pet=3                     # 60: after sacrificing an Imp (Demonic Pact)
actions.precombat+=/soul_link,if=buff.pet.up&!buff.soul_link.up                       # 30% of damage to the demon, +3% for both
actions=call_action_list,name=precombat
actions+=/curse_of_the_elements,if=settings.curse=1&!dot.curse_of_the_elements.up
actions+=/curse_of_recklessness,if=settings.curse=2&!dot.curse_of_recklessness.up
# Bane slot (Mmonster/wowtbc.gg: Doom on >1 min targets).
actions+=/bane_of_doom,if=settings.boss&settings.bane=2&!dot.bane_of_doom.up&!dot.bane_of_agony.up
actions+=/bane_of_agony,if=settings.bane=1&!dot.bane_of_agony.up&!dot.bane_of_doom.up
actions+=/corruption,if=dot.corruption.remains<3                                       # keeps its cast time in the Demonology builds
actions+=/immolate,if=dot.immolate.remains<2.5
# Decimation: Soul Fire shard-free and faster for 10 s after a Shadow Bolt below 35% health.
actions+=/soul_fire,if=buff.decimation.up
actions+=/life_tap,if=mana_pct<settings.tap_pct                                         # the pet receives the same mana with Demonic Energies
# Opt-in: Searing Pain with Demonic Brand to hand the pet threat (custom2), otherwise never in groups.
actions+=/searing_pain,if=toggle.custom2
actions+=/call_action_list,name=aoe,if=active_enemies>=3
actions+=/shadow_bolt
actions.aoe=rain_of_fire,if=active_enemies>=settings.rof_targets
```

**Interrupt hint (all specs, opt-in):** `spell_lock,if=toggle.custom1&target.casting` is not expressible today (no target-cast observation,
no pet-bar cast): keep it out of the APL and show it as a standalone reminder when the toggle is on (section 10, gap 2).

## 9. Spell and aura table

Verified against the data addon (`TacoDogForeverData.WARLOCK`) and DB2; "-" = not applicable. **Not in the data addon**: Curse of the Elements
(4 ranks), Bane of Agony rank 2 (1014), the imbue spells, every pet spell, the auras below the line. The generator drops rows whose
SkillLineAbility ClassMask is 0 (same bug as Priest's Shadow Word: Death); the Affliction/Demonology/Destruction lines are warlock-only,
so a skill-line-owner fallback would recover them.

| Spell (key) | Ranks (IDs, rank 1 first) | Cost | Cast | GCD | Duration | Cooldown |
|---|---|---|---|---|---|---|
| Shadow Bolt (`shadow_bolt`) | 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 (levels 1/6/12/20/28/36/44/52/60/60) | 25-380 mana | 1.7/2.2/2.8/3.0 s | 1.5 | - | - |
| Immolate | 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 | 25-380 | 2.0 s | 1.5 | 15 s DoT + direct | - |
| Corruption | 172, 6222, 6223, 7648, 11671, 11672, 25311 (4/14/24/34/44/54/60) | 35-340 | 2.0 s | 1.5 | 12/15/18 s | - |
| Bane of Agony | 980, 6217, 11711, 11712, 11713 (+1014) | 25-215 | instant | 1.5 | 24 s | - |
| Bane of Doom | 603 (60) | 300 | instant | 1.5 | 60 s | 60 s |
| Bane of Havoc | 1225228 (1), talent | 5% base | instant | **0** | 300 s | - |
| Curse of the Elements | 440892, 1311676, 1311677, 1311680 (20/30/40/50) | 50-200 | instant | 1.5 | 300 s | - |
| Curse of Recklessness / Weakness / Tongues | 704, 7658, 7659, 11717 / 702, 1108, 6205, 7646, 11707, 11708 / 1714, 11719 | 35-175 | instant | 1.5 | 120/120/30 s | - |
| Curse of Exhaustion (talent) | 18223 | 8% base | instant | 1.5 | 12 s | - |
| Amplify Curse (talent) | 18288 | - | instant | **0** | 30 s | 180 s |
| Siphon Life (talent) | 18265, 18879, 18880, 18881 (30/38/48/58) | 150-365 | instant | 1.5 | 30 s | - |
| Wrack (talent, spell at 40) | 1316697 | 200 | 6 s channel | 1.5 | 6 s | - |
| Drain Soul | 1120, 8288, 8289, 11675 (10/24/38/52) | 290 (R4) | 15 s channel | 1.5 | 15 s | - |
| Drain Life | 689, 699, 709, 7651, 11699, 11700 (+variants 403677-403689) | 300 (R6) | 5 s channel | 1.5 | 5 s | - |
| Life Tap | 1454, 1455, 1456, 11687, 11688, 11689 (6/16/26/36/46/56) | health = mana gain | instant | 1.5 | - | - |
| Conflagrate (talent) | 1293817, 1293818, 17962, 18930, 18931, 18932 (25/32/40/48/54/60) | 100-255 | instant | 1.5 | - | 10 s |
| Shadowburn (talent) | 17877, 18867, 18868, 18869, 18870, 18871 (20/24/32/40/48/56) | 105-365 + shard | instant | 1.5 | 8 s kill window | 15 s |
| Incinerate (talent) | 412758, 1293812, 1293813 (40/50/60) | 205/265/325 | 2.5 s | 1.5 | - | - |
| Searing Pain | 5676, 17919, 17920, 17921, 17922, 17923 (18/26/34/42/50/58) | 45-168 | 1.5 s | 1.5 | - | - |
| Soul Fire | 6353, 17924 (48/56) | 305/335 + shard | 6.0 s | 1.5 | - | 60 s |
| Rain of Fire | 5740, 6219, 11677, 11678 (20/34/46/58) | 295-1185 | 8 s channel | 1.5 | 8 s | - |
| Hellfire | 1949, 11683, 11684 (30/42/54) | 645-1300 | 15 s channel | 1.5 | 15 s | - |
| Fear / Howl of Terror / Death Coil | 5782, 6213, 6215 / 5484, 17928 / 6789, 17925, 17926 | 15% base / 150-200 / 435-600 | 1.5 / 2.0 / instant | 1.5 | 10-20 / 10-15 / 3 s | - / 40 s / 120 s |
| Demonic Sacrifice (talent) | 18788 | - | instant | 0 | 2 h | - |
| Fel Domination (talent) | 18708 | - | instant | 0 | 15 s | 300 s |
| Soul Link (talent) | 19028 (aura 25228) | 20% base | instant | 1.5 | until demon dies | - |
| Demon Armor | 706, 1086, 11733, 11734, 11735 (20/30/40/50/60) | 275-1580 | instant | 1.5 | 30 min | - |
| Summons | Imp 688 (80%, no shard), Voidwalker 697, Succubus 712, Incubus 713, Felhunter 691 (100% + shard) | % base | 10 s | 1.5 | - | - |
| Weapon imbues | Firestone 758, 17945, 17947, 17949; Spellstone 1237152, 1237156, 1237159 (create: 6366, 17951-17953; 2362, 17727, 17728) | - | 3 s | - | long | - |
| Spell Lock (pet) | 19244 (36), 19647 (52); aura 24259 | 120/200 | instant | 1.5 | 6/8 s lockout | 30 s |

Procs and passives: Nightfall 18094, 18095 (aura Shadow Trance 17941); Improved Shadow Bolt 17793, 17796, 17801-17803 (aura 17794); Pandemic 427712; Malediction
1225177; Malevolence 1310949; Improved Drains 403511; Decimation 440870 (aura 440873); Shadow and Flame 426316 (auras 1293816, 426311); Fire and
Brimstone 412751; Demonic Brand 1293695; Demonic Energies 1225214; Demonic Knowledge 412732; Demonic Pact 425464; Master Demonologist 23785,
23822-23825; Soul Harvest 437032 (aura 1242853).

## 10. Open questions, probes, data bugs and sources

**Data bugs and gaps (fix before the pack):**
1. `gen_data.py` `select()` drops rows with SkillLineAbility ClassMask 0, so **Curse of the Elements (4 ranks) and Bane of Agony rank 2 (1014)**
   are missing from `TacoDogForeverData.WARLOCK`. The shipped warlock spells on those skill lines are Forever-only (Affliction/
   Demonology/Destruction are warlock-only lines), so a skill-line-owner fallback fixes it. Check the other classes (the Priest note found the
   same).
2. The DB2 `Talent` table is the Classic tree with renames; Wrack and Incinerate are not in it (only as `Spell` rows). Forever's own tree is in trait
   tables the CSV set does not include. ForeverDB's companion addon claims to record each character's talents, so a talent read API may exist.
3. SoD leftovers are in the data addon under Demonology/Destruction (Chaos Bolt, Metamorphosis, Shadow Cleave, Shadowflame, Fel Armor): do not
   register them. `drain_life` carries 6 `variants` (403677-403689, SoD).

**Engine gaps the pack needs:**
- **Channels** (Wrack, Drain Soul/Life, Rain of Fire, Hellfire): a hard cast of the same length stands in; it mis-times DoT application and mana
  spend but keeps GCD planning honest.
- A `mana_pct` form or `mana.pct` the planner can gate; player-health read for Life Tap; **target is casting** and pet-bar casts for Spell Lock;
  `moving` (Life Tap "while moving"); pet existence; item-count read for shards; `GetWeaponEnchantInfo` for the imbues; target health for
  Shadowburn/Decimation/Drain Soul.
- A second-target action ("cast this on the other mob") for Bane of Havoc; a toggle stands in.

**Probes (level 20-30 warlock suffices for 1-8):**
1. Does `C_Spell.GetSpellInfo(id).castTime` reflect Improved Corruption/Bane and haste, and is it plain in combat?
2. `C_UnitAuras.GetPlayerAuraBySpellID` for 17941, 440873, 1293816, 426311, 18288, 25228, 18789-18792 in combat.
3. `UnitHealth("player")`/`UnitHealthPercent` secrecy and `C_Spell.IsSpellUsable(1454)` at low health (does Life Tap grey out at the floor?).
4. Does `UnitPower("player", 0)` read in combat, and what is the five-second rule (regen before/after a cast with `GetPowerRegen`)?
5. `IsSpellUsable(1293817)` without/with Immolate: is Conflagrate greyed without the DoT? (decides the Conflagrate gate).
6. Out of combat on a dummy: does recasting Corruption/Bane/Immolate with time left carry over or replace? (decides `pandemic`.)
7. `C_SpellBook.IsSpellKnown(403629, 403789, 427733, 403619)` (Chaos Bolt, Metamorphosis, Summon Felguard, Fel Armor) must all be false.
8. Shard reads: `C_Item.GetItemCount(6265)` in combat; do Shadowburn/Soul Fire become unusable at 0 shards (reagent in `IsSpellUsable`)?
9. Does Wrack proc Nightfall (Blizzard says yes) and does an early refresh of Bane of Agony keep its ramp?
10. Is Bane of Havoc really off the GCD (DB2 `StartRecoveryTime` 0)? Is the Life Tap ratio 1:1?

**Open questions:** Conflagrate (sim says skip at 30, guides say use it); Wrack vs Shadow Bolt raw damage; whether Siphon Life beats Immolate as the
fifth DoT; whether Shadow Bolt below the Decimation threshold is worth tracking; what the level 60 priorities look like (launch 2026-11-04).

**Sources** (fetched 2026-10-12 unless noted; "-" = no date on the page):
- Blizzard, Rogue and Warlock class deep dive (2026-10-07, corrected version): https://news.blizzard.com/en-us/article/24310968/world-of-warcraft-forever-class-deep-dives-rogue-and-warlock ;
  Warcraft Tavern summary (2026-10-07): https://www.warcrafttavern.com/forever/news/poison-pets-rogue-warlock-deep-dive-for-wow-forever/
- ForeverDB Warlock (build 70338, updated 2026-10-12/13): https://foreverdb.net/class/Warlock , /pve , /changes , /builds (read via curl)
- Blizzard beta development notes (2026-10-08): https://www.mmo-champion.com/content/14592-World-of-Warcraft-Forever-Beta-Development-Notes-October-8-2026
- Blizzard forum: warlock changes thread (2026-09-23/30): https://us.forums.blizzard.com/en/wow/t/wow-forever-warlock-guide-all-the-changes-you-didnt-notice/2359459 ;
  bugs thread (2026-09-24/25): https://us.forums.blizzard.com/en/wow/t/bugs-surrounding-warlock-compiled-from-personal-and-community-experience/2359915
- Mmonster rotation trainer (published 2026-09-26, updated 2026-10-10): https://mmonster.co/wow-forever/tools/rotation-trainer/warlock
- ExpCarry (2026-10-08): https://expcarry.com/wow-forever-warlock-guide ; LepreStore Destruction/Affliction (2026-09-22, updated 2026-10-03):
  https://leprestore.com/guides/world-of-warcraft-forever/wow-forever-destruction-warlock-guide-best-builds-rotation-race-professions/ ,
  https://leprestore.com/guides/world-of-warcraft-forever/wow-forever-affliction-warlock-guide-best-builds-race-professions/
- wowtbc.gg Affliction/Destruction/Demonology (undated, level 30 beta; some lines stale, e.g. Curse of Shadow): https://wowtbc.gg/warcraftforever/class-guides/affliction-warlock/ (and /destruction-warlock/, /demonology-warlock/)
- Warcraft Tavern guide (build 69913, undated): https://www.warcrafttavern.com/forever/guides/warlock/ ; classicwowforever.com changes (2026-10-07, build 70245):
  https://classicwowforever.com/class-changes/warlock/ ; Endgame Tools (2026-09-27, updated 2026-10-09): https://endgametools.com/en/blog/wow-forever-warlock ;
  ConquestCapped (2026-10-04): https://conquestcapped.com/guides/wow-forever/wow-forever-warlock-talents/ ; guided.news (2026-10-08).
- Low trust, read for contrast only: wowforever.games Demonology (2026-09-21, names Hand of Gul'dan and Chaos Bolt: discard), MMOExp (2026-09-21, store promo, claims
  "Ruin is a Shadow DoT"), kami-labs.fr (2026-09-14, pre-rebuild).
- Search only (fetch blocked, 403): Mobalytics Affliction/Demonology/Destruction guides, Icy Veins Affliction guide, Wowhead deep dive page.
- Local: DB2 sqlite (`spell_info`, `talent_info`, `Spell`, `SpellEffect`, `SpellCooldowns`, `SpellPower`, `SkillLineAbility`), `src/TacoDogForever_Data/Generated/Spells.lua`
  (WARLOCK), `docs/class-packs/*`, `src/TacoDogForever_Warrior/*` (gates, stances), `src/TacoDogForever_Druid/Feral.lua`, the Priest note in this folder.
  Hekili behaviour only: `origin/classic:Classic/Warlock.lua` (solo/group curse settings, Shadow Trance, Cataclysm ranks; no readable warlock APL
  exists on the classic branch, its packs are encoded strings).
