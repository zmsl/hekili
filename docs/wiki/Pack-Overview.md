<!--
Purpose: What a class addon is, load order, the content API version, the core and pack boundary.
Type: Explanation
Audience: Lua developers
Prerequisites: Lua 5.1.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. What a class addon is, load order, the content API version, the core and pack boundary.

## What a class addon is

- One addon per class: its kit (abilities, auras, talents) and its generated priorities. Source: `DEVELOPMENT.md` (section 3)

## Load order

- The core loads the shared content, then the class addon, on demand. Source: `src/Hekili/Engine/Content.lua`, `tests/helpers/addons.lua`

## The content API version

- `X-Hekili-ContentAPI` in the class addon's TOC must equal the core's CONTENT_API. Source: `src/Hekili/Engine/Content.lua`

## The core and pack boundary

- The core names no class, spell or aura; packs use only the registration API. Source: `tests/boundary_spec.lua`, `DEVELOPMENT.md` (The hard rules)

## See also

- [Pack class file anatomy](Pack-Class-File-Anatomy)
- [Pack API reference](Pack-API-Reference)
- [Contributing architecture](Contributing-Architecture)
