<!--
Purpose: Nameplates, damage detection and target swaps, and why counts differ on Forever.
Type: Explanation
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Nameplates, damage detection and target swaps, and why counts differ on Forever.

## Your target

- Your target is always counted. Source: `src/Hekili/Engine/Sim/Targets.lua`

## Nameplates

- Enemies with a nameplate within Enemy Range Radius count; beyond 10 yards only enemies in combat count. Source: `src/Hekili/Engine/Sim/Targets.lua`, `src/Hekili/Options/Options.lua` (nameplateRange)

## Damaged enemies

- Count Damaged Enemies finds fewer targets on Forever: the game does not report the hits landed on other enemies. TODO: date the measurement. Source: `src/Hekili/Engine/Sim/Targets.lua`

## Target swaps

- Allow Target Swaps and Filter by Time-to-Die; time to die reads 3600 on Forever. Source: `src/Hekili/Options/Options.lua` (cycle, cycle_min)

## See also

- [Setting up target counting](Setting-Up-Target-Counting)
- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
