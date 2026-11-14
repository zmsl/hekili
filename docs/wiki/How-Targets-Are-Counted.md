<!--
Purpose: Nameplates, damage detection and target swaps, and why counts differ on Forever.
Type: Explanation
Audience: players
Prerequisites: None.
-->
**Target counting** is how Hekili Forever decides how many enemies a fight has. The count decides when a priority switches to its area-of-effect abilities, and which enemies a target swap can suggest. Hekili Forever counts the current target, enemies with a nameplate near the player and, where the game reports it, enemies the player has recently damaged. The settings are on each specialization's **Targeting** tab; [Setting up target counting](Setting-Up-Target-Counting) gives the steps.

The count shows at the bottom right of the first icon in the **Primary** and **AOE** displays whenever it is above one.

## The current target

The current target is always counted as an enemy, even when there is no target. The **Your Target** option shows this and cannot be turned off. So the count is never below one.

The game's soft targets, from its action targeting system, are not supported.

## Nameplates

With **Count Nameplates Near You** checked, each enemy whose nameplate is shown counts when it is within **Enemy Range Radius** of the player. The game must show enemy nameplates: **Show Enemy Nameplates** and **Show All Nameplates** turn on the game's own settings for that. Beyond 10 yards, an enemy counts only while it is in combat, so that a group of idle enemies further away does not change the recommendations.

The distance to an enemy comes in steps of about 5 yards. When the distance stops being reported, it counts as unknown after 1.5 seconds.

A rising count is used at once. A falling count is held for a moment, so that the display does not flicker between the single-target and area-of-effect abilities when an enemy steps briefly out of range.

### In dungeons and raids

In dungeons and raids, the game hides which enemy each nameplate belongs to. As of v0.8.1, Hekili Forever still counts the nameplates there, and tells the enemies apart by their nameplates. With enemy nameplates or **Count Nameplates Near You** off, it counts one enemy.

## Damaged enemies

With **Count Damaged Enemies** checked, an enemy the player has damaged counts for several seconds afterwards (**Timeout**). Its options can include enemies damaged by the player's pets and enemies carrying the player's damage-over-time effects, and leave out enemies with no nameplate on screen.

> [!NOTE]
> **On Forever:** As of v0.8.1, the game does not report the hits you land on other enemies, so **Count Damaged Enemies** finds fewer targets than it did in retail Hekili. Counting nameplates is the more reliable method.

## Target swaps

With **Allow Target Swaps** checked, a priority that keeps a debuff on several enemies can suggest using an ability on another enemy. The suggestion shows as a small indicator on the icon. Target swaps are off by default; they can also be turned on with Recommend Target Swaps on the menu that a left click on the Hekili Forever minimap button opens, or with `/hekili set cycle on`.

Target swaps need enemy nameplates: **Show Enemy Nameplates** and **Show All Nameplates** on, in the open world too. Hekili Forever remembers the debuffs placed on each enemy that was targeted. An enemy whose nameplate disappears is forgotten, so its debuff may be suggested again. On enemies other than the current target, the time left on a debuff is estimated, not read.

The original Hekili could skip enemies about to die. The game hides target health on Forever, so the time until an enemy dies is unknown, and the **Filter by Time-to-Die** option is hidden.

## Minimum targets for area-of-effect

**Minimum Targets for Dedicated AOE Recommendations** sets the number of enemies that the **AOE** display, and the AOE display mode, assume at least. It applies however many enemies are counted.

## See also

- [Toggles](Toggles#display-modes): the display modes that decide which count the displays use
- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
- [Specializations reference](Specializations-Reference): every option on the **Targeting** tab, with its default
