# Forever shared content pass in the Hekili fork: design spec (2026-10-15)

Status: draft for the user's review. Target: branch `forever-shared` at a414b73c (`src/Hekili/` is the addon, `tests/`
mirrors it; `docs/dev/layout.md`). Inputs: the research brief `tmp/shared/research.md` ("R", the `all` inventory at
688dd350, with its controller corrections: the racials are the race packs' since `forever-races`, and the facade remapped
61304 to 29515), the Forever DB2 (build 1.60.1.70338, `wowdb`) and the core reads at a414b73c. Plan:
`docs/superpowers/plans/2026-10-15-forever-shared-content.md`.

## 1. Scope

The shared `all` spec held two things in one 3,428-line file: the spec engine (the mixin, `all`'s creation,
SpecializationChanged's merge) and retail's shared content (lusts, racials, potions, healthstones, trinkets, dispels).
This pass splits them and keeps only content that exists and is observable on Forever:

- the engine becomes `src/Hekili/Engine/Spec.lua` (renamed `Classes.lua`), beside `Engine/Races.lua` (renamed
  `Races.lua`) and a new `Engine/Shared.lua`;
- shared game content moves to `src/Hekili/Forever/Shared/{Auras,Consumables,Items}.lua`, registered through
  `Hekili:NewShared()`;
- dead retail content is dropped, every drop checked against every priority, class, race, engine and shared file by a
  test;
- the GCD is asked as Forever's own spell everywhere (one constant), and the facade's 61304 remap goes.

Not in scope: class content beyond what `all` gave up (the class files are untouched), the race packs (untouched), new
Forever consumables or trinkets beyond the Healthstone (§9), the layer.

## 2. The rule

Binding (user). Each `all` key is decided by the first that applies:

| # | Content | Decision |
|---|---|---|
| R1 | ours, class-specific | the class file (nothing of that kind stays shared) |
| R2 | ours, cross-class (consumables, trinkets, racials) | `Forever/Shared/<File>.lua` or the race pack; a `now` where the cast changes more than its cost, cooldown and GCD (the race packs' convention) |
| R3 | external, on the player | keep: the player's aura walk reads it in combat |
| R4 | external, on the target | keep only with a reason to read it out of combat; else drop (a target's auras are secret in combat) |
| R5 | does not exist on Forever | drop, or replace the ID with the same-named Forever spell |
| core | engine state core reads by name | stays in the engine (`Engine/Spec.lua`) |

## 3. The engine rename and `Hekili:NewShared`

`git mv src/Hekili/Classes.lua src/Hekili/Engine/Spec.lua` and `git mv src/Hekili/Races.lua src/Hekili/Engine/Races.lua`;
`Hekili.toc` names them in their old places (`Engine\Races.lua` before `Events.lua`, `Engine\Spec.lua` after it), then
`Engine\Shared.lua` and the three content files, before the class files (a race file still loads after every shared
file, so a race registration still wins its key in `all`). `.luacheckrc` moves `Classes.lua`'s entry and gives
`src/Hekili/Forever/Shared/` the `stateEnv` globals. Every path and comment naming the two files follows
(`tests/Virtual/State/races_spec.lua` reads both by path).

`Engine/Spec.lua` keeps: the mixin and Register* API, `NewSpecialization`, the helpers that were already there
(`ns.addToggle` .. `ns.setRole`, `GetAbilityInfo`, `GetActiveSpecOption`), `all`'s creation with the engine keys core
reads by name (§4.5), SpecializationChanged and the merge, the spell/gear reset events. Nothing else.

`Engine/Shared.lua` (~40 lines): `Hekili:NewShared()` returns an object with the race object's four calls,
`RegisterAbility( key, def )`, `RegisterAura( key, def )`, `RegisterResourceMod( { max = pct } )`,
`RegisterCostMod( def )`. Always live (any class, any race), writing into `all` (`Hekili.Class.specs[ 0 ]`, resolved at
call time) and into `ns.raceMods`; it records no ownership, so a class's entry still wins the merge and a race pack's
`ns.applyRace` still wins over both.

## 4. Decisions per family

Forever ID: `wowdb` at build 1.60.1.70338; "none" = no spell of that ID or name (R §1-§5). Basis: the rule of §2.

### 4.1 Auras (`all:RegisterAuras`, old Classes.lua:1484-2323)

| key | old ID | decision | new home | Forever ID | basis |
|---|---|---|---|---|---|
| voidbinding | 462661 | stub (no ID) | Shared/Auras | none | R5; core reads (State.lua:2968) |
| shadowform | 232698 | stub | Shared/Auras | none (Priest 15473, no pack) | R5; core reads (State.lua:1983) |
| voidform | 194249 | stub | Shared/Auras | none | R5; core reads (State.lua:3201, 3214) |
| adrenaline_rush | 13750 | stub | Shared/Auras | 13750 (Rogue; no GCD effect on Forever) | R1, no Rogue file; core reads (State.lua:3198, 3211) |
| bloodlust (alias) | members of 9 | keep, one member | Shared/Auras | via bloodlust_actual | R3; core reads (State.lua:2649) |
| bloodlust_actual | 2825 | replace | Shared/Auras | 1245940 (checkpoint Q2) | R5 + R3 |
| power_infusion | 10060, 20 s | keep, 15 s | Shared/Auras | 10060 (15 s) | R3; core reads (State.lua:2649) |
| ancient_hysteria, heroism, time_warp, netherwinds, primal_rage, drums_of_deathly_ferocity, fury_of_the_aspects, harriers_cry | 90355, 32182, 80353, 160452, 264667, 309658, 390386, 466904 | drop | - | none (same-name 19372 "Ancient Hysteria" and the "Heroism" procs are other spells) | R5 |
| exhaustion, insanity, temporal_displacement, fatigued, sated, sated_actual | 57723/390435, 95809, 80354, 264689, alias, 57724 | drop | - | none (24225 "Exhaustion", 3271 "Fatigued", 470085 "Sated" are other spells) | R5; checkpoint Q3 |
| mark_of_the_wild | 1126 | drop from `all` | Druid.lua (owns it) | 1126 | R1 |
| battle_shout | 6673 | drop from `all` | Warrior.lua (owns it) | 6673 | R1 |
| berserking, blood_fury, shadowmeld (auras) | 26297, 20572, 58984 | drop from `all` | Troll/Orc/NightElf race packs | 20554, 20572, 20580 | R2 |
| loss_of_control, disoriented, feared, incapacitated (copy sapped), rooted, snared (copy slowed), stunned | generators | keep, verbatim | Shared/Auras | `C_LossOfControl` (plain, W PR12/PR18) | R3 |
| dispellable_curse, _poison, _disease, reversible_magic | generators | keep, verbatim | Shared/Auras | player debuff walk | R3; checkpoint Q1 (`dispelName`) |
| dispellable_magic | generator (player debuff + target buff) | keep the player half: reversible_magic's generator | Shared/Auras | player debuff walk | R3 / R4 (target half dropped) |
| stealable_magic, dispellable_enrage | target buff walks | drop | - | - | R4: no class reads them, nothing to read in combat |
| all_absorbs (copy unravel_absorb) | `UnitGetTotalAbsorbs` | drop | - | unprobed (Q7) | R4 for the target; no reader, an unguarded compare on a possibly secret total |
| out_of_range | LibSpellRange | drop | - | - | no reader in core or any pack |
| casting, movement, unknown_buff | generators | keep | Engine/Spec.lua | - | core (the target half of `casting` is answered by the layer's TargetCast family through the facade) |

**Stubs or a core edit** (the four keys State.lua reads by name, plus voidbinding). Chosen: id-less stubs
(`voidform = {}`), never found on a unit, so never up. Smaller: four lines in one content file against five hunks in
State.lua's hot paths (the GCD length on every recommendation, the cooldown read), and the core keeps its retail shape.
Cost: four dead keys; the key test (§8) forbids any priority, class, race or engine file from naming them.

### 4.2 Racials (`all:RegisterAbilities`, old 2476-2610)

| key | old ID | decision | owner | Forever ID | basis |
|---|---|---|---|---|---|
| berserking | 26297 | drop from `all` | Forever/Races/Troll.lua | 20554 | R2 |
| blood_fury (+ `bf_classes`, copies 33702, 33697) | per class | drop | Orc.lua | 20572 | R2 |
| will_to_survive | 59752 | drop | Human.lua | 1259718 | R2 |
| shadowmeld | 58984 | drop | NightElf.lua | 20580 (Q6) | R2 |
| stoneform (+ aura 65116) | 20594 @120 | drop | Dwarf.lua | 20594 @180 | R2 |

Since `forever-races` each race pack registers its racial for its own race (R corrections). `all`'s stale copies were
still merged into every other race's class tables with retail IDs: they go. Scripts.lua's `stealthed.shadowmeld` token
reads `buff.shadowmeld`, registered for a Night Elf only, else the unknown aura (down).

### 4.3 Consumables (old 2326-2474, healthstone 2660-2694)

| key | old ID | decision | new home | Forever ID | basis |
|---|---|---|---|---|---|
| potion (action, copy potion_default) | default item 191387 | keep without a default; usable only once a Forever potion is registered (none is) | Shared/Consumables | none | R2; core reads (State.lua:2989, Core.lua:822) |
| fake_potion, potion (aura alias) | - | keep | Shared/Consumables | - | R2; core reads (State.lua:820) |
| `exp_potions` loop and its `reset_precast` hook | empty list | drop (registers nothing) | - | - | R5 |
| healthstone | 224464 / 5512, `talent.pact_of_gluttony`, cd 3600/60 | replace: the best of Forever's 15 Healthstone items in the bags, cd 120 (Q5) | Shared/Consumables | items 19013, 19012, 9421, 19011, 19010, 5510, 19009, 19008, 5509, 19007, 19006, 5511, 19005, 19004, 5512 (spells 11732, 5723, 5720, 6263, 6262) | R2 + R5 |
| flasks, elixirs, food | - | nothing registered before or after | - | - | §9 |

No `now` on either action: VirtualState sees spell casts only and an item action carries no spell ID (RegisterAbility
gives it `-100 - n`), and the Healthstone's effect is health, which the belief does not track. The race packs'
convention (a `now` only for an effect beyond cost, cooldown and GCD) gives none. `readyTime` goes too: State.lua already
reads an item action's cooldown through `GetItemCooldown( item )`.

### 4.4 Items (old 2786-2810, 2948-3028, 3418-3428)

| key | decision | new home | basis |
|---|---|---|---|
| use_items | keep | Shared/Items | core (Core.lua:704, 901-953; Druid priorities) |
| trinket1/actual_trinket1, trinket2/actual_trinket2, main_hand/actual_main_hand | keep | Shared/Items | core (Events.lua:580-733 rebinds them) |
| null_cooldown | keep | Shared/Items | core (Events.lua's empty-slot stub) |
| class.trinkets (with its `[0]` fallback) | keep, empty | Shared/Items | State.lua:361-365 |
| unusable_trinket | drop | - | no reader |
| `setUsableItemCooldown`, `class.itemSettings`, `addItemSettings`, the commented `addUsableItem` | drop | - | no caller |

No retail trinket ID was registered (`class.trinkets` held only `[0]`): nothing to drop there.

### 4.5 Engine keys (stay in `Engine/Spec.lua`)

`casting`, `movement`, `unknown_buff`; `global_cooldown` (§5), `call_action_list`, `run_action_list`, `wait`,
`pool_resource`, `cancel_action`, `variable`, `cancel_buff`. These are core's vocabulary, not game content, so the
GCD action stays engine content rather than moving to Shared/Auras.

## 5. The GCD constant

`I.GCD_SPELL = 29515` (`Virtual/State/Sources/Spellbook.lua`, Forever's GCD spell, cleanup Q6) is the one name. The five
core sites read it as `ns.VirtualStateInternal.GCD_SPELL` in place of 61304: `global_cooldown`'s `id`
(Engine/Spec.lua), `UI.lua:1494` and `:1695`, `Events.lua:1679`, `Options/Options.lua:4043`. The facade drops its remap
rows: `C_Spell.GetSpellCooldown` and its policy answer 29515 only; `C_Spell.GetSpellInfo` and `C_Spell.GetSpellTexture`,
hybrid only to remap, become passthroughs (`tools/api_inventory.txt` and the facade spec's counts follow: 123
passthrough, 26 hybrid, 27 virtual). Nothing in a file the TOC loads names 61304 afterwards (a test). This reverses
event-facade decision 7 for the GCD only: the spec slot and the talent read stay in the facade.

## 6. Named core edits

| Edit | Where | What |
|---|---|---|
| E1 | `Core.lua:822-838` | the `potion` verb's fallback to the retail `tempered_potion` goes: no chosen potion, or one not registered, gives `wait` as before; the dead `or "tempered_potion"` after a found action goes |
| E2 | `Engine/Spec.lua`, `UI.lua` (2), `Events.lua`, `Options/Options.lua` | 61304 → `ns.VirtualStateInternal.GCD_SPELL` (§5) |

No State.lua edit (§4.1). `Options/DevTools.lua:1117` (a generator template's `potion = tempered_potion` line) is a dev
tool's text, not a read: untouched.

## 7. Checkpoint

After Task 5, a full client restart (new files in the TOC), ForeverProbe loaded. Each line copies through `VSCopy(`
(`/vscopy` reopens it; a secret prints `S`); every line is under 255 characters. Q0 confirms the load; Q1 is the
research's question 4 (the aura entry fields), first because two families depend on it.

| # | R | Question | Line | Answer → action |
|---|---|---|---|---|
| Q0 | - | the shared files load | `/run local a=Hekili.Class.specs[0] VSCopy(a.auras.loss_of_control~=nil,a.abilities.healthstone~=nil,a.abilities.use_items~=nil,Hekili.Class.abilities.global_cooldown.id)` | `true true true 29515` → none; else stop and report the error |
| Q1 | 4 | are `sourceUnit`, `isFromPlayerOrPlayerPet`, `dispelName` plain on the player's entries in combat | in combat with a buff and a debuff: `/run local a,b=C_UnitAuras.GetAuraDataByIndex("player",1,"HELPFUL"),C_UnitAuras.GetAuraDataByIndex("player",1,"HARMFUL") VSCopy(a and a.sourceUnit,a and a.isFromPlayerOrPlayerPet,b and b.spellId,b and b.dispelName)` | plain → none; `dispelName` `S` → drop `dispellable_*` and `reversible_magic` from Shared/Auras (and Stoneform's gate in Dwarf.lua), keys to the drop list; source fields `S` → none (no shared aura reads them), recorded |
| Q2 | 1 | the aura a Shaman's lust puts on the player | with it up: `/run for i=1,40 do local a=C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL") if not a then break end VSCopy(i,a.spellId,a.name,a.duration) end` | 1245940 → none; another ID → `bloodlust_actual.id` and its duration; no lust on Forever → `bloodlust_actual` dropped, `bloodlust` an id-less stub |
| Q3 | 2 | a lockout debuff after the lust | within a minute: the same walk with `"HARMFUL"` | none → none; an ID → a `sated` aura in Shared/Auras (it leaves the drop list) |
| Q4 | 3 | the GCD constant answers | right after a GCD ability: `/run local c=C_Spell.GetSpellCooldown(29515) VSCopy(c and c.startTime,c and c.duration,GetTime(),Hekili.State.cooldown.global_cooldown.duration)` | a 1.5 (1.0 in Cat) duration, `S` in combat with Hekili's number plain → none; nil → stop: `I.GCD_SPELL` is wrong |
| Q5 | 5 | an item cooldown in combat, and the Healthstone's length | after a Healthstone in combat: `/run for _,i in ipairs({19013,19012,9421,19011,19010,5510,19009,19008,5509,19007,19006,5511,19005,19004,5512}) do if C_Item.GetItemCount(i)>0 then VSCopy(i,C_Item.GetItemCooldown(i)) end end` | plain, 120 → none; another length → `cooldown`; `S` → stop and report: State.lua's item cooldown read needs a hybrid facade row (outside this pass) |
| Q6 | 6 | Shadowmeld's aura ID | while Shadowmelded: `/run for i=1,40 do local a=C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL") if not a then break end if a.name=="Shadowmeld" then VSCopy(a.spellId) end end` | 20580 → none; another → NightElf.lua's aura `id` |
| Q7 | 7 | the absorb total in combat | under an absorb: `/run VSCopy(UnitGetTotalAbsorbs("player"))` | either → none (`all_absorbs` stays dropped: no reader); recorded for a revival |
| Q8 | 8 | Shadowmeld's owner | as a Night Elf: `/run local s=Hekili.Class.abilities.shadowmeld VSCopy(s and s.id,s and s.cooldown)` | `20580 10` → none (closed by `forever-races`: the race pack owns it, R2); else report |

## 8. Tests

`tests/Forever/shared_spec.lua` (new; busted base 286 at a414b73c):

- Task 2 (facade_spec): no file the TOC loads names 61304, and `global_cooldown`'s `id` is the constant; the decision-7
  case keeps the spec slot and talent rank; the inventory counts follow; alloc_spec drops its 61304 call.
- Task 3: `NewShared` writes all four registrations for any race; Shared/Auras registers exactly its 19 keys (stubs
  id-less, Power Infusion 15 s, the lust alias and 1245940); `dispellable_magic` reads only the player's debuffs; the
  key test: no dropped key in `tools/packs/*.lua`, `Engine/*.lua` or `Forever/**/*.lua`, no stub outside
  Shared/Auras.lua, and each key `all` gave up registered by its owner and absent from Engine/Spec.lua.
- Task 4: Shared/Consumables registers `potion` (with `potion_default`), `healthstone`, `fake_potion` and the `potion`
  alias, the 15 Forever items, no `now`; the best Healthstone in the bags, Minor when none; `tempered_potion`, 191387,
  224464 and `pact_of_gluttony` join the drop list; Core.lua no longer names `tempered_potion`.
- Task 5: Shared/Items registers `use_items`, the slot actions with their `actual_*` copies and `null_cooldown`, an
  empty `class.trinkets`; each shared key is registered by one file only; `unusable_trinket` joins the drop list.

Every task ends with the verification block (busted, luacheck, the API-read check and inventory diff, LuaLS, `luac`).

## 9. Not modelled

Forever potions, flasks, elixirs and food (the default priorities leave consumables out; the `potion` verb waits);
trinket effects (`class.trinkets` empty); a lust lockout (`sated`) unless Q3 finds one; target-side dispels, purges and
enrage removal (R4); absorbs; spell range (`out_of_range`); a Healthstone's heal amount (the sim keeps 25%); the
`incapacitated` generator's retail `STUN` locType (kept verbatim; a mapping fix needs Forever's locTypes in game); the
race files' headers still say a racial "replaces `all`'s stock entry" (true of the retail entry this pass removed).
