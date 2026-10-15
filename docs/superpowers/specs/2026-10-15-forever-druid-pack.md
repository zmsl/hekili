# Forever Druid class pack in the Hekili fork: design spec (2026-10-15)

Status: draft for the user's review. Target: `Forever/Classes/Druid.lua` beside `Forever/Classes/Warrior.lua` on the
`virtualstate-event-facade` branch at its head 5114e04a (Task 13, the Warrior with `now` lines and Classic's combat-log
windows, is fe727909; 5114e04a then renamed `VirtualState/` to `Virtual/{Events,API,State}`), so the Druid is written
against the facade from its first commit: `now` beside every `handler` (facade spec §12a), race packs and cost
modifiers (§12b), the combat-log rows (§2.4, §6). Layer paths below are the renamed ones (`Virtual/State/...`).

Inputs and data are listed in §13 (the research brief is cited "R §n"). Energy and mana costs are DB2 points; rage is the
DB2 cost / 10.

Clean room: Taco Dog Forever (`~/src/TacoDogForever/src/TacoDogForever_Druid/`) mechanics may be ported into Hekili with
credit in the file header. What this spec ports, and so what the header credits: the `excess_e` energy reservation
(TDF `Expressions.lua`, itself after the user's Wrath `excess_e`, `origin/wrath_release:Wrath/Druid.lua` L413-566), the
Feral, bear and Balance priorities (`APLs/feral.simc`, `bear.simc`, `balance.simc`, after Nerdegghead and the guides
they cite), the not-behind window (`Feral.lua`, `ns.NOT_BEHIND_ERRORS`, 5 s), Enrage's 10 + 2/s and the Faerie Fire
in-form rule (`Bear.lua`), and the `form` alias over the forms (`Expressions.lua`, `ns.RegisterForms`). The Classic
kit, handlers and `swap_form` come from Hekili's own `origin/classic:Classic/Druid.lua`.

## 0. Layer prerequisites (the plan's first task)
Three gaps in the belief (`Virtual/State`) block the Druid; all three are layer edits, named here, built and tested before any
class-file task. No shortcut stands in for them.

1. **A fractional cost is a fraction of the maximum.** Hekili's simulation already treats a declared cost below 1 as
   that fraction of the resource's maximum (`State.lua` :6633, :7092, :7158, :7319); the belief does not:
   `I.BaseCostOf` (`Virtual/State/Families/Casts.lua:251`) returns 0.55 as 0.55 points, so the usability ladder
   (`I.CostOf` → `ladder`, `Resources.lua` :396-412, :469-471) pins mana at 0.55 and the `now` family's cost step
   (`Now.lua` :263-275) pays 0.55. Edit: `I.BaseCostOf` returns `c * R.max[ A.slot[ a ] ]` when `0 < c < 1` (no
   allocation). It is shared by the ladder, the cost step and `I.CostMod` (a `pct` then scales the multiplied cost, as
   the simulation's wrapper does), so all three pay and pin the real number.
2. **A regenerating resource rests at its maximum.** The adapter gives every `passive_regen` resource `rest = 100`
   (`Adapter.lua:143`), so belief mana starts at, and returns out of combat to, 100 points while `UnitPowerMax` (a
   passthrough, `Virtual/API/Facade.lua:843`) shows the real maximum. Edit: the adapter forwards `rest = true|false`
   (`ns.ResourceRegenerates( k )`), and Resources sets `R.rest[ r ] = R.max[ r ]` for a resting-at-max slot at the
   build and again wherever `R.max[ r ]` changes. Moving `rest` alone never moves the current estimate, so for such a
   slot each maximum change (the plain read, `Sources/Power.lua` `readMax` → the Max handler, `Resources.lua` ~:430;
   `maxOf` at CombatEnd) also raises `est0` and `hi0` by the increase (never lowering `est0` below its current value):
   seeded at 100, a plain read of 1200 gives an estimate of 1200. Energy is unchanged (its maximum is 100); a slot
   resting at 0 (rage) is untouched.
3. **A swing entry can be gated on a player aura** (bear rage, §2.3). Today the adapter forwards only a swing entry's
   `value` (`Adapter.lua:118-130`) and `I.SwingValue` (`Resources.lua:187-196`) pays every swing, while Hekili's `stop`
   gate is seen only by the simulation. Edit: the swing entry's **`aura`** field (the same field an aura-regen entry
   uses) is forwarded as `d.swingAura`; the build resolves it to the player aura index as the aura-regen entries do
   (`Resources.lua` :158-170, -1 = named but not tracked: then the swing pays nothing); `I.SwingValue` returns 0
   unless that aura's believed expiry is after `I.clock` and its application at or before it
   (`I.auras.exp0[1][j]`, `I.auras.applied[1][j]`). An entry without `aura` pays as today (the Warrior unchanged).
   Planner note: `I.SwingValue` has two other callers, `SwingPerSecond` (the calibration) and the ladder pin's step
   width; gated to 0 out of Bear both stay correct (no calibration update, a zero-width pin) but each gets a test.

Tests (`Virtual/State/spec/`): `casts_spec`/`resources_spec`: an ability declaring 0.55 mana with a plain maximum of
1200 pins mana at 660 when it reads usable and below 660 when it reads short, and its cast's cost step pays 660; a
cost modifier `pct = -0.5` on it pays 330; a cost of 1 or more is unchanged; mana rests at 1200 after the plain
maximum read and seeds at its declared maximum before one; seeded at 100 then a plain maximum read of 1200 gives an
estimate of 1200; rage (rest 0) is unchanged by a maximum read (Warrior non-regression); energy still rests at 100; a swing entry with `aura` pays
only while that aura is believed up (applied by a `now`, expired, never applied), and out of Bear updates no
calibration (`SwingPerSecond`) and pins with a zero-width step; zero allocation over 1000 casts and
swings; `adapter_spec`: `rest` and `swingAura` forwarded. The facade spec's `races_spec.lua:137` covers the
simulation side already.

## 1. Goal and scope
**Goal.** Hekili recommends a Forever Druid's Feral (cat) rotation correctly at the beta cap (level 30) and at 60, with
the same machinery as the Warrior: the Classic kit re-based on the Forever DB2, VirtualState's belief for the secret
resources and auras, `now` for the cast effects the client hides, and a default priority built by `tools/make_pack.lua`.

**One specialization, four packs, three shipped.** Classic registered the Druid as one `NewSpecialization( 11 )` and
chose Feral or Balance by talent points. Forever reports one pseudo-spec per class (the Warrior's is 1491,
`Constants.lua:247`, probe PR15), and Hekili's Forever path keys the class off that row's `forever` field. The Druid
registers one specialization with the ID the client reports for a Druid, written once as the file constant
`DRUID_SPEC`. Until Q1 reads it, `DRUID_SPEC = 1499` (an unused ID; the headless specs read it from the file, and the
pseudo-spec case pins it, which Q1's commit updates with it); the in-game session runs only after Q1's commit replaces it with the value read. Stop rule: if Q1 reads
1491 (the Warrior's row), stop and report, because `Constants.lua` keys rows by ID alone and would need a class key.
The row is `[DRUID_SPEC] = { key = "druid", class = "DRUID",
ranged = false, forever = "Druid" }`, exactly as 1491's. Packs are chosen with `/hekili priority <name>`
(`RegisterPackSelector` does not exist in this fork, Warrior plan Self-Review):

| Pack | Status | Why |
|---|---|---|
| `Feral` | **shipped, the default** (`RegisterOptions{ package = "Feral" }`) | the user's spec; a sourced Forever priority (Nerdegghead) already proven in TDF |
| `Guardian` (bear) | registered, **provisional** (desc says so) | the kit is needed anyway (form gates, Clearcasting, rage); TDF's `bear.simc` ports line for line; Maul, Swipe, Demoralizing Roar, Bash, Enrage are all below 30 and Primal Bite is a 25 talent, so it is usable at the cap. Provisional because bear rage income (Q8) and decay (Q9) are unmeasured |
| `Balance` | registered, **provisional** | Wrath, Moonfire, Starfire, Insect Swarm (25 talent) are below 30; TDF's `balance.simc` ports; provisional because mana is never readable (Q5) and Eclipse's charge rule is unconfirmed (R §9) |
| `Restoration` | **deferred** | no Classic, TBC-era-Forever or TDF priority exists to port; a healer's choices hang on health, which is secret on Forever, so a priority would be guesswork. Heals are registered only so a cast spends Clearcasting (§7) |

Out of scope: SoD rune spells (Savage Roar 407988, Starsurge, Sunfire, Starfall, Lifebloom, Nourish, Wild Growth,
Skull Bash 410176, Swipe (Cat) 411128, Feral Charge (Cat) 414924, Survival Instincts: in the DB2, listed by no Forever source; Q16 confirms they are
unlearnable), Tiger's Fury (removed; its Classic ranks are not in the DB2), powershifting (gone with Furor's redesign),
Wolfshead Helm, Omen of Clarity as a castable buff (a passive on Forever), Rebirth/Revive, Hibernate, Soothe Animal,
Remove Curse, the poison cures, Track Humanoids, and a pack selector.

**Files.**
```
Forever/Classes/Druid.lua         the class file (pseudo-spec, resources, talents, auras, abilities, state, settings, packs)
Forever/Races/NightElf.lua        Elune's Light, for every class (§9)
Forever/Races/Tauren.lua          War Stomp, for every class (§9)
Forever/spec/druid_spec.lua       KIT and TALENTS pins, the behaviour cases (§10)
Forever/spec/helpers/load_druid.lua   the recording loader (load_warrior.lua's shape, Energy/ComboPoints/Mana in Enum)
tools/make_pack.lua               takes the class, default `warrior`: `lua5.1 tools/make_pack.lua druid` (§8)
tools/packs/{warrior,druid}.lua   each class's DATE and PACKS (the Warrior's text moved verbatim: same strings, no bump)
Constants.lua                     the Druid's pseudo-spec row
Classes.lua                       `spec:RegisterCostMod` (named core edit, §7)
Virtual/State/Families/Casts.lua  layer edit (§0): a declared cost below 1 is that fraction of the resource's maximum
Virtual/State/Adapter.lua         layer edit (§0): `rest` as a flag (a regenerating resource rests at its maximum);
                                  a swing entry's `aura` forwarded as `swingAura`
Virtual/State/Families/Resources.lua  layer edit (§0): rest = maximum; `I.SwingValue` gated on `swingAura`
Virtual/State/spec/{casts,resources,adapter}_spec.lua  the layer edits' cases (§0)
Hekili.toc                        Forever\Classes\Druid.lua after Warrior.lua; Forever\Races\NightElf.lua and Tauren.lua after Gnome.lua
.luacheckrc                       `druidEnv` (the Druid's state names), as `warriorEnv`
```

## 2. Resources on Forever
Registered in this order (Classic's): Energy, ComboPoints, Rage, Mana. Every ability names its `spendType`, so the
primary resource never decides a cost. VirtualState polls `UnitPower` for every registered resource
(`Virtual/State/Sources/Power.lua:100-110`) and the adapter forwards each one's meta `{ max, decay }`.

### 2.1 Energy (Cat)
```lua
spec:RegisterResource( Enum.PowerType.Energy )
```
- **Max 100**, the adapter's default; no Druid modifier in the DB2. **No decay** (energy rests at 100: the adapter's
  `rest = 100` from `ns.ResourceRegenerates`).
- **Regen continuous, 10/s** (Blizzard's class notes; `GetPowerRegenForPowerType(3)` = 10.001 plain out of combat,
  secret in combat, R §2.1). No regen model and no `regen` field: Classic's 20-per-tick model
  (`Classic/Druid.lua:163-185`) is dropped, as Wrath dropped it. The out-of-combat plain read seeds the belief's rate and
  the belief keeps it through combat. shortcut: after a `/reload` in combat the rate stays 0 for the rest of the
  fight (calibrate returns early at a declared rate of 0, so pins never recover it); upgrade with a one-line `regen`
  meta field forwarded by the adapter after checkpoint Q3. A 0 out-of-combat read (a non-Cat form) is skipped, since
  energy rests at its maximum.
- **The usability ladder is the pin source.** `UnitPower(Energy)` is secret always; `C_Spell.IsSpellUsable` and its
  `insufficientPower` are plain. Each energy ability is a rung: Cower 20 < Rip 30 < Ferocious Bite 35 < Rake 40 < Claw
  45 < Pounce 50 < Shred 60 = Ravage 60 (rank-independent in the DB2). Talents move rungs (Ferocity, Shredding Attacks,
  §6); the belief reads the cost through Hekili's `spend`, so they move together; Q4 compares `cost=` with `read=`.
- Feral Dedication (1231380-1231382: +25% regen after 5 s in Cat Form) is not modelled: who has it and when it starts
  are unknown (Q3). Its effect is a steady bias the ladder pins absorb.

### 2.2 Combo points (plain)
```lua
spec:RegisterResource( Enum.PowerType.ComboPoints )
```
- Plain 0-5 in combat (`GetComboPoints`, `C_Secrets.GetPowerTypeSecrecy(ComboPoints)` = 0, R §2.2); the poll refreshes
  them and an observed read beats any modelled sample. **No `now` writes combo points.** The sim `handler`s keep
  Classic's `gain( 1, "combo_points" )` (builders) and `spend( combo_points.current, "combo_points" )` (finishers).
  No `max` (a point resource; §12b leaves `maxMods` off them).
- Open (Q10): whether `UnitPower(4)` reads plain in combat (Blood in the Water saw it secret), and the count after a
  target swap, a target's death and a missed finisher.

### 2.3 Rage (Bear)
```lua
spec:RegisterResource( Enum.PowerType.Rage, {
    mainhand = { swing = "mainhand", aura = "bear_form", -- the belief's gate (§0.3); `stop` is the simulation's
                 last = <Warrior's>, interval = "mainhand_speed",
                 stop = function () return state.swings.mainhand == 0 or not state.buff.bear_form.up end,
                 value = function () return BEAR_RAGE_RATE * bearSwing() end },
    enrage = { aura = "enrage", last = <Warrior's bloodrage shape>, interval = 1, value = 2 }, -- 25503: 20 every 1000 ms /10
}, nil, {
    -- the Warrior's measured out-of-combat loss (tooltip, 100 -> 0 in 82.2 s); Q9 confirms for a bear. A function, not a
    -- number: RegisterResource setfenv's every meta field (Classes.lua:185-187), so a number would raise.
    decay = function () return 1.25 end,
} )
```
- **Max 100** (adapter default; no Gnome Druid, so no `maxMods` reaches it, R §8).
- **Swing rage: the Warrior's speed rule is the default.** Rage per white swing = unhasted swing speed x a rate,
  independent of damage, level and haste (measured on Forever for the Warrior: magey/forever-warrior#3, warrior
  compendium v3.1.0; the damage formula was off by half at the level-22 checkpoint). In Bear and Dire Bear Form the
  swing is the form's 2.5 s and the weapon does not swing, so the two-hander flag (`main_hand.size`) has no meaning:
  `BEAR_RAGE_RATE = 3.46` (the one-hand main-hand rate; decision D4) and `bearSwing()` = `VS.SwingBase( 1 )`, falling
  back to `state.mainhand_speed` before a plain base read, as `rageOf` does. 2.5 x 3.46 = 8.65 a swing. The entry pays
  only in Bear or Dire Bear Form, in both layers: the belief through the swing entry's `aura = "bear_form"` field
  (§0.3; the `bear_form` aura's `copy = { 9634 }` makes Dire Bear Form count, so no `dire_bear_form` gate; a
  click-off in combat is no cast, so the belief keeps crediting until the next shift or combat end), the
  simulation through `stop` (which the belief ignores). Cat and caster swings add no rage.
  shortcut: crits, misses, Blood Frenzy (5 rage on a crit, chance), Natural Reaction (5 on a dodge) and rage from
  damage taken are unmodelled; VirtualState's swing-scale calibration absorbs a steady bias, Hekili's own forecast
  does not. Upgrade from the combat-log rows (a `SWING_DAMAGE` crit flag) once a non-cast `now` trigger exists (§12a
  out of scope).
- **Enrage** (5229): 10 rage at once in `now`/`handler` (DB2 effect 30 base 100) and 2 a second for 10 s from its aura
  25503 (aura 24 periodic energize 20 / 1000 ms), Classic's own entry (`Classic/Druid.lua:128-139`).
- **Decay 1.25/s** out of combat, the Warrior's tooltip value (`GetPowerRegenForPowerType(1)` = -12.499 internal);
  TDF's bear assumed the same. Q9 reads it in Bear Form.
- **Maul** is a next-swing strike: `onNextSwing = true` (VirtualState pays it at the swing, which then brings no rage);
  Hekili's simulation pays at the press (the Warrior's known Q9 risk, same comment).

### 2.4 Mana (caster, forms, Shifting Power)
```lua
spec:RegisterResource( Enum.PowerType.Mana )
```
- Secret even out of combat (R §2.4); maximum and regen unprobed (Q5). No meta: if the checkpoint finds
  `UnitPowerMax(0)` plain, the plain maximum read wins (§12b "a plain maximum read arrives, which wins for good");
  if secret, Q5's action adds `max` from the read the user reports.
- Percent costs are fractions of maximum mana, in the simulation (Hekili's own rule) and in the belief (layer edit
  §0.1, with mana resting at its maximum, §0.2): Cat/Bear/Dire Bear Form and
  Shifting Power 0.55, Moonkin 0.35, Travel/Aquatic 0.20, Innervate 0.05, each x (1 - 0.1 x Natural Shapeshifter rank)
  for the forms and Shifting Power (16833: -10% a rank; Shifting Power's text names the same effects).
  Known approximation (Classic's too): the DB2 costs are % of *base* mana, the fraction is of *maximum* mana, so gear
  Intellect overstates them; Q5 records base and maximum so the plan can size the error.
- The five-second rule is not modelled (Q5).

## 3. Forms
**What is read plainly.** The Warrior reads its stance from `GetShapeshiftForm()` and the fourth return of
`GetShapeshiftFormInfo( form )` (the form's spell ID), both plain in combat for a Warrior (PR10); a stance is not an
aura there. For a Druid the form *is* an aura (768, 5487, 9634, 24858, 783, 1066), and player auras are secret in
combat (`C_UnitAuras.GetPlayerAuraBySpellID` raises when tainted, R §4), so the aura cannot be the source. The
shapeshift API is the same API, so the default is the Warrior's method; Q2 confirms it on a Druid, and its fallback
is TDF's usability inference (a cat ability unusable for a non-power reason means out of Cat Form).

```lua
local FORM_OF_SPELL = { [ 768 ] = "cat_form", [ 5487 ] = "bear_form", [ 9634 ] = "bear_form",
    [ 24858 ] = "moonkin_form", [ 783 ] = "travel_form", [ 1066 ] = "aquatic_form" }
local FORMS = { "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" }
-- reset_precast: remove every form, then map GetShapeshiftForm() -> GetShapeshiftFormInfo( form ) 4th return -> applyBuff
```
- The bar order never matters (the Warrior's ruling W5); Hekili's own `stance` table stays unused (it reads a fifth
  return that does not exist, `State.lua:2617-2631`).
- **Dire Bear Form is Bear Form's rank 2**: one ability `bear_form` (id 5487, `copy = { 9634 }`, `known` by rank) and
  one aura `bear_form` (`copy = { 9634 }`); every bear gate says `buff = "bear_form"`. No `dire_bear_form` key.
- **Aliases** (Hekili `RegisterAura` alias, as Classic's `form`): `form` over the five forms (`buff.form.up` for the
  precombat lines) and `feral_form` over `cat_form` and `bear_form` (Faerie Fire's free cost, the caster gate).

**Form gates** (Classic knowledge; the DB2 has no SpellShapeshift table and its NOT_NEED_SHAPESHIFT flag only marks
the castable-anywhere spells, R §6; Q15 confirms per form, the Warrior's Q1 pattern):

| Gate | Abilities |
|---|---|
| `buff = "cat_form"` | Claw, Shred, Rake, Rip, Ferocious Bite, Cower, Prowl, Dash, Shifting Power |
| `buff = "prowl"` (Prowl needs Cat) | Ravage, Pounce |
| `buff = "bear_form"` | Maul, Swipe, Primal Bite, Lacerate, Demoralizing Roar, Growl, Bash, Challenging Roar, Enrage, Frenzied Regeneration, Feral Charge |
| `buff` function: `cat_form` or `bear_form`, whichever is up | Berserk ("Requires Cat Form, Bear Form, Dire Bear Form", DB2 text) |
| `nobuff = "feral_form"` | Wrath, Starfire, Moonfire, Insect Swarm, Hurricane, Entangling Roots, Healing Touch, Regrowth, Rejuvenation, Mark/Gift of the Wild, Thorns, Innervate, Nature's Grasp |
| none | Faerie Fire (any form, free in Cat/Bear), Barkskin, the forms (each `nobuff = <itself>`) |

**A shift, in `now` and `handler` alike** (a state function `swap_form( key )` for the sim; the forms' `now` write the
same lines, the Warrior's stance pattern):
1. remove every other form aura and `maul`; apply the new form's aura (3600 s, as the Warrior's stances).
2. **Into Bear:** rage goes to 0 (`spend( rage.current, "rage" )`); then Furor (17056, now Feral): a 20%-a-rank chance
   of 10 rage (17057). The cast cannot know the roll: the belief takes 0 (its lower bound stays right; the next rung
   raises it). Classic's rank-5 certainty and Wolfshead's +5 are dropped.
3. **Into Cat:** Forever's Furor restores 20% a rank of the energy held on leaving Cat plus energy for the time spent
   out (1238181), and powershifting is gone. Energy is secret and the leave may be unseen (a click-off is no cast), so
   `now` writes no energy. shortcut: energy is believed kept across a shift; the first ladder rung corrects it; upgrade
   once Q3 measures Furor's rule.
4. The mana cost is the declared `spend` (the layer pays it automatically, §12a).

## 4. The kit
Columns: IDs lowest rank first (DB2); cost with every talent at rank 0 (type); cooldown = larger of RecoveryTime and
CategoryRecoveryTime; GCD: `"totem"` is Hekili's fixed 1.0 s (every cat ability's StartRecoveryTime is 1000),
`"spell"` 1.5 s, `"off"` none. Every ability has `known = knows( <RANKS> )` (the highest rank in the spellbook, through
`VS.KnownRank` as the Warrior's Task 13 file) and its gate from §3. `now` is what the cast does to the now-state that
the declared cost, cooldown and GCD do not already cover (§12a: the layer pays those itself).

### 4.1 Cat
| Key | IDs | Cost | CD | GCD | `usable` / notes | `now` |
|---|---|---|---|---|---|---|
| `claw` | 1082, 3029, 5201, 9849, 9850 | 45 energy - Ferocity | 0 | totem | | none (combo points plain) |
| `shred` | 5221, 6800, 8992, 9829, 9830 | 60 - 6 x Shredding Attacks | 0 | totem | behind: the pack's switch (§8) | none |
| `rake` | 1822, 1823, 1824, 9904 (+1289140 copy) | 40 - Ferocity | 0 | totem | | `applyDebuff( "target", "rake" )` (9 s) |
| `rip` | 1079, 9492, 9493, 9752, 9894, 9896 (+1289141) | 30 | 0 | totem | `usable = combo_points.current > 0` | `applyDebuff( "target", "rip" )` (12 s) |
| `ferocious_bite` | 22568, 22827, 22828, 22829, 31018 (+1289142) | 35 | 0 | totem | `usable = combo_points.current > 0` | `spend( energy.current, "energy" )`: Bite converts all the energy left after its cost (DB2 text) |
| `ravage` | 6785, 6787, 9866, 9867 | 60 | 0 | totem | `buff = "prowl"` | `removeBuff( "prowl" )` |
| `pounce` | 9005, 9823, 9827 | 50 | 0 | totem | `buff = "prowl"` | `removeBuff( "prowl" )`; `applyDebuff( "target", "pounce", 2 + 0.5 * talent.brutal_impact.rank )`; `applyDebuff( "target", "pounce_bleed" )` (18 s) |
| `cower` | 8998, 9000, 9892 | 20 | 10 | totem | | none |
| `prowl` | 5215, 6783, 9913 | 0 | 10 | off | `usable = combat == 0` | `applyBuff( "prowl" )` |
| `dash` | 1850, 9821 | 0 | 300 | off | | `applyBuff( "dash" )` (15 s) |
| `shifting_power` | 1322605 | 0.55 mana x NS | 16 - 4 x Improved Shifting Power (D5) | totem | no toggle: it is the rotation's core | `gain( 40, "energy" )` (DB2 effect 30 base 40) |
| `berserk` | 417141 | 0 | 180 | off | `buff` function (§3); `toggle = "cooldowns"` | `applyBuff( "berserk" )` (15 s) |
| `cat_form` | 768 | 0.55 mana x NS | 0 | spell | `nobuff = "cat_form"` | §3 shift |

### 4.2 Bear
| Key | IDs | Cost | CD | GCD | `usable` / notes | `now` |
|---|---|---|---|---|---|---|
| `bear_form` | 5487, 9634 | 0.55 mana x NS | 0 | spell | `nobuff = "bear_form"` | §3 shift |
| `maul` | 6807, 6808, 6809, 8972, 9745, 9880, 9881 | 15 rage - Ferocity | 0 | off | `onNextSwing = true`; `usable = not buff.maul.up` | none (paid at its swing) |
| `swipe_bear` | 779, 780, 769, 9754, 9908 | 20 - Ferocity | 0 | spell | hits up to 3 | none |
| `primal_bite` | 407995, 1238069, 1238070, 1238073 | 20 - Ferocity | 6 | spell | Mangle renamed; `known` (talent spell) | none (Berserk's no-cooldown rule unmodelled) |
| `lacerate` | 414644, 1235826, 1235827 | 15 - Shredding Attacks rule (Q12) | 0 | spell | | `applyDebuff( "target", "lacerate", 15, min( 5, debuff.lacerate.stack + 1 ) )` |
| `demoralizing_roar` | 99, 1735, 9490, 9747, 9898 | 10 | 0 | spell | | `applyDebuff( "target", "demoralizing_roar" )` (30 s) |
| `growl` | 6795 | 0 | 8 | off | | `applyDebuff( "target", "growl" )` (3 s) |
| `bash` | 5211, 6798, 8983 | 10 | 60 (Brutal Impact's -30 s unmodelled, §6) | spell | | `applyDebuff( "target", "bash", ( BASH_STUN[ knownRank( BASH ) ] or 2 ) + 0.5 * talent.brutal_impact.rank )` (`BASH_STUN = { 2, 3, 4 }`; `or 2` when the spellbook answers 0) |
| `challenging_roar` | 5209 | 15 | 600 | spell | | `applyDebuff( "target", "challenging_roar" )` (6 s) |
| `enrage` | 5229 | 0 | 60 | off | no toggle (`settings.use_enrage` guards it) | `gain( 10, "rage" )`; `applyBuff( "enrage" )` |
| `frenzied_regeneration` | 22842 | 0 | 180 (Q13) | spell | `toggle = "defensives"` | `applyBuff( "frenzied_regeneration" )` (10 s); its rage drain unmodelled (health is secret, the drain stops at full health) |
| `feral_charge` | 1238122 (+16979 copy) | 5 | 15 | off | | `applyDebuff( "target", "feral_charge_effect" )` (4 s) |

### 4.3 Shared, Balance, utility
| Key | IDs | Cost | CD | GCD | notes | `now` |
|---|---|---|---|---|---|---|
| `faerie_fire` | 770, 778, 9749, 9907 | 55/75/95/115 mana; **0 while `buff.feral_form.up`** | 0; 6 in form (TDF, R §3.2) | spell | any form; Q7 settles the free cost, the cooldown and the debuff ID (770 family vs 1288561) | `applyDebuff( "target", "faerie_fire" )` (40 s) |
| `wrath` | 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 | 10/20/40/50/70/80/100/120 | 0 | spell | cast 1.5/1.7/2.0 s by rank, - 0.1 x Improved Wrath | `if talent.eclipse.rank > 0 then addStack( "eclipse", nil, 2 ) end` ("Eclipse is known" = `talent.eclipse.rank > 0`, the same test in `handler`; R §9 open: +1 or +2) |
| `starfire` | 2912, 8949, 8950, 8951, 9875, 9876, 25298 | 95/135/180/230/275/315/340 | 0 | spell | cast 3.5 s, shorter with an Eclipse charge (unmodelled) | none (spending a charge is no `now` verb; the belief's charges end with the 15 s aura). `handler`: `if buff.eclipse.up then removeStack( "eclipse" ) end` |
| `moonfire` | 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 | 25..375 by rank | 0 | spell | instant | `applyDebuff( "target", "moonfire", ( knownRank( MOONFIRE ) > 1 and 12 or 9 ) + 3 * talent.natures_splendor.rank )` (inline: no helper reading `state`) |
| `insect_swarm` | 5570, 24974, 24975, 24976, 24977 | 45/85/100/140/160 | 0 | spell | Balance talent on Forever | `applyDebuff( "target", "insect_swarm", 12 + 2 * talent.natures_splendor.rank )` |
| `hurricane` | 16914, 17401, 17402 | 880/1180/1495 | 0 | spell | `channeled = true`, 10 s | none |
| `entangling_roots` | 339, 1062, 5195, 5196, 9852, 9853 | 50..125 | 0 | spell | cast 1.5 s | `applyDebuff( "target", "entangling_roots", ROOTS_DURATION[ knownRank( ROOTS ) ] or 12 )` (`ROOTS_DURATION = { 12, 15, 18, 21, 24, 27 }`, by rank, DB2) |
| `moonkin_form` | 24858 | 0.35 mana x NS | 0 | spell | level 40 | §3 shift |
| `travel_form`, `aquatic_form` | 783 / 1066 | 0.20 x NS | 0 | spell | out of every pack | §3 shift |
| `innervate` | 29166 | 0.05 | 360 | spell | `toggle = "cooldowns"` | `applyBuff( "innervate" )` (20 s) |
| `barkskin` | 22812 | 0 | 60 | spell | `toggle = "defensives"` | `applyBuff( "barkskin" )` (15 s) |
| `natures_grasp` | 16689, 16810, 16811, 16812, 16813, 17329 | 50..125 | 60 | spell | | `applyBuff( "natures_grasp" )` (45 s) |
| `mark_of_the_wild` / `gift_of_the_wild` | 1126, 5232, 6756, 5234, 8907, 9884, 9885 / 21849, 21850 | 20..445 / 900, 1200 | 0 | spell | | `applyBuff( <own> )` (1 h) |
| `thorns` | 467, 782, 1075, 8914, 9756, 9910 | 35/60/105/170/240/320 | 0 | spell | | `applyBuff( "thorns" )` (10 min) |
| `healing_touch`, `regrowth`, `rejuvenation` | 5185 ..25297 (11) / 8936 .. 9858 (9) / 774 .. 25299 (11) | by rank | 0 | spell | no pack line; registered so a cast spends Clearcasting (§7) | none |

Costs by rank are file-level tables (`WRATH_COST = { 10, 20, ... }`) read through `knownRank`, shared by `spend`, the
KIT pins and nothing else. Every rank list is a file-level constant shared by `copy = rest( RANKS )`, `known`,
`handler` and `now`, as the Warrior's.

**The shape** (one example; the rest follow the tables):
```lua
rake = {
    id = 1822, copy = rest( RAKE ), cast = 0, cooldown = 0, gcd = "totem",
    spend = function () return 40 - talent.ferocity.rank end, spendType = "energy",
    startsCombat = true, known = knows( RAKE ), buff = "cat_form",
    -- what the cast did to the now-state, in VirtualState's context (spec §12a)
    now = function () applyDebuff( "target", "rake" ) end,
    handler = function () applyDebuff( "target", "rake" ); gain( 1, "combo_points" ) end,
},
```
`rip` and `rake` keep Classic's `readyTime = debuff.<x>.remains` out: the pack's guards (`!debuff.rip.up`) say "never
clip" instead, so a refresh is never predicted early.

**The misses** (Classic's combat-log windows, the Warrior's Task 13 shape). A dodged, parried or missed Rake, Rip or
Pounce still raises `SPELL_CAST_SUCCESS`, so `now` applies the debuff. The facade's ability-outcome rows carry the
miss: a `spec:RegisterEvent( "COMBAT_LOG_EVENT_UNFILTERED", ... )` handler records `bleed_missed[ key ] = GetTime()`
for our `SPELL_MISSED` of a Rake/Rip/Pounce rank (an `ids -> key` lookup built at load), and `reset_precast`, while
`now == query_time`, removes that debuff when the miss is newer than the debuff's application. The belief's modelled
expiry stays until a non-cast `now` trigger exists (§12a out of scope); the sim is right from the next reset, and the
combo points (plain, not spent by a missed finisher on vanilla rules, Q10) agree. Same handler: the not-behind window
(§8). The file reads `CombatLogGetCurrentEventInfo` and `GetTime` through `ns.Facade`.

## 5. Auras
`id`/`copy` from the DB2's rank IDs; numbers where the duration is fixed, a function only where a talent or rank
changes it (then every `now` that applies it passes the number, §12a).

| Key | ID (`copy`) | Unit | Duration / stacks | Notes |
|---|---|---|---|---|
| `cat_form`, `bear_form` (`copy` 9634), `moonkin_form`, `travel_form`, `aquatic_form` | 768, 5487, 24858, 783, 1066 | player | 3600 | applied by `reset_precast` from the shapeshift read |
| `form`, `feral_form` | alias | player | | §3 |
| `prowl` | 5215, 6783, 9913 | player | 3600 | |
| `dash` | 1850, 9821 | player | 15 | |
| `clearcasting` | 16870 | player | 15, 1 stack | §7 |
| `berserk` | 417141 | player | 15 | |
| `enrage` | 25503 (`copy` 5229) | player | 10, tick 1 | the rage entry's aura |
| `frenzied_regeneration` | 22842 | player | 10, tick 1 | Classic's 22895/22896 are not in the DB2 |
| `barkskin`, `innervate`, `natures_grasp` | 22812 / 29166 / 16689 + ranks | player | 15 / 20 / 45 | |
| `mark_of_the_wild`, `gift_of_the_wild`, `thorns` | rank lists | player | 3600 / 3600 / 600 | right out of combat only |
| `maul` | no spell | player | `function () return state.mainhand_speed end` | queued; `IsCurrentSpell` in `reset_precast`, as `heroic_strike` |
| `eclipse` | 408255 (`copy` 441260) | player | 15, 4 stacks | Balance |
| `natures_grace` | 16886 | player | 3 | |
| `not_behind` | no spell | player | 5 | §8, from `UI_ERROR_MESSAGE` |
| `rake` | 1822 + ranks, 1289140 | target | 9, tick 3 | |
| `rip` | 1079 + ranks, 1289141 | target | 12, tick 2 | |
| `pounce` / `pounce_bleed` | 9005 + ranks / 9007, 9824, 9826 | target | function (2 + 0.5 x Brutal Impact) / 18, tick 3 | |
| `lacerate` | 414644, 1235826, 1235827 | target | 15, 5 stacks, tick 3 | |
| `bleed` | alias of `rake`, `rip`, `pounce_bleed`, `lacerate` | target | | Classic's alias without the other classes' bleeds |
| `moonfire` | 8921 + ranks | target | function (rank, Splendor), tick 3 | |
| `insect_swarm` | 5570 + ranks | target | function (Splendor), tick 2 | |
| `faerie_fire` | 770, 778, 9749, 9907 (+1288561 per Q7) | target | 40 | one key; Classic's `faerie_fire_feral` ability and aura fold into it |
| `demoralizing_roar` | 99 + ranks | target | 30 | Classic's 48560 is not in the DB2 |
| `growl`, `challenging_roar`, `bash`, `feral_charge_effect`, `entangling_roots` | 6795 / 5209 / 5211 + ranks / 19675 / 339 + ranks | target | 3 / 6 / function / 4 / function | |

Dropped from Classic: `omen_of_clarity` (buff), `rend`/`garrote`/`rupture`/`deep_wound` (only filled the bleed alias),
the `improved_*` and `sharpened_claws` entries (talents, not auras), `tigers_fury`, `dire_bear_form`.

## 6. Talents
**How the Warrior got its live tree, and why the Druid needs the same first.** The DB2 holds the old Classic trees
only, and only rank 1 of each talent. The Warrior's 52 live nodes came from a **ForeverProbe export**: with
`~/src/ForeverProbe` loaded (its `Export.lua`), the user ran `/fprobe export` out of combat, then `/reload`, which
wrote `ForeverProbeDB.export` to `WTF/Account/<account>/SavedVariables/ForeverProbe.lua` under the beta's
`_classic_beta_` folder. The export walks `C_Traits` (config -> trees -> nodes -> entry -> definition), the spellbook and
the stances. The orchestrator copied the file to
`/home/zack/.claude/jobs/080a308e/tmp/warrior/export/`, dumped the nodes to `talents.txt` (one line per node:
definition spell, `cur`/`max`, name, tooltip) with `dump.lua`/`t.lua`, and reconciled them against the class file in
`reconcile.md`; the accuracy plan's ruling A1 then registered exactly those 52 nodes as `{ 0, definitionSpell,
maxRank }` (no rank aliases: every node reports one definition spell at every rank). **The Druid's export is
checkpoint item 1 (Q1)**, run on a Druid, read and reconciled the same way (`.../tmp/druid/export/`).

**Until the export: the DB2's 47 nodes are the registered set.** `wowdb talents DRUID` returns 47 (Balance 16, Feral
Combat 16, Restoration 15) and Hekili's Classic `RegisterTalents` has the same 47 at rank 1 (R §5.1). Format as the
Warrior's: `key = { 0, rank-1 spell, max rank }`, keys Classic's (the Warrior kept Classic keys where the talent
exists, e.g. `improved_shred` for Shredding Attacks, `primal_fury` for 16958 "Blood Frenzy").
```lua
-- Balance (16)
improved_wrath = { 0, 16814, 5 }, natures_grasp = { 0, 16689, 1 }, improved_natures_grasp = { 0, 17245, 4 },
improved_entangling_roots = { 0, 16918, 3 }, improved_moonfire = { 0, 16821, 5 }, natural_weapons = { 0, 16902, 5 },
natural_shapeshifter = { 0, 16833, 3 }, improved_thorns = { 0, 16836, 3 }, omen_of_clarity = { 0, 16864, 1 },
natures_reach = { 0, 16819, 2 }, vengeance = { 0, 16909, 5 }, improved_starfire = { 0, 16850, 5 },
natures_grace = { 0, 16880, 1 }, moonglow = { 0, 16845, 3 }, moonfury = { 0, 16896, 5 }, moonkin_form = { 0, 24858, 1 },
-- Feral Combat (16)
ferocity = { 0, 16934, 5 }, feral_aggression = { 0, 16858, 5 }, feral_instinct = { 0, 16947, 5 },
brutal_impact = { 0, 16940, 2 }, thick_hide = { 0, 16929, 5 }, feline_swiftness = { 0, 17002, 2 },
feral_charge = { 0, 16979, 1 }, sharpened_claws = { 0, 16942, 3 }, improved_shred = { 0, 16966, 2 },
predatory_strikes = { 0, 16972, 3 }, blood_frenzy = { 0, 16952, 2 }, primal_fury = { 0, 16958, 2 },
savage_fury = { 0, 16998, 2 }, faerie_fire_feral = { 0, 16857, 1 }, heart_of_the_wild = { 0, 17003, 5 },
leader_of_the_pack = { 0, 17007, 1 },
-- Restoration (15)
improved_mark_of_the_wild = { 0, 17050, 5 }, furor = { 0, 17056, 5 }, improved_healing_touch = { 0, 17069, 5 },
natures_focus = { 0, 17063, 5 }, improved_enrage = { 0, 17079, 2 }, reflection = { 0, 17106, 3 },
insect_swarm = { 0, 5570, 1 }, subtlety = { 0, 17118, 5 }, tranquil_spirit = { 0, 24968, 5 },
improved_rejuvenation = { 0, 17111, 3 }, natures_swiftness = { 0, 17116, 1 }, gift_of_nature = { 0, 17104, 5 },
improved_tranquility = { 0, 17123, 2 }, improved_regrowth = { 0, 17074, 5 }, swiftmend = { 0, 18562, 1 },
```

**Forever-only addendum, gated on Q1.** From TDF's data (`tools/data/classes/DRUID.json`, `Register.lua`
`TALENT_MOVES`) and the Forever research, unconfirmed: `shifting_power` 1322605 (1), `improved_shifting_power` 1322670
(2), `primal_bite` 407995 (1), `berserk` 417141 (1), `natural_reaction` 417051 (5), `eclipse` 408248 (3),
`natures_splendor` 1223083 (1), `natures_majesty` 1223082 (2), `genesis` 1223081 (5). These keys land in the commit
that applies the export, with the export's definition spells and max ranks, and the export also decides which of the
47 go (Tiger's Fury-era removals, King of the Jungle), which max ranks change (DB2 vs Era pages: Shredding Attacks
2 vs 3, Sharpened Claws 3 vs 2, Feral Instinct 5 vs 3, Thick Hide 5 vs 3) and where Furor and Insect Swarm now sit.
Nothing waits on it: **every ability gates on `known` (the spellbook), never on a talent**, so a talent ability
(Shifting Power, Primal Bite, Berserk, Insect Swarm) is recommended once learned, registered talent or not. Until
the addendum lands, `talent.improved_shifting_power`, `talent.natures_splendor` and `talent.eclipse` read rank 0: so no
reader names an unregistered key, the plan registers those three with the 47 as placeholders, marked "replaced by the
export": `improved_shifting_power = { 0, 1322670, 2 }`, `natures_splendor = { 0, 1223083, 1 }`,
`eclipse = { 0, 408248, 3 }`. Wrath's Eclipse charges and the Balance pack's `buff.eclipse` follow the talent.

**Modifiers modelled** (rank 1's DB2 value x the rank, floored at 0: Classic's convention and the Warrior's ruling):
Ferocity -1 energy/rage a rank on Claw, Rake, Maul, Swipe, Primal Bite; Shredding Attacks (`improved_shred`) -6 energy
a rank on Shred and, per its DB2 text (m2 = -60), -6 rage a rank on Lacerate (Q12); Natural Shapeshifter -10% a rank on
the forms and Shifting Power; Brutal Impact +0.5 s a rank on the Bash and Pounce stuns; Improved Wrath -0.1 s cast a
rank; Furor (§3); Improved Shifting Power -4 s a rank (D5); Nature's Splendor +3 s Moonfire, +2 s Insect Swarm.
**Not modelled:** Moonglow (DB2 rank 1 is -25%, the Era page -8/-17/-25: the x-rank rule would give -75%), Brutal
Impact's -30 s on Bash's cooldown (a cooldown modifier, the Warrior's ruling), Feral Instinct, Heart of the Wild,
Predatory Strikes, Savage Fury, the tier set, Berserk's Primal Bite rule.

## 7. Clearcasting
**The proc and its aura.** Omen of Clarity (16864) is a passive on Forever (trained at 20); its proc Clearcasting
(16870, 15 s, aura 108 -100%: the next covered ability is free) has no event, and the aura is secret in combat (Q6).

**The `spend = 0` rule goes.** Classic wrote `(buff.clearcasting.up and 0) or cost` in each `spend`, and TDF's
`energyCost` helpers did the same. On the facade branch the declaration is one cost modifier read by both layers
(§12b), so no ability's `spend` mentions Clearcasting, and no `now` or `handler` removes it.

**The entry.** Class content, not a race's, so not in a race file: the Druid file declares it through
`spec:RegisterCostMod( def )` (decision D1), a named core edit in `Classes.lua` with the race object's signature that
appends `def` to the same list `Races.lua` reads (`ns.raceMods.costMods`, read by the adapter for the belief and by
the `spend` wrapper for the sim). The Druid file has already returned for any other class, so the append is the
player's. The coverage is the DB2 masks of 16870 (derived for this spec, used as given); `spells` lists the rank-1 IDs
of the covered abilities the file registers (higher ranks resolve through each ability's `copy`):
```lua
-- Clearcasting (16870), aura 108 -100% cost, by its DB2 masks; covered but unregistered: Sunfire, Starfall,
-- Tranquility, Wild Growth, Skull Bash. Not covered: Wrath, Thrash, Savage Roar, Faerie Fire, Cower, Challenging Roar,
-- Mark/Gift of the Wild, Hibernate, Soothe Animal, Shifting Power. Covered by the masks (in by default, Q6 removes
-- either if unusable at 0 rage with Clearcasting up): Primal Bite (mask1 64), Demoralizing Roar (mask0 8).
spec:RegisterCostMod( {
    aura = "clearcasting", pct = -1, charges = 1,
    spells = { 8921, 2912, 5570, 16914, 5185, 8936, 774, 1082, 1822, 5221, 1079, 22568, 9005, 6785, 779, 6807, 414644,
        5211, 1238122, 339, 467, 16689, 407995, 99 },
} )
```
- Charges follow the declared cost (§12b): a covered cast whose declared cost is above 0 takes the stack, including
  the free cast itself. Ferocious Bite's base 35 is free; its `now`/`handler` still drain the energy left over (on
  vanilla rules Bite converts the extra energy under Clearcasting too).
- Maul's charge: the belief takes it at the swing (the on-next-swing rule: its `CastSuccess`, and with it the cost
  step and `SpendCostCharges`, arrives with the swing, `Now.lua:266`), as the client does; Hekili's simulation takes
  it at the press. The two differ by at most one swing.
- shortcut: a covered heal the file does not register (Tranquility) leaves Clearcasting believed up until its 15 s
  end; registering heals beyond the three would fix it.
- **Known limit.** The proc is unseen: while Clearcasting is up but not believed, a covered ability reads usable below
  its cost, and the ladder pins energy (or rage, or mana) at that rung. The free cast then pays the full cost in the
  belief, which roughly cancels the pin; the next rung corrects the rest. If Q6 finds the aura readable in combat,
  nothing is needed; if not, a TDF-style inference ("usable below the believed cost with the energy interval far
  below the rung") is a follow-up, not this spec.

## 8. Priorities
`tools/make_pack.lua` takes the class name, **default `warrior`**, and reads `tools/packs/<class>.lua` (each returns
`{ date = ..., packs = { { name, desc, simc } } }`); `loadfile( "tools/make_pack.lua" )( "lists", "druid" )` returns
the Druid's parsed lists, and the Warrior spec's existing `( "lists" )` call (`warrior_spec.lua`) keeps working
unchanged, as does `lua5.1 tools/make_pack.lua`. The Warrior's PACKS move to `tools/packs/warrior.lua` byte for byte (same strings, no version bump). The
Druid's three `spec:RegisterPack( <name>, DATE, [[...]] )` lines are pasted from its output.

**State the packs read** (registered in the class file):
- `excess_e` (`RegisterStateExpr`): the energy a GCD-triggering spender (Shred, Claw) may use now and still pay the
  coming Rip (at `settings.rip_cp` combo points) and Rake refreshes, with Shifting Power's +40 credited once it is off
  cooldown. Ported from TDF's `Expressions.excess_e` (credit, header): up to three events (Rip due at
  `debuff.rip.remains`, Rake at `debuff.rake.remains`, Shifting Power at `cooldown.shifting_power.remains`), sorted by
  due time in preallocated arrays (no table per call, as the Warrior's `queueEvents`); solved backwards: the energy
  needed before each event is its cost plus whatever regen (`energy.regen`) cannot cover of the events after it,
  honouring the 100 cap; `-math.huge` when the spender's GCD would delay a refresh that could otherwise start on time.
  A refresh the druid does not know (`action.rip.known`) or whose toggle is off reserves nothing. Refresh costs are the
  full price (the spender uses up Clearcasting): the base costs (Rip 30, Rake 40 - Ferocity), not `action.x.cost`,
  which Clearcasting may make 0. No `ttd`: Forever hides
  target health.
- `shred_ok` (`RegisterStateExpr`): `settings.behind or ( group and not buff.not_behind.up )` (TDF's switch; Classic's
  `combat_mode` setting is replaced by Hekili's `group`).
- The not-behind window: the combat-log handler's twin for `UI_ERROR_MESSAGE` records the time of the "must be behind"
  error (its message type, Q11; until recorded the list is empty and the window never opens, as in TDF); `reset_precast`
  applies `not_behind` for the rest of 5 s.

**Settings** (TDF's names and defaults): `rip_cp` (5, 1-5), `bite_finisher` (false), `behind` (false), `buffs` (true),
`dump_rage` (60), `use_enrage` (false), `moonkin` (true), `trash_dots` (true), `starfire_filler` (false),
`hurricane_targets` (4), `innervate` (true).

**Feral** (Nerdegghead via the user; TDF `feral.simc`; Classic `DruidFeral.simc`'s precombat buffs):
```
actions.precombat=mark_of_the_wild,if=settings.buffs&!buff.mark_of_the_wild.up&!buff.gift_of_the_wild.up
actions.precombat+=/thorns,if=settings.buffs&!buff.thorns.up
actions.precombat+=/cat_form,if=!buff.cat_form.up
actions=cat_form,if=!buff.cat_form.up
actions+=/shifting_power,if=energy.current<50
actions+=/use_items
actions+=/berserk
actions+=/rip,if=combo_points.current>=settings.rip_cp&!debuff.rip.up
actions+=/rake,if=!debuff.rake.up
actions+=/ferocious_bite,if=settings.bite_finisher&combo_points.current>=5&debuff.rip.up&excess_e>=energy.current
actions+=/shred,if=shred_ok&excess_e>=action.shred.cost
actions+=/claw,if=!shred_ok&excess_e>=action.claw.cost
```
Left out on purpose: Tiger's Fury, powershifting and the `cat_ps`/`innervate_or_shift` lists, Omen of Clarity's
precombat line, `ttd` guards, Faerie Fire in cat (not in Nerdegghead's priority), the ranged Moonfire opener.

**Guardian** (provisional; TDF `bear.simc`):
```
actions.precombat=bear_form,if=!buff.bear_form.up
actions=bear_form,if=!buff.bear_form.up
actions+=/run_action_list,name=aoe,if=active_enemies>=2
actions+=/berserk
actions+=/use_items
actions+=/demoralizing_roar,if=!debuff.demoralizing_roar.up
actions+=/lacerate,if=debuff.lacerate.stack>=5&debuff.lacerate.remains<=4.5
actions+=/primal_bite
actions+=/faerie_fire,if=!debuff.faerie_fire.up
actions+=/lacerate,if=boss&debuff.lacerate.stack<5
actions+=/maul,use_off_gcd=1,if=rage.current>=action.maul.cost+action.primal_bite.cost|!action.primal_bite.known
actions+=/swipe_bear,if=rage.current>=settings.dump_rage
actions+=/enrage,if=settings.use_enrage&rage.current<action.primal_bite.cost
actions+=/frenzied_regeneration
actions.aoe=demoralizing_roar,if=!debuff.demoralizing_roar.up
actions.aoe+=/berserk,if=active_enemies>=3
actions.aoe+=/use_items
actions.aoe+=/primal_bite
actions.aoe+=/swipe_bear
actions.aoe+=/maul,use_off_gcd=1,if=rage.current>=action.maul.cost+action.swipe_bear.cost+action.primal_bite.cost|!action.primal_bite.known&rage.current>=action.maul.cost+action.swipe_bear.cost
actions.aoe+=/faerie_fire,if=!debuff.faerie_fire.up
```

**Balance** (provisional; TDF `balance.simc` without the consumables):
```
actions.precombat=moonkin_form,if=settings.moonkin&!buff.moonkin_form.up
actions.precombat+=/mark_of_the_wild,if=settings.buffs&!buff.mark_of_the_wild.up&!buff.gift_of_the_wild.up
actions.precombat+=/thorns,if=settings.buffs&!buff.thorns.up
actions=innervate,if=settings.innervate&mana.current<action.starfire.cost*2
actions+=/use_items
actions+=/call_action_list,name=aoe,if=settings.hurricane_targets>0&active_enemies>=settings.hurricane_targets
actions+=/moonfire,if=!debuff.moonfire.up&(boss|settings.trash_dots)
actions+=/insect_swarm,if=!debuff.insect_swarm.up&boss
actions+=/starfire,if=!moving&buff.eclipse.stack>=1
actions+=/starfire,if=!moving&settings.starfire_filler
actions+=/wrath,if=!moving
actions.aoe=moonfire,if=!debuff.moonfire.up
actions.aoe+=/hurricane,if=!moving
```

## 9. Races
Druid races on Forever: Night Elf and Tauren; no Gnome Druid (the DB2 has no DRUID Eureka! or Expansive Mind, R §8),
so `Forever/Races/Gnome.lua` never touches the Druid and the Druid appends nothing to its `spells`.

- **`Forever/Races/NightElf.lua`** (new; Gnome.lua's shape, `Hekili:NewRace( "NightElf" )`, inert for any other race,
  so it serves the Night Elf Warrior too): Elune's Light 1259799 (one ID for every class; +10% crit with spells and
  attacks, aura 290 base 10; 180 s, off the GCD, 15 s): `race:RegisterAbility( "elunes_light", { id = 1259799, cast =
  0, cooldown = 180, gcd = "off", startsCombat = false, toggle = "cooldowns", handler = function () applyBuff( "elunes_light" ) end,
  now = function () applyBuff( "elunes_light" ) end } )` (two closures: one shared would be refused, "now is its handler") and its aura (15 s). No resource or cost modifier. Shadowmeld stays in `all`.
  No pack names it (a race ability is absent for other races, and the spec test "names only registered abilities"
  would fail); the player adds it to a priority if wanted.
- **`Forever/Races/Tauren.lua`** (new; the same shape, inert for any other race): War Stomp (20549: 2 s stun, 0.5 s
  cast, 120 s, off the GCD) and its target aura, because Hekili's `all` spec has no `war_stomp` (it has Berserking and
  Shadowmeld only); no pack names it. Plainsrunning (1259918) is a passive movement-speed ramp, and Endurance and
  Cultivation are passives: nothing to register.
- **Troll: no file.** Berserking (20554, DRUID in its DB2 class mask) is a stock racial in `all`, so a Troll Druid (if
  any, Q14) already gets it; no Forever-specific Troll racial is known.
- Skyborne racials (1259416, 1259686, 1259705, 1259707, 1259710): classes unknown; Q14 lists what a Druid knows.

## 10. Tests
`Forever/spec/druid_spec.lua` through `Forever/spec/helpers/load_druid.lua` (load_warrior.lua's recording stand-in,
copied: `Enum.PowerType` gains Energy 3, ComboPoints 4, Mana 0; `game.form`/`formSpell` as the Warrior's; `w.events`,
`VS.KnownRank` and `GetTime` as Task 13's; the stand-in `state` gains `energy`, `combo_points`, `mana`; it requires
`Virtual.State.spec.helpers.load` where the Warrior spec does). TDF layout.

**The KIT pin table** (from the DB2; cost with every talent at rank 0, the first rank's cost where it varies by rank;
a fraction for a percent-of-mana cost; gcd `"totem"` for 1.0 s):
```lua
-- key = { spell IDs in rank order, cost, spendType, cooldown, gcd }
local KIT = {
    claw = { { 1082, 3029, 5201, 9849, 9850 }, 45, "energy", 0, "totem" },
    shred = { { 5221, 6800, 8992, 9829, 9830 }, 60, "energy", 0, "totem" },
    rake = { { 1822, 1823, 1824, 9904, 1289140 }, 40, "energy", 0, "totem" },
    rip = { { 1079, 9492, 9493, 9752, 9894, 9896, 1289141 }, 30, "energy", 0, "totem" },
    ferocious_bite = { { 22568, 22827, 22828, 22829, 31018, 1289142 }, 35, "energy", 0, "totem" },
    ravage = { { 6785, 6787, 9866, 9867 }, 60, "energy", 0, "totem" },
    pounce = { { 9005, 9823, 9827 }, 50, "energy", 0, "totem" },
    cower = { { 8998, 9000, 9892 }, 20, "energy", 10, "totem" }, prowl = { { 5215, 6783, 9913 }, 0, nil, 10, "off" },
    dash = { { 1850, 9821 }, 0, nil, 300, "off" }, shifting_power = { { 1322605 }, 0.55, "mana", 16, "totem" },
    berserk = { { 417141 }, 0, nil, 180, "off" }, cat_form = { { 768 }, 0.55, "mana", 0, "spell" },
    bear_form = { { 5487, 9634 }, 0.55, "mana", 0, "spell" }, moonkin_form = { { 24858 }, 0.35, "mana", 0, "spell" },
    travel_form = { { 783 }, 0.20, "mana", 0, "spell" }, aquatic_form = { { 1066 }, 0.20, "mana", 0, "spell" },
    maul = { { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }, 15, "rage", 0, "off" },
    swipe_bear = { { 779, 780, 769, 9754, 9908 }, 20, "rage", 0, "spell" },
    primal_bite = { { 407995, 1238069, 1238070, 1238073 }, 20, "rage", 6, "spell" },
    lacerate = { { 414644, 1235826, 1235827 }, 15, "rage", 0, "spell" },
    demoralizing_roar = { { 99, 1735, 9490, 9747, 9898 }, 10, "rage", 0, "spell" },
    growl = { { 6795 }, 0, nil, 8, "off" }, bash = { { 5211, 6798, 8983 }, 10, "rage", 60, "spell" },
    challenging_roar = { { 5209 }, 15, "rage", 600, "spell" }, enrage = { { 5229 }, 0, nil, 60, "off" },
    frenzied_regeneration = { { 22842 }, 0, nil, 180, "spell" },
    feral_charge = { { 1238122, 16979 }, 5, "rage", 15, "off" },
    faerie_fire = { { 770, 778, 9749, 9907 }, { 55, 75, 95, 115 }, "mana", 0, "spell" },
    wrath = { { 5176, 5177, 5178, 5179, 5180, 6780, 8905, 9912 }, { 10, 20, 40, 50, 70, 80, 100, 120 }, "mana", 0, "spell" },
    starfire = { { 2912, 8949, 8950, 8951, 9875, 9876, 25298 }, { 95, 135, 180, 230, 275, 315, 340 }, "mana", 0, "spell" },
    moonfire = { { 8921, 8924, 8925, 8926, 8927, 8928, 8929, 9833, 9834, 9835 },
        { 25, 50, 75, 105, 150, 190, 235, 280, 325, 375 }, "mana", 0, "spell" },
    insect_swarm = { { 5570, 24974, 24975, 24976, 24977 }, { 45, 85, 100, 140, 160 }, "mana", 0, "spell" },
    hurricane = { { 16914, 17401, 17402 }, { 880, 1180, 1495 }, "mana", 0, "spell" },
    entangling_roots = { { 339, 1062, 5195, 5196, 9852, 9853 }, { 50, 65, 80, 95, 110, 125 }, "mana", 0, "spell" },
    innervate = { { 29166 }, 0.05, "mana", 360, "spell" }, barkskin = { { 22812 }, 0, nil, 60, "spell" },
    natures_grasp = { { 16689, 16810, 16811, 16812, 16813, 17329 }, { 50, 65, 80, 95, 110, 125 }, "mana", 60, "spell" },
    mark_of_the_wild = { { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, { 20, 50, 100, 160, 240, 340, 445 }, "mana", 0, "spell" },
    gift_of_the_wild = { { 21849, 21850 }, { 900, 1200 }, "mana", 0, "spell" },
    thorns = { { 467, 782, 1075, 8914, 9756, 9910 }, { 35, 60, 105, 170, 240, 320 }, "mana", 0, "spell" },
    healing_touch = { { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },
        { 25, 55, 110, 190, 280, 350, 425, 520, 630, 755, 840 }, "mana", 0, "spell" },
    regrowth = { { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
        { 70, 125, 170, 210, 250, 305, 370, 445, 525 }, "mana", 0, "spell" },
    rejuvenation = { { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
        { 25, 40, 75, 105, 135, 160, 195, 235, 280, 335, 360 }, "mana", 0, "spell" },
}
```
The plan re-reads every row from `wowdb` before writing it (Nature's Grasp ranks 4-6 costs and the per-rank costs above
are the research's; a row that disagrees with the DB2 is corrected, not the DB2).

**Cases** (each the Warrior's counterpart where one exists):
1. registers the kit with the DB2's ranks, costs, cooldowns and GCDs (KIT), and no SoD rune or Tiger's Fury spell.
2. models the talent-modified costs from rank 1's value x the rank: Ferocity on Claw/Rake/Maul/Swipe/Primal Bite,
   Shredding Attacks on Shred and Lacerate, Natural Shapeshifter on the forms and Shifting Power, floored at 0.
3. gates every ability on the form §3 names (`buff`/`nobuff`/function), Ravage and Pounce on Prowl, Faerie Fire free
   only in Cat or Bear.
4. registers the 47 DB2 nodes (TALENTS pin: `{ spell, max }`) plus the three placeholder keys (`improved_shifting_power`,
   `natures_splendor`, `eclipse`), and no rank aliases.
5. registers every aura a handler, `now`, state function or gate names (the Warrior's case 208).
6. declares `now` on the abilities §4 lists, and their effects: Rake/Rip/Pounce/Lacerate/Demoralizing Roar/Faerie Fire
   debuffs (Lacerate +1 stack to 5; Pounce's stun duration with Brutal Impact), Shifting Power +40 energy, Enrage +10
   rage and its buff, Bite's leftover energy, Wrath's Eclipse stacks only with `talent.eclipse.rank > 0`, Starfire's
   `handler` removing one stack, Bash's stun at spellbook rank 0, and no `now` writes combo points.
7. a shift: Bear Form spends all rage and removes the other forms and `maul`; Cat Form writes no energy.
8. reads the form at reset from the shapeshift read (Dire Bear -> `bear_form`), and Maul's queue from `IsCurrentSpell`.
9. gains rage per white swing at 2.5 x 3.46 in Bear Form and none in Cat Form (the swing entry declares
   `aura = "bear_form"` and a `stop` reading the form); Enrage's 2/s entry; decay 1.25.
10. declares the energy resource with no regen model and no decay, combo points with no max, mana with no max.
11. declares the Clearcasting cost modifier through `spec:RegisterCostMod` with exactly the covered rank-1 IDs, and no
    ability's `spend` reads `buff.clearcasting` (a grep over the file in the spec).
12. the combat log: a missed Rake or Rip row removes the debuff at the next reset, a hit does not; the not-behind error
    opens `not_behind` for the rest of 5 s.
13. `excess_e`: Shred allowed when the energy covers Shred, Rip and Rake in time; held when Rip at 5 CP is due within
    the regen; Shifting Power's 40 credited off cooldown; `-math.huge` when the GCD would delay an on-time refresh; an
    unknown Rip reserves nothing; zero allocation over 1000 calls.
14. registers the Feral, Guardian and Balance packs exactly as `tools/make_pack.lua druid` prints them (and the
    Warrior's pack case still passes with the default class), Feral the
    default package; and the packs name only registered abilities, auras, talents, settings and lists.
15. `Forever/spec/races_spec.lua` (facade suite) gains: NightElf.lua and Tauren.lua inert for another race, registered for
    their own, and each race ability's `now` run in the strict context.

Kept by the verification block (the Warrior's): busted, luacheck, `tools/check_api_reads.sh` (the class file reads the
game only through `ns.Facade`), the api-inventory diff, LuaLS `--checklevel=Error`, `luac5.1 -p`.

## 11. Checkpoint questions
One in-game session on a Druid, ForeverProbe loaded (`VSCopy(` prints to the copy box, `/vscopy` reopens it; every
line under 255 characters), the client pointed at the branch. Run Q1 first: its answer rewrites §6 before anything
else is judged. Each action is its own commit with the verification block and, where a value changes, its KIT row.

| # | Question | Line(s) | Answer → action |
|---|---|---|---|
| Q1 | **The live talent tree and the spec ID** (the DB2 has the old 47; the Warrior's 52 came from this export) | out of combat: `/fprobe export`, `/reload`, then `/run local e=ForeverProbeDB.export;VSCopy(e.meta.class,#e.spells,#e.talents.trees,e.stances.num)` and `/run VSCopy(C_SpecializationInfo.GetSpecialization(),GetSpecializationInfo(1))`; the orchestrator copies `SavedVariables/ForeverProbe.lua` | the export's nodes → `RegisterTalents` (definition spells, max ranks, Forever-only keys, removed ones dropped with their readers), TALENTS pin, the two placeholder keys replaced; the spec ID → `DRUID_SPEC` (replacing 1499) and its `Constants.lua` row; 1491 → stop and report (rows are keyed by ID alone) |
| Q2 | **Form read in combat** | `/run for i=1,GetNumShapeshiftForms() do VSCopy(i,GetShapeshiftFormInfo(i)) end`, then in each form in combat `/run VSCopy(GetShapeshiftForm(),pcall(C_UnitAuras.GetPlayerAuraBySpellID,768))` | plain → none (§3 stands); secret → `reset_precast` infers Cat/Bear from the usability read (Claw/Maul unusable for a non-power reason = not in that form), TDF's tracker |
| Q3 | **Energy regen and Furor** | in Cat out of combat `/run VSCopy(GetTime(),GetPowerRegenForPowerType(3))` now and every 20 s for 2 min; then leave Cat at a known energy (the bar), wait 5 s, shift back and read the bar | rate rises 25% → an aura- or talent-gated regen entry for Feral Dedication; ticks → keep Classic's tick model; Furor's energy matches 20%/rank + 10/s out → Cat Form's `now` gains it (file-level leave time and energy written by the other forms' `now`) |
| Q4 | **Costs with talents; Shifting Power's cooldown** | `/run for _,i in ipairs({5221,1082,1822,1079,22568,6807,779,407995,414644,1322605}) do local c=C_Spell.GetSpellPowerCost(i) c=c and c[1] VSCopy(i,c and c.type,c and c.minCost) end`; after Shifting Power `/run local c=C_Spell.GetSpellCooldown(1322605) VSCopy(c.duration)` | equal → none; different → that ability's per-rank reduction; cooldown ≠ 16 - 4 x rank → D5's formula |
| Q5 | **Mana: max, regen, five-second rule** | `/run VSCopy(UnitPowerMax("player",0),GetPowerRegenForPowerType(0),GetManaRegen())` out of combat, again right after a cast | plain max → none (the belief's fractional costs and rest use it, §0); secret → `max` in the mana meta from the reported value, which §0's costs and rest then use; regen shape recorded for a Balance follow-up |
| Q6 | **Clearcasting visibility and coverage** | when it procs in combat: `/run VSCopy(pcall(C_UnitAuras.GetPlayerAuraBySpellID,16870))`; below 60 energy `/run VSCopy(C_Spell.IsSpellUsable(5221))`; with it up in Bear: `/run VSCopy(C_Spell.IsSpellUsable(407995),C_Spell.IsSpellUsable(99))` at 0 rage | readable → none; secret and usable below cost → record for the follow-up tracker (§7 known limit); Primal Bite or Demoralizing Roar not usable at 0 rage → remove its rank-1 ID from `spells` |
| Q7 | **Faerie Fire in forms** | in Bear: `/run local c=C_Spell.GetSpellCooldown(9907) VSCopy(c.startTime,c.duration,C_Spell.IsSpellUsable(9907))`; out of combat after casting on a dummy `/run VSCopy(C_UnitAuras.GetAuraDataByIndex("target",1,"HARMFUL").spellId)` | free and 6 s → none; else `spend`/`cooldown` from the reads; debuff 1288561 → add it to `faerie_fire`'s `copy` |
| Q8 | **Bear swing rage** | in Bear on a dummy `/run VSCopy(UnitAttackSpeed("player"))`, then `/run VSCopy(Hekili.VirtualState.Snapshot())` before and after 10 swings, comparing with the bar | ~8.65 a swing → none; ~11.25 → `BEAR_RAGE_RATE = 4.5`; other → the measured rate per second of swing |
| Q9 | **Bear rage decay and the shift's rage** | in Bear out of combat `/run VSCopy(GetPowerRegenForPowerType(1))` (Warrior -12.499); shift out and back with rage up and read the bar | -12.5 → none; else `decay` from the read; rage kept on a shift → Bear Form's `now` stops spending it |
| Q10 | **Combo points** | at 3 CP in combat `/run VSCopy(GetComboPoints("player","target"),UnitPower("player",4))`, again after `/targetlasttarget`, after the target dies, after a dodged Rip | both plain → none; `UnitPower(4)` secret → stop and report (a Power source change, outside the class file); a missed finisher spends them → the miss handler also zeroes them in the sim |
| Q11 | **"Must be behind" error** | `/run local f=CreateFrame("Frame") f:RegisterEvent("UI_ERROR_MESSAGE") f:SetScript("OnEvent",function(_,e,a,b) VSCopy(a,b) end)`, then Shred from the front | the message type → `NOT_BEHIND_ERRORS` in the class file |
| Q12 | **Shredding Attacks on Lacerate** | with 1 point: `/run local c=C_Spell.GetSpellPowerCost(414644) VSCopy(c and c[1] and c[1].minCost)` | 9 → none (-6 a rank); 14 → -1 a rank |
| Q13 | **Maul queue; Frenzied Regeneration's cooldown** | right after pressing Maul in combat `/run VSCopy(C_Spell.IsCurrentSpell(6807))`; after Frenzied Regeneration `/run local c=C_Spell.GetSpellCooldown(22842) VSCopy(c.startTime,c.duration)` | true → none; secret → Maul's `usable` falls back to none (the client refuses a double queue); duration ≠ 180 → `cooldown` and its KIT row |
| Q14 | **Race and racials** | `/run VSCopy(UnitRace("player"))` and `/run VSCopy(IsSpellKnown(1259799),IsSpellKnown(1259918),IsSpellKnown(20580),IsSpellKnown(20549),IsSpellKnown(20554))` | Night Elf token `NightElf` → none; another token or Elune's Light unknown → fix `NewRace`'s token; a Troll Druid knowing 20554 → none (stock) |
| Q15 | **Form gates per form** (the Warrior's Q1) | in each form `/run VSCopy(GetShapeshiftForm(),C_Spell.IsSpellUsable(5221),C_Spell.IsSpellUsable(6807),C_Spell.IsSpellUsable(5176),C_Spell.IsSpellUsable(1126),C_Spell.IsSpellUsable(770))` | as §3 → none; an ability usable in more forms → its `buff` becomes a function returning the current form's aura, or the gate goes |
| Q16 | **What exists at the cap** | `/run VSCopy(IsSpellKnown(407995),IsSpellKnown(1322605),IsSpellKnown(417141),IsSpellKnown(414644),IsSpellKnown(408255),IsSpellKnown(417157),IsSpellKnown(407988),IsSpellKnown(414924))` | rune spells (417157, 407988, 414924) false → none; true → report (scope question, not this spec) |

Also recorded: any recommended ability the client refuses; one Rip cycle (Shred held for Rip at 5 CP). Known limits:
Clearcasting unseen (§7), Furor's energy (§3), rage from damage taken (§2.3), a missed bleed in the belief (§4).

## 12. Open decisions for the user
Execution proceeds on the defaults; each is one commit to change.

| # | Decision | Default |
|---|---|---|
| D1 | How class content declares a cost modifier: a `spec:RegisterCostMod( def )` in `Classes.lua` (a named core edit; same signature as the race object's; appends to the list `Races.lua` and the adapter already read), or the class file appending to `ns.raceMods.costMods` itself (no core edit, a misleading name). | **`spec:RegisterCostMod`**: one small core function, and a priest's Inner Focus or a mage's Clearcasting later uses the same call. |
| D2 | Which packs ship: Feral only; Feral + provisional Guardian and Balance; or all four with a Restoration stub. | **Feral (default) + Guardian and Balance marked provisional; Restoration deferred** (no source priority, health secret). |
| D3 | Talents before the export: register the DB2's 47 now and apply the Forever export as its own commit after Q1; or hold the class file's talents until the export. | **The 47 now, the export as a follow-up commit**; abilities gate on `known`, so nothing in the rotation waits. |
| D4 | Bear swing rage rate: 3.46 (one-hand main-hand rate) or 4.5 (two-hand rate) x the 2.5 s form swing, until Q8 measures it. | **3.46** (8.65 a swing): the form's paws are not a two-hander, and the lower guess errs toward not over-promising Maul. |
| D5 | Improved Shifting Power's cooldown reduction: model it as rank 1's -4 s x the rank (a cooldown modifier, which the Warrior's ruling would leave out), or leave Shifting Power at 16 s. | **Model it** (16 - 4 x rank, Q4 checks): it moves the Feral rotation's main energy source by 25-50%, too large to leave to calibration. |

## 13. Sources
- Research brief `/home/zack/.claude/jobs/080a308e/tmp/druid/research.md` (R §0-§10, with its own sources).
- Facade branch `~/src/hekili/.claude/worktrees/virtualstate-event-facade` (head 5114e04a; Task 13 fe727909):
  `Forever/Classes/Warrior.lua`, `Forever/Races/Gnome.lua`, `Races.lua`, `Forever/spec/warrior_spec.lua`,
  `tools/make_pack.lua`, `Virtual/State/Adapter.lua`, `Virtual/State/Families/{Resources,Casts,Now}.lua`; spec
  `docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md` §12a/§12b; plan `...-phase-ab.md` Task 13 (:7911).
- `~/src/hekili`: `docs/superpowers/plans/2026-10-15-forever-warrior-{profile,accuracy}.md` (Task 5 checkpoint, rulings
  A1-A8), `Constants.lua:247`; `origin/classic:Classic/Druid.lua`, `Classic/APLs/DruidFeral.simc`;
  `origin/wrath_release:Wrath/Druid.lua` L413-566.
- The Warrior export: `/home/zack/.claude/jobs/080a308e/tmp/warrior/{export-report.md,export/talents.txt,reconcile.md}`;
  `~/src/ForeverProbe/Export.lua`.
- Taco Dog Forever (ported, credited): `src/TacoDogForever_Druid/{Feral,Bear,Balance,Expressions,Register}.lua`, `APLs/`.
- DB2 `wowdb` 1.60.1.70338 (queried 2026-10-15; the rest via R §3-§5). Clearcasting 16870's coverage: the caller's
  derived DB2 masks, used as given.

## Rulings (controller, user away, 2026-10-15)
D1 spec:RegisterCostMod (named core edit); D2 Feral ships, Guardian/Balance provisional, Restoration deferred; D3 DB2 47 nodes now, live export as its own commit after Q1; D4 bear 3.46 x 2.5 s until Q8; D5 Improved Shifting Power modelled 16 - 4 x rank, checked by Q4. Spec ID: read in Q1; stop and report if the Druid also reports 1491. make_pack.lua per-class pack text accepted.
