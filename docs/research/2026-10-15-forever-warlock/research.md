# Forever Warlock class pack in the Hekili fork: research brief (2026-10-15)

Read-only research for a spec of `Forever/Classes/Warlock.lua` beside Warrior, Druid and (planned) Mage. Build: Forever DB2 1.60.1.70338 (`wowdb`), client 1.60.1.70374, beta cap 30, launch 2026-11-04. Hekili HEAD 81a503a8.
Tags: [DB2] = queried here (queries in section 10); [TDF] = `docs/research/tdf/2026-10-13-forever-warlock-rotations.md` (Blizzard deep dive, ForeverDB, guides, relayed and not verified by us; "TDF §n" = its section); [H] = Hekili file; [P] = in-game probe
(`docs/research/tdf/2026-10-13-probe-session-W-results.md`, a Warrior session); [I] = my inference. Paths: `HK` = `/home/zack/src/hekili`; template = `HK/docs/research/2026-10-15-forever-mage/research.md` ("Mage §n": its mana, cast-time, cost-mod and
lockout findings are reused, not repeated); depth = `...-forever-druid/research.md`; file shape = `HK/src/Hekili/Forever/Classes/Warrior.lua` (rank lists, `knownRank`, `RegisterResource`, `RegisterTalents`, abilities with `now`, `RegisterStateExpr`, `RegisterSetting`) and
`tools/packs/{warrior,druid}.lua` (SimC text per pack).
## 0. Not found / cannot be settled from the repos (read this first)

- **The brief's premises that the DB2 refutes** [DB2]: there is **no Felguard** (Summon Felguard 427733/427748/431754 exist at base_level 0/30 with no skill line and no class: Season of Discovery rune residue); **no Dark Pact** (talent 18220 has no SpellName row; the spell name search is empty);
  **no Curse of Shadow** in the trainer (402791 is an SoD row, level 0, 20% base, 180 s, no skill line); **no Backlash** (no SpellName row); **no Curse of Agony** (it is **Bane of Agony**; Curse of Doom is **Bane of Doom**; both are Banes, section 2.2).
  **Curse of the Elements is Forever's own** (440892, 1311676, 1311677, 1311680 at levels 20/30/40/50): its class mask is 0, so `spell_skill` does not list it (the TDF data bug: the generator dropped it); it must be registered by ID.
- **The live Forever Warlock talent tree is not in the DB2.** `wowdb talents WARLOCK` returns a 50-node hybrid (Affliction 17, Demonology 17, Destruction 16): Classic nodes with Forever descriptions on some and **four ghost nodes with no spell name** (18213, 17864, 18220 Affliction; 18748 Demonology).
  Wrack (1316697), Incinerate (412758..), Pandemic, Malediction, Soul Harvest, Decimation, Shadow and Flame, Fire and Brimstone, Demonic Brand, Demonic Energies, Demonic Pact, Bane of Havoc are **spells with no tree node**. No Warlock ForeverProbe export exists (`~/src/ForeverProbe/results` has only the W and O runs). Q1 produces it.
- **Only rank 1 of each talent is in the DB2, and the rank-1 row holds the maximum-rank total** for several (same finding as Mage §0): Bane 17788 reads -500 ms (Shadow Bolt, Immolate, Incinerate) and -2000 ms (Soul Fire) for a 5-rank talent whose text is -0.1 s and -0.4 s per rank [TDF]; Improved Corruption 17810 reads -2000 ms (instant at 5/5, so -0.4 s a rank);
  Cataclysm 17778 reads -10 (cost %, aura 108 misc 14; TDF says 3/3 for -10%, the DB2 tree says 5 ranks: Q10). Per-rank rule for the pack: row value / max rank.
- **Mana, health, Spirit and shard counts in combat are unprobed on a Warlock.** Mana is secret even out of combat [P, Mage §0]; player `UnitHealth` is "unprobed" (cleanup Q11, `Virtual/State/Sources/Player.lua:166`); `UnitHealth("pet")` is secret with no pet [P PR12]; pets and shards were never probed (a Warrior session). Section 8 lists the lines.
- **No ItemEffect table**: Soulstone, Healthstone and Spellstone use-spells are matched to items by rank order [I], as the Mana Gem case in Mage §2.3.
## 1. Scope

**Specs.** Affliction (default), Destruction, Demonology as three packs on pseudo-spec 1491 behind `UnitClassBase("player") ~= "WARLOCK"` (as Warrior and Druid; selection by `/hekili priority <name>`). Nothing exists on `forever` today; `origin/classic:Classic/Warlock.lua` carries only serialized packs (TDF §10). The pet bar
(Spell Lock, Devour Magic, Firebolt), Fear, utility, summoning rituals, Eye of Kilrogg and the wand are not priorities. **New engine ground beyond the Mage:** DoT/Bane/Curse upkeep on a target whose auras are unreadable, channels as the main spenders, a health-for-mana spell, a bag-count resource (shards) and a pet.
**Forever differences that shape everything** [TDF §1, DB2 rows below]: Banes/Curses split with a one-Bane-one-Curse-per-target rule; Curse of Shadow gone; Wrack (level 40 channel) and Incinerate (level 40) are talent spells; DoTs are not snapshotted and haste does not speed DoTs or channels; base numbers are about half Classic's with higher coefficients (DoTs are 40-60% of damage).
## 2. Resources

