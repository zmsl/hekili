# VirtualState: the full facade (reads and events)

Date: 2026-10-15. Branch: `forever-warrior-profile` at b62beacf (`virtualstate-phase1` merged). This spec amends
the Phase 1 spec (`docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md`, "spec §N") and replaces the
Phase 2 investigation plan and the Phase 3 outline as the plan input for events: what they asked is settled
below, by the user's decision or by facts measured this session.

Cite conventions:
- A bare `File.lua:N` is Hekili at b62beacf. `fc61b6d9:File.lua:N` is the same file before Phase 1.
- `Classic/Warrior.lua:N` is `git show origin/classic:Classic/Warrior.lua` (origin/classic at fce4fcf1).
- "outline §N" is `docs/research/2026-10-14-virtualstate-phase3-event-bus-outline.md`; "Phase 2 §N" is
  `docs/research/2026-10-14-virtualstate-phase2-eventing-investigation.md`.
- "[V] Cn/Mn/Dn" is a row or detection pattern of `~/src/TacoDogForever/docs/research/2026-10-14-virtual-combat-log-events.md`;
  its probe ids (O1-O16, session O; W-PRn, session W) are quoted as it gives them.
- "CP1/CP2/CP4 2026-10-15" are this session's in-game checkpoints. The Overpower facts (Overpower stayed
  recommended past its window; `C_Spell.IsSpellUsable` plain in combat) are CP2/CP4. The other facts reached
  this spec as one list without a per-checkpoint mapping, so they cite the group; the plan cites each one's own
  checkpoint from the session logs.

## 0. Purpose and the decision

The user's decision (2026-10-15, verbatim):

> "Virtual game event API should act as a full facade for hekili core. It subscribes to events from the layer, the
> layer subscribes to the events that still exist and models the ones that no longer exist that hekili core
> requires. Then hekili core is designed the same as it used to be. Additionally, I think there is a use for
> extending the virtual layers to be a full facade with passthrough where custom modeling is unnecessary so that we
> can monitor/trace when needed."

And on the worked example: "Whether overpower is ready has always been something modeled within the warrior class
since it's not something that game state can tell us when modeling the future. I would keep it simple and allow
virtual game state to accurately represent if it is usable NOW, and then let hekili warrior handle the modeled dodge
event like it used to." The rationale: "Why continue on a design that constantly has us either engineer adaptive
logic in core hekili instead of solving it one time in a virtual game event api?"

So VirtualState becomes the only thing between Hekili and the client, in both directions. Hekili core and the
class files read the game and hear its events through it, unchanged in shape from retail and Classic; every
Forever difference is answered once inside the layer.

| Phase 1 section | Before | After |
|---|---|---|
| §1 decision 3, §7 | the facade keeps 51 names; 124 plain passthroughs revert to direct calls | the facade covers all 175 names (and any new one): `virtual`, `passthrough` or `stub` (§1) |
| §4.2 | VirtualState's frame hears shared events independently of Hekili's frames | VirtualState's frame is the only frame registered with the client; Hekili's frames subscribe to it (§2) |
| §4.4 urgent lane | `Hekili:ForceUpdate` only | plus synchronous delivery of the event and of the rows it triggers (§3) |
| §4.6 feeds | the module writes `AddToHistory`, `realQueue`, `swings.*` | retired as synthesized own-cast and swing rows reach `CLEU_HANDLER` (§7) |
| §8 clock | fold in the drain only | unchanged; synthesized rows carry their observation time (§3) |
| §10 | `UNIT_AURA` handler neutered; CLEU skipped at `Events.lua:174` | both reverted to their pre-Forever form (§7) |
| §12 G2 | Hekili's handler runs first; one-cycle staleness accepted | order closed: VirtualState first by construction; staleness unchanged, handler reads stay up to one cycle stale (§3) |
| §14 | no synthesized events, no virtual combat log | in scope (§2) |

## 1. The two facades

Both facades are full: every game function and every game event Hekili core or a class file touches goes through
the layer. Each entry has one status:
- **virtual**: answered by a policy from VirtualState's beliefs (a read), or synthesized from them (an event);
- **passthrough**: the real function or event, unchanged except for the `Plain` gate on event payloads (§2.3); it
  exists so it can be traced (§5) and so a later Forever finding changes one row, not Hekili;
- **stub**: absent on Forever; a fixed, API-shaped answer, or an event that is never registered.

### 1.1 The read facade (`ns.Facade`)

`VirtualState/Facade.lua` keeps its shape (`kept(name, kind, fn, reason)`, `Facade.lua:40-50`; `Status`, `Why`,
`Stubs`, `Inventory`, `Facade.lua:517-528`) and gains a third kind, `passthrough`, built by one load-time helper:
`passthrough(name, reason)` resolves the real function (`resolve`, `Facade.lua:31-38`), stores a wrapper in the
namespace table that mirrors the game, and records the status. An absent passthrough (a nil global) becomes a stub
with a no-op, which is how the seven deprecation shims are handled today in each file
(`local IsPlayerSpell = IsPlayerSpell or function() end`, `Events.lua:10`; spec §7.3); that fallback moves into
the facade.

