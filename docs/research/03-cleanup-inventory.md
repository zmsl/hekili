# R3: Cleanup and rearchitecture inventory (stage 1 input)

Source examined: `.claude/worktrees/forever-research` at `36daec38` (final retail TWW code, TOC `## Interface: 110205`).
Line references are against that tree. The sibling API inventory (`01-api-inventory.md`) did not exist when
this was written, so API availability claims below come from my own `wow` MCP spot checks (flavor `forever`) and
should be cross-checked against it.

---

## Summary

- The addon is about **151k lines of Lua** that we wrote ourselves (libraries not counted). The engine core is
  about **28.6k lines** (`State.lua` 8,099 · `Classes.lua` 4,430 · `UI.lua` 3,201 · `Events.lua` 2,773 ·
  `Core.lua` 2,317 · `Scripts.lua` 2,197 · `Targets.lua` 1,604 · the rest under 1.1k each). Options add another
  12.7k. **About 106k lines (around 70%) are deletable content**: about 17.3k in expansion folders, plus 89k in
  `TheWarWithin/`, of which 22.9k are retail-only classes and 62.9k are the 23 Forever-class TWW spec modules.
  None of those spec modules is valid for a vanilla-1.6 ruleset.
- **Blocker found: the checkout does not load as-is.** `Libs/` holds only `SpellFlashCore`. Every other library
  is a packager external listed in `.pkgmeta`, and `embeds.xml` includes them (`embeds.xml:2-27`). The symlinked
  main checkout `~/src/hekili/Libs` has the same gap. Without the libraries, `Hekili.lua:5` (`LibStub(...)`)
  errors on load. Stage 1 step 0 is to vendor or fetch the libraries.
- **Second blocker: build gates invert on Forever.** `Hekili.CurrentBuild` is the 4th return of `GetBuildInfo()`
  (`Hekili.lua:15-17`), which is the interface number (most likely 16001 on Forever). As a result:
  - `IsDragonflight()` and `IsTWW()` are false.
  - `Dragonflight/Classes.lua:7` exits early. That file is where the C_Traits-based `ns.updateTalents` lives.
  - `TheWarWithin/Classes.lua:7` exits early.
  - `Core.lua:203` raises a "future version" warning.
  - `NewSpecialization` uses `IsRetail()`, which comes from TOC `X-Flavor` metadata (`Hekili.lua:7`, `Classes.lua:1377`).

  Every version gate needs to go. The engine should be Forever-only.
- **CLEU is load-bearing.** `Events.lua:1709-2016` (`CLEU_HANDLER`) is the only source of:
  - real cast history (`state:AddToHistory`, which feeds `prev`, `prev_gcd`, `action.X.lastCast`)
  - swing timers
  - damage-based target counting and unit elimination on death
  - DoT and snapshot tracking (`ns.trackDebuff`)
  - incoming-damage samples (`ns.storeDamage`)
  - 33 spec modules' `RegisterCombatLogEvent` hooks

  On Forever the event is still documented (`COMBAT_LOG_EVENT_UNFILTERED`), but `CombatLogGetCurrentEventInfo`
  is "not documented". It is removed on Midnight retail. Stage 1 should cut CLEU out behind a seam and reroute
  history and swings to `UNIT_SPELLCAST_SUCCEEDED` and `PLAYER_SWING`. Both are documented on Forever.
- **Secret-value hot spots** are concentrated in a few places, which makes a "game data source" layer realistic:
  - `state.reset` (powers, health, totems, swing speed)
  - `ScrapeUnitAuras`
  - `mt_default_cooldown`
  - `UNIT_POWER_FREQUENT` and `UNIT_AURA` handlers
  - Targets/TTD (`UnitHealth`)
  - UI cooldown and delay math

  Forever exposes `issecretvalue()` and a full `C_Secrets.Should*BeSecret` predicate family. That makes the layer
  testable at runtime.
- **Recommended stage 1:** 9 ordered steps (below). Each one leaves a loadable addon. They end at TOC 16001, no
  Lua errors on `/reload` on a Druid, no non-Forever content, an empty spec registry (Feral comes in stage 2), and
  luacheck and LuaLS clean.

---

## Findings

### 1. Engine map

#### 1.1 Load order (TOC)
`embeds.xml` (Ace3, LSM, LibRangeCheck, LibSpellRange, LibDualSpec, LibCustomGlow, etc.)
→ `Hekili.lua` (AceAddon object, flavor/build predicates, debug)
→ `Utils.lua` (aura wrappers, `ns.UnitBuff/UnitDebuff`, talent export string, covenant cache)
→ `Formatting.lua` and `MultilineEditor.lua` (APL editor widgets)
→ `Constants.lua` (resource enum map, the `ns.Specializations` table for all 39 retail specs, `ns.HeroTrees`, target dummies)
→ `State.lua` (the simulated state table and all its metatables)
→ `Events.lua` (event bus, game event handlers, keybinding scraper)
→ `Classes.lua` (class/spec registration API, shared `all` spec 0 auras and abilities, potions, trinkets, PvP gear, `SpecializationChanged`)
→ expansion item/system files (TBC through TWW)
→ `TheWarWithin/*` spec modules
→ `Targets.lua`
→ `Options/DevTools.lua`, `Options/ChatCommands.lua`, `Options/Options.lua`
→ `UI.lua`, `Scripts.lua`, `Core.lua`.

