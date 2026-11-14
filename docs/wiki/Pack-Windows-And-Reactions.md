<!--
Purpose: RegisterWindow and RegisterReaction.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
-->
A **rotation window** is a named span of time that a class pack registers when the game shows no aura for it, such as the five seconds after a parry in which Riposte can be used. A reaction is a `now` function that the belief runs at an observed outcome, such as a landed white swing, instead of at a cast. Both exist for spans and effects that only an event reveals. This page describes `RegisterWindow` and `RegisterReaction`. How a priority opens and reads a window is on [APL windows](APL-Windows).

| Windows and reactions | |
|---|---|
| Calls | `spec:RegisterWindow(name, data)`, `spec:RegisterReaction(name, data)` |
| Defined in | `src/Hekili/Engine/Schema/Spec.lua` |
| Belief side | `src/Hekili/Game/State/Families/Windows.lua`, `Now.lua` |
| Read in a priority as | `window.<name>.up`, `.remains`, `.elapsed`, `.step`, `.next.<ability>` |
| Shipped examples | Windows in the Rogue, Hunter and Paladin packs; reactions in the Warrior and Paladin packs |

Use the first that fits: an aura when the game shows one; a usability flip when the game's answer for an ability changes at the span's edges; a reaction only where only an outcome reveals the span.

## RegisterWindow

```lua
spec:RegisterWindow(name, data)
```

The name must be unique across the class's specs. The belief owns the real windows: their state is part of the belief, so a window survives a rebuild of the simulation. Every simulation reset copies the windows from the belief, and within one forecast an `open_window` or `close_window` line, a `handler`'s `openWindow` or `closeWindow`, and a simulated cast of a window's step change only that forecast's copy.

| Field | Type | Meaning |
|---|---|---|
| `evaluator` | function | Optional. Run in the belief's `now` context once per update. Its change from false to true opens the window. It may only read. |
| `duration` | number, `"combat"` or function | How long an opening lasts. A number is seconds. `"combat"` has no timer: only combat ending, a close, `close_on_false` or the last step ends it. A function is the forecast's, run under `state` at each forecast opening and counted refresh. |
| `now_duration` | function | The belief's own duration function, run in the `now` context. Required with a function `duration`, and only then. |
| `refresh` | boolean | A new opening restarts an open window |
| `max_duration` | number | Caps a refreshed window's total length, in seconds from its first opening |
| `max_refresh` | number | Caps the number of refreshes |
| `close_on_false` | boolean | The evaluator's change from true to false closes the window |
| `steps` | list | Ability keys, registered before the window, that make it a stepped window: it advances on the player's observed cast of the step that is due |
| `loop` | boolean | A stepped window starts its steps again after the last |
| `on_deviation` | string | What a cast other than the due step does: `"stay"` (the default), `"skip"` or `"end"` |
| `strict` | boolean | Any other cast on the GCD ends the window |

A function `duration` and its `now_duration` are two functions for the same reason an ability has a `handler` and a `now`: one function cannot run in both layers ([Pack belief and simulation](Pack-Belief-And-Simulation)). A duration function that raises, returns a hidden value, or returns a value of 0 or less opens nothing. Combat ending closes every window.

A `now` function can open and close windows with the verbs `openWindow(name)` and `closeWindow(name)`; the simulation has verbs of the same names for handlers.

### Examples

Riposte's window, from `src/Hekili_Rogue/Rogue.lua`. The evaluator reads the client's usability answer for Riposte; the window opens when the answer turns true, lasts at most 5 seconds and closes when the answer turns false again:

```lua
local function riposteUsable()
    local r = knownRank(RIPOSTE)
    if r == 0 then
        return false
    end
    local usable, noMana = IsSpellUsable(RIPOSTE[r])
    return usable == true or noMana == true
end
spec:RegisterWindow("riposte", {
    evaluator = riposteUsable,
    duration = 5,
    close_on_false = true,
})
```

A stepped window, from `src/Hekili_Paladin/Paladin.lua`: an opening sequence of two casts, run once a fight, before the first main-hand swing.

```lua
spec:RegisterWindow("move1", {
    evaluator = function()
        return talent.seal_of_command.enabled and combat > 0 and lastSwing(1) < combat
    end,
    duration = "combat",
    close_on_false = true,
    steps = { "judgement", "seal_of_command" },
})
```

## RegisterReaction

```lua
spec:RegisterReaction(name, data)
```

| Field | Type | Meaning |
|---|---|---|
| `who` | string | `"player"`: an outcome of a hit on the player. `"target"`: an outcome of the player's own cast or white swing. |
| `outcome` | string | `"dodge"`, `"parry"`, `"block"`, `"miss"`, `"deflect"`, `"evade"` or `"crit"`; and, with `who = "target"` only, `"swing"` or `"land"` |
| `hand` | string | With `"swing"` or `"land"` only: `"main"` or `"off"`, the hand the belief paired the swing to |
| `now` | function | What the outcome does, written with the belief's verbs |

`"block"` covers both a full and a partial block. `"swing"` runs once per white swing of the player, whatever its outcome; `"land"` runs once per white swing that landed. A spell of the player's that the target blocks fires nothing.

The belief runs the `now` in its `now` context at the outcome's time, after the outcome is settled, so an aura read inside it answers as of that time. A reaction is not an ability: it has no cast history, no GCD, no ticket and no options row, and the simulation never sees it. A window it opens reaches the simulation at the next reset.

From `src/Hekili_Warrior/Warrior.lua`: each landed white swing spends a charge of Reckless Swings and gains 5 rage.

```lua
spec:RegisterReaction("reckless_swings", {
    who = "target",
    outcome = "land",
    now = function()
        if buff.reckless_swings.up then
            gain(5, "rage")
            removeStack("reckless_swings")
        end
    end,
})
```

> [!NOTE]
> **On Forever:** The game hides most of the amounts of the player's hits on the target, while avoids stay visible. A white swing with no avoid seen is therefore presumed landed, at the swing's own time.

## See also

- [APL windows](APL-Windows)
- [Pack environment names](Pack-Environment-Names)
- [Pack belief and simulation](Pack-Belief-And-Simulation)
