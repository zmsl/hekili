<!-- Research output saved verbatim from the 2026-10-14 planning session (sonnet Explore agent, read-only survey of ~/src/hekili at fc61b6d9): the Hekili integration points for VirtualState. "Nowcast" was a working name; the component is VirtualState. -->

## Hekili "nowcast" integration points (branch forever, HEAD fc61b6d9)

Nothing was edited and I did not write the plan file. Line numbers are as read.

### 1. Update cycle

| Item | Where |
|---|---|
| Throttle state | `UI.lua:2293` sets `Engine.refreshTimer = 1`. `UI.lua:2294` sets `eventsTriggered = {}`. |
| Per-frame driver | `HekiliEngine OnUpdate`, `UI.lua:2370-2450`. `refreshTimer` only accumulates while no thread is active (`2371`). |
| Cycle start | `UI.lua:2383`. Condition: no live thread and `refreshTimer &gt; (criticalUpdate and combatRate or refreshRate)`. |
| Creating the coroutine | `UI.lua:2389-2393`: `criticalUpdate=false`, `refreshTimer=0`, then `coroutine.create(Hekili.Update)`. |
| Resuming | `UI.lua:2414`, one `coroutine.resume` per OnUpdate frame. |
| Cycle end | `UI.lua:2431-2435`: `activeThread=nil`, `refreshRate=0.5`, `combatRate=0.2`. |
| Rates | `refreshRate` starts at 0.25 (`2377`), then 0.5 after the first thread ends. `combatRate` is 0.2. |
| Yielding | `Hekili:Yield` → `DoYield`, `Core.lua:668-679`. It yields only when the frame budget (`maxFrameTime`) is exceeded. |
| One cycle | `Hekili.Update`, `Core.lua:1547`. It returns early on `ScriptsLoaded`, `IsValidSpec` and `specID` (`1548-1558`). |
| Resets in a cycle | `state.reset( dispName, fullReset )` at `Core.lua:1619`, once per display (up to 5 rounds). The display order is Interrupts, Defensives, Cooldowns, Primary, AOE (`displayRules`, `Core.lua:1537`). |
| Reset gating | A display with `UI.Active and UI.alpha &gt; 0 and rule(profile)` false skips its reset. `Scripts.lua:1761` also calls a bare `state.reset()`. |
| Full vs short reset | `state.reset` overrides its argument at `State.lua:6184`: `full = dispName=="Primary" or state.offset&gt;0`. |

`ForceUpdate` (`UI.lua:2459-2470`) sets `Engine.criticalUpdate = true`, which drops the wait from 0.5s to 0.2s. With `super` it also adds 0.1 to `refreshTimer`, so the next cycle starts roughly 0.1s after the previous one ends. It records `firstForce` and `eventsTriggered[event]`, which are only used for debug (`UI.lua:2037-2069`). It never interrupts a running thread.

**Earliest safe drain point, before any reset:**
- **Outside the coroutine:** `UI.lua:2389-2393`, right before `coroutine.create`. This runs once per cycle on the update thread.
- **Inside the coroutine:** the top of `Hekili.Update`, after the `IsValidSpec` and `specID` checks (`Core.lua:~1558`, before the `displayRules` loop at `1580`). Use this one if the drain needs `state.spec` and `class` to be valid.
- **Mid-cycle events:** a cycle spans many frames, and events keep arriving. The drain should cut off at a timestamp captured at drain time. Anything later waits for the next cycle.

### 2. Running one ability outside a recommendation

The sequence Core uses to "cast" an instant in the simulation (`Core.lua:1984-2048`):

| Step | Call | Defined |
|---|---|---|
| Wait | `if state.delay&gt;0 then state.advance(state.delay)` | `Core.lua:1989`, `State.lua:6513` |
| GCD | `setCooldown("global_cooldown", gcd.execute)` | `Core.lua:1993-1995` |
| Charges or cooldown | `spendCharges(action,1)` if `charges&gt;1 and recharge&gt;0`, else `setCooldown(action, ability.cooldown)` | `Core.lua:2038-2044` |
| Spend | `ns.spendResources(action)` | `State.lua:6608-6636`: reads `ability.spend` (number or function), then `state.spend(cost, resource)`. A cost between 0 and 1 is multiplied by `modmax`. |
| Handler | `state:RunHandler(action)` | `State.lua:6124-6168` |

