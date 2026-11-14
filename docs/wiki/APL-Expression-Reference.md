The **APL expression reference** lists the values that a priority line can test in its conditions on Hekili Forever. An expression such as `energy.lo>=60` or `buff.cat_form.up` names a value by a root (`energy`, `buff`), an optional key (`cat_form`) and a field (`lo`, `up`). The page covers resources, time to die, buffs and debuffs, cooldowns, actions, talents, the target, toggles, settings, previous casts and the other values of the fight.

Expressions follow the SimulationCraft action-list dialect that the original Hekili used, with the changes listed in [APL Forever differences](APL-Forever-Differences). Operators and the line grammar are in [APL syntax reference](APL-Syntax-Reference). The resource and time-to-die tables are generated from the addon; the others are written by hand and list the keys priorities use. In every table, `<key>` stands for an ability's or aura's key, such as `rake`.

## Resources

A resource expression starts with the resource's name, such as `energy`, `rage`, `mana` or `combo_points`. In the table, `<resource>` stands for that name.

The game hides resources ([What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know)), so Hekili Forever keeps three values for each hidden resource: a low end, a best guess and a high end. `current` reads the best guess. `lo` and `hi` read the ends. A resource the game reports directly, such as combo points, has no range, and all three read the same value.

<!-- GENERATED:expressions-resource -->
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
<!-- /GENERATED -->

> [!NOTE]
> **On Forever:** The game hides target health, so every time-to-die value reads 3600 seconds. In the Affliction line above, `fight_remains>60` always passes. A line that needs `fight_remains<8` never fires.

### Edge cases

- `<resource>.time_to_<N>` with an N that is not a number reads 3600.
- `health.pct` reads 100 while the game hides the player's health.
- The WoW client raises an error on division by zero, unlike standard Lua. A value that can be zero must not be used as a divisor.

## Buffs and debuffs

`buff.<key>` reads an aura on the player and `debuff.<key>` an aura on the target. `<key>` is the aura's key in the class pack, usually the ability's key.

| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `buff.<key>.up` | boolean | The aura is up | Estimated | `buff.cat_form.up` |
| `buff.<key>.down` | boolean | The aura is not up | Estimated | `buff.prowl.down` |
| `buff.<key>.remains` | seconds | Time until the aura ends; 0 when down | Estimated | `buff.battle_shout.remains<=10` |
| `buff.<key>.duration` | seconds | The aura's full length | Modelled | `buff.cat_form.duration>0` |
| `buff.<key>.stack` | number | Stacks; 0 when down | Estimated | `buff.heating_up.stack=3` |
| `buff.<key>.max_stack` | number | The most stacks the aura can have | Modelled | `buff.heating_up.max_stack>1` |
| `buff.<key>.refreshable` | boolean | The aura is down, or close enough to its end to recast it | Estimated | `buff.battle_shout.refreshable` |
| `buff.<key>.react` | number | Stacks, for a proc aura | Estimated | `buff.clearcasting.react>0` |
| `buff.<key>.icd_ready` | boolean | The aura's internal cooldown has passed, for a proc aura the pack gives one | Modelled | `buff.clearcasting.icd_ready` |
| `buff.<key>.icd_remains` | seconds | Time until that internal cooldown passes | Modelled | `buff.clearcasting.icd_remains<1` |
| `debuff.<key>.up` | boolean | The aura is on the target | Estimated | `debuff.rake.up` |
| `debuff.<key>.remains` | seconds | Time until it ends on the target | Estimated | `debuff.rip.remains>=2` |
| `debuff.<key>.stack` | number | Stacks on the target | Estimated | `debuff.winters_chill.stack=5` |
| `debuff.<key>.duration` | seconds | The aura's full length | Modelled | `debuff.rake.duration>0` |
| `debuff.<key>.refreshable` | boolean | Down, or close enough to its end to recast | Estimated | `debuff.rake.refreshable` |
| `debuff.<key>.ticking` | boolean | A damage-over-time aura is ticking | Estimated | `debuff.rake.ticking` |
| `active_dot.<key>` | number | How many enemies carry the aura | Estimated | `active_dot.bane_of_havoc>0` |

From Frost (wowsims.com):

```simc
actions+=/cone_of_cold,focus=1,if=debuff.winters_chill.stack=5
```

> [!NOTE]
> **On Forever:** During combat the game hides aura durations, so Hekili Forever estimates them from the casts it sees and the aura's length. Where the game's own Cooldown Manager shows an aura, Hekili Forever uses it to confirm that the aura is up ([Cooldown Manager](Cooldown-Manager)).

### Edge cases

- An aura the class pack does not register reads as down, with 0 stacks and 0 remaining.
- `active_dot.<key>` counts the target and the enemies Hekili Forever remembers. When it cannot tell, it counts every enemy as carrying the aura, so a line that looks for an enemy without it does not fire.

## Cooldowns

| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `cooldown.<key>.ready` | boolean | The ability is off cooldown | Read | `cooldown.innervate.ready` |
| `cooldown.<key>.up` | boolean | The same as `ready` | Read | `cooldown.whirlwind.up` |
| `cooldown.<key>.remains` | seconds | Time until the cooldown ends; 0 when ready | Estimated | `cooldown.judgement.remains<=1` |
| `cooldown.<key>.duration` | seconds | The cooldown's full length | Modelled | `cooldown.judgement.duration>8` |
| `cooldown.<key>.charges` | number | Charges available now | Estimated | `cooldown.innervate.charges>=1` |
| `cooldown.<key>.charges_fractional` | number | Charges, with the next one's progress as a fraction | Estimated | `cooldown.innervate.charges_fractional>1.5` |
| `cooldown.<key>.full_recharge_time` | seconds | Time until every charge is back | Estimated | `cooldown.innervate.full_recharge_time<2` |

From Protection (wowsims.com), Paladin:

```simc
actions+=/swift_judgement,use_off_gcd=1,if=(!action.judgement.known|cooldown.judgement.remains<=(cooldown.judgement.duration-0))
```

> [!NOTE]
> **On Forever:** During combat the game reports whether a cooldown is ready, but not how long it has left. Hekili Forever estimates `remains` from the cast time and the cooldown's length.

## Actions

`action.<key>` reads an ability's facts: whether the character has it, what it costs and whether it can be used.

| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `action.<key>.known` | boolean | The character has learned the ability, and it is not disabled | Read | `action.cat_form.known` |
| `action.<key>.enabled` | boolean | The same as `known` | Read | `action.shred.enabled` |
| `action.<key>.disabled` | boolean | The player disabled the ability in the options | Read | `!action.shred.disabled` |
| `action.<key>.ready` | boolean | Usable and ready now | Estimated | `action.shifting_power.ready` |
| `action.<key>.usable_in` | seconds | Time until its cooldown ends | Estimated | `action.rake.usable_in<1` |
| `action.<key>.cost` | number | Its cost now, after modifiers | Modelled | `energy.lo>=action.shred.cost` |
| `action.<key>.cast` | seconds | Its cast time; 0 for an instant | Modelled | `action.hammer_of_wrath.cast=0` |
| `action.<key>.execute_time` | seconds | Its cast time or its GCD, whichever is longer | Modelled | `action.shred.execute_time<=1.5` |
| `action.<key>.gcd` | seconds | The GCD it triggers | Modelled | `action.shred.gcd>0` |
| `action.<key>.in_range` | boolean | The target is in its range | Read | `action.holy_strike.in_range` |
| `action.<key>.executing` | boolean | It is being cast, or was the last cast with the GCD still running | Estimated | `!action.pyroblast.executing` |
| `action.<key>.travel_time` | seconds | Its flight time to the target | Modelled | `action.incinerate.travel_time<1` |
| `action.<key>.channeling` | boolean | The player is channeling it | Estimated | `action.arcane_missiles.channeling` |
| `action.<key>.charges` | number | The same as `cooldown.<key>.charges` | Estimated | `action.rake.charges>=1` |

From Retribution (wowsims.com):

```simc
actions=call_action_list,name=move_to_melee,if=(!action.holy_strike.known|!action.holy_strike.in_range)
```

### The leveling guard

