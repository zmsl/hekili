<!--
Purpose: What a class addon is, load order, the content API version, the core and pack boundary.
Type: Explanation
Audience: Lua developers
Prerequisites: Lua 5.1.
-->
A class pack is the addon that teaches Hekili Forever one class: `Hekili_Druid` for the Druid, `Hekili_Warrior` for the Warrior, and so on. It declares the class's abilities, auras, talents, resources and settings, and ships its default priorities. The core addon, `Hekili`, is a generic engine that names no class, spell or aura; everything it knows about a class comes from the pack, through the registration API. This page explains what a pack holds, how and when it loads, and the boundary between the pack and the core.

| Class pack | |
|---|---|
| Folder | `src/Hekili_<Class>/` |
| Files | One class file (`<Class>.lua`), `Locales/`, the TOC; priority sources under `APLs/` (not shipped) |
| Loaded by | The core, on demand, after `Hekili_Shared` |
| Depends on | `Hekili`, `Hekili_Shared` |
| Version check | `## X-Hekili-ContentAPI` in the TOC must equal the core's `CONTENT_API` |
| Reaches the core through | `Hekili:NewClass`, the `Register*` calls, `Hekili.State`, `Hekili.Class`, `Hekili.Client`, `Hekili:GetLocale` |

## What a class addon is

Each class has one addon. Its class file builds the class's **kit**: every ability, aura and talent of the class, shared by all its specializations. The kit also lists the class's specializations (specs), each tied to one talent tree, with its own settings and its default priority. A spec reads the kit's abilities and auras and keeps its own settings and options.

A pack holds:

- `<Class>.lua`, the class file: the kit, its specs, resources, talents, auras, abilities, settings and the generated `RegisterPack` blocks that carry the default priorities. [Pack class file anatomy](Pack-Class-File-Anatomy) walks through one.
- `Locales/`, the pack's string table: every text a player sees is written as `L["English text"]`, read through `Hekili:GetLocale("Hekili_<Class>")`.
- `Hekili_<Class>.toc`, which lists the locale files before the class file.
- `APLs/`, the priority sources (`<Pack>.simc`) and the pack manifest (`packs.lua`). The TOC does not list them, so the game never loads them, and the packager leaves them out of the release. `make packs` turns them into the `RegisterPack` blocks.

The default priorities are generated from wowsims.com: each supported spec has one pack named "&lt;Spec&gt; (wowsims.com)", translated from wowsims's own action list ([Pack wowsims recipes](Pack-wowsims-Recipes)).

`Hekili_Shared` is a content addon too. It holds what every class uses: racial abilities, consumables, items and common auras, and one race file per race under `Races/`. It registers through `Hekili:NewShared` and `Hekili:NewRace` instead of `NewClass`.

## Load order

The client loads only the core by itself. Every content addon has `## LoadOnDemand: 1`, and the core loads them once per session, when it initializes and before it builds the profile, so the profile's defaults already see the class's specs and packs.

1. The core loads `Hekili_Shared`. Every class gets the shared and race content, with or without a pack of its own.
2. The core reads the player's class token, such as `DRUID`, and finds the matching pack, `Hekili_Druid`.
3. It reads the pack's `## X-Hekili-ContentAPI` from the TOC. If the pack is missing or the number differs from the core's, the pack is not loaded.
4. It loads the pack. The class file runs; `Hekili:NewClass` returns the kit, and the file registers everything on it.

The loader is `ns.LoadContent` in `src/Hekili/Engine/Content.lua`. It loads `Hekili_Shared` explicitly instead of relying on the client to load a dependency. A failure at any step (the shared addon fails to load, the class cannot be read, the pack is missing, its content API differs, or it fails to load) keeps one notice, which the core shows once the addon is enabled. The core then runs with no class spec, and nothing retries: the notice asks for a `/reload` or an install.

A class file starts by checking the class, so that its code does nothing for any other character. From `src/Hekili_Druid/Druid.lua`:

```lua
local Facade = Hekili.Client
local C_Spell, UnitClassBase = Facade.C_Spell, Facade.UnitClassBase
local L = Hekili:GetLocale("Hekili_Druid")

if UnitClassBase("player") ~= "DRUID" then
    return
end
```

`Hekili:NewClass` makes the same check and returns nil for another class, so the file stops there too.

`tests/helpers/addons.lua` holds the list of addons and their order, which every headless test, loader and tool reads: `Hekili`, then `Hekili_Shared`, then the class packs.

## The content API version

The content surface is everything a content addon may use: the registration API, `Hekili.Client`, and the names available inside content functions ([Pack environment names](Pack-Environment-Names)). Its version is `CONTENT_API` in `src/Hekili/Engine/Content.lua`, and each content addon's TOC declares the version it was written for:

```text
## Dependencies: Hekili, Hekili_Shared
## LoadOnDemand: 1
## X-Hekili-ContentAPI: 14
```

The core loads a pack only when the two numbers are equal. This turns a core and a pack from different releases into a clear notice ("update the older one") instead of an error in the middle of the class file. `CONTENT_API` and every content TOC change together, and only when the content surface changes: a new `Register*` call, a new ability or aura field the core reads, a new name in a content function's environment. `tests/Forever/content_spec.lua` checks that the TOCs and the constant agree. A pack's own release changes its `## Version`, not the content API.

## The core and pack boundary

The core is a generic engine configured by its callers. It names no class, spell, aura, talent, form or rotation; it works only with what the packs declare. In turn, a pack uses only the registration API and never the core's internals. A behaviour that one class needs is added to the core as a generic mechanism, which the pack then switches on with data: a cost modifier tied to an aura, a resource regenerated per swing, a window opened by an evaluator.

`tests/boundary_spec.lua` enforces both directions as part of `make check`.

- **The core side.** The belief, the registration code and the test harness may hold no ability, aura or talent key, spell ID, class or form name that the content registers. The keys are read from the content at test time. A few simulation files inherited from the original Hekili still carry some of these names; each file is held to a per-name ceiling that may only fall.
- **The pack side.** A content file may use only `Hekili:NewClass`, `Hekili:NewShared`, `Hekili:NewRace`, `Hekili.State`, `Hekili.Class`, `Hekili.Client` and `Hekili:GetLocale`. It may not reach into the core's private namespace or its debug handles. Pack share strings and the `Locales/` files are data and are not scanned.

A separate check, `tools/check_api_reads.sh`, fails on any game API read outside the facade, so a pack reads the client only through `Hekili.Client` ([Pack belief and simulation](Pack-Belief-And-Simulation#the-facade)).

> [!WARNING]
> **Different from retail Hekili:** In the original Hekili, class files were part of the core addon and could use its private namespace. Here a class file is a separate addon that sees only the public `Hekili` object, so a retail class file does not load unchanged.

## See also

- [Pack class file anatomy](Pack-Class-File-Anatomy)
- [Pack API reference](Pack-API-Reference)
- [Pack belief and simulation](Pack-Belief-And-Simulation)
- [Pack adding a spec or class](Pack-Adding-A-Spec-Or-Class)
- [Contributing architecture](Contributing-Architecture)
