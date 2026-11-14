<!--
Purpose: Copy a built-in, change a line, test it with a snapshot, export it.
Type: Tutorial
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Copy a built-in, change a line, test it with a snapshot, export it.

## What you will have at the end

- A copy of a built-in priority with one changed line, active and exported. TODO: the time it takes.

## Copy a built-in priority

- TODO: the steps in the Priorities panel. Source: `src/Hekili/Options/Options.lua` (newPackHeader, createNewPack)
- TODO-SCREENSHOT: the new-priority fields

## Change a line

- The editor's Action Lists tab. Source: `src/Hekili/Options/Options.lua`

## Test it

- Take a snapshot and read the changed line. See [Reading a snapshot](Reading-A-Snapshot).

## Export it

- Export on the priority's page. Source: `src/Hekili/Options/Options.lua` (exportString)

## Next steps

- A copy does not follow updates of the built-in it came from. Source: `docs/dev/wowsims-packs.md`

## See also

- [APL priority editor](APL-Priority-Editor)
- [APL debugging](APL-Debugging)
