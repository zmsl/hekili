# R5 — Making WoW Forever game data queryable (spells, talents, items)

Date: 2026-10-11 · Target: WoW Forever "Camelot" 1.60.1.70338 (TOC 16001, product `wow_classic_beta`)

## Summary

- **wago.tools has the exact Forever build.** `1.60.1.70338` is listed under products `wow_classic_beta` and `wow_cn_beta`. The CSV export URL `https://wago.tools/db2/<Table>/csv?build=1.60.1.70338` returned HTTP 200 for all 21 spell, talent and item tables we tried. A build that doesn't exist returns HTTP 400 rather than a silent fallback. No 403 from this WSL connection.
- **Working prototype, built and queried.** The scripts live in `~/.local/share/wow-db2/bin/`, outside the repo. They download pinned CSVs and build a 16.8 MB SQLite database in about 1.2 s. The database has the views `spell_info`, `spell_effects`, `talent_info` and `spell_skill`. A Python query CLI, `wowdb`, returns compact TSV and needs no `sqlite3` binary. `wowdb spell Rip` returns 7 rows / ~1 KB.
- **`wow` MCP gaps are mostly fixable without new tooling.** I ran `sync game-data -- forever` (listfile plus Forever atlases, which succeeded) and `sync ui-source -- forever` (Blizzard UI source at 1.60.1 (70338), giving 534 cvars and 345 global strings). The MCP server must be **restarted/reconnected** to load them. Globals and the full CVar registry come from Ketho's `BlizzardInterfaceResources@forever` branch, which is already at 70338.

## Findings

### 1. `wow` MCP state (hated-wow-mcp 0.6.1)

| Data set | Before | After this session |
|---|---|---|
| Forever API index (functions/events/tables) | 6577 / 1802 / 1738, synced 2026-09-18 | unchanged (bundled; `api` sync is git-checkout only) |
| Forever globals / cvars | 0 / 0 ("no upstream source yet") | cvars: 534 UI-used cvars indexed by the ui-source sync (visible after an MCP restart) |
| Event payloads (forever) | **present**, e.g. `UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID, castBarID?)` | — |
| File index (listfile) | NOT BUILT | built: 2,256,962 files / 176,032 interface / 37,049 icons |
| Forever atlas index | NOT BUILT | built from wago.tools build 1.60.1.70338: 20,559 atlases / 2,807 sheets |
| Forever UI source (`wow_ui_grep` etc.) | not synced (only mainline) | cloned Gethe/wow-ui-source@forever, HEAD `9437644` "1.60.1 (70338)", 4429 files / 348 packages / 4337 templates / 3743 mixins |

The running MCP process cached its indexes at startup. After the syncs, `wow_ui_grep`/`wow_cvar_search` with `flavor=forever` still said "not synced". **Reconnect the `wow` server (`/mcp`) to pick them up.**

The `wow` MCP has **no spell/talent/item game data** at all. It only covers API, UI source, files and atlases.

### 2. Secret values (12.x "Midnight" API on Forever)

- The Forever generated API docs (`Blizzard_APIDocumentationGenerated` in the synced UI source) carry secret metadata on functions:
  - `SecretArguments = "AllowedWhenUntainted"` ×3677, `"AllowedWhenTainted"` ×177, `"NotAllowed"` ×92
  - `ConditionalSecret = true` ×20, `SecretReturns = true` ×19
  - Affected functions include `UnitHealth`, `UnitHealthPercent`, `UnitCastingDuration`, `GetCurrentEventInfo` (CLEU), `UnitGetTotalAbsorbs`, `UnitInRange`, `GetRaidTargetIndex`.
- The `C_Secrets` namespace exists on Forever: `ShouldCooldownsBeSecret`, `ShouldAurasBeSecret`, `GetSpellCooldownSecrecy`, `GetSpellAuraSecrecy`, `GetSpellCastSecrecy`, `GetPowerTypeSecrecy`, `HasSecretRestrictions`.
- `wow_api_search` returns the function but **does not show the secret flags**. To see them, grep the docs instead:
  `grep -rn -B12 "SecretReturns = true" ~/.cache/hated-wow-mcp/uisource/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/`
- Ketho annotations (vscode-wow-api 0.22.3, `Annotations/Core`) include `SecretPredicateAPIDocumentation.lua` (`C_Secrets`), `issecretvalue`, `scrubsecretvalues`, `DurationObject`, `isCooldownSecret`/`isAuraSecret` fields. They are **retail-based, not Forever-specific**. Use them for types, and use the Forever docs for "does it exist on Forever".

