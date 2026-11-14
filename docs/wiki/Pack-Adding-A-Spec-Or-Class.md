<!--
Purpose: The checklist for a new spec or class.
Type: How-to
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview).
-->
**Adding a spec or class** to Hekili Forever means adding a class pack, or a spec inside one, together with its generated priority, its tests and its gates. This page gives the steps as two checklists: one for a new spec in an existing class, and one for a new class, which includes the first.

The core is a generic engine. It names no class, spell, aura or talent, and a new class needs no change to it: everything about the class lives in its own addon and reaches the engine through the registration API. [Pack overview](Pack-Overview) describes the class addons, and [Pack class file anatomy](Pack-Class-File-Anatomy) the class file.

## Before you start

- Every default priority is generated from wowsims.com: a spec's priority is wowsims/forever's own rotation, translated by a recipe ([Pack wowsims recipes](Pack-wowsims-Recipes)). There are no hand-built priorities. A spec with no wowsims rotation is registered as unsupported and has no priority.
- Exporting a new spec needs a wowsims/forever checkout at the pinned commit and its command-line simulator, described in [Pack wowsims recipes](Pack-wowsims-Recipes#exporting).
- A new priority must pass the gates described in [Pack testing and gates](Pack-Testing-And-Gates), and its first measurement sets its floors.

## Adding a spec to an existing class

In these steps `<class>_<spec>` is the recipe name (`warrior_arms`), `<Pack>` the priority name (`Arms (wowsims.com)`), `<key>` the spec key (`arms`) and `<Class>` the addon's class (`Warrior`).

1. **Add the spec entry.** In the class file, add the spec to the `specs` list of `Hekili:NewClass` ([The spec entry](#the-spec-entry) below). A spec that shares its talent tree with another needs a selector that picks it from the talents ([Pack talents, specs and selectors](Pack-Talents-Specs-And-Selectors)).
2. **Write the recipe.** Create `tools/wowsims/specs/<class>_<spec>.lua`, with a header comment naming the wowsims files and lines its values come from.
3. **Export.** Run `make wowsims-export SPEC=<class>_<spec>`. Check the first lines of `tests/Forever/wowsims/<class>_<spec>.log`: the header names the pin, the spec and the build's talents, and a three-minute fight has many `Casting` lines. An error from the simulator means a recipe value is wrong.
4. **Translate.** Run `make wowsims-packs` and read the `# Omitted:` lines of `src/Hekili_<Class>/APLs/<Pack>.simc`. For each spell, aura or item ID listed there, add a `map` entry if the class has it under another ID, add the ability to the class file if wowsims casts it and the class lacks it, or leave it omitted (another race's racial, a consumable). Repeat until only true gaps remain. Then the leveling check prints nothing:

   ```sh
   .lua/bin/lua tools/check_pack_levels.lua "src/Hekili_<Class>/APLs/<Pack>.simc"
   ```

5. **Register the priority.** In `src/Hekili_<Class>/APLs/packs.lua`, add `<Pack>` to `packs` and map it to `<key>` in `specs`. Set the spec entry's `package` to `<Pack>`. For each `# Setting` line in the priority's header, register the setting on the spec, as in `src/Hekili_Warrior/Warrior.lua`:

   ```lua
   spec:RegisterSetting("wowsims_stance_dance", false, {
       type = "toggle",
       name = L["Stance Dance (wowsims.com)"],
       desc = L["The wowsims.com priority's Stance Dance ON/OFF switch (its default in wowsims's own APL)."],
       width = "full",
   }, "arms") -- the spec key it belongs to
   ```

   Then run `make packs`, which writes the priority's block into the class file.
6. **Close kit gaps.** For each ability wowsims casts that the class file lacks or models differently (cast time, cooldown, a talent's effect, a proc window), fix the class file, with a test in `tests/Forever/<class>_spec.lua`.
7. **Extend the class test world.** Add the priority's content to `tests/Forever/helpers/<class>_world.lua`: the build's talents, and a press for every ability the priority recommends.
8. **Add the replay and leveling gates.** In `tests/Forever/wowsims_<class>_spec.lua`, add the priority's replay gate and its leveling gate at three levels. Run the replay first with a floor of 0, work through the top disagreements reported on its line (a kit gap, a missing `map` entry, a limit of the replay, or a difference in wowsims itself), and record each in the recipe's header. Then set the floor to the measured value.
9. **Add the loop gate.** Create `tests/Forever/loop_<class>_<spec>_spec.lua` for the priority's 20-fight gate, tagged with the class's gate tag, and set its flicker limits in `tests/Forever/helpers/pack_gate.lua`.
10. **Record the focus tiers** of the priority's lines in `tests/Forever/focus_roles_spec.lua`.
11. **Run the checks.** Run `make check`, then `make gate`. Commit the recipe, the checked-in request and log, the generated files and the tests together.

## Adding a class

A new class follows these steps, then the spec checklist above for each of its specs. Copy the shape of an existing class at each step; the Druid's files are cited here.

1. **Create the addon folder.** Its name is `src/Hekili_<Class>/`. The core finds the class pack by name: `"Hekili_"` followed by the class token with only its first letter in capitals, so the token `DRUID` loads `Hekili_Druid`.
2. **Write the TOC.** Create `src/Hekili_<Class>/Hekili_<Class>.toc` by copying an existing class's. From `src/Hekili_Druid/Hekili_Druid.toc`, shortened, with the content API number replaced by a placeholder:

   ```text
   ## Interface: 16001
   ## Version: @project-version@
   ## Title: Hekili Forever - Druid
   ## Dependencies: Hekili, Hekili_Shared
   ## Group: Hekili
   ## LoadOnDemand: 1
   ## X-Hekili-ContentAPI: <the core's CONTENT_API>

   Locales\enUS.lua
   Locales\zhCN.lua

   Druid.lua
   ```

   The class pack is load-on-demand: the core loads `Hekili_Shared`, then the player's class pack, at login. `## X-Hekili-ContentAPI` must equal `CONTENT_API` in `src/Hekili/Engine/Content.lua`; on a mismatch the core shows a notice and does not load the class pack. The core raises that number only when the content surface (the registration API, the client facade or the names a class pack's code can read) changes. `tests/Forever/content_spec.lua` checks that every content TOC agrees with the core, and `tests/Forever/publication_spec.lua` checks the title, author, credit, website, icon and version fields shared by every TOC.
3. **Write the class file.** The file `src/Hekili_<Class>/<Class>.lua` returns at once for any other class, then calls `Hekili:NewClass(token, def)`, which returns the class kit, and registers everything on that kit: talents, resources, auras, abilities, settings and priorities ([Pack class file anatomy](Pack-Class-File-Anatomy)). `NewClass` returns nil when the token is not the player's class.
4. **Add the string table.** The class file reads its text through `local L = Hekili:GetLocale("Hekili_<Class>")`. Run `python3 tools/locales.py` to write `Locales/enUS.lua` and the language files; it finds a new addon by itself. The TOC lists the `Locales` files before the class file.
5. **Add the priority manifest.** `src/Hekili_<Class>/APLs/packs.lua` holds the class token, the priorities in block order, and each priority's spec key. The `APLs/` folder is development-only: no TOC lists it, and the packager leaves it out. From `src/Hekili_Druid/APLs/packs.lua`, shortened:

   ```lua
   return {
       class = "DRUID",
       packs = { "Feral (wowsims.com)", "Balance (wowsims.com)", "Guardian (wowsims.com)" },
       specs = {
           ["Feral (wowsims.com)"] = "feral",
           ["Balance (wowsims.com)"] = "balance",
           ["Guardian (wowsims.com)"] = "guardian",
       },
   }
   ```

6. **Add the class to the lists.** These files name every class addon:
   - `tests/helpers/addons.lua`, `M.CONTENT`: the addon list every headless loader, spec and tool reads, in load order;
   - `.pkgmeta`: a `move-folders` line, and an `ignore` line for its `APLs` folder;
   - `tools/check_package.sh`: both addon loops;
   - `.luacheckrc`: the class file's entry with the globals its environment provides;
   - `tests/Forever/publication_spec.lua`: its TOC list and its `.pkgmeta` list;
   - the `Makefile`: the new gate tag in `.PHONY`, `TEST_EXCLUDE`, the `test-fast` exclusions and `GATE_TAGS`;
   - `tests/boundary_lib.lua`: the class file's loader;
   - `tests/Forever/cdm_map_spec.lua`: the class's entry in `CLASSES`, with a Cooldown Manager export from the game client under `tests/Forever/fixtures/cdm/`;
   - the class lists in `tests/Forever/packs_spec.lua` and `tests/Forever/make_pack_spec.lua`.
   - the repository `README.md`: the folder list and the folder count ("eleven") in its install section;
   - the wiki's [Installing](Installing) page: the folder list under "Before you start" and each folder count.
7. **Write the learn table.** Run `make wowsims-learn CLASS=<TOKEN>`. It writes `tests/Forever/wowsims/learn_<class>.lua`, the level at which each rank of each ability is learned, which the leveling gates read.
8. **Add the class tests.** Create `tests/Forever/<class>_spec.lua` for the class file's registrations (loading the class file through `tests/Forever/helpers/load_druid.lua`, with the class's file and token), the class test world `tests/Forever/helpers/<class>_world.lua`, `tests/Forever/loop_<class>_spec.lua` for the world's boot checks and short gates, and `tests/Forever/wowsims_<class>_spec.lua` for the replay gates.
9. **Add each spec** with the checklist above.
10. **Update the developer documentation.** Add the class to the floor table and the addon lists in `docs/dev/layout.md` and `DEVELOPMENT.md`.

<!-- UNVERIFIED: no single document lists every place a new class must be added; step 6 comes from a search of the repository for an existing class's addon name and token, and may be incomplete. -->

## The spec entry

Each entry of `def.specs` in `Hekili:NewClass` describes one spec. The fields, from `src/Hekili/Engine/Schema/Spec/Kits.lua`:

| Field | Meaning |
|---|---|
| `key` | The spec key, such as `feral`. Priorities and settings name the spec by it. |
| `name` | The spec's display name, from the class's string table. |
| `tree` | The talent tree (1 to 3) the spec rides. Two specs may share a tree. |
| `icon` | The spec's icon (a file ID). |
| `role` | `"attack"`, `"tank"` or `"healer"`. Shown, not simulated. |
| `ranged` | `true` for a ranged spec. |
| `nameplateRange` | The spec's default enemy range radius in yards, which target counting falls back to. 30 for a ranged spec and 10 for a melee spec unless set. |
| `package` | The spec's default priority, such as `"Feral (wowsims.com)"`. |
| `movement` | `true` when the spec's priority reads `toggle.movement`; the options then show the Movement toggle for it. `tests/Forever/packs_spec.lua` checks that the two agree. |
| `unsupported` | `true` for a spec with no priority on Forever. Its displays are off, the engine idles and the options page says so. |
| `formerPackages` | Priority names that count as the spec's default: a player on one of them counts as on the default when the spec picks its priority. |

From `src/Hekili_Druid/Druid.lua`:

```lua
local spec = Hekili:NewClass("DRUID", {
    specs = {
        {
            key = "feral",
            name = L["Feral"],
            tree = 2,
            icon = 132115,
            role = "attack",
            package = "Feral (wowsims.com)",
            movement = true, -- the pack reads toggle.movement
        },
        -- balance, guardian, restoration ...
    },
})
```

## See also

- [Pack overview](Pack-Overview)
- [Pack class file anatomy](Pack-Class-File-Anatomy)
- [Pack testing and gates](Pack-Testing-And-Gates)
- [Pack wowsims recipes](Pack-wowsims-Recipes)
- [Pack translator rules](Pack-Translator-Rules)
