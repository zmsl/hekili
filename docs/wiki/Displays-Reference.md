<!--
Purpose: Every option on the Displays pages and style tabs.
Type: Reference
Audience: everyone
Prerequisites: None.
Status: stub (phase 1). Each bullet is a fact to write up, with its source. Write to the Style-Guide page.
-->
TODO: the lead. Every option on the Displays pages and style tabs.

## Options for every display

<!-- GENERATED:options-displays-all -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Option | Type | Default | Values | Description |
|---|---|---|---|---|
| Multiple | button | n/a | n/a | n/a |
| Primary | button | n/a | n/a | n/a |
| AOE | button | n/a | n/a | n/a |
| Cooldowns | button | n/a | n/a | n/a |
| Defensives | button | n/a | n/a | n/a |
| Interrupts | button | n/a | n/a | n/a |
| Notification Panel | button | n/a | n/a | The Notification Panel provides brief updates when settings are changed or toggled while in combat. |
| Font | choice | Fonts\ARIALN.TTF | 11 choices | n/a |
| Size | slider | 12 | 8 to 64, step 1 | n/a |
| Style | choice | Outline | Monochrome; Monochrome, Outline; Monochrome, Thick Outline; None; Outline; Thick Outline | n/a |
| Color | colour | #FFFFFF | n/a | n/a |
| Action Bar Glow | button | n/a | n/a | Preferences for the glow around your action bar buttons. |
| Share Styles | button | n/a | n/a | Your display styles can be shared with other addon users with these export strings. |

n/a: no default value (a button), no range, or no description.
<!-- /GENERATED -->

## Icons

- Shown for the Primary display; the other displays have the same options.

<!-- GENERATED:options-display-icons -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Option | Type | Default | Values | Description |
|---|---|---|---|---|---|
| Icons | Enabled | toggle | On | n/a | If disabled, this display will not appear under any circumstances. |
| Icons | Style | choice | Classic | Classic; Timeline | Select how this display draws its recommendations. |
| Icons | Icons Shown | slider | 3 | 1 to 10, step 1 | Specify the number of recommendations to show. |
| Icons | Forecast Period | slider | 15 | 1.5 to 15, step 0.1 | Specify the amount of time that the addon can look forward to generate a recommendation. |
| Position | X | slider | 0 | -640 to 640, step 1 | Set the horizontal position for this display's primary icon relative to the center of the screen. |
| Position | Y | slider | -225 | -360 to 360, step 1 | Set the vertical position for this display's primary icon relative to the center of the screen. |
| Icons | Apply ElvUI Cooldown Style to Primary Icon | toggle | Off | n/a | If ElvUI is installed, you can apply the ElvUI cooldown style to your queued icons. |
| Display Frame Layer | Strata | choice | LOW | BACKGROUND; LOW; MEDIUM; HIGH; DIALOG; FULLSCREEN; FULLSCREEN_DIALOG; TOOLTIP | Frame Strata determines which graphical layer that this display is drawn on. |

n/a: no fixed default (a keybind not set, or a value that follows the game or another option), no range, or no description.
<!-- /GENERATED -->

## Classic style

