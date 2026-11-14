<!--
Purpose: Make the next ability glow on your action bars.
Type: How-to
Audience: players
Prerequisites: None.
-->
This page shows how to make the action buttons that cast Hekili Forever's recommendation glow on your own action bars. The first recommendation glows gold and the second blue, by default. The glow works even with the display itself hidden, so it can replace the display.

| Action Bar Glow | |
|---|---|
| Where | **/hekili > Displays > Action Bar Glow** |
| Default | Off |
| Follows | The **Primary** display, by default |
| Works on | The game's keyboard and gamepad bars, ElvUI, Bartender and Dominos |
| Saved | In your profile |

## Turn it on

1. Type `/hekili` and open **Displays**, then **Action Bar Glow**.
2. Check **Enabled**.

## Choose what glows

- **Follow Display** chooses the display whose recommendations glow. The default is **Primary**.
- **Now Color** is the glow on the buttons of the first recommendation. The default is gold.
- **Glow the next recommendation** makes the buttons of the second recommendation glow too, in **Next Color**, blue by default. The followed display must show at least two recommendations.
- **In Combat Only**, on by default, limits the glow to combat.

The glow is placed on every button that casts the ability, so an ability on two bars glows on both. A bar that changes with a form or a stance is followed as it changes.

## Hide the display

To use the glow instead of the icons, keep the display enabled and set its transparency to 0: on the display's **Visibility** tab, set **PvE Alpha** and **PvP Alpha** to 0. Hekili Forever keeps working out the followed display's recommendations for the glow while every display is hidden.

## Check that it works

Enter combat with an enemy targeted. The button that casts the first recommendation glows gold, and the button of the second glows blue.

<!-- TODO-SCREENSHOT: an action bar with a gold and a blue glow -->

## See also

- [Reading the displays](Reading-The-Displays)
- [Displays reference](Displays-Reference)
