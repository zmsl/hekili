# Providers: the damage meter and the Cooldown Manager as injected, switchable sources (design, 2026-10-23)

Status: DESIGNED (plan: `docs/superpowers/plans/2026-10-23-providers.md`). Builds on the unit-registry spec
(`docs/superpowers/specs/2026-10-22-unit-registry-and-tickets-design.md`, "the base spec", decisions 1-45) and the
attribution-recovery spec (`docs/superpowers/specs/2026-10-23-attribution-recovery-design.md`, "the recovery spec",
decisions 46-56; the parry-haste spec holds 57-64). Decisions here are numbered from 65.
Paths are under `src/Hekili/` unless they start with `tests/`, `tools/` or `docs/`. Line numbers are as of
`forever-attribution-2` cbdfdc41 (recovery Task 1 merged; Tasks 2-5 in flight).

Research this rests on (both final, 2026-10-23):

- "DM": `docs/research/2026-10-23-damagemeter-api.md` (branch `forever-damagemeter-research`): a plain
  `DAMAGE_METER_COMBAT_SESSION_UPDATED (type, sessionID)` per server-resolved damage event of **the group** (us and party
  members; strangers never); a type-0 group 0-11 ms after each `PLAYER_SWING` that hits and none for an avoid (99 of 99
  swings); instants and DoT ticks group 1-14 ms after their row; type 7 about 0.4 s before a melee hit on a group member;
  getters secret in combat and exact out of combat; behaves the same with the meter option off (DM §0, §3, §7).
- "CV": `docs/research/2026-10-23-cooldown-manager-api.md` (branch `forever-cooldownviewer-research`): the viewer's item
  frames carry a plain presence bit in combat (`auraInstanceID` secret while up, nil while down), `HookScript`
  OnShow/OnHide fire 3-4 ms after the aura edge, pre-pull auras read fully plain, direct aura reads are refused, taint
  unproven but no harm seen (CV §0, §2, §5, §6).

## 0. The owner's requirements

Verbatim (2026-10-23):

1. "I would like to have the damage meter integration as an experimental feature that can be enabled", and the A/B must
   be testable through that switch.
2. "I would not want the code to be integrated together, it would need to be separate containers of the logic
   potentially with a single common interface so that the users of the data contract dont know the difference and that
   it's the engine config that injects the right provider".
3. "I would also like to do the same for the cooldown manager hook".

Owner addition (2026-10-23, relayed): the injected Presence provider may be a ROUTER, "a third small container holding
only a map and delegation": a tracked aura is answered by the viewer leaf ("an absolute fact"), an untracked one answers
UNKNOWN so the engine falls back to the modelled timer; the switch decides whether the router includes the viewer leaf;
the audit is per aura; the tools check is a coverage report, not a failure.

What follows: two contracts (section 1), four leaf providers and one router that share no code (section 2), one
injection point in the engine's build config (section 3), a double-run harness and an in-game audit (section 4).

## 1. The two contracts

A contract is the set of questions the engine asks. Answers are small integers (no strings, no tables), so a call
allocates nothing and costs one function call. Every provider is a table with exactly these fields; a consumer reads the
active one through `I.outcomes` or `I.presence` and never knows which file it came from.

### 1.1 Outcomes

```
I.HIT, I.AVOID, I.UNKNOWN = 1, 2, 0          -- SwingOutcome's answers
I.OURS, I.FOREIGN = 1, 2                      -- RowOwner's answers (I.UNKNOWN shared)

P.name                     -- "default" | "meter" (the Snapshot line's)
P.SWING_DELAY              -- s after a swing before SwingOutcome may be asked (0: never asked)
P.ROW_DELAY                -- s after a row before RowOwner may be asked (0: never asked, rows are not held)
P.Activate(api, t)         -- out of combat only: register its events, reset its state
P.Deactivate(t)            -- out of combat only: its events dormant
P.SwingOutcome(i, now)     -- swing ticket i (T.kind[i] == MELEE), asked once, at the first tick with
                           -- now >= T.at[i] + SWING_DELAY: HIT | AVOID | UNKNOWN
P.RowOwner(t, uid, school, amount, act, now)
                           -- the row at t, asked once at now >= t + ROW_DELAY: OURS | FOREIGN | UNKNOWN
P.EnemyHitAt(t)            -- a hit row on the player at t: the time the server resolved it, or nil
P.Audit()                  -- out of combat only: the audit table (1.3) once read plain for the last fight, else nil
```

- **SwingOutcome** answers "did my swing hit?" one frame after the swing, long before its row (0.1-1.45 s, DM §2). HIT
  means "a hit happened at that swing, ours or (in a party) a partner's"; AVOID means "nothing of the group hit there,
  so our swing did not"; UNKNOWN means "no evidence: do what you do today".
- **RowOwner** answers "could this row be ours?" FOREIGN means "certainly no member of our group dealt it"; OURS means
  "a member of our group dealt it and we are in no group" (which includes our own pet, DM §4 `RedirectSourceToOwner`);
  UNKNOWN otherwise.
- **EnemyHitAt** answers "when did the hit I see now really land?" for the attackers' swing clocks.
- **Audit** answers "what did the server count for the fight?" after combat.

### 1.2 AuraPresence

