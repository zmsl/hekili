<!-- Research output saved verbatim from the 2026-10-14 planning session (sonnet Explore agent, read-only survey of ~/src/TacoDogForever): the TDF port-mapping facts the VirtualState spec cites. Written when the target was still a standalone library; the port targets are now `VirtualState/` inside Hekili. -->

# TDF port-mapping facts for VirtualGameState-1.0

Path prefixes: `E` = `src/TacoDogForever/Engine`, `M` = `src/TacoDogForever/Model`, `S` = `src/TacoDogForever/Sources`, `W` = `src/TacoDogForever_Warrior`, `D` = `src/TacoDogForever_Data`, `T` = `tests`. I read the files but did not run `make check` or the specs.

## 1. Class model format

A pack calls `ns.NewSpec{key,gcd,gcdTime,tank}` (E/NewSpec.lua:491). It then registers `RegisterResources/Auras/Abilities/Talents/Events/GameEvents/Procs/Pets/Gear/Hook/Usable/Tracker/Include`. `Definition()` (NewSpec.lua:477) returns a plain table that `SpecBuilder.Build` turns into the state class.

| Item | Fields / behaviour | Cite |
|---|---|---|
| Ability fields | `id copy variants gcd gcdTime spend spendType cast cooldown charges recharge usable handler flipsAt reads start impact travel toggle known startsCombat essential aura onNextSwing swingSpend talent notalent readyTime timeToReady nobuff nodebuff icd buff debuff nomounted nocombat spec noOverride max_targets channeled tick_time tick finish breakchannel dual_cast spendPerSec spend2 spendType2 baseProbe item items bagItem slot equipped category categoryCooldown interrupt rangeSpell cycle` | E/SpecBuilder/Fields.lua:227-293 |
| Ability meanings | cost = `spend`+`spendType` (scalar, function, or a fraction 0..1 of `resBase`); cooldown = `cooldown`, or `charges`+`recharge`; gcd = `Enum.Gcd.Spell/Fixed/Off` (default Spell) plus `gcdTime` | E/SpecBuilder.lua:737-747, 755-790 |
| Ability meanings (cont.) | `cast` seconds; `handler(s)`; swing = `onNextSwing` + `swingSpend`; `usable(s)` per ability plus a spec-level `RegisterUsable(fn(s,t,id,ability))`; `known` = `false`, a function, or a spell ID, else the `s.known[id]` flag; rank = `s.rank[id]` (1 = `id`, 1+k = k-th `copy`) | NewSpec.lua:164, 173; E/SpecBuilder/Ready.lua:178-188; E/SpecBuilder.lua:67 |
| Aura fields | `key id copy duration tick_time max_stack unit shared pandemic family family_rank alias aliasMode aliasType onRemove generate totem cooldownOverride`. `duration` is a number &gt;0 or `function(s)`. `pandemic` is 0..1, default `Helpers.PANDEMIC` 0.3. `max_stack` is &gt;=1. | Fields.lua:205-226; validation at 660-720 (`duration` check 667-670); E/Helpers.lua:16; E/SpecBuilder.lua:1155 |
| Handler writes | `H.applyBuff/applyDebuff/removeBuff/addStack/removeStack` write `auraApplied/auraExp/auraStacks`. `H.gain/spend` write `res` and `resWindowEnd`. | E/Helpers.lua:274-413, 612-660 |
| Handler writes (cont.) | `H.setCooldown/reduceCooldown` write `cdReady`. `gainCharges/syncCharges` write `charges` and `chargeNext`. `H.summonPet` writes `petExp`. `H.queue/resetSwing` write the event queue and `swingNext`. | Helpers.lua:1519-1617; E/Timeline.lua:61, 192 |
| Use step (generated, not pack-written) | Spend and cooldown/charges are written first. `opening` then writes `gcdEnd`, `prevGcd/prevOffGcd/prevAll` and `lastCast`. | E/SpecBuilder/Use.lua:57-106, 206-219 |
| Pack hooks | `reset_precast`, `time_to_ready`, plus chained `runHandler/prespend/spend/pregain/gain` | NewSpec.lua:284-315 |
| Generic example pack (use this, not Warrior, for the port) | One-file neutral pack covering resources, auras and abilities | T/helpers/model_def.lua:11-73 |

