<!--
Purpose: Belief, band, facade, forecast, pack, recipe, window and other terms.
Type: Reference
Audience: everyone
Prerequisites: None.
-->
The **glossary** defines the terms used across this wiki: the player terms of the options and displays, and the developer terms of the pages on writing priorities and class addons. Each term links the page that explains it, where one exists.

## Terms

| Term | Meaning |
|---|---|
| Action list | A named list of priority lines. A priority has a default list and can call others, such as one for the pull or for several enemies. |
| Action priority list (APL) | The text form of a priority: one line per ability, each with conditions, in the SimulationCraft dialect the original Hekili read ([APL overview](APL-Overview)). |
| Band | The range of an estimate: a low end, a best guess and a high end. A priority line that tests `energy.lo` reads the low end. |
| Belief | Hekili Forever's running estimate of the game values that the client hides, such as energy, rage, mana and cooldown times. Each value is a band, plus how it was learned ([Pack belief and simulation](Pack-Belief-And-Simulation)). |
| Built-in priority | A priority shipped with a class addon. When an update changes it, the new version replaces the saved one; to change one, copy it first. |
| Class addon | The addon folder of one class, such as `Hekili_Druid`, with that class's abilities, auras, talents and priorities ([Installing](Installing)). |
| Clash | An ability option: treat the ability as ready this many seconds early, so that it wins over one that is ready only slightly sooner ([Abilities and items](Abilities-And-Items)). |
| Cooldown Manager | The game's own bars of cooldowns and auras. Hekili Forever reads them to learn whether a buff or debuff is up ([Cooldown Manager](Cooldown-Manager)). |
| Custom priority | A priority made or imported by the player. It is never replaced by an update. |
| Display | An on-screen frame of recommendations: **Primary**, **AOE**, **Cooldowns**, **Interrupts** or **Defensives** ([Reading the displays](Reading-The-Displays)). |
| Display mode | The setting that decides how many enemies the **Primary** and **AOE** displays plan for ([Toggles](Toggles#display-modes)). |
| Estimate | A value that Hekili Forever works out because the game hides it ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)). |
| Facade | The one part of the core addon that reads the game client. When the game hides a value, the facade answers from the belief instead. |
| Flicker | The first icon changing and changing back within a moment. Hekili Forever holds an icon for one more update rather than flicker. |
| Focus ability | An ability that a priority marks as worth watching, such as a buff to refresh. The Timeline style shows it in its **Now** circle. |
| Forecast | The simulated look ahead: Hekili Forever plays the priority forward over the next few seconds to fill the queue of icons. |
| Hidden value | A value the game shows on its own frames but does not let an addon read, compare or calculate with, such as energy or target health. Developer pages call it a secret value. |
| Kit | A class's abilities, auras and talents, shared by all its specializations. |
| Pack | A priority, also called an action pack. On developer pages, also the class addon that ships a class's kit and priorities. |
| Priority | The ordered list of abilities, with conditions, that a display follows. Each specialization has a default one ([Choosing a priority](Choosing-A-Priority)). |
| Profile | One complete set of Hekili Forever settings ([Profiles and sharing](Profiles-And-Sharing)). |
| Recipe | The data from which a built-in priority is generated: a wowsims.com rotation and the rules that translate it ([wowsims recipes](Pack-wowsims-Recipes)). |
| Recommendation | One ability that a display shows, with the time it is due. |
| Selector | A rule in a class addon that picks a specialization and a priority from the talents ([Choosing a priority](Choosing-A-Priority)). |
| Snapshot | A record of how one set of recommendations was chosen, line by line ([Reading a snapshot](Reading-A-Snapshot)). |
| Specialization | One talent tree of a class, with its own priorities and settings. Feral Combat has two: Feral and Guardian. |
| Target swap | A suggestion to use an ability on another enemy, shown as a small indicator on the icon ([How targets are counted](How-Targets-Are-Counted)). |
| Toggle | A switch that lets the priority use or skip a group of abilities, such as major cooldowns ([Toggles](Toggles)). |
| Window | A named span of time that a class addon defines and a priority can open and test, for a span the game shows no aura for ([APL windows](APL-Windows)). |
| wowsims.com | The rotation simulator whose rotations the built-in priorities are translated from, and against which they are measured ([Accuracy](Accuracy)). |

## See also

- [Contributing architecture](Contributing-Architecture)
