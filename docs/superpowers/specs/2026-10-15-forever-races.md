# Forever race pass in the Hekili fork: design spec (2026-10-15)

Status: draft for the user's review. Target: `Forever/Races/<Race>.lua`, one file per Classic race, on branch
`forever-races` at 688dd350 (the event-facade branch plus the Druid pack: `Races.lua`, `Gnome.lua`, `NightElf.lua`,
`Tauren.lua` exist). Every value below is the Forever DB2 (build 1.60.1.70338, `wowdb`), read for the research brief
`docs/research/2026-10-15-forever-races/research.md` (cited "R §n"); the Eureka! lists (§4) were re-queried for
this spec. Race files keep Hekili's style (spaces inside parentheses), `Hekili:NewRace( token )` and the four
`Register*` calls of `Races.lua`; nothing in `Races.lua`, `Classes.lua` or the layer changes.

## 1. Scope

One file per Classic race. New: `Human.lua`, `Dwarf.lua`, `Orc.lua`, `Troll.lua`, `Undead.lua`. Amended: `Gnome.lua`
(Eureka! scope per class, Escape Artist, header), `NightElf.lua` (Shadowmeld over `all`'s stale entry, header);
`Tauren.lua` is correct as it stands (War Stomp off the GCD per the DB2; its header names every passive) and is not
edited. `Hekili.toc` lists each new file after `Forever\Races\Tauren.lua`, so every race file still follows every class
file. `.luacheckrc` already gives `Forever/Races/` the `stateEnv` globals (`applyBuff`, `removeBuff`, `buff`, `boss`,
`solo`, `moving`), which covers every name the new files use: no edit.

The Forever additions (skill line 2980 "Skyborne Racial": two races by `RaceMasks_1` bits 32 and 33, R §1, §2.9) get
**no file**. Their names, tokens and classes are not in the DB2 and no token can be guessed (a wrong token makes a file
silently inert, and none of their five racials has rotation value: Walk on Air, Skysight, Read Ley Line with a 2 s cast
near a ley line, two passives). Deferred: checkpoint Q1 on a Skyborne character prints its token; a file follows only
if a racial turns out to matter (Wind Blessed's haste is a passive the game reports).

## 2. Registrations per race

Every active is an ability with its DB2 cooldown and GCD. An active whose cast leaves an aura has `handler` and `now`
(two closures, the same verbs: `now` names only Now.lua's verbs, no state, no API) and registers that aura; an active
whose cast leaves nothing beyond its cooldown and GCD (a stun or fear break) has neither, as `all`'s Will to Survive
never had a `handler`: VirtualState's automatic step writes its cooldown and GCD. `startsCombat = false` except War
Stomp. Toggle: offensive buffs `cooldowns`, the rest `defensives`, Shadowmeld none (as `all`).

**GCD rule** (R §5 Q6). The DB2's `gcd_ms` 1500 (start-recovery category 133) is Hekili's `gcd = "spell"`; 0 is
`gcd = "off"`. On the GCD on Forever: Will to Survive, Perception, Stoneform, Escape Artist, Shatter Curse, Will of the
Forsaken, Cannibalize (`all` had Stoneform and Will to Survive off it). Off: Berserking, Blood Fury, Shadowmeld, Rapid
Regeneration, Eureka!, Elune's Light, War Stomp.

| Race (token) | key | ID | cast / cd / GCD | toggle | `now` and `handler` | aura (id, s) |
|---|---|---|---|---|---|---|
| Human (`Human`) | `will_to_survive` | 1259718 | 0 / 180 / spell | defensives | none (stun break) | none |
| | `perception` | 20600 | 0 / 180 / spell | defensives | `applyBuff( "perception" )` | 20600, 20 |
| Dwarf (`Dwarf`) | `stoneform` | 20594 | 0 / 180 / spell | defensives | `removeBuff` poison, disease, bleed; `applyBuff( "stoneform" )` | 20594, 8 |
| Night Elf (`NightElf`) | `elunes_light` | 1259799 | 0 / 180 / off | cooldowns | as is | 1259799, 15 |
| | `shadowmeld` | 20580 | 0 / 10 / off | none | `applyBuff( "shadowmeld" )` | 20580, 3600 |
| Gnome (`Gnome`) | `eureka` | 1259813 (+4 copies) | 0 / 120 / off | cooldowns | as is: `applyBuff( "eureka", 15, 3 )` | 1259813, 15, 3 stacks |
| | `escape_artist` | 20589 | 0 / 120 / spell | defensives | `applyBuff( "escape_artist" )` | 20589, 3 |
| Orc (`Orc`) | `blood_fury` | 20572 | 0 / 120 / off | cooldowns | `applyBuff( "blood_fury", 15 )` | 20572, 15 |
| | `shatter_curse` | 1299026 | 0 / 180 / spell | defensives | `removeBuff( "dispellable_curse" )`; `applyBuff( "shatter_curse" )` | 1299026, 8 |
| Undead (`Scourge`) | `will_of_the_forsaken` | 7744 | 0 / 120 / spell | defensives | none (fear/charm/sleep break, 0.1 s immunity) | none |
| | `cannibalize` | 20577 | 10 channel / 120 / spell | defensives | `applyBuff( "cannibalize" )` | 20578, 10 |
| Tauren (`Tauren`) | `war_stomp` | 20549 | 0.5 / 120 / off | cooldowns | as is: `applyDebuff( "target", "war_stomp" )` | 20549, 2 |
| Troll (`Troll`) | `berserking` | 20554 | 0 / 180 / off | cooldowns | `applyBuff( "berserking" )` | 20554, 10 |
| | `rapid_regeneration` | 1260270 | 6 channel / 180 / off | defensives | `applyBuff( "rapid_regeneration" )` | 1260270, 6 |

Notes:
- **Blood Fury** has one ID for every class on Forever (R §2.5): `id = 20572`, no `bf_classes` map, no `copy`. Its
  aura (20572, 15 s) is already right in `all`; `Orc.lua` registers it again so the race owns it (`ns.applyRace` writes
  only owned keys) and so its `now` has an aura to write in the strict-context test.
- **Shadowmeld**: cooldown 0 with a 10 s category recovery (category 871) in the DB2, so `cooldown = 10` (Q6 confirms).
  `all`'s `usable` gate (boss fight or group, not moving) is kept verbatim. The aura is "until cancelled" (DB2 -1):
  3600 s, as `all`'s.
- **Stoneform** on Forever dispels poison, disease and bleed (not curse or magic; R §2.2) and reduces physical damage
  taken by 10%. `all`'s `buff` gate (usable only while a dispellable effect it removes is up) is kept over those three,
  from a file-level list `CLEARS` with a numeric loop (no table built per call; `all`'s built one per call). `handler`
  and `now` spell the three `removeBuff` lines inline (a `now` has no `ipairs`). No `dispellable_bleed` aura exists in
  `all` (it registers curse, poison, disease, magic, enrage): until one does, the gate covers poison and disease, the
  bleed `removeBuff` is a no-op and `buff.dispellable_bleed` reads Hekili's unknown buff, as `all`'s entry already did.
  The bleed lines stay (Forever's real dispel); the file header says so.
- **Cannibalize and Rapid Regeneration are self-channels.** Cannibalize 20577 triggers 20578 and Rapid Regeneration is
  1260270; both carry `Attributes_1` 0x20000040, and 0x40 is SPELL_ATTR1_IS_SELF_CHANNELLED. The player breaks them by
  acting. Both are registered as Hekili channels, `channeled = true` with `cast` = the DB2 duration (10 s for 20578, 6 s
  for 1260270) and `fixedCast = true` (not hasted), so the simulation does not recommend breaking them; `handler` and
  `now` apply the aura as usual (Cannibalize's under ID 20578). The corpse Cannibalize needs is not known to either
  layer, so a priority that names it gates it. If the client's channel reports 20578 rather than 20577 (Q4's
  `UnitChannelInfo` line), `cannibalize` gains `copy = 20578`.
- **Escape Artist** and **Perception** register their 3 s and 20 s auras so `buff.<key>.up` reads true after a cast.
- **Passives as modifiers.** Expansive Mind: `race:RegisterResourceMod( { max = 0.05 } )`, unchanged. Every Gnome class
  on Forever (Warrior, Rogue, Mage, Warlock, Priest: the Eureka! and Expansive Mind class masks, R §2.4) has an
  Expansive Mind of +5% on its resource (20591 mana, 1259802 rage, 1259803 energy), so one declaration serves each.
  Touch of the Grave (Undead, 1260189 / 1260201): a 5% / 10% proc that drains health; it changes no resource, cost or
  cast: **not modelled**. No other race has a resource maximum or a cost modifier (R §3.3).

## 3. The override rule

`Race:RegisterAbility( key )` and `RegisterAura( key )` register into `all` under the same key after `Classes.lua`'s
own registration (the TOC loads race files after `Classes.lua`), so the race's entry replaces `all`'s under that key and
its `id`/`copy` aliases; `ns.applyRace` then writes every owned key (and alias) over the class's after the merge. So a
race key overrides `all`'s stale entry for the live race only; for any other race `all`'s entry stays (inert
registration). The stale `all` IDs this pass replaces:

| `all` key | stale | replaced by | file |
|---|---|---|---|
| ability `berserking` | 26297 (absent) | 20554 | Troll |
| aura `berserking` | 26297, 10 s (absent) | 20554, 10 s | Troll |
| ability `blood_fury` | `id` function: 33702 Mage/Warlock/Priest, 33697 Shaman (absent), 20572 others | 20572 for every class | Orc |
| ability `will_to_survive` | 59752 (absent), off the GCD | 1259718, on the GCD | Human |
| ability `shadowmeld` | 58984 (absent), 120 s | 20580, 10 s | Night Elf |
| aura `shadowmeld` | 58984 (absent) | 20580 | Night Elf |
| ability `stoneform` | 20594 at 120 s, off the GCD | 20594 at 180 s, on the GCD | Dwarf |
| aura `stoneform` (the ability's `auras`) | 65116 (absent) | 20594, 8 s | Dwarf |

The stock entries stay under their old numeric aliases (26297, 58984, ...) in `all`; nothing reads those IDs and the
override keys are what priorities name. "Absent" is the DB2's SpellName; Q2 confirms the client agrees.

## 4. Eureka! scope per class

Eureka!'s effect 0 (aura 108, misc 14, -10%) names spells by class mask against each class's `SpellClassSet` (R §3.2).
The query, run for each class without the `ManaCost > 0` filter of R §3.2 (a percent cost reads 0 in that column, so
Arcane Blast 15% and Shadow Word: Death 401955 12% were missing), restricted to spells taught by a skill line:

```sql
select distinct o.SpellID, n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID
  join SpellPower p on p.SpellID=o.SpellID join spell_skill k on k.spell_id=o.SpellID where o.SpellClassSet=<set>
  and not (((o.SpellClassMask_0 & 4294967295)&<m0>)=0 and ((o.SpellClassMask_1 & 4294967295)&<m1>)=0
  and ((o.SpellClassMask_2 & 4294967295)&<m2>)=0)
```

Rank-1 IDs (the `Rank 1` row, or the unranked one): higher ranks resolve through the class's `copy` lists.

| class (set; masks) | n | rank-1 IDs |
|---|---|---|
| WARRIOR (4; 1784679630/5/1) | 18 | the shipped 17: 78, 845, 1240193, 5308, 7384, 12294, 23881, 1680, 23922, 6572, 6343, 1715, 20252, 694, 6552, 72, 1310222; plus Quick Strike 429765 |
| ROGUE (8; 100794910/2097408/0) | 10 | Ambush 8676, Backstab 53, Eviscerate 2098, Ghostly Strike 14278, Gouge 1776, Hemorrhage 16511, Kick 1766, Mutilate 1310707, Riposte 14251, Sinister Strike 1752 |
| MAGE (3; 549591799/4096/0) | 16 | Arcane Blast 400574, Arcane Explosion 1449, Arcane Missiles 5143, Blast Wave 11113, Blizzard 10, Cone of Cold 120, Fire Blast 2136 and 400618, Fireball 133, Flamestrike 2120, Frost Nova 122, Frostbolt 116, Frostfire Bolt 401502, Ice Lance 1312002, Pyroblast 11366, Scorch 2948 |
| WARLOCK (5; 541165/8650880/0) | 13 | Conflagrate 1293817, Death Coil 6789, Drain Life 689 and 403677, Drain Soul 1120, Hellfire 1949, Immolate 348, Rain of Fire 5740, Searing Pain 5676, Shadow Bolt 686, Shadowburn 17877, Soul Fire 6353, Wrack 1316697 |
| PRIEST (6; 150224528/8388614/0) | 16 | Binding Heal 401937, Flash Heal 2061, Greater Heal 2060, Heal 2054, Holy Fire 14914, Holy Nova 15237, Lesser Heal 2050, Mana Burn 8129, Mind Blast 8092, Mind Flay 15407, Penance 402174, Prayer of Healing 596, Shadow Word: Death 401955 and 1309595, Smite 585, Starshards 10797 |

Quick Strike 429765 is in by the same rule as the other four lists: in the mask, taught by the Arms skill line, 20
rage, on the GCD (Q10 reads its cost with Eureka! up). Left out: Rebuke 425609 (the query's Rogue set, a Paladin skill
line), Felfire 24530 (Mage set, no class, level 0), the Warrior's unranked Execute 20647 (the triggered damage: no
GCD, cost 1, no rank; the cast is 5308's ranks, Warrior.lua). Haunt is in no Warlock skill line in the DB2, so not
listed.

`Gnome.lua` holds the five lists in `EUREKA_SPELLS` keyed by class file name and declares one cost modifier with
`spells = EUREKA_SPELLS[ Hekili.Class.file ]` (`Classes.lua` sets `class.file` from `UnitClassBase` before any race file
runs). A class with no list (Hunter, Shaman, Paladin, Druid: no Gnome Eureka! exists for them) declares no cost
modifier rather than one with `spells = nil`, which would cover every ability. A listed ID the loaded class does not
register (any Mage ID today: no Mage pack) is absent from both layers' scope with no error (`Races.lua`'s `inScope`,
`Modifiers.lua`'s build). The modifier applies only to the ability's declared `spend`/`spendType` (its own slot:
Casts.lua:245, Now.lua:266-273, Adapter.lua:169; the simulation wraps only the declared `spend`, Races.lua:153), so
Eviscerate's combo points are untouched.

## 5. Race tokens

`state.race_token` is UnitRace's second return (`State.lua:516`), matched exactly by `Hekili:NewRace`. Assumed (the
retail tokens; the DB2 has no ChrRaces): `Human`, `Dwarf`, `NightElf`, `Gnome`, `Orc`, `Scourge` (Undead, file
`Undead.lua`), `Tauren`, `Troll`. Gnome, Night Elf and Tauren were already assumed by the shipped files. A wrong token
leaves the file inert and `all`'s stale entries live: checkpoint Q1, first, prints the player's token on every
character the user has, and the answer table renames the `NewRace` argument when one differs.

## 6. Tests (`Virtual/State/spec/races_spec.lua`)

- The race files are read from `Hekili.toc` (`Forever\Races\*.lua`, in order) instead of a hard list, so the TOC and the
  specs cannot drift; `TOKEN` maps a file to its token where they differ (`Undead` → `Scourge`).
- One case per pass: Hekili.toc lists every race file after every class file; for each file, loading its token
  registers exactly its own ability keys (sorted) and its counts of `Hekili.RaceMods.maxMods` / `costMods` (Gnome 1/1
  for a Warrior, the others 0/0); and every file in `OWN` is in the TOC. Since every file runs for every token, a key
  leaking to another race fails it.
- Inert: a token no file answers (`BloodElf`) registers nothing and no modifier (was `Human`, now a real race).
- Per race: the IDs, cooldowns, GCDs and toggles of §2, auras' IDs and durations, and the override over a seeded stale
  `all` entry (`ns.applyRace` writes the race's over the class's): Escape Artist and Shadowmeld (Task 1), Will to Survive
  and Stoneform (Task 2), Blood Fury for Warrior/Mage/Shaman/Druid and Berserking (Task 3), Will of the Forsaken and
  Cannibalize for `Scourge`, nothing for `Undead` (Task 4). Rapid Regeneration and Cannibalize are registered
  `channeled` with `cast` 6 / 10 and `fixedCast` (Tasks 3, 4).
- Eureka! per class: 18 / 10 / 16 / 13 / 16 spells for Warrior / Rogue / Mage / Warlock / Priest, none and no cost
  modifier for a Druid; a percent-cost Arcane Blast (`spend = 0.15`) is priced 0.135 under Eureka!.
- Strict context: for each race token, every registered ability with a `now` (and `now ~= handler`) is cast through
  Families/Now.lua in a fresh VirtualState: `I.nowErrors == 0`, `I.nowRuns == 1`, the ability's aura believed up on the
  player or the target; then 1000 more casts of it allocate 0 bytes (`helpers/alloc.lua`).

## 7. Checkpoint (in game, after the last task)

The client checkout points at `forever-races`; the TOC gained five files, so a full client restart. Every line is under
255 characters and copies through `VSCopy(` (ForeverProbe loaded; `/vscopy` reopens the box).

| # | line (run on each character the user has, Q1 first) | answer → action |
|---|---|---|
| Q1 | `/run VSCopy(UnitRace("player"),select(2,UnitRace("player")),UnitClassBase("player"),Hekili.State.race_token,#Hekili.RaceMods.maxMods,#Hekili.RaceMods.costMods)` | token as §5 → none. Token differs (e.g. `Undead`) → rename that file's `NewRace` argument (and `TOKEN` in the spec), re-test. A Skyborne token → record it in §1's deferred note. Gnome with counts not 1/1 (Warrior, Rogue, Mage, Warlock, Priest) → `Class.file` was not set at load: stop and report. costMods 1 on a non-Gnome Druid → its Clearcasting (Druid.lua), none. |
| Q2 | `/run local f=function(i) return tostring(C_Spell.GetSpellInfo(i)~=nil) end VSCopy(f(26297),f(58984),f(59752),f(65116),f(33702),f(33697))` | all `false` → the overrides are needed as written. Any `true` → that stock ID exists on the client: note it; the override stays (the DB2 values are Forever's). |
| Q3 | `/run local a=Hekili.Class.abilities VSCopy(a.berserking.id,a.blood_fury.id,a.shadowmeld.id,a.will_to_survive.id,a.stoneform.cooldown,a.stoneform.gcd)` | the own race's key shows §2's value, the others `all`'s → none. Own race shows the stale value → `ns.applyRace` did not run: stop and report. |
| Q3b | `/run local u=Hekili.Class.auras VSCopy(u.berserking.id,u.shadowmeld.id,u.stoneform.id,u.blood_fury.id)` | the own race's aura shows §3's ID (Troll 20554, Night Elf 20580, Dwarf 20594, Orc 20572); another race shows `all`'s stale ID or its key string (onLoad found the ID invalid) → none. Own race stale → stop and report. |
| Q4 | cast the race's buff racial, then `/run local i=1 while true do local a=C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL") if not a then break end VSCopy(a.spellId,a.name,a.duration) i=i+1 end` | aura ID and duration as §2 → none. A different ID (e.g. Stoneform not 20594, Cannibalize not 20578) → change that aura's `id`, re-test. |
| Q4b | (Undead, Troll) while Cannibalize or Rapid Regeneration channels: `/run local n,_,_,s,e,_,_,id=UnitChannelInfo("player") VSCopy(n,id,s,e)` | a channel with spell ID 20578 / 1260270 and end - start of 10000 / 6000 ms → none. `nil` (no channel) → drop `channeled` from that ability. Cannibalize channels as 20578 → add `copy = 20578`. Another length → set `cast`. |
| Q5 | a macro `/cast <racial>` then `/run local g=C_Spell.GetSpellCooldown(61304) VSCopy(g and g.duration,g and g.startTime,GetTime())`, for each racial of the race | duration 1.5 for §2's "spell" ones and 0 for "off" → none. Otherwise flip that ability's `gcd`. |
| Q6 | (Night Elf) Shadowmeld, then `/run local s=C_Spell.GetSpellCooldown(20580) VSCopy(20580,s and s.duration,s and s.startTime,GetTime())` | 10 → none. Another value → set `cooldown` to it. |
| Q7 | `/run VSCopy(UnitClass("player"),IsPlayerSpell(1260189),IsPlayerSpell(1260201),IsPlayerSpell(20554),IsPlayerSpell(1259718),IsPlayerSpell(20589))` | which racials the character knows: confirms race/class availability (R §5 Q4). An unexpected `false` for the own race's racial → note it in §8. |
| Q8 | `/run VSCopy(C_Spell.GetSpellDescription(20572),C_Spell.GetSpellDescription(1259710))` | Blood Fury's percent and Wind Blessed's haste: notes only (neither is modelled). |
| Q9 | (Gnome) `/run local e=Hekili.RaceMods.costMods[1] VSCopy(e and e.aura,e and #e.spells,Hekili.Class.file)` | `eureka`, the class's §4 count, the class file → none. `nil` for a Gnome of a §4 class → stop and report. |
| Q10 | (Gnome Warrior) without and then with Eureka! up: `/run local c=C_Spell.GetSpellPowerCost(429765) VSCopy(c and c[1] and c[1].cost)` | 20 then 18 → none (Quick Strike in scope). 20 both times → drop 429765 from the Warrior's list. |

## 8. Not modelled, and why

- **Passives on stats the game reports**: The Human Spirit, Sword / Mace / Axe Specialization, Quickness, Endurance,
  Hardiness, Regeneration, Wind Blessed. Hekili reads crit, haste, hit and health from the client. Wisp Spirit (death
  form), Engineering Specialization (profession), Underwater Breathing and Plainsrunning (movement speed) change nothing a
  rotation reads.
- **Eureka!'s +10% damage** and **Berserking's / Blood Fury's / Elune's Light's stat change**: no damage or stat model in
  Hekili's simulation of these classes; the buffs are tracked so priorities can read `buff.<key>.up`.
- **Touch of the Grave**, **Big Game Hunter**, **Beast Slaying**, **Elemental Insight**: procs or target-type damage; no
  rotation input.
- **Utility actives**: Find Treasure, Cultivation, Skysight, Walk on Air, Read Ley Line (and the Skyborne races, §1).
- **Cannibalize's corpse** and a channel broken by damage or movement: neither layer knows a corpse is near; a broken
  channel's aura runs its full duration in the belief until an observation ends it (the channel itself is modelled, §2).
- **Will to Survive's / Will of the Forsaken's / Escape Artist's / Stoneform's need**: whether a stun, fear, root or
  dispellable effect is on the player. Stoneform keeps `all`'s `buff` gate; the others are `defensives` for the player
  to toggle.
- **The heal and damage reduction amounts** of Stoneform, Shatter Curse, Rapid Regeneration, Cannibalize: Hekili's
  defensives are toggled by the player, not scored.
- No pack names a racial: a priority line is the player's (or a later pack's) choice.
