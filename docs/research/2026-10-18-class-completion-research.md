# Class completion: wowsims/forever as the APL reference (2026-10-18)

Research for the class completion plan (`docs/superpowers/plans/2026-10-18-class-completion.md`). For every Forever DPS
and tank spec (no healers) it gives wowsims' rotation as the APL basis, what the fork already has, what is missing,
where `focus=N` fits, and which engine or belief capabilities the spec needs that the fork has not modelled on
Forever. Everything here is a recommendation. The user's own priorities (Fury, Feral) stay the spec where they exist.

**Credit and licence.** wowsims/forever, https://github.com/wowsims/forever, MIT License ("Copyright (c) 2022 wowsims
team"). It is a reference only. Nothing is built, linked or copied. Pack lines get written fresh with the fork's keys.
The clone is `/home/zack/src/wowsims-forever` (commit `d33930d0`). Clone paths below are relative to it. Fork paths are
relative to the repository root. Spell IDs quoted from the clone are wowsims'. An implementer re-reads each one with
`~/.local/share/wow-db2/bin/wowdb spell <name>` before registering it. Spells numbered 1,000,000 and up are
Forever-only.

**Where the rotations live.** Every spec runs on an APL. None has a hardcoded Go rotation, and the Go code defines only
spells, auras and procs. Druid, Rogue, Paladin, Enhancement, Hunter, Warrior and Mage keep
`ui/specs/<class>/<spec>/apls/*.apl.json`. Warlock, Shadow Priest and Elemental embed the APL in
`ui/specs/<class>/<spec>/builds/*.build.json` under `player.rotation`, and `presets.ts` loads it. The "Simple"
rotations in the UI are those same JSONs with toggles flipped (`ui/specs/warrior/dps/spec.ts:138`,
`ui/specs/rogue/dps/spec.ts:177-190`, `ui/specs/hunter/dps/spec.ts:167`).

**Fork state.** Two packs exist: `src/Hekili_Warrior/Warrior.lua` (Arms, Fury, Protection) and
`src/Hekili_Druid/Druid.lua` (Feral, Balance, bear). Shared content and racials are in `src/Hekili_Shared/`. The
APL text is in `tools/packs/<class>/*.simc` at e280b43f. It moves to `src/Hekili_<Class>/APLs/` on `forever-fury`
(c9d675a2), and that branch also introduces `focus=2`. The belief families (`src/Hekili/Game/State/Families/`) are
Resources (ladder, regen calibration, swing rage, combo points), Auras (player walk, modelled target debuffs with
per-target memory), Casts (casts, channels, charges, GCD, on-next-swing queue), Swing (two hands), Totems (four
slots), TargetCast, TargetHealth (`healthGate`), Enemies (plates and range polls), Player, Talents, Modifiers and Now.
The belief has **no pet family, no ranged swing, no weapon enchant read and no stealth read**.

**The focus method** (`docs/research/2026-10-18-fury-vs-wowsims.md` on `forever-fury`, "Where focus fits"):
- `focus=N` marks an APL line as a Timeline attention candidate. It is for reactive or timing-bound picks, never the
  steady rotation.
- Reactive windows the engine reads only at `now` show gold on arrival: procs, usability-gated windows, interrupts and
  health gates.
- Predictable picks can show a countdown: refreshes of modelled debuffs or buffs, and cooldown-gated or swing-timed
  picks.
- Tiers proposed here: **1** = reactive, or costly to miss (a proc window, an execute, an interrupt, a proc-gated
  spender). **2** = a predictable upkeep or timing window (a DoT, buff or totem refresh, a swing gap, a mana window).
  The Fury run's `focus=2` lines (the no-clip Heroic Strike) fit tier 2. This needs a decision (plan, D1).

---

## 1. Druid

### 1.1 Feral (cat)
- **Sim:** `ui/specs/druid/feralcat/apls/default.apl.json` (MONOCAT_APL, `ui/specs/druid/feralcat/presets.ts`).
  Alternates in the same folder are shadowmeld, energized, jvmes, pounce, ravage and bearweave. Code:
  `sim/druid/forms.go`, `omen_of_clarity.go`, `shifting_power.go`, `talents_feral_combat.go:198`, `apl_values.go`.