```
I.UP, I.DOWN = 1, 2                           -- Presence's answers (I.UNKNOWN shared)

Q.name                     -- "default" | "viewer" (the leaf) | "router"
Q.scope                    -- "self" (our own auras only) | "any" (anyone's) | nil (covers nothing)
Q.covered                  -- how many (aura, unit) pairs it can answer; 0: Presence is never asked
Q.Activate(api, t, def, cfg) -- out of combat only: build its map for the tracked set, install what it needs
Q.Deactivate(t)            -- out of combat only: answers UNKNOWN from now on
Q.Presence(j, u)           -- aura index j (def.auras order), unit index u (1 player, 2 target): UP | DOWN | UNKNOWN
Q.onEdge                   -- fn(j, u, up, t), set by whoever injected Q; Q calls it on a change it observed
```

The consumer (`Sources/Auras.lua`) sets `I.presence.onEdge` after each activation; a router sets its leaf's `onEdge` to
its own forwarder. A leaf never knows who listens.

`scope` is provider-defined and reported by the provider: UP from a "self" provider means "our aura is up", from an "any"
provider "someone's is up". Packs that care (a debuff stacking line) read it through `VS.PresenceScope()` (3.4). The
Cooldown Manager provider is "self", measured (2.4).

### 1.3 The audit table

Preallocated once by the Meter provider: `{ valid = false, done = 0, taken = 0, at = 0 }` (our damage done and damage
taken for the last finished session, the time read). The Default provider's `Audit()` returns nil.

## 2. The providers: four files, no shared code

```
Game/State/Sources/Outcomes/Default.lua     Game/State/Sources/Presence/Default.lua
Game/State/Sources/Outcomes/Meter.lua       Game/State/Sources/Presence/CooldownViewer.lua
                                            Game/State/Sources/Presence/Router.lua
```

Each file registers itself by name in `I.OUTCOMES[name]` or `I.PRESENCE[name]` (a table `Belief.lua` creates) and uses
only the engine's own surface (`I.Sources` for events and `Plain`, `I.Units.OnRow`, `I.Tickets` read-only). No leaf
requires, reads or calls another provider; the router knows its leaves only as `I.PRESENCE[name]` tables that satisfy
the contract and holds no logic but its map and the delegation. The two Default files load first in `Hekili.toc`, after
`Sources/Units.lua` (line 34) and before `Sources/Player.lua`; the others after `Sources/Enchants.lua` (line 47), the
router last.

Outcomes has no router: its questions are about our swings and rows, not about a key some source covers and another
does not, so the switch picks the leaf directly ("default" or "meter").

### 2.1 Outcomes/Default.lua

`SWING_DELAY = 0`, `ROW_DELAY = 0`; `SwingOutcome`, `RowOwner` return UNKNOWN; `EnemyHitAt` returns nil; `Audit`
returns nil; `Activate` and `Deactivate` do nothing. With these, every consumer runs exactly today's path (section 3.3):
this provider *is* today's behaviour, and the recovery spec's assumed outcome (recovery decision 51) is its path for a
swing with no row.

### 2.2 Outcomes/Meter.lua

**Events.** `DAMAGE_METER_COMBAT_SESSION_UPDATED`, registered through `S.On` at load and kept dormant (3.2) until
`Activate`. The handler returns after one compare for a discarded event (sessionID 0, the duplicate set DM §1; types other
than 0, 1, 7, 10). Types 0, 1 and 10 of one batch mean one group-damage event and are folded into one "group" when they
fall within 3 ms of the previous one (DM §2, 29244/29245); type 7 is its own "taken" group. A group is one entry in a
preallocated ring: `RING = 64` entries of `gT[k]` (time) and `gKind[k]` (0 damage, 7 taken), an integer head, and a
`gUsed[k]` boolean for EnemyHitAt. About 6-12 events per hit (DM §4) reach the handler; nothing allocates.

