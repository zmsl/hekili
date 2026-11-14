<!--
Purpose: The recipe file and the export, translate and pack pipeline.
Type: How-to
Audience: Lua developers
Prerequisites: [Contributing](Contributing).
-->
A **wowsims recipe** is the Lua file from which one "(wowsims.com)" priority pack is generated. It names the wowsims.com build to export (race, gear, talents, options) and holds the translation data, mostly a map from wowsims's spell IDs to the addon's keys. This page describes the recipe and the three steps that turn it into the priorities the class addons ship: export, translate and pack.

Every default priority in Hekili Forever comes from a recipe. There are no hand-built priorities. A pack follows wowsims as closely as the Forever client allows: a difference the client forces is recorded with its reason, and any other difference is a gap to fix in the layer that is wrong (the class kit, the translator, the test harness or the core). [APL wowsims packs explained](APL-wowsims-Packs-Explained) gives the background for players.

## The recipe

Each recipe is `tools/wowsims/specs/<class>_<spec>.lua`. The file name is the spec name the tools take, such as `warrior_arms` or `druid_feral`, so listing that folder lists every spec. The file returns one table. Its header comment names the wowsims files and lines its values come from. `tools/wowsims/export.lua` reads the request fields; `tools/wowsims/apl.lua` reads the translation fields.

### Request fields

