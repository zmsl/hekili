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
| `Hekili:RegisterRecommendationListener(fn)` and `Hekili:UnregisterRecommendationListener(fn)` | Functions | An addon that follows each update of the recommendations |
| `HEKILI_RECOMMENDATION_UPDATE` | WeakAuras event | A WeakAura that shows or reacts to recommendations |
| `Hekili:GetToggleState(name)` and `HEKILI_TOGGLE` | Function, WeakAuras event | Reading the toggles and the display mode, and reacting when they change |
| `Hekili.IsForever()` and `Hekili.Version` | Function, string | Telling Hekili Forever from retail Hekili, and which release is loaded ([Detecting Hekili Forever](#detecting-hekili-forever)) |
| `Hekili:RegisterSnapshotListener(fn)` and `Hekili:UnregisterSnapshotListener(fn)` | Functions | An addon that adds its own lines to a snapshot |
| The public chat commands | Commands | Macros and buttons that change toggles, priorities and profiles |
| The LibDataBroker data source `Hekili` | Data source name | A display addon for LibDataBroker, such as a panel bar, that shows Hekili Forever's mode and toggles and its menu |

The display style interface and the fields of a recommendation record are described in [Contributing display styles and integrations](Contributing-Display-Styles-And-Integrations). `Hekili.DisplayStyleAPI` changes only when that interface or the record's fields change. The chat commands are listed in [Slash commands](Slash-Commands); each one also works in a macro.

Only the name of the LibDataBroker data source is promised: a display addon finds it under `Hekili`. What the data source holds (its text, icon and click handler) is internal and can change.

The saved settings (`HekiliDB`), the options, the frames and every other member of the `Hekili` global are internal. An addon that reads them can break with any release. `Hekili.Engine` is internal too: an addon that follows the recommendations registers a recommendation listener.

## Detecting Hekili Forever

The core addon's folder, and the name another addon declares as a dependency, is `Hekili`. The class addons, such as `Hekili_Druid`, are loaded by the core and are never a dependency of an integration.

- An addon that cannot work without Hekili Forever lists `## Dependencies: Hekili` in its TOC file. The game then loads Hekili Forever first, so the `Hekili` global and the functions on this page exist when the addon's own files run.
- An addon that only adds to Hekili Forever when it is there lists `## OptionalDeps: Hekili`, which also loads Hekili Forever first when it is installed, and tests for it before use.

Retail Hekili uses the same folder name and the same `Hekili` global, so an addon that must know which one is loaded calls `Hekili.IsForever()`:

```lua
-- A file of an addon with "## OptionalDeps: Hekili" in its TOC
if Hekili and Hekili.IsForever and Hekili.IsForever() then
    -- Hekili Forever is loaded
end
```

| Name | What it gives |
|---|---|
| `Hekili.IsForever()` | Always `true` in Hekili Forever. Retail Hekili has no such function, so the test above is false there. |
| `Hekili.Version` | The version as a string: the release's tag, such as `v0.9.0`, or `Dev-` followed by the game build and a date for a copy run straight from the source. It does not tell Hekili Forever from retail Hekili. |
| `Hekili.DisplayStyleAPI` | The version of the display style interface and the recommendation record, 1 in this release. Comparing it with the version an addon was written for tells the addon that both are the ones it expects. `Hekili:RegisterDisplayStyle` itself refuses a style written for another version. |

## Load order

| Function or event | When it can be used |
|---|---|
| `Hekili:RegisterDisplayStyle` | Any time after Hekili Forever's files have loaded, including from the dependent addon's own files. A style registered after the displays exist is bound on the next rebuild, and its settings are added to every display. |
| `Hekili:RegisterSnapshotListener` | Any time after Hekili Forever's files have loaded |
| `Hekili:RegisterRecommendationListener` | Any time after Hekili Forever's files have loaded. The listener is called from the next update on. |
| `Hekili:GetToggleState` | After Hekili Forever's saved settings have loaded; from `PLAYER_LOGIN` on it is always safe |
| `HEKILI_RECOMMENDATION_UPDATE` | Sent only when WeakAuras is loaded as the player enters the world |

The recommendations are worked out only for a display that is shown, or followed by the action bar glow. A display that is hidden publishes nothing new, so neither a style, a listener nor the WeakAuras event sees an update for it.

## Hidden values

The Forever client hides some game values from addons. A hidden value is a secret value: the game's own frames can show it, but Lua code cannot compare it, calculate with it or turn it into text ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)).

The numbers in a recommendation record are not game values. `time`, `exact_time`, `cost`, `busy` and each entry of `resources` are worked out by Hekili Forever's simulation, which calculates with them, so they are plain Lua numbers that an addon can compare and calculate with. `resources` holds the simulation's estimate of each resource at the time of the recommendation. The game hides the real amount, so the estimate can differ from it.

An integration that reads the game itself meets the game's limits. On Forever the game hides energy, rage and mana in and out of combat, and during combat the remaining time of cooldowns and of buffs and debuffs, as the table in [What the game reports](What-Hekili-Forever-Can-And-Cannot-Know#what-the-game-reports) lists.

<!-- UNVERIFIED: the text fields of a record (texture, keybind) are assumed plain like the numbers; not measured in game. -->

> [!WARNING]
> **Different from retail Hekili:** Retail Hekili has a global function, `Hekili_GetRecommendedAbility`. Hekili Forever has no such function: an addon follows the recommendations with a recommendation listener or a display style, and a WeakAura with `HEKILI_RECOMMENDATION_UPDATE`.

## See also

- [Show the next recommendation in a WeakAura](Integration-WeakAuras-Example)
- [Contributing architecture](Contributing-Architecture): where the recommendations come from
