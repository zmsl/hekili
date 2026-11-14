<!--
Purpose: Make the next ability glow on your action bars.
Type: How-to
Audience: players
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Make the next ability glow on your action bars.

## Turn it on

- Displays > Action Bar Glow > Enabled; off by default. Source: `src/Hekili/Options/Options.lua` (GetDefaults barGlow), `src/Hekili/UI/BarGlow.lua`

## Choose what glows

- Follow Display (default Primary), Now Color (gold), Glow the next recommendation and Next Color (blue), In Combat Only (on). Source: `src/Hekili/Options/Options.lua` (GetDefaults barGlow)

## Check that it works

- The button that casts the first recommendation glows, even with the display hidden.
- TODO-SCREENSHOT: an action bar with a gold and a blue glow

## See also

- [Displays reference](Displays-Reference)