**Liveness.** The provider answers only while `live`: `C_DamageMeter.IsDamageMeterAvailable()` read plain at `Activate`
(DM §4: measured plain), and at least one damage group seen since `PLAYER_REGEN_DISABLED`. Before the first group of a
fight every answer is UNKNOWN (a pull that opens with an avoid stays on today's path). A **mute** guards a client that
stops sending groups mid-fight (an instance restriction, DM §8.3): the provider counts the swings it told AVOID and the
white avoid rows (MISS, DODGE, PARRY, school 1) it saw through its own `I.Units.OnRow` listener; when told-AVOID exceeds
seen-avoids by 3, it answers UNKNOWN for the rest of the fight and counts `muted`. Every true avoid of ours makes an avoid
row on the unit we swung at, so a working meter never trips it.

**SwingOutcome, the 15 ms rule.** `SWING_DELAY = 0.015`. Swing ticket i swung at `T.at[i]`: HIT when a damage group lies
in `[T.at[i], T.at[i] + 0.015]`, else AVOID. Measured: 0-11 ms after every hitting swing, none for 15 avoids among 99
swings (DM §3); 15 ms is the measured maximum plus 4 ms. The group trails the swing, so the question is asked one frame
later (3.3), never in the swing's own handler.

The collision bound (party). Groups are the group's: a partner's hit, our DoT tick or our proc within those 15 ms reads
as HIT for a swing of ours that was avoided. With `λ` the rate of other group damage events per second, the chance an
avoided swing reads HIT is `1 - exp(-0.015 λ)`: 0.7 % at λ = 0.5/s (solo, a DoT and procs), 4.4 % at λ = 3/s (two
partners), 11 % at λ = 8/s (a raid's dps on one mob). Multiplied by the avoid share (about 15 %, DM §3), a wrong HIT is
0.1 % / 0.7 % / 1.7 % of swings. A wrong HIT is recovered: it moves the ticket to ASSUMED (3.3), and our own avoid row,
arriving in the swing's window, refunds it (recovery decision 51: `Obs.Swing` c = 6, with the hold of recovery decision
50). The reverse error does not exist: AVOID is certain while live, since our hit always groups.

**RowOwner, "no group behind the row".** `ROW_DELAY = 0.015`. Asked at `now >= t + 0.015` for a row at t:

| Row | FOREIGN when | OURS when | Else |
|---|---|---|---|
| a non-white WOUND (spell, proc, DoT tick) | no damage group in `[t - 0.003, t + 0.015]` (DM §3: instants 3-14 ms after their row, periodic 1-2 ms) | a group there and not in a group (`IsInGroup()` plain, read at `PLAYER_REGEN_DISABLED`) | UNKNOWN |
| a white WOUND | no damage group in `[t - 2.0, t + 0.015]` (our swing's group precedes its row by up to 1.45 s, DM §2; a strike's comes in its frame after it) | as above | UNKNOWN |
| an avoid | never (avoids never group, DM §3) | never | UNKNOWN |

Strangers never group (DM §3, captures A-C), so in solo FOREIGN is exact; in a party a group in the frame means "ours or a
partner's" and the answer is UNKNOWN, leaving the tickets to decide as today.

**EnemyHitAt.** For a WOUND row on the player at t: the latest unused taken group in `[t - 0.6, t - 0.3]` (DM §3: 389-565
ms before a melee row) for a white row, or in `[t - 0.005, t + 0.005]` for a spell row; marked used; nil when we are in a
group (type 7 fires for partners' damage taken too, DM §3 capture D) or not live.

**Audit.** At `PLAYER_REGEN_ENABLED` the provider sets `pending`; its poll (order 12, after the overlay's 11) retries
while out of combat for up to 3 s (ForeverMeter's observed settling, DM §5): `pcall(C_DamageMeter.GetCombatSessionFromType,
1, 0)` (Current, DamageDone) and `(1, 7)` (DamageTaken); each returned value is tested with `issecretvalue` before any
use; in `combatSources` the source whose `isLocalPlayer` (NeverSecret, DM §4) is true gives `totalAmount`; any secret
field drops the whole read for that poll. The getters allocate their session tables, so they run at most once per poll
for 3 s after a fight, never in combat; nothing read is passed back to an API. The result fills the preallocated audit
table; `Audit()` returns it while `valid`.

### 2.3 Presence/Default.lua

`scope = nil`, `covered = 0`; `Presence` returns UNKNOWN; `Activate`, `Deactivate` do nothing; it never calls
`onEdge`.

### 2.4 Presence/CooldownViewer.lua

**Measured scope: "self".** Probe CDM-S (party capture, 2026-10-23): a partner's Sunder Armor on our target made no
edge and no aura field on the Sunder item; a simultaneous show/hide of the Sunder and Demoralizing Shout items with nil
aura ids (92269/100018) was a viewer layout refresh, not an aura edge; our own Sunder at 128168 showed 5 ms later with a
secret aura id and hid at the target's death. The viewer tracks player-cast auras only (its filter is
`HARMFUL|PLAYER`, CV §3). Once we have contributed a stack, the shared debuff reads UP, so a "keep it up" line works when
we take part; partners' debuffs stay a gap. With two stacks of ours (casts 2980, 4476) the item's stack text read
`secret` in combat (CDV_FRAME 5609): the viewer draws the count but addons cannot read it. Presence only, stacks never.

**Map, out of combat only.** At `Activate` (the router calls it at its own activation and at each rebuild, 2.5):
`C_CooldownViewer.IsCooldownViewerAvailable()` (plain);
`GetCooldownViewerCategorySet(c)` for the categories 0-8 and `GetCooldownViewerCooldownInfo(id)` per id (both allocate,
CV §3); an id maps to aura index j when its `spellID`, `overrideSpellID` or one of its `linkedSpellIDs` is one of
`def.auraIds[j]` (any rank). The map is two preallocated arrays sized at build: `cdvToJ[cooldownID]` (a hash filled at
the map, never in combat) and the per-pair state `st[(u - 1) * I.AURA_UNIT + j]` (0 unknown, 1 up, 2 down). `covered`
counts the mapped aura indices times the units seen in `auraDataUnit`. No pack data: the spell IDs link the pack's
auras to the viewer's items.

**Hooks.** The four viewers (`EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`,
`BuffBarCooldownViewer`, read from `api`) are walked with `GetChildren()` out of combat; every child with a
`layoutIndex` gets `HookScript("OnShow", h)` and `HookScript("OnHide", h)` once (a per-frame flag in a weak-keyed table;
one shared function `h`, no closure per frame). Items are pooled and reassigned (CV §5), so `h(self)` reads the item's
`cooldownID` at fire time.

**The edge rule: presence is read, not inferred from the script.** `h(self)`: `rawget(self, "cooldownID")` through
`Plain`, `cdvToJ` lookup; `id = rawget(self, "auraInstanceID")`; `up = api.issecretvalue(id) or id ~= nil` (no compare on
a secret; never `a and b or c`); the unit from `Plain(rawget(self, "auraDataUnit"))` ("player" 1, "target" 2, else
ignored). If `up` differs from `st[k]`, store it and call `onEdge(j, u, up, now)`. A layout refresh's hide/show
with nil ids changes nothing for an aura already down (CDM-S 92269/100018); an OnShow of a cooldown item (no aura fields)
is ignored. Measured lags: 3-5 ms after the cast or kill (CV §2; CDM-S 128168); the Sunder item hid 4 ms after the killing
swing, in the same millisecond Victorious showed.

`Presence(j, u)` returns `st` for a mapped pair (UP or DOWN), UNKNOWN otherwise. The provider's own `PLAYER_TARGET_CHANGED`
handler re-reads every mapped target item by rawget (the target's items may change without a show edge when "hide when
inactive" is off, CV §7) and reports changes the same way. Presence never reads `shown`, so the "hide when inactive"
setting does not matter.

**Taint rule.** Read, never call: item fields by `rawget`, frame getters only `GetChildren` (out of combat); never a
viewer method, never a write to a viewer table or frame (CV §5). Hooks only by `HookScript`. Hooks cannot be removed:
`Deactivate` sets `active = false` and `h` returns after that one test. If the next probe fight's taint log (6) shows any
viewer breakage, the provider stays off by default and the hooks are replaced by the per-poll rawget read.

**Coverage report** (`make cdv-coverage`, dev-only like `spell-data-check`): `tools/check_cooldown_viewer.lua` loads each
class pack the way `tools/check_spell_data.lua:6-12` does and compares every pack aura's IDs with the class's viewer
fixture, `tools/data/cooldownviewer/<CLASS>.lua` (the cooldown infos from ForeverProbe's `/vslog cdv ids`, transcribed).
It prints, per class, the auras the viewer tracks (answered by the fact) and the ones it does not (left to the modelled
timer), and always exits 0: coverage is information, not a failure. A class with no fixture prints "no fixture"; an
unreadable fixture prints "unreadable". The Warrior fixture comes from the 2026-10-23 capture; the others are probe
CDM-C (6).

### 2.5 Presence/Router.lua

The provider the game layer injects (`def.providers.presence = "router"`). Its whole state: `leaf` (the viewer leaf's
table or nil), `tracked[j]` (a boolean per aura index, preallocated at build), and the per-aura audit counters (4.3).

- **Activate(api, t, def, cfg)**, out of combat only: `leaf = cfg.viewer and I.PRESENCE.viewer or nil`. With a leaf it
  reads `IsCooldownViewerAvailable()`, the category sets 0-8 and each id's cooldown info (plain out of combat, CV §2) and
  marks `tracked[j]` for every aura whose IDs match one (the same ID rule as 2.4, read by the router itself: no code
  shared with the leaf), activates the leaf and sets `leaf.onEdge` to its forwarder. Without a leaf every `tracked[j]` is
  false and `covered` is 0.
- **Presence(j, u)**: `tracked[j]` and the leaf's answer, else UNKNOWN. An untracked aura is therefore answered by the
  modelled timer (the belief's own expiry), which is exactly the Default provider's path.
- **The forwarder** passes a leaf edge on only for a tracked aura and counts it (4.3).
- **Rebuild.** On `COOLDOWN_VIEWER_DATA_LOADED` (and `COOLDOWN_VIEWER_TABLE_HOTFIXED`, CV §3) out of combat the router
  re-reads the sets, re-marks `tracked` and re-activates the leaf; in combat it only sets `pending` and rebuilds at
  `PLAYER_REGEN_ENABLED`. The tracked set never changes mid-fight (no-jitter).
- **Switch off** (`cfg.viewer` false): no leaf, every answer UNKNOWN, `covered` 0, no hook installed, no getter read:
  identical to the Default provider to the digit (the first gate covers both).

## 3. Injection

### 3.1 The engine config carries the providers

`def.providers = { outcomes = "default" | "meter", presence = "default" | "router", viewer = false | true }` joins the
build config `def`
(`Game/State/Adapter.lua:98-108`). `I.Build` (`Game/State/Belief.lua:99-111`) resolves the names before the build hooks:
an unknown or missing name is "default"; the old provider's `Deactivate` and the new one's `Activate` run when the name
or `viewer` changed (with `I.api` set; at `VS.Start` otherwise). `viewer` is the router's `cfg`. `I.outcomes`, `I.presence` then name the active tables. The harness
builds `def` itself (`tests/Game/harness/drive.lua:55`, `detect.lua:149-152`) and sets `def.providers` per run.

`VS.SetProviders(outcomes, presence, viewer)` swaps without a rebuild: out of combat at once; in combat it stores the names and
applies them at `PLAYER_REGEN_ENABLED`. A provider never changes mid-fight (the no-jitter rule, owner 2026-10-20).

### 3.2 Dormant events

A provider's client events must not reach the client registration while it is inactive, or the Default run would
deliver events today's does not (`events delivered` in Snapshot). `S.Dormant(event, on)` (new, `Sources.lua`) keeps a set
`S.DORMANT`; the facade's `sync` (`Game/Events/EventFacade.lua:58-96`) treats a dormant event's sources as absent and is
exposed as `E.Sync(event)`. The Meter marks its event dormant at load and flips it in `Activate`/`Deactivate`.
Events other files also handle (`PLAYER_REGEN_*`, `PLAYER_TARGET_CHANGED`) stay registered; a provider's handler for
them returns at once while inactive.

### 3.3 The consumers and the guesses they replace

Every consumer calls the contract only. With the Default providers each branch below is not taken, so the code path is
byte-for-byte today's.

| Consumer | Today's guess (where) | Contract call (new) | With an answer |
|---|---|---|---|
| Tickets, swing outcome | none until the row: the swing's LR at the row (`Rows.lua:269-285`, `Melee.lua:152-184`), the veto from usability answers (`Rows.lua:280-283`, `Resources.lua:825-840`), and past the pending window the recovery spec's assumption (`T.Expire`, recovery plan Task 3) | `T.Decide(now)` in Rows' tick (`Rows.lua:389-392`) before `T.Expire`: each OPEN MELEE ticket with `T.told[i] == 0` and `now >= T.at[i] + P.SWING_DELAY` gets `P.SwingOutcome(i, now)` once | HIT: `T.Assume(i, now)` at once (the recovery spec's ASSUMED shadow and `T.onAssume`, `Obs.Swing` c = 5: `est` and `hi`, never `lo`), reconciled by its row (c = 7 confirmed, c = 6 refunded). AVOID: `T.told[i] = 2`: `M.score` skips the ticket for a wound (`Melee.lua:155-160`), `M.Overdue` likewise, `T.Expire` never assumes it, `T.SwingPending` returns 0 for it (`Tickets.lua:320-331`, so `VS.SwingPending`, `Resources.lua:1269-1285`, stops forecasting its rage) |
| Rows, row owner | every row goes through the passes, the LR and pass (d), and is foreign only when none takes it (`Rows.lua:222-313`, `foreign` `:201-214`) | rows are held `P.ROW_DELAY` in a preallocated ring and routed in order at the tick; `P.RowOwner(...)` is asked at release | FOREIGN: straight to `foreign()` (the crowd gate `T.Foreign`, `Tickets.lua:90-95`, and the background `M.background`, `Melee.lua:188-209`, as today for a foreign row); no ticket is offered it. OURS and UNKNOWN: today's routing. OURS is not trusted for payment (our pet's hits are OURS, base K14p); it only counts `ownUnclaimed` when no ticket took the row |
| Tickets, expiry | `T.Expire(now)` (`Tickets.lua:601-611`) | `T.Expire(now - P.ROW_DELAY)` | a ticket is not closed while a row it may own is still held |
| Attackers | the hit's time is its row's (`Attackers.lua:196`, the clock `learn(k, t, ...)` at `:262`) | `P.EnemyHitAt(t)` once per WOUND row on the player | the clock's anchor and gap use the resolved time; nil: the row's time |
| Auras overlay | the walk stops at the first secret in combat (`Sources/Auras.lua:62-136`); the overlay glow covers a few procs (poll 11, `:176-197`); else the modelled expiry stands | `Q.onEdge` (edges) and `Q.Presence(j, u)` in poll 11 for every pair when `Q.covered > 0` | the overlay's own rule: UP while believed down and that unit's walk is not plain stages `Obs.Read` -1 (up, no expiry); DOWN while believed up and the walk is not plain (or the aura has no expiry) stages `Obs.Read` 0; an edge also calls `S.Urgent("VS_PRESENCE")`. A plain walk always wins (it has durations); the target's walk gains the `playerPlain` flag's twin (`targetPlain`) |
| Snapshot | none | `P.Audit()` and the counters (4.3) | the audit line |

The swing ticket gains `T.told[i]` (0 unknown, 1 hit, 2 avoid; reset in `fill`). `T.Assume(i, now)` is the recovery
plan Task 3's inline transition in `T.Expire`, extracted unchanged so both callers share it.

**The first gate.** With `def.providers` absent or "default", every detection floor (`tests/Game/harness/detect_floors.lua`),
the solo and group rage gates (`tests/Game/harness/solo_spec.lua:21-25`, `group_spec.lua`), the flicker floors, every
`make gate` loop line, `make bench-ta`, the memory ceiling and the allocation specs are identical to the digit, and so is
the Snapshot output apart from the new lines. Task 1 of the plan proves it by running the full gate before and after.

### 3.4 The options

Two experimental toggles, off by default, profile-wide (the client's data sources are not per spec):
`profile.performance.damageMeter` and `profile.performance.cooldownViewer` (defaults in `Options/Options.lua:297-301`'s
`performance` table, reachable from the engine as `Engine.settings.performance` by reference, `Engine/Settings.lua:9-25`).
They sit under the Performance group's existing "Experimental" header (`Options/Options.lua:4085-4100`, beside
`steadyIcons`), each with its own `get`/`set` on `Hekili.DB.profile.performance` (the `frameBudget` pattern,
`:4004-4005`); the descriptions say what each needs (the Cooldown Manager enabled for the viewer) and that a change applies
at once out of combat, else when the fight ends.

The game layer injects `outcomes = damageMeter and "meter" or "default"` and always `presence = "router"` with
`viewer = cooldownViewer` (the router with no leaf is the Default path). It reads them in two places only: `buildDef()`
sets `def.providers` from them
(`Adapter.lua:211`, before `I.Build` in `VS.SpecChanged`, `:344-347`, called from `Engine/Schema/Spec.lua:2404`), and
`Hekili:ProvidersChanged()` (new, in `Adapter.lua`), which each setter calls, passes them to `VS.SetProviders`. The engine
never reads the profile (DEVELOPMENT.md §4 layering).

`VS.PresenceScope(unit, key)` returns the active presence provider's `scope` when it covers that aura on that unit, else
nil: the read a pack's stacking logic may use. It joins the documented API.

## 4. The A/B

### 4.1 Headless: every gate twice

An arm is chosen by the environment: `HEKILI_AB` unset or `default` (outcomes "default", presence "router" with no
leaf), `meter` (outcomes "meter"), `viewer` (presence "router" with the viewer leaf). `tests/Game/harness/ab.lua` (new)
gives `AB.arm`, `AB.providers()` (for `def.providers` and for
the loops' profile toggles) and `AB.check(ok, label, line)`: in the default arm `assert(ok, label .. ": " .. line)`; in a
provider arm it appends `label TAB ok TAB line` to `.ab/<arm>.tsv` and never fails, so one run records every cell.
`detect.check` (`detect.lua:296-312`), `pack_gate.flicker` and `pack_gate.gate` (`tests/Forever/helpers/pack_gate.lua:71-100`),
`solo_spec.lua:21-25` and `group_spec.lua`'s bars route their floor assertions through it; health assertions (errors,
secrets, allocation) stay plain asserts in every arm. `make gate-ab` runs `make gate` three times, `HEKILI_AB` default,
meter and viewer, on the same seeds; both provider files are kept.

### 4.2 The observer learns the measured shapes

All new output is added events only, drawn from a new generator (`W.mrng`, seed + 32452843, beside `W.crng` and `W.grng`,
`tests/Game/harness/world.lua:47-50`), so a stream with the shapes on is today's stream plus new lines, and the default
arm (whose provider leaves those events dormant) sees exactly today's.

| Knob (observer `DEFAULTS`) | Shape | Measured |
|---|---|---|
| `meter = false` | a `DAMAGE_METER_COMBAT_SESSION_UPDATED` group (types 0, 1, 10 for the session, then the same for session 0) 0-11 ms after each `swing` truth event whose `act` is WOUND and whose source is in our group; none for an avoid | DM §3, 99 swings |
| | a group 3-14 ms after each `spell`, `proc`, `strike` WOUND row of a group member, 1-2 ms after each `tick` | DM §3 |
| | type 7 at each WOUND on a group member (us, party), at the hit's truth time | DM §3 (no harness row lag on us: the 0.4 s lead needs `takenLag`) |
| `takenLag = 0` | the hit row on us moves `U(0.33, 0.57)` s after its truth time (opt-in; moves rows, so it is never on in a floor run) | DM §3 |
| `group` per band | `detect.BANDS` gains `group`: party true (partners tick), busy false (strangers never tick), raid bands true | DM §3 captures B, D |
| `viewer = false` | for each `aura` truth event of ours on the player or our target, a `@viewer` event 3-5 ms later (unit, spell ID, up) that the drive turns into a fake item frame's Show/Hide with `auraInstanceID` set to the client's secret or nil; partners' auras make none (CDM-S) | CV §2, CDM-S |

The drive gains the fake viewer: four frames whose children carry `layoutIndex`, `cooldownID`, `auraInstanceID`,
`auraDataUnit`, built from a fixture category set (the fake spec's aura IDs), and `C_CooldownViewer`/`C_DamageMeter`
fakes on `fake_api` (getters secret in combat; out of combat the true totals from the world's rows).

### 4.3 In game: one audit line per fight

The Snapshot gains (registered by Rows, which owns the counters; reset at `PLAYER_REGEN_DISABLED`, the last finished
fight's kept until the next pull):

```
providers outcomes=%s presence=%s swings tick=%d/%d row=%d unknown=%d muted=%d ownUnclaimed=%d foreignByMeter=%d
paid=%d meter=%s pins=%d pinErr=%.1f edges up=%d down=%d
```

- `outcomes`, `presence`: the active names (the switch state).
- `tick=HIT/AVOID`: swings decided by the provider; `row`: swings decided by a row (paid, credited or avoided with
  `told` 0); `unknown`: asked and unanswered; `muted`: 1 if the mute tripped.
- `foreignByMeter`: rows routed foreign by RowOwner.
- `paid`: the sum of amounts our tickets were paid this fight (Rows, at each payment and credit); `meter`: the audit's
  `done` (or `-` until read; in a party the meter counts our pet too, DM §4).
- `pins`, `pinErr`: usability flips at an unchanged cost (`Resources.lua:1055`, the known-cost crossing) and the mean
  absolute difference between the estimate before the flip and the cost: the rage error the switch should move.
- `edges`: presence edges the router passed on.

Per aura, one line for each aura the router saw this fight (the owner's "which path answered, and how often the fact
disagreed with the model's guess"):

```
presence <key> unit=%s path=viewer|model facts=%d disagree=%d
```

`path` is `viewer` for a tracked aura, `model` for an untracked one (the modelled timer answered alone). `facts` counts
the viewer answers the consumer acted on or confirmed (edges and poll reads that differed from nothing or from the
belief); `disagree` counts the facts that contradicted the belief's own state at that moment (believed up, viewer down,
or the reverse): the number that says how wrong the modelled timers were. The consumer counts it, since only it holds
the belief; the router only names the path.

The owner toggles a switch between pulls and compares lines. `/vslog` copies them through VSCopy (one line < 255 chars;
the line is split in two if needed).

## 5. What a player gets, and what it cannot do

| Provider | Gets | Cannot |
|---|---|---|
| Meter | rage for a hit at the swing instead of at the row or the assumption (a rage-gated line lights 0.1-1.4 s sooner); an avoided swing stops forecasting rage one frame after it; strangers' rows never taken as ours (solo crowd precision); tighter attacker clocks solo; a recall audit after each fight | amounts, crits, blocks, glances or the spell (groups carry no payload, DM §4); which hand when both swing in one frame (DM §8.5); ours vs a partner's in a party (the collision bound); anything when the client stops sending groups (the mute) |
| CooldownViewer | our debuffs on the target and our buffs up or down in combat, 3-5 ms after the change (a DoT refresh line, a proc window like Victorious) | durations, stacks or charges of anything applied in combat (stack text secret, CDM-S 5609); partners' debuffs (scope self, CDM-S); anything not in the class's viewer sets; anything with the Cooldown Manager disabled (`IsCooldownViewerAvailable` false: the provider covers nothing and answers UNKNOWN) |

## 6. Risks and probes

| # | Risk | Probe | Until measured |
|---|---|---|---|
| DM-P | party collision rate above the bound | a party capture of 100+ swings with `/vslog meter` (DM §8's sequence): wrong HITs = avoid rows whose swing had a group | the harness party band's number (4.1) |
| CDM-T | the hooks taint the viewer | the next probe fight with `/console taintLog 1`, then `Logs/taint.log` for Hekili or the viewer; the viewer still refreshing in combat | the viewer switch's description says "experimental"; off by default |
| DM-PET | our own pet's groups (`RedirectSourceToOwner`) | a pet class fight | OURS is never used to pay (3.3) |
| DM-FL | projectile groups at the landing or at the cast | a caster at range (DM §8.1) | spell rows use the frame rule only |
| DM-I, CDM-I | instances and encounters make events or fields secret or silent | `/vslog meter` and `/vslog cdv` in a dungeon (DM §8.3, CV §7) | the mute (meter); `IsCooldownViewerAvailable` and nil ids (viewer: DOWN is reported only on a read, never assumed) |
| CDM-C | coverage per class | `/vslog cdv ids` per class into `tools/data/cooldownviewer/` | `make cdv-coverage` lists "no fixture" |
| CDM-S | partners' shared debuffs | DONE 2026-10-23: not visible; scope self (2.4) | |

## 7. Relation to the recovery plan

Recovery Tasks 2-5 continue unchanged. Task 3's assumption is the Default provider's path and stays: a swing with no
answer (Default, not live, muted, UNKNOWN) is assumed at its lag tolerance exactly as recovery decision 51 says. The
Meter provider answers 15 ms after the swing, before any assumption is needed: HIT enters the same ASSUMED shadow early
through `T.Assume`, so confirmation, refund and the hold are the recovery spec's, not new code; AVOID removes the ticket
from the assumption and from the wound scoring. The plan's Task 1 needs recovery Task 3 merged (`T.ASSUMED`,
`T.onAssume`, `Obs.Swing` c = 5-7); its other parts do not.

## Decisions made in this spec

| # | Decision | Reason |
|---|---|---|
| 65 | Two contracts, Outcomes (`SwingOutcome`, `RowOwner`, `EnemyHitAt`, `Audit`) and AuraPresence (`Presence`, `onEdge`, `scope`, `covered`), defined by the engine's questions; answers are integers; a call allocates nothing | the owner's "single common interface"; the consumers cannot tell providers apart |
| 66 | Four provider files (`Sources/Outcomes/{Default,Meter}.lua`, `Sources/Presence/{Default,CooldownViewer}.lua`), each self-registering by name, sharing no code and never calling each other | "separate containers of the logic" |
| 67 | The build config `def.providers` names them; `I.Build` resolves (unknown = default) and activates; `VS.SetProviders` swaps out of combat, in combat at `PLAYER_REGEN_ENABLED`; never mid-fight | "the engine config injects the right provider"; the no-jitter rule |
| 68 | The Default providers answer UNKNOWN (delays 0, covered 0) and every consumer's UNKNOWN branch is today's code: every gate, floor, loop line and Snapshot line is identical to the digit (the first gate) | the switch must be a true A/B; today's behaviour is one of the arms |
| 69 | A provider's client events stay dormant in the facade's registration while it is inactive (`S.Dormant`, `E.Sync`) | the Default arm must not even receive the meter's events |
| 70 | SwingOutcome is asked once per swing ticket, one frame after `SWING_DELAY`, from Rows' tick before `T.Expire`; HIT enters the recovery ASSUMED shadow at once (`T.Assume`, c = 5: `est`/`hi`, never `lo`); AVOID sets `T.told` = 2: no wound credit, no assumption, no pending rage | reuse the recovery machinery for confirmation and refund; `lo` never rests on a provider |
| 71 | Meter's swing rule: HIT iff a damage group in `[at, at + 15 ms]`; answers only while live (available, a group seen this fight) and not muted (told-AVOID > seen avoid rows + 3) | 99 of 99 swings (DM §3); a silent client must not turn every swing into an avoid |
| 72 | In a party HIT may be a partner's hit: bound `1 - exp(-0.015 λ)` per avoided swing; recovered by the row's refund with the hold | the measured group semantics (DM §3 capture D) |
| 73 | RowOwner is asked `ROW_DELAY` after the row; Rows holds rows that long in a preallocated ring and routes them in order; `T.Expire` runs at `now - ROW_DELAY`; FOREIGN goes straight to `foreign()` | a spell's group comes 1-14 ms after its row (DM §3); without the hold the answer would come too late to route |
| 74 | Meter's FOREIGN: no damage group in `[t - 3 ms, t + 15 ms]` (non-white), in `[t - 2 s, t + 15 ms]` (white); avoids UNKNOWN; OURS only outside a group and never used to pay (it includes our pet) | strangers never group; our pet folds into us (DM §4) |
| 75 | EnemyHitAt: solo only, a white row's taken group in `[t - 0.6, t - 0.3]`, a spell row's in `±5 ms`; Attackers' clock uses it | type 7 is the group's; 389-565 ms lead for melee (DM §3) |
| 76 | Audit: read out of combat only, at combat end, retried by poll for 3 s; each field `issecretvalue`-tested, the whole read dropped on any secret; into a preallocated table; Snapshot only (no belief use yet) | the getters allocate and are secret in combat (DM §3-4); band seeding is a later decision |
| 77 | Presence `scope` is provider-defined and reported; CooldownViewer is "self", measured (CDM-S); `VS.PresenceScope` is the pack-facing read | the owner asked whether partners' Sunder shows: it does not |
| 78 | The viewer map is built out of combat only, matching each cooldown info's spell, override and linked IDs against the tracked auras' IDs; no pack data | the IDs already link them; a pack override waits for a gap the IDs miss |
| 79 | The viewer hook reads presence (`issecretvalue(id) or id ~= nil`) at fire time and reports only a change; rawget only; `HookScript` once per item frame with one shared function; `Deactivate` makes it return at once | layout refreshes show/hide items with nil ids (CDM-S); the taint rule (CV §5); hooks cannot be removed |
| 80 | Presence is consumed with the overlay's rule (a plain walk wins; UP and DOWN only stage while the unit's walk is not plain), per poll and per edge with an urgent cycle | one rule for every presence source; durations come only from plain walks |
| 81 | `make cdv-coverage` (dev-only) reports pack auras against per-class viewer fixtures transcribed from `/vslog cdv ids` and always exits 0 | the owner: a coverage report, not a failure; the client's sets are not in DB2 |
| 82 | Two experimental profile toggles (`performance.damageMeter`, `performance.cooldownViewer`), off by default, under the Experimental header; read by the game layer at build and through `Hekili:ProvidersChanged()`; never by the engine | the owner's "experimental feature that can be enabled", testable by its switch |
| 83 | The harness A/B: `HEKILI_AB` chooses the arm; `AB.check` asserts in the default arm and records in a provider arm; `make gate-ab` runs the gate for each arm on the same seeds | every gate, loop and kind run twice with both results kept |
| 84 | The observer's meter and viewer shapes are opt-in knobs that only add events, drawn from their own generator; a band says whether its others are group members | the default arm's stream must stay today's |
| 85 | A Snapshot audit line per fight: the switch state, swings by tick vs by row, rows paid vs the meter total, the pin error, presence edges | the owner compares in game between pulls |
| 86 | Provider arms are measured, not gated; the default arm's floors never move for a provider change; the owner decides from the recorded numbers whether a provider becomes default | experimental means measured first |
| 87 | Recovery Tasks 2-5 continue; Task 3's assumption is the Default path; the Meter answers before it is needed and reuses its states | one ticket model, two sources of evidence |
| 88 | The game layer injects `Presence/Router.lua`, a third container holding only `tracked[j]` and delegation: a tracked aura is answered by the viewer leaf, an untracked one UNKNOWN (the modelled timer); the switch decides whether the router has the viewer leaf; switch off = Default to the digit | the owner's router: facts where the viewer has them, the model elsewhere, leaves unaware of each other |
| 89 | The router marks `tracked` out of combat only, at activation and on the viewer's set-change events (`COOLDOWN_VIEWER_DATA_LOADED`, `..._TABLE_HOTFIXED`), deferred to combat end when they come in combat | no-jitter: the path of an aura never changes mid-fight |
| 90 | The audit is per aura: path (viewer or model), facts, and facts that disagreed with the belief | the measure of how wrong the modelled timers were |
| 91 | Outcomes has no router: the switch picks the leaf | its questions are not keyed by a coverage set |
