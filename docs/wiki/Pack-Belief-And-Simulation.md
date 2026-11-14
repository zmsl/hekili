<!--
Purpose: The two layers: now for the belief, handler for the simulation, and bands.
Type: Explanation
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview).
-->
Hekili Forever keeps two models of the game, and a class pack describes each ability's effect once for each of them. The belief is the addon's running estimate of what has happened in the game, built from observed events. The simulation is the forecast of the casts ahead, which picks the recommendations. An ability's `now` function writes its effect into the belief; its `handler` function writes the same effect into the simulation. This page explains why there are two layers, how the two functions differ, and what the belief's estimates look like.

| Two layers | |
|---|---|
| Belief | What the addon believes happened, from observed events. Written by `now`. |
| Simulation | The forecast of future casts. Written by `handler`. |
| Read by both | The ability's declared fields: cost, cooldown, cast time, GCD, auras |
| Belief only | `now`, `onCrit`, `onLand`, `now_finish`, `refundOnAvoid`, reactions |
| Simulation only | `handler`, `start`, `tick`, `finish`, state functions and expressions |
| Source | `src/Hekili/Game/` (belief), `src/Hekili/Engine/Sim/` (simulation) |

## Two layers

The Forever client hides many values from addons: resources such as energy, rage and mana at all times, and cooldown times, aura durations and target health during combat. The game's own frames can show a hidden value, but an addon cannot read it, compare it or calculate with it ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)). The original Hekili read all of these values on every update, so its simulation cannot start from the game directly.

Hekili Forever keeps the original simulation and puts the belief in front of it.

- **The belief** starts from what the client still answers plainly: values read out of combat, the player's own casts, whether an ability is usable, and whether a cooldown is ready. It carries those values forward with the models the class pack registers (costs, regeneration, durations) and corrects itself whenever the client reveals something new. It lives in `src/Hekili/Game/`.
- **The simulation** is the original Hekili's forecast, in `src/Hekili/Engine/Sim/`. On each update the engine copies the belief into the simulated state, walks the active priority, picks the first ability whose conditions hold, advances the simulated clock past that cast, and walks the priority again. The repeated walk fills the queue of recommendations.

The belief answers "what is true now"; the simulation answers "what happens if the player presses these abilities". Both run pack code, and both need to know what an ability does.

## now and handler

An ability whose cast changes more than its cost, cooldown and GCD states that effect twice. Barkskin, in `src/Hekili_Druid/Druid.lua`, applies its buff in both layers (comments added for this page):

```lua
barkskin = {
    id = 22812,
    cast = 0,
    cooldown = 60,
    gcd = "spell",

    startsCombat = false,
    known = knows(BARKSKIN),
    toggle = "defensives",

    -- the belief: the player's cast succeeded, so the buff is up
    now = function()
        applyBuff("barkskin")
    end,

    -- the simulation: a forecast cast puts the buff up
    handler = function()
        applyBuff("barkskin")
    end,
},
```

The two functions look the same here, but they run in different places, at different times, with different names in scope.

| | `now` | `handler` |
|---|---|---|
| Layer | Belief | Simulation |
| Runs when | The client reports that the player's cast succeeded | The forecast casts the ability, possibly many times per update |
| Environment | The belief's `now` context (`src/Hekili/Game/State/Families/Now.lua`) | The simulated `state` (`src/Hekili/Engine/Sim/State.lua`) |
| Reads | Belief values at the cast's time | Simulated values at the forecast's time |
| Writes | Modelled samples, which any later observation overrides | The simulated state, discarded at the next update |

When the client reports a successful cast, the belief first writes the effects the ability declares as fields: it spends the cost, starts the cooldown or uses a charge, and starts the GCD. It then runs `now`, if there is one. So `now` holds only what the fields cannot say: an aura applied, a resource gained, another ability's cooldown reset.

### Why two functions

A Lua function has one environment. The engine binds a `handler` to the simulated `state` and binds a `now` to the belief's context, so one function cannot serve both. A bare name such as `buff`, `talent`, `energy` or `applyBuff` answers from whichever layer runs the function. The belief refuses a `now` that is the same function as the ability's `handler`: it counts an error and drops that `now`.

The two layers also need different things.

- **The simulation may use helpers the belief does not have.** Bear Form's `handler` calls the state function `swap_form`, registered with `RegisterStateFunction`, which exists only in the simulation. Its `now` writes the same steps out with the belief's verbs.
- **The belief has verbs the simulation does not need.** Shifting into Bear Form loses all rage and then gains a share from the Furor talent, which below the talent's last rank is a roll the addon cannot see. The belief records that as a range with `resetResource`; the simulation spends its low end and gains only the certain part.

From `src/Hekili_Druid/Druid.lua`, shortened:

