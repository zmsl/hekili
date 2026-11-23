<!--
Purpose: Which game values are read, which are estimated, and what that means for recommendations.
Type: Explanation
Audience: everyone
Prerequisites: None.
-->
**What Hekili Forever can and cannot know** describes which game values the addon reads directly on the WoW Forever client, which it estimates, and how the estimates affect its recommendations.

The Forever client is a modern game client that hides many combat values from addons. The game's own frames can still show a hidden value, but an addon cannot read it, compare it or calculate with it. There is no combat log. Hekili Forever keeps the original Hekili's simulation of the fight ahead. Where the original read a value directly, Hekili Forever uses an estimate built from what the game still reports.

| What Hekili Forever can and cannot know | |
|---|---|
| Applies to | Every class and specialization |
| Read directly | Combo points, ability usability, cooldown ready or not, shapeshift form, melee swings, nameplates, the target's and the player's health in whole-percent steps |
| Estimated | Energy, rage, mana, cooldown times, buff and debuff times, the target's time to die |
| Not available | Hits landed on a target |

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
| Energy, rage and mana | Estimated | The exact amount is hidden in and out of combat. Where the game allows it, the 1% step the amount is in is read, and the estimate stays inside it. |
| Cooldown remaining time | Estimated | From the cast time and the ability's cooldown. |
| Buff and debuff times | Estimated | From the cast and the aura's duration. The game's Cooldown Manager can show some of them ([Cooldown Manager](Cooldown-Manager)). A debuff whose cast finishes after a target change counts on the enemy it was cast at. A missed or dodged instant is noticed from the game's report of the miss, or within about half a second from the Cooldown Manager. |
| Hits landed on a target | Not available | |
| Target health | Read | In whole-percent steps, and no lower than 2% while the target lives; unknown for a moment after a target change. When an ability that is usable only at low target health disagrees with the step, the ability's answer wins. If the game offers no reading, full (100) until such an ability becomes usable, then that ability's threshold. |
| Time until the target dies | Estimated | From how fast its health falls; unknown until there is enough to estimate from. |

## How a resource is estimated

An estimate is built in five parts.

- **What the game still reports.** The estimate starts from values the game answers plainly: values read out of combat, the player's own casts, whether an ability is usable, and whether a cooldown is ready.
- **Known changes.** Each cast spends its cost. Regeneration, melee swings and talents add to the total, using the same rules the class pack gives the simulation.
- **Corrections.** When the game reports that an ability cannot be used for lack of resources, the amount must be below its cost. When the ability becomes usable, the amount is at least its cost. The estimate moves to agree whenever the game reveals something new.
- **The 1% step.** Where the game allows it, Hekili Forever reads which 1% step of the maximum the amount is in. With a maximum of 100 that is the exact whole number. A resource the active priority compares with a number is also cut exactly at that number, for up to 8 numbers. The step can trail the game by a fraction of a second, so a cast or swing heard since then moves the estimate on from it, and the game's answer on whether an ability is usable always wins over it.
- **A range.** Each estimate is a low end, a best guess and a high end, together with how the value was learned.

## Effect on recommendations

A priority line that needs a resource checks the low end of the range. A line that needs 60 energy is shown once Hekili Forever is sure there are at least 60. A recommendation can therefore appear slightly later than the ability becomes usable, but it does not appear while the ability is still unaffordable.

The time until the target dies is an estimate, and it can be well off early in a fight and near its end. The time left in the fight is that estimate with one enemy; with several enemies, or while there is no estimate, the priorities see 3600 seconds (unknown), so lines that wait for the end of the fight do not fire then. Lines that test health follow the whole-percent step, for the target and for the player. If the game offers no reading of the player's health, Hekili Forever treats it as full, and a defensive line based on low health does not fire.

> [!WARNING]
> **Different from retail Hekili:** The original Hekili read resources, cooldowns and target health on every update. A custom priority copied from it that tests `target.time_to_die` behaves differently here, and one that tests `health.pct` or `target.health.pct` reads whole-percent steps.

## Measurements

The table in [What the game reports](#what-the-game-reports) comes from in-game measurements on the Forever client. The estimation steps describe how Hekili Forever models the hidden values; they are not measurements. A client update can change what the game reports. The infobox gives the version the page was last checked against.

## See also

- [How targets are counted](How-Targets-Are-Counted)
- [Accuracy](Accuracy): how much the hidden values cost, per specialization
- [APL expression reference](APL-Expression-Reference): the `.lo` and `pct_lo` expressions, for priority authors
