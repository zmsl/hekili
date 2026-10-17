# Forever Mage class pack in the Hekili fork: research brief (2026-10-15)

Read-only research for a spec of `Forever/Classes/Mage.lua` beside the Warrior and Druid. Build: Forever DB2 1.60.1.70338 (`wowdb`), client 1.60.1.70374, beta cap 30, launch 2026-11-04. Hekili HEAD 3e906ad0. Tags: [DB2] = queried here
(queries in section 11); [TDF] = Taco Dog Forever file; [H] = Hekili file; [P] = in-game probe recorded in a repo doc; [G] = guide or Blizzard post relayed by `docs/research/tdf/2026-10-13-forever-mage-rotations.md` (not verified by
us); [I] = my inference. Costs: mana is DB2 points, or "% base" where `SpellPower.PowerCostPct` is set. Paths: `HK` = `/home/zack/src/hekili`, `TDF` = `/home/zack/src/TacoDogForever`, template =
`HK/docs/research/2026-10-15-forever-druid/research.md`, pack shape = `HK/src/Hekili/Forever/Classes/{Warrior,Druid}.lua`.

## 0. Not found / cannot be settled from the repos (read this first)

- **The live Forever Mage talent tree is not in the DB2.** `wowdb talents MAGE` returns the old 49-node tree (Arcane 16, Fire 16, Frost 17) and none of Forever's talent-granted spells (Arcane Blast 400574, Missile Barrage 400588, Ice
  Lance 1312002, Fingers of Frost 400647, Heating Up 400624). No Mage ForeverProbe export exists (`~/src/ForeverProbe/results` has only the W and O runs). Q1 produces it.
- **Mana is secret even out of combat** [P, `docs/research/tdf/2026-10-13-research-findings-for-lanes.md:51`]. Max, base mana and the regen rates, the five-second rule and Spirit are unprobed on a Mage. Nothing in the DB2 gives a Spirit
  regen formula.
- **Only rank 1 of each talent is in the DB2** (ranks 2..5 are absent from `spell_info`), and two rank-1 rows contradict the Forever rank text: Improved Fireball 11069 reads -500 ms (the text: -0.5 s at 5/5) and Arcane Meditation 18462
  reads 50 (the text: 17/33/50).
- **No ItemEffect table** (gem-to-spell is by rank order, 2.3). **Two Evocations** (12051, 1303599) and **two Fire Blasts** (the Era 2136 family and a rune family 400616/400618-23); which one the client knows is a Q (Q9, Q12).
- Rune-era spells (Arcane Barrage 400610, Arcane Surge 425124, Icy Veins 425121, Frozen Orb 440802, Living Bomb, Living Flame, Balefire/Spellfrost Bolt, Regeneration, Rewind Time) sit in the DB2 at base_level 0 with one rank; [G] says Forever offers no runes: the pack ignores them (Druid precedent).

## 1. Scope

**Specs.** Frost (default), Fire, Arcane, as three packs on pseudo-spec 1491 behind `UnitClassBase("player") ~= "MAGE"`, as the Warrior and Druid do; selection by `/hekili priority <name>` (the fork has no `RegisterPackSelector`). The
wand, Polymorph, utility and the rune spells are not priorities. **In Hekili today:** `origin/classic:Classic/Mage.lua` (a WotLK-shaped 5197-line spec with serialized packs, not readable SimC; talent keys are WotLK) and nothing on
`forever` [H]. The Mage is the engine's first spell-caster: Warrior is rage/swing and Druid is mostly instants, so cast bars, channels, pushback, haste and a continuous mana regen are new (sections 6 and 10).

## 2. Mana on Forever

### 2.1 Pool and costs
- `spec:RegisterResource( Enum.PowerType.Mana )` as in Druid.lua:220 [H]. Max and base mana are unknown (Q2). The Adapter forwards `meta.max` (default 100) and no `regen`; a plain `UnitPowerMax` read, if it exists, wins for good (Druid
  spec §2.4).
- **Percent costs** (`PowerCostPct`, % of *base* mana): Arcane Blast 15 (all five ranks), Blink 35, Remove Lesser Curse 10. Everything else is flat points. Hekili treats a `spend` below 1 as a fraction of maximum mana in both layers
  (Druid spec §2.4), so Arcane Blast is `spend = 0.15 * (1 + 1.75 * stacks)` and overstates by max/base mana (gear Intellect); Q2 records both to size it.
- **Arcane Blast stack cost.** Buff 400573: 8 s, 4 stacks; per stack other spells +10% damage (aura 108 misc 0, base 10) and Arcane Blast's own cost +175% (aura 108 misc 14, base 175) [DB2 effects 400573]. Additive: 1 / 2.75 / 4.5 /
  6.25 / 8 x at 0..4 stacks [G, I]. Whether "any other damage spell" ends the stacks is unsettled (Q7).
- **Arcane Power** 12042: 15 s, +30% damage and +30% mana cost (aura 108 base 30, misc 14, masks 549591799/4096 = the Mage cost scope (the damage effect uses 551686903/4096)) [DB2]; a `RegisterCostMod{ aura = "arcane_power", pct = 0.3, spells = ... }` (no `charges`). [G]: now
  requires Presence of Mind (not in the DB2).
- Master of Elements 29074 refunds 10/20/30% of base mana on Fire and Frost crits: crits are unseen, so **not modelled** (`shortcut:`). Frost Channeling 11160: Frost costs -15% (aura 108 misc 14 base -15, rank 1) [DB2]; per-rank rule as
  the Druid's Moonglow (rank 1 x rank).

### 2.2 Regen: what is known and not
- `GetManaRegen()` returns (not-casting, casting) rates; the facade answers `VS.Regen(0,t).est, VS.Regen(0,t,true).est` [HK `Virtual/API/Facade.lua:253`]. **`VS.Regen` ignores its `casting` argument** ("Phase 1 has one rate",
  `Families/Resources.lua:602`), so both returns are the one believed rate. State uses `active_regen` (the second return) once `state.time > 0` and `inactive_regen` before (`State.lua:3513`, `:6312`): the sim runs the single believed
  rate all fight. For a Mage the two differ most of the time.
