<!--
Purpose: What the game's Cooldown Manager gives Hekili Forever, and the per-aura switches.
Type: Explanation
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. What the game's Cooldown Manager gives Hekili Forever, and the per-aura switches.

## What it provides

- Hekili Forever reads the Cooldown Manager to see when your buffs and debuffs are up. Source: `src/Hekili/Options/Options.lua` (the Cooldown Manager panel intro)

## The per-aura switches

- One switch per aura; gold: on a bar, grey: not. Changes apply after combat. Source: `src/Hekili/Options/Options.lua` (cdm)
- TODO-SCREENSHOT: the Cooldown Manager panel with gold and grey switches

## Effect on accuracy

- The live-like column of [Accuracy](Accuracy) assumes the Cooldown Manager shows none of your auras.

## See also

- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