#### 1.2 Data flow

```
GAME ──events──► Events.lua handlers ──► state flags / ns caches / ForceUpdate()
  │                 PLAYER_ENTERING_WORLD → SpecializationChanged (Classes.lua:4091)
  │                 talent/gear events    → ns.updateTalents / ns.updateGear (Events.lua:416, 709; DF/Classes.lua override)
  │                 UNIT_AURA             → instance DB, state[unit].updated = true (Events.lua:1513)
  │                 UNIT_POWER_FREQUENT   → tick-rate learning, ForceUpdate on spend (Events.lua:1400-1460)
  │                 UNIT_SPELLCAST_*      → ForceUpdate, hold removal, cast/channel queue (Events.lua:1220-1393)
  │                 CLEU                  → history, swings, targets, dots, damage (Events.lua:1709-2016)
  │                 NAME_PLATE_*          → nameplate unit maps (Targets.lua:240-263)
  │
  ├──pull (per update)──► Hekili.Update() coroutine (Core.lua:1561), driven by Hekili.Engine OnUpdate (UI.lua:2377-2440)
  │      ├─ Hekili:GetNumTargets(true) → ns.getNumberTargets (Targets.lua:385): nameplates + range + CLEU-seen GUIDs + pet-based
  │      ├─ per display (Interrupts → Defensives → Cooldowns → Primary → AOE):
  │      │    state.reset(dispName, full)  (State.lua:6787-7136)
  │      │       ScrapeUnitAuras(player/target)      ← C_UnitAuras.Get{Buff,Debuff}DataByIndex   (State.lua:5956)
  │      │       class.stateTables onReset
  │      │       GetTotemInfo(1..5)                  ← totems/pets
  │      │       UnitPower/UnitPowerMax/GetPowerRegenForPowerType/GetManaRegen  ← resources + forecast
  │      │       UnitHealth/UnitHealthMax, UnitAttackSpeed, swing estimates
  │      │       buff.casting (UnitCastingInfo/ChannelInfo) → queue CAST_FINISH/CHANNEL_TICK, advance clock
  │      │    lazy reads via metatables while the APL evaluates:
  │      │       cooldown.X.*   mt_default_cooldown → C_Spell.GetSpellCooldown / GetSpellCharges / LoC cooldown (State.lua:3283-3500)
  │      │       buff/debuff.X  → scraped aura tables, ns.trackDebuff data
  │      │       talent.X       → state.talent (populated by updateTalents)
  │      │       target.*       → UnitHealth / UnitCanAttack / range libs / TTD (mt_target, State.lua:3100)
  │      │       active_enemies → ns.getNumberTargets result
  │      │    Hekili:GetPredictionFromAPL (Core.lua:695) → Scripts compiled closures (Scripts.lua:1423 ConvertScript)
  │      │       → state:IsReady / TimeToReady (State.lua:7831-8034) → runHandler, advance → next slot
  │      └─ writes UI.Recommendations[i]
  │
  └──UI──► display OnUpdate (UI.lua:1108) renders icon/keybind; RefreshCooldowns (UI.lua:1700) re-reads
           GetSpellCooldown / UnitCastingInfo for the swipe and does arithmetic on it; glow (IsSpellOverlayed),
           range (LibRangeCheck / LibSpellRange), usability (C_Spell.IsSpellUsable).
```

**APL path.** SimC text is stored as compressed packs (`spec:RegisterPack(..., [[Hekili:...]])`, for example
`TheWarWithin/DruidFeral.lua:3106`). It is decoded into `profile.packs` and compiled by `Scripts.lua`
(`SimToLua` at 349, `ConvertScript` at 1423) into Lua closures that index `state`. **Every APL comparison
(`energy>=50`, `buff.x.remains<3`) is plain Lua arithmetic on what the `state` metatables return.** If any
metatable passes a secret through, the comparison errors in tainted code. This is why the data-source boundary
has to sit in `state.reset` and the `mt_*` metatables, not in the APLs.

#### 1.3 What gets read where (API hit counts, core files)
- `State.lua`: UnitExists 19, UnitIsUnit 16, UnitHealth/Max 20, UnitCanAttack 9, GetTotemInfo 9, UnitPower/Max 7,
  GetShapeshiftForm 6, GetCombatRating 6, UnitStat 5, UnitAttackSpeed 5, GetSpellCharges 4, IsSpellKnown*
- `Events.lua`: GetBindingKey 27, GetActionInfo 25 (keybind scraper), CLEU 1, Azerite/Essence APIs (dead), GetTalentInfoByID, GetPvpTalentInfoByID
- `Targets.lua`: UnitGUID/Exists/Name/Health, UnitInPhase/PhaseReason, C_PvP.IsWarModeDesired, C_PlayerInfo.IsPlayerInTimerunningHeroicWorldTier
- `UI.lua`: C_Spell.GetSpellCooldown (with arithmetic), UnitCastingInfo, IsSpellOverlayed, LibRangeCheck/LibSpellRange, IsUsableSpell
- `Utils.lua`: C_Traits/C_ClassTalents (loadout export), C_TooltipInfo.GetConduit, aura-by-index wrappers

