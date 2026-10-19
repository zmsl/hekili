# Class Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Approved by the user 2026-10-18** with decisions D1-D7 taken (see "Decisions"). Execution: one opus controller per day or two from the SDD ledger; the merge into `forever` after each day's gates.

**Goal:** Every Forever DPS and tank spec is at least modelled. That means a class pack with wowsims/forever's
rotation as its APL basis, `focus=N` on its non-rotational timing-bound lines, and a headless `<Spec> solo:` gate. The
order is Druid first, then the remaining melee, then the casters. No healing specs.

**Architecture:** Capabilities land before the specs blocked on them. Each capability is one belief family, Schema field or facade row change behind the existing seams: Sources → Families → `Hekili.Client`/`now` → content; Each new class is a load-on-demand content addon, `src/Hekili_<Class>/`, shaped like `Hekili_Warrior`. Its APLs are SimC text in `src/Hekili_<Class>/APLs/` (the `forever-fury` layout), plus a manifest, `make packs`, and a class-neutral harness gate.

**Tech Stack:** Lua 5.1 (WoW), busted headless harness (`tests/Game/harness/`), `tools/make_pack.lua`, `wowdb` for
every spell and item ID (`~/.local/share/wow-db2/bin/wowdb spell <name>`; item IDs from its `ItemSparse` table).

**Spec:** `docs/research/2026-10-18-class-completion-research.md` (per-spec APL basis, focus picks, capabilities
C1-C17 and H). The per-class briefs `docs/research/2026-10-15-forever-{rogue,hunter,mage,warlock,priest}/research.md`
hold the DB2 tables and checkpoint questions.

## Global Constraints

- `make check` green before every commit. Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Recommendations stay byte-identical for untouched packs: `Arms solo:` lines are unchanged except timings; The `tests/Forever/arms_recs_spec.lua` fixture is untouched, unless the task changes Arms on purpose (then re-record it with `ARMS_RECS=record`); `make test-druid` is green.
- Boundary rule (`tests/boundary_spec.lua`): no class, spell, aura or form name in `Game/`, `Engine/Schema/` or the
  harness. Class content lives only in `src/Hekili_<Class>/` and `tests/Forever/helpers/<class>_*.lua`.
- Secret safety: a new facade row or source goes through `Plain`/`issecretvalue` first. A row whose secrecy is
  unprobed is `hybrid`, with the belief as the fallback, and is marked "unprobed" in the facade note.
- No new tables, closures or string building in recurring paths (Update, UNIT_COMBAT, polls). `make bench` is
  reported for every core task.
- Any change to `Hekili.Client`, the Register* API or the `now` names bumps `CONTENT_API` and every content TOC's
  `## X-Hekili-ContentAPI` together (`tests/Forever/content_spec.lua`).
- Spell and item IDs come from wowdb, never from memory or wowsims alone. Forever-only spells (≥ 1,000,000) and
  Season-of-Discovery rune spells get registered only if learnable (D4).
- Credit wowsims/forever (MIT) in each new pack header, as a reference only: no code copied.

## Review Focus

1. **The harness generalization (T1) must not change Arms.** The three `Arms solo:` lines must match their
   recorded numbers. Test: rerun `make check` and compare with `docs/dev/layout.md`.
2. **A ladder precondition (T3) must stop a finisher's "short" answer from pinning energy.** Test: a Rogue Eviscerate
   at 0 combo points pins nothing (resources_spec).
3. **New facade rows (T4, T10, T11) never pass a secret to content.** Test: each row's spec covers the secret case,
   and the traced fight's `m.secrets` stays `{}`.
4. **A Pets family (T10) summon must yield to the first observation.** `UNIT_PET` or `UnitExists` overrides the
   modelled up state. Test: a summon whose pet never appears is down after the cast window.
5. **Each pack's gate must exercise its focus lines.** Test: the gate's report counts records with `focus` set, and
   the count is above 0 for every spec with a flagged line.

## Decisions (user, 2026-10-18; binding)

- **D1 Focus tiers.** `focus=N` is a priority tier (merged d66f6dcc): lowest number first, soonest within a tier, a
  ready flagged press always wins the Now circle. Use tier 1 for reactive or costly-to-miss lines, tier 2 for
  predictable upkeep and timing windows.
