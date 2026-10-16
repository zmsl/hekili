<!-- Ported from TacoDogForever docs/research/2026-10-13-research-findings-for-lanes.md (credit: TacoDogForever), copied here because that repo is being retired. -->
# Extras to fold into Phase 1 lane dispatches (from research reports)

## 1D2 (owns TacoDogForever_Warrior/Warrior.lua)
- Bloodrage aura ID: the shipped pack uses 2687; Forever's Bloodrage buff is **29131** (Protection research,
  verified against DB2 1.60.1.70338). Fix with a test that the pack's aura IDs exist in the data addon.
- Classic-style debuffs (Rend, Sunder, Thunder Clap, Demoralizing Shout) refresh with `pandemic = 0`.

## 1E (display mode) / Phase 2 2C1
- `Belief.enemies` is never written today (stays 1) so `active_enemies` is inert; 1E's clamp `enemies = max(detected,
  aoe)` is the first writer. Make the clamp test cover `detected = 0` (no nameplate lane yet).

## Reconciliation re-scopes (apply at the next phase merge)
- **G089 classic Druid settings shrinks**: powershifting is dead on Forever (Furor returns only the energy you had
  on leaving Cat Form; Omen of Clarity is a level-20 passive). Hekili's `powershift_*` / `claw_trick` settings and the
  precombat Omen cast retire as "not portable on Forever (mechanic removed)". "Must be behind" (Shred vs Claw) stays.
- Rune spells (Starsurge, Sunfire, Starfall, Skull Bash, Savage Roar, Kill Command, SoD SW:D …) sit in the DB2 but
  Forever has no engraving: treat as absent everywhere (data lane flags them).

## Data-pipeline lane (after all research docs; owns tools/gen_data.py, tools/data, TacoDogForever_Data)
- `select()` requires `class_mask != 0`; Forever's new ranked spells have SkillLineAbility mask 0 and are dropped
  (Priest SW:D 1309595/1309633/1309635/1309636 replaced by SoD rune 401955).
- Triggered auras missing: 15258 Shadow Weaving, 15271 Spirit Tap, 6788 Weakened Soul (generalise: include auras
  triggered by a class's spells, not only the spells).
- Talent table generated is the Classic tree; Forever talents are single rank-scaled spells.
- `families.json`: drop Sunder Armor from `armor_reduction` (no longer conflicts with Expose Armor on Forever).
- Concussion Blow: DB2 shows GCD 0 ms with category 133 — check how gen_data derives GCD for category-133 spells.
- Hunter (same mask-0 cause): Aimed Shot ranks 2–6, Trueshot Aura ranks, Sniper Shot, Lacerate, Hydra Shot, Expose
  Prey, Rapid Killing missing or truncated. Kill Command exists only as the SoD rune — do not carry SoD runes into a
  class's spell list when a Forever spell of the same name is absent (flag them `sod = true` or drop them).
- Mage: Evocation 12051, wand Shoot 5019 and the Forever talent-granted buff IDs (400573, 400589, 400625, 400669/70,
  1312934, 28682, 12579) are missing because the generator keeps only class-skill-line spells. Generalise: include
  (a) general skill-line spells every class has (Shoot, Attack, racials later), (b) auras applied/triggered by any
  kept spell, (c) talent-granted spells (Forever talents are spells; walk Talent → spell IDs).
- Druid: Innervate, Eclipse and Nature's Splendor IDs missing. The Forever DB2 is queryable directly at
  `~/.local/share/wow-db2/forever/current.sqlite` (the Talent table there is the stale Classic tree).
- Warlock: Curse of the Elements (440892, 1311676, 1311677, 1311680) and Bane of Agony rank 2 (1014) missing (mask
  0). Dormant SoD leftovers to exclude: Chaos Bolt, Metamorphosis, Shadow Cleave, Shadowflame, Fel Armor.
- Paladin: `seal_of_command` has rank 1 only (ranks 2–5 = 20915, 20918, 20919, 20920); `holy_shield`, `holy_shock`
  one rank each; `judgement_of_the_crusader` missing rank 1 (21183); `righteous_fury.ids` lists the SoD id 407627
  before the learned 25780 → **rank/ID ordering rule: real trainer/talent ranks first, SoD ids last or excluded**.
  Missing keys: Templar's Bulwark, Sacred Arbiter, Iron Creed, Holy Conduit, the Echo auras.
- Talent API lead: the Forever addon **iSealTwist 0.7.1** claims to read talents through a talent-tree API — read its
  source (CurseForge/GitHub) to learn which call (`C_Traits`? `C_SpecializationInfo`? `GetTalentInfo`?) and feed PR5 /
  Phase 2 lane 2B. Small research task.
- Rogue: new talents missing (Flawless Execution, Coup de Grace, Thousand Cuts, Quietus, Cutthroat, Puncturing
  Wounds, Dirty Tricks); **combo-point-scaled durations are exported as the base only** (Slice and Dice, Rupture,
  Venom say 6 s; real = base + per-CP) → the data needs a `durationPerCombo` (or per-point table) field and the
  engine's aura duration must take the CP count at cast; Sunder/Expose Armor family should be `strongest`, not
  `replace`, on Forever. SoD runes (Saber Slash, Main Gauche, Between the Eyes…) unavailable.
- Energy regenerates **continuously** on Forever (rogue research; no tick) — resolves spec §15's energy tick-grid
  question for Feral too: model regen as a rate, keep the tick grid only if a probe shows ticks.
- Mage research notes mana is secret **even out of combat**; percent-of-base-mana costs (Arcane Blast 15 % base) need
  the base-mana read — Phase 3 lane 3D, flag it there.
