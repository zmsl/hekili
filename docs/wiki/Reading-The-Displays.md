<!--
Purpose: What each display and icon element means: Primary, AOE, Cooldowns, Interrupts, Defensives; Classic and Timeline styles.
Type: Explanation
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. What each display and icon element means: Primary, AOE, Cooldowns, Interrupts, Defensives; Classic and Timeline styles.

## The displays

- Primary, AOE, Cooldowns, Interrupts and Defensives; Cooldowns, Interrupts and Defensives fill only when their toggle shows them separately. Source: `src/Hekili/Options/Options.lua` (displays)

## The icon row

- The first icon is the next ability; the queue follows. Keybind text, the target count (bottom right, when more than one) and captions. Source: `src/Hekili/UI/Styles/Classic.lua`
- TODO-SCREENSHOT: the Primary display in the Classic style with each element numbered

## The Timeline style

- Now, Next and Lane elements. Source: `src/Hekili/UI/Styles/Timeline.lua`
- TODO-SCREENSHOT: the Primary display in the Timeline style with each element numbered

## Modern overlays

- Real Cooldown Swipes, Grey When Not Usable and Proc Glow read what the game shows. Source: `src/Hekili/UI/Truth.lua`

## See also

- [Setting up displays](Setting-Up-Displays)
- [Displays reference](Displays-Reference)