```lua
bear_form = {
    -- ...
    now = function()
        for i = 1, #FORMS do
            removeBuff(FORMS[i])
        end
        removeBuff("maul")
        local f = talent.furor.rank
        resetResource("rage", f >= 5 and FUROR_RAGE or 0, f > 0 and f < 5 and FUROR_RAGE or 0)
        applyBuff("bear_form")
    end,

    handler = function()
        swap_form("bear_form")
    end,
},
```

The names each context offers are listed on [Pack environment names](Pack-Environment-Names).

### Rules for both

- Write `now` only when the cast changes more than its declared cost, cooldown and GCD. An ability with nothing more to say has a `handler` only, or neither. `tests/Forever/druid_spec.lua` checks the Druid's abilities against a list of the ones that need a `now`.
- Write both from the same source of truth. A duration or amount that depends on a talent, a rank or gear is computed the same way in each, usually through a shared table or the aura's own `duration` function. An `applyBuff` with no duration, in either layer, uses the aura's registered duration.
- A `now` never assigns a global. The context raises on any assignment, which counts as an error, so that one cast cannot shadow a verb for every later cast.
- A helper defined at file level keeps the file's environment, not the layer's. A class file that needs the known rank in a helper takes it once as `local rankOf = state.knownRank`, which gives the same answer in both layers, and passes anything else the helper needs as an argument.
- The ability fields a pack writes as functions (`spend`, `cooldown`, `cast`, `known`, `usable`, an aura's `duration`) run in the simulation under `state`. The belief evaluates the ones it prices with (`spend`, `cooldown`, `gcdTime`, an aura's `duration`) in its own context, so those read only names both contexts have.

### Fields with no twin

Some effects only the belief can see, because they depend on what happened: a critical hit, a dodge, a hit that landed. The simulation does not predict crits or avoidance. These fields have no simulation twin:

- `onCrit`: what a critical hit of the cast gives, written with the same verbs as `now`.
- `onLand`: what only a landed hit gives, run once the cast's hit is settled as landed.
- `now_finish`: a channel's twin of the simulation's `finish`, run when the channel ran to its end.
- `refundOnAvoid`: the share of the cost given back when the target dodges, parries or misses.
- Reactions (`RegisterReaction`): a `now` function run by an observed outcome instead of a cast ([Pack windows and reactions](Pack-Windows-And-Reactions)).

The simulation's `start`, `tick` and `finish` (a channel in progress) and its state functions and expressions have no belief twin, except `finish` through `now_finish`. Each field is described on [Pack abilities reference](Pack-Abilities-Reference).

> [!WARNING]
> **Different from retail Hekili:** A retail Hekili ability has only `handler`, because the original addon read the game state directly. An ability ported from a retail or Classic class file needs a `now` beside its `handler` wherever the cast changes more than its cost, cooldown and GCD. Without it the belief never learns of the effect, and the recommendations drift until the client reveals the truth.

## Bands

Each belief estimate of a hidden value is a band: a low end, a best guess and a high end, together with how the value was learned.

| Part | Meaning |
|---|---|
| Low end | The least the value can be, given everything observed |
| Best guess | The estimate the forecast starts from |
| High end | The most the value can be |
| How it was learned | Observed (read plainly), pinned by an event (such as a usability answer), or modelled (carried forward by the pack's models) |

A write from `now` is a modelled sample at the cast's time. A later observation overrides it: if the client reports that an ability cannot be used for lack of rage, the rage must be below its cost, and the band moves to agree. A `now` that is slightly wrong therefore corrects itself at the next observation, while a missing `now` leaves the belief wrong until then.

A resource exposes its band as `current` (the best guess), `lo` and `hi`, in both layers. The simulation carries the low end forward beside the estimate, and the check that a press is affordable reads the low end. A priority line that tests `energy.lo>=60` is therefore shown only when the energy is certain to be there ([APL expression reference](APL-Expression-Reference)).

> [!NOTE]
> **On Forever:** A resource the client reports plainly, such as combo points, has no band: all three parts read the same value.

## The facade

Neither layer calls the game client directly. Every read goes through the facade (`src/Hekili/Game/API/Facade.lua`), which a content addon reaches as `Hekili.Client`. A plain value passes through; a secret one is answered from the belief. A class file takes the client functions it needs from the facade at load:

```lua
local Facade = Hekili.Client
local C_Spell, UnitClassBase = Facade.C_Spell, Facade.UnitClassBase
```

A content addon never names a game API global. `make check` runs `tools/check_api_reads.sh`, which fails on a game API read outside the facade. This keeps one rule in one place: what the client hides, and how each hidden read is answered, is decided in the facade and the belief, not in each pack.

## See also

- [Glossary](Glossary)
- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack environment names](Pack-Environment-Names)
- [Pack tutorial: add an ability](Pack-Tutorial-Add-An-Ability)
- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