The pack is `W/Warrior.lua` plus `W/Gates.lua`, `W/Protection.lua` and `W/Register.lua`. Verbatim Rend ability (W/Warrior.lua:485-493):

```lua
rend = base(spell.rend, {
    startsCombat = true,
    stance = "battle|defensive",
    gate = gateOf("rend"),
    handler = function(s)
        H.applyDebuff(s, debuff.rend)
    end,
}),
```

`base()` (W/Warrior.lua:351-370) fills `id`, `copy`, `spend`, `spendType`, `gcd` and `cooldown` from the data record. `stance` and `gate` are pack-declared via `RegisterAbilityFields` (W:~320).

## 2. Belief families

All are registered through `ns.BeliefShared`. The registration API is in M/Belief.lua:98-166: `Applier(kind)`, `Reader(readOf)`, `Writer`, `Listener(kind)`, `Init`, `FinalWriter` and `Serial`. The TOC load order is M/Belief.lua first, then Resources, Auras, Casts, Targets, Options, History, Ranks, Events, Swing, Talents, Player, Target, Usable, Pets, Gear, Items, Persist (TacoDogForever.toc:50-67).

| File | Purpose | Registers | Writes (snapshot `s` unless noted) |
|---|---|---|---|
| M/Belief/Resources.lua | Cost ladder, exact reads, regen calibration | `Applier` Usable:327, PowerTick:378; `Reader` Resource:365, Max:487, Base:496, Regen:516, CastRegen:539, Rest:554; `Listener` PlayerInfo:505, CastStart/CastSuccess:568; `Init` 319, 420, 447; `Writer` 574, 604 | `res resMax resBase resRegen resLastTick resCastRegen resWindowEnd` |
| M/Belief/Auras.lua | Aura reads | `Reader` Aura/TargetAura:33-34; `Writer`:37 | `auraApplied auraExp auraStacks` |
| M/Belief/Casts.lua | Our casts run the use step; cooldown flips | `Applier` CastStart:226, ChannelStart/Update/Stop:269-307, CastDelay:329, CastSuccess:340, CastStop:376, Cooldown:385, Queued:391; `Writer` 396, 448 | `cdReady charges chargeNext castEnd castKind channelStart channelTick` |
| M/Belief/Targets.lua | Per-target aura memory, combat start/end | `Applier` TargetSwap:147, TargetGone:152, CombatStart:161, CombatEnd:168, Enemies:184; `Writer`:193 | `activeDotOther`; clears `auraExp/auraStacks` |
| M/Belief/Options.lua | Known flags, group, toggles | `Applier` Known:28, Group:41; `Writer`:52; `FinalWriter`:72 | `known toggle off abToggle rangeFilter cycleOn` |
| M/Belief/History.lua | Cast history | `Writer`:12 | `lastCast prevGcd prevOffGcd prevAll` |
| M/Belief/Ranks.lua | Known rank, queued flag | `Writer`:8 | `rank queued` |
| M/Belief/Events.lua | Pending impacts and pack callbacks | `Writer`:14; no-op `Applier` PackEvent:26 | event queue via `Timeline.Push` |
| M/Belief/Swing.lua | Per-hand swing clocks and income | `Applier` Swing:602; `Listener` Queued:596, CastStart:637, CastSuccess:643, PowerTick:656, CombatStart:710, CombatEnd:723; `Writer`:742 | `swingNext swingSpeed swingScale res` |
| M/Belief/Talents.lua | Rank by source (tree, declared, rank spells) | `Applier` Talent:39; `Writer`:71 | `talentRank` |
| M/Belief/Player.lua | Haste, GCD cadence, movement, player facts | `Applier` Haste:130, Moving:194, PlayerInfo:201; `Listener` CastSuccess:168, CastStart:188, CombatEnd:216; `Writer`:221 | `moving mounted level aggro zone` |
| M/Belief/Target.lua | Target facts, encounter, target cast, range | `Applier` TargetInfo:71, Encounter:82, GameError:90, Range:93, TargetCast:103; `Listener` TargetSwap:59; `Writer` 127, 182, 185 | `targetLevel boss encounter`, target-cast fields, range |
| M/Belief/Usable.lua | The game's "not usable" gate | `Listener` Usable:31; `FinalWriter`:41 | `usable` |
| M/Belief/Pets.lua | Pets and totems | `Applier` Pet:35, Totem:57; `Writer`:102 | `petExp petExists petDead`, totem `auraApplied` |
| M/Belief/Gear.lua | Worn gear, weapon facts | `Applier` Gear:22; `Writer`:70 | `gearCount weaponSize weaponType offHandShield` |
| M/Belief/Items.lua | Item counts and cooldowns | `Applier` ItemCooldown:37; `Reader` ItemCount:56; `Writer`:81 | `itemCount itemCd cdReady` |
| M/Belief/Persist.lua | Reload record (`Persist.Write/Restore`) | Consumes the `Serial` lists | SavedVariables, not state |

