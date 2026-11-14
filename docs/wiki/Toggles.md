<!--
Purpose: Every toggle, its keybind and what it skips; Display Mode; Pause.
Type: Reference
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Every toggle, its keybind and what it skips; Display Mode; Pause.

## How a toggle works

- A toggle that is off makes the priority skip the abilities that need it; the walk falls through to the next line. Source: `src/Hekili/Engine/Sim/State.lua` (mt_toggle)
- `/hekili set <toggle> on`, `off`, or no value to flip it. Source: `src/Hekili/Options/ChatCommands.lua` (HandleSetCommand)

## Every toggle

<!-- GENERATED:options-toggles -->
<!-- /GENERATED -->

## Display modes

- Automatic, Single-Target, AOE, Dual and Reactive Dual; the Display Mode keybind cycles through the checked ones. Source: `src/Hekili/Options/Options.lua` (displayModes)

## See also

- [Slash commands](Slash-Commands)
- [Abilities and items](Abilities-And-Items)