The policy table, all 175 names (Phase 1's 51 rows are spec §7.2/§7.4 unchanged and listed here by group only):

| Group | Names | Status | Evidence |
|---|---|---|---|
| Phase 1 kept | the 51 of `tools/api_inventory.txt` at b62beacf (resources, health, the 12 stats, haste and speed, totems, auras, cooldowns, casts, combat log, talents, absent spells and items) | virtual (34) / stub (17), spec §7.2-§7.4 | spec §7.2; `CombatLogGetCurrentEventInfo` turns virtual (§2.4) |
| Usability and cooldown flags | `C_Spell.IsSpellUsable` | passthrough | both returns plain in combat (CP1/CP2/CP4 2026-10-15); the "usable NOW" signal of §6 |
| Item cooldowns | `C_Item.GetItemCooldown` | passthrough | plain in combat (CP1/CP2/CP4 2026-10-15) |
| Combat and threat | `InCombatLockdown`, `UnitThreatSituation`, `UnitAffectingCombat` | passthrough | plain in combat (CP1/CP2/CP4 2026-10-15); `InCombatLockdown` lags at `PLAYER_REGEN_DISABLED` (spec §7.7), VirtualState itself uses `InCombat()` |
| Unit facts | `UnitIsDead`, `UnitCanAttack`, `UnitCanAssist`, `UnitIsDeadOrGhost`, `UnitExists`, `UnitGUID`, `UnitIsUnit`, `UnitIsFriend`, `UnitIsPlayer`, `UnitIsPVP`, `UnitIsTrivial`, `UnitIsConnected`, `UnitClass`, `UnitClassBase`, `UnitClassification`, `UnitCreatureType`, `UnitLevel`, `UnitEffectiveLevel`, `UnitName`, `UnitRace`, `UnitSex`, `UnitFactionGroup`, `UnitInParty`, `UnitInRaid`, `UnitInVehicle`, `UnitHasVehicleUI`, `UnitOnTaxi`, `UnitPhaseReason`, `UnitPowerMax`, `UnitPowerType`, `UnitTokenFromGUID` | passthrough | nameplate `UnitIsDead`/`UnitCanAttack` plain in combat (CP1/CP2/CP4 2026-10-15); the rest identity facts, plain [V] §5 O6, O8 |
| Stances | `GetShapeshiftForm`, `GetShapeshiftFormInfo` | passthrough | the 4th return is the stance's spell ID (CP1/CP2/CP4 2026-10-15); `Forever/Warrior.lua:496-499` reads it |
| Spell data and book | `C_Spell.GetSpellInfo`, `GetSpellDescription`, `GetSpellPowerCost`, `GetSpellTexture`, `IsCurrentSpell`, `IsSpellDataCached`, `IsSpellHarmful`, `IsSpellHelpful`, `IsSpellPassive`, `RequestLoadSpellData`; `C_SpellBook.*` (6); `C_SpellActivationOverlay.IsSpellOverlayed` | passthrough | static or plain (spec §4.5 reads `GetSpellPowerCost` out of combat) |
| Talents and spec | `C_Traits.*` (8), `C_ClassTalents.*` (2), `C_SpecializationInfo.*` (3), `GetSpecializationInfoByID` | passthrough | plain and identical in combat [W PR5] (spec §4.5) |
| Items and gear | `C_Item.*` other than `GetItemCooldown` (9), `GetInventoryItemID`, `C_TooltipInfo.*` (3) | passthrough | static |
| Loss of control | `C_LossOfControl.GetActiveLossOfControlData`, `...DataCount` | passthrough | plain in combat [V] C28 (W-PR18, O5) |
| Session and UI | `GetTime`, `GetBuildInfo`, `GetCVar`, `GetFramerate`, `GetNetStats`, `GetFrameCPUUsage`, `GetInstanceInfo`, `GetRealmName`, `GetNumGroupMembers`, `GetNumSubgroupMembers`, `IsInGroup`, `IsInRaid`, `IsInInstance`, `IsInJailersTower`, `IsMounted`, `IsResting`, `GetActionInfo`, `GetBindingKey`, `GetCursorInfo`, `GetClassInfo`, `GetNumClasses`, `GetStablePetInfo`, `SecureCmdOptionParse`, `C_AddOns.*` (3), `C_ClassColor.GetClassColor`, `C_PetBattles.IsInBattle`, `C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier`, `C_PvP.IsWarModeDesired`, `C_Texture.GetAtlasInfo`, `C_VideoOptions.GetCurrentGameWindowSize`, `AuraUtil.UnpackAuraData` | passthrough | not combat state |
| Deprecation shims | `HasOverrideActionBar`, `HasVehicleActionBar`, `IsActionInRange`, `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `SpellIsSelfBuff` | passthrough, stub when the global is nil | only while `loadDeprecationFallbacks` is on (spec §7.3; cleanup Q12) |
| Frames | `CreateFrame` | virtual (§2.1) | the event facade's entry point |

Out of the inventory: Lua and library calls (`LibStub`, `C_Timer`, `debugprofilestop`, `hooksecurefunc`, the
string and table globals) and UI widgets that read no game state (`UIParent`, `GameTooltip`, the dropdown and
fade helpers); `.luacheckrc` keeps them in `read_globals`.

A passthrough wrapper is `function(...) if tracing then return trace(id, real, ...) end return real(...) end`,
built once at load. Off, its cost is one upvalue test and one tail call; no allocation (Lua 5.1 passes `...`
without building a table). On, it is `return finish(id, real(...))`, where `finish(id, ...)` records
`select("#", ...)` and the first four results and returns `...` unchanged, so names with many results
(`GetInstanceInfo`, `UnitCastingInfo`: 9 each) lose none. A passthrough is transparent: it does not gate secrets
(decision 8). The table above marks the names known to be secret in combat (all of them are virtual rows), and the
trace records a secret result as `S` (§5), which is how a misfiled name shows up.

### 1.2 File-top locals and the tools

The Phase 1 revert (spec §7.7) is undone. Every Hekili file that reads a game name takes it from the facade:

```lua
local addon, ns = ...
local Facade = ns.Facade
local C_Item, C_SpecializationInfo, C_Spell, C_UnitAuras = Facade.C_Item, Facade.C_SpecializationInfo, Facade.C_Spell, Facade.C_UnitAuras
local CreateFrame, GetTime, UnitExists, UnitGUID = Facade.CreateFrame, Facade.GetTime, Facade.UnitExists, Facade.UnitGUID
```

Namespace locals now name the facade's namespace tables (today `Events.lua:7` mixes `C_Spell` direct with
`Facade.C_UnitAuras`), so each facade namespace carries every member Hekili uses, kept and passthrough alike.
`State.lua` is at the 200-locals cap (spec §7.7 step 4): its direct reads become inline `Facade.Name(` with no new
local; its 31 existing `Facade.` reads stay. Class files do the same (`Forever/Warrior.lua:16-23` reads
`C_SpellBook`, `C_Spell`, `UnitClassBase`, `GetShapeshiftForm`, `GetShapeshiftFormInfo` directly today).

- `tools/api_inventory.txt` lists all names of the facade (175 plus `CreateFrame`, plus any name a later probe or
  file adds); `VirtualState/spec/facade_spec.lua` asserts `Facade.Inventory()` equals it, and that every entry has
  a status and a reason.
- `tools/check_api_reads.sh` returns to its pre-Phase-1 rule, "no game API from the inventory is read directly"
  (`fc61b6d9:tools/check_api_reads.sh`: W113 on any inventory global, namespaces included, plus the `_G.Name` grep),
  so the dotted-name grep Phase 1 added is dropped: a bare `C_Spell` is itself W113 once `.luacheckrc` stops
  declaring it. With `CreateFrame` in the inventory, every frame a loaded file makes comes from the facade; the
  script adds one grep that fails on `getmetatable(` combined with `RegisterEvent`/`RegisterUnitEvent` (the only
  way left to reach the real method).
- `.luacheckrc` removes the 124 reverted names and `CreateFrame` from `read_globals` (lines 1-3 restate "every game
  read goes through `ns.Facade`"). The layer's own two client frames are the named exemptions in
  `check_api_reads.sh`: the event-facade frame (§2.1) and the boot frame of `Adapter.lua:36-42`, which stays on the
  real `CreateFrame` (it is TOC-loaded, so it would otherwise fail W113).
- `Events.lua:6` aliases `AuraUtil` directly today; it becomes `Facade.AuraUtil` in the same task that restores
  the `UNIT_AURA` body, because that body captures `AuraUtil.ForEachAura` at load (`fc61b6d9:Events.lua:1255`).
- An event inventory, `tools/event_inventory.txt`, lists every event any loaded file registers plus the
  synthesized names; `EventFacade.Inventory()` must equal it (§9).

## 2. The event facade

### 2.1 Who owns the frame

Hekili core keeps its event system as written: `ns.RegisterEvent` (`Events.lua:168-182`), `ns.UnregisterEvent`
(`:186-198`), `ns.RegisterUnitEvent` (`:203-243`), the `handlers[event]` and `unitHandlers[unit].events[event]`
tables (`:57-58`), `GenericOnEvent` (`:78-95`), `UnitSpecificOnEvent` (`:97-117`), `ns.StartEventHandler`
(`:120-153`) and every handler. Class files keep `spec:RegisterEvent`, `spec:RegisterUnitEvent` and
`spec:RegisterCombatLogEvent` (`Classes.lua:1074-1088`).

The diversion is at frame creation, not in those functions. `Facade.CreateFrame(...)` calls the real
`CreateFrame` and shadows four methods on the returned instance: `RegisterEvent`, `RegisterUnitEvent`,
`UnregisterEvent`, `UnregisterAllEvents` (and `IsEventRegistered`, answered from the layer). Hekili's frames are
insecure, so an instance field over a frame method is legal (Phase 2 §6 option (b), from feasibility §C.2.1). Through
the file-top `CreateFrame` local, the frames Hekili makes become subscribers: the general frame
(`Events.lua:56`), the per-unit frames (`:207`, `:227`), the display buttons that register overlay, alpha,
keybinding and flash events (`UI.lua:1904-1922`) and the dev tool's listener (`Options/DevTools.lua:1152-1157`,
which today registers `COMBAT_LOG_EVENT_UNFILTERED` on the client directly, cleanup Q5). None of them is
registered with the client again.

- `frame:RegisterEvent(e)` → `EventFacade.Subscribe(frame, e)`; `frame:RegisterUnitEvent(e, u1, u2)` →
  `Subscribe(frame, e, u1, u2)`; the unregister methods remove the subscription.
- **Unit filters are per subscriber.** Each subscription keeps its own unit list (none, or one or two units,
  preallocated at Subscribe), and delivery checks the event's unit against that list, subscriber by subscriber,
  the way `UnitSpecificOnEvent` (`Events.lua:97-117`) dispatches through `unitHandlers[unit]`. Hekili has one
  frame per unit (`:207`, `:227`), and both the player and the target frame subscribe to
  `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_SPELLCAST_START` and `UNIT_AURA` (`:1008`, `:1028`, `:1261`); a per-event
  unit set would hand the target's event to the player frame too and run the target handlers twice.
- VirtualState's own frame (`Sources.lua:176-189`) is the one frame registered with the client. Its registration
  for an event is the union of VirtualState's sources (`S.On`, `Sources.lua:119-138`) and the subscribers. A union
  of at most two units uses `RegisterUnitEvent(e, u1, u2)` (the client takes two units per frame, as
  `Sources.lua:183` already does); more units, or any general subscriber, use `RegisterEvent(e)` and a per-event
  per-subscriber unit filters decide delivery.
- Subscribe runs at load and on rare runtime registrations (`Events.lua:309`, `:361`, `:386`), never in a
  recurring path. It `pcall`s the real registration: an event the client does not know becomes a stub entry
  (never registered, never delivered, listed by `Snapshot()`).
- Delivery calls the subscriber's current script: `local fn = frame:GetScript("OnEvent")`, then
  `fn(frame, event, ...)`. So `StopEventHandler` (`Events.lua:155-163`, which clears `OnEvent`) still silences
  Hekili, and `GenericOnEvent`/`UnitSpecificOnEvent` dispatch exactly as on retail.
- `FRAME_UPDATE` is not a game event; it stays on Hekili's `OnUpdate` (`Events.lua:127-152`). `ns.FeignEvent`
  (`Events.lua:260-268`) calls `handlers[event]` directly and stays internal to Hekili.

**Lifecycle.** The event-facade file (`VirtualState/EventFacade.lua`, TOC-loaded with the facade, before
`Hekili.lua`) creates the layer's client frame when it loads, with the real `CreateFrame` resolved once from the
client table (`_G` in game; the fake api in specs, which the loader sets before it runs any Hekili file). Hekili's
frames subscribe while their files load (`PLAYER_ENTERING_WORLD` at `Events.lua:336`, `VARIABLES_LOADED` at
`:949`, `SPELLS_CHANGED` at `:2254` and about 40 more), and each subscription is registered with the client as it
is made. Passthrough delivery runs from load, so events before login (`VARIABLES_LOADED`, `PLAYER_LOGIN`) reach
Hekili as before. VirtualState's sources run only once `VS.Start` has set `I.api` (step 1 of §3 is skipped while
`I.api` is nil; today `S:OnEvent` would index nil, `Sources.lua:153, 158`). `VS.Start` (`Sources.lua:176-189`)
then adds the sources' registrations to the same frame instead of creating one; an event both need is registered
once. The boot frame at `Adapter.lua:36-42` stays a plain client frame (§1.2).

**Template frames.** `Facade.CreateFrame` also returns tooltip frames (`Hekili.lua:670` `ns.Tooltip`,
`Options/DevTools.lua:237`). A template's `OnLoad` runs inside the real `CreateFrame`, before the shadow exists,
so any registration it makes is on the client directly; `GameTooltipTemplate` registers none that Hekili's code
handles. The shadow is installed on every frame, and `check_api_reads.sh` cannot see `OnLoad` code, so the plan
lists the templates Hekili passes and confirms each.

With this, the two Forever edits in the registration functions are reverted to their originals:
`events:RegisterEvent( event )` for every event except `FRAME_UPDATE` (today `:174` also skips
`COMBAT_LOG_EVENT_UNFILTERED`) and the matching unregister at `:197`. A subscription to
`COMBAT_LOG_EVENT_UNFILTERED` is a subscription to the layer's synthesized log; the client never sees it.

### 2.2 The event policy table

Every event in `tools/event_inventory.txt` is passthrough unless a row below says otherwise.

| Event | Status | Policy |
|---|---|---|
| any event not listed | passthrough | the real event; payload slots through `Plain` (§2.3) |
| `UNIT_AURA` (other units: the dev tool's general registration, `Options/DevTools.lua:1155`) | passthrough with `info` nil | the client's table has secret fields in combat and the layer has no beliefs for those units; the dev tool's handler does not read it (`Options/DevTools.lua:362-366`) |
| `UNIT_AURA` (player, target) | virtual | the real event triggers VirtualState's aura walk (spec §4.5), then the subscribers receive `(unit, info)` with `info` the unit's preallocated `{ isFullUpdate = true }` (§2.5) |
| `UNIT_SPELLCAST_*` (target) | passthrough | `spellID` and `castGUID` arrive nil (secret, [V] §5 O4); Hekili's target arm reads neither (`Events.lua:1017`, `:1029`) |
| `UNIT_POWER_FREQUENT` (player) | passthrough | payload `(unit, powerToken)` is plain ([V] N11); the handler's `UnitPower` read (`Events.lua:1196`) is the facade's belief (spec §7.4) |
| `UNIT_COMBAT` | passthrough to subscribers (Hekili: player only, `Events.lua:1716`) | the layer also registers it for every unit to build rows (§2.4); plain in combat ([V] N27, O1: 779 firings, 0 secret) |
| `COMBAT_LOG_EVENT_UNFILTERED` | virtual | never registered with the client; rows synthesized (§2.4) and delivered with no payload; `Facade.CombatLogGetCurrentEventInfo()` returns the row being delivered |
| an event the client rejects at registration | stub | never delivered |

### 2.3 Passthrough payloads

The layer's `OnEvent(frame, event, r1..r8)` gates each argument into a local, `local a1 = Plain(api, r1)` ... `a8`
(`Sources.lua:22-27`), and passes the eight locals down the subscriber loop: a secret becomes nil before Hekili
sees it, nothing is shared between deliveries, and a client event that fires while another is being delivered
(some client calls fire events synchronously) is delivered at once in its own call, as on retail. Real events are
never queued; only synthesized rows are (§3, §4). Eight covers every event Hekili registers (the
widest, `UNIT_COMBAT`, has five; `ENCOUNTER_START` and `UNIT_SPELLCAST_SENT` four); the inventory records each
event's arity and §9 asserts it. A table argument cannot be gated by value; the only one Hekili consumes is
`UNIT_AURA`'s `updateInfo`, which is virtual. Today Hekili's handlers receive secrets directly; after this they
never do.

### 2.4 The synthesized combat log

`CLEU_HANDLER` (`Events.lua:1399-1704`) destructures the positional tuple, fans it to the class hooks first
(`ns.callHook`, `:1401`), handles deaths and returns (`:1403-1419`), stamps `time = GetTime()` (`:1421`), and
then runs its branches. Classic class files read the same tuple in their own `spec:RegisterEvent(
"COMBAT_LOG_EVENT_UNFILTERED", ...)` by calling `CombatLogGetCurrentEventInfo()` (`Classic/Warrior.lua:441-456`).
The layer emits rows into one pool and delivers each by calling the subscribers' `OnEvent` with
`"COMBAT_LOG_EVENT_UNFILTERED"` and no arguments, the way the client does; `CLEU_HANDLER`'s registration closure
(`Events.lua:1706`) and every class handler then call the facade's `CombatLogGetCurrentEventInfo`, which returns
the current row's 24 slots by explicit index (no `unpack` of a growing table).

Provenance is [V]'s: observed (a plain signal says it happened), inferred (plain signals plus a rule), modelled
(spell data and a clock). The families, with the Hekili consumer each one feeds:

| Family | Rows | Source | Provenance | Consumer |
|---|---|---|---|---|
| Own casts | `SPELL_CAST_START`, `SPELL_CAST_SUCCESS`, `SPELL_CAST_FAILED`; a channel's `SPELL_AURA_REMOVED` | our `UNIT_SPELLCAST_START/SUCCEEDED/FAILED/INTERRUPTED/CHANNEL_STOP` with the `UNIT_SPELLCAST_SENT` target GUID ([V] C36, C38, C40, D1; O16: 134 successes plain) | observed | `:1505-1601`: `realQueue` `CAST_FINISH`/`CHANNEL_*`/`PROJECTILE_IMPACT`, `AddToHistory` (`:1601`) |
| Our swings | `SWING_DAMAGE` (amount, critical), `SWING_MISSED` (missType `DODGE`/`PARRY`/`MISS`, isOffHand) | `PLAYER_SWING` per hand for time and hand; the target's `UNIT_COMBAT` in the same frame for the outcome ([V] C1, C3, D7; O3: `PLAYER_SWING` also fires on avoided swings; O1: the target's MISS, DODGE, PARRY plain, 374 firings) | observed time; the outcome's attribution to us is inferred (`UNIT_COMBAT` is victim-side) | swing timers `:1622-1635`; class hooks (Overpower, §6) |
| Our ability missed | `SPELL_MISSED` (missType) | our `UNIT_SPELLCAST_SUCCEEDED` plus the target's `UNIT_COMBAT` DODGE/PARRY/MISS in the same frame ([V] C9, M2; O16: a dodged Heroic Strike still fired its success) | inferred | class hooks |
| Avoided on us | `SWING_MISSED`/`SPELL_MISSED` with `destGUID` = ours | the player's `UNIT_COMBAT` DODGE, PARRY, BLOCK, MISS ([V] C4, M1-M4, D13; O1: 165 firings plain); the attacker is not in the event, so the row is emitted only when the source is known: the target, when it is attacking us (plain `UnitThreatSituation`, CP1/CP2/CP4 2026-10-15); with an unknown source no row is emitted | observed type, inferred source | class hooks (Revenge, §6); tank attacker counting `:1619-1620` |
| Deaths | `UNIT_DIED`, `PARTY_KILL` | `UNIT_DIED`, `PARTY_KILL`, `PLAYER_TARGET_DIED` with plain GUIDs ([V] C66-C68, D11; O6: 34/23/23 firings) | observed | `ns.eliminateUnit` (`:1403-1419`); Victory Rush window (§6) |
| Damage we deal | `SWING_DAMAGE`, `SPELL_DAMAGE` on the target and plates | the unit's `UNIT_COMBAT` WOUND attributed to our same-frame swing or cast | inferred | enemy counting `:1693-1701` (`ns.updateTarget`) |
| Damage on us | `SWING_DAMAGE`, `SPELL_DAMAGE` with `destGUID` = ours | the player's `UNIT_COMBAT` WOUND (amount, school) ([V] C2, C4; O1); emitted only with a known source, as above | observed (source inferred, as above) | `ns.storeDamage` (`:1451-1495`) |
| Our debuffs on the target | `SPELL_AURA_APPLIED`/`_REFRESH`/`_REMOVED` | our success plus travel plus the spec's duration ([V] C27, D3); removal at the modelled expiry, or a compensating `SPELL_AURA_REMOVED` when the cast's target `UNIT_COMBAT` says DODGE/PARRY/MISS | inferred / modelled | `ns.trackDebuff`, `active_dot` (`:1652-1687`) |
| Energize | `SPELL_ENERGIZE` | our cast plus the spec's gain ([V] C14, D6) | modelled | none in core ([V] §6; outline §1); emitted only when a class file needs it |

**Payload contract.** Every synthesized event has the client's name and positional payload as the `wow` MCP
event docs for Forever give it (the plan carries a per-event signature table; for `COMBAT_LOG_EVENT_UNFILTERED`
those docs list no event payload, which matches delivery with none, and the row layout is the combat log's).
Slots 1-11 are the base parameters (timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags,
sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags); slots 12 on follow the prefix (SWING none; SPELL
spellId, spellName, spellSchool) and the suffix (warcraft.wiki.gg `COMBAT_LOG_EVENT`, "Base parameters",
"Prefixes", "Suffixes", "Special events"). Hekili names the slots in `CLEU_HANDLER`'s signature (`Events.lua:1399`:
12 `spellID`, 13 `spellName`, 14 `school`, 15 `amount`, 16 `interrupt`, 17-20 `a`-`d`, 21 `offhand`, 22
`multistrike`) and Classic's Warrior hook names 12 `actionType` and 15 `spellMissType`
(`Classic/Warrior.lua:442`). The rows the layer emits:

| Subevent | 12 | 13 | 14 | 15 | 16 | 17-20 | 21 | 22 | Hekili reads |
|---|---|---|---|---|---|---|---|---|---|
| `SWING_DAMAGE` | amount | overkill 0 | school 1 | resisted 0 | blocked 0 | absorbed 0, critical, glancing false, crushing false | isOffHand | false | amount `:1469`; overkill `spellName > 0` `:1696`; `offhand`, `not multistrike` `:1622` |
| `SWING_MISSED` | missType | isOffHand | amountMissed 0 | critical false | — | — | — | — | `offhand = spellName` `:1623`; `actionType` (Classic `:443`) |
| `SPELL_DAMAGE` | spellId | spellName | school | amount | overkill 0 | school, resisted 0, blocked 0, absorbed 0 | critical | glancing false; 23 crushing false, 24 isOffHand false (its last slot) | `interrupt > 0` `:1696` |
| `SPELL_MISSED` | spellId | spellName | school | missType | isOffHand false | amountMissed 0, critical false | — | — | `amount == "IMMUNE"` `:1699`; `spellMissType` (Classic `:443`) |
| `SPELL_AURA_APPLIED`, `_REFRESH`, `_REMOVED` | spellId | spellName | school | auraType `"DEBUFF"`/`"BUFF"` | amount 0 | — | — | — | `spellID` for `class.auras` `:1654` |
| `SPELL_ENERGIZE` | spellId | spellName | school | amount | overEnergize 0 | powerType, maxPower | — | — | class hooks only |
| `SPELL_CAST_START`, `_SUCCESS` | spellId | spellName | school | — | — | — | — | — | `class.abilities[ spellID ]` `:1505-1601` |
| `SPELL_CAST_FAILED` | spellId | spellName | school | failedType `""` | — | — | — | — | `:1541-1545` |
| `UNIT_DIED`, `PARTY_KILL` | recapID 0 (`UNIT_DIED` only) | unconsciousOnDeath false (`UNIT_DIED` only) | — | — | — | — | — | — | `destGUID` `:1403-1419` |

No nil holes: every slot up to a subevent's last slot is a value (`0`, `false`, `""` or the datum), because
`ns.callHook` rebuilds the tuple with `unpack( vars )` after `load_args` (`Classes.lua:2858-2877`), and a nil
inside the tuple makes `#vars`, and so the tuple's length, unreliable. Slots past a subevent's last slot are absent.
Elsewhere: `destFlags` and `sourceFlags` are numbers (`bit.band` at `:1449`), synthesized from plain
`UnitCanAttack`/`UnitIsFriend`; GUIDs are strings (`:len()` at `:1512`, `:1557`; `:match` at `:1409`, `:1438`);
names come from plain `UnitName` or `""`. `cleu_rows_spec` asserts this table.

**No row on us with an unknown source.** The tank branch (`Events.lua:1619-1620`: tank role, `destGUID` ours, a
`SWING` subevent) calls `ns.updateTarget( sourceGUID, time, true )`, and `updateTarget` rejects only nil and our
own GUID (`Targets.lua:659`). A `""` or invented source would become a counted enemy for Protection, and a nil
source would leave a hole in the tuple (above). So the layer drops the row: Revenge then falls back to its usability
read (§6) and `storeDamage` misses that hit, which is what Hekili does on Forever today. `cleu_rows_spec` checks it
(tank role, unknown attacker: no row, target count unchanged).

What cannot be synthesized ([V] §3; outline §1): overkill (so overkill elimination at `:1696` never fires and
deaths come from `UNIT_DIED`/`PARTY_KILL` only), absorbed and over-energize amounts, the source of a hit beyond the
same-frame rule, other units' casts and auras (the target's `spellID` is secret, O4), `SPELL_PERIODIC_MISSED`,
which aura left our target early, and the Timerunning aura branch (`:1429`). Hekili then behaves as on retail
with those rows missing: the 1 s target auditor drops unseen units after `damageExpiration` (Phase 2 §2.1 E2),
and the identity filters fall through.

### 2.5 `UNIT_AURA`

The Phase 1 handler (`Events.lua:1259-1263`) is restored to its original body (`fc61b6d9:Events.lua:1265-1325`).
The layer always delivers its own payload, never the client's: the client's instance IDs are real, the facade's
aura reads answer with invented stable IDs (spec §6.3), and a real payload out of combat would send Hekili's
`GetAuraDataByAuraInstanceID` (`fc61b6d9:Events.lua:1298`, through the facade) looking for IDs the beliefs do not
use. The payload is depth 1 of Phase 2 §5, `{ isFullUpdate = true }`, preallocated per unit. The original full
path wipes the instance table, walks both filters through `Facade.AuraUtil.ForEachAura`, sets
`state[unit].updated = true` and calls `Hekili:ForceUpdate( "UNIT_AURA_FULL", true )`. `StoreInstanceInfo` reads
`isBossAura`, `isStealable`, `isFromPlayerOrPlayerPet`, which the facade's AuraData already carries
(`Facade.lua:238-259`), so the gap Phase 2 §5 noted is closed. Setting `updated` at the real event is early enough:
the flag only gates the scrape in the next cycle's resets (`State.lua:6199-6207`), and the
drain folds the walk's observations before those resets (spec §5.1).

## 3. Ordering and the clock

- **One handler, in order.** The layer's `OnEvent` runs (1) VirtualState's sources for the event (`S:OnEvent`,
  `Sources.lua:152-163`: Plain gate, logging and staging, the §4.6 feeds while they exist, `Hekili:ForceUpdate`
  through `I.urgent`, `Adapter.lua:31-33`), then (2) the event's policy builds the payload, then (3) delivers it to
  the subscribers in subscription order, then (4) emits and delivers the rows this event triggers. Hekili now
  hears every event after VirtualState has seen it. CP1/CP2/CP4 2026-10-15 measured the opposite today (Hekili's
  `UNIT_SPELLCAST_SUCCEEDED` handler about 1 ms before VirtualState's urgent lane); G2 is closed by construction.
- **"After the fold"** means after the sources have logged the observation, not after a belief fold: the fold
  stays inside the drain (spec §8), which runs inside `Hekili.Update`. Hekili's handlers read beliefs through the
  facade, at most one cycle stale (0.2 s in combat), as in Phase 1.
- **Synchronous rows** are emitted in step (4) from the event that completes them: a target `UNIT_COMBAT` in the
  frame of our `PLAYER_SWING` emits the swing row; our `UNIT_SPELLCAST_SUCCEEDED` emits `SPELL_CAST_SUCCESS`. Their
  time is the handler's `GetTime()`, which is what `CLEU_HANDLER` stamps (`:1421`) and what Classic's Warrior hook
  stamps (`Classic/Warrior.lua:445, 448`).
- **Pairing window.** The swing (or our cast) and its outcome arrive as separate client events, in either order,
  and nobody has measured how far apart: [V] C1 calls matching a WOUND to the swing "design work, not yet measured
  jointly", and D8 notes the Overpower flip can lag past one frame. The window is a named constant,
  `PAIR_WINDOW_MS`, default 200 ms (the only pairing window [V] gives, D10a's interrupt pairing "within 0.2 s",
  until measured). Phase B's first checkpoint measures it with a probe line that prints, per target `UNIT_COMBAT`
  in combat, the ms since our last `PLAYER_SWING` and our last `UNIT_SPELLCAST_SUCCEEDED`
  (`debugprofilestop()` stamps), and sets the constant from the largest observed gap plus a frame. The layer holds
  pending swings, casts and outcomes in two preallocated buffers (8 entries each) and emits a row as soon as its
  pair arrives (a synchronous row). A swing still unpaired when its window closes is emitted at the next delivery
  point as `SWING_DAMAGE` with amount 0 (a deferred row, carrying the swing's time), `destGUID` the current
  target's plain GUID at the swing (`""` when there was none); an outcome unpaired when its window closes is
  dropped (someone else's). The row's time is the earlier event's.
- **Deferred rows** (modelled expiries, a debuff applied after travel, a row the drain's polls produce, any row
  queued during a delivery) go into the queue (§4) and are delivered at the next delivery point: the layer's own
  `OnUpdate` (`Sources.lua:169-171`, after `S.Flush`). Never inside `Hekili.Update`'s coroutine, a reset or a pack
  hook (outline §6). Hekili's coroutine yields across frames, so a delivery may land while a cycle is suspended;
  on retail every event does the same. Whether the layer's `OnUpdate` runs before or after Hekili's engine frame
  (`UI.lua:2370-2450`) does not matter: only deferred rows are delivered there, and either way the next cycle
  reads what they wrote (outline §6's question, closed without a measurement).
- **Swing rows are back-dated (phase B).** Every `SWING_DAMAGE`/`SWING_MISSED` row is emitted when its pair
  arrives or its window closes, up to `PAIR_WINDOW_MS` after the swing. Once the swing feed (`Adapter.lua:257-264`)
  is retired, `CLEU_HANDLER`'s swing branch would stamp the delivery time (`time = GetTime()` at `:1421`, written to
  `swings.mh_actual`/`oh_actual` at `:1622-1635`), so the swing clock would run late. The carrier is the row's
  timestamp slot: slot 1 holds the `PLAYER_SWING` observation's `GetTime()` (on the client clock, not the client's
  epoch combat log timestamp; no Hekili reader uses slot 1, `CLEU_HANDLER` ignores it, Phase 2 §4.2). Because
  `CLEU_HANDLER` reads `GetTime()`, not slot 1, the layer makes them agree without a core edit: while it delivers a
  back-dated row, `Facade.GetTime` (the file-top `GetTime` of `Events.lua` and of the class files, §1.2) returns
  slot 1, and after delivery it is the real clock again. The handler's `time > sw.mh_actual` test (`:1627-1632`)
  then keeps a back-dated swing from moving the clock backwards. Class hooks that stamp `GetTime()` (Classic's
  `enemy_dodged`, `Classic/Warrior.lua:445`) get the swing's time as well.
- **The clock of other deferred rows.** For every other row, `GetTime` stays the real clock during delivery, and
  Hekili stamps the delivery time, up to one cycle after the row's own time. That is accepted for the remaining
  rows of phases B and C. The debuff family (phase D) decides whether its rows are back-dated the same way
  (outline §5; decision 5).
- **Re-entrancy.** A synthesized row emitted while a delivery is in progress is queued, never delivered nested,
  and counted (`requeued`); a real client event is delivered as it arrives (§2.3). `ns.callHook` returns at once for an event whose hooks are running
  (`Classes.lua:2869`), so nesting would drop rows silently. A subscription added during a delivery takes effect
  for the next event (the loop runs to the count it read at entry).
- **Drop policy.** A full queue drops the oldest row and counts it (`dropped`); a dropped or overflowed row is
  never re-emitted (outline §7 default).

## 4. Payloads and pools

- One row pool of 64 slots, each a fixed table of the 24 positional slots `CLEU_HANDLER` destructures
  (`Events.lua:1399`), plus the row's time, provenance and family. Interned strings only (subevent names, miss
  types, `""`); GUIDs are the plain strings the client handed the layer. Allocated at `VirtualState.Start`.
- The queue is a ring over the pool's slot indices (one reader, the delivery point: Hekili and class files hear
  rows through the same frame subscription, so per-reader cursors are unnecessary; outline §4).
- One `UNIT_AURA` info table per unit, two in all, and the two pairing buffers of §3 (8 entries each).
  Passthrough payloads are locals (§2.3), never stored.
- Plain by construction: every value placed in a row or a slot has passed `Plain` or is the layer's own constant.
  No row ever holds a secret, so `CombatLogGetCurrentEventInfo` needs no gate.
- Zero allocation in every recurring path: receiving, gating, emitting, queueing, delivering and the facade's
  `CombatLogGetCurrentEventInfo`. Hekili's own dispatch allocates per call (`GenericOnEvent` builds a key string
  per handler, `Events.lua:84`, and an `eventData` table per new key, `:88-91`); that is Hekili's retail cost,
  outside the layer's test, and is measured per delivered row from `Hekili.EData` (§9).

## 5. Tracing

- `VirtualState.SetTrace(on)` and `/hekili vs trace on|off|dump` (a `vs` entry in the command table,
  `Options/ChatCommands.lua:86-95`). Not saved: a `/reload` turns it off.
- On, the facade's read wrappers and the event facade write one record per facade read and per event received,
  delivered, synthesized, queued or dropped into a ring of 1024 preallocated records (parallel arrays allocated at
  `SetTrace(true)`, freed at `off`): sequence, `GetTime()`, `debugprofilestop()`, kind, name (the interned name
  string), status (`virtual`/`passthrough`/`stub`), provenance for a row, and the first four arguments and four
  results, all scalars. A secret value is stored as the constant `"S"` after an `issecretvalue` test (never
  `a and b or c`); a secret returned by a passthrough is also counted per name, which is how a misfiled
  passthrough is found. A table result (the facade's shared AuraData, `Facade.lua:236-262`; a cooldown info table)
  is recorded as its scalar fields copied at call time (`spellId`, `expirationTime`, `applications`; `startTime`,
  `duration`), never as the reference, which would show the value at dump time.
- `VirtualState.TraceDump(n)` returns the last `n` records as text (it allocates; debugging only), and
  `/hekili vs trace dump` prints it to the chat frame (decision 3), as does
  `/run print(Hekili.VirtualState.TraceDump(50))`. `Snapshot()` gains the event facade's counters (`delivered`, `synthesized` per family, `requeued`,
  `dropped`, stub events) and the trace state.
- Off: one branch per read wrapper and per delivery. Records are written by index into the preallocated arrays,
  so tracing on allocates nothing either (§9).

## 6. The class-file contract restored

A class file models reactive windows from events, as Classic did, and reads "now" from the plain client signal
through the facade. It contains nothing Forever-specific about where an event comes from. The worked example is
`Forever/Warrior.lua`:

- **Overpower.** On Forever, Overpower costs a combo point that the target's dodge grants (aura 1282733, 5 s), so
  `C_Spell.IsSpellUsable( overpower )` is the "ready now" signal: both returns are plain in combat (CP2/CP4
  2026-10-15). Its strict first return is the signal. A missing combo point reads as `noMana`, the second
  return, and CP2/CP4 saw the result: with today's `reactive()` (`usable == true or noMana == true`,
  `Forever/Warrior.lua:81-86`) Overpower stayed recommended past its window. Rule: "ready now" for any ability
  with a second power cost reads `usable` alone; `reactive()` stays for the abilities gated only by rage
  (Execute, Revenge, Victory Rush), while the aura itself is
  unseen in combat (the walk raises on the target, and the player's aura payload is secret). The
  file returns to Classic's shape (`Classic/Warrior.lua:400-404, 441-456, 625-631`, and the ability's
  `usable = buff.overpower_ready.up`, `:1198-1199`): a `spec:RegisterEvent( "COMBAT_LOG_EVENT_UNFILTERED", ... )`
  handler records `enemy_dodged = GetTime()` and the target GUID on our `SWING_MISSED`/`SPELL_MISSED` with
  missType `DODGE`, and `last_overpower` on our `SPELL_CAST_SUCCESS` of Overpower; `reset_precast`
  (`Forever/Warrior.lua:491-508`), when `now == query_time`, applies `overpower_ready` for the remaining
  `enemy_dodged + 5 − now` when that dodge is under 5 s old, on the current target and not yet spent, else the
  full 5 s when Overpower's strict `usable` is true. The port keeps Classic's rules as written: the age test is
  `query_time - enemy_dodged < 6` (`Classic/Warrior.lua:626`), not 5. `reactive()`'s comment, "Forever has no combat
  log to time the window", goes. The event
  model is what lets Hekili recommend a swap into Battle Stance for Overpower (the `overpower_enabled` and
  `overpower_threshold` settings, `Forever/Warrior.lua:1373-1388`) before the usability read can say so (the
  client refuses Overpower outside Battle Stance). If the same-frame attribution misfires in a group, the
  usability read in Battle Stance corrects it on the next reset.
