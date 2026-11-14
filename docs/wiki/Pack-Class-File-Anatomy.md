<!--
Purpose: A guided tour of one class file in the order it is written.
Type: Explanation
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview).
-->
A class file is the one Lua file of a class pack, `src/Hekili_<Class>/<Class>.lua`, that declares everything the core knows about the class. This page follows the Druid's, `src/Hekili_Druid/Druid.lua`, from top to bottom, in the order its sections are written, and explains what each section is for. The examples are shortened from that file, with comments written for this page. Each call is listed with its parameters on [Pack API reference](Pack-API-Reference).

| Druid class file | |
|---|---|
| File | `src/Hekili_Druid/Druid.lua` |
| Specs | Balance, Feral, Guardian; Restoration registered as unsupported |
| Order | Header and class check, `NewClass`, rank lists and helpers, resources, talents, selectors, gear, auras, cost and GCD modifiers, state expressions and functions, hooks, abilities, settings, packs |
| Tests | `tests/Forever/druid_spec.lua` and the Druid loop and replay specs |

## The header and the class check

The file opens with the facade, the pack's string table and the class check:

```lua
local Facade = Hekili.Client
local C_Spell, UnitClassBase = Facade.C_Spell, Facade.UnitClassBase
local L = Hekili:GetLocale("Hekili_Druid")

if UnitClassBase("player") ~= "DRUID" then
    return
end

local state = Hekili.State
```

