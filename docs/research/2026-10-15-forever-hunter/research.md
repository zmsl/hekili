# Forever Hunter class pack in the Hekili fork: research brief (2026-10-15)

Read-only research for a spec of `src/Hekili/Forever/Classes/Hunter.lua` beside Warrior.lua and Druid.lua. Hekili HEAD 81a503a8. Build: Forever DB2 1.60.1.70338 (`wowdb`), client 1.60.1.70374. Tags: [DB2] queried here
(section 11 lists the queries); [HK] a Hekili file; [W] the `wow` MCP API index, flavor `forever`; [P] an in-game probe relayed by a repo doc; [I] my inference. Template: `docs/research/2026-10-15-forever-druid/research.md`
("Druid R"), cast-time facts reused by citation from `docs/research/2026-10-15-forever-mage/research.md` ("Mage R"), regen presentation after `.../forever-rogue/research.md` ("Rogue R").

## 0. Read this first

- **The Forever Hunter spends MANA, not focus.** Every one of the 125 `SpellPower` rows on Hunter-class spells has `PowerType 0` (mana); zero rows have PowerType 2 (focus) [DB2 Q1]. `ChrClasses` Hunter has `DisplayPower 0` (mana) [DB2 Q2]. Focus
  exists only on **pet** abilities (Beast Training skill line: Swipe, Pinch, Dismember, Tendon Rip, Savage Rend, Web, Mine!, Dust Cloud, Sonic Blast, Thunderstomp: `power focus`, 10-80) [DB2 Q3]. So the Hunter is a second
  mana caster after the Mage; its resource has **no tick and no Aspect-of-the-Viper-style fixed regen in the data except the Viper aura itself** (section 1).
- **The ranged auto-shot clock is the engine gap.** `PLAYER_SWING` has `swingType` 0 MainHand, 1 OffHand, **2 Ranged** [W `PlayerSwingType`], and `C_SwingTimer.IsTargetWithinSwingRange(swingType)` exists [W]. But both Hekili
  consumers **drop swingType > 1**: `Virtual/State/Sources/Swing.lua:17` and `Virtual/Events/Rows.lua:110`. `UnitRangedDamage` / `UnitRangedAttackSpeed` are **not** in `tools/api_inventory.txt` (only `GetRangedCritChance`, line 94) and
  not in `Virtual/API/Facade.lua`; `UnitAttackSpeed` answers the two melee hands only (Facade.lua:340). The Swing family has two hands (`for h = 1, 2`, Families/Swing.lua). A Hunter pack therefore has **no auto-shot
  clock today**; section 1.3 says what it takes.
- Not settled by the repos: whether `PLAYER_SWING` fires for ranged on Forever (the API has the enum; the probe in [SU]/[V] covered main and off hand only) Q2; whether Aspect of the Viper, Steady Shot and the other
  Season-of-Discovery rune spells are learnable on Forever (Q9); the live talent tree and the Forever-only talents' tree nodes (Q12); the race/class table (no `ChrRaces`/race-class table in the DB2: tables are ChrClasses, Item,
  ItemSparse, SkillLine, SkillLineAbility, Spell*, Talent, TalentTab only [DB2 `wowdb tables`]) so "can a Gnome be a Hunter" is **unknown**; `Races/Gnome.lua:130` says only that no Eureka! spell exists for a Hunter, and
  `Forever/Races/*.lua` has no Hunter list (Races R open question 4 already asks which race/class combinations are creatable). Pet focus is unreadable (section 3).
- Mana base, max, regen: unprobed on a Hunter. Mana is "secret even out of combat" on the Mage [Mage R 0, P] and the facade's `UnitPower` answers the belief for the player only and **0 for any other unit**
  (Facade.lua:230-232), so pet power reads are 0.

## 1. Resource and timing

### 1.1 Mana
- `spec:RegisterResource( Enum.PowerType.Mana )` as Mage R 2.1 / Druid.lua:220. Max and regen are unknown (Q4). Hunter costs mix flat points and **percent of base mana** (`PowerCostPct`) [DB2 Q4]: Multi-Shot 13.9%,
  Concussive Shot 8%, Steady Shot 5%, Scatter Shot 8%, Chimera Shot 6%, Bestial Wrath 12%, Intimidation 8%, Kill Command 1.5%, Flanking Strike 1.5%, Carve 4%, Strider Kick 5.81%. Hekili treats a `spend` below 1 as a fraction of
  max mana (Mage R 2.1), so `spend = 0.139` overstates by max/base mana; Q4 sizes it. Flat costs: Arcane Shot r8 190, Aimed Shot r6 310, Serpent Sting r9 250, Hunter's Mark r4 60, Rapid Fire 100, Volley r3 490.