- **Revenge.** The same handler records `enemy_revenge_trigger = GetTime()` on a row with `destGUID` ours and
  missType `DODGE`, `PARRY` or `BLOCK` (Classic's `misses`, `Classic/Warrior.lua:406-410, 447-448`);
  `reset_precast` applies `revenge_usable` only when Revenge is usable now (`IsUsableSpell` gates both branches in
  Classic, `Classic/Warrior.lua:633-638`, and the port keeps that gate through `reactive()`): for the remaining
  `trigger + 5 − now` when a trigger is under 5 s old, else 5 s, replacing today's usability-only window (`Forever/Warrior.lua:421-428, 507`).
- **Victory Rush** (Forever's, DB2 402927): `usable` stays the plain usability read (`Forever/Warrior.lua:1252`).
  A `PARTY_KILL` row with our `sourceGUID` is available if the file later models the window ahead; nothing in this
  spec requires it.

The fallback when attribution is impossible (no target `UNIT_COMBAT` in the frame, or a group where the rule
rejects the outcome): the usability flip of the reactive ability is itself the signal ([V] D8: an Overpower
`IsSpellUsable` false → true flip; it lagged a swing in O3, 4 flips after 34 melee no-rage swings). The layer does
not emit a row from the flip; the class file's "usable now" branch, on the strict `usable` return, covers it.

## 7. What this retires in Phase 1 code

| Phase 1 edit or write | After |
|---|---|
| The passthrough revert, 14 files (spec §7.7) | undone: file-top locals from `ns.Facade` (§1.2) |
| `UNIT_AURA` handler neutered (`Events.lua:1259-1263`) | the original body restored (§2.5) |
| `COMBAT_LOG_EVENT_UNFILTERED` skipped at `Events.lua:174` and `:197` | the original lines; the layer never registers it with the client (§2.1) |
| `CombatLogGetCurrentEventInfo` stay stub (`Facade.lua:491`) | virtual: the current row (§2.4) |
| The own-cast feeds `I.feed.CastSucceeded`, `CastStart`, `CastFailed`, `ChannelStart`, `ChannelStop` (`Adapter.lua:203-256`: `AddToHistory`, `QueueEvent`, `RemoveSpellEvent(s)`) | retired in the task that lands the own-cast rows; `CLEU_HANDLER` writes them (`Events.lua:1505-1601`). Both together would record each cast twice |
| The swing feed `I.feed.Swing` (`Adapter.lua:257-268`, `swings.*_actual`) | retired with the swing rows; `CLEU_HANDLER` writes them (`:1622-1635`) |
| The interim Overpower and Revenge windows from usability alone (`Forever/Warrior.lua:78-86, 388-395, 421-428, 507`) | Classic's event model plus the usability read (§6) |
| Drain step 5, `updated` from `AuraGen` (`Adapter.lua:452-456`) | kept: a layer-side write, so a belief that moved without a real `UNIT_AURA` (an own cast, a modelled expiry) still rescans in the same cycle (decision 2) |
| The APL warning scanner (Task 9b, `VirtualState/AplWarnings.lua:65`, its `Hekili:LoadScript` call) | stays: target health and time to die are still secret or defaulted |
| The drain call (`Core.lua:1570-1572`), `SpecChanged` (`Classes.lua:3355-3356`), GCD 61304 → 29515, the spec 1491 loop break, the talent walk in `ns.updateTalents` (`Events.lua:424-435`), the version gates | stay. The facade could absorb three of them later (decision 7) |

## 8. Secret safety, performance and the drain

- Event payloads never carry a secret to Hekili, and neither do virtual reads; read passthroughs are plain by
  probe, transparent and traced (decision 8). Every event slot passes `Plain`; every row holds plain values or layer
  constants; virtual reads keep spec §4.5's rules (`pcall` and `issecretvalue` before any field); the trace tests
  `issecretvalue` before storing. No layer code compares, indexes or does arithmetic on a value before that test,
  and none uses `a and b or c` on a possibly-secret value. The ported secrets spec (spec §11) gains the event
  facade's files.
- Zero allocation in recurring paths (§4); everything is allocated at load, at `Start`, at `SpecChanged`, at a
  subscription or at `SetTrace(true)`.
- The drain stays where it is (`Core.lua:1570-1572`, spec §5.1). The layer's frame does not drive Hekili:
  `Hekili.Engine`'s `OnUpdate` still starts cycles (`UI.lua:2370-2400`) and the urgent lane still only shortens
  the wait (`UI.lua:2459-2470`). CP1/CP2/CP4 2026-10-15 measured the drain at 0.1-0.5 ms, under spec §5.4's 1-2 ms
  estimate (G7 closed). Folding moves nowhere: the event facade adds receive-and-deliver work to event handlers,
  never a fold.

## 9. Testing

Headless (busted, `VirtualState/spec/`, the Phase 1 helpers `fake_api.lua` and `alloc.lua`):
- `event_facade_spec`: a frame from `Facade.CreateFrame` on the fake api registers events and unit events, sets
  an `OnEvent` that captures; the fake game frame fires. Lifecycle: a subscription made before `VS.Start`, an
  event delivered before `Start` (sources skipped, no error), then `Start`: nothing is registered twice and the
  sources run from then on. Units: a player frame and a target frame subscribe to the same unit event, and each
  handler runs exactly once per firing. Re-entrancy: a subscriber that fires a client event from its handler gets
  correct payloads in both deliveries. Asserts: only VirtualState's frame is registered with the
  fake client; the capture sees each event once, after the source handler (an order stamp); a `SECRET` proxy slot
  arrives nil; `UnregisterEvent` stops delivery and drops the real registration when no source needs it; a third
  unit switches to a general registration with filtering; an unknown event becomes a stub; clearing `OnEvent`
  silences delivery; `COMBAT_LOG_EVENT_UNFILTERED` is never registered with the fake client.
- `cleu_rows_spec`: per emitted subevent, the tuple matches §2.4's slot table (types, no nil hole up to the last
  slot, the result of `ns.callHook`'s `unpack` equal to the row); pairing in both event orders within
  `PAIR_WINDOW_MS`; an unpaired outcome dropped and an unpaired swing emitted, each after its window closes; tank
  role with an unknown attacker: no row, target count unchanged; rows emitted during a delivery arrive at the next delivery point, counted; a full queue
  drops the oldest, counted.
- `unit_aura_spec`: a real `UNIT_AURA` with a secret info table reaches the subscriber as the preallocated
  `{ isFullUpdate = true }`.
- `trace_spec`: on, every read and event writes one record in order; the ring wraps; a secret is stored as
  `"S"`; a secret from a passthrough is counted; off, nothing is written.
- `facade_spec`: inventory equals `tools/api_inventory.txt` (all names, each with status and reason);
  every event registered at runtime is listed in `tools/event_inventory.txt` with a status (not equality:
  registrations depend on version and runtime, `Events.lua:309`, `:361`, `:383-386`, and UI frames register only
  when a display activates, `UI.lua:1896`); no inventoried event exceeds eight slots.
- `alloc_spec` gains 10,000 mixed events through the event facade (passthroughs, `UNIT_AURA`, `PLAYER_SWING`
  paired with target `UNIT_COMBAT`, own casts, deaths), delivered to a no-op subscriber, with the facade's
  `CombatLogGetCurrentEventInfo` called per row and every passthrough wrapper called: 0 bytes with tracing off and
  0 bytes with it on (after `SetTrace(true)`).
- `tools/check_api_reads.sh` passes on the loaded files (§1.2).

In game (the user runs it; Warrior on a dummy):
1. `/reload`: no Lua error, no "Blizzard UI only" popup; `Snapshot()` lists no unexpected stub event.
2. Out of combat: `/hekili vs trace on`, cast, `dump`: VirtualState's source record precedes Hekili's delivery for
   `UNIT_SPELLCAST_SUCCEEDED` (G2), and `SPELL_CAST_SUCCESS` follows as a row.
3. Arms in Battle Stance at a dummy: Overpower is recommended only after a floating DODGE, within one cycle, and
   not after the 5 s window or after Overpower is cast; in Defensive Stance with rage under the threshold, the
   swap to Battle Stance for Overpower is recommended inside the window. The trace shows target `UNIT_COMBAT`
   DODGE → `SWING_MISSED` (inferred) → the Warrior handler.
4. `UNIT_AURA` in combat: no error; `Hekili.Engine.eventsTriggered.UNIT_AURA_FULL` is set; Rend still tracks
   (spec §11's checkpoint, unchanged).
5. Cast history: `prev_gcd` works and `Hekili.EData` shows `COMBAT_LOG_EVENT_UNFILTERED_1` with a per-row cost
   (`Events.lua:88-91`); each cast appears once in `state.player.lastcast`'s history.
6. Swing clock (phase B): over 60 s on a dummy, `state.swings.mh_actual` matches the time of the `PLAYER_SWING`
   that produced it (stamped in the trace) within 50 ms, both for paired swings and for unpaired ones emitted when
   their window closes.
7. The cycle cost with the full read facade against b62beacf (Hekili's CPU profile, `Hekili:ProfileCPU`), tracing
   off.

## 10. Risks with closers

| # | Risk | Closer |
|---|---|---|
| E1 | Passthrough wrappers slow hot reads (`GetTime`, `UnitExists` in the cycle) | in-game step 7; if the cycle grows by more than 5 %, the hottest names take the raw function when tracing is off at load (decision 4) |
| E2 | A frame Hekili does not create through the facade registers events directly (a library, an XML template, a metatable call) | `check_api_reads.sh` greps the loaded files (§1.2); libraries are not Hekili core and keep their own frames |
| E3 | Victim-side outcomes misattributed in groups (another attacker's dodge credited to our swing) | pairing within `PAIR_WINDOW_MS` only (§3), the row marked inferred; in Battle Stance the strict usability read corrects Overpower on the next reset (§6) |
| E4 | Own-cast and swing writes doubled while the Phase 1 feeds and the rows coexist | retire each feed in the same task as its rows (§7); in-game step 5 and a headless count of `AddToHistory` calls |
| E5 | Hekili's dispatch allocates per delivered row (`Events.lua:84, 88-91`) | Hekili's retail cost; measured per row in in-game step 5; rows are emitted only for §11's families |
| E6 | Registering an event the client does not know raises | `pcall` at subscription; stub entry (§2.1) |
| E7 | A row delivered inside a hook is dropped by `ns.callHook` (`Classes.lua:2869`) | no nested delivery; queued and counted (§3) |
| E8 | `UNIT_AURA` fires often in combat (O12: 226 firings), each a full rescan request | `ForceUpdate(…, true)` only adds 0.1 s to the refresh timer (`UI.lua:2459-2461`); the scrape still runs once per cycle |
| E9 | Gated payloads change a handler's input (nil instead of a secret) | the only handlers that received secrets are the target arms of `UNIT_SPELLCAST_*`, which read neither slot (`Events.lua:1017`, `:1029`); the trace shows any other |
| E10 | A deferred row's time skew shifts a time-stamping consumer: the swing clock (up to `PAIR_WINDOW_MS`) or `trackDebuff` (up to one cycle) | swing rows are back-dated from phase B (§3: slot 1 plus `Facade.GetTime` during delivery), checked by in-game step 6; the debuff rows are decision 5 |
| E11 | A passthrough name is secret in some state nobody probed | the trace counts secrets per passthrough (§5); the name becomes a virtual row |

## 11. Phasing

Each phase ends in game; the order follows Phase 2's ranking of silent damage (Phase 2 §2.1: cast history, enemy
count, swing clock, debuff tracking, damage taken), with this session's facts standing in for the Phase 2 probes
they answer (G2 order, drain cost, the plain signals of §1.1).

- **A. The full facade, all passthrough.** `Facade.CreateFrame` and the event facade with every event
  passthrough; `UNIT_AURA` virtual and the original handler restored; the read facade's 124 passthroughs and the
  file-top locals; the tools; the trace ring and `/hekili vs trace`. `CombatLogGetCurrentEventInfo` still a stub,
  no rows. In game: steps 1, 2 (order only), 4, 7.
- **B. Own casts, swings and avoidance (the Warrior's).** First checkpoint: the pairing-window probe (§3) sets `PAIR_WINDOW_MS`. Then the row pool, queue and delivery; own-cast rows,
  swing rows paired within the window, our missed abilities, avoidance on us; the Phase 1 feeds retired; the
  Warrior file in Classic's shape (§6). This phase answers the user's example. In game: steps 2, 3, 5, 6.
- **C. Deaths, damage dealt and taken.** `UNIT_DIED`/`PARTY_KILL` rows to `ns.eliminateUnit`; WOUND rows for enemy
  counting and `ns.storeDamage`.
- **D. Our debuffs on the target.** Inferred `SPELL_AURA_APPLIED/REFRESH`, modelled `REMOVED`, the compensating
  removal on an avoided cast; the deferred lane and decision 5. Feeds `active_dot` and `cycle_targets`.

Phase 2's remaining probes (the dodge window in ms, the `UNIT_AURA` key pattern, the `UNIT_DIED` range,
IMMUNE/RESIST) are run inside the phase that needs them, not as a separate phase.

## 12. Out of scope

- Summons, friendly HoTs, empower casts (`SPELL_EMPOWER_END`) and `SPELL_ENERGIZE` until a loaded class file
  consumes them.
- Rows for other units' casts and auras (identity secret, O4), absorbs, overkill.
- `UNIT_AURA` depth 2 (incremental payloads from `AuraGen` diffs, Phase 2 §5).
- Moving the fold out of the drain; persistence across `/reload` (spec §14, G5).
- Facading frames and events of embedded libraries (`Libs/`).
- Retiring the GCD constant, the spec 1491 loop break and the talent edit through facade policies (decision 7).

## 13. Decisions needed from the user

Each has a recommended default that this spec assumes.

1. **Where the event diversion sits.** Default: at frame creation (`Facade.CreateFrame` shadows the event
   methods), so `ns.RegisterEvent` and friends stay byte-identical to the original. Alternative: edit the four
   registration lines in `Events.lua` (`:174`, `:197`, `:222`, `:240`) to call the layer, which leaves the UI and
   dev-tool frames outside the facade.
2. **`UNIT_AURA`.** Default: always the layer's `{ isFullUpdate = true }` at the real event, and keep drain step 5.
   Alternative: also queue a synthesized `UNIT_AURA` after a drain that moved `AuraGen` and drop step 5 (the
   rescan then lands one cycle later).
3. **Trace controls.** Default: `/hekili vs trace on|off|dump`, a 1024-record ring, not saved, dumped to the chat
   frame (no new edit box). Alternative: a saved option, a name filter.
4. **Passthrough wrappers.** Default: always a wrapper with one branch, so tracing needs no `/reload`. Alternative,
   if E1 trips: the raw function for the hottest names, traced only when tracing was on at load.
5. **Back-dated delivery.** Ruled for swing rows: back-dated from phase B (slot 1 and `Facade.GetTime` during
   delivery, §3). Default for every other row: stamped at delivery (skew up to one cycle). Phase D revisits it
   for the debuff rows.
6. **Attribution of victim-side outcomes.** Default: an outcome is ours only within `PAIR_WINDOW_MS` of our own
   swing or cast (measured in phase B), and a row on us is emitted only when its source is known (the target,
   attacking us). Alternative: drop
   attribution in groups entirely and rely on the usability read.
7. **Absorbing more Forever edits into the facade** (`C_Spell.GetSpellCooldown(61304)` answered as 29515, the spec
   query returning nil for id 0, `GetTalentInfoByID` answered from the `C_Traits` walk), which would revert three
   more core edits. Default: not in this spec; a follow-up once phase A is in.
8. **Secrets from read passthroughs.** Default: allowed. The passthrough is transparent, the trace records a
   secret result as `S` and counts it per name, and the policy table marks which names are known to be secret in
   combat (those are virtual rows). Alternative: gate the first return of every wrapper through `issecretvalue`,
   at one more call per read.
9. **The DevTools skeleton listener and inferred rows.** It generates class data from what it hears
   (`Options/DevTools.lua:1152-1159`), so inferred rows could end up in skeletons. Default: it hears every row,
   with provenance visible in the trace. Alternative: deliver only observed rows to it.
