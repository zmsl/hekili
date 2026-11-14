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
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Class | Specializations | Key | Label | Type | Default |
|---|---|---|---|---|---|
| Warrior | Arms, Fury | `wowsims_recklessness` | Recklessness (wowsims.com) | toggle | Off |
| Warrior | Arms | `wowsims_stance_dance` | Stance Dance (wowsims.com) | toggle | Off |
| Warrior | Arms | `maintain_thunder_clap` | Maintain Thunder Clap | toggle | Off |
| Warrior | Fury | `wowsims_rend_weave` | Rend Weave (wowsims.com) | toggle | On |
| Warrior | Protection | `maintain_demoralizing_shout` | Maintain Demoralizing Shout | toggle | Off |
| Druid | Balance, Feral, Guardian | `behind` | Always Behind | toggle | Off |
| Druid | Feral, Guardian | `maintain_demoralizing_roar` | Maintain Demoralizing Roar | toggle | Off |
| Priest | Shadow | `prefer_starshards` | Prefer Starshards | toggle | Off |
| Warlock | Affliction, Demonology, Destruction | `assigned_curse` | Assigned Curse | choice | Curse of the Elements |
<!-- /GENERATED -->

## See also

- [Specializations reference](Specializations-Reference)
