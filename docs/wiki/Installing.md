<!--
Purpose: Install from CurseForge or a GitHub release, remove an old Hekili folder, keep core and class addons on one version.
Type: How-to
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Install from CurseForge or a GitHub release, remove an old Hekili folder, keep core and class addons on one version.

## Before you start

- Close the game client, or plan a `/reload` after copying. Source: `docs/publishing/README.md`
- The release zip holds the core addon `Hekili`, the shared content `Hekili_Shared` and one addon per class: eleven folders. Source: `tests/helpers/addons.lua`, `.pkgmeta`

## Install from CurseForge

- The CurseForge app installs every folder of the zip. TODO-LINK(CurseForge project page). Source: `docs/publishing/README.md`

## Install from a GitHub release

- Download the zip from the [releases page](https://github.com/zmsl/hekili/releases) and copy every folder into the game's AddOns folder. Source: `.github/workflows/publish.yml`

## Remove an old Hekili folder

- A Hekili folder from another client or an older release must be replaced, not merged. TODO: verify the exact steps in game. Source: `README.md` (Install)

## Keep the addons on one version

- Every addon in the zip carries the same version. A class addon built for another content API version is refused, with a notice in chat. Source: `src/Hekili/Engine/Content.lua` (CONTENT_API, ContentNotice)

## Check that it works

- Type `/hekili` after login: the options open. The Primary display shows a recommendation once a target is selected. Source: `src/Hekili/Options/ChatCommands.lua`
- TODO-SCREENSHOT: the addon list on the character screen with the eleven Hekili Forever addons enabled

## See also

- [Getting started](Getting-Started)
- [Troubleshooting and FAQ](Troubleshooting-And-FAQ)
