# VirtualGameAPI-1.0

A LibStub library that sits between an addon and the World of Warcraft game API. On clients that return
secret values (WoW Forever, Midnight), many reads an addon relies on (resources, stats, aura data, cooldown
times) cannot be compared or computed with in combat, and some older globals no longer exist. The addon reads
every game API through this library instead of the global, so each read has one place where its Forever
behaviour is decided.

Today that decision is either "call the real function" or "return a fixed, harmless, API-shaped value". Later a
virtual game state answers the stubbed reads, and caching or secrecy checks attach to the single passthrough seam,
without touching the addon's call sites.

```lua
local VGA = LibStub( "VirtualGameAPI-1.0" )
local UnitPower, GetSpellCooldown = VGA.UnitPower, VGA.C_Spell.GetSpellCooldown
```

## Statuses

| Status | Meaning |
|---|---|
| `passthrough` | The real function, called through one seam (`invoke`). |
| `stub` | A fixed, non-secret result in the real API's shape. Table results are shared constants: read them, never mutate them. |
| `missing` | Declared passthrough, but the real function does not exist on this client; returns `nil`. |

## Query API

- `VGA.Status( name )`: `"passthrough"`, `"stub"`, `"missing"`, or `nil` for a name the library does not know.
- `VGA.Why( name )`: the reason string for the decision (secrecy class and probe reference, or "absent on Forever").
- `VGA.Stubs()`: sorted array of every name that is not a live passthrough (stubs and missing). Built once at load.
- `VGA.Inventory()`: sorted array of every registered name.

Names use the game's spelling: `UnitPower`, `C_Spell.GetSpellCooldown`, `AuraUtil.ForEachAura`.

## Adding an entry

1. Add the name to the addon's `tools/api_inventory.txt` (sorted) and a row to the inventory table in
   `docs/forever-facade-notes.md`; the tests require the library and the inventory to match exactly.
2. Add one line in `VirtualGameAPI-1.0.lua` under the matching family comment:
   - `passthrough( "C_Foo.GetBar", "plain [probe ref]" )`, or
   - `stub( "C_Foo.GetBar", nothing, "secret in combat [probe ref]" )`, reusing a shared stub function
     (`zero`, `zero2`, `zero4`, `zeros`, `nothing`, `noop`, `isFalse`, ...) whenever the shape fits. Write a new
     local only for a new shape, and never allocate in it: return a shared constant table.
3. Run the tests.

## Running the tests

From the addon root (the `.busted` file there points at `Libs/VirtualGameAPI-1.0/spec`):

```sh
busted
```

The tests run headless under Lua 5.1 with a fake `_G` and `LibStub`.

## Out of scope for now

- Events: `RegisterEvent` diversion, a virtual combat log and `UNIT_AURA` payloads are Phase 1 and Phase 3b work.
- Caching: a later addition at the `invoke` seam.

## Licence

MIT, see `LICENSE`.
