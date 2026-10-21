# Architecture

How the pieces fit, as built after the restructure (`docs/dev/layout.md` has the folders and the in-game setup). Paths
are relative to `src/Hekili/` unless they start with another top-level folder.

## 1. The layers

```
 Forever client (WoW API, events)
        |  read only through ns.Facade (Game/API/Facade.lua), exposed to content as Hekili.Client
        v
 Game/        the game as the addon knows it: API (the facade), Events (synthesized), State (the belief,
              VirtualState: observed / pinned / modelled values)
        |
        v
 Engine/         Schema/  the registration API (Spec, Races, Shared)
                 Sim/     upstream's simulation (Core, State, Scripts, Events, Targets, Constants, Utils)
                 Driver   the HekiliEngine frame: frame budget, the recommendation thread
                 Output   per-display records, publish/subscribe        Settings   the profile port
                 Registry what content registered (read-only views)     Snapshot   the debug snapshot
                 Content  loads the shared content, then the class pack
        |  Hekili.Engine.Subscribe(name, fn)          ^ Hekili.Engine.Configure(profile)
        v                                             |
 subscribers: UI/ (displays), Integrations/WeakAuras, Options/ (owns the AceDB profile, Options.lua, Profile.lua)
 the headless loop (tests)

 Content addons (Hekili_Shared, Hekili_<Class>) call the public Hekili object: Hekili:NewClass,
 NewShared, NewRace, Hekili.State, Hekili.Class, Hekili.Client.
```

The client is read through the facade only. `Game/` turns client reads and events into a belief about the game.
`Engine/` runs the simulation against that belief and publishes, per display, a set of recommendation records. The UI,
WeakAuras and the headless test loop are subscribers; none of them reads the simulation. Content addons declare
abilities, auras and priorities through the public `Hekili` object and never touch `ns`. Options owns the saved profile
and hands it to the engine; the engine never names `Hekili.DB`.

## 2. The `Hekili.Engine` port

`Hekili.Engine` is a plain table made in `Hekili.lua`; the Engine files fill it. UI and Options reach the engine only
through it.

