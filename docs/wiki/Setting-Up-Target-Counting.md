This page shows how to make Hekili Forever count the enemies near you, so that its area-of-effect recommendations start when several enemies are in range. It covers nameplate counting and the **Enemy Range Radius** setting. For why the count can differ from what you see on screen, read [How targets are counted](How-Targets-Are-Counted).

| Enemy Range Radius | |
|---|---|
| Where | **/hekili > Priorities > *your specialization* > Targeting > Nameplate Detection** |
| Values | 0 to 100 yards, in steps of 1 |
| Default | Set per specialization ([table below](#default-radius-by-specialization)) |
| Needs | **Count Nameplates Near You**, with enemy nameplates shown |
| Saved | Per specialization, in your profile |

## Before you start

- Leave combat. The nameplate settings below cannot be changed during combat.
- Each specialization keeps its own settings. Repeat these steps for each one you play.

## Turn on nameplate counting

1. Type `/hekili` to open the options.
2. Open **Priorities**, then your specialization, then **Targeting**.
3. Check **Count Nameplates Near You**.
4. If **Show Enemy Nameplates** and **Show All Nameplates** appear under **Nameplate Detection**, check both. They change the game's own nameplate settings, and they disappear once both are on.

![The Targeting tab for a Feral Druid, with Count Nameplates Near You checked and both nameplate boxes shown](images/Setting-Up-Target-Counting-1.png)
<!-- shot: TODO, Druid Feral -->

## Set the radius

1. Find **Enemy Range Radius** under **Nameplate Detection**. It appears only when both nameplate settings are on.
2. Drag the slider to the distance at which an enemy should count:
   - For a melee specialization, 10 yards or less.
   - For a ranged specialization, the range of your main attack.
3. Close the options.

Beyond 10 yards, Hekili Forever counts only enemies that are in combat.

> [!NOTE]
> **On Forever:** The game does not report the hits you land on other enemies, so **Count Damaged Enemies** finds fewer targets than it did in retail Hekili. Counting nameplates is the more reliable method.

### Default radius by specialization

<!-- GENERATED:spec-defaults-nameplate -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Class | Specializations | Default (yards) |
|---|---|---|
| Warrior | Arms, Fury, Protection | 10 |
| Druid | Balance | 30 |
| Druid | Feral, Guardian | 10 |
| Rogue | Assassination, Combat, Subtlety | 10 |
| Paladin | Protection, Retribution | 10 |
| Shaman | Elemental | 30 |
| Shaman | Enhancement | 10 |
| Hunter | Beast Mastery, Marksmanship, Survival | 35 |
| Mage | Arcane, Fire, Frost | 30 |
| Priest | Discipline, Shadow | 30 |
| Warlock | Affliction, Demonology, Destruction | 30 |
<!-- /GENERATED -->

## Check that it works

1. Pull two or more enemies.
2. Look at the bottom right of the first icon in the **Primary** or **AOE** display. It shows the number of counted enemies when there is more than one.

If the number stays at one, see [Troubleshooting and FAQ](Troubleshooting-And-FAQ).

## See also

- [Specialization options](Specializations-Reference): every option on the specialization page
- [Toggles](Toggles): **Display Mode**, including the AOE and Dual modes
