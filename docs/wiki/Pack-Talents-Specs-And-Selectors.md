<!--
Purpose: Talent ranks, spec ids, selectors and the automatic pick.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
-->
This page describes how a class pack declares its **talents** and **specializations** (specs), how Hekili Forever numbers the specs, and how **selectors** pick the active spec and its priority from the player's talents. The Forever client reports one pseudo-spec per class, so the core works out the spec itself, from the talent points and the class pack's declarations.

| Talents, specs and selectors | |
|---|---|
| Talents | `kit:RegisterTalents({ [key] = { tree, spellID, maxRank } })` |
| Specs | The `specs` list of `Hekili:NewClass` |
| Selectors | `kit:RegisterSelector(key, { spec, pack }, condition)` |
| Defined in | `src/Hekili/Engine/Schema/Spec.lua`, `Spec/Kits.lua`, `Selectors.lua`, `Trees.lua` |
| Tests | `tests/Forever/talent_trees_spec.lua`, each class spec |

## Talents

`kit:RegisterTalents(talents)` lists every talent of the class. Each entry is keyed by the talent's name in snake case and holds three numbers:

| Position | Meaning |
|---|---|
| 1 | The talent tree, 1 to 3, in the game's tree order. 0 when unknown; such a talent counts toward no tree. |
| 2 | Rank 1's spell ID |
| 3 | The maximum rank |

From `src/Hekili_Druid/Druid.lua`:

```lua
spec:RegisterTalents({
    improved_wrath = { 1, 16814, 5 },
    moonglow = { 1, 16845, 3 },
    furor = { 2, 17056, 5 },
    thick_hide = { 2, 16929, 3 },
    natures_focus = { 3, 17063, 5 },
    -- ...
})
```

The belief reads the ranks from the game's talent data, and every function reads a talent as `talent.<key>.rank` (0 when not taken) or `talent.<key>.enabled` (rank above 0), in both layers. A priority reads `talent.<key>.enabled` and `talent.<key>.rank` the same way. A selector raises on a key that is not registered, and `tests/Forever/druid_spec.lua` checks that the Druid's files read only registered keys.

Register every talent the class can take, even one no current priority reads, with the values its ranks give. A talent that changes a cost, a cooldown or a duration is modelled in the ability or aura it changes, as a function of `talent.<key>.rank`.

## Spec entries

Each entry of `specs` in `Hekili:NewClass(token, { specs = { ... } })` is one spec of the class. The order of the list is the order of the slots that number the specs.

| Field | Meaning |
|---|---|
| `key` | The spec's key, such as `"feral"`. Used by `RegisterSetting`, selectors, the priority manifest, exports and `/hekili spec`. |
| `name` | The name shown to the player, as `L["Feral"]` |
| `tree` | The talent tree the spec rides, 1 to 3. Two specs may share a tree. |
| `icon` | The spec's icon, a texture file ID |
| `role` | `"attack"`, `"tank"` or `"healer"`. Shown in the options; not simulated. |
| `ranged` | True for a ranged spec. Sets the default **Enemy Range Radius** to 30 yards instead of 10. |
| `nameplateRange` | The spec's own **Enemy Range Radius** default, in yards, when neither 30 nor 10 fits |
| `package` | The spec's default priority, by name, such as `"Feral (wowsims.com)"` |
| `formerPackages` | A set of priority names that count as the default: a profile on one of them counts as being on the default. |
| `movement` | True when the spec's priorities read the Movement toggle, whose options row is then shown |
| `unsupported` | True for a spec with no priorities on Forever: its displays are off and its options page says so |

From `src/Hekili_Druid/Druid.lua`:

```lua
{
    key = "feral",
    name = L["Feral"],
    tree = 2,
    icon = 132115,
    role = "attack",
    package = "Feral (wowsims.com)",
    movement = true,
},
{ key = "restoration", name = L["Restoration"], tree = 3, icon = 136041, role = "healer", unsupported = true },
```

Each spec reads the kit's abilities, auras and talents, and keeps its own settings and options.

## Spec ids

The ids are the addon's own, not the client's. Each class has one id per slot: slot 0 is the kit, and slots 1 and up are the entries of `specs` in order.

```text
id = 100000 + client class ID x 10 + slot
```

For the Druid (client class ID 11), the kit is 100110, Balance 100111, Feral 100112, Guardian 100113 and Restoration 100114. The formula is `ns.TreeSpecID` in `src/Hekili/Engine/Schema/Trees.lua`. Exports do not carry the number: they name a spec by its share key, `"<TOKEN>:<key>"` such as `"DRUID:feral"`, which the importer resolves to the id.

## Selectors

The talent tree with the most points decides which specs are candidates. When two specs ride one tree, or a build needs a different priority, a selector decides. `kit:RegisterSelector(key, target, condition)` takes:

| Parameter | Meaning |
|---|---|
| `key` | The selector's name, shown in the snapshot when it picks |
| `target.spec` | The key of one of the class's specs |
| `target.pack` | A built-in priority of that spec |
| `condition` | `function(tab1, tab2, tab3)`, given the points in each tree, returning true when the selector applies |

The condition runs in its own small environment, not in the simulation: it can read `talent.<key>.rank` for the kit's registered talents, `level`, `max` and `min`. From `src/Hekili_Druid/Druid.lua`:

```lua
spec:RegisterSelector("guardian", { spec = "guardian", pack = "Guardian (wowsims.com)" }, function(tab1, tab2, tab3)
    return tab2 > tab1 and tab2 > tab3 and talent.thick_hide.rank >= 3
end)
```

Feral Combat ahead with all three ranks of Thick Hide picks Guardian and its priority. Anything else on that tree falls to Feral, the tree's first spec.

Selectors are kept in registration order, and the first whose condition holds wins, so register the specific before the general. A selector whose spec is unsupported is skipped. A condition that raises counts as false; the snapshot's `spec:` line shows the count of such errors and the last message.

Selectors run at login, on a talent change and on a spec change, never on each update.

## The automatic pick

At each of those moments the core picks the spec for the tree with the most points, in this order:

1. The spec whose priority the player activated for that tree, with **Priority** on the spec's page, a priority's **Active** toggle, `/hekili priority`, or `/hekili spec`.
2. Otherwise, the first selector that holds.
3. Otherwise, a spec stored for the tree earlier.
4. Otherwise, the tree's first spec in `specs` order.

With no points spent, or a tie between trees, the last spec settled with points holds. On a first login with none seen yet, the first supported spec is used. A respec that moves the dominant tree therefore switches the spec, and two builds of one tree share the choice.

A selector also sets its priority, but only over the spec's default or over a priority an earlier selector set. A priority the player chose, a custom priority, or no priority stays as it is. When no selector holds any more, a priority a selector set goes back to the default. A notice tells the player when a selector switches the priority, or the spec after the first settle.

> [!WARNING]
> **Different from retail Hekili:** Retail Hekili takes the spec from the game. On the Forever client the game reports one spec per class, so Hekili Forever picks the spec and its priority from the talents.

## See also

- [Choosing a priority](Choosing-A-Priority)
- [Specializations reference](Specializations-Reference)
- [Pack class file anatomy](Pack-Class-File-Anatomy)