**`Engine.Output[name]`** (the display table only: names and `status`, no functions), for `name` in `Interrupts`, `Defensives`, `Cooldowns`, `Primary`, `AOE`:
- `version` (bumps each publish), `count` (records in `recs`), `recs` (the last complete set, up to 10 records).
- A record holds the recommendation (`Sim/Core.lua`'s `slot.*` writes are the list): `index`, `depth`, `display`,
  `pack`, `list`, `listName`, `action`, `actionName`, `actionID` (negative for an item), `name`, `texture`, `caption`,
  `indicator`, `focus` (the tier N from a `focus=N` entry), `item` (the item id), `keybind`, `keybindFrom`, `time`, `exact_time`,
  `delay`, `since`, `wait`, `waitSec`, `offGCD`, `interrupt`, `castStart`, `resource`, `resource_type`, `cost`, `busy`,
  `scriptType`, `script`, `hook`, plus the tables `resources`, `alts` (§7) and `belief` (empty until an annotator fills it).
- `payload`: the WeakAuras copy, set by `Integrations/WeakAuras.lua` (a passive subscriber, outside `Engine/`) only
  when WeakAuras is loaded.
- Read it in a subscriber, or between publishes. Records are reused: copy a field you need to keep.

**`Engine.Output.status`**: the engine's own record, published once (`count` is 1) when one of its fields changes:
`combat`, `combatStart` (0 out of combat), `numTargets`, `specID`, `specKey`, `specName`, `packName`. Combat, target
count, spec and pack are read here and nowhere else.

**`Engine.Subscribe(name, fn, passive, needs)`** returns true, or false when the display's 4 slots are full. `fn(name, version,
output)` runs after each publish of `name` (`name` may be `"status"`). Subscribing the same `fn` again only updates its
`passive` flag and `needs` (`needs.alts`: §7). A passive subscriber listens without asking for the display to be computed: the engine builds a display
only when a non-passive subscriber exists. WeakAuras is passive, so it never makes the engine compute a hidden display.
**`Engine.Unsubscribe(name, fn)`** is safe inside a subscriber; later subscribers are not skipped.

**`Engine.Registry`**: read-only views of what content registered, each the engine's live table, never a copy:
`Specs()`, `Abilities()`, `AbilityList()`, `ItemList()`, `Auras()`, `AuraList()`, `Potions()`, `PotionList()`, `Gear()`,
`Talents()`, `ClassFile()`. Also `Settings(specID)` (the AceOption entries a spec registered with
`RegisterSetting`, or nil) and `IsDisabled(key, strict)` (true plus a reason when the profile disables the ability).

**`Engine.Snapshot(isAuto)`** runs one update with debugging on, so the displays' reports are saved. `isAuto` is the
engine's own call and runs only when `settings.autoSnapshot` is on. It also drops a suspended build thread, so the
stale thread cannot write into the set it just published.

**`Hekili:RegisterSnapshotListener(fn)`** / **`Hekili:UnregisterSnapshotListener(fn)`** (`Engine/Snapshot.lua`): other
addons' hook on the snapshot. Once per `Engine.Snapshot`, after all its records (one per display) are stored, the
engine calls `fn(index, record, isAuto)` inside pcall, in registration order: `index` is the first record's in
`Hekili.Snapshots`, `record` that record (the rest follow it). A raising listener only adds a "failed" line. A returned
string (capped at 4000 characters) is appended to each of the snapshot's records under "## External", so it shows in
the snapshot panel whichever display is picked. One engine registry, no AceEvent message; registering the same `fn` twice is a no-op.

**`Engine.Evaluate(pack, list, action, mod, results)`** is the pack editor's preview: resets the state, then fills
`results` with the values of the entry's conditions (`mod` nil) or of one modifier (`"value"`, `"value_else"`,
`"strict_if"`). Returns `results, list, action`.

**`Engine.Configure(profile)`** and **`Engine.settings`** (`Engine/Settings.lua`). The engine reads configuration only
from `Engine.settings`. `Configure` assigns `specs`, `packs`, `toggles`, `displays`, `performance` and
`notifications` by reference: an edit inside them is live with no call. It copies the scalars `enabled`,
`autoSnapshot` and `screenshot`: a setter that writes one must call `Configure` again. Each call bumps
`settings.version`. `Options/Profile.lua` calls it at load and on every AceDB profile change (change, copy, reset).

**Private, on `ns`**, because only the engine and its tests use them:
- `ns.Output`: a separate table whose `__index` is `Engine.Output` (so `ns.Output.Primary` reads the display), holding
  the functions. `ns.Output.Begin(name)`, `Publish(name, count)`, `Wanted(name)`: the build side of publish/subscribe.
  Only `Sim/Core.lua` builds records. `Begin` returns the scratch set; `Publish` runs the annotators, swaps scratch and `recs`, and calls
  the subscribers, so a reader never sees a half-built set.
- `ns.Output.Annotate(fn)` / `Unannotate(fn)`: run `fn(name, rec, i)` over each record before the swap. Reserved for the
  belief annotator (section 7); 4 slots. Not on the port until that feature exists.
- `ns.EngineFrame`: the `HekiliEngine` frame (`Engine/Driver.lua`). Only engine files touch it: `Driver.lua` (the loop
  and `Hekili:ForceUpdate`, which the UI and the engine call), `Snapshot.lua`, `Sim/Core.lua`, `Sim/Targets.lua` and
  `Schema/Spec.lua`; `tools/check_engine_reads.sh` keeps it out of UI, Options and `Hekili.lua`.
- `ns.LoadContent`, `ns.ContentNotice` (`Engine/Content.lua`): called by `OnInitialize` and `OnEnable` only.

Output allocates nothing in `Begin`, `Publish`, `Subscribe` or `Unsubscribe` (`tests/Forever/output_spec.lua` checks
1000 rounds).

## 3. The content surface

What a content addon may use, and nothing else (`tests/boundary_spec.lua` enforces it):
- `Hekili:NewClass(token, { specs = { ... } })`, `Hekili:NewShared(...)`, `Hekili:NewRace(...)` and the `Register*`
  calls on the object they return (abilities, auras, hooks, settings, packs, ...). `NewClass` (`Engine/Schema/Spec.lua`)
  returns the class's kit, or nil on another class (the pack then returns). The kit holds every ability, aura and talent;
  each entry of `specs` is one talent tree's spec: `{ key, name, tree (1-3), icon, role, ranged, package, unsupported }`
  (`package`: the default priority's name; `unsupported`: no priorities on Forever, its displays off and its page a
  notice). A spec reads the kit through its metatable and keeps its own settings and options. Ids are the core's:
  `100000 + client class id x 10 + slot` (`ns.TreeSpecID`, `Engine/Schema/Trees.lua`; slot 0 the kit, 1..n the specs
  in `specs` order: Warrior Arms 100011). `RegisterTalents` entries are `{ tree, spell, max rank }`, the tree from the
  DB2 (`Talent.TabID`, ordered by `TalentTab.OrderIndex`; 0 when unknown, counted nowhere). `kit:RegisterSetting(key,
  value, option, ...)` registers the setting on every supported spec, or only on the specs whose keys follow `option`
  (`"enhancement"`; an unknown key errors). An option may carry `sim`, the setting's default under
  the harness (`Hekili.Engine.scenario == "sim"`; nil in game): `Engine.SettingDefault(entry)` fills an unset
  profile value at the spec load, the options build and `option.get`, and `sim` never reaches AceConfig.
  A choice setting is an AceConfig `select` (`values`: candidate key -> display name, `sorting`: their order): its
  default and `sim` must be candidates (else RegisterSetting errors), the spec's page shows it as a dropdown, `/hekili
  set spec <key> <candidate>` sets it, and a priority reads it as `settings.<key>='<candidate>'` (a quoted string
  passes through the script language as is: `Engine/Sim/Scripts.lua` never extends a resource name inside quotes).
- `Hekili.State` (the simulation's `state`) and `Hekili.Class` (the registry the class file fills).
- `Hekili.Client`: the game client as an addon may read it, the same table as `ns.Facade`. Content never names a WoW
  global (`tools/check_api_reads.sh`).

The belief's plain reads, names in every content function's environment: `knownRank`, `stat`, `swingBase`, `healthMax`.
Two environments have them:
- the sim's `state` (`Engine/Sim/State.lua`): `knownRank`, `swingBase`, `healthMax` are plain functions; `stat` is the
  sim's stat table (`stat.crit`) and also callable (`stat(name, arg)`, the belief's out-of-combat stat cache);
- the belief's `now` context (`Game/State/Families/Now.lua`, `NAMES`): the same four names, where `stat` is only the
  plain function `stat(name, arg)`. A `now` handler cannot read `stat.crit`.

`RegisterAbility{ passive = true, id = <number> }` (`Engine/Schema/Spec.lua`) is a spell the spellbook knows and the
player never casts. The belief tracks its known rank (`knownRank` reads it); the sim never sees it.

**Target creature type.** `target.creature_type` (`Engine/Sim/State.lua`'s target table, cached per reset) is the
target's creature type as a key: UnitCreatureType's second return, CreatureType.db2's ID (the same on every client
language), as its English name in snake case (`"undead"`, `"demon"`, `"beast"`, `"not_specified"`, ...), and
`"unknown"` with no target, a secret answer (the raw docs flag it `SecretWhenUnitIdentityRestricted`; the facade's
passthrough row is probed plain in combat) or an unlisted ID. `target.is_undead` and `target.is_demon` read it.
An ability may declare `usable_on = { "undead", "demon" }`: `state:IsUsable` refuses it on a target of another known
type ("target's creature type not in usable_on") and never on `"unknown"`, so a hidden type never blocks a line. The
harness sets the type on a world's mob (`entities.new{ creatureType }`, a content `WORLD.creatureType`, a replay's
request `mobType` through `tests/Forever/helpers/wowsims.lua` `creatureType`), and the client fake answers it
(`ctl.creature[unit]`, default `"beast"`).

**Pets.** `RegisterPets` names the pets (`{ id, spell, duration, cap }`; a `cap` makes a counted guardian). Both
layers have the verbs `summonPet(key, duration)` and `dismissPet(key)`: the sim's (`Engine/Sim/State.lua`, Hekili's)
in `handler`, the belief's (`Game/State/Families/Now.lua`) in `now`, where a guardian's summon adds an expiring slot
and its dismissal frees them, and any other key models the pet unit up or down until the first observation
(`Families/Pets.lua`; UNIT_PET and poll 13 read `UnitExists`, `UnitIsDead` and `UnitPower` of `"pet"`, plain). The sim
answers `pet.up`/`pet.alive` through the facade's `UnitExists`/`UnitIsDead("pet")`, `pet.<key>.count` from the
belief's guardians, and `pet.mana` (`rage`, `focus`, `energy`) as `UnitPower("pet", type)`: the client's plain answer,
or the belief's last plain read (`VS.PetPower`) when secret (unprobed with a pet out; plain 0 with none, probe W PR12).
The translator reads a wowsims resource value on the Pet (`currentMana`) as `pet.mana`.

**Bag counts and stats.** `C_Item.GetItemCount` is a plain passthrough (W PR13): a reagent a kit counts (a
`RegisterStateExpr` over `Hekili.Client.C_Item.GetItemCount(id)`) is read live, and the sim does not predict its
spends. `UnitStat` and the other stat reads are the belief's out-of-combat cache (`stat(name, arg)`, `VS.Stat`).

**In the harness** (central fix 27), a content declares them in `WORLD` (or `entities.new`): `bags = { [itemID] =
count }`, `pet = { pt, max, power, regen, tick, up }` and `stats = { [index] = value }`. The world keeps the truth: a
press's `reagent = { itemID, n }` is checked like a cost (refused `"reagent"`) and paid when its cast lands, the press
effects `item = { itemID, n }` and `pet = "summon" | "dismiss"` (and `W.item`, `W.summonPet`, `W.dismissPet`,
`W.petGain`) change it, and the pet regenerates `regen` a second in `tick`-second steps while up. The observer answers
them plain (`@itemCount`, `@pet` with UNIT_PET, `@petPower`, `@stats` at login), so `C_Item.GetItemCount`,
`UnitExists`/`UnitPower("pet")` and `UnitStat` read the world. The pet's events carry its power as `petPower`: an
event's `power` is always ours (central fix 31). A replay world starts from the content's values; its pet's power then
follows the log's pet power lines (their after-values, no modelled regen; fix 31), and its bags read nothing from the
log.

**Percent-of-base costs.** A `spend` between 0 and 1 is a fraction of its pool's base power (the resource meta's
`base`, or the belief's learned one; without either, of the maximum, as Hekili), floored, in both layers: the sim's
`ns.SpendPoints` (`Engine/Sim/State.lua`, every site that prices a spend) and the belief's `I.BaseCostOf`
(`Game/State/Families/Casts.lua`). Any other cost is points. An ability declaring `spendBase = true` has its `spend`,
scalar or function, read as a fraction at any magnitude (a percent-of-base cost a stacking aura raises past 100% of
base), priced `floor(c x base)` the same way; the base learning from out-of-combat cost reads counts its reads too.

An ability's `known` must depend only on the spellbook, talents and gear, never on buffs or time, because the engine
caches it for one prediction (`state:IsKnown`, wiped by `Hekili:ResetSpellCaches`). `state:IsDisabled` caches its
prefix the same way: the ability and item options, the toggle assignment, `state.filter`, boss and the target counts
are fixed within one prediction, wiped every slot and by every option setter; `ability.disabled`, holds and the DoT cap
are read live.

**A proc aura's internal cooldown.** `RegisterAura{ icd = <seconds> }` declares that the aura can be applied at most
once per `icd` seconds (its proc's ICD), measured from its last application; `icdSpell = <id>` names the spell an
outside source names the ICD by (the proc trigger passive, as wowsims does; `tools/wowsims/apl.lua` rule 9). The sim
answers `buff.<key>.icd_remains` (`max(applied, last_application) + icd - query_time`, never below 0) and
`buff.<key>.icd_ready` (`icd_remains == 0`) from the aura's existing state entry, so it advances with the sim's clock
and allocates nothing; an aura without `icd`, or never applied, reads ready (an unknown ICD never blocks). The
application comes from the aura belief (`Game/State/Families/Auras.lua`), which reads `icd` at build: a plain read
of the gain starts it, and for an `icd` aura only, a read whose expiry moved past the believed one by more than
`I.AURA_REFRESH` (0.5 s) is a re-application, so a re-proc restarts it (any other aura keeps its applied time, which
times its tick phase). An `icd` aura already up in the unit's first clean walk (a reload, a login) has an unknown gain,
so its ICD reads ready (its applied time is put one ICD back, a sentinel) until a gain is seen. The sim's `applyBuff`
starts it too, and removing a down aura keeps it (`tests/Forever/aura_icd_spec.lua`, `tests/Game/State/auras_spec.lua`).

**Addons and load order.** `Hekili` (core, the only addon the client loads by itself), `Hekili_Shared`
(`## Dependencies: Hekili`, `## LoadOnDemand: 1`; Shared auras, consumables, items, and the race packs), then one pack
per class: `Hekili_Warrior`, `Hekili_Druid`, `Hekili_Rogue`, `Hekili_Paladin`, `Hekili_Shaman`, `Hekili_Hunter`, `Hekili_Mage`, `Hekili_Priest`, `Hekili_Warlock` (`## Dependencies: Hekili, Hekili_Shared`,
`## LoadOnDemand: 1`). `tests/helpers/addons.lua` lists them in this order. `ns.LoadContent` runs once, in
`OnInitialize`, before `InitializeProfile`, so the profile's defaults see the class's spec and packs. It loads
`Hekili_Shared` explicitly first (every class, with or without a pack, gets the shared and race content), then reads
the player's class token, finds `Hekili_<Class>` and loads it if its `## X-Hekili-ContentAPI` equals
`CONTENT_API` in `Engine/Content.lua`. Nothing relies on the client loading a dependency for `LoadAddOn`; the headless
fake refuses a pack whose dependency is not loaded yet. A failed shared load (then no pack is tried), an unreadable
class token, a missing pack, a mismatch or a failed pack load keeps one notice, which `ns.ContentNotice` shows at
`OnEnable`; the core then runs with no class spec. Nothing retries: a notice asks for `/reload` or an install.

