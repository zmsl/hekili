<!--
Purpose: What carried over, what is new and what is gone, for players of the original.
Type: Explanation
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. What carried over, what is new and what is gone, for players of the original.

## What carried over

- The simulation of the next few seconds, the displays, toggles, priorities and snapshots. Source: `DEVELOPMENT.md` (section 1)

## What is new

- Estimated values where the game hides them; recommendations can appear a moment later. Source: `DEVELOPMENT.md` (section 1)
- Built-in priorities are generated from wowsims.com. Source: `docs/dev/wowsims-packs.md`
- The game's Cooldown Manager as a source of aura times. Source: `src/Hekili/Options/Options.lua` (the Cooldown Manager panel)
- `/hekili spec` chooses the specialization for the current talent tree. Source: `src/Hekili/Options/ChatCommands.lua` (HandleSpecCommand)

## What is gone

- `pool_resource` is accepted but ignored: the forecast already waits for resources. Source: `src/Hekili/Engine/Sim/Core.lua`
- Time to die always reads 3600 seconds. Source: `src/Hekili/Engine/Sim/State.lua` (fight_remains, time_to_die)
- SpellFlash support was removed. Source: `CHANGELOG.md`

## Why recommendations can lag

- A line waits until the low end of an estimate covers its cost. Source: `src/Hekili/Engine/Sim/State.lua` (mt_resource lo)

## See also

- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
- [APL Forever differences](APL-Forever-Differences)
