<!-- Research output saved verbatim from the 2026-10-14 planning session (opus Plan agent): the first design draft, written for a standalone LibStub library "VirtualGameState-1.0". The shape changed afterwards (decision 1 of the spec): VirtualState is an in-addon module under `VirtualState/` with a functions-only API and a Belief record, and the facade folds in as `ns.Facade`. The families, policy table, clock, tests, risks and Phase 2/3 outlines remain valid content; the library packaging, metatable access and `VGS` naming do not. -->

# VirtualGameState-1.0 (VS): Phase 1 design

Grounding: Hekili `forever` at fc61b6d9 and TDF main at 7bef7b5, both read-only. The TDF belief layer is already on absolute time: `s.now` is the belief clock (`Model/Belief.lua:4`). The main porting cost is somewhere else. TDF moves its belief forward by running the whole engine: `Timeline.Advance`, `Forecast`, `H.resAt` and compiled `spec.use` chunks (`Belief.lua:26-33`, `497-504`, `594-630`; `Engine/SpecBuilder.lua:1236`). VS has to carry its own small replacement for that.

## A. Module layout and port map

`Libs/VirtualGameState-1.0/`. The order below is the load order in `VirtualGameState-1.0.xml`.

| # | File | Responsibility |
|---|---|---|
| 1 | `VirtualGameState-1.0.lua` | LibStub head, internal table `I` with a loading guard, `VS.Enum` (Obs kinds, Hand, origin strings), Belief record factory, debug rings (8 per origin), projection helpers |
| 2 | `ObsLog.lua` | 256-slot ring of {kind,t,a,b,c} |
| 3 | `Effects.lua` | `E.*` mutators on the flat state `s` |
| 4 | `Class.lua` | `RegisterClass`, `SetFactsProvider`; turns string keys into integers, allocates `s` and every record once |
| 5 | `Belief.lua` | `Update(now)`: dispatch, advance, constrain, sync; lag clamp |
| 6-12 | `Belief/Resources.lua`, `Casts.lua` (casts, cooldowns, charges, GCD), `Auras.lua` (target memory, index order, `AuraGen`), `Swing.lua`, `Player.lua` (haste, speed, health, TTD, enemies, stats, talents), `Totems.lua`, `TargetCast.lua` | One file per belief family: appliers, listeners, accessors |
| 13-23 | `Sources/Sources.lua` (`Plain`, staging, Flush, Poll, event table), `Power`, `Spellbook` (ranks, ladder poll, cooldown flags, plain cost reads), `Casts`, `Auras`, `Swing` (adds weapon size), `Player` (adds the out-of-combat stats cache), `Target` (target casts, `UNIT_COMBAT`), `Talents`, `Nameplates`, `Totems` | The only layer that touches the game, through an injected `api` |
| 24 | `Data/Spells.lua` | Generated DB2 numbers |
| 25 | `Classes/Warrior.lua` | Class data and effect routines |
| 26 | `Drive.lua`, `Snapshot.lua` | `Start`, OnUpdate, the urgent lane, `Snapshot()` |

Not in the .xml: `spec/` (busted specs and helpers), `tools/gen_data.py` with `tools/data/*.json`, `README.md`, MIT `LICENSE`, and a standalone `.busted`.

Hekili wiring:
- `embeds.xml`: include VS before VGA (VGA is on line 3 now).
- Hekili `.busted`: add the VS spec directory to ROOT.
- `.pkgmeta`: ignore `spec` and `tools`.

