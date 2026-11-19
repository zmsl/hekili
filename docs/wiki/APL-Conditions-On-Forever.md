<!--
Purpose: Which condition expressions work on Forever, which are estimated or limited, which never change, and what to write instead.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL expression reference](APL-Expression-Reference).
-->
**APL conditions on Forever** lists how well each family of condition expressions works on the Forever client, for authors who write their own priority. Most expressions work as they do in the original Hekili. Some read an estimate, because the game hides the value from addons; some work only in some places; and a few never change. The tables, written by hand, give each family's support and, where a better test exists, what to write instead.

What each expression means is in [APL expression reference](APL-Expression-Reference). Why the game hides values is in [What Hekili Forever can and cannot know](What-Hekili-Forever-Can-And-Cannot-Know).

## Support levels

| Support | Meaning |
|---|---|
| Read | The game reports the value, so the condition works as in retail Hekili. |
| Estimated | The game hides the value in combat or always, and Hekili Forever estimates it from what the game still reports. |
| Limited | The condition works, except in the situations the table names. |
| Fixed | The value does not change on Forever; the table gives what it reads. |

In the tables, "n/a" in the "Write this instead" column means the expression can be used as it is, or that nothing replaces it.

## Common rewrites

| Written for retail Hekili | Write on Forever | Why |
|---|---|---|
| `mana.pct<30` | `mana.pct_lo<30` | The game hides mana; the low end is the amount certain to be there. |
| `energy.current>=50` | `energy.lo>=50` | The same for energy and rage |
| `target.health.pct<20` | `target.health.pct<=20` | Target health reads the threshold of an ability limited by target health, not less; on a specialization without one, remove the test. |
| `fight_remains<8` | Remove the test | The time to die is unknown, so the test never passes. |
| `target.time_to_die>12` | Remove the test | The test always passes. |

From Affliction (wowsims.com), a line written this way:

```simc
actions+=/life_tap,if=(mana.pct_lo<30&fight_remains>60)
```

## Resources

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `combo_points.current` and its fields | Read | The game reports combo points; `lo`, `current` and `hi` are equal. | n/a |
| `<resource>.max` | Read | The maximum, read from the game | n/a |
| `<resource>.current`, `<resource>.pct` | Estimated | The best guess for mana, energy and rage, which the game hides | `<resource>.lo`, `<resource>.pct_lo` |
| `<resource>.lo`, `<resource>.pct_lo` | Estimated | The low end of the estimate: the amount that is certain to be there | n/a |
| `<resource>.hi` | Estimated | The high end of the estimate | n/a |
| `<resource>.deficit`, `<resource>.deficit_pct` | Estimated | Worked out from the best guess | `<resource>.hi>=<resource>.max-<N>` to act before the resource caps |
| `<resource>.regen` | Estimated | The regeneration rate the class pack models | n/a |
| `<resource>.time_to_max`, `<resource>.time_to_<N>`, `<resource>.time_to_deficit_<N>` | Estimated | Worked out from the best guess, not the low end | A comparison that waits, such as `energy.lo>=60` |
| `cast_regen` | Estimated | From the modelled regeneration | n/a |