### 3. Game-data sources evaluated

| Source | Forever build? | Machine-readable? | Verdict |
|---|---|---|---|
| **wago.tools DB2 CSV** | **Yes**, 1.60.1.70338 (2026-10-10), plus 70334/70291/70245/70235 | CSV per table, per build | **Primary source** |
| Ketho/BlizzardInterfaceResources `forever` branch | Yes, commit "1.60.1 (70338)" 2026-10-11 | Lua tables: `CVars.lua` (1897 lines, includes `SpellQueueWindow` default 400), `GlobalAPI.lua` (~7077 names), `LuaEnum.lua`, `GlobalStrings/`, `Events.lua` | Fills the MCP globals/cvars gap |
| Gethe/wow-ui-source `forever` | Yes, 70338 | Lua/XML | Already used by the MCP (now synced) |
| warcraft.wiki.gg | `Patch_1.60.1/API_changes` (12.1.5 → 1.60.1 diff); `Module:Wowapi/data/patch/camelot/function` | HTML; curl gets **403 "Blocked - wiki.gg"**, WebFetch works | Human reference only |
| Townlong-Yak FrameXML | `/framexml/forever` returned 404 (via WebFetch) | — | Not usable now |
| talentsforever.com | curl TLS failure (local CA chain) | unverified | Skip. Talent DB2 tables cover it |
| seemeta.com Forever talent calculator | 1.60.1 beta, 51 points | HTML | Cross-check only |
| Wowhead Classic (`/classic/spell=1079`) | Era 1.15 data, **not Forever** | HTML | Do not trust for Forever numbers |

### 4. What the Forever DB2 data looks like (useful for Hekili)

- The tables are retail-shaped (12.x schema): `SpellMisc` (cast/duration/range indexes, school), `SpellPower` (`ManaCost`, `PowerType`, `OrderIndex`), `SpellCooldowns` (`RecoveryTime`, `CategoryRecoveryTime`, `StartRecoveryTime` = GCD), `SpellCategories` (`StartRecoveryCategory` 133 = GCD), `SpellEffect` (`EffectBasePointsF`, `EffectPointsPerResource` = per-combo-point, `EffectAuraPeriod`), `Talent` (`TabID`, `TierID`, `ColumnIndex`, `SpellRank_0..8`, `PrereqTalent_*`), `TalentTab`. Several tables have a `DifficultyID` column; the views use `DifficultyID = 0`.
- Ranks are separate spell IDs, and the rank label is in `Spell.NameSubtext_lang` ("Rank 1"). For the trainer-taught ranks, the class comes from `SkillLineAbility.ClassMask` (bit `1 << (ChrClasses.ID-1)`).
- **Forever-specific content exists.** Two examples: new high spell IDs (`1289141` Rip, 21 s, 15 yd; `1289140` Rake, 6 s) with no skill line, and talents that aren't in vanilla (Druid Balance "Overgrowth", "Natural Shapeshifter" at tier 1). This is why Era data (Wowhead Classic, old Hekili Classic tables) can't be trusted blindly.
- Row counts at 70338: SpellName 31,863, SpellEffect 42,569, SkillLineAbility 7,834, Talent 432, TalentTab 27, ChrClasses 9, ItemSparse 19,248.

## Evidence

**Build listing** (`https://wago.tools/api/builds`, parsed):
```
wow_classic_beta  hits: 1.60.1.70338 (2026-10-10 05:05:05), 1.60.1.70334, 1.60.1.70291, 1.60.1.70245, 1.60.1.70235
wow_cn_beta       hits: 1.60.1.70338 (2026-10-10 04:54:10), ...
```
**CSV endpoint**: `GET https://wago.tools/db2/SpellName/csv?build=1.60.1.70338` → `200 text/csv 835757 bytes` (`ID,Name_lang` …). The HTML page `https://wago.tools/db2/SpellName?build=1.60.1.70338` → 200 HTML. A bogus build `1.60.1.99999` → **400** HTML.

**Fetch run** (`fetch-db2.sh`): all 21 tables `ok` (Spell 2.2 MB, SpellEffect 3.8 MB, ItemSparse 5.3 MB, …). About 53 MB on disk including the CSVs.

**Build run** (`python3 -I build-db.py`): `built ~/.local/share/wow-db2/forever/1.60.1.70338/db2.sqlite (16828 KiB)`, real 1.24 s.

