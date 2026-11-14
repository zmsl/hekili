<!--
Purpose: expects kinds and what an ability's hit looks like.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack abilities reference](Pack-Abilities-Reference).
-->
An ability's `expects` field tells the core what the cast's hit looks like: whether it hits at once, flies to the target, lands with the next swing, ticks, or deals no damage at all. The Forever client gives addons no combat log, so the core cannot ask which cast caused a hit. Instead it opens a **ticket** for each cast and pays each outcome it sees on the target (a hit, a miss, a tick) to the cast that should have made it. `expects`, with `school` and `velocity`, is plain data on the ability that tells the core what to wait for.

| expects | |
|---|---|
| Field | `expects` on an ability, with `school`, `velocity` and the applied aura's `tick_time` |
| Kinds | `"none"`, `"instant"`, `"debuff"`, `"travel"`, `"strike"`, `"ticks"`, `"channel"` |
| Default | `"strike"` with `onNextSwing`, `"instant"` with `startsCombat`, else `"none"` |
| Read by | The belief (`src/Hekili/Game/State/Families/Expect.lua`) |
| Checked by | `tests/Forever/expects_spec.lua`, each class spec, `make spell-data-check` |

## Kinds

| Kind | The cast's hit | Needs |
|---|---|---|
| `"none"` | No row: a buff, a summon, a form | |
| `"instant"` | One row in the same frame as the cast | `school` |
| `"debuff"` | An effect that deals no damage, such as an armor debuff or a taunt. Only its own miss, dodge or parry pays it; its success makes no row. | No `school`, no ticking aura |
| `"travel"` | A projectile: one row when it arrives | `velocity` |
| `"strike"` | One row with the next melee swing | `onNextSwing` |
| `"ticks"` | A damage-over-time effect with no direct hit: one row per tick | An aura with `tick_time` and `dot = "debuff"` |
| `"channel"` | One row per tick of a channel | An aura with `tick_time` |

`"melee"` is the core's own kind for white swings; a pack cannot declare it. `"channel"` is accepted but no shipped pack uses it, and it has not been checked in the game.

## Fields

| Field | Meaning |
|---|---|
| `expects` | The kind, from the table above |
| `school` | The spell's school by name: `"physical"`, `"holy"`, `"fire"`, `"nature"`, `"frost"`, `"shadow"` or `"arcane"` (`Hekili.SCHOOL`). Leave it out when the spell's school mask has no single name. |
| `velocity` | A projectile's speed in yards a second, from the spell data's speed |

A ticking kind reads the aura the ability applies: the ability's `cycle` if set, else its `aura`, else the aura with the ability's own key. That aura's `tick_time` is the period, and `floor(duration / tick_time)` is the number of ticks, both read at each cast; a function is evaluated in the simulated state. The ability itself has no tick fields.

An `"instant"` or `"travel"` ability whose aura has a `tick_time` and `dot = "debuff"` also ticks after its hit. A `"ticks"` ability may also have a `velocity`, for a damage-over-time effect that flies to the target.

## Examples

A frost projectile, from `src/Hekili_Mage/Mage.lua`, shortened:

```lua
frostbolt = {
    id = 116,
    expects = "travel",
    velocity = 28,
    school = "frost",
    -- ...
},
```

A damage-over-time effect, from `src/Hekili_Druid/Druid.lua`, shortened. The ability declares the kind and school; its aura declares the ticks:

```lua
-- in RegisterAbilities
insect_swarm = {
    id = 5570,
    expects = "ticks",
    school = "nature",
    -- ...
},

-- in RegisterAuras
insect_swarm = {
    id = 5570,
    duration = function()
        return 12 + 2 * talent.natures_splendor.rank --[[ + gear ]]
    end,
    tick_time = 2,
    dot = "debuff",
    max_stack = 1,
},
```

An effect that deals no damage, from `src/Hekili_Druid/Druid.lua`:

```lua
challenging_roar = {
    id = 5209,
    expects = "debuff",
    -- ...
},
```

## Malformed declarations

A declaration that breaks the table's rules is malformed: an `"instant"` with no `school`, a `"travel"` with no `velocity`, a `"strike"` without `onNextSwing`, a `"ticks"` whose aura has no `tick_time` or `dot = "debuff"`, a `"debuff"` with a `school` or a ticking aura, or an unknown kind. The core counts it in the snapshot's error count and uses the default for that ability instead. The class specs check that every declared outcome builds as declared.

## Checking against the spell data

`make spell-data-check` reads every pack's `expects`, `velocity`, `school` and aura `tick_time` against the game's spell tables. It needs a local copy of those tables, so it is not part of `make check`.

- A rank with no row in the tables is printed as a note and passes; a mismatch fails.
- A declared `velocity` must match the rank's speed.
- An ability that starts combat and whose first rank has a speed above 0 must declare `velocity`, unless it is `"none"` (such as a summon) or `"ticks"`.
- A `"debuff"` fails when any rank has a damaging effect.

> [!NOTE]
> **On Forever:** The game hides the amounts and kinds of most hits on the target, so many target rows cannot be paid to a cast in the game. The tickets still close in time, and a cast's `now` does not wait for them. The fields matter most where rows are plain: in the test harness, in replays, and in any area where the game shows them.
<!-- UNVERIFIED: the extent to which target rows are hidden in each area of the game; the note follows the architecture notes on hidden target rows. -->

## See also

- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack auras reference](Pack-Auras-Reference)
- [Pack belief and simulation](Pack-Belief-And-Simulation)
