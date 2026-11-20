# LibHiddenValues-1.0

Threshold events for unit health and power on World of Warcraft Forever (Interface 16001), where the client hides
those values from addons. Your addon says which thresholds it cares about; the library tells it, as plain numbers,
which band the value is in and when it crosses one. Your code never touches a hidden value.

MIT licence (see `LICENSE`). Works installed on its own or embedded in your addon; LibStub keeps one running copy (the
newest minor) either way, and every addon that watches the same thing shares the same bars.

## Quick start

Standalone: list it in your TOC with `## OptionalDeps: LibHiddenValues`. Embedded: copy the folder into your addon
and include `LibHiddenValues.xml` from your `embeds.xml`.

```lua
local LHV = LibStub and LibStub("LibHiddenValues-1.0", true)
if not LHV then return end -- keep your own fallback

-- An execute icon: shown while the target is below 20%. lo == nil means unknown (priming, no target, a dead
-- target, the capability lost): hide it then.
local h = LHV:Watch("MyAddon", { kind = "health", unit = "target", edges = { 20 } }, function(h, lo, hi, dir, t, q)
    icon:SetShown(lo ~= nil and hi <= 20)
end)
```

- The value is in `lo <= value < hi` (percent 0-100; `hi` is inclusive at 100). `dir` is `1` up, `-1` down, `0` for
  the first band after unknown. `t` is `GetTime()` of the frame; `q` is the quality (`LHV.BAND` = 2, `LHV.UNKNOWN` =
  0).
- At most one call per handle per frame. A handle on one edge is called in the frame of the change; on several edges,
  one frame later, with the net band (a jump over three edges is one call).
- `h:Get()` returns `lo, hi, t, q` without a callback; `h:State()` returns `state, reason`; `h:SetPaused(true)` stops
  feeding while your frame is hidden; `h:Release()` and `LHV:ReleaseAll("MyAddon")` drop watches.
- `LHV:IsAvailable(kind, unit)` returns `ok, state, reason`; `LHV:OnCapability("MyAddon", fn)` calls
  `fn(kind, state, reason)` when that changes. A kind is `"pending"` for about a second after login (the self-test),
  then `"ready"`.

## What works now

| Kind | Spec | Proven on |
|---|---|---|
| `health` | `unit`, `edges`, `predicted` (default true) | `player`, `target` |
| `power` | `unit`, `edges`, `power` (`Enum.PowerType`; omitted: the displayed power) | `player`: mana, energy |

Every other kind, token or option (`step`, `points`, rage, `focus`, ...) returns a handle whose state is
`"unavailable", "unproven"`: write against it now, it comes alive when its stage ships. Bad input returns
`nil, "bad-spec: ..."`.

## Testing your addon

`Testing/FakeClient.lua` runs the real library on a fake client (stock Lua 5.1, not in the TOC):

```lua
local Fake = dofile("libs/LibHiddenValues/Testing/FakeClient.lua")
Fake.world.unit.target = { health = 1.0 }  -- fractions, as the client has them
dofile("MyAddon.lua")
Fake.login()                                -- login, then frames until the self-test passed
Fake.tick(10)                               -- priming
Fake.world.unit.target.health = 0.19
Fake.tick(1)
Fake.restore()
```

Its header lists the world fields, the fault knobs (`closed`, `lag`, `drop`, `snap`, `maxpoints`, `refuse`) and what
it does not model.

## Diagnostics

`/lhv` (status), `/lhv selftest`, `/lhv stats`, `/lhv watch health target 20 50`, `/lhv watch off`, `/lhv copy` (all
output in a box you can copy from), `/lhv off` and `/lhv on` (this session only).

## Credits

The technique of reading a hidden value's thresholds back from a status bar's fill has prior public use in other
Forever addons; this library is written from its authors' own probes.