**Sample query, Rip** (`wowdb spell Rip`):
```
id      name rank   base_level cast_ms duration_ms power  cost cooldown_ms gcd_ms gcd_category range_max skill_line   classes
1289141 Rip         0          0       21000                                       0            15
1079    Rip  Rank 1 20         0       12000       energy 30   0           1000   133          5         Feral Combat DRUID
9492    Rip  Rank 2 28         0       12000       energy 30   0           1000   133          5         Feral Combat DRUID
9493    Rip  Rank 3 36         0       12000       energy 30   0           1000   133          5         Feral Combat DRUID
9752    Rip  Rank 4 44         0       12000       energy 30   0           1000   133          5         Feral Combat DRUID
9894    Rip  Rank 5 52         0       12000       energy 30   0           1000   133          5         Feral Combat DRUID
9896    Rip  Rank 6 60         0       12000       energy 30   0           1000   133          5         Feral Combat DRUID
```
**Sample query, Rake** (`wowdb spell Rake`):
```
id      name rank   base_level cast_ms duration_ms power  cost cooldown_ms gcd_ms gcd_category range_max max_stacks skill_line   classes
24331   Rake        0          0       9000                    0           1000   133          5         0
24332   Rake        0          0       9000                    0           1000   133          5         0
27556   Rake        0          0       15000                   0           1000   133          5         100
27638   Rake        0          0       15000                   0           1000   133          5         100
1289140 Rake        0          0       6000                                       0            15
1822    Rake Rank 1 24         0       9000        energy 40   0           1000   133          5                    Feral Combat DRUID
1823    Rake Rank 2 34         0       9000        energy 40   0           1000   133          5                    Feral Combat DRUID
1824    Rake Rank 3 44         0       9000        energy 40   0           1000   133          5                    Feral Combat DRUID
9904    Rake Rank 4 54         0       9000        energy 40   0           1000   133          5                    Feral Combat DRUID
```
(24331/24332/27556/27638 are NPC or item Rake variants with no skill line. Filter with `classes IS NOT NULL` for player ranks.)

**Effects** (`wowdb effects 1079`): `Rip idx0 effect=6 aura=3 (periodic damage) base_points=3 period_ms=2000 per_combo_point=4.4`.

**Talents** (`wowdb talents DRUID | head`): `762 DRUID Balance 0 0 Improved Wrath 16814..16818`, `921 DRUID Balance 0 2 Overgrowth 17245 17247 17248 17249 prereq 761`, …

**MCP syncs run** (both non-destructive, writing to `~/.cache/hated-wow-mcp`):
```
npx -y -p hated-wow-mcp@0.6.1 hated-wow-mcp-sync game-data -- forever
  -> files-index.json {"total":2256962,"interface":176032,"icons":37049}
  -> atlas-index-forever.json [forever, build 1.60.1.70338] {"atlases":20559,"sheets":2807}
npx -y -p hated-wow-mcp@0.6.1 hated-wow-mcp-sync ui-source -- forever
  -> [forever] {"files":4429,"packages":348,"templates":4337,"mixins":3743,"mixinMethods":29752,"globalStrings":345,"cvars":534}
```
URLs: https://wago.tools/api/builds · https://wago.tools/db2/SpellName/csv?build=1.60.1.70338 · https://github.com/Ketho/BlizzardInterfaceResources/tree/forever/Resources · https://github.com/Gethe/wow-ui-source/tree/forever · https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes · https://warcraft.wiki.gg/wiki/Module:Wowapi/data/patch/camelot/function · https://seemeta.com/en/wow-forever/talent-calculator

## Recommendation

**Use one setup: pinned wago.tools DB2 CSVs → local SQLite → the `wowdb` CLI called through Bash.** Don't add another MCP server for now. A one-line Bash call returns ~1 KB of TSV, which is as small as an MCP response, and it adds no server, no tool schemas in context, and nothing to install. Bump the pinned build when Forever patches, and rebuild. Keep the old build directories for diffing ranks and costs between patches.

Layout (already created, outside the repo):
```
~/.local/share/wow-db2/
  bin/fetch-db2.sh      # curl the 21 pinned tables; 403/400 handled with a message; atomic .part -> .csv
  bin/build-db.py       # CSV -> SQLite, indexes, views; atomic swap; updates forever/current.sqlite symlink
  bin/wowdb             # read-only query CLI (TSV, 200-row cap, 160-char cell cap)
  forever/1.60.1.70338/{csv/,db2.sqlite,BUILD}
  forever/current.sqlite -> 1.60.1.70338/db2.sqlite
  forever/bir/{CVars.lua,GlobalAPI.lua,LuaEnum.lua}   # Ketho BIR@forever snapshot for cvars/globals
```