- **Priority:**
  Sapper Charge → Cat Form → Berserk, as `Berserk→Rake` when Rake is due and Rip is not, or `Berserk→Shred` when no pool or Shifting Power is due → Cooldowns: Elune's Light outside Berserk, Thistle Tea at energy ≤ 20, a mana potion → **Shred (or Claw) on Clearcasting.** → Rip at 5 CP when not up and ≥ 10 s of the fight left. Rake when not up and ≥ 6 s left → Bite at 5 CP with < 10 s left → Shifting Power at energy < 40 with Clearcasting, < 50 without, or while pooling → Shred, then Claw, unless pooling. The pool condition: Rip ≤ 2 s or Rake ≤ 1 s and energy − Shred + 10 < the refresh cost → Innervate in Cat when mana is low and energy ≤ 30 → Faerie Fire (Feral) to fish for Omen while its internal cooldown is ready.
- **Fork:** `tools/packs/druid/Feral.simc`. It has Cat Form, Shifting Power < 50, Berserk, Rip (`focus=1`), Rake, the
  Bite option and Shred/Claw with `excess_e` (the same pooling idea). The not-behind window and `missedAt` are at
  `Druid.lua:586-620`.
- **Missing:**
  - The Clearcasting Shred line, and Shifting Power's lower threshold under Clearcasting.
  - `Berserk→Rake` ordering.
  - Innervate in Cat, and the FF Omen fishing (it needs the Omen internal cooldown: a modelled timer from the proc,
    and only if Clearcasting is readable).
  - The sim's "fight left" guards. The fork has no time to die (the user dropped it). Use `boss` plus a setting.
- **Focus:**
  - `rip` stays 1.
  - Shred on Clearcasting gets 1. It is a proc window, gold on arrival.
  - Rake refresh gets 2. It is predictable, and it is the line `excess_e` pools for.
  - Innervate gets 2 (a mana window). Berserk gets none (steady burst).
- **Unmodelled:** Clearcasting visibility in combat (C2), the Omen internal cooldown as a timer (S, pack-only) and mana
  for Innervate (C3, already ladder-only).

### 1.2 Guardian (bear)
- **Sim:** `ui/specs/druid/feralbear/apls/default.apl.json`. Code: `sim/druid/lacerate.go`, `primal_bite.go`,
  `maul.go`, `frenzied_regeneration.go`, `feralbear/feralbear.go`.
- **Priority:**
  Berserk after Primal Bite (Demoralizing Roar up, Primal Bite ≥ 4 s away). Elune's Light → Frenzied Regeneration at HP < 20% → Lacerate at 5 stacks and ≤ 1.5 s left. Demoralizing Roar when not up → Primal Bite, then Lacerate → Maul at rage ≥ 20.
- **Fork:** `tools/packs/druid/Guardian.simc`. It has Lacerate refresh at ≤ 4.5 s, Primal Bite, Faerie Fire, Maul with
  a rage reserve, Swipe, Enrage, an AoE list, and Frenzied Regeneration unconditionally.
- **Missing:**
  - The HP < 20% gate on Frenzied Regeneration. Player health is read by the Player family's 1.5 s poll, so this is a
    pack change.
  - Berserk keyed to Primal Bite's cooldown.
  - The tighter 1.5 s Lacerate window. That is a judgement call: the fork's 4.5 s is safer with modelled debuffs.
  - Keep the fork's AoE list. The sim has none.
- **Focus:** Frenzied Regeneration gets 1 (defensive, reactive). Lacerate refresh gets 2. Demoralizing Roar refresh
  gets 2.
- **Unmodelled:** nothing new. The rage income is still unmeasured (Druid checkpoint Q9).

### 1.3 Balance
- **Sim:** `ui/specs/druid/balance/apls/default.apl.json`. Eclipse is custom: `sim/druid/talents_balance.go:132-175`.
  Each Wrath adds a charge to 408255, and each Starfire spends one.
- **Priority:**
  Innervate at mana < 10% → Moonfire, then Insect Swarm, each when not up → Hurricane (channel) at ≥ 4 targets → Starfire with Eclipse → Wrath.
- **Fork:** `tools/packs/druid/Balance.simc` matches it (provisional Eclipse rule). Hurricane is a setting.
  Moonfire/IS are gated on `boss|settings.trash_dots`.
- **Missing:** Innervate at a mana fraction rather than "cost × 2", and the Eclipse charge rule confirmed in game.
- **Focus:** Starfire on Eclipse gets 1 (a proc window). Moonfire/IS refresh gets 2. Innervate gets 2.
- **Unmodelled:** the five-second rule and casting regen (C3). Eclipse visibility (C2).