<!-- GENERATED:options-display-classic -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Option | Type | Default | Values | Description |
|---|---|---|---|---|---|
| Icons > Primary Icon | Width | slider | 50 | 10 to 500, step 1 | Specify the width of the primary icon for your Primary Display. |
| Icons > Primary Icon | Height | slider | 50 | 10 to 500, step 1 | Specify the height of the primary icon for your Primary Display. |
| Icons > Primary Icon | Icon Zoom | slider | 30 | 0 to 100, step 1 | Select the zoom percentage for the icon textures in this display. |
| Icons > Primary Icon | Keep Aspect Ratio | toggle | On | n/a | If your primary or queued icons are not square, checking this option will prevent the icon textures from being stretched and distorted, trimming some of the texture instead. |
| Icons > Queued Icon Size | Width | slider | 50 | 10 to 500, step 1 | Select the width of the queued icons. |
| Icons > Queued Icon Size | Height | slider | 50 | 10 to 500, step 1 | Select the height of the queued icons. |
| Icons > Queued Icon Positioning | Anchor To | choice | Right | 12 choices | Select the point on the primary icon to which the queued icons will attach. |
| Icons > Queued Icon Positioning | Grow Direction | choice | Right | Down; Left; Right; Up | Select the direction for the icon queue. |
| Icons > Queued Icon Positioning | X Offset | slider | 5 | -100 to 500, step 1 | Specify the horizontal offset (in pixels) for the queue, in relation to the anchor point on the primary icon for this display. |
| Icons > Queued Icon Positioning | Y Offset | slider | 0 | -100 to 500, step 1 | Specify the vertical offset (in pixels) for the queue, in relation to the anchor point on the primary icon for this display. |
| Icons > Queued Icon Positioning | Icon Spacing | slider | 5 | -50 to 50, step 1 | Select the number of pixels between icons in the queue. |
| Icons | Apply ElvUI Cooldown Style to Queued Icons | toggle | Off | n/a | If ElvUI is installed, you can apply the ElvUI cooldown style to your queued icons. |
| Border | Enabled | toggle | On | n/a | If enabled, each icon in this display will have a thin border. |
| Border | Border Thickness | slider | 1 | 1 to 20, step 1 | Determines the thickness (width) of the border. |
| Border | Border Inside | toggle | Off | n/a | If enabled, when borders are enabled, the button's border will fit inside the button (instead of around it). |
| Border | Coloring Mode | choice | Specify a Custom Color | Class #ffffff; Specify a Custom Color | Specify whether to use Class or Custom color borders. |
| Border | Custom Color | colour | 0 | n/a | When borders are enabled and the Coloring Mode is set to Custom Color, the border will use this color. |
| Range | Enabled | toggle | On | n/a | If enabled, the addon will provide a red warning highlight when you are not in range of your enemy. |
| Range | Range Checking | choice | Per Ability | Per Ability; Melee Range; Exclude Out-of-Range | Select the kind of range checking and range coloring to be used by this display. |
| Glows | Enable Overlay Glow | toggle | On | n/a | If enabled, when the ability for the first icon has an active glow (or overlay), it will also glow in this display. |
| Glows | Enabled for Queued Icons | toggle | Off | n/a | If enabled, abilities that have active glows (or overlays) will also glow in your queue. |
| Glows | Glow Style | choice | AutoCast Shine | AutoCast Shine; Default Button Glow; Pixel Glow | Select the glow style for your display. |
| Glows | Coloring Mode | choice | Use Default Color | Class #ffffff; Specify a Custom Color; Use Default Color | Select the coloring mode for this glow effect. |
| Glows | Glow Color | colour | 0.95 | n/a | Select the custom glow color for your display. |
| Glows | Enable Action Highlight | toggle | On | n/a | If enabled, the addon will apply the default highlight when the first recommended item/ability is currently queued. |
| Keybinds | Enabled | toggle | On | n/a | n/a |
| Keybinds | Enabled for Queued Icons | toggle | On | n/a | n/a |
| Keybinds > Position | Anchor Point | choice | Top Right | 9 choices | n/a |
| Keybinds > Position | X Offset | slider | 1 | -50 to 50, step 1 | n/a |
| Keybinds > Position | Y Offset | slider | -1 | -50 to 50, step 1 | n/a |
| Keybinds > Font and Style | Font | choice | Fonts\ARIALN.TTF | 11 choices | n/a |
| Keybinds > Font and Style | Style | choice | Outline | Monochrome; Monochrome, Outline; Monochrome, Thick Outline; None; Outline; Thick Outline | n/a |
| Keybinds > Font and Style | Size | slider | 12 | 8 to 64, step 1 | n/a |
| Keybinds > Font and Style | Color | colour | 1 | n/a | n/a |
| Keybinds | Use Lowercase | toggle | Off | n/a | n/a |
| Keybinds | Use Different Settings for Queue | toggle | Off | n/a | n/a |
| Keybinds > Queued Font and Style | Font | choice | Fonts\ARIALN.TTF | 11 choices | n/a |
| Keybinds > Queued Font and Style | Style | choice | Outline | Monochrome; Monochrome, Outline; Monochrome, Thick Outline; None; Outline; Thick Outline | n/a |
| Keybinds > Queued Font and Style | Size | slider | 12 | 8 to 64, step 1 | n/a |
| Keybinds > Queued Font and Style | Color | colour | 1 | n/a | n/a |
| Keybinds | Use Lowercase in Queue | toggle | Off | n/a | n/a |
| Gamepad > Position | Anchor Point | choice | Top Right | 9 choices | n/a |
| Gamepad > Position | X Offset | slider | 1 | -50 to 50, step 1 | n/a |
| Gamepad > Position | Y Offset | slider | -1 | -50 to 50, step 1 | n/a |
| Gamepad > Position | Size | slider | 12 | 8 to 64, step 1 | The size of the controller button pictures, in pixels. |
| Gamepad > ConsolePort | Use ConsolePort Buttons | toggle | n/a | n/a | n/a |
| Gamepad > ConsolePort | ConsolePort Button Zoom | slider | n/a | 0 to 1, step 0.01 | The ConsolePort button textures generally have a significant amount of blank padding around them. |
| Captions | Enabled | toggle | Off | n/a | If enabled, when the first ability shown has a descriptive caption, the caption will be shown. |
| Captions | Enabled for Queued Icons | toggle | Off | n/a | If enabled, descriptive captions will be shown for queued abilities, if appropriate. |
| Captions > Position | Anchor Point | choice | Bottom | Bottom; Top | n/a |
| Captions > Position | X Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Captions > Position | Y Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Captions > Position | Alignment | choice | Center | Center; Left; Right | n/a |
| Captions > Text | Font | choice | Fonts\ARIALN.TTF | 11 choices | n/a |
| Captions > Text | Style | choice | Outline | Monochrome; Monochrome, Outline; Monochrome, Thick Outline; None; Outline; Thick Outline | n/a |
| Captions > Text | Size | slider | 12 | 8 to 64, step 1 | n/a |
| Captions > Text | Color | colour | 1 | n/a | n/a |
| Targets | Enabled | toggle | On | n/a | If enabled, the addon will show the number of active (or virtual) targets for this display. |
| Targets > Position | Anchor To | choice | Bottom Right | 9 choices | n/a |
| Targets > Position | X Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Targets > Position | Y Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Targets > Text | Font | choice | Fonts\ARIALN.TTF | 11 choices | n/a |
| Targets > Text | Style | choice | Outline | Monochrome; Monochrome, Outline; Monochrome, Thick Outline; None; Outline; Thick Outline | n/a |
| Targets > Text | Size | slider | 12 | 8 to 64, step 1 | n/a |
| Targets > Text | Color | colour | 1 | n/a | n/a |
| Delays | Extend Spiral | toggle | On | n/a | If checked, the primary icon's cooldown spiral will continue until the ability should be used. |
| Delays | Fade as Unusable | toggle | Off | n/a | Fade the primary icon when you should wait before using the ability, similar to when an ability is lacking required resources. |
| Delays | Desaturate | toggle | n/a | n/a | Desaturate the primary icon when you should wait before using the ability. |
| Delays | Indicator | choice | No Indicator | Show Icon (Color); Show Text (Countdown); No Indicator | Specify the type of indicator to use when you should wait before casting the ability. |
| Delays > Position | Anchor Point | choice | Top Left | 9 choices | n/a |
| Delays > Position | X Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Delays > Position | Y Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Delays > Text | Font | choice | Fonts\ARIALN.TTF | 11 choices | n/a |
| Delays > Text | Style | choice | Outline | Monochrome; Monochrome, Outline; Monochrome, Thick Outline; None; Outline; Thick Outline | n/a |
| Delays > Text | Size | slider | 12 | 8 to 64, step 1 | n/a |
| Delays > Text | Color | colour | 1 | n/a | n/a |
| Indicators | Enabled | toggle | On | n/a | If enabled, small indicators for target-swapping, aura-cancellation, etc. |
| Indicators > Appearance | Width | slider | 20 | 8 to 100, step 1 | Specify the width of indicator icons. |
| Indicators > Appearance | Height | slider | 20 | 8 to 100, step 1 | Specify the height of indicator icons. |
| Indicators > Appearance | Icon Zoom | slider | 30 | 0 to 100, step 1 | Select the zoom percentage for indicator icon textures. |
| Indicators > Appearance | Keep Aspect Ratio | toggle | On | n/a | When enabled, indicator icons will maintain their original aspect ratio when resized. |
| Indicators > Position | Anchor To | choice | Right | 9 choices | n/a |
| Indicators > Position | X Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Indicators > Position | Y Offset | slider | 0 | -50 to 50, step 1 | n/a |
| Indicators | Enabled for Queued Icons | toggle | On | n/a | If enabled, these indicators will appear on queued icons as well as the primary icon, when appropriate. |

