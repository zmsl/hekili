<!--
Purpose: From first login to a placed display with working toggle keybinds.
Type: Tutorial
Audience: players
Prerequisites: Hekili Forever installed ([Installing](Installing)).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. From first login to a placed display with working toggle keybinds.

## What you will have at the end

- A Primary display placed on screen, the toggles bound to keys, and a first recommendation. TODO: state the time it takes.

## Open the options

- `/hekili` (alias `/hek`) opens the options; `/hekili help` lists the commands. Source: `src/Hekili/Engine/Sim/Core.lua` (RegisterChatCommand), `src/Hekili/Options/ChatCommands.lua`

## Place the displays

- `/hekili move` unlocks the displays for moving; `/hekili lock` locks them. Not available in combat. Source: `src/Hekili/Options/ChatCommands.lua` (HandleMoveCommand)
- TODO-SCREENSHOT: the Primary and AOE displays unlocked for moving

## Bind the toggles

- Default keybinds: Major Cooldowns ALT-SHIFT-R, Minor Cooldowns ALT-SHIFT-G, Interrupts ALT-SHIFT-I, Defensives ALT-SHIFT-T, Display Mode ALT-SHIFT-N, Pause ALT-SHIFT-P, Snapshot ALT-SHIFT-[. The full list is generated on [Toggles](Toggles). Source: `src/Hekili/Options/Options.lua` (GetDefaults)

## See a first recommendation

- Target an enemy: the first icon is the ability to press next, the icons after it the ones that follow. Source: `src/Hekili/UI/Styles/Classic.lua`

## Next steps

- Choose the display mode (Automatic or Single-Target) with `/hekili set mode`. Source: `src/Hekili/Options/ChatCommands.lua` (HandleSetCommand)

## See also

- [Reading the displays](Reading-The-Displays)
- [Choosing a priority](Choosing-A-Priority)
- [Toggles](Toggles)
