# Forever Protection Warrior: research brief (2026-10-16, corrected)

Read-only research for a Forever Protection priority and the two engine models behind it (rage from damage taken, threat/avoidance). Hekili `forever` branch at 939a64cc; Forever DB2 build 1.60.1.70338 (`wowdb`). Tags: [DB2] queried here; [EXP] the ForeverProbe export of the live client 1.60.1.70374 (2026-10-15, `~/.claude/jobs/080a308e/tmp/warrior/export/`, reconciled in `.../warrior/reconcile.md`); [MG#n] magey/forever-warrior issue n (fetched 2026-10-16); [HK] Hekili file; [TDF] `docs/research/tdf/2026-10-14-virtual-combat-log-events.md`; [AUD] `docs/research/2026-10-15-api-events-audit.md`; [DOC] the client's API docs (wow MCP, flavor forever); [WEB] community page (fetched); [I] inference. Facts only; no engine design.

**Correction pass (2026-10-16).** Every DB2 number below was re-queried with `wowdb spell`, `wowdb effects` and SQL on `SpellAuraOptions`, `SpellCooldowns`, `SpellCategories` and `talent_info`. Corrections are marked **(corr.)**; anything the DB2 or the export cannot settle is marked **unverified**. The main changes: (1) Improved Shield Block, Improved Taunt and Toughness are **not in the live tree** (the export's 52 nodes; reconcile.md "GONE" list), so they cannot be registered; (2) the "rank N" rows the first draft called "last rank" are **rank 1** rows (12297, 12298, 12299, 16538); (3) Bloodrage's aura gives **10** rage (10 ticks), not 9; (4) Victory Rush heals **10%**, not 15%; (5) Concussion Blow is **off the GCD** in the DB2; (6) Shield Block's two blocks are **aura proc charges** (`SpellAuraOptions.ProcCharges = 2`), not spell charges (no charge category); (7) Master of Defense's chance is **0** in its DB2 row (`$m1`), so the chance is unknown; its energize reads 50 (5 rage) today where the 2026-10-15 reconcile read 20 (2 rage).

## 0. Read first
- **The DB2 `Talent` table is the vanilla/TBC tree**, with some nodes blank-named (Iron Will 141, Defiance 144); Forever-only talents exist only as spell IDs >= 1,000,000 with no tree position. The 18 Protection nodes the Warrior file lists come from the export ([HK] Warrior.lua:330-352), not the DB2. DB2 rank tables list rank IDs that mostly have no `Spell`/`SpellEffect` row beyond rank 1 (or, for Defiance, beyond the last), so **per-rank values are only known where a row exists** (section 1).
- **(corr.)** The live tree has no Toughness (12299), Improved Shield Block (12945) or Improved Taunt (12302): the export lists no node for them ([EXP] reconcile.md:126, the "GONE" list of ten), and the 2026-10-15 accuracy plan deleted their readers (ruling A1). Defiance's live node is max rank **3**, defined by 12792 ([EXP] talents.txt:50), against 5 rank IDs in the DB2 talent row 144.
- magey's repo (README, 7 open issues: 1 attack table, 2 off-hand+HS/Cleave, 3 rage normalization, 4 Unbridled Wrath, 12 Flurry, 24 Armor, 28 Extra attacks) has **nothing on threat, Revenge, Shield Block or Protection talents**, and no compendium link. Everything below on those is DB2, [EXP], [HK], [TDF] or community pages.
- Icy Veins and Mobalytics Forever pages returned 403; priorities in section 5 come from wow.gg, mmonster's rotation trainer and a wowforever.games / Mobalytics search snippet. No page documents Devastate; Level 60 numbers are theorycraft (beta cap 30).

## 1. Protection talents on Forever

Columns: talent, ranks (live max from [EXP]), DB2 effect (the row that exists), what it does, Warrior.lua reader.

| Talent | Ranks | DB2 | Effect on rage / threat / cd / procs | Reader in Warrior.lua |
|---|---|---|---|---|
| Shield Specialization 12298 | 5 (talent 1601: 12298, 12724-12727; only 12298 has rows) | **(corr.) rank-1 row**: e0 aura 51 (block chance) base 5; e1 aura 42 (proc trigger) base 100 -> 1310318 (energize rage, base 50 = 5 rage); `SpellAuraOptions` ProcChance 100, ProcTypeMask 680 | +5% block at rank 1 and "a $m2% chance to generate 5 Rage when you Block": m2 = **100 at rank 1** (description of 12298). Ranks 2-5: **unverified** (no rows) | talent `shield_specialization` (max 5) registered, **no effect modelled** |
| Anticipation 12297 | 5 | **(corr.) rank-1 row**: aura 30 (skill), misc 95 (Defense), base 20 | +Defense skill; 20 at rank 1 looks retuned (vanilla +2); **unverified** | registered, unmodelled |
| Improved Bloodrage 12301 | 2 | rank-1 row: aura 108 (pct) misc 8 base 50 | the row says +50% at rank 1; the in-game tooltip the file cites says +25% a rank: **unverified** which is live | `improved_bloodrage`; the `bloodrage` handler's instant gain; the resource entry's 25% unmodelled (Warrior.lua:222-223) |
| Toughness 12299 | **not live** | rank-1 row: aura 142 base 10 and aura 466 base 10 | - | not registered (correct) |
| Iron Will 12962 | 5 | two aura 232 rows base -15 (misc 1 and 12) | stun/fear duration | registered, unused |
| Last Stand 12975 | 1 | 12975: cd 180000, off GCD (StartRecovery 0); cast 12976: aura 34 (flat max health) base 30, 20 s | +30% of max health for 20 s, lost at expiry (12975 description); the flat aura carrying a percent means the dummy converts it at cast [I] | `last_stand` talent + ability + aura (20 s) |
| Improved Shield Block 12945/12307/12944 | **not live** | 3 ranks (talent 145, needs Shield Specialization 4): each rank e0 aura 107 misc 4 (proc charges) base **1** (+1 block, not cumulative) and e1 aura 107 misc 1 (duration) base 500 / 1000 / 2000 ms | - | not registered (correct) |
| Improved Revenge 12797/12799/12800 | 3 | 12797: aura 108 (pct) base 60; 12799/12800 no rows | +60% Revenge damage at rank 1 ("Increases damage dealt by your Revenge ability by $m1%"); the stun proc 12798 is the vanilla design, not in this row | `improved_revenge` registered; `revenge_stun` aura 12798 (3 s); no proc logic |
| Shield Slam 23922 | 1 | **(corr.)** rage 200 (20), category cooldown 6000 (category 971), GCD 1500, base level **40**; e0 effect 38 (dispel) misc 1 (magic) base 1; e1 effect 2 (damage) base 430, sp coeff 1 | the "50%" dispel chance of the first draft is not in the DB2 (**unverified**); "+ block value" damage is vanilla's, not in the row [I] | `shield_slam` ability (cd 6, cost 20) |
| Concussion Blow 12809 | 1 | rage 100 (10), RecoveryTime 45000, **StartRecovery 0 (off GCD)**, aura 12 (stun) 5 s, base level 30 | | ability (gcd off) + talent |
| Improved Sunder Armor 12308 | 3 | rank-1 row: aura 107 misc 14 (flat cost) base -30 = -3 rage; 12810/12811 no rows | Sunder 15 -> 12 at rank 1; -3 a rank [I]. L60 observed 9 [WEB mmonster] | `15 - 3*rank` (Warrior.lua sunder_armor), then `offensive_cost` (Focused Rage) on top |
| Improved Taunt 12302/12765 | **not live** | 12302 aura 107 misc 11 (cd) -1000; 12765 -2000 | - | not registered (correct) |
| **Defiance** 12792 | **3 live** ([EXP]); 5 rank IDs in the DB2 talent 144 (12303, 12788, 12789, 12791, 12792), only 12792 has rows | 12792: aura 10 (threat) base 15, misc 127 | "+$s1% threat in Defensive Stance while a shield is equipped" = +15% at the live max [I: 5% a rank if 3 ranks]; 7376's description multiplies it: `(7376 s3 + 100) * (12792 s1 / 100 + 1)` | `defiance = {0, 12792, 3}` (matches the export). Not read by anything |
| Improved Shield Wall 12312 | 2 | rank-1 row: aura 107 misc 11 (cd) base -660000 | description `${$m1/-60000}.1 min` = 11.0 min off a 15 min cooldown: implausible, **unverified** | `improved_shield_wall` registered, unread (shield_wall cd 900) |
| Improved Shield Bash 12311 | 2 | rank-1 row: aura 42 base 100 -> 18498 (the silence) | silence | used in `shield_bash` |
| **Bastion** 16538 | 5 (talent 702: 16538-16542) | **(corr.) rank-1 row**: aura 79 (damage done pct) misc 1 (physical) base 10 | +10% physical damage at rank 1 | key `one_handed_weapon_specialization`; no reader |
| Improved Disarm 12313 | 3 | rank-1 row: aura 107 misc 11 (cd) base -20000 | Disarm -20 s at rank 1 (vanilla: duration); **unverified** | registered |
| Improved Thunder Clap 12287 (Protection column on Forever) | 3 | rank-1 row: aura 107 misc 14 base -60 = -6 rage | file: 20 - 6/rank; L20 cost 14 at rank 1 [WEB] | used in `thunder_clap` |
| **Vanguard 1310317** | 1 | **(corr.)** three aura 332 (override) rows: 1240289 / 1240288 / 1240287 with misc 11578 / 6178 / 100 (the three Charge ranks) | "Your Charge ability is now usable while in Defensive Stance" | `vanguard`; Charge's `buff` (Warrior.lua charge) |
| **Master of Defense 1310316** | 2 | **(corr.)** aura 42 (proc trigger) **base 0** -> 23602 (energize rage base 50 = 5 rage); ProcChance 100 | description "Grants you a $m1% chance to generate ${23602m1/10} Rage when you Dodge or Parry while a shield is equipped": m1 = 0 in the row, so the chance is **unverified** ([WEB wow.gg]: 50% a rank). The amount: 5 rage by today's DB2; the 2026-10-15 reconcile recorded 23602 as 20 (2 rage): **unverified**, the tooltip settles it | registered, **unmodelled** |
| **Focused Rage 29787** | 3 | one row only (no rank IDs): aura 107 misc 14 base -30 | -3 rage on offensive abilities (per-rank scaling **unverified**; 3/rank assumed by the file) | `offensive_cost()` |
| Raging Blows 1310315 | 1 | aura 4 base 100; aura 107 misc 14 base -30 | -3 rage Cleave and Whirlwind | `raging_blows` in cleave/whirlwind |
| Lingering Rage 1323964 | 5 | **(corr.)** 1323964: aura 42 -> 1323966 (passive); 1323965: aura 94, 10 s | delays out-of-combat decay by "$s1/1000 sec"; per-rank N **unverified** | registered, unmodelled |
| Gore Drinker 1323967 | 2 | aura 4 base 3 and 1; buff 1323969 (8 s): aura 231 -> 1323968 | next 3 melee attacks restore 1% max health ([EXP] tooltip) | registered, unmodelled |
| Bloodthrill 1289682 | 5 | aura 42 base 15 -> 1282733 ("Overpower", 5 s); aura 1289681 6 s | Arms; not Protection | registered, unmodelled |
| Weaponmaster 1290261 | 5 | three aura-4 rows 5 / 15 / 5 | per weapon type | registered, unmodelled |

Shield Specialization detail [DB2]: its trigger spell 1310318 is "Generate ${$1310318m1/10} Rage when you Block" (energize 50 = 5 rage); a variant 1310925 is an effect-137 (energize percent) base 6 spell (the first draft's "Paladin mana" reading: **unverified**). Vigilance 426972, Devastate 403195/403196, Commanding Shout 403215 and Focused Rage 29787 are **Season of Discovery rune spells present in the DB2** (403475 "Engrave Gloves - Devastate" is an engraving spell); whether they are engraved, granted or absent on Forever is unconfirmed (section 6 Q3). Warrior.lua registers `focused_rage` (a live talent node per [EXP]) but not Devastate or Commanding Shout.

## 2. The Protection kit [DB2]

IDs are rank-1 unless noted. Rage costs are DB2 points (divide by 10). "Cat. cd" is `SpellCooldowns.CategoryRecoveryTime`; "GCD" is `StartRecoveryTime`.

| Ability | ID(s) | Rage | Cooldown | GCD | Duration / notes | In Warrior.lua |
|---|---|---|---|---|---|---|
| Shield Block | 2565 (level 16) | 10 | 5 s (RecoveryTime 5000) | **off** (0) | 7 s; aura 51 +75% block; **(corr.) `SpellAuraOptions.ProcCharges` 2** ("will only block $n attacks"); **no `SpellCategories` row, so no charge category**: `C_Spell.GetSpellCharges` has nothing to report (it is also `SecretWhenCooldownsRestricted` [DOC]); the export tooltip: "75% for 7 sec, but will only block 2 attacks" | cd 5, spend 10, gcd off, `buff = "defensive_stance"`, `equipped = "shield"`, aura 2565 duration 7 `max_stack = 1` (no charge model) |
| Revenge | 6572, 6574, 7379, 11600, 11601, 25288 (levels 14/24/34/44/54/60) | 5 | 5 s (cat. cd 5000; category 65) | 1500 | "Must follow a block, dodge or parry"; **(corr.)** effect **2** (damage) base 22, sp coeff 1 (not "effect 22"); the window's length: none in the DB2 (5 s is Classic's, [HK]) | `revenge_usable` aura 5 s from the combat-log rows on us (attributed hits only) or `reactive(REVENGE)` = the plain `IsSpellUsable` |
| Shield Slam | 23922-23925 (levels 40/48/54/60) | 20 | 6 s (cat. cd 6000, category 971) | 1500 | dispel 1 magic (effect 38) + damage 430 | cd 6, `offensive_cost(20)` |
| Sunder Armor | 7386, 7405, 8380, 11596, 11597 (levels 10/22/34/46/58) | 15 | none | 1500 | 30 s, 5 stacks; aura 674 misc 1 base -90 (armor per stack [I]); effect 63 (threat) base 34 | stack to 5, 30 s |
| **Devastate** | 403196 (knowledge 403195: aura 109 base 100 -> 403196; 403355: aura 332 misc 399967; engrave 403475) | none (no power row) | none | none | **(corr.)** 403196: effect 2 base 150 and effect 3 base 10: "Sunder Armor also deals $s1% weapon damage, +$s2% per Sunder already on the target"; 403195: "while in Defensive Stance with a shield"; range 50000 | **not registered** |
| Taunt | 355 (level 10) | 0 | 8 s (cat. cd 8000) | **off** | 3 s (aura 11); effect 114 | yes, `buff = defensive_stance` |
| Mocking Blow | 694, 7400, 7402, 20559, 20560 (levels 16-56) | 10 | 120 s (cat. cd) | 1500 | 6 s taunt (aura 11); damage effect 2 base 22; Battle Stance in vanilla | yes, `buff = "battle_stance"` |
| Challenging Shout | 1161 (level 26) | 5 | 600 s | 1500 | 6 s, aura 11, area (target 22) | yes |
| Last Stand | 12975 (cast) / 12976 (aura) | 0 | 180 s | off | +30% max health 20 s | yes |
| Shield Wall | 871 (level 28) | 0 | 900 s | 1500 | -60% damage taken (aura 87 base -60, misc 127), 12 s | yes |
| Concussion Blow | 12809 (level 30) | 10 | 45 s | **(corr.) off** (StartRecovery 0) | 5 s stun | yes (gcd off) |
| Thunder Clap | 6343, 8198, 8204, 8205, 11580, 11581 (levels 6/18/28/38/48/58) | 20 | 6 s (cat. cd) | 1500 | 10/14/18/22/26/30 s; e0 damage base 10; **(corr.)** e1 aura 319 (attack speed) base **-20**; "up to 4 targets": the target cap is not in this DB2 extract, **unverified** | yes |
| Demoralizing Shout | 1160, 6190, 11554, 11555, 11556 (level 14) | 10 | none | 1500 | 45 s | yes (setting, off by default) |
| **Commanding Shout** | 403215 | **(corr.)** no power row (0) | **(corr.)** none (the 300000 ms is its duration, 5 min) | 1500 | aura 29 misc 2 (stamina) base 2 + 0.68 a level, party (target 20); 22440 "Commanding Shout" is an unrelated aura-77 spell | **not registered** |
| Bloodrage | 2687 (aura 29131) | 0 (health cost: `SpellPower` PowerType -2 (health), PowerCostPct 20) | 60 s | **off** | 10 rage now (effect 30 base 100) + **(corr.) 10 over 10 s** (29131: aura 24 base 10 every 1000 ms for 10000 ms = 10 ticks; the tenth lands at the expiry, stepped-decay design §1) | yes (resource entry `bloodrage`) |
| Defensive Stance | 71 (level 10; passive 7376) | 0 | 1 s stance category ([EXP] tooltip; 0 in `spell_info`) | off | 7376: aura 87 **-10% damage taken (misc 127)**, aura 79 **-10% damage dealt**, aura 10 **+30% threat** (Defiance multiplies it) | yes |
| Spearing Strike | 1310222 (talent, Arms) | 15 (cost 150) | 20 s | 1500 | **(corr.)** effects 121 (normalized weapon damage), 31 (weapon %) base 40, 3 (dummy) base 2; Battle Stance | yes (talent-gated) |
| Victory Rush | 402927 (level 20) | 0 | 30 s | 1500 | usable 20 s after a kill (402975 "Victorious", 20 s); **(corr.) heals 10% of max health** (effect 136 base 10); effect 3 base 15 is the AP coefficient (`1 + AP x m3 / 100`) | yes (`reactive(VICTORY_RUSH)`) |
| Shield Bash | 72, 1671, 1672 (level 12) | 10 | 12 s (cat. cd) | 1500 | 6 s school lock | yes |
| Heroic Strike | 78 ... 25286 | 15 | none | off (next swing) | "high amount of threat" (tooltip) | yes |
| Cleave | 845 ... 20569 (level 20) | 20 | none | off (next swing) | effect 17 base 5; the 2-target cap: **unverified** (not in this extract) | yes |
| Battle Shout | 6673 ... 25289 | 10 | none | 1500 | 180 s | yes |
| Disarm | 676 (level 18) | 20 | 60 s (cat. cd) | 1500 | 10 s (aura 67) | **(corr.)** a registered ability (Warrior.lua disarm, `buff = defensive_stance`), plus the `improved_disarm` talent |

Observed costs at L60 on Forever [WEB mmonster]: Shield Slam 17, Revenge 2, Shield Block 10, Thunder Clap 11, Sunder 9, Demoralizing 10, Heroic Strike 12 (consistent with Focused Rage -3, Improved Sunder Armor 1/3 and Improved Thunder Clap 1 rank: -6). Not verifiable from the DB2 (the ranks have no rows).

## 3. Rage from damage taken [MG#3, MG#24]

magey issue 3 (level 8-9 Warrior on Zephras Isle, Forever 1.60.1; nothing at 60 yet), re-read 2026-10-16:
- **rage (bar points) = pre-armor damage x 10 / max health** ("Formula that fits every geared log"; the page's "factor" is tenths per point x max health / 10, so a factor of 10 is this formula). Example, log 01 (593 armor): 20 hits, 110 pre-armor damage, max health 203, 5.9 rage logged against 5.4 predicted (factor 10.9).
- Blocked hits grant the rage of the **unblocked** amount.
- Attacker level made no difference (L5 vs L6 mobs, same rate).
- **Armor step:** below roughly 130-170 armor the same formula gives exactly double: clusters 9.6-11 (>= 170 armor) vs 18.3-20.5 (<= 132). "Not tied to a piece"; the step sits between 10.2% and 13.6% reduction against a level 5 mob. Reported as a possible Blizzard bug; unresolved.
- **(corr.)** Stance: the issue never names one. Defensive Stance is a level-10 spell (71, base level 10) and the logs are from level 8-9, so they were **not** in Defensive Stance [I].
- Open at L60: the factor (a level-scaled form would diverge from a health-scaled one); off-hand and crits (autoattack side: 3.46 rage/s one-hand weapon speed, 4.5 two-hand; crit adds one base swing).
- Not covered: Berserker Rage, Defensive Stance's and Shield Wall's damage reduction against the formula.

Armor reduction on Forever [MG#24]: vanilla DR = A / (A + 400 + 85 L) (player armor above L10 fits per attacker level: 0.995-1.004 of the constant; weighted fit 246 + 91.8 x L, within +-5% of classic); below L10 mob attackers also match classic. Armor below 0 adds no damage. Logged raw amount is floored: add 0.5 before fitting. Crits x2.0.

Inputs readable in combat:
- `UNIT_COMBAT` on `player` is **plain** (165 firings, 0 secret): event WOUND/BLOCK/DODGE/PARRY/MISS/HEAL, flagText CRITICAL/GLANCING/CRUSHING/BLOCK/BLOCK_REDUCED, amount and school plain [TDF N27, C2, C4, M1-M4]. The amount is the post-armor, **post-block** hit; the blocked part is not given [TDF :180]. Whether a full `BLOCK` event carries an amount: **unverified** (section 6 Q11).
- `UnitArmor("player")`: `SecretWhenUnitStatsRestricted` [DOC], secret in combat, plain out of combat [AUD row 18]; returns `base, effective, real, bonus` [DOC]. **(corr.)** The 2026-10-16 probe's "UnitArmor 0" was the first return (`base`), not the armor: use the second (`effective`). Cached by the stat cache (Families/Player.lua `I.STATS`).
- `GetShieldBlock()`: exists on Forever, `SecretWhenUnitStatsRestricted` [DOC] (plain out of combat by the family's behaviour [I]); **not** in the stat cache today.
- `UnitHealthMax("player")`: plain always (2026-10-16 probe: 624 in and out of combat).
- Attacker level: not in `UNIT_COMBAT`; `UnitLevel("target")` plain; `UnitIsUnit("targettarget","player")` plain (facade passthrough, [W PR14]).
- Reconstructing pre-armor [I]: pre = post / (1 - DR), DR = armor / (armor + 400 + 85 x attackerLevel) with the cached out-of-combat effective armor; then rage = pre x 10 / maxHealth. Blocked hits: post + block value before the division. The 2x low-armor step is a separate uncertainty.
- Defensive Stance: aura 87 base -10 = -10% damage taken (all schools) [DB2 7376]. Whether the formula's "pre-armor damage" is before or after this 10% is untested (Q7).

## 4. Threat

- Defensive Stance: **+30% threat** (7376 e2 aura 10 base 30), -10% damage dealt/taken. **Defiance** adds 15% at its live max (12792 base 15), multiplicatively: `(30+100) x (1 + D/100)`; 3 live ranks ([EXP]) against 5 DB2 rank IDs. Applies only in Defensive Stance with a shield.
- Per-ability threat values on Forever: **not documented** in the DB2 beyond Sunder's effect 63 base 34; the tooltips say "high amount" (Revenge, Heroic Strike) and "moderate" (Mocking Blow). magey's repo has no threat data.
- Plain reads [TDF N20; AUD; HK]: `UnitThreatSituation(unit, mobUnit)` plain in combat [W PR14; facade passthrough row] (status 0-3: 0 not on the list / lower, 1 higher than the tank but not tanking, 2 tanking but not highest, 3 tanking securely); its doc flag is `SecretWhenUnitThreatStateRestricted` [DOC]; `UnitDetailedThreatSituation` percent plain [TDF]; events `UNIT_THREAT_LIST_UPDATE` (278 firings, target 225) and `UNIT_THREAT_SITUATION_UPDATE` (65) plain. `UnitIsUnit("targettarget","player")` plain; `UNIT_TARGET` plain (172). Hekili State: `aggro = UnitThreatSituation("player") > 1` and `tanking = role.tank and aggro` ([HK] State.lua:1842, 1870). **(corr.)** `role.tank` is set only from `GetSpecializationInfo`'s role (Engine/Spec.lua:1974-1980); Forever's single pseudo-spec 1491's role is unread, so `tanking` may be false for a Protection build (section 6 Q12).
- `UnitThreatSituation("player")` with no second argument = highest across mobs.

## 5. Recommended priority

Sources: wow.gg beta guide ("Revenge only after block/dodge/parry; Sunder once or twice early, spread stacks; Thunder Clap main AoE; Demoralizing on non-casters; Victory Rush after a kill, don't wait; no rage on nearly dead mobs"); mmonster rotation trainer L60 ("Charge from Defensive via Vanguard; Bloodrage; Shield Block up nearly always; Thunder Clap up; Shield Slam on cooldown; Revenge after every avoid; Demoralizing; Sunder to 5; HS with leftover rage"); Mobalytics snippet ("1 Shield Slam, 2 Revenge when available, Victory Rush, Rend, Sunder, HS excess rage"); the existing provisional list in `tools/packs/warrior.lua`. Devastate appears in no Forever guide.

Flag key: [E] expression already supported; [N] new named expression needed.

Single target:
```
actions.precombat=battle_shout,if=!buff.battle_shout.up                          [E]
actions.precombat+=/charge,use_off_gcd=1                                           [E] (usable in Defensive via Vanguard)
actions.precombat+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up    [E]
actions=shield_bash                                                              [E] (interrupts toggle)
actions+=/defensive_stance,use_off_gcd=1,if=!buff.defensive_stance.up             [E]
actions+=/taunt,use_off_gcd=1,if=threat.lost                                        [N]
actions+=/victory_rush                                                           [E]
actions+=/shield_block,use_off_gcd=1,if=!buff.shield_block.up                     [E] (blocks left: [N] belief stacks)
actions+=/bloodrage,use_off_gcd=1,if=rage.current<20                              [E]
actions+=/battle_shout,if=!buff.battle_shout.up                                   [E]
actions+=/shield_slam                                                            [E]
actions+=/revenge                                                                [E] (buff.revenge_usable gates it)
actions+=/thunder_clap,if=!debuff.thunder_clap.up                                 [E]
actions+=/sunder_armor,if=debuff.sunder_armor.stack<5|debuff.sunder_armor.remains<5   [E]
actions+=/demoralizing_shout,if=!debuff.demoralizing_shout.up&settings.debuff_demoshout_enabled   [E]
actions+=/concussion_blow,if=toggle.defensives&health.pct<30                      [N] player health is secret: needs a belief
actions+=/heroic_strike,use_off_gcd=1,if=rage.current>=50                          [E]
actions+=/sunder_armor                                                           [E]
```
AoE (>=3 enemies):
```
actions.aoe=thunder_clap,if=!debuff.thunder_clap.up|active_dot.thunder_clap<active_enemies   [E]
actions.aoe+=/demoralizing_shout,if=!debuff.demoralizing_shout.up                  [E]
actions.aoe+=/revenge                                                              [E]
actions.aoe+=/shield_slam                                                          [E]
actions.aoe+=/sunder_armor,if=target.debuff.sunder_armor.stack<2                   [N?] per-target stack; settings.debuff_sunder_max_stack=1 exists
actions.aoe+=/cleave,use_off_gcd=1,if=rage.current>=40                             [E]
actions.aoe+=/challenging_shout,if=toggle.defensives&!target_of_target.is_me           [N]
```
Cooldowns, behind the `defensives` toggle: `last_stand,if=health.pct<30` and `shield_wall,if=health.pct<20`. **(corr.)** The player's current health is **secret always** (UnitHealth `SecretReturns`; the 2026-10-16 probe read `S` in and out of combat): only the maximum is plain. These need a current-health belief.

New expressions requested: `threat.situation` (0-3 from `UnitThreatSituation`), `threat.lost`/`not_tanking` (`aggro` exists), `buff.shield_block.stack` (blocks left: the aura walk is secret in combat, so a belief), `health.pct` for the player (a belief).

## 6. Open questions with in-game probe lines

`VSCopy` prints a secret as S. Every line is under 255 characters.

Q1. Shield Block's blocks: whether the aura's `charges` or `applications` shows 2 out of combat (and in combat, expected S).
`/run local a=C_UnitAuras.GetPlayerAuraBySpellID(2565) VSCopy("SB",a and a.applications,a and a.charges,a and a.maxCharges,a and a.duration)`
Q2. Revenge window edge: time between a block and `IsSpellUsable(6572)` flipping, and length.
`/run local f=CreateFrame("Frame") f:RegisterEvent("UNIT_COMBAT") f:SetScript("OnEvent",function(_,e,u,ev) if u=="player" and (ev=="BLOCK" or ev=="DODGE" or ev=="PARRY") then VSCopy("RV",GetTime(),ev,C_Spell.IsSpellUsable(6572)) end end)`
Q3. Are Devastate/Commanding Shout/Focused Rage granted or engraved? `/run VSCopy("DEV",IsPlayerSpell(403196),IsPlayerSpell(403195),IsPlayerSpell(403215),IsPlayerSpell(29787),C_Engraving~=nil)`
Q4. UnitThreatSituation values solo: `/run VSCopy("TH",UnitThreatSituation("player","target"),UnitThreatSituation("player"),UnitDetailedThreatSituation("player","target"))`
Q5. Target-of-target identity: `/run VSCopy("TT",UnitIsUnit("targettarget","player"),UnitExists("targettarget"),UnitName("targettarget"))`
Q6. Defiance, Shield Specialization and Master of Defense tooltips at the current rank: `/run for _,i in ipairs({12792,12298,1310316,29787}) do VSCopy("T",i,C_Spell.GetSpellDescription(i)) end`
Q7. Rage per hit taken: hit a mob, record bar change vs the UNIT_COMBAT amount, in Battle and then Defensive Stance:
`/run local f=CreateFrame("Frame") f:RegisterEvent("UNIT_COMBAT") f:SetScript("OnEvent",function(_,_,u,e,fl,a) if u=="player" then VSCopy("R",GetTime(),e,a,fl,UnitPower("player",1),UnitHealthMax("player")) end end)`
Q8. Out-of-combat armor and block value: `/run VSCopy("AR",select(2,UnitArmor("player")),GetShieldBlock(),UnitHealthMax("player"),UnitLevel("player"))` (run in and out of combat).
Q9. Defensive Stance +30% threat and shield-only Defiance: no direct read; compare `UnitDetailedThreatSituation` percent growth after Sunder in and out of the stance.
Q10. Rage costs: `/run for _,i in ipairs({7386,23922,6572,6343}) do local c=C_Spell.GetSpellPowerCost(i) VSCopy("C",i,c and c[1] and c[1].cost) end`
Q11. **(new)** A full block's amount and flags: the Q7 line, reading the `BLOCK` rows (amount 0 or the blocked amount?) and the `WOUND` rows flagged `BLOCK`/`BLOCK_REDUCED`.
Q12. **(new)** The pseudo-spec's role: `/run local i=GetSpecialization() VSCopy("ROLE",i,i and select(5,GetSpecializationInfo(i)),Hekili.State.role.tank)`
