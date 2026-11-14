<!--
Purpose: What a priority is, lists, the walk and the forecast, and why each evaluation stands alone.
Type: Explanation
Audience: theorycrafters
Prerequisites: None.
-->
An **action priority list** (APL) is the text form of a priority: an ordered list of abilities, each with the conditions under which it should be used. Hekili Forever reads APLs in the SimulationCraft dialect that the original Hekili used, and recommends the first ability whose conditions hold. This page explains how a priority is split into lists, how Hekili Forever walks it to build the queue of upcoming abilities, and why each walk starts from nothing.

The other pages in this group are references: [APL syntax reference](APL-Syntax-Reference) for the grammar, [APL expression reference](APL-Expression-Reference) for the values a condition can test, and [APL line options](APL-Line-Options) for the options a line can carry.

## What a priority is

A priority is a named bundle of action lists for one specialization. Each specialization has one active priority, chosen under **/hekili > Priorities**, on the page of that specialization. The built-in priorities are generated from the rotations at [wowsims.com](https://wowsims.com) and carry "(wowsims.com)" in their names ([wowsims priorities explained](APL-wowsims-Packs-Explained)). A player can copy a built-in priority and edit the copy, or write a new one.

Each line of an APL names one action and, after `if=`, its condition. From Feral (wowsims.com):

```simc
actions+=/rake,focus=2,if=((!action.cat_form.known|buff.cat_form.up)&(!debuff.rake.up&fight_remains>6))&(toggle.movement&target.outside5|target.within5)
```

This line recommends Rake when the player is in Cat Form (or has not learned it yet), Rake is not on the target, and the target is in melee range or the **Movement** toggle is on. The action is usually an ability's key. A few actions are instructions to the walk instead, such as `call_action_list` and `variable`.

## Lists

A priority holds several lists, each a name and its lines:

- `precombat` is walked first on every update. Once combat has started, its lines are skipped, unless the class pack marks the ability as essential. Lists it calls are filtered the same way.
- `default` is the main list, walked after `precombat`. Its lines are written `actions=` and `actions+=/`.
- Any other name is a sub-list, written `actions.<name>+=/`. A sub-list is used only when another list calls it.

Two actions call a sub-list by its name:

- `call_action_list,name=<list>` walks the named list at that point. If nothing in it is chosen, the walk continues with the next line of the calling list.
- `run_action_list,name=<list>` walks the named list in the same way. In addition, while its own condition holds, no line after it in the calling lists can be chosen. Those lines can be chosen only at a time when that condition has stopped holding.

A list that is already being walked is not entered again: a call that would loop is skipped.

## The walk and the forecast

On each update, Hekili Forever copies its picture of the game into a simulated state and walks the active priority:

1. It goes down the lists line by line, looking for a line whose ability is known, enabled and usable and whose condition holds. A line whose ability is not ready yet is not dropped: Hekili Forever works out how long the ability takes to become ready and whether the condition holds then. It keeps the line that is ready soonest, and a later line displaces it only by being ready earlier.
2. The chosen ability becomes the first recommendation.
3. The simulated clock moves past that cast: its cost is spent, its cooldown starts, and its effects are applied as the class pack describes them.
4. The walk starts again from the top to find the next recommendation.

Repeating the walk fills the queue of upcoming abilities that the displays show. This look ahead is the forecast. Because the forecast waits on time, a line such as `energy.lo>=60` does not have to hold now. Hekili Forever finds when it will hold, and shows the ability that far ahead, with its wait ([Comparisons that wait](APL-Expression-Reference#comparisons-that-wait)).

On Forever, many game values are hidden from addons ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)). The simulated state starts from Hekili Forever's estimates of those values, not from the game's own numbers.

## Each evaluation stands alone

Every update builds the simulated state again from the estimates and walks the priority from the top. Nothing a walk decided is carried into the next one: there is no memory of an earlier recommendation, no pooling state and no counter that a line could advance. A variable set by a `variable` line is worked out again in each walk.

This has three consequences for a priority author:

- A condition describes the situation in which the ability is right, not a step in a plan. To hold an ability back, write a condition that is false until the right moment. The forecast shows the ability when that moment comes.
- Waiting for a resource needs no line of its own, because the forecast already waits for each line's cost. Of `pool_resource`, only the form that delays the walk until the next line is affordable works (`for_next=1`, see [APL line options](APL-Line-Options)).
- Two walks that start from the same state give the same answer. A recommendation changes because the game changed, or because an estimate was corrected.

A recommendation that changes and changes back within a few updates is called flicker, and Hekili Forever treats it as a defect. [APL debugging](APL-Debugging) describes how to avoid it.

## See also

- [APL tutorial: your first custom priority](APL-Tutorial-Your-First-Custom-Priority)
- [APL Forever differences](APL-Forever-Differences): what differs from SimulationCraft and retail Hekili
- [APL priority editor](APL-Priority-Editor)
- [Choosing a priority](Choosing-A-Priority)
