<!--
Purpose: What another addon may rely on, how to detect Hekili Forever, load order, and the limits of the data.
Type: Explanation
Audience: addon and WeakAura authors
Prerequisites: None.
-->
The **integration surface** of Hekili Forever is the set of functions, events and commands that another addon or a WeakAura may rely on to read Hekili Forever's recommendations or react to them. Everything on the surface is listed here and described in the [Integration reference](Integration-Reference). Anything else that can be reached through the `Hekili` global works, but it is not a promise: it can change in any release without notice.

The recommendations come from Hekili Forever's own simulation of the next few seconds of the fight. They are estimates, not values read from the game, which matters on the Forever client because the game hides many combat values from addons.

## What is stable

| Surface | Kind | For |
|---|---|---|
| `Hekili:RegisterDisplayStyle(name, impl)` and `Hekili.DisplayStyleAPI` | Function, number | An addon that draws a display's recommendations in its own way |
| The recommendation record | Table fields | Every reader of the recommendations |
| `HEKILI_RECOMMENDATION_UPDATE` | WeakAuras event | A WeakAura that shows or reacts to recommendations |
| `Hekili:RegisterSnapshotListener(fn)` and `Hekili:UnregisterSnapshotListener(fn)` | Functions | An addon that adds its own lines to a snapshot |
| The public chat commands | Commands | Macros and buttons that change toggles, priorities and profiles |

The display style interface and the fields of a recommendation record are described in [Contributing display styles and integrations](Contributing-Display-Styles-And-Integrations). `Hekili.DisplayStyleAPI` changes only when that interface or the record's fields change. The chat commands are listed in [Slash commands](Slash-Commands); each one also works in a macro.

The saved settings (`HekiliDB`), the options, the frames and every other member of the `Hekili` global are internal. An addon that reads them can break with any release. An addon that is neither a display style nor a WeakAura therefore has no public way to receive each update of the recommendations; the snapshot listener runs only when a snapshot is taken.

## Detecting Hekili Forever

The core addon's folder, and the name another addon declares as a dependency, is `Hekili`. The class addons, such as `Hekili_Druid`, are loaded by the core and are never a dependency of an integration.

- An addon that cannot work without Hekili Forever lists `## Dependencies: Hekili` in its TOC file. The game then loads Hekili Forever first, so the `Hekili` global and the functions on this page exist when the addon's own files run.
- An addon that only adds to Hekili Forever when it is there lists `## OptionalDeps: Hekili`, which also loads Hekili Forever first when it is installed, and tests for it before use.

```lua
-- A file of an addon with "## OptionalDeps: Hekili" in its TOC
if Hekili and Hekili.DisplayStyleAPI == 1 then
    -- the interface this addon was written for is present
end
```

`Hekili.DisplayStyleAPI` is the interface version of the display style interface and the recommendation record. Comparing it with the version an addon was written for tells the addon that both are the ones it expects. `Hekili:RegisterDisplayStyle` itself refuses a style written for another version.

## Load order

| Function or event | When it can be used |
|---|---|
| `Hekili:RegisterDisplayStyle` | Any time after Hekili Forever's files have loaded, including from the dependent addon's own files. A style registered after the displays exist is bound on the next rebuild, and its settings are added to every display. |
| `Hekili:RegisterSnapshotListener` | Any time after Hekili Forever's files have loaded |
| `HEKILI_RECOMMENDATION_UPDATE` | Sent only when WeakAuras is loaded as the player enters the world |

The recommendations are worked out only for a display that is shown. A display that is hidden publishes nothing new, so neither a style nor the WeakAuras event sees an update for it.

## Hidden values

The Forever client hides some game values from addons. A hidden value is a secret value: the game's own frames can show it, but Lua code cannot compare it, calculate with it or turn it into text ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)).

The numbers in a recommendation record are not game values. `time`, `exact_time`, `cost`, `busy` and each entry of `resources` are worked out by Hekili Forever's simulation, which calculates with them, so they are plain Lua numbers that an addon can compare and calculate with. `resources` holds the simulation's estimate of each resource at the time of the recommendation. The game hides the real amount, so the estimate can differ from it.

An integration that reads the game itself meets the game's limits. On Forever the game hides energy, rage and mana in and out of combat, and during combat the remaining time of cooldowns and of buffs and debuffs, as the table in [What the game reports](What-Hekili-Forever-Can-And-Cannot-Know#what-the-game-reports) lists.

<!-- UNVERIFIED: the text fields of a record (texture, keybind) are assumed plain like the numbers; not measured in game. -->

> [!WARNING]
> **Different from retail Hekili:** Retail Hekili has a global function, `Hekili_GetRecommendedAbility`. Hekili Forever has no such function: an addon reads the recommendations through a display style, and a WeakAura through `HEKILI_RECOMMENDATION_UPDATE`.

## See also

- [Show the next recommendation in a WeakAura](Integration-WeakAuras-Example)
- [Contributing architecture](Contributing-Architecture): where the recommendations come from
