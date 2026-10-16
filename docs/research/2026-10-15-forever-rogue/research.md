# Forever Rogue class pack in the Hekili fork: research brief (2026-10-15)

Read-only research for a spec of `src/Hekili/Forever/Classes/Rogue.lua` beside Warrior.lua and Druid.lua. Hekili HEAD 3e906ad0. Build: Forever DB2 1.60.1.70338 (`wowdb`), client 1.60.1.70374, beta cap 30, launch 2026-11-04. Tags: [DB2]
queried here; [TDF] `~/src/docs/research/tdf/2026-10-13-forever-rogue-rotations.md` ("TDF rogue", guides + Blizzard 2026-10-07 deep dive, not re-verified); [HK] Hekili file; [P] in-game probe relayed by a repo doc; [I] my
inference. Energy/mana costs are DB2 points. Template: `docs/research/2026-10-15-forever-druid/research.md` ("Druid R").

## 0. Not found / cannot be settled from the repos (read this first)

- **The live Forever Rogue talent tree is not in the DB2.** `Talent` holds the vanilla/TBC tree (49 rows, three of them renamed "Hack and Slash"); the Forever-only talents exist only as spells with IDs >= 1,000,000 and no tree position
  (section 3). A ForeverProbe export on a Rogue does not exist (`~/src/ForeverProbe/results` has W and O runs only). Q1.
- **Energy regen rate and shape** were never probed on a Rogue; 10/s continuous is Blizzard's note plus the Druid's probe (`GetPowerRegenForPowerType(3)` = 10.001 plain out of combat, secret in combat, Druid R 2.1 [P]). Q2.
- **Whether `UnitPower(player, ComboPoints)` is plain in combat.** `GetComboPoints("player","target")` is plain in combat (Rogue gate spike, per the Druid R 2.2 [P]), but the Virtual layer polls `UnitPower`, not `GetComboPoints` (section 8,
  R3). Blood in the Water saw `UnitPower(4)` secret. Q3.
- **Player auras in combat** (Slice and Dice, Adrenaline Rush, Stealth) are secret per the facade notes; `IsStealthed()` is a plain bool in the Forever API index but was never probed in combat. Q5, Q6.
- **`C_Item.GetWeaponEnchantInfo`** exists on Forever (`secretArguments = AllowedWhenUntainted`, returns a table) but is not in `tools/api_inventory.txt`, was never probed and Hekili's Classic code calls the removed global form. Q9.
- No `SpellShapeshift` table, no `SpellItemEnchantment` table in the DB2 (tables: ChrClasses, Item, ItemSparse, SkillLine, SkillLineAbility, Spell, SpellAuraOptions, SpellCastTimes, SpellCategories, SpellCategory, SpellClassOptions,
  SpellCooldowns, SpellDuration, SpellEffect, SpellLevels, SpellMisc, SpellName, SpellPower, SpellRange, Talent, TalentTab): the weapon-type requirements (dagger for Backstab/Ambush/Mutilate) and the poison enchant IDs are not queryable;
  they come from spell text and TDF rogue.

## 1. Scope

**Specs.** Combat (the default), Assassination, Subtlety, as three packs on one Forever pseudo-spec, chosen with `/hekili priority <name>` (the Warrior/Druid model; `RegisterPackSelector` does not exist in this fork). Pseudo-spec ID: the
Druid used the unused placeholder 1499 until its Q1 read the client's ID; the Rogue takes the same route with `ROGUE_SPEC = 1500` (no `[1500]` row in `Constants.lua` today; Constants rows 259-261 are retail Rogue specs) [HK
Constants.lua:189-199, 247-254]. Stop rule as the Druid spec: if the client reports 1491, stop (rows are keyed by ID alone).

**What exists.** Hekili `origin/classic:Classic/Rogue.lua` (1378 lines) with two APL files only, `RogueCombat.simc` (8 lines) and `RogueAssassination.simc` (14 lines); no Subtlety. Its resource is a 20-per-tick energy model (to drop),
`spec:RegisterHook ("spend")` with `math.random` Relentless Strikes (to replace), a Classic `stealthed` state table and a `runHandler` stealth breaker (reusable), Slice and Dice duration `6 + 3*cp + 3*improved_slice_and_dice.rank` (wrong,
section 2.3), stale talent rank lists (Vile Poisons ends 16516/16517; the DB2 has 16719/16720), and `GetWeaponEnchantInfo()` (a global that Forever replaced). `archive/TheWarWithin/RogueOutlaw.lua` is the only other Rogue file. TDF rogue is
the Forever fact base; this brief reuses its numbers where DB2 confirms them and says so.

**Out of scope (not in any Forever guide).** Season of Discovery rune spells, present in the DB2 as class spells with base level 0: Saber Slash 424785 (45 energy), Main Gauche 424919/1289849 (15 energy), Quick Draw 398196, Between the Eyes
400009, Blade Dance 400012, Poisoned Knife 425012, Shiv 424799 (20), Shadowstrike 399985 (20), Shuriken Toss 399986 (30), Redirect 438040, Envenom 399968, Tease 410412/1219355, the `Engrave *` spells, and the S03 set bonuses
(1213713-1226956) [DB2 spell_info]. Poison creation spells ("Poisons" skill line), Pick Pocket 921, Pick Lock, Detect/Disarm Trap, Safe Fall, Distract, Blind, Sap, Feint, Evasion, Sprint are registered or ignored as section 2 says.


## 2. Resources and the ability kit

### 2.1 Energy
- **Max 100** [DB2/Classic]; the Vigor talent adds +10 in the DB2 (14983: aura 35, misc 3 = energy, base 10, single rank) while TDF rogue reports 2 ranks of +5/+10 on Forever (spell 1310708, effect 30 base 1; its description is empty). The
  Virtual layer takes a plain `UnitPowerMax` read as final ("a plain maximum read wins", Druid spec 2.4), so no `max` meta and no Vigor handling is needed if Q2's `UnitPowerMax(3)` is plain (it was plain for rage). Gnome Rogue: Expansive
  Mind 1259803 +5% max, already in `Races/Gnome.lua` [HK]. [DB2: `wowdb effects 14983`]
- **Regen: continuous, 10/s, no tick.** Drop Classic's `tick` table entirely and register bare `spec:RegisterResource( Enum.PowerType.Energy )` as the Druid does (Druid.lua:163): the out-of-combat plain regen read seeds the Virtual belief;
  the ladder calibrates it. No decay (energy rests at 100: `ns.ResourceRegenerates`). The Druid's Q3 shortcut applies verbatim: after a `/reload` in combat the rate stays 0 until a `regen` meta field exists.