**What bumps what.** A class release bumps `## Version` in its pack's TOC. `CONTENT_API` and every content TOC's
`## X-Hekili-ContentAPI` change together, only when the content surface changes: the Register* API, `Hekili.Client`,
or the environment names above. `tests/Forever/content_spec.lua` checks the TOCs and the constant agree.

**Active spec.** The client reports one pseudo-spec per class, so the core picks the spec (`ns.PickSpec`) from the
talent tree with the most points: the spec the character activated for that tree
(`profile.specChoice["Name-Realm"] = { [tree] = key, last = tree }`), else the tree's first spec; on no points or a
tie, the last dominant tree seen; with none seen, the first supported spec. A respec or dual-spec swap that moves the
dominant tree therefore switches the spec, and two builds of one tree share its choice. The choice is written only by a
spec page's "Activate <Spec>" button or `/hekili spec <name>`, for the current dominant tree (a pre-table scalar
choice moves onto it once). On a class's first login after the update a one-time migration (`ns.MigrateTrees`, marked in
`profile.specMigrated[<TOKEN>]`) merges the legacy pseudo-spec profile (the client's id, now read for nothing else:
Rogue 1488 and Warrior 1491 read in game; Druid 1483, Hunter 1484, Paladin 1486, Shaman 1489 assumed) into every
supported spec, value by
value; a legacy custom priority stays the choice of the active spec, or of the first supported spec when the active one
is unsupported, and custom priorities bound to the legacy id are rebound to it. Exports carry the spec as a share key
`"<TOKEN>:<key>"` (`"WARRIOR:fury"`), which the importer resolves to this session's id (another class's key is kept
as the string until that class logs in).

