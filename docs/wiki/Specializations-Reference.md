<!--
Purpose: Every option on a specialization page, plus each class's settings.
Type: Reference
Audience: everyone
Prerequisites: None.
-->
The **specializations reference** lists every option on a specialization's page under **/hekili > Priorities**, and the settings each class adds for its specializations. The tables are generated from the addon. Each specialization keeps its own values, saved in the profile, except the **Performance** options, which are one value for the whole profile.

| Specialization page | |
|---|---|
| Where | **/hekili > Priorities**, then *your specialization* |
| Tabs | **Specialization Settings**, **Targeting**, **Performance**, then one page per priority |
| Saved | Per specialization, in your profile; **Performance**: once per profile |

## Specialization page options

Shown for one specialization; every specialization has the same options, with its own name in place of *your specialization*. The sections are:

- **Specialization Settings**: the priority in use (**Priority**), the button that makes this specialization the active one, the potion to recommend, the class's own settings and the switch that turns recommendations off for this specialization.
- **Targeting**: how enemies are counted ([How targets are counted](How-Targets-Are-Counted), [Setting up target counting](Setting-Up-Target-Counting)).
- **Performance**: **Frame Budget**, the share of each frame that working out recommendations may use, and **Forecast window (s)**, how far ahead the **Primary** and **AOE** displays look for the next ability that can be afforded. Raise the forecast window if the queue stays empty while a resource builds up. Both are saved once per profile: a change on one specialization's page applies to every specialization.

<!-- GENERATED:options-spec -->
<!-- /GENERATED -->

Notes on the table:

- **Count Targets Near Your Pet** appears only for classes that have a pet ability it can use.
- **Filter by Time-to-Die** is not listed: it is always hidden on Forever, because the game hides target health, so the time until an enemy dies is unknown.
- The **Nameplate Detection** options appear only while **Count Nameplates Near You** is checked, and **Enemy Range Radius** only once **Show Enemy Nameplates** and **Show All Nameplates** are both on.
- A specialization with no priorities on Forever shows a notice in place of these options.

Each priority of the specialization has its own page below these tabs, with its summary, its source, its action lists and its export string. The [APL priority editor](APL-Priority-Editor) page describes them.

## Class settings

The settings in the table below appear on **Specialization Settings** for the specializations listed. Built-in priorities read them. A setting with "(wowsims.com)" in its name is a switch of the wowsims.com rotation, with the default that wowsims.com gives it.

<!-- GENERATED:spec-settings -->
<!-- /GENERATED -->

A class setting can also be changed from chat or a macro with `/hekili set spec`, followed by the setting's name and a value. `/hekili help` lists the current specialization's settings by name, with their values. For example, for a Druid:

```text
/hekili set spec behind on
```

## See also

- [Choosing a priority](Choosing-A-Priority)
- [Pack settings](Pack-Settings): how a class addon declares a setting
