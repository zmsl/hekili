<!-- Ported from TacoDogForever docs/research/2026-10-13-forever-priest-shadow-rotations.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# WoW Forever priest (Shadow first): rotations, mechanics and a pack design (2026-10-12)

Research for a Taco Dog Forever Priest pack (research only, no code changed). Evidence tags on every claim:

- **[DB2]** Forever DB2, build 1.60.1.70338 (`~/.local/share/wow-db2/forever/current.sqlite`, the data addon's source), queried directly.
- **[FDB]** ForeverDB (foreverdb.net), which extracts the same build (1.60.1.70338, updated 2026-10-12) and diffs it against Classic Era.
- **[BLZ]** Blizzard's Priest deep dive and beta development notes. **[GUIDE]** a Forever guide (dated in Sources).
- **[VAN]** vanilla-assumed (not re-verified on Forever). **[INF]** inferred by me from the numbers; a probe is listed in section 10.

Confidence: **Shadow high** on the kit, costs and talent effects (client data), **medium** on priorities (guides are
level-30 beta, sim data is level 30 only), **low** on levels 40-60 (Shadowform, Shadow Word: Death untested: the beta cap
is 30; launch is 2026-11-04 with cap 60 and every character starting at 1). **Discipline/Holy damage medium-low.**

## 1. What Forever changes in the priest

**Gone: the Season of Discovery toolkit.** DB2 still holds Vampiric Touch (402668), Shadowfiend (401977), Mind Sear
(413259), Mind Spike (431655), Dispersion (425294), Void Plague (425204), Eye of the Void, Homunculi, Circle of
Healing, Pain Suppression, Power Word: Barrier. FDB lists them as "SoD leftovers: no Forever trainer, quest or talent
teaches them" [FDB], and neither Blizzard nor any guide mentions them [BLZ]. The pack must not register them. This
removes Shadow's AoE and its mana battery, and leaves **Shadow Word: Pain, Devouring Plague, Mind Blast, Mind Flay,
Shadow Word: Death** as the whole damage kit. **High.**

**New or reworked, all [BLZ]+[FDB]+[DB2]:**
- **Devouring Plague is baseline at 20 for every race** (was Undead racial), **1 min cooldown** (Classic 3 min), 24 s,
  8 ticks every 3 s, heals the caster, **can crit** (fixed 2026-10-01). Costs 215 mana at rank 1 up to 985 at rank 6.
- **Shadow Word: Death is a baseline ranked spell from 32** (ranks at 32, 40, 48, 56; DB2 1309595, 1309633, 1309635,
  1309636). Instant, 15 s cooldown, 1.5 s GCD, 175-340 mana, coefficient 0.429. If the target survives the caster takes
  **10% of maximum health**. It was an SoD rune; Forever re-made it. **High.**
- **Mind Flay is a one-point Shadow talent** (tier 3, spell level 20, 6 ranks at 20/28/36/44/52/60 from the trainer).
  3 s channel, 1 s ticks, 50% slow. **Improved Mind Flay** (new, 2 ranks): +20% damage, +10 yards, slow only 20%.
- **Shadowform is the tier-7 talent (level 40, 30 points above it)**: +10% Shadow damage, **-50% mana cost of Shadow
  spells**, **+100% crit-damage bonus** of Shadow spells, -15% physical damage taken; **only healing spells are blocked**
  (a healing cast drops Shadowform); Smite, Holy Fire, Mind Blast, Resurrection work in it. Classic: +15% damage, no mana cut.
- **Shadow Weaving is personal and has 3 ranks**: each Shadow damage spell has a 100% chance (at 3/3) to add **+2%**
  Shadow damage you deal for 15 s, up to 5 stacks (10%). Classic: +3% vulnerability for the whole raid, 5 ranks.
  "Can no longer fail to apply" (fixed 2026-10-01). DB2 15258 is a target debuff, "increased Shadow damage from the
  caster" (aura 270, 5 stacks, 15 s), so it lives on the enemy and resets on a target swap. **Medium** on the exact
  proc sources (see 7).
- **Vampiric Embrace is a tier-4 talent (16-point gold medal), 30 s duration (Classic 1 min), 1 min cooldown, 40
  mana, 20% of Shadow spell damage heals the party.** Improved Vampiric Embrace is removed. An enemy dying with your VE
  on it also triggers Spirit Tap.
- **Silence is a one-point tier-5 talent** (no Improved Psychic Scream gate): 5 s silence **plus a 3 s interrupt**
  (aura 1241057 "Interrupted"), 45 s cooldown, 225 mana, 20 yd. The only interrupt a priest has.
- **Devouring Contagion** (new, tier 5, 2 ranks; replaces Improved VE): -50% Devouring Plague mana at 2/2 (-25% at
  1/2), and a target that dies while it carries your plague **spreads it** to an enemy within 10 yd (5 yd at 1/2) for the
  remaining duration. **Early Demise** (new, tier 6, 2 ranks, level 35): +30% Shadow Word: Death crit chance on targets
  at or below 20% health (a bug that applied it at any health was fixed 2026-10-01).
- **Improved Shadow Word: Pain**: +6 s over 2 ranks (18 s to 24 s, 8 ticks). **Improved Mind Blast**: -2.5 s over 5
  ranks (8 s to 5.5 s). **Spirit Tap** (5 ranks): 100% chance, +100% Spirit for 15 s after killing a non-trivial target
  **or when an enemy afflicted by your VE dies**, and 50% of mana regen continues while casting. **Shadow Focus** is now
  +5% hit (was -resist), **Darkness** +10% Shadow damage, **Shadow Affinity** -30% Shadow threat.
- **Inner Focus** (Discipline tier 3, 3 min, off the GCD): next spell free and +25% crit **if non-periodic** (periodic
  exclusion added 2026-10-01). **Meditation** (Disc tier 3): 17/33/50% of regen continues while casting.
- Numbers: Mind Blast, Smite, Holy Fire, Shadow Word: Pain, Mind Flay and Devouring Plague deal **less base damage** but
  have **higher spell-power coefficients** (Mind Blast 0.429 on every rank, Shadow Word: Pain 0.2 per tick (Classic
  0.167), Mind Flay 0.167 per tick, Devouring Plague 0.1 per tick) [FDB][DB2]. **No snapshotting**: DoTs follow your
  current stats [GUIDE: Icy Veins]. Wands no longer scale with spell damage [GUIDE: wowforeverguides, citing Blizzard].
- **Five-second rule exists**: finishing a cast pauses mana regeneration for 5 s; cancelled and interrupted casts do not
  restart it; wanding does not [GUIDE: Icy Veins]. **Medium** (guide, not tested).
- Talents: one point per level from 10 to 60 (51 points; 21 at the beta cap; 31 at 40), a tier needs 5 points in the
  tiers above [FDB]. **Forever talents are single, rank-scaled spells**: the DB2 values are the full-rank values
  (Improved Mind Blast 15273 = -2500 ms, Improved SW:P 15275 = +6000 ms, Spirit Tap, Shadow Weaving 15257), so a spell ID
  does not tell the rank (section 8, settings).
- **Tier 1 raid set (1.60.0, from the 2026-12-09 raids)**: Shadow 2P hit, 3P Shackle Undead, 4P spell power vs undead,
  **5P Devouring Plague cooldown -60 s** (no cooldown) [DB2 1300955, 1301045, 1301087, 1301706].
- Racials: Night Elf **Starshards** (L10, 30 s cooldown, 6 s DoT; ForeverDB's sim has it at 19% of level-30 Shadow
  damage), Undead **Dark Sacrifice** (10 min, trades 400 health for mana over 15 s, scales with Spirit), Dwarf Chastise,
  Human Divine Grace, Gnome Confounding Flash and Contingency Plan, Troll Hex of Weakness and Shadowguard [BLZ][FDB].
- Smaller: Power Word: Fortitude 1 hour, stronger Fade (threat -4100 at rank 6), Prayer of Healing heals the target's
  whole party, Divine Spirit is a trainer spell at 30, Power Word: Shield can always overwrite on a target without
  Weakened Soul, Renew can stack from several priests [BLZ].

## 2. Specs and the builds players run

Forever has no spec switch: three trees, 51 points at 60, dual specialization at 40 [BLZ]. Shadow is the leveling pick
at 1-30 (Venruki and Hydramist agree, Twitch 2026-10-05/07 [GUIDE: wowforeverguides]).

**2.1 Shadow tree (the real Forever tree, [FDB talents]; ranks, tier, level the tier opens)**

| Tier (level) | Talents (ranks) |
|---|---|
| 1 (10) | Shadow Focus 5, Blackout 5 (10% stun on a Shadow damage hit), **Spirit Tap 5** |
| 2 (15) | Shadow Affinity 3, **Improved Shadow Word: Pain 2**, Shadow Reach 2 |
| 3 (20) | **Improved Mind Blast 5**, Improved Psychic Scream 2, **Mind Flay 1**, **Improved Mind Flay 2** |
| 4 (25) | Improved Fade 2, **Vampiric Embrace 1**, **Shadow Weaving 3** |
| 5 (30) | **Silence 1**, **Devouring Contagion 2** |
| 6 (35) | **Early Demise 2**, **Darkness 5** |
| 7 (40) | **Shadowform 1** |

Spells with no talent: Shadow Word: Pain (4), Mind Blast (10), Devouring Plague (20), Shadow Word: Death (32), Smite (1).

**2.2 Builds**
- **Level 30, 21 points, deep Shadow** (every guide converges): Spirit Tap 5, Improved SW:P 2, Shadow Reach 2 (or Shadow
  Focus), Mind Flay 1, Improved Mind Flay 2, Improved Mind Blast 2-5, Vampiric Embrace 1, Shadow Weaving 3, then Silence
  or Devouring Contagion. Wand Specialization 2/2 (Discipline) first for leveling. ForeverDB's two builds:
  "Vampiric Embrace Leveling" (Imp MB 5/5, Weaving 3/3, Contagion 1/2) and "Shadow DPS with VE" (Shadow Focus 5,
  Shadow Affinity 3, Imp MB 3/5, Silence). [FDB builds, GUIDE Icy Veins, Leprestore, ExpCarry, wowforeverguides]
- **Level 60 (theory, untested)**: about 17 Discipline / 34 Shadow: Shadowform, Weaving 3/3, Devouring Contagion 2/2,
  Early Demise, Darkness 5/5, Imp MB 5/5, Shadow Focus 5/5, VE, Mind Flay; Discipline: Inner Focus, Meditation 3/3, Twin
  Disciplines [GUIDE: Leprestore, 2026-10-05]. PvP skips Improved Mind Flay to keep the 50% slow.
- Talents that change the rotation: Improved SW:P (duration 18/21/24 s), Improved Mind Blast (cooldown 8 to 5.5 s),
  Mind Flay / Improved Mind Flay (slow only), Devouring Contagion (cost, spread), Early Demise (execute value),
  Shadowform (mana), Silence (interrupt), Spirit Tap and Meditation (mana), Inner Focus (cooldown).

**2.3 Discipline and Holy damage: is it worth a pack? Yes, as a small second profile, later.**
- Real damage kits exist: Smite (L1, 8 ranks, 2.5 s cast, coefficient 0.714), **Holy Fire** (L20, 3.5 s cast, 10 s DoT,
  coefficient 0.75), **Penance** (Discipline tier 5, level 30, 2 s channel, 12 s cooldown, offensive ticks of Holy
  damage at 0, 1 and 2 s; ranks 30/40/50/60: 402174, 1240720, 1240721, 1316995), **Power in Light** (Disc tier 1, 5
  ranks: Smite and Penance deal +10% to targets with your Holy Fire), Divine Fury (-0.5 s Smite/Holy Fire casts, Holy
  tier 2), Searing Light, Mental Agility (-10% Smite/Holy Fire/instant mana) [FDB talents].
- Damage per cast is **lower than Classic** (Smite rank 8: 160-180 vs 371-415; Holy Fire rank 8: 184-232 + 75 vs
  355-449 + 145), coefficients higher. ForeverDB publishes two Disc damage leveling builds ("Holy Fire and Penance",
  "Wand and Shield") and a Holy "Smite Leveling" build; Mmonster's trainer gives rotations: level 20 **Holy Fire,
  Shadow Word: Pain, Mind Blast on cooldown, Smite filler, wand**; level 60 **Penance on cooldown, Holy Fire when its burn
  has expired, Mind Blast on cooldown, Shadow Word: Pain, Smite filler** [GUIDE: Mmonster, 2026-10].
- Shadow Word: Pain, Mind Blast and Devouring Plague are baseline, so a Discipline/Holy priest already shares half the
  Shadow list. A "holy damage" profile is the same ability table plus Holy Fire, Penance and a different priority
  (draft APL in 8.3). Priority below Shadow; healers get no pack (no DPS role).

## 3. Single-target priority (Shadow)

Each rule: condition, then why. Level gates are automatic (an unknown spell is never recommended), so one list covers
levels 1-60. "Hidden" means the engine cannot read it in combat (section 7).

0. **Precombat/maintenance (any time, cheap lines at the top)**: Shadowform if missing (L40+); Power Word: Fortitude
   (1 h), Divine Spirit (L30+, 1 h), Inner Fire (10 min, 20 charges) if missing; Power Word: Shield before a hard pull
   if no Weakened Soul. *Why:* long buffs, stateless guards on readable player auras. Shield also stops damage
   pushback on your casts while it holds [DB2 PW:S text]. **High.**
1. **Vampiric Embrace** on the primary target when `group` (or a long solo target) and it is not on the target; behind
   the cooldowns toggle. *Why:* 40 mana and one GCD for 30 s of party healing (20% of Shadow damage) and a Spirit Tap
   trigger; costs about 2.5% of GCDs (1.5 s per 60 s). wowtbc.gg: "during party-wide damage". **Medium** (value is
   healing, not damage; display it, do not force it).
2. **Shadow Word: Pain**: cast when the DoT is **not up on the current target**; never before it expires. *Why:* the
   first priority of every guide (ForeverDB sim: up 79% of a 60 s fight, worth 10-12% of damage at 20-30). Ticks every
   3 s and **a recast replaces the DoT and drops the unticked remainder** [VAN], so recasting with time left forfeits
   the last tick (127 damage at rank 8) while a late recast loses only 1/3 tick per second of gap; so recast on expiry.
   Instant, 1.5 s GCD, 6/7/8 ticks (18/21/24 s with Improved SW:P). Skip on targets about to die (`settings.boss` or
   `group`; time-to-die is not available on Forever).
3. **Devouring Plague** when off cooldown and the DoT is down, on targets that will live ~24 s (`group` or
   `settings.boss`), if mana allows. *Why:* highest damage per GCD in the kit (rank 6: 848 per cast) and it heals you,
   but the worst per mana (0.86 damage per mana at 985 mana), so it is skipped on trash/solo mobs; Devouring Contagion
   halves the cost. ForeverDB's sim casts it on the pull. With the T1 5-piece (no cooldown) it becomes "whenever down".
4. **Starshards** (Night Elf) on cooldown (30 s): instant 6 s DoT, 19% of level-30 Shadow damage in ForeverDB's sim
   (default race: Night Elf, so the share is race-dependent). Arcane, so Shadow Weaving, Darkness and
   Shadowform do not buff it. Skipped automatically for other races.
5. **Shadow Word: Death**, only when the **target is at or below 20% health** (Early Demise window). *Why:* instant,
   coefficient 0.429 (448 base at rank 4) ~ a Mind Blast per GCD, +30% crit chance and +100% crit-damage bonus in
   Shadowform; outside the window the 10%-max-health backlash if it does not kill makes it a bad button. wowtbc.gg,
   Mmonster and Leprestore agree; wowtbc.gg also uses it "while moving" (no `moving` in our dialect). Target health is
   a hidden input (section 7). **Medium.**
6. **Inner Focus**, cooldowns toggle, when Mind Blast is ready and Inner Focus is down; Mind Blast follows at once.
   *Why:* wowtbc.gg ("with Mind Blast"): Mind Blast is non-periodic, so it gets +25% crit as well as the free cast.
   Alternative for mana: pair it with Devouring Plague (985 mana at 60; no crit bonus on a periodic). **Low-Medium.**
7. **Mind Blast** on cooldown (8 s, 5.5 s with 5 ranks): 1.5 s cast, high threat. *Why:* best damage
   per cast-second; spend it before the filler. In groups the first Mind Blast waits a few seconds for tank threat
   (ForeverDB); not expressible, left to the player. Shadow Affinity (30% less Shadow threat) shortens that wait.
8. **Mind Flay** as the filler, chained back to back (no gap between channels). Details below.
9. **Smite** as the filler **only while Mind Flay is not learned** (levels 1-19, or a build without the talent): same
   list, the entry is skipped when Mind Flay is known because Mind Flay is always ahead of it. Smite is usable in
   Shadowform. **High.**
10. **Wand (Shoot)** as the mana filler (opt-in custom toggle): "cast each spell once, then wand" is the leveling rule
    before Shadowform [GUIDE: Icy Veins]; wanding does not restart the 5-second rule; wand is ~6% of level-30 damage
    in ForeverDB's sim and 40-50% of leveling damage [Icy Veins]. See section 6.
11. **Silence**: not in the APL (cannot be timed: no read of the target's cast, PR8). Registered for tracking, behind
    `custom1`. When PR8 passes, line: `silence,if=target.casting&target.interruptible`.

**Mind Flay channel rules [INF + VAN; Hekili's Wrath list uses `ticks>=2` for the same reason].**
- 3 s channel, ticks at +1, +2 and +3 s, GCD 1.5 s, mana paid at channel start (not refunded on a cancel), no haste on
  Forever gear (Classic-era stats; probe PR4 to be sure), 50% slow (20% with Improved Mind Flay).
- *Chaining:* start the next Mind Flay the instant the previous ends (the GCD ended at 1.5 s). There is no early-chain.
- *Clipping:* cancel **only just after a tick**, never mid-tick. The earliest legal clip is at +1.5 s (GCD), but tick 2
  lands at +2.0 s, so clipping at 1.5 wastes half a tick for nothing. So the clip point is **tick 2 (at 2.0 s)**.
  Arithmetic (rank 6 MF 130 per tick, Mind Blast 485): clipping at a tick boundary for a ready Mind Blast is
  time-neutral for damage and shifts the 8 s cooldown cycle 1 s earlier (dps 166 vs 162), so **clip after tick 2 when
  Mind Blast is ready, or Shadow Word: Pain has expired, or Devouring Plague/Starshards just came off cooldown**;
  otherwise let tick 3 land. If the cast becomes ready between tick 2 and 3, wait for tick 3 (a mid-tick clip loses more
  than the delay costs).
- Shadow Word: Pain expiring mid-channel is handled by the same rule (clip at the next tick after expiry); never recast
  early to avoid a gap (a gap costs at most 1/3 tick per second; an early recast costs a whole tick).
- **The engine cannot express any of this yet** (channels are not built; no `interrupt_if`, `ticks`, `moving`). Interim:
  model Mind Flay as a 3 s hard cast with the 1.5 s GCD, which predicts the next action after the full channel.

## 4. AoE priority

**Shadow has no AoE spell on Forever** [BLZ][GUIDE: Icy Veins "no strong AoE spells"]. Holy Nova (Holy tier 3) is the
only AoE and is a healing spell, so it needs Shadowform off and a Holy talent. Options that exist:
- **Multi-dot by tabbing**: the single-target list already works per target (the belief files DoTs per target slot, so
  Shadow Word: Pain and Devouring Plague show as missing on a new target). Icy Veins suggests it for groups at a large
  mana cost, noting Spirit Tap misses last hits.
- **Devouring Contagion** gives limited cleave: the plague jumps on death (10 yd).
- So the pack ships **one list and no switch count**; the draft `aoe` list is empty of new spells (8.2) and display
  mode `single` is the default. The engine's enemy count is fixed at 1 (parity B17), `cycle_targets` is disabled in v1.

## 5. Cooldowns, defensives, interrupts

| Ability | Role | Toggle | Notes |
|---|---|---|---|
| Inner Focus (14751) | next spell free +25% crit (non-periodic) | cooldowns | 3 min, off the GCD, Discipline talent |
| Vampiric Embrace (15286) | party healing, Spirit Tap hook | cooldowns | 60 s cooldown, 30 s duration, group or long target |
| Devouring Plague (19280 top) | core DoT on long targets | none (rotation) | 60 s cooldown; T1 5P removes it |
| Starshards | core DoT (Night Elf) | none | 30 s |
| Silence (15487) | interrupt | custom1 (not in APL) | 45 s, 5 s silence + 3 s interrupt |
| Power Word: Shield (10901 top) | defensive, pushback guard | `settings.shield` | 4 s cooldown, **Weakened Soul 15 s** on the target |
| Fade (10942 top) | threat dump | none | 30 s, 10 s; use when Mind Blast pulls aggro |
| Psychic Scream (10890 top) | 8 yd fear | none | 30 s (26 s with Improved Psychic Scream 2/2) |
| Dark Sacrifice (Undead), Desperate Prayer (Dwarf), Elune's Grace, Divine Grace, Contingency Plan | racial safety nets | none | 10 min each (Elune's Grace 5 min, 15 s) |

- No Dispersion, no Shadowfiend, no Pain Suppression on Forever (SoD leftovers).
- Power Infusion is a Discipline tier-7 talent (level 40, 3 min, +20% spell damage and healing for 15 s on a target; not in
  the Shadow builds). Candidate for the cooldowns toggle if detected.
- Mind Control (L30, 3 s cast) is crowd control, never a damage line.

## 6. Resources and timing

- **Mana is the limiter until Shadowform (L40).** "Without easy access to any of the new mana tools, Shadow is very
  mana-hungry" [GUIDE: Icy Veins]; the rule is to cast each spell once then wand. Level 60 Shadowform halves every
  Shadow-school cost: Mind Blast 350 to 175, SW:P 470 to 235, Mind Flay 205 to 103, Devouring Plague 985 to 493 (246
  with Contagion 2/2); Smite, Holy Fire, Starshards (Arcane) and Power Word: Shield are not discounted.
- **Regeneration (vanilla-assumed with Forever additions):** Spirit-based regen only while out of the 5-second window
  (5 s after the last completed cast); `GetManaRegen()` returns `(base, casting)` (present on Forever, probe PR16).
  Casting regen comes from Spirit Tap (50% for 15 s), Meditation (17/33/50%) and mp5 gear. In practice, a casting
  Shadow priest regenerates only the "casting" part, so the belief should seed `regen` from `castingManaRegen` out of
  combat and read `baseManaRegen` for rest. Out of combat is a fast refill (drink).
- **Spirit Tap**: needs XP-yielding ("non-trivial") kills, so group play is "inconsistent" and VE on the target is the
  workaround [GUIDE: Icy Veins]. It is a player aura (15271) [DB2], so it is readable if player auras are (section 7).
- **Starting mana**: out of combat max is readable (`UnitPowerMax`); current power is secret in combat (assumed, as for
  energy and rage); `IsSpellUsable` gives affordability, and each spell's cost bounds the belief (the cost ladder).
- **GCD** 1.5 s for every spell (no haste modelled; probe PR4); Hard casts (Mind Blast 1.5 s, Smite 1.5-2.5 s, Holy Fire 3.5 s)
  start the GCD with the cast (Mind Blast's 1.5 s cast equals the GCD, so no extra delay); Inner Focus and Shoot are
  off the GCD. Mind Flay: 3 s channel. Cooldown starts at cast finish for hard casts.
- **Wand**: `Shoot` (5019) costs nothing, is an auto-repeat (`C_Spell.IsAutoRepeatSpell`, present), does not restart the
  5-second rule; Wand Specialization (Disc tier 1, 2 ranks) +25%.
- **Dark Sacrifice** (Undead, 10 min): converts health to mana over 15 s, 80 health per 3 s at rank 1 (400 total) up to
  320 per 3 s at rank 5 (1600), and the mana gained scales with Spirit [DB2 1277324-1277328][BLZ]; recommend only with
  `settings.dark_sacrifice` and no enemy attacking (not observable; a toggle).
- **No pets, no totems, no shards.** The one "summon" is gone (Shadowfiend).

## 7. Auras, procs and trackers the pack must model

"Readable" is Forever's rule from the spikes: player auras by spell ID are readable in combat; target auras, power,
cooldown times and target health are secret in combat. Target DoT up/down comes from the target-frame aura container
presence; durations from our own cast events (gate-spike memory).

| Aura | ID | Unit | Duration | Readable in combat? | Inference when not |
|---|---|---|---|---|---|
| Shadowform | 15473 (self form) | player | until cancelled | yes (player aura) | none needed; also removed by a healing cast |
| Inner Fire | 588, 7128, 602, 1006, 10951, 10952 | player | 600 s, 20 charges | yes | charges not needed |
| Power Word: Fortitude | 1243, 1244, 1245, 2791, 10937, 10938 | player | 3600 s | yes | family `stamina` with Prayer of Fortitude |
| Divine Spirit | 14752, 14818, 14819, 27841 | player | 3600 s | yes | |
| Spirit Tap | 15271 (talent 15270) | player | 15 s | yes | regen fraction known; also starts on a VE'd death |
| Inner Focus | 14751 (aura = spell) | player | until the next spell | yes | consumed by the next cast |
| Weakened Soul | 6788 | player (also on allies) | 15 s | yes on self | for Power Word: Shield gating |
| Shadow Word: Pain | 589, 594, 970, 992, 2767, 10892-10894 | target | 18/21/24 s, tick 3 s | up/down gated; remains secret | cast + duration (Improved SW:P setting), `pandemic = 0` |
| Devouring Plague | 2944, 19276-19280 | target | 24 s, tick 3 s | up/down gated | cast + 24 s; spread on death can move it (unseen) |
| Vampiric Embrace | 15286 | target | 30 s | up/down gated | cast + 30 s |
| Starshards | 10797, 19296, 19299, 19302-19305 | target | 6 s, tick 1 s | | cast + 6 s |
| Holy Fire (DoT) | 14914, 15262-15267, 15261 | target | 10 s, tick 2 s | | cast + 10 s |
| Shadow Weaving | 15258 (talent 15257) | target (from caster) | 15 s, 5 stacks | no (stacks secret) | count our Shadow damage casts; **not needed by the APL** |
| Silence (the target's) / Interrupted | 15487 / 1241057 | target | 5 s / 3 s | no | none |

- **Shadow Weaving** only changes damage, not decisions: the list keeps it at 5 stacks by never idling. Model it only if
  a display wants it. Proc sources are unconfirmed: Mind Blast (direct) certainly; Mind Flay (guides: "keeps it
  stacked"); Shadow Word: Pain ticks unknown (DB2 proc mask 0x10000 = direct negative magic damage). **Medium-low.**
- **Mind Flay channel**: own channel events (`UNIT_SPELLCAST_CHANNEL_*`) and `UnitChannelInfo('player')` exist on
  Forever; core's Sources do not subscribe yet (parity A25/A26). Without them the 3 s length comes from data.
- **Talent ranks are not readable** (the Classic `Talent` table in DB2 is stale; Forever talents are single spells).
  Use pack settings: `imp_swp` (0-2), `imp_mb` (0-5), `contagion` (0-2), `silence_known` is the spell itself. PR5
  tries `C_SpecializationInfo.GetTalentInfo` and `IsSpellKnown` on rank ladders; a third route is parsing
  `C_Spell.GetSpellDescription(15273)` ("by X sec", scaled to the learned rank) [INF].
- **Target health** (SW:D execute, `target.health.pct`) is hidden; `UnitHealthPercent(unit, usePredicted, curve)`
  exists with a curve, so a step curve can gate the display exactly as `UnitPowerPercent` does for power [INF; probe].
- **Cooldowns** (Mind Blast, Devouring Plague, SW:D, VE): secret in combat; tracked from our own casts and the known
  base times (Mind Blast uses the `imp_mb` setting).
- **Spec**: no readable talent tree; detect Shadow by any known Shadow-signature spell (Mind Flay 15407, VE 15286, Spirit
  Tap 15270, Shadow Weaving 15257, Silence 15487, Shadowform 15473) and default to Shadow for an unspecced priest.

## 8. Draft APLs (our dialect)

Spec keys: `shadow` (default) and `holy_damage` (Disc/Holy leveling). Names are DB2 snake_case; target auras are `dot.`
or `debuff.`. Lines are stateless guards. `mana.pct` is **not** in the registry (only `mana`, `mana.deficit`,
`mana.max`, `mana.regen`, `time_to_<n>`), so mana floors use `mana>=mana.max*N`; `time_to_die` is replaced by
`settings.boss`; `moving`, `interrupt_if` and `ticks` do not exist yet.

### 8.1 Shadow, default list

```
# Shadow Priest on WoW Forever. One list for levels 1-60: spells the player doesn't know are skipped by the engine.
actions=call_action_list,name=maint
actions+=/vampiric_embrace,if=(group|settings.boss)&!dot.vampiric_embrace.up&toggle.cooldowns   # 60 s, party heal + Spirit Tap hook
actions+=/shadow_word_pain,if=!dot.shadow_word_pain.up                                          # recast on expiry only: no carry-over
actions+=/devouring_plague,if=(group|settings.boss)&!dot.devouring_plague.up&mana>=mana.max*settings.dp_mana   # 24 s DoT, worst per mana
actions+=/starshards,if=!dot.starshards.up                                                      # Night Elf, 30 s
actions+=/shadow_word_death,if=target.health.pct<=20                                            # Early Demise window; backlash otherwise
actions+=/inner_focus,if=toggle.cooldowns&!buff.inner_focus.up&cooldown.mind_blast.ready        # free, +25% crit on the Mind Blast that follows
actions+=/mind_blast                                                                            # on cooldown (8 s, 5.5 s at 5/5)
actions+=/mind_flay,if=buff.shadowform.up|mana>=mana.max*settings.flay_mana                     # filler; below the floor, wand instead
actions+=/smite,if=mana>=mana.max*settings.flay_mana                                            # only reached while Mind Flay is unknown
actions+=/shoot,if=toggle.custom2                                                               # wand when out of mana (opt-in)
# silence is tracked but not recommended: the target's cast is unreadable (PR8); then: silence,if=target.casting
```

```
actions.maint=shadowform,if=!buff.shadowform.up                                  # L40 talent
actions.maint+=/power_word_fortitude,if=!buff.power_word_fortitude.up            # 1 h
actions.maint+=/divine_spirit,if=!buff.divine_spirit.up                          # L30 trainer, 1 h
actions.maint+=/inner_fire,if=!buff.inner_fire.up                                # 10 min, 20 charges
actions.maint+=/power_word_shield,if=settings.shield&!debuff.weakened_soul.up    # opt-in pre-pull shield (also stops pushback)
```

Settings: `shield` (bool, default false), `boss` (bool; stands in for time-to-die), `dp_mana` (0-1, default 0.35), `flay_mana` (0-1, default 0.15 pre-
Shadowform), `imp_swp` (0-2), `imp_mb` (0-5), `contagion` (0-2), `dark_sacrifice` (bool).

### 8.2 Shadow, aoe list (display mode `aoe`)

```
actions.aoe=call_action_list,name=maint
actions.aoe+=/shadow_word_pain,if=!dot.shadow_word_pain.up        # tab to the next target: the DoT is per target slot
actions.aoe+=/devouring_plague,if=!dot.devouring_plague.up&settings.boss
actions.aoe+=/starshards,if=!dot.starshards.up
actions.aoe+=/mind_blast
actions.aoe+=/mind_flay,if=buff.shadowform.up|mana>=mana.max*settings.flay_mana
```
No target counts: Forever offers no AoE spell, and the enemy count is fixed at 1 until the nameplate probe (PR6).

### 8.3 Holy damage (Disc/Holy leveling), default list

```
actions=call_action_list,name=maint                                  # same maint list (Shadowform is skipped when unknown)
actions+=/holy_fire,if=!dot.holy_fire.up                             # opener; unlocks Power in Light (+Smite/Penance damage)
actions+=/shadow_word_pain,if=!dot.shadow_word_pain.up
actions+=/penance,if=toggle.cooldowns                                # L30 Disc talent, 2 s channel, 12 s
actions+=/mind_blast
actions+=/smite
actions+=/shoot,if=toggle.custom2
```
Mmonster's level-60 order puts Penance first and Holy Fire "once its burn has expired" (10 s DoT); the list above does
both through `!dot.holy_fire.up`. Needs Holy Fire's 3.5 s cast and Penance's channel (engine channels).

### 8.4 Pack notes
- Gcd kinds: every spell `Gcd.Spell` (1.5 s); `inner_focus`, `shoot` `Gcd.Off`. `mind_blast` `cast = 1.5`; `smite` 2.5 s
  (2.0 with Divine Fury 5/5); `holy_fire` 3.5; `mind_flay` `cast = 3` as the channel stand-in.
- `shadow_word_pain`, `devouring_plague`, `vampiric_embrace`: `H.applyDebuff` with `pandemic = 0` (no carry-over).
- Costs: pack literals per rank from the DB2 (section 9). A `spend` function that reads `buff.shadowform` (x0.5, Shadow
  school only), `buff.inner_focus` (x0) and `settings.contagion` (Devouring Plague x(1 - 0.25/rank)); `reads` those
  auras so the APL rechecks on a change.
- `shadow_word_death` needs the Forever ranks as `copy`: the shared data has only the SoD rune (see 10, data bugs).

## 9. Spell and aura table

IDs from DB2 1.60.1.70338 (R = rank; the data addon's `ids` order). Cost is mana unless noted. "Data addon" notes mismatches.

| Spell | IDs (rank order) | Level | Cost (low-high) | GCD | Cast | Duration | Cooldown |
|---|---|---|---|---|---|---|---|
| Shadow Word: Pain | 589, 594, 970, 992, 2767, 10892, 10893, 10894 | 4,10,18,26,34,42,50,58 | 25-470 | 1.5 | 0 | 18 (+6 talent), tick 3 | 0 |
| Mind Blast | 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 | 10,16,22,28,34,40,46,52,58 | 50-350 | 1.5 | 1.5 | - | 8 (-2.5 talent) |
| Mind Flay (talent) | 15407, 17311, 17312, 17313, 17314, 18807 | 20,28,36,44,52,60 | 45-205 | 1.5 | channel 3, tick 1 | 3 | 0 |
| Devouring Plague | 2944, 19276, 19277, 19278, 19279, 19280 | 20,28,36,44,52,60 | 215-985 | 1.5 | 0 | 24, tick 3 | 60 |
| Shadow Word: Death | **1309595, 1309633, 1309635, 1309636** (Forever); data addon has 401955 (SoD rune: 12% mana, 12 s) | 32,40,48,56 | 175-340 | 1.5 | 0 | - | 15 |
| Vampiric Embrace (talent) | 15286 | 30 | 40 | 1.5 | 0 | 30 | 60 |
| Silence (talent) | 15487 | - | 225 | 1.5 | 0 | 5 (+3 interrupt, aura 1241057) | 45 |
| Shadowform (talent) | 15473 | - | 40% base mana | 1.5 | 0 | until cancelled | 1.5 |
| Inner Focus (talent) | 14751 | - | 0 | off | 0 | until used | 180 |
| Starshards | 10797, 19296, 19299, 19302, 19303, 19304, 19305 | 10,18,26,34,42,50,58 | 50-350 | 1.5 | 0 | 6, tick 1 | 30 |
| Smite | 585, 591, 598, 984, 1004, 6060, 10933, 10934 | 1,6,14,22,30,38,46,54 | 20-280 | 1.5 | 1.5,2,2.5 (x5) | - | 0 |
| Holy Fire | 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 | 20,24,30,36,42,48,54,60 | 85-255 | 1.5 | 3.5 | 10, tick 2 | 0 |
| Penance (talent) | 402174, 1240720, 1240721, 1316995 | 30,40,50,60 | 150-385 | 1.5 | channel 2 | - | 12 |
| Power Word: Shield | 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 | 6,12,...,60 | 45-500 | 1.5 | 0 | 30 | 4 (Weakened Soul 6788, 15 s) |
| Power Word: Fortitude | 1243, 1244, 1245, 2791, 10937, 10938 | 1,12,24,36,48,60 | 60-1695 | 1.5 | 0 | 3600 | 0 |
| Divine Spirit | 14752, 14818, 14819, 27841 | 30,40,50,60 | 285-970 | 1.5 | 0 | 3600 | 0 |
| Inner Fire | 588, 7128, 602, 1006, 10951, 10952 | 12,20,30,40,50,60 | 30-315 | 1.5 | 0 | 600 | 0 |
| Fade | 586, 9578, 9579, 9592, 10941, 10942 | 8,20,30,40,50,60 | 40-275 | 1.5 | 0 | 10 | 30 |
| Psychic Scream | 8122, 8124, 10888, 10890 | 14,28,42,56 | 100-210 | 1.5 | 0 | 8 | 30 |
| Shoot (wand) | 5019 | - | 0 | off | auto-repeat | - | - |
| Dark Sacrifice (Undead) | 1277324-1277328 | 20-60 | 0 | 1.5 | 0 | 15 | 600 |

Auras and talent spells not in the data addon (add by literal or `tools/data/overrides.json`): Shadow Weaving debuff
15258, Spirit Tap buff 15271, Weakened Soul 6788, Improved Mind Flay 1225139, Devouring Contagion 1309950, Early Demise
1310076, Twin Disciplines 1225132, Power in Light 1309969, Holy Precision 1309957, Interrupted 1241057. The data addon
also carries the unused SoD rune spells (vampiric_touch, shadowfiend, mind_sear, mind_spike, void_plague, dispersion):
leave them out of the pack.

Efficiency at top ranks (no spell power; my arithmetic from FDB damage and DB2 costs; DoTs only if the target lives the
full duration), per GCD and per mana: Devouring Plague 848 (0.86/mana), Shadow Word: Pain 762 (1.62), Mind Blast 485
(1.39), Shadow Word: Death 448 base (1.32, plus backlash), Mind Flay 390 per 3 s = 195 per GCD (1.90), Smite 170 per
2.5 s (0.61). So every DoT and cooldown beats the filler per GCD, and Mind Flay is the most mana-efficient: matching
the guides' "cast each once, then Mind Flay".

## 10. Open questions, probes, data bugs and sources

**Data bugs (fix before the pack):**
1. `TacoDogForeverData.PRIEST.shadow_word_death` is the **SoD rune (401955)**, not Forever's ranked spell: the
   generator's selection drops the Forever rows because their SkillLineAbility has ClassMask 0 (`tools/gen_data.py`
   `select()` requires `class_mask != 0`). Forever ranks 1309595, 1309633, 1309635, 1309636 are lost, and so are Lightwell
   Renew 27873/27874 and Litany of Light 1317006. Check other classes for the same ClassMask-0 pattern.
2. The `Talent` table is the **Classic** tree: Forever's new talents (Improved Mind Flay, Devouring Contagion, Early Demise,
   Power in Light, Twin Disciplines, Holy Precision) and their 1-spell ranks are in `Spell` only, and `talent_info` still
   lists removed ones (Unbreakable Will, Force of Will, Improved VE). Forever's own tree comes from TraitNode tables
   (wago.tools returned 503 for TraitDefinition/TraitNodeEntry on 2026-10-12).
3. Triggered auras are skipped when a learned row of the same name exists (Shadow Weaving 15258, Spirit Tap 15271).

**Engine gaps the Priest pack needs (listed in the existing reconciliation as E34, A25/A26, B17):**
- **Channels** (Mind Flay, Penance): `channeled`, `tick`, `breakchannel`, `ticks` in the APL, channel events. Blocks
  clipping advice; a 3 s hard cast stands in.
- A `mana.pct` (or `mana.max*x`) form the planner can gate; an inverted aura gate for the five-second rule; `interrupts`
  toggle and a read of the target's cast (PR8); `moving`; `active_enemies` > 1.

**Open questions (probe in game; a level 30 priest is enough for the first six):**
1. Is **mana** secret in combat on Forever? (`UnitPower('player', 0)`, PR16). Is **target health** secret
   (`UnitHealthPercent` with a step curve gating SW:D)?
2. Player aura reads in combat for 15473, 15271, 588, 14751, 6788 (`C_UnitAuras.GetPlayerAuraBySpellID`).
3. Does recasting Shadow Word: Pain with time left **carry over** or replace? (only visible out of combat on a dummy).
4. Which casts add a **Shadow Weaving** stack (Mind Flay tick or channel start; DoT ticks)? Count with the target frame's
   debuff stack text, if shown.
5. `GetManaRegen()` base vs casting before/after a cast, with and without Spirit Tap, to seed the regen model; confirm the
   five-second rule on Forever.
6. Does **Mind Flay** keep its GCD overlap (can Mind Blast be pressed at 1.5 s and cancel the channel)? What does
   `UnitChannelInfo('player')` return in combat (PR9)?
7. Talent rank reads: `C_SpecializationInfo.GetTalentInfo` (PR5) for Improved Mind Blast (8 vs 5.5 s) and Improved SW:P;
   or `C_Spell.GetSpellDescription(15273)` parsed.
8. `IsSpellKnown` for the SoD leftovers (401977, 402668, 413259, 431655, 425294): confirm none are learnable.
9. Does SW:D have any usability gate on target health (`C_Spell.IsSpellUsable(1309595)` at 100% vs 15%)?
10. Is Shadowform `15473` the player aura, and is anything else (e.g. 16592, 22917) applied with it?
11. Inner Focus target: Mind Blast (crit) vs Devouring Plague (985 mana) at level 60 (sim question).
12. Vampiric Embrace: the talent opens at 25 but the spell record says level 30 (flagged by wowforeverguides and
    classicwowforever): does a 25-29 character hold the spell? Same check for Mind Flay (talent 20, spell level 20).
13. After launch (cap 60): re-sim priorities with Shadowform; Tier 1 5P changes Devouring Plague to "whenever down".

**Sources** (fetched 2026-10-12 unless noted; "-" means no date on the page):
- Blizzard, "World of Warcraft: Forever Class Deep Dives, Priest and Warrior" (published about 2026-09-30, via Carried.io/
  Wowhead): https://news.blizzard.com/en-us/article/24301514/world-of-warcraft-forever-class-deep-dives-priest-and-warrior ;
  https://www.carried.io/news/687-priest-and-warrior-class-deep-dives-in-world-of-warcraft-forever
- ForeverDB, Priest (build 1.60.1.70338, updated 2026-10-12, extracts the client): https://foreverdb.net/class/Priest ,
  /pve , /changes , /talents , /builds
- Icy Veins, Shadow Priest (published 2026-09-17, changelog to 2026-10-03; WebFetch 403, read via curl):
  https://www.icy-veins.com/wow-forever/shadow-priest-ranged-dps-pve-guide
- wowtbc.gg Shadow Priest (undated, (c) 2026): https://wowtbc.gg/warcraftforever/class-guides/shadow-priest/
- Leprestore Shadow Priest (2026-09-20, updated 2026-10-05): https://leprestore.com/guides/world-of-warcraft-forever/wow-forever-shadow-priest-guide-best-builds-race-professions/
- ExpCarry Priest (modified 2026-10-03): https://expcarry.com/wow-forever-priest-guide
- classicwowforever.com Shadow (updated 2026-10-04, build 1.60.1.70205): https://classicwowforever.com/class-guides/priest/shadow/
- wowforeverguides.com leveling (published 2026-09-28, updated 2026-10-08): https://wowforeverguides.com/leveling/priest
- Mmonster rotation trainer, priest (undated, 2026-10): https://mmonster.co/wow-forever/tools/rotation-trainer/priest
- LFCarry priest (updated 2026-10-11): https://lfcarry.com/guides/wow-forever-priest ; beta/launch: https://lfcarry.com/guides/wow-forever-beta ;
  roadmap https://www.icy-veins.com/wow-forever/roadmap
- MMO-Champion, Beta Development Notes, October 1: https://www.mmo-champion.com/content/14573-World-of-Warcraft-Forever-Beta-Development-Notes-October-1
- Mobalytics Shadow Priest (403, not read): https://mobalytics.gg/wow-forever/classes/shadow-priest-guide
- Hekili (behaviour only): `origin/wrath_release:Wrath/APLs/PriestShadow.simc` (`interrupt_if=ticks>=2`, DoT-before-nuke
  order; Wrath spells that Forever lacks), `origin/classic:Classic/Priest.lua` (Wrath-era ability table; no priest APL
  on the classic branch).
- Local: DB2 sqlite, `src/TacoDogForever_Data/Generated/Spells.lua` (PRIEST), engine docs
  `docs/class-packs/*`, `docs/research/2026-10-12-parity-*.md`, `docs/research/2026-10-13-port-probes-runbook.md`.
