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

 Content addons (Hekili_Shared, Hekili_<Class>) call the public Hekili object: Hekili:NewSpecialization,
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
- `Hekili:NewSpecialization(id, ...)`, `Hekili:NewShared(...)`, `Hekili:NewRace(...)` and the `Register*` calls on the
  object they return (abilities, auras, hooks, settings, packs, ...).
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

An ability's `known` must depend only on the spellbook, talents and gear, never on buffs or time, because the engine
caches it for one prediction (`state:IsKnown`, wiped by `Hekili:ResetSpellCaches`). `state:IsDisabled` caches its
prefix the same way: the ability and item options, the toggle assignment, `state.filter`, boss and the target counts
are fixed within one prediction, wiped every slot and by every option setter; `ability.disabled`, holds and the DoT cap
are read live.

**Addons and load order.** `Hekili` (core, the only addon the client loads by itself), `Hekili_Shared`
(`## Dependencies: Hekili`, `## LoadOnDemand: 1`; Shared auras, consumables, items, and the race packs), then one pack
per class: `Hekili_Warrior`, `Hekili_Druid`, `Hekili_Rogue`, `Hekili_Paladin`, `Hekili_Shaman` (`## Dependencies: Hekili, Hekili_Shared`,
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
  - content allowlist: files of the three content addons may use only `Hekili:NewSpecialization/NewShared/NewRace` and
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
  Enhancement gate, about 60 s), `make bench`
  (ms and bytes per Update and per UNIT_COMBAT; reported, not gated). `make check`
  runs lint, format, type check, `make test` (one process per spec file, in parallel), syntax, `api-check` and
  `packs-check`.

## 6. The pack pipeline

Default priorities are written as SimC text: `src/Hekili_<Class>/APLs/<Pack>.simc` (leading `#` lines are the
description) and the manifest `src/Hekili_<Class>/APLs/packs.lua` (`spec`, `packs` in block order). The TOC lists
neither, so WoW never loads them, and `.pkgmeta` leaves them out of the zip. `make packs` runs
`.lua/bin/lua tools/make_pack.lua write <class>` (`lua5.1` without `.lua/`) for each manifest. It parses the text, serializes and encodes it as the share
string `RegisterPack` takes, and rewrites the generated `RegisterPack` blocks in `src/Hekili_<Class>/<Class>.lua`.
`lua5.1 tools/make_pack.lua decode <string>` prints a share string back as SimC. The pack version is the class's date
times 1000 plus a checksum of the text, so any text change reloads a saved profile. `make packs` on a clean tree is a
no-op (`tests/Forever/make_pack_spec.lua`), and encode then decode returns the normalized text. `make packs` is not
part of `make check`.

**APL line options.** `make_pack.lua` and the in-game importer accept these on a line before `if=` (in the tool,
an unknown option or a non-numeric value errors; `unparse` writes them in this order): `name=<list>` (for
`call_action_list`/`run_action_list`), `use_off_gcd=1` (recommendable off the GCD) and `focus=N` (a priority tier, 1
highest; the record carries `focus = N` and the timeline shows it in the now circle ahead of time, below). The tool
refuses 0, negatives and non-integers; the in-game importer drops `focus=0` (off) and warns on and drops anything that
is not a whole number; the priority editor's Focus Tier slider sets it (0 is off). The tier is per line, not per
ability. The Druid pack flags Feral's `rip` (tier 1); the Warrior pack's Fury tiers Heroic Strike and Cleave 1 near the
rage cap and 2 otherwise.

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
flagged when `focus` is a tier (N >= 1), and the focus record is record 1 if flagged (any tier), else, among the
flagged records 2.. due within `focusHorizon` seconds (default 10, never past `horizon`), the lowest tier number and,
within a tier, the soonest. It takes the now circle: record 1 with the press look, its countdown, extend sweep and
the `focusPendingColor` ring while it still waits (the GCD, a cast, its cooldown) and the gold `focusColor` ring (or
`focusReadyStyle`'s glow or full-colour Gold Ring) from the frame its `exact_time` arrives (within 0.05 s, with no
publish needed), or a later record with a countdown, no keybind and the `focusPendingColor` ring;
with no focus record the now circle is empty. The next box draws the first record that is neither the focus record nor
flagged (flagged records never sit there), and the lane every other record at its time, flagged ones included.
`nowFallback = "press"` keeps the earlier rule: record 1 never counts as focus, a focus record (by the same tier rule) takes the now circle and
record 1 the next box, else now, next and lane draw records 1, 2 and 3... Every "key to press" affordance (keybind,
glow, flash, range, cast highlight, targets, alternatives, pause overlay, extend sweep) sits on the cell drawing
record 1. With `oocPinned`
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
- **ForeverProbe**: `Hekili.VirtualState` became `Hekili.Virtual.State`; update its calls.
