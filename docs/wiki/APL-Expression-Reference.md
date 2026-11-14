The **APL expression reference** lists the values that a priority line can test in its conditions on Hekili Forever. An expression such as `energy.lo>=60` or `buff.cat_form.up` names a value by a root (`energy`, `buff`), an optional key (`cat_form`) and a field (`lo`, `up`). This part of the page covers resources and time to die. The rest of the page covers buffs and debuffs, cooldowns, actions, talents, the target, toggles, settings and previous casts.

Expressions follow the SimulationCraft action-list dialect that the original Hekili used, with the changes listed in [APL Forever differences](APL-Forever-Differences). Operators and the line grammar are in [APL syntax reference](APL-Syntax-Reference). The tables on this page are generated from the addon.

## Resources

A resource expression starts with the resource's name, such as `energy`, `rage`, `mana` or `combo_points`. In the table, `<resource>` stands for that name.

The game hides resources ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)), so Hekili Forever keeps three values for each hidden resource: a low end, a best guess and a high end. `current` reads the best guess. `lo` and `hi` read the ends. A resource the game reports directly, such as combo points, has no range, and all three read the same value.

<!-- GENERATED:expressions-resource -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `<resource>.current` | number | The best estimate of the amount | Estimated while hidden | `combo_points.current>=5` |
| `<resource>.lo` | number | The lowest amount there can be | Estimated while hidden | `energy.lo>=60` |
| `<resource>.hi` | number | The highest amount there can be | Estimated while hidden | `rage.hi<30` |
| `<resource>.max` | number | The maximum | Read | `energy.max>100` |
| `<resource>.pct` | percent | `current` as a share of `max` | Estimated while hidden | `mana.pct<50` |
| `<resource>.pct_lo` | percent | `lo` as a share of `max` | Estimated while hidden | `mana.pct_lo<30` |
| `<resource>.deficit` | number | `max` minus `current` | Estimated while hidden | `energy.deficit<20` |
| `<resource>.deficit_pct` | percent | `deficit` as a share of `max` | Estimated while hidden | `mana.deficit_pct>40` |
| `<resource>.regen` | number per second | The regeneration rate now | Modelled | `energy.regen>10` |
| `<resource>.time_to_max` | seconds | Time until full | Modelled | `energy.time_to_max<1` |
| `<resource>.time_to_<N>` | seconds | Time until the amount reaches N | Modelled | `energy.time_to_40<0.5` |
| `<resource>.time_to_deficit_<N>` | seconds | Time until the amount is N below `max` | Modelled | `energy.time_to_deficit_20<1` |
<!-- /GENERATED -->

### Testing the low end

A line that spends a resource should test `lo`, so that it is shown only when the cost is certain to be there. `pct_lo` does the same as a percentage of the maximum. From Feral (wowsims.com), shortened:

```text
actions+=/ferocious_bite,if=...combo_points.current>=5&(buff.clearcasting.up&energy.lo>=50)...
```

From Affliction (wowsims.com):

```text
actions+=/life_tap,if=(mana.pct_lo<30&fight_remains>60)
```

### Comparisons that wait

When a comparison asks a resource to reach a value, as in `energy.lo>=60` or `60<=energy.lo`, Hekili Forever does not only test it now. It works out how long the resource takes to get there and shows the ability that far ahead in the queue, with its wait. This applies to `<resource>`, `.lo`, `.pct` and `.pct_lo`. A comparison in the other direction, such as `energy.lo<=57`, is tested at each step only.

## Time to die

<!-- GENERATED:expressions-time-to-die -->
<!-- Do not edit: written by `make wiki-tables` (tools/wiki/manifest.lua). -->
| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `fight_remains` | seconds | Time until the longest-lived enemy dies | Always 3600 (unknown) | `fight_remains>60` |
| `target.time_to_die` | seconds | Time until the target dies | Always 3600 (unknown) | `target.time_to_die>12` |
| `target.time_to_pct_<N>` | seconds | Time until the target falls to N percent health | Always 3600 (unknown) | `target.time_to_pct_20>5` |
<!-- /GENERATED -->

> [!NOTE]
> **On Forever:** The game hides target health, so every time-to-die value reads 3600 seconds. In the Affliction line above, `fight_remains>60` always passes. A line that needs `fight_remains<8` never fires.

### Edge cases

- `<resource>.time_to_<N>` with an N that is not a number reads 3600.
- `health.pct` reads 100 while the game hides the player's health.
- The WoW client raises an error on division by zero, unlike standard Lua. A value that can be zero must not be used as a divisor.

## See also

- [APL line options](APL-Line-Options)
- [APL debugging](APL-Debugging): reading a line's result in a snapshot
