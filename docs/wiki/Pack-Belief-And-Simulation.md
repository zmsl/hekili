<!--
Purpose: The two layers: now for the belief, handler for the simulation, and bands.
Type: Explanation
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. The two layers: now for the belief, handler for the simulation, and bands.

## Two layers

- The belief (the running estimate of hidden values) and the simulation. Source: `DEVELOPMENT.md` (section 1), `docs/dev/architecture.md` (section 1)

## now and handler

- An ability writes its effect twice: `now` for the belief, `handler` for the simulation. Source: `src/Hekili_Druid/Druid.lua`

## Bands

- Each estimate is low, best guess and high, plus how it was learned. Source: `DEVELOPMENT.md` (section 1)

## The facade

- `Hekili.Client` is the only window on the game. Source: `docs/dev/architecture.md`

## See also

- [Glossary](Glossary)
- [Pack abilities reference](Pack-Abilities-Reference)
