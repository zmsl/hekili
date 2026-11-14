**What Hekili Forever can and cannot know** describes which game values the addon reads directly on the WoW Forever client, which it estimates, and how the estimates affect its recommendations.

The Forever client is a modern game client that hides many combat values from addons. The game's own frames can still show a hidden value, but an addon cannot read it, compare it or calculate with it. There is no combat log. Hekili Forever keeps the original Hekili's simulation of the fight ahead. Where the original read a value directly, Hekili Forever uses an estimate built from what the game still reports.

| What Hekili Forever can and cannot know | |
|---|---|
| Applies to | Every class and specialization |
| Read directly | Combo points, ability usability, cooldown ready or not, shapeshift form, melee swings, nameplates |
| Estimated | Energy, rage, mana, cooldown times, buff and debuff times |
| Not available | Target health, hits landed on a target |
| As of | Hekili Forever v0.8.1 |

## What the game reports

| Value | Hekili Forever | Notes |
|---|---|---|
| Combo points | Read | Reported during combat. |
| Whether an ability is usable | Read | Includes whether it is unusable for lack of resources. |
| Whether a cooldown is ready | Read | The remaining time is hidden. |
| Shapeshift form | Read | |
| Melee swings | Read | Each swing is reported as it happens. |
| Nameplates | Read | Used to count nearby enemies. |
| Hits on the player | Read | Including misses, dodges and parries. |
| Energy, rage and mana | Estimated | Hidden in and out of combat. |
| Cooldown remaining time | Estimated | From the cast time and the ability's cooldown. |
| Buff and debuff times | Estimated | From the cast and the aura's duration. The game's Cooldown Manager can show some of them ([Cooldown Manager](Cooldown-Manager)). |
| Hits landed on a target | Not available | |
| Target health | Not available | So the time until a target dies is unknown. |

## How a resource is estimated

An estimate is built in four parts.

- **What the game still reports.** The estimate starts from values the game answers plainly: values read out of combat, the player's own casts, whether an ability is usable, and whether a cooldown is ready.
- **Known changes.** Each cast spends its cost. Regeneration, melee swings and talents add to the total, using the same rules the class pack gives the simulation.
- **Corrections.** When the game reports that an ability cannot be used for lack of resources, the amount must be below its cost. When the ability becomes usable, the amount is at least its cost. The estimate moves to agree whenever the game reveals something new.
- **A range.** Each estimate is a low end, a best guess and a high end, together with how the value was learned.

## Effect on recommendations

A priority line that needs a resource checks the low end of the range. A line that needs 60 energy is shown once Hekili Forever is sure there are at least 60. A recommendation can therefore appear slightly later than the ability becomes usable, but it does not appear while the ability is still unaffordable.

Because target health is hidden, the time until a target dies reads as unknown, which the priorities see as 3600 seconds. Lines that wait for a target to be nearly dead do not fire. When the game hides the player's own health, Hekili Forever treats it as full, so a defensive line based on low health does not fire.

> [!WARNING]
> **Different from retail Hekili:** The original Hekili read resources, cooldowns and target health on every update. A custom priority copied from it that tests `target.time_to_die` or `health.pct` behaves differently here.

## Measurements

The table in [What the game reports](#what-the-game-reports) comes from in-game measurements on the Forever client. The estimation steps describe how Hekili Forever models the hidden values; they are not measurements. A client update can change what the game reports. The infobox gives the version the page was last checked against.

## See also

- [How targets are counted](How-Targets-Are-Counted)
- [Accuracy](Accuracy): how much the hidden values cost, per specialization
- [APL expression reference](APL-Expression-Reference): the `.lo` and `pct_lo` expressions, for priority authors
