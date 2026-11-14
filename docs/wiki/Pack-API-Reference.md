<!--
Purpose: Every Register* call: parameters and an example.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Every Register* call: parameters and an example.

## Every call

<!-- GENERATED:register-api -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Call | Parameters | Offered by | Used by |
|---|---|---|---|
| `RegisterAbilities` | `abilities` | class | Warrior, Druid, Rogue, Paladin, Shaman, Hunter, Mage, Priest, Warlock |
| `RegisterAbility` | `ability, data` | class, shared, race | Shared, Warrior |
| `RegisterAura` | `aura, data` | class, shared, race | Shared |
| `RegisterAuras` | `auras` | class | Warrior, Druid, Rogue, Paladin, Shaman, Hunter, Mage, Priest, Warlock |
| `RegisterCombatLogEvent` | `func` | class | n/a |
| `RegisterCostMod` | `def` | class, shared, race | Shared, Druid, Rogue, Shaman, Mage, Priest |
| `RegisterCycle` | `func` | class | n/a |
| `RegisterEvent` | `event, func` | class | Warrior, Shaman, Hunter |
| `RegisterGcdMod` | `def` | class | Druid |
| `RegisterGear` | `...` | class | Druid, Paladin, Shaman, Hunter, Warlock |
| `RegisterHook` | `hook, func, noState` | class | Warrior, Druid, Rogue, Shaman, Hunter |
| `RegisterOptions` | `options` | class | n/a |
| `RegisterPack` | `name, version, import` | class | Warrior, Druid, Rogue, Paladin, Shaman, Hunter, Mage, Priest, Warlock |
| `RegisterPet` | `token, id, spell, duration, ...` | class | n/a |
| `RegisterPets` | `pets` | class | Hunter, Warlock |
| `RegisterPhase` | `key, start, finish, ...` | class | n/a |
| `RegisterPhasedVariable` | `key, default, value, ...` | class | n/a |
| `RegisterPotion` | `potion, data` | class | n/a |
| `RegisterPotions` | `potions` | class | n/a |
| `RegisterPower` | `power, id, aura` | class | n/a |
| `RegisterPowers` | `powers` | class | n/a |
| `RegisterPriority` | `name, version, notes, priority` | class | n/a |
| `RegisterPvpTalents` | `pvp` | class | n/a |
| `RegisterRangeFilter` | `name, func` | class | n/a |
| `RegisterRanges` | `...` | class | n/a |
| `RegisterReaction` | `name, data` | class | Warrior, Paladin |
| `RegisterRecheck` | `func` | class | n/a |
| `RegisterRegenMod` | `def` | race | Shared |
| `RegisterResource` | `resourceID, regen, model, meta` | class | Warrior, Druid, Rogue, Paladin, Shaman, Hunter, Mage, Priest, Warlock |
| `RegisterResourceMod` | `def` | shared, race | Shared |
| `RegisterSelector` | `key, target, condition` | class | Druid, Paladin, Mage, Warlock |
| `RegisterSetBonus` | `key, spellID` | class | Druid, Paladin, Hunter, Warlock |
| `RegisterSetBonuses` | `...` | class | n/a |
| `RegisterSetting` | `key, value, option, ...` | class | Warrior, Druid, Priest, Warlock |
| `RegisterStateExpr` | `key, func` | class, shared | Shared, Warrior, Druid, Paladin, Shaman, Hunter, Warlock |
| `RegisterStateFunction` | `key, func` | class | Warrior, Druid |
| `RegisterStateTable` | `key, data` | class | Rogue |
| `RegisterTalents` | `talents` | class | Warrior, Druid, Rogue, Paladin, Shaman, Hunter, Mage, Priest, Warlock |
| `RegisterTotem` | `token, id, ...` | class | n/a |
| `RegisterTotems` | `totems` | class | Shaman |
| `RegisterUnitEvent` | `event, unit1, unit2, func` | class | n/a |
| `RegisterVariable` | `key, func` | class | n/a |
| `RegisterWindow` | `name, data` | class | Rogue, Paladin, Hunter |

Offered by: the registration object (class: Hekili:NewClass; shared: Hekili:NewShared; race: Hekili:NewRace). n/a: no parameters, or no content addon calls it.
<!-- /GENERATED -->

## Examples

- TODO: one example per call, from a shipped class file. Source: `src/Hekili_*/`

## See also

- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack auras reference](Pack-Auras-Reference)
- [Pack settings](Pack-Settings)
