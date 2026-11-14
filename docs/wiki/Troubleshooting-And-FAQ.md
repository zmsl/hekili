<!--
Purpose: Nothing shows, wrong keybinds, recommendations lag, old data after an upgrade.
Type: How-to
Audience: players with a problem
Prerequisites: None.
-->
This page lists common problems with Hekili Forever and how to fix them: displays that show nothing, the wrong specialization, wrong keybinds, recommendations that seem late, and old settings after an upgrade. If a problem is not listed here, or the fix does not help, report it as [Reporting a problem](Reporting-A-Problem) describes.

## Nothing shows

Work through these checks in order.

1. **Hekili Forever is turned on.** Open **/hekili > General** and check **Enabled**, or type `/hekili enable`. After a Lua error, the addon can turn itself off.
2. **The class addon is installed and up to date.** At login, Hekili Forever shows a notice when it cannot load your class's addon: one that names the missing folder, or one that ends "update the older one" when the core and the class addon come from different releases. Install every folder again from one release ([Installing](Installing)).
3. **The specialization has priorities.** Type `/hekili spec`. A specialization marked "no priorities on Forever", such as a healing one, recommends nothing. If the current one is not the one you play, choose it with `/hekili spec` and its name.
4. **The specialization is not turned off.** On its page under **/hekili > Priorities**, the **Disable *your specialization*** box must be clear.
5. **The display is visible.** On the display's **Visibility** tab, **PvE Alpha** and **PvP Alpha** must be above 0. With **Advanced** checked, check each transparency setting there.
6. **There is something to recommend.** Target an enemy. Out of combat, a priority may have nothing to show until it does.

If the displays are still missing, they may be off the screen. Open **/hekili > Displays > Primary** and set **X** and **Y** on its **Icons** tab to 0.

## The wrong specialization or priority

Hekili Forever picks the talent tree with the most points, and some classes pick a priority from your talents. To choose yourself:

- `/hekili spec` and a name chooses the specialization;
- `/hekili priority` and a name chooses the priority; `/hekili priority default` hands the choice back.

[Choosing a priority](Choosing-A-Priority) explains how the choice is made.

## Wrong keybinds

Hekili Forever reads the keys from your action bars. A macro, a stealth or form bar, or an ability on several bars can make it show the wrong key. Set the text yourself with **Override Keybind Text** on the ability's page under **/hekili > Abilities**, or the item's page under **/hekili > Gear and Items** ([Abilities and items](Abilities-And-Items)).

## An icon you do not recognise

It is most likely an item, such as a potion or a trinket. Press the **Pause** key (ALT-SHIFT-P by default) and hover over the icon to see what it is. Press the key again to resume. To stop an item or ability from being recommended, disable it on its page under **Abilities** or **Gear and Items**.

## Recommendations seem late

The game hides energy, rage and mana from addons. Hekili Forever estimates them, and shows an ability only once it is sure the cost is covered, so an icon can appear a moment after the ability becomes usable. This is expected. [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know) explains the estimates.

If an ability is usable for much longer than a moment before it appears, take a snapshot and report it.

## No area-of-effect recommendations

Hekili Forever switches to area-of-effect abilities only when it counts several enemies. The count shows on the first icon when it is above one. If it stays at one, set up nameplate counting as [Setting up target counting](Setting-Up-Target-Counting) describes. In dungeons, enemy nameplates must be shown.

## Old data after an upgrade

- **Built-in priorities are replaced when an update changes them.** A chat notice names each priority that was updated. Changes made to a built-in priority are then lost; make changes in a copy instead.
- **A retired priority.** When a built-in priority is removed, a notice says so, and specializations that used it switch to their default priority.
- **Settings from an older Hekili.** Hekili Forever keeps the original Hekili's saved settings. If displays or toggles behave strangely after moving from another version, reset the profile on the Profiles page of **/hekili**, then type `/reload`. Resetting returns every setting of that profile to its default.

## Lua errors

A Lua error is a message from the game about a fault in an addon's code. If Hekili Forever turns itself off after an error, or a display stays blank, capture the error text and report it ([Reporting a problem](Reporting-A-Problem#capture-lua-errors)).

## See also

- [Reading a snapshot](Reading-A-Snapshot)
