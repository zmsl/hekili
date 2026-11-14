<!--
Purpose: What carried over, what is new and what is gone, for players of the original.
Type: Explanation
Audience: players
Prerequisites: None.
-->
**Hekili Forever** is a fork of the original Hekili, the priority helper for retail World of Warcraft, rebuilt for the WoW Forever client. Most of what a retail Hekili player knows carries over: the displays, the toggles, the priorities and the snapshots work the same way. The main difference is that the Forever client hides many combat values from addons, so Hekili Forever estimates them, and a few features that depended on them are gone or work differently.

Problems with Hekili Forever are reported to the Hekili Forever project ([Reporting a problem](Reporting-A-Problem)), never to the original Hekili project.

## What carried over

- **The simulation.** As in the original, each recommendation comes from simulating the next few seconds of the fight with the active priority. The first icon is the ability to press now, and the next icons follow from it.
- **The displays.** **Primary**, **AOE**, **Cooldowns**, **Interrupts** and **Defensives**, in the original's icon-row look, now called the Classic style.
- **The toggles.** Major and minor cooldowns, interrupts, defensives, potions and the two custom toggles, with the same default keys, and the same display modes.
- **Priorities.** Action priority lists in the SimulationCraft dialect the original used, with the same editor, import and export.
- **Snapshots** and the **Pause** key, to see why an ability was recommended.
- **Commands.** `/hekili` and `/hek`, with `set`, `priority`, `profile`, `move`, `lock`, `enable`, `disable` and `snapshot` ([Slash commands](Slash-Commands)).
- **Settings.** Hekili Forever uses the same addon folder name, `Hekili`, and the same saved settings, so an existing profile carries over.

## What is new

- **Estimates of hidden values.** Energy, rage and mana are hidden at all times, and cooldown times and aura durations during combat. Hekili Forever estimates them from what the game still reports ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)).
- **Priorities from wowsims.com.** Every built-in priority is translated from a rotation at [wowsims.com](https://wowsims.com) rather than from SimulationCraft. Their names end in "(wowsims.com)".
- **One specialization per talent tree.** Each talent tree is a specialization with its own priorities and settings, and Hekili Forever picks the tree with the most points. `/hekili spec` chooses another one. Some priorities are picked from the talents ([Choosing a priority](Choosing-A-Priority)).
- **Class addons.** Each class's content is a separate addon folder, loaded only for that class ([Installing](Installing)).
- **The game's Cooldown Manager.** Hekili Forever reads the game's Cooldown Manager bars to learn whether a buff or debuff is up during combat ([Cooldown Manager](Cooldown-Manager)).
- **The Timeline style.** A display style that lays recommendations out along time, beside the Classic style ([Reading the displays](Reading-The-Displays)).
- **Modern overlays.** An optional layer that adds the game's own cooldown swipes and usability feedback to the icons.
- **Action Bar Glow.** The real action buttons glow for the first and second recommendations ([Action Bar Glow](Action-Bar-Glow)).
- **The Movement toggle.** Some priorities show the next ability while the player is out of range, tinted, so that the player can move to it.
- **Fewer flickers.** When the first icon would swap between two abilities that are both still counting down, it keeps the current one for one more update.

## What is different or gone

- **Time to die.** The game hides target health, so the time until a target dies is always unknown and reads as 3600 seconds. Priority lines that wait for a target to be nearly dead do not fire, and the **Filter by Time-to-Die** option of target swaps is hidden.
- **The player's health.** While the game hides it, the player's health reads as full, so a defensive line based on low health does not fire.
- **Counting damaged enemies.** The game does not report hits landed on other enemies, so **Count Damaged Enemies** finds fewer targets. Nameplate counting is the reliable method ([How targets are counted](How-Targets-Are-Counted)).
- **Resource pooling.** `pool_resource` works only in its `for_next=1` form, which waits for the next line's cost. Other forms are ignored: the forecast already waits until a cost is covered.
- **Minor Cooldowns.** In `/hekili set`, the **Minor Cooldowns** toggle is `minor_cooldowns`; the older word `essences`, used by retail macros, still works.
- **SpellFlash.** SpellFlash support was removed; it never worked on Forever.
- **Imported priorities.** A priority exported from retail Hekili names another game's specializations and abilities. It needs translating before it works ([APL Forever differences](APL-Forever-Differences)).

## Why recommendations can lag

A priority line that spends a resource tests the low end of Hekili Forever's estimate. A line that needs 60 energy shows once Hekili Forever is sure there are at least 60. The icon can therefore appear a moment after the ability becomes usable, but it does not appear while the ability is still unaffordable. Retail Hekili read the exact value, so it never waited this way.

> [!WARNING]
> **Different from retail Hekili:** A custom priority copied from retail Hekili that tests `target.time_to_die`, `fight_remains` or `health.pct` behaves differently here. Lines that test resources work, but `energy.lo` and `mana.pct_lo` are the cautious readings.

## See also

- [Accuracy](Accuracy)
- [Getting started](Getting-Started)
