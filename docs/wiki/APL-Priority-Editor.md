<!--
Purpose: Every field of the Priorities editor, and which do nothing on Forever.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Every field of the Priorities editor, and which do nothing on Forever.

## Every field

<!-- GENERATED:options-editor -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Field | Type | Values | Description |
|---|---|---|---|---|
| Summary | Active | toggle | n/a | If checked, the addon's recommendations for this specialization are based on this priority package. |
| Summary | Priority Name | text | n/a | n/a |
| Summary | Specialization | choice | Arms; Fury; Protection | n/a |
| Summary | Description | text | n/a | n/a |
| Source | Source | text | n/a | If the Priority is based on a SimulationCraft profile or a popular guide, it is a good idea to provide a link to the source (especially before sharing). |
| Source | Author | text | n/a | The author field is automatically filled out when creating a new Priority. |
| Source | Last Updated | text | n/a | This date is automatically updated when any changes are made to the action lists for this Priority. |
| Source | Priority (SimulationCraft Action Priority List) | text | n/a | If this pack's action lists were imported from a SimulationCraft profile, the profile is included here. |
| Source | Import | button | n/a | Clear existing action list(s) and load the priority above. |
| Source | Import Log | text | n/a | n/a |
| Action Lists | Action List | choice | cd_racials; default; pre_pull_move; pre_pull_stance; precombat; sunder_armor | Select the action list to view or modify. |
| Action Lists | Entry | choice | 31 choices | Select the entry to modify in this action list. |
| Action Lists | List Name | text | n/a | n/a |
| Action Lists | Add List | button | n/a | n/a |
| Action Lists | Cancel | button | n/a | n/a |
| Action Lists | Enabled | toggle | n/a | If disabled, this entry will not be shown even if its criteria are met. |
| Action Lists | Create New Entry | button | n/a | n/a |
| Action Lists | Action | choice | 61 choices | Select the action that will be recommended when this entry's criteria are met. |
| Action Lists | Action Name | choice | 61 choices | Specify the action to cancel; the result is that the addon will allow the channel to be removed immediately. |
| Action Lists | Buff Name | choice | 29 choices | Specify the buff to remove. |
| Action Lists | Action List | choice | cd_racials; pre_pull_move; pre_pull_stance; precombat; sunder_armor | n/a |
| Action Lists | Max Energy | toggle | n/a | When checked, this entry will require that the player have enough energy to trigger Ferocious Bite's full damage bonus. |
| Action Lists | Potion | choice | Default | n/a |
| Action Lists | Seconds | text | n/a | n/a |
| Action Lists | Window Name | choice | n/a | Specify the rotation window to open or close. |
| Action Lists | Caption | text | n/a | Captions are very short descriptions that can appear on the icon of a recommended ability. |
| Action Lists | Label | text | n/a | Text shown on the recommendation while the Label Condition (if any) holds, e.g. |
| Action Lists | Label Condition | text | n/a | If entered, the Label shows only while this is true. |
| Action Lists | Icon | text | n/a | A texture file ID or path to show on the recommendation in place of the ability's icon while the Icon Condition (if any) holds. |
| Action Lists | Icon Condition | text | n/a | If entered, the Icon shows only while this is true. |
| Action Lists | Description | text | n/a | This allows you to provide text that explains this entry, which will show when you Pause and mouseover the ability to see why this entry was recommended. |
| Action Lists | Variable Name | text | n/a | Specify a name for this variable. |
| Action Lists | Operation | choice | 14 choices | n/a |
| Action Lists | Pool for Next Entry ([Call Action List]) | toggle | n/a | If checked, the addon will pool resources until the next entry has enough resources to use. |
| Action Lists | Extra Pooling | text | n/a | Specify the amount of extra resources to pool in addition to what is needed for the next entry. |
| Action Lists | Pooling Time | text | n/a | Specify the time, in seconds, as a number or as an expression that evaluates to a number. |
| Action Lists | Conditions | text | n/a | Specify Conditions that must be met for this action to be recommended or used in generating recommendations. |
| Action Lists | Value | text | n/a | Provide the value to store (or calculate) when this variable is invoked. |
| Action Lists | Value when Conditions are Not Met | text | n/a | Provide the value to store (or calculate) if Conditions are not met. |
| Action Lists | Cycle Targets | toggle | n/a | If checked, the addon will check each available target and show whether to switch targets. |
| Action Lists | Max Cycle Targets | text | n/a | If cycle targets is checked, the addon will check up to the specified number of targets. |
| Action Lists | Check Movement | toggle | n/a | If checked, this entry can only be recommended when your character movement matches the setting. |
| Action Lists | Movement | choice | Stationary; Moving | If set, this entry can only be recommended when your movement matches the setting. |
| Action Lists | Use Off GCD | toggle | n/a | If checked, this entry can be checked even if the global cooldown (GCD) is active. |
| Action Lists | Use While Casting | toggle | n/a | If checked, this entry can be checked even if you are already casting or channeling. |
| Action Lists | During Channel | toggle | n/a | If checked, this entry can only be used if you are channeling another spell. |
| Action Lists | Focus Tier | slider | 0 to 5, step 1 | Timeline style: 0 is off; a tier (1 highest) makes this entry a focus candidate. |
| Action Lists | Entry Cooldown | text | n/a | If set, this entry cannot be recommended unless this time has passed since the last time the ability was used. |
| Action Lists | Test Conditions Immediately | toggle | n/a | If checked, the Conditions (above) must be met immediately for this action to be recommended or used. |
| Action Lists | Additional Immediate Criteria | text | n/a | If entered, these Immediate Criteria must be met before the Conditions above will be tested. |
| Action Lists | Show Unused Modifiers (if applicable) | toggle | n/a | If checked, additional modifiers that are not currently used by this entry. |
| Export | Priority Export String | text | n/a | Press CTRL+A to select, then CTRL+C to copy. |
| Export | Stress Test Results | text | n/a | n/a |

n/a: free text, or no description.
<!-- /GENERATED -->

## Fields that do nothing on Forever

- TODO: verify each pooling field (Max Energy) against the engine. Source: `src/Hekili/Engine/Sim/Core.lua`

## See also

- [APL line options](APL-Line-Options)
- [APL tutorial your first custom priority](APL-Tutorial-Your-First-Custom-Priority)
