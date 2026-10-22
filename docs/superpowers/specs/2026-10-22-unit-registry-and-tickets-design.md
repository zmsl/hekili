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
`uLeft[u]` (the time its last token left).

| State | Value | Meaning | Rows resolve to it |
|---|---|---|---|
| FREE | 0 | slot unused | no |
| LIVE | 1 | at least one token bound | yes |
| GRACE | 2 | no token bound, left less than `GRACE` ago | yes |
| GONE | 3 | no token bound for `GRACE` or more | no |
| DEAD | 4 | the kill tell or a plain `UnitIsDead` named it | yes, for `GRACE` after the death |

Dedupe memory: the last `DUP_N` = 4 resolved rows (`dT`, `dUid`, `dAct`, `dFlag`, `dAmount`, `dSchool`), a ring.

All arrays are filled at load. Event handlers write numbers, booleans and the plain GUID strings the client handed
them. No table, closure or string is made after load.

### 2.2 Events consumed

| Event | Handler | Note |
|---|---|---|
| `PLAYER_TARGET_CHANGED` | rebind token 1 from `Plain(api, api.UnitGUID("target"))` | today read by `Target.lua:55` and `Attackers.lua:116-121`; both take it from the registry instead |
| `PLAYER_FOCUS_CHANGED` | rebind token 2 | |
| `NAME_PLATE_UNIT_ADDED` | rebind the plate's index from its live GUID | |
| `NAME_PLATE_UNIT_REMOVED` | unbind the plate's index; if the live read still answers (soft-targeting log: it does), check it equals the bound GUID first | a mismatch rebinds to the read GUID, then unbinds |
| `PLAYER_SOFT_ENEMY_CHANGED`, `PLAYER_SOFT_INTERACT_CHANGED` | rebind 43 / 44 | registered through `S.On`; a client that refuses them leaves them in `E.STUB` (`EventFacade.lua:93-95`) and nothing depends on them |
| `UNIT_COMBAT` | resolve, dedupe, dispatch (2.4) | the one non-player `UNIT_COMBAT` entry point |
| `UNIT_SPELLCAST_FAILED` (`player`) | records `failT` for the kill tell (2.5) | any castGUID, including `Cast-2-0-0-0` key spam |
| `UNIT_DIED`, `PLAYER_TARGET_DIED` | mark the plain GUID DEAD when delivered | opportunistic: the event-facade spec lists them as observed (`docs/superpowers/specs/2026-10-15-virtualstate-event-facade.md:289`, O6), the 2026-10-22 captures did not register them; probe U3 |
| `PLAYER_REGEN_ENABLED` | reset (2.5) | |

Every payload slot reaches these handlers through `Plain` already (`EventFacade.lua:221-226`, `Game/State/Sources/Sources.lua:18-23`).
Every `UnitGUID` and `UnitIsDead` read the registry makes goes through `Plain` as well, and a nil answer means "no
answer", never a value.

### 2.3 Token to GUID resolution

`I.Units.Resolve(api, i, t)` answers the GUID a row on token index `i` at time `t` is about, and its unit slot. Order:

1. Live read: `g = Plain(api, api.UnitGUID(TOKENS[i]))`. A plain string is the answer. If it differs from the token's
   binding, the registry rebinds the token first (it heals a missed event).
2. Registry fallback within grace: the live read is nil (no unit, or secret) and the token's previous slot left it less
   than `GRACE` ago (`t - tokAt[i] < GRACE`) and that slot is not GONE: answer the previous slot. This is the post-clear
   killing blow (capture b 42067 on `target` after `TARGET none` at 42048).
3. Otherwise nil: the row is unresolved, counted (`U.unresolved`), and no consumer sees it.

A token that was rebound to a different live GUID less than `GRACE` ago is the swap case. The live read wins (rule 1),
with one exception handled by the dedupe (2.4): if the same payload already arrived on another token within
`DUP_WINDOW`, the row is a duplicate of that one. This catches a stale `target` echo right after a swap, which the
report flagged (risk: a stale `target` WOUND after a swap counts toward the new target).

`GRACE` = 0.1 s: the slowest post-clear row seen is 36 ms (capture c 219886 to 219922); 0.1 s is about three times that.

### 2.4 Dedupe and dispatch

One outcome arrives once per token naming the victim, in the order plate, target, soft (`tests/Game/harness/observer.lua:81-95`
encodes the same order from the earlier logs; capture b 42067-42068 confirms it). The fan-out can span 1 ms.