Hard-casts and channels go through `QueueEvent` (`Core.lua:2002-2033`). `HandleEvent` then replays `CAST_FINISH` as `spendCharges`/`setCooldown`, `spendResources`, `RunHandler` (`State.lua:5921-5953`).

**What each call mutates:**

| Call | State fields |
|---|---|
| `state.spend` (`State.lua:1387`) | `prespend` hook, `resourceChange` (`1344`): `r.spend` hook, or `r.actual = max(0, r.current - amt)`, then `forecastResources`. |
| `setCooldown` (`State.lua:522`) | `cooldown[x].duration`, `.expires = query_time+duration`, `.charge=0`, `.recharge_began=query_time`. |
| `spendCharges` (`State.lua:537-562`) | `.charge`, `.recharge_began`, `.duration`, `.expires`. Falls back to `setCooldown` if the ability has one charge. |
| `applyBuff` / `applyDebuff` (`State.lua:731`, `874`) | `.applied` (defaults to `query_time`), `.expires`, `.count`, `.v1-v3`, `.caster`, `lastApplied`, `active_dot`. `removeBuff` is `applyBuff(aura, 0)`. |
| `RunHandler` | `state.modified=true` (`6133`), `ability.handler()`, `prev.last`, `prev_gcd.last` / `prev_off_gcd.last`, `predictions*`, `history.casts[key]=query_time` (`6146`), `StartCombat` if `time==0 and startsCombat`, then the `runHandler` hook. |
| GCD | `cooldown.global_cooldown` through `setCooldown`. |

Channeled abilities take a different path in `RunHandler` (`6135-6137`): `ability.start()` and `channelSpell`, not `handler`.

**Setting the clock to a past time:**
- `query_time` is computed as `now + offset + delay` (`State.lua:1814`). `now` is lazily cached from `GetTime()` (`1812`). `ClearMarks` drops that cache at the start of `reset` (`6186`, `Utils.lua:888`). `offset` and `delay` are plain writable fields.
- Every mutator above reads `query_time`, so setting `state.offset = t - state.now` with `delay = 0` before the call applies the effects at time `t`. `offset` may be negative.
- Precedent: `advance` temporarily sets `state.offset = event.time - state.now` around `HandleEvent` (`State.lua:6543-6550`), and likewise around `RunHandler` (`6529-6532`). `Core.lua:1717` does `offset - t`.
- Restore `offset` and `delay` afterwards.
- Caveat: `advance()` applies `roundUp(time,3)` outside reset (`6519`). A direct offset write skips that.
- Caveat: `state.resetting` should be false (set by `reset`), or the handler's `modified` flag is skipped.

### 3. How Hekili learns of our casts today

| Event or source | Registered | What it writes |
|---|---|---|
| `UNIT_SPELLCAST_SUCCEEDED` | `Events.lua:1014` (player and target) | Only `ForceUpdate` and `RemoveHold`. **No history write.** |
| `UNIT_SPELLCAST_START` | `1034` | `ForceUpdate`, plus `ForceUpdate(event,true)`. |
| `UNIT_SPELLCAST_STOP` | `1067` | Only `ForceUpdate` and `RemoveHold`. |
| `UNIT_SPELLCAST_DELAYED` | `1076` | Re-queues a real `CAST_FINISH` using `UnitCastingInfo`. |
| `UNIT_SPELLCAST_SENT` | `1121` | `state.cast_target`. |
| `UNIT_SPELLCAST_CHANNEL_START` / `_STOP` / `_UPDATE` | `1047`, `1056`, `1062` | `ForceUpdate`, and `RemoveHold` on start. |
| CLEU handler | `1461-1766` (`SPELL_CAST_START` `1571`, `SPELL_CAST_SUCCESS` `1613`) | `QueueEvent(...,true)` into `realQueue`, and `state:AddToHistory` (`1663`, `1666`). |

- **`AddToHistory`** (`Events.lua:912-943`) is the only writer of `player.lastcast`, `casttime`, `lastgcd`, `lastoffgcd`, the `prev*` histories (6 entries each) and `ability.realCast`, `realUnit`, `realRank`.
- **Forever gap:** it is called only from CLEU. `Events.lua:174` skips registering CLEU on Forever (the comment says a "virtual combat log" is a Phase 3b item). So on Forever none of the history above is written today.
- **`ns.castsAll/On/Off`** (`Events.lua:905-909`) are static `no_action` arrays that nothing else reads. The live data is `state.predictions/predictionsOn/predictionsOff` (`State.lua:178`, `3228-3230`).