### 2. Removal inventory

Effort: S = under 1h, M = half a day, L = 1 day or more. Risk is "chance of breaking load or engine behaviour".

#### 2(a) Non-Forever content

| # | Item | Path(s) / symbols | Lines | Effort | Risk | Dependencies / order |
|---|---|---|---|---|---|---|
| A1 | Retail spec modules (all 39) | `TheWarWithin/*.lua` minus `Classes.lua` and `Items.lua`, plus `TheWarWithin/Warrior/ReflectableSpells.lua` | 85,794 (DK/DH/Monk/Evoker 22,902; the 9 Forever classes 62,892) | S (TOC + delete) | Low. Modules self-gate on `UnitClassBase` and only touch `class`/`state` via the registration API | First removal. Keep `DruidFeral.lua` **out of the TOC but in git history** as a stage-2 reference (`git show 36daec38:TheWarWithin/DruidFeral.lua`). |
| A2 | SimC priorities | `TheWarWithin/Priorities/*.simc` (39 files) | 5,305 | S | None (not loaded) | With A1. Keep `DruidFeral.simc` in history as a reference. |
| A3 | TWW shared | `TheWarWithin/Items.lua` (TWW trinkets/consumables), `TheWarWithin/Classes.lua` (M+ dungeon spell-filter table for interrupts/reflect) | 1,929 + 1,431 | S | Low. `Classes.lua` exits early on Forever anyway | With A1. The spell-filter *mechanism* (`class.spellFilters`) could later be reused with Forever dungeon data. Keep the consumer and drop the data. |
| A4 | BfA | `BfA/AzeritePowers.lua`, `Essences.lua`, `Items.lua` | 5,692 | S | Medium. `state.azerite`/`state.essence`/`bfa_essence` metatables (`State.lua:95-96, 4491-4554`), `ns.updatePowers`/`updateEssences` (`Events.lua:493, 608, 1033-1058`), `Hekili:IsEssenceScripted` (`Scripts.lua:1800`), `heart_essence` ability (`Classes.lua:3407`), `essences` toggle (`State.lua:3015, 7556, 7622`, Options) | Delete the files, then strip the consumers in the same commit. Make the `state.azerite`/`essence` tables return default 0/false through a stub metatable at first, then remove the stub in C3. |
| A5 | Shadowlands | `Shadowlands/AnimaPowers.lua`, `Covenants.lua`, `SoulbindConduits.lua`, `Trinkets.lua`, `Legendaries.lua` | 6,602 | S/M | Medium. `ns.WipeCovenantCache` / `IsDisabledCovenant` / `AreCovenantsDisabled` (`Utils.lua:866-869`, `State.lua:34, 7436`, `Events.lua:38`, `Classes.lua:4404`), `state.legendary`/`runeforge` (`State.lua:126-127, 4486, 5033`), `C_Soulbinds` in Options, `C_TooltipInfo.GetConduit` in Utils | Same pattern as A4. |
| A6 | Dragonflight | `Dragonflight/Items.lua` (2,320), `Dragonflight/Classes.lua` (85) | 2,405 | S | **High for `DF/Classes.lua`**. It installs the C_Traits `ns.updateTalents` and the `mt_generic_traits` talent metatable. It is currently dead on Forever because of the `IsDragonflight()` gate. | Do not just delete. Fold whatever talent model we keep into the engine (see B1). |
| A7 | Legion, TBC, Wrath, Cata items | `Legion/Items.lua` 522, `TheBurningCrusade/Items.lua` 47, `Wrath/Items.lua` 59, `Cataclysm/Items.lua` 28 | 656 | S | Low | These are retail-client timewalking/legacy trinkets, not vanilla. Delete. Revisit whether any vanilla-era trinkets are wanted (they would be new Forever data, not this). |
| A8 | Retail-only class data in core | `Constants.lua:103-300` (`ns.Specializations` for 39 specs), `Constants.lua:310-550` (`ns.HeroTrees`, `getActiveHeroTreeName`), `State.lua:140` (`state.hero_tree`), `State.lua:4989-5027` (hero-tree set-bonus matching), `Constants.lua:697+` `SkeletonTalentEnhancements` | ~700 | M | Medium. Spec IDs drive `profile.specs[...]`, options, and `NewSpecialization` | Reduce to the 9 classes. **The spec-ID question (Q1) must be answered first.** |
| A9 | Shared retail auras/abilities in `Classes.lua` | `all:RegisterAuras` block `Classes.lua:1472-2724`: TWW M+ affixes, SL S3, WoD legendaries, DF/TWW potions (about line 2686), Bloodlust variants. Also racials `2885-3380`, `heart_essence` 3407, PvP medallion/badge/emblem/insignia `3439-3706`, 8.3 corrupted on-use `3707-3785`, holiday items `3786-3910` | ~2,400 of 4,430 | M | Medium. APLs and the engine reference `bloodlust`, `potion`, `use_items`, `casting`, `gcd` and others | Keep the engine-required shared auras (`casting`, `movement`, `bloodlust` family, `potion` framework, `use_items`). Remove the rest. Racials: keep the vanilla race set only. |
| A10 | Legion Remix / Timerunning | `Targets.lua:323-348` (`TimerunningCheck`, `UnitInPhase` reason 4), `Events.lua:1738-1741` | ~30 | S | Low | Anywhere. |
| A11 | Retail world checks | `Targets.lua:290-320` (Chromie Time, War Mode), PvP talents (`Events.lua:440-460`, `class.pvptalents`, `state.pvptalent`, `RegisterPvpTalents`), arena prep (`Events.lua:392`), M+ affix auras | ~150 | S | Low | With A8/A9. |
| A12 | Empower (Evoker) machinery | `Events.lua:1257-1292` (`UNIT_SPELLCAST_EMPOWER_*`), `state.empowerment`, `UI.lua` empowerment glow (~1737), `ability.empowered` paths in `Core.lua` and `State.lua` | ~200 | M | Low/Medium (scattered conditionals) | After A1. Do it with grep and keep it optional (it can be left inert). |
| A13 | Retail options | `Options/Options.lua` essences/covenant/soulbind toggles (19 refs), SimC importer (`3755-3925`) is still useful, Wago/Discord/patron text (`Hekili.lua:56-59`), `Options/Archive.lua` | 10,128 total; ~500 removable now | M | Medium (AceConfig tables are fragile) | After A4-A9. `Options/Archive.lua` (677) is **not in the TOC** and nothing references it. Delete immediately. |
| A14 | One-time profile migrations | `Options/Options.lua:44-126` (`oneTimeFixes`) | ~80 | S | Low. A fresh SavedVariables on Forever means nothing to migrate | Replace with an empty table. Consider renaming `SavedVariables: HekiliDB` to avoid importing retail profiles (Q6). |
| A15 | DevTools retail generators | `Options/DevTools.lua` (1,220): talent/trait skeleton generator using C_Traits, retail spec dumps | 1,220 | M | Low | Keep the skeleton generator idea (it will be needed to author Forever class modules) but rewrite it against `C_Spell`/spellbook scans. Gate it behind a dev flag now. |

