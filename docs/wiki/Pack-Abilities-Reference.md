<!--
Purpose: Every ability field.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
-->
An **ability** is one entry of `RegisterAbilities` (or one `RegisterAbility` call): a spell, an item or an action the player can press, under a key such as `barkskin`. This page lists the fields an ability may declare, grouped by what they do. Each field is a value or a function; a function is evaluated when the field is read. The tables were written by hand from the core's source and the shipped class files.

| Ability | |
|---|---|
| Registered by | `kit:RegisterAbilities({ [key] = data })`, `kit:RegisterAbility(key, data)`; the shared and race objects' `RegisterAbility` |
| Defined in | `src/Hekili/Engine/Schema/Spec/Abilities.lua` |
| Read by | The simulation (`src/Hekili/Engine/Sim/State.lua`) and the belief (`src/Hekili/Game/State/Families/Casts.lua`, `Now.lua`, `Expect.lua`) |
| Defaults | `cast` 0, `cooldown` 0, `recharge` equal to `cooldown`, `charges` 1 |
| Example | Barkskin in `src/Hekili_Druid/Druid.lua` ([Pack tutorial: add an ability](Pack-Tutorial-Add-An-Ability)) |

## How fields are evaluated

A field declared as a function runs in the simulation with the simulated `state` as its environment, each time the field is read, so `talent.ferocity.rank` or `buff.bear_form.up` inside it answers for the simulated moment. The effect functions `handler`, `start`, `tick`, `finish` and `impact` are not evaluated on read: the simulation calls them when the matching event happens.

The belief reads the declared fields it needs to model a cast (cost, cooldown, charges, GCD, cast time, swing fields) and evaluates `spend`, `cooldown` and `gcdTime` functions in its own context, falling back to a value computed under `state` if one raises. It runs `now`, `onCrit`, `onLand` and `now_finish` in its own context. Write those functions with names both contexts have ([Pack environment names](Pack-Environment-Names)).

`known` is cached for a whole prediction, so it must depend only on the spellbook, talents and gear, never on buffs or time.

## Identity

| Field | Type | Meaning |
|---|---|---|
| `id` | number | Rank 1's spell ID. Without one, the ability gets a negative pseudo-ID (an item ability gets its own range). |
| `copy` | number, string or list | The other ranks' spell IDs, in rank order, or other keys the ability answers to |
| `name` | string | The name shown, when it should not come from the spell's own name |
| `listName` | string | The text the options' ability list shows |
| `texture` | number | The icon, when it should not come from the spell |
| `unlisted` | boolean | Leaves the ability out of the options' ability list |
| `item` | number | The item ID of an item ability; the ability is usable only while the item is worn, unless `bagItem` is set |
| `items` | list | More item IDs that count as the same ability |
| `bagItem` | boolean | The item is used from the bags, not worn |
| `passive` | boolean | A spell the spellbook knows and the player never casts. With `passive = true` and a numeric `id`, nothing else is registered: the belief tracks its known rank, and the simulation never sees it. |

## Cost

| Field | Type | Meaning |
|---|---|---|
| `spend` | number or function | The cost. A value between 0 and 1 is a share of the resource's base power ([Pack resources and regen](Pack-Resources-And-Regen#meta-fields)); any other value is points. |
| `spendType` | string | The resource paid, such as `"energy"`, `"rage"` or `"mana"`. Without it, the class's primary resource. |
| `spendBase` | boolean | Reads `spend` as a share of base power at any size, for a percent cost that an aura can raise past 100% |
| `refundOnAvoid` | boolean or number | The share of the cost given back when the target dodges, parries or misses. `true` uses the resource's default share. Belief only. |
| `ladder` | boolean | `false`: the client's usability answers for this ability do not bound the resource. Use it when the answer depends on something else, such as a finisher that is unusable at 0 combo points. |