### Exact setup steps (reproduce or update to a new build)

```bash
# 1. Fetch (default build 1.60.1.70338; pass a newer build string to update)
bash ~/.local/share/wow-db2/bin/fetch-db2.sh 1.60.1.70338 forever
# 2. Build SQLite + views
python3 -I ~/.local/share/wow-db2/bin/build-db.py 1.60.1.70338 forever
# 3. Query
python3 -I ~/.local/share/wow-db2/bin/wowdb spell Rip
python3 -I ~/.local/share/wow-db2/bin/wowdb effects 1079
python3 -I ~/.local/share/wow-db2/bin/wowdb talents DRUID
python3 -I ~/.local/share/wow-db2/bin/wowdb "SELECT id,name,rank,cost,duration_ms FROM spell_info WHERE classes='DRUID' AND name LIKE 'Claw%'"
# 4. Refresh MCP extras after a client patch
npx -y -p hated-wow-mcp@0.6.1 hated-wow-mcp-sync ui-source -- forever
npx -y -p hated-wow-mcp@0.6.1 hated-wow-mcp-sync game-data -- forever
#    then reconnect the `wow` MCP server (/mcp) so it reloads its indexes
# 5. CVars/globals the MCP lacks
grep -i spellqueue ~/.local/share/wow-db2/forever/bir/CVars.lua
grep -w UnitAura   ~/.local/share/wow-db2/forever/bir/GlobalAPI.lua
```

Optional user actions (need sudo or new installs; not done):
- `sudo apt install sqlite3` gives the native CLI (`sqlite3 -readonly -box ~/.local/share/wow-db2/forever/current.sqlite`). `wowdb` covers the same need without it.
- To use an MCP server anyway, install `uv` (not present) and add `uvx mcp-server-sqlite --db-path ~/.local/share/wow-db2/forever/current.sqlite`. This is not recommended, because it puts extra tool schemas in context and gives write access.
- Add a one-paragraph pointer to `CLAUDE.local.md` ("Forever spell data: `python3 -I ~/.local/share/wow-db2/bin/wowdb spell <name>`") so future sessions find the tool. I didn't do this because only this file may be edited in the repo.

### Workarounds for `wow` MCP Forever gaps

| Gap | Workaround |
|---|---|
| globals = 0 | `~/.local/share/wow-db2/forever/bir/GlobalAPI.lua` (Ketho BIR@forever); `LuaEnum.lua` for enums |
| cvars = 0 | ui-source sync now indexes 534 UI-used cvars (after an MCP restart); the full registry is in `bir/CVars.lua` (defaults, help text) |
| secret flags not shown by `wow_api_search` | grep `SecretArguments`/`SecretReturns`/`ConditionalSecret` in `~/.cache/hated-wow-mcp/uisource/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/` |
| event payloads | already present for forever (`wow_api_event_search flavor=forever`); `eventNames` "no upstream" only affects the name-only list |
| no spell/talent/item data | wow-db2 SQLite (above) |

## Open questions

1. **wago.tools terms and rate limits.** No published limit was found. 23 sequential requests at 0.5 s spacing went fine. The MCP itself warns that wago.tools 403s some datacentre networks; `fetch-db2.sh` reports this per table and leaves existing CSVs intact.
2. **DB2 vs live server values.** Server-side scripts and spell overrides on Forever (for example combo-point scaling or talent modifiers) aren't in the client DB2. Spot-check key numbers in game with `C_Spell.GetSpellInfo`/tooltips.
3. **Purpose of the new 128914x spell IDs.** These are the Forever Rip/Rake variants: Rip 21 s, Rake 6 s, both 15 yd, with no cost and no skill line. They may be NPC, pet or test spells, or Forever mechanics. Worth checking in game.
4. **Talent mapping.** `Talent.ClassID` and `SpecID` weren't used; the class comes from `TalentTab.ClassMask`. Check that every tab maps to exactly one class (the null-class count was 0).
5. **Power type IDs.** The `power_type` mapping is retail-style. Energy (3) and mana (0) are verified on the sample spells; the others are assumed.

## Confidence

- **High:** wago.tools serves exact-build Forever DB2 CSVs; the prototype works end to end; the MCP sync results and the gap workarounds.
- **Medium:** the column semantics in the views (retail 12.x schema meaning applied to Forever), the class attribution via `SkillLineAbility`, and whether the DB2 numbers match live server behaviour.
- **Low:** availability of third-party sites (talentsforever.com unreachable over TLS here; Townlong-Yak Forever 404).