## 2. Rogue (Combat, Assassination, Subtlety: one wowsims spec)
- **Sim:** `ui/specs/rogue/dps/apls/default.apl.json`. Code: `sim/rogue/rogue.go:105` (finishers), `stealth.go`,
  `vanish.go`, `poisons.go`, `talents_subtlety.go:266` (Cutthroat 462707), `:306` (Thousand Cuts),
  `talents_assassination.go:234` (Venom), `talents_combat.go:137`. Build presets: Mutilate/Combat, Combat SS, Combat
  Backstab, Sub Hemo, Sub Backstab.
- **Priority:**
  - Precombat: Blade Flurry, Premeditation, Stealth.
  - Openers:
    Expose Armor (option) at 5 CP when missing or ≤ 16 s left → Ambush on Cutthroat or in stealth → Garrote in stealth → Vanish to re-open. Preparation.
  - Cooldowns: Adrenaline Rush at energy ≤ 50 with SnD up, Blood Fury, Eureka!, Thistle Tea at low energy.
  - Main list:
    Slice and Dice when down and CP ≥ 1 → Venom when down and CP ≥ 3 (Forever-only) → Rupture at CP ≥ 3 with Thousand Cuts or Hemorrhage up → Cold Blood at 5 CP → Eviscerate at 5 CP (4 with Mutilate, or ≥ 4 with SnD ≤ 6 s) → Ghostly Strike, then Hemorrhage upkeep → Builders when CP < 5: Backstab, Mutilate, Hemorrhage, Sinister Strike.
- **Fork:** none. Research: `docs/research/2026-10-15-forever-rogue/research.md` (§4 stealth, §5 poisons, §8 risks
  R1-R9).
- **Missing:** the whole pack. Energy, combo points, the not-behind window and `missedAt` exist from the Druid.
- **Focus:**
  - Ambush on Cutthroat gets 1 (proc, gold on arrival).
  - Kick on an interruptible cast gets 1.
  - SnD refresh ("fall imminent", ≤ 2 s) gets 1. It is costly to miss and predictable.
  - Rupture refresh gets 2. Expose Armor refresh gets 2. Vanish re-open gets 2.
- **Unmodelled:**
  - Stealth state (C5).
  - Poisons as weapon enchants (C4).
  - The finisher ladder pin (R1): the usability ladder must not pin energy on a finisher refused for lack of combo
    points (C9).
  - Adrenaline Rush as a regen multiplier (C3b).
  - Fight-length guards (D2).
  - The dagger and behind requirements (settings plus the existing error window).

## 3. Paladin

### 3.1 Retribution
- **Sim:** two presets. `ui/specs/paladin/retribution/apls/twist_of_light.apl.json` is the default.
  `apls/holy_shock.apl.json` is chosen when the Holy Shock talent is taken (`spec.ts:142`). Code:
  `sim/paladin/seals.go:30-40` (Echo auras), `talents_retribution.go:343`, `judgement.go`, `swift_judgement.go`,
  `consecration.go`.
- **Twist of Light priority:**
  - Precombat: Retribution Aura, Seal of Command, Seal of the Crusader.
  - Main list:
    Judgement → Hammer of Wrath when instant, or within 0.2 s after a main-hand swing → Holy Strike → **Seal of Command if Echo of Command (1311703) and the seal are both down.** → **Seal of Righteousness if Echo of Righteousness (1311704) and the seal are both down.** Lines 4-5 are the twist → Consecration, then Exorcism, each when the next swing is > 1.5 s away and mana ≥ 10%.
- **Holy Shock preset:** adds Holy Shock and Divine Favor keyed to Consecrated Ground (1310905, target), and SoR when
  its remaining time < the swing. It also has an item swap, which the fork drops: display only.
- **Fork:** none. No research brief either.
- **Missing:** the whole pack.
  - Seals are player buffs. Echoes are player auras: verify in game.
  - Judgement's effect on the active seal on Forever is unknown. The sim does not consume it. Checkpoint question.
  - Hammer of Wrath maps to `healthGate` (exists).
  - The swing-gap tests map to the Swing family (`mainhand_remains`, exists).
- **Focus:**
  - Hammer of Wrath gets 1 (execute window, gold on arrival).
  - The seal twist lines get 1. They are timing-bound to the swing, and a missed twist loses the Echo.
  - Consecration and Exorcism in the swing gap get 2.
  - Judgement on cooldown gets none.
- **Unmodelled:** the five-second rule (C3, mana-gated fillers). Proc and Echo visibility (C2). The judgement debuff on
  the target, which can be modelled from the cast (S).