| TDF source | Library file | What changes |
|---|---|---|
| `Model/ObsLog.lua` | `ObsLog.lua` | Copied as is; `ns` becomes `I` |
| `Engine/Enum.lua:70-117` (Obs, ReadOf, Hand, TargetCastOf) | core file | Same kinds and integers. Adds origin strings. `Input` and `Bound` are dropped (VGA chooses the bound) |
| `Model/Belief.lua` | `Belief.lua` | Record changes to the owner's shape. `anchor()` (`:478`) becomes `sample(rec, origin, v, t, event)`. `Write`, `WRITERS`, `FINAL` and the Persist serials are dropped; accessors replace them. `advance`/`stretch` are rewritten without Timeline or Forecast: linear regen, tick models (`floor((t-phase)/interval)` crossings), swing steps, one pending cast-finish slot |
| `Belief/Resources.lua` | same | `pin` `:218-263`, `ladder` `:275-315` and `calibrate` (the regen EMA, `:117-136`) are copied as is. `spec.cost[a]` becomes `C.cost[a](s,t)`. `APLRegistry.Readable` becomes `C.res[slot].readable` |
| `Belief/Casts.lua`, `Usable.lua`, `Ranks.lua` | `Belief/Casts.lua` | Keeps the `step()` before/after diff (`:34-78`): it shifts lo/hi and writes the `modelled` sample. The compiled `spec.use`/`finish` become a core cast step (spend cost, start cooldown, start GCD) followed by the class `effect` |
| `Belief/Auras.lua`, `Targets.lua` | `Belief/Auras.lua` | Target-slot memory kept (`TARGET_CAP` 16). Adds a per-unit index-order array and `AuraGen` |
| `Belief/Swing.lua` | same | Logic copied. `H.swingRate` becomes `C.res[slot].swing[h](s)`. The Write part becomes an accessor |
| `Belief/Player.lua`, `Talents.lua`, `Pets.lua` | `Player.lua`, `Totems.lua` | Haste, moving, facts and talents kept. Only the totem half of pets is ported |
| `Sources/*.lua` | `Sources/*.lua` | `opts.spec/def` become the compiled class `C`. `mark` becomes the urgent flag. Selftest lines go to `Snapshot`. Items, Group and Options are dropped |
| `Engine/NewSpec.lua`, `SpecBuilder.lua` (data part) | `Class.lua` | No APL, codegen, settings or toggles |
| `Engine/Helpers.lua` `:274-436`, `:612-660`, `:1519-1527` | `Effects.lua` | Only the about 10 mutators; each takes an absolute `t` |
| `TacoDogForever_Warrior/Warrior.lua`, `Gates.lua` | `Classes/Warrior.lua` | Data and effects only |
| `TacoDogForever_Data/Generated/Spells.lua`, `tools/gen_data.py` | `Data/Spells.lua`, `tools/gen_data.py` | Only the output header changes |
| `Game/App.lua:943-967` | `Drive.lua` | Only Flush and Update remain |

Build order: core, ObsLog and Resources/Casts (the cost ladder) → Swing → Auras → the remaining families → VGA policy → in-game checkpoint.

## B. Public API

**How a Belief record is read.** `Update` keeps the values at belief-clock time in family arrays (`est0/lo0/hi0[slot]`). An accessor writes `rec.est/lo/hi/conf = project(clock values, now)` and returns `rec`. Every projection starts from the clock values, so the order of reads never matters. Accessors never flush, update or call the game.

Projection rules (`dt = max(0, now − clock)`):
- **Resources:** `est0/lo0/hi0 + regen.{est,lo,hi}·dt`, clamped to [0, max]. `conf = 1 − (hi−lo)/max`, halved within `SNAP_HOLD` of a snap (`Belief.lua:695-699`).
- **Absolute-time quantities** (cooldown readyAt, aura expiry, totem, target cast end) do not move. Their conf is `1/(1+age/AURA_HALF_LIFE)` (`:709`).
- **Swing:** est is the first predicted swing after `now` (`Swing.lua:197`); conf is `confAt` (`:181-188`).

