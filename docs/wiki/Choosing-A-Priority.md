<!--
Purpose: Which priority runs and why, choosing another, handing the choice back.
Type: How-to
Audience: players
Prerequisites: None.
-->
This page shows how Hekili Forever decides which priority to use, how to choose another one, and how to hand the choice back. A priority is the ordered list of abilities, with conditions, that the displays follow. Every built-in priority is listed in [Supported classes and priorities](Supported-Classes-And-Priorities).

## Which priority runs

Hekili Forever treats each talent tree as a specialization, with its own priorities and settings. Feral Combat is the exception: it has two specializations, Feral and Guardian.

At login, after a respec and after a talent change, Hekili Forever settles which specialization and priority to use:

1. If you chose a specialization or a priority yourself, that choice is used.
2. Otherwise, some classes pick from your talents. For example, a Fire Mage build with Ice Shards gets Frostfire (wowsims.com), and a Feral Combat build with all three points in Thick Hide gets Guardian. A chat notice names the priority picked from your talents.
3. Otherwise, the specialization of the tree with the most points runs its default priority.

An automatic pick never replaces a priority you chose yourself, or a custom priority.

## Choose another priority

1. Type `/hekili` and open **Priorities**, then your specialization.
2. Choose a priority in **Priority**, at the top of the page. The active priority is marked with a green check in the list on the left.

From chat, type `/hekili priority` to list your specialization's priorities, then `/hekili priority` and the start of a name to switch:

```text
/hekili priority
/hekili priority frostfire
```

A priority chosen this way is kept until you choose another one, or hand the choice back.

## Hand the choice back

Type `/hekili priority default`. Hekili Forever switches to the built-in default priority, and the automatic picks from your talents apply again.

## Choose the specialization

When Hekili Forever runs a specialization you do not play, choose it yourself. Each talent tree remembers its own choice:

- type `/hekili spec` to list the specializations, then `/hekili spec` and a name, such as `/hekili spec guardian`; or
- press **Activate *your specialization*** on that specialization's page under **Priorities**.

## Check that it works

Take a look at the **Priorities** list: the active priority has a green check. Type `/hekili priority`; the current one is marked "(current)".

## See also

- [Specializations reference](Specializations-Reference): every option on a specialization's page
- [wowsims priorities explained](APL-wowsims-Packs-Explained)
- [APL tutorial: your first custom priority](APL-Tutorial-Your-First-Custom-Priority)
