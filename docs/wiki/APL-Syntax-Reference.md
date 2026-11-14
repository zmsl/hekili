<!--
Purpose: Line grammar, operators and precedence, lists, variables, comments.
Type: Reference
Audience: theorycrafters
Prerequisites: [APL overview](APL-Overview).
-->
The **APL syntax reference** describes how Hekili Forever reads the text of a priority: the form of a line, the operators a condition can use and their precedence, the list and variable actions, and comments. The values a condition tests are in [APL expression reference](APL-Expression-Reference), and the options a line can carry are in [APL line options](APL-Line-Options).

Priority text reaches the addon by three paths, which read it slightly differently:

| Path | Where | Notes |
|---|---|---|
| The importer | The **Priority (SimulationCraft Action Priority List)** box on a priority's Source tab, then **Import** | Converts some SimulationCraft forms and reports each change in the **Import Log** |
| The editor | The **Conditions** box of one entry on the Action Lists tab | Stores the text as typed |
| A priority source | The `.simc` files of a class pack, built into the addon by `make packs` | Developer path ([Pack overview](Pack-Overview)) |

Where the paths differ, the tables below say so.

## Line grammar

A line has this form:

```simc
actions[.<list>]=<action>[,<option>=<value>]...[,if=<condition>]
actions[.<list>]+=/<action>[,<option>=<value>]...[,if=<condition>]
```

