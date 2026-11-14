<!--
Purpose: SimulationCraft, retail Hekili and Hekili Forever side by side, for every expression or option that differs.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
-->
The **APL Forever differences** are the expressions and line options that behave differently in Hekili Forever than in SimulationCraft or in retail Hekili, the original addon this fork comes from. Most differences follow from one fact: the Forever client hides many combat values from addons ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)). The others are additions this fork made. A priority copied from SimulationCraft or retail Hekili should be checked against the tables below.

The tables list the differences a priority author meets. The importer also rewrites a few retail-only forms that are not listed. The pages they link give the details.

## Expressions

| Expression | SimulationCraft | Retail Hekili | Hekili Forever |
|---|---|---|---|
| `<resource>.current`, `.pct`, `.deficit` | The simulated amount | The amount the game reports | An estimate while the game hides the resource |
| `<resource>.lo`, `.hi`, `.pct_lo` | Not available | Not available | The low and high ends of the estimate ([Resources](APL-Expression-Reference#resources)) |
| `fight_remains`, `target.time_to_die`, `target.time_to_pct_<N>` | From the simulated fight | Worked out from target health | Always 3600 seconds, meaning unknown |
| `target.health.pct` and the other target health values | The simulated health | The health the game reports | 100 until an ability usable only at low target health narrows it; always 100 on a specialization without one. A warning in **Warnings** when the priority loads. |
| `health.pct` | The simulated health | The health the game reports | The reported value, or 100 while the game hides it |
| `cooldown.<key>.remains` | Simulated | The time the game reports | Estimated from the last cast; `cooldown.<key>.ready` is read from the game |
| `buff.<key>.remains`, `debuff.<key>.remains` | Simulated | The time the game reports | Estimated from the cast and the aura's length |
| `target.within<N>`, `target.outside<N>`, `target.range<A>to<B>` | The simulated distance | From the game's range checks | From the range checks of the abilities Hekili Forever tracks; while the range is unknown, all are true |
| `active_dot.<key>` | Simulated | Counted from the combat log | The target and the enemies Hekili Forever remembers; while unknown, every enemy counts as carrying the aura |
| `target.is_targeting_player` | Simulated | Read from the game | Read; false while the game hides it |
| `target.creature_type`, `target.is_undead`, `target.is_demon` | Not available | Not available | The target's creature type; `unknown` while hidden |
| `main_hand.<kind>`, `off_hand.<kind>` | Not available | The size only: `two_handed`, `one_handed` | The size and the kind of the worn weapon, such as `two_handed` or `dagger` |
| `buff.<key>.icd_ready`, `buff.<key>.icd_remains` | Not available | Not available | A proc aura's internal cooldown, when the class pack gives one |
| `window.<name>.*` | Not available | Not available | Rotation windows ([APL windows](APL-Windows)) |
| `toggle.movement` | Not available | Not available | The **Movement** toggle |
| `toggle.essences` | Not available | Its name for the minor cooldowns toggle | Read as `toggle.minor_cooldowns` |

> [!NOTE]
> **On Forever:** A line that waits for a target to be nearly dead, such as `fight_remains<8`, never fires. A line such as `fight_remains>60` always passes.

## Line options

| Option | SimulationCraft | Retail Hekili | Hekili Forever |
|---|---|---|---|
| `pool_resource,for_next=1` | Pools for the next line | Delays the walk until the next line is affordable | The same, testing the low end of the resource |
| `pool_resource,wait=<seconds>` and `pool_resource` without `for_next` | Pools for the time given | Accepted and ignored | Accepted and ignored ([Pooling](APL-Line-Options#pooling)) |
| `focus=<tier>` | Not available | Not available | A focus tier for the Timeline display style |
| `label=`, `label_if=` | Not available | Not available | Text on the recommended icon |
| `icon=`, `icon_if=` | Not available | Not available | An icon override |
| `other_target=1` | Not available | Not available | The line is for another enemy only |
| `open_window`, `close_window` | Not available | Not available | Rotation window lines ([APL windows](APL-Windows)) |
| `actions=` | Starts the list again | Adds a line | Adds a line |

> [!WARNING]
> **Different from retail Hekili:** Pooling options and energy tests written to wait for a resource are not needed. Every line waits for its own cost in the forecast, tested at the low end of the estimate ([Comparisons that wait](APL-Expression-Reference#comparisons-that-wait)).

The editor fields that have no effect are listed in [APL priority editor](APL-Priority-Editor#fields-that-do-nothing-on-forever).

## Deprecated and refused options

The importer converts these SimulationCraft forms, or drops them, and lists each change in the **Import Log**.

| Option or expression | What the importer does |
|---|---|
| `wait_for_cooldown,name=<ability>` | Becomes `wait,sec=cooldown.<ability>.remains` |
| `talent.<key>` | Becomes `talent.<key>.enabled` |
| `toggle.essences` | Becomes `toggle.minor_cooldowns` |
| `target_if=min:<expression>` or `max:<expression>` | The `min:` or `max:` is removed and the rest becomes the condition when the line has no `if=`; the target is not sorted |
| `cancel_if=` | Becomes `interrupt_if=` |
| `use_item,name=<item>` | Becomes the item's ability key; an item the addon does not know switches the line off |
| `%` and `%%` | Become `/` (division) and `%` (remainder) |
| `snapshot_stats`, `flask`, `food`, `augmentation` | Dropped |
| An action the specialization does not have | Kept, with an "Unsupported action" warning; the walk skips it |
| `open_window` or `close_window` with a window the class does not register | Kept switched off, with an "Unknown window" warning |

A class pack's own source (`tools/make_pack.lua`) refuses any option outside a short list and stops the build ([APL line options](APL-Line-Options#options-by-path)).

## See also

- [APL expression reference](APL-Expression-Reference)
- [Coming from retail Hekili](Coming-From-Retail-Hekili)
- [APL syntax reference](APL-Syntax-Reference)
