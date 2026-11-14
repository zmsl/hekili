<!--
Purpose: Nothing shows, wrong keybinds, recommendations lag, old data after an upgrade.
Type: How-to
Audience: players with a problem
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Nothing shows, wrong keybinds, recommendations lag, old data after an upgrade.

## Nothing shows

- No class addon for your class: `/hekili spec` says so. Source: `src/Hekili/Options/ChatCommands.lua` (HandleSpecCommand)
- A class addon from another version is refused, with a chat notice. Source: `src/Hekili/Engine/Content.lua`
- The specialization has no priorities on Forever. Source: `src/Hekili/Engine/Schema/Spec/Kits.lua` (unsupported)

## Wrong keybinds

- Override Keybind Text on the ability's page. Source: `src/Hekili/Options/Options.lua` (abilities)

## Recommendations lag

- Hidden values are estimated. See [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know).

## Old data after an upgrade

- Built-in priorities are replaced on upgrade, with a chat notice; `/hekili priority default` returns to the default. Source: `src/Hekili/Engine/Schema/Spec/Packs.lua` (RestoreDefaults)

## See also

- [Reporting a problem](Reporting-A-Problem)
- [Reading a snapshot](Reading-A-Snapshot)
