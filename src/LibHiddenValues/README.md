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

-- An execute icon: shown while the target is below 20%. lo == nil means unknown (priming, no target, the
-- capability lost): hide it then. A dead target is unknown only when the client tells the death plainly; under the
-- dungeon restrictions it may not, and the band then stays at 0-20: check death yourself if a corpse must not count.
local h = LHV:Watch("MyAddon", { kind = "health", unit = "target", edges = { 20 } }, function(h, lo, hi, dir, t, q)
    icon:SetShown(lo ~= nil and hi <= 20)
end)
```

- The value is in `lo <= value < hi` (percent 0-100; `hi` is inclusive at 100). `dir` is `1` up, `-1` down, `0` for
  the first band after unknown. `t` is `GetTime()` of the frame in which the change was seen (for a handle on several
  edges, the frame before the call; for an unknown call, the frame of the call); `q` is the quality (`LHV.BAND` = 2,
  `LHV.UNKNOWN` = 0).
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
| `power` | `unit`, `edges`, `power` (`Enum.PowerType`, required) | `player`: mana, energy |

`power` has no default: the displayed power changes with a form, and a handle must not change what it measures. Every
other kind, token or option (a `step` without `edges`, `points`, rage, `focus`, ...) returns a handle whose state is
`"unavailable", "unproven"`: write against it now, it comes alive when its stage ships. A `step` beside `edges` is
ignored for now: the edges are served and `h:Domain()` returns a nil step. Bad input (a missing `power` too) returns
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

Diagnostics are a consumer's job: the library prints nothing (an error goes to the client's error handler), registers
no slash command and shows no frame of its own. The calls below answer everything a diagnostic tool needs; LHVProbe is
the reference consumer (`/lhvp`).

| Call | Returns |
|---|---|
| `LHV:GetVersion()` | `major, minor` (`"LibHiddenValues-1.0", 1`) |
| `LHV:GetKinds()` | a fresh array, one `{ kind =, state =, reason = }` per kind of the major, in contract order (`health`, `power`, then the unproven ones); `state` and `reason` as `IsAvailable` |
| `LHV:IsAvailable(kind, unit)` | `ok, state, reason` (`state` `"ready"`, `"pending"` or `"unavailable"`; `reason` nil unless unavailable) |
| `LHV:OnCapability(owner, fn)` | nothing; `fn(kind, state, reason)` on each change |
| `LHV:GetStats()` | `bars, usFrame, usPeak, pushesPerSec, firesPerSec, desyncs, level, barsMade`: bars in use, average and peak µs per frame, pushes and firings per second, desyncs, governor level (0 for now), bars made |
| `LHV:GetSources()` | a fresh array, one `{ kind =, unit =, power =, handles =, bars =, active = }` per source with a watch, in creation order (`power` nil for health; `active`: fed every frame) |
| `LHV:SelfTest(fn)` | nothing; runs the self-test (or joins the run going) and calls `fn(pass, lines)` when it ends: `pass` a boolean, `lines` an array of strings under 255 characters, the last one `selftest PASS ...` or `selftest FAIL ...`. Called at once (inside `SelfTest`) when it cannot run: the client lacks the API, switched off, or no free bar (the earlier verdict then stands). Before login it waits for the login run. `lines` is shared: read it, do not change it |
| `LHV:GetSelfTest()` | `verdict, lines, running`: the last completed run's verdict (`true`/`false`; nil before the first, and after `SetEnabled(true)` until a run ends), its lines (the array `fn` got; nil before the first) and whether a run is going |
| `LHV:SetEnabled(on)` | nothing. `false`: every kind `unavailable, off` for this session. `true` after `false`: pending until a fresh self-test passes (it starts one). Already on, it changes nothing: after a failed self-test, `LHV:SelfTest(fn)` runs it again and the kinds come back when it passes |

`GetKinds`, `GetSources` and `GetSelfTest` build or hand out tables: call them from a command, not every frame.

## Credits

The technique of reading a hidden value's thresholds back from a status bar's fill has prior public use in other
Forever addons; this library is written from its authors' own probes.
