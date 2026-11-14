<!--
Purpose: Move, size and style displays; choose a style; set visibility in and out of combat.
Type: How-to
Audience: players
Prerequisites: [Getting started](Getting-Started).
-->
This page shows how to move a display, change its size and look, choose between the Classic and Timeline styles, and set when it shows and how transparent it is. What each part of a display means is explained in [Reading the displays](Reading-The-Displays).

## Before you start

- Leave combat. The displays cannot be unlocked in combat, and some options cannot be changed during it.
- Each display has its own settings, under **/hekili > Displays**. Click a display's name to open its page, or click **Multiple** to change several displays at once.

## Move a display

1. Type `/hekili move`. The displays unlock and show.
2. Drag a display by its first icon to where you want it.
3. Type `/hekili lock`.

The options window unlocks the displays too: while it is open, every display shows and can be dragged. To place a display exactly, set **X** and **Y** on its **Icons** tab. They are measured from the centre of the screen.

## Choose the style

1. Open **/hekili > Displays > Primary**, or another display.
2. On the **Icons** tab, choose **Style**: Classic, a row of icons, or Timeline, a circle, a box and a lane.
3. The tabs after **Icons** change with the style. The style's own settings are on its **Style** tab.

## Size and number of icons

- **Icons Shown**, on the **Icons** tab, sets how many recommendations the Classic style shows, from 1 to 10. Each extra icon shows one step further ahead.
- In the Classic style, the size of the first icon is **Width** and **Height** in the first section of the **Style** tab, and the size of the queued icons is under **Queued Icon Size**. **Grow Direction** and **Icon Spacing** set where the queue goes.
- In the Timeline style, each part has its own size: the **Now** circle, the **Next** box and the icons on the **Lane**, each on its own tab.
- The font of all text on every display is set under **/hekili > Displays**, with **Font**, **Size**, **Style** and **Color**. Each element's own text settings, such as the keybind's, are on the display's **Style** tab.

## Visibility and transparency

The **Visibility** tab sets when a display shows.

- **PvE Alpha** and **PvP Alpha** set the transparency in each kind of content. At 0, the display does not appear there.
- Check **Advanced** for finer control. Each kind of content then has its own **Default**, **Target**, **Combat** and **Combat w/ Target** transparency, and **Hide When Mounted**.

## Modern overlays

The **Modern** tab adds the game's own cooldown swipes, a grey icon when the game says an ability cannot be used yet, and a glow when the game lights an ability. Check **Modern (game truth)** to turn it on for that display. It is marked experimental. If you use **Proc Glow**, turn the style's own **Enable Overlay Glow** off, so that the same ability does not glow twice.

## Check that it works

Close the options and target an enemy. The display shows at its new place, in its new style and size. Out of combat with no target, a display shows at the **Default** transparency when **Advanced** is checked.

<!-- TODO-SCREENSHOT: a display's Style tab -->

## Share a style

**Share Styles**, under **/hekili > Displays**, makes an export string of the chosen displays' settings, or applies one. [Profiles and sharing](Profiles-And-Sharing) has the steps.

## See also

- [Displays reference](Displays-Reference): every display option, with its default
- [Action Bar Glow](Action-Bar-Glow)
