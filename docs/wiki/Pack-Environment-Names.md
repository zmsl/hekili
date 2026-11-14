<!--
Purpose: The names and verbs available inside content functions.
Type: Reference
Audience: Lua developers
Prerequisites: [Pack API reference](Pack-API-Reference).
-->
A content function, such as an ability's `now` or `handler`, runs with an **environment** the core sets, so a bare name inside it, like `buff` or `gain`, answers from that environment rather than from Lua's globals. There are two environments: the simulated `state`, where `handler`, field functions, state expressions and hooks run, and the belief's `now` context, where `now`, `onCrit`, `onLand`, `now_finish`, reactions and window evaluators run. This page lists the names each environment offers, and the verbs that write to it. Why there are two is explained on [Pack belief and simulation](Pack-Belief-And-Simulation).

| Environment names | |
|---|---|
| Simulation | `state`, in `src/Hekili/Engine/Sim/State.lua`: every name a priority can read, plus the verbs |
| Belief | The `now` context, in `src/Hekili/Game/State/Families/Now.lua`: the names below and nothing else |
| Shared names | The plain reads in [Names in both](#names-in-both) |
| Part of the content API | Yes: adding or changing a name changes `CONTENT_API` ([Pack overview](Pack-Overview#the-content-api-version)) |

## Names

### Names in both

These names answer in both environments, with the same meaning. A function that both layers run, such as an aura's `duration` or an ability's `spend`, reads only these.

| Name | Meaning |
|---|---|
| `buff.<key>`, `debuff.<key>` | An aura on the player or the target: `.up`, `.down`, `.remains`, `.stack` (or `.count`), `.expires`, `.applied` |
| `talent.<key>` | A registered talent: `.rank`, `.enabled` |
| `<resource>` | A resource by key, such as `energy`: `.current`, `.lo`, `.hi`, `.max` |
| `set_bonus.<key>` | A registered gear set's count of worn pieces, or a set bonus's 1 or 0 |
| `equipped.<key>` | True when `set_bonus.<key>` is above 0 |
| `equipped.shield` | True when a shield is worn |
| `weapon.size` | The main hand's size: 2 for a two-handed weapon |
| `totem.<element>` | `fire`, `earth`, `water` or `air`: `.up` (or `.active`), `.down`, `.remains`, `.expires` |
| `window.<name>` | A registered window: `.up`, `.remains`, `.elapsed`, `.step`. The simulation also answers `.next.<ability key>`. |
| `settings.<key>` | The active spec's value of a class setting ([Pack settings](Pack-Settings)) |
| `action.<key>.in_range` | Whether the target is in range of the ability, as the client last answered |
| `knownRank(ids)` | The highest known rank of a rank list, 0 when none is known |
| `stat(name, arg)` | A stat read by the client's function name, such as `stat("UnitStat", 5)`: the plain answer, or the last plain one when the client hides it |
| `swingBase(hand)` | A hand's unhasted swing speed (1 main hand, 2 off hand), 0 before a plain read |
| `healthMax` | The player's maximum health |
| `mainhand_speed`, `offhand_speed` | The current swing speeds |
| `haste` | The spell haste multiplier |
| `now` | The current time: the cast's time in the belief, the forecast's starting time in the simulation |
| `combat` | When combat started, 0 out of combat |
| `level` | The player's level |

`stat` differs in one way: in the simulation it is also the stat table, so `stat.crit` works there, while in the `now` context it is only the function.

### Names only in the belief

| Name | Meaning |
|---|---|
| `instant` | True inside an instant cast's `now`; false elsewhere |
| `cast_start` | The cast's start time; 0 for an instant |
| `target.health` | The belief's bounds on the target's health, in percent: `.known`, `.lo`, `.hi` (0 and 100 while unknown). There is no `.pct`: a hidden health is unknown, so a `now` tests a bound, such as `target.health.hi < 35` for "proven below 35%". |
| `usable.<key>` | The client's last plain answer to whether the ability is usable; false before one |
| `lastSwing(hand)` | The time of the last observed swing of a hand (1 main, 2 off, 3 ranged); 0 for none |
| `nextSwing(hand)` | The next expected swing of a hand; 0 when unknown |

The `now` context also has Lua's pure helpers: `math`, `min`, `max`, `floor`, `ceil`, `abs`, `type`, `select`, `tonumber` and `error`. It has no game API and no other global. Assigning any name raises an error, which the belief counts.

### Names only in the simulation

The simulated `state` holds every value a priority line can read: `cooldown.<key>`, `action.<key>`, `prev_gcd`, `active_enemies`, `time`, `query_time`, `target.creature_type`, the weapon keys such as `main_hand.dagger`, and the rest of the [APL expression reference](APL-Expression-Reference). It also holds the class's state expressions, state functions and state tables, and the game functions the core exposes there. A `handler` or a field function can read all of them; a `now` cannot.

> [!NOTE]
> **On Forever:** `health.pct` and the time-to-die values exist only in the simulation, and they answer for an unknown value (full health, and 3600 seconds) when the game hides the real one. A `now` reads the target's health only as `target.health` bounds.

### Helpers at file level

A function defined at the top of a class file keeps the file's environment, not the layer's. Inside it, `buff`, `talent` and the verbs are Lua globals, which do not exist. A helper that needs the known rank takes it from a local set once as `local rankOf = state.knownRank`, which gives the same answer in both layers; anything else it needs is passed as an argument by the class pack function that calls it.

## Verbs

The verbs write the effect of a cast. In a `handler` they change the simulated state for the rest of the forecast. In a `now` they write modelled samples into the belief at the cast's time, which any later observation overrides. Called from anywhere else, a belief verb writes nothing.

| Verb | Meaning | Belief | Simulation |
|---|---|---|---|
| `gain(amount, resource)` | Adds to a resource | Yes | Yes |
| `spend(amount, resource)` | Takes from a resource | Yes | Yes |
| `resetResource(resource, amount, upto)` | Sets a resource to `amount`, or up to `upto` more by a roll the belief cannot see | Yes | No |
| `applyBuff(aura, duration, stacks)` | Puts a player aura up. Without `duration`, the aura's registered one. | Yes | Yes |
| `applyDebuff(unit, aura, duration, stacks)` | Puts a target aura up | Yes | Yes |
| `removeBuff(aura)` | Takes a player aura down | Yes | Yes |
| `removeDebuff(unit, aura)` | Takes a target aura down | Yes | Yes |
| `addStack(aura, duration, stacks)` | Adds stacks to a player aura | Yes | Yes |
| `removeStack(aura, stacks)` | Removes stacks (1 by default), keeping the expiry; the aura goes down at 0 | Yes | Yes |
| `setCooldown(action, duration)` | Sets an ability's cooldown; 0 makes it ready | Yes | Yes |
| `reduceCooldown(action, time)` | Shortens a running cooldown, or brings the next charge sooner | Yes | Yes |
| `summonTotem(name, element, duration)` | Fills an element's totem slot | Yes | Yes |
| `summonPet(key, duration)` | Summons a pet; a guardian registered with a `cap` gains one expiring summon | Yes | Yes |
| `dismissPet(key)` | Dismisses a pet, or ends a guardian's summons | Yes | Yes |
| `openWindow(name)` | Opens a window. The simulation's also takes `duration` and `refresh`. | Yes | Yes |
| `closeWindow(name)` | Closes an open window | Yes | Yes |

The simulation also keeps the original Hekili's other verbs, such as `removeDebuffStack` and `interrupt`, and the class's state functions. The belief's verbs use the original's names and argument order, so a line ported from a Classic `handler` reads the same in a `now`.

## See also

- [Pack belief and simulation](Pack-Belief-And-Simulation)
- [Pack abilities reference](Pack-Abilities-Reference)
- [Pack windows and reactions](Pack-Windows-And-Reactions)
- [APL expression reference](APL-Expression-Reference)