`Shared.Serial` is also declared in Target:88, Casts:107, Talents:23, Resources:484 and Swing:162, plus the hub (Belief.lua:166).

**Belief.lua calls**
- `Belief.New(spec, def)` is at :303. It runs the `Init` callbacks.
- `Belief.Update(B, log, now)` is at :720. Per observation it does: `Shift`, `advance(B,t)` (:594), `apply` (:634, applier or reader, then listeners), then the trackers' `observe`. After the loop it runs `advance(B,now)`, `constrain` (:652, cooldown flips) and `sync` (:687, belief records).
- `Belief.Write(B, s, bound)` is at :830. Order: writer parts, scalars, trackers' `write`, `generate` auras, `FinalWriter`s.
- `ConfirmAura` is at :770 and `DropAura` at :781.

**Frame-loop callers**
- `advance`, `constrain` and `sync` are file-local. Only `Update` and `Write` are called from outside.
- Game/App.lua frame: `now = api.GetTime()` (App.lua:945), `sources:Flush()` (:947), then `pcall(Belief.Update, belief, log, now)` (:963) only if the driver is idle and the log is at least 75% full. `drainAt = floor(LOG_CAP*0.75)` (:607, cap 256 at :26).
- The normal path is `Model.NewRecalc` unit 1 (M/Recalc.lua:33-35, wired at App.lua:481-490), with `Sources:Poll(GetTime())` run first (:490).
- `Belief.Write` is called by `Model.Simulate` (M/Run.lua:64) as `spec.reset(snap); Belief.Write(B,snap,b); spec.copy; Sim.Run`.

**Clock**
- The belief state `B.s.now` and every observation's `t` use absolute `GetTime()` (Belief.lua:15-16, App.lua:945).
- `Write` rebases to a relative snapshot clock where 0 = belief `now`, through `Shared.rel` (Belief.lua:817). `NEVER` and `HUGE` stay as they are. Example: `s.gcdEnd = bs.gcdEnd - now` (:836); History:12-19.

## 3. ObsLog and Sources API

**ObsLog** (M/ObsLog.lua). Preallocated ring, no allocation on `Add`.

| Function | Cite |
|---|---|
| `ObsLog.New(cap)` errors if cap&lt;1; returns `{cap,head,n,dropped,obs}` | :24 |
| `ObsLog.Add(log,kind,t,a?,b?,c?)` drops the oldest when full and bumps `dropped` | :38 |
| `ObsLog.At(log,i)` is the i-th oldest; the record is reused | :57 |
| `ObsLog.Shift(log)` pops and returns the oldest; the record is reused | :65 |
| `ObsLog.Clear(log)` sets `head=1, n=0` | :79 |

