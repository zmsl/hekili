<!--
Purpose: Every aura field.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
-->
An **aura** is one entry of `RegisterAuras` (or one `RegisterAura` call): a buff on the player or a debuff on the target, under a key such as `barkskin`. Priorities read it as `buff.<key>` or `debuff.<key>`, and both layers write it with `applyBuff`, `applyDebuff` and the other aura verbs. This page lists the fields an aura may declare. The tables were written by hand from the core's source and the shipped class files.

| Aura | |
|---|---|
| Registered by | `kit:RegisterAuras({ [key] = data })`, `kit:RegisterAura(key, data)`; the shared and race objects' `RegisterAura` |
| Defined in | `src/Hekili/Engine/Schema/Spec/Auras.lua` |
| Read by | The simulation (`src/Hekili/Engine/Sim/State.lua`) and the belief (`src/Hekili/Game/State/Families/Auras.lua`) |
| Defaults | `duration` 30 seconds, `max_stack` 1 |
| Example | `barkskin = { id = 22812, duration = 15, max_stack = 1 }` in `src/Hekili_Druid/Druid.lua` |

## How fields are evaluated

A field declared as a function runs with the simulated `state` as its environment each time it is read, except `generate`, which the simulation calls itself. The belief evaluates a `duration` function in its own context when a `now` applies the aura without a duration, so a duration that depends on a talent, a rank or gear is written once, on the aura, and both layers agree. From `src/Hekili_Druid/Druid.lua`:

```lua
faerie_fire = {
    id = 770,
    copy = { 778, 9749, 9907 },
    duration = function()
        return 40 + (set_bonus.haruspex_3pc > 0 and 5 or 0)
    end,
    max_stack = 1,
},
```

Every aura that an ability, a `now`, a state function, a resource entry or an alias names must be registered.

## Identity and timing

| Field | Type | Meaning |
|---|---|---|
| `id` | number | The aura's spell ID, which the belief tracks. Without one, the aura gets a negative pseudo-ID and only the simulation knows it. |
| `copy` | number, string or list | Other spell IDs (other ranks, or a cast ID beside the buff's) or keys the aura answers to |
| `duration` | number or function | Its length in seconds. Use 3600 for an aura that lasts until removed, such as a form. |
| `max_stack` | number or function | The most stacks it can hold |
| `tick_time` | number or function | The time between ticks of a periodic effect. Multiplied by the spell haste unless `tick_fixed` is set. |
| `tick_fixed` | boolean | `tick_time` is not multiplied by haste |
| `dot` | string | `"debuff"` or `"buff"`: marks a periodic effect. A debuff with `tick_time` and `dot = "debuff"` is what a ticking `expects` reads ([Pack expects and outcomes](Pack-Expects-And-Outcomes)). |
| `shared` | string | `"player"` or `"target"`: the aura counts whoever applied it, read on that unit, instead of only the player's own |
| `texture` | number | The icon, when it should not come from the spell |

## Aliases

An alias aura answers for a group of other auras, so a priority can test one name.

| Field | Type | Meaning |
|---|---|---|
| `alias` | list | The keys of the auras it stands for |
| `aliasType` | string | `"buff"` or `"debuff"` |
| `aliasMode` | string | `"first"` (the first member that is up; the default), `"longest"` or `"shortest"` (the member with the most or least time left) |

From `src/Hekili_Druid/Druid.lua`:

```lua
bleed = {
    alias = { "rake", "rip", "pounce_bleed", "lacerate" },
    aliasType = "debuff",
    aliasMode = "longest",
},
```

## Proc limits and charges

| Field | Type | Meaning |
|---|---|---|
| `icd` | number | The aura can be applied at most once per this many seconds, measured from its last application (its proc's internal cooldown). Priorities read `buff.<key>.icd_remains` and `buff.<key>.icd_ready`. Without `icd`, or never applied, it reads ready. |
| `icdSpell` | number | The spell ID that wowsims names the internal cooldown by, for the translator |
| `consumedBy` | set | Kinds of hit on the player that each spend one stack: `WOUND`, `BLOCKED`, `BLOCK`, `DODGE`, `PARRY`, `MISS`, `HEAL`, `DEFLECT`, `EVADE`. Belief only. |
| `consumeIcd` | number | Limits `consumedBy` to one stack per this many seconds from the last spend |

From `src/Hekili_Druid/Druid.lua`, Clearcasting procs at most once every 10 seconds:

```lua
clearcasting = {
    id = 16870,
    duration = 15,
    max_stack = 1,
    icd = 10,
    icdSpell = 16864,
},
```

From `src/Hekili_Shaman/Shaman.lua`, each landed or blocked hit on the player spends a stack of Water Shield:

```lua
water_shield = { id = 408510, duration = 600, max_stack = 3, consumedBy = { WOUND = true, BLOCKED = true } },
```

## How the belief reads an aura

These fields tell the belief where to read an aura that the game hides or reports in another way. They are belief only.

| Field | Type | Meaning |
|---|---|---|
| `overlay` | number | A player proc aura read from that spell's glow on the action bar while the aura itself cannot be read: up while it glows, down once it stops |
| `isStealthed` | boolean | The player aura follows the client's stealth state |
| `weaponEnchant` | number | On an aura without `id`: up while that weapon slot (0 main hand, 1 off hand) carries a lasting enchant, such as an imbue or a poison |
| `enchants` | list | On an aura without `id`: up while either weapon carries one of these enchant IDs |
| `swingHaste` | number | While the aura is up in combat, every melee hand swings this many times faster |
| `family` | string | A name the pack gives each aura of a set the game shows as one Cooldown Manager entry, one of them up at a time (the Paladin seals, the Druid forms). The entry's light says some member is up and its silence that none is; the member is the one the belief holds up (the last cast). A member the entry took down comes back if the entry lights again within 2 seconds. The name is only compared. |

> [!NOTE]
> **On Forever:** The game hides aura durations during combat. The belief times an aura from the cast that applied it and the registered `duration`, and corrects it from what the game still shows, including the game's Cooldown Manager ([Cooldown Manager](Cooldown-Manager)). A wrong `duration` shows up as an aura that falls too early or too late in the forecast.

## Simulation fields

| Field | Type | Meaning |
|---|---|---|
| `generate` | function | Fills the aura's simulated state when it is read, instead of the game's answer. The shared dispel auras use it. |
| `meta` | table | Extra fields computed by functions, read as `buff.<key>.<field>` |

## See also

- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack belief and simulation](Pack-Belief-And-Simulation)
- [APL expression reference](APL-Expression-Reference)