#### 2(b) Functionality likely invalid on Forever

| # | Item | Where | Why invalid | Effort | Risk | Recommendation |
|---|---|---|---|---|---|---|
| B1 | Talent model | `Events.lua:416-464` (legacy `GetTalentInfoByID`), `Dragonflight/Classes.lua` (C_Traits override), `Utils.lua:960-1000` (loadout export), `class.talents`, `state.talent`, 131 `talent.` refs in Feral alone | No readable talent API on Forever (shared context). `GetTalentInfoByID` is "not documented" on Forever and `C_Traits` is documented, but talents are not exposed. | M | Medium | Replace with a **`state.talent` that is user-configured** (an options checklist per class) plus `IsPlayerSpell` probing, behind one function. Remove the C_Traits path and the loadout export. |
| B2 | Spec detection | `Classes.lua:4091-4400` (`SpecializationChanged`), `Constants.lua:7-8, 301-308`, `Hekili.Update` early-outs on `state.spec.id` (`Core.lua:1573-1576`) | The whole engine is keyed on retail spec IDs (`NewSpecialization(103)`). Behaviour of `C_SpecializationInfo.GetSpecialization` on a vanilla-ruleset client is unknown (Q1). If it returns nil or 0, `PendingSpecializationChange` loops forever and nothing ever updates. | M | **High** | Introduce a "loadout key" abstraction (class plus user-selected role, for example `DRUID:cat`), mapped to synthetic IDs if needed so `profile.specs[id]` keeps working. |
| B3 | CLEU consumers | `Events.lua:1709-2016`, `RegisterCombatLogEvent` in 33 spec modules (Feral `:1182`), `ns.updateTarget`/`eliminateUnit`/`trackDebuff`/`storeDamage` (`Targets.lua:670-947`) | `CombatLogGetCurrentEventInfo` is removed on Midnight and undocumented on Forever. If it exists, the payload may be secret in combat. | L | High | Put one seam (`ns.CombatEvents`) in front of everything. Reroute: cast history goes to `UNIT_SPELLCAST_SUCCEEDED` (already registered `Events.lua:1220`), swings to `PLAYER_SWING`, target death to `UNIT_FLAGS`/`NAME_PLATE_UNIT_REMOVED`. Drop damage-based target counting and dot snapshots in stage 1 and re-add them in stage 2 only if CLEU proves to work. |
| B4 | Numeric resources in `state.reset` | `State.lua:6884-6930` (`UnitPower`, `UnitPowerMax`, `GetManaRegen`, `GetPowerRegenForPowerType`, then `forecastResources`) | Power and combo points are secret in combat. `res.max > 0` (6890) errors on a secret. | M | High | The data-source layer (D1) returns a *predicted* number for `actual`, plus a flag. Reads are guarded with `issecretvalue`/`C_Secrets.ShouldUnitPowerBeSecret`. |
| B5 | `UNIT_POWER_FREQUENT` handler | `Events.lua:1400-1460` | `newPower < lastPower` comparison on a secret value | S | High (fires constantly) | Guard or replace with a spend inferred from cast events. |
| B6 | Aura scraping and `UNIT_AURA` | `State.lua:5956-6170` `ScrapeUnitAuras`; `Events.lua:1513-1570` (`class.auras[aura.spellId]` and `aura.isFromPlayerOrPlayerPet`) | Aura fields (spellId, expirationTime, applications) are secret in combat. Using a secret as a table key or in a comparison errors. | M | High | Out of combat: scrape as today. In combat: self-tracked timers from cast events, plus the readable booleans (Cooldown Manager `IsShown`, the spell-cost trick for Clearcasting). Check `C_Secrets.ShouldUnitAuraInstanceBeSecret` per instance. |
| B7 | Cooldown metatable | `State.lua:3275-3500` (`GetUnpackedSpellCooldown`, `GetSpellCharges`, `GetSpellLossOfControlCooldown`, `start + duration` math) | Cooldown start/duration are secret in combat. `isActive`/`isOnGCD` stay readable. | M | High | The data source supplies `remains` from self-tracked timers. When untracked, fall back to the readable booleans (`ready` = not `isActive`). |
| B8 | Totems/pets | `State.lua:6868-6873`, `PLAYER_TOTEM_UPDATE` `Events.lua:1399` | `C_Secrets.ShouldTotemSlotBeSecret` exists, so slots can be secret | S | Medium | Guard. Low priority for Feral. |
| B9 | Health, TTD, target counting | `Targets.lua:1160-1600` (TTD from `UnitHealth` samples), `mt_target_health` `State.lua:3217`, `UnitGetTotalAbsorbs` | Enemy health is likely secret in combat (Q3). TTD would error or be meaningless. | M | Medium | Stage 1: make TTD return a configurable constant (APLs mostly use `target.time_to_die>X`). Count targets from nameplates only (readable unit existence). |
| B10 | Range checks | `UI.lua:957, 1583-1586` (LibRangeCheck, LibSpellRange), `Targets.lua` nameplate range, `IsActionInRange` | Item and range APIs are restricted in combat on modern clients. Status on Forever is unknown (Q4). | S | Medium | Keep behind a pcall/guard in stage 1. Re-evaluate with `C_Spell.IsSpellInRange` on Forever. |
| B11 | UI cooldown math | `UI.lua:1496-1516` (delay), `UI.lua:1700-1730` (`RefreshCooldowns`: `start + duration`, `cd:SetCooldown`) | Secret start/duration | S/M | High (runs every frame) | Use `C_Spell.GetSpellCooldownDuration` plus `Cooldown:SetCooldownFromDurationObject`. Both are documented on Forever. This is display-only, which is the case secrets allow. |
| B12 | Casting state | `State.lua:7008-7100` (`buff.casting` from `UnitCastingInfo`), `UI.lua:1504, 1702` | Cast timing is secret | M | Medium | Self-track cast start and end from `UNIT_SPELLCAST_START/STOP/SUCCEEDED` (already handled `Events.lua:1240-1330`). Feral is mostly instant, so this is low priority but needs a guard. |
| B13 | Loss of control | `Classes.lua` (8x `C_LossOfControl.*`), `GetSpellLossOfControlCooldown` | Likely secret | S | Low | Guard or drop. |
| B14 | Keybinding scraper | `Events.lua:2040-2580` (`GetActionInfo`, `GetBindingKey`, 27+25 calls) | Probably readable (not combat data) | n/a | Low | **Keep.** Check `ACTIVE_TALENT_GROUP_CHANGED`/`TRAIT_CONFIG_UPDATED` registrations (`Events.lua:2575-2579`) on Forever. |
| B15 | Build/flavor gates | `Hekili.lua:26-54` (`IsRetail/IsWrath/IsClassic/IsDragonflight/IsTWW/IsMidnight`, `BuiltFor=110200`, `ns.PTR`), `Core.lua:203`, `Classes.lua:1377`, `Events.lua:350, 696, 2575`, `UI.lua:868`, `Targets.lua:300`, `DF/Classes.lua:7`, `TWW/Classes.lua:7`, `local PTR` in 14 spec modules | `buildNum` is the interface number (assumed to be 16001), so every gate takes the "classic" or wrong branch | S | Medium | Delete all predicates and branches, keeping the Forever path. Set `BuiltFor = 16001`. |