Every game read goes through `Hekili.Client` ([Pack belief and simulation](Pack-Belief-And-Simulation#the-facade)). `L["..."]` wraps every text a player sees. `Hekili.State` is the simulated state; the file keeps it to read `state.knownRank` and, in a few model functions, the simulated swing times.

## NewClass and specs

`Hekili:NewClass(token, definition)` creates the class kit and returns it, or nil when the player is another class. Every later call is made on the kit, which the Druid's file names `spec`:

```lua
local spec = Hekili:NewClass("DRUID", {
    specs = {
        {
            key = "balance",
            name = L["Balance"],
            tree = 1,
            icon = 136096,
            role = "attack",
            ranged = true,
            package = "Balance (wowsims.com)",
        },
        {
            key = "feral",
            name = L["Feral"],
            tree = 2,
            icon = 132115,
            role = "attack",
            package = "Feral (wowsims.com)",
            movement = true,
        },
        -- guardian: tree 2, role "tank", package "Guardian (wowsims.com)"
        { key = "restoration", name = L["Restoration"], tree = 3, icon = 136041, role = "healer", unsupported = true },
    },
})
if not spec then
    return
end
```

Each entry of `specs` is one specialization, riding one talent tree. Two specs may share a tree, as Feral and Guardian share Feral Combat; a selector then chooses between them. The fields are in [Pack talents, specs and selectors](Pack-Talents-Specs-And-Selectors#spec-entries).

## Rank lists and helpers

Before the registrations, the file lists each ability's spell IDs in rank order, and the per-rank values the spell data gives:

```lua
local CLAW = { 1082, 3029, 5201, 9849, 9850 }
local BARKSKIN = { 22812 }
local ROOTS_DURATION = { 12, 15, 18, 21, 24, 27 }
```

A few small helpers turn them into fields:

```lua
local rankOf = state.knownRank

local function knows(ids)
    return function()
        return rankOf(ids) > 0
    end
end

local function byRank(values, ids)
    return values[rankOf(ids)] or values[1]
end
```

`state.knownRank(ids)` is the highest rank the spellbook knows, 0 for none; it gives the same answer in the simulation and in the belief. A helper defined at file level keeps the file's environment, so it reads the rank through this local instead of a bare `knownRank` ([Pack belief and simulation](Pack-Belief-And-Simulation#rules-for-both)).

## Resources

`spec:RegisterResource(powerType, regen, model, meta)` declares each resource the class uses, with its regeneration entries and its meta fields. The Druid registers energy, combo points, rage and mana:

```lua
spec:RegisterResource(
    Enum.PowerType.Energy,
    { bear_pause = { aura = "bear_form", mult = 0 } },
    nil,
    { regen = 10, refundOnAvoid = 0.8 }
)
spec:RegisterResource(Enum.PowerType.ComboPoints)
```

Energy regenerates 10 a second, stops in Bear Form, and gives back 80% of an avoided ability's cost when the ability asks for a refund. Rage comes from white swings in Bear Form and from Enrage over time; mana follows the five-second rule. The first resource registered is the class's primary resource. Every field is on [Pack resources and regen](Pack-Resources-And-Regen).

## Talents and selectors

`spec:RegisterTalents` lists every talent of the class as `{ tree, rank 1's spell ID, max rank }`:

```lua
spec:RegisterTalents({
    moonglow = { 1, 16845, 3 },
    furor = { 2, 17056, 5 },
    thick_hide = { 2, 16929, 3 },
    -- ...
})
```

Code reads a talent as `talent.<key>.rank`. The points per tree decide the active spec. A selector refines that choice: the Druid's picks Guardian, with its pack, when Feral Combat leads and Thick Hide is at 3/3.

```lua
spec:RegisterSelector("guardian", { spec = "guardian", pack = "Guardian (wowsims.com)" }, function(tab1, tab2, tab3)
    return tab2 > tab1 and tab2 > tab3 and talent.thick_hide.rank >= 3
end)
```

See [Pack talents, specs and selectors](Pack-Talents-Specs-And-Selectors).

## Gear

`spec:RegisterGear(key, item, ...)` names an item or a set by its item IDs; `spec:RegisterSetBonus(key, spellID)` names a set bonus by its hidden aura. Priorities and pack code read them as `set_bonus.<key>`: a set's count of worn pieces, and 1 or 0 for a bonus such as `set_bonus.haruspex_3pc`.

```lua
spec:RegisterGear("haruspex", 19613, 19838, 19839, 19840, 19955)
spec:RegisterSetBonus("haruspex_3pc", 24479)
```

The Druid keeps the IDs in a `GEAR` table and passes `unpack(GEAR.haruspex)`.

## Auras

`spec:RegisterAuras` declares every buff and debuff the class reads or writes, by key. An aura that an ability, a `now`, a state function, a resource entry or an alias names must be registered; `tests/Forever/druid_spec.lua` checks that.

```lua
spec:RegisterAuras({
    barkskin = {
        id = 22812,
        duration = 15,
        max_stack = 1,
    },
    entangling_roots = {
        id = 339,
        copy = { 1062, 5195, 5196, 9852, 9853 },
        duration = function()
            return ROOTS_DURATION[knownRank(ROOTS)] or 12
        end,
        max_stack = 1,
    },
    form = {
        alias = { "cat_form", "bear_form", "moonkin_form", "travel_form", "aquatic_form" },
        aliasType = "buff",
        aliasMode = "first",
    },
})
```

`copy` lists the other ranks' spell IDs. A `duration` may be a function; both layers evaluate it. An alias answers for a group of auras. Every field is on [Pack auras reference](Pack-Auras-Reference).

## Cost and GCD modifiers

A proc that makes abilities cheaper is a cost modifier, declared once and read by both layers. Clearcasting makes the next covered ability free and is used up by it:

```lua
spec:RegisterCostMod({
    aura = "clearcasting",
    pct = -1,
    charges = 1,
    spells = { 8921, 2912, 5570, --[[ ... rank 1 IDs ]] 99 },
})
```

`spells` lists rank 1's IDs; the other ranks match through each ability's `copy`. `spec:RegisterGcdMod({ aura, pct, spells })` works the same way for an aura that shortens the GCD, such as Nature's Grace. Neither modifier is written into an ability's `spend` or `gcd`, so no ability has to know about the proc.

## State expressions, functions and hooks

These extend the simulation only.

- `spec:RegisterStateExpr(key, fn)` adds a value a priority can read by name. The Druid's `druid_bleed_active` is true while any of its bleeds is on the target.
- `spec:RegisterStateFunction(key, fn)` adds a function handlers can call. The Druid's `swap_form(form)` removes the other forms and applies the resource rules of a shift; every form's `handler` calls it.
- `spec:RegisterHook(name, fn)` runs code at a point of the simulation's cycle. The Druid's `reset_precast` hook marks a queued Maul as a buff at each reset.

```lua
spec:RegisterStateExpr("druid_bleed_active", function()
    return debuff.rake.up or debuff.rip.up or debuff.lacerate.up or debuff.pounce_bleed.up
end)
```

The belief does not run them. A `now` that needs the same steps writes them out with the belief's verbs.

## Abilities

`spec:RegisterAbilities` is most of the file. Each ability declares its identity, cost, timing and usability as fields, and its effect twice: `now` for the belief and `handler` for the simulation.

```lua
spec:RegisterAbilities({
    bash = {
        id = 5211,
        copy = { 6798, 8983 },
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        spend = 10,
        spendType = "rage",

        startsCombat = true,
        refundOnAvoid = true,
        known = knows(BASH),
        form = "bear_form",

        now = function()
            applyDebuff("target", "bash", (BASH_STUN[knownRank(BASH)] or 2) + 0.5 * talent.brutal_impact.rank)
        end,

        handler = function()
            applyDebuff("target", "bash")
        end,
    },
})
```

Here the `now` computes the stun's duration from the known rank and the Brutal Impact talent, while the `handler` lets the aura's own `duration` function do the same. Why each ability has two effect functions is explained on [Pack belief and simulation](Pack-Belief-And-Simulation); every field is on [Pack abilities reference](Pack-Abilities-Reference).

## Settings and packs

`spec:RegisterSetting(key, default, option, ...)` adds a class setting, shown on the spec's options page and read by priorities as `settings.<key>`. The spec keys after `option` limit it to those specs:

```lua
local behind = {
    type = "toggle",
    name = L["Always Behind"],
    desc = L["Hekili assumes you are always behind the target. ..."],
    width = "full",
}
spec:RegisterSetting("behind", false, behind, "feral", "balance")
```

See [Pack settings](Pack-Settings).

The file ends with the default priorities. `make packs` writes each `spec:RegisterPack(name, version, string)` block from `APLs/packs.lua` and `APLs/<Pack>.simc`; the blocks are never edited by hand. `spec:RetirePacks` names built-in priorities the class no longer ships, so that a profile that chose one falls back to the spec's default.

```lua
spec:RegisterPack(
    "Feral (wowsims.com)",
    20261113000,
    [[Hekili:...]]
)

spec:RetirePacks({ "Feral", "Guardian", "Balance" })
```

## See also

- [Pack API reference](Pack-API-Reference)
- [Pack tutorial: add an ability](Pack-Tutorial-Add-An-Ability)
- [Pack adding a spec or class](Pack-Adding-A-Spec-Or-Class)
