<!--
Purpose: Every toggle, its keybind and what it skips; Display Mode; Pause.
Type: Reference
Audience: players
Prerequisites: None.
-->
**Toggles** are switches that let the active priority use, or skip, whole groups of abilities, such as major cooldowns, defensives or interrupts. Each toggle can have a key bound to it, so it can be flipped during a fight. The same page holds the **Display Mode**, which sets how many enemies the displays plan for, and the **Pause** and **Snapshot** keys. All of them are under **/hekili > Toggles**.

## How a toggle works

Each ability can be tied to one toggle with its **Require Toggle** setting ([Abilities and items](Abilities-And-Items)). While that toggle is off, Hekili Forever treats the ability as unusable, as if it were on cooldown. The priority then moves on to its next line, so the recommendation becomes the next ability that is allowed. Turning the toggle back on lets the ability be recommended again at once.

A toggle can be changed in three ways:

- its key, set under **/hekili > Toggles**;
- its check box on the same page;
- a chat command or a macro: `/hekili set <toggle> on`, `/hekili set <toggle> off`, or `/hekili set <toggle>` with no value to flip it.

The toggle names that `/hekili set` accepts are `cooldowns` (also `cd` or `cds`), `minor_cooldowns`, `potions` (also `pot`), `interrupts`, `defensives`, `movement`, `custom1` and `custom2`. For example:

```text
/hekili set cooldowns off
/hekili set defensives
```

Some toggles have their own options:

- The "Show in Separate ... Display" box of **Major Cooldowns**, **Interrupts** and **Defensives** moves the abilities of that toggle out of the **Primary** display and into the **Cooldowns**, **Interrupts** or **Defensives** display. Those displays show something only while this option is on.
- The "Active During Bloodlust" and "Active During Power Infusion" boxes treat **Major Cooldowns** as on while that effect is up, even when the toggle is off.
- **Auto-Enable when Major Cooldowns Active**, under **Minor Cooldowns** and **Potions**, lets those abilities be recommended whenever **Major Cooldowns** is on.
- **Interrupt Timing** sets how late in an enemy's cast an interrupt is recommended: by default, when 0.25 seconds or less of the cast remain.

## Every toggle

The table below lists every option on the **Toggles** page, with its default.

<!-- GENERATED:options-toggles -->
<!-- /GENERATED -->

The **Movement** toggle appears only for specializations whose priority uses it. While it is on, such a priority shows the ability that needs you to move closer, tinted as out of range. While it is off, that ability stays hidden until you are in range.

**Custom #1** and **Custom #2** start empty. Tie abilities to them with **Require Toggle**, and give each a name with **Custom #1 Name** or **Custom #2 Name**.

## Display modes

The **Display Mode** sets how many enemies the **Primary** and **AOE** displays plan for. **Select Display Mode** chooses the mode directly. The **Display Mode** key steps through the modes that are checked below it, and `/hekili set mode` does the same from chat.

| Mode | `/hekili set mode` | What the displays show |
|---|---|---|
| Automatic (Default) | `automatic` (also `auto`) | **Primary** plans for the number of enemies Hekili Forever counts. |
| Single-Target | `single` | **Primary** plans for one enemy, however many are counted. |
| AOE (Multi-Target) | `aoe` | **Primary** plans for at least the AOE minimum of enemies (2 by default). |
| Dual | `dual` | **Primary** plans for one enemy; **AOE** plans for at least the AOE minimum (2 by default), always shown. |
| Reactive Dual Display | `reactive` | **Primary** plans for one enemy; **AOE** appears only while the number of enemies counted reaches the AOE minimum (2 by default). |

The AOE minimum is **Minimum Targets for Dedicated AOE Recommendations**, on each specialization's **Targeting** tab. How enemies are counted is explained in [How targets are counted](How-Targets-Are-Counted).

## Pause and snapshot

- **Pause** freezes every display. While paused, hovering over an icon shows what it recommends. Pausing also takes a snapshot. Press the key again to resume.
- **Snapshot** records why the current recommendations were chosen, without pausing. Snapshots are read on the **Snapshots (Troubleshooting)** page; [Reporting a problem](Reporting-A-Problem) explains how to send one.

## The minimap menu

A left click on the Hekili Forever minimap button, or on its entry in the game's addon compartment, opens a menu of quick changes: "Enable", **Pause**, the **Display Mode**, each toggle under **Toggles**, and, for the current specialization, Recommend Target Swaps, the preferred potion and the class's own on/off and choice settings. A right click opens the options window. Hovering over the button shows the display mode and which toggles are on. **/hekili > General > Hide Minimap Icon** hides the button; the addon compartment entry stays.

## See also

- [Slash commands](Slash-Commands)
- [Displays reference](Displays-Reference)