#### 2(c) Dead code, duplication, oversized files

| # | Item | Where | Lines | Effort | Notes |
|---|---|---|---|---|---|
| C1 | Unreferenced file | `Options/Archive.lua` | 677 | S | Not in the TOC, no references. |
| C2 | Commented-out `--[[ ]]` blocks | State 277, UI 158, Core 91, Options 60, Classes 56, Scripts 47, Events 29, Targets 20 | ~740 | S | Examples: the Azerite event loop `Events.lua:1033-1058`, BfA/SL trinket code in `state.reset` (`State.lua:6960-7000`, `cyclotronic_blast` at 7022-7035 is live but BfA-only). |
| C3 | Retail trait systems inside `State.lua` | trinket metatable zoo `State.lua:412-720` (stat-stick logic for retail trinkets), azerite/essence/legendary/set-bonus metatables `4486-4554, 4989-5033` | ~600 | M | Trinket stat logic could shrink to `trinket.t1/t2.cooldown/ready` for Forever. |
| C4 | Duplicated API shims | `GetSpellCooldown`/`GetSpellCharges`/`GetSpellInfo`/`GetSpecialization` local wrappers redefined in `Events.lua:25-34`, `UI.lua:24-38`, `State.lua:20-36`, `Classes.lua:27-34`, `Options/DevTools.lua:53-65`, `Options/Options.lua:36-40`, `Utils.lua:57-61` | ~60 | S | This is where the data-source layer will live (D1). Centralise it in one `ns.API` table. |
| C5 | Oversized files | `State.lua` 8,099 (resource model, ~40 metatables, cycle system, event queue, reset, readiness all in one file); `Options/Options.lua` 10,128; `Classes.lua` 4,430; `UI.lua` 3,201 | n/a | L | See D2. |
| C6 | Packaging cruft | `.travis.yml`, `.github/` (retail release workflows), `.pkgmeta` externals using svn `repos.wowace.com` URLs, `Hekili.toc` CurseForge/Wago IDs | small | S | Replace with a vendored `Libs/` or a fetch script, and a Forever-only TOC. |
| C7 | `ns.attr` giant list | `State.lua:8099` (one line listing every state attribute for the script parser) | 1 very long line | S | Regenerate after cleanup. |
| C8 | Lint tooling | `.luacheckrc` is 537 KB of retail globals; **`luacheck` is not installed in WSL** (`which luacheck` returns nothing) | n/a | S | Install (`luarocks install luacheck`) and regenerate globals from Forever API data. `wow_lua_lint` on Forever does not check unknown functions ("upstream does not publish a global function list"), so it catches only removed APIs, events and taint. |

