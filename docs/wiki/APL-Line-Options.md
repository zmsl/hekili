<!--
Purpose: use_off_gcd, focus, label, icon, cycle_targets, and the refused or ignored options.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL syntax reference](APL-Syntax-Reference).
-->
The **APL line options** are the `<option>=<value>` pairs that follow the action on a priority line, such as `use_off_gcd=1` or `focus=2`. This page lists every option Hekili Forever reads, the options it accepts but does nothing with, and how each path into the addon treats them. The line grammar is in [APL syntax reference](APL-Syntax-Reference), and the matching fields of the editor are in [APL priority editor](APL-Priority-Editor).

An option written `=1` is on; `=0` or leaving it out is off. Options that hold a condition take the same expressions as `if=` ([APL expression reference](APL-Expression-Reference)).

## Options a line accepts

| Option | Value | Effect | Editor field |
|---|---|---|---|
| `if` | Condition | The line is used only while it holds. | **Conditions** |
| `name` | List, ability, variable or window name | The target of `call_action_list`, `run_action_list`, `cancel_action`, `variable`, `open_window` and `close_window` | **Action List**, **Action Name**, **Variable Name**, **Window Name** |
| `use_off_gcd` | 1 | The line can be chosen while the global cooldown (GCD) runs, for an ability that is off the GCD. | **Use Off GCD** |
| `focus` | Whole number, 1 highest | Makes the line a focus candidate for the Timeline display style ([Focus](#focus)). 0 is off. | **Focus Tier** |
| `label` | Text | Text drawn on the recommended icon, while `label_if` holds | **Label** |
| `label_if` | Condition | When the label shows. With no `label_if`, it always shows. | **Label Condition** |
| `icon` | Texture file ID or path | An icon a display can draw in place of the ability's own, while `icon_if` holds | **Icon** |
| `icon_if` | Condition | When the icon override shows | **Icon Condition** |
| `cycle_targets` | 1 | Checks the other enemies and shows a target swap when the line suits another target better ([Target swaps](#target-swaps)) | **Cycle Targets** |
| `max_cycle_targets` | Number | The most targets `cycle_targets` checks | **Max Cycle Targets** |
| `other_target` | 1 | The line is for another enemy only, never the current target | none |
| `buff_name` | Aura key | The aura `cancel_buff` removes | **Buff Name** |
| `sec` | Seconds, or an expression | How long a `wait` line waits (0.5 when not given) | **Seconds** |
| `for_next` | 1 | `pool_resource` delays the walk for the next line ([Pooling](#pooling)) | Pool for Next Entry (*ability*) |
| `extra_amount` | Number | With `for_next=1`, the resource to pool beyond the next line's cost | **Extra Pooling** |
| `value`, `value_else`, `op`, `default` | Expression, operation | A `variable` line's value ([Variables](APL-Syntax-Reference#variables)) | **Value**, **Value when Conditions are Not Met**, **Operation** |
| `refresh`, `duration` | 1, seconds | An `open_window` line's refresh and length ([APL windows](APL-Windows)) | none |
| `line_cd` | Seconds | After the ability is cast in combat, the line waits this long before it can be chosen again. | **Entry Cooldown** |
| `sync` | Ability key | The line waits until that ability is ready too. | none |
| `moving` | 1 or 0 | 1: only while the player moves. 0: only while the player stands still. | **Check Movement**, **Movement** |
| `only_cwc` | 1 | Only while the player channels a spell, for an ability the class pack allows during a channel | **During Channel** |
| `strict` | 1 | On a list call: test the condition now only, with no look ahead | **Test Conditions Immediately** |
| `strict_if` | Condition | On a list call: a condition that must hold now before `if=` is tested | **Additional Immediate Criteria** |
| `target_if` | Condition | Read by the importer as `if=` when the line has none; a leading `min:` or `max:` is removed | none |
| `caption` | Text, 20 characters at most | Short text that can appear on the icon, when the display shows captions | **Caption** |
| `description` | Text | Shown when the display is paused and the icon is hovered | **Description** |
| `interrupt_if`, `interrupt_immediate`, `chain`, `early_chain_if` | Condition | On the line of a channeled ability: when the channel may be broken for another line, or recast at its last tick | none |
| `interrupt` | Condition | On the line of a channeled ability: while it holds, another line may break the channel, once the GCD is ready and at a channel tick | none |

From Feral (wowsims.com):

```simc
actions+=/elunes_light,use_off_gcd=1,if=action.elunes_light.known&(toggle.movement&target.outside5|target.within5)
```

### Focus

The Timeline display style draws one recommendation in its now circle: among the lines with a focus tier that are due within the focus horizon, the lowest tier wins, then the soonest. The built-in priorities give tier 1 to reactive lines the player must catch, such as Shred on Clearcasting, and tier 2 to upkeep, such as Rake and Rip. Other display styles ignore `focus`. From Feral (wowsims.com), shortened:

```simc
actions+=/rip,focus=2,if=((!action.cat_form.known|buff.cat_form.up)&...
```

[Reading the displays](Reading-The-Displays) shows how a focus line looks.

### Target swaps

`cycle_targets=1` and `other_target=1` act only when target swaps are allowed for the specialization (`/hekili set cycle`) and more than one enemy is counted. With a single valid enemy the line is tested on the current target. A line that would be better on another target shows the target-swap indicator on its icon ([How targets are counted](How-Targets-Are-Counted)).

### Pooling

`pool_resource` has two forms. Only one works.

- `pool_resource,for_next=1[,extra_amount=<n>]` works. When the next line's ability is known, usable and off cooldown but its resource is short, the walk moves its clock forward until the low end of the resource covers the cost plus `extra_amount`, and continues only if the next line's condition holds at that time. When the resource is already there, or the wait would pass the current choice, the line does nothing.
- `pool_resource,wait=<seconds>` and `pool_resource` without `for_next=1` are accepted and do nothing.

> [!WARNING]
> **Different from retail Hekili:** A priority does not need `pool_resource` to wait for energy, rage or mana. Every line already waits for its own cost in the forecast ([Comparisons that wait](APL-Expression-Reference#comparisons-that-wait)).

## Ignored options

These options are accepted and stored, but nothing in Hekili Forever reads them:

| Option | Editor field | Note |
|---|---|---|
| `wait` on `pool_resource` | **Pooling Time** | Pooling for a fixed time is not implemented. |
| `max_energy` | **Max Energy** | Shown only for Ferocious Bite, left from an older pooling option |
| `use_while_casting` | **Use While Casting** | |
| `interrupt_global` | none | The channel-breaking options that work are `interrupt`, `interrupt_if`, `interrupt_immediate`, `chain` and `early_chain_if`. |
| `strict`, `strict_if` on an ability line | **Test Conditions Immediately**, **Additional Immediate Criteria** | They act only on `call_action_list`, `run_action_list` and `use_items` lines. |

The importer drops SimulationCraft lines for `snapshot_stats`, `flask`, `food` and `augmentation` without a warning.

## Options by path

- **The importer** reads every option above. It warns in the **Import Log** about an unsupported action, a `use_item` it cannot match to an item (the line is switched off), an unknown window name (the line is switched off) and a `focus` that is not a whole number (the option is dropped).
- **The editor** shows only the fields that apply to the line's action.
- **A priority source** (`tools/make_pack.lua`) accepts `name`, `buff_name`, `use_off_gcd`, `cycle_targets`, `max_cycle_targets`, `other_target`, `focus`, `label`, `label_if`, `icon`, `icon_if` and `if`, and stops the build on any other option.

## See also

- [APL Forever differences](APL-Forever-Differences)
- [APL debugging](APL-Debugging)
