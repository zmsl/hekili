<!--
Purpose: Rotation windows as they work in the released version.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Rotation windows as they work in the released version.

## What a window is

- A named span a class addon registers and a priority opens and reads. Source: `src/Hekili/Engine/Schema/Spec.lua` (RegisterWindow), `docs/dev/architecture.md` (section 3)

## Reading a window

- `window.<name>` expressions. TODO: list the fields from the code. Source: `src/Hekili/Engine/Sim/State.lua`

## Opening and closing

- `open_window` and `close_window` lines. Source: `docs/dev/architecture.md` (section 3)

## See also

- [Pack windows and reactions](Pack-Windows-And-Reactions)
