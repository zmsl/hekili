# LibHiddenValues-1.0

Threshold events for unit health and power, and for auras the client's Cooldown Manager shows, on World of Warcraft
Forever (Interface 16001), where the client hides those values from addons. Your addon says which thresholds it cares about; the library tells it, as plain numbers,
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
  edges, and for any handle's first band after a prime, the frame before the call; for an unknown call, the frame of
  the call); `q` is the quality (`LHV.BAND` = 2,
  `LHV.UNKNOWN` = 0).
- At most one call per handle per frame. A handle on one edge is called in the frame of the change; on several edges,
  one frame later, with the net band (a jump over three edges is one call).
- `h:Get()` returns `lo, hi, t, q` without a callback; `h:State()` returns `state, reason` (`"live"` means a band is
  known: `Get()` has it); `h:SetPaused(true)` stops
  feeding while your frame is hidden; `h:Release()` and `LHV:ReleaseAll("MyAddon")` drop watches.
- `LHV:IsAvailable(kind, unit)` returns `ok, state, reason`; `LHV:OnCapability("MyAddon", fn)` calls
  `fn(kind, state, reason)` when that changes. A kind is `"pending"` for about a second after login (the self-test),
  then `"ready"`.

## What works now

| Kind | Spec | Proven on |
|---|---|---|
| `health` | `unit`, `edges`, `predicted` (default true) | `player`, `target` |
| `power` | `unit`, `edges`, `power` (`Enum.PowerType`, required) | `player`: mana, energy, rage (rage: proven by the BandProbe2 warm-up, the library's own run owed) |
| `aura` | `unit`, `spell`, `what`, `edges`, `max` | `player`, `target`: read from the Cooldown Manager, **not yet run in game** (below) |

`power` has no default: the displayed power changes with a form, and a handle must not change what it measures. Every
other kind, token or option (a `step` without `edges`, `points`, focus or another power type, the `focus` token, ...)
returns a handle whose state is `"unavailable", "unproven"`: write against it now, it comes alive when its stage
ships. A `step` beside `edges` is
ignored for now: the edges are served and `h:Domain()` returns a nil step. Bad input (a missing `power` too) returns
`nil, "bad-spec: ..."`.

## Auras (from the Cooldown Manager)

The client hides aura data from addons in combat, but its Cooldown Manager still shows the auras the player placed
there. The `aura` kind reads those items: it never changes the player's Cooldown Manager (nothing is shown, hidden,
faded, moved or re-laid out; it only post-hooks the items' own updates), so it can only serve what the player placed.

```lua
-- Stacks of a debuff on the target (bands 0-2, 2-4, 4+), and whether a buff of mine is up.
LHV:Watch("MyAddon", { kind = "aura", unit = "target", spell = 12345, what = "stacks", edges = { 2, 4 } }, sink)
LHV:Watch("MyAddon", { kind = "aura", unit = "player", spell = 67890, what = "up" }, sink)
```

| Field | Meaning |
|---|---|
| `unit` | `"player"` or `"target"` (the only units the Cooldown Manager reads; another token is `unavailable, unproven`) |
| `spell` | the aura's spell ID; it matches a Cooldown Manager entry by its spell, override, tooltip override or linked spells, and the watch then answers for that entry: whatever aura of the entry the client shows (a sibling linked aura reads as this one) |
| `what` | `"up"`: presence, `lo == hi`, 1 up and 0 not. `"stacks"`: the stack count. `"left"`: seconds left |
| `edges` | `stacks`: whole numbers from 1 (1 is presence itself); `left`: seconds above 0.01 (required) |
| `max` | `stacks` only: the top of the domain; alone it means every count from 1 to `max` (an exact count) |

An absent aura is a known value: no stacks and no seconds, the lowest band (`0` to the lowest edge), `up` 0. A
handle is unknown (`lo == nil`) only while no item shows it (`gone`) or before its first band (`priming`); `"live"`
always comes with a band. The client hides the count at one stack: an aura that is up with no count reads 1. `left`
on an aura with no duration reads the lowest band while it is up (the client pushes 0 seconds for it), which looks
like "about to expire": watch `up` for such auras.
`h:Domain()` returns `nil, 0, top`: 1 for `up`, `max` (or `math.huge`) for stacks, `math.huge` for seconds. An aura
handle is called one frame after the change (`h:Latency()`).

What each placement gives (the player chooses it in the Cooldown Manager's settings):

| Placement | `up` | `stacks` | `left` |
|---|---|---|---|
| Tracked Bar | yes | yes | yes |
| Tracked Buff icon | yes | yes | no: `unavailable, cdm-icon-only` |
| Essential or Utility, a hidden category, or nowhere | no | no | no |

`LHV:IsAvailable("aura", spec)` (the whole spec, without a watch) and `h:State()` answer `ready`, `pending` (not read
yet; also after a reload in combat, until combat ends) or `unavailable` with one of these reasons:

| Reason | Meaning | What the player can do |
|---|---|---|
| `cdm-off` | the Cooldown Manager is switched off (Options), the client says it is not available, or its viewers are missing | switch it on |
| `not-in-cdm` | no Cooldown Manager entry names this spell | nothing: the client cannot track it there |
| `cdm-not-tracked` | an entry names it, but no tracked buff icon or bar shows it | place it in Tracked Buffs, or Tracked Bars for its timer |
| `cdm-icon-only` | `what = "left"` on an aura shown as an icon | move it to Tracked Bars |

The library only reports: telling the player is your addon's choice. `LHV:OnCapability(owner, fn)` calls
`fn("aura", state, reason)` when the kind changes (`cdm-off`) and `fn("aura", state, reason, h)` for each of your aura
handles whose answer changed (the player placed or removed the aura, a layout change). A handle is `gone` (unknown)
while its item cannot be read: its viewer hidden (Edit Mode "Hidden", or the whole UI hidden), Edit Mode open, or, in
combat after the client re-laid the items out, an item whose identity the client keeps secret (until combat ends).

A bar is read 4 frames (`LHV.SETTLE`) after the client's first push into it, so the first band is the true one, once,
with dir 0. A stacks watch started while its aura is already up stays `priming` until the client next writes the
count (an application, a refresh, a target swap); after a re-layout (UI scale, a loading screen) an aura handle is
unknown until its bars settle again. When an aura comes back the band before it stands while the count settles. A
refresh within a frame of a seconds edge can be told up to about 10 frames late (the band before it stands
meanwhile). `OnCapability` is not called from inside `Watch` or `IsAvailable`: read `h:State()` there (an answer
`IsAvailable` gives may be a frame old; the callbacks follow on the next frame). A paused aura handle only reports
unknown; its bars keep following the client.

## Testing your addon

`Testing/FakeClient.lua` runs the real library on a fake client (stock Lua 5.1, not in the TOC):

```lua
local Fake = dofile("libs/LibHiddenValues/Testing/FakeClient.lua")
Fake.world.unit.target = { health = 1.0 }  -- fractions, as the client has them
dofile("MyAddon.lua")
Fake.login()                                -- login, then frames until the self-test passed
Fake.tick(12)                               -- priming: 10 frames at least (hold 4, push, settle 4, decode)
Fake.world.unit.target.health = 0.19
Fake.tick(1)
Fake.restore()
```

Its header lists the world fields, the fault knobs (`closed`, `lag`, `secretlag`, `drop`, `snap`, `maxpoints`,
`refuse`) and what it does not model. It also models the Cooldown Manager (`W.cdm`, `W.aura`, `Fake.setAura`,
`Fake.cdmLayout`, `Fake.cdmEnable`): see the comment above its viewers.

## Diagnostics

Diagnostics are a consumer's job: the library prints nothing (an error goes to the client's error handler), registers
no slash command and shows no frame of its own. The calls below answer everything a diagnostic tool needs; LHVProbe is
the reference consumer (`/lhvp`).

| Call | Returns |
|---|---|
| `LHV:GetVersion()` | `major, minor` (`"LibHiddenValues-1.0", 2`) |
| `LHV:GetKinds()` | a fresh array, one `{ kind =, state =, reason = }` per kind of the major, in contract order (`health`, `power`, `cooldown` ... `aura` ... `meter`: the major's twelve); `state` and `reason` as `IsAvailable` |
| `LHV:IsAvailable(kind, unit)` | `ok, state, reason` (`state` `"ready"`, `"pending"` or `"unavailable"`; `reason` nil unless unavailable). `unit` may be a whole spec: the aura kind then answers for its placement |
| `LHV:OnCapability(owner, fn)` | nothing; `fn(kind, state, reason)` on each change, and `fn("aura", state, reason, h)` for each of the owner's aura handles whose answer changed |
| `LHV:GetAuraSources()` | a fresh array, one `{ unit =, spell =, what =, handles =, bars =, active =, cooldownID =, placement =, state =, reason =, up = }` per aura source with a watch (`placement` `"bar"`, `"icon"` or nil; `up` true, false or nil for unknown); then `off, read, texts, values, refused, reads`: the Cooldown Manager is off, its catalogue was read, count texts and bar values forwarded, values a bar refused, item reads |
| `LHV:GetStats()` | `bars, usFrame, usPeak, pushesPerSec, firesPerSec, desyncs, level`: bars in use, average and peak µs per frame, pushes and firings per second, desyncs, governor level (0 for now) |
| `LHV:GetPool()` | `made, cap`: bars made (32 at login; frames are never destroyed) and the cap (256) |
| `LHV:GetSources()` | a fresh array, one `{ kind =, unit =, power =, predicted =, handles =, bars =, active = }` per source with a watch, in creation order (`kind`, `unit`, `power`, `predicted` are the source's key: watches differing in any of them do not share bars; `power` nil for health; `active`: fed every frame) |
| `LHV:SelfTest(fn)` | nothing; runs the self-test (or joins the run going) and calls `fn(pass, lines)` when it ends: `pass` a boolean, `lines` an array of strings under 255 characters, the last one `selftest PASS ...` or `selftest FAIL ...`. Called at once (inside `SelfTest`) when it cannot run: the client lacks the API, switched off, or no free bar (an earlier verdict then stands; with none it is a FAIL). Before login it waits for the login run. The capability has already changed when `fn` runs: `IsAvailable` and the handles' `State()` show the new verdict. `lines` is shared: read it, do not change it |
| `LHV:GetSelfTest()` | `verdict, lines, running`: the last completed run's verdict (`true`/`false`) and its lines (the array `fn` got), both nil before the first run and again after `SetEnabled(true)` until the new run ends; and whether a run is going |
| `LHV:SetEnabled(on)` | nothing. `false`: every kind `unavailable, off` for this session. `true` after `false`: pending until a fresh self-test passes (it starts one). Already on, it changes nothing: after a failed self-test, `LHV:SelfTest(fn)` runs it again and the kinds come back when it passes |

`GetKinds`, `GetSources`, `GetAuraSources` and `GetSelfTest` build or hand out tables: call them from a command, not every frame.

## Credits

The technique of reading a hidden value's thresholds back from a status bar's fill has prior public use in other
Forever addons; this library is written from its authors' own probes.
