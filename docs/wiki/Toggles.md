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
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Option | Type | Default | Description |
|---|---|---|---|---|
| Damage Cooldowns | Major Cooldowns | keybind | ALT-SHIFT-R | Set a key to toggle recommendations of Major Cooldowns on or off. |
| Damage Cooldowns | Enable Major Cooldowns | toggle | On | If checked, abilities and items that require the Major Cooldowns toggle can be recommended. |
| Damage Cooldowns | Show in Separate Cooldowns Display | toggle | Off | If checked, abilities controlled by this toggle will be shown separately in your Major Cooldowns display when the toggle is enabled. |
| Damage Cooldowns | Active During Bloodlust | toggle | Off | If checked, when any Bloodlust effect is active, the Major Cooldowns toggle will be treated as enabled, even if unchecked. |
| Damage Cooldowns | Active During Power Infusion | toggle | Off | If checked, when Power Infusion is active, the Major Cooldowns toggle will be treated as enabled, even if unchecked. |
| Damage Cooldowns | Minor Cooldowns | keybind | ALT-SHIFT-G | Set a key to toggle recommendations of Minor Cooldowns on or off. |
| Damage Cooldowns | Enable Minor Cooldowns | toggle | On | If checked, abilities that require the Minor Cooldowns toggle can be recommended. |
| Damage Cooldowns | Auto-Enable when Major Cooldowns Active | toggle | On | If checked, when Major Cooldowns are enabled (or auto-enabled), your Minor Cooldowns may be recommended even if the toggle itself is not checked. |
| Damage Cooldowns | Potions | keybind | n/a | Set a key to toggle recommendations of Potions on or off. |
| Damage Cooldowns | Enable Potions | toggle | Off | If checked, abilities that require the Potions toggle can be recommended. |
| Damage Cooldowns | Auto-Enable when Major Cooldowns Active | toggle | Off | If checked, when Major Cooldowns are enabled (or auto-enabled), your Potions may be recommended even if the toggle itself is not checked. |
| Interrupts and Defensives | Interrupts | keybind | ALT-SHIFT-I | Set a key to toggle recommendations of Interrupts (or utility abilities) on or off. |
| Interrupts and Defensives | Enable Interrupts | toggle | On | If checked, abilities that require the Interrupts toggle can be recommended |
| Interrupts and Defensives | Show in Separate Interrupts Display | toggle | Off | If checked, abilities that require the Interrupts toggle will be shown separately in your Interrupts display. |
| Interrupts and Defensives | Interrupt Timing | slider | 0.25 | By default, interrupts are recommended when an enemy's cast has 0.25 seconds (or less) remaining. |
| Interrupts and Defensives | Defensives | keybind | ALT-SHIFT-T | Set a key to toggle recommendations of Defensives on or off. |
| Interrupts and Defensives | Enable Defensives | toggle | On | If checked, abilities that require the Defensives toggle can be recommended. |
| Interrupts and Defensives | Show in Separate Defensives Display | toggle | Off | If checked, defensive/mitigation abilities will be shown separately in your Defensives display. |
| Movement | Movement | keybind | n/a | Set a key to toggle Movement on or off. |
| Movement | Enable Movement | toggle | On | If checked, a priority that moves to reach its next ability shows that ability while you are out of range, tinted as out of range. |
| Display Control | Display Mode | keybind | ALT-SHIFT-N | Pressing this binding will cycle your Display Mode through the options checked below. |
| Display Control | Select Display Mode | choice | Automatic | Select your Display Mode. |
| Display Control | Automatic (Default) | toggle | On | If checked, the Display Mode toggle can select Automatic mode. |
| Display Control | Single-Target | toggle | On | If checked, the Display Mode toggle can select Single-Target mode. |
| Display Control | AOE (Multi-Target) | toggle | On | If checked, the Display Mode toggle can select AOE mode. |
| Display Control | Dual | toggle | On | If checked, the Display Mode toggle can select Dual mode. |
| Display Control | Reactive Dual Display | toggle | On | If checked, the Display Mode toggle can select Reactive mode. |
| Troubleshooting | Pause | keybind | ALT-SHIFT-P | Set a key to pause processing of your action lists. |
| Troubleshooting | Pause | toggle | n/a | n/a |
| Troubleshooting | Snapshot | keybind | ALT-SHIFT-[ | Set a key to make a snapshot (without pausing) that can be viewed on the Snapshots tab. |
| Custom Toggles | Custom #1 | keybind | n/a | Set a key to toggle your first custom set. |
| Custom Toggles | Enable Custom #1 | toggle | Off | If checked, abilities linked to Custom #1 can be recommended. |
| Custom Toggles | Custom #1 Name | text | Custom #1 | Specify a descriptive name for this custom toggle. |
| Custom Toggles | Custom #2 | keybind | n/a | Set a key to toggle your second custom set. |
| Custom Toggles | Enable Custom #2 | toggle | Off | If checked, abilities linked to Custom #2 can be recommended. |
| Custom Toggles | Custom #2 Name | text | Custom #2 | Specify a descriptive name for this custom toggle. |

n/a: no keybind is set by default, or no description.
<!-- /GENERATED -->

## Display modes

- Automatic, Single-Target, AOE, Dual and Reactive Dual; the Display Mode keybind cycles through the checked ones. Source: `src/Hekili/Options/Options.lua` (displayModes)

## See also

- [Slash commands](Slash-Commands)
- [Abilities and items](Abilities-And-Items)
