<!--
Purpose: Which priority runs and why, choosing another, handing the choice back.
Type: How-to
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Which priority runs and why, choosing another, handing the choice back.

## Which priority runs

- Each specialization has a default priority; a selector can pick one from your talents. Source: `src/Hekili/Engine/Schema/Selectors.lua`, `src/Hekili/Engine/Schema/Spec.lua` (RegisterSelector)
- The full list is on [Supported classes and priorities](Supported-Classes-And-Priorities).

## Choose another priority

- The Priority choice on the specialization page, or `/hekili priority <name>`. Source: `src/Hekili/Options/ChatCommands.lua` (HandlePriorityCommand)

## Hand the choice back

- `/hekili priority default` returns to the built-in default and lets the selectors pick again. Source: `src/Hekili/Options/ChatCommands.lua` (HandlePriorityCommand)

## Choose the specialization

- `/hekili spec <name>` activates a specialization for the current talent tree. Source: `src/Hekili/Options/ChatCommands.lua` (HandleSpecCommand)

## See also

- [Specializations reference](Specializations-Reference)
- [APL wowsims packs explained](APL-wowsims-Packs-Explained)