| Field | Meaning |
|---|---|
| `class` | The class token, such as `"WARRIOR"`. |
| `pack` | The pack name, such as `"Arms (wowsims.com)"`. |
| `spec` | The spec key, such as `"arms"`. |
| `name` | The wowsims spec name written in the log header. |
| `talentTree` | The wowsims talent tree file. |
| `apl` | The APL file in the wowsims checkout. Optional when the build carries its own rotation. |
| `player` | The character: `race`, `class`, `gear` (a gear-set file), `talentsString`, `specKey`, `options` (wowsims's default options for the spec), `profession1`, `profession2`, `reactionTimeMs`, `distanceFromTarget`, `inFrontOfTarget`. |
| `build` | Instead of `player`: a preset build file taken whole, with `gear` replacing its equipment. |
| `siml` | Instead of `player`, `build` and `apl`: a `.siml` build in the checkout, converted to the checked-in `tests/Forever/wowsims/<spec>.build.json`. |
| `tank`, `healingModel` | For a tank spec: the player becomes the raid's tank and receives the preset's incoming healing, as wowsims's own interface does. |
| `vars` | APL variables that a build's simple rotation overrides. The request carries them, so the pack follows. |

### Translation fields

| Field | Meaning |
|---|---|
| `map` | `{ [spell ID or "item:<id>"] = key }`: a wowsims ID the class kit holds under another ID. It maps casts and aura reads alike. |
| `auras` | `{ [aura ID] = key }`: an aura wowsims keys by an ability's own spell ID, where `map` would also change that ability's casts. |
| `focus` | `{ [action] = tier }`: the display's focus tier by the line's role. Tier 1 is a reactive or windowed line the player must catch; tier 2 is upkeep (DoTs, debuffs, buffs kept up). Rotational strikes, cooldowns and pre-pull lines carry none. |
| `requires` | `{ [action or group] = talent key }`: entries written for a talent build run only once the talent is taken. |
| `guard` | `{ [action or group] = expression }`: one `&(<expression>)` term appended to each such entry's condition. |
| `condition` | `{ [action] = expression }`: replaces the APL's condition of each cast line of that action. |
| `prepullSkip` | `{ action, ... }`: leaves out that action's pre-pull lines. |
| `leveling` | Lines appended to `actions` for lower levels. |
| `levelingFirst` | Lines put first in `actions`: a form the simulation starts in and the APL never casts. |
| `extra` | `{ { before = action, line = text } }`: a line put immediately before the first line of `before` (its last, with `last = true`). |
| `settings` | `{ [key] = { default = bool, desc = text } }`: a pack setting a recipe line reads as `settings.<key>`. |
| `maintenance` | `{ [action] = setting key }`: a raid debuff kept up; off in game, on in the test harness ([Pack translator rules](Pack-Translator-Rules), rule 15). |
| `select` | A cast whose spell a class option picks (rule 16). |
| `exclusive` | `{ [spell ID] = true }`: auras wowsims gives an exclusive effect (rule 10). |
| `windowVars` | `{ [variable] = window }`: an APL variable read from a window the class kit registers (rule 10). |
| `knownAs` | `{ [aura ID] = talent key }`: that aura's "is known" test reads the talent (rule 4). |
| `executePhase` | The key the kit's execute-phase read answers. |
| `notes` | Sentences added to the pack's in-game description, such as what a toggle hides. |

A key that names no APL entry, a `maintenance` key no line casts, an `extra` with no line to go before, and a `condition` or `prepullSkip` with no line to act on are errors: the build stops rather than dropping the entry silently.

### An example

From `tools/wowsims/specs/warrior_arms.lua`, shortened, with comments rewritten:

```lua
return {
    class = "WARRIOR",
    pack = "Arms (wowsims.com)",
    spec = "arms",
    name = "Arms",
    talentTree = "warrior",
    apl = "ui/specs/warrior/dps/apls/arms.apl.json",
    player = {
        race = "RaceOrc",
        class = "ClassWarrior",
        gear = "ui/specs/warrior/dps/gear_sets/p1_arms.gear.json",
        -- talentsString, specKey, options, professions ...
        distanceFromTarget = 25,
    },
    -- Berserker Rage only with the talent that makes it gain rage
    requires = { berserker_rage = "improved_berserker_rage" },
    -- wowsims casts Sweeping Strikes by its effect ID
    map = { [12723] = "sweeping_strikes" },
    focus = { overpower = 1, heroic_strike = 2, cleave = 2, rend = 2 },
    maintenance = { thunder_clap = "maintain_thunder_clap" },
    -- before Mortal Strike is learned
    leveling = {
        "heroic_strike,use_off_gcd=1,focus=2,if=!action.mortal_strike.known&rage.lo>=30",
        "thunder_clap,if=!action.mortal_strike.known&!debuff.thunder_clap.up",
        "sunder_armor,if=!action.mortal_strike.known&debuff.sunder_armor.stack<5",
    },
    -- Victory Rush: wowsims never moves from mob to mob, so its window never opens there
    extra = { { before = "mortal_strike", line = "victory_rush,focus=1" } },
}
```

The generated `src/Hekili_Warrior/APLs/Arms (wowsims.com).simc` then holds the `extra` line just above Mortal Strike, and the Thunder Clap leveling line behind its maintenance setting:

```text
actions+=/victory_rush,focus=1
actions+=/mortal_strike,if=settings.wowsims_stance_dance
...
actions+=/thunder_clap,if=settings.maintain_thunder_clap&!action.mortal_strike.known&!debuff.thunder_clap.up
```

### Adding what wowsims does not carry

Only six recipe keys may add something wowsims does not carry: `leveling`, `levelingFirst`, `extra`, `requires`, `settings` and `focus`. Each use names its reason in the recipe's comment.

- A `leveling` line is a real rotation ability that a lower level casts for a genuine need: its buff about to expire, a debuff missing, a stack low, a resource to spend. It must be silent at level 60, which the line does by testing an ability the level-60 build has, as in `!action.mortal_strike.known&...` above. A leveling line is never a filler that recasts an active buff to fill an idle global cooldown.
- An `extra` line is only for content wowsims cannot model, never to tune a wowsims line.

`guard`, `condition` and `prepullSkip` change what a wowsims line does. They are deviations from wowsims: use one only when the deviation has been agreed, and state its reason in the recipe's header comment.

## The pipeline

The pipeline runs from the recipe to the class files that ship. Run each step from the repository root.

```sh
make wowsims-export SPEC=warrior_arms   # 1. export one spec's request and fight log
make wowsims-packs                      # 2. translate every recipe into its .simc
make packs                              # 3. write the priorities into the class files
```

| Target | What it does | Needs |
|---|---|---|
| `make wowsims-export SPEC=<spec>` | Writes the request `tests/Forever/wowsims/<spec>.json` from the recipe and the checkout's preset files, runs wowsims's command-line simulator on it and writes the fight log `tests/Forever/wowsims/<spec>.log`. A recipe with `siml` converts its build first. | A wowsims/forever checkout at the spec's pinned commit and its simulator. |
| `make wowsims-siml SPEC=<spec>` | Converts a recipe's `siml` build to `tests/Forever/wowsims/<spec>.build.json`. The export runs it too. | The same checkout. |
| `make wowsims-learn CLASS=<TOKEN>` | Writes the class's learn levels, `tests/Forever/wowsims/learn_<class>.lua`, from the game's spell data. | A DB2 reader. |
| `make wowsims-packs` | Translates every recipe into `src/Hekili_<Class>/APLs/<Pack>.simc` from its checked-in request and log. | Nothing outside the repository. |
| `make packs` | Rewrites each class file's generated priority blocks from its `APLs/` folder. | Nothing outside the repository. |

### Exporting

Most changes skip the export and use the checked-in request and log. Exporting is needed for a new spec, or when the recipe's build changes (race, gear, talents, options, the APL file).

Each spec is pinned to one wowsims/forever commit: `M.SPEC_PIN` in `tools/wowsims/export.lua`. The export refuses a checkout at another commit. Build the checkout's simulator once with `make wowsims-sim-cli WOWSIMS=<checkout>` (Go, `protoc` and `protoc-gen-go` on the path), then pass the same `WOWSIMS=<checkout>` to `make wowsims-export`. The log starts with a header naming the pin, the spec, the seed, the duration, the target level and the build's talents. `tests/Forever/wowsims_pin_spec.lua` checks every log's header against its spec's pin.

An error from wowsims's simulator means a recipe value is wrong: fix the recipe, not the tool.

### Translating

`make wowsims-packs` needs no wowsims checkout, so it runs in continuous integration. It reads the checked-in log as well as the request: the automatic cooldown lines (rule 13) and the mana-share terms (rule 22) come from the log, so a re-export can change them.

Never edit a generated `.simc` file by hand. Its header names the recipe to edit instead:

```text
# Generated by `make wowsims-packs` (tools/wowsims/apl.lua) from tools/wowsims/specs/warrior_arms.lua: edit that recipe, not this file.
```

Read its `# Omitted:` lines after each translation. A `spell N`, `aura N` or `item N` there is either an ID the class kit holds under another ID (add it to `map`), an ability the kit lacks (a kit gap: add it to the class file), or something left out on purpose, such as another race's racial or a consumable. The other header lines are listed in [Pack translator rules](Pack-Translator-Rules#header-lines).

### Packing

`make packs` runs `tools/make_pack.lua` for every class. It reads the class's manifest, `src/Hekili_<Class>/APLs/packs.lua`, and each `.simc` beside it, and rewrites the class file's generated priority blocks. A class's pack date changes only when one of its blocks changed, so running it on a clean tree changes nothing.

### The packs check

`make check` runs the packs check: `make wowsims-packs`, then `make packs`, then a `git diff` of `src/`. Any difference fails it. Commit the regenerated `.simc` files and class files in the same commit as the recipe, translator or kit change that caused them.

## See also

- [Pack translator rules](Pack-Translator-Rules)
- [APL wowsims packs explained](APL-wowsims-Packs-Explained)
- [Pack testing and gates](Pack-Testing-And-Gates): the replay that measures a pack against wowsims's fight
- [Pack adding a spec or class](Pack-Adding-A-Spec-Or-Class)
