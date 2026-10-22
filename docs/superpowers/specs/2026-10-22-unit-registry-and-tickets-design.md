# Unit registry and attribution tickets (design, 2026-10-22)

Status: DESIGNED. Binding authority for the implementation plan. Base: `origin/forever` 760c0b55.
Paths are under `src/Hekili/` unless they start with `src/Hekili_`, `tests/`, `tools/` or `docs/`.
Evidence: the Wrath captures of 2026-10-22 (capture a `wrath-5176-2026-10-22.log`, capture b
`wrath-5176-2026-10-22-b.log`, capture c `wrath-5176-2026-10-22-c-swap.log`, and the soft-targeting log, pasted and not
saved in full) and the replay of captures a and b through Rows (the F1-F7 analysis). Times in the captures are ms.

This spec builds one core feature in two parts: a unit registry (token to GUID, with lifetimes) that every
UNIT_COMBAT consumer reads, and a generic ticket model that attributes our own outcomes, melee and spells alike. It
folds in central fix 32 (the projectile flight window, docs/dev/gaps.md:54) and replaces the ad hoc token reads in
Rows, Attackers, Target, Casts and TargetHealth.

## 1. Problem and evidence

Forever gives addons no combat log. Rows are synthesised from `PLAYER_SWING`, our own `UNIT_SPELLCAST_*` (plain for the
player, secret spell IDs for other units) and `UNIT_COMBAT`, which is plain and victim-side: unit token, action, flag,
amount, school. It names no source and no spell. It fires once per token naming the victim: `target`, `nameplateN`,
`focus`, `targettarget`, and `softenemy` / `softinteract` only while Action Targeting is on (it is off by default on
Forever, and the soft events stop entirely when it is off).

What the captures show, and what the code does with it:

| # | Measured | Code today | Result |
|---|---|---|---|
| 1 | A projectile lands at success + distance / Speed. Wrath (Speed 20): five max-range lags 1483-1566 ms; 222-245 ms in melee (capture b) | Rows pairs a school-8 WOUND only within `SAME_FRAME` 0.05 s of the success (`Game/Events/Rows.lua:37`, `:458`), a school-1 WOUND within `CAST_WINDOW` 0.2 s (`:33`, `:497-499`) | 0 of 14 Wrath landings credited in the replay; no `SPELL_DAMAGE` row; `Obs.Crit` never fires for a projectile (`:506-510`) |
| 2 | A spell miss is `UNIT_COMBAT` MISS, amount 0, school 1 (capture b, 783 ms after its success) | MISS is in `REFUSED` (`:159`) and treated as white (`:453`); past the landing window it is background and raises `bg[7]` (`:414-417`) | a late miss narrows every cast's avoid claim for about 30 s (GAP AX, `:49`, `:459-461`) |
| 3 | A cast keeps the target it was SENT to. Capture c: target swapped at 215719 during a cast; its landing at 216184 came on `nameplate1` only | Rows pins `actDst = UnitGUID("target")` at SUCCEEDED (`:362`) and never checks it; it reads only the `target` token (`:444`) | after a swap the pin is the new mob; a plate-only landing is never seen |
| 4 | A kill: our in-progress cast gets FAILED then STOP in the same ms, the target clears to none about 3 ms later, and the killing blow's `UNIT_COMBAT` arrives 11-36 ms after the clear, sometimes on `nameplateN` + `softinteract` only (capture b 42067, 74805; capture c 219922) | no consumer reads a token other than `target`; poll 4's `UnitIsDead("target")` (`Game/State/Sources/Target.lua:80-89`) never sees the kill because the target is already gone | the killing blow is lost; `TargetGone` never fires on a kill |
| 5 | Plates churn: the same mob's plate is removed and re-added within about 0.5 s while looking around; `NAME_PLATE_UNIT_REMOVED` still resolves name and GUID | Attackers clears its token on removal (`Game/Events/Attackers.lua:110-115`); no one keys by GUID across tokens | GUID is the identity; tokens are transient |
| 6 | Every player cast event is echoed on `targettarget` while the mob targets us (same castGUID, another castBarID) | the cast sources register `player` only (`Game/Events/EventFacade.lua:56-96` registers per unit; `Game/State/Sources/Casts.lua:31-92` checks `unit == "player"`) | harmless today; the registry must not treat `targettarget` rows as a new victim |
| 7 | A melee killing blow lands after the clear: Rogue capture, swing at 10283, `TARGET none` at 10384, `NAME_PLATE_UNIT_REMOVED` resolving the GUID at 10653, the CRITICAL row at 10754 on `softinteract` only (the corpse), with Action Targeting off | the same `target`-only reads as row 4 | a fixed 0.1 s grace after the clear would lose it (370 ms) |
| 8 | A school-32 WOUND on the target in the same ms as a HEAL on the player (a life-steal proc, Rogue capture 8799), between our swing (8682) and its white hit (9154). The kill-events capture shows the order: the proc fires 1 ms after `PLAYER_SWING` (2764 to 2765), before the swing's own row; a swing-time proc row precedes the swing's own row | a school-1 gate already guards swings (`Rows.lua:481`) | the school check must and does leave it foreign, or it would pay the swing ticket before the white hit arrives; this is why the gate exists for melee too |
| 9 | An instant strike's row comes in its frame: Sinister Strike's WOUND 8 arrived 2 ms after its SUCCEEDED (second Rogue capture: 2248 to 2250; the first strike's at 0 ms, 630) | FRAME's `SAME_FRAME` 0.05 s (`Rows.lua:37`) | the `"instant"` kind's frame window holds |
| 10 | An instant kill clears after its row: Eviscerate's killing blow (WOUND 14) arrived 1 ms after its SUCCEEDED (3500), and `TARGET none` came 101 ms after the row (3602) | as row 4 | the opposite order to a white-swing kill (row 7), which clears before its row |

The replay shows the cost: every own Wrath outcome goes to `background()` (`Rows.lua:517-519`), every success emits
only `SPELL_CAST_SUCCESS` and the aura rows, and a dead mob's modelled debuff expires 16 s after its death because no
`TargetGone` fires.

## 2. Unit registry

A new source file, `Game/State/Sources/Units.lua`, loaded right after `Game/State/Sources/Sources.lua` in
`Hekili.toc` (line 31) so every consumer can register with it at load. It is the only code that turns a unit token
into a GUID for the purpose of attribution. It owns no beliefs.

### 2.1 Data (fixed-size pools)

Tokens have integer indices fixed at load. The order matches Attackers' `TOKENS` today (`Attackers.lua:31-37`) so
Attackers keeps its own per-token arrays.

| Index | Token | Binding events |
|---|---|---|
| 1 | `target` | `PLAYER_TARGET_CHANGED` |
| 2 | `focus` | `PLAYER_FOCUS_CHANGED` |
| 3-42 | `nameplate1` .. `nameplate40` | `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED` |
| 43 | `softenemy` | `PLAYER_SOFT_ENEMY_CHANGED` (opportunistic) |
| 44 | `softinteract` | `PLAYER_SOFT_INTERACT_CHANGED` (opportunistic) |

`player` is not in the table: hits on us stay with `Game/State/Sources/Player.lua:166-188` and `Attackers.lua:198-288`,
which read the `player` token as today. `targettarget`, `partyN`, `raidN` and `mouseover` rows are ignored by the
registry: on Forever they are echoes of a row that also arrives on a table token, or rows about friends.

Per token index `i` (44 entries, built at load): `tokUid[i]` (the unit slot bound now, 0 none), `tokPrev[i]` (the slot
bound before the last change), `tokAt[i]` (the time of the last change).

Per unit slot `u` (`UNIT_CAP` = 64 entries, built at load): `uGUID[u]` (plain string, "" free), `uState[u]`, `uTokens[u]`
(the number of table tokens bound to it), `uSeen[u]` (last time any token named it or a row resolved to it),
`uLeft[u]` (the time its last token left), `uHeld[u]` (the number of open tickets pinned to it, kept by the ticket
pool on open and close) and `uFree[u]` (the time its last pinned ticket closed). The unit is released at the later of
`uLeft` and `uFree` once `uTokens` and `uHeld` are both 0.

| State | Value | Meaning | Rows resolve to it |
|---|---|---|---|
| FREE | 0 | slot unused | no |
| LIVE | 1 | at least one token bound | yes |
| GRACE | 2 | no token bound, and held (an open ticket pins it) or released less than `GRACE` ago | yes |
| GONE | 3 | no token bound, not held, released `GRACE` or more ago | no |
| DEAD | 4 | a death event, the fallback kill tell or a plain `UnitIsDead` named it | yes, while held and for `GRACE` after release |

Dedupe memory: the last `DUP_N` = 4 outcome groups (`dT`, `dUid`, `dAct`, `dFlag`, `dAmount`, `dSchool`), a ring.
Each entry also records the tokens already seen in its group: a fixed boolean array `dTok[(e - 1) x 44 + i]` over the
44 token indices (176 booleans, built at load; a new group clears its 44). `targettarget` needs no bit: the registry
never dispatches its rows (2.1).

All arrays are filled at load. Event handlers write numbers, booleans and the plain GUID strings the client handed
them. No table, closure or string is made after load.

### 2.2 Events consumed

| Event | Handler | Note |
|---|---|---|
| `PLAYER_TARGET_CHANGED` | rebind token 1 from `Plain(api, api.UnitGUID("target"))` | today read by `Target.lua:55` and `Attackers.lua:116-121`; both take it from the registry instead |
| `PLAYER_FOCUS_CHANGED` | rebind token 2 | |
| `NAME_PLATE_UNIT_ADDED` | rebind the plate's index from its live GUID | |
| `NAME_PLATE_UNIT_REMOVED` | unbind the plate's index; if the live read still answers (soft-targeting log: it does), check it equals the bound GUID first | a mismatch rebinds to the read GUID, then unbinds |
| `PLAYER_SOFT_ENEMY_CHANGED`, `PLAYER_SOFT_INTERACT_CHANGED` | rebind 43 / 44 | registered through `S.On`; a client that refuses them leaves them in `E.STUB` (`EventFacade.lua:93-95`) and nothing depends on them. `softinteract` rows exist with Action Targeting off (the corpse after a kill, Rogue capture 10754), so the token set keeps it; only the soft-enemy events depend on the setting |
| `UNIT_COMBAT` | resolve, dedupe, dispatch (2.4) | the one non-player `UNIT_COMBAT` entry point |
| `UNIT_DIED` | marks the unit holding the plain victim GUID DEAD at once (the primary kill tell, 2.5) | measured (kill-events capture): fires 2 ms after the killing swing, plain GUID; also fires for nearby units killed by others, so any known unit can be marked |
| `PARTY_KILL` | with killer equal to our GUID (`I.Log.player`, read once at load and on `PLAYER_ENTERING_WORLD`, `Casts.lua:17-21`), marks the victim's unit as our kill (`uOurs[u]`) | measured: fires in the same ms as the killing `PLAYER_SWING`, both GUIDs plain |
| `PLAYER_TARGET_DIED` | marks the current target's unit DEAD when `UNIT_DIED` has not | measured: same ms as `UNIT_DIED` |
| `UNIT_SPELLCAST_FAILED` (`player`) | records `failT` for the fallback kill tell (2.5) | any castGUID, including `Cast-2-0-0-0` key spam; used only when the client refused the death events |
| `PLAYER_REGEN_ENABLED` | reset (2.5) | |

Every payload slot reaches these handlers through `Plain` already (`EventFacade.lua:221-226`, `Game/State/Sources/Sources.lua:18-23`).
Every `UnitGUID` and `UnitIsDead` read the registry makes goes through `Plain` as well, and a nil answer means "no
answer", never a value.

### 2.3 Token to GUID resolution

`I.Units.Resolve(api, i, t)` answers the GUID a row on token index `i` at time `t` is about, and its unit slot. Order:

1. Live read: `g = Plain(api, api.UnitGUID(TOKENS[i]))`. A plain string is the answer. If it differs from the token's
   binding, the registry rebinds the token first (it heals a missed event).
2. Registry fallback while held: the live read is nil (no unit; `UnitGUID` on plate, target and soft tokens is plain in
   combat, probe U5, so nil means the token names no unit, and the `Plain` gate stays only as the secret-safety rule) and the token's previous slot is not GONE
   (it is held by an open ticket, or released less than `GRACE` ago): answer the previous slot. This is the post-clear
   killing blow (capture b 42067 on `target` after `TARGET none` at 42048; the Rogue capture's 10754 on
   `softinteract`, 370 ms after the clear).
3. Otherwise nil: the row is unresolved, counted (`U.unresolved`), and no consumer sees it.

A token rebound to a different live GUID while its previous slot is not GONE is the swap case. The live read wins
(rule 1), with two exceptions. First, the row resolves to the old unit when its payload matches an open ticket's queue
on the old unit (3.4 step 2: an avoid and any open ticket owing a row, or a WOUND whose school matches); otherwise it
resolves to the new unit. Second, the dedupe (2.4): if the same payload already arrived on another token within
`DUP_WINDOW`, the row is a duplicate of that one. This catches a stale `target` echo right after a swap, which the
report flagged (risk: a stale `target` WOUND after a swap counts toward the new target).

`GRACE` = 0.1 s is now a floor, not the whole grace: a unit's tokens stay resolvable for as long as any open ticket is
pinned to it, plus `GRACE` after the last one closes. The kill kinds differ. A projectile kill clears the target 11-36
ms before the row (the clear comes at impact; capture c 219886 to 219922). A melee kill clears it about 370 ms before
the row: the server's hit clears the target, and the row arrives at the landing lag (Rogue capture: swing 10283, clear
10384, row 10754, 471 ms after the swing). An open swing ticket (window 1.5 s, `Rows.lua:30`, `:333-338`) holds the unit
across that gap.

