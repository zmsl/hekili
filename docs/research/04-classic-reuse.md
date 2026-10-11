# R4: What we can reuse from the `classic` branch

Research for reviving Hekili on WoW Forever (Camelot 1.60.1, Interface 16001, vanilla-1.6 ruleset on the Midnight 12.1.5 API). The first target is Feral cat.
Every source here was read only: `git show/diff/log/ls-tree` against `origin/classic`, `origin/sod` and `forever` (HEAD `36daec38`), plus the Forever addons installed under `_classic_beta_/Interface/AddOns`.

## Summary

- **Build on the `forever` engine (retail TWW 11.2.5), not on the `classic` engine.** The classic engine is a Sept-2022 Wrath fork. It calls legacy globals (`GetSpellInfo` 21 times, `GetSpellCooldown`, `UnitAuraBySlot`, `GetTalentTabInfo`, `GetSpellTexture`) that Midnight removed and that Forever doesn't document. The forever engine already uses the `C_Spell` / `C_UnitAuras` / `C_SpellBook` / `C_Traits` namespaces that Forever does document. Neither engine handles secret values. That work is new either way.
- **The engine part of the Classic-Era port is small.** Commits `2ef2a444..origin/classic` (Nov 2024 to Jul 2025, mostly by zmsl, the user) changed only about 300 lines in State, Events, UI, Core and Targets. The main pieces are a 2-second energy-tick model with `energy.time_to_tick`, GCD spell 29515, rank glossing by spell name, weapon stats read from tooltips, and `IsClassic()` guards. These are easy to port onto the forever engine as ideas. The energy-tick detector is the exception: it reads `UnitPower` deltas, which are secret in combat, so it has to be redesigned.
- **`Classic/Druid.lua` (1924 lines) is a good source of vanilla Druid data.** It has every rank ID, the auras, costs and talent effects, plus useful mechanics models: energy ticks, Furor and Wolfshead powershift gain, Maul as a next-swing attack, rage from swings, and Enrage rage over time. Much of its logic reads values that are secret in combat on Forever: energy, combo points, rage, aura remains and target health.
- **The Feral APL is a powershift / Rip / Bite sim port with no Rake and no Tiger's Fury in melee.** It leans heavily on `energy.current`, `energy.time_to_tick`, `combo_points.current` and `debuff.rip.remains`, which are all secret or derived from secret values in combat. Its condition list is below for checking against the secret-value matrix.
- **Forever does use vanilla spell IDs**, with additions. All six of Catnip's IDs and its GCD spell match the classic branch exactly. Forever's talent data also uses vanilla first-rank talent spell IDs, alongside Season of Discovery rune IDs (Primal Bite 407995, Berserk 417141, Eclipse 408248, Wild Growth 408120) and new Forever IDs in the 1.2M to 1.3M range.
- **`origin/sod` has nothing for Season of Discovery.** It is a Nov-2023 Wrath fork. Of the other classic class modules, only Rogue and Warrior were reworked for vanilla, and Rogue only partly. Hunter, Mage, Paladin, Priest, Shaman and Warlock are unchanged Wrath modules.
- **Talents may be readable after all.** TalentsForeverBook reads the character's talents through `C_Traits` on Forever, and its node and spell IDs line up with Hekili's retail `RegisterTalents{ node, spell, max }` format. This contradicts the shared assumption that Forever has no readable talent API, so it needs checking in game (see Open questions).

## Findings

### 1. Engine comparison: `classic` vs `forever`

**Lineage.** The two branches share merge-base `968371b9` (2022-08-31, "Quickfix for #1599").
- **`origin/classic`:** 485 commits since the merge-base. It is the Wrath branch (Sep 2022 to Apr 2024: Hekili, Supernuss and Zachary Samsel) with a Classic-Era port on top (2024-11-15 to 2025-07-10: zmsl, rheuz and Zack). The TOC is `Interface: 11505`, `X-Flavor: Classic`, and it loads `Classic\*.lua`.
- **`forever`:** 5167 commits since the merge-base. It is retail through The War Within 11.2.5 (`Interface: 110205`). It has per-expansion folders, a split `Options/` directory, and `TheWarWithin/*.lua` spec modules.

**Size of the divergence.**