- **D2 Fight length.** DoT lines gate on `boss`, plus a per-pack setting "short fights: skip DoTs under N s",
  default off. No time-to-die estimate.
- **D3 Hunter basis.** Turret (MM), Turret Hawk (BM), Melee (SV). The melee weave is out of scope.
- **D4 Rune and Forever-only spells.** Register all of them; `known` comes from the spellbook, so an unlearnable
  spell's lines are inert. No per-class learnability check first.
- **D5 Probe budget.** Druid only this week. Every other spec ships "provisional" in its pack description; its
  checkpoint questions go into the T18 ledger. T11 therefore builds the modelled auto-shot clock (from Auto Shot
  casts and the ranged speed) without the `PLAYER_SWING` measurement; Marksmanship ships as "shots without
  weaving"; the measurement stays on the ledger.
- **D6 Out of scope.** Out: pet-bar abilities (Spell Lock etc.) and the Paladin item swap. In: the Hamstring weave
  (Arms gets the Windfury-gated Hamstring line in T5, as Fury has) and the Priest Smite/Holy damage build (T16 adds a
  `Smite` APL beside `Shadow` in the same pack). Multidot (Flame Shock ×3, Bane of Havoc) stays deferred until C14.
- **D7 Absolute mana thresholds.** Fractions of the maximum, one setting per line.
- Also settled: combo points are plain in combat (research addendum), so no event-driven combo-point estimate.

## The per-pack gate (every class task uses this)

- `tests/Forever/helpers/<class>_world.lua` holds the class content of the class-neutral loop, in the
  `warrior_world.lua` shape. Through a recording load of the class file (as `load_druid.lua` does) it provides: `character()`; `PACK`; `resolve(key, H)`: each press in the world's verbs (cast, cost, cooldown, GCD, debuffs); `usable(H)`; `gain(pt, ...)`: from T1; `WORLD` and `uptime(H)`.

  Damage numbers are unmeasured. The gate scores the belief and the picks, not the DPS.
