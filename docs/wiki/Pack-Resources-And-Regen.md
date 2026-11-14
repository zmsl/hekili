<!--
Purpose: RegisterResource, regeneration entries, swing rage, refunds.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
-->
A class pack declares each resource its class uses with `RegisterResource`: the power type, how the resource comes in (regeneration entries), and a few meta fields such as its base rate and its out-of-combat decay. The game hides energy, rage and mana from addons, so these declarations are what the belief uses to carry each estimate forward between observations, and what the simulation uses to forecast it. This page describes the call, every kind of regeneration entry, the meta fields and refunds.

| Resources | |
|---|---|
| Call | `kit:RegisterResource(powerType, regen, model, meta)` |
| Defined in | `src/Hekili/Engine/Schema/Spec/Regen.lua` |
| Belief side | `src/Hekili/Game/State/Families/Resources.lua` |
| Simulation side | `src/Hekili/Engine/Sim/State.lua` (the resource table, its forecast and its `lo` and `hi`) |
| Examples | Energy, combo points, rage and mana in `src/Hekili_Druid/Druid.lua`; rage in `src/Hekili_Warrior/Warrior.lua` |

## RegisterResource

```lua
kit:RegisterResource(powerType, regen, model, meta)
```

| Parameter | Meaning |
|---|---|
| `powerType` | The game's power type, such as `Enum.PowerType.Energy`. The resource's key (`energy`, `rage`, `mana`, `combo_points`) comes from it. |
| `regen` | A table of named regeneration entries, or nil ([below](#regeneration-entries)) |
| `model` | A replacement for the simulation's resource table. Packs pass nil. |
| `meta` | A table of meta fields, or nil ([below](#meta-fields)) |

The first resource a class registers is its primary resource, which an ability with no `spendType` pays. A resource the client reports plainly needs no entries. From `src/Hekili_Druid/Druid.lua`:

```lua
spec:RegisterResource(
    Enum.PowerType.Energy,
    { bear_pause = { aura = "bear_form", mult = 0 } },
    nil,
    { regen = 10, refundOnAvoid = 0.8 }
)
spec:RegisterResource(Enum.PowerType.ComboPoints)
```

Energy comes in at 10 a second, stops while Bear Form is up, and gives back 80% of an avoided ability's cost. Combo points are read plainly from the game and need nothing more.

In both layers the resource reads as `<key>.current` (the best guess), `<key>.lo` and `<key>.hi` (the ends of the belief's band), `<key>.max` and more ([APL expression reference](APL-Expression-Reference)).

## Regeneration entries

Each entry of `regen` has a name of the pack's choosing and one of four shapes. Functions in an entry run in the simulation under `state`; the belief reads the fields named below in its own context.

### Swing entries

A swing entry pays the resource on each white melee swing, as rage is paid. The belief steps the estimate at each observed swing and learns a scale from the client's answers; the simulation forecasts each swing.

| Field | Read by | Meaning |
|---|---|---|
| `swing` | Both | `"mainhand"` or `"offhand"`: the hand that pays |
| `aura` | Both | A player aura that must be up for a swing to pay, such as `"bear_form"` |
| `value` | Both | The amount one landed swing pays: a number or a function |
| `crit` | Both | The amount a critical swing pays instead |
| `taken` | Belief | `function(kind, amount, attacker)`: the resource gained from a hit on the player, as an expected gain and its half-width. The simulation forecasts the rate the belief learns from it. `kind` is `"WOUND"`, `"BLOCKED"`, `"BLOCK"`, `"DODGE"`, `"PARRY"` or `"MISS"`. |
| `last` | Simulation | The time of the last swing, from which the forecast steps |
| `interval` | Simulation | The swing period, such as `"mainhand_speed"` |
| `stop` | Simulation | True when no more swings pay |

From `src/Hekili_Druid/Druid.lua`, shortened: rage per white swing in Bear Form.

```lua
mainhand = {
    swing = "mainhand",
    aura = "bear_form",
    last = function() --[[ the last swing, from state.swings.mainhand ]] end,
    interval = "mainhand_speed",
    stop = function()
        return state.swings.mainhand == 0 or not state.buff.bear_form.up
    end,
    value = function()
        return BEAR_RAGE_RATE * BEAR_SWING
    end,
    crit = function()
        return BEAR_RAGE_RATE * BEAR_SWING + primalFury(talent.primal_fury.rank)
    end,
},
```

The Warrior's main-hand entry in `src/Hekili_Warrior/Warrior.lua` adds a `taken` function for rage from hits on the player.

### Aura entries

An aura entry pays a fixed amount every `interval` seconds while a player aura is up, as Enrage pays 2 rage a second. Without `aura`, it pays in combat.

| Field | Read by | Meaning |
|---|---|---|
| `aura` | Both | The player aura that must be up |
| `interval` | Both | Seconds between payments |
| `value` | Both | The amount of each payment: a number or a function |
| `talent` | Both | A talent that must be taken |
| `pausesDecay` | Belief | True when the out-of-combat decay stops while the aura is up |
| `last` | Simulation | The time of the last payment |

From `src/Hekili_Druid/Druid.lua`:

```lua
enrage = {
    aura = "enrage",
    last = function()
        local app = state.buff.enrage.applied
        return app + floor(state.query_time - app)
    end,
    interval = 1,
    value = 2,
},
```

### Rate entries

A rate entry changes the continuous rate while a player aura is up. It has `aura` and any of four rate fields, which follow wowsims's mana model.

| Field | Meaning |
|---|---|
| `mult` | The whole rate times this. 0 stops the resource, as Bear Form stops energy. |
| `spirit` | The spirit part of the rate times this, a number or a function |
| `share` | This share of the spirit part continues inside the five-second rule, added to the meta's `share` and capped at all of it |
| `mp5` | This much more a second, inside and outside the five-second rule |

From `src/Hekili_Druid/Druid.lua`: Innervate makes the spirit regeneration five times as fast and lets all of it continue while casting.

```lua
innervate = { aura = "innervate", spirit = 5, share = 1 },
```

A rate entry is not a forecast event: the simulation takes the belief's current rate as constant over its forecast, so it does not see a rate aura end in the middle of the forecast.

A race applies a rate entry with `race:RegisterRegenMod({ resource, aura, ... })` ([Pack API reference](Pack-API-Reference#resources)).

## Meta fields

| Field | Type | Meaning |
|---|---|---|
| `max` | number or function | The maximum. Without it, 100. |
| `regen` | number | The base rate a second, which the belief uses until it reads a plain rate. Energy needs it, because the game hides energy even out of combat. |
| `base` | number | The pool's base power at the class's top level. A cost between 0 and 1, or any cost of an ability with `spendBase`, is that share of it, rounded down. The belief replaces it with the player's own once it reads a plain cost. Without it, a share is of the maximum. |
| `decay` | function | The amount lost a second out of combat |
| `decayInterval` | function | The seconds between decay steps; with `decay`, the decay is stepped |
| `fsr` | table | The five-second rule's parts ([below](#the-five-second-rule)) |
| `refundOnAvoid` | number | The class's default share of an avoided ability's cost given back ([below](#refunds)) |

From `src/Hekili_Druid/Druid.lua`, rage decays 1.25 a second out of combat, in one-second steps:

```lua
{
    decay = function()
        return 1.25
    end,
    decayInterval = function()
        return 1
    end,
    refundOnAvoid = 0.8,
}
```

### The five-second rule

A resource with an `fsr` meta field splits its continuous regeneration into two parts, each learned on its own:

- the spirit part, which stops for five seconds after the player spends the resource;
- the `mp5` part, which never stops.

```lua
fsr = { spirit = 22, mp5 = 0 },
base = 1244,
```

Each part is a rate a second, a number or a function read when the class is built; the declared values are a starting point that the belief replaces with what it reads out of combat. An optional `share` (0 to 1) is the part of the spirit regeneration that continues while casting. The rule is the belief's only; a priority cannot read `fsr`.

> [!NOTE]
> **On Forever:** The game hides mana even out of combat. The estimate starts at full and moves with the player's spending and the declared regeneration, until a usability answer shows that it is lower.

## Refunds

Some abilities give back part of their cost when the target dodges, parries or misses them. Two declarations work together:

1. The resource's meta field `refundOnAvoid` sets the class's default share, such as `0.8`.
2. The ability declares `refundOnAvoid = true` to use that share, or a number for its own share.

From `src/Hekili_Druid/Druid.lua`, Bash refunds 80% of its rage on an avoid:

```lua
bash = {
    -- ...
    spend = 10,
    spendType = "rage",
    refundOnAvoid = true,
},
```

The refund is the belief's only. The simulation does not predict avoidance, so it never reads the field. When the client reports the avoid, the belief also removes the target debuffs the cast's `now` applied.

## See also

- [Pack belief and simulation](Pack-Belief-And-Simulation)
- [Pack abilities reference](Pack-Abilities-Reference)
- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