## 4. `Hekili.Virtual`

`Hekili.Virtual = { State, Events }` (`Game/State/Adapter.lua`) is the probe and debug handle, for example
`/run print(Hekili.Virtual.State.Snapshot())` and ForeverProbe's `Calib.lua`. It is not for content, which has the
facade and the environment names. The boundary scan rejects `Hekili.Virtual` and `VirtualState` in a content file.

## 5. The checks

- `tests/boundary_spec.lua`:
  - strict scan: `Game/`, `Engine/Schema/` and `tests/Game/harness/` (its fixtures excluded) name no ability, aura
    or talent key, no spell ID, and no class or form name that the content registers; the keys are extracted from the
    content at test time;
  - Sim baseline: each `Engine/Sim/` file may hold no more of each content name than `tests/boundary_baseline.lua`
    (a per-token ceiling; regenerate with `tools/boundary_baseline.lua` only to remove a leak);
  - content allowlist: files of the content addons may use only `Hekili:NewClass/NewShared/NewRace` and
    `Hekili.State/Class/Client`, and contain none of `ns.`, `ns = ...`, `VirtualState`, `Hekili.Virtual`,
    `Hekili.Engine`. Pack share strings are data and skipped.
- `tools/check_engine_reads.sh` (in `make api-check`), both directions: the engine files (`Sim/{Core,State,Targets,
  Scripts}`, `Output`, `Registry`, `Snapshot`, `Driver`) name no `HekiliDisplay*`, `ns.UI.` or
  `DisplayPool`, and nothing in `Engine/` names `Hekili.DB` or `.profile` (exempt: `Settings.lua`, comments). UI,
  Options, `Integrations/` and `Hekili.lua` read no `state.`, `class.`, `Hekili.State/Class`, `ns.queue`, `VirtualStateInternal` or
  `HekiliEngine`, `ns.EngineFrame`. The exemptions are anchored to the whole line: `Hekili.lua`'s two definitions, DevTools' generated-text
  line, and UI.lua's own `Hekili.DisplayPool`.
