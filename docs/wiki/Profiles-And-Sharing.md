<!--
Purpose: Profiles, and importing and exporting displays and priorities.
Type: How-to
Audience: players
Prerequisites: None.
-->
This page shows how to keep separate sets of settings in profiles, and how to share display styles and priorities with other players through import strings. Every Hekili Forever setting is saved in a profile: displays, toggles, specialization settings and priorities.

## Profiles

A profile is one complete set of settings. All characters share the profile named Default until another one is chosen. Profiles are on the Profiles page of the options window (`/hekili`).

- To make a new profile, type its name in the "New" box and press Enter. The new profile starts with the default settings and becomes the active one.
- To switch, choose a profile in "Existing Profiles", or type `/hekili profile` and its name. `/hekili profile` alone lists the profiles and marks the current one.
- To copy another profile's settings into the active one, choose it in "Copy From".
- To start over, press "Reset Profile". The active profile goes back to the default settings.
- To delete a profile that is not in use, choose it in "Delete a Profile".

"Enable spec profiles" switches profiles when the game reports a change of specialization. The Forever client reports one specialization for each class, so the option may have no effect there; it has not been checked on Forever. <!-- UNVERIFIED: LibDualSpec keys on C_SpecializationInfo (Libs/LibDualSpec-1.0/LibDualSpec-1.0.lua); Forever reports one pseudo-spec per class, so it cannot follow talent trees. Not tested in game. -->

Switching profiles for a macro:

```text
/hekili profile Raid
```

## Share display styles

A display style is the look and placement of one or more displays.

To export:

1. Open **/hekili > Displays > Share Styles**, then the **Export** tab.
2. Check the displays to include, then press **Export Style**.
3. Copy the string that appears and send it. To keep it for later, give it a **Style Name** and press **Store Export String**. A stored style can be used from any of your characters, whatever their profile.

To import:

1. Open the **Import** tab of **Share Styles**.
2. Paste a string into **Import String**, or choose a stored style in **Select a Saved Style**, then press **Import Style**.
3. Check the summary and press **Apply Changes**.

## Share priorities

To export a priority:

1. Open **/hekili > Priorities > Import / Export**, then the **Export** tab.
2. Choose the priority in **Priorities**.
3. Copy the string from **Priority Export String**: click it, press Ctrl+A, then Ctrl+C.

To import a priority:

1. Open the **Import** tab of **Import / Export**.
2. Paste the string into **Import String** and press **Import Priority**.
3. Check the name, date and specialization shown, then press **Apply Changes**.

An imported priority is a custom priority: it is not updated when Hekili Forever is updated, and only priorities written for Hekili Forever work. A priority exported from the original Hekili names specializations and abilities of another game version, and needs translating first ([APL Forever differences](APL-Forever-Differences)).

When an update of Hekili Forever changes a built-in priority, the new version replaces the saved one, and edits made to it are lost; a chat notice names each priority replaced. To change a built-in priority, copy it first with the copy button on its **Summary** tab, and edit the copy. [APL tutorial: your first custom priority](APL-Tutorial-Your-First-Custom-Priority) has the steps.

## Check that it works

After switching profiles, the displays move to the places saved in that profile. After importing a priority, it appears in the **Priority** list of its specialization, and `/hekili priority` lists it.

## See also

- [Choosing a priority](Choosing-A-Priority)
- [Setting up displays](Setting-Up-Displays)