The built-in priorities wrap each read of another ability in a test of whether it is known: `(!action.cat_form.known|buff.cat_form.up)` reads "Cat Form is up, or the character has not learned it yet". A character below the level of an ability then skips the test instead of waiting for an ability it cannot have. [APL wowsims packs explained](APL-wowsims-Packs-Explained#why-a-built-in-looks-verbose) explains why the guards are there.

### Edge cases

- A line whose own action is unknown is skipped, so it needs no guard.
- An ability the class pack does not register makes the walk report a warning.

## Talents

| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `talent.<key>.enabled` | boolean | The talent has at least one point | Read | `talent.predatory_discipline.enabled` |
| `talent.<key>.rank` | number | Points in the talent; 0 when not taken | Read | `talent.primal_fury.rank>=2` |

A talent key the class pack does not know reads as not taken and adds a warning naming it.

## The target

| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `target.within<N>` | boolean | The target is at most N yards away | Estimated, from range checks | `target.within5` |
| `target.outside<N>` | boolean | The target is at least N yards away | Estimated, from range checks | `target.outside8` |
| `target.range<A>to<B>` | boolean | The target is between A and B yards away | Estimated, from range checks | `target.range8to25` |
| `target.distance` | yards | The middle of the estimated range | Estimated | `target.distance<10` |
| `target.time_to_die` | seconds | See [Time to die](#time-to-die) | Always 3600 | `target.time_to_die>12` |
| `target.is_boss` | boolean | The target is a boss | Read | `target.is_boss` |
| `target.is_player` | boolean | The target is a player | Read | `!target.is_player` |
| `target.is_targeting_player` | boolean | The target is targeting the player | Read; false when hidden | `!target.is_targeting_player` |
| `target.creature_type` | text | The target's creature type in snake case, such as `beast` or `undead`; `unknown` when hidden | Read | `target.creature_type='undead'` |
| `target.is_undead`, `target.is_demon` | boolean | The creature type is undead, or demon | Read | `target.is_undead` |
| `target.moving` | boolean | The target is moving | Read | `!target.moving` |
| `target.health.pct` | percent | The target's health | Always 100 | `target.health.pct<20` |

From Feral (wowsims.com), shortened:

```simc
actions+=/cat_form,if=!buff.cat_form.up&(toggle.movement&target.outside5|target.within5)
```

> [!NOTE]
> **On Forever:** The game gives addons no distance to the target, only whether each spell is in range. Hekili Forever brackets the distance between the ranges of the abilities it tracks. While the bracket is unknown, `target.withinN`, `target.outsideN` and `target.rangeAtoB` are all true, so a range test never blocks a line on its own.

> [!NOTE]
> **On Forever:** The game hides target health. `target.health.pct` reads 100, and a priority that uses it gets a "target health is secret" warning in **Warnings** when it loads.

## Toggles

`toggle.<name>` reads a toggle from the **Toggles** page ([Toggles](Toggles)).

| Expression | Type | Meaning | Example |
|---|---|---|---|
| `toggle.cooldowns` | boolean | Major Cooldowns is on, or treated as on during Bloodlust or Power Infusion when set to | `toggle.cooldowns` |
| `toggle.minor_cooldowns` | boolean | Minor Cooldowns is on, or Major Cooldowns is on and set to enable it | `toggle.minor_cooldowns` |
| `toggle.potions` | boolean | Potions is on, or Major Cooldowns is on and set to enable it | `toggle.potions` |
| `toggle.defensives` | boolean | Defensives is on | `toggle.defensives` |
| `toggle.interrupts` | boolean | Interrupts is on | `toggle.interrupts` |
| `toggle.movement` | boolean | Movement is on, for a specialization whose priority uses it | `toggle.movement&target.outside5` |
| `toggle.custom1`, `toggle.custom2` | boolean | Custom #1 or Custom #2 is on | `toggle.custom1` |

`toggle.essences` is read as `toggle.minor_cooldowns`.

## Settings

`settings.<key>` reads a setting of the specialization ([Specialization options](Specializations-Reference)). A switch reads true or false, a slider a number, and a choice the key of the chosen value, compared in quotes. The built-in priorities read the settings their wowsims.com rotation switches on and off, named `settings.wowsims_<name>`. From Arms (wowsims.com):

```simc
actions+=/whirlwind,if=settings.wowsims_stance_dance
```

A setting key that the specialization does not have reads as missing, which counts as false.

## Previous casts

| Expression | Type | Meaning | Example |
|---|---|---|---|
| `prev.<N>.<key>` | boolean | The Nth most recent cast, counting forecast casts first, was `<key>` | `prev.1.inner_focus` |
| `prev.<key>` | boolean | The same as `prev.1.<key>` | `prev.rake` |
| `prev_gcd.<N>.<key>` | boolean | The same, counting only abilities on the GCD | `prev_gcd.1.rake` |
| `prev_off_gcd.<N>.<key>` | boolean | The same, counting only abilities off the GCD | `prev_off_gcd.1.prowl` |

From Shadow (wowsims.com):

```simc
actions+=/mind_flay,if=((action.inner_focus.known&prev.1.inner_focus)|(!action.inner_focus.known))
```

## The fight and the player

| Expression | Type | Meaning | On Forever | Example |
|---|---|---|---|---|
| `time` | seconds | Time since combat started; 0 out of combat | Read | `time>=0` |
| `active_enemies` | number | Enemies counted ([How targets are counted](How-Targets-Are-Counted)), at least 1 | Read | `active_enemies>=3` |
| `spell_targets.<key>` | number | Enemies counted for the ability; `active_enemies` unless the pack limits it | Read | `spell_targets.swipe_bear>=3` |
| `gcd.remains` | seconds | Time until the running GCD ends | Read | `gcd.remains<=0` |
| `gcd.max` | seconds | The length of a GCD | Modelled | `gcd.max<1.5` |
| `health.pct` | percent | The player's health | Read; 100 while hidden | `health.pct<=30` |
| `totem.<element>.up` | boolean | A totem of that element is down | Read | `!totem.fire.up` |
| `totem.<element>.remains` | seconds | Time until it expires | Estimated | `totem.fire.remains<2` |
| `main_hand.<kind>`, `off_hand.<kind>` | boolean | The weapon in that hand is of a kind, such as `dagger` or `two_handed` | Read | `main_hand.dagger` |
| `equipped.shield` | boolean | A shield is equipped | Read | `equipped.shield` |
| `variable.<name>` | number | A variable ([Variables](APL-Syntax-Reference#variables)) | Not applicable | `variable.pool>0` |

From Protection (wowsims.com), Warrior:

```simc
actions+=/healthstone,use_off_gcd=1,if=health.pct<=30
```

A class pack can register names of its own, such as the swing timers `mainhand_remains`, `mainhand_speed`, `ranged_remains` and `ranged_speed` that several classes define. The class file defines each one ([Pack class file anatomy](Pack-Class-File-Anatomy)).

## See also

- [APL line options](APL-Line-Options)
- [APL windows](APL-Windows): the `window.<name>` expressions
- [APL debugging](APL-Debugging): reading a line's result in a snapshot
