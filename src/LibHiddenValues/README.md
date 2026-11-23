# LibHiddenValues-1.0

Threshold events for unit health and power, and for auras the client's Cooldown Manager shows, on World of Warcraft
Forever (Interface 16001), where the client hides those values from addons. Your addon says which thresholds it cares about; the library tells it, as plain numbers,
which band the value is in and when it crosses one. Your code never touches a hidden value.

MIT licence (see `LICENSE`). Embedded only: it is not published on its own. LibStub keeps one running copy (the
newest minor), and every addon that watches the same thing shares the same bars.

## Quick start

Copy the folder into your addon and include `LibHiddenValues.xml` from your `embeds.xml`.

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
  edges, the frame before the call; on a `step` or `precision` source, the frame of the change's LAST firing (one
  frame after its first when its firings split over two frames), or of a prime's last push: two frames before the
  call for a change of the value, one frame for an edge or point bar kept inside a ring quantum, which moves the band
  while the value stays; for an unknown call, the frame of the call); `q` is the quality
  (`LHV.BAND` = 2, `LHV.UNKNOWN` = 0).
- At most one call per handle per frame. A handle on one edge is called in the frame of the change; on several edges,
  one frame later, with the net band (a jump over three edges is one call); on a `step` or `precision` source every
  change waits for the next frame's decode to agree (confirmation, below), so two frames later, three when its firings
  split. While changes' firings keep landing, up to six frames later: at most five frames hold, then the handle is
  called with the value or, after a desync, unknown. `h:Latency()` gives that worst case in seconds (seven frames,
  counted from the frame the change's first firing arrives, or from a prime's last push: the client's own delay before
  it is not counted).
- `h:Get()` returns `lo, hi, t, q` without a callback; `h:State()` returns `state, reason` (`"live"` means a band is
  known: `Get()` has it); `h:SetPaused(true)` stops
  feeding while your frame is hidden; `h:Release()` and `LHV:ReleaseAll("MyAddon")` drop watches.
- `LHV:IsAvailable(kind, unit)` returns `ok, state, reason`; `LHV:OnCapability("MyAddon", fn)` calls
  `fn(kind, state, reason)` when that changes. A kind is `"pending"` for about a second after login (the self-test),
  then `"ready"`. An aura `up` watch uses no bar: the self-test, pending or failed, never holds it (below).

## What works now