### 2.1 Mana, Life Tap, Dark Pact (absent)
- `spec:RegisterResource( Enum.PowerType.Mana )` as Druid.lua:220 [H]. Mana modelling is the Mage's: one calibrated regen number, ladder-only if `UnitPowerMax` is secret, Evocation-like jumps rejected by the 2x guard (Mage §2.2). Warlock-specific: no Evocation, no gems; the big jumps are **Life Tap** and **Soul Harvest** (+100% regen for 10 s, 100% of regen continues while casting; aura 1242853, spell 437032 [DB2]).
- **Percent costs** [DB2 `cost_pct`]: Summon Imp 80%; Succubus, Incubus, Voidwalker, Felhunter, Inferno 100%; Fear 15%; Curse of Exhaustion 8%; Soul Link 20%; Bane of Havoc 5%; Create Soulstone 85%; Portal of Summoning 12%; Metamorphosis/Chaos Bolt/Shadowflame/Fel Armor/Demon Charge/Demonic Howl are SoD residue (do not register). Hekili treats `spend < 1` as a fraction of max mana (Mage §2.1): `spend = 0.8` etc. overstates by (max mana / base mana).
- **Life Tap** (1454, 1455, 1456, 11687, 11688, 11689 at levels 6/16/26/36/46/56; GCD 1.5, instant, no cast time; `power` column reads `health`, cost 0) [DB2]. Effect 0 is a dummy (effect 3) with base 20/65/130/210/300/420 (+1 per level); description `Converts (m1 + SPI*1) * (1 + Improved Life Tap m1/100) Health into the same Mana`. **Health and mana move 1:1** (TDF's "half" was a text fix of 2026-09-24).
  Improved Life Tap 18182 (+10/+20%; effect 4 dummy, 2 ranks). Demonic Energies 1225214 gives the pet `m2`% of the mana gained.
- **What a Life Tap `now` can write** [H `Virtual/State/Families/Now.lua`]: `gain( n, "mana" )` (a tracked resource; `ResourceShift` plus an Energize log row). The `now` environment has **no Spirit and no stat read** (NAMES = math helpers, buff/debuff/talent, resources, `knownRank`, `now`, `combat`), so `n` is a rank table of the base value, optionally plus a constant Spirit estimate
  (`LIFE_TAP_SPIRIT`, a setting-less constant; the real figure is `VS.Stat( "UnitStat" )`'s out-of-combat cache, unreachable from `now`: **shortcut:** understate by Spirit, the ladder or the next plain mana read corrects it). **What it cannot write: health.** `gain/spend` raise "now: no tracked resource" for anything not in `def.resources`; the player health belief
  (`Families/Player.lua:44`, a 0..1 fraction) is written only by the 1.5 s plain-read poll (`Sources/Player.lua:166`) and decays to its default of 1.0 when the read is secret. So after a Life Tap the belief's health is stale (high), and **no APL line may gate on `health.pct` or the cost of Life Tap**; the game's own `C_Spell.IsSpellUsable( 1454 )` (plain [W PR14]) is the floor guard (TDF probe 3, Q4 here).
  The sim `handler` can do both for the cost ladder (`spend( n, "health" )` is a Hekili verb, `gain( n, "mana" )`), but Hekili's `state.health` reads `UnitHealth( "player" )` through the facade (`Facade.lua:264`: belief x max), so it is only as good as the poll.
- **Dark Pact does not exist** (section 0). There is no mana-from-pet button; Demonic Energies feeds the pet instead.
- **APL rule:** Life Tap on `mana.pct` (a `RegisterStateExpr( "mana_pct" )` guarding max 0) below a setting (default 35, the sim's threshold [TDF §3]) and `settings.tap_floor` (health % the player accepts, default 40, used only if Q4 shows a plain health read; else omitted).

### 2.2 Soul Shards (bag item 6265)
- **Soul Shard is item 6265** (ItemSparse; quality 1, bonding 1, stack 1: each shard is a bag slot) [DB2]; the Healthstone's `GetItemCount` row is plain [W PR13: `GetItemCount` "P 47/47", zero for owned-none] and `C_Item.GetItemCount` is documented `AllowedWhenUntainted` on Forever (`wow_api_search`), so a shard count is readable the same way `Consumables.lua:81` counts Healthstones. **Reagent Economy 1225503** removes vendor reagents, **not** shards [TDF §1].
- **Model it as a StateExpr, not a resource:** `spec:RegisterStateExpr( "soul_shards", function() return GetItemCount( 6265 ) end )` with `local GetItemCount = ns.Facade.C_Item.GetItemCount` (the Consumables pattern; no `Enum.PowerType.SoulShards` is needed and the belief has no item channel). Spenders `usable = soul_shards > 0` (or `soul_shards - 1` for one already queued) and a `handler` that decrements nothing: the sim never spends the item, so one cast per list evaluation is correct and a sequence of two shard spells in a recommendation queue is a **known over-recommendation** (`shortcut:` upgrade by tracking a `shards_spent` StateExpr set from `handler`, reset each `reset_precast`).
- **Sinks** (one shard each [TDF §6, VAN]): Soul Fire, Shadowburn (refund 20% per Shadow and Flame rank; and a kill within the 8 s window grants one), Summon Voidwalker/Succubus/Incubus/Felhunter (Imp is free), Create Healthstone/Soulstone [VAN], Ritual of Summoning (the forum says none). **Sources:** Drain Soul ticks (a progressively rising chance, guaranteed on a kill of a non-trivial target), Shadowburn kill, Decimation window makes Soul Fire free. The count changes at events the belief never sees, so **read the count live each evaluation** (plain; Q2).
- **Items the Warlock creates** (all in `Forever/Shared/Consumables.lua` only for Healthstone): the 15 Healthstone items are `HEALTHSTONES = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 }` (Major, Greater, plain, Lesser, Minor; each Improved 2/2, 1/2, plain). The Warlock file adds: `create_healthstone` as a **cast** (6201, 6202, 5699, 11729, 11730; levels 10/22/34/46/58; 95/240/475/750/1120 mana; 3 s; GCD 1.5), `usable` only when no stone is in the bags
  (`select( 2, healthstone() )` false inside the shared function; export it from Consumables or recount with `GetItemCount` over `HEALTHSTONES`) and shards > 0 [VAN]; `create_soulstone` (693, 20752, 20755, 20756, 20757; 85% base mana, 3 s; items by rank order Minor 5232, Lesser 16892, Soulstone 16893, Greater 16895, Major 16896 [I]); `create_spellstone` (2362, 17727, 17728; 500/750/1000; 5 s; items Spellstone 5522, Greater 13602, Major 13603) and
  `create_firestone` (6366, 17951, 17952, 17953; 500..1100; 3 s; items Lesser 1254, Firestone 13699, Greater 13700, Major 13701). **Spellstone and Firestone are weapon imbues** on Forever (apply spells Firestone 758, 17945, 17947, 17949; Spellstone 1237152, 1237156, 1237159 [TDF §1]): a precombat "apply" line needs `C_Item.GetWeaponEnchantInfo` (probed plain out of combat [W PR13]); the Soulstone use is a target-friendly 30 min buff (resurrection 20707, 20762..5), not a rotation item.
  None gets a `now` (item use has no spell ID, Consumables.lua header); a cast of Create Healthstone does have a spell ID, but the bag change is read live, so no `now` either.
## 3. Ability table (DB2 ranks, costs, cast, cooldown, GCD)

IDs lowest rank first (first = `id`, rest = `copy`). (L) = base_level. Cost = mana; cast in s unhasted; GCD 1.5 s for every spell here except where marked; cd = larger of RecoveryTime and category recovery. School 32 shadow, 4 fire. Spell haste does not speed DoT ticks or channel length on Forever [TDF §1]: channels use `fixedCast`-style durations.

| Key | Rank IDs (levels) | Cost per rank | Cast / duration / tick | Cooldown | Notes |
|---|---|---|---|---|---|
| `shadow_bolt` | 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 (1,6,12,20,28,36,44,52,60,60) | 25,40,70,110,160,210,265,315,370,380 | 1.7,2.2,2.8,3,3,3,3,3,3,3 | 0 | Bane -0.1 s a rank; Shadow Trance = instant |
| `immolate` | 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 (1,10,20,30,40,50,60,60) | 25,45,90,155,220,295,370,380 | 2.0; DoT 15 s, tick 3 s | 0 | Bane -0.1 a rank; direct hit then DoT |
| `corruption` | 172, 6222, 6223, 7648, 11671, 11672, 25311 (4,14,24,34,44,54,60) | 35,55,100,160,225,290,340 | 2.0; DoT 12,15,18,18,18,18,18 s, tick 3 s | 0 | Improved Corruption -0.4 s a rank |
| `bane_of_agony` | 980, 1014, 6217, 11711, 11712, 11713 (8,18,28,38,48,58) | 25,(55),90,130,170,215 | instant; 24 s, tick 2 s | 0 | rank 2 (1014) has no class mask; effect 6/10/../46 per tick, back-loaded; Amplify Curse +50% |
| `bane_of_doom` | 603 (60) | 300 | instant; 60 s, one hit at the end (1742) | 60 | same Bane slot; not castable on players |
| `bane_of_havoc` | 1225228 (talent, L1) | 5% base | instant; 300 s | 0 | **GCD 0** [TDF]; copies 15% of your damage to the cursed target; Bane slot of that mob |
| `curse_of_the_elements` | 440892, 1311676, 1311677, 1311680 (20,30,40,50) | 50,100,150,200 | instant; 300 s | 0 | +4/6/8/10% all magic schools; resist -30/45/60/75 (effect 0 aura 22 misc 126) |
| `curse_of_recklessness` | 704, 7658, 7659, 11717 (14,28,42,56) | 35,60,90,115 | instant; 120 s | 0 | armor reduction, ignores Fear; no AP debuff here |
| `curse_of_weakness` | 702, 1108, 6205, 7646, 11707, 11708 (4,12,22,32,42,52) | 20,35,70,95,130,175 | instant; 120 s | 0 | -4 melee AP.. rank 1 |
| `curse_of_tongues` | 1714, 11719 (26,50) | 80,110 | instant; 30 s | 0 | -50% cast speed |
| `curse_of_exhaustion` | 18223 (talent) | 8% base | instant; 12 s | 0 | -30% speed (aura 33) |
| `amplify_curse` | 18288 (talent) | 0 | instant; 30 s window | 180 | **GCD 0**; +50% next Weakness/Bane of Agony (aura 108 misc 8); Exhaustion -20 (aura 107 misc 3) |
| `siphon_life` | 18265, 18879, 18880, 18881 (30,38,48,58) | 150,205,285,365 | instant; 30 s, tick 3 s | 0 | talent; heals; Wrack prerequisite |
| `drain_life` | 689, 699, 709, 7651, 11699, 11700 (14,22,30,38,46,54) | 55,85,135,185,240,300 | channel 5 s, tick 1 s | 0 | the 403677-403689 family (15 s, cooldown 15 s, SoD) is **not** registered |
| `drain_soul` | 1120, 8288, 8289, 11675 (10,24,38,52) | 55,125,210,290 | channel 15 s, tick 3 s (aura 86) | 0 | shard chance per tick; stops if another spell is cast (2026-10-01) |
| `wrack` | 1316697 (talent, L40) | 200 | channel 6 s, tick 1 s, 36 shadow (sp 0.143) | 0 | +10% (effect 1 aura 271) from your other Shadow DoTs for 6 s; can proc Nightfall |
| `searing_pain` | 5676, 17919, 17920, 17921, 17922, 17923 (18,26,34,42,50,58) | 45,68,91,118,141,168 | 1.5 | 0 | Emberstorm trims the cast; Demonic Brand |
| `conflagrate` | 1293817, 1293818, 17962, 18930, 18931, 18932 (25,32,40,48,54,60) | 100,130,165,200,230,255 | instant | **10** | talent; needs and consumes Immolate (Shadow and Flame decides) |
| `shadowburn` | 17877, 18867, 18868, 18869, 18870, 18871 (20,24,32,40,48,56) | 105,130,190,245,305,365 + shard | instant; 8 s kill window | **15** | talent |
| `soul_fire` | 6353, 17924 (48,56) | 305,335 + shard | 6.0 (Bane -0.4/rank, Decimation -40%) | 60 (Decimation -90%) | |
| `incinerate` | 412758, 1293812, 1293813 (40,50,60) | 205,265,325 | 2.5 (Bane -0.1/rank) | 0 | talent; effect 1 +25% vs Immolated target |
| `rain_of_fire` | 5740, 6219, 11677, 11678 (20,34,46,58) | 295,605,885,1185 | channel 8 s, tick 2 s (aura 226) | 0 | at the ground target |
| `hellfire` | 1949, 11683, 11684 (30,42,54) | 645,975,1300 | channel 15 s, tick 1 s; hits you | 0 | off by default |
| `death_coil` | 6789, 17925, 17926 (42,50,58) | 435,525,600 | instant; horror 3 s | 120 | emergency, cooldowns toggle |
| `life_tap` | see 2.1 | health | instant | 0 | |
| `fear`, `howl_of_terror` | Fear 5782, 6213, 6215 (8,32,56; 15% base; 1.5 s cast); Howl 5484, 17928 (40,54; 150,200; 2.0 s; cd 40) | | | | utility |
| `demon_armor` | 706, 1086, 11733, 11734, 11735 (20,30,40,50,60); Demon Skin 687, 696 (1,10) | 275,520,800,1150,1580; 50,120 | 30 min | 0 | precombat |
| `shadow_ward` | 6229, 11739, 11740, 28610 | 135..320 | 30 s | 30 | |
| `soul_link` | 19028 (talent, aura 25228) | 20% base | until demon dies | 0 | 30% of damage taken goes to the demon (effect 1 aura 81) |
| `fel_domination` | 18708 (talent) | 0 | 15 s window | 300 | **GCD 0**; next summon cast -5.5 s (aura 107 misc 10 base -5500) and -50% cost (aura 108 misc 14) |
| `demonic_sacrifice` | 18788 (talent) | 0 | instant; 2 h | 0 | **GCD 0** (no gcd on the row); kills the demon |
| `health_funnel` | 755, 3698, 3699, 3700, 11693, 11694, 11695 (12..60) | health 11..79 | channel 10 s | 0 | pet upkeep, not in the APL |
| summons | Imp 688 (L1, 80%), Voidwalker 697 (10), Succubus 712 (20), Incubus 713 (20), Felhunter 691 (30) (100%) | % base + shard (not Imp) | **10 s cast** | 0 | GCD 1.5; Inferno 1122 (50; 100%; cd 3600) |
| `subjugate_demon` | 1098, 11725, 11726 (30,44,58) | 300,500,700 | 3 s | 0 | was Enslave Demon |
| `shoot` | 5019 | 0 | wand | | damage does not scale with spell power |

Auras the pack tracks beyond the dots: `shadow_trance` 17941 (10 s, the Nightfall proc; aura 108 misc 10 base -100: next Shadow Bolt cast time -100%), `decimation` 440873 (10 s), `shadow_and_flame` 1293816 (Shadow +, 20 s, after Conflagrate) and 426311 (Fire +, 20 s, after Shadowburn),
`amplify_curse` 18288, `soul_harvest` 1242853, `demon_armor` 706..11735, `soul_link` 25228, `fel_domination` 18708, sacrifice effects 18789-18792, `improved_shadow_bolt` debuff 17794 (12 s, +4% a rank, **unreadable and unobservable**: crit-driven, not modelled).
## 4. Auras and what `now` must carry (the DoT-heavy burden)

**Player auras** (Shadow Trance, Decimation, Shadow and Flame, Amplify Curse, Soul Harvest, armor, Soul Link, Fel Domination, sacrifice) are `C_UnitAuras.GetPlayerAuraBySpellID` reads: secret in combat in general (facade notes: "secret in combat; errors when tainted"), **the Warlock's readability is Q5/Q6** (TDF assumed "yes"; the gate spike proved usability, not auras).
If secret, `buff.shadow_trance.up` is never true and the instant Shadow Bolt is missed; the fallback is the usability signal: `C_Spell.GetSpellPowerCost( 686 )` or the cast time `C_Spell.GetSpellInfo( 686 ).castTime` reading 0 under the proc (Mage §2.4 / Q13 pattern), which needs a read in the `cast` function.
**Target debuffs are unreadable in combat** (facade notes; TDF §7), so every DoT, Bane and Curse is modelled from `CastSuccess` through `now` (Warrior's Rend/Thunder Clap precedent: `applyDebuff( "target", "rend", REND_DURATION[ knownRank( REND ) ] or 9 )`, Warrior.lua:1267) and expires on a believed timer; there is no hit/resist evidence and no combat log (CLEU registration is forbidden; the virtual rows are only the bot's own casts).

| Key | Spell ID(s) | Unit | Duration | `now` (and refresh rule) |
|---|---|---|---|---|
| `corruption` | 172.. (copy) | target | by rank 12/15/18 s | `applyDebuff( "target", "corruption", CORRUPTION_DURATION[ knownRank( CORRUPTION ) ] or 18 )`; a recast **replaces** the timer (no pandemic carry-over [VAN], probe 6) |
| `bane_of_agony` | 980.. | target | 24 s | `removeDebuff( "target", "bane_of_doom" )`, `removeDebuff( "target", "bane_of_havoc" )`, then apply; refresh **at expiry only** (damage back-loaded, an early refresh resets the ramp [TDF §3]) |
| `bane_of_doom` | 603 | target | 60 s | removes the other Banes; consumed at the end (the 1742 hit) so `remains` doubles as "doom pending" |
| `bane_of_havoc` | 1225228 | target (another mob) | 300 s | `applyDebuff`; separate slot per target, so it needs `active_dot.bane_of_havoc` not `dot.` |
| `curse_of_*` (Elements, Recklessness, Weakness, Tongues, Exhaustion) | see section 3 | target | 300/120/120/30/12 s | each removes the other four on the same target (one Curse per Warlock per target); Amplify Curse's buff is consumed by the next Weakness or Bane of Agony (`removeBuff( "amplify_curse" )` in their `now`) |
| `siphon_life` | 18265.. | target | 30 s | apply |
| `immolate` | 348.. | target | 15 s | apply; **Conflagrate's `now` removes it** unless Shadow and Flame ranks cover it (`settings.sf_ranks`; expected-value rule from TDF §7) |
| `wrack` | 1316697 | target | 6 s | channel `start` applies |
| `drain_soul`, `drain_life` | 1120.., 689.. | target | 15 s / 5 s | channel `start`; stopped early only when the believed cast ends (`ChannelStop`) |
| `shadow_trance` | 17941 | player | 10 s | proc unseen; a Shadow Bolt cast consumes it: `removeBuff( "shadow_trance" )` in Shadow Bolt's `now`. If Q5 shows the aura readable the belief is overridden by the read |
| `decimation` | 440873 | player | 10 s | proc unseen (below 35% health: unobservable); read it or ignore |
| `shadow_and_flame` Shadow / Fire | 1293816 / 426311 | player | 20 s | `now` of Conflagrate / Shadowburn |
| `amplify_curse` | 18288 | player | 30 s | `now` of Amplify Curse |
| `demon_armor` | 706..11735 | player | 30 min | `now` of the armor cast; the armor is cleared by the Demon Skin cast |
| `soul_link` | 25228 | player | indefinite | `now` of Soul Link; ends if the demon dies (the pet read, section 5) |
| `demonic_sacrifice` | 18789 / 18790 / 18791 / 18792 | player | 2 h | `now` of Sacrifice; which one depends on the demon (section 5) |

Target swap: a DoT belongs to a guid. The belief files debuffs under the target slot; "Banes and Curses lose tracking after you drop and re-acquire a target" (a Blizzard known issue of 2026-09-24 [TDF §7]) is therefore also what the belief does: **after a retarget every DoT reads down and the APL re-recommends them** (a clip, never a miss). `active_dot.<x>` needs the per-guid table the Druid bleeds use (Druid.lua); check there before promising multi-target.
## 5. Pets

- **Summons** (10 s casts; creature IDs in the effect rows [DB2]): Imp 416 (688), Voidwalker 1860 (697), Succubus 1863 (712), **Incubus 185317** (713, a separate summon here), Felhunter 417 (691); Inferno (1122) summons creature 89, Ritual of Doom 177193. Felguard (213450) is a rune summon with no trainer entry [DB2, TDF §1]: not registered.
- **What the pack needs:** (a) "a pet exists and is alive" for the precombat line and `soul_link`; (b) which kind, for Master Demonologist, Demonic Sacrifice's choice and (rarely) the pet-dependent list branches; nothing needs pet health or pet energy.
- **What Hekili reads** [H `State.lua`]: `pet.up`/`exists`/`active` is `UnitExists( "pet" ) and not UnitIsDead( "pet" )` (State.lua:2558) after a loop over `state.pet.<token>` entries with `expires > query_time` (filled by `summonPet`, State.lua:1010, from a handler or from the GUID path); `pet.alive` also needs `UnitHealth( "pet" ) > 0` (2561); `pet.<token>` resolves the creature through
  `UnitGUID( "pet" )` parsed by `%-(%d+)%-[0-9A-F]+$` against `class.pets` (2490-2540), keyed by `RegisterPets` entries (`id`, `token`, `spell`, `duration`; summon duration `3600` = permanent).
- **Facade status:** `UnitExists`, `UnitIsDead`, `UnitGUID`, `UnitName`, `UnitClass` are `passthrough` "plain in combat [W PR14; gate spike]" for the units probed (player, target); for `"pet"` the only probe is a Warrior with **no pet**: `UnitExists( "pet" )` plain false (27/27 in combat), `UnitGUID( "pet" )` nil, `UnitPower( "pet" )` plain 0, **`UnitHealth( "pet" )` secret** [P PR12]. The facade answers `UnitHealth( unit )` for non-player, non-target units as 0 if `UnitIsDead` is secret or true, else 100
  (`Virtual/API/Facade.lua:270-276`) and `UnitHealthMax( "pet" )` as 100: so `pet.alive` works (100 > 0) and `pet.health_pct` is a constant 100 (the "stub returns 0" rows of `docs/forever-facade-notes.md` and `forever-cleanup.md:172` predate the virtual `UnitHealth`). Everything else is unprobed with a pet out: whether `UnitGUID( "pet" )` is plain with a pet (the creature-ID match), and whether `UnitIsDead( "pet" )` is plain: Q3.
- **`UnitCreatureFamily`**: exists on Forever (`wow_api_search`: returns `name, id`; `secretArguments: AllowedWhenUntainted`, no `SecretReturns` flag), **not in `tools/api_inventory.txt`** (no Hekili file reads it), so it has no facade entry; a pack cannot call a global the facade does not export (`ns.Facade.X`; Warrior.lua's header). Needs either a facade passthrough row added or the GUID path; pet type via GUID/creature ID is the primary plan, the family the fallback (Q3). Family names to expect: Imp, Voidwalker, Succubus, Incubus, Felhunter [I].
- **Registration shape (Hekili-style):** `spec:RegisterPets( { imp = { id = 416, spell = 688, duration = 3600 }, voidwalker = { id = 1860, spell = 697 }, succubus = { id = 1863, spell = 712 }, incubus = { id = 185317, spell = 713 }, felhunter = { id = 417, spell = 691 } } )`; each summon's `handler` (the sim, not the belief) does `summonPet( "imp" )`, and every summon `handler` first calls `dismissPet` for the others. **The belief has no pet family** (VirtualState has Totems only; `Families/Totems.lua`): a `now` cannot write a pet, so a summon cast is invisible to the belief and `pet.up` after a summon rests on the live `UnitExists` read (plain, so correct as soon as the pet appears) - the 10 s cast is the only gap, covered by the cast bar (`casting`).
- **Demonic Sacrifice** (18788; talent; 2 h; GCD 0): kills the demon and grants one of 18789 Burning Shadow (+15% Shadow, mask 32), 18790 Fel Stamina (3% health per 4 s), 18791 Touch of Fire (+15% Fire, mask 4), 18792 Fel Energy (2% mana per 4 s) [DB2 effect rows]. Demon-to-aura map is [TDF §1]: Imp -> Shadow, Succubus/Incubus -> Fire; TDF also says Voidwalker -> mana and Felhunter -> health, but the DB2 aura names (Fel Stamina = health, Fel Energy = mana, Classic's Voidwalker/Felhunter respectively) contradict it: **Q7**. The effect is cancelled by summoning another demon unless
  Demonic Pact 425464 (31-point talent: summoning a *different* demon keeps it). So the APL precombat line is `demonic_sacrifice,if=settings.sacrifice&pet.up&!buff.demonic_sacrifice.up` and every summon line has `!buff.demonic_sacrifice.up|talent.demonic_pact.enabled`; `buff.demonic_sacrifice` is an alias over the four auras (`alias = { ... }, aliasMode = "first"`).
- **Fel Domination** (cooldown 300 s, off GCD, 15 s): precede an emergency summon; in the APL only `toggle.cooldowns&!pet.up&cooldown.fel_domination.ready`. **Pet-dependent lines are the weakest point** (section 9): Spell Lock (19244, 19647; lockout aura 24259, 30 s) is a pet-bar cast and cannot be recommended or observed.
## 6. Talents (DB2 tree, Hekili key style; Forever-only flagged)

`key = { 0, definitionSpell, maxRank }`, max rank = non-zero `r1..r5` slots of `wowdb talents WARLOCK`. Counts: Affliction 17, Demonology 17, Destruction 16 [DB2]. Rank-1 rows hold 5/5 totals for several (section 0): modifiers use `value / maxRank * rank`.
```lua
-- Affliction (17 nodes; 4 ghost slots with no spell name keep a placeholder key)
suppression = { 0, 18174, 5 }, improved_corruption = { 0, 17810, 5 }, improved_curse_of_weakness = { 0, 18179, 3 }, ghost_affliction_18213 = { 0, 18213, 2 },
improved_life_tap = { 0, 18182, 2 }, soul_siphon = { 0, 17804, 5 }, improved_bane_of_agony = { 0, 18827, 3 }, fel_concentration = { 0, 17783, 5 },
amplify_curse = { 0, 18288, 1 }, grim_reach = { 0, 18218, 2 }, nightfall = { 0, 18094, 2 }, ghost_affliction_17864 = { 0, 17864, 2 },
siphon_life = { 0, 18265, 1 }, curse_of_exhaustion = { 0, 18223, 1 }, improved_curse_of_exhaustion = { 0, 18310, 4 }, shadow_mastery = { 0, 18271, 5 },
ghost_dark_pact = { 0, 18220, 1 },   -- no spell row: where Dark Pact was; Wrack replaces it in the live tree [TDF]
-- Demonology (17)
improved_healthstone = { 0, 18692, 2 }, improved_imp = { 0, 18694, 3 }, demonic_embrace = { 0, 18697, 5 }, improved_health_funnel = { 0, 18703, 2 },
improved_voidwalker = { 0, 18705, 3 }, fel_vitality = { 0, 18731, 5 }, improved_sayaad = { 0, 18754, 3 }, fel_domination = { 0, 18708, 1 },
ghost_demonology_18748 = { 0, 18748, 5 }, master_summoner = { 0, 18709, 2 }, unholy_power = { 0, 18769, 5 }, improved_subjugate_demon = { 0, 18821, 5 },
demonic_sacrifice = { 0, 18788, 1 }, improved_firestone = { 0, 18767, 2 }, master_demonologist = { 0, 23785, 5 }, soul_link = { 0, 19028, 1 }, improved_spellstone = { 0, 18774, 2 },
-- Destruction (16)
improved_shadow_bolt = { 0, 17793, 5 }, cataclysm = { 0, 17778, 5 }, bane = { 0, 17788, 5 }, aftermath = { 0, 18119, 5 }, improved_firebolt = { 0, 18126, 2 },
improved_lash_of_pain = { 0, 18128, 2 }, devastation = { 0, 18130, 5 }, shadowburn = { 0, 17877, 1 }, intensity = { 0, 18135, 2 }, destructive_reach = { 0, 17917, 2 },
agonizing_flames = { 0, 17927, 5 }, apocalypse = { 0, 18096, 2 }, improved_immolate = { 0, 17815, 5 }, ruin = { 0, 17959, 1 }, emberstorm = { 0, 17954, 5 }, conflagrate = { 0, 17962, 1 },
-- Forever-only (spells with no node in the DB2 tree; node and rank from [TDF], definition spells from DB2): the real list needs Q1
wrack = { 0, 1316697, 1 }, incinerate = { 0, 412758, 1 }, bane_of_havoc = { 0, 1225228, 1 }, pandemic = { 0, 427712, 3 }, malediction = { 0, 1225177, 5 },
malevolence = { 0, 1310949, 3 }, soul_harvest = { 0, 437032, 2 }, improved_drains = { 0, 403511, 3 }, shadow_and_flame = { 0, 426316, 5 }, fire_and_brimstone = { 0, 412751, 5 },
decimation = { 0, 440870, 2 }, demonic_brand = { 0, 1293695, 1 }, demonic_energies = { 0, 1225214, 2 }, demonic_pact = { 0, 425464, 1 }, demonic_knowledge = { 0, 412732, 1 },
```
- **Forever-only / changed** [TDF §1-2]: Wrack (requires Siphon Life), Incinerate (requires Bane of Havoc, 31 points), Bane of Havoc, Pandemic (crit damage on DoTs, not Retail's refresh), Malediction (+5% periodic per rank; replaced Improved Curse of Weakness), Malevolence (replaced Grim Reach), Soul Harvest (replaced Improved Drain Soul), Improved Drains (replaced Improved Drain Life), Shadow and Flame, Fire and Brimstone, Decimation, Demonic Brand, Demonic Energies/Fel Vitality, Demonic Pact, Soul Link at 21 points.
  The DB2 tree still carries Classic's Improved Curse of Exhaustion, Grim Reach, Improved Curse of Weakness, Soul Siphon (a Classic node here, Forever's has `m1` 12% a rank per Affliction effect, 17804 effect 4 base 12). Max-rank disagreements: Cataclysm (DB2 5 ranks, TDF 3/3), Ruin (DB2 1 rank, TDF 1-5); the DB2 counts are the table's until Q1.
- **Rotation-relevant reads** (the only ones the engine must see): `talent.improved_corruption.rank` (Corruption cast), `talent.bane.rank` (Shadow Bolt/Immolate/Incinerate/Soul Fire casts), `talent.nightfall.enabled`, `talent.siphon_life.enabled`, `talent.conflagrate.enabled`, `talent.shadowburn.enabled`, `talent.shadow_and_flame.rank`, `talent.wrack.enabled`, `talent.demonic_sacrifice.enabled`, `talent.soul_link.enabled`, `talent.cataclysm.rank` (cost). Cost modifiers (Cataclysm -1% a rank on Destruction spells: masks as the Gnome's WARLOCK list below): `RegisterCostMod{ aura = ..., pct = ... }` is for auras; a passive talent cost uses the Warrior's rank-times-row rule (Warrior.lua header).
## 7. Draft priorities (SimC style, pack convention, stateless)

Format as `tools/packs/warrior.lua` / `druid.lua`: `HEAD` shared text, one entry per pack (`name`, `desc`, `simc`), `actions.precombat` first, `settings.*` guards, `known` gates the missing ranks and talents, **no state kept between evaluations**. Classic-era baselines (not Hekili's, which has no readable Warlock APL): Affliction = DoTs then Shadow Bolt filler with Nightfall
procs; Destruction = Immolate, Shadow Bolt/Incinerate, Conflagrate timing; Demonology = pet + DoTs + Shadow Bolt. Settings: `curse` (0 none, 1 Elements default grouped, 2 Recklessness, 3 Weakness, 4 Tongues, 5 Exhaustion), `bane` (1 Agony default, 2 Doom), `pet` (1 Imp default, 2 Voidwalker, 3 Succubus, 4 Felhunter, 5 Incubus), `boss` (bool),
`tap_pct` (35), `tap_floor` (40, only if the health read is plain), `sacrifice` (bool), `sf_ranks` (0-5, default 0), `conflag_window` (4), `rof_targets` (3), `hellfire` (false), `shard_farm` (false). StateExprs: `mana_pct`, `soul_shards`, `shards_spent` (optional), `curse_up` (any Curse debuff), `bane_up` (any Bane). Toggles: `cooldowns` (Amplify Curse, Fel Domination, Death Coil, racials), `custom1` = second-target (Bane of Havoc).
```
# Shared head (all three): Demon Armor, the pet, then the Curse slot.
actions.precombat=demon_armor,if=!buff.demon_armor.up
actions.precombat+=/summon_imp,if=!pet.up&settings.pet=1&!buff.demonic_sacrifice.up
actions.precombat+=/summon_voidwalker,if=!pet.up&settings.pet=2&soul_shards>0&!buff.demonic_sacrifice.up
actions.precombat+=/summon_succubus,if=!pet.up&settings.pet=3&soul_shards>0&!buff.demonic_sacrifice.up
actions.precombat+=/summon_felhunter,if=!pet.up&settings.pet=4&soul_shards>0&!buff.demonic_sacrifice.up
actions.precombat+=/create_healthstone,if=soul_shards>1&!healthstone_in_bags
actions.precombat+=/demonic_sacrifice,if=settings.sacrifice&pet.up&!buff.demonic_sacrifice.up
actions.precombat+=/shadow_bolt
actions.curses=curse_of_the_elements,if=settings.curse=1&!dot.curse_of_the_elements.up
actions.curses+=/curse_of_recklessness,if=settings.curse=2&!dot.curse_of_recklessness.up
actions.curses+=/curse_of_weakness,if=settings.curse=3&!dot.curse_of_weakness.up
actions.curses+=/curse_of_tongues,if=settings.curse=4&!dot.curse_of_tongues.up
actions.curses+=/curse_of_exhaustion,if=settings.curse=5&!dot.curse_of_exhaustion.up

# Affliction (default)
actions=shadow_bolt,if=buff.shadow_trance.up
actions+=/call_action_list,name=curses,if=toggle.default
actions+=/amplify_curse,if=toggle.cooldowns&!dot.bane_of_agony.up&settings.bane=1&!buff.amplify_curse.up
actions+=/bane_of_doom,if=settings.boss&settings.bane=2&!bane_up
actions+=/bane_of_agony,if=settings.bane=1&!bane_up
actions+=/corruption,if=dot.corruption.remains<2.5
actions+=/siphon_life,if=talent.siphon_life.enabled&!dot.siphon_life.up
actions+=/life_tap,if=mana_pct<settings.tap_pct
actions+=/call_action_list,name=aoe,if=active_enemies>=4
actions+=/drain_soul,if=settings.shard_farm
actions+=/wrack,if=talent.wrack.enabled
actions+=/immolate,if=settings.boss&dot.immolate.remains<2.5&!talent.wrack.enabled
actions+=/shadow_bolt
actions.aoe=rain_of_fire,if=active_enemies>=settings.rof_targets
actions.aoe+=/hellfire,if=settings.hellfire&active_enemies>=5

# Destruction
actions=call_action_list,name=curses
actions+=/bane_of_doom,if=settings.boss&settings.bane=2&!bane_up
actions+=/bane_of_agony,if=settings.bane=1&!bane_up
actions+=/bane_of_havoc,if=toggle.custom1&active_enemies>=2&active_dot.bane_of_havoc<1
actions+=/soul_fire,if=buff.decimation.up&soul_shards>0
actions+=/conflagrate,if=dot.immolate.up&(settings.sf_ranks>=5|dot.immolate.remains<=settings.conflag_window)
actions+=/immolate,if=dot.immolate.remains<2.5
actions+=/corruption,if=settings.boss&dot.corruption.remains<2.5
actions+=/shadowburn,if=talent.shadowburn.enabled&settings.sf_ranks>0&soul_shards>0
actions+=/life_tap,if=mana_pct<settings.tap_pct
actions+=/call_action_list,name=aoe,if=active_enemies>=3
actions+=/shadow_bolt,if=buff.shadow_and_flame_shadow.up|talent.improved_shadow_bolt.rank>0&!talent.incinerate.enabled
actions+=/incinerate,if=talent.incinerate.enabled
actions+=/shadow_bolt
actions.aoe=rain_of_fire,if=active_enemies>=settings.rof_targets

# Demonology
actions=call_action_list,name=curses
actions+=/soul_link,if=talent.soul_link.enabled&pet.up&!buff.soul_link.up
actions+=/bane_of_doom,if=settings.boss&settings.bane=2&!bane_up
actions+=/bane_of_agony,if=settings.bane=1&!bane_up
actions+=/corruption,if=dot.corruption.remains<3.5
actions+=/immolate,if=dot.immolate.remains<2.5
actions+=/soul_fire,if=buff.decimation.up&soul_shards>0
actions+=/life_tap,if=mana_pct<settings.tap_pct
actions+=/call_action_list,name=aoe,if=active_enemies>=3
actions+=/shadow_bolt
actions.aoe=rain_of_fire,if=active_enemies>=settings.rof_targets
```
Notes: target health is hidden, so every "below 35%" or "kill within 8 s" form is dropped (Decimation, Shadowburn finisher, Drain Soul on a dying mob); `buff.decimation.up` is only true if the aura is readable (Q5). Corruption's 2.5 s refresh is 2.0 s cast + 0.5 s margin; with Improved Corruption 5/5 the cast is 0 and the rule can be `dot.corruption.remains<1.5` (make it
`cast_time + 0.5` once `ability.cast` reads the rank). Bane of Agony refresh at expiry only (`!bane_up`) so the ramp is never reset. Conflagrate assumes it consumes Immolate: the cost of the wrong assumption is one early Immolate recast. Thresholds are judgment [TDF §3, sim tips] with no Hekili sim behind them.
## 8. Checkpoint questions (each one `/run`, VSCopy, under 255 characters)

Run on a Warlock (Gnome or Troll helps), levels 20-30. `VSCopy` is ForeverProbe's (`~/src/ForeverProbe/Copy.lua:46`; `/vscopy` reopens). Ranked by importance.

| # | Question | Line | Answer -> action |
|---|---|---|---|
| Q1 | **Live talent tree** | `/fprobe export`, `/reload`, then `/run local e=ForeverProbeDB.export;VSCopy(e.meta.class,#e.spells,#e.talents.trees,e.stances.num)` | node list and max ranks -> section 6; resolves Cataclysm/Ruin and the ghost nodes |
| Q2 | **Soul shard count** in and out of combat, plain? | `/run VSCopy(C_Item.GetItemCount(6265),issecretvalue(C_Item.GetItemCount(6265)),InCombatLockdown())` | plain number -> `soul_shards` StateExpr as written; secret -> shard gates use `IsSpellUsable` only |
| Q3 | **Pet reads** with a demon out, in combat | `/run local g=UnitGUID("pet") VSCopy(UnitExists("pet"),g,UnitCreatureFamily("pet"),UnitIsDead("pet"),issecretvalue(UnitHealth("pet")))` | plain GUID with a creature ID -> `RegisterPets` ids work; family plain -> add the facade row; secret GUID -> pet kind from the summon event only |
| Q4 | **Life Tap value and the player health read** | `/run local c=UnitHealth("player") VSCopy(issecretvalue(c),UnitStat("player",5),C_Spell.IsSpellUsable(11689))` before and after a tap; then `/run VSCopy(UnitPower("player",0),issecretvalue(UnitPower("player",0)))` | plain health -> `tap_floor` works; Spirit and mana delta vs `LIFE_TAP[ rank ]` + Spirit set the `gain` constant |
| Q5 | **Nightfall aura ID and readability** | `/run for i=1,40 do local a=C_UnitAuras.GetBuffDataByIndex("player",i) if not a then break end VSCopy(a.spellId,a.name) end` right after a proc; also `/run VSCopy(pcall(C_UnitAuras.GetPlayerAuraBySpellID,17941))` | 17941 present and plain -> read it; error/secret -> the cast-time fallback (section 4) |
| Q6 | **Other procs**: Decimation 440873, Shadow and Flame 1293816/426311, Soul Harvest 1242853 | `/run VSCopy(pcall(C_UnitAuras.GetPlayerAuraBySpellID,440873),pcall(C_UnitAuras.GetPlayerAuraBySpellID,1293816))` in combat after the trigger | readable -> keep `buff.` gates; secret -> drop Decimation/S&F lines |
| Q7 | **Demonic Sacrifice map** | after sacrificing each demon: `/run for i=1,20 do local a=C_UnitAuras.GetBuffDataByIndex("player",i) if a and a.spellId>18788 and a.spellId<18793 then VSCopy(a.spellId,a.name) end end` | which of 18789-18792 per demon -> section 5 map |
| Q8 | **Drain Soul channel info** and Nightfall from Wrack | `/run VSCopy(UnitChannelInfo("player"))` mid-Drain Soul; in Wrack `/run VSCopy(UnitChannelInfo("player"))` | end-start 15 vs 6 s; `channeled` + `tick_time` 3 / 1; Wrack procs Nightfall -> noted |
| Q9 | **Curse visibility**: is the target debuff readable out of combat and after a retarget | `/run local a=C_UnitAuras.GetAuraDataByIndex("target",1,"HARMFUL") VSCopy(a and a.spellId,a and a.duration,a and a.expirationTime)` after Corruption on a dummy; repeat in combat | readable out of combat -> a reconcile poll could prime the belief; nil in combat -> confirmed (model only) |
| Q10 | **Talent text vs rows**: Cataclysm, Improved Corruption, Bane | `/run VSCopy(C_Spell.GetSpellDescription(17778),C_Spell.GetSpellInfo(172).castTime,C_Spell.GetSpellInfo(686).castTime)` | per-rank rules; ranks 5/5 cast times 0 / 2.5 |
| Q11 | **Spell haste and DoT length** (does haste change Shadow Bolt but not Corruption ticks) | `/run VSCopy(UnitSpellHaste("player"),C_Spell.GetSpellInfo(686).castTime)` with and without Spellstone | `cast` needs `* haste` for casts only; channels and DoTs fixed |
| Q12 | **Bane/Curse exclusivity and Conflagrate/Immolate** | `/run local c=C_Spell.IsSpellUsable VSCopy(c(1293817),c(980),c(440892))` with Immolate down, then up; then after a Bane cast | Conflagrate greyed without Immolate -> gate tracker; second Bane replaces first -> `now` removals correct |
| Q13 | **Life Tap and Shadow Bolt as read costs** | `/run local c=C_Spell.GetSpellPowerCost(11689) VSCopy(c and c[1] and c[1].type,c and c[1] and c[1].minCost)` | cost type `health` and its value -> usable guard |
| Q14 | **School lockout shape** (Counterspell on a Warlock) | `/run local d=C_LossOfControl.GetActiveLossOfControlData(1) VSCopy(d and d.locType,d and d.lockoutSchool,d and d.timeRemaining)` while locked out | `lockoutSchool ~= 0` -> shared lockout aura needed (Mage §10) |
| Q15 | **Healthstone/Soulstone item cooldown and use-spell** | `/run VSCopy(C_Item.GetItemCooldown(19013),C_Item.GetItemSpell(19013))` after a use | 120 s vs item's own; use spell ID for a `now` |
## 9. Risks and what the belief lacks

- **DoT clipping with no target reads.** The belief's modelled expiry (from `CastSuccess` + the believed duration) is the only source: a resisted or missed DoT/Bane/Curse still reads "up" (the event shows a cast, not a landing), a target swap files it under the old slot, and a Blizzard-known tracking loss after re-acquiring a target means the APL re-casts (a clip, never a miss). Refresh at `remains < cast + 0.5` assumes the tick timer matches the game's; a 3 s tick offset is invisible. Mitigate: durations from rank tables, `removeDebuff` on the Bane/Curse
  slot, and the usable gate (`IsSpellUsable` plain) as a last guard for Conflagrate; `shortcut:` Q9 may allow a reconcile poll out of combat only.
- **Multiple curses, one-at-a-time rule.** A Warlock keeps one Curse and one Bane on a target. The `now` removals must cover all five Curses and three Banes in both directions, and the Amplify Curse buff is consumed by the *next* Weakness/Bane of Agony only. Another Warlock's curses coexist (not seen); a Bane of Havoc is on another mob, so it needs `active_dot`.
- **Pet-dependent lines.** Pet creature identity is unprobed with a pet out (Q3); the belief cannot hold a pet (no pet family); a `summonPet` in a sim `handler` is not seen by the belief; the pet's death mid-fight (Soul Link, Master Demonologist) arrives only via the live read; `UnitHealth( "pet" )` is the facade's constant 100. Spell Lock/Devour Magic/Firebolt are unrecommendable. A summon is a 10 s cast with a shard: the precombat line only; never in the rotation.
- **Shard overspend.** `soul_shards` is a live count but a handler spends nothing, so two shard spells recommended back-to-back can exceed the count; the game then greys the second (Q2/`IsSpellUsable`).
- **Life Tap vs the health belief.** `now` cannot write health; the belief's health stays high after a tap until the next plain poll (if any). No health-gated line is safe until Q4. Spirit scaling is invisible to `now`: the mana jump is understated by Spirit, so `mana.pct` after a tap is low and the rotation may tap twice (Hekili's `usable` for Life Tap should include `cooldown.global_cooldown` plus `mana_pct < tap_pct` only).
- **Channels** (Wrack, Drain Soul/Life, Rain of Fire, Hellfire): `handler` does not run for a channeled ability (Mage §6); use `start`/`tick`/`finish`; interrupt-by-cast and pushback are unmodelled, Fel Concentration (avoid interrupt) and Intensity matter only for pushback. A channel `now` runs at success (the start, if Forever fires SUCCEEDED then: Mage Q8).
- **Mana modelling** is the Mage's: one calibrated regen rate, ladder-only if secret, the five-second rule unmodelled, Soul Harvest (+100%/10 s) and Life Tap jumps outside the 2x calibration guard. APL lines use `mana_pct`, not `mana.time_to_x`.
- **Auras possibly secret** (Q5/Q6): Shadow Trance is the highest-value read (free instant Shadow Bolt); without it the Affliction list loses its first line.
- **Dormant SoD spells** (Chaos Bolt 403629, Metamorphosis 403789, Shadow Cleave 403835.., Shadowflame 426320, Fel Armor 403619, Summon Felguard 427733/427748, Curse of Shadow 402791, Curse of the Elements 402792, Drain Life 403677..403689) must not be registered; `known` is false.
- **Racials:** Gnome Eureka! for Warlock is **1259821** (15 s, 120 s, off GCD) with cost scope `WARLOCK = { 1293817, 6789, 689, 403677, 1120, 1949, 348, 5740, 5676, 686, 17877, 6353, 1316697 }` (set 5, masks 541165 / 8650880) in `Forever/Races/Gnome.lua:61` - **it names Conflagrate, Death Coil, both Drain Lifes, Drain Soul, Hellfire, Immolate, Rain of Fire, Searing Pain, Shadow Bolt, Shadowburn, Soul Fire, Wrack, but not Corruption, Banes or Incinerate**; the Warlock file must register those keys so the Gnome file's `copy` lists resolve (an ID the loaded class does not register is absent). Expansive Mind 20591 (+5% max mana). Troll Berserking 20554 (+10% speed 10 s, cd 180; aura 319/140/65). Undead Touch of the Grave 1260201 (inert) and Will of the Forsaken 7744 are stock. Orc Blood Fury 20572 is shared (`Races/Orc.lua`).
## 10. DB2 queries used (all `~/.local/share/wow-db2/bin/wowdb`, build 1.60.1.70338)

- Class spells: `select s.id,s.name,s.rank,s.base_level,s.school_mask,s.cast_ms,s.duration_ms,s.power,s.cost,s.cost_pct,s.cooldown_ms,s.category_cd_ms,s.gcd_ms,s.range_max from spell_info s join spell_skill k on k.spell_id=s.id where k.classes like '%WARLOCK%' order by s.name,s.base_level` (+ `and s.name >= 'Ritual of Summoning'` for the second page).
  Name sweeps: `select ... from spell_info where name like 'Curse of the Elements%' or name like 'Dark Pact%' or name like 'Summon%' ...`; absent names: `select count(*) from SpellName where Name_lang='Backlash'` -> 0; `wowdb spell "Dark Pact"` and `wowdb spell "Summon Felguard"` (427733, 427748, 431754, no skill line).
- Tree: `wowdb talents WARLOCK`; counts `select tab,count(*) from talent_info where class='WARLOCK' group by tab` (17/17/16); definition names/descriptions: `select t.tab,t.tier,t.col,t.r1,(select Name_lang from SpellName where ID=t.r1),... substr((select Description_lang from Spell where ID=t.r1),1,150) from talent_info t where t.class='WARLOCK'`.
- Effects: `wowdb effects <id>` for 1454, 11689, 18182, 1120, 11675, 17941, 18094, 18788-18792, 18708, 18288, 1316697, 689, 18265, 25228, 19028, 172, 25311, 980, 11713, 603, 1225228, 348, 25309, 5740, 1949, 6353, 5676, 17877, 1293817, 6789, 686, 25307, 412758, 18223, 440892, 704, 702, 1714, 17788, 17778, 17793, 17794, 18271, 17804, 18827, 18692, 18731, 427733, 688, 697, 712, 713, 691, 1122, 18540, 20554.
  Descriptions: `select ID,Description_lang,AuraDescription_lang from Spell where ID in (...)`. Items: `select ID,Display_lang,Bonding,Stackable,RequiredLevel from ItemSparse where ID in (6265,5509..5512,9421,19004..19013,16892..)` and `Display_lang like '%Soulstone%'/'%Firestone%'/'%Spellstone%'/'%Healthstone%'`. Racials: `select distinct k.skill_line,k.spell_id,s.name,... from spell_skill k join spell_info s on s.id=k.spell_id where k.skill_line like 'Racial%' and k.classes like '%WARLOCK%'`.
- Reads: `wow_api_search UnitCreatureFamily`, `GetItemCount` (flavor forever); `HK Virtual/API/Facade.lua:255-290`, `Virtual/State/Families/{Now,Player}.lua`, `Sources/Player.lua:166-180`, `State.lua` 1010, 2410-2570; `HK docs/forever-facade-notes.md`, `docs/forever-cleanup.md:172`; `docs/research/tdf/2026-10-13-probe-session-W-results.md` PR12-PR13.
## 11. Pack spec inputs (constants to copy)
```lua
-- Pseudo-spec 1491, class "WARLOCK"; RegisterResource( Enum.PowerType.Mana ); RegisterOptions( { package = "Affliction" } ); packs Affliction (default), Destruction, Demonology
local SHADOW_BOLT = { 686, 695, 705, 1088, 1106, 7641, 11659, 11660, 11661, 25307 } local SHADOW_BOLT_COST = { 25, 40, 70, 110, 160, 210, 265, 315, 370, 380 } local SHADOW_BOLT_CAST = { 1.7, 2.2, 2.8, 3, 3, 3, 3, 3, 3, 3 }
local IMMOLATE = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 } local IMMOLATE_COST = { 25, 45, 90, 155, 220, 295, 370, 380 } -- cast 2.0, DoT 15 s, tick 3 s
local CORRUPTION = { 172, 6222, 6223, 7648, 11671, 11672, 25311 } local CORRUPTION_COST = { 35, 55, 100, 160, 225, 290, 340 } local CORRUPTION_DURATION = { 12, 15, 18, 18, 18, 18, 18 } -- cast 2.0, tick 3 s
local BANE_OF_AGONY = { 980, 1014, 6217, 11711, 11712, 11713 } local BANE_COST = { 25, 55, 90, 130, 170, 215 } -- 24 s, tick 2 s (rank 2 cost interpolated)
local BANE_OF_DOOM, BANE_OF_HAVOC = 603, 1225228 -- 603: 300 mana, 60 s, cd 60; 1225228: 5% base, GCD 0, 300 s
local CURSE_OF_THE_ELEMENTS = { 440892, 1311676, 1311677, 1311680 } -- 50, 100, 150, 200 mana, 300 s
local CURSE_OF_RECKLESSNESS = { 704, 7658, 7659, 11717 } -- 35, 60, 90, 115; 120 s
local CURSE_OF_WEAKNESS = { 702, 1108, 6205, 7646, 11707, 11708 } -- 20, 35, 70, 95, 130, 175; 120 s
local CURSE_OF_TONGUES = { 1714, 11719 } -- 80, 110; 30 s
local CURSE_OF_EXHAUSTION = 18223 -- 8% base; 12 s
local AMPLIFY_CURSE = 18288 -- GCD 0, cd 180, 30 s, +50% (Weakness / Bane of Agony)
local SIPHON_LIFE = { 18265, 18879, 18880, 18881 } local SIPHON_COST = { 150, 205, 285, 365 } -- 30 s, tick 3 s
local DRAIN_LIFE = { 689, 699, 709, 7651, 11699, 11700 } local DRAIN_LIFE_COST = { 55, 85, 135, 185, 240, 300 } -- channel 5 s, tick 1 s
local DRAIN_SOUL = { 1120, 8288, 8289, 11675 } local DRAIN_SOUL_COST = { 55, 125, 210, 290 } -- channel 15 s, tick 3 s
local WRACK = 1316697 -- 200 mana, channel 6 s, tick 1 s, +10% on other Shadow DoTs
local SEARING_PAIN = { 5676, 17919, 17920, 17921, 17922, 17923 } local SEARING_COST = { 45, 68, 91, 118, 141, 168 } -- cast 1.5
local CONFLAGRATE = { 1293817, 1293818, 17962, 18930, 18931, 18932 } local CONFLAGRATE_COST = { 100, 130, 165, 200, 230, 255 } -- cd 10
local SHADOWBURN = { 17877, 18867, 18868, 18869, 18870, 18871 } local SHADOWBURN_COST = { 105, 130, 190, 245, 305, 365 } -- cd 15, 8 s window, 1 shard
local SOUL_FIRE = { 6353, 17924 } local SOUL_FIRE_COST = { 305, 335 } -- cast 6.0, cd 60, 1 shard
local INCINERATE = { 412758, 1293812, 1293813 } local INCINERATE_COST = { 205, 265, 325 } -- cast 2.5
local RAIN_OF_FIRE = { 5740, 6219, 11677, 11678 } local RAIN_COST = { 295, 605, 885, 1185 } -- channel 8 s, tick 2 s
local HELLFIRE = { 1949, 11683, 11684 } local HELLFIRE_COST = { 645, 975, 1300 } -- channel 15 s, tick 1 s
local DEATH_COIL = { 6789, 17925, 17926 } local DEATH_COIL_COST = { 435, 525, 600 } -- cd 120, horror 3 s
local LIFE_TAP = { 1454, 1455, 1456, 11687, 11688, 11689 } local LIFE_TAP_BASE = { 20, 65, 130, 210, 300, 420 } -- health = mana gain = base + Spirit; Improved Life Tap 18182 (+10/20%)
local DEMON_ARMOR = { 706, 1086, 11733, 11734, 11735 } local DEMON_ARMOR_COST = { 275, 520, 800, 1150, 1580 }
local DEMON_SKIN = { 687, 696 }
local CREATE_HEALTHSTONE = { 6201, 6202, 5699, 11729, 11730 } local CREATE_HEALTHSTONE_COST = { 95, 240, 475, 750, 1120 } -- cast 3 s
local CREATE_SOULSTONE = { 693, 20752, 20755, 20756, 20757 } -- 85% base, 3 s; items 5232, 16892, 16893, 16895, 16896
local CREATE_SPELLSTONE = { 2362, 17727, 17728 } -- 500, 750, 1000; 5 s; items 5522, 13602, 13603
local CREATE_FIRESTONE = { 6366, 17951, 17952, 17953 } -- 500, 700, 900, 1100; 3 s; items 1254, 13699, 13700, 13701
local SOUL_SHARD = 6265 -- bag item, count via C_Item.GetItemCount (plain, Q2)
local HEALTHSTONES = { 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 } -- Consumables.lua
local SUMMON = { imp = 688, voidwalker = 697, succubus = 712, incubus = 713, felhunter = 691 } -- cast 10 s; Imp 80% base no shard, others 100% + 1 shard; Inferno 1122
local PET_CREATURE = { imp = 416, voidwalker = 1860, succubus = 1863, incubus = 185317, felhunter = 417 } -- Felguard 213450 not registered
local FEL_DOMINATION, DEMONIC_SACRIFICE, SOUL_LINK, SPELL_LOCK = 18708, 18788, 19028, { 19244, 19647 } -- FD cd 300 GCD 0; DS GCD 0 2 h; SL 20% base
local SACRIFICE_AURAS = { 18789, 18790, 18791, 18792 } -- shadow +15%, health 3%/4s, fire +15%, mana 2%/4s (demon map: Q7)
-- auras (unit, id, duration, max stacks)
--   shadow_trance 17941 player 10 s; decimation 440873 player 10 s; shadow_and_flame 1293816 (shadow) / 426311 (fire) player 20 s; amplify_curse 18288 player 30 s; soul_harvest 1242853 player 10 s
--   soul_link 25228 player indef.; demon_armor 706..11735 player 1800 s; fel_domination 18708 player 15 s; improved_shadow_bolt 17794 target 12 s (not modelled)
-- talents (rank rows are 5/5 totals where noted): bane 17788 (-0.1 s/rank Shadow Bolt, Immolate, Incinerate; -0.4 s/rank Soul Fire), improved_corruption 17810 (-0.4 s/rank), nightfall 18094 (2%/4%), cataclysm 17778 (cost, Q10)
-- Gnome Eureka! WARLOCK 1259821 and Expansive Mind 20591 are already in Forever/Races/Gnome.lua (cost scope listed in section 9); Troll Berserking 20554, Orc Blood Fury 20572, Undead 1260201 are shared
-- Settings: curse(0-5), bane(1-2), pet(1-5), boss, tap_pct 35, tap_floor 40, sacrifice, sf_ranks 0, conflag_window 4, rof_targets 3, hellfire false, shard_farm false
-- StateExprs: mana_pct, soul_shards (GetItemCount(6265)), bane_up, curse_up; GCD 1.5 s (gcd = "spell") except Bane of Havoc, Amplify Curse, Fel Domination, Demonic Sacrifice (gcd = "off")
```