A resolved row is a duplicate when a ring entry has the same slot, `act`, `flag`, `amount` and `school`, and
`|t - dT| <= DUP_WINDOW` (0.005 s). A row whose token was rebound less than `GRACE` ago and whose payload matches a ring
entry within `DUP_WINDOW` on any slot is also a duplicate (the swap exception of 2.3). Duplicates are counted
(`U.dup`) and dropped. A row that is not a duplicate goes into the ring, refreshes `uSeen`, and is dispatched once to
each listener registered with `I.Units.OnRow(fn)`, in registration order:
`fn(t, guid, uid, act, flag, amount, school)`.

Listeners register at load. Rows (tickets) registers first, then Target (`TargetDamage`), then any later consumer
(LibTTD). Dispatch is a loop over a load-time array of functions: no allocation.

### 2.5 Lifecycle

- Seen: a binding or a resolved row sets `uSeen = t`. A GUID not held takes a FREE slot, else an evicted one (2.6).
- Unbound: when `uTokens` drops to 0 the slot goes to GRACE with `uLeft = t`.
- Gone: the per-frame tick (`L.OnTick`, run from `EventFacade.lua:239-246`) moves a GRACE slot to GONE once
  `t - uLeft >= GRACE`, and calls each `I.Units.OnGone(fn)` listener: `fn(uid, guid, GONE, t)`. A GUID bound again
  later (plate churn, 0.5 s) takes LIVE again in the same slot if it was not evicted; nothing closed earlier reopens.
- Dead: any of these marks the slot DEAD at `t` and calls the OnGone listeners with `DEAD`:
  - the kill tell: `PLAYER_TARGET_CHANGED` to none within `KILL_TELL` = 0.010 s after any player
    `UNIT_SPELLCAST_FAILED`; the previous target's slot dies. Seen in all four kills of captures b and c (FAILED to clear:
    16019 to 16022, 42045 to 42048, 74794 to 74796, 219884 to 219886).
  - a plain `UnitIsDead(token) == true` on a bound token. The existing polls already read it: `Target.lua:84` (poll 4) and
    `Game/State/Sources/Nameplates.lua:36-40` (poll 5). They report to `I.Units.Dead(uid, t)`; the registry adds no read.
  - `UNIT_DIED` or `PLAYER_TARGET_DIED` with a plain GUID, when the client delivers them.
  A DEAD slot still resolves rows for `GRACE` after the death, so the killing blow pays its ticket.
- Reset: `PLAYER_REGEN_ENABLED` frees every slot with no bound token (OnGone with `RESET` first) and clears the dedupe
  ring and `failT`. Bound units stay: the target is still the target after combat.

### 2.6 Capacity and eviction

At most 44 tokens are bound, so at most 44 slots are LIVE; 64 slots always leave 20 that are GRACE, GONE, DEAD or FREE.
A new GUID takes a FREE slot, else the GONE or DEAD slot with the oldest `uSeen`, else the GRACE slot with the oldest
`uSeen`. A LIVE slot is never evicted. Evictions are counted (`U.evicted`). The search is a 64-step loop.

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
| `kind` | the expectation kind (5.1): NONE, FRAME, FLIGHT, MELEE, STRIKE, TICKS, CHANNEL, or the engine's own DEFAULT and UNMAPPED |
| `ab` | the ability index (0 for a swing or an unmapped success): the integer reference to the ability's precompiled expectation (`A.expKind[ab]` and its numbers); no closure is stored |
| `x` | hand (1 main, 2 off) for a swing; the spell ID for a spell (the row's spell ID) |
| `guid`, `uid` | the pinned victim and its registry slot ("" and 0 when nothing was pinned) |
| `school` | the school the expectation names (0: none; the kind then owes no WOUND, 5.1) |
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
ability's learned amount band (`bandLo`, `bandHi`, `bandN`, 3.4). Only the `expects` escape hatch (5.3) reads it from
pack code. No table, closure or string is made per event.

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

At opening the engine takes the ability's expectation (`A.expKind[ab]` and its numbers, or the value the escape hatch
returns for `CTX`) and fills `kind`, `owed`, `period`, `school`, `lo` and `hi` by that kind's rule (3.3). Kind NONE
resolves the ticket at commit (a buff, a seal, anything that owes no row): it closes at once, counts `T.none` and never
matches a row.