#### 2(d) Rearchitecture candidates

| # | Candidate | Value | Cost | Verdict |
|---|---|---|---|---|
| D1 | **Game data source layer** (`DataSource.lua`, loaded before `State.lua`). Every game read goes through it. Each field is one of three kinds: `readable` (plain value), `tracked` (self-tracked from cast/swing events, predicted), or `display` (secret, may only reach widgets). State metatables call `ds:Power(k)`, `ds:AuraRemains(unit,id)`, `ds:CooldownRemains(id)`, which always return plain numbers or booleans. Each read is guarded by `issecretvalue`/`C_Secrets.*`. | Very high. It is the only way APL closures can stay unchanged and never touch a secret. It is also unit-testable outside the client (pure-logic trackers, so TDD applies). | M-L (touches `state.reset`, ~6 metatables, 3 event handlers, UI cooldowns) | **Do it in stage 1 as a seam with passthrough implementations.** Fill in the tracked logic in stage 2 with Feral. |
| D2 | Split `State.lua` into `State/Core.lua` (env, `advance`, clock), `State/Resources.lua` (1500-1893, 3689-3816), `State/Auras.lua` (1066-1315, 3977-6180), `State/Cooldowns.lua` (3258-3535), `State/Queue.lua` (event queue ~6400-6730), `State/Reset.lua`, `State/Readiness.lua` (7250-8099) | Medium. Readability, smaller diffs, a natural home for D1 consumers. | M (upvalue sharing: many `local function`s are shared, so they need an `ns.state_internal` table) | Do it **after** the content removal (which shrinks it) and **after** D1 lands, as a pure move. Optional for the stage-1 exit. |
| D3 | Per-class module layout: `Classes/<Class>/<Class>.lua` (class-wide abilities, auras, forms) plus `Classes/<Class>/<Role>.lua` (APL pack + role hooks) for 9 classes | High for the 9-class future. Vanilla abilities are shared across "specs" (no spec-locked spellbooks), so a class-level base avoids the copy-paste seen in the TWW modules (Feral and Guardian each redefine Druid forms and abilities). | S to set up the skeleton, then L to fill | Set up the empty skeleton plus a loader in stage 1. Content goes in stage 2+. |
| D4 | Replace the spec-ID key with a loadout key (B2) | High. It unblocks everything if Forever has no specs. | M | Required in stage 1 if Q1 says there are no specs. Otherwise defer. |
| D5 | CLEU seam (B3) | High | M | Stage 1. |
| D6 | Trim `Options.lua` into per-panel files | Medium | L | Defer. Only remove retail panels in stage 1. |
| D7 | C_AssistedCombat integration as a fallback or sanity display (`C_AssistedCombat.GetNextCastSpell` is documented on Forever) | Medium. A free "second opinion" icon and a debugging aid. | S | Stage 2. Note it in the data-source design. |
| D8 | Drop SpellFlashCore, LibDualSpec, AceComm/Serializer sharing, Masque/ElvUI/ConsolePort skins | Low/medium simplification | S each | Optional. Keep the skins (cheap). LibDualSpec relies on spec APIs, so evaluate it with Q1. |

### 3. Proposed stage-1 sequence

Each step is one commit (or a small PR), must `/reload` cleanly on a Forever Druid (the BugSack/`/console scriptErrors 1` log
is the evidence), and must pass `luacheck .` and LuaLS with no new diagnostics.

