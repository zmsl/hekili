<!--
Purpose: Take a snapshot, capture Lua errors, and open a useful issue.
Type: How-to
Audience: players with a problem
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Take a snapshot, capture Lua errors, and open a useful issue.

## Take a snapshot

- `/hekili snapshot` or the Snapshot keybind (ALT-SHIFT-[ by default) while the problem is on screen; copy it from the Snapshots tab. Source: `src/Hekili/Engine/Snapshot.lua`, `src/Hekili/Options/Options.lua` (snapshots)
- TODO-SCREENSHOT: the Snapshots tab with a snapshot selected

## Capture Lua errors

- TODO: the game's error display or an error-catching addon. Source: `src/Hekili/Options/Options.lua` (errors)

## Open an issue

- At [github.com/zmsl/hekili/issues](https://github.com/zmsl/hekili/issues), with class, specialization, level, version, what you expected and what you saw, and the snapshot. Never to the original Hekili project. Source: `README.md`
- Include: the Hekili Forever version, class, specialization and level; what you expected and what you saw; the snapshot (paste it or attach the file); any Lua error text. Report here, on GitHub, and nowhere else.

## See also

- [Reading a snapshot](Reading-A-Snapshot)
- [Troubleshooting and FAQ](Troubleshooting-And-FAQ)
