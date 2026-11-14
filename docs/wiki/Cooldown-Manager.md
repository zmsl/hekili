<!--
Purpose: What the game's Cooldown Manager gives Hekili Forever, and the per-aura switches.
Type: Explanation
Audience: players
Prerequisites: None.
-->
The **Cooldown Manager** is a feature of the game client: bars of icons that show chosen cooldowns and auras. During combat, the game hides the player's buffs and debuffs from addons, but it still shows them on the Cooldown Manager's bars. Hekili Forever reads those bars to learn whether a buff or debuff is up. The **Cooldown Manager** page of its options lists the auras it can learn this way, with a switch for each.

| Cooldown Manager | |
|---|---|
| Where | **/hekili > Cooldown Manager** |
| Needs | The game's Cooldown Manager turned on, with the aura on one of its bars |
| Switches | One per aura, on by default; saved per specialization |
| Applies | After combat |

## What it provides

Without the Cooldown Manager, Hekili Forever estimates in combat whether each buff or debuff is up, from the casts it has seen and the aura's known duration. An estimate can drift: a proc that the addon did not predict, or a debuff that ends early, is not seen.

When one of the Cooldown Manager's bars shows one of the player's auras, Hekili Forever uses it to correct whether that aura is up. Hekili Forever learns only about the auras that are on a bar. An aura that the game offers but that sits in no bar teaches it nothing.

The game's Cooldown Manager must be turned on in the game's options. When it is off, the panel says so. When the game offers no Cooldown Manager to the character, the panel shows the game's reason.

Hekili Forever always uses the Cooldown Manager this way; there is no setting that turns the whole feature off.

## The per-aura switches

The panel shows one switch for each aura that both the game's Cooldown Manager and the class addon know:

- a **gold** name: the aura is on one of the Cooldown Manager's bars, so Hekili Forever reads it there;
- a **grey** name: the aura is not on a bar. Its switch takes effect once the aura is added to a bar in the game's settings.

Turning a switch off makes Hekili Forever ignore that aura on the bars, and go back to its own estimate. A class addon can set a switch off by default when reading that aura from the bars does more harm than good. The switches are saved for each specialization. **Reset** returns every switch of the current specialization to its default.

A switch changed during combat takes effect when combat ends; the panel says so.

<!-- TODO-SCREENSHOT: the Cooldown Manager panel with gold and grey switches -->

## Effect on accuracy

The more of a priority's own buffs are on the Cooldown Manager's bars, the closer its recommendations stay to what it would show with every value known. The [Accuracy](Accuracy) page reports two numbers per specialization. The "live-like" number assumes the Cooldown Manager shows none of the player's auras, so it is the lower bound.

## See also

- [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)
