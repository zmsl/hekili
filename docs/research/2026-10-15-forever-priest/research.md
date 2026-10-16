# Forever Priest class pack in the Hekili fork: research brief (2026-10-15)

Read-only research for a spec of `Forever/Classes/Priest.lua` beside the Warrior, Druid and (researched) Mage. Build: Forever DB2 1.60.1.70338 (`wowdb`), client 1.60.1.70374, beta cap 30, launch 2026-11-04. Hekili HEAD 799bd49e.
Tags: [DB2] = queried here (queries in section 10); [TDF] = Taco Dog Forever file; [H] = Hekili file; [MAGE] = `HK/docs/research/2026-10-15-forever-mage/research.md` section N (engine findings reused, not re-derived); [DRUID] = the Druid brief
`HK/docs/research/2026-10-15-forever-druid/research.md`; [P] = in-game probe recorded in a repo doc; [G] = guide or Blizzard post relayed by `docs/research/2026-10-15-forever-priest/tdf-priest-shadow-rotations.md` (not verified by us); [I] = my inference.
Paths: `HK` = `/home/zack/src/hekili`, `TDF` = `/home/zack/src/TacoDogForever`. Costs: mana points, or "% base" where `SpellPower.PowerCostPct` is set. Pack shape = `HK/src/Hekili/Forever/Classes/{Warrior,Druid}.lua`; priorities = `HK/tools/packs/{warrior,druid}.lua`.

## 0. Not found / cannot be settled from the repos (read this first)

- **The live Forever Priest talent tree is not in the DB2.** `wowdb talents PRIEST` returns the Era tree (Discipline 15, Holy 16, Shadow 16 = 47 nodes) and none of Forever's rebuilt nodes as nodes; their spells exist only as bare spell rows (Improved Mind Flay 1225139, Devouring
  Contagion 1309950, Early Demise 1310076, Twin Disciplines 1225132, Power in Light 1309969, Holy Precision 1309957) [DB2]. Their ranks, tiers and the removed nodes come from ForeverDB via [G]. **No Priest ForeverProbe export exists** (`~/src/ForeverProbe/results` has only the W and O runs). Q1 produces it.
- **Talent rank values are ambiguous.** Only rank 1 of a talent is in `spell_info` (ranks 2..5 absent except three: Improved Power Word: Fortitude 14767, Blackout 15323, Force of Will 18547). Several rank-1 rows read the **full-rank** value (Improved Mind Blast 15273 = -2500 ms, Improved SW:P 15275
  = +6000 ms, Meditation 14521 = 50, Darkness 15259 = 10, Mental Agility 14520 = -10, Divine Fury 18530 = -500) while others read the Era per-rank value (Holy Specialization 14889 = 1, Spiritual Healing 14898 = 2, Improved Renew 14908 = 5) [DB2 effects]. The Warrior's "rank 1 x rank" rule is therefore **wrong for
  the Shadow talents that matter**; Q8 reads the description at the learned rank.
- **Mana is secret even out of combat** [P, `TDF/docs/research/2026-10-13-research-findings-for-lanes.md:51`]; the Spirit regen formula, the five-second rule, `GetManaRegen` pair and Spirit are unprobed on a Priest (Q6). Nothing in the DB2 gives rates.
- **The Season of Discovery spells in the DB2 are leftovers, not Forever spells** [G, FDB: "no Forever trainer, quest or talent teaches them"]: Vampiric Touch 402668, Shadowfiend 401977, Mind Sear 413259, Mind Spike 431655, Dispersion 425294, Void Plague 425204, Eye of the Void 402789, Homunculi 402799, Pain Suppression 402004, Power Word: Barrier 425207, Circle of Healing 401946 (all
  `base_level` 0, one rank, percent costs) [DB2]. The pack ignores them (Mage and Druid precedent). Q9 confirms with `IsSpellKnown`. **The shared data in TDF, and `Forever/Shared`, must not leak them**: the SWD rune 401955 is NOT the Forever spell (section 3).
- **Priority numbers are judgment**: Shadow guides are level-30 beta; levels 40-60 (Shadowform, Shadow Word: Death) are untested [G].

## 1. Scope

