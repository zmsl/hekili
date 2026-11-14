<!--
Purpose: RegisterSetting, toggle and choice settings, how a priority reads settings.x.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. RegisterSetting, toggle and choice settings, how a priority reads settings.x.

## RegisterSetting

- `RegisterSetting( key, value, option, ... )`: on the kit, every supported spec (or the specs named after `option`). Source: `src/Hekili/Engine/Schema/Spec.lua`

## Reading a setting

- A priority reads `settings.<key>`. Source: `src/Hekili/Engine/Sim/State.lua` (mt_settings)

## Every class setting

<!-- GENERATED:pack-settings -->
<!-- /GENERATED -->

## See also

- [Specializations reference](Specializations-Reference)