### 3.2 Protection
- **Sim:** `ui/specs/paladin/protection/apls/default.apl.json`. Code: `sim/paladin/seal_of_fury.go`,
  `holy_shield.go`, `righteous_fury.go`, `protection/protection.go`.
- **Priority:**
  - Precombat: Retribution Aura, Seal of the Crusader.
  - Main list:
    Judgement → Swift Judgement (1310994) → Seal of Fury when not up → Consecration → Holy Shock when Consecrated Ground is up → Holy Shield → Holy Strike → Exorcism.
- **Fork:** none. Righteous Fury is a precombat buff line.
- **Focus:** Holy Shield refresh gets 2. Seal of Fury refresh gets 2. Taunt (Hand of Reckoning, if it exists on Forever:
  wowdb) on `threat.lost` gets 1, as Warrior Protection does (`Engine/Schema/Threat.lua`).
- **Unmodelled:** C3, plus Holy Shield charges spent by blocks (the Auras family's `consumedBy`, exists: S).

## 4. Shaman Enhancement
- **Sim:** `ui/specs/shaman/enhancement/apls/default.apl.json`. Code: `sim/shaman/totems.go`, `fire_totems.go:98-130`
  (Fire Nova needs a fire totem), `weapon_imbues.go`, `talents_enhancement.go:234` (Maelstrom Weapon 408505),
  `talents_elemental.go:101` (Clearcasting 16246), `apl_values.go` (`totemRemainingTime`).
- **Priority:**
  - Precombat: Grace of Air, Flametongue, Strength of Earth, Mana Spring.
  - Main list:
    Mana potion / Demonic Rune at a mana fraction → Grace of Air, then Strength of Earth, when the slot is empty → **Fire Nova on Clearcasting.** → Lightning Shield when down → Searing Totem when the fire slot is empty → Stormstrike → **Lightning Bolt at 5 Maelstrom.** → Flame Shock when down → Earth Shock → Fire Nova at mana > 10%.
  - The imbue (Rockbiter by default) is set as an option and never cast. Windfury Totem comes from the party.
- **Fork:** none. The Totems family and source exist (`Families/Totems.lua`, `Sources/Totems.lua`). Schema has
  `RegisterTotem(s)` (`Engine/Schema/Spec.lua:1155`), and the facade answers `GetTotemInfo` as hybrid
  (`Game/API/Facade.lua:377-386`).
- **Focus:**
  - Lightning Bolt at 5 Maelstrom gets 1 (a stacking proc, gold on arrival).
  - Fire Nova on Clearcasting gets 1.
  - Totem refreshes get 2 (predictable expiry from our cast). Lightning Shield refresh gets 2. Flame Shock on drop
    gets 2.
- **Unmodelled:**
  - The totem element→key map and modelled durations from our cast, on the sim side (C6, mostly content).
  - The weapon imbue precombat check (C4).
  - Maelstrom and Clearcasting visibility (C2).
  - The five-second rule (C3).
  - Lightning Shield charges spent by hits on the player (`consumedBy`, exists).

## 5. Hunter (one wowsims spec, three builds)
- **Sim:** `ui/specs/hunter/dps/apls/default.apl.json` ("Melee Weave"), `turret.apl.json` (MM), `turret_hawk.apl.json`
  (BM), `melee.apl.json` (SV melee). Builds and pets: `ui/specs/hunter/dps/presets.ts:153-159`. Code:
  `sim/hunter/pets.go:73-240`, `summon_hawk.go` (Summon Hawk 1293527: 18 s guardians, capped), `sniper_shot.go`,
  `raptor_strike.go:23` (on-next-swing).
- **Turret priority:**
  - Precombat: Hunter's Mark, Aspect of the Hawk.
  - Main list:
    Cooldowns (Rapid Fire) → Hunter's Mark refresh → Aimed Shot (option) → Serpent Sting when not up → **Sniper Shot during Rapid Fire or Quick Shots (6150).** → Hawk ×2 → Arcane Shot → Multi-Shot.
- **Melee Weave:** moves between 5 and 11 yards on the swing timers. A display can't move the player, so this is not a
  basis (D3).
- **Melee:** Raptor Strike (queued), Mark, Mongoose Bite, Strider Kick (1317257), Immolation Trap, Hawk, Wing Clip.
- **Fork:** none. Research: `docs/research/2026-10-15-forever-hunter/research.md`. Forever Hunters spend **mana**, not
  focus (§0). The research also covers the auto-shot gap (§1.3) and pets (§3).
- **Focus:**
  - Sniper Shot in the proc window gets 1.
  - Mongoose Bite (usable after a dodge) gets 1.
  - Raptor Strike gets 1 (swing-timed, on-next-swing).
  - Serpent Sting refresh gets 2. Hunter's Mark on a new target gets 2.
  - Aimed/Multi in the auto-shot gap gets 1 once the ranged clock exists.
- **Unmodelled:**
  - The ranged auto-shot clock (C7: `Sources/Swing.lua:18` and `Events/Rows.lua:265` drop `swingType > 1`, and the
    Swing family has two hands).
  - Pets and guardians (C1).
  - The 8-yard deadzone and ranged range polls (C11).
  - Ranged haste (stale in combat).

## 6. Warrior: gaps vs wowsims
- **Sim:** `ui/specs/warrior/dps/apls/arms.apl.json`, `fury.apl.json`, `ui/specs/warrior/protection/apls/default.apl.json`.
  Code: `sim/warrior/heroic_strike_cleave.go:66`, `whirlwind.go`, `overpower.go`, `talents_arms.go:230,253,418`,
  `stances.go`.
- **Fury** is covered by `docs/research/2026-10-18-fury-vs-wowsims.md` and the Fury run on `forever-fury`. It is not
  repeated here.
- **Arms** (fork `tools/packs/warrior/Arms.simc`) vs the sim:
  - Rend in Battle Stance at ≤ 1.5 s remaining, outside execute. The fork only Rends without the Mortal Strike talent.
  - Overpower in Battle Stance. Present.
  - Slam when its cast < 1.5 s, or right after a main-hand swing (`autoTimeSinceLast ≤ inputDelay + 300 ms`). The fork
    only Slams without MS. The Swing family has `mainhand` timing, so this is a pack line.
  - Execute at 20%. The fork has a separate list.
  - Heroic Strike at rage ≥ 90 (the fork uses MS-relative thresholds) and Cleave at > 1 target and rage ≥ 40.
  - Bloodrage at < 90. Present.
  - Battle Shout at ≤ 10 s remaining. The fork tests `!up`.
  - The stance dance and Hamstring weave options (`Windfury Totem` aura 10610/10612, party buffs). Skip the Hamstring
    weave: party-totem dependent.
- **Protection** (fork `tools/packs/warrior/Protection.simc`) vs the sim:
  - Shield Block at rage ≥ 40, or when Revenge is near ready and its proc is down. The fork uses
    `buff.shield_block.stack < 2`.
  - Defensives: Last Stand at HP ≤ 40%, Shield Wall at ≤ 35%, Stoneform at ≤ 50%, Healthstone at ≤ 30%. The fork has
    none. They belong in the Defensives display, and player health is polled.
  - Bloodthirst and Mortal Strike for hybrid builds.
  - Rend when not up.
  - Sunder at < 5 or ≤ 10 s remaining. The fork uses 3 s.
  - Demoralizing Shout with a 6 s overlap.
  - Thunder Clap at > 2 targets first.
- **Focus:**
  - Arms Overpower gets 1. Execute and Victory Rush get 1 (Fury doc).
  - Rend refresh gets 2. Battle Shout ≤ 10 s gets 2. Slam after the swing gets 2 (a swing window).
  - Protection: Last Stand and Shield Wall get 1 (reactive health). Shield Block gets 2. Shield Bash, Taunt and
    Mocking Blow get 1.
- **Unmodelled:** none new. The Spearing Strike 2H requirement (`talents_arms.go:230`) is a gear read; the Items
  `main_hand` row exists.

## 7. Mage
- **Sim:** `ui/specs/mage/dps/apls/arcane.apl.json` (default), `deepFire.apl.json` (Fire), `ffb.apl.json` (Frostfire).
  Code: `sim/mage/arcane_charge.go`, `talents_arcane.go:100,233-280`, `talents_fire.go:184-226`,
  `talents_frost.go:205-275`, `mana_gems.go`. There is no Water Elemental in the sim.
- **Shared head:** at mana ≤ 10%, the Skyborne racial (1259705), then Evocation channelled until 99%.
- **Arcane:**
  Arcane Missiles on Missile Barrage (400589) → Arcane Wrath (1326082, Forever-only) → Arcane Blast by charge count (400573) and absolute mana (≥ 5000 / 4000) → Frostbolt.
- **Fire:**
  Scorch while Fire Vulnerability (22959, target) has < 5 stacks or < 5 s left → Cooldowns → **Pyroblast at 3 Heating Up (400625).** → Fire Blast → Missiles on Barrage → Fireball.
- **Frostfire:** Fire's head, then Fire Blast only with Fingers of Frost (400669) < 2, then Frostfire Bolt
  (1237313, Forever-only).
- **Fork:** none. Research: `docs/research/2026-10-15-forever-mage/research.md` (§2 mana, §6 casts, §10 risks).
- **Focus:**
  - Missiles on Barrage gets 1. Pyroblast at 3 Heating Up gets 1. Counterspell gets 1.
  - Scorch to refresh Fire Vulnerability gets 2. Evocation and gems at low mana get 2.
- **Unmodelled:**
  - Channels: Missiles (shortened by Barrage), Evocation (C8).
  - Mana as an absolute value. Absolute thresholds become fractions of the maximum or settings (C3).
  - Mana gems as items (C12).
  - School lockouts (C10). The proc auras (C2).
  - Fire Vulnerability stacks from our Scorches (modelled `addStack`, exists).
  - Spell haste staleness (C13).

## 8. Warlock
- **Sim:** `ui/specs/warlock/dps/builds/`: `aff_wrack.build.json`, `sm_ruin.build.json`, `demo_fire_brand.build.json`
  (default), `demo_shadow_brand.build.json`, `destro.build.json`. Code: `sim/warlock/agony.go`, `conflagrate.go`,
  `wrack.go`, `soul_shards.go`, `pets.go`, `summon.go`, `talents_affliction.go:153`, `talents_demonology.go:222,309`,
  `apl_values.go`.
- **Affliction:**
  Amplify Curse, then Bane of Agony → Corruption, Siphon Life, the curse, then Immolate, each when down → Shadow Bolt for Shadow Vulnerability (17794) → **Shadow Bolt on Shadow Trance (17941).** → Wrack (1316697, channel, Forever-only) while Corruption and Agony both have ≥ 4 s left → Shadow Bolt, then Life Tap.
- **Demonology:**
  Bane of Doom when ≥ 60 s remain → Searing Pain for Demonic Brand (1293696, target) → Immolate, then the curse → Life Tap when the **pet's mana** is short → **Soul Fire on Decimation (440873).** → Corruption → Searing Pain or Shadow Bolt filler.
- **Destruction:**
  Doom or Agony by the fight left → The curse, then Immolate, then Corruption → Conflagrate while Immolate is up → Shadowburn → Incinerate (1293813) → Life Tap.
- **Refresh rule:** every list refreshes only once a DoT has dropped. That suits modelled debuffs, because no target
  durations are needed beyond our own timers.
- **Fork:** none. Research: `docs/research/2026-10-15-forever-warlock/research.md` (§2.2 shards, §5 pets, §9 risks).
- **Focus:**
  - Shadow Bolt on Shadow Trance gets 1. Soul Fire on Decimation gets 1.
  - Bane, Corruption and Immolate refreshes get 2. Amplify Curse gets 2.
- **Unmodelled:**
  - Pets (C1). Pet mana is unreadable (`UnitPower("pet")` answers 0, `Facade.lua:230`), so it becomes a setting.
  - Soul shards (C12).
  - Several concurrent DoTs and the one-Bane / one-Curse exclusivity (content, S).
  - Channels (C8). The five-second rule and Life Tap's gain (C3).
  - Fight-length guards (D2).
  - Demonic Brand charges spent by the pet: invisible, so model them as a timer.

## 9. Priest Shadow
- **Sim:** `ui/specs/priest/dps/builds/testing.build.json` (Shadow), `smite_testing.build.json` (Smite, skip: Holy
  damage is out of scope unless asked). Code: `sim/priest/mind_flay.go`, `talents_shadow.go:107`. There is no
  Shadowfiend in the sim.
- **Priority:**
  - Precombat: Shadowguard, Mind Blast.
  - Main list:
    Shadowform → Dark Sacrifice (1277328) at mana ≤ 2000 → Racials → SW:Pain, then Devouring Plague, each when down → Mind Blast → SW:Death (1309636) → Inner Focus → Mind Flay → Mind Flay channelled to its third tick, which is the full channel.
- **Fork:** none. Research: `docs/research/2026-10-15-forever-priest/research.md` (§6 Shadowform as a stance-like aura,
  §9 channels).
- **Focus:** SW:P and Devouring Plague on drop get 2. Dark Sacrifice at low mana gets 2. Silence or an interrupt, if
  known, gets 1.
- **Unmodelled:**
  - Mind Flay channel and `now` timing (C8).
  - Shadowform through the Forms source. `GetShapeshiftForm` is plain; verify that it lists Shadowform (S).
  - C3, C10, C13.

## 10. Shaman Elemental
- **Sim:** `ui/specs/shaman/elemental/builds/testing.build.json`. Code: `sim/shaman/lava_burst.go:40`,
  `fire_totems.go`, `shields.go`, `elemental/elemental.go`. Forever's Revelation enchant procs are listed in
  `sim/common/forever/enchants.go:14-23`.
- **Priority:**
  - Precombat: Water Shield, Strength of Earth, Windfury Totem, Mana Spring, then Searing (1 target) or Magma (> 1).
  - Main list:
    Mana potion / rune → Mana Tide (1325256) at < 50% → The fire totem when empty → At > 1 target: Fire Nova, then Chain Lightning → Lava Burst (1326047) while Flame Shock is up → Flame Shock multidot on up to 3 targets → Earth Shock on Revelation (1323418) → Elemental Mastery → Lightning Bolt.
- **Fork:** none, and no brief.
- **Focus:** Earth Shock on Revelation gets 1. Flame Shock on drop gets 2. The fire totem refresh gets 2. Mana Tide gets
  Lava Burst gets none (rotation).
- **Unmodelled:**
  - Multidot across targets (C14; start single target).
  - Totems (C6). C3. Spell haste (C13).
  - The Revelation proc from a weapon enchant (C2/C4).

---

## Unmodelled capabilities

| # | Capability | Specs | How to model it on Forever | Size |
|---|---|---|---|---|
| H | Harness: class-neutral loop gate | every new pack | `tests/Game/harness/loop.lua` takes `content.rage(hand, amount, flag)` (line 25, 94). Generalize it to a per-power gain hook so an energy, mana or combo-point pack can drive it. Add a `tests/Forever/helpers/<class>_world.lua` per pack. A shared `pack_gate.lua` (the `arms_gate.lua` shape) prints `<Spec> solo:` and gates agreement, react, refusals, errors, misses, secrets and CPU. The world already does casts and regen (`world.lua:124-138, 280-293`). | M |
| C1 | Pets and guardians | Hunter BM/SV, Warlock all, (Mage, Priest: none in the sim) | `pet.up` already works (`UnitExists`/`UnitIsDead` plain). Add facade rows: `UnitGUID("pet")` creature ID (probe) and `UnitCreatureFamily` (absent from `tools/api_inventory.txt`). Add a belief **Pets family**: `UNIT_PET` makes it observed. Our summon cast plus the creature's duration is modelled (guardians: Summon Hawk count, cap N, 18 s each). Add a Now verb `summonPet(key, dur)` to `Families/Now.lua` NAMES. Pet power and health stay unreadable, so they become settings. Content API bump. | M |
| C2 | Proc and player-aura visibility in combat | every spec with a proc line (Clearcasting, Maelstrom, Barrage, Heating Up, FoF, Shadow Trance, Decimation, Cutthroat, Echoes, Revelation, Eclipse) | The player walk (`Sources/Auras.lua`) stops at the first secret. Rank the reads: (1) the walk where the aura is plain, (2) `C_SpellActivationOverlay.IsSpellOverlayed` (plain, in the facade), (3) a usability flip of the proc-gated spell (Ambush, Mongoose Bite: Power ladder, poll 2), (4) model it from our cast for self-applied stacks (Arcane Charges, Heating Up from Fire Blast). Add a per-aura Schema field `overlay = spellID`, which a new poll reads into a `Read`. In game: one probe per class (D5). | M |
| C3 | Mana, the five-second rule, casting vs idle regen | every caster, Paladin, Enhancement, Hunter, Balance | `Families/Resources.lua` has one calibrated rate. Add a resource meta `fsr = { spirit, mp5 }`. After our own mana spend (Now writes the cost) the spirit part pauses for 5 s. Calibrate each part in its own state. Thresholds in packs use `mana.pct` (the maximum: `docs/research/2026-10-16-player-max-health-mana.md`). Absolute sim thresholds (AB at ≥ 5000, Dark Sacrifice ≤ 2000) become fractions of the maximum. C3b: a `mult` on regen entries (Adrenaline Rush, Energized). | M |
| C4 | Weapon enchants (poisons, imbues, stones, Revelation enchant) | Rogue, Enhancement, Elemental, Warlock | Add a `C_Item.GetWeaponEnchantInfo` facade row. Its secrecy is unknown (Rogue Q9), so probe it. Poll it out of combat into a player pseudo-aura (`main_hand_enchant` / `off_hand_enchant`) with observed expiry. In combat it is modelled from our apply cast. Only precombat lines read it. | M |
| C5 | Stealth and openers | Rogue (Druid Prowl already via form) | `IsStealthed` is plain in the API index. Add a facade row and a `Sources/Forms.lua`-style read that puts the stealth aura up or down. If `GetShapeshiftForm` reports Stealth on a Rogue, Forms already covers it (Rogue Q6). Breaking stealth uses the `startsCombat` hook. | S |
| C6 | Totems on the sim side | Enhancement, Elemental | The belief has the slots. Content registers `RegisterTotems` with element and duration, and the summon's `now` writes the modelled expiry (`Families/Totems.lua` already treats an update just after our cast as a summon). Fire Nova's "needs a fire totem" comes free from usability. Verify Forever's slot order out of combat. | S |
| C7 | Ranged auto-shot clock | Hunter | Accept `swingType == 2` in `Sources/Swing.lua:18` and `Events/Rows.lua:265`. Give `Families/Swing.lua` a third hand. Add a `UnitRangedDamage` facade row (out-of-combat speed), and map Hekili's auto-shot names onto it. Probe whether `PLAYER_SWING` fires for ranged on Forever (Hunter Q2). | L |
| C8 | Channels: clip and the timing of `now` | Mage, Warlock, Shadow, Balance (Hurricane) | Casts tracks channels and `CastDelay`. Hekili's `CheckChannel` (`Engine/Sim/Core.lua` ~459) needs `tick_time` on the ability. Content declares `channeled`, `tick_time` and `start`. Probe whether SUCCEEDED fires at channel start (Mage Q8). A clip such as Evocation at 99% mana is unreadable, so channel it in full. | S |
| C9 | Ladder pins on multi-requirement spells | Rogue finishers, stealth openers, Paladin Echo seals | `Families/Resources.lua` pins a resource on a "short" answer. Add an ability field `ladder = false`, or a `usable` precondition checked before the pin, as the Druid Rip does. | S |
| C10 | School lockouts | Mage, Warlock, Shadow, Elemental | `src/Hekili_Shared/Shared/Auras.lua:67` keeps `lockoutSchool == 0` only. Add a per-school `locked_out` StateExpr from `C_LossOfControl` (plain). | S |
| C11 | Ranged range and deadzone, caster AoE count | Hunter, casters | `Sources/Nameplates.lua` poll 8 counts plates in range of an attack's spell. Register the ranged spell as the tracked attack. Add a deadzone read with `IsSpellInRange` of a melee spell. | S |
| C12 | Item counts as resources | Warlock shards, Mage gems, mana potions, Demonic Rune, Thistle Tea | A `C_Item.GetItemCount` StateExpr (plain [W PR13]), as `Shared/Consumables.lua` does for Healthstone. Add the new consumables to Shared (item IDs from wowdb `ItemSparse`). Two shard spells in one queue is a known over-recommendation (shortcut). | S |
| C13 | Spell haste in combat | casters | `UnitSpellHaste` is secret in combat and the facade keeps the last plain read. Add a modelled multiplier from our own haste auras (Berserking, Elemental Mastery is crit, so skip it) through `Families/Modifiers.lua`. Defer. | M |
| C14 | Multi-target DoTs | Elemental Flame Shock ×3, Bane of Havoc | Per-target memory (`TARGET_CAP`) only fills for targets we hold. `active_dot` needs our own cast rows to carry a dest GUID (synthesized CLEU: check it). Ship single target first. | M |
| C15 | DoT miss and resist | every DoT spec | The Druid's `missedAt` (`Druid.lua:586-620`, synthesized `SPELL_MISSED`) generalizes into a Schema ability field `missable = true` handled in core. | S |
| C16 | Interrupts per class | Rogue Kick, Mage Counterspell, Shaman Earth Shock, Paladin (if any), Priest Silence | The TargetCast family and the Interrupts display exist (Warrior Shield Bash). This is content only. | S |
| C17 | Fight length | Feral, Rogue, Warlock | Time to die was dropped (`Families/TargetHealth.lua` header). Replace with `boss` and settings (D2). | S |

Already modelled and only to reuse: combo points and energy (Druid), charges (`Families/Casts.lua`, facade
`chargesPolicy`), forms and stances through `Sources/Forms.lua`, health gates (`healthGate`), on-next-swing
(Raptor Strike), player health (Player poll), racials (`src/Hekili_Shared/Races/`; check Forever's Elune's Light
1259799, Eureka! 1259812/1259821/1259823 and Skyborne 1259705 against wowdb), and the Healthstone and potion pattern.