**Static, read-only tables:**
- `VS.Player`: `{class, specKey, level, guid, powerType, maxPower[pt], inCombat, moving}`
- `VS.Abilities[spellID]`: one record for every rank ID: `{key, id, ids, power, cost, cooldown, gcd, cast, charges, onNextSwing, known, rank, isActive, isOnGCD}`. The two flags are plain, taken from the last `SPELL_UPDATE_COOLDOWN`. `cost` is the plain `C_Spell.GetSpellPowerCost` read when one has been made, else DB2.
- `VS.Auras[spellID]`: `{key, id, unit, duration, maxStacks, tick, name, icon}`
- `VS.Talents[key]`: `{id, rank, maxRank}`, from the `C_Traits` walk (observed; plain in combat)
- `VS.Stats`: out-of-combat cache with read time `t`:
  - `str, agi, sta, int, spi` as {base, eff, pos, neg}
  - `ap` as {base, pos, neg}; `mhMin, mhMax, ohMin, ohMax`; `armor` as {base, eff}
  - `crit, rangedCrit, mastery`; `spellCrit[school]`, `spellBonus[school]`; `rating[cr]`, `ratingBonus[cr]`
- `VS.GcdInfo`: `{start, duration}`
- `VS.TargetCastInfo`: `{active, channel, castBarID, start, interruptible = 1/0/-1}`
- `VS.TotemInfo[slot]`: `{spellID, name, icon, start, duration}`

Origins: O observed, P pinned, M modelled, D default.

| Accessor | Returns | Origins |
|---|---|---|
| `VS.Power(pt, now)` | Belief | O (readable types, e.g. combo points), P (usability flip, ladder), M (casts, swing steps, ticks), D (rest) |
| `VS.Regen(pt, now, casting?)` | Belief, per second | O (out-of-combat read), M (EMA calibration), D (declared) |
| `VS.Cooldown(spellID, now)` | Belief readyAt, or nil | O (out-of-combat times), P (`isActive` edges, `CD_PROBE`, `Belief.lua:652-684`), M (cast + length), D (DB2) |
| `VS.CooldownLength(spellID)` | plain number | M (talent functions), D |
| `VS.Charges(spellID, now)` | Belief charges, Belief next | M, D (unprobed) |
| `VS.Gcd(now)` | Belief end | P (`isOnGCD` edges), M |
| `VS.Aura(unit, spellID, now)` | Belief expiry, stacks (or nil) | O (out-of-combat or plain read), P (gate flips), M (cast + duration), D (DB2) |
| `VS.AuraAt(unit, filter, i, now)` | spellID, Belief, stacks, applied | As above. Index order is applied time ascending, then data order; only auras with est &gt; now |
| `VS.AuraGen(unit)` | integer | Bumped when that unit's aura set changes |
| `VS.Swing(h, now)` / `VS.LastSwing(h)` | Belief / plain | O (`PLAYER_SWING`), M (k·speed, paired rage steps), D |
| `VS.SwingSpeed(h, now)` | Belief | O (swing duration, out-of-combat read), D 2.0 |
| `VS.Haste(now)` / `VS.SpellHaste(now)` | Belief | Melee: O (out of combat) and M (base ÷ swing duration). Spell: O (last plain read), D |
| `VS.TargetCast(now)` | Belief cast end | O (start/stop events with `castBarID`), D (default length) |
| `VS.Health(unit, now)` + `VS.HealthMax(unit)` | Belief fraction, plain | Player: O (if plain), M (`UNIT_COMBAT` deltas), D 1.0. Target: P (Execute gate sets hi = 0.2), D |
| `VS.TTD(unit, now)` | Belief | D only (30 s, wide) |
| `VS.Speed(now)` | Belief | O (out of combat), M (moving events × 7), D 0 |
| `VS.Totem(slot, now)` | Belief expiry | O (out of combat), P (`PLAYER_TOTEM_UPDATE` with no cast means destroyed), M (cast), D |
| `VS.Enemies(now)` | Belief count | O (nameplate scan), D 1 |

The player's own casts and channels get no accessor: VGA keeps the passthrough.