| | classic (merge-base → tip) | forever (merge-base → HEAD) |
|---|---|---|
| Whole tree | 108 files, +27.7k / −69.7k (deleted the retail class modules) | 201 files, +138.8k / −73.6k |
| Core engine files | State +576/−, Events 420, Constants 1302, Options 992, UI 229, Scripts 79, Core 62, Targets 87 | State ~3.0k, Classes ~4.8k, Events 1.2k, Core 1.3k, UI 1.3k, Scripts 1.0k, Targets 0.8k, Options split out (−11.5k from `Options.lua` into `Options/`) |
| Engine diff between the two tips | Classes 6.3k, Options 11.8k, State 3.4k, Events 1.4k, Core 1.3k, UI 1.3k, Scripts 1.1k, Targets 0.9k lines changed | |

**Themes on the classic side.**
1. Wrath support (2022–2024): ranks folded into `copy={}` lists; `state:IsKnown` replaces an ability's ID with the highest known rank via `select(7, GetSpellInfo(name))` (`origin/classic:State.lua:6805-6830`); glyphs; a pack selector driven by `GetTalentTabInfo`; Wrath trinkets in `Classic/Classes.lua`; and talents detected by calling `IsPlayerSpell` on each rank ID (`Classic/Classes.lua:10-73`).
2. The Classic-Era port, `2ef2a444..origin/classic` (62 files, +5.2k / −10.1k):
   - **Energy ticks:** the energy resource has `tick_rate`/`tick_time_avg` = 2 s. `Events.lua:1392-1433` detects a tick when energy rises by +20 (or caps) after at least 1.9 s, and averages the tick period.
   - **New expression:** `energy.time_to_tick` (`State.lua:3515`).
   - **Resource padding removed:** the 0.1 s retail energy padding was taken out of `TimeToResource`.
   - **GCD spell:** 29515 replaces 61304 (`UI.lua`, three places).
   - **Mana per Intellect:** set to 15 for Classic.
   - **Attack power:** `UnitAttackPower` a+b+c.
   - **Weapon stats:** min, max and speed scraped from the tooltip (`Events.lua GetBaseWeaponStats`).
   - **Target name:** new `target.name`.
   - **LibDualSpec:** disabled.
   - **Flavor guards:** `IsClassic()` decoupled from `IsWrath()` and added in the places that matter (`Hekili.lua`, `Core`, `Targets`, `UI`).
   - **Five-second rule:** there is no explicit model. Mana regen comes from `GetManaRegen()` inactive/active (`State.lua:6261`).
   - **Swing timer:** the engine already tracks `swings.mainhand`, `nextMH` and `mainhand_speed` from combat-log swings (`State.lua:6301-6311`). `Druid.lua` builds `mainhand_remains` on top of that.

**Themes on the forever side.**
- Retail namespaces throughout (`C_Spell.GetSpellCooldown`, `C_UnitAuras.GetBuffDataByIndex` / `GetAuraSlots`, `C_SpellBook`) and talents from `C_Traits` (`Dragonflight/Classes.lua`, `ns.updateTalents`, keyed `{ nodeID, spellID, maxRank }`).
- All Wrath and Classic branches are gone: `IsWrath()` and `IsClassic()` checks appear 3 times in Events and once in UI, and nowhere in State or Classes.
- `IsKnown` no longer does rank glossing (`State.lua:7402`).
- The energy model is the retail 0.1 s one (`Events.lua:1408`), and the GCD spell is 61304 (`UI.lua:1500,1701`, `Events.lua:1924`).
- No secret-value handling at all: a grep for `issecret`/`secret` across the engine found none.

**API reality on Forever** (from the `wow` MCP).
- **Retail namespaces:** `C_Spell.GetSpellInfo`, `C_ClassTalents.GetActiveConfigID`, `C_Traits.GetNodeInfo` and `C_SpecializationInfo.GetSpecialization` / `GetSpecializationInfo` are documented for Forever.
- **Legacy globals:** `GetSpellInfo`, `GetSpellCooldown`, `UnitAura`, `UnitAuraBySlot`, `GetTalentTabInfo` and `IsPlayerSpell` show as "not documented (may still be a legacy global)". Catnip calls `IsPlayerSpell` defensively (`IsPlayerSpell and not IsPlayerSpell(id)`), and TalentsForeverBook probes `_G.GetSpellInfo` and `GetTalentInfo` (`Game.lua:228`). So some legacy globals may exist, but the classic engine cannot rely on them.

**Verdict.** Use the forever engine as the base. It already speaks the API family that Forever ships. The secret-value work that both engines lack fits better on retail's aura and cooldown code paths, which are close to Midnight's. Port the classic delta as a small, reviewable set of vanilla mechanics (listed under Reuse plan). Taking the classic engine would mean re-porting four years of retail engine fixes plus every namespace migration.

### 2. `Classic/Druid.lua` inventory (`origin/classic`, 1924 lines)

**Header and spec.**
- `NewSpecialization( 11 )` is the class ID, not spec 103. One spec module serves all trees, and a pack selector picks Balance or Feral (`:1915-1924`).
- The event hooks (combat log, `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_POWER_UPDATE COMBO_POINTS`) are empty stubs (`:10-22`).

**State expressions and helpers.**
- `rage_gain` / `rage_amount()` uses the TBC-era rage formula from `UnitDamage` and level (`:24-44`).
- `mainhand_remains` comes from `nextMH` / `mainhand_speed` (`:46-64`).
- `ttd` returns 300 on "Combat Dummy", otherwise `target.time_to_die` (`:66-72`).
- `combat_mode_solo` / `combat_mode_group` come from the `combat_mode` setting (`:74-80`).
- `swap_form(form)` removes the `form` and `maul` buffs, spends all rage, and applies the Furor 5/5 and Wolfshead gains: +10 or +5 rage into bear, +40 or +20 energy into cat (`:83-111`).
- `start_maul` / `finish_maul` model Maul as a next-swing aura that costs `15 - ferocity` rage when the swing lands (`:108-121`, used by the `reset_precast` hook `:33-40` via `IsCurrentSpell`).
- Gear: `wolfshead` = item 8345 (`:124`).

**Resources** (`:127-183`).
- Rage: an `enrage` tick of +2 every 1 s while the buff is up, and a `mainhand` swing generator in bear form that yields `rage_amount()` unless Maul is queued.
- Mana and ComboPoints: plain.
- Energy: a custom `tick` regen of +20 every `energy.tick_time_avg`, anchored on `energy.last_tick`.

**Talents** (`:186-235`). 47 vanilla talents, each as `{ talentIndex, maxRank, rankIDs... }`. They are detected through `IsPlayerSpell` on the rank IDs (`Classic/Classes.lua:10-44`). The Feral ones the APL and costs use are `ferocity`, `improved_shred`, `furor`, `natural_shapeshifter`, `brutal_impact`, `improved_enrage`, `moonglow`, `tranquil_spirit`, `improved_wrath`, `improved_healing_touch` and `improved_starfire`.

**Auras** (`:238-604`). Every multi-rank aura carries a `copy` list of all its vanilla rank IDs.
- **Forms:** `bear_form` 5487/9634, `cat_form` 768, `dire_bear_form` 9634, `moonkin_form` 24858, `travel_form` 783, `aquatic_form` 1066, and a `form` alias.
- **Feral:** `rake` 1822/1823/1824/9904 (9 s); `rip` 1079/9492/9493/9752/9894/9896 (12 s); `pounce` / `pounce_bleed`; `prowl` 5215/6783/9913; `tigers_fury` 5217/6793/9845/9846 (6 s); `dash`; `enrage` 5229; `frenzied_regeneration`; `clearcasting` 16870 (15 s); `omen_of_clarity` 16864 (600 s); `faerie_fire_feral` (16857+); `demoralizing_roar`; `bash`; `growl`; `feral_charge_effect` 19675.
- **Caster and debuffs:** `moonfire` (10 ranks), `insect_swarm`, `hurricane`, `entangling_roots`, `hibernate`, `regrowth`, `rejuvenation`, `thorns`, `innervate` 29166, `natures_grasp`, `natures_swiftness`, `natures_grace`, `tranquility`, `soothe_animal`.
- **Cross-class bleeds** (rupture, garrote, rend, deep_wound) feed a `bleed` alias.
- **Leftovers from Wrath and TBC:** `natural_perfection` 45283 and a `demoralizing_roar` primary ID of 48560.

**Abilities** (`:606-1737`): 55 entries. The Feral ones:

| Ability | Base ID | Cost | Notes |
|---|---|---|---|
| `claw` | 1082 (+4 ranks) | 45 − ferocity energy | |
| `shred` | 5221 (+4 ranks) | 60 − 6×improved_shred energy | |
| `rake` | 1822 (+3 ranks) | 40 − ferocity energy | `readyTime = debuff.rake.remains` |
| `rip` | 1079 (+5 ranks) | 30 energy | `usable` needs CP > 0; `readyTime = debuff.rip.remains`; spends all CP |
| `ferocious_bite` | 22568 | 35 energy, then spends all remaining energy and CP | copy list includes TBC rank 31018 |
| `tigers_fury` | 5217 | 30 energy | cooldown modelled as 1 s |
| `pounce` / `ravage` | | | need `buff = "prowl"` |
| `faerie_fire_feral` | 16857 | | 6 s cooldown |
| `maul` | 6807 (+6 ranks) | | off GCD, queued |
| `swipe_bear`, `bash`, `growl`, `enrage`, `demoralizing_roar`, `challenging_roar`, `frenzied_regeneration`, `cower`, `dash`, `prowl` | | | |
| Forms | | 55% base mana × (1 − 10%×natural_shapeshifter) | `swap_form` |

- Every energy and rage ability costs 0 while `buff.clearcasting.up` and removes the buff.
- Combo-point builders `gain(1,"combo_points")`. The model has no crit / Primal Fury combo points.
- Abilities have no form gating. The engine relies on the spell being usable.

**Settings** (`:1738-1906`): `innervate_enabled`, `innervate_threshold` (20%), `combat_mode` (solo/group), `powershift_enabled`, `powershift_time` (1 s), `rip_enabled` (default false), `rip_cp` (5), `bite_enabled` (true), `bite_cp` (5), `bite_time` (0), `claw_trick_enabled`, and a dev-only `dummy_ttd`.

**What depends on data that is secret on Forever.** This is based on the shared brief: in combat, power, combo points, aura data and cooldown times are secret.

| Dependency | Where | Forever status |
|---|---|---|
| Energy tick detection from `UnitPower` deltas (+20 per tick) | `Events.lua:1392-1433` | **Breaks**: energy is secret in combat. Needs a timing-only signal (event cadence) or a free-running 2 s clock seeded out of combat. |
| `energy.current`, `rage.current`, `mana.current/pct` | APL and `swap_form` | Secret in combat. |
| `combo_points.current`; `usable` for rip and bite | APL and abilities | Secret in combat. |
| `debuff.rip.remains/up`, `debuff.rake.remains`, `debuff.moonfire.up`, `debuff.faerie_fire*.remains` | APL, `readyTime` | Aura durations are secret. The workaround is to track our own casts by cast event × known duration (as Catnip's DotRings does). |
| `buff.clearcasting.up` | every cost function, APL | Use Catnip's trick: Shred `GetSpellPowerCost == 0`. |
| `buff.maul.up` via `IsCurrentSpell` | `reset_precast` | `IsCurrentSpell` is probably readable. Not verified. |
| Swing timer (`swings.mainhand`, `nextMH`) | rage generator, `mainhand_remains` | Catnip has a working Swing.lua, so it is likely readable. |
| `rage_amount()` from `UnitDamage` and level | rage model | `UnitDamage` is probably readable (a stat, not combat state). |
| `target.time_to_die` (the `ttd` used everywhere) | APL | Derived from target health, which is secret on Midnight. |
| Talent ranks via `IsPlayerSpell(rankID)` | `Classic/Classes.lua` | Passive talents don't add a spell on Forever (Catnip `Gcd.lua:77`). Use `C_Traits` instead. |
| Pack selector via `GetTalentTabInfo` | `Classic/Classes.lua:46-73` | Not documented on Forever. |
| `set_bonus.wolfshead` | APL | Equipment is readable. |

### 3. Feral APL condition inventory (`Classic/APLs/DruidFeral.simc` and `.t.simc`)

The `.t.simc` file is a template: `# name=expr` macros expanded with `{{name}}` by `Classic/APLs/template.js`. The `.simc` file is the flattened output, and the two are semantically the same. Lists: `precombat`, default, `innervate_or_shift`, `ranged`, `bear`, `cat_solo`, `cat_oom`, `cat_ps`.

**Every distinct expression used, for the secret-value matrix:**

| Group | Expressions |
|---|---|
| Resources | `energy.current` (compared with `<10`, `=100`, `>=15`, `>=28`, `>=63`); `energy.time_to_tick`; `mana.current`; `mana.pct`; `rage.current` (`>60`); `combo_points.current` (`>=settings.rip_cp`, `>=settings.bite_cp`) |
| Player buffs | `buff.form.up`; `buff.cat_form.up`; `buff.bear_form.up`; `buff.clearcasting.up`; `buff.maul.up`; `buff.omen_of_clarity.up`; `buff.gift_of_the_wild.up`; bare `up` / `!up` (self-buff of the action: mark_of_the_wild, thorns) |
| Target debuffs | `debuff.rip.up`; `debuff.rip.remains` (also in `debuff.rip.remains-energy.time_to_tick`, `ttd-debuff.rip.remains`); `debuff.moonfire.up`; `debuff.faerie_fire_feral.remains`; `debuff.faerie_fire.remains` |
| Target | `ttd` (custom expression = `target.time_to_die`, with the dummy override); `target.outside2`; `target.outside5` |
| Actions | `action.cat_form.cost`; `action.bear_form.cost`; `action.moonfire.cost`; `action.innervate.known`; `action.shred.known` |
| Talents and gear | `talent.furor.rank`; `set_bonus.wolfshead` |
| Settings and mode | `settings.rip_enabled`, `settings.rip_cp`, `settings.bite_enabled`, `settings.bite_cp`, `settings.bite_time`, `settings.powershift_enabled`, `settings.powershift_time`, `settings.claw_trick_enabled`, `settings.innervate_enabled`, bare `innervate_threshold` (resolves through `spec.settings` fallback, `State.lua:2746`), `combat_mode_solo` |
| Items and flow | `best_mana_potion`, `mana_rune`, `potion`, `use_items`; `use_off_gcd=1`; `call_action_list`, `run_action_list` |

**Not used anywhere in the APL:** `cooldown.*` (not even `cooldown.tigers_fury.ready`), `target.health.pct`, `debuff.rake.*`, `active_enemies`, `gcd`, and swing timing. Rake is never recommended. Tiger's Fury appears only in the `ranged` list when energy is 100 and the target is more than 5 yd away.

**Implicit expressions used by `Druid.lua` itself:** `talent.ferocity.rank`, `talent.improved_shred.rank`, `talent.natural_shapeshifter.rank`, `talent.moonglow.rank`, `talent.tranquil_spirit.rank`, `talent.improved_enrage.rank`, `talent.brutal_impact.rank`, `buff.natures_swiftness.up`, `buff.natures_grace.up`, `buff.moonkin_form.down`, `buff.berserk.up` (a Wrath leftover; it now names a Forever talent, Berserk 417141), `buff.prowl`, `debuff.rake.remains`, `debuff.rip.remains`, `buff.maul.expires`, `swings.mainhand_speed`, `mainhand_remains`, `haste`, `IsCurrentSpell(maul)`.

**What this means for Forever.** The APL is a powershifting sim port: it decides from exact energy against the next tick and from Rip time remaining. Almost every branch in `cat_ps` and `cat_oom` reads energy, combo points or Rip remaining. Without readable values in combat it would need modelled state: energy and combo points predicted from our own casts plus ticks, and Rip remaining from our cast time. Treat it as a design reference, not drop-in content.

### 4. Spell IDs: classic branch vs Catnip vs Forever data

| Spell | classic `Druid.lua` | Catnip | Forever data (TalentsForeverBook / GearQuest) | Match |
|---|---|---|---|---|
| Rake ranks | 1822, 1823, 1824, 9904 (aura `copy`, ability `copy`) | `DotRings.lua:27` same | n/a | identical |
| Rip ranks | 1079, 9492, 9493, 9752, 9894, 9896 | `DotRings.lua:31` same | idol 220606 "+2 s Rip" | identical |
| Clearcasting | 16870 | `Proc.lua:11` | n/a | identical |
| Omen of Clarity | 16864 (talent and ability) | `Proc.lua:10` (Cooldown Manager tracks it) | **removed as a talent** (TFB Balance `removed`) | ID same; presumably baseline now |
| Enrage | 5229 | `Enrage.lua:8` ("verified in Forever") | n/a | identical |
| GCD spell | 29515 (`origin/classic:UI.lua`) | `Gcd.lua:2-3` | n/a | identical |
| Other abilities | by ID + `copy` | by name via `C_Spell.GetSpellInfo(name)` + `IsPlayerSpell` (`Catnip.lua:48-50`) | n/a | compatible: classic's own `IsKnown` resolves the same way, by name |

**Talent IDs** (TalentsForeverBook `Data.lua`, build 1.60.1.70291).
- Nearly every surviving vanilla Druid talent keeps the vanilla rank-1 spell ID in classic's `RegisterTalents`: 16814, 16845, 16821, 16819, 16918, 5570, 16909, 16850, 16880, 16896, 24858, 16934, 17003, 17002, 16947, 16940, 16929, 16966, 16998, 16942, 16972, 17007, 17063, 17056, 17069, 17118, 16833, 17106, 17104, 24968, 17111, 18562, 17116, 17123 and 17074.
- Many max ranks changed: Improved Moonfire 5→2, Feral Instinct 5→3, Thick Hide 5→3, Shredding Attacks 2→3, Sharpened Claws 3→2. So `{maxRank, ids…}` tables need updating.
- **Renames and reused IDs:**
  - Feline Swiftness → Feral Swiftness (17002).
  - Improved Shred → Shredding Attacks (16966).
  - Improved Healing Touch → Naturalist (17069).
  - Forever "Blood Frenzy" uses classic `primal_fury`'s ID 16958 with Primal Fury's text (crit → extra combo point).
  - "Overgrowth" reuses 17245 (classic `improved_natures_grasp`).
  - Feral Charge has a new ID, 1238122 (classic 16979).
- **Removed:** Nature's Grasp, Improved Nature's Grasp, Natural Weapons, Improved Thorns, Omen of Clarity, Feral Aggression, Faerie Fire (Feral) (as a talent), Improved Mark of the Wild, Improved Enrage.

**Forever-only spells the classic branch doesn't have.**
- **Season of Discovery rune IDs, reused as talents:**
  - Primal Bite 407995.
  - Berserk 417141. Its SoD idol 213594 reads: "Causes your **Primal Bite** ability to strike up to 3 targets, removes its cooldown…" In SoD the same rune buffed Mangle, which suggests Primal Bite is Forever's renamed SoD Mangle.
  - Eclipse 408248, Wild Growth 408120, Gift of the Earthmother 414673, Natural Reaction 417051.
- **New Forever IDs:** Shifting Power 1322605, Improved Shifting Power 1322670, Genesis 1223081, Nature's Majesty 1223082, Nature's Splendor 1223083, Natural Instinct 1223242, Rend and Tear 1223246, Living Spirit 1309631.
- **Lacerate** is referenced in TFB `mentions` for Shredding Attacks.
- **Other spells Catnip tracks:** cooldown rings for Primal Bite and Faerie Fire (Feral), an arc for Shifting Power, and Growl.

**Verdict: confirmed, with additions.** Forever uses vanilla spell IDs for classic abilities, auras and talents: every overlapping ID matches. On top of those it adds SoD 4xxxxx IDs and new 1.2M to 1.3M IDs. Classic's rank `copy` lists can be reused as they are for vanilla ranks. One caveat: if Forever's level cap goes beyond 60 (GearQuest mentions "Level 70 … Phase 3"), Catnip's lists stop at vanilla max rank, so TBC ranks such as Rip 27008 or Rake 27003 would be missing (see Open questions).

### 5. `origin/sod` and per-class readiness

**`origin/sod`** (tip `9d4a47f5`, 2023-11-18) is a Wrath fork: `Wrath/*.lua` and Wrath APLs, including Death Knight. Grepping for SoD rune IDs (407995, 417141, 408248, 408120, 414673) or `C_Engraving` found nothing. It has no usable Season of Discovery work. Its only Druid-relevant content is a Wrath Feral module with zmsl's 2023 pooling changes, and the same changes already exist in classic's history.

**Classic class modules.** `2ef2a444..origin/classic` shows six of them as pure renames from `Wrath/` with zero changes. For the 9 Forever classes:

| Class | `Classic/*.lua` | Vanilla-ready? | Notes |
|---|---|---|---|
| Druid | 1924 lines, rewritten Nov 2024 | **Yes (vanilla 1.12)** | Feral and Bear pack. Balance pack selector registered, but Balance content is thin. A few Wrath and TBC leftovers (berserk, natural_perfection, 31018, 48560). |
| Warrior | 1781 lines, rewritten Nov 2024 to Jul 2025 | **Yes** | Arms, Fury and Prot packs (2025-07-10), DPR execute logic, `.t.simc` templates. |
| Rogue | 1378 lines, partly reworked (rheuz, Nov 2024) | Partial | Still carries Wrath content (killing_spree, hunger_for_blood, fan_of_knives, shadow_dance) and 2023 packs. |
| Hunter | 2417 lines, Wrath as-is | No | 17 glyph references, Wrath talents (`aimed_shot = {1345,…}`). |
| Mage | 5197 lines, Wrath as-is | No | 75 glyph references, arcane_barrage, deep_freeze and similar. |
| Paladin | 2328 lines, Wrath as-is | No | Divine Storm, Hammer of the Righteous, glyphs. |
| Priest | 1858 lines, Wrath as-is | No | Dispersion and similar, glyphs. |
| Shaman | 2583 lines, Wrath as-is | No | Lava Burst, Feral Spirit, glyphs. |
| Warlock | 2420 lines, Wrath as-is | No | Haunt, Chaos Bolt, Metamorphosis. |

All modules use `NewSpecialization(classID)`, a single module per class with pack selectors. The forever engine is built on retail spec IDs (for example 103 Feral). Forever documents `C_SpecializationInfo.GetSpecialization` and `GetSpecializationInfo`, and TFB shows each class has three named trees. What these calls return on Forever is unverified.

## Reuse plan

**Copy as-is (data, after a light review):**
- The vanilla rank `copy` lists for Druid abilities and auras in `Classic/Druid.lua` (`:238-604`, `:606-1737`): IDs, durations, base costs, textures and descriptions. They match Catnip and Forever wherever they overlap.
- Wolfshead gear ID 8345, and GCD spell 29515.
- The APL templating tool `Classic/APLs/template.js` and the `.t.simc` macro convention, as a way to write readable APLs that flatten to Hekili's syntax.
- Druid settings definitions (`:1738-1906`): powershift, rip and bite thresholds, claw trick, combat mode, innervate.

**Adapt (port the idea onto the forever engine):**
- **Energy tick model:** the `RegisterResource(Energy, { tick = … })` regen, `energy.time_to_tick` in `mt_resource`, and the `tick_rate = 2` default. Re-source tick timing: the `UnitPower` delta is secret in combat, so seed the phase out of combat, or test whether `UNIT_POWER_FREQUENT` firing cadence alone reveals the tick in combat.
- **Rank glossing in `state:IsKnown`:** move from `select(7, GetSpellInfo(name))` to `C_Spell.GetSpellInfo(name).spellID`, as Catnip does, and refresh keybindings when the ID changes.
- **`swap_form`, Furor / Wolfshead powershift gains, Maul queued-swing model, rage-from-swing generator, Enrage rage over time:** good models of the mechanics. Check them against Forever's changed talents (Furor still exists; Improved Enrage is removed).
- **Ability cost functions:** keep the formulas, but `buff.clearcasting.up` must come from the Shred-cost-0 probe, and `talent.*.rank` from `C_Traits` with Forever max ranks.
- **Talents:** rewrite `RegisterTalents` in the retail `{ node, spell, max }` format, using TalentsForeverBook's node and spell IDs. Do not port classic's `IsPlayerSpell` rank scan: passive talents aren't in the spellbook on Forever.
- **The Feral APL:** keep the decision structure (rip_now, bite_now, bite_at_end, jit_shift), but rewrite it against modelled or readable state. Add Forever spells (Primal Bite, Shifting Power, Berserk, Rake/Rend and Tear) and drop powershift branches if Forever's Furor or Wolfshead behaviour differs.
- **Small engine deltas:** `target.name`, weapon damage and speed via tooltip, Classic `UnitAttackPower` triple, and 15 mana per Intellect. Use these only where Forever's stats differ from retail; verify each.

**Don't reuse:**
- The classic engine files (`State`, `Classes`, `Events`, `Core`, `UI`, `Options`, `Scripts`, `Targets`). They are a 2022 Wrath engine on legacy globals.
- `Classic/Classes.lua`: Wrath and ICC trinkets, glyph code, the `GetTalentTabInfo` pack selector.
- The Hunter, Mage, Paladin, Priest, Shaman and Warlock modules (unchanged Wrath), and the Rogue module beyond its talent table.
- All of `origin/sod`.
- Druid leftovers: `dire_bear_form` as a separate form, `natural_perfection`, `berserk` as the Wrath buff, the Moonkin aura text, and the cross-class `bleed` alias.

## Evidence

- **Merge-base:** `968371b9` (2022-08-31). Classic port base: `2ef2a444` (2024-04-20). Classic tip: `fce4fcf1` (2025-07-10). Sod tip: `9d4a47f5` (2023-11-18). Forever: `36daec38`.
- **Classic-Era port diff:** `git diff --stat 2ef2a444 origin/classic`. Shows Wrath→Classic renames with 0 changes for Hunter, Mage, Paladin, Priest, Shaman and Warlock; Rogue 1198 lines changed; Druid and Warrior new.
- **`origin/classic` files:**
  - `Hekili.toc`: Interface 11505, X-Flavor Classic.
  - `Events.lua:1373-1433`: energy tick detection.
  - `State.lua:3515`: `time_to_tick`. `:6257-6261`: `tick_rate`, `GetManaRegen`. `:6301-6311`: swings. `:6805-6830`: rank-glossing `IsKnown`. `:2746`: `spec.settings` fallback. `:2820`: `outsideN`.
  - `UI.lua`: `GetSpellCooldown( Hekili.IsClassic() and 29515 or 61304 )`, three places.
  - `Classic/Classes.lua:10-73`: `IsPlayerSpell` talents and the `GetTalentTabInfo` pack selector.
  - `Classic/Druid.lua`: `:8` spec 11; `:24-121` helpers; `:124` wolfshead; `:127-183` resources; `:186-235` talents; `:238` auras (rake `:487`, rip `:509`, tigers_fury `:538`); `:606` abilities (claw `:724`, ferocious_bite `:939`, maul `:1150`, rake `:1346`, rip `:1483`, shred `:1509`, tigers_fury `:1616`); `:1738-1906` settings; `:1913` Feral pack; `:1915-1924` pack selectors.
  - `Classic/APLs/DruidFeral.simc` (51 lines), `DruidFeral.t.simc` (70 lines).
- **`forever` (HEAD):** `Hekili.toc:1` Interface 110205; `Hekili.lua:30-35` `IsClassic()` aliases `IsWrath()`; `State.lua:7402` `IsKnown` without rank glossing; `Events.lua:1408` `energy_avg = 0.10`; `UI.lua:1500,1701` and `Events.lua:1924` GCD 61304; `Dragonflight/Classes.lua` `C_Traits` talent update; `TheWarWithin/DruidFeral.lua:68` `RegisterTalents{ node, spell, max }`.
- **Forever addons:**
  - Catnip: `Catnip.lua:48-50` resolves spells by name; `DotRings.lua:27,31` Rake and Rip ranks; `Proc.lua:10-11`; `Enrage.lua:8`; `Gcd.lua:2-3` GCD 29515, and `:77` (passive talents not in the spellbook); `CooldownRings.lua:30-44` Faerie Fire (Feral) and Primal Bite; `ShiftingPower.lua`.
  - TalentsForeverBook: `Data.lua` (Druid at line 5715 onward, removed-talent blocks around 5923 and 6209); `Game.lua:1-60` (reads `C_Traits` live).
  - GearQuestForever_DRUID: `AuditTips.lua:2230` (idol 213594, Berserk→Primal Bite), `:2236` (idol 220606, Rip +2 s); `Data.Druid.generated.lua` header mentions level 70.
- **`wow` MCP (`wow_api_diff` / `wow_api_search`, flavor forever):** `GetSpellInfo`, `GetSpellCooldown`, `UnitAura`, `UnitAuraBySlot`, `GetTalentTabInfo`, `IsPlayerSpell` and `GetSpecialization` are "not documented". `C_Spell.GetSpellInfo`, `C_ClassTalents.GetActiveConfigID`, `C_Traits.GetNodeInfo`, `C_SpecializationInfo.*` and `GetManaRegen` are documented.

## Open questions

1. **Can talents be read through `C_Traits` on Forever, and in combat?** TalentsForeverBook reads them live with `C_Traits` and has a "From character" import. That contradicts the "no readable talent API" assumption in the brief. Check whether node ranks are secret in combat; we only need them out of combat, cached.
2. **Which spec ID does Forever report?** It matters whether `C_SpecializationInfo.GetSpecialization` / `GetSpecializationInfo` return retail-style spec IDs (103 Feral) or something else. This decides between per-spec modules (forever engine) and a per-class module (classic).
3. **Can the energy tick be detected in combat without reading energy?** For example, from `UNIT_POWER_FREQUENT` cadence, or whether the 2 s tick phase survives a powershift. Without it, `energy.time_to_tick` and the whole powershift APL are guesses.
4. **Does Forever still support the Furor and Wolfshead powershift economy?** Furor exists; it is unknown whether item 8345 does or the energy gain is unchanged. If not, drop the `cat_ps` list.
5. **What do Primal Bite and Shifting Power do?** Cost, cooldown, combo-point interaction. TFB tooltips come from the game at runtime, so they need an in-game check. Is Primal Bite the SoD Mangle (Bear 407995) re-skinned for both forms?
6. **What is the level cap?** GearQuest's mention of level 70 suggests ranks above vanilla might exist; Catnip's rank lists stop at rank 6 Rip and rank 4 Rake.
7. **Is Omen of Clarity baseline?** It is removed from the talent tree, but Catnip treats 16864 as a known spell.
8. **Are `IsCurrentSpell` (Maul queue), `UnitDamage` and swing events readable in combat?** These feed the bear rage model.

## Confidence

- **High:** branch lineage and divergence figures, the APL condition inventory, the classic Druid inventory, the matching ID comparison (exact matches checked against files), and that sod and six classic class modules are Wrath content.
- **Medium-high:** recommending the forever engine as the base. It rests on namespace availability in the MCP's Forever docs plus Catnip and TFB usage; no legacy global was tested in game.
- **Medium:** the SoD-ID origin of Primal Bite and Berserk (inferred from ID ranges and idol text), `C_Traits` readability (inferred from TFB code, not tested), and which mechanics survive in combat (from the brief plus Catnip comments).