- `tools/check_api_reads.sh`: no file of any addon TOC reads a game API from `tools/api_inventory.txt` except through
  `ns.Facade`. It uses luacheck for bare reads and grep for `_G.Name`; `git diff` guards `api_inventory.txt`.
- Headless gates: `make test` (everything except the tagged gates), `make test-fast` (skips `#slow`), `make test-loop`
  (the 20-fight Arms loop and its `Arms solo:` line), `make test-party`, `make test-druid` (about 190 s), `make test-rogue` (the
  20-fight Rogue gates, about 320 s), `make test-paladin` (the 20-fight Paladin gates, about 150 s), `make test-shaman` (the 20-fight
  Enhancement gate, about 60 s), `make test-hunter` (the 20-fight Hunter gates), `make test-wowsims` (the `#wowsims`
  replay and leveling gates alone; `make check` runs them in its `#slow` tier), `make gate` (`make check` then all
  seven loop targets in parallel, one process each: the merge gate in about a third of the serial time), `make bench`
  (ms and bytes per Update and per UNIT_COMBAT; reported, not gated). `make check`
  runs lint, format, type check, `make test` (one process per spec file, in parallel), syntax, `api-check`,
  `packs-check` (`make wowsims-packs` and `make packs` leave `src/` unchanged) and `tools-test`.

## 6. The pack pipeline

Default priorities are written as SimC text: `src/Hekili_<Class>/APLs/<Pack>.simc` (leading `#` lines are the
description) and the manifest `src/Hekili_<Class>/APLs/packs.lua` (`{ class = "<TOKEN>", packs = { ... } in block
order, specs = { [<Pack>] = <spec key> } }`; each pack's payload gets `spec = "<TOKEN>:<key>"`, a pack without a spec
key errors). The TOC lists
neither, so WoW never loads them, and `.pkgmeta` leaves them out of the zip. `make packs` runs
`.lua/bin/lua tools/make_pack.lua write <class>` (`lua5.1` without `.lua/`) for each manifest. It parses the text, serializes and encodes it as the share
string `RegisterPack` takes, and rewrites the generated `RegisterPack` blocks in `src/Hekili_<Class>/<Class>.lua`.
`lua5.1 tools/make_pack.lua decode <string>` prints a share string back as SimC. The pack version is the class's date
times 1000 plus a checksum of the text, so any text change reloads a saved profile. `make packs` on a clean tree is a
no-op (`tests/Forever/make_pack_spec.lua`), and encode then decode returns the normalized text. `make check`'s
`packs-check` runs it and fails on any diff in `src/`.