- **Adrenaline Rush (13750)** is the one regen modifier: aura 110 (MOD_POWER_REGEN_PERCENT), misc 3 energy, base 100 => +100% (+10/s) for 15 s, 300 s cooldown, 25-free (cost 0), on the GCD (1000 ms) [DB2 `wowdb effects 13750`, spell_info].
  Model it as an aura-gated regen entry (the Adapter forwards entries with `{ aura, interval, value }`, Adapter.lua:121-135; the Warrior's `bloodrage` entry is the shape): `adrenaline_rush = { aura = "adrenaline_rush", last = <applied +
  floor(t - applied)>, interval = 1, value = 10 }`. Credited ticks stay out of the regen calibration (Resources.lua:271). Shared/Auras.lua stubs `adrenaline_rush = {}` (no id, never up); the Rogue file registers a real `adrenaline_rush`
  aura and **must be loaded so its registration wins over the shared stub** (check the merge order in Engine/Shared.lua when specing).
- **Relentless Strikes** (14179, one rank in the DB2): "20% per combo point to restore 25 energy" (effect 14181 = 25) [DB2]. A 5-point finisher refunds 25 for certain; below 5 it is a 20% x cp chance. Model only the certain part in
  `now`/`handler` (`if combo_points.current >= 5 and talent.relentless_strikes.enabled then gain( 25, "energy" )`); do **not** port Classic's `math.random` hook (a random value in a recommendation path flickers the display and allocates
  nothing but is non-reproducible). Other finisher refunds exist in the DB2 but are of unknown source: Fallen Regality 1231492 (aura 109 chance per CP, restores 1231491 energy), Restless Blades 1241797 (finishers cut Adrenaline Rush/Blade
  Flurry/Evasion/Sprint/Vanish cooldowns by `$m1` sec per CP): neither is in a Forever guide; treat as absent until Q1's export lists them.
- **Usability ladder rungs** (energy is secret always, `C_Spell.IsSpellUsable` is plain; cost identical across ranks) [DB2 spell_info.cost]: Riposte 10 < Feint 20 < Slice and Dice = Rupture = Venom = Kick = Blade Flurry = Expose Armor =
  Kidney Shot 25 < Distract = Blind 30 < Eviscerate = Hemorrhage 35 < Ghostly Strike 40 < Sinister Strike = Gouge 45 < Garrote 50 < Backstab = Ambush = Cheap Shot = Mutilate 60 < Sap 65. Rich ladder: every rung is a pin, so calibration
  should converge in seconds. **Caveat (R1):** a rung pins energy only when the ability is unusable *for lack of energy*. Finishers carry a second power cost (SpellPower row `OrderIndex 1`, `PowerType 4` = combo points, `ManaCost 1`) on
  Eviscerate, Slice and Dice, Rupture, Venom, Expose Armor, Kidney Shot (and runes Between the Eyes, Blade Dance) [DB2 `SpellPower`]: at 0 combo points `IsSpellUsable` returns false with `insufficientPower`-or-not unspecified, the same trap
  as the Warrior's Overpower. Stealth openers (Ambush, Garrote, Cheap Shot) out of stealth and Riposte unlit are unusable for non-power reasons. Q4 records both flags.
- **Energy cost modifiers** (all `aura 107 misc 14` flat cost mods, so `spend` functions, not `RegisterCostMod`, unless the Q shows they are family-masked like Clearcasting): Improved Sinister Strike 13732 -5 (rank 2: -2 more, TDF: 45 ->
  42/40); Flawless Execution 1310711 -10 on Eviscerate (35 -> 25); Thousand Cuts buff 1310723 -3 per stack on Hemorrhage/Backstab, 5 stacks, 10 s (cumulative, from Rupture ticks via 1310721); Improved Expose Armor 14168 -5/-10; Dirty Deeds
  14082 -$m1 on Cheap Shot/Garrote; Dirty Tricks 1224782 aura 108 -50% on Sap/Blind; Tier 1 5-piece 1301708 -5 on Eviscerate (and rune Envenom); Eureka! 1259812 (Gnome race pack already covers `ROGUE = { 8676, 53, 2098, 14278, 1776, 16511,
  1766, 1310707, 14251, 1752 }`). Rank 2+ values are rank-1 value x rank (Warrior convention), floored at 0, checked by Q7.

### 2.2 Combo points
- `spec:RegisterResource( Enum.PowerType.ComboPoints )` as Classic and Druid. Max 5. Plain 0-5 via `GetComboPoints("player", "target")` [P]; per-target in the API but **Forever keeps points on a target swap** (they clear only when you build
  on a different enemy) and a missed Expose Armor no longer loses them [TDF rogue 1, Blizzard 2026-10-01]. The belief's single player-level count is therefore correct between target swaps and wrong right after a swap onto a *new* target
  plus a builder.
- Generation per cast [DB2 effect 30 with misc0 = 4, base = points]: Sinister Strike 1, Backstab 1, Hemorrhage 1, Ghostly Strike 1, Ambush 1, Garrote 1, Gouge 1, **Cheap Shot 2, Mutilate 2** (one effect for both hands), **Premeditation +2**
  (20 s timer, 14183: effect 30 base 2 plus aura 560 base 2). Finishers (Eviscerate, Rupture, Slice and Dice, Venom, Expose Armor, Kidney Shot) spend all. Stochastic: Seal Fate 14186 (crit, 20% x rank), Ruthlessness 14156 (finisher, aura 42
  = proc trigger 14157; 20% per rank on the Classic tooltip), Puncturing Wounds 1224716 (Backstab +45% chance of +1 point, aura 42 -> 1310710), Initiative 13976 (opener), Setup 13983 (after a dodge).
  Per the Druid pattern `now` writes **no** combo points (a poll corrects the belief); the sim `handler` keeps `gain( n, "combo_points" )` and `spend( combo_points. current, "combo_points" )` as Classic does.
- Cutthroat 424980 (talent) teaches the aura-336 trigger 462708 ("Backstab 3-15% chance to make your next Ambush within 10 s not need Stealth"), buff 462707 (10 s, 1 charge, aura 275 "ignore stealth req") [DB2].

### 2.3 The ability table
Columns: key (Hekili Classic key), rank-1 ID + `copy` list (lowest first, levels), energy cost, cooldown (max of `RecoveryTime` and `CategoryRecoveryTime`), GCD [DB2 spell_info: `gcd_ms` 1000 for energy attacks, "off" where 0], requirement,
CP, notes. Everything is rank-independent for cost; ids are `copy = rest(IDS)` as the Warrior.

| Key | Rank-1 id; `copy` (base levels) | Cost | CD | GCD | Requires | CP | Notes |
|---|---|---|---|---|---|---|---|
| `sinister_strike` | 1752; 1757 1758 1759 1760 8621 11293 11294 (1,6,14,22,30,38,46,54) | 45 | - | 1 s | any weapon | +1 | -5/-2 Improved SS |
| `backstab` | 53; 2589 2590 2591 8721 11279 11280 11281 25300 (4,12,20,28,36,44,52,60,60) | 60 | - | 1 s | dagger MH, behind | +1 | 150% + flat; Thousand Cuts -3/stack |
| `eviscerate` | 2098; 6760 6761 6762 8623 8624 11299 11300 31016 (1,8,16,24,32,40,48,56,60) | 35 | - | 1 s | CP >= 1 | spend all | Flawless -10; r9: 108 + 170/CP |
| `slice_and_dice` | 5171 (10, +20% haste); 6774 (42, +30%) | 25 | - | 1 s | CP >= 1 | spend all | duration below |
| `rupture` | 1943; 8639 8640 11273 11274 11275 (20,28,36,44,52,60) | 25 | - | 1 s | CP >= 1 | spend all | 6 + 2/CP s, tick 2 s (DB2 duration 6000..16000, per-resource 2000) |
| `hemorrhage` | 16511 (30, talent) | 35 | - | 1 s | any | +1 | 15 s debuff, +15% Rupture damage (aura 271); 100% / 145% dagger |
| `mutilate` | 1310707 (30); 399956 (40); 1241582 (50); 1241584 (60) | 60 | - | 1 s | two daggers | +2 | talent; +20% vs poisoned; triggers 1310706/1310705 per hand |
| `venom` | 1310703 (40, talent) | 25 | - | 1 s | CP >= 1 | spend all | self buff 6 + 3/CP s: poison dmg +30%, chance +10% (auras 108, 107) |
| `expose_armor` | 8647; 8649 8650 11197 11198 (14,26,36,46,56) | 25 | - | 1 s | CP >= 1 | spend all | 30 s |
| `kidney_shot` | 408 (30); 8643 (50) | 25 | 20 s cat. | 1 s | CP >= 1 | spend all | stun 0..5 s r1, 1..6 s r2 (1 s per CP) |
| `kick` | 1766; 1767 1768 1769 (12,26,42,58) | 25 | 10 s cat. | 1 s | in range | - | interrupt, 5 s lockout; silenced debuff 18425 (2 s) |
| `gouge` | 1776; 1777 8629 11285 11286 (6,18,32,46,60) | 45 | 10 s cat. | 1 s | target faces you | +1 | 4 s |
| `ghostly_strike` | 14278 (talent) | 40 | 20 s | 1 s | any | +1 | 125% / 180% dagger; dodge +15% 7 s |
| `ambush` | 8676; 8724 8725 11267 11268 11269 (18,26,34,42,50,58) | 60 | - | 1 s | stealth (or Cutthroat 462707), dagger, behind | +1 | 250%-class |
| `garrote` | 703; 8631 8632 8633 11289 11290 (14,22,30,38,46,54) | 50 | - | 1 s | stealth, behind (Dirty Deeds waives) | +1 | 18 s bleed, tick 3 s |
| `cheap_shot` | 1833 (26) | 60 | - | 1 s | stealth | +2 | stun 4 s |
| `riposte` | 14251 (talent) | 10 | 6 s | off (cat. 1 s) | lit after a parry (usability gate) | - | 150%, disarm |
| `feint` | 1966; 6768 8637 11303 25302 (16,28,40,52,60) | 20 | 10 s cat. | 1 s | - | - | threat |
| `blade_flurry` | 13877 (talent) | 25 | 120 s | 1 s | - | - | aura 319 base 20: +20% melee haste, +1 target, 15 s |
| `adrenaline_rush` | 13750 (talent) | 0 | 300 s | 1 s | - | - | +100% regen 15 s (2.1) |
| `cold_blood` | 14177 (talent) | 0 | 180 s | off | - | - | aura 107 misc 7 +100% crit, 1 charge; next SS, Backstab, Ambush, Eviscerate, Mutilate |
| `premeditation` | 14183 (talent, level 20) | 0 | 120 s | off | - | +2 | 20 s |
| `preparation` | 14185 (talent) | 0 | 600 s | 1 s | - | - | finishes cooldowns of the other Rogue abilities (effect 3 dummy) |
| `evasion` | 5277 (8) | 0 | 300 s | off | - | - | 15 s dodge |
| `sprint` | 2983; 8696 11305 (10,34,58) | 0 | 300 s | off | - | - | 15 s; does not break stealth |
| `vanish` | 1856 (22); 1857 (42); 1285372 (42, "Rank 3") | 0 | 300 s | off | - | - | buff 11327 / 11329, 10 s; see 4 |
| `stealth` | 1784; 1785 1786 1787 (1,20,40,60) | 0 | 10 s cat. | off | out of combat | - | until cancelled; see 4 |
| `distract` | 1725 (22) | 30 | 30 s cat. | **1.5 s** | - | - | 10 s |
| `sap` | 6770 (10); 2070 (28); 11297 (48) | 65 | - | 1 s | out of combat humanoid | - | 35/25/45 s per rank as listed by DB2 |
| `blind` | 2094 (34) | 30 | 300 s | 1 s | - | - | 10 s |

Not registered: Kidney/Garrote variants, Pick Pocket, Pick Lock, traps. Notes:
- **GCD is 1.0 s for every energy ability, fixed, unhasted** (`StartRecoveryTime` 1000, category 133); Hekili's `gcd = "totem"` is the fixed 1 s GCD the Druid cat abilities already use (Druid R 2.1). Distract is 1.5 s (`gcd = "spell"`).
  Cold Blood, Evasion, Sprint, Vanish, Stealth, Premeditation, Riposte are `gcd = "off"`.
- **Slice and Dice duration = (6 + 3 x cp) x (1 + 0.15 x Improved Slice and Dice rank)** seconds [DB2 duration 6000..21000, per- resource 3000; 14165 aura 108 base 15; description "9 x mult s at 1 point"]: 9/12/15/18/21 s base, 13.05..30.45
  s at 3/3. Classic's `+ 3 * rank` is wrong. Aura id 5171 with `copy = { 6774 }`; haste 20% (5171) vs 30% (6774, level 42) is only a note.
- **Rupture** = 6 + 2 x cp s; **Venom** = 6 + 3 x cp s; **Kidney Shot** stun = 1 s per CP. Duration functions read `combo_points.current` at the cast, so they live in `now`/`handler` (`applyBuff( "slice_and_dice", duration )`), as the
  Warrior passes its talent-modified durations.
- The `now`/`handler` pairs the belief needs (facade spec 12a; the layer pays cost and cooldown/GCD itself): every finisher applies its aura and spends combo points in `handler` only; Slice and Dice, Venom, Adrenaline Rush, Blade Flurry,
  Cold Blood (1 charge, removed by the next listed attack's `now`), Premeditation, Hemorrhage (debuff 15 s), Rupture, Expose Armor, Ghostly Strike, Stealth/Vanish (`applyBuff( "stealth" )`; section 4) and every opener (`removeBuff(
  "stealth" )`). Adrenaline Rush has no energy gain (its regen rides the resource entry). Relentless's certain 25 at 5 CP goes in the finishers' `now` as `gain( 25, "energy" )` guarded by the talent and `combo_points.current >= 5`.

## 3. Talents

`wowdb talents ROGUE` [DB2 `talent_info`, columns tab, tier, col; r1..r5 are the rank spell IDs; `prereq`]. **This is the Classic/TBC tree.** Keys are Classic's snake_case (Classic/Rogue.lua:37-77); the Warrior's registration shape `{ 0,
definitionSpell, maxRank }` is the target (only the live export fixes max ranks and the node list, Q1). Forever-only entries are flagged **[F]** (spell ID >= 1,000,000 or a rename); their tree position is unknown.

**Assassination** (tier,col: key = rank-1 spell, DB2 ranks) 0,0 `improved_eviscerate` 14162 (3); 0,1 `remorseless_attacks` 14144 (2); 0,2 `malice` 14138 (5); 1,0 `ruthlessness` 14156 (3); 1,1 `murder` 14158 (2); 1,3
`improved_slice_and_dice` 14165 (3); 2,0 `relentless_strikes` 14179 (1); 2,1 `improved_expose_armor` 14168 (2); 2,2 `lethality` 14128 (5, needs Malice 4); 3,1 `vile_poisons` 16513 (5; ranks 16513 16514 16515 16719 16720); 3,2
`improved_poisons` 14113 (5); 4,1 `cold_blood` 14177 (1); 4,2 `improved_kidney_shot` 14174 (3); 5,1 `seal_fate` 14186 (5, needs Cold Blood); 6,1 `vigor` 14983 (1 in the DB2). **[F]**: `mutilate` 1310707 (21-point row; rank IDs in the
table); `venom` 1310703 (31 points); `coup_de_grace` 1310709 (aura 107 +2% Eviscerate damage per Deadly Poison stack, level 30); `vigor` 1310708 (Forever's 2- rank version, same name).

**Combat** 0,0 `improved_gouge` 13741 (3); 0,1 `improved_sinister_strike` 13732 (2); 0,2 `lightning_reflexes` 13712 (5); 1,0 *unnamed row* 13733 (3, Improved Backstab: spell has no name, replaced by [F] `puncturing_wounds` 1224716); 1,1
`deflection` 13713 (5); 1,2 `precision` 13705 (5); 2,0 `endurance` 13742 (2); 2,1 `riposte` 14251 (1, needs Deflection 4); 2,3 `improved_sprint` 13743 (2); 3,0 `improved_kick` 13754 (2); 3,1 *"Hack and Slash"* 13706 (5; description:
dagger/fist crit, i.e. the old Dagger Specialization renamed); 3,2 `dual_wield_specialization` 13715 (5, needs Precision 4); 4,0 *"Hack and Slash"* 13709 (5; description: mace ignores armor); 4,1 `blade_flurry` 13877 (1); 4,2
`hack_and_slash` 13960 (5; "Axe/Sword: chance for an extra attack", effect 4 base 5/15/5 = the merged Forever talent [F]); 4,3 `fist_weapon_specialization` 13707 (5, stale); 5,1 `weapon_expertise` 30919 (2; TBC row, kept); 5,2 `aggression`
18427 (3); 6,1 `adrenaline_rush` 13750 (1). **[F]**: `flawless_execution` 1310711 (aura 107 misc 14 base -10 on Eviscerate); `puncturing_wounds` 1224716 (Backstab crit +30 [effect 0], +45% add-a-point chance [effect 1 -> 1310710], Mutilate
crit +15).

**Subtlety** 0,1 `master_of_deception` 13958 (5); 0,2 `opportunity` 14057 (5); 1,0 `sleight_of_hand` 30892 (2, stale TBC row; TDF says removed); 1,1 `elusiveness` 13981 (2); 1,2 `camouflage` 13975 (5); 2,0 `initiative` 13976 (3); 2,1
`ghostly_strike` 14278 (1); 2,2 `improved_ambush` 14079 (3); 3,0 `setup` 13983 (3); 3,1 `improved_sap` 14076 (3, becomes [F] `dirty_tricks` 1224782: Sap/Blind -50% energy); 3,2 `serrated_blades` 14171 (3); 4,0 `heightened_senses` 30894 (2,
TBC row); 4,1 `preparation` 14185 (1); 4,2 `dirty_deeds` 14082 (2); 4,3 `hemorrhage` 16511 (1, needs Serrated Blades 2); 5,2 `deadliness` 30902 (5, stale TBC row); 6,1 `premeditation` 14183 (1, needs Preparation). **[F]**: `thousand_cuts`
1310721 (+ buff 1310723); `quietus` 1310728 (auras 4: Sinister Strike/Ghostly/Hemorrhage +10% below 35% health); `cutthroat` 424980 / 1241810 (+ aura 462707, trigger 462708); `restless_blades` 1241797 and `fallen_regality` 1231492 (source
unknown, see 2.1); Coup de Grace is listed under Assassination.

The Forever tree also drops the vanilla weapon specializations for Hack and Slash and adds Weaponmaster-like effects only on the Warrior; for the Rogue nothing else new was found with a class-set 8 query for IDs >= 1,000,000 [DB2:
`spell_info where class_set=8 and id>=1000000`]. The seven S03 / Tier-1 / Naxxramas spells in that set are items, not talents (Tier 1: 1300956 +hit, 1301047 Kidney Shot cooldown, 1301088 AP vs humanoids, 1301708 -5 energy Eviscerate; the
Tier 1 set IDs are for `Items.lua`, not this file). Settings stand in for `talent.*` reads where the talent affects the rotation (TDF rogue 2: Improved Slice and Dice rank, Flawless Execution, Vigor, Relentless Strikes, Thousand Cuts); the
Warrior's `state.talent.x.rank` from the trait walk is preferred once Q1 lands.

## 4. Stealth, openers, Vanish and detectability

- **Stealth 1784** is a shapeshift-form aura (effect aura 36 misc 30 = stealth form), plus aura 16 (mod stealth level, base 5) and aura 33 (speed, base -50): 50% slower, Camouflage reduces it. Forever also carries variant IDs 1256867 (aura
  36, speed -20%), 1287162, 1290708, 1318151 (silent shells); register the aura as `id = 1784, copy = { 1785, 1786, 1787, 1256867 }` and decide on the probe (Q5). Cooldown 10 s (category), no GCD, out of combat only.
- **Vanish 1856** (r1, L22) triggers buff 11327 (aura 16 base 170, 10 s) and purge 18461; r2 1857 and the odd duplicate "Rank 3" 1285372 (L42; its extra aura 16 base 50 and "more effective than Rank 2") trigger 11329 (aura 16 base 270). 300
  s cooldown, off GCD; Elusiveness 13981 reduces it. Treat 11327/11329 as a second stealth aura: `vanish = { id = 11327, copy = { 11329 } }`, duration 10, and `stealthed.all` covers both (Classic's state table, Rogue.lua:301-316).
- **Detectability (the open item).** `IsStealthed()` is a plain bool in the Forever API index [wow_api_search]; the player aura walk reads Stealth/Vanish out of combat, secret in combat. A stealth opener starts out of combat, so the aura
  walk suffices to seed `buff.stealth`; a Vanish *in* combat is the only secret case, and our own cast (`now`) sets the belief. Reconcile: Q5 prints `IsStealthed()` and the aura read in and out of combat; if the bool is plain, a
  `reset_precast` hook sets/removes the aura from it (the Warrior's stance-map pattern); and Q6 checks whether `GetShapeshiftForm()` (plain in the facade inventory) reports the stealth form for a Rogue, a free plain signal.
- **Openers and usability.** Ambush/Garrote/Cheap Shot are usable only in stealth, so `C_Spell.IsSpellUsable` is also a stealth signal, but Ambush additionally needs a dagger and to be behind (an error, not a usability flip). Pattern from
  Druid Shred: a "not behind" window from `UI_ERROR_MESSAGE` (plain; Druid Q11 records the id) or a `settings.behind` proxy. Garrote requires behind unless Dirty Deeds 2/2; Cheap Shot needs neither. Cutthroat's 462707 buff removes the
  stealth need for one Ambush.
- **Breaking stealth.** Classic's `runHandler` hook (`startsCombat` abilities remove `stealth`/`vanish` and put Stealth on a 10 s cooldown) is reusable. Forever: Sap no longer breaks stealth; Distract and Sprint do not; Premeditation is not
  documented to [TDF rogue 1; DB2 Sprint text]. Set `startsCombat = false` on those.
- **Precombat:** `actions.precombat=stealth,if=!buff.stealth.up` for Assassination/Subtlety (a pre-pull action out of combat); Combat has none (Hekili's Classic Combat list has none). Poison reminders are not recommendations (section 5).

## 5. Poisons (weapon enchants)

- Poisons are consumables applied to a weapon (items: Instant 6947 6949 6950 8926 8927 8928, Deadly 2892 2893 8984 8985 20844, Crippling, Mind-numbing, Wound 10918..10922, Occult 226374/234444 [DB2 ItemSparse]); the Forever bonus is more
  charges (TDF), and a class quest at 20 teaches them. The "Poisons" skill-line spells (Instant Poison 8681.., Deadly Poison 2835..25347, Crippling 3420, Wound 13220..13230, Occult 458822/1214168) are *creation* spells, not applications: do
  not register them.
- **Target debuffs** (unreadable in combat): Deadly Poison 2818 (r1) .. 25349 (r5): 12 s, 5 stacks, tick 3 s [DB2 spell_info]; the Coup de Grace, Mutilate (+20% vs poisoned) and Venom bonuses hang on them. Instant Poison leaves no debuff.
  Model Deadly's stacks as "assumed present", as TDF rogue does; do not track them.
- **The player's own enchants.** `C_Item.GetWeaponEnchantInfo(weaponSlot)` is present on Forever, returns `table<WeaponEnchantInfo>` (Classic's multi-return global is gone), `secretArguments = AllowedWhenUntainted`; secrecy of the result is
  **unknown** and the function is not in `tools/api_inventory.txt`, so the facade has no entry (Hekili's Classic file would call the nil global). A "poison missing" reminder (`buff.mh_poison.up`) needs a facade `passthrough` row plus Q9;
  until then the pack ignores poisons.
- Mutilate's "+20% against poisoned" and Coup de Grace are damage-only: no `usable` gate, no priority change.

## 6. Draft priorities (SimC style, tools/packs/rogue.lua)

Convention: `tools/packs/<class>.lua` returns `{ date, spec, packs = { { name, desc, simc } } }`; strings are compiled by `lua5.1 tools/make_pack.lua rogue` (the `date` is the pack date, `spec` the pseudo-spec). `settings.<name>` reads a
`spec:RegisterSetting`; `boss`, `active_enemies`, `combo_points.current`, `energy.current`, `buff/debuff/dot.x.remains/up/stack`, `cooldown.x.remains`, `action.x.cost` are core names. Abilities with a `toggle` field (Adrenaline Rush, Blade
Flurry, Cold Blood, Premeditation, Preparation -> `cooldowns`) need no `toggle.` in the line. Settings used (defaults): `boss` is core; `refresh_window` 3 (1-6), `early_refresh` 6 (0-10), `venom` true, `backstab` false (dagger main hand and
behind), `bf_single` true, `min_cp` 5 (3-5), `rupture` true (Sub, long fights), `kick` false (needs `target.casting`, unavailable: left commented). Stateless guards: every line is a function of the believed state alone (APL stateless-guards
rule). The `excess_e` reservation is **not** in the first version (TDF rogue 6 asks for it for Slice and Dice/Venom/Rupture); the Druid `excess_e` (Druid.lua:1715) is the template if playtests show a builder starving a refresh.

```
-- Combat (default): Slice and Dice always, Sinister Strike builder, Eviscerate at the cap, Adrenaline Rush + Blade Flurry on cd.
actions.precombat=
actions=slice_and_dice,if=!buff.slice_and_dice.up&combo_points.current>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=settings.refresh_window&combo_points.current>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=1.5&combo_points.current>=1
actions+=/slice_and_dice,if=combo_points.current>=5&buff.slice_and_dice.remains<=settings.early_refresh
actions+=/adrenaline_rush,if=buff.slice_and_dice.up&energy.current<50
actions+=/blade_flurry,if=buff.slice_and_dice.up&(settings.bf_single|active_enemies>1)
actions+=/riposte
actions+=/eviscerate,if=combo_points.current>=settings.min_cp
actions+=/backstab,if=settings.backstab&combo_points.current<5
actions+=/sinister_strike,if=combo_points.current<5
```
```
-- Assassination (Mutilate daggers; falls back to Sinister Strike without Mutilate; Venom from level 40):
actions.precombat=stealth,if=!buff.stealth.up
actions=ambush,if=buff.stealth.up&settings.backstab
actions+=/cheap_shot,if=buff.stealth.up
actions+=/cold_blood,if=buff.slice_and_dice.up&!buff.cold_blood.up&combo_points.current<=2
actions+=/slice_and_dice,if=!buff.slice_and_dice.up&combo_points.current>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=settings.refresh_window&combo_points.current>=2
actions+=/slice_and_dice,if=combo_points.current>=5&buff.slice_and_dice.remains<=settings.early_refresh
actions+=/venom,if=settings.venom&!buff.venom.up&combo_points.current>=3&buff.slice_and_dice.up
actions+=/venom,if=settings.venom&buff.venom.remains<=settings.refresh_window&combo_points.current>=4
actions+=/venom,if=settings.venom&combo_points.current>=5&buff.venom.remains<=settings.early_refresh
actions+=/eviscerate,if=combo_points.current>=settings.min_cp&buff.slice_and_dice.remains>settings.early_refresh&(!settings.venom|buff.venom.remains>settings.early_refresh)
actions+=/sinister_strike,if=combo_points.current=4
actions+=/mutilate,if=combo_points.current<=3
actions+=/sinister_strike,if=combo_points.current<5
```
```
-- Subtlety (Hemorrhage debuff, Rupture on long fights, Eviscerate otherwise; Backstab only with settings.backstab):
actions.precombat=stealth,if=!buff.stealth.up
actions=premeditation,if=combo_points.current<=2
actions+=/ambush,if=(buff.stealth.up|buff.cutthroat.up)&settings.backstab
actions+=/cheap_shot,if=buff.stealth.up
actions+=/slice_and_dice,if=!buff.slice_and_dice.up&combo_points.current>=2
actions+=/slice_and_dice,if=buff.slice_and_dice.remains<=settings.refresh_window&combo_points.current>=2
actions+=/slice_and_dice,if=combo_points.current>=5&buff.slice_and_dice.remains<=settings.early_refresh
actions+=/hemorrhage,if=!debuff.hemorrhage.up|debuff.hemorrhage.remains<=settings.refresh_window
actions+=/rupture,if=settings.rupture&boss&combo_points.current>=5&!debuff.rupture.up
actions+=/eviscerate,if=combo_points.current>=settings.min_cp&buff.slice_and_dice.remains>settings.early_refresh&(!settings.rupture|!boss|debuff.rupture.up)
actions+=/ghostly_strike,if=combo_points.current<=4
actions+=/backstab,if=settings.backstab&combo_points.current<5
actions+=/hemorrhage,if=combo_points.current<5
```
Sources for these shapes: Hekili Classic lists (`Classic/APLs/RogueCombat.simc`: SnD at 2 CP or 5 CP with under 3 s, Blade Flurry/ Adrenaline Rush, Sinister Strike until 5 CP then Eviscerate; `RogueAssassination.simc`: Ambush if stealthed,
Backstab, SnD), refined by TDF rogue 3 (four+ Forever guides: wowtbc.gg, Mmonster, Leprestore, foreverdb builds). Left out on purpose: Expose Armor (coexists with Sunder on Forever, `families.json` fix needed first), Kick (needs
`target.casting`), Evasion/Sprint/Vanish/ Feint/Gouge/Sap/Blind (no health read), Preparation, Garrote, `kidney_shot`, the poison lines. Confidence: Combat high (loop), Assassination medium (Venom value disputed), Subtlety low-medium.
`buff.cutthroat` needs the aura registered (462707) and Premeditation uses the `cooldowns` toggle, so with it off the line is skipped.

## 7. Open questions for the in-game checkpoint

Each is one `/run` through ForeverProbe's `VSCopy(` (`~/src/ForeverProbe/Copy.lua`; `/vscopy` reopens the box); every line is under 255 characters. Run on a Rogue. Ranked by importance.

| # | Question | Line | Answer -> action |
|---|---|---|---|
| Q1 | Live talent tree, the pseudo-spec ID, Forever-only nodes | `/fprobe export`, `/reload`, then `/run local e=ForeverProbeDB.export;VSCopy(e.meta.class,#e.spells,#e.talents.trees,e.stances.num)` and `/run VSCopy(GetSpecialization(),GetSpecializationInfo(1))` | node list -> `RegisterTalents`; ID -> `ROGUE_SPEC` and the Constants row |
| Q2 | Energy regen, max (Vigor), rate under Adrenaline Rush | OOC `/run VSCopy(GetTime(),UnitPowerMax("player",3),GetPowerRegenForPowerType(3))`, again under Adrenaline Rush and with Vigor | 10/s flat -> bare resource; max plain -> no `max` meta; AR rate -> the regen entry value |
| Q3 | Combo points: `UnitPower(4)` plain in combat? kept on target swap, on kill, after a missed finisher | at 3 points in combat `/run VSCopy(GetComboPoints("player","target"),UnitPower("player",4))`; repeat after `/targetlasttarget`, after the target dies, after a dodged Eviscerate | which API the Power source polls (R3); miss/swap handling |
| Q4 | Usability flags at the ladder edges: finisher at 0 CP, Ambush unstealthed, Mutilate without daggers, Riposte unlit | `/run for _,i in ipairs({2098,5171,1943,8676,1310707,14251}) do local u,n=C_Spell.IsSpellUsable(i) VSCopy(i,u,n) end` at 0 CP, 100 energy, out of stealth | `(false,true)` vs `(false,false)` decides which abilities may pin the ladder (R1) |
| Q5 | Stealth state: `IsStealthed()`, aura read, aura ID, in and out of combat; form index | in stealth `/run VSCopy(IsStealthed(),GetShapeshiftForm(),GetNumShapeshiftForms(),pcall(C_UnitAuras.GetPlayerAuraBySpellID,1784))`; repeat after Vanish in combat | plain bool -> `reset_precast` stealth sync; which ID (1784 vs 1256867) |
| Q6 | Player auras in combat: Slice and Dice, Adrenaline Rush, Blade Flurry readable? duration secret? | in combat with each up `/run for _,i in ipairs({5171,6774,13750,13877,1310703}) do VSCopy(i,pcall(C_UnitAuras.GetPlayerAuraBySpellID,i)) end` | secret -> track from casts (`now`) only; plain -> aura walk |
| Q7 | Costs with talents and the Slice and Dice remainder | `/run for _,i in ipairs({1752,2098,53,1310707,16511,5171,1943,8647}) do local c=C_Spell.GetSpellPowerCost(i) c=c and c[1] VSCopy(i,c and c.type,c and c.minCost) end` | compare with `Snapshot` `cost=`/`read=`: Improved SS, Flawless, Thousand Cuts per-rank rule |
| Q8 | Slice and Dice recast semantics and haste: replaced, extended or refused; attack speed change | `/run VSCopy(UnitAttackSpeed("player"))` before, with SnD up, after a lower-point recast | replace -> `applyBuff` resets; `UnitAttackSpeed` plain -> exact SnD uptime signal |
| Q9 | Weapon enchants: shape and secrecy | `/run local e=C_Item.GetWeaponEnchantInfo(16) VSCopy(type(e),e and e.hasEnchant,e and e.expiration,e and e.charges)` (slots 16/17) | plain -> add a facade passthrough and a poison reminder; secret -> none |
| Q10 | Relentless Strikes: is the 25 energy refund at 5 CP visible | after a 5-point Slice and Dice at 20 energy: `/run VSCopy(C_Spell.IsSpellUsable(1752),C_Spell.IsSpellUsable(2098))` | refund certain -> keep `gain( 25 )`; else drop it |
| Q11 | "Must be behind" error id (Druid Q11) | press Backstab from the front with a `UI_ERROR_MESSAGE` frame: `/run local f=CreateFrame("Frame") f:RegisterEvent("UI_ERROR_MESSAGE") f:SetScript("OnEvent",function(_,e,a,b) VSCopy(a,b) end)` | fills the not-behind window; Backstab/Ambush/Garrote gate |
| Q12 | Which spells exist at the cap: Mutilate, Venom, Premeditation, runes | `/run VSCopy(IsSpellKnown(1310707),IsSpellKnown(1310703),IsSpellKnown(14183),IsSpellKnown(424785),IsSpellKnown(399968),IsSpellKnown(1285372))` | `known` gates; confirms runes unavailable; the third Vanish |
| Q13 | Kick and the target cast read | in range of a caster `/run VSCopy(UnitCastingInfo("target"),C_Spell.IsSpellUsable(1766))` | `kick,if=target.casting` or a manual toggle |

## 8. Risks and what the engine lacks for Rogues

- **R1 Ladder pins from finishers and stealth openers.** Each finisher has a second power cost (combo points) and the stealth attacks a non-power requirement; if `IsSpellUsable` reports `insufficientPower` for those, the belief would pin
  energy to the wrong value. The Warrior hit the same case (Overpower) and the Druid R 2.2; the fix is per-ability: pin a rung only when its other requirements hold (Q4), or give finishers `usable = combo_points.current > 0` as the Druid
  does for Rip. Spec must say which.
- **R2 Adrenaline Rush as a regen modifier.** The engine has aura-gated *additive* regen entries only; +100% of the calibrated rate is expressed as `+10/s` (`value = 10`), so a Vigor-less rate other than 10 (Q2) makes the entry wrong by
  that delta. A `mult` field on the regen meta would be exact; not built. Hekili's own forecast also needs the entry, with the `adrenaline_rush` stub in Shared/Auras.lua overridden by the real aura.
- **R3 Combo points source.** The Virtual Power poll reads `UnitPower( "player", ComboPoints )` (Sources/Power.lua:100) and the facade lists `UnitPower` as `virtual`; there is **no `GetComboPoints` path** (not in `tools/api_inventory.txt`,
  grep: none). If Q3 shows `UnitPower(4)` secret in combat, the belief runs blind on combo points exactly where the Rogue needs them; add a `GetComboPoints("player","target")` passthrough to the poll (and to the Poll for the player) before
  the class file.
- **R4 No target-aura reads.** Rupture, Hemorrhage, Expose Armor, Deadly Poison stacks are target debuffs: all from `now` (cast + duration), reset on target swap (spec 20.3 per-target memory) and never confirmed in combat; a missed finisher
  is only detected by the combo point read staying put (Q3). Dodged/parried Eviscerate loses no points on Forever? [TDF: open].
- **R5 Stealth is state, not resource.** Stealth/Vanish/Cutthroat gates (`stealthed.all`, `buff.cutthroat`) depend on aura walks that are secret in combat; the sim breaks stealth on `startsCombat` (Classic hook) but a Vanish *cancelled* by
  the game is unseen.
- **R6 Weapon-type and positional requirements are unreadable.** Dagger-only Backstab/Mutilate/Ambush use `settings.backstab` (the gear scan `main_hand.size` is a size, not a type); "behind" from the error window. A Mutilate recommendation
  with a non-dagger off hand fails silently in game.
- **R7 No fight length.** `boss` and `time_to_die` cannot gate Rupture and Slice and Dice on short fights; settings.
- **R8 Stale data in Hekili's Classic Rogue file** (Vile Poisons ranks, `GetWeaponEnchantInfo`, `math.random` hook, Slice and Dice duration); port nothing without re-reading the DB2.
- **R9 Spell-ID duplicates.** Mutilate has three rows per hand-trigger (1310705/6, 399960/1, 1241585/6, 1241588/90) and Stealth has four silent variants; only the castable IDs go in `id`/`copy`.

## 9. Pack spec inputs (constants to copy)

```
File: src/Hekili/Forever/Classes/Rogue.lua; guard UnitClassBase("player") ~= "ROGUE"; ROGUE_SPEC = 1500 (placeholder until Q1)
Packs: Combat (default RegisterOptions{ package = "Combat" }), Assassination, Subtlety; tools/packs/rogue.lua, spec = ROGUE_SPEC
Resources: Energy (bare), ComboPoints (bare); Adrenaline Rush entry { aura="adrenaline_rush", interval=1, value=10 }
Energy: max 100, regen 10/s continuous (no tick), no decay, GCD 1.0 s (gcd="totem"), Distract 1.5 s, Cold Blood/Riposte/Evasion/Sprint/Vanish/Stealth/Premeditation off GCD
Energy costs: Riposte 10, Feint 20, SnD/Rupture/Venom/Kick/Blade Flurry/Expose/Kidney 25, Distract/Blind 30, Eviscerate/Hemorrhage 35,
  Ghostly 40, Sinister Strike/Gouge 45, Garrote 50, Backstab/Ambush/Cheap Shot/Mutilate 60, Sap 65
Cost mods: Improved Sinister Strike -5/rank cap 2 (13732), Flawless Execution -10 Eviscerate (1310711), Thousand Cuts -3 x stacks <=5 on Hemorrhage/Backstab (1310723),
  Improved Expose Armor -5/rank (14168), Dirty Deeds (14082), Dirty Tricks -50% (1224782), Tier 1 5pc -5 Eviscerate (1301708)
Combo points: SS/Backstab/Hemorrhage/Ghostly/Ambush/Garrote/Gouge +1; Cheap Shot/Mutilate +2; Premeditation +2 (20 s); finishers spend all (second cost row: PowerType 4 x1)
Relentless Strikes: 14179, +25 energy certain at 5 CP (14181)
Durations: SnD (6+3cp)*(1+0.15*ImprovedSnD) haste +20% 5171 / +30% 6774; Rupture 6+2cp (tick 2); Venom 6+3cp; Kidney 1 s/cp; Expose 30; Garrote 18 (tick 3); Cheap Shot 4; Gouge 4;
  Hemorrhage 15; Adrenaline Rush 15 (+100% regen, cd 300); Blade Flurry 15 (+20% haste, cd 120, 25 energy); Cold Blood cd 180 (1 charge, aura 14177);
  Premeditation cd 120, 20 s; Preparation cd 600; Ghostly 7 s cd 20; Riposte cd 6 (10 energy); Evasion/Sprint 15 s cd 300; Vanish 10 s cd 300 (11327, 11329); Stealth cd 10
Rank lists: SS {1752,1757,1758,1759,1760,8621,11293,11294}; Backstab {53,2589,2590,2591,8721,11279,11280,11281,25300}; Eviscerate {2098,6760,6761,6762,8623,8624,11299,11300,31016};
  SnD {5171,6774}; Rupture {1943,8639,8640,11273,11274,11275}; Mutilate {1310707,399956,1241582,1241584}; Venom {1310703}; Expose {8647,8649,8650,11197,11198};
  Kidney {408,8643}; Kick {1766,1767,1768,1769}; Gouge {1776,1777,8629,11285,11286}; Ambush {8676,8724,8725,11267,11268,11269}; Garrote {703,8631,8632,8633,11289,11290};
  Cheap Shot {1833}; Feint {1966,6768,8637,11303,25302}; Sprint {2983,8696,11305}; Stealth {1784,1785,1786,1787}; Vanish {1856,1857,1285372}; Sap {6770,2070,11297};
  Hemorrhage {16511}; Ghostly {14278}; Riposte {14251}; Blade Flurry {13877}; Adrenaline Rush {13750}; Cold Blood {14177}; Premeditation {14183}; Preparation {14185}; Evasion {5277}
Auras: stealth {1784,1785,1786,1787,1256867}, vanish {11327,11329}, slice_and_dice {5171,6774}, venom 1310703, adrenaline_rush 13750, blade_flurry 13877, cold_blood 14177,
  premeditation 14183, thousand_cuts 1310723, cutthroat 462707, remorseless 14143 (20 s), rupture/hemorrhage 16511/expose_armor (debuffs), deadly_poison 2818..25349 (12 s, 5 stacks)
Talents (Forever-only): mutilate 1310707, venom 1310703, coup_de_grace 1310709, flawless_execution 1310711, thousand_cuts 1310721, quietus 1310728, puncturing_wounds 1224716,
  dirty_tricks 1224782, cutthroat 424980, hack_and_slash 13960, vigor 1310708, restless_blades 1241797, fallen_regality 1231492
APIs to add to the facade: GetComboPoints, IsStealthed, C_Item.GetWeaponEnchantInfo (none are in tools/api_inventory.txt today)
Settings: refresh_window 3, early_refresh 6, venom true, backstab false, bf_single true, min_cp 5, rupture true
Toggles: cooldowns = Adrenaline Rush, Blade Flurry, Cold Blood, Premeditation, Preparation; interrupts = Kick; defensives = Evasion, Feint (never recommended)
Out of scope: runes (424785 399986 399985 424799 398196 400009 400012 425012 438040 399968), S03 sets, poisons creation, Pick Pocket, traps
```

Sources: Hekili `Forever/Classes/Warrior.lua`, `Druid.lua`, `Races/Gnome.lua`, `Shared/Auras.lua`, `Virtual/State/Adapter.lua`, `Virtual/State/Families/Resources.lua`, `Virtual/State/Sources/Power.lua`, `Engine/Races.lua`,
`tools/packs/{warrior,druid}.lua`, `docs/forever-facade-notes.md`, `docs/research/2026-10-15-forever-druid/research.md`, `docs/superpowers/specs/2026-10-15-forever-druid-pack.md`, `origin/classic:Classic/Rogue.lua` and its two Rogue
`.simc`; TDF rogue research; DB2 via `wowdb` (spell_info, effects, talents ROGUE, SpellPower, SpellDuration, ItemSparse) and `wow_api_search` (flavor forever) for `GetWeaponEnchantInfo`, `IsStealthed`, `GetComboPoints`. No web access was
needed.
