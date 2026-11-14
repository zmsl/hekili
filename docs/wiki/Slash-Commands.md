<!--
Purpose: Every public command and alias.
Type: Reference
Audience: everyone
Prerequisites: None.
-->
The **slash commands** of Hekili Forever are chat commands that open the options, change toggles and settings, and switch priorities, profiles and specializations. Each one starts with `/hekili` or its short form `/hek`. Typed alone, `/hekili` opens the options window. The tables on this page are generated from the addon.

Commands work in macros too, so a toggle or a priority can be changed from an action bar button.

## Commands

<!-- GENERATED:slash-commands -->
<!-- /GENERATED -->

Notes on the table:

- `/hekili set` takes a toggle name ([Toggles](Toggles)), `mode` with a display mode, `cycle` to turn target swaps on or off, or `spec` with the name of a specialization setting. `/hekili help` lists the current specialization's settings and the values each one accepts.
- `/hekili priority` with a name switches to the first of your specialization's priorities whose name starts with what you typed; capitals do not matter. `/hekili priority default` returns to the built-in default ([Choosing a priority](Choosing-A-Priority)).
- `/hekili spec` takes a specialization's short name, such as `feral` or `guardian`.
- `/hekili move`, `/hekili unlock` and `/hekili lock` do nothing in combat.

Examples:

```text
/hekili set cooldowns on
/hekili set mode single
/hekili set spec behind on
/hekili priority default
/hek snap
```

## Word aliases

A few words after `/hekili` have shorter forms. `/hekili prio` is `/hekili priority`, and `/hekili snap` is `/hekili snapshot`. Inside `/hekili set`, the words in the table below can be shortened.

<!-- GENERATED:slash-command-words -->
<!-- /GENERATED -->

## See also

- [Getting started](Getting-Started)
- [Specializations reference](Specializations-Reference): the specialization settings that `/hekili set spec` changes