- **Regen model**: continuous, one rate; reuse the Mage answer (Mage R 2.2: bare resource, ladder pins, `VS.Regen` ignores `casting`). The five-second rule matters less for a Hunter (instants) but the Viper changes it.
- **Aspect of the Viper (415423)**, if learnable: effect 0 = aura 21 (periodic, **3 s**, base 10, misc 0 = mana), effect 1 = aura 79 (damage dealt -10%, misc 127) [DB2 Q5]. Description: "your ranged and melee auto attacks
  regenerate mana but reduce total damage by $s2%" (text cut at 160 characters by the DB2): the base 10 is a percent-of-damage or percent-of-something, unresolved. It has **no cost row** (free), GCD 1.5 s, level 0 (a rune
  spell with `Engrave Belt - Aspect of the Viper` 416084). Model as an aura-gated regen entry (`{ aura = "aspect_of_the_viper", interval = 3, value = ? }`, the Adapter's `Rogue R 2.1` shape) only after Q9 and Q10 pin the value;
  otherwise the pack treats Viper as a plain stance and the ladder calibrates (the rate change exceeds the 2x guard? unknown). Aspect of the Hawk (13165-25296): aura 124 (ranged AP +20 r1) plus aura 42 trigger **Quick
  Shots 6150** (aura 140 +30% ranged haste, 12 s, proc) [DB2 Q6].
- **Rapid Fire (3045)**: L26, 100 mana flat, **300 s** category cooldown, **GCD 0**, 15 s; effects aura 140 (ranged haste +40), 110, 134, 319 (melee+ranged haste +40) [DB2 Q7]. It is a haste buff, not a regen change: it
  shortens the auto-shot period (1.3) and, if it also changes `GetRangedHaste`, nothing the belief reads (the melee-haste read is `GetMeleeHaste`, Sources/Swing.lua:38).
- **Efficiency** (talent 19416, -2% mana per rank on shots/stings, 5 ranks) and **Rapid Recuperation** (Forever, 1223987/1242512: aura 4 dummy 50/100 and aura 134 +50% regen while casting for 15 s after Serpent Sting hit
  / Rapid Killing, Q7) are the two regen/cost passives [DB2]. Cost modifiers go through `RegisterCostMod` only if Q11 shows them family-masked (Mage R 2.4 pattern); else `spend` functions.

### 1.2 Cast times: shots are not hard casts in the Mage sense
- DB2 `CastTime` for Arcane Shot, Serpent Sting, Concussive Shot, Scorpid/Viper Sting, Distracting Shot, Scatter Shot, Chimera Shot, Tranquilizing Shot, Summon Hawk is **-1000000** (a sentinel, not seconds) [DB2 Q4]; Aimed
  Shot **2000** ms (ranks 1-6; the TBC rank-6 spell 27632 and the extra rows 1236188/1294124 say 3000), **Multi-Shot 500 ms**, Steady Shot 437123 **1500**, Sniper Shot 1310687-1310786 **4000** (15 s CD, 365 mana),
  everything else 0. The -1000000 spells are the "instant, next ranged action" family; Hekili must treat them as `cast = 0` with the GCD only. Q12 reads `GetSpellInfo(3044).castTime`.
- Numeric `cast` is hasted by the engine (`Engine/Schema/Spec.lua:772`, Mage R 6): Aimed Shot is `cast = 2`, hasted by **spell haste** (`UnitSpellHaste`), but the client hastes ranged casts by **ranged haste** (Quick Shots, Rapid
  Fire). `UnitSpellHaste` is a secret in combat and the facade returns the last plain read (Mage R 6): Rapid Fire's +40% is **invisible to the cast time**. Use `fixedCast = true` plus a function that reads the aura
  (`cast = 2 / (buff.rapid_fire.up and 1.4 or 1)`), or accept the lag. **Improved Aimed Shot** (Forever 1299437: aura 108 +50% damage, aura 107 misc 10 = +2000 ms cast) turns Aimed Shot into a 4 s cast.
- GCD: 1.5 s for every shot, sting, trap, aspect and mark; **GCD 0**: Rapid Fire, Feign Death, Raptor Strike r1-8 (2973 chain), Bestial Wrath, Kill Command, Readiness (1.0 s) [DB2 Q6].

### 1.3 The auto-shot cycle (the core timing problem)
- Auto Shot 75: L1, cast 0, `SpellRange 114` **"Hunter Range", min 8 / max 35 yards** [DB2 Q8], effect 58 (normalized weapon damage), no cost, no cooldown, no GCD. The ranged weapon's speed is the period. `Shoot Bow/Gun/Crossbow`
  (2480/7918/7919, cast 1000 ms, range 30) are the wand-style "Shoot" spells and are not Auto Shot.
- Classic Hunters weave Aimed/Steady between auto-shots so the cast ends just before the next auto: a shot cast **resets nothing** but a cast started too late **delays the next auto** (the auto swing waits for the cast bar). The
  APL must know the time to the next ranged swing and the cast length: `swings.ranged_remains > cast_time` ("the weave window").
- **Can the existing model express it? No, not as is.** `state.swings` has `mh_*` and `oh_*` only (`State.lua:190`); `swings.mainhand`/`offhand` are the Warrior regen entries' clocks (`Warrior.lua:148,170`); the Swing
  family is two-handed (`Families/Swing.lua`: arrays of 2, `Sources/Swing.lua:17` rejects type 2). `ranged = false` is a constant in `State.lua:1978` and the `Specializations` rows 253/254 (`Constants.lua:125-135`) are
  retail IDs the Forever pseudo-spec never matches. What the pack needs from the engine is **a third hand**:
  1. `Sources/Swing.lua` accepts `swingType == 2` (`hand = 3`), and a `UnitRangedDamage("player")` first return read out of combat (like `readSpeeds`; the API is `AllowedWhenUntainted`, secrecy unprobed, Q1) feeds the speed; the base speed is `UnitRangedDamage` speed unhasted, the haste is the ranged haste (`GetRangedHaste`, not in the facade inventory either);
  2. `Families/Swing.lua` grows from 2 to 3 hands (`anchorT`, `speed`, `base`, `swingRec`), `Rows.lua:110` stops dropping type 2 (the outcome pairing of an auto shot with `UNIT_COMBAT` is the same), and the facade adds `UnitRangedDamage`
     (hybrid, `VS.SwingSpeed(3)`) and `UnitRangedAttackSpeed` if the global exists;
  3. `state.swings.ranged_actual / ranged_speed / ranged_projected` and a `ranged_remains` expression in the Forever Shared layer, mirroring `mh_*`.
  Until then the weave is a **documented gap**: the draft priorities (section 6) ignore the auto-shot timing and the user weaves by feel; the engine offers no honest alternative (the Warrior's `swing_remains` has no ranged analogue).
- **Range gate and the deadzone**: Auto Shot, Aimed, Multi, Arcane, stings, Steady: **8-35 yards** (`SpellRange 114`; Concussive, Distracting, Scatter 15 and 30, Hunter's Mark 100 = "Vision"), melee abilities **5 yards** (`SpellRange 2`:
  Raptor Strike, Mongoose Bite, Wing Clip, Counterattack, Carve, Strider Kick). Use the Charge pattern: `action.<key>.in_range` reading `C_Spell.IsSpellInRange` (Warrior.lua:826 notes it is plain out of combat; in combat unprobed,
  Q6). The pack must not recommend a shot inside 8 yards (the shot is refused) nor a strike outside 5; a "melee deadzone" priority branch (`in_range` of Raptor Strike) is the Survival core. `C_SwingTimer.IsTargetWithinSwingRange(2)`
  is a second source (nil must not be read as out of range [W]); Q6 probes both.

## 2. Ability table

IDs lowest rank first (`first = id`, rest = `copy`); `(L)` base level; cost mana; cast hasted s; cd = max(RecoveryTime, category); all from `wowdb spell` / `spell_info` [DB2 Q4, Q13]. Range = max yards. **SoD/rune** = base level 0
and an `Engrave ...` spell, treated out of scope like Rogue R 1 unless Q9 shows them learnable.

| Key | IDs (L) | Cost | Cast | CD | GCD | Range | Notes |
|---|---|---|---|---|---|---|---|
| `auto_shot` | 75 (1) | 0 | 0 | - | 0 | 8-35 | the swing; section 1.3 |
| `arcane_shot` | 3044, 14281-14287 (6,12,20,28,36,44,52,60) | 25,35,50,80,105,135,160,190 | inst. | **6 s** (cat 1173) | 1.5 | 8-35 | shares cat 1173 with Hydra Shot |
| `multi_shot` | 2643 (18), one rank | **13.9% base** | **0.5** | 6 s (cat 2) | 1.5 | 8-35 | **shares cat 2 with Aimed Shot** |
| `aimed_shot` | 19434, 20900-20904 (20,28,36,44,52,60) | 75,115,160,210,260,310 | **2.0** | 6 s (cat 2) | 1.5 | 8-35 | talent (19434 rank 1 in tree); Improved Aimed Shot +2 s |
| `serpent_sting` | 1978, 13549-13555, 25295 (4,10,18,26,34,42,50,58,60) | 15,30,50,80,115,150,190,230,250 | inst. | - | 1.5 | 8-35 | 15 s, tick 3 s; 1232979-82 are longer-duration variants (21/42/63/84 s, gear?) |
| `scorpid_sting` | 3043 (22) | 9% base | inst. | - | 1.5 | 8-35 | 20 s; one Sting per Hunter per target |
| `viper_sting` | 3034, 14279, 14280 (36,46,56) | 135,175,215 | inst. | 15 s | 1.5 | 8-35 | 8 s mana drain |
| `hunters_mark` | 1130, 14323, 14324, 14325 (6,22,40,58); 1213268 = Forever rank-4 duplicate | 15,30,45,60 | 0 | - | 1.5 | 100 | 120 s; effect 1 aura 127 (ranged AP vs the target) |
| `rapid_fire` | 3045 (26) | 100 | 0 | **300 s** | **0** | self | +40% ranged/melee haste, 15 s |
| `raptor_strike` | 2973, 14260-14266 (1,8,16,24,32,40,48,56) | 10,25,35,45,55,70,85,100 | 0 | 6 s (cat) | **0** | 5 | on-next-swing (melee); 409691-409755 and 415335-415343 are rune chains, ignore |
| `mongoose_bite` | 1495, 14269-14271 (16,30,44,58) | 30,40,50,65 | 0 | 5 s | 1.5 | 5 | "only after you dodge" (usability gate like Overpower) |
| `counterattack` | 19306, **1242634** (30), 20909, 20910 (42,54) | 30,45,65,85 | 0 | 5 s | 1.5 | 5 | after a parry; rank 2 is a Forever row (level 30 like rank 1) |
| `wing_clip` | 2974, 14267, 14268 (12,38,60); **1310180** (12, Forever, slow -50) | 40,60,80 | 0 | - | 1.5 | 5 | 10 s |
| `concussive_shot` | 5116 (8) | 8% base | inst. | 12 s | 1.5 | 8-35 | 4 s daze |
| `scatter_shot` | 19503 (talent; 1988, 23601, 462666 other rows) | 8% base | inst. | 30 s | 1.5 | 15 | 4 s disorient |
| `distracting_shot` | 20736, 14274, 15629-15632 | 20..110 | inst. | 8 s | 1.5 | 8-35 | threat |
| `tranquilizing_shot` | 19801 (60), 1218134 | 270 | inst. | 20 s | 1.5 | 8-35 | |
| `volley` | 1510, 14294, 14295 (40,50,58) | 350,420,490 | channel (6 s) | - | 1.5 | 8-35 | channel, ground target |
| `freezing_trap` | 1499, 14310, 14311 (20,40,60) | 50,75,100 | 0 | 30 s | 1.5 | self | 60 s trap |
| `frost_trap` | 13809 (28) | 60 | 0 | 30 s | 1.5 | self | |
| `immolation_trap` | 13795, 14302-14305 (16..56); 1213271 Forever | 50..245 | 0 | 30 s | 1.5 | self | |
| `explosive_trap` | 13813, 14316, 14317 (34,44,54) | 275,395,520 | 0 | 30 s | 1.5 | self | |
| `feign_death` | 5384 (30) | 80 | 0 | 30 s | **0** | self | aura 66; 360 s |
| `disengage` | 781, 14272, 14273 (20,34,48) | 50,100,150 | 0 | 5 s | 1.5 | 5 | |
| `flare` | 1543 (32) | 50 | 0 | 15 s | 1.5 | 30 | |
| `aspect_of_the_hawk` | 13165, 14318-14322, 25296 (10,18,28,38,48,58,60) | 20..120 | 0 | - | 1.5 | self | aura 124 + Quick Shots proc |
| `aspect_of_the_monkey` | 13163 (4) | 20 | 0 | - | 1.5 | self | |
| `aspect_of_the_cheetah` | 5118 (20) | 40 | | | 1.5 | self | |
| `aspect_of_the_pack` | 13159 (40) | 100 | | | 1.5 | self | |
| `aspect_of_the_wild` | 20043, 20190 (46,56) | 90,115 | | | 1.5 | self | |
| `aspect_of_the_beast` | 13161; **1299445-1299447** Forever ranks 2-4 | 50,70,90,110 | | | 1.5 | self | melee AP, untrackable |
| `aspect_of_the_falcon` | 469145 (Forever? level 0) | 120 | | | 1.5 | self | |
| `aspect_of_the_viper` | 415423 (rune) | 0 | | | 1.5 | self | section 1.1 |
| `trueshot_aura` | 19506, 20905, 20906 (talent); **1299346, 1299348** (L25, L32) | 180, 245 | 0 | - | 1.5 | self | 30-minute aura |
| `bestial_wrath` | 19574 (40); 1310831 Forever | 12% base | 0 | **120 s** | **0** | pet | 18 s; effects target the pet |
| `intimidation` | 19577 (30) | 8% base | 0 | **60 s** | 1.5 | pet | stun via pet's next hit |
| `kill_command` | 409379 (rune, level 0) | 1.5% base | 0 | 60 s | **0** | pet | rune; out of scope |
| `mend_pet` | 136, 3111, 3661, 3662, 13542-13544 (12..52) | 50..480 | channel 5 s | - | 1.5 | 20 | |
| `call_pet` / `dismiss_pet` / `revive_pet` | 883 / 2641 / 982 | 0 / 0 / 0 | 0 / 5 / 10 s | | 1.5 | | pet management |
| Forever-only shots | **Hydra Shot** 1293020 (L60 r4 only, 250, instant, cat 1173); **Sniper Shot** 1310687, 1310785, 1310786 (L40,48,58; 365, **4 s cast**, 15 s CD, range 45, +range aura 107 misc 5); **Summon Hawk** 1293241, 1293525-27 (L25..60; 80..190; cat 6 s) | | | | | | recorded; not in the draft priorities |
| Steady Shot | 437123 (cast 1.5, **5% base**, GCD 1.5); learned by 409957 (rune "Engrave Belt") | | | | | | rune: out of scope until Q9 |
| Kill Shot, Chimera Shot 409433, Explosive Shot, Wyvern Strike, Flanking Strike 415320, Carve 425711, Strider Kick 1317257 | SoD runes | | | | | | out of scope |

- Missing in the DB2 (no spell row): Mongoose bite variants beyond the above, Black Arrow (3674/14296 exist, no cost; probably rune), Beast Lore 1462, Eagle Eye 6197, Eyes of the Beast 1002, Track * (1494, 19878-19885 free), Tame Beast 1515
  (20 s cast), Feed Pet 6991. These are utility; register none.
- **What `now` must carry** (target debuffs are unreadable; modelled from `CastSuccess` as the Mage/Druid DoTs): `serpent_sting` applies debuff 15 s (tick 3 s; refresh by recast), `scorpid_sting` 20 s, `viper_sting` 8 s,
  `hunters_mark` 120 s (all stings are mutually exclusive per Hunter: a new sting `removeDebuff` of the others), `concussive_shot` 4 s, `wing_clip` 10 s, traps place a ground object (no debuff). Self buffs: `rapid_fire` 15 s,
  `aspect_*` (until replaced; only one aspect: each aspect's handler removes the other aspects), `trueshot_aura`, `quick_shots` 12 s (a proc: not modelled; Hawk gives it, invisible in combat, Q5).
  Pet-side: `bestial_wrath` applies a 18 s buff (to the pet's frame; the belief tracks it as a player-side aura keyed by the Hunter's cast), `intimidation` 15 s (the spell's duration).
- Stat of mention: Mongoose Bite and Counterattack are **proc-gated by an unreadable event** (dodge / parry): use the Warrior's `usable`-read pattern (`C_Spell.IsSpellUsable`, Warrior.lua:107), not a `buff`.

## 3. Pets

- **Pet existence**: `UnitExists("pet")` and `UnitIsDead("pet")` are **plain in combat** [Facade.lua:819-830: "plain in combat [W PR14; gate spike]"], so `pet.up` (State.lua:2555 `UnitExists and not UnitIsDead`) works.
- **Broken in the stub**: `UnitHealth`/`UnitHealthMax` return 0 for any unit (facade notes 236-237), so `pet.alive` (State.lua:2561 requires `UnitHealth( "pet" ) > 0`) and `pet.health_pct` are **always false / 100**. The pack must
  use `pet.up` / `pet.exists`, never `pet.alive`. The pet's type (`UnitCreatureFamily("pet")`) is not in the inventory; Hekili's `pet.<key>` resolves a registered pet by `UnitGUID` / NPC ID (State.lua ~2538): the Hunter has
  no registered pets, so `pet.real_pet` is "fake_pet". Nothing in the draft priorities needs the family.
- **Pet focus is unreadable**: `UnitPower("pet")` answers 0 (Facade.lua:231, `unit ~= "player"` returns 0). Pet abilities cost focus in the DB2 [DB2 Q3]; the pet's own AI spends it, so the player-side priority never needs it.
- **Bestial Wrath (19574)**: L40, mana 12% base, **120 s**, GCD 0, 18 s; effect 0 aura 61 (scale), effect 1 aura 79 (damage +50% on the pet), effects 2-12 aura 77 mechanic immunities (pet only) [DB2 Q7]. **The Beast Within
  (1223758, Forever, level 1 passive)**: when the pet is under Bestial Wrath you also rage: +10% damage and -50% mana cost (aura 4 dummy 10 and -50) [DB2 Q14]. If you want the Hunter side: `buff.bestial_wrath` set by the
  cast, mana cost halved for 18 s (a cost modifier through `RegisterCostMod` keyed on `buff.bestial_wrath` and `talent.the_beast_within.enabled`).
- **Intimidation (19577)**: talent, 60 s, the pet stuns on its next hit (24394, 3 s). Kill Command (409379) is a rune spell (60 s, free of GCD) and conditional on the pet being in range of the target [DB2 Q15].
- **Focused Fire** (Forever, 1223755 / 1242139): +2% damage while the pet is active (aura 4 dummy 2) [DB2 Q14]; **Lone Wolf** (1310684) the opposite. These are `talent.*` reads, not pet reads.
- Spirit Bond, Bestial Discipline (pet focus regen), Frenzy, Ferocity, Unleashed Fury: pet-side, no player decisions.

## 4. Talents

`wowdb talents HUNTER` [DB2 Q9]. **The DB2 `Talent` rows are the Classic tree (45 nodes); Forever-only talents exist only as spells (>= 1,000,000) with no tree position, as the Rogue (Rogue R 3).** Keys follow
Classic's snake_case, Hekili's `{ 0, definitionSpell, maxRank }` Warrior shape. `(r)` = ranks in the DB2; Forever-only = **[F]**.

**Beast Mastery** (tier,col): 0,1 `deadly_aspects` 19552 (5); 0,2 `endurance_training` 19583 (5); 1,0 `improved_eyes_of_the_beast` 19557 (2); 1,1 `improved_aspect_of_the_monkey` 19549 (5); 1,2
`thick_hide` 19609 (3); 1,3 `improved_revive_pet` 24443 (2); 2,0 `pathfinding` 19559 (2); 2,1 `bestial_swiftness` 19596 (1); 2,2 `unleashed_fury` 19616 (5); 3,1 `improved_mend_pet` 19572 (2); 3,2 `ferocity` 19598 (5);
4,0 `spirit_bond` 19578 (2); 4,1 `intimidation` 19577 (1); 4,3 `bestial_discipline` 19590 (2); 5,2 `frenzy` 19621 (5, needs Ferocity 4); 6,1 `bestial_wrath` 19574 (1, needs Intimidation). **[F]**: `the_beast_within`
1223758; `focused_fire` 1223755 / 1242139; `rapid_recuperation` 1223987 / 1242512; `careful_aim` 1223984 (AP from Intellect, auras 580 and 598); `improved_revive_pet` 1293639.

**Marksmanship** 0,1 `improved_concussive_shot` 19407 (5); 0,2 `efficiency` 19416 (5); 1,1 `improved_hunters_mark` 19421 (5); 1,2 `lethal_shots` (named "Lethal Attacks" in the row) 19426 (5); 2,0 `aimed_shot` 19434 (1); 2,1
`improved_arcane_shot` 19454 (5); 2,3 `hawk_eye` 19498 (3); 3,1 `improved_serpent_sting` 19464 (5); 3,2 `mortal_shots` 19485 (5, needs Lethal 4); 4,0 `scatter_shot` 19503 (1); 4,1 `barrage` 19461 (3); 4,2 *unnamed* 19491
(3: Piercing Shots in Classic); 5,2 `ranged_weapon_specialization` 19507 (5); 6,1 `trueshot_aura` 19506 (1, needs Barrage 2). **[F]**: `improved_aimed_shot` 1299437 (+50% damage, **+2 s cast**); `improved_stings` 1310661
(aura 108 +20% Serpent Sting damage, aura 107 -6000 Viper Sting cooldown, aura 107 +45000 sting duration); `sniper_shot` 1310687; `hydra_shot` 1293020; `trueshot_aura` ranks 1299346/1299348.

**Survival** 0,0 `improved_tracking` 24293 (3); 0,1 `humanoid_slaying` 19151 (3); 0,2 `deflection` 19295 (5); 1,0 `entrapment` 19184 (5); 1,1 `savage_strikes` 19159 (2); 1,2 `improved_wing_clip` 19228 (5); 2,0
`clever_traps` 19239 (2); 2,1 `survivalist` 19255 (5); 2,2 `deterrence` 19263 (1); 3,0 `survival_tactics` 19376 (2); 3,1 `surefooted` 19290 (3); 3,3 `improved_feign_death` 19286 (2); 4,1 `killer_instinct` 19370 (3);
4,2 `counterattack` 19306 (1, needs Deterrence); 5,2 `lightning_reflexes` 19168 (5); 6,1 *unnamed* 19386 (1, needs Killer Instinct 2: Wyvern Sting in Classic). **[F]**: `survivalists_discipline` 1310496 (aura 108 -40%
trap/Deterrence cooldown); `expose_prey` 1310532 (10% proc 1310726: attacks vs Hunter's Mark target activate Mongoose Bite); `lacerating_strikes` 1310533 (Mongoose Bite adds a bleed, 40%, 1 per 3 s for 21 s); `predators_edge`
1310627 (melee crit damage +30% [aura 108 misc 15], off-hand +50%); `lone_wolf` 1310684; `revelation` 1323410 (aura 107 misc 7, 100); `lacerate` 1299332 (L60 mana 95, 21 s bleed, melee); `wing_clip` variant 1310180.

## 5. Not modelled in the belief and engine gaps (summary)

Crits (procs, Hawk's Quick Shots), the auto-shot clock (1.3), the dodge/parry window (read `IsSpellUsable`), pet damage and pet focus, target debuff durations (unreadable; modelled from `CastSuccess`), Hunter's Mark visibility
(Q8), the deadzone read in combat (Q6), ranged haste (Q1, Q5).

## 6. Draft priorities (SimC style, pack convention, stateless)

Shape after `tools/packs/warrior.lua` / `druid.lua`: `PACKS = { { name, desc, simc = [[...]] } }`, `actions.precombat` first. Classic-era baselines; **the auto-shot weave is a documented gap** (no `swings.ranged_*` yet,
section 1.3), so no line uses it. `in_range` guards as `action.<key>.in_range`. Stings are mutually exclusive: only one sting expression per list. All lines stateless (each evaluation reads belief and cooldowns; no `pool_resource`).

**Marksmanship** (default; Aimed/Multi share cooldown cat 2, Arcane cat 1173):
```
actions.precombat=aspect_of_the_hawk,if=!buff.aspect_of_the_hawk.up
actions.precombat+=/hunters_mark,if=!debuff.hunters_mark.up
actions.precombat+=/call_pet,if=!pet.exists
actions=aspect_of_the_hawk,if=!buff.aspect_of_the_hawk.up&!buff.aspect_of_the_viper.up
actions+=/hunters_mark,if=!debuff.hunters_mark.up&target.level>=level+2
actions+=/rapid_fire,if=toggle.cooldowns
actions+=/serpent_sting,if=!debuff.serpent_sting.up&action.serpent_sting.in_range
actions+=/aimed_shot,if=action.aimed_shot.in_range&talent.aimed_shot.enabled
actions+=/multi_shot,if=active_enemies>1&action.multi_shot.in_range
actions+=/arcane_shot,if=action.arcane_shot.in_range&mana.pct>settings.arcane_mana_pct
actions+=/aspect_of_the_viper,if=mana.pct<settings.viper_pct
actions+=/raptor_strike,if=action.raptor_strike.in_range
```
**Beast Mastery**:
```
actions.precombat=aspect_of_the_hawk,if=!buff.aspect_of_the_hawk.up
actions.precombat+=/call_pet,if=!pet.exists
actions.precombat+=/hunters_mark,if=!debuff.hunters_mark.up
actions=aspect_of_the_hawk,if=!buff.aspect_of_the_hawk.up
actions+=/mend_pet,if=pet.up&settings.mend_pet&!buff.mend_pet.up
actions+=/bestial_wrath,if=pet.up&toggle.cooldowns
actions+=/intimidation,if=pet.up&talent.intimidation.enabled&settings.intimidation
actions+=/rapid_fire,if=toggle.cooldowns
actions+=/serpent_sting,if=!debuff.serpent_sting.up&action.serpent_sting.in_range
actions+=/multi_shot,if=active_enemies>1&action.multi_shot.in_range
actions+=/arcane_shot,if=action.arcane_shot.in_range&mana.pct>settings.arcane_mana_pct
actions+=/raptor_strike,if=action.raptor_strike.in_range
```
Do not use `pet.alive` (always false, section 3); `buff.mend_pet` is a guess (the belief does not model the channel): drop that term until the pet side is probed.

**Survival** (melee core, since Mongoose Bite/Counterattack are the engine of the spec; `action.raptor_strike.in_range` selects the melee branch):
```
actions.precombat=aspect_of_the_hawk,if=!buff.aspect_of_the_hawk.up
actions.precombat+=/call_pet,if=!pet.exists
actions=aspect_of_the_hawk,if=!buff.aspect_of_the_hawk.up&!buff.aspect_of_the_wild.up
actions+=/hunters_mark,if=!debuff.hunters_mark.up
actions+=/call_action_list,name=melee,if=action.raptor_strike.in_range
actions+=/serpent_sting,if=!debuff.serpent_sting.up&action.serpent_sting.in_range
actions+=/arcane_shot,if=action.arcane_shot.in_range
actions.melee=counterattack,if=talent.counterattack.enabled
actions.melee+=/mongoose_bite
actions.melee+=/raptor_strike
actions.melee+=/wing_clip,if=settings.wing_clip&!debuff.wing_clip.up
```
`counterattack` and `mongoose_bite` have no `if=` beyond talent: the engine drops them when `IsSpellUsable` is false (the Warrior's usable gate); the ability's `usable` function must read it (Warrior.lua:107). Trap lines (Immolation, Explosive) are left out on purpose: a ground trap is a placement decision.
Settings the lists name: `arcane_mana_pct`, `viper_pct`, `mend_pet`, `intimidation`, `wing_clip`; add them with `spec:RegisterSetting`.

## 7. Checkpoint questions (each one `/run`, VSCopy, under 255 characters; run on a Hunter with a ranged weapon and a pet)

| # | Question | Line | Answer -> action |
|---|---|---|---|
| Q1 | Ranged attack speed readable | `/run VSCopy(UnitRangedDamage("player"))` plain, then in combat | plain speed -> the base for hand 3; secret -> only PLAYER_SWING durations seed it |
| Q2 | **PLAYER_SWING for ranged** | `/run local f=CreateFrame("Frame");f:RegisterEvent("PLAYER_SWING");f:SetScript("OnEvent",function(_,_,d,t)VSCopy(d,t)end)` then shoot a dummy | type 2 and the duration per auto -> the third hand is feasible |
| Q3 | Ranged range check | `/run VSCopy(C_SwingTimer.IsTargetWithinSwingRange(2),C_Spell.IsSpellInRange(75,"target"))` at 4, 10, 40 yards | true/false pattern; gives the deadzone read |
| Q4 | Power type and mana | `/run VSCopy(UnitPowerType("player"),UnitPowerMax("player",0),C_Spell.GetSpellPowerCost(2643)[1].minCost,GetManaRegen())` | 0 = mana (not focus); max; Multi-Shot flat cost to size the 13.9% |
| Q5 | Hawk's Quick Shots / Rapid Fire aura | `/run VSCopy(pcall(C_UnitAuras.GetPlayerAuraBySpellID,3045))` and `...6150` in combat | readable -> read them; secret -> inferred only |
| Q6 | In-combat range | same as Q3 mid-fight at 4 and 20 yards | plain -> the `in_range` gate is safe in combat |
| Q7 | Aspect of the Viper aura ID | `/run VSCopy(IsSpellKnown(415423),C_UnitAuras.GetPlayerAuraBySpellID(415423))` after casting it | known? aura ID and `amount`/regen (Q10) |
| Q8 | Hunter's Mark / Serpent Sting visibility | `/run local a=C_UnitAuras.GetAuraDataByIndex("target",1,"HARMFUL") VSCopy(a and a.spellId,a and a.duration)` in combat | nil -> modelled from CastSuccess (as written) |
| Q9 | Rune spells learnable | `/run VSCopy(IsSpellKnown(437123),IsSpellKnown(415423),IsSpellKnown(409379),IsSpellKnown(1310687))` | decides Steady/Viper/Kill Command/Sniper Shot in the pack |
| Q10 | Mana change after Viper | `/run VSCopy(UnitPower("player",0))` before and after 10 s of auto shots under Viper | the regen value of the aura entry |
| Q11 | Talent text vs rows | `/run VSCopy(C_Spell.GetSpellDescription(19416),C_Spell.GetSpellInfo(19434).castTime,C_Spell.GetSpellInfo(3044).castTime)` | Efficiency per rank; Aimed 2000 vs 3000; shot cast sentinel |
| Q12 | Live tree | `/fprobe export`, `/reload`, then `/run local e=ForeverProbeDB.export;VSCopy(e.meta.class,#e.spells,#e.talents.trees)` | node list and Forever-only nodes |
| Q13 | Pet reads in combat | `/run VSCopy(UnitExists("pet"),UnitIsDead("pet"),UnitCreatureFamily("pet"),UnitPower("pet"))` | confirms `pet.up`, pet type; focus plain? (the facade answers 0 today) |
| Q14 | Mongoose/Counterattack usable after dodge/parry | `/run VSCopy(C_Spell.IsSpellUsable(14269))` right after a dodge | true only then -> the gate |

## 8. Risks

1. **The auto-shot clock.** The pack cannot express the weave without a third swing hand (1.3); a priority without it will clip Auto Shot every Aimed Shot and mis-time Multi-Shot's 0.5 s cast. Core work, not pack work.
2. **The deadzone.** A recommendation inside 8 or outside 35 yards is a refused action. `IsSpellInRange` in combat is unprobed (Q3, Q6), `IsTargetWithinSwingRange` too; the Survival melee branch needs the same read.
3. **Pet lines.** `UnitHealth` stub 0 means `pet.alive` is false and `UnitPower("pet")` is 0; any Mend Pet / pet-focus line is blind. Pet type, stance and happiness are unread.
4. **Rune spells and Forever redesigns.** Steady Shot, Viper, Kill Command, Kill Shot, Chimera/Explosive and the Hydra/Sniper/Summon Hawk Forever spells are in the DB2, not in any guide; the pack either gambles on an unlearnable
   spell (a dead recommendation) or leaves them out and loses the Season-of-Discovery rotations.
5. **Viability before the ranged swing family.** Viable but degraded: Beast Mastery and Survival lose little (pet and melee carry them); Marksmanship loses the weave, its defining skill, so it is a priority-list stand-in, not a timing coach. Mana is secret, so `mana.pct` lines run on the belief's calibrated pool and Viper/Efficiency only after the ladder converges. Ship it as "shots without weaving" with the gap in the pack description.
6. Rank 2+ cost values are not in the DB2 for Forever-only rows; checked by Q11.

## 9. Races

No Hunter Eureka! list (Gnome.lua:130). Race/class legality unknown (no table). Blood Fury 20572 (Orc, "Orc Racial" skill line, ClassMask 0) is shared (Races R); Berserking 20554 is Troll, ClassMask -1 (all classes incl. HUNTER) [DB2 Q16]; Dwarf's Big Game Hunter 1259721 (+5% vs Beasts) has no rotation effect (Races R 77).

## 10. Open items for the spec

Pseudo-spec ID: Constants rows 253/254/255 are the retail BM/MM/SV specs; pick the next free placeholder (1501 proposed, nothing in `Constants.lua` uses it; stop rule as Druid/Rogue: if Q12 reports a different ID, key by it).

## 11. DB2 queries used (all `~/.local/share/wow-db2/bin/wowdb`, build 1.60.1.70338)

Q1 `"select PowerType,count(*) from SpellPower where SpellID in (select id from spell_info where classes like '%HUNTER%') group by 1"` -> only PowerType 0 (125); Q2 `"select * from ChrClasses"` (Hunter DisplayPower 0); Q3 the
`class_set=9 and id>1235390` listing (Beast Training pet spells `focus`); Q4 `"select id,name,rank,base_level,cast_ms,duration_ms,range_max,power,cost,cooldown_ms,category_cd_ms,gcd_ms,skill_line from spell_info where classes like '%HUNTER%' and skill_line in ('Beast Mastery','Marksmanship','Survival','Hunter')"`
plus `select ... cost_pct ... from spell_info where id in (2643,5116,437123,...)` and `select * from SpellPower where SpellID in (2643,437123,5116,409433)`; Q5 `wowdb effects 415423`; Q6 `wowdb effects 13165 / 6150`; Q7 `wowdb effects 3045 / 19574`; Q8 `"select * from SpellRange where ID in (114,6,2,...)"`
and `"select SpellID,RangeIndex from SpellMisc where SpellID in (75,2643,...)"` (114 for Auto Shot, shots; 2 for strikes; 6 Hunter's Mark); Q9 `wowdb talents HUNTER`; Q13 `"select ... from spell_info where class_set=9 and id>=1000000 ..."` (Forever-only rows);
Q14 `wowdb effects 1223758 / 1223755 / 1223984 / 1223987 / 1299437 / 1310661 / 1310532 / 1310627 / 1310496 / 1310687`; Q15 `wowdb effects 409379 / 19577`; Q16 `"select spell_id,skill_line,class_mask,classes from spell_skill where spell_id in (...)"`.
API facts: `wow_api_event_search PLAYER_SWING`, `wow_api_type_search PlayerSwingType`, `wow_api_search UnitRanged`, `IsSpellInRange`, `SwingTimer` (flavor forever). No WebSearch was needed.

## 12. Pack spec inputs (constants to copy)

```
HUNTER_SPEC = 1501 (proposed; Q12)         resource: Enum.PowerType.Mana (DB2: all 125 rows PowerType 0)     GCD: 1.5 s ("spell"); 0: rapid_fire, feign_death, raptor_strike, bestial_wrath, kill_command
auto_shot 75   range 8-35 (SpellRange 114)   melee range 5 (SpellRange 2)   Hunter's Mark / vision 100 (SpellRange 6)
arcane_shot 3044,14281,14282,14283,14284,14285,14286,14287   cd 6 s (cat 1173)     multi_shot 2643 cost 13.9% base, cast 0.5, cd 6 s (cat 2)
aimed_shot 19434,20900,20901,20902,20903,20904  cast 2.0 (+2.0 with 1299437)  cd 6 s (cat 2)   costs 75,115,160,210,260,310
serpent_sting 1978,13549,13550,13551,13552,13553,13554,13555,25295  15 s, tick 3 s   scorpid_sting 3043 20 s   viper_sting 3034,14279,14280 8 s cd 15 s   hunters_mark 1130,14323,14324,14325 120 s
rapid_fire 3045 cost 100, cd 300 s, 15 s, +40% haste (auras 140, 319), GCD 0       quick_shots 6150 12 s +30%     aspect_of_the_hawk 13165,14318,14319,14320,14321,14322,25296
aspect_of_the_viper 415423 (aura 21, 3 s period, base 10; aura 79 -10% damage)     bestial_wrath 19574 cd 120 s 18 s 12% base GCD 0     intimidation 19577 cd 60 s 15 s 8% base
raptor_strike 2973,14260,14261,14262,14263,14264,14265,14266 cd 6 s GCD 0   mongoose_bite 1495,14269,14270,14271 cd 5 s   counterattack 19306,1242634,20909,20910 cd 5 s   wing_clip 2974,14267,14268 (+1310180)
concussive_shot 5116 cd 12 s 4 s      scatter_shot 19503 cd 30 s 4 s      freezing_trap 1499,14310,14311   frost_trap 13809   immolation_trap 13795,14302,14303,14304,14305   explosive_trap 13813,14316,14317 (traps cd 30 s)
feign_death 5384 cost 80 cd 30 s     disengage 781,14272,14273   steady_shot 437123 (cast 1.5, 5% base; rune)   hydra_shot 1293020   sniper_shot 1310687,1310785,1310786 (cast 4, cd 15 s, 365)
swingType 2 = Ranged (PlayerSwingType)    pet focus: abilities cost PowerType 2; UnitPower("pet") = 0 in the facade
talents (rank-1 id): aimed_shot 19434, barrage 19461, scatter_shot 19503, trueshot_aura 19506, bestial_wrath 19574, intimidation 19577, counterattack 19306, deterrence 19263; [F] improved_aimed_shot 1299437, improved_stings 1310661, the_beast_within 1223758, focused_fire 1223755, careful_aim 1223984, expose_prey 1310532, lacerating_strikes 1310533, predators_edge 1310627, survivalists_discipline 1310496, lone_wolf 1310684
```

**Engine prerequisites.** (1) A third swing hand: `Sources/Swing.lua:17` and `Events/Rows.lua:110` accept `swingType == 2`; `Families/Swing.lua` grows to three hands; the facade gains `UnitRangedDamage` (hybrid, `VS.SwingSpeed(3)`) and a ranged-haste read; `state.swings.ranged_*` and a `ranged_remains` expression in the Forever Shared layer (Q1, Q2). (2) A pet-safe `UnitHealth`/`UnitPower` for `"pet"`, or `pet.alive`/`pet.health_pct` guarded (the pack uses `pet.up` regardless). (3) `in_range` for the 8-35 yard band (min 8, SpellRange 114) read from `C_Spell.IsSpellInRange`, plus `C_SwingTimer.IsTargetWithinSwingRange` as a fallback (Q3, Q6). (4) Mana as in Mage R (one calibrated rate, percent-of-base `spend`s, `VS.Regen` casting argument) and a periodic aura regen entry for the Viper if Q9 learns it. (5) Ranged-haste-aware cast times (Rapid Fire, Quick Shots) since `UnitSpellHaste` is stale in combat. (6) A `Hunter.lua` file and `tools/packs/hunter.lua` using the Warrior/Druid shape; the Forever/Shared aura stubs (`rapid_fire`, `aspect_*`) must be overridden by the Hunter file's real registrations.