- `actions` without a list name is the `default` list. `actions.precombat` and `actions.<name>` name other lists ([Lists](#lists)).
- `=` and `+=/` both add the line to the end of its list. Unlike SimulationCraft, `=` does not clear the list first.
- `<action>` is an ability's key, such as `shred` or `cat_form`, or one of the actions in [Special actions](#special-actions). The keys a specialization knows are the choices of the **Action** field in the editor. The importer accepts an unknown key but writes "Unsupported action" in the **Import Log**, and the walk reports the missing ability as a warning.
- Options follow the action, separated by commas. `if=` holds the condition. The other options are listed in [APL line options](APL-Line-Options).
- A line with no `if=` has no condition: it is used whenever its ability is ready.

From Feral (wowsims.com):

```simc
actions.precombat=prowl,use_off_gcd=1,if=!buff.prowl.up
actions+=/shifting_power,if=((!action.cat_form.known|buff.cat_form.up)&energy.lo<=57&action.shifting_power.ready)&(toggle.movement&target.outside5|target.within5)
```

### Line edge cases

- The importer splits a line at every comma, so a condition pasted into the importer cannot contain a comma. Write `min(a,b)` and `max(a,b)` in the editor instead, or use the `<?` and `>?` operators.
- The importer ends a line at a `^` or `$` character. Use `^` only in the editor.
- A priority source accepts only the options `tools/make_pack.lua` knows, and stops the build on any other.

## Operators and precedence

Hekili Forever translates a condition to Lua before it runs it. The table lists the operators from the lowest precedence to the highest; operators on one row have the same precedence and group from left to right.

| Precedence | Operator | Meaning | Example |
|---|---|---|---|
| 1 (lowest) | `\|` | Or (`\|\|` is read the same) | `buff.clearcasting.up\|energy.lo>=60` |
| 2 | `&` | And | `combo_points.current>=5&debuff.rip.up` |
| 3 | `!` | Not, applied to everything up to the next `&`, `\|` or closing bracket | `!debuff.rake.up` |
| 4 | `=` `!=` `<` `<=` `>` `>=` | Comparison (`==` is read as `=`) | `combo_points.current=5` |
| 4 | `^` | Exclusive or: true when exactly one side is true | `buff.prowl.up^buff.cat_form.up` |
| 5 | `+` `-` | Addition, subtraction | `energy.lo+energy.regen>=40` |
| 6 | `*` `/` `%` | Multiplication, division, remainder ([Arithmetic](#arithmetic)) | `fight_remains*50` |
| 7 (highest) | `-` | Negation | `-1` |

Brackets `( )` group as usual. From Feral (wowsims.com), shortened:

```simc
actions+=/innervate,if=((!action.cat_form.known|buff.cat_form.up)&cooldown.innervate.ready&...&mana.lo<(fight_remains*50)&...)
```

### Functions and value operators

| Form | Meaning | Example |
|---|---|---|
| `a<?b` | The larger of `a` and `b` | `energy.lo<?30>=30` |
| `a>?b` | The smaller of `a` and `b` | `(energy.lo>?30)>=30` |
| `@x` | The absolute value of `x`; bracket `x` | `@(energy.deficit-5)<5` |
| `max(a,b,...)` | The largest argument; a `false` argument is skipped | `max(energy.lo,10)>=10` |
| `min(a,b,...)` | The smallest argument; a `false` argument is skipped | `min(energy.lo,5)<=5` |
| `floor(x)`, `ceil(x)`, `abs(x)` | Rounding down, rounding up, absolute value | `floor(energy.lo/20)>=2` |

### Numbers and true or false

- A true or false value used in arithmetic counts as 1 or 0: `buff.cat_form.up+buff.prowl.up>=1` is true when either buff is up.
- A number used as a condition is false when it is 0, and true otherwise. A missing value is false.
- A text value is written in quotes: `settings.<key>='<choice>'` compares a choice setting ([Pack settings](Pack-Settings)).

### Arithmetic

- `/` is division. The WoW client raises an error on division by zero, unlike standard Lua, so a value that can be zero must not be a divisor.
- In the editor and in a priority source, `%` is the remainder (modulo), as in Lua.
- The importer follows SimulationCraft: it turns `%` into `/` (division) and `%%` into `%` (remainder), and notes each change in the **Import Log**.

### Short forms

A bare resource name stands for its current value: `energy>=40` reads `energy.current>=40`. The same holds for `health` and `spell_targets` (read as `spell_targets.any`), and `gcd` reads `gcd.execute`.

The importer also rewrites a few SimulationCraft forms and lists each in the **Import Log**: `talent.<key>` becomes `talent.<key>.enabled`, `toggle.essences` becomes `toggle.minor_cooldowns`, and a bare `gcd` becomes `gcd.max`.

## Lists

| Action | Form | Effect |
|---|---|---|
| `call_action_list` | `call_action_list,name=<list>[,if=<condition>]` | Walks `<list>` here when the condition holds. If nothing in it is chosen, the walk continues with the next line. |
| `run_action_list` | `run_action_list,name=<list>[,if=<condition>]` | Walks `<list>` as `call_action_list` does. While the condition holds, no later line of the calling lists can be chosen. |

- A list name uses letters, digits and underscores only, at least two characters long, in the editor's **List Name** field.
- A call of a list that does not exist is skipped. So is a call of a list already being walked, which would loop.
- `precombat` and `default` always exist. A new priority starts with one disabled `wait` line in each.

From Frost (wowsims.com):

```simc
actions+=/call_action_list,name=aoe,if=active_enemies>=3
```

## Variables

A variable gives a name to a value that several lines use.

```simc
actions+=/variable,name=<name>[,op=<operation>],value=<expression>[,value_else=<expression>][,if=<condition>]
```

A line reads it as `variable.<name>`. The value is worked out when a line reads it: every `variable` line with that name is evaluated in list order, each on the path the walk would take, starting from 0. A variable that no line sets reads 0, and the walk adds a warning naming it.

| `op=` | Editor label | Effect when the condition holds |
|---|---|---|
| `set` (default) | "Set Value" | The value becomes `value`. When the condition fails, it becomes `value_else` if one is given. |
| `setif` | "Set Value If..." | The same as `set` |
| `reset` | "Reset to Default" | The value becomes `value`, else `default`, else 0 |
| `default` | "Set Default Value" | Leaves the value as it is; a `default=` option on the line is the value that `set` and `reset` use when `value` is missing |
| `add`, `sub`, `mul`, `div`, `mod`, `pow` | "Add Value", "Subtract Value", "Multiply Value", "Divide Value", "Modulo of Value", "Raise Value to X Power" | Applies `value` to the current value; dividing by 0 gives 0 |
| `max`, `min` | "Maximum of Values", "Minimum of Values" | Keeps the larger or smaller of the current value and `value` |
| `floor`, `ceil` | "Floor of Value", "Ceiling of Value" | Rounds the current value |

- A variable name has at least three characters (**Variable Name** in the editor).
- A class pack can register a variable of the same name. The class pack's value then wins, and the line is ignored.
- A true or false `value` is stored as 1 or 0. Test it as `variable.<name>` or `variable.<name>>0`.
- Each walk works variables out again from nothing ([APL overview](APL-Overview#each-evaluation-stands-alone)).

## Special actions

| Action | Form | Effect |
|---|---|---|
| `wait` | `wait,sec=<seconds>[,if=<condition>]` | Shows a wait in the queue for `sec` seconds (0.5 when not given). A value of 0 or less skips the line. |
| `pool_resource` | `pool_resource,for_next=1[,extra_amount=<n>]` | Delays the walk until the next line's ability is affordable, plus `extra_amount` ([APL line options](APL-Line-Options#pooling)) |
| `cancel_action` | `cancel_action,name=<ability>[,if=<condition>]` | While the player channels `<ability>` and the condition holds, lets the walk recommend something that breaks the channel |
| `cancel_buff` | `cancel_buff,buff_name=<aura>[,if=<condition>]` | Recommends removing a buff, when the class pack defines a way to cancel it |
| `open_window`, `close_window` | `open_window,name=<window>[,if=<condition>]` | Opens or closes a rotation window for the rest of the walk ([APL windows](APL-Windows)) |
| `use_items` | `use_items[,if=<condition>]` | Walks the equipped items that can be used |

The importer turns SimulationCraft's `wait_for_cooldown,name=<ability>` into `wait,sec=cooldown.<ability>.remains`.

## Comments

A line that starts with `#` is a comment.

- In the importer, a comment attaches to the next line as its description, shown when the display is paused and the icon is hovered. A comment in the form `<caption>::<description>` also sets the line's caption, the short text that can appear on the icon.
- In a priority source, the `#` lines at the top of the file are the priority's description. Other `#` lines are dropped.

## See also

- [APL Forever differences](APL-Forever-Differences)
- [APL priority editor](APL-Priority-Editor)
- [APL debugging](APL-Debugging)
