<!--
Purpose: What each display and icon element means: Primary, AOE, Cooldowns, Interrupts, Defensives; Classic and Timeline styles.
Type: Explanation
Audience: players
Prerequisites: None.
-->
The **displays** are the on-screen frames where Hekili Forever shows its recommendations: the ability to press now and the ones expected to follow. There are five built-in displays. Each one draws in one of two styles, Classic (a row of icons) or Timeline (a circle, a box and a lane of upcoming abilities). This page explains what each display and each part of an icon means. To move, size or restyle a display, see [Setting up displays](Setting-Up-Displays).

## The displays

| Display | What it shows |
|---|---|
| **Primary** | The main recommendations. Its first icon is the ability to press now. |
| **AOE** | Recommendations planned for two or more enemies. It shows only in the Dual and Reactive Dual display modes ([Toggles](Toggles#display-modes)). |
| **Cooldowns** | Abilities that need the **Major Cooldowns** toggle, when that toggle is set to show them separately. |
| **Interrupts** | Interrupts, when the **Interrupts** toggle is set to show them separately. |
| **Defensives** | Defensive abilities, when the **Defensives** toggle is set to show them separately. |

With the default settings, everything appears in the **Primary** display, and the **Cooldowns**, **Interrupts** and **Defensives** displays stay empty. While the options window is open, every display shows, so that it can be placed.

Each recommendation is worked out by simulating the next few seconds of the fight: Hekili Forever takes the first ability in the priority whose conditions hold, moves its simulated clock past that cast, and looks again. So the second icon is the ability expected after the first, and so on. A later icon is a forecast; it can change when the fight does.

## The Classic style

The Classic style is the original Hekili's look: a row of icons. The first icon is the largest; the queued icons follow it. The **Primary** display shows three icons by default.

<!-- TODO-SCREENSHOT: the Primary display in the Classic style with each element numbered -->

Each part of an icon has a meaning:

- **Keybind text**, top right by default: the key bound to that ability on the action bars. With a gamepad, the controller button picture shows there instead.
- **Target count**, bottom right of the first icon: the number of enemies counted, shown only when there is more than one ([How targets are counted](How-Targets-Are-Counted)).
- **Cooldown spiral**: the time until the ability can be used. When the ability should wait even after it is ready, the spiral can run on until the moment to press it (**Extend Spiral**).
- **Delay indicator**: when the ability should be pressed a little later, a coloured icon or a countdown can show the wait (**Indicator**, on the **Delays** tab).
- **Red tint**: the ability, or melee range, is out of reach (the **Range** tab).
- **Glow**: the game itself is lighting the ability, for example after a proc (**Enable Overlay Glow**).
- **Indicators**, at the right edge: a small mark, for example when the ability should be used on a different target.
- **Caption**: a short note that some priority lines attach to an ability. Captions are off by default.

## The Timeline style

The Timeline style lays the recommendations out along time:

- The **Next** box holds the ability to press now, with its keybind.
- The **Now** circle holds a focus ability that is coming up: an ability that a priority marks as worth watching, such as a buff to refresh or a proc to use. It counts down until the ability is ready, and its ring changes colour when it is time to press it. With no focus ability coming up, the circle stays empty by default (**Without Focus**).
- The **Lane** places the abilities after that by how far ahead they are, so it shows what is coming and when.

When Hekili Forever cannot be sure that a resource will be there in time, the Timeline can show the abilities the priority would pick instead, stacked beside the cell (**Show Alternatives**). A pick on the lane that is still short of its resource is marked (**Resource Gate**).

<!-- TODO-SCREENSHOT: the Primary display in the Timeline style with each element numbered -->

## Modern overlays

The **Modern** tab of each display adds what the game itself shows about an ability, on top of either style. It is off by default and marked experimental. Hekili Forever still decides which abilities to show; the overlays only change how they look.

- **Real Cooldown Swipes**: the game's own cooldown on the icon, in place of Hekili Forever's estimate.
- **Grey When Not Usable**: the icon turns grey as soon as the game reports that the ability cannot be used yet, for example for lack of resources.
- **Proc Glow**: the next ability glows when the game lights it.

## Why an icon can appear late

The game hides several values from addons, among them energy, rage and mana. Hekili Forever estimates them, and shows an ability only when it is sure the cost is covered. An icon can therefore appear a moment after the ability becomes usable. [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know) explains which values are estimated.

## See also

- [Displays reference](Displays-Reference): every display option
- [Action Bar Glow](Action-Bar-Glow): the same recommendations on your own action buttons