A proc that makes abilities cheaper is a cost modifier (`RegisterCostMod`), not a condition in `spend` ([Pack API reference](Pack-API-Reference#cost-and-gcd-modifiers)).

## Timing

| Field | Type | Meaning |
|---|---|---|
| `cast` | number or function | The cast time in seconds; 0 for an instant. A number is multiplied by the spell haste. |
| `fixedCast` | boolean | The numeric `cast` is not multiplied by haste |
| `channeled` | boolean | The cast is a channel; `cast` is its length |
| `cooldown` | number or function | The cooldown in seconds |
| `hasteCD` | boolean | A numeric `cooldown` and `recharge` are multiplied by haste |
| `charges` | number or function | The number of charges; 1 for none |
| `recharge` | number or function | The time to regain one charge |
| `gcd` | string or function | `"spell"` (the 1.5 second GCD, shortened by haste), `"totem"` (a fixed 1 second GCD) or `"off"` (no GCD) |
| `gcdTime` | number or function | A fixed GCD length that overrides the kind's |
| `readyTime` | number or function | An extra wait before the ability is ready, in seconds |
| `timeToReady` | number or function | The same, read after the aura waits below |
| `icd` | number | The least time between two casts |
| `onNextSwing` | boolean | The ability replaces the next melee swing, as a queued attack. It is unusable beyond melee range. |
| `rangedSwing` | boolean | The ability is the ranged auto attack: its cast is the ranged hand's shot |

A GCD that an aura shortens is a GCD modifier (`RegisterGcdMod`), not a condition in `gcd`.

## Availability

These fields decide whether the ability is known, usable and shown.

| Field | Type | Meaning |
|---|---|---|
| `known` | boolean or function | Whether the player has the ability. Usually true when the spellbook knows any rank. Cached per prediction. |
| `talent` | string or list | The talents it needs |
| `notalent` | string or list | Talents that rule it out |
| `equipped` | string | Gear it needs, read as `equipped.<key>` |
| `usable` | boolean, number or function | A function returns `false, reason` when the ability cannot be used. A number is a spell ID the client is asked about. |
| `form` | string or function | The form or stance aura it needs, such as `"bear_form"`. A function returns the key. |
| `noform` | string | A form it cannot be used in |
| `buff` | string or list | Player auras that must be up |
| `debuff` | string or list | Target auras that must be up |
| `nobuff` | string or list | Player auras that must be down; the simulation waits until they fall |
| `nodebuff` | string or list | Target auras that must be down; the simulation waits until they fall |
| `usable_on` | list | The target creature types it works on, such as `{ "undead", "demon" }`. An unknown type never blocks it. |
| `healthGate` | number | The client allows the ability only at or below this share of the target's health. The belief reads the client's answers for it as bounds on the target's health. |
| `range` | number | The greatest range in yards, checked when the range filter is on |
| `rangeSpell` | number | The spell ID to ask the client about for range |
| `nomounted` | boolean | Not recommended while mounted |
| `nocombat` | boolean | Not usable in combat |
| `toggle` | string | The toggle it sits under: `"cooldowns"`, `"defensives"`, `"interrupts"`, `"potions"` and the others on [Toggles](Toggles) |
| `startsCombat` | boolean | Casting it starts combat with the target |
| `essential` | boolean | A precombat line with this ability is still considered once combat has started |

Declare a form requirement with `form`, never through `buff` or a `usable` function; `tests/Forever/forms_spec.lua` checks this.

## Effect

| Field | Layer | When it runs |
|---|---|---|
| `handler` | Simulation | The forecast's cast completes |
| `now` | Belief | The client reports the player's cast succeeded, after the cost, cooldown and GCD are written |
| `onCrit` | Belief | The target's row shows a critical hit by this cast |
| `onLand` | Belief | The cast's hit is settled as landed; never on an avoid, and never for `expects = "none"` |
| `start` | Simulation | A channel starts |
| `tick` | Simulation | A channel ticks |
| `finish` | Simulation | A channel finishes |
| `now_finish` | Belief | A channel ran to its believed end |
| `impact` | Simulation | A projectile lands (`velocity` or `flightTime` set) |

`now` and `handler`, and `now_finish` and `finish`, must be separate functions: the belief refuses a pair that is one function. Why each effect is written twice is explained on [Pack belief and simulation](Pack-Belief-And-Simulation).

> [!NOTE]
> **On Forever:** The game hides the amounts and kinds of most hits on the target, so `onCrit` and `onLand` run only where a hit's row is plain. Treat them as corrections, not as the only source of an effect the recommendations need.
<!-- UNVERIFIED: that onCrit rarely runs in the game follows the architecture notes on hidden target rows (onLand is documented so); not measured in game for onCrit. -->

## Outcome

These fields tell the belief what the cast's hit looks like, so that it can pay each hit, miss or tick it sees to the right cast. They are described on [Pack expects and outcomes](Pack-Expects-And-Outcomes).

| Field | Type | Meaning |
|---|---|---|
| `expects` | string | `"none"`, `"instant"`, `"debuff"`, `"travel"`, `"strike"`, `"ticks"` or `"channel"` |
| `school` | string | `"physical"`, `"holy"`, `"fire"`, `"nature"`, `"frost"`, `"shadow"` or `"arcane"` |
| `velocity` | number | A projectile's speed in yards a second |
| `flightTime` | number | A projectile's fixed flight time in seconds |
| `missable` | boolean or string | A miss leaves the debuff off the target: `true` for the debuff of the ability's own key, or another debuff's key |
| `cycle` | string | The debuff that a target swap or a ticking kind reads, when it is not the ability's own key |
| `aura` | string | The aura the ability applies, when it is not the ability's own key |

## Other fields

The original Hekili's ability table has more fields (for example `dual_cast`, `channeling`, `max_targets`, `noOverride`, `spec`, `nospec` and `suffix`). The core still reads them, but no shipped pack uses them. A field the core does not read is kept on the ability and ignored.

## See also

- [Pack auras reference](Pack-Auras-Reference)
- [Pack expects and outcomes](Pack-Expects-And-Outcomes)
- [Pack belief and simulation](Pack-Belief-And-Simulation)
- [Pack environment names](Pack-Environment-Names)
