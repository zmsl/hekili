<!--
Purpose: What a priority is, lists, the walk and the forecast, and why each evaluation stands alone.
Type: Explanation
Audience: theorycrafters
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. What a priority is, lists, the walk and the forecast, and why each evaluation stands alone.

## What a priority is

- An action priority list (APL): the text form of a priority, in the SimulationCraft dialect the original Hekili read. Source: `src/Hekili/Engine/Sim/Scripts.lua`

## Lists

- `precombat`, the default list and named lists; `call_action_list` and `run_action_list`. Source: `src/Hekili/Engine/Sim/Core.lua`

## The walk and the forecast

- Pick the first line whose conditions hold, advance the simulated clock past it, walk again. Source: `DEVELOPMENT.md` (section 1)

## Each evaluation stands alone

- No evaluation depends on an earlier one; there is no pooling state. Source: `src/Hekili/Engine/Sim/Core.lua` (pool_resource)

## See also

- [APL syntax reference](APL-Syntax-Reference)
- [APL expression reference](APL-Expression-Reference)
- [APL tutorial your first custom priority](APL-Tutorial-Your-First-Custom-Priority)
