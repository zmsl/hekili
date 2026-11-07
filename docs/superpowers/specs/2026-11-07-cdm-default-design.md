# Cooldown Manager facts by default: one reduced fact per tracked thing (spec amendment, 2026-11-07)

Status: DESIGN (not built). Plan: `docs/superpowers/plans/2026-11-07-cdm-default.md`.
Amends `docs/superpowers/specs/2026-10-23-providers-design.md` ("the providers spec", decisions 65-91). New decisions
are numbered from 92. Paths are under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`. Line numbers
are as of `integ/0.7` a0bd6f8dd.

Supersedes or amends: **89** (superseded: §3.4), **79** (superseded: the hook is a wake-up, not the read, §3.3),
**80** (amended: the consumer reads the reduced fact, §4), **82** (amended for the viewer: default ON, a visible
toggle, §6), **88** (amended: the router hosts the reducer, §2.4), and the providers spec §2.4 "Only BuffIcon and
BuffBar items are presence sources" and its taint rule (superseded: §3.2, §3.5).

Inputs: the owner-approved plan (`~/src/hekili-cdm-default-plan.md`, P0 results 1-9, the owner's answers and the
"reduce to one fact per tracked thing" direction), the Druid probe (`~/src/hekili-central-needs/druid-probe-2026-11-07.txt`),
the TellMeWhen research (`~/src/hekili-central-needs/tmw-research.md`, "TMW"), the 2026-10-23 research
(`docs/research/2026-10-23-cooldown-manager-api.md`, "CV") and Blizzard's Forever UI source
(`Blizzard_CooldownViewer`, "BV": `CooldownViewer.lua`, "BD": `CooldownViewerItemData.lua`).

## 0. The owner's requirements

1. By default and with no setup beyond the game's own Cooldown Manager (CDM), what the CDM shows enriches the
   belief's aura records. Default ON, with a visible profile toggle (owner, 2026-11-07, answer 1).
2. A generic fact layer, not Lightning Shield code: any fact the CDM can give becomes an observation in the belief's
   existing records through one mechanism; with no fact the belief keeps its closest accurate model (owner
   clarification 2026-11-07).
3. "Take in all the info we can get from the CDM and reduce it down into 1 fact per thing that we track, so that we're
   not making any assumptions and are open to all forms of configs" (owner direction 2026-11-07).
4. Mid-fight changes allowed (decision 89 amended, owner question 2026-11-07).
5. A direct never-secret read in the same release, CONDITIONAL on a Shaman finding an aura with secrecy flag 0 (P0
   result 2: all 15 spells tested over two classes are contextual).

## 1. Measured facts this rests on

Relied on as measured (the brief's list, plus the coordinator's P0 results 8-9):

| # | Fact | Source |
|---|---|---|
| F1 | Contextual auras (flag 2) read nil by direct read in combat, a table out of combat | Clearcasting 16870, probe §5 |
| F2 | A viewer item's `auraInstanceID` existence flips hidden->shown on gain and back on removal in combat within 1 s | Thorns 199474, Enrage 199381, probe §6, §9 |
| F3 | `auraSpellID` is secret when the aura was applied in combat, plain otherwise: never depend on it | probe §6, §9 |
| F4 | An item can hold a linked spell's aura (Omen entry 199480 links Clearcasting 16870) and lights on the proc | probe §7, P0 result 7 |
| F5 | One spell has separate cooldownIDs per role (Essential/Utility vs TrackedBuff) | probe §8 |
| F6 | **Cooldown entries (Essential, Utility) carry `auraInstanceID` while the spell's aura is up, in combat**, for a self buff and a target debuff, gain and removal | Enrage 199382, Moonfire 199545, probe §10 (P0 result 9; revises result 5) |
| F7 | A target debuff entry lights on a mob | Faerie Fire 199443, P0 result 8 (visual) |
| F8 | Coverage is a property of the player's layout (what the viewers hold), not of the category sets | probe §8 |
| F9 | The combat-exit walk is ground truth for every aura | `Sources/Auras.lua:165-190` |
| F10 | The viewer tracks player-cast auras only (scope "self") | CDM-S, providers spec §2.4 |

Read from source (Forever UI, not measured): `SetAuraInstanceInfo` calls `ClearAuraInstanceInfo` first when the
instance changes, then sets the fields, then `OnAuraInstanceInfoSet` (BD:371-380); `ClearAuraInstanceInfo` clears
`auraInstanceID`, `auraSpellID`, `auraDataUnit` before `OnAuraInstanceInfoCleared` and fires nothing when nothing was
held (BD:382-392); a pool release runs `ResetCooldownData`, which sets `cooldownID = nil` **before** it clears the aura
(BD:96-98, BV:1645-1650); a re-pointed item clears then refreshes (BV:176-177); a hidden viewer unregisters `UNIT_AURA`
and stops updating its items (BV:1746-1750).

Doubted or unmeasured (the design does not lean on them; each is in §10): sub-second edge latency (only bounded by the
1 Hz sampler); whether the method hooks are taint-free (probe e4, CDM-T); target-switch ordering (CDM-O); a second mob
with the same debuff; instances (CDM-I); partner-cast buffs on us (CDM-P); F7 is a visual report only.

## 2. The fact reducer (the core of this amendment)

### 2.1 The model

A **thing** is a pack aura on a unit: the pair (j, u), aura index j in `def.auras` order, unit u (1 player, 2 the
current target). Every tracked thing has exactly one **reduced fact** the belief reads. Evidence about a thing comes
from **providers**, each with a **standing**:

| Standing | Provider | Evidence | Carries |
|---|---|---|---|
| 3 | the aura walk (`Sources/Auras.lua` `walk`), plain only (always out of combat, so the combat-exit walk) | found / not found per aura | remaining time, stacks |
| 2 | the direct never-secret read (`Presence/Direct.lua`, CONDITIONAL, §3.6) | a plain table / nil for a never-secret aura | remaining time, stacks |
| 1 | CDM items (`Presence/CooldownViewer.lua`, §3) | per item: holds an aura / holds none | presence only |
| 0 | none | | the belief's model runs alone |

The highest standing with live evidence decides; lower standings are not consulted for that thing at that moment.
Standing 3 already wins today (providers decision 80: "a plain walk always wins"); this spec names it as evidence
rather than a special path, and keeps its code (it writes `Obs.Read` with durations directly, `Sources/Auras.lua:119`).

### 2.2 Evidence from items

One item frame in a viewer is one **evidence slot**. A slot counts as evidence for thing (j, u) only when ALL hold:

- its viewer is shown (`viewer:IsShown()` plain true); a hidden or disabled viewer's items are not evidence (BV:1746-1750:
  they stop updating);
- it is configured: `cooldownID` plain and non-nil (an unconfigured slot, the Buff bar's `nil` rows in probe §8, is not
  evidence);
- its `cooldownID` maps to aura j (§3.1); an item whose cooldown info could not be read, or that maps to nothing, is not
  evidence;
- for u = 2 only: it is not **settling** (§3.4, target switch).

A slot's reading is `held = issecretvalue(aid) or aid ~= nil` with `aid = rawget(item, "auraInstanceID")` (no compare on
a secret). `held` with a plain `auraDataUnit` ("player" 1, "target" 2) is **UP evidence for that unit only**. Not held is
**NONE evidence for both units** of its aura (the item says none of its auras is on anyone it scans, BD:23-35). The role
of the entry (Essential, Utility, Buff icon, Buff bar) plays no part (F6): any mix and any number of items per spell is
the same reduction.

An item that maps to **more than one** pack aura (its spellID, override, tooltip override and linked spells name two
pack auras) is **ambiguous**: its NONE counts for every aura it maps to; its UP counts for none of them (the aura's own
spell id is secret in combat, F3, so it cannot say which one is up). Counted per fight as `ambiguous`.

### 2.3 The reduction: one pure function

Per thing and standing the provider keeps preallocated counters: `nLive` (evidence slots), `nUp`, `nNone`, `nStale`
(slots that exist and map here but are not evidence right now: hidden viewer, settling target), `tUp`, `tNone` (the
latest time a slot's reading changed to UP / to NONE). The reduction is

```
Reduce(nLive, nUp, nNone, nStale, tUp, tNone) -> state, agree
```

| Case | state | agree |
|---|---|---|
| `nLive == 0` | UNKNOWN | true |
| `nUp > 0`, `nNone == 0` | UP | true |
| `nUp == 0`, `nNone > 0`, `nStale == 0` | DOWN | true |
| `nUp == 0`, `nNone > 0`, `nStale > 0` | UNKNOWN (a stale item may hold it) | true |
| `nUp > 0`, `nNone > 0`, `tUp >= tNone` | UP (no fresher contradiction) | false |
| `nUp > 0`, `nNone > 0`, `tNone > tUp` | UNKNOWN (a fresher NONE contradicts) | false |

Pure: no upvalues, no tables, numbers in, two values out. It lives in `Presence/Reduce.lua` as `I.ReduceFact` and is
tested by a table of rows (plan Task 1). Every provider's counters go through it; the router picks the highest standing
whose `nLive > 0` (§2.4). Disagreement is never resolved silently: a reduction with `agree == false` at poll 15
increments `disagree[k]` (a sub-frame lag between two viewers handling the same `UNIT_AURA` resolves before the poll and
is not counted).

### 2.4 The reduced record and the router

`Presence/Router.lua` (still the injected provider, decision 88) holds, preallocated at build for both units:

```
fact.state[k]   0 UNKNOWN, 1 UP, 2 DOWN            fact.n[k]      evidence count (nLive of the deciding standing)
fact.agree[k]   true/false                         fact.t[k]      time of the last state change
fact.from[k]    the deciding standing (0-3)        fact.via[k]    provenance bitmask: 1 Essential, 2 Utility, 4 Buff icon,
                                                                  8 Buff bar, 16 direct (OR of the live slots' viewers)
fact.disagree[k], fact.ambiguous[k], fact.lost[k]  per-fight counters (lost: a thing that had a fact went UNKNOWN)
```

with `k = (u - 1) * I.AURA_UNIT + j`. `R.Presence(j, u)` returns `fact.state[k]` (UP/DOWN or `I.UNDECIDED`), keeping
the scope rule: a self-scoped DOWN on the target is no answer (`Router.lua:22-24`, unchanged). The contract (providers
§1.2) gains one optional leaf field, `Q.Counts(j, u)` returning the six counters (numbers; no allocation); `Presence`,
`onEdge`, `covered`, `scope` stay. Leaves still share no code and never call each other (decision 66).

### 2.5 What the belief does with a reduced fact (reconciliation)

One rule set, in `Sources/Auras.lua` `apply` (`:218-243`), not in `Families/Auras.lua` (CN13's file, §7):

1. **A fact beats the model for presence.** UP while believed down, or DOWN while believed up, stages
   `Obs.Read` (today's rule, decision 80).
2. **Between facts the model runs.** UP while believed up stages nothing: the modelled expiry, stacks and consumption
   stand. Poll 15 re-asks every poll, so if the model's expiry passes while the fact still says UP, the same drain
   re-stages UP before the belief is read (no visible gap).
3. **UP with no model behind it** (believed down): remaining = the aura's registered numeric duration
   (`def.auras[j].duration`) minus the time since the fact turned UP (`fact.t[k]`) when that is positive; else -1
   (unknown expiry: `Families/Auras.lua:205` stores it as `math.huge`). Reason: with `math.huge` a DoT or proc never
   reads `refreshable` and its `remains` is infinite, so a refresh line would wait for the DOWN edge; the registered
   duration is the closest accurate model, and a later DOWN fact closes it either way.
4. **DOWN closes the record** (`Obs.Read` 0).
5. **UNKNOWN leaves the model untouched** and says so (`fact.from[k] == 0` in the debug line). A thing that had a fact
   this fight and loses it (item released, viewer hidden, target settling) keeps its last belief; the model ends it.
   That is the hysteresis of amended rule 89 (4): no basis flip mid-record, so no flap (plan: the flap test).
6. **A plain walk wins** (standing 3), as today (`playerPlain` / `targetPlain`).
7. **Edges request a cycle.** A change of a reduced state calls the existing `onEdge` path (`Sources/Auras.lua:244-250`:
   stage, then deliver the synthetic `UNIT_AURA` so Hekili refreshes).

Facts and disagreements with the belief keep today's per-aura audit (`facts[k]`, `disagree[k]`, decision 90).

### 2.6 The combat-exit reconcile as a measured fact

The first plain walk after `PLAYER_REGEN_ENABLED` (`Sources/Auras.lua:165-190`) is standing-3 evidence for every aura.
It already corrects the belief; this spec makes it **counted**: the walk that clears `pending` counts, per thing,
`exitFix[k]` when it changes the believed presence (believed up and not found, or found while believed down). Snapshot
line `presence exit <key> unit=%s fixes=%d`, reset per fight. The A/B reports exit fixes per spec with the viewer arm on
and off: the number that says how wrong the model alone is at a fight's end. No new event, no taint surface.

## 3. The CDM provider

### 3.1 The map: cooldownID -> aura, complete, out of combat

Built at activation and rebuild, out of combat only (allocates: the getters' tables):

- `C_CooldownViewer.GetCooldownViewerCategorySet(c, true)` for c = 0-8 (**`allowUnlearned = true`**, so a spell learned
  mid-fight or an item re-pointed in combat is already in the map);
- per cooldownID, `GetCooldownViewerCooldownInfo(id)`; candidate spell IDs: `spellID`, `overrideSpellID`,
  `overrideTooltipSpellID`, every entry of `linkedSpellIDs`, and `C_Spell.GetOverrideSpell(x)` of each; **never the
  singular `linkedSpellID`** (the viewer writes the secret aura spell id into it, TMW `Auras.lua:960-1010`);
- each candidate is looked up in the pack's aura IDs (`def.auraIds[j]`, every rank); 0 matches: unmapped; 1: `cdvToJ[id]
  = j`; 2 or more: ambiguous, `cdvToJ[id] = -a` with `amb[a]` the list of j (§2.2).

Today's first-match rule (`CooldownViewer.lua:92-98`, `Router.lua:66-72`) is replaced by this. The router's own
`tracked[j]` (`Router.lua:43-80`) becomes "mappable" (some cooldownID maps to j) and is no longer the path: the path is
the reduced fact (§2.4). The router reads the sets through the leaf's map rather than duplicating it: the leaf exposes
`Q.Mappable(j)` (a boolean read).

Rebuild triggers: `COOLDOWN_VIEWER_DATA_LOADED`, `..._TABLE_HOTFIXED` (today), and
`COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`; in combat they set `pending` and rebuild at combat end (as today). Because the
map is keyed by cooldownID and complete over all categories with unlearned spells, a layout change in combat needs no
rebuild: it only changes the evidence set (§3.2).

### 3.2 The read: a sweep of the items at poll 15, by rawget

The evidence is **read, not pushed**: at poll 15 (every drain, `Sources/Auras.lua:257-271`) the leaf sweeps its slot
list. Per viewer: `IsShown()` once. Per slot: `rawget` of `cooldownID`, `layoutIndex`, `auraInstanceID`,
`auraDataUnit`; the slot's reading is compared with its stored one and, on a change, the counters of the affected things
move in O(1) and `tUp`/`tNone` take the poll's time. Then the router reduces only the things whose counters moved.

Why a sweep rather than state from hooks: every hazard in the hook path disappears.

- **The refresh pair.** `SetAuraInstanceInfo` clears then sets in one call (BD:371-380); BV:176 clears then refreshes on
  a re-point. A sweep runs after the call stack: it never sees the intermediate NONE. No collapse logic is needed.
- **The release order.** A released frame's Cleared fires with `cooldownID` already nil (BD:96-98) and a released
  frame that held nothing fires nothing at all. A sweep sees `cooldownID == nil` / `layoutIndex == nil` and drops the
  slot from the evidence (the item left: UNKNOWN for its thing if it was the last, never DOWN).
- **Re-pointing.** The slot's stored j differs from the new cooldownID's: the old thing loses a slot, the new one gains
  one.
- **Essential and Utility items** are always shown, so `OnShow`/`OnHide` never fire for them (F6 makes them evidence):
  the sweep reads them like any other.

Cost: four `IsShown` calls and four rawgets per slot per drain (a full layout is about 30-60 slots), no allocation.

### 3.3 Hooks: a wake-up, not the read (supersedes decision 79)

Latency. The real `UNIT_AURA` fires for the player and the target in combat (its payload is secret, the event is not),
and Hekili already runs a forced cycle on it; the viewer handles the same event in its own frame's `OnEvent`. So the
sweep normally sees the viewer's new state at the next drain. If the measured order puts our drain before the viewer's
refresh (probe e4 records it), the change waits one update (0.1-0.2 s in combat).

The method hooks close that gap, **gated on probe e4/CDM-T** (§10):

- `hooksecurefunc(viewer, "OnAcquireItemFrame", onAcquire)` once per viewer (out of combat, at first activation):
  `onAcquire` appends a new frame to the slot list (a bounded insert, once per pooled frame's lifetime) and hooks it;
- `hooksecurefunc(frame, "OnAuraInstanceInfoSet", wake)` and `(frame, "OnAuraInstanceInfoCleared", wake)` once per
  frame (a weak-keyed `hooked` set; one shared function `wake`, no closure per frame);
- `wake` reads nothing and stores nothing: it delivers the synthetic `UNIT_AURA` for the player token (the existing
  forced cycle), at most once per frame (`GetTime()` compared with the last wake's).

**The gate and its fallback.** If e4/CDM-T shows any taint naming Hekili or a `CooldownViewer` frame: no item hooks at
all, no `OnAcquireItemFrame` hook; slots come from `GetChildren()` out of combat only (today's walk,
`CooldownViewer.lua:107-133`), and the sweep alone reads them (latency one update at worst). Either way today's
`HookScript("OnShow"/"OnHide")` is **removed** (TMW #2463: HookScript on Blizzard frames that hide in secure paths
spreads taint; and it cannot see Essential/Utility edges). The fallback is a constant in the leaf (`WAKE_HOOKS`), set by
the plan's probe checkpoint; both paths are tested.

### 3.4 The target

Target evidence is presence **on the current target only**, never per GUID (P0 result 8). On `PLAYER_TARGET_CHANGED`
the leaf marks every slot whose last unit was the target (and every unit-less NONE slot) as **settling** until a sweep
at a later frame than the event (`settleUntil = t + SETTLE`, `SETTLE` = one frame, 0.05 s until CDM-O measures the
viewer's re-point order); settling slots are `nStale`, so the target's thing reads UNKNOWN meanwhile (§2.3) and the
belief's per-target memory (`Families/Auras.lua:255-264`) is neither written with the old target's state nor flipped.
This replaces today's immediate re-read (`CooldownViewer.lua:161-168`), which could copy the old target's state into
the new one. The self-scoped DOWN on the target stays no answer (`Router.lua:22-24`).

### 3.5 The taint rule (supersedes providers spec §2.4's)

Read, never write: item fields by `rawget`; on Blizzard frames only `GetChildren()` (out of combat) and `IsShown()`
(any time, read-only widget getter); hooks only by `hooksecurefunc` on the four viewers' `OnAcquireItemFrame` and on
item frames' `OnAuraInstanceInfoSet`/`Cleared`, behind the gate (§3.3); no `HookScript`; never a call to a viewer or
item Lua method; nothing written to a viewer table or frame (CV §5). Hooks cannot be removed: `Deactivate` sets `active
= false` and `wake` returns after that test. A Lua error inside the leaf's sweep is caught once (`pcall` around the
sweep body, out of the per-slot loop) and turns the leaf off for the session with one `def.error` line: the in-code
kill switch.

### 3.6 The conditional direct never-secret provider

Built only if the Shaman run finds a pack aura with `C_Secrets.GetSpellAuraSecrecy(id) == 0`. `Presence/Direct.lua`:
at build (out of combat) classify every pack aura ID; on `UNIT_AURA` for the player (and the target) read
`C_UnitAuras.GetPlayerAuraBySpellID(id)` / `GetUnitAuraBySpellID("target", id)` for flagged IDs only, each field through
`issecretvalue`; a plain table stages a full `Obs.Read` (remaining, stacks) as the walk does (standing 2); nil is NONE
(the flag says it never hides); on the target an UP counts only with a plain `sourceUnit` of player or pet. New API
names join `tools/api_inventory.txt`. Ranks: every rank ID (TMW `buffcontainer.lua:185`).

## 4. Providers and the belief: contract changes

| Item | Today | After |
|---|---|---|
| `Q.Presence(j, u)` | leaf state per pair, one value (`CooldownViewer.lua:153-159`) | the router returns the reduced `fact.state[k]` |
| `Q.Counts(j, u)` | none | leaf: the six counters for the reducer |
| `Q.Mappable(j)` | router's own `mark` | leaf's map |
| `Q.covered` | aura indices with a BuffIcon/BuffBar item | aura indices with at least one live slot in any viewer (recounted at each sweep that moves a count) |
| `onEdge` | leaf -> router -> consumer per hook | router -> consumer on a reduced state change (from poll 15) |
| poll 15 | consumer asks `P.Presence` for every pair | leaf sweep, router reduce, consumer `apply` for the pairs that changed (and every pair, as today, for the model-lapse rule 2.5.2) |

Ordering inside poll 15: the sweep and reduction must run before the consumer's loop. Poll orders 13-14 are taken, so
the consumer's poll-15 function calls `P.Sweep(t)` first (a new contract field; the Default provider's is a no-op, and
the router's calls its leaves' `Sweep` then reduces).

## 5. What the CDM offers, and what we ingest

| Field / API | Secrecy in combat (measured) | Fact it supports | Redundant? | Ingested |
|---|---|---|---|---|
| item `auraInstanceID` | secret while up, nil while down (CV §2, F2, F6) | aura presence, any item, any viewer | no: the walk is secret in combat | **yes**, existence only |
| item `auraDataUnit` | plain (CV §2) | which unit the presence is for | no | **yes**, while held |
| item `auraSpellID` | secret if applied in combat, plain otherwise (F3) | which aura | n/a | **no** (unreliable by design) |
| item `cooldownID` | plain (CV §2) | the slot's identity, the map key | no | **yes** |
| item `layoutIndex` | plain | the slot is configured / not released | no | **yes** (liveness only) |
| viewer `IsShown()` | plain (getter; e4 confirms) | evidence liveness | no | **yes** |
| `GetCooldownViewerCooldownInfo` fields `spellID`, `overrideSpellID`, `overrideTooltipSpellID`, `linkedSpellIDs`, `selfAura`, `hasAura` | plain out of combat (CV §2, probe §7); in combat unmeasured | the map | no | **yes**, out of combat only |
| info `linkedSpellID` (singular) | secret (TMW) | | | **never** |
| `GetCooldownViewerCategorySet(c, allowUnlearned)` | plain out of combat | the map's universe | no | **yes**, out of combat only |
| item `isActive`, `shown` | plain (CV §2) | the item is active / drawn | `shown` of a cooldown entry says nothing about the aura (F5); `isActive` duplicates `C_Spell.GetSpellCooldown().isActive` (NeverSecret, `Sources/Spellbook.lua`) | **no** |
| item `isOnGCD` | plain (CV §2) | GCD running | yes: `GetSpellCooldown().isOnGCD` NeverSecret | **no** |
| item `cooldownIsActive` | plain while ready or on GCD, secret while a real cooldown runs (CV §2) | "a real cooldown runs" by `issecretvalue` | yes: the spell API's NeverSecret flags give it directly | **no** (candidate corroboration, deferral D3) |
| cooldown times, charge text, stack text | secret (CV §2, CDM-S 5609) | | | **never** |
| `IsCooldownViewerAvailable()` | plain | the provider can run | | **yes** (activation) |
| `ADDON_RESTRICTION_STATE_CHANGED` | event, plain (TMW e6) | when walks fail | partly: the walk's own plain/secret result already gates it | **no** (candidate, D4) |

So the only fact kind is aura presence (self and current target, including procs through linked spells). The registry
(§2.1's table) admits a cooldown kind later without new structure: a provider row with its record and Obs kind.

## 6. Default ON, the toggle, coverage, the debug command

- **Default flip.** `Options/Options.lua:312` `cooldownViewer = true`. `providersOf` (`Engine/Schema/Tracked.lua:216-226`)
  reads `cooldownViewer` from `e.settings.performance` in every build (not only `Hekili.IsDev`); the other three stay
  dev-only. AceDB stores only non-default values, so a profile that saved `false` stays off; one that never touched it
  turns on.
- **The toggle** leaves the Experimental header (`Options.lua:4212-4227`) for its own visible group, "Cooldown Manager
  facts", in the Performance tab (or the General tab: Sonnet's choice, owner's eye at review), not dev-gated. Text says
  what it needs (the CDM enabled in the game options, the aura on any of its four bars, the bar shown) and that it gives
  presence only.
- **The coverage line** (per spec, below the toggle): "N of M tracked auras have an item in a Cooldown Manager bar; to
  cover X, Y and Z, add them to any bar in the Cooldown Manager settings (Tracked Buffs is simplest)." Computed **in
  the core** (`Options/`, a helper beside the toggle), out of combat when the panel draws, from `C_CooldownViewer` (the
  four viewers' children by `GetChildren`, `rawget` `cooldownID`, the cooldown info's IDs as §3.1) and the active spec's
  `class.auras` IDs. No belief read, so **no new belief-to-core crossing**. The helper duplicates the ID match (about 30
  lines, options-only); the plan's test compares its count with the belief's `covered` on the same fake layout.
- **The kill switch** is the toggle (applies at once out of combat, else at combat end: `VS.SetProviders`, unchanged),
  plus the leaf's self-off on error (§3.5). Kept for at least one release (plan P4).
- **The debug command** `/hekili cdm`: prints the presence lines of the belief's `Snapshot()` through the existing debug
  bridge (`Hekili.Virtual.State.Snapshot()`, `Hekili.lua:213-215`; the route ForeverProbe already uses) to the copy
  box. Lines (one per thing with evidence or a fact this fight, under 255 chars):
  `presence <key> unit=%s fact=up|down|unknown from=walk|direct|viewer|model n=%d via=EUBR agree=%s facts=%d disagree=%d
  itemDisagree=%d exitFixes=%d lost=%d` and one summary line `presence covered=%d/%d ambiguous=%d unmapped=%d
  hooks=on|off|fallback`. No new crossing: the debug bridge is existing (`SetLog`'s `logger.debug`,
  `Game/API/Facade.lua:64-70`) and `tools/check_border.sh` is unchanged; the plan runs it.

## 7. Composition with CN13 (the generic consumption model)

CN13 (in flight; `Families/Auras.lua` `Obs.PlayerHit`, `:238-252`, and `Sources/Player.lua` hit staging) is the model
when no fact exists: kind-only staging of hits whose amount is secret, so any `consumedBy` aura loses charges, and a
class-neutral per-aura consume ICD. With a fact:

- UP fact, believed up: the model's stack count and expiry stand (§2.5.2); CN13 keeps spending charges.
- CN13 spends the last charge (believed down) while the fact still says UP: the fact wins at the next poll (§2.5.1); the
  record comes back up with the registered duration (§2.5.3) and stacks 1 (unknown). Counted as a disagreement:
  the A/B's measure of CN13's error.
- DOWN fact while CN13 believes charges remain: the record closes (§2.5.4).
- No fact (UNKNOWN): CN13 alone.

No code in this lane touches `Families/Auras.lua`; reconciliation is in `Sources/Auras.lua` `apply`. Merge conflicts
with CN13 are therefore limited to `Sources/Auras.lua` if CN13 edits it (it should not), and to the harness.

## 8. Secrets and allocation

- Secrets: `auraInstanceID` only through `issecretvalue(x) or x ~= nil`; every other read through `S.Plain`; a secret
  `cooldownID`, `layoutIndex` or `auraDataUnit` makes the slot not evidence for that sweep (counted `secretField`);
  nothing read is passed back to an API; never `a and b or c` on a raw value.
- Allocation: none in the sweep, the reduction, the router or `apply` (preallocated arrays at build for every thing and
  every slot index up to `MAX_SLOTS` = 128; a frame is mapped to its slot index by a weak-keyed table written once per
  frame lifetime). Bounded, once-per-frame inserts in `onAcquire` (new pooled frames, rare) are the only in-combat
  inserts; `alloc_spec` covers the sweep and the reduction.

## 9. Harness and A/B (detail in the plan)

The fake viewer (`tests/Game/State/helpers/fake_api.lua:666-712`) models any layout: per viewer a list of frames
(configured or `cooldownID` nil), `IsShown`, `OnAcquireItemFrame` and per-frame `OnAuraInstanceInfoSet`/`Cleared`
methods (so `hooksecurefunc` works), infos with `overrideTooltipSpellID`, `linkedSpellIDs` and a secret singular
`linkedSpellID`, category sets honouring `allowUnlearned`, and the client's order (clear then set; release clears
`cooldownID` first). The drive's `@viewer` (`tests/Game/harness/drive.lua:457-466`) sets the aura on every item in any
viewer whose info names the spell, cooldown entries included; new ops acquire, release, re-point and hide. Layout
presets per spec: `none`, `buffs` (an aura entry per pack aura), `fixture` (from `tools/data/cooldownviewer/<CLASS>.lua`
plus cooldown entries carrying aura state), `mixed` (duplicates across viewers, unconfigured slots, a hidden viewer).

The A/B arms: `default` (viewer off, explicitly: `tests/Game/harness/loop.lua:333`, `ab.lua:6`), `viewer-none`,
`viewer-buffs`, `viewer-fixture`, `viewer-mixed`; measured per spec: flicker/min, readyShort, agreement, facts,
disagreements, item disagreements, exit fixes. Measured, not gated (decision 86), except: no flicker rise beyond the
seed noise (±0.3/min, providers spec §4.1) on any spec in any viewer arm (the owner's acceptance).

## 10. Risks and unknowns (only the game answers these)

| # | Question | Probe (ForeverProbe `aurasec`, `/fprobe cdm ...`; `~/src/forever-probe-cdm-report.md`) | Until answered |
|---|---|---|---|
| e4 / CDM-T | Do `hooksecurefunc` hooks on `OnAcquireItemFrame` and item `OnAuraInstanceInfoSet/Cleared` taint the viewer or the damage meter in combat? Do the edges arrive, in which order against our drain? | `/fprobe cdm hooks` with `/console taintLog 1`, a pull with procs; `Logs/taint.log` | `WAKE_HOOKS = false` (sweep only) |
| e4b | `IsShown()` on the viewers from addon code in combat: taint-clean? | same run | if not: viewer liveness read only out of combat, a hidden-in-combat viewer undetected (risk named in the toggle text) |
| CDM-O | `PLAYER_TARGET_CHANGED` against the viewer's target re-point: how long until target items are right? | `/fprobe cdm target` (+0/+50/+200 ms/+1 s) | `SETTLE` = 0.05 s |
| CDM-I | Instances and encounters: item fields still plain/nil-or-secret? `IsCooldownViewerAvailable` changes? | `/fprobe cdm items` in a dungeon and on a boss | a secret field = not evidence; UNKNOWN, never DOWN |
| CDM-P | A partner-cast copy of our buff: does it hold or drop our item? | `/fprobe cdm items` in a party | player DOWN taken as a fact (risk: a partner's copy) |
| CDM-M | Is `GetCooldownViewerCooldownInfo` plain in combat? (only matters if a rebuild is ever wanted in combat) | `/fprobe cdm sets` in combat | never called in combat |
| D2T | A second mob with the same debuff; the debuff falling off at death | `/fprobe cdm items` with two mobs | target presence is the current target's only |
| e1-e3 Shaman | Is any Shaman aura (Lightning Shield, Water Shield) flag 0? Does a direct read return a plain table in combat? | `/fprobe aurasec`, `/fprobe aurawatch` | the direct provider is not built |
| LAT | Edge latency below 1 s | `/fprobe cdm hooks` timestamps | the sweep's one-update bound |
| e6 | `ADDON_RESTRICTION_STATE_CHANGED` order vs `PLAYER_REGEN_*` | `/fprobe cdm events` | combat flags (today) |

## 11. Decisions

| # | Decision | Reason |
|---|---|---|
| 92 | A **fact reducer** sits between evidence and belief: one reduced fact per tracked thing (aura, unit); the belief reads only the reduced fact | the owner: "1 fact per thing that we track" |
| 93 | Providers have a **standing** (walk 3, direct 2, CDM 1, model 0); the highest standing with live evidence decides | a plain walk already wins (decision 80); a never-secret read carries durations; items carry presence only |
| 94 | `Reduce(nLive, nUp, nNone, nStale, tUp, tNone)` is one pure function with a table-driven test; rules in §2.3 | no silent resolution; testable alone |
| 95 | Evidence is per item; the entry's role does not matter: any item in any viewer whose cooldown info names the aura; UP needs a held `auraInstanceID` with a plain unit, NONE counts for both units | F6 (P0 result 9 revises result 5): cooldown entries carry aura state |
| 96 | Not evidence: a hidden viewer's items, an unconfigured slot, an unmapped or info-less item, a settling target item, a secret identity field; no item anywhere = UNKNOWN, never DOWN | no layout assumptions (owner direction) |
| 97 | An item mapping to two or more pack auras: NONE for all, UP for none | `auraSpellID` is secret in combat (F3) |
| 98 | The map is keyed by cooldownID, complete (categories 0-8, `allowUnlearned = true`, spellID, overrideSpellID, overrideTooltipSpellID, linkedSpellIDs, each through `GetOverrideSpell`; never singular `linkedSpellID`), built out of combat; rebuild events in combat wait for combat end | in combat the evidence set changes, the map need not (owner's amended 89 (1)-(2)) |
| 99 (supersedes 89) | Mid-fight layout changes apply at once as evidence changes (additions count at the next sweep; removals make a thing UNKNOWN and keep its belief); hysteresis: UNKNOWN never flips the belief; no full rescan in combat | the owner's amended 89 (1)-(5) |
| 100 (supersedes 79) | Presence is read by a rawget sweep of the slots at poll 15; hooks only wake a cycle | the clear-then-set pair, the release order (`cooldownID` nil before Cleared) and Essential/Utility items (never hidden) all vanish under a sweep |
| 101 | Wake hooks (`hooksecurefunc` on `OnAcquireItemFrame` and item `OnAuraInstanceInfoSet/Cleared`) behind the e4/CDM-T gate; fallback: sweep only, frames from `GetChildren` out of combat; `HookScript` removed either way | TMW's technique (credited), taint unproven on Forever |
| 102 | A hidden or disabled viewer's items are not evidence (`IsShown()` per sweep) | it stops updating (BV:1746-1750) |
| 103 | Target presence is the current target's only; a target change makes target items settling for `SETTLE` (0.05 s until CDM-O) | no per-GUID fact; no copy of the old target's state into the new one |
| 104 (amends 80) | Reconciliation in `Sources/Auras.lua` `apply`: fact beats model; between facts the model runs; UP with no model = registered duration from the fact's time, else -1; DOWN closes; UNKNOWN leaves the model; plain walk wins | one rule set, outside CN13's file |
| 105 | The combat-exit walk is counted evidence (`exitFix` per thing, a Snapshot line, an A/B column) | P0 result 2's new fact kind, cheap and class-neutral |
| 106 | Only aura presence is ingested; item cooldown flags are redundant with the NeverSecret spell API and are not ingested (§5 table) | owner's "only where it adds information" |
| 107 (amends 82) | `cooldownViewer` defaults ON in every build with a visible, non-dev toggle; the leaf turns itself off for the session on a Lua error | owner answer 1; a kill switch |
| 108 | The coverage line is computed in the core (Options) from the client API and `class.auras`; `/hekili cdm` prints through the existing debug bridge: no new belief-to-core crossing | the border rule; owner yes not needed |
| 109 | The direct never-secret provider is built only if a pack aura reads flag 0; otherwise dropped and recorded | P0 result 2 (15 of 15 contextual) |
| 110 | The harness fake viewer models any layout and the client's call order; the default arm stays viewer-off explicitly; viewer arms per layout preset are measured, not gated, except no flicker rise beyond noise | the first loop A/B of the viewer (providers-ab.md: none possible before) |

## 12. Credits

The method-hook technique (`OnAcquireItemFrame` + `OnAuraInstanceInfoSet/Cleared` via `hooksecurefunc`), the
hidden-viewer rule and the `overrideTooltipSpellID` / never-`linkedSpellID` mapping are ideas from **TellMeWhen
(Cybeloras)**, GPL-3.0 like Hekili Forever; ideas only, re-implemented, no code copied. Credit in the file headers of
`Presence/CooldownViewer.lua` and `Presence/Reduce.lua` and in the credits, beside Catnip (Durts).

## 13. Candidate deferrals (for the controller's ledger)

| # | What | Why deferred | Trigger |
|---|---|---|---|
| D1 | The direct never-secret provider (§3.6) | 15 of 15 auras contextual so far | the Shaman `aurasec` run finds a flag 0 |
| D2 | A thing that loses its fact mid-fight with an unknown (`math.huge`) expiry stays up until the model or the exit walk ends it; cap it at the registered duration from its last UP | rare (layouts do not change in combat); counted as `lost` | the A/B or a player shows `lost` > 0 with a stuck aura |
| D3 | Item `cooldownIsActive` secrecy as a corroboration counter for cooldown readiness | redundant with the NeverSecret spell API | the spell API's flags read secret somewhere (an instance) |
| D4 | `ADDON_RESTRICTION_STATE_CHANGED` instead of combat flags for walk failure | the walk's own plain/secret result gates it | probe e6 shows a restriction outside combat that the walk mis-reads |
| D5 | `SETTLE` from CDM-O, latency from LAT, `WAKE_HOOKS` from e4 | in-game only | the owner's probe session |
| D6 | Per-class coverage fixtures (CDM-C) for classes other than Warrior and Druid | in-game only | each class's `/fprobe cdm sets` |
