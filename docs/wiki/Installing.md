<!--
Purpose: Install from CurseForge or a GitHub release, remove an old Hekili folder, keep core and class addons on one version.
Type: How-to
Audience: players
Prerequisites: None.
-->
This page shows how to install Hekili Forever from CurseForge or from a GitHub release, how to replace an older Hekili folder, and how to keep the core addon and the class addons on the same version. After installing, continue with [Getting started](Getting-Started).

## Before you start

- Close the game client. If it stays open, type `/reload` after copying the folders.
- Hekili Forever is made of eleven addons, and each one is a folder:
  - `Hekili`, the core addon, with the displays, the options and the simulation;
  - `Hekili_Shared`, the content every class uses, such as racial abilities and items;
  - one class addon for each class: `Hekili_Warrior`, `Hekili_Druid`, `Hekili_Rogue`, `Hekili_Paladin`, `Hekili_Shaman`, `Hekili_Hunter`, `Hekili_Mage`, `Hekili_Priest` and `Hekili_Warlock`.

Install all eleven together. The core loads only the class addon of the character you log in with.

## Install from CurseForge

1. In the CurseForge app, search for Hekili Forever, or open its page at [curseforge.com/wow/addons/hekili-forever](https://www.curseforge.com/wow/addons/hekili-forever).
2. Install it. The app installs all eleven folders.
3. Update it from the app as well. The app updates every folder at once.

## Install from a GitHub release

1. Open the [releases page](https://github.com/zmsl/hekili/releases) and download the zip file of the latest release.
2. Extract the zip. It holds the eleven folders listed above.
3. Copy every folder into the game's `Interface\AddOns` folder. <!-- UNVERIFIED: the exact name of the Forever client's game folder that holds Interface\AddOns. -->

## Replace an old Hekili folder

Hekili Forever uses the original Hekili's folder name, `Hekili`, and its saved settings, so settings from an earlier install carry over.

1. Close the game client.
2. Delete the old `Hekili` folder, and any old `Hekili_` folders, from `Interface\AddOns`.
3. Copy the new folders in, as above.

Replace the folders rather than copying the new files over the old ones: a file that the new release no longer ships would stay behind and could still load. <!-- UNVERIFIED: these steps have not been checked in game. -->

## Keep the addons on one version

Every addon in a release carries the same version. When the core and a class addon come from different releases, the class addon may not load. Hekili Forever then shows a notice at login that ends "update the older one", and recommends nothing for that class.

To fix it, install the core and every class addon again from one release. A notice that names a missing class addon means that the class folder is not installed.

## Check that it works

1. Log in. On the character screen, open the game's addon list and make sure the Hekili Forever addons are enabled.
2. In the game, type `/hekili`. The options window opens.
3. Target an enemy. The **Primary** display shows the ability to press next.

<!-- TODO-SCREENSHOT: the addon list on the character screen with the eleven Hekili Forever addons enabled -->

If nothing appears, see [Troubleshooting and FAQ](Troubleshooting-And-FAQ).
