<!--
Purpose: RegisterSetting, toggle and choice settings, how a priority reads settings.x.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
-->
A **class setting** is an option a class pack adds to its specializations' options pages, such as the Druid's Always Behind. A pack registers it with `RegisterSetting`, the player changes it on the spec's page or with `/hekili set`, and priorities and pack code read it as `settings.<key>`. This page describes the call, the kinds of setting, how each layer reads a setting, and lists every class setting the packs ship.

| Class settings | |
|---|---|
| Call | `kit:RegisterSetting(key, default, option, specKey, ...)` |
| Defined in | `src/Hekili/Engine/Schema/Spec.lua` |
| Kinds | Toggle (`"toggle"`), number (`"range"`), choice (`"select"`) |
| Shown on | The specialization's page under **Priorities** |
| Read as | `settings.<key>` in a priority, a `handler`, a `now` or a `usable` |
| Saved | Per specialization, in the player's profile |

## RegisterSetting

```lua
kit:RegisterSetting(key, default, option, specKey, ...)
```

| Parameter | Meaning |
|---|---|
| `key` | The setting's key: what `settings.<key>` reads and what the profile stores |
| `default` | The value until the player changes it |
| `option` | An AceConfig option table: `type`, `name`, `desc`, `width` and, for a choice, `values` and `sorting`. Two extra fields are described below. |
| `specKey, ...` | The specs that get the setting, by key. Without any, every supported spec gets it. An unknown key is an error. |

Called on the class kit, the setting is registered on each wanted spec with its own copy of `option`, so each spec keeps its own value. From `src/Hekili_Druid/Druid.lua`:

```lua
local behind = {
    type = "toggle",
    name = L["Always Behind"],
    desc = L["Hekili assumes you are always behind the target. ..."],
    width = "full",
}
spec:RegisterSetting("behind", false, behind, "feral", "balance")
```

The `name` and `desc` are player text, so they are written as `L["..."]`.

### Extra option fields

Two fields of `option` are read by the core and removed before the table reaches AceConfig:

| Field | Meaning |
|---|---|
| `sim` | The setting's value in the test harness, where it differs from the default in game. A setting with `sim` and a text description gets a sentence added to the description that says how the harness runs it. |
| `section` | `{ name, desc }`: the options page opens a section, with a header and a line of text, before this setting |

From `src/Hekili_Druid/Druid.lua`: keeping Demoralizing Roar on the target is off in game and on in the harness, which models a raid boss.

```lua
local roar = {
    type = "toggle",
    name = L["Maintain Demoralizing Roar"],
    desc = L["Keep Demoralizing Roar on the target, as a raid tank does, ..."],
    width = "full",
    sim = true,
}
spec:RegisterSetting("maintain_demoralizing_roar", false, roar, "guardian")
```

## Kinds of setting

- Toggle, `type = "toggle"`: true or false. `/hekili set spec <key>` flips it; `on` or `off` sets it.
- Number, `type = "range"` with `min`, `max` and `step`: `/hekili set spec <key> <number>` sets it within its range.
- Choice, `type = "select"`: one of several candidates. `values` maps each candidate key to the name shown, and `sorting` lists their order. The default and `sim` must be candidates, or `RegisterSetting` raises an error. The options page shows a dropdown, and `/hekili set spec <key> <candidate>` sets it.

From `src/Hekili_Warlock/Warlock.lua`, shortened:

```lua
spec:RegisterSetting("assigned_curse", "elements", {
    type = "select",
    name = L["Assigned Curse"],
    desc = L["The curse the wowsims.com priority keeps on the target ..."],
    values = {
        elements = curseName(440892, L["Curse of the Elements"]),
        recklessness = curseName(704, L["Curse of Recklessness"]),
        weakness = curseName(702, L["Curse of Weakness"]),
        nocurse = L["No Curse"],
    },
    width = "full",
    sim = "elements",
})
```

## Reading a setting

A priority line reads `settings.<key>`. A toggle reads as true or false, a number as the number, and a choice as its candidate key, compared with a quoted string. From the Warlock's generated priorities, shortened:

```simc
actions+=/curse_of_recklessness,if=settings.assigned_curse='recklessness'&...
```

The script language passes a quoted string through as it is, so a candidate key may contain any name.

Pack code reads the same name in both layers:

- **In the simulation** (a `handler`, a `usable`, a state expression), `settings.<key>` reads the active spec's value from the profile at the moment of the read. An unset value reads the setting's default.
- **In the belief** (a `now`, a window's evaluator), `settings.<key>` reads a plain copy of the active spec's values, which the core refreshes whenever a setting changes.

Each spec keeps its own value, and `settings.<key>` always reads the active spec's. A setting that another spec's imported lists read must therefore also be registered on the importing spec; the Druid registers `behind` on Guardian, and `maintain_demoralizing_roar` on Feral, each under a section that names where it comes from.

The wowsims translator turns some of wowsims's switches into settings whose keys start with `wowsims_`; the class file registers each one ([Pack translator rules](Pack-Translator-Rules)).

## Every class setting

The table below lists every class setting the shipped packs register, generated from the class files.

<!-- GENERATED:pack-settings -->
<!-- /GENERATED -->

The [Specializations reference](Specializations-Reference) lists the same settings for players, with their descriptions.

## See also

- [Specializations reference](Specializations-Reference)
- [Pack API reference](Pack-API-Reference)
- [APL expression reference](APL-Expression-Reference)