### 2.4 Dedupe and dispatch

One outcome arrives once per token naming the victim, in the order plate, target, soft (`tests/Game/harness/observer.lua:81-95`
encodes the same order from the earlier logs; capture b 42067-42068 confirms it). The fan-out can span 1 ms.

A resolved row is a duplicate when a ring entry has the same slot, `act`, `flag`, `amount` and `school`,
`|t - dT| <= DUP_WINDOW` (0.005 s), and the row's token is not yet in that entry's token set. A row whose token was
rebound while its previous slot is not GONE and whose payload matches a ring entry within `DUP_WINDOW` on any slot, under the same
token condition, is also a duplicate (the swap exception of 2.3). A duplicate adds its token to the group's set.

One outcome's fan-out never repeats a token: plate, target and soft each appear at most once per outcome (captures a,
b and c). So a row whose token is already in the matching group's set is a second outcome, even with the same payload
inside `DUP_WINDOW`: it starts a new group (a new ring entry) and is dispatched. Two partners' equal hits, or our two
hands landing together with equal damage, therefore stay two rows whenever they share a token.

Known limit: two genuine outcomes that each arrive on only one token, different tokens, with the same payload in the
same `DUP_WINDOW`, are indistinguishable and merge. That needs a victim with no shared token, which a visible plate
makes rare (a hit on our target arrives on its plate and `target`). An upper bound before that condition: in
party-light, about `1.8^2 x 0.005` = 0.016 same-window pairs a second, times about 0.07 for an equal amount over a
15-value damage range, is about 4 an hour. The detection suite measures the real rate per band (6.2, K9); in game a
merge looks exactly like one outcome on two tokens, so no counter can see it. Duplicates are counted
(`U.dup`) and dropped. A row that is not a duplicate goes into the ring, refreshes `uSeen`, and is dispatched once to
each listener registered with `I.Units.OnRow(fn)`, in registration order:
`fn(t, guid, uid, act, flag, amount, school)`.

Listeners register at load. Rows (tickets) registers first, then Target (`TargetDamage`), then any later consumer
(LibTTD). Dispatch is a loop over a load-time array of functions: no allocation.

### 2.5 Lifecycle

- Seen: a binding or a resolved row sets `uSeen = t`. A GUID not held takes a FREE slot, else an evicted one (2.6).
- Unbound: when `uTokens` drops to 0 the slot goes to GRACE with `uLeft = t`.
- Held: while `uHeld > 0` the slot stays GRACE (or DEAD) however long ago its last token left.
- Gone: the per-frame tick (`L.OnTick`, run from `EventFacade.lua:239-246`) moves a GRACE slot to GONE once it is
  released (no token, no open ticket) and `GRACE` has passed since the release, and calls each `I.Units.OnGone(fn)` listener: `fn(uid, guid, GONE, t)`. A GUID bound again
  later (plate churn, 0.5 s) takes LIVE again in the same slot if it was not evicted; nothing closed earlier reopens.
- Dead: any of these marks the slot DEAD at `t` and calls the OnGone listeners with `DEAD`:
  - the primary kill tell, the death events: `UNIT_DIED` with the unit's plain GUID, or `PLAYER_TARGET_DIED` for the
    current target. Measured on a white-swing kill (kill-events capture): `PLAYER_SWING` and `PARTY_KILL` (killer our
    GUID, victim the unit's, both plain) in the same ms (4364); `UNIT_DIED` and `PLAYER_TARGET_DIED` 2 ms later (4366);
    `PLAYER_TARGET_CHANGED` to none 2 ms after that (4368); a new target auto-selected 20 ms later (4388); the
    killing-blow WOUND 456 ms after the swing on `softinteract` only (4820). `UNIT_DIED` also fired for two nearby units
    killed by others (9433, 11352). `PARTY_KILL` with killer equal to our GUID also sets `uOurs[u]`: our kill.
  - a plain `UnitIsDead(token) == true` on a bound token. The existing polls already read it: `Target.lua:84` (poll 4) and
    `Game/State/Sources/Nameplates.lua:36-40` (poll 5). They report to `I.Units.Dead(uid, t)`; the registry adds no read.
    `UnitIsDead` on plates is plain in combat (probe U5), so this path needs no fallback.
  - the fallback kill tell, only when the client refused the death events (they are in `E.STUB`,
    `EventFacade.lua:93-95`): `PLAYER_TARGET_CHANGED` to none within `KILL_TELL` = 0.010 s after any player
    `UNIT_SPELLCAST_FAILED`; the previous target's slot dies. Seen in all four kills of captures b and c (FAILED to clear:
    16019 to 16022, 42045 to 42048, 74794 to 74796, 219884 to 219886). A melee kill shows no FAILED (the Rogue capture
    clears the target with none), so the fallback misses it; the unit then ends through poll 5 or GONE.
  A DEAD unit's tickets stay open until paid or their own window ends (decision 8). A ticket on a unit we killed
  (`uOurs`) that is never paid closes as `closedDead`, never lost; it also counts `T.closedOurs`. The auto-selected new
  target rebinds `target` 20 ms after the death, so the killing row resolves through the rebound-token rule (2.3) or,
  as measured, arrives on `softinteract` alone.
  The clear and the killing row come in either order. A white-swing kill clears before its row (about 370 ms: the
  server's hit clears the target, the row arrives at the landing lag). An instant kill clears after its row (Eviscerate:
  row 1 ms after its success, clear 101 ms after the row). A projectile kill clears 11-36 ms before its row.
  A DEAD slot still resolves rows while held and for `GRACE` after its release, so the killing blow pays its ticket.
- Reset: `PLAYER_REGEN_ENABLED` frees every slot with no bound token (OnGone with `RESET` first) and clears the dedupe
  ring and `failT`. Bound units stay: the target is still the target after combat. The reset does not precede the last
  row: in the Rogue capture `PLAYER_LEAVE_COMBAT` fired 100 ms after the clear (10483) and `PLAYER_REGEN_ENABLED` about
  420 ms after it (10802), after the killing-blow row (10754).

Other observations from the Rogue capture: `PLAYER_SWING`'s payload is (1.6, 0), the swing speed and the hand index,
as Rows reads it (`Rows.lua:318`); `UNIT_TARGET` fires for `player`, `targettarget`, `nameplateN` and `target` when the
mob turns to us (7166-7169), which Attackers' `recheck` already covers (`Attackers.lua:102-108`).

### 2.6 Capacity and eviction

At most 44 tokens are bound and at most `TICKETS` = 16 tickets are open, so at most 60 slots are LIVE or held; 64 slots
always leave 4 that are released or FREE.
A new GUID takes a FREE slot, else the GONE or released DEAD slot with the oldest `uSeen`, else a released GRACE slot with the oldest
`uSeen`. A LIVE or held slot is never evicted. Evictions are counted (`U.evicted`). The search is a 64-step loop.

### 2.7 API

All functions are on `I.Units` (internal; not public surface). None allocates.

| Function | Answer | Callers |
|---|---|---|
| `TOKENS`, `INDEX` | token by index; index by token string | Attackers, Nameplates |
| `Resolve(api, i, t)` | `guid, uid` or nil | the registry's `UNIT_COMBAT` handler |
| `Bound(i)` | the GUID bound to token index `i`, "" none | Attackers (replaces `tokGUID`), Target |
| `Pin(api, t)` | the commit-time GUID: `target`'s live GUID, else `softenemy`'s, else nil | Casts (SENT), tickets (swing, instant success) |
| `Find(guid)` | the slot holding `guid`, or 0 | tickets, Target |
| `Alive(uid)` | true while LIVE or GRACE | tickets |
| `Dead(uid, t)` | marks DEAD (from a poll) | Target poll 4, Nameplates poll 5 |
| `OnRow(fn)` | load-time listener for resolved, deduplicated rows | Rows, Target |
| `OnGone(fn)` | load-time listener `fn(uid, guid, why, t)`, why 3 GONE, 4 DEAD, 0 RESET | Rows, Target |

Snapshot line: `units live=%d grace=%d gone=%d dead=%d unresolved=%d dup=%d evicted=%d deaths tell=%d poll=%d event=%d`.

## 3. Tickets

The ticket model replaces Rows' pending-action ring (`actT`, `actKind`, `actX`, `actDst`, `actW`, `actRef`, `actLR`,
`actAvoid`, `Rows.lua:108-111`) and keeps everything that already works: the swing likelihood ratio, the amount
classes, the learned lags, the background rates, the provisional avoid, the usability oracle and the on-next-swing
replacement.

The engine makes no assumption about what a spell does. The ability declares an expectation (section 5): a value
naming one of a small fixed set of kinds, with its numbers. The engine registers a ticket with it and handles the rest.
Each kind's matching rule and closure rule are implemented once, in the engine; packs write no matching or closing code.

### 3.1 The record

A pool of `TICKETS` = 16 records (Rows has 8 today, `Rows.lua:104`; flight windows of up to about 2.1 s for a 40 yd
Speed-20 cast need more room). Fields, each a preallocated array:

| Field | Meaning |
|---|---|
| `kind` | the engine kind (3.3) of the ability's `expects` type (5.1): NONE, FRAME, FLIGHT, MELEE, STRIKE, TICKS, CHANNEL, or the engine's own UNMAPPED |
| `ab` | the ability index (0 for a swing or an unmapped success): the integer reference to the ability's precompiled type and fields (`A.expKind[ab]`, `A.velocity[ab]`, `A.school[ab]`, ...); no closure is stored |
| `x` | hand (1 main, 2 off) for a swing; the spell ID for a spell (the row's spell ID) |
| `guid`, `uid` | the pinned victim and its registry slot ("" and 0 when nothing was pinned) |
| `school` | the ability's `school` field (0: none, the kind then owes no WOUND; -1: ANY, from the default type, 5.2) |
| `owed` | rows still owed: 0 resolves the ticket; 1 for FRAME and FLIGHT; N for TICKS; open-ended for CHANNEL; each paid row decrements it |
| `period` | seconds between owed rows (TICKS, CHANNEL); 0 otherwise |
| `at` | the anchor: the swing, or the success (a hard cast is anchored when its success arrives) |
| `lo`, `hi` | the current window, absolute once the ticket is armed |
| `ref` | an off-hand swing's main reference (as `actRef`) |
| `lr`, `avoid` | a provisional avoid's LR and action (as `actLR`, `actAvoid`) |
| `state` | 0 free, 1 committed (hard cast between SENT and success), 2 open, 3 provisional (holds an avoid), 4 closed |

The context the engine fills a ticket from is one preallocated table `CTX`, built at load: `t` (the commit time),
`guid`, `hand`, `rMax` (the ability's maximum range), the (GUID, speed) learned lag when one exists (`lagE`,
`lagSpr`, `lagAge`), the optional plain range bracket's lower bound `rangeLo` (0 when absent, 3.3.1), and the
ability's learned amount band (`bandLo`, `bandHi`, `bandN`, 3.4). Pack code never reads it. No table, closure or
string is made per event.

### 3.2 Opening

A ticket opens for every commit, unconditionally, as one uniform record:

- Every `PLAYER_SWING` with swingType 0 or 1, at the swing: kind MELEE for that hand, window `[at, at + w]` with `w`
  as today (`Rows.lua:333-338`). Swings are the engine's own commits; no pack declares them.
- Every player `UNIT_SPELLCAST_SENT` of a mapped ability with a cast time (a hard cast): the ticket opens committed,
  pinned at SENT (Casts stores `I.Units.Pin` with the SENT's castGUID). It is armed (anchored, state open) when the
  matching success arrives, and closed without counting when the matching FAILED or INTERRUPTED stops the cast
  (`Casts.lua:67-79`).
- Every player `UNIT_SPELLCAST_SUCCEEDED` that no committed ticket claims, mapped or not, pinned at the success.
- An unmapped success (a potion, an item, a racial: `I.ab.bySpell` has no entry) opens kind UNMAPPED. It owes no row,
  its window is `L.UNMAPPED_WINDOW` (`Rows.lua:54`), and it matches any GUID. It absorbs an avoid or a crit inside its
  window, past another ticket's own frame, as nobody's: no row, no `Obs.Avoided`, no `Obs.Crit`. This is today's
  `another()` rule (`:163-173`) as a generic ticket, and it replaces `unmappedT` (`:55`, `:344-346`, `:617`).

At opening the engine takes the ability's type (`A.expKind[ab]`) and reads the fields that type needs (5.1:
`velocity`, `school`, and for TICKS and CHANNEL the aura's `tick_time` and `duration`), then fills `kind`, `owed`,
`period`, `school`, `lo` and `hi` by that kind's rule (3.3).

Ticks come from the aura the packs already declare, not from new ability fields. The aura is resolved as the sim
resolves it, `ability.cycle or ability.aura or ability.key` (`Engine/Sim/State.lua:676`; `Engine/Sim/Events.lua:1609` reads
`ability.tick_time or class.auras[ability.aura].tick_time`). The period is the aura's `tick_time` and the count is
`floor(duration / tick_time)`, the same fields the sim reads (`Engine/Sim/State.lua:2283-2285`). Packs already declare
them, for example `src/Hekili_Priest/Priest.lua:265-280` (Devouring Plague 24 / 3, Holy Fire 10 / 2, Mind Flay 3 / 1)
and `src/Hekili_Mage/Mage.lua:235` (Evocation 8 / 1). A numeric field compiles at build. A function-valued field
(Moonfire's rank-dependent duration, `src/Hekili_Druid/Druid.lua:512-520`) is called at commit in its own environment,
Hekili's state, exactly as the sim calls it; it must return a number and allocate nothing.

Kinds compose with ticks. A declared `"instant"` or `"travel"` ability whose resolved aura has a `tick_time` and
upstream's aura field `dot = "debuff"` (read by the sim's `mt_dot`, `Engine/Sim/State.lua:3302-3312`; values `"buff"`,
`"debuff"`, `"both"`; no pack sets it today, so packs add `dot = "debuff"` to their DoT auras) opens two tickets pinned
to the same GUID at one commit (Moonfire: ability `expects = "instant", school = "arcane"`, aura `duration = 12,
tick_time = 3, dot = "debuff"`): the direct ticket of
the declared kind and a TICKS ticket owing the aura's tick count (decision 17's `owed`). The TICKS ticket is
anchored at the application: the direct ticket's row when it is paid, else the success; if the direct ticket is paid
by an avoid, the TICKS ticket closes with nothing owed (not lost). `expects = "ticks"` alone (Corruption, Shadow Word:
Pain) opens only the TICKS ticket, anchored at the success. A `"ticks"` ability may also declare `velocity` (Serpent
Sting): its application's avoid is then taken in the FLIGHT hard window and learned-lag bands (3.3.1), not
`LandWindow(1)`, so a long-range miss still pays; and its schedule is anchored at the success plus the learned flight
lag for that GUID and speed when one exists, else at the success plus `rMax / speed / 2` with every tick band widened
by `rMax / speed / 2` until the first tick is paid, after which the anchor snaps to that tick. Kind NONE
resolves the ticket at commit (a buff, a seal, anything that owes no row): it closes at once, counts `T.none` and never
matches a row.

An ability with no `expects` gets a default type (5.2): `"strike"` if it has `onNextSwing`, `"instant"` if it has
`startsCombat`, otherwise `"none"`. That is today's behaviour exactly (Rows holds only those abilities, `:347`), with
school ANY when the ability has no `school` field. Every pack's floors therefore hold until it declares data.

A mapped ticket whose pin is nil (no target, Action Targeting off) still opens, with `guid` "". It matches no row (rows
always resolve to a GUID), closes on expiry and counts as `T.unpinned`, not as lost. Today such a ticket's rows are
never emitted anyway (`emit` drops a "" destination, `:283-286`).

### 3.3 Kinds: windows, matching and closure

| Kind | Window | A row it accepts | Closes |
|---|---|---|---|
| NONE | none | none | at commit |
| FRAME(school) | a WOUND within `SAME_FRAME`, or `CAST_WINDOW` for a white wound no swing takes (today, `:458`, `:497-499`); an avoid within `LandWindow(1)`, or `CAST_WINDOW` while `bg[7] >= FOREIGN_AVOIDS` (today, GAP AX, `:459-461`) | a WOUND of `school`; any avoid | on its row, or expiry |
| FLIGHT(speed, school) | the hard window `[at, at + rMax / speed + TOL]`, scored by the learned lag (3.3.1) | a WOUND of `school`; any avoid (a spell miss is school 1, fact 2) | on its row, or expiry |
| MELEE(hand) | the LR density's support `[0, w]` (`Rows.lua:252-269`) | the swing scoring (3.4 step 3) | on its row (an avoid provisionally), or expiry |
| STRIKE | today's frame | the strike's row; it replaces the main hand's MELEE ticket within `STRIKE_WINDOW`, or waits for that swing (today `:329-332`, `:351-361`) | on its row, or expiry |
| TICKS(period, ticks, school) | tick `k` at application + `k x period +- 0.1 s` | a WOUND of `school` on the pinned GUID inside a tick's band; no amount band (a ramping DoT such as Curse of Agony varies 3x across its ticks; the schedule is the discriminator); an alone-declared TICKS ticket takes the application's avoid inside `LandWindow(1)` (inside the FLIGHT bands when the ability declares `velocity`, 3.2) and closes with nothing owed | on the last tick; on a refresh (a new application of the same ability on the same GUID: closed as `refreshed`, its unpaid `owed` not lost, and a new TICKS ticket opens from the new application); on the unit's death (`closedDead`, decisions 7 and 8); on the removal of the ability's debuff on that GUID (the aura row `L.Aura` emits, `Game/Events/CombatLog.lua:171`); or expiry |
| CHANNEL(period, school) | tick `j` at `at + j x period +- TOL` | a WOUND of `school` | on `Obs.ChannelStop` for the ability (`Casts.lua:130-139`) |
| UNMAPPED | `UNMAPPED_WINDOW` | an avoid or crit nobody took (3.4 step 5) | expiry, never lost |

TICKS is measured (Moonfire rank 1, druid-moonfire capture): the direct hit is a WOUND of the spell's school (arcane,
64) 2 ms after its success (amounts 9, 8, 8); the ticks are plain WOUND rows of the same school, amount 4, no flag,
every 3.0 s +- 50 ms (3036, 2984, 3050, 2967, 2967, 3033 ms) counted from the application; three ticks fall in a 9.8 s
window, so four over the 12 s duration. A recast resets the schedule: the next tick comes 3 s after the refresh and the
old schedule's remaining ticks never arrive. A kill by the direct hit cleared the target 3 ms after the row, and the
remaining ticks never came. A tick row outside every TICKS band is foreign.

A school of nil on a declared type means the hit makes no row of ours: the kind then takes only an avoid in its
window, and its expiry is not a lost resolution (a pure aura with no damage). School ANY (a default type on an
ability with no `school` field, 5.2) takes any WOUND or avoid in its window, as today, and is never lost.

#### 3.3.1 FLIGHT: hard window and learned lag

The engine cannot read an up-to-date range to a unit in combat, so a FLIGHT window is not built from a range bracket.

Hard window: `[at, at + H]` with `H = rMax / speed + TOL`, always. `rMax` is the ability's maximum range
(`Game/State/Sources/Spellbook.lua:43`), or 40 yd when that is 0; `TOL` = 0.15 s. For Wrath, `H` = 1.65 s; the five
max-range samples (1483-1566 ms) fit with 84 ms to spare.

One optional plain read may narrow its lower bound. `VS.TargetRange()` (`Game/State/Families/Enemies.lua:71-73`) is
plain in combat: poll 14 builds it from `C_Spell.IsSpellInRange`, which answers plainly (`Game/State/Sources/Target.lua:8-9`,
probe W PR7). It covers the current target only, as a bracket between the tracked abilities' ranges, as of its last
change. When the pinned GUID is the current target and the bracket has `lo > 0`, the hard window's lower bound becomes
`max(0, (lo - CLOSE x age) / speed - TOL)`, where `age` is the time since the bracket was logged and `CLOSE` = 7 yd/s
(a running mob). The bracket's upper bound is never used: a closing mob makes it stale on the wrong side.

Learned lag. A pool of `LAG_CAP` = 16 records, keyed by (GUID, speed), preallocated: `lagGUID`, `lagSpeed`, `lagE` (the
last observed lag, s), `lagSpr` (spread), `lagT` (time of the last observation), `lagN` (observations). It is the
same mechanism as Rows' global melee lag (`learn()`, `Rows.lua:272-279`), keyed per unit and speed because a
projectile's lag depends on the distance to that unit. A FLIGHT ticket paid in pass (a) or (b) (3.4) with no other
candidate in that pass teaches its record: `lagE` takes the observed lag (the expected lag for the next ticket is the
last one: a closing mob makes it shrink); `lagSpr` moves by `0.25 x (1.2533 x |lag - old lagE| - lagSpr)`, clamped to
[0.02, 0.4]; `lagT` is the row's time. The first landing on a GUID also gives its distance, `lag x speed` (Snapshot
only). A full pool evicts the record with the oldest `lagT`. Records survive combat end (a GUID does not return) and
reset at load.

Widening schedule, for a ticket whose (GUID, speed) has a record, with `d` = the row's time minus `lagT`:

- base half-width `b = max(TOL, 2 x lagSpr)`;
- downward (the mob closed) `down = max(b, (CLOSE / speed) x d)`; upward (the mob backed off) `up = max(b, (CLOSE / 2 / speed) x d)`;
- narrow band (pass a): `[at + lagE - b, at + lagE + b]`;
- widened band (pass b): `[at + lagE - down, at + lagE + up]`, clipped to the hard window.

For Wrath, `CLOSE / speed` = 0.35: two seconds after the last landing the band reaches 0.7 s below the last lag.

First-ticket rule: no record for (GUID, speed) yet means the whole hard window, uniform, and the ticket is a candidate
in pass (c) only.

#### 3.3.2 MELEE: the first swing of a combat

The first white swing after `PLAYER_ENTER_COMBAT` landed 989 ms after its `PLAYER_SWING` (second Rogue capture, one
sample); the next landed at 452 ms, in line with the learned median (0.474 s, `Rows.lua:67`). Either the first
`PLAYER_SWING` marks auto-attack turning on rather than a swing, or the first swing lags longer. The owner's ruling
(U10): auto-attack turns on at once when an ability is used or `/attack` is pressed, and the first `PLAYER_SWING` is
that first swing. Its row's lag stays a one-sample observation (989 ms), so the first MELEE ticket of a combat does not teach the learned lag (`learn()`, `Rows.lua:272-279`), and its
Due band (pass a) is the whole LR window `[0, w]` instead of the core band.

Landing lags also vary by session: 988, 837 and 456 ms in the Rogue kill-events session against the Warrior's 474 +-
60 ms (`Rows.lua:67` seeds). Floating combat text does not delay the rows (U11, closed by owner ruling), so these are
real row lags, not a display artefact. The MELEE learned lag and spread must absorb that range per session: the
Warrior's 474 +- 60 ms is one character's seed, not a constant, and nothing in this design assumes 0.474 s beyond the
seed. The Due band uses the learned spread, which widens in such a session.

### 3.4 Paying (the consumption order)

The order in which rows are consumed by tickets decides correctness. The algorithm, exactly:

1. Rows are consumed online, one at a time, in arrival order, after the registry's dedupe (GUID + ms, 2.4). Several
   distinct rows at the same ms are processed in token order. A WOUND 0 is processed before the damage row of the same
   strike frame: it marks `lastW0` and pays nothing (today, `Rows.lua:454-457`), which arms the foreign strike frame
   rule (`:481`) for the row after it.
2. Candidates for a row are the open or provisional tickets of its queue: `guid` equal to the row's, and a kind
   compatible with the row. An avoid can pay any kind that still owes a row. A WOUND can pay only a kind whose school
   equals the row's (MELEE and STRIKE: school 1, as today; school ANY: any), and only
   once it fits the ability's amount band (below). A nil-school ticket is paid only by an avoid.
3. Each candidate has an expected closure time: `at + lagE` for FLIGHT (`at + H / 2` before its first record),
   `at + L.med[hand]` for MELEE (the learned landing lag, `Rows.lua:67`), `at` for FRAME and STRIKE,
   `at + j x period` for the next owed tick of TICKS and CHANNEL. Candidates are taken in expected-closure order, not
   commit order. FIFO per queue falls out of it when expected lags are equal.
4. Passes, in order: (a) the narrow band around each candidate's expected closure; (b) the widened band (3.3.1 for
   FLIGHT); (c) the hard window, open only to tickets with no learned record (the first-ticket rule). The first
   candidate in expected-closure order that matches at the current pass pays. A later pass runs only if no candidate
   matched at the earlier one. So a ticket whose expected closure is still ahead of the row by more than its band
   cannot be paid ahead of a ticket whose expected closure has arrived. "First in order" is a single scan for the
   least expected closure among the candidates that match at the pass: no sort, no allocation.
