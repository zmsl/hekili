# VirtualState: the full facade (reads and events)

Date: 2026-10-15; amended the same day with the user's nine decisions (§13). Branch: `forever-warrior-profile` at
b62beacf (`virtualstate-phase1` merged); the plan builds it on `virtualstate-event-facade` from `forever` at 75d71c8b.
This spec amends
the Phase 1 spec (`docs/superpowers/specs/2026-10-14-hekili-virtualstate-design.md`, "spec §N") and replaces the
Phase 2 investigation plan and the Phase 3 outline as the plan input for events: what they asked is settled
below, by the user's decision or by facts measured this session.

Cite conventions:
- A bare `File.lua:N` is Hekili at b62beacf. `fc61b6d9:File.lua:N` is the same file before Phase 1.
- `Classic/Warrior.lua:N` is `git show origin/classic:Classic/Warrior.lua` (origin/classic at fce4fcf1).
- "outline §N" is `docs/research/2026-10-14-virtualstate-phase3-event-bus-outline.md`; "Phase 2 §N" is
  `docs/research/2026-10-14-virtualstate-phase2-eventing-investigation.md`.
- "[V] Cn/Mn/Dn" is a row or detection pattern of `~/src/docs/research/tdf/2026-10-14-virtual-combat-log-events.md`;
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
| §1 decision 3, §7 | the facade keeps 51 names; 124 plain passthroughs revert to direct calls | the facade covers all 175 names, `CreateFrame` and any new one, each `passthrough`, `hybrid` or `virtual` (§1) |
| §4.2 | VirtualState's frame hears shared events independently of Hekili's frames | VirtualState's frame is the only frame registered with the client; Hekili's frames subscribe to it (§2) |
| §4.4 urgent lane | `Hekili:ForceUpdate` only | plus synchronous delivery of the event and of the rows it triggers (§3) |
| §4.6 feeds | the module writes `AddToHistory`, `realQueue`, `swings.*` | retired as synthesized own-cast and swing rows reach `CLEU_HANDLER` (§7) |
| §8 clock | fold in the drain only | unchanged; synthesized rows carry their observation time (§3) |
| §10 | `UNIT_AURA` handler neutered; CLEU skipped at `Events.lua:174` | both reverted to their pre-Forever form (§7) |
| §12 G2 | Hekili's handler runs first; one-cycle staleness accepted | order closed: VirtualState first by construction; staleness unchanged, handler reads stay up to one cycle stale (§3) |
| §14 | no synthesized events, no virtual combat log | in scope (§2) |

## 1. The two facades

Both facades are full: every game function and every game event Hekili core or a class file touches goes through
the layer. Each read has one of three classes (decision 8), chosen per name from its probe evidence:
- **passthrough**: the raw call, untested. For a name that is plain by probe, or whose value Hekili never uses in a
  way a secret breaks; no modelling until one is needed. It exists so it can be traced (§5) and so a later Forever
  finding changes one row, not Hekili.
- **hybrid**: the raw call, and a secret answer (any of the first four values, or a table's time fields) replaced by
  the model's. For a name secret only sometimes (in combat, or for some units). A hybrid also answers a Forever-only
  shape in retail's (decision 7: the GCD spell, an empty specialization slot) and the clock of a back-dated row (§3).
- **virtual**: never the game's answer, the model only. For a name secret always, absent on Forever (a fixed,
  API-shaped answer: Phase 1's stubs are virtual rows), or answered from VirtualState for a reason beyond secrecy (the
  auras' one instance-ID space, §2.5; rage's believed estimate, G4).

Events have the same split: an event is passthrough (the real event, its payload through `Plain`, §2.3) unless the
policy table (§2.2) makes it virtual (synthesized or reshaped) or the client refuses it (a stub, never delivered).

### 1.1 The read facade (`ns.Facade`)

