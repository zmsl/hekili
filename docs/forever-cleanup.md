# Forever cleanup report

Branch `forever-cleanup` (base `forever` at 36daec38, head a49f9f9e before this report), 2026-10-14. Phase 2 of the
Hekili-on-Forever port: the `VirtualGameAPI-1.0` facade, every game read routed through it, every embedded library
vendored, the retail content archived or removed, a load-only Warrior stub (spec 1491), TOC interface 16001.

Readers: the project owner, and the implementers of Phase 1 (virtual game state) and Phase 3b (the shim and the real
Warrior class file). Detail lives in `docs/forever-facade-notes.md` (the inventory, one row per name) and
`Libs/CREDITS.md`.

| Commit | Task |
|---|---|
| fce79adf | plan |
| e72eb898, 3ecb5f02 | 1: Forever `.luacheckrc`; game API names stay undeclared; facade boundary documented |
| 7baef3fc | plan amendment: vendor every embedded library |
| 72432284, 10960465 | 2: API inventory (`tools/api_inventory.txt`, notes table), `tools/list_api_reads.sh` |
| e03b3110, 3bdc8404 | 3: `VirtualGameAPI-1.0` skeleton, headless busted tests (stub test records calls) |
| f7985b3d, 4204b99c, 5022d894, fe59c015, 4fe10bd3, e07d1c5b | 4-9: route every read through the facade (Hekili/Utils/Constants/Formatting/editor, State, Events, Classes/Targets, UI/Scripts/Core, Options) |
| 307815af | 10: `tools/check_api_reads.sh`; facade notes for Phase 3b |
| 632dbb1a | 19: TOC 16001, libraries vendored and pinned (`Libs/CREDITS.md`) |
| 1906de33 | 11: expansion and retail class folders moved to `archive/`, unloaded, history kept |
| 144df3cc | 11b: `Forever/Warrior.lua`, load-only stub registering spec 1491 |
| 198226cf | 12: Events |
| 8316a83a | 13: State |
| 147913a3 | 14: Constants |
| dcf8b294 | 15: Classes |
| b09e746b | 16: Utils |
| 1641d8e2 | 17: UI |
| e18579dd | 18: Options |
| a49f9f9e | 20: `.luarc.json` and the post-cleanup sweep (Checkpoint B) |

## 1. Facade status

`Libs/VirtualGameAPI-1.0/VirtualGameAPI-1.0.lua`: `grep -c '^passthrough('` and `grep -c '^stub('`.

| Status | Count | Meaning |
|---|---|---|
| passthrough | 125 | calls the real function unchanged |
| stub | 51 | returns a fixed safe shape, never calls the client (`VGA.Stubs()`) |
| missing | 0 expected | a passthrough whose real function is nil on the client; known only at runtime (`VGA.Status(name)`). All 125 are present on Forever per the inventory, but 7 are deprecation shims (`HasOverrideActionBar`, `HasVehicleActionBar`, `IsActionInRange`, `IsPlayerSpell`, `IsSpellKnown`, `IsSpellKnownOrOverridesKnown`, `SpellIsSelfBuff`) that become missing when `loadDeprecationFallbacks` is off |
| total | 176 | equals the line count of `tools/api_inventory.txt`; `list_api_reads.sh` output matches it exactly |

Of the 125 passthroughs, 15 are undocumented C globals whose presence rests on Forever FrameXML evidence.

Every stub, with the shape it returns (from the notes' "Stub returns" column):

| Name | Stub returns | Hekili call sites |
|---|---|---|
| `AuraUtil.FindAura` | `nil` | Utils.lua |
| `AuraUtil.ForEachAura` | no-op, returns nothing | Hekili.lua, Events.lua |
| `C_Spell.GetSpellCastCount` | `0` | State.lua, Options/DevTools.lua |
| `C_Spell.GetSpellCharges` | shared table `{ currentCharges = 1, maxCharges = 1, cooldownStartTime = 0, cooldownDuration = 0, chargeModRate = 1 }` | State.lua, Options/DevTools.lua |
| `C_Spell.GetSpellCooldown` | shared table `{ startTime = 0, duration = 0, isEnabled = true, modRate = 1, isActive = false, isOnGCD = false }` | State.lua, Events.lua, Options/DevTools.lua, UI.lua |
| `C_Spell.GetSpellLossOfControlCooldown` | `nil` | State.lua |
| `C_UnitAuras.GetAuraDataByAuraInstanceID` | `nil` | Events.lua |
| `C_UnitAuras.GetAuraSlots` | `nil` (no continuation token, no slots) | State.lua |
| `C_UnitAuras.GetBuffDataByIndex` | `nil` | Hekili.lua, Utils.lua, State.lua |
| `C_UnitAuras.GetDebuffDataByIndex` | `nil` | Hekili.lua, Utils.lua, State.lua |
| `C_UnitAuras.GetPlayerAuraBySpellID` | `nil` | Utils.lua, State.lua, Events.lua, Options/DevTools.lua |
| `CombatLogGetCurrentEventInfo` | `nil` | Events.lua, Options/DevTools.lua |
| `GetCombatRating` | `0` (every return) | State.lua |
| `GetCombatRatingBonus` | `0` (every return) | State.lua |
| `GetCritChance` | `0` (every return) | State.lua |
| `GetHaste` | `0` (every return) | Targets.lua |
| `GetItemGem` | `nil` | State.lua |
| `GetItemInfo` | `nil` | State.lua |
| `GetManaRegen` | `0, 0` | State.lua |
| `GetMasteryEffect` | `0` (every return) | State.lua |
| `GetMeleeHaste` | `0` (every return) | State.lua |
| `GetPowerRegenForPowerType` | `0, 0` | State.lua |
| `GetRangedCritChance` | `0` (every return) | State.lua |
| `GetSpellBaseCooldown` | `nil` | Options/DevTools.lua |
| `GetSpellBonusDamage` | `0` (every return) | State.lua |
| `GetSpellCritChance` | `0` (every return) | State.lua |
| `GetSpellLink` | `nil` | State.lua |
| `GetTalentInfoByID` | `nil` | Events.lua |
| `GetTotemInfo` | `false, "", 0, 0, 0` | State.lua |
| `GetUnitSpeed` | `0, 0, 0, 0` | State.lua, Targets.lua |
| `IsHarmfulSpell` | `false` | Options/DevTools.lua |
| `IsHelpfulSpell` | `false` | Options/DevTools.lua |
| `IsPassiveSpell` | `false` | Options/DevTools.lua |
| `IsUsableSpell` | `false` | State.lua |
| `UnitArmor` | `0` (every return) | State.lua |
| `UnitAttackPower` | `0` (every return) | State.lua |
| `UnitAttackSpeed` | `2, nil` (keeps `UnitAttackSpeed("player") > 0` at load true) | State.lua, Events.lua, Classes.lua |
| `UnitAura` | `nil` | State.lua |
| `UnitAuraBySlot` | `nil` | State.lua |
| `UnitCastingInfo` | the real call when `unit == "player"`, else `nil` | State.lua, Events.lua, Classes.lua, UI.lua |
| `UnitChannelInfo` | the real call when `unit == "player"`, else `nil` | State.lua, Events.lua, Classes.lua, UI.lua |
| `UnitDamage` | `0` (every return) | State.lua |
| `UnitGetTotalAbsorbs` | `0` | State.lua, Classes.lua, Targets.lua |
| `UnitHealth` | `0` | Utils.lua, State.lua, Targets.lua |
| `UnitHealthMax` | `0` | Utils.lua, State.lua, Targets.lua |
| `UnitInRange` | `false, true` | State.lua |
| `UnitPartialPower` | `0` | State.lua |
| `UnitPower` | `0` | State.lua, Events.lua |
| `UnitSpellHaste` | `0` (every return) | State.lua, Options/DevTools.lua |
| `UnitStat` | `0` (every return) | State.lua |
| `UnitWeaponAttackPower` | `0` (every return) | State.lua |

## 2. Archived and removed

Lines before: `git show 36daec38:FILE | wc -l`; after: `wc -l FILE` at a49f9f9e. The after figures are net of the
facade redirection (Tasks 4-9) and the sweep (Task 20), not only the removals.

| Area | Before | After | Commit | What went |
|---|---|---|---|---|
| Expansion folders (`BfA`, `Cataclysm`, `Dragonflight`, `Legion`, `Shadowlands`, `TheBurningCrusade`, `TheWarWithin`, `Wrath`) | 104,532 (56 files) | 0 loaded; 104,532 under `archive/` | 1906de33 | moved with `git mv`, dropped from the TOC; TheWarWithin alone is 42 files, 89,177 lines (the retail class files) |
| `Classes.lua` | 4,430 | 3,413 | dcf8b294 | PvP trinkets, retail potions, M+ affixes, holiday items, non-vanilla racials |
| `State.lua` | 8,099 | 7,341 | 8316a83a | azerite, legendaries, empower, hero trees, PvP talents, retail trinket systems (incl. the BfA `cyclotronic_blast` block in `state.reset`) |
| `Constants.lua` | 738 | 449 | 147913a3 | hero trees and the retail-only class rows |
| `Events.lua` | 2,773 | 2,519 | 198226cf | azerite, essence, PvP-talent, Torghast and Timerunning handlers (the Timerunning check inside `CLEU_HANDLER` stays) |
| `UI.lua` | 3,201 | 3,154 | 1641d8e2 | empowerment rendering; Masque stays optional |
| `Utils.lua` | 1,092 | 918 | b09e746b | covenant cache, talent loadout export |
| `Options/Options.lua` | 10,128 | 9,814 | e18579dd | one-time fixes, retail panels, the hero-tree/PvP/legendary snapshot lines, heart_essence and gladiator entries |
| `Options/DevTools.lua` | 1,220 | 1,168 | e18579dd | PvP-talent and retail skeleton paths |
| `Options/Archive.lua` | 677 | deleted | e18579dd | the whole file (archived-profile UI) |
| Libraries | `.gitignore`d, fetched at package time (SpellFlashCore in-repo) | 26 entries in `Libs/` plus VirtualGameAPI-1.0, all tracked | 632dbb1a | nothing dropped (user decision: drop only on in-game evidence). Upstream gates: **SpellFlashCore** returns for builds below 110000, so it never loads on 16001; **LibChatAnims** has an early return on `WOW_PROJECT_ID` 1/18 and a lowercase `<script>` tag that may stop the client loading it (zero Hekili call sites, so a failure is silent) |

Untouched apart from facade edits: `Hekili.lua` 666 -> 669, `Formatting.lua` 800 -> 800, `MultilineEditor.lua`
670 -> 672, `Targets.lua` 1,604 -> 1,609, `Scripts.lua` 2,197 -> 2,176, `Core.lua` 2,317 -> 2,257,
`Options/ChatCommands.lua` 654 -> 655. New: `Forever/Warrior.lua` 22.

Retained Lua: the 16 loaded files (TOC order, `embeds.xml` aside) total **37,636** lines, against **41,266** for the
base's root plus `Options/` Lua (16 files including `Archive.lua`). The base TOC also loaded the 104,532 archived lines.

## 3. Kept but flagged for Phase 3b

Copied from `docs/forever-facade-notes.md` as of this commit (that file is the one to keep current). Line numbers are
as of a49f9f9e.

### Secrecy zone (bodies unchanged in Phase 2; Phase 3b revisits them)

Line ranges are as of the post-cleanup sweep (Task 20).

| Code | Where | What it reads through the facade |
|---|---|---|
| cooldown metatable | `State.lua` 2905-3119 (`GetUnpackedSpellCooldown`, `mt_default_cooldown`) | `C_Spell.GetSpellCooldown`, `GetSpellCharges`, `GetSpellLossOfControlCooldown` |
| `ScrapeUnitAuras` | `State.lua` 5353-5567 (`function state.ScrapeUnitAuras`); slot reader `StoreMatchingAuras` 5281-5350 | `C_UnitAuras.Get{Buff,Debuff}DataByIndex`, `UnitAuraBySlot`, `UnitIsUnit` |
| `state.reset` | `State.lua` 6178-6476 (`function state.reset`) | `UnitPower`, `UnitPowerMax`, `GetManaRegen`, `GetPowerRegenForPowerType`, `UnitHealth`, `UnitHealthMax`, `UnitAttackSpeed`, `GetTotemInfo`, `UnitCastingInfo` |
| `UNIT_POWER_FREQUENT` handler | `Events.lua` 1174-1211 | `UnitPower` |
| `UNIT_AURA` handler | `Events.lua` 1254-1324 | `AuraUtil.ForEachAura`, `C_UnitAuras.GetAuraDataByAuraInstanceID` |
| combat-log handler | `Events.lua` 1460-1767 (`CLEU_HANDLER` and its registration on 1767) | `CombatLogGetCurrentEventInfo`, `UnitAttackSpeed` |
| target counting | `Targets.lua` 395-667 (`ns.getNumberTargets`) | `UnitHealth`, `UnitGUID`, `GetUnitSpeed`, `GetHaste` |
| time to die | `Targets.lua` 1164-1605 (`EliminateEnemy`, `UpdateEnemy`, `GetTTD`, `GetTimeToPct`, `UpdateTTDs`) | `UnitHealth`, `UnitHealthMax`, `UnitGetTotalAbsorbs` |
| UI cooldown arithmetic | `UI.lua` 1107-1663 (`d:OnUpdate`) and 1693-1740 (`d:RefreshCooldowns`) | `C_Spell.GetSpellCooldown`, `UnitCastingInfo`, `UnitChannelInfo` |
| spec detection | `Classes.lua` 3077-3362 (`Hekili:SpecializationChanged`) | `C_SpecializationInfo.*` |

### Stub call sites that would throw or misbehave (for Phase 3b; not patched here)

Every stub site in the retained files that throws or yields a wrong value. Sites that read a stub and stay correct
(nil-guarded, `or` defaults) are left out.

| Stub | Call site | Effect |
|---|---|---|
| `CombatLogGetCurrentEventInfo` -> nil | `Events.lua` 1767 `CLEU_HANDLER( event, CombatLogGetCurrentEventInfo() )` | **throws** in combat if the event ever fires: every argument is nil, the out-of-combat early return (1494) is skipped, and `bit.band( destFlags, ... )` (1510) gets nil. Registering CLEU itself is forbidden on Forever; removing or diverting the registration is the real fix |
| `CombatLogGetCurrentEventInfo` -> nil | `Options/DevTools.lua` 458 `SkeletonCLEU( CombatLogGetCurrentEventInfo() )` | safe: `sourceName` nil returns at 339 |
| `GetTalentInfoByID` -> nil | `Events.lua` 431-435, `ns.updateTalents`: `name` nil falls back to `IsPlayerSpell( v )` where `v` is a `RegisterTalents` entry (a table) | probably **throws** (`IsPlayerSpell` given a table); unverified on the client. Either way talents come out wrong until the `C_Traits` walk replaces this loop |
| `UnitAttackSpeed` -> `2, nil` | `State.lua` 192 and 6356, `Events.lua` 816 and 1695, `Classes.lua` 3357 | wrong value: main-hand speed is a constant 2.0, so swing projections (`swings.mh_*`) are fiction. `oh_speed` nil is guarded at State.lua 195/5132/6358 and Events.lua 1688/1690 |
| `UnitAttackSpeed` -> `2, nil` | `State.lua` 2310 `stat.weapon_speed` | wrong value: 2.0 / 0 |
| `GetPowerRegenForPowerType` -> `0, 0` | `State.lua` 6310 in `state.reset`, feeding `forecastResources` | wrong value: `active or 0.001` keeps the 0 (0 is truthy), so regen is 0, every resource forecast is flat, and `time_to_x` returns 3600 or the next modeled slice (`State.lua` 3391 divides by 0 to `inf` but the comparison that follows still picks `after.t`). Assassination's timeout `energy.max / max( 0.001, regen )` (1192) becomes 100000 s, bounded by the 30-iteration cap |
| `GetManaRegen` -> `0, 0` | `State.lua` 6303 | wrong value: mana never regenerates in the forecast |
| `UnitPower` -> 0 | `State.lua` 6290 `res.actual`; `Events.lua` 1174-1208 | wrong value: every resource reads 0, so nothing with a cost is ever recommended. The single largest behavioural gap |
| `C_UnitAuras.GetAuraSlots` -> nil | `State.lua` 456 `state.UnitAuraSlots` | no retained consumer; spec code calling `UnitAuraSlots` would get no slots |
| `GetTotemInfo` -> `false, "", 0, 0, 0` | `State.lua` 2389 (totem pets), 4093 (`mt_default_totem.expires`), 4128-4149 (`mt_totem` fire/earth/water/air), 6261 (`summonPet` from totems) | wrong value: `spellID` and `modRate` are nil (`class.abilities[ nil ]` reads nil, no throw), every totem and totem-backed pet is down |
| `UnitCastingInfo` / `UnitChannelInfo` ("target") -> nil | `Classes.lua` 1646 and 1677, the `casting` aura generator for `unit == "target"` | wrong value: `debuff.casting` is never up on the target, so interrupt recommendations never fire. Player casts pass through |
| `UnitHealth` / `UnitHealthMax` -> 0 | `Targets.lua` 434 and 511 enemy scan `UnitHealth( unit ) > 1` | wrong value: every nameplate is filtered out unless it is a training dummy, so `active_enemies` stays at 1 |
| `UnitHealth` / `UnitHealthMax` -> 0 | `Targets.lua` 1600 `UpdateEnemy( guid, health / healthMax, ... )` (1583-1587 clamps `healthMax` to 1, 1600 does not) | wrong value: `0 / 0` is NaN, NaN comparisons are false, `rate` stays 0, and TTD stays at its default |
| `UnitHealth` / `UnitHealthMax` -> 0 | `Targets.lua` 1304-1312 (`GetTTD`) and 1328-1340 (`GetTimeToPct`) | wrong value: NaN `healthPct`; the `enemy.n < 3` early return hides it, so callers get the default |
| `UnitHealth` / `UnitHealthMax` -> 0 | `State.lua` 2860-2866 `mt_target_health` | wrong value: `target.health.pct` is 100 (the `t.max ~= 0` guard), so execute-phase conditions never pass |
| `UnitHealth` / `UnitHealthMax` -> 0 | `State.lua` 1866-1893 `group_health`, `at_risk`; 2562 pet `health_pct`; `Utils.lua` 416-462 | wrong value: `0 / 0` NaN percentages, every `<` test false |
| `UnitHealth` -> 0 | `State.lua` 2424, 2556 pet alive checks `UnitHealth( "pet" ) > 0` | wrong value: the pet always reads dead |
| `UnitHealth` -> 0 | `State.lua` 6351-6352 `state.health` | wrong value: player health 0 of max 1 |
| `IsUsableSpell` -> false | `State.lua` 6966 `usable` check for a numeric `usable` | wrong value: such abilities are never usable (port to `C_Spell.IsSpellUsable`) |
| `GetUnitSpeed` -> 0 | `State.lua` 1861, 2793; `Targets.lua` 492, 558, 622, 642 | wrong value: nothing is ever moving |
| `UnitInRange` -> `false, true` | `State.lua` 1850 | wrong value: no group member is in range |
| `C_Spell.GetSpellCooldown`, `GetSpellCharges`, `GetSpellLossOfControlCooldown` | `State.lua` 2905-3011 | wrong value only: every spell is off cooldown with 1/1 charges; the loss-of-control nil is guarded |
| stat stubs (`UnitStat`, `GetCombatRating*`, `GetMasteryEffect`, crit, haste, `UnitDamage`, `UnitArmor`, attack power) | `State.lua` 2236-2356, `Targets.lua` 816 | wrong value: 0 everywhere; haste 0 gives a factor of 1, so no division by zero |

### Edits no facade absorbs (feasibility doc C.5)

- GCD spell 61304 -> 29515: `Classes.lua` 2469 (`id = 61304`), `UI.lua` 1493 and 1694, `Events.lua` 1675.
- The enemy-scan health comparison: `Targets.lua` 434 and 511.
- TTD: `Targets.lua` 1164-1605 needs another source of health deltas.
- Spec identity (pseudo-spec 1491): `Classes.lua` 3077-3362 `SpecializationChanged`. `NewSpecialization` now takes
  identity from the `ns.Specializations[ 1491 ].forever` row (Task 11b); what remains:
  - `Classes.lua` 3135-3138: Forever returns id `0` (truthy) for spec slots 2 and 3, so the loop does not break and
    `specs` holds `0` several times; `all` is merged repeatedly and its hooks (`reset_precast`, 3242) run 2-3 times per
    reset. Wrong cost, no error (the hook is idempotent). Fix: `if not id or id == 0 then break end`.
  - `Classes.lua` 3148-3164: `role` and `primaryStat` from `GetSpecializationInfo( 1 )` are unprobed on Forever; if nil,
    `state.role.healer` and `state.spec.primaryStat = "intellect"` are set for a Warrior. Wrong data, no error.
- Talents: replace `ns.updateTalents` (`Events.lua` 423) with a `C_Traits` walk (`Options/DevTools.lua` already walks the tree).
- CLEU: remove or divert the registration at `Events.lua` 1767 (and `Options/DevTools.lua` 1156).
- Version gates: `Hekili.lua` 18-56 (`IsDragonflight`, `IsTWW`, `IsMidnight` and `ns.PTR` are false on build 16001;
  `BuiltFor = 110200`) and `Core.lua` 205 (`BuiltFor > CurrentBuild` reports Hekili as built for a newer client).
- Division-by-zero audit: the NaN and `inf` sites in the table above.
- Load-time nils: the stubs above cover reads; globals the facade does not list stay a Phase 3b audit.

## 4. Vendored libraries

Copied from `Libs/CREDITS.md` (the source of truth; it also carries the licence notes).

| Library | Upstream | Pin | Licence | Author credit | Forever support upstream | Load gate |
|---|---|---|---|---|---|---|
| LibStub | https://github.com/WoWUIDev/Ace3 (`LibStub/`) | Ace3 tag `Release-r1403`, commit d295b12 (2026-08-12) | Public domain (file header); Ace3 `LICENSE.txt` copied | Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke | No (Ace3.toc lists 11508 ... 120007, not 16001) | None |
| CallbackHandler-1.0 | Ace3 (`CallbackHandler-1.0/`) | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceAddon-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceGUI-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None at load; `widgets/AceGUIWidget-ColorPicker.lua:16` inverts alpha when `WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE` |
| AceConsole-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceConfig-3.0 (Registry, Cmd, Dialog) | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceTimer-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceSerializer-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceComm-3.0 (with ChatThrottleLib) | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team; ChatThrottleLib by Mikk | No (as Ace3) | None |
| AceEvent-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceDB-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| AceDBOptions-3.0 | Ace3 | Ace3 `Release-r1403`, d295b12 | Ace3 BSD-style, `LICENSE.txt` | Ace3 Development Team | No (as Ace3) | None |
| LibSharedMedia-3.0 | https://repos.wowace.com/wow/libsharedmedia-3-0/trunk/LibSharedMedia-3.0 | MINOR 12000004 (wowace trunk mirrored 2026-10-14) | LGPL v2.1 (file header; quoted in `LICENSE-NOTE.md`) | Elkano | No | None found |
| AceGUI-3.0-SharedMediaWidgets | https://repos.wowace.com/wow/ace-gui-3-0-shared-media-widgets/trunk/AceGUI-3.0-SharedMediaWidgets | DataVersion 9004, widgetVersion 13; wowace trunk mirrored 2026-10-14 (no `$Id`) | None stated upstream (no file, no header) | Yssaril | No | None |
| AceGUI-3.0_SFX-Widgets | https://github.com/SFX-WoW/AceGUI-3.0_SFX-Widgets | commit 450c923 (2026-10-05) | Custom permissive-with-conditions, `LICENSE.txt` (Copyright StormFX) | StormFX | Yes: TOC `## Interface: 11509, 16001, ...`; CHANGELOG "Forever: 16001" | None |
| LibSpellRange-1.0 | https://github.com/ascott18/LibSpellRange-1.0 | commit 49da263 (2024-08-19), TOC version 1.0.17 | None upstream (no licence file or header) | Cybeloras of Aerie Peak (ascott18) | No (TOC 100001) | Feature branch, not build-keyed: uses `C_Spell.IsSpellInRange` when present, else spellbook fallbacks |
| LibRangeCheck-3.0 | https://github.com/WeakAuras/LibRangeCheck-3.0 | commit 95a6313 (2026-09-29, "Add checks for Forever on all isEra checks") | MIT, `LICENSE` | The WoWUIDev Community | Yes: `isForever = interfaceVersion >= 16000 and < 20000` (main file line 60), Forever shares the Era range tables | Branches on `GetBuildInfo` and `WOW_PROJECT_ID` (Era/Forever, TBC, Wrath, Cata, Mists, Midnight); no early return. Main file moved up from the repo's nested `LibRangeCheck-3.0/` folder (upstream `.pkgmeta` `move-folders`) |
| LibCompress | https://repos.wowace.com/wow/libcompress/trunk (returns 401); taken from Hekili release v11.2.5-1.0.0 | Hekili release v11.2.5-1.0.0 (TOC `r86-release`, header `$Revision: 83 $`) | GPL v2 (file header; quoted in `LICENSE-NOTE.md`) | jjsheets, Galmok | No (TOC 90002) | None |
| LibDeflate | https://github.com/SafeteeWoW/LibDeflate | commit afc3b78 (2021-05-05) | zlib, `LICENSE.txt` | Haoqian He (Safetyy) | No (TOC 80300) | None |
| LibDataBroker-1.1 | https://github.com/tekkub/libdatabroker-1-1 | commit 1a63ede (2008-07-31), MINOR 4 | None upstream (no licence file or header) | tekkub | No | None |
| LibDBIcon-1.0 | https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0 | MINOR 57 (wowace trunk mirrored 2026-10-14) | None stated upstream (no file, no header) | wowace project libdbicon-1-0 (no author named in source) | No | None found |
| LibDualSpec-1.0 | https://github.com/AdiAddons/LibDualSpec-1.0 | commit 71dcd66 (2026-09-20) | BSD-style with a no-standalone-redistribution clause (file header; quoted in `LICENSE-NOTE.md`) | Adirelle, Nebula | Yes: TOC `## Interface: 11509, 16001, ...`; Forever branches at lines 72-77 and 518 | `GetBuildInfo` 16000-20000 forces primary/secondary (dual spec) mode, then a Forever `GetProfileSpecialization` using `GetNumSpecGroups` |
| LibCustomGlow-1.0 | https://github.com/Stanzilla/LibCustomGlow | commit 4f8f5c2 (2026-07-17) | MIT, `LICENSE` | deezo, Benjamin Staneck (Stanzilla) | No (TOC 120001, 120000) | `isRetail = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` picks retail vs classic code paths (lines 16, 24, 151); no early return. Repo folder `LibCustomGlow` vendored as `LibCustomGlow-1.0` to match `embeds.xml` |
| LibChatAnims | https://repos.wowace.com/wow/libchatanims/trunk/LibChatAnims | MINOR 7 (wowace trunk mirrored 2026-10-14) | None stated upstream (no file, no header) | wowace project libchatanims (no author named in source) | No | Early `return` when `WOW_PROJECT_ID == 1 or == 18` (line 17), retail-only block at line 256. Forever's `WOW_PROJECT_ID` is not yet confirmed, so whether it runs is unknown. Its XML uses a lowercase `<script>` tag (wow_xml_validate: error, case-sensitive element), so the client may skip the Lua file entirely |
| LibTranslit-1.0 | https://github.com/Vardex/LibTranslit | commit 66a5aa7 (2022-11-11) | LGPL v3, `COPYING` + `COPYING.LESSER` | Vardex | No (TOC 100000) | None |
| SpellFlashCore | Contributed copy kept in this repo (the 2024-09-15 copy; git history: added 617e3e6a 2023-11-29, last changed 1bd9f1c2 2024-07-08) | in-repo, TOC version 2.4.1 | No licence file in its folder | BigRedBrent, LightSpell | No | **Returns for builds below 110000** (`SpellFlashCore.lua` lines 1-4; 30400 for 3.4.x). Forever (16001) therefore does not load it: expected, not a Hekili failure |
| VirtualGameAPI-1.0 | This repository | in-repo | MIT, `LICENSE` | Hekili Forever port | Yes (written for Forever) | None |

Upstream Forever support: **yes** for AceGUI-3.0_SFX-Widgets, LibRangeCheck-3.0 (`isForever` branch), LibDualSpec-1.0
(Forever branches) and VirtualGameAPI-1.0; **no** for every other library, including all twelve Ace3 entries. All
are kept until in-game evidence says otherwise. The two with a gate that matters on 16001 are SpellFlashCore (does
not load, expected) and LibChatAnims (load unknown, see above).

## 5. Open questions for Phases 1 and 3b

| # | Question | Where | Owner |
|---|---|---|---|
| 1 | AddOns folder name. Every file reads `local Hekili = _G[ addon ]`, so the folder must be named `Hekili`. At Checkpoint A the user's symlink was `hekili` and load failed. Rename the symlink, or change 12 lines to `_G.Hekili` | user setup / all files | owner |
| 2 | Per-file environment vs file-top locals. `State.lua`'s main chunk is at the 200-locals cap (0 spare), so 34 single-use reads use `VGA.Name(` inline (listed in 4204b99c). A shim that swaps reads per file wants `setfenv` on the chunk; the feasibility Appendix asks whether chunk-level `setfenv(1, env)` works on Forever (one `/run` check) | `State.lua`, every redirected file | 1, 3b |
| 3 | Event facade. `ns.RegisterEvent` reaches a real frame; virtual events need a diverting `RegisterEvent` or one edit at the call. `UNIT_AURA` (`isFullUpdate` on a secret), `UNIT_POWER_FREQUENT` and target `UNIT_SPELLCAST_*` (secret `spellID`) need payload facades (feasibility C.2.1-2) | `Events.lua` | 1 |
| 4 | Virtual combat log timing (feasibility C.2.3). Hekili stamps CLEU with `GetTime()` at handler entry, so inferred rows delivered late shift swing and DoT clocks. Conditions: observed rows delivered synchronously; inferred rows carry a back-dated clock (or the facade's `GetTime` returns the event time during delivery); delivery never nests in a Hekili call (the update coroutine runs `state.reset`); the B.4 payload contract holds. Derived events from inside a pack hook are dropped | `Events.lua` `CLEU_HANDLER` 1460-1767 | 1 |
| 5 | CLEU registration popup. Registering `COMBAT_LOG_EVENT_UNFILTERED` is forbidden on Forever; the registrations at `Events.lua` 1767 and `Options/DevTools.lua` 1156 are still live, and the stubbed `CombatLogGetCurrentEventInfo` makes the handler throw if it ever fires. Unprobed: whether a diverted insecure-frame registration avoids the popup (moot if the diversion is total) | `Events.lua` 1767, `Options/DevTools.lua` 1156 | 3b |
| 6 | GCD constant 61304 (retail) vs 29515 (Forever). A constant, not a call | `Classes.lua` 2469, `UI.lua` 1493 and 1694, `Events.lua` 1675 | 3b |
| 7 | Spec identity 1491. `NewSpecialization` takes identity from `ns.Specializations[ 1491 ].forever`. Forever returns id `0` (truthy) for spec slots 2/3, so the `GetSpecializationInfo` loop in `SpecializationChanged` does not break, `all` merges 2-3 times and `reset_precast` runs repeatedly (no error). Fix: `if not id or id == 0 then break end` | `Classes.lua` 3133-3138 | 3b |
| 8 | `role` and `primaryStat` from `GetSpecializationInfo( 1 )` are unprobed. If nil, a Warrior gets `state.role.healer` and `primaryStat = "intellect"` | `Classes.lua` 3148-3164 | 3b (probe) |
| 9 | Talent reader. `GetTalentInfoByID` is stubbed nil, so `ns.updateTalents` falls through to `IsPlayerSpell( table )` (probably throws) and talents read as none. Replace with a `C_Traits` walk (`Options/DevTools.lua` already walks the tree). The retail override `ns.updateTalents` now lives only in `archive/Dragonflight/Classes.lua` | `Events.lua` 423-435 | 3b |
| 10 | `SavedVariables: HekiliDB`: keep retail Hekili's name (a copied retail SavedVariables file would load retail profiles and specs) or rename it for a clean break | `Hekili.toc` line 7 | owner |
| 11 | Combo points and forms unprobed: `UnitPower(…, ComboPoints)` (stubbed 0 with every `UnitPower`), `GetShapeshiftForm`/`GetShapeshiftFormInfo` (passthrough, secrecy unknown). Also unprobed: player-health secrecy, channels, stats getters | feasibility Appendix | 1 (probe) |
| 12 | Deprecated shims (7 names above) exist only with the CVar `loadDeprecationFallbacks` on. Port to `C_SpellBook.IsSpellKnown` and `C_ActionBar.*`; until then they read nil (`missing`) | inventory | 3b |
| 13 | LibChatAnims lowercase `<script>` tag (`LibChatAnims.xml` line 4, `wow_xml_validate` error). Upstream as is; confirm in game whether it loads | `Libs/LibChatAnims/` | in game |
| 14 | `.luacheckrc` boundary. The facade covers game-state reads only. Writes (`SetCVar`, `SetOverrideBindingClick`, `ClearOverrideBindings`, `ClearCursor`, `Screenshot`), timers (`C_Timer`), hooks (`hooksecurefunc`), `debugprofilestop` and the secrecy predicates (`C_Secrets`, `issecretvalue`, `issecrettable`) stay declared globals outside the facade. A later facade that virtualises any of them adds them by hand | `.luacheckrc` | 1 |
| 15 | Version gates: `IsDragonflight`/`IsTWW`/`IsMidnight`/`ns.PTR` are false on 16001, `BuiltFor = 110200`, and `Core.lua` 205 reports Hekili as built for a newer client | `Hekili.lua` 18-56, `Core.lua` 205 | 3b |
| 16 | Behavioural gaps from stubs (section 3): `UnitPower` 0 (nothing with a cost is recommended), `UnitHealth` 0 (enemy scan sees one target, TTD default, NaN percentages), regen 0, all spells off cooldown. These are Phase 1's virtual-state fields | section 3 | 1 |

### Deferred minors (from the ledger, still open at a49f9f9e)

- `tools/check_api_reads.sh`: ignores luacheck's exit code (a syntax error passes silently); `_G` reads through
  `rawget` or a variable key are not covered; the `_G.` grep does not skip comments.
- `tools/api_inventory.txt`: `C_AddOns.LoadAddOn` and `C_Spell.RequestLoadSpellData` are actions kept by the
  every-`C_*` rule; `C_PetBattles.IsInBattle` presence rests on FrameXML evidence only.
- `Libs/VirtualGameAPI-1.0`: `zeros()` returns 7 values (harmless at `State.lua` call sites); spec files lint only with `--ignore 212`;
  `UnitHealthMax`/`UnitDamage` stubs return 0, a divisor at several sites.
- `State.lua`: main chunk has 0 spare locals; ~200-char block lines from the redirection; `heart_essence` now joins
  the item ICD logic (unusable anyway); dead `DEATHKNIGHT` branch at 1188; `state.empowerment = { start = 0 }` kept
  for the UI; `ns.attr` keeps `conduit`/`covenant`/`soulbind` vocabulary.
- `Classes.lua`: retail potion fallback item 191387 (2444); healthstone `talent.pact_of_gluttony` and item 224464
  (2661-2677); shadowed unused local `GetItemInfo` in the potion block (2349); `class.pvptalents` written, never read
  (kept: `RegisterPvpTalents` is spec API).
- `Constants.lua`: the 1491 row's `forever` field doubles as the spec name; `essence` power type kept with its
  non-Forever siblings.
- `Core.lua`: dead `DEATHKNIGHT` branches (1644, 1665, 1883).
- `Events.lua` / `Targets.lua`: the Timerunning block (`Targets.lua` 333-350, `Events.lua` 1489-1491) stays; removing
  it touches the inventory, library and notes.
  `Events.lua:1904` `defaultBarMap` is dead data with no reader (kept; remove in Phase 3b).
- Facade notes: the `reset_precast` cite (`Classes.lua` 3242) is a rough locator for the hook-merge loop in `Classes.lua`.
- `UI.lua`: `d:RefreshCooldowns` 1711, 1731-1737 dead behind `ability.empowered` (secrecy zone, left alone).
- `Options/DevTools.lua`: dead `or VGA.IsX` fallbacks (29-31); `SkeletonTalentEnhancements.talentCopies` Monk keys;
  the `GetHeroTalentSpecsForClassSpec` walk (490) is inert.
- `Hekili.lua`: `ns.Patrons` text claims all specs are supported.
- `.luacheckrc`: `INVSLOT_NECK` declared, unused.
- `Libs/`: Ace3 `LICENSE.txt` copied 12 times.
- `Forever/README.md`: repeats "Phase 3b".

## How to verify

Tools: `BUSTED=~/src/TacoDogForever/.lua/bin/busted`, `LUACHECK=~/src/TacoDogForever/.lua/bin/luacheck`,
`lua-language-server` from mise (`~/.local/share/mise/installs/lua-language-server/latest/bin/`). Run from the repo
root. Results at this commit in brackets.

```sh
$BUSTED                                              # [9 successes / 0 failures]
$LUACHECK .                                          # [0 warnings / 0 errors in 17 files]
LUACHECK=$LUACHECK tools/check_api_reads.sh          # [ok: no direct game API read in 16 loaded files]
LUACHECK=$LUACHECK tools/list_api_reads.sh | grep -xFf tools/api_inventory.txt | sort -u \
  | diff - tools/api_inventory.txt                   # [empty: inventory equals reads]
lua-language-server --check . --checklevel=Error --logpath=/tmp/luals   # [no problems found, 17 files]
```

`wow_toc_validate Hekili.toc` (wow MCP, flavor `forever`): 0 errors, 4 warnings (backslash paths), at Task 20.
In game: `/reload` with the AddOns folder named `Hekili` (question 1).