- A comparison such as `energy.lo>=60` also waits: Hekili Forever shows the ability as far ahead as the resource takes to arrive ([Comparisons that wait](APL-Expression-Reference#comparisons-that-wait)).
- The high end has no percentage: write `mana.hi>=mana.max*0.9`, not `mana.pct_hi`.
- A resource the class does not have, such as `mana` on a class without mana, is an error in the condition.

## Time to die and fight length

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `fight_remains`, `time_to_die` | Fixed | 3600 s, meaning unknown, less the time the forecast looks ahead | Remove the test |
| `target.time_to_die` | Fixed | 3600 s, meaning unknown | Remove the test |
| `target.time_to_pct_<N>` | Fixed | 2520 s, meaning unknown, less the time the forecast looks ahead | Remove the test |
| `time_to_pct_<N>` | Fixed | 3600 s, less the time the forecast looks ahead | Remove the test |
| `expected_combat_length` | Fixed | 3600 s plus `time` | Remove the test |

> [!NOTE]
> **On Forever:** The game hides target health, so the time until an enemy dies is unknown. A test such as `fight_remains>60` always passes and `fight_remains<8` never does. To act on a part of the fight, `time` (the seconds since combat started) is read.

## Health

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `target.health.pct`, `target.health.current`, `target.health_pct` | Limited | 100 until an ability usable only below a target-health threshold becomes usable; then that threshold, such as 20 | `<=` at the ability's threshold: `target.health.pct<=20`, not `target.health.pct<20` |
| `health.pct`, `health.current` | Limited | The player's health as the game reports it out of combat; full (100) in combat, where the game hides it | Leave the test out: a low-health check never passes in combat |
| `group_health`, `at_risk` | Fixed | Every other group member reads as full, because the game hides other players' health, and the player reads as `health.pct` does. `group_health` is the group's average health; `at_risk` counts the members below 70% health, so in combat it reads 0 | n/a |
| `incoming_damage_<N>s`, `incoming_physical_damage_<N>s`, `incoming_magic_damage_<N>s`, `incoming_heal_<N>s` | Fixed | 0, because the game hides the amount of each hit and heal on the player | n/a |

- On a specialization with no ability limited by target health, `target.health.pct` always reads 100. A priority that reads target health gets a warning in **Warnings** when it loads. A priority that reads the player's health gets one too.
- A class pack can name the low-health phase itself; its class file lists such names ([Pack class file anatomy](Pack-Class-File-Anatomy)).

## Buffs and debuffs

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `buff.<key>.up`, `buff.<key>.down` | Estimated | Read out of combat; in combat, estimated from the player's casts and confirmed by the [Cooldown Manager](Cooldown-Manager) when the aura is on one of its bars | n/a; add the aura to a Cooldown Manager bar |
| `buff.<key>.remains`, `buff.<key>.refreshable` | Estimated | In combat, from the cast and the aura's length | n/a |
| `buff.<key>.stack`, `buff.<key>.react` | Estimated | In combat, from the casts and procs the class pack models; the Cooldown Manager shows whether the aura is up, not its stacks | `buff.<key>.up` when any stack is enough |
| `buff.<key>.duration`, `buff.<key>.max_stack` | Read | From the class pack | n/a |
| `debuff.<key>.up`, `.remains`, `.stack`, `.ticking`, `.refreshable` | Estimated | From the player's casts, since the game hides the target's auras in combat, and corrected by the Cooldown Manager when the debuff is on one of its bars | n/a |
| `active_dot.<key>` | Limited | The target and the enemies Hekili Forever remembers, which needs enemy nameplates; while unknown, every enemy counts as carrying the aura | n/a |
| `buff.<key>.icd_ready`, `buff.<key>.icd_remains` | Estimated | From the proc's last application | n/a |

## Cooldowns and abilities

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `cooldown.<key>.ready`, `cooldown.<key>.up` | Read | Whether the cooldown has ended | n/a |
| `cooldown.<key>.remains`, `.charges`, `.charges_fractional`, `.full_recharge_time` | Estimated | Read out of combat; in combat, from the last cast and the cooldown's length, set to 0 when the game reports the cooldown ready | n/a |
| `action.<key>.known`, `.enabled`, `.disabled` | Read | Read from the game and the options | n/a |
| `action.<key>.in_range` | Read | The game's range check for the ability | n/a |
| `action.<key>.ready`, `action.<key>.usable_in` | Estimated | Built on the cooldown and resource estimates | n/a |
| `action.<key>.cost`, `action.<key>.travel_time` | Read | From the class pack | n/a |
| `action.<key>.cast`, `.execute_time`, `.gcd` | Estimated | From the class pack, scaled by the haste estimate in combat | n/a |
| `gcd.remains`, `gcd.max` | Estimated | From the player's casts and the haste estimate | n/a |
| `prev.<N>.<key>`, `prev_gcd.<N>.<key>`, `prev_off_gcd.<N>.<key>` | Read | The player's own casts, then the forecast's | n/a |
| `channeling`, `channel_remains` | Read | The player's own cast | n/a |
| `totem.<element>.up`, `totem.<element>.remains` | Estimated | In combat, from the player's casts and each totem's length | n/a |

## The target

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `target.exists`, `target.is_player`, `target.is_dead`, `target.level` | Read | Read from the game | n/a |
| `target.within<N>`, `target.outside<N>`, `target.range<A>to<B>`, `target.distance` | Estimated | From the range checks of the abilities Hekili Forever tracks; while the range is unknown, all are true | n/a |
| `target.is_boss` | Limited | Read in the open world; in dungeons and raids, a boss that the game does not show as a world boss can read false | n/a |
| `target.creature_type`, `target.is_undead`, `target.is_demon` | Limited | Read in the open world; `unknown` and false in dungeons and raids | n/a |
| `target.is_targeting_player` | Limited | Read in the open world; false while the game hides it, as in dungeon fights | n/a |
| `target.casting` | Estimated | Whether the target is casting is read; how long the cast lasts is not | n/a |
| `target.moving` | Limited | Read out of combat; false in combat, because the game hides the target's speed | n/a |

<!-- UNVERIFIED: target.is_boss inside a dungeon boss fight is not measured; the boss comparison is hidden there under the identity restriction. -->

## Enemies

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `active_enemies`, `spell_targets.<key>` | Limited | Counts the target and the enemies with a nameplate, with **Count Nameplates Near You**; without enemy nameplates it is usually 1, in dungeons and raids always ([How targets are counted](How-Targets-Are-Counted)) | n/a |
| `cycle_enemies` | Limited | Needs **Allow Target Swaps** and enemy nameplates; otherwise 1 | n/a |
| `raid_event.adds.up`, `.count`, `.in`, `.remains` | Limited | Worked out from `active_enemies`; `.remains` reads `fight_remains` | `active_enemies>1` |

## The player and the fight

| Expression | Support | On Forever | Write this instead |
|---|---|---|---|
| `time` | Read | Seconds since combat started | n/a |
| `moving` | Read | The player is moving | n/a |
| `aggro`, `tanking` | Read | From the game's threat status | n/a |
| `level`, `solo`, `group`, `latency` | Read | Read from the game | n/a |
| `haste`, `spell_haste`, `melee_haste`, `crit`, `mastery_value` | Estimated | Read out of combat; in combat, the last read adjusted for the buffs the class pack knows | n/a |
| `talent.<key>.enabled`, `talent.<key>.rank` | Read | Read from the game | n/a |
| `equipped.<item>`, `set_bonus.<name>`, `main_hand.<kind>`, `off_hand.<kind>` | Read | From the equipped gear | n/a |
| `trinket.t1.cooldown.ready`, `trinket.t2.cooldown.ready` and other item cooldowns | Read | The game reports item cooldowns | n/a |
| `pet.alive` and the other pet values | Read | Read from the game | n/a |
| Swing timers, such as `mainhand_remains` | Estimated | Names a class pack registers; from the swings the game reports, with the swing speed estimated in combat | n/a |
| `toggle.<name>`, `settings.<key>`, `variable.<name>` | Read | Values of the addon, not of the game | n/a |
| `window.<name>.*` | Read | Rotation windows a class pack opens from what the game reports ([APL windows](APL-Windows)) | n/a |

## See also

- [APL Forever differences](APL-Forever-Differences): the same differences, beside SimulationCraft and retail Hekili
- [APL debugging](APL-Debugging): reading a line's result in a snapshot
- [Accuracy](Accuracy): how much the hidden values cost, per specialization