**The wowsims.com packs.** Every default priority is generated (the user's rule: no hand-built lists): one
`<Spec> (wowsims.com)` pack per supported spec, wowsims/forever's own APL translated to the fork's keys. A recipe
`tools/wowsims/specs/<class>_<spec>.lua` names the wowsims build (race, gear, talents, options; `tank` and
`healingModel` for a tank) and the translation data (`map`, `auras`, `focus`, `requires`, `exclusive`,
`executePhase`, `leveling`); `make wowsims-export SPEC=<spec>` writes its request and wowsims's debug log under
`tests/Forever/wowsims/`, both checked in; `make wowsims-packs` translates the request's APL
(`tools/wowsims/apl.lua`, `M.translate`, 16 rules in its header: entries, omissions, ON/OFF switches as settings,
keys, the leveling guard, constants, ICDs, exclusive refreshes, distance, unresolved reads, automatic cooldowns from
the log, `strictSequence`, maintenance debuffs, option-selected casts) into `src/Hekili_<Class>/APLs/<Pack>.simc`, its header listing the
switches its lines read and every omitted entry; `make packs` then writes the RegisterPack blocks as for any pack. Each class file registers
its switches (`spec:RegisterSetting("wowsims_<name>", ...)`, per spec) and names the pack as its spec's `package`.
The author's guide is `docs/dev/wowsims-packs.md`; the gates and numbers are in `docs/dev/layout.md`.

**Retired packs.** `kit:RetirePacks({ "<Old>", ... })` (`Engine/Schema/Spec.lua`, into `class.retiredPacks`) names
built-in packs a class no longer ships. At `Hekili:RestoreDefaults` a saved built-in of that name leaves the profile
(a user's own pack of the name stays), every spec that chose it falls back to its `NewClass` default
(`ns.DefaultPackage`), and the login notice says it was retired (`tests/Forever/retired_packs_spec.lua`).

**Lists.** A pack's lists are `default` (the `actions=` lines) and any named list; `precombat` is optional. Without
one (every wowsims list with no prepull actions, and make_pack writes none), `Hekili:GetNextPrediction` starts the
default list from the forecast window `state.delayMax` as it would after an empty precombat pass
(`tests/Forever/apl_entry_spec.lua`).

**Time to die.** Target health is secret on Forever, so `Engine/Sim/Targets.lua`'s tracker is not fed and every time
to die (`fight_remains`, `target.time_to_die`, `time_to_pct_N`, `longest_ttd`, ...) answers "unknown": `FOREVER`, 3600 s,
a fight that never ends soon, a grey (trivial) target's too (wowsims's `remainingTime` has no trivial case), and
`GetNumTTDsAfter` counts every enemy as after any time. The tracker's 0.5 s ticker is not started. A priority may read them without a load warning (`Game/State/AplWarnings.lua` warns only
on target health); wowsims's `remainingTime` maps to `fight_remains` with that deviation.

**Player health.** The same rule for the player's own health (`health.pct`, `health.current`, `health.deficit`): the
plain value whenever the client answers one (out of combat), full while it keeps the answer secret
(`Game/State/Families/Player.lua`), never a stale read from before the pull. A defensive line (`health.pct<50`) never
fires on an unknown and a `health.pct>50` gate always passes; no load warning. wowsims's `currentHealthPercent` maps to
`health.pct` with that deviation.

**APL line options.** `make_pack.lua` and the in-game importer accept these on a line before `if=` (in the tool,
an unknown option or a non-numeric value errors; `unparse` writes them in this order): `name=<list>` (for
`call_action_list`/`run_action_list`), `use_off_gcd=1` (recommendable off the GCD) and `focus=N` (a priority tier, 1
highest; the record carries `focus = N` and the timeline shows it in the now circle ahead of time, below). The tool
refuses 0, negatives and non-integers; the in-game importer drops `focus=0` (off) and warns on and drops anything that
is not a whole number; the priority editor's Focus Tier slider sets it (0 is off). The tier is per line, not per
ability. The Druid pack flags Feral's `rip` (tier 1); the Warrior pack's Fury tiers Heroic Strike and Cleave 1 near the
rage cap and 2 otherwise.

**Pre-pull guards.** Upstream Hekili walks `precombat` before `default` on every refresh and skips its non-essential
entries once `time > 0`; out of combat it is a plain priority. The fork keeps it so (owner ruling 2026-10-21: "a guard
against recasting"; the player decides when to press): the engine holds no schedule and no per-episode state, and a
pre-pull line shows whenever its purpose is unmet and its ability is ready (a guard that releases inside the
forecast window shows the line ahead with its wait, as any line does). The purpose is written into the line: the
wowsims translator (`tools/wowsims/apl.lua` rule 1) keeps wowsims's `doAtValue` order and gives each pre-pull cast
one guard derived from what its ability's handler does (run once in the kit's stub state with the verbs recorded):
`!buff.<key>.up` or `!debuff.<key>.up` for an aura of its own key (none when that aura is no longer than the
cooldown, which already hides it: Bloodrage), `!totem.<element>.up` for a totem, and none otherwise (Charge and
Intercept: their own usability and cooldown). Two lines whose handlers remove each other's aura (seals) form a group:
its first line waits for no member to be up
(`!buff.seal_of_command.up&(!action.seal_of_the_crusader.known|!buff.seal_of_the_crusader.up)`), later ones for their
own, so the first is cast only when neither is up and the later one replaces it. `prepull_at` (the retired
once-per-episode schedule) is gone: `make_pack` refuses it and the in-game importer stores it inert.

**In precombat.** Being in precombat is a property of the walk, not of a list's name: `GetPredictionFromAPL` sets
`inPrecombat` while it walks the precombat list and every list that list calls or runs (at any depth; saved and
restored around each list, so the caller's value returns after), and the in-combat filter reads it. A list the precombat list calls (wowsims's "Pre-pull: Move" becomes `pre_pull_move`) is skipped in combat
like precombat itself; the same list reached from `default` is not (`tests/Forever/precombat_calls_spec.lua`).
Upstream Hekili checks the name alone, so a called list leaked into combat.

## 7. Display styles