**Specs.** Shadow (default), Smite/Holy ("holy_damage") and Discipline-damage ("disc_damage"), as three priorities on one pseudo-spec behind `UnitClassBase("player") ~= "PRIEST"` (the Warrior's 1491 and the Druid's 1499 are taken; the Priest's id is chosen in the spec), selection by `/hekili priority <name>` (no `RegisterPackSelector`)
[MAGE 1]. Forever has no spec switch (three trees, 51 points at 60, dual spec at 40) [G]. No healer pack. **In Hekili today:** `origin/classic:Classic/Priest.lua` (1858 lines, WotLK-shaped: keys, ids and Mind Flay/Shadowform shape reusable, talent keys not) and `Wrath/APLs/PriestShadow.simc` on `origin/wrath_release`; nothing on `forever` [H].
**Like the Mage, a caster**: cast bars, pushback and a continuous mana regen are shared engine findings [MAGE 2.2, 6, 10]. **Unlike the Mage**, the Priest adds a channel that must be broken on a tick (Mind Flay, Penance), a stance-like aura (Shadowform) and DoTs that decide the rotation.

## 2. Mana and the Priest-specific regen pieces

### 2.1 Pool and costs
- `spec:RegisterResource( Enum.PowerType.Mana )` as in Druid.lua:220. Max/base unknown (Q6). Gnome Expansive Mind **20591 (+5% maximum resources)** already lists Priest [H `Forever/Races/Gnome.lua`]; nothing for the pack to add.
- **Percent costs** [DB2 `cost_pct`]: Shadowform **40**, Power Infusion **20**, Resurrection 75, Dispel Magic 18, Cure/Abolish Disease 15, Elune's Grace 3. Every damage spell below is a flat point cost. A `spend` below 1 is a fraction of maximum mana in both layers [MAGE 2.1], so Shadowform is `spend = 0.4` and Power Infusion `spend = 0.2`; both overstate by max/base mana (gear Intellect). Q6 records both.
- **Shadowform: -50% mana cost of all Shadow-school spells** (effect 3: aura 72, base -50, misc 32 = the Shadow school) [DB2 effects 15473]. Scope = every Shadow-school spell with a cost, so it is a school cost mod, not a class-mask one: `RegisterCostMod{ aura = "shadowform", pct = -0.5, spells = { Shadow-school rank-1 IDs } }` with no `charges`, `copy` lists resolving the ranks
  [MAGE 2.4 pattern; `Engine/Races.lua:76`, `inScope`]. Not discounted: Smite, Holy Fire, Penance, Starshards (Arcane, mask 64), Power Word: Shield, Inner Fire.
- **Inner Focus 14751**: cost -100% (effect 0: aura 108 misc 14 base -100, masks cover almost every Priest spell: heals, DP, Fade, Inner Fire, Holy Fire, Mind Blast...), **+25% crit on the next non-periodic spell** (effect 1: aura 107 misc 7), `ProcCharges 1`, duration until used, 180 s cooldown, **GCD 0** [DB2 effects, SpellAuraOptions]. The Clearcasting pattern fits exactly:
  `RegisterCostMod{ aura = "inner_focus", pct = -1, charges = 1 }` with no `spells` (= every resource-paid ability) [MAGE 2.4; DRUID Clearcasting]. Aura id = the spell id (14751).
- **Power Infusion 10060** is *not* a haste/cost aura on Forever: two effects only, **+20% healing done (aura 136, misc 126) and +20% damage done, all schools (aura 79, misc 126)**, 15 s, friendly target, 20% base mana, 180 s cooldown, **GCD 0**, Discipline tier 7 (needs Mental Strength 4) [DB2 effects 10060, `talents PRIEST` row 322]. No spell-haste, no cost reduction, no
  shared resource effect: nothing for the cost-mod list. The aura is already registered in `Forever/Shared/Auras.lua` (`power_infusion`, id 10060, 15 s, `shared = "player"`, `dot = "buff"`, for another Priest's cast on you); the Priest file registers the **ability only** (section 4).
- **Eureka! (Gnome)**: 1259823, scope list of 16 rank-1 IDs already in `Gnome.lua` `EUREKA_SPELLS.PRIEST` (set 6: Binding Heal, Flash Heal, Greater Heal, Heal, Holy Fire, Holy Nova, Lesser Heal, Mana Burn, Mind Blast, Mind Flay, Penance, Prayer of Healing, both SWDs, Smite, Starshards). It reaches the cost mods through the `copy` rank lists, so **the Priest file's abilities must carry
  every rank in `copy`, and register the Forever SWD (1309595) and Penance (402174) as the in-scope IDs** (the list holds the rune SWD 401955 and 1309595 both).

### 2.2 Regen: the engine facts apply unchanged
Everything in [MAGE 2.2] holds: `GetManaRegen` is answered with one believed rate (`VS.Regen` ignores `casting`), the 2x calibration guard rejects big jumps, `mana.time_to_x` is unreliable, APL lines use `mana.pct`/`mana.deficit`. What is specific to the Priest:
- **Spirit Tap 15270** (Shadow tier 1, 5 ranks): on killing a non-trivial target **or when an enemy afflicted by your Vampiric Embrace dies**, triggers **15271** for 15 s: aura 137 base 100 misc 4 (**+100% Spirit**) and **aura 134 base 50: 50% of mana regen continues while casting** [DB2 effects 15270, 15271, description]. A player aura, a proc on a kill: the pack cannot see the kill, so it is **readable only if the
  player aura is** (Q5), else not modelled (`shortcut:`). Effect on the sim: with the aura, `casting` regen is 50% not 0 (needs the second rate, [MAGE 10] core work).
- **Meditation 14521** (Discipline tier 3, 3 ranks): aura 134 base 50 (rank 1 row; the text is 17/33/50 [G]): a **passive** share of regen while casting, i.e. a constant level for the believed rate, set from the talent rank (settings `meditation`, 0-3, until Q1/Q8 give the rank).
- **Five-second rule exists on Forever**; finishing a cast pauses regen 5 s, cancelled casts do not, wanding does not [G]. In practice a casting Shadow Priest regenerates only the "casting" part [G]: seed from `castingManaRegen` if plain (Q6).
- **Shadowform halves Shadow costs**, so level 40+ Shadow is mana-neutral where levels 1-39 are "cast each spell once, then wand" [G]. This is the single biggest swing in the mana model and must be believed correctly (section 6).
- **No Shadowfiend, no Dispersion** (leftovers). **Dark Sacrifice (Undead, 1277324..28)**: 15 s, 600 s cooldown, GCD 1.5; aura 226 (periodic dummy, health lost) 80/136/196/258/320 per 3 s and aura 24 (periodic energize mana) the same base + Spirit coefficient 1 [DB2 effects]; a channel-like 15 s mana source: register behind `toggle = "cooldowns"`, off the default lists, and model the mana as a `resource` entry like Bloodrage's pattern once Q7 shows the yield. **Mana potions/gems:** no Forever potion is registered in `Shared/Consumables.lua` ("No Forever potion, flask or food is registered"); the Healthstone pattern is [MAGE 2.3].
- **Wand**: `Shoot` 5019 (0 cost, auto-repeat, off GCD) is the mana filler; `C_Spell.IsAutoRepeatSpell` exists [G]. Wands no longer scale with spell damage [G]. Wand Specialization (Discipline tier 1) +25%.

## 3. Ability table (DB2 ranks, costs, cast, cooldown, GCD)

IDs lowest rank first (first = `id`, rest = `copy`). `(L)` = base_level. Cost = mana; cast in s (unhasted); cd = the larger of RecoveryTime and category recovery. GCD is 1.5 s for every spell here except where stated. School masks: 2 holy, 32 shadow, 64 arcane. Channel flag = `SpellMisc.Attributes_1 & 0x4` [DB2 SpellMisc] (Mind Flay, Penance, Mind Sear).

| Key | Rank IDs (levels) | Cost per rank | Cast / duration | Cooldown | Notes |
|---|---|---|---|---|---|
| `shadow_word_pain` | 589, 594, 970, 992, 2767, 10892, 10893, 10894 (4,10,18,26,34,42,50,58) | 25,50,95,155,230,305,385,470 | instant; **18 s, tick 3 s** (aura 3, r8 127/tick, sp 0.2) | 0 | Improved SW:P 15275 +6 s at 2/2 (rank-1 row reads +6000) |
| `mind_blast` | 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 (10,16,22,28,34,40,46,52,58) | 50,80,110,150,185,225,265,310,350 | **1.5 s hard cast** | **8** (category) | sp 0.429 all ranks (r9 485); Improved Mind Blast 15273 -2.5 s at 5/5 (aura 107 misc 11) |
| `mind_flay` | 15407, 17311, 17312, 17313, 17314, 18807 (20,28,36,44,52,60) | 45,70,100,135,165,205 | **channel 3 s, tick 1 s** (aura 3 period 1000, r6 130/tick, sp 0.167); slow -50% (aura 33) | 0 | **talent** (Shadow tier 3, 1 point); no cast time in the row (cast_ms 0), duration 3000 |
| `devouring_plague` | 2944, 19276, 19277, 19278, 19279, 19280 (20,28,36,44,52,60) | 215,350,495,645,810,985 | instant; **24 s, tick 3 s** (aura 53, r6 106/tick, sp 0.1) | **60** (category) | baseline on Forever, heals caster, can crit [G]; disease |
| `shadow_word_death` | **1309595, 1309633, 1309635, 1309636** (32,40,48,56) | 175,205,250,340 | instant; r4 448, sp 0.429 | **15** (category, gcd category 133) | backlash 10% max health if the target survives (effect 2 base 10) [G]; NOT the rune 401955 (12% base, 12 s, L0) |
| `vampiric_embrace` | 15286 (30) | 40 | instant; **30 s**, "all party members healed for 20% of Shadow damage" (effect base 20) | 60 | **talent**; also triggers Spirit Tap on a death |
| `silence` | 15487 | 225 | instant; 5 s silence + 3 s "Interrupted" (1241057) | 45 | **talent** (tier 5); 20 yd; the only interrupt |
| `shadowform` | 15473 (talent) | **40% base** | instant, `category_cd` 1.5 s; until cancelled | 0 | section 6 |
| `inner_focus` 14751 | talent | 0 | until used | 180 | **GCD 0** |
| `power_infusion` 10060 | talent (L40) | **20% base** | 15 s | 180 | **GCD 0**, friendly target; section 4 |
| `smite` | 585, 591, 598, 984, 1004, 6060, 10933, 10934 (1,6,14,22,30,38,46,54) | 20,30,60,95,140,185,230,280 | **1.5, 2.0, 2.5 x6** s hard cast (r8 170, sp 0.714) | 0 | Divine Fury 18530 -0.5 s at 5/5; Mental Agility -10% cost |
| `holy_fire` | 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 (20,24,30,36,42,48,54,60) | 85,95,125,145,170,200,230,255 | **3.5 s hard cast**; direct r8 208 (sp 0.75) + **DoT 10 s, tick 2 s** (aura 3 period 2000, 15/tick, sp 0.05) | 0 | Power in Light 1309969 (+15% Smite/Penance vs your Holy Fire) |
| `penance` | 402174, 1240720, 1240721, 1316995 (30,40,50,60) | 150,220,270,385 | instant spell + **2 s channel** (child aura 402261/1240732.. period 1000): hits at 0, 1, 2 s (r4 92 each, sp 0.19; heal 425) | **12** (category) | Discipline talent (tier 5 [G]); 36 yd; channel flag set |
| `starshards` (Night Elf) | 10797, 19296, 19299, 19302, 19303, 19304, 19305 (10..58 by 8) | 50,85,140,190,245,300,350 | instant; **6 s DoT**, tick 1 s | 30 | Arcane (64), not buffed by Shadowform/Darkness |
| `dark_sacrifice` (Undead) | 1277324-1277328 (20..60 by 10) | 0 | 15 s | 600 | section 2.2 |
| `power_word_shield` | 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 (6..60 by 6) | 45,80,130,175,210,250,300,355,425,500 | 30 s absorb | 4 | Weakened Soul 6788 (15 s, on the target) |
| `inner_fire` | 588, 7128, 602, 1006, 10951, 10952 (12,20,30,40,50,60) | 30,65,105,165,235,315 | 600 s, **20 charges** (SpellAuraOptions ProcCharges 20), armor aura 22 | 0 | Improved Inner Fire +12 charges (aura 107 misc 4) |
| `power_word_fortitude` | 1243, 1244, 1245, 2791, 10937, 10938 (1,12,24,36,48,60) | 60,155,400,745,1170,1695 | 3600 s | 0 | Prayer of Fortitude 21562, 21564 (2600/3400) |
| `divine_spirit` | 14752, 14818, 14819, 27841 (30,40,50,60) | 285,420,785,970 | 3600 s | 0 | trainer spell on Forever [G]; Prayer of Spirit 27681 |
| `shoot` | 5019 | 0 | auto-repeat wand | | GCD 0 |
| utility, not priorities | Fade 586.. (40..275, cd 30), Psychic Scream 8122.. (cd 30), Mind Control 605.., Shackle Undead 9484.., Dispel Magic 527/988, Resurrection 2006.., heals (Heal 2054.., Flash Heal 2061.., Greater Heal 2060.., Renew 139..) | | | | Holy Nova 15237.. is a heal spell: blocked in Shadowform |

GCD for all of the above is 1.5 s (`gcd = "spell"`) except Inner Focus, Power Infusion, Shoot (`gcd = "off"`). Mind Blast's 1.5 s cast equals the GCD, so a hard cast adds no extra delay [G]. Hasted by Berserking (+10% cast speed, 10 s) through the engine's `haste` [MAGE 6, 10: stale in combat].

## 4. Auras and what `now` must carry

Player auras are secret in combat in general (`GetPlayerAuraBySpellID` stubs to `nil` in the facade) [HK `docs/forever-facade-notes.md:86`]; whether the Priest's are readable is Q5. Target debuffs are unreadable in combat: **every target effect is modelled from `CastSuccess` through `now`** and expires on a believed timer (Warrior/Druid rule). `UnitChannelInfo("player")` is plain [W PR9, facade notes:155].

| Key | ID (copy) | Unit | Duration / stacks | How the belief gets it |
|---|---|---|---|---|
| `shadowform` | 15473 (`copy` none needed) | player | until cancelled (`duration = 3600`) | reset hook from `GetShapeshiftForm` (section 6); `now` of the Shadowform cast `applyBuff( "shadowform" )` |
| `inner_fire` | 588, 7128, 602, 1006, 10951, 10952 | player | 600 s / 20 charges | `now`: apply; charges not tracked (hits unseen) |
| `inner_focus` | 14751 | player | until used, 1 charge | `now`: `applyBuff`; consumed by the cost mod (2.1) |
| `power_infusion` | 10060 | player/target | 15 s | **ability only**; aura stays in `Shared/Auras.lua` (see below) |
| `spirit_tap` | 15271 (talent 15270) | player | 15 s | proc on a kill, unseen: read it if Q5 allows, else absent |
| `power_word_fortitude` / `divine_spirit` / `weakened_soul` | 1243.. / 14752.. / 6788 | player | 3600 s / 3600 s / 15 s | `now` for self-casts; Weakened Soul `now` of Power Word: Shield (15 s) |
| `shadow_word_pain` | 589.. | **target** | 18 s (+6 s Improved SW:P) | `now`: `applyDebuff( "target", "shadow_word_pain", 18 + imp_swp )`; `tick_time = 3` |
| `devouring_plague` | 2944.. | target | 24 s, tick 3 | `now`; also set `cooldown` 60 (cast ledger) |
| `vampiric_embrace` | 15286 | target | 30 s | `now` |
| `holy_fire` (DoT) | 14914.. | target | 10 s, tick 2 | `now`; DoT starts at cast **end** (3.5 s hard cast, `now` runs at `CastSuccess`) [MAGE 6] |
| `starshards` | 10797.. | target | 6 s, tick 1 | `now` |
| `mind_flay` | 15407.. | target | 3 s, tick 1 | `start` (channel `now` timing is Q4); required by `Core.lua:CheckChannel` as `ability.aura` |
| `shadow_weaving` | 15258 (talent 15257) | target (from caster) | 15 s / 5 stacks (aura 270 +2% Shadow damage per stack) | decides nothing: **not modelled** [G: 3 ranks, personal] |
| `silence` / `interrupted` | 15487 / 1241057 | target | 5 s / 3 s | not tracked |

**What `now` must carry** (target effects invisible in combat): Shadow Word: Pain (apply with the talent-adjusted duration), Devouring Plague (apply 24 s; the 60 s cooldown comes from the cast ledger), Vampiric Embrace, Holy Fire's DoT, Starshards; **Penance and Mind Flay** need the channel handling of section 9. Nothing else decides a priority, so no crit, proc, kill or Shadow Weaving read is needed
(Devouring Contagion's spread on a death, Spirit Tap's procs and Shadow Weaving's stacks are unseen events: not modelled).

**The Power Infusion hand-off.** `Forever/Shared/Auras.lua` registers aura `power_infusion` {id 10060, duration 15, `shared = "player"`, `dot = "buff"`} for *another* Priest's cast, read by the player aura walk (shared-content spec R3). The Priest file registers `ability power_infusion` {id 10060, `spend = 0.2`, `cooldown = 180`, `gcd = "off"`, `toggle = "cooldowns"`, `aura = "power_infusion"`} and **no aura of its own**,
so the shared entry serves both self-casts and a partner's; the class file re-registering `power_infusion` would win the merge (Spec.lua, class first) and drop `shared = "player"`. A self-cast needs a handler `applyBuff( "power_infusion" )` (the aura is on the *target*; only valid when that is you: gate with `settings.pi_self`, default false).

## 5. Talents (DB2 tree, Hekili key style; Forever-only flagged)

Format as the Warrior/Druid: `key = { 0, definitionSpell, maxRank }`; max ranks = non-zero rank slots in `wowdb talents PRIEST` (the DB2/Era counts; [G] disagreements below). Counts: Discipline 15, Holy 16, Shadow 16. Ranks come from the trait walk once the Q1 export defines the nodes (Warrior note, `Warrior.lua:233-241`).
```lua
-- Discipline (15)
unbreakable_will = { 0, 14522, 5 }, wand_specialization = { 0, 14524, 5 }, silent_resolve = { 0, 14523, 5 }, improved_power_word_fortitude = { 0, 14749, 2 },
improved_power_word_shield = { 0, 14748, 3 }, martyrdom = { 0, 14531, 2 }, inner_focus = { 0, 14751, 1 }, meditation = { 0, 14521, 3 },
improved_inner_fire = { 0, 14747, 3 }, mental_agility = { 0, 14520, 5 }, improved_mana_burn = { 0, 14750, 2 }, mental_strength = { 0, 18551, 5 },
divine_spirit = { 0, 14752, 1 }, force_of_will = { 0, 18544, 5 }, power_infusion = { 0, 10060, 1 },
-- Holy (16)
twilight_focus = { 0, 14913, 2 }, improved_renew = { 0, 14908, 3 }, holy_specialization = { 0, 14889, 5 }, spell_warding = { 0, 27900, 5 }, divine_fury = { 0, 18530, 5 },
holy_nova = { 0, 15237, 1 }, blessed_recovery = { 0, 27811, 3 }, inspiration = { 0, 14892, 3 }, holy_reach = { 0, 27789, 2 }, improved_healing = { 0, 14912, 3 },
searing_light = { 0, 14909, 2 }, holy_tier4_col0 = { 0, 14911, 2 }, spirit_of_redemption = { 0, 20711, 1 }, spiritual_guidance = { 0, 14901, 5 },
spiritual_healing = { 0, 14898, 5 }, lightwell = { 0, 724, 1 },
-- Shadow (16)
spirit_tap = { 0, 15270, 5 }, blackout = { 0, 15268, 5 }, shadow_affinity = { 0, 15318, 3 }, improved_shadow_word_pain = { 0, 15275, 2 }, shadow_focus = { 0, 15260, 5 },
improved_psychic_scream = { 0, 15392, 2 }, improved_mind_blast = { 0, 15273, 5 }, mind_flay = { 0, 15407, 1 }, improved_fade = { 0, 15274, 2 }, shadow_reach = { 0, 17322, 3 },
shadow_weaving = { 0, 15257, 5 }, silence = { 0, 15487, 1 }, vampiric_embrace = { 0, 15286, 1 }, improved_vampiric_embrace = { 0, 27839, 2 }, darkness = { 0, 15259, 5 },
shadowform = { 0, 15473, 1 },
-- Forever-only (ids >= 1,000,000: no node in the DB2 tree; node, tier and max rank from [G]/FDB; definition spells from DB2): the real list needs Q1
improved_mind_flay = { 0, 1225139, 2 },     -- Shadow tier 3: +20% Mind Flay damage, +10 yd range, slow 50% -> 20% (aura 108 misc 22, 107 misc 5, 107 misc 12 -30, aura 4 base 50)
devouring_contagion = { 0, 1309950, 2 },    -- Shadow tier 5: Devouring Plague -50% mana (aura 108 misc 14), spreads on death within 10 yd (5 yd at 1/2)
early_demise = { 0, 1310076, 2 },           -- Shadow tier 6 (L35): Shadow Word: Death +30% crit at or below 20% health
twin_disciplines = { 0, 1225132, 5 },       -- Discipline: +5% (full-rank row) damage and healing of instants (aura 108 misc 0 and 22)
power_in_light = { 0, 1309969, 5 },         -- Discipline tier 1: Smite and Penance +15% (row) vs targets with your Holy Fire (aura 4 base 15)
holy_precision = { 0, 1309957, 1 },         -- Holy: +18% (row) hit with Holy spells (aura 107 misc 16)
```
- **Forever-only** (6): Improved Mind Flay, Devouring Contagion, Early Demise, Twin Disciplines, Power in Light, Holy Precision (ranks for the last three are not in the repos: max values above are placeholders, Q1). **Removed on Forever** [G]: Improved Vampiric Embrace (replaced by Devouring Contagion), Unbreakable Will, Force of Will; Mind Flay is a one-point talent at L20; Shadowform moves to tier 7 / L40 and Silence loses its Improved Psychic Scream gate (DB2 prereq 542 rank 1). **Changed**: Shadow Weaving personal, 3 ranks (+2% per stack, 5 stacks max), Spirit Tap 100% chance and a VE-death trigger, Improved SW:P +6 s, Improved Mind Blast -2.5 s.
- **Max-rank disagreements, DB2 (Era) vs [G]**: Shadow Weaving 5 vs 3, Shadow Affinity 3 (text -30%; row -8), Shadow Focus 5 (text now +5% hit), Meditation 3 (text 17/33/50). The Holy tier-4 node 14911 has no spell row at all in `spell_info` (name empty). Until Q1, the DB2 counts are the table's.
- Keys the APL reads: `talent.mind_flay.enabled`, `talent.shadowform.enabled`, `talent.improved_shadow_word_pain.rank`, `talent.improved_mind_blast.rank`, `talent.devouring_contagion.rank`, `talent.inner_focus.enabled`, `talent.power_infusion.enabled`.

## 6. Shadowform: a stance-like aura

- **Shadowform is a real shapeshift form.** 15473 effect 0 is aura 36 (MOD_SHAPESHIFT) with misc0 = **28** (the Shadowform id) [DB2 effects 15473; the Druid forms are the same aura with misc 1/5/8/3/4/31, DRUID 6]. The other effects: +10% Shadow damage (aura 79 misc 32), -15% physical damage taken (aura 87), Shadow costs -50% (aura 72 misc 32), +100% Shadow crit-damage bonus (aura 108 misc 15).
  The description: "However, **you may not cast healing spells** while in this form" [DB2 description]; Smite, Holy Fire, Penance (an offensive spell) and Mind Blast are castable [G]. **Do not copy the Druid's `SpellMisc.Attributes_2 & 0x80000` (NOT_NEED_SHAPESHIFT) test** [DRUID 6]: on a Priest it is 1 for Power Word: Shield, Inner Fire, SW:P, Mind Flay, Mind Blast and
  the heals, but **0 for Smite, Holy Fire, Penance, Vampiric Embrace, Power Infusion and Shadowform itself** [DB2 SpellMisc], which the guides use freely. The cast-from-form rules are healing-only; Q3 lists what errors.
- **What the Druid form handling is** [H `Druid.lua:108-116`, `reset_precast` at 619-634; DRUID 6]: `FORMS`/`FORM_OF_SPELL` map the form's spell ID to an aura; `reset_precast` removes every form aura, reads `GetShapeshiftForm()` and `GetShapeshiftFormInfo(form)`'s **4th return** (the spell ID), and `applyBuff`s the aura. It **applies to the Priest, shrunk to one form**:
  `reset_precast`: `removeBuff( "shadowform" )`; `local f = GetShapeshiftForm()`; `if f and f > 0 then local _,_,_,id = GetShapeshiftFormInfo( f ); if id == 15473 then applyBuff( "shadowform" ) end end`. No `swap_form` StateFunction is needed (no rage/energy to lose; the Shadowform cast costs 40% base mana and nothing else) and no `form` alias; gates are `buff = "shadowform"`/`nobuff = "shadowform"`.
  Hekili's own `stance` table is not used (it reads a fifth return that does not exist, State.lua 2617-2631).
- **Is the form read plain in combat?** The Warrior's `GetShapeshiftForm` was plain in combat [W PR10, facade notes:115-116], but the Druid brief records that a *form* is an aura, not a stance, and the Druid's plain read is unverified [DRUID 6, Q2]. Shadowform is the same case (aura 36, a 28 form). **Q2 settles it.** Fallback if the read is secret or `GetNumShapeshiftForms() == 0`: infer from
  the Shadow-spell cost, which `C_Spell.GetSpellPowerCost` returns plain and modified (it reads 0 under Clearcasting [MAGE 2.4, P]): `cost( Mind Blast ) == 175 at rank 9` means Shadowform is up. Implement as a `reset_precast` fallback comparing the client cost to the table cost x0.5 (Q2 line 2).
- **The stub hand-off.** `Forever/Shared/Auras.lua:23` registers `shadowform = {}` (an id-less stub; the shared spec §4.1 notes "Priest 15473, no pack") because core reads it by name: `State.lua:1983` (`prowling` = `buff.prowl.up or ( buff.cat_form.up and buff.shadowform.up )`) and `State.lua:3201/3214` (`buff.voidform.up`, not shadowform; the stub `voidform = {}` stays). The class file's `shadowform` {id = 15473} **supersedes the stub without touching Shared/Auras.lua**: `SpecializationChanged` merges `specs` in order
  current spec first, `0` (the `all` spec) last, and `if not class.auras[ k ] then class.auras[ k ] = v end` (Spec.lua 1996, 2083-2085), so the class entry wins and the stub is only seen by non-Priests. Leave the stub (Warrior/Druid still need it); the `prowling` read on a Priest evaluates `cat_form.up` false first, harmless.
- **Shadowform off-GCD?** No: GCD 1.5 s plus a 1.5 s own recovery (`category_cd` 1500) [DB2 `spell_info` 15473]. A healing cast drops the form; the pack has no heals, so re-entry after a manual heal is the `shadowform,if=!buff.shadowform.up` line at the top of the combat list.

## 7. Draft priorities (SimC style, pack convention, stateless)

Format as `tools/packs/warrior.lua` / `druid.lua`: `actions.precombat` first, `settings.*` guards, `known` gates the missing ranks and talents (one text serves levels 1-60), no state kept between evaluations. Settings: `buffs` (bool, default true), `boss_dots` (bool: Devouring Plague on any target, default false), `swd` (bool: Shadow Word: Death, default false),
`wand` (bool) and `wand_pct` (default 15), `plague_pct` (default 35), `pi_self` (bool), `embrace` (bool, default false), `imp_swp`/`imp_mb`/`contagion` (0-2/0-5/0-2 ranks, until Q8). `moving` exists (`VS.Moving`), `time_to_die` does not (target health is secret), `boss` is the Warrior's. Classic-era baselines: DoTs first, Mind Blast on cooldown, filler channel [G, Wrath `PriestShadow.simc`].
```
# Shadow (default). Smite is the filler only before Mind Flay is learned; Shadowform from level 40.
actions.precombat=shadowform,if=!buff.shadowform.up
actions.precombat+=/power_word_fortitude,if=settings.buffs&!buff.power_word_fortitude.up
actions.precombat+=/divine_spirit,if=settings.buffs&!buff.divine_spirit.up
actions.precombat+=/inner_fire,if=!buff.inner_fire.up
actions.precombat+=/mind_blast
actions=silence,if=toggle.interrupts&debuff.casting.up&debuff.casting.v2=0
actions+=/shadowform,if=!buff.shadowform.up
actions+=/power_infusion,if=toggle.cooldowns&settings.pi_self
actions+=/shadow_word_pain,if=!dot.shadow_word_pain.up
actions+=/devouring_plague,if=!dot.devouring_plague.up&(settings.boss_dots|boss|target.level>=level+3)&mana.pct>=settings.plague_pct
actions+=/starshards,if=!dot.starshards.up
actions+=/vampiric_embrace,if=toggle.cooldowns&settings.embrace&!dot.vampiric_embrace.up
actions+=/shadow_word_death,if=settings.swd
actions+=/inner_focus,if=toggle.cooldowns&!buff.inner_focus.up&cooldown.mind_blast.ready
actions+=/mind_blast
actions+=/mind_flay,chain=1,interrupt_if=ticks>=2&(cooldown.mind_blast.ready|!dot.shadow_word_pain.up)
actions+=/smite,if=!talent.mind_flay.enabled&mana.pct>=settings.wand_pct
actions+=/shoot,if=settings.wand&mana.pct<settings.wand_pct
```
```
# Smite / Holy damage (Holy tree or a levelling Priest with no Mind Flay): Holy Fire first, SW:P and Mind Blast on cooldown, Smite filler
actions.precombat=power_word_fortitude,if=settings.buffs&!buff.power_word_fortitude.up
actions.precombat+=/divine_spirit,if=settings.buffs&!buff.divine_spirit.up
actions.precombat+=/inner_fire,if=!buff.inner_fire.up
actions.precombat+=/holy_fire
actions=holy_fire,if=!dot.holy_fire.up
actions+=/shadow_word_pain,if=!dot.shadow_word_pain.up
actions+=/mind_blast
actions+=/smite,if=mana.pct>=settings.wand_pct
actions+=/shoot,if=settings.wand
```
```
# Discipline damage: Holy Fire opener (unlocks Power in Light), Penance on cooldown, Inner Focus with the Penance (cooldowns), Smite filler
actions.precombat=<as Smite/Holy, without the last line>
actions=power_infusion,if=toggle.cooldowns&settings.pi_self
actions+=/holy_fire,if=!dot.holy_fire.up
actions+=/inner_focus,if=toggle.cooldowns&!buff.inner_focus.up&cooldown.penance.ready
actions+=/penance
actions+=/shadow_word_pain,if=!dot.shadow_word_pain.up
actions+=/mind_blast
actions+=/smite,if=mana.pct>=settings.wand_pct
actions+=/shoot,if=settings.wand
```
Notes. `silence` reuses the Mage's counterspell line: the target cast is a model [MAGE 6, facade notes:231]. **SW:P is recast only on expiry**: a recast replaces the DoT and drops the unticked remainder [VAN, G]; the sim's expiry is the believed timer. **Shadow Word: Death is behind `settings.swd`** because the target's health is secret and a non-kill costs 10% of max health [G]; if Q10 shows `IsSpellUsable` is health-gated,
replace the setting with an `execute_phase`-style StateExpr (Warrior.lua:1555). Inner Focus before Mind Blast follows [G wowtbc.gg] (Mind Blast is non-periodic, so it also gets +25% crit). Devouring Plague has the worst damage per mana (0.86) and so a mana floor and a boss gate [G]. Thresholds are judgment; no sim backs them.

## 8. Checkpoint questions (each one `/run`, VSCopy, under 255 characters)

Run on a Priest (Shadow, level 40+ for Q2, Q7; a Gnome or Troll helps; an Undead for Q7). `VSCopy` is ForeverProbe's (`~/src/ForeverProbe/Copy.lua`; `/vscopy` reopens it). Ranked by importance.

| # | Question | Line | Answer -> action |
|---|---|---|---|
| Q1 | **Live talent tree + Forever-only nodes** | `/fprobe export`, `/reload`, then `/run local e=ForeverProbeDB.export;VSCopy(e.meta.class,#e.spells,#e.talents.trees,e.stances.num)` | node list, ranks -> section 5 Forever-only block; resolves the max-rank disagreements |
| Q2 | **Shadowform detection** | `/run VSCopy(GetNumShapeshiftForms(),GetShapeshiftForm(),GetShapeshiftFormInfo(1))` out of combat in and out of the form, then again in combat | `1, 1, icon, true/false, true, 15473` plain in combat -> section 6 reset hook; secret or 0 forms -> cost fallback: `/run VSCopy(C_Spell.GetSpellPowerCost(10947)[1].minCost)` (175 in form, 350 out) |
| Q3 | **What errors in Shadowform** | in the form, cast Smite, Holy Fire, Penance, Power Word: Shield, Inner Fire, Vampiric Embrace, Power Infusion, then `/run VSCopy(C_Spell.IsSpellUsable(14914),C_Spell.IsSpellUsable(402174),C_Spell.IsSpellUsable(15286))` | usable true -> no `nobuff` gates; false -> a `nobuff = "shadowform"` on the refused spells |
| Q4 | **Mind Flay channel info** | `/run VSCopy(UnitChannelInfo("player"))` during Mind Flay (once in combat); same during Penance | name, text, texture, start, end plain in combat; end - start 3000 / 2000; fixes when a channel's `now` runs (start or end) and the `casting` aura's `v3` |
| Q5 | **Player aura readability**: Spirit Tap, Inner Fire, Power Infusion | `/run VSCopy(pcall(C_UnitAuras.GetPlayerAuraBySpellID,15271))` after a kill (Spirit Tap), and `10060` after a self-cast Power Infusion | readable -> read them and drop the inference; `10060` also confirms the aura id and `sourceUnit` for section 4; secret -> `now`/cost inference only |
| Q6 | **Mana pool + regen pair** | `/run VSCopy(UnitPowerMax("player",0),GetPowerRegenForPowerType(0),GetManaRegen())`; idle full mana, right after a cast, 6 s later, then once under Spirit Tap | plain -> `meta.max` and `regen` seeds; secret -> ladder only; the casting-vs-idle pair [MAGE Q3] decides whether the second rate is needed |
| Q7 | **SW:P refresh rule** | on a dummy: cast SW:P, wait 6 s, cast again, then `/run local a=C_UnitAuras.GetAuraDataByIndex("target",1,"HARMFUL|PLAYER") VSCopy(a and a.spellId,a and a.duration,a and a.expirationTime-GetTime())` | duration restarts at 18 (24 with the talent) and the old unticked ticks are lost -> recast-on-expiry only (section 7); if it carries over, `refreshable` rules |
| Q8 | **Talent rank text** (rank-1 rows read full-rank values) | `/run VSCopy(C_Spell.GetSpellDescription(15273),C_Spell.GetSpellDescription(15275))` and, after a Mind Blast, `/run VSCopy(C_Spell.GetSpellCooldown(8092).duration)` | per-rank cooldown 8 vs 5.5 and SW:P 18/21/24 -> the `imp_mb`/`imp_swp` rules without a setting |
| Q9 | **SoD leftovers learnable?** | `/run VSCopy(IsSpellKnown(402668),IsSpellKnown(401977),IsSpellKnown(413259),IsSpellKnown(431655),IsSpellKnown(425294),IsSpellKnown(1309595),IsSpellKnown(401955))` | all false except 1309595 (Forever SWD, L32+) -> section 0 holds; any true -> a spell to register |
| Q10 | **SWD usability vs target health** | `/run VSCopy(C_Spell.IsSpellUsable(1309595))` at 100% and at 15% health | equal -> `settings.swd` stays; differs -> a plain `execute_phase` StateExpr |
| Q11 | **Spell haste plain in combat** | `/run VSCopy(UnitSpellHaste("player"),GetHaste())` with and without Berserking | secret -> Mind Flay ticks and the GCD lag by 10% (section 9) [MAGE 10] |

## 9. Risks and what the belief lacks

- **Channels in the `start`/`tick`/`finish` model.** A channeled ability's `handler` is not run (`RunHandler`, State.lua 6130-6140): `ability.start` runs and `channelSpell( key, query_time, ability.cast, ability.id )` queues `CHANNEL_FINISH` at the end and a `CHANNEL_TICK` every `ability.tick_time or aura.tick_time` (State.lua 6421-6436) [MAGE 6]. So Mind Flay declares `channeled = true`, `cast = 3`, `tick_time = 1`, `aura = "mind_flay"`, `start = applyDebuff( "target", "mind_flay", 3 )`, and Penance `cast = 2`, `tick_time = 1`
  (hits at 0, 1, 2 s, so three; its first hit lands at the cast, the `start` handler). `tick` and `finish` are optional (no Shadow Weaving or Pain and Suffering to model). **Breaking it**: `Core.lua:459 CheckChannel` allows `chain`, `early_chain_if` and `interrupt_if` only on a tick edge (`last_tick`, or within 0.25 s of a tick) with the GCD ready, and refuses outright when neither the ability nor its aura has `tick_time`.
  It reads the real channel from `buff.casting` (`UnitChannelInfo`, plain). **Risk 1**: `ticks` in `interrupt_if` resolves to `1 + dot[aura].duration/tick_time - ticks_remain` (State.lua 4978-4981) on the *target debuff* `mind_flay`, which only exists in the sim if `start` applied it; an in-progress *real* channel at reset has no `dot.mind_flay` unless the belief's `now` set it at SUCCEEDED
  (Q4: whether Forever fires it at channel start). If it does not, replace `ticks>=2` by a time test against `buff.casting.applied` (`query_time - buff.casting.applied >= 2`). **Risk 2**: the rule "clip after tick 2 for a ready Mind Blast or an expired SW:P, else let tick 3 land" [G INF] is arithmetic, not sim-backed. **Risk 3**: the Mage's channel-length cap, `UnitChannelInfo` channels over 10 s are ignored
  (Spec.lua 1525), is fine for 3 s and 2 s.
- **DoT clipping without target reads.** SW:P, DP, VE, Holy Fire and Starshards run on believed timers from `CastSuccess`. A resist or miss is invisible; pushback of the *cast* is seen (`CastDelay`) but a DoT application is not confirmed. The Druid precedent (`missedAt` from `UI_ERROR_MESSAGE`) does not cover a Priest's resist. A wrong "up" costs a full GCD; a recast with time left forfeits a tick (Q7). No snapshotting on Forever [G], so no pandemic logic.
- **Procs and kills are unseen** (Spirit Tap, Shadow Weaving, Devouring Contagion's spread): mana regen under Spirit Tap and the DP "up" after a spread are wrong whenever they fire. Spirit Tap's absence makes the sim's mana model pessimistic.
- **Shadowform halves cost.** If the form read fails (Q2) the sim over-charges Shadow spells by 2x and the `mana.pct` gates trip early (and the 40% cast of Shadowform itself is `spend = 0.4`, an overstatement by max/base mana [MAGE 2.1]).
- **School lockouts** are invisible (a Silence on the Priest locks Shadow, Holy still castable): `loss_of_control` keeps only `lockoutSchool == 0` events [MAGE 10, Shared/Auras.lua]; this is the Mage's Q14, not repeated.
- **The `all` shadowform stub and `voidform`.** `State.lua:3201` takes `voidform` into the GCD floor (`0.67` or `0.75`); the stub never goes up, so the GCD floor is 0.75 s for a Priest (no effect: base 1.5 s). The shadowform supersession above is safe in the merge order; a *test* should assert `class.auras.shadowform.id == 15473` for a Priest and `nil` for a Warrior.
- **The Eureka! cost scope lists the SoD SWD rune (401955)** next to the Forever one (1309595): harmless (`copy` resolves only registered IDs) but the Priest file must register 1309595 as `id` with 1309633/35/36 as `copy`, not the rune.
- **Percent-cost overstatement**, one rate for regen, haste stale in combat: shared with the Mage [MAGE 10], not Priest work.

## 10. DB2 queries used (all `~/.local/share/wow-db2/bin/wowdb`, build 1.60.1.70338)

- Tree: `wowdb talents PRIEST` (ranks = non-zero `r1..r5`; 47 rows: Discipline 15, Holy 16, Shadow 16). Rank-row presence: `select t.name,t.r2,s.name,s.rank from talent_info t join spell_info s on s.id=t.r2 where t.class='PRIEST'` (3 rows); `select name,r1 from talent_info where class='PRIEST' and r1 not in (select id from spell_info)` (Holy 14911).
- Spells: `select s.id,s.name,s.rank,s.base_level,s.school_mask,s.cast_ms,s.duration_ms,s.power,s.cost,s.cost_pct,s.cooldown_ms,s.category_cd_ms,s.gcd_ms,s.range_max from spell_info s join spell_skill k on k.spell_id=s.id where k.classes like '%PRIEST%' and k.skill_line in ('Shadow Magic','Shadow','Holy','Discipline') order by s.name,s.base_level`;
  the runes/engravings/racials: the same with `k.skill_line in ('Runes','Engraving','Meditation','Racial - Gnome','Racial - Troll','Racial - Undead')`; per name `select id,name,rank,base_level,cast_ms,duration_ms,cost,cost_pct,cooldown_ms,category_cd_ms,gcd_ms,max_stacks,skill_line,classes from spell_info where name='<Name>'` (Vampiric Touch, Mind Sear, Mind Spike, Shadowfiend, Dispersion, Void Plague, Surge of Light, Inner Focus, Inner Fire, Shadowform, Spirit Tap, Starshards, Smite, Holy Fire, Penance, SW:P, VE); `wowdb spell 'Shadow Word: Death'`.
- Effects: `wowdb effects <id>` for 15473 (and 1213334, 401980, 426223, 16592, 22917), 15270, 15271, 10060, 14751, 14521, 15407, 18807, 15257, 15258, 6788, 8092, 10947, 10894, 19280, 2944, 10934, 15261, 1316995, 1316991, 1316993, 1316992, 1316994, 402261, 1309636, 15286, 10952, 15487, 1241057, 1277324-8, 1225139, 1309950, 1310076, 1225132, 1309969, 1309957, 15273, 15275, 15268, 15260, 15259, 15318, 17322, 14531, 14524, 14522, 14520, 14747, 18530, 14909, 18551.
  Full descriptions (15473, 15270, 14751) read with `sqlite3` Python on `spell_info.description` (wowdb truncates the column).
- Masks and attributes: `select * from SpellEffect where SpellID=14751` (masks -721944581 / 278135862 / 83952128 / 268436624); `select distinct o.SpellID,n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID join spell_skill k on k.spell_id=o.SpellID where o.SpellClassSet=6 and k.classes like '%PRIEST%' and (((o.SpellClassMask_0 & <m0>)<>0) or ... _3)`; `select SpellID,Attributes_0..Attributes_5 from SpellMisc where SpellID in (...)` (channel `& 0x4`, NOT_NEED_SHAPESHIFT `Attributes_2 & 524288`); `select SpellID,ProcChance,ProcCharges from SpellAuraOptions where SpellID in (10952,14751,588)`.
- Forever-only spells by description: `select id,name,substr(description,1,150) from spell_info where id>=1000000 and (description like '%Mind Blast%' or description like '%Mind Flay%' ...)`. Engine reads: `Engine/Spec.lua` 1996, 2083-2085, 1525; `Engine/Races.lua` 55-130; `Engine/Shared.lua`; `Core.lua` 459-585; `State.lua` 1983, 3201, 4978, 6130-6160, 6385-6440; `Forever/Classes/Druid.lua` 108-116, 538, 619-634, 1122-1143; `Forever/Shared/Auras.lua`; `Forever/Races/Gnome.lua`; `origin/classic:Classic/Priest.lua` 332, 470, 1121.

## 11. Pack spec inputs (constants to copy)
```lua
-- Pseudo-spec: id to be chosen (Warrior 1491, Druid 1499), class "PRIEST"; RegisterResource( Enum.PowerType.Mana ); RegisterOptions( { package = "Shadow" } ); spec icon e.g. 136207 (spell_shadow_shadowwordpain)
local SHADOW_WORD_PAIN = { 589, 594, 970, 992, 2767, 10892, 10893, 10894 }  local SWP_COST = { 25, 50, 95, 155, 230, 305, 385, 470 }  -- 18 s, tick 3, +6 s Improved SW:P
local MIND_BLAST = { 8092, 8102, 8103, 8104, 8105, 8106, 10945, 10946, 10947 }  local MB_COST = { 50, 80, 110, 150, 185, 225, 265, 310, 350 } -- cast 1.5, cd 8, -2.5 Improved MB
local MIND_FLAY = { 15407, 17311, 17312, 17313, 17314, 18807 }  local MF_COST = { 45, 70, 100, 135, 165, 205 }  -- channeled, cast 3, tick_time 1, gcd spell, talent
local DEVOURING_PLAGUE = { 2944, 19276, 19277, 19278, 19279, 19280 }  local DP_COST = { 215, 350, 495, 645, 810, 985 }  -- 24 s, tick 3, cd 60; Devouring Contagion -50%
local SHADOW_WORD_DEATH = { 1309595, 1309633, 1309635, 1309636 }  local SWD_COST = { 175, 205, 250, 340 }  -- cd 15, instant; NOT 401955
local SMITE = { 585, 591, 598, 984, 1004, 6060, 10933, 10934 }  local SMITE_COST = { 20, 30, 60, 95, 140, 185, 230, 280 }  local SMITE_CAST = { 1.5, 2, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5 } -- Divine Fury -0.5
local HOLY_FIRE = { 14914, 15262, 15263, 15264, 15265, 15266, 15267, 15261 }  local HF_COST = { 85, 95, 125, 145, 170, 200, 230, 255 }  -- cast 3.5, DoT 10 s tick 2
local PENANCE = { 402174, 1240720, 1240721, 1316995 }  local PENANCE_COST = { 150, 220, 270, 385 }  -- channeled, cast 2, tick_time 1, cd 12
local STARSHARDS = { 10797, 19296, 19299, 19302, 19303, 19304, 19305 }  local STARSHARDS_COST = { 50, 85, 140, 190, 245, 300, 350 }  -- cd 30, 6 s tick 1
local POWER_WORD_SHIELD = { 17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 }  local PWS_COST = { 45, 80, 130, 175, 210, 250, 300, 355, 425, 500 }  -- cd 4, Weakened Soul 6788 (15 s)
local INNER_FIRE = { 588, 7128, 602, 1006, 10951, 10952 }  local INNER_FIRE_COST = { 30, 65, 105, 165, 235, 315 }  -- 600 s, 20 charges
local POWER_WORD_FORTITUDE = { 1243, 1244, 1245, 2791, 10937, 10938 }  local PWF_COST = { 60, 155, 400, 745, 1170, 1695 }  -- 3600 s; Prayer of Fortitude 21562, 21564
local DIVINE_SPIRIT = { 14752, 14818, 14819, 27841 }  local DS_COST = { 285, 420, 785, 970 }  -- 3600 s
local DARK_SACRIFICE = { 1277324, 1277325, 1277326, 1277327, 1277328 }  -- cd 600, 15 s; health per 3 s 80, 136, 196, 258, 320
-- single spells: vampiric_embrace 15286 (40, cd 60, 30 s), silence 15487 (225, cd 45, 5 s), shadowform 15473 (spend 0.4, gcd spell, category 1.5), inner_focus 14751 (cd 180, gcd off),
--   power_infusion 10060 (spend 0.2, cd 180, 15 s, gcd off), shoot 5019 (gcd off)
-- auras: shadowform 15473 (3600), inner_fire (ranks above), inner_focus 14751, power_infusion 10060 (STAYS in Shared/Auras.lua), spirit_tap 15271 (15 s), weakened_soul 6788 (15),
--   shadow_weaving 15258 (15 s, 5), silence_target 15487, interrupted 1241057 (3 s), mind_flay (aura key, tick_time 1, copy = MIND_FLAY), shadow_word_pain (tick 3), devouring_plague (tick 3), holy_fire (tick 2), starshards (tick 1)
-- Shadow-school cost scope (Shadowform): MIND_BLAST + MIND_FLAY + SHADOW_WORD_PAIN + DEVOURING_PLAGUE + SHADOW_WORD_DEATH + { 15286, 15487, 605, 8129, 586, 8122 }; Inner Focus scope = every ability
spec:RegisterCostMod( { aura = "shadowform", pct = -0.5, spells = { 8092, 15407, 589, 2944, 1309595, 15286, 15487, 605, 8129, 586, 8122 } } )
spec:RegisterCostMod( { aura = "inner_focus", pct = -1, charges = 1 } )
-- reset_precast: removeBuff( "shadowform" ); GetShapeshiftForm() > 0 and GetShapeshiftFormInfo( f ) 4th return == 15473 -> applyBuff( "shadowform" ) (fallback: Mind Blast cost x0.5)
-- now: SW:P applyDebuff( "target", "shadow_word_pain", 18 + 3 * improved_swp_rank_or_full_value ); DP 24; VE 30; Holy Fire 10; Starshards 6; Penance is a channel (cast 2, tick_time 1), no debuff
-- Gnome Eureka! PRIEST 1259823 and Expansive Mind 20591 are already in Forever/Races/Gnome.lua; Troll Berserking 20554 stock; Night Elf Starshards and Undead Dark Sacrifice are class skill-line spells (the race files do not hold them)
-- Forever-only talent spells (>= 1,000,000): 1225139 improved_mind_flay, 1309950 devouring_contagion, 1310076 early_demise, 1225132 twin_disciplines, 1309969 power_in_light, 1309957 holy_precision
```
