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
  one frame later, with the net band (a jump over three edges is one call); on a `step` or `precision` source up to
  two frames later (a split holds the decode a frame). `h:Latency()` gives the worst case in seconds.
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
| `power` | `unit`, `power` (`Enum.PowerType`, required), `edges`, `step`, `points`, `precision` | `player`: mana, energy, rage (rage: proven by the BandProbe2 warm-up, the library's own run owed) |
| `aura` | `unit`, `spell` or `cooldown`, `what`, `edges`, `max` | `player`, `target`: read from the Cooldown Manager, **not yet run in game** (below) |

A spec needs at least one of `edges`, `step`, `points` or `precision`.

- `edges`: thresholds in percent, (0.05, 100].
- `step`: position. Any step is granted as 1: the band is the 1% cell (`lo`, `lo + 1`), `h:Domain()` returns step 1.
  Beside `edges` the band is cut by both (an edge on the 1% grid costs no bar). The source runs 8 bars (a Gray code
  and a parity bar) while any watch on it asks for a step. A jump of any size is one call, one frame later (two when
  one change's firings split over two frames).
- `points` (player power): whole-number thresholds in the value's own units, e.g. `{ 40, 60 }` energy. A handle with
  `points` (even `{}`) answers in points: `lo`, `hi` and `h:Domain()` (0 to the player's plain max) are in points.
  The cut is `points / max`; it moves with the max (`UNIT_MAXPOWER`: the handle goes unknown while it primes again).
  Identical points share a bar; a point on the 1% grid of a `step` source costs no bar. Caps (`GetPool`): 8 distinct
  points per source and 64 in total, each counted as if it needed a bar (a point answered without one while a `step`
  or `precision` watch is there needs one when that watch goes), checked when you ask; over either the whole request
  is refused (`edge-limit`), nothing granted. `h:SetPoints(list)` swaps a handle's points in one step: `true`, or
  `nil, code` with the old set kept. While the max was never read as a plain number the handle is `unavailable, max-unknown`.
- `precision = "point"` (player power): the exact value. `h:Exact()` returns `value, step` (value nil while unknown):
  step 1 up to a max of 3175, above it the step grows until every curve fits the client's 256-point limit (6400
  mana: step 3). `q` is `LHV.EXACT` (3) at step 1. It costs 57 bars at most (50 + a cell code + parity); while any
  watch on the source asks for it, that source's other bars are released and every other watch on it is answered
  from the exact value. At a step above 1 (a max over 3175) a point that is not a multiple of the step, and an edge
  whose cut is not, keeps its own bar, so points and edges stay exact to the point; `h:Exact()` is to the step. A
  `step` watch beside it still reads one 1% cell: while one is there the source also runs the 8 position bars (cut on
  whole points, so they agree with the exact value), and a cell that does not meet the exact value is held a frame,
  then primes again, as any disagreement. A `step` watch joining or leaving such a source primes it again (about 9
  frames unknown). At step 1 the exact value already gives the cell: no extra bars. A one-step change is
  never misread when its firings land within two frames: at a cell boundary (every 50 steps) the library holds one
  frame when only half of the change's bars have landed. A larger jump whose firings land in two frames can read as
  another value for that one frame, as on a `step` source; the probe runs saw no change split over two frames. A max
  of 100 or less is the same as `step` (8 bars, exact). It is outside the point caps but inside the 256-bar pool,
  with every edge and point on the source counted (the step can grow with the max) and the 8 position bars when a
  `step` watch is there: over it, `pool-limit`. A `step` watch is checked against the pool too.

`power` has no default: the displayed power changes with a form, and a handle must not change what it measures. Every
other kind, token or option (focus or another power type, `points` or `precision` on health, the `focus` token, ...)
returns a handle whose state is `"unavailable", "unproven"`: write against it now, it comes alive when its stage
ships.

## Error codes

`Watch`, `h:SetPoints` and the managed-layout calls (below) refuse with `nil, code`; codes are plain strings in
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
| `STORE_INVALID` | `store-invalid` | managed layout: store not a table |
| `CDM_COMBAT` | `cdm-combat` | managed layout: called in combat |
| `CDM_SLOTS` | `cdm-slots-full` | managing: the store holds 5 layouts already |
| `CDM_API` | `cdm-api` | managed layout: the client lacks the layout or encoding API (or its encoder failed the self-check) |
| `CDM_UNREADABLE` | `cdm-unreadable` | managed layout: the saved layouts cannot be read or decoded, are of a save version other than 5, or the player's class cannot be read; nothing is changed |
| `CDM_WRITE` | `cdm-write-failed` | managed layout: the write did not read back as written (the library tried to write back what was there; the saved original is kept) |
| `CDM_OWNER` | `cdm-owner` | managed layout: another addon's store holds the managed layout (or a restore of it not yet verified by a load) |
| `CDM_NOT_MANAGED` | `cdm-not-managed` | restoring: the store holds nothing to restore |
| `CDM_OFF` | `cdm-off` | managing: the Cooldown Manager is off |

## Auras (from the Cooldown Manager)

The client hides aura data from addons in combat, but its Cooldown Manager still shows the auras the player placed
there. The `aura` kind reads those items. By default (Mode A) it never changes the player's Cooldown Manager (nothing is
shown, hidden, faded, moved or re-laid out; it only post-hooks the items' own updates), so it can only serve what the
player placed. Mode B, the managed layout below, changes it only when your addon asks, with the player's consent.

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
| `spell` | the aura's spell ID, a convenience: the library picks the entry, which is an assumption. Of the entries naming the spell (as their spell, override, tooltip override or a linked spell) that an item shows now, the one on the highest viewer (Tracked Bar, Tracked Buff icon, Essential, Utility); on one viewer, the first in catalogue order (category 0 to 8, then the client's order). The watch answers for that entry: whatever aura of it the client shows (a sibling linked aura reads as this one) |
| `cooldown` | instead of `spell` (exactly one of the two): a Cooldown Manager cooldownID. The watch follows that entry only, wherever it is placed; the reasons are the same. `LHV:GetAuraEntries(spell)` lists the entries with the client's facts so you choose |
| `what` | `"up"`: presence, `lo == hi`, 1 up and 0 not. `"stacks"`: the stack count. `"left"`: seconds left |
| `edges` | `stacks`: whole numbers from 1 (1 is presence itself); `left`: seconds above 0.01 (required) |
| `max` | `stacks` only: the top of the domain; alone it means every count from 1 to `max` (an exact count) |

The library reports what the Cooldown Manager shows, never a guess: anything it cannot tell is unknown. An absent
aura (the item shows it not up) is a known value: no stacks and no seconds, the lowest band (`0` to the lowest edge),
`up` 0. A handle is unknown (`lo == nil`, `gone`) while no item shows it, while its viewer is hidden or in Edit Mode
(or either reads secret), and while its item holds the aura on a unit the client keeps secret, names no unit, or
names the other unit (a player watch whose entry shows the target's aura is unknown, not 0); before its first band it
is `priming`. `"live"` always comes with a band. The client shows no count at 0 or 1 stack (a non-stacking aura
shows none): an aura that is up with no count reads 0 to the lowest stacks edge above 1 (`[0, 2)` with `max`),
never 1; stacks edge 1 is told only by the aura being absent. `left` is the tracked bar's value: an aura with no
duration has a bar at 0 and reads the lowest band while it is up, which looks like "about to expire": watch `up` for
such auras.
`h:Domain()` returns `nil, 0, top`: 1 for `up`, `max` (or `math.huge`) for stacks, `math.huge` for seconds.
`h:Latency()` is the worst case from the Cooldown Manager's update to the call (its own delay is not counted): `up`
2 frames; `stacks` `LHV.SETTLE + 1` (5); `left` `LHV.HOLD + LHV.SETTLE + 3` (11: a refresh as the seconds fall
through an edge; a plain fall through an edge is told within 2). When an aura comes back, `up` reads 1 at once while
`stacks` and `left` keep the absent band for about `LHV.SETTLE` frames: read each handle on its own, or allow
`h:Latency()` after `up` flips before combining them (a fresh application would otherwise read as about to expire).

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
yet; also after a reload in combat, until combat ends) or `unavailable` with one of these reasons:

| Reason | Meaning | What the player can do |
|---|---|---|
| `cdm-off` | the Cooldown Manager is switched off (Options), the client says it is not available, or its viewers are missing | switch it on |
| `not-in-cdm` | no Cooldown Manager entry names this spell (or has this cooldownID) | nothing: the client cannot track it there |
| `cdm-not-tracked` | an entry names it, but no tracked buff icon or bar shows it | place it in Tracked Buffs, or Tracked Bars for its timer |
| `cdm-icon-only` | `what = "left"` on an aura shown as an icon | move it to Tracked Bars |
| `cdm-cooldown-only` | `stacks` or `left` on an aura shown only by an Essential or Utility item | place its aura entry in Tracked Buffs or Tracked Bars |
| `bad-spec` | (`IsAvailable` only) a spec `Watch` would refuse; `Watch` returns its error code | nothing: fix the spec |

The library only reports: telling the player is your addon's choice. `LHV:OnCapability(owner, fn)` calls
`fn("aura", state, reason)` when the kind changes (`cdm-off`) and `fn("aura", state, reason, h)` for each of your aura
handles whose answer changed (the player placed or removed the aura, a layout change). A handle is `gone` (unknown)
while its item cannot be read: its viewer hidden (Edit Mode "Hidden", or the whole UI hidden), Edit Mode open, or, in
combat after the client re-laid the items out, an item whose identity the client keeps secret (until combat ends).

A bar is read 4 frames (`LHV.SETTLE`) after the client's first push into it, so the first band is the true one, once,
with dir 0. A stacks watch started while its aura is already up stays `priming` until the client next writes the
count (an application, a refresh, a target swap); after a re-layout (UI scale, a loading screen) an aura handle is
unknown until its bars settle again. When an aura comes back the band before it stands while the count settles. A
refresh within a frame of a seconds edge can be told up to 11 frames late (`h:Latency()`; the band before it stands
meanwhile). `OnCapability` is not called from inside `Watch` or `IsAvailable`: read `h:State()` there (an answer
`IsAvailable` gives may be a frame old; the callbacks follow on the next frame). A paused aura handle only reports
unknown; its bars keep following the client.

## The managed layout (Mode B)

Mode A serves only what the player placed, and only a tracked bar gives seconds left. Mode B lets the library put every
aura your watches need on a tracked bar: it adds one layout of its own to the Cooldown Manager (named after your
`owner`, so pass your addon's name), a copy of the player's active layout with each watched aura's entry moved to
Tracked Bars (aura entries only: a spell's cooldown entry stays where it is), and makes it active. A reload finishes
it. While it is in use, the four Cooldown Manager viewers sit at alpha 0: their data keeps flowing to the library,
nothing shows and a hidden bar shows no tooltip (each viewer's own alpha is given back on restore). It is one layout
per character and uses one of the player's 5 layout slots. **Ask the player first** and never call it on your own:
it changes the player's Cooldown Manager.

The library has no SavedVariables. Your addon keeps a table in its `SavedVariablesPerCharacter` and hands it over:
the saved original layouts and the state across reloads live there. Its fields are the library's: persist it, never
edit it. Hand over the same persisted table at every load, never a fresh one: a table your SavedVariables do not keep
loses the saved original.

```lua
-- At every load, once your SavedVariables exist (ADDON_LOADED or PLAYER_LOGIN):
MyAddonCharDB.cdm = MyAddonCharDB.cdm or {}
LHV:SetCooldownManagerStore("MyAddon", MyAddonCharDB.cdm)

-- The player clicked "Let MyAddon manage it" (out of combat):
local ok, code = LHV:ManageCooldownManager("MyAddon", MyAddonCharDB.cdm)
if not ok then showError(LHV:GetMessage(code)) end
-- Show a Reload button while LHV:IsReloadPending() is true. Its OnClick calls ReloadUI() itself: the client blocks a
-- reload from a timer, and the library never reloads.
reloadButton:SetScript("OnClick", function() ReloadUI() end)

-- The player clicked "Restore my Cooldown Manager":
LHV:RestoreCooldownManager("MyAddon", MyAddonCharDB.cdm)
```

| Call | Returns |
|---|---|
| `LHV:SetCooldownManagerStore(owner, store)` | `true` or `nil, code`. Call it at every load; a store a manage left pending is checked after the reload |
| `LHV:ManageCooldownManager(owner, store)` | `true` or `nil, code`. Out of combat. Writes the layout (a reload pending), or rewrites only its own: a new aura watch needs a bar (`update`), or the player switched away (drift) and wants it back. Nothing changed: `true`, no write, no reload |
| `LHV:RestoreCooldownManager(owner, store)` | `true` or `nil, code`. Out of combat. Puts the player's layouts back and gives the viewers' alpha back at once |
| `LHV:IsReloadPending()` | `pending, what`: `true, "manage"` or `true, "restore"` while a write of this session waits for a reload; `false` |
| `LHV:GetCooldownManagerMode()` | `mode, reason` (below) |

| Mode | Reason | Meaning |
|---|---|---|
| `player` | nil | the player's own layout: Mode A, nothing hidden |
| `player` | `check-failed` | after the reload the client did not take the layout (not active, or a learned aura without its bar item) within 20 s out of combat (time in combat does not count); nothing hidden. Offer the restore |
| `player` | `restore-failed` | after a restore and its reload our layout is back (the client wrote its layouts over the restore); nothing hidden, the saved original is kept. Offer the restore again |
| `pending` | `reload` | a write of this session waits for the reload |
| `pending` | `checking` | after the reload, the check runs; also a load in combat while managed, until combat ends (nothing hidden meanwhile) |
| `managed` | nil | our layout is active and checked: the viewers are hidden |
| `managed` | `update` | as above, but a watched aura has no bar in it yet: offer an update (`ManageCooldownManager`, a reload) |
| `drift` | `switched` | the player made another layout active: the library reads it as in Mode A, never switches back by itself |
| `drift` | `deleted` | our layout is gone: deleted, edited by the player (it is theirs now), or a layout of the player took its id |
| `drift` | `cdm-off` | the Cooldown Manager is off |

`OnCapability` callbacks hear each mode change as `fn("cdm", mode, reason)` (`"cdm"` is not a kind: `IsAvailable`
knows nothing of it), on the frame after the call that caused it, never from inside an API call. The viewers are
hidden only in `managed`; a `pending` update over a managed layout stays hidden until its reload; `SetEnabled(false)`
and an error in the aura kind give them back. Each viewer's alpha is read again at every pass while hidden: one not at
0 (Edit Mode applied the player's opacity again) is noted and set to 0, and restore gives back the latest.

Our layout is recognised by its id, its name (your `owner`) and the exact content the library wrote, all kept in your
store; never by the id alone (the client gives a new layout the largest id + 1, so a layout the player makes after
deleting ours takes our id). A layout that fails any of the three is the player's: it reads `drift, deleted`, and
neither restore nor manage ever changes it (manage adds a new layout of ours instead). After an update, our content
from before it also counts as ours until a check passes (the client may write the layouts it loaded back over the
update); the check that passes adopts the content it found (an update the client undid reads `managed, update`). A
manage that finds none of ours saves the store as it is then as the original.

Restore, decided per case: nothing else changed in the store since the manage (structurally) writes the saved
original back byte for byte; the player changed something (edited, added or deleted another layout) removes only our
layout and makes the layout that was active before ours active again (if the player switched away from ours, their
choice stays; if that layout is gone, the default). Equal bytes are not written again. Before the reload of a manage,
restore is an undo: the store is back to what the client loaded, so no reload is pending (a manage whose write is
already gone from the store leaves nothing pending either). Restore after the reload needs one (`pending, reload`)
so the Cooldown Manager reads the player's layout again; the saved original stays in your store until the next load
shows our layout gone (else `player, restore-failed`). Restore refuses `cdm-unreadable` and changes nothing when the
store cannot be read or decoded, or is of another save version; the one exception is the exact string a failed write
of the library left: restore then starts from the readable store that write replaced (kept in your store, the
player's edits with it), or the saved original raw when none was kept. A manage that needs no reload (the store
already is what this session loaded) is checked in the same session.

Not covered: a store lost from your SavedVariables while our layout exists (the layout stays; the player deletes it
in the Cooldown Manager's settings, and a new manage adds another); a store saved by minor 4 before the layout's name
and content were kept (it reads `drift, deleted`; the player deletes that layout by hand); another addon writing the
layout store. Unproven in game: that the client keeps our layout's content unchanged when it saves the store again (a
layout switch in Cooldown Settings); if it does not, our layout reads `deleted` and a manage adds a second one.

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

Its header lists the world fields (`max` per power type for `points` and `precision`), the fault knobs (`closed`,
`lag`, `secretlag`, `drop`, `stagger`, `snap`, `maxpoints`, `refuse`) and what it does not model. It also models the
Cooldown Manager (`W.cdm`, `W.aura`, `Fake.setAura`, `Fake.cdmLayout`, `Fake.cdmEnable`): see the comment above its
viewers. For Mode B it models the layout store (`W.cdm.store`, `Fake.encodeLayouts`, `Fake.decodeLayouts`), the
reload (`ReloadUI()` or `Fake.reload()`: everything is built again, `Fake.onReload(Fake)` loads your addon again before
login) and the viewers' alpha: see the comment above `Fake.reload`.

## Diagnostics

Diagnostics are a consumer's job: the library prints nothing (an error goes to the client's error handler), registers
no slash command and shows no frame of its own. The calls below answer everything a diagnostic tool needs; LHVProbe is
the reference consumer (`/lhvp`).

| Call | Returns |
|---|---|
| `LHV:GetVersion()` | `major, minor` (`"LibHiddenValues-1.0", 4`) |
| `LHV:GetKinds()` | a fresh array, one `{ kind =, state =, reason = }` per kind of the major, in contract order (`health`, `power`, `cooldown` ... `aura` ... `meter`: the major's twelve); `state` and `reason` as `IsAvailable` |
| `LHV:IsAvailable(kind, unit)` | `ok, state, reason` (`state` `"ready"`, `"pending"` or `"unavailable"`; `reason` nil unless unavailable). `unit` may be a whole spec: the aura kind then answers for its placement |
| `LHV:OnCapability(owner, fn)` | nothing; `fn(kind, state, reason)` on each change, and `fn("aura", state, reason, h)` for each of the owner's aura handles whose answer changed; `fn("cdm", mode, reason)` when the managed-layout mode changes |
| `LHV:GetCooldownManagerMode()`, `LHV:IsReloadPending()` | the managed layout's mode and reason; a pending reload and what for (the managed layout, above) |
| `LHV:GetAuraSources()` | a fresh array, one `{ unit =, spell =, cooldown =, what =, handles =, bars =, active =, cooldownID =, placement =, state =, reason =, up = }` per aura source with a watch (`cooldown` the entry a watch by entry names, else nil; `cooldownID` the entry read now; `placement` `"bar"`, `"icon"`, `"essential"`, `"utility"` or nil; `up` true, false or nil for unknown); then `off, read, texts, values, refused, reads`: the Cooldown Manager is off, its catalogue was read, count texts and bar values forwarded, values a bar refused, item reads |
| `LHV:GetAuraEntries(spell)` | a fresh array, one `{ cooldownID =, spellID =, overrideSpellID =, overrideTooltipSpellID =, linkedSpellIDs = { ... }, category =, placement = }` per Cooldown Manager entry naming the spell (as its spell, override, tooltip override or a linked spell), in catalogue order: the client's plain facts from its out-of-combat read (`category` the default one; `placement` as in `GetAuraSources`, nil when no item shows it); then `read` (the catalogue was read). Choose one and watch it with `cooldown =` |
| `LHV:GetStats()` | `bars, usFrame, usPeak, pushesPerSec, firesPerSec, desyncs, level, splits`: bars in use, average and peak µs per frame, pushes and firings per second, desyncs, governor level (0 for now), splits (a position decode held one frame). The frame times cover the library's whole frame, the self-test's frames included while it runs; with nothing fed the driver stops and every rate and time reads 0 |
| `LHV:GetPool()` | `made, cap, pointBars, pointCap, pointCapPerSource`: bars made (32 at login; frames are never destroyed), the cap (256), point bars in use, and the point caps (64, 8) |
| `LHV:GetSources()` | a fresh array, one `{ kind =, unit =, power =, predicted =, handles =, bars =, mode =, max =, active = }` per source with a watch, in creation order (`kind`, `unit`, `power`, `predicted` are the source's key: watches differing in any of them do not share bars; `power` nil for health; `mode` `"edges"`, `"gray"` (position) or `"ring"` (point precision); `max` the plain max a power source cuts points with; `active`: fed every frame) |
| `LHV:SelfTest(fn)` | nothing; runs the self-test (or joins the run going) and calls `fn(pass, lines)` when it ends: `pass` a boolean, `lines` an array of strings under 255 characters, the last one `selftest PASS ...` or `selftest FAIL ...`. Called at once (inside `SelfTest`) when it cannot run: the client lacks the API, switched off, or no free bar (an earlier verdict then stands; with none it is a FAIL). Before login it waits for the login run. The capability has already changed when `fn` runs: `IsAvailable` and the handles' `State()` show the new verdict. `lines` is shared: read it, do not change it |
| `LHV:GetSelfTest()` | `verdict, lines, running`: the last completed run's verdict (`true`/`false`) and its lines (the array `fn` got), both nil before the first run and again after `SetEnabled(true)` until the new run ends; and whether a run is going |
| `LHV:SetEnabled(on)` | nothing. `false`: every kind `unavailable, off` for this session. `true` after `false`: pending until a fresh self-test passes (it starts one). Already on, it changes nothing: after a failed self-test, `LHV:SelfTest(fn)` runs it again and the kinds come back when it passes |

`GetKinds`, `GetSources`, `GetAuraSources` and `GetSelfTest` build or hand out tables: call them from a command, not every frame.

## Credits

The technique of reading a hidden value's thresholds back from a status bar's fill has prior public use in other
Forever addons; this library is written from its authors' own probes.
