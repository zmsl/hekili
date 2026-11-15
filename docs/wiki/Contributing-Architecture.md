<!--
Purpose: The layers and the hard rules, with links to the repository docs.
Type: Explanation
Audience: contributors
Prerequisites: [Contributing](Contributing).
-->
The **architecture** of Hekili Forever is a stack of layers, each of which talks only to its neighbours: a facade that alone reads the game client, a belief that estimates what the client hides, the engine that simulates the priority, an output that publishes recommendations, and the subscribers that show them. Class content sits beside the stack and reaches the engine only through a registration interface. This page explains the layers and the rules that keep them apart. The full reference is [docs/dev/architecture.md](https://github.com/zmsl/hekili/blob/forever/docs/dev/architecture.md) in the repository, and [docs/dev/layout.md](https://github.com/zmsl/hekili/blob/forever/docs/dev/layout.md) describes every folder.

## Why it is built this way

The WoW Forever client hides many combat values from addons: resources, cooldown times, aura durations, target health. Such a value is **secret**: an addon can pass it to the game's own frames, but cannot read it, compare it or calculate with it. There is no combat log. The original Hekili read all of these values on every update, so it cannot work as written.

Hekili Forever keeps the original's simulation and class model, and replaces the hidden reads with an estimate. The layers exist so that only one place touches the client, only one place keeps estimates, and the simulation never needs to know which values were read and which were estimated ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)).

## The layers

| Layer | Where | What it does |
|---|---|---|
| Facade | `src/Hekili/Game/API/Facade.lua` | The only code that calls the game client. Exposed to content as `Hekili.Client`. |
| Belief | `src/Hekili/Game/State/`, `src/Hekili/Game/Events/` | The running estimate of the game state, built from what the facade reads and the events it sees |
| Engine | `src/Hekili/Engine/` | The registration interface (`Schema/`), the simulation (`Sim/`), the driver that schedules updates, the output and the debug snapshot |
| Output | `src/Hekili/Engine/Output.lua` | The recommendation records of each display, and their publish and subscribe |
| Subscribers | `src/Hekili/UI/`, `src/Hekili/Integrations/` | The displays and the WeakAuras bridge, and the headless test loop |
| Options | `src/Hekili/Options/` | The saved profile and the options panels; hands the settings to the engine |
| Content addons | `src/Hekili_Shared/`, `src/Hekili_<Class>/` | Abilities, auras, talents and priorities, declared through the registration interface |

### The facade

The facade is the only code that calls the game's API. When the client answers a value plainly, the facade returns it. When the answer is secret, the facade answers from the belief instead, in the same shape as the client's own answer. Code above it therefore reads one interface whether the value was read or estimated.

### The belief

A **belief** is the estimate of one hidden value: a **band** (a low end, a best guess and a high end), together with how it was learned: observed, pinned by an event, or modelled.

- It starts from values the client still answers plainly: out-of-combat reads, the player's own casts, "is this spell usable" answers and cooldown-ready flags.
- It carries them forward with the same models the class pack registers: costs, regeneration, durations.
- When the client reveals something new, such as an ability turning unusable for lack of resources, the band moves to agree.

The belief never reads the engine's state. What it needs from the class packs arrives as plain records when a specialization loads.

### The engine and the output

On each update the engine copies the belief into its simulated state, walks the active priority, and advances the simulated clock to fill the queue ([APL overview](APL-Overview)). It writes the result as a set of recommendation records per display and publishes them. Every display, the WeakAuras bridge and the test loop subscribe to those records; none of them reads the simulation ([Contributing display styles and integrations](Contributing-Display-Styles-And-Integrations)).

### Content addons

`Hekili_Shared` holds what every class uses, such as racials, consumables and items. Each `Hekili_<Class>` addon is a class pack: one class file with the class's abilities, auras, talents and settings, and its generated priorities. A class pack calls `Hekili:NewClass`, `Hekili:NewShared` or `Hekili:NewRace` and the `Register*` calls on the object they return, and nothing else of the core ([Pack overview](Pack-Overview)).

## The hard rules

These rules hold for every change to the core. The checks in `make check` enforce most of them.

- **The core is generic.** The core names no class, spell, aura, talent, form or rotation. It works only with what packs declare through the registration interface, and packs use only that interface, never the core's internals. A boundary test scans both sides. A few simulation files inherited from the original Hekili still carry class names; each is held to a count that may only fall.
- **Secret safety.** Only the facade reads the client. A value is never compared or calculated with unless it is known to be plain: test it with the client's secret check first, or take it from the belief.
- **No allocation on recurring paths.** Code that runs on every update or combat event creates no tables, closures or strings. It reuses records allocated once. Allocation tests cover the belief, the driver and the output.
- **The layering.** The client is read through the facade, turned into a belief, simulated by the engine and published to subscribers. The displays and options never read the simulation. The engine never reads the displays or the saved profile directly.
- **The belief and the core stay apart.** The belief imports nothing from the engine, and the engine reads the belief only through the facade, except at a few named calls that a check allows and nothing else.

## See also

- [Glossary](Glossary)
- [Pack belief and simulation](Pack-Belief-And-Simulation)
- [Contributing](Contributing)