**Persists across resets:**
- `realQueue` (`State.lua:5619`), pruned only when `e.time + 0.2 &lt; now` (`5857-5866`).
- `prev*.history`, `player.last*`, `ability.realCast`.
- `swings.mh_actual` / `oh_actual`, `gcd.lastStart`, `cast_target`, `holds`.

**Rebuilt or wiped by reset:**
- `virtualQueue`, copied from `realQueue` (`5850-5878`).
- `predictions*` and `history.casts` / `history.units` (`6268-6272`).
- Cached `now`, `offset`, `delay`, `modified`.
- Resource `.actual`, re-read from `UnitPower` (`6290`).
- `swings.mh_pseudo` / `oh_pseudo` (`6366`).

### 4. Other handlers

| Event | Registered | What it does |
|---|---|---|
| `PLAYER_REGEN_DISABLED` | `Events.lua:856` | Sets `state.combat` and calls `ForceUpdate`. |
| `PLAYER_REGEN_ENABLED` | `875` | Zeroes `state.combat` and `swings.*_actual`, releases combat holds. |
| `UNIT_POWER_FREQUENT` | `1212` (function at `1175`) | Tracks the focus/energy tick, and calls `ForceUpdate` when power drops. |
| `UNIT_AURA` | `1265` (player and target) | Maintains `instanceDB`, sets `state[unit].updated`, and `ForceUpdate` if an aura is of concern. |
| `PLAYER_TARGET_CHANGED` | `1327` | Rebuilds target `instanceDB`, sets `state.target.updated`, and `ForceUpdate(event,true)`. |
| `PLAYER_STARTED_MOVING` / `PLAYER_STOPPED_MOVING` | `1349`, `1359` | `ForceUpdate`, rate-limited to one per 0.5s. |

`SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_USABLE`, `ACTIONBAR_UPDATE_USABLE` and `PLAYER_SWING*` are **not registered anywhere** in the loaded files (confirmed by grep). The only swing handling is CLEU `SWING_*` at `Events.lua:1684-1699`, which is dead on Forever.

### 5. Facade

Every `local VGA = LibStub( "VirtualGameAPI-1.0" )` is at line 5 of its file. The count is `grep -c "VGA\."` (matching lines), and `archive/` is excluded.

| File | Count | File | Count |
|---|---|---|---|
| `State.lua` | 42 | `Hekili.lua` | 2 |
| `Events.lua` | 10 | `Constants.lua` | 2 |
| `Targets.lua` | 9 | `MultilineEditor.lua` | 1 |
| `Options/DevTools.lua` | 9 | `Core.lua` | 1 |
| `Utils.lua` | 6 | `Forever/Warrior.lua` | 1 |
| `UI.lua` | 6 | `Options/ChatCommands.lua` | 1 |
| `Classes.lua` | 4 | | |
| `Options/Options.lua` | 4 | | |

- **Local pattern:** file-top locals alias the facade, for example `local GetFrameCPUUsage, GetTime, InCombatLockdown = VGA.GetFrameCPUUsage, VGA.GetTime, VGA.InCombatLockdown` (`Core.lua:6`). Namespaces are aliased too: `local C_Item, C_LossOfControl, C_Spell = VGA.C_Item, ...` (`State.lua:6`).
- **Library:** `Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua` has 322 lines. It has 51 `stub(` calls (lines `104-234`), 124 `passthrough(` calls and 175 names in total, matching `tools/api_inventory.txt`.
- **Stubs:**
  - Resources: `UnitPower`, `UnitPartialPower`, `GetPowerRegenForPowerType`, `GetManaRegen`.
  - Health: `UnitHealth`, `UnitHealthMax`, `UnitGetTotalAbsorbs`.
  - Combat stats (`GetCombatRating*`, `GetCritChance`, `GetHaste`, `GetMasteryEffect`, `GetMeleeHaste`, `GetRangedCritChance`, `GetSpellBonusDamage`, `GetSpellCritChance`, `UnitArmor`, `UnitAttackPower`, `UnitAttackSpeed`, `UnitDamage`, `UnitSpellHaste`, `UnitStat`, `UnitWeaponAttackPower`): all return zeros.
  - Movement and range: `GetUnitSpeed`, `UnitInRange`, `GetTotemInfo`.
  - Auras: `AuraUtil.FindAura`, `AuraUtil.ForEachAura`, `C_UnitAuras.GetAuraDataByAuraInstanceID`, `GetAuraSlots`, `GetBuffDataByIndex`, `GetDebuffDataByIndex`, `GetPlayerAuraBySpellID`, `UnitAura`, `UnitAuraBySlot`.
  - Spells: `C_Spell.GetSpellCooldown`, `GetSpellCharges`, `GetSpellCastCount`, `GetSpellLossOfControlCooldown`.
  - Casts: `UnitCastingInfo`, `UnitChannelInfo`.
  - Combat log: `CombatLogGetCurrentEventInfo`.
  - Absent on Forever: `GetTalentInfoByID`, `GetSpellBaseCooldown`, `GetSpellLink`, `IsHarmfulSpell`, `IsHelpfulSpell`, `IsPassiveSpell`, `IsUsableSpell`, `GetItemGem`, `GetItemInfo`.