An observation is `{kind,t,a,b,c}`. `Enum.Obs` has 34 kinds, listed with field meanings at E/Enum.lua:70-114.

**Sources** (S/Sources.lua)

| API | Signature | Cite |
|---|---|---|
| `Sources.New` | `New(opts{api,spec,def,log,mark?})`; errors `"TacoDog: Sources.New needs { api, spec, def, log, mark }"` | :251 |
| `Sources.Stage` | `Stage(self,kind,t,a,b,c) -&gt; bool`; false if `STAGE`=128 is full | :~530 |
| `S:Flush()` | Runs the `BeforeFlush` hooks, then moves the staged observations into the log | :553 |
| `S:Poll(now)` | Runs the polls registered with `Sources.Poll(order, fn(self,now))`, sorted by `order` | :594 (reg. ~:566) |
| `Sources.Plain` | `Plain(api, v)`: nil if `api.issecretvalue(v)` | :41 |
| `Sources.EVENTS` | event -&gt; `true` (player unit) / `"target"` / `false` | :56-125 |
| `Sources.SelftestLines` | `SelftestLines(self,out,belief)`; registered with `Sources.Selftest(fn)` | :~515 (reg. :~507) |

The other registration points are:
- `Sources.On(event, fn(self,t,unit,a2,spellID,a4,event,a5))`
- `Sources.Also`
- `Sources.Init`
- `Sources.BeforeFlush`
- `Sources.Defer`
- `Sources.Stub`

Events are dispatched by `OnEvent`. The `mark(kind,urgent)` callback is how Sources ask for a recalculation.

**Injection.** `api` is `_G` in game and the fake from `tests/helpers/wow.lua` in tests (App.lua:452 passes `api`). `Boot.lua` is the only file that reads globals (.luacheckrc:3-4). Every client value goes through `Plain`; `T/game/secrets_spec.lua` enforces this statically.

**Client functions Sources read** (grep of `api.*` in `S/*.lua`; the fake defines them at wow.lua:432-860):
- Core: `issecretvalue` (56 uses), `GetTime`, `InCombatLockdown`, `UnitAffectingCombat`, `Enum.PowerType`, `GetFramerate`.
- Units and facts: `UnitGUID`, `UnitExists`, `UnitIsUnit`, `UnitIsDead`, `UnitIsFriend`, `UnitIsPlayer`, `UnitCanAttack`, `UnitLevel`, `UnitEffectiveLevel`, `UnitClassification`, `UnitName`, `UnitThreatSituation`, `GetNumGroupMembers`, `IsInRaid`, `IsMounted`, `GetUnitSpeed`, `GetInstanceInfo`.
- Casting: `UnitCastingInfo`, `UnitChannelInfo`.
- Power and haste: `UnitPower`, `UnitPowerMax`, `UnitPowerDisplayMod`, `GetComboPoints`, `GetPowerRegenForPowerType`, `GetManaRegen`, `GetMeleeHaste`, `UnitSpellHaste`, `UnitAttackSpeed`.
- Gear and totems: `GetInventoryItemID`, `GetTotemInfo`, `ItemLocation`.
- `C_Spell`: `IsSpellUsable`, `GetSpellCooldown`, `IsSpellInRange`, `IsCurrentSpell`, `GetSpellPowerCost`.
- `C_SpellBook`: `IsSpellKnown`, `IsSpellKnownOrInSpellBook`.
- `C_UnitAuras`: `GetPlayerAuraBySpellID`, `GetUnitAuraBySpellID`, `GetAuraDataByIndex`.
- `C_Item`: `IsUsableItem`, `GetItemCount`, `GetItemCooldown`, `GetItemSpell`, `GetItemID`, `IsEquippedItem`, `DoesItemExist`, `IsItemDataCachedByID`.
- Talents and misc: `C_Traits.*`, `C_ClassTalents.GetActiveConfigID`, `C_TooltipInfo.GetSpellByID`, `C_CVar.GetCVarBool`.

The `REQUIRED` selftest list at Game/App.lua:51-99 is the authoritative minimum set.

