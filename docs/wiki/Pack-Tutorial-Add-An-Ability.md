<!--
Purpose: Add an ability and its aura end to end, with a test.
Type: Tutorial
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview), a bootstrapped checkout ([Contributing](Contributing)).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Add an ability and its aura end to end, with a test.

## What you will have at the end

- An ability and its aura registered, both layers written, a test, a green `make check`.

## Register the aura

- RegisterAura. Source: `src/Hekili/Engine/Schema/Spec/Auras.lua`

## Register the ability

- RegisterAbility, with `now` and `handler`. Source: `src/Hekili/Engine/Schema/Spec/Abilities.lua`

## Write a test

- A headless spec. Source: `tests/Forever/`

## Run the checks

- `make check`, then `make gate`. Source: `Makefile`

## Next steps

- See [Pack testing and gates](Pack-Testing-And-Gates).

## See also

- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack auras reference](Pack-Auras-Reference)