A display style draws one display's recommendations. Each display names one in `displays[id].style` (nil or unknown:
classic; unknown also gives one notice per display and name). Styles live in `ns.UI.Styles` (`UI/Styles.lua`); the
built-in ones are classic (`UI/Styles/Classic.lua`, Hekili's icon row) and timeline (`UI/Styles/Timeline.lua`: now and
next cells and a time lane; below). Each display binds its own style, so Primary can be timeline while Cooldowns stays
classic; choosing another in the options rebuilds the UI, which calls the old style's `Clear` before the new one's
`Build`.

**The public door.** Another addon (a UI pack, `## Dependencies: Hekili`) registers a style with
`Hekili:RegisterDisplayStyle(name, impl)`, the same call the built-in styles use. `impl.api` must equal
`Hekili.DisplayStyleAPI` (now `1`); it is bumped only when the interface or the record fields below change, and a
mismatch is refused with one notice. A name that is a core display field or option tab (`style`, `enabled`, `numIcons`,
`main`, `queue`, `visibility`, ...) is refused the same way; the call returns `false` when refused, `true` otherwise. A
dependent addon registers after Hekili's `OnInitialize`: its `defaults` are then registered with AceDB again so every
display gets `displays[id].<name>`, the options tabs are rebuilt on the next open, and the displays are rebuilt, so a
display whose profile already names the style binds it.

| Member | Called | Does |
|---|---|---|
| `api` | registration | the interface version it was written for |
| `label` | dropdown | the name the style dropdown shows; the options group itself is always titled Style |
| `defaults` | registration | optional; the template of `displays[id].<name>` |
| `needs` | subscribing | optional; `{ alts = true }` asks the engine for `recs[1..2].alts` (below), which costs extra simulation passes; read from the bound style table on every subscribe, which the display's alpha check repeats about every 0.5 s while it is shown, so a change applies within about 0.5 s |
| `NeedsFor(id, conf)` | subscribing | optional; when present core asks it instead of reading `needs`, for that display's needs table (return preallocated tables: it runs on every alpha check); Timeline answers `needs` while `alts.enabled`, else no needs |
| `Build(d, conf)` | every `BuildUI` | creates or reuses (`d.styleFrames[name]`) its frames on `d`; returns the button list (may be empty) |
| `Draw(d, conf, out, status)` | on a drawing frame: a publish or the 0.25 s pulse | draws `out` |
| `Tick(d, conf, out, now, elapsed)` | every frame, before `Draw` | timers, flashes, range |
| `OnGameEvent(d, conf, event, ...)` | every display event, after core's alpha and keybinding handling | |
| `Clear(d)` | style switch, deactivate, and every unsubscribe (the display's alpha drops to 0: combat-only visibility, mounting, vehicles, barber shop, pet battles) | hides everything it shows; `Build` is not run again after an unsubscribe, so `Draw` must re-show what `Clear` hid on the next publish (as Timeline's `reveal()` does) |
| `Perimeter(d)` | config mode | left, right, top, bottom frames for the mover backdrop, or nil |
| `UpdateKeybindings(d)` | keybinding changes | |
| `Options(id, conf)` | building the options | the style's tabs, new tables each call; they land in one group keyed by `name`, so their options resolve to `displays[id].<name>.<option>` (keys flat and unique within the style) |

