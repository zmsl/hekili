<!--
Purpose: Why a line is never picked: snapshots, warnings, the import log, flicker.
Type: How-to
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
-->
This page shows how to find out why a line of a priority is never recommended, or is recommended at the wrong time, and how to keep a priority from flickering. It uses snapshots, the **Warnings** page and the **Import Log**. [Reading a snapshot](Reading-A-Snapshot) explains a snapshot in full.

## Before you start

- Make the priority you are testing active for your specialization ([APL tutorial: your first custom priority](APL-Tutorial-Your-First-Custom-Priority)).
- Forever has no target dummies: test on an enemy in the open world.

## Read the line in a snapshot

A snapshot records one walk of the priority: every line the walk reached, and why each was or was not chosen.

1. In the situation where the line should be recommended, type `/hekili snapshot` (or `/hekili snap`). A key for it can be set as **Snapshot** in **/hekili > Toggles**.
2. Open `/hekili`, then **Snapshots (Troubleshooting)**, and choose the snapshot in **Select a Snapshot**.
3. Search the text for the line's action, such as `faerie_fire`. Each entry is shown with its list and its number in the list.
4. Read the messages under the entry:

| Message | Meaning | What to check |
|---|---|---|
| "ability disabled" or "ability unknown" | The ability is switched off, or the character does not have it | **/hekili > Abilities**, or the character's level and talents |
| "The action is not ready ... before our maximum delay window" | Its cooldown or cost will not be ready within the forecast | The cooldown, and the resource it needs |
| "The action (...) is unusable at ... because ..." | The class pack refuses it at that moment; the reason follows | The reason, such as a missing form or an empty combo point bar |
| "this entry's criteria FAILS" followed by the values | The condition is false; each value it read is printed | Which value is not what you expected |
| "this entry would not be reached at the current time via the current action list path" | A list call above it, or a `run_action_list`, keeps the walk away from it | The conditions of the lists that lead to it |
| "The conditions for this entry contain an error" | The condition does not compile | The **Warnings** page |
| "Action chosen" | The line was recommended at the time shown | |

An ability that needs a toggle that is off, such as **Major Cooldowns** for a cooldown, also shows as "ability disabled", with the reason in brackets.

## Check the warnings and the import log

1. Open **/hekili > Warnings**. Choose a warning in **Warning Identifier** to read it in **Warning Information**.
2. Look for warnings that name your priority:
   - a condition that fails to compile, with the list and entry number;
   - an unknown talent or an action the specialization does not have;
   - a variable that is read but never set;
   - "target health is secret", for a line that reads target health ([APL Forever differences](APL-Forever-Differences)).
3. If the priority came from the importer, open its **Source** tab and read the **Import Log**. It lists every conversion the importer made and every line it switched off.

## Common causes

- **The line waits for the target to die.** `fight_remains`, `target.time_to_die` and `target.time_to_pct_<N>` always read 3600 on Forever, so `fight_remains<8` never passes.
- **The line reads target health.** It reads 100 unless an ability usable only at low target health has narrowed it, so a test such as `target.health.pct<20` rarely passes.
- **The line tests a range that is not known yet.** While Hekili Forever cannot bracket the distance, `target.withinN` and `target.outsideN` are both true. Add `action.<key>.in_range` when the line must wait for range.
- **A line above it always wins.** The walk keeps the line that is ready soonest. Move the line up, or narrow the condition of the line above.
- **A `precombat` line in combat.** Lines of `precombat`, and of the lists it calls, are skipped once combat starts.
- **A pasted line reads differently after import.** The importer converts some forms, such as `%`, `%%` and `//`, and lists each change in the **Import Log** ([APL Forever differences](APL-Forever-Differences)). Compare the **Conditions** box with the text you pasted.

## Avoid flicker

Flicker is a recommendation that changes and changes back within a few updates. Hekili Forever treats it as a defect, because a player cannot act on an icon that keeps changing.

- Test the low end of a hidden resource, `energy.lo>=60`, not the best guess, `energy.current>=60`. The best guess moves each time the estimate is corrected; the low end only rises as the resource is proven.
- Avoid two lines whose conditions are near opposites at the same threshold, such as `energy.lo>=50` on one and `energy.lo<=55` on the next. Small corrections then swap them back and forth.
- Do not test short remaining times of auras whose durations the game hides, such as `debuff.rake.remains<0.5`, when a test of `up` or `refreshable` does the job. Those times are estimates.
- After a change, watch the first icon for a minute of steady fighting. If it flickers, take a snapshot during a change and compare the values the two lines read.

Hekili Forever already holds a waiting icon for one update before it shows a different waiting icon, so a single noisy update does not show. A ready icon is always shown at once.

## See also

- [Reading a snapshot](Reading-A-Snapshot)
- [APL priority editor](APL-Priority-Editor)
- [Reporting a problem](Reporting-A-Problem)
