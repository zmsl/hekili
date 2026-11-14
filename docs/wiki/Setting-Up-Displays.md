<!--
Purpose: Move, size and style displays; choose a style; set visibility in and out of combat.
Type: How-to
Audience: players
Prerequisites: [Getting started](Getting-Started).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Move, size and style displays; choose a style; set visibility in and out of combat.

## Before you start

- Leave combat: the displays cannot be unlocked in combat. Source: `src/Hekili/Options/ChatCommands.lua` (HandleMoveCommand)

## Move a display

- `/hekili move`, drag, then `/hekili lock`. Source: `src/Hekili/Options/ChatCommands.lua`

## Size and style

- The Icons and Style tabs of each display; the style is Classic or Timeline. Source: `src/Hekili/UI/Styles.lua`, `src/Hekili/Options/StyleOptions.lua`

## Visibility and transparency

- Separate PvE and PvP settings, and Hide When Mounted. Source: `src/Hekili/Options/Options.lua` (visibility)

## Check that it works

- TODO: the visible result.
- TODO-SCREENSHOT: a display's Style tab

## See also

- [Displays reference](Displays-Reference)
- [Reading the displays](Reading-The-Displays)