0. **Make it loadable at all.** Vendor the `.pkgmeta` externals into `Libs/` (or add a `tools/fetch-libs.sh`
   and document it) and confirm `embeds.xml` resolves. Set TOC `## Interface: 16001` and drop the CurseForge/Wago
   IDs. Install luacheck. Record the baseline Lua errors on `/reload` (expected: many, from the build gates and specs).
1. **Delete the content that cannot run (A1, A2, A3, A7, A10, C1).** Remove all `TheWarWithin/*` spec and shared
   files, `Priorities/`, Legion/TBC/Wrath/Cata items, the Timerunning hooks and `Options/Archive.lua`, and edit the
   TOC. The addon then has zero specs: `class.initialized` stays false, `Hekili.Update` returns at `IsValidSpec`,
   and the "no modules loaded" notice (`Events.lua:1222`) fires. That is acceptable and loadable.
2. **Remove the build/flavor gates (B15).** One Forever path everywhere. Set `BuiltFor`. Remove `ns.PTR`.
3. **Remove the BfA, Shadowlands and Dragonflight systems (A4, A5, A6) and their consumers.** That covers the
   azerite/essence/legendary/covenant/conduit tables, `updatePowers`/`updateEssences`, `WipeCovenantCache`, the
   essences toggle, and `C_Soulbinds` options. Replace `ns.updateTalents` with a stub that zeroes `state.talent`
   (B1 placeholder).
4. **Trim shared and constant data (A8, A9, A11, A12, A14).** Cut `ns.Specializations` and racials down to the 9
   classes and vanilla races. Delete hero trees, PvP talents, M+ affixes, retail potions and trinkets, PvP gear,
   holiday items and one-time fixes. Keep the engine-required `all` auras.
5. **Spec identity (B2, D4).** Implement the loadout-key abstraction according to Q1, so `SpecializationChanged`
   completes on a Forever character and `Hekili.Update` reaches `state.reset`.
6. **CLEU seam (B3, D5).** Wrap `CLEU_HANDLER` behind `ns.CombatEvents`. Register CLEU only if
   `CombatLogGetCurrentEventInfo` exists (probe with `pcall`). Move `AddToHistory` to
   `UNIT_SPELLCAST_SUCCEEDED` and swings to `PLAYER_SWING`. Drop `RegisterCombatLogEvent` from the spec API, or
   make it a no-op that warns.
7. **Data-source seam (D1, B4-B13).** Add `DataSource.lua` with three kinds of access: readable, tracked
   (passthrough for now) and display. Route `state.reset` powers/health/totems/swing speed, `ScrapeUnitAuras`,
   `mt_default_cooldown`, `UNIT_POWER_FREQUENT`, `UNIT_AURA` and UI cooldowns (switched to
   `GetSpellCooldownDuration` + `SetCooldownFromDurationObject`) through it, with `issecretvalue` guards. Out of
   combat behaviour is unchanged. In combat, guards return the last known plain value plus `stale = true` instead
   of erroring.
8. **Retail options and dev tools (A13, A15, C2, C4).** Remove retail panels, gate DevTools behind a flag, delete
   commented-out blocks, centralise the API shims into the data source.
9. **Class skeleton (D3), and optionally the `State.lua` split (D2).** Create `Classes/Druid/Druid.lua` with
   the class registration only (no APL) to prove the loader path. Regenerate `.luacheckrc` globals and `ns.attr`.