`Virtual/API/Facade.lua` keeps its shape (`kept(name, class, fn, reason)`, `Facade.lua:40-50`; `Status` (now the
class), `Why`, `Inventory`, `Facade.lua:517-528`; `Stubs` goes with the stub status) and gains two load-time helpers:
`passthrough(name, reason)` resolves the real function (`resolve`, `Facade.lua:31-38`) and stores it as the row;
`hybrid(name, policy, reason)` stores the raw call with the policy behind it. `kept` puts every row, of any class,
behind one wrapper (the trace's branch, §5). An absent passthrough (a nil global) becomes a virtual row answering
nothing, which is how the seven deprecation shims are handled today in each file
(`local IsPlayerSpell = IsPlayerSpell or function() end`, `Events.lua:10`; spec §7.3); that fallback moves into
the facade.

The full table is two files: `Virtual/API/Facade.lua` holds every row with its class and its evidence as the reason
(the 124 former passthroughs carry `docs/forever-facade-notes.md`'s secrecy column verbatim), and
`tools/api_inventory.txt` lists every name with its class, one `Name<TAB>class` line each, sorted; `facade_spec`
asserts the two agree. By group (a name the first rows class differently keeps that class where a later group lists
it):

| Group | Names | Class | Evidence |
|---|---|---|---|
| Phase 1 kept, secret always or absent | `UnitPower`, `UnitPartialPower`, `UnitHealth`, `UnitHealthMax`, `UnitGetTotalAbsorbs`, `UnitInRange`, the absent or dead names (`UnitAura`, `UnitAuraBySlot`, `GetSpellLink`, `GetItemInfo` ...), `C_Spell.GetSpellCastCount`, `C_UnitAuras.GetAuraSlots` | virtual | spec §7.2-§7.4 |
| Phase 1 kept, beyond secrecy | the six aura reads (`C_UnitAuras.*`, `AuraUtil.ForEachAura`/`FindAura`): one instance-ID space in and out of combat (§2.5); `CombatLogGetCurrentEventInfo` (the row being delivered, §2.4); `GetTalentInfoByID` (the `C_Traits` walk, decision 7) | virtual | spec §7.2; [W §4] errors when tainted |
| Phase 1 kept, secret in combat | the 12 stats, `GetHaste`, `GetMeleeHaste`, `UnitSpellHaste`, `UnitAttackSpeed`, `GetUnitSpeed`, `GetTotemInfo`, `GetPowerRegenForPowerType`, `GetManaRegen`, `C_Spell.GetSpellCooldown`, `C_Spell.GetSpellCharges`, `UnitCastingInfo` and `UnitChannelInfo` (player plain, target secret) | hybrid | [W PR2, PR4, PR7, PR12, PR14, PR16; SU PR2]: out of combat the raw answer is the truth, in combat the Phase 1 policy answers |
| The clock | `GetTime` | hybrid | plain [W]; a back-dated row's observed time while it is delivered (§3) |
| Forever shapes (decision 7) | `C_Spell.GetSpellInfo`, `C_Spell.GetSpellTexture` (61304 asked as 29515), `C_SpecializationInfo.GetSpecializationInfo` (id 0 answered as nil) | hybrid | cleanup Q6, Q7 |
| `IsUsableSpell` | `IsUsableSpell` | passthrough | absent on Forever; the raw `C_Spell.IsSpellUsable` (plain [W PR14; SU]) |
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
| Deprecation shims | `HasOverrideActionBar`, `HasVehicleActionBar`, `IsActionInRange`, `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `SpellIsSelfBuff` | passthrough; a virtual row answering nothing when the global is nil | only while `loadDeprecationFallbacks` is on (spec §7.3; cleanup Q12) |
| Frames | `CreateFrame` | virtual (§2.1) | the event facade's entry point |

Counts after the plan's follow-up task: 121 passthrough, 28 hybrid, 27 virtual (176 names with `CreateFrame`).
Phase A ends at 125/24/27; `GetTime` turns hybrid in phase B, the three Forever shapes in the follow-up.

Out of the inventory: Lua and library calls (`LibStub`, `C_Timer`, `debugprofilestop`, `hooksecurefunc`, the
string and table globals) and UI widgets that read no game state (`UIParent`, `GameTooltip`, the dropdown and
fade helpers); `.luacheckrc` keeps them in `read_globals`.

Every row, whatever its class, is stored behind one wrapper built at load (decision 4): `function(...) if
hekili.ActiveDebug then return traced(name, class, a1, a2, fn(...)) end return fn(...) end`. Off, its cost is one
field test and one tail call; no allocation (Lua 5.1 passes `...` without building a table). On, `traced` writes the
trace line (§5) and returns `...` unchanged, so names with many results (`GetInstanceInfo`, `UnitCastingInfo`: 9
each) lose none. A passthrough is transparent: it does not gate secrets (decision 8). Every name known to be secret
sometimes is a hybrid or virtual row, and the trace records a secret result as `S` and counts it per passthrough
name (§5), which is how a misfiled name shows up: it moves to hybrid with a policy.

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
VirtualState's own Hekili-side file, `Adapter.lua`, does too: its boot frame (`Adapter.lua:36-42`) comes from
`Facade.CreateFrame` and hears `PLAYER_LOGIN` through the layer like any Hekili frame, so no loaded file is exempt.

- `tools/api_inventory.txt` lists all names of the facade with their class (175 plus `CreateFrame`, plus any name a
  later probe or file adds); `Virtual/API/spec/facade_spec.lua` asserts `Facade.Inventory()` and each name's class
  equal it, and that every entry has a reason.
- `tools/check_api_reads.sh` returns to its pre-Phase-1 rule, "no game API from the inventory is read directly"
  (`fc61b6d9:tools/check_api_reads.sh`: W113 on any inventory global, namespaces included, plus the `_G.Name` grep),
  so the dotted-name grep Phase 1 added is dropped: a bare `C_Spell` is itself W113 once `.luacheckrc` stops
  declaring it. With `CreateFrame` in the inventory, every frame a loaded file makes comes from the facade; the
  script adds one grep that fails on `getmetatable(` combined with `RegisterEvent`/`RegisterUnitEvent` (the only
  way left to reach the real method).
- `.luacheckrc` removes the 124 reverted names and `CreateFrame` from `read_globals` (lines 1-3 restate "every game
  read goes through `ns.Facade`"). The layer's own client frame (§2.1) is made from the client table VirtualState
  resolves at load (as `Facade.lua` resolves every real function), so `check_api_reads.sh` needs no exemption.
- `Events.lua:6` aliases `AuraUtil` directly today; it becomes `Facade.AuraUtil` in the same task that restores
  the `UNIT_AURA` body, because that body captures `AuraUtil.ForEachAura` at load (`fc61b6d9:Events.lua:1255`).
- No event inventory file: every event is passthrough unless §2.2 lists it, and registrations depend on version and
  runtime (`Events.lua:309`, `:361`, `:383-386`; UI frames register only when a display activates, `UI.lua:1896`).
  `Snapshot()` lists the events the client refused (stubs), the delivery count and handler errors.

## 2. The event facade

### 2.1 Who owns the frame

Hekili core keeps its event system as written: `ns.RegisterEvent` (`Events.lua:168-182`), `ns.UnregisterEvent`
(`:186-198`), `ns.RegisterUnitEvent` (`:203-243`), the `handlers[event]` and `unitHandlers[unit].events[event]`
tables (`:57-58`), `GenericOnEvent` (`:78-95`), `UnitSpecificOnEvent` (`:97-117`), `ns.StartEventHandler`
(`:120-153`) and every handler. Class files keep `spec:RegisterEvent`, `spec:RegisterUnitEvent` and
`spec:RegisterCombatLogEvent` (`Classes.lua:1074-1088`).

The diversion is at frame creation, not in those functions (decision 1). `Facade.CreateFrame(...)` calls the real
`CreateFrame` and shadows four methods on the returned instance: `RegisterEvent`, `RegisterUnitEvent`,
`UnregisterEvent`, `UnregisterAllEvents` (and `IsEventRegistered`, answered from the layer). Hekili's frames are
insecure, so an instance field over a frame method is legal (Phase 2 §6 option (b), from feasibility §C.2.1). Through
the file-top `CreateFrame` local, the frames Hekili makes become subscribers: the general frame
(`Events.lua:56`), the per-unit frames (`:207`, `:227`), the display buttons that register overlay, alpha,
keybinding and flash events (`UI.lua:1904-1922`) and the dev tool's listener (`Options/DevTools.lua:1152-1157`,
which today registers `COMBAT_LOG_EVENT_UNFILTERED` on the client directly, cleanup Q5). None of them is
registered with the client again.

**Hekili cannot tell (decision 2).** Every event Hekili hears, real or modelled, is intercepted by the layer and
delivered through the same subscription path, in the game's own name and payload shape: the same `OnEvent` script,
the same argument positions, `COMBAT_LOG_EVENT_UNFILTERED` with no payload and its row from
`CombatLogGetCurrentEventInfo`. Nothing in a payload or in the call marks a synthesized event; provenance lives only
in the layer (its counters and the trace, §5). A raising handler is reported through `geterrorhandler` and the
delivery loop goes on to the next subscriber, as the client isolates frames.

- `frame:RegisterEvent(e)` → `EventFacade.Subscribe(frame, e)`; `frame:RegisterUnitEvent(e, u1, u2)` →
  `Subscribe(frame, e, u1, u2)`; the unregister methods remove the subscription.
- **Unit filters are per subscriber.** Each subscription keeps its own unit list (none, or one or two units,
  preallocated at Subscribe), and delivery checks the event's unit against that list, subscriber by subscriber,
  the way `UnitSpecificOnEvent` (`Events.lua:97-117`) dispatches through `unitHandlers[unit]`. Hekili has one
  frame per unit (`:207`, `:227`), and both the player and the target frame subscribe to
  `UNIT_SPELLCAST_SUCCEEDED`, `UNIT_SPELLCAST_START` and `UNIT_AURA` (`:1008`, `:1028`, `:1261`); a per-event
  unit set would hand the target's event to the player frame too and run the target handlers twice.
- VirtualState's own frame (made in `EventFacade.lua`, no longer in `Sources.lua:176-189`) is the one frame
  registered with the client. Its registration
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

**Lifecycle.** The event-facade file (`Virtual/Events/EventFacade.lua`, TOC-loaded with the facade, before
`Hekili.lua`) creates the layer's client frame when it loads, with the real `CreateFrame` resolved once from the
client table (`_G` in game; the fake api in specs, which the loader sets before it runs any Hekili file). Hekili's
frames subscribe while their files load (`PLAYER_ENTERING_WORLD` at `Events.lua:336`, `VARIABLES_LOADED` at
`:949`, `SPELLS_CHANGED` at `:2254` and about 40 more), and each subscription is registered with the client as it
is made. Passthrough delivery runs from load, so events before login (`VARIABLES_LOADED`, `PLAYER_LOGIN`) reach
Hekili as before. VirtualState's sources run only once `VS.Start` has set `I.api` (step 1 of §3 is skipped while
`I.api` is nil; today `S:OnEvent` would index nil, `Sources.lua:153, 158`). `VS.Start` (`Sources.lua:176-189`)
then adds the sources' registrations to the same frame instead of creating one; an event both need is registered
once. The boot frame at `Adapter.lua:36-42` is a facade frame (§1.2): `PLAYER_LOGIN` reaches it through the layer,
whose sources are skipped for that one event (`I.api` is set by the very `VS.Start` the boot frame calls).

**Template frames.** `Facade.CreateFrame` also returns tooltip frames (`Hekili.lua:670` `ns.Tooltip`,
`Options/DevTools.lua:237`). A template's `OnLoad` runs inside the real `CreateFrame`, before the shadow exists,
so any registration it makes is on the client directly. The shadow is installed on every frame, and
`check_api_reads.sh` cannot see `OnLoad` code, so the templates Hekili passes were checked against the client's
FrameXML (`wow_ui_grep`, flavor forever): `GameTooltipTemplate` (`GameTooltip_OnLoad` registers
`TOOLTIP_DATA_UPDATE` on the client when `supportsDataRefresh`, handled by Blizzard's own script; Hekili's code
handles none), `UIPanelButtonTemplate`, `BackdropTemplate` (`OnBackdropLoaded` registers nothing),
`UIDropDownMenuTemplate`, `CooldownFrameTemplate` and Hekili's `HekiliPopupDropdownRangeTemplate`
(`UIDropDownCustomMenuEntryMixin`, no events). A later `UnregisterEvent` by Blizzard code on such a frame reaches
the shadow and leaves the client registration in place, which only keeps Blizzard's own handler running.

With this, the two Forever edits in the registration functions are reverted to their originals (phase B, with the
first rows):
`events:RegisterEvent( event )` for every event except `FRAME_UPDATE` (today `:174` also skips
`COMBAT_LOG_EVENT_UNFILTERED`) and the matching unregister at `:197`. A subscription to
`COMBAT_LOG_EVENT_UNFILTERED` is a subscription to the layer's synthesized log; the client never sees it.

### 2.2 The event policy table

Every event a loaded file registers is passthrough unless a row below says otherwise.

| Event | Status | Policy |
|---|---|---|
| any event not listed | passthrough | the real event; payload slots through `Plain` (§2.3) |
| `UNIT_AURA` (other units: the dev tool's general registration, `Options/DevTools.lua:1155`) | passthrough with `info` nil | the client's table has secret fields in combat and the layer has no beliefs for those units; the dev tool's handler does not read it (`Options/DevTools.lua:362-366`) |
| `UNIT_AURA` (player, target) | virtual | the real event triggers VirtualState's aura walk (spec §4.5), then the subscribers receive `(unit, info)` with `info` the unit's preallocated `{ isFullUpdate = true }` (§2.5; decision 2: phase A). Phase C replaces it with the believed `addedAuras`/`updatedAuraInstanceIDs`/`removedAuraInstanceIDs` lists from the beliefs' changes, still in the client's shape |
| `UNIT_SPELLCAST_*` (target) | passthrough | `spellID` and `castGUID` arrive nil (secret, [V] §5 O4); Hekili's target arm reads neither (`Events.lua:1017`, `:1029`) |
| `UNIT_POWER_FREQUENT` (player) | passthrough | payload `(unit, powerToken)` is plain ([V] N11); the handler's `UnitPower` read (`Events.lua:1196`) is the facade's belief (spec §7.4) |
| `UNIT_COMBAT` | passthrough to subscribers (Hekili: player only, `Events.lua:1716`) | the layer also registers it for every unit to build rows (§2.4); plain in combat ([V] N27, O1: 779 firings, 0 secret). Payload `(unitTarget, event, flagText, amount, schoolMask)` (wow MCP, flavor forever) |
| `COMBAT_LOG_EVENT_UNFILTERED` | virtual | never registered with the client; rows synthesized (§2.4) and delivered with no payload; `Facade.CombatLogGetCurrentEventInfo()` returns the row being delivered |
| an event the client rejects at registration | stub | never delivered |

### 2.3 Passthrough payloads

The layer's `OnEvent(frame, event, r1..r8)` gates each argument into a local, `local a1 = Plain(api, r1)` ... `a8`
(`Sources.lua:22-27`), and passes the eight locals down the subscriber loop: a secret becomes nil before Hekili
sees it, nothing is shared between deliveries, and a client event that fires while another is being delivered
(some client calls fire events synchronously) is delivered at once in its own call, as on retail. Real events are
never queued; only synthesized rows are (§3, §4). Eight covers every event Hekili registers (the
widest, `UNIT_COMBAT`, has five; `UNIT_SPELLCAST_INTERRUPTED` and `_CHANNEL_STOP` five; `ENCOUNTER_START` and
`UNIT_SPELLCAST_SENT` four); every real event reaches a subscriber with eight slots (trailing nils), which no handler
counts. A table argument cannot be gated by value; the only one Hekili consumes is
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
the current row's slots up to its last, `unpack(row, 1, row.n)` on the fixed pool table (no allocation).

Provenance is [V]'s: observed (a plain signal says it happened), inferred (plain signals plus a rule), modelled
(spell data and a clock). The families, with the Hekili consumer each one feeds:

| Family | Rows | Source | Provenance | Consumer |
|---|---|---|---|---|
| Own casts | `SPELL_CAST_START`, `SPELL_CAST_SUCCESS`, `SPELL_CAST_FAILED`; a channel's `SPELL_AURA_REMOVED` | our `UNIT_SPELLCAST_START/SUCCEEDED/FAILED/INTERRUPTED/CHANNEL_STOP` with the `UNIT_SPELLCAST_SENT` target GUID ([V] C36, C38, C40, D1; O16: 134 successes plain) | observed | `:1505-1601`: `realQueue` `CAST_FINISH`/`CHANNEL_*`/`PROJECTILE_IMPACT`, `AddToHistory` (`:1601`) |
| Our swings | `SWING_DAMAGE` (amount, critical), `SWING_MISSED` (missType `DODGE`/`PARRY`/`MISS`, isOffHand) | `PLAYER_SWING` per hand for time and hand; the target's `UNIT_COMBAT` within `PAIR_WINDOW_MS` for the outcome (§3) ([V] C1, C3, D7; O3: `PLAYER_SWING` also fires on avoided swings; O1: the target's MISS, DODGE, PARRY plain, 374 firings); an on-next-swing strike's success takes its swing's outcome as `SPELL_DAMAGE`/`SPELL_MISSED` and no swing row | observed time; the outcome's attribution to us is inferred (`UNIT_COMBAT` is victim-side) | swing timers `:1622-1635`; class hooks (Overpower, §6) |
| Our ability missed | `SPELL_MISSED` (missType) | our `UNIT_SPELLCAST_SUCCEEDED` of an ability that starts combat or strikes on the next swing, plus the target's `UNIT_COMBAT` DODGE/PARRY/MISS within `PAIR_WINDOW_MS` ([V] C9, M2; O16: a dodged Heroic Strike still fired its success) | inferred | class hooks |
| Avoided on us | `SWING_MISSED`/`SPELL_MISSED` with `destGUID` = ours | the player's `UNIT_COMBAT` DODGE, PARRY, BLOCK, MISS ([V] C4, M1-M4, D13; O1: 165 firings plain); the attacker is not in the event, so the row is emitted only when attribution names it (decision 6, below); otherwise no row | observed type, inferred source | class hooks (Revenge, §6); tank attacker counting `:1619-1620` |
| Deaths | `UNIT_DIED`, `PARTY_KILL` | `UNIT_DIED`, `PARTY_KILL`, `PLAYER_TARGET_DIED` with plain GUIDs ([V] C66-C68, D11; O6: 34/23/23 firings) | observed | `ns.eliminateUnit` (`:1403-1419`); Victory Rush window (§6) |
| Damage we deal | `SWING_DAMAGE`, `SPELL_DAMAGE` on the target (phase B, with our swings and abilities above) and on plates (phase C) | the unit's `UNIT_COMBAT` WOUND paired with our swing or cast within `PAIR_WINDOW_MS` | inferred | enemy counting `:1693-1701` (`ns.updateTarget`) |
| Damage on us | `SWING_DAMAGE`, `SPELL_DAMAGE` with `destGUID` = ours | the player's `UNIT_COMBAT` WOUND (amount, school) ([V] C2, C4; O1); emitted only when attribution names the source, as above; physical (`schoolMask` 1) as `SWING_DAMAGE`, other schools as `SPELL_DAMAGE` with spellId 0 | observed (source inferred, as above) | `ns.storeDamage` (`:1451-1495`) |
| Our casts' auras | `SPELL_AURA_APPLIED`/`_REFRESH`/`_REMOVED` on the target (debuffs) and on us (buffs) | phase B: what our cast's `now` verbs wrote (§12a: `applyBuff`, `applyDebuff`, `removeBuff`, `removeDebuff`, `addStack`, against the aura's believed expiry before the cast), APPLIED or REFRESH at the cast's time, REMOVED when the cast removed it or at the modelled expiry ([V] C27, D3). Phase D adds travel time and the compensating `SPELL_AURA_REMOVED` when the cast's outcome was DODGE/PARRY/MISS | inferred / modelled | `ns.trackDebuff`, `active_dot` (`:1652-1687`) |
| Energize | `SPELL_ENERGIZE` on us | phase B: a resource our cast's `now` gained (§12a's `gain`) ([V] C14, D6) | modelled | none in core ([V] §6; outline §1); class hooks |

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
| `SWING_DAMAGE` | amount | overkill 0 | school 1 | resisted 0 | blocked 0 | absorbed 0, critical, glancing, crushing | isOffHand (its last slot) | absent (nil: `not multistrike`) | amount `:1469`; overkill `spellName > 0` `:1696`; `offhand`, `not multistrike` `:1622` |
| `SWING_MISSED` | missType | isOffHand | amountMissed 0 | critical false | — | — | — | — | `offhand = spellName` `:1623`; `actionType` (Classic `:443`) |
| `SPELL_DAMAGE` | spellId | spellName | school | amount | overkill 0 | school, resisted 0, blocked 0, absorbed 0 | critical | glancing false; 23 crushing false, 24 isOffHand false (its last slot) | `interrupt > 0` `:1696` |
| `SPELL_MISSED` | spellId | spellName | school | missType | isOffHand false | 17 amountMissed 0, 18 critical false (its last slot) | — | — | `amount == "IMMUNE"` `:1699`; `spellMissType` (Classic `:443`) |
| `SPELL_AURA_APPLIED`, `_REFRESH`, `_REMOVED` | spellId | spellName | school | auraType `"DEBUFF"`/`"BUFF"` | amount 0 | — | — | — | `spellID` for `class.auras` `:1654` |
| `SPELL_ENERGIZE` | spellId | spellName | school | amount | overEnergize 0 | 17 powerType, 18 maxPower (its last slot) | — | — | class hooks only |
| `SPELL_CAST_START`, `_SUCCESS` | spellId | spellName | school | — | — | — | — | — | `class.abilities[ spellID ]` `:1505-1601` |
| `SPELL_CAST_FAILED` | spellId | spellName | school | failedType `""` | — | — | — | — | `:1541-1545` |
| `UNIT_DIED`, `PARTY_KILL` | recapID 0 (`UNIT_DIED` only) | unconsciousOnDeath false (`UNIT_DIED` only) | — | — | — | — | — | — | `destGUID` `:1403-1419` |

No nil holes: every slot up to a subevent's last slot is a value (`0`, `false`, `""` or the datum), because
`ns.callHook` rebuilds the tuple with `unpack( vars )` after `load_args` (`Classes.lua:2858-2877`), and a nil
inside the tuple makes `#vars`, and so the tuple's length, unreliable. Slots past a subevent's last slot are absent.
Elsewhere: `destFlags` and `sourceFlags` are numbers (`bit.band` at `:1449`), synthesized from plain
`UnitCanAttack`/`UnitIsFriend`; GUIDs are strings (`:len()` at `:1512`, `:1557`; `:match` at `:1409`, `:1438`);
names are `""` (no Hekili reader needs one: `IsActuallyFriend("")` is false). A row on the target or another unit
needs that unit's GUID: with none (no target at the swing, the target cleared before an aura row) no row is made,
since a `""` destination with hostile flags would reach `ns.updateTarget("")` as an enemy. Own-cast rows keep `""`
with our flags (Hekili's handler falls back to the target for a cast's destination). Slot 12 of an own-cast row is
the spell ID, never nil. Source and destination flags are
constants: ours `0x511` (mine, friendly, player), a hostile's `0xA48`. `cleu_rows_spec` asserts this table.

**Attribution of hits on us (decision 6).** `UNIT_COMBAT` on the player says what landed or was avoided, not who
swung. The layer keeps two things (`Virtual/Events/Attackers.lua`):
- *Who targets me*: for the tokens `target`, `focus` and `nameplate1`-`40`, on `UNIT_TARGET`, `PLAYER_TARGET_CHANGED`,
  `PLAYER_FOCUS_CHANGED` and `NAME_PLATE_UNIT_ADDED/REMOVED`, the token's plain GUID, `UnitCanAttack("player",
  token)` and `UnitIsUnit("<token>target", "player")` (the "<token>target" strings built once at load). Each answer
  goes through `Plain`: a secret `UnitIsUnit` counts as "not targeting us" (its status is noted for `Snapshot()`;
  probe 2 of phase B measures it).
- *Attacker clocks*: per attacker GUID (8 preallocated), an anchor and a period like our own hands. The period is
  `UnitAttackSpeed(token)` when it is plain (probe 1 of phase B; the facade's `UnitAttackSpeed` is a hybrid, so a
  plain answer for a hostile is the client's); otherwise it is learned from the gap between consecutive hits credited
  to that attacker (the first gap in [1, 5] s sets it; later gaps within `ATTACK_TOLERANCE` of a whole number of
  periods refine it, 0.8/0.2).

A melee hit or avoidance on us is credited to the attacker, among the hostiles targeting us, whose clock predicts a
swing nearest the hit, within `ATTACK_TOLERANCE` (0.2 s). While exactly one hostile targets us and its clock is not
set (no anchor or no period), the hit is that one's and starts its clock; a non-physical hit (a spell does not follow
the swing clock) is credited only to a lone hostile, its clock set or not, and does not move the clock. A clock is
made only when a hit is credited (a free slot first, else the oldest anchor's), so a learned period survives the
anchors' reset at combat end.
Otherwise the hit stays unattributed: no row (counted, `Snapshot()`'s `unattributed`), so it stays out of the enemy
counter. The credited hit re-anchors that clock. Dodges and parries of our own swings are not attributed this way:
they are the target's `UNIT_COMBAT` paired with our swing within `PAIR_WINDOW_MS` (§3).

**No row on us with an unknown source.** The tank branch (`Events.lua:1619-1620`: tank role, `destGUID` ours, a
`SWING` subevent) calls `ns.updateTarget( sourceGUID, time, true )`, and `updateTarget` rejects only nil and our
own GUID (`Targets.lua:659`). A `""` or invented source would become a counted enemy for Protection, and a nil
source would leave a hole in the tuple (above). So an unattributed hit makes no row: Revenge then falls back to its
usability read (§6) and `storeDamage` misses that hit, which is what Hekili does on Forever today. `cleu_rows_spec`
checks it (nobody known to target us, or a secret answer: no row, counted).

What cannot be synthesized ([V] §3; outline §1): overkill (so overkill elimination at `:1696` never fires and
deaths come from `UNIT_DIED`/`PARTY_KILL` only), absorbed and over-energize amounts, the source of a hit beyond the
attribution rule, other units' casts and auras (the target's `spellID` is secret, O4), `SPELL_PERIODIC_MISSED`,
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

- **One handler, in order.** The layer's `OnEvent` runs (1) VirtualState's sources for the event (`S.Run`, which
  replaces `S:OnEvent`, `Sources.lua:152-163`, and receives the slots already gated: logging and staging, the §4.6
  feeds while they exist, `Hekili:ForceUpdate` through `I.urgent`, `Adapter.lua:31-33`), then (2) the event's
  policy builds the payload, then (3) delivers it to the subscribers in subscription order, then (4) delivers the
  rows this event completed. Hekili now
  hears every event after VirtualState has seen it. CP1/CP2/CP4 2026-10-15 measured the opposite today (Hekili's
  `UNIT_SPELLCAST_SUCCEEDED` handler about 1 ms before VirtualState's urgent lane); G2 is closed by construction.
- **"After the fold"** means after the sources have logged the observation, not after a belief fold: the fold
  stays inside the drain (spec §8), which runs inside `Hekili.Update`. Hekili's handlers read beliefs through the
  facade, at most one cycle stale (0.2 s in combat), as in Phase 1.
- **Synchronous rows** are emitted by the sources in step (1) and delivered in step (4) of the event that completes
  them: a target `UNIT_COMBAT` within the window of our `PLAYER_SWING` emits the swing row; our
  `UNIT_SPELLCAST_SUCCEEDED` emits `SPELL_CAST_SUCCESS`.
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
- **Deferred rows** (unpaired swings, modelled expiries, our casts' aura and energize rows the `now` verbs write
  when the drain folds the cast (§12a), later a debuff applied after travel) go into the queue (§4) and are delivered at the next delivery
  point: the layer's own `OnUpdate` (after `S.Flush` and the deferred lane's `Tick`, which closes pairing windows and
  emits modelled expiries) or the end of the next client event. Never inside `Hekili.Update`'s coroutine, a reset or a pack
  hook (outline §6). Hekili's coroutine yields across frames, so a delivery may land while a cycle is suspended;
  on retail every event does the same. Whether the layer's `OnUpdate` runs before or after Hekili's engine frame
  (`UI.lua:2370-2450`) does not matter: only deferred rows are delivered there, and either way the next cycle
  reads what they wrote (outline §6's question, closed without a measurement).
- **Time as accurate as possible (decision 5).** A row with an observed basis carries the observed time in slot 1
  and is back-dated on delivery; a purely modelled row is stamped at delivery. Per family:

  | Family | Basis | Slot 1 | Back-dated |
  |---|---|---|---|
  | Own casts (`SPELL_CAST_*`, a channel's end) | our `UNIT_SPELLCAST_*` | that event's `GetTime()` | yes (delivered in the same event, so it equals the clock) |
  | Our swings and abilities on the target | `PLAYER_SWING` or our cast, and the target's `UNIT_COMBAT` | the earlier of the two | yes |
  | An unpaired swing | `PLAYER_SWING` | the swing's | yes |
  | Hits on us | the player's `UNIT_COMBAT` | its time | yes |
  | Our casts' auras, APPLIED/REFRESH, and a REMOVED the cast caused | our cast (the drain applies it up to a cycle later) | the cast's | yes |
  | Our casts' auras, REMOVED at the modelled expiry | the spec's duration | the delivery's | no |
  | Energize | our cast | the cast's | yes |
  | Deaths (phase C) | `UNIT_DIED`, `PARTY_KILL` | their time | yes |
  | A usability flip (a class file's, §6) | the plain `IsSpellUsable` read | not a row: the class file reads it now | n/a |

  Back-dating matters most for swings. Every `SWING_DAMAGE`/`SWING_MISSED` row is emitted when its pair
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
- **Re-entrancy.** A synthesized row emitted while a delivery is in progress is queued, never delivered nested,
  and counted (`requeued`): the delivery loop takes it after the current row; a real client event is delivered as it
  arrives (§2.3). `ns.callHook` returns at once for an event whose hooks are running
  (`Classes.lua:2869`), so nesting would drop rows silently. A subscription added during a delivery takes effect
  for the next event (the loop runs to the count it read at entry).
- **Drop policy.** A full queue drops the oldest row and counts it (`dropped`); a dropped or overflowed row is
  never re-emitted (outline §7 default). During a delivery the row being delivered still holds its slot, so when only
  that slot is left the new row is the one dropped (counted), never the row a subscriber is reading.
- **No delivery inside a coroutine.** A client event fired synchronously inside `Hekili.Update`'s coroutine leaves its
  rows queued (`coroutine.running()` is tested at no cost); the next `OnUpdate` delivers them.

## 4. Payloads and pools

- One row pool of 64 slots, each a fixed table of the 24 positional slots `CLEU_HANDLER` destructures
  (`Events.lua:1399`), plus the row's time, provenance and family. Interned strings only (subevent names, miss
  types, `""`); GUIDs are the plain strings the client handed the layer. Allocated when `CombatLog.lua` loads.
- The queue is a ring over the pool's slot indices (one reader, the delivery point: Hekili and class files hear
  rows through the same frame subscription, so per-reader cursors are unnecessary; outline §4).
- One `UNIT_AURA` info table per unit, two in all; the two pairing buffers of §3 (8 entries each); the attacker
  clocks (8) and the 42 target-of tokens of §2.4; per tracked aura and unit, its believed expiry for the aura rows.
  Passthrough payloads are locals (§2.3), never stored.
- Plain by construction: every value placed in a row or a slot has passed `Plain` or is the layer's own constant.
  No row ever holds a secret, so `CombatLogGetCurrentEventInfo` needs no gate.
- Zero allocation in every recurring path: receiving, gating, emitting, queueing, delivering and the facade's
  `CombatLogGetCurrentEventInfo`. Hekili's own dispatch allocates per call (`GenericOnEvent` builds a key string
  per handler, `Events.lua:84`, and an `eventData` table per new key, `:88-91`); that is Hekili's retail cost,
  outside the layer's test, and is measured per delivered row from `Hekili.EData` (§9).

## 5. Tracing

The trace writes through Hekili's own debug and snapshot facility (decision 3): no ring of its own, no command.
- On means Hekili is making a snapshot: `Hekili.ActiveDebug` is true while `Hekili:MakeSnapshot` runs a cycle
  (`/hekili snapshot`, the snapshot keybinding, pausing, an automatic snapshot; `Options/Options.lua:9649-9679`).
  `Facade.Attach(Hekili)` (`Adapter.lua`) names the addon table; until then nothing is traced.
- Each facade read writes one line through `Hekili:Debug` into the display's snapshot log: `[vs] <class> <name>(<two
  arguments>) -> <four results> #<count>`, where the class is the one that answered (`passthrough`, `virtual`, and
  `hybrid:raw` or `hybrid:model` for a hybrid, decision 8). `GetTime` is read too often to write: it is counted only
  (`Facade.QUIET`). A secret value is written as `S` after an `issecretvalue` test (never `a and b or c`); a secret
  returned by a passthrough is also counted per name (`Facade.secrets`, listed by `Snapshot()`), which is how a
  misfiled passthrough is found. A table result (the facade's shared AuraData, `Facade.lua:236-262`; a cooldown
  info table) is written as its scalar fields at call time (`spellId`, `expirationTime`, `applications`;
  `startTime`, `duration`).
- Each client event the layer receives and each row it delivers during a snapshot writes a line too (`[vs] event
  <name>(...)`, `[vs] row <subevent> <family> <provenance> t=<slot 1>`).
- Each display's snapshot log opens with `VirtualState.Snapshot()` (the adapter wraps `Hekili:SetupDebug`), so the
  snapshot carries the beliefs, the read statuses, the event facade's counters (`delivered`, `errors`, refused
  events), the rows' counters (`emitted`, `delivered`, `requeued`, `dropped`, per family, `unattributed`) and the
  passthroughs' secret counts.
