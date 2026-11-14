<!--
Purpose: Add an ability and its aura end to end, with a test.
Type: Tutorial
Audience: Lua developers
Prerequisites: [Pack overview](Pack-Overview), a bootstrapped checkout ([Contributing](Contributing)).
-->
This tutorial adds one ability and the aura it applies to a class pack, writes the ability's effect for both the belief and the simulation, tests it headless, and runs the checks. The example is the Druid's Barkskin, a defensive cooldown that puts a 15-second buff on the player. Barkskin already exists in `src/Hekili_Druid/Druid.lua`, so the end state can be compared line by line with the shipped file.

| Tutorial | |
|---|---|
| Builds | The `barkskin` aura and ability, and two tests |
| Files | `src/Hekili_Druid/Druid.lua`, `tests/Forever/druid_spec.lua` |
| Needs | A checkout with `make bootstrap` done ([Contributing](Contributing)) |
| Ends with | A green `make check` |

## What you will have at the end

- The `barkskin` aura, registered with its spell ID, duration and stacks.
- The `barkskin` ability, with its cooldown, GCD and toggle, and its effect written twice: `now` for the belief and `handler` for the simulation.
- Two tests in `tests/Forever/druid_spec.lua` that load the class file headless and check both.
- A green `make check`.

To follow along on a branch, first delete the three Barkskin entries from `src/Hekili_Druid/Druid.lua`: the `BARKSKIN` rank list near the top, the `barkskin` entry in `spec:RegisterAuras`, and the `barkskin` entry in `spec:RegisterAbilities`. Then add them back as the steps below describe.

## Gather the spell data

Look up the facts the class pack needs before writing any code. For Barkskin they are:

| Fact | Value |
|---|---|
| Spell ID (rank 1, the only rank) | 22812 |
| Cost | None |
| Cooldown | 60 seconds |
| GCD | Triggers the spell GCD |
| Buff | 22812, 15 seconds, 1 stack |
| Effect of the cast | Applies the buff to the player |

On conflicting values the wowsims data wins over the game's spell tables, and a measurement in game wins over both. Never guess a cooldown or a duration: a wrong number makes the belief and the simulation agree with each other and disagree with the game.

## Add the rank list

Near the top of the class file, with the other rank lists, add the ability's spell IDs in rank order:

```lua
local BARKSKIN = { 22812 }
```

The file's `knows(ids)` helper turns this list into a `known` function, true when the spellbook knows any rank.

## Register the aura

In `spec:RegisterAuras`, add the buff the ability applies:

```lua
barkskin = {
    id = 22812,
    duration = 15,
    max_stack = 1,
},
```

The key, `barkskin`, is the name every priority and every function uses: `buff.barkskin.up`, `applyBuff("barkskin")`. The belief tracks the aura by its `id`. An aura with more ranks lists their IDs in `copy`; a duration that depends on a rank or a talent can be a function ([Pack auras reference](Pack-Auras-Reference)).

## Register the ability

In `spec:RegisterAbilities`, add the ability:

```lua
barkskin = {
    id = 22812,
    cast = 0,
    cooldown = 60,
    gcd = "spell",

    startsCombat = false,
    known = knows(BARKSKIN),
    toggle = "defensives",

    now = function()
        applyBuff("barkskin")
    end,

    handler = function()
        applyBuff("barkskin")
    end,
},
```

The fields, in order:

- `id` is rank 1's spell ID. An ability with more ranks lists the others in `copy`.
- `cast = 0` makes it instant, `cooldown = 60` gives its cooldown in seconds, and `gcd = "spell"` makes it trigger the spell GCD.
- Barkskin costs nothing, so it has no `spend` or `spendType`.
- `startsCombat = false`: casting it does not pull the target.
- `known` decides whether the player has the ability. It must depend only on the spellbook, talents and gear, because the engine caches it for a whole prediction.
- `toggle = "defensives"` puts it under the Defensives toggle, so a player who turns defensives off never sees it.

The cast changes more than its cooldown and GCD: it puts a buff up. So the effect is written twice.

- `now` runs in the belief when the client reports the player's successful cast. It tells the belief that the buff is up, so the belief does not have to wait for the game to show it.
- `handler` runs in the simulation each time the forecast casts Barkskin, so the abilities forecast after it see the buff.

Here both functions are one line, and `applyBuff` with no duration uses the aura's 15 seconds in either layer. They must still be two separate functions: the belief refuses a `now` that is the same function as the `handler`. [Pack belief and simulation](Pack-Belief-And-Simulation) explains why, and shows an ability whose two functions differ.

## Write a test

The class specs in `tests/Forever/` load the class file headless, against a recording stand-in for the core (`tests/Forever/helpers/load_druid.lua`), and run its functions in a stand-in state that records every verb. Inside `describe("Forever Druid", ...)` in `tests/Forever/druid_spec.lua`, whose `before_each` already loads the file into `w`, add:

```lua
it("registers Barkskin: no cost, a 60 s cooldown, the defensives toggle, a 15 s buff", function()
    local a = w.abilities.barkskin
    assert.are.same({ 22812, 60, "spell", "defensives" }, { a.id, a.cooldown, a.gcd, a.toggle })
    assert.is_nil(a.spend)
    assert.are.equal(15, w.auras.barkskin.duration)
end)

it("applies Barkskin's buff in both layers", function()
    local e = ld.env(w)
    ld.run(w.abilities.barkskin.now, e)
    ld.run(w.abilities.barkskin.handler, e)
    assert.are.same({ "barkskin", "barkskin" }, e.applied)
end)
```

`ld.env(w)` makes the stand-in state; `ld.run` runs a pack function in it; `e.applied` lists the auras the functions applied.

The Druid spec also checks every ability against two tables at its top, and both already hold Barkskin:

- `KIT` lists each ability's spell IDs, cost, cost type, cooldown and GCD, checked against the game's spell data: `barkskin = { { 22812 }, 0, nil, 60, "spell" }`.
- `NOW` lists the abilities that must have a `now`, and the test fails for an ability that has one and is not listed, or is listed and has none.

For a new ability, add a row to `KIT`, add its key to `NOW` if it has a `now`, and raise the ability count that the first test asserts (`assert.are.equal(45, n)` today).

Run the class spec:

```sh
.lua/bin/busted tests/Forever/druid_spec.lua
```

## Run the checks

Run the full check before committing:

```sh
make check
```

It runs lint, formatting, the type check, every headless spec (including the short replay and loop gates), the API and boundary checks and the packs check. A class pack change that can move recommendations is also measured by the class's 20-fight loops, which `make gate` runs for every class before a merge. To run only the Druid's:

```sh
make test-druid
```

When the ability is new to the class's priorities, its priority lines come from the wowsims recipe, not from a hand edit of the generated priority ([Pack wowsims recipes](Pack-wowsims-Recipes)).

## Next steps

- [Pack testing and gates](Pack-Testing-And-Gates): what each check and gate measures.
- [Pack abilities reference](Pack-Abilities-Reference): every field, including costs, charges, forms and the belief-only fields.
- [Pack expects and outcomes](Pack-Expects-And-Outcomes): declaring what a damaging ability's hit looks like.

## See also

- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack auras reference](Pack-Auras-Reference)
- [Pack class file anatomy](Pack-Class-File-Anatomy)