- `tests/Forever/loop_<class>_spec.lua` runs 3 fights per spec in `make check`. A `#<class>` describe runs 20 fights,
  and a Makefile target `test-<class>` runs that tag (`make test-druid`'s pattern). Each spec prints `<Spec> solo:` and
  calls `pack_gate.gate`: agreement ≥ 0.85; react median ≤ 1 and p90 ≤ 3; no GCD or cooldown refusals; cost refusals ≤ the oracle's + 3; errors, raises, self-check, misses and secrets all empty; CPU mean ≤ 10 ms.

  The first passing run's line goes into the commit message and into `docs/dev/layout.md` beside the Arms lines.
- `tests/Forever/<class>_spec.lua` holds the unit specs for the class file: `now` handlers, auras, the focus lines'
  conditions.
- **New addon checklist:** `src/Hekili_<Class>/Hekili_<Class>.toc`: `## Dependencies: Hekili, Hekili_Shared`, `## LoadOnDemand: 1`, `## X-Hekili-ContentAPI`, `## Group: Hekili`; The tools/packs manifest; `tests/helpers/addons.lua`; The `mklink` line in `docs/dev/layout.md`; A `docs/dev/architecture.md` §3 addon list entry; `Engine/Content.lua` finds the pack by class token, with no code change.

---

## Day 1: harness and Druid

### Task 1: class-neutral loop gate (H) [M]
**Files:** `tests/Game/harness/loop.lua`, `tests/Forever/helpers/pack_gate.lua` (new),
`tests/Forever/helpers/arms_gate.lua`, `tests/Forever/helpers/warrior_world.lua`.
**Interface:** `content.gain(pt, hand, amount, flag)` replaces `content.rage(...)`. `warrior_world` maps rage onto it; `pack_gate.gate(m, r, line)` and `pack_gate.solo(label, world, n, seed0)` are the `arms_gate` body, label-driven; `arms_gate` keeps `M.REPORTED` and delegates.

**Steps:**
- [ ] Spec: `loop_spec` (new, small): a stub energy world drives two fights, and the energy pt's gains reach the
  observer.
- [ ] Generalize the loop, then move the gate body to `pack_gate`.
- [ ] Gate: the three `Arms solo:` lines are unchanged except timings; `arms_recs` untouched; `make bench` reported.

**Deps:** none.

### Task 2: Druid aligned with wowsims, plus three solo lines [M]
**Files:** APLs: `src/Hekili_Druid/APLs/{Feral,Guardian,Balance}.simc` (the APL move is merged, d66f6dcc); `src/Hekili_Druid/Druid.lua`; New: `tests/Forever/helpers/druid_loop_world.lua` (reuses `druid_world.lua`'s character and presses) and `tests/Forever/loop_druid_spec.lua`.

**Content** (research §1): Feral:.
  - `shred,focus=1,if=buff.clearcasting.up`;
  - Shifting Power at 40 under Clearcasting;
  - Berserk ahead of a due Rake;
  - Innervate in Cat (`focus=2`);
  - Rake `focus=2`;
  - Rip stays `focus=1`.
- Guardian: Frenzied Regeneration at `health.pct<20` (`focus=1`); Berserk after Primal Bite; the Lacerate refresh window as a setting (default 4.5 s, the sim's 1.5 s noted), `focus=2`.
- Balance: Innervate at `mana.pct<10`; Starfire on Eclipse `focus=1`; DoT refresh `focus=2`.

**Steps:**
- [ ] Specs first: each new condition in `druid_spec.lua`.
- [ ] Edit the APLs, then `make packs`.
- [ ] Gate: `Feral solo:`, `Guardian solo:` and `Balance solo:` printed and gated. `make test-druid` green. The pack
  date bumps.

**In game (user):** Feral Clearcasting is visible in combat, as the aura walk or the overlay (feeds T3b).
**Deps:** T1. D1 for the tiers.

## Day 2: small core capabilities, facade rows, Warrior gaps

### Task 3: ladder precondition, missable DoTs, school lockouts, consumables (C9, C15, C10, C12) [S each]
**Files:** `src/Hekili/Game/State/Families/Resources.lua` (pin only when the ability's `ladder ~= false` and its `usable` precondition holds); `src/Hekili/Engine/Schema/Spec.lua` (document `ladder` and `missable`); Core handling of `missable = true`, built from `Druid.lua:586-620`. The Druid then declares `missable` and drops its own copy; `src/Hekili_Shared/Shared/Auras.lua:67` (a `locked_out` StateExpr per school); `src/Hekili_Shared/Shared/Consumables.lua` (Major Mana Potion, Demonic Rune, Thistle Tea, mana gems; item IDs from wowdb).

**Tests:** `tests/Game/State/resources_spec.lua` (a 0-CP finisher pins nothing), `tests/Forever/druid_spec.lua` (the
missed bleed still drops), `tests/Forever/shared_spec.lua`.
**Gate:** Arms unchanged; `make test-druid` green; CONTENT_API bump if `ladder` or `missable` is new content surface.
**Deps:** none.

### Task 3b: proc visibility (C2) [M]
**Files:** `src/Hekili/Game/State/Sources/Auras.lua` or a new `Sources/Overlay.lua` (a poll over registered auras with
`overlay = <spellID>`, reading `C_SpellActivationOverlay.IsSpellOverlayed`, plain), `Engine/Schema/Spec.lua`
(`overlay` aura field), and `Families/Auras.lua` (an overlay read is a `Read` with no expiry).
**Tests:** `tests/Game/State/auras_spec.lua`, with an overlay on and off in combat and the walk secret.
**In game:** which Forever procs light an overlay (one `/run` per class with a proc; VSCopy).
**Deps:** none.

### Task 4: facade rows (C4, C5, and probe-only rows for C1 and C7) [M]
**Files:** `src/Hekili/Game/API/Facade.lua` and `tools/api_inventory.txt`.
- `C_Item.GetWeaponEnchantInfo` is hybrid, unprobed. An out-of-combat poll writes the `main_hand_enchant` and
  `off_hand_enchant` pseudo-auras in a new `Sources/Enchants.lua`. In combat the expiry is modelled from our apply cast.
- `IsStealthed` is plain per the API index. It goes into `Sources/Forms.lua`'s pattern as a tracked stealth aura.
- `UnitCreatureFamily` and `UnitRangedDamage` are hybrid, unprobed.

**Tests:** `tests/Game/API/facade_spec.lua`, with each row's secret case.
**Gate:** `make api-check` and `tools/check_api_reads.sh` clean. CONTENT_API bump.
**In game:** Rogue Q5, Q6 and Q9 (`docs/research/2026-10-15-forever-rogue/research.md` §7) and Hunter Q2.
**Deps:** none.

### Task 5: Warrior gaps vs wowsims [S]
**Files:** `src/Hekili_Warrior/APLs/{Arms,Protection}.simc` and `src/Hekili_Warrior/Warrior.lua` (settings).
- Arms: Rend in Battle Stance at ≤ 1.5 s, outside execute, also with Mortal Strike (`focus=2`); Slam after the main-hand swing, gated on `mainhand_remains` (`focus=2`); Battle Shout at ≤ 10 s; Overpower `focus=1`; Hamstring with Windfury up, the Fury line's shape (D6: in scope).
- Protection: Shield Block at rage ≥ 40, or when Revenge is near ready; Last Stand, Shield Wall, Stoneform and Healthstone on health in the Defensives display (`focus=1`); Rend when not up; Sunder at ≤ 10 s; Shield Bash, Taunt and Mocking Blow `focus=1`.

**Gate:** Arms changes on purpose, so re-record `arms_recs` and record the new `Arms solo:` lines in `layout.md`.
`warrior_spec.lua` covers the new conditions. `make test-party` green.
**Deps:** the Fury run merged (`forever-fury`), so the APL paths and `focus=2` exist. D1.

## Day 3: mana, then Rogue

### Task 6: mana with the five-second rule (C3, C3b) [M]
**Files:** `src/Hekili/Game/State/Families/Resources.lua`, `Game/State/Adapter.lua` (forward a resource's `fsr` meta),
`Engine/Schema/Spec.lua` (document `fsr = { spirit = fn, mp5 = fn }` and a regen entry's `mult`).
**Behaviour:** Our own mana spend (Now's cost write) opens a 5 s window. In it, only the mp5 part regenerates; calibration keeps one EMA per part; `mult` scales the calibrated rate while its aura is up (Adrenaline Rush, Energized).

**Tests:** `tests/Game/State/resources_spec.lua`: the 5 s window, a calibration across windows, a `mult` aura.
**Gate:** Arms unchanged. `Balance solo:` refusals no worse than the T2 baseline. `make bench` reported.
**Deps:** none.

### Task 7: Rogue pack [L]
**Files:** new `src/Hekili_Rogue/` (`Hekili_Rogue.toc`, `Rogue.lua`, `APLs/{Combat,Assassination,Subtlety}.simc`), the
manifest, `tests/Forever/{rogue_spec,loop_rogue_spec}.lua`, `tests/Forever/helpers/rogue_world.lua`, and the
new-addon checklist.
**Content** (research §2): Energy and combo points, as the Druid has them; Stealth (T4), poisons as precombat reminders (T4), finishers `ladder = false` (T3); Cutthroat Ambush `focus=1`, SnD refresh `focus=1`, Rupture and Expose Armor `focus=2`, Kick `focus=1`; Adrenaline Rush as a `mult` (T6); Fight-length guards as settings (D2); Venom only if learnable (D4).

**Gate:** `Combat solo:`, `Assassination solo:` and `Subtlety solo:`.
**In game (user):** a Rogue, Q1-Q9 of the Rogue brief.
**Deps:** T1, T3, T4, T6.

## Day 4: Paladin and Enhancement

### Task 8: Paladin pack (Retribution, Protection) [L]
**Files:** new `src/Hekili_Paladin/` (`APLs/{Retribution,Protection}.simc`), tests and world as the checklist.
**Content** (research §3): Seals are player auras, with one seal at a time (`now` removes the others); Echo auras; Judgement: its effect on the seal is open, so set it from the in-game answer; Hammer of Wrath through `healthGate` (`focus=1`); The Twist of Light seal lines `focus=1`; Consecration and Exorcism in the swing gap (`mainhand_remains>1.5`, `focus=2`); The Holy Shock list chosen by talent; Protection: Seal of Fury, Holy Shield (charges `consumedBy` hits), Swift Judgement, Righteous Fury precombat.

**Gate:** `Retribution solo:` and `Protection solo:` (the Prot world takes hits, as Warrior Protection's does).
**In game (user):** a Paladin. Write the new checkpoint list in the task: seal and echo auras readable in combat,
Judgement and the seal, Hammer of Wrath's usability edge, Holy Shield charges.
**Deps:** T1, T3, T3b, T6.

### Task 9: Shaman Enhancement pack, with totems on the sim side (C6) [L]
**Files:** new `src/Hekili_Shaman/` (`APLs/Enhancement.simc`; Elemental joins in T17), and tests and world.
**Content:** `RegisterTotems` (element, duration from wowdb). The summon's `now` writes the modelled slot expiry, which `Families/Totems.lua` reads; Lightning Bolt at 5 Maelstrom Weapon `focus=1`. Fire Nova on Clearcasting `focus=1`; Totem, Lightning Shield and Flame Shock refreshes `focus=2`; The imbue as a precombat reminder (T4).

**Gate:** `Enhancement solo:`. The world needs totem slots: add totem verbs to `tests/Game/harness/world.lua`
(class-neutral: a slot and an expiry).
**In game (user):** a Shaman. Totem slot order, `PLAYER_TOTEM_UPDATE` in combat, and Maelstrom visibility.
**Deps:** T1, T3b, T4, T6.

## Day 5: pets, the ranged clock, Hunter

### Task 10: Pets family (C1) [M]
**Files:** new `src/Hekili/Game/State/Families/Pets.lua` and `Sources/Pets.lua` (`UNIT_PET`, `UnitExists`/`UnitGUID`
of "pet", plain), the `summonPet(key, dur)` verb in `Families/Now.lua` NAMES, Hekili's `pet.*` reads through the facade,
and guardian counts (a cap, per-summon expiry).
**Tests:** `tests/Game/State/pets_spec.lua`: a summon that is then observed, a summon never seen, a pet death, and
3 guardians against a cap of 2.
**Gate:** Arms unchanged; alloc 0 B per UNIT_COMBAT; CONTENT_API bump.
**Deps:** T4.

### Task 11: ranged auto-shot clock (C7) [L]
**Files:** `Sources/Swing.lua:18`, `Events/Rows.lua:265`, `Families/Swing.lua` (a third hand), the facade
`UnitRangedDamage` row (T4), and the mapping of Hekili's auto-shot state names (find the names in
`Engine/Sim/State.lua`).
**Tests:** `tests/Game/State/swing_spec.lua` (ranged anchors). The harness world grows a ranged hand.
**In game:** deferred (D5: no Hunter this week). Build the modelled clock from Auto Shot casts and the ranged speed
now; the `PLAYER_SWING` `swingType` 2 measurement goes on the T18 ledger and, if it fires, a later task anchors the
clock on it.
**Deps:** T4.

### Task 12: Hunter pack (D3 builds) [L]
**Files:** new `src/Hekili_Hunter/` (`APLs/{BeastMastery,Marksmanship,Survival}.simc`).
**Content:** Mana, with no focus; Summon Hawk guardians (T10); Sniper Shot in Rapid Fire or Quick Shots `focus=1`; Mongoose Bite on usability `focus=1`; Raptor Strike on-next-swing `focus=1`; Serpent Sting and Mark refreshes `focus=2`; Aimed and Multi after Auto Shot `focus=1` once T11 holds; A deadzone guard (C11).

**Gate:** `BeastMastery solo:`, `Marksmanship solo:` and `Survival solo:`.
**In game (user):** a Hunter with a pet. The Hunter brief §7.
**Deps:** T1, T6, T10, T11 (Marksmanship can ship without T11 as "shots without weaving").

## Day 6: channels, Mage

### Task 13: channels (C8) [S]
**Files:** `Engine/Schema/Spec.lua` (document `channeled`, `tick_time`, `start` for content), `Families/Casts.lua`
(the channel end from the declared length when the end is secret), and Hekili's `CheckChannel`, untouched.
**Tests:** `tests/Game/State/casts_spec.lua`, with a channel delayed and one clipped.
**In game:** Mage Q8 (SUCCEEDED at channel start).
**Deps:** none.

### Task 14: Mage pack [L]
**Files:** new `src/Hekili_Mage/` (`APLs/{Arcane,Fire,Frost}.simc`).
**Content:** Missiles on Missile Barrage `focus=1`; Pyroblast at 3 Heating Up `focus=1`; Scorch for Fire Vulnerability `focus=2` (stacks by `addStack`); Evocation and gems at low `mana.pct` `focus=2`; Counterspell `focus=1`; Lockouts (T3); Arcane Blast's mana tests as fractions (D7).

**Gate:** `Arcane solo:`, `Fire solo:` and `Frost solo:` (casts and channels in the world).
**In game (user):** a Mage. Mage brief §9.
**Deps:** T1, T3, T3b, T6, T13.

## Day 7: Warlock, Shadow, Elemental (overflow day)

### Task 15: Warlock pack [L]
**Files:** new `src/Hekili_Warlock/` (`APLs/{Affliction,Demonology,Destruction}.simc`).
**Content:** Soul shards as an item-count StateExpr (T3); Pets via T10; One Bane and one Curse, each removing the others in `now`; Shadow Trance and Decimation `focus=1`. DoT refreshes `focus=2`; Wrack while the DoTs have ≥ 4 s left; Life Tap's mana gain in `now`; Pet mana as a setting.

**Gate:** three solo lines. **In game:** a Warlock with a demon, Warlock brief §8.
**Deps:** T1, T3, T6, T10, T13.

### Task 16: Priest Shadow pack [M]
**Files:** new `src/Hekili_Priest/` (`APLs/{Shadow,Smite}.simc`).
**Content:** Shadowform via Forms (verify); SW:P and Devouring Plague on drop `focus=2`; Mind Flay channel; Dark Sacrifice at a mana fraction. Smite (D6: in scope): the sim's Smite/Holy damage list as a second pack in the same addon, Holy Fire and SW:P upkeep `focus=2`, Inner Focus `focus=1`.

**Gate:** `Shadow solo:`. **In game:** Priest brief Q2 and Q4.
**Deps:** T1, T6, T13.

### Task 17: Shaman Elemental [M]
**Files:** `src/Hekili_Shaman/APLs/Elemental.simc`.
**Content:** Single target first (D6); Searing or Magma by `active_enemies`; Lava Burst while Flame Shock is up; Earth Shock on Revelation `focus=1`; Mana Tide `focus=2`.

**Gate:** `Elemental solo:`.
**Deps:** T9, T13.

### Task 18: docs and the checkpoint ledger [S]
**Files:** `docs/dev/architecture.md` §3: the addon list, the new Schema fields (`ladder`, `missable`, `overlay`, `fsr`, `mult`, `summonPet`) and the focus tiers; `docs/dev/layout.md`: the mklink lines and the solo lines; A checkpoint ledger listing every open in-game question by class.

**Deps:** all.

## Open after Day 1-2 (2026-10-18)
- **Druid, in game:** Innervate unshifts from Cat; Clearcasting arriving in the same frame as the cast that procs it
  (the 0.25 s shortcut in `tests/Forever/helpers/druid_loop_world.lua`); Frenzied Regeneration shown ready during the
  GCD (stock State.lua defensives toggle); a dodged Rake drops through the core SPELL_MISSED route; which Forever procs
  light an overlay; whether UnitHealth("player") is plain in combat (it gates FR at low health and the Warrior
  Protection defensives).
- **Consumable item cooldowns:** taken from wowsims db.json; Mana Agate's 120 s is assumed; the shared potion/rune
  category is unmodelled.
- **Guardian:** reported, not gated (agreement 0.718); it needs core rage precision or rage from damage taken; the
  `cooldown.primal_bite.remains` cause is unverified.
- **Feral:** the D2 "short fights: skip DoTs under N s" guard is unscheduled (research C17 names Feral).
- **Protection:** focus=1 lines but no loop gate; it needs a threat or second-mob scenario (Review Focus 5).
- **Task 3b:** guard the overlay off-read with `I.SAME_FRAME` before the first pack declares `overlay` on a
  cast-modelled aura.

## Open after Day 3 (2026-10-19)
- **Rogue, in game:** Q1-Q13 of `docs/research/2026-10-15-forever-rogue/research.md` §7 (Q3 itself is closed: combo
  points are plain), plus:
  - Q3-new: on a finisher, does the combo-point drop (UNIT_POWER to 0) arrive before `UNIT_SPELLCAST_SUCCEEDED`? If
    it does, the `now` handlers read 0 points and SnD, Rupture and Venom are modelled at their 0-point durations (SnD
    believed down about 6 s after each cast). Fix generically: remember the last nonzero points in Families/Now.lua.
  - Q14: does Premeditation need Stealth on Forever (registered without the requirement)?
  - Q15: Cutthroat: does Ambush read usable out of stealth while 462707 is up, and is the castable Ambush 8676.. or
    462718..462723 (also Backstab 462709.., Garrote 462724..)? Is the 15% chance from Backstab only?
  - Q16 player auras secret in combat; Q17 any hasted GCD under Adrenaline Rush; Q18 poison item use from the
    reminder.
- **Rogue, headless coverage gaps:** Cutthroat Ambush (tier 1), Kick, Expose Armor, Rupture, Garrote and Vanish never
  run in the Rogue solo worlds; every Rogue spec's focus count comes from the Slice and Dice line only.
- **Rogue SnD focus=1** is "when down", not research's "refresh at <= 2 s": settle after Q8 (replace vs extend).
- **Rogue Vanish re-open** has no focus=2 line (only research has it; off on trash by default).
- **Rogue stealth drop:** only Ambush and Garrote's `now` drop Stealth/Vanish; a Sinister Strike, Backstab,
  Hemorrhage or Mutilate opener leaves `buff.stealth` believed up until the IsStealthed read. If Q5 finds IsStealthed
  secret in combat, drop it in every `startsCombat` ability's `now` (final review Minor 2).
- **Closed (8e9d3bf8):** ~~Task 6 residuals, for the first task that declares `fsr`~~ (Day 4 Paladin/Enhancement or a Balance adoption):
  the OOC regen read is skipped for fsr slots (Power.lua): use its two returns (not casting / casting) for the
  spirit+mp5 and mp5 parts; a declared mp5 of 0 never learns; add resources_spec cases for 0 < pinB < PIN_GAP and a
  mult aura expiring between pins; note in Spec.lua that `mana.fsr` is not an APL field.
- **Task 6 shortcuts:** the forecast takes VS.Regen at `now` as constant across a `mult` aura edge (Spec.lua
  `shortcut:`); overlapping `mult` auras add rather than multiply (only one exists).
- **Still open from Day 1-2:** the `locked_out_*` allocation (fix before a caster APL reads it in combat) and the
  overlay `I.SAME_FRAME` guard (Task 3b).

## Open after Day 4 (2026-10-19)
- **Closed (T9b):** ~~Core mana bound decision, before T10~~ (every mana pack hits it): D7 percent floors are judged on the belief's
  lower bound `lo`, which starts at 0 on boot (lo0 = 0) and sits low after spending. Options: judge pct thresholds on
  `est`, or seed lo0 from rest/max on boot when restMax; add a headless case with a long OOC rest. Until then the
  Retribution (Consecration/Exorcism) and Enhancement (Fire Nova, potion/rune) mana floors default 0.
- **Paladin, in game:** checkpoints P1-P9 in `docs/dev/layout.md`. **Shaman, in game:** S1-S10.
- **Paladin, headless gaps:** the Holy Shock list and Hammer of Wrath's window never run; partial blocks (BLOCKED) are
  never produced (P6).
- **Paladin, belief:** the Echo 3600 s belief fallback could stall the twist if P2 finds player auras secret; the
  Exorcism rank lists concatenate the 879 and 415068 families (P8).
- **Enhancement gate is thin:** the world goes OOM in ~35 s (687 ticks / 3) with no Mana Spring or mp5 regen in the
  world; the Searing and Grace of Air in-combat lines barely run. Revisit with T17.
- **Harness:** loop.lua does not feed a kill, so the next fight's prepull is believed in combat; worked around in
  shaman_world only, other worlds unchecked. Fixing it changes other packs' lines, so it is its own task.
- **RegisterTotems** drops element/duration (Schema keeps only the id mapping); shaman_spec asserts the recording
  stand-in.
- **Sim summonTotem** raises on an unknown element (a content bug only).
- **D4 runes unregistered:** Lava Lash 408507, Water Shield 408510, Shamanistic Rage 433255; for T17 (Water Shield
  bears on the thin gate).
- **shaman_world** prices presses from the oracle's belief while usable reads world truth (Paladin precedent).

## Open after Day 5 (2026-10-19)
- **Hunter, in game:** checkpoints H1-H13 in `docs/dev/layout.md` plus the Hunter research's §7
  (`docs/research/2026-10-15-forever-hunter/research.md`). Key: H1 the pseudo-spec 1484 (the alphabetical pattern;
  reconcile with Druid's 1499 on forever); H3/H4 PLAYER_SWING swingType 2 and Auto Shot SUCCEEDED per shot; H6
  IsSpellInRange(75) in the deadzone (the C11 guard rests on it); H7 the percent-of-base costs; H9 learnability,
  including the rune Raptor Strike variants; H10 CAST_GRACE and whether a hawk is a pet unit.
- **Hunter, headless gaps:** Mongoose Bite's window never opens in the Survival world (`dodged()` likely reads the
  batch world's end); all three gates are thin (~28% of Survival ticks with icons; the turret worlds go OOM within a
  minute); the deadzone is untested headless (in_range always true); hawks deal nothing; the Beast Mastery and
  Marksmanship `casting` refusals (the world's client sees no cast start); the world mirrors the overstated percent
  costs (Multi-Shot 0.139*MAX, Strider Kick 0.0581*MAX), so the gate cannot catch H7; `Specializations[1484].ranged =
  true` gives Survival `spec.melee = false` (no Survival line reads active_enemies yet).
- **Hunter, belief shortcuts:** the simulation's `pet.<key>.count` ignores predicted summons; ranged haste is unread in
  combat; the modelled Auto Shot anchor counts at full weight; Rows.lua's advance(t) on swingType 2; an uncapped or
  typo'd `summonPet` key models the pet unit; the sim tests take `model.cap` as truthy where the Adapter wants a
  numeric cap >= 1; VS.Pet writes `est` in a getter; the UnitGUID("pet") and UnitCreatureFamily rows are not added
  (research C1).
- **Rune Raptor Strike** (415335-415343, on-GCD instants; 409691-409755): unregistered, a separate ability (D4 gap,
  H9).
- **D2:** confirm with the user that C17's scope (Feral, Rogue, Warlock) is the intended reading; it now covers Rend,
  Flame Shock and Serpent Sting.
- **Mana bound (T9b):** the at-rest bound exists (it reaches max after ~5-6 min out of combat), but Sources/Power.lua:122
  skips an out-of-combat regen read equal to the estimate, so `lo` climbs at 0.9x (its own task; may move mana lines);
  plus its three test minors (paladin_spec.lua:349's comment, resources_spec.lua:921 and :932). The Retribution,
  Enhancement and Hunter mana floors default 0.
- **Still open:** loop.lua feeds no kill (worked around in shaman_world and hunter_world); the `locked_out_*`
  allocation; the overlay `I.SAME_FRAME` guard.

## Verification
- `make check` green with every `<Spec> solo:` line gated. `make test-<class>` runs 20 fights per class and is green.
  Arms stays as recorded (or re-recorded in T5).
- **In game, the user, per class with a character (D5):** a full client restart for each new addon, then the class's
  checkpoint list on an open-world mob (Forever has no target dummies). Specs without a character stay "provisional".