| Kind | Spec | Proven on |
|---|---|---|
| `health` | `unit`, `edges`, `step`, `predicted` (default true) | `player`, `target` |
| `power` | `unit`, `power` (`Enum.PowerType`, required), `edges`, `step`, `points`, `precision` | `player`: mana, energy, rage (rage: proven by a separate probe, the library's own run owed) |
| `aura` | `unit`, `spell` or `cooldown`, `what`, `edges`, `max` | `player`, `target`: read from the Cooldown Manager; run in game on minor 7 (2026-11-21: the kind ready, target swaps and a cleared target right). The hooks on first use (minor 8) are not yet run there |

A spec needs at least one of `edges`, `step`, `points` or `precision`.

- `edges`: thresholds in percent, (0.05, 100].
- `step`: position. Any step is granted as 1: the band is the 1% cell (`lo`, `lo + 1`), `h:Domain()` returns step 1.
  Beside `edges` the band is cut by both (an edge on the 1% grid costs no bar). The source runs 8 bars (a Gray code
  and a parity bar) while any watch on it asks for a step. A jump of any size is one call, two frames later (three when
  one change's firings split over two frames): every change is confirmed first (below). Full reads `100, 100`.
  Health only (minor 9): exactly empty reads `0, 0`, and `0, 1` means above 0 (a little left); no extra bar. Health
  under one millionth of the max also reads empty: exact below 1,000,000 max health; at 1,000,000 and above the lowest health
  (under max / 1,000,000) reads `0, 0`; a target's max is hidden, so the library cannot tell which side it is on.
  Measured on plain values only; on the hidden values at empty, and predicted against real health at 0, it is
  assumed, not measured. Empty says nothing about death (that is your call); a unit the client plainly calls dead
  reads unknown (`gone`), so `0, 0` shows only before that. A watch with only `edges` reads `0, e` at empty, as before.
  Power at 0 still reads `0, 1`.
- `points` (player power): whole-number thresholds in the value's own units, e.g. `{ 40, 60 }` energy. A handle with
  `points` (even `{}`) answers in points: `lo`, `hi` and `h:Domain()` (0 to the player's plain max) are in points.
  The cut is `points / max`; it moves with the max (`UNIT_MAXPOWER`: the handle goes unknown while it primes again).
  Identical points share a bar; a point on the 1% grid of a `step` source costs no bar. Caps (`GetPool`): 8 distinct
  points per source and 64 in total, each counted as if it needed a bar (a point answered without one while a `step`
  or `precision` watch is there needs one when that watch goes), checked when you ask; over either the whole request
  is refused (`edge-limit`), nothing granted. `h:SetPoints(list)` swaps a handle's points in one step: `true`, or
  `nil, code` with the old set kept. While the max was never read as a plain number the handle is `unavailable, max-unknown`.
- `precision = "point"` (player power): the exact value. `h:Exact()` returns `value, step` (value nil while unknown):
  step 1 up to a max of 3175, above it the step grows until every curve fits the client's 256-point limit (6400 mana:
  step 3). `q` is `LHV.EXACT` (3) at step 1. It costs 57 bars at most (50 + a cell code + parity); while any watch on
  the source asks for it, that source's other bars are released and every other watch on it is answered from the exact
  value. At a step above 1 (a max over 3175) a point that is not a multiple of the step, and an edge whose cut is not,
  keeps its own bar, so points and edges stay exact to the point; `h:Exact()` is to the step. A `step` watch beside it
  still reads one 1% cell: while one is there the source also runs the 8 position bars (cut on whole points, so they
  agree with the exact value), and a cell that does not meet the exact value is held a frame, then primes again, as any
  disagreement. A `step` watch joining or leaving such a source primes it again (about 9 frames unknown). At step 1 the
  exact value already gives the cell: no extra bars run (admission still counts them: the max can grow past 3175).
  Should the client refuse a ring curve at a max, the precision watch is `suspended` there and the source's other
  watches keep their bars (a `step` watch reads the 8 position bars). A max of 100 or less is the same as `step` (8
  bars, exact). It is outside the point caps but inside the 256-bar pool, with every edge and point on the source
  counted (the step can grow with the max) and the 8 position bars when a `step` watch is there: over it, `pool-limit`. Any `step` watch is admitted the same way
  (counted, or refused with `pool-limit`), as a points or precision watch is; one joining a precision source counts the
  8 position bars.
- Confirmation (`step` and `precision`, one rule for every such source): every change of the value, and the first value
  after a prime, is held until the next frame's decode gives the same value (one frame, about 16 ms at 60 fps). Half of
  a change whose firings land over two frames is a valid state the client never held (another 1% cell, 84 for 85; whole
  ring cells off, 1200 for 1250; or a value partway through a change of several steps); with every push's firings
  landing within two frames the rest of them lands before the next decode, so such a state is not confirmed: no value
  the client did not hold is reported (fake runs with each firing 1-2 frames late: none in 45 minutes of mana and 15 of
  energy regen and spending). Named exceptions: a change undone on the next frame whose late halves cancel bar for bar
  rebuilds the same half state and confirms it (for mana a spend and a regen tick undoing each other across a cell,
  1249 -> 1250 -> 1249 read 1200: rare, never seen in the fake runs; pinned in `precision_spec`); firings later than
  two frames can still confirm a half-landed state (in 15 minutes with firings 1-3 frames late: 53-65 calls on mana,
  15 on energy). A value that moves one way on every frame is never confirmed: the source holds six frames, primes
  again and repeats, and every watch on that source reads unknown with it until the changes slow, edges-only watches
  included, another addon's too (bars are shared): a `step` watch on a target losing 1% a frame, dead in under about
  1.7 s at 60 fps. With each firing 1-2 frames late a cell every two frames already loses about half its calls to
  desyncs (fake: 50 calls for 99 cells, 3 desyncs; a target dead in about 3.3 s at 60 fps, 6.6 s at 30; without
  the confirmation: 1 and 0 desyncs, with it 6 at a cell a frame and 3 at a cell every two frames); a cell every three frames is
  clean. A value alternating on every frame (35, 36, 35, ...) comes back to the held value every other decode: it
  never desyncs and reads the held value until it settles. An in-game
  run (2026-11-21, mana regenerating 2-3 points at a time) saw about one change in four split over two frames.

`power` has no default: the displayed power changes with a form, and a handle must not change what it measures. Every
other kind, token or option (focus or another power type, `points` or `precision` on health, the `focus` token, ...)
returns a handle whose state is `"unavailable", "unproven"`: write against it now, it comes alive when that is
built.

## Error codes

`Watch` and `h:SetPoints` refuse with `nil, code`; codes are plain strings in
`LHV.ERR`. Map them yourself,
or show `LHV:GetMessage(code)`: the text in the client's locale (or the one you pass), `nil` for a locale the library
has no text for yet (enUS only for now). `GetMessage` also knows every state and reason.

| Constant | Code | When |
|---|---|---|
| `OWNER_INVALID` | `owner-invalid` | owner not a string |
| `SPEC_INVALID` | `spec-invalid` | spec not a table |
| `SINK_INVALID` | `sink-invalid` | sink neither a function nor nil |
| `KIND_INVALID` | `kind-invalid` | no kind, or not one of the major's |
| `UNIT_INVALID` | `unit-invalid` | unit missing or not a token |
| `EDGES_INVALID` | `edges-invalid` | edges not a list of numbers (aura stacks: of whole numbers) |
| `EDGES_OUT_OF_RANGE` | `edges-out-of-range` | an edge outside (0.05, 100]; aura stacks outside 1 to `max`, aura seconds 0.01 or less |
| `EDGES_REQUIRED` | `edges-required` | none of edges, step, points, precision; aura stacks without edges or `max`, aura seconds without edges |
| `STEP_INVALID` | `step-invalid` | step not a positive number |
| `POWER_REQUIRED` | `power-required` | a power watch without `power` |
| `POWER_INVALID` | `power-invalid` | `power` not a number |
| `POINTS_INVALID` | `points-invalid` | points not a list of whole numbers >= 1; `SetPoints` on a percent handle |
| `EDGE_LIMIT` | `edge-limit` | over the point caps |
| `POOL_LIMIT` | `pool-limit` | points, precision or step over the 256-bar pool |
| `PRECISION_INVALID` | `precision-invalid` | precision other than `"point"` |
| `SPELL_INVALID` | `spell-invalid` | aura: spell not a whole number above 0 |
| `SPELL_OR_COOLDOWN` | `spell-or-cooldown` | aura: both `spell` and `cooldown`, or neither |
| `COOLDOWN_INVALID` | `cooldown-invalid` | aura: cooldown not a whole number above 0 |
| `WHAT_INVALID` | `what-invalid` | aura: what not `"up"`, `"stacks"` or `"left"` |
| `MAX_INVALID` | `max-invalid` | aura: max not a whole number of 1 or more |

## Auras (from the Cooldown Manager)

The client hides aura data from addons in combat, but its Cooldown Manager still shows the auras the player placed
there. The `aura` kind reads those items. It never changes the player's Cooldown Manager (nothing is
shown, hidden, faded, moved or re-laid out; it only post-hooks the items' own updates), so it can only serve what the
player placed. It attaches to nothing there until you watch an aura (below).

```lua
-- Stacks of a debuff on the target (bands 0-2, 2-4, 4+), and whether a buff of mine is up.
LHV:Watch("MyAddon", { kind = "aura", unit = "target", spell = 12345, what = "stacks", edges = { 2, 4 } }, sink)
LHV:Watch("MyAddon", { kind = "aura", unit = "player", spell = 67890, what = "up" }, sink)
-- The same, on the one Cooldown Manager entry you chose (LHV:GetAuraEntries lists them).
LHV:Watch("MyAddon", { kind = "aura", unit = "player", cooldown = 1234, what = "up" }, sink)
```

| Field | Meaning |
|---|---|
| `unit` | `"player"` or `"target"` (the only units the Cooldown Manager reads; another token is `unavailable, unproven`) |
| `spell` | the aura's spell ID, a convenience: the library's own rule picks the entry, an assumption about which one you mean. To choose yourself, list the entries with `LHV:GetAuraEntries(spell)` and watch one with `cooldown =`. The rule: of the entries naming the spell (as their spell, override, tooltip override or a linked spell) that an item shows now, the one on the highest viewer (Tracked Bar, Tracked Buff icon, Essential, Utility); on one viewer, the first in catalogue order (category 0 to 8, then the client's order). The watch answers for that entry: whatever aura of it the client shows (a sibling linked aura reads as this one) |
| `cooldown` | instead of `spell` (exactly one of the two): a Cooldown Manager cooldownID. The watch follows that entry only, wherever it is placed; the reasons are the same. `LHV:GetAuraEntries(spell)` lists the entries with the client's facts so you choose |
| `what` | `"up"`: presence, `lo == hi`, 1 up and 0 not. `"stacks"`: the stack count. `"left"`: seconds left |
| `edges` | `stacks`: whole numbers from 1 (1 has no bar: told only by the aura being absent, see below); `left`: seconds above 0.01 (required) |
| `max` | `stacks` only: the top of the domain; alone it means every count from 1 to `max`: exact from 2 up, `[0, 2)` while up with no count shown. `max = 1` tells nothing beyond `up` (`[0, 1]` up or absent alike) |

The library reports what the Cooldown Manager shows: anything the item cannot tell is unknown. `up` 0 (with no stacks
and no seconds, the lowest band: `0` to the lowest edge) means the item holds no aura of yours now: the item's reading,
not proof that the aura is absent. Measured limits: the Cooldown Manager shows only auras the player cast, and on the
player only helpful ones, so a partner's debuff reads 0; and an item stayed silent a whole fight while its aura
was up (Mark of the Wild). After a target change every target watch whose item has not lit on the target since
is unknown (`gone`) until it does (lit on the player or on a secret unit does not count) or the client sends the new
target's auras (a target `UNIT_AURA`): the client shows a new target's auras only once their update arrives (a Tracked
Buffs icon stayed dark 0.4-0.6 s on a mob that had the aura), and an Essential or Utility item looks at the new target
only when it held a target aura. Stacks and seconds watches are unknown with it; a cleared target stays unknown until a
target `UNIT_AURA`. A handle is unknown (`lo == nil`, `gone`)
while no item shows it, while its viewer is hidden or in Edit Mode (or either reads secret), and while its item holds
the aura on a unit the client keeps secret, names no unit, or names the other unit (a player watch whose entry shows the
target's aura is unknown, not 0: a watch on each unit of one entry reads unknown on one of them while the aura is up on
the other); before its first band it is `priming`. `"live"` always comes with a band. The client shows no count at 0 or
1 stack (a non-stacking aura shows none): an aura that is up with no count reads 0 to the lowest stacks edge above 1
(`[0, 2)` with `max`, `[0, 3)` with edges `{ 3 }`: no bar at 2), never 1; stacks edge 1 is told only by the item holding
none. `left` is the tracked bar's value: an aura with no duration has a bar at 0 and reads the lowest band while it is
up, which looks like "about to expire": watch `up` for such auras.
`h:Domain()` returns `nil, 0, top`: 1 for `up`, `max` (or `math.huge`) for stacks, `math.huge` for seconds.
`h:Latency()` is the worst case from the Cooldown Manager's update to the call (its own delay is not counted): `up`
2 frames; `stacks` `LHV.SETTLE + 1` (5); `left` `LHV.HOLD + LHV.SETTLE + 3` (11: a refresh as the seconds fall
through an edge; a plain fall through an edge is told within 2). When an aura comes back, `up` reads 1 at once while
`stacks` and `left` keep the absent band for about `LHV.SETTLE` frames: read each handle on its own, or allow
`h:Latency()` after `up` flips before combining them (a fresh application would otherwise read as about to expire).
`stacks` keeps it only while a count settles: when the aura came up and the bars took no count (a new watch's or a
re-layout's bars hold low 4 frames; the item was placed for the watch only after; the client bound the aura after
writing the count), it is unknown until the client next writes the count. That can be for long, and where the count
was below the lowest edge the absent band would have been true: with no further count it lasts the aura's life.

When a watch moves to another entry (the spell's other entry now ranks first), nothing of the entry it left is kept:
`up` is unknown for a frame, `left` until its bars settle, `stacks` until the client next writes that entry's count,
also when the count is the same. The same entry on another viewer keeps its answer.

A Tracked Buffs icon whose aura runs out with no aura event can show a linked aura and write no count of it: `stacks`
is then unknown until the client next writes that icon's count (seen through the icon's `MarkDirty`, which the client
calls when the linked spell changed). Known limit: an icon that binds the linked spell it already had calls nothing,
and the band is the count of the aura before it until the client refreshes that item.

After a target change, expect a target aura watch to read unknown on a mob that has the aura until its item lights
or that target's `UNIT_AURA` arrives. A mob whose auras do not change sends neither: 0.8 to 6.4 seconds were measured
in game.

What each placement gives (the player chooses it in the Cooldown Manager's settings):

| Placement | `up` | `stacks` | `left` |
|---|---|---|---|
| Tracked Bar | yes | yes | yes |
| Tracked Buff icon | yes | yes | no: `unavailable, cdm-icon-only` |
| Essential or Utility (a cooldown whose aura it binds) | yes | no: `unavailable, cdm-cooldown-only` | no: the same |
| a hidden category, or nowhere | no | no | no |

`up` uses no bar, so the bar self-test does not gate it: an `up` watch is `ready` while the self-test is pending or
has failed (`selftest`), and goes unavailable only for `api`, `off`, `error` or `cdm-off`. `stacks` and `left` wait
for the self-test like every bar. The kind's own answer (`IsAvailable("aura")`, `GetKinds`, `fn("aura", state,
reason)`) describes the bars; ask with the whole spec, or read `h:State()`, for an `up` watch.

`LHV:IsAvailable("aura", spec)` (the whole spec, without a watch) and `h:State()` answer `ready`, `pending` (not read
yet, or an item on screen the catalogue does not hold: below) or `unavailable` with one of these reasons:

| Reason | Meaning | What the player can do |
|---|---|---|
| `cdm-off` | the Cooldown Manager is switched off (Options), the client says it is not available, or its viewers are missing | switch it on |
| `not-in-cdm` | no Cooldown Manager entry names this spell (or has this cooldownID) | nothing: the client cannot track it there |
| `cdm-not-tracked` | an entry names it (or the entry exists), but no item of the four viewers shows it | place it in Tracked Buffs, or Tracked Bars for its timer |
| `cdm-icon-only` | `what = "left"` on an aura shown as an icon | move it to Tracked Bars |
| `cdm-cooldown-only` | `stacks` or `left` on an aura shown only by an Essential or Utility item | place its aura entry in Tracked Buffs or Tracked Bars |
| `bad-spec` | (`IsAvailable` only) a spec `Watch` would refuse; `Watch` returns its error code | nothing: fix the spec |

The library only reports: telling the player is your addon's choice. `LHV:OnCapability(owner, fn)` calls
`fn("aura", state, reason)` when the kind changes (`cdm-off`) and `fn("aura", state, reason, h)` for each of your aura
handles whose answer changed (the player placed or removed the aura, a layout change). A handle is `gone` (unknown)
while its item cannot be read: its viewer hidden (Edit Mode "Hidden", or the whole UI hidden), Edit Mode open, or an
item whose `cooldownID` the client keeps secret (which entry it shows is not known; until the next layout or data pass
finds it plain).

### When the library attaches to the Cooldown Manager

The hooks go in on first use: the first `Watch` of an aura on `player` or `target` installs them (after login: one
made earlier installs them on the first frame) and reads the items already on screen, in combat too. It sees nothing
from before that: a target aura can be in a swap's doubt, and stacks wait for the next count. The hooks stay for the session (a hook cannot be removed), also after the watch is released. With no aura watch, health
and power watches included, nothing is hooked and no item is read (the getters below read them when called).

The catalogue (which entries exist and the spells they name) is not a hook and is kept known with no watch, read out
of combat only, as by minor 7: at login, on the events that can change it (`COOLDOWN_VIEWER_DATA_LOADED`,
`COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`, `COOLDOWN_VIEWER_TABLE_HOTFIXED`, `PLAYER_LEVEL_CHANGED`, `SPELLS_CHANGED`,
`PLAYER_EQUIPMENT_CHANGED`, `PLAYER_PVP_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED`,
`ACTIVE_PLAYER_SPECIALIZATION_CHANGED`, `ACTIVE_COMBAT_CONFIG_CHANGED`, `ACTIVE_TALENT_GROUP_CHANGED`), when combat
ends if one came during it, and with a watch whenever the items are read again out of combat. In combat the list from
before the fight answers every watch and getter, so a change made during a fight is seen when it ends. An item on
screen whose entry that list does not hold, met by the first watch or by a getter with no watch, makes new answers
wait until the next read: a watch and `IsAvailable` with a spec say `pending` and `GetAuraEntries` says not read,
never a 0 or a `not-in-cdm`.

| Call | Hooks | Cooldown Manager work with no aura watch |
|---|---|---|
| `Watch` of an aura on `player` or `target` | installs them, each once: two per viewer (`OnAcquireItemFrame`, `RefreshData`), two per Tracked Bar item (the count's `SetText`, the bar's `SetValue`), two per Tracked Buffs icon (the count's `SetText`, the item's `MarkDirty`), none per Essential or Utility item | (it is the first use: the items are read, in combat too) |
| `Watch` refused, of another unit, or of another kind | none | none |
| none (login and the events) | none | on or off, and the catalogue as above |
| `IsAvailable("aura")`, `GetKinds`, `OnCapability` | none | none of their own |
| `IsAvailable("aura", spec)`, `GetAuraEntries` | none | reads the items when called, and out of combat a catalogue an event left old |
| `GetAuraSources`, the other getters | none | none (`read`: the catalogue was read at least once) |

With no watch, the kind's `cdm-off` that ends without an event stays until the next event or combat end: a `Watch`
reads again, so watch rather than wait for `ready`. Viewers that appear after a watch are hooked at the next event the
library listens to.

Until the catalogue was read once (after a login or reload in combat, until that fight ends; or the Cooldown Manager off
since), `IsAvailable` with a spec and `GetAuraEntries` say not read (`pending`; `read` false). While an item's `cooldownID`
reads secret, which entry it shows cannot be told: a new watch (one watched again too), and `IsAvailable` with a spec, say `pending` where
that item could be the entry that ranks first or the only one, and a watch that answered keeps its answer (its own
item secret: `gone`).

A bar is read 4 frames (`LHV.SETTLE`) after the client's first push into it, so the first band of a new watch is the
pushed value's, once, with dir 0. A handle that joins another's live watch starts from that watch's last frame: its
first band can be one frame old. A stacks watch started while its aura is already up stays `priming` until the client next writes the
count (an application, a refresh, a target swap); after a re-layout (UI scale, a loading screen) an aura handle is
unknown until its bars settle again. When an aura comes back the band before it stands while the count settles (a
count the bars took: with none, a stacks watch is unknown). A
refresh within a frame of a seconds edge can be told up to 11 frames late (`h:Latency()`; the band before it stands
meanwhile). `OnCapability` is not called from inside `Watch` or `IsAvailable`: read `h:State()` there (an answer
`IsAvailable` gives may be a frame old; the callbacks follow on the next frame). A paused aura handle only reports
unknown; its bars keep following the client.

## The self-test

At login, and on `LHV:SelfTest()`, invisible bars are pushed known values for about 45 frames, and one more bar is
primed from the player's health. A pass requires that this prime was fed a secret: the player's health reads secret in
and out of combat on the live client (measured 2026-11-22), so a plain or nil read there is no pass, and the kinds
that rest on bars stay `unavailable, selftest`.

A pass proves that the bars fire, that the curves follow the library's convention, and that a secret moved a bar whose
firing arrived in time. It does not check the values behind secrets. Its limit: a client change that stops those
firings after a run is seen at the next `SelfTest` or login, not before; until then bands can be stale.

A copy that takes over from a minor before 8 after login does not keep that copy's verdict: it is `pending` while it
runs the test again, and a stacks watch stays unknown until its next count change.

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

The self-test passes there only on a secret health read (`W.secret`, the default): a test that wants plain reads
turns it off after `Fake.login()`.

Its header lists the world fields (`max` per power type for `points` and `precision`), the fault knobs (`closed`,
`lag`, `secretlag`, `drop`, `stagger`, `jitter`, `seed`, `snap`, `maxpoints`, `refuse`) and what it does not model. It
also models the Cooldown Manager (`W.cdm`, `W.aura`, `Fake.setAura`, `Fake.cdmLayout`, `Fake.cdmEnable`; a target's
auras arriving late after a swap: `W.cdm.lateSwap`): see the comment above its viewers.

## Diagnostics

Diagnostics are a consumer's job: the library prints nothing (an error goes to the client's error handler), registers
no slash command and shows no frame of its own. The calls below answer everything a diagnostic tool needs.

| Call | Returns |
|---|---|
| `LHV:GetVersion()` | `major, minor` (`"LibHiddenValues-1.0", 8`) |
| `LHV:GetKinds()` | a fresh array, one `{ kind =, state =, reason = }` per kind of the major, in contract order (`health`, `power`, `cooldown` ... `aura` ... `meter`: the major's twelve); `state` and `reason` as `IsAvailable` |
| `LHV:IsAvailable(kind, unit)` | `ok, state, reason` (`state` `"ready"`, `"pending"` or `"unavailable"`; `reason` nil unless unavailable). `unit` may be a whole spec: the aura kind then answers for its placement |
| `LHV:OnCapability(owner, fn)` | nothing; `fn(kind, state, reason)` on each change, and `fn("aura", state, reason, h)` for each of the owner's aura handles whose answer changed |
| `LHV:GetAuraSources()` | a fresh array, one `{ unit =, spell =, cooldown =, what =, handles =, bars =, active =, cooldownID =, placement =, state =, reason =, up = }` per aura source with a watch (`cooldown` the entry a watch by entry names, else nil; `cooldownID` the entry read now; `placement` `"bar"`, `"icon"`, `"essential"`, `"utility"` or nil; `up` true, false or nil for unknown); then `off, read, texts, values, refused, reads`: the Cooldown Manager is off, its catalogue was read, count texts and bar values forwarded, values a bar refused, item reads |
| `LHV:GetAuraEntries(spell)` | a fresh array, one `{ cooldownID =, spellID =, overrideSpellID =, overrideTooltipSpellID =, linkedSpellIDs = { ... }, hasAura =, selfAura =, category =, placement = }` per Cooldown Manager entry naming the spell (as its spell, override, tooltip override or a linked spell), in catalogue order: the client's plain facts from the last catalogue read (`hasAura` and `selfAura` the client's booleans as given, nil when not plain; the library does not filter on them; `category` the default one; `placement` as in `GetAuraSources`, nil when no item shows it); then `read` (the catalogue was read and holds every item on screen). Choose one and watch it with `cooldown =` |
| `LHV:GetStats()` | `bars, usFrame, usPeak, pushesPerSec, firesPerSec, desyncs, level, splits`: bars in use, average and peak µs per frame, pushes and firings per second, desyncs (a source whose bars contradicted each other, a lost firing: it primes again; a position or precision decode counts one only when still invalid on a frame with no new firing after an invalid one, or 4 in a row), governor level (0 for now), splits (a position decode held one frame). The frame times cover the library's whole frame, the self-test's frames included while it runs; with nothing fed the driver stops and every rate and time reads 0 |
| `LHV:GetPool()` | `made, cap, pointBars, pointCap, pointCapPerSource`: bars made (32 at login; frames are never destroyed), the cap (256), point bars in use, and the point caps (64, 8) |
| `LHV:GetSources()` | a fresh array, one `{ kind =, unit =, power =, predicted =, handles =, bars =, mode =, max =, active = }` per source with a watch, in creation order (`kind`, `unit`, `power`, `predicted` are the source's key: watches differing in any of them do not share bars; `power` nil for health; `mode` `"edges"`, `"gray"` (position) or `"ring"` (point precision); `max` the plain max a power source cuts points with; `active`: fed every frame) |
| `LHV:SelfTest(fn)` | nothing; runs the self-test (or joins the run going) and calls `fn(pass, lines)` when it ends: `pass` a boolean, `lines` an array of strings under 255 characters, the last one `selftest PASS ...` or `selftest FAIL ...`. Called at once (inside `SelfTest`) when it cannot run: the client lacks the API, switched off, or no free bar (an earlier verdict then stands; with none it is a FAIL). A run whose prime was not fed a secret is a FAIL. Before login it waits for the login run. The capability has already changed when `fn` runs: `IsAvailable` and the handles' `State()` show the new verdict. `lines` is shared: read it, do not change it |
| `LHV:GetSelfTest()` | `verdict, lines, running`: the last completed run's verdict (`true`/`false`) and its lines (the array `fn` got), both nil before the first run and again after `SetEnabled(true)` until the new run ends; and whether a run is going |
| `LHV:SetEnabled(on)` | nothing. `false`: every kind `unavailable, off` for this session. `true` after `false`: pending until a fresh self-test passes (it starts one). Already on, it changes nothing: after a failed self-test, `LHV:SelfTest(fn)` runs it again and the kinds come back when it passes |

`GetKinds`, `GetSources`, `GetAuraSources` and `GetSelfTest` build or hand out tables: call them from a command, not every frame.

## Credits

The technique of reading a hidden value's thresholds back from a status bar's fill has prior public use in other
Forever addons; this library is written from its authors' own probes.
