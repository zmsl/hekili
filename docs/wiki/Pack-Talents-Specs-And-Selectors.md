<!--
Purpose: Talent ranks, spec ids, selectors and the automatic pick.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Talent ranks, spec ids, selectors and the automatic pick.

## Talents

- RegisterTalents entries are `{ tree, spell, max rank }`. Source: `src/Hekili/Engine/Schema/Spec/Kits.lua` (NewClass comment)

## Spec ids

- Ids are the addon's own: one per class tree slot. Source: `src/Hekili/Engine/Schema/Spec/Kits.lua`

## Selectors

- The first selector whose condition holds picks its spec and pack. Source: `src/Hekili/Engine/Schema/Spec.lua` (RegisterSelector), `src/Hekili/Engine/Schema/Selectors.lua`

## See also

- [Choosing a priority](Choosing-A-Priority)