An ability with no `expects` gets kind DEFAULT, which is today's behaviour exactly: for an ability that `startsCombat`
or is `onNextSwing` (the set Rows holds today, `:347`), an open ticket with today's windows (3.3), any school, owed 1,
and no lost count on expiry; for any other mapped ability, today holds nothing, so DEFAULT resolves at commit as NONE
does. Every pack's floors therefore hold until it declares data.

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
| TICKS(period, ticks, school) | tick `j` at `at + j x period +- TOL` | a WOUND of `school`; the application's avoid inside `LandWindow(1)` closes it with nothing owed | on the last tick, on the removal of the ability's debuff on that GUID (the aura row `L.Aura` emits, `Game/Events/CombatLog.lua:171`), or expiry |
| CHANNEL(period, school) | tick `j` at `at + j x period +- TOL` | a WOUND of `school` | on `Obs.ChannelStop` for the ability (`Casts.lua:130-139`) |
| DEFAULT | as FRAME | any WOUND or avoid, as today | on its row, or expiry, never lost |
| UNMAPPED | `UNMAPPED_WINDOW` | an avoid or crit nobody took (3.4 step 5) | expiry, never lost |

A school of nil means the hit makes no row of ours: the kind then takes only an avoid in its window, and its expiry is
not a lost resolution (Serpent Sting's application, 5.4).

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

### 3.4 Paying (the consumption order)

The order in which rows are consumed by tickets decides correctness. The algorithm, exactly:

1. Rows are consumed online, one at a time, in arrival order, after the registry's dedupe (GUID + ms, 2.4). Several
   distinct rows at the same ms are processed in token order. A WOUND 0 is processed before the damage row of the same
   strike frame: it marks `lastW0` and pays nothing (today, `Rows.lua:454-457`), which arms the foreign strike frame
   rule (`:481`) for the row after it.
2. Candidates for a row are the open or provisional tickets of its queue: `guid` equal to the row's, and a kind
   compatible with the row. An avoid can pay any kind that still owes a row. A WOUND can pay only a kind whose school
   equals the row's (MELEE, STRIKE and DEFAULT: as today, school 1 for MELEE and STRIKE, any for DEFAULT), and only
   once it fits the ability's amount band (below). A nil-school ticket is paid only by an avoid.
3. Each candidate has an expected closure time: `at + lagE` for FLIGHT (`at + H / 2` before its first record),
   `at + L.med[hand]` for MELEE (the learned landing lag, `Rows.lua:67`), `at` for FRAME, STRIKE and DEFAULT,
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

Bands per kind:

| Kind | (a) narrow | (b) widened | (c) hard |
|---|---|---|---|
| FLIGHT | `lagE +- b` | `[lagE - down, lagE + up]` | `[0, H]` (no record only) |
| MELEE | the core band, within 2 `spr` of the median (`Rows.lua:367-369`) | the LR window `[0, w]` (`:252-269`) | as (b) |
| FRAME, STRIKE, DEFAULT | `SAME_FRAME` | WOUND: `CAST_WINDOW`; avoid: `LandWindow(1)`, or `CAST_WINDOW` while `bg[7] >= FOREIGN_AVOIDS` (GAP AX) | as (b) |
| TICKS, CHANNEL | tick time `+- TOL` | tick time `+- 2 x TOL` | as (b) |

MELEE inside the frame: when the first match at a pass is a MELEE ticket, the existing likelihood ratio decides among
all MELEE candidates that match at that pass (LR = q x f / lambda, the bar `THETA` for avoids and `theta[k]` for wounds,
the veto, `:487-495`). Below the bar, MELEE does not match at that pass. At a tie in pass (a) between a FRAME ticket
and a MELEE ticket for a white avoid or crit, MELEE wins, keeping today's precedence (`:464-478`).

Where this differs from today: Rows tries a fresh cast's frame first and then any avoid within the cast window
(`:458-461`), then the swing LR (`:487-495`), then a white wound within `CAST_WINDOW` for the cast (`:497-499`), always
the oldest cast first (`:146`). The new order replaces commit order with expected closure and adds the passes; for
abilities on DEFAULT and for swings the bands are today's windows, so the outcome is the same.

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
| resolved at commit | kind NONE, or DEFAULT for an ability Rows does not hold today | nothing | `T.none` |
| paid out | `owed` reached 0 (3.4) | 3.5 | `T.paid[kind]` |
| signal | the kind's non-row close (3.3): TICKS on its debuff's removal, CHANNEL on its stop | nothing | `T.paid[kind]` |
| cast stopped | a committed hard cast's FAILED or INTERRUPTED | nothing | none |
| window expiry | `now > hi` with `owed > 0`, in the per-frame tick (today `:597-609`) | MELEE: `SWING_MISSED` if provisional, else `SWING_DAMAGE` amount 0 (kept: the swing timer reads it); others: nothing | `T.lost[kind] += owed`; DEFAULT, UNMAPPED and a school-nil kind count `T.expired` instead |
| kill | OnGone with DEAD for its `uid`; at death + `GRACE` if still open, so the final row can pay first | as expiry | `T.closedDead` |
| gone | OnGone with GONE for its `uid` | as expiry | `T.closedGone` |
| combat end | `PLAYER_REGEN_ENABLED` (today `:612-618`) | nothing | none |
| pool full | the oldest open ticket gives way (today `:138`) | nothing | `T.overflow` |

A lost resolution is an owed row that never came while its unit was alive. It is the recall signal in game: Snapshot
shows `tickets open=%d none=%d paid=%d lost=%d expired=%d foreign=%d unpinned=%d dead=%d gone=%d bandRejected=%d
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

### 5.1 The kinds

A fixed set, each implemented once in the engine (3.3). A pack names a kind and its numbers; it never writes matching
or closing code.

| Kind | Fields | Backed by |
|---|---|---|
| NONE | none | captures: every success that owes no row (Drink, capture b) |
| FRAME | `school` | captures and measured logs: today's instant-cast windows (`Rows.lua:33-49`) |
| FLIGHT | `speed`, `school` | captures a, b, c (Wrath 1483-1566 ms at max range) |
| MELEE | `hand` | measured logs (the P and G logs behind `Rows.lua:15-16`) |
| STRIKE | none | measured logs (today's on-next-swing replacement) |
| TICKS | `period`, `ticks`, `school` | unprobed: implemented, marked untested until probe U9 |
| CHANNEL | `period`, `school` | unprobed: implemented, marked untested until probe U9 |

A `school` of nil means the hit makes no row of ours (3.3). The engine's own DEFAULT and UNMAPPED kinds (3.2) are not
offered to packs.

### 5.2 The builders

Constructors in `Hekili_Shared/Shared/Expect.lua`, exposed as `Hekili.Expect`, so packs stay declarative. Every class
pack already depends on Hekili_Shared (`src/Hekili_Druid/Hekili_Druid.toc:8`). Each returns a small descriptor table
(`kind` from the core's kind ids, plus its numbers), built once at file load.

| Builder | Kind |
|---|---|
| `Expect.None()` | NONE |
| `Expect.Frame(school)` | FRAME |
| `Expect.Flight(speed, school)` | FLIGHT |
| `Expect.Melee(hand)` | MELEE (the engine's own kind for `PLAYER_SWING`; no pack needs it) |
| `Expect.Strike()` | STRIKE |
| `Expect.Ticks(period, ticks, school)` | TICKS |
| `Expect.Channel(period, school)` | CHANNEL |

An ability declares it as a value: `expects = Expect.Flight(20, 8)`.

### 5.3 The escape hatch and precompilation

`expects` may instead be a function `function(ctx)` that returns one of the builders' descriptors, for an ability whose
kind depends on context (a talent that turns a cast into a channel). It must return a descriptor built at file load
(an upvalue), never build one per call; `tests/Game/harness/alloc_spec.lua` catches a violation. Closure stays the
engine's whatever the function returns.

Precompilation: at each build, beside `now` and `onCrit` (`Game/State/Families/Now.lua:318-333`), the engine reads
`rawget(obj, "expects")` into per-ability arrays: a descriptor fills `A.expKind`, `A.expSpeed`, `A.expSchool`,
`A.expPeriod`, `A.expTicks`; a function goes to `obj.funcs` (Hekili moves a function-valued unknown field there,
`Engine/Schema/Spec.lua:897`) and from there into `A.expFn` (false otherwise). A ticket refers to them by its integer
`ab`.

Hekili's simulation already knows a `velocity` field, but its projectile branch needs `impact` too
(`Engine/Schema/Spec.lua:908-909`), and no APL reads `in_flight`. The builders set neither on the ability, so the
simulation does not change.

Per-ability matching or closing handlers (`accept`, `resolve`, `lost`) are a possible later extension; this spec does
not add them.

### 5.4 Abilities

From DB2 build 1.60.1.70338 (`SpellMisc`, every rank the pack lists agrees unless noted; LaunchDelay is 0 for all):

| Pack | Ability | Declares | Note |
|---|---|---|---|
| Druid | `wrath` | `Expect.Flight(20, 8)` | |
| Warlock | `shadow_bolt` | `Expect.Flight(20, 32)` | |
| Warlock | `incinerate` | `Expect.Flight(20, 4)` | |
| Warlock | `soul_fire` | `Expect.Flight(24, 4)` | |
| Warlock | `death_coil` | `Expect.Flight(24, 32)` | |
| Mage | `frostbolt` | `Expect.Flight(28, 16)` | |
| Mage | `fireball` | `Expect.Flight(24, 4)` | |
| Mage | `pyroblast` | `Expect.Flight(24, 4)` | |
| Mage | `frostfire_bolt` | `Expect.Flight(24, 20)` | the row's school for a two-school spell is unmeasured (probe U7) |
| Shaman | `lightning_bolt` | `Expect.Flight(20, 8)` | |
| Shaman | `lava_burst` | `Expect.Flight(20, 4)` | |
| Priest | `shoot` | `Expect.Flight(20, 1)` | the wand's own school may differ from the spell's mask (probe U7) |
| Paladin | `hammer_of_wrath` | `Expect.Flight(35, 2)` | |
| Hunter | `auto_shot` | `Expect.Flight(40, 1)` | |
| Hunter | `aimed_shot` | `Expect.Flight(40, 1)` | |
| Hunter | `arcane_shot` | `Expect.Flight(40, 64)` | |
| Hunter | `multi_shot` | `Expect.Flight(30, 1)` | the GUID match pays only the row on the pinned target; its other targets' rows stay foreign |
| Hunter | `sniper_shot` | `Expect.Flight(60, 1)` | |
| Hunter | `serpent_sting` | `Expect.Flight(40, nil)` | an aura only, no direct WOUND: its miss is its only row. Rank 1978's Speed is 40, the Forever 425728 family's is 0, so the check reads the pack's own ranks. Its ticks move to TICKS after U9 |
| Hunter | `summon_hawk` | nothing (DEFAULT) | no outcome of ours known |

Instant abilities may declare `Expect.Frame(school)`; that turns on the school check and lost counting inside today's
frame windows. This spec does not require it, and the melee packs are left on DEFAULT.

### 5.5 The DB2 check

`tools/check_spell_data.lua`, run by a new dev-only target `make spell-data-check` (outside `make check`, like the
wowsims targets, because CI has no DB2 file). It loads each pack through the existing test loader, and for every
ability with an `id` and a descriptor, over the ranks it lists (`id` and `copy`), reads `SpellMisc.Speed` and
`SchoolMask` from `$WOW_DB2` (default `~/.local/share/wow-db2/forever/current.sqlite`) through `wowdb`'s SQL mode. It
fails when:

- the speed handed to `Expect.Flight` differs from Speed on any listed rank;
- a non-nil school handed to any builder differs from SchoolMask on any listed rank;
- an ability with Speed > 0 on its first rank and `startsCombat` declares neither `Expect.Flight` nor a function.

A function `expects` is checked by calling it with a context for each talent state the pack's test loader can build;
each descriptor it returns is checked as above.

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
| 7 | Kill: `PLAYER_TARGET_CHANGED` to none 3 ms after the death's FAILED; the killing outcome 11-36 ms after the clear on the plate (and the soft token when on), `target` only sometimes | `observer.lua:437-453` keeps the dead target |
| 8 | Plate churn: a knob removes and re-adds a mob's plate (same GUID, new index allowed) within 0.5 s at a rate | none |
| 9 | Action Targeting knob, off by default: when on, `softenemy` binds to the target and its rows join the fan-out | `observer.lua:23` (`targetTokens`) |
| 10 | Truth carries the outcome's own ticket: `castT` (the success it belongs to) beside `hand` and `swingT` | `observer.lua:97-106` stream fields |

### 6.2 The detection suite

`tests/Game/harness/detect_spec.lua`, tagged `#slow`, table-driven over detection kinds x density bands, scored
against tickets through a new `metrics.tickets(m, s, W)` beside `metrics.score` (`tests/Game/harness/metrics.lua:75`).

Kinds (each a scripted scenario through the existing `scenarios.world` knobs, `tests/Game/harness/scenarios.lua:59`):

| Kind | Our actions | What it checks |
|---|---|---|
| K1 melee | white swings, both hands | swing tickets, unchanged recall |
| K2 strike | on-next-swing strike | replacement, WOUND 0 |
| K3 instant | an instant spell declaring `Expect.Frame(school)` | frame window, school check |
| K4 projectile | a cast declaring `Expect.Flight(20, 8)` at 5, 20 and 30 yd | flight window, crit, miss at range |
| K5 swap | K4 with a target swap mid-cast | SENT pin, plate-only landing |
| K6 kill | K4 or K1 killing the target, with and without a press at the kill | kill tell, post-clear row, `TargetGone` |
| K7 churn | K4 with plate churn on the pinned mob | resolution, gone and revive |
| K8 identical | another source with our exact amount and school on the same mob | dedupe never merges two GUIDs; precision |

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
print their numbers and assert only that the run finished, as `group_spec.lua:45-53` does today.

The pending-cast gap: today's group runs never exercise a pending cast, because the oracle press is not
`startsCombat` (`scenarios.lua:207-213` presses "CAST"). The fake spec declares an expectation for each of its
abilities: `Expect.Frame` for the instant spender, `Expect.Flight(20, 8)` for a new `startsCombat` hard cast,
`Expect.Strike()` for the strike, `Expect.None()` for a buff, and one ability left on DEFAULT so the default path keeps
a test. K3 and K4 press the `startsCombat` ones, so every band runs spell tickets. TICKS and CHANNEL get unit tests
against the harness's own tick model only, marked untested until probe U9.

### 6.3 Fixtures from the captures

`tools/vslog_fixture.lua` today parses `PLAYER_SWING`, `UNIT_COMBAT` and casts and raises on anything else
(`tools/vslog_fixture.lua:1-8`). It learns `SC_*` lines (castGUID, castBarID columns as in the captures' README),
`TARGET` lines (GUID or none) and skips `NOTE` lines. Then:

| Capture | Fixture | Replay asserts |
|---|---|---|
| b | `tests/Game/harness/fixtures/wrath_b.lua` | every Wrath WOUND pays its ticket (14 of 14 against 0 today); the 783 ms MISS pays as `SPELL_MISSED` and stages `Obs.Avoided`; `bg[7]` does not rise; each kill fires the tell and `TargetGone`; the 74805 killing blow (plate and soft only) pays |
| c | `tests/Game/harness/fixtures/wrath_swap.lua` | the 216184 plate-only landing pays the ticket pinned at SENT to the old mob; the `targettarget` echoes are ignored; the 219922 post-clear row pays |
| a | `tests/Game/harness/fixtures/wrath_a.lua` | the 667 ms CRITICAL stages `Obs.Crit`; the 97891 MISS (517 ms after a 30 yd cast) is foreign once the range bracket is known, and pays the 97374 ticket only at an unknown range |

The soft-targeting log was not saved in full; its findings become the churn and Action Targeting knobs (6.1 rows 8 and 9), and probe U2 recaptures it.

## 7. Migration

| Consumer | Stops doing | Does instead |
|---|---|---|
| Rows (`Game/Events/Rows.lua`) | its own `UNIT_COMBAT` handler and the `unit ~= "target"` filter (`:443-444`); `UnitGUID("target")` pins (`:338`, `:362`); the `act*` ring (`:108-111`); school 1 in spell rows (`:300`, `:304`); silent cast expiry (`:597-609`) | an `I.Units.OnRow` listener; pins from `I.Units.Pin` and the SENT pin; the ticket pool, one ticket per commit; the expectation's school; lost counters. Today's paths become kinds: the swing scoring (`:252-269`, `:375-402`, `:479-549`) is MELEE; the on-next-swing replacement (`:329-332`, `:351-361`) is STRIKE; the cast frame and avoid windows (`:458-461`, `:497-499`) are FRAME and DEFAULT; `unmappedT` and `another()`'s unmapped half (`:54-55`, `:163-166`, `:344-346`) are UNMAPPED |
| Attackers (`Game/Events/Attackers.lua`) | `Plain(api, api.UnitGUID(tok))` in `recheck` (`:81`); clearing a plate's GUID itself (`:110-115`); `L.target` from its own read (`:116-121`) | `I.Units.Bound(i)` for the GUID; keeps its own `UnitIsUnit`, `UnitCanAttack`, `UnitAttackSpeed` reads and its clocks; still handles `unit == "player"` rows itself |
| Target (`Game/State/Sources/Target.lua`) | `UnitGUID("target")` in `swap` (`:55`); `TargetDamage` from the `target` token only (`:139-143`) | `I.Units.Bound(1)`; `TargetDamage` from OnRow rows whose GUID is the current target's; `TargetGone` on OnGone DEAD for a GUID holding a memory slot; poll 4 reports `I.Units.Dead` |
| Casts (`Game/State/Sources/Casts.lua`) | `I.sentGUID = UnitGUID("target")` (`:31-35`) | `I.sentGUID = I.Units.Pin(api, t)` with the SENT's castGUID kept beside it; `SPELL_CAST_START`/`SUCCESS` destination from that pin (`:47`, `:61`) |
| Nameplates (`Game/State/Sources/Nameplates.lua`) | nothing removed | poll 5's plain `UnitIsDead` (`:36-40`) also reports `I.Units.Dead` for a bound plate |
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
| U2 | Auto-target on cast with Action Targeting off: does `PLAYER_TARGET_CHANGED` come before SENT, and does SENT name the new target | `/vslog` of SENT, START, SUCCEEDED, `PLAYER_TARGET_CHANGED` pressing Wrath with no target near a mob, Action Targeting off; plus the soft-targeting log saved in full |
| U3 | Does `UNIT_DIED` or `PLAYER_TARGET_DIED` fire for addons on Forever (O6), and is its GUID plain | `/vslog` with both registered, three kills |
| U4 | DoT ticks and channels: does a periodic tick arrive as a WOUND on the victim's tokens, with which school; is a channel's tick distinguishable | `/vslog` of Moonfire's DoT and Arcane Missiles on a solo mob |
| U5 | Nameplate GUID secrecy in combat beyond what Attackers relies on: `UnitGUID("nameplateN")` and `UnitIsDead("nameplateN")` plain for every plate in a five-man pull | `/run` loop over plates in combat with `VSCopy(issecretvalue(...))` |
| U6 (deferred with U1) | Partial resists: a WOUND with a RESIST flag and a reduced amount, or two rows | `/vslog` of a Shadow Bolt series on a mob with shadow resistance |
| U7 | Two-school spells and wands: the school a Frostfire Bolt WOUND carries (20, 4 or 16); a wand's | `/vslog` of Frostfire Bolt and of Shoot with a non-physical wand |
| U8 | The kill tell: is the target clear on a kill a client rule or a user setting; does it happen when no press is in flight | `/vslog` of a melee kill with no ability pressed, and the interface option in question |
| U9 | DoT tick and channel row shapes: per tick, which tokens, action, flag, amount, school; the first tick's delay after the application; whether a channel's ticks and a DoT's are told apart; needed before TICKS and CHANNEL are trusted | `/vslog` of Moonfire, Corruption and Serpent Sting to full duration, and Arcane Missiles and Drain Life channels, on solo mobs |

## 9. Risks and what the gate must show

The gate for this central change is the full merge gate: `make gate` (which runs `make check`, including every
class's wowsims replay floors in its slow tier, and every loop tag with `make test-loop`), the flicker floors
(`tests/Game/harness/flicker_spec.lua`), the existing group gates (`group_spec.lua`), and the new detection suite.
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
| Kill tell misses melee kills | no FAILED without a press | K6 without a press: the unit still closes through poll 5 or GONE; probe U8 |

## Decisions made in this spec

| # | Decision | Reason |
|---|---|---|
| 1 | `GRACE` = 0.1 s | about three times the slowest post-clear row seen (36 ms) |
| 2 | `DUP_WINDOW` = 0.005 s, ring of 4 | one outcome's token fan-out spans up to 1 ms in the captures |
| 3 | A rebound token's row that matches another token's payload within `DUP_WINDOW` is a duplicate | stops a stale `target` echo after a swap from paying the new mob |
| 4 | `UNIT_CAP` = 64 slots, LIVE never evicted | 44 tokens can be LIVE at once; 20 spare slots for grace and dead units |
| 5 | Token set: target, focus, nameplate1-40, softenemy, softinteract; `player` stays with Player and Attackers | the victim-side tokens of hostiles; `targettarget` rows are echoes |
| 6 | Kill tell = any player FAILED (any castGUID) within 0.010 s before a clear to none | all four kills in captures b and c show it, two of them with no cast in progress |
| 7 | `UNIT_DIED` and `PLAYER_TARGET_DIED` registered opportunistically | an earlier probe saw them (O6); costs nothing if the client refuses them |
| 8 | Tickets on a dead unit close at death + `GRACE` | the killing blow arrives up to 36 ms after the clear and must still pay |
| 9 | `TICKETS` = 16 | flight windows of up to about 2.1 s plus two hands need more than today's 8 |
| 10 | A ticket opens for every commit (every `PLAYER_SWING`, every player success mapped or not, a hard cast at SENT); the kind decides how it closes | one uniform record; no engine assumption about what a spell does |
| 11 | Fixed kind set: NONE; FRAME(`school`); FLIGHT(`speed`, `school`); MELEE(`hand`); STRIKE; TICKS(`period`, `ticks`, `school`); CHANNEL(`period`, `school`); each kind's matching and closure rule lives in the engine | packs declare, the engine handles the rest; each rule is written and tested once |
| 12 | Builders `Expect.None()`, `Expect.Frame(school)`, `Expect.Flight(speed, school)`, `Expect.Melee(hand)`, `Expect.Strike()`, `Expect.Ticks(period, ticks, school)`, `Expect.Channel(period, school)` in Hekili_Shared, returning load-time descriptors | packs stay declarative; every class pack already depends on Hekili_Shared |
| 13 | Escape hatch: `expects` may be a `function(ctx)` precompiled at spec load that returns a prebuilt descriptor; no per-ability `accept`, `resolve` or `lost` handlers (a possible later extension) | covers a talent that changes an ability's kind without letting packs write matching code |
| 14 | `CTX` fields: `t`, `guid`, `hand`, `rMax`, `lagE`, `lagSpr`, `lagAge`, `rangeLo` (optional, 0 absent), `bandLo`, `bandHi`, `bandN` | what the engine knows at commit; no range is assumed readable |
| 15 | Default kind for an ability with no `expects`: DEFAULT, today's windows exactly (open for `startsCombat` or `onNextSwing` abilities, resolved at commit for the rest), never counted lost | every pack's floors hold until it declares data |
| 16 | Unmapped successes open an UNMAPPED ticket: `UNMAPPED_WINDOW`, no owed row, any GUID, absorbs an avoid or crit as nobody's | today's `another()` unmapped rule as a generic ticket; replaces `unmappedT` |
| 17 | `owed`: rows still owed; each paid row decrements it, 0 closes the ticket; unpaid `owed` at expiry counts as lost | one counter covers one hit, N ticks and open-ended channels |
| 18 | A `school` of nil means the hit makes no row of ours: only an avoid pays, expiry is not lost (Serpent Sting: `Expect.Flight(40, nil)`) | an aura-only cast needs no handler of its own |
| 19 | Backed by captures or measured logs: NONE, FRAME, FLIGHT, MELEE, STRIKE. Unprobed: TICKS and CHANNEL, implemented but marked untested and unused by packs until probe U9 | no tick row has been captured yet |
| 20 | FLIGHT hard window `[0, rMax / speed + TOL]` from the success, always; `TOL` = 0.15 s; `rMax` 0 means 40 yd; the plain bracket's `lo` may only raise the lower bound, less `CLOSE x age` | the engine cannot read an up-to-date range in combat; the five max-range samples fit [0, 1.65] s |
| 21 | School check by equality with the declared numeric school | no bit operations in core; two-school rows are probed (U7) |
| 22 | Amount band [0.6 x lo, 1.6 x hi] after 3 clean wounds | spell damage varies more than weapon damage; procs and crits halved stay inside |
| 23 | Consumption order: rows online in arrival order after dedupe; candidates of the row's queue in expected-closure order; passes (a) narrow, (b) widened, (c) hard window for tickets with no record; first match pays; MELEE's LR decides among MELEE candidates at a pass | the order decides correctness; FIFO per queue falls out of it |
| 24 | A mapped ticket with no pin opens with `guid` "" and counts `unpinned`, not lost | it can match no row; today its rows are dropped anyway |
| 25 | Until 4.2 is built, a divergent row emits its row but stages nothing | stays on the floor's safe side, as today's two-casts rule |
| 26 | Build trigger for 4.2: `divergent` over 1 per 100 paid tickets in a five-man run | a rate that would show as flicker; below it the union is not worth its cost |
| 27 | DB2 check is a dev-only `make spell-data-check` over the builders' numbers | CI has no DB2 file |
| 28 | Registry dispatches rows through `OnRow`; Rows registers before Target | one resolution and dedupe for every consumer; tickets see a row first |
| 29 | Learned flight lag: `LAG_CAP` = 16 records per (GUID, speed): `lagE` (last observed lag), `lagSpr` (EMA spread, 0.25 rate, [0.02, 0.4]), `lagT`, `lagN`; taught by a clean pass (a) or (b) payment; oldest `lagT` evicted | the same mechanism as the global melee lag, keyed per unit because flight lag is distance; the last lag tracks a closing mob |
| 30 | Widening: `b = max(TOL, 2 x lagSpr)`; `down = max(b, (CLOSE / speed) x d)`, `up = max(b, (CLOSE / 2 / speed) x d)`, `d` = time since the last landing, `CLOSE` = 7 yd/s, clipped to the hard window; no record: the whole hard window, uniform | the band grows as fast as a running mob can change the lag |
| 31 | FIFO per queue (kind, school, speed, GUID); never across queues | one queue's rows arrive in cast order unless the distance shrinks faster than the projectile (20 yd/s or more) between casts, which no run does |
| 32 | Cascade bound: a lost ticket shifts its queue by at most one row, only while casts are closer than the narrow band or before the first record, until it expires at `H` or closes on the kill tell or GONE; shifts that change a belief count as `divergent` | a shift between two own same-school hits changes nothing; only divergent outcomes matter |
| 33 | Pass (c), the hard window, is open only to tickets with no learned record | otherwise a far-off row (capture a's 517 ms MISS) would still be charged to a cast whose learned lag excludes it |
