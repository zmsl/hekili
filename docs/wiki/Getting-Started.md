<!--
Purpose: From first login to a placed display with working toggle keybinds.
Type: Tutorial
Audience: players
Prerequisites: Hekili Forever installed ([Installing](Installing)).
-->
This tutorial takes a newly installed Hekili Forever from the first login to a placed display, toggles bound to keys and a first recommendation. It takes a few minutes, out of combat. Install the addon first, as [Installing](Installing) describes.

## What you will have at the end

- The **Primary** display placed where you want it on the screen.
- Keys that turn the main groups of abilities, such as major cooldowns, on and off during a fight.
- A first recommendation: the ability to press next, with the ones that follow it.

## Open the options

1. Type `/hekili` in chat. The short form `/hek` does the same. The options window opens, and every display shows on the screen while it is open.
2. Open **Getting Started** on the left for the addon's own short guide. This tutorial covers the same ground.
3. Type `/hekili help` to list the chat commands in the chat window. [Slash commands](Slash-Commands) lists them all.

## Check your specialization

Hekili Forever treats each talent tree as a specialization with its own priorities and settings. It picks the tree you have spent the most points in.

1. Type `/hekili spec`. The chat lists your class's specializations and marks the current one.
2. If the current one is not the one you play, type `/hekili spec` and its name, for example `/hekili spec guardian`.

A specialization marked "no priorities on Forever" recommends nothing. [Supported classes and priorities](Supported-Classes-And-Priorities) lists every specialization.

## Place the displays

1. Leave combat. The displays cannot be moved in combat.
2. Type `/hekili move`. The displays unlock and show even without a target.
3. Drag the **Primary** display to where you want it. Drag the **AOE** display as well if you plan to use a display mode that shows two displays.
4. Type `/hekili lock`. The displays lock in place.

To place a display by number instead, set **X** and **Y** on the **Icons** tab of **/hekili > Displays > Primary**.

<!-- TODO-SCREENSHOT: the Primary and AOE displays unlocked for moving -->

## Bind the toggles

A toggle is a switch that lets the priority use, or skip, one group of abilities. Several toggles have a key bound already:

| Toggle | Default key |
|---|---|
| **Major Cooldowns** | ALT-SHIFT-R |
| **Minor Cooldowns** | ALT-SHIFT-G |
| **Interrupts** | ALT-SHIFT-I |
| **Defensives** | ALT-SHIFT-T |
| **Display Mode** | ALT-SHIFT-N |
| **Pause** | ALT-SHIFT-P |
| **Snapshot** | ALT-SHIFT-[ |

1. Open **/hekili > Toggles**.
2. To change a key, click the key box of a toggle and press the new key.
3. Close the options and press the **Major Cooldowns** key. A message on the screen or in chat reports that Major Cooldowns are now off. Press it again to turn them back on.

[Toggles](Toggles) describes every toggle and what it skips.

## See a first recommendation

1. Target an enemy. The **Primary** display shows a row of icons.
2. The first icon is the ability to press now. The icons after it are the abilities to press after it, in order.
3. The text in a corner of an icon is the key bound to that ability on your action bars.

Hekili Forever shows recommendations; it never presses anything for you.

<!-- TODO-SCREENSHOT: the Primary display with a first recommendation on an open-world enemy -->

## Next steps

- Learn what each part of a display means in [Reading the displays](Reading-The-Displays).
- Choose how the displays react to several enemies with the **Display Mode** toggle or `/hekili set mode`, described in [Toggles](Toggles#display-modes).
- Make Hekili Forever count the enemies near you in [Setting up target counting](Setting-Up-Target-Counting).
- Pick another priority in [Choosing a priority](Choosing-A-Priority).