**Exit criteria (stage 1 done):**
- TOC `## Interface: 16001`. The libraries are present in the repo or fetched by a documented script.
- `/reload` and fresh login on a Forever Druid produce **zero Lua errors**, both out of combat and during 60 s of
  combat on a target dummy (the data-source guards prove themselves here). The display frame shows (it can be
  empty, or show the Druid skeleton's placeholder).
- `git grep -nE 'Azerite|Essence|Covenant|Soulbind|Conduit|Legendary|HeroTree|hero_tree|Timerunning|Evoker|DEATHKNIGHT|DEMONHUNTER|MONK|IsDragonflight|IsTWW|IsRetail|ns\.PTR'`
  returns nothing in our own Lua.
- `luacheck .` is clean with regenerated Forever globals. LuaLS reports no errors or warnings in non-Libs files.
- `CombatLogGetCurrentEventInfo` is referenced only inside the guarded CLEU seam. `UnitPower`, `UnitAura`-family
  calls, `GetSpellCooldown` and `UnitHealth` are referenced only inside `DataSource.lua`.

Expected size after stage 1: about 25-30k lines of our own Lua, down from about 151k.

---

## Evidence (file:line)

- Libraries missing: `embeds.xml:2-27` includes 25 libraries; `ls Libs` shows only `SpellFlashCore`; `.pkgmeta` lists them as externals; same in the symlinked `~/src/hekili/Libs`.
- Build number: `Hekili.lua:15-17` (`buildNum` = 4th `GetBuildInfo` return), predicates `Hekili.lua:26-54`, `BuiltFor` warning `Core.lua:203`, early exits `Dragonflight/Classes.lua:7`, `TheWarWithin/Classes.lua:7`.
- Talent paths: legacy `Events.lua:416-464`; C_Traits override `Dragonflight/Classes.lua:17-30+`; loadout export `Utils.lua:960-990`; hero tree `Constants.lua:310-550`, `State.lua:140, 5001-5016`.
- Spec keying: `Classes.lua:1369-1400` (`NewSpecialization`, `IsRetail` branch at 1377), `Classes.lua:4091-4140` (`SpecializationChanged`), `Core.lua:1561-1585` (`Hekili.Update` guards), `TheWarWithin/DruidFeral.lua:11` (`NewSpecialization( 103 )`).
- CLEU: handler `Events.lua:1709-2016` (history 1911-1914, swings 1933-1950, dots 1968-1996, targets 1930/2010, damage 1804); registration `Events.lua:2016`; 33 spec modules use it (Feral `:1182`).
- Reset reads: `State.lua:6787-7136` (auras 6807-6815, totems 6868-6873, powers 6884-6930, health 6956-6958, swings 6961-6970, casting 7008-7100).
- Aura scrape: `State.lua:5956-6170`; `UNIT_AURA` `Events.lua:1513-1570`.
- Cooldown metatable: `State.lua:3275-3500`.
- Power handler: `Events.lua:1400-1460`.
- UI cooldown math: `UI.lua:1496-1516`, `UI.lua:1700-1730`; engine loop `UI.lua:2377-2440`; display OnUpdate `UI.lua:1108`.
- Targets: `Targets.lua:385` (`getNumberTargets`), 670-947 (CLEU-fed tracking), 1160-1600 (TTD), 290-348 (Chromie/WarMode/Timerunning).
- APL compile: `Scripts.lua:349` (`SimToLua`), `1423` (`ConvertScript`); APL pack example `TheWarWithin/DruidFeral.lua:3106`.
- Dead file: `Options/Archive.lua` (absent from `Hekili.toc`, no references).
- Forever API spot checks (`wow` MCP):
  - `CombatLogGetCurrentEventInfo`, `UnitBuff`, `GetSpellInfo`, `GetTalentInfoByID`, global `GetSpecialization`: "not documented" on Forever. Hekili already uses namespaced replacements for all except CLEU and `GetTalentInfoByID`.
  - Documented on Forever: `C_SpecializationInfo.GetSpecialization/GetSpecializationInfo`, `C_Traits.GetNodeInfo`, `C_ClassTalents.GetActiveConfigID`, `GetPowerRegenForPowerType`, `C_UnitAuras.GetAuraDataByIndex`, `C_NamePlate.GetNamePlates`, `C_AssistedCombat.GetNextCastSpell`, `C_Spell.GetSpellCooldownDuration`, `Cooldown:SetCooldownFromDurationObject`, `issecretvalue`, `issecrettable`, and `C_Secrets.Should{UnitPower,UnitPowerMax,SpellCooldown,UnitAuraInstance,UnitAuraSlot,TotemSlot,UnitSpellCasting,UnitHealthMax,UnitIdentity,…}BeSecret`.
  - Events: `COMBAT_LOG_EVENT_UNFILTERED`, `PLAYER_SWING(swingDuration, swingType)`, `PLAYER_SWING_RANGE_UPDATE`.
- `wow_lua_lint` on `Events.lua` (forever): 0 errors. It notes that unknown-function checks are off for Forever, so it cannot prove API presence.

## Open questions

1. **Q1, spec identity:** what do `C_SpecializationInfo.GetSpecialization()` and `GetSpecializationInfo()`
   return on a Forever character (nil, 0, an "initial spec" ID, or real 102/103/104)? This decides how big B2/D4 is.
2. **Q2, CLEU:** does `CombatLogGetCurrentEventInfo` exist on Forever? If it does, are source/dest GUIDs, spellIDs
   and amounts secret in combat? (`/dump CombatLogGetCurrentEventInfo` plus a test in combat.)
3. **Q3:** are enemy `UnitHealth`/`UnitHealthMax` secret in combat on Forever (TTD), and is `UnitGUID` on nameplate
   units secret (`ShouldUnitIdentityBeSecret`)? Target counting depends on it.
4. **Q4:** in combat on Forever, do the range APIs (`C_Spell.IsSpellInRange`, `IsItemInRange` as used by
   LibRangeCheck, `IsActionInRange`) return readable values?
5. **Q5:** confirm that the 4th return of `GetBuildInfo()` on Forever is 16001 (assumed above).
6. **Q6:** keep `SavedVariables: HekiliDB`, or rename it (for example `HekiliForeverDB`) so a retail install's
   profile is never loaded into the fork? Recommended: rename.
7. **Q7:** licence and attribution for vendoring the libraries into the repo (all are permissive or LGPL Ace3,
   but this should be confirmed).
8. Dependency on `01-api-inventory.md`: re-validate B4-B13 against its verified secret/readable matrix once it exists.

## Confidence

- **High:** sizes, file inventory, dead `Archive.lua`, missing libraries, CLEU consumer map, the call sites of the
  `state.reset`/metatable/UI reads, the expansion-system dependency web (A4-A6).
- **Medium:** the exact secret behaviour of each call on Forever (from the shared context plus `C_Secrets`
  predicate existence, not in-game tests), the effort estimates, and the build-gate inversion (it depends on Q5).
- **Low:** spec-ID behaviour (Q1) and CLEU availability (Q2). These are the two biggest unknowns, and both change
  step 5/6 effort from M to L.