## 4. Test harness

| Item | Fact | Cite |
|---|---|---|
| Runner | `.lua/bin/busted`; `.busted` sets `ROOT={"tests"}`, `pattern="_spec"` | .busted:1-6; Makefile:2-4 |
| `make check` | `lint fmt-check typecheck test pytest data-check apl-check apiref-check` | Makefile:70 |
| `make parity` | `PARITY_REPORT=1 busted --tags=parity`; specs tagged `#parity` come from `T/parity_spec.lua` and `T/helpers/parity.lua` | Makefile:28-29; T/parity_spec.lua:4 |
| `make ci` | `check` plus `coverage`; each of Engine/Refresh/Model/Sources/Render/Views/Game must reach &gt;=90% via `tools/coverage_gate.lua` | Makefile:52-62 |
| Layout | `tests/{model,game,engine,refresh,warrior,druid,apl,template,tools}` plus `helpers/`. Model specs are about 30 files (`belief_*`, `obslog_spec`); Sources specs are `game/sources_*_spec`. | |
| Allocation tests | `T/helpers/alloc.lua:7-33`: `alloc.bytes(fn,iters)` does 200 warm-ups, `collectgarbage` collect x2 then `stop`, and measures `count` delta. 59 spec files use it, e.g. `obslog_spec` and `belief_spec`. | |
| luacheck | `std="lua51"`, `max_line_length=120`, `files["tests/"]={std="+busted"}`; excludes `Generated/**` and `Libs/**` | .luacheckrc:6-9 |
| luacheck (cont.) | The Data addon alone may write the `TacoDogForeverData` global; the core never reads it. | .luacheckrc:11-17 |
| Toolchain | `scripts/bootstrap.sh` (hererocks Lua 5.1.5, luarocks 3.8.0, busted 2.3.0-1, luacheck 1.2.0-1, luacov 0.17.0-1); `mise.toml` (stylua 2.5.2, lua-language-server 3.19.1) | |
| CI | `.github/workflows/*.yml`: `make bootstrap`, then `make ci` | |

**Helpers to copy for headless Model and Sources specs**
- `T/helpers/load.lua`. It reads each addon's TOC, so give the new repo a TOC listing the library files. `load.packs()` shells out to `tools/packs/*.lua` and can be dropped. `load.data()` is only needed if you keep a data addon.
- `T/helpers/wow.lua` (900 lines): the fake client and `ctl`, including the `SECRET` proxy.
- `T/helpers/alloc.lua`.
- `T/helpers/model_def.lua`: the neutral pack for belief specs.
- `T/helpers/game_def.lua` (15 lines): wraps `model_def` for Sources specs.
- Optional: `swing_def.lua` (7 specs), `items.lua` (5), `replay.lua` (3), `player_client.lua`, `pet_client.lua`, `client.lua` (the boot harness). `client.lua` needs `Boot.lua`, so skip it.
- Skip: `parity.lua`, `warrior.lua`, `feral.lua`, `engine_def.lua`, `test_def.lua`, `shared_content.lua`.

Hidden coupling: `model_def` and `game_def` build specs through `ns.NewSpec`, `SpecBuilder` and `Helpers`. So "port the belief and class model" drags in `Engine/{Codegen,Enum,Helpers,Forecast,Timeline,SpecBuilder*,Generated/GameEnums}` (TOC lines 9-19). `Belief.lua` itself binds `Timeline`, `SpecBuilder`, `ObsLog`, `Helpers` and `Forecast` (Belief.lua:28-31).

## 5. Data addon