- Off: one field test per read wrapper and per event or row; nothing is written and nothing allocated. On, the
  lines are Hekili's own `format` calls, which allocate as every Hekili debug line does.

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
  log to time the window", goes, and so does the interim `usable = usableNow( OVERPOWER )` the Warrior accuracy pass
  put in (its ruling A8). The event model is what would let Hekili recommend a swap into Battle Stance for
  Overpower before the usability read can say so (the client refuses Overpower outside Battle Stance); the accuracy
  pass deleted the swap settings (its A6), so restoring the swap is a later class-file choice, not this spec's. If
  the pairing misattributes another attacker's dodge in a group, the usability read in Battle Stance corrects it on
  the next reset.
- **Revenge.** The same handler records `enemy_revenge_trigger = GetTime()` on a row with `destGUID` ours and
  missType `DODGE`, `PARRY` or `BLOCK` (Classic's `misses`, `Classic/Warrior.lua:406-410, 447-448`); such a row
  exists only when attribution named the attacker (§2.4, decision 6);
  `reset_precast` applies `revenge_usable` only when Revenge is usable now (`IsUsableSpell` gates both branches in
  Classic, `Classic/Warrior.lua:633-638`, and the port keeps that gate through `reactive()`): for the remaining
  `trigger + 5 − now` when a trigger is under 5 s old, else 5 s, replacing today's usability-only window (`Forever/Warrior.lua:421-428, 507`).
- **Victory Rush** (Forever's, DB2 402927): `usable` stays the plain usability read (`Forever/Warrior.lua:1252`).
  A `PARTY_KILL` row with our `sourceGUID` is available if the file later models the window ahead; nothing in this
  spec requires it.

The fallback when attribution is impossible (no target `UNIT_COMBAT` within the window, or a hit on us no clock
claims): the usability flip of the reactive ability is itself the signal ([V] D8: an Overpower
`IsSpellUsable` false → true flip; it lagged a swing in O3, 4 flips after 34 melee no-rage swings). The layer does
not emit a row from the flip; the class file's "usable now" branch, on the strict `usable` return, covers it.

## 7. What this retires in Phase 1 code

| Phase 1 edit or write | After |
|---|---|
| The passthrough revert, 14 files (spec §7.7) | undone: file-top locals from `ns.Facade` (§1.2) |
| `UNIT_AURA` handler neutered (`Events.lua:1259-1263`) | the original body restored (§2.5) |
| `COMBAT_LOG_EVENT_UNFILTERED` skipped at `Events.lua:174` and `:197` | the original lines, with the first rows (phase B); the layer never registers it with the client (§2.1) |
| `CombatLogGetCurrentEventInfo` stay stub (`Facade.lua:491`) | virtual: the current row (§2.4) |
| The own-cast feeds `I.feed.CastSucceeded`, `CastStart`, `CastFailed`, `ChannelStart`, `ChannelStop` (`Adapter.lua:203-256`: `AddToHistory`, `QueueEvent`, `RemoveSpellEvent(s)`) | retired in the task that lands the own-cast rows; `CLEU_HANDLER` writes them (`Events.lua:1505-1601`). Both together would record each cast twice |
| The swing feed `I.feed.Swing` (`Adapter.lua:257-268`, `swings.*_actual`) | retired with the swing rows; `CLEU_HANDLER` writes them (`:1622-1635`) |
| The interim Overpower and Revenge windows from usability alone (`Forever/Warrior.lua:78-86, 388-395, 421-428, 507`) | Classic's event model plus the usability read (§6) |
| The drain's apply through the spec (`Adapter.lua` `readBefore`, `apply`, `readAfter`; the reset before and after; `I.pinned`; `I.Fold`'s `stopAtCast`) | retired by `now` handlers (§12a): a cast's effects come from the declared fields and the class file's `now`, never from replaying Hekili's `handler` through `state` |
| Drain step 5, `updated` from `AuraGen` (`Adapter.lua:452-456`) | kept: a layer-side write, so a belief that moved without a real `UNIT_AURA` (an own cast, a modelled expiry) still rescans in the same cycle (decision 2) |
| The APL warning scanner (Task 9b, `Virtual/State/AplWarnings.lua:65`, its `Hekili:LoadScript` call) | stays: target health and time to die are still secret or defaulted |
| GCD 61304 → 29515 (`Classes.lua:2469`, `UI.lua:1494, 1695`, `Events.lua:1670`, `Options/Options.lua:4043`), the spec 1491 loop break (`Classes.lua:3135-3136`), the talent read in `ns.updateTalents` (`Events.lua:424-435`) | moved into the facade by a named follow-up task of the plan (decision 7): the five GCD sites back to 61304, which `C_Spell.GetSpellCooldown`, `GetSpellInfo` and `GetSpellTexture` ask as 29515; the loop back to `if not id then break end`, `GetSpecializationInfo` answering an id-0 slot as nil; `ns.updateTalents` back to its `GetTalentInfoByID( v, 1 )` body, which the facade answers from the `C_Traits` walk. One line of that body stays Forever's: retail and Classic Hekili model talents as on or off and have no rank, so the facade's rank comes as a 12th return and the body stores it (`state.talent[ k ].rank`) |
| The drain call (`Core.lua:1570-1572`), `SpecChanged` (`Classes.lua:3355-3356`), the version gates | stay |
| (new, §12b) race packs and their cost modifiers in the simulation: `Races.lua` (`Hekili:NewRace`, `ns.costMods`), `ns.costMods.Wrap( a )` in RegisterAbility, `ns.costMods.Spend( cost, ability )` in `ns.spendResources`, `state.race_token` and `state.race[ <token> ]`; the class files in `Forever/Classes/`, race files in `Forever/Races/` | core edits kept on purpose: one declaration (`all.resourceMods`) read by the belief and by Hekili's simulation, so the recommendation and the belief pay the same cost |

## 8. Secret safety, performance and the drain

- The secrets policy is per class (decision 8). Event payloads never carry a secret to Hekili. A virtual read never
  returns the game's answer. A hybrid read tests its raw answer with `issecretvalue` (the first four values, or a
  table's time fields, after testing the table itself) and answers the model instead of any secret. A passthrough is
  raw and untested: it is used only where the evidence says plain, or where Hekili's use survives a secret; the trace
  counts a secret answer per name, and such a name becomes a hybrid. Every event slot passes `Plain`; every row
  holds plain values or layer constants; virtual reads keep spec §4.5's rules (`pcall` and `issecretvalue` before any field); the trace tests
  `issecretvalue` before storing. No layer code compares, indexes or does arithmetic on a value before that test,
  and none uses `a and b or c` on a possibly-secret value. The ported secrets spec (spec §11) gains the event
  facade's source files (`Virtual/Events/Rows.lua`, `Virtual/Events/Attackers.lua`); `EventFacade.lua` and `CombatLog.lua` read
  the client only through `Plain`-gated slots.
- Zero allocation in recurring paths (§4); everything is allocated at load, at `Start`, at `SpecChanged` or at a
  subscription. The trace, on, allocates as Hekili's own debug lines do (§5).
- The drain stays where it is (`Core.lua:1570-1572`, spec §5.1). The layer's frame does not drive Hekili:
  `Hekili.Engine`'s `OnUpdate` still starts cycles (`UI.lua:2370-2400`) and the urgent lane still only shortens
  the wait (`UI.lua:2459-2470`). CP1/CP2/CP4 2026-10-15 measured the drain at 0.1-0.5 ms, under spec §5.4's 1-2 ms
  estimate (G7 closed). Folding moves nowhere: the event facade adds receive-and-deliver work to event handlers,
  never a fold.

## 9. Testing

Headless (busted, `Virtual/State/spec/`, the Phase 1 helpers `fake_api.lua` and `alloc.lua`):
- `event_facade_spec`: a frame from the layer's `CreateFrame` on the fake api registers events and unit events, sets
  an `OnEvent` that captures; the fake game frame fires. Lifecycle: a subscription made before `VS.Start`, an
  event delivered before `Start` (sources skipped, no error), then `Start`: nothing is registered twice and the
  sources run from then on. Units: a player frame and a target frame subscribe to the same unit event, and each
  handler runs exactly once per firing. Re-entrancy: a subscriber that fires a client event from its handler gets
  correct payloads in both deliveries. A raising handler is counted and the next subscriber still hears the event;
  a frame unregistering itself mid-delivery does not disturb the loop. Asserts: only VirtualState's frame is
  registered with the fake client; the capture sees each event once, after the source handler (an order stamp); a
  `SECRET` proxy slot arrives nil; `UNIT_AURA` for the player or target arrives with the preallocated
  `{ isFullUpdate = true }`, for another unit with nil; `UnregisterEvent` stops delivery and drops the real
  registration when no source needs it; a third unit switches to a general registration with filtering; an unknown
  event becomes a stub; clearing `OnEvent` silences delivery; `COMBAT_LOG_EVENT_UNFILTERED` is never registered with
  the fake client; 10,000 events through the layer allocate 0 bytes.
- `cleu_rows_spec`: per emitted subevent, the tuple matches §2.4's slot table (no nil up to the last slot, the
  result of `ns.callHook`'s rebuild equal to the row, no event payload); `Facade.GetTime` answers a back-dated row's
  slot 1 during delivery and the clock after, and the delivery time for a modelled row; pairing in both event
  orders within `PAIR_WINDOW_MS`; an unpaired outcome dropped and an unpaired swing emitted at its own time once
  its window closes; an on-next-swing strike takes its swing's outcome; a row emitted during a delivery follows it,
  never nested, counted; a full pool drops the oldest, counted. Hits on us: credited to the one hostile targeting
  us; none and counted when nobody is known to, or `UnitIsUnit` is secret; two attackers told apart by their plain
  swing speeds, a hit off both clocks unattributed; a period learned from the gaps. 0 bytes per row.
- `adapter_spec`: the adapter writes no cast history, queue or swing field (the rows do); our casts' aura rows
  (APPLIED and REFRESH back-dated to the cast, REMOVED at the modelled expiry stamped at delivery) and energize.
- `trace_spec`: while `Hekili.ActiveDebug`, one `Hekili:Debug` line per read naming the answering class
  (`hybrid:raw`/`hybrid:model`), `GetTime` counted only, a secret written as `S` and counted for a passthrough, a
  line per event; off, nothing written and 0 bytes per read.
- `facade_spec`: inventory and classes equal `tools/api_inventory.txt`, each row with a reason; virtual rows never
  call the game; a passthrough is transparent (arguments, nine results, a secret); a hybrid answers raw while plain
  and the model once secret; a passthrough the client lacks is a virtual row answering nothing; the follow-up's
  Forever shapes (GCD spell, empty spec slot, talent rank).
- `alloc_spec` keeps its 10,000 mixed events and adds passthrough reads; with the rows in, its own casts' rows and
  aura rows ride along: 0 bytes.
- `tools/check_api_reads.sh` passes on the loaded files (§1.2).

The DevTools skeleton listener (`Options/DevTools.lua:1152-1159`) hears every row, modelled ones included, like any
`COMBAT_LOG_EVENT_UNFILTERED` subscriber (decision 9); a skeleton generated from them reflects the layer's
inference, and the provenance of each row is in the trace (§5).

In game (the user runs it; Warrior on a dummy):
1. `/reload`: no Lua error, no "Blizzard UI only" popup; `Snapshot()` reports `events ... errors=0 stubs=[]`.
2. Out of combat: `/hekili snapshot`, then the snapshot's log: VirtualState's `Snapshot()` heads it, and `[vs]`
   lines name each read's class; out of combat a hybrid answers `hybrid:raw`, in combat `hybrid:model`.
3. Arms in Battle Stance at a dummy (phase B): Overpower is recommended only after a floating DODGE, within one
   cycle, and not after the 5 s window or after Overpower is cast. A snapshot taken inside the window shows the
   rows' counters (`missed` grew) and the `overpower_ready` buff from the Warrior handler.
4. `UNIT_AURA` in combat: no error; Rend and Battle Shout still track (spec §11's checkpoint, unchanged).
5. Cast history (phase B): `prev_gcd` works and `Hekili.EData` shows `COMBAT_LOG_EVENT_UNFILTERED_1` with a per-row
   cost (`Events.lua:88-91`); each cast appears once in the history.
6. Swing clock (phase B): over 60 s on a dummy, `state.swings.mh_actual` matches the time of the `PLAYER_SWING`
   that produced it within 50 ms, both for paired swings and for unpaired ones emitted when their window closes.
7. The cycle cost with the full read facade against 75d71c8b (Hekili's thread time per frame), tracing off.
8. Phase B's two probes, first: `UnitAttackSpeed("target")` of a hostile in combat (plain or secret) and
   `UnitIsUnit("targettarget", "player")` in combat (plain or secret), and the pairing gap (§3).

## 10. Risks with closers

| # | Risk | Closer |
|---|---|---|
| E1 | Row wrappers slow hot reads (`GetTime`, `UnitExists` in the cycle; a hybrid adds a raw call) | in-game step 7; if the cycle grows by more than 5 %, the user decides between keeping the always-on wrapper (decision 4) and giving the hottest names the raw function |
| E2 | A frame Hekili does not create through the facade registers events directly (a library, an XML template, a metatable call) | `check_api_reads.sh` greps the loaded files (§1.2); libraries are not Hekili core and keep their own frames |
| E3 | Victim-side outcomes misattributed in groups (another attacker's dodge credited to our swing; a hit on us credited to the wrong attacker) | pairing within `PAIR_WINDOW_MS` only (§3); hits on us credited only by a clock within `ATTACK_TOLERANCE` or to the one hostile targeting us (§2.4), else no row; rows marked inferred; in Battle Stance the strict usability read corrects Overpower on the next reset (§6) |
| E4 | Own-cast and swing writes doubled while the Phase 1 feeds and the rows coexist | retire each feed in the same task as its rows (§7); in-game step 5 and a headless count of `AddToHistory` calls |
| E5 | Hekili's dispatch allocates per delivered row (`Events.lua:84, 88-91`) | Hekili's retail cost; measured per row in in-game step 5; rows are emitted only for §11's families |
| E6 | Registering an event the client does not know raises | `pcall` at subscription; stub entry (§2.1) |
| E7 | A row delivered inside a hook is dropped by `ns.callHook` (`Classes.lua:2869`) | no nested delivery; queued and counted (§3) |
| E8 | `UNIT_AURA` fires often in combat (O12: 226 firings), each a full rescan request | `ForceUpdate(…, true)` only adds 0.1 s to the refresh timer (`UI.lua:2459-2461`); the scrape still runs once per cycle |
| E9 | Gated payloads change a handler's input (nil instead of a secret) | the only handlers that received secrets are the target arms of `UNIT_SPELLCAST_*`, which read neither slot (`Events.lua:1017`, `:1029`); the trace shows any other |
| E10 | A deferred row's time skew shifts a time-stamping consumer: the swing clock (up to `PAIR_WINDOW_MS`) or `trackDebuff` (up to one cycle) | every row with an observed basis is back-dated (§3, decision 5: slot 1 plus `Facade.GetTime` during delivery), checked by in-game step 6; modelled expiries are stamped at delivery |
| E11 | A passthrough name is secret in some state nobody probed | the trace counts secrets per passthrough (§5); the name becomes a hybrid row |
| E12 | A hybrid's raw answer out of combat and its model's in combat disagree at the edge (a cooldown read raw just before combat, the model's right after) | the model is seeded from the same plain reads (spec §4); the checkpoint's snapshot shows both classes answering (step 2) |
| E13 | `UnitIsUnit("<token>target", "player")` or a hostile's `UnitAttackSpeed` is secret in combat | each goes through `Plain` and its status is noted (`Snapshot()`'s `read UnitIsUnit target-of`, `read UnitAttackSpeed hostile`); secret targeting means no row on us (the Revenge fallback, §6); a secret speed means a learned period (§2.4); phase B's probes measure both first |

## 11. Phasing

Each phase ends in game; the order follows Phase 2's ranking of silent damage (Phase 2 §2.1: cast history, enemy
count, swing clock, debuff tracking, damage taken), with this session's facts standing in for the Phase 2 probes
they answer (G2 order, drain cost, the plain signals of §1.1).

- **A. The full facade.** `Facade.CreateFrame` and the event facade with every event passthrough but
  `UNIT_AURA` (the layer's full update, the original handler restored); the read facade over all names in three
  classes and the file-top locals; the tools; the trace through Hekili's snapshots. No rows yet. In game: steps 1,
  2, 4, 7.
- **B. Own casts, swings, avoidance and hits on us (the Warrior's).** The row pool, queue and delivery with
  back-dating; own-cast rows; swing rows and our abilities' outcomes paired within the window; hits on us with the
  targeting set and the attacker clocks; our casts' aura rows and energize from the `now` family's writes (§12a);
  the Phase 1 feeds retired; the `COMBAT_LOG_EVENT_UNFILTERED` skip reverted; the Warrior file in Classic's shape
  (§6). This phase answers the user's example. Its checkpoint starts with the two probes
  and the pairing gap (step 8), which set `PAIR_WINDOW_MS` and confirm the attribution's inputs; then steps 3, 5, 6.
- **`now` handlers (§12a).** After phase B's rows: a cast's effects from the class files' declared now-state; the
  drain's replay of Hekili's sim handlers retired; the Warrior's `now` lines with its windows.
- **The follow-up (decision 7).** The GCD spell, the spec slot and the talent read move into the facade (§7).
- **C. Deaths, damage on other units, the believed `UNIT_AURA` lists.** `UNIT_DIED`/`PARTY_KILL` rows to
  `ns.eliminateUnit`; WOUND rows on plates for enemy counting; `UNIT_AURA` with the believed added, updated and
  removed lists (decision 2).
- **D. Our debuffs on the target, refined.** Travel time, the compensating removal on an avoided cast. Feeds
  `active_dot` and `cycle_targets`.

Phase 2's remaining probes (the dodge window in ms, the `UNIT_AURA` key pattern, the `UNIT_DIED` range,
IMMUNE/RESIST) are run inside the phase that needs them, not as a separate phase.

## 12. Out of scope

- Summons, friendly HoTs, empower casts (`SPELL_EMPOWER_END`).
- Rows for other units' casts and auras (identity secret, O4), absorbs, overkill.
- `UNIT_AURA` depth 2 (incremental payloads from `AuraGen` diffs, Phase 2 §5).
- Moving the fold out of the drain; persistence across `/reload` (spec §14, G5).
- Facading frames and events of embedded libraries (`Libs/`).
- The stance swap into Battle Stance for Overpower (§6).

## 12a. `now` handlers (approved 2026-10-15)

The belief stops learning a cast's effects by replaying Hekili's sim `handler` through `state` and diffing (the
Phase 1 drain's reset, apply, read-before/read-after, reset). A class file declares instead, beside `handler`, what
the cast does to the now-state:

```lua
charge = {
    ...,
    now = function ()
        gain( ( CHARGE_RAGE[ knownRank( CHARGE ) ] or 9 ) + 3 * talent.improved_charge.rank, "rage" )
        applyDebuff( "target", "charge_stun" )
    end,
    handler = function () ... end, -- sim only; shares the same constants (upvalues)
},
```

- **Environment.** Hekili's `RegisterAbility` setfenv's every function field to `state` and keeps a non-protected one
  in `ability.funcs` (`Classes.lua:784-793`), where reading `ability.now` would call it; VirtualState reads it raw
  (`rawget(ability.funcs, "now")`) when the tracked set is built and setfenv's it to one shared context table.
  Upvalues are untouched, so the file's constants serve both functions. The context carries Hekili's verbs with belief
  meanings and Hekili's own signatures (`State.lua`), so a Classic handler's lines port by copying (the user's ruling
  of 2026-10-15, superseding the design brief's shorthand): `gain(amount, resource)`, `spend(amount, resource)` →
  `I.ResourceShift`; `applyBuff(aura, duration, stacks)`, `applyDebuff(unit, aura, duration, stacks)`,
  `removeBuff(aura)`, `removeDebuff(unit, aura)`, `addStack(aura, duration, stacks)` → `I.AuraModel`;
  `setCooldown(action, duration)` → `I.CooldownModel`. A `gain` or `spend` naming no tracked resource (or none) is
  an error counted like a raised `now`, with no write: the layer never guesses a resource. A missing duration takes the aura's registered number; an aura whose duration is a function needs
  the `now` to pass one. Reads: `talent.<key>.rank`/`.enabled`, `buff.<key>`/`debuff.<key>` (`up`, `down`, `remains`,
  `stack`, `count`, `expires`, `applied`, at the cast's time), `<resource>.current`/`.max`, `knownRank(ids)` (the
  belief's spellbook, `VS.KnownRank`), `now` (the cast's belief time), `combat` (the combat start), and Lua's pure
  helpers (`math`, `min`, `max`, `floor`, `ceil`, `abs`, `type`, `select`, `tonumber`, `error`). Every proxy is built
  at SpecChanged: no allocation per call. Nothing else is reachable: no game API, no Hekili state; a file-local helper
  a `now` calls runs in the file's own environment, so it takes what it needs as arguments. `.luacheckrc` declares
  the names (`nowEnv`).
- **Writes.** Writes are live only while a cast's `now` runs: Hekili keeps `now` in `ability.funcs`, where DevTools'
  `RunStressTest` (`Options/DevTools.lua:140`) or an APL reading `action.<x>.now` (`State.lua:5076`) can call it, and
  such a call writes nothing. Every write is a `modelled` sample at the cast's belief time (the fold's lagged time when lagged); by
  `I.Basis` (newest by time, ties observed > pinned > modelled) any later read overrides it. The aura verbs also
  write the combat log's aura rows, `gain` the energize row (§2.4, back-dated to the cast).
- **Trigger.** `Virtual/State/Families/Now.lua` registers on `CastSuccess` only (a channel stages both
  `ChannelStart` and `CastSuccess`; the user's ruling: one run, never two), after the Resources family's ladder pin
  for the same observation, and writes for ability a at t, unless a is a `track_<id>` extra (`VS.Track`: no ability,
  no effects): (1) the cost, `I.ResourceShift(slot,
  -I.CostOf(a), t)` (an on-next-swing strike keeps paying at its swing); (2) the declared `cooldown` through
  `I.CooldownModel`, or a charge through `I.ChargesModel`, and the GCD through `I.GcdModel` (a hard cast's GCD began at
  its start, written only while it still runs); (3) `now`, if declared, under `pcall`: an error is counted
  (`I.nowErrors`, `Snapshot()`'s `errors=`) and the fold goes on.
- **The drain** becomes: flush, polls, fold (no stop at a cast), settle, and Hekili's rescan flags from `AuraGen`.
  `I.drainCasts` counts the casts folded. Hekili's `state` is never reset or replayed by VirtualState. The Phase 1
  feeds into Hekili's cast history and queue are already gone (§7: the combat-log rows write them).
- **The Warrior.** `now` on Charge, Bloodrage, Berserker Rage, Rend, Sunder Armor, Thunder Clap, Hamstring,
  Demoralizing Shout, Piercing Howl and the three stances, each sharing its constants with its sim handler. The
  file's `knownRank` reads `VS.KnownRank`, so it answers the same in both environments; Tactical Mastery, a passive,
  is tracked so the spellbook knows it.
- **Out of scope** (later, with phase C's observation kinds): non-cast triggers (the dodge, a kill, an aura tick) as
  `spec:RegisterNow(kind, fn)` with the same context. Version 1 is cast success only.
- **Tests** (`Virtual/State/spec/now_spec.lua`): `gain` shifts est, lo and hi as a modelled `CastSuccess` sample;
  `applyDebuff` lands as a modelled target expiry with stacks, which a later read overrides and an earlier one does
  not; an ability without `now` changes only cost, cooldown and GCD; a raising `now` is counted and the fold goes on;
  zero allocation over 1000 casts; a `now` calling `gain` never touches `state.rage`; the reads through the context;
  the aura and energize rows.

## 12b. Race packs and resource modifiers (approved 2026-10-15)

Racials are race content, not class content: one file per race that has Forever-specific racials, registered for
every class, and two declarative fields of a resource definition that talents and class auras can use too. The
user's design (race packs) supersedes a registration in the shared `all` spec with a per-class scope table.

- **Layout.** `Forever/Classes/Warrior.lua` (moved from `Forever/Warrior.lua`; `Forever/spec/` stays where `.busted`
  finds it, its loader's path follows) and `Forever/Races/Gnome.lua`. The TOC lists every race
  file unconditionally, after the class files. Races with only Hekili's stock racials (Berserking, Blood Fury,
  Stoneform, Shadowmeld, Will to Survive) stay in the shared `all` spec; moving them is cosmetic and out of scope.
- **Race token** (named core edit, `State.lua`): at load the core reads UnitRace once; the second return, the
  locale-free token, goes into `state.race_token`, and `state.race[ <token, formatKey'd> ] = true` holds beside
  Hekili's localized key.
- **`Hekili:NewRace( token )`** (`Races.lua`, new core file after `State.lua`) returns a registration object that
  mirrors the spec API: `race:RegisterAbility( key, def )`, `race:RegisterAura( key, def )` (both into the shared
  `all` spec, over `all`'s own entry for the key), `race:RegisterResourceMod{ max = pct }` (every resource the loaded class registered) and
  `race:RegisterCostMod{ aura = key, pct = n | flat = n, charges = k|nil, spells = { spell IDs }|nil }`. For a race
  that is not the player's, every call is accepted and inert: the file runs unconditionally and loads headless.
- **A race wins a key clash.** Hekili's `SpecializationChanged` merges the class's spec first and `all` last and only
  adds keys still missing, so a race entry in `all` would lose to a class entry under the same key. `Races.lua` keeps
  the keys the live race registered (`copy` aliases included), and `ns.applyRace( class )`, one named call after the
  merge loop, writes them over `class.abilities` and `class.auras`: the race's registration overrides both the
  class's and `all`'s own entry for that key.
- **The Gnome's pack.** Eureka! (1259813, the other classes' 1259812, 1259817, 1259821, 1259823 as `copy`; 120 s, off
  the GCD; its handler and its `now` apply `eureka` for 15 s with 3 stacks) and its aura; Expansive Mind
  (`{ max = 0.05 }`); Eureka!'s cost modifier `{ aura = "eureka", pct = -0.10, charges = 3, spells = { ... } }`.
  A cost-modifier aura is spell-family masked in the DB2, so the entry lists the abilities it covers: Eureka!
  1259813's effect 0 masks are 1784679630 / 5 / 1 / 0 against the Warrior's SpellClassSet 4, which covers Heroic
  Strike, Cleave, Slam, Execute, Overpower, Mortal Strike, Bloodthirst, Whirlwind, Shield Slam, Revenge, Thunder Clap,
  Hamstring, Intercept, Mocking Blow, Pummel, Shield Bash and Spearing Strike, by the class file's rank-1 IDs, and
  not Rend, Sunder Armor, the shouts, Concussion Blow, Death Wish, Disarm, Retaliation, Shield Block or Sweeping
  Strikes. Another class appends its IDs from the wowdb query the file's comment gives. Clearcasting is masked the
  same way (on Forever it excludes Wrath, Thrash and Savage Roar), so a class's own entry lists `spells` too; an
  entry without `spells` means every ability paid from the resource.
- **`maxMods`** (`{ pct = n, when = fn|nil }`): the maximum is the declared `max` (a number or a state-bound function,
  default 100) × Π(1 + pct) over the holding modifiers. One evaluator, the Resources family's `maxOf`, applies it at
  the build (so the interval's upper bound is seeded at the raised maximum) and at each CombatEnd, until a plain
  maximum read arrives, which wins for good. A percentage maximum modifier never applies to a point resource
  (combo points, runes, soul shards, holy power, chi, arcane charges, essence): the adapter leaves `maxMods` off them.
- **Scope.** A modifier with `spells` covers the abilities whose `id` or a `copy` rank is listed; one without `spells`
  covers every ability paid from the resource. Both layers read the scope the same way.
- **Charges follow the declared cost.** A charged modifier takes a stack from a cast in scope whose declared (base)
  cost is above 0, even when the discount brought the paid cost to 0 (`pct = -1, charges = 1` is Clearcasting's
  shape); a cast with no declared cost takes none. Both layers gate on the declared cost, never on the discounted one.
- **`costMods` in the belief.** `spells` resolve at the build to ability indices through the tracked abilities' ids
  and `copy` ranks; an ID the class does not register is absent (no error); zero allocation per cast. `I.CostOf(a)`
  applies every modifier in a's scope whose aura is believed up on the player at the belief time (`pct` multiplies,
  `flat` adds, floored at 0), so the usability ladder's pin and the `now` family's automatic cost step (§12a) pay the
  modified cost. With `charges`, each in-scope cast with a declared cost spends one believed stack (a modelled
  sample), which goes at 0; an observed aura read still wins by the basis rule. Out-of-scope casts get no discount and take no charge.
- **One declaration, two readers** (named core edits). The simulation reads the same `ns.raceMods`, never
  per-ability code in a class file: `Races.lua` wraps every ability's `spend` when RegisterAbility builds it, so every
  reader of `ability.spend` (`action.<x>.cost`, `ns.hasRequiredResources`, `state:TimeToReady`,
  `ns.spendResources`) gets the declared cost through the modifiers in the ability's scope whose buff is up in
  Hekili's `state` (a fraction-of-maximum cost takes the same `pct`, as in the belief); `ability.baseSpend` keeps the
  declared cost for the belief, which applies the modifiers itself. `ns.spendResources` then, given the declared cost,
  takes one stack of each charged in-scope modifier's buff (`state.removeStack`). Not a `spend` hook: `state.spend` also runs for spends that are no ability's cost (a stance
  swap's lost rage), which must take no charge.
- **Tests** (`Virtual/State/spec/races_spec.lua`, `modifiers_spec.lua`): the Gnome file inert for another race;
  registered for the Gnome, winning a key clash with `all` and, after the merge, with the class; max 105 through the
  modifier with the interval seeded at it, a plain read winning, a point resource left at its own maximum; Heroic
  Strike at 13.5 with Eureka! up and a charge per cast, Rend at 10 and no charge, in the belief and in the simulation;
  a listed `copy` rank matching; no `spells` covering every ability, in both layers; `pct = -1, charges = 1` spending
  its charge on the free cast, in both layers; a fraction-of-maximum cost taking the pct; an unknown ID ignored; an
  observed aura read winning over modelled charges; zero allocation over 1000 casts.

## 13. Decisions taken (2026-10-15)

The user settled all nine; each is a rule in the section named.

1. **Diversion at frame creation** (§2.1): `Facade.CreateFrame` shadows the event methods, so `ns.RegisterEvent`
   and friends stay as written, and the UI, dev-tool and boot frames are subscribers too.
2. **Every event intercepted, Hekili cannot tell** (§2.1, §2.2): real or modelled, each event reaches Hekili in the
   game's name and shape through one path. `UNIT_AURA` is the layer's full update in phase A and the believed lists
   in phase C; drain step 5 stays (§7).
3. **The trace through Hekili's debug and snapshot facility** (§5): `Hekili:Debug` lines into the snapshot while
   `Hekili.ActiveDebug`, `Snapshot()` at the head of each display's log; no ring, no command.
4. **Every row wrapped, one branch** (§1.1): the trace's test in every row's wrapper; E1 measures the cost.
5. **Time as accurate as possible** (§3): a row with an observed basis carries the observed time in slot 1 and is
   back-dated on delivery; a purely modelled row is stamped at delivery; the basis per row family is §3's table.
6. **Attribution of hits on us** (§2.4, §6): the set of hostiles targeting us (`UNIT_TARGET` and the target,
   focus and plate tokens, `UnitIsUnit("<unit>target", "player")`) and a swing clock per attacker (`UnitAttackSpeed`
   when plain, else learned from the gaps between hits on us while one hostile targets us); a hit goes to the
   attacker whose clock predicts it within a tolerance, else it is unattributed and makes no row. Our own swings'
   dodges and parries keep the pairing window. Phase B's checkpoint probes both inputs first.
7. **The three remaining core edits move into the facade** (§7): a named follow-up task of the plan, after phase
   A (the plan runs it after phase B's tasks).
8. **Three classes per name** (§1, §8): passthrough, hybrid, virtual, each classified from its evidence; the trace
   names the class that answered.
9. **The dev-tools listener hears modelled rows** (§9), their provenance in the trace.

Approved with them (2026-10-15): **`now` handlers** (§12a), which retire the drain's replay of Hekili's sim handlers,
and **race packs with resource modifiers** (§12b).