n/a: no fixed default (a keybind not set, or a value that follows the game or another option), no range, or no description.
<!-- /GENERATED -->

## Timeline style

<!-- GENERATED:options-display-timeline -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Option | Type | Default | Values | Description |
|---|---|---|---|---|---|
| Now | Size | slider | 48 | 16 to 200, step 1 | The diameter of the now circle (a focus ability coming up). |
| Now > ETA | Show ETA | toggle | On | n/a | Show the seconds until the now and next picks should be used. |
| Now > ETA | Format | choice | 0.1 s | 0.1 s; Whole seconds | Tenths of a second, or whole seconds. |
| Now > ETA | Font | choice | Fonts\FRIZQT__.TTF | 11 choices | n/a |
| Now > ETA | Style | choice | Thick Outline | Monochrome; Monochrome, Outline; Monochrome, Thick Outline; None; Outline; Thick Outline | n/a |
| Now > ETA | Size | slider | 16 | 8 to 64, step 1 | n/a |
| Now > ETA | Color | colour | 1 | n/a | n/a |
| Now > Sweep | Cooldown Sweep | choice | Extend | Extend; Cooldown; Off | Extend: the sweep runs until the pick should be used. |
| Now | Without Focus | choice | Empty | Empty; First Recommendation | Empty: the now circle holds only focus abilities (gold once ready to press) and the next box what to press. |
| Now | Pending Ring Color | colour | 1 | n/a | The now circle's ring while a focus ability counts down (the Timeline tab's Ring Color once it is ready). |
| Now | Ready Look | choice | Ring | Glow; Gold Ring; Ring | How the now circle shows a focus ability that is ready to press: the ring in the Timeline tab's Ring Color, or a glow in it, or the Gold Ring art (full colour when ready, grey and half faded while pending; fixed-colour art, so the ring colours do not apply to it). |
| Now > Border | Enabled | toggle | On | n/a | If enabled, each icon in this display will have a thin border. |
| Now > Border | Border Thickness | slider | 1 | 1 to 20, step 1 | Determines the thickness (width) of the border. |
| Now > Border | Coloring Mode | choice | Specify a Custom Color | Class #ffffff; Specify a Custom Color | Specify whether to use Class or Custom color borders. |
| Now > Border | Custom Color | colour | 0 | n/a | When borders are enabled and the Coloring Mode is set to Custom Color, the border will use this color. |
| Now > Range | Enabled | toggle | On | n/a | If enabled, the addon will provide a red warning highlight when you are not in range of your enemy. |
| Now > Range | Range Checking | choice | Per Ability | Per Ability; Melee Range; Exclude Out-of-Range | Select the kind of range checking and range coloring to be used by this display. |
| Now > Glows | Enable Overlay Glow | toggle | Off | n/a | If enabled, when the ability for the first icon has an active glow (or overlay), it will also glow in this display. |
| Now > Glows | Glow Style | choice | AutoCast Shine | AutoCast Shine; Default Button Glow; Pixel Glow | Select the glow style for your display. |
| Now > Glows | Coloring Mode | choice | Use Default Color | Class #ffffff; Specify a Custom Color; Use Default Color | Select the coloring mode for this glow effect. |
| Now > Glows | Glow Color | colour | 0.95 | n/a | Select the custom glow color for your display. |
| Now > Glows | Enable Action Highlight | toggle | On | n/a | If enabled, the addon will apply the default highlight when the first recommended item/ability is currently queued. |
| Now > Captions | Enabled | toggle | Off | n/a | If enabled, when the first ability shown has a descriptive caption, the caption will be shown. |
| Now > Indicators | Enabled | toggle | On | n/a | If enabled, small indicators for target-swapping, aura-cancellation, etc. |
| Now > Targets | Enabled | toggle | On | n/a | If enabled, the addon will show the number of active (or virtual) targets for this display. |
| Now > Delays | Fade as Unusable | toggle | Off | n/a | Fade the primary icon when you should wait before using the ability, similar to when an ability is lacking required resources. |
| Now > Delays | Desaturate | toggle | n/a | n/a | Desaturate the primary icon when you should wait before using the ability. |
| Now > Keybinds | Enabled | toggle | On | n/a | n/a |
| Now > Keybinds | Use Lowercase | toggle | Off | n/a | n/a |
| Next | Size | slider | 48 | 16 to 200, step 1 | The size of the next box (what to press now). |
| Next | Gap | slider | 12 | 0 to 100, step 1 | The space between the now circle and the next box, and between the next box and the lane. |
| Next | Frame | choice | None | Gold Frame; None | None: the colour border (the Border options). |
| Next > Alternatives | Show Alternatives | toggle | On | n/a | Show what the rotation would pick instead if the gating resource came in lower or higher than expected. |
| Next > Alternatives | Show On | choice | Both | Both; Next; Now | Which cells show their alternatives: the now circle (a focus ability, or the first recommendation when Without Focus is that), the next box, or both. |
| Next > Alternatives | Count | slider | 2 | 1 to 2, step 1 | How many alternatives each cell shows. |
| Next > Alternatives | Size | slider | 16 | 8 to 48, step 1 | The alternatives' icon size. |
| Next > Alternatives | Spacing | slider | 2 | 0 to 20, step 1 | The gap between the cell and its alternatives, and between them. |
| Next > Glows | Enabled for Queued Icons | toggle | Off | n/a | If enabled, abilities that have active glows (or overlays) will also glow in your queue. |
| Next > Captions | Enabled for Queued Icons | toggle | Off | n/a | If enabled, descriptive captions will be shown for queued abilities, if appropriate. |
| Next > Indicators | Enabled for Queued Icons | toggle | On | n/a | If enabled, these indicators will appear on queued icons as well as the primary icon, when appropriate. |
| Next > Keybinds | Enabled for Queued Icons | toggle | On | n/a | n/a |
| Lane | Icon Size | slider | 20 | 8 to 64, step 1 | The size of the picks on the lane. |
| Lane > ETA | Show ETA | toggle | Off | n/a | Show the seconds under each pick on the lane. |
| Lane > ETA | Size | slider | 10 | 6 to 32, step 1 | The lane ETA's font size. |
| Lane > Resource Gate | Mark | choice | Veil | Fade; Corner Mark; Veil | How a pick short of its resource is marked. |
| Lane > Resource Gate | Color | colour | 0 | n/a | n/a |
| Timeline > Lane | Horizon | slider | 10 | 2 to 30, step 1 | Seconds the lane shows; later picks are hidden. |
| Timeline > Lane | Pixels per Second | slider | 24 | 4 to 100, step 1 | How far apart picks one second apart sit. |
| Timeline > Lane | Direction | choice | Left to Right | Right to Left; Left to Right | Which way time runs. |
| Timeline > Lane | Rows | slider | 2 | 1 to 2, step 1 | With two rows, a pick close to the one before it hangs on the second row. |
| Timeline > Lane | Row Gap | slider | 24 | 0 to 100, step 1 | Picks closer than this many pixels to the one before them take the second row. |
| Timeline > Lane | Height | slider | 56 | 20 to 200, step 1 | The lane's height. |
| Timeline > Lane | Opacity | slider | 0.95 | 0 to 1, step 0.05 | The opacity of the picks on the lane. |
| Timeline > Lane | Dimmed Opacity | slider | 0.6 | 0 to 1, step 0.05 | The opacity of the picks after one short of its resource (they may slip). |
| Timeline > Lane | Glide | slider | 0.08 | 0 to 1, step 0.01 | Seconds a lane pick takes to settle on a new predicted time (0: jump). |
| Timeline > Lane | Pin out of Combat | toggle | On | n/a | Out of combat the lane and the countdowns hold still between updates, timed from the first recommendation; in combat they follow the clock. |
| Timeline > Lane | Timers Out of Combat | toggle | Off | n/a | Show the cooldown sweeps and the countdown numbers out of combat. |
| Timeline > Ruler | Style | choice | Ruler | Center; Dots; Lines; Ruler | Ruler: a baseline and a tick each second. |
| Timeline > Ruler | Color | colour | 1 | n/a | The ruler's color. |
| Timeline > Ruler | Opacity in Combat | slider | 0.5 | 0 to 1, step 0.05 | The ruler's opacity in combat. |
| Timeline > Ruler | Opacity out of Combat | slider | 0.25 | 0 to 1, step 0.05 | The ruler's opacity out of combat. |
| Timeline > Focus | Focus Abilities | toggle | On | n/a | An ability marked focus=N in the priority (a tier, 1 highest) takes the now circle with a countdown when it comes up within the focus horizon; the lowest tier wins, then the soonest. |
| Timeline > Focus | Focus Horizon | slider | 10 | 1 to 30, step 1 | Seconds ahead a focus ability takes the now circle (never past the lane's horizon). |
| Timeline > Focus | Ring Color | colour | 1 | n/a | The now circle's ring when the focus ability is ready to press. |

n/a: no fixed default (a keybind not set, or a value that follows the game or another option), no range, or no description.
<!-- /GENERATED -->

## Modern overlays

<!-- GENERATED:options-display-modern -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Option | Type | Default | Values | Description |
|---|---|---|---|---|---|
| Modern | Modern (game truth) | toggle | Off | n/a | Turn the Modern overlays on for this display. |
| Modern | Real Cooldown Swipes | toggle | On | n/a | Show the game's own cooldown on an icon while it runs, instead of Hekili's estimate. |
| Modern | Grey When Not Usable | toggle | On | n/a | Grey an icon as soon as the game says the ability cannot be used yet (short of resource, or its proc or condition is not up). |
| Modern | Proc Glow | toggle | Off | n/a | Glow the next ability (and the focus ability) when the game lights its proc. |

n/a: no fixed default (a keybind not set, or a value that follows the game or another option), no range, or no description.
<!-- /GENERATED -->

## Visibility

<!-- GENERATED:options-display-visibility -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Section | Option | Type | Default | Values | Description |
|---|---|---|---|---|---|
| Visibility | Advanced | toggle | Off | n/a | If checked, options are provided to fine-tune display visibility and transparency. |
| PvE | Hide When Mounted | toggle | Off | n/a | If checked, the display will not be visible when you are mounted when out of combat. |
| PvE | Default | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity by default. |
| PvE | Target | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity when you have an attackable PvE target. |
| PvE | Combat | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity in PvE combat. |
| PvE | Combat w/ Target | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity when you are in combat and have an attackable PvE target. |
| PvP | Hide When Mounted | toggle | Off | n/a | If checked, the display will not be visible when you are mounted unless you are in combat. |
| PvP | Default | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity by default. |
| PvP | Target | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity when you have an attackable PvP target. |
| PvP | Combat | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity in PvP combat. |
| PvP | Combat w/ Target | slider | 1 | 0 to 1, step 0.01 | If non-zero, this display is shown with the specified level of opacity when you are in combat and have an attackable PvP target. |
| Visibility | PvE Alpha | slider | 1 | 0 to 1, step 0.01 | Set the transparency of the display when in PvE environments. |
| Visibility | PvP Alpha | slider | 1 | 0 to 1, step 0.01 | Set the transparency of the display when in PvP environments. |

n/a: no fixed default (a keybind not set, or a value that follows the game or another option), no range, or no description.
<!-- /GENERATED -->

## See also

- [Setting up displays](Setting-Up-Displays)
- [Reading the displays](Reading-The-Displays)