| Item | Fact | Cite |
|---|---|---|
| Path | `D/Generated/Spells.lua`, 1223 lines, 300,850 bytes | |
| Other files | `D/Publish.lua` (78 lines, defines the one global `TacoDogForeverData`), `D/Shared/{Items,Racials}.lua`, and the TOC (LoadOnDemand) | D/TacoDogForever_Data.toc |
| Header | `-- GENERATED by tools/gen_data.py. Do not edit`; DB2 build `1.60.1.70338`; input/body sha256 | Spells.lua:1-4 |
| Tables | `ns.family` (non-stacking aura families, :9-21); `ns.auraGroup` (:24-28); `ns.&lt;CLASS&gt;` for 9 classes (WARRIOR at :1061); `ns.RACIAL` (:1170); `ns.ITEM` (:1214) | |
| Record shape (`TacoDogSpellRecord`) | `name skill ids[] (all ranks, lowest first) variants? maxRank? power cost costPct cast duration durationPerCombo? cooldown cdCategory gcd maxStacks dispel school range family? family_rank? races?` | D/Publish.lua:~19-45 |
| Example | `rend = { ... ids={772,6546,6547,6548,11572,11573,11574}, power="rage", cost=10, cast=0, duration=21, cooldown=0, gcd=1.5, maxStacks=0, school=1, range=5 }` | Spells.lua:1143 |
| Generator | `tools/gen_data.py` (`make data`; `--check` needs no DB and is in `make check`). Reads the Forever DB2 SQLite (`$WOW_DB2`) plus `tools/data/{classes/*.json,general,overrides,families,aura_groups,races,items}.json`. | gen_data.py:1-50, :63, :856; Makefile:20-24 |
| Consumers | Packs read `TacoDogForeverData.WARRIOR.rend` (W/Warrior.lua:16); the core never does (CLAUDE.md "Layout") | |

Ranks live in `ids[]`, durations by rank are pack code (`ns.REND_DURATIONS`, W/Warrior.lua:~65), and there is no per-rank cost table.

## 6. Licence and credits

- **No `LICENSE` or `COPYING` file exists at the repo root.** `ls LICENSE* COPYING*` found nothing; the only licence text is `Libs/Ace3-LICENSE.txt` (Options addon).
- `CREDITS.md:1-14` credits four sources:
  - Hekili (adapted APL compiler, spec style and sim loop; reuse permission is being requested, and nothing from Hekili is to be published before it is granted).
  - Catnip by Durts (Forever secret-value research and display techniques, used with permission).
  - Blood in the Water (the AuraContainer technique).
  - Zachary Samsel (`excess_e` model).
  - It also credits Ace3, embedded under the limited BSD licence.
- `CLAUDE.md:43-44` rule: credit Catnip and Hekili in file headers wherever their code or data is used, and don't publish ported Hekili code before permission.
- **No Catnip or Durts text appears in any `src/` or `tests/` Lua header.** Hits are only in `CREDITS.md`, `README.md:87-89` and `spikes/` (spike files carry "adapted from Catnip by Durts ... used with permission"). The `src/` files with real Hekili wording are in the clean-room risk list below.
- **Hekili-derived files (clean-room risk)**, because they carry Hekili vocabulary or mimic its behaviour:
  - Whole files: `E/NewSpec.lua:1-7`, `M/Belief.lua:2`, `M/Snapshot.lua:1`, `M/Belief/Options.lua:4`, `S/Sources.lua`, `S/Spellbook.lua`, `E/Sim.lua`, `E/Timeline.lua`, `E/Forecast.lua`.
  - Single lines: `M/Belief.lua:71` (false start) and `M/Belief/Casts.lua:372`.
  - The recorded design analysis is `docs/research/2026-10-12-eval-hekili-*.md` and `docs/research/2026-10-12-hekili-state-engine-matrix.md`.

A ported library should carry the credits block and the Hekili permission caveat, and should cite Catnip wherever display or secret-value techniques come along. `Plain` and `issecretvalue` handling is the Catnip-adjacent part.

Not checked: a few line cites marked `~` (the exact line of `Sources.Stage`, the Poll registration and `Selftest`) are approximate. I did not open the `docs/class-packs/*.md` guides, which may have the authoritative field table. Risk: the "port" is not self-contained, because Belief/Sources need `Enum`, `Helpers`, `Timeline`, `SpecBuilder` and the generated state class, and `Boot.lua`/`Game/` own the frame loop you would have to re-create.