- **What the belief does for a continuous resource** [H `Resources.lua`]: mana rests at its maximum (`restMax`); `regE` starts at the declared `regen` (0: none is forwarded) and moves by an EMA between ladder pins, each measurement
  dropped if it falls outside 0.5x..2x of the reference (`REGEN_RATIO = 2`, `VirtualState.lua:68`); a zero reference never calibrates (the Druid file's `shortcut:` for energy). The out-of-combat poll reads `GetPowerRegenForPowerType(0)`
  (second return) when plain (`Sources/Power.lua:115`); it reads `GetManaRegen` nowhere. Periodic entries with an `aura` (Bloodrage's pattern) are credited and kept out of the measurement (`pinDelta`). `channel`-gated entries are not
  forwarded (`Adapter.lua:128`).
- **Five-second rule / Spirit.** [G]: Icy Veins says the rule applies on Forever [VA]; Mage Armor lets 50% of regen continue while casting (DB2 aura 134 base 50 on 6117; all three ranks per [G]); Arcane Meditation 17/33/50% [G] (DB2
  rank 1 reads 50, section 0). Regen is Spirit-based in 2 s ticks [G, VA]. **No DB2 number gives the rates; "unknown" until Q2/Q3.** Players call Forever regen faster in combat [G].
- **Consequence.** One calibrated rate is a time-average of casting and idle; **Evocation (x16) always breaks the 2x guard**, so Evocation, gems and drinking must enter as modelled jumps (2.3), and APL lines use `mana.pct`/`mana.deficit`, not `mana.time_to_x`, until Q3.
- **Evocation.** 12051 [DB2]: L20, 8 min, GCD 1.5, 8 s channel, aura 110 base 1500 (mana regen +1500%), aura 134 base 100 (100% regen continues), aura 226 per-second dummy; a channel, Spirit-scaled yield (no fixed 60%). 1303599 [DB2]: 6
  s, no cooldown row, GCD 1.5, no skill line, aura 23 periodic every 500 ms triggering **Mana Surge 1303603** (effect 30 energize base 10, sp_coeff 1): a Forever redesign, 12 ticks, size unknown. 28763 (-60 s per rank on Evocation, aura
  107 misc 11) is a set bonus. Model as a channel (`channeled = true`, `cast = 8` or 6, `start = applyBuff("evocation")`) plus a resource entry `{ aura = "evocation", last = ..., interval = 1 (or 0.5), value = ... }` once Q9 measures
  the yield; before that it is not recommended (`toggle = "cooldowns"`, off the default lists).

### 2.3 Mana gems (the Healthstone pattern)
- Items [DB2 ItemSparse]: Mana Agate 5514, Mana Jade 5513, Mana Citrine 8007, Mana Ruby 8008 (conjured by 759 / 3552 / 10053 / 10054 at L28/38/48/58, 3 s cast, 530/800/1130/1470 mana). Their use spells by rank order [I]: Replenish Mana
  5405 / 10052 / 10057 / 10058, effect 30 energize base 400 / 600 / 850 / 1100 (a die not extracted), **category 30, 60 s** [DB2]. Forever adds a picker spell **Mana Gems 1318827**: "Consume a mana gem, restoring your mana" (category
  1153, **120 s**, instant, no cost; the text lists the gems you hold) [DB2]. Which cooldown binds: Q4.
- Pattern: `Forever/Shared/Consumables.lua` registers `healthstone` with `item = healthstone` (best in bags by `GetItemCount`), `items = {...}`, `bagItem = true`, `cooldown = 120`, `gcd = "off"`, a `usable` testing bags, `IsUsableItem`
  and "must be damaged", and a `handler` of `gain( 0.25 * health.max, "health" )`; it has **no `now`** because an item action has no spell ID and VirtualState sees only spell casts. A `mana_gem` ability copies it with `GetItemCount`
  over `{ 8008, 8007, 5513, 5514 }`, `usable` = "deficit >= restore", `handler` = `gain( 1100/850/600/400, "mana" )`. Whether the use spell (5405..) or 1318827 fires `UNIT_SPELLCAST_SUCCEEDED` (letting the belief see the jump via a
  `now` keyed on the spell) is Q4.

### 2.4 Clearcasting (Arcane Concentration)
- Arcane Concentration 11213 [DB2]: aura 42 (proc) on any damage spell hit, proc chance in the aura row 100 at rank 1 (the 2% per rank, 10% at 5/5, is [I] from Classic and [G]); triggers **Clearcasting 12536**: 15 s, 1 charge, aura 108
  misc 14 base **-1000** (the Classic "free", as in `Classic/Mage.lua:2216`), masks 549591799 / 167936 / 268697664 / 540672 on SpellClassSet 3. Not 16870 (the Druid's, set 7) and not 16246 (Shaman, set 11).
- The Druid's pattern applies (`Druid.lua:538`): `spec:RegisterCostMod{ aura = "clearcasting", pct = -1, charges = 1, spells = { ... } }`. Covered, rank-1 IDs [DB2 mask query]: Arcane Blast 400574, Arcane Explosion 1449, Arcane Missiles
  5143, Blast Wave 11113, Blizzard 10, Cone of Cold 120, Fire Blast 2136 (and 400618), Fireball 133, Flamestrike 2120, Frost Nova 122, Frostbolt 116, Frostfire Bolt 401502, Ice Lance 1312002, Pyroblast 11366, Scorch 2948; the
  unregistered rune spells (Arcane Barrage 400610, Balefire 428878, Living Bomb 400613, Living Flame 401556, Spellfrost 412532) are also covered. Not covered: Polymorph, Counterspell, the armors, Evocation.
- **Missile Barrage** 400589: 15 s buff on a 40% (Arcane Blast) / 20% (Fireball, Frostbolt, Frostfire Bolt) proc; aura 108 misc 1 base -50 (channel time), aura 108 misc 14 base -100 (cost), aura 107 misc 19 base -500 [DB2]: another cost
  mod `{ aura = "missile_barrage", pct = -1, charges = 1, spells = { 5143 } }`; the channel becomes 2.5 s (Q8). Presence of Mind 12043: aura 108 misc 10 base -100, mask0 1073741824 = every hard cast (Arcane Blast, Fireball, Frostbolt,
  Frostfire Bolt, Flamestrike, Pyroblast, Scorch, Polymorph, conjures); it is consumed by the next cast of 0 s or more, so the ability's `cast` reads `buff.presence_of_mind.up`.
- **Known limit.** The proc is unseen, as the Druid's; Mage mitigation: `C_Spell.GetSpellPowerCost` reads 0 under Clearcasting [P gate spike, TDF mage §6], so the cost ladder sees a covered spell usable below its cost (same inference as
  Druid Q6). Q5 tests whether aura 12536 is readable at all.

## 3. Ability table (DB2 ranks, costs, cast, cooldown, GCD)

IDs lowest rank first (first = `id`, rest = `copy`). `(L)` = base_level. Cost = mana; cast in s (unhasted); cd = the larger of RecoveryTime and category recovery. GCD is 1.5 s for every spell below except where
noted (haste scales it, section 6). School mask: 4 fire, 16 frost, 64 arcane, 20 frostfire.

| Key | Rank IDs (levels) | Cost per rank | Cast / duration | Cooldown | Notes |
|---|---|---|---|---|---|
| `frostbolt` | 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304 (4,8,14,20,26,32,38,44,50,56,60) | 25,35,50,65,100,130,160,195,225,260,290 | 1.5,1.8,2.2,2.6,3 x7; chill 5,6,6,7,7,8,8,9,9,9,9 s | 0 | slow -40% (aura 33); Chill source |
| `fireball` | 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306 (1,6,12,18,24,30,36,42,48,54,60,60) | 30,45,65,95,140,185,220,260,305,350,395,410 | 1.5,2.0,2.5,3.0,3.5 x8; DoT 4,6,6,8 x9 s, tick 2 s | 0 | R12 483 + 15 per tick (sp 1.0) |
| `scorch` | 2948, 8444, 8445, 8446, 10205, 10206, 10207 (22..58 by 6) | 50,65,80,100,115,135,150 | 1.5 | 0 | feeds Improved Scorch |
| `pyroblast` | 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809 (talent R1; 24..60 by 6) | 125,150,195,240,285,335,385,440 | 6; DoT 12 s, tick 3 s | 0 | Heating Up -25% cast per stack (400625, 3 stacks, 20 s) |
| `fire_blast` | 2136, 2137, 2138, 8412, 8413, 10197, 10199 (6,14,22,30,38,46,54) | 40,75,115,165,220,280,340 | 0 | **8** | 20 yd; rune family 400616, 400618-400623: cd 15 s, **GCD 0**, L0 (Q12) |
| `frostfire_bolt` | 401502, 1237312, 1237313 (40,50,60) | 205,285,370 | 3.0; DoT 9 s tick 3 s | 0 | slow -40% |
| `arcane_blast` | 400574, 1239696, 1239697, 1239699, 1239700 (talent R1 L20; 30,40,50,60) | 15% base | 2.5 | 0 | stack buff 400573 |
| `arcane_missiles` | 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345 (8,16,24,32,40,48,56,56) | 85,140,235,320,410,500,595,655 | channel 3,4,5 x6 s, 1 s ticks (aura 23 trigger) | 0 | Barrage: 2.5 s, free |
| `ice_lance` | 1312002, 400640, 1240044, 1240045, 1240046, 1240047 (talent R1 L20; 28,34,42,48,56) | 45,55,70,105,120,160 | 0 | 0 | +300% vs Frozen (effect 1 base 300) |
| `arcane_explosion` | 1449, 8437, 8438, 8439, 10201, 10202 (14..54 by 8) | 75,120,185,250,315,390 | 0 | 0 | |
| `flamestrike` | 2120, 2121, 8422, 8423, 10215, 10216 (16..56 by 8) | 195,330,490,650,815,990 | 3.0; DoT 8 s tick 2 s | 0 | one active per Mage [G] |
| `blizzard` | 10, 6141, 8427, 10185, 10186, 10187 (20..60 by 8) | 320,520,720,935,1160,1400 | channel 8 s, tick 1 s | 0 | Improved Blizzard Chill |
| `cone_of_cold` | 120, 8492, 10159, 10160, 10161 (26,34,42,50,58) | 210,290,380,465,555 | 0; slow 6 s | 10 | |
| `blast_wave` | 11113, 13018, 13019, 13020, 13021 (talent R1; 36..60) | 215,270,355,450,545 | 0 | 45 | |
| `frost_nova` | 122, 865, 6131, 10230 (10,26,40,54) | 55,85,115,145 | 0; freeze 8 s | 25 | |
| `counterspell` | 2139 (24) | 100 | 0; lockout 10 s | 30 | **GCD 0**, 30 yd; Improved Counterspell 4 s silence |
| `evocation` | 12051 (20) / 1303599 | 0 | channel 8 s / 6 s | 480 / 0 | section 2.2 |
| `presence_of_mind` 12043, `arcane_power` 12042, `combustion` 11129, `cold_snap` 12472 | talents (Combustion L40) | 0 | PoM until used; AP 15 s; Combustion until 3 crits (stack aura 28682) | 180 (PoM category 1151), 180, 180, 600 | all GCD 0 |
| `ice_barrier` | 11426, 13031, 13032, 13033 (40,46,52,58) | 305,360,420,480 | 60 s absorb 431..811 | 30 | |
| `ice_block` 11958 (15 mana, 10 s, cd 300), `blink` 1953 (L20, 35% base, cd 15), `mana_shield` 1463, 8494, 8495, 10191, 10192, 10193 (40..140) | | | | | |
| armors, `arcane_intellect`, `polymorph`, `shoot` | Frost 168, 7300, 7301 (60/110/170); Ice 7302, 7320, 10219, 10220 (240..500); Mage 6117, 22782, 22783 (L34+; 270..490); AI 1459, 1460, 1461, 10156, 10157 (60..1510); Poly 118, 12824, 12825, 12826 (60..150); wand 5019 | | armors 30 min, AI 1 h, Poly 1.5 s cast / 20-50 s | 0 | one armor at a time; wand not in the data |

## 4. Auras and what `now` must carry

Player auras: secret in combat in general [HK `docs/forever-facade-notes.md`, `C_UnitAuras.GetPlayerAuraBySpellID`]; **whether the Mage's are readable is Q5**; target auras: unreadable in combat. Hence every target effect below is
modelled from `CastSuccess` through `now` (the Warrior/Druid rule) and expires on a believed timer.

| Key | ID (copy) | Unit | Duration / stacks | How the belief gets it |
|---|---|---|---|---|
| `arcane_blast` | 400573 | player | 8 s / 4 | `now` of Arcane Blast: `applyBuff( "arcane_blast", 8, min( 4, stack + 1 ) )`; any other damage cast clears it if Q7 says so |
| `clearcasting` | 12536 | player | 15 s / 1 charge | proc unseen; consumption by the cost mod (2.4) |
| `missile_barrage` | 400589 (talent 400588) | player | 15 s | proc unseen; consumed by Arcane Missiles via its cost mod |
| `heating_up`, `wake_of_fire` | 400625 (talent 400624); 1312934 | player | 20 s / 3; 30 s | crits and kills unseen: not modelled; Pyroblast's cast time is read from the client (Q13) |
| `fingers_of_frost` | 400669 / 400670 (talent 400647) | player | 15 s / 2 | proc unseen; Ice Lance unconditional if Q5 shows the aura readable |
| `ice_barrier` | 11426 (copy 13031..3) | player | 60 s | `now`: `applyBuff( "ice_barrier" )`; absorb not tracked |
| `evocation` | 12051 | player | 8 s | channel `start`; see 2.2 |
| `frostbolt` chill | 116.. | **target** | 5-9 s | `now`: `applyDebuff( "target", "frostbolt", chill )`; slow only, no decision |
| `fireball` DoT | 133.. | target | 4-8 s | `now`: `applyDebuff( "target", "fireball", dot )` |
| `pyroblast` DoT | 11366.. | target | 12 s | `now`: apply; the opener line tests `dot.pyroblast.ticking` |
| `frostfire_bolt` DoT | 401502.. | target | 9 s | `now` |
| `flamestrike` | 2120.. | target | 8 s | `now`; one at a time |
| `fire_vulnerability` | 22959 (Improved Scorch 11095) | target | 30 s / 5 | `now` of Scorch: +1 stack at 33/66/100% chance (rank), 30 s; **personal** [G] |
| `ignite`, `winters_chill` | 412538 (talent 11119); 12579 (talent 11180) | target | 4 s tick 2 s; 15 s / 5 | damage modifiers, no decision, unreadable in combat: not modelled (Q6) |
| `frost_nova` / Frozen | 122.. / 1306620 | target | 8 s / 3 s | `now` applies Nova; Frozen unobservable (Shatter and Lance's +300% are not modelled) |


Only `now` for what the engine cannot learn: the cost and cooldown/GCD of every cast are paid automatically. Mana jumps that are not spell casts (gems, drinking) are the weak spot (2.3).

## 5. Talents (DB2 tree, Hekili key style; Forever-only flagged)

Format as the Warrior/Druid: `key = { 0, definitionSpell, maxRank }`, max ranks = non-zero rank slots in `wowdb talents MAGE`. Confirmed DB2 counts: Arcane 16, Fire 16, Frost 17.
```lua
-- Arcane (16)
arcane_subtlety = { 0, 11210, 2 }, arcane_focus = { 0, 11222, 5 }, improved_channeling = { 0, 11237, 5 }, wand_specialization = { 0, 6057, 2 },
magic_absorption = { 0, 29441, 5 }, arcane_concentration = { 0, 11213, 5 }, arcane_geometry = { 0, 11247, 2 }, arcane_impact = { 0, 11242, 3 },
arcane_resilience = { 0, 28574, 1 }, arcane_shielding = { 0, 11252, 2 }, improved_counterspell = { 0, 11255, 2 }, arcane_meditation = { 0, 18462, 3 },
presence_of_mind = { 0, 12043, 1 }, arcane_mind = { 0, 11232, 5 }, arcane_instability = { 0, 15058, 3 }, arcane_power = { 0, 12042, 1 },
-- Fire (16)
improved_fireball = { 0, 11069, 5 }, impact = { 0, 11103, 5 }, ignite = { 0, 11119, 5 }, flame_throwing = { 0, 11100, 2 },
wake_of_fire = { 0, 11078, 3 }, incineration = { 0, 18459, 2 }, improved_flamestrike = { 0, 11108, 3 }, pyroblast = { 0, 11366, 1 },
burning_soul = { 0, 11083, 2 }, improved_scorch = { 0, 11095, 3 }, improved_fire_ward = { 0, 11094, 2 }, master_of_elements = { 0, 29074, 3 },
critical_mass = { 0, 11115, 3 }, blast_wave = { 0, 11113, 1 }, fire_power = { 0, 11124, 5 }, combustion = { 0, 11129, 1 },
-- Frost (17)
frost_warding = { 0, 11189, 2 }, improved_frostbolt = { 0, 11070, 5 }, elemental_precision = { 0, 29438, 3 }, ice_shards = { 0, 11207, 5 },
frostbite = { 0, 11071, 3 }, improved_frost_nova = { 0, 11165, 2 }, permafrost = { 0, 11175, 3 }, piercing_ice = { 0, 11151, 3 },
cold_snap = { 0, 12472, 1 }, improved_blizzard = { 0, 11185, 3 }, arctic_reach = { 0, 16757, 2 }, frost_channeling = { 0, 11160, 3 },
shatter = { 0, 11170, 5 }, ice_block = { 0, 11958, 1 }, improved_cone_of_cold = { 0, 11190, 3 }, winters_chill = { 0, 11180, 5 },
ice_barrier = { 0, 11426, 1 },
-- Forever-only (not in the DB2 tree; node and rank from [G], definition spells from DB2): the real list needs Q1
arcane_blast = { 0, 400574, 1 }, missile_barrage = { 0, 400588, 1 }, ice_lance = { 0, 1312002, 1 }, fingers_of_frost = { 0, 400647, 2 },
heating_up = { 0, 400624, 1 },
```
- **Forever-only** (5): Arcane Blast (row 3, 11 points), Missile Barrage (16), Ice Lance (11), Fingers of Frost (row 5, needs Ice Lance; 2 ranks), Heating Up (row 4, needs Pyroblast; was Hot Streak until 10-01) [G, TDF mage §1].
  **Changed**: Wake of Fire replaces Improved Fire Blast (DB2 11078: -1 s Fire Blast cooldown per rank, +25/+50% crit after a kill, buff 1312934); Incineration adds Ice Lance and Arcane Blast to its crit scope (18459); Ignite is
  personal and 40% of the crit over 4 s; Winter's Chill, Improved Scorch and Elemental Precision are rebuilt [G].
- **Max-rank disagreements, DB2 (Era) vs [G]**: Shatter 5 vs 3 (17/33/50%); Wake of Fire 3 vs 2; Incineration 2 vs 3; Burning Soul 2 vs 3; Elemental Precision 3 vs 5; Magic Absorption 5 (a TBC talent in the DB2). Q1 resolves; until then
  the DB2 counts are the table's.

## 6. Cast-time modelling

- **Numeric `cast` is hasted by the engine**: `Engine/Schema/Spec.lua:772` rewrites a number to `return N * haste` unless `fixedCast`; a function must multiply by `haste` itself. `haste` = `1/(1 + spell_haste)`, with `spell_haste =
  Facade.UnitSpellHaste( "player" ) / 100` (`State.lua:2348`); the facade's `UnitSpellHaste` is **hybrid**: `VS.SpellHaste( now ).est`, the last plain read (default 0, so haste is stale in combat) [`Families/Player.lua:89`]. Berserking
  (Troll, +10% cast and attack speed, 10 s) and gear change it; the stock casts need no haste code.
- **`cast_time`**: `action.X.cast_time` is `ability.cast` (`State.lua:4963`); `execute_time` = `max( gcd.execute, cast )`. Casts: Frostbolt `cast = 3 - 0.1 * talent.improved_frostbolt.rank` (per rank table), Fireball `3.5 - 0.1 *
  talent.improved_fireball.rank` (Q10: DB2 says -0.5 per rank), Pyroblast `6 * ( 1 - 0.25 * buff.heating_up.stack )` (reads the client cast time; Q13), Arcane Blast 2.5, Presence of Mind `buff.presence_of_mind.up and 0 or ...`. All
  times are then `* haste` in the function form. `gcd = "spell"` (1.5 s, hasted) for everything but Counterspell, Presence of Mind, Arcane Power, Combustion, Cold Snap (GCD 0 in the DB2, `gcd = "off"`).
- **`casting` / `channeling`**: the `casting` aura reads `UnitCastingInfo/UnitChannelInfo( "player" )` (`Engine/Schema/Spec.lua:1488-1519`; channels over 10 s are ignored, so Evocation's 8 s and Blizzard's 8 s pass); `state.casting` is the
  ability key, `channeling` is `buff.casting.v3 == 1`. At reset the sim queues `CAST_FINISH` (or `CHANNEL_FINISH` and a `CHANNEL_TICK` every `tick_time`) and **delays to the cast end** (`State.lua:6405-6455`). A channeled ability's
  **`handler` is not run** (`RunHandler`, `State.lua:6140`): use `start` (at the cast), `tick` and `finish`; the Druid's Hurricane uses `start`. Declare `channeled = true`, `cast = <seconds>`, `tick_time = 1` for Arcane Missiles
  (Barrage: 0.5 s ticks, 2.5 s), Blizzard and Evocation.
- **What the facade reports** [HK `Facade.lua:616-650`]: `UnitCastingInfo( "player" )` and `UnitChannelInfo( "player" )` are `kept(..., "hybrid")`: the **real call**, returned only if every return is plain (`plainAll`), else `nil`
  (player casts are plain [W PR9]); the target's are modelled from `VS.TargetCast`, `notInterruptible` false and a fixed icon. So a player cast reads true in and out of combat; the *target* cast bar (Counterspell timing) is a model.
- **What the belief does**: `CastStart` sets `castAb`/`castEnd` from the event's end time, `CastDelay` moves `castEnd` (pushback is seen as it happens), `CastSuccess` clears it, `ChannelStart/Update/Stop` do the same for channels
  (`Families/Casts.lua:97-138`). A hard cast's GCD starts at the cast start (`Now.lua:292`), the length is `1.5/haste` until the game's own edge teaches it (`gcdLearned`). `now` runs at `CastSuccess`, **the end of the cast**, so a
  Frostbolt's chill and a Fireball's DoT land when the cast completes (correct); for a channel `now` runs at success (the start, if Forever fires SUCCEEDED then: Q8), not at the end.
- **Not modelled in the sim**: pushback from damage taken (Burning Soul 70% avoidance, Improved Channeling, Ice Barrier stop it [G]); Hekili's sim finishes every cast on time. Casting while moving: `moving` is `VS.Moving()`
  (`Facade.lua:353`); give hard casts `usable = not moving` unless Presence of Mind is up; `gcd` moves only Ice Lance, Fire Blast, Arcane Explosion.

## 7. Draft priorities (SimC style, pack convention, stateless)

Format as `tools/packs/warrior.lua` / `druid.lua`: `actions.precombat` first, `settings.*` guards, `known` gates the missing ranks, no state kept between evaluations. Settings: `mage_armor` (bool), `ab_stacks` (1-4, default 3),
`pyro_stacks` (1-3, default 2), `scorch` (bool), `frostfire` (bool), `gem_deficit` (num, default 1000), `use_wand` (bool). `armor_up` is a StateExpr (any of three armor auras). Classic-era baselines: Frostbolt spam, Scorch then
Fireball, Arcane Missiles/Frostbolt filler; Forever's talent spells layer on top.
```
# Frost (default): Frostbolt, Ice Lance on Fingers of Frost
actions.precombat=arcane_intellect,if=!buff.arcane_intellect.up
actions.precombat+=/mage_armor,if=settings.mage_armor&!armor_up
actions.precombat+=/ice_armor,if=!armor_up
actions.precombat+=/frost_armor,if=!armor_up
actions.precombat+=/frostbolt
actions=counterspell,if=toggle.interrupts&debuff.casting.up&debuff.casting.v2=0
actions+=/evocation,if=toggle.cooldowns&mana.pct<20
actions+=/mana_gem,if=mana.deficit>=settings.gem_deficit
actions+=/cold_snap,if=toggle.cooldowns&cooldown.ice_block.remains>0&cooldown.frost_nova.remains>0&cooldown.cone_of_cold.remains>0
actions+=/call_action_list,name=aoe,if=active_enemies>=3
actions+=/ice_lance,if=buff.fingers_of_frost.up
actions+=/frostbolt
actions+=/shoot,if=settings.use_wand
actions.aoe=cone_of_cold
actions.aoe+=/ice_lance,if=buff.fingers_of_frost.up
actions.aoe+=/blizzard,if=active_enemies>=5
actions.aoe+=/arcane_explosion,if=active_enemies>=5

# Fire: Scorch to 5 on long fights, Pyroblast on Heating Up stacks, Fire Blast on cooldown, Fireball (Frostfire Bolt from 40)
actions.precombat=<as Frost>,/pyroblast,if=!dot.pyroblast.ticking
actions=<counterspell, evocation, mana_gem as Frost>
actions+=/combustion,if=toggle.cooldowns&!buff.combustion.up&(debuff.fire_vulnerability.stack>=5|!settings.scorch)
actions+=/call_action_list,name=aoe,if=active_enemies>=3
actions+=/fire_blast,if=buff.wake_of_fire.up
actions+=/scorch,if=settings.scorch&(debuff.fire_vulnerability.stack<5|debuff.fire_vulnerability.remains<5)
actions+=/pyroblast,if=buff.heating_up.stack>=settings.pyro_stacks
actions+=/fire_blast
actions+=/frostfire_bolt,if=settings.frostfire
actions+=/fireball
actions+=/shoot,if=settings.use_wand
actions.aoe=flamestrike,if=active_enemies>=4&!dot.flamestrike.ticking
actions.aoe+=/blast_wave,if=active_enemies>=3
actions.aoe+=/arcane_explosion

# Arcane: build Arcane Blast stacks, spend them on another damage spell, Missiles on Barrage, Power + Presence of Mind as the burst
actions.precombat=<as Frost, ending in /frostbolt>
actions=<counterspell, evocation, mana_gem as Frost>
actions+=/arcane_power,if=toggle.cooldowns&!buff.arcane_power.up&mana.pct>=70
actions+=/presence_of_mind,if=toggle.cooldowns&buff.arcane_power.up&!buff.presence_of_mind.up
actions+=/call_action_list,name=aoe,if=active_enemies>=3
actions+=/arcane_missiles,if=buff.missile_barrage.up&(buff.arcane_blast.stack>=2|buff.missile_barrage.remains<4)
actions+=/arcane_blast,if=buff.clearcasting.up&buff.arcane_blast.stack>=2&buff.arcane_blast.stack<4
actions+=/arcane_blast,if=buff.presence_of_mind.up
actions+=/fire_blast,if=buff.arcane_blast.stack>=settings.ab_stacks
actions+=/arcane_missiles,if=buff.arcane_power.up&buff.arcane_blast.stack>=settings.ab_stacks
actions+=/frostbolt,if=buff.arcane_blast.stack>=settings.ab_stacks
actions+=/arcane_blast
actions+=/shoot,if=settings.use_wand
actions.aoe=flamestrike,if=active_enemies>=4&!dot.flamestrike.ticking
actions.aoe+=/arcane_explosion
```
Notes: `known` skips unlearned ranks, so one text serves levels 1-60. Arcane Blast stacks and Clearcasting are believed (section 4), so the Arcane list is the least reliable; thresholds are judgment [G, I], no sim backs them.

## 8. Races

Mage races [DB2 spell_skill]: Human (Perception 20600, Will to Survive 1259718), Gnome, Undead (Will of the Forsaken 7744, Cannibalize 20577), Troll (Berserking 20554: +10% speed 10 s / 180 s, off GCD). **Gnome is wired** in `Forever/Races/Gnome.lua`: Eureka! for MAGE is 1259817 with its cost scope `MAGE = { 400574, 1449, 5143, 11113, 10, 120, 2136, 400618, 133, 2120, 122, 116, 401502, 1312002, 11366, 2948 }` (masks 549591799 / 4096) and Expansive Mind 20591 (+5% max mana); the Mage file must register those rank-1 IDs (an unregistered one is absent, harmless). Berserking and Cannibalize are stock `all`; Cannibalize's mana jump is not modelled.

## 9. Open questions for the in-game checkpoint (each one `/run`, VSCopy, under 255 characters)

Run on a Mage (a Gnome or Troll helps). `VSCopy` is ForeverProbe's (`~/src/ForeverProbe/Copy.lua`; `/vscopy` reopens it). Ranked by importance.

| # | Question | Line | Answer -> action |
|---|---|---|---|
| Q1 | **Live talent tree** | `/fprobe export`, `/reload`, then `/run local e=ForeverProbeDB.export;VSCopy(e.meta.class,#e.spells,#e.talents.trees,e.stances.num)` | node list, ranks -> the Forever-only block of section 5; resolves the rank disagreements |
| Q2 | **Mana readability**: max, regen rates, in and out of combat | `/run VSCopy(UnitPowerMax("player",0),GetPowerRegenForPowerType(0),GetManaRegen())` | plain -> `meta.max` and a `regen` seed; secret -> ladder only, `mana.pct` guards stay as written |
| Q3 | **Five-second rule**: casting vs idle rate | `/run VSCopy(GetTime(),GetManaRegen())` idle full mana, right after a cast, and 6 s later | two different pairs -> a bimodal rate (needs `VS.Regen`'s casting argument, section 10); equal -> one rate is right |
| Q4 | **Mana gem**: which cooldown, does a spell event fire | `/run local c=C_Spell.GetSpellCooldown(1318827) VSCopy(c.startTime,c.duration,C_Item.GetItemCooldown(5514))` after using a gem | 60 s (Replenish) vs 120 s (Mana Gems); decides the ability's `cooldown` and whether a `now` can see it |
| Q5 | **Clearcasting aura** readable in combat | `/run VSCopy(pcall(C_UnitAuras.GetPlayerAuraBySpellID,12536))` on a proc; also `/run VSCopy(C_Spell.GetSpellPowerCost(133)[1].minCost)` | readable -> read it, drop the inference; secret -> usable-below-cost is the signal (Druid Q6) |
| Q6 | **Ignite / target debuffs** | `/run local a=C_UnitAuras.GetAuraDataByIndex("target",1,"HARMFUL") VSCopy(a and a.spellId,a and a.duration)` in combat after a Fire crit | nil in combat -> Ignite stays unmodelled (no decision); readable -> `dot` reads |
| Q7 | **Arcane Blast stacks**: cost per stack, which cast clears them | `/run local c=C_Spell.GetSpellPowerCost(400574) VSCopy(c[1].minCost,pcall(C_UnitAuras.GetPlayerAuraBySpellID,400573))` after each Blast, then after a Frostbolt | 1/2.75/4.5/6.25/8 x confirmed; clear-on-other-cast confirmed -> `now` rule of section 4 |
| Q8 | **Cast info + channel**: SUCCEEDED timing, Barrage length | `/run VSCopy(UnitCastingInfo("player"))` mid-Frostbolt; `/run VSCopy(UnitChannelInfo("player"))` in Arcane Missiles, once with Barrage | end - start per rank; channel 5.0 vs 2.5 s; fixes when a channel's `now` runs |
| Q9 | **Which Evocation / yield** | `/run VSCopy(IsSpellKnown(12051),IsSpellKnown(1303599),IsSpellKnown(1318827),IsSpellKnown(400574),IsSpellKnown(1312002))` | the known one -> section 2.2 entry; mana before/after from a screenshot or Q2 |
| Q10 | **Talent text vs rows**: Improved Fireball, Arcane Meditation | `/run VSCopy(C_Spell.GetSpellDescription(11069),C_Spell.GetSpellDescription(18462))` and `/run VSCopy(C_Spell.GetSpellInfo(25306).castTime,C_Spell.GetSpellInfo(25304).castTime)` | per-rank value for the cast-time and regen rules |
| Q11 | **Spell haste** plain in combat? | `/run VSCopy(UnitSpellHaste("player"),GetHaste())` with and without Berserking, in combat | secret -> haste stale at its last out-of-combat read (section 10) |
| Q12 | **Fire Blast family**: 8 s or 15 s, GCD | `/run VSCopy(IsSpellKnown(10199),IsSpellKnown(400623),C_Spell.GetSpellCooldown(2136).duration)` after a cast | which ids to register; cooldown and `gcd` |
| Q13 | **Pyroblast cast time** at Heating Up 0..3 | `/run VSCopy(C_Spell.GetSpellInfo(11366).castTime)` at each stack | 6/4.5/3/1.5 s -> the cast-time rule reads the client |
| Q14 | **School lockout shape**: Loss of Control for a silenced Mage | `/run local d=C_LossOfControl.GetActiveLossOfControlData(1) VSCopy(d and d.locType,d and d.lockoutSchool,d and d.timeRemaining)` while locked out | `lockoutSchool ~= 0`: the shared generators skip it (section 10) |

## 10. Risks and what the belief lacks

- **First spell-caster.** The sim's cast bars are ideal (no pushback, no movement cancel; the belief does see `CastDelay`); `cast` becomes a function of talents and buffs, so tests need `knownRank` and `buff.*` doubles (Warrior KIT table).
- **Spell haste is stale in combat.** `UnitSpellHaste` is secret in combat [W PR2/PR4]; the facade returns the last plain read, so Berserking (+10%) is invisible mid-fight; cast times and the GCD (`1.5/haste` until `gcdLearned`) lag by that much.
- **Mana regen is one number.** `VS.Regen` ignores `casting`; the Mage needs an idle/casting pair, and Evocation, drinking and gem jumps exceed the 2x calibration guard and are rejected. Core fixes, not pack work: a second rate selected by `casting`, an Adapter-forwarded `regen` meta, a `gain` for item spells. Until then no APL line uses `mana.time_to_x`.
- **School lockouts and interrupts.** `Forever/Shared/Auras.lua` builds `loss_of_control` from `C_LossOfControl` events with `lockoutSchool == 0` only, and has no `silenced` or `interrupted` aura. A Counterspell/Pummel on the Mage
  (school lockout, `lockoutSchool ~= 0`) is invisible: the priority keeps recommending the locked school (Q14). Needs a school-aware generator and `locked_out` StateExpr in Shared/Auras.lua before Mage ships.
- **The belief lacks**: crit events (Ignite, Combustion's three crits, Heating Up, Master of Elements); the Frozen state (Shatter, Ice Lance +300%); procs without events (Clearcasting, Missile Barrage, Fingers of Frost, Wake of Fire's
  kill); Arcane Blast stack clearing if Q7 shows other-spell clearing (the belief only sees casts of tracked abilities); item casts (gems); target casts (Counterspell timing, a model); the moving flag only via `GetUnitSpeed`.

## 11. DB2 queries used (all `~/.local/share/wow-db2/bin/wowdb`, build 1.60.1.70338)

- Items and races: `ItemSparse` by `Display_lang like '%Mana Agate%'` etc.; `wowdb spell "Replenish Mana"`; `SpellCooldowns` for 1303599 and 12051; `spell_skill` by `skill_line like 'Racial - Human%'` (Gnome, Undead, Troll). Engine reads: `Facade.lua` 230-260, 616-650; `Families/{Resources,Casts,Now,Player}.lua`; `State.lua` 3513, 4963, 6140, 6312, 6405-6455; `Engine/Schema/Spec.lua` 760-775, 1480-1535.
- Tree: `wowdb talents MAGE` (ranks = non-zero `r1..r5`; `select tab,count(*) from talent_info where class='MAGE' group by tab` -> 16/16/17). Spells: `select
  s.id,s.name,s.rank,s.base_level,s.school_mask,s.cast_ms,s.duration_ms,s.power,s.cost,s.cost_pct,s.cooldown_ms,s.category_cd_ms,s.gcd_ms,s.range_max from spell_info s join spell_skill k on k.spell_id=s.id where k.classes like '%MAGE%'
  and k.skill_line in ('Frost','Fire','Arcane')`.
- Effects: `wowdb effects <id>` for 12051, 1303599, 1303603, 12043, 12042, 12536, 11213, 400573, 400589, 6117, 18462, 11160, 22959, 11095, 1318827, 5405..10058; masks: `select * from SpellEffect where SpellID=12536`. Clearcasting scope:
  `select distinct o.SpellID,n.Name_lang from SpellClassOptions o join SpellName n on n.ID=o.SpellID join SpellPower p on p.SpellID=o.SpellID join spell_skill k on k.spell_id=o.SpellID where o.SpellClassSet=3 and not
  (((o.SpellClassMask_0 & 549591799)=0) and ((o.SpellClassMask_1 & 167936)=0) and ((o.SpellClassMask_2 & 268697664)=0) and ((o.SpellClassMask_3 & 540672)=0))`.

## 12. Pack spec inputs (constants to copy)
```lua
-- Pseudo-spec 1491, class "MAGE"; RegisterResource( Enum.PowerType.Mana ); RegisterOptions( { package = "Frost" } )
local FROSTBOLT = { 116, 205, 837, 7322, 8406, 8407, 8408, 10179, 10180, 10181, 25304 } local FROSTBOLT_COST = { 25, 35, 50, 65, 100, 130, 160, 195, 225, 260, 290 } local FROSTBOLT_CAST = { 1.5, 1.8, 2.2, 2.6, 3, 3, 3, 3, 3, 3, 3 }
local FROSTBOLT_CHILL = { 5, 6, 6, 7, 7, 8, 8, 9, 9, 9, 9 }
local FIREBALL = { 133, 143, 145, 3140, 8400, 8401, 8402, 10148, 10149, 10150, 10151, 25306 } local FIREBALL_COST = { 30, 45, 65, 95, 140, 185, 220, 260, 305, 350, 395, 410 }
local FIREBALL_CAST = { 1.5, 2, 2.5, 3, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5, 3.5 } local FIREBALL_DOT = { 4, 6, 6, 8, 8, 8, 8, 8, 8, 8, 8, 8 }
local SCORCH = { 2948, 8444, 8445, 8446, 10205, 10206, 10207 } local SCORCH_COST = { 50, 65, 80, 100, 115, 135, 150 }
local PYROBLAST = { 11366, 12505, 12522, 12523, 12524, 12525, 12526, 18809 } local PYROBLAST_COST = { 125, 150, 195, 240, 285, 335, 385, 440 }
local FIRE_BLAST = { 2136, 2137, 2138, 8412, 8413, 10197, 10199 } local FIRE_BLAST_COST = { 40, 75, 115, 165, 220, 280, 340 } -- cd 8, gcd 1.5; rune family 400616, 400618-400623 (Q12)
local FROSTFIRE_BOLT = { 401502, 1237312, 1237313 } local FROSTFIRE_COST = { 205, 285, 370 }
local ARCANE_BLAST = { 400574, 1239696, 1239697, 1239699, 1239700 } -- 15% base, cast 2.5, buff 400573 (8 s, 4 stacks, +175% cost, +10% other damage)
local ARCANE_MISSILES = { 5143, 5144, 5145, 8416, 8417, 10211, 10212, 25345 } local MISSILES_COST = { 85, 140, 235, 320, 410, 500, 595, 655 } local MISSILES_CHANNEL = { 3, 4, 5, 5, 5, 5, 5, 5 }
local ICE_LANCE = { 1312002, 400640, 1240044, 1240045, 1240046, 1240047 } local ICE_LANCE_COST = { 45, 55, 70, 105, 120, 160 }
local ARCANE_EXPLOSION = { 1449, 8437, 8438, 8439, 10201, 10202 } local EXPLOSION_COST = { 75, 120, 185, 250, 315, 390 }
local FLAMESTRIKE = { 2120, 2121, 8422, 8423, 10215, 10216 } local FLAMESTRIKE_COST = { 195, 330, 490, 650, 815, 990 }
local BLIZZARD = { 10, 6141, 8427, 10185, 10186, 10187 } local BLIZZARD_COST = { 320, 520, 720, 935, 1160, 1400 } local CONE_OF_COLD = { 120, 8492, 10159, 10160, 10161 }  -- cost 210,290,380,465,555; cd 10
local BLAST_WAVE = { 11113, 13018, 13019, 13020, 13021 } -- cost 215,270,355,450,545; cd 45
local FROST_NOVA = { 122, 865, 6131, 10230 }             -- cost 55,85,115,145; cd 25; freeze 8
local ICE_BARRIER = { 11426, 13031, 13032, 13033 }       -- cost 305,360,420,480; cd 30; 60 s
local ARMOR = { frost = { 168, 7300, 7301 }, ice = { 7302, 7320, 10219, 10220 }, mage = { 6117, 22782, 22783 } }
local ARCANE_INTELLECT = { 1459, 1460, 1461, 10156, 10157 } -- cost 60,185,520,945,1510; 1 h
local POLYMORPH = { 118, 12824, 12825, 12826 }
-- single spells: counterspell 2139 (100, cd 30, gcd off), evocation 12051 (cd 480, 8 s; or 1303599, 6 s), presence_of_mind 12043 (cd 180, off),
-- arcane_power 12042 (cd 180, 15 s), combustion 11129 (cd 180), cold_snap 12472 (cd 600), ice_block 11958 (15, cd 300, 10 s), blink 1953 (35% base, cd 15)
-- auras: arcane_blast 400573, clearcasting 12536, missile_barrage 400589, heating_up 400625, fingers_of_frost 400669/400670, wake_of_fire 1312934,
--   fire_vulnerability 22959 (30 s, 5), winters_chill 12579, ignite 412538, combustion 28682, frozen 1306620, mana_surge 1303603
-- mana gems: items AGATE 5514, JADE 5513, CITRINE 8007, RUBY 8008; restores 400/600/850/1100 (spells 5405, 10052, 10057, 10058; category 30, 60 s); Forever spell 1318827 (category 1153, 120 s)
spec:RegisterCostMod( { aura = "clearcasting", pct = -1, charges = 1, spells = { 400574, 1449, 5143, 11113, 10, 120, 2136, 400618, 133, 2120, 122, 116, 401502, 1312002, 11366, 2948 } } )
spec:RegisterCostMod( { aura = "missile_barrage", pct = -1, charges = 1, spells = { 5143 } } )
spec:RegisterCostMod( { aura = "arcane_power", pct = 0.3, spells = { 400574, 1449, 5143, 11113, 10, 120, 2136, 400618, 133, 2120, 122, 116, 401502, 1312002, 11366, 2948 } } )
-- Arcane Blast spend = 0.15 * ( 1 + 1.75 * buff.arcane_blast.stack ); GCD 1.5 s (gcd = "spell") except the off-GCD spells above; Frost Channeling -15% Frost cost per rank 1 row
-- Gnome Eureka! MAGE 1259817 and Expansive Mind 20591 are already in Forever/Races/Gnome.lua; Troll Berserking 20554 and Undead Cannibalize 20577 are stock
```