Lifecycle:
- `VS.Start(frame?, api?)`: idempotent. Defaults are `CreateFrame("Frame")` and `_G`. The class is compiled at `PLAYER_LOGIN`.
- **Per-frame drive:** VS's own OnUpdate runs `Flush()` then `pcall(Update, GetTime())` every frame (as `App.lua:947-966` does).
- **Urgent lane:** inside VS's own handlers, `PLAYER_SWING`, our `UNIT_SPELLCAST_*`, usability and cooldown-flag events run Flush and Update synchronously.
- No VS code runs inside a consumer's call, and Phase 1 has no callbacks.
- `VS.SetFactsProvider(fn(classToken) → classData)`: before compile only; raises after.
- `VS.RegisterClass(data)`; `VS.Snapshot() → string` (allocates; debug only); `VS.SetDebug(on)` enables the rings.

## C. Class data format

```lua
local id = { ability = {}, aura = {}, res = {}, talent = {} } -- Class.lua fills it at compile; effects capture it
local E, W = VS.Effects, VS.DB2.WARRIOR
VS.RegisterClass({ class = "WARRIOR", id = id, gcd = 1.5,
  resources = { rage = { powerType = 1, max = 100, rest = 0, restRate = 1.25, regen = 0,
    swing = { [1] = function(s) return RATE[s.weaponSize[1]] or 4.5 end, [2] = offHandRate },
    ticks = { { interval = 1, value = 1, aura = "bloodrage" } } } },
  talents = { improved_slam = { id = W.improved_slam.ids[1], maxRank = 2 } },
  auras = { rend = { ids = W.rend.ids, unit = "target", tick = 3, maxStacks = 0,
    duration = function(s) return REND[s.rank[id.ability.rend]] or 9 end } },
  abilities = {
    rend = { ids = W.rend.ids, power = "rage", cost = W.rend.cost, gcd = 1.5, gate = "rend_ready",
      effect = function(s, t) E.applyAura(s, id.aura.rend, t) end },
    heroic_strike = { ids = W.heroic_strike.ids, onNextSwing = true, swingSpend = true,
      cost = function(s) return 15 - s.talentRank[id.talent.improved_heroic_strike] end } },
  rules = { healthGate = { ability = "execute", below = 0.2 } },
})
```

- **Ability fields:** `ids, power, cost, cooldown, gcd, cast, charges, recharge, onNextSwing, swingSpend, startsCombat, resetsSwing, gate, totem, effect`. Any number field may be a function `(s,t)`.
- **Aura fields:** `ids, unit, duration, maxStacks, tick, pandemic, family, gateWindow`.
- **Effect signature:** `effect(s, t) → nil`. It runs at success for an instant and at finish for a hard cast, after the core has charged the cost, started the cooldown and started the GCD. It mutates only these fields of `s`, through `E`: `res, auraExp, auraStacks, auraApplied, cdReady, charges, chargeNext, swingNext`. It reads `talentRank, rank, level, weaponSize, moving, combat`.
- The Warrior example ports `Warrior.lua:271-285` (rage models), `385-396` (stance swap), `468-511` (Heroic Strike, Rend, Execute).
- **DB2 numbers:** `Data/Spells.lua` is generated by `tools/gen_data.py`, copied from TDF with its `tools/data/*.json` and the `--check` hash mode. Rows have the same shape as TDF's `Spells.lua:1101`, under `VS.DB2.&lt;CLASS&gt;`. The DB2 SQLite input is not vendored.

## D. VGA policy layer

VGA gains a `virtual` status. It uses the policy when `LibStub("VirtualGameState-1.0", true)` exists at load, and otherwise keeps the current stub. Every policy uses `now = GetTime()` and returns shared tables that VGA preallocates. That is safe for Hekili: `GetUnpackedSpellCooldown` unpacks the table at once (`State.lua:2905-2909`).

