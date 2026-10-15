# Race pass research brief (Forever 1.60.1.70338, DB2)

Read-only research. Pattern read: `Forever/Races/{Gnome,NightElf,Tauren}.lua`, `Races.lua`, `Classes.lua` (`all`) at hekili HEAD 688dd350.
Queries are `wowdb "SELECT ..."`; `spell_info`, `spell_effects` views plus raw `SpellEffect` (class masks) and `SpellClassOptions`.

## 1 Races on Forever

There is no ChrRaces table in the DB2 extract (tables: ChrClasses, SkillLine, SkillLineAbility, Spell*, Talent*, Item*). Races are inferred
from the racial SkillLines and `SkillLineAbility.RaceMasks_0/1` (bit = 1 << (raceID-1)).

| Race | SkillLine | race token (UnitRace 2nd return) | status |
|---|---|---|---|
| Human | 754 "Racial - Human" | `Human` (assumed) | no file |
| Dwarf | 101 "Dwarven Racial" | `Dwarf` (assumed) | no file |
| Night Elf | 126 "Night Elf Racial" | `NightElf` (file uses it) | `NightElf.lua` done |
| Gnome | 753 "Racial - Gnome" | `Gnome` (file uses it) | `Gnome.lua` done |
| Orc | 125 "Orc Racial" | `Orc` (assumed) | no file |
| Undead | 220 "Racial - Undead" | `Scourge` (assumed; Blizzard's token, NOT `Undead`) | no file |
| Tauren | 124 "Tauren Racial" | `Tauren` (file uses it) | `Tauren.lua` done |
| Troll | 733 "Racial - Troll" | `Troll` (assumed) | no file |
| Forever addition | 2980 "Skyborne Racial" | unknown | see below |

RaceMasks_0 values on the eight skill lines are exactly 1,4,8,2,16,32,64,128 (Human, Dwarf, NE, Orc, UD, Tauren, Gnome, Troll), confirming Classic's eight.
No Goblin/Blood Elf/Draenei/Worgen racials exist (no skill line, no mask bits 256+ in RaceMasks_0).

Forever additions (inferred, not named in the DB2): skill line 2980 "Skyborne Racial" has RaceMasks_0 = 0 and RaceMasks_1 nonzero:
Read Ley Line 1259705 mask_1=1 (race bit 32), Skysight 1259686 mask_1=2 (bit 33), Walk on Air 1259416 / Elemental Insight 1259707 /
Wind Blessed 1259710 mask_1=3 (both). Also "Galestrider Riding" 1285849/1285853 (mask_1=3) and "Skyborne Portal to Dalaran" 1278902/1278903.
So there are two new races (probably two factions' versions of one "Skyborne" people; Galestrider is their mount). I could not find their names,
playable class lists or token strings. Treat as out of this pass unless the user wants them (table in 2.9).

Hekili `state.race_token` = `UnitRace("player")` second return (State.lua:516); `Hekili:NewRace(token)` is live only when equal.

## 2 Racials per race

Legend. cd/dur in seconds; GCD from `gcd_ms` (1500 = on GCD, 0/blank = off GCD). Model: ADD (race file adds), OVERRIDE (race file replaces an `all` key
because the Forever ID/behaviour differs), ALL (leave to `all`), NM (not modelled, nothing a rotation can use). All Forever racials have a single ID for
every class unless the table says otherwise (exceptions: Gnome Eureka/Expansive Mind, Undead Touch of the Grave).

### What `all` (Classes.lua) already registers

| `all` key | ID in `all` | exists on Forever? | note |
|---|---|---|---|
| ability `berserking` | 26297, cd 180, gcd off, toggle cooldowns, handler applyBuff berserking | NO. Forever Berserking is 20554 | OVERRIDE |
| aura `berserking` | 26297, 10 s | NO | override aura id 20554 |
| ability `blood_fury` | `bf_classes[class.file]`: 20572 (Hunter/Rogue/Warrior) 33702 (Mage/Warlock/Priest) 33697 (Shaman), cd 120, handler applyBuff blood_fury 15 | only 20572 exists (33702, 33697 absent) | OVERRIDE id=20572 for all classes |
| aura `blood_fury` | 20572, 15 s | yes | keep (works through the override) |
| ability `will_to_survive` | 59752, cd 180, toggle defensives, no handler | NO. Forever is 1259718 | OVERRIDE |
| ability `shadowmeld` | 58984, cd 120, usable needs boss/group and not moving, handler applyBuff shadowmeld | NO. Forever is 20580 (cd 0, 10 s category recovery) | OVERRIDE |
| aura `shadowmeld` | 58984, 3600 s | NO | override aura id 20580 |
| ability `stoneform` | 20594, cd 120, gcd off, toggle defensives, handler clears dispellable_* and applyBuff stoneform | id yes; cd is 180 on Forever, GCD 1.5 | OVERRIDE (cd, gcd, aura id) |
| aura `stoneform` (inside the ability's `auras`) | 65116, 8 s | NO (65116 absent). Buff is 20594 itself (aura 87 on the spell) | override aura id 20594 |

Not registered anywhere in `all` or Forever/Classes: arcane_torrent, escape_artist, war_stomp (Tauren.lua adds), perception, cannibalize,
will_of_the_forsaken, gift_of_the_naaru, every_man_for_himself (grep of Classes.lua, Forever/Classes/*.lua, Forever/spec). The Classic `all`
therefore leaves every race with at most the shared stock entries above; none are "left to `all`" safely except possibly blood_fury (its
`id` function returns 20572 for Hunter/Rogue/Warrior and the Druid fallback `or 20572` for all other class files, so on Forever it
already resolves to 20572 for Orc Druid/Warrior; Mage/Priest/Warlock/Shaman would get nonexistent IDs: override is simplest).
No pack (Druid.lua, Warrior.lua, specs) names any racial. Existing race files set `toggle = "cooldowns"`, `startsCombat = false/true`, plus `now`.

### 2.1 Human (754)

| id | name | classes | type | cast/cd/dur/GCD | effect | model |
|---|---|---|---|---|---|---|
| 1259718 | Will to Survive | all | active | 0 / 180 / instant / GCD 1.5 | Effect 0: dummy base 99 misc 12 (remove stuns, mechanic 12 = stun) | OVERRIDE `will_to_survive` (id 59752 gone). No aura, no `now` writes (a cleanse; set `toggle="defensives"`, `usable` could test a stun later; unmodelled) |
| 20600 | Perception | all | active | 0 / 180 / 20 / GCD 1.5 | aura 17 (stealth detection) 50 | ADD optional, `toggle="defensives"`; a stealth-detection buff has no rotation value. Recommend NOT modelled (NM) |
| 20598 | The Human Spirit | all | passive | - | aura 137 (stat % mod) +5% misc 4 (Spirit) | NM (Spirit; mana regen only if a model reads it) |
| 20597 | Sword Specialization | all | passive | - | aura 290 (crit %) +2% while sword/2h sword equipped | NM (needs weapon type; stat) |

### 2.2 Dwarf (101)

| id | name | classes | type | cast/cd/dur/GCD | effect | model |
|---|---|---|---|---|---|---|
| 20594 | Stoneform | all | active, level 1 | 0 / 180 / 8 / GCD 1.5 | eff 0 aura 87 (damage taken %) -10 misc 1 (Physical); eff 1-3 dispel (misc 4 disease, 3 poison, 15 bleed); eff 4/5 aura 41 dispel immunity (poison, disease); eff 6 aura 77 mechanic immunity (bleed) | OVERRIDE `stoneform` (cd 180, aura 20594, gcd). Handler keeps the `all` cleanse-buff removal. |
| 2481 | Find Treasure | all | active | 0 / 0 (cat cd 0) / - / GCD 1.5 | aura 45 (track resources) | NM |
| 1259719 | Mace Specialization | all | passive | - | aura 290 crit +1% with a mace | NM |
| 1259721 | Big Game Hunter | all | passive | - | aura 168 (damage % vs creature type) +5% vs Beasts (misc 1) | NM (target type; not a rotation input) |

### 2.3 Night Elf (126)  (file exists)

| id | name | type | cast/cd/dur | effect | model |
|---|---|---|---|---|---|
| 1259799 | Elune's Light | active | 0 / 180 / 15 / off GCD | aura 290 crit +10% | ADD done (`NightElf.lua`) |
| 20580 | Shadowmeld | active | 0 / cd 0, category cd 10 s (cat 871) / until cancelled / no GCD | eff 0 aura 16 (stealth), eff 1 aura 103 (threat -999999) | OVERRIDE `shadowmeld` with id 20580 + aura id 20580 (the file's header says "Shadowmeld stays Hekili's stock racial": that is wrong on Forever: `all` uses 58984, which does not exist; fix in this pass). cooldown 10 not 120 (note: Hekili's gating by boss/not moving stays) |
| 20582 / 21009 | Quickness (+passive) | passive | - | dodge +1% (aura 49), run speed +2% (aura 31); 21009 aura 154 stealth detection 5 | NM |
| 20585 | Wisp Spirit | passive | - | death form | NM |

### 2.4 Gnome (753)  (file exists)

| id | name | classes (ClassMask) | type | detail | model |
|---|---|---|---|---|---|
| 1259813 / 1259812 / 1259817 / 1259821 / 1259823 | Eureka! | Warrior(1) / Rogue(8) / Mage(128) / Warlock(256) / Priest(16) | active | 0 / 120 / 15 / off GCD, 3 proc charges, class set 4 / 8 / 3 / 5 / 6 | ADD done; cost mod only declares Warrior spells (see 3.2) |
| 20591 / 1259802 / 1259803 | Expansive Mind | Priest+Mage+Warlock(400) / Warrior / Rogue | passive | aura 178 (max power %) +5%, misc 0 mana / 1 rage / 3 energy | ADD done (`max = 0.05` for any resource) |
| 20589 | Escape Artist | all | active | 0 / 120 / 3 / GCD 1.5: aura 77 mechanic immunity roots+snare (misc 7, 11) | NM (movement-impair clear). Optional ADD, defensives |
| 20593 | Engineering Specialization | passive | engineering failures | NM |

### 2.5 Orc (125)

| id | name | classes | type | cast/cd/dur/GCD | effect | model |
|---|---|---|---|---|---|---|
| 20572 | Blood Fury | all (one ID, no per-class variants on Forever) | active | 0 / 120 / 15 / off GCD | aura 166 (melee AP %) +10, 167 (ranged AP %) +10, 317 (spell power %) +10 | OVERRIDE `blood_fury`: `id = 20572` (drop the `bf_classes` map), handler `applyBuff("blood_fury", 15)` (aura already 20572/15) |
| 1299026 | Shatter Curse | all | active, level 1 | 0 / 180 / 8 / GCD 1.5 | aura 87 -15% all magic damage taken (misc 126 = all non-physical schools); dispel eff misc 2 (curse); immunity aura 41/ misc 2 | ADD `shatter_curse` (defensives), aura 1299026 8 s |
| 20573 | Hardiness | all | passive | - | aura 232 (stun duration) -20% | NM |
| 20574 | Axe Specialization | all | passive | - | aura 290 crit +1% with axe/2h axe | NM |

### 2.6 Undead (220)

| id | name | classes | type | cast/cd/dur/GCD | effect | model |
|---|---|---|---|---|---|---|
| 7744 | Will of the Forsaken | all | active | 0 / 120 / 0.1 / GCD 1.5 | aura 77 mechanic immunity: charm(1), fear(5), sleep(10) | ADD optional, defensives; no rotation value, NM acceptable |
| 20577 | Cannibalize | all | active | 0 / 120 / ch 10 via 20578 / GCD 1.5, range 5 | trigger 20578: periodic every 2 s, heal 7% health (aura 20) and 7% mana (aura 21) | ADD optional (needs a corpse; `usable` cannot know) NM |
| 1260189 | Touch of the Grave | Warrior(1)+Paladin(2)+Rogue(8) (ClassMask 11) | passive proc | 5% proc chance, ProcTypeMask 69972, internal 1 s | aura 4 dummy +5 (health drain up to 5% max HP) | NM |
| 1260201 | Touch of the Grave | Priest+Mage+Warlock (400) | passive proc | 10% proc | same | NM |
| 5227 | Underwater Breathing | - | passive | +300% | NM |

### 2.7 Tauren (124)  (file exists)

| id | name | type | cast/cd/dur | effect | model |
|---|---|---|---|---|---|
| 20549 | War Stomp | active | 0.5 / 120 / 2 / off GCD | aura 12 (stun), 5 targets, 8 yd | ADD done (`Tauren.lua`) |
| 20550 | Endurance | passive | - | max health +5% (aura 133), hit +1% (54, 55) | NM |
| 1259918 | Plainsrunning | passive | - | aura 226 (periodic dummy 1 s), speed +5% per tick to +30% | NM |
| 20552 | Cultivation | active | herb | NM |

### 2.8 Troll (733)

| id | name | classes | type | cast/cd/dur/GCD | effect | model |
|---|---|---|---|---|---|---|
| 20554 | Berserking | ClassMask -1 (all classes) | active | 0 / 180 / 10 / off GCD | aura 319 + 140 + 65: +10% haste melee, ranged, casting speed (single flat 10; Classic's rage/energy-scaled variants are gone) | OVERRIDE `berserking`: id 20554, aura 20554 10 s; handler `applyBuff("berserking")`. A haste buff: the simulation reads `buff.berserking.up`; the haste itself is read from the game (not modelled in `haste`) |
| 1260270 | Rapid Regeneration | all | active | 0 / 180 / 6 / off GCD | aura 20 (periodic heal) 10% max HP per 1.2 s tick (total 50%), cancelled by movement/action/damage | ADD optional, defensives; NM for rotation |
| 20555 | Regeneration | all | passive | - | aura 88 (health regen %) +10, aura 116 (combat regen) +10 | NM (health only) |
| 20557 | Beast Slaying | all | passive | - | aura 168 +5% vs beasts | NM |

### 2.9 Forever-added races (2980 "Skyborne Racial"; names/tokens unknown)

| id | name | mask_1 | type | cast/cd/dur | effect | model |
|---|---|---|---|---|---|---|
| 1259416 | Walk on Air | 3 | active | 0 / 120 / 10 / GCD 1.5 | glide (aura 105 hover? 409, 139 override) trigger 1259417 | NM |
| 1259686 | Skysight | 2 | active | 0.5 / 120 / - / GCD 1.5 | trigger 1259688 "Elemental Blessing" 30 s: +10% run speed (aura 31), +10% mounted (172) | NM |
| 1259705 | Read Ley Line | 1 | active | 2.0 / 120 / - / GCD 1.5 | trigger 1259691 "Energized" 900 s (near a ley line) or 1270842 15 s: aura 110 (mana regen %) +100, aura 88 (health regen %) +100 | candidate: a regen buff, but cast 2 s and location-dependent: NM |
| 1259707 | Elemental Insight | 3 | passive | - | +5% damage vs Elementals | NM |
| 1259710 | Wind Blessed | 3 | passive | - | aura 342 (haste, melee/ranged) base 1, aura 65 (casting speed) base 1; description `$s1%` value I could not resolve (base shown 1; likely scaled, perhaps 1%) | passive haste: NM |

## 3 Modifiers to declare

No race other than the Gnome has a masked cost or resource effect. Elune's Light, Blood Fury, Berserking are percentage stat
auras with no resource effect (haste does not change energy regen in the simulation here); no `RegisterResourceMod` needed for them.

### 3.1 Resource maxima
- Gnome Expansive Mind: `max = 0.05` (done). Covers Priest/Mage/Warlock mana (20591, ClassMask 400), Warrior rage 1259802, Rogue energy 1259803. Aura 178, misc 0/1/3.
- Troll/Orc/Tauren: Endurance is health, not a Hekili resource. None other.

### 3.2 Gnome Eureka cost mods (only Warrior declared today)
Effect 0 (cost): aura 108 (ADD_PCT_MODIFIER) misc 14 (cost) -10; effect 1 aura 108 misc 0 (damage) +10, class masks on `SpellEffect.EffectSpellClassMask_0..3`;
per-class `SpellClassSet`. The cost mask is the effect-0 mask (the damage mask differs for Mage/Warlock/Priest).

| class | Eureka ID | SpellClassSet | cost mask (0/1/2) | damage mask (0/1/2/3) |
|---|---|---|---|---|
| Warrior | 1259813 | 4 | 1784679630 / 5 / 1 | same / 0 |
| Rogue | 1259812 | 8 | 100794910 / 2097408 / 0 | same |
| Mage | 1259817 | 3 | 549591799 / 4096 / 0 | 551688947 / 4096 / 0 / 8 (+ eff 2 misc 22: DoT damage +10%) |
| Warlock | 1259821 | 5 | 541165 / 8650880 / 0 | 524773 / 8388736 / 0 (+ eff 2 misc 22) |
| Priest | 1259823 | 6 | 150224528 / 8388614 / 0 | 150224528 / 8486918 / 0 (+ eff 2 misc 22) |

Covered-spell query (set `<set>` and the three cost masks from the table; the `& 4294967295` guards sign extension):
```
select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
 join SpellPower p on p.SpellID=o.SpellID where o.SpellClassSet=<set> and p.ManaCost>0 and not
 (((o.SpellClassMask_0 & 4294967295)&<m0>)=0 and ((o.SpellClassMask_1 & 4294967295)&<m1>)=0 and ((o.SpellClassMask_2 & 4294967295)&<m2>)=0)
```
Caveat: it filters `ManaCost>0` (flat cost). Spells costing only `PowerCostPct` (many Mage/Warlock/Priest base-percent costs) are excluded by it;
rerun with `(p.ManaCost>0 or p.PowerCostPct>0)` before declaring those classes. The Warrior result (rank list in Gnome.lua) matches Gnome.lua's 17 base IDs.
Spell names covered (all ranks, run the query for IDs; rank-1 IDs go in `spells` with the class's `copy` lists resolving higher ranks):
- Rogue (energy PowerType 3; Eviscerate also lists combo-point PowerType 4): Ambush, Backstab, Eviscerate, Ghostly Strike, Gouge, Hemorrhage, Kick, Mutilate, Riposte, Sinister Strike. Not: poisons, Garrote, Rupture, Slice and Dice, cooldowns.
- Mage: Arcane Explosion, Arcane Missiles, Blast Wave, Blizzard, Cone of Cold, Fire Blast, Fireball, Flamestrike, Frost Nova, Frostbolt, Frostfire Bolt, Ice Lance, Pyroblast, Scorch, plus Forever runes/volleys.
- Warlock: Conflagrate, Death Coil, Drain Life, Drain Soul, Haunt, Hellfire, Immolate, Rain of Fire, Searing Pain, Shadow Bolt, Shadowburn, Soul Fire, Wrack.
- Priest: Binding Heal, Flash Heal, Greater Heal, Heal, Lesser Heal, Holy Fire, Holy Nova, Mana Burn, Mind Blast, Mind Flay, Penance, Prayer of Healing, Shadow Word: Death, Smite, Starshards.
- Warrior (existing): heroic_strike, cleave, slam, execute, overpower, mortal_strike, bloodthirst, whirlwind, shield_slam, revenge, thunder_clap, hamstring, intercept, mocking_blow, pummel, shield_bash, spearing_strike (+ Quick Strike 429765 appears in the query result; its Gnome status unverified).
The project's packs are Druid and Warrior only; Druid is not a Gnome class (no Druid Eureka/Expansive Mind exists, class masks 1, 8, 16, 128, 256 only) so the other four are needed only if more class packs appear.
Eureka's +10% damage is "not modelled" (Gnome.lua header).

### 3.3 Declarations for the pass
Nothing else: no Human/Dwarf/Orc/Undead/Tauren/Troll/Night Elf resource max or cost modifier exists in the DB2 data.
`RegisterCostMod` and `RegisterResourceMod` are needed for Gnome only.

## 4 What `now` must write

The Races.lua contract: `now` mirrors `handler` for VirtualState (spec §12a). Statements below use Gnome/NightElf/Tauren files as models.

| ability | handler / `now` writes | aura to register |
|---|---|---|
| `berserking` (20554) | `applyBuff("berserking")` (10 s) | `berserking` id 20554 duration 10, max_stack 1 |
| `blood_fury` (20572) | `applyBuff("blood_fury", 15)` | `blood_fury` id 20572 duration 15 |
| `shadowmeld` (20580) | `applyBuff("shadowmeld")` (until cancelled; `all` used 3600) | `shadowmeld` id 20580 duration 3600 (or 3600 as stock) |
| `stoneform` (20594) | `removeBuff` of the dispellable_* group then `applyBuff("stoneform")` (8 s) | `stoneform` id 20594 duration 8 (move out of the ability's `auras` or fix the id) |
| `shatter_curse` (1299026) | removeBuff dispellable_curse (if present) then `applyBuff("shatter_curse")` (8 s) | id 1299026 duration 8 |
| `will_to_survive` (1259718) | none (stun removal, no aura) | none |
| `eureka` (done) | `applyBuff("eureka", 15, 3)` | done |
| `elunes_light` / `war_stomp` (done) | `applyBuff("elunes_light")` / `applyDebuff("target","war_stomp")` | done |
| `rapid_regeneration` (1260270) optional | `applyBuff("rapid_regeneration", 6)` | id 1260270 duration 6 |
| `escape_artist`, `will_of_the_forsaken`, `perception`, `cannibalize` | optional; if registered, `now = function() end` with `gcd = "spell"` (all on the GCD) | none |

Gains: no racial grants a resource. No racial needs `gain()`. Stun on the target: only War Stomp (done). The Orc/Troll buffs are
read by APLs through `buff.blood_fury.up` / `buff.berserking.up`.

## 5 Open questions the DB2 cannot settle

1. Token strings from UnitRace's second return per race (Undead may be `Scourge`; the two Forever additions are unknown). `race_token` match is exact, so a wrong string silently makes a file inert.
   `/run VSCopy(select(2,UnitRace("player")), UnitRace("player"))`
2. Whether Forever really lets Hekili resolve spell IDs 26297 / 58984 / 59752 / 65116 / 33702 / 33697: they are absent from SpellName, so `GetSpellInfo` should return nil. Confirms that `all` berserking, shadowmeld, will_to_survive, stoneform-aura and non-Warrior blood_fury are broken and need overriding.
   `/run VSCopy(tostring(C_Spell.GetSpellInfo(26297)), tostring(C_Spell.GetSpellInfo(58984)), tostring(C_Spell.GetSpellInfo(59752)), tostring(C_Spell.GetSpellInfo(33702)))`
3. Does Blood Fury / Berserking apply the same ID aura name to the player (aura spell ID 20572 / 20554 on `UnitAura`), and does Shatter Curse / Stoneform buff report the spell's own ID?
   `/run local i=1 while true do local a=C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL") if not a then break end VSCopy(a.spellId,a.name,a.duration) i=i+1 end`
4. Race/class availability: whether a racial applies to a class the SkillLine ClassMask does not name (Gnome Druid does not exist in the data; Troll Berserking ClassMask -1; Touch of the Grave ClassMask 11/400 leaves Hunter, Shaman, Druid without it). Confirm in game which Forever race/class combinations are creatable.
   `/run VSCopy(UnitClass("player"), IsPlayerSpell(1260189), IsPlayerSpell(1260201), IsPlayerSpell(20554), IsPlayerSpell(1259718))`
5. Shadowmeld's real recovery on Forever: DB2 shows cooldown 0 with a 10 s category cooldown (cat 871), not Classic's 120 s; confirm via GetSpellCooldown after use.
   `/run local s,d=C_Spell.GetSpellCooldown(20580) VSCopy(20580, s and s.duration, s and s.startTime)`
6. Stoneform / Will to Survive / Escape Artist / Perception / Cannibalize / Will of the Forsaken now sit on the 1.5 s GCD (gcd_ms 1500, category 133); the stock `all` entry uses `gcd = "off"`. Confirm in game.
   `/run local i=C_Spell.GetSpellCooldown(20594) VSCopy(i and i.isEnabled, i and i.duration, GetSpellCooldown and GetSpellCooldown(20594))`
7. Wind Blessed (1259710) haste amount (`$s1%`, base 1) and the two unnamed Skyborne races (name, token, classes).
   `/run VSCopy(GetSpellDescription and GetSpellDescription(1259710), C_Spell.GetSpellDescription(1259710))`
8. Blood Fury scaling: aura 317 (spell power %) is a percent on a derived stat; the AP/SP bonus amount on Forever may differ from 10 % in the tooltip.
   `/run VSCopy(C_Spell.GetSpellDescription(20572))`

## 6 Sources

- `/home/zack/src/hekili/Forever/Races/{Gnome,NightElf,Tauren}.lua`, `/home/zack/src/hekili/Races.lua`, `/home/zack/src/hekili/Classes.lua` (`all`: lines 1759-1772 auras, 2477-2600 abilities), `/home/zack/src/hekili/State.lua:513-518` (race_token), `Virtual/State/spec/races_spec.lua`.
- DB2 via wowdb: SkillLine (101,124,125,126,220,733,753,754,2980), SkillLineAbility (+RaceMasks, ClassMask), SpellName, SpellEffect (aura, base points, misc, class masks), SpellCooldowns, SpellClassOptions, SpellPower, SpellAuraOptions; views spell_info/spell_effects.
- Not found / not done: ChrRaces table (absent); race names/tokens for the Skyborne races; item-based racials; class/race creatable combinations; per-rank IDs of masked Eureka spell lists for Rogue/Mage/Warlock/Priest (names only above, rerun the query); PowerCostPct spells; Wind Blessed value; in-game behaviour of any racial. Weapon-specialisation passives' required item class not decoded (needs SpellEquippedItems, absent).