5. A row that matches no candidate after pass (c) goes to the UNMAPPED ticket if it is an avoid or crit inside an
   UNMAPPED window (absorbed as nobody's), else it is foreign: `background()` as today (`:408-429`), counted `T.foreign`.
   A foreign row of the same school as one of our tickets that is Due on another GUID at that moment also counts
   `T.aoeOther` (our AoE or cleave on a unit we did not pin): a diagnostic only, routed as foreign, never a ticket and
   never lost.

Bands per kind:

| Kind | (a) narrow | (b) widened | (c) hard |
|---|---|---|---|
| FLIGHT | `lagE +- b` | `[lagE - down, lagE + up]` | `[0, H]` (no record only) |
| MELEE | the core band, within 2 `spr` of the median (`Rows.lua:367-369`) | the LR window `[0, w]` (`:252-269`) | as (b) |
| FRAME, STRIKE | `SAME_FRAME` | WOUND: `CAST_WINDOW`; avoid: `LandWindow(1)`, or `CAST_WINDOW` while `bg[7] >= FOREIGN_AVOIDS` (GAP AX) | as (b) |
| TICKS | tick time `+- 0.1 s` | as (a): the schedule is the only discriminator | as (a) |
| CHANNEL | tick time `+- TOL` | tick time `+- 2 x TOL` | as (b) |

MELEE inside the frame: when the first match at a pass is a MELEE ticket, the existing likelihood ratio decides among
all MELEE candidates that match at that pass (LR = q x f / lambda, the bar `THETA` for avoids and `theta[k]` for wounds,
the veto, `:487-495`). Below the bar, MELEE does not match at that pass. At a tie in pass (a) between a FRAME ticket
and a MELEE ticket for a white avoid or crit, MELEE wins, keeping today's precedence (`:464-478`).

Where this differs from today: Rows tries a fresh cast's frame first and then any avoid within the cast window
(`:458-461`), then the swing LR (`:487-495`), then a white wound within `CAST_WINDOW` for the cast (`:497-499`), always
the oldest cast first (`:146`). The new order replaces commit order with expected closure and adds the passes; for
abilities on their default type and for swings the bands are today's windows, so the outcome is the same.

Why this bounds a lost resolution to one shift. A ticket whose row never comes (a resist not seen as a row, a row on
a token we do not see) stays open. A later row of its queue could pay it instead of its true owner only if the row
falls in the lost ticket's band at the earliest pass where the owner also matches. Two tickets of one queue committed
`s` seconds apart have expected closures `s` apart; once `s` exceeds the narrow band (`2b`, 0.3 s for Wrath), each
row matches its own ticket at pass (a) and the lost ticket simply expires at its hard window. Only when casts come
closer than the band, or while no record exists, does a row shift by one ticket, and the shift ends when the lost
ticket expires (at most `H` after its commit) or closes on the kill tell or GONE. A shift between two of our own hits
of the same school and kind changes no belief. Only a divergent outcome (hit vs miss, hit vs crit, amount for rage)
is affected; those count as `divergent` toward the 4.2 trigger.

Example from capture a: the 97374 Wrath's own row landed at 98890 (1516 ms), and a MISS arrived at 97891, 517 ms after
that success and 2067 ms after the 95824 success. Today Rows charges the MISS to the 97374 cast, because it is inside
the cast's avoid window (`:459-461`). With a learned `lagE` of about 1.5 s for that GUID and a last landing about 1.5 s
earlier, the 97374 ticket's narrow band is [1.35, 1.65] s and its widened band reaches down to about 1.5 - 0.53 =
0.97 s: 0.517 s is in neither. The 95824 ticket has expired (its hard window ended at 1.65 s). The MISS is therefore
foreign. Had an older ticket of that queue still been open with the MISS in its band, that ticket would have paid it.

FIFO per queue, proof. Take one GUID and one speed `v`, casts A then B with successes `tA < tB` and distances `dA`,
`dB`. A lands at `tA + dA / v`, B at `tB + dB / v`. B lands first only if `dA - dB > v x (tB - tA)`: the distance
must shrink faster than `v` between the two successes. The slowest projectile is 20 yd/s (5.4); a running mob is about
7 yd/s and a running player about the same, so closing never reaches `v`. Resolutions of one queue therefore arrive in
cast order, and expected-closure order equals commit order within a queue. The exceptions are a charge, a blink or a
knockback between two casts. They swap two same-school hits, which changes no belief (the cascade bound above).
Different speeds, schools or GUIDs are separate queues and never FIFO across one another.

The amount band: per ability, `bandLo` and `bandHi` of its own non-crit WOUNDs (a crit halved), learned from tickets
paid with exactly one candidate. On a new low, `bandLo` takes the amount; otherwise it creeps up by
`0.05 x (amount - bandLo)`; `bandHi` mirrors it. Once 3 wounds taught it, a WOUND outside
`[SPELL_BAND_LO x bandLo, SPELL_BAND_HI x bandHi]` = `[0.6 x, 1.6 x]` is not a candidate (counted `T.bandRejected`).
The band survives combat end and resets at load, like the swing lags (`Rows.lua:611`). MELEE keeps its own amount
classes from `UnitDamage` (`classOf`, `:223-242`) instead.

A paid row decrements `owed`; a ticket with rows still owed moves its window to the next one (`lo + period`,
`hi + period`).

Invariants, checked by the detection suite: a row pays at most one ticket; a ticket is paid at most `owed` times,
except through the existing controlled re-opens (the provisional avoid overtaken by a higher-LR wound, `:522-529`; the
firm retraction of `I.CreditVerdict`, `:577-586`; the strike replacement).

#### 3.4.1 Phases of an open ticket

An open ticket passes through four phases relative to its expected closure `E` (3.4 step 3). They are computed from
the row's time at each row evaluation and never stored: no state field, no transition event.

| Phase | Row time | Pass |
|---|---|---|
| Ahead | earlier than `E` minus the narrow band | none: an Ahead ticket cannot be paid ahead of a Due one |
| Due | inside the narrow band | (a) |
| Widened | inside the widened band (3.3.1), outside the narrow one | (b) |
| Overdue | inside the hard window only | (c), reachable only by tickets with no learned record (decision 33) |

A ticket with a learned record whose row falls outside its widened band but inside the hard window is in no phase
for that row: it is not a candidate. MELEE uses the same phases with its learned global lag (`L.med`, `L.spr`): Due
is the core band, Widened and Overdue are both the LR window, as the bands table above gives.

### 3.5 What a payment emits

| Payment | Row (dst = the ticket's `guid`) | Staged |
|---|---|---|
| MELEE, WOUND | `SWING_DAMAGE` (today, `:290-293`) | `Obs.Swing` c = 1, and c = 3 on CRITICAL (`:544-547`) |
| MELEE, avoid | provisional (`:522-526`); `SWING_MISSED` at close | nothing |
| spell, WOUND | `SPELL_DAMAGE` with the ticket's `school` in slots 14 and 17 (the row's school when the kind names none; today hard-coded 1, `:300`) | `Obs.Crit` on CRITICAL when no divergent pair (4.2) |
| spell, DODGE / PARRY / MISS | `SPELL_MISSED` with the same school rule (today 1, `:304`) | `Obs.Avoided` (`:175-184`) when no divergent pair |
| spell, RESIST / IMMUNE / ABSORB / EVADE / BLOCK / DEFLECT | `SPELL_MISSED` with that miss type | nothing (as today: `REFUSED` covers DODGE, PARRY, MISS only) |
| TICKS or CHANNEL, WOUND | `SPELL_PERIODIC_DAMAGE` at the row's own time | nothing |
| UNMAPPED, absorbed | nothing | nothing |

Rows other than ticks are back-dated to `at`, as today. `another()`'s two-casts half is replaced by the divergent-pair
rule (4.2); its unmapped half is the UNMAPPED ticket.

### 3.6 Closing

A ticket closes on the first of:

| Close | When | Emitted | Counter |
|---|---|---|---|
| resolved at commit | kind NONE (declared, or the default type of an ability Rows does not hold today) | nothing | `T.none` |
| paid out | `owed` reached 0 (3.4) | 3.5 | `T.paid[kind]` |
| signal | the kind's non-row close (3.3): TICKS on its debuff's removal, CHANNEL on its stop | nothing | `T.paid[kind]` |
| refreshed | TICKS: a new application of the same ability on the same GUID | nothing | `T.refreshed`, unpaid `owed` not lost |
| cast stopped | a committed hard cast's FAILED or INTERRUPTED | nothing | none |
| window expiry | `now > hi` with `owed > 0`, in the per-frame tick (today `:597-609`) | MELEE: `SWING_MISSED` if provisional, else `SWING_DAMAGE` amount 0 (kept: the swing timer reads it); others: nothing | `T.lost[kind] += owed`; UNMAPPED, school ANY and a declared nil school count `T.expired` instead |
| kill | its `uid` is DEAD and its own window ends unpaid (it stays open until then: a melee killing blow lands about 370 ms after the clear) | as expiry | `T.closedDead`, not lost |
| gone | OnGone with GONE for its `uid` | as expiry | `T.closedGone` |
| combat end | `PLAYER_REGEN_ENABLED` (today `:612-618`) | nothing | none |
| pool full | the oldest open ticket gives way (today `:138`) | nothing | `T.overflow` |

A lost resolution is an owed row that never came while its unit was alive. It is the recall signal in game: Snapshot
shows `tickets open=%d none=%d paid=%d lost=%d expired=%d refreshed=%d foreign=%d unpinned=%d dead=%d gone=%d bandRejected=%d
divergent=%d overflow=%d`.

Belief effects stay where they are: `now` at the success, `onCrit` through `Obs.Crit`, the undo and refund through
`Obs.Avoided` (4.1). Tickets never write beliefs.

### 3.7 The existing paths, kept

- Provisional avoid (`:522-526`): unchanged, now GUID-filtered.
- `I.CreditVerdict` (`:558-592`): unchanged. Its re-open `hold(1, hand, recDst[id], ...)` (`:582`) becomes an open
  MELEE ticket with `guid = recDst[id]` and `uid = I.Units.Find(recDst[id])`; a GUID no longer held reopens nothing and
  emits the `SWING_MISSED` branch (`:584`) instead.
- WOUND 0 (`:454-457`) and the foreign strike frame after it (`:481`): unchanged.
- `VS.SwingPending` (`Game/State/Families/Resources.lua:1279-1296`): unchanged; it reads `L.LandWindow`, which keeps its
  meaning for swings.
- Learning: lags learn from clean swing credits as today (`:530-535`); the amount band (3.4) learns from clean spell
  credits.

## 4. Beliefs

### 4.1 Unchanged consumers

Families read the same observations with the same payloads:

- `Obs.Swing` (`Rows.lua:544-547`) to `Families/Resources.lua` (`:883` and the owe path): unchanged.
- `Obs.Crit` to `Families/Now.lua:455-462`: runs the ability's `onCrit` at the crit's row. New: it now fires for
  projectiles (Shadow Bolt's crit, ledger Wl3, docs/dev/gaps.md:54), at landing time, which is when the game applies it.
- `Obs.Avoided` to `Families/Now.lua:469-486`: undoes the latest cast's target auras and refunds `refundOnAvoid`.
  It still acts only when the avoided cast is the latest (`:470`). A projectile's miss now arrives up to 1.65 s after
  its success, so a second cast may have succeeded since; the undo then does nothing, as designed for "any other cast".
- `Obs.TargetDamage` and `Obs.TargetGone` to `Families/TargetHealth.lua:197-224`: unchanged payloads (4.3).

### 4.2 Divergent ambiguity (DESIGNED, DEFERRED)

Two candidate tickets for one row are divergent when the choice changes what the belief stages:

| Dimension | Divergent when | Not divergent |
|---|---|---|
| hit vs miss | an avoid has two candidate spell tickets and the latest cast (Now.lua's `undoA`, `undoT`) is one of them | both candidates are older than the latest cast |
| hit vs crit | a CRITICAL has two candidate tickets of different abilities, at least one with an `onCrit` | same ability on both |
| amount for rage | a WOUND has two swing candidates of different hands both over their bar with different rage | one candidate over the bar |

Two plain hits of the same school are not ambiguous: the oldest pays, the other stays open for its own row.

The rule when built: widen the belief to the union on that dimension only, and collapse it on the first of: the other
candidate ticket is paid (the remaining assignment is then determined); a usability read answers (swing rage:
`I.CreditVerdict`; an aura: a plain read where one exists); a branch dies (expiry, kill, gone). Concretely:

- swing rage: `hi0` of the slot steps to include the larger credit, `lo0` keeps the smaller; `est0` does not move.
- crit: the `onCrit` writes go to the record's `hi` only; `est` keeps the no-crit value.
- miss: the undo is applied to `lo` only; `est` keeps the hit.

Under the no-jitter rule a wide belief never flips the icon by itself: recommendations read `est`, which stays at the
pre-ambiguity value until a collapse.

Until it is built, a divergent row stages nothing (no `Obs.Crit`, no `Obs.Avoided`, no rage), pays the oldest candidate
for the row only (so the combat-log row is still emitted), and counts `T.divergent`. This matches today's behaviour for
two pending casts (`another()`, `Rows.lua:500-502`) and stays on the floor's safe side.

Trigger for building it: the in-game Snapshot shows `divergent` above 1 per 100 paid tickets over a five-man dungeon
run, or the detection suite's busy 5-man band shows a divergent pair rate above that with a measured flicker cost.
Neither has been measured; this spec does not build it.

### 4.3 Target health and the killing blow

`Target.lua` stages `TargetDamage` from the registry's rows whose GUID is the current target's (any token), instead of
`unit == "target"` only (`Target.lua:139-143`). The killing blow after the clear resolves to the old GUID, which is no
longer the current target, so it still stages nothing; `TargetHealth` drops slot 0 anyway (`TargetHealth.lua:198`).
The gain is the kill itself: OnGone with DEAD calls `Direct(Obs.TargetGone, t, slot)` for the dead GUID's memory slot
(`Target.lua:29-47` keeps the GUID to slot map), so a dead target's modelled debuffs end at its death rather than 16 s
later (the replay's 32.324 removal).

## 5. Pack expectations

### 5.1 The types

`expects` on an ability is a plain string from a fixed set, nothing else. Each type maps to one engine kind (3.3),
implemented once; the engine reads the ability's other fields for the numbers. A pack never writes matching or
closing code.

| `expects` | Kind | Fields the engine reads | Backed by |
|---|---|---|---|
| `"none"` | NONE | none | captures: every success that owes no row (Drink, capture b) |
| `"instant"` | FRAME | `school` | captures and measured logs: today's instant-cast windows (`Rows.lua:33-49`) |
| `"travel"` | FLIGHT | `velocity` (DB2 `SpellMisc.Speed`), `school` (DB2 `SchoolMask`) | captures a, b, c (Wrath 1483-1566 ms at max range) |
| `"melee"` | MELEE | the hand, from `PLAYER_SWING`'s swingType | measured logs (the P and G logs behind `Rows.lua:15-16`) |
| `"strike"` | STRIKE | the existing `onNextSwing` | measured logs (today's on-next-swing replacement) |
| `"ticks"` | TICKS | `school`, optional `velocity`; the aura's `tick_time`, `duration` and `dot = "debuff"` (3.2); a declared `"instant"` or `"travel"` whose aura has those also opens one | measured: the druid-moonfire capture (3.3) |
| `"channel"` | CHANNEL | `school`; the aura's `tick_time`; opt-in only (never a default) | unprobed: implemented, untested and unused by packs; U9's channel half deferred by owner ruling |

`"melee"` is the engine's own type for `PLAYER_SWING`. No ability carries a hand field today, so an ability that
declares `"melee"` fails validation and falls back to its default type (below).

A `school` of nil on a declared type means the hit makes no row of ours: only an avoid pays, and expiry is not lost
(3.3). `velocity` is a plain number on the ability; the tick period, count and the `dot = "debuff"` marker live on the
aura (3.2). A heal-over-time or a self buff with a `tick_time` and no `dot = "debuff"` never opens a ticket. `school` is declared by name, a plain lowercase
string from a fixed enum: `"physical"`, `"holy"`, `"fire"`, `"nature"`, `"frost"`, `"shadow"`, `"arcane"`; numbers are
not accepted. The enum is one core table, `ns.SCHOOL = { physical = 1, holy = 2, fire = 4, nature = 8, frost = 16,
shadow = 32, arcane = 64 }`, in `Engine/Schema/Spec.lua` where the Schema compiles abilities, published as
`Hekili.SCHOOL` for the content addons. Schools are a game concept, not class content. Hekili_Shared's private copy
(`src/Hekili_Shared/Shared/Auras.lua:23`, `local SCHOOLS = { ... }`) becomes `local SCHOOLS = Hekili.SCHOOL`; the
lockout names it builds (`locked_out_<name>`) are unchanged, and Mage and Priest already branch on these names
(`src/Hekili_Mage/Mage.lua:142-150`, `src/Hekili_Priest/Priest.lua:148-152`). The engine maps the name to the client's
mask once at build and stores the number on the ability's compiled record (`A.school`); `UNIT_COMBAT`'s school argument
is compared with that number. A two-school spell (Frostfire Bolt) is deferred by owner ruling (U7): until then a pack
declares the school the client reports, or leaves it nil; Frostfire Bolt keeps no `school`. Hekili's simulation already knows
a `velocity` field, but its projectile branch needs `impact` too (`Engine/Schema/Spec.lua:908-909`), and no APL reads
`in_flight`. No pack adds `impact`, so the simulation does not change.

### 5.2 Default type

When `expects` is absent the engine maps it: `"strike"` if the ability has `onNextSwing`; `"instant"` if it has
`startsCombat`; otherwise `"none"`. The CHANNEL kind is opt-in: an ability with upstream's `channeled = true`
(`src/Hekili_Priest/Priest.lua:333` and others) and no `expects` follows this same rule, so Mind Flay and every other
channel keep their floors; only an explicit `expects = "channel"` opens a CHANNEL ticket, which reads the aura's
`tick_time` (3.2). This reproduces today's behaviour exactly: Rows holds only `startsCombat` and
`onNextSwing` abilities today (`Rows.lua:347`) with exactly these windows, and holds nothing for the rest. Every pack's
floors therefore hold until it declares data.

One rule keeps that exact. A mapped default ticket whose ability has no `school` field carries school ANY: any WOUND or
avoid in its window pays, as today, and its expiry is not lost. The nil-school rule above (only an avoid pays) applies
only when the pack declared `expects` itself. Unmapped successes keep their UNMAPPED ticket (3.2).

### 5.3 Precompilation and validation

At each build, beside `now` and `onCrit` (`Game/State/Families/Now.lua:318-333`), the engine reads `expects`,
`velocity`, `school`, `onNextSwing`, `cycle` and `aura` from each ability, and the resolved aura's
`tick_time`, `duration` and `dot`, into per-ability arrays: `A.expKind`, `A.expDeclared`, `A.velocity`, `A.school`, `A.dot` (the aura's `dot` is `"debuff"`),
`A.tickAura` (the aura index), `A.tickTime` and `A.tickCount` (numbers, or false when the field is a function and is
read at commit). A ticket refers to them by its integer `ab`.

Validation runs at the same build. An `expects` that is not one of the seven strings, or a type whose required fields
are missing or malformed (a `velocity` that is not a number, a `school` that is not one of the seven names;
`"travel"` without `velocity`; `"ticks"` or `"channel"` whose aura is missing or has no `tick_time`; `"ticks"` whose aura lacks `dot = "debuff"`;
`"strike"` without `onNextSwing`; any `"melee"`), is reported once through the existing build
warning path. `Hekili:Error` already reports a malformed `RegisterAbility` (`Engine/Schema/Spec.lua:857`), and Now's
build counts its errors into `I.nowErrors` for Snapshot (`Now.lua:327`). The ability then falls back to its default
type (5.2).

### 5.4 Abilities

From DB2 build 1.60.1.70338 (`SpellMisc`, every rank the pack lists agrees unless noted; LaunchDelay is 0 for all):

| Pack | Ability | Declares | Note |
|---|---|---|---|
| Druid | `wrath` | `expects = "travel", velocity = 20, school = "nature"` | |
| Warlock | `shadow_bolt` | `expects = "travel", velocity = 20, school = "shadow"` | |
| Warlock | `incinerate` | `expects = "travel", velocity = 20, school = "fire"` | |
| Warlock | `soul_fire` | `expects = "travel", velocity = 24, school = "fire"` | |
| Warlock | `death_coil` | `expects = "travel", velocity = 24, school = "shadow"` | |
| Mage | `frostbolt` | `expects = "travel", velocity = 28, school = "frost"` | |
| Mage | `fireball` | `expects = "travel", velocity = 24, school = "fire"` | |
| Mage | `pyroblast` | `expects = "travel", velocity = 24, school = "fire"` | |
| Mage | `frostfire_bolt` | `expects = "travel", velocity = 24` (no `school`: U7 deferred) | DB2 mask 20 (fire and frost) has no single name; the row's school is unmeasured (U7, deferred by owner ruling) |
| Shaman | `lightning_bolt` | `expects = "travel", velocity = 20, school = "nature"` | |
| Shaman | `lava_burst` | `expects = "travel", velocity = 20, school = "fire"` | |
| Priest | `shoot` | `expects = "travel", velocity = 20, school = "physical"` | the wand's own school may differ from the spell's mask (U7, deferred by owner ruling) |
| Paladin | `hammer_of_wrath` | `expects = "travel", velocity = 35, school = "holy"` | |
| Hunter | `auto_shot` | `expects = "travel", velocity = 40, school = "physical"` | |
| Hunter | `aimed_shot` | `expects = "travel", velocity = 40, school = "physical"` | |
| Hunter | `arcane_shot` | `expects = "travel", velocity = 40, school = "arcane"` | |
| Hunter | `multi_shot` | `expects = "travel", velocity = 30, school = "physical"` | the GUID match pays only the row on the pinned target; its other targets' rows stay foreign |
| Hunter | `sniper_shot` | `expects = "travel", velocity = 60, school = "physical"` | |
| Hunter | `serpent_sting` | ability `expects = "ticks", school = "nature", velocity = 40`; aura adds `dot = "debuff"` | a DoT with no direct WOUND; its aura (`src/Hekili_Hunter/Hunter.lua:232`: duration 15, tick_time 3) gives 5 ticks; `velocity` puts its miss in the FLIGHT window and anchors its ticks after the flight. Rank 1978's Speed is 40, the Forever 425728 family's is 0, so the check reads the pack's own ranks |
| Druid | `moonfire` | ability `expects = "instant", school = "arcane"`; aura `duration = 12, tick_time = 3, dot = "debuff"` | today's aura duration is a rank function (`src/Hekili_Druid/Druid.lua:512-520`: 9 at rank 1, 12 above); setting each rank's duration from DB2 and the capture is a pack data task |
| Hunter | `summon_hawk` | nothing (default type) | no outcome of ours known |

Instant abilities may declare `expects = "instant", school = "<name>"`; that turns on the school check and lost counting
inside today's frame windows. This spec does not require it, and the melee packs keep their default types.

### 5.5 The DB2 check

`tools/check_spell_data.lua`, run by a new dev-only target `make spell-data-check` (outside `make check`, like the
wowsims targets, because CI has no DB2 file). It loads each pack through the existing test loader. For every ability
that declares `velocity` or `school`, it reads `SpellMisc.Speed` and `SchoolMask` for each rank the ability lists (`id`
and `copy`) from `$WOW_DB2` (default `~/.local/share/wow-db2/forever/current.sqlite`) through `wowdb`'s SQL mode. It
fails when:

- a declared `velocity` differs from Speed on any listed rank;
- a declared `school` name differs from the name of SchoolMask on any listed rank (the check maps the mask through `ns.SCHOOL`; a mask with no single name, such as 20, is reported for the pack to leave `school` nil);
- an ability with Speed > 0 on its first rank and `startsCombat` declares no `velocity`; this rule covers abilities
  whose type is not `"ticks"` (a `"ticks"` ability's `velocity` is optional, but once declared it must equal Speed by
  the first rule).

## 6. Harness

### 6.1 Observer corrections (from the F1-F7 analysis, section c)

| # | Change | Where today |
|---|---|---|
| 1 | `castStop` takes a cause. Death: `@casting` nil, FAILED (castBarID 4th), STOP the same ms, then at +0.15 s three INTERRUPTED with nil, nil. Movement: INTERRUPTED (castBarID 5th), STOP 1 ms later, then two or three INTERRUPTED nil, nil | `tests/Game/harness/observer.lua:496-501` (INTERRUPTED then STOP), `world.lua:304-311`; `press_spec.lua:459-466` changes with it |
| 2 | Echo every player START, STOP, SENT, FAILED, INTERRUPTED, DELAYED on `targettarget` while the mob targets us, same castGUID, another castBarID | `observer.lua:482-484` echoes SUCCEEDED only |
| 3 | `UNIT_SPELLCAST_SENT (unit, targetName, castGUID, spellID)` before each START or instant success | none |
| 4 | castBarID payloads: 4th on START, STOP, SUCCEEDED, FAILED, DELAYED; 5th on INTERRUPTED; nil for instants (`Cast-4`) and key-spam FAILED (`Cast-2-0-0-0`) | none |
| 5 | DELAYED on our hard cast when we are hit, about 0.37 s before the player's `UNIT_COMBAT`, with `@casting` moved | none |
| 6 | Spell WOUNDs carry the spell's school; MISS carries school 1; a projectile lands at success + distance / velocity | `world.lua:601-618` and `replay.lua:696`, `:709`, `:721` emit school 1 at once |
| 7 | Kill: `PARTY_KILL` (killer our GUID) with the killing swing, `UNIT_DIED` and `PLAYER_TARGET_DIED` 2 ms later, `PLAYER_TARGET_CHANGED` to none 2 ms after that, optionally a new target 20 ms later; for a spell kill, `PLAYER_TARGET_CHANGED` to none 3 ms after the death's FAILED; the killing outcome 11-36 ms after the clear on the plate (and the soft token when on), `target` only sometimes | `observer.lua:437-453` keeps the dead target |
| 8 | Plate churn: a knob removes and re-adds a mob's plate (same GUID, new index allowed) within 0.5 s at a rate | none |
| 9 | Action Targeting knob, off by default: when on, `softenemy` binds to the target and its rows join the fan-out | `observer.lua:23` (`targetTokens`) |
| 10 | Truth carries the outcome's own ticket: `castT` (the success it belongs to) beside `hand` and `swingT` | `observer.lua:97-106` stream fields |
| 11 | Ticks: `W.hit` and the observer emit a DoT's ticks as WOUND rows of the spell's school at multiples of its period from the application, with +-50 ms jitter; a recast resets the schedule; a kill stops it | `world.lua:570-575` emits ticks as school 1 |

### 6.2 The detection suite

`tests/Game/harness/detect_spec.lua`, tagged `#slow`, table-driven over detection kinds x density bands, scored
against tickets through a new `metrics.tickets(m, s, W)` beside `metrics.score` (`tests/Game/harness/metrics.lua:75`).

Kinds (each a scripted scenario through the existing `scenarios.world` knobs, `tests/Game/harness/scenarios.lua:59`):

| Kind | Our actions | What it checks |
|---|---|---|
| K1 melee | white swings, both hands | swing tickets, unchanged recall |
| K2 strike | on-next-swing strike | replacement, WOUND 0 |
| K3 instant | an instant spell declaring `expects = "instant"` with a `school` | frame window, school check |
| K4 projectile | a cast declaring `expects = "travel", velocity = 20, school = "nature"` at 5, 20 and 30 yd | flight window, crit, miss at range |
| K5 swap | K4 with a target swap mid-cast | SENT pin, plate-only landing |
| K6 kill | K4 or K1 killing the target, with and without a press at the kill | kill tell, post-clear row, `TargetGone` |
| K7 churn | K4 with plate churn on the pinned mob | resolution, gone and revive |
| K8 identical | another source with our exact amount and school on the same mob | dedupe never merges two GUIDs; precision |
| K9 same-ms twins | two equal-amount hits from two sources on one target in the same ms, each on plate and target; and one hit on plate, target and soft | the twins dispatch twice; the single hit dispatches once; the single-token residual's rate per band (MEASURED) |
| K10 lag | melee row lag per session drawn from [0.4, 1.0] s (the Rogue session's 988, 837, 456 ms); cast events with +-50 ms latency jitter; DELAYED pushback on a hard cast; the first swing of a combat landing at 1.0 s | melee recall holds with the learned spread; the first swing does not teach the lag; no false credit from the jitter |
| K11 death in flight | our projectile in flight when another source's blow kills the target (`UNIT_DIED` from a foreign kill, no `PARTY_KILL` for us); our melee swing pending when the target dies | tickets close `closedDead` (not lost, not paid by a stale row); `TargetGone` fires once |
| K12 two live targets | tickets open on A and B (swap between them, a cast at each), rows from both; a DoT ticking on A after the swap to B | no cross-payment; A's ticks keep paying A's TICKS ticket; lost accounting per GUID |
| K13 lockstep partner | a same-school caster partner on our target with our cast time and amount band, phase-shifted by 0, 0.1 and 0.5 s, with its own crit and miss rates | divergent pairs per 100 measured; non-divergent twins cost nothing (recall and precision unchanged against K4); asserts the claim that only divergent pairs matter (4.2) |
| K14 our own twins | dual-wield hands landing in one ms with equal amounts; our Hunter pet hitting the target | both hands paid; the pet's rows foreign |
| K15 refused casts | a cast that fails for range or line of sight (SENT then FAILED, no SUCCEEDED); an unmapped success (a potion) | no ticket armed for the failed cast (a committed one closes uncounted, 3.2); the UNMAPPED ticket absorbs an avoid as nobody's |
| K16 stress | raid-40 density for 300 s | the 16-ticket pool never overflows, or each overflow is counted and the oldest closes lost; the 64-slot unit pool evicts only released GONE or DEAD units; the dedupe ring never drops a non-duplicate; no allocation over the run (the `tests/Game/harness/alloc_spec.lua` pattern) |
| K17 combat end | `PLAYER_REGEN_ENABLED` with tickets open and units held; a `/reload` mid-fight (`I.Build` with an empty registry while rows keep arriving) | the reset is clean; no row after the reset pays a pre-reset ticket; nothing errors |
| K18 cleave and AoE | an AoE of ours hitting the target and two plates (one row per unit); a partner's cleave | our AoE pays one ticket, on the target only; its rows on the other units are counted `aoeOther` (3.4 step 5) and never lost; the partner's cleave stays foreign |
| K19 swap during ticks and a strike | swap away before a strike lands, then back; swap away while a DoT ticks on the old target | pins hold: the strike pays its pinned GUID; the ticks pay the old target's TICKS ticket |
| K20 replay fixtures | every saved capture (wrath a, b and c-swap, rogue b, rogue kill-events, druid moonfire) replayed through the real sources (6.3) | the exact credits per capture (6.3), so the suite is anchored on the game, not only on the model |

Bands (other sources on our target and nearby; foreign outcomes per second as measured today):

| Band | Roster | Status |
|---|---|---|
| solo | none | GATED |
| party-light | 1 melee + 1 caster (today's party, about 1.3-1.8 foreign outcomes/s) | GATED |
| busy 5-man | 3 melee + 2 casters + 2 pets | GATED |
| raid 12, 25, 40 | the `group_spec.lua:45-53` mix scaled | MEASURED only (printed, not asserted) |

Metrics, per kind x band, all against tickets:

- recall: own tickets paid by their own row / own tickets that had a row in truth. Missed = own tickets paid by nothing.
- precision: false credit = tickets paid by a row that truth says is not theirs, per 100 paid tickets.
- foreign leak: foreign rows that paid any ticket, per 100 foreign rows.
- lost reported: tickets the engine counted lost that truth says had no row (should equal the truth's lost count).
- divergent: divergent pairs per 100 own tickets, and how long each stayed open (the time a band would stay wide).
- staged: `Obs.Crit` and `Obs.Avoided` staged for the right cast / staged in truth.

Floors: the first clean run sets each gated cell's floor (recall, staged at or above; false credit, foreign leak at or
below). Floors only move up, except with a named cause written beside the number and the owner's ruling. Raid cells
print their numbers and assert only that the run finished, as `group_spec.lua:45-53` does today. K10-K20 get their own
floors from their first clean run under the same rule; K13's divergent rate and K16's overflow count are reported
beside their floors.

The invariant sweep: `tests/Game/harness/detect_sweep_spec.lua` (#slow) runs seeds 1..N over lag x jitter x density x
partner phase and asserts on every run, whatever the score:

- a row pays at most one ticket;
- per ticket, rows paid <= `owed` at opening;
- conservation: opened = paid + provisional-closed + refreshed + closedDead + closedGone + lost + expired + none +
  unpinned + cast-stopped + overflow + combat-end + still open (every close in 3.6 counted once);
- no ticket is paid by a row whose resolved GUID differs from the ticket's;
- no row is dispatched twice by the registry.

It prints the metric surface (every counter of 3.6 and 2.7, per band) for each run.

The pending-cast gap: today's group runs never exercise a pending cast, because the oracle press is not
`startsCombat` (`scenarios.lua:207-213` presses "CAST"). The fake spec declares an expectation for each of its
abilities: `expects = "instant"` with a `school` for the instant spender, `expects = "travel", velocity = 20,
school = "nature"` for a new `startsCombat` hard cast, `expects = "strike"` for the strike, `expects = "none"` for a buff, one
ability with no `expects` so the default mapping keeps a test, and one with a malformed `expects` so the validation
fallback does. K3 and K4 press the `startsCombat` ones, so every band runs spell tickets. TICKS runs a
Moonfire-shaped case (direct hit plus four ticks), including a refresh that resets the schedule (the old ticket closes
`refreshed`, the new schedule pays). CHANNEL gets unit tests against the harness's own tick model only, marked
untested (U9's channel half deferred by owner ruling).

### 6.3 Fixtures from the captures

`tools/vslog_fixture.lua` today parses `PLAYER_SWING`, `UNIT_COMBAT` and casts and raises on anything else
(`tools/vslog_fixture.lua:1-8`). It learns `SC_*` lines (castGUID, castBarID columns as in the captures' README),
`TARGET` lines (GUID or none) and skips `NOTE` lines. Then:

| Capture | Fixture | Replay asserts |
|---|---|---|
| b | `tests/Game/harness/fixtures/wrath_b.lua` | every Wrath WOUND pays its ticket (14 of 14 against 0 today); the 783 ms MISS pays as `SPELL_MISSED` and stages `Obs.Avoided`; `bg[7]` does not rise; each kill fires the tell and `TargetGone`; the 74805 killing blow (plate and soft only) pays |
| c | `tests/Game/harness/fixtures/wrath_swap.lua` | the 216184 plate-only landing pays the ticket pinned at SENT to the old mob; the `targettarget` echoes are ignored; the 219922 post-clear row pays |
| a | `tests/Game/harness/fixtures/wrath_a.lua` | the 667 ms CRITICAL stages `Obs.Crit`; the 97891 MISS (517 ms after a 30 yd cast) is foreign once the GUID has a learned lag (3.4's example), and pays the 97374 ticket only under the first-ticket rule |
| rogue b | `tests/Game/harness/fixtures/rogue_b.lua` | each Sinister Strike WOUND pays its FRAME ticket within 2 ms; the life-steal school-32 row at 2250 is foreign; the white hits pay their swings (the first at 989 ms without teaching the lag); Eviscerate's killing row pays before the clear |
| rogue kill-events | `tests/Game/harness/fixtures/rogue_kill.lua` | `PARTY_KILL`, `UNIT_DIED` and `PLAYER_TARGET_DIED` mark the unit DEAD and ours; the 4820 killing WOUND on `softinteract` pays the 4364 swing; the school-32 proc at 2765 is foreign; the two foreign `UNIT_DIED` mark their units if known |
| druid moonfire | `tests/Game/harness/fixtures/moonfire.lua` | each direct hit pays its FRAME ticket; every tick pays the TICKS ticket on schedule; the refresh closes the old ticket `refreshed` and the new schedule pays; the kill closes the remaining ticks `closedDead` |

The soft-targeting log was not saved in full; its findings become the churn and Action Targeting knobs (6.1 rows 8 and 9), and probe U2 was answered by the Rogue auto-target capture instead.

## 7. Migration

| Consumer | Stops doing | Does instead |
|---|---|---|
| Rows (`Game/Events/Rows.lua`) | its own `UNIT_COMBAT` handler and the `unit ~= "target"` filter (`:443-444`); `UnitGUID("target")` pins (`:338`, `:362`); the `act*` ring (`:108-111`); school 1 in spell rows (`:300`, `:304`); silent cast expiry (`:597-609`) | an `I.Units.OnRow` listener; pins from `I.Units.Pin` and the SENT pin; the ticket pool, one ticket per commit; the expectation's school; lost counters. Today's paths become kinds: the swing scoring (`:252-269`, `:375-402`, `:479-549`) is MELEE; the on-next-swing replacement (`:329-332`, `:351-361`) is STRIKE; the cast frame and avoid windows (`:458-461`, `:497-499`) are FRAME (`"instant"`, also the default type of a `startsCombat` ability); `unmappedT` and `another()`'s unmapped half (`:54-55`, `:163-166`, `:344-346`) are UNMAPPED |
| Attackers (`Game/Events/Attackers.lua`) | `Plain(api, api.UnitGUID(tok))` in `recheck` (`:81`); clearing a plate's GUID itself (`:110-115`); `L.target` from its own read (`:116-121`) | `I.Units.Bound(i)` for the GUID; keeps its own `UnitIsUnit`, `UnitCanAttack`, `UnitAttackSpeed` reads and its clocks; still handles `unit == "player"` rows itself |
| Target (`Game/State/Sources/Target.lua`) | `UnitGUID("target")` in `swap` (`:55`); `TargetDamage` from the `target` token only (`:139-143`) | `I.Units.Bound(1)`; `TargetDamage` from OnRow rows whose GUID is the current target's; `TargetGone` on OnGone DEAD for a GUID holding a memory slot; poll 4 reports `I.Units.Dead` |
| Casts (`Game/State/Sources/Casts.lua`) | `I.sentGUID = UnitGUID("target")` (`:31-35`) | `I.sentGUID = I.Units.Pin(api, t)` with the SENT's castGUID kept beside it; `SPELL_CAST_START`/`SUCCESS` destination from that pin (`:47`, `:61`) |
| Nameplates (`Game/State/Sources/Nameplates.lua`) | nothing removed | poll 5's plain `UnitIsDead` (`:36-40`) also reports `I.Units.Dead` for a bound plate |
| Now (`Game/State/Families/Now.lua`) | nothing | its build (`:318-333`) also precompiles `expects`, `velocity`, `school` and the resolved aura's `tick_time`, `duration` and `dot` per ability, applies the default type and validates (5.3) |
| TargetHealth (`Game/State/Families/TargetHealth.lua`) | nothing | receives `TargetGone` on kills; its header's stale secrecy note (`:10-11`) is corrected |
| LibTTD (later) | its target-only feed | an OnRow listener keyed by GUID, deduplicated per ms |

Hekili's own handler sees `SPELL_DAMAGE` rows for casters for the first time. The CLEU handler calls
`ns.updateTarget( destGUID, time, amSource, spellID )` for every direct damage row on a hostile destination
(`Engine/Sim/Events.lua:1735-1743`, `direct_dmg_events` `:1388-1392`). Casters' targets now enter Hekili's enemy
tracker the way melee targets already do through `SWING_DAMAGE`. Consequences: `active_enemies` and the target-count
lines of caster APLs can read higher when a caster hits several mobs in turn, and Hekili's own `time_to_die` tracker
gets samples it never had. Rows keep slot 16 (overkill) at 0, so the overkill branch (`:1737-1739`) never eliminates a
unit. The wowsims replay floors of Balance, Warlock, Mage, Elemental, Priest and Hunter must show the effect; any change
in an AoE line's count gets its named cause in the gate report.

## 8. Open questions as ledger probes

Each becomes a row in `docs/dev/ingame-ledger.md` with the capture that closes it.

| ID | Question | Capture that closes it |
|---|---|---|
| U1 (deferred, owner ruling 2026-10-22: not needed for the first build; the untested branches above stay as written and the engine takes the shapes on later) | RESIST, IMMUNE, ABSORB, EVADE row shapes: action, flag, amount, school; do they arrive as rows at all | `/vslog` with `UNIT_COMBAT` while casting a school the mob is immune to (an Elemental at a fire mob), and a mob that evades (leash) |
| U2 (closed 2026-10-22, Rogue capture) | Auto-target on cast with Action Targeting off. Answer: a spell with no target does not auto-target (the cast never commits: no SENT with a target). A melee ability does: `TARGET` 68 ms before `SC_SENT` (6998 to 7066); `SC_SENT`, `PLAYER_SWING` and `PLAYER_ENTER_COMBAT` in the same ms; `SUCCEEDED` +1 ms; the strike's WOUND +2 ms on `nameplate2` and `target`. So the SENT pin always has a target | `rogue-ss-autotarget-2026-10-22.log` |
| U3 (closed 2026-10-22, kill-events capture; closes O6 and T8) | Do `UNIT_DIED`, `PLAYER_TARGET_DIED` and `PARTY_KILL` fire for addons on Forever, with plain GUIDs. Answer: yes, all three, GUIDs plain; order on a white-swing kill: `PLAYER_SWING` and `PARTY_KILL` same ms, `UNIT_DIED` and `PLAYER_TARGET_DIED` +2 ms, `TARGET none` +4 ms; `UNIT_DIED` also for units others kill | `rogue-kill-events-2026-10-22.log` |
| U4 (closed 2026-10-22, druid-moonfire capture) | DoT ticks: does a periodic tick arrive as a WOUND on the victim's tokens, with which school. Answer: yes, a plain WOUND of the spell's school, no flag, every 3.0 s +- 50 ms from the application; a recast resets the schedule; the channel half moves to U9 | `druid-moonfire-2026-10-22.log` |
| U5 (closed 2026-10-22, recorder `/vslog plates` in combat) | Nameplate secrecy in combat. Answer: `UnitGUID`, `UnitIsDead`, `UnitCanAttack("player", plate)`, `UnitName`, `UnitLevel`, `UnitClassification` and `UnitReaction` are plain on nameplate tokens; `UnitHealth` and `UnitHealthMax` are secret. Caveat: two plates (our target and a passing mob), not a five-man pull; the secrecy rule is per API, so it is expected to hold | `/vslog plates` in combat |
| U6 (deferred with U1) | Partial resists: a WOUND with a RESIST flag and a reduced amount, or two rows | `/vslog` of a Shadow Bolt series on a mob with shadow resistance |
| U7 (deferred by owner ruling 2026-10-22, like U1 and U6; Frostfire Bolt keeps no `school`) | Two-school spells and wands: the school a Frostfire Bolt WOUND carries (20, 4 or 16); a wand's | `/vslog` of Frostfire Bolt and of Shoot with a non-physical wand |
| U8 (closed by owner ruling 2026-10-22: the client clears the target when it is killed, as a rule, not a user setting, whether or not a press is in flight; the registry treats the clear-on-kill as reliable, and the death events remain the primary tell) | The kill tell: is the target clear on a kill a client rule or a user setting; does it happen when no press is in flight | `/vslog` of a melee kill with no ability pressed, and the interface option in question |
| U9 (DoT half closed 2026-10-22 by the druid-moonfire capture; channel half deferred by owner ruling 2026-10-22; CHANNEL stays implemented, untested and unused by packs) | Channel row shapes: per tick, which tokens, action, flag, amount, school; whether a channel's ticks and a DoT's are told apart; needed before CHANNEL is trusted | `/vslog` of Arcane Missiles and Drain Life channels on solo mobs |
| U10 (owner-explained 2026-10-22, lag unmeasured: auto-attack turns on at once when an ability is used or `/attack` is pressed, and the first `PLAYER_SWING` is that first swing; its row's lag is one sample, 989 ms, so the first swing of a combat still does not teach the MELEE lag and uses the LR window) | The first white swing of a combat: does the first `PLAYER_SWING` after `PLAYER_ENTER_COMBAT` mark auto-attack turning on, or a swing with a longer lag (one sample: 989 ms against 452 ms for the next) | `/vslog` of ten pulls with auto-attack only, amounts on, `PLAYER_SWING`, `PLAYER_ENTER_COMBAT` and the target's `UNIT_COMBAT` |
| U11 (closed by owner ruling 2026-10-22) | Do the floating combat text settings delay `UNIT_COMBAT` rows? Answer: no. The Rogue session's white-hit lags (988, 837, 456 ms) are real row lags; the MELEE learned lag and spread absorb that range per session, and the Warrior's 474 +- 60 ms is a seed, not a constant | owner ruling |

## 9. Risks and what the gate must show

The gate for this central change is the full merge gate: `make gate` (which runs `make check`, including every
class's wowsims replay floors in its slow tier, and every loop tag with `make test-loop`), the flicker floors
(`tests/Game/harness/flicker_spec.lua`), the existing group gates (`group_spec.lua`), the new detection suite, and
the performance budgets of section 10 (the memory ceiling, the allocation checks and the `make bench-ta` floor).
Floors only move up except with a named cause: upward moves are expected for casters (projectile outcomes now pay);
any downward move needs a named cause written beside the number and the owner's ruling before merge.

| Risk | Why | What the gate must show |
|---|---|---|
| Wrong GUID after a swap | the live read wins for `target`; a stale echo with no matching plate row resolves to the new mob | K5 precision at its floor; the c fixture's swap pays the old mob |
| Over-merge in dedupe | two real identical rows on one GUID within 5 ms collapse into one | K8 recall at its floor in the busy band |
| Plate churn closes a live ticket | a plate-only pinned unit whose plate leaves for over 0.1 s goes GONE | K7 lost count at its floor; Snapshot `gone` in game |
| Wider spell windows take foreign rows | the [0, 1.65] s hard window for a first ticket on a GUID, and widened bands long after the last landing | party-light and busy K4 foreign leak at their floors; the school check and band hold it |
| Caster `active_enemies` rises | new `SPELL_DAMAGE` rows reach `ns.updateTarget` | wowsims replay floors of every caster class; a moved AoE decision gets its named cause |
| Melee behaviour drifts | the ring becomes the ticket pool | melee replay floors, `make test-loop` and flicker floors unchanged; `group_spec.lua` numbers unchanged |
| Allocation in a recurring path | new handlers on `UNIT_COMBAT` and the tick | `tests/Game/harness/alloc_spec.lua` and `make bench` show no new allocation |
| Kill tell misses melee kills | no FAILED without a press | K6 without a press: the death events mark the unit; the clear-on-kill is a client rule (U8, owner ruling), so the unit also ends through poll 5 or GONE |

## 10. Performance

Performance is a design constraint of the registry and the tickets, gated like the floors.

### 10.1 Memory

Every structure is a fixed pool allocated once at load (or at build, for the per-ability arrays). Estimates assume
Lua 5.1 on 64-bit: 16 bytes per array slot, about 56 bytes per table header, about 40 bytes per hash entry.

| Structure | Size | Estimate |
|---|---|---|
| Unit slots: `uGUID`, `uState`, `uTokens`, `uSeen`, `uLeft`, `uHeld`, `uFree`, `uOurs` | 64 x 8 arrays | 8.6 KB |
| GUID strings the slots keep alive after the client drops them | up to 64 x about 60 bytes | 3.9 KB |
| Token tables: `tokUid`, `tokPrev`, `tokAt`, `TOKENS` (array), `INDEX` (hash), the 44 token name strings | 44 x 4 + 44 hash + 44 strings | 6.2 KB |
| Tickets: `kind`, `ab`, `x`, `guid`, `uid`, `school`, `owed`, `period`, `at`, `lo`, `hi`, `ref`, `lr`, `avoid`, `state` | 16 x 15 arrays | 4.7 KB |
| Learned flight lag: `lagGUID`, `lagSpeed`, `lagE`, `lagSpr`, `lagT`, `lagN` | 16 x 6 arrays | 1.9 KB |
| Dedupe ring: 6 payload arrays x 4 groups, `dTok` 4 x 44 booleans | 24 + 176 slots | 3.5 KB |
| Per-ability arrays: `expKind`, `expDeclared`, `velocity`, `school`, `dot`, `tickAura`, `tickTime`, `tickCount`, `bandLo`, `bandHi`, `bandN` | 11 x up to 120 abilities | 21.6 KB |
| `CTX`, the listener arrays (`OnRow`, `OnGone`: a few functions each), the counters | fixed | 1.5 KB |
| Total | | about 52 KB |

There are no per-unit token sets: a unit keeps only its token count (`uTokens`), and each token keeps its unit.
`I.Units.Find(guid)` is a 64-step linear scan by string equality (interned strings compare by pointer). A GUID-keyed
hash would allocate as it grows, so there is none.

Hard ceiling: under 64 KB resident for the module. A headless spec measures `collectgarbage("count")` after a full
collect before and after loading the module and building a spec, and asserts the difference.

### 10.2 Allocation

No table, closure or string is created per event, per row or per poll after load. Token names map to integer ids once,
through the `INDEX` table built at load; nothing concatenates `"nameplate" .. i` at runtime. GUIDs are the client's own
strings, stored by reference and compared, never built or sliced. The existing allocation check
(`tests/Game/State/alloc_spec.lua`, with its helper `tests/Game/State/helpers/alloc.lua`, as
`tests/Game/harness/alloc_spec.lua` uses it) runs over a full K16 run and a 300 s solo run and asserts 0 bytes after
warm-up.

### 10.3 Time

| Path | Bound |
|---|---|
| Resolve | O(1): `INDEX[token]`, one `UnitGUID` read through `Plain`, the token's slot |
| Dedupe | at most 4 groups, each a payload compare and one token-array read |
| Match | at most `TICKETS` (16) candidates x 3 passes, each a scan for the least expected closure |
| Lifecycle sweep (per frame) | a fixed loop over `UNIT_CAP` (64) slots, skipped when no slot is in GRACE or DEAD-releasing (a pending count). Chosen over an intrusive list: 64 compares are cheaper than keeping links right, and the count makes the common frame free |
| Ticket expiry (per frame) | a fixed loop over 16 tickets (Rows loops 8 today, `Rows.lua:597-609`) |
| `Find(guid)` | 64 string compares; only on death events and `PARTY_KILL` |

Budgets: a row under 0.02 ms; a per-frame poll under 0.10 ms; the registry and tickets together under 2% of a frame at
60 fps (0.33 ms per frame) at the raid-40 design point of about 50 rows a second (today's measured raid mix is about
6 a second). Measured two ways:

- in game, with `Hekili:ProfileCPU` hooks on the `UNIT_COMBAT` dispatch and the per-frame tick (`src/Hekili/Hekili.lua:48`
  registers a function for the profiler; `Engine/Sim/Events.lua:179` already wraps handlers this way);
- headless, with a microbenchmark `make bench-ta` (a new target beside `make bench`, `tools/bench_ta.lua`) that feeds
  N synthetic rows over a K16-shaped population and reports rows per second and ms per row. Its number goes in the
  plan's gate as a floor that only moves up, except with a named cause.

### 10.4 Scaling

| Grows with | What grows | What does not |
|---|---|---|
| Density (rows per second) | resolve, dedupe and match work, linearly | memory |
| Plates (token churn) | rebinds and the lifecycle sweep's pending count | memory: at most 44 tokens |
| Pack size | the per-ability arrays, once at build | per-row work: tickets carry an ability index |
| Fight length | nothing: pools are fixed, paid and lost counters are integers | everything |

At saturation nothing allocates or errors. Ticket overflow closes the oldest open ticket as `overflow` (counted).
Unit overflow evicts the oldest released GONE or DEAD unit (2.6). Dedupe ring overflow drops the oldest group. K16
asserts the counters and the allocation check.

### 10.5 Snapshot cost

The Snapshot lines for units and tickets (2.7, 3.6) are built only when a snapshot is taken, through `I.OnSnapshot`
(as `Rows.lua:623-650` does today). String building is allowed there and nowhere else in this module.

### 10.6 Review focus for the plan

Each task review checks for a hot path that builds a string or a table: any concatenation, `string.format`, table
constructor, closure or `{...}` inside an event handler, a row dispatch, a poll or the per-frame tick.

## Decisions made in this spec

| # | Decision | Reason |
|---|---|---|
| 1 | A unit's tokens stay resolvable while any open ticket is pinned to it, plus `GRACE` = 0.1 s (a floor) after the last one closes; a token rebound to another unit resolves to the old unit only for rows that match an open ticket's queue on it | a melee killing blow lands 370 ms after the clear (Rogue capture); projectile kills land 11-36 ms after it |
| 2 | `DUP_WINDOW` = 0.005 s, ring of 4 groups, each with a token set (a fixed boolean array over the 44 token indices); a row whose token is already in the matching group starts a new group and is dispatched | one outcome's fan-out spans up to 1 ms and never repeats a token (captures a, b, c), so equal twins on a shared token stay two |
| 3 | A rebound token's row that matches another token's payload within `DUP_WINDOW` is a duplicate, unless its token is already in that group | stops a stale `target` echo after a swap from paying the new mob |
| 4 | `UNIT_CAP` = 64 slots, LIVE never evicted | 44 tokens can be LIVE at once; 20 spare slots for grace and dead units |
| 5 | Token set: target, focus, nameplate1-40, softenemy, softinteract; `player` stays with Player and Attackers | the victim-side tokens of hostiles; `targettarget` rows are echoes; `softinteract` rows exist with Action Targeting off (the corpse), so it stays; only the soft-enemy events depend on the setting |
| 6 | Primary kill tell: `UNIT_DIED` (plain victim GUID) marks the unit DEAD at once, `PLAYER_TARGET_DIED` the current target; `PARTY_KILL` with killer equal to our GUID marks it our kill. Fallback, only when the client refused the death events: any player FAILED within 0.010 s before a clear to none | measured: all three fire with plain GUIDs, 0-2 ms after the killing swing, and `UNIT_DIED` covers units others kill; FAILED misses melee kills |
| 7 | An unpaid ticket on a unit we killed (`PARTY_KILL`) closes as `closedDead` and counts `T.closedOurs`, never lost | our kill is known exactly; LibTTD and the lost accounting read it |
| 8 | A ticket on a dead unit stays open until paid or its own window ends; unpaid, it closes as `closedDead`, not lost | a melee killing blow arrives about 370 ms after the clear and must still pay |
| 9 | `TICKETS` = 16 | flight windows of up to about 2.1 s plus two hands need more than today's 8 |
| 10 | A ticket opens for every commit (every `PLAYER_SWING`, every player success mapped or not, a hard cast at SENT); the kind decides how it closes | one uniform record; no engine assumption about what a spell does |
| 11 | `expects` is a plain string from a fixed set, each mapped to one engine kind whose matching and closure rule lives in the engine; the engine reads the ability's other fields per type: `"none"` (none), `"instant"` (`school`), `"travel"` (`velocity`, `school`), `"melee"` (the hand from `PLAYER_SWING`; the engine's own, not declarable), `"strike"` (`onNextSwing`), `"ticks"` (`school`, optional `velocity`, and the aura's `tick_time`, `duration` and `dot = "debuff"`), `"channel"` (`school`, the aura's `tick_time`; opt-in only); a plain string and nothing else; `school` is a name from the core enum `ns.SCHOOL` (`"physical"`, `"holy"`, `"fire"`, `"nature"`, `"frost"`, `"shadow"`, `"arcane"`), compiled to its mask at build, never a number | packs declare data on the ability; each rule is written and tested once; the DB2 check reads the same fields |
| 12 | Default when `expects` is absent: `"strike"` if `onNextSwing`, else `"instant"` if `startsCombat`, else `"none"`; a default-mapped ability never opens a TICKS ticket; `channeled` abilities follow the same rule, and CHANNEL is opened only by an explicit `expects = "channel"` | reproduces today exactly: Rows holds only `startsCombat` and `onNextSwing` abilities, with these windows; channels keep their floors until a pack opts in |
| 13 | Validation at build: an unknown `expects`, a type missing a required field, an unknown `school` name, or a `"ticks"` or `"channel"` whose aura is missing or has no `tick_time` (and for `"ticks"`, no `dot = "debuff"`) is reported once through the build warning path (`Hekili:Error`, counted like `I.nowErrors`) and the ability falls back to its default type | a typo never silently changes attribution; floors hold |
| 14 | `CTX` fields: `t`, `guid`, `hand`, `rMax`, `lagE`, `lagSpr`, `lagAge`, `rangeLo` (optional, 0 absent), `bandLo`, `bandHi`, `bandN` | what the engine knows at commit; no range is assumed readable |
| 15 | A default-type ticket on an ability with no `school` field carries school ANY: any WOUND or avoid in its window pays, never lost; a declared type's nil school means only an avoid pays | keeps the default mapping exactly today's while letting a pack declare an aura-only cast |
| 16 | Unmapped successes open an UNMAPPED ticket: `UNMAPPED_WINDOW`, no owed row, any GUID, absorbs an avoid or crit as nobody's | today's `another()` unmapped rule as a generic ticket; replaces `unmappedT` |
| 17 | `owed`: rows still owed; each paid row decrements it, 0 closes the ticket; unpaid `owed` at expiry counts as lost | one counter covers one hit, N ticks and open-ended channels |
| 18 | A `school` of nil means the hit makes no row of ours: only an avoid pays, expiry is not lost (a pure aura with no damage) | an aura-only cast needs no handler of its own |
| 19 | Backed by captures or measured logs: NONE, FRAME, FLIGHT, MELEE, STRIKE, TICKS (druid-moonfire capture). Unprobed: CHANNEL, implemented but untested and unused by packs (U9's channel half deferred by owner ruling) | no channel row has been captured yet |
| 20 | FLIGHT hard window `[0, rMax / speed + TOL]` from the success, always; `TOL` = 0.15 s; `rMax` 0 means 40 yd; the plain bracket's `lo` may only raise the lower bound, less `CLOSE x age` | the engine cannot read an up-to-date range in combat; the five max-range samples fit [0, 1.65] s |
| 21 | School check by equality with the declared school's compiled mask | no bit operations in core; two-school rows are deferred (U7, owner ruling) |
| 22 | Amount band [0.6 x lo, 1.6 x hi] after 3 clean wounds | spell damage varies more than weapon damage; procs and crits halved stay inside |
| 23 | Consumption order: rows online in arrival order after dedupe; candidates of the row's queue in expected-closure order; passes (a) narrow, (b) widened, (c) hard window for tickets with no record; first match pays; MELEE's LR decides among MELEE candidates at a pass | the order decides correctness; FIFO per queue falls out of it |
| 24 | A mapped ticket with no pin opens with `guid` "" and counts `unpinned`, not lost | it can match no row; today its rows are dropped anyway |
| 25 | Until 4.2 is built, a divergent row emits its row but stages nothing | stays on the floor's safe side, as today's two-casts rule |
| 26 | Build trigger for 4.2: `divergent` over 1 per 100 paid tickets in a five-man run | a rate that would show as flicker; below it the union is not worth its cost |
| 27 | DB2 check is a dev-only `make spell-data-check` over the declared `velocity` and `school` fields; it maps SchoolMask to a name through `ns.SCHOOL` and compares names | CI has no DB2 file; the pack's declared name is what is checked |
| 28 | Registry dispatches rows through `OnRow`; Rows registers before Target | one resolution and dedupe for every consumer; tickets see a row first |
| 29 | Learned flight lag: `LAG_CAP` = 16 records per (GUID, speed): `lagE` (last observed lag), `lagSpr` (EMA spread, 0.25 rate, [0.02, 0.4]), `lagT`, `lagN`; taught by a clean pass (a) or (b) payment; oldest `lagT` evicted | the same mechanism as the global melee lag, keyed per unit because flight lag is distance; the last lag tracks a closing mob |
| 30 | Widening: `b = max(TOL, 2 x lagSpr)`; `down = max(b, (CLOSE / speed) x d)`, `up = max(b, (CLOSE / 2 / speed) x d)`, `d` = time since the last landing, `CLOSE` = 7 yd/s, clipped to the hard window; no record: the whole hard window, uniform | the band grows as fast as a running mob can change the lag |
| 31 | FIFO per queue (kind, school, speed, GUID); never across queues | one queue's rows arrive in cast order unless the distance shrinks faster than the projectile (20 yd/s or more) between casts, which no run does |
| 32 | Cascade bound: a lost ticket shifts its queue by at most one row, only while casts are closer than the narrow band or before the first record, until it expires at `H` or closes on the kill tell or GONE; shifts that change a belief count as `divergent` | a shift between two own same-school hits changes nothing; only divergent outcomes matter |
| 33 | Pass (c), the hard window, is open only to tickets with no learned record | otherwise a far-off row (capture a's 517 ms MISS) would still be charged to a cast whose learned lag excludes it |
| 34 | An open ticket's phase (Ahead, Due, Widened, Overdue) is computed from the row's time against its expected closure and bands at each evaluation, never stored; Due, Widened and Overdue are passes (a), (b) and (c) | no state to keep in step and no transition event to miss; one vocabulary for the passes and the phases |
| 35 | A declared `"instant"` or `"travel"` ability whose resolved aura has a `tick_time` and `dot = "debuff"` opens the direct ticket and a TICKS ticket pinned to the same GUID, anchored at the direct row (else the success); `"ticks"` alone opens only the TICKS ticket (same aura requirement) and may declare `velocity` (its avoid then uses the FLIGHT window and bands, its anchor the success plus the learned flight lag, else plus `rMax / speed / 2`); no ability-level flag | the DoT marker already exists upstream on the aura; a heal-over-time or a self buff with a `tick_time` never opens a ticket |
| 36 | TICKS matches by school, GUID and schedule only: period = the aura's `tick_time`, count = `floor(duration / tick_time)`, tick `k` at application + `k x period`, band +- 0.1 s, widened by `rMax / speed / 2` for a `velocity` TICKS ticket with no learned lag until its first tick is paid (the anchor then snaps to that tick); no amount band; a tick outside every band is foreign | measured jitter +- 50 ms; ramping DoTs vary 3x in amount, so the schedule is the discriminator; an unknown flight lag shifts the whole schedule once |
| 37 | A new application of the same ability on the same GUID closes the old TICKS ticket as `refreshed` (unpaid `owed` not lost) and opens a new one from the new application | measured: a recast resets the schedule and the old ticks never arrive |
| 38 | Memory: every structure a fixed pool built at load or build, about 52 KB estimated; hard ceiling 64 KB resident, asserted with `collectgarbage("count")` in a headless spec | fixed pools make the cost known and constant |
| 39 | Allocation: zero tables, closures or strings per event, row or poll after load; asserted over a K16 run and a 300 s solo run | the project's performance rule; recurring paths must not feed the collector |
| 40 | Time budgets: a row under 0.02 ms, a per-frame poll under 0.10 ms, the module under 2% of a 60 fps frame at about 50 rows a second | a raid-40 design point with headroom over today's measured 6 rows a second |
| 41 | The lifecycle sweep is a fixed 64-slot loop gated by a pending count, not an intrusive list | simpler and free on most frames |
| 42 | `make bench-ta` (`tools/bench_ta.lua`) reports rows per second and ms per row; its number is a gate floor that only moves up | a regression shows as a number, not a feeling |
| 43 | Ticks read the aura the packs already declare, resolved as `ability.cycle or ability.aura or ability.key`: period `tick_time`, count `floor(duration / tick_time)`, and upstream's `dot = "debuff"` marks a DoT; no `tickPeriod`, `ticks` or `dot` ability fields | DRY with upstream: the sim resolves and reads the same fields (`State.lua:676`, `:2283-2285`, `:3302-3312`; `Events.lua:1609`) |
| 44 | A function-valued `duration` or `tick_time` is called at commit in its own environment (Hekili's state), as the sim calls it; numbers compile at build | rank-dependent durations (Moonfire) are functions today; rebinding their environment would move the sim's |
