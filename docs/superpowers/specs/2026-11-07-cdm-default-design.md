# Cooldown Manager facts, always on: one reduced fact per tracked thing (spec amendment, 2026-11-07)

Status: DESIGN (not built), review rounds 1-4 applied (round 3: the seen rule, review 2 §3; round 4: the seen rule per slot, review 3) (`~/src/hekili-central-needs/cdm-design-review.md`). Plan:
`docs/superpowers/plans/2026-11-07-cdm-default.md`.
Amends `docs/superpowers/specs/2026-10-23-providers-design.md` ("the providers spec", decisions 65-91). New decisions
are numbered from 92. Paths are under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`. Line numbers
are as of `integ/0.7` a0bd6f8dd; Blizzard lines as of the Gethe `forever` head the review read.

Supersedes or amends: **89** (superseded by decision 99: §3.1-§3.2), **79** (superseded by decisions 100-101: a sweep
reads, no hooks, §3.3), **80** (amended: the consumer reads the reduced fact, §2.5), **82** (superseded for the viewer:
always on, no option; internal self-off only, §6), **88** (amended: the router hosts the reducer, §2.4), and the
providers spec §2.4 "Only BuffIcon and BuffBar items are presence sources" and its taint rule (superseded: §3.2, §3.5).

Inputs: the owner's plan (`~/src/hekili-cdm-default-plan.md`: P0 results 1-9, the answers, the "reduce to one fact"
and "no visible toggle" directions), the Druid probe (`~/src/hekili-central-needs/druid-probe-2026-11-07.txt`), the
TellMeWhen research (`~/src/hekili-central-needs/tmw-research.md`, "TMW"), the 2026-10-23 research
(`docs/research/2026-10-23-cooldown-manager-api.md`, "CV") and Blizzard's Forever UI source (`Blizzard_CooldownViewer`,
"BV": `CooldownViewer.lua`, "BD": `CooldownViewerItemData.lua`).

## 0. The owner's requirements

1. Always on and adaptive, with no option: "We don't need a visible CDM toggle as long as it's adaptive: automatically
   reads all available CDM item info and ignores the unavailable ones, reduces multiple CDM items tying to the same
   thing down to 1 fact, and falls back to beliefs or other ways of getting facts if necessary" (owner direction
   (toggle), 2026-11-07). Internal safety only: a self-off on a Lua error, a debug-only session off.
2. A generic fact layer, not Lightning Shield code (owner clarification 2026-11-07).
3. "Take in all the info we can get from the CDM and reduce it down into 1 fact per thing that we track, so that we're
   not making any assumptions and are open to all forms of configs" (owner direction 2026-11-07).
4. Mid-fight changes allowed (decision 89 amended, owner question 2026-11-07).
5. A direct never-secret read in the same release, CONDITIONAL on a Shaman finding an aura with secrecy flag 0.
6. The CDM debug information lives only in the existing debug snapshot (owner answer Q5): no slash command, nothing
   new in the options panel but the coverage line.

## 1. Measured facts this rests on

| # | Fact | Source |
|---|---|---|
| F1 | Contextual auras (flag 2) read nil by direct read in combat, a table out of combat | Clearcasting 16870, probe §5 |
| F2 | A viewer item's `auraInstanceID` existence flips on gain and back on removal in combat within 1 s | Thorns 199474, Enrage 199381, probe §6, §9 |
| F3 | `auraSpellID` is secret when the aura was applied in combat, plain otherwise: never depend on it | probe §6, §9 |
| F4 | An item can hold a linked spell's aura (Omen entry 199480 links Clearcasting 16870) and lights on the proc; the passive (16864) did not light it | probe §7, §8, P0 result 7 |
| F5 | One spell has separate cooldownIDs per role (Essential/Utility vs TrackedBuff) | probe §8 |
| F6 | **Cooldown entries (Essential, Utility) carry `auraInstanceID` while the spell's aura is up, in combat**, self buff and target debuff, gain and removal | Enrage 199382, Moonfire 199545, probe §10 (P0 result 9; revises result 5) |
| F7 | A target debuff entry lights on a mob | Faerie Fire 199443, P0 result 8 (visual) |
| F8 | Coverage is a property of the player's layout, not of the category sets | probe §8 |
| F9 | The combat-exit walk is ground truth for every aura | `Sources/Auras.lua:165-190` |
| F10 | The viewer tracks player-cast auras only | CDM-S; and from source below |
| F11 | Item presence matches the aura's lifetime to the second, in combat, gain and removal: Enrage 10 s, Demoralizing Roar 30 s, Growl 3 s, Nature's Grasp consumed at 18 s; Faerie Fire, Demoralizing Roar and Growl (target debuffs) lit their items | AuraProbe run 1, P0 result 10 (`~/src/hekili-central-needs/auraprobe-druid-run1-2026-11-07.txt`) |
| F12 | **An item can stay silent while its aura is up**: the Mark of the Wild item (5232) held no aura for a whole 55 s fight while the buff was up (the owner confirms it was up all fight); cause unknown, possibly a client bug (Task 10 records its `sets` entry) | P0 result 10.4 |
| F14 | A target item's `auraDataUnit` is plain "target" while held | CV §2 (Rend); the probe now records it (P0 result 10.5) |

Read from source (not measured): `SetAuraInstanceInfo` clears then sets in one call (BD:368-380);
`ClearAuraInstanceInfo` fires nothing when nothing was held (BD:382-392); a pool release runs `ResetCooldownData`,
which sets `cooldownID = nil` (BD:95) **before** clearing the aura (BD:98); an override re-point is
`SetOverrideSpell` + `RefreshData` (BV:137-147); viewer `UNIT_AURA` handling is synchronous (BV:1787-1789); a hidden
viewer unregisters `UNIT_AURA` (BV:1746-1751); the player's auras are read with `HELPFUL|PLAYER` and linked spells need
`sourceUnit == "player"` (BD:~716-724, BD:26): **a buff someone else cast on us never lights our item** (C1);
Essential/Utility items refresh on a target change only with a range check or a target aura unit (BV:483-485).

Unmeasured (the design does not lean on them; each is in §10): sub-second latency, taint (CDM-T), target-switch order
(CDM-O), a second mob, instances (CDM-I), a partner's copy (CDM-P, answered by source, still to confirm), F7.

## 2. The fact reducer (the core of this amendment)

### 2.1 The model and the registry

A **thing** is a pack aura on a unit: (j, u), aura index j in `def.auras` order, unit u (1 player, 2 the current
target). Every thing has exactly one **reduced fact** the belief reads. Evidence comes from **providers**, each with a
**standing**. This table is the fact-provider registry:

| Standing | Provider | Fact kind | Evidence | Belief record | Obs kind | Carries |
|---|---|---|---|---|---|---|
| 3 | the aura walk (`Sources/Auras.lua` `walk`), **plain and out of combat only** (so the combat-exit walk) | aura state | found / not found | aura record (u, j) | `Obs.Read`, `ReadOf.Aura` | remaining, stacks |
| 2 | the direct never-secret read (`Presence/Direct.lua`, CONDITIONAL, §3.6) | aura state | plain table / nil | aura record (u, j) | `Obs.Read`, `ReadOf.Aura` | remaining, stacks |
| 1 | CDM items (`Presence/CooldownViewer.lua`, §3) | aura presence | per item: holds an aura / none | aura record (u, j) | `Obs.Read`, `ReadOf.Aura` | presence only |
| 0 | none | | | | | the belief's model alone |

The highest standing with live evidence decides. A new fact kind is a new row (provider, record, Obs kind).

**Standing 3 is out of combat only (I7).** Today `apply` returns early while `playerPlain`/`targetPlain` is true
(`Sources/Auras.lua:224-227`), a walk whose index 1 reads nil counts as complete (`:94-96`, `:128-129`), and in combat
reads return nil or raise (F1), so a stale "plain" flag would mute every CDM fact for that unit (the Shaman snapshot
shows `combat=true` with `aura walk target: readable`, `shaman-tank-snapshot-2026-11-06.txt:122, :135`). The presence
path therefore uses `walkWins(u) = plain[u] and not I.inCombat`; the overlay's own use of `playerPlain` (poll 11) is
unchanged, so the default arm stays identical.

### 2.2 Evidence from items

One item frame is one **evidence slot**. A slot is **live** for thing (j, u) when ALL hold:

- its viewer is visible (`viewer:IsVisible()` plain true: parent-aware, so Alt-Z counts; BV:1746-1751);
- it is configured: `cooldownID` and `layoutIndex` plain and non-nil;
- its `cooldownID` maps to aura j (§3.1);
- u = 2 only: it is not **settling** (§3.4);
- it gives an answer for u: **UP** (held, with plain `auraDataUnit` = u, F14) or **NONE** (not held, and the slot's
  seen rule of §2.2a holds for (j, u)). A held slot for the other unit, a held slot with a secret or nil unit, and a
  silent slot failing its seen rule are not live for u.

`held = issecretvalue(aid) or aid ~= nil`, `aid = rawget(item, "auraInstanceID")`. The entry's role plays no part (F6).

**Ambiguity (I2).** An item's **aura candidates** are its `linkedSpellIDs` when it has any (Blizzard looks for the linked
spells' auras: BD `FindLinkedSpellForCurrentAuras`; F4: the Omen passive did not light its item), else its `spellID`,
`overrideSpellID`, `overrideTooltipSpellID` (each with `GetOverrideSpell`). The plan's Task 3a reads
`GetAssociatedAuraSpellPriority` (BD:327-358) and widens the candidate set if the base spell can bear the aura while links
exist. UP is evidence for j only if **every** candidate maps to j (untracked candidates included: an unregistered linked
proc makes the item ambiguous). An ambiguous item gives no NONE either: its UP names no single aura, so the seen rule
(§2.2a) never holds for it. Counted per fight as `ambiguous`.

### 2.2a The seen rule: a slot's silence closes only an application that slot was seen holding (decision 115)

F12 shows an item can stay silent while its aura is up. Under "DOWN when every existing item says none" that silence
would close the record: a wrong DOWN and a "rebuff" every poll for the rest of the fight. The cause does not matter
(a client bug, a candidate list, anything); one rule covers it, kept **per slot** so a silent item can never borrow
another item's light (review 3, must-fix 1):

- **`sSeen[s]`**, one preallocated number per slot (beside the leaf's other slot arrays, `MAX_SLOTS` numbers), 0 at
  build. At **every** sweep where slot s is held with plain `auraDataUnit` = u and its UP counts for a single j (not
  ambiguous, §2.2): `sSeen[s] = t` and `sUnit[s] = u`. Every sweep, not only on a reading change: a refresh is a
  clear-then-set inside one client call, so a change-only write would leave `sSeen` at the first light while our refresh
  moves `applied`. `sUnit[s]` is the slot's last plain held unit and is kept through silence.
- **Resets** (`sSeen[s] = 0`, `sUnit[s] = 0`): when the slot's mapping is (re)assigned, that is at a `cooldownID` change
  (release, re-point, (re)configure) and at a map rebuild; at a held sweep whose unit is secret or nil (it held
  something for no known unit); and at `PLAYER_TARGET_CHANGED` for a slot whose `sUnit` is the target (the same place
  §3.4 marks it settling: mob A's light says nothing of mob B's application).
- **The gate is in liveness:** a silent slot s is live as NONE for (j, u) only when all three hold:
  the record is up, `U.exp0[u][j] > t`; `sSeen[s] >= U.applied[u][j]` (this slot held this application); and
  `sUnit[s] == u`. Otherwise it is not live, so the reduced fact reads UNKNOWN, never DOWN. `Reduce` and its table are
  unchanged.
- **Owner and detection, no hook.** The leaf owns `sSeen` and `sUnit`; the router never reads them. `applied` moves in
  `Families/` (our cast, a read) without telling the leaf, so the sweep re-checks the gate of **every silent mapped slot
  at every sweep** (bounded by `MAX_SLOTS`, reading `U.applied`/`U.exp0` inside `Game/`, no allocation); a slot whose
  gate result changed moves the counters like any reading change. Nothing is added to `Families/Auras.lua`.

What happens:

| Case | Result |
|---|---|
| Our fresh cast of a buff whose item lit for an **earlier** application | the cast writes `applied = T` (`Families/Now.lua:325-328` through `I.AuraModel`), so `sSeen < applied`: the silent item is not live, the fact is UNKNOWN until the item lights (then `sSeen >= applied`); no close in the gap between our cast and the client's `UNIT_AURA` (closes I-B) |
| A **never-lit** item (F12) | its `sSeen` stays 0: never live as NONE, fact UNKNOWN; the model closes the record at its expiry |
| A buff **re-applied after its item went silent** (an item that stops following), by a fresh application | the new application moves `applied`; the item never holds it, so it never closes it: UNKNOWN, the model runs (closes I-A for a fresh application; a refresh before expiry: the Residual row) |
| Our refresh while the item stays held | `applied = T`; the next sweep writes `sSeen = t >= T`; when the aura really ends the item's NONE is live and DOWN closes |
| A **partner's copy** of our buff (out of combat it overwrites ours; a walk re-read keeps `applied`, `Families/Auras.lua:208-212`) | `sSeen` may still be `>= applied`, so the NONE is live and the reduced fact is DOWN; it does not close, because the walk read with a partner source cleared `ours[k]` (rule 2.5.1). That is why `ours` stays |
| Two items for one aura, one silent (also across our refresh) | the silent one's `sSeen` stays 0, so it is never live: the working one alone decides (UP while held, DOWN when the aura ends); no flip, `agree` stays true |
| The working item **leaves** mid-application (released, re-pointed, held with a secret or nil unit) while the silent one stays | the working slot drops or resets; the silent one is still not live: UNKNOWN, the model runs, no close |
| An **ambiguous** item | its UP counts for no j and it never writes `sSeen`: never live as NONE |
| A target slot after a target switch | its `sSeen` was reset at the switch: not live for the new target until it holds that target's aura |
| A hidden viewer | its slots are stale (`nStale > 0`, UNKNOWN), and while hidden they write no `sSeen`; an application no visible item showed is never closed by an item (the model handles it) |
| **Residual**: our refresh lands before the old application expires, a sweep inside the latency window still sees the item holding the old one (`sSeen >= T`), and the item then does not light the new application (an item that stops following) | its silence is live, the state is DOWN and `ours` is set: the record closes **once** (one wrong "rebuff"). The next cast moves `applied` again and is gated, so it is not a loop. Accepted, no guard (D14) |

### 2.3 The reduction: one pure, total function

Per thing the provider keeps preallocated counters `nLive`, `nUp`, `nNone`, `nStale`, `tUp`, `tNone`:

```
Reduce(nLive, nUp, nNone, nStale, tUp, tNone) -> state, agree
```

| Case | state | agree |
|---|---|---|
| `nLive == 0` | UNKNOWN | true |
| `nUp == 0`, `nNone == 0` (unreachable under §2.2's "live", kept for totality) | UNKNOWN | true |
| `nUp > 0`, `nNone == 0` | UP | true |
| `nUp == 0`, `nNone > 0`, `nStale == 0` | DOWN (a NONE answer; §2.5 decides whether it closes) | true |
| `nUp == 0`, `nNone > 0`, `nStale > 0` | UNKNOWN | true |
| `nUp > 0`, `nNone > 0`, `tUp >= tNone` | UP | false |
| `nUp > 0`, `nNone > 0`, `tNone > tUp` | UNKNOWN | false |

Pure: numbers in, two values out, no tables. `I.ReduceFact` in `Presence/Reduce.lua`, tested row by row.

**Times (I3).** `tUp` / `tNone` are the latest time a live slot of the thing *began* to answer UP / NONE. A slot begins
to answer at a reading change, at its first collect, at stale-to-live (viewer visible again) and at settle end; each is
a change at that poll's time. A silent slot begins to answer NONE only at its own held-to-silent change (its `sSeen` is
written only while it is held, so its seen rule can afterwards only stop holding, which takes it out of liveness, never
give it a new answer). The seen rule is folded into liveness (§2.2), so `Reduce` itself does not change. `fact.t[k]` is the time the reduced state last went from UNKNOWN or DOWN to UP.

**Disagreement (M8, M3).** `disagree[k]` counts transitions of `agree` from true to false, not polls. Expected source:
an Essential/Utility item that does not refresh on a target change (BV:483-485) beside a Buff entry that does; the
reducer gives UP (fresher), and the A/B reads the column as lag, not error.

### 2.4 The reduced record and the router

`Presence/Router.lua` (the injected provider, decision 88) holds, preallocated at build for both units:

```
fact.state[k] 0 UNKNOWN, 1 UP, 2 DOWN      fact.n[k]     nLive of the deciding standing
fact.agree[k]                              fact.t[k]     §2.3
fact.from[k]  deciding standing 0-3        fact.via[k]   bitmask: 1 Essential, 2 Utility, 4 Buff icon, 8 Buff bar, 16 direct
counters per fight: disagree, ambiguous, lost (a thing with a fact went UNKNOWN), exitFix (§2.6)
```

`k = (u - 1) * I.AURA_UNIT + j`. `R.Presence(j, u)` returns `fact.state[k]` as UP, DOWN or `I.UNDECIDED`. The contract
(providers §1.2) gains `Q.Sweep(t)`, `Q.Counts(j, u)` (six numbers) and `Q.Mappable(j)`; the Default provider's are
no-ops. Leaves share no code and never call each other (decision 66).

### 2.5 What the belief does with a reduced fact

One rule set, in `Sources/Auras.lua` `apply` (`:218-243`), plus one array CN13 reads (§7):

1. **Who may close a record (C1).** The viewer reads only our own auras (F10). A NONE closes a record (stages
   `Obs.Read` 0) only where our evidence opened it:
   - target (u = 2): never (today's scope rule, `Router.lua:22-24`, `:139`);
   - player (u = 1): only when the reduced state is DOWN (its NONEs already pass the seen rule, §2.2a) **and**
     `ours[k]` is set: both are needed. `ours[k]` (preallocated, `Sources/Auras.lua`, exposed as
     `I.auraOurs`) is set by our cast opening or refreshing the record (`Families/Now.lua:325`, the `aura()` writer: a
     one-line write), by a CDM UP that opened it, and by an out-of-combat walk read whose `sourceUnit` is plain "player"
     or "pet"; it is cleared when a walk read with any other or a secret source opens or refreshes the record, and when
     the record closes. Otherwise a NONE is no answer, and a partner's Mark of the Wild survives the fight.
2. **A fact beats the model for presence.** UP while believed down stages `Obs.Read` (rule 4 gives the time); a
   closing DOWN (rule 1) while believed up stages `Obs.Read` 0.
3. **Between facts the model runs.** UP while believed up stages nothing: the modelled expiry, stacks and consumption
   stand.
4. **An UP with no model behind it (C2; owner Q3).** Let `d` be the aura's numeric registered duration
   (`def.auras[j].duration`, cached at build) and `t0 = max(fact.t[k], U.applied[u][j])` (our cast's refresh moves
   `applied`, so refreshes count).
   - `d` known and `t0 + d - now > HOLD`: remaining = `t0 + d - now`.
   - `d` known and that remaining `<= HOLD`: remaining = `HOLD` (1.0 s), staged **only when the record is down or
     within one poll of lapsing**, so a fact that stays UP past the duration is re-staged once per `HOLD`, not per poll.
     When the item clears, nothing re-stages and the record lapses within `HOLD`, even where the NONE may not close it
     (the target). Remains stays at or below `HOLD`, so `refreshable` reads true throughout and does not flip.
   - `d` unknown, player: -1 (`math.huge`, `Families/Auras.lua:205`); rule 1's NONE closes it (a CDM UP sets `ours`).
   - `d` unknown, target: remaining = `HOLD`, same re-stage rule. **Never `math.huge` on the target or with a numeric
     duration.**
5. **UNKNOWN leaves the model untouched.** A thing that had a fact and loses it (item released, viewer hidden, target
   settling) keeps its belief; rule 4's bounded expiries make that safe.
6. **A plain out-of-combat walk wins** (standing 3, §2.1).
7. **Forms and enchants are skipped** on the player, as the walk does (`Sources/Auras.lua:140`; M5): those records belong
   to `Sources/Forms.lua` and `Sources/Enchants.lua` (an ambiguous "Druid Forms" entry would otherwise write them).
8. A reduced-state change calls the existing `onEdge` path (`Sources/Auras.lua:244-250`).

The per-aura audit (`facts[k]`, `disagree[k]`, decision 90) is kept.

### 2.6 The combat-exit reconcile as a measured fact

The first plain walk after `PLAYER_REGEN_ENABLED` (`Sources/Auras.lua:165-190`) is standing-3 evidence for every aura.
It is counted: `exitFix[k]` when it changes the believed presence. Shown in the debug snapshot (§6), reset per fight,
reported by the A/B per spec.

## 3. The CDM provider

### 3.1 The map: cooldownID -> aura, complete, out of combat

Built at activation and rebuild, out of combat only (allocates): `GetCooldownViewerCategorySet(c, true)` for c = 0-8
(`allowUnlearned`); per cooldownID `GetCooldownViewerCooldownInfo(id)`; the candidates of §2.2 (never the singular
`linkedSpellID`, which the viewer fills with the secret aura id: TMW `Auras.lua:960-1010`); each looked up in
`def.auraIds[j]` (every rank). Result per id: unmapped, one j, or ambiguous (`cdvToJ[id] = -a`, `amb[a]` the js, UP
never counts). Today's first-match rule (`CooldownViewer.lua:92-98`, `Router.lua:66-72`) is replaced; the router's own
`mark` is deleted and `tracked[j]` reads `leaf.Mappable(j)`. Rebuild triggers: `COOLDOWN_VIEWER_DATA_LOADED`,
`..._TABLE_HOTFIXED` (today) and `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`; in combat they wait for combat end. A layout
change in combat needs no rebuild: it changes the evidence set.

### 3.2 The read: a sweep of the slots at poll 15, by rawget

At poll 15 (every drain), **before** poll 15's `covered == 0` early return (`Sources/Auras.lua:259`), the leaf sweeps:
per viewer `IsVisible()` and `GetNumChildren()` once; per slot `rawget` of `cooldownID`, `layoutIndex`,
`auraInstanceID`, `auraDataUnit`; on a reading change the affected counters move in O(1). The router then reduces the
touched things.

The sweep runs after the client's call stack, so: the refresh's clear-then-set pair is never seen; a release
(`cooldownID` nil before the clear) only drops the slot (UNKNOWN if it was the last, never NONE); a re-point moves the
slot's evidence; always-shown Essential/Utility items are read like any other.

**Not the forbidden rescan** (owner Q1, confirmed on the controller's recommendation): no getter, no allocation, no map
change; a read of known frames, as poll 15's per-pair re-ask already is.

**The collect (M4, I6).** Each viewer's children are collected at activation, at rebuild, at `PLAYER_REGEN_ENABLED`,
and **in combat when `GetNumChildren()` grows** (a viewer set to show "In Combat" builds its pool in the first fight:
BV `ShouldBeShown`, RefreshLayout from OnShow BV:1743). The in-combat collect walks `select(i, viewer:GetChildren())`
for the new indices only (varargs, no table). Every child is kept as a slot, item or not; liveness per sweep is
`cooldownID`/`layoutIndex` (non-item children such as pandemic frames have neither; released items have `layoutIndex`
nil). Slots are preallocated to `MAX_SLOTS = 128`; a child past that is ignored and counted (`overflow`). The only
in-combat insert is the frame-to-slot entry of a new child.

Cost per drain: four `IsVisible` and four `GetNumChildren` calls and four rawgets per slot (30-60 slots); no allocation.

### 3.3 No hooks (supersedes decision 79; owner Q2)

A hook could only buy latency. For the player it buys none: the player's real `UNIT_AURA` reaches the core as a full
update and forces an update that "waits its turn ... never shortens the wait" (perf 2.1a, `Engine/Sim/Events.lua:1288-1289`;
a force selects the 0.2 s combat rate, `Engine/Driver.lua:171`), and the sweep at that drain reads the viewer's state.
For the target it would: the target's `UNIT_AURA` in combat is not delivered to the core
(`Game/Events/EventFacade.lua:261-266`), so a target change we did not cause (expiry, dispel, death, a proc-applied
debuff) waits for the unforced in-combat rate, up to 0.5 s (`Engine/Driver.lua:77-85`), where a hook would give 0.2 s.
Accepted as a known limit (a target NONE is no answer anyway; target UPs mostly follow our own casts, which force);
deferral D8 names the upgrade inside `Game/`.

So the leaf installs **no hooks**: today's `HookScript("OnShow"/"OnHide")` is removed (TMW #2463 shows `HookScript` on
Blizzard frames spreading taint; and it never sees Essential/Utility changes), and no `hooksecurefunc` is installed.

### 3.4 The target

Target evidence is presence **on the current target only**, never per GUID (P0 result 8). On `PLAYER_TARGET_CHANGED`
every slot whose last answer was for the target, and every NONE slot, is **settling** until `t + SETTLE` (0.05 s until
CDM-O measures it), and every slot whose `sUnit` is the target has its `sSeen` reset (§2.2a); settling slots count as
`nStale`, so the target's thing is UNKNOWN meanwhile and the per-target
memory (`Families/Auras.lua:255-264`) gets no old-target state. Settle end is a reading change (§2.3). An
Essential/Utility NONE may stay stale after the switch (BV:483-485, M3): the fresher-UP rule covers it. Replaces today's
immediate re-read (`CooldownViewer.lua:161-168`).

### 3.5 Taint rule and internal safety (supersedes providers spec §2.4's rule)

Read, never write: item fields by `rawget`; on Blizzard frames only `GetChildren()`, `GetNumChildren()` and
`IsVisible()` (read-only getters); no hooks; no call to a viewer or item Lua method; nothing written to a viewer table
or frame (CV §5). The `HookScript` hooks of earlier dev builds cannot be removed; nothing after this installs them.

Internal safety, no option (owner direction (toggle)):
- **Self-off on error.** The sweep body runs under one `pcall` (outside the per-slot loop); an error turns the leaf off
  for the session, writes one `def.error` line, and the snapshot shows `leaf=off(error)`.
- **Debug-only session off.** `/run Hekili.cdmOff = true; Hekili:ProvidersChanged()` (documented in `DEVELOPMENT.md`,
  not a slash command or option): `providersOf` gives `viewer = false` until `/reload`; the snapshot shows
  `leaf=off(debug)`. The same field is how the harness's A/B arms choose the viewer (§6). Taint (CDM-T) raises no Lua
  error, so its remedy is this switch for a player and a held release for the project.

### 3.6 The conditional direct never-secret provider

Built only if the Shaman run finds a pack aura with `C_Secrets.GetSpellAuraSecrecy(id) == 0`. `Presence/Direct.lua`: at
build (out of combat) classify every pack aura ID; on `UNIT_AURA` read `C_UnitAuras.GetPlayerAuraBySpellID(id)` /
`GetUnitAuraBySpellID("target", id)` for flagged IDs only, each field through `issecretvalue`; a plain table stages a
full `Obs.Read` like the walk (standing 2); nil is NONE (the flag says it never hides); a target UP needs a plain
`sourceUnit` of player or pet. New API names join `tools/api_inventory.txt`.

## 4. Contract changes

| Item | Today | After |
|---|---|---|
| `Q.Presence(j, u)` | leaf state per pair (`CooldownViewer.lua:153-159`) | router: the reduced `fact.state[k]` |
| `Q.Sweep(t)` | none | leaf: the sweep; router: leaf sweeps, then reduce; Default: no-op |
| `Q.Counts(j, u)`, `Q.Mappable(j)` | none / router's `mark` | leaf |
| `Q.covered` | auras with a BuffIcon/BuffBar item | auras with at least one live slot in any viewer |
| `onEdge` | leaf -> router -> consumer per hook | router -> consumer on a reduced change |
| poll 15 | `P.Presence` for every pair | `P.Sweep(t)` first (before the `covered` guard), then `apply` per pair |

## 5. What the CDM offers, and what we ingest

| Field / API | Secrecy in combat (measured) | Fact it supports | Redundant? | Ingested |
|---|---|---|---|---|
| item `auraInstanceID` | secret while up, nil while down (CV §2, F2, F6) | aura presence, any item | no: the walk is secret in combat | **yes**, existence only |
| item `auraDataUnit` | plain (CV §2) | the unit of the presence | no | **yes**, while held |
| item `auraSpellID` | secret if applied in combat, plain otherwise (F3) | which aura | n/a | **no** |
| item `cooldownID`, `layoutIndex` | plain | slot identity, configured / released | no | **yes** |
| viewer `IsVisible()`, `GetNumChildren()` | plain getters (e4b confirms) | liveness, new frames | no | **yes** |
| `GetCooldownViewerCooldownInfo`: `spellID`, `overrideSpellID`, `overrideTooltipSpellID`, `linkedSpellIDs`, `selfAura`, `hasAura` | plain out of combat (CV §2, probe §7) | the map | no | **yes**, out of combat |
| info `linkedSpellID` (singular) | secret (TMW) | | | **never** |
| `GetCooldownViewerCategorySet(c, true)` | plain out of combat | the map's universe | no | **yes**, out of combat |
| item `isActive`, `shown` | plain (CV §2) | drawn / active | `shown` of a cooldown entry says nothing of the aura (F5); `isActive` = `GetSpellCooldown().isActive` (NeverSecret) | **no** |
| item `isOnGCD` | plain | GCD | yes (`GetSpellCooldown().isOnGCD`) | **no** |
| item `cooldownIsActive` | plain while ready / on GCD, secret while a real cooldown runs | "a real cooldown runs" | yes (the spell API's flags) | **no** (D3) |
| cooldown times, charge text, stack text | secret | | | **never** |
| `IsCooldownViewerAvailable()` | plain | the provider can run | | **yes** |
| `ADDON_RESTRICTION_STATE_CHANGED` | plain event (TMW e6) | walk failure | partly (the walk's own result) | **no** (D4) |

The only fact kind is aura presence (self and current target, procs through linked spells included).

## 6. Always on; coverage; the debug snapshot

- **No option.** `providersOf` (`Engine/Schema/Tracked.lua:216-226`) returns `viewer = Hekili.cdmOff ~= true` in every
  build and no longer reads `performance.cooldownViewer`. The setting (`Options/Options.lua:312`), its Experimental
  entry (`:4212-4227`) and their locale strings are removed; a saved value is ignored (no migration). The other three
  experimental switches are unchanged.
- **The harness** keeps choosing per arm: `def.providers.viewer` from `ab.providers()` (`tests/Game/harness/detect.lua:155`),
  and the loops set `Hekili.cdmOff` from the arm instead of the removed profile value (`loop.lua:333`), so the `default`
  arm stays viewer-off and the first gate holds.
- **The coverage line** (information, not a switch; Options' Performance tab): "N of M tracked auras have an item in a
  Cooldown Manager bar; to cover X, Y and Z, add them to any bar in the Cooldown Manager settings." Computed in
  `Options/` (client API + `class.auras`, the §3.1 match, out of combat on draw): **no belief read**.
- **The debug snapshot** (owner Q5). Players attach the file `Hekili:SaveDebugSnapshot` writes (`Engine/Snapshot.lua:81`);
  each display's log opens with `log.onOpen()` (`Hekili.lua:238`), which the belief fills itself through the approved
  `SetLog` (`Game/API/Facade.lua:68-75`) to write `VS.Snapshot()` (`Game/State/Snapshot.lua:17`, the `I.OnSnapshot`
  callbacks, `VirtualState.lua:216`). The CDM section is one such callback in `Sources/Auras.lua` (replacing
  `:281-306`): per tracked aura and unit with evidence or a fact this fight,
  `presence <key> unit=%s fact=up|down|unknown from=walk|direct|viewer|model n=%d via=EUBR agree=%s ours=%s facts=%d
  disagree=%d itemDisagree=%d ambiguous=%d lost=%d exitFix=%d`, and one summary line `presence covered=%d/%d
  unmapped=%d ambiguous=%d overflow=%d leaf=on|off(error)|off(debug)` (each under 255 chars, split if longer). It
  allocates only while a snapshot is taken.
- **Border.** The core reads nothing new: the coverage line uses the client API; the snapshot text arrives through the
  logger the core already owns. `tools/check_border.sh` output is unchanged.

## 7. Composition with CN13 (the generic consumption model)

CN13 (`Families/Auras.lua` `Obs.PlayerHit` `:238-252`, `Sources/Player.lua`) is the model when no fact exists. With a
fact: UP while believed up, CN13 spends charges as modelled; a closing DOWN closes; UNKNOWN, CN13 alone.

**The one-update flash.** The drain runs the polls, then the fold (`Sources/Sources.lua:228-230`): a hit spending the
last charge would take the record down for one update before poll 15 restores it. Owner Q4: **CN13 builds the floor**
as a generic input, an array `I.auraFloor[j]` (default 0) that `Obs.PlayerHit` honours (keeps one stack while it is 1);
this lane's Task 4b writes it from the reduced fact (1 while the player fact is UP). `Families/` needs no router
knowledge. If CN13 merges without it, Task 4c adds the three-line read (one `Families/Auras.lua` diff, accepted).

## 8. Secrets and allocation

- `auraInstanceID` only through `issecretvalue(x) or x ~= nil`; everything else through `S.Plain`; a secret
  `cooldownID`, `layoutIndex` or `auraDataUnit` makes the slot not live for that sweep; nothing passed back to an API;
  never `a and b or c` on a raw value; the walk's `sourceUnit` (rule 2.5.1) through `S.Plain`, out of combat only.
- No allocation in the sweep, the reducer, the router, `apply` (preallocated per thing and per slot up to `MAX_SLOTS`);
  the only in-combat insert is a new child's frame-to-slot entry (bounded by `MAX_SLOTS`).

## 9. Harness and A/B (detail in the plan)

The fake viewer (`tests/Game/State/helpers/fake_api.lua:666-712`) models any layout: per viewer a child list (items
configured or not, non-item children), `IsVisible` (own and parent), `GetNumChildren`, pool growth in combat; infos
with `overrideTooltipSpellID`, `linkedSpellIDs`, a secret singular `linkedSpellID`; `allowUnlearned`; the client order
(clear then set; release clears `cooldownID` first); only player-sourced auras light items; a **silent item** flag
(an item that never lights, F12) and a **lag** option (an item lights one poll after our cast, I-B); `HookScript`/`hooksecurefunc`
recorders (asserted unused). Layout presets: `none`, `buffs`, `fixture`, `mixed`. Arms: `default` (viewer off),
`viewer-none`, `viewer-buffs`, `viewer-fixture`, `viewer-mixed`; measured: flicker/min, readyShort, agreement, facts,
disagreements, item disagreements, ambiguous, lost, exit fixes, and two flicker rows: a Shaman `consumedBy` row (§7) and
a target-DoT-past-duration row (rule 2.5.4). Measured, not gated (decision 86), except the owner's acceptance: no
flicker rise beyond seed noise (±0.3/min) on any spec in any viewer arm.

## 10. Risks and unknowns (only the game answers these)

| # | Question | Probe (ForeverProbe `aurasec`, `/fprobe cdm ...`; `~/src/forever-probe-cdm-report.md`) | Until answered |
|---|---|---|---|
| CDM-T | Does the rawget sweep leave `taint.log` clean for Hekili, the viewer and the damage meter after a pull? | `/console taintLog 1`, a pull with procs, ForeverProbe hooks off | release held; `Hekili.cdmOff` for a player |
| e4b | `IsVisible()`/`GetNumChildren()` plain and taint-clean in combat? Alt-Z reads not visible? | `/fprobe cdm items` with Alt-Z | if not plain: liveness out of combat only |
| ACQ | Frames created in combat (a viewer set to "In Combat")? | `/fprobe cdm hooks` with such a viewer, first fight after login | the `GetNumChildren` collect |
| CDM-O | Target switch: how long until target items are right? | `/fprobe cdm target` | `SETTLE` = 0.05 s |
| CDM-I | Instances: item fields plain/nil-or-secret? availability? | `/fprobe cdm items` in a dungeon, on a boss | secret field = not live; UNKNOWN |
| CDM-P | A partner's copy of our buff: confirm it never lights or drops our item | `/fprobe cdm items` in a party | rule 2.5.1 (`ours`) |
| CDM-M | `GetCooldownViewerCooldownInfo` in combat | `/fprobe cdm sets` in combat | never called in combat |
| D2T | A second mob with the same debuff; removal at death | `/fprobe cdm items`, two mobs | current target only; rule 2.5.4 bounds |
| e1-e3 | A Shaman flag-0 aura; a plain direct read in combat | `/fprobe aurasec`, `/fprobe aurawatch` | direct provider not built |
| LAT | Latency below 1 s | `/fprobe cdm hooks` timestamps | player: the next forced update (0.2 s); target changes we did not cause: up to 0.5 s (§3.3) |
| e6 | `ADDON_RESTRICTION_STATE_CHANGED` order | `/fprobe cdm events` | combat flags |

## 11. Decisions

| # | Decision | Reason |
|---|---|---|
| 92 | A fact reducer between evidence and belief: one reduced fact per (aura, unit); the belief reads only it | "1 fact per thing that we track" |
| 93 | Providers have a standing (walk 3 out of combat only, direct 2, CDM 1, model 0); the highest standing with live evidence decides | a plain walk carries durations; in combat a walk's "plain" is not trustworthy (I7) |
| 94 | `Reduce` is pure and total, table-tested; disagreements counted on transitions | no silent resolution |
| 95 | Any item in any viewer is evidence; role ignored; a slot is live for (j, u) only if it answers UP (unit from the plain `auraDataUnit`, F14) or a NONE that passes its own seen rule | F6; totality; F12 |
| 96 | Not evidence: an invisible viewer, an unconfigured or released slot, an unmapped item, a settling target slot, a secret identity field, a silent slot failing its seen rule; no item = UNKNOWN | no layout assumptions; F12 |
| 97 | UP counts for j only if every aura candidate of the item maps to j; an ambiguous item gives neither UP nor NONE (it never passes the seen rule) | `auraSpellID` secret (F3); untracked linked procs (I2); an ambiguous light names no single application |
| 98 | The map is keyed by cooldownID, complete over categories 0-8 with unlearned spells, built out of combat | in combat only the evidence set changes |
| 99 (supersedes 89) | Mid-fight layout changes apply as evidence changes; losing evidence makes a thing UNKNOWN and keeps its belief | the owner's amended 89 |
| 100 (supersedes 79) | Presence is read by a rawget sweep at poll 15, run before the `covered` guard | the refresh pair, release order and always-shown items vanish |
| 101 | No hooks; children collected at activation, rebuild, combat end and on `GetNumChildren` growth in combat | a hook buys no player latency (perf 2.1a); target-side 0.5 s accepted (D8); smallest taint surface |
| 102 | An invisible viewer (`IsVisible()`, parent-aware) gives no evidence | it stops updating (BV:1746-1751) |
| 103 | Target presence is the current target's only; a switch makes target slots settle for `SETTLE` | no per-GUID fact |
| 104 (amends 80) | Reconciliation in `Sources/Auras.lua` `apply`, rules 2.5.1-8 | one rule set outside CN13's file |
| 105 | The combat-exit walk's corrections are counted (`exitFix`) | P0 result 2's fact kind |
| 106 | Only aura presence is ingested from the CDM (§5) | "only where it adds information" |
| 107 (supersedes 82 for the viewer) | Always on, no option, no migration; the leaf turns itself off for the session on a Lua error; `Hekili.cdmOff` is the debug-only session off and the harness's arm switch | owner direction (toggle) |
| 108 | The coverage line is computed in `Options/` from the client API and `class.auras`; the CDM debug information is a section of the belief's own Snapshot, reaching the core through the SetLog logger: no new crossing | the border rule; owner Q5 |
| 109 | The direct never-secret provider only if a pack aura reads flag 0 | 15 of 15 contextual so far |
| 110 | The fake viewer models any layout and the client's order; the default arm stays viewer-off; viewer arms measured, not gated, except no flicker rise | the first loop A/B of the viewer |
| 111 | A player DOWN closes a record only if the reduced state is DOWN (its NONEs pass the seen rule, decision 115) and our evidence opened the record (`ours[k]`: our cast, a CDM UP, an out-of-combat walk read with source player/pet); a target NONE never closes | the viewer reads only our auras (C1); a silent item proves nothing (F12) |
| 112 | An UP with no model: registered duration from `max(fact.t, applied)`; past it a `HOLD` (1.0 s) re-staged once per `HOLD` while the fact stays UP; `math.huge` only for a player aura with no numeric duration | never stuck up on the target; bounded lapse; no per-poll churn (C2; owner Q3) |
| 113 | `apply` skips player form and enchant auras | their records belong to Forms/Enchants (M5) |
| 114 | CN13 owns a generic `I.auraFloor[j]`; this lane writes it from the reduced fact | no one-update flash; `Families/` knows nothing of the router (owner Q4) |
| 115 | **The seen rule, per slot**: a silent slot counts as NONE for (j, u) only for an application that slot was seen holding: the record is up (`U.exp0[u][j] > t`), `sSeen[s] >= U.applied[u][j]` and `sUnit[s] == u`; `sSeen` is written at every sweep the slot is held for u (unambiguous), reset at a mapping change, a rebuild, a held sweep with a secret or nil unit and, for a target slot, a target switch; otherwise not live, so UNKNOWN | an item can stay silent while its aura is up (F12); also closes the cast-before-`UNIT_AURA` flash (I-B) and the item-stops-following loop (I-A) for a fresh application (a refresh before expiry leaves one wrong close: §2.2a Residual, D14); per slot, not per thing, so a silent item never borrows another item's light (review 3); one number per slot (`MAX_SLOTS`), the leaf's own, no per-entry or per-thing state |

## 12. Credits

The hidden-viewer rule, the presence bit on items of all four viewers and the `overrideTooltipSpellID` /
never-`linkedSpellID` mapping are ideas from **TellMeWhen (Cybeloras)** (its method-hook technique was weighed and not
needed, §3.3), GPL-3.0 like Hekili Forever; ideas only, re-implemented, no code copied. Credit in the headers of
`Presence/CooldownViewer.lua` and `Presence/Reduce.lua` and in the credits, beside Catnip (Durts).

## 13. Candidate deferrals (for the controller's ledger)

| # | What | Why deferred | Trigger |
|---|---|---|---|
| D1 | The direct never-secret provider (§3.6) | 15 of 15 auras contextual so far | the Shaman `aurasec` run finds a flag 0 |
| D3 | Item `cooldownIsActive` secrecy as a corroboration counter | redundant with the NeverSecret spell API | the spell API's flags read secret somewhere |
| D4 | `ADDON_RESTRICTION_STATE_CHANGED` instead of combat flags | the walk's own result gates it | probe e6 shows a restriction outside combat the walk mis-reads |
| D5 | `SETTLE` from CDM-O; `IsVisible`/`GetNumChildren` from e4b | in game only | the owner's probe session |
| D6 | Coverage fixtures for classes other than Warrior and Druid | in game only | each class's `/fprobe cdm sets` |
| D8 | Target-side changes we did not cause wait up to 0.5 s (no hooks; the target's `UNIT_AURA` is not delivered in combat); upgrade: deliver it inside `Game/` while target coverage > 0 | small impact; a target NONE is no answer | the A/B or a player shows late target edges |
| D9 | `HOLD` = 1.0 s is a guess | no measurement | Task 9's target-DoT-past-duration flicker row |
| D13 | A player aura with no numeric duration whose item is lost mid-fight (viewer hidden, Alt-Z) stays up (-1) until combat ends and the exit walk closes it | rare: such auras are mostly permanent | Task 9 or a player report |
| D14 | The latency window between our cast's record write and the item lighting is unmeasured. Safe for a fresh cast (UNKNOWN until the item lights). A refresh before expiry whose new application the item does not light gives one wrong close (§2.2a Residual): one "rebuff", not a loop; no guard built | needs the game; one close per such refresh | the LAT probe (cast success vs `OnAuraInstanceInfoSet` timestamps), or a report of a single mid-fight rebuff |
| D15 | The cause of the silent Mark of the Wild item (F12) | needs the game | Task 10's `/fprobe cdm sets` on that entry |

D2 (stuck-up after losing a fact) and D7 (an acquire hook) are closed by decisions 112 and 101.

## 14. Owner answers recorded (2026-11-07)

Round 2 (P0 result 10) introduced decision 115; round 3 (review 2 §3, owner: keep it small) replaced its machinery with
the seen rule; round 4 (review 3) keys it per slot, so a silent item cannot borrow another item's light.


Q1 sweep: yes (controller's recommendation, reversible). Q2 no hooks: yes (same). Q3 registered duration: yes, made
complete by decision 112. Q4 floor: CN13 builds it (decision 114; Task 4c fallback). Q5: no command; the debug
snapshot (§6). Q6: superseded by "no toggle". New for the owner: confirm `Hekili.cdmOff` (a field on the addon table set
by `/run`, not a command or option) as the debug-only session off.