| Stub(s) | Policy |
|---|---|
| `UnitPower` | Player: `floor(VS.Power(pt or UnitPowerType).lo)`. Other units: 0 |
| `GetPowerRegenForPowerType` | `est, est`. A swing-paid resource in combat returns `0, 0` (Hekili's swing model adds that rage) |
| `GetManaRegen` | `VS.Regen(0).est, VS.Regen(0, now, true).est` |
| `UnitHealth`, `UnitHealthMax` | Player: `VS.Health`·max. Target: est·100 over 100. Plates and pet: 100/100 when plain `UnitIsDead` is false, else 0 (keeps the `Targets.lua:434/511` scan working) |
| 12 stat stubs (`UnitStat`, `UnitAttackPower`, `UnitDamage`, `UnitArmor`, `UnitWeaponAttackPower`, `GetCombatRating(Bonus)`, `GetCritChance`, `GetRangedCritChance`, `GetSpellCritChance`, `GetSpellBonusDamage`, `GetMasteryEffect`) | `VS.Stats` fields in the real return order |
| `GetHaste`, `GetMeleeHaste` / `UnitSpellHaste` | `(VS.Haste.est − 1)·100` / `VS.SpellHaste.est` |
| `UnitAttackSpeed` | `VS.SwingSpeed(1).est`, then hand 2's est or nil |
| `GetUnitSpeed` | Player: `VS.Speed.est, 7, 7, 4.72`. Others: zeros |
| `GetTotemInfo` | Up: `true, name, start, duration, icon, 1, spellID`. Else `false, "", 0, 0, 0` |
| `GetBuffDataByIndex`, `GetDebuffDataByIndex`, `GetPlayerAuraBySpellID`, `GetAuraDataByAuraInstanceID`, `AuraUtil.ForEachAura`, `AuraUtil.FindAura` | Walk `VS.AuraAt` into one AuraData table per aura slot. `expirationTime` is `rec.lo` (the early bound). `auraInstanceID` is an invented stable integer. `points` is an empty table |
| `C_Spell.GetSpellCooldown` | 61304 or 29515 → `GcdInfo`. An ability whose `isOnGCD` is true → the same `GcdInfo.start/duration` numbers (bit-identical). Otherwise `start = est − len`, `duration = len`, `isActive = est &gt; now` |
| `GetSpellCharges` | `VS.Charges`, or nil for a spell VS gives no charges (what the real API returns) |
| `UnitCastingInfo`, `UnitChannelInfo` | Player passthrough. Target: `"Casting", "", 136243, start·1000, est·1000, false, castBarID, interruptible == 0, 0`, which feeds `Classes.lua:1645-1660` |
| `IsUsableSpell` | Alias of `C_Spell.IsSpellUsable` |
| **Stay stubs** | `UnitPartialPower` (no Forever user); `UnitGetTotalAbsorbs`, `UnitInRange` (no signal); `GetAuraSlots` (no consumer); `UnitAura`, `UnitAuraBySlot`, `GetItemGem`, `GetItemInfo`, `GetSpellBaseCooldown`, `GetSpellLink`, `Is{Harmful,Helpful,Passive}Spell`, `GetSpellLossOfControlCooldown` (absent on Forever); `GetSpellCastCount` (unprobed, unused); `CombatLogGetCurrentEventInfo` (Phases 2 and 3); `GetTalentInfoByID` (Hekili's talent loop moves to `VS.Talents`, cleanup Q9) |

## E. Clock and timing

- **Time base:** everything is absolute `GetTime()`. Each observation carries the `GetTime()` of its handler. `now` is a required argument on every accessor; VGA passes `GetTime()`.
- **Clock start:** the clock starts at the first observation (`Belief.lua:723-727`).
- **Lag clamp:** an observation older than the clock is applied at the clock with `lag` (`:733-736`).
  - A late ladder rung is moved by regen × lag, and dropped if it conflicts (`Resources.lua:278-290`).
  - A late exact read is widened by the regen spread × lag (`:365-372`).
  - Swing anchors use `t − lag`.
- **No backward projection:** if `now` is before the clock, `dt` is 0.
- **A consumer reading inside its own handler for the same event:** if VS's handler ran first, the read is current (urgent lane). If not, it gets the last Update projected to `now`: at most one event stale, and fixed by the next Update in the same frame. It never mutates anything.
- **Reads inside Hekili's update coroutine** are pure projections, so the "nests in a reset" hazard (feasibility C.2.3) cannot happen.

## F. Testing

- **Runner:** headless busted under Lua 5.1, both standalone and from Hekili's root.
- **Helpers in `spec/helpers/`:**
  - `fake_api.lua`: the SECRET proxy from TDF `tests/helpers/wow.lua:16-25`, plus a fake frame with `Fire(event, ...)` and `Tick(now)`.
  - `alloc.lua`: copied as is from TDF.
  - `replay.lua`: a trimmed TDF `tests/helpers/replay.lua` that asserts accessors instead of the view model.
  - A fake LibStub, from `VirtualGameAPI_spec.lua:36-48`.
- **Ported specs:** `obslog_spec`; the resources part of `belief_spec`; `belief_swing_spec`; and `secrets_spec` (a static check that every Sources read goes through `Plain`).
- **Zero allocation:** 10,000 mixed events (`PLAYER_SWING`, `UNIT_POWER_FREQUENT`, usability, casts, `UNIT_AURA`) with Update every tick and every accessor and VGA policy called. The test asserts `alloc.bytes == 0`, which measures `collectgarbage("count")` with the collector stopped.
- **Three golden scenarios:**
  1. `tests/model/swing_replay_spec.lua:96`: swing anchors from rage steps every 2.6 s with casts interleaved.
  2. `tests/model/belief_spec.lua:568` with `:197`: the cost ladder bounds rage, and regen is measured between pins net of our own spends.
  3. `tests/model/belief_spec.lua:401`: cooldowns snap to the game's ready flags.
- **VGA spec additions:** `virtual` becomes a valid status; when VS is absent the current tests stay the same; the GCD bit-identity assertion.
- **In-game checkpoint (Hekili alone, then TDF alone):**
  - `/reload` gives no errors and no popup.
  - Out of combat, `/dump LibStub("VirtualGameState-1.0").Snapshot()` shows WARRIOR, the talent ranks, and rage with basis `default` at est 0.
  - After 60 s on a dummy:
    - rage moves between `pinned` and `modelled`, its interval is mostly 15 wide or less, and it contains the rage bar's value;
    - the main-hand swing basis is `observed`, with speed equal to the weapon speed ±0.01;
    - Rend's expiry is within 0.2 s of the debuff timer;
    - Hekili recommends spenders;
    - `VGA.Status("UnitPower") == "virtual"`.

## G. Risks and open questions

1. **Hekili never rescans auras in combat.** Its `UNIT_AURA` handler tests the secret `data.isFullUpdate` (`Events.lua:1269`), and that handler is the only thing that sets `state[unit].updated` (`State.lua:6199-6204`). **Decision:** a Phase 3b Hekili edit: the handler never reads the payload and sets `updated` when `VS.AuraGen` changes.
2. **Event order between VS's frame and Hekili's.** **Probe:** stamp `debugprofilestop()` in both `PLAYER_SWING` handlers. If Hekili's fires first, accept the one-event staleness.
3. **Rage counted twice** (VGA regen plus Hekili's swing model). **Closed by** the 0-in-combat rule in D; confirm on the dummy by comparing Hekili's forecast with the next VS pin.
4. **Returning `lo` for resources may make Hekili too passive near costs.** **Probe:** log picks on a dummy where lo &lt; cost ≤ est. **Decision:** choose lo or est per resource as a VGA constant.
5. **`/reload` in combat loses the belief** (TDF `Persist.lua` is not ported). **Decision:** defer to Phase 1b; until then reads start wide.
6. **Two embedders or two facts providers.** LibStub's highest minor wins. `SetFactsProvider` raises after compile.
7. **DB2 drift.** The plain out-of-combat `GetSpellPowerCost` overrides `cost`, and Snapshot lists mismatches. `gen_data.py --check` runs in CI.
8. **Target cast length is unknown** (its spellID and times are secret). **Probe:** time the target's START, STOP and INTERRUPTED events by `castBarID`. **Decision:** the default length.

## H. Phase outlines (deferred)

**Phase 2 investigation:** `docs/research/&lt;date&gt;-vgs-eventing.md`.
- **Questions:**
  - Which Hekili consumers need events rather than reads: feasibility B.2 E2-E9 and W1-W3, `UNIT_AURA`, `UNIT_POWER_FREQUENT`, the target's `UNIT_SPELLCAST_*`. Would TDF gain anything (view-model invalidation)?
  - For each one, is a synthesised event cheaper than a read plus an edit? Count the edits saved.
  - Which of [V]'s 137 combat-log rows VS can emit, split into synchronous observed rows and late inferred ones. What timestamp policy: back-dated `GetTime` during delivery, or synchronous only? Does the B.4 payload contract hold?
  - `UNIT_AURA` synthesis: `isFullUpdate` only, or added/updated/removed instance IDs from `AuraGen` diffs?
  - `RegisterEvent` diversion: an environment `CreateFrame` wrapper, or the edit at `Events.lua:163`? Does a diverted registration avoid the popup (cleanup Q5)?
  - How retractions (a dodge becomes `SPELL_AURA_REMOVED`) reach the across-reset caches.
- **Inputs:** feasibility B, C.2 and D.3; [V]; cleanup §5 Q3-5; Phase 1 Snapshot logs from a dummy and a dungeon; the event-order probe.
- **Decision it produces:** go or no-go per event family, plus the subscription shape needed (push or pull).

**Phase 3 plan:** `docs/superpowers/plans/&lt;date&gt;-vgs-event-bus.md`.
- **Questions:**
  - Subscription API: `VS.Subscribe(event, fn, owner)` or frame diversion.
  - Preallocated payload pools.
  - Queue model: a ring per subscriber, or one shared ring with cursors.
  - Lanes: urgent synchronous, and deferred with back-dated time.
  - Delivery point: VS's OnUpdate, never nested in a consumer call.
  - Re-entrancy and drop policy (`ns.callHook` drops re-entrant calls, `Classes.lua:3883`), and overflow counters.
  - Queue readers: a Hekili adapter (feeds `CLEU_HANDLER` and `CombatLogGetCurrentEventInfo`, synthesises `UNIT_AURA`) and a TDF adapter.
  - Tests: zero allocation per delivered event, and golden ordering tests.
  - Which Phase 1 edits it retires.
- **Inputs:** Phase 2's decisions and the Phase 1 code.
- **Produces:** a task-by-task plan with checkpoints.

I skipped TDF's Persist, Items, Gear (beyond weapon size), Group and Options families, and I did not read the full Sources files or every TDF test. The test line numbers above come from `it(` greps. The biggest risk is G1: until Hekili's `UNIT_AURA` handler is fixed, VS aura data never reaches Hekili in combat.

### Critical Files for Implementation
- /home/zack/src/TacoDogForever/src/TacoDogForever/Model/Belief.lua
- /home/zack/src/TacoDogForever/src/TacoDogForever/Model/Belief/Resources.lua
- /home/zack/src/TacoDogForever/src/TacoDogForever/Model/Belief/Swing.lua
- /home/zack/src/TacoDogForever/src/TacoDogForever/Sources/Sources.lua
- /home/zack/src/hekili/Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua
