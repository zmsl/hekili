# Hekili on WoW Forever: research summary

Date: 2026-10-11 · Branch: `research/forever-revival` · Client: WoW Forever "Camelot" 1.60.1.70338
(Interface 16001, Midnight 12.1.5 API, vanilla 1.6 ruleset).

Sources: [01 API inventory](01-api-inventory.md) · [02 secret values (gate)](02-secret-values.md) ·
[03 cleanup inventory](03-cleanup-inventory.md) · [04 classic-branch reuse](04-classic-reuse.md) ·
[05 queryable game data](05-queryable-game-data.md) · [06 prior art](06-prior-art.md)

Credits: much of the Forever API knowledge here comes from **Catnip** by Durts
(github.com/DurtsGaming/Catnip, MIT on CurseForge; the author has authorized reuse in this project). Credit
Catnip in file headers and the README wherever its code or data is used.

## Verdict: (B) hybrid predictor, a conditional GO

A faithful port of Hekili's simulator is **not possible**. Its engine runs numeric simulations of energy,
combo points, aura remaining time, cooldown remaining time and target health, and it builds its state from the
combat log. On Forever every one of those is secret in combat (51 of the functions Hekili uses return secrets,
per [01](01-api-inventory.md)), and the combat-log getter is gone. Blizzard intends this: "Addons should no
longer offer a competitive advantage in WoW combat" ([06](06-prior-art.md)).

A **hybrid predictor** looks viable. In combat it can branch on readable booleans and the player's own cast
events ([02](02-secret-values.md)):

| Signal | Source | Status |
|---|---|---|
| Can I afford X now? | `C_Spell.IsSpellUsable(id)`, plus `insufficientPower` | Documented not secret; **needs the probe** (the gate) |
| Combo points | `UnitPower("player", ComboPoints)`, reset on target change | Catnip doc says readable; **needs the probe** |
| Clearcasting | `GetSpellPowerCost("Shred")` cost == 0 | Verified (Catnip) |
| Cooldown ready / GCD running | `GetSpellCooldown` `isActive`/`isOnGCD` (`NeverSecret`) | Verified |
| Cat Form | `UnitPowerType` == Energy | Verified |
| Rip / Rake / FF / Tiger's Fury up | self-timers from `UNIT_SPELLCAST_SUCCEEDED` plus durations from `wowdb` | Approximate (misses can't be seen) |
| Swing | `PLAYER_SWING` | Verified |
| Blizzard's suggestion | `C_AssistedCombat.GetNextCastSpell` | Exists, not secret; **availability and data unknown** |

**Not available in combat:** exact energy and time-to-energy (pooling), exact DoT remaining, target health
(execute), the combat log (misses, damage-based target counts), talents through the classic API (but `C_Traits`
may work, see [04](04-classic-reuse.md)).

If the probe shows `IsSpellUsable` is secret in combat, the fallback is **(C)**: a `C_AssistedCombat`
wrapper with Hekili's display, plus Catnip-style display of secret values. That is what every surviving Midnight
rotation helper does (MaxDps, HekiLight, JustAC; [06](06-prior-art.md)). No rotation predictor exists for
Forever yet.

## Feral APL coverage (classic `DruidFeral.simc` against Forever signals)

| APL input | Forever in combat | Treatment |
|---|---|---|
| `energy.current >= N`, `energy.time_to_tick` | secret | Replace with "action usable" plus a tick model for the next GCD or two (coarse) |
| `combo_points.current >= settings.*_cp` | probably readable (`UnitPower` CP) | Keep, if the probe confirms |
| `buff.clearcasting.up` | derivable, exact | Keep (cost trick) |
| `buff.cat_form/bear_form.up` | readable | Keep |
| `debuff.rip.up/.remains`, `debuff.faerie_fire*.remains` | secret → self-timer | Keep, approximate |
| `ttd`, `target.time_to_die` | unavailable (health secret) | Drop, or replace with a user setting |
| `mana.*`, powershift / `innervate` lists | secret mana | Drop powershifting at first (it depends on exact energy and mana) |
| `talent.furor.rank`, `set_bonus.wolfshead` | `C_Traits` maybe / gear readable | Probe; otherwise a user setting |
| `cooldown.*` (unused by the classic APL) | flags readable | Add Tiger's Fury and FF (Feral) readiness |

The classic APL is a design reference, not drop-in content. It needs a **new, simpler Forever Feral APL**
built on the signals above. Use Forever spell data from `wowdb`: Forever adds Primal Bite (renamed SoD Mangle),
Berserk, Shifting Power, and new high-ID variants (e.g. a 21s Rip at 1289141).

## Recommended architecture

1. **Base:** the `forever` (retail 11.2.5) engine, not `classic`. It has the newer API surface; the classic engine
   is a 2022 Wrath fork ([04](04-classic-reuse.md)).
2. **New "game data source" layer** between the game and `state` ([03](03-cleanup-inventory.md)). Each value
   is classified as readable, self-tracked, or display-only, using `issecretvalue` and
   `C_Secrets.Should*BeSecret` checks at runtime. APL scripts never see a secret, and secret values only flow to
   widgets (StatusBar, duration objects, `CustomAuraContainerTemplate`; Catnip's techniques).
3. **State model changes:** energy as affordability flags plus a tick model; a cast-event-fed aura and debuff
   store keyed by target GUID (player-target GUIDs are readable); the cooldown model built on flags plus learned
   lengths; no combat-log dependency (one guarded entry point, cast history from `UNIT_SPELLCAST_SUCCEEDED`,
   swings from `PLAYER_SWING`).
4. **Optional oracle:** `C_AssistedCombat` as a cross-check or fallback, if it has Forever data.

## Stage 1: cleanup and rearchitecture (first development stage)

From [03](03-cleanup-inventory.md), ordered so the addon stays loadable after each step:

0. **Add the missing libraries.** `embeds.xml` needs 25 packager externals (LibStub, Ace3, LibRangeCheck,
   LibSpellRange…). Only SpellFlashCore is in the repo, so **Hekili currently can't load in game at all.**
1. Set the TOC to `## Interface: 16001`. Drop the retail version checks (`IsDragonflight`/`IsTWW` take the wrong
   branch at build 16001, and `Core.lua:203` warns that the addon targets a future WoW version).
2. Delete about 106k of 151k Lua lines (about 70%): every TWW spec module, its `.simc` files, the BfA, SL, DF,
   Legion, TBC, Wrath and Cata content, the DK, DH, Monk and Evoker classes, and dead `Options/Archive.lua`.
3. Remove or fix the three missing APIs ([01](01-api-inventory.md)): the combat-log getter,
   `GetSpellLossOfControlCooldown` → `…CooldownInfo`, and dead `InterfaceOptions_AddCategory`. Also replace the
   GCD spell 61304 with 29515.
4. Put the combat log behind a guard (`Events.lua:1709-2016`) and move cast history and swings to
   readable events.
5. Introduce the game-data-source layer and remove secret-touching paths: `state.reset`,
   `ScrapeUnitAuras`, `mt_default_cooldown`, the `UNIT_POWER_FREQUENT` and `UNIT_AURA` handlers, health and TTD,
   and the UI's cooldown maths.
6. Lay out per-class modules for the 9 Forever classes (empty stubs).

Exit criteria: TOC 16001; loads on Forever with no Lua errors; only Forever-relevant code; luacheck and LuaLS
clean (luacheck needs `sudo apt install lua-check`).

## What to reuse ([04](04-classic-reuse.md))
- **Copy:** Druid rank ID lists (they match Catnip and Forever), the APL template tool
  (`template.js` + `.t.simc`), and the Druid settings.
- **Adapt:** the vanilla energy-tick model, highest-rank lookup by name (via `C_Spell.GetSpellInfo`), the form,
  Maul and rage models, cost formulas, and the talent table, converted to the retail `C_Traits` format (which
  TalentsForeverBook already reads on Forever).
- **Don't reuse:** the classic engine files, `Classic/Classes.lua`, the six untouched Wrath class modules,
  and `origin/sod` (a Wrath fork, no SoD content).

## Tooling ([05](05-queryable-game-data.md))
- **`wowdb`** (`~/.local/share/wow-db2/bin/wowdb`): a SQLite DB of 21 DB2 tables for the exact Forever build
  from wago.tools. `wowdb spell Rip` returns ranks, cost, duration and GCD in about 1 KB. Use it rather than Wowhead
  Classic, whose values differ from Forever's.
- **`wow` MCP:** Forever API, events and UI source. Run `/mcp` → reconnect to pick up the newly synced file,
  atlas and UI indexes. It **under-reports secrecy** (conditional `SecretWhen*` flags are dropped), so check the
  raw docs for secrecy questions ([01](01-api-inventory.md)).
- Ketho's BlizzardInterfaceResources `forever` branch fills in the missing globals and cvars (saved under
  `~/.local/share/wow-db2/forever/bir/`).

## Other classes (hypothesis, low confidence)
They follow the same rules: they can branch on affordability, cooldown flags, cast-event timers and swing.
- **Rogue:** closest to Feral (energy and CP); expected to be similar.
- **Warrior:** rage is secret, so it depends on affordability flags. The classic Warrior module was rewritten for vanilla.
- **Caster DoT classes** (Warlock, Priest Shadow, Mage): rely more on cooldown and DoT timers than exact
  resources, so they may suit this model *better*.
- **Hunter:** auto-shot timing, if `PLAYER_SWING`/ranged equivalents are readable.
- **Paladin and Shaman:** seals and totems (`C_Secrets.ShouldTotemSlotBeSecret` exists).

Assess each class with an input-coverage table like the Feral one before committing to it.

## Open questions → the in-game probe

The probe addon is at `~/src/ForeverProbe` (protocol in its README). It answers:
1. Is `C_Spell.IsSpellUsable` (and `insufficientPower`) readable in combat? **The gate.**
2. Is `UnitPower("player", ComboPoints)` readable in combat?
3. Is `C_AssistedCombat` available, and does it return Druid spells?
4. Does registering the combat-log event fail or stay silent? Does `UNIT_COMBO_POINTS` exist?
5. Which `C_Secrets` restrictions are active out of and in combat?

Not covered by the probe yet: the spec ID Forever reports (the engine is keyed on retail IDs, e.g. Feral 103);
whether `C_Traits` talent reads work; whether the `loadDeprecationFallbacks` CVar is on; and what Primal Bite
and Shifting Power do.

## Next steps
1. **User:** link and run the probe (see the README), then report back. Claude reads
   `WTF/Account/*/SavedVariables/ForeverProbe.lua`.
2. Update this verdict with the probe results.
3. Superpowers `brainstorming` → spec → `writing-plans` for **stage 1 (cleanup and rearchitecture)**,
   executed subagent-driven.
4. Then the same for the Feral POC.
