<!--
Purpose: Line grammar, operators and precedence, lists, variables, comments.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Line grammar, operators and precedence, lists, variables, comments.

## Line grammar

- `actions+=/<action>,<option>=<value>,...` and `actions.<list>+=/...`. Source: `tools/make_pack.lua`, `src/Hekili/Engine/Schema/Spec/Packs.lua`

## Operators and precedence

- TODO: table from the translation to Lua. Source: `src/Hekili/Engine/Sim/Scripts.lua` (SimToLua, HandleDeprecatedOperators)

## Lists

- `call_action_list`, `run_action_list`. Source: `src/Hekili/Engine/Sim/Core.lua`

## Variables

- `variable,name=...,value=...`, read as `variable.<name>`. Source: `src/Hekili/Engine/Sim/Scripts.lua`

## Comments

- TODO: the `#` description header. Source: `tools/make_pack.lua`

## See also

- [APL expression reference](APL-Expression-Reference)
- [APL line options](APL-Line-Options)