**Timeline zones.** On each publish the press record is record 1. With `focusEnabled` (default on), a record is
flagged when `focus` is a tier (N >= 1), and the focus record is, among the flagged records due within `focusHorizon`
seconds (default 10, never past `horizon`; record 1 always counts), the lowest tier number and, within a tier, the
soonest (`FOCUS_BEST_TIER` in Timeline.lua). One focus per display, and it alone takes the now circle: record 1 with
the press look, its countdown, extend sweep and the `focusPendingColor` ring while it still waits (the GCD, a cast,
its cooldown) and the gold `focusColor` ring (or `focusReadyStyle`'s glow or full-colour Gold Ring) from the frame its
`exact_time` arrives (within 0.05 s, with no publish needed), or a later record with a countdown, no keybind and the
`focusPendingColor` ring; with no focus record the now circle is empty. The next box draws the first record other than
the focus record, and the lane every other record at its time: a flagged record that is not the focus keeps its place
and look. `nowFallback = "press"` keeps the earlier rule: record 1 never counts as focus, a focus record (by the same
tier rule) takes the now circle and record 1 the next box, else now, next and lane draw records 1, 2 and 3... Every
"key to press" affordance (keybind, glow, flash, range, cast highlight, targets, alternatives, pause overlay, extend
sweep) sits on the cell drawing record 1. With `oocPinned`
(default on) and out of combat, lane positions, countdowns and the focus test use `rec.time - recs[1].time` instead
of the clock, so the display holds still between updates; the lane never draws left of its first mark. With `oocTimers` off
(the default) and out of combat, the now and next cells show no cooldown sweep and no zone shows an ETA.

**Shared option builders.** `Hekili.StyleOptions` (`Options/StyleOptions.lua`) builds classic's tabs for any style's
subtable: `keybindings`, `captions`, `border`, `range`, `glow`, `flash`, `delays`, `targets`, `indicators` as
`(styleKey, zones, order, id, conf)`, `icon(zone, order, id)` and `defaults(groups, zones)` for the matching
`defaults`; the engine's range, flash and keybinding reads take the bound style's group (`Hekili.Engine.StyleGroup`),
classic's when the style has none. Later zones get their own prefixed blocks (`nextFont`); only classic marks its
zones `legacy = true`, which keeps its queue's `queued*` keybinding fields behind `separateQueueStyle`.

**Config.** Every style owns one subtable, `displays[id].<name>`, filled from its `defaults`; classic's is
`displays[id].classic` too (`Hekili:RunOneTimeFixes` moves an older profile's flat classic fields under it on every
load). Core fields (`numIcons`, `enabled`, `style`, position, `visibility`) stay on the display table. No style reads
another style's subtable. The engine and the resolve read the shared groups (range, flash, keybindings) through
`Hekili.Engine.StyleGroup`, the bound style's group or classic's; only the classic migration, a few classic options
and the display reset in `ChatCommands.lua` name `classic` directly.

**What a style may read.** `conf` is the whole display table: core fields and its own subtable `conf[name]`.
`d.styleState` is per-display scratch shared by every style the display has bound; state of the style's own goes on
`d.styleFrames[name]`. `out` is
`Hekili.Engine.Output[id]`: `out.count`, `out.version` and `out.recs[1..count]`, each record with `actionName`,
`actionID`, `texture`, `caption`, `indicator`, `focus`, `keybind`, `offGCD`, `time`, `exact_time`, `delay`, `since`, `wait`,
`resource_type`, `resources`, `cost` (the amount of `resource_type` the pick spends; a fractional spend is multiplied by the resource's maximum),
`busy` (seconds the pick keeps the player busy: its GCD, or its cast when longer), `script`, `list`, `action`, `pack`,
and `alts` (`alts.n` entries of
`actionName`, `actionID`, `texture`, `action`, `list`, `bound` = `"lo"` or `"hi"`: the pick with the gating resource
at the belief's low or high bound, when it differs from the record's own, sorted by APL entry; filled for records 1
and 2 only while a subscriber's style declares `needs.alts`, otherwise `n = 0`); `status` is `Output.status`. `d.resolved[i]` (`UI/Resolve.lua`:
range, usable, desaturation, delay, targets, glow per record) is the place to read those instead of asking the game
again. `ns.UI.Resolve` runs only on drawing frames, before `Tick` and `Draw`, so a `Tick` that reads `d.resolved` sees
values up to 0.25 s old. A style never reads `state.*`, `class.*`, `Hekili.State`, `Hekili.Class` or
`HekiliEngine`: `tools/check_engine_reads.sh` enforces it inside Hekili, and an external style must keep it by
convention. Draw and Tick allocate nothing after the first publish, and `Clear` must leave none of the style's
frames shown.

**Steady icons (experimental, off by default).** With the active specialization's `steadyIcons` on (its Performance
tab), `Output.Publish` holds a slot for one publish when its shown icon and the new one are both countdowns (due more
than 0.05 s out) with different names and the raw set did not already have the new one last publish: the shown
record table moves into the new set and the new one into the old, so the hold costs no copy and no allocation, and
`out.held[i]` says which slots are held (the snapshot marks them `(held)`). A ready icon on either side and the first
publish after our own cast start or success, channel end or swing queue change (`Output.Acted`, from
`Game/State/Sources/Casts.lua`) show at once, so what is pressable and when never changes. Core reads the setting once
per update into `Output.steady`; styles see only the held records and need nothing. Known limits: a held cell keeps
the previous publish's `time` (one poll off in Timeline's out-of-combat pinned mode), and for one publish the same icon
can show in two slots when a held slot's icon is the next slot's new icon.

## 8. Follow-ups

- **Belief annotator** (needs its own short design): `Game/Annotate.lua`, registered with `ns.Output.Annotate`. Per
  record: the gating resource's est/lo/hi at the record's time, the basis of the usability read (observed, pinned or
  modelled, plus the event), the band width relative to cost as a confidence, the gating aura or cooldown and its basis,
  and the GCD kind. It fills `rec.belief`, which exists and is cleared by `Begin`.
- **In-game checks owed after the merge** (the user): a full client restart; the four `mklink` lines in `layout.md`;
  that `LoadAddOn` from inside Hekili's `ADDON_LOADED` loads `Hekili_Shared` then the class pack (the spike did not
  test this path; see `docs/research/2026-10-17-content-addon-spike.md`);
  icons, minimap and compartment entries, the pack editor, `/hekili snapshot`, combat alpha, a spec swap, the minimap
  position surviving `/reload`, and a third class (neither Warrior nor Druid) seeing the "no Forever pack" notice.
- **Time to die from the TargetHealth belief** (a follow-up design): once the belief has M (the damage per full
  health) and a modelled sample, the target's time to die is its health fraction x M / the recent WOUND damage rate
  (a ring of the last ~10 s of our and the group's damage on it), "unknown" before that; Targets.lua's `FEED` would read
  that belief instead of the facade's health, and `fight_remains` the longest over tracked enemies.
- **ForeverProbe**: `Hekili.VirtualState` became `Hekili.Virtual.State`; update its calls.