- **Partly secret, already stubs:**
  - `C_Spell.GetSpellCooldown` (`155`) and `C_Spell.GetSpellCharges` (`156`) return fixed tables, because the times are secret in combat.
  - `UnitCastingInfo` and `UnitChannelInfo` (`163-164`) call the real function for `"player"` only (`playerOnly`) and return nil otherwise.
- **Passthroughs to double-check before reverting to direct calls:** `C_Item.GetItemCooldown` (marked "plain" but cooldown-shaped), `C_Spell.IsSpellUsable`, `UnitThreatSituation` and `InCombatLockdown` (the last "lags at REGEN_DISABLED").
- **Sizing the revert:** the 124 passthroughs plus about 9 absent-API stubs are the names whose use could go back to direct calls. About 41 stubs (the secret ones) would stay. About 100 `VGA.` lines across 14 files would change, 42 of them in `State.lua`.
- **Enforcement:**
  - `tools/check_api_reads.sh`: fails on any `luacheck` W113 hit for a name in `tools/api_inventory.txt` (grep of the `accessing undefined variable` message). It also greps `_G.Name` / `_G["Name"]` reads. It runs on the files in `Hekili.toc` minus the archived expansion folders.
  - `tools/list_api_reads.sh`: lists the same reads, plus `VGA.` reads.
  - `.luacheckrc:1-3` states the rule. Game API names are deliberately left out of `globals` / `read_globals` (`.luacheckrc:28`, `:45`). That is why a bare read shows up as W113.
  - Reverting a name to a direct call means removing it from `tools/api_inventory.txt` (and the lib), or declaring it in `read_globals`. Otherwise the check fails.
  - `Libs/` is excluded from luacheck.

### 6. Headless specs

- `.busted` (root): `default = { ROOT = {"Libs/VirtualGameAPI-1.0/spec"}, pattern = "_spec", verbose = true }`. Run `busted` from the repo root.
- `Libs/VirtualGameAPI-1.0/spec/VirtualGameAPI_spec.lua` (176 lines):
  - Paths are relative to the repo root (`LIB` at `:4`, `INVENTORY` at `:5`).
  - `fake(name, calls)` (`:17`) installs a function into `_G` (or `_G[ns][key]`) for every inventory name. It returns `"real:"..name` and logs the call.
  - `fakeLibStub()` (`:36`) is a minimal callable table with `NewLibrary`.
  - `before_each` (`:58-65`) sets `_G.LibStub`, `_G.issecretvalue`, fakes every inventory name, then `loadfile(LIB)()`. It reloads with a fresh stub at `:103`, `:115` and `:155`.
  - `after_each` (`:67-71`) unfakes everything.
- The spec only loads the facade. It cannot load Hekili's own files, which need much more of `_G`. A nowcast module would need its own fakes for `state`, `class` and `ns`.

Skipped: I did not read the Forever class modules' handlers and spends, the `Hekili:Yield` frame-budget internals, or the `mt_resource` forecast internals. The 124 passthrough count is from grep, not a runtime listing. Main risk for the design: `Events.lua:1676` and the CLEU path are dead on Forever, so the observation log would be the only source of cast history there.
